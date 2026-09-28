class_name Uav
extends Enemy
## Fixed-wing drone making attack runs: a head-on pass, a banked turn overhead, then a pass from
## behind. `attack`: "bomb" drops bombs on marked circles; "strafe" walks gunfire down the road.

const SPEED := 42.0
const ALTITUDE := 17.0

var attack := "bomb"
var _dir := Vector3.BACK
var _pass := 0
var _turn := 0.0
var _bombs := 0
var _bomb_timer := 0.0
var _strafe := 0
var _strafe_timer := 0.0
var _strafe_point := Vector3.ZERO
var _strafe_step := Vector3.ZERO
var _prop: Node3D
var _sound: AudioStreamPlayer3D
var engine_hp := 18.0 ## A hit on the pusher engine sends it gliding into the ground.
var _falling := false


func _init() -> void:
	super()
	max_hp = 40.0
	hp = 40.0
	radius = 2.4
	flying = true
	score = 500
	death_radius = 2.6
	despawn_behind = 0.0
	debris_colors = [Palette.MIST, Palette.SLATE, Palette.INK]
	weakness = {Hit.Kind.BLAST: 1.4}


func build() -> void:
	var b := LowPoly.new()
	b.box(Transform3D(Basis(), Vector3(0, 0, 0)), Vector3(0.6, 0.55, 3.6), Palette.MIST)
	b.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -1.8)), 0.3, 0.7, 6, Palette.MIST, 0.05)
	b.box(Transform3D(Basis(), Vector3(0, 0.15, -0.2)), Vector3(6.4, 0.08, 0.9), Palette.CONCRETE)
	for x in [-1.2, 1.2]:
		b.box(Transform3D(Basis(), Vector3(x, 0.1, 1.4)), Vector3(0.12, 0.12, 2.6), Palette.SLATE)
		b.box(Transform3D(Basis(Vector3.BACK, 0.5 * signf(x)), Vector3(x * 1.1, 0.5, 2.6)), Vector3(0.06, 0.8, 0.5), Palette.SLATE)
	b.box(Transform3D(Basis(), Vector3(0, -0.35, -0.9)), Vector3(0.35, 0.3, 0.35), Palette.INK)
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(3.2, 0.15, -0.2)), Vector3(0.12, 0.1, 0.2), Palette.RED)
	b.box(Transform3D(Basis(), Vector3(-3.2, 0.15, -0.2)), Vector3(0.12, 0.1, 0.2), Palette.MINT)
	var body := MeshInstance3D.new()
	body.mesh = b.mesh()
	model.add_child(body)
	_prop = MeshInstance3D.new()
	var p := LowPoly.new()
	p.glow = true
	p.prism(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), 0.7, 0.03, 6, Palette.MIST)
	(_prop as MeshInstance3D).mesh = p.mesh()
	_prop.position = Vector3(0, 0, 1.9)
	model.add_child(_prop)
	# Enter far ahead and fly back down the road toward the tank.
	var world := World.current
	var slot: Vector3 = get_meta("slot", Vector3(0, 0, 0))
	var d := world.rail.d + 220.0 + slot.z * 0.2
	global_position = Course.to_world(d, slot.x, Course.height(d, slot.x) + ALTITUDE + slot.y)
	_dir = -world.rail.forward()
	_bombs = 5 if Game.difficulty == Game.Difficulty.HARD else 4
	_sound = Sfx.loop("jet", self, -4.0)


func on_damaged(hit: Hit, amount: float) -> void:
	super(hit, amount)
	var local := model.global_transform.affine_inverse() * hit.position
	if not _falling and local.z > 1.0:
		engine_hp -= amount
		if engine_hp <= 0.0:
			_falling = true
			World.current.fx.explosion(_prop.global_position, 0.8)
			World.current.fx.burn(_prop.global_position, 0.1, 0.5)


func behave(delta: float) -> void:
	if _falling:
		# Engine out: nose down, trailing smoke, until it hits the ground.
		_dir = (_dir + Vector3.DOWN * delta * 0.8).normalized()
		global_position += _dir * SPEED * delta
		model.look_at(global_position + _dir, Vector3.UP)
		model.rotate_object_local(Vector3.FORWARD, age * 3.0)
		World.current.fx.smoke(global_position, 1, 0.6, [Palette.ASH, Palette.STONE])
		if global_position.y <= Course.height_at(global_position) + 0.5:
			die(Hit.make(Hit.Kind.RAM, 999.0, global_position))
		return
	var world := World.current
	var tank := player()
	if tank == null:
		return
	_prop.rotation.z += delta * 40.0
	if is_staggered():
		# Knocked into a stall: nose dips and it loses height.
		global_position.y -= 6.0 * delta
	var ground := Course.height_at(global_position)
	var desired_y := ground + ALTITUDE
	global_position.y = lerpf(global_position.y, desired_y, 1.5 * delta)
	var to_tank := tank.global_position - global_position
	var flat := Vector2(to_tank.x, to_tank.z)
	var ahead := flat.dot(Vector2(_dir.x, _dir.z))
	if _turn > 0.0:
		# Banked 180° turn overhead.
		_turn -= delta
		_dir = _dir.rotated(Vector3.UP, PI / 2.2 * delta)
		model.rotation.z = lerpf(model.rotation.z, 0.8, 3.0 * delta)
		if _turn <= 0.0:
			_dir = world.rail.forward()
			_pass += 1
			_bombs = 3
			_strafe = 0
	else:
		model.rotation.z = lerpf(model.rotation.z, 0.0, 3.0 * delta)
		if ahead < -35.0:
			if _pass == 0:
				_turn = 2.2
			elif global_position.distance_to(tank.global_position) > 260.0:
				despawn()
				return
	var speed := SPEED + (world.rail.speed if _pass > 0 else 0.0)
	global_position += _dir * speed * delta
	model.look_at(global_position + _dir, Vector3.UP)
	if attack == "bomb":
		_bomb_run(delta, tank, ahead)
	else:
		_strafe_run(delta, tank, ahead)


func _bomb_run(delta: float, tank: Tank, ahead: float) -> void:
	_bomb_timer -= delta
	if _bombs <= 0 or ahead > 55.0 or ahead < 5.0 or _bomb_timer > 0.0 or is_staggered():
		return
	_bombs -= 1
	_bomb_timer = 0.22
	var world := World.current
	var flight := 1.3
	var target := tank.global_position + tank.velocity * flight + Vector3(randf_range(-5, 5), 0, randf_range(-6, 6))
	target.y = Course.height_at(target)
	var from := global_position + Vector3.DOWN * 0.6
	var velocity_out := (target - from) / flight
	velocity_out.y += 0.5 * 20.0 * flight
	var bomb := world.spawn_projectile(Team.ENEMY, from, velocity_out, "bomb", Palette.HOT)
	bomb.gravity = 20.0
	bomb.hit = Hit.make(Hit.Kind.BLAST, 0.0, from)
	bomb.hit.source = self
	bomb.blast_radius = 3.6
	bomb.blast_damage = 18.0
	bomb.interceptable = true
	bomb.intercept_hp = 0.8
	bomb.life = flight + 1.0
	world.fx.marker(target, 3.6, flight, Palette.RED)
	Sfx.play("warn", target, -6.0, 1.4)


func _strafe_run(delta: float, tank: Tank, ahead: float) -> void:
	var world := World.current
	if _strafe == 0 and ahead < 80.0 and ahead > 45.0 and _turn <= 0.0 and not is_staggered():
		# Start the walking line well ahead of the tank so the dust shows where it will go.
		_strafe = 22
		var along := Vector3(_dir.x, 0, _dir.z).normalized()
		_strafe_point = tank.global_position - along * 26.0 + tank.global_basis.x * randf_range(-3, 3)
		_strafe_step = along * 2.4
	if _strafe <= 0:
		return
	_strafe_timer -= delta
	if _strafe_timer > 0.0:
		return
	_strafe_timer = 0.05
	_strafe -= 1
	_strafe_point += _strafe_step
	var ground := _strafe_point + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
	ground.y = Course.height_at(ground)
	var shot := fire_at("orb", global_position + Vector3.DOWN * 0.5, ground, 150.0, 5.0)
	shot.hit.caliber = 23
	Sfx.play("enemy_gun", global_position, -4.0, 1.2)
	if _strafe == 0:
		_strafe = -1 # One line per pass.


func on_death(hit: Hit) -> void:
	super(hit)
	# Wreck spirals down trailing smoke.
	World.current.fx.debris(hit_center(), 10, [Palette.MIST, Palette.INK], 14.0, 0.5)
