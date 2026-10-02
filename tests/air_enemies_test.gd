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


func _heli_ready_to_fire(world: World, tank: Tank) -> Helicopter:
	var heli := Helicopter.new()
	heli.set_meta("slot", Vector3(0, 13, 55))
	heli.position = Course.ground_at(world.rail.d + 55.0, 0.0) + Vector3.UP * 13.0
	world.add_enemy(heli)
	heli._rockets = true
	heli._telegraph = 0.1
	tank.velocity = Course.right(world.rail.d) * 10.0
	return heli


func test_rocket_pair_aims_where_the_tank_will_be_and_holds_it() -> void:
	var world := stage()
	var tank := world.player
	var heli := _heli_ready_to_fire(world, tank)
	var target := tank.hit_center()
	var flight := heli.global_position.distance_to(target) / Helicopter.ROCKET_SPEED
	heli.behave(0.2)
	check_eq(heli._burst, 2, "the telegraph ends in a pair of rockets")
	var expected := target + tank.velocity * flight
	check(heli._rocket_aim.distance_to(expected) < 2.0, "the aim point leads the tank by the rockets' flight (%.1f m off)" % heli._rocket_aim.distance_to(expected))
	check(heli._rocket_aim.distance_to(target) > 5.0, "the lead is a real offset from the tank")
	var fixed := heli._rocket_aim
	tank.velocity = -tank.velocity
	tank.global_position += Vector3.UP * 3.0
	check(heli._aim_point(tank).is_equal_approx(fixed), "the aim does not re-track during the pair")
	heli._fire(tank)
	heli._burst -= 1
	tank.velocity = Vector3.ZERO
	heli._fire(tank)
	check(heli._aim_point(tank).is_equal_approx(fixed), "both rockets share the fixed aim")


func test_rocket_aim_tracks_again_after_the_pair() -> void:
	var world := stage()
	var tank := world.player
	var heli := _heli_ready_to_fire(world, tank)
	heli.behave(0.2)
	heli._burst = 0
	tank.velocity = Vector3.ZERO
	check(heli._aim_point(tank).is_equal_approx(tank.hit_center()), "between volleys the aim follows the tank again")


func test_tiltrotor_flies_in_hovers_drops_a_squad_and_sweeps() -> void:
	var world := stage()
	var tank := world.player
	tank.invulnerable = true
	world.director.events.clear() # Only the tiltrotor and its squad.
	var spawned := world.director.spawn_wave({"d": world.rail.d, "kind": "tiltrotor", "height": 10.0, "ahead": 150.0, "u": 16.0, "props": {"squad": "drones"}})
	var rotor := spawned[0] as Tiltrotor
	rotor.invulnerable = true
	check_eq(rotor.state, Tiltrotor.State.APPROACH, "it starts in airplane mode")
	check_near(rotor._tilt, 0.0, 0.001, "rotors forward")
	var enemies_before := world.enemies.size()
	var start := Course.to_course(rotor.global_position).x - world.rail.d
	var fast := await wait_until(func() -> bool: return Course.to_course(rotor.global_position).x - world.rail.d < start - 60.0, 60 * 4)
	check(fast, "it closes sixty meters on the rail within four seconds")
	var hovering := await wait_until(func() -> bool: return rotor.state == Tiltrotor.State.HOVER, 60 * 12)
	check(hovering, "it settles into the hover")
	check_near(rotor._tilt, 1.0, 0.05, "rotors up in the hover")
	var ahead := Course.to_course(rotor.global_position).x - world.rail.d - tank.course_offset
	check(absf(ahead - Tiltrotor.HOVER_AHEAD) < 8.0, "it hangs ahead of the tank (%.1f m)" % ahead)
	check(absf(Course.to_course(rotor.global_position).y) > 10.0, "and beside the road")
	var dropped := await wait_until(func() -> bool: return rotor._dropped, 60 * 4)
	check(dropped, "the squad leaves the ramp")
	var drones := world.enemies.filter(func(e: Enemy) -> bool: return e is FpvDrone)
	check(drones.size() >= 2 and drones.size() <= 3, "two or three drones drop (%d)" % drones.size())
	check(world.enemies.size() > enemies_before, "they join the fight")
	var telegraphed := await wait_until(func() -> bool: return rotor.telegraphing(), 60 * 4)
	check(telegraphed, "the door gun shows its line first")
	var rounds := world.projectiles.size()
	check(rotor._line_a.distance_to(rotor._line_b) > 10.0, "the line spans the road")
	var fired := await wait_until(func() -> bool: return world.projectiles.size() > rounds, 60 * 3)
	check(fired, "then it sweeps")
	var gone_forward := await wait_until(gone(rotor), 60 * 14)
	check(gone_forward, "and tilts forward and leaves")


func test_a_lost_nacelle_spins_the_tiltrotor_down() -> void:
	var world := stage()
	var rotor := Tiltrotor.new()
	rotor.position = Course.ground_at(world.rail.d + 40.0, 16.0) + Vector3.UP * 10.0
	world.add_enemy(rotor)
	var tip := rotor.model.to_global(Vector3(Tiltrotor.NACELLE_X, 1.8, 0.0))
	check_eq(rotor.nacelle_at(tip), 1, "the right wing tip is the right nacelle")
	check_eq(rotor.nacelle_at(rotor.hit_center()), -1, "the fuselage is not a nacelle")
	var hit := Hit.make(Hit.Kind.BULLET, Tiltrotor.NACELLE_HP + 1.0, tip, Vector3.LEFT)
	hit.source = world.player
	rotor.take_hit(hit)
	check_eq(rotor.state, Tiltrotor.State.CRASH, "losing a nacelle starts the crash")
	check(not rotor.dead and rotor.hp > rotor.max_hp * 0.9, "the hull is still whole")
	var crashed := [false]
	rotor.died.connect(func(_e: Entity) -> void: crashed[0] = true)
	var down := await wait_until(func() -> bool: return crashed[0], 60 * 6)
	check(down, "it hits the ground and dies")
	check_eq(world.stats.kills, 1, "the crash counts as the player's kill")


func test_tiltrotor_dies_to_a_full_charge_or_two_quick_shells() -> void:
	var world := stage()
	var rotor := Tiltrotor.new()
	rotor.position = Course.ground_at(world.rail.d + 40.0, 16.0) + Vector3.UP * 10.0
	world.add_enemy(rotor)
	var quick := Hit.make(Hit.Kind.SHELL, Armament.QUICK_DAMAGE.y * Armament.SHELL_DAMAGE_SCALE * 0.5, rotor.hit_center(), Vector3.FORWARD)
	quick.source = world.player
	rotor.take_hit(quick)
	check(not rotor.dead, "one quick shell does not kill it")
	rotor.take_hit(quick)
	check(rotor.dead, "two do")
	var other := Tiltrotor.new()
	other.position = rotor.position + Vector3.UP * 20.0
	world.add_enemy(other)
	var full := Hit.make(Hit.Kind.SHELL, Armament.QUICK_DAMAGE.y * Armament.SHELL_DAMAGE_SCALE, other.hit_center(), Vector3.FORWARD)
	full.source = world.player
	other.take_hit(full)
	check(other.dead, "a full charge does")
