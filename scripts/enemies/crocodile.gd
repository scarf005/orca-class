class_name Crocodile
extends Enemy
## Flame tank towing a fuel trailer. It drives in from the haze, closes to flame range, turns its hull onto the tank
## (the nozzle is fixed in the bow), flares the nozzle and marks the end of the jet on the ground, then burns a
## 28 m jet before it pulls away again. Keep out of 30 m, sidestep the slow hull, or shoot the trailer, which is hidden
## behind the hull head-on and bursts into a fire that takes the whole tank with it. A hit on the tracks stops it.

const LEAD_FAR := 40.0 ## Metres ahead of the tank it holds between attacks.
const LEAD_NEAR := 18.0 ## How close it presses before it burns.
const CLOSE_RATE := 6.0 ## Metres per second the lead shrinks by while it closes.
const PACE_TIME := 16.0 ## After this long it stops pacing the rail and lets the tank drive past.
const REACH := 28.0 ## Metres the jet reaches.
const START_RANGE := 26.0 ## It lights the nozzle once the tank is this close ahead of the bow.
const START_ARC := 35.0 ## Degrees either side of the bow the tank must be in.
const WIND := 0.9 ## Seconds from the nozzle flaring to the jet.
const BURN := 1.6
const COOLDOWN := 3.0
const TURN := 0.9 ## Radians per second the hull slews onto the tank while it burns.
const FRONT_ARMOR := 0.25 ## Share of coax damage that gets through the front plate.
const TRAILER_CENTER := Vector3(0.0, 1.0, 1.9) ## The fuel bowser's middle in the trailer's frame.
const TRAILER_RADIUS := 1.7
const TRAILER_SWING := 0.9 ## Radians the trailer can swing off the line of the hull.

var tracks_hp := 9.0
var fuel_hp := 14.0
var immobile := false
var fuel_gone := false
var _lane := 0.0
var _lane_timer := 0.0
var _lead := LEAD_FAR
var _wind := 0.0
var _jet := 0.0
var _cooldown := 2.0
var _yaw := 0.0
var _turret := Node3D.new()
var _trailer := Node3D.new()
var _nozzle := Node3D.new()
var _muzzle := Node3D.new()
var _hard := false


func _init() -> void:
	super()
	wreck_on_death = true
	max_hp = 70.0
	hp = 70.0
	radius = 2.2
	center_height = 1.5
	armor = 14.0 ## Millimetres: the light coax glances off; heavier rounds bite less.
	stabbable = true
	score = 500
	debris = [Fx.Debris.ARMOR, Fx.Debris.METAL, Fx.Debris.PAINT]
	weakness = {Hit.Kind.THROWN: 1.4, Hit.Kind.TAIL: 1.4, Hit.Kind.FRAGMENT: 0.3}
	mark_offsets = [-1.55, 1.55]
	mark_width = 0.6


func build() -> void:
	_hard = Game.difficulty == Game.Difficulty.HARD
	_add_mesh(model, "hull")
	_turret.position = Vector3(0, 2.5, 0.2)
	model.add_child(_turret)
	_add_mesh(_turret, "turret")
	pop_parts = [_turret]
	_trailer.position = Vector3(0, 0, 4.4)
	model.add_child(_trailer)
	_add_mesh(_trailer, "trailer")
	_nozzle.position = Vector3(0.7, 1.75, -3.8)
	model.add_child(_nozzle)
	_add_mesh(_nozzle, "nozzle")
	_muzzle.position = Vector3(0, 0, -0.2)
	_nozzle.add_child(_muzzle)
	_lane = Course.to_course(global_position).y
	_yaw = model.rotation.y


func _add_mesh(parent: Node3D, part: String) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = ActorMeshes.mesh("crocodile", part)
	parent.add_child(instance)


## The middle of the fuel bowser in the world.
func trailer_center() -> Vector3:
	return _trailer.to_global(TRAILER_CENTER)


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	var hull := super(from, to, extra_radius)
	if hidden or arriving or fuel_gone:
		return hull
	var rear := segment_sphere(from, to, trailer_center(), TRAILER_RADIUS + extra_radius)
	return hull if rear < 0.0 else (rear if hull < 0.0 else minf(hull, rear))


func behave(delta: float) -> void:
	var world := World.current
	var tank := player()
	if tank == null:
		return
	var here := Course.to_course(global_position)
	var attacking := _wind > 0.0 or _jet > 0.0
	_lane_timer -= delta
	if _lane_timer <= 0.0:
		_lane_timer = randf_range(2.0, 3.5)
		_lane = tank.course_u + randf_range(-4.0, 4.0)
	var target_d := here.x
	if age < PACE_TIME and world.rail.mode != Rail.Mode.ARENA:
		if not attacking:
			_lead = move_toward(_lead, LEAD_NEAR, CLOSE_RATE * delta)
		target_d = world.rail.d + tank.course_offset + _lead * Course.stage.standoff
	var speed := 0.0 if is_staggered() or immobile else world.rail.speed + 10.0
	var move := Vector2(clampf(target_d - here.x, -speed, speed), clampf(_lane - here.y, -5.0, 5.0) if not immobile and not attacking else 0.0)
	var before := model.rotation.y
	global_position = wading_at(here.x + move.x * delta, here.y + move.y * delta)
	var to_tank := tank.global_position - _muzzle.global_position
	if attacking or is_staggered():
		model.rotation.y = rotate_toward(model.rotation.y, atan2(-to_tank.x, -to_tank.z), TURN * delta) if not is_staggered() else model.rotation.y
	elif move.length() > 1.0:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-move.y, maxf(absf(move.x), 1.0) * signf(move.x + 0.01)), 3.0 * delta)
	# The trailer drags behind the turn: it keeps its heading and swings back in line.
	_trailer.rotation.y = clampf(lerp_angle(_trailer.rotation.y, 0.0, 1.5 * delta) - angle_difference(before, model.rotation.y), -TRAILER_SWING, TRAILER_SWING)
	var local := model.global_transform.affine_inverse() * tank.hit_center()
	_turret.rotation.y = lerp_angle(_turret.rotation.y, atan2(-local.x, -local.z), 4.0 * delta)
	if is_staggered():
		interrupt()
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if _wind > 0.0:
		_wind -= delta
		_flare(1.0 - _wind / (WIND * Game.telegraph_scale()), delta)
		if _wind <= 0.0:
			_jet = BURN * (1.25 if _hard else 1.0)
			FlameJet.start(self, _muzzle, _jet, REACH)
	elif _jet > 0.0:
		_jet -= delta
		if _jet <= 0.0:
			_cooldown = COOLDOWN * (0.75 if _hard else 1.0)
			_lead = LEAD_FAR
			_nozzle.scale = Vector3.ONE
	elif _cooldown <= 0.0 and _can_burn(tank):
		_wind = WIND * Game.telegraph_scale()
		Sfx.play("warn", global_position, -2.0, 0.6)


## Whether the tank is inside the bow's arc and close enough to light the nozzle for.
func _can_burn(tank: Tank) -> bool:
	var to_tank := tank.global_position - _muzzle.global_position
	to_tank.y = 0.0
	return to_tank.length() < START_RANGE and rad_to_deg((-model.global_basis.z).angle_to(to_tank)) < START_ARC


## The wind-up: the nozzle swells and glows and a ring on the ground marks where the jet will end.
func _flare(share: float, delta: float) -> void:
	var fx := World.current.fx
	_nozzle.scale = Vector3.ONE * lerpf(1.0, 3.0, share)
	if randf() < delta * 10.0:
		var bore := -_muzzle.global_basis.z
		var end := _muzzle.global_position + bore * REACH
		fx.marker(end, 3.0, 0.15, Palette.AMBER)
		fx.tongue(_muzzle.global_position + bore * 0.5, 0.5 + share, 0.8)


func damage_multiplier(hit: Hit) -> float:
	return super(hit) * frontal_armor(hit, FRONT_ARMOR)


func telegraphing() -> bool:
	return _wind > 0.0


func on_damaged(hit: Hit, amount: float) -> void:
	super(hit, amount)
	var world := World.current
	if not fuel_gone and hit.position.distance_to(trailer_center()) < TRAILER_RADIUS + 0.6:
		fuel_hp -= amount
		if fuel_hp <= 0.0:
			_rupture()
		return
	amount /= frontal_armor(hit, FRONT_ARMOR) # The front plate guards the hull, not the tracks behind it.
	var local := model.global_transform.affine_inverse() * hit.position
	if not immobile and local.y < 1.0 and absf(local.x) > 1.2:
		tracks_hp -= amount
		if tracks_hp <= 0.0:
			immobile = true
			world.fx.debris(global_position + Vector3.UP * 0.4, 8, [Fx.Debris.METAL, Fx.Debris.DIRT], 7.0, 0.3)
			world.fx.burn(global_position + Vector3.UP * 0.6, 10.0, 0.6)
			world.award(100, global_position, false)


## The bowser bursts: its fuel fires the ground around it and the blast takes the tank with it.
func _rupture() -> void:
	var world := World.current
	fuel_gone = true
	var at := trailer_center()
	var ground := Vector3(at.x, Course.height_at(at), at.z)
	FireZone.ignite(ground, "fuel", true)
	world.blast(at, 6.0, 30.0, Team.PLAYER, null, self, [Palette.WHITE, Palette.AMBER, Palette.HOT, Palette.CORAL])
	world.fx.burn(ground, 6.0, 1.4)
	Wreck.launch(_trailer, at, 1.5, true, Vector3.UP * 6.0, false)
	var blast := Hit.make(Hit.Kind.BLAST, max_hp, at)
	blast.source = world.player
	take_hit(blast)


func interrupt() -> void:
	super()
	_wind = 0.0
	_jet = 0.0
	_nozzle.scale = Vector3.ONE
