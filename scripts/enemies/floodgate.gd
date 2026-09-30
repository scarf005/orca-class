class_name Floodgate
extends Enemy
## A drainage fortress on the basin's bank. Four independent gate batteries give way to a
## pumping/root phase, then the exposed core. Concrete stays scenery; only living weapons glow.

enum Phase { GATES, DRAINED, CORE }
enum BatteryKind { FLAK, ATGM, MORTAR, SPORE }

const BATTERY_HP := 2600.0 ## Two clean 100 mm hits per gate; coax finishes a wounded battery.
const CORE_HP := 4200.0 ## Three clean cannon hits on the root, not a second armored hull.
const DROP_LEVELS := [0.16, -0.18, -0.52, -0.90]
const DRAINED_TIME := 12.0
const WARNING := 1.2
const BATTERY_RADIUS := 4.0
const CORE_RADIUS := 4.4
const BATTERY_NAMES := ["FLAK", "ATGM", "MORTAR", "SPORE"]
const BATTERY_OFFSETS := [Vector3(-30, 9, 5), Vector3(-10, 9, 5), Vector3(10, 9, 5), Vector3(30, 9, 5)]
const CORE_OFFSET := Vector3(0, 3.2, 5.2)
const INTAKE_OFFSETS := [Vector3(-24, 0.2, 12), Vector3(24, 0.2, 12)]
const GEYSER_RADIUS := 4.0
const GEYSER_WARNING := 1.2
const GEYSER_DAMAGE := 28.0

class Battery:
	var name := ""
	var kind := BatteryKind.FLAK
	var hp := BATTERY_HP
	var node: Node3D
	var gate: MeshInstance3D
	var gun: Node3D
	var barrels: Node3D
	var muzzle: Node3D
	var sac: MeshInstance3D
	var telegraph := 0.0
	var attack_count := 0
	var destroyed := false
	var target := Vector3.ZERO
	var burst := 0
	var burst_timer := 0.0

var phase := Phase.GATES
var batteries: Array[Battery] = []
var core_hp := CORE_HP
var core_exposed := false
var intake_active := false
var _core: Node3D
var _sheath: MeshInstance3D
var _growth: MeshInstance3D
var _intakes: Array[Node3D] = []
var _swirls: Array[MeshInstance3D] = []
var _pieces: Array[Dam.Piece] = []
var _torrents: Array[Dictionary] = []
var _geysers: Array[Dictionary] = []
var _phase_clock := 0.0
var _attack_index := 0
var _attack_timer := 1.8
var _spawn_time := 1.0
var _spawn_index := 0
var _geyser_time := 1.2
var _water_target := Stage2.LEVEL
var _water_from := Stage2.LEVEL
var _water_clock := 2.0
var _death_clock := 0.0
var _spray_clock := 0.0

func _init() -> void:
	super()
	max_hp = BATTERY_HP * 4.0 + CORE_HP
	hp = max_hp
	radius = 4.0
	center_height = 9.0
	can_stagger = false
	despawn_behind = 0.0
	score = 50000
	debris = [Fx.Debris.CONCRETE, Fx.Debris.METAL, Fx.Debris.FLESH]
	set_meta("title", "BOSS_FLOODGATE")
	set_meta("phase_marks", [CORE_HP / max_hp])
	for i in 4:
		var battery := Battery.new()
		battery.name = BATTERY_NAMES[i]
		battery.kind = i
		batteries.append(battery)

func _ready() -> void:
	rotation.y = Course.yaw_at(Stage2.GATE_D)
	super()
	# Enemy's default marks the whole model. Keep the piers and walkway in the pastel scenery pass.
	ActorLayer.unmark(model, ActorLayer.HOSTILE)
	for battery in batteries:
		ActorLayer.mark(battery.node, ActorLayer.HOSTILE)
	ActorLayer.mark(_core, ActorLayer.HOSTILE)
	_water_target = (Course.stage as Stage2).arena_level
	Sfx.play("boss_klaxon", global_position, 3.0)

func build() -> void:
	# Each block really exists before destruction, as in Dam: no intact facade over a fake wreck.
	for x in [-40.0, -20.0, 0.0, 20.0, 40.0]:
		for tier in 4:
			_block(Vector3(x, 3.0 + tier * 6.0, 0), Vector3(4.4, 5.9, 8.0), Palette.CONCRETE if tier % 2 else Palette.MIST)
	for x in [-30.0, -10.0, 10.0, 30.0]:
		_block(Vector3(x, 22.5, 0), Vector3(15.6, 3.0, 8.0), Palette.CONCRETE)
		_block(Vector3(x, 25, 0), Vector3(20.0, 1.5, 9.0), Palette.ASH)
	# Crown: railings, hoist gantries and a glazed control house, facing the arena (+Z).
	for x in [-40.0, -20.0, 0.0, 20.0, 40.0]:
		_block(Vector3(x, 27, 4.2), Vector3(0.3, 3.0, 0.3), Palette.SLATE)
	for x in [-30.0, -10.0, 10.0, 30.0]:
		_block(Vector3(x, 28.3, 4.2), Vector3(20.0, 0.25, 0.3), Palette.SLATE)
		_block(Vector3(x, 20, 1), Vector3(2.2, 2, 2), Palette.DUSK)
		var rig := LowPoly.new()
		for side in [-6.0, 6.0]:
			rig.box(Transform3D(Basis(), Vector3(x + side, 13, 4.5)), Vector3(0.28, 18, 0.3), Palette.SLATE)
		_add_mesh(model, rig.mesh())
	_block(Vector3(0, 29.3, -0.5), Vector3(19, 6, 6), Palette.STONE)
	_block(Vector3(0, 32.6, -0.5), Vector3(23, 0.9, 8), Palette.INK)
	var glass := LowPoly.new()
	for x in [-6.0, -2.0, 2.0, 6.0]:
		glass.box(Transform3D(Basis(), Vector3(x, 29.6, 2.56)), Vector3(3.2, 2.4, 0.08), Palette.SKY)
	_add_mesh(model, glass.mesh())
	var growth := LowPoly.new()
	growth.flesh = true
	for i in 18:
		var x := -40.0 + float(i % 5) * 20.0
		var y := 3.5 + float((i * 7) % 22)
		growth.blob(Transform3D(Basis().scaled(Vector3(1.4, 0.8, 0.65)), Vector3(x, y, 4.1)), 2.0 + (i % 3) * 0.7, [Palette.FUNGUS, Palette.LILAC, Palette.BLUSH][i % 3], 1, 0.4, i)
		growth.tube(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(x + 1, y, 4.6)), 0.22, 3.8 + i % 4, 6, Palette.MAUVE, 0.08)
	_growth = _add_mesh(model, growth.mesh())
	for i in 4:
		var battery := batteries[i]
		var leaf := LowPoly.new()
		leaf.box(Transform3D(), Vector3(15.5, 18.0, 0.45), Palette.SLATE, Palette.DUSK)
		for y in [-7.0, -3.5, 0.0, 3.5, 7.0]:
			leaf.box(Transform3D(Basis(), Vector3(0, y, 0.32)), Vector3(15.0, 0.3, 0.45), Palette.INK)
		battery.gate = _add_mesh(model, leaf.mesh())
		battery.gate.position = Vector3(BATTERY_OFFSETS[i].x, 10.5, 3.8)
		battery.node = _battery_mesh(battery)
		battery.node.position = BATTERY_OFFSETS[i]
		model.add_child(battery.node)
	_core = Node3D.new()
	_core.position = CORE_OFFSET
	_core.visible = false
	model.add_child(_core)
	var core := LowPoly.new()
	core.flesh = true
	core.blob(Transform3D(Basis().scaled(Vector3(1.4, 0.85, 0.8)), Vector3.ZERO), 3.6, Palette.FUNGUS, 1, 0.3, 9)
	for i in 8:
		var angle := TAU * i / 8.0
		core.blob(Transform3D(Basis(), Vector3(cos(angle) * 3.6, sin(angle) * 2.4, 0.8)), 0.65, Palette.CREAM, 0, 0.15, i)
	core.glow = true
	core.blob(Transform3D(Basis(), Vector3(0, 0.2, 2.0)), 1.65, Palette.HOT, 1, 0.2, 4)
	_add_mesh(_core, core.mesh())
	var sheath := LowPoly.new()
	sheath.flesh = true
	for x in [-1.0, 1.0]:
		sheath.blob(Transform3D(Basis().scaled(Vector3(0.9, 1.5, 0.5)), Vector3(x * 2, 0, 2.1)), 2.2, Palette.MAUVE, 1, 0.2, 3)
	_sheath = _add_mesh(_core, sheath.mesh())
	for offset in INTAKE_OFFSETS:
		var intake := Node3D.new()
		intake.position = offset
		intake.visible = false
		model.add_child(intake)
		var ib := LowPoly.new()
		ib.prism(Transform3D(), 3.4, 0.35, 12, Palette.INK)
		for x in [-2.0, -1.0, 0.0, 1.0, 2.0]:
			ib.box(Transform3D(Basis(), Vector3(x, 0.4, 0)), Vector3(0.18, 0.12, sqrt(10.0 - x * x) * 2.0), Palette.SLATE)
		_add_mesh(intake, ib.mesh())
		_intakes.append(intake)
		var swirl := MeshInstance3D.new()
		swirl.mesh = ArrayMesh.new()
		swirl.material_override = Terrain.water_material(true)
		intake.add_child(swirl)
		_swirls.append(swirl)

func _block(at: Vector3, size: Vector3, color: Color) -> void:
	var piece := Dam.Piece.new()
	var b := LowPoly.new()
	b.box(Transform3D(), size, color, Palette.STONE)
	piece.node = _add_mesh(model, b.mesh())
	piece.node.position = at
	piece.center = at
	_pieces.append(piece)

func _add_mesh(parent: Node3D, mesh: Mesh) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	parent.add_child(instance)
	return instance

func _battery_mesh(battery: Battery) -> Node3D:
	var root := Node3D.new()
	var mount := LowPoly.new()
	mount.box(Transform3D(), Vector3(5.2, 1.5, 3.8), Palette.DUSK, Palette.RED)
	mount.prism(Transform3D(Basis(), Vector3(0, 1, 0)), 1.5, 0.7, 8, Palette.CORAL)
	mount.glow = true
	mount.box(Transform3D(Basis(), Vector3(0, 0.2, 2)), Vector3(2.4, 0.22, 0.1), Palette.HOT)
	_add_mesh(root, mount.mesh())
	battery.gun = Node3D.new()
	battery.gun.position = Vector3(0, 1.4, 0)
	battery.gun.rotation.y = PI # Barrels face the arena, not into the bank.
	root.add_child(battery.gun)
	battery.barrels = Node3D.new()
	battery.gun.add_child(battery.barrels)
	battery.muzzle = Node3D.new()
	battery.muzzle.position.z = -3.5
	battery.gun.add_child(battery.muzzle)
	var gun := LowPoly.new()
	match battery.kind:
		BatteryKind.FLAK:
			gun.box(Transform3D(), Vector3(2.3, 1.6, 1.8), Palette.RED, Palette.CORAL)
			for x in [-0.65, 0.65]:
				for y in [-0.45, 0.45]:
					gun.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(x, y, -0.6)), 0.17, 3.0, 8, Palette.INK)
					gun.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(x, y, -2.8)), 0.23, 0.4, 8, Palette.HOT)
		BatteryKind.ATGM:
			for x in [-0.9, 0.9]:
				for y in [-0.4, 0.5]:
					gun.box(Transform3D(Basis(), Vector3(x, y, -1)), Vector3(1.4, 0.8, 3.2), Palette.RED, Palette.AMBER)
					gun.box(Transform3D(Basis(), Vector3(x, y, -2.65)), Vector3(0.9, 0.5, 0.08), Palette.INK)
		BatteryKind.MORTAR:
			gun.tube(Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO), 0.6, 3.5, 10, Palette.RED)
			gun.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -3.0)), 0.7, 0.5, 10, Palette.HOT)
		BatteryKind.SPORE:
			gun.flesh = true
			gun.blob(Transform3D(Basis().scaled(Vector3(1.1, 1.4, 1.0)), Vector3(0, 0.6, -1.6)), 1.65, Palette.FUNGUS, 1, 0.3, 3)
			gun.glow = true
			gun.blob(Transform3D(Basis(), Vector3(0, 0.6, -3.0)), 0.65, Palette.HOT, 1, 0.2, 5)
	battery.sac = _add_mesh(battery.barrels, gun.mesh())
	return root

func hit_center() -> Vector3:
	if core_exposed:
		return model.global_transform * CORE_OFFSET
	for battery in batteries:
		if not battery.destroyed and battery.node != null:
			return battery.node.global_position + Vector3.UP
	return global_position + Vector3.UP * 9.0

func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	if dead:
		return -1.0
	var best := -1.0
	if phase == Phase.GATES:
		for battery in batteries:
			if battery.destroyed:
				continue
			var t := Entity.segment_sphere(from, to, battery.node.global_position + Vector3.UP, BATTERY_RADIUS + extra_radius)
			if t >= 0.0 and (best < 0.0 or t < best):
				best = t
	elif core_exposed:
		best = Entity.segment_sphere(from, to, model.global_transform * CORE_OFFSET, CORE_RADIUS + extra_radius)
	return best

func take_hit(hit: Hit) -> void:
	if dead or invulnerable or hit.damage <= 0.0:
		return
	if phase == Phase.GATES:
		var nearest: Battery = null
		var distance := BATTERY_RADIUS + 1.0 # Projectile thickness and the sight's small assist sphere.
		for battery in batteries:
			var d := hit.position.distance_to(battery.node.global_position + Vector3.UP)
			if not battery.destroyed and d <= distance:
				distance = d
				nearest = battery
		if nearest == null:
			return
		nearest.hp = maxf(0.0, nearest.hp - hit.damage * damage_multiplier(hit))
		_feedback(hit, nearest.hp <= 0.0)
		if nearest.hp <= 0.0:
			_break_battery(nearest)
	elif core_exposed and hit.position.distance_to(model.global_transform * CORE_OFFSET) <= CORE_RADIUS + 1.0:
		core_hp = maxf(0.0, core_hp - hit.damage * damage_multiplier(hit))
		_feedback(hit, core_hp <= 0.0)
		if core_hp <= 0.0:
			die(hit)
	_refresh_hp()

func _feedback(hit: Hit, killed: bool) -> void:
	World.current.fx.impact_star(hit.position, 2.0, Palette.WHITE)
	World.current.fx.sparks(hit.position, -hit.direction, 10, Palette.BUTTER)
	damaged.emit(self, hit)
	if hit.by_player():
		World.current.hit_confirmed.emit(killed)
		Sfx.confirm_hit(killed)

func _refresh_hp() -> void:
	hp = core_hp
	for battery in batteries:
		hp += battery.hp

func _break_battery(battery: Battery) -> void:
	battery.destroyed = true
	battery.telegraph = 0.0
	battery.burst = 0
	battery.gate.visible = false
	battery.node.visible = false
	var world := World.current
	Sfx.play("gate_break", battery.node.global_position, 3.0)
	world.fx.shatter(battery.gate.global_transform * battery.gate.get_aabb(), [Fx.Debris.METAL], global_basis.z, 0.45)
	world.fx.debris(battery.node.global_position, 22, [Fx.Debris.METAL, Fx.Debris.FLESH], 16.0, 0.5, global_basis.z)
	world.fx.explosion(battery.node.global_position, 4.0)
	world.shake(0.35, battery.node.global_position)
	_spawn_torrent(battery)
	var destroyed_count := batteries.filter(func(b: Battery) -> bool: return b.destroyed).size()
	_lower_water(DROP_LEVELS[destroyed_count - 1])
	if destroyed_count == 4:
		_enter_drained()

func _lower_water(target: float) -> void:
	_water_from = (Course.stage as Stage2).arena_level
	_water_target = target
	_water_clock = 0.0

func _update_water(delta: float) -> void:
	_water_clock = minf(2.0, _water_clock + delta)
	(Course.stage as Stage2).arena_level = lerpf(_water_from, _water_target, smoothstep(0.0, 2.0, _water_clock))

func _spawn_torrent(battery: Battery) -> void:
	var node := MeshInstance3D.new()
	node.mesh = ArrayMesh.new()
	node.material_override = Terrain.water_material(true)
	model.add_child(node)
	_torrents.append({"node": node, "x": battery.node.position.x, "clock": 0.0})
	Sfx.play("torrent", battery.node.global_position, 4.0)

func _update_torrents(delta: float) -> void:
	for torrent: Dictionary in _torrents:
		torrent.clock += delta
		var clock: float = torrent.clock
		var quads := []
		var flow := minf(clock, 1.0) * clampf((7.0 - clock) / 2.0, 0.0, 1.0)
		var fall := 1.1 * flow
		for j in 12:
			var t0 := fall * j / 12.0
			var t1 := fall * (j + 1) / 12.0
			for i in 8:
				var x0: float = torrent.x + (float(i) / 8.0 - 0.5) * 14.0
				var x1 := x0 + 14.0 / 8.0
				var color: Color = Dam.SHEET_COLORS[posmod(i * 2 + j - int(clock * 9), Dam.SHEET_COLORS.size())]
				quads.append([Vector3(x0, 8 - 6 * t0 * t0, 4 + 12 * t0), Vector3(x1, 8 - 6 * t0 * t0, 4 + 12 * t0), Vector3(x1, 8 - 6 * t1 * t1, 4 + 12 * t1), Vector3(x0, 8 - 6 * t1 * t1, 4 + 12 * t1), color])
		Dam._set_quads(torrent.node, quads, Vector3.UP)
		(torrent.node as MeshInstance3D).visible = flow > 0.0
	_spray_clock -= delta
	if _spray_clock <= 0.0:
		_spray_clock = 0.12
		for torrent: Dictionary in _torrents:
			if torrent.clock < 6.0:
				var at := to_global(Vector3(torrent.x, 0.4, 17))
				World.current.fx.splash(at, 2.4, at.y)

func _enter_drained() -> void:
	phase = Phase.DRAINED
	_phase_clock = 0.0
	intake_active = true
	_core.visible = true
	for intake in _intakes:
		intake.visible = true
	Sfx.play("intake_suction", global_position, 4.0)

func expose_core() -> void:
	if phase != Phase.DRAINED or dead:
		return
	phase = Phase.CORE
	_phase_clock = 0.0
	core_exposed = true
	_sheath.visible = false
	World.current.fx.spores(_core.global_position, 32, 4.0)
	Sfx.play("roar", _core.global_position, 2.0, 0.7)

func current_force_for(point: Vector3) -> Vector3:
	if not intake_active or dead:
		return Vector3.ZERO
	var force := Vector3.ZERO
	for intake in _intakes:
		var offset := intake.global_position - point
		offset.y = 0.0
		var distance := offset.length()
		if distance > 0.1 and distance < 38.0:
			# A current adds to arena translation (m/s), weaker than even deep-water full strafe.
			force += offset.normalized() * (9.0 * (1.0 - distance / 38.0))
	return force.limit_length(10.0)

func _update_intakes(delta: float) -> void:
	if not intake_active:
		return
	for i in _intakes.size():
		var quads := []
		for j in 28:
			var angle := j * TAU / 28.0 + age * (2.0 if i == 0 else -2.0)
			var r := 3.4 + float(j) / 28.0 * 5.5
			var a := Vector3(cos(angle), 0, sin(angle))
			var b := Vector3(cos(angle + 0.3), 0, sin(angle + 0.3))
			var y := maxf(0.6, (Course.stage as Stage2).arena_level - _intakes[i].global_position.y + 0.08)
			quads.append([a * r + Vector3.UP * y, a * (r + 0.45) + Vector3.UP * y, b * (r + 0.6) + Vector3.UP * y, b * (r + 0.15) + Vector3.UP * y, Palette.SKY if j % 3 else Palette.WHITE])
		Dam._set_quads(_swirls[i], quads, Vector3.UP)

func _process_batteries(delta: float) -> void:
	var tank := player()
	if tank == null or tank.dead:
		return
	for battery in batteries:
		if battery.destroyed:
			continue
		if battery.telegraph > 0.0:
			_update_telegraph(battery, delta)
			battery.telegraph = maxf(0.0, battery.telegraph - delta)
			if battery.telegraph <= 0.0:
				_attack(battery)
			return
		if battery.burst > 0:
			battery.burst_timer -= delta
			battery.barrels.rotation.z += 30.0 * delta
			if battery.burst_timer <= 0.0:
				battery.burst -= 1
				battery.burst_timer = 0.09
				var dir := (battery.target - battery.muzzle.global_position).normalized()
				var shot := fire_at("orb", battery.muzzle.global_position, battery.target, 92.0, 5.0, Palette.HOT, Muzzle.AUTO)
				shot.hit.caliber = 20
				shot.hit.direction = dir
				Sfx.play("enemy_gun", battery.muzzle.global_position, -1.0, 0.8)
			return
	_attack_timer -= delta
	if _attack_timer > 0.0:
		return
	for i in 4:
		var index := (_attack_index + i) % 4
		var battery := batteries[index]
		if battery.destroyed:
			continue
		_attack_index = (index + 1) % 4
		battery.telegraph = WARNING
		battery.target = tank.global_position + tank.velocity * 0.6
		battery.target.y = Course.height_at(battery.target)
		if battery.kind in [BatteryKind.MORTAR, BatteryKind.SPORE]:
			World.current.fx.marker(battery.target, 3.8, WARNING + 1.7, Palette.HOT)
		Sfx.play("lock" if battery.kind == BatteryKind.ATGM else "warn", battery.node.global_position)
		_attack_timer = 1.1
		return

func _update_telegraph(battery: Battery, delta: float) -> void:
	var progress := 1.0 - battery.telegraph / WARNING
	match battery.kind:
		BatteryKind.FLAK:
			aim_barrel(battery.gun, battery.target + Vector3.UP, 5.0, delta)
			battery.barrels.rotation.z += delta * lerpf(3.0, 30.0, progress)
		BatteryKind.ATGM:
			# Tracking stops for the last 0.35 seconds: a deliberate window to sidestep the line.
			if battery.telegraph > 0.35:
				battery.target = player().hit_center()
			aim_barrel(battery.gun, battery.target, 5.0, delta)
			World.current.fx.beam(battery.muzzle.global_position, battery.target, Palette.HOT, 0.1 + progress * 0.15, 0.04)
		BatteryKind.MORTAR:
			slew_barrel(battery.gun, _lob(battery.muzzle.global_position, battery.target, 1.7), 5.0, delta)
		BatteryKind.SPORE:
			battery.sac.scale = Vector3.ONE * (1.0 + progress * 0.55 + sin(age * 24.0) * 0.04)
			aim_barrel(battery.gun, battery.target, 3.0, delta)

func _lob(from: Vector3, target: Vector3, flight: float) -> Vector3:
	return (target - from) / flight + Vector3.UP * (0.5 * QuadMech.MORTAR_GRAVITY * flight)

func _attack(battery: Battery) -> void:
	if battery.destroyed:
		return
	battery.attack_count += 1
	battery.sac.scale = Vector3.ONE
	var from := battery.muzzle.global_position
	match battery.kind:
		BatteryKind.FLAK:
			battery.burst = 10
			battery.burst_timer = 0.0
		BatteryKind.ATGM:
			var shot := fire_at("atgm", from, battery.target, 32.0, 0.0, Palette.HOT)
			shot.hit.kind = Hit.Kind.SHELL
			shot.hit.warhead = true
			shot.homing_target = player()
			shot.turn_rate = 0.65
			shot.interceptable = true
			shot.intercept_hp = 1.6
			shot.blast_radius = 2.8
			shot.blast_damage = 30.0
			shot.life = 6.0
			shot.trail = Projectile.ROCKET_SMOKE
			Sfx.play("launch", from, 2.0)
		BatteryKind.MORTAR, BatteryKind.SPORE:
			var shot := World.current.spawn_projectile(Team.ENEMY, from, _lob(from, battery.target, 1.7), "mortar", Palette.HOT)
			shot.gravity = QuadMech.MORTAR_GRAVITY
			shot.hit = Hit.make(Hit.Kind.SPORE if battery.kind == BatteryKind.SPORE else Hit.Kind.SHELL, 0.0, from)
			shot.hit.source = self
			shot.blast_radius = 3.8
			shot.blast_damage = 24.0
			shot.life = 2.8
			shot.interceptable = true
			shot.intercept_hp = 1.0
			muzzle_blast(from, shot.velocity.normalized(), Muzzle.HEAVY, "mortar")
			Sfx.play("spore" if battery.kind == BatteryKind.SPORE else "launch", from, 2.0)

func _spawn_roots(delta: float) -> void:
	_spawn_time -= delta
	if _spawn_time > 0.0 or _spawn_index >= 4:
		return
	_spawn_time = 3.0
	_spawn_index += 1
	# Wet pockets along the outer moat let the leeches still hunt while the centre is dry.
	var side := -1.0 if _spawn_index % 2 else 1.0
	var leech := CanalLeech.new()
	leech.position = Course.ground_at(Stage2.ARENA_CENTER_D + 34, side * 58)
	World.current.add_enemy(leech)
	var crawler: Enemy = load(Director.ENEMY_SCRIPTS.crawler).new()
	crawler.position = Course.ground_at(Stage2.GATE_D - 15, side * 16)
	World.current.add_enemy(crawler)
	var gnat := GnatSwarm.new()
	gnat.position = to_global(Vector3(side * 33, 18, 6))
	World.current.fx.spores(gnat.position, 18, 2.5)
	World.current.add_enemy(gnat)

func _process_geysers(delta: float) -> void:
	for geyser: Dictionary in _geysers.duplicate():
		geyser.time -= delta
		if geyser.time <= 0.0:
			geyser_impact(geyser.center)
			_geysers.erase(geyser)
	_geyser_time -= delta
	if _geyser_time <= 0.0 and player() != null and not player().dead:
		_geyser_time = 3.0
		var center := player().global_position + player().velocity * 0.4
		center.y = Course.height_at(center)
		_geysers.append({"center": center, "time": GEYSER_WARNING})
		World.current.fx.marker(center, GEYSER_RADIUS, GEYSER_WARNING, Palette.HOT)
		Sfx.play("warn", center, 1.0, 0.8)

func geyser_impact(center: Vector3) -> void:
	if dead or not core_exposed:
		return
	var world := World.current
	Sfx.play("geyser", center, 3.0)
	world.fx.spores(center, 30, GEYSER_RADIUS)
	for i in 12:
		world.fx.spawn(Fx.Kind.GLOW, center + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), Vector3(0, randf_range(12, 25), 0), 0.65, 1.0, Palette.FUNGUS, {"gravity": 20.0, "end_size": 2.0})
	var tank := player()
	# A floor hazard, not a spherical blast inflated by the hull's collision radius.
	if tank != null and not tank.dead and Vector2(tank.global_position.x - center.x, tank.global_position.z - center.z).length() <= GEYSER_RADIUS:
		var hit := Hit.make(Hit.Kind.SPORE, GEYSER_DAMAGE, center, Vector3.UP)
		hit.source = self
		tank.take_hit(hit)

func tick(delta: float) -> void:
	age += delta
	_update_water(delta)
	_update_torrents(delta)
	if dead:
		_death_clock += delta
		_update_ruin(delta)
		return
	behave(delta)

func behave(delta: float) -> void:
	_phase_clock += delta
	if phase == Phase.GATES:
		_process_batteries(delta)
	else:
		_update_intakes(delta)
		_spawn_roots(delta)
		if phase == Phase.DRAINED and _phase_clock >= DRAINED_TIME:
			expose_core()
		elif phase == Phase.CORE:
			_process_geysers(delta)
	if _core.visible:
		_core.scale = Vector3.ONE * (1.0 + sin(age * 5.0) * 0.035)

func die(hit: Hit) -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	core_hp = 0.0
	intake_active = false
	_geysers.clear()
	_core.visible = false
	_growth.visible = false
	for swirl in _swirls:
		swirl.visible = false
	_lower_water(-3.0)
	(Course.stage as Stage2).dawn = 1.0
	for piece in _pieces:
		piece.state = Dam.State.BROKEN
		piece.launch_at = randf_range(0.0, 0.7)
		piece.velocity = Vector3(randf_range(-5, 5), randf_range(1, 7), randf_range(4, 12))
		piece.spin = Vector3(randf_range(-1.5, 1.5), randf_range(-1, 1), randf_range(-1.5, 1.5))
	on_death(hit)
	died.emit(self)
	World.current.unregister(self)
	# Remain as inert masonry during Director's clear delay; the stage owns the rubble lifetime.

func _update_ruin(delta: float) -> void:
	for piece in _pieces:
		if piece.state == Dam.State.BROKEN and _death_clock >= piece.launch_at:
			piece.state = Dam.State.FLYING
		if piece.state != Dam.State.FLYING:
			continue
		piece.velocity.y -= Dam.GRAVITY * delta
		piece.node.position += piece.velocity * delta
		piece.node.rotation += piece.spin * delta
		var at := piece.node.global_position
		var ground := Course.height_at(at) + 0.6
		if at.y <= ground and piece.velocity.y < 0.0:
			piece.state = Dam.State.LANDED
			at.y = ground
			piece.node.global_position = at
			piece.node.scale *= 0.55
			World.current.fx.dust(at, 5, 2.5, Palette.MIST)
			Sfx.play("rubble", at, -4.0, 0.65)

func on_death(hit: Hit) -> void:
	var world := World.current
	world.award(score, global_position + Vector3.UP * 12, true)
	world.style_event("GIANT", 500.0)
	world.fx.debris(_core.global_position, 60, debris, 25.0, 0.8, global_basis.z)
	world.fx.spores(_core.global_position, 50, 5.0)
	world.fx.explosion(_core.global_position, 9.0, [Palette.WHITE, Palette.FUNGUS, Palette.HOT])
	world.shake(0.8, global_position)
	Sfx.play("core_death", global_position, 5.0)

func module_states() -> Array:
	var states := []
	for battery in batteries:
		states.append([battery.name, battery.hp / BATTERY_HP])
	states.append(["CORE", core_hp / CORE_HP])
	return states

func aim_parts() -> Dictionary:
	var result := {}
	if dead:
		return result
	if phase == Phase.GATES:
		for battery in batteries:
			if not battery.destroyed:
				result[battery.name] = [battery.node.global_position + Vector3.UP, BATTERY_RADIUS, battery.name]
	elif core_exposed:
		result["CORE"] = [model.global_transform * CORE_OFFSET, CORE_RADIUS, "CORE"]
	return result
