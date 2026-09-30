extends TestCase
## Phase C enemy contracts: each test drives the real warning state into its attack and counter.

func begin(name: String) -> void:
	super.begin(name)
	# Keep this suite's authored meshes/effects from perturbing later Stage 1 RNG fixtures.
	seed(hash(name))

func _spawn(enemy: Enemy, at: Vector3) -> Enemy:
	enemy.position = at
	_world.add_enemy(enemy)
	return enemy

func _water_point(d: float, u: float) -> Vector3:
	var p := Course.to_world(d, u)
	var surface := Water.surface_at(p)
	p.y = surface - 0.15
	return p

func _freeze_tank() -> Tank:
	_world.rail.mode = Rail.Mode.HOLD
	_world.player.input_enabled = false
	_world.player.set_process(false)
	return _world.player

func test_airboat_telegraph_attack_sensor_and_fan_shot_kill() -> void:
	_world = stage("", true, 2)
	var tank := _freeze_tank()
	var p := _water_point(730.0, -30.0)
	tank.global_position = p
	var boat := _spawn(Airboat.new(), p + Vector3.BACK * 8.0) as Airboat
	await frames(2)
	boat.set_process(false)
	check(Water.surface_at(boat.global_position) > Course.height_at(boat.global_position), "airboat starts on water")
	boat.state = Airboat.State.TELEGRAPH
	boat._state_time = 0.0
	boat.behave(Airboat.TELEGRAPH_TIME - 0.01)
	check(boat.state == Airboat.State.TELEGRAPH and _world.projectiles.is_empty(), "fan roar precedes the burst")
	boat.behave(0.01)
	check(boat.state == Airboat.State.BURST, "airboat attacks only after its warning")
	boat.behave(0.11)
	check(_world.projectiles.any(func(pj: Projectile) -> bool: return pj.hit.caliber == 12), "burst is a real 12.7 mm bullet")
	await frames(10)
	check(tank.modules.hp["laser"] < TankModules.MAX["laser"] or tank.modules.hp["fcs"] < TankModules.MAX["fcs"], "the real shot can damage an exposed sensor")
	var dry := Course.ground_at(730.0, 18.0)
	check(Water.surface_at(dry) <= Course.height_at(dry), "a dike is dry")
	var fan_hit := Hit.make(Hit.Kind.SHELL, 8.0, boat._fan.global_position, Vector3.BACK)
	fan_hit.source = tank
	boat.take_hit(fan_hit)
	check(boat.fan_destroyed and boat.dead, "shooting the rear fan kills the boat")

func test_spray_real_warning_strip_damage_bounds_and_expiry() -> void:
	_world = stage("", true, 2)
	var tank := _freeze_tank()
	var drone := _spawn(SprayDrone.new(), tank.global_position + Vector3.UP * 8.0) as SprayDrone
	await frames(2)
	drone.set_process(false)
	drone.state = SprayDrone.State.TELEGRAPH
	drone._state_time = 0.0
	drone.behave(SprayDrone.TELEGRAPH_TIME - 0.01)
	check(not drone.mist_active, "dripping nozzles precede the full strip")
	drone.behave(0.01)
	check(drone.mist_active, "full spray begins after 0.8 seconds")
	var mist: SprayMist
	for child in _world.get_children():
		if child is SprayMist:
			mist = child as SprayMist
	check(mist != null, "the drone creates a strip hazard")
	mist.set_process(false)
	var hp_before := tank.hp
	tank.global_position = mist.global_position
	mist._process(0.15)
	check(tank.hp < hp_before, "the strip damages a tank inside")
	hp_before = tank.hp
	tank.invuln = 0.0
	tank.global_position = mist.global_position + Vector3.RIGHT * (mist.width + 1.0)
	mist._process(0.15)
	check_near(tank.hp, hp_before, 0.01, "the strip does not damage outside its width")
	mist.life = 0.0
	mist._process(0.01)
	await frames(1)
	check(not is_instance_valid(mist), "the corrosive strip expires")

func test_heron_warning_stab_topple_and_actual_tail_throw() -> void:
	_world = stage("", true, 2)
	var tank := _freeze_tank()
	var heron := _spawn(HeronWalker.new(), tank.global_position + Vector3.FORWARD * 10.0) as HeronWalker
	await frames(2)
	heron.set_process(false)
	heron._attack_timer = 0.0
	heron.behave(0.01)
	check(heron.state == HeronWalker.State.TELEGRAPH, "heron neck draw-back starts its warning")
	var hp_before := tank.hp
	heron.behave(HeronWalker.TELEGRAPH_TIME - 0.01)
	check(tank.hp == hp_before, "the impact circle gives a fair dodge window")
	heron.behave(0.01)
	check(tank.hp < hp_before, "the beak stab hurts the tank")
	# The same lance state cannot hurt beyond its stated fourteen-metre reach.
	tank.global_position = heron.global_position + Vector3.FORWARD * 16.0
	heron.state = HeronWalker.State.TELEGRAPH
	heron._state_time = 0.0
	heron._impact = tank.global_position
	hp_before = tank.hp
	heron.behave(HeronWalker.TELEGRAPH_TIME)
	check(tank.hp == hp_before, "heron lance has a fourteen-metre reach limit")
	var leg_hit := Hit.make(Hit.Kind.SHELL, 12.0, heron.global_position + Vector3.DOWN * 0.1, Vector3.FORWARD)
	heron.take_hit(leg_hit)
	check(heron.fallen and heron.state == HeronWalker.State.FALLEN, "leg damage topples heron")
	# This is the ordinary tail path, not a direct throw helper: fallen herons are selected after swat/snatch.
	tank.global_position = heron.global_position + Vector3.BACK * 2.0
	tank.auto_tail()
	await frames(30)
	check(not is_instance_valid(heron), "the tail grabs and throws a fallen heron")

func test_leech_real_ripple_latch_drain_dry_refusal_blast_and_tail_priority() -> void:
	_world = stage("", true, 2)
	var tank := _freeze_tank()
	var p := _water_point(1450.0, -40.0)
	tank.global_position = p
	var leech := _spawn(CanalLeech.new(), p) as CanalLeech
	leech.set_process(false)
	await frames(2)
	leech.behave(0.01)
	check(leech.state == CanalLeech.State.TELEGRAPH, "bubbles precede a leech lunge")
	leech.behave(CanalLeech.TELEGRAPH_TIME - 0.02)
	check(not leech.latched, "the ripple is not an instant latch")
	leech.behave(0.02)
	check(leech.latched, "leech latches after its warning")
	var hp_before := tank.hp
	leech.behave(0.2)
	check(tank.hp < hp_before, "a latch drains hull HP")
	tank.auto_tail()
	check(leech.dead, "swat priority removes a latched leech")
	# A full warning can move a distant leech toward the hull, but it cannot teleport the last gap.
	var miss_leech := _spawn(CanalLeech.new(), p) as CanalLeech
	miss_leech.set_process(false)
	tank.global_position = p + Vector3.FORWARD * 50.0
	miss_leech.state = CanalLeech.State.TELEGRAPH
	miss_leech._state_time = 0.0
	miss_leech.behave(CanalLeech.TELEGRAPH_TIME)
	check(not miss_leech.latched and miss_leech.global_position.distance_to(tank.global_position) > CanalLeech.LATCH_DISTANCE, "distant leech lunges without a teleport latch")
	var dry_tank := Course.ground_at(1450.0, 0.0)
	var dry_leech := _spawn(CanalLeech.new(), p) as CanalLeech
	dry_leech.set_process(false)
	tank.global_position = dry_tank
	dry_leech.state = CanalLeech.State.TELEGRAPH
	dry_leech._state_time = 0.0
	dry_leech.behave(0.1)
	check(not dry_leech.latched, "a wet-origin leech refuses a dry-dike tank")
	var blast_leech := _spawn(CanalLeech.new(), p) as CanalLeech
	blast_leech.set_process(false)
	blast_leech.take_hit(Hit.make(Hit.Kind.BLAST, 20.0, blast_leech.global_position))
	check(blast_leech.dead, "a blast removes a leech")

func test_leech_live_rail_latch_survives_ramming_and_drains() -> void:
	_world = stage("", true, 2)
	var tank := _world.player
	tank.input_enabled = false
	_world.rail.mode = Rail.Mode.HOLD
	_world.rail.d = 1450.0
	tank.course_offset = 0.0
	tank.course_u = -40.0
	tank.local_velocity = Vector2.ZERO
	tank._place(_world.rail.d)
	tank.tail.destroyed = true
	var leech := _spawn(CanalLeech.new(), tank.global_position + Vector3.BACK * 2.0) as CanalLeech
	await wait_until(func() -> bool: return leech.latched, 120)
	check(leech.latched, "a live rail tick reaches the latch state")
	var hp_before := tank.hp
	await frames(20)
	check(leech.latched and tank.hp < hp_before, "a latched leech survives ramming and drains while the tail is disabled")
	check(tank.water_factor() < Tank.WADE_SPEED, "the live latch slows strafing")

func test_eggs_real_swell_hatch_and_destroy_before_hatch() -> void:
	_world = stage("", true, 2)
	var tank := _freeze_tank()
	var eggs := _spawn(SnailEggCluster.new(), tank.global_position + Vector3.FORWARD * 8.0) as SnailEggCluster
	eggs.set_process(false)
	await frames(2)
	eggs.behave(0.01)
	check(eggs.state == SnailEggCluster.State.SWELL, "eggs brighten when the tank approaches")
	eggs.behave(SnailEggCluster.TELEGRAPH_TIME - 0.02)
	check(eggs.hatch_count == 0, "swelling eggs have not hatched before the deadline")
	eggs.behave(0.02)
	check_eq(eggs.hatch_count, 3, "three crawlers hatch after the warning")
	var unhatched := _spawn(SnailEggCluster.new(), tank.global_position + Vector3.RIGHT * 30.0) as SnailEggCluster
	await frames(1)
	unhatched.set_process(false)
	var crawler_before := _world.enemies.filter(func(e: Entity) -> bool: return e is Crawler).size()
	unhatched.take_hit(Hit.make(Hit.Kind.SHELL, 999.0, unhatched.global_position))
	await frames(1)
	check_eq(_world.enemies.filter(func(e: Entity) -> bool: return e is Crawler).size(), crawler_before, "destroyed egg cluster hatches no crawlers")

func test_lotus_real_arm_detonation_damage_and_shot_counter() -> void:
	_world = stage("", true, 2)
	var tank := _freeze_tank()
	var p := _water_point(1550.0, -40.0)
	tank.global_position = p
	var mine := _spawn(LotusMine.new(), p) as LotusMine
	mine.set_process(false)
	await frames(2)
	mine.behave(0.01)
	check(mine.state == LotusMine.State.ARMING, "lotus veins begin ticking on proximity")
	mine.behave(LotusMine.ARM_TIME - 0.02)
	check(not mine.armed, "mine is safe during the arm warning")
	mine.behave(0.02)
	check(mine.armed, "mine arms after the warning")
	var hp_before := tank.hp
	mine.behave(0.01)
	check(mine.detonated and tank.hp < hp_before, "armed lotus detonates and damages the tank")
	var safe_mine := _spawn(LotusMine.new(), p) as LotusMine
	safe_mine.set_process(false)
	tank.invuln = 0.0
	hp_before = tank.hp
	var safe_hit := Hit.make(Hit.Kind.BULLET, 20.0, safe_mine.global_position)
	safe_hit.source = tank
	safe_mine.take_hit(safe_hit)
	check(safe_mine.dead and tank.hp == hp_before, "shooting a mine first prevents its damage")

func test_gnats_real_warning_blast_no_era_and_ciws_overheat() -> void:
	_world = stage("", true, 2)
	var tank := _freeze_tank()
	var swarm := _spawn(GnatSwarm.new(), tank.global_position + Vector3.FORWARD * 4.0 + Vector3.UP * 2.0) as GnatSwarm
	await frames(2)
	swarm.set_process(false)
	swarm.attack_timer = 0.0
	swarm.behave(0.01)
	check(swarm.state == GnatSwarm.State.TELEGRAPH, "gnat whine precedes the cloud attack")
	var hp_before := tank.hp
	swarm.behave(GnatSwarm.TELEGRAPH_TIME - 0.01)
	check(tank.hp == hp_before, "gnats wait through their warning")
	swarm.behave(0.01)
	check(tank.hp < hp_before, "gnat small blast hurts without an ERA decision")
	var era_before: Dictionary = tank.modules.era.duplicate()
	swarm.global_position = tank.global_position + Vector3.FORWARD * 20.0
	var swat_swarm := _spawn(GnatSwarm.new(), tank.global_position + Vector3.FORWARD * 3.0) as GnatSwarm
	swat_swarm.set_process(false)
	swat_swarm.state = GnatSwarm.State.TELEGRAPH
	tank.swat(false)
	check(swat_swarm.dead, "gnats are fragile swat fodder")
	swarm.global_position = tank.global_position + Vector3.FORWARD * 4.0 + Vector3.UP * 2.0
	for _i in 14:
		tank._update_ciws(0.1)
	check(tank.ciws_heat >= 0.9 or tank.ciws_overheated, "the dense swarm stresses CIWS heat")
	check(tank.modules.era == era_before, "gnats never consume ERA")

func test_airboat_rejects_a_dry_step() -> void:
	_world = stage("", true, 2)
	var boat := _spawn(Airboat.new(), _water_point(730.0, -30.0)) as Airboat
	await frames(2)
	boat.set_process(false)
	var before := boat.global_position
	var dry := Course.ground_at(730.0, 18.0)
	check(not boat.water_step(dry), "airboat rejects a step onto a dry dike")
	check(boat.global_position.is_equal_approx(before), "the rejected water step does not teleport across land")
