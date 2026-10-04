extends TestCase
## City hunters warn before firing, respect hard cover and lose attacks when their modules break.

const STEP := 1.0 / 60.0


func _setup(number := 1) -> World:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage("", true, number)
	await frames(2)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.player.velocity = Vector3.ZERO
	for prop: Prop in world.props.get_children():
		prop.dead = true
	world.rail.mode = Rail.Mode.HOLD
	return world


func _spawn(world: World, enemy: Enemy, ahead := 65.0) -> void:
	enemy.position = Course.ground_at(world.rail.d + world.player.course_offset + ahead, 0.0)
	world.add_enemy(enemy)
	var toward := world.player.global_position - enemy.global_position
	enemy.model.rotation.y = atan2(-toward.x, -toward.z)


func _run(enemy: Enemy, seconds: float) -> void:
	for _i in roundi(seconds / STEP):
		enemy.behave(STEP)


func _blocker(world: World, at: Vector3, hard := true) -> Prop:
	var prop := Prop.new()
	prop.setup("house", PropKit.mesh("house", 0), 5.0, 15.0, 10000.0)
	prop.hard = hard
	prop.position = at
	world.props.add_child(prop)
	return prop


func test_abel_lases_before_losat_and_spins_before_gatling() -> void:
	var world := await _setup()
	var abel := Abel.new()
	_spawn(world, abel)
	abel._attack_timer = 0.0
	abel.behave(STEP)
	check(abel.telegraphing(), "launcher starts with a laser wind-up")
	_run(abel, 0.85)
	check_eq(world.projectiles.size(), 0, "no LOSAT before the one-second warning finishes")
	_run(abel, 0.2)
	check_eq(world.projectiles.size(), 1, "one kinetic missile leaves after the warning")
	check(world.projectiles[0] is LosatMissile, "it uses accelerating kinetic flight")
	check(not abel.telegraphing(), "warning ends after launch")
	abel._attack_timer = 0.0
	abel.behave(STEP)
	var spin := abel._barrels.rotation.z
	_run(abel, 0.4)
	check(abel._barrels.rotation.z > spin, "gatling spins during its warning")
	check_eq(world.projectiles.size(), 1, "no tracer fires during spin-up")
	_run(abel, 1.0)
	check(world.projectiles.size() > 1, "the warned gatling fires visible tracers")


func test_losat_close_range_denies_kinetic_energy_even_head_on() -> void:
	var damage: Array[float] = []
	for distance in [15.0, 24.0, 85.0, 110.0]:
		var world := await _setup()
		var tank := world.player
		var observed: Array[float] = []
		tank.damaged.connect(func(_entity: Entity, hit: Hit) -> void: observed.append(hit.damage))
		var missile := LosatMissile.new()
		missile.position = tank.hit_center() - tank.global_basis.z * distance
		missile.velocity = (tank.hit_center() - missile.position).normalized() * LosatMissile.LAUNCH_SPEED
		world.add_child(missile)
		for _i in 480:
			if missile.is_queued_for_deletion():
				break
			missile.step(1.0 / 240.0)
		check(not observed.is_empty(), "a dart at %.0f m strikes the tank" % distance)
		damage.append(observed[0] if not observed.is_empty() else 0.0)
	check(damage[0] < 10.0 and damage[1] < 10.0, "inside 25 m the unboosted dart barely hurts")
	check(damage[2] > damage[1] * 10.0, "at 85 m it carries over ten times the close-range energy")
	check(damage[3] > damage[2], "acceleration still raises striking energy past 85 m")


func test_losat_ciws_only_engages_inside_nine_metres() -> void:
	var world := await _setup()
	var tank := world.player
	var missile := LosatMissile.new()
	missile.position = tank.global_position + Vector3(0, 2, -20)
	missile.velocity = Vector3.BACK * 300.0
	world.add_child(missile)
	check(tank._ciws_pick_target() != missile, "the usual CIWS envelope cannot lock a distant LOSAT")
	var hp := missile.intercept_hp
	check(not missile.laser(10.0), "a distant dart rejects laser damage")
	check_eq(missile.intercept_hp, hp, "distant laser damage cannot bypass the close-range gate")
	missile.global_position = tank.global_position + Vector3(0, 2, -7)
	missile._update_interception()
	check(tank._ciws_pick_target() == missile, "the dart becomes a CIWS target at very short range")
	tank._update_ciws(STEP)
	check(missile.is_queued_for_deletion(), "one brief dwell zaps it inside the short envelope")


func test_hunters_seek_hard_cover_then_peek_and_relocate() -> void:
	var world := await _setup()
	var abel := Abel.new()
	_spawn(world, abel, 85.0)
	abel._attack_timer = INF
	var tank := world.player
	var prop := _blocker(world, tank.global_position + Vector3(8, 0, -65))
	check(abel.seek_cover(tank), "a tall hard building is useful cover")
	var cover_goal := abel._cover_goal
	check(BipedMech.line_blocked(tank.hit_center(), cover_goal + Vector3.UP * abel.center_height), "the chosen hiding point actually breaks tank LOS")
	for _i in 600:
		abel.behave(STEP)
		if abel.global_position.distance_to(cover_goal) < 1.0:
			break
	check(abel.global_position.distance_to(cover_goal) < 1.0, "the hunter reaches cover rather than walking through the building")
	check(BipedMech.line_blocked(tank.hit_center(), abel.hit_center()), "its actual hiding position breaks LOS")
	_run(abel, 4.0)
	check(abel._peek, "after sheltering it moves to a firing edge")
	check(not BipedMech.line_blocked(tank.hit_center(), abel.hit_center()), "the peek position restores LOS: at %s, goal %s, building %s" % [abel.global_position, abel._cover_goal, prop.global_position])
	var side := abel._side
	abel._attack_timer = 0.0
	_run(abel, 1.1)
	check_eq(abel._side, side, "one volley is followed by a second from the same edge")
	abel._attack_timer = 0.0
	_run(abel, 2.4)
	check_eq(abel._side, -side, "two completed volleys pick the other edge for relocation")
	prop.dead = true
	check(not BipedMech.line_blocked(tank.hit_center(), cover_goal + Vector3.UP * abel.center_height), "a destroyed blocker no longer conceals the hunter")


func test_a_hunter_that_peeks_out_fires_before_it_ducks_away() -> void:
	for kind: GDScript in [Abel, Kain]:
		var world := await _setup()
		var hunter: BipedMech = kind.new()
		_spawn(world, hunter, 85.0)
		var tank := world.player
		_blocker(world, tank.global_position + Vector3(8, 0, -65))
		check(hunter.seek_cover(tank), "a tall hard building is useful cover")
		var warned := false
		for _i in 60 * 14:
			hunter.behave(STEP)
			if hunter.telegraphing():
				warned = true
				break
		check(warned, "%s winds up an attack from behind its cover within 14 s" % kind.get_global_name())


func test_light_props_do_not_hide_hunters_and_cover_cancels_fire() -> void:
	var world := await _setup()
	var abel := Abel.new()
	_spawn(world, abel)
	var middle := world.player.global_position.lerp(abel.global_position, 0.5)
	var prop := _blocker(world, middle, false)
	check(not abel.seek_cover(world.player), "light scenery is not cover")
	abel._attack_timer = 0.0
	abel.behave(STEP)
	check(abel.telegraphing(), "clear LOS permits a warning")
	prop.hard = true
	_run(abel, 1.1)
	check(not abel.telegraphing(), "a blocker appearing cancels the laser")
	check_eq(world.projectiles.size(), 0, "no dart fires through hard scenery")


func test_kain_warns_then_lobs_a_shell_at_its_marked_patch() -> void:
	var world := await _setup()
	var kain := Kain.new()
	_spawn(world, kain)
	kain._attack_timer = 0.0
	kain.behave(STEP)
	var aim := kain._aim
	var pitch := kain._gun.rotation.x
	_run(kain, 0.85)
	check(kain.telegraphing(), "impact circle precedes the heavy shell")
	check_eq(world.projectiles.size(), 0, "nothing fires during the marked wind-up")
	check(absf(kain._gun.rotation.x - pitch) > 0.05, "the muzzle visibly swivels onto its arc")
	_run(kain, 0.2)
	check_eq(world.projectiles.size(), 1, "the warned gun launches one shell")
	if world.projectiles.is_empty():
		return
	var shell := world.projectiles[0]
	check(shell.gravity > 0.0 and shell.velocity.y > 0.0, "the slow shell arcs above the street")
	var landing := shell.global_position + shell.velocity * kain._flight - Vector3.UP * Kain.GRAVITY * kain._flight * kain._flight * 0.5
	check(landing.distance_to(aim) < 0.1, "the trajectory ends at the warned patch")
	check(shell.blast_radius >= 5.0 and shell.hit.caliber == 100, "it carries a broad 100 mm blast")
	var hp := world.player.hp
	var contact: Array = []
	shell.impacted.connect(func(_shot: Projectile, at: Vector3, target: Entity) -> void: contact.assign([at, target]))
	land(world, 0)
	check(world.player.hp < hp, "the shell actually bursts and hurts a tank that stayed in the marked patch: contact %s, tank %s, invuln %.2f" % [contact, world.player.global_position, world.player.invuln])


func test_kain_front_protects_turret_not_rear_or_legs() -> void:
	var world := await _setup()
	var kain := Kain.new()
	_spawn(world, kain)
	var hit := Hit.make(Hit.Kind.SHELL, 100.0, kain.hit_center(), kain._turret.global_basis.z)
	var front := kain.damage_multiplier(hit)
	hit.direction = -hit.direction
	check(kain.damage_multiplier(hit) > front * 2.0, "turret rear is much weaker than the front")
	hit.position = kain.global_position + Vector3.UP
	check(kain.damage_multiplier(hit) > front * 2.0, "turret armor does not protect the legs")


func test_leg_hits_topple_all_three_and_cancel_attacks() -> void:
	for kind in ["abel", "kain", "adam"]:
		var world := await _setup()
		var mech: BipedMech = load(Director.ENEMY_SCRIPTS[kind]).new()
		_spawn(world, mech, 6.0 if kind == "adam" else 60.0)
		mech.set("_attack_timer", 0.0)
		mech.behave(STEP)
		check(mech.telegraphing(), "%s has a pending attack" % kind)
		var point := mech._legs[0].to_global(Vector3(0, -2.0, -0.25))
		check(mech.hit_test(point + Vector3(0, 0, 3), point - Vector3(0, 0, 3)) >= 0.0, "%s low legs can actually be shot" % kind)
		mech.take_hit(Hit.make(Hit.Kind.SHELL, 40.0, point))
		check(mech.toppled, "%s collapses on a leg hit" % kind)
		check(not mech.telegraphing(), "%s collapse cancels the pending attack" % kind)
		var at := mech.global_position
		_run(mech, 2.0)
		check_eq(world.projectiles.size(), 0, "%s never fires after losing its legs" % kind)
		check_eq(mech.global_position, at, "%s stays toppled" % kind)


func test_launcher_and_hoses_are_shootable_counters() -> void:
	var world := await _setup()
	var abel := Abel.new()
	_spawn(world, abel)
	abel._attack_timer = 0.0
	abel.behave(STEP)
	var tube := abel._launcher.global_position
	check(abel.hit_test(tube + Vector3(0, 0, 4), tube - Vector3(0, 0, 4)) >= 0.0, "the outboard launcher has a hit volume")
	abel.take_hit(Hit.make(Hit.Kind.SHELL, 60.0, tube))
	check(abel.disarmed and not abel.telegraphing(), "breaking tubes interrupts LOSAT")
	_run(abel, 6.0)
	check(world.projectiles.all(func(p: Projectile) -> bool: return not p is LosatMissile), "a broken launcher never launches a dart")
	var adam := Adam.new()
	_spawn(world, adam, 6.0)
	adam._attack_timer = 0.0
	adam.behave(STEP)
	var hose := adam._hose.global_position
	var hit := Hit.make(Hit.Kind.SHELL, 15.0, hose)
	check(adam.damage_multiplier(hit) >= 3.0, "hose bundle is a weak point")
	check(adam.hit_test(hose + Vector3(0, 0, 4), hose - Vector3(0, 0, 4)) >= 0.0, "the exposed hoses can actually be shot")
	adam.take_hit(hit)
	check(adam.disarmed and not adam.telegraphing(), "a severed hose cancels the breaker")


func test_adam_warns_slams_shoves_and_sweeps_next() -> void:
	var world := await _setup()
	var adam := Adam.new()
	_spawn(world, adam, 6.0)
	adam._attack_timer = 0.0
	var tank := world.player
	var hp := tank.hp
	adam.behave(STEP)
	_run(adam, 0.7)
	check(adam.telegraphing(), "breaker rears over its impact circle")
	check_eq(tank.hp, hp, "no damage before the slam")
	_run(adam, 0.25)
	check(tank.hp < hp, "the warned slam hurts a tank still in the patch")
	check(absf(tank.local_velocity.x) >= 14.0, "the breaker shoves the tank sideways")
	_run(adam, 0.5)
	adam._attack_timer = 0.0
	adam.behave(STEP)
	check(not adam._breaker and adam.telegraphing(), "the next attack winds up the carried I-beam")
	var yaw := adam._beam.rotation.y
	_run(adam, 0.8)
	check(absf(adam._beam.rotation.y - yaw) > 0.2, "the beam visibly draws back before sweeping")


func test_adam_slam_can_be_dodged_or_interrupted_and_respects_height() -> void:
	for counter in ["dodge", "stagger", "height"]:
		var world := await _setup()
		var adam := Adam.new()
		_spawn(world, adam, 6.0)
		adam._attack_timer = 0.0
		adam.behave(STEP)
		var tank := world.player
		var hp := tank.hp
		if counter == "dodge":
			tank.global_position.x += Adam.SLAM_RADIUS + 1.0
		elif counter == "height":
			tank.global_position.y += 8.0
		else:
			adam.interrupt()
		_run(adam, 1.0)
		check_eq(tank.hp, hp, "%s denies breaker damage" % counter)
		check_eq(tank.local_velocity.x, 0.0, "%s also denies the shove" % counter)


func test_adam_bodyguards_an_ally_on_the_tank_facing_side() -> void:
	var world := await _setup()
	var adam := Adam.new()
	var kain := Kain.new()
	_spawn(world, adam, 30.0)
	_spawn(world, kain, 45.0)
	var goal := adam.guard_spot(world.player)
	check(goal.distance_to(world.player.global_position) < kain.global_position.distance_to(world.player.global_position), "Adam guards in front of the gun carrier")
	_run(adam, 3.0)
	var line := Geometry3D.get_closest_point_to_segment(adam.hit_center(), world.player.hit_center(), kain.hit_center())
	check(adam.hit_center().distance_to(line) < adam.radius, "its broad hull physically intersects the tank-to-ally firing lane")


func test_director_formations_and_feet_follow_elevated_ground() -> void:
	var world := await _setup()
	world.rail.d = 3080.0 - world.player.course_offset
	for kind in ["abel", "kain", "adam"]:
		check(Director.DUEL.has(kind) and Director.duel_counts.has(kind), "%s participates in duel formations" % kind)
		var spawned := world.director.spawn_wave({"kind": kind, "formation": "line", "ahead": 0.0, "count": 1, "u": 0.0})
		var mech := spawned[0]
		check(mech.global_position.y > 5.0, "%s starts on an elevated road, not at world zero" % kind)
		mech.behave(STEP)
		check_near(mech.global_position.y, Course.height_at(mech.global_position), 0.01, "%s follows the height at its new position" % kind)


func test_real_shots_can_break_outboard_tubes_and_hoses() -> void:
	for kind in ["abel", "adam"]:
		var world := await _setup()
		var mech: BipedMech = load(Director.ENEMY_SCRIPTS[kind]).new()
		_spawn(world, mech)
		var parts := mech.aim_parts()
		var point: Vector3 = parts.values()[0][0]
		var shot := world.spawn_projectile(Entity.Team.PLAYER, point - mech.model.global_basis.z * 6.0, mech.model.global_basis.z * 200.0, "shell")
		shot.hit = Hit.make(Hit.Kind.SHELL, 60.0, shot.global_position)
		shot.hit.source = world.player
		shot.hit.caliber = 100
		land(world, 0)
		check(mech.get("disarmed"), "%s module, not the nearby hull, takes an actual swept shell" % kind)


func test_boosted_losat_can_be_zapped_during_real_flight() -> void:
	var world := await _setup()
	var tank := world.player
	var missile := LosatMissile.new()
	missile.position = tank.hit_center() + Vector3(0, 0, -12)
	missile.velocity = Vector3.BACK * 650.0
	missile._traveled = 80.0
	world.add_child(missile)
	check(tank._ciws_pick_target() != missile, "even a boosted dart cannot be picked at 12 m")
	missile.step(1.0 / 120.0)
	check(not missile.is_queued_for_deletion(), "it is still in flight as it enters the short defensive bubble")
	tank._update_ciws(STEP)
	check(missile.is_queued_for_deletion(), "CIWS can zap a boosted dart in the remaining short flight window")


func test_adam_beam_hits_front_but_not_behind_or_out_of_reach() -> void:
	for offset in [Vector3(0, 0, -10), Vector3(0, 0, 10), Vector3(0, 0, -15)]:
		var world := await _setup()
		var adam := Adam.new()
		_spawn(world, adam)
		adam.model.rotation.y = 0.0
		adam._breaker = false
		world.player.global_position = adam.global_position + offset
		var hp := world.player.hp
		adam._land_attack(world.player)
		check_eq(world.player.hp < hp, offset.z == -10.0, "I-beam only lands inside its forward sweep at %s" % offset)


func test_tail_stab_interrupts_city_hunters() -> void:
	for kind in ["abel", "kain", "adam"]:
		var world := await _setup()
		var mech: BipedMech = load(Director.ENEMY_SCRIPTS[kind]).new()
		_spawn(world, mech, 6.0 if kind == "adam" else 60.0)
		mech.set("_attack_timer", 0.0)
		mech.behave(STEP)
		check(mech.telegraphing(), "%s is winding up before the stab" % kind)
		world.player._grab_target = mech
		world.player.tail.state = Tail.State.STAB
		world.player._on_tail_arrived()
		check(not mech.telegraphing() and mech.is_staggered(), "%s tail counter immediately stops the warning" % kind)
		_run(mech, 1.0)
		check_eq(world.projectiles.size(), 0, "%s interrupted weapon cannot fire" % kind)


func test_hard_mode_adds_aggression_without_damage_sponging() -> void:
	var volleys: Array[int] = []
	for difficulty in [Game.Difficulty.NORMAL, Game.Difficulty.HARD]:
		var world := await _setup()
		Game.difficulty = difficulty
		var abel := Abel.new()
		_spawn(world, abel)
		abel._losat = false
		abel._attack_timer = 0.0
		_run(abel, 1.8)
		volleys.append(world.projectiles.size())
	check(volleys[1] > volleys[0], "hard-mode gatling delivers a denser warned burst")
	Game.difficulty = Game.Difficulty.NORMAL


func test_abel_one_charge_or_two_quick_shells() -> void:
	for shots in [1, 2]:
		var world := await _setup()
		var abel := Abel.new()
		_spawn(world, abel)
		for i in shots:
			var damage := Armament.SHELL_DAMAGE * Armament.APHE_DAMAGE.y if shots == 1 else Armament.QUICK_DAMAGE.x
			var hit := Hit.make(Hit.Kind.SHELL, damage * Armament.SHELL_DAMAGE_SCALE, abel.hit_center())
			hit.caliber = 100
			hit.source = world.player
			abel.take_hit(hit)
			if shots == 2 and i == 0:
				check(not abel.dead, "one quick hull hit leaves an elite hunter alive")
		check(abel.dead, "%d main-gun hit(s) defeats Abel" % shots)
