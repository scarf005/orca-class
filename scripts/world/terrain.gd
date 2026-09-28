class_name Terrain
extends Node3D
## Streams flat-shaded ground chunks around the camera's course distance.

const CHUNK_LENGTH := 40.0
const STEP_D := 2.5
const HALF_WIDTH := 190.0
const AHEAD := 320.0
const BEHIND := 80.0

## Lateral sample positions: fine near the road, coarse on the far hills.
static var _columns := _make_columns()

var _chunks := {}
var _pending := {} ## index -> WorkerThreadPool task id.
var _built := {} ## index -> LowPoly builder finished on a worker thread.
var _mutex := Mutex.new()
var _water: MeshInstance3D


static func _make_columns() -> PackedFloat32Array:
	var columns := PackedFloat32Array()
	var u := -HALF_WIDTH
	while u < HALF_WIDTH + 0.01:
		columns.append(u)
		u += 2.5 if absf(u) < 60.0 else (5.0 if absf(u) < 110.0 else 10.0)
	return columns


func _ready() -> void:
	_water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 1200)
	var material := StandardMaterial3D.new()
	material.albedo_color = Palette.TEAL
	material.roughness = 0.2
	material.metallic_specular = 0.8
	plane.material = material
	_water.mesh = plane
	_water.position = Vector3(0, Course.WATER_LEVEL, -2200)
	add_child(_water)


## Keeps chunks covering [d - BEHIND, d + AHEAD]. Missing chunks are built on worker threads;
## `wait` builds them immediately instead (used while loading).
func stream(d: float, wait := false) -> void:
	var first := int(floorf((d - BEHIND) / CHUNK_LENGTH))
	var last := int(floorf((d + AHEAD) / CHUNK_LENGTH))
	for index in range(first, last + 1):
		if _chunks.has(index) or _pending.has(index):
			continue
		if wait:
			_attach(index, _build_chunk(index))
		else:
			_pending[index] = WorkerThreadPool.add_task(_build_async.bind(index))
	_mutex.lock()
	var finished := _built.duplicate()
	_built.clear()
	_mutex.unlock()
	for index: int in finished:
		WorkerThreadPool.wait_for_task_completion(_pending[index])
		_pending.erase(index)
		if index >= first - 1 and index <= last + 1 and not _chunks.has(index):
			_attach(index, finished[index])
	for index: int in _chunks.keys():
		if index < first - 1 or index > last + 1:
			_chunks[index].queue_free()
			_chunks.erase(index)


func _exit_tree() -> void:
	for task: int in _pending.values():
		WorkerThreadPool.wait_for_task_completion(task)


func _build_async(index: int) -> void:
	var builder := _build_chunk(index)
	_mutex.lock()
	_built[index] = builder
	_mutex.unlock()


func _attach(index: int, builder: LowPoly) -> void:
	var chunk := MeshInstance3D.new()
	chunk.mesh = builder.mesh()
	chunk.name = "Chunk%d" % index
	add_child(chunk)
	_chunks[index] = chunk


## Pure geometry work, safe on a worker thread.
func _build_chunk(index: int) -> LowPoly:
	var d0 := index * CHUNK_LENGTH
	var rows := int(CHUNK_LENGTH / STEP_D)
	var grid: Array[PackedVector3Array] = []
	for r in rows + 1:
		var d := d0 + r * STEP_D
		var row := PackedVector3Array()
		for u in _columns:
			row.append(Course.ground_at(d, u))
		grid.append(row)
	var builder := LowPoly.new()
	for r in rows:
		for c in _columns.size() - 1:
			var a := grid[r][c]
			var b := grid[r][c + 1]
			var e := grid[r + 1][c]
			var f := grid[r + 1][c + 1]
			# Alternate the diagonal so slopes read as facets rather than stripes.
			if (r + c) % 2 == 0:
				_face(builder, a, b, f)
				_face(builder, a, f, e)
			else:
				_face(builder, a, b, e)
				_face(builder, b, f, e)
	return builder


func _face(builder: LowPoly, a: Vector3, b: Vector3, c: Vector3) -> void:
	var center := (a + b + c) / 3.0
	var course := Course.to_course(center)
	var normal := (b - a).cross(c - a).normalized()
	if normal.y < 0.0:
		normal = -normal
	var slope := Vector2(normal.x, normal.z).length() / maxf(normal.y, 0.01)
	builder.tri(a, b, c, Course.ground_color(course.x, course.y, center.y, slope), Vector3.UP)
