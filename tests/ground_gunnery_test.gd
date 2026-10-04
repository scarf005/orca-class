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


## Fires a gun burst at a tank moving at `lateral` m/s. Once aim is committed by `_attack`, the
## tank switches to `after` immediately. Returns analytic diagnostics plus real-flight completion.
func _burst(world: World, enemy: Enemy, lateral: float, after: float) -> Dictionary:
	var tank := _tank_moving(world, lateral)
	if enemy is Ugv:
		enemy._attack()
	else:
		enemy._attack(tank)
	var drift := world.rail.forward() * RAIL_SPEED + tank.global_basis.x * after
	var reversal_seen := not is_equal_approx(after, lateral)
	tank.velocity = drift
	var reversal_velocity := tank.velocity
	var tracked: Array[Projectile] = []
	var misses: Array[float] = []
	var all_resolved := false
	for frame in 360: # Six seconds bounds the longest three-second gun flight.
		tank.invuln = maxf(0.0, tank.invuln - 1.0 / 60.0)
		tank.global_position += tank.velocity * (1.0 / 60.0)
		enemy.behave(1.0 / 60.0)
		for round in world.projectiles.duplicate():
			if round not in tracked and round.hit.source == enemy:
				tracked.append(round)
				# Begin each diagnostic at the target's actual position when this round launches.
				misses.append(_miss(round, tank.model.sensor_position("laser"), drift))
		var active := false
		for round in tracked.duplicate():
			if is_instance_valid(round) and not round.is_queued_for_deletion():
				active = true
				round.step(1.0 / 60.0)
		if enemy.get("_burst") == 0 and not active:
			all_resolved = true
			break
	return {"misses": misses, "reversal_seen": reversal_seen, "reversal_velocity": reversal_velocity, "all_resolved": all_resolved}


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
	for walker in [false, true]:
		seed(5)
		var world := stage()
		world.player.modules.mount_rws()
		var modules_before := world.player.modules.hp.duplicate()
		var misses_result := _burst(world, _gunner(world, "gun", walker, STRAFE), STRAFE, STRAFE)
		var misses: Array[float] = misses_result["misses"]
		print("%s steady: %d rounds, miss %.2f..%.2f m" % ["walker" if walker else "UGV", misses.size(), _best(misses), _worst(misses)])
		check(misses.size() >= 5, "the burst fires")
		check(misses_result["all_resolved"], "every steady flight terminates within the bound")
		check(_best(misses) <= world.player.radius, "a committed round reaches the moving hull trajectory (%.2f)" % _best(misses))
		check(world.player.hp < world.player.max_hp or world.player.modules.hp != modules_before, "a steady tank is actually affected by the rounds")
		cleanup()
		await frames(1)


func test_gunners_miss_a_tank_that_reverses_after_the_telegraph() -> void:
	for walker in [false, true]:
		seed(5)
		var world := stage()
		world.player.modules.mount_rws()
		var hp_before := world.player.hp
		var modules_before := world.player.modules.hp.duplicate()
		var tail_before := world.player.tail.hp
		var tail_destroyed_before := world.player.tail.destroyed
		var lives_before := world.stats.lives
		var damage_before := world.stats.damage_taken
		var result := _burst(world, _gunner(world, "gun", walker, STRAFE), STRAFE, -STRAFE)
		var misses: Array[float] = result["misses"]
		print("%s reversed: %d rounds, miss %.2f..%.2f m" % ["walker" if walker else "UGV", misses.size(), _best(misses), _worst(misses)])
		check(result["reversal_seen"] and result["reversal_velocity"].dot(world.player.global_basis.x) < -1.0, "the tank reverses immediately after aim commitment")
		check(misses.size() >= 5, "the burst fires")
		check(result["all_resolved"], "every reversed flight terminates within the bound")
		check(_best(misses) > world.player.radius, "reversed trajectory clears the moving hull (%.2f m)" % _best(misses))
		check_eq(world.player.hp, hp_before, "reversal leaves hull health unchanged")
		check_eq(world.player.modules.hp, modules_before, "reversal leaves every module unchanged")
		check_eq(world.player.tail.hp, tail_before, "reversal leaves the tail unchanged")
		check_eq(world.player.tail.destroyed, tail_destroyed_before, "reversal leaves tail state unchanged")
		check_eq(world.stats.lives, lives_before, "reversal costs no life")
		print("%s reversed state hp %.1f modules %s tail %.1f/%s lives %d damage %.1f" % ["walker" if walker else "UGV", world.player.hp, world.player.modules.hp, world.player.tail.hp, world.player.tail.destroyed, world.stats.lives, world.stats.damage_taken])
		check_eq(world.stats.damage_taken, damage_before, "reversal accepts no damage")
		cleanup()
		await frames(1)


func test_aim_point_stays_fixed_through_the_burst() -> void:
	var world := stage()
	var ugv := _gunner(world, "gun", false) as Ugv
	var tank := _tank_moving(world, STRAFE)
	ugv._attack()
	var aim := ugv._aim
	tank.global_position += Vector3(30, 0, 0)
	ugv.behave(1.0 / 60.0)
	check_eq(ugv._aim, aim, "the tank moving does not move it")


func _place_at(world: World, enemy: Enemy, ahead: float, lane: float, height := 0.0) -> void:
	enemy.position = Course.ground_at(world.rail.d + world.player.course_offset + ahead, lane) + Vector3.UP * height
	world.add_enemy(enemy)


func test_every_gunner_and_missile_shooter_aims_at_the_rws_first() -> void:
	var world := stage()
	var tank := world.player
	tank.velocity = Vector3.ZERO
	var rws := tank.model.sensor_position("laser")
	var heli := Helicopter.new()
	heli.set_meta("slot", Vector3(0, 13, 55))
	_place_at(world, heli, 55.0, 0.0, 13.0)
	var quad := QuadMech.new()
	_place_at(world, quad, 60.0, 4.0)
	var walker := Walker.new()
	walker.weapon = "missile"
	_place_at(world, walker, 45.0, -4.0)
	var atgm := Ugv.new()
	atgm.weapon = "atgm"
	_place_at(world, atgm, 50.0, 4.0)
	var rotor := Tiltrotor.new()
	_place_at(world, rotor, 36.0, 16.0, 10.0)
	var aims := {
		"helicopter gun": heli._aim_point(tank),
		"helicopter rockets": (func() -> Vector3:
			heli._rockets = true
			return heli._aim_point(tank)).call(),
		"quad flak": quad._flak_aim(tank),
		"walker pod": walker._pod_aim(tank) - Walker.POD_LOFT,
		"ATGM UGV": atgm._aim_point(tank),
	}
	for name: String in aims:
		check(aims[name].distance_to(rws) < 0.01, "the %s aims at the RWS" % name)
	rotor._line_across(tank)
	var line := Course.to_course((rotor._line_a + rotor._line_b) * 0.5)
	check_near(line.y, Course.to_course(rws).y, 0.5, "the tiltrotor's sweep is centred on the RWS")
	tank.damage_module("laser", 1000.0)
	var fcs := tank.model.sensor_position("fcs")
	check(heli._aim_point(tank).distance_to(fcs) < 0.01 and quad._flak_aim(tank).distance_to(fcs) < 0.01, "with the RWS gone they take the FCS")
