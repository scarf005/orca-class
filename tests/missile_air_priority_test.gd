extends TestCase
## Both player missile rounds prefer eligible air targets without losing ground fallback.


func _rig() -> World:
	var world := stage()
	world.set_process(false)
	world.director.set_process(false)
	world.player.set_process(false)
	world.camera.set_process(false)
	world.camera.follow(0.0)
	return world


func _enemy(world: World, at: Vector3, flying: bool) -> Enemy:
	var enemy := Enemy.new()
	enemy.position = at
	enemy.flying = flying
	world.add_enemy(enemy)
	enemy.set_process(false)
	return enemy


func test_missile_locks_prefer_air_only_inside_the_lock_ring() -> void:
	for round in [Armament.Round.ATGM, Armament.Round.MICRO, Armament.Round.APHE]:
		for air_first in [false, true]:
			var world := _rig()
			var tank := world.player
			tank.load_round(round)
			var at := tank.hit_center() + Vector3(0, 0, -60)
			var air: Enemy
			var ground: Enemy
			if air_first:
				air = _enemy(world, at + Vector3(1, 0, 0), true)
				ground = _enemy(world, at, false)
			else:
				ground = _enemy(world, at, false)
				air = _enemy(world, at + Vector3(1, 0, 0), true)
			tank.aim_screen = world.camera.unproject_position(ground.hit_center())
			check_eq(tank._nearest_lockable()[0], ground if round == Armament.Round.APHE else air, "only missiles prefer air regardless of iteration order")
			air.position.x += 1000.0
			check_eq(tank._nearest_lockable()[0], ground, "air outside the ring does not displace ground")
			air.position = at + Vector3(1, 0, 0)
			air.dead = true
			check_eq(tank._nearest_lockable()[0], ground, "dead air targets cannot lock")
			cleanup()
			await frames(1)


func test_both_missiles_retarget_air_then_fall_back_to_ground() -> void:
	for round in [Armament.Round.ATGM, Armament.Round.MICRO]:
		for air_first in [false, true]:
			var world := _rig()
			var origin := world.player.hit_center() + Vector3(0, 30, -40)
			var air: Enemy
			var ground: Enemy
			if air_first:
				air = _enemy(world, origin + Vector3(0, 0, -60), true)
				ground = _enemy(world, origin + Vector3(0, 0, -10), false)
			else:
				ground = _enemy(world, origin + Vector3(0, 0, -10), false)
				air = _enemy(world, origin + Vector3(0, 0, -60), true)
			var nearer_air := _enemy(world, origin + Vector3(0, 0, -30), true)
			var missile := world.player._spawn_missile(round, origin, Vector3.FORWARD, null, "")
			missile._retarget()
			check_eq(missile.homing_target, nearer_air, "nearest air wins over closer ground")
			nearer_air.dead = true
			missile._retarget()
			check_eq(missile.homing_target, air, "dead air is skipped")
			air.position.z -= Armament.ATGM_RETARGET_RANGE
			missile._retarget()
			check_eq(missile.homing_target, ground, "out-of-range air falls back to ground")
			check(missile._seeking(), "a living ground lock remains valid")
			cleanup()
			await frames(1)
