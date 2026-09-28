class_name ChaseCamera
extends Camera3D
## Follows the rail from behind the tank; in the arena it locks on, keeping the boss framed.
## Trauma-based shake and recoil kick are layered on top of the smoothed pose.

const RAIL_BACK := 11.0
const RAIL_HEIGHT := 6.2

var trauma := 0.0
var _kick := 0.0
var _time := 0.0
var _eye := Vector3.ZERO
var _look := Vector3.ZERO
var _initialized := false


func _ready() -> void:
	fov = 64.0
	near = 0.3
	far = 900.0
	# Follow after the tank has moved this frame.
	process_priority = 100


func _process(delta: float) -> void:
	follow(delta)


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Pitches the view up briefly, e.g. on cannon recoil.
func kick(amount: float) -> void:
	_kick = minf(_kick + amount, 0.12)


func follow(delta: float) -> void:
	var world := World.current
	var player := world.player
	if player == null:
		return
	var eye: Vector3
	var look: Vector3
	var roll := 0.0
	if world.rail.mode == Rail.Mode.ARENA:
		var focus := player.global_position
		if is_instance_valid(world.boss):
			focus = world.boss.global_position
		var away := player.global_position - focus
		away.y = 0.0
		if away.length() < 1.0:
			away = player.global_basis.z
		away = away.normalized()
		eye = player.global_position + away * 14.0 + Vector3.UP * 7.5
		look = player.global_position.lerp(focus, 0.3) + Vector3.UP * 2.5
	else:
		var d := world.rail.d
		var u := player.course_u
		eye = Course.to_world(d - RAIL_BACK, u * 0.55)
		eye.y = maxf(Course.height(d - RAIL_BACK, u * 0.55), player.global_position.y - 1.0) + RAIL_HEIGHT
		look = Course.to_world(d + 24.0, u * 0.7, player.global_position.y + 1.2)
		roll = -player.lateral_velocity * 0.006
	var k := 1.0 - exp(-9.0 * delta)
	if not _initialized:
		_eye = eye
		_look = look
		_initialized = true
	_eye = _eye.lerp(eye, k)
	_look = _look.lerp(look, k)
	global_position = _eye
	look_at(_look, Vector3.UP)
	rotate_object_local(Vector3.FORWARD, roll)
	_apply_shake(delta)


func snap() -> void:
	_initialized = false


func _apply_shake(delta: float) -> void:
	_time += delta
	var amount := trauma * trauma
	trauma = maxf(0.0, trauma - delta * 1.6)
	_kick = move_toward(_kick, 0.0, delta * 0.5)
	rotate_object_local(Vector3.RIGHT, _kick)
	if amount <= 0.0:
		return
	var t := _time * 38.0
	rotate_object_local(Vector3.RIGHT, amount * 0.05 * sin(t * 1.1))
	rotate_object_local(Vector3.UP, amount * 0.05 * sin(t * 0.9 + 1.7))
	rotate_object_local(Vector3.FORWARD, amount * 0.04 * sin(t * 1.3 + 3.1))
	global_position += global_basis * Vector3(sin(t * 1.7), sin(t * 2.1 + 0.5), 0.0) * amount * 0.35
