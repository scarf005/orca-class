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
	var title: Control = main._screen
	check_eq(title._menu.items[0].label, tr("MENU_TUTORIAL"), "practice is the first title choice")
	title._menu.items[0].action.call()
	await frames(1)
	check(main._screen is Tutorial, "title choice opens the real tutorial screen")
	get_tree().paused = true
	main._screen.exit.emit()
	check(not get_tree().paused, "returning to the title clears pause")
	check(not main._screen is Tutorial, "return replaces the tutorial")
	main.queue_free()
	await frames(1)


func test_waits_without_danger_or_scroll() -> void:
	var tutorial := practice()
	await frames(120)
	check_eq(tutorial.step, Tutorial.Step.WELCOME, "reading never advances the lesson")
	check_eq(tutorial.world.director, null, "no enemy waves")
	check_near(tutorial.world.rail.d, 0.0, 0.001, "range does not scroll")
	check_near(tutorial.tank.hp, Tank.MAX_ARMOR, 0.001, "player is safe")
	check_eq(tutorial.world.enemies.size(), 1, "only the practice target")
	tutorial.advance()
	tutorial.advance()
	check_eq(tutorial.step, Tutorial.Step.LEFT, "Next cannot skip an unfinished task")
	await frames(60)
	check(not tutorial.achieved, "waiting is not movement")


func test_movement_each_direction_and_stop() -> void:
	var tutorial := practice()
	tutorial.advance()
	for action in Tutorial.MOVE_ACTIONS:
		var before := tutorial.step
		Input.action_press(action)
		check(await wait_until(func() -> bool: return tutorial.achieved, 60), "%s moves the tank" % action)
		Input.action_release(action)
		check_eq(tutorial.step, before, "success waits for Next")
		tutorial.advance()
	check_eq(tutorial.step, Tutorial.Step.STOP, "all four directions lead to stopping")
	Input.action_press("move_left")
	await frames(5)
	check(not tutorial.achieved, "holding a movement key is not stopping")
	Input.action_release("move_left")
	check(await wait_until(func() -> bool: return tutorial.achieved, 60), "release and actual stop complete the task")


func test_aim_and_real_cannon_hit() -> void:
	var tutorial := practice()
	tutorial._set_step(Tutorial.Step.AIM)
	tutorial.tank.using_gamepad = true
	var at := tutorial.world.camera.unproject_position(tutorial.target.hit_center())
	tutorial.tank.aim_screen = at + Vector2(150, 0)
	await frames(2)
	check(not tutorial.achieved, "moving the sight away is not aiming at the target")
	tutorial.tank.aim_screen = at
	check(await wait_until(func() -> bool: return tutorial.achieved, 60), "sight placed on the target completes aiming")
	check_eq(tutorial.world.projectiles.size(), 0, "automatic guns cannot finish the task")
	tutorial.advance()
	Input.action_press("fire")
	check(await wait_until(func() -> bool: return tutorial.achieved, 180), "holding fire lands a real cannon hit")
	Input.action_release("fire")
	check(tutorial.world.stats.shots > 0, "the real gun fired")
	check(not tutorial.target.dead, "target remains available for more practice")
	check_eq(tutorial.step, Tutorial.Step.FIRE, "hit waits for Next")
	tutorial.advance()
	check_eq(tutorial.step, Tutorial.Step.DONE, "hit unlocks completion")
	check(tutorial.tank.moving and tutorial.tank.shooting, "completion allows free practice")


func test_miss_and_non_cannon_cannot_complete() -> void:
	var tutorial := practice()
	tutorial._set_step(Tutorial.Step.FIRE)
	tutorial.tank.using_gamepad = true
	tutorial.tank.aim_screen = Vector2(40, 240)
	Input.action_press("fire")
	await frames(150)
	Input.action_release("fire")
	check(not tutorial.achieved, "a shot that misses is not success")
	var hit := Hit.make(Hit.Kind.BULLET, 999.0, tutorial.target.hit_center())
	hit.source = tutorial.tank
	tutorial.target.take_hit(hit)
	check(not tutorial.achieved, "a machine-gun hit cannot complete the main-gun lesson")
	tutorial._set_step(Tutorial.Step.AIM)
	hit.weapon = "cannon"
	tutorial.target.take_hit(hit)
	check(not tutorial.achieved, "hits outside the firing lesson cannot advance it")


func test_restart_and_easy_handoff() -> void:
	var tutorial := practice()
	var previous := Game.difficulty
	Game.difficulty = Game.Difficulty.HARD
	check_eq(Game.difficulty, Game.Difficulty.HARD, "entering practice preserves difficulty")
	tutorial.tank.course_u = 12.0
	tutorial._set_step(Tutorial.Step.DONE)
	tutorial.restart_practice()
	check_eq(tutorial.step, Tutorial.Step.WELCOME, "restart returns to the beginning")
	check_near(tutorial.tank.course_u, 0.0, 0.001, "restart places the tank centrally")
	check(not tutorial.tank.shooting, "restart disables weapons")
	var starts: Array[String] = []
	tutorial.start.connect(func(checkpoint: String) -> void: starts.append(checkpoint))
	tutorial._set_step(Tutorial.Step.DONE)
	tutorial.advance()
	check_eq(starts, [""], "completion starts the real game from the beginning")
	check_eq(Game.difficulty, Game.Difficulty.EASY, "completion chooses easy explicitly")
	Game.difficulty = previous


func test_pause_does_not_advance_or_fire() -> void:
	var tutorial := practice()
	tutorial._set_step(Tutorial.Step.FIRE)
	var event := InputEventAction.new()
	event.action = &"pause"
	event.pressed = true
	tutorial._unhandled_input(event)
	check(get_tree().paused, "pause stops practice")
	Input.action_press("fire")
	await frames(90)
	check(not tutorial.achieved, "pause does not complete the lesson")
	check_eq(tutorial.world.stats.shots, 0, "pause prevents firing")
	Input.action_release("fire")
	tutorial._close_pause()
	check(not get_tree().paused, "resume restores practice")


func test_device_hints_and_refresh_preserve_progress() -> void:
	var tutorial := practice()
	tutorial._set_step(Tutorial.Step.LEFT)
	tutorial._complete()
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = -1.0
	tutorial._input(motion)
	check(tutorial.tank.using_gamepad, "movement stick selects controller instructions")
	check(tutorial.achieved, "changing device does not erase success")
	tutorial._set_step(Tutorial.Step.AIM)
	check_eq(tutorial._instruction.text, tr("TUTORIAL_AIM_PAD"), "controller aiming explains the right stick")
	tutorial._complete()
	var previous: String = Game.settings.locale
	Game.settings.locale = "en"
	Game.apply_settings()
	tutorial._refresh_text()
	check(tutorial.achieved, "language refresh preserves success")
	check_eq(tutorial._leave.text, "Back to title", "footer also changes language")
	Game.settings.locale = previous
	Game.apply_settings()


func test_bindings_and_both_languages() -> void:
	var tutorial := practice()
	var previous: String = Game.settings.locale
	var bindings: Dictionary = Game.settings.bindings.duplicate()
	var custom := InputEventKey.new()
	custom.physical_keycode = KEY_J
	Game.settings.bindings["move_left"] = custom
	for locale in ["ko", "en"]:
		Game.settings.locale = locale
		Game.apply_settings()
		tutorial._set_step(Tutorial.Step.LEFT)
		check(tutorial._instruction.text.contains("J"), "%s shows the rebound key" % locale)
		check(not tutorial._instruction.text.contains("TUTORIAL_"), "%s has the instruction" % locale)
		tutorial._set_step(Tutorial.Step.FIRE)
		check(not tutorial._instruction.text.contains("TUTORIAL_"), "%s has the mouse button name" % locale)
		for lesson in Tutorial.Step.values():
			tutorial._set_step(lesson as Tutorial.Step)
			await frames(1)
			check(not tutorial._instruction.text.contains("TUTORIAL_"), "%s lesson %d is translated" % [locale, lesson])
			check(tutorial._instruction.get_minimum_size().y <= 106, "%s lesson %d fits the panel" % [locale, lesson])
		for button in [1, 2, 3, 8, 9]:
			check(tr("TUTORIAL_MOUSE_%d" % button) != "TUTORIAL_MOUSE_%d" % button, "mouse %d is translated" % button)
	Game.settings.locale = previous
	Game.settings.bindings = bindings
	Game.apply_settings()
