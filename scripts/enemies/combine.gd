class_name Combine
extends Enemy
## Rice-mill mid-boss. The header locks a lane before mowing; the auger sweeps before firing.
## Machinery breaks independently, while the infected grain tank exposes the soft hull beneath.

enum Attack { NONE, MOW, CHAFF }

const BODY_HP := 3000.0
const HEADER_HP := 150.0
const AUGER_HP := 135.0
const TRACK_HP := 120.0
const MOW_WARN := 1.0
const CHAFF_WARN := 0.8
const STANDOFF := 56.0
const MOW_SPEED := 65.0
const MOW_DAMAGE := 38.0
const PART_LABELS := {"header": "REEL", "auger": "AUGER", "track_l": "TRACK L", "track_r": "TRACK R", "grain": "GRAIN"}
const PART_HP := {"header": HEADER_HP, "auger": AUGER_HP, "track_l": TRACK_HP, "track_r": TRACK_HP, "grain": BODY_HP}

class Part:
	var name := ""
	var hp := 0.0
	var offset := Vector3.ZERO
	var half := Vector3.ONE
	var node: Node3D

## A crawler released from the grain tank lands running, rather than bursting on leap touchdown.
class GrainCrawler extends Crawler:
	var falling := true
	var fall_velocity := Vector3.ZERO

	func build() -> void:
		var drop_y := position.y
		super()
		global_position.y = drop_y

	func behave(delta: float) -> void:
		if not falling:
			super(delta)
			return
		fall_velocity.y -= 24.0 * delta
		global_position += fall_velocity * delta
		var ground := Course.height_at(global_position)
		if global_position.y <= ground:
			global_position.y = ground
			falling = false
			World.current.fx.dust(global_position, 4, 1.0, Palette.OCHRE)


var parts: Dictionary = {}
var _header: Node3D
var _reel: MeshInstance3D
var _auger: Node3D
var _grain: MeshInstance3D
var _attack := Attack.NONE
var _attack_time := 0.0
var _next_attack := 2.0
var _alternate := false
var _lane := 0.0
var _start_d := 0.0
var _end_d := 0.0
var _mow_hit := false
var _hurt_once := false
var _dying := 0.0
var _death_hit: Hit
var _spray_target := Vector3.ZERO
var _auger_from := 0.0
var _auger_to := 0.0
var _engine_sound: AudioStreamPlayer3D


func _init() -> void:
	super()
	radius = 5.0
	center_height = 3.0
	stabbable = true
	score = 22000
	despawn_behind = 0.0
	debris = [Fx.Debris.METAL, Fx.Debris.ARMOR, Fx.Debris.FLESH, Fx.Debris.STRAW]
	mark_offsets = [-3.0, 3.0]
	set_meta("title", "BOSS_COMBINE")


func build() -> void:
	max_hp = BODY_HP
	hp = max_hp
	# Local -Z is the header; face the tank coming up the rail.
	rotation.y = Course.yaw_at(Course.to_course(global_position).x) + PI
	var b := LowPoly.new()
	b.box(Transform3D(Basis(), Vector3(0, 2.2, 1.0)), Vector3(5.5, 2.4, 6.2), Palette.OCHRE)
	b.box(Transform3D(Basis(), Vector3(0, 3.55, 1.2)), Vector3(5.8, 0.3, 6.7), Palette.CORAL)
	# Rear radiator, side slats, ladders and feeder throat distinguish the machine from a tank.
	for x in [-1.8, -0.9, 0.0, 0.9, 1.8]:
		b.box(Transform3D(Basis(), Vector3(x, 2.6, 4.16)), Vector3(0.12, 1.3, 0.12), Palette.INK)
	for side in [-1.0, 1.0]:
		for z in [0.0, 0.7, 1.4, 2.1]:
			b.box(Transform3D(Basis(), Vector3(side * 2.8, 2.6, z)), Vector3(0.12, 0.7, 0.16), Palette.INK)
		for y in [1.8, 2.3, 2.8, 3.3]:
			b.box(Transform3D(Basis(), Vector3(side * 2.9, y, -0.8)), Vector3(0.65, 0.12, 0.2), Palette.CREAM)
	b.box(Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, 2.3, -3.0)), Vector3(2.8, 1.3, 3.3), Palette.CORAL)
	b.box(Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 4.7, -0.4)), Vector3(3.9, 2.1, 2.8), Palette.INK)
	b.box(Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 4.8, -1.86)), Vector3(3.5, 1.55, 0.12), Palette.SKY)
	b.box(Transform3D(Basis(), Vector3(0, 5.9, -0.5)), Vector3(4.5, 0.25, 3.4), Palette.CORAL)
	for side in [-1.0, 1.0]:
		b.box(Transform3D(Basis(), Vector3(side * 1.82, 4.8, -1.96)), Vector3(0.12, 1.8, 0.18), Palette.CREAM)
	b.glow = true
	for x in [-2.0, 2.0]:
		b.box(Transform3D(Basis(), Vector3(x, 3.3, -2.0)), Vector3(0.45, 0.3, 0.18), Palette.BUTTER)
	_mesh(model, b.mesh())
	for side in [-1.0, 1.0]:
		var t := LowPoly.new()
		t.box(Transform3D(), Vector3(1.3, 1.8, 6.5), Palette.INK)
		for z in [-2.2, -0.75, 0.75, 2.2]:
			t.prism(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(side * 0.7, 0, z)), 0.65, 0.12, 8, Palette.STONE)
		for z in range(-3, 4):
			t.box(Transform3D(Basis(), Vector3(0, 0.96, z)), Vector3(1.45, 0.15, 0.25), Palette.CORAL)
		_part("track_l" if side < 0 else "track_r", Vector3(side * 3.0, 1.1, 1.0), Vector3(0.8, 1.1, 3.3), _mesh(model, t.mesh()))
	_header = Node3D.new()
	model.add_child(_header)
	_part("header", Vector3(0, 1.9, -5.1), Vector3(5.2, 1.6, 1.6), _header)
	var h := LowPoly.new()
	h.box(Transform3D(Basis(), Vector3(0, -0.5, 0.4)), Vector3(10.2, 0.45, 2.4), Palette.CORAL)
	for x in range(-5, 6):
		h.box(Transform3D(Basis(Vector3.UP, 0.15 * (x % 2)), Vector3(x, -0.45, -1.05)), Vector3(0.5, 0.16, 1.1), Palette.CREAM)
	for side in [-1.0, 1.0]:
		h.prism(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(side * 4.7, 0.4, 0)), 1.1, 0.22, 6, Palette.OCHRE)
	_mesh(_header, h.mesh())
	var r := LowPoly.new()
	r.prism(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), 0.18, 9.5, 8, Palette.INK)
	for i in 6:
		var a := TAU * i / 6.0
		r.box(Transform3D(Basis(Vector3.RIGHT, a), Vector3(0, cos(a), sin(a))), Vector3(9.1, 0.16, 0.16), Palette.CREAM)
		for x in [-4.2, 0.0, 4.2]:
			r.box(Transform3D(Basis(Vector3.RIGHT, a), Vector3(x, cos(a) * 0.5, sin(a) * 0.5)), Vector3(0.12, 1.0, 0.12), Palette.CORAL)
	_reel = _mesh(_header, r.mesh())
	_reel.position.y = 0.4
	var g := LowPoly.new()
	g.prism(Transform3D(), 2.5, 2.3, 8, Palette.OCHRE, 1.8)
	g.flesh = true
	for i in 7:
		var a := i * TAU / 7.0
		g.blob(Transform3D(Basis().scaled(Vector3(1.1, 0.65, 1.0)), Vector3(cos(a) * 1.4, 1.5, sin(a) * 1.3)), 0.95, Palette.FUNGUS if i % 2 else Palette.LILAC, 1, 0.18, i + 31)
		g.box(Transform3D(Basis(), Vector3(cos(a) * 2.0, 0.4, sin(a) * 1.8)), Vector3(0.22, 2.1, 0.22), Palette.BLUSH)
	g.glow = true
	g.blob(Transform3D(Basis(), Vector3(0, 0.7, -1.7)), 1.0, Palette.FUNGUS, 1, 0.15, 19)
	_grain = _mesh(model, g.mesh())
	_part("grain", Vector3(0, 7.0, 1.0), Vector3(2.6, 2.5, 2.3), _grain)
	_auger = Node3D.new()
	model.add_child(_auger)
	_part("auger", Vector3(2.4, 5.3, 1.6), Vector3(3.1, 0.7, 0.7), _auger)
	var a := LowPoly.new()
	a.prism(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(2.9, 0, 0)), 0.35, 5.8, 8, Palette.CREAM)
	a.box(Transform3D(Basis(), Vector3(2.7, 0.35, 0)), Vector3(5.6, 0.15, 0.4), Palette.CORAL)
	a.prism(Transform3D(Basis(), Vector3(5.6, -0.35, 0)), 0.6, 0.9, 6, Palette.FUNGUS)
	_mesh(_auger, a.mesh())
	_engine_sound = Sfx.loop("combine_engine", self, -5.0)


func _mesh(parent: Node3D, mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	parent.add_child(node)
	return node


func _part(name: String, offset: Vector3, half: Vector3, node: Node3D) -> void:
	var p := Part.new()
	p.name = name
	p.hp = PART_HP[name]
	p.offset = offset
	p.half = half
	p.node = node
	node.position = offset
	parts[name] = p


func _live(name: String) -> bool:
	return parts[name].hp > 0.0


func _part_frame(p: Part) -> Transform3D:
	# Auger bounds follow its swept arm, not a stationary sphere beside the hull.
	var frame := model.global_transform * Transform3D(Basis(), p.offset)
	if p.name == "auger":
		frame.basis *= Basis(Vector3.UP, _auger.rotation.y)
		frame.origin += frame.basis.x * 2.9
	return frame


func aim_parts() -> Dictionary:
	var result := {}
	if dead or _dying > 0.0:
		return result
	for name: String in parts:
		var p: Part = parts[name]
		if p.hp > 0.0:
			result[name] = [_part_frame(p).origin, 2.0 if name == "grain" else 1.2, PART_LABELS[name]]
	return result


func module_states() -> Array:
	var result: Array = []
	for name: String in parts:
		result.append([PART_LABELS[name], clampf(parts[name].hp / PART_HP[name], 0.0, 1.0)])
	return result


static func _box_hit(from: Vector3, to: Vector3, half: Vector3) -> float:
	var d := to - from
	var lo := 0.0
	var hi := 1.0
	for axis in 3:
		if absf(d[axis]) < 0.00001:
			if absf(from[axis]) > half[axis]:
				return -1.0
		else:
			var a := (-half[axis] - from[axis]) / d[axis]
			var b := (half[axis] - from[axis]) / d[axis]
			lo = maxf(lo, minf(a, b))
			hi = minf(hi, maxf(a, b))
			if lo > hi:
				return -1.0
	return lo * d.length()


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	if dead or _dying > 0.0:
		return -1.0
	var frame := model.global_transform.affine_inverse()
	var result := _box_hit(frame * from - Vector3(0, 3.0, 0.8), frame * to - Vector3(0, 3.0, 0.8), Vector3(2.8, 2.8, 3.5) + Vector3.ONE * extra_radius)
	for name: String in parts:
		var p: Part = parts[name]
		if p.hp <= 0.0:
			continue
		var inverse := _part_frame(p).affine_inverse()
		var t := _box_hit(inverse * from, inverse * to, p.half + Vector3.ONE * extra_radius)
		if t >= 0.0 and (result < 0.0 or t < result):
			result = t
	return result


func hit_center() -> Vector3:
	return global_transform * Vector3(0, 3.3, -0.5)


func _part_at(at: Vector3) -> Part:
	var best: Part = null
	var nearest := INF
	for name: String in parts:
		var p: Part = parts[name]
		if p.hp <= 0.0:
			continue
		var local := _part_frame(p).affine_inverse() * at
		var outside := local.abs() - p.half
		if maxf(outside.x, maxf(outside.y, outside.z)) > 0.65:
			continue
		var distance := local.length_squared()
		if distance < nearest:
			nearest = distance
			best = p
	return best


func take_hit(hit: Hit) -> void:
	if dead or invulnerable or _dying > 0.0 or hit.damage <= 0.0:
		return
	var part := _part_at(hit.position)
	# Blast damage samples hit_center; do not redirect filler into a distant weak point.
	var weak := part != null and part.name == "grain"
	# Heavy shells tear machinery off in one shot; the armored chassis absorbs most of the blast.
	# The soft grain mass takes twice that hull damage; HEAT doubles it once more.
	var amount := hit.damage * (0.35 if hit.kind in [Hit.Kind.BULLET, Hit.Kind.LASER] else 0.06)
	if hit.kind in [Hit.Kind.TAIL, Hit.Kind.FIRE]:
		amount = hit.damage
	if weak:
		amount *= 2.0
		if hit.kind == Hit.Kind.SHELL and hit.heat:
			amount *= 2.0
	var before := hp
	hp = maxf(0.0, hp - amount)
	parts.grain.hp = hp
	on_damaged(hit, before - hp)
	damaged.emit(self, hit)
	if hit.stagger >= 1.0:
		interrupt()
	if part != null and part.name != "grain":
		part.hp = maxf(0.0, part.hp - hit.damage)
		if part.hp <= 0.0:
			_break_part(part, hit)
	if hp <= 0.0:
		_begin_death(hit)


func on_damaged(hit: Hit, amount: float) -> void:
	super(hit, amount)
	if amount > 0.0 and not _hurt_once and hp > 0.0:
		_hurt_once = true
		_spawn_crawlers()


func _break_part(part: Part, hit: Hit) -> void:
	var world := World.current
	if (part.name == "header" and _attack == Attack.MOW) or (part.name == "auger" and _attack == Attack.CHAFF):
		_end_attack()
	# Detached pieces stop participating in flash, animation, targeting and collision.
	var detached: Array[GeometryInstance3D] = []
	for mesh in _meshes:
		if part.node == mesh or part.node.is_ancestor_of(mesh):
			mesh.material_overlay = rest_overlay
			detached.append(mesh)
	for mesh in detached:
		_meshes.erase(mesh)
	ActorLayer.unmark(part.node, ActorLayer.HOSTILE)
	world.fx.explosion(_part_frame(part).origin, 2.2, [Palette.WHITE, Palette.CORAL, Palette.FUNGUS])
	Wreck.launch(part.node, part.node.global_position, 2.0, hit.by_player(), Enemy.kill_push(hit) * 12.0 + Vector3.UP * 8.0, false)
	world.award(900, global_position + Vector3.UP * 3.0, false)


func behave(delta: float) -> void:
	if _live("header"):
		_reel.rotation.x += delta * (lerpf(2.0, 22.0, clampf(_attack_time / MOW_WARN, 0.0, 1.0)) if _attack == Attack.MOW else 2.0)
	if _dying > 0.0:
		_dying -= delta
		model.rotation.z += delta * 0.7
		if _dying <= 0.0:
			die(_death_hit)
		return
	if is_staggered() or player() == null:
		return
	var tank := player()
	match _attack:
		Attack.NONE:
			_reposition(delta, tank)
			_next_attack -= delta
			if _next_attack <= 0.0:
				_choose_attack(tank)
		Attack.MOW:
			_update_mow(delta, tank)
		Attack.CHAFF:
			_update_chaff(delta)


func reposition_speed() -> float:
	var lost := int(not _live("track_l")) + int(not _live("track_r"))
	return [28.0, 14.0, 7.0][lost]


func _reposition(delta: float, tank: Tank) -> void:
	var here := Course.to_course(global_position)
	var speed := reposition_speed()
	global_position = Course.ground_at(move_toward(here.x, World.current.rail.d + STANDOFF, speed * delta), move_toward(here.y, tank.course_u, speed * delta))


func _choose_attack(tank: Tank) -> void:
	if _live("header") and (not _alternate or not _live("auger")):
		# Line up before starting the full warning; broken tracks lengthen this reposition.
		if absf(Course.to_course(global_position).y - tank.course_u) > 2.0:
			_next_attack = 0.1
			return
		_start_mow(tank)
	elif _live("auger"):
		_start_chaff(tank)
	else:
		_next_attack = 1.0
	_alternate = not _alternate


func _start_mow(tank: Tank) -> void:
	_attack = Attack.MOW
	_attack_time = 0.0
	_start_d = Course.to_course(global_position).x
	_lane = Course.to_course(global_position).y
	_end_d = World.current.rail.d + Tank.FORWARD_LIMIT.x - 8.0
	_mow_hit = false
	var world := World.current
	# Full header-width bars down the locked corridor, all the way to the tank.
	for i in 6:
		var d := lerpf(_start_d - 5.0, _end_d, i / 5.0)
		world.fx.beam(Course.ground_at(d, _lane - 5.2) + Vector3.UP * 0.15, Course.ground_at(d, _lane + 5.2) + Vector3.UP * 0.15, Palette.RED, 0.3, MOW_WARN)
		world.fx.marker(Course.ground_at(d, _lane), 5.2, MOW_WARN, Palette.RED)
	Sfx.play("combine_reel", global_position)


func _update_mow(delta: float, tank: Tank) -> void:
	if not _live("header"):
		_end_attack()
		return
	var previous := Course.to_course(global_position).x
	_attack_time += delta
	_header.position.y = lerpf(1.9, 0.95, clampf(_attack_time / MOW_WARN, 0.0, 1.0))
	parts.header.offset.y = _header.position.y
	if _attack_time < MOW_WARN:
		return
	var charge_time := (_start_d - _end_d) / MOW_SPEED
	var elapsed := _attack_time - MOW_WARN
	if elapsed <= charge_time:
		var d := maxf(_end_d, _start_d - MOW_SPEED * elapsed)
		global_position = Course.ground_at(d, _lane)
		var tank_d := Course.to_course(tank.global_position).x
		# Swept header contact prevents long frames tunnelling over the tank or scenery.
		if not _mow_hit and absf(tank.course_u - _lane) < 5.2 + Tank.HULL_RADIUS and tank_d >= d - 7.0 and tank_d <= previous - 2.0:
			_mow_hit = true
			var hit := Hit.make(Hit.Kind.RAM, MOW_DAMAGE, tank.hit_center(), -global_basis.z)
			hit.source = self
			tank.take_hit(hit)
		_crush_path(previous, d)
		return
	var backoff := (_start_d - _end_d) / reposition_speed()
	var k := clampf((elapsed - charge_time) / backoff, 0.0, 1.0)
	global_position = Course.ground_at(lerpf(_end_d, _start_d, k), _lane)
	if k >= 1.0:
		_end_attack()


func _crush_path(from_d: float, to_d: float) -> void:
	var step := from_d
	while step >= to_d:
		for prop: Prop in World.current.props.in_radius(Course.ground_at(step - 5.0, _lane), 6.0):
			if not prop.is_falling() and prop.global_position.y < global_position.y + 3.0:
				var hit := Hit.make(Hit.Kind.RAM, 99999.0, prop.global_position, -global_basis.z)
				hit.source = self
				prop.take_hit(hit)
		step -= 3.0


func _start_chaff(tank: Tank) -> void:
	_attack = Attack.CHAFF
	_attack_time = 0.0
	_spray_target = tank.hit_center()
	_auger_from = _auger.rotation.y
	var local: Vector3 = model.global_transform.affine_inverse() * _spray_target - parts.auger.offset
	_auger_to = atan2(-local.z, local.x)
	Sfx.play("combine_auger", _auger.global_position)
	World.current.fx.marker(tank.global_position, 7.0, CHAFF_WARN, Palette.RED)
	World.current.fx.beam(_auger.global_position, _spray_target, Palette.RED, 0.22, CHAFF_WARN)


func _update_chaff(delta: float) -> void:
	if not _live("auger"):
		_end_attack()
		return
	_attack_time += delta
	_auger.rotation.y = lerp_angle(_auger_from, _auger_to, clampf(_attack_time / CHAFF_WARN, 0.0, 1.0))
	if _attack_time >= CHAFF_WARN:
		_spray()
		_end_attack()


func _spray() -> void:
	if not _live("auger"):
		return
	var from := _auger.global_transform * Vector3(5.6, -0.6, 0)
	var forward := (_spray_target - from).normalized()
	for i in 9:
		var dir := forward.rotated(Vector3.UP, (i - 4) * 0.075)
		var pellet := World.current.spawn_projectile(Team.ENEMY, from, dir * 38.0, "pellet", Palette.HOT)
		pellet.hit = Hit.make(Hit.Kind.SPORE, 8.0, from, dir)
		pellet.hit.source = self
		pellet.interceptable = true
		pellet.intercept_hp = 0.5
		pellet.life = 3.0
	World.current.fx.spores(from, 24, 2.0)
	Sfx.play("combine_chaff", from)


func _end_attack() -> void:
	_attack = Attack.NONE
	_attack_time = 0.0
	_next_attack = 1.3 if Game.difficulty == Game.Difficulty.NORMAL else 1.0
	if _live("header"):
		_header.position.y = 1.9
		parts.header.offset.y = 1.9


func interrupt() -> void:
	# Tail stabs cancel warnings, not a charge already committed to its locked corridor.
	if (_attack == Attack.MOW and _attack_time < MOW_WARN) or (_attack == Attack.CHAFF and _attack_time < CHAFF_WARN):
		World.current.fx.sparks(hit_center(), Vector3.UP, 18, Palette.BUTTER)
		_end_attack()
	super()


func _spawn_crawlers() -> void:
	for i in (3 if Game.difficulty == Game.Difficulty.NORMAL else 4):
		var crawler := GrainCrawler.new()
		crawler.position = global_transform * Vector3(-2.0 + i * 1.5, 7.8, 1.0)
		crawler.fall_velocity = Vector3((i - 1.0) * 3.0, 2.0, 5.0)
		World.current.add_enemy(crawler)
		World.current.fx.spores(crawler.position, 5, 0.7)
	Sfx.play("spore", _grain.global_position, -3.0)


func _begin_death(hit: Hit) -> void:
	_dying = 1.0
	_death_hit = hit
	hp = 0.0
	_end_attack()
	if _engine_sound:
		_engine_sound.stop()
	var at := _grain.global_position
	World.current.fx.explosion(at, 5.0, [Palette.WHITE, Palette.AMBER, Palette.HOT, Palette.FUNGUS])
	World.current.fx.spores(at, 55, 7.0)
	World.current.fx.embers(at, 40, 5.0)
	for i in 8:
		World.current.fx.tongue(at + Vector3(randf_range(-2, 2), 1, randf_range(-2, 2)), 3.0, 0.8)
	World.current.shake(0.8)
	World.current.hitstop(0.12)
	World.current.screen_flash(Palette.WHITE, 0.45)
	Sfx.play("combine_death", global_position)


func on_death(hit: Hit) -> void:
	mark_offsets.clear()
	var world := World.current
	var at := hit_center()
	world.fx.explosion(at, 8.0, [Palette.WHITE, Palette.AMBER, Palette.HOT, Palette.FUNGUS])
	world.fx.smoke_column(at, 5.0, [Palette.DUSK, Palette.INK, Palette.SLATE])
	world.award(score, at, true)
	world.style_event("GIANT", 300.0)
	world.spawn_pickup("coax", Course.ground_at(world.rail.d + 12.0, 6.0) + Vector3.UP)
	# The grain tank tears free and both wrecks cartwheel along the shot; landing adds a secondary pop.
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = rest_overlay
	ActorLayer.unmark(model, ActorLayer.HOSTILE)
	Wreck.launch(_grain, _grain.global_position, 2.4, hit.by_player(), Enemy.kill_push(hit) * 16.0 + Vector3.UP * 12.0, false)
	Wreck.launch(model, at, 5.0, hit.by_player(), Enemy.kill_push(hit) * 22.0 + Vector3.UP * 14.0)
	model = null
