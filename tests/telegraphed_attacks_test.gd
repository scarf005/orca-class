extends TestCase
## Sharper attacks, each with its telegraph: the UGV's ram, the walker's missile ripple, the quad's
## line of mortar circles, the spitter's trail and the helicopter's strafing run.


func _place(world: World, enemy: Enemy, ahead: float, lane: float) -> void:
	enemy.position = Course.ground_at(world.rail.d + world.player.course_offset + ahead, lane)
	world.add_enemy(enemy)


func test_a_ugv_the_tank_has_passed_winds_up_and_rams() -> void:
	var world := stage()
	var tank := world.player
	tank.invulnerable = true
	tank.course_u = 0.0
	var ugv := Ugv.new()
	_place(world, ugv, -30.0, Course.to_course(tank.global_position).y)
	ugv._attack_timer = INF
	ugv.behave(0.02)
	check(ugv._ram_wind > 0.0 and ugv.telegraphing(), "it spins its tracks up first")
	check_eq(ugv._ram, 0.0, "and is not charging yet")
	var before := ugv.global_position
	ugv.behave(0.2)
	check(ugv.global_position.distance_to(before) < 0.5, "it stays put while the tracks spin")
	for _i in 40:
		ugv.behave(0.02)
	check(ugv._ram > 0.0 and ugv._ram_wind <= 0.0, "the charge starts after 0.6 s")
	var hurt := [0.0]
	tank.damaged.connect(func(_e: Entity, hit: Hit) -> void: hurt[0] += hit.damage if hit.kind == Hit.Kind.RAM else 0.0)
	tank.invulnerable = false
	for _i in 120:
		if ugv._ram <= 0.0:
			break
		ugv.behave(1.0 / 60.0)
		tank.global_position = tank.global_position # The tank holds its place.
	check(hurt[0] >= Ugv.RAM_DAMAGE or ugv._ram_cooldown > 0.0, "the charge lands as a ram hit")


func test_a_ugv_does_not_ram_from_the_wrong_place() -> void:
	var world := stage()
	var tank := world.player
	var lane := Course.to_course(tank.global_position).y
	for case in [[30.0, lane], [-30.0, lane + 9.0], [-3.0, lane]]:
		var ugv := Ugv.new()
		_place(world, ugv, case[0], case[1])
		ugv._attack_timer = INF
		ugv.behave(0.02)
		check(ugv._ram_wind <= 0.0, "no ram with the tank %.0f m ahead, %.0f m off" % [-case[0], case[1] - lane])
	var supply := Ugv.new()
	supply.weapon = "atgm"
	_place(world, supply, -30.0, lane)
	supply.behave(0.02)
	check(supply._ram_wind <= 0.0, "only the gun UGV rams")


func test_walker_missiles_come_as_a_four_ripple_after_the_pod_opens() -> void:
	var world := stage()
	var tank := world.player
	var walker := Walker.new()
	walker.weapon = "missile"
	_place(world, walker, 40.0, 0.0)
	walker._attack_timer = 0.0
	walker.behave(0.02)
	check_near(walker._telegraph, Walker.MISSILE_WIND, 0.05, "the telegraph is 0.8 s")
	for _i in 30:
		walker.behave(0.02)
	check(walker._pod_lid.rotation.x > 0.5, "the pod's lid swings open during the wind-up")
	check_eq(world.projectiles.size(), 0, "nothing flies yet")
	for _i in 60:
		walker.behave(0.02)
	var missiles := world.projectiles.filter(func(p: Projectile) -> bool: return p.homing_target == tank)
	check_eq(missiles.size(), Walker.RIPPLE, "four missiles leave one after another")
	check(missiles.all(func(p: Projectile) -> bool: return p.homing_lead and p.trail.a > 0.0), "each leads the tank")
	check_eq(walker._burst, 0, "and the ripple ends")


func test_mortar_volley_is_a_line_across_the_road_with_a_gap_and_smoke() -> void:
	var world := stage()
	var tank := world.player
	tank.velocity = Vector3.ZERO
	var quad := QuadMech.new()
	quad.weapon = "mortar"
	_place(world, quad, 70.0, 0.0)
	quad.slew_barrel(quad._gun, quad._lob(quad._muzzle.global_position, quad._mortar_target(tank, 2.0), 1.7), 100.0, 1.0) # The tube has trained onto the line.
	quad._attack(tank)
	var shells := world.projectiles.filter(func(p: Projectile) -> bool: return p.blast_damage > 0.0)
	check_eq(shells.size(), QuadMech.MORTAR_SLOTS - 1, "one circle of the line stays empty")
	check(shells.all(func(p: Projectile) -> bool: return p.trail == QuadMech.MORTAR_SMOKE), "each shell trails dark smoke")
	var centre := Course.to_course(tank.global_position)
	var slots: Array[int] = []
	var ds: Array[float] = []
	for shell: Projectile in shells:
		var flight := shell.life - 1.0
		var land := Course.to_course(shell.global_position + shell.velocity * flight + Vector3.DOWN * 0.5 * shell.gravity * flight * flight)
		slots.append(roundi((land.y - centre.y) / QuadMech.MORTAR_SPACING))
		ds.append(land.x)
	check(slots.all(func(s: int) -> bool: return absi(s) <= 2), "the circles span five slots across the road")
	check_eq(slots.size(), slots.duplicate().reduce(func(a: Array, s: int) -> Array: return a if s in a else a + [s], []).size(), "each lands in its own slot")
	check(ds.max() - ds.min() < 3.0, "they share one line across the road (%.1f m)" % (ds.max() - ds.min()))


func test_spore_shells_leave_a_pale_trail() -> void:
	var world := stage()
	var spitter := Spitter.new()
	_place(world, spitter, 50.0, 0.0)
	spitter._volley(world.player)
	var spores := world.projectiles.filter(func(p: Projectile) -> bool: return p.blast_damage > 0.0)
	check(not spores.is_empty() and spores.all(func(p: Projectile) -> bool: return p.trail == Spitter.SPORE_TRAIL), "every spore trails")
	check(Spitter.SPORE_TRAIL.get_luminance() > 0.8, "and the trail is pale")


func test_helicopter_strafing_run_walks_its_sight_down_the_lane_then_fires() -> void:
	var world := stage()
	var tank := world.player
	tank.velocity = Vector3.ZERO
	var heli := Helicopter.new()
	heli.set_meta("slot", Vector3(0, 13, 55))
	_place(world, heli, 55.0, 0.0)
	heli.position.y += 13.0
	heli._strafing = true
	heli._attack_timer = 0.0
	heli.behave(0.01)
	check(heli.telegraphing(), "the run starts with a telegraph")
	var lane := Course.to_course(tank.global_position)
	check_near(Course.to_course(heli._strafe_point()).y, lane.y, 0.5, "the sight walks the tank's own lane")
	var start := Course.to_course(heli._strafe_point()).x
	check(start > lane.x + 40.0, "it starts well ahead of the tank")
	for _i in 40:
		heli.behave(0.02)
	var walked := start - Course.to_course(heli._strafe_point()).x
	check(walked > 20.0, "the sight walks toward the tank during the telegraph (%.0f m)" % walked)
	check_eq(world.projectiles.size(), 0, "and nothing is fired yet")
	for _i in 200:
		heli.behave(0.02)
	check(world.projectiles.size() >= Helicopter.STRAFE_ROUNDS - 2, "then the rounds follow it down the lane (%d)" % world.projectiles.size())
	check(not heli._strafing and heli._rockets == false and heli._burst == 0, "and the cycle goes back to the gun")
