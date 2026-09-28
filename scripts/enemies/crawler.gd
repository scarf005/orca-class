class_name Crawler
extends Enemy
## Fungal crawler. Scuttles at the tank, leaps the last stretch, then swells and bursts into a
## spore cloud. Burning or crushing it first stops the burst.

enum State { RUN, LEAP, SWELL }

const RUN_SPEED := 10.0
const SWELL_TIME := 0.75

var state := State.RUN
var _state_time := 0.0
var _leap_velocity := Vector3.ZERO
var _legs: Array[Node3D] = []
var _body: MeshInstance3D
var _phase := randf() * TAU


func _init() -> void:
	super()
	max_hp = 14.0
	hp = 14.0
	radius = 1.0
	center_height = 0.8
	grabbable = true
	score = 120
	death_radius = 1.2
	debris_colors = [Palette.FUNGUS, Palette.LILAC, Palette.CREAM]
	weakness = {Hit.Kind.FIRE: 3.0, Hit.Kind.BLAST: 1.3, Hit.Kind.TAIL: 2.0}


func build() -> void:
	var b := LowPoly.new()
	b.blob(Transform3D(Basis().scaled(Vector3(1.0, 0.75, 1.2)), Vector3(0, 0.8, 0)), 0.8, Palette.MAUVE, 1, 0.3, randi())
	b.blob(Transform3D(Basis(), Vector3(0, 1.2, 0.2)), 0.5, Palette.FUNGUS, 0, 0.35, randi())
	b.glow = true
	for i in 5:
		var angle := randf() * TAU
		b.blob(Transform3D(Basis(), Vector3(cos(angle) * 0.6, 0.9 + randf() * 0.4, sin(angle) * 0.6)), 0.14, Palette.BLUSH)
	_body = MeshInstance3D.new()
	_body.mesh = b.mesh()
	model.add_child(_body)
	for i in 6:
		var leg := Node3D.new()
		var side := -1.0 if i < 3 else 1.0
		leg.position = Vector3(0.5 * side, 0.7, -0.5 + (i % 3) * 0.5)
		leg.rotation.y = side * (PI * 0.5) + ((i % 3) - 1) * 0.5 * side
		var l := LowPoly.new()
		l.prism(Transform3D(Basis(Vector3.BACK, -side * 1.0), Vector3.ZERO), 0.07, 1.0, 4, Palette.CREAM, 0.03)
		var mesh := MeshInstance3D.new()
		mesh.mesh = l.mesh()
		leg.add_child(mesh)
		model.add_child(leg)
		_legs.append(leg)
	global_position.y = Course.height_at(global_position)


func behave(delta: float) -> void:
	_state_time += delta
	var tank := player()
	if tank == null:
		return
	var to_tank := tank.global_position - global_position
	to_tank.y = 0.0
	var distance := to_tank.length()
	match state:
		State.RUN:
			if is_staggered():
				return
			var dir := to_tank.normalized()
			# Aim a little ahead of the tank; it keeps scrolling forward.
			var lead := tank.global_position + tank.velocity * 0.6 - global_position
			lead.y = 0.0
			dir = lead.normalized()
			dir = dir.rotated(Vector3.UP, sin(age * 5.0 + _phase) * 0.35)
			global_position += dir * RUN_SPEED * delta
			global_position.y = Course.height_at(global_position)
			model.rotation.y = atan2(-dir.x, -dir.z)
			for i in _legs.size():
				_legs[i].rotation.x = sin(age * 22.0 + i * 1.7) * 0.5
			if distance < 13.0 and distance > 6.0 and randf() < delta * 1.5:
				_leap(tank)
			elif distance < 5.5:
				_start_swell()
			if distance < tank.radius + 0.9 and tank.velocity.length() > 3.0:
				# Crushed under the tracks.
				die(Hit.make(Hit.Kind.RAM, 999.0, global_position))
		State.LEAP:
			_leap_velocity.y -= 24.0 * delta
			global_position += _leap_velocity * delta
			var ground := Course.height_at(global_position)
			if global_position.y <= ground:
				global_position.y = ground
				World.current.fx.dust(global_position, 4, 1.0, Palette.OCHRE)
				_start_swell()
		State.SWELL:
			var k := _state_time / SWELL_TIME
			_body.scale = Vector3.ONE * (1.0 + k * 0.7 + sin(_state_time * 40.0) * 0.08)
			if fmod(_state_time, 0.14) < 0.07:
				flash()
			if is_staggered() and burning <= 0.0:
				_state_time = 0.0
				state = State.RUN
				_body.scale = Vector3.ONE
			elif _state_time >= SWELL_TIME:
				_burst()


func _leap(tank: Tank) -> void:
	state = State.LEAP
	_state_time = 0.0
	var target := tank.global_position + tank.velocity * 0.7
	var time := 0.7
	_leap_velocity = (target - global_position) / time
	_leap_velocity.y = 0.5 * 24.0 * time
	Sfx.play("squelch", global_position, -4.0, 1.3)


func _start_swell() -> void:
	state = State.SWELL
	_state_time = 0.0
	Sfx.play("squelch", global_position, 0.0, 0.8)


func _burst() -> void:
	var world := World.current
	var center := hit_center()
	world.fx.spores(center, 24, 2.5)
	world.fx.shockwave(center, 5.0, Palette.FUNGUS)
	Sfx.play("spore", center)
	var tank := player()
	if tank and tank.hit_center().distance_to(center) < 4.5:
		var hit := Hit.make(Hit.Kind.SPORE, 12.0, center, (tank.global_position - center).normalized())
		hit.source = self
		tank.take_hit(hit)
	Hazard.spawn(center, 3.2, 2.2, 6.0)
	despawn()


func on_death(hit: Hit) -> void:
	# Killed before bursting: a harmless puff, and it scores.
	var world := World.current
	world.fx.spores(hit_center(), 10, 1.0)
	world.fx.debris(hit_center(), 6, debris_colors, 6.0, 0.25)
	world.award(score, hit_center(), true)
	world.kill_style(hit, self)
	Sfx.play("squelch", hit_center(), 0.0, 1.1)
	if hit and hit.kind == Hit.Kind.FIRE:
		world.fx.spawn(Fx.Kind.FLAME, hit_center(), Vector3.UP * 3.0, 0.5, 1.2, Palette.PEACH)
	if not drop.is_empty():
		world.spawn_pickup(drop, hit_center() + Vector3.UP)
