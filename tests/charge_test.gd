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
	var loaded := delta if tank.reload <= 0.0 else maxf(delta - tank.reload, 0.0)
	tank.reload = maxf(tank.reload - delta, 0.0)
	tank._update_charge(loaded)
	tank._update_weapons(delta)


func test_hold_release_and_tap() -> void:
	var world := _rig()
	var tank := world.player
	Input.action_press("fire_cannon")
	_step(tank, Armament.CHARGE_DELAY + Armament.CHARGE_TIME)
	check_eq(world.stats.shots, 0, "holding never fires")
	check_eq(tank.charge, 1.0, "loaded gun reaches full at delay plus charge time")
	_step(tank, 5.0)
	check_eq(tank.charge, 1.0, "full charge holds indefinitely")
	check_eq(world.stats.shots, 0, "long hold still never fires")
	Input.action_release("fire_cannon")
	_step(tank, 0.0)
	check_eq(world.stats.shots, 1, "release fires once")
	check_eq(world.stats.charged_shots, 1, "full shot is counted")
	check_eq(tank.charge, 0.0, "release clears charge")
	Input.action_press("fire_cannon")
	_step(tank, 0.01)
	Input.action_release("fire_cannon")
	_step(tank, 0.01)
	check_eq(world.stats.shots, 1, "tap during reload does nothing")
	tank.reload = 0.0
	Input.action_press("fire_cannon")
	_step(tank, Armament.CHARGE_DELAY - 0.01)
	check_eq(tank.charge, 0.0, "tap before delay has zero power")
	Input.action_release("fire_cannon")
	_step(tank, 0.0)
	check_eq(world.stats.shots, 2, "loaded tap fires")
	check_eq(world.stats.charged_shots, 1, "tap is uncharged")


func test_held_during_reload_starts_only_when_loaded() -> void:
	var world := _rig()
	var tank := world.player
	tank.reload = 0.5
	Input.action_press("fire_cannon")
	_step(tank, 0.4)
	check_eq(tank.charge, 0.0, "reload time contributes no charge")
	_step(tank, 0.2)
	check_near(tank._charge_time, 0.1, 0.0001, "only the loaded portion of the frame counts")
	_step(tank, Armament.CHARGE_DELAY + Armament.CHARGE_TIME - 0.1 + 0.00001)
	check_eq(tank.charge, 1.0, "holding begins charging once loaded")
	Input.action_release("fire_cannon")


func test_lateral_speed_and_dash() -> void:
	var world := _rig()
	var tank := world.player
	Input.action_press("move_right")
	Input.action_press("fire_cannon")
	_step(tank, Armament.CHARGE_DELAY + 0.01)
	tank._update_movement(0.2)
	check_near(tank.local_velocity.x, Tank.MOVE_SPEED.x * 0.5, 0.01, "rail lateral speed halves")
	tank.dash(Vector2.RIGHT)
	check(tank._drift > 0.0, "dash works while charging")
	tank._drift = 0.0
	Input.action_release("fire_cannon")
	_step(tank, 0.0)
	tank._update_movement(0.2)
	check_near(tank.local_velocity.x, Tank.MOVE_SPEED.x, 0.01, "release restores lateral speed")
	tank.reload = 0.0
	world.rail.mode = Rail.Mode.ARENA
	Input.action_press("fire_cannon")
	_step(tank, Armament.CHARGE_DELAY + 0.01)
	tank._move_arena(0.2, Vector2.RIGHT)
	check_near(tank.local_velocity.length(), Tank.ARENA_SPEED * 0.5, 0.01, "arena speed halves")
	Input.action_release("fire_cannon")
	_step(tank, 0.0)
	tank._move_arena(0.2, Vector2.RIGHT)
	check_near(tank.local_velocity.length(), Tank.ARENA_SPEED, 0.01, "arena speed restores")
	Input.action_release("move_right")


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
	var muzzle := tank.global_position + Vector3(0, 30, 0)
	var forward := Vector3.FORWARD
	var center := muzzle + forward * 40.0
	world.camera.global_position = muzzle + Vector3.BACK * 20.0
	world.camera.look_at(center)
	var catcher := _target(world, center)
	catcher.radius = 3.0
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
	tank._fire_canister(muzzle, forward, 1.0)
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
