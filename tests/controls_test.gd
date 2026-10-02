extends TestCase
## Controls: WASD plus the left mouse button, double-tap rolls, the auto coax, and handling.


func test_keyboard_needs_only_wasd_and_the_mouse() -> void:
	check(Game.REBINDABLE == [&"move_forward", &"move_back", &"move_left", &"move_right", &"fire_coax", &"fire_cannon", &"pause"], "only movement, the guns and pause are bound")
	for action in [&"anchor", &"overdrive", &"brake"]:
		check(not InputMap.has_action(action), "%s is gone" % action)
	var button := func(action: StringName, index: MouseButton) -> bool:
		return InputMap.action_get_events(action).any(func(e: InputEvent) -> bool: return e is InputEventMouseButton and (e as InputEventMouseButton).button_index == index)
	check(button.call(&"fire_coax", MOUSE_BUTTON_LEFT), "left mouse fires the coax")
	check(button.call(&"fire_cannon", MOUSE_BUTTON_RIGHT), "right mouse fires the main gun")


func test_rounds_leave_along_the_barrel() -> void:
	var out := Tank.along_barrel(Vector3.FORWARD, Vector3.BACK)
	check(out.angle_to(Vector3.FORWARD) <= deg_to_rad(6.1), "a turret facing away never sends rounds forward")
	var near := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(3.0))
	check(Tank.along_barrel(Vector3.FORWARD, near).is_equal_approx(near), "small lead corrections pass through")


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await frames(1)
	Input.action_release(action)
	await frames(1)


func test_double_tap_dashes_that_way() -> void:
	var world := stage()
	var tank := world.player
	tank.input_enabled = true
	await frames(2)
	var u := tank.course_u
	await _tap(&"move_right")
	check(not tank.is_dashing(), "a single tap only steers")
	await _tap(&"move_right")
	check(tank.is_dashing(), "a double tap dashes")
	check(tank.invuln > 0.0, "the dash is a dodge")
	await frames(10)
	check(tank.course_u > u + 4.0, "it bursts sideways")
	check(tank.model.rotation.z == 0.0 and tank.model.position.y == 0.0, "no roll: the hull stays on its tracks")
	await frames(40)
	var offset := tank.course_offset
	await _tap(&"move_forward")
	await _tap(&"move_forward")
	await frames(6)
	check(tank.course_offset > offset + 1.5 and world.rail.speed > Rail.CRUISE + 8.0, "a forward double tap surges ahead")
	tank.input_enabled = false


func test_w_and_s_are_the_throttle() -> void:
	var world := stage()
	world.player.input_enabled = true
	await frames(30)
	Input.action_press(&"move_forward")
	await frames(20)
	check(world.rail.throttle == 1, "holding W boosts")
	Input.action_release(&"move_forward")
	Input.action_press(&"move_back")
	await frames(5)
	check(world.rail.throttle == -1, "holding S brakes")
	Input.action_release(&"move_back")


func test_coax_soft_locks_near_the_reticle() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var ugv := Ugv.new()
	ugv.position = Course.ground_at(world.rail.d + 50.0, 6.0)
	world.add_enemy(ugv)
	ugv.invulnerable = true
	await frames(2)
	tank.using_gamepad = true
	tank.aim_screen = world.camera.unproject_position(ugv.hit_center()) + Vector2(12, 0)
	await frames(2)
	check(tank.coax_target == ugv, "an enemy just off the reticle is soft-locked for lead")
	tank.aim_screen = Vector2(20, 20)
	await frames(2)
	check(tank.coax_target == null, "nothing near the reticle, no lock")


func test_tank_ranges_across_the_valley_floor() -> void:
	check(Tank.lateral_limit(300.0) > 25.0, "the farm valley is open to the foot of the hills")
	check(Tank.lateral_limit(3100.0) <= 12.0, "the highway deck keeps it inside the guardrails")
	check(Tank.MOVE_SPEED.x * 1.0 > Tank.lateral_limit(300.0), "it crosses half the valley in under a second")


func test_one_main_gun_shell_wrecks_a_vehicle() -> void:
	var world := stage()
	var ugv := Ugv.new()
	ugv.position = Course.ground_at(world.rail.d + 60.0, 0.0)
	world.add_enemy(ugv)
	await frames(1)
	var shell := Hit.make(Hit.Kind.SHELL, Armament.SHELL_DAMAGE, ugv.hit_center())
	shell.caliber = 100
	ugv.take_hit(shell)
	check(ugv.dead, "a direct 100 mm hit is a kill")
	check(Armament.CHARGE_DELAY + Armament.CHARGE_TIME <= 1.0, "and a full charge takes no longer than a second")


func test_the_gun_lays_on_a_soft_locked_drone_not_the_ground_behind_it() -> void:
	var world := stage()
	var tank := world.player
	world.rail.mode = Rail.Mode.HOLD
	world.rail.hold_at = world.rail.d
	var drone := FpvDrone.new()
	drone.position = Course.ground_at(world.rail.d + 40.0, 4.0) + Vector3.UP * 11.0
	world.add_enemy(drone)
	await frames(2)
	drone.set_process(false) # Hold it still so the check is about the gun, not the chase.
	var cam := world.camera
	# Just beside the drone on screen: the sight line runs past it to the ground far behind.
	tank.aim_screen = cam.unproject_position(drone.hit_center()) + Vector2(0, 14)
	await frames(40)
	check(tank.aim_target == null and tank.aim_point.distance_to(drone.hit_center()) > 30.0, "the sight itself rests on the ground past the drone")
	check(tank.coax_target == drone, "the drone is soft-locked")
	var barrel := -tank.model.barrel.global_basis.z
	var to_drone := (drone.hit_center() - tank.model.muzzle.global_position).normalized()
	check(barrel.angle_to(to_drone) < deg_to_rad(6.0), "the barrel points close enough for rounds to reach it (off by %.1f°)" % rad_to_deg(barrel.angle_to(to_drone)))
	var start := drone.hp
	tank.fire_cannon()
	check(drone.dead or drone.hp < start, "the main gun hits it")
	cleanup()
