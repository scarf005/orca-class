extends TestCase
## The main gun's charge lock outlives its shots: only the target dying or leaving the view drops it.

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


func test_the_lock_survives_the_shot_and_the_release_until_its_target_dies() -> void:
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
	check_eq(tank.charge_lock, enemy, "still locked right after the shot")
	check_eq(tank.lock_charge, 1.0, "its boxes stay at the charge it fired with")
	Input.action_release("fire")
	tank.aim_screen = world.camera.unproject_position(other.hit_center())
	for _i in 10:
		_frame(tank)
	check_eq(tank.charge_lock, enemy, "still locked after letting go, with the sight on another enemy")
	enemy.dead = true
	_frame(tank)
	check(tank.charge_lock != enemy, "its death drops it")
	check_eq(tank.lock_charge, 0.0, "and its boxes")
