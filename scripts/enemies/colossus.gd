class_name Colossus
extends Enemy
## Mid-boss rooted in the schoolyard. Three glowing nodes hide under spongy caps that burn off
## with fire (or wear down under heavy fire). With every node destroyed the core opens.
## Hits retain their weapon damage; damage left after breaking a cap reaches the node below.
## Attacks: half-corridor tendril sweeps, spore barrages and crawler spawns; the exposed core
## adds a full sweep that must be dodged with an anchor drift.

enum Attack { NONE, SWEEP, BARRAGE, SPAWN }

const NODE_HP := 100.0
const CAP_HP := 100.0
const CORE_HP := 600.0
const PART_LABELS := {"left": "NODE L", "right": "NODE R", "top": "NODE TOP", "core": "CORE"}

class Part:
	var name := ""
	var offset := Vector3.ZERO
	var radius := 1.5
	var hp := 0.0
	var cap := 0.0
	var mesh: MeshInstance3D
	var cap_mesh: MeshInstance3D

var parts: Array[Part] = []
var core: Part
var _attack := Attack.NONE
var _attack_time := 0.0
var _next_attack := 2.5
var _sweep_side := 1.0
var _sweep_full := false
var _sweep_hit := false
var _sweep_d := 0.0
var _tendril: Array[MeshInstance3D] = []
var _tendril_tip := Vector3.ZERO
var _hard := false
var _dying := 0.0
var _body_mesh: MeshInstance3D


func _init() -> void:
	super()
	radius = 8.0
	center_height = 5.0
	can_stagger = true
	stabbable = true
	score = 20000
	despawn_behind = 0.0
	debris = [Fx.Debris.FLESH, Fx.Debris.SPORE]
	set_meta("title", "BOSS_COLOSSUS")


func build() -> void:
	_hard = Game.difficulty == Game.Difficulty.HARD
	# Its weak points are on its face: turn that face back up the road toward the tank.
	rotation.y = Course.yaw_at(Course.to_course(global_position).x)
	var b := LowPoly.new()
	b.blob(Transform3D(Basis().scaled(Vector3(1.4, 1.0, 1.1)), Vector3(0, 4.0, 0)), 6.5, Palette.MAUVE, 1, 0.3, 11)
	b.blob(Transform3D(Basis(), Vector3(-4.5, 2.5, 2.0)), 3.5, Palette.LILAC, 1, 0.3, 12)
	b.blob(Transform3D(Basis(), Vector3(4.8, 2.2, 1.0)), 3.2, Palette.LILAC, 1, 0.3, 13)
	b.blob(Transform3D(Basis(), Vector3(0, 9.5, -1.0)), 3.0, Palette.MAUVE, 1, 0.3, 14)
	# Mushroom crowns and roots spreading into the yard.
	for i in 7:
		var angle := TAU * i / 7.0
		b.prism(Transform3D(Basis(Vector3(cos(angle), 0, sin(angle)).cross(Vector3.UP), 0.3), Vector3(cos(angle) * 4.0, 7.0, sin(angle) * 3.0)), 0.4, 3.0, 5, Palette.CREAM, 0.2)
		b.prism(Transform3D(Basis(), Vector3(cos(angle) * 4.6, 9.8, sin(angle) * 3.4)), 1.6, 0.6, 7, Palette.FUNGUS, 0.3)
		b.box(Transform3D(Basis(Vector3.UP, angle), Vector3(cos(angle) * 9.0, 0.3, -sin(angle) * 9.0)), Vector3(8.0, 0.6, 1.0), Palette.MAUVE)
	_body_mesh = MeshInstance3D.new()
	_body_mesh.mesh = b.mesh()
	model.add_child(_body_mesh)
	for spec in [["left", Vector3(-4.8, 4.5, 3.6)], ["right", Vector3(5.0, 4.0, 3.2)], ["top", Vector3(0.0, 10.5, 1.8)]]:
		parts.append(_make_part(spec[0], spec[1], 1.7, NODE_HP, CAP_HP))
	core = _make_part("core", Vector3(0, 4.5, 5.2), 2.4, CORE_HP, 0.0)
	core.mesh.visible = false
	max_hp = _total_hp()
	hp = max_hp
	set_meta("phase_marks", [CORE_HP / max_hp])
	for i in 9:
		var segment := MeshInstance3D.new()
		segment.mesh = LowPoly.new().blob(Transform3D(), 1.2 - i * 0.08, Palette.MAUVE if i % 2 else Palette.LILAC, 0, 0.25, i).mesh()
		segment.visible = false
		add_child(segment)
		segment.top_level = true
		_tendril.append(segment)
	Sfx.play("roar", global_position)


func _make_part(part_name: String, offset: Vector3, r: float, part_hp: float, cap_hp: float) -> Part:
	var part := Part.new()
	part.name = part_name
	part.offset = offset
	part.radius = r
	part.hp = part_hp
	part.cap = cap_hp
	part.mesh = MeshInstance3D.new()
	var glow := LowPoly.new()
	glow.glow = true
	glow.blob(Transform3D(), r, Palette.FUNGUS if part_name == "core" else Palette.BLUSH, 1, 0.15, part_name.length())
	part.mesh.mesh = glow.mesh()
	part.mesh.position = offset
	model.add_child(part.mesh)
	if cap_hp > 0.0:
		part.cap_mesh = MeshInstance3D.new()
		part.cap_mesh.mesh = LowPoly.new().blob(Transform3D(Basis().scaled(Vector3(1.2, 0.8, 1.2)), Vector3.ZERO), r * 1.25, Palette.PEACH, 0, 0.35, part_name.length() + 3).mesh()
		part.cap_mesh.position = offset + Vector3(0, 0.3, 0.4)
		model.add_child(part.cap_mesh)
	return part


func _live_parts() -> Array[Part]:
	var result: Array[Part] = []
	for part in parts:
		if part.hp > 0.0:
			result.append(part)
	if result.is_empty() and core.hp > 0.0:
		result.append(core)
	return result


## The weak points the sight can lock one by one: the capped nodes, then the core once they fall.
func aim_parts() -> Dictionary:
	var result := {}
	if _dying > 0.0:
		return result
	for part in _live_parts():
		result[part.name] = [global_transform * part.offset, part.radius, PART_LABELS[part.name]]
	return result


## Each node's cap and flesh together, then the core.
func module_states() -> Array:
	var states: Array = parts.map(func(part: Part) -> Array: return [PART_LABELS[part.name], clampf((part.hp + part.cap) / (NODE_HP + CAP_HP), 0.0, 1.0)])
	states.append([PART_LABELS.core, clampf(core.hp / CORE_HP, 0.0, 1.0)])
	return states


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	# The body blocks shots; parts are checked separately in take_hit via the impact point.
	var t := Entity.segment_sphere(from, to, global_position + Vector3(0, 4.5, 0), 7.5 + extra_radius)
	for part in _live_parts():
		var pt := Entity.segment_sphere(from, to, global_transform * part.offset, part.radius + extra_radius)
		if pt >= 0.0 and (t < 0.0 or pt < t):
			t = pt
	return t


func hit_center() -> Vector3:
	var live := _live_parts()
	return global_transform * live[0].offset if not live.is_empty() else global_position + Vector3.UP * 5.0


func take_hit(hit: Hit) -> void:
	if dead or invulnerable or _dying > 0.0 or hit.damage <= 0.0:
		return
	var world := World.current
	# Find the part nearest the impact (blasts reach any part within their falloff).
	var best: Part = null
	var best_distance := INF
	for part in _live_parts():
		var distance := hit.position.distance_to(global_transform * part.offset) - part.radius
		if distance < best_distance:
			best_distance = distance
			best = part
	if hit.stagger >= 1.0 and _attack == Attack.SWEEP and _attack_time < 1.2:
		_cancel_attack()
	_flesh_hit(hit)
	if best == null or best_distance > (2.5 if hit.kind != Hit.Kind.BLAST else 5.0):
		if hit.incendiary:
			world.fx.spawn(Fx.Kind.FLAME, hit.position, Vector3.UP * 2.0, 0.4, 0.6, Palette.PEACH)
		return
	var amount := hit.damage
	var health_before := _total_hp()
	if best.cap > 0.0:
		# Fire still burns caps four times faster; only the damage spent on the cap is absorbed.
		var multiplier := 4.0 if hit.kind == Hit.Kind.FIRE or hit.incendiary else 1.0
		var absorbed := minf(amount, best.cap / multiplier)
		best.cap = maxf(0.0, best.cap - absorbed * multiplier)
		amount -= absorbed
		best.cap_mesh.scale = Vector3.ONE * clampf(0.5 + best.cap / CAP_HP * 0.5, 0.5, 1.0)
		if best.cap <= 0.0:
			best.cap_mesh.visible = false
			world.fx.explosion(global_transform * best.offset, 2.0, [Palette.WHITE, Palette.PEACH, Palette.FUNGUS])
			world.fx.spores(global_transform * best.offset, 20, 2.0)
			Sfx.play("roar", global_position, -4.0, 1.3)
			world.shake(0.3)
	if hit.kind == Hit.Kind.SHELL and hit.pierce and hit.caliber < 100:
		amount *= 1.5
	best.hp = maxf(0.0, best.hp - amount)
	hp = _total_hp()
	impact_feedback(hit, health_before - hp, core.hp <= 0.0)
	if amount > 0.0:
		world.fx.spores(hit.position, 3, 0.5)
	if best.hp <= 0.0:
		best.mesh.visible = false
		world.fx.explosion(global_transform * best.offset, 3.5, [Palette.WHITE, Palette.BLUSH, Palette.FUNGUS, Palette.LILAC])
		world.hitstop(0.08)
		world.shake(0.5)
		world.award(2000, global_transform * best.offset, false)
		Sfx.play("roar", global_position, 0.0, 0.8)
		if best != core and _core_phase():
			core.mesh.visible = true
			world.radio.emit(&"AI_CORE")
			stagger = 2.0
	if core.hp <= 0.0:
		_begin_death()


## Every hit on the mass shows, weak point or not: it flinches away from the blow and flesh and
## spores burst out of the wound. A shell blows a crater in it and the whole mass rocks back.
func _flesh_hit(hit: Hit) -> void:
	var world := World.current
	var heavy := hit.kind in [Hit.Kind.SHELL, Hit.Kind.BLAST, Hit.Kind.RAM, Hit.Kind.TAIL, Hit.Kind.THROWN]
	flash()
	_shudder = maxf(_shudder, 0.25 if heavy else 0.1)
	model.position += global_basis.inverse() * hit.direction.normalized() * (1.4 if heavy else 0.3)
	var out := (-hit.direction.normalized() * 0.5 + Vector3.UP).normalized()
	world.fx.debris(hit.position, 10 if heavy else 3, debris, 12.0 if heavy else 7.0, 0.5 if heavy else 0.3, out)
	world.fx.spores(hit.position, 12 if heavy else 3, 1.5 if heavy else 0.5)
	Sfx.play("squelch", hit.position, 4.0 if heavy else -6.0, randf_range(0.7, 1.1))
	if hit.by_player():
		world.hit_confirmed.emit(false)
		Sfx.confirm_hit(false)
	if hit.kind == Hit.Kind.SHELL and hit.caliber >= 100:
		world.fx.explosion(hit.position, 2.5, [Palette.WHITE, Palette.BLUSH, Palette.FUNGUS, Palette.LILAC], hit.direction)
		world.hitstop(0.07)
		world.shake(0.45, hit.position)
		world.camera.kick(0.03)
		Sfx.play("roar", global_position, -6.0, 1.2)


func _total_hp() -> float:
	var total := maxf(core.hp, 0.0)
	for part in parts:
		total += maxf(part.hp, 0.0) + maxf(part.cap, 0.0)
	return total


func behave(delta: float) -> void:
	var world := World.current
	for part in parts + [core]:
		if part.mesh.visible:
			part.mesh.scale = Vector3.ONE * (1.0 + sin(age * 4.0 + part.offset.x) * 0.08)
	_body_mesh.scale = Vector3(1.0 + sin(age * 1.3) * 0.02, 1.0 + sin(age * 1.1) * 0.03, 1.0)
	if _dying > 0.0:
		_dying -= delta
		if randf() < delta * 8.0:
			var p := global_position + Vector3(randf_range(-7, 7), randf_range(1, 11), randf_range(-5, 5))
			world.fx.explosion(p, randf_range(1.5, 3.0), [Palette.WHITE, Palette.BLUSH, Palette.FUNGUS])
			Sfx.play("blast_small", p)
		model.scale.y = maxf(0.2, model.scale.y - delta * 0.25)
		if _dying <= 0.0:
			die(Hit.make(Hit.Kind.BLAST, 9999.0, global_position))
		return
	if is_staggered():
		return
	var tank := player()
	if tank == null:
		return
	if _attack == Attack.NONE:
		_next_attack -= delta
		if _next_attack <= 0.0:
			_choose_attack()
		return
	_attack_time += delta
	match _attack:
		Attack.SWEEP:
			_update_sweep(delta, tank)
		Attack.BARRAGE:
			if _attack_time >= 0.9:
				_barrage(tank)
				_end_attack()
		Attack.SPAWN:
			if _attack_time >= 0.6:
				_spawn_crawlers()
				_end_attack()


func _core_phase() -> bool:
	return parts.all(func(part: Part) -> bool: return part.hp <= 0.0)


func _choose_attack() -> void:
	var roll := randf()
	if roll < 0.5:
		_attack = Attack.SWEEP
		var tank := player()
		_sweep_full = _core_phase() and randf() < 0.5
		_sweep_side = signf(tank.course_u + 0.01) if randf() < 0.7 else -signf(tank.course_u + 0.01)
		_sweep_d = World.current.rail.d + tank.course_offset
		_sweep_hit = false
		_telegraph_sweep()
	elif roll < 0.8:
		_attack = Attack.BARRAGE
		flash()
		Sfx.play("squelch", global_position, 4.0, 0.5)
	else:
		_attack = Attack.SPAWN
		Sfx.play("roar", global_position, -6.0, 1.2)
	_attack_time = 0.0


func _end_attack() -> void:
	_attack = Attack.NONE
	var pace := 0.7 if _core_phase() else 1.0
	_next_attack = randf_range(1.4, 2.4) * pace * (0.8 if _hard else 1.0)
	for segment in _tendril:
		segment.visible = false


func _cancel_attack() -> void:
	World.current.fx.sparks(_tendril_tip, Vector3.UP, 12, Palette.FUNGUS)
	_end_attack()


## Ground markers along the half (or all) of the corridor about to be swept.
func _telegraph_sweep() -> void:
	var world := World.current
	for i in 7:
		var u := _sweep_side * (2.0 + i * 2.6) if not _sweep_full else -15.0 + i * 5.0
		world.fx.marker(Course.ground_at(_sweep_d, u), 2.2, 1.3, Palette.RED if not _sweep_full else Palette.BUTTER)
	Sfx.play("warn", Course.ground_at(_sweep_d, 0.0), 0.0, 0.7)
	if _sweep_full:
		world.radio.emit(&"AI_SWEEP")


func _update_sweep(delta: float, tank: Tank) -> void:
	var world := World.current
	var root := global_transform * Vector3(0, 3.0, 4.0)
	var start_u := 20.0 * _sweep_side if not _sweep_full else 20.0 * _sweep_side
	var end_u := 0.0 if not _sweep_full else -20.0 * _sweep_side
	var tip: Vector3
	if _attack_time < 1.3:
		# Rear up high over the sweep's starting edge.
		var k := _attack_time / 1.3
		tip = Course.ground_at(_sweep_d, start_u) + Vector3.UP * lerpf(4.0, 12.0, k)
	else:
		var k := clampf((_attack_time - 1.3) / 0.45, 0.0, 1.0)
		var u := lerpf(start_u, end_u, k)
		tip = Course.ground_at(_sweep_d, u) + Vector3.UP * lerpf(12.0, 1.2, minf(k * 3.0, 1.0))
		if k > 0.2:
			world.fx.dust(tip, 2, 1.5, Palette.OCHRE)
		if not _sweep_hit and absf(tank.course_u - u) < 3.0 and absf(world.rail.d + tank.course_offset - _sweep_d) < 5.0 and tip.y - tank.global_position.y < 3.0:
			_sweep_hit = true
			var hit := Hit.make(Hit.Kind.RAM, 26.0, tip, (tank.global_position - root).normalized())
			hit.source = self
			tank.take_hit(hit)
			if tank.damage_multiplier(hit) > 0.0:
				tank.course_u -= _sweep_side * 5.0
				world.hitstop(0.08)
		if k >= 1.0:
			world.shake(0.3)
			_end_attack()
			return
	_tendril_tip = tip
	for i in _tendril.size():
		var t := float(i) / (_tendril.size() - 1)
		var arc := root.lerp(tip, t) + Vector3.UP * sin(t * PI) * 5.0
		_tendril[i].global_position = arc
		_tendril[i].visible = true


func _barrage(tank: Tank) -> void:
	var world := World.current
	var from := global_position + Vector3(0, 11.0, 0)
	var count := 6 if not _core_phase() else 9
	for i in count:
		var flight := 1.5 + i * 0.08
		var target := tank.global_position + tank.velocity * flight * 0.5 + Vector3(randf_range(-9, 9), 0, randf_range(-6, 6))
		if i == 0:
			target = tank.global_position
		target.y = Course.height_at(target)
		var velocity_out := (target - from) / flight
		velocity_out.y += 0.5 * 20.0 * flight
		var mortar := world.spawn_projectile(Team.ENEMY, from, velocity_out, "mortar", Palette.FUNGUS)
		mortar.gravity = 20.0
		mortar.hit = Hit.make(Hit.Kind.SPORE, 0.0, from)
		mortar.hit.source = self
		mortar.blast_radius = 3.0
		mortar.blast_damage = 11.0
		mortar.blast_colors = [Palette.WHITE, Palette.BLUSH, Palette.FUNGUS, Palette.LILAC]
		mortar.interceptable = true
		mortar.intercept_hp = 1.0
		mortar.life = flight + 1.0
		world.fx.marker(target, 3.0, flight, Palette.FUNGUS)
	world.fx.spores(from, 30, 3.0)
	Sfx.play("spore", from, 4.0)


func _spawn_crawlers() -> void:
	var world := World.current
	for i in (3 if not _hard else 5):
		var crawler: Crawler = load("res://scripts/enemies/crawler.gd").new()
		var angle := randf_range(-0.8, 0.8)
		crawler.position = global_position + Vector3(sin(angle) * 11.0, 0, cos(angle) * 11.0)
		world.add_enemy(crawler)
		world.fx.dust(crawler.position, 6, 1.5, Palette.OCHRE)
		world.fx.spores(crawler.position, 8, 1.0)


func _begin_death() -> void:
	_dying = 2.4
	hp = 0.0
	_end_attack()
	World.current.shake(0.8)
	World.current.hitstop(0.2)
	World.current.screen_flash(Palette.WHITE, 0.6)


func on_death(_hit: Hit) -> void:
	var world := World.current
	world.fx.explosion(global_position + Vector3.UP * 4.0, 9.0, [Palette.WHITE, Palette.BLUSH, Palette.FUNGUS, Palette.LILAC])
	world.fx.spores(global_position + Vector3.UP * 4.0, 60, 8.0)
	world.award(score, global_position + Vector3.UP * 6.0, true)
	world.style_event("GIANT", 300.0)
	world.spawn_pickup("coax", Course.ground_at(Course.MIDBOSS_D - 30.0, 6.0) + Vector3.UP)
	world.spawn_pickup("repair", Course.ground_at(Course.MIDBOSS_D - 30.0, -6.0) + Vector3.UP)
	world.spawn_pickup("era", Course.ground_at(Course.MIDBOSS_D - 36.0, 0.0) + Vector3.UP)
	Sfx.play("blast", global_position)
