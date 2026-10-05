extends TestCase

class TestMain extends "res://scripts/main.gd":
	func _ready() -> void:
		pass

var _tutorial: Tutorial


func practice() -> Tutorial:
	_tutorial = Tutorial.new()
	add_child(_tutorial)
	return _tutorial


func cleanup() -> void:
	for action in Game.REBINDABLE:
		Input.action_release(action)
	if is_instance_valid(_tutorial):
		_tutorial.queue_free()
	get_tree().paused = false
	super.cleanup()


func test_title_entry_and_return_clear_pause() -> void:
	var main := TestMain.new()
	add_child(main)
	main.show_title()
	check_eq(main._screen._menu.items[0].label, tr("MENU_TUTORIAL"), "practice remains the first title choice")
	main._screen._menu.items[0].action.call()
	await frames(1)
	check(main._screen is Tutorial, "title choice opens practice")
	get_tree().paused = true
	main._screen.exit.emit()
	check(not get_tree().paused, "returning to title clears pause")
	check(not main._screen is Tutorial, "return replaces practice")
	main.queue_free()
	await frames(1)


func test_starts_with_visible_goal_without_modal_or_countdown() -> void:
	var tutorial := practice()
	await frames(120)
	check_eq(tutorial.step, Tutorial.Step.FORWARD, "the first task is immediately playable and waits indefinitely")
	check(tutorial.goal.y > tutorial.tank.course_offset, "a real pad is ahead of the tank")
	check_eq(tutorial.world.director, null, "no enemy waves")
	check_near(tutorial.world.rail.d, 0.0, 0.001, "no scrolling before driving is taught")
	check_near(tutorial.tank.hp, Tank.MAX_ARMOR, 0.001, "practice is safe")
	check(not tutorial.target.visible, "unintroduced firing target is hidden")
	check(tutorial.world.enemies.is_empty(), "hidden target cannot cast a registry-based shadow or attract aim locks")
	check(not tutorial._play.visible and not tutorial._replay.visible, "no Next or restart buttons compete with the goal")


func test_movement_requires_reaching_pad_then_releasing() -> void:
	var tutorial := practice()
	for action in Tutorial.MOVE_ACTIONS:
		var before := tutorial.step
		var goal := tutorial.goal
		Input.action_press(action)
		await frames(3)
		check(not tutorial.reached, "a brief press without reaching the pad is not success")
		check(await wait_until(func() -> bool: return tutorial.reached, 240), "%s reaches a real pad" % action)
		check_eq(tutorial.step, before, "holding the control waits for release, not a Next click")
		check(Vector2(tutorial.tank.course_u, tutorial.tank.course_offset).distance_to(goal) <= Tutorial.PAD_RADIUS + 0.5, "goal is spatial, not just an input check")
		Input.action_release(action)
		check(await wait_until(func() -> bool: return tutorial.step != before, 60), "release and actual stop reveal the next task")
	check_eq(tutorial.step, Tutorial.Step.AIM, "driving leads straight to aiming")
	check(tutorial.target.visible, "the target is introduced when needed")


func test_long_hold_does_not_make_the_next_pad_unreachable() -> void:
	var tutorial := practice()
	Input.action_press("move_forward")
	await frames(360)
	check(tutorial.reached, "a long hold still reaches the first pad")
	Input.action_release("move_forward")
	check(await wait_until(func() -> bool: return tutorial.step == Tutorial.Step.LEFT, 60), "release advances after a long hold")
	check_near(tutorial.goal.y, tutorial.tank.course_offset, 0.001, "the lateral pad stays on the player's actual forward position")
	Input.action_press("move_left")
	check(await wait_until(func() -> bool: return tutorial.reached, 240), "the displayed key alone can reach the next pad")
	Input.action_release("move_left")


func test_wrong_direction_does_not_complete() -> void:
	var tutorial := practice()
	Input.action_press("move_left")
	await frames(30)
	Input.action_release("move_left")
	check(not tutorial.reached, "movement away from the pad cannot complete it")
	check_eq(tutorial.step, Tutorial.Step.FORWARD, "wrong input leaves the instruction available")


func test_guidance_recovers_when_the_player_drives_the_wrong_way() -> void:
	var tutorial := practice()
	Input.action_press("move_left")
	await frames(90)
	Input.action_release("move_left")
	check(not tutorial.reached, "wrong-way driving leaves the goal unfinished")
	for frame in 360:
		for action in Tutorial.MOVE_ACTIONS:
			Input.action_release(action)
		Input.action_press(tutorial._move_action)
		await frames(1)
		if tutorial.reached:
			break
	check(tutorial.reached, "following updated control hints returns the player to the pad")
	check_eq(tutorial.step, Tutorial.Step.FORWARD, "recovery does not skip the current task")
	for action in Tutorial.MOVE_ACTIONS:
		Input.action_release(action)


func test_aim_and_actual_hit_lead_to_road_practice() -> void:
	var tutorial := practice()
	tutorial._set_step(Tutorial.Step.AIM)
	tutorial.tank.using_gamepad = true
	var at := tutorial.world.camera.unproject_position(tutorial.target.hit_center())
	tutorial.tank.aim_screen = at + Vector2(150, 0)
	await frames(2)
	check_eq(tutorial.step, Tutorial.Step.AIM, "moving the sight away does not complete aiming")
	tutorial.tank.aim_screen = at
	check(await wait_until(func() -> bool: return tutorial.step == Tutorial.Step.FIRE, 60), "manual aiming directly reveals the firing instruction")
	check_eq(tutorial.world.projectiles.size(), 0, "automatic guns cannot do the task")
	Input.action_press("fire")
	check(await wait_until(func() -> bool: return tutorial.reached, 240), "a real cannon round hits the target")
	check(tutorial.world.stats.shots > 0, "the real gun fired")
	check_eq(tutorial.step, Tutorial.Step.FIRE, "hit feedback remains while fire is held")
	Input.action_release("fire")
	check(await wait_until(func() -> bool: return tutorial.step == Tutorial.Step.ROAD, 60), "release introduces automatic driving")
	check_eq(tutorial.world.rail.mode, Rail.Mode.RAIL, "road practice uses actual rail behavior")
	await frames(60)
	check(tutorial.world.rail.d > 0.0, "the tank advances without held keys")
	check_eq(tutorial.step, Tutorial.Step.ROAD, "watching alone does not finish braking practice")
	Input.action_press("move_back")
	check(await wait_until(func() -> bool: return tutorial.reached, 120), "actual braking completes the road task")
	Input.action_release("move_back")
	check(await wait_until(func() -> bool: return tutorial.step == Tutorial.Step.DONE, 60), "completion waits for the brake control to be released")
	check(tutorial._play.visible and tutorial.tank.moving and tutorial.tank.shooting, "completion allows further practice or Easy")


func test_miss_or_automatic_weapon_cannot_complete() -> void:
	var tutorial := practice()
	tutorial._set_step(Tutorial.Step.FIRE)
	tutorial.tank.using_gamepad = true
	tutorial.tank.aim_screen = Vector2(40, 240)
	Input.action_press("fire")
	await frames(180)
	Input.action_release("fire")
	check(not tutorial.reached, "a missed shot does not complete firing")
	var hit := Hit.make(Hit.Kind.BULLET, 999.0, tutorial.target.hit_center())
	hit.source = tutorial.tank
	tutorial.target.take_hit(hit)
	check(not tutorial.reached, "a non-cannon hit does not complete firing")
	tutorial._set_step(Tutorial.Step.AIM)
	hit.weapon = "cannon"
	tutorial.target.take_hit(hit)
	check_eq(tutorial.step, Tutorial.Step.AIM, "a stale hit outside the firing task cannot advance")


func test_held_fire_must_be_released_after_aiming() -> void:
	var tutorial := practice()
	Input.action_press("fire")
	tutorial._set_step(Tutorial.Step.FIRE)
	await frames(90)
	check_eq(tutorial.world.stats.shots, 0, "a button held in an earlier lesson cannot fire immediately")
	check(not tutorial.tank.shooting, "release instruction gates charging")
	Input.action_release("fire")
	await frames(2)
	check(tutorial.tank.shooting, "releasing makes a fresh hold available")


func test_restart_resets_scrolling_and_projectiles_and_easy_is_optional() -> void:
	var tutorial := practice()
	var previous := Game.difficulty
	Game.difficulty = Game.Difficulty.HARD
	tutorial._set_step(Tutorial.Step.ROAD)
	await frames(60)
	tutorial._set_step(Tutorial.Step.DONE)
	check_eq(Game.difficulty, Game.Difficulty.HARD, "completing practice does not change difficulty")
	tutorial.restart_practice()
	check_eq(tutorial.step, Tutorial.Step.FORWARD, "replay starts directly at the first goal")
	check_near(tutorial.world.rail.d, 0.0, 0.001, "replay resets road position")
	check_near(tutorial.world.rail.speed, 0.0, 0.001, "replay stops scrolling")
	check_near(tutorial.tank.course_u, 0.0, 0.001, "replay centers the tank")
	check(not tutorial.tank.shooting, "replay disables weapons")
	var starts: Array[String] = []
	tutorial.start.connect(func(checkpoint: String) -> void: starts.append(checkpoint))
	tutorial._start_game()
	check(starts.is_empty(), "Easy is unavailable before completion")
	tutorial._set_step(Tutorial.Step.DONE)
	tutorial._start_game()
	check_eq(starts, [""], "Easy starts the actual game from its beginning")
	check_eq(Game.difficulty, Game.Difficulty.EASY, "only the explicit Easy choice changes difficulty")
	Game.difficulty = previous


func test_indefinite_road_practice_does_not_run_past_the_course() -> void:
	var tutorial := practice()
	for lesson in [Tutorial.Step.ROAD, Tutorial.Step.DONE]:
		tutorial._set_step(lesson)
		tutorial.world.rail.d = Course.LENGTH + 50.0
		tutorial.world.rail.speed = Rail.CRUISE
		tutorial.tank.course_u = 5.0
		tutorial.tank._place(tutorial.world.rail.d)
		tutorial._process(0.0)
		check_near(tutorial.world.rail.d, 0.0, 0.001, "long practice repeats the safe stretch")
		check_eq(tutorial.step, lesson, "looping neither advances nor restarts the lesson")
		check_near(tutorial.world.rail.speed, Rail.CRUISE, 0.001, "loop preserves automatic driving speed")
		check_near(tutorial.tank.course_u, 5.0, 0.001, "loop preserves steering position")
		check_eq(tutorial.tank._last_position, tutorial.tank.position, "loop cannot create a teleport velocity spike")
		check_eq(tutorial.tank.tracks._last, Vector3.INF, "loop cannot draw a track stripe across the entire road")
		check(not tutorial.tank.tail._initialized, "tail is reattached at the new location")
		check(absf(tutorial.world.camera.global_basis.z.dot(Vector3.UP)) < 0.95, "camera keeps a readable angle rather than looking straight down at the clamped course end")


func test_completion_buttons_do_not_steal_rebound_fire_or_steering() -> void:
	var tutorial := practice()
	var bindings: Dictionary = Game.settings.bindings.duplicate()
	var previous := Game.difficulty
	var fire := Game._key(KEY_SPACE)
	fire.keycode = KEY_SPACE
	Game.settings.bindings["fire"] = fire
	Game.apply_settings()
	var starts: Array[String] = []
	tutorial.start.connect(func(checkpoint: String) -> void: starts.append(checkpoint))
	tutorial._set_step(Tutorial.Step.DONE)
	check_eq(get_viewport().gui_get_focus_owner(), tutorial._play, "controller confirm can reach the Easy button")
	tutorial._pause()
	tutorial._close_pause()
	check_eq(get_viewport().gui_get_focus_owner(), tutorial._play, "resume restores controller confirmation on completion")
	fire.pressed = true
	Input.parse_input_event(fire)
	await frames(2)
	check(starts.is_empty(), "a rebound fire key must not activate the focused Easy button")
	fire.pressed = false
	Input.parse_input_event(fire)
	var steer := InputEventJoypadMotion.new()
	steer.axis = JOY_AXIS_LEFT_X
	steer.axis_value = 0.8
	Input.parse_input_event(steer)
	await frames(2)
	check_eq(get_viewport().gui_get_focus_owner(), tutorial._play, "analog steering does not navigate completion buttons")
	steer.axis_value = 0.0
	Input.parse_input_event(steer)
	var confirm := InputEventJoypadButton.new()
	confirm.button_index = JOY_BUTTON_A
	confirm.pressed = true
	Input.parse_input_event(confirm)
	await frames(2)
	confirm.pressed = false
	Input.parse_input_event(confirm)
	await frames(2)
	check_eq(starts, [""], "controller confirm activates the focused Easy button")
	Game.difficulty = previous
	Game.settings.bindings = bindings
	Game.apply_settings()


func test_free_practice_target_stays_in_the_play_area_after_braking() -> void:
	var tutorial := practice()
	for offset in [Tank.FORWARD_LIMIT.x, 4.0, Tank.FORWARD_LIMIT.y]:
		tutorial.tank.course_offset = offset
		tutorial.tank._place(tutorial.world.rail.d)
		tutorial._set_step(Tutorial.Step.DONE)
		tutorial.world.camera.follow(0.0)
		var at := tutorial.world.camera.unproject_position(tutorial.target.hit_center())
		check(Rect2(40, 60, 880, 320).has_point(at), "free-practice target is clear of the header and instruction card at offset %.1f" % offset)


func test_pause_and_locale_refresh_preserve_task() -> void:
	var tutorial := practice()
	tutorial._set_step(Tutorial.Step.FIRE)
	tutorial._menu_button.grab_focus()
	check_eq(get_viewport().gui_get_focus_owner(), tutorial._menu_button, "menu button is initially focused")
	tutorial._pause()
	check_eq(get_viewport().gui_get_focus_owner(), null, "pause releases underlying button focus for keyboard menu navigation")
	Input.action_press("fire")
	await frames(90)
	check_eq(tutorial.world.stats.shots, 0, "pause prevents firing")
	check_eq(tutorial.step, Tutorial.Step.FIRE, "pause does not advance practice")
	Input.action_release("fire")
	tutorial._close_pause()
	var previous: String = Game.settings.locale
	Game.settings.locale = "en"
	Game.apply_settings()
	tutorial._refresh_text()
	check_eq(tutorial.step, Tutorial.Step.FIRE, "language change preserves the task")
	check_eq(tutorial._menu_button.text, "Menu", "menu button also refreshes")
	Game.settings.locale = previous
	Game.apply_settings()


func test_current_bindings_device_hints_and_text_fit() -> void:
	var tutorial := practice()
	var previous: String = Game.settings.locale
	var bindings: Dictionary = Game.settings.bindings.duplicate()
	var custom := InputEventKey.new()
	custom.physical_keycode = KEY_J
	Game.settings.bindings["move_forward"] = custom
	for locale in ["ko", "en"]:
		Game.settings.locale = locale
		Game.apply_settings()
		tutorial.tank.using_gamepad = false
		tutorial._set_step(Tutorial.Step.FORWARD)
		check(tutorial._instruction.text.contains("J"), "remapped keyboard cue is current")
		for lesson in Tutorial.Step.values():
			tutorial._set_step(lesson as Tutorial.Step)
			await frames(1)
			check(not tutorial._instruction.text.contains("TUTORIAL_"), "%s task %d is translated" % [locale, lesson])
			check(tutorial._instruction.get_minimum_size().y <= tutorial._instruction.size.y, "%s task %d fits the small card" % [locale, lesson])
		var motion := InputEventJoypadMotion.new()
		motion.axis = JOY_AXIS_RIGHT_X
		motion.axis_value = 0.5
		tutorial._input(motion)
		tutorial._set_step(Tutorial.Step.AIM)
		check_eq(tutorial._instruction.text, tr("TUTORIAL_AIM_PAD"), "right-stick cue is distinct from mouse aiming")
		check_eq(tutorial._event_for(&"aim_right").axis, JOY_AXIS_RIGHT_X, "aim diagram uses the actual right stick")
		for lesson in Tutorial.Step.values():
			tutorial._set_step(lesson as Tutorial.Step)
			await frames(1)
			check(tutorial._instruction.get_minimum_size().y <= tutorial._instruction.size.y, "%s controller task %d fits" % [locale, lesson])
	Game.settings.locale = previous
	Game.settings.bindings = bindings
	Game.apply_settings()
