extends TestCase
## Fired locks last until their target disappears or their projectiles hit or finish.

const DT := 1.0 / 60.0


func _rig() -> World:
	var world := stage()
	world.set_process(false)
	world.director.set_process(false)
	world.player.set_process(false)
	world.player.input_enabled = true
	world.camera.set_process(false)
	world.camera.follow(0.0)
	Input.action_release("fire")
	return world


func _enemy(world: World, at: Vector3) -> Enemy:
	var enemy := Enemy.new()
	enemy.position = at
	enemy.max_hp = 1.0e9
	enemy.hp = enemy.max_hp
	world.add_enemy(enemy)
	enemy.set_process(false)
	return enemy


func _frame(tank: Tank) -> void:
	tank._update_charge(DT)
	tank._update_charge_lock()
	tank._update_weapons(DT)


func test_a_full_charge_releases_its_lock_on_the_same_frame_it_hits() -> void:
	var world := _rig()
	var tank := world.player
	var enemy := _enemy(world, tank.hit_center() - Vector3(0, 0, 60))
	var other := _enemy(world, tank.hit_center() - Vector3(-12, 0, 60))
	tank.aim_screen = world.camera.unproject_position(enemy.hit_center())
	Input.action_press("fire")
	var shots := world.stats.shots
	for _i in 120:
		_frame(tank)
		if world.stats.shots > shots:
			break
	check(world.stats.shots > shots, "the full charge fired")
	check_eq(tank.charge_lock, null, "hitscan contact drops the lock immediately")
	check_eq(tank.lock_charge, 0.0, "and its boxes")
	Input.action_release("fire")


func _locked_shot(world: World, enemy: Enemy, round := Armament.Round.APHE) -> Projectile:
	var tank := world.player
	tank.load_round(round)
	tank.charge_lock = enemy
	tank.charge_part = ""
	tank.fire_cannon(tank.hit_center() + Vector3.UP * 10.0, Vector3.FORWARD, 0.3)
	return world.projectiles.back()


func test_flying_locks_end_on_contact_miss_expiry_or_removal() -> void:
	for round in [Armament.Round.APHE, Armament.Round.ATGM]:
		for ending in ["hit", "miss", "expire", "remove", "pierce", "glance"]:
			var world := _rig()
			var tank := world.player
			var enemy := _enemy(world, tank.hit_center() - Vector3(0, 0, 60))
			var shot := _locked_shot(world, enemy, round)
			check_eq(tank.charge_lock, enemy, "lock survives while the projectile flies")
			match ending:
				"hit", "glance":
					shot.hit.damage = 0.0 # Contact, not target death or damage, releases the lock.
					shot.hit.caliber = 20 if ending == "glance" else 100
					shot.detonate(enemy.hit_center(), enemy)
				"miss":
					shot.detonate(shot.global_position, null)
				"expire":
					shot.life = 0.0
					shot.step(DT)
				"remove":
					shot.queue_free()
				"pierce":
					shot.sure_target = enemy
					shot.pierce_entities = true
					shot._sweep(enemy.hit_center() + Vector3.BACK * 5.0, enemy.hit_center() + Vector3.FORWARD * 5.0)
			await frames(2)
			check_eq(tank.charge_lock, null, "%s releases %s lock" % [ending, round])
			check_eq(tank.lock_charge, 0.0, "fired boxes disappear")
			check(not enemy.dead, "the target need not die")


func test_an_old_projectile_does_not_clear_a_new_target_or_active_charge() -> void:
	var world := _rig()
	var tank := world.player
	var enemy := _enemy(world, tank.hit_center() - Vector3(0, 0, 60))
	var old := _locked_shot(world, enemy)
	enemy.dead = true
	tank._update_charge_lock()
	var other := _enemy(world, tank.hit_center() - Vector3(-12, 0, 60))
	var current := _locked_shot(world, other)
	old.detonate(old.global_position, null)
	await frames(2)
	check_eq(tank.charge_lock, other, "old shot cannot release the new target")
	Input.action_press("fire")
	tank._update_charge(Armament.TAP_TIME + DT)
	current.detonate(current.global_position, null)
	await frames(2)
	check_eq(tank.charge_lock, other, "a new held charge still needs its lock")
	check_eq(tank.lock_charge, 0.0, "the completed shot's boxes are gone")
	Input.action_release("fire")
