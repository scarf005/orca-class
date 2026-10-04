class_name RooftopBattery
extends Enemy
## Fixed roof launcher: marks a spread across the tank's lane before a rocket ripple.

var _launcher := Node3D.new()
var _muzzle := Node3D.new()
var _timer := 1.0
var _wind := 0.0
var _burst := 0
var _targets: Array[Vector3] = []


func _init() -> void:
	super()
	max_hp = 40.0
	hp = max_hp
	armor = 10.0
	radius = 1.5
	center_height = 1.2
	stabbable = true
	score = 450


func build() -> void:
	global_position.y = CityCover.surface_at(global_position)
	var b := LowPoly.new()
	b.prism(Transform3D(), 1.6, 0.5, 8, Palette.STONE, 1.2)
	for side in [-1.0, 1.0]:
		b.box(Transform3D(Basis(), Vector3(side * 1.5, 0.7, 0)), Vector3(0.5, 0.8, 3.2), Palette.MOSS)
	var base := MeshInstance3D.new()
	base.mesh = b.mesh()
	model.add_child(base)
	_launcher.position.y = 1.2
	model.add_child(_launcher)
	var rack := LowPoly.new()
	rack.box(Transform3D(), Vector3(2.1, 0.8, 2.0), Palette.SLATE)
	rack.glow = true
	for x in [-0.7, 0.0, 0.7]:
		for y in [-0.2, 0.2]:
			rack.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(x, y, -0.9)), 0.16, 0.2, 6, Palette.CORAL)
	var mesh := MeshInstance3D.new()
	mesh.mesh = rack.mesh()
	_launcher.add_child(mesh)
	_muzzle.position.z = -1.2
	_launcher.add_child(_muzzle)


func behave(delta: float) -> void:
	var tank := player()
	if tank == null or tank.dead or is_staggered():
		return
	aim_barrel(_launcher, tank.hit_center(), 3.0, delta)
	if _wind > 0.0:
		_wind = maxf(0.0, _wind - delta)
		if _wind == 0.0:
			_burst = _targets.size()
			_timer = 0.0
	elif _burst > 0:
		_timer -= delta
		if _timer <= 0.0:
			var target := _targets[_targets.size() - _burst]
			var shot := fire_at("rocket", _muzzle.global_position, target, 45.0, 0.0)
			shot.hit.kind = Hit.Kind.SHELL
			shot.blast_radius = 3.0
			shot.blast_damage = 12.0
			shot.interceptable = true
			shot.intercept_hp = 0.55
			shot.trail = Projectile.ROCKET_SMOKE
			shot.life = 6.0
			_burst -= 1
			_timer = 0.18 if _burst > 0 else 2.0
	else:
		_timer -= delta
		if _timer <= 0.0 and global_position.distance_to(tank.global_position) < 140.0 and CityCover.blocker(_muzzle.global_position, tank.hit_center()) == null:
			_wind = 0.9 * Game.telegraph_scale()
			_targets.clear()
			var c := Course.to_course(tank.global_position + tank.velocity * 1.0)
			for i in 4:
				var target := Course.ground_at(c.x, c.y + (i - 1.5) * 4.0)
				_targets.append(target)
				World.current.fx.marker(target, 3.0, _wind + global_position.distance_to(target) / 45.0 + i * 0.18, Palette.HOT)
			Sfx.play("warn", global_position)


func telegraphing() -> bool:
	return _wind > 0.0


func interrupt() -> void:
	super()
	_wind = 0.0
	_burst = 0
	_timer = 1.0
