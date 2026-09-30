extends TestCase
## Stage 2's water: shallow sheets painted on the ground, deep canal, marsh, levee and arena water
## under flat meshes, and one surface query that agrees with all of them.


func _depth(d: float, u: float) -> float:
	var at := Course.to_world(d, u)
	var surface := Water.surface_at(at)
	return surface - Course.height(d, u) if surface > -INF else 0.0


func _use_stage_2() -> void:
	Course.use(2)


func test_depth_categories_at_chosen_points() -> void:
	_use_stage_2()
	var dry := {"floodplain road": [200.0, 0.0], "paddy dike top": [700.0, 18.0], "other dike": [700.0, -18.0], "mill yard": [1150.0, 0.0], "levee road": [2000.0, 0.0], "levee road later": [2200.0, 0.0]}
	for name: String in dry:
		check_eq(_depth(dry[name][0], dry[name][1]), 0.0, "%s is dry" % name)
	var shallow := {"floodplain": [300.0, 20.0], "paddy": [700.0, 0.0], "marsh": [1500.0, 10.0], "arena centre": [2410.0, 0.0]}
	for name: String in shallow:
		var depth := _depth(shallow[name][0], shallow[name][1])
		check(depth > 0.0 and depth <= Water.DEEP, "%s is shallow (%.2f m)" % [name, depth])
	var deep := {"canal": [700.0, -30.0], "levee side": [2000.0, 25.0], "other levee side": [2200.0, -20.0], "arena ring": [2410.0, 60.0], "gate footprint": [2490.0, 0.0]}
	for name: String in deep:
		var depth := _depth(deep[name][0], deep[name][1])
		check(depth > Water.DEEP, "%s is deep (%.2f m)" % [name, depth])
	check(Course.stage.mud_at(1500.0, 30.0), "the marsh has mud")
	check(not Course.stage.mud_at(700.0, 0.0), "the paddies have none")
	check(not Course.stage.mud_at(1150.0, 0.0), "nor the mill yard")


func test_every_paddy_terrace_holds_its_own_water() -> void:
	_use_stage_2()
	var levels := {}
	for u in [0.0, 25.0, -25.0, 40.0]:
		var surface := Water.surface_at(Course.to_world(700.0, u))
		if surface > -INF:
			levels[snappedf(surface, 0.01)] = true
	check(levels.size() >= 2, "terraces stand at different levels (%s)" % [levels.keys()])
	for d in [520.0, 640.0, 760.0, 880.0]:
		for u in [-14.0, -5.0, 5.0, 14.0, 24.0, 30.0]:
			var depth := _depth(d, u)
			check(depth <= 0.5, "paddy water is a hand deep at %.0f,%.0f (%.2f)" % [d, u, depth])


func test_the_dikes_are_dry_lanes_along_the_rail() -> void:
	_use_stage_2()
	var d := 480.0
	while d < 960.0:
		check_eq(_depth(d, 18.0), 0.0, "the dike at u=18 is dry at %.0f" % d)
		check_eq(_depth(d, -18.0), 0.0, "and at u=-18 at %.0f" % d)
		d += 4.0
	check(_depth(560.0, 9.0) > 0.0, "between the dikes it is flooded")


func test_deep_water_has_meshes_and_shallow_water_has_none() -> void:
	var world := stage("", true, 2)
	await frames(2)
	check_eq(world.terrain._waters.size(), 2, "one mesh for the canal, marsh and levee, one for the arena")
	for water: MeshInstance3D in world.terrain._waters:
		check(water.mesh.get_surface_count() > 0 and water.mesh.get_faces().size() > 0, "each has water in it")
	check_near(world.terrain._waters[0].position.y, Stage2.LEVEL, 0.001, "at the marsh level")
	var faces := world.terrain._waters[0].mesh.get_faces()
	var shallow_covered := 0
	for i in range(0, faces.size(), 3):
		var c := Course.to_course((faces[i] + faces[i + 1] + faces[i + 2]) / 3.0)
		if c.x > 440.0 and c.x < 1000.0 and absf(c.y + 30.0) > 9.0:
			shallow_covered += 1
	check_eq(shallow_covered, 0, "the paddies' shallow water is painted, not meshed")
	var lake := stage("", true, 1)
	await frames(2)
	check_eq(lake.terrain._waters.size(), 1, "stage 1 keeps its one reservoir mesh")
	check_near(lake.terrain._waters[0].position.y, Stage1.WATER_LEVEL, 0.001, "at its level")


func test_arena_water_level_moves_the_query_and_the_mesh() -> void:
	var world := stage("boss", true, 2)
	await frames(2)
	var ring := Course.to_world(Stage2.ARENA_CENTER_D, 60.0)
	var centre := Course.to_world(Stage2.ARENA_CENTER_D, 0.0)
	check_near(Water.surface_at(ring), Stage2.LEVEL, 0.001, "the ring starts at the high level")
	var stage_2 := Course.stage as Stage2
	stage_2.arena_level = -0.5
	await frames(2)
	check_near(Water.surface_at(ring), -0.5, 0.001, "the query follows the new level")
	check_near(world.terrain._waters[1].position.y, -0.5, 0.001, "and so does the mesh")
	check_near(world.terrain._waters[0].position.y, Stage2.LEVEL, 0.001, "the marsh does not move")
	check_eq(Water.surface_at(centre), -INF, "the shallow middle dries out")
	stage_2.arena_level = -3.0
	check_eq(Water.surface_at(ring), -INF, "and then the whole basin")


func test_water_ends_at_the_banks() -> void:
	_use_stage_2()
	for u in [-70.0, -60.0, 60.0, 70.0]:
		check_eq(Water.surface_at(Course.to_world(2000.0, u)), -INF, "no water on the hills at u=%.0f" % u)
	check_eq(Water.surface_at(Course.to_world(2600.0, 0.0)), -INF, "nor behind the gate")
	check_eq(Water.surface_at(Course.to_world(-40.0, 0.0)), -INF, "nor before the start")


## The tank on a spot, pinned there so only its speed and meter change.
func _drive(world: World, d: float, u: float, frame_count: int, input := "") -> Dictionary:
	var tank := world.player
	tank.input_enabled = not input.is_empty()
	world.rail.d = d
	world.rail.meter = 0.2
	tank.course_u = u
	tank.course_offset = 0.0
	tank.local_velocity = Vector2.ZERO
	var fastest := 0.0
	if not input.is_empty():
		tank._last_tap[StringName(input)] = -100.0 # Frames run faster than the clock in tests: no double taps.
		Input.action_press(input)
	for i in frame_count:
		await frames(1)
		fastest = maxf(fastest, absf(tank.local_velocity.x))
		tank.course_u = u
		world.rail.d = d
	var result := {"speed": fastest, "meter": world.rail.meter, "depth": tank.water_depth, "mud": tank.in_mud}
	if not input.is_empty():
		Input.action_release(input)
	return result


func test_wading_slows_the_strafe_and_deep_water_slows_the_refill() -> void:
	var world := stage("", true, 2)
	world.player.invulnerable = true
	var dry := await _drive(world, 700.0, 18.0, 20, "move_right")
	var shallow := await _drive(world, 700.0, 0.0, 20, "move_right")
	var deep := await _drive(world, 700.0, -30.0, 20, "move_right")
	check_eq(dry.depth, 0.0, "the dike is dry")
	check(shallow.depth > 0.0 and shallow.depth <= Water.DEEP, "the paddy is shallow")
	check(deep.depth > Water.DEEP, "the canal is deep")
	check_near(dry.speed, Tank.MOVE_SPEED.x, 0.01, "dry ground: full strafe speed")
	check_near(shallow.speed, Tank.MOVE_SPEED.x * Tank.WADE_SPEED, 0.01, "shallow: 85%")
	check_near(deep.speed, Tank.MOVE_SPEED.x * Tank.DEEP_SPEED, 0.01, "deep: 65%")
	var gains := {}
	for name in ["dry", "shallow", "deep"]:
		var spot := {"dry": [700.0, 18.0], "shallow": [700.0, 0.0], "deep": [700.0, -30.0]}[name] as Array
		gains[name] = (await _drive(world, spot[0], spot[1], 60)).meter - 0.2
	var full := Rail.METER_REFILL * 60.0 / 60.0 ## One second of refill.
	check(gains.dry > full * 0.8, "the meter refills on dry ground (%.3f of %.3f)" % [gains.dry, full])
	check_near(gains.shallow, full, full * 0.1, "shallow water leaves the refill alone (%.3f)" % gains.shallow)
	check_near(gains.deep, full * Tank.DEEP_REFILL, full * 0.12, "deep water halves it (%.3f vs %.3f)" % [gains.deep, full])
	world.player.input_enabled = false


func test_mud_keeps_the_tank_sliding() -> void:
	var world := stage("", true, 2)
	world.player.invulnerable = true
	var tank := world.player
	world.rail.d = 1500.0
	tank.course_u = 30.0
	await frames(2)
	check(tank.in_mud, "the marsh patch is mud")
	var mud_grip := tank._grip()
	tank.course_u = 10.0
	await frames(2)
	check(not tank.in_mud, "the neighbouring marsh is not")
	check(mud_grip < tank._grip() * 0.5, "mud lets go of the ground (%.2f vs %.2f)" % [mud_grip, tank._grip()])
	tank.course_u = 0.0
	world.rail.d = 200.0
	await frames(2)
	check_eq(tank._grip(), 1.0, "dry road: full grip")
	# Let go of the stick: on mud the strafe coasts on where dry ground stops at once.
	var coast := {}
	for name in ["mud", "road"]:
		tank.course_u = 30.0 if name == "mud" else 0.0
		world.rail.d = 1500.0 if name == "mud" else 200.0
		tank.local_velocity = Vector2(30.0, 0.0)
		for i in 5:
			await frames(1)
			tank.course_u = 30.0 if name == "mud" else 0.0
			world.rail.d = 1500.0 if name == "mud" else 200.0
		coast[name] = tank.local_velocity.x
	check(coast.mud > coast.road + 5.0, "after 5 frames the mud slide keeps %.1f m/s, the road %.1f" % [coast.mud, coast.road])


func test_stage_1_water_does_not_change_the_driving() -> void:
	var world := stage("", true, 1)
	var tank := world.player
	world.rail.d = 2200.0
	tank.course_u = -30.0
	await frames(3)
	check(Water.surface_at(tank.global_position) > -INF, "the tank is in the reservoir")
	check_eq(tank.water_depth, 0.0, "stage 1 does not slow it")
	check_eq(tank._grip(), 1.0, "with full grip")


func test_hud_shows_what_the_tank_is_driving_through() -> void:
	var world := stage("", true, 2)
	var hud := Hud.new()
	hud.world = world
	add_child(hud)
	var tank := world.player
	var seen := {}
	for spot in [[200.0, 0.0, "dry"], [700.0, 0.0, "shallow"], [700.0, -30.0, "deep"], [1500.0, 30.0, "mud"]]:
		world.rail.d = spot[0]
		tank.course_u = spot[1]
		await frames(2)
		seen[spot[2]] = hud.terrain_glyph()
	check_eq(seen, {"dry": 0, "shallow": 1, "deep": 2, "mud": 3}, "the glyph names the terrain")
	hud.free()


func test_ground_enemies_keep_driving_through_water() -> void:
	var world := stage("", true, 2)
	world.player.invulnerable = true
	for spot in [[650.0, 0.0], [650.0, -30.0], [1400.0, 5.0], [1950.0, 25.0]]:
		world.rail.d = spot[0]
		for kind in ["ugv", "walker", "crawler"]:
			var enemy: Enemy = load(Director.ENEMY_SCRIPTS[kind]).new()
			enemy.position = Course.ground_at(spot[0] + 50.0, spot[1])
			world.add_enemy(enemy)
			enemy.max_hp = 1e6 # The tank shoots at anything near; only the driving is under test.
			enemy.hp = 1e6
			var start := enemy.global_position
			await frames(60)
			if kind != "crawler": # Crawlers blow themselves up on reaching the tank.
				check(is_instance_valid(enemy) and not enemy.dead, "%s survives at %s" % [kind, spot])
			if is_instance_valid(enemy):
				if kind != "crawler": # A crawler may already be curled up at the tank.
					check(enemy.global_position.distance_to(start) > 1.0, "%s still moves in the water at %s" % [kind, spot])
				check(enemy.global_position.y > -5.0, "%s stays on the ground at %s" % [kind, spot])
				enemy.queue_free()
