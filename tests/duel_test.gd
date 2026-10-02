extends TestCase
## The duel prototype: a held rail and its live tuning panel.


func _tab() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true
	Input.parse_input_event(key)


func test_tab_opens_and_closes_the_tuning_panel() -> void:
	var panel := DuelPanel.new()
	add_child(panel)
	await frames(2)
	check(not panel.visible, "closed at the start")
	_tab()
	await frames(2)
	check(panel.visible and get_tree().paused, "Tab opens it and pauses")
	panel.find_children("*", "HSlider", true, false)[0].grab_focus() # As after dragging one.
	_tab()
	await frames(2)
	check(not panel.visible and not get_tree().paused, "Tab again closes it, even with sliders on screen")
	get_tree().paused = false
	panel.queue_free()
