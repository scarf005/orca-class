class_name Helicopter
extends Enemy
## Final boss: an attack helicopter overtaken by mycelium, fought in the arena below the dam.
## Phase 1 (Hunter) orbits wide with chin-gun strafes and rocket ripples that saturate the laser.
## Phase 2 (Stripped) closes in once its armor is off: flares, ATGMs and FPV calls.
## Phase 3 (Infected) turns erratic, sheds spores and dives. It dies crashing into the dam.

enum Phase { HUNTER, STRIPPED, INFECTED }
enum Attack { NONE, GUN, ROCKETS, ATGM, DRONES, DIVE }

const BODY_HP := 5200.0
const PANEL_HP := 320.0
const POD_HP := 260.0

class Part:
	var name := ""
	var offset := Vector3.ZERO
	var radius := 1.0
	var hp := 0.0
	var node: Node3D

var phase := Phase.HUNTER
var parts := {}
var _attack := Attack.NONE
var _attack_time := 0.0
var _next_attack := 2.5
var _orbit_angle := 0.0
var _orbit_dir := 1.0
var _velocity := Vector3.ZERO
var _rotor := Node3D.new()
var _tail_rotor := Node3D.new()
var _chin := Node3D.new()
var _fungus := Node3D.new()
var _shots := 0
var _shot_timer := 0.0
var _flare_cooldown := 0.0
var _spore_timer := 0.0
var _crash := 0.0
var _crash_from := Vector3.ZERO
var _hard := false
var _rotor_sound: AudioStreamPlayer3D
var _jitter := Vector3.ZERO


func _init() -> void:
	super()
	radius = 3.2
	armor = 0.6
	center_height = 0.0
	flying = true
	can_stagger = true
	score = 50000
	death_radius = 7.0
	despawn_behind = 0.0
	debris_colors = [Palette.SLATE, Palette.DUSK, Palette.FUNGUS, Palette.INK]
	set_meta("title", "BOSS_HELICOPTER")
	set_meta("phase_marks", [0.66, 0.33])


func build() -> void:
	_hard = Game.difficulty == Game.Difficulty.HARD
	max_hp = BODY_HP * (1.35 if _hard else 1.0)
	hp = max_hp
	var b := LowPoly.new()
	# Narrow tandem fuselage, stepped canopies, tail boom and fin.
	b.box(Transform3D(Basis(), Vector3(0, 0, 0.2)), Vector3(1.5, 1.7, 5.4), Palette.SLATE)
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.55, -2.6)), Vector3(1.3, 1.1, 1.8), Palette.SLATE)
	b.box(Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, -0.35, -2.9)), Vector3(1.2, 0.8, 1.2), Palette.DUSK)
	b.glow = true
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 1.0, -2.3)), Vector3(1.1, 0.5, 1.2), Palette.PERIWINKLE)
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 1.2, -0.9)), Vector3(1.0, 0.5, 1.1), Palette.PERIWINKLE)
	b.glow = false
	b.box(Transform3D(Basis(), Vector3(0, 0.3, 5.2)), Vector3(0.6, 0.6, 5.2), Palette.SLATE)
	b.box(Transform3D(Basis(), Vector3(0, 1.3, 7.5)), Vector3(0.2, 2.0, 1.2), Palette.DUSK)
	b.box(Transform3D(Basis(), Vector3(0, 0.4, 7.3)), Vector3(2.2, 0.1, 0.8), Palette.DUSK)
	# Engine nacelles and exhausts on the shoulders.
	for x in [-0.95, 0.95]:
		b.box(Transform3D(Basis(), Vector3(x, 1.1, 0.4)), Vector3(0.6, 0.7, 2.4), Palette.STONE)
		b.box(Transform3D(Basis(), Vector3(x * 1.1, 1.1, 1.7)), Vector3(0.5, 0.5, 0.3), Palette.INK)
	# Stub wings.
	b.box(Transform3D(Basis(), Vector3(0, -0.1, 0.3)), Vector3(5.6, 0.18, 1.2), Palette.DUSK)
	b.box(Transform3D(Basis(), Vector3(0, 1.75, 0.2)), Vector3(0.4, 0.5, 0.4), Palette.INK)
	var body := MeshInstance3D.new()
	body.mesh = b.mesh()
	model.add_child(body)
	_rotor.position = Vector3(0, 2.05, 0.2)
	model.add_child(_rotor)
	var r := LowPoly.new()
	for i in 5:
		r.box(Transform3D(Basis(Vector3.UP, TAU * i / 5.0), Vector3(0, 0, 0)).translated_local(Vector3(3.7, 0, 0)), Vector3(7.4, 0.06, 0.45), Palette.INK)
	var rotor_mesh := MeshInstance3D.new()
	rotor_mesh.mesh = r.mesh()
	_rotor.add_child(rotor_mesh)
	_tail_rotor.position = Vector3(0.2, 1.4, 7.6)
	model.add_child(_tail_rotor)
	var tr_mesh := MeshInstance3D.new()
	var t := LowPoly.new()
	for i in 4:
		t.box(Transform3D(Basis(Vector3.RIGHT, TAU * i / 4.0), Vector3.ZERO).translated_local(Vector3(0, 0.7, 0)), Vector3(0.05, 1.4, 0.25), Palette.INK)
	tr_mesh.mesh = t.mesh()
	_tail_rotor.add_child(tr_mesh)
	# Chin gun turret.
	_chin.position = Vector3(0, -0.85, -2.7)
	model.add_child(_chin)
	var c := LowPoly.new()
	c.box(Transform3D(), Vector3(0.5, 0.4, 0.5), Palette.INK)
	c.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(0, 0, -0.2)), 0.06, 1.5, 6, Palette.INK)
	var chin_mesh := MeshInstance3D.new()
	chin_mesh.mesh = c.mesh()
	_chin.add_child(chin_mesh)
	_add_part("panel_l", Vector3(-0.85, 0.1, -0.2), 1.2, PANEL_HP, _panel_mesh(-1.0))
	_add_part("panel_r", Vector3(0.85, 0.1, -0.2), 1.2, PANEL_HP, _panel_mesh(1.0))
	_add_part("pod_l", Vector3(-2.6, -0.4, 0.2), 0.8, POD_HP, _pod_mesh())
	_add_part("pod_r", Vector3(2.6, -0.4, 0.2), 0.8, POD_HP, _pod_mesh())
	_add_part("mast", Vector3(0, 1.9, 0.2), 0.7, INF, null)
	model.add_child(_fungus)
	_grow_fungus(4)
	_rotor_sound = Sfx.loop("rotor", self, 2.0)


func _add_part(part_name: String, offset: Vector3, r: float, part_hp: float, mesh: Mesh) -> void:
	var part := Part.new()
	part.name = part_name
	part.offset = offset
	part.radius = r
	part.hp = part_hp
	if mesh:
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = offset
		model.add_child(node)
		part.node = node
	parts[part_name] = part


func _panel_mesh(side: float) -> Mesh:
	var b := LowPoly.new()
	b.box(Transform3D(Basis(Vector3.BACK, side * 0.12), Vector3(side * 0.1, 0, 0)), Vector3(0.12, 1.3, 3.0), Palette.STONE)
	b.box(Transform3D(Basis(), Vector3(side * 0.18, 0.3, 0)), Vector3(0.02, 0.1, 2.4), Palette.CORAL)
	return b.mesh()


func _pod_mesh() -> Mesh:
	var b := LowPoly.new()
	b.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(0, 0, 1.0)), 0.42, 2.0, 7, Palette.MOSS)
	b.glow = true
	for i in 6:
		var angle := TAU * i / 6.0
		b.box(Transform3D(Basis(), Vector3(cos(angle) * 0.24, sin(angle) * 0.24, -1.01)), Vector3(0.12, 0.12, 0.02), Palette.CORAL)
	return b.mesh()


func _grow_fungus(count: int) -> void:
	for i in count:
		var blob := MeshInstance3D.new()
		var p := Vector3(randf_range(-0.8, 0.8), randf_range(-0.5, 1.2), randf_range(-2.0, 5.0))
		blob.mesh = LowPoly.new().blob(Transform3D(), randf_range(0.3, 0.8), [Palette.FUNGUS, Palette.LILAC, Palette.BLUSH][i % 3], 0, 0.35, randi()).mesh()
		blob.position = p
		_fungus.add_child(blob)
		_meshes.append(blob)


func _live(part_name: String) -> bool:
	return parts[part_name].hp > 0.0


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	if _crash > 0.0:
		return -1.0
	var best := -1.0
	for center: Vector3 in [Vector3(0, 0.2, -1.2), Vector3(0, 0.2, 1.4), Vector3(0, 0.3, 4.5)]:
		var t := Entity.segment_sphere(from, to, model.global_transform * center, (1.6 if center.z < 3.0 else 0.9) + extra_radius)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	for part: Part in parts.values():
		if part.hp <= 0.0:
			continue
		var t := Entity.segment_sphere(from, to, model.global_transform * part.offset, part.radius + extra_radius)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


func take_hit(hit: Hit) -> void:
	if dead or _crash > 0.0:
		return
	var world := World.current
	# Route to the nearest part: pods and panels absorb what hits them.
	var nearest: Part = null
	var nearest_distance := 1.2
	for part: Part in parts.values():
		if part.hp <= 0.0:
			continue
		var distance := hit.position.distance_to(model.global_transform * part.offset) - part.radius
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = part
	var amount := hit.damage * damage_multiplier(hit)
	if nearest and nearest.name != "mast":
		nearest.hp -= amount
		flash()
		world.fx.sparks(hit.position, -hit.direction, 5, Palette.BUTTER)
		if nearest.hp <= 0.0:
			_lose_part(nearest)
		# Some of it still reaches the airframe.
		amount *= 0.3
	elif nearest and nearest.name == "mast":
		amount *= 2.0 if hit.pierce else 1.3
		if hit.stagger > 0.5:
			stagger = maxf(stagger, 1.2)
			world.fx.sparks(hit.position, Vector3.UP, 16, Palette.WHITE, 12.0)
	var armored := _live("panel_l") or _live("panel_r")
	if armored and not hit.pierce and hit.kind != Hit.Kind.BLAST:
		amount *= 0.5
	hp -= amount
	flash()
	if hit.stagger >= 1.0:
		stagger = maxf(stagger, 0.6)
		if _attack in [Attack.GUN, Attack.ATGM] and _attack_time < 0.8:
			_end_attack()
	if hp <= 0.0:
		_begin_crash()
		return
	_update_phase()


func damage_multiplier(hit: Hit) -> float:
	var multiplier := super(hit)
	match hit.kind:
		Hit.Kind.FRAGMENT:
			multiplier *= 1.5 # Airburst fragments shred rotorcraft.
		Hit.Kind.BULLET:
			multiplier *= 0.4 # Machine guns only scratch it; the main gun does the work.
	return multiplier


func _lose_part(part: Part) -> void:
	var world := World.current
	var at: Vector3 = model.global_transform * part.offset
	world.fx.explosion(at, 2.5 if part.name.begins_with("pod") else 1.6)
	world.fx.debris(at, 10, [Palette.STONE, Palette.CORAL, Palette.INK], 10.0, 0.4)
	world.shake(0.4)
	world.hitstop(0.06)
	world.award(1500, at, false)
	Sfx.play("blast", at)
	if part.node:
		part.node.queue_free()
	if part.name.begins_with("pod"):
		# Cooking off the remaining rockets.
		hp -= 80.0
	_update_phase()


func _update_phase() -> void:
	var world := World.current
	var ratio := hp / max_hp
	if phase == Phase.HUNTER and (ratio < 0.66 or not (_live("panel_l") or _live("panel_r"))):
		phase = Phase.STRIPPED
		world.radio.emit(&"AI_BOSS_PHASE2")
		_resupply()
		_grow_fungus(6)
		for side in ["panel_l", "panel_r"]:
			if _live(side):
				parts[side].hp = 0.0
				_lose_part(parts[side])
		_next_attack = 1.0
	elif phase == Phase.STRIPPED and ratio < 0.33:
		phase = Phase.INFECTED
		world.radio.emit(&"AI_BOSS_PHASE3")
		_resupply()
		_grow_fungus(14)
		world.screen_flash(Palette.FUNGUS, 0.4)
		Sfx.play("roar", global_position, 6.0, 0.7)
		_next_attack = 0.8


## Drops fresh ERA and a regrowth pod near the tank at each phase change.
func _resupply() -> void:
	var world := World.current
	var tank := player()
	if tank == null:
		return
	world.spawn_pickup("era", tank.global_position + tank.global_basis.x * 8.0 + Vector3.UP * 1.5)
	world.spawn_pickup("tail", tank.global_position - tank.global_basis.x * 8.0 + Vector3.UP * 1.5)


func behave(delta: float) -> void:
	var world := World.current
	var tank := player()
	_rotor.rotation.y += delta * (28.0 if _crash <= 0.0 else 40.0)
	_tail_rotor.rotation.x += delta * 50.0
	if _crash > 0.0:
		_update_crash(delta)
		return
	if tank == null:
		return
	_flare_cooldown -= delta
	_watch_for_shells()
	# Orbit the arena center, keeping the tank in front.
	var center := Course.to_world(Course.ARENA_CENTER_D, 0.0)
	var orbit_radius := [55.0, 34.0, 28.0][phase] as float
	var altitude := [19.0, 13.0, 11.0][phase] as float
	var speed := [0.18, 0.3, 0.42][phase] as float
	if randf() < delta * 0.15:
		_orbit_dir = -_orbit_dir
	_orbit_angle += _orbit_dir * speed * delta * (0.3 if is_staggered() else 1.0)
	var focus := tank.global_position.lerp(center, 0.5)
	var goal := focus + Vector3(cos(_orbit_angle), 0, sin(_orbit_angle)) * orbit_radius
	goal.y = Course.height_at(goal) + altitude
	if phase == Phase.INFECTED:
		_jitter = _jitter.lerp(Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-6, 6)), delta * 2.0)
		goal += _jitter
		_spore_timer -= delta
		if _spore_timer <= 0.0:
			_spore_timer = 0.7
			var drop := global_position
			drop.y = Course.height_at(drop)
			Hazard.spawn(drop + Vector3.UP, 3.0, 3.0, 6.0)
			world.fx.spores(global_position, 16, 3.0)
	if _attack == Attack.DIVE:
		goal = tank.global_position + Vector3.UP * 5.0
	if is_staggered():
		goal.y -= 5.0
	var accel := (goal - global_position) * 1.6 - _velocity * 1.4
	_velocity += accel * delta
	global_position += _velocity * delta
	# Nose at the tank, bank into the turn.
	var to_tank := tank.global_position - global_position
	var yaw := atan2(-to_tank.x, -to_tank.z)
	model.rotation.y = lerp_angle(model.rotation.y, yaw, 2.5 * delta)
	var lateral := _velocity.dot(model.global_basis.x)
	model.rotation.z = lerpf(model.rotation.z, -lateral * 0.04, 3.0 * delta)
	model.rotation.x = lerpf(model.rotation.x, -_velocity.dot(-model.global_basis.z) * 0.02 - 0.08, 3.0 * delta)
	_chin.look_at(tank.hit_center(), Vector3.UP)
	_update_attack(delta, tank)


func _watch_for_shells() -> void:
	if phase == Phase.HUNTER or _flare_cooldown > 0.0:
		return
	var world := World.current
	for projectile in world.projectiles:
		if projectile.team != Team.PLAYER or projectile.hit.caliber < 100:
			continue
		if projectile.global_position.distance_to(global_position) < 45.0 and projectile.velocity.dot(global_position - projectile.global_position) > 0.0:
			_pop_flares()
			return


func _pop_flares() -> void:
	var world := World.current
	_flare_cooldown = 5.0 if not _hard else 3.5
	Sfx.play("launch", global_position, 0.0, 1.5)
	for i in 6:
		var flare: Flare = Flare.new()
		var side := -1.0 if i % 2 == 0 else 1.0
		flare.drift = model.global_basis.x * side * randf_range(8, 14) + Vector3.UP * randf_range(2, 6) - model.global_basis.z * randf_range(-4, 4)
		flare.position = global_position + model.global_basis.x * side
		world.add_enemy(flare)


func _update_attack(delta: float, tank: Tank) -> void:
	if _attack == Attack.NONE:
		_next_attack -= delta
		if _next_attack <= 0.0 and not is_staggered():
			_choose_attack()
		return
	_attack_time += delta
	match _attack:
		Attack.GUN:
			_gun(delta, tank)
		Attack.ROCKETS:
			_rockets(delta, tank)
		Attack.ATGM:
			if _attack_time < 1.3:
				set_meta("locking", true)
				if fmod(_attack_time, 0.1) < 0.05:
					World.current.fx.beam(_chin.global_position, tank.hit_center(), Palette.RED, 0.05, 0.05)
			else:
				set_meta("locking", false)
				for i in (2 if phase == Phase.STRIPPED else 3):
					_launch_atgm(tank, i)
				_end_attack()
		Attack.DRONES:
			if _attack_time > 0.6:
				var wave := {"d": 0.0, "kind": "fpv", "count": 3 if not _hard else 5, "formation": "ring", "height": 0.0, "spacing": 5.0, "ahead": 0.0, "hover": 18.0, "approach": 1.0}
				var spawned: Array[Enemy] = World.current.director.spawn_wave(wave)
				for drone in spawned:
					drone.global_position = global_position + Vector3(randf_range(-4, 4), -1.0, randf_range(-4, 4))
				_end_attack()
		Attack.DIVE:
			if _attack_time > 2.2:
				_end_attack()
			elif tank.global_position.distance_to(global_position) < 9.0:
				var hit := Hit.make(Hit.Kind.RAM, 20.0, global_position, (tank.global_position - global_position).normalized())
				hit.source = self
				tank.take_hit(hit)
				_end_attack()


func _choose_attack() -> void:
	var options: Array[Attack] = [Attack.GUN, Attack.ROCKETS]
	match phase:
		Phase.STRIPPED:
			options = [Attack.GUN, Attack.ROCKETS, Attack.ATGM, Attack.DRONES]
		Phase.INFECTED:
			options = [Attack.GUN, Attack.ROCKETS, Attack.ATGM, Attack.DIVE, Attack.ROCKETS]
	if not (_live("pod_l") or _live("pod_r")):
		options.erase(Attack.ROCKETS)
	_attack = options.pick_random()
	_attack_time = 0.0
	_shots = 0
	match _attack:
		Attack.GUN:
			Sfx.play("warn", global_position, 0.0, 1.2)
		Attack.ROCKETS:
			Sfx.play("warn", global_position, 2.0, 0.8)
		Attack.ATGM:
			Sfx.play("lock", global_position)
		Attack.DIVE:
			Sfx.play("roar", global_position, 0.0, 1.4)


func _end_attack() -> void:
	_attack = Attack.NONE
	set_meta("locking", false)
	var pause := [2.2, 1.6, 1.1][phase] as float
	_next_attack = pause * (0.8 if _hard else 1.0) + randf() * 0.6


func _gun(delta: float, tank: Tank) -> void:
	var world := World.current
	if _attack_time < 0.6:
		# Telegraph: sight beam sweeping onto the tank.
		if fmod(_attack_time, 0.12) < 0.06:
			world.fx.beam(_chin.global_position, tank.hit_center() + Vector3(0, 0, 0), Palette.CORAL, 0.04, 0.05)
		return
	_shot_timer -= delta
	var total := [14, 18, 24][phase] as int
	if _shot_timer <= 0.0 and _shots < total:
		_shots += 1
		_shot_timer = 0.07
		var from := _chin.global_position
		var lead := tank.hit_center() + tank.velocity * (from.distance_to(tank.hit_center()) / 110.0) * 0.7
		var shot := fire_at("orb", from, lead + Vector3(randf_range(-1.5, 1.5), randf_range(-0.5, 0.5), randf_range(-1.5, 1.5)), 110.0, 4.5)
		shot.hit.caliber = 30
		world.fx.spawn(Fx.Kind.FLAME, from, Vector3.ZERO, 0.05, 0.4, Palette.CORAL)
		Sfx.play("enemy_gun", from, 0.0, 0.8)
	elif _shots >= total:
		_end_attack()


func _rockets(delta: float, tank: Tank) -> void:
	var world := World.current
	if _attack_time < 0.8:
		for side in ["pod_l", "pod_r"]:
			var part: Part = parts[side]
			if part.hp > 0.0 and fmod(_attack_time, 0.16) < 0.08:
				flash()
		return
	_shot_timer -= delta
	var total := [12, 14, 20][phase] as int
	if _shot_timer <= 0.0 and _shots < total:
		var side: String = "pod_l" if _shots % 2 == 0 else "pod_r"
		if not _live(side):
			side = "pod_r" if side == "pod_l" else "pod_l"
		_shots += 1
		_shot_timer = 0.09 if phase != Phase.INFECTED else 0.06
		var from: Vector3 = model.global_transform * (parts[side].offset + Vector3(0, 0, -1.0))
		var spread := 7.0 if phase != Phase.INFECTED else 11.0
		var target := tank.global_position + tank.velocity * 0.8 + Vector3(randf_range(-spread, spread), 0, randf_range(-spread, spread))
		if phase == Phase.INFECTED:
			var angle := _shots * 0.7
			target = tank.global_position + Vector3(cos(angle), 0, sin(angle)) * (4.0 + _shots * 0.4)
		target.y = Course.height_at(target)
		var rocket := fire_at("rocket", from, target, 55.0, 0.0)
		rocket.hit = Hit.make(Hit.Kind.SHELL, 0.0, from)
		rocket.hit.source = self
		rocket.blast_radius = 2.6
		rocket.blast_damage = 9.0
		rocket.interceptable = true
		rocket.intercept_hp = 0.55
		rocket.trail = Palette.MIST
		rocket.life = 4.0
		world.fx.spawn(Fx.Kind.FLAME, from, Vector3.ZERO, 0.08, 0.6, Palette.BUTTER)
		Sfx.play("launch", from, -2.0, randf_range(1.1, 1.3))
	elif _shots >= total:
		_end_attack()


func _launch_atgm(tank: Tank, index: int) -> void:
	var from := global_position + model.global_basis.x * (index - 1) * 1.5 + Vector3.DOWN
	var missile := fire_at("atgm", from, from + Vector3.UP * 2.0 + model.global_basis.x * (index - 1) * 4.0 + (tank.hit_center() - from).normalized() * 4.0, 30.0, 0.0)
	missile.hit = Hit.make(Hit.Kind.SHELL, 0.0, from)
	missile.hit.source = self
	missile.blast_radius = 3.0
	missile.blast_damage = 24.0
	missile.hit.warhead = true
	missile.homing_target = tank
	missile.turn_rate = 2.0
	missile.interceptable = true
	missile.intercept_hp = 1.4
	missile.life = 7.0
	missile.trail = Palette.MIST
	Sfx.play("launch", from, 2.0, 0.8)


func _begin_crash() -> void:
	var world := World.current
	_crash = 3.2
	_crash_from = global_position
	hp = 0.0
	world.boss_changed.emit(null)
	world.shake(0.7)
	world.hitstop(0.25)
	world.screen_flash(Palette.WHITE, 0.7)
	world.radio.emit(&"AI_CLEAR")
	Sfx.play("blast", global_position)
	for side in ["pod_l", "pod_r"]:
		if _live(side):
			_lose_part(parts[side])


## Engine on fire, spinning, it arcs into the dam face and explodes against it.
func _update_crash(delta: float) -> void:
	var world := World.current
	_crash -= delta
	var dam := Course.to_world(Course.DAM_D - 3.0, Course.to_course(_crash_from).y, 12.0)
	var k := 1.0 - _crash / 3.2
	global_position = _crash_from.lerp(dam, k * k) + Vector3.UP * sin(k * PI) * 6.0
	model.rotation.y += delta * (4.0 + k * 10.0)
	model.rotation.z = lerpf(model.rotation.z, 0.6, delta)
	if randf() < delta * 20.0:
		world.fx.spawn(Fx.Kind.FLAME, global_position + Vector3(randf_range(-1, 1), 1, randf_range(-1, 1)), Vector3(0, 3, 0), 0.5, 1.2, [Palette.PEACH, Palette.CORAL, Palette.BUTTER][randi() % 3])
		world.fx.smoke(global_position, 1, 2.0, [Palette.STONE, Palette.ASH, Palette.DUSK])
	if _crash <= 0.0:
		for i in 5:
			world.fx.explosion(global_position + Vector3(randf_range(-5, 5), randf_range(-2, 6), randf_range(-3, 3)), 6.0 + i)
		world.fx.shockwave(global_position, 40.0, Palette.BUTTER)
		world.shake(1.0)
		world.hitstop(0.3)
		world.screen_flash(Palette.WHITE, 0.9)
		die(Hit.make(Hit.Kind.BLAST, 9999.0, global_position))


func on_death(_hit: Hit) -> void:
	var world := World.current
	world.fx.debris(global_position, 30, debris_colors, 18.0, 0.7)
	world.fx.spores(global_position, 60, 8.0)
	world.award(score, global_position, true)
	world.style_event("GIANT", 400.0)
	Sfx.play("blast", global_position, 6.0, 0.7)
