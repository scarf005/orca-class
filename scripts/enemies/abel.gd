class_name Abel
extends BipedMech
## Canopy-cockpit police/labor mech: a spinning gatling and right-arm kinetic launcher.
## The laser gives a second to rush it; breaking the three tubes leaves only small arms.

var launcher_hp := 45.0
var disarmed := false
var _attack_timer := 1.5
var _wind := 0.0
var _wind_total := 1.0
var _alert := 0.0 ## Seconds the WARNING label stays up: the whole LOSAT wind-up and the flight after it.
var _losat := true
var _burst := 0
var _shot_timer := 0.0
var _aim := Vector3.ZERO
var _launcher := Node3D.new()
var _launch_muzzle := Node3D.new()
var _gun := Node3D.new()
var _barrels := Node3D.new()
var _muzzle := Node3D.new()


const LOSAT_ALERT_AFTER := 1.2
const LOSAT_MIN_FIRE := 45.0 ## Closer than this the dart has not gained its speed, so the gatling answers instead.


func _init() -> void:
	super()
	radius = 1.5
	center_height = 3.0
	min_range = 55.0
	max_hp = lerpf(Armament.QUICK_DAMAGE.x, Armament.QUICK_DAMAGE.y, Armament.STAGE_1) * Armament.SHELL_DAMAGE_SCALE * 1.5
	hp = max_hp
	score = 800


## About 5 m tall, a fifth shorter than the tank stood on its tail: a police labor in white and black with a blue
## band, round shoulders, a visor head under a light bar, the LOSAT pod on its right forearm and a gatling on its left.
func build() -> void:
	super()
	if Course.stage.city:
		_attack_timer = 0.1
	build_legs(2.15, "knee", Palette.WHITE, Palette.INK, 0.5)
	var b := LowPoly.new()
	# Pelvis, a black waist and white hip skirts that swing clear of the thighs.
	b.box(Transform3D(Basis(), Vector3(0, 0.1, 0)), Vector3(0.95, 0.42, 0.7), Palette.DUSK)
	b.frustum(Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, -0.25, -0.42)), Vector2(0.6, 0.12), Vector2(0.75, 0.14), 0.5, Palette.WHITE)
	for side in [-1.0, 1.0]:
		b.frustum(Transform3D(Basis(Vector3.BACK, side * 0.22), Vector3(side * 0.6, -0.3, 0)), Vector2(0.14, 0.62), Vector2(0.16, 0.7), 0.55, Palette.WHITE)
	b.prism(Transform3D(Basis(), Vector3(0, 0.3, 0)), 0.34, 0.4, 8, Palette.INK)
	# Chest: widening upward into the shoulders, a sloped white front, a black core with vents and the blue band.
	b.frustum(Transform3D(Basis(), Vector3(0, 0.62, 0.05)), Vector2(1.1, 0.8), Vector2(1.75, 1.05), 0.95, Palette.WHITE, Palette.MIST)
	b.frustum(Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 0.72, -0.42)), Vector2(1.0, 0.1), Vector2(1.45, 0.1), 0.8, Palette.WHITE)
	b.box(Transform3D(Basis(), Vector3(0, 1.0, -0.56)), Vector3(0.5, 0.42, 0.06), Palette.INK)
	for i in 3:
		b.box(Transform3D(Basis(), Vector3(0, 0.88 + i * 0.12, -0.6)), Vector3(0.4, 0.04, 0.03), Palette.SLATE)
	b.box(Transform3D(Basis(), Vector3(0, 0.74, -0.5)), Vector3(1.32, 0.13, 0.1), Palette.PERIWINKLE)
	b.box(Transform3D(Basis(), Vector3(0, 0.67, -0.5)), Vector3(1.25, 0.03, 0.11), Palette.INK)
	# Backpack: power pack with two short exhausts.
	b.frustum(Transform3D(Basis(), Vector3(0, 0.7, 0.62)), Vector2(1.0, 0.55), Vector2(0.9, 0.45), 0.85, Palette.DUSK, Palette.SLATE)
	for side in [-1.0, 1.0]:
		b.prism(Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(side * 0.28, 1.4, 0.75)), 0.09, 0.35, 6, Palette.INK)
	# Shoulders: big round pauldrons over black joints, a blue rim and an amber marker lamp.
	for side in [-1.0, 1.0]:
		b.blob(Transform3D(Basis(), Vector3(side * 1.0, 1.4, 0)), 0.26, Palette.INK)
		b.blob(Transform3D(Basis().scaled(Vector3(0.95, 0.78, 1.05)), Vector3(side * 1.1, 1.5, 0)), 0.47, Palette.WHITE, 1)
		b.box(Transform3D(Basis(Vector3.BACK, side * -0.35), Vector3(side * 1.22, 1.73, 0)), Vector3(0.3, 0.06, 0.8), Palette.PERIWINKLE)
		b.glow = true
		b.box(Transform3D(Basis(), Vector3(side * 1.55, 1.5, -0.1)), Vector3(0.05, 0.12, 0.22), Palette.AMBER)
		b.glow = false
	# Head: a narrow helmet with a brim, a black face, a wide cyan visor, a light bar and one antenna raked back.
	b.prism(Transform3D(Basis(), Vector3(0, 1.55, 0)), 0.16, 0.25, 6, Palette.INK)
	b.frustum(Transform3D(Basis(), Vector3(0, 1.72, 0.02)), Vector2(0.52, 0.56), Vector2(0.44, 0.48), 0.46, Palette.WHITE, Palette.WHITE, Vector2(0, 0.03))
	b.frustum(Transform3D(Basis(), Vector3(0, 1.7, -0.27)), Vector2(0.46, 0.12), Vector2(0.4, 0.08), 0.28, Palette.INK)
	b.frustum(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 2.07, -0.24)), Vector2(0.6, 0.24), Vector2(0.58, 0.06), 0.06, Palette.WHITE)
	b.box(Transform3D(Basis(), Vector3(0, 2.22, 0.04)), Vector3(0.5, 0.1, 0.16), Palette.INK)
	b.prism(Transform3D(Basis(Vector3.RIGHT, 0.45), Vector3(0.2, 2.1, 0.22)), 0.025, 0.9, 4, Palette.INK)
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(0, 1.88, -0.3)), Vector3(0.38, 0.08, 0.04), Palette.CYAN)
	b.box(Transform3D(Basis(), Vector3(-0.13, 2.29, 0.04)), Vector3(0.2, 0.08, 0.13), Palette.RED)
	b.box(Transform3D(Basis(), Vector3(0.13, 2.29, 0.04)), Vector3(0.2, 0.08, 0.13), Palette.RED)
	b.glow = false
	add_mesh(_body, b.mesh())
	# Right arm: upper arm hanging from the shoulder to a forearm that is the three-tube LOSAT pod.
	_launcher.position = Vector3(1.1, 1.3, 0)
	_body.add_child(_launcher)
	var p := LowPoly.new()
	limb(p, Vector3.ZERO, Vector3(0.05, -0.62, 0), Vector2(0.32, 0.36), Vector2(0.28, 0.32), Palette.DUSK)
	p.blob(Transform3D(Basis(), Vector3(0.05, -0.68, 0)), 0.2, Palette.INK)
	p.frustum(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.05, -0.78, 0.3)), Vector2(0.62, 0.62), Vector2(0.56, 0.54), 1.3, Palette.WHITE)
	p.box(Transform3D(Basis(), Vector3(0.05, -0.47, -0.3)), Vector3(0.5, 0.06, 1.1), Palette.PERIWINKLE)
	for i in 3:
		var angle := i * TAU / 3.0 + PI / 6.0
		var at := Vector3(0.05 + cos(angle) * 0.17, -0.78 + sin(angle) * 0.17, -1.0)
		p.tube(Transform3D(Basis(Vector3.UP, PI), at), 0.12, 0.6, 8, Palette.INK)
		p.tube(Transform3D(Basis(Vector3.UP, PI), at + Vector3(0, 0, -0.55)), 0.14, 0.08, 8, Palette.CORAL)
	p.glow = true
	p.box(Transform3D(Basis(), Vector3(0.05, -0.44, -0.86)), Vector3(0.14, 0.1, 0.06), Palette.RED) # Laser designator.
	p.glow = false
	add_mesh(_launcher, p.mesh())
	_launch_muzzle.position = Vector3(0.05, -0.78, -1.65)
	_launcher.add_child(_launch_muzzle)
	# Left arm: an armored forearm carrying a three-barrel gatling under it.
	_gun.position = Vector3(-1.1, 1.3, 0)
	_body.add_child(_gun)
	var arm := LowPoly.new()
	limb(arm, Vector3.ZERO, Vector3(-0.05, -0.62, 0), Vector2(0.32, 0.36), Vector2(0.28, 0.32), Palette.DUSK)
	arm.blob(Transform3D(Basis(), Vector3(-0.05, -0.68, 0)), 0.2, Palette.INK)
	arm.frustum(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(-0.05, -0.75, 0.25)), Vector2(0.46, 0.5), Vector2(0.4, 0.42), 0.9, Palette.WHITE)
	arm.box(Transform3D(Basis(), Vector3(-0.05, -0.98, -0.35)), Vector3(0.36, 0.3, 0.7), Palette.SLATE)
	add_mesh(_gun, arm.mesh())
	_barrels.position = Vector3(-0.05, -1.0, -0.6)
	_gun.add_child(_barrels)
	var g := LowPoly.new()
	g.tube(Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO), 0.17, 0.2, 8, Palette.INK)
	for i in 3:
		var angle := i * TAU / 3.0
		g.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(cos(angle) * 0.09, sin(angle) * 0.09, 0)), 0.045, 1.1, 6, Palette.INK)
	g.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -0.75)), 0.16, 0.08, 8, Palette.ASH)
	add_mesh(_barrels, g.mesh())
	_muzzle.position = Vector3(-0.05, -1.0, -1.75)
	_gun.add_child(_muzzle)
	pop_parts = [_launcher, _gun]


func behave(delta: float) -> void:
	var tank := player()
	if tank == null:
		return
	_alert = maxf(0.0, _alert - delta)
	move_hunter(tank, delta, _wind > 0.0 or _burst > 0)
	if toppled or is_staggered():
		_cancel()
		return
	var dart_aim := tank.hit_center() + tank.velocity * (0.45 if Course.stage.city else 0.0)
	aim_barrel(_launcher, dart_aim, 3.0, delta)
	aim_barrel(_gun, _aim if _burst > 0 else Gunnery.sensor_lead(tank, _muzzle.global_position, MG_SPEED), 3.0, delta)
	if _wind <= 0.0 and _burst == 0 and not disarmed:
		# Pick the weapon that has a line from this spot: the other arm may still be behind the corner.
		var gun_clear := not line_blocked(_muzzle.global_position, tank.hit_center())
		var launcher_clear := not line_blocked(_launch_muzzle.global_position, tank.hit_center())
		if _losat and not launcher_clear and gun_clear:
			_losat = false
		elif not _losat and not gun_clear and launcher_clear and global_position.distance_to(tank.global_position) >= LOSAT_MIN_FIRE:
			_losat = true
	if (Course.stage.city and not clear_firing_spot(tank)) or line_blocked(_muzzle.global_position if _burst > 0 or not _losat else _launch_muzzle.global_position, tank.hit_center()):
		_cancel()
		return
	if _burst > 0:
		_barrels.rotation.z += delta * 35.0
		_shot_timer -= delta
		if _shot_timer <= 0.0:
			var shot := fire_along("orb", _muzzle, MG_SPEED, 4.0, Palette.HOT, _aim - _muzzle.global_position, 3.0, 0.02, Muzzle.AUTO)
			shot.hit.caliber = 20
			Sfx.play("enemy_gun", _muzzle.global_position, -3.0, 1.2)
			_burst -= 1
			_shot_timer = 0.07
			if _burst == 0:
				volley_done()
		return
	if _wind > 0.0:
		_wind -= delta
		if _losat:
			_designate(tank)
		else:
			_barrels.rotation.z += delta * 25.0
			if fmod(_wind, 0.16) < 0.05:
				flash()
		if _wind <= 0.0:
			if _losat and not disarmed:
				_fire_losat(tank)
				volley_done()
			else:
				_aim = Gunnery.sensor_lead(tank, _muzzle.global_position, MG_SPEED)
				_burst = 12 if _hard else 8
				_shot_timer = 0.0
			_losat = not _losat and not disarmed
		return
	_attack_timer -= delta
	if _attack_timer <= 0.0 and in_reach(tank, 150.0):
		_losat = _losat and not disarmed and global_position.distance_to(tank.global_position) >= LOSAT_MIN_FIRE
		_wind = (1.0 if _losat else 0.65) * Game.telegraph_scale()
		_wind_total = _wind
		_alert = _wind + LOSAT_ALERT_AFTER if _losat else 0.0
		_attack_timer = 2.0 if _hard else 2.6
		Sfx.play("warn", global_position, -4.0)


func _fire_losat(tank: Tank) -> void:
	var missile := LosatMissile.new()
	missile.position = _launch_muzzle.global_position
	missile.velocity = bore_direction(_launch_muzzle, tank.hit_center() + tank.velocity * (0.45 if Course.stage.city else 0.0) - missile.position) * LosatMissile.LAUNCH_SPEED
	missile.hit.source = self
	World.current.add_child(missile)
	muzzle_blast(missile.position, missile.velocity.normalized(), Muzzle.HEAVY, "rocket")
	_launch_blaze(missile.position, missile.velocity.normalized())
	_alert = LOSAT_ALERT_AFTER
	Sfx.play("launch", missile.position, 6.0, 1.15)
	Sfx.play("warn", global_position, 2.0, 1.8)


## The aim: a fat flickering red beam with a white core to the tank, a glow that swells in the tube and a star that
## blinks on the hull, so the target knows exactly who is being lased.
func _designate(tank: Tank) -> void:
	var fx := World.current.fx
	var from := _launch_muzzle.global_position
	var charge := 1.0 - clampf(_wind / maxf(_wind_total, 0.01), 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_wind * 50.0)
	fx.beam(from, tank.hit_center(), Palette.RED, 0.5 + 0.7 * pulse * charge + 0.3 * charge, 0.05)
	fx.beam(from, tank.hit_center(), Palette.WHITE, 0.18 + 0.1 * charge, 0.05)
	fx.light_flash(from, 10.0 + 30.0 * charge, Palette.RED, 20.0 + 20.0 * charge)
	fx.muzzle_flash(from, (tank.hit_center() - from).normalized(), 3.0 + 8.0 * charge * pulse, Palette.CORAL)
	if fmod(_wind, 0.16) < 0.05:
		fx.impact_star(tank.hit_center(), 5.0 + 5.0 * charge, Palette.RED)
		fx.shockwave(tank.global_position, 9.0, Palette.RED, 0.16)
		Sfx.play("warn", global_position, 0.0, 1.5 + charge * 0.6)


## The launch: a white-hot fireball and a long flame jet out of the tube, a backblast of fire and smoke behind it.
func _launch_blaze(at: Vector3, dir: Vector3) -> void:
	var fx := World.current.fx
	fx.muzzle_flash(at + dir * 2.0, dir, 22.0, Palette.WHITE)
	fx.muzzle_flash(at + dir * 1.5, dir, 15.0, Palette.AMBER)
	fx.muzzle_flash(at - dir * 2.0, -dir, 16.0, Palette.AMBER)
	for i in 40:
		var jet := (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.22).normalized()
		fx.spawn(Fx.Kind.FLAME, at + dir * 0.8, jet * randf_range(26.0, 60.0), 0.7, 5.0, [Palette.BUTTER, Palette.AMBER, Palette.CORAL][i % 3], {"drag": 3.0})
	for i in 24:
		var back := (-dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.4).normalized()
		fx.spawn(Fx.Kind.FLAME, at - dir * 0.8, back * randf_range(12.0, 34.0), 0.6, 4.0, [Palette.AMBER, Palette.CORAL][i % 2], {"drag": 3.0})
	fx.smoke(at - dir * 2.0, 24, 5.0, [Palette.ASH, Palette.STONE, Palette.MIST])
	fx.light_flash(at, 90.0, Palette.AMBER, 60.0)
	fx.shockwave(at, 18.0, Palette.WHITE, 0.45)


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	var best := super(from, to, extra_radius)
	if hidden or disarmed:
		return best
	var t := Entity.segment_sphere(from, to, _launcher.global_position + _launcher.global_basis * Vector3(0, -0.78, -0.4), 0.6 + extra_radius)
	return t if t >= 0.0 and (best < 0.0 or t < best) else best


func aim_parts() -> Dictionary:
	return {} if disarmed else {"launcher": [_launcher.global_position + _launcher.global_basis * Vector3(0, -0.78, -0.4), 0.6, tr("ENEMY_ABEL")]}


func on_damaged(hit: Hit, amount: float) -> void:
	var tube_hit := not disarmed and hit.position.distance_to(_launcher.global_position + _launcher.global_basis * Vector3(0, -0.78, -0.4)) < 0.9
	super(hit, amount)
	if tube_hit:
		launcher_hp -= amount
		if launcher_hp <= 0.0:
			disarmed = true
			_launcher.hide()
			_cancel()
			World.current.fx.explosion(hit.position, 1.2)
			World.current.award(150, global_position, false)


func on_exposed() -> void:
	if is_finite(_attack_timer):
		_attack_timer = minf(_attack_timer, 0.5)


func telegraphing() -> bool:
	return _wind > 0.0


func alert_text() -> String:
	return tr("WARN_LOSAT") if _alert > 0.0 and not dead else ""


func _cancel() -> void:
	if _wind > 0.0:
		_alert = 0.0 # A broken aim withdraws the warning; a dart already in flight keeps it.
	_wind = 0.0
	_burst = 0


func interrupt() -> void:
	super()
	_cancel()
