extends TestCase
## War Thunder-style modules: ERA versus warheads, module effects, field repair, enemy modules.


func _warhead(tank: Tank, from_direction: Vector3) -> Hit:
	var hit := Hit.make(Hit.Kind.BLAST, 14.0, tank.hit_center() - from_direction * 2.0, from_direction)
	hit.warhead = true
	return hit


func test_era_stops_a_frontal_warhead() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var hp := tank.hp
	tank.take_hit(_warhead(tank, tank.global_basis.z))
	check_eq(tank.hp, hp, "no hull damage")
	check_eq(tank.modules.era.front, TankModules.ERA.front - 1, "one front brick spent")
	check(not tank.model.era_blocks.front[TankModules.ERA.front - 1].visible, "the spent brick is gone from the hull")
	check_eq(world.stats.lives, 3, "no life lost")


func test_warhead_on_bare_armor_is_fatal() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	tank.take_hit(_warhead(tank, -tank.global_basis.z))
	check_eq(world.stats.lives, 2, "a rear hit with no ERA costs a life")


func test_warhead_after_era_runs_out_is_fatal() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	for i in TankModules.ERA.left:
		tank.invuln = 0.0
		tank.take_hit(_warhead(tank, tank.global_basis.x))
	check_eq(world.stats.lives, 3, "every left brick absorbs one")
	tank.invuln = 0.0
	tank.take_hit(_warhead(tank, tank.global_basis.x))
	check_eq(world.stats.lives, 2, "the next left hit goes through")


func test_module_effects_and_field_repair() -> void:
	var world := stage()
	var tank := world.player
	tank.modules.damage("breech", 999.0)
	tank.reload = 0.0
	tank.fire_cannon()
	check_near(tank.reload, Armament.RELOAD * 3.0, 0.01, "destroyed breech triples the reload")
	tank.modules.damage("engine", 999.0)
	check(not tank.modules.overdrive_online(), "dead engine: no overdrive")
	check_eq(tank.modules.meter_refill_factor(), 0.0, "and no meter refill")
	tank.modules.update(TankModules.REPAIR_TIME + 0.1)
	check_eq(tank.modules.state("breech"), TankModules.State.DAMAGED, "crew repairs one step")
	tank.modules.update(TankModules.REPAIR_TIME + 0.1)
	check_eq(tank.modules.state("breech"), TankModules.State.OK, "and then the next")


func test_destroyed_laser_stops_interception() -> void:
	var world := stage()
	var tank := world.player
	tank.modules.damage("laser", 999.0)
	var from := tank.global_position + Vector3(0, 10, -25)
	var rocket := world.spawn_projectile(Entity.Team.ENEMY, from, (tank.hit_center() - from).normalized() * 5.0, "rocket")
	rocket.interceptable = true
	rocket.life = 10.0
	await frames(20)
	check(tank.ciws_target == null, "laser offline")
	check(is_instance_valid(rocket), "rocket untouched")


func test_respawn_restores_modules() -> void:
	var world := stage()
	var tank := world.player
	tank.modules.damage("track_l", 999.0)
	tank.modules.consume_era("front")
	tank.tail.damage(1000.0)
	tank.take_hit(Hit.make(Hit.Kind.BLAST, 9999.0, tank.global_position, Vector3.BACK))
	await wait_until(func() -> bool: return tank.hp == tank.max_hp, 240)
	check_eq(tank.modules.state("track_l"), TankModules.State.OK, "fresh tracks")
	check_eq(tank.modules.era.front, TankModules.ERA.front, "fresh ERA")
	check(not tank.tail.destroyed, "spare hull comes with a tail")


func test_ugv_modules() -> void:
	var world := stage()
	var ugv: Ugv = load("res://scripts/enemies/ugv.gd").new()
	ugv.position = Course.ground_at(world.rail.d + 60.0, 0.0)
	world.add_enemy(ugv)
	var low := Hit.make(Hit.Kind.SHELL, 35.0, ugv.global_position + Vector3.UP * 0.3)
	ugv.take_hit(low)
	check(ugv.immobile, "track hit immobilizes")
	var high := Hit.make(Hit.Kind.SHELL, 30.0, ugv.global_position + Vector3.UP * 1.8)
	ugv.take_hit(high)
	check(ugv.disarmed, "turret hit disarms")
	check(not ugv.dead, "the hull is still alive")
