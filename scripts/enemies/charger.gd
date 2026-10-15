class_name Charger
extends Enemy
## Rams down one committed line. It stalks the tank, paws the ground along the lane it has locked, then
## bolts down it: take the hit and it is spent; sidestep and it overshoots and stands winded, open to a
## shot, before it stalks again. Subclasses give it a body and its numbers.

enum State { STALK, WIND, CHARGE, WINDED }

const LANE_MARKERS := 6
const LANE_SPACING := 8.0
const CHARGE_TIME := 1.6 ## A charge ends this long after it starts, hit or miss.
const WINDED_TIME := 2.0

var walk_speed := 12.0
var charge_speed := 36.0
var wind_time := 0.9
var charge_range := 42.0 ## Distance at which it locks a lane.
var ram_damage := 24.0
var hover := 0.0 ## Height of its body over the ground.
var state := State.STALK
var _state_time := 0.0
var _dir := Vector3.ZERO
var _paw := 0.0


func behave(delta: float) -> void:
	var tank := player()
	if tank == null or tank.dead:
		return
	_state_time += delta
	if is_staggered():
		if state != State.WINDED:
			_set_state(State.WINDED)
		return
	var toward := tank.global_position - global_position
	toward.y = 0.0
	var previous := global_position
	match state:
		State.STALK:
			_step(toward.normalized() * walk_speed * delta)
			if toward.length() < charge_range:
				_lock(tank)
		State.WIND:
			_paw -= delta
			if _paw <= 0.0:
				_paw = 0.18
				World.current.fx.dust(global_position, 3, 1.2, Palette.STRAW)
			if _state_time >= wind_time * Game.telegraph_scale():
				_set_state(State.CHARGE)
		State.CHARGE:
			_step(_dir * charge_speed * delta)
			if randf() < delta * 15.0:
				World.current.fx.dust(global_position, 2, 1.4, Palette.STRAW)
			var closest := Geometry3D.get_closest_point_to_segment(tank.global_position, previous, global_position)
			if closest.distance_to(tank.global_position) < tank.radius + radius:
				_ram(tank)
			elif _state_time >= CHARGE_TIME:
				_set_state(State.WINDED)
		State.WINDED:
			if _state_time >= WINDED_TIME:
				_set_state(State.STALK)


## Locks the lane on where the tank will be when the charge arrives, and marks it.
func _lock(tank: Tank) -> void:
	_dir = (FpvDrone.intercept(global_position, tank.global_position, tank.velocity, charge_speed) - global_position) * Vector3(1, 0, 1)
	_dir = _dir.normalized()
	model.rotation.y = atan2(-_dir.x, -_dir.z)
	_set_state(State.WIND)
	var window := wind_time * Game.telegraph_scale()
	for i in LANE_MARKERS:
		var reach := LANE_SPACING + i * LANE_SPACING
		World.current.fx.marker(global_position + _dir * reach, 2.2, window + reach / charge_speed, Palette.HOT)
	Sfx.play("warn", global_position)


func _step(motion: Vector3) -> void:
	global_position += motion
	global_position.y = Course.height_at(global_position) + hover
	if motion.length_squared() > 0.0001:
		model.rotation.y = atan2(-motion.x, -motion.z)
	model.rotation.z = sin(age * 18.0) * 0.06


func _ram(tank: Tank) -> void:
	var hit := Hit.make(Hit.Kind.RAM, ram_damage, tank.hit_center(), _dir)
	hit.source = self
	tank.take_hit(hit)
	var world := World.current
	world.fx.shatter(visual_bounds(), debris, _dir)
	world.fx.impact_star(hit_center(), 2.4, Palette.WHITE)
	Sfx.play("impact", global_position)
	despawn()


func _set_state(value: State) -> void:
	state = value
	_state_time = 0.0


func telegraphing() -> bool:
	return state == State.WIND


func interrupt() -> void:
	super()
	_set_state(State.WINDED)
