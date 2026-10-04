class_name Abel
extends BipedMech
## Canopy-cockpit police/labor mech: a spinning gatling and right-arm kinetic launcher.
## The laser gives a second to rush it; breaking the three tubes leaves only small arms.

var launcher_hp := 45.0
var disarmed := false
var _attack_timer := 1.5
var _wind := 0.0
var _losat := true
var _burst := 0
var _shot_timer := 0.0
var _aim := Vector3.ZERO
var _launcher := Node3D.new()
var _launch_muzzle := Node3D.new()
var _gun := Node3D.new()
var _barrels := Node3D.new()
var _muzzle := Node3D.new()


func _init() -> void:
	super()
	max_hp = 2600.0
	hp = max_hp
	score = 800


func build() -> void:
	super()
	build_legs(true, Palette.MIST)
	var b := LowPoly.new()
	b.blob(Transform3D(Basis().scaled(Vector3(1.4, 0.8, 0.9)), Vector3(0, 0.4, 0)), 1.0, Palette.SLATE)
	b.box(Transform3D(Basis(), Vector3(0, -0.1, 0)), Vector3(1.8, 0.7, 1.3), Palette.DUSK)
	b.blob(Transform3D(Basis().scaled(Vector3(0.95, 0.75, 1.05)), Vector3(0, 1.4, -0.1)), 0.9, Palette.MIST)
	b.box(Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, 1.4, -0.85)), Vector3(1.15, 0.7, 0.12), Palette.INK)
	b.box(Transform3D(Basis(), Vector3(0, 1.35, -0.94)), Vector3(0.07, 0.7, 0.05), Palette.ASH)
	b.prism(Transform3D(Basis(), Vector3(0.55, 2.1, 0)), 0.055, 0.8, 6, Palette.INK)
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(0.55, 2.55, -0.03)), Vector3(0.22, 0.15, 0.2), Palette.HOT)
	add_mesh(_body, b.mesh())
	_launcher.position = Vector3(1.65, 0.4, -0.1)
	_body.add_child(_launcher)
	var p := LowPoly.new()
	p.blob(Transform3D(Basis(), Vector3(-0.3, 0.3, 0.3)), 0.45, Palette.MIST)
	p.box(Transform3D(), Vector3(0.8, 0.85, 1.6), Palette.DUSK)
	for i in 3:
		var angle := i * TAU / 3.0
		p.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(cos(angle) * 0.25, sin(angle) * 0.25, -0.45)), 0.17, 1.1, 8, Palette.INK)
		p.glow = true
		p.box(Transform3D(Basis(), Vector3(cos(angle) * 0.25, sin(angle) * 0.25, -1.56)), Vector3(0.14, 0.14, 0.02), Palette.CORAL)
		p.glow = false
	add_mesh(_launcher, p.mesh())
	_launch_muzzle.position.z = -1.6
	_launcher.add_child(_launch_muzzle)
	_gun.position = Vector3(-1.45, 0.1, -0.1)
	_body.add_child(_gun)
	_gun.add_child(_barrels)
	var g := LowPoly.new()
	g.blob(Transform3D(), 0.45, Palette.SLATE)
	for i in 3:
		var angle := i * TAU / 3.0
		g.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(cos(angle) * 0.16, sin(angle) * 0.16, -0.2)), 0.07, 1.5, 6, Palette.INK)
	add_mesh(_barrels, g.mesh())
	_muzzle.position.z = -1.8
	_gun.add_child(_muzzle)
	pop_parts = [_launcher, _gun]


func behave(delta: float) -> void:
	var tank := player()
	if tank == null:
		return
	move_hunter(tank, delta, _wind > 0.0 or _burst > 0)
	if toppled or is_staggered():
		_cancel()
		return
	aim_barrel(_launcher, tank.hit_center(), 3.0, delta)
	aim_barrel(_gun, _aim if _burst > 0 else Gunnery.sensor_lead(tank, _muzzle.global_position, MG_SPEED), 3.0, delta)
	if line_blocked(_muzzle.global_position if _burst > 0 or not _losat else _launch_muzzle.global_position, tank.hit_center()):
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
				relocate()
		return
	if _wind > 0.0:
		_wind -= delta
		if _losat:
			World.current.fx.beam(_launch_muzzle.global_position, tank.hit_center(), Palette.CORAL, 0.035, 0.05)
		else:
			_barrels.rotation.z += delta * 25.0
			if fmod(_wind, 0.16) < 0.05:
				flash()
		if _wind <= 0.0:
			if _losat and not disarmed:
				_fire_losat(tank)
				relocate()
			else:
				_aim = Gunnery.sensor_lead(tank, _muzzle.global_position, MG_SPEED)
				_burst = 12 if _hard else 8
				_shot_timer = 0.0
			_losat = not _losat and not disarmed
		return
	_attack_timer -= delta
	if _attack_timer <= 0.0 and global_position.distance_to(tank.global_position) < 150.0:
		_losat = _losat and not disarmed
		_wind = (1.0 if _losat else 0.65) * Game.telegraph_scale()
		_attack_timer = 2.4 if _hard else 3.2
		Sfx.play("warn", global_position, -4.0)


func _fire_losat(tank: Tank) -> void:
	var missile := LosatMissile.new()
	missile.position = _launch_muzzle.global_position
	missile.velocity = bore_direction(_launch_muzzle, tank.hit_center() - missile.position) * LosatMissile.LAUNCH_SPEED
	missile.hit.source = self
	World.current.add_child(missile)
	muzzle_blast(missile.position, missile.velocity.normalized(), Muzzle.HEAVY, "rocket")
	Sfx.play("launch", missile.position, 1.0, 1.3)


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	var best := super(from, to, extra_radius)
	if hidden or disarmed:
		return best
	var t := Entity.segment_sphere(from, to, _launcher.global_position, 0.8 + extra_radius)
	return t if t >= 0.0 and (best < 0.0 or t < best) else best


func aim_parts() -> Dictionary:
	return {} if disarmed else {"launcher": [_launcher.global_position, 0.8, tr("ENEMY_ABEL")]}


func on_damaged(hit: Hit, amount: float) -> void:
	var tube_hit := not disarmed and hit.position.distance_to(_launcher.global_position) < 1.2
	super(hit, amount)
	if tube_hit:
		launcher_hp -= amount
		if launcher_hp <= 0.0:
			disarmed = true
			_launcher.hide()
			_cancel()
			World.current.fx.explosion(hit.position, 1.2)
			World.current.award(150, global_position, false)


func telegraphing() -> bool:
	return _wind > 0.0


func _cancel() -> void:
	_wind = 0.0
	_burst = 0


func interrupt() -> void:
	super()
	_cancel()
