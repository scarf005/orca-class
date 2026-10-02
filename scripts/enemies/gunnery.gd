class_name Gunnery
## Aim points for ground gunners that snipe the tank's roof sensors.


## The tank's exposed sensor (the RWS if fitted, else the FCS, else the hull's middle) moved ahead
## by `tank.velocity` for the time a round at `speed` takes to reach it from `from`.
static var TAIL_CHANCE := 0.35 ## Share of bursts a gunner puts on the tail while it has one (tuned live in the duel mode).


static func sensor_lead(tank: Tank, from: Vector3, speed: float, at_tail := false) -> Vector3:
	var sensor := tank.hit_center()
	if at_tail and not tank.tail.destroyed:
		sensor = tank.tail.claw_position()
	elif tank.modules.laser_online():
		sensor = tank.model.sensor_position("laser")
	elif tank.modules.state("fcs") != TankModules.State.DESTROYED:
		sensor = tank.model.sensor_position("fcs")
	var aim := sensor
	for _i in 4:
		aim = sensor + tank.velocity * from.distance_to(aim) / speed
	return aim
