class_name HiMo
extends Enemy
## A long, low shark-mouthed hull on four thick legs that skate on big wheels, after the Project Landsword crawler
## and the HAL-X10. It sheds its white armor, then fights on exposed rails and broken legs. Above-water actuators
## are the leg weak points.
## Stable redraw anchors: Model/Body, Rail, Rack, PlateL/R; Hip0..3/Knee/Wheel on Body.

enum Phase { SKATER, STRIPPED, DESPERATE }
enum Attack { NONE, GUN, MISSILES, RAIL, CHARGE, STOMP, SWEEP, HOP }

const BODY_HP := 95000.0 ## Skating limits uptime; bare flanks still take full main-gun damage. About 50 s for perfect aim.
const PHASE_MARKS := [0.65, 0.30]
const LEG_HP := 100.0
const SCALE := 1.7 ## The whole machine is drawn this much larger than its model-space layout.
const WHEEL_RADIUS := 1.3 * SCALE
const HIP := Vector3(2.2, -0.2, 3.2) ## Model-space leg rig for the right rear corner; other corners mirror it.
const KNEE := Vector3(2.5, 2.7, 0.9) ## From the hip.
const AXLE := Vector3(2.3, -5.6, 1.3) ## From the knee: the wheel's centre, its radius above the foot.
const SPEED := [46.0, 42.0, 34.0]
const CIRCLE := [46.0, 40.0, 34.0] ## Metres it keeps from the tank while skating round it, closing in by phase.
const WIND := [0.0, 0.7, 1.0, 1.5, 1.2, 1.1, 0.9, 0.8]
const PATTERNS := [
	[Attack.GUN, Attack.RAIL, Attack.CHARGE, Attack.HOP, Attack.STOMP],
	[Attack.HOP, Attack.MISSILES, Attack.GUN, Attack.CHARGE, Attack.STOMP, Attack.SWEEP, Attack.RAIL],
	[Attack.SWEEP, Attack.RAIL, Attack.CHARGE, Attack.STOMP, Attack.HOP, Attack.MISSILES, Attack.GUN, Attack.RAIL],
]
const ACTUATOR_RADIUS := 1.3 * SCALE
const STOMP_REACH := 20.0 ## Both reaches grow with the machine: 12 and 15 m at model size.
const SWEEP_REACH := 25.0
const CHARGE_SPEED := 68.0
const HOP_TIME := 1.0
const SPUN := 3.0 ## Seconds a full charge into its face mid-charge leaves it spun out, taking double damage.

var phase := Phase.SKATER
var _body := Node3D.new()
var _rail := Node3D.new()
var _rack := Node3D.new()
var _muzzle := Node3D.new()
var _guns: Array[Node3D] = []
var _legs: Array[Dictionary] = [] ## {hip, knee, wheel, hp, corner}.
var _plates: Array[Node3D] = []
var _attack := Attack.NONE
var _attack_time := 0.0
var _next_attack := 2.0
var _pattern := 0
var _shots := 0
var _shot_timer := 0.0
var _aim := Vector3.ZERO
var _from := Vector3.ZERO
var _drift := Vector3.ZERO
var _hop := 0.0
var _hop_from := Vector3.ZERO
var _hop_to := Vector3.ZERO
var _hop_height := 0.0
var _shell_time := -1.0
var _transition := 0.0
var _transition_from := Vector3.ZERO
var _transition_to := Vector3.ZERO
var _wake := 0.0
var _overcharge := false
var _final_rail := false
var spun := 0.0


func _init() -> void:
	super()
	boss = true
	heavy = true
	wreck_on_death = true
	max_hp = BODY_HP
	hp = BODY_HP
	radius = 6.5 * SCALE
	center_height = 4.4 * SCALE
	armor = 30.0
	despawn_behind = 0.0
	score = 50000
	mark_offsets = [-5.2, 5.2]
	mark_width = 0.6
	set_meta("title", "BOSS_HI_MO")
	set_meta("phase_marks", PHASE_MARKS)


func build() -> void:
	model.scale = Vector3.ONE * SCALE
	_body.name = "Body"
	_rail.name = "Rail"
	_rack.name = "Rack"
	_body.position.y = 4.4
	model.add_child(_body)
	# A long, low armoured hull with a shark-mouthed nose; white side armour comes off.
	_add_mesh(_body, ActorMeshes.mesh("hi_mo", "hull"))
	for side in [-1.0, 1.0]:
		var plate := Node3D.new()
		plate.name = "PlateL" if side < 0.0 else "PlateR"
		plate.position = Vector3(side * 2.5, 0.1, 0.4)
		_body.add_child(plate)
		_add_mesh(plate, ActorMeshes.mesh("hi_mo", "plate_l" if side < 0.0 else "plate_r"))
		_plates.append(plate)
		# Chin gun pods under the prow.
		var gun := Node3D.new()
		gun.position = Vector3(side * 1.7, -1.1, -4.6)
		_body.add_child(gun)
		_add_mesh(gun, ActorMeshes.mesh("hi_mo", "gun"))
		var muzzle := Node3D.new()
		muzzle.position.z = -2.3
		gun.add_child(muzzle)
		_guns.append(muzzle)
	# Rail cannon on a flat turret along the spine.
	_rail.position = Vector3(0, 1.4, -0.4)
	_body.add_child(_rail)
	_add_mesh(_rail, ActorMeshes.mesh("hi_mo", "rail"))
	_muzzle.position.z = -7.2
	_rail.add_child(_muzzle)
	# Missile block aft.
	_rack.position = Vector3(0, 1.5, 3.1)
	_body.add_child(_rack)
	_add_mesh(_rack, ActorMeshes.mesh("hi_mo", "rack"))
	# Four armoured legs: the thigh climbs from a round hip housing to a knee above the hull, where the glowing
	# actuator is the weak point, then the shin drops to a big wheel at the foot.
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var tag: String = ("f" if corner.y < 0.0 else "r") + ("l" if corner.x < 0.0 else "r")
		var hip := Node3D.new()
		hip.name = "Hip%d" % _legs.size()
		hip.position = Vector3(corner.x * HIP.x, HIP.y, corner.y * HIP.z)
		_body.add_child(hip)
		_add_mesh(hip, ActorMeshes.mesh("hi_mo", "thigh_" + tag))
		var knee := Node3D.new()
		knee.name = "Knee"
		knee.position = Vector3(corner.x * KNEE.x, KNEE.y, corner.y * KNEE.z)
		hip.add_child(knee)
		_add_mesh(knee, ActorMeshes.mesh("hi_mo", "shin_" + tag))
		var wheel := Node3D.new()
		wheel.name = "Wheel"
		wheel.position = Vector3(corner.x * AXLE.x, AXLE.y, corner.y * AXLE.z)
		knee.add_child(wheel)
		_add_mesh(wheel, ActorMeshes.mesh("hi_mo", "wheel"))
		_legs.append({"hip": hip, "knee": knee, "wheel": wheel, "hp": LEG_HP, "corner": corner})
	pop_parts = [_rail, _rack]
	call_deferred("_play_music") # After the director's boss-start call.


func _add_mesh(parent: Node3D, mesh: Mesh) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	parent.add_child(instance)


func music_track() -> String:
	return Course.stage.boss_music(phase)


func _play_music() -> void:
	if not dead:
		Sfx.play_music(music_track())


func legs_lost() -> int:
	return _legs.filter(func(leg: Dictionary) -> bool: return leg.hp <= 0.0).size()


func skate_speed() -> float:
	return (SPEED[phase] as float) * (0.2 if legs_lost() >= 2 else 0.65 if legs_lost() == 1 else 1.0)


func _bounded(at: Vector3) -> Vector3:
	return World.current.director.scenery.arena_position(at, Stage2.BAY_D, radius)


func _floor(at: Vector3) -> float:
	var height := Course.height_at(at)
	for structure in Course.structure_boxes:
		var local: Vector3 = structure.pose.affine_inverse() * at
		if absf(local.x) < structure.size.x * 0.5 + radius and absf(local.z) < structure.size.z * 0.5 + radius:
			height = maxf(height, structure.pose.origin.y + structure.size.y)
	for prop: Prop in World.current.props.near(at, at, radius + 8.0):
		if prop.hard and not prop.dead and Vector2(at.x - prop.position.x, at.z - prop.position.z).length() < prop.footprint + radius:
			height = maxf(height, prop.global_position.y + prop.height)
	return height


func _start_hop(to: Vector3) -> void:
	_hop = HOP_TIME
	_hop_from = global_position
	_hop_to = _bounded(to)
	_hop_to.y = _floor(_hop_to)
	_hop_height = maxf(12.0, _floor(global_position.lerp(_hop_to, 0.5)) - minf(_hop_from.y, _hop_to.y) + 8.0)


func behave(delta: float) -> void:
	var tank := player()
	if tank == null:
		return
	if _transition > 0.0 and phase == Phase.DESPERATE:
		_transition = maxf(0.0, _transition - delta)
		var k := 1.0 - _transition / 2.4
		global_position = _transition_from.lerp(_transition_to, minf(k * 2.0, 1.0)) + Vector3.UP * smoothstep(0.5, 1.0, k) * 3.5
		_wake -= delta
		if _wake <= 0.0:
			_wake = 0.15
			World.current.fx.splash(global_position, 2.0, Stage2.WATER_LEVEL)
		_animate(delta)
		return
	if spun > 0.0:
		spun = maxf(0.0, spun - delta)
		model.rotation.y += delta * 6.0 * spun / SPUN # Spinning out on its wheels, slowing to a stop.
		_drift = Vector3.ZERO
		_animate(delta)
		return
	if is_staggered() and _transition <= 0.0:
		_drift = _drift.move_toward(Vector3.ZERO, delta * 80.0)
	elif _hop <= 0.0 and _attack not in [Attack.RAIL, Attack.CHARGE, Attack.STOMP, Attack.SWEEP]:
		var goal := circling_goal(tank.global_position, CIRCLE[phase], 0.6, Course.to_world(Stage2.BAY_D, 0.0), Stage2.BAY_RADIUS - radius - 1.0) # Leads the turn so the lagging drift holds the ring.
		var desired := (goal - global_position).normalized() * skate_speed()
		if _attack == Attack.MISSILES:
			desired = Vector3.ZERO # The high-perch volley is an exposed charge opening.
		if phase == Phase.DESPERATE:
			desired *= 0.8 + 0.35 * sin(age * 4.0)
		_drift = _drift.lerp(desired, 1.0 - exp(-3.0 * delta))
		var next := _bounded(global_position + _drift * delta)
		var floor_y := _floor(next)
		if legs_lost() < 2 and (floor_y > global_position.y + 1.0 or global_position.y > floor_y + 2.0):
			_start_hop(global_position + _drift.normalized() * 28.0)
		elif floor_y <= global_position.y + 1.0:
			next.y = floor_y
			global_position = next
		else:
			_drift = Vector3.ZERO
	if _hop > 0.0:
		_hop = maxf(0.0, _hop - delta)
		var k := 1.0 - _hop / HOP_TIME
		global_position = _hop_from.lerp(_hop_to, k) + Vector3.UP * sin(k * PI) * _hop_height
		if _hop <= 0.0 and (_transition > 0.0 or phase >= Phase.STRIPPED and _attack in [Attack.HOP, Attack.STOMP]):
			World.current.director.scenery.crush_cover(global_position, global_position, radius, ["container", "city_deck"])
			global_position.y = _floor(global_position)
			World.current.fx.shockwave(global_position, STOMP_REACH * 2.0, Palette.HOT)
			if _transition > 0.0:
				_transition = 0.0
				while not _plates.is_empty():
					_shed_plate(Vector3.UP)
				_play_music()
	global_position = _bounded(global_position)
	var toward := tank.hit_center() - _body.global_position
	if _attack not in [Attack.RAIL, Attack.CHARGE, Attack.SWEEP]:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-toward.x, -toward.z), minf(1.0, delta * 3.5))
	_animate(delta)
	if _transition <= 0.0 and not is_staggered() and (_hop <= 0.0 or _attack in [Attack.STOMP, Attack.HOP]):
		_update_attack(delta, tank)


func _animate(delta: float) -> void:
	_body.position.y = lerpf(_body.position.y, 1.8 if legs_lost() >= 2 else 4.4, minf(1.0, delta * 6.0))
	_body.rotation.z = lerpf(_body.rotation.z, 0.25 if spun > 0.0 else clampf(-_drift.dot(model.global_basis.x) * 0.009, -0.3, 0.3), minf(1.0, delta * 4.0))
	for leg in _legs:
		if leg.hp > 0.0:
			var knee: Node3D = leg.knee
			knee.rotation.x = lerpf(knee.rotation.x, -0.35 if _hop > 0.0 else 0.0, minf(1.0, delta * 6.0))
			(leg.wheel as Node3D).rotation.x -= _drift.length() * delta / WHEEL_RADIUS


func _choose_attack() -> void:
	if phase == Phase.DESPERATE and hp <= max_hp * 0.13 and not _final_rail:
		_final_rail = true
		_begin_attack(Attack.RAIL)
		return
	var options: Array[Attack] = []
	options.assign(PATTERNS[phase])
	if legs_lost() >= 2:
		options = options.filter(func(attack: Attack) -> bool: return attack not in [Attack.CHARGE, Attack.STOMP, Attack.SWEEP, Attack.HOP])
	_begin_attack(options[_pattern % options.size()])
	_pattern += 1


func _begin_attack(attack: Attack) -> void:
	_attack = attack
	_overcharge = phase == Phase.DESPERATE and attack == Attack.RAIL and hp <= max_hp * 0.13
	print("ATTACK kind=hi_mo attack=%s phase=%d t=%.2f overcharge=%s" % [Attack.keys()[attack], phase + 1, age, _overcharge])
	_attack_time = 0.0
	_shots = 0
	_shot_timer = 0.0
	_from = global_position
	_aim = player().hit_center()
	if _overcharge and global_position.distance_to(player().global_position) < 40.0:
		var away := Course.to_world(Stage2.BAY_D, 0.0) - player().global_position
		away.y = 0.0
		_start_hop(player().global_position + (away.normalized() if away.length_squared() > 0.01 else model.global_basis.z) * 42.0)
	if attack == Attack.STOMP:
		_aim = _bounded(player().global_position)
		_aim.y = _floor(_aim)
	if attack == Attack.HOP:
		_aim = _perch(phase >= Phase.STRIPPED)
	if attack == Attack.SWEEP and global_position.distance_to(player().global_position) > SWEEP_REACH:
		_start_hop(player().global_position + (global_position - player().global_position).normalized() * SWEEP_REACH * 0.6)
	if attack == Attack.CHARGE:
		_aim = _bounded(_from + (_aim - _from).normalized() * 180.0)
		_aim.y = _floor(_aim)
	set_meta("locking", true)
	Sfx.play("warn", global_position, 2.0, 0.7)


func _perch(high := false) -> Vector3:
	var best := _bounded(global_position + _drift.normalized() * 30.0)
	var distance := INF
	for box in Course.structure_boxes:
		if box.get("kind", "") in (["ship"] if high else ["container", "city_deck"]) and absf(box.d - Stage2.BAY_D) < Stage2.BAY_RADIUS:
			var gap := global_position.distance_squared_to(box.pose.origin)
			if gap < distance:
				distance = gap
				best = box.pose.origin
	return best


func _wind() -> float:
	return (2.6 if _overcharge else float(WIND[_attack])) * Game.telegraph_scale()


func telegraphing() -> bool:
	return _attack != Attack.NONE and _attack_time < _wind()


func _end_attack() -> void:
	var previous := _attack
	_attack = Attack.NONE
	set_meta("locking", false)
	_next_attack = 0.18 if previous == Attack.HOP or phase == Phase.DESPERATE and previous in [Attack.SWEEP, Attack.CHARGE] else 1.1 if phase == Phase.DESPERATE else 1.5


func _update_attack(delta: float, tank: Tank) -> void:
	var world := World.current
	if _attack == Attack.NONE:
		_next_attack -= delta
		if _next_attack <= 0.0:
			_choose_attack()
		return
	_attack_time += delta
	var wind := _wind()
	if _attack_time < wind:
		match _attack:
			Attack.GUN, Attack.MISSILES:
				_aim = Gunnery.sensor_lead(tank, _muzzle.global_position, MG_SPEED)
				world.fx.beam(_body.global_position, _aim, Palette.HOT, 0.08, 0.06)
			Attack.RAIL:
				if _attack_time < wind - 0.8 * Game.telegraph_scale():
					_aim = tank.hit_center()
				aim_barrel(_rail, _aim, 8.0, delta)
				world.fx.beam(_muzzle.global_position, _aim, Palette.HOT, 0.35 if not _overcharge else 0.55, 0.06)
				# At melee range the muzzle line hides in the hull/smoke; its ground projection
				# still shows the entire sideways-dodge corridor, held still for the final 0.8 s.
				var line := (_aim - _muzzle.global_position) * Vector3(1, 0, 1)
				var ground := Vector3(_muzzle.global_position.x, Stage2.WATER_LEVEL + 0.3, _muzzle.global_position.z)
				world.fx.beam(ground, ground + line.normalized() * 180.0, Palette.HOT, 0.6 if _overcharge else 0.35, 0.06)
			Attack.CHARGE:
				world.fx.beam(Vector3(_from.x, maxf(_from.y, Stage2.WATER_LEVEL) + 0.3, _from.z), Vector3(_aim.x, maxf(_aim.y, Stage2.WATER_LEVEL) + 0.3, _aim.z), Palette.HOT, 0.7, 0.06)
			Attack.STOMP, Attack.HOP:
				var circle := _aim
				circle.y = maxf(circle.y, Water.surface_at(circle)) + 0.15
				world.fx.marker(circle, STOMP_REACH, 0.08, Palette.HOT)
			Attack.SWEEP:
				world.fx.marker(Vector3(global_position.x, maxf(global_position.y, Stage2.WATER_LEVEL) + 0.15, global_position.z), SWEEP_REACH, 0.08, Palette.HOT)
		return
	set_meta("locking", false)
	match _attack:
		Attack.RAIL:
			var from := _muzzle.global_position
			if not world.director.scenery.line_blocked(from, _aim):
				print("RAIL_FIRE phase=%d t=%.2f overcharge=%s" % [phase + 1, age, _overcharge])
				var shot := fire_at("shell", from, _aim, 1700.0, 50.0 if _overcharge else 35.0)
				shot.hit.kind = Hit.Kind.SHELL
				shot.hit.caliber = 100
				var to := shot.resolve_now(350.0)
				world.fx.beam(from, to, Palette.HOT, 0.8 if _overcharge else 0.45, 0.2)
			Sfx.play("cannon", from)
			_end_attack()
		Attack.GUN, Attack.MISSILES:
			_shot_timer -= delta
			if _shot_timer > 0.0:
				return
			# Cover buys time; it never becomes an invisible hitscan through the containers.
			if world.director.scenery.line_blocked(_body.global_position, _aim):
				_end_attack()
				return
			var missile := _attack == Attack.MISSILES
			var muzzle := _rack if missile else _guns[_shots % 2]
			aim_barrel(_rack if missile else muzzle.get_parent() as Node3D, _aim, 12.0, delta)
			var shot := fire_along("rocket" if missile else "orb", muzzle, 65.0 if missile else MG_SPEED, 0.0 if missile else 5.0, Palette.HOT, _aim - muzzle.global_position, 5.0, 0.02)
			shot.hit.caliber = 30
			if missile:
				shot.hit.kind = Hit.Kind.SHELL
				shot.blast_radius = 4.0 * SCALE
				shot.blast_damage = 20.0
				shot.homing_target = tank
				shot.turn_rate = 0.5
				shot.interceptable = true
				shot.intercept_hp = 0.7
				shot.trail = Projectile.ROCKET_SMOKE
			Sfx.play("launch" if missile else "enemy_gun", muzzle.global_position)
			_shots += 1
			_shot_timer = 0.16 if missile else 0.08
			if _shots >= (6 if missile else 12):
				_end_attack()
		Attack.CHARGE:
			var before := global_position
			var next := _bounded(before + (_aim - _from).normalized() * CHARGE_SPEED * delta * (skate_speed() / (SPEED[phase] as float)))
			if _floor(next) > global_position.y + 1.0:
				_end_attack()
				return
			next.y = _floor(next)
			global_position = next
			var closest := Geometry3D.get_closest_point_to_segment(tank.global_position, before, next)
			if Vector2(closest.x - tank.position.x, closest.z - tank.position.z).length() < radius + tank.radius:
				_melee(tank, 32.0)
				_end_attack()
			elif _attack_time > wind + 2.8 or global_position.distance_to(_aim) < radius:
				_end_attack()
		Attack.STOMP, Attack.HOP:
			if _shots == 0:
				_shots = 1
				_start_hop(_aim)
			elif _hop <= 0.0:
				world.fx.shockwave(global_position, STOMP_REACH * 2.0, Palette.HOT)
				world.shake(0.5, global_position)
				if _attack == Attack.STOMP:
					_area_hit(tank, STOMP_REACH, 35.0)
				_end_attack()
		Attack.SWEEP:
			model.rotation.y += delta * TAU * 1.5
			if _shots == 0:
				_shots = 1
				_area_hit(tank, SWEEP_REACH, 25.0)
			if _attack_time > wind + 0.7:
				_end_attack()


func _area_hit(tank: Tank, reach: float, damage: float) -> void:
	var distance := Vector2(global_position.x - tank.position.x, global_position.z - tank.position.z).length()
	if distance < reach and not World.current.director.scenery.line_blocked(global_position + Vector3.UP, tank.hit_center()):
		_melee(tank, damage * (1.0 - distance / reach))


func _melee(tank: Tank, damage: float) -> void:
	var hit := Hit.make(Hit.Kind.RAM, damage, tank.hit_center(), (tank.position - global_position).normalized())
	hit.source = self
	tank.take_hit(hit)


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	var best := -1.0
	for z in [-3.8, 0.0, 3.8]:
		var t := Entity.segment_sphere(from, to, _body.global_transform * Vector3(0, 0, z), 2.8 * SCALE + extra_radius)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	for leg in _legs:
		if leg.hp > 0.0:
			for joint: Node3D in [leg.knee, leg.hip]:
				var t := Entity.segment_sphere(from, to, joint.global_position, ACTUATOR_RADIUS + extra_radius)
				if t >= 0.0 and (best < 0.0 or t < best):
					best = t
	return best


func _actuator_hit(at: Vector3) -> bool:
	return _legs.any(func(leg: Dictionary) -> bool: return leg.hp > 0.0 and (at.distance_to((leg.knee as Node3D).global_position) <= ACTUATOR_RADIUS + 0.5 or at.distance_to((leg.hip as Node3D).global_position) <= ACTUATOR_RADIUS + 0.5))


func damage_multiplier(hit: Hit) -> float:
	var multiplier := super.damage_multiplier(hit) * (2.0 if spun > 0.0 else 1.0)
	if hit.kind == Hit.Kind.BULLET:
		return multiplier * frontal_armor(hit, 0.1)
	if hit.kind == Hit.Kind.SHELL and not hit.pierce and phase == Phase.SKATER and not _actuator_hit(hit.position):
		var facing := -model.global_basis.z
		if facing.dot(-hit.direction.normalized()) > 0.5:
			multiplier *= 0.65 # Sloped front; flank and actuators remain exposed.
	return multiplier


func take_hit(hit: Hit) -> void:
	# A direct cannon hit and its APHE splash are one hull strike, as on the gunship.
	if hit.kind == Hit.Kind.BLAST and hit.weapon == "cannon" and age - _shell_time < Gunship.SHELL_WINDOW:
		return
	super(hit)


func on_damaged(hit: Hit, amount: float) -> void:
	super(hit, amount)
	if hit.kind == Hit.Kind.SHELL and hit.caliber >= 100:
		_shell_time = age
	for leg in _legs:
		if leg.hp > 0.0 and (hit.position.distance_to((leg.knee as Node3D).global_position) <= ACTUATOR_RADIUS + 0.5 or hit.position.distance_to((leg.hip as Node3D).global_position) <= ACTUATOR_RADIUS + 0.5):
			leg.hp = maxf(0.0, leg.hp - amount)
			if leg.hp <= 0.0:
				_break_leg(leg, hit.direction)
				interrupt()
			break
	if hit.power >= 1.0:
		if _attack == Attack.RAIL and not _overcharge and _attack_time < 0.25:
			interrupt()
		# The tank meets the charge head-on: a full charge into its face mid-charge spins it out.
		if _attack == Attack.CHARGE and _attack_time >= _wind() and hit.direction.dot(_aim - _from) < 0.0 and hp > 0.0:
			_end_attack()
			spun = SPUN
			var world := World.current
			world.style_event("KNOCKDOWN", 150.0)
			world.hitstop(0.12)
			world.shake(0.6, global_position)
			world.fx.splash(global_position, 8.0, Stage2.WATER_LEVEL)
			Sfx.play("blast", global_position, 0.0, 0.7)
		_shed_plate(hit.direction)
	stagger = minf(stagger, 0.15) # Hull recoil cannot starve every attack under sustained fire.
	if phase == Phase.DESPERATE and hp <= max_hp * 0.13 and not _final_rail and _attack != Attack.RAIL:
		_end_attack()
		_next_attack = 0.2
	var next := Phase.DESPERATE if hp <= max_hp * PHASE_MARKS[1] else Phase.STRIPPED if hp <= max_hp * PHASE_MARKS[0] else Phase.SKATER
	if next > phase and hp > 0.0:
		phase = next
		_end_attack()
		_pattern = 0
		stagger = 0.0
		spun = 0.0 # The phase change's move takes over from a spin-out.
		if phase == Phase.STRIPPED:
			_transition = HOP_TIME
			_start_hop(_perch())
			while not _plates.is_empty():
				_shed_plate(hit.direction)
			_play_music()
		else:
			for leg in _legs:
				if leg.hp > 0.0:
					_break_leg(leg, hit.direction)
					break
			_transition = 2.4
			_hop = 0.0
			_transition_from = global_position
			var center := Course.to_world(Stage2.BAY_D, 0.0)
			_transition_to = _bounded(global_position.move_toward(center, 28.0))
			if _floor(_transition_to) > Stage2.WATER_LEVEL:
				_transition_to = center
			_transition_to.y = Course.height_at(_transition_to) - 3.5


func _break_leg(leg: Dictionary, direction: Vector3) -> void:
	leg.hp = 0.0
	var knee: Node3D = leg.knee
	World.current.fx.explosion(knee.global_position, 4.0)
	World.current.shake(0.6, knee.global_position)
	Sfx.play("blast", knee.global_position)
	Wreck.launch(knee, knee.global_position, ACTUATOR_RADIUS, true, direction * 14.0 + Vector3.UP * 8.0)


func _shed_plate(direction: Vector3) -> void:
	if _plates.is_empty():
		return
	var plate := _plates.pop_back() as Node3D
	Wreck.launch(plate, plate.global_position, 3.0, true, direction * 12.0 + Vector3.UP * 6.0)


func interrupt() -> void:
	super()
	_end_attack()


func on_death(hit: Hit) -> void:
	var world := World.current
	if world.boss == self:
		world.boss = null
	world.boss_changed.emit(null)
	boss = false
	super(hit)
