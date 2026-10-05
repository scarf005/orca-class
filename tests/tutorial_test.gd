extends TestCase

var tutorial: Tutorial

class MeasuredTank extends Tutorial.CourseTank:
	var updates := 0
	var elapsed := 0.0
	var dashes := 0

	func dash(direction: Vector2) -> void:
		var cooldown := anchor_cooldown
		super.dash(direction)
		if cooldown <= 0:
			dashes += 1

	func _update_movement(delta: float) -> void:
		updates += 1
		elapsed += delta
		super._update_movement(delta)


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


func test_course_uses_normal_arena_motion_and_all_elapsed_time() -> void:
	var course := practice()
	var at := course.tank.global_position
	Input.action_press("move_forward")
	course.tank.tick(0.5)
	Input.action_release("move_forward")
	var actual := course.tank.global_position
	var ordinary := Tank.new()
	course.world.add_child(ordinary)
	ordinary._set_pose(at, course.tank.hull_yaw)
	ordinary._last_position = at
	Input.action_press("move_forward")
	for i in 30:
		ordinary.tick(1.0 / 60.0)
	Input.action_release("move_forward")
	check_near(actual.distance_to(ordinary.global_position), 0, 0.01, "same native movement, allowing centimetre float accumulation")
	check(actual.distance_to(at) > 13, "half-second native distance: %s (floor %s -> %s)" % [actual.distance_to(at), course.floor_position(at), course.floor_position(actual)])
	check_eq(course.world.rail.mode, Rail.Mode.ARENA, "self-paced course uses the actual arena movement mode")


func test_long_frame_work_is_bounded_without_discarding_elapsed_time() -> void:
	var course := practice()
	var tank := MeasuredTank.new()
	tank.course = course
	course.world.add_child(tank)
	tank._set_pose(course.floor_world(Tutorial.ROUTE[0]), course.tank.hull_yaw)
	tank._last_position = tank.global_position
	var started := Time.get_ticks_usec()
	tank.tick(10.0)
	var duration := Time.get_ticks_usec() - started
	check(tank.updates <= 32, "even a ten-second frame has a fixed Tank-update budget")
	check_near(tank.elapsed, 10.0, 0.00001, "budget conserves every elapsed second")
	print("Tutorial slow-frame budget: %d updates, %d walls, %d projectiles, %d microseconds" % [tank.updates, course.walls.size(), course.world.projectiles.size(), duration])


func test_one_dash_input_edge_is_consumed_once_during_a_long_frame() -> void:
	var course := practice()
	var tank := MeasuredTank.new()
	tank.course = course
	course.world.add_child(tank)
	tank._set_pose(course.floor_world(Tutorial.ROUTE[0]), course.tank.hull_yaw)
	tank._last_position = tank.global_position
	Input.action_press("move_forward")
	var press := Game._key(KEY_SPACE) as InputEventKey
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	check(Input.is_action_just_pressed("dash"), "one real keyboard dash edge is present")
	tank.tick(1.0)
	var release := press.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	Input.action_release("move_forward")
	check_eq(tank.dashes, 1, "substeps cannot replay the same dash edge after cooldown expires")


func test_expiring_cannon_still_hits_gate_during_its_live_interval() -> void:
	var course := practice()
	var muzzle := course.gate.hit_center() + course.floor_basis * Vector3(0, 0, 30)
	course.tank.fire_cannon(muzzle, (course.gate.hit_center() - muzzle).normalized(), 0.4)
	check(not course.gate.dead and not course.world.projectiles.is_empty(), "ordinary quick round is in flight before slow frame")
	course.world._process(1.1)
	check(course.gate.dead, "gate thirty metres away is struck before the ordinary round expires")
	check_eq(course.step, Tutorial.Step.LOCK, "accepted hit opens the real passage despite crossing expiry")


func test_intact_gate_blocks_swept_driving_and_dash() -> void:
	var course := practice()
	var before := Vector2(28, 5)
	var after := course.slide(before, Vector2(28, 40))
	check(after.y < 15.5 - Tank.HULL_RADIUS, "sweep cannot tunnel through the closed gate")
	course.tank._set_pose(course.floor_world(before), course.tank.hull_yaw)
	course.tank._last_position = course.tank.global_position
	Input.action_press("move_forward")
	course.tank.tick(1.0)
	Input.action_release("move_forward")
	check(course.floor_position(course.tank.global_position).y < 15.5 - Tank.HULL_RADIUS, "normal driving stops at door, position %s" % course.floor_position(course.tank.global_position))
	check(not course.gate.dead, "ramming the door does not bypass the shot")
	course.tank.dash(Vector2(0, 1))
	Input.action_press("move_forward")
	course.tank.tick(0.5)
	Input.action_release("move_forward")
	check(course.floor_position(course.tank.global_position).y < 15.5 - Tank.HULL_RADIUS, "native dash also remains on the near side")


func test_walls_stop_wrong_way_driving_but_allow_turns() -> void:
	var course := practice()
	var first := Tutorial.ROUTE[0]
	var blocked := course.slide(first, first + Vector2(40, 0))
	check(blocked.x < -29 - Tank.HULL_RADIUS, "side wall requires driving to the corner")
	var turn := course.slide(Vector2(-36, -12), Vector2(-4, -12))
	check_near(turn.distance_to(Vector2(-4, -12)), 0, 0.01, "open corner joins the next actual corridor")
	var diagonal := course.slide(first, first + Vector2(40, 20))
	check(diagonal.x < -29 - Tank.HULL_RADIUS, "diagonal approach cannot jump a wall")
	check(diagonal.y > first.y, "contact slides along the wall rather than freezing movement")


func test_gate_ignores_coax_ram_and_misses() -> void:
	var course := practice()
	var health := course.gate.hp
	for kind in [Hit.Kind.RAM, Hit.Kind.BULLET]:
		var hit := Hit.make(kind, 99999, course.gate.hit_center())
		hit.source = course.tank
		hit.weapon = "coax"
		course.gate.take_hit(hit)
	check_eq(course.gate.hp, health, "automatic weapons and contact do not teach cannon firing")
	course.tank.fire_cannon(course.gate.hit_center() + Vector3.UP * 30, Vector3.UP, 1)
	check(not course.gate.dead, "a real missed cannon shot leaves the gate closed")
	check_eq(course.step, Tutorial.Step.DRIVE, "missing cannot unlock the next encounter")
	check(course.target == null, "lock target cannot be locked through the closed door")


func test_cannon_destroys_gate_and_opens_the_actual_route() -> void:
	var course := practice()
	var gate := course.gate
	var center := gate.hit_center()
	var muzzle := center + course.floor_basis * Vector3(0, 0, 20)
	course.tank.fire_cannon(muzzle, (center - muzzle).normalized(), 1)
	check(gate.dead, "real projectile sweep delivers accepted cannon damage")
	check(not course.world.props.in_radius(center, 10).has(gate), "destroyed gate leaves the scenery collision registry")
	check(not course.world.enemies.has(gate), "elevated aim adapter unregisters at destruction")
	check_eq(course.step, Tutorial.Step.LOCK, "destruction introduces the lock encounter")
	check(is_instance_valid(course.target), "next target appears only after the door is destroyed")
	check_near(course.slide(Vector2(28, 5), Vector2(28, 40)).y, 40, 0.01, "the same passage is now physically traversable")


func test_unlocked_cannon_cannot_complete_lock_encounter() -> void:
	var course := practice()
	course.gate.die(Hit.make(Hit.Kind.SHELL, 100, course.gate.hit_center()))
	var target := course.target
	var center := target.hit_center()
	var muzzle := center + course.floor_basis * Vector3(0, 0, 20)
	course.tank.charge_lock = null
	course.tank.fire_cannon(muzzle, (center - muzzle).normalized(), 1)
	check(not target.dead, "a real unlocked full cannon shot cannot stand in for lock-on")
	check_eq(target.hp, target.max_hp, "unlock rejection preserves accepted health")
	check_eq(course.step, Tutorial.Step.LOCK, "lock task remains available")


func test_native_acquired_lock_and_accepted_shot_complete_course() -> void:
	var course := practice()
	course.gate.die(Hit.make(Hit.Kind.SHELL, 100, course.gate.hit_center()))
	course.tank._set_pose(course.floor_world(Vector2(20, 50)), course.tank.hull_yaw)
	course.world.camera.follow(0)
	course.tank.aim_screen = course.world.camera.unproject_position(course.target.hit_center())
	course.tank.using_gamepad = true
	check_eq(course.tank.charge_lock, null, "starts without a pre-acquired lock")
	Input.action_press("fire")
	for i in 40:
		course.tank.tick(1.0 / 60.0)
	check_eq(course.tank.charge_lock, course.target, "native aim path acquires from held input")
	var target := course.target
	for i in 30:
		course.tank.tick(1.0 / 60.0)
	Input.action_release("fire")
	check(target.dead, "uninterrupted charge auto-fires from the real barrel and produces accepted destruction")
	check_eq(course.step, Tutorial.Step.DONE, "destruction, not input or lock event alone, completes the course")
	check(course.tank.firing_lock == null, "firing provenance is scoped to the actual synchronous shot")
	check_eq(get_viewport().gui_get_focus_owner(), course._play, "completion retains controller confirmation")


func test_floor_cues_follow_rebound_keys_and_fire_button() -> void:
	var course := practice()
	var forward := Game._key(KEY_UP)
	var fire := Game._key(KEY_SPACE)
	Game.settings.bindings["move_forward"] = forward
	Game.settings.bindings["fire"] = fire
	Game.apply_settings()
	course._refresh_paint()
	var labels: Array[String] = []
	for mark in course._paint:
		if mark is Label3D:
			labels.append(mark.text)
	check(labels.has(OS.get_keycode_string(KEY_UP)), "floor displays the actual rebound movement key")
	check(labels.has(OS.get_keycode_string(KEY_SPACE)), "fire key replaces the mouse diagram when rebound")
	course.tank.using_gamepad = true
	course._refresh_paint()
	labels.clear()
	for mark in course._paint:
		if mark is Label3D:
			labels.append(mark.text)
	check(labels.has("RT"), "controller fire cue appears in the same place in the world")
	course.tank.using_gamepad = false
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
		Game.settings.bindings["move_forward"] = Game._mouse(button)
		Game.settings.bindings["fire"] = Game._mouse(button)
		Game.apply_settings()
		check_eq(course._binding("move_forward"), "M%d" % (button - 4 if button in [8, 9] else button), "supported mouse movement remains named")
		course._refresh_paint()


func test_completion_settings_resume_and_easy_handoff() -> void:
	var course := practice()
	course.gate.die(Hit.new())
	course.target.die(Hit.new())
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


func test_stopped_gate_contact_has_no_crush_feedback() -> void:
	var course := practice()
	Game.silent = false
	course.tank._set_pose(course.floor_world(Vector2(28, 8)), course.tank.hull_yaw)
	course.tank._last_position = course.tank.global_position
	course.world.camera._kick = 0
	course.tank.tick(0.1)
	check_eq(course.world.camera._kick, 0.0, "persistent gate does not issue native ram camera kicks while stopped")
	check(not course.gate.dead, "contact still cannot destroy the door")


func test_slow_frames_advance_real_projectiles_by_all_elapsed_time() -> void:
	var course := practice()
	var at := course.tank.global_position + Vector3.UP * 100
	var shot := course.world.spawn_projectile(Entity.Team.PLAYER, at, Vector3.UP * 10, "bullet")
	course.world._process(0.5)
	check_near(shot.life, 1.5, 0.00001, "slow-frame weapon production cannot outpace projectile lifetime")
	check_near(shot.global_position.distance_to(at), 5, 0.01, "projectile sweep consumes elapsed movement too")


func test_replay_clears_projectiles_targets_and_pause_focus() -> void:
	var course := practice()
	course.gate.die(Hit.make(Hit.Kind.SHELL, 100, course.gate.hit_center()))
	var old := course.target
	var shot := course.world.spawn_projectile(Entity.Team.PLAYER, course.tank.global_position + Vector3.UP * 100, Vector3.UP, "bullet")
	check(course.world.projectiles.has(shot), "actual projectile is live before replay")
	course.tank.dash(Vector2.RIGHT)
	check(course.tank._drift > 0, "production dash is active before pausing")
	course._pause()
	check(get_tree().paused, "menu pauses the real world")
	course._overlay.selected = 1
	course._overlay._activate()
	check(not get_tree().paused, "replay menu resumes the real world")
	check(shot.is_queued_for_deletion() and course.world.projectiles.is_empty(), "replay clears the actual projectile and registry")
	check_eq(course.tank._drift, 0.0, "replay cancels the running dash")
	check_eq(course.tank.anchor_cooldown, 0.0, "new run can dash immediately")
	check_eq(get_viewport().gui_get_focus_owner(), null, "driving resumes without a menu consuming input")
	var entrance := course.tank.global_position
	course.tank.tick(0.1)
	check_near(course.tank.global_position.distance_to(entrance), 0, 0.01, "old dash cannot move the new run without input")
	check_eq(course.step, Tutorial.Step.DRIVE, "replay starts in the connected course")
	check_eq(course.target, null, "later encounter is not prematurely available")
	check(not course.world.enemies.has(old), "previous lock target is unregistered immediately")
	check(not course.gate.dead, "door is rebuilt")
	check_near(course.floor_position(course.tank.global_position).distance_to(Tutorial.ROUTE[0]), 0, 0.01, "replay returns to the actual entrance")
	check(not course._play.visible, "no next/start buttons interrupt initial driving")
