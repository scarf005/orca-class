class_name HeronWalker
extends Enemy
## A white stilt walker in the paddies. It freezes until close, then plants a beak-lance circle.
## Leg health is separate; once toppled it becomes a clear tail-stab target.

enum State { STILL, TELEGRAPH, FALLEN }
const TELEGRAPH_TIME := 0.9
const REACH := 14.0

var state := State.STILL
var fallen := false
var legs_hp := 10.0
var _state_time := 0.0
var _attack_timer := 1.8
var _neck := Node3D.new()
var _eye_material := StandardMaterial3D.new()
var _legs: Array[Node3D] = []
var _impact := Vector3.ZERO

func _init() -> void:
	super()
	max_hp = 22.0
	hp = max_hp
	radius = 1.6
	center_height = 3.6
	stabbable = true
	wreck_on_death = true
	score = 500
	debris = [Fx.Debris.METAL, Fx.Debris.PAINT]
	weakness = {Hit.Kind.TAIL: 1.5}

func build() -> void:
	var body := LowPoly.new()
	body.box(Transform3D(Basis(), Vector3(0, 3.1, 0)), Vector3(1.7, 1.2, 1.3), Palette.CREAM, Palette.PEACH)
	body.box(Transform3D(Basis(), Vector3(0, 3.8, -0.15)), Vector3(1.2, 0.7, 0.9), Palette.SKY)
	body.gable(Transform3D(Basis(), Vector3(0, 4.25, 0)), Vector3(1.4, 0.3, 1.0), Palette.MAUVE, Palette.LILAC)
	var body_mesh := MeshInstance3D.new()
	body_mesh.mesh = body.mesh()
	model.add_child(body_mesh)
	_neck.position = Vector3(0, 4.0, -0.35)
	model.add_child(_neck)
	var neck_mesh := LowPoly.new()
	neck_mesh.prism(Transform3D(), 0.22, 2.3, 6, Palette.CREAM)
	neck_mesh.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(0, 2.25, 0)), 0.08, 1.2, 5, Palette.OCHRE)
	var neck_instance := MeshInstance3D.new()
	neck_instance.mesh = neck_mesh.mesh()
	_neck.add_child(neck_instance)
	var eye := MeshInstance3D.new()
	var eye_poly := LowPoly.new()
	eye_poly.glow = true
	eye_poly.box(Transform3D(), Vector3(0.25, 0.18, 0.06), Palette.RED)
	eye.mesh = eye_poly.mesh()
	eye.position = Vector3(0, 2.35, -0.13)
	_neck.add_child(eye)
	_eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_material.albedo_color = Palette.RED
	eye.material_override = _eye_material
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.55, 0.0, 0.05)
		var leg_poly := LowPoly.new()
		leg_poly.prism(Transform3D(), 0.18, 2.8, 5, Palette.SLATE)
		leg_poly.prism(Transform3D(Basis(), Vector3(0, 2.7, 0)), 0.14, 1.6, 5, Palette.CORAL)
		leg_poly.box(Transform3D(Basis(), Vector3(0, 0.05, -0.3)), Vector3(0.55, 0.16, 0.9), Palette.INK)
		var leg_mesh := MeshInstance3D.new()
		leg_mesh.mesh = leg_poly.mesh()
		leg.add_child(leg_mesh)
		model.add_child(leg)
		_legs.append(leg)
	global_position.y = Course.height_at(global_position)

func behave(delta: float) -> void:
	_state_time += delta
	var tank := player()
	if tank == null:
		return
	if fallen:
		model.rotation.z = lerpf(model.rotation.z, 0.95, delta * 3.0)
		return
	var offset := tank.global_position - global_position
	var facing := atan2(-offset.x, -offset.z)
	model.rotation.y = lerp_angle(model.rotation.y, facing, delta * 5.0)
	offset.y = 0.0
	var distance := offset.length()
	if state == State.STILL:
		_neck.rotation.x = lerpf(_neck.rotation.x, -0.18, delta * 2.0)
		_attack_timer -= delta
		if distance < REACH + 6.0 and distance > 4.0 and _attack_timer <= 0.0:
			state = State.TELEGRAPH
			_state_time = 0.0
			_impact = tank.global_position + tank.velocity * 0.28
			_impact.y = Course.height_at(_impact)
			Sfx.play("heron_warn", global_position)
	elif state == State.TELEGRAPH:
		_neck.rotation.x = lerpf(_neck.rotation.x, -0.85, delta * 5.0)
		_eye_material.albedo_color = Palette.WHITE if fmod(_state_time, 0.14) < 0.07 else Palette.RED
		World.current.fx.marker(_impact, 3.2, maxf(TELEGRAPH_TIME - _state_time, 0.0), Palette.HOT)
		if _state_time >= TELEGRAPH_TIME:
			_attack(tank)

func _attack(tank: Tank) -> void:
	state = State.STILL
	_state_time = 0.0
	_attack_timer = 2.8
	_neck.rotation.x = 0.0
	_eye_material.albedo_color = Palette.RED
	var hit_point := tank.hit_center()
	hit_point.y = _impact.y + 0.8
	if global_position.distance_to(tank.global_position) <= REACH and tank.global_position.distance_to(_impact) <= 3.6 and not tank.dead:
		var hit := Hit.make(Hit.Kind.SHELL, 18.0, hit_point, (tank.global_position - global_position).normalized())
		hit.source = self
		tank.take_hit(hit)
		World.current.fx.beam(_neck.global_position, _impact + Vector3.UP, Palette.HOT, 0.12, 0.18)
		World.current.fx.impact_star(hit_point, 2.5, Palette.HOT)
	Sfx.play("heron_stab", global_position)

func on_damaged(hit: Hit, amount: float) -> void:
	super(hit, amount)
	if fallen or dead:
		return
	var local := model.global_transform.affine_inverse() * hit.position
	if local.y < 2.4:
		legs_hp -= amount
		if legs_hp <= 0.0:
			topple()

func topple() -> void:
	if fallen:
		return
	fallen = true
	state = State.FALLEN
	stabbable = true
	World.current.fx.debris(global_position + Vector3.UP * 2.0, 12, [Fx.Debris.METAL, Fx.Debris.PAINT], 9.0, 0.3)
	World.current.award(150, global_position, false)
	Sfx.play("heron_topple", global_position)


func on_death(hit: Hit) -> void:
	World.current.fx.spores(hit_center(), 10, 1.4)
	super(hit)
