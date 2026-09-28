extends TestCase
## The 200 kW laser CIWS: engagement, heat and overheat.


func _rocket(world: World, from: Vector3, velocity: Vector3) -> Projectile:
	var rocket := world.spawn_projectile(Entity.Team.ENEMY, from, velocity, "rocket")
	rocket.interceptable = true
	rocket.intercept_hp = 0.5
	rocket.life = 10.0
	rocket.gravity = 0.0
	rocket.hit = Hit.make(Hit.Kind.SHELL, 5.0, from)
	return rocket


func test_intercepts_incoming_rocket() -> void:
	var world := stage()
	var tank := world.player
	var from := tank.global_position + Vector3(0, 12, -30)
	var rocket := _rocket(world, from, (tank.hit_center() - from).normalized() * 10.0)
	var hp := tank.hp
	var ok := await wait_until(gone(rocket), 120)
	check(ok, "rocket shot down before impact")
	check_eq(tank.hp, hp, "no damage taken")
	check(tank.ciws_heat > 0.0, "engaging builds heat")


func test_ignores_receding_and_distant_threats() -> void:
	var world := stage()
	var tank := world.player
	var away := _rocket(world, tank.global_position + Vector3(0, 8, -15), Vector3(0, 0, -20))
	var far := _rocket(world, tank.global_position + Vector3(0, 8, -120), Vector3(0, 0, 0.01))
	await frames(20)
	check(is_instance_valid(away), "rocket flying away is left alone")
	check(is_instance_valid(far), "out-of-range rocket is left alone")
	check(tank.ciws_target == null, "no target selected")


func test_saturation_overheats_and_recovers() -> void:
	var world := stage()
	var tank := world.player
	tank.ciws_heat = 0.98
	var from := tank.global_position + Vector3(0, 12, -25)
	var rocket := _rocket(world, from, (tank.hit_center() - from).normalized() * 4.0)
	rocket.intercept_hp = 100.0
	await wait_until(func() -> bool: return tank.ciws_overheated, 60)
	check(tank.ciws_overheated, "heat at 1.0 locks the laser")
	rocket.queue_free()
	var recovered := await wait_until(func() -> bool: return not tank.ciws_overheated, 600)
	check(recovered, "laser cools down and comes back")
	check(tank.ciws_heat <= 0.3, "comes back only once cooled")
