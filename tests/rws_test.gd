extends TestCase
## The laser RWS is a pickup: the tank starts without it, and losing it is permanent until another.


func _rocket(world: World, tank: Tank) -> Projectile:
	var from := tank.global_position + Vector3(0, 12, -30)
	var rocket := world.spawn_projectile(Entity.Team.ENEMY, from, (tank.hit_center() - from).normalized() * 10.0, "rocket")
	rocket.interceptable = true
	rocket.intercept_hp = 0.5
	rocket.life = 10.0
	rocket.gravity = 0.0
	rocket.hit = Hit.make(Hit.Kind.SHELL, 5.0, from)
	return rocket


func _wrecks(world: World) -> int:
	return world.get_children().filter(func(n: Node) -> bool: return n is Wreck).size()


func _pickup(world: World, tank: Tank, id: String) -> Pickup:
	return world.spawn_pickup(id, tank.global_position + Vector3.UP)


func test_the_tank_starts_without_an_rws() -> void:
	var world := stage("", false)
	var tank := world.player
	await frames(2)
	check(not tank.modules.laser_online(), "no laser")
	check(not tank.model.rws.visible, "no model on the roof")
	check(tank.model.fcs.visible, "but the FCS is there")
	check(tank.needs("rws"), "it needs one")
	var rocket := _rocket(world, tank)
	var got := []
	world.intercepted.connect(func(at: Vector3) -> void: got.append(at))
	await frames(90)
	check(tank.ciws_target == null and tank.ciws_heat == 0.0, "the CIWS never fires")
	check(got.is_empty(), "nothing is intercepted")
	check(is_instance_valid(rocket) and rocket.intercept_hp == 0.5, "the rocket is untouched")


func test_an_rws_pickup_mounts_it_and_the_laser_intercepts() -> void:
	var world := stage("", false)
	var tank := world.player
	await frames(2)
	var pickup := _pickup(world, tank, "rws")
	check_eq(pickup.id, "rws", "a wanted RWS pickup stays one")
	tank.collect(pickup)
	check(tank.modules.laser_online(), "the laser is online")
	check_eq(tank.modules.hp.laser, TankModules.MAX.laser, "at full health")
	check(tank.model.rws.visible, "the model shows")
	check(not tank.needs("rws"), "it no longer needs one")
	var rocket := _rocket(world, tank)
	var ok := await wait_until(gone(rocket), 150)
	check(ok, "the rocket is shot down")


func test_a_destroyed_rws_is_knocked_off_for_good() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var before := _wrecks(world)
	tank.damage_module("laser", 30.0)
	check_eq(tank.modules.state("laser"), TankModules.State.DAMAGED, "damaged first")
	check(tank.model.rws.visible and _wrecks(world) == before, "still bolted on")
	tank.modules.update(TankModules.REPAIR_TIME + 0.1)
	check_eq(tank.modules.state("laser"), TankModules.State.OK, "a damaged laser is field-repaired as before")
	tank.damage_module("laser", 999.0)
	check(not tank.modules.laser_online(), "destroyed: the laser is offline")
	check(not tank.model.rws.visible, "the model is hidden")
	check_eq(_wrecks(world), before + 1, "a burning piece flies off")
	tank.modules.update(TankModules.REPAIR_TIME * 5.0)
	check(not tank.modules.laser_online(), "the crew does not put it back")
	await frames(2)
	check(not tank.model.rws.visible, "and the roof stays bare")
	var rocket := _rocket(world, tank)
	await frames(60)
	check(tank.ciws_target == null and is_instance_valid(rocket), "no interception")
	tank.hp = 50.0
	tank.collect(_pickup(world, tank, "repair"))
	check(not tank.modules.laser_online(), "a repair pickup does not bring it back")
	check(tank.hp > 50.0, "though it does mend the hull")
	tank.hp = tank.max_hp
	check(not tank.needs("repair"), "a missing RWS does not make repairs wanted")
	tank.collect(_pickup(world, tank, "rws"))
	check(tank.modules.laser_online() and tank.model.rws.visible, "a new RWS pickup remounts it")


func test_the_piece_burns_off_without_exploding() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	tank.damage_module("laser", 999.0)
	var wreck := world.get_children().filter(func(n: Node) -> bool: return n is Wreck)[0] as Wreck
	check(not wreck.explodes, "it crashes and burns like a turret")
	check(wreck.get_child_count() > 0, "carrying the sensor model")


func test_losing_a_life_loses_the_rws() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	check(tank.modules.laser_online(), "mounted to begin with")
	tank.modules.damage("track_l", 999.0)
	tank.take_hit(Hit.make(Hit.Kind.BLAST, 9999.0, tank.global_position, Vector3.BACK))
	await wait_until(func() -> bool: return tank.hp == tank.max_hp, 240)
	check_eq(world.stats.lives, 2, "a life went")
	check(not tank.modules.laser_online(), "the spare hull has no RWS")
	check(not tank.model.rws.visible, "the roof is bare")
	check_eq(tank.modules.state("track_l"), TankModules.State.OK, "everything else is restored")
	check_eq(tank.modules.state("fcs"), TankModules.State.OK, "including the FCS")


func test_a_spare_pickup_prioritizes_repairs_and_weapons_not_an_rws() -> void:
	var world := stage("", false)
	var tank := world.player
	await frames(2)
	tank.set_coax_tier(0)
	check_eq(tank.useful_pickup("rws"), "rws", "asked for directly")
	check_eq(tank.useful_pickup("repair"), "coax", "a wasted repair becomes a coax upgrade")
	check_eq(tank.useful_pickup("coax"), "coax", "a wanted coax upgrade is left alone")
	tank.set_coax_tier(Armament.COAX_TIERS.size() - 1)
	check(Armament.round_from_id(tank.useful_pickup("coax")) in Armament.OFFERED, "a maxed coax becomes an offered special round")
	check_eq(tank.useful_pickup("apfsds"), "apfsds", "rounds are never wasted")
	tank.modules.damage("track_l", 999.0)
	check_eq(tank.useful_pickup("coax"), "repair", "repair comes first")
	tank.collect(_pickup(world, tank, "repair"))
	tank.modules.consume_era("front")
	check_eq(tank.useful_pickup("coax"), "era", "then ERA")
	tank.modules.restore_era()
	tank.tail.damage(1000.0)
	check_eq(tank.useful_pickup("coax"), "tail", "then the tail")
	tank.tail.regrow()
	check(Armament.round_from_id(tank.useful_pickup("coax")) in Armament.OFFERED, "then an offered round, never an automatic RWS")
	tank.set_coax_tier(0)
	check_eq(tank.useful_pickup("era"), "coax", "the coax upgrade comes next")


func test_a_spare_pickup_is_never_an_rws_when_it_is_mounted() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	check(not tank.needs("rws"), "mounted: not needed")
	for id: String in Pickup.IDS:
		for i in 10:
			check(tank.useful_pickup(id) != "rws", "%s never turns into an RWS" % id)


func test_stage_keeps_the_ciws_off_the_tank() -> void:
	var world := stage()
	var spots := world.director.scenery.specs.filter(func(s: Scenery.Spec) -> bool: return s.pickup == "rws").map(func(s: Scenery.Spec) -> Vector2: return Vector2(s.d, s.u))
	check(spots.is_empty(), "the current stage places no RWS pickups")
