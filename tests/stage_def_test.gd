extends TestCase
## Stages are looked up through `Course.use`, and each definition carries what the framework reads.


func test_course_use_switches_the_active_stage() -> void:
	Course.use(2)
	check_eq(Course.stage.number, 2, "stage 2 becomes the active definition")
	check(Course.stage is Stage2, "and it is the stage 2 class")
	var kept := Course.stage
	Course.use(2)
	check(Course.stage == kept, "asking for the active stage again keeps it and its road")
	Course.use(1)
	check_eq(Course.stage.number, 1, "stage 1 comes back")
	check(Course.stage is Stage1, "as the stage 1 class")


func test_the_road_follows_the_active_stage() -> void:
	var bend := func() -> Vector3: return Course.to_world(1200.0, 0.0)
	Course.use(1)
	var first: Vector3 = bend.call()
	Course.use(2)
	check(not first.is_equal_approx(bend.call()), "the same distance lies elsewhere on stage 2's road")
	Course.use(1)
	check(first.is_equal_approx(bend.call()), "and back where it was on stage 1's")


func test_every_stage_covers_what_the_framework_reads() -> void:
	for number in range(1, Game.STAGE_COUNT + 1):
		Course.use(number)
		var stage_def := Course.stage
		var length := 0.0
		for piece: Array in stage_def.plan:
			length += piece[0]
		check_eq(stage_def.number, number, "stage %d knows its number" % number)
		check(not stage_def.section_starts.is_empty() and stage_def.section_starts[0] == 0.0, "stage %d has sections from the start" % number)
		check(stage_def.arena_center_d > 0.0 and stage_def.arena_center_d <= stage_def.plan_start * -1.0 + length, "stage %d's arena lies on its road" % number)
		check(stage_def.checkpoints.has(""), "stage %d starts from its beginning" % number)
		check(not stage_def.music(0).is_empty(), "stage %d has music" % number)
		check_eq(stage_def.section_at(-10.0), 0, "before the start is still section 0 of stage %d" % number)
	Course.use(1)


func test_stage_2_starts_fitted_after_stage_1() -> void:
	var bare := stage("", false, 1)
	check(not bare.player.modules.laser_online(), "stage 1 starts without the RWS")
	check_eq(bare.player.coax_tier, 0, "and with the basic coax")
	var world := stage("", false, 2)
	check_eq(world.stage_number, 2, "stage 2 replaces the stage 1 world")
	check(world.player.modules.laser_online(), "the RWS is fitted without being picked up")
	check_eq(world.player.coax_tier, 2, "the coax is tier 2")
	check_eq(world.rail.d, 0.0, "the run starts at the beginning")


func test_stage_2_is_an_empty_rail_that_scrolls() -> void:
	check(Stage2.new().events(true).is_empty() and Stage2.new().events(false).is_empty(), "stage 2 scripts no encounters yet")
	var world := stage("", false, 2)
	world.player.invulnerable = true
	await frames(180)
	check(world.rail.d > 20.0, "the rail runs (d = %.0f)" % world.rail.d)
	check(world.enemies.is_empty(), "nothing attacks on the empty rail")
	check_eq(world.rail.mode, Rail.Mode.RAIL, "the rail never stops")
