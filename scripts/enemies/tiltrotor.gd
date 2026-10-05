class_name Tiltrotor
extends Enemy
## Tiltrotor gunship. It flies in fast with its rotors forward, tilts them up to hover beside the rail,
## drops a squad out of the rear ramp, rakes the road with its door gun (a laser line on the ground
## shows where, then the beam sweeps across it) and tilts forward to leave. A nacelle shot off makes it
## spin down and crash.
## `squad`: "drones" (2-3 FPV drones), "crawlers" (a fungal pack roped down) or "" for either.

enum State { APPROACH, HOVER, DEPART, CRASH }

const CRUISE_SPEED := 46.0
const DEPART_SPEED := 60.0
const HOVER_AHEAD := 36.0 ## Meters ahead of the tank it hangs, level with the rail.
const HEIGHT := 10.0
const LANE := 16.0 ## It hovers this far to the side of the road.
const TILT_TIME := 1.6 ## Seconds the nacelles take to swing between flight and hover.
const DROP_AT := 1.6 ## Hover seconds before the squad leaves the ramp.
const SWEEP_AT := 3.4 ## Hover seconds before the door gun starts to sight its line.
const SWEEP_WIND := 1.2 ## Seconds the line shows before the gun fires.
const SWEEP_TIME := 1.8 ## Seconds the beam takes to cross the line.
const SWEEP_HALF := 9.0 ## Half the line's length across the road.
const LEAVE_AT := 8.4 ## Hover seconds before it tilts forward and goes.
const GUN_SLEW := 4.0
const GUN_SPREAD := 0.012
const NACELLE_X := 5.9
const NACELLE_HP := 60.0

var squad := ""
var state := State.APPROACH
var _lane := LANE
var _height := HEIGHT
var _hover := 0.0
var _tilt := 0.0 ## 0 rotors forward (airplane), 1 rotors up (hover).
var _ramp := 0.0 ## 0 closed, 1 open.
var _dropped := false
var _depart_speed := 0.0
var _hard := false
var _nacelles: Array[Node3D] = [] ## Pivots at the wing tips, left then right.
var _rotors: Array[Node3D] = []
var _spin: Array[float] = [1.0, 1.0] ## Rotor speed share; a lost nacelle's falls to 0.
var _nacelle_hp: Array[float] = [NACELLE_HP, NACELLE_HP]
var _lost := 0.0 ## Side (-1 left, 1 right) of the nacelle that was shot off.
var _fall := 0.0
var _ramp_hinge := Node3D.new()
var _gun := Node3D.new()
var _muzzle := Node3D.new()
var _wind := 0.0 ## Seconds of the sweep's telegraph left.
var _sweep := 0.0 ## Seconds of the sweep left.
var _sweep_done := false
var _line_a := Vector3.ZERO
var _line_b := Vector3.ZERO
var _shot_timer := 0.0


func _init() -> void:
	super()
	max_hp = 2600.0
	armor = 8.0 ## Millimetres: the 8 mm coax glances off; 15 and 20 mm get in.
	hp = max_hp
	radius = 3.2
	center_height = 0.4
	flying = true
	evasive = true
	trails = true
	can_stagger = false
	stabbable = false
	score = 900
	wreck_on_death = true
	weakness = {Hit.Kind.FRAGMENT: 1.5, Hit.Kind.BLAST: 1.3}
	debris = [Fx.Debris.ARMOR, Fx.Debris.METAL, Fx.Debris.GLASS]


func build() -> void:
	_hard = Game.difficulty == Game.Difficulty.HARD
	var slot: Vector3 = get_meta("slot", Vector3(LANE, HEIGHT, 150.0))
	_lane = slot.x if absf(slot.x) > 1.0 else LANE
	_height = maxf(slot.y, 8.0)
	_add_mesh(model, ActorMeshes.mesh("tiltrotor", "body"))
	_ramp_hinge.position = Vector3(0, -1.0, 5.5)
	model.add_child(_ramp_hinge)
	_add_mesh(_ramp_hinge, ActorMeshes.mesh("tiltrotor", "ramp"))
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * NACELLE_X, 1.8, 0.0)
		model.add_child(pivot)
		_add_mesh(pivot, ActorMeshes.mesh("tiltrotor", "nacelle"))
		var rotor := Node3D.new()
		rotor.position = Vector3(0, 0, -2.0)
		pivot.add_child(rotor)
		_add_mesh(rotor, ActorMeshes.mesh("tiltrotor", "blades"))
		_nacelles.append(pivot)
		_rotors.append(rotor)
	# Door gun on the ramp's lip; it rests pointing out the back.
	_gun.position = Vector3(0, 0.3, 4.4)
	model.add_child(_gun)
	_add_mesh(_gun, ActorMeshes.mesh("tiltrotor", "gun"))
	_muzzle.position = Vector3(0, 0, -1.8)
	_gun.add_child(_muzzle)
	_gun.basis = Basis.looking_at(Vector3.BACK)
	pop_parts = [_nacelles[0], _nacelles[1]]
	# Enter far ahead and beside the road, nose to the tank, rotors forward.
	var d := World.current.rail.d + slot.z
	global_position = Course.to_world(d, _lane, Course.height(d, _lane) + _height + 6.0)
	model.rotation.y = _heading(-Course.forward(d))
	_apply_tilt()
	Sfx.loop("rotor", self, -3.0)


func _add_mesh(parent: Node3D, mesh: Mesh) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	parent.add_child(instance)


## Model yaw that makes it face the world direction `dir`.
static func _heading(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	var best := -1.0
	for sphere: Vector4 in [Vector4(0, -0.2, -3.2, 1.3), Vector4(0, 0, -0.6, 1.6), Vector4(0, 0, 2.2, 1.6), Vector4(0, 0.2, 4.8, 1.2), Vector4(0, 1.8, 0, 1.2), Vector4(-NACELLE_X, 1.8, -0.4, 1.5), Vector4(NACELLE_X, 1.8, -0.4, 1.5)]:
		var t := Entity.segment_sphere(from, to, model.to_global(Vector3(sphere.x, sphere.y, sphere.z)), sphere.w + extra_radius)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


## Which nacelle a world point is nearest, as an index into `_nacelles` (0 left, 1 right), or -1 on the fuselage.
func nacelle_at(point: Vector3) -> int:
	var local := model.to_local(point)
	return -1 if absf(local.x) < NACELLE_X - 1.7 else (0 if local.x < 0.0 else 1)


func on_damaged(hit: Hit, amount: float) -> void:
	super(hit, amount)
	var i := nacelle_at(hit.position)
	if i < 0 or state == State.CRASH or _nacelle_hp[i] <= 0.0:
		return
	_nacelle_hp[i] -= amount
	if _nacelle_hp[i] > 0.0:
		return
	var world := World.current
	state = State.CRASH
	_lost = -1.0 if i == 0 else 1.0
	killing_hit = hit.copy()
	velocity = Vector3.ZERO
	world.fx.explosion(_nacelles[i].global_position, 1.8)
	world.fx.burn(_nacelles[i].global_position, 6.0, 1.0)
	world.award(200, global_position, false)
	_wind = 0.0
	_sweep = 0.0
	Sfx.play("blast_small", global_position)


func behave(delta: float) -> void:
	for i in 2:
		_spin[i] = move_toward(_spin[i], 0.0 if state == State.CRASH and (i == 0) == (_lost < 0.0) else 1.0, delta * 0.8)
		_rotors[i].rotation.z += delta * 36.0 * _spin[i] * (1.0 if i == 0 else -1.0)
	var world := World.current
	var tank := player()
	if state == State.CRASH:
		_crash(delta)
		return
	if tank == null or tank.dead:
		return
	var course := Course.to_course(global_position)
	var target_x := world.rail.d + tank.course_offset + HOVER_AHEAD
	var remaining := course.x - target_x
	var tilt_goal := 0.0
	var heading := -Course.forward(course.x)
	match state:
		State.APPROACH:
			tilt_goal = 1.0 if remaining < 80.0 else 0.0
			course.x += (world.rail.speed - clampf(remaining * 1.1, -20.0, CRUISE_SPEED)) * delta
			if remaining < 6.0 and _tilt > 0.97:
				state = State.HOVER
		State.HOVER:
			tilt_goal = 1.0
			_hover += delta
			course.x += (world.rail.speed + clampf(-remaining * 1.1, -20.0, 20.0)) * delta
			heading = global_position - tank.global_position # Tail to the tank: the ramp and the gun face it.
			heading.y = 0.0
			_hover_tasks(delta, tank)
			if _hover > LEAVE_AT and _wind <= 0.0 and _sweep <= 0.0:
				state = State.DEPART
		State.DEPART:
			_depart_speed = move_toward(_depart_speed, DEPART_SPEED if _tilt < 0.3 else world.rail.speed, 26.0 * delta)
			course.x += _depart_speed * delta
			heading = Course.forward(course.x)
			if course.x > world.rail.d + 300.0 or age > 90.0:
				despawn()
				return
	_tilt = move_toward(_tilt, tilt_goal if state != State.DEPART else 0.0, delta / TILT_TIME)
	_apply_tilt()
	var swing := signf(_lane - course.y) * minf(absf(_lane - course.y), 10.0)
	course.y = lerpf(course.y, _lane, delta * 1.2)
	global_position = Course.to_world(course.x, course.y, global_position.y)
	var altitude := Course.height_at(global_position) + _height + sin(age * 1.3) * 0.7
	global_position.y = lerpf(global_position.y, altitude, delta * 1.5)
	model.rotation.y = lerp_angle(model.rotation.y, _heading(heading), delta * (2.2 if state == State.HOVER else 1.6))
	model.rotation.z = lerpf(model.rotation.z, clampf(swing * 0.02, -0.2, 0.2) + sin(age * 0.9) * 0.04, delta * 2.0)
	model.rotation.x = lerpf(model.rotation.x, 0.08 * (1.0 - _tilt), delta * 2.0)
	_ramp = move_toward(_ramp, 1.0 if state == State.HOVER and _hover > 0.3 else 0.0, delta * 1.6)
	_ramp_hinge.rotation.x = lerpf(-0.5, 0.45, _ramp)


## Hangs in the hover with the ramp down without running any AI (debug room).
func pose_idle() -> void:
	_tilt = 1.0
	_apply_tilt()
	model.rotation.y = 0.0
	_ramp_hinge.rotation.x = 0.45


func _apply_tilt() -> void:
	for pivot in _nacelles:
		pivot.rotation.x = _tilt * PI * 0.5


## The squad leaves the ramp, then the door gun sights its line, fires across it, and goes quiet.
func _hover_tasks(delta: float, tank: Tank) -> void:
	var world := World.current
	if not _dropped and _hover > DROP_AT:
		_dropped = true
		_drop_squad()
	if _hover > SWEEP_AT and not _sweep_done and _wind <= 0.0 and _sweep <= 0.0 and _ramp > 0.9:
		_sweep_done = true
		_wind = SWEEP_WIND * Game.telegraph_scale()
		_line_across(tank)
		Sfx.play("warn", global_position, -2.0, 0.8)
	var aim := _line_a
	if _wind > 0.0:
		_wind -= delta
		world.fx.beam(_muzzle.global_position, _line_a, Palette.CORAL, 0.04, 0.05)
		if _wind <= 0.0:
			if _hard:
				_drop_squad()
			_sweep = SWEEP_TIME
			_shot_timer = 0.0
	elif _sweep > 0.0:
		_sweep -= delta
		aim = _sweep_point()
		world.fx.beam(_muzzle.global_position, aim, Palette.HOT, 0.09, 0.05)
		_shot_timer -= delta
		if _shot_timer <= 0.0:
			_shot_timer = 0.07
			_fire(aim)
	if _wind > 0.0 or _sweep > 0.0:
		world.fx.beam(_line_a, _line_b, Palette.CORAL if _sweep <= 0.0 else Palette.HOT, 0.3, 0.05)
		aim_barrel(_gun, aim, GUN_SLEW, delta)
	else:
		slew_barrel(_gun, model.global_basis * Vector3.BACK, 2.0, delta)


## A line across the road through where the RWS (or the hull) will be when the beam reaches it,
## starting on the near side so the sweep runs away from the aircraft.
func _line_across(tank: Tank) -> void:
	var at := Gunnery.sensor_lead(tank, _muzzle.global_position, MG_SPEED)
	var lead := Course.to_course(at + tank.velocity * (SWEEP_WIND * Game.telegraph_scale() + SWEEP_TIME * 0.5))
	var side := signf(Course.to_course(global_position).y - lead.y)
	_line_a = Course.to_world(lead.x, lead.y + side * SWEEP_HALF)
	_line_b = Course.to_world(lead.x, lead.y - side * SWEEP_HALF)
	_line_a.y = Course.height_at(_line_a) + 0.2
	_line_b.y = Course.height_at(_line_b) + 0.2


func _sweep_point() -> Vector3:
	return _line_a.lerp(_line_b, 1.0 - clampf(_sweep / SWEEP_TIME, 0.0, 1.0))


func _fire(point: Vector3) -> void:
	var spot := point + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
	var shot := fire_along("orb", _muzzle, MG_SPEED, 4.0, Palette.HOT, spot - _muzzle.global_position, 4.0, GUN_SPREAD, Muzzle.AUTO)
	shot.hit.caliber = 20
	Sfx.play("enemy_gun", _muzzle.global_position, -3.0, 0.9)


func _ramp_point() -> Vector3:
	return _ramp_hinge.to_global(Vector3(0, 0, 1.8))


## Roped down or flung out of the ramp: FPV drones that form up on the tank, or a fungal pack.
func _drop_squad() -> void:
	var world := World.current
	var tank := player()
	var from := _ramp_point()
	var kind := squad if not squad.is_empty() else ("drones" if randf() < 0.5 else "crawlers")
	var count := (3 if _hard else 2) + (randi() % 2 if kind == "drones" else 1)
	for i in count:
		var spread := (i - (count - 1) * 0.5) * 6.0
		if kind == "drones":
			var drone := FpvDrone.new()
			drone.position = from
			drone.slot = Vector3(Course.to_course(tank.global_position).y + spread, 7.0, 22.0 + i * 3.0)
			drone.approach_time = 1.0 + i * 0.3
			world.add_enemy(drone)
		else:
			var course := Course.to_course(from)
			var crawler := Crawler.new()
			crawler.position = Course.ground_at(course.x - 2.0 - i, course.y + spread * 0.4)
			world.add_enemy(crawler)
			world.fx.dust(crawler.position, 6, 2.0, Palette.STRAW)
			world.fx.beam(from, crawler.position + Vector3.UP, Palette.STONE, 0.05, 0.4)
	Sfx.play("warn", from, -4.0, 1.3)


## Engine out on one side: it rolls over that way, spins and drops until it hits the ground.
func _crash(delta: float) -> void:
	_fall += delta
	velocity.y -= 14.0 * delta
	global_position += Vector3(0, velocity.y, 0) * delta
	model.rotation.y += delta * 2.5
	model.rotation.z = lerpf(model.rotation.z, _lost * 1.3, delta * 1.5)
	World.current.fx.smoke(model.to_global(_nacelles[0 if _lost < 0.0 else 1].position), 1, 0.7, [Palette.ASH, Palette.STONE, Palette.INK])
	if global_position.y <= Course.height_at(global_position) + 1.0:
		die(Hit.make(Hit.Kind.BLAST, 99.0, global_position))


func telegraphing() -> bool:
	return _wind > 0.0


func interrupt() -> void:
	super()
	_wind = 0.0
	_sweep = 0.0
	_sweep_done = true
