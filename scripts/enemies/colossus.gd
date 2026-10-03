class_name Colossus
extends Enemy
## Mid-boss rooted in the schoolyard. Three glowing nodes hide under spongy caps that burn off
## with fire (or wear down under heavy fire). With every node destroyed the core opens.
## Hits retain their weapon damage; damage left after breaking a cap reaches the node below.
## Cannon rounds count in rounds, not raw damage: a plain shell is worth ROUND_DAMAGE, coax a quarter
## on any weak point not burning; fire and full charges land in full, and a full charge on the open
## core counts double again. A round on the bare mass still reaches the nearest weak point, at half.
## Every attack shows where it will land before it hurts, and drifting sideways, moving or shooting a
## weak point gets out of it. Each lost node unlocks more of them (UNLOCK); with only the core left it
## layers a ground attack over a tendril one and rests for less.

enum Attack { NONE, SWEEP, BARRAGE, SPAWN, SPIKES, GEYSERS, SLAM, WALL, GRAB }

const NODE_HP := 150.0
const CAP_HP := 150.0
const CORE_HP := 900.0
const ROUND_DAMAGE := 40.0 ## What one plain main-gun round is worth; a full charge is worth two.
const BURN_TIME := 4.0 ## Seconds a node keeps taking full damage after fire touched it.
const WINDOW := 1.0 ## Seconds after each attack with none new: time for a full charge and its aim.
const STRIKE_DAMAGE := 33.0 ## Tendril lash and spore burst: a third of the tank's armor before its facing counts.
const SPIKE_DAMAGE := 30.0
const GEYSER_DAMAGE := 28.0
const SLAM_DAMAGE := 35.0
const GRAB_DAMAGE := 25.0 ## The crush when a grab has pulled the tank all the way in.
const WALL_DPS := 30.0 ## Armor a second inside the spore wall.
const UNLOCK := {Attack.SWEEP: 0, Attack.BARRAGE: 0, Attack.SPAWN: 0, Attack.SPIKES: 0, Attack.GEYSERS: 1, Attack.SLAM: 1, Attack.WALL: 2, Attack.GRAB: 3} ## Weak points lost before each attack is in play.
const WEIGHT := {Attack.SWEEP: 3.0, Attack.BARRAGE: 2.0, Attack.SPAWN: 1.0, Attack.SPIKES: 3.0, Attack.GEYSERS: 3.0, Attack.SLAM: 3.0, Attack.WALL: 2.0, Attack.GRAB: 2.0}
const TENDRIL_ATTACKS := [Attack.SWEEP, Attack.SLAM, Attack.GRAB] ## They share the one tendril, so only one runs at a time.
const COMBOS := [Attack.GEYSERS, Attack.SPIKES, Attack.BARRAGE] ## Ground attacks the core phase layers over a tendril one.
const COMBO_CHANCE := 0.7
const BARRAGE_WIND := 0.6
const SPAWN_WIND := 0.6
const SPIKE_LINES := 3 ## Cracks racing toward the tank; two more from the third phase.
const SPIKE_WIND := 0.5 ## Seconds the cracks are drawn before they start to run.
const CRACK_SPEED := 26.0
const SPIKE_GAP := 3.5 ## Metres between spikes along a crack.
const SPIKE_DELAY := 0.75 ## Seconds from the crack passing a spot to the spike.
const SPIKE_RADIUS := 2.0
const GEYSER_WARN := 0.9 ## Seconds a geyser's circle swells before it erupts.
const GEYSER_RADIUS := 3.4
const SLAM_RISE := 1.3
const SLAM_TIME := 0.45
const SLAM_HALF_WIDTH := 2.6 ## Half the lane the slam covers.
const WALL_WIND := 1.0 ## Seconds the wall grows out of the ground before it drifts.
const WALL_SPEED := 9.0
const WALL_HALF := 18.0 ## Half the wall's length across the road.
const WALL_DEPTH := 3.5 ## Half its thickness along the road.
const GAP_HALF := 3.6 ## Half the gap's width.
const GRAB_REACH := 1.0 ## Seconds the tendril hovers over the tank's tail before it drops.
const GRAB_DROP := 0.3
const GRAB_RADIUS := 3.0
const GRAB_HOLD := 1.6 ## Seconds it drags the tank in before the crush.
const GRAB_PULL := 12.0 ## Metres a second.
const TIP_RADIUS := 2.5 ## The raised tendril's tip as a target.
const SWEEP_RISE := 0.8 ## Seconds the tendril rears up over the sweep's starting edge.
const SWEEP_LASH := 0.3 ## Seconds the lash takes across the corridor.
const DYING_TIME := 1.0 ## Seconds from the killing blow to the final blast.
const DEATH_BLAST_RATE := 19.0 ## Random blasts a second while dying, as dense as the old 8 a second over 2.4 s.
const DEATH_SINK := 0.6 ## How much of its height it sinks by then.
const PART_LABELS := {"left": "NODE L", "right": "NODE R", "top": "NODE TOP", "core": "CORE"}

class Part:
	var name := ""
	var offset := Vector3.ZERO
	var radius := 1.5
	var hp := 0.0
	var cap := 0.0
	var burn := 0.0
	var mesh: MeshInstance3D
	var cap_mesh: MeshInstance3D

## A ground spot that erupts at `at` seconds into its move; `warn_at` is when its circle appears.
class Burst:
	var position := Vector3.ZERO
	var warn_at := 0.0
	var at := 0.0
	var radius := 2.0
	var damage := 0.0
	var geyser := false
	var shown := false
	var done := false


## One attack under way; the passive ones do not hold up the next.
class Move:
	var kind := Attack.NONE
	var time := 0.0
	var side := 1.0
	var full := false
	var lane := 0.0 ## Road u the attack is aimed along.
	var d := 0.0 ## Road d it is aimed at.
	var hit := false
	var passive := false
	var held := 0.0 ## Seconds a grab has dragged the tank.
	var spawned := 0
	var points: Array[Vector3] = []
	var bursts: Array[Burst] = []
	var props: Array[Node3D] = []

var parts: Array[Part] = []
var core: Part
var _moves: Array[Move] = []
var _last := Attack.NONE
var _next_attack := 1.5
var _tendril: Array[MeshInstance3D] = []
var _tendril_tip := Vector3.ZERO
var _tip_open := false ## The tendril is raised where a shot can cut it.
var _prop_meshes := {}
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
	if _tip_open:
		result["tip"] = [_tendril_tip, TIP_RADIUS, "TENDRIL"]
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
	if _tip_open:
		var tt := Entity.segment_sphere(from, to, _tendril_tip, TIP_RADIUS + extra_radius)
		if tt >= 0.0 and (t < 0.0 or tt < t):
			t = tt
	return t


func hit_center() -> Vector3:
	var live := _live_parts()
	return global_transform * live[0].offset if not live.is_empty() else global_position + Vector3.UP * 5.0


func take_hit(hit: Hit) -> void:
	if dead or invulnerable or _dying > 0.0 or hit.damage <= 0.0:
		return
	var world := World.current
	if _tip_open and hit.position.distance_to(_tendril_tip) <= TIP_RADIUS + 0.5:
		_hit_tip(hit)
		return
	# Find the part nearest the impact (blasts reach any part within their falloff).
	var best: Part = null
	var best_distance := INF
	for part in _live_parts():
		var distance := hit.position.distance_to(global_transform * part.offset) - part.radius
		if distance < best_distance:
			best_distance = distance
			best = part
	if hit.stagger >= 1.0:
		for move in _moves.filter(func(m: Move) -> bool: return m.kind == Attack.SWEEP and m.time < 1.2):
			_cancel(move)
	_flesh_hit(hit)
	if best == null:
		return
	var near := best_distance <= (2.5 if hit.kind != Hit.Kind.BLAST else 5.0)
	var amount := hit.damage * (1.0 if near else 0.5)
	if not near and hit.incendiary:
		world.fx.spawn(Fx.Kind.FLAME, hit.position, Vector3.UP * 2.0, 0.4, 0.6, Palette.PEACH)
	var health_before := _total_hp()
	if near and (hit.kind == Hit.Kind.FIRE or hit.incendiary):
		best.burn = BURN_TIME
	var cannon := hit.kind == Hit.Kind.SHELL and hit.caliber >= 100
	if cannon:
		amount *= ROUND_DAMAGE / Armament.SHELL_DAMAGE
	if best == core and cannon and hit.power >= 1.0:
		amount *= 2.0
	elif best.burn <= 0.0 and hit.power < 1.0:
		amount *= 0.25 if hit.kind == Hit.Kind.BULLET else 1.0
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
	if is_area_round(hit):
		amount *= HEAVY_AREA # Its hide shrugs off balls and fragments.
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
		if best != core and _phase() >= 3:
			core.mesh.visible = true
			stagger = 2.0
	if core.hp <= 0.0:
		killing_hit = hit.copy()
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
		part.burn = maxf(0.0, part.burn - delta)
		if part.mesh.visible:
			part.mesh.scale = Vector3.ONE * (1.0 + sin(age * 4.0 + part.offset.x) * 0.08)
	_body_mesh.scale = Vector3(1.0 + sin(age * 1.3) * 0.02, 1.0 + sin(age * 1.1) * 0.03, 1.0)
	if _dying > 0.0:
		_dying -= delta
		if randf() < delta * DEATH_BLAST_RATE:
			var p := global_position + Vector3(randf_range(-7, 7), randf_range(1, 11), randf_range(-5, 5))
			world.fx.explosion(p, randf_range(1.5, 3.0), [Palette.WHITE, Palette.BLUSH, Palette.FUNGUS])
			Sfx.play("blast_small", p)
		model.scale.y = maxf(0.2, model.scale.y - delta * DEATH_SINK / DYING_TIME)
		if _dying <= 0.0:
			die(Hit.make(Hit.Kind.BLAST, 9999.0, global_position))
		return
	if is_staggered():
		return
	var tank := player()
	if tank == null:
		return
	var busy := _moves.any(func(m: Move) -> bool: return not m.passive)
	if not busy:
		_next_attack -= delta
		if _next_attack <= 0.0:
			_choose_attack()
	for move in _moves.duplicate():
		move.time += delta
		match move.kind:
			Attack.SWEEP:
				_update_sweep(move, tank)
			Attack.BARRAGE:
				if move.time >= BARRAGE_WIND:
					_barrage(tank)
					_finish(move)
			Attack.SPAWN:
				if move.time >= SPAWN_WIND:
					_spawn_crawlers(move)
					_finish(move)
			Attack.SPIKES, Attack.GEYSERS:
				_update_bursts(move, tank)
			Attack.SLAM:
				_update_slam(move, tank)
			Attack.WALL:
				_update_wall(move, tank, delta)
			Attack.GRAB:
				_update_grab(move, tank, delta)


## Nodes lost so far: the attacks it has unlocked and how hard it presses.
func _phase() -> int:
	return parts.filter(func(part: Part) -> bool: return part.hp <= 0.0).size()


func _tank_d(tank: Tank) -> float:
	return World.current.rail.d + tank.course_offset


## The tank takes `damage` at `at`; true when it was not dodged or shielded by a drift's invulnerability.
func _strike(tank: Tank, kind: Hit.Kind, damage: float, at: Vector3) -> bool:
	var hit := Hit.make(kind, damage, at, (tank.global_position - at).normalized())
	hit.source = self
	var landed := tank.damage_multiplier(hit) > 0.0
	tank.take_hit(hit)
	return landed


func _choose_attack() -> void:
	var phase := _phase()
	var kinds: Array = UNLOCK.keys().filter(func(k: Attack) -> bool: return UNLOCK[k] <= phase and k != _last and not _moves.any(func(m: Move) -> bool: return m.kind == k))
	var roll: float = randf() * kinds.reduce(func(sum: float, k: Attack) -> float: return sum + WEIGHT[k], 0.0)
	var kind: Attack = kinds[0]
	for k: Attack in kinds:
		kind = k
		roll -= WEIGHT[k]
		if roll <= 0.0:
			break
	_begin(kind)
	if phase >= 3 and kind in TENDRIL_ATTACKS and randf() < COMBO_CHANCE:
		_begin(COMBOS.pick_random())


## Starts an attack and draws its telegraph.
func _begin(kind: Attack) -> Move:
	var tank := player()
	var world := World.current
	var move := Move.new()
	move.kind = kind
	move.d = _tank_d(tank)
	move.lane = tank.course_u
	_last = kind
	_moves.append(move)
	match kind:
		Attack.SWEEP:
			move.full = _phase() >= 2 and randf() < 0.5
			move.side = signf(tank.course_u + 0.01) if randf() < 0.7 else -signf(tank.course_u + 0.01)
			_telegraph_sweep(move)
		Attack.BARRAGE:
			flash()
			world.fx.spores(global_position + Vector3(0, 11.0, 0), 14, 2.0)
			Sfx.play("squelch", global_position, 4.0, 0.5)
		Attack.SPAWN:
			for i in 4 + _phase() + (2 if _hard else 0):
				var angle := randf_range(-0.8, 0.8)
				var spot := global_position + Vector3(sin(angle) * 11.0, 0, cos(angle) * 11.0)
				move.points.append(spot)
				world.fx.marker(spot, 2.0, SPAWN_WIND, Palette.PEACH)
			Sfx.play("roar", global_position, -6.0, 1.2)
		Attack.SPIKES:
			_telegraph_spikes(move)
		Attack.GEYSERS:
			Sfx.play("warn", global_position, 0.0, 0.9)
		Attack.SLAM:
			_telegraph_slam(move)
		Attack.WALL:
			_telegraph_wall(move)
		Attack.GRAB:
			_tendril_tip = global_transform * Vector3(0, 6.0, 6.0)
			Sfx.play("warn", global_position, 0.0, 0.5)
	return move


func _finish(move: Move) -> void:
	_moves.erase(move)
	for prop in move.props:
		if is_instance_valid(prop):
			prop.queue_free()
	if move.kind in TENDRIL_ATTACKS:
		_tip_open = false
		for segment in _tendril:
			segment.visible = false
	if not _moves.any(func(m: Move) -> bool: return not m.passive):
		_next_attack = WINDOW + randf_range(0.0, 0.5) * (1.0 - 0.2 * _phase()) * (0.8 if _hard else 1.0)


func _end_attack() -> void:
	for move in _moves.duplicate():
		_finish(move)
	_next_attack = maxf(_next_attack, WINDOW)


func _cancel(move: Move) -> void:
	World.current.fx.sparks(_tendril_tip, Vector3.UP, 12, Palette.FUNGUS)
	_finish(move)


## A shot at the raised tendril's tip: a slam is cut by a full charge, a grab lets go for any cannon round or stab.
func _hit_tip(hit: Hit) -> void:
	var world := World.current
	flash()
	world.fx.sparks(hit.position, -hit.direction, 8, Palette.FUNGUS)
	var move: Move = _moves.filter(func(m: Move) -> bool: return m.kind in [Attack.SLAM, Attack.GRAB])[0]
	var cuts := hit.power >= 1.0 if move.kind == Attack.SLAM else hit.kind != Hit.Kind.BULLET
	if not cuts:
		Sfx.play("squelch", hit.position, -4.0, 1.4)
		return
	world.fx.explosion(_tendril_tip, 2.0, [Palette.WHITE, Palette.BLUSH, Palette.FUNGUS])
	world.shake(0.3)
	world.hitstop(0.05)
	if hit.by_player():
		world.hit_confirmed.emit(false)
		Sfx.confirm_hit(false)
	Sfx.play("roar", global_position, -2.0, 1.4)
	_finish(move)


## Draws the tendril from the colossus's face to `tip`, arching over by `arch` metres.
func _show_tendril(tip: Vector3, arch := 5.0) -> void:
	var root := global_transform * Vector3(0, 3.0, 4.0)
	_tendril_tip = tip
	for i in _tendril.size():
		var t := float(i) / (_tendril.size() - 1)
		_tendril[i].global_position = root.lerp(tip, t) + Vector3.UP * sin(t * PI) * arch
		_tendril[i].visible = true


## Ground markers along the half (or all) of the corridor about to be swept.
func _telegraph_sweep(move: Move) -> void:
	var world := World.current
	for i in 7:
		var u := move.side * (2.0 + i * 2.6) if not move.full else -15.0 + i * 5.0
		world.fx.marker(Course.ground_at(move.d, u), 2.2, 1.3, Palette.RED if not move.full else Palette.BUTTER)
	Sfx.play("warn", Course.ground_at(move.d, 0.0), 0.0, 0.7)


func _update_sweep(move: Move, tank: Tank) -> void:
	var world := World.current
	var root := global_transform * Vector3(0, 3.0, 4.0)
	var start_u := 20.0 * move.side
	var end_u := 0.0 if not move.full else -20.0 * move.side
	var tip: Vector3
	if move.time < SWEEP_RISE:
		# Rear up high over the sweep's starting edge.
		var k := move.time / SWEEP_RISE
		tip = Course.ground_at(move.d, start_u) + Vector3.UP * lerpf(4.0, 12.0, k)
	else:
		var k := clampf((move.time - SWEEP_RISE) / SWEEP_LASH, 0.0, 1.0)
		var u := lerpf(start_u, end_u, k)
		tip = Course.ground_at(move.d, u) + Vector3.UP * lerpf(12.0, 1.2, minf(k * 3.0, 1.0))
		if k > 0.2:
			world.fx.dust(tip, 2, 1.5, Palette.OCHRE)
		if not move.hit and absf(tank.course_u - u) < 3.0 and absf(_tank_d(tank) - move.d) < 5.0 and tip.y - tank.global_position.y < 3.0:
			move.hit = true
			if _strike(tank, Hit.Kind.RAM, STRIKE_DAMAGE, tip):
				tank.course_u -= move.side * 5.0
				world.hitstop(0.08)
		if k >= 1.0:
			world.shake(0.3)
			_finish(move)
			return
	_show_tendril(tip)


func _barrage(tank: Tank) -> void:
	var world := World.current
	var from := global_position + Vector3(0, 11.0, 0)
	var count := 9 + 2 * _phase()
	for i in count:
		var flight := 1.1 + i * 0.05
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
		mortar.blast_damage = STRIKE_DAMAGE
		mortar.blast_colors = [Palette.WHITE, Palette.BLUSH, Palette.FUNGUS, Palette.LILAC]
		mortar.interceptable = true
		mortar.intercept_hp = 1.0
		mortar.life = flight + 1.0
		world.fx.marker(target, 3.0, flight, Palette.FUNGUS)
	world.fx.spores(from, 30, 3.0)
	Sfx.play("spore", from, 4.0)


func _spawn_crawlers(move: Move) -> void:
	var world := World.current
	for spot in move.points:
		var crawler: Crawler = load("res://scripts/enemies/crawler.gd").new()
		crawler.position = spot
		world.add_enemy(crawler)
		world.fx.dust(spot, 6, 1.5, Palette.OCHRE)
		world.fx.spores(spot, 8, 1.0)


## A cached mesh for the attacks' own parts, in the colossus's palette.
func _mesh(id: String) -> Mesh:
	if not _prop_meshes.has(id):
		var b := LowPoly.new()
		match id:
			"spike":
				b.prism(Transform3D(), 1.1, 4.5, 5, Palette.CREAM, 0.0)
				b.prism(Transform3D(Basis(), Vector3(1.0, 0, 0.6)), 0.7, 3.0, 5, Palette.BLUSH, 0.0)
				b.prism(Transform3D(Basis(), Vector3(-0.9, 0, -0.7)), 0.7, 3.2, 5, Palette.BLUSH, 0.0)
			"geyser":
				b.glow = true
				b.prism(Transform3D(), 1.0, 9.0, 7, Palette.FUNGUS, 1.25, Palette.WHITE)
			"strip":
				b.box(Transform3D(), Vector3.ONE, Palette.DUSK)
			"puff":
				b.blob(Transform3D(), 2.4, Palette.LILAC, 1, 0.3, 21)
		_prop_meshes[id] = b.mesh()
	return _prop_meshes[id]


## A short-lived prop that shoots up out of the ground at `position` and sinks again.
func _eruption(id: String, position: Vector3, width: float, hold: float) -> void:
	var node := MeshInstance3D.new()
	node.mesh = _mesh(id)
	World.current.add_child(node)
	node.global_position = position
	node.scale = Vector3(width, 0.02, width)
	var tween := node.create_tween()
	tween.tween_property(node, "scale", Vector3(width, 1.0, width), 0.12)
	tween.tween_interval(hold)
	tween.tween_property(node, "scale", Vector3(width, 0.02, width), 0.25)
	tween.tween_callback(node.queue_free)


## Cracks run from the colossus toward the tank and spikes follow along them (drift off the line).
func _telegraph_spikes(move: Move) -> void:
	var world := World.current
	var root_d := Course.to_course(global_position).x - 7.0
	var lines := SPIKE_LINES + (2 if _phase() >= 2 else 0)
	for i in lines:
		var u := move.lane + (i - (lines - 1) * 0.5) * 6.0
		var from := Course.ground_at(root_d, 0.0)
		var to := Course.ground_at(move.d - 4.0, u)
		world.fx.beam(from + Vector3.UP * 0.3, to + Vector3.UP * 0.3, Palette.RED, 0.3, SPIKE_WIND + 1.5)
		var length := Vector2(from.x - to.x, from.z - to.z).length()
		for s in range(1, int(length / SPIKE_GAP) + 1):
			var f := s * SPIKE_GAP / length
			var burst := Burst.new()
			burst.position = Course.ground_at(lerpf(root_d, move.d - 4.0, f), lerpf(0.0, u, f))
			burst.warn_at = SPIKE_WIND + s * SPIKE_GAP / CRACK_SPEED
			burst.at = burst.warn_at + SPIKE_DELAY
			burst.radius = SPIKE_RADIUS
			burst.damage = SPIKE_DAMAGE
			move.bursts.append(burst)
	Sfx.play("warn", Course.ground_at(root_d, 0.0), 0.0, 0.6)
	world.shake(0.2)

## Spikes and geysers both erupt at marked spots; geysers are laid one after another under where the tank is.
func _update_bursts(move: Move, tank: Tank) -> void:
	var world := World.current
	var geysers := 3 + _phase()
	if move.kind == Attack.GEYSERS:
		while move.spawned < geysers and move.time >= 0.4 + move.spawned * (0.4 if _phase() >= 3 else 0.5):
			var burst := Burst.new()
			burst.position = Vector3(tank.global_position.x, Course.height_at(tank.global_position), tank.global_position.z)
			burst.warn_at = move.time
			burst.at = move.time + GEYSER_WARN
			burst.radius = GEYSER_RADIUS
			burst.damage = GEYSER_DAMAGE
			burst.geyser = true
			move.bursts.append(burst)
			move.spawned += 1
	for burst in move.bursts:
		if not burst.shown and move.time >= burst.warn_at:
			burst.shown = true
			world.fx.marker(burst.position, burst.radius, burst.at - burst.warn_at, Palette.FUNGUS if burst.geyser else Palette.RED)
			world.fx.dust(burst.position, 3, 1.0, Palette.OCHRE)
		if not burst.done and move.time >= burst.at:
			burst.done = true
			_erupt(burst, tank)
	if move.bursts.all(func(b: Burst) -> bool: return b.done) and (move.kind != Attack.GEYSERS or move.spawned >= geysers):
		_finish(move)


func _erupt(burst: Burst, tank: Tank) -> void:
	var world := World.current
	_eruption("geyser" if burst.geyser else "spike", burst.position, burst.radius if burst.geyser else 1.0, 0.45 if burst.geyser else 0.3)
	world.fx.spores(burst.position, 10 if burst.geyser else 4, burst.radius)
	world.fx.dust(burst.position, 6, burst.radius, Palette.OCHRE)
	Sfx.play("squelch" if burst.geyser else "stab", burst.position, 0.0, randf_range(0.7, 1.0))
	if Vector2(tank.global_position.x - burst.position.x, tank.global_position.z - burst.position.z).length() < burst.radius:
		_strike(tank, Hit.Kind.SPORE if burst.geyser else Hit.Kind.RAM, burst.damage, burst.position)
		world.hitstop(0.05)


## The road span a slam covers, from the colossus's face to past the tank: x is the near end, y the far one.
func _slam_span(move: Move) -> Vector2:
	return Vector2(Course.to_course(global_position).x - 7.0, move.d - 12.0)


## A dark strip along the tank's lane, ringed in red, under the tendril rearing over it.
func _telegraph_slam(move: Move) -> void:
	var world := World.current
	var span := _slam_span(move)
	var mid := (span.x + span.y) * 0.5
	var strip := MeshInstance3D.new()
	strip.mesh = _mesh("strip")
	world.add_child(strip)
	strip.global_transform = Transform3D(Basis(Vector3.UP, Course.yaw_at(mid)) * Basis.from_scale(Vector3(SLAM_HALF_WIDTH * 2.0, 0.05, span.x - span.y)), Course.ground_at(mid, move.lane) + Vector3.UP * 0.12)
	move.props.append(strip)
	for i in int((span.x - span.y) / 4.0) + 1:
		world.fx.marker(Course.ground_at(span.y + i * 4.0, move.lane), SLAM_HALF_WIDTH, SLAM_RISE, Palette.RED)
	Sfx.play("warn", Course.ground_at(span.x, move.lane), 0.0, 0.6)


## The tendril rears over the lane's near end, then slams down along it.
func _update_slam(move: Move, tank: Tank) -> void:
	var world := World.current
	var span := _slam_span(move)
	var tip: Vector3
	_tip_open = move.time < SLAM_RISE
	if _tip_open:
		tip = Course.ground_at(span.x, move.lane) + Vector3.UP * lerpf(4.0, 14.0, move.time / SLAM_RISE)
	else:
		var k := clampf((move.time - SLAM_RISE) / SLAM_TIME, 0.0, 1.0)
		var d := lerpf(span.x, span.y, k)
		tip = Course.ground_at(d, move.lane) + Vector3.UP * lerpf(14.0, 1.2, minf(k * 4.0, 1.0))
		if k > 0.1:
			world.fx.dust(tip, 2, 2.0, Palette.OCHRE)
		if not move.hit and absf(tank.course_u - move.lane) < SLAM_HALF_WIDTH and absf(_tank_d(tank) - d) < 4.0 and tip.y - tank.global_position.y < 3.0:
			move.hit = true
			if _strike(tank, Hit.Kind.RAM, SLAM_DAMAGE, tip):
				world.hitstop(0.08)
		if k >= 1.0:
			world.shake(0.4)
			_finish(move)
			return
	_show_tendril(tip, 3.0)


## A wall of spore cloud grows across the road with one gap, then drifts toward the tank.
func _telegraph_wall(move: Move) -> void:
	var world := World.current
	var tank := player()
	move.passive = true
	move.lane = clampf(tank.course_u + randf_range(-8.0, 8.0), -9.0, 9.0)
	move.d = Course.to_course(global_position).x - 9.0
	for row in 2:
		for i in 12:
			var u := -WALL_HALF + 1.6 + i * 3.2
			if absf(u - move.lane) < GAP_HALF + 1.6:
				continue
			var puff := MeshInstance3D.new()
			puff.mesh = _mesh("puff")
			puff.set_meta("u", u)
			puff.set_meta("y", 2.2 + row * 3.4)
			world.add_child(puff)
			puff.global_position = Course.ground_at(move.d, u)
			puff.scale = Vector3.ONE * 0.05
			puff.create_tween().tween_property(puff, "scale", Vector3.ONE, WALL_WIND)
			move.props.append(puff)
	var gap := Course.ground_at(move.d, move.lane)
	world.fx.marker(gap, GAP_HALF, WALL_WIND, Palette.BUTTER)
	world.fx.beam(gap, gap + Vector3.UP * 9.0, Palette.BUTTER, 0.3, WALL_WIND)
	Sfx.play("warn", gap, 0.0, 0.8)


func _in_wall(move: Move, tank: Tank) -> bool:
	return absf(tank.course_u) <= WALL_HALF and absf(tank.course_u - move.lane) > GAP_HALF and absf(_tank_d(tank) - move.d) < WALL_DEPTH


func _update_wall(move: Move, tank: Tank, delta: float) -> void:
	var world := World.current
	if move.time >= WALL_WIND:
		move.d -= WALL_SPEED * delta
	for puff in move.props:
		var at := Course.ground_at(move.d, puff.get_meta("u"))
		puff.global_position = at + Vector3.UP * (puff.get_meta("y") as float)
		if randf() < delta * 1.5:
			world.fx.spores(puff.global_position, 3, 1.5)
	if move.time >= WALL_WIND and _in_wall(move, tank):
		move.held += delta
		if move.held >= 0.2:
			move.held -= 0.2
			_strike(tank, Hit.Kind.SPORE, WALL_DPS * 0.2, tank.global_position)
	else:
		move.held = 0.0
	if move.d < _tank_d(tank) - 25.0 or move.time > 14.0:
		_finish(move)


## A tendril hovers over the tank's tail, then drops on it; if it catches, it drags the tank in until a drift frees it or a shot cuts the tendril.
func _update_grab(move: Move, tank: Tank, delta: float) -> void:
	var world := World.current
	var target := tank.hit_center() if tank.tail.destroyed else tank.tail.claw_position()
	var tip := _tendril_tip
	var landed := GRAB_REACH + GRAB_DROP
	_tip_open = true
	if move.held > 0.0:
		move.held += delta
		if tank.is_dashing():
			Sfx.play("roar", global_position, -4.0, 1.5)
			_finish(move)
			return
		tank.course_offset += GRAB_PULL * delta
		tank.course_u = move_toward(tank.course_u, 0.0, 6.0 * delta)
		tip = target
		if move.held >= GRAB_HOLD:
			world.shake(0.5)
			_strike(tank, Hit.Kind.RAM, GRAB_DAMAGE, tip)
			_finish(move)
			return
	elif move.time < GRAB_REACH:
		tip = tip.lerp(target + Vector3.UP * 7.0, minf(delta * 4.0, 1.0))
		if fposmod(move.time, 0.25) < delta:
			world.fx.marker(Vector3(target.x, 0.0, target.z), GRAB_RADIUS, 0.3, Palette.BUTTER)
	elif move.time < landed:
		if move.points.is_empty():
			move.points.append(target)
		tip = tip.lerp(move.points[0], clampf((move.time - GRAB_REACH) / GRAB_DROP, 0.0, 1.0))
	else:
		tip = move.points[0]
		_tip_open = false
		if not move.hit:
			move.hit = true
			world.fx.dust(tip, 8, 2.0, Palette.OCHRE)
			if tip.distance_to(target) < GRAB_RADIUS and not tank.is_dashing():
				move.held = delta
		elif move.time > landed + 0.4:
			_finish(move)
			return
	_show_tendril(tip, 3.0)


func _begin_death() -> void:
	_dying = DYING_TIME
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
