class_name Uav
extends Enemy
## Fixed-wing drone making attack runs: a head-on pass, a banked turn overhead, then a pass from
## behind. `attack`: "bomb" lays a carpet of bombs across the road; "strafe" walks gunfire down the road.

const SPEED := 42.0 ## Diving speed when its engine is shot out.
const HEAD_ON_SPEED := 20.0 ## First pass, toward the tank: slow enough to shoot down.
const OVERTAKE := 8.0 ## Later passes creep past the tank this much faster than the rail.
const LEAVE := 40.0
const ALTITUDE := 17.0
const BOMB_FLIGHT := 1.3 ## Seconds from release to impact; the marked circles show for all of it.
const CARPET_BOMBS := 5 ## Bombs per run, in a line across the road with one slot left empty.
const CARPET_SPACING := 5.0
const CARPET_LEAD := 1.0 ## Seconds ahead the tank's sideways position is predicted for the carpet's centre.
const BARREL_SLEW := 2.5 ## Radians per second the strafing gun turns onto the next point of its line.

var attack := "bomb"
var from_behind := false ## Arrives from behind the tank on an overtaking pass.
var _leaving := false
var _dir := Vector3.BACK
var _sense := -1.0 ## -1 while flying back down the road toward the tank, +1 after turning.
var _pass := 0
var _turn := 0.0
var _bombs := 0 ## Carpets still to drop on this pass.
var _bomb_timer := 0.0
var _strafe := 0
var _strafe_timer := 0.0
var _strafe_point := Vector3.ZERO
var _strafe_step := Vector3.ZERO
var _prop: Node3D
var _gun: Node3D ## Strafers hang a cannon under the nose; it turns onto the line it walks along the road.
var _muzzle: Node3D
var engine_hp := 5.0 ## A hit on the pusher engine sends it gliding into the ground.
var _falling := false


func _init() -> void:
	super()
	wreck_on_death = true
	max_hp = 20.0
	hp = 20.0
	radius = 2.4
	flying = true
	trails = true
	score = 500
	despawn_behind = 0.0
	debris = [Fx.Debris.PAINT, Fx.Debris.METAL]
	weakness = {Hit.Kind.BLAST: 1.4, Hit.Kind.FRAGMENT: 2.0}


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
	if attack == "strafe":
		_gun = Node3D.new()
		_gun.position = Vector3(0, -0.35, -0.9)
		model.add_child(_gun)
		var g := LowPoly.new()
		g.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3.ZERO), 0.07, 1.4, 6, Palette.INK)
		var gun_mesh := MeshInstance3D.new()
		gun_mesh.mesh = g.mesh()
		_gun.add_child(gun_mesh)
		_muzzle = Node3D.new()
		_muzzle.position = Vector3(0, 0, -1.5)
		_gun.add_child(_muzzle)
	# Enter far ahead and fly back down the road toward the tank.
	var world := World.current
	var slot: Vector3 = get_meta("slot", Vector3(0, 0, 0))
	var d := world.rail.d + 220.0 + slot.z * 0.2
	if from_behind:
		d = world.rail.d - 70.0 - slot.z * 0.2
		_sense = 1.0
		_pass = 1
	global_position = Course.to_world(d, slot.x, Course.height(d, slot.x) + ALTITUDE + slot.y)
	_dir = Course.forward(d) * _sense
	_bombs = 2 if Game.difficulty == Game.Difficulty.HARD else 1
	Sfx.loop("jet", self, -4.0)


func telegraphing() -> bool:
	return _strafe > 0


func on_damaged(hit: Hit, amount: float) -> void:
	super(hit, amount)
	var local := model.global_transform.affine_inverse() * hit.position
	if not _falling and local.z > 1.0:
		engine_hp -= amount
		if engine_hp <= 0.0:
			killing_hit = hit.copy()
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
			_sense = 1.0
			_pass += 1
			_bombs = 1
			_strafe = 0
	else:
		_dir = Course.forward(Course.to_course(global_position).x) * _sense
		model.rotation.z = lerpf(model.rotation.z, 0.0, 3.0 * delta)
		if ahead < -35.0 and _pass == 0:
			_turn = 2.2
		elif ahead < -45.0 and _pass > 0:
			_leaving = true
		if _leaving and global_position.distance_to(tank.global_position) > 220.0:
			despawn()
			return
	var speed := HEAD_ON_SPEED
	if _turn > 0.0:
		speed = world.rail.speed
	elif _pass > 0:
		speed = world.rail.speed + (LEAVE if _leaving else OVERTAKE)
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
	_bomb_timer = 1.6
	# A line of bombs across the road centred where the tank will be; one slot is left open.
	var world := World.current
	var centre := Course.to_course(tank.global_position + tank.velocity * CARPET_LEAD)
	var along := Course.to_course(tank.global_position + tank.velocity * BOMB_FLIGHT).x
	var gap := randi() % CARPET_BOMBS
	for i in CARPET_BOMBS:
		if i == gap:
			continue
		var target := Course.to_world(along, centre.y + (i - (CARPET_BOMBS - 1) * 0.5) * CARPET_SPACING)
		target.y = Course.height_at(target)
		_drop_bomb(target)
		world.fx.marker(target, 3.6, BOMB_FLIGHT, Palette.RED)
		Sfx.play("warn", target, -6.0, 1.4)


func _drop_bomb(target: Vector3) -> void:
	var from := global_position + Vector3.DOWN * 0.6
	var velocity_out := (target - from) / BOMB_FLIGHT
	velocity_out.y += 0.5 * 20.0 * BOMB_FLIGHT
	var bomb := World.current.spawn_projectile(Team.ENEMY, from, velocity_out, "bomb", Palette.HOT)
	bomb.gravity = 20.0
	bomb.hit = Hit.make(Hit.Kind.BLAST, 0.0, from)
	bomb.hit.source = self
	bomb.blast_radius = 3.6
	bomb.blast_damage = 30.0
	bomb.interceptable = true
	bomb.intercept_hp = 0.8
	bomb.life = BOMB_FLIGHT + 1.0


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
	var line := _strafe_point + _strafe_step
	line.y = Course.height_at(line)
	aim_barrel(_gun, line, BARREL_SLEW, delta)
	_strafe_timer -= delta
	if _strafe_timer > 0.0:
		return
	_strafe_timer = 0.05
	_strafe -= 1
	_strafe_point += _strafe_step
	var ground := _strafe_point + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8))
	ground.y = Course.height_at(ground)
	var shot := fire_along("orb", _muzzle, MG_SPEED, 5.0, Palette.HOT, ground - _muzzle.global_position, 4.0, 0.0, Muzzle.LIGHT)
	shot.hit.caliber = 23
	Sfx.play("enemy_gun", global_position, -4.0, 1.2)
	if _strafe == 0:
		_strafe = -1 # One line per pass.


func on_death(hit: Hit) -> void:
	super(hit)
	# Wreck spirals down trailing smoke.
	World.current.fx.debris(hit_center(), 10, [Fx.Debris.PAINT, Fx.Debris.METAL], 14.0, 0.5)
