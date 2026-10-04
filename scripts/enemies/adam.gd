class_name Adam
extends BipedMech
## Construction biped that stands between the tank and its allies. The breaker marks one patch;
## the carried I-beam sweeps a wider arc. Exposed hydraulic hoses stop the breaker, legs stop both.

const SLAM_RADIUS := 5.0
const BEAM_REACH := 9.0

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
	max_hp = 3000.0
	hp = max_hp
	radius = 2.5
	armor = 18.0
	score = 1000


func build() -> void:
	super()
	build_legs(false, Palette.OCHRE)
	var b := LowPoly.new()
	b.box(Transform3D(), Vector3(2.3, 1.0, 1.8), Palette.OCHRE, Palette.BUTTER)
	b.box(Transform3D(Basis(), Vector3(0, 0.9, 0)), Vector3(1.4, 1.2, 1.3), Palette.STONE)
	b.box(Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0, 1.05, -0.72)), Vector3(1.15, 0.65, 0.1), Palette.INK)
	for x in [-0.85, 0.85]:
		b.box(Transform3D(Basis(), Vector3(x, 0.4, 1.0)), Vector3(0.5, 0.9, 0.6), Palette.DUSK)
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(0, 1.65, -0.2)), Vector3(0.25, 0.15, 0.25), Palette.CORAL)
	add_mesh(_body, b.mesh())
	_arm.position = Vector3(1.7, 0.6, -0.1)
	_body.add_child(_arm)
	var a := LowPoly.new()
	a.blob(Transform3D(), 0.45, Palette.INK)
	a.box(Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0, -0.9, -0.2)), Vector3(0.6, 2.0, 0.65), Palette.OCHRE)
	a.prism(Transform3D(Basis(), Vector3(0.35, -0.5, -0.4)), 0.12, 1.6, 6, Palette.ASH)
	a.box(Transform3D(Basis(), Vector3(0, -2.0, -0.5)), Vector3(0.65, 0.8, 0.65), Palette.DUSK)
	a.prism(Transform3D(Basis(), Vector3(0, -2.6, -0.5)), 0.13, 1.0, 6, Palette.INK, 0.02)
	add_mesh(_arm, a.mesh())
	_hose.position = Vector3(0.4, -0.6, 0)
	_arm.add_child(_hose)
	var h := LowPoly.new()
	for x in [-0.12, 0.0, 0.12]:
		h.prism(Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(x, 0, 0)), 0.055, 1.1, 6, Palette.CORAL)
	add_mesh(_hose, h.mesh())
	_beam.position = Vector3(-1.65, 0.3, -0.2)
	_body.add_child(_beam)
	var steel := LowPoly.new()
	steel.box(Transform3D(Basis(), Vector3(0, -0.5, 0)), Vector3(0.5, 1.2, 0.5), Palette.OCHRE)
	# Two flanges and the narrow web make the carried scrap read as an I-beam.
	for y in [-0.95, -1.65]:
		steel.box(Transform3D(Basis(), Vector3(0, y, -2.0)), Vector3(0.65, 0.12, 7.0), Palette.SLATE)
	steel.box(Transform3D(Basis(), Vector3(0, -1.3, -2.0)), Vector3(0.15, 0.7, 7.0), Palette.DUSK)
	add_mesh(_beam, steel.mesh())
	pop_parts = [_arm, _beam]


## Picks the point on the tank-facing side of an ally: the broad hull blocks the firing lane.
func guard_spot(tank: Tank) -> Vector3:
	var ally: Enemy
	var best := 60.0
	for enemy: Enemy in World.current.enemies:
		if enemy == self or enemy.dead or enemy.flying:
			continue
		var distance := global_position.distance_to(enemy.global_position)
		if distance < best:
			ally = enemy
			best = distance
	var spot := tank.global_position + (global_position - tank.global_position).normalized() * 10.0
	if ally != null:
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
	if _wind <= 0.0 and _follow <= 0.0:
		var toward := tank.global_position - global_position
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-toward.x, -toward.z), minf(delta * 2.0, 1.0))
		walk_to(guard_spot(tank), 5.0 if _hard else 3.5, delta)
	for i in _legs.size():
		_legs[i].rotation.x = sin(_walk + i * PI) * 0.15
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
	if _attack_timer <= 0.0 and global_position.distance_to(tank.global_position) < (8.0 if _next_breaker and not disarmed else 12.0):
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
	return super(hit) * (3.0 if not disarmed and hit.position.distance_to(_hose.global_position) < 0.7 else 1.0)


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	var best := super(from, to, extra_radius)
	if hidden or disarmed:
		return best
	var t := Entity.segment_sphere(from, to, _hose.global_position, 0.5 + extra_radius)
	# A hose on the hull's skin takes a shot aimed at it, not the overlapping hull sphere.
	return t if t >= 0.0 and (best < 0.0 or t - best < 1.0) else best


func aim_parts() -> Dictionary:
	return {} if disarmed else {"hose": [_hose.global_position, 0.5, tr("ENEMY_ADAM")]}


func on_damaged(hit: Hit, amount: float) -> void:
	var hose_hit := not disarmed and hit.position.distance_to(_hose.global_position) < 0.7
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
