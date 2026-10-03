extends TestCase
## FPV drones from behind: they die only to what kills them or to their own detonation on the hull.


func test_drones_from_behind_reach_the_tank_instead_of_blowing_up_alone() -> void:
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
		await frames(1)
		for drone in drones:
			if is_instance_valid(drone):
				last[drone] = world.player.hit_center().distance_to(drone.hit_center())
	for drone in drones:
		check(not is_instance_valid(drone), "the drone is gone after its dive")
	for distance: float in last.values():
		check(distance < world.player.radius + 1.5, "it went off on the hull, not alone short of it (%.1f m away)" % distance)
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
