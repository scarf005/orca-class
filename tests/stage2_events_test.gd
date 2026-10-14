extends TestCase
## City pacing, loadout choices, boss flow and stage-local results.

var _saved_bests := {}
var _saved_path := ""
var _results: Results
var _screen: GameScreen


func begin(name: String) -> void:
	super.begin(name)
	_saved_bests = Game.bests
	_saved_path = Game.bests_path
	Game.bests = {}
	Game.bests_path = "user://stage2_events_test.cfg"
	Game.stage = 2
	Game.difficulty = Game.Difficulty.NORMAL


func cleanup(restore_environment := false) -> void:
	if is_instance_valid(_results):
		remove_child(_results)
		_results.queue_free()
		_results = null
	if is_instance_valid(_screen):
		remove_child(_screen)
		_screen.queue_free()
		_screen = null
	DirAccess.remove_absolute(Game.bests_path)
	Game.bests = _saved_bests
	Game.bests_path = _saved_path
	Game.stage = 1
	Game.difficulty = Game.Difficulty.NORMAL
	super.cleanup(restore_environment)


func test_events_are_ordered_and_kinds_are_available() -> void:
	for hard in [false, true]:
		var previous := -INF
		var events := Stage2.new().events(hard)
		check(not events.is_empty(), "city has encounters")
		for event in events:
			check(event.d >= previous and event.d < Stage2.LENGTH, "events advance within the course")
			previous = event.d
			if event.has("kind"):
				check(Director.ENEMY_SCRIPTS.has(event.kind), "%s is registered" % event.kind)
				if Director.ENEMY_SCRIPTS.has(event.kind):
					check(ResourceLoader.exists(Director.ENEMY_SCRIPTS[event.kind]), "%s script exists" % event.kind)


func test_quiet_opening_and_release_keep_the_elite_count_low() -> void:
	var city := Stage2.new().events(false)
	var waves := city.filter(func(e: Dictionary) -> bool: return e.type == "wave")
	check(not waves.is_empty(), "city has hunters")
	if waves.is_empty():
		return
	check(waves[0].d <= 60.0 and waves[0].kind == "fpv" and waves[0].get("count", 1) == 1, "the first contact is a lone drone within seconds of the start")
	check(waves[1].d >= 180.0 and waves[1].kind == "abel" and waves[1].get("count", 1) == 1, "the first hunter teaches the LOSAT alone")
	var city_count := 0
	var farm_count := 0
	for event in waves:
		city_count += int(event.get("count", 1))
		check(event.d < 3290.0, "final bay squad leaves a long supply-only boss approach")
	for event in Stage1.new().events(false):
		if event.type == "wave":
			farm_count += int(event.get("count", 1))
	check(city_count < farm_count / 2, "elite city sends less than half the scripted stage-one enemies")


func test_supplies_offer_stage_one_special_rounds_before_plaza() -> void:
	var supplies := {}
	for event in Stage2.new().events(false):
		if event.d >= Stage2.PLAZA_D - 110.0:
			continue
		if event.type == "pickup":
			supplies[event.id] = true
		if event.has("drop"):
			supplies[event.drop] = true
		if event.has("reward"):
			supplies[event.reward] = true
	for round: Armament.Round in Armament.OFFERED:
		var id: String = Armament.ROUND_IDS[round]
		check(supplies.has(id), "%s is offered before the missile-countering midboss" % id)


func test_city_scripted_pickups_load_only_stage_one_special_rounds() -> void:
	var offered := Armament.OFFERED.map(func(round: Armament.Round) -> String: return Armament.ROUND_IDS[round])
	for hard in [false, true]:
		var world := stage("", false, 2)
		world.process_mode = Node.PROCESS_MODE_DISABLED
		for event in Stage2.new().events(hard):
			for key in ["drop", "reward"]:
				var id: String = event.get(key, "")
				check(id != "rws", "city rewards never mount CIWS")
				if id in Armament.ROUND_IDS.values():
					check(id in offered, "city %s offers a stage-one special round" % key)
			if event.type != "pickup":
				continue
			check(event.id != "rws", "city placed loot never mounts CIWS")
			world.director._fire(event)
			var pickup: Pickup = world.pickups.back()
			if event.id in Armament.ROUND_IDS.values():
				check(pickup.id in offered, "%s spawns as a stage-one special round" % event.id)
				world.player.collect(pickup)
				check_eq(world.player.current_round, Armament.round_from_id(event.id), "collecting the city pickup loads its round")
				check_eq(world.player.round_count, Armament.MAGAZINE[world.player.current_round], "city pickup loads the shared magazine size")


func test_boss_events_follow_checkpoints_and_do_not_overlap_waves() -> void:
	var events := Stage2.new().events(false)
	for spec in [{"type": "midboss", "kind": "hovercraft", "name": "midboss", "d": Stage2.PLAZA_D - 110.0}, {"type": "boss", "kind": "hi_mo", "name": "boss", "d": Stage2.BAY_D - 110.0}]:
		var fights := events.filter(func(e: Dictionary) -> bool: return e.type == spec.type)
		check_eq(fights.size(), 1, "one %s encounter" % spec.type)
		if fights.is_empty():
			continue
		check_eq(fights[0].kind, spec.kind, "correct city boss")
		check_near(fights[0].d, spec.d, 0.01, "boss starts inside its approach")
		check(events.any(func(e: Dictionary) -> bool: return e.type == "checkpoint" and e.name == spec.name and e.d < spec.d), "checkpoint unlock precedes the fight")
		check(not events.any(func(e: Dictionary) -> bool: return e.type == "wave" and absf(e.d - spec.d) < 100.0), "boss gets a clean entrance")


func test_hovercraft_is_first_seen_at_the_range_every_other_hunter_is_revealed() -> void:
	var world := stage("", false, 2)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var event: Dictionary = Stage2.new().events(false).filter(func(e: Dictionary) -> bool: return e.type == "midboss")[0]
	world.rail.d = event.d
	world.player._place(event.d)
	world.director._start_midboss(event)
	var ahead := Course.to_course(world.boss.global_position).x - Course.to_course(world.player.global_position).x
	check(ahead >= 150.0, "the plaza midboss appears %.0f m ahead, not out of open air" % ahead)


func test_music_matches_sections_and_bay_leaves_boss_phase_alone() -> void:
	var city := Stage2.new()
	for section in [Stage2.Section.BOULEVARD, Stage2.Section.VIADUCT]:
		check_eq(city.music(section), "res://assets/music/stage2_boulevard.ogg", "opening and viaduct theme")
	check_eq(city.music(Stage2.Section.PLAZA), "res://assets/music/stage2_hovercraft.ogg", "plaza theme")
	check_eq(city.music(Stage2.Section.CANYON), "res://assets/music/stage2_canyon.ogg", "canyon theme")
	check_eq(city.music(Stage2.Section.BAY), "", "bay does not replace boss phase music")
	var bosses := city.events(false).filter(func(e: Dictionary) -> bool: return e.type == "boss")
	check(not bosses.is_empty() and bosses[0].get("music", "") == "res://assets/music/stage2_boss.ogg", "arena starts the city boss theme")


func test_hard_adds_flank_pressure_without_filling_releases() -> void:
	var city := Stage2.new()
	var normal := city.events(false)
	var hard := city.events(true)
	check(hard.size() > normal.size(), "hard remixes the build beats")
	for event in hard:
		if event.type == "wave":
			check(event.d >= 30.0 and event.d < 3290.0, "hard preserves opening and bay release")
			check_eq(event.get("hard_scale", 1.4), 1.0, "elite formations do not silently double on hard")


func test_city_slow_driving_does_not_trigger_fpv_pursuit() -> void:
	var world := stage("", false, 2)
	world.director.set_process(false)
	world.rail.speed = 0.0
	world.player.local_velocity = Vector2.ZERO
	world.director._update_pursuit(Director.PURSUIT_FILL + 1.0)
	check(world.enemies.is_empty(), "taking time to use city cover does not call drone swarms")
	check_near(world.director.slow_meter, 0.0, 0.001, "city pursuit meter stays empty")


func test_city_results_store_only_city_bests_and_offer_retry_and_title() -> void:
	_results = Results.new()
	_results.stats = RunStats.new()
	_results.stats.score = 12345
	add_child(_results)
	check_eq(Game.bests.get(Game.best_key("score", 2), 0), 12345, "ranked city result saves city best")
	check(not Game.bests.has(Game.best_key("score", 1)), "city result leaves stage-one best alone")
	_results._process(4.0)
	check_eq(_results._menu.items.size(), 2, "final supported stage offers retry and title, not stage three")
	var actions := []
	_results.retry.connect(func() -> void: actions.append("retry"))
	_results.title_pressed.connect(func() -> void: actions.append("title"))
	for item: Menu.Item in _results._menu.items:
		item.action.call()
	check_eq(actions, ["retry", "title"], "both final-stage menu actions reach their flow signals")


func test_opening_hunter_is_outside_cover_and_cannot_fire_through_it() -> void:
	var world := stage("", false, 2)
	world.director.set_process(false)
	var event: Dictionary = Stage2.new().events(false).filter(func(e: Dictionary) -> bool: return e.type == "wave" and e.kind == "abel")[0]
	world.rail.d = event.d
	world.player._place(event.d)
	world.camera.snap()
	world.director.scenery.stream(event.d, 100000)
	world.camera.follow(0.0)
	var hunter := world.director.spawn_wave(event)[0] as Abel
	check(not world.director.scenery.line_blocked(world.player.hit_center(), hunter.hit_center()), "first LOSAT hunter offers a clear shot inside the street")
	check(not world.director.scenery.line_blocked(hunter.hit_center(), hunter.hit_center()), "hunter is not embedded in the building")
	check(Course.to_course(hunter.global_position).x - event.d > 160.0, "the hunter spawns out in the haze, not mid-street")
	hunter.global_position = Course.ground_at(event.d + 110.0, float(event.u))
	var shots := world.projectiles.size()
	hunter._attack_timer = 0.0
	hunter.behave(0.01)
	check(hunter.telegraphing(), "visible street hunter warns before attacking")
	check_eq(world.projectiles.size(), shots, "cover blocks the first attack")


func test_boss_deaths_resume_then_clear() -> void:
	for type in ["midboss", "boss"]:
		var event: Dictionary = Stage2.new().events(false).filter(func(e: Dictionary) -> bool: return e.type == type)[0]
		var world := stage("", false, 2)
		world.director.set_process(false)
		world.rail.d = event.d
		var clears := [0]
		world.stage_cleared.connect(func() -> void: clears[0] += 1)
		world.director._fire(event)
		check_eq(world.rail.mode, Rail.Mode.ARENA, "both city bosses permit all-range dodging")
		check(world.boss != null, "boss is announced to the HUD")
		world.boss.died.emit(world.boss)
		await frames(100)
		if type == "midboss":
			check_eq(world.rail.mode, Rail.Mode.RAIL, "midboss death resumes the course")
			check_eq(clears[0], 0, "midboss cannot clear the stage")
		else:
			check_eq(clears[0], 1, "boss death clears the stage once")


func test_city_clear_screen_retries_the_same_stage_or_returns_to_title() -> void:
	_screen = GameScreen.new()
	_screen.stage = 2
	add_child(_screen)
	_screen.world.director.set_process(false)
	_screen.world.player.invulnerable = true
	var actions := []
	_screen.restart.connect(func(checkpoint: String) -> void: actions.append(["retry", checkpoint, Game.stage]))
	_screen.quit_to_title.connect(func() -> void: actions.append(["title"]))
	_screen.world.stage_cleared.emit()
	check(await wait_until(func() -> bool: return _screen._results != null, 180), "clear signal reaches the results screen")
	if _screen._results == null:
		return
	check(not _screen._results.has_next_stage, "city clear cannot start unsupported stage three")
	_screen._results._process(4.0)
	for item: Menu.Item in _screen._results._menu.items:
		item.action.call()
	check_eq(actions, [["retry", "", 2], ["title"]], "clear retry starts the whole city; title uses the title flow")


func test_stage_one_results_keep_the_next_stage_action() -> void:
	Game.stage = 1
	_results = Results.new()
	_results.stats = RunStats.new()
	_results.has_next_stage = true
	add_child(_results)
	_results._process(4.0)
	check_eq(_results._menu.items.size(), 3, "stage one still offers next stage, retry and title")
	var next := [false]
	_results.next_stage.connect(func() -> void: next[0] = true)
	_results._menu.items[0].action.call()
	check(next[0], "next-stage menu action reaches its flow signal")
	check_eq(_results.clear_heading(), tr("STAGE_CLEAR"), "stage-one heading is unchanged")


func test_checkpoint_unlock_selection_and_game_over_retry_stay_in_city() -> void:
	for checkpoint in ["midboss", "boss"]:
		_screen = GameScreen.new()
		_screen.stage = 2
		add_child(_screen)
		_screen.world.process_mode = Node.PROCESS_MODE_DISABLED
		_screen.world.director._fire({"type": "checkpoint", "name": checkpoint})
		check(Game.is_checkpoint_unlocked(checkpoint, 2), "reached city checkpoint is unlocked")
		check(not Game.is_checkpoint_unlocked(checkpoint, 1), "city unlock does not leak to stage one")
		var select := StageSelect.new()
		select.selected_stage = 2
		var selected := []
		select.selected.connect(func(_difficulty: Game.Difficulty, name: String, number: int) -> void: selected.append([name, number]))
		select._activate_checkpoint(select._checkpoints().find(checkpoint))
		check_eq(selected, [[checkpoint, 2]], "stage selection starts the unlocked city checkpoint")
		select.free()
		var retries := []
		_screen.restart.connect(func(name: String) -> void: retries.append(name))
		_screen.world.game_over.emit()
		check(await wait_until(func() -> bool: return _screen._overlay != null, 180), "game over offers checkpoint retry")
		if _screen._overlay != null:
			_screen._overlay.items[0].action.call()
			check_eq(retries, [checkpoint], "continue retries the reached checkpoint")
			_screen._close_overlay()
		get_tree().paused = false
		remove_child(_screen)
		_screen.queue_free()
		_screen = null
		await frames(1)
		var world := stage(checkpoint, false, 2)
		world.process_mode = Node.PROCESS_MODE_DISABLED
		check_near(world.rail.d, 1660.0 if checkpoint == "midboss" else 3390.0, 0.01, "retry loads the city approach")
		check(world.player.coax_tier >= 2 and not world.player.modules.laser_online(), "retry restores the city coax without CIWS")
		check(not world.stats.ranked, "retry remains unranked")


func test_city_checkpoint_clear_retries_the_selected_checkpoint() -> void:
	for checkpoint in ["midboss", "boss"]:
		_screen = GameScreen.new()
		_screen.stage = 2
		_screen.checkpoint = checkpoint
		add_child(_screen)
		_screen.world.process_mode = Node.PROCESS_MODE_DISABLED
		var retries := []
		_screen.restart.connect(func(name: String) -> void: retries.append(name))
		_screen.world.stage_cleared.emit()
		check(await wait_until(func() -> bool: return _screen._results != null, 180), "checkpoint clear reaches results")
		if _screen._results != null:
			_screen._results._process(4.0)
			_screen._results._menu.items[0].action.call()
			check_eq(retries, [checkpoint], "results retry preserves the checkpoint sortie")
		remove_child(_screen)
		_screen.queue_free()
		_screen = null
		await frames(1)


func test_checkpoint_results_do_not_save_bests() -> void:
	_results = Results.new()
	_results.stats = RunStats.new()
	_results.stats.ranked = false
	_results.stats.score = 99999
	add_child(_results)
	check(Game.bests.is_empty(), "checkpoint results cannot overwrite ranked stage bests")


func test_clear_heading_is_localized_for_the_completed_stage() -> void:
	var locale := TranslationServer.get_locale()
	for language in ["ko", "en"]:
		TranslationServer.set_locale(language)
		_results = Results.new()
		_results.stats = RunStats.new()
		add_child(_results)
		check(_results.has_method("clear_heading"), "results exposes its localized completed-stage heading")
		if _results.has_method("clear_heading"):
			check_eq(_results.call("clear_heading"), tr("S2_STAGE_CLEAR"), "city heading uses city localization")
			Game.stage = 1
			check_eq(_results.call("clear_heading"), tr("S2_STAGE_CLEAR"), "completed-stage heading survives a next-stage selection")
		remove_child(_results)
		_results.queue_free()
		_results = null
		Game.stage = 2
	TranslationServer.set_locale(locale)


func _street_hind(world: World, ahead: float) -> Hind:
	world.director.events.clear()
	world.rail.mode = Rail.Mode.HOLD
	var tank := world.player
	var d := Course.to_course(tank.global_position).x + ahead
	var heli := Hind.new()
	heli.position = Course.to_world(d, 0.0, tank.global_position.y + 5.0)
	world.add_enemy(heli)
	heli._attack_timer = 0.0
	return heli


func test_hind_holds_its_station_for_the_whole_fight_instead_of_leaving_after_its_pacing_pass() -> void:
	var world := stage("", false, 2)
	var heli := _street_hind(world, 85.0 * Course.stage.standoff)
	heli.age = 60.0
	heli.behave(0.1)
	check(not heli.dead, "a stage 2 hunter does not fly off unkilled")
	var before := world.projectiles.size()
	for i in 80:
		heli.behave(0.1)
	check(world.projectiles.size() > before, "late in the fight it still attacks")


func test_hind_flies_to_a_lane_with_a_clear_shot_instead_of_firing_into_a_roadside_prop() -> void:
	var world := stage("", false, 2)
	var heli := _street_hind(world, 85.0 * Course.stage.standoff)
	var shop := Prop.new()
	shop.setup("city_shop", PropKit.mesh("city_shop", 0), 4.5, 7.5, 1000.0)
	shop.position = world.player.global_position.lerp(heli.global_position, 0.7)
	shop.position.y = world.player.global_position.y
	world.props.add_child(shop)
	check(CityCover.blocker(heli._chin_muzzle.global_position, world.player.hit_center()) == shop, "the shop screens the straight shot")
	var before := world.projectiles.size()
	for i in 120:
		heli.behave(0.1)
		if world.projectiles.size() > before:
			break
	check(world.projectiles.size() > before, "the gunship eventually fires")
	check(CityCover.blocker(heli._chin_muzzle.global_position, world.player.hit_center()) == null, "it fires only along a line free of the prop")


func test_hind_keeps_station_ahead_of_a_driving_tank_and_attacks_every_few_seconds() -> void:
	var world := stage("", false, 2)
	var heli := _street_hind(world, 85.0 * Course.stage.standoff)
	world.rail.speed = 23.0
	var tank := world.player
	var d := Course.to_course(tank.global_position).x
	var bursts := 0
	var last := world.projectiles.size()
	var worst := INF
	for i in 400:
		d += 23.0 * 0.025
		tank.global_position = Course.to_world(d, 0.0, tank.global_position.y)
		heli.behave(0.025)
		worst = minf(worst, Course.to_course(heli.global_position).x - d)
		bursts += maxi(world.projectiles.size() - last, 0)
		last = world.projectiles.size()
	check(worst >= 65.0 * Course.stage.standoff, "it never falls behind its firing band (closest %.0f m)" % worst)
	check(bursts >= 10, "over ten driven seconds it lands two attacks, not one warning after another (%d rounds)" % bursts)


func test_ground_hunter_keeps_its_firing_band_ahead_of_a_driving_tank_and_shoots() -> void:
	var world := stage("", false, 2)
	world.director.events.clear()
	world.rail.mode = Rail.Mode.HOLD
	var tank := world.player
	var d := Course.to_course(tank.global_position).x
	var kain := Kain.new()
	kain.position = Course.ground_at(d + 95.0, 0.0)
	world.add_enemy(kain)
	kain._attack_timer = 0.0
	var worst := INF
	var rounds := 0
	var last := world.projectiles.size()
	for i in 400:
		d += 29.0 * 0.025
		tank.global_position = Course.to_world(d, 0.0, tank.global_position.y)
		kain.behave(0.025)
		worst = minf(worst, Course.to_course(kain.global_position).x - d)
		rounds += maxi(world.projectiles.size() - last, 0)
		last = world.projectiles.size()
	# Its firing spot is re-picked every 0.25 s, so a 29 m/s tank can gain about 7 m on the band edge in between.
	check(worst >= 65.0 * Course.stage.standoff - 29.0 * 0.25, "a tank doing 29 m/s never overruns it, and any dip out of the band is recovered (closest %.0f m)" % worst)
	check(rounds >= 6, "it gets its shots off during ten driven seconds (%d rounds)" % rounds)
