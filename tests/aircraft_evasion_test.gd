extends TestCase


func _rig() -> World:
	var world := stage()
	world.set_process(false)
	world.director.set_process(false)
	world.player.set_process(false)
	Course.flat = true
	world.rail.mode = Rail.Mode.ARENA
	return world


func _flyer(world: World, kind: String) -> Enemy:
	seed(700)
	if kind == "gunship":
		world.rail.d = Course.ARENA_CENTER_D - 60.0
		world.player.global_position = Course.to_world(world.rail.d, 0.0)
	var flyer: Enemy = load(Director.ENEMY_SCRIPTS[kind]).new()
	world.add_enemy(flyer)
	flyer.set_process(false)
	flyer.global_position = Course.to_world(world.rail.d + 80.0, 10.0, 20.0)
	if flyer is Helicopter:
		flyer._lane = 10.0
		flyer._height = 20.0
		flyer._attack_timer = 100.0
	elif flyer is Tiltrotor:
		flyer._lane = 10.0
		flyer._height = 20.0
	elif flyer is Gunship:
		flyer._next_attack = 100.0
		var center := Course.to_world(Course.ARENA_CENTER_D, 0.0)
		flyer.global_position = world.player.global_position.lerp(center, 0.5) + Vector3(90, 42, 0)
	elif flyer is Uav:
		# Keep the tank ahead throughout the 8 s sample: a normal pass-end U-turn must not
		# masquerade as a repeated evasive turn. The initial separation stays within shell range.
		world.player.global_position = Course.to_world(world.rail.d - 220.0, 10.0)
	flyer._last_position = flyer.global_position
	return flyer


func _path(kind: String, locked: bool, mode: Game.Difficulty) -> Array[Vector3]:
	Game.difficulty = mode
	var world := _rig()
	var flyer := _flyer(world, kind)
	world.player.charge_lock = flyer if locked else null
	var positions: Array[Vector3] = []
	for i in 480:
		flyer.tick(1.0 / 60.0)
		positions.append(flyer.global_position)
		if locked:
			check_eq(world.player.charge_lock, flyer, "a held lock survives every flight-controller step")
	return positions


func test_all_evasive_aircraft_repeat_lateral_maneuvers_through_eight_seconds_of_lock() -> void:
	for kind in ["helicopter", "tiltrotor", "uav", "gunship"]:
		var ordinary := _path(kind, false, Game.Difficulty.HARD)
		var evasive := _path(kind, true, Game.Difficulty.HARD)
		var low := 0.0
		var high := 0.0
		var late_motion := 0.0
		var previous := Vector3.ZERO
		for i in evasive.size():
			var displacement := evasive[i] - ordinary[i]
			var lateral_speed := (displacement.x - previous.x) * 60.0
			low = minf(low, lateral_speed)
			high = maxf(high, lateral_speed)
			if i >= 240:
				late_motion += displacement.distance_to(previous)
			previous = displacement
		check(low < -1.0 and high > 1.0, kind + " reverses its evasive lateral travel at more than 1 m/s in both directions")
		check(late_motion > 4.0, kind + " keeps changing its flight path after the old 2.8-second cooldown")


func test_easy_difficulty_lock_does_not_change_any_aircraft_flight_path() -> void:
	for kind in ["helicopter", "tiltrotor", "uav", "gunship"]:
		var ordinary := _path(kind, false, Game.Difficulty.EASY)
		var locked := _path(kind, true, Game.Difficulty.EASY)
		check(locked == ordinary, kind + " retains its easy flight path")


func test_normal_aircraft_attempt_evasion_with_less_than_a_quarter_of_hards_displacement() -> void:
	for kind in ["helicopter", "tiltrotor", "uav", "gunship"]:
		var normal_base := _path(kind, false, Game.Difficulty.NORMAL)
		var normal := _path(kind, true, Game.Difficulty.NORMAL)
		var hard_base := _path(kind, false, Game.Difficulty.HARD)
		var hard := _path(kind, true, Game.Difficulty.HARD)
		var slow := 0.0
		var fast := 0.0
		for i in normal.size():
			slow = maxf(slow, normal[i].distance_to(normal_base[i]))
			fast = maxf(fast, hard[i].distance_to(hard_base[i]))
		check(slow > 0.05, kind + " performs a real, nonzero evasive movement on Normal")
		# A tenfold-smaller goal and slower response must give clearly smaller travel even
		# though each airframe's flight controller filters the maneuver differently.
		check(slow < fast * 0.25, kind + " sluggish Normal evasion travels less than a quarter of Hard")


func test_fixed_wing_evasion_banks_and_turns_without_side_slipping_or_changing_airspeed() -> void:
	for mode in [Game.Difficulty.NORMAL, Game.Difficulty.HARD]:
		Game.difficulty = mode
		var scale := 0.1 if mode == Game.Difficulty.NORMAL else 1.0
		var world := _rig()
		var flyer := _flyer(world, "uav") as Uav
		flyer.global_position.y = Uav.ALTITUDE
		world.player.charge_lock = flyer
		var previous := flyer.global_position
		var bank := 0.0
		var saw_bank := false
		for i in 60:
			flyer.tick(1.0 / 60.0)
			var motion := flyer.global_position - previous
			motion.y = 0.0
			# Float roundoff over a 1/60 s step at course coordinates; 1 mm is far below the airframe size.
			check_near(motion.length(), Uav.HEAD_ON_SPEED / 60.0, 0.001, "turning preserves cruise speed")
			check(motion.normalized().dot(-flyer.model.global_basis.z) > 0.999, "the nose follows travel, not a lateral position kick")
			check(absf(flyer._evade_bank - bank) <= 0.9 * scale / 60.0 + 0.00001, "bank changes at the difficulty's roll-rate bound")
			check(flyer.model.global_basis.x.y * flyer._evade_bank >= 0.0, "the inside wing lowers into the turn")
			saw_bank = saw_bank or absf(flyer.model.rotation.z) > 0.1 * scale
			previous = flyer.global_position
			bank = flyer._evade_bank
		check(saw_bank, "the production airframe banks into its turn on both difficulties")


func test_rotorcraft_start_without_a_velocity_kick_and_settle_when_the_lock_ends() -> void:
	for mode in [Game.Difficulty.NORMAL, Game.Difficulty.HARD]:
		Game.difficulty = mode
		var scale := 0.1 if mode == Game.Difficulty.NORMAL else 1.0
		var world := _rig()
		var flyer := _flyer(world, "helicopter")
		var origin := flyer.global_position
		world.player.charge_lock = flyer
		var previous := origin
		var lateral_speed := 0.0
		for i in 180:
			flyer.tick(1.0 / 60.0)
			var speed := (flyer.global_position.x - previous.x) * 60.0
			var acceleration := (speed - lateral_speed) * 60.0
			var thrust := flyer.model.global_basis.y
			# Double differencing 32-bit positions at x=10 m introduces <0.02 m/s² of roundoff.
			check_near(acceleration, 9.81 * thrust.x / thrust.y, 0.02, "visible rotor thrust supplies the actual horizontal acceleration")
			check(absf(acceleration) <= 9.81 * tan(0.65 * scale) + 0.02, "rotorcraft accelerates within its difficulty's achievable tilt")
			previous = flyer.global_position
			lateral_speed = speed
		world.player.charge_lock = null
		# The 2/4 position controller has a roughly 2 s slow pole; allow five time constants to settle.
		for i in 600:
			flyer.tick(1.0 / 60.0)
		check(flyer.global_position.distance_to(Vector3(origin.x, flyer.global_position.y, origin.z)) < 0.05, "losing the lock returns to the original arena position without drift: %s" % flyer._jink_offset)
		check(not flyer._jink_active, "an ended lock does not begin another weave")


func test_rotorcraft_attitude_is_continuous_when_acquiring_and_releasing_a_lock_after_ordinary_flight() -> void:
	for mode in [Game.Difficulty.NORMAL, Game.Difficulty.HARD]:
		Game.difficulty = mode
		var rate := 0.09 if mode == Game.Difficulty.NORMAL else 0.9
		for kind in ["helicopter", "tiltrotor"]:
			var world := _rig()
			var flyer := _flyer(world, kind)
			for i in 150:
				flyer.tick(1.0 / 60.0)
			var up := flyer.model.global_basis.y.normalized()
			check(up.angle_to(Vector3.UP) > 0.02, kind + " starts acquisition from an established nonzero ordinary attitude")
			world.player.charge_lock = flyer
			for i in 960:
				if i == 360:
					world.player.charge_lock = null
				var banking := flyer._jink_banking
				flyer.tick(1.0 / 60.0)
				var next := flyer.model.global_basis.y.normalized()
				# Ordinary bobbing keeps its existing rate after evasion has handed control back.
				if banking or flyer._jink_banking:
					check(up.angle_to(next) <= rate / 60.0 + 0.00001, kind + " thrust axis stays within the difficulty's roll-rate bound during takeover, reversal and handoff")
				up = next
			check(not flyer._jink_banking, kind + " eventually hands attitude control back to ordinary flight")


func test_rotorcraft_evasion_preserves_nominal_travel_through_a_curved_road() -> void:
	Game.difficulty = Game.Difficulty.HARD
	for kind in ["helicopter", "tiltrotor"]:
		var world := _rig()
		world.rail.d = 950.0
		world.rail.mode = Rail.Mode.HOLD
		world.player.global_position = Course.to_world(world.rail.d, 0.0)
		var flyer := _flyer(world, kind)
		var ordinary := _flyer(world, kind)
		world.player.charge_lock = flyer
		for i in 300:
			flyer.tick(1.0 / 60.0)
			ordinary.tick(1.0 / 60.0)
			var difference := flyer.global_position - ordinary.global_position - flyer._jink_offset
			difference.y = 0.0
			# Inverse course conversion at kilometre-scale float coordinates accumulates roundoff;
			# 0.1 m is below the smallest aircraft hit sphere (0.7 m).
			check(difference.length() < 0.1, kind + " keeps its nominal course while adding the full smooth evasive trajectory")


func test_tracking_a_production_charge_lock_keeps_it_through_evasive_flight() -> void:
	Game.difficulty = Game.Difficulty.HARD
	var world := _rig()
	var flyer := _flyer(world, "helicopter")
	var tank := world.player
	tank.input_enabled = true
	tank._fire_held = true
	tank._hold = Armament.TAP_TIME + 0.1
	tank.using_gamepad = true
	world.camera.global_position = tank.global_position + Vector3.UP * 8.0
	world.camera.look_at(flyer.hit_center(), Vector3.UP)
	tank.aim_screen = world.camera.unproject_position(flyer.hit_center())
	tank._update_aim(0.0)
	check_eq(tank.charge_lock, flyer, "the production sight acquires the aerial target")
	var origin := flyer.global_position
	for i in 240:
		flyer.tick(1.0 / 60.0)
		check_eq(tank.charge_lock, flyer, "maneuvering does not cancel an acquired charge lock")
		tank.aim_screen = world.camera.unproject_position(flyer.hit_center())
		tank._update_aim(1.0 / 60.0)
		check_eq(tank.charge_lock, flyer, "tracking the moving target preserves the production lock")
	check(flyer.global_position.distance_to(origin) > 1.0, "an acquired lock drives actual aircraft movement")


func test_side_on_rotorcraft_follow_the_full_horizontal_evasion_direction() -> void:
	Game.difficulty = Game.Difficulty.HARD
	for kind in ["helicopter", "tiltrotor"]:
		var world := _rig()
		var flyer := _flyer(world, kind)
		var ordinary := _flyer(world, kind)
		flyer.model.rotation.y = PI / 2.0
		ordinary.model.rotation.y = PI / 2.0
		world.player.global_position = flyer.global_position + Vector3.LEFT * 90.0
		world.player.charge_lock = flyer
		for i in 90:
			flyer.tick(1.0 / 60.0)
			ordinary.tick(1.0 / 60.0)
		var displacement := flyer.global_position - ordinary.global_position
		check(absf(displacement.z) > 1.0, kind + " follows airframe-right even when it lies along the road")
		check_eq(world.player.charge_lock, flyer, "side-on movement keeps the lock")


func test_stagger_and_crash_paths_do_not_start_new_evasion() -> void:
	Game.difficulty = Game.Difficulty.HARD
	for kind in ["helicopter", "tiltrotor", "uav", "gunship"]:
		var world := _rig()
		var flyer := _flyer(world, kind)
		world.player.charge_lock = flyer
		flyer.stagger = 1.0
		flyer.tick(1.0 / 60.0)
		check(not flyer._jink_active, kind + " cannot start a weave while staggered")
		flyer.stagger = 0.0
		if flyer is Uav:
			flyer._falling = true
		elif flyer is Tiltrotor:
			flyer.state = Tiltrotor.State.CRASH
		elif flyer is Gunship:
			flyer._crash = 1.0
		else:
			continue
		var phase := flyer._jink_phase
		flyer.tick(1.0 / 60.0)
		check_eq(flyer._jink_phase, phase, kind + " crash movement bypasses the evasion controller")


func _tank_at_range(world: World, flyer: Enemy, distance: float) -> void:
	var tank := world.player
	tank.global_position = flyer.hit_center() + Vector3.FORWARD * distance
	tank.global_position.y = 0.0
	# Place the actual muzzle, rather than the hull origin, at the reported range.
	for i in 3:
		tank.model.barrel.look_at(flyer.hit_center(), Vector3.UP)
		var actual := tank.model.muzzle.global_position.distance_to(flyer.hit_center())
		tank.global_position += Vector3.FORWARD * (distance - actual)


func _unlocked_bore_path(kind: String, near: bool) -> Array[Vector3]:
	Game.difficulty = Game.Difficulty.HARD
	var world := _rig()
	var flyer := _flyer(world, kind)
	_tank_at_range(world, flyer, 100.0)
	var tank := world.player
	check_near(tank.model.muzzle.global_position.distance_to(flyer.hit_center()), 100.0, 0.01, "the real muzzle begins at the reported 100 m range")
	if not near:
		tank.model.barrel.look_at(tank.model.barrel.global_position + Vector3.FORWARD, Vector3.UP)
	var positions: Array[Vector3] = []
	for i in 60:
		if near:
			tank.model.barrel.look_at(flyer.hit_center(), Vector3.UP)
		flyer.tick(1.0 / 60.0)
		positions.append(flyer.global_position)
		check_eq(flyer._jink_active, near, kind + " reacts on the first flight step and throughout bore tracking")
		check(tank.charge_lock == null and tank.aim_target == null and tank.coax_target == null and not tank.is_charging(), "barrel awareness needs neither sight selection nor charging nor a lock")
	return positions


func test_all_evasive_aircraft_move_as_soon_as_an_unlocked_barrel_points_near_them_at_100_m() -> void:
	for kind in ["helicopter", "tiltrotor", "uav", "gunship"]:
		var ordinary := _unlocked_bore_path(kind, false)
		var threatened := _unlocked_bore_path(kind, true)
		check(threatened.back().distance_to(ordinary.back()) > 0.01, kind + " changes its actual flight path before the player charges or locks")


func test_barrel_near_miss_starts_flight_but_away_behind_out_of_range_and_easy_do_not() -> void:
	for scenario in ["near", "away", "behind", "range", "normal", "easy"]:
		Game.difficulty = Game.Difficulty.NORMAL if scenario == "normal" else (Game.Difficulty.EASY if scenario == "easy" else Game.Difficulty.HARD)
		var world := _rig()
		var flyer := _flyer(world, "helicopter")
		_tank_at_range(world, flyer, 500.0 if scenario == "range" else 100.0)
		var tank := world.player
		var aim := flyer.hit_center() + Vector3.RIGHT * (20.0 if scenario == "away" else 5.0)
		if scenario == "behind":
			aim = tank.model.barrel.global_position + Vector3.FORWARD
		tank.model.barrel.look_at(aim, Vector3.UP)
		if scenario == "near":
			var muzzle := tank.model.muzzle.global_position
			var end := muzzle - tank.model.barrel.global_basis.z.normalized() * Armament.SHELL_RANGE
			check(flyer.hit_test(muzzle, end) < 0.0, "the near barrel ray does not intersect the real helicopter hit shape")
		var origin := flyer.global_position
		for i in 60:
			flyer.tick(1.0 / 60.0)
		var horizontal := flyer.global_position - origin
		horizontal.y = 0.0
		check_eq(horizontal.length() > 0.01, scenario in ["near", "normal"], scenario + " flight outcome respects direction, range and difficulty gates")
		check(tank.charge_lock == null and not tank.is_charging(), "the near-miss warning precedes charging")


func _stage_one_release_at_100_m(evade: bool, mode := Game.Difficulty.HARD) -> Dictionary:
	Game.difficulty = mode
	var world := _rig()
	var flyer := _flyer(world, "helicopter")
	flyer.global_position.x = 0.0 # Fire down the open road, not through a roadside building.
	flyer._lane = 0.0
	flyer._last_position = flyer.global_position
	flyer.evasive = evade
	_tank_at_range(world, flyer, 100.0)
	var tank := world.player
	tank.model.barrel.basis = Basis() # Production aiming owns turret yaw and gun-pivot elevation.
	tank.input_enabled = true
	tank.using_gamepad = true
	tank._burst_gap = 100.0 # Isolate the reported cannon shot from automatic coax bursts.
	world.camera.global_position = tank.global_position + Vector3.UP * 8.0
	world.camera.look_at(flyer.hit_center(), Vector3.UP)
	var origin := flyer.global_position
	for i in 90:
		tank.aim_screen = world.camera.unproject_position(flyer.hit_center())
		tank._update_aim(1.0 / 60.0)
		flyer.tick(1.0 / 60.0)
		check(tank.charge_lock == null and not tank.is_charging(), "ordinary barrel tracking starts before a charge lock")
	var precharge := flyer.global_position - origin
	precharge.y = 0.0
	for i in 3:
		var actual := tank.model.muzzle.global_position.distance_to(flyer.hit_center())
		tank.global_position += Vector3.FORWARD * (100.0 - actual)
	Input.action_press("fire")
	for i in 18:
		tank._update_charge(1.0 / 60.0)
		tank.aim_screen = world.camera.unproject_position(flyer.hit_center())
		tank._update_aim(1.0 / 60.0)
		flyer.tick(1.0 / 60.0)
	check_eq(Armament.stage(tank.charge), 1, "the actual fire input charges only the first stage")
	# Movement and the 0.8 m altitude bob during charging can shift this range slightly.
	check_near(tank.model.muzzle.global_position.distance_to(flyer.hit_center()), 100.0, 0.5, "the real first-stage release occurs at the reported range")
	Input.action_release("fire")
	tank._update_charge(1.0 / 60.0)
	tank._update_weapons(1.0 / 60.0)
	var shell: Projectile = world.projectiles.back()
	shell.set_process(false)
	var hp := flyer.hp
	for i in 60:
		flyer.tick(1.0 / 60.0)
		if not shell.is_queued_for_deletion():
			shell.step(1.0 / 60.0)
	return {"precharge_motion": precharge.length(), "hit": flyer.hp < hp or flyer.dead}


func test_barrel_tracking_moves_the_helicopter_before_a_real_stage_one_charge_and_release_at_100_m() -> void:
	var control := _stage_one_release_at_100_m(false)
	var warned := _stage_one_release_at_100_m(true)
	check_eq(control.precharge_motion, 0.0, "the control has no lateral flight before charging")
	check(warned.precharge_motion > 0.1, "the helicopter is already moving evasively when the real first-stage charge starts")
	check(control.hit, "the real ground-tank muzzle, sight, lead, charge and release damage the vulnerable control")
	print("100 m stage-one release: control hit=%s, early-warning hit=%s" % [control.hit, warned.hit])


func _quick_shot(power: float, evade: bool, delay: float, options := {}) -> bool:
	Game.difficulty = options.get("difficulty", Game.Difficulty.HARD)
	var world := _rig()
	var flyer := _flyer(world, options.get("kind", "helicopter"))
	if not options.is_empty() and not flyer is Gunship:
		flyer.global_position.x = 0.0 # Keep the test shot clear of roadside buildings.
		if flyer is Helicopter or flyer is Tiltrotor:
			flyer._lane = 0.0
		flyer._last_position = flyer.global_position
	world.player.charge_lock = flyer
	flyer.evasive = evade
	var side := Vector3.BACK if flyer is Uav else Vector3.FORWARD
	world.player.global_position = flyer.global_position + side * float(options.get("distance", 360.0))
	world.player.global_position.y = 0.0
	# Sample releases throughout the weave; natural motion need not avoid every shot.
	for i in roundi(delay * 60.0):
		flyer.tick(1.0 / 60.0)
	# Fire from the actual ground tank muzzle, with the production barrel and lead correction.
	var muzzle := world.player.model.muzzle.global_position
	var target := world.player.lead_point(muzzle, Armament.quick_speed(power), flyer)
	world.player.model.barrel.look_at(target, Vector3.UP)
	world.player.fire_cannon(Vector3.INF, Vector3.ZERO, power)
	var shell: Projectile = world.projectiles.back()
	shell.set_process(false)
	var hp := flyer.hp
	for i in 90:
		flyer.tick(1.0 / 60.0)
		if not shell.is_queued_for_deletion():
			shell.step(1.0 / 60.0)
	check_eq(world.player.charge_lock, flyer, "flight does not cancel the lock to manufacture a miss")
	return flyer.hp < hp or flyer.dead


func test_normal_barrel_warning_moves_before_charging_but_cannot_avoid_the_real_100_m_first_stage_release() -> void:
	var warned := _stage_one_release_at_100_m(true, Game.Difficulty.NORMAL)
	check(warned.precharge_motion > 0.05, "Normal begins a nonzero evasive movement before the player charges")
	check(warned.hit, "the real sight, barrel, lead and first-stage release still damage the vulnerable Normal helicopter")


func test_sluggish_normal_evasion_still_takes_real_first_stage_shells_on_all_four_aircraft() -> void:
	for kind in ["helicopter", "tiltrotor", "uav", "gunship"]:
		for distance in [100.0, 360.0]:
			# The gunship starts at its orbit goal, then settles after the ground tank is placed.
			var phases := [5.5, 7.5, 9.5] if kind == "gunship" else [1.5, 3.5, 5.5]
			for delay in phases:
				var options := {"difficulty": Game.Difficulty.NORMAL, "kind": kind, "distance": distance}
				check(_quick_shot(Armament.STAGE_1, false, delay, options), "%s control accepts the real first-stage shell from an initial %.0f m separation / %.1f s" % [kind, distance, delay])
				check(_quick_shot(Armament.STAGE_1, true, delay, options), "%s sluggish Normal evasion cannot avoid the first-stage shell from an initial %.0f m separation / %.1f s" % [kind, distance, delay])


func test_continuous_flight_can_avoid_real_led_stage_one_and_two_shells_that_hit_without_evasion() -> void:
	for power in [Armament.STAGE_1, Armament.STAGE_2]:
		var avoided := 0
		for delay in [0.5, 1.5, 2.5, 3.5, 4.5, 5.5]:
			check(_quick_shot(power, false, delay), "the control accepts the real charged cannon shell at %.1f s" % delay)
			if not _quick_shot(power, true, delay):
				avoided += 1
		check(avoided > 0, "changing course defeats production lead and avoids real stage %d shells without invulnerability" % Armament.stage(power))
