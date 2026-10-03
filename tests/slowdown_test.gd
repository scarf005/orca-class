extends TestCase
## What slows the tank on the rail: solid buildings, water and mud.


func _quiet_stage(d: float, u: float) -> World:
	var world := stage("", false)
	world.director.events.clear()
	world.rail.d = d
	world.player.course_u = u
	return world


func _prop_in_front(world: World, kind: String, hard: bool) -> Prop:
	var prop := Prop.new().setup(kind, PropKit.mesh(kind), 3.0, 4.0, 50.0)
	prop.hard = hard
	prop.position = world.player.global_position
	world.props.add_child(prop)
	return prop


func test_a_hard_building_drops_the_speed_and_it_recovers() -> void:
	var world := _quiet_stage(100.0, 0.0)
	await frames(10)
	check_near(world.rail.speed, Rail.CRUISE, 0.1, "the tank starts at cruise")
	var house := _prop_in_front(world, "house", true)
	await frames(2)
	check(not is_instance_valid(house) or house.dead, "the building still breaks")
	check(world.rail.speed <= Rail.CRUISE * Rail.HARD_HIT_SPEED + 0.5, "the speed drops to a quarter of cruise (%.1f m/s)" % world.rail.speed)
	await frames(int(60 * Rail.HARD_RECOVER * 0.5))
	check(world.rail.speed < Rail.CRUISE * 0.9, "it is still slow halfway through the recovery (%.1f m/s)" % world.rail.speed)
	await frames(int(60 * (Rail.HARD_RECOVER + 1.5)))
	check_near(world.rail.speed, Rail.CRUISE, 0.1, "it is back at cruise afterwards")


func test_a_light_prop_costs_no_speed() -> void:
	var world := _quiet_stage(100.0, 0.0)
	await frames(10)
	var wall := _prop_in_front(world, "wall", false)
	wall.crushable = true
	await frames(2)
	check(not is_instance_valid(wall) or wall.dead, "the fence goes down")
	check_near(world.rail.speed, Rail.CRUISE, 0.1, "at no cost in speed")


func test_hard_kinds_are_the_landmarks_and_solid_structures() -> void:
	for kind in ["house", "hall", "church_nave", "church_tower", "church_spire", "school_wing", "school_center", "overpass_pier"]:
		check(kind in Scenery.HARD, "%s is hard" % kind)
	for kind in ["wall", "jars", "bale", "car", "truck", "crate", "greenhouse", "reeds", "mushroom"]:
		check(kind not in Scenery.HARD, "%s stays crushable at speed" % kind)


func test_water_caps_the_speed_even_in_overdrive() -> void:
	var world := _quiet_stage(2100.0, -30.0)
	await frames(60)
	check(world.player._wet, "the tank stands in the reservoir")
	check_near(world.rail.speed, Rail.CRUISE * Rail.WADE_SPEED, 0.2, "the speed is capped to the wade share")
	world.rail.meter = 1.0
	world.rail.advance(0.5, 1)
	check(world.rail.speed <= Rail.CRUISE * Rail.WADE_SPEED + 0.01, "overdrive cannot beat the cap")


func test_mud_caps_the_speed_and_dry_ground_does_not() -> void:
	var world := _quiet_stage(2225.0 - 4.0, 0.0)
	for _i in 60:
		world.rail.d = 2225.0 - 4.0 # Stay on the patch while the speed settles.
		await frames(1)
	check(TrackMarks.over_fungus(world.player.global_position), "the tank is on a fungus patch")
	check_near(world.rail.speed, Rail.CRUISE * Rail.WADE_SPEED, 0.2, "mud caps the speed")
	world.rail.d = 100.0
	await frames(120)
	check_near(world.rail.speed, Rail.CRUISE, 0.1, "dry ground lets it run again")
