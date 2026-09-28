class_name Walker
extends Enemy
## Bipedal walker with wheels on its feet. It skates between lanes ahead of the tank, then plants
## its feet, crouches with a flashing eye and fires: a 15 mm burst from its arm gun, or a pair of
## missiles from its shoulder pod. A hit low on the legs breaks them and it topples.

const KEEP_AHEAD := 42.0
const PACE_TIME := 14.0
const SKATE_SPEED := 18.0

var weapon := "gun" ## "gun" or "missile".
var legs_hp := 8.0
var crippled := false
var _lane := 0.0
var _lane_timer := 0.0
var _attack_timer := 1.6
var _telegraph := 0.0
var _burst := 0
var _burst_timer := 0.0
var _phase := 0.0
var _body := Node3D.new()
var _legs: Array[Dictionary] = [] ## {hip, knee, ankle, wheel}
var _arm := Node3D.new()
var _muzzle := Node3D.new()
var _pod := Node3D.new()
var _eye_material := StandardMaterial3D.new()
var _hard := false


func _init() -> void:
	super()
	wreck_on_death = true
	max_hp = 16.0
	hp = 16.0
	radius = 1.6
	center_height = 2.6
	armor = 0.0
	stabbable = true
	score = 450
	debris_colors = [Palette.SLATE, Palette.DUSK, Palette.CORAL, Palette.INK]
	weakness = {Hit.Kind.THROWN: 1.5, Hit.Kind.TAIL: 1.3}


func build() -> void:
	_hard = Game.difficulty == Game.Difficulty.HARD
	_body.position = Vector3(0, 2.7, 0)
	model.add_child(_body)
	var b := LowPoly.new()
	# Pelvis block, cockpit pod and a back pack.
	b.box(Transform3D(Basis(), Vector3(0, 0, 0)), Vector3(1.4, 0.5, 1.0), Palette.DUSK)
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.15), Vector3(0, 0.65, -0.1)), Vector3(1.2, 0.8, 1.3), Palette.SLATE, Palette.ASH)
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3(0, 0.55, -0.85)), Vector3(0.9, 0.5, 0.3), Palette.DUSK)
	b.box(Transform3D(Basis(), Vector3(0, 0.7, 0.75)), Vector3(0.9, 0.6, 0.4), Palette.INK)
	b.box(Transform3D(Basis(), Vector3(0.61, 0.7, -0.1)), Vector3(0.02, 0.12, 1.0), Palette.CORAL)
	b.box(Transform3D(Basis(), Vector3(-0.61, 0.7, -0.1)), Vector3(0.02, 0.12, 1.0), Palette.CORAL)
	b.prism(Transform3D(Basis(), Vector3(0.35, 1.05, 0.3)), 0.03, 0.8, 3, Palette.INK)
	_add_mesh(_body, b.mesh())
	var eye := MeshInstance3D.new()
	var e := LowPoly.new()
	e.glow = true
	e.box(Transform3D(), Vector3(0.5, 0.12, 0.04), Color.WHITE)
	eye.mesh = e.mesh()
	_eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_material.albedo_color = Palette.HOT
	eye.material_override = _eye_material
	eye.position = Vector3(0, 0.75, -0.9)
	_body.add_child(eye)
	# Arm gun on the right, missile pod on the left shoulder.
	_arm.position = Vector3(0.85, 0.55, 0)
	_body.add_child(_arm)
	var a := LowPoly.new()
	a.box(Transform3D(Basis(), Vector3(0, 0, 0)), Vector3(0.35, 0.35, 0.9), Palette.DUSK)
	a.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(0, 0, -0.4)), 0.07, 1.1, 6, Palette.INK)
	a.box(Transform3D(Basis(), Vector3(0, -0.25, 0.1)), Vector3(0.25, 0.25, 0.4), Palette.OCHRE)
	_add_mesh(_arm, a.mesh())
	_muzzle.position = Vector3(0, 0, -1.6)
	_arm.add_child(_muzzle)
	_pod.position = Vector3(-0.8, 1.1, 0.1)
	_body.add_child(_pod)
	var p := LowPoly.new()
	p.box(Transform3D(), Vector3(0.6, 0.5, 0.8), Palette.MOSS)
	for x in [-0.14, 0.14]:
		for y in [-0.12, 0.12]:
			p.glow = true
			p.box(Transform3D(Basis(), Vector3(x, y, -0.41)), Vector3(0.12, 0.12, 0.02), Palette.HOT)
			p.glow = false
	_add_mesh(_pod, p.mesh())
	# Reverse-jointed legs ending in wheeled feet.
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.55 * side, -0.1, 0)
		_body.add_child(hip)
		var thigh := LowPoly.new()
		thigh.box(Transform3D(Basis(), Vector3(0, -0.6, -0.15)), Vector3(0.35, 1.3, 0.4), Palette.SLATE)
		thigh.blob(Transform3D(), 0.28, Palette.INK)
		_add_mesh(hip, thigh.mesh())
		var knee := Node3D.new()
		knee.position = Vector3(0, -1.2, -0.3)
		hip.add_child(knee)
		var shin := LowPoly.new()
		shin.box(Transform3D(Basis(), Vector3(0, -0.55, 0.2)), Vector3(0.28, 1.2, 0.3), Palette.DUSK)
		shin.blob(Transform3D(), 0.22, Palette.CORAL)
		_add_mesh(knee, shin.mesh())
		var ankle := Node3D.new()
		ankle.position = Vector3(0, -1.15, 0.35)
		knee.add_child(ankle)
		var foot := LowPoly.new()
		foot.box(Transform3D(Basis(), Vector3(0, -0.05, -0.1)), Vector3(0.45, 0.15, 0.95), Palette.INK)
		_add_mesh(ankle, foot.mesh())
		var wheel := Node3D.new()
		wheel.position = Vector3(0.28 * side, -0.12, 0)
		ankle.add_child(wheel)
		var w := LowPoly.new()
		for z in [-0.35, 0.25]:
			w.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0, z)), 0.2, 0.12, 8, Palette.STONE, -1.0, Palette.BUTTER)
		_add_mesh(wheel, w.mesh())
		_legs.append({"hip": hip, "knee": knee, "ankle": ankle, "wheel": wheel, "side": side})
	_lane = Course.to_course(global_position).y
	_attack_timer = randf_range(1.2, 2.2)


func _add_mesh(parent: Node3D, mesh: Mesh) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	parent.add_child(instance)


func behave(delta: float) -> void:
	var world := World.current
	var tank := player()
	if tank == null:
		return
	var here := Course.to_course(global_position)
	var planted := _telegraph > 0.0 or _burst > 0 or crippled or is_staggered()
	_lane_timer -= delta
	if _lane_timer <= 0.0:
		_lane_timer = randf_range(1.2, 2.4)
		_lane = randf_range(-1.0, 1.0) * Tank.lateral_limit(here.x) * 0.8
	var target_d := here.x
	if age < PACE_TIME and world.rail.mode != Rail.Mode.ARENA:
		target_d = world.rail.d + tank.course_offset + KEEP_AHEAD
	var move := Vector2.ZERO
	if not planted:
		var chase := world.rail.speed + 12.0
		move = Vector2(clampf(target_d - here.x, -chase, chase), clampf(_lane - here.y, -SKATE_SPEED, SKATE_SPEED) * 0.9)
	var next := here + move * delta
	global_position = Course.ground_at(next.x, next.y)
	# Face the tank; lean into lateral skating.
	var to_tank := tank.global_position - global_position
	model.rotation.y = lerp_angle(model.rotation.y, atan2(-to_tank.x, -to_tank.z), 5.0 * delta)
	_animate(delta, move, planted)
	if crippled or is_staggered():
		_telegraph = 0.0
		return
	if _burst > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_burst -= 1
			_burst_timer = 0.08
			var shot := fire_at("orb", _muzzle.global_position, tank.hit_center() + Vector3(randf_range(-1.2, 1.2), randf_range(-0.3, 0.8), randf_range(-1.2, 1.2)), 100.0, 3.0)
			shot.hit.caliber = 15
			world.fx.muzzle_flash(_muzzle.global_position, (tank.hit_center() - _muzzle.global_position).normalized(), 0.5, Palette.HOT)
			Sfx.play("enemy_gun", _muzzle.global_position, -4.0, 1.2)
			_body.position.z = 0.1
		return
	if _telegraph > 0.0:
		_telegraph -= delta
		_eye_material.albedo_color = Palette.WHITE if fmod(_telegraph, 0.1) < 0.05 else Palette.HOT
		if _telegraph <= 0.0:
			_attack(tank)
		return
	_attack_timer -= delta
	var distance := global_position.distance_to(tank.global_position)
	if _attack_timer <= 0.0 and distance < 90.0 and distance > 10.0:
		_telegraph = 0.55
		_attack_timer = (2.2 if weapon == "gun" else 3.2) * (0.75 if _hard else 1.0)
		Sfx.play("warn", global_position, -6.0, 1.6)


func _attack(tank: Tank) -> void:
	_eye_material.albedo_color = Palette.HOT
	if weapon == "gun":
		_burst = 8 if _hard else 6
		_burst_timer = 0.0
		return
	for i in 2:
		var from := _pod.global_position + Vector3(0, 0.2, 0)
		var missile := fire_at("rocket", from, from + Vector3(randf_range(-3, 3), 4.0, 0) + (tank.hit_center() - from).normalized() * 3.0, 34.0, 0.0)
		missile.hit = Hit.make(Hit.Kind.SHELL, 0.0, from)
		missile.hit.source = self
		missile.blast_radius = 2.4
		missile.blast_damage = 12.0
		missile.homing_target = tank
		missile.turn_rate = 1.3
		missile.interceptable = true
		missile.intercept_hp = 0.7
		missile.trail = Palette.MIST
		missile.life = 5.0
	Sfx.play("launch", _pod.global_position, 0.0, 1.3)


## Settles into the planted crouch without running any AI (debug room).
func pose_idle() -> void:
	for _i in 30:
		_animate(0.05, Vector2.ZERO, true)


## Skating stride: legs push alternately while moving, crouch when planted, wheels spin.
func _animate(delta: float, move: Vector2, planted: bool) -> void:
	var speed := move.length()
	_phase += delta * (4.0 + speed * 0.4)
	var crouch := 0.55 if planted and not crippled else 0.25
	_body.position.y = lerpf(_body.position.y, 2.7 - crouch * 0.8, 8.0 * delta)
	_body.position.z = move_toward(_body.position.z, 0.0, delta)
	_body.rotation.z = lerpf(_body.rotation.z, clampf(-move.y * 0.02, -0.3, 0.3), 5.0 * delta)
	for leg in _legs:
		var push: float = sin(_phase + (0.0 if leg.side < 0.0 else PI)) * clampf(speed / 18.0, 0.0, 1.0)
		(leg.hip as Node3D).rotation.x = -0.35 - crouch + push * 0.5
		(leg.knee as Node3D).rotation.x = 0.7 + crouch * 1.6 - push * 0.3
		(leg.ankle as Node3D).rotation.x = -0.35 - crouch * 0.8
		(leg.hip as Node3D).rotation.z = push * 0.25 * leg.side
		(leg.wheel as Node3D).rotation.x += delta * speed * 3.0
	if crippled:
		# Broken legs: slumped to one side, sparking.
		model.rotation.z = lerpf(model.rotation.z, 0.8, 3.0 * delta)
		_body.position.y = lerpf(_body.position.y, 1.2, 3.0 * delta)
		if randf() < delta * 6.0:
			World.current.fx.sparks(_body.global_position, Vector3.UP, 4, Palette.BUTTER)


func on_damaged(hit: Hit, amount: float) -> void:
	super(hit, amount)
	var local := model.global_transform.affine_inverse() * hit.position
	if not crippled and local.y < 1.8:
		legs_hp -= amount
		if legs_hp <= 0.0:
			crippled = true
			World.current.fx.debris(global_position + Vector3.UP, 8, [Palette.INK, Palette.CORAL], 7.0, 0.3)
			World.current.award(100, global_position, false)


func interrupt() -> void:
	super()
	_telegraph = 0.0
	_burst = 0
	_eye_material.albedo_color = Palette.HOT
