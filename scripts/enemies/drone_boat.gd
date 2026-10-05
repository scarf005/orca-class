class_name DroneBoat
extends Enemy
## Low twin-sponson explosive skiff: a weaving wake, accelerating bow flashes, then a committed ram.

enum State { APPROACH, TELEGRAPH, RAM }

const WARN_TIME := 1.0
const SPEED := 32.0
const RAM_SPEED := 48.0

var state := State.APPROACH
var _wind := 0.0
var _ram_left := 3.0
var _direction := Vector3.ZERO
var _wake_left := 0.0
var _beep_left := 0.0
var _light := MeshInstance3D.new()
var _motor: AudioStreamPlayer3D
var _phase := randf() * TAU


func _init() -> void:
	super()
	max_hp = Armament.GUNS[8].damage * 2.0
	hp = max_hp
	radius = 1.1
	center_height = 0.35
	stabbable = true
	score = 200
	debris = [Fx.Debris.METAL, Fx.Debris.PAINT]


func build() -> void:
	var b := LowPoly.new()
	# Two long tapered pontoons, a low bridging deck and an exposed bow charge.
	for side in [-1.0, 1.0]:
		b.frustum(Transform3D(Basis(), Vector3(side * 0.65, -0.15, 0)), Vector2(0.45, 3.0), Vector2(0.3, 2.2), 0.45, Palette.INK, Palette.CORAL, Vector2(0, 0.35))
	b.frustum(Transform3D(Basis(), Vector3(0, 0.15, 0.3)), Vector2(1.5, 1.5), Vector2(1.0, 1.0), 0.25, Palette.SLATE)
	b.tube(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.4, -0.8)), 0.25, 0.8, 6, Palette.OCHRE)
	b.prism(Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0.3, 0.4, 0.8)), 0.025, 0.8, 4, Palette.INK)
	var body := MeshInstance3D.new()
	body.mesh = b.mesh()
	model.add_child(body)
	var lamp := LowPoly.new()
	lamp.glow = true
	lamp.box(Transform3D(), Vector3(0.35, 0.15, 0.08), Palette.RED)
	_light.mesh = lamp.mesh()
	_light.position = Vector3(0, 0.45, -1.25)
	model.add_child(_light)
	_motor = Sfx.loop("boat_motor", self, -8.0)


func flash_period() -> float:
	return lerpf(0.08, 0.4, clampf(_wind / (WARN_TIME * Game.telegraph_scale()), 0.0, 1.0))


func behave(delta: float) -> void:
	var tank := player()
	if tank == null or tank.dead or is_staggered():
		return
	var toward := tank.global_position - global_position
	toward.y = 0.0
	var previous := global_position
	match state:
		State.APPROACH:
			var weave := Course.right(Course.to_course(global_position).x) * sin(age * 3.0 + _phase) * 9.0
			global_position += (toward.normalized() * SPEED + weave) * delta
			if toward.length() < 38.0:
				state = State.TELEGRAPH
				_wind = WARN_TIME * Game.telegraph_scale()
				Sfx.play("boat_warn", global_position)
		State.TELEGRAPH:
			_wind = maxf(0.0, _wind - delta)
			_light.visible = fmod(age, flash_period()) < flash_period() * 0.5
			_beep_left -= delta
			if _beep_left <= 0.0:
				_beep_left = flash_period()
				Sfx.play("boat_warn", global_position, -4.0, 1.0 + 1.0 - _wind / (WARN_TIME * Game.telegraph_scale()))
			if _wind == 0.0:
				state = State.RAM
				_direction = (FpvDrone.intercept(global_position, tank.global_position, tank.velocity, RAM_SPEED) - global_position) * Vector3(1, 0, 1)
				_direction = _direction.normalized()
				_light.show()
		State.RAM:
			global_position += _direction * RAM_SPEED * delta
			_ram_left -= delta
			var closest := Geometry3D.get_closest_point_to_segment(tank.global_position, previous, global_position)
			if closest.distance_to(tank.global_position) < tank.radius + radius:
				var hit := Hit.make(Hit.Kind.RAM, 30.0, tank.hit_center(), _direction)
				hit.source = self
				tank.take_hit(hit)
				World.current.fx.splash(global_position, 3.0, global_position.y)
				World.current.fx.explosion(hit_center(), 2.0)
				Sfx.play("boat_break", global_position)
				despawn()
			elif _ram_left <= 0.0:
				despawn()
	var surface := Water.surface_at(global_position)
	global_position.y = (surface if surface > -INF else Course.height_at(global_position)) + sin(age * 5.0) * 0.06
	var heading := global_position - previous
	heading.y = 0.0
	if heading.length_squared() > 0.001:
		model.rotation.y = atan2(-heading.x, -heading.z)
	model.rotation.z = sin(age * 3.0 + _phase) * 0.12
	_wake_left -= delta
	if _wake_left <= 0.0:
		_wake_left = 0.09
		World.current.fx.wake(global_position, heading / maxf(delta, 0.001), 1.4, global_position.y)
	if _motor:
		_motor.pitch_scale = 1.4 if state == State.RAM else 0.8


func telegraphing() -> bool:
	return state == State.TELEGRAPH


func interrupt() -> void:
	super()
	state = State.APPROACH
	_light.show()


func on_death(hit: Hit) -> void:
	World.current.fx.splash(global_position, 2.5, global_position.y)
	Sfx.play("boat_break", global_position)
	super(hit)
