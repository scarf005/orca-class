extends TestCase
## Ground enemies sit on the main gun's tiers: a plain shell kills the medium ones, the quad mech
## takes two plain shells or one charged one, and a plate on their fronts turns most of the coax.


func _spawn(world: World, enemy: Enemy) -> Enemy:
	enemy.position = Course.ground_at(world.rail.d + world.player.course_offset + 45.0, 3.0)
	world.add_enemy(enemy)
	enemy.model.rotation.y = 0.0 # Facing -Z.
	return enemy


## Fire an APHE shell through the same public runtime path as the tank's cannon.
func _fire_shell(tank: Tank, enemy: Enemy, power: float) -> Projectile:
	var world := World.current
	var muzzle := tank.model.muzzle.global_position
	var before := world.projectiles.size()
	tank._fire_shell(Armament.Round.APHE, muzzle, (enemy.hit_center() - muzzle).normalized(), power)
	var shell: Projectile = world.projectiles[before] if world.projectiles.size() > before else null
	if shell != null and power < 1.0:
		shell.resolve_now(Armament.SHELL_RANGE)
	return shell


## A coax round arriving along `direction`.
func _coax(tank: Tank, enemy: Enemy, direction: Vector3, caliber := 8) -> Hit:
	var spec: Dictionary = Armament.GUNS[caliber]
	var hit := Hit.make(Hit.Kind.BULLET, spec.damage, enemy.hit_center(), direction)
	hit.caliber = caliber
	hit.source = tank
	return hit


## Seconds the penetrating coax needs to kill `enemy` with rounds arriving along `direction`.
func _coax_kill_time(tank: Tank, enemy: Enemy, direction: Vector3) -> float:
	var spec: Dictionary = Armament.GUNS[15]
	var rounds := 0
	while not enemy.dead and rounds < 10000:
		enemy.take_hit(_coax(tank, enemy, direction, 15))
		rounds += 1
	return rounds * spec.interval


func test_plain_shell_kills_the_medium_tier() -> void:
	var world := stage()
	var walker := Walker.new()
	var spitter := Spitter.new()
	for enemy: Enemy in [Ugv.new(), walker, spitter]:
		_spawn(world, enemy)
		var shell := _fire_shell(world.player, enemy, 0.0)
		check_eq(shell.hit.damage, 1600.0, "the fired quick shell carries its scaled APHE payload")
		check(enemy.dead, "%s dies to one plain shell" % enemy.get_script().get_global_name())
	var supply := Ugv.new()
	supply.weapon = "supply"
	_spawn(world, supply)
	var supply_shell := _fire_shell(world.player, supply, 0.0)
	check_eq(supply_shell.hit.damage, 1600.0, "the fired supply-UGV shell carries its scaled APHE payload")
	check(supply.dead, "so does the supply UGV")


func test_quad_mech_survives_one_plain_shell() -> void:
	var world := stage()
	var tank := world.player
	var quad := _spawn(world, QuadMech.new()) as QuadMech
	var quick := _fire_shell(tank, quad, 0.0)
	check_eq(quick.hit.damage, 1600.0, "a quick shell is scaled by the live APHE path")
	check(not quad.dead, "one quick shell leaves it standing")
	check_near(quad.hp, 800.0, 0.01, "with 800 of 2400 health left")
	_fire_shell(tank, quad, 0.0)
	check(quad.dead, "the second kills it")


func test_quad_mech_dies_to_one_full_charge_shell() -> void:
	var world := stage()
	var quad := _spawn(world, QuadMech.new()) as QuadMech
	var shell := _fire_shell(world.player, quad, 1.0)
	check_eq(shell.hit.damage, 6000.0, "a full shell carries the live 6000 damage payload")
	check(quad.dead, "a full-charge shell kills it outright")


func test_quad_mech_collapses_without_two_legs() -> void:
	var world := stage()
	var quad := _spawn(world, QuadMech.new()) as QuadMech
	for leg in 2:
		var corner: Vector2 = quad._legs[leg].corner
		var at: Vector3 = quad._body.global_transform * Vector3(corner.x * 1.8, -1.5, corner.y * 1.4)
		var hit := Hit.make(Hit.Kind.SHELL, QuadMech.LEG_HP, at, Vector3.DOWN)
		quad.take_hit(hit)
	check(quad.collapsed(), "two legs shot off bring it down")
	check(not quad.dead, "without killing the hull")


func test_front_arc_boundaries() -> void:
	var world := stage()
	var ugv := _spawn(world, Ugv.new()) as Ugv
	var tank := world.player
	for case in [[0.0, 0.25], [59.0, 0.25], [-59.0, 0.25], [61.0, 1.0], [90.0, 1.0], [180.0, 1.0]]:
		# A round flying away from a gunner `case[0]` degrees off the nose.
		var from := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(case[0]))
		var hit := _coax(tank, ugv, -from)
		check_near(ugv.frontal_armor(hit, 0.25), case[1], 0.0001, "%.0f degrees off the nose" % case[0])
	var shell := Hit.make(Hit.Kind.SHELL, Armament.SHELL_DAMAGE, ugv.hit_center(), Vector3.BACK)
	shell.caliber = 100
	check_eq(ugv.frontal_armor(shell, 0.25), 1.0, "shells ignore it")
	var rise := _coax(tank, ugv, Vector3.DOWN)
	check_eq(ugv.frontal_armor(rise, 0.25), 1.0, "a round straight from above has no front")


func test_penetrating_coax_takes_longer_against_the_front_plate() -> void:
	var world := stage()
	var tank := world.player
	var front := _coax_kill_time(tank, _spawn(world, Ugv.new()), Vector3.BACK)
	var side := _coax_kill_time(tank, _spawn(world, Ugv.new()), Vector3.RIGHT)
	var walker_front := _coax_kill_time(tank, _spawn(world, Walker.new()), Vector3.BACK)
	check(front > side * 3.5 and front < side * 4.5, "the front plate takes about four times as many penetrating rounds")
	check(side > 0.0 and side < 5.0, "15 mm can kill from the side within five seconds")
	check(walker_front > side and walker_front < front, "the walker's thinner armor still benefits from its front plate")
	for enemy: Enemy in [_spawn(world, Ugv.new()), _spawn(world, Walker.new())]:
		for direction in [Vector3.BACK, Vector3.RIGHT]:
			var hp := enemy.hp
			var hit := _coax(tank, enemy, direction)
			check(enemy.glances(hit), "8 mm glances from front and side")
			enemy.take_hit(hit)
			check_eq(enemy.hp, hp, "tier-1 coax cannot penetrate")


func test_front_plate_leaves_module_damage_alone() -> void:
	var world := stage()
	var ugv := _spawn(world, Ugv.new()) as Ugv
	var glance := _coax(world.player, ugv, Vector3.BACK)
	glance.position = ugv.global_position + Vector3.UP * 0.3
	ugv.take_hit(glance)
	check_eq(ugv.hp, ugv.max_hp, "a glance spares the hull")
	check_eq(ugv.tracks_hp, 6.0, "a glance spares the tracks too")
	var hit := _coax(world.player, ugv, Vector3.BACK, 15)
	hit.position = glance.position
	ugv.take_hit(hit)
	check_near(ugv.hp, ugv.max_hp - 0.375, 0.001, "armor blunts the round, then the front quarters hull damage")
	check_near(ugv.tracks_hp, 4.5, 0.001, "module damage is armor-blunted but not quartered by the front plate")
