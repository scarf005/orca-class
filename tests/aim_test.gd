extends TestCase
## The aiming reticle stays put while air targets weave: a steady sight range, a held soft lock and a smoothed lead.

const JUMP_PX := 12.0 ## Largest per-frame chevron move (3D view pixels at 960x540) after settling.


func _chevron(tank: Tank) -> Vector2:
	return World.current.camera.unproject_position(tank.sight_point())


func _hold_rail(world: World) -> void:
	world.rail.mode = Rail.Mode.HOLD
	world.rail.hold_at = world.rail.d


func _drone(world: World, ahead: float, u: float) -> FpvDrone:
	var drone := FpvDrone.new()
	drone.slot = Vector3(u, 11.0, ahead)
	drone.approach_time = 999.0 # Hovers and weaves instead of diving.
	drone.position = Course.ground_at(world.rail.d + 4.0 + ahead, u) + Vector3.UP * 11.0
	drone.invulnerable = true
	world.add_enemy(drone)
	return drone


## Runs `count` frames with the cursor at `spot(frame)`; returns the worst chevron step after the
## first 10 frames and how often the lock, the aim target and the raw aim range (over 20 m) flipped.
func _run(tank: Tank, spot: Callable, count: int) -> Dictionary:
	var worst := 0.0
	var lock_flips := 0
	var aim_flips := 0
	var range_jumps := 0
	var last := Vector2.INF
	var last_lock: Entity = null
	var last_aim: Entity = null
	var last_range := 0.0
	for i in count:
		tank.aim_screen = spot.call(i)
		await frames(1)
		var at := _chevron(tank)
		var range_m := tank.model.muzzle.global_position.distance_to(tank.aim_point)
		if i >= 10:
			worst = maxf(worst, at.distance_to(last))
			lock_flips += int(tank.coax_target != last_lock)
			aim_flips += int(tank.aim_target != last_aim)
			range_jumps += int(absf(range_m - last_range) > 20.0)
		last = at
		last_lock = tank.coax_target
		last_aim = tank.aim_target
		last_range = range_m
	return {"worst": worst, "lock_flips": lock_flips, "aim_flips": aim_flips, "range_jumps": range_jumps}


func test_the_sight_holds_steady_on_a_weaving_drone() -> void:
	var world := stage()
	var tank := world.player
	_hold_rail(world)
	var drone := _drone(world, 40.0, 0.0)
	await frames(30)
	# A fixed cursor at the edge of the drone's hit shape: it weaves across, so the ray alternates
	# between the drone (~40 m) and the ground far behind it.
	var spot := world.camera.unproject_position(drone.hit_center()) + Vector2(10, 0)
	var result := await _run(tank, func(_i: int) -> Vector2: return spot, 240)
	check(result.worst < JUMP_PX, "the chevron moves at most %.1f px a frame" % result.worst)
	check(result.lock_flips <= 2, "the lock flips %d times" % result.lock_flips)
	check(tank.sight_range < 80.0, "the sight rests near the drone, not the ground behind it (%.0f m)" % tank.sight_range)
	cleanup()


func test_the_sight_holds_steady_on_a_uav_pass() -> void:
	var world := stage()
	var tank := world.player
	_hold_rail(world)
	var uav := Uav.new()
	uav.position = Course.ground_at(world.rail.d + 120.0, 3.0) + Vector3.UP * Uav.ALTITUDE
	uav.invulnerable = true
	world.add_enemy(uav)
	await frames(2)
	var cam := world.camera
	var result := await _run(tank, func(_i: int) -> Vector2: return cam.unproject_position(uav.hit_center()) + Vector2(0, 12), 150)
	check(result.worst < JUMP_PX, "the chevron moves at most %.1f px a frame" % result.worst)
	check(result.lock_flips <= 2, "the lock flips %d times" % result.lock_flips)
	cleanup()


func test_a_held_lock_survives_two_drones_at_the_same_distance() -> void:
	var world := stage()
	var tank := world.player
	_hold_rail(world)
	var left := _drone(world, 40.0, -2.0)
	var right := _drone(world, 40.0, 2.0)
	await frames(2)
	left.set_process(false)
	right.set_process(false)
	var cam := world.camera
	var mid := (cam.unproject_position(left.hit_center()) + cam.unproject_position(right.hit_center())) * 0.5
	tank.aim_target = null
	var flips := 0
	var last: Entity = null
	for i in 60:
		tank.aim_screen = mid + Vector2(1.0 if i % 2 == 0 else -1.0, 0)
		await frames(1)
		tank.aim_target = null
		var lock := tank._pick_coax_target()
		flips += int(lock != last)
		last = lock
	check(flips <= 2, "the lock flips %d times over 60 frames" % flips)
	check(last == left or last == right, "and it holds one of them")
	cleanup()


func test_a_much_nearer_enemy_takes_the_lock_and_one_under_the_cursor_at_once() -> void:
	var world := stage()
	var tank := world.player
	_hold_rail(world)
	var far := _drone(world, 40.0, -6.0)
	var near := _drone(world, 40.0, 6.0)
	await frames(2)
	far.set_process(false)
	near.set_process(false)
	var cam := world.camera
	var far_at := cam.unproject_position(far.hit_center())
	var near_at := cam.unproject_position(near.hit_center())
	tank.aim_target = null
	tank.aim_screen = far_at + Vector2(-2, 0)
	check(tank._pick_coax_target() == far, "the drone by the cursor locks")
	tank.aim_screen = far_at.lerp(near_at, 0.4)
	check(tank._pick_coax_target() == far, "the lock stays while the other is not clearly nearer")
	tank.aim_screen = near_at + Vector2(0, 8)
	check(tank._pick_coax_target() == near, "one much nearer the cursor takes it")
	tank.aim_screen = Vector2(20, 20)
	check(tank._pick_coax_target() == null, "and a lost lock is dropped")
	tank.aim_target = far
	tank.aim_screen = near_at
	check(tank._pick_coax_target() == far, "the enemy under the reticle wins at once")
	cleanup()


func test_lead_velocity_converges_and_ignores_a_teleport() -> void:
	var world := stage()
	var enemy := Enemy.new()
	world.add_enemy(enemy)
	enemy.set_process(false)
	enemy.despawn_behind = 0.0
	var step := Vector3(0.5, 0.0, -0.25)
	for _i in 60:
		enemy.global_position += step
		enemy.tick(1.0 / 60.0)
	check((enemy.track_velocity - step * 60.0).length() < 1.0, "it settles on the true velocity (%s)" % enemy.track_velocity)
	enemy.global_position += Vector3(80.0, 0.0, 0.0)
	enemy.tick(1.0 / 60.0)
	check(enemy.velocity.x > 1000.0, "the raw velocity spikes")
	check((enemy.track_velocity - step * 60.0).length() < 1.0, "the smoothed one does not (%s)" % enemy.track_velocity)
	enemy.tick(0.0)
	check(is_finite(enemy.track_velocity.x) and (enemy.track_velocity - step * 60.0).length() < 1.0, "a zero-length frame changes nothing")
	cleanup()
