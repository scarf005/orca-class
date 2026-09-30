extends TestCase
## Stage selection and Stage 2's skeleton: its own road, sections and checkpoints, per-stage
## progress keys, the flow from a Stage 1 clear to Stage 2, and switching back to Stage 1.

var _bests := {}
var _bests_path := ""


## Progress tests write to a scratch file, never the player's saves.
func _isolate_bests() -> void:
	_bests = Game.bests
	_bests_path = Game.bests_path
	Game.bests = {}
	Game.bests_path = "user://test_bests.cfg"
	DirAccess.remove_absolute(Game.bests_path)


func _restore_bests() -> void:
	DirAccess.remove_absolute(Game.bests_path)
	Game.bests = _bests
	Game.bests_path = _bests_path
	Game.stage = 1
	Game.difficulty = Game.Difficulty.NORMAL


func _labels(menu: Menu) -> Array[String]:
	var labels: Array[String] = []
	for item in menu.items:
		labels.append(item.label)
	return labels


func _snapshot() -> Array:
	var samples := []
	for d in [-40.0, 300.0, 1655.0, 2200.0, 3450.0]:
		for u in [-60.0, 0.0, 12.0]:
			samples.append([Course.height(d, u), Course.ground_color(d, u, 0.0, 0.5), Course.to_world(d, u), Course.section_at(d), Course.fungus_at(d, u)])
	return samples


func test_switching_stage_rebuilds_the_course_and_back_restores_stage_1() -> void:
	var before := _snapshot()
	Course.use(2)
	check_eq(Course.stage.number, 2, "stage 2 is active")
	check(_snapshot() != before, "stage 2 has its own geography")
	check(Course.forward(1000.0).dot(Vector3(0, 0, -1)) < 0.99, "and its own road")
	Course.use(1)
	check_eq(Course.stage.number, 1, "stage 1 is active again")
	check(_snapshot() == before, "stage 1 comes back exactly")
	Course.use(1)
	check(_snapshot() == before, "selecting the active stage changes nothing")


func test_stage_2_sections_and_checkpoints() -> void:
	Course.use(2)
	var starts := Course.stage.section_starts
	check_eq(starts.size(), 6, "six sections")
	check_eq(starts, [0.0, 420.0, 1000.0, 1260.0, 1880.0, 2300.0] as Array[float], "section starts")
	for i in starts.size():
		check_eq(Course.section_at(starts[i]), i, "section %d starts at %.0f" % [i, starts[i]])
		check_eq(Course.section_at(starts[i] - 0.1), maxi(i - 1, 0), "and the one before ends there")
	var midboss: float = Course.stage.checkpoints["midboss"]
	var boss: float = Course.stage.checkpoints["boss"]
	check(Course.section_at(Course.stage.midboss_d) == Stage2.Section.MILL, "the mid-boss fights in the rice mill yard")
	check(midboss < Course.stage.midboss_d and Course.section_at(midboss) == Stage2.Section.MILL, "its checkpoint is just before it")
	check(boss > starts[Stage2.Section.LEVEE] and boss < starts[Stage2.Section.ARENA], "the boss checkpoint closes the levee")
	check(Course.stage.arena_center_d > starts[Stage2.Section.ARENA], "the arena lies in the last section")
	check(Course.stage.arena_center_d < 2500.0, "about 2,400 m of rail before the arena")
	var events := Course.stage.events(false)
	check_near(events.filter(func(e: Dictionary) -> bool: return e.type == "checkpoint").map(func(e: Dictionary) -> float: return e.d).min(), 1010.0, 0.01, "the mid-boss checkpoint event comes before its start")
	check(events.any(func(e: Dictionary) -> bool: return e.type == "checkpoint" and e.name == "boss"), "the boss checkpoint event exists")


func test_stage_2_events_are_ordered_and_use_known_enemies() -> void:
	Course.use(2)
	var events := Course.stage.events(false)
	var kinds := {}
	for e in events:
		check(e.d >= 0.0 and e.d < Course.stage.section_starts[-1] + 200.0, "event at %.0f is on the course" % e.d)
		if e.type == "wave":
			kinds[e.kind] = true
			check(Director.ENEMY_SCRIPTS.has(e.kind), "wave kind %s has a script" % e.kind)
	check(kinds.size() >= 6, "a mix of enemies")
	check_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "midboss").size(), 1, "one mid-boss")
	check_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "boss").size(), 1, "one boss")
	check(Course.stage.events(true).size() > events.size(), "hard adds encounters")
	for section in Stage2.Section.values():
		if section != Stage2.Section.MILL and section != Stage2.Section.ARENA:
			check(events.any(func(e: Dictionary) -> bool: return e.type == "wave" and Course.section_at(e.d) == section), "section %d has waves" % section)


func test_stage_2_course_maps_both_ways_and_ends_straight_in_the_arena() -> void:
	Course.use(2)
	var d := -40.0
	while d < 2700.0:
		for u in [-Terrain.HALF_WIDTH, -60.0, 0.0, 7.0, 90.0, Terrain.HALF_WIDTH]:
			var back := Course.to_course(Course.to_world(d, u))
			check(absf(back.x - d) < 0.05 and absf(back.y - u) < 0.05, "(%.0f, %.0f) round-trips, got (%.2f, %.2f)" % [d, u, back.x, back.y])
		d += 11.0
	check(Course.forward(2280.0).dot(Course.forward(2600.0)) > 0.9999, "the road runs straight through the arena")
	var headings: Array[float] = []
	d = 0.0
	while d < 2300.0:
		var f := Course.forward(d)
		headings.append(rad_to_deg(atan2(f.x, -f.z)))
		d += 10.0
	check(headings.max() > 20.0 and headings.min() < -25.0, "a few gentle bends both ways")
	check(headings.max() < 60.0 and headings.min() > -70.0, "none of them sharp")


func test_stage_2_ground_is_walkable_and_the_arena_is_flat() -> void:
	Course.use(2)
	var previous := Course.height(0.0, 0.0)
	var d := 0.0
	while d < Course.stage.arena_center_d:
		for u in [-12.0, 0.0, 12.0]:
			check(not is_nan(Course.height(d, u)), "height defined at %.0f,%.0f" % [d, u])
		var h0 := Course.height(d, 0.0)
		check(absf(h0 - previous) < 1.0, "road has no cliffs near d=%.0f" % d)
		previous = h0
		d += 2.0
	check(Course.height(1000.0, 150.0) > 15.0, "hills rise beyond the valley")
	for u in [-30.0, -20.0, 0.0, 20.0, 30.0]:
		check(absf(Course.height(Course.stage.arena_center_d, u)) < 0.6, "the arena floor is flat at u=%.0f" % u)


func test_stage_2_starts_with_rws_and_second_tier_coax() -> void:
	var world := stage("", false, 2)
	check_eq(world.player.coax_tier, 2, "coax tier 2")
	check(world.player.modules.laser_online(), "RWS fitted")
	check_eq(world.rail.d, 0.0, "starts at the beginning")
	world = stage("midboss", false, 2)
	check_eq(world.player.coax_tier, 2, "the mid-boss checkpoint is fair too")
	check(world.player.modules.laser_online(), "with the RWS")
	check_near(world.rail.d, Course.stage.checkpoints["midboss"], 0.01, "at the stage 2 checkpoint")
	world = stage("boss", false, 2)
	check_eq(world.player.coax_tier, 3, "the boss checkpoint grants tier 3")
	world = stage("", false)
	check_eq(world.player.coax_tier, 0, "stage 1 still starts bare")
	check(not world.player.modules.laser_online(), "without the RWS")


func test_stage_2_world_uses_its_own_look_and_scenery() -> void:
	var world := stage("", true, 2)
	check_eq(Course.stage.number, 2, "the world switched the course")
	check_near(world.environment.fog_depth_end, Course.stage.fog_end, 0.001, "fog from the stage")
	check(world.environment.fog_depth_end < 420.0, "closer than stage 1's")
	check(not world.director.scenery.specs.is_empty(), "the stage has scenery")
	check(world.director.scenery.specs.all(func(s: Scenery.Spec) -> bool: return s.d < 2600.0), "and none of stage 1's dam or highway")
	var other := stage()
	check_eq(Course.stage.number, 1, "a stage 1 world switches back")
	check_near(other.environment.fog_depth_end, 420.0, 0.001, "with stage 1's fog")


func test_stage_2_run_reaches_the_boss_checkpoint_and_the_arena() -> void:
	var world := stage("boss", true, 2)
	var reached := []
	world.director.checkpoint_reached.connect(func(name: String) -> void: reached.append(name))
	check_near(world.rail.d, 2260.0, 0.01, "starts at the boss checkpoint")
	var arena := await wait_until(func() -> bool: return world.rail.mode == Rail.Mode.ARENA, 60 * 12)
	check(arena, "the rail enters the arena mode")
	check(reached.has("boss"), "the boss checkpoint fires on the way")
	check(world.boss != null, "a boss waits in the arena")
	check(world.boss.global_position.distance_to(Course.to_world(Course.stage.arena_center_d, 0.0)) < 120.0, "above the arena")


func test_stage_2_boss_death_clears_the_stage() -> void:
	var world := stage("boss", true, 2)
	world.player.invulnerable = true
	await wait_until(func() -> bool: return world.boss != null, 60 * 12)
	var boss := world.boss as Gunship
	var cleared := [false]
	world.stage_cleared.connect(func() -> void: cleared[0] = true)
	boss.hp = 1.0
	var hit := Hit.make(Hit.Kind.SHELL, 50.0, boss.global_position)
	hit.pierce = true
	boss.take_hit(hit)
	check(boss._crash > 0.0, "the boss goes down")
	var crash_to := boss._crash_to
	check(await wait_until(func() -> bool: return cleared[0], 60 * 14), "the stage clears without a dam to crash into")
	check(crash_to.y < 5.0, "the wreck came down on the ground")


func test_stage_2_midboss_holds_and_releases_the_rail() -> void:
	var world := stage("midboss", true, 2)
	world.player.invulnerable = true
	var spawned := await wait_until(func() -> bool: return world.boss is Colossus, 60 * 10)
	check(spawned, "the mid-boss appears in the mill yard")
	check_eq(world.rail.mode, Rail.Mode.HOLD, "the rail holds")
	check(world.boss.global_position.distance_to(Course.ground_at(Course.stage.midboss_d, 0.0)) < 30.0, "at the mill")
	await frames(300)
	check(world.rail.d <= world.rail.hold_at + 0.5, "never past the hold point")
	var boss := world.boss as Colossus
	for part: Colossus.Part in boss.parts:
		part.cap = 0.0
		part.hp = 0.0
	boss.core.hp = 1.0
	boss.take_hit(Hit.make(Hit.Kind.SHELL, 10.0, boss.global_transform * boss.core.offset))
	check(await wait_until(func() -> bool: return world.rail.mode == Rail.Mode.RAIL, 60 * 8), "the rail runs again")


func test_progress_keys_are_per_stage() -> void:
	_isolate_bests()
	Game.stage = 1
	check_eq(Game.best_key("score"), "score_normal", "stage 1 keeps its keys")
	Game.difficulty = Game.Difficulty.HARD
	check_eq(Game.best_key("score"), "score_hard", "on hard too")
	check_eq(Game.best_key("rank_S", 2), "s2_rank_S_hard", "stage 2 keys are prefixed")
	Game.difficulty = Game.Difficulty.NORMAL
	Game.stage = 2
	check_eq(Game.best_key("score"), "s2_score_normal", "the current stage decides the key")
	check_eq(Game.best_key("score", 1), "score_normal", "and can be overridden")
	Game.submit_best(Game.best_key("score"), 500)
	Game.submit_best(Game.best_key("score", 1), 900)
	check_eq(Game.bests["s2_score_normal"], 500, "stage 2 best stored under its key")
	check_eq(Game.bests["score_normal"], 900, "stage 1 best untouched")
	Game.unlock_checkpoint("boss")
	check(Game.bests.has("s2_checkpoint_boss") and not Game.bests.has("checkpoint_boss"), "checkpoints follow the stage")
	check(Game.is_checkpoint_unlocked("boss", 2) and not Game.is_checkpoint_unlocked("boss", 1), "and are asked per stage")
	check_eq(Game.string_key("SECTION_1", 1), "SECTION_1", "stage 1 strings keep their names")
	check_eq(Game.string_key("SECTION_1", 2), "S2_SECTION_1", "stage 2 strings are prefixed")
	_restore_bests()


func test_stage_unlock_persists_and_stage_1_is_always_open() -> void:
	_isolate_bests()
	check(Game.is_stage_unlocked(1), "stage 1 is always open")
	check(not Game.is_stage_unlocked(2), "stage 2 starts locked")
	Game.unlock_stage(1)
	Game.unlock_stage(Game.STAGE_COUNT + 1)
	check(Game.bests.is_empty(), "there is nothing to unlock for stage 1 or beyond the last")
	Game.unlock_stage(2)
	check(Game.is_stage_unlocked(2), "clearing unlocks stage 2")
	Game.bests = {}
	Game._load_bests()
	check(Game.is_stage_unlocked(2), "and it is saved")
	_restore_bests()


func test_results_offer_the_next_stage_only_when_there_is_one() -> void:
	_isolate_bests()
	for has_next in [true, false]:
		var results := Results.new()
		results.stats = RunStats.new()
		results.stats.ranked = false
		results.has_next_stage = has_next
		add_child(results)
		await wait_until(func() -> bool: return results._menu != null, 60 * 6)
		var labels := _labels(results._menu)
		check_eq(labels.has(tr("MENU_NEXT_STAGE")), has_next, "NEXT STAGE shown: %s" % has_next)
		check(labels.has(tr("MENU_RETRY")) and labels.has(tr("MENU_QUIT_TITLE")), "retry and title remain")
		if has_next:
			check_eq(labels[0], tr("MENU_NEXT_STAGE"), "it comes first")
		results.queue_free()
	_restore_bests()


func test_game_screen_clear_unlocks_and_offers_stage_2_only_after_stage_1() -> void:
	_isolate_bests()
	for number in [1, 2]:
		var screen := GameScreen.new()
		screen.stage = number
		add_child(screen)
		await frames(3)
		check_eq(Game.stage, number, "the screen plays stage %d" % number)
		check_eq(Course.stage.number, number, "on its course")
		screen.world.stage_cleared.emit()
		await wait_until(func() -> bool: return screen._results != null, 60 * 5)
		check_eq(screen._results.has_next_stage, number == 1, "next stage offered after stage %d: %s" % [number, number == 1])
		check_eq(Game.is_stage_unlocked(2), true, "stage 2 is open after clearing stage %d" % number)
		check(not Game.bests.has("stage_3"), "there is no stage 3 to open")
		if number == 1:
			var restarts := []
			screen.restart.connect(func(name: String) -> void: restarts.append(name))
			screen._results.next_stage.emit()
			check_eq(Game.stage, 2, "next stage selects stage 2")
			check_eq(restarts, [""], "and restarts from its beginning")
		remove_child(screen)
		screen.queue_free()
		await frames(2)
	_restore_bests()


func test_title_lists_stage_2_entries_once_unlocked() -> void:
	_isolate_bests()
	var title: Control = load("res://scripts/ui/title.gd").new()
	add_child(title)
	await frames(2)
	var labels := _labels(title._menu)
	check(labels.has(tr("MENU_START_NORMAL")) and labels.has(tr("MENU_START_HARD")), "stage 1 sorties")
	check(not labels.has(tr("S2_MENU_START_NORMAL")), "no stage 2 sortie while it is locked")
	Game.unlock_stage(2)
	title._show_main()
	labels = _labels(title._menu)
	check(labels.has(tr("S2_MENU_START_NORMAL")) and labels.has(tr("S2_MENU_START_HARD")), "stage 2 sorties once stage 1 is cleared")
	check(not labels.has(tr("S2_MENU_FROM_MIDBOSS")) and not labels.has(tr("S2_MENU_FROM_BOSS")), "no stage 2 checkpoints yet")
	check(not labels.has(tr("MENU_FROM_MIDBOSS")), "and no stage 1 ones")
	Game.stage = 2
	Game.unlock_checkpoint("midboss")
	Game.stage = 1
	title._show_main()
	labels = _labels(title._menu)
	check(labels.has(tr("S2_MENU_FROM_MIDBOSS")) and not labels.has(tr("S2_MENU_FROM_BOSS")), "a reached stage 2 checkpoint is listed")
	check(not labels.has(tr("MENU_FROM_MIDBOSS")), "stage 1's is not")
	var started := []
	title.start.connect(func(checkpoint: String) -> void: started.append([checkpoint, Game.stage, Game.difficulty]))
	title._menu.items[labels.find(tr("S2_MENU_START_HARD"))].action.call()
	check_eq(started, [["", 2, Game.Difficulty.HARD]], "the entry starts stage 2 on hard")
	title._menu.items[labels.find(tr("S2_MENU_FROM_MIDBOSS"))].action.call()
	check_eq(started[1], ["midboss", 2, Game.Difficulty.NORMAL], "the checkpoint entry starts stage 2 from there")
	title._menu.items[labels.find(tr("MENU_START_NORMAL"))].action.call()
	check_eq(started[2], ["", 1, Game.Difficulty.NORMAL], "and a stage 1 entry goes back to stage 1")
	remove_child(title)
	title.queue_free()
	await frames(2)
	_restore_bests()


func test_stage_2_banners_and_strings() -> void:
	var previous: String = Game.settings.locale
	Game.settings.locale = "en"
	Game.apply_settings()
	var names := []
	for i in 6:
		names.append(tr(Game.string_key("SECTION_%d" % i, 2)))
	check_eq(names, ["FLOODPLAIN", "TERRACED PADDIES", "RICE MILL", "MARSH", "LEVEE", "FLOODGATE"], "English banners")
	Game.settings.locale = "ko"
	Game.apply_settings()
	check_eq(tr("S2_SECTION_3"), "늪", "Korean banner")
	Game.settings.locale = previous
	Game.apply_settings()
	var world := stage("boss", true, 2)
	var banners := []
	world.director.section_changed.connect(func(section: int) -> void: banners.append(section))
	await wait_until(func() -> bool: return banners.size() > 0, 60 * 6)
	check_eq(banners, [Stage2.Section.ARENA], "the director announces stage 2's sections")
