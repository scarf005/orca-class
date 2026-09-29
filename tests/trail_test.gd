extends TestCase
## Flying enemies leave a fading ribbon behind them; ground enemies do not.


func _trails(world: World) -> Array:
	return world.get_children().filter(func(n: Node) -> bool: return n is FlyerTrail)


## A trail behind a plain mover flying `speed` m/s along the rail's heading.
func _mover(world: World, speed: float) -> Array:
	var mover := Node3D.new()
	world.add_child(mover)
	mover.global_position = Vector3(0, 40, 0)
	var trail := FlyerTrail.new()
	trail.source = mover
	trail.setup(mover.global_position, 0.5)
	world.add_child(trail)
	var step := func(frames_count: int) -> void:
		for i in frames_count:
			await get_tree().process_frame
			if not mover.has_meta("stop"):
				mover.global_position += Vector3(speed / 60.0, 0, 0)
	return [mover, trail, step]


func test_a_moving_flyers_trail_grows_to_its_length() -> void:
	var world := stage()
	var rig := _mover(world, 20.0)
	var trail: FlyerTrail = rig[1]
	check_near(trail.length(), 0.0, 0.001, "a new trail has no length")
	await rig[2].call(120)
	check(trail.length() > 20.0 * FlyerTrail.TRAIL_TIME * 0.85 and trail.length() < 20.0 * FlyerTrail.TRAIL_TIME * 1.15, "it is as long as the path of the last %.2f s (%.1f m)" % [FlyerTrail.TRAIL_TIME, trail.length()])
	check(trail.oldest_age() > 1.0 and trail.oldest_age() < 1.5, "its oldest point is 1-1.5 s old (%.2f s)" % trail.oldest_age())
	check(trail.layers == 1, "it draws on the plain layer, outside every outline class")
	check(trail.top_level and trail.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "and casts no shadow")


func test_a_stationary_flyers_trail_collapses() -> void:
	var world := stage()
	var rig := _mover(world, 20.0)
	var trail: FlyerTrail = rig[1]
	await rig[2].call(90)
	check(trail.length() > 10.0, "moving, it has a trail")
	rig[0].set_meta("stop", true)
	await rig[2].call(100)
	check_near(trail.length(), 0.0, 0.05, "hovering, the old path is gone within about a second (%.2f m)" % trail.length())


func test_the_trail_fades_and_frees_itself_after_the_flyer_dies() -> void:
	var world := stage()
	var drone := FpvDrone.new()
	drone.position = Course.ground_at(world.rail.d + 60.0, 0.0) + Vector3.UP * 12.0
	world.add_enemy(drone)
	await frames(2)
	var trails := _trails(world)
	check_eq(trails.size(), 1, "a drone gets a trail")
	var trail: FlyerTrail = trails[0]
	for i in 30:
		drone.global_position += Vector3(0.4, 0.0, 0.0)
		await frames(1)
	check(trail.length() > 5.0, "it follows the drone (%.1f m)" % trail.length())
	drone.take_hit(Hit.make(Hit.Kind.SHELL, 999.0, drone.global_position))
	await frames(2)
	check(is_instance_valid(trail), "the trail outlives the drone")
	await frames(20)
	check(is_instance_valid(trail), "and is still fading a third of a second later")
	var length := trail.length()
	await frames(10)
	check_near(trail.length(), length, 0.001, "it no longer follows anything")
	check(await wait_until(gone(trail), 120), "then it frees itself when it has faded")


func test_every_flyer_has_a_trail_and_ground_enemies_do_not() -> void:
	var world := stage()
	var at := Course.ground_at(world.rail.d + 80.0, 0.0)
	var flyers := {"FpvDrone": FpvDrone, "Uav": Uav, "Helicopter": Helicopter, "Gunship": Gunship}
	for name: String in flyers:
		var before := _trails(world).size()
		var enemy: Enemy = flyers[name].new()
		enemy.position = at + Vector3.UP * 15.0
		world.add_enemy(enemy)
		check_eq(_trails(world).size(), before + 1, "%s leaves a trail" % name)
	for grounded: Enemy in [Ugv.new(), Walker.new(), QuadMech.new(), Crawler.new(), Spitter.new()]:
		var before := _trails(world).size()
		grounded.position = at
		world.add_enemy(grounded)
		check_eq(_trails(world).size(), before, "%s leaves none" % grounded.get_script().get_global_name())
