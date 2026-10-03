extends TestCase
## The duel prototype: a held rail and its live tuning panel.


class TestTuning extends GameTuning:
	var saved := false

	func save_values() -> void:
		saved = true


func test_duel_difficulty_is_scoped_to_the_world() -> void:
	var saved := GameTuning.duel_difficulty
	var normal_difficulty := Game.difficulty
	Game.difficulty = Game.Difficulty.HARD
	for mode in GameTuning.DUEL_DIFFICULTIES:
		GameTuning.duel_difficulty = mode
		var world := stage("duel")
		world.process_mode = Node.PROCESS_MODE_DISABLED
		check_eq(Game.difficulty, mode, "duel uses its selected difficulty")
		check_eq(world.director._hard, mode == Game.Difficulty.HARD, "director initializes at duel difficulty")
		check_near(Game.telegraph_scale(), 2.0 if mode == Game.Difficulty.EASY else 1.0, 0.001, "duel uses difficulty rules")
		world.queue_free()
		await frames(1)
		check_eq(Game.difficulty, Game.Difficulty.HARD, "leaving duel preserves normal difficulty")
		world = stage()
		world.process_mode = Node.PROCESS_MODE_DISABLED
		check_eq(Game.difficulty, Game.Difficulty.HARD, "normal stage ignores duel difficulty")
		world.queue_free()
		await frames(1)
	Game.difficulty = normal_difficulty
	GameTuning.duel_difficulty = saved


func test_duel_difficulty_restarts_only_when_tuning_closes() -> void:
	var saved := GameTuning.duel_difficulty
	GameTuning.duel_difficulty = Game.Difficulty.NORMAL
	var normal_difficulty := Game.difficulty
	var screen := GameScreen.new()
	screen.checkpoint = "duel"
	add_child(screen)
	screen.world.process_mode = Node.PROCESS_MODE_DISABLED
	var panel: DuelPanel = screen.find_children("*", "DuelPanel", true, false)[0]
	var tuning := TestTuning.new()
	panel._tuning = tuning
	var restarts: Array[String] = []
	screen.restart.connect(func(checkpoint: String) -> void:
		check(tuning.saved, "settings saved before restart")
		restarts.append(checkpoint))
	var row := tuning._rows.find(tuning._rows.filter(func(r: Array) -> bool: return r[0] == "Duel difficulty")[0])
	var slider: HSlider = panel._grid.get_child(row * 3 + 1)
	check_eq(slider.min_value, 0.0, "slider starts at Easy")
	check_eq(slider.max_value, 2.0, "slider ends at Hard")
	check_eq(slider.step, 1.0, "slider selects discrete difficulties")
	_tab()
	await frames(1)
	slider.value = 0
	slider.value = 1
	_tab()
	await frames(1)
	check_eq(restarts.size(), 0, "returning to the original difficulty does not restart")
	_tab()
	await frames(1)
	for index in [0, 1, 2]:
		tuning.saved = false
		slider.value = index
		check_eq(GameTuning.duel_difficulty, GameTuning.DUEL_DIFFICULTIES[index], "slider stores selected difficulty")
		var label: Label = panel._grid.get_child(row * 3 + 2)
		check_eq(label.text, ["Easy", "Normal", "Hard"][index], "slider shows difficulty name")
		await frames(1)
	check_eq(restarts.size(), 0, "slider changes never interrupt tuning")
	check(panel.visible and get_tree().paused, "tuning stays open while adjusting difficulty")
	_tab()
	await frames(1)
	check_eq(restarts, ["duel"], "closing tuning restarts once with the final difficulty")
	check(not panel.visible and not get_tree().paused, "Tab closes tuning before restarting")
	_tab()
	_tab()
	await frames(1)
	check_eq(restarts.size(), 1, "closing without a difficulty change does not restart")
	screen.queue_free()
	await frames(1)
	check_eq(Game.difficulty, normal_difficulty, "slider leaves normal difficulty unchanged")
	GameTuning.duel_difficulty = saved


func test_duel_restart_preserves_speed_when_the_previous_world_exits() -> void:
	var saved := GameTuning.duel_speed
	GameTuning.duel_speed = 0.5
	var previous := stage("duel")
	previous.process_mode = Node.PROCESS_MODE_DISABLED
	previous.queue_free()
	var current := stage("duel")
	current.process_mode = Node.PROCESS_MODE_DISABLED
	await frames(1)
	check_eq(World.current, current, "new duel remains the current world")
	check_near(Engine.time_scale, 0.5, 0.0001, "old duel teardown does not reset the restarted duel speed")
	GameTuning.duel_speed = saved


func test_duel_speed_survives_hitstop_and_leaves_normal_stages_alone() -> void:
	var saved := GameTuning.duel_speed
	GameTuning.duel_speed = 0.5
	var world := stage("duel")
	world.set_process(false)
	world.director.set_process(false)
	world.player.set_process(false)
	check_near(Engine.time_scale, 0.5, 0.0001, "duel starts at the selected speed")
	world.hitstop(0.1)
	check_near(Engine.time_scale, 0.025, 0.0001, "hitstop scales with duel speed")
	world._process(0.005)
	check_near(Engine.time_scale, 0.5, 0.0001, "hitstop restores duel speed")
	world.queue_free()
	await frames(1)
	check_near(Engine.time_scale, 1.0, 0.0001, "leaving duel restores normal speed")
	world = stage()
	check_near(Engine.time_scale, 1.0, 0.0001, "normal stages ignore the duel setting")
	GameTuning.duel_speed = saved


func test_duel_speed_slider_applies_live_and_saves() -> void:
	var saved := GameTuning.duel_speed
	var world := stage("duel")
	world.set_process(false)
	world.director.set_process(false)
	world.player.set_process(false)
	var tuning := TestTuning.new()
	var panel := DuelPanel.new()
	panel._tuning = tuning
	add_child(panel)
	var row := tuning._rows.find(tuning._rows.filter(func(r: Array) -> bool: return r[0] == "Duel speed (x)")[0])
	var slider: HSlider = panel._grid.get_child(row * 3 + 1)
	for speed in [0.1, 2.0, 1.0]:
		slider.value = speed
		check_near(GameTuning.duel_speed, speed, 0.0001, "slider changes stored speed")
		check_near(Engine.time_scale, speed, 0.0001, "slider changes duel speed immediately")
	world.hitstop(0.1)
	slider.value = 0.5
	check_near(Engine.time_scale, 0.025, 0.0001, "changing speed preserves active hitstop")
	world._process(0.005)
	check_near(Engine.time_scale, 0.5, 0.0001, "hitstop restores the newly selected speed")
	check(tuning.saved, "slider saves settings")
	panel.queue_free()
	GameTuning.duel_speed = saved


func test_missile_turn_options_have_independent_setters() -> void:
	var panel := GameTuning.new()
	var options := {
		"ATGM turn rate increment rate (rad/s)": 3.5,
		"Micro-Missile turn rate (rad/s)": 8.0,
		"Micro-missile turn rate increment rate (rad/s)": 5.5,
	}
	var atgm_turn := Armament.ATGM_TURN
	var originals: Dictionary = {}
	for row: Array in panel._rows:
		if options.has(row[0]):
			originals[row[0]] = row[1].call()
			row[2].call(options[row[0]])
	for row: Array in panel._rows:
		if options.has(row[0]):
			check_near(row[1].call(), options[row[0]], 0.001, row[0])
	check_eq(originals.size(), 3, "all three requested options exist")
	check_near(Armament.ATGM_TURN, atgm_turn, 0.001, "micro tuning leaves ATGM turn rate alone")
	for row: Array in panel._rows:
		if originals.has(row[0]):
			row[2].call(originals[row[0]])


func _tab() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true
	Input.parse_input_event(key)


func test_micro_initial_split_row_controls_the_launch_angle() -> void:
	var panel := GameTuning.new()
	var rows := panel._rows.filter(func(row: Array) -> bool: return row[0] == "Micro-missile intial split (rad)")
	check_eq(rows.size(), 1, "initial split option exists once")
	if not rows.is_empty():
		var row: Array = rows[0]
		var saved := Armament.MICRO_INITIAL_SPLIT
		check_eq(row[3], 0.0, "supports a straight launch")
		check_near(row[4], PI / 2.0, 0.0001, "supports a perpendicular launch")
		row[2].call(0.4)
		check_near(Armament.MICRO_INITIAL_SPLIT, 0.4, 0.0001, "setter controls launch split")
		check_near(row[1].call(), 0.4, 0.0001, "getter reads launch split")
		Armament.MICRO_INITIAL_SPLIT = saved


func test_tab_opens_and_closes_the_tuning_panel() -> void:
	var panel := DuelPanel.new()
	add_child(panel)
	await frames(2)
	check(not panel.visible, "closed at the start")
	_tab()
	await frames(2)
	check(panel.visible and get_tree().paused, "Tab opens it and pauses")
	var slider: HSlider = panel.find_children("*", "HSlider", true, false)[0]
	slider.focus_mode = Control.FOCUS_ALL
	slider.grab_focus()
	_tab()
	await frames(2)
	check(not panel.visible and not get_tree().paused, "Tab again closes it, even with sliders on screen")
	get_tree().paused = false
	panel.queue_free()
