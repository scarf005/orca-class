extends TestCase
## Fired locks last until their target disappears or their projectiles hit or finish.

const DT := 1.0 / 60.0

class LockHud extends Hud:
	var boxes: Array[float] = []

	func _draw_lock_box(_center: Vector2, half: float, _angle: float, _color: Color) -> void:
		boxes.append(half)


func test_fired_full_charge_draws_all_three_boxes_already_settled() -> void:
	var hud := LockHud.new()
	hud.world = _rig()
	add_child(hud)
	hud._draw_lock_boxes(Vector2.ZERO, 20.0, 1.0, Color.WHITE, true)
	check_eq(hud.boxes.size(), 3, "the full-charge display includes every box")
	for i in 3:
		check_near(hud.boxes[i], 20.0 * (1.0 + i * 0.32), 0.001, "fired boxes are converged, not still spinning in")
	hud.queue_free()
	await frames(2)


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


func test_a_full_charge_shows_its_boxes_for_a_tenth_of_a_second_after_it_hits() -> void:
	var world := _rig()
	var tank := world.player
	var enemy := _enemy(world, tank.hit_center() - Vector3(0, 0, 60))
	tank.aim_screen = world.camera.unproject_position(enemy.hit_center())
	Input.action_press("fire")
	var shots := world.stats.shots
	for _i in 120:
		_frame(tank)
		if world.stats.shots > shots:
			break
	check(world.stats.shots > shots, "the full charge fired")
	check_eq(tank.charge_lock, enemy, "hitscan keeps the completed lock briefly")
	check_eq(tank.lock_charge, 1.0, "all three boxes remain visible")
	await frames(3)
	check_eq(tank.lock_charge, 1.0, "the display lasts at least 0.1 seconds")
	await frames(7)
	check_eq(tank.charge_lock, null, "hitscan contact releases the lock after the delay")
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
			await frames(10)
			check_eq(tank.charge_lock, null, "%s releases %s lock" % [ending, round])
			check_eq(tank.lock_charge, 0.0, "fired boxes disappear")
			check(not enemy.dead, "the target need not die")


func test_a_shared_lock_lasts_until_the_last_projectile_resolves() -> void:
	var world := _rig()
	var tank := world.player
	var enemy := _enemy(world, tank.hit_center() - Vector3(0, 0, 60))
	var first := _locked_shot(world, enemy)
	var second := _locked_shot(world, enemy)
	first.detonate(first.global_position, null)
	check_eq(tank.charge_lock, enemy, "another projectile still needs this lock")
	second.detonate(second.global_position, null)
	await frames(10)
	check_eq(tank.charge_lock, null, "the last shot releases it after the display delay")


func test_target_death_or_leaving_the_view_drops_a_flying_lock() -> void:
	for death in [true, false]:
		var world := _rig()
		var tank := world.player
		var enemy := _enemy(world, tank.hit_center() - Vector3(0, 0, 60))
		_locked_shot(world, enemy)
		if death:
			enemy.dead = true
		else:
			enemy.global_position = world.camera.global_position + world.camera.global_basis.z * 100.0
		tank._update_charge_lock()
		check_eq(tank.charge_lock, null, "death or leaving the view still releases the targeting lock")
		check_eq(tank.lock_charge, 0.3, "its fired display survives briefly")
		await frames(10)
		check_eq(tank.lock_charge, 0.0, "its fired boxes disappear after 0.1 seconds")


func test_freed_targets_leave_a_safe_display_snapshot_during_the_delay() -> void:
	var world := _rig()
	var tank := world.player
	var enemy := _enemy(world, tank.hit_center() - Vector3(0, 0, 60))
	var shot := _locked_shot(world, enemy)
	var resolutions := [0]
	shot.resolved.connect(func() -> void: resolutions[0] += 1)
	var focus := enemy.hit_center()
	shot.detonate(focus, enemy)
	enemy.queue_free()
	await frames(2)
	tank._update_charge_lock()
	check_eq(tank.lock_visual[0], focus, "the display has a position independent of the freed target")
	check_eq(tank.lock_charge, 0.3, "the display remains during its grace period")
	check_eq(resolutions[0], 1, "contact, detonation and removal resolve the projectile only once")
	await frames(10)
	check_eq(tank.lock_charge, 0.0, "the cached display is removed on schedule")


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
	await frames(10)
	check_eq(tank.charge_lock, other, "old shot cannot release the new target")
	Input.action_press("fire")
	tank._update_charge(Armament.TAP_TIME + DT)
	current.detonate(current.global_position, null)
	await frames(10)
	check_eq(tank.charge_lock, other, "a new held charge still needs its lock")
	check_eq(tank.lock_charge, 0.0, "the completed shot's boxes are gone")
	Input.action_release("fire")
