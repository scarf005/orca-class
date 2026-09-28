class_name Helicopter
extends Enemy
## Ordinary attack helicopter: paces the rail, telegraphs gun bursts and rocket pairs, then leaves.

const KEEP_AHEAD := 55.0
const PACE_TIME := 12.0

var _rotor := Node3D.new()
var _tail_rotor := Node3D.new()
var _chin := Node3D.new()
var _lane := 0.0
var _height := 13.0
var _attack_timer := 1.8
var _telegraph := 0.0
var _burst := 0
var _shot_timer := 0.0
var _rockets := false
var _hard := false


func _init() -> void:
	super()
	max_hp = 16.0
	hp = max_hp
	radius = 2.5
	flying = true
	score = 650
	wreck_on_death = true
	weakness = {Hit.Kind.FRAGMENT: 1.5, Hit.Kind.BLAST: 1.4}
	debris = [Fx.Debris.ARMOR, Fx.Debris.METAL, Fx.Debris.GLASS]


func build() -> void:
	_hard = Game.difficulty == Game.Difficulty.HARD
	var slot: Vector3 = get_meta("slot", Vector3(0, 13, 55))
	_lane = slot.x
	_height = maxf(slot.y, 10.0)
	var b := LowPoly.new()
	# Narrow tandem fuselage, stepped canopies, tail boom and fin.
	b.box(Transform3D(Basis(), Vector3(0, 0, 0.2)), Vector3(1.5, 1.7, 5.4), Palette.SLATE)
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.55, -2.6)), Vector3(1.3, 1.1, 1.8), Palette.SLATE)
	b.box(Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, -0.35, -2.9)), Vector3(1.2, 0.8, 1.2), Palette.DUSK)
	b.glow = true
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 1.0, -2.3)), Vector3(1.1, 0.5, 1.2), Palette.PERIWINKLE)
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, 1.2, -0.9)), Vector3(1.0, 0.5, 1.1), Palette.PERIWINKLE)
	b.glow = false
	b.box(Transform3D(Basis(), Vector3(0, 0.3, 5.2)), Vector3(0.6, 0.6, 5.2), Palette.SLATE)
	b.box(Transform3D(Basis(), Vector3(0, 1.3, 7.5)), Vector3(0.2, 2.0, 1.2), Palette.DUSK)
	b.box(Transform3D(Basis(), Vector3(0, 0.4, 7.3)), Vector3(2.2, 0.1, 0.8), Palette.DUSK)
	# Engine nacelles and exhausts on the shoulders.
	for x in [-0.95, 0.95]:
		b.box(Transform3D(Basis(), Vector3(x, 1.1, 0.4)), Vector3(0.6, 0.7, 2.4), Palette.STONE)
		b.box(Transform3D(Basis(), Vector3(x * 1.1, 1.1, 1.7)), Vector3(0.5, 0.5, 0.3), Palette.INK)
	# Stub wings.
	b.box(Transform3D(Basis(), Vector3(0, -0.1, 0.3)), Vector3(5.6, 0.18, 1.2), Palette.DUSK)
	b.box(Transform3D(Basis(), Vector3(0, 1.75, 0.2)), Vector3(0.4, 0.5, 0.4), Palette.INK)
	var body := MeshInstance3D.new()
	body.mesh = b.mesh()
	model.add_child(body)
	_rotor.position = Vector3(0, 2.05, 0.2)
	model.add_child(_rotor)
	var r := LowPoly.new()
	for i in 5:
		r.box(Transform3D(Basis(Vector3.UP, TAU * i / 5.0), Vector3(0, 0, 0)).translated_local(Vector3(3.7, 0, 0)), Vector3(7.4, 0.06, 0.45), Palette.INK)
	var rotor_mesh := MeshInstance3D.new()
	rotor_mesh.mesh = r.mesh()
	_rotor.add_child(rotor_mesh)
	_tail_rotor.position = Vector3(0.2, 1.4, 7.6)
	model.add_child(_tail_rotor)
	var tr_mesh := MeshInstance3D.new()
	var t := LowPoly.new()
	for i in 4:
		t.box(Transform3D(Basis(Vector3.RIGHT, TAU * i / 4.0), Vector3.ZERO).translated_local(Vector3(0, 0.7, 0)), Vector3(0.05, 1.4, 0.25), Palette.INK)
	tr_mesh.mesh = t.mesh()
	_tail_rotor.add_child(tr_mesh)
	# Chin gun turret.
	_chin.position = Vector3(0, -0.85, -2.7)
	model.add_child(_chin)
	var c := LowPoly.new()
	c.box(Transform3D(), Vector3(0.5, 0.4, 0.5), Palette.INK)
	c.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(0, 0, -0.2)), 0.06, 1.5, 6, Palette.INK)
	var chin_mesh := MeshInstance3D.new()
	chin_mesh.mesh = c.mesh()
	_chin.add_child(chin_mesh)
	for side in [-1.0, 1.0]:
		var pod := MeshInstance3D.new()
		pod.mesh = _pod_mesh()
		pod.position = Vector3(side * 2.6, -0.4, 0.2)
		model.add_child(pod)
	pop_parts = [_rotor, _tail_rotor]
	Sfx.loop("rotor", self, -5.0)


func _pod_mesh() -> Mesh:
	var b := LowPoly.new()
	b.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(0, 0, 1.0)), 0.42, 2.0, 7, Palette.MOSS)
	b.glow = true
	for i in 6:
		var angle := TAU * i / 6.0
		b.box(Transform3D(Basis(), Vector3(cos(angle) * 0.24, sin(angle) * 0.24, -1.01)), Vector3(0.12, 0.12, 0.02), Palette.CORAL)
	return b.mesh()


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	var best := -1.0
	# Preserve the original airframe's long tail and outboard rocket-pod hit areas.
	for sphere: Vector4 in [Vector4(0, 0.2, -1.2, 1.6), Vector4(0, 0.2, 1.4, 1.6), Vector4(0, 0.3, 4.5, 0.9), Vector4(0, 1.4, 7.6, 0.9), Vector4(-2.6, -0.4, 0.2, 0.8), Vector4(2.6, -0.4, 0.2, 0.8), Vector4(0, 1.9, 0.2, 0.7)]:
		var center := model.to_global(Vector3(sphere.x, sphere.y, sphere.z))
		var t := Entity.segment_sphere(from, to, center, sphere.w + extra_radius)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


func behave(delta: float) -> void:
	_rotor.rotation.y += delta * 28.0
	_tail_rotor.rotation.x += delta * 50.0
	var world := World.current
	var tank := player()
	if tank == null or tank.dead:
		return
	var course := Course.to_course(global_position)
	if world.rail.mode != Rail.Mode.ARENA:
		var target_d := world.rail.d + tank.course_offset + KEEP_AHEAD
		var speed := clampf(world.rail.speed + (target_d - course.x) * 1.2, 0.0, world.rail.speed + 20.0) if age < PACE_TIME else 4.0
		course.x += speed * delta
		course.y = lerpf(course.y, _lane + sin(age * 0.8) * 4.0, delta * 1.8)
		global_position = Course.to_world(course.x, course.y, global_position.y)
	var altitude := Course.height_at(global_position) + _height + sin(age * 1.7) * 0.8
	global_position.y = lerpf(global_position.y, altitude - (2.0 if is_staggered() else 0.0), delta * 2.0)
	var to_tank := tank.hit_center() - global_position
	model.rotation.y = lerp_angle(model.rotation.y, atan2(-to_tank.x, -to_tank.z), delta * 3.0)
	model.rotation.z = sin(age * 0.8) * 0.12
	_chin.look_at(tank.hit_center(), Vector3.UP)
	if age > PACE_TIME + 12.0:
		despawn()
		return
	if is_staggered():
		return
	if _telegraph > 0.0:
		_telegraph -= delta
		world.fx.beam(_chin.global_position, tank.hit_center(), Palette.CORAL, 0.035, 0.05)
		if _telegraph <= 0.0:
			_burst = 2 if _rockets else 6
			_shot_timer = 0.0
	elif _burst > 0:
		_shot_timer -= delta
		if _shot_timer <= 0.0:
			_fire(tank)
			_burst -= 1
			_shot_timer = 0.22 if _rockets else 0.12
			if _burst == 0:
				_rockets = not _rockets
				_attack_timer = 2.4 if _hard else 3.2
	else:
		_attack_timer -= delta
		if _attack_timer <= 0.0 and to_tank.length() < 130.0:
			_telegraph = 0.8
			Sfx.play("warn", global_position, -4.0)


func _fire(tank: Tank) -> void:
	var from := _chin.global_position
	if _rockets:
		from = model.to_global(Vector3(-2.6 if _burst % 2 == 0 else 2.6, -0.4, -0.8))
	var target := tank.hit_center() + tank.velocity * (from.distance_to(tank.hit_center()) / (55.0 if _rockets else 100.0)) * 0.6
	var shot := fire_at("rocket" if _rockets else "orb", from, target, 55.0 if _rockets else 100.0, 0.0 if _rockets else 4.0)
	shot.hit.caliber = 30
	if _rockets:
		shot.hit.kind = Hit.Kind.SHELL
		shot.blast_radius = 2.6
		shot.blast_damage = 9.0
		shot.interceptable = true
		shot.intercept_hp = 0.55
		shot.trail = Projectile.ROCKET_SMOKE
		shot.life = 4.0
	World.current.fx.spawn(Fx.Kind.FLAME, from, Vector3.ZERO, 0.08, 0.5, Palette.CORAL)
	Sfx.play("launch" if _rockets else "enemy_gun", from, -4.0)


func interrupt() -> void:
	super()
	_telegraph = 0.0
	_burst = 0
	_attack_timer = 2.0
