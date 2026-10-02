extends TestCase
## Ground gunners snipe the roof sensors with lead: the aim point is fixed when the telegraph ends,
## so a tank that keeps its course is hit and one that reverses after the telegraph is missed.

const STRAFE := 12.0
const RAIL_SPEED := 22.0


func _tank_moving(world: World, lateral: float) -> Tank:
	var tank := world.player
	tank.velocity = world.rail.forward() * RAIL_SPEED + tank.global_basis.x * lateral
	return tank


func _gunner(world: World, weapon: String, walker: bool, lateral := 0.0) -> Enemy:
	var enemy: Enemy = Walker.new() if walker else Ugv.new()
	enemy.set("weapon", weapon)
	enemy.position = Course.ground_at(world.rail.d + world.player.course_offset + 45.0, 4.0)
	world.add_enemy(enemy)
	enemy.set("_attack_timer", INF)
	if not walker:
		enemy.set("immobile", true) # Keeps the muzzle where the test measured it.
	_tank_moving(world, lateral)
	for _i in 120:
		enemy.behave(1.0 / 60.0) # Turret and barrel finish turning onto the tank.
	return enemy


## Closest a round comes to `target` while that point drifts with `drift`.
func _miss(round: Projectile, target: Vector3, drift: Vector3) -> float:
	var offset := round.global_position - target
	var relative := round.velocity - drift
	var t := maxf(0.0, -offset.dot(relative) / relative.length_squared())
	return (offset + relative * t).length()


## Fires a gun burst at a tank moving at `lateral` m/s, which then moves at `after` m/s once the
## telegraph is over. Returns each round's miss distance against the roof sensor it was aimed at.
func _burst(world: World, enemy: Enemy, lateral: float, after: float) -> Array[float]:
	var tank := _tank_moving(world, lateral)
	var sensor := tank.model.sensor_position("laser")
	if enemy is Ugv:
		enemy._attack()
	else:
		enemy._attack(tank)
	var drift := _tank_moving(world, after).velocity
	var before := world.projectiles.duplicate()
	var misses: Array[float] = []
	for _i in 200:
		enemy.behave(1.0 / 60.0)
		for round in world.projectiles:
			if round not in before and round.hit.source == enemy:
				before.append(round)
				misses.append(_miss(round, sensor, drift))
		if misses.size() >= 5 and enemy.get("_burst") == 0:
			break
	return misses


func _worst(misses: Array[float]) -> float:
	return misses.max() if not misses.is_empty() else INF


func _best(misses: Array[float]) -> float:
	return misses.min() if not misses.is_empty() else INF


func test_sensor_choice() -> void:
	var world := stage()
	var tank := _tank_moving(world, 0.0)
	tank.velocity = Vector3.ZERO
	var from := tank.global_position + Vector3(0, 3, -40)
	check(Gunnery.sensor_lead(tank, from, 95.0).is_equal_approx(tank.model.sensor_position("laser")), "the RWS first")
	tank.damage_module("laser", 1000.0)
	check(Gunnery.sensor_lead(tank, from, 95.0).is_equal_approx(tank.model.sensor_position("fcs")), "then the FCS")
	tank.damage_module("fcs", 1000.0)
	check(Gunnery.sensor_lead(tank, from, 95.0).is_equal_approx(tank.hit_center()), "then the hull")
	cleanup()
	world = stage("", false)
	tank = world.player
	tank.velocity = Vector3.ZERO
	check(Gunnery.sensor_lead(tank, from, 95.0).is_equal_approx(tank.model.sensor_position("fcs")), "an unfitted RWS is skipped")


func test_lead_covers_the_flight_time() -> void:
	var world := stage()
	var tank := _tank_moving(world, STRAFE)
	var from := tank.global_position + Vector3(0, 3, -50)
	var aim := Gunnery.sensor_lead(tank, from, 95.0)
	var shift := aim - tank.model.sensor_position("laser")
	check_near(shift.length() / tank.velocity.length() * 95.0, from.distance_to(aim), 0.5, "a round at its speed reaches the point as the sensor does")


func test_gunners_hit_a_tank_that_keeps_its_course() -> void:
	seed(5)
	var world := stage()
	for walker in [false, true]:
		var misses := _burst(world, _gunner(world, "gun", walker, STRAFE), STRAFE, STRAFE)
		print("%s steady: %d rounds, miss %.2f..%.2f m" % ["walker" if walker else "UGV", misses.size(), _best(misses), _worst(misses)])
		check(misses.size() >= 5, "the burst fires")
		check(_worst(misses) <= 3.0, "every round passes within 3 m of the sensor (%.2f)" % _worst(misses))


func test_gunners_miss_a_tank_that_reverses_after_the_telegraph() -> void:
	seed(5)
	var world := stage()
	for walker in [false, true]:
		var misses := _burst(world, _gunner(world, "gun", walker, STRAFE), STRAFE, -STRAFE)
		print("%s reversed: %d rounds, miss %.2f..%.2f m" % ["walker" if walker else "UGV", misses.size(), _best(misses), _worst(misses)])
		check(misses.size() >= 5, "the burst fires")
		check(_best(misses) >= 6.0, "no round is re-aimed: all pass 6 m or more wide (%.2f)" % _best(misses))


func test_aim_point_stays_fixed_through_the_burst() -> void:
	var world := stage()
	var ugv := _gunner(world, "gun", false) as Ugv
	var tank := _tank_moving(world, STRAFE)
	ugv._attack()
	var aim := ugv._aim
	tank.global_position += Vector3(30, 0, 0)
	ugv.behave(1.0 / 60.0)
	check_eq(ugv._aim, aim, "the tank moving does not move it")
