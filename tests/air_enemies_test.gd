extends TestCase
## UAV bomb carpets and helicopter rocket leads.


func _uav_over(world: World) -> Uav:
	var uav := Uav.new()
	uav.position = Course.ground_at(world.rail.d + 30.0, 0.0) + Vector3.UP * Uav.ALTITUDE
	world.add_enemy(uav)
	return uav


func test_bomb_run_is_a_carpet_across_the_road_with_one_gap() -> void:
	var world := stage()
	var tank := world.player
	tank.velocity = Vector3.ZERO
	var uav := _uav_over(world)
	uav._bomb_run(0.0, tank, 30.0)
	var bombs := world.projectiles.filter(func(p: Projectile) -> bool: return p.blast_damage > 0.0)
	check_eq(bombs.size(), Uav.CARPET_BOMBS - 1, "four bombs fall and one slot stays empty")
	var us: Array[float] = []
	var ds: Array[float] = []
	for bomb: Projectile in bombs:
		var land := Course.to_course(bomb.global_position + _landing_offset(bomb))
		us.append(land.y)
		ds.append(land.x)
	us.sort()
	var centre := Course.to_course(tank.global_position).y
	var slots: Array[int] = []
	for u in us:
		slots.append(roundi((u - centre) / Uav.CARPET_SPACING))
	slots.sort()
	check_eq(slots.size(), 4, "four distinct impact slots")
	for i in slots.size():
		check(absf(us[i] - centre - slots[i] * Uav.CARPET_SPACING) < 0.5, "impact %d sits on the 5 m grid across the road" % i)
		check(slots[i] >= -2 and slots[i] <= 2, "impact %d is within the five slots" % i)
		check(i == 0 or slots[i] > slots[i - 1], "impact slots are distinct")
	check(absf(ds.max() - ds.min()) < 0.5, "all impacts share one line across the road")
	var missing := 0
	for slot in range(-2, 3):
		if slot not in slots:
			missing += 1
	check_eq(missing, 1, "exactly one slot is empty")


## Where a bomb is when it reaches the ground, relative to its release point.
func _landing_offset(bomb: Projectile) -> Vector3:
	return bomb.velocity * Uav.BOMB_FLIGHT + Vector3.DOWN * 0.5 * bomb.gravity * Uav.BOMB_FLIGHT * Uav.BOMB_FLIGHT


func test_carpet_circles_are_marked_before_impact_and_follow_the_tank() -> void:
	var world := stage()
	var tank := world.player
	tank.velocity = Course.right(world.rail.d) * 8.0
	var uav := _uav_over(world)
	check(Uav.BOMB_FLIGHT >= 1.2, "every circle shows at least 1.2 s before impact")
	uav._bomb_run(0.0, tank, 30.0)
	var bombs := world.projectiles.filter(func(p: Projectile) -> bool: return p.blast_damage > 0.0)
	var predicted := Course.to_course(tank.global_position + tank.velocity * Uav.CARPET_LEAD).y
	var mean := 0.0
	for bomb: Projectile in bombs:
		check(bomb.life >= Uav.BOMB_FLIGHT, "the bomb outlives its telegraph")
		mean += Course.to_course(bomb.global_position + _landing_offset(bomb)).y
	mean /= bombs.size()
	check(absf(mean - predicted) <= Uav.CARPET_SPACING * 1.0, "the carpet is centred on the tank's lateral position one second ahead (%.1f vs %.1f)" % [mean, predicted])
