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
	await frames(2)
	check_near(world.environment.fog_depth_end, Course.stage.look_at(world.rail.d).fog_end, 0.001, "fog from the stage's look")
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
	var spawned := await wait_until(func() -> bool: return world.boss is Combine, 60 * 10)
	check(spawned, "the mid-boss appears in the mill yard")
	check_eq(world.rail.mode, Rail.Mode.HOLD, "the rail holds")
	check(world.boss.global_position.distance_to(Course.ground_at(Course.stage.midboss_d, 0.0)) < 30.0, "at the mill")
	await frames(300)
	check(world.rail.d <= world.rail.hold_at + 0.5, "never past the hold point")
	var boss := world.boss as Combine
	boss.hp = 1.0
	var hit := Hit.make(Hit.Kind.SHELL, 20.0, boss.hit_center())
	hit.source = world.player
	boss.take_hit(hit)
	check(boss._dying > 0.0, "the killing hit starts the burning wreck")
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


func test_stage_select_has_both_stages_and_preserves_difficulty() -> void:
	_isolate_bests()
	var select := StageSelect.new()
	select.difficulty = Game.Difficulty.HARD
	add_child(select)
	await frames(2)
	check_eq(select.selected_stage, 1, "stage one is initially focused")
	check_eq(select._checkpoints().size(), 0, "fresh bests show no checkpoints")
	var right := InputEventKey.new()
	right.physical_keycode = KEY_D
	right.pressed = true
	select._unhandled_input(right)
	check_eq(select.selected_stage, 2, "A/D moves focus to stage two")
	var started := []
	select.selected.connect(func(chosen: Game.Difficulty, checkpoint: String, stage: int) -> void: started.append([chosen, checkpoint, stage]))
	select._activate(2)
	check_eq(started, [[Game.Difficulty.HARD, "", 2]], "stage two starts on selected difficulty")
	Game.stage = 2
	Game.unlock_checkpoint("midboss")
	select.selected_stage = 2
	check_eq(select._checkpoints(), ["midboss"] as Array[String], "only reached checkpoints appear")
	Game.submit_best("s2_score_hard", 777)
	check_eq(select.best_score(2), 777, "the focused difficulty shows its stage best")
	check(select.MAPS[0] != null and select.MAPS[1] != null, "both map thumbnails load")
	check_eq(select.MAPS[0].get_width(), 256, "stage one map is square")
	check_eq(select.MAPS[1].get_height(), 256, "stage two map is square")
	var checkpoint_started := []
	select.selected.connect(func(chosen: Game.Difficulty, checkpoint: String, stage: int) -> void: checkpoint_started.append([chosen, checkpoint, stage]))
	var down := InputEventKey.new()
	down.physical_keycode = KEY_DOWN
	down.pressed = true
	select._unhandled_input(down)
	var enter := InputEventKey.new()
	enter.physical_keycode = KEY_ENTER
	enter.keycode = KEY_ENTER
	enter.pressed = true
	select._unhandled_input(enter)
	check_eq(checkpoint_started, [[Game.Difficulty.HARD, "midboss", 2]], "keyboard activates an unlocked checkpoint")
	select.focus = StageSelect.Focus.CARD
	var stick_down := InputEventJoypadMotion.new()
	stick_down.axis = JOY_AXIS_LEFT_Y
	stick_down.axis_value = 1.0
	select._unhandled_input(stick_down)
	check_eq(select.focus, StageSelect.Focus.CHECKPOINT, "gamepad down reaches checkpoint choices")
	var stick_up := InputEventJoypadMotion.new()
	stick_up.axis = JOY_AXIS_LEFT_Y
	stick_up.axis_value = -1.0
	select._unhandled_input(stick_up)
	check_eq(select.focus, StageSelect.Focus.CARD, "gamepad up returns to the cards")
	var went_back := [false]
	select.back.connect(func() -> void: went_back[0] = true)
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	select._unhandled_input(escape)
	check(went_back[0], "escape returns to the main menu")
	select.queue_free()
	_restore_bests()


func test_game_screen_clear_retains_next_stage_only_for_stage_one() -> void:
	_isolate_bests()
	for number in [1, 2]:
		var screen := GameScreen.new()
		screen.stage = number
		add_child(screen)
		await frames(3)
		screen.world.stage_cleared.emit()
		await wait_until(func() -> bool: return screen._results != null, 60 * 5)
		check_eq(screen._results.has_next_stage, number == 1, "NEXT STAGE after stage %d" % number)
		if number == 1:
			var restarts := []
			screen.restart.connect(func(name: String) -> void: restarts.append(name))
			screen._results.next_stage.emit()
			check_eq(Game.stage, 2, "NEXT STAGE selects stage two")
			check_eq(restarts, [""], "and restarts from its beginning")
		screen.world.camera.set_process(false)
		screen.world.process_mode = Node.PROCESS_MODE_DISABLED
		remove_child(screen)
		screen.queue_free()
		await frames(3)
	_restore_bests()


func test_title_sorties_open_stage_select_for_both_difficulties() -> void:
	_isolate_bests()
	var title: Control = load("res://scripts/ui/title.gd").new()
	add_child(title)
	await frames(2)
	var labels := _labels(title._menu as Menu)
	check(labels.slice(0, 2) == [tr("MENU_START_NORMAL"), tr("MENU_START_HARD")], "main menu starts with two sortie difficulty entries")
	check(labels.size() <= 5 and labels.count(tr("MENU_START_NORMAL")) == 1 and labels.count(tr("MENU_START_HARD")) == 1, "no per-stage sortie entries remain")
	var started := []
	title.start.connect(func(checkpoint: String) -> void: started.append([checkpoint, Game.stage, Game.difficulty]))
	(title._menu as Menu).items[0].action.call()
	check(title._menu is StageSelect, "normal sortie opens stage select")
	var right := InputEventKey.new()
	right.physical_keycode = KEY_D
	right.keycode = KEY_D
	right.pressed = true
	(title._menu as StageSelect)._unhandled_input(right)
	var enter := InputEventKey.new()
	enter.physical_keycode = KEY_ENTER
	enter.keycode = KEY_ENTER
	enter.pressed = true
	(title._menu as StageSelect)._unhandled_input(enter)
	check_eq(started, [["", 2, Game.Difficulty.NORMAL]], "keyboard starts stage two")
	title._show_main()
	(title._menu as Menu).items[1].action.call()
	check((title._menu as StageSelect).difficulty == Game.Difficulty.HARD, "hard sortie passes difficulty")
	var pad_right := InputEventJoypadMotion.new()
	pad_right.axis = JOY_AXIS_LEFT_X
	pad_right.axis_value = 1.0
	(title._menu as StageSelect)._unhandled_input(pad_right)
	var pad_accept := InputEventJoypadButton.new()
	pad_accept.button_index = JOY_BUTTON_A
	pad_accept.pressed = true
	(title._menu as StageSelect)._unhandled_input(pad_accept)
	check_eq(started[1], ["", 2, Game.Difficulty.HARD], "gamepad starts stage two on hard")
	title.queue_free()
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


func test_stage_2_look_runs_from_night_through_a_thick_marsh_to_dawn() -> void:
	Course.use(2)
	var stage_2 := Course.stage as Stage2
	var night := stage_2.look_at(0.0)
	var dawn := stage_2.look_at(2400.0)
	var marsh := stage_2.look_at(1500.0)
	check(night.sun_energy < dawn.sun_energy, "the light grows toward the arena (%.2f to %.2f)" % [night.sun_energy, dawn.sun_energy])
	check(night.sky_top.get_luminance() < dawn.sky_top.get_luminance(), "the sky brightens")
	check(night.sky_horizon.r < night.sky_horizon.b and dawn.sky_horizon.r > dawn.sky_horizon.b, "from blue to peach at the horizon")
	check(marsh.fog_end < night.fog_end and marsh.fog_end < dawn.fog_end, "the marsh mist is the thickest (%.0f m)" % marsh.fog_end)
	check(marsh.fog_end < stage_2.look_at(1000.0).fog_end and marsh.fog_end < stage_2.look_at(2000.0).fog_end, "thicker than at either side of it")
	check_eq(stage_2.look_at(-100.0), night, "before the start it is night")
	check_eq(stage_2.look_at(9000.0), stage_2.look_at(2300.0), "past the arena it holds")
	var previous := stage_2.look_at(0.0)
	var d := 10.0
	while d < 2400.0:
		var look := stage_2.look_at(d)
		check(absf(look.fog_end - previous.fog_end) < 30.0 and absf(look.sun_energy - previous.sun_energy) < 0.05, "the look changes smoothly at %.0f" % d)
		previous = look
		d += 10.0
	stage_2.dawn = 1.0
	var sunrise := stage_2.look_at(2400.0)
	check(sunrise.sun_energy > dawn.sun_energy and sunrise.sky_top.get_luminance() > dawn.sky_top.get_luminance(), "the sun comes up when dawn is set")
	check_eq(Stage1.new().look_at(1000.0), {}, "stage 1 keeps its constant look")
	check(not Stage1.new().dynamic_look, "and does not ask")


func test_the_world_follows_the_look_along_the_course() -> void:
	var world := stage("", true, 2)
	await frames(2)
	var night_fog := world.environment.fog_depth_end
	world.rail.d = 1500.0
	await frames(2)
	check(world.environment.fog_depth_end < night_fog, "the mist thickens by the marsh (%.0f to %.0f)" % [night_fog, world.environment.fog_depth_end])
	check_near(world.sun.light_energy, Course.stage.look_at(1500.0).sun_energy, 0.01, "and the sun follows")
	var lake := stage("", true, 1)
	await frames(2)
	check_near(lake.environment.fog_depth_end, 420.0, 0.001, "stage 1 keeps its fog")
