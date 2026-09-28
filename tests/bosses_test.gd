extends TestCase
## Mid-boss caps/core and the helicopter's phases and crash.


func _colossus(world: World) -> Colossus:
	var boss := Colossus.new()
	boss.position = Course.ground_at(world.rail.d + 60.0, 0.0)
	world.add_enemy(boss)
	boss.stagger = 1000.0 # Keep it from attacking during the test.
	return boss


func _hit_part(boss: Colossus, part: Colossus.Part, kind: Hit.Kind, damage: float, incendiary := false) -> void:
	var hit := Hit.make(kind, damage, boss.global_transform * part.offset)
	hit.incendiary = incendiary
	boss.take_hit(hit)


func test_colossus_faces_back_up_a_bent_road() -> void:
	var world := stage()
	var boss := Colossus.new()
	boss.position = Course.ground_at(Course.MIDBOSS_D, 0.0)
	world.add_enemy(boss)
	var toward_tank := -Course.forward(Course.MIDBOSS_D)
	check(absf(Course.forward(Course.MIDBOSS_D).x) > 0.3, "the schoolyard runs at an angle to the world axes")
	var core_side := (boss.global_transform * boss.core.offset - boss.global_position).normalized()
	check(core_side.dot(toward_tank) > 0.7, "the core faces the approaching tank")


func test_colossus_caps_shield_nodes_and_burn_off() -> void:
	var world := stage()
	var boss := _colossus(world)
	var node: Colossus.Part = boss.parts[0]
	_hit_part(boss, node, Hit.Kind.SHELL, 60.0)
	check_eq(node.hp, Colossus.NODE_HP, "capped node takes no damage")
	check(node.cap < Colossus.CAP_HP, "cap wears down")
	_hit_part(boss, node, Hit.Kind.FIRE, Colossus.CAP_HP / 4.0, true)
	check(node.cap <= 0.0, "fire burns the cap off fast (4x)")
	_hit_part(boss, node, Hit.Kind.SHELL, 50.0)
	check_near(node.hp, Colossus.NODE_HP - 50.0, 0.01, "exposed node takes damage")


func test_colossus_core_opens_then_dies() -> void:
	var world := stage()
	var boss := _colossus(world)
	for part: Colossus.Part in boss.parts:
		part.cap = 0.0
		_hit_part(boss, part, Hit.Kind.SHELL, 999.0)
	check(boss.core.mesh.visible, "core exposed once every node is gone")
	check(not boss.dead, "still alive with the core intact")
	_hit_part(boss, boss.core, Hit.Kind.SHELL, 9999.0)
	boss.stagger = 0.0
	var died := await wait_until(gone(boss), 400)
	check(died, "core destroyed: collapses and dies")


func test_colossus_heat_interrupts_sweep() -> void:
	var world := stage()
	var boss := _colossus(world)
	boss.stagger = 0.0
	boss._attack = Colossus.Attack.SWEEP
	boss._attack_time = 0.5
	var heat := Hit.make(Hit.Kind.SHELL, 10.0, boss.global_position)
	heat.stagger = 1.0
	boss.take_hit(heat)
	check_eq(boss._attack, Colossus.Attack.NONE, "heavy stagger cancels a telegraphed sweep")


func _helicopter(world: World) -> Helicopter:
	world.director._start_boss({"kind": "helicopter"})
	var boss := world.boss as Helicopter
	boss._next_attack = 1000.0
	return boss


func _shell(at: Vector3, direction := Vector3.FORWARD) -> Hit:
	var hit := Hit.make(Hit.Kind.SHELL, 110.0, at, direction)
	hit.caliber = 100
	return hit


## A world point on the airframe at a model-local spot.
func _on(boss: Helicopter, local: Vector3) -> Vector3:
	return boss.model.global_transform * local


func test_helicopter_era_eats_a_shell_then_bare_hull_takes_a_quarter() -> void:
	var world := stage("boss")
	var boss := _helicopter(world)
	var flank := Vector3(-0.8, 0.0, 0.8)
	boss.take_hit(_shell(_on(boss, flank)))
	check_near(boss.hp, boss.max_hp * (1.0 - Helicopter.PLATED_SHARE), 0.5, "a plated flank only loses the plate")
	check(not boss._live("era_left"), "the shell pops the left plate")
	check(boss._live("era_right") and boss._live("era_front"), "other plates hold")
	boss.take_hit(_shell(_on(boss, flank)))
	check_near(boss.hp, boss.max_hp * (1.0 - Helicopter.PLATED_SHARE - Helicopter.CANNON_SHARE), 0.5, "the bared flank takes a quarter")
	var hp := boss.hp
	boss.take_hit(_shell(_on(boss, Vector3(0, 0.3, 4.5))))
	check_near(hp - boss.hp, boss.max_hp * Helicopter.CANNON_SHARE, 0.5, "the tail boom was never plated")
	var coax := Hit.make(Hit.Kind.BULLET, 10.0, _on(boss, Vector3(0, 0.3, 4.5)))
	coax.caliber = 20
	hp = boss.hp
	boss.take_hit(coax)
	check(hp - boss.hp < boss.max_hp * 0.01, "machine guns only scratch it")


func test_helicopter_four_bare_shells_bring_it_down() -> void:
	var world := stage("boss")
	var boss := _helicopter(world)
	for i in 4:
		check(boss._crash <= 0.0, "still flying before shell %d" % (i + 1))
		boss.take_hit(_shell(_on(boss, Vector3(0, 0.3, 4.5))))
	check(boss._crash > 0.0, "four shells on bare airframe start the crash")


func test_helicopter_phases_follow_hull() -> void:
	var world := stage("boss")
	var boss := _helicopter(world)
	boss.take_hit(_shell(_on(boss, Vector3(0, 0.3, 4.5))))
	boss.take_hit(_shell(_on(boss, Vector3(0, 0.3, 4.5))))
	check_eq(boss.phase, Helicopter.Phase.STRIPPED, "half its hull gone: it closes in")
	boss.take_hit(_shell(_on(boss, Vector3(0, 0.3, 4.5))))
	check_eq(boss.phase, Helicopter.Phase.INFECTED, "a quarter left: it turns")


func test_helicopter_modules_change_the_fight() -> void:
	var world := stage("boss")
	var boss := _helicopter(world)
	boss.take_hit(_shell(_on(boss, boss.parts.chin.offset)))
	check(not boss._live("chin"), "a shell wrecks the chin gun")
	for i in 30:
		boss._choose_attack()
		check(boss._attack != Helicopter.Attack.GUN, "no gun runs without the chin gun")
		boss._end_attack()
	boss.take_hit(_shell(_on(boss, boss.parts.tail_rotor.offset)))
	check(not boss._live("tail_rotor"), "a shell wrecks the tail rotor")
	var yaw := boss.model.rotation.y
	boss.stagger = 0.0
	boss.behave(0.1)
	check(absf(boss.model.rotation.y - yaw) > 0.2, "without a tail rotor it spins")
	boss.hp = boss.max_hp
	boss.take_hit(_shell(_on(boss, boss.parts.engine_l.offset)))
	check(boss._crash <= 0.0, "one engine keeps it up")
	boss.take_hit(_shell(_on(boss, boss.parts.engine_r.offset)))
	check(boss._crash > 0.0, "losing both engines drops it")


func test_colossus_cannon_sized() -> void:
	var world := stage()
	var boss := _colossus(world)
	var node: Colossus.Part = boss.parts[0]
	_hit_part_with(boss, node, _shell(Vector3.ZERO))
	check(node.cap <= 0.0 and node.hp == Colossus.NODE_HP, "one shell pops a cap")
	_hit_part_with(boss, node, _shell(Vector3.ZERO))
	check(node.hp <= 0.0, "one shell bursts a bare node")
	for part: Colossus.Part in boss.parts:
		part.cap = 0.0
		part.hp = 0.0
	for i in 3:
		_hit_part_with(boss, boss.core, _shell(Vector3.ZERO))
	check_near(boss.core.hp, Colossus.CORE_HP * 0.25, 0.5, "each shell takes a quarter of the core")


func _hit_part_with(boss: Colossus, part: Colossus.Part, hit: Hit) -> void:
	hit.position = boss.global_transform * part.offset
	boss.take_hit(hit)


func test_helicopter_crash_clears_stage() -> void:
	var world := stage("boss")
	var boss := _helicopter(world)
	var cleared := [false]
	world.stage_cleared.connect(func() -> void: cleared[0] = true)
	boss.hp = 1.0
	var hit := Hit.make(Hit.Kind.SHELL, 50.0, boss.global_position)
	hit.pierce = true
	boss.take_hit(hit)
	check(boss._crash > 0.0, "zero hp starts the crash")
	var ok := await wait_until(func() -> bool: return cleared[0], 60 * 9)
	check(ok, "crash into the dam clears the stage")


func test_flares_catch_shells() -> void:
	var world := stage("boss")
	var boss := _helicopter(world)
	boss.phase = Helicopter.Phase.STRIPPED
	boss._pop_flares()
	var flares := world.enemies.filter(func(e: Entity) -> bool: return e is Flare)
	check(flares.size() >= 4, "pops a spread of flares")
	check(flares.all(func(e: Entity) -> bool: return e.team == Entity.Team.ENEMY), "flares are targets for shells")


func test_bosses_shrug_off_machine_guns() -> void:
	var world := stage("boss")
	var boss := _helicopter(world)
	var coax := Hit.make(Hit.Kind.BULLET, 10.0, boss.global_position)
	coax.caliber = 20
	var fragment := Hit.make(Hit.Kind.FRAGMENT, 10.0, boss.global_position)
	check_near(boss.damage_multiplier(coax), 0.4, 0.001, "20 mm coax only scratches the gunship")
	check_near(boss.damage_multiplier(fragment), 1.5, 0.001, "airburst fragments shred it")
	var colossus := _colossus(world)
	var node: Colossus.Part = colossus.parts[0]
	node.cap = 0.0
	_hit_part(colossus, node, Hit.Kind.BULLET, 100.0)
	check_near(node.hp, Colossus.NODE_HP - 35.0, 0.01, "the colossus soaks machine-gun fire")
