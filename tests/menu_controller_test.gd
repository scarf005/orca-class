extends TestCase

const BUTTONS := {
	"ui_accept": JOY_BUTTON_A, "ui_cancel": JOY_BUTTON_B,
	"ui_up": JOY_BUTTON_DPAD_UP, "ui_down": JOY_BUTTON_DPAD_DOWN,
	"ui_left": JOY_BUTTON_DPAD_LEFT, "ui_right": JOY_BUTTON_DPAD_RIGHT,
}


func test_controller_buttons_match_menu_actions() -> void:
	Game.apply_settings()
	for action in BUTTONS:
		var event := Game._button(BUTTONS[action])
		event.pressed = true
		event.pressure = 1.0
		check(event.is_action_pressed(action), "%s has a controller button" % action)


func test_controller_can_select_and_confirm_a_menu_item() -> void:
	var menu := Menu.new()
	var chosen: Array[int] = []
	menu.add_item("First", func() -> void: chosen.append(0))
	menu.add_item("Second", func() -> void: chosen.append(1))
	add_child(menu)
	await press(JOY_BUTTON_DPAD_DOWN)
	check_eq(menu.selected, 1, "D-pad navigates the real menu")
	await press(JOY_BUTTON_A)
	check_eq(chosen, [1], "confirm activates the selected item")


func test_refresh_keeps_keyboard_and_custom_events_without_duplicates() -> void:
	Game.apply_settings()
	var custom := InputEventKey.new()
	custom.keycode = KEY_K
	InputMap.action_add_event("ui_accept", custom)
	var before: Array[int] = []
	for action in BUTTONS:
		before.append(InputMap.action_get_events(action).size())
	Game.apply_settings()
	Game.apply_settings()
	for i in BUTTONS.size():
		check_eq(InputMap.action_get_events(BUTTONS.keys()[i]).size(), before[i], "refresh adds no duplicate controller events")
	custom.pressed = true
	check(custom.is_action_pressed("ui_accept"), "custom menu input is preserved")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	check(enter.is_action_pressed("ui_accept"), "keyboard confirm remains available")
	InputMap.action_erase_event("ui_accept", custom)


func press(button: JoyButton) -> void:
	var event := Game._button(button)
	event.pressed = true
	event.pressure = 1.0
	Input.parse_input_event(event)
	await frames(2)
	event.pressed = false
	event.pressure = 0.0
	Input.parse_input_event(event)
	await frames(2)
