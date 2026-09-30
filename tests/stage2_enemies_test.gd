extends TestCase
## Phase C enemy contracts: readable warning windows, counters, water boundaries and tail priorities.

func _spawn(enemy: Enemy, at: Vector3) -> Enemy:
	enemy.position = at
	_world.add_enemy(enemy)
	return enemy

func _water_point(d: float, u: float) -> Vector3:
	var p := Course.to_world(d, u)
	var surface := Water.surface_at(p)
	p.y = surface - 0.15
	return p

func test_airboat_stays_wet_and_fan_module_kill() -> void:
	_world = stage("", true, 2)
	var boat := _spawn(Airboat.new(), _water_point(730.0, -30.0)) as Airboat
	await frames(2)
	check(Water.surface_at(boat.global_position) > Course.height_at(boat.global_position), "airboat starts on water")
	boat.destroy_fan()
	check(boat.fan_destroyed and boat.state == Airboat.State.STRANDED, "fan cage strands the boat")
	var dry := Course.ground_at(730.0, 0.0)
	boat.global_position = dry
	boat.state = Airboat.State.APPROACH
	boat.behave(0.1)
	check(Water.surface_at(boat.global_position) > Course.height_at(boat.global_position), "airboat does not travel onto a dry dike")

func test_airboat_127mm_is_small_arms_and_can_harm_sensor() -> void:
	_world = stage("", true, 2)
	var boat := _spawn(Airboat.new(), _water_point(730.0, -30.0)) as Airboat
	await frames(2)
	var tank := _world.player
	var before := tank.modules.state("laser")
	var hit := Hit.make(Hit.Kind.BULLET, 25.0, tank.model.sensor_position("laser"), Vector3.UP)
	hit.caliber = 12
	hit.source = boat
	hit.position = tank.model.sensor_position("laser")
	tank.take_hit(hit)
	check(before == TankModules.State.OK and tank.modules.state("laser") == TankModules.State.DAMAGED, "12.7 mm damages the exposed RWS sensor")
	check(tank.hp == Tank.MAX_ARMOR, "12.7 mm does not fake hull damage")

func test_spray_telegraph_and_strip_expiry_and_bounds() -> void:
	_world = stage("", true, 2)
	var drone := _spawn(SprayDrone.new(), Course.to_world(580.0, 0.0) + Vector3.UP * 8.0) as SprayDrone
	await frames(2)
	var mist := SprayMist.spawn(drone.global_position, Vector3.FORWARD)
	mist.life = SprayDrone.MIST_TIME
	check(not drone.mist_active, "spray is not active before the warning")
	check(mist.inside_strip(mist.global_position), "tank in the strip is inside")
	check(not mist.inside_strip(mist.global_position + Vector3.RIGHT * (mist.width + 1.0)), "tank outside the strip is safe")
	mist.life = 0.0
	await frames(1)
	check(not is_instance_valid(mist), "spray mist expires")

func test_heron_warning_legs_topple_and_fallen_tail_throw() -> void:
	_world = stage("", true, 2)
	var heron := _spawn(HeronWalker.new(), Course.ground_at(640.0, 0.0)) as HeronWalker
	await frames(2)
	heron.state = HeronWalker.State.TELEGRAPH
	heron._state_time = 0.0
	heron.behave(HeronWalker.TELEGRAPH_TIME * 0.5)
	check(heron.state == HeronWalker.State.TELEGRAPH, "beak circle keeps its warning window")
	var leg_hit := Hit.make(Hit.Kind.SHELL, 12.0, heron.global_position + Vector3.DOWN * 0.1, Vector3.FORWARD)
	heron.take_hit(leg_hit)
	check(heron.fallen and heron.state == HeronWalker.State.FALLEN, "leg damage topples heron")
	heron.throw_from_tail()
	check(heron.dead, "fallen heron can be grabbed and thrown by the tail")

func test_leech_only_latches_in_water_and_slows_then_tail_removes() -> void:
	_world = stage("", true, 2)
	var tank := _world.player
	var leech := _spawn(CanalLeech.new(), _water_point(1450.0, -40.0)) as CanalLeech
	await frames(2)
	var wet_tank := _water_point(1450.0, -40.0)
	tank.global_position = wet_tank
	leech._latch(tank)
	check(leech.latched and leech.get_meta("leech_latched", false), "leech latches on wet hull")
	check(tank.water_factor() < Tank.WADE_SPEED, "a latch slows lateral movement")
	_world.player.swat(false)
	check(not leech.latched, "tail swat removes a latched leech")
	var dry_leech := _spawn(CanalLeech.new(), Course.ground_at(1450.0, 0.0)) as CanalLeech
	await frames(1)
	dry_leech._latch(tank)
	check(not dry_leech.latched, "leech cannot latch on a dry dike")

func test_eggs_hatch_three_crawlers_only_after_warning() -> void:
	_world = stage("", true, 2)
	var eggs := _spawn(SnailEggCluster.new(), Course.ground_at(520.0, 18.0)) as SnailEggCluster
	await frames(2)
	check(eggs.hatch_count == 0, "eggs wait before hatching")
	eggs.hatch()
	await frames(1)
	check_eq(eggs.hatch_count, 3, "three crawlers hatch")
	check(_world.enemies.filter(func(e: Entity) -> bool: return e is Crawler).size() >= 3, "hatched crawlers enter the world")

func test_lotus_mine_arms_and_blast_is_not_era_decided() -> void:
	_world = stage("", true, 2)
	var mine := _spawn(LotusMine.new(), _water_point(1550.0, -18.0)) as LotusMine
	await frames(2)
	mine.state = LotusMine.State.ARMING
	mine._state_time = 0.0
	mine.behave(LotusMine.ARM_TIME * 0.5)
	check(mine.state == LotusMine.State.ARMING, "mine ticks during its arm telegraph")
	mine.behave(LotusMine.ARM_TIME)
	check(mine.armed and mine.state == LotusMine.State.ARMED, "mine arms after the warning")
	var tank := _world.player
	tank.global_position = mine.global_position
	var era_before: Dictionary = tank.modules.era.duplicate()
	mine.detonate(tank)
	check(mine.detonated and tank.modules.era == era_before, "lotus blast does not consume ERA")

func test_gnats_are_fragile_swatform_and_small_blast_not_warhead() -> void:
	_world = stage("", true, 2)
	var swarm := _spawn(GnatSwarm.new(), Course.to_world(90.0, 0.0) + Vector3.UP * 5.0) as GnatSwarm
	await frames(2)
	var tank := _world.player
	var hp_before := tank.hp
	swarm.global_position = tank.global_position + Vector3.FORWARD * 4.0
	swarm._attack(tank)
	check(tank.hp < hp_before, "gnat attack hurts the tank")
	check(not swarm.era_decided, "gnat attack never makes an ERA decision")
	check(swarm.damage_multiplier(Hit.make(Hit.Kind.BLAST, 1.0, swarm.global_position)) > 1.0, "gnats are fragile to blast")
	_world.player.swat(false)
	check(swarm.dead or swarm.hp < swarm.max_hp, "gnats are swat fodder")
