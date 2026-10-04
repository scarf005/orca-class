extends TestCase
## Dragon's breath: a 60 m jet that burns what is in it and sets the ground alight.


func _breath(tank: Tank, toward: Vector3) -> void:
	tank.load_round(Armament.Round.DRAGON)
	tank.fire_cannon(Vector3.INF, toward)


## A spot on the ground `distance` m from the muzzle along the tank's heading.
func _ahead(tank: Tank, distance: float, lateral := 0.0) -> Vector3:
	var at := tank.model.muzzle.global_position - tank.global_basis.z * distance + tank.global_basis.x * lateral
	at.y = Course.height_at(at)
	return at


func _ugv_at(world: World, tank: Tank, distance: float, lateral := 0.0) -> Ugv:
	var ugv := Ugv.new()
	ugv.position = _ahead(tank, distance, lateral)
	world.add_enemy(ugv)
	ugv.immobile = true
	ugv.disarmed = true
	return ugv


func _toward(tank: Tank, enemy: Entity) -> Vector3:
	return enemy.hit_center() - tank.model.muzzle.global_position


func test_a_target_at_50_meters_burns_and_one_at_75_is_untouched() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	for round in 5:
		seed(round)
		var near := _ugv_at(world, tank, 50.0)
		var far := _ugv_at(world, tank, 75.0, 3.0)
		var full := far.hp
		_breath(tank, _toward(tank, near))
		await frames(70)
		check(not is_instance_valid(near) or near.dead or near.burning > 0.0, "a UGV 50 m ahead catches fire or dies (round %d)" % round)
		check(is_instance_valid(far) and far.hp == full and far.burning <= 0.0, "a UGV 75 m ahead is untouched (round %d)" % round)
		for e in [near, far]:
			if is_instance_valid(e):
				e.queue_free()
		await frames(2)


func test_a_crawler_at_50_meters_dies() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var dead := 0
	for round in 5:
		seed(20 + round)
		var crawler := Crawler.new()
		crawler.position = _ahead(tank, 50.0)
		world.add_enemy(crawler)
		_breath(tank, _toward(tank, crawler))
		await frames(70)
		dead += 1 if not is_instance_valid(crawler) or crawler.dead else 0
		if is_instance_valid(crawler):
			crawler.queue_free()
		await frames(2)
	check_eq(dead, 5, "a crawler 50 m out dies every time")


func test_flyers_in_the_cone_catch_fire_and_others_do_not() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var forward := -tank.global_basis.z
	var drone := FpvDrone.new()
	world.add_enemy(drone)
	drone.global_position = tank.model.muzzle.global_position + forward * 35.0 + Vector3.UP * 3.0
	var aside := FpvDrone.new()
	world.add_enemy(aside)
	aside.global_position = tank.model.muzzle.global_position + forward * 35.0 + tank.global_basis.x * 30.0 + Vector3.UP * 3.0
	_breath(tank, forward)
	await frames(2)
	check(not is_instance_valid(drone) or drone.burning > 0.0 or drone.dead, "a drone in the cone burns as the jet leaves")
	check_near(aside.burning, 0.0, 0.0001, "one 30 m off to the side does not")


func test_the_jet_pours_out_over_a_third_of_a_second_and_reaches_60_meters() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var forward := -tank.global_basis.z
	var start := tank.model.muzzle.global_position
	seed(3)
	var inside := _ugv_at(world, tank, DragonBreath.RANGE - 1.0)
	var outside := _ugv_at(world, tank, DragonBreath.RANGE + 15.0)
	_breath(tank, forward)
	var breath: DragonBreath = world.get_children().filter(func(n: Node) -> bool: return n is DragonBreath)[0]
	var emitted: Array[int] = []
	var farthest := 0.0
	var peak := 0 ## Largest single pool.
	var total := 0
	var done_at := -1
	for frame in 60:
		await frames(1)
		emitted.append(breath._emitted if is_instance_valid(breath) else DragonBreath.FLAMES)
		if done_at < 0 and emitted[-1] >= DragonBreath.FLAMES:
			done_at = frame + 1
		for p in world.projectiles:
			if p.flame_trail:
				farthest = maxf(farthest, (p.global_position - start).dot(forward))
		peak = maxi(peak, world.fx._pools.values().map(func(pool: Array) -> int: return pool.size()).max())
		total = maxi(total, world.fx.particle_count())
	check(emitted[2] > 0 and emitted[2] < DragonBreath.FLAMES / 2, "after three frames only part of the jet is out (%d of %d)" % [emitted[2], DragonBreath.FLAMES])
	check(done_at >= 19 and done_at <= 25, "the last flame leaves at about 0.35 s (frame %d)" % done_at)
	check(farthest >= 50.0, "flames reach at least 50 m (%.1f)" % farthest)
	check(not is_instance_valid(inside) or inside.dead or inside.burning > 0.0, "the jet reaches its 60 m boundary from inside")
	check(is_instance_valid(outside) and not outside.dead and outside.burning <= 0.0 and outside.hp == outside.max_hp, "the jet stops beyond its 60 m boundary")
	check(DragonBreath.RANGE == 60.0, "the nominal jet boundary remains 60 m")
	check(peak < Fx.SOFT_CAP, "no particle pool passes the soft cap (%d of %d)" % [peak, Fx.SOFT_CAP])
	print("DRAGON peak pool ", peak, " total ", total, " farthest ", farthest, " done ", done_at)


func test_every_ground_impact_ignites_a_zone_with_the_new_stats() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	for zone in FireZone._zones:
		zone.queue_free()
	var spot := _ahead(tank, 40.0)
	FireZone.on_flame_impact(null, spot, null)
	check_eq(FireZone._zones.size(), 1, "a flame landing on the ground ignites it")
	check_near(FireZone._zones[0].life, 6.0, 0.001, "for six seconds")
	check_eq(FireZone.RADIUS, 3.5, "3.5 m wide")
	check_eq(FireZone.DAMAGE_PER_SECOND, 20.0, "and 20 damage a second")
	var victim := _ugv_at(world, tank, 60.0)
	FireZone.on_flame_impact(null, victim.global_position, victim)
	victim.queue_free()
	check_eq(FireZone._zones.size(), 1, "a flame that hits an enemy leaves no fire on the ground")
	var ugv := _ugv_at(world, tank, 40.0)
	ugv.position = spot
	var hp := ugv.hp
	await frames(70)
	check(not is_instance_valid(ugv) or ugv.hp < hp or ugv.dead, "the zone burns what stands in it")
	_breath(tank, -tank.global_basis.z + Vector3.DOWN * 0.15)
	await frames(60)
	check(FireZone._zones.size() >= 3, "a jet into the ground leaves several zones (%d)" % FireZone._zones.size())
