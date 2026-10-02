extends TestCase
## Main-gun input, one held lock, and charged rounds at their real impact paths.


func _rig() -> World:
	var world := stage()
	world.set_process(false)
	world.director.set_process(false)
	world.player.set_process(false)
	world.player.input_enabled = true
	world.camera.set_process(false)
	world.camera.follow(0.0)
	Input.action_release("fire_cannon")
	Input.action_release("fire_coax")
	return world


func _step(tank: Tank, delta: float) -> void:
	tank._update_charge(delta)
	tank._update_weapons(delta)


func test_clicks_and_early_releases_fire_nothing_and_reset() -> void:
	var world := _rig()
	var tank := world.player
	for _i in 10:
		Input.action_press("fire_cannon")
		_step(tank, 1.0 / 60.0)
		Input.action_release("fire_cannon")
		_step(tank, 1.0 / 60.0)
	check_eq(world.stats.shots, 0, "a few clicks fire nothing")
	_step(tank, 1.0)
	check_eq(tank.charge, 0.0, "and what they built drains away")
	Input.action_press("fire_cannon")
	_step(tank, Armament.CHARGE_DELAY - 0.01)
	check_eq(tank.charge, 0.0, "no charge before the delay")
	_step(tank, 0.01 + Armament.CHARGE_TIME * 0.5)
	check_near(tank.charge, 0.5, 0.001, "then it charges over CHARGE_TIME")
	_step(tank, Armament.CHARGE_TIME * 0.49)
	check(tank.charge < 1.0, "just short of full")
	Input.action_release("fire_cannon")
	_step(tank, 0.0)
	check_eq(world.stats.shots, 0, "releasing before full fires nothing")
	var kept := tank.charge
	_step(tank, Armament.CHARGE_TIME * 0.1)
	check_near(tank.charge, kept - 0.1 * Armament.CHARGE_DRAIN, 0.001, "the charge drains back instead of vanishing")
	Input.action_press("fire_cannon")
	_step(tank, 0.01)
	check(tank.charge > kept - 0.1 * Armament.CHARGE_DRAIN, "and a quick re-press resumes from what is left")
	Input.action_release("fire_cannon")
	_step(tank, 0.0)
	_step(tank, (Armament.CHARGE_DELAY + Armament.CHARGE_TIME) / Armament.CHARGE_DRAIN + 0.01)
	check_eq(tank.charge, 0.0, "left alone, it drains to nothing")
	check_eq(world.stats.shots, 0, "and never fires")


func test_full_charge_holds_and_release_fires_exactly_one_shell() -> void:
	var world := _rig()
	var tank := world.player
	Input.action_press("fire_cannon")
	_step(tank, Armament.CHARGE_DELAY + Armament.CHARGE_TIME)
	check_eq(tank.charge, 1.0, "full at delay plus charge time")
	_step(tank, 5.0)
	check_eq(tank.charge, 1.0, "a full charge holds indefinitely")
	check_eq(world.stats.shots, 0, "holding fires nothing")
	Input.action_release("fire_cannon")
	_step(tank, 0.0)
	check_eq(world.stats.shots, 1, "release fires one shell")
	check_eq(world.stats.charged_shots, 1, "a charged one")
	check_eq(tank.charge, 0.0, "release clears the charge")
	_step(tank, 0.0)
	check_eq(world.stats.shots, 1, "and only the one")


func test_continuous_charge_and_release_cycles_are_a_full_charge_apart() -> void:
	var world := _rig()
	var tank := world.player
	var delta := 1.0 / 60.0
	var shot_times: Array[float] = []
	var t := 0.0
	for _i in 600:
		# The bot: hold, and let go the frame the charge is full.
		if tank.charge >= 1.0:
			Input.action_release("fire_cannon")
		else:
			Input.action_press("fire_cannon")
		var before := world.stats.shots
		_step(tank, delta)
		t += delta
		if world.stats.shots > before:
			shot_times.append(t)
	Input.action_release("fire_cannon")
	check(shot_times.size() >= 8, "it keeps firing (%d shots in 10 s)" % shot_times.size())
	for k in range(1, shot_times.size()):
		check(shot_times[k] - shot_times[k - 1] >= Armament.CHARGE_DELAY + Armament.CHARGE_TIME - 0.0001, "shots %d and %d are at least a full charge apart (%.3f s)" % [k - 1, k, shot_times[k] - shot_times[k - 1]])


func test_charging_does_not_slow_the_tank() -> void:
	var world := _rig()
	var tank := world.player
	Input.action_press("move_right")
	Input.action_press("fire_cannon")
	_step(tank, Armament.CHARGE_DELAY + 0.01)
	check(tank.is_charging(), "charging")
	tank._update_movement(0.2)
	check_near(tank.local_velocity.x, Tank.MOVE_SPEED.x, 0.01, "rail lateral speed is untouched")
	tank.dash(Vector2.RIGHT)
	check(tank._drift > 0.0, "dash works while charging")
	tank._drift = 0.0
	world.rail.mode = Rail.Mode.ARENA
	tank._move_arena(0.2, Vector2.RIGHT)
	check_near(tank.local_velocity.length(), Tank.ARENA_SPEED, 0.01, "arena speed is untouched")
	Input.action_release("fire_cannon")
	Input.action_release("move_right")


func test_breech_damage_slows_the_charge() -> void:
	var world := _rig()
	var tank := world.player
	check_near(tank.charge_time(), Armament.CHARGE_TIME, 0.0001, "whole breech")
	tank.modules.hp.breech = TankModules.MAX.breech * 0.4
	check_near(tank.charge_time(), Armament.CHARGE_TIME * 1.5, 0.0001, "damaged breech charges x1.5 slower")
	tank.modules.damage("breech", 999.0)
	check_near(tank.charge_time(), Armament.CHARGE_TIME * 3.0, 0.0001, "destroyed breech: x3")
	Input.action_press("fire_cannon")
	_step(tank, Armament.CHARGE_DELAY + Armament.CHARGE_TIME * 2.0)
	check(tank.charge < 1.0, "twice the usual charge time is not enough")
	_step(tank, Armament.CHARGE_TIME + 0.001)
	check_eq(tank.charge, 1.0, "three times it is")
	Input.action_release("fire_cannon")


func test_special_rounds_spend_one_round_per_charged_shot() -> void:
	var world := _rig()
	var tank := world.player
	tank.load_round(Armament.Round.CANISTER)
	check_eq(tank.round_count, Armament.MAGAZINE[Armament.Round.CANISTER], "full magazine")
	Input.action_press("fire_cannon")
	_step(tank, Armament.CHARGE_DELAY + Armament.CHARGE_TIME)
	check_eq(tank.round_count, Armament.MAGAZINE[Armament.Round.CANISTER], "charging spends none")
	Input.action_release("fire_cannon")
	_step(tank, 0.0)
	check_eq(tank.round_count, Armament.MAGAZINE[Armament.Round.CANISTER] - 1, "the charged shot spends one")


func _target(world: World, at: Vector3) -> Enemy:
	var enemy := Enemy.new()
	enemy.position = at
	world.add_enemy(enemy)
	enemy.set_process(false)
	return enemy


func test_single_lock_holds_drops_and_reacquires() -> void:
	var world := _rig()
	var tank := world.player
	var at := tank.hit_center() - Vector3(0, 0, 40)
	var first := _target(world, at)
	var second := _target(world, at + Vector3.RIGHT * 2.0)
	tank.aim_screen = world.camera.unproject_position(first.hit_center())
	Input.action_press("fire_cannon")
	_step(tank, Armament.CHARGE_DELAY + Armament.CHARGE_TIME - 0.01)
	tank._update_charge_lock()
	check(tank.charge_lock == null, "no lock before full charge")
	check(tank.charge_candidate == first, "but the brackets already show what it will lock")
	var locks: Array[Entity] = []
	tank.charge_locked.connect(func(target: Entity) -> void: locks.append(target))
	_step(tank, 0.02)
	tank._update_charge_lock()
	check(tank.charge_lock == first, "only nearest entity locks")
	check_eq(locks.size(), 1, "one acquisition signal")
	tank.aim_screen = world.camera.unproject_position(second.hit_center())
	tank._update_charge_lock()
	check(tank.charge_lock == first, "held lock is not replaced by another candidate")
	first.global_position += Vector3.RIGHT * 50.0
	tank._update_charge_lock()
	check(tank.charge_lock == second, "outside hold radius drops and reacquires nearest")
	second.global_position = world.camera.global_position + world.camera.global_basis.z * 20.0
	tank._update_charge_lock()
	check(tank.charge_lock == null, "behind-camera target drops")
	first.global_position = at
	tank.aim_screen = world.camera.unproject_position(first.hit_center())
	tank._update_charge_lock()
	first.dead = true
	tank._update_charge_lock()
	check(tank.charge_lock == null, "dead target drops")
	Input.action_release("fire_cannon")


func test_freed_lock_drops_and_reacquires() -> void:
	var world := _rig()
	var tank := world.player
	var at := tank.hit_center() - Vector3(0, 0, 40)
	var first := _target(world, at)
	var second := _target(world, at + Vector3.RIGHT)
	tank.aim_screen = world.camera.unproject_position(first.hit_center())
	Input.action_press("fire_cannon")
	_step(tank, Armament.CHARGE_DELAY + Armament.CHARGE_TIME)
	tank._update_charge_lock()
	check(tank.charge_lock == first, "first locks")
	first.free()
	tank._update_charge_lock()
	check(is_instance_valid(tank.charge_lock) and tank.charge_lock == second, "freed lock drops and nearest valid target reacquires")
	Input.action_release("fire_cannon")


func test_fcs_and_cancellation() -> void:
	var world := _rig()
	var tank := world.player
	var enemy := _target(world, tank.hit_center() - Vector3(0, 0, 40))
	tank.aim_screen = world.camera.unproject_position(enemy.hit_center())
	tank.modules.hp.fcs = 0.0
	Input.action_press("fire_cannon")
	_step(tank, Armament.CHARGE_DELAY + Armament.CHARGE_TIME)
	tank._update_charge_lock()
	check_eq(tank.charge, 1.0, "FCS loss does not prevent charging")
	check(tank.charge_lock == null, "knocked-off FCS cannot lock")
	tank.input_enabled = false
	check_eq(tank.charge, 0.0, "input disable cancels immediately")
	tank.input_enabled = true
	_step(tank, Armament.CHARGE_DELAY + Armament.CHARGE_TIME)
	tank.die(Hit.new())
	check_eq(tank.charge, 0.0, "losing a life cancels")
	tank._finish_respawn()
	check_eq(tank.charge, 0.0, "respawn starts uncharged")
	Input.action_release("fire_cannon")


func test_full_canister_balls_land_inside_ring_at_40_m() -> void:
	var world := _rig()
	var tank := world.player
	tank.global_position += Vector3.UP * 40.0 # Clear of the ground, so the whole cone reaches 40 m.
	var muzzle := tank.global_position + Vector3(0, 30, 0)
	var forward := Vector3.FORWARD
	var center := muzzle + forward * 40.0
	world.camera.global_position = muzzle + Vector3.BACK * 20.0
	world.camera.look_at(center)
	var catcher := _target(world, center)
	catcher.radius = 6.0
	catcher.max_hp = 1000000.0
	catcher.hp = catcher.max_hp
	catcher.invulnerable = false
	tank.aim_point = center
	tank.aim_screen = world.camera.unproject_position(center)
	tank.current_round = Armament.Round.CANISTER
	tank.charge = 1.0
	# Use the actual muzzle for the footprint calculation, and the same plane for impacts.
	muzzle = tank.model.muzzle.global_position
	center = muzzle + forward * 40.0
	catcher.global_position = center
	world.camera.global_position = muzzle + Vector3.BACK * 20.0
	world.camera.look_at(center)
	tank.aim_point = center
	tank.aim_screen = world.camera.unproject_position(center)
	var ring := tank.charge_ring_radius()
	var hits: Array[Vector3] = []
	catcher.damaged.connect(func(_enemy: Entity, hit: Hit) -> void: hits.append(hit.position))
	seed(1)
	tank._fire_canister(muzzle, forward)
	var inside := 0
	for hit in hits:
		if world.camera.unproject_position(hit).distance_to(tank.aim_screen) <= ring:
			inside += 1
	check_eq(hits.size(), 50, "all fifty balls reach the target at 40 m")
	check(inside >= 48, "at least 95 percent land inside displayed footprint (%d/50)" % inside)


func test_aphe_base_kill_and_full_overpenetration() -> void:
	var world := _rig()
	var muzzle := world.player.global_position + Vector3(40, 15, 0)
	var victims: Array[Ugv] = []
	for distance in [30.0, 65.0]:
		var ugv := Ugv.new()
		ugv.position = muzzle + Vector3.FORWARD * distance - Vector3.UP * 0.9
		world.add_enemy(ugv)
		ugv.set_process(false)
		victims.append(ugv)
	world.player.fire_cannon(muzzle, (victims[0].hit_center() - muzzle).normalized(), 0.0)
	check(victims[0].dead, "base APHE still kills a UGV outright")
	check(not victims[1].dead, "base APHE stops at first UGV")
	await frames(1)
	var replacement := Ugv.new()
	replacement.position = muzzle + Vector3.FORWARD * 30.0 - Vector3.UP * 0.9
	world.add_enemy(replacement)
	replacement.set_process(false)
	world.player.fire_cannon(muzzle, (replacement.hit_center() - muzzle).normalized(), 1.0)
	check(replacement.dead and victims[1].dead, "full APHE kills both UGVs in line")


## Three UGVs in a row across the road, `near` and `far` meters from the one under the shell.
func _pack(world: World, near: float, far: float) -> Array[Ugv]:
	var d := world.rail.d + 60.0
	var ugvs: Array[Ugv] = []
	for u in [0.0, near, far]:
		var ugv := Ugv.new()
		ugv.position = Course.ground_at(d, u)
		ugv.immobile = true
		world.add_enemy(ugv)
		ugv.set_process(false)
		ugvs.append(ugv)
	return ugvs


func test_charged_blast_takes_a_pack_within_6_m_of_the_hit() -> void:
	var world := _rig()
	var tank := world.player
	var pack := _pack(world, 3.0, 6.0)
	var wide := _pack(world, 3.0, 14.0)[2]
	await frames(1)
	tank.fire_cannon(pack[0].hit_center() + Vector3.UP * 20.0, Vector3.DOWN, 1.0)
	check_eq(pack.map(func(ugv: Ugv) -> bool: return ugv.dead), [true, true, true], "a charged shell takes the whole pack")
	check(not wide.dead, "but not one 14 m away")


func test_charged_shot_hits_a_target_crossing_at_15_m_per_s() -> void:
	var world := _rig()
	var tank := world.player
	var enemy := _target(world, tank.hit_center() - Vector3(7.0, 0, 60.0))
	enemy.radius = 0.5
	enemy.max_hp = 100000.0
	enemy.hp = enemy.max_hp
	var delta := 1.0 / 60.0
	var steer := func() -> void:
		enemy.global_position.x += 15.0 * delta
		enemy.track_velocity = Vector3(15.0, 0, 0)
		tank.aim_screen = world.camera.unproject_position(enemy.hit_center())
		tank._update_aim(delta)
		_step(tank, delta)
	Input.action_press("fire_cannon")
	while tank.charge < 1.0:
		steer.call()
	steer.call()
	check(tank.charge_lock == enemy, "full charge locks the crosser")
	for _i in 12:
		steer.call()
	var before := enemy.hp
	Input.action_release("fire_cannon")
	enemy.global_position.x += 15.0 * delta
	tank._update_aim(delta)
	_step(tank, delta)
	check(before - enemy.hp >= Armament.SHELL_DAMAGE, "the charged shell hits it (%.0f damage)" % (before - enemy.hp))
	check(world.projectiles.all(func(p: Projectile) -> bool: return p.homing_target == null), "nothing homes")
