class_name ChaseCamera
extends Camera3D
## Follows the rail from behind the tank; in the arena it locks on, keeping the boss framed.
## Trauma-based shake and recoil kick are layered on top of the smoothed pose.

const RAIL_BACK := 17.0
const RAIL_HEIGHT := 12.5
const RAIL_LOOK_AHEAD := 30.0
const ARENA_BACK := 22.0
const ARENA_HEIGHT := 16.0
const FOV := 70.0
const MAX_FOV := 90.0 ## Widest the view opens to keep a framed boss and the tank both in sight.
const FRAME_TOP_MARGIN := 10.0 ## Degrees a framed boss keeps below the top edge.
const FRAME_BOTTOM_MARGIN := 15.0 ## Degrees the tank keeps above the bottom edge when the view tilts up for one.
const SOLID_OVERHEAD := ["tunnel_roof", "tunnel_wall"] ## The camera rides inside these: they never fade.

var trauma := 0.0
var _kick := 0.0
var _time := 0.0
var _eye := Vector3.ZERO
var _look := Vector3.ZERO
var _initialized := false
var _watch: Node3D ## Set when the boss goes down: the camera stays on it (and where it fell).
var _watch_point := Vector3.INF


func _ready() -> void:
	fov = FOV
	near = 0.3
	far = 900.0
	# Follow after the tank has moved this frame.
	process_priority = 100


func _process(delta: float) -> void:
	follow(delta)


const MAX_TRAUMA := 0.55 ## Shake never goes past this, however many things blow up at once.


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount * 0.7, 0.0, MAX_TRAUMA)


## Keeps the camera on `target` from now on, and on the spot it was last seen once it is gone.
func watch(target: Node3D) -> void:
	_watch = target
	_watch_point = target.global_position


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
	var view_fov := FOV
	if world.rail.mode == Rail.Mode.ARENA:
		var focus := player.global_position
		if is_instance_valid(_watch):
			_watch_point = _watch.global_position
		if _watch_point != Vector3.INF:
			focus = _watch_point
		elif is_instance_valid(world.boss):
			focus = world.boss.global_position
		var away := player.global_position - focus
		away.y = 0.0
		if away.length() < 1.0:
			away = player.global_basis.z
		away = away.normalized()
		var zoom := float(world.boss.get_meta("zoom", 1.0)) if is_instance_valid(world.boss) else 1.0 # A giant boss asks the camera to back off.
		eye = player.global_position + away * ARENA_BACK * zoom + Vector3.UP * ARENA_HEIGHT * zoom
		look = player.global_position.lerp(focus, 1.0 if _watch_point != Vector3.INF else 0.3) + Vector3.UP * 1.0
	else:
		var d := world.rail.d
		var u := player.course_u
		var camera_u := Course.stage.camera_u(d, u)
		eye = Course.to_world(d - RAIL_BACK, camera_u)
		eye.y = maxf(Course.height(d - RAIL_BACK, camera_u), player.global_position.y - 1.0) + RAIL_HEIGHT
		look = Course.to_world(d + RAIL_LOOK_AHEAD, u * 0.85, player.global_position.y - 1.0)
		# A boss fought along the road (the flying wing) asks to be kept in frame while it is ahead.
		if is_instance_valid(world.boss) and world.boss.has_meta("frame") and Course.to_course(world.boss.global_position).x > d:
			# Turn the view about the eye, keeping the look point's height and distance so the tank keeps its place.
			var boss := world.boss.global_position
			var flat := Vector2(look.x - eye.x, look.z - eye.z)
			var turned := flat.rotated(flat.angle_to(Vector2(boss.x - eye.x, boss.z - eye.z)) * float(world.boss.get_meta("frame")))
			look = Vector3(eye.x + turned.x, look.y, eye.z + turned.y)
			# High on a glide it would leave the top edge: widen the view and tilt up until its hull clears it, never
			# pushing the tank down behind the bottom panels.
			var level := turned.length()
			var pitch := atan2(look.y - eye.y, level)
			var tank := player.hit_center()
			var above := atan2(boss.y - eye.y, Vector2(boss.x - eye.x, boss.z - eye.z).length()) + deg_to_rad(FRAME_TOP_MARGIN)
			var below := atan2(tank.y - eye.y, Vector2(tank.x - eye.x, tank.z - eye.z).length()) - deg_to_rad(FRAME_BOTTOM_MARGIN)
			view_fov = clampf(rad_to_deg(above - below), FOV, MAX_FOV)
			var half := deg_to_rad(view_fov * 0.5)
			look.y = eye.y + tan(clampf(above - half, pitch, maxf(pitch, below + half))) * level
		roll = clampf(-player.lateral_velocity * 0.006, -0.1, 0.1) # A 74 m/s dash would otherwise bank the view 25 degrees.
	var k := 1.0 - exp(-9.0 * delta)
	if not _initialized:
		fov = view_fov
		_eye = eye
		_look = look
		_initialized = true
	fov = lerpf(fov, view_fov, k)
	_eye = _eye.lerp(eye, k)
	_look = _look.lerp(look, k)
	global_position = world.director.scenery.camera_position(player.hit_center(), _eye) if world.director else _eye
	look_at(_look, Vector3.UP)
	_fade_occluders(player.hit_center())
	rotate_object_local(Vector3.FORWARD, roll)
	_apply_shake(delta)


var _faded: Array[Prop] = []
var _faded_enemies: Array[Enemy] = []


## Props and enemies between the camera and the tank turn see-through (the dither pass renders it as a screen door).
func _fade_occluders(target: Vector3) -> void:
	var blocking: Array[Enemy] = []
	for node in World.current.enemies:
		var enemy := node as Enemy
		if enemy != null and not enemy.dead and enemy.hit_test(global_position, target) >= 0.0:
			blocking.append(enemy)
	for enemy in _faded_enemies:
		if is_instance_valid(enemy) and enemy not in blocking:
			enemy.set_see_through(false)
	for enemy in blocking:
		enemy.set_see_through(true)
	_faded_enemies = blocking
	var still: Array[Prop] = []
	for prop: Prop in World.current.props.near(global_position, target, 8.0):
		if prop.dead or prop.kind in SOLID_OVERHEAD:
			continue
		var base := prop.global_position
		var reach := maxf(prop.footprint, prop.spread)
		var passing := Geometry3D.get_closest_point_to_segment(Vector3(base.x, target.y, base.z), global_position, target) # The sight line's height where it passes the prop.
		var t := Entity.segment_sphere(global_position, target, Vector3(base.x, clampf(passing.y, base.y, base.y + prop.height), base.z), reach + 1.0)
		var beside := Vector2(base.x - global_position.x, base.z - global_position.z).length() < reach + 6.0
		if t >= 0.0 or beside:
			still.append(prop)
	for prop in _faded:
		if is_instance_valid(prop) and prop not in still:
			prop.set_see_through(false)
	for prop in still:
		prop.set_see_through(true)
	_faded = still


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
