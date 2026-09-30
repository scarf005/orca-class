class_name HeronWalker
extends Enemy
## A tall white stilt walker in the paddies. It freezes until close, then plants a beak-lance circle.
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
	radius = 1.3
	center_height = 5.7
	stabbable = true
	wreck_on_death = true
	score = 500
	debris = [Fx.Debris.METAL, Fx.Debris.PAINT]
	weakness = {Hit.Kind.TAIL: 1.5}

func build() -> void:
	# The legs and neck are deliberately long and thin: the silhouette is roughly 2.5x the tank's
	# mounted height, while the body and continuous stilt hit volumes remain easy to read.
	var body := LowPoly.new()
	body.box(Transform3D(Basis(), Vector3(0, 5.98, 0)), Vector3(1.7, 1.82, 1.3), Palette.CREAM, Palette.PEACH)
	body.box(Transform3D(Basis(), Vector3(0, 7.09, -0.15)), Vector3(1.2, 1.04, 0.9), Palette.SKY)
	body.gable(Transform3D(Basis(), Vector3(0, 7.74, 0)), Vector3(1.4, 0.39, 1.0), Palette.MAUVE, Palette.LILAC)
	var body_mesh := MeshInstance3D.new()
	body_mesh.mesh = body.mesh()
	model.add_child(body_mesh)
	_neck.position = Vector3(0, 7.54, -0.35)
	model.add_child(_neck)
	var neck_mesh := LowPoly.new()
	neck_mesh.prism(Transform3D(), 0.22, 2.99, 6, Palette.CREAM)
	neck_mesh.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(0, 2.93, 0)), 0.08, 1.56, 5, Palette.OCHRE)
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
		leg_poly.prism(Transform3D(), 0.18, 5.2, 5, Palette.SLATE)
		leg_poly.prism(Transform3D(Basis(), Vector3(0, 5.0, 0)), 0.14, 1.95, 5, Palette.CORAL)
		leg_poly.box(Transform3D(Basis(), Vector3(0, 0.05, -0.3)), Vector3(0.55, 0.16, 0.9), Palette.INK)
		var leg_mesh := MeshInstance3D.new()
		leg_mesh.mesh = leg_poly.mesh()
		leg.add_child(leg_mesh)
		model.add_child(leg)
		_legs.append(leg)
	global_position.y = Course.height_at(global_position)

## Hit volumes follow the articulated model, so low rounds can actually break the stilt legs and a
## fallen heron presents its lowered body rather than an obsolete upright sphere.
func hit_center() -> Vector3:
	return model.to_global(Vector3(0, 6.4, 0)) if is_instance_valid(model) else super.hit_center()

func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	var best := -1.0
	var local_from := model.to_local(from)
	var local_to := model.to_local(to)
	# Each stilt is a continuous thin ellipsoid, not a few disconnected hit dots. This keeps the
	# visible lower leg and upper joint shootable at every height, including after the model falls.
	for side in [-1.0, 1.0]:
		var center := Vector3(side * 0.55, 2.95, 0.05)
		var extent := Vector3(0.38, 2.95, 0.38) + Vector3.ONE * extra_radius
		var a := (local_from - center) / extent
		var b := (local_to - center) / extent
		var t := Entity.segment_sphere(a, b, Vector3.ZERO, 1.0)
		if t >= 0.0:
			t *= from.distance_to(to) / maxf(a.distance_to(b), 0.0001)
			if best < 0.0 or t < best:
				best = t
	for part: Array in [[Vector3(0, 6.4, 0), 1.15]]:
		var center: Vector3 = model.global_transform * (part[0] as Vector3)
		var t := Entity.segment_sphere(from, to, center, float(part[1]) + extra_radius)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	# The neck is articulated under _neck, so its warning pose and a fallen pose share the same
	# collision volume.
	var neck_from := _neck.to_global(Vector3(0, 0, 0))
	var neck_to := _neck.to_global(Vector3(0, 2.99, 0))
	var neck_axis := neck_to - neck_from
	var neck_steps := maxi(1, ceili(neck_axis.length() / 0.35))
	for i in neck_steps + 1:
		var center := neck_from.lerp(neck_to, float(i) / neck_steps)
		var t := Entity.segment_sphere(from, to, center, 0.32 + extra_radius)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	var beak_from := _neck.to_global(Vector3(0, 2.93, 0))
	var beak_to := _neck.to_global(Vector3(0, 2.93, -1.56))
	for i in 6:
		var center := beak_from.lerp(beak_to, float(i) / 5.0)
		var t := Entity.segment_sphere(from, to, center, 0.2 + extra_radius)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best

func behave(delta: float) -> void:
	_state_time += delta
	var tank := player()
	if tank == null:
		return
	if fallen:
		model.rotation.z = lerpf(model.rotation.z, PI * 0.5, 1.0 - exp(-6.0 * delta))
		model.position.y = lerpf(model.position.y, 0.85, 1.0 - exp(-6.0 * delta))
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
	var local := model.global_transform.affine_inverse() * hit.position
	super(hit, amount)
	if fallen or dead:
		return
	if local.y < 5.9 and absf(absf(local.x) - 0.55) < 0.4 and absf(local.z - 0.05) < 0.4:
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
