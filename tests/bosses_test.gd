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


func test_colossus_caps_shield_nodes_and_burn_off() -> void:
	var world := stage()
	var boss := _colossus(world)
	var node: Colossus.Part = boss.parts[0]
	_hit_part(boss, node, Hit.Kind.SHELL, 60.0)
	check_eq(node.hp, Colossus.NODE_HP, "capped node takes no damage")
	check(node.cap < Colossus.CAP_HP, "cap wears down")
	_hit_part(boss, node, Hit.Kind.FIRE, 10.0, true)
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


func test_helicopter_armor_then_phases() -> void:
	var world := stage("boss")
	var boss := _helicopter(world)
	var body_hit := Hit.make(Hit.Kind.SHELL, 100.0, boss.global_position + Vector3(0, 0, 40))
	var hp := boss.hp
	boss.take_hit(body_hit)
	check_near(hp - boss.hp, 50.0, 0.5, "armor panels halve body damage")
	for side in ["panel_l", "panel_r"]:
		var part: Helicopter.Part = boss.parts[side]
		boss.take_hit(Hit.make(Hit.Kind.SHELL, 999.0, boss.model.global_transform * part.offset))
	check_eq(boss.phase, Helicopter.Phase.STRIPPED, "losing both panels strips it")
	boss.hp = boss.max_hp * 0.34
	boss.take_hit(Hit.make(Hit.Kind.SHELL, boss.max_hp * 0.05, boss.global_position + Vector3(0, 0, 40)))
	check_eq(boss.phase, Helicopter.Phase.INFECTED, "below a third it turns")


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
