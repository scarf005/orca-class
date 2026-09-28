class_name FpvDrone
extends Enemy
## Kamikaze quadcopter. Weaves in, hangs ahead of the tank, flashes red and whines, then dives.
## The dive commits to a predicted point, so a drift or brake makes it miss.

enum State { APPROACH, TELEGRAPH, DIVE, TUMBLE }

const TELEGRAPH_TIME := 0.6
const DIVE_SPEED := 34.0
const CRUISE_SPEED := 30.0

var state := State.APPROACH
var slot := Vector3(0, 8, 22) ## (u, height, distance ahead of the tank) it hovers at before diving.
var approach_time := 2.5
var from_behind := false
var _state_time := 0.0
var _dive_dir := Vector3.ZERO
var _light: MeshInstance3D
var _rotors: Array[Node3D] = []
var _buzz: AudioStreamPlayer3D
var _phase := randf() * TAU


func _init() -> void:
	super()
	max_hp = 6.0
	hp = 6.0
	radius = 0.9
	flying = true
	interceptable = true
	grabbable = true
	score = 150
	death_radius = 1.4
	debris_colors = [Palette.INK, Palette.SLATE, Palette.BUTTER]
	weakness = {Hit.Kind.BLAST: 1.5, Hit.Kind.FIRE: 2.0}


func build() -> void:
	var b := LowPoly.new()
	# X frame, battery, warhead.
	b.box(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3.ZERO), Vector3(1.5, 0.08, 0.14), Palette.INK)
	b.box(Transform3D(Basis(Vector3.UP, -PI * 0.25), Vector3.ZERO), Vector3(1.5, 0.08, 0.14), Palette.INK)
	b.box(Transform3D(Basis(), Vector3(0, 0.12, 0.05)), Vector3(0.3, 0.16, 0.5), Palette.BUTTER)
	b.tube(Transform3D(Basis(), Vector3(0, -0.2, -0.35)), 0.12, 0.7, 6, Palette.OCHRE, 0.08)
	b.box(Transform3D(Basis(), Vector3(0, 0.05, -0.32)), Vector3(0.18, 0.18, 0.14), Palette.SLATE)
	var body := MeshInstance3D.new()
	body.mesh = b.mesh()
	model.add_child(body)
	for i in 4:
		var angle := PI * 0.25 + i * PI * 0.5
		var rotor := MeshInstance3D.new()
		var r := LowPoly.new()
		r.glow = true
		r.prism(Transform3D(), 0.38, 0.02, 6, Palette.MIST)
		rotor.mesh = r.mesh()
		rotor.position = Vector3(cos(angle), 0.08, sin(angle)) * 0.53
		rotor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.add_child(rotor)
		_rotors.append(rotor)
	_light = MeshInstance3D.new()
	var l := LowPoly.new()
	l.glow = true
	l.box(Transform3D(), Vector3(0.12, 0.12, 0.05), Color.WHITE)
	_light.mesh = l.mesh()
	_light.position = Vector3(0, 0.05, -0.4)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Palette.SKY
	_light.material_override = material
	model.add_child(_light)
	_buzz = Sfx.loop("buzz", self, -8.0)
	if _buzz:
		_buzz.pitch_scale = randf_range(0.9, 1.15)


func behave(delta: float) -> void:
	_state_time += delta
	for rotor in _rotors:
		rotor.rotation.y += delta * 60.0
	var tank := player()
	if tank == null:
		return
	if is_staggered() and state != State.DIVE:
		_tumble(delta)
		return
	match state:
		State.APPROACH:
			var world := World.current
			var target: Vector3
			if world.rail.mode == Rail.Mode.ARENA:
				# No rail to pace: circle in at hover distance from wherever the tank is.
				var away := global_position - tank.global_position
				away.y = 0.0
				target = tank.global_position + away.normalized().rotated(Vector3.UP, 0.4 * delta) * absf(slot.z)
				target.y = Course.height_at(target) + 7.0 + sin(age * 3.1 + _phase) * 0.8
			else:
				var d := world.rail.d + tank.course_offset + slot.z
				target = Course.to_world(d, slot.x + sin(age * 2.3 + _phase) * 2.5, 0.0)
				target.y = Course.height(d, slot.x) + slot.y + sin(age * 3.1 + _phase) * 0.8
			_steer(target, CRUISE_SPEED, 45.0, delta)
			model.look_at(global_position + (tank.global_position - global_position) * Vector3(1, 0, 1) + Vector3(0.001, 0, 0), Vector3.UP)
			if _state_time > approach_time and global_position.distance_to(tank.global_position) < 60.0:
				_set_state(State.TELEGRAPH)
				(_light.material_override as StandardMaterial3D).albedo_color = Palette.RED
				if _buzz:
					_buzz.pitch_scale *= 1.35
				Sfx.play("dive", global_position, -4.0, randf_range(0.9, 1.1))
		State.TELEGRAPH:
			velocity = velocity.move_toward(Vector3.ZERO, 40.0 * delta)
			global_position += velocity * delta + Vector3.UP * sin(_state_time * 40.0) * 0.02
			model.look_at(tank.global_position + Vector3.UP, Vector3.UP)
			_light.visible = fmod(_state_time, 0.12) < 0.07
			if _state_time >= TELEGRAPH_TIME:
				_light.visible = true
				var lead := tank.global_position + Vector3.UP * 1.2 + tank.velocity * 0.45
				_dive_dir = (lead - global_position).normalized()
				_set_state(State.DIVE)
		State.DIVE:
			# Commits to its line with only a little steering, so dodges work.
			var to_tank := (tank.hit_center() - global_position).normalized()
			_dive_dir = _dive_dir.slerp(to_tank, clampf(0.6 * delta, 0.0, 1.0))
			global_position += _dive_dir * DIVE_SPEED * delta
			model.look_at(global_position + _dive_dir, Vector3.UP if absf(_dive_dir.y) < 0.95 else Vector3.BACK)
			if tank.hit_center().distance_to(global_position) < tank.radius + 0.8 and not tank.dead:
				var boom := Hit.make(Hit.Kind.BLAST, 14.0, global_position, _dive_dir)
				boom.source = self
				tank.take_hit(boom)
				_explode()
			elif global_position.y < Course.height_at(global_position) + 0.3 or _state_time > 3.0:
				World.current.blast(global_position, 3.0, 8.0, Team.ENEMY)
				despawn()
		State.TUMBLE:
			_tumble(delta)


func _tumble(delta: float) -> void:
	velocity.y -= 18.0 * delta
	global_position += velocity * delta
	model.rotate_x(delta * 9.0)
	if global_position.y < Course.height_at(global_position):
		die(Hit.make(Hit.Kind.RAM, 99.0, global_position))


func _steer(target: Vector3, max_speed: float, accel: float, delta: float) -> void:
	var desired := (target - global_position)
	desired = desired.limit_length(max_speed) if desired.length() > 1.0 else desired * 2.0
	velocity = velocity.move_toward(desired, accel * delta)
	global_position += velocity * delta


func _set_state(value: State) -> void:
	state = value
	_state_time = 0.0


func interrupt() -> void:
	super()
	if state == State.TELEGRAPH:
		_set_state(State.APPROACH)
		(_light.material_override as StandardMaterial3D).albedo_color = Palette.SKY


## Blows up on contact without scoring a kill for the player.
func _explode() -> void:
	World.current.fx.explosion(global_position, 1.6)
	Sfx.play("blast_small", global_position)
	despawn()
