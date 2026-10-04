class_name Landsword
extends Enemy
## Low military hull on four reverse-jointed wheel legs. It skates around the bay, sheds armor,
## then fights on exposed rails and broken legs. Heavy shells tear off wheels; two lost force a crawl.

enum Phase { SKATER, STRIPPED, DESPERATE }
enum Attack { NONE, GUN, MISSILES, RAIL, CHARGE, STOMP, SWEEP }

const BODY_HP := 48000.0 ## Eight normal full-charge APHE hits; the gunship takes ten.
const PHASE_MARKS := [0.65, 0.30]
const LEG_HP := 100.0
const SCALE := 1.7 ## The whole machine is drawn this much larger than its model-space layout.
const WHEEL_RADIUS := 0.85 * SCALE
const SPEED := [30.0, 38.0, 62.0] ## The last phase is faster even with its first wheel gone.
const WIND := [0.0, 0.7, 1.0, 1.2, 1.0, 1.1, 0.9]
const STOMP_REACH := 20.0 ## Both reaches grow with the machine: 12 and 15 m at model size.
const SWEEP_REACH := 25.0
const CHARGE_SPEED := 68.0
const HOP_TIME := 1.0

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
var _orbit := 0.0
var _hop := 0.0
var _hop_from := Vector3.ZERO
var _hop_to := Vector3.ZERO
var _hop_height := 0.0
var _shell_time := -1.0


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
	set_meta("title", "BOSS_LANDSWORD")
	set_meta("phase_marks", PHASE_MARKS)


func build() -> void:
	model.scale = Vector3.ONE * SCALE
	_body.position.y = 4.4
	model.add_child(_body)
	var b := LowPoly.new()
	# A low white wedge: sloped glacis, a sensor visor across the prow, an armoured spine, twin tail fins
	# and thruster bells. No cockpit glass; the machine is its own pilot.
	b.box(Transform3D(Basis(), Vector3(0, 0.0, 0.3)), Vector3(3.8, 1.5, 8.6), Palette.WHITE, Palette.CREAM)
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 0.55, -4.6)), Vector3(3.4, 0.9, 3.4), Palette.WHITE, Palette.CREAM)
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.42), Vector3(0, 0.25, -6.0)), Vector3(2.8, 0.7, 2.4), Palette.MIST)
	b.box(Transform3D(Basis(), Vector3(0, -0.8, -0.2)), Vector3(2.6, 0.6, 9.6), Palette.INK)
	b.box(Transform3D(Basis(), Vector3(0, 1.0, 1.6)), Vector3(2.6, 0.8, 5.2), Palette.MIST, Palette.WHITE)
	b.box(Transform3D(Basis(), Vector3(0, 1.5, 1.6)), Vector3(1.4, 0.3, 4.4), Palette.ASH)
	b.box(Transform3D(Basis(), Vector3(0, 0.9, 5.0)), Vector3(3.0, 1.0, 1.0), Palette.DUSK)
	# Red flank stripes and hazard chevrons.
	for side in [-1.0, 1.0]:
		b.box(Transform3D(Basis(), Vector3(side * 1.92, 0.15, 0.3)), Vector3(0.05, 0.28, 8.0), Palette.CORAL)
		for i in 5:
			b.box(Transform3D(Basis(), Vector3(side * 1.93, -0.3, -2.0 + i * 1.4)), Vector3(0.04, 0.35, 0.3), Palette.INK)
		b.box(Transform3D(Basis(Vector3.BACK, side * -0.3), Vector3(side * 1.2, 2.0, 5.2)), Vector3(0.12, 1.9, 1.4), Palette.WHITE)
		b.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(side * 0.9, 0.5, 5.5)), 0.5, 0.5, 10, Palette.INK, 0.62)
	b.glow = true
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 0.82, -6.28)), Vector3(2.4, 0.16, 0.05), Palette.HOT)
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 0.62, -6.28)), Vector3(1.4, 0.07, 0.05), Palette.CORAL)
	for side in [-1.0, 1.0]:
		b.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(side * 0.9, 0.5, 5.95)), 0.4, 0.05, 10, Palette.CYAN)
	b.glow = false
	_add_mesh(_body, b.mesh())
	for side in [-1.0, 1.0]:
		var plate := Node3D.new()
		plate.position = Vector3(side * 2.4, 0.1, 0)
		_body.add_child(plate)
		var p := LowPoly.new()
		for z in [-2.6, 0.0, 2.6]:
			p.box(Transform3D(Basis(Vector3.BACK, side * -0.2), Vector3(0, 0, z)), Vector3(0.4, 1.6, 2.4), Palette.WHITE, Palette.MIST)
			p.box(Transform3D(Basis(Vector3.BACK, side * -0.2), Vector3(side * 0.22, 0.2, z)), Vector3(0.05, 0.4, 2.0), Palette.CORAL)
		p.box(Transform3D(Basis(), Vector3(side * 0.24, 0.55, 0)), Vector3(0.05, 0.12, 7.4), Palette.BUTTER)
		_add_mesh(plate, p.mesh())
		_plates.append(plate)
		var gun := Node3D.new()
		gun.position = Vector3(side * 1.6, -0.1, -5.2)
		_body.add_child(gun)
		var g := LowPoly.new()
		g.box(Transform3D(), Vector3(0.6, 0.6, 1.1), Palette.DUSK)
		g.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -0.5)), 0.28, 0.4, 8, Palette.ASH)
		for off in [-0.1, 0.1]:
			g.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(off, 0, -0.4)), 0.08, 2.1, 8, Palette.INK)
		_add_mesh(gun, g.mesh())
		var muzzle := Node3D.new()
		muzzle.position.z = -2.5
		gun.add_child(muzzle)
		_guns.append(muzzle)
	_rail.position = Vector3(0, 1.1, -1.6)
	_body.add_child(_rail)
	var r := LowPoly.new()
	r.box(Transform3D(), Vector3(1.8, 1.0, 2.6), Palette.WHITE, Palette.CREAM)
	r.box(Transform3D(Basis(), Vector3(0, 0.55, 0.4)), Vector3(1.3, 0.2, 1.8), Palette.CORAL)
	for x in [-0.45, 0.45]:
		r.box(Transform3D(Basis(), Vector3(x, 0, -3.4)), Vector3(0.32, 0.5, 5.8), Palette.DUSK)
		r.box(Transform3D(Basis(), Vector3(x, 0.3, -3.4)), Vector3(0.1, 0.06, 5.4), Palette.CORAL)
	r.glow = true
	r.box(Transform3D(Basis(), Vector3(0, 0.0, -2.5)), Vector3(0.58, 0.12, 0.3), Palette.CYAN)
	r.glow = false
	r.box(Transform3D(Basis(), Vector3(0, 0, -6.2)), Vector3(1.3, 0.8, 0.5), Palette.ASH)
	_add_mesh(_rail, r.mesh())
	_muzzle.position.z = -6.5
	_rail.add_child(_muzzle)
	_rack.position = Vector3(0, 1.6, 3.4)
	_body.add_child(_rack)
	var rack := LowPoly.new()
	rack.box(Transform3D(), Vector3(3.8, 1.2, 2.4), Palette.MIST, Palette.WHITE)
	for x in [-1.3, -0.45, 0.45, 1.3]:
		rack.tube(Transform3D(Basis(Vector3.RIGHT, -PI * 0.35), Vector3(x, 0.5, -0.8)), 0.27, 1.0, 6, Palette.INK)
		rack.box(Transform3D(Basis(Vector3.RIGHT, -PI * 0.35), Vector3(x, 0.8, -1.2)), Vector3(0.3, 0.3, 0.1), Palette.CORAL)
	_add_mesh(_rack, rack.mesh())
	# Hips splay out; the knee folds back and the shin returns forward to the wheel hub.
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var hip := Node3D.new()
		hip.position = Vector3(corner.x * 2.2, -0.5, corner.y * 3.1)
		_body.add_child(hip)
		var thigh := LowPoly.new()
		thigh.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO), 0.7, 0.7, 8, Palette.ASH)
		thigh.box(Transform3D(Basis(Vector3.BACK, corner.x * -0.6), Vector3(corner.x * 0.9, -0.8, 0.8)), Vector3(0.8, 2.2, 1.0), Palette.WHITE, Palette.MIST)
		thigh.box(Transform3D(Basis(Vector3.BACK, corner.x * -0.6), Vector3(corner.x * 1.0, -0.6, 1.32)), Vector3(0.5, 1.4, 0.06), Palette.CORAL)
		_add_mesh(hip, thigh.mesh())
		var knee := Node3D.new()
		knee.position = Vector3(corner.x * 1.7, -1.5, 1.3)
		hip.add_child(knee)
		var shin := LowPoly.new()
		shin.blob(Transform3D(), 0.6, Palette.CORAL)
		shin.box(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(corner.x * 0.4, -0.9, -0.6)), Vector3(0.6, 2.3, 0.75), Palette.ASH, Palette.MIST)
		shin.tube(Transform3D(Basis(Vector3.RIGHT, PI * 0.65), Vector3(0, -0.2, -0.3)), 0.15, 1.7, 6, Palette.BUTTER)
		_add_mesh(knee, shin.mesh())
		var wheel := Node3D.new()
		wheel.position = Vector3(corner.x * 1.0, -1.55, -1.3)
		knee.add_child(wheel)
		var w := LowPoly.new()
		w.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO), WHEEL_RADIUS / SCALE, 0.7, 14, Palette.INK)
		w.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(corner.x * 0.35, 0, 0)), 0.58, 0.06, 10, Palette.WHITE)
		w.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(corner.x * 0.4, 0, 0)), 0.18, 0.06, 6, Palette.CORAL)
		_add_mesh(wheel, w.mesh())
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
	if is_staggered():
		_end_attack()
		_drift = _drift.move_toward(Vector3.ZERO, delta * 80.0)
	elif _hop <= 0.0 and _attack not in [Attack.RAIL, Attack.CHARGE, Attack.STOMP, Attack.SWEEP]:
		var center := Course.to_world(Stage2.BAY_D, 0.0)
		_orbit += delta * skate_speed() / 72.0
		var goal := center + Vector3(cos(_orbit), 0, sin(_orbit)) * 72.0
		var desired := (goal - global_position).normalized() * skate_speed()
		if _attack != Attack.NONE:
			desired *= 0.2 # A planted gun is a full-charge opening.
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
	global_position = _bounded(global_position)
	var toward := tank.hit_center() - _body.global_position
	if _attack not in [Attack.RAIL, Attack.CHARGE, Attack.SWEEP]:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-toward.x, -toward.z), minf(1.0, delta * 3.5))
	_animate(delta)
	if not is_staggered() and (_hop <= 0.0 or _attack == Attack.STOMP):
		_update_attack(delta, tank)


func _animate(delta: float) -> void:
	_body.position.y = lerpf(_body.position.y, 1.8 if legs_lost() >= 2 else 4.4, minf(1.0, delta * 6.0))
	_body.rotation.z = lerpf(_body.rotation.z, clampf(-_drift.dot(model.global_basis.x) * 0.009, -0.3, 0.3), minf(1.0, delta * 4.0))
	for leg in _legs:
		var knee: Node3D = leg.knee
		knee.rotation.x = lerpf(knee.rotation.x, 0.9 if leg.hp <= 0.0 else -0.35 if _hop > 0.0 else 0.0, minf(1.0, delta * 6.0))
		if leg.hp > 0.0:
			(leg.wheel as Node3D).rotation.x -= _drift.length() * delta / WHEEL_RADIUS


func _choose_attack() -> void:
	var options: Array[Attack] = [Attack.GUN]
	if phase >= Phase.STRIPPED:
		options.append_array([Attack.MISSILES, Attack.CHARGE])
	if phase == Phase.DESPERATE:
		options.append_array([Attack.RAIL, Attack.STOMP, Attack.SWEEP])
	if legs_lost() >= 2:
		options = options.filter(func(attack: Attack) -> bool: return attack not in [Attack.CHARGE, Attack.STOMP, Attack.SWEEP])
	_begin_attack(options[_pattern % options.size()])
	_pattern += 1


func _begin_attack(attack: Attack) -> void:
	_attack = attack
	_attack_time = 0.0
	_shots = 0
	_shot_timer = 0.0
	_from = global_position
	_aim = player().hit_center()
	if attack == Attack.STOMP:
		_aim = _bounded(player().global_position)
		_aim.y = _floor(_aim)
	if attack == Attack.CHARGE:
		_aim = _bounded(_from + (_aim - _from).normalized() * 180.0)
		_aim.y = _floor(_aim)
	set_meta("locking", true)
	Sfx.play("warn", global_position, 2.0, 0.7)


func telegraphing() -> bool:
	return _attack != Attack.NONE and _attack_time < (WIND[_attack] as float) * Game.telegraph_scale()


func _end_attack() -> void:
	_attack = Attack.NONE
	set_meta("locking", false)
	_next_attack = 2.0 if phase != Phase.DESPERATE else 1.5


func _update_attack(delta: float, tank: Tank) -> void:
	var world := World.current
	if _attack == Attack.NONE:
		_next_attack -= delta
		if _next_attack <= 0.0:
			_choose_attack()
		return
	_attack_time += delta
	var wind := (WIND[_attack] as float) * Game.telegraph_scale()
	if _attack_time < wind:
		match _attack:
			Attack.GUN, Attack.MISSILES:
				_aim = Gunnery.sensor_lead(tank, _muzzle.global_position, MG_SPEED)
				world.fx.beam(_body.global_position, _aim, Palette.HOT, 0.08, 0.06)
			Attack.RAIL:
				if _attack_time < wind - 0.45 * Game.telegraph_scale():
					_aim = tank.hit_center()
				aim_barrel(_rail, _aim, 8.0, delta)
				world.fx.beam(_muzzle.global_position, _aim, Palette.HOT, 0.16, 0.06)
			Attack.CHARGE:
				world.fx.beam(_from + Vector3.UP * 0.2, _aim + Vector3.UP * 0.2, Palette.HOT, 0.7, 0.06)
			Attack.STOMP:
				world.fx.marker(_aim, STOMP_REACH, delta * 2.0, Palette.HOT)
			Attack.SWEEP:
				world.fx.marker(global_position, SWEEP_REACH, delta * 2.0, Palette.HOT)
		return
	set_meta("locking", false)
	match _attack:
		Attack.GUN, Attack.MISSILES, Attack.RAIL:
			_shot_timer -= delta
			if _shot_timer > 0.0:
				return
			# Cover buys time; it never becomes an invisible hitscan through the containers.
			if world.director.scenery.line_blocked(_body.global_position, _aim):
				_end_attack()
				return
			var missile := _attack == Attack.MISSILES
			var muzzle := _muzzle if _attack == Attack.RAIL else _rack if missile else _guns[_shots % 2]
			aim_barrel(muzzle.get_parent() as Node3D if _attack != Attack.MISSILES else _rack, _aim, 12.0, delta)
			var shot := fire_along("rocket" if missile else "shell" if _attack == Attack.RAIL else "orb", muzzle, 65.0 if missile else 480.0 if _attack == Attack.RAIL else MG_SPEED, 0.0 if missile else 35.0 if _attack == Attack.RAIL else 5.0, Palette.HOT, _aim - muzzle.global_position, 5.0, 0.0 if _attack == Attack.RAIL else 0.02)
			shot.hit.caliber = 100 if _attack == Attack.RAIL else 30
			if missile or _attack == Attack.RAIL:
				shot.hit.kind = Hit.Kind.SHELL
			if missile:
				shot.blast_radius = 4.0 * SCALE
				shot.blast_damage = 20.0
				shot.homing_target = tank
				shot.turn_rate = 0.5
				shot.interceptable = true
				shot.intercept_hp = 0.7
				shot.trail = Projectile.ROCKET_SMOKE
			Sfx.play("launch" if missile else "cannon" if _attack == Attack.RAIL else "enemy_gun", muzzle.global_position)
			_shots += 1
			_shot_timer = 0.16 if missile else 0.08
			if _shots >= (6 if missile else 1 if _attack == Attack.RAIL else 12):
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
		Attack.STOMP:
			if _shots == 0:
				_shots = 1
				_start_hop(_aim)
			elif _hop <= 0.0:
				world.fx.shockwave(global_position, STOMP_REACH * 2.0, Palette.HOT)
				world.shake(0.5, global_position)
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
			var t := Entity.segment_sphere(from, to, (leg.wheel as Node3D).global_position, WHEEL_RADIUS + extra_radius)
			if t >= 0.0 and (best < 0.0 or t < best):
				best = t
	return best


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
		if leg.hp > 0.0 and hit.position.distance_to((leg.wheel as Node3D).global_position) <= WHEEL_RADIUS + 0.5:
			leg.hp = maxf(0.0, leg.hp - amount)
			if leg.hp <= 0.0:
				_break_leg(leg, hit.direction)
				interrupt()
			break
	if hit.power >= 1.0:
		interrupt()
		_shed_plate(hit.direction)
	var next := Phase.DESPERATE if hp <= max_hp * PHASE_MARKS[1] else Phase.STRIPPED if hp <= max_hp * PHASE_MARKS[0] else Phase.SKATER
	if next > phase and hp > 0.0:
		phase = next
		interrupt()
		while not _plates.is_empty():
			_shed_plate(hit.direction)
		if phase == Phase.DESPERATE and legs_lost() == 0:
			_break_leg(_legs[2], hit.direction)
		_play_music()


func _break_leg(leg: Dictionary, direction: Vector3) -> void:
	leg.hp = 0.0
	var wheel: Node3D = leg.wheel
	World.current.fx.explosion(wheel.global_position, 2.0)
	Wreck.launch(wheel, wheel.global_position, WHEEL_RADIUS, true, direction * 14.0 + Vector3.UP * 8.0)


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
