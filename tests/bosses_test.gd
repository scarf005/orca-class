extends TestCase
## Mid-boss caps/core and the gunship's phases and crash.


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
	check_eq(boss.max_hp, 1200.0, "health bar includes all three caps, nodes and the core")
	_hit_part(boss, node, Hit.Kind.SHELL, 60.0)
	check_eq(node.hp, Colossus.NODE_HP, "capped node takes no damage")
	check_near(node.cap, 40.0, 0.01, "cap absorbs the hit")
	check_near(boss.hp, boss.max_hp - 60.0, 0.01, "cap damage immediately lowers the health bar")
	_hit_part(boss, node, Hit.Kind.FIRE, Colossus.CAP_HP / 4.0, true)
	check(node.cap <= 0.0, "fire burns the cap off fast (4x)")
	check_near(node.hp, Colossus.NODE_HP - 15.0, 0.01, "10 fire damage burns the remaining cap; 15 reaches the node")
	check_near(boss.hp, boss.max_hp - 115.0, 0.01, "health bar includes both burned cap and node damage")
	_hit_part(boss, node, Hit.Kind.SHELL, 50.0)
	check_near(node.hp, Colossus.NODE_HP - 65.0, 0.01, "exposed node takes full damage")


func test_colossus_coax_damage_is_not_reduced() -> void:
	var world := stage()
	var boss := _colossus(world)
	for i in 3:
		var node: Colossus.Part = boss.parts[i]
		var hit := Hit.make(Hit.Kind.BULLET, 40.0, Vector3.ZERO)
		hit.caliber = [8, 15, 20][i]
		_hit_part_with(boss, node, hit)
		check_near(node.cap, 60.0, 0.01, "%d mm deals full damage to the cap" % hit.caliber)
		hit.damage = 80.0
		_hit_part_with(boss, node, hit)
		check_eq(node.cap, 0.0, "cap is depleted")
		check_near(node.hp, 80.0, 0.01, "remaining bullet damage reaches the node without reduction")
	check_near(boss.hp, boss.max_hp - 360.0, 0.01, "health bar loses all the accepted bullet damage")


func test_colossus_exact_cap_break_and_small_cannon_hits() -> void:
	var world := stage()
	var boss := _colossus(world)
	var node: Colossus.Part = boss.parts[0]
	var hit := _shell(Vector3.ZERO)
	hit.damage = 1.0
	_hit_part_with(boss, node, hit)
	check_eq(node.cap, 99.0, "100 mm caliber does not fabricate minimum damage")
	hit.damage = 99.0
	_hit_part_with(boss, node, hit)
	check_eq(node.cap, 0.0, "exact cap damage breaks it")
	check_eq(node.hp, Colossus.NODE_HP, "exact cap break has no surplus damage")
	check(not node.cap_mesh.visible, "broken cap disappears")
	check_near(boss.hp, boss.max_hp - Colossus.CAP_HP, 0.01, "exact break is counted once")


func test_colossus_incendiary_overflow_keeps_cap_only_fire_bonus() -> void:
	var world := stage()
	var boss := _colossus(world)
	var node: Colossus.Part = boss.parts[0]
	_hit_part(boss, node, Hit.Kind.FRAGMENT, 40.0, true)
	check_eq(node.cap, 0.0, "incendiary fragments also burn caps four times faster")
	check_near(node.hp, 85.0, 0.01, "25 damage burns the cap; remaining 15 is not multiplied")


func test_colossus_ignored_hits_do_not_damage_caps_or_confirm_hits() -> void:
	var world := stage()
	var boss := _colossus(world)
	var node: Colossus.Part = boss.parts[0]
	var confirmations: Array[bool] = []
	world.hit_confirmed.connect(func(killed: bool) -> void: confirmations.append(killed))
	var hit := _shell(Vector3.ZERO)
	hit.source = world.player
	for amount in [0.0, -10.0]:
		hit.damage = amount
		_hit_part_with(boss, node, hit)
	hit.damage = Armament.SHELL_DAMAGE
	boss.invulnerable = true
	_hit_part_with(boss, node, hit)
	boss.invulnerable = false
	check(confirmations.is_empty(), "ignored hits do not emit hit confirmation")
	hit.position = boss.global_position + Vector3.UP * 50.0
	boss.take_hit(hit)
	check_eq(node.cap, Colossus.CAP_HP, "zero, negative, invulnerable and off-target hits spare the cap")
	check_eq(node.hp, Colossus.NODE_HP, "ignored hits spare the node")
	check_eq(boss.hp, boss.max_hp, "ignored hits leave the health bar full")
	check_eq(confirmations, [false], "a hit on the mass away from any weak point still confirms")


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


func _gunship(world: World) -> Gunship:
	world.director._start_boss({"kind": "gunship"})
	var boss := world.boss as Gunship
	boss._next_attack = 1000.0
	return boss


func _shell(at: Vector3, direction := Vector3.FORWARD) -> Hit:
	var hit := Hit.make(Hit.Kind.SHELL, 110.0, at, direction)
	hit.caliber = 100
	return hit


## A world point on the airframe at a model-local spot.
func _on(boss: Gunship, local: Vector3) -> Vector3:
	return boss.model.global_transform * local


func test_gunship_era_eats_a_shell_then_bare_hull_takes_a_third() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var flank := Vector3(-2.8, 0.0, 0.8)
	boss.take_hit(_shell(_on(boss, flank)))
	check_near(boss.hp, boss.max_hp * (1.0 - Gunship.PLATED_SHARE), 0.5, "a plated flank only loses the plate")
	check(not boss._live("era_left"), "the shell pops the left plate")
	check(boss._live("era_right") and boss._live("era_front"), "other plates hold")
	boss.take_hit(_shell(_on(boss, flank)))
	check_near(boss.hp, boss.max_hp * (1.0 - Gunship.PLATED_SHARE - Gunship.CANNON_SHARE), 0.5, "the bared flank takes a third")
	var hp := boss.hp
	boss.take_hit(_shell(_on(boss, Vector3(0, 0.3, 7.0))))
	check_near(hp - boss.hp, boss.max_hp * Gunship.CANNON_SHARE, 0.5, "the tail boom was never plated")
	var coax := Hit.make(Hit.Kind.BULLET, 10.0, _on(boss, Vector3(0, 0.3, 7.0)))
	coax.caliber = 20
	hp = boss.hp
	boss.take_hit(coax)
	check(hp - boss.hp < boss.max_hp * 0.01, "machine guns only scratch it")


func test_gunship_three_bare_shells_bring_it_down() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	for i in 3:
		check(boss._crash <= 0.0, "still flying before shell %d" % (i + 1))
		boss.take_hit(_shell(_on(boss, Vector3(0, 0.3, 7.0))))
	check(boss._crash > 0.0, "three shells on bare airframe start the crash")


func test_gunship_phases_follow_hull() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	boss.take_hit(_shell(_on(boss, Vector3(0, 0.3, 7.0))))
	check_eq(boss.phase, Gunship.Phase.STRIPPED, "a third of its hull gone: it closes in")
	boss.take_hit(_shell(_on(boss, Vector3(0, 0.3, 7.0))))
	check_eq(boss.phase, Gunship.Phase.INFECTED, "one shell from death: it turns")


func test_gunship_modules_change_the_fight() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	boss.take_hit(_shell(_on(boss, boss.parts.chin.offset)))
	check(not boss._live("chin"), "a shell wrecks the chin drum")
	boss.phase = Gunship.Phase.STRIPPED
	var chosen := {}
	for i in 60:
		boss._choose_attack()
		chosen[boss._attack] = true
		boss._end_attack()
	check(not chosen.has(Gunship.Attack.ATGM), "no ATGM volleys without the chin drum")
	check(chosen.has(Gunship.Attack.GUN), "the gatlings still fly gun runs")
	boss._attack = Gunship.Attack.ROCKETS
	var gun_l: Node3D = boss.parts.gatling_l.node
	boss._lose_part(boss.parts.pod_l)
	check(not boss._live("gatling_l") and boss._live("gatling_r"), "a lost rack takes only the gatling slung under it")
	check(gun_l.get_parent() != boss.model, "the gatling falls away with its rack instead of hanging in midair")
	check_eq(boss._gatlings[0], null, "the fallen gatling no longer tracks the tank")
	boss._lose_part(boss.parts.gatling_r)
	check(boss._live("pod_r"), "a lost gatling leaves the rack above it")
	boss._lose_part(boss.parts.pod_r)
	check_eq(boss._attack, Gunship.Attack.NONE, "losing both racks stops an active rocket volley")
	var shots := world.projectiles.size()
	boss._rockets(1.0, world.player)
	check_eq(world.projectiles.size(), shots, "destroyed racks cannot fire")
	boss.phase = Gunship.Phase.INFECTED
	for i in 30:
		boss._choose_attack()
		check(boss._attack not in [Gunship.Attack.GUN, Gunship.Attack.ROCKETS], "infected attack choices also respect destroyed weapons")
		boss._end_attack()


func test_gunship_gatling_warns_after_chin_wreck_is_freed() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	boss._lose_part(boss.parts.chin)
	boss._chin.free()
	boss._attack = Gunship.Attack.GUN
	boss._attack_time = 0.13
	var before := world.fx._transients.size()
	boss._gun(0.01, world.player)
	check(world.fx._transients.size() > before, "a live gatling still draws its warning after the chin wreck is gone")


func test_gunship_rotors_are_independent_and_both_lost_crash() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var events: Array[bool] = []
	world.hit_confirmed.connect(func(killed: bool) -> void: events.append(killed))
	var hit := _shell(_on(boss, boss.parts.rotor_l.offset))
	hit.source = world.player
	boss.take_hit(hit)
	check(not boss._live("rotor_l") and boss._live("rotor_r"), "the left rotor can be destroyed independently")
	check(boss._crash <= 0.0, "one rotor keeps it flying")
	check_eq(events, [false], "one lost rotor confirms a hit, not a kill")
	boss.stagger = 0.0
	boss._velocity = Vector3.ZERO
	boss.behave(0.1)
	check(boss.model.rotation.z > 0.0, "the gunship banks toward its lost left rotor")
	hit = _shell(_on(boss, boss.parts.rotor_r.offset))
	hit.source = world.player
	boss.take_hit(hit)
	check(boss._crash > 0.0, "losing both rotors starts the crash while hull would survive")
	check_eq(events, [false, true], "the second rotor confirms the kill immediately")
	boss.take_hit(hit)
	check_eq(events.size(), 2, "crashing wreck does not confirm further hits")


func test_gunship_rotor_blades_can_be_shot_and_destroyed_blades_do_not_block() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	# Outboard blade tip is beyond the nacelle and missile rack hit spheres.
	var tip: Vector3 = boss.parts.rotor_l.offset + Vector3(-8.0, 0, 0)
	var from := _on(boss, tip + Vector3.UP * 5.0)
	var to := _on(boss, tip + Vector3.DOWN * 5.0)
	var distance := boss.hit_test(from, to)
	check(distance >= 0.0, "shots can hit the thin swept rotor disc")
	var point := from + (to - from).normalized() * distance
	check_eq(boss._struck_part(point), boss.parts.rotor_l, "blade impact damages its rotor module")
	boss.take_hit(_shell(point, Vector3.DOWN))
	from = _on(boss, tip + Vector3.UP * 5.0)
	to = _on(boss, tip + Vector3.DOWN * 5.0)
	check_eq(boss.hit_test(from, to), -1.0, "destroyed outboard rotor no longer blocks shots")
	check(boss._live("rotor_r"), "opposite rotor is unaffected")


func test_gunship_ignores_zero_damage_and_invulnerable_hits() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var hit := _shell(_on(boss, boss.parts.rotor_l.offset))
	hit.damage = 0.0
	boss.take_hit(hit)
	check_eq(boss.hp, boss.max_hp, "zero-damage rocket contact does not become cannon damage")
	check(boss._live("rotor_l"), "zero damage does not destroy a rotor")
	hit.damage = 110.0
	boss.invulnerable = true
	boss.take_hit(hit)
	check_eq(boss.hp, boss.max_hp, "invulnerability also protects boss hull")
	check(boss._live("rotor_l"), "invulnerability protects modules")


func test_colossus_cannon_uses_full_damage_through_caps_and_on_core() -> void:
	var world := stage()
	var boss := _colossus(world)
	var node: Colossus.Part = boss.parts[0]
	_hit_part_with(boss, node, _shell(Vector3.ZERO))
	check_eq(node.cap, 0.0, "110 damage pops the cap")
	check_near(node.hp, 90.0, 0.01, "remaining 10 damage reaches the node")
	var hit := _shell(Vector3.ZERO)
	hit.damage = Armament.SHELL_DAMAGE
	for part: Colossus.Part in boss.parts:
		_hit_part_with(boss, part, hit)
		check(part.cap == 0.0 and part.hp == 0.0, "full-power shell destroys cap and node together")
		check_eq(boss.core.hp, Colossus.CORE_HP, "node overkill does not bypass the core phase")
	check(boss.core.mesh.visible, "destroying all nodes still exposes the core")
	check_eq(boss.hp, Colossus.CORE_HP, "remaining health is exactly the exposed core")
	var marks: Array = boss.get_meta("phase_marks")
	check_near(boss.hp / boss.max_hp, marks[0], 0.001, "core phase mark includes the caps")
	_hit_part_with(boss, boss.core, _shell(Vector3.ZERO))
	check_near(boss.core.hp, Colossus.CORE_HP - 110.0, 0.01, "core takes actual shell damage instead of a fixed share")
	_hit_part(boss, boss.core, Hit.Kind.BULLET, 40.0)
	check_near(boss.core.hp, Colossus.CORE_HP - 150.0, 0.01, "core takes full machine-gun damage too")
	hit.pierce = true
	_hit_part_with(boss, boss.core, hit)
	check_eq(boss.hp, 0.0, "full-power shell kills the exposed core")
	check(boss._dying > 0.0, "lethal damage retains the collapse sequence")


func _hit_part_with(boss: Colossus, part: Colossus.Part, hit: Hit) -> void:
	hit.position = boss.global_transform * part.offset
	boss.take_hit(hit)


func test_gunship_crash_clears_stage() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
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
	var boss := _gunship(world)
	boss.phase = Gunship.Phase.STRIPPED
	boss._pop_flares()
	var flares := world.enemies.filter(func(e: Entity) -> bool: return e is Flare)
	check(flares.size() >= 4, "pops a spread of flares")
	check(flares.all(func(e: Entity) -> bool: return e.team == Entity.Team.ENEMY), "flares are targets for shells")


func test_gunship_resists_machine_guns_and_is_weak_to_fragments() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var coax := Hit.make(Hit.Kind.BULLET, 10.0, boss.global_position)
	coax.caliber = 20
	var fragment := Hit.make(Hit.Kind.FRAGMENT, 10.0, boss.global_position)
	check_near(boss.damage_multiplier(coax), 0.4, 0.001, "20 mm coax only scratches the gunship")
	check_near(boss.damage_multiplier(fragment), 1.5, 0.001, "airburst fragments shred it")
