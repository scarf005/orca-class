class_name Hovercraft
extends Enemy
## Plaza mid-boss: an air-cushion landing craft with two ducted fans, twin autocannons and a bow gun.
## Shells break the laser and fans; overlapping missile salvos exhaust the laser's shared heat.
## At half hull the flank plates and fan cowls tear off, and the rear rocket rack joins the fight.

enum Phase { ARMORED, STRIPPED }
enum Attack { NONE, GUN, CANNON, RAM, MLRS }

const SCALE := 1.3 ## Drawn this much larger than its model-space layout.
const BODY_HP := 1900.0
const ROUND_DAMAGE := 40.0 ## Like the colossus, main-gun damage counts in rounds, not the tank's raw thousands.
const SPEED := 32.0
const RAM_SPEED := 65.0
const LASER_RANGE := 30.0
const LASER_DPS := 6.0
const LASER_HEAT := 0.24 ## Heat per interception: four missiles fit, an overlapping salvo gets through.
const LASER_COOL := 0.3
const WIND := 1.0
const WINDOW := 1.6 ## A full charge and its aim fit between attacks.
const PARTS := {"fan_l": Vector3(-4.0, 3.4, 5.0), "fan_r": Vector3(4.0, 3.4, 5.0), "laser": Vector3(0, 3.5, -1.0)}
const LABELS := {"fan_l": "HOVER_FAN_L", "fan_r": "HOVER_FAN_R", "laser": "HOVER_LASER"}

var phase := Phase.ARMORED
var parts := {"fan_l": 100.0, "fan_r": 100.0, "laser": 70.0}
var laser_heat := 0.0
var laser_overheated := false
var _part_nodes: Dictionary[String, Node3D] = {}
var _fans: Array[Node3D] = []
var _plates: Array[Node3D] = []
var _guns: Array[Node3D] = []
var _muzzles: Array[Node3D] = []
var _emitters: Array[Node3D] = []
var _bow := Node3D.new()
var _bow_muzzle := Node3D.new()
var _rack := Node3D.new()
var _rack_muzzle := Node3D.new()
var _attack := Attack.NONE
var _attack_time := 0.0
var _next_attack := 2.0
var _shots := 0
var _shot_timer := 0.0
var _angle := 0.0
var _pattern := 0
var _aim := Vector3.ZERO
var _ram_direction := Vector3.ZERO
var _ram_hit := false
var _wake := 0.0
var _dying := 0.0


func _init() -> void:
	super()
	boss = true
	heavy = true
	max_hp = BODY_HP
	hp = max_hp
	armor = 25.0
	radius = 7.0 * SCALE
	center_height = 2.0 * SCALE
	score = 20000
	despawn_behind = 0.0
	set_meta("title", "BOSS_HOVERCRAFT")
	set_meta("phase_marks", [0.5])


func build() -> void:
	model.scale = Vector3.ONE * SCALE
	var b := LowPoly.new()
	# An air-cushion landing craft: a black skirt bulging out over the water, a flat grey deck with an open cargo well,
	# long deckhouses down both sides, a hazard-striped bow ramp, and the hull number on the bridge.
	b.frustum(Transform3D(Basis(), Vector3(0, 0.0, 0)), Vector2(9.0, 13.4), Vector2(10.8, 15.0), 1.0, Palette.INK)
	b.frustum(Transform3D(Basis(), Vector3(0, 1.0, 0)), Vector2(10.8, 15.0), Vector2(10.0, 14.2), 0.6, Palette.DUSK)
	b.box(Transform3D(Basis(), Vector3(0, 1.85, 0.4)), Vector3(9.8, 0.5, 13.0), Palette.ASH, Palette.STONE)
	b.box(Transform3D(Basis(), Vector3(0, 2.12, 0.0)), Vector3(4.6, 0.06, 10.0), Palette.SLATE)
	for i in 5:
		b.box(Transform3D(Basis(), Vector3(0, 2.16, -4.0 + i * 2.0)), Vector3(4.4, 0.03, 0.1), Palette.BUTTER)
	b.frustum(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 1.6, -6.6)), Vector2(4.6, 0.25), Vector2(4.6, 0.25), 2.2, Palette.STONE)
	for i in 5:
		b.box(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(-1.8 + i * 0.9, 2.1, -6.95)), Vector3(0.45, 0.04, 0.9), Palette.CORAL if i % 2 == 0 else Palette.INK)
	for side in [-1.0, 1.0]:
		# Deckhouse: a long low cabin with a raked front, windows at the bow end and lift fan grilles on its roof.
		b.frustum(Transform3D(Basis(), Vector3(side * 3.6, 2.1, 0.4)), Vector2(2.2, 11.0), Vector2(1.9, 10.2), 1.5, Palette.HULL_LIGHT, Palette.ASH, Vector2(0, 0.4))
		b.glow = true
		b.box(Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(side * 3.6, 3.15, -4.6)), Vector3(1.6, 0.32, 0.05), Palette.CYAN)
		b.glow = false
		for z in [-1.0, 2.6]:
			b.prism(Transform3D(Basis(), Vector3(side * 3.6, 3.6, z)), 0.75, 0.12, 12, Palette.INK)
			b.prism(Transform3D(Basis(), Vector3(side * 3.6, 3.7, z)), 0.6, 0.04, 12, Palette.SLATE)
		b.box(Transform3D(Basis(), Vector3(side * 4.65, 2.8, 0.4)), Vector3(0.06, 0.24, 10.0), Palette.CORAL)
	# Bridge on the starboard deckhouse: a raised cab with wrap-around glazing, a mast and a radar.
	b.frustum(Transform3D(Basis(), Vector3(3.6, 3.6, -2.6)), Vector2(1.8, 2.2), Vector2(1.6, 1.8), 1.0, Palette.HULL_LIGHT, Palette.WHITE)
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(3.6, 4.2, -3.55)), Vector3(1.5, 0.3, 0.05), Palette.CYAN)
	b.box(Transform3D(Basis(), Vector3(3.6, 6.25, -2.6)), Vector3(0.25, 0.25, 0.25), Palette.HOT)
	b.glow = false
	b.box(Transform3D(Basis(), Vector3(3.6, 5.3, -2.6)), Vector3(0.12, 1.8, 0.12), Palette.ASH)
	b.box(Transform3D(Basis(), Vector3(3.6, 5.6, -2.6)), Vector3(1.6, 0.12, 0.35), Palette.INK)
	b.box(Transform3D(Basis(), Vector3(4.71, 3.0, -1.2)), Vector3(0.04, 0.5, 1.1), Palette.WHITE)
	for x in [4.72]:
		for i in 3:
			b.box(Transform3D(Basis(), Vector3(x, 3.0, -1.55 + i * 0.35)), Vector3(0.05, 0.36, 0.22), Palette.INK)
	_add_mesh(model, b.mesh())
	for side in [-1.0, 1.0]:
		var name := "fan_l" if side < 0.0 else "fan_r"
		var fan := Node3D.new()
		fan.position = PARTS[name]
		model.add_child(fan)
		_part_nodes[name] = fan
		# Propulsion: a deep ducted shroud on a pylon with twin rudders behind it.
		var duct := LowPoly.new()
		for i in 16:
			var a := TAU * i / 16.0
			duct.box(Transform3D(Basis(Vector3.FORWARD, a), Vector3(sin(a), cos(a), 0) * 2.1), Vector3(0.9, 0.3, 1.8), Palette.SLATE)
		duct.box(Transform3D(Basis(), Vector3(0, -2.25, 0)), Vector3(0.5, 0.6, 1.2), Palette.DUSK)
		for x in [-0.8, 0.8]:
			duct.box(Transform3D(Basis(), Vector3(x, 0, 1.6)), Vector3(0.12, 3.6, 1.0), Palette.HULL_LIGHT)
		duct.box(Transform3D(Basis(), Vector3(0, 2.0, 0)), Vector3(0.3, 0.06, 1.7), Palette.CORAL)
		_add_mesh(fan, duct.mesh())
		var rotor := Node3D.new()
		fan.add_child(rotor)
		var blades := LowPoly.new()
		blades.tube(Transform3D(Basis(), Vector3(0, 0, -0.4)), 0.35, 0.8, 8, Palette.INK)
		for i in 4:
			blades.box(Transform3D(Basis(Vector3.FORWARD, i * PI * 0.5) * Basis(Vector3.UP, 0.35), Vector3.ZERO), Vector3(0.3, 3.7, 0.08), Palette.ASH)
		_add_mesh(rotor, blades.mesh())
		_fans.append(rotor)
		var plate := Node3D.new()
		plate.position = Vector3(side * 4.75, 2.6, 0.4)
		model.add_child(plate)
		_add_mesh(plate, LowPoly.new().frustum(Transform3D(Basis(Vector3.BACK, side * -0.2), Vector3(0, -0.8, 0)), Vector2(0.3, 9.4), Vector2(0.24, 8.8), 1.4, Palette.STONE).mesh())
		_plates.append(plate)
		var gun := _weapon(Vector3(side * 3.6, 3.6, -0.2 if side < 0.0 else 0.6), 1, 2.5)
		_guns.append(gun)
		_muzzles.append(gun.get_node("Muzzle"))
	var laser := Node3D.new()
	laser.position = PARTS.laser
	model.add_child(laser)
	_part_nodes.laser = laser
	for side in [-1.0, 1.0]:
		var emitter := Node3D.new()
		emitter.position.x = side * 0.7
		laser.add_child(emitter)
		var lens := LowPoly.new()
		lens.box(Transform3D(), Vector3(0.8, 0.6, 1.0), Palette.SLATE)
		lens.glow = true
		lens.box(Transform3D(Basis(), Vector3(0, 0, -0.55)), Vector3(0.5, 0.35, 0.1), Palette.HOT)
		_add_mesh(emitter, lens.mesh())
		_emitters.append(emitter)
	_bow = _weapon(Vector3(0, 2.3, -5.6), 1, 4.0)
	_bow_muzzle = _bow.get_node("Muzzle")
	_rack = _weapon(Vector3(0, 3.1, 4.2), 6, 1.6)
	_rack_muzzle = _rack.get_node("Muzzle")


func _add_mesh(parent: Node3D, mesh: Mesh) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	parent.add_child(node)


func _weapon(at: Vector3, barrels: int, length: float) -> Node3D:
	var node := Node3D.new()
	node.position = at
	model.add_child(node)
	var b := LowPoly.new()
	b.prism(Transform3D(Basis(), Vector3(0, -0.55, 0)), 0.75, 0.3, 10, Palette.DUSK)
	b.frustum(Transform3D(Basis(), Vector3(0, -0.4, 0.1)), Vector2(1.6, 1.8), Vector2(1.2, 1.1), 0.85, Palette.WHITE, Palette.MIST, Vector2(0, 0.2))
	b.box(Transform3D(Basis(), Vector3(0, 0.47, 0.3)), Vector3(0.8, 0.06, 0.7), Palette.CORAL)
	for i in barrels:
		var x := (i - (barrels - 1) * 0.5) * 0.4
		b.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0, -0.8)), 0.15, length, 6, Palette.INK)
		b.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0, -0.8 - length * 0.9)), 0.2, length * 0.14, 6, Palette.ASH)
	_add_mesh(node, b.mesh())
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position.z = -0.8 - length
	node.add_child(muzzle)
	return node


func aim_parts() -> Dictionary:
	var result := {}
	if _dying > 0.0:
		return result
	for name: String in parts:
		if parts[name] > 0.0:
			result[name] = [model.global_transform * PARTS[name], (2.2 if name != "laser" else 1.2) * SCALE, tr(LABELS[name])]
	result["rear"] = [model.global_transform * Vector3(0, 2, 6), 2.0, tr("HOVER_REAR")]
	return result


func module_states() -> Array:
	return parts.keys().map(func(name: String) -> Array: return [tr(LABELS[name]), maxf(parts[name], 0.0) / (70.0 if name == "laser" else 100.0)])


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	if _dying > 0.0:
		return -1.0
	var best := Entity.segment_sphere(from, to, hit_center(), radius + extra_radius)
	for spec: Array in aim_parts().values():
		var distance := Entity.segment_sphere(from, to, spec[0], spec[1] + extra_radius)
		if distance >= 0.0 and (best < 0.0 or distance < best):
			best = distance
	return best


func take_hit(hit: Hit) -> void:
	if dead or invulnerable or _dying > 0.0 or hit.damage <= 0.0:
		return
	var amount := hit.damage * damage_multiplier(hit)
	if (hit.kind == Hit.Kind.SHELL and (hit.caliber >= 100 or hit.weapon == "cannon")) or (hit.kind == Hit.Kind.BLAST and hit.weapon == "cannon"):
		amount *= ROUND_DAMAGE / Armament.SHELL_DAMAGE
	if hit.kind == Hit.Kind.SHELL:
		var local := model.to_local(hit.position)
		for name: String in parts:
			if parts[name] > 0.0 and local.distance_to(PARTS[name]) <= (2.6 if name != "laser" else 1.6):
				parts[name] -= amount
				if parts[name] <= 0.0:
					_break_part(name, hit.direction)
				break
	if model.to_local(hit.position).z > 4.0:
		amount *= 1.5
	hp = maxf(0.0, hp - amount)
	impact_feedback(hit, amount, hp <= 0.0)
	if hit.power >= 1.0 or hit.stagger >= 1.0:
		stagger = maxf(stagger, 0.2)
		if _attack == Attack.RAM and _attack_time < 0.25:
			_end_attack()
	if hp <= 0.0:
		killing_hit = hit.copy()
		_dying = 1.0
		_end_attack()
		World.current.hitstop(0.15)
	elif phase == Phase.ARMORED and hp <= max_hp * 0.5:
		phase = Phase.STRIPPED
		_pattern = 3 # The newly exposed rack answers immediately, not after another full cycle.
		for plate in _plates:
			Wreck.launch(plate, plate.global_position, 2.0, true, Vector3.UP * 8.0)
		# The fan cowls peel off; the exposed rotors keep working until shot out.
		for name: String in ["fan_l", "fan_r"]:
			if parts[name] > 0.0:
				var cowl := _part_nodes[name].get_child(0) as Node3D
				Wreck.launch(cowl, cowl.global_position, 2.0, true, Vector3.UP * 8.0)
		World.current.fx.explosion(hit_center(), 4.0)
		Sfx.play("blast", global_position)


func _break_part(name: String, direction: Vector3) -> void:
	parts[name] = 0.0
	var node := _part_nodes[name]
	World.current.fx.explosion(node.global_position, 2.0)
	Wreck.launch(node, node.global_position, 2.0, true, direction * 8.0 + Vector3.UP * 5.0)


func move_speed() -> float:
	var fans := int(parts.fan_l > 0.0) + int(parts.fan_r > 0.0)
	return SPEED * (1.4 if phase == Phase.STRIPPED else 1.0) * (0.4 + 0.3 * fans)


func arena_center() -> Vector3:
	return Course.to_world(Stage2.PLAZA_D, 0.0)


func _bound() -> void:
	var center := arena_center()
	var offset := global_position - center
	offset.y = 0.0
	global_position = center + offset.limit_length(Stage2.PLAZA_RADIUS - radius)
	global_position.y = maxf(Course.height_at(global_position), Water.surface_at(global_position)) + 0.15


func behave(delta: float) -> void:
	var world := World.current
	if _dying > 0.0:
		_dying -= delta
		world.fx.smoke(hit_center(), 1, 3.0)
		if _dying <= 0.0:
			die(killing_hit)
		return
	_bound()
	_update_laser(delta)
	for i in _fans.size():
		if parts["fan_l" if i == 0 else "fan_r"] > 0.0:
			_fans[i].rotation.z += delta * 30.0
	var listing := 0.22 if parts.fan_l <= 0.0 and parts.fan_r > 0.0 else -0.22 if parts.fan_r <= 0.0 and parts.fan_l > 0.0 else 0.0
	model.rotation.z = lerpf(model.rotation.z, listing, minf(delta * 4.0, 1.0))
	var tank := player()
	if tank == null or is_staggered():
		return
	var before := global_position
	if _attack not in [Attack.CANNON, Attack.RAM]:
		_angle += move_speed() / 46.0 * delta
		var goal := arena_center() + Vector3(cos(_angle), 0, sin(_angle)) * 46.0
		global_position = global_position.move_toward(Vector3(goal.x, global_position.y, goal.z), move_speed() * delta)
	var toward := tank.global_position - global_position
	model.rotation.y = lerp_angle(model.rotation.y, atan2(-toward.x, -toward.z), minf(delta * 3.0, 1.0))
	for gun in _guns:
		aim_barrel(gun, _aim if _attack == Attack.GUN else tank.hit_center(), 5.0, delta)
	aim_barrel(_bow, _aim if _attack == Attack.CANNON else tank.hit_center(), 5.0, delta)
	if _attack == Attack.MLRS:
		slew_barrel(_rack, _rocket_velocity(_rocket_target()), 5.0, delta)
	else:
		aim_barrel(_rack, tank.hit_center() + Vector3.UP * 8.0, 5.0, delta)
	_wake -= delta
	if _wake <= 0.0:
		_wake = 0.12
		var surface := maxf(Course.height_at(global_position), Water.surface_at(global_position))
		world.fx.wake(global_position, (global_position - before) / maxf(delta, 0.001), 5.0, surface)
		world.fx.splash(global_position + model.global_basis.z * 5.0, 2.0, surface)
	_update_attack(delta, tank)
	_bound()


func _update_laser(delta: float) -> void:
	if parts.laser <= 0.0:
		return
	if laser_overheated:
		laser_heat = maxf(0.0, laser_heat - LASER_COOL * delta)
		if laser_heat <= 0.25:
			laser_overheated = false
		return
	var targets: Array[Projectile] = []
	for shot in World.current.projectiles:
		if shot.team != Team.PLAYER or shot.shape not in ["atgm", "micro", "rocket"] or shot.is_queued_for_deletion():
			continue
		if shot.global_position.distance_to(hit_center()) <= LASER_RANGE and CityCover.blocker(_part_nodes.laser.global_position, shot.global_position) == null:
			targets.append(shot)
	targets.sort_custom(func(a: Projectile, b: Projectile) -> bool: return a.global_position.distance_squared_to(hit_center()) < b.global_position.distance_squared_to(hit_center()))
	if targets.is_empty():
		laser_heat = maxf(0.0, laser_heat - LASER_COOL * delta)
	for i in mini(2, targets.size()):
		var shot := targets[i]
		World.current.fx.beam(_emitters[i].global_position, shot.global_position, Palette.HOT, 0.12, 0.05)
		if shot.laser(LASER_DPS * delta):
			laser_heat += LASER_HEAT
			Sfx.play("zap", _emitters[i].global_position, -4.0)
		laser_heat += delta * 0.6
		if laser_heat >= 1.0:
			laser_heat = 1.0
			laser_overheated = true
			break


func telegraphing() -> bool:
	return _attack != Attack.NONE and _attack_time < WIND * Game.telegraph_scale()


func _begin_attack(kind: Attack) -> void:
	if kind == Attack.MLRS and phase == Phase.ARMORED:
		return
	_attack = kind
	print("ATTACK kind=hovercraft attack=%s phase=%d t=%.2f" % [Attack.keys()[kind], phase + 1, age])
	_attack_time = 0.0
	_shots = 0
	_shot_timer = 0.0
	_ram_hit = false
	_aim = player().hit_center()
	if kind in [Attack.CANNON, Attack.MLRS]:
		_aim.y = maxf(Course.height_at(_aim), Water.surface_at(_aim))
	_ram_direction = (_aim - global_position) * Vector3(1, 0, 1)
	_ram_direction = _ram_direction.normalized()
	var world := World.current
	if kind == Attack.RAM:
		var from := global_position + Vector3.UP * 0.6
		world.fx.beam(from, from + _ram_direction * 120.0, Palette.HOT, 0.6, WIND * Game.telegraph_scale())
		for i in 10:
			var at := global_position + _ram_direction * i * 12.0
			if at.distance_to(arena_center()) <= Stage2.PLAZA_RADIUS:
				world.fx.marker(at, radius, WIND * Game.telegraph_scale(), Palette.HOT)
	else:
		world.fx.beam(hit_center(), _aim, Palette.HOT, 0.12, WIND * Game.telegraph_scale())
		if kind in [Attack.CANNON, Attack.MLRS]:
			world.fx.marker(_aim, 4.5, WIND * Game.telegraph_scale(), Palette.RED)
	Sfx.play("warn", global_position)


func _end_attack() -> void:
	_attack = Attack.NONE
	_next_attack = WINDOW


func _update_attack(delta: float, tank: Tank) -> void:
	if _attack == Attack.NONE:
		_next_attack -= delta
		if _next_attack <= 0.0:
			var options := [Attack.GUN, Attack.CANNON, Attack.RAM]
			if phase == Phase.STRIPPED:
				options.append(Attack.MLRS)
			_begin_attack(options[_pattern % options.size()])
			_pattern += 1
		return
	_attack_time += delta
	if telegraphing():
		return
	_shot_timer -= delta
	match _attack:
		Attack.GUN:
			if _shot_timer <= 0.0:
				for muzzle in _muzzles:
					var shot := fire_along("bullet", muzzle, MG_SPEED, 6.0, Palette.HOT, _aim - muzzle.global_position, 3.0, 0.015, Muzzle.AUTO)
					shot.hit.caliber = 30
				_shots += 1
				_shot_timer = 0.12
				Sfx.play("enemy_gun", global_position)
				if _shots >= 8:
					_end_attack()
		Attack.CANNON:
			var shot := fire_along("shell", _bow_muzzle, 180.0, 20.0, Palette.HOT, _aim - _bow_muzzle.global_position)
			shot.hit.kind = Hit.Kind.SHELL
			shot.hit.caliber = 100
			shot.blast_radius = 4.5
			shot.blast_damage = 25.0
			shot.interceptable = true
			shot.intercept_hp = 6.0
			Sfx.play("cannon", _bow_muzzle.global_position)
			_end_attack()
		Attack.MLRS:
			if _shot_timer <= 0.0:
				_rack_muzzle.position.x = (_shots - 2.5) * 0.35
				var target := _rocket_target()
				var flight := 1.1
				var from := _rack_muzzle.global_position
				var speed := _rocket_velocity(target)
				var shot := fire_along("rocket", _rack_muzzle, speed.length(), 0.0, Palette.HOT, speed)
				shot.gravity = 20.0
				shot.hit = Hit.make(Hit.Kind.SHELL, 0.0, from)
				shot.hit.source = self
				shot.blast_radius = 4.0
				shot.blast_damage = 20.0
				shot.interceptable = true
				shot.trail = Projectile.ROCKET_SMOKE
				World.current.fx.marker(target, 4.0, flight, Palette.RED)
				Sfx.play("launch", from)
				_shots += 1
				_shot_timer = 0.16
				if _shots >= 6:
					_end_attack()
		Attack.RAM:
			var from := global_position
			global_position += _ram_direction * RAM_SPEED * move_speed() / SPEED * delta
			for prop: Prop in World.current.props.near(from, global_position, radius):
				if not prop.dead and not prop.invulnerable and prop.hit_test(from, global_position, radius) >= 0.0:
					var crush := Hit.make(Hit.Kind.RAM, prop.hp, prop.hit_center(), _ram_direction)
					crush.source = self
					prop.die(crush)
			if not _ram_hit and Entity.segment_sphere(from, global_position, tank.hit_center(), radius + tank.radius) >= 0.0:
				_ram_hit = true
				var hit := Hit.make(Hit.Kind.RAM, 25.0, hit_center(), _ram_direction)
				hit.source = self
				tank.take_hit(hit)
			if _attack_time >= WIND * Game.telegraph_scale() + 1.6 or global_position.distance_to(arena_center()) >= Stage2.PLAZA_RADIUS - radius:
				_end_attack()


func _rocket_target() -> Vector3:
	return _aim + Vector3((_shots - 2.5) * 3.0, 0, 0)


func _rocket_velocity(target: Vector3) -> Vector3:
	return (target - _rack_muzzle.global_position) / 1.1 + Vector3.UP * 11.0


func on_death(_hit: Hit) -> void:
	var world := World.current
	world.fx.explosion(hit_center(), 9.0)
	world.fx.debris(hit_center(), 30, debris, 18.0, 0.7)
	world.award(score, hit_center(), true)
	world.style_event("GIANT", 300.0)
	for kind in ["coax", "repair", "era"]:
		world.spawn_pickup(kind, global_position + Vector3(randf_range(-8, 8), 1, randf_range(-8, 8)))
	Sfx.play("blast", global_position)
