extends TestCase
## Aircraft predict observed ground motion without moving an already announced attack.

const DT := 1.0 / 60.0


func _world_at(d: float, u := 0.0) -> World:
	var world := stage("", false)
	world.set_process(false)
	world.player.set_process(false)
	world.director.events.clear()
	world.rail.d = d
	world.player.course_u = u
	world.player._place(d)
	world.player._last_position = world.player.global_position
	return world


func _heli(world: World) -> Helicopter:
	var heli := Helicopter.new()
	heli.position = Course.ground_at(world.rail.d + world.player.course_offset + 55.0, 0.0) + Vector3.UP * 13.0
	world.add_enemy(heli)
	heli.set_process(false)
	heli._attack_timer = INF
	return heli


func _rotor(world: World) -> Tiltrotor:
	var rotor := Tiltrotor.new()
	world.add_enemy(rotor)
	rotor.set_process(false)
	rotor.global_position = Course.ground_at(world.rail.d + world.player.course_offset + 36.0, 16.0) + Vector3.UP * 10.0
	rotor.state = Tiltrotor.State.HOVER
	rotor._tilt = 1.0
	rotor._ramp = 1.0
	rotor._dropped = true
	rotor._hover = Tiltrotor.SWEEP_AT + DT
	return rotor


func _step(world: World, enemy: Enemy) -> void:
	world.player.tick(DT)
	enemy.tick(DT)
	for shot: Projectile in world.projectiles.duplicate():
		if not shot.is_queued_for_deletion():
			shot.step(DT)


func test_helicopter_drift_lead_does_not_extrapolate_terrain_rise_into_the_air() -> void:
	var world := _world_at(800.0, 12.0)
	var tank := world.player
	var heli := _heli(world)
	tank.dash(Vector2.RIGHT)
	for frame in 20:
		tank.tick(DT)
		if tank.velocity.y > 10.0:
			break
	check(tank.velocity.y > 10.0, "production drift changes terrain footprint height, not sustained altitude")
	var aim := heli._aim_point(tank)
	var offset := tank.model.sensor_position("fcs") - tank.global_position
	var root := aim - offset
	var forward := Vector3(-sin(tank.hull_yaw), 0.0, -cos(tank.hull_yaw))
	var right := forward.cross(Vector3.UP)
	var heights := [Course.height_at(root + forward * 3.0), Course.height_at(root - forward * 3.0), Course.height_at(root + right * 1.6), Course.height_at(root - right * 1.6)]
	# Any footprint average lies within its sample extrema; 1 cm covers world-coordinate float rounding.
	check(root.y >= heights.min() - 0.01 and root.y <= heights.max() + 0.01, "the lead remains at sensor height over predicted terrain")


func test_tiltrotor_warning_predicts_dash_deceleration_instead_of_a_mountain_lane() -> void:
	for difficulty in [Game.Difficulty.EASY, Game.Difficulty.NORMAL, Game.Difficulty.HARD]:
		for side in [-1.0, 1.0]:
			Game.difficulty = difficulty
			var world := _world_at(100.0)
			var tank := world.player
			tank.dash(Vector2(side, 0.0))
			tank.tick(DT)
			var rotor := _rotor(world)
			rotor.behave(DT)
			var a := rotor._line_a
			var b := rotor._line_b
			var predicted := Course.to_course((a + b) * 0.5).y
			for frame in int(ceil((Tiltrotor.SWEEP_WIND * Game.telegraph_scale() + Tiltrotor.SWEEP_TIME) / DT)):
				tank.tick(DT)
			# A transverse line must cover the no-new-input dash endpoint: its half-width is the contract.
			check(absf(predicted - tank.course_u) < Tiltrotor.SWEEP_HALF, "the committed line covers the observed dash, not the valley wall")
			check(rotor._line_a == a and rotor._line_b == b, "player movement does not move the committed warning")
			cleanup()


func test_tiltrotor_sweep_hits_a_vulnerable_tank_that_stays_in_its_announced_path() -> void:
	var world := _world_at(100.0)
	var tank := world.player
	tank.dash(Vector2.RIGHT)
	tank.tick(DT)
	var rotor := _rotor(world)
	var hp := tank.hp
	var modules := tank.modules.hp.duplicate()
	for frame in 240:
		_step(world, rotor)
	check(tank.hp < hp or tank.modules.hp != modules, "the actual sweep rounds affect the tank after its dash invulnerability ends")


func test_helicopter_gun_burst_hits_ground_target_after_drift() -> void:
	var world := _world_at(800.0, 12.0)
	var tank := world.player
	var heli := _heli(world)
	tank.dash(Vector2.RIGHT)
	for frame in 8:
		tank.tick(DT)
		heli.tick(DT)
	# Isolate the fire computer from initial traverse: the bore has acquired its requested target.
	heli.aim_barrel(heli._chin, heli._aim_point(tank), 100.0, 1.0)
	heli._burst = 6
	var hp := tank.hp
	var modules := tank.modules.hp.duplicate()
	for frame in 80:
		_step(world, heli)
	check(tank.hp < hp or tank.modules.hp != modules, "the production gun burst affects the ground target after dodge invulnerability expires")


func test_tiltrotor_warning_stays_fixed_and_steering_out_of_it_avoids_damage() -> void:
	var world := _world_at(100.0)
	var tank := world.player
	var rotor := _rotor(world)
	_step(world, rotor)
	var a := rotor._line_a
	var b := rotor._line_b
	var hp := tank.hp
	var modules := tank.modules.hp.duplicate()
	var tail_hp := tank.tail.hp
	var lives := world.stats.lives
	tank.input_enabled = true
	Input.action_press("move_left")
	for frame in 240:
		_step(world, rotor)
	Input.action_release("move_left")
	check(rotor._line_a == a and rotor._line_b == b, "ordinary steering does not drag the committed danger line")
	check_eq(tank.hp, hp, "leaving the warned line avoids hull damage without dash invulnerability")
	check_eq(tank.modules.hp, modules, "leaving the warned line avoids sensor damage")
	check_eq(tank.tail.hp, tail_hp, "leaving the warned line avoids tail damage")
	check_eq(world.stats.lives, lives, "leaving the warned line costs no life")


func test_sweep_samples_terrain_between_its_fixed_endpoints() -> void:
	var world := _world_at(100.0)
	var rotor := _rotor(world)
	rotor._line_a = Course.ground_at(105.0, -9.0) + Vector3.UP * 0.2
	rotor._line_b = Course.ground_at(105.0, 9.0) + Vector3.UP * 0.2
	for fraction in [0.25, 0.5, 0.75]:
		rotor._sweep = Tiltrotor.SWEEP_TIME * (1.0 - fraction)
		var point := rotor._sweep_point()
		# 1 mm covers arithmetic rounding; the contract is terrain clearance, not endpoint-height lerp.
		check_near(point.y - Course.height_at(point), 0.2, 0.001, "the live sweep follows terrain relief")


func test_prediction_ignores_future_controls_and_respects_arena_and_corridor_edges() -> void:
	var world := _world_at(100.0, 29.0)
	var tank := world.player
	tank.dash(Vector2.RIGHT)
	tank.tick(DT)
	var predicted := Gunnery.ground_position(tank, 3.0)
	Input.action_press("move_left")
	check(Gunnery.ground_position(tank, 3.0).is_equal_approx(predicted), "prediction does not read a new movement command")
	Input.action_release("move_left")
	var course := Course.to_course(predicted)
	check(absf(course.y) <= Tank.lateral_limit(course.x) + 0.01, "predicted hull stays inside the permitted corridor")
	world.rail.mode = Rail.Mode.ARENA
	world.rail.speed = 0.0
	var center := Course.to_world(Course.ARENA_CENTER_D, 0.0)
	tank._drift = 0.0
	tank.global_position = center
	tank.velocity = Vector3(32.0, 50.0, 0.0)
	predicted = Gunnery.ground_position(tank, 10.0)
	check(Vector2(predicted.x - center.x, predicted.z - center.z).length() <= Course.ARENA_RADIUS - 6.0 + 0.01, "prediction obeys the arena boundary instead of extrapolating flight")
	check(Gunnery.ground_position(tank, 0.0).is_equal_approx(tank.global_position), "zero-horizon prediction preserves the current pose")


func _rocket_volley(dodge: bool) -> void:
	Course.flat = true
	var world := _world_at(100.0)
	var tank := world.player
	var heli := _heli(world)
	heli._rockets = true
	for frame in 90:
		_step(world, heli)
	heli._telegraph = DT * 0.5
	_step(world, heli)
	var locked := heli._rocket_aim
	var hp := tank.hp
	var modules := tank.modules.hp.duplicate()
	var tail_hp := tank.tail.hp
	var lives := world.stats.lives
	if dodge:
		tank.input_enabled = true
		Input.action_press("move_left")
	var seen: Array[Projectile] = []
	for frame in 180:
		tank.tick(DT)
		heli.tick(DT)
		for shot: Projectile in world.projectiles.duplicate():
			if shot.hit.source == heli and not seen.has(shot):
				seen.append(shot)
				# 3 degrees of bore correction plus <=1.5 degrees from the rocket's scatter cone.
				check(rad_to_deg(shot.velocity.angle_to(locked - shot.global_position)) < 5.0, "each actual rocket leaves toward the original locked point")
			if not shot.is_queued_for_deletion():
				shot.step(DT)
	check_eq(seen.size(), 2, "both rockets actually launch")
	check_eq(heli._rocket_aim, locked, "the rocket pair retains its committed point")
	Input.action_release("move_left")
	if dodge:
		check_eq(tank.hp, hp, "ordinary steering after rocket lock avoids hull damage")
		check_eq(tank.modules.hp, modules, "ordinary steering after rocket lock avoids sensor damage")
		check_eq(tank.tail.hp, tail_hp, "ordinary steering after rocket lock avoids tail damage")
		check_eq(world.stats.lives, lives, "ordinary steering after rocket lock costs no life")
	else:
		check(tank.hp < hp or tank.modules.hp != modules, "the real rocket pair affects a vulnerable tank holding course")


func test_rocket_pair_hits_a_vulnerable_tank_holding_course() -> void:
	_rocket_volley(false)


func test_steering_after_rocket_lock_avoids_damage_without_moving_the_aim() -> void:
	_rocket_volley(true)


func test_sweep_slews_before_launching_from_the_current_bore() -> void:
	var world := _world_at(100.0)
	var rotor := _rotor(world)
	rotor._sweep_done = true
	for frame in 60:
		_step(world, rotor)
	rotor._line_across(world.player)
	rotor._sweep = 1.0
	var direction := rotor._sweep_point() - rotor._gun.global_position
	rotor._gun.global_basis = Basis.looking_at(direction.rotated(Vector3.UP, deg_to_rad(10.0)))
	rotor._hover_tasks(DT * 2.0, world.player)
	var rounds := world.projectiles.filter(func(shot: Projectile) -> bool: return shot.hit.source == rotor)
	check_eq(rounds.size(), 1, "the sweeping gun actually launches a round")
	if rounds.is_empty():
		return
	var shot: Projectile = rounds[0]
	# 7.6 degrees of slew plus 4 of correction acquire the 10-degree offset; scatter/jitter stay below 2.5.
	check(rad_to_deg(shot.velocity.angle_to(rotor._sweep_point() - shot.global_position)) < 2.5, "the shot uses this update's gun solution, not the previous bore")


func test_rendered_sweep_path_matches_terrain_and_is_reused_until_interrupt() -> void:
	var world := _world_at(100.0)
	var rotor := _rotor(world)
	rotor.behave(DT)
	var mesh := rotor._line_mesh.mesh
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for segment in 12:
		var center := Vector3.ZERO
		# LowPoly.box emits twelve triangles per segment; averaging their vertices finds its centre.
		for index in range(segment * 36, (segment + 1) * 36):
			center += rotor._line_mesh.to_global(vertices[index]) / 36.0
		var from := rotor._line_a.lerp(rotor._line_b, segment / 12.0)
		var to := rotor._line_a.lerp(rotor._line_b, (segment + 1) / 12.0)
		from.y = Course.height_at(from) + 0.2
		to.y = Course.height_at(to) + 0.2
		check(center.distance_to((from + to) * 0.5) < 0.001, "the visible danger path uses the same terrain as the live sweep")
	for frame in 30:
		_step(world, rotor)
	check(rotor._line_mesh.visible and rotor._line_mesh.mesh == mesh, "moving the aircraft reuses the committed warning mesh")
	rotor.interrupt()
	check(not rotor._line_mesh.visible, "interrupt removes the visible danger line")
	rotor._line_mesh.visible = true
	world.player.dead = true
	rotor.behave(DT)
	check(not rotor._line_mesh.visible, "game-over does not retain an active danger line")


func _strafe(dodge: bool) -> void:
	Course.flat = true
	var world := _world_at(100.0)
	world.rail.mode = Rail.Mode.HOLD
	world.rail.hold_at = world.rail.d
	world.rail.speed = 0.0
	var tank := world.player
	var heli := _heli(world)
	for frame in 90:
		_step(world, heli)
	heli._strafing = true
	heli._attack_timer = 0.0
	_step(world, heli)
	var lane := heli._strafe_u
	var hp := tank.hp
	var modules := tank.modules.hp.duplicate()
	var tail_hp := tank.tail.hp
	if dodge:
		tank.input_enabled = true
		Input.action_press("move_left")
	for frame in 150:
		_step(world, heli)
	Input.action_release("move_left")
	check_eq(heli._strafe_u, lane, "the strafing run keeps the lane announced before steering")
	if dodge:
		check_eq(tank.hp, hp, "leaving the strafing lane avoids hull damage without invulnerability")
		check_eq(tank.modules.hp, modules, "leaving the strafing lane avoids sensor damage")
		check_eq(tank.tail.hp, tail_hp, "leaving the strafing lane avoids tail damage")
	else:
		check(tank.hp < hp or tank.modules.hp != modules, "staying in the strafing path accepts actual round damage")


func test_helicopter_strafe_damages_a_vulnerable_tank_in_the_announced_lane() -> void:
	_strafe(false)


func test_steering_out_of_the_helicopter_strafe_lane_avoids_damage() -> void:
	_strafe(true)


func test_forecast_follows_observed_course_motion_on_both_sides_of_a_bend() -> void:
	for side in [-1.0, 1.0]:
		var world := _world_at(655.0, side * 25.0)
		var tank := world.player
		tank.tick(DT)
		var predicted := Gunnery.ground_position(tank, 2.0)
		for frame in 120:
			tank.tick(DT)
		# Course velocity is sampled over a physics step; allow one rail step of XZ scheduling error.
		check(Vector2(predicted.x, predicted.z).distance_to(Vector2(tank.global_position.x, tank.global_position.z)) < world.rail.speed * DT, "unchanged rail motion is predicted around the bend, not along its tangent")
		cleanup()


func test_forecast_stops_backward_offset_at_the_rear_rail_boundary() -> void:
	var world := _world_at(100.0)
	var tank := world.player
	tank.input_enabled = true
	Input.action_press("move_back")
	for frame in 6:
		tank.tick(DT)
	var d := world.rail.d
	var predicted := Course.to_course(Gunnery.ground_position(tank, 1.0)).x
	var rear := d + world.rail.speed + Tank.FORWARD_LIMIT.x
	check_near(predicted, rear, 0.01, "sustained backward movement reaches, then stops at, the rear rail offset")
	Input.action_release("move_back")


func test_ground_lead_handles_an_unreachable_round_without_unbounded_forecasts() -> void:
	var world := _world_at(100.0)
	var tank := world.player
	var sensor := tank.model.sensor_position("fcs")
	check(Gunnery.ground_lead(tank, sensor + Vector3.UP * 1000.0, 1.0).is_equal_approx(sensor), "an unreachable round falls back to the current bounded target")
	check(Gunnery.ground_lead(tank, sensor, 0.0).is_equal_approx(sensor), "zero speed does not divide by zero")
