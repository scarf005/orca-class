extends TestCase
## Stage flow: events, checkpoints, mid-boss hold, game over, stage data sanity.


func test_checkpoint_start_is_unranked_and_positioned() -> void:
	var world := stage("boss")
	check_near(world.rail.d, Director.CHECKPOINTS["boss"], 0.01, "rail starts at the boss checkpoint")
	check(not world.stats.ranked, "checkpoint runs are unranked")
	check(world.player.coax_tier >= 3, "checkpoint grants a fair coax tier")


func test_waves_spawn_as_rail_advances() -> void:
	var world := stage()
	world.rail.d = 85.0
	var ok := await wait_until(func() -> bool: return world.enemies.size() > 0, 120)
	check(ok, "the first drone wave spawns near d=90")


func test_midboss_holds_rail_until_dead() -> void:
	var world := stage("midboss")
	world.rail.d = Course.MIDBOSS_D - 111.0
	var spawned := await wait_until(func() -> bool: return world.boss is Colossus, 120)
	check(spawned, "mid-boss appears")
	check_eq(world.rail.mode, Rail.Mode.HOLD, "rail holds for the fight")
	await frames(400)
	check(world.rail.d <= world.rail.hold_at + 0.5, "rail never passes the hold point")
	var boss := world.boss as Colossus
	for part: Colossus.Part in boss.parts:
		part.cap = 0.0
		part.hp = 0.0
	boss.core.hp = 1.0
	boss.take_hit(Hit.make(Hit.Kind.SHELL, 10.0, boss.global_transform * boss.core.offset))
	var released := await wait_until(func() -> bool: return world.rail.mode == Rail.Mode.RAIL, 60 * 8)
	check(released, "rail resumes after the mid-boss dies")


func test_game_over_after_last_life() -> void:
	var world := stage()
	var over := [false]
	world.game_over.connect(func() -> void: over[0] = true)
	world.stats.lives = 1
	world.player.take_hit(Hit.make(Hit.Kind.BLAST, 9999.0, world.player.global_position, Vector3.BACK))
	check(over[0], "last life lost ends the run")
	check(world.player.dead, "tank stays dead")


func test_stage_events_are_ordered_and_reach_the_boss() -> void:
	var events := Stage1.events(false)
	var kinds := {}
	for e in events:
		if e.type == "wave":
			kinds[e.kind] = true
			check(Director.ENEMY_SCRIPTS.has(e.kind), "wave kind %s has a script" % e.kind)
	for kind in ["fpv", "ugv", "uav", "crawler", "spitter", "walker", "quad"]:
		check(kinds.has(kind), "stage uses %s" % kind)
	check(events.any(func(e: Dictionary) -> bool: return e.type == "midboss"), "stage has the mid-boss")
	check(events.any(func(e: Dictionary) -> bool: return e.type == "boss"), "stage has the boss")
	check(Stage1.events(true).size() > events.size(), "hard adds encounters")


func test_course_maps_both_ways_across_the_valley() -> void:
	var d := -40.0
	while d < Course.DAM_D + 60.0:
		for u in [-Terrain.HALF_WIDTH, -60.0, -5.0, 0.0, 7.0, 90.0, Terrain.HALF_WIDTH]:
			var back := Course.to_course(Course.to_world(d, u))
			check(absf(back.x - d) < 0.05 and absf(back.y - u) < 0.05, "(%.0f, %.0f) round-trips, got (%.2f, %.2f)" % [d, u, back.x, back.y])
		d += 7.0


func test_course_winds_through_real_bends() -> void:
	var headings: Array[float] = []
	var d := 0.0
	while d < Course.DAM_D:
		var f := Course.forward(d)
		check(absf(f.length() - 1.0) < 0.001 and absf(f.y) < 0.001, "forward is a flat unit vector at %.0f" % d)
		var chord := Course.to_world(d + 1.0, 0.0) - Course.to_world(d - 1.0, 0.0)
		check(chord.normalized().dot(f) > 0.999, "forward follows the road at %.0f" % d)
		check(absf(Course.right(d).dot(f)) < 0.001, "right is square to forward at %.0f" % d)
		check(absf((Course.to_world(d + 1.0, 0.0) - Course.to_world(d, 0.0)).length() - 1.0) < 0.01, "d is arc length at %.0f" % d)
		headings.append(rad_to_deg(atan2(f.x, -f.z)))
		d += 10.0
	check(headings.max() > 50.0 and headings.min() < -40.0, "road turns both ways by more than 40°")
	for straight: Vector2 in [Course.SCHOOL_YARD, Vector2(Course.SECTION_STARTS[Course.Section.ARENA], Course.DAM_D)]:
		check(Course.forward(straight.x).dot(Course.forward(straight.y)) > 0.9999, "road runs straight over %s" % straight)


func test_course_is_continuous_and_walkable() -> void:
	var previous := Course.height(0.0, 0.0)
	var d := 0.0
	while d < Course.ARENA_CENTER_D:
		for u in [-12.0, 0.0, 12.0]:
			var h := Course.height(d, u)
			check(not is_nan(h), "height defined at %.0f,%.0f" % [d, u])
			check(h > Course.WATER_LEVEL, "corridor stays above water at %.0f,%.0f" % [d, u])
		var h0 := Course.height(d, 0.0)
		check(absf(h0 - previous) < 1.5, "road has no cliffs near d=%.0f" % d)
		previous = h0
		d += 2.0
