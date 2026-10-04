extends TestCase
## FPVs hit slow tanks; an outrun dive times out quietly without awarding a kill.


func test_drones_from_behind_reach_a_braking_tank_instead_of_timing_out() -> void:
	var world := stage("", false)
	world.director.events.clear()
	world.player.tail.destroyed = true
	await frames(5)
	var lost := []
	world.player.life_lost.connect(func() -> void: lost.append(true))
	var drones := world.director.spawn_wave({"d": world.rail.d, "kind": "fpv", "count": 3, "formation": "behind", "height": 6.0, "spacing": 6.0, "hover": 14.0, "approach": 1.2})
	var last := {}
	for drone in drones:
		drone.invulnerable = true # Only its own AI can remove it.
	for _i in 60 * 8:
		world.rail.speed = Rail.BRAKE
		await frames(1)
		for drone in drones:
			if is_instance_valid(drone):
				last[drone] = world.player.hit_center().distance_to(drone.hit_center())
	for drone in drones:
		check(not is_instance_valid(drone), "the drone is gone after its dive")
	for distance: float in last.values():
		check(distance < world.player.radius + 1.5, "it contacted the hull instead of timing out short of it (%.1f m away)" % distance)
	check(not lost.is_empty(), "the rear has no reactive armor: the hit is fatal")


func test_a_dive_skims_the_ground_instead_of_crashing_into_it() -> void:
	var world := stage("", false)
	world.director.events.clear()
	await frames(5)
	var drone := FpvDrone.new()
	drone.invulnerable = true
	world.add_enemy(drone)
	var tank := world.player
	drone.global_position = tank.global_position + Vector3(0, 0.4, 0) + Vector3(30, 0, 0)
	drone.state = FpvDrone.State.DIVE
	drone._dive_dir = Vector3.DOWN
	for _i in 30:
		drone.behave(1.0 / 60.0)
		check(drone.global_position.y >= Course.height_at(drone.global_position) + 0.4, "it never goes into the ground")
	check(not drone.dead, "a dive into the ground does not blow it up")


func test_intercept_leads_a_moving_target_and_gives_up_on_a_faster_one() -> void:
	var met := FpvDrone.intercept(Vector3.ZERO, Vector3(0, 0, -20), Vector3(0, 0, -20), 34.0)
	var time := (-met.z - 20.0) / 20.0
	check_near(met.length(), 34.0 * time, 0.01, "it is met at the dive speed")
	var chased := FpvDrone.intercept(Vector3.ZERO, Vector3(0, 0, -30), Vector3(0, 0, -50), 34.0)
	check_eq(chased, Vector3(0, 0, -30), "a target that outruns it is aimed at where it is")


# --- Pursuit: a slow tank on the rail draws FPV pursuers from behind.

func _pursuers(world: World) -> Array[Entity]:
	return world.enemies.filter(func(e: Entity) -> bool: return e is FpvDrone and (e as FpvDrone).state == FpvDrone.State.PURSUE)


## Runs `frames_count` frames with the rail speed pinned at `speed`.
func _run_at(world: World, speed: float, frames_count: int) -> void:
	for _i in frames_count:
		world.rail.speed = speed
		await frames(1)


func _pursuit_stage() -> World:
	var world := stage("", false)
	world.director.events.clear()
	world.player.tail.destroyed = true
	return world


func test_every_pattern_ends_on_the_tank_and_stays_off_the_ground() -> void:
	for kind in FpvDrone.Pattern.values():
		for flank in [-1.0, 1.0]:
			var end := FpvDrone.pursuit_offset(kind, 0.0, flank, 0.0)
			check_near(end.x, 0.0, 0.001, "pattern %d ends centered" % kind)
			check_near(end.y, FpvDrone.HIT_HEIGHT, 0.001, "pattern %d ends at hull height" % kind)
			check_near(end.z, 0.0, 0.001, "pattern %d ends level with the tank" % kind)
			var previous := FpvDrone.pursuit_offset(kind, 1.0, flank, 0.7)
			for i in range(1, 101):
				var spot := FpvDrone.pursuit_offset(kind, 1.0 - i / 100.0, flank, 0.7)
				check(spot.y >= FpvDrone.HIT_HEIGHT - 0.001, "pattern %d stays above the ground" % kind)
				check(spot.distance_to(previous) < 4.0 or i == 1, "pattern %d is a smooth path (jump %.1f m)" % [kind, spot.distance_to(previous)])
				previous = spot


func test_the_patterns_look_different() -> void:
	var widest := {}
	var highest := {}
	for kind in FpvDrone.Pattern.values():
		widest[kind] = 0.0
		highest[kind] = 0.0
		for i in 101:
			var spot := FpvDrone.pursuit_offset(kind, i / 100.0, 1.0, 0.0)
			widest[kind] = maxf(widest[kind], absf(spot.x))
			highest[kind] = maxf(highest[kind], spot.y)
	check(highest[FpvDrone.Pattern.ARC] > 20.0, "the arc stoops from high above")
	check(highest[FpvDrone.Pattern.WEAVE] < 3.0, "the weave skims the ground")
	check(widest[FpvDrone.Pattern.PINCER] > 15.0, "the pincer goes wide")
	check(widest[FpvDrone.Pattern.SPIRAL] < 8.0 and highest[FpvDrone.Pattern.SPIRAL] > 6.0, "the spiral winds around the axis")


func test_each_pattern_hits_a_braking_tank() -> void:
	for kind in FpvDrone.Pattern.values():
		var world := _pursuit_stage()
		await frames(5)
		var lost := []
		world.player.life_lost.connect(func() -> void: lost.append(true))
		var sent := world.director.send_pursuers(1, kind)
		check_eq(sent.size(), 1, "pattern %d launches" % kind)
		for drone in sent:
			drone.invulnerable = true
			check(Course.to_course(drone.global_position).x < world.rail.d, "pattern %d starts behind the tank" % kind)
		var last := [INF]
		for _i in 60 * 14:
			world.rail.speed = Rail.BRAKE
			await frames(1)
			for i in sent.size():
				if is_instance_valid(sent[i]):
					last[i] = world.player.hit_center().distance_to(sent[i].hit_center())
		check(not lost.is_empty(), "pattern %d reaches the hull" % kind)
		for distance: float in last:
			check(distance < world.player.radius + 1.5, "pattern %d contacts the hull instead of timing out short of it (%.1f m)" % [kind, distance])
		world.queue_free()
		await frames(2)


func test_a_tank_at_overdrive_outruns_the_pursuers() -> void:
	var world := _pursuit_stage()
	await frames(5)
	var lost := []
	world.player.life_lost.connect(func() -> void: lost.append(true))
	var sent := world.director.send_pursuers(3, FpvDrone.Pattern.SPIRAL)
	for drone in sent:
		drone.invulnerable = true
	await _run_at(world, Rail.OVERDRIVE, 60 * 8)
	for drone in sent:
		check(not is_instance_valid(drone), "the pursuer peeled off and is gone")
	check(lost.is_empty(), "it never reached the tank")
	check_eq(world.stats.kills, 0, "peeling off is not a kill")


func test_pursuit_starts_after_the_fill_time_only_in_rail_mode() -> void:
	var world := _pursuit_stage()
	await frames(5)
	await _run_at(world, 5.0, int(60 * Director.PURSUIT_FILL * 0.6))
	check(world.director.slow_meter > 0.3 and world.director.slow_meter < 1.0, "the meter is part full (%.2f)" % world.director.slow_meter)
	check(_pursuers(world).is_empty(), "nothing launches before the fill time")
	await _run_at(world, 5.0, int(60 * Director.PURSUIT_FILL * 0.6))
	check_eq(_pursuers(world).size(), Director.PURSUIT_GROUP, "a group of pursuers launches once it is full")


func test_no_pursuit_while_the_rail_holds_or_the_tank_is_fast() -> void:
	var held := _pursuit_stage()
	held.rail.mode = Rail.Mode.HOLD
	held.rail.hold_at = held.rail.d
	await frames(60 * 4)
	check_eq(held.director.slow_meter, 0.0, "a hold never fills the meter")
	check(_pursuers(held).is_empty(), "no pursuers in a hold")
	held.queue_free()
	await frames(2)
	var arena := _pursuit_stage()
	arena.rail.mode = Rail.Mode.ARENA
	await frames(60 * 4)
	check(_pursuers(arena).is_empty(), "no pursuers in the arena")
	arena.queue_free()
	await frames(2)
	var fast := _pursuit_stage()
	await _run_at(fast, Rail.OVERDRIVE, 60 * 4)
	check_eq(fast.director.slow_meter, 0.0, "a fast tank leaves the meter empty")
	check(_pursuers(fast).is_empty(), "no pursuers for a fast tank")


func test_speeding_up_drains_the_meter_and_ends_the_spell() -> void:
	var world := _pursuit_stage()
	await frames(5)
	await _run_at(world, 5.0, int(60 * Director.PURSUIT_FILL * 0.8))
	check(world.director.slow_meter > 0.5, "slowness fills the meter")
	await _run_at(world, Rail.CRUISE, 60 * 3)
	check_eq(world.director.slow_meter, 0.0, "running at cruise drains it")
	check(_pursuers(world).is_empty(), "and nothing was sent")


func test_groups_keep_coming_and_grow_while_the_tank_stays_slow() -> void:
	var world := _pursuit_stage()
	await frames(5)
	var sizes: Array[int] = []
	var spawned := [world.stats.spawned]
	world.director.incoming.connect(func(_from: Vector3) -> void:
		sizes.append(world.stats.spawned - spawned[0])
		spawned[0] = world.stats.spawned)
	var old_interval := Director.PURSUIT_INTERVAL
	Director.PURSUIT_INTERVAL = 1.0
	await _run_at(world, 5.0, int(60 * (Director.PURSUIT_FILL + 3.5)))
	Director.PURSUIT_INTERVAL = old_interval
	check(sizes.size() >= 4, "groups keep coming (%d)" % sizes.size())
	check_eq(sizes.slice(0, 4), [2, 3, 4, 4], "they grow from 2 to 4 and stay there")
