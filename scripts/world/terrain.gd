class_name Terrain
extends Node3D
## Streams flat-shaded ground chunks around the camera's course distance.

const CHUNK_LENGTH := 40.0
const STEP_D := 2.5
const HALF_WIDTH := 190.0
const AHEAD := 320.0
const BEHIND := 80.0
const STREAM_BUDGET_USEC := 1000
const ROWS := int(CHUNK_LENGTH / STEP_D)
const BEHIND_BENDS := 480.0 ## How far back chunks may stay loaded while a bend swings them into view.

## Lateral sample positions: fine near the road, coarse on the far hills.
static var _columns := _make_columns()

class ChunkBuild:
	var index: int
	var cursor := 0
	var grid: Array[Vector3] = []
	var builder := LowPoly.new()

	func _init(chunk_index: int) -> void:
		index = chunk_index


var threaded := OS.has_feature("threads")
var _serial := {} ## index -> ChunkBuild, resumed within the frame budget without worker threads.
var _chunks := {}
var _pending := {} ## index -> WorkerThreadPool task id.
var _built := {} ## index -> LowPoly builder finished on a worker thread.
var _mutex := Mutex.new()
var _waters: Array[MeshInstance3D] = []


static func _make_columns() -> PackedFloat32Array:
	var columns := PackedFloat32Array()
	var u := -HALF_WIDTH
	while u < HALF_WIDTH + 0.01:
		columns.append(u)
		u += 2.5 if absf(u) < 60.0 else (5.0 if absf(u) < 110.0 else 10.0)
	return columns


func _ready() -> void:
	var material := water_material()
	for mesh in Course.stage.water_meshes():
		var water := MeshInstance3D.new()
		water.mesh = mesh
		water.material_override = material
		add_child(water)
		_waters.append(water)
	_lift_water()


## Water surfaces can move (the floodgate's basin drains), so each mesh follows the stage's level.
func _process(_delta: float) -> void:
	_lift_water()


func _lift_water() -> void:
	for i in _waters.size():
		_waters[i].position.y = Course.stage.water_level(i)


## The water's look, shared by every water surface. `vertex_colors` lets a surface vary its shades.
static func water_material(vertex_colors := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE if vertex_colors else Palette.TEAL
	material.vertex_color_use_as_albedo = vertex_colors
	material.vertex_color_is_srgb = vertex_colors
	material.roughness = 0.2
	material.metallic_specular = 0.8
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## Keeps the same bend-aware window on every platform. Loading waits for complete geometry;
## play gives generation/attachment a time budget. Web exports without threads resume a chunk
## across frames instead of running the whole worker callable on the main thread.
func stream(d: float, wait := false) -> void:
	var deadline := Time.get_ticks_usec() + STREAM_BUDGET_USEC
	var last := int(floorf((d + AHEAD) / CHUNK_LENGTH))
	var wanted := {}
	for index in range(int(floorf((d - BEHIND_BENDS) / CHUNK_LENGTH)), last + 1):
		if (index + 1) * CHUNK_LENGTH >= d - BEHIND or _in_front(index, d):
			wanted[index] = true
	for index: int in _serial.keys():
		if not wanted.has(index):
			_serial.erase(index)
	for index: int in wanted:
		if _chunks.has(index):
			continue
		if wait:
			if _pending.has(index):
				WorkerThreadPool.wait_for_task_completion(_pending[index])
				_pending.erase(index)
				_mutex.lock()
				var builder: LowPoly = _built[index]
				_built.erase(index)
				_mutex.unlock()
				_attach(index, builder)
			else:
				var job: ChunkBuild = _serial.get(index, ChunkBuild.new(index))
				_advance(job)
				_attach(index, job.builder)
				_serial.erase(index)
		elif not _pending.has(index) and not _serial.has(index):
			if threaded:
				_pending[index] = WorkerThreadPool.add_task(_build_async.bind(index))
			else:
				_serial[index] = ChunkBuild.new(index)
	for index: int in _serial.keys():
		if Time.get_ticks_usec() >= deadline:
			break
		var job: ChunkBuild = _serial[index]
		if _advance(job, deadline):
			_attach(index, job.builder)
			_serial.erase(index)
	_mutex.lock()
	var finished := _built.keys()
	_mutex.unlock()
	for index: int in finished:
		if not wait and Time.get_ticks_usec() >= deadline:
			break
		WorkerThreadPool.wait_for_task_completion(_pending[index])
		_pending.erase(index)
		_mutex.lock()
		var builder: LowPoly = _built[index]
		_built.erase(index)
		_mutex.unlock()
		if wanted.has(index) and not _chunks.has(index):
			_attach(index, builder)
	for index: int in _chunks.keys():
		if not wanted.has(index):
			_chunks[index].queue_free()
			_chunks.erase(index)


## Whether any corner of chunk `index` lies ahead of the rail's position at d.
static func _in_front(index: int, d: float) -> bool:
	var at := Course.to_world(d, 0.0)
	var forward := Course.forward(d)
	for cd in [index * CHUNK_LENGTH, (index + 1) * CHUNK_LENGTH]:
		for u in [-HALF_WIDTH, HALF_WIDTH]:
			if (Course.to_world(cd, u) - at).dot(forward) > -20.0:
				return true
	return false


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


## The synchronous/worker path uses exactly the same cells and ordering as the budgeted path.
func _build_chunk(index: int) -> LowPoly:
	var job := ChunkBuild.new(index)
	_advance(job)
	return job.builder


func _advance(job: ChunkBuild, deadline := 0) -> bool:
	var columns := _columns.size()
	var vertices := (ROWS + 1) * columns
	var total := vertices + ROWS * (columns - 1)
	while job.cursor < total and (deadline == 0 or Time.get_ticks_usec() < deadline):
		if job.cursor < vertices:
			var r := job.cursor / columns
			job.grid.append(Course.ground_at(job.index * CHUNK_LENGTH + r * STEP_D, _columns[job.cursor % columns]))
		else:
			var cell := job.cursor - vertices
			var r := cell / (columns - 1)
			var c := cell % (columns - 1)
			var a := job.grid[r * columns + c]
			var b := job.grid[r * columns + c + 1]
			var e := job.grid[(r + 1) * columns + c]
			var f := job.grid[(r + 1) * columns + c + 1]
			# Alternate the diagonal so slopes read as facets rather than stripes.
			if (r + c) % 2 == 0:
				_face(job.builder, a, b, f)
				_face(job.builder, a, f, e)
			else:
				_face(job.builder, a, b, e)
				_face(job.builder, b, f, e)
		job.cursor += 1
	return job.cursor == total


func _face(builder: LowPoly, a: Vector3, b: Vector3, c: Vector3) -> void:
	var center := (a + b + c) / 3.0
	var course := Course.to_course(center)
	var normal := (b - a).cross(c - a).normalized()
	if normal.y < 0.0:
		normal = -normal
	var slope := Vector2(normal.x, normal.z).length() / maxf(normal.y, 0.01)
	builder.tri(a, b, c, Course.ground_color(course.x, course.y, center.y, slope), Vector3.UP)
