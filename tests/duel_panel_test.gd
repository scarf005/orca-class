extends TestCase


func _panel() -> DuelPanel:
	var panel := DuelPanel.new()
	add_child(panel)
	panel.show()
	return panel


func _click(button: Button) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	get_viewport().push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = motion.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
		await frames(1)


func test_every_tuning_row_appears_once_in_a_collapsed_group() -> void:
	var panel := _panel()
	var sections: VBoxContainer = panel.get_child(0).get_child(0)
	var labels: Array[String] = []
	check_eq(sections.get_child_count(), DuelPanel.GROUPS.size() * 2, "each group has a header and grid")
	for i in DuelPanel.GROUPS.size():
		var header: Button = sections.get_child(i * 2)
		var grid: GridContainer = sections.get_child(i * 2 + 1)
		check_eq(header.text, "+ " + DuelPanel.GROUPS.keys()[i], "header identifies its group")
		check(not grid.visible, "group starts collapsed")
		check_eq(header.focus_mode, Control.FOCUS_NONE, "headers leave Tab for the panel")
		for index in range(0, grid.get_child_count(), 3):
			var label: Label = grid.get_child(index)
			labels.append(label.text)
			check_eq(grid.get_child(index + 1).focus_mode, Control.FOCUS_NONE, "sliders leave Tab for the panel")
	var rows: Array = GameTuning.new()._rows
	check_eq(labels.size(), rows.size(), "no tuning rows are added or omitted")
	for row: Array in rows:
		check_eq(labels.count(row[0]), 1, "exactly one control for " + row[0])
	panel.queue_free()
	await frames(1)


func test_clicking_headers_toggles_only_their_group_and_preserves_tab_state() -> void:
	var panel := _panel()
	await frames(2)
	var sections: VBoxContainer = panel.get_child(0).get_child(0)
	var first: Button = sections.get_child(0)
	var second: Button = sections.get_child(2)
	var first_grid: GridContainer = sections.get_child(1)
	var second_grid: GridContainer = sections.get_child(3)
	await _click(first)
	check(first_grid.visible, "click expands first group")
	check_eq(first.text, "- Duel", "expanded header shows collapse marker")
	check(not second_grid.visible, "other group stays collapsed")
	await _click(second)
	check(first_grid.visible and second_grid.visible, "groups can be open independently")
	await _click(first)
	check(not first_grid.visible and second_grid.visible, "click collapses only its group")
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	panel._input(tab)
	check(not panel.visible and not get_tree().paused, "Tab closes and resumes")
	panel._input(tab)
	check(panel.visible and get_tree().paused, "Tab opens and pauses")
	check(not first_grid.visible and second_grid.visible, "Tab preserves expanded groups")
	get_tree().paused = false
	panel.queue_free()
	await frames(1)
