class_name Ugv
extends Enemy
## Tracked unmanned ground vehicle. Keeps ahead of the tank, hopping between lanes.
## `weapon`: "gun" fires telegraphed 30 mm bursts, "atgm" paints the tank with a laser before
## launching a guided missile, "supply" carries a pickup and tries to get away. A "gun" UGV the tank has
## driven past in its own lane spins its tracks up in a cloud of dust (0.6 s) and rams it from behind.

const KEEP_AHEAD := 48.0
const PACE_TIME := 13.0 ## After this long it stops pacing the rail and falls behind.
const BARREL_SLEW := 3.0 ## Radians per second the gun turns onto the tank.
const GUN_SPREAD := 0.03 ## Radians of scatter on every round.
const ROUND_SPEED := MG_SPEED
const FRONT_ARMOR := 0.25 ## Share of coax damage that gets through the front plate.
const RAM_WIND := 0.6 ## Seconds the tracks spin up, throwing dust, before the charge.
const RAM_SPEED := 30.0
const RAM_TIME := 1.6 ## The charge ends this long after it starts, hit or miss.
const RAM_REACH := Vector2(8.0, 60.0) ## It picks a tank this far ahead along the road ...
const RAM_LANE := 3.5 ## ... and this close to its own lane.
const RAM_COOLDOWN := 5.0
const RAM_DAMAGE := 20.0
const RAM_SHOVE := 12.0 ## Sideways speed the hit adds to the tank.

var weapon := "gun"
var _at_tail := false ## This burst goes for the tank's tail, not its roof sensors.
var _lane := 0.0
var _lane_timer := 0.0
var _attack_timer := 2.0
var _telegraph := 0.0
var _burst := 0
var _burst_timer := 0.0
var _ram_wind := 0.0
var _ram := 0.0 ## Seconds of the charge left.
var _ram_cooldown := 0.0
var _aim := Vector3.ZERO ## Where the gun burst goes: fixed when the telegraph ends.
var _turret: Node3D
var _barrel: Node3D ## Gun or launcher pivot on the turret; its -Z is the bore.
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
	max_hp = 60.0
	hp = 60.0
	radius = 1.8
	center_height = 1.0
	armor = 12.0 ## Millimetres: the light coax glances off; heavier rounds bite less.
	stabbable = true
	score = 400
	debris = [Fx.Debris.ARMOR, Fx.Debris.METAL]
	weakness = {Hit.Kind.THROWN: 1.5, Hit.Kind.TAIL: 1.5, Hit.Kind.FRAGMENT: 0.3}
	mark_offsets = [-0.95, 0.95] # Under its two tracks: a narrower gauge than the tank's.
	mark_width = 0.6


func build() -> void:
	_hard = Game.difficulty == Game.Difficulty.HARD
	if weapon == "atgm":
		max_hp = 60.0
	elif weapon == "supply":
		max_hp = 45.0
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
		_barrel = Node3D.new()
		_muzzle = Node3D.new()
		pop_parts = [_turret]
		_turret.position = Vector3(0, 1.35, 0)
		model.add_child(_turret)
		var t := LowPoly.new()
		t.box(Transform3D(Basis(), Vector3(0, 0.25, 0.1)), Vector3(1.0, 0.5, 1.2), Palette.DUSK)
		var turret_mesh := MeshInstance3D.new()
		turret_mesh.mesh = t.mesh()
		_turret.add_child(turret_mesh)
		# The gun (or launcher tubes) is its own pivot: it slews onto the tank and rounds leave along it.
		var g := LowPoly.new()
		if weapon == "gun":
			g.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3.ZERO), 0.08, 1.8, 6, Palette.INK)
			_barrel.position = Vector3(0, 0.3, -0.4)
			_muzzle.position = Vector3(0, 0, -1.9)
		else:
			for x in [-0.28, 0.28]:
				g.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(x, 0, 0)), 0.16, 1.4, 6, Palette.MOSS)
			_barrel.position = Vector3(0, 0.55, 0.5)
			_muzzle.position = Vector3(0.28, 0, -1.5)
		var barrel_mesh := MeshInstance3D.new()
		barrel_mesh.mesh = g.mesh()
		_barrel.add_child(barrel_mesh)
		_barrel.add_child(_muzzle)
		_turret.add_child(_barrel)
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
	if weapon == "gun":
		move = _ram_step(delta, tank, here, move)
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
	aim_barrel(_barrel, _aim_point(tank), BARREL_SLEW, delta)
	if is_staggered():
		_cancel()
		return
	var distance := global_position.distance_to(tank.global_position)
	if _burst > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_burst -= 1
			_burst_timer = 0.11
			var shot := fire_along("orb", _muzzle, ROUND_SPEED, 4.0, Palette.HOT, _aim - _muzzle.global_position, 3.0, GUN_SPREAD, Muzzle.AUTO)
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
	if _attack_timer <= 0.0 and distance < 110.0 and distance > 12.0 and _ram_wind <= 0.0 and _ram <= 0.0:
		_telegraph = (1.4 if weapon == "atgm" or _hard else 0.5) * Game.telegraph_scale()
		_at_tail = randf() < Gunnery.TAIL_CHANCE
		if weapon == "atgm":
			Sfx.play("lock", global_position)
		_attack_timer = (3.8 if weapon == "atgm" else 2.4) * (0.75 if _hard else 1.0)


## Winds up and charges at a tank that is ahead of it in its lane; returns the drive for this frame.
func _ram_step(delta: float, tank: Tank, here: Vector2, move: Vector2) -> Vector2:
	_ram_cooldown = maxf(0.0, _ram_cooldown - delta)
	if immobile or is_staggered():
		_ram_wind = 0.0
		_ram = 0.0
		return move
	var ahead := Course.to_course(tank.global_position) - here
	if _ram_wind <= 0.0 and _ram <= 0.0:
		if _ram_cooldown <= 0.0 and _burst == 0 and _telegraph <= 0.0 and ahead.x > RAM_REACH.x and ahead.x < RAM_REACH.y and absf(ahead.y) < RAM_LANE:
			_ram_wind = RAM_WIND * Game.telegraph_scale()
			Sfx.play("warn", global_position, -2.0, 0.7)
		return move
	if fmod(age, 0.1) < delta:
		for x in [-0.95, 0.95]:
			World.current.fx.dust(model.to_global(Vector3(x, 0.1, 1.4)), 2, 1.2, Palette.STRAW)
	if _ram_wind > 0.0:
		_ram_wind -= delta
		_eye_material.albedo_color = Palette.WHITE if fmod(_ram_wind, 0.12) < 0.06 else Palette.RED
		if _ram_wind <= 0.0:
			_eye_material.albedo_color = Palette.RED
			_ram = RAM_TIME
		return Vector2.ZERO
	_ram -= delta
	if Vector2(tank.global_position.x - global_position.x, tank.global_position.z - global_position.z).length() < radius + tank.radius + 0.5 and not tank.dead:
		_land_ram(tank)
	return Vector2(RAM_SPEED, clampf(ahead.y, -8.0, 8.0))


func _land_ram(tank: Tank) -> void:
	var world := World.current
	_ram = 0.0
	_ram_cooldown = RAM_COOLDOWN
	if _hard and not disarmed and weapon != "supply":
		_attack_timer = 0.0
	var hit := Hit.make(Hit.Kind.RAM, RAM_DAMAGE, tank.hit_center(), (tank.global_position - global_position).normalized())
	hit.source = self
	tank.take_hit(hit)
	tank.local_velocity.x += signf(Course.to_course(tank.global_position).y - Course.to_course(global_position).y) * RAM_SHOVE
	world.fx.sparks(tank.hit_center(), hit.direction, 12, Palette.BUTTER, 12.0)
	world.shake(0.4, global_position)
	Sfx.play("impact", tank.global_position)


func damage_multiplier(hit: Hit) -> float:
	return super(hit) * frontal_armor(hit, FRONT_ARMOR)


func telegraphing() -> bool:
	return _telegraph > 0.0 or _ram_wind > 0.0


func on_damaged(hit: Hit, amount: float) -> void:
	super(hit, amount)
	amount /= frontal_armor(hit, FRONT_ARMOR) # The front plate guards the hull, not the modules behind it.
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
	if weapon == "gun" or _hard:
		_aim = Gunnery.sensor_lead(tank, _muzzle.global_position, ROUND_SPEED, _at_tail)
		_burst = 6 if _hard else 5
		_burst_timer = 0.0
		if not _hard:
			return
	var from := _muzzle.global_position
	var missile := fire_along("atgm", _muzzle, 32.0, 0.0, Palette.HOT, Vector3.ZERO, 3.0, 0.02)
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


## What the barrel turns onto: the lead on the sensor while a gun winds up, then that point held
## for the burst; the other weapons follow the roof sensor (the RWS first).
func _aim_point(tank: Tank) -> Vector3:
	if weapon != "gun":
		return Gunnery.sensor_lead(tank, _muzzle.global_position, 32.0)
	return _aim if _burst > 0 else Gunnery.sensor_lead(tank, _muzzle.global_position, ROUND_SPEED, _at_tail)


func _cancel() -> void:
	_ram_wind = 0.0
	if _telegraph > 0.0:
		_telegraph = 0.0
		set_meta("locking", false)
		_eye_material.albedo_color = Palette.RED


func interrupt() -> void:
	super()
	_cancel()
	_ram = 0.0
	_burst = 0
