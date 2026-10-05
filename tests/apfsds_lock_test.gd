extends TestCase


func _rig() -> World:
	var world := stage()
	world.set_process(false)
	world.director.set_process(false)
	world.player.set_process(false)
	Course.flat = true
	return world


func _ugv(world: World, center: Vector3) -> Ugv:
	var enemy := Ugv.new()
	enemy.position = center - Vector3.UP
	world.add_enemy(enemy)
	enemy.set_process(false)
	return enemy


func _lock(world: World, muzzle: Vector3) -> void:
	var tank := world.player
	world.camera.global_position = muzzle
	world.camera.look_at(muzzle + Vector3.FORWARD, Vector3.UP)
	tank.using_gamepad = true
	tank.aim_screen = world.camera.unproject_position(muzzle + Vector3.FORWARD * 60.0)
	tank.current_round = Armament.Round.APFSDS
	tank.round_count = 6
	tank.input_enabled = true
	tank._fire_held = true
	tank._hold = Armament.TAP_TIME + 0.5
	tank._update_aim(0.0)


func test_grazing_charge_locks_kill_real_ugvs_and_keep_line_penetration_at_every_stage() -> void:
	for power in [Armament.STAGE_1, Armament.STAGE_2, 1.0]:
		for side in [-1.0, 1.0]:
			var world := _rig()
			var center := Vector3(40, 30, -60)
			# 2.1 m is outside the UGV's 1.8 m sphere, inside its 2.4 m sight sphere.
			var muzzle: Vector3 = Vector3(40, 30, 0) + Vector3.RIGHT * side * 2.1
			var enemy := _ugv(world, center)
			_lock(world, muzzle)
			check_eq(world.player.aim_target, enemy, "the production sight selects the grazing UGV")
			check_eq(world.player.charge_lock, enemy, "holding fire acquires the production charge lock")
			check_eq(enemy.hit_test(muzzle, muzzle + Vector3.FORWARD * 100.0), -1.0, "the uncorrected sight ray misses the real hit shape")
			var front := _ugv(world, muzzle.lerp(center, 0.5))
			var behind := _ugv(world, muzzle.lerp(center, 1.5))
			var neighbor := _ugv(world, center + Vector3.RIGHT * 6.0)
			world.player.fire_cannon(muzzle, Vector3.FORWARD, power)
			for victim in [front, enemy, behind]:
				check(victim.dead, "the locked dart kills every real armored UGV along the corrected line")
			check_eq(neighbor.hp, neighbor.max_hp, "lock correction adds neither splash nor a wider hit shape")


func test_valid_off_center_charge_lock_keeps_its_original_ray() -> void:
	var world := _rig()
	var muzzle := Vector3(41, 30, 0)
	var enemy := _ugv(world, Vector3(40, 30, -60))
	_lock(world, muzzle)
	check_eq(world.player.charge_lock, enemy, "the off-center sight acquires the UGV")
	var behind := _ugv(world, Vector3(41, 30, -200))
	world.player.fire_cannon(muzzle, Vector3.FORWARD, 1.0)
	check(enemy.dead, "the original valid off-center ray kills its lock")
	check(behind.dead, "a valid ray is not redirected toward the target center")


func test_charge_lock_does_not_let_a_dart_pass_through_solid_earth() -> void:
	var world := _rig()
	var enemy := _ugv(world, Vector3(40, -6, -60))
	world.player.charge_lock = enemy
	world.player.current_round = Armament.Round.APFSDS
	world.player.round_count = 6
	world.player.fire_cannon(Vector3(40, 30, 0), Vector3.FORWARD, 1.0)
	check_eq(enemy.hp, enemy.max_hp, "solid earth blocks the locked dart before its target")
