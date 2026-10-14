class_name Borer
extends Enemy
## Stage 3 mid-boss: a terraforming tunnel-boring machine that fungus and a giant centipede have grown into.
## It hunts the pit on a trail of armoured segments. Shells break the cutterhead and the glowing spore pods;
## small arms glance off the plates. It charges across the pit, dives under the sand and bursts out
## beneath a marker, and lobs spores. At half hull the plates split open and it gets faster.

enum Phase { ARMORED, STRIPPED }
enum Attack { NONE, BORE, BURROW, ERUPT, SPORES }

const BODY_HP := 6000.0
const ROUND_DAMAGE := 40.0 ## Main-gun damage counts in rounds, like the other bosses.
const SEGMENTS := 15
const SPACING := 4.2
const SPEED := 15.0
const BORE_SPEED := 52.0
const WIND := 1.0
const WINDOW := 1.6
const POD_AT := [3, 6, 9, 12] ## Segment index of each spore pod.
const POD_HP := 110.0
const CUTTER_HP := 160.0
const BURROW_TIME := 1.6
const EXPOSED := 3.0 ## Seconds the head stays out after an eruption.
const HEAD_RADIUS := 5.0

var phase := Phase.ARMORED
var parts := {"cutter": CUTTER_HP, "pod_1": POD_HP, "pod_2": POD_HP, "pod_3": POD_HP, "pod_4": POD_HP}
var _cutter := Node3D.new()
var _segments: Array[Node3D] = []
var _pods := {}
var _trail: Array[Vector3] = []
var _attack := Attack.NONE
var _attack_time := 0.0
var _next_attack := 2.5
var _pattern := 0
var _aim := Vector3.ZERO
var _direction := Vector3.FORWARD
var _angle := 0.0
var _shots := 0
var _shot_timer := 0.0
var _exposed := 0.0
var _burrowed := false
var _hit_done := false
var _dying := 0.0
var _heading := Vector3.FORWARD


func _init() -> void:
	super()
	boss = true
	heavy = true
	max_hp = BODY_HP
	hp = max_hp
	armor = 30.0
	radius = HEAD_RADIUS
	center_height = 2.0
	score = 12000
	despawn_behind = 0.0
	set_meta("title", "BOSS_BORER")
	set_meta("phase_marks", [0.5])


func build() -> void:
	var b := LowPoly.new()
	# Head: a dark drill housing with pincers either side of the cutterhead and a fungus crest.
	b.box(Transform3D(Basis(), Vector3(0, 2.0, 1.0)), Vector3(5.0, 3.6, 5.6), Palette.SLATE, Palette.ASH)
	b.blob(Transform3D(Basis(), Vector3(0, 3.8, 1.6)), 1.6, Palette.FUNGUS, 0, 0.25)
	for side in [-1.0, 1.0]:
		b.tube(Transform3D(Basis.from_euler(Vector3(0, side * 0.35, 0)), Vector3(side * 2.9, 1.2, -2.0)), 0.5, 4.4, 6, Palette.OCHRE, 0.12)
		b.glow = true
		b.box(Transform3D(Basis(), Vector3(side * 1.1, 2.9, -1.55)), Vector3(0.7, 0.4, 0.1), Palette.HOT)
		b.glow = false
	_add_mesh(model, b.mesh())
	_cutter.position = Vector3(0, 2.0, -2.4)
	model.add_child(_cutter)
	var c := LowPoly.new()
	c.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5)), 2.9, 0.9, 12, Palette.STONE, 2.2)
	for i in 6:
		c.box(Transform3D(Basis(Vector3.BACK, i * PI / 3.0), Vector3.ZERO), Vector3(0.7, 5.8, 0.5), Palette.ASH)
	c.glow = true
	c.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -0.45)), 0.7, 0.2, 8, Palette.AMBER)
	_add_mesh(_cutter, c.mesh())
	for i in SEGMENTS:
		var seg := Node3D.new()
		seg.top_level = true
		add_child(seg)
		var s := LowPoly.new()
		var size := lerpf(1.0, 0.55, float(i) / SEGMENTS)
		s.frustum(Transform3D(Basis(), Vector3(0, 0.0, 0)), Vector2(4.6, 4.0) * size, Vector2(4.0, 3.6) * size, 3.2 * size, Palette.SLATE if i % 2 == 0 else Palette.DUSK, Palette.ASH)
		s.box(Transform3D(Basis(), Vector3(0, 3.5 * size, 0)), Vector3(3.0, 0.5, 2.4) * size, Palette.OCHRE)
		for side in [-1.0, 1.0]:
			s.tube(Transform3D(Basis.from_euler(Vector3(0, 0, side * 1.1)), Vector3(side * 2.6 * size, 0.6, 0)), 0.2, 3.0 * size, 5, Palette.INK)
			s.tube(Transform3D(Basis.from_euler(Vector3(0, 0, side * 0.4)), Vector3(side * 3.9 * size, -1.0, 0)), 0.14, 2.2 * size, 5, Palette.OCHRE)
		_add_mesh(seg, s.mesh())
		_segments.append(seg)
	for n in POD_AT.size():
		var pod := Node3D.new()
		pod.position = Vector3(0, 4.2, 0)
		_segments[POD_AT[n]].add_child(pod)
		_pods["pod_%d" % (n + 1)] = pod
		var g := LowPoly.new()
		g.glow = true
		g.blob(Transform3D(), 1.5, Palette.FUNGUS, 0, 0.25)
		_add_mesh(pod, g.mesh())


func _add_mesh(parent: Node3D, mesh: Mesh) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	parent.add_child(node)


func _ready() -> void:
	super()
	_trail.clear()
	for i in SEGMENTS * 8:
		_trail.append(global_position + Vector3.BACK * i * SPACING / 8.0)


func arena_center() -> Vector3:
	return Course.to_world(Stage3.PIT_D, 0.0)


func _bound() -> void:
	var offset := global_position - arena_center()
	offset.y = 0.0
	global_position = arena_center() + offset.limit_length(Stage3.PIT_RADIUS - radius)
	if not _burrowed:
		global_position.y = Course.height_at(global_position)


func _pod_world(name: String) -> Vector3:
	return _pods[name].global_position


func aim_parts() -> Dictionary:
	var result := {}
	if _dying > 0.0 or _burrowed:
		return result
	if parts.cutter > 0.0:
		result["cutter"] = [_cutter.global_position, 2.9, tr("BORER_CUTTER")]
	for name: String in _pods:
		if parts[name] > 0.0:
			result[name] = [_pod_world(name), 1.8, tr("BORER_" + name.to_upper())]
	return result


func module_states() -> Array:
	return parts.keys().map(func(name: String) -> Array: return [tr("BORER_CUTTER" if name == "cutter" else "BORER_" + name.to_upper()), maxf(parts[name], 0.0) / (CUTTER_HP if name == "cutter" else POD_HP)])


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	if _dying > 0.0 or _burrowed:
		return -1.0
	var best := Entity.segment_sphere(from, to, hit_center(), radius + extra_radius)
	for spec: Array in aim_parts().values():
		var distance := Entity.segment_sphere(from, to, spec[0], spec[1] + extra_radius)
		if distance >= 0.0 and (best < 0.0 or distance < best):
			best = distance
	for seg in _segments:
		var distance := Entity.segment_sphere(from, to, seg.global_position + Vector3.UP * 1.5, 2.6 + extra_radius)
		if distance >= 0.0 and (best < 0.0 or distance < best):
			best = distance
	return best


func take_hit(hit: Hit) -> void:
	if dead or invulnerable or _dying > 0.0 or _burrowed or hit.damage <= 0.0:
		return
	var amount := hit.damage * damage_multiplier(hit)
	if amount <= 0.0:
		return
	if (hit.kind == Hit.Kind.SHELL and (hit.caliber >= 100 or hit.weapon == "cannon")) or (hit.kind == Hit.Kind.BLAST and hit.weapon == "cannon"):
		amount *= ROUND_DAMAGE / Armament.SHELL_DAMAGE
	if hit.kind == Hit.Kind.SHELL:
		if parts.cutter > 0.0 and hit.position.distance_to(_cutter.global_position) <= 3.4:
			parts.cutter -= amount
			if parts.cutter <= 0.0:
				_break_part("cutter", _cutter, hit.direction)
		else:
			for name: String in _pods:
				if parts[name] > 0.0 and hit.position.distance_to(_pod_world(name)) <= 2.2:
					parts[name] -= amount
					if parts[name] <= 0.0:
						_break_part(name, _pods[name], hit.direction)
					break
	if _exposed > 0.0 or parts.cutter <= 0.0:
		amount *= 1.5
	hp = maxf(0.0, hp - amount)
	impact_feedback(hit, amount, hp <= 0.0)
	if hit.power >= 1.0 or hit.stagger >= 1.0:
		stagger = maxf(stagger, 0.2)
	if hp <= 0.0:
		killing_hit = hit.copy()
		_dying = 1.6
		_attack = Attack.NONE
		World.current.hitstop(0.15)
	elif phase == Phase.ARMORED and hp <= max_hp * 0.5:
		phase = Phase.STRIPPED
		for seg in _segments:
			var plate := seg.get_child(0) as Node3D
			plate.scale = Vector3(1.0, 1.0, 1.0) * 0.9
		World.current.fx.explosion(hit_center(), 4.0)
		Sfx.play("blast", global_position)


func _break_part(name: String, node: Node3D, direction: Vector3) -> void:
	parts[name] = 0.0
	World.current.fx.explosion(node.global_position, 2.0)
	if name != "cutter":
		Wreck.launch(node, node.global_position, 1.6, true, direction * 6.0 + Vector3.UP * 5.0)


func move_speed() -> float:
	return SPEED * (1.4 if phase == Phase.STRIPPED else 1.0)


func telegraphing() -> bool:
	return _attack != Attack.NONE and _attack_time < WIND * Game.telegraph_scale() and _attack != Attack.ERUPT


func behave(delta: float) -> void:
	var world := World.current
	if _dying > 0.0:
		_dying -= delta
		world.fx.smoke(hit_center(), 2, 4.0)
		world.fx.explosion(global_position + Vector3(randf_range(-6, 6), 2.0, randf_range(-6, 6)), 2.0)
		if _dying <= 0.0:
			die(killing_hit)
		_follow(delta)
		return
	var tank := player()
	_cutter.rotation.z += delta * (3.0 if _attack == Attack.BORE else 12.0) * (0.0 if parts.cutter <= 0.0 else 1.0)
	_exposed = maxf(0.0, _exposed - delta)
	if tank == null:
		return
	if is_staggered():
		_follow(delta)
		return
	if _attack not in [Attack.BORE, Attack.BURROW, Attack.ERUPT]:
		_angle += move_speed() / 40.0 * delta
		var goal := arena_center() + Vector3(cos(_angle), 0, sin(_angle)) * 40.0
		var before := global_position
		global_position = global_position.move_toward(Vector3(goal.x, global_position.y, goal.z), move_speed() * delta)
		var step := global_position - before
		step.y = 0.0
		if step.length() > 0.001:
			_heading = _heading.lerp(step.normalized(), minf(delta * 4.0, 1.0)).normalized()
	model.global_basis = Basis.looking_at(_heading, Vector3.UP)
	_update_attack(delta, tank)
	_bound()
	_follow(delta)


## Segments trail the head along its recent path, undulating as they go.
func _follow(delta: float) -> void:
	if _trail.is_empty() or _trail[0].distance_to(global_position) > SPACING / 8.0:
		_trail.push_front(global_position)
		if _trail.size() > SEGMENTS * 8 + 8:
			_trail.resize(SEGMENTS * 8 + 8)
	for i in SEGMENTS:
		var seg := _segments[i]
		var at := _trail[mini((i + 1) * 8, _trail.size() - 1)]
		var ahead := _trail[mini((i + 1) * 8 - 4, _trail.size() - 1)]
		var toward := ahead - at
		toward.y = 0.0
		seg.visible = not _burrowed
		seg.global_position = at + Vector3.UP * (0.4 + 0.3 * sin(age * 4.0 - i * 0.8))
		if toward.length() > 0.01:
			seg.global_basis = Basis.looking_at(toward.normalized(), Vector3.UP)
	visible = not _burrowed
	for seg in _segments:
		seg.visible = not _burrowed


func _begin_attack(kind: Attack) -> void:
	_attack = kind
	print("ATTACK kind=borer attack=%s phase=%d t=%.2f" % [Attack.keys()[kind], phase + 1, age])
	_attack_time = 0.0
	_shots = 0
	_shot_timer = 0.0
	_hit_done = false
	var tank := player()
	var world := World.current
	_aim = tank.global_position + tank.velocity * 0.6
	_aim.y = Course.height_at(_aim)
	_direction = (_aim - global_position) * Vector3(1, 0, 1)
	_direction = _direction.normalized()
	match kind:
		Attack.BORE:
			var from := global_position + Vector3.UP * 1.0
			world.fx.beam(from, from + _direction * 90.0, Palette.HOT, 0.8, WIND * Game.telegraph_scale())
			_heading = _direction
		Attack.BURROW:
			world.fx.dust(global_position, 20, 5.0, Palette.STRAW)
			world.fx.marker(global_position, radius + 2.0, WIND * Game.telegraph_scale(), Palette.RED)
		Attack.SPORES:
			world.fx.beam(hit_center(), _aim, Palette.HOT, 0.12, WIND * Game.telegraph_scale())
	Sfx.play("warn", global_position, 0.0, 0.7)


func _end_attack() -> void:
	_attack = Attack.NONE
	_next_attack = WINDOW * (0.7 if phase == Phase.STRIPPED else 1.0)


func _update_attack(delta: float, tank: Tank) -> void:
	var world := World.current
	if _attack == Attack.NONE:
		_next_attack -= delta
		if _next_attack <= 0.0:
			var options := [Attack.SPORES, Attack.BORE, Attack.BURROW]
			_begin_attack(options[_pattern % options.size()])
			_pattern += 1
		return
	_attack_time += delta
	if telegraphing():
		return
	match _attack:
		Attack.BORE:
			var from := global_position
			global_position += _direction * BORE_SPEED * (1.2 if phase == Phase.STRIPPED else 1.0) * delta
			_heading = _direction
			world.fx.dust(global_position, 2, 3.0, Palette.STRAW)
			if not _hit_done and Entity.segment_sphere(from, global_position, tank.hit_center(), radius + tank.radius) >= 0.0:
				_hit_done = true
				var hit := Hit.make(Hit.Kind.RAM, 30.0, hit_center(), _direction)
				hit.source = self
				tank.take_hit(hit)
			if _attack_time >= WIND * Game.telegraph_scale() + 1.7 or global_position.distance_to(arena_center()) >= Stage3.PIT_RADIUS - radius - 1.0:
				world.shake(0.3, global_position)
				_end_attack()
		Attack.BURROW:
			if not _burrowed:
				_burrowed = true
				invulnerable = true
				_attack_time = WIND * Game.telegraph_scale()
				_aim = tank.global_position + tank.velocity * 1.2
				_aim.y = Course.height_at(_aim)
				world.fx.marker(_aim, 7.0, BURROW_TIME, Palette.RED)
				Sfx.play("warn", _aim, 0.0, 0.6)
			world.fx.dust(global_position, 2, 3.0, Palette.STRAW)
			var target := Vector3(_aim.x, global_position.y, _aim.z)
			global_position = global_position.move_toward(target, 70.0 * delta)
			if _attack_time >= WIND * Game.telegraph_scale() + BURROW_TIME:
				_erupt(tank)
		Attack.ERUPT:
			if _attack_time >= 1.0:
				_end_attack()
		Attack.SPORES:
			_shot_timer -= delta
			if _shot_timer <= 0.0:
				_lob(tank)
				_shots += 1
				_shot_timer = 0.25
				if _shots >= 5:
					_end_attack()


func _erupt(tank: Tank) -> void:
	var world := World.current
	_burrowed = false
	invulnerable = false
	global_position.y = Course.height_at(global_position)
	_attack = Attack.ERUPT
	_attack_time = 0.0
	_exposed = EXPOSED
	world.fx.explosion(global_position, 7.0)
	world.fx.shockwave(global_position, 14.0, Palette.STRAW)
	world.fx.dust(global_position, 24, 7.0, Palette.STRAW)
	world.shake(0.5, global_position)
	Sfx.play("blast", global_position)
	if tank.global_position.distance_to(global_position) <= 8.0:
		var hit := Hit.make(Hit.Kind.BLAST, 30.0, global_position, Vector3.UP)
		hit.source = self
		tank.take_hit(hit)
	_trail.clear()
	for i in SEGMENTS * 8 + 8:
		_trail.append(global_position)


func _lob(tank: Tank) -> void:
	var world := World.current
	var from := hit_center() + Vector3.UP * 3.0
	var target := tank.global_position + tank.velocity * 1.3 + Vector3(randf_range(-7, 7), 0, randf_range(-7, 7))
	target.y = Course.height_at(target)
	var flight := 1.4
	var velocity := (target - from) / flight + Vector3.UP * 0.5 * 20.0 * flight
	var shell := world.spawn_projectile(Team.ENEMY, from, velocity, "mortar", Palette.FUNGUS)
	shell.gravity = 20.0
	shell.hit = Hit.make(Hit.Kind.SHELL, 0.0, from)
	shell.hit.source = self
	shell.blast_radius = 4.5
	shell.blast_damage = 18.0
	shell.interceptable = true
	shell.life = flight + 1.0
	world.fx.marker(target, 4.5, flight, Palette.RED)
	Sfx.play("launch", from, 0.0, 0.8)


func on_death(_hit: Hit) -> void:
	var world := World.current
	world.fx.explosion(hit_center(), 9.0)
	world.fx.debris(hit_center(), 30, debris, 18.0, 0.7)
	world.fx.dust(global_position, 24, 8.0, Palette.STRAW)
	world.award(score, hit_center(), true)
	world.style_event("GIANT", 300.0)
	for kind in ["coax", "repair", "era"]:
		world.spawn_pickup(kind, global_position + Vector3(randf_range(-8, 8), 1, randf_range(-8, 8)))
	for seg in _segments:
		world.fx.explosion(seg.global_position, 2.5)
		seg.visible = false
	Sfx.play("blast", global_position)
