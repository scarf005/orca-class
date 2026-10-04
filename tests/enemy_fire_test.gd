extends TestCase
## Enemy rounds leave along the barrel that visibly points at the tank, the barrels slew onto it during
## the telegraph, and the gunship cannon barrel stays put once its aim locks.

const BORE_TOLERANCE := 5.0 ## Degrees between a round and its barrel: correction and scatter only.
const MISSILE_TOLERANCE := 9.0 ## Guided rounds may already have started to steer.


func _spawn(world: World, enemy: Enemy, ahead := 45.0, lane := 3.0) -> Enemy:
	enemy.position = Course.ground_at(world.rail.d + world.player.course_offset + ahead, lane)
	world.add_enemy(enemy)
	return enemy


## Degrees between the first round `enemy` fires and the bore of the closest of `muzzles` (-1: no round).
func _first_shot(world: World, enemy: Enemy, muzzles: Array, frames_limit := 300, before := Callable()) -> float:
	var seen := world.projectiles.duplicate()
	for _i in frames_limit:
		await get_tree().process_frame
		if before.is_valid():
			before.call()
		for p in world.projectiles:
			if p in seen or p.team != Entity.Team.ENEMY or p.hit.source != enemy:
				continue
			var nearest: Node3D = muzzles[0]
			for m: Node3D in muzzles:
				if m.global_position.distance_to(p.global_position) < nearest.global_position.distance_to(p.global_position):
					nearest = m
			return rad_to_deg(p.velocity.angle_to(-nearest.global_basis.z))
	return -1.0


func _bore_to_tank(enemy: Enemy, muzzle: Node3D, tank: Tank) -> float:
	return rad_to_deg((-muzzle.global_basis.z).angle_to(tank.hit_center() - muzzle.global_position))


func test_slew_is_limited_and_arrives() -> void:
	var world := stage("", false)
	var enemy := Enemy.new()
	world.add_enemy(enemy)
	var pivot := Node3D.new()
	enemy.add_child(pivot)
	var target := Vector3(10, 4, -3)
	var last := -pivot.global_basis.z
	var arrived := false
	for _i in 60:
		var left := enemy.slew_barrel(pivot, target, 2.0, 0.05)
		var now := -pivot.global_basis.z
		check(rad_to_deg(last.angle_to(now)) <= rad_to_deg(2.0 * 0.05) + 0.01, "a barrel turns no faster than its slew rate")
		last = now
		if left <= 0.0:
			arrived = true
			break
	check(arrived, "and gets onto the target")
	check(rad_to_deg((-pivot.global_basis.z).angle_to(target)) < 0.1, "pointing at it")


func test_fire_along_leaves_the_bore_with_a_capped_correction() -> void:
	var world := stage("", false)
	var enemy := Enemy.new()
	world.add_enemy(enemy)
	var muzzle := Node3D.new()
	enemy.add_child(muzzle)
	muzzle.global_position = Vector3(0, 5, 0)
	var shot := enemy.fire_along("orb", muzzle, 100.0, 1.0)
	check(rad_to_deg(shot.velocity.angle_to(Vector3.FORWARD)) < 0.01, "with nothing else asked, a round goes exactly down the bore")
	shot = enemy.fire_along("orb", muzzle, 100.0, 1.0, Palette.HOT, Vector3.RIGHT, 3.0)
	check_near(rad_to_deg(shot.velocity.angle_to(Vector3.FORWARD)), 3.0, 0.05, "a wanted direction far off the bore corrects only by the cap")
	shot = enemy.fire_along("orb", muzzle, 100.0, 1.0, Palette.HOT, Vector3(0.02, 0, -1), 3.0)
	check_near(rad_to_deg(shot.velocity.angle_to(Vector3(0.02, 0, -1))), 0.0, 0.05, "a wanted direction inside the cap is followed")
	shot = enemy.fire_along("orb", muzzle, 100.0, 1.0, Palette.HOT, Vector3.ZERO, 3.0, 0.05)
	check(rad_to_deg(shot.velocity.angle_to(Vector3.FORWARD)) < 6.0, "scatter stays small")


func test_ugv_gun_and_launcher_fire_along_the_barrel() -> void:
	for weapon in ["gun", "atgm"]:
		var world := stage("", false)
		var ugv := Ugv.new()
		ugv.weapon = weapon
		_spawn(world, ugv)
		ugv._attack_timer = 0.0
		var angle := await _first_shot(world, ugv, [ugv._muzzle])
		check(angle >= 0.0, "the %s UGV fires" % weapon)
		check(angle <= (BORE_TOLERANCE if weapon == "gun" else MISSILE_TOLERANCE), "the %s UGV round leaves along its barrel (%.1f deg)" % [weapon, angle])
		cleanup()


func test_ugv_barrel_turns_onto_the_tank_during_the_telegraph() -> void:
	var world := stage("", false)
	var tank := world.player
	tank.set_process(false) # Hold the target still; this test measures turret slew, not rail movement.
	var ugv := Ugv.new()
	_spawn(world, ugv, 40.0, 8.0)
	ugv.immobile = true # Hold the platform still; only the barrel should move.
	ugv._attack_timer = INF
	await frames(90) # The turret ring swings round first.
	# Point the gun well away from the tank, then let the AI start a telegraph.
	ugv._barrel.global_basis = Basis.looking_at((tank.hit_center() - ugv._muzzle.global_position).rotated(Vector3.UP, deg_to_rad(50.0)))
	var start := _bore_to_tank(ugv, ugv._muzzle, tank)
	check(start > 30.0, "setup: the gun starts pointing away (%.0f deg)" % start)
	ugv._attack_timer = 0.0
	var early := 0.0
	for i in 40:
		await get_tree().process_frame
		if i == 5:
			early = _bore_to_tank(ugv, ugv._muzzle, tank)
	check(early < start, "it is already turning early in the telegraph")
	check(early > 3.0, "at a limited rate, not instantly")
	check(_bore_to_tank(ugv, ugv._muzzle, tank) < 5.0, "and it is on the tank by the end of it")


func test_walker_arm_gun_and_pod_fire_along_their_barrels() -> void:
	for weapon in ["gun", "missile"]:
		var world := stage("", false)
		var walker := Walker.new()
		walker.weapon = weapon
		_spawn(world, walker)
		walker._attack_timer = 0.0
		var muzzle: Node3D = walker._muzzle if weapon == "gun" else walker._pod_muzzle
		var angle := await _first_shot(world, walker, [muzzle])
		check(angle >= 0.0, "the %s walker fires" % weapon)
		check(angle <= (BORE_TOLERANCE if weapon == "gun" else MISSILE_TOLERANCE), "the %s walker's round leaves along its barrel (%.1f deg)" % [weapon, angle])
		cleanup()


func test_quad_flak_and_mortar_fire_along_their_barrels() -> void:
	for weapon in ["flak", "mortar"]:
		var world := stage("", false)
		var quad := QuadMech.new()
		quad.weapon = weapon
		_spawn(world, quad)
		quad._attack_timer = 0.0
		var angle := await _first_shot(world, quad, [quad._muzzle])
		check(angle >= 0.0, "the %s quad fires" % weapon)
		check(angle <= (BORE_TOLERANCE if weapon == "flak" else QuadMech.MORTAR_CORRECTION + 0.5), "the %s quad's round leaves along its barrel (%.1f deg)" % [weapon, angle])
		cleanup()


func test_quad_mortar_tube_points_up_along_the_arc() -> void:
	var world := stage("", false)
	var quad := QuadMech.new()
	quad.weapon = "mortar"
	_spawn(world, quad)
	quad._attack_timer = 0.0
	await frames(60)
	check((-quad._muzzle.global_basis.z).y > 0.5, "the mortar tube is raised along its launch arc")


func test_helicopter_chin_gun_and_rockets_fire_along_their_barrels() -> void:
	for rockets in [false, true]:
		var world := stage("", false)
		var heli := Helicopter.new()
		heli.set_meta("slot", Vector3(0, 13, 45))
		heli._rockets = rockets
		_spawn(world, heli)
		heli._attack_timer = 0.0
		var muzzles: Array = heli._pod_muzzles if rockets else [heli._chin_muzzle]
		var angle := await _first_shot(world, heli, muzzles)
		check(angle >= 0.0, "the helicopter fires (rockets %s)" % rockets)
		check(angle <= (MISSILE_TOLERANCE if rockets else BORE_TOLERANCE), "its round leaves along the barrel (rockets %s, %.1f deg)" % [rockets, angle])
		cleanup()


func test_strafing_uav_fires_along_its_gun() -> void:
	var world := stage("", false)
	var uav := Uav.new()
	uav.attack = "strafe"
	_spawn(world, uav, 80.0, 0.0)
	uav._bombs = 0
	var tank := world.player
	var run := func() -> void: uav._strafe_run(get_process_delta_time(), tank, 60.0)
	var angle := await _first_shot(world, uav, [uav._muzzle], 300, run)
	check(angle >= 0.0, "the strafing UAV fires")
	check(angle <= BORE_TOLERANCE, "along its gun (%.1f deg)" % angle)


func _gunship(world: World) -> Gunship:
	world.director._start_boss({"kind": "gunship"})
	var boss := world.boss as Gunship
	boss._next_attack = 1000.0
	return boss


func test_gunship_weapons_fire_along_their_barrels() -> void:
	var cases := {
		Gunship.Attack.GUN: [BORE_TOLERANCE, "gatlings"],
		Gunship.Attack.CANNON: [1.0, "nose cannon"],
		Gunship.Attack.ROCKETS: [BORE_TOLERANCE + 2.0, "rocket racks"],
		Gunship.Attack.ATGM: [MISSILE_TOLERANCE, "chin drum"],
	}
	for attack: Gunship.Attack in cases:
		var world := stage("boss")
		var boss := _gunship(world)
		var muzzles: Array = []
		match attack:
			Gunship.Attack.GUN:
				muzzles = boss._gatling_muzzles
			Gunship.Attack.CANNON:
				muzzles = [boss._nose_muzzle]
			Gunship.Attack.ROCKETS:
				muzzles = boss._rack_muzzles.values()
			Gunship.Attack.ATGM:
				muzzles = boss._chin_muzzles
		boss._attack = attack
		boss._attack_time = 0.0
		var angle := await _first_shot(world, boss, muzzles, 400)
		var expected: Array = cases[attack]
		check(angle >= 0.0, "the gunship's %s fire" % expected[1])
		check(angle <= expected[0], "the gunship's %s round leaves along its barrel (%.1f deg)" % [expected[1], angle])
		cleanup()


func test_gunship_gatling_barrels_turn_toward_the_tank() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var tank := world.player
	await frames(90) # The airframe swings its nose round first.
	for gatling: Node3D in boss._gatlings:
		gatling.global_basis = Basis.looking_at(Vector3.UP + Vector3.RIGHT)
	var before := _bore_to_tank(boss, boss._gatling_muzzles[0], tank)
	await frames(6)
	var soon := _bore_to_tank(boss, boss._gatling_muzzles[0], tank)
	check(soon < before, "the gatling turns toward the tank")
	check(soon > 1.0, "at a limited rate")
	await frames(60)
	check(_bore_to_tank(boss, boss._gatling_muzzles[0], tank) < 8.0, "and settles on it")


func test_gunship_cannon_barrel_turns_then_holds_still_through_the_lock() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	boss._attack = Gunship.Attack.CANNON
	boss._attack_time = 0.0
	var held: Array[Vector3] = []
	for _i in 200:
		await get_tree().process_frame
		if boss._cannon_hold != Vector3.ZERO:
			held.append(-boss._nose_muzzle.global_basis.z)
		elif not held.is_empty():
			break
	check(held.size() >= int(Gunship.CANNON_LOCK * 60.0 * 0.7), "the lock lasted (%d frames)" % held.size())
	var drift := 0.0
	for i in range(1, held.size()):
		drift = maxf(drift, rad_to_deg(held[0].angle_to(held[i])))
	check(drift < 0.5, "the cannon barrel does not move during the lock (%.2f deg)" % drift)


func test_gunship_gatlings_fire_visibly_from_both_barrels() -> void:
	seed(104)
	var world := stage("boss")
	var boss := _gunship(world)
	var chosen := {}
	for phase in [Gunship.Phase.HUNTER, Gunship.Phase.STRIPPED, Gunship.Phase.INFECTED]:
		boss.phase = phase
		chosen[phase] = 0
		for _i in 300:
			boss._choose_attack()
			chosen[phase] += int(boss._attack == Gunship.Attack.GUN)
			boss._end_attack()
		check(chosen[phase] > 20, "gun runs come up in phase %d (%d of 300)" % [phase, chosen[phase]])
	boss.phase = Gunship.Phase.HUNTER
	boss._attack = Gunship.Attack.GUN
	boss._attack_time = 0.0
	var seen := world.projectiles.duplicate()
	var from_side := [0, 0]
	var streaks := 0
	var spin := 0.0
	for _i in 200:
		var transients := world.fx._transients.size()
		await get_tree().process_frame
		spin = maxf(spin, boss._spin)
		for p in world.projectiles:
			if p in seen or p.team != Entity.Team.ENEMY:
				continue
			seen.append(p)
			from_side[0 if p.global_position.distance_to(boss._gatling_muzzles[0].global_position) < p.global_position.distance_to(boss._gatling_muzzles[1].global_position) else 1] += 1
			streaks += int(world.fx._transients.size() > transients)
	check(from_side[0] >= 5 and from_side[1] >= 5, "both gatlings spit rounds (%s)" % str(from_side))
	check(streaks >= 10, "each burst draws tracer streaks (%d)" % streaks)
	check(spin > 30.0, "the barrels wind up")
