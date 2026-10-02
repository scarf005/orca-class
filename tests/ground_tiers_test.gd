extends TestCase
## Ground enemies sit on the main gun's tiers: a plain shell kills the medium ones, the quad mech
## takes two plain shells or one charged one, and a plate on their fronts turns most of the coax.


func _spawn(world: World, enemy: Enemy) -> Enemy:
	enemy.position = Course.ground_at(world.rail.d + world.player.course_offset + 45.0, 3.0)
	world.add_enemy(enemy)
	enemy.model.rotation.y = 0.0 # Facing -Z.
	return enemy


## A main gun hit as `Tank._fire_shell` makes it; `power` 1 is a full charge.
func _shell(tank: Tank, enemy: Enemy, power: float) -> Hit:
	var hit := Hit.make(Hit.Kind.SHELL, Armament.SHELL_DAMAGE * lerpf(Armament.APHE_DAMAGE.x, Armament.APHE_DAMAGE.y, power), enemy.hit_center(), Vector3.BACK)
	hit.caliber = 100
	hit.source = tank
	hit.weapon = "cannon"
	hit.stagger = 0.4
	return hit


## An 8 mm round arriving along `direction`.
func _coax(tank: Tank, enemy: Enemy, direction: Vector3) -> Hit:
	var spec: Dictionary = Armament.GUNS[8]
	var hit := Hit.make(Hit.Kind.BULLET, spec.damage, enemy.hit_center(), direction)
	hit.caliber = 8
	hit.source = tank
	return hit


## Seconds the tier-1 coax needs to kill `enemy` with rounds arriving along `direction`.
func _coax_kill_time(tank: Tank, enemy: Enemy, direction: Vector3) -> float:
	var spec: Dictionary = Armament.GUNS[8]
	var rounds := 0
	while not enemy.dead and rounds < 10000:
		enemy.take_hit(_coax(tank, enemy, direction))
		rounds += 1
	return rounds * spec.interval


func test_plain_shell_kills_the_medium_tier() -> void:
	var world := stage()
	var walker := Walker.new()
	var spitter := Spitter.new()
	for enemy: Enemy in [Ugv.new(), walker, spitter]:
		_spawn(world, enemy)
		enemy.take_hit(_shell(world.player, enemy, 0.0))
		check(enemy.dead, "%s dies to one plain shell" % enemy.get_script().get_global_name())
	var supply := Ugv.new()
	supply.weapon = "supply"
	_spawn(world, supply)
	supply.take_hit(_shell(world.player, supply, 0.0))
	check(supply.dead, "so does the supply UGV")


func test_quad_mech_survives_one_plain_shell() -> void:
	var world := stage()
	var tank := world.player
	var quad := _spawn(world, QuadMech.new()) as QuadMech
	quad.take_hit(_shell(tank, quad, 0.0))
	check(not quad.dead, "one plain shell leaves it standing")
	check_near(quad.hp, 900.0, 0.01, "with 900 of 2400 health left")
	quad.take_hit(_shell(tank, quad, 0.0))
	check(quad.dead, "the second kills it")


func test_quad_mech_dies_to_one_full_charge_shell() -> void:
	var world := stage()
	var quad := _spawn(world, QuadMech.new()) as QuadMech
	quad.take_hit(_shell(world.player, quad, 1.0))
	check(quad.dead, "a 3000 damage shell kills it outright")


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
	var shell := _shell(tank, ugv, 0.0)
	shell.direction = Vector3.BACK
	check_eq(ugv.frontal_armor(shell, 0.25), 1.0, "shells ignore it")
	var rise := _coax(tank, ugv, Vector3.DOWN)
	check_eq(ugv.frontal_armor(rise, 0.25), 1.0, "a round straight from above has no front")


func test_coax_needs_three_seconds_from_the_front_and_little_from_the_side() -> void:
	var world := stage()
	var tank := world.player
	var front := _coax_kill_time(tank, _spawn(world, Ugv.new()), Vector3.BACK)
	var side := _coax_kill_time(tank, _spawn(world, Ugv.new()), Vector3.RIGHT)
	var walker_front := _coax_kill_time(tank, _spawn(world, Walker.new()), Vector3.BACK)
	print("UGV tier-1 coax kill: front %.2f s, side %.2f s; walker front %.2f s" % [front, side, walker_front])
	check(front >= 3.0, "the coax from straight ahead takes at least 3 s (%.2f)" % front)
	check(side <= 1.5, "from the side at most 1.5 s (%.2f)" % side)
	check(walker_front >= 3.0, "the walker's front plate holds the same (%.2f)" % walker_front)


func test_front_plate_leaves_module_damage_alone() -> void:
	var world := stage()
	var ugv := _spawn(world, Ugv.new()) as Ugv
	var hit := _coax(world.player, ugv, Vector3.BACK)
	hit.position = ugv.global_position + Vector3.UP * 0.3
	ugv.take_hit(hit)
	check_near(ugv.hp, ugv.max_hp - hit.damage * 0.25, 0.001, "the hull gets a quarter")
	check_near(ugv.tracks_hp, 6.0 - hit.damage, 0.001, "the tracks take it all")
