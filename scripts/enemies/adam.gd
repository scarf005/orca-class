class_name Adam
extends BipedMech
## Construction biped that stands between the tank and its allies. The breaker marks one patch;
## the carried I-beam sweeps a wider arc. Exposed hydraulic hoses stop the breaker, legs stop both.

const SLAM_RADIUS := 7.5
const BEAM_REACH := 13.0

var hose_hp := 35.0
var disarmed := false
var _attack_timer := 1.0
var _wind := 0.0
var _breaker := true
var _next_breaker := true
var _impact := Vector3.ZERO
var _follow := 0.0
var _arm := Node3D.new()
var _hose := Node3D.new()
var _beam := Node3D.new()


func _init() -> void:
	super()
	max_hp = lerpf(Armament.QUICK_DAMAGE.x, Armament.QUICK_DAMAGE.y, Armament.STAGE_1) * Armament.SHELL_DAMAGE_SCALE * 2.5
	hp = max_hp
	radius = 2.3
	center_height = 3.0
	armor = 18.0
	score = 1000


## About 5 m tall: an industrial walker in construction yellow, hunched forward over thick armored legs, its
## cockpit glazed into the chest, exhaust stacks behind, a hydraulic breaker on the right arm and a girder in the left.
func build() -> void:
	super()
	build_legs(2.0, "heavy", Palette.AMBER, Palette.DUSK, 0.85)
	var b := LowPoly.new()
	b.box(Transform3D(Basis(), Vector3(0, 0.12, 0)), Vector3(1.4, 0.5, 0.95), Palette.DUSK)
	# Torso: a wide block leaning forward, flaring toward the shoulders, with hazard stripes along the belly.
	b.frustum(Transform3D(Basis(), Vector3(0, 0.35, 0.05)), Vector2(1.7, 1.35), Vector2(2.3, 1.6), 1.35, Palette.AMBER, Palette.AMBER, Vector2(0, -0.2))
	for i in 7:
		b.box(Transform3D(Basis(Vector3.BACK, 0.6), Vector3(-0.72 + i * 0.24, 0.55, -0.66)), Vector3(0.1, 0.42, 0.04), Palette.INK)
	b.box(Transform3D(Basis(), Vector3(0, 0.55, -0.64)), Vector3(1.75, 0.34, 0.02), Palette.BUTTER)
	# Cockpit: a raked glazed front with a black frame and two work lights above it.
	b.frustum(Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, 1.0, -0.78)), Vector2(1.25, 0.12), Vector2(1.1, 0.1), 0.62, Palette.INK)
	b.frustum(Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, 1.04, -0.85)), Vector2(1.05, 0.04), Vector2(0.92, 0.04), 0.5, Palette.SKY)
	b.box(Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, 1.29, -0.98)), Vector3(0.06, 0.55, 0.06), Palette.INK)
	b.box(Transform3D(Basis(), Vector3(0, 1.72, -0.55)), Vector3(1.6, 0.14, 0.5), Palette.DUSK)
	b.glow = true
	for x in [-0.55, 0.55]:
		b.box(Transform3D(Basis(), Vector3(x, 1.72, -0.81)), Vector3(0.3, 0.12, 0.04), Palette.BUTTER)
	b.box(Transform3D(Basis(), Vector3(0, 1.88, -0.1)), Vector3(0.22, 0.18, 0.22), Palette.AMBER) # Beacon.
	b.glow = false
	# Engine pack, side radiators and twin exhaust stacks.
	b.frustum(Transform3D(Basis(), Vector3(0, 0.45, 0.95)), Vector2(1.6, 0.7), Vector2(1.4, 0.6), 1.1, Palette.DUSK, Palette.SLATE)
	for side in [-1.0, 1.0]:
		b.prism(Transform3D(Basis(), Vector3(side * 0.45, 1.3, 1.05)), 0.12, 0.9, 6, Palette.INK)
		b.prism(Transform3D(Basis(), Vector3(side * 0.45, 2.15, 1.05)), 0.15, 0.12, 6, Palette.SLATE)
		for i in 3:
			b.box(Transform3D(Basis(), Vector3(side * 1.08, 0.75 + i * 0.22, 0.3)), Vector3(0.05, 0.08, 0.6), Palette.INK)
	add_mesh(_body, b.mesh())
	# Right arm: pauldron, a thick forearm with its ram, the breaker housing and a chisel pointing down.
	_arm.position = Vector3(1.35, 1.2, -0.1)
	_body.add_child(_arm)
	var a := LowPoly.new()
	a.blob(Transform3D(), 0.36, Palette.INK)
	a.frustum(Transform3D(Basis(), Vector3(0.1, 0.0, 0)), Vector2(0.9, 1.0), Vector2(0.6, 0.8), 0.45, Palette.DUSK, Palette.AMBER)
	limb(a, Vector3.ZERO, Vector3(0.1, -0.75, -0.1), Vector2(0.42, 0.45), Vector2(0.36, 0.4), Palette.SLATE)
	a.blob(Transform3D(Basis(), Vector3(0.1, -0.8, -0.1)), 0.28, Palette.INK)
	limb(a, Vector3(0.1, -0.8, -0.1), Vector3(0.1, -1.65, -0.2), Vector2(0.62, 0.66), Vector2(0.56, 0.6), Palette.AMBER)
	a.prism(Transform3D(Basis(), Vector3(-0.22, -1.6, 0.12)), 0.08, 0.8, 6, Palette.ASH)
	a.box(Transform3D(Basis(), Vector3(0.1, -1.95, -0.2)), Vector3(0.56, 0.6, 0.56), Palette.DUSK)
	a.prism(Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.1, -2.25, -0.2)), 0.16, 0.55, 6, Palette.STONE, 0.04)
	a.box(Transform3D(Basis(), Vector3(0.1, -1.95, -0.49)), Vector3(0.4, 0.12, 0.02), Palette.CORAL)
	add_mesh(_arm, a.mesh())
	_hose.position = Vector3(0.38, -0.75, 0.12)
	_arm.add_child(_hose)
	var h := LowPoly.new()
	for x in [-0.08, 0.0, 0.08]:
		h.prism(Transform3D(Basis(Vector3.RIGHT, 0.15), Vector3(x, -0.5, 0)), 0.05, 1.0, 6, Palette.CORAL)
	add_mesh(_hose, h.mesh())
	# Left arm: hanging to a clamp hand that carries a long I-beam level with the ground.
	_beam.position = Vector3(-1.35, 1.1, -0.1)
	_body.add_child(_beam)
	var steel := LowPoly.new()
	steel.blob(Transform3D(), 0.34, Palette.INK)
	steel.frustum(Transform3D(Basis(), Vector3(-0.1, 0.0, 0)), Vector2(0.85, 0.95), Vector2(0.55, 0.75), 0.4, Palette.DUSK, Palette.AMBER)
	limb(steel, Vector3.ZERO, Vector3(-0.1, -0.75, -0.15), Vector2(0.4, 0.44), Vector2(0.34, 0.4), Palette.SLATE)
	limb(steel, Vector3(-0.1, -0.75, -0.15), Vector3(-0.1, -1.3, -0.55), Vector2(0.5, 0.54), Vector2(0.46, 0.5), Palette.AMBER)
	steel.box(Transform3D(Basis(), Vector3(-0.1, -1.4, -0.6)), Vector3(0.6, 0.3, 0.4), Palette.INK)
	# Two flanges and a narrow web make the girder read as an I-beam, with orange paint marks.
	for y in [-1.32, -1.88]:
		steel.box(Transform3D(Basis(), Vector3(-0.1, y, -3.4)), Vector3(0.5, 0.1, 8.5), Palette.ASH)
	steel.box(Transform3D(Basis(), Vector3(-0.1, -1.6, -3.4)), Vector3(0.1, 0.5, 8.5), Palette.STONE)
	for z in [-6.8, -3.6, 0.2]:
		steel.box(Transform3D(Basis(), Vector3(-0.1, -1.31, z)), Vector3(0.52, 0.11, 0.4), Palette.CORAL)
	add_mesh(_beam, steel.mesh())
	pop_parts = [_arm, _beam]


## Picks the point on the tank-facing side of an ally: the broad hull blocks the firing lane.
func guard_spot(tank: Tank) -> Vector3:
	var ally: Entity
	var best := 60.0
	for enemy in World.current.enemies:
		if enemy == self or enemy is not Enemy or enemy.dead or enemy.flying:
			continue
		var distance := global_position.distance_to(enemy.global_position)
		if distance < best:
			ally = enemy
			best = distance
	var spot := tank.global_position + (global_position - tank.global_position).normalized() * 9.0
	if Course.stage.city:
		# On the flooded avenue the allies hold 80 m out: it bars the tank's own lane a stride ahead instead.
		var t := Course.to_course(tank.global_position)
		spot = Course.to_world(t.x + 12.0, t.y)
	elif ally != null:
		spot = ally.global_position + (tank.global_position - ally.global_position).normalized() * (ally.radius + radius + 3.0)
	spot.y = Course.height_at(spot)
	return spot


func behave(delta: float) -> void:
	var tank := player()
	if tank == null:
		return
	_follow = maxf(0.0, _follow - delta)
	if toppled:
		move_hunter(tank, delta, true)
		_cancel()
		return
	if is_staggered():
		_cancel()
		return
	var tank_d := Course.to_course(tank.global_position).x
	if Course.stage.city and is_finite(_tank_d):
		keep_pace(tank_d - _tank_d, delta) # The tank wades several times faster than it walks: it marches with it.
	_tank_d = tank_d
	if _wind <= 0.0 and _follow <= 0.0:
		var toward := tank.global_position - global_position
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-toward.x, -toward.z), minf(delta * 2.0, 1.0))
		var goal := guard_spot(tank)
		var far := Course.stage.city and global_position.distance_to(goal) > 20.0
		walk_to(goal, World.current.rail.speed + 18.0 if far else (5.0 if _hard else 3.5), delta)
	stride(delta)
	_arm.rotation.x = lerpf(_arm.rotation.x, -1.6 if _wind > 0.0 and _breaker else (0.5 if _follow > 0.0 and _breaker else 0.0), minf(delta * 8.0, 1.0))
	_beam.rotation.y = lerpf(_beam.rotation.y, -1.1 if _wind > 0.0 and not _breaker else (1.2 if _follow > 0.0 and not _breaker else 0.0), minf(delta * 8.0, 1.0))
	if _wind > 0.0:
		_wind -= delta
		if fmod(_wind, 0.16) < 0.05:
			flash()
		if _wind <= 0.0:
			_land_attack(tank)
			_follow = 0.4
		return
	_attack_timer -= delta
	if _attack_timer <= 0.0 and global_position.distance_to(tank.global_position) < (13.0 if _next_breaker and not disarmed else 16.0):
		_breaker = _next_breaker and not disarmed
		_wind = (0.9 if _breaker else 1.1) * Game.telegraph_scale()
		_attack_timer = 2.0 if _hard else 2.8
		_impact = tank.global_position
		_impact.y = Course.height_at(_impact)
		World.current.fx.marker(_impact if _breaker else global_position, SLAM_RADIUS if _breaker else BEAM_REACH, _wind, Palette.HOT)
		Sfx.play("warn", global_position, -2.0, 0.6)


func _land_attack(tank: Tank) -> void:
	var center := _impact if _breaker else global_position
	var reach := SLAM_RADIUS if _breaker else BEAM_REACH
	World.current.fx.shockwave(center, reach * 2.0, Palette.HOT)
	World.current.fx.dust(center, 12, 3.0, Palette.OCHRE)
	Sfx.play("impact", center, 2.0, 0.7)
	var offset := tank.global_position - center
	var direction := tank.global_position - global_position
	var in_arc := _breaker or (-model.global_basis.z).angle_to(direction) <= deg_to_rad(110.0)
	if Vector2(offset.x, offset.z).length() <= reach and absf(offset.y) < 3.0 and in_arc and not line_blocked(hit_center(), tank.hit_center()):
		var hit := Hit.make(Hit.Kind.RAM, 32.0 if _breaker else 24.0, tank.hit_center(), direction.normalized())
		hit.source = self
		tank.take_hit(hit)
		var lateral := direction.dot(Course.right(Course.to_course(tank.global_position).x))
		tank.local_velocity.x += (1.0 if lateral >= 0.0 else -1.0) * 14.0
		World.current.shake(0.4, center)
	# Keep the last weapon through its follow-through; switch when the next wind-up starts.
	_attack_timer += 0.4
	_next_breaker = not _breaker


func damage_multiplier(hit: Hit) -> float:
	return super(hit) * (3.0 if not disarmed and hit.position.distance_to(_hose.global_position) < 0.9 else 1.0)


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	var best := super(from, to, extra_radius)
	if hidden or disarmed:
		return best
	var t := Entity.segment_sphere(from, to, _hose.global_position, 0.6 + extra_radius)
	# A hose on the hull's skin takes a shot aimed at it, not the overlapping hull sphere.
	return t if t >= 0.0 and (best < 0.0 or t - best < 1.0) else best


func aim_parts() -> Dictionary:
	return {} if disarmed else {"hose": [_hose.global_position, 0.6, tr("ENEMY_ADAM")]}


func on_damaged(hit: Hit, amount: float) -> void:
	var hose_hit := not disarmed and hit.position.distance_to(_hose.global_position) < 0.9
	super(hit, amount)
	if hose_hit:
		hose_hp -= amount
		if hose_hp <= 0.0:
			disarmed = true
			_hose.hide()
			interrupt()
			World.current.fx.sparks(hit.position, Vector3.UP, 12, Palette.BUTTER)
			World.current.award(150, global_position, false)


func telegraphing() -> bool:
	return _wind > 0.0


func _cancel() -> void:
	_wind = 0.0


func interrupt() -> void:
	super()
	_cancel()
