class_name Kain
extends BipedMech
## Reverse-jointed gun carrier. Its back turret lobs a slow 100 mm shell at a marked patch;
## the front plate guards the turret, but the rear and legs are exposed.

const GRAVITY := 20.0
const BLAST := 5.0

var _attack_timer := 1.8
var _wind := 0.0
var _shell := true
var _aim := Vector3.ZERO
var _flight := 1.5
var _burst := 0
var _shot_timer := 0.0
var _turret := Node3D.new()
var _gun := Node3D.new()
var _muzzle := Node3D.new()
var _coax := Node3D.new()


func _init() -> void:
	super()
	max_hp = 2000.0
	hp = max_hp
	score = 900


func build() -> void:
	super()
	build_legs()
	var b := LowPoly.new()
	b.box(Transform3D(), Vector3(1.8, 0.8, 2.0), Palette.SLATE, Palette.ASH)
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, 0.4, -1.1)), Vector3(1.4, 0.7, 0.7), Palette.DUSK)
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(0, 0.5, -1.5)), Vector3(0.55, 0.1, 0.05), Palette.HOT)
	add_mesh(_body, b.mesh())
	_turret.position = Vector3(0, 0.8, 0.55)
	_body.add_child(_turret)
	var t := LowPoly.new()
	t.prism(Transform3D(), 1.3, 0.7, 6, Palette.MOSS, 1.1, Palette.SLATE)
	t.box(Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, 0.45, -0.9)), Vector3(2.1, 0.7, 0.5), Palette.DUSK)
	for x in [-0.7, 0.7]:
		t.box(Transform3D(Basis(), Vector3(x, 0.45, 1.1)), Vector3(0.45, 0.4, 0.5), Palette.CORAL)
	add_mesh(_turret, t.mesh())
	_gun.position = Vector3(0, 0.55, -0.85)
	_turret.add_child(_gun)
	var g := LowPoly.new()
	g.blob(Transform3D(), 0.4, Palette.SLATE)
	g.tube(Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO), 0.18, 2.5, 8, Palette.INK)
	g.box(Transform3D(Basis(), Vector3(0, 0, -2.3)), Vector3(0.6, 0.4, 0.4), Palette.DUSK)
	g.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(0.55, 0, 0)), 0.07, 1.4, 6, Palette.INK)
	add_mesh(_gun, g.mesh())
	_muzzle.position.z = -2.6
	_gun.add_child(_muzzle)
	_coax.position = Vector3(0.55, 0, -1.5)
	_gun.add_child(_coax)
	pop_parts = [_turret]


func _lob() -> Vector3:
	return (_aim - _muzzle.global_position) / _flight + Vector3.UP * GRAVITY * _flight * 0.5


func behave(delta: float) -> void:
	var tank := player()
	if tank == null:
		return
	move_hunter(tank, delta, _wind > 0.0 or _burst > 0, 80.0)
	if toppled or is_staggered():
		_cancel()
		return
	var local := _body.to_local(_aim if _wind > 0.0 else tank.hit_center()) - _turret.position
	_turret.rotation.y = lerp_angle(_turret.rotation.y, atan2(-local.x, -local.z), minf(delta * 3.0, 1.0))
	if _wind > 0.0 and _shell:
		slew_barrel(_gun, _lob(), 3.0, delta)
	else:
		aim_barrel(_gun, Gunnery.sensor_lead(tank, _coax.global_position, MG_SPEED), 3.0, delta)
	if line_blocked(hit_center(), tank.hit_center()):
		_cancel()
		return
	if _burst > 0:
		_shot_timer -= delta
		if _shot_timer <= 0.0:
			var shot := fire_along("orb", _coax, MG_SPEED, 4.0, Palette.HOT, Gunnery.sensor_lead(tank, _coax.global_position, MG_SPEED) - _coax.global_position, 3.0, 0.02, Muzzle.AUTO)
			shot.hit.caliber = 20
			Sfx.play("enemy_gun", _coax.global_position, -4.0)
			_burst -= 1
			_shot_timer = 0.1
			if _burst == 0:
				relocate()
		return
	if _wind > 0.0:
		_wind -= delta
		if fmod(_wind, 0.16) < 0.05:
			flash()
		if _wind <= 0.0:
			if _shell:
				_fire_shell()
				relocate()
			else:
				_burst = 10 if _hard else 6
				_shot_timer = 0.0
			_shell = not _shell
		return
	_attack_timer -= delta
	if _attack_timer <= 0.0 and global_position.distance_to(tank.global_position) < 140.0:
		_wind = 1.0 * Game.telegraph_scale()
		_attack_timer = 2.6 if _hard else 3.6
		_aim = tank.global_position + tank.velocity * 0.8
		_aim.y = Course.height_at(_aim)
		_flight = clampf(global_position.distance_to(_aim) / 45.0, 1.2, 2.4)
		if _shell:
			World.current.fx.marker(_aim, BLAST, _wind + _flight, Palette.HOT)
		Sfx.play("warn", global_position, -3.0, 0.7)


func _fire_shell() -> void:
	var velocity_out := _lob()
	# An interrupted swivel must never fire sideways through its own telegraph.
	if (-_muzzle.global_basis.z).angle_to(velocity_out) > deg_to_rad(5.0):
		return
	muzzle_blast(_muzzle.global_position, velocity_out.normalized(), Muzzle.HEAVY, "mortar")
	var shell := World.current.spawn_projectile(Team.ENEMY, _muzzle.global_position, velocity_out, "mortar", Palette.HOT)
	shell.gravity = GRAVITY
	shell.hit = Hit.make(Hit.Kind.SHELL, 32.0 if _hard else 26.0, _muzzle.global_position)
	shell.hit.source = self
	shell.hit.caliber = 100
	shell.blast_radius = BLAST
	shell.blast_damage = 32.0 if _hard else 26.0
	shell.interceptable = true
	shell.intercept_hp = 1.0
	shell.life = _flight + 1.0
	shell.trail = Palette.DUSK
	Sfx.play("launch", _muzzle.global_position, 2.0, 0.6)


func damage_multiplier(hit: Hit) -> float:
	if model.to_local(hit.position).y < 1.8:
		return super(hit)
	var facing := -_turret.global_basis.z
	var incoming := -hit.direction
	facing.y = 0.0
	incoming.y = 0.0
	var front := incoming.length_squared() > 0.0001 and facing.angle_to(incoming) < deg_to_rad(60.0)
	return super(hit) * (0.65 if front else 1.4)


func aim_parts() -> Dictionary:
	return {"turret": [_turret.global_position + Vector3.UP * 0.3, 1.3, tr("ENEMY_KAIN")]}


func telegraphing() -> bool:
	return _wind > 0.0


func _cancel() -> void:
	_wind = 0.0
	_burst = 0


func interrupt() -> void:
	super()
	_cancel()
