class_name Burner
extends Walker
## Flame walker: the walker chassis with a shrouded flame projector for an arm and a fuel pack on its back that
## stands up over its shoulders. It skates in, plants, lights its pilot flame and aims, then burns a short jet while its
## arm sweeps after the tank. Stay out of 20 m, strafe the slow arm, or shoot the fuel pack over its shoulder: it
## bursts into a fireball that takes the walker with it.

const LEAD_FAR := 36.0 ## Metres ahead of the tank it holds between attacks.
const LEAD_NEAR := 13.0
const CLOSE_RATE := 7.0
const REACH := 18.0
const START_RANGE := 16.0
const WIND := 0.7
const BURN := 1.1
const COOLDOWN := 2.6
const JET_SLEW := 1.2 ## Radians per second the arm sweeps after the tank while it burns.
const PACK_CENTER := Vector3(0.0, 1.75, 0.85) ## The fuel pack's middle in the body's frame.
const PACK_RADIUS := 0.9

var pack_hp := 10.0
var pack_gone := false
var _wind := 0.0
var _jet := 0.0
var _lead := LEAD_FAR
var _pack := Node3D.new()


func _init() -> void:
	super()
	score = 600
	radius = 1.2 # Smaller than the walker's: the fuel pack must stand clear of the hull's hit sphere over its shoulders.
	center_height = 2.4


func build() -> void:
	super()
	_pod.queue_free()
	(_arm.get_child(0) as MeshInstance3D).mesh = ActorMeshes.mesh("burner", "arm")
	_muzzle.position = Vector3(0, 0, -2.5)
	_pack.position = Vector3(0, 0.55, 0.85)
	_body.add_child(_pack)
	var mesh := MeshInstance3D.new()
	mesh.mesh = ActorMeshes.mesh("burner", "tank")
	_pack.add_child(mesh)


func pack_center() -> Vector3:
	return _body.to_global(PACK_CENTER)


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	var hull := super(from, to, extra_radius)
	if hidden or arriving or pack_gone:
		return hull
	var rear := segment_sphere(from, to, pack_center(), PACK_RADIUS + extra_radius)
	return hull if rear < 0.0 else (rear if hull < 0.0 else minf(hull, rear))


func behave(delta: float) -> void:
	var world := World.current
	var tank := player()
	if tank == null:
		return
	var here := Course.to_course(global_position)
	var planted := _wind > 0.0 or _jet > 0.0 or crippled or is_staggered()
	_lane_timer -= delta
	if _lane_timer <= 0.0:
		_lane_timer = randf_range(1.2, 2.4)
		_lane = tank.course_u + randf_range(-6.0, 6.0)
	var target_d := here.x
	if age < PACE_TIME and world.rail.mode != Rail.Mode.ARENA:
		if not planted:
			_lead = move_toward(_lead, LEAD_NEAR, CLOSE_RATE * delta)
		target_d = world.rail.d + tank.course_offset + _lead * Course.stage.standoff
	var move := Vector2.ZERO
	if not planted:
		var chase := world.rail.speed + 12.0
		move = Vector2(clampf(target_d - here.x, -chase, chase), clampf(_lane - here.y, -SKATE_SPEED, SKATE_SPEED) * 0.9)
	global_position = wading_at(here.x + move.x * delta, here.y + move.y * delta)
	var to_tank := tank.global_position - global_position
	model.rotation.y = lerp_angle(model.rotation.y, atan2(-to_tank.x, -to_tank.z), 5.0 * delta)
	_animate(delta, planted)
	if crippled or is_staggered():
		interrupt()
		return
	var slew := JET_SLEW if _jet > 0.0 else BARREL_SLEW
	aim_barrel(_arm, tank.hit_center(), slew, delta)
	if _wind > 0.0:
		_wind -= delta
		_eye_material.albedo_color = Palette.WHITE if fmod(_wind, 0.1) < 0.05 else Palette.HOT
		if randf() < delta * 10.0:
			world.fx.marker(_muzzle.global_position - _muzzle.global_basis.z * REACH, 2.5, 0.15, Palette.AMBER)
			world.fx.tongue(_muzzle.global_position, 0.6, 0.8)
		if _wind <= 0.0:
			_jet = BURN * (1.25 if _hard else 1.0)
			_eye_material.albedo_color = Palette.HOT
			FlameJet.start(self, _muzzle, _jet, REACH)
	elif _jet > 0.0:
		_jet -= delta
		if _jet <= 0.0:
			_attack_timer = COOLDOWN * (0.75 if _hard else 1.0)
			_lead = LEAD_FAR
	else:
		_attack_timer -= delta
		if _attack_timer <= 0.0 and Vector2(to_tank.x, to_tank.z).length() < START_RANGE:
			_wind = WIND * Game.telegraph_scale()
			Sfx.play("warn", global_position, -6.0, 1.2)


func telegraphing() -> bool:
	return _wind > 0.0


func on_damaged(hit: Hit, amount: float) -> void:
	super(hit, amount)
	if not pack_gone and hit.position.distance_to(pack_center()) < PACK_RADIUS + 0.6:
		pack_hp -= amount
		if pack_hp <= 0.0:
			_rupture()


## The fuel pack bursts: a fireball and burning ground take the walker with it.
func _rupture() -> void:
	var world := World.current
	pack_gone = true
	var at := pack_center()
	FireZone.ignite(Vector3(at.x, Course.height_at(at), at.z), "fuel", true)
	world.blast(at, 4.5, 25.0, Team.PLAYER, null, self, [Palette.WHITE, Palette.AMBER, Palette.HOT, Palette.CORAL])
	var blast := Hit.make(Hit.Kind.BLAST, max_hp, at)
	blast.source = world.player
	take_hit(blast)


func interrupt() -> void:
	super()
	_wind = 0.0
	_jet = 0.0
