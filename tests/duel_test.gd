extends TestCase
## The duel prototype: a held rail and its live tuning panel.


class TestTuning extends GameTuning:
	var saved := false

	func save_values() -> void:
		saved = true


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
