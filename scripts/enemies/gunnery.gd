class_name Gunnery
## Aim points for ground gunners that snipe the tank's roof sensors.


## The tank's exposed sensor (the RWS if fitted, else the FCS, else the hull's middle) moved ahead
## by `tank.velocity` for the time a round at `speed` takes to reach it from `from`.
static var TAIL_CHANCE := 0.35 ## Share of bursts a gunner puts on the tail while it has one (tuned live in the duel mode).


static func _sensor(tank: Tank, at_tail := false) -> Vector3:
	var sensor := tank.hit_center()
	if at_tail and not tank.tail.destroyed:
		sensor = tank.tail.claw_position()
	elif tank.modules.laser_online():
		sensor = tank.model.sensor_position("laser")
	elif tank.modules.state("fcs") != TankModules.State.DESTROYED:
		sensor = tank.model.sensor_position("fcs")
	return sensor


static func sensor_lead(tank: Tank, from: Vector3, speed: float, at_tail := false) -> Vector3:
	var sensor := _sensor(tank, at_tail)
	var aim := sensor
	for _i in 4:
		aim = sensor + tank.velocity * from.distance_to(aim) / speed
	return aim


## Aircraft forecast observed ground motion, never future input or terrain-induced vertical velocity.
## `delay` is the time before firing (the sweep's warning and travel); `life` bounds flight time.
static func ground_lead(tank: Tank, from: Vector3, speed: float, options := {}) -> Vector3:
	var delay: float = options.get("delay", 0.0)
	var life: float = options.get("life", 3.0)
	var offset := _sensor(tank) - tank.global_position
	var observation := _observation(tank)
	var low := 0.0
	var high := life
	if speed <= 0.0 or from.distance_to(_planar_position(tank, delay + high, observation) + offset) > speed * high:
		return ground_position(tank, delay, observation) + offset
	# Solve the planar path first; terrain sampling is needed only to refine the resulting intercept.
	for _i in 12:
		var flight := (low + high) * 0.5
		var target := _planar_position(tank, delay + flight, observation) + offset
		if from.distance_to(target) > speed * flight:
			low = flight
		else:
			high = flight
	for _i in 2:
		high = minf(life, from.distance_to(ground_position(tank, delay + high, observation) + offset) / speed)
	return ground_position(tank, delay + high, observation) + offset


## A dash's observed speed decays at its existing rate; after it stops, no new input is assumed.
static func _dash_travel(speed: float, time: float) -> float:
	var deceleration := Tank.DASH_SPEED / Tank.DASH_TIME
	var duration := minf(time, absf(speed) / deceleration)
	return speed * duration - signf(speed) * deceleration * duration * duration * 0.5


static func _observation(tank: Tank) -> Dictionary:
	return {"motion": Vector3(tank.velocity.x, 0.0, tank.velocity.z), "course": Course.to_course(tank.global_position), "ground": _footprint_height(tank, tank.global_position)}


static func ground_position(tank: Tank, time: float, observation := {}) -> Vector3:
	if time == 0.0 or Vector2(tank.velocity.x, tank.velocity.z).is_zero_approx():
		return tank.global_position
	if observation.is_empty():
		observation = _observation(tank)
	var p := _planar_position(tank, time, observation)
	p.y = tank.global_position.y + _footprint_height(tank, p) - float(observation.ground)
	return p


static func _planar_position(tank: Tank, time: float, observation: Dictionary) -> Vector3:
	var motion: Vector3 = observation.motion
	if time == 0.0 or motion.is_zero_approx():
		return tank.global_position
	var rail := World.current.rail
	var p := tank.global_position
	var sideways_dash := tank.is_dashing() and tank._drift_dir != 0.0
	if rail.mode == Rail.Mode.ARENA:
		p += motion.normalized() * _dash_travel(motion.length(), time) if sideways_dash else motion * time
		var center := Course.to_world(Course.ARENA_CENTER_D, 0.0)
		var radial := Vector3(p.x - center.x, 0.0, p.z - center.z).limit_length(Course.ARENA_RADIUS - 6.0)
		p = center + radial
	else:
		var course: Vector2 = observation.course
		var lateral := motion.dot(Course.right(course.x))
		var forward := motion.dot(Course.forward(course.x)) / maxf(1.0 - Course._curvature_at(course.x) * course.y, 0.1)
		var offset := clampf(tank.course_offset + (forward - rail.speed) * time, Tank.FORWARD_LIMIT.x, Tank.FORWARD_LIMIT.y)
		var d := course.x + rail.speed * time + offset - tank.course_offset
		var u := course.y + (_dash_travel(lateral, time) if sideways_dash else lateral * time)
		u = clampf(u, -Tank.lateral_limit(d), Tank.lateral_limit(d))
		p = Course.to_world(d, u)
	p.y = tank.global_position.y
	return p


## Match the tank's four terrain samples at its current yaw, without simulating future steering.
static func _footprint_height(tank: Tank, at: Vector3) -> float:
	var forward := Vector3(-sin(tank.hull_yaw), 0.0, -cos(tank.hull_yaw))
	var right := forward.cross(Vector3.UP)
	return (Course.height_at(at + forward * 3.0) + Course.height_at(at - forward * 3.0) + Course.height_at(at + right * 1.6) + Course.height_at(at - right * 1.6)) * 0.25
