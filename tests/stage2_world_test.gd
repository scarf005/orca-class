extends TestCase
## The flooded city remains navigable beneath solid cover, including broad roofs and expressways.


func test_section_boundaries_and_bending_rail() -> void:
	Course.use(2)
	for i in Stage2.SECTION_STARTS.size():
		var d: float = Stage2.SECTION_STARTS[i]
		check_eq(Course.section_at(d), i, "the section changes exactly at its boundary")
		check_eq(Course.section_at(d - 0.01), maxi(i - 1, 0), "the previous section owns the approach")
	var length := Course.stage.plan_start
	for piece: Array in Course.stage.plan:
		length += piece[0]
	check_near(length, Stage2.LENGTH, Course.STEP, "the generated rail ends at the declared 4000 m, excluding its approach")
	check_eq(Course.section_at(Stage2.LENGTH), Stage2.Section.BAY, "the rail ends in the harbour")
	check(Course.forward(1000.0).distance_to(Course.forward(1400.0)) > 0.2, "the expressway district bends in plan")
	for d in range(0, 4001, 50):
		for u in [-100.0, 0.0, 100.0]:
			var c := Course.to_course(Course.to_world(float(d), u))
			check_near(c.x, float(d), 0.2, "city bends preserve rail distance")
			check_near(c.y, u, 0.2, "city bends preserve lateral offset")


func test_shallow_lanes_and_deep_offroad_pools() -> void:
	Course.use(2)
	for d in [100.0, 900.0, 2400.0, 3300.0]:
		var lane := Course.ground_at(d, 0.0)
		var pool := Course.ground_at(d, 20.0)
		check(Water.surface_at(lane) - lane.y > 0.0 and Water.surface_at(lane) - lane.y < Water.DEEP, "the asphalt is shallow enough to drive")
		check(Water.surface_at(pool) - pool.y > Water.DEEP, "off-road pools slow the tank")
	check_eq(Course.stage.water_surface(Vector2(-101, 0)), -INF, "no water before its mesh")
	check_eq(Course.stage.water_surface(Vector2(100, 186)), -INF, "no invisible water beyond the mesh")
	check_eq(Course.stage.water_surface(Vector2(Stage2.LENGTH + 1.0, 0)), -INF, "the flood stops with the generated rail")


func test_highest_walkable_surface_and_underpass_ground() -> void:
	Course.use(2)
	var top := Course.surface_height(1050.0, 42.0)
	check_near(top, 28.8, 0.01, "the parallel road wins where expressways overlap")
	check_near(Course.surface_height(1050.0, 0.0), 21.8, 0.01, "a crossing expressway supports enemies above the lane")
	check_near(Course.height(1050.0, 0.0), 0.05, 0.01, "the tank still drives underneath")
	check_near(Course.surface_height(100.0, 0.0), Course.height(100.0, 0.0), 0.01, "open street has no phantom elevated surface")
	var building: Dictionary = Course.stage.structures[0]
	check_near(Course.surface_height(building.d, building.u), building.y + building.size.y, 0.01, "a rooftop is walkable before it streams in")
	var outside: Vector3 = Course.to_world(building.d, building.u) + Course.right(building.d) * (building.size.x * 0.5 + 0.1)
	var c := Course.to_course(outside)
	check(Course.surface_height(c.x, c.y) < building.y + building.size.y, "roof footprint does not leak past its facade")


func test_cover_blocks_sides_roofs_and_inside_rays() -> void:
	Course.use(2)
	var scenery := Scenery.new()
	add_child(scenery)
	check(scenery.line_blocked(Course.to_world(60, -45, 5), Course.to_world(60, -5, 5)), "a tower stops horizontal sight")
	check(not scenery.line_blocked(Course.to_world(60, -45, 60), Course.to_world(60, -5, 60)), "sight above the roof stays clear")
	check(scenery.line_blocked(Course.to_world(60, -25, 60), Course.to_world(60, -25, 5)), "a vertical ray enters the roof")
	check(scenery.line_blocked(Course.to_world(60, -25, 5), Course.to_world(60, -5, 5)), "a ray starting inside cover is blocked")
	check(not scenery.line_blocked(Course.to_world(800, 0, 2), Course.to_world(800, 0, 15)), "clearance under the viaduct is not cover")
	check(scenery.line_blocked(Course.to_world(800, 0, 30), Course.to_world(800, 0, 15)), "the deck itself blocks diving fire")
	check(not scenery.line_blocked(Course.to_world(100, 0, 2), Course.to_world(500, 0, 2)), "the opening lane stays unobstructed")
	scenery.free()


func test_destroyed_and_soft_props_do_not_block_sight() -> void:
	var world := stage()
	var scenery := world.director.scenery
	var at := Course.to_world(20, 0, 0)
	var prop := Prop.new().setup("wall", PropKit.mesh("wall"), 2.0, 5.0, 10.0)
	prop.position = at
	world.props.add_child(prop)
	var a := at + Vector3(-5, 2, 0)
	var b := at + Vector3(5, 2, 0)
	check(not scenery.line_blocked(a, b), "soft scenery is not hunter cover")
	prop.hard = true
	check(scenery.line_blocked(a, b), "a live HARD prop blocks sight")
	prop.dead = true
	check(not scenery.line_blocked(a, b), "destroyed cover stops blocking immediately")


func test_city_structures_cannot_be_crushed_or_shot_down() -> void:
	var world := stage("", false, 2)
	var checked := 0
	for prop: Node in world.props.get_children():
		if not prop is Prop or (prop as Prop).box_size == Vector3.ZERO:
			continue
		var solid := prop as Prop
		var hp := solid.hp
		var ram := Hit.make(Hit.Kind.RAM, 99999, solid.hit_center())
		ram.source = world.player
		solid.take_hit(ram)
		solid.take_hit(Hit.make(Hit.Kind.SHELL, 99999, solid.hit_center()))
		check(solid.hard and not solid.crushable and not solid.dead, "city architecture stays HARD and impassable")
		check_eq(solid.hp, hp, "crushing and main guns leave its footprint intact")
		checked += 1
	check(checked >= 10, "the real streaming path supplies city buildings")


func test_swept_drive_shoves_sideways_instead_of_tunneling() -> void:
	Course.use(2)
	var scenery := Scenery.new()
	add_child(scenery)
	var from := Course.ground_at(35, -25)
	var to := Course.ground_at(85, -25)
	var corrected := scenery.drive_position(from, to, Tank.HULL_RADIUS)
	check_near(Course.to_course(corrected).x, 85.0, 0.05, "a fast drive keeps forward progress")
	check(Course.to_course(corrected).y > -14.0, "the whole footprint is swept even when the endpoint is beyond it")
	var trapped := Course.ground_at(60, -25)
	var out := scenery.drive_position(trapped, trapped, Tank.HULL_RADIUS)
	check(Course.to_course(out).y > -14.0, "starting at a building centre cannot leave the tank stuck")
	check(scenery.drive_position(out, out, Tank.HULL_RADIUS).is_equal_approx(out), "a shoved hull settles rather than oscillating")
	check(scenery.drive_position(Course.ground_at(770, 0), Course.ground_at(830, 0), Tank.HULL_RADIUS).is_equal_approx(Course.ground_at(830, 0)), "the tank passes under a broad expressway")
	scenery.free()


func test_whole_rail_sweep_at_offsets_and_speeds() -> void:
	Course.use(2)
	var scenery := Scenery.new()
	add_child(scenery)
	for speed in [10.0, 30.0, 60.0]:
		for u in [-32.0, -18.0, 0.0, 18.0, 32.0]:
			var d := 0.0
			var last := Course.ground_at(d, u)
			var clear := true
			var advancing := true
			while d < Stage2.LENGTH:
				d = minf(d + speed * 0.1, Stage2.LENGTH)
				var next := Course.ground_at(d, Course.to_course(last).y)
				last = scenery.drive_position(last, next, Tank.HULL_RADIUS)
				advancing = advancing and absf(Course.to_course(last).x - d) < 3.0
				for box in Course.structure_boxes:
					if absf(box.d - d) < 90.0 and Prop.box_hit(box.pose, box.size, last, last, Tank.HULL_RADIUS - 0.01) >= 0.0:
						clear = false
			check(clear, "no hull remains inside HARD scenery at u=%.0f speed=%.0f m/s" % [u, speed])
			check(advancing, "sideways shoves do not stall forward progress")
	scenery.free()


func test_live_tank_is_shoved_after_driving() -> void:
	var world := stage("", false, 2)
	var tank := world.player
	world.rail.d = 60.0
	tank.course_u = -25.0
	tank._place(world.rail.d)
	world.director.scenery._process(1.0 / 60.0)
	check(tank.course_u > -14.0, "the streamed world's post-drive phase ejects an embedded tank")
	check_near(Course.to_course(tank.global_position).y, tank.course_u, 0.1, "the corrected pose and driving offset agree")


func test_driving_beside_a_facade_does_not_repeatedly_jolt() -> void:
	var world := stage("", false, 2)
	world.rail.d = 60.0
	world.rail.speed = Rail.CRUISE
	world.player.course_u = -13.0
	world.player._place(world.rail.d)
	world.player._collide_props()
	check_near(world.rail.speed, Rail.CRUISE, 0.01, "the legacy cylinder query cannot jolt a hull already clear of a rectangular facade")


func test_both_all_range_arenas_bound_tank_movement() -> void:
	var world := stage("", false, 2)
	world.rail.mode = Rail.Mode.ARENA
	for d in [Stage2.PLAZA_D, Stage2.BAY_D]:
		world.rail.d = d
		world._process(0.0)
		var arena := Course.stage.arena_at(d)
		var center := Course.to_world(d, 0.0)
		world.player.global_position = center + Vector3(250, 0, 250)
		world.player._move_arena(1.0 / 60.0, Vector2.ONE)
		var offset := world.player.global_position - center
		check(Vector2(offset.x, offset.z).length() <= arena.radius - 5.9, "the active arena clamps actual tank movement")
		check_eq(Course.stage.arena_center_d, d, "the legacy tank arena reads the active rail hold")
	check(Stage2.BAY_RADIUS > Stage2.PLAZA_RADIUS, "the harbour gives the boss more all-range space")


func test_camera_stays_outside_decks_and_facades() -> void:
	Course.use(2)
	var scenery := Scenery.new()
	add_child(scenery)
	for pair in [[Course.to_world(800, 0, 2), Course.to_world(800, 0, 30)], [Course.to_world(60, 0, 2), Course.to_world(60, -25, 12)]]:
		var eye := scenery.camera_position(pair[0], pair[1])
		check(not scenery.line_blocked(pair[0], eye), "a chase eye is shortened before it enters cover")
		check(eye.distance_to(pair[0]) > 2.0, "the shortened view still has hull clearance")
	scenery.free()


func test_live_chase_camera_clears_the_whole_city() -> void:
	var world := stage("", false, 2)
	var clear := true
	for d in range(0, 4001, 50):
		for u in [-32.0, -18.0, 0.0, 18.0, 32.0]:
			world.rail.d = float(d)
			world.player.course_u = u
			world.player._place(float(d))
			world.director.scenery._last_tank = Vector3.INF
			world.director.scenery._process(0.0)
			world.camera.snap()
			world.camera.follow(1.0 / 60.0)
			for box in Course.structure_boxes:
				if Prop.box_hit(box.pose, box.size, world.camera.global_position, world.camera.global_position, 0.1) >= 0.0:
					clear = false
	check(clear, "actual chase views stay outside facades and decks at five offsets along the whole rail")


func test_prop_plan_is_bounded_for_streaming() -> void:
	Course.use(2)
	var scenery := Scenery.new()
	add_child(scenery)
	scenery.build()
	var peak := 0
	for d in range(0, 4001, 20):
		var count := 0
		for spec in scenery.specs:
			if spec.d >= d - Scenery.BEHIND and spec.d < d + Scenery.AHEAD:
				count += 1
		peak = maxi(peak, count)
	check(peak <= 100, "city streaming keeps fewer than 100 nearby props/decor (got %d)" % peak)
	print("CITY plan=%d peak_window=%d structures=%d" % [scenery.specs.size(), peak, Course.stage.structures.size()])
	scenery.free()
