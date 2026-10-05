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
	radius = 1.8
	center_height = 2.9
	max_hp = lerpf(Armament.QUICK_DAMAGE.x, Armament.QUICK_DAMAGE.y, Armament.STAGE_1) * Armament.SHELL_DAMAGE_SCALE * 0.65 * 1.5
	hp = max_hp
	score = 900


## About 4.6 m tall on reverse-jointed legs: a short slice of tank hull carrying a real tank turret, in desert sand
## with brown blotches so it never reads as the player's grey-green hull.
func build() -> void:
	super()
	if Course.stage is Stage2:
		_attack_timer = 0.1
	build_legs(2.35, "bird", Palette.STRAW, Palette.DUSK, 0.95)
	var b := LowPoly.new()
	# Hull slice: sides that slope in toward the belly, a raked glacis, a rear engine deck and the hip housings.
	b.frustum(Transform3D(Basis(), Vector3(0, -0.45, 0.05)), Vector2(1.5, 2.0), Vector2(2.2, 2.6), 0.55, Palette.OCHRE)
	b.box(Transform3D(Basis(), Vector3(0, 0.3, 0.05)), Vector3(2.2, 0.4, 2.6), Palette.STRAW, Palette.STRAW)
	b.frustum(Transform3D(Basis(Vector3.RIGHT, -1.05), Vector3(0, -0.1, -1.25)), Vector2(2.2, 0.5), Vector2(2.0, 0.5), 0.7, Palette.STRAW)
	b.box(Transform3D(Basis(), Vector3(0, 0.55, 1.05)), Vector3(1.9, 0.12, 0.6), Palette.OCHRE)
	for i in 4:
		b.box(Transform3D(Basis(), Vector3(-0.6 + i * 0.4, 0.62, 1.05)), Vector3(0.08, 0.04, 0.5), Palette.INK)
	for side in [-1.0, 1.0]:
		b.prism(Transform3D(Basis(Vector3.BACK, side * PI * 0.5), Vector3(side * 0.7, 0.0, 0.0)), 0.45, 0.4, 8, Palette.DUSK)
		for i in 3:
			b.box(Transform3D(Basis(Vector3.BACK, side * 0.35), Vector3(side * 1.12, -0.12, -0.75 + i * 0.75)), Vector3(0.1, 0.5, 0.65), Palette.OCHRE)
	b.box(Transform3D(Basis(), Vector3(0.6, 0.48, -0.6)), Vector3(0.55, 0.05, 0.45), Palette.WOOD)
	b.box(Transform3D(Basis(), Vector3(-0.5, 0.48, 0.6)), Vector3(0.6, 0.05, 0.4), Palette.WOOD)
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(0, 0.05, -1.5)), Vector3(0.7, 0.1, 0.05), Palette.HOT)
	b.glow = false
	add_mesh(_body, b.mesh())
	_turret.position = Vector3(0, 0.5, 0.15)
	_body.add_child(_turret)
	var t := LowPoly.new()
	# Turret: a low faceted cast shape, wide at the ring and sloped hard at the front, with a rear bustle, a
	# commander's cupola, smoke dischargers, stowage and a whip antenna.
	t.frustum(Transform3D(), Vector2(2.0, 2.3), Vector2(1.5, 1.6), 0.62, Palette.STRAW, Palette.STRAW, Vector2(0, 0.2))
	t.frustum(Transform3D(Basis(), Vector3(0, 0.05, 1.3)), Vector2(1.5, 0.7), Vector2(1.3, 0.6), 0.5, Palette.OCHRE)
	t.box(Transform3D(Basis(), Vector3(0, 0.3, -1.2)), Vector3(0.75, 0.5, 0.35), Palette.OCHRE)
	t.box(Transform3D(Basis(), Vector3(0.3, 0.63, 0.2)), Vector3(0.6, 0.04, 0.5), Palette.WOOD)
	t.prism(Transform3D(Basis(), Vector3(-0.45, 0.6, 0.35)), 0.3, 0.28, 8, Palette.OCHRE, 0.26)
	t.box(Transform3D(Basis(), Vector3(-0.45, 0.9, 0.35)), Vector3(0.38, 0.06, 0.38), Palette.INK)
	t.glow = true
	t.box(Transform3D(Basis(), Vector3(0.45, 0.72, -0.3)), Vector3(0.3, 0.12, 0.08), Palette.CYAN)
	t.glow = false
	t.box(Transform3D(Basis(), Vector3(0.45, 0.66, -0.25)), Vector3(0.36, 0.14, 0.2), Palette.INK)
	for x in [-1.0, 1.0]:
		for i in 3:
			t.tube(Transform3D(Basis(Vector3.UP, x * 0.5) * Basis(Vector3.RIGHT, -0.5), Vector3(x * 0.9, 0.35, -0.4 + i * 0.16)), 0.06, 0.32, 6, Palette.INK)
	t.box(Transform3D(Basis(), Vector3(0, 0.4, 1.68)), Vector3(1.4, 0.4, 0.08), Palette.DUSK)
	t.prism(Transform3D(Basis(Vector3.BACK, 0.15), Vector3(0.55, 0.55, 1.4)), 0.02, 1.4, 4, Palette.INK)
	add_mesh(_turret, t.mesh())
	_gun.position = Vector3(0, 0.3, -1.35)
	_turret.add_child(_gun)
	var g := LowPoly.new()
	# Low-pressure 100 mm: a long tube with a fume extractor bulge and a slotted muzzle brake; the coax rides beside.
	g.tube(Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO), 0.13, 3.1, 8, Palette.OCHRE)
	g.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -1.3)), 0.2, 0.45, 8, Palette.STRAW)
	g.box(Transform3D(Basis(), Vector3(0, 0, -3.2)), Vector3(0.32, 0.22, 0.34), Palette.DUSK)
	g.box(Transform3D(Basis(), Vector3(0, 0, -3.2)), Vector3(0.36, 0.06, 0.1), Palette.INK)
	g.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(0.3, -0.05, 0.1)), 0.05, 0.8, 6, Palette.INK)
	add_mesh(_gun, g.mesh())
	_muzzle.position.z = -3.45
	_gun.add_child(_muzzle)
	_coax.position = Vector3(0.3, -0.05, -0.75)
	_gun.add_child(_coax)
	pop_parts = [_turret]


func _lob() -> Vector3:
	return (_aim - _muzzle.global_position) / _flight + Vector3.UP * GRAVITY * _flight * 0.5


func behave(delta: float) -> void:
	var tank := player()
	if tank == null:
		return
	move_hunter(tank, delta, _wind > 0.0 or _burst > 0, 58.0)
	if toppled or is_staggered():
		_cancel()
		return
	var local := _body.to_local(_aim if _wind > 0.0 else tank.hit_center()) - _turret.position
	_turret.rotation.y = lerp_angle(_turret.rotation.y, atan2(-local.x, -local.z), minf(delta * 3.0, 1.0))
	if _wind > 0.0 and _shell:
		slew_barrel(_gun, _lob(), 3.0, delta)
	else:
		aim_barrel(_gun, Gunnery.sensor_lead(tank, _coax.global_position, MG_SPEED), 3.0, delta)
	if (Course.stage is Stage2 and not clear_firing_spot(tank)) or line_blocked(hit_center(), tank.hit_center()):
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
				volley_done()
		return
	if _wind > 0.0:
		_wind -= delta
		if fmod(_wind, 0.16) < 0.05:
			flash()
		if _wind <= 0.0:
			if _shell:
				_fire_shell()
				volley_done()
			else:
				_burst = 10 if _hard else 6
				_shot_timer = 0.0
			_shell = not _shell
		return
	_attack_timer -= delta
	if _attack_timer <= 0.0 and global_position.distance_to(tank.global_position) < 140.0:
		_wind = (0.65 if Course.stage is Stage2 else 1.0) * Game.telegraph_scale()
		_attack_timer = 2.2 if _hard else 3.0
		_flight = clampf(global_position.distance_to(tank.global_position) / 45.0, 1.2, 2.4)
		_aim = tank.global_position + tank.velocity * (_wind + _flight if Course.stage is Stage2 else 0.8)
		_aim.y = Course.height_at(_aim)
		if not Course.stage is Stage2:
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
	var damage := (130.0 if _hard else 110.0) if Course.stage is Stage2 else (32.0 if _hard else 26.0)
	shell.hit = Hit.make(Hit.Kind.SHELL, damage, _muzzle.global_position)
	shell.hit.source = self
	shell.hit.caliber = 100
	shell.blast_radius = BLAST
	shell.blast_damage = damage
	shell.interceptable = true
	shell.intercept_hp = 3.0 if Course.stage is Stage2 else 1.0
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
	return {"turret": [_turret.global_position + Vector3.UP * 0.3, 1.2, tr("ENEMY_KAIN")]}


func on_exposed() -> void:
	if is_finite(_attack_timer):
		_attack_timer = minf(_attack_timer, 0.6)


func telegraphing() -> bool:
	return _wind > 0.0


func _cancel() -> void:
	_wind = 0.0
	_burst = 0


func interrupt() -> void:
	super()
	_cancel()
