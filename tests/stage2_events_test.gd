extends TestCase
## City pacing, loadout choices and stage-local results, without depending on pending bosses.

var _saved_bests := {}
var _saved_path := ""
var _results: Results


func begin(name: String) -> void:
	super.begin(name)
	_saved_bests = Game.bests
	_saved_path = Game.bests_path
	Game.bests = {}
	Game.bests_path = "user://stage2_events_test.cfg"
	Game.stage = 2
	Game.difficulty = Game.Difficulty.NORMAL


func cleanup() -> void:
	if is_instance_valid(_results):
		remove_child(_results)
		_results.queue_free()
		_results = null
	DirAccess.remove_absolute(Game.bests_path)
	Game.bests = _saved_bests
	Game.bests_path = _saved_path
	Game.stage = 1
	Game.difficulty = Game.Difficulty.NORMAL
	super.cleanup()


func test_events_are_ordered_and_kinds_are_available_or_pending() -> void:
	for hard in [false, true]:
		var previous := -INF
		var events := Stage2.new().events(hard)
		check(not events.is_empty(), "city has encounters")
		for event in events:
			check(event.d >= previous and event.d < Stage2.LENGTH, "events advance within the course")
			previous = event.d
			if event.has("kind") and event.kind not in ["hovercraft", "landsword"]:
				check(Director.ENEMY_SCRIPTS.has(event.kind), "%s is registered" % event.kind)
				if Director.ENEMY_SCRIPTS.has(event.kind):
					check(ResourceLoader.exists(Director.ENEMY_SCRIPTS[event.kind]), "%s script exists" % event.kind)


func test_quiet_opening_and_release_keep_the_elite_count_low() -> void:
	var city := Stage2.new().events(false)
	var waves := city.filter(func(e: Dictionary) -> bool: return e.type == "wave")
	check(not waves.is_empty(), "city has hunters")
	if waves.is_empty():
		return
	check(waves[0].d >= 180.0 and waves[0].kind == "abel" and waves[0].get("count", 1) == 1, "quiet opening teaches one LOSAT hunter")
	var city_count := 0
	var farm_count := 0
	for event in waves:
		city_count += int(event.get("count", 1))
		check(event.d < 3150.0, "bay approach gives the player breathing room")
	for event in Stage1.new().events(false):
		if event.type == "wave":
			farm_count += int(event.get("count", 1))
	check(city_count < farm_count / 2, "elite city sends less than half the scripted stage-one enemies")


func test_supplies_offer_missiles_and_kinetic_counters_before_plaza() -> void:
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
	for id in ["atgm", "micro", "heat", "apfsds"]:
		check(supplies.has(id), "%s is offered before the missile-countering midboss" % id)


func test_boss_events_follow_checkpoints_and_do_not_overlap_waves() -> void:
	var events := Stage2.new().events(false)
	for spec in [{"type": "midboss", "kind": "hovercraft", "name": "midboss", "d": Stage2.PLAZA_D - 110.0}, {"type": "boss", "kind": "landsword", "name": "boss", "d": Stage2.BAY_D - 110.0}]:
		var fights := events.filter(func(e: Dictionary) -> bool: return e.type == spec.type)
		check_eq(fights.size(), 1, "one %s encounter" % spec.type)
		if fights.is_empty():
			continue
		check_eq(fights[0].kind, spec.kind, "correct city boss")
		check_near(fights[0].d, spec.d, 0.01, "boss starts inside its approach")
		check(events.any(func(e: Dictionary) -> bool: return e.type == "checkpoint" and e.name == spec.name and e.d < spec.d), "checkpoint unlock precedes the fight")
		check(not events.any(func(e: Dictionary) -> bool: return e.type == "wave" and absf(e.d - spec.d) < 100.0), "boss gets a clean entrance")


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
			check(event.d >= 180.0 and event.d < 3150.0, "hard preserves opening and bay release")
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
