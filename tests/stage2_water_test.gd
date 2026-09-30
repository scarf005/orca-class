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
		check(depth > 0.0 and depth <= Stage2.DEEP, "%s is shallow (%.2f m)" % [name, depth])
	var deep := {"canal": [700.0, -43.0], "levee side": [2000.0, 25.0], "other levee side": [2200.0, -20.0], "arena ring": [2410.0, 60.0], "gate footprint": [2490.0, 0.0]}
	for name: String in deep:
		var depth := _depth(deep[name][0], deep[name][1])
		check(depth > Stage2.DEEP, "%s is deep (%.2f m)" % [name, depth])
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
		if c.x > 440.0 and c.x < 1000.0 and absf(c.y + 43.0) > 9.0:
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
