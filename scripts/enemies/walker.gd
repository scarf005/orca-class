class_name Walker
extends Enemy
## Bipedal walker with wheels on its feet. It rolls between lanes ahead of the tank, then plants
## its feet, crouches with a flashing eye and fires: a 15 mm burst from its arm gun, or a ripple of four
## missiles from its shoulder pod, whose lid opens for the whole 0.8 s wind-up. A hit low on the legs breaks them and it topples.

const KEEP_AHEAD := 42.0
const PACE_TIME := 14.0
const SKATE_SPEED := 18.0
const BARREL_SLEW := 3.0 ## Radians per second the arm gun and the pod turn onto the tank.
const POD_LOFT := Vector3(0, 6, 0) ## The pod aims above the tank: its missiles pop up, then steer down onto it.
const GUN_SPREAD := 0.03 ## Radians of scatter on every arm gun round.
const MISSILE_WIND := 0.8 ## Seconds the pod's lid is open before the first missile leaves.
const RIPPLE := 4 ## Missiles in a salvo.
const RIPPLE_GAP := 0.16
const LID_OPEN := 1.7
const WHEEL_RADIUS := 0.2
const ROUND_SPEED := MG_SPEED
const KICK_RANGE := 7.0 ## A tank this close in front is kicked.
const KICK_REACH := 8.0 ## It must still be this close when the kick lands.
const KICK_WIND := 0.45
const KICK_COOLDOWN := 2.5
const KICK_DAMAGE := 18.0
const KICK_SHOVE := 12.0 ## Sideways speed the kick adds to the tank.
const KICK_ARC := 60.0 ## Degrees either side of where it faces.
const FRONT_ARMOR := 0.25 ## Share of coax damage that gets through the front plate.

var weapon := "gun" ## "gun" or "missile".
var _at_tail := false ## This burst goes for the tank's tail, not its roof sensors.
var legs_hp := 8.0
var crippled := false
var _lane := 0.0
var _lane_timer := 0.0
var _attack_timer := 1.6
var _telegraph := 0.0
var _burst := 0
var _burst_timer := 0.0
var _kick := 0.0 ## Seconds of the kick's wind-up left.
var _kick_cooldown := 0.0
var _aim := Vector3.ZERO ## Where the arm gun burst goes: fixed when the telegraph ends.
var _crouch := 0.25 ## How far it sits into its knees: 0.25 rolling, 0.55 planted.
var _body := Node3D.new()
var _legs: Array[Dictionary] = [] ## {hip, knee, ankle, wheel}
var _arm := Node3D.new()
var _muzzle := Node3D.new()
var _pod := Node3D.new()
var _pod_muzzle := Node3D.new()
var _pod_lid := Node3D.new() ## Hinged along the pod's top front edge; it swings up for the ripple.
var _eye_material := StandardMaterial3D.new()
var _hard := false


func _init() -> void:
	super()
	wreck_on_death = true
	max_hp = 60.0
	hp = 60.0
	radius = 1.6
	center_height = 2.6
	armor = 10.0 ## Millimetres: the light coax glances off; heavier rounds bite less.
	stabbable = true
	score = 450
	debris = [Fx.Debris.ARMOR, Fx.Debris.METAL, Fx.Debris.PAINT]
	weakness = {Hit.Kind.THROWN: 1.5, Hit.Kind.TAIL: 1.3, Hit.Kind.FRAGMENT: 0.3}
	mark_offsets = [-0.83, 0.83] # Thin lines under the wheels on its feet.
	mark_width = 0.25


func build() -> void:
	_hard = Game.difficulty == Game.Difficulty.HARD
	_body.position = Vector3(0, 2.7, 0)
	model.add_child(_body)
	_add_mesh(_body, ActorMeshes.mesh("walker", "body"))
	var eye := MeshInstance3D.new()
	eye.mesh = ActorMeshes.mesh("walker", "eye")
	_eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_material.albedo_color = Palette.HOT
	eye.material_override = _eye_material
	eye.position = Vector3(0, 0.75, -0.9)
	_body.add_child(eye)
	# Arm gun on the right, missile pod on the left shoulder.
	_arm.position = Vector3(0.85, 0.55, 0)
	_body.add_child(_arm)
	_add_mesh(_arm, ActorMeshes.mesh("walker", "arm"))
	_muzzle.position = Vector3(0, 0, -1.6)
	_arm.add_child(_muzzle)
	_pod.position = Vector3(-0.8, 1.1, 0.1)
	_body.add_child(_pod)
	_add_mesh(_pod, ActorMeshes.mesh("walker", "pod"))
	_pod_muzzle.position = Vector3(0, 0, -0.6)
	_pod.add_child(_pod_muzzle)
	_pod_lid.position = Vector3(0, 0.25, -0.43)
	_pod.add_child(_pod_lid)
	_add_mesh(_pod_lid, ActorMeshes.mesh("walker", "lid"))
	# Reverse-jointed legs ending in wheeled feet.
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.55 * side, -0.1, 0)
		_body.add_child(hip)
		_add_mesh(hip, ActorMeshes.mesh("walker", "thigh"))
		var knee := Node3D.new()
		knee.position = Vector3(0, -1.2, -0.3)
		hip.add_child(knee)
		_add_mesh(knee, ActorMeshes.mesh("walker", "shin"))
		var ankle := Node3D.new()
		ankle.position = Vector3(0, -1.15, 0.35)
		knee.add_child(ankle)
		_add_mesh(ankle, ActorMeshes.mesh("walker", "foot"))
		var wheel := Node3D.new()
		wheel.position = Vector3(0.28 * side, -0.12, 0)
		ankle.add_child(wheel)
		_add_mesh(wheel, ActorMeshes.mesh("walker", "wheels"))
		_legs.append({"hip": hip, "knee": knee, "ankle": ankle, "wheel": wheel, "side": side})
	_lane = Course.to_course(global_position).y
	_attack_timer = randf_range(1.2, 2.2)


func _add_mesh(parent: Node3D, mesh: Mesh) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	parent.add_child(instance)


func behave(delta: float) -> void:
	var world := World.current
	var tank := player()
	if tank == null:
		return
	var here := Course.to_course(global_position)
	_kick_cooldown = maxf(0.0, _kick_cooldown - delta)
	var planted := _telegraph > 0.0 or _burst > 0 or _kick > 0.0 or crippled or is_staggered()
	_lane_timer -= delta
	if _lane_timer <= 0.0:
		_lane_timer = randf_range(1.2, 2.4)
		_lane = randf_range(-1.0, 1.0) * Tank.lateral_limit(here.x) * 0.8
	var target_d := here.x
	if age < PACE_TIME and world.rail.mode != Rail.Mode.ARENA:
		target_d = world.rail.d + tank.course_offset + KEEP_AHEAD
	var move := Vector2.ZERO
	if not planted:
		var chase := world.rail.speed + 12.0
		move = Vector2(clampf(target_d - here.x, -chase, chase), clampf(_lane - here.y, -SKATE_SPEED, SKATE_SPEED) * 0.9)
	var next := here + move * delta
	global_position = Course.ground_at(next.x, next.y)
	# Face the tank; the body leans into acceleration as it rolls.
	var to_tank := tank.global_position - global_position
	model.rotation.y = lerp_angle(model.rotation.y, atan2(-to_tank.x, -to_tank.z), 5.0 * delta)
	_animate(delta, planted)
	_pod_lid.rotation.x = lerpf(_pod_lid.rotation.x, LID_OPEN if (weapon == "missile" or _hard) and (_telegraph > 0.0 or _burst > 0) else 0.0, 12.0 * delta)
	if crippled or is_staggered():
		_telegraph = 0.0
		_kick = 0.0
		return
	aim_barrel(_arm, _arm_aim(tank), BARREL_SLEW, delta)
	aim_barrel(_pod, _pod_aim(tank), BARREL_SLEW, delta)
	if _burst > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0 and weapon == "missile":
			_burst -= 1
			_burst_timer = RIPPLE_GAP
			_fire_missile(tank)
			if _hard:
				var shot := fire_along("orb", _muzzle, ROUND_SPEED, 3.0, Palette.HOT, _aim - _muzzle.global_position, 3.0, GUN_SPREAD, Muzzle.LIGHT)
				shot.hit.caliber = 15
		elif _burst_timer <= 0.0:
			_burst -= 1
			_burst_timer = 0.08
			if _hard and _burst % 2 == 0:
				_fire_missile(tank)
			var shot := fire_along("orb", _muzzle, ROUND_SPEED, 3.0, Palette.HOT, _aim - _muzzle.global_position, 3.0, GUN_SPREAD, Muzzle.LIGHT)
			shot.hit.caliber = 15
			Sfx.play("enemy_gun", _muzzle.global_position, -4.0, 1.2)
			_body.position.z = 0.1
		return
	if _telegraph > 0.0:
		_telegraph -= delta
		_eye_material.albedo_color = Palette.WHITE if fmod(_telegraph, 0.1) < 0.05 else Palette.HOT
		if _telegraph <= 0.0:
			_attack(tank)
		return
	if _kick > 0.0:
		_kick -= delta
		_eye_material.albedo_color = Palette.WHITE if fmod(_kick, 0.1) < 0.05 else Palette.HOT
		if _kick <= 0.0:
			_land_kick(tank)
		return
	if _kick_cooldown <= 0.0 and _flat_distance(tank) < KICK_RANGE and _faces(tank):
		_kick = KICK_WIND * Game.telegraph_scale()
		Sfx.play("warn", global_position, -6.0, 1.6)
		return
	_attack_timer -= delta
	var distance := global_position.distance_to(tank.global_position)
	if _attack_timer <= 0.0 and distance < 90.0 and distance > 10.0:
		_telegraph = (0.55 if weapon == "gun" and not _hard else MISSILE_WIND) * Game.telegraph_scale()
		_at_tail = randf() < Gunnery.TAIL_CHANCE
		_attack_timer = (2.2 if weapon == "gun" else 3.2) * (0.75 if _hard else 1.0)
		Sfx.play("warn", global_position, -6.0, 1.6)


func _attack(tank: Tank) -> void:
	_eye_material.albedo_color = Palette.HOT
	_aim = Gunnery.sensor_lead(tank, _muzzle.global_position, ROUND_SPEED, _at_tail)
	if weapon == "gun":
		_burst = 8 if _hard else 6
		_burst_timer = 0.0
		return
	_burst = RIPPLE
	_burst_timer = 0.0


## One missile of the ripple: it pops up out of the pod, then steers onto where the tank will be.
func _fire_missile(tank: Tank) -> void:
	var from := _pod_muzzle.global_position
	var missile := fire_along("rocket", _pod_muzzle, 34.0, 0.0, Palette.HOT, Vector3.ZERO, 3.0, 0.06)
	missile.hit = Hit.make(Hit.Kind.SHELL, 0.0, from)
	missile.hit.source = self
	missile.blast_radius = 2.4
	missile.blast_damage = 12.0
	missile.homing_target = tank
	missile.homing_lead = true
	missile.turn_rate = 2.1
	missile.interceptable = true
	missile.intercept_hp = 0.7
	missile.trail = Projectile.ROCKET_SMOKE
	missile.life = 5.0
	Sfx.play("launch", from, 0.0, 1.3)


## Where the pod points: above the tank's roof sensor (the RWS first), so the missiles pop up and then steer down onto it.
func _pod_aim(tank: Tank) -> Vector3:
	return Gunnery.sensor_lead(tank, _pod_muzzle.global_position, 34.0) + POD_LOFT


func _flat_distance(tank: Tank) -> float:
	return Vector2(tank.global_position.x - global_position.x, tank.global_position.z - global_position.z).length()


## Whether the tank is inside the kick's arc ahead of the walker.
func _faces(tank: Tank) -> bool:
	var to_tank := tank.global_position - global_position
	to_tank.y = 0.0
	return rad_to_deg((-model.global_basis.z).angle_to(to_tank)) <= KICK_ARC


## The kick lands: a ram hit and a shove sideways, if the tank has not backed out of reach.
func _land_kick(tank: Tank) -> void:
	var world := World.current
	_kick_cooldown = KICK_COOLDOWN
	_eye_material.albedo_color = Palette.HOT
	_body.position.z = -0.3
	if _flat_distance(tank) > KICK_REACH:
		return
	var hit := Hit.make(Hit.Kind.RAM, KICK_DAMAGE, tank.hit_center(), (tank.global_position - global_position).normalized())
	hit.source = self
	tank.take_hit(hit)
	var lateral := tank.global_position.x - global_position.x if world.rail.mode == Rail.Mode.ARENA else Course.to_course(tank.global_position).y - Course.to_course(global_position).y
	tank.local_velocity.x += signf(lateral) * KICK_SHOVE
	world.fx.sparks(tank.hit_center(), hit.direction, 12, Palette.BUTTER, 12.0)
	Sfx.play("impact", tank.global_position)


## What the arm turns onto: the lead on the sensor while a gun winds up, then that point held for
## the burst; a missile walker keeps it on the tank.
func _arm_aim(tank: Tank) -> Vector3:
	if weapon != "gun":
		return tank.hit_center()
	return _aim if _burst > 0 else Gunnery.sensor_lead(tank, _muzzle.global_position, ROUND_SPEED, _at_tail)


## Settles into the planted crouch without running any AI (debug room).
func pose_idle() -> void:
	for _i in 30:
		_animate(0.05, true)


## Rolling stance: the legs hold one pose, crouched when planted, with a small suspension bob over
## the ground and a lean into acceleration; the wheels on the feet spin at the ground speed.
func _animate(delta: float, planted: bool) -> void:
	var lean := sway(delta)
	var bob := clampf(lean.y * 0.02, -1.0, 1.0)
	_crouch = lerpf(_crouch, 0.55 if planted and not crippled else 0.25, 10.0 * delta)
	_body.position.y = lerpf(_body.position.y, 2.7 - _crouch * 0.8 - bob * 0.05, 8.0 * delta)
	_body.position.z = move_toward(_body.position.z, 0.0, delta)
	_body.rotation.x = lerpf(_body.rotation.x, clampf(lean.z * 0.01, -0.12, 0.12), 5.0 * delta)
	_body.rotation.z = lerpf(_body.rotation.z, clampf(-lean.x * 0.01, -0.12, 0.12), 5.0 * delta)
	var hip := -0.35 - _crouch - bob * 0.05
	var knee := 0.7 + _crouch * 1.6 + bob * 0.06
	var spin := rolled() / WHEEL_RADIUS
	for leg in _legs:
		(leg.hip as Node3D).rotation.x = hip
		(leg.knee as Node3D).rotation.x = knee
		(leg.ankle as Node3D).rotation.x = -0.35 - _crouch * 0.8
		(leg.wheel as Node3D).rotation.x -= spin
	if crippled:
		# Broken legs: slumped to one side, sparking.
		model.rotation.z = lerpf(model.rotation.z, 0.8, 3.0 * delta)
		_body.position.y = lerpf(_body.position.y, 1.2, 3.0 * delta)
		if randf() < delta * 6.0:
			World.current.fx.sparks(_body.global_position, Vector3.UP, 4, Palette.BUTTER)


func damage_multiplier(hit: Hit) -> float:
	return super(hit) * frontal_armor(hit, FRONT_ARMOR)


func telegraphing() -> bool:
	return _telegraph > 0.0 or _kick > 0.0


func on_damaged(hit: Hit, amount: float) -> void:
	super(hit, amount)
	amount /= frontal_armor(hit, FRONT_ARMOR) # The front plate guards the hull, not the legs.
	var local := model.global_transform.affine_inverse() * hit.position
	if not crippled and local.y < 1.8:
		legs_hp -= amount
		if legs_hp <= 0.0:
			crippled = true
			World.current.fx.debris(global_position + Vector3.UP, 8, [Fx.Debris.METAL], 7.0, 0.3)
			World.current.award(100, global_position, false)


func interrupt() -> void:
	super()
	_telegraph = 0.0
	_kick = 0.0
	_burst = 0
	_eye_material.albedo_color = Palette.HOT
