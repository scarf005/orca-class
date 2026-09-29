class_name FlyerTrail
extends MeshInstance3D
## A thin ribbon behind a flying enemy that fades over about 1.3 s, so its path reads at a glance. The
## ribbon is one draw call: the vertex shader builds it from a ring of the flyer's recent positions.
## When the flyer dies (or leaves) the trail stays and fades out on its own, then frees itself.

const POINTS := 22 ## Keep in step with the shader.
const SAMPLE := 0.06 ## Seconds between recorded points.
const TRAIL_TIME := (POINTS - 1) * SAMPLE ## Age of the oldest point.
const COLOR := Palette.BLUSH ## Muted hostile pink: never the orange of a shot.

static var _shader := preload("res://shaders/trail.gdshader")
static var _ribbon: ArrayMesh

var source: Node3D
var _material := ShaderMaterial.new()
var _points: Array[PackedVector4Array] = [PackedVector4Array(), PackedVector4Array()]
var _live := 0 ## The buffer the material holds; the other is free to write, so nothing is copied.
var _clock := 0.0
var _sample_timer := SAMPLE
var _newest := 0.0 ## Time of the last position recorded.


## Starts a trail behind `enemy` in the world; it outlives the enemy.
static func follow(enemy: Enemy) -> FlyerTrail:
	var trail := FlyerTrail.new()
	trail.source = enemy
	trail.setup(enemy.global_position, clampf(enemy.radius * 0.25, 0.25, 1.0))
	World.current.add_child(trail)
	return trail


func setup(start: Vector3, width: float) -> void:
	if _ribbon == null:
		_ribbon = _build_ribbon()
	mesh = _ribbon
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3.ONE * -20000.0, Vector3.ONE * 40000.0) # The shader moves the vertices.
	_material.shader = _shader
	_material.set_shader_parameter("width", width)
	_material.set_shader_parameter("trail_time", TRAIL_TIME)
	_material.set_shader_parameter("tint", COLOR)
	material_override = _material
	for buffer in _points:
		buffer.resize(POINTS)
		buffer.fill(Vector4(start.x, start.y, start.z, 0.0))
	_material.set_shader_parameter("points", _points[_live])


static func _build_ribbon() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in POINTS:
		vertices.append(Vector3(-1, i, 0))
		vertices.append(Vector3(1, i, 0))
	for i in POINTS - 1:
		var a := i * 2
		indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var ribbon := ArrayMesh.new()
	ribbon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return ribbon


func _following() -> bool:
	return is_instance_valid(source) and not (source is Entity and (source as Entity).dead)


func _process(delta: float) -> void:
	_clock += delta
	if _following():
		_record(delta)
	elif _clock - _newest >= TRAIL_TIME:
		queue_free()
		return
	_material.set_shader_parameter("now", _clock)


## Writes the next frame's ring into the free buffer: the newest point follows the flyer, and every
## SAMPLE the older ones move down one place.
func _record(delta: float) -> void:
	var from := _points[_live]
	var to := _points[1 - _live]
	_sample_timer -= delta
	var offset := 0
	if _sample_timer <= 0.0:
		_sample_timer = SAMPLE
		offset = 1
	for i in range(1, POINTS):
		to[i] = from[i - offset]
	var at := source.global_position
	to[0] = Vector4(at.x, at.y, at.z, _clock)
	_newest = _clock
	_live = 1 - _live
	_material.set_shader_parameter("points", to)


## Seconds since the oldest point in the ribbon was recorded.
func oldest_age() -> float:
	return _clock - _points[_live][POINTS - 1].w


## Length of the ribbon in meters.
func length() -> float:
	var total := 0.0
	var buffer := _points[_live]
	for i in POINTS - 1:
		total += Vector3(buffer[i].x, buffer[i].y, buffer[i].z).distance_to(Vector3(buffer[i + 1].x, buffer[i + 1].y, buffer[i + 1].z))
	return total
