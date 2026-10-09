extends TestCase
## The flooded city remains navigable beneath solid cover, including broad roofs and expressways.


func test_stage_driven_street_limits_and_clear_corridor() -> void:
	Course.use(2)
	check_near(Tank.lateral_limit(300.0), 30.0, 0.01, "boulevard street is 60 m wide")
	check_near(Tank.lateral_limit(900.0), 30.0, 0.01, "viaduct street is 60 m wide")
	check_near(Tank.lateral_limit(2300.0), 22.0, 0.01, "canyon street narrows to 44 m")
	for d in [100.0, 800.0, 1700.0, 2200.0, 3300.0]:
		check_near(Tank.lateral_limit(d), 22.0 if Course.section_at(d) == Stage2.Section.CANYON else 30.0, 0.01, "stage limit follows every non-arena section")
	for box in Course.structure_boxes:
		if box.kind in ["city_deck", "city_pier"] or Course.stage.in_arena(box.d):
			continue
		var is_split := false
		for split: Dictionary in Stage2.SPLITS:
			is_split = is_split or absf(float(split.d) - box.d) < 0.01
		if is_split:
			continue
		var pose: Transform3D = box.pose
		for local_z in [-box.size.z * 0.5, box.size.z * 0.5]:
			for local_x in [-box.size.x * 0.5, box.size.x * 0.5]:
				var corner: Vector3 = pose * Vector3(local_x, 0.0, local_z)
				var c := Course.to_course(corner)
				check(absf(c.y) >= Tank.lateral_limit(c.x) - 0.05, "transformed city structure clears the drivable corridor")


func test_new_breakable_debris_pieces_are_capped() -> void:
	for kind in ["city_shop", "kiosk", "bus_shelter", "barricade"]:
		var chunks := PropKit.collapse_pieces(PropKit.mesh(kind, 0))
		for chunk in chunks:
			var width := maxf(chunk.get_aabb().size.x, chunk.get_aabb().size.z)
			check(width * Prop.debris_piece_scale(kind, width) <= 2.01, "%s collapse pieces stay under two metres" % kind)


func test_city_frontage_props_are_real_breakable_shop_cover() -> void:
	var world := stage("", false, 2)
	var scenery := world.director.scenery
	var shop_specs := scenery.specs.filter(func(spec: Scenery.Spec) -> bool: return spec.kind == "city_shop")
	check(shop_specs.size() >= 60, "street shops match village-like frontage density")
	var shop_spec: Scenery.Spec = shop_specs[0]
	scenery.stream(shop_spec.d, 100000)
	var shop := shop_spec.node as Prop
	check(shop != null and shop.hard and shop.crushable, "shops are registered HARD breakable props")
	if shop:
		world.player.global_position = shop.global_position
		world.player._collide_props()
		check(shop.dead or shop.is_falling(), "the tank can flatten a shop")
	var furniture := scenery.specs.filter(func(spec: Scenery.Spec) -> bool: return spec.kind in ["kiosk", "bus_shelter", "barricade"])
	check(not furniture.is_empty(), "kiosks, shelters and barricades are streamed as props")
	for spec: Scenery.Spec in furniture.slice(0, mini(furniture.size(), 3)):
		scenery.stream(spec.d, 100000)
		check(spec.node is Prop, "%s is a registered destructible prop" % spec.kind)


func test_splitters_and_overhead_clearance_are_explicit() -> void:
	Course.use(2)
	check_eq(Stage2.SPLITS.size(), 1, "the route has exactly one central building fork")
	check_eq(Stage2.SPLITS[0].kind, "tower", "the remaining fork surrounds a building")
	var leaning := Course.structure_boxes.filter(func(box: Dictionary) -> bool: return box.kind == "city_leaning")
	check(not leaning.is_empty() and leaning[0].pose.basis.y.dot(Vector3.UP) < 0.99, "the canyon edge landmark is physically leaning")
	check(Course.structure_boxes.any(func(box: Dictionary) -> bool: return box.kind == "city_sag_span"), "the parallel expressway has a broken sagging span")
	var section_counts := {}
	for split: Dictionary in Stage2.SPLITS:
		var section := Course.section_at(float(split.d))
		section_counts[section] = int(section_counts.get(section, 0)) + 1
	for count: int in section_counts.values():
		check(count <= 2, "no section has more than two splitters")
	for split: Dictionary in Stage2.SPLITS:
		check(split.d >= 150.0, "splitters leave the opening readable")
		var lanes := Stage2.new().split_lane_centres(Stage2.SPLITS.find(split))
		var limit := Tank.lateral_limit(float(split.d))
		check(lanes.x + float(split.size) * 0.5 - (-limit) >= 9.0, "splitter leaves a nine metre left lane")
		check(limit - (lanes.y - float(split.size) * 0.5) >= 9.0, "splitter leaves a nine metre right lane")
	for box in Course.structure_boxes:
		if Course.stage.in_arena(box.d):
			continue
		var split := false
		for spec: Dictionary in Stage2.SPLITS:
			split = split or absf(float(spec.d) - box.d) < 0.01
		if split:
			continue
		var low_overlap := false
		for local_z in [-box.size.z * 0.5, box.size.z * 0.5]:
			for local_x in [-box.size.x * 0.5, box.size.x * 0.5]:
				var c := Course.to_course(box.pose * Vector3(local_x, 0.0, local_z))
				low_overlap = low_overlap or absf(c.y) < Tank.lateral_limit(c.x) and box.y < 16.0 and box.y + box.size.y > 0.0
		check(not low_overlap, "no non-splitter low structure spans the driving corridor")


func test_hull_can_cross_the_street_everywhere_except_through_a_visible_building() -> void:
	Course.use(2)
	var scenery := Scenery.new()
	add_child(scenery)
	var tower: Dictionary = Stage2.SPLITS[0]
	var d := 20.0
	while d < Stage2.BAY_D - Stage2.BAY_RADIUS - 20.0:
		var limit := Tank.lateral_limit(d)
		var in_tower := absf(d - float(tower.d)) < float(tower.size) * 0.5 + 8.0
		for dir: float in [1.0, -1.0]:
			var u := -dir * (limit - 1.0)
			var at := Course.ground_at(d, u)
			for step in 12:
				u = Course.to_course(at).y + dir * (2.0 * limit - 2.0) / 12.0 # Steer from where the hull really is.
				at = scenery.drive_position(at, Course.ground_at(d, u), Tank.HULL_RADIUS)
			if not in_tower:
				check(Course.to_course(at).y * dir > limit - 5.0, "the hull crosses the whole street at d=%d dir=%d (reached u=%.1f)" % [d, dir, Course.to_course(at).y])
		d += 40.0 if absf(d - float(tower.d)) > 200.0 else 10.0
	scenery.free()


func test_frontage_edges_and_gaps_use_measured_layout_data() -> void:
	Course.use(2)
	for gap: Dictionary in (Course.stage as Stage2).frontage_gaps:
		check(gap.gap >= 0.0 and gap.gap <= 14.0, "frontage gap stays within the seeded 0-14 m range")
	for box in Course.structure_boxes:
		if box.kind != "city_building" or Course.stage.in_arena(box.d):
			continue
		var splitter := false
		for split: Dictionary in Stage2.SPLITS:
			splitter = splitter or absf(float(split.d) - box.d) < 0.01
		if splitter or is_equal_approx(box.d, 1808.0):
			continue
		var c := Course.to_course(box.pose.origin)
		var face: float = absf(c.y) - box.size.x * 0.5
		check(face >= Tank.lateral_limit(c.x) + 2.9, "tower inner face is three metres beyond the limit")
		check(face <= Tank.lateral_limit(c.x) + 9.1, "tower jitter stays within six metres")


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
		var pool := Course.ground_at(d, 40.0)
		check(Water.surface_at(lane) - lane.y > 0.0 and Water.surface_at(lane) - lane.y < Water.DEEP, "the asphalt is shallow enough to drive")
		check(Water.surface_at(pool) - pool.y > Water.DEEP, "off-road pools slow the tank")
	check_eq(Course.stage.water_surface(Vector2(-101, 0)), -INF, "no water before its mesh")
	check_eq(Course.stage.water_surface(Vector2(100, 186)), -INF, "no invisible water beyond the mesh")
	check_eq(Course.stage.water_surface(Vector2(Stage2.LENGTH + 1.0, 0)), -INF, "the flood stops with the generated rail")


func test_highest_walkable_surface_and_underpass_ground() -> void:
	Course.use(2)
	var top := Course.surface_height(1050.0, -40.0)
	check_near(top, Stage2.WATER_LEVEL + 6.0, 0.2, "the parallel expressway is six metres above water")
	check_near(Course.surface_height(1050.0, 0.0), 0.05, 0.01, "the tank still drives underneath")
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
	var tower: Dictionary = Course.structure_boxes.filter(func(box: Dictionary) -> bool: return box.kind == "city_building" and not Course.stage.in_arena(box.d))[0]
	var pose: Transform3D = tower.pose
	var centre := pose.origin
	var across := pose.basis.x
	check(scenery.line_blocked(centre - across * (tower.size.x + 10.0) + Vector3.UP * 5.0, centre + across * (tower.size.x + 10.0) + Vector3.UP * 5.0), "a tower stops horizontal sight")
	check(not scenery.line_blocked(centre - across * (tower.size.x + 10.0) + Vector3.UP * (tower.size.y + 5.0), centre + across * (tower.size.x + 10.0) + Vector3.UP * (tower.size.y + 5.0)), "sight above the roof stays clear")
	check(scenery.line_blocked(centre + Vector3.UP * (tower.size.y + 5.0), centre + Vector3.UP), "a vertical ray enters the roof")
	check(scenery.line_blocked(centre + Vector3.UP, centre + across * (tower.size.x + 10.0) + Vector3.UP), "a ray starting inside cover is blocked")
	check(not scenery.line_blocked(Course.to_world(800, 0, 2), Course.to_world(800, 0, 5)), "clearance under the viaduct is not cover")
	check(scenery.line_blocked(Course.to_world(800, -40, 8), Course.to_world(800, -40, 5)), "the expressway deck blocks diving fire")
	check(not scenery.line_blocked(Course.to_world(100, 0, 2), Course.to_world(200, 0, 2)), "the opening lane stays unobstructed")
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


func test_city_boundary_architecture_cannot_be_crushed_or_shot_down() -> void:
	var world := stage("", false, 2)
	var checked := 0
	for prop: Node in world.props.get_children():
		if not prop is Prop or (prop as Prop).box_size == Vector3.ZERO or (prop as Prop).kind in ["container", "ship"]:
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
	check(absf(Course.to_course(corrected).y) <= Tank.lateral_limit(85.0), "the swept drive remains inside the street")
	var tower: Dictionary = Course.structure_boxes.filter(func(box: Dictionary) -> bool: return box.kind == "city_building")[0]
	var trapped: Vector3 = tower.pose.origin
	var out := scenery.drive_position(trapped, trapped, Tank.HULL_RADIUS)
	check(Prop.box_hit(tower.pose, tower.size, out, out, Tank.HULL_RADIUS - 0.01) < 0.0, "starting at a building centre cannot leave the tank stuck")
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
	check(absf(tank.course_u) <= Tank.lateral_limit(world.rail.d), "the streamed world's post-drive phase keeps the tank in the street")
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
	check(peak <= 130, "city streaming keeps at most 130 nearby props/decor, 30 %% over the 100 before the skyline chunks (got %d)" % peak)
	print("CITY plan=%d peak_window=%d structures=%d" % [scenery.specs.size(), peak, Course.stage.structures.size()])
	scenery.free()


func test_splitters_stay_low_enough_for_the_chase_camera_to_see_over() -> void:
	var stage := Stage2.new()
	for structure: Dictionary in stage.structures:
		if Stage2.SPLITS.any(func(split: Dictionary) -> bool: return is_equal_approx(float(split.d), float(structure.d)) and is_equal_approx(float(split.u), float(structure.u))):
			var top: float = structure.y + structure.size.y - Stage2.WATER_LEVEL
			check(top <= 4.5, "splitter at %.0f m rises %.1f m above the water, low enough to see the far lane over" % [structure.d, top])


func test_each_section_has_its_own_haze_that_blends_in_without_a_jump() -> void:
	var stage := Stage2.new()
	for section in range(1, Stage2.SECTION_STARTS.size()):
		var start: float = Stage2.SECTION_STARTS[section]
		var before := stage.fog_tint(start - 0.5)
		var after := stage.fog_tint(start + 0.5)
		check(absf(before.r - after.r) + absf(before.g - after.g) + absf(before.b - after.b) < 0.02, "haze is continuous across the start of section %d" % section)
		var settled := stage.fog_tint(start + 200.0)
		var previous := stage.fog_tint(start - 1.0)
		check(absf(settled.r - previous.r) + absf(settled.g - previous.g) + absf(settled.b - previous.b) > 0.08, "section %d has a different haze from the one before it" % section)
