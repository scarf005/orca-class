extends TestCase
## Small arms glance off the armor but break exposed sensors; the FCS and what it does.


## A small-arms hit as an enemy gun lands it: fired from `from` at the hull's middle plus a random
## offset of up to `spread`, stopped where it first touches the hull's hit sphere. Null if it misses.
func _shot(tank: Tank, from: Vector3, spread: Vector3, caliber := 30) -> Hit:
	var aim := tank.hit_center() + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread
	var direction := (aim - from).normalized()
	var t := tank.hit_test(from, from + direction * 200.0, 0.0)
	if t < 0.0:
		return null
	var hit := Hit.make(Hit.Kind.BULLET, 4.0, from + direction * t, direction)
	hit.caliber = caliber
	return hit


## A gunner the way the stage has them, ahead of the tank: UGV, walker, quad mech or helicopter.
## Returns [muzzle, offset spread] as those enemies aim (see their fire_at calls).
func _gunner(tank: Tank) -> Array:
	var at := tank.global_position - tank.global_basis.z * randf_range(35.0, 100.0) + tank.global_basis.x * randf_range(-25.0, 25.0)
	match randi() % 4:
		0: return [at + Vector3.UP * 2.2, Vector3(1.5, 0.75, 1.5)]
		1: return [at + Vector3.UP * 3.0, Vector3(1.2, 0.55, 1.2)]
		2: return [at + Vector3.UP * 2.5, Vector3(2.0, 1.0, 2.0)]
	return [at + Vector3.UP * randf_range(8.0, 22.0), Vector3(1.0, 0.5, 1.0)]


## A hit landing on the hull sphere in the direction of `toward` from its middle.
func _strike(tank: Tank, toward: Vector3, caliber := 30) -> Hit:
	var direction := toward.normalized()
	var hit := Hit.make(Hit.Kind.BULLET, 4.0, tank.hit_center() + direction * tank.radius, -direction)
	hit.caliber = caliber
	return hit


func test_small_arms_share_on_sensors_matches_enemy_spread() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	seed(7)
	var reached := 0
	var on_sensors := 0
	for i in 4000:
		var gunner := _gunner(tank)
		var hit := _shot(tank, gunner[0], gunner[1])
		if hit == null:
			continue
		reached += 1
		on_sensors += 0 if tank.struck_sensor(hit).is_empty() else 1
	var share := float(on_sensors) / maxf(reached, 1.0)
	check(reached > 1000, "most shots reach the hull (%d)" % reached)
	check(share >= 0.10 and share <= 0.20, "10-20%% of small arms that reach the tank land on the FCS or RWS (%.3f)" % share)


func test_small_arms_leave_the_hull_untouched() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var flashes := [0]
	var hp := tank.hp
	var style := world.stats.style
	tank.damaged.connect(func(_e: Entity, _h: Hit) -> void: flashes[0] += 1)
	for caliber in [8, 15, 23, 30, 39]:
		tank.take_hit(_strike(tank, -tank.global_basis.z, caliber))
	check_eq(tank.hp, hp, "no hull damage")
	check_eq(world.stats.damage_taken, 0.0, "no damage taken for stats")
	check_eq(world.stats.style, style, "no style lost")
	check_eq(flashes[0], 0, "no damage signal: no screen flash or shake")
	check_eq(tank.invuln, 0.0, "and no grace period started")


func test_forty_millimeters_and_blasts_still_hurt() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var hp := tank.hp
	tank.take_hit(_strike(tank, tank.global_basis.z, 40))
	check(tank.hp < hp, "a 40 mm round hurts the hull")
	check(world.stats.damage_taken > 0.0, "and counts as damage taken")
	tank.invuln = 0.0
	hp = tank.hp
	tank.take_hit(Hit.make(Hit.Kind.BLAST, 10.0, tank.hit_center(), Vector3.FORWARD))
	check(tank.hp < hp, "a blast hurts the hull")
	tank.invuln = 0.0
	hp = tank.hp
	var shell := Hit.make(Hit.Kind.SHELL, 10.0, tank.hit_center(), Vector3.FORWARD)
	shell.caliber = 30
	tank.take_hit(shell)
	check(tank.hp < hp, "a shell of any caliber hurts the hull")


func test_small_arms_break_the_sensor_they_strike() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var toward := func(name: String) -> Vector3: return tank.model.sensor_position(name) - tank.hit_center()
	tank.take_hit(_strike(tank, toward.call("laser"), 15))
	check(tank.modules.hp.laser < TankModules.MAX.laser, "a round on the RWS damages it")
	check_eq(tank.modules.hp.fcs, TankModules.MAX.fcs, "and only it")
	tank.take_hit(_strike(tank, toward.call("fcs"), 15))
	check(tank.modules.hp.fcs < TankModules.MAX.fcs, "a round on the FCS damages it")
	check_near(tank.modules.hp.fcs, TankModules.MAX.fcs - 4.0, 0.01, "for the hit's own damage")
	var hp := tank.hp
	var laser := float(tank.modules.hp.laser)
	var fcs := float(tank.modules.hp.fcs)
	tank.take_hit(_strike(tank, -tank.global_basis.z + Vector3.DOWN * 0.3, 15))
	check_eq(tank.hp, hp, "the hull's middle takes nothing")
	check_eq(tank.modules.hp.laser, laser, "and the RWS is spared")
	check_eq(tank.modules.hp.fcs, fcs, "and the FCS is spared")
	tank.invuln = 0.5
	tank.take_hit(_strike(tank, toward.call("fcs"), 15))
	check_eq(tank.modules.hp.fcs, fcs, "no sensor breaks under respawn or dash cover")


func test_a_missing_rws_cannot_be_shot_again() -> void:
	var world := stage("", false)
	var tank := world.player
	await frames(2)
	var wrecks := world.get_children().filter(func(n: Node) -> bool: return n is Wreck).size()
	tank.take_hit(_strike(tank, tank.model.sensor_position("laser") - tank.hit_center(), 15))
	check_eq(tank.modules.hp.laser, 0.0, "nothing to hit up there")
	check_eq(world.get_children().filter(func(n: Node) -> bool: return n is Wreck).size(), wrecks, "nothing flies off")


func test_a_shot_off_fcs_flies_away_and_only_a_repair_restores_it() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var wrecks := func() -> int: return world.get_children().filter(func(n: Node) -> bool: return n is Wreck).size()
	var before: int = wrecks.call()
	tank.damage_module("fcs", 20.0)
	check_eq(tank.modules.state("fcs"), TankModules.State.DAMAGED, "damaged first")
	check(tank.model.fcs.visible, "the sight is still on the roof")
	tank.damage_module("fcs", 999.0)
	check_eq(tank.modules.state("fcs"), TankModules.State.DESTROYED, "then destroyed")
	check_eq(wrecks.call(), before + 1, "it flies off as a burning piece")
	check(not tank.model.fcs.visible, "and the roof is bare")
	await frames(1)
	check(not tank.model.fcs.visible, "it stays off")
	tank.modules.update(TankModules.REPAIR_TIME * 4.0)
	check_eq(tank.modules.state("fcs"), TankModules.State.DESTROYED, "the crew cannot rebuild it in the field")
	tank.collect(world.spawn_pickup("repair", tank.global_position + Vector3.UP))
	check_eq(tank.modules.state("fcs"), TankModules.State.OK, "a repair pickup does")
	await frames(1)
	check(tank.model.fcs.visible, "and the sight is back")


func test_a_damaged_fcs_is_field_repaired() -> void:
	var world := stage()
	var tank := world.player
	tank.damage_module("fcs", 20.0)
	tank.modules.update(TankModules.REPAIR_TIME + 0.1)
	check_eq(tank.modules.state("fcs"), TankModules.State.OK, "a hurt sight mends itself")


func test_damaged_fcs_halves_the_lock_and_drops_the_lead() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var ugv := Ugv.new()
	ugv.position = Course.ground_at(world.rail.d + 60.0, 0.0)
	world.add_enemy(ugv)
	ugv.track_velocity = Vector3(10.0, 0.0, 0.0)
	var from := tank.model.muzzle.global_position
	var led := tank.lead_point(from, 100.0, ugv)
	check(led.distance_to(ugv.hit_center()) > 1.0, "a whole FCS leads a moving target")
	check_eq(tank.modules.lock_factor(), 1.0, "and locks at the full radius")
	tank.damage_module("fcs", 20.0)
	check_eq(tank.modules.lock_factor(), 0.5, "damaged, the soft-lock radius halves")
	check(tank.lead_point(from, 100.0, ugv).is_equal_approx(ugv.hit_center()), "and rounds go at the lock center, no lead")
	var spot := ugv.hit_center() + Vector3(0, 1.0, 0)
	check(tank.lead_point(from, 100.0, ugv, spot).is_equal_approx(spot), "or the aimed spot")


func test_soft_lock_reaches_only_half_as_far_when_the_fcs_is_damaged() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var ugv := Ugv.new()
	ugv.position = Course.ground_at(world.rail.d + 60.0, 0.0)
	world.add_enemy(ugv)
	ugv.invulnerable = true
	await frames(2)
	var screen := world.camera.unproject_position(ugv.hit_center())
	tank.aim_target = null
	tank.aim_screen = screen + Vector2(Tank.SOFT_LOCK_RADIUS * 0.75, 0)
	check(tank._pick_coax_target() == ugv, "inside the full radius it locks")
	tank.damage_module("fcs", 20.0)
	check(tank._pick_coax_target() == null, "the same offset is outside a halved radius")
	tank.aim_screen = screen + Vector2(Tank.SOFT_LOCK_RADIUS * 0.4, 0)
	check(tank._pick_coax_target() == ugv, "but a closer one still locks")


func test_soft_lock_reaches_forty_pixels_and_no_further() -> void:
	var world := stage()
	var tank := world.player
	var ugv := Ugv.new()
	ugv.position = Course.ground_at(world.rail.d + 60.0, 0.0)
	world.add_enemy(ugv)
	ugv.invulnerable = true
	await frames(2)
	var screen := world.camera.unproject_position(ugv.hit_center())
	tank.aim_target = null
	tank.aim_screen = screen + Vector2(39.0, 0)
	check(tank._pick_coax_target() == ugv, "39 px off the target still locks")
	tank.coax_target = null # A held lock would linger past the radius.
	tank.aim_screen = screen + Vector2(41.0, 0)
	check(tank._pick_coax_target() == null, "41 px off does not")


func test_destroyed_fcs_disables_lock_and_lead() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var ugv := Ugv.new()
	ugv.position = Course.ground_at(world.rail.d + 60.0, 0.0)
	world.add_enemy(ugv)
	ugv.track_velocity = Vector3(12.0, 0.0, 0.0)
	ugv.invulnerable = true
	await frames(2)
	tank.aim_target = ugv
	tank.aim_point = ugv.hit_center()
	check(tank._pick_coax_target() == ugv, "a whole FCS locks the enemy under the reticle")
	var from := tank.model.muzzle.global_position
	var lead := tank._fire_direction(from, 100.0)
	tank.damage_module("fcs", 999.0)
	check(tank._pick_coax_target() == null, "with no sight nothing is locked, even under the reticle")
	tank.aim_point = ugv.hit_center() + Vector3(0, 4.0, 0)
	var straight := Tank.along_barrel(-tank.model.barrel.global_basis.z, (tank.aim_point - from).normalized())
	check(tank._fire_direction(from, 100.0).is_equal_approx(straight), "the guns fire at the aim point")
	check(not lead.is_equal_approx(straight), "which is not where a led round went")
	tank._update_weapons(0.016)
	check(tank.coax_target == null and tank.coax_part.is_empty(), "the weapons track nothing")


## A shooter's muzzle for a gun firing down on the roof: a helicopter on station (55 m out, 10-15 m up)
## or a UAV on a strafing pass (17 m up, 15-80 m out).
func _from_above(tank: Tank, helicopter: bool) -> Vector3:
	var out := randf_range(50.0, 65.0) if helicopter else randf_range(15.0, 80.0)
	var up := randf_range(10.0, 15.0) if helicopter else 17.0
	return tank.global_position - tank.global_basis.z * out + tank.global_basis.x * randf_range(-15.0, 15.0) + Vector3.UP * up


func test_guns_firing_down_on_the_roof_hurt() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	seed(3)
	for helicopter in [true, false]:
		var hurt := 0
		var tries := 0
		for i in 60:
			var hit := _shot(tank, _from_above(tank, helicopter), Vector3(1.0, 0.5, 1.0), 30 if helicopter else 23)
			if hit == null:
				continue
			tries += 1
			tank.invuln = 0.0
			tank.hp = Tank.MAX_ARMOR
			var hp := tank.hp
			tank.take_hit(hit)
			hurt += 1 if tank.hp < hp else 0
			check_eq(tank.facing_of(hit), "top", "a shot from a %s comes down on the roof" % ("helicopter" if helicopter else "UAV"))
		check(tries > 40 and hurt == tries, "every roof hit hurts (%d of %d)" % [hurt, tries])


func test_roof_hits_are_weak_and_reach_the_top_modules() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	seed(6)
	var hit := _strike(tank, Vector3(0.2, 1.0, 0.1), 30)
	check_near(tank.damage_multiplier(hit), 1.4, 0.001, "the roof is as weak as the rear")
	var struck := {}
	for i in 60:
		tank.invuln = 0.0
		tank.hp = Tank.MAX_ARMOR
		for name in TankModules.MAX:
			tank.modules.hp[name] = TankModules.MAX[name]
		tank.take_hit(_strike(tank, Vector3(0.2, 1.0, 0.1), 30))
		for name in TankModules.MAX:
			if tank.modules.hp[name] < TankModules.MAX[name]:
				struck[name] = true
	for name in ["turret", "engine", "fcs", "laser"]:
		check(struck.has(name), "the roof reaches the %s" % name)
	for name in ["track_l", "track_r", "breech"]:
		check(not struck.has(name), "but not the %s" % name)


func test_ground_gunners_still_glance_off() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	seed(4)
	var reached := 0
	for i in 200:
		var gunner := _gunner(tank)
		if gunner[0].y - tank.global_position.y > 6.0:
			continue
		var hit := _shot(tank, gunner[0], gunner[1], 30)
		if hit == null:
			continue
		reached += 1
		tank.invuln = 0.0
		var hp := tank.hp
		tank.take_hit(hit)
		check_eq(tank.hp, hp, "a 30 mm round from the ground glances off")
	check(reached > 40, "enough ground shots landed (%d)" % reached)


func test_light_rounds_from_above_still_glance_off() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	seed(5)
	for caliber in [8, 15, 19]:
		var landed := 0
		for i in 20:
			var hit := _shot(tank, _from_above(tank, true), Vector3(1.0, 0.5, 1.0), caliber)
			if hit == null:
				continue
			landed += 1
			tank.invuln = 0.0
			var hp := tank.hp
			tank.take_hit(hit)
			check_eq(tank.hp, hp, "a %d mm round from above glances off" % caliber)
		check(landed >= 10, "enough %d mm roof attempts landed (%d)" % [caliber, landed])


func test_the_roof_rule_is_for_bullets_only() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var blast := Hit.make(Hit.Kind.BLAST, 10.0, tank.hit_center(), Vector3.DOWN)
	check(tank.facing_of(blast) != "top", "a blast from above keeps its horizontal facing")
	var shell := Hit.make(Hit.Kind.SHELL, 10.0, tank.hit_center(), Vector3.DOWN)
	check(tank.facing_of(shell) != "top", "so does a shell")
	var horizontal := _strike(tank, tank.global_basis.x, 30)
	check(tank.facing_of(horizontal) != "top", "a level bullet is no roof hit")
	var shallow := _strike(tank, Vector3(1.0, 0.09, 0.0), 30)
	check(tank.facing_of(shallow) != "top", "a 5 degree descent is no roof hit")


## Deliver a real round: glances tumble the projectile, not a separate FX tracer.
func _round(world: World, target: Entity, hit: Hit) -> Projectile:
	var round := world.spawn_projectile(Entity.Team.ENEMY if target is Tank else Entity.Team.PLAYER, hit.position, hit.direction * 100.0, "bullet")
	round.hit = hit
	round.interceptable = true
	round.detonate(hit.position, target)
	return round


func test_a_glancing_round_leaves_one_harmless_tracer() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	seed(6)
	for side in [-tank.global_basis.z, tank.global_basis.x, -tank.global_basis.x]:
		var hit := _strike(tank, side, 15)
		var hp := tank.hp
		var shots := world.projectiles.size()
		var round := _round(world, tank, hit)
		check_eq(world.projectiles.size(), shots + 1, "the same round tumbles, with no duplicate projectile")
		check(round._glanced and not round.is_queued_for_deletion(), "the glanced round remains visible")
		check(not round.interceptable, "it is no longer a CIWS target")
		var normal := (hit.position - tank.hit_center()).normalized()
		check(round.velocity.normalized().dot(normal) > 0.1, "it leaves the armor")
		check(round.velocity.length() >= 85.0 and round.velocity.length() <= 110.0, "at nearly its incoming speed")
		check_eq(tank.hp, hp, "the glance does no damage")
		var victim := Ugv.new()
		victim.position = round.global_position + round.velocity.normalized() * 2.0
		world.add_enemy(victim)
		var victim_hp := victim.hp
		for _i in 40:
			if round.is_queued_for_deletion():
				break
			round.step(1.0 / 60.0)
		check_eq(victim.hp, victim_hp, "a tumbling round no longer collides or damages")
		check(round.is_queued_for_deletion(), "it expires within 0.6 seconds")


func test_glancing_tracers_scatter_and_a_damaging_hit_leaves_none() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	seed(8)
	var directions := []
	for i in 6:
		var round := _round(world, tank, _strike(tank, -tank.global_basis.z, 15))
		directions.append(round.velocity.normalized())
	check(directions.any(func(d: Vector3) -> bool: return d.distance_to(directions[0]) > 0.05), "the scatter varies from shot to shot")
	for hit in [_strike(tank, tank.global_basis.z, 40), _strike(tank, Vector3(0.2, 1.0, 0.1), 30)]:
		tank.invuln = 0.0
		var hp := tank.hp
		var round := _round(world, tank, hit)
		check(not round._glanced and round.is_queued_for_deletion(), "a penetrating round is spent, not tumbled")
		check(tank.hp < hp, "a penetrating hull or roof hit damages")


func test_armor_that_stops_a_round_outright_shows_it_too() -> void:
	var world := stage()
	await frames(2)
	var ugv: Ugv = load("res://scripts/enemies/ugv.gd").new()
	ugv.position = Course.ground_at(world.rail.d + 60.0, 0.0)
	world.add_enemy(ugv)
	ugv.armor = 8.0
	var hit := Hit.make(Hit.Kind.BULLET, 3.0, ugv.hit_center() + Vector3(0, 0, 1.0), Vector3(0, 0, -1))
	hit.caliber = 8
	var stopped := _round(world, ugv, hit)
	check(stopped._glanced and not stopped.is_queued_for_deletion(), "equal-caliber armor turns the visible round")
	check_eq(ugv.hp, ugv.max_hp, "and does nothing")
	ugv.armor = 0.0
	var accepted := _round(world, ugv, hit)
	check(not accepted._glanced and accepted.is_queued_for_deletion(), "an unarmored hit is spent, not turned")
	check_eq(ugv.hp, ugv.max_hp - 3.0, "unarmored damage is accepted")
