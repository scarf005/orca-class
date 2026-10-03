extends TestCase
## The duel prototype: a held rail and its live tuning panel.


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
