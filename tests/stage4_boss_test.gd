extends TestCase
## The tracked fortress: it crashes in through the jungle untouchable, only its modules take damage, every attack is
## announced before it lands, and the tank can answer by shooting out its tracks, guns, turret and fuel.

const STEP := 1.0 / 60.0


## A fortress in the clearing, already fighting, facing along its own heading with the tank `ahead` metres in front.
func _fight(ahead := Fortress.HULL_FRONT + 50.0) -> Fortress:
	var world := stage("boss", false, 4)
	world.director._next_event = world.director.events.size()
	world.rail.mode = Rail.Mode.HOLD
	var fortress := Fortress.new()
	world.add_enemy(fortress)
	world.boss = fortress
	fortress._state = Fortress.State.FIGHT
	fortress.invulnerable = false
	fortress.global_position = Course.to_world(Stage4.CLEARING_D, 0.0)
	fortress._yaw = 0.0
	fortress._speed = 0.0
	fortress._next_attack = 1000.0
	fortress._pose(1.0)
	_place_tank(fortress, ahead)
	return fortress


func _place_tank(fortress: Fortress, ahead: float, across := 0.0) -> void:
	var at := fortress.global_position + Vector3(across, 0.0, -ahead)
	world_tank().displace(Vector3(at.x, Course.height_at(at), at.z))


func world_tank() -> Tank:
	return World.current.player


func _step(fortress: Fortress, seconds: float) -> void:
	for _i in roundi(seconds / STEP):
		world_tank().invuln = 0.0
		fortress.behave(STEP)
		for node in World.current.get_children():
			if node is FlameJet:
				node._process(STEP)


func _shell(at: Vector3, rounds := 1.0) -> Hit:
	var hit := Hit.make(Hit.Kind.SHELL, rounds * Armament.SHELL_DAMAGE, at, Vector3.FORWARD)
	hit.weapon = "cannon"
	hit.caliber = 120
	hit.source = World.current.player
	return hit


## A volley that finishes module `name` whatever its health.
func _kill(at: Vector3, name: String) -> Hit:
	return _shell(at, 2.0 * Fortress.MODULE_HP[name] / Fortress.ROUND_DAMAGE)


func _hostile_zones() -> Array:
	return FireZone._zones.filter(func(zone: FireZone) -> bool: return is_instance_valid(zone) and zone.hostile)


func _flame_jets() -> Array:
	return World.current.get_children().filter(func(node: Node) -> bool: return node is FlameJet)


func test_the_fortress_crashes_in_untouchable_and_fells_the_jungle_in_its_lane() -> void:
	var world := stage("boss", false, 4)
	world.director._next_event = world.director.events.size()
	world.rail.mode = Rail.Mode.HOLD
	var scenery: Scenery = world.director.scenery
	var standing := func() -> int:
		return scenery.specs.filter(func(spec: Scenery.Spec) -> bool: return spec.kind in Fortress.CRUSH_KINDS and not spec.has_meta("destroyed")).size()
	var before: int = standing.call()
	var fortress := Fortress.new()
	world.add_enemy(fortress)
	check(fortress.invulnerable, "it is out of reach on the way in")
	var hp := fortress.hp
	fortress.take_hit(_shell(fortress.module_at("turret")))
	check_eq(fortress.hp, hp, "a round at its turret does nothing while it is still crashing in")
	check(fortress.aim_parts().is_empty(), "and the targeting offers no module")
	world.player.global_position = Course.ground_at(Stage4.CLEARING_D - 60.0, 0.0)
	for _i in roundi(14.0 / STEP):
		fortress.behave(STEP)
		if fortress._state == Fortress.State.FIGHT:
			break
	check_eq(fortress._state, Fortress.State.FIGHT, "it becomes a fight once it is well inside the rim")
	check(not fortress.invulnerable, "and is then vulnerable")
	var felled: int = before - standing.call()
	check(felled >= 12, "it leaves the trees and ruins of its lane flattened (%d of %d)" % [felled, before])


func test_ruins_and_trees_stand_in_the_fortresss_path() -> void:
	var world := stage("", false, 4)
	var scenery: Scenery = world.director.scenery
	var entry := Course.to_course(Course.stage.boss_position())
	var centre := Vector2(Stage4.CLEARING_D, 0.0)
	var along := func(kind: String) -> int:
		return scenery.specs.filter(func(spec: Scenery.Spec) -> bool:
			return spec.kind == kind and Geometry2D.get_closest_point_to_segment(Vector2(spec.d, spec.u), entry, centre).distance_to(Vector2(spec.d, spec.u)) < Fortress.CRUSH_REACH + 12.0).size()
	check(along.call("jungle_tree") >= 10, "figs crowd the lane the fortress will drive down (%d)" % along.call("jungle_tree"))
	check(along.call("jungle_building") >= 4, "overgrown ruins stand beside it (%d)" % along.call("jungle_building"))


func test_the_hull_only_sparks_and_a_module_takes_main_gun_rounds_at_forty_each() -> void:
	var fortress := _fight()
	var hull := fortress.model.to_global(Vector3(0.0, 12.0, 10.0) * Fortress.SCALE)
	for name: String in Fortress.MODULES:
		check(hull.distance_to(fortress.module_at(name)) - Fortress.MODULE_RADIUS[name] > 1.5, "the probe point is clear of %s" % name)
	var hp := fortress.hp
	fortress.take_hit(_shell(hull, 3.0))
	check_eq(fortress.hp, hp, "three rounds into the hull plate leave every module intact")
	var turret := fortress.module_at("turret")
	fortress.take_hit(_shell(turret))
	check_near(fortress.parts.turret, Fortress.MODULE_HP.turret - Fortress.ROUND_DAMAGE * fortress.damage_multiplier(_shell(turret)), 0.01, "one round on the turret costs a round's worth of its health")
	check_eq(fortress.parts.track_l, Fortress.MODULE_HP.track_l, "and nothing else")
	var fire := Hit.make(Hit.Kind.FIRE, 500.0, turret)
	fortress.take_hit(fire)
	check(fortress.parts.turret > 0.0 and fortress.parts.turret >= Fortress.MODULE_HP.turret - Fortress.ROUND_DAMAGE, "fire does not hurt it")


func test_a_full_charge_fired_from_behind_reaches_the_rear_fuel_tanks() -> void:
	for name in ["fuel_l", "fuel_r"]:
		var fortress := _fight()
		_place_tank(fortress, -(Fortress.HULL_REAR + 80.0))
		var tank := world_tank()
		tank.look_at(fortress.global_position * Vector3(1, 0, 1) + Vector3.UP * tank.global_position.y)
		var muzzle := tank.model.muzzle.global_position
		tank.fire_cannon(muzzle, (fortress.module_at(name) - muzzle).normalized(), 1.0)
		await frames(60)
		check(fortress.parts[name] < Fortress.MODULE_HP[name], "a shell aimed from behind at %s strikes it, not the hull around it" % name)


func test_a_full_charge_fired_from_far_ahead_reaches_the_turret_over_the_bow() -> void:
	var fortress := _fight(Fortress.HULL_FRONT + 100.0)
	var tank := world_tank()
	var muzzle := tank.model.muzzle.global_position
	tank.fire_cannon(muzzle, (fortress.module_at("turret") - muzzle).normalized(), 1.0)
	await frames(60)
	check(fortress.parts.turret < Fortress.MODULE_HP.turret, "a shell aimed from 100 m off the bow clears it and strikes the turret")


func test_a_shot_out_track_tears_off_and_slows_and_two_leave_it_stranded() -> void:
	var fortress := _fight(400.0)
	var node := fortress._nodes.track_l
	fortress.take_hit(_kill(fortress.module_at("track_l"), "track_l"))
	check_eq(fortress.parts.track_l, 0.0, "the left track is gone")
	check(node.get_parent() != fortress.model and node.get_parent() is Wreck, "it leaves the hull as a tumbling wreck")
	check(not fortress.aim_parts().has("track_l"), "and is no longer a target")
	_step(fortress, 6.0)
	var limp := fortress._speed
	check_near(limp, Fortress.DRIVE_SPEED * 0.55, 0.3, "one track left drives it at about half speed")
	check(fortress._sag.track_l > 0.99, "that side slumps")
	fortress.take_hit(_kill(fortress.module_at("track_r"), "track_r"))
	_step(fortress, 6.0)
	check_near(fortress._speed, 0.0, 0.01, "with both gone it sits where it is")
	var parked := fortress.global_position
	_step(fortress, 2.0)
	check(fortress.global_position.distance_to(parked) < 0.01, "it does not move at all")


func test_a_fortress_limping_on_one_track_stays_inside_the_clearing() -> void:
	for dead in ["track_l", "track_r"]:
		var fortress := _fight()
		fortress.take_hit(_kill(fortress.module_at(dead), dead))
		var nearest := INF
		for _i in 90:
			_place_tank(fortress, Fortress.HULL_FRONT + 50.0)
			_step(fortress, 1.0)
			nearest = minf(nearest, fortress._rim_gap())
		check(nearest >= Fortress.HULL_FRONT * 0.5, "with %s shot out its middle keeps %.0f m inside the rim" % [dead, nearest])


func test_gamepad_aim_assist_pulls_toward_a_module_not_the_armoured_hull() -> void:
	var fortress := _fight(260.0)
	var tank := world_tank()
	var camera := World.current.camera
	camera.global_position = tank.global_position + Vector3(0.0, 12.0, 17.0)
	camera.look_at(fortress.hit_center())
	tank.aim_screen = camera.unproject_position(fortress.hit_center())
	tank._aim_assist(1.0)
	var modules: Array = fortress.aim_parts().values().map(func(part: Array) -> Vector2: return camera.unproject_position(part[0]))
	var nearest: float = modules.map(func(at: Vector2) -> float: return at.distance_to(tank.aim_screen)).min()
	check(nearest < 1.0, "the sight settles %.1f px from the nearest module" % nearest)


func test_a_flame_gun_destroyed_cannot_burn_and_the_other_still_does() -> void:
	var fortress := _fight(Fortress.HULL_FRONT + 25.0)
	fortress._attack = Fortress.Attack.FLAME
	fortress._attack_time = Fortress.WIND
	fortress.take_hit(_kill(fortress.module_at("flame_l"), "flame_l"))
	check(fortress._jets.is_empty() and _flame_jets().is_empty(), "no jet is lit for a gun that was shot off")
	check_eq(fortress._flames_alive(), ["flame_r"] as Array[String], "one gun is left")
	fortress._attack = Fortress.Attack.FLAME
	fortress._attack_time = Fortress.WIND
	_step(fortress, 0.1)
	check_eq(_flame_jets().size(), 1, "the surviving gun burns alone")
	fortress.take_hit(_kill(fortress.module_at("flame_r"), "flame_r"))
	_step(fortress, 0.1)
	for _i in 4:
		fortress._attack = Fortress.Attack.NONE
		fortress._begin_attack(world_tank())
		check(fortress._attack != Fortress.Attack.FLAME, "with both guns gone it never picks the flame attack again")
		fortress._end_attack()


func test_the_flame_is_announced_before_it_burns_and_then_burns_the_tank() -> void:
	var fortress := _fight(Fortress.HULL_FRONT + 25.0)
	fortress._pattern = 1 # SALVO, then FLAME.
	fortress._next_attack = 0.0
	var burned := -1.0
	var hits := {"n": 0}
	world_tank().damaged.connect(func(_who: Entity, hit: Hit) -> void: hits.n += int(hit.kind == Hit.Kind.FIRE))
	var clock := 0.0
	var warned := -1.0
	for _i in roundi(8.0 / STEP):
		_step(fortress, STEP)
		clock += STEP
		if warned < 0.0 and fortress._attack == Fortress.Attack.FLAME and fortress.telegraphing():
			warned = clock
		if burned < 0.0 and hits.n > 0:
			burned = clock
	check(warned >= 0.0, "the guns wind up with the telegraph on")
	check(burned >= 0.0, "and the jets reach a tank 30 m in front of the bow")
	check(burned - warned >= Fortress.WIND * 0.95, "the first burn comes at least %.1f s after the warning (%.2f s)" % [Fortress.WIND, burned - warned])


func test_a_tank_caught_in_one_whole_flame_attack_keeps_most_of_its_hull() -> void:
	var fortress := _fight(Fortress.HULL_FRONT + 25.0)
	fortress.phase = 2
	fortress._pattern = 1
	fortress._next_attack = 0.0
	var tank := world_tank()
	var full := tank.hp
	var burns := {"n": 0}
	tank.damaged.connect(func(_who: Entity, hit: Hit) -> void: burns.n += int(hit.kind == Hit.Kind.FIRE))
	var at := fortress.global_position
	for _i in roundi(6.0 / STEP):
		fortress.global_position = at # Held still so only the flame reaches the tank.
		_step(fortress, STEP)
	check(burns.n >= 10, "the jets burn the tank throughout (%d burns)" % burns.n)
	check(tank.hp >= full * 0.6, "and leave %.0f of %.0f hull: one flame never decides the fight" % [tank.hp, full])


func test_once_lit_the_jets_hold_the_bearing_they_were_aimed_on_so_driving_aside_escapes_them() -> void:
	var fortress := _fight(Fortress.HULL_FRONT + 25.0)
	fortress._pattern = 1
	fortress._next_attack = 0.0
	var burns := {"n": 0}
	world_tank().damaged.connect(func(_who: Entity, hit: Hit) -> void: burns.n += int(hit.kind == Hit.Kind.FIRE and hit.source == fortress))
	var at := fortress.global_position
	while burns.n == 0 and fortress._attack_time < 3.0:
		fortress.global_position = at
		_step(fortress, STEP)
	check(burns.n > 0, "the jets first burn the tank where they were aimed")
	# The tank swerves 45 m aside, beyond the cone's half width there, and keeps going.
	_place_tank(fortress, Fortress.HULL_FRONT + 25.0, 45.0)
	var before: int = burns.n
	for _i in roundi(3.0 / STEP):
		fortress.global_position = at
		_step(fortress, STEP)
	check_eq(burns.n - before, 0, "the jets do not swing after it")


func test_the_flame_attack_ends_once_its_jets_burn_out() -> void:
	var fortress := _fight(Fortress.HULL_FRONT + 25.0)
	fortress._pattern = 1
	fortress._next_attack = 0.0
	var started := false
	var ended := false
	for _i in 140:
		_step(fortress, 0.1)
		await frames(1) # The burnt-out jets are freed between frames.
		started = started or fortress._attack == Fortress.Attack.FLAME
		if started and fortress._attack != Fortress.Attack.FLAME:
			ended = true
			break
	check(started and ended, "the flame attack runs and then returns the fortress to its idle pattern")


func test_a_hit_does_not_white_out_the_hull() -> void:
	var fortress := _fight()
	fortress.take_hit(_shell(fortress.module_at("turret"), 1.0))
	check(fortress._meshes.all(func(mesh: GeometryInstance3D) -> bool: return mesh.material_overlay == fortress.rest_overlay), "no mesh carries the white flash overlay")


func test_the_salvo_marks_every_shell_and_the_shells_can_be_shot_down() -> void:
	var fortress := _fight(Fortress.HULL_FRONT + 50.0)
	fortress._attack = Fortress.Attack.SALVO
	fortress._attack_time = 0.0
	_step(fortress, Fortress.WIND * 0.9)
	check(World.current._projectile_container.get_child_count() == 0, "no shell flies during the wind-up")
	_step(fortress, 0.2)
	var shells := World.current._projectile_container.get_children()
	check(shells.size() >= 1, "then the volley begins")
	check(shells.all(func(shell: Projectile) -> bool: return shell.interceptable), "every shell is interceptable")
	_step(fortress, 3.0)
	var all := World.current._projectile_container.get_children()
	check(all.size() == Fortress.SALVO_SHELLS[0], "the whole volley of %d is loosed (%d)" % [Fortress.SALVO_SHELLS[0], all.size()])
	check_eq(fortress._attack, Fortress.Attack.NONE, "and the attack ends after the last shell")


func test_the_charge_waits_for_its_lane_markers_then_floors_it() -> void:
	var fortress := _fight(Fortress.HULL_FRONT + 100.0)
	fortress._attack = Fortress.Attack.CRUSH
	fortress._attack_time = 0.0
	_step(fortress, Fortress.WIND * 0.9)
	check_near(fortress._speed, 0.0, 0.01, "it stands still while the lane is marked")
	_step(fortress, 1.6)
	check(fortress._speed > 10.0, "then it charges (%.1f m/s)" % fortress._speed)
	fortress.take_hit(_kill(fortress.module_at("track_l"), "track_l"))
	fortress._end_attack()
	fortress._begin_attack(world_tank())
	check(fortress._attack != Fortress.Attack.CRUSH, "with a track gone it cannot charge")


func test_a_burst_fuel_tank_rains_burning_ground_around_it() -> void:
	var fortress := _fight()
	var zones := _hostile_zones().size()
	fortress.take_hit(_kill(fortress.module_at("fuel_l"), "fuel_l"))
	check_eq(fortress.parts.fuel_l, 0.0, "the tank is gone")
	check(_hostile_zones().size() > zones, "it leaves fire on the ground")


func test_the_flame_gun_aims_on_its_own_pivot_apart_from_its_mount_and_the_turret() -> void:
	var fortress := _fight(Fortress.HULL_FRONT + 40.0)
	var gun: Node3D = fortress._guns.flame_r
	var base := gun.get_parent() as Node3D
	var base_basis := base.basis
	var turret_yaw := fortress._turret.rotation.y
	_place_tank(fortress, Fortress.HULL_FRONT + 25.0, -40.0)
	for _i in 60:
		fortress.aim_barrel(gun, world_tank().hit_center(), 3.0, STEP)
	check(absf(gun.rotation.y) > 0.3, "the gun swings toward a tank off to the side (%.2f rad)" % gun.rotation.y)
	check(base.basis.is_equal_approx(base_basis), "while its sponson mount stays fixed to the hull")
	check_eq(fortress._turret.rotation.y, turret_yaw, "and the turret ring is not turned by it")
	check(absf(fortress._barrel.rotation.y) < 0.01, "nor the barrel")


func test_a_tank_left_in_the_charges_lane_is_rammed_once_and_thrown_out_of_it() -> void:
	var fortress := _fight(Fortress.HULL_FRONT + 40.0)
	var tank := world_tank()
	var rams := {"n": 0}
	tank.damaged.connect(func(_who: Entity, hit: Hit) -> void: rams.n += int(hit.kind == Hit.Kind.RAM))
	fortress._attack = Fortress.Attack.CRUSH
	fortress._attack_time = 0.0
	for _i in roundi(6.0 / STEP):
		tank.invuln = 0.0
		fortress.behave(STEP)
	check(rams.n >= 1, "the charge reaches the tank")
	check_eq(rams.n, 1, "and rams it once, not again every second it stays pinned to the bow")


func test_the_hull_is_solid_and_throws_a_tank_off_it_for_a_hull_hit() -> void:
	var fortress := _fight()
	var tank := world_tank()
	_place_tank(fortress, -5.0, 10.0) # Inside the hull's footprint.
	var hp := tank.hp
	fortress._collide(tank, STEP)
	var local := Basis(Vector3.UP, fortress._yaw).inverse() * (tank.global_position - fortress.global_position)
	check(absf(local.x) >= Fortress.HULL_HALF + tank.radius - 0.01, "the tank is pushed out through the nearest flank (%.1f)" % local.x)
	check(tank.hp < hp, "and loses armor (%.0f)" % (hp - tank.hp))
	var again := tank.hp
	_place_tank(fortress, -5.0, 10.0)
	fortress._collide(tank, STEP)
	check_eq(tank.hp, again, "the next shove inside a second costs nothing more")


func test_the_fortress_goes_down_with_its_last_module_after_a_burning_death_throe() -> void:
	var fortress := _fight(150.0)
	for name: String in Fortress.MODULES:
		fortress.take_hit(_kill(fortress.module_at(name), name))
	check_eq(fortress.hp, 0.0, "every module is gone")
	check_eq(fortress._state, Fortress.State.DYING, "it starts dying")
	check(not fortress.dead, "but it does not vanish at once")
	_step(fortress, 3.5)
	check(fortress.dead or not is_instance_valid(fortress), "after the death throes it is destroyed")


func test_a_hull_shove_is_not_read_as_driving_speed() -> void:
	var fortress := _fight()
	var tank := world_tank()
	World.current.rail.mode = Rail.Mode.ARENA
	tank.tick(STEP)
	_place_tank(fortress, -5.0, 10.0)
	fortress._collide(tank, STEP)
	var thrown := tank.global_position.distance_to(fortress.global_position)
	check(thrown > Fortress.HULL_HALF, "the shove moved the tank clear of the hull (%.1f m)" % thrown)
	tank.tick(STEP)
	check(tank.velocity.length() < Tank.ARENA_SPEED + Fortress.HULL_SHOVE + 1.0, "the speed readout stays within what the tank and the shove can reach (%.0f km/h)" % (tank.velocity.length() * 3.6))


## The biggest fire or smoke particle a battered, burning body throws over one second.
func _biggest_puff(body: Enemy) -> float:
	var fx := World.current.fx
	var before := {}
	for kind in [Fx.Kind.GLOW, Fx.Kind.FLAME]:
		before[kind] = fx._pools[kind].duplicate()
	body.burning = 3.0
	for _i in 60:
		body._burn(STEP)
		body.show_damage(STEP, body.death_radius)
	var biggest := 0.0
	for kind in [Fx.Kind.GLOW, Fx.Kind.FLAME]:
		for p in fx._pools[kind]:
			if p not in before[kind]:
				biggest = maxf(biggest, maxf(p.size, p.end_size))
	return biggest


func test_a_battered_burning_fortress_smokes_no_bigger_than_an_ordinary_big_body() -> void:
	var fortress := _fight()
	fortress.hp = fortress.max_hp * 0.2
	var giant := _biggest_puff(fortress)
	fortress.death_radius = Entity.BODY_FX_MAX
	var ordinary := _biggest_puff(fortress)
	check(ordinary > 0.0, "a battered, burning body throws fire and smoke")
	check(giant <= ordinary + 0.01, "the 112 m hull throws no bigger fire or smoke than a body of the cap's size (%.1f m against %.1f m)" % [giant, ordinary])
