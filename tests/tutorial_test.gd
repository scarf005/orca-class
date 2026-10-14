extends TestCase

var tutorial: Tutorial

class TestMain extends "res://scripts/main.gd":
	func _ready() -> void:
		pass


func practice() -> Tutorial:
	tutorial = Tutorial.new()
	add_child(tutorial)
	return tutorial


func cleanup(restore_environment := false) -> void:
	get_tree().paused = false
	if is_instance_valid(tutorial):
		tutorial.queue_free()
	for action in Game.REBINDABLE:
		Input.action_release(action)
	super.cleanup(restore_environment)


## Runs the tank through its own tick for `seconds` of 60 Hz frames.
func drive(course: Tutorial, seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		course.tank.tick(1.0 / 60.0)


func wall_nodes(course: Tutorial) -> Array[Prop]:
	var result: Array[Prop] = []
	for spec in course.maze.specs:
		result.append(spec.node as Prop)
	return result


func test_opening_from_main_applies_tuning_before_building_the_tutorial() -> void:
	if not TestCase.is_isolated():
		skip("tuning load reads the user constants file; run through `just test`")
		return
	var defaults := ConfigFile.new()
	check_eq(defaults.load(GameTuning.DEFAULT_PATH), OK, "repository defaults load")
	var tuned: float = defaults.get_value("constants", "Turret traverse (rad/s)")
	var personal := ConfigFile.new() # Saved by earlier tuning tests in the same sandbox; it overrides the defaults.
	if personal.load(GameTuning.PATH) == OK:
		tuned = personal.get_value("constants", "Turret traverse (rad/s)", tuned)
	var original := Tank.TURRET_RATE
	Tank.TURRET_RATE = tuned + 7.0
	var main := TestMain.new()
	add_child(main)
	main._open_tutorial()
	check_eq(Tank.TURRET_RATE, tuned, "a fresh launch's tutorial uses the saved tuning, not script defaults")
	Tank.TURRET_RATE = original
	main.queue_free()


func place(course: Tutorial, u: float, d: float) -> void:
	var at := Course.ground_at(d, u)
	course.tank._set_pose(at, 0.0)
	course.tank._last_position = at


func test_maze_is_production_wall_scenery_registered_as_props() -> void:
	var course := practice()
	check(course.maze.specs.size() > 20, "a walled box (%d walls)" % course.maze.specs.size())
	for spec in course.maze.specs:
		check_eq(spec.kind, "wall", "every maze piece is the stage's wall kind")
		check(spec.node is Prop and course.world.props.in_radius(spec.node.global_position, 0.1).has(spec.node), "wall at d=%.0f u=%.0f is a live prop in world.props" % [spec.d, spec.u])
		check_eq((spec.node as Prop).min_charge, 0, "wall at d=%.0f u=%.0f breaks to any hit" % [spec.d, spec.u])


func test_maze_is_a_compact_three_by_three_box_on_the_start_road() -> void:
	var course := practice()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for spec in course.maze.specs:
		low = low.min(Vector2(spec.u, spec.d))
		high = high.max(Vector2(spec.u, spec.d))
		check(spec.d > Course.stage.plan_start and spec.d < 0.0, "wall d=%.0f lies on the pre-start road, where no stage content lives" % spec.d)
		check_near(Course.yaw_at(spec.d), 0.0, 0.0001, "the road is straight under the maze")
		check(absf(spec.u) + (spec.node as Prop).footprint <= Tank.lateral_limit(spec.d), "wall u=%.1f stands on the valley floor" % spec.u)
	check(high.x - low.x <= 37.0 and high.x - low.x >= 31.0, "about 36 m across (%.1f)" % (high.x - low.x))
	check(high.y - low.y <= 37.0 and high.y - low.y >= 31.0, "about 36 m along the road (%.1f)" % (high.y - low.y))
	var reach := Tank.HULL_RADIUS + (course.maze.specs[0].node as Prop).footprint
	var crushes := 0
	for i in Tutorial.ROUTE.size() - 1:
		var from: Vector2 = Tutorial.ROUTE[i]
		var to: Vector2 = Tutorial.ROUTE[i + 1]
		for k in int(from.distance_to(to)) + 1:
			var at := from.move_toward(to, k)
			for spec in course.maze.specs:
				if Vector2(spec.u, spec.d).distance_to(at) < reach:
					crushes += 1
	check_eq(crushes, 0, "following the route touches no wall")
	for shortcut in [[Vector2(0, -452), Vector2(0, -440)], [Vector2(0, -452), Vector2(0, -464)], [Vector2(-12, -452), Vector2(0, -452)], [Vector2(12, -452), Vector2(12, -440)]]:
		var blocked := false
		for k in 21:
			var at: Vector2 = shortcut[0].lerp(shortcut[1], k / 20.0)
			for spec in course.maze.specs:
				blocked = blocked or Vector2(spec.u, spec.d).distance_to(at) < reach
		check(blocked, "cutting across %s hits a wall" % [shortcut])


## Holds the key for `direction` (course u, d) for `seconds` from `from`.
func push(course: Tutorial, from: Vector2, direction: Vector2, seconds: float) -> void:
	place(course, from.x, from.y)
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(action)
	Input.action_press("move_forward" if direction.y > 0 else "move_back" if direction.y < 0 else "move_right" if direction.x > 0 else "move_left")
	drive(course, seconds)
	for action in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(action)


func test_ramming_a_maze_wall_in_each_direction_crushes_it_and_the_tank_drives_on() -> void:
	var cases := [
		["forward into the divider above the start", Vector2(0, -452), Vector2(0, 1), Vector2(0, -446)],
		["back into the divider below the start", Vector2(0, -452), Vector2(0, -1), Vector2(0, -458)],
		["left into the divider beside the start", Vector2(0, -452), Vector2(-1, 0), Vector2(-6, -452)],
		["right into the box side", Vector2(12, -452), Vector2(1, 0), Vector2(18, -452)],
	]
	for item: Array in cases:
		var course := practice()
		var before := wall_nodes(course).filter(func(wall: Prop) -> bool: return not wall.dead).size()
		push(course, item[1], item[2], 3.0)
		var at := Course.to_course(course.tank.global_position)
		var travelled: float = (Vector2(at.y, at.x) - item[3] as Vector2).dot(item[2])
		check(travelled > Tank.HULL_RADIUS, "%s: the hull drove through the wall line (%.2f m past it)" % [item[0], travelled])
		var broken := wall_nodes(course).filter(func(wall: Prop) -> bool: return wall.dead).size()
		check(broken >= 1 and broken < before, "%s: a ram crushed %d of its %d walls" % [item[0], broken, before])
		course.free()
		tutorial = null


## Steers the real tank to each of `points` (u, d) on frames with the movement keys.
func drive_route(course: Tutorial, points: Array) -> void:
	var actions := ["move_forward", "move_back", "move_left", "move_right"]
	for target: Vector2 in points:
		for frame in 360:
			var at := Course.to_course(course.tank.global_position)
			var error := Vector2(target.x - at.y, target.y - at.x)
			if error.length() < 1.5:
				break
			var wish := {"move_right": error.x > 1.0, "move_left": error.x < -1.0, "move_forward": error.y > 1.0, "move_back": error.y < -1.0}
			for action in actions:
				if wish[action]:
					Input.action_press(action)
				else:
					Input.action_release(action)
			await get_tree().process_frame
	for action in actions:
		Input.action_release(action)


func test_driving_the_painted_route_reaches_the_top_of_the_maze_with_every_wall_standing() -> void:
	var course := practice()
	await drive_route(course, Tutorial.ROUTE.slice(1))
	var at := Course.to_course(course.tank.global_position)
	check(absf(at.y - Tutorial.ROUTE[-1].x) < 2.0 and absf(at.x - Tutorial.ROUTE[-1].y) < 2.0, "the tank arrived at the route's end (u=%.1f d=%.1f)" % [at.y, at.x])
	for wall in wall_nodes(course):
		check(not wall.dead, "the route crushes nothing")


func test_driving_off_an_island_stops_at_its_edge() -> void:
	var course := practice()
	place(course, 0.0, -462.0)
	Input.action_press("move_back")
	drive(course, 3.0)
	Input.action_release("move_back")
	var maze: Rect2 = Tutorial.ISLANDS[0][0]
	var d := Course.to_course(course.tank.global_position).x
	check(d >= maze.position.y + Tank.HULL_RADIUS - 0.01, "the hull stays on the maze's island (d=%.2f)" % d)
	check(d < maze.position.y + Tank.HULL_RADIUS + 0.6, "and drives to its edge (d=%.2f)" % d)
	check(not course.world.terrain.visible, "with no valley under the islands")
	var boss := Rail.new()
	check_eq(boss.arena_d, Stage1.ARENA_CENTER_D, "the boss arena keeps its centre by default")
	check_eq(boss.arena_radius, Stage1.ARENA_RADIUS, "the boss arena keeps its radius by default")
	check_eq(boss.arena_u, INF, "and puts no strip limit on the tank")
	check(boss.arena_land.is_empty(), "and puts no land limit on it")


func test_reaching_the_goal_finishes_the_course() -> void:
	var course := practice()
	check_eq(course.step, Tutorial.Step.COURSE, "starts on the course")
	check(not course._play.visible and not course._replay.visible, "no start or practice buttons while driving")
	place(course, 14.0, Tutorial.FINISH_D - 2.0)
	Input.action_press("move_forward")
	await wait_until(func() -> bool: return course.step == Tutorial.Step.DONE, 120)
	Input.action_release("move_forward")
	check_eq(course.step, Tutorial.Step.DONE, "driving past the finish ends the course")
	check(course._play.visible and course._replay.visible, "both end buttons appear")
	check(not course.tank.input_enabled, "the tank stops taking input")


func test_end_buttons_wait_for_the_end_and_dash_cannot_start_the_game() -> void:
	var course := practice()
	var started: Array[String] = []
	course.start.connect(func(arena: String) -> void: started.append(arena))
	check(not course._play.visible and not course._replay.visible, "no end buttons before the end")
	course._finish()
	check(course._play.visible and course._replay.visible, "both end buttons appear at the end")
	check(not course.tank.input_enabled, "the tank stops taking input")
	check_eq(get_viewport().gui_get_focus_owner(), course._play, "Play holds focus for a controller")
	var press := Game._key(KEY_SPACE) as InputEventKey
	press.keycode = KEY_SPACE # A real key event carries both codes: dash matches the physical one, ui_accept the logical one.
	press.pressed = true
	check(press.is_action("dash") and press.is_action("ui_accept"), "Space is both dash and menu confirm")
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await frames(2)
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await frames(2)
	check_eq(started, [], "a dash press cannot start the game")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	Input.parse_input_event(enter)
	Input.flush_buffered_events()
	await frames(2)
	var enter_up := enter.duplicate() as InputEventKey
	enter_up.pressed = false
	Input.parse_input_event(enter_up)
	Input.flush_buffered_events()
	await frames(2)
	check_eq(started, [""], "confirming Play starts the game")
	check_eq(Game.difficulty, Game.Difficulty.EASY, "and starts it on easy")


func test_completion_settings_resume_and_easy_handoff() -> void:
	var course := practice()
	course._finish()
	course._pause()
	course._settings()
	Game.settings.locale = "en"
	Game.apply_settings()
	course._overlay.back.emit()
	check(not get_tree().paused, "settings returns to the active course")
	check_eq(get_viewport().gui_get_focus_owner(), course._play, "completion confirmation survives settings")
	check_eq(course._play.text, "Play on easy", "completion adopts changed language")
	var started: Array[String] = []
	course.start.connect(func(arena: String) -> void: started.append(arena))
	course._play.pressed.emit()
	check_eq(started, [""], "confirmation emits the normal gameplay handoff")
	check_eq(Game.difficulty, Game.Difficulty.EASY, "handoff selects Easy")
	var exited := [false]
	course.exit.connect(func() -> void: exited[0] = true)
	course._pause()
	course._overlay.selected = 3
	course._overlay._activate()
	check(exited[0], "leave practice invokes the title-return signal")
	course._close_pause()


func test_practice_again_gives_main_a_fresh_tutorial() -> void:
	var main := TestMain.new()
	add_child(main)
	main._open_tutorial()
	var old: Tutorial = main._screen
	var wall := wall_nodes(old)[0]
	wall.die(Hit.make(Hit.Kind.RAM, 99999.0, wall.global_position))
	old._restart()
	var fresh: Tutorial = main._screen
	check(fresh != old and fresh is Tutorial, "main swapped in a new tutorial")
	check(old.is_queued_for_deletion(), "the old run is discarded")
	check(not wall_nodes(fresh)[0].dead, "the new course has every wall again")
	check_eq(fresh.step, Tutorial.Step.COURSE, "and starts at the beginning")
	main.queue_free()


func paint_texts(course: Tutorial) -> Array[String]:
	var labels: Array[String] = []
	for mark in course._paint:
		if mark is Label3D:
			labels.append(mark.text)
	return labels


func test_route_letters_follow_rebound_keys_and_the_controller() -> void:
	var course := practice()
	Game.settings.bindings["move_forward"] = Game._key(KEY_UP)
	Game.apply_settings()
	course._refresh_paint()
	check(paint_texts(course).has(OS.get_keycode_string(KEY_UP)), "floor displays the actual rebound movement key")
	course.tank.using_gamepad = true
	course._refresh_paint()
	check(paint_texts(course).has("↑"), "the controller shows its arrows")
	course.tank.using_gamepad = false
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
		Game.settings.bindings["move_forward"] = Game._mouse(button)
		Game.apply_settings()
		check_eq(course._binding("move_forward"), "M%d" % (button - 4 if button in [8, 9] else button), "supported mouse movement remains named")
		course._refresh_paint()


func key_event(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event


func back_event(pressed: bool) -> InputEventJoypadButton:
	var event := Game._button(JOY_BUTTON_BACK) as InputEventJoypadButton
	event.pressed = pressed
	return event


## Crushed props leave solid shards in the world's particle pool, and wrecks as nodes.
func debris_count(course: Tutorial) -> int:
	return course.world.find_children("*", "Wreck", true, false).size() + course.world.fx._pools[Fx.Kind.SOLID].size()


func test_restart_binding_is_not_shared_with_any_other_action() -> void:
	Game.apply_settings()
	for probe: InputEvent in [key_event(KEY_R, true), back_event(true)]:
		check(probe.is_action("restart"), "%s restarts" % probe.as_text())
		for action in InputMap.get_actions():
			if action != &"restart":
				check(not probe.is_action(action), "%s is not also %s" % [probe.as_text(), action])


func test_restart_hotkeys_and_button_rebuild_the_tutorial_from_scratch() -> void:
	var main := TestMain.new()
	add_child(main)
	for trigger in ["R", "Back", "button"]:
		main._open_tutorial()
		var old: Tutorial = main._screen
		old.world.spawn_projectile(Entity.Team.PLAYER, old.tank.global_position + Vector3.UP * 50.0, Vector3.UP, "bullet")
		var wall := wall_nodes(old)[0]
		wall.take_hit(Hit.make(Hit.Kind.RAM, 99999.0, wall.global_position))
		check(wall.dead, "%s: the wall is crushed" % trigger)
		await frames(3)
		check(not old.world.projectiles.is_empty(), "%s: the run to be discarded has a projectile and a crushed wall" % trigger)
		var leftovers := debris_count(old)
		check(leftovers > 0, "%s: the crushed wall left debris behind (%d)" % [trigger, leftovers])
		match trigger:
			"R":
				Input.parse_input_event(key_event(KEY_R, true))
				Input.flush_buffered_events()
				await frames(2)
				Input.parse_input_event(key_event(KEY_R, false))
			"Back":
				Input.parse_input_event(back_event(true))
				Input.flush_buffered_events()
				await frames(2)
				Input.parse_input_event(back_event(false))
			_:
				old._restart_button.pressed.emit()
		Input.flush_buffered_events()
		await frames(2)
		var fresh: Tutorial = main._screen
		check(fresh != old and fresh is Tutorial, "%s: main swapped in a new tutorial" % trigger)
		check(not is_instance_valid(old) or old.is_queued_for_deletion(), "%s: the old run is discarded" % trigger)
		check(fresh.world.projectiles.is_empty(), "%s: no projectiles survive" % trigger)
		check_eq(debris_count(fresh), 0, "%s: no wreck or crushed-wall debris survives (the old run had %d)" % [trigger, leftovers])
		check(not wall_nodes(fresh)[0].dead, "%s: the wall is standing again" % trigger)
		check_near(fresh.tank.global_position.distance_to(Course.ground_at(Tutorial.ROUTE[0].y, Tutorial.ROUTE[0].x)), 0.0, 0.05, "%s: the tank is at the maze start" % trigger)
		check_eq(fresh.step, Tutorial.Step.COURSE, "%s: back at the beginning" % trigger)
	main.queue_free()


func test_restart_is_ignored_while_paused_and_labelled_with_its_binding() -> void:
	Game.settings.locale = "en"
	Game.apply_settings()
	var course := practice()
	var restarted := [0]
	course.restart.connect(func() -> void: restarted[0] += 1)
	check_eq(course._restart_button.text, "R  Restart", "keyboard label: binding, then the word")
	check(course._restart_button.get_global_position().x < 40.0 and course._restart_button.get_global_position().y < 40.0, "the button sits top-left")
	check_eq(course._restart_button.focus_mode, Control.FOCUS_NONE, "it never takes focus, so Space cannot press it")
	course.tank.using_gamepad = true
	course._refresh_buttons()
	check_eq(course._restart_button.text, "BACK  Restart", "controller label shows the controller button")
	course._pause()
	course._unhandled_input(key_event(KEY_R, true))
	check_eq(restarted[0], 0, "R does nothing under the pause menu")
	course._close_pause()
	course._unhandled_input(key_event(KEY_R, true))
	check_eq(restarted[0], 1, "R restarts once the menu is closed")
	course._unhandled_input(key_event(KEY_R, true))
	check_eq(restarted[0], 1, "a second press before the swap cannot restart twice")


func test_rebinding_in_settings_and_closing_with_pause_updates_the_floor_letter() -> void:
	var course := practice()
	check(paint_texts(course).has("W"), "starts with the default letter")
	course._pause()
	course._settings()
	Game.rebind(&"move_forward", Game._key(KEY_UP))
	course._unhandled_input(key_event(KEY_P, true))
	check(not get_tree().paused and course._overlay == null, "the pause key closed settings")
	var labels := paint_texts(course)
	check(labels.has(OS.get_keycode_string(KEY_UP)) and not labels.has("W"), "the floor letter follows the new binding")


func test_the_ground_is_flat_while_a_tutorial_is_open_through_a_restart() -> void:
	var main := TestMain.new()
	add_child(main)
	main._open_tutorial()
	await frames(2)
	check(Course.flat, "the valley's mountains are gone while practising")
	main._open_tutorial()
	await frames(2)
	check(Course.flat, "a restart frees the old run after the new one opens and keeps the plain")
	main.show_title()
	await frames(2)
	check(not Course.flat, "leaving restores the valley")
	main.queue_free()


func test_the_camera_watches_a_fall_from_where_the_tank_left_the_island() -> void:
	var course := practice()
	var camera := course.world.camera
	var tank := course.tank
	var run: Rect2 = Tutorial.ISLANDS[10][0]
	place(course, run.end.x - 5.0, run.get_center().y)
	tank.course_u = run.end.x - 5.0
	for _i in 120:
		tank.tick(1.0 / 60.0)
		camera.follow(1.0 / 60.0)
	var stood := camera.global_position
	tank.dash(Vector2.RIGHT) # Off the island's right edge, into the sky.
	var fell := false
	for _i in roundi(60 * Tank.FALL_TIME) - 10:
		tank.tick(1.0 / 60.0)
		camera.follow(1.0 / 60.0)
		fell = fell or tank.is_falling()
	check(fell and tank.is_falling(), "the dash carries the tank off and it is still falling")
	check(Vector2(camera.global_position.x - stood.x, camera.global_position.z - stood.z).length() < 6.0, "the camera stays by the edge (%.1f m from where it stood)" % Vector2(camera.global_position.x - stood.x, camera.global_position.z - stood.z).length())
	check(camera.global_position.y > stood.y - 0.5, "and does not drop with the tank")
	var toward := (tank.global_position - camera.global_position).normalized()
	check(toward.dot(-camera.global_basis.z) > 0.9, "it looks at the falling tank (%.2f)" % toward.dot(-camera.global_basis.z))


func test_the_camera_is_overhead_in_the_maze_and_the_chase_view_past_it() -> void:
	var course := practice()
	var camera := course.world.camera
	place(course, Tutorial.ROUTE[0].x, Tutorial.ROUTE[0].y)
	for _i in 60:
		camera.follow(1.0 / 60.0)
	check_near(camera.global_position.y - course.tank.global_position.y, 30.0, 0.5, "the maze is seen from above")
	place(course, -12.0, -426.0)
	for _i in 120:
		camera.follow(1.0 / 60.0)
	var eye := Course.to_course(camera.global_position)
	var height := camera.global_position.y - course.tank.global_position.y
	check_near(height, ChaseCamera.RAIL_HEIGHT, 0.3, "past it the camera drops to the game's chase height")
	check_near(Course.to_course(course.tank.global_position).x - eye.x, ChaseCamera.RAIL_BACK, 0.5, "and follows behind the tank, along the island")
	place(course, 4.0, Tutorial.PILLBOX.y)
	for _i in 180:
		camera.follow(1.0 / 60.0)
	eye = Course.to_course(camera.global_position)
	check_near(Course.to_course(course.tank.global_position).y - eye.y, ChaseCamera.RAIL_BACK, 0.5, "and swings round behind it where the islands turn right")
