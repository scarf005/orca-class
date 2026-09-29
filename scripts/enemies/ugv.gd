class_name Ugv
extends Enemy
## Tracked unmanned ground vehicle. Keeps ahead of the tank, hopping between lanes.
## `weapon`: "gun" fires telegraphed 30 mm bursts, "atgm" paints the tank with a laser before
## launching a guided missile, "supply" carries a pickup and tries to get away.

const KEEP_AHEAD := 48.0
const PACE_TIME := 13.0 ## After this long it stops pacing the rail and falls behind.

var weapon := "gun"
var _lane := 0.0
var _lane_timer := 0.0
var _attack_timer := 2.0
var _telegraph := 0.0
var _burst := 0
var _burst_timer := 0.0
var _turret: Node3D
var _muzzle: Node3D
var _eye: MeshInstance3D
var _eye_material := StandardMaterial3D.new()
var _hard := false
## Modules: a tracked hit immobilizes it, a turret hit disarms it; the hull still has to die.
var tracks_hp := 6.0
var weapon_hp := 5.0
var immobile := false
var disarmed := false


func _init() -> void:
	super()
	wreck_on_death = true
	max_hp = 16.0
	hp = 16.0
	radius = 1.8
	center_height = 1.0
	armor = 0.0
	stabbable = true
	score = 400
	debris = [Fx.Debris.ARMOR, Fx.Debris.METAL]
	weakness = {Hit.Kind.THROWN: 1.5, Hit.Kind.TAIL: 1.5}


func build() -> void:
	_hard = Game.difficulty == Game.Difficulty.HARD
	if weapon == "atgm":
		max_hp = 16.0
	elif weapon == "supply":
		max_hp = 12.0
		score = 300
	hp = max_hp
	var b := LowPoly.new()
	for side in [-1.0, 1.0]:
		b.box(Transform3D(Basis(), Vector3(0.95 * side, 0.45, 0)), Vector3(0.5, 0.8, 3.4), Palette.INK)
		for z in [-1.1, 0.0, 1.1]:
			b.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(1.22 * side, 0.4, z)), 0.32, 0.06, 6, Palette.STONE)
	b.box(Transform3D(Basis(), Vector3(0, 0.95, 0)), Vector3(1.7, 0.7, 3.2), Palette.SLATE)
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 1.05, -1.7)), Vector3(1.6, 0.5, 0.6), Palette.SLATE)
	b.box(Transform3D(Basis(), Vector3(0, 1.32, 0.9)), Vector3(1.2, 0.1, 1.0), Palette.DUSK)
	# Sensor mast and a stripe of warning paint.
	b.box(Transform3D(Basis(), Vector3(0.55, 1.55, 1.2)), Vector3(0.12, 0.6, 0.12), Palette.INK)
	b.box(Transform3D(Basis(), Vector3(0, 1.0, -1.61)), Vector3(1.6, 0.1, 0.02), Palette.CORAL)
	if weapon == "supply":
		for i in 3:
			b.box(Transform3D(Basis(), Vector3(-0.4 + i * 0.4, 1.6, 0.3 - i * 0.2)), Vector3(0.6, 0.5, 0.8), Palette.OCHRE if i % 2 else Palette.PINE)
		b.glow = true
		b.box(Transform3D(Basis(), Vector3(0, 2.0, -0.6)), Vector3(0.3, 0.3, 0.3), Palette.BUTTER)
	var body := MeshInstance3D.new()
	body.mesh = b.mesh()
	model.add_child(body)
	if weapon != "supply":
		_turret = Node3D.new()
		_muzzle = Node3D.new()
		pop_parts = [_turret]
		_turret.position = Vector3(0, 1.35, 0)
		model.add_child(_turret)
		var t := LowPoly.new()
		t.box(Transform3D(Basis(), Vector3(0, 0.25, 0.1)), Vector3(1.0, 0.5, 1.2), Palette.DUSK)
		if weapon == "gun":
			t.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(0.0, 0.3, -0.4)), 0.08, 1.8, 6, Palette.INK)
			_muzzle.position = Vector3(0, 0.3, -2.3)
		else:
			for x in [-0.28, 0.28]:
				t.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(x, 0.55, 0.5)), 0.16, 1.4, 6, Palette.MOSS)
			_muzzle.position = Vector3(0.28, 0.55, -1.0)
		var turret_mesh := MeshInstance3D.new()
		turret_mesh.mesh = t.mesh()
		_turret.add_child(turret_mesh)
		_turret.add_child(_muzzle)
	_eye = MeshInstance3D.new()
	var e := LowPoly.new()
	e.glow = true
	e.box(Transform3D(), Vector3(0.3, 0.14, 0.05), Color.WHITE)
	_eye.mesh = e.mesh()
	_eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_material.albedo_color = Palette.RED
	_eye.material_override = _eye_material
	_eye.position = Vector3(0, 1.05, -1.98)
	model.add_child(_eye)
	_lane = Course.to_course(global_position).y
	_attack_timer = randf_range(1.2, 2.4)


func behave(delta: float) -> void:
	var world := World.current
	var tank := player()
	if tank == null:
		return
	var here := Course.to_course(global_position)
	# Drive: pace ahead of the tank for a while, weaving between lanes.
	_lane_timer -= delta
	if _lane_timer <= 0.0:
		_lane_timer = randf_range(2.0, 3.5)
		_lane = randf_range(-1.0, 1.0) * Tank.lateral_limit(here.x) * 0.8
	var target_d := here.x
	if age < PACE_TIME and world.rail.mode != Rail.Mode.ARENA:
		target_d = world.rail.d + tank.course_offset + KEEP_AHEAD * (1.2 if weapon == "supply" else 1.0)
	# Faster than the rail, so a UGV dropped in behind the tank overtakes it and pulls ahead.
	var speed := 0.0 if is_staggered() or immobile else world.rail.speed + 14.0
	var move := Vector2(clampf(target_d - here.x, -speed, speed), clampf(_lane - here.y, -6.0, 6.0) if not immobile else 0.0)
	var next := here + move * delta
	var p := Course.ground_at(next.x, next.y)
	global_position = p
	var heading := Vector3(move.y, 0, -maxf(absf(move.x), 1.0) * signf(move.x + 0.01))
	if heading.length() > 0.1:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-heading.x, -heading.z), 4.0 * delta)
	if weapon == "supply" or disarmed:
		return
	# Aim the turret at the tank (turret is child of the model).
	var local := model.global_transform.affine_inverse() * tank.hit_center()
	_turret.rotation.y = lerp_angle(_turret.rotation.y, atan2(-local.x, -local.z), 5.0 * delta)
	if is_staggered():
		_cancel()
		return
	var distance := global_position.distance_to(tank.global_position)
	if _burst > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_burst -= 1
			_burst_timer = 0.11
			var shot := fire_at("orb", _muzzle.global_position, tank.hit_center() + Vector3(randf_range(-1.5, 1.5), randf_range(-0.5, 1.0), randf_range(-1.5, 1.5)), 95.0, 4.0)
			shot.hit.caliber = 30
			world.fx.spawn(Fx.Kind.FLAME, _muzzle.global_position, Vector3.ZERO, 0.06, 0.5, Palette.CORAL)
			Sfx.play("enemy_gun", _muzzle.global_position, -2.0)
		return
	if _telegraph > 0.0:
		_telegraph -= delta
		if weapon == "atgm":
			set_meta("locking", true)
			if fmod(_telegraph, 0.1) < 0.06:
				world.fx.beam(_muzzle.global_position, tank.hit_center(), Palette.RED, 0.05, 0.05)
		else:
			_eye_material.albedo_color = Palette.WHITE if fmod(_telegraph, 0.12) < 0.06 else Palette.RED
		if _telegraph <= 0.0:
			_attack()
		return
	_attack_timer -= delta
	if _attack_timer <= 0.0 and distance < 110.0 and distance > 12.0:
		_telegraph = 1.4 if weapon == "atgm" else 0.5
		if weapon == "atgm":
			Sfx.play("lock", global_position)
		_attack_timer = (3.8 if weapon == "atgm" else 2.4) * (0.75 if _hard else 1.0)


func on_damaged(hit: Hit, amount: float) -> void:
	super(hit, amount)
	var world := World.current
	var local := model.global_transform.affine_inverse() * hit.position
	if not immobile and local.y < 0.8:
		tracks_hp -= amount
		if tracks_hp <= 0.0:
			immobile = true
			world.fx.debris(global_position + Vector3.UP * 0.4, 8, [Fx.Debris.METAL, Fx.Debris.DIRT], 7.0, 0.3)
			world.fx.burn(global_position + Vector3.UP * 0.6, 10.0, 0.6)
			world.award(100, global_position, false)
	elif not disarmed and weapon != "supply" and local.y > 1.3:
		weapon_hp -= amount
		if weapon_hp <= 0.0:
			disarmed = true
			_cancel()
			_burst = 0
			_turret.rotation.x = -0.35
			world.fx.explosion(_turret.global_position + Vector3.UP * 0.4, 1.0)
			world.award(100, global_position, false)


func _attack() -> void:
	set_meta("locking", false)
	_eye_material.albedo_color = Palette.RED
	var tank := player()
	if weapon == "gun":
		_burst = 6 if _hard else 5
		_burst_timer = 0.0
		return
	var from := _muzzle.global_position
	var missile := fire_at("atgm", from, from + Vector3.UP * 3.0 + (tank.hit_center() - from).normalized() * 6.0, 32.0, 0.0)
	missile.hit = Hit.make(Hit.Kind.SHELL, 0.0, from)
	missile.hit.source = self
	missile.blast_radius = 2.8
	missile.blast_damage = 30.0
	missile.hit.warhead = true
	missile.homing_target = tank
	missile.turn_rate = 2.4
	missile.interceptable = true
	missile.intercept_hp = 1.6
	missile.life = 6.0
	missile.trail = Projectile.ROCKET_SMOKE
	Sfx.play("launch", from)


func _cancel() -> void:
	if _telegraph > 0.0:
		_telegraph = 0.0
		set_meta("locking", false)
		_eye_material.albedo_color = Palette.RED


func interrupt() -> void:
	super()
	_cancel()
	_burst = 0
