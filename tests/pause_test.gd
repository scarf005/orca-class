extends TestCase
## Pause has a browser-safe key without losing Escape or the gamepad Start button.


func test_p_pauses_and_resumes_the_play_session() -> void:
	var screen := GameScreen.new()
	add_child(screen)
	screen.world.player.input_enabled = false
	var event := InputEventKey.new()
	event.physical_keycode = KEY_P
	event.pressed = true
	screen._unhandled_input(event)
	check(get_tree().paused and screen._overlay != null, "P opens the pause menu")
	var distance := screen.world.rail.d
	await frames(3)
	check_eq(screen.world.rail.d, distance, "the world stops while paused")
	screen._unhandled_input(event)
	check(not get_tree().paused and screen._overlay == null, "P resumes the session")
	screen._close_overlay()
	screen.queue_free()


func test_escape_and_gamepad_start_remain_pause_bindings() -> void:
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	check(InputMap.event_is_action(escape, &"pause"), "Escape still pauses outside browser fullscreen")
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	check(InputMap.event_is_action(start, &"pause"), "gamepad Start still pauses")
