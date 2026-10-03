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


## A main-gun round as the tank fires it: a plain APHE shell, or with `power` 1.0 the full charge.
func _round(power := 0.0) -> Hit:
	var hit := Hit.make(Hit.Kind.SHELL, Armament.SHELL_DAMAGE * lerpf(Armament.APHE_DAMAGE.x, Armament.APHE_DAMAGE.y, power), Vector3.ZERO)
	hit.caliber = 100
	hit.power = power
	return hit


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
	check_eq(boss.max_hp, 1800.0, "health bar includes all three caps, nodes and the core")
	_hit_part(boss, node, Hit.Kind.SHELL, 60.0)
	check_eq(node.hp, Colossus.NODE_HP, "capped node takes no damage")
	check_near(node.cap, Colossus.CAP_HP - 60.0, 0.01, "cap absorbs the hit")
	check_near(boss.hp, boss.max_hp - 60.0, 0.01, "cap damage immediately lowers the health bar")
	_hit_part(boss, node, Hit.Kind.FIRE, Colossus.CAP_HP / 4.0, true)
	check(node.cap <= 0.0, "fire burns the cap off fast (4x)")
	check_near(node.hp, Colossus.NODE_HP - 15.0, 0.01, "the cap's last 22.5 fire damage burns it; 15 reaches the node")
	_hit_part(boss, node, Hit.Kind.SHELL, 50.0)
	check_near(node.hp, Colossus.NODE_HP - 65.0, 0.01, "the burning node takes full damage")


func test_colossus_unburnt_weak_points_shrug_off_coax() -> void:
	var world := stage()
	var boss := _colossus(world)
	for i in 3:
		var node: Colossus.Part = boss.parts[i]
		var hit := Hit.make(Hit.Kind.BULLET, 40.0, Vector3.ZERO)
		hit.caliber = [8, 15, 20][i]
		_hit_part_with(boss, node, hit)
		check_near(node.cap, Colossus.CAP_HP - 10.0, 0.01, "%d mm deals a quarter to the unburnt cap" % hit.caliber)
		node.burn = Colossus.BURN_TIME
		_hit_part_with(boss, node, hit)
		check_near(node.cap, Colossus.CAP_HP - 50.0, 0.01, "%d mm deals full damage once the node burns" % hit.caliber)
		hit.damage = 200.0
		_hit_part_with(boss, node, hit)
		check_eq(node.cap, 0.0, "cap is depleted")
		check_near(node.hp, Colossus.NODE_HP - 100.0, 0.01, "remaining bullet damage reaches the node")
	check_near(boss.hp, boss.max_hp - 3 * (Colossus.CAP_HP + 100.0), 0.01, "health bar loses all the accepted bullet damage")


func test_colossus_fire_keeps_a_node_burning_for_a_while() -> void:
	var world := stage()
	var boss := _colossus(world)
	var node: Colossus.Part = boss.parts[0]
	_hit_part(boss, node, Hit.Kind.FIRE, 1.0, true)
	check_eq(node.burn, Colossus.BURN_TIME, "fire sets the node alight")
	boss.stagger = 0.0
	boss._next_attack = 1000.0
	boss.behave(Colossus.BURN_TIME + 0.1)
	check_eq(node.burn, 0.0, "and it burns out")
	var other: Colossus.Part = boss.parts[1]
	check_eq(other.burn, 0.0, "fire on one node leaves the others unburnt")


func test_colossus_exact_cap_break_and_small_cannon_hits() -> void:
	var world := stage()
	var boss := _colossus(world)
	var node: Colossus.Part = boss.parts[0]
	node.burn = Colossus.BURN_TIME
	var hit := _shell(Vector3.ZERO)
	hit.damage = Armament.SHELL_DAMAGE / Colossus.ROUND_DAMAGE
	_hit_part_with(boss, node, hit)
	check_eq(node.cap, Colossus.CAP_HP - 1.0, "100 mm caliber does not fabricate minimum damage")
	hit.damage = (Colossus.CAP_HP - 1.0) * Armament.SHELL_DAMAGE / Colossus.ROUND_DAMAGE
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
	check_near(node.hp, Colossus.NODE_HP - 2.5, 0.01, "37.5 damage burns the cap; the remaining 2.5 is not multiplied")


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


## A fighting colossus (free to attack, but choosing nothing on its own) and the tank placed in the lane `u`.
func _fighter(world: World, u := 0.0) -> Colossus:
	var boss := _colossus(world)
	boss.stagger = 0.0
	boss._next_attack = 1000.0
	_place(world, u)
	return boss


func _place(world: World, u: float, offset := 4.0) -> Tank:
	var tank := world.player
	tank.invuln = 0.0
	tank.tail.destroyed = true # Its hit center is where a grab aims, and the test moves that by hand.
	tank.course_u = u
	tank.course_offset = offset
	tank.global_position = Course.ground_at(world.rail.d + offset, u)
	return tank


func _step(boss: Colossus, seconds: float) -> void:
	var tank := boss.player()
	for i in roundi(seconds * 60.0):
		tank.invuln = maxf(0.0, tank.invuln - 1.0 / 60.0)
		boss.behave(1.0 / 60.0)


## Armor the tank lost, as a share of the strike's damage: its facing scales a hit between 0.6 and 1.4.
func _near_strike(lost: float, damage: float, message: String) -> void:
	check(lost >= damage * 0.6 - 0.01 and lost <= damage * 1.4 + 0.01, "%s (lost %.1f of a %.0f strike)" % [message, lost, damage])


func _unlocked(phase: int) -> Array:
	return Colossus.UNLOCK.keys().filter(func(k: int) -> bool: return Colossus.UNLOCK[k] <= phase)


func _lose_nodes(boss: Colossus, count: int) -> void:
	for i in count:
		boss.parts[i].hp = 0.0


func test_colossus_leaves_a_charge_window_after_each_attack() -> void:
	var world := stage()
	var boss := _fighter(world)
	var crawlers := world.enemies.size()
	for attack in Colossus.UNLOCK:
		if attack == Colossus.Attack.WALL:
			continue # Passive: it drifts on while the next attack comes.
		boss._begin(attack)
		boss._end_attack()
		check(boss._next_attack >= Colossus.WINDOW, "attack %d is followed by at least %.1f s of quiet" % [attack, Colossus.WINDOW])
		boss._next_attack = Colossus.WINDOW
		_step(boss, Colossus.WINDOW - 2.0 / 60.0)
		check(boss._moves.is_empty(), "no new attack begins inside the window")
	check_eq(world.enemies.size(), crawlers, "and nothing is spawned in it")


func test_colossus_phase_gates_its_attacks() -> void:
	var world := stage()
	var boss := _fighter(world)
	var most := 0
	for phase in 4:
		_lose_nodes(boss, phase)
		check_eq(boss._phase(), phase, "%d lost nodes make phase %d" % [phase, phase])
		var seen := {}
		var most_at_once := 0
		for i in 400:
			boss._end_attack()
			boss._choose_attack()
			most_at_once = maxi(most_at_once, boss._moves.size())
			for move: Colossus.Move in boss._moves:
				seen[move.kind] = true
			check(boss._moves.filter(func(m: Colossus.Move) -> bool: return m.kind in Colossus.TENDRIL_ATTACKS).size() <= 1, "one tendril at a time")
		boss._end_attack()
		var expected := _unlocked(phase)
		expected.sort()
		var got := seen.keys()
		got.sort()
		check_eq(got, expected, "phase %d picks exactly the attacks it has unlocked" % phase)
		check_eq(most_at_once, 2 if phase == 3 else 1, "attacks combine only in the last phase")
		check(expected.size() > most, "each phase has more attacks than the one before")
		most = expected.size()


func test_colossus_rests_for_less_as_it_loses_nodes() -> void:
	var world := stage()
	var boss := _fighter(world)
	var longest := []
	for phase in 4:
		_lose_nodes(boss, phase)
		var gap := 0.0
		for i in 100:
			var move := Colossus.Move.new()
			boss._moves.append(move)
			boss._finish(move)
			gap = maxf(gap, boss._next_attack)
			check(boss._next_attack >= Colossus.WINDOW, "rests at least the charge window")
		longest.append(gap)
	check(longest[3] < longest[0] - 0.2, "the longest rest shrinks from %.2f s to %.2f s" % [longest[0], longest[3]])
	for i in 3:
		check(longest[i + 1] <= longest[i] + 0.001, "and never grows with a lost node")


func test_colossus_hits_cost_a_quarter_to_a_third_of_the_armor() -> void:
	for damage: float in [Colossus.STRIKE_DAMAGE, Colossus.SPIKE_DAMAGE, Colossus.GEYSER_DAMAGE, Colossus.SLAM_DAMAGE, Colossus.GRAB_DAMAGE]:
		check(damage >= 25.0 and damage <= 35.0, "a strike of %.0f is 25 to 35 armor" % damage)
	check(Colossus.WALL_DPS * 2.0 * Colossus.WALL_DEPTH / Colossus.WALL_SPEED >= 20.0, "crossing the wall costs about a hit")


func test_colossus_spikes_follow_cracks_and_hurt_only_where_they_erupt() -> void:
	var world := stage()
	var boss := _fighter(world)
	var tank := world.player
	boss._begin(Colossus.Attack.SPIKES)
	var move: Colossus.Move = boss._moves[0]
	check(move.bursts.size() >= 3 * 8, "three cracks of spikes run toward the tank")
	var first: Colossus.Burst = move.bursts[0]
	for burst in move.bursts:
		check(burst.at - burst.warn_at >= Colossus.SPIKE_DELAY - 0.001, "every spike is marked at least %.2f s before it erupts" % Colossus.SPIKE_DELAY)
		if burst.at < first.at:
			first = burst
	tank.global_position = first.position
	_step(boss, first.at - 0.05)
	check(first.shown and not first.done, "the crack reached the spot and the spike has not come yet")
	check_eq(tank.hp, tank.max_hp, "standing on a marked spot is safe until it erupts")
	_step(boss, 0.1)
	check(first.done, "the spike erupts")
	_near_strike(tank.max_hp - tank.hp, Colossus.SPIKE_DAMAGE, "and costs the tank standing on it a hit")
	boss._end_attack()
	tank.hp = tank.max_hp
	boss._begin(Colossus.Attack.SPIKES)
	_place(world, 30.0)
	for i in 600:
		_step(boss, 1.0 / 60.0)
		if boss._moves.is_empty():
			break
	check(boss._moves.is_empty(), "the cracks run out")
	check_eq(tank.hp, tank.max_hp, "a tank off every line is not touched")


func test_colossus_geysers_chase_the_tank_and_hurt_only_a_tank_that_stays() -> void:
	var world := stage()
	var boss := _fighter(world, -8.0)
	var tank := world.player
	_lose_nodes(boss, 1)
	boss._begin(Colossus.Attack.GEYSERS)
	var move: Colossus.Move = boss._moves[0]
	var seen := 0
	var spots: Array[Vector3] = []
	for i in 600:
		_step(boss, 1.0 / 60.0)
		if move.bursts.size() > seen:
			var burst: Colossus.Burst = move.bursts[seen]
			spots.append(burst.position)
			check_near(burst.position.distance_to(Vector3(tank.global_position.x, burst.position.y, tank.global_position.z)), 0.0, 0.01, "geyser %d is laid where the tank is" % seen)
			check_near(burst.at - burst.warn_at, Colossus.GEYSER_WARN, 0.001, "and marked %.1f s before it erupts" % Colossus.GEYSER_WARN)
			seen += 1
			var best := 0.0
			var best_gap := -1.0
			for u: float in [-14.0, -7.0, 0.0, 7.0, 14.0]:
				var gap := 1000.0
				for spot in spots:
					gap = minf(gap, Course.ground_at(world.rail.d + 4.0, u).distance_to(spot))
				if gap > best_gap:
					best = u
					best_gap = gap
			_place(world, best) # Keeps moving: each geyser lands where it was, away from the next.
		if boss._moves.is_empty():
			break
	check_eq(seen, 4, "a geyser chase with one node lost has four geysers")
	check(spots[0].distance_to(spots[1]) > 10.0, "each lies where the tank was, not where it is going")
	check_eq(tank.hp, tank.max_hp, "a tank that keeps moving is never caught")
	cleanup()
	var world2 := stage()
	var still := _fighter(world2, 0.0)
	still._begin(Colossus.Attack.GEYSERS)
	_step(still, 0.5)
	var hp := world2.player.hp
	_step(still, 0.5)
	check_eq(world2.player.hp, hp, "a geyser's circle swells before it hurts")
	_step(still, 0.35)
	_near_strike(world2.player.max_hp - world2.player.hp, Colossus.GEYSER_DAMAGE, "a tank that stays is caught by the first geyser")


func test_colossus_slam_marks_the_lane_and_hurts_only_inside_it() -> void:
	var world := stage()
	var boss := _fighter(world, 3.0)
	var tank := world.player
	boss._begin(Colossus.Attack.SLAM)
	var move: Colossus.Move = boss._moves[0]
	check_eq(move.props.size(), 1, "a shadow strip is laid along the lane")
	_step(boss, Colossus.SLAM_RISE - 0.1)
	check(boss._tip_open, "the tendril hangs raised over the lane")
	check_eq(tank.hp, tank.max_hp, "nothing hurts while it rises")
	_step(boss, 1.0)
	check(boss._moves.is_empty(), "the slam ends")
	_near_strike(tank.max_hp - tank.hp, Colossus.SLAM_DAMAGE, "a tank left in the lane is slammed")
	cleanup()
	var world2 := stage()
	var dodge := _fighter(world2, 3.0)
	dodge._begin(Colossus.Attack.SLAM)
	_step(dodge, Colossus.SLAM_RISE - 0.1)
	var drifted := _place(world2, 3.0 + Colossus.SLAM_HALF_WIDTH + 1.0)
	_step(dodge, 1.0)
	check_eq(drifted.hp, drifted.max_hp, "a tank that drifted out of the lane is not touched")


func test_colossus_slam_is_cut_by_a_charged_shot_on_the_raised_tip_only() -> void:
	var world := stage()
	var boss := _fighter(world, 0.0)
	var tank := world.player
	boss._begin(Colossus.Attack.SLAM)
	_step(boss, 0.5)
	boss.take_hit(_shell(boss._tendril_tip))
	check_eq(boss._moves.size(), 1, "a plain shell does not cut it")
	boss.take_hit(_charged(boss._tendril_tip + Vector3(0, 0, 20)))
	check_eq(boss._moves.size(), 1, "a charged shot that misses the tip does not either")
	boss.take_hit(_charged(boss._tendril_tip))
	check(boss._moves.is_empty() and not boss._tip_open, "a charged shot on the tip cuts it")
	_step(boss, 2.0)
	check_eq(tank.hp, tank.max_hp, "the cut slam never lands")
	check(not boss.aim_parts().has("tip"), "and the tip is no longer a target")
	boss._begin(Colossus.Attack.SLAM)
	_step(boss, 0.5)
	check(boss.aim_parts().has("tip"), "a raised tip can be locked")
	check(boss.hit_test(boss._tendril_tip + Vector3(0, 0, 10), boss._tendril_tip, 0.0) >= 0.0, "and shots collide with it")


func test_colossus_wall_hurts_inside_its_cloud_not_in_the_gap_or_while_it_grows() -> void:
	var world := stage()
	var boss := _fighter(world)
	boss._begin(Colossus.Attack.WALL)
	var move: Colossus.Move = boss._moves[0]
	check(move.passive, "the wall does not hold up the next attack")
	check(absf(move.lane) <= 9.0, "its gap is on the road")
	var inside := move.lane + (8.0 if move.lane < 0.0 else -8.0)
	var tank := _place(world, inside, move.d - 3.4 - world.rail.d)
	_step(boss, Colossus.WALL_WIND - 0.1)
	check_eq(tank.hp, tank.max_hp, "the growing wall does not hurt yet")
	while not boss._moves.is_empty():
		_step(boss, 1.0 / 60.0)
	var lost := tank.max_hp - tank.hp
	check(lost >= 8.0 and lost <= 45.0, "crossing the cloud costs about a hit (lost %.1f)" % lost)
	cleanup()
	var world2 := stage()
	var boss2 := _fighter(world2)
	boss2._begin(Colossus.Attack.WALL)
	var move2: Colossus.Move = boss2._moves[0]
	var safe := _place(world2, move2.lane, move2.d - 3.4 - world2.rail.d)
	while not boss2._moves.is_empty():
		_step(boss2, 1.0 / 60.0)
	check_eq(safe.hp, safe.max_hp, "a tank in the gap takes nothing")
	cleanup()
	var world3 := stage()
	var boss3 := _fighter(world3)
	boss3._begin(Colossus.Attack.WALL)
	var move3: Colossus.Move = boss3._moves[0]
	var beside := _place(world3, Colossus.WALL_HALF + 1.5, move3.d - 3.4 - world3.rail.d)
	while not boss3._moves.is_empty():
		_step(boss3, 1.0 / 60.0)
	check_eq(beside.hp, beside.max_hp, "nor does one past the wall's end")


func test_colossus_grab_drags_a_tank_in_until_a_drift_or_a_shot_frees_it() -> void:
	var world := stage()
	var boss := _fighter(world)
	var tank := world.player
	boss._begin(Colossus.Attack.GRAB)
	var move: Colossus.Move = boss._moves[0]
	_step(boss, Colossus.GRAB_REACH - 0.1)
	check(boss._tip_open and move.held == 0.0, "the tendril hovers over the tail before it drops")
	_step(boss, Colossus.GRAB_DROP + 0.2)
	check(move.held > 0.0, "a tank that stayed is caught")
	var offset := tank.course_offset
	_step(boss, 0.5)
	check(tank.course_offset > offset + 4.0, "and dragged toward the colossus")
	tank._drift = 0.3
	_step(boss, 0.05)
	check(boss._moves.is_empty(), "a drift frees it")
	check_eq(tank.hp, tank.max_hp, "with no crush")
	cleanup()
	var world2 := stage()
	var boss2 := _fighter(world2)
	boss2._begin(Colossus.Attack.GRAB)
	_step(boss2, Colossus.GRAB_REACH + Colossus.GRAB_DROP + 0.3)
	boss2.take_hit(_shell(boss2._tendril_tip))
	check(boss2._moves.is_empty(), "a cannon round on the tendril frees it")
	cleanup()
	var world3 := stage()
	var boss3 := _fighter(world3)
	boss3._begin(Colossus.Attack.GRAB)
	_step(boss3, Colossus.GRAB_REACH + Colossus.GRAB_DROP + Colossus.GRAB_HOLD + 0.2)
	_near_strike(world3.player.max_hp - world3.player.hp, Colossus.GRAB_DAMAGE, "dragged all the way in it is crushed")
	cleanup()
	var world4 := stage()
	var boss4 := _fighter(world4)
	boss4._begin(Colossus.Attack.GRAB)
	_step(boss4, Colossus.GRAB_REACH + 0.1)
	var away := _place(world4, 12.0)
	_step(boss4, 0.7)
	check(boss4._moves.is_empty(), "the missed grab lets go")
	check_eq(away.hp, away.max_hp, "a tank that moved before the drop takes nothing")
	check_eq(away.course_offset, 4.0, "and is not dragged")


func test_colossus_sweep_costs_an_ignoring_tank_a_third_of_its_armor() -> void:
	var world := stage()
	var boss := _colossus(world)
	var tank := world.player
	tank.invuln = 0.0
	var before := tank.hp
	var lash := Hit.make(Hit.Kind.RAM, Colossus.STRIKE_DAMAGE, tank.global_position)
	lash.source = boss
	var scale := tank.damage_multiplier(lash)
	tank.take_hit(lash)
	check_near(Colossus.STRIKE_DAMAGE, tank.max_hp / 3.0, 1.0, "a strike is a third of the armor before facing")
	check_near(before - tank.hp, Colossus.STRIKE_DAMAGE * scale, 0.01, "and the tank loses exactly that, scaled by facing")


func test_colossus_heat_interrupts_sweep() -> void:
	var world := stage()
	var boss := _fighter(world)
	boss._begin(Colossus.Attack.SWEEP)
	boss._moves[0].time = 0.5
	var heat := Hit.make(Hit.Kind.SHELL, 10.0, boss.global_position)
	heat.stagger = 1.0
	boss.take_hit(heat)
	check(boss._moves.is_empty(), "heavy stagger cancels a telegraphed sweep")


func _gunship(world: World) -> Gunship:
	world.director._start_boss({"kind": "gunship"})
	var boss := world.boss as Gunship
	boss._next_attack = 1000.0
	return boss


## One hovering high enough that a shell fired level at it cannot meet the ground first.
func _hovering(world: World) -> Gunship:
	var boss := _gunship(world)
	boss.global_position.y += 20.0
	return boss


func _shell(at: Vector3, direction := Vector3.FORWARD) -> Hit:
	var hit := Hit.make(Hit.Kind.SHELL, 110.0, at, direction)
	hit.caliber = 100
	return hit


func _charged(at: Vector3, direction := Vector3.FORWARD) -> Hit:
	var hit := _shell(at, direction)
	hit.power = 1.0
	return hit


## A world point on the airframe at a model-local spot.
func _on(boss: Gunship, local: Vector3) -> Vector3:
	return boss.model.global_transform * local


## `count` full-charge shells into a module.
func _cannon_on(boss: Gunship, part: String, count: int) -> void:
	for i in count:
		boss.take_hit(_charged(_on(boss, boss.parts[part].offset)))


func test_gunship_every_full_charge_takes_the_same_hull_wherever_it_lands() -> void:
	var share := Gunship.CANNON_SHARE * 1600.0
	for spot in [Vector3(-2.8, 0.0, 0.8), Vector3(0, 0.4, -7.0), Vector3(0, 0.3, 7.0), Vector3(0, 0.5, -1.8)]:
		var world := stage("boss")
		var boss := _gunship(world)
		boss.take_hit(_charged(_on(boss, spot)))
		check_near(boss.max_hp - boss.hp, share, 0.5, "a full charge at %s takes one share, plate or not" % spot)
		cleanup()
	var world := stage("boss")
	var boss := _gunship(world)
	var flank := Vector3(-2.8, 0.0, 0.8)
	boss.take_hit(_charged(_on(boss, flank)))
	check(not boss._live("era_left"), "the full charge pops the left plate")
	check(boss._live("era_right") and boss._live("era_front"), "other plates hold")
	var coax := Hit.make(Hit.Kind.BULLET, 10.0, _on(boss, Vector3(0, 0.3, 7.0)))
	coax.caliber = 20
	var hp := boss.hp
	boss.take_hit(coax)
	check_eq(boss.hp, hp, "machine guns glance off the airframe")


func test_gunship_plain_shells_crack_a_plate_and_two_pop_it() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var nose := _on(boss, Vector3(0, 0.4, -7.0))
	boss.take_hit(_shell(nose))
	check(boss._live("era_front"), "one plain shell leaves the nose plate standing")
	check_near(boss.parts.era_front.hp, Gunship.ERA_HP * 0.5, 0.01, "but cracked half through")
	check_near(boss.max_hp - boss.hp, boss.max_hp * Gunship.CANNON_SHARE * Gunship.QUICK_WEIGHT, 0.5, "a plain shell is half a hit on the hull")
	boss.take_hit(_shell(nose))
	check(not boss._live("era_front"), "the second plain shell pops it")


func test_gunship_heat_pops_a_plate_in_one_hit() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var heat := _shell(_on(boss, Vector3(0, 0.4, -7.0)))
	heat.pierce = true
	boss.take_hit(heat)
	check(not boss._live("era_front"), "a HEAT round pops a plate outright")


func test_gunship_ten_full_charges_bring_an_infected_one_down() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	boss.phase = Gunship.Phase.INFECTED
	var tail := _on(boss, Vector3(0, 0.3, 7.0))
	for i in 10:
		check(boss._crash <= 0.0, "still flying before charge %d" % (i + 1))
		boss.take_hit(_charged(tail))
	check(boss._crash > 0.0, "ten full charges on bare airframe start the crash")


func test_gunship_fight_lasts_six_to_fifteen_full_charges_on_any_aim() -> void:
	var spots: Array[String] = ["tail", "nose", "flank", "rotor_l", "rotor_r", "pod_l", "chin", "bay", "gatling_r", "nose_gun"]
	for start in spots.size():
		var world := stage("boss")
		var boss := _gunship(world)
		var hits := 0
		while boss._crash <= 0.0 and hits < 40:
			var name := spots[(start + hits * 3) % spots.size()]
			var spot: Vector3 = Vector3(0, 0.3, 7.0) if name == "tail" else Vector3(0, 0.4, -7.0) if name == "nose" else Vector3(-2.8, 0.0, 0.8) if name == "flank" else boss.parts[name].offset
			boss.take_hit(_charged(_on(boss, spot)))
			boss.age += 1.0
			hits += 1
		check(hits >= 6 and hits <= 15, "aim order %d: %d full charges bring it down" % [start, hits])
		cleanup()


func test_gunship_one_shell_never_counts_for_more_than_one_hit() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var tail := _on(boss, Vector3(0, 0.3, 7.0))
	var blast := _charged(tail)
	blast.kind = Hit.Kind.BLAST
	blast.weapon = "cannon"
	boss.take_hit(_charged(tail))
	boss.take_hit(blast)
	check_near(boss.max_hp - boss.hp, boss.max_hp * Gunship.CANNON_SHARE, 0.5, "a shell's blast after its direct hit adds nothing")
	boss.age += 1.0
	boss.hp = boss.max_hp
	boss.take_hit(blast)
	check_near(boss.max_hp - boss.hp, boss.max_hp * Gunship.CANNON_SHARE * Gunship.QUICK_WEIGHT, 0.5, "a blast alone is half a hit, however charged")
	var rotor: float = boss.parts.rotor_l.hp
	boss.age += 1.0
	blast.position = _on(boss, boss.parts.rotor_l.offset)
	boss.take_hit(blast)
	check_eq(boss.parts.rotor_l.hp, rotor, "a blast never reaches into a module")
	boss.age += 1.0
	boss.hp = boss.max_hp
	boss.take_hit(_shell(tail))
	check_near(boss.max_hp - boss.hp, boss.max_hp * Gunship.CANNON_SHARE * Gunship.QUICK_WEIGHT, 0.5, "a quick shell is half a hit")


func test_gunship_holds_a_still_charge_window_after_each_attack() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	for phase in Gunship.Phase.values():
		boss.phase = phase
		boss._attack = Gunship.Attack.GUN
		boss._end_attack()
		var window: float = Gunship.WINDOW[phase]
		check(boss._next_attack >= window, "phase %d waits at least %.1f s before the next attack" % [phase, window])
		check(window >= 1.6, "a full charge (0.95 s) and its aim fit in the window")
		boss._next_attack = window
		var shots := world.projectiles.filter(func(p: Projectile) -> bool: return p.team == Entity.Team.ENEMY).size()
		for i in int(window * 60.0) - 2:
			boss.behave(1.0 / 60.0)
			check_eq(boss._attack, Gunship.Attack.NONE, "no attack starts inside the window")
		check_eq(world.projectiles.filter(func(p: Projectile) -> bool: return p.team == Entity.Team.ENEMY).size(), shots, "nothing is fired inside the window")


func test_gunship_drone_call_in_rises_low_in_front_of_the_tank() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	boss.phase = Gunship.Phase.STRIPPED
	boss._attack = Gunship.Attack.DRONES
	boss._attack_time = 1.0
	boss._update_attack(0.0, world.player)
	var drones := world.enemies.filter(func(e: Entity) -> bool: return e is FpvDrone)
	check(drones.size() >= 3, "a handful of drones is called in")
	var ahead := -world.player.global_basis.z
	for drone: Entity in drones:
		var offset := drone.global_position - world.player.global_position
		check(offset.dot(ahead) > 15.0, "each rises ahead of the tank")
		check(offset.length() > Tank.CIWS_RANGE, "outside the laser's reach")
		check(drone.global_position.y - Course.height_at(drone.global_position) < 3.0, "at ground level")


func test_gunship_phases_follow_hull() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var tail := _on(boss, Vector3(0, 0.3, 7.0))
	for i in 2:
		boss.take_hit(_charged(tail))
	check_eq(boss.phase, Gunship.Phase.HUNTER, "a fifth of its hull gone: it still hunts")
	boss.take_hit(_charged(tail))
	boss.take_hit(_charged(tail))
	check_eq(boss.phase, Gunship.Phase.STRIPPED, "under seven tenths: it closes in")
	for i in 3:
		boss.take_hit(_charged(tail))
	check_eq(boss.phase, Gunship.Phase.INFECTED, "under a third and a half: it turns")


func test_gunship_modules_change_the_fight() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	_cannon_on(boss, "chin", Gunship.MODULE_HITS)
	check(not boss._live("chin"), "two shells wreck the chin drum")
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


func test_gunship_rotor_takes_three_cannon_hits() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	_cannon_on(boss, "rotor_l", 2)
	check(boss._live("rotor_l"), "a rotor survives two cannon hits")
	check_near(boss.parts.rotor_l.hp, Gunship.MODULE_HP.rotor_l / 3.0, 0.01, "with one hit left")
	check_near(boss.max_hp - boss.hp, 2.0 * boss.max_hp * Gunship.CANNON_SHARE, 0.5, "the airframe behind a module takes the same share")
	_cannon_on(boss, "rotor_l", 1)
	check(not boss._live("rotor_l"), "the third wrecks it")


func test_gunship_other_modules_take_two_cannon_hits() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	for part in ["nose_gun", "chin", "pod_l", "pod_r", "bay"]:
		_cannon_on(boss, part, 1)
		check(boss._live(part), "%s survives one cannon hit" % part)
		_cannon_on(boss, part, 1)
		check(not boss._live(part), "%s falls to the second" % part)


func test_gunship_coax_silences_a_weapon_slowly_and_never_touches_the_rest() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var spec: Dictionary = Armament.GUNS[Armament.tier_calibers(0)[0]]
	var plates := Gunship.PLATES.map(func(name: String) -> float: return boss.parts[name].hp)
	var time := 0.0
	while boss._live("chin") and time < 600.0:
		var round := Hit.make(Hit.Kind.BULLET, spec.damage, _on(boss, boss.parts.chin.offset))
		round.caliber = Armament.tier_calibers(0)[0]
		boss.take_hit(round)
		time += spec.interval
	check(time >= 8.0, "tier-1 coax takes %.1f s to wreck the ATGM drum" % time)
	check(time < 600.0, "but it does wreck it")
	for spot: Vector3 in [boss.parts.era_front.offset, boss.parts.era_left.offset, boss.parts.rotor_l.offset, Vector3(0, 0.3, 7.0)]:
		var round := Hit.make(Hit.Kind.BULLET, 12.0, _on(boss, spot))
		round.caliber = 20
		for i in 200:
			boss.take_hit(round)
	check_eq(boss.hp, boss.max_hp, "no machine-gun round ever scratches the hull")
	check_eq(Gunship.PLATES.map(func(name: String) -> float: return boss.parts[name].hp), plates, "or a plate")
	check_eq(boss.parts.rotor_l.hp, Gunship.MODULE_HP.rotor_l, "or a rotor")


func test_gunship_airburst_and_canister_glance_off_everything() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var modules := Gunship.MODULE_HP.keys().map(func(name: String) -> float: return boss.parts[name].hp)
	var fragment := Hit.make(Hit.Kind.FRAGMENT, 400.0, _on(boss, boss.parts.chin.offset))
	fragment.caliber = 30
	for i in roundi(Armament.AIRBURST_FRAGMENTS.y):
		boss.take_hit(fragment)
	var pellet := Hit.make(Hit.Kind.BULLET, 90.0, _on(boss, boss.parts.nose_gun.offset))
	pellet.caliber = 20
	pellet.weapon = "canister"
	for i in 50:
		boss.take_hit(pellet)
	var burst := Hit.make(Hit.Kind.BLAST, 3000.0, _on(boss, boss.parts.chin.offset))
	burst.caliber = 100
	burst.weapon = "airburst"
	boss.take_hit(burst)
	var direct := Hit.make(Hit.Kind.SHELL, 140.0, _on(boss, boss.parts.chin.offset))
	direct.caliber = 100
	direct.weapon = "airburst"
	boss.take_hit(direct)
	check_eq(boss.hp, boss.max_hp, "a whole airburst and canister volley leave the hull alone")
	check_eq(Gunship.MODULE_HP.keys().map(func(name: String) -> float: return boss.parts[name].hp), modules, "and every module")
	check(Gunship.PLATES.all(func(name: String) -> bool: return boss._live(name)), "and every plate")


func test_gunship_wreck_blasts_rams_the_tail_and_flames_cannot_shortcut_the_fight() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	for kind in [Hit.Kind.BLAST, Hit.Kind.RAM, Hit.Kind.TAIL, Hit.Kind.THROWN, Hit.Kind.FIRE, Hit.Kind.LASER]:
		var hit := Hit.make(kind, 9999.0, _on(boss, Vector3(0, 0.3, 7.0)))
		hit.weapon = "collateral"
		for i in 100:
			boss.take_hit(hit)
	check(boss.max_hp - boss.hp <= Gunship.SIDE_RATE, "all of them together take %.0f hull in a second" % (boss.max_hp - boss.hp))
	check(boss.max_hp - boss.hp > 0.0, "but they do hurt")
	check(Gunship.SIDE_RATE < boss.max_hp * Gunship.CANNON_SHARE * Gunship.QUICK_WEIGHT * 0.25, "far below a quick shell")
	boss.age += 1.0
	boss.hp = boss.max_hp
	var lash := Hit.make(Hit.Kind.TAIL, 90.0, _on(boss, Vector3(-2.8, 0.0, 0.8)))
	boss.take_hit(lash)
	check(boss._live("era_left"), "the tail does not pop a plate")
	check_near(boss.max_hp - boss.hp, Gunship.SIDE_RATE, 0.01, "a lash a second later takes the rate's share, not its 90")


func test_gunship_blast_before_the_direct_hit_still_totals_one_shell() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var tail := _on(boss, Vector3(0, 0.3, 7.0))
	var blast := _charged(tail)
	blast.kind = Hit.Kind.BLAST
	blast.weapon = "cannon"
	boss.take_hit(blast)
	boss.take_hit(_charged(tail))
	check_near(boss.max_hp - boss.hp, boss.max_hp * Gunship.CANNON_SHARE, 0.5, "a piercing shell's burst on an enemy in front, then its hit: one share")
	boss.age += 1.0
	boss.hp = boss.max_hp
	boss.take_hit(blast)
	boss.take_hit(_shell(tail))
	check_near(boss.max_hp - boss.hp, boss.max_hp * Gunship.CANNON_SHARE * Gunship.QUICK_WEIGHT, 0.5, "a quick shell after its own blast adds nothing")


## The tank's own main gun fired for real at the hovering gunship, a second apart.
func _shoot(world: World, boss: Gunship, power: float, count: int) -> int:
	var shots := 0
	var tank := world.player
	while boss._crash <= 0.0 and shots < count:
		boss.age += 1.0
		boss.stagger = 1000.0
		var from := boss.global_position + Vector3(0, 0, 30.0)
		var before := world.projectiles.size()
		tank.fire_cannon(from, (_on(boss, Vector3(0, 0.4, 0)) - from).normalized(), power)
		land(world, before)
		shots += 1
	return shots


func test_gunship_real_shells_take_a_steady_count() -> void:
	var world := stage("boss")
	var boss := _hovering(world)
	check_eq(_shoot(world, boss, 1.0, 40), 10, "ten real full charges bring it down")
	cleanup()
	world = stage("boss")
	boss = _hovering(world)
	check_eq(_shoot(world, boss, 0.4, 40), 20, "twenty real quick shells do")
	cleanup()
	world = stage("boss")
	boss = _hovering(world)
	boss.stagger = 1000.0
	world.player.charge_lock = boss
	check_eq(_shoot(world, boss, 1.0, 40), 10, "and ten locked ones")


func test_gunship_losing_rotors_never_shortcuts_the_hull() -> void:
	for phase in Gunship.Phase.values():
		var world := stage("boss")
		var boss := _gunship(world)
		boss.phase = phase
		_cannon_on(boss, "rotor_l", Gunship.ROTOR_HITS)
		_cannon_on(boss, "rotor_r", Gunship.ROTOR_HITS)
		check(boss._crash <= 0.0, "phase %d: both rotors lost does not crash it" % phase)
		check_near(boss.max_hp - boss.hp, 6.0 * boss.max_hp * Gunship.CANNON_SHARE, 0.5, "phase %d: six hits cost six shares, no more" % phase)
		check(not boss._live("rotor_l") and not boss._live("rotor_r"), "phase %d: the rotors stay lost" % phase)
		cleanup()


func test_gunship_emptied_hull_recovers_into_the_next_phase() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	boss.hp = 1.0
	boss.take_hit(_shell(_on(boss, Vector3(0, 0.3, 7.0))))
	check(boss._crash <= 0.0, "an emptied hull does not crash it before the last phase")
	check_eq(boss.phase, Gunship.Phase.STRIPPED, "it recovers into the next phase")
	check_near(boss.hp, boss.max_hp * Gunship.PHASE_MARKS[0], 0.5, "at that phase's entry hull")
	boss.hp = 1.0
	boss.take_hit(_shell(_on(boss, Vector3(0, 0.3, 7.0))))
	check_eq(boss.phase, Gunship.Phase.INFECTED, "and again")
	boss.hp = 1.0
	boss.take_hit(_shell(_on(boss, Vector3(0, 0.3, 7.0))))
	check(boss._crash > 0.0, "an emptied hull crashes it in the last phase")


func test_gunship_rotors_are_independent() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var events: Array[bool] = []
	world.hit_confirmed.connect(func(killed: bool) -> void: events.append(killed))
	boss.phase = Gunship.Phase.STRIPPED # The infected phase's erratic jitter would randomize the lean.
	var hit := _charged(_on(boss, boss.parts.rotor_l.offset))
	hit.source = world.player
	for i in Gunship.ROTOR_HITS:
		boss.take_hit(hit)
	check(not boss._live("rotor_l") and boss._live("rotor_r"), "the left rotor can be destroyed independently")
	check(boss._crash <= 0.0, "one rotor keeps it flying")
	check_eq(events, [false, false, false], "a lost rotor confirms its hits, not a kill")
	boss.stagger = 0.0
	boss._velocity = Vector3.ZERO
	boss.model.rotation.z = 0.0 # Each hit lurches it at random; start level.
	boss.behave(0.1)
	check(boss.model.rotation.z > 0.0, "the gunship banks toward its lost left rotor")
	hit = _charged(_on(boss, boss.parts.rotor_r.offset))
	hit.source = world.player
	for i in Gunship.ROTOR_HITS:
		boss.take_hit(hit)
	check(not boss._live("rotor_r"), "the right rotor goes too")
	check(boss._crash <= 0.0, "with both rotors gone it still flies until the hull is empty")
	check_eq(events, [false, false, false, false, false, false], "every hit confirms, none a kill")


func test_gunship_rotor_blades_can_be_shot_and_destroyed_blades_do_not_block() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	# Outboard blade tip is beyond the nacelle and missile rack hit spheres and the other rotor's reach.
	var tip: Vector3 = boss.parts.rotor_l.offset + Vector3(-(Gunship.ROTOR_RADIUS - 0.5), 0, 0)
	var from := _on(boss, tip + Vector3.UP * 5.0)
	var to := _on(boss, tip + Vector3.DOWN * 5.0)
	var distance := boss.hit_test(from, to)
	check(distance >= 0.0, "shots can hit the thin swept rotor disc")
	var point := from + (to - from).normalized() * distance
	check_eq(boss._struck_part(point), boss.parts.rotor_l, "blade impact damages its rotor module")
	for i in Gunship.ROTOR_HITS:
		boss.take_hit(_charged(_on(boss, tip), Vector3.DOWN)) # The craft lurches under each hit, so aim afresh.
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


func test_colossus_plain_shells_halve_on_unburnt_nodes_but_fire_and_full_charges_do_not() -> void:
	var world := stage()
	var boss := _colossus(world)
	var node: Colossus.Part = boss.parts[0]
	_hit_part_with(boss, node, _round())
	check_near(node.cap, Colossus.CAP_HP - Colossus.ROUND_DAMAGE * 0.5, 0.01, "a plain round is worth half on an unburnt node")
	node.burn = Colossus.BURN_TIME
	_hit_part_with(boss, node, _round())
	check_near(node.cap, Colossus.CAP_HP - Colossus.ROUND_DAMAGE * 1.5, 0.01, "a burning node takes the whole round")
	var other: Colossus.Part = boss.parts[1]
	_hit_part_with(boss, other, _round(1.0))
	check_near(other.cap, Colossus.CAP_HP - Colossus.ROUND_DAMAGE * 2.0, 0.01, "a full charge is two whole rounds on an unburnt node")
	var third: Colossus.Part = boss.parts[2]
	_hit_part_with(boss, third, _round(0.5))
	check_near(third.cap, Colossus.CAP_HP - Colossus.ROUND_DAMAGE * 1.5 * 0.5, 0.01, "a half charge is no full charge")


func test_colossus_core_takes_rounds_and_a_full_charge_counts_double() -> void:
	var world := stage()
	var boss := _colossus(world)
	for part: Colossus.Part in boss.parts:
		part.cap = 0.0
		_hit_part(boss, part, Hit.Kind.SHELL, 999.0)
		check(part.hp == 0.0, "node destroyed")
	check(boss.core.mesh.visible, "destroying all nodes exposes the core")
	check_eq(boss.hp, Colossus.CORE_HP, "remaining health is exactly the exposed core")
	var marks: Array = boss.get_meta("phase_marks")
	check_near(boss.hp / boss.max_hp, marks[0], 0.001, "core phase mark includes the caps")
	_hit_part_with(boss, boss.core, _round())
	check_near(boss.core.hp, Colossus.CORE_HP - Colossus.ROUND_DAMAGE, 0.01, "a plain round takes a whole round off the core")
	_hit_part_with(boss, boss.core, _round(1.0))
	check_near(boss.core.hp, Colossus.CORE_HP - Colossus.ROUND_DAMAGE * 5.0, 0.01, "a full charge takes four rounds: two for the charge, doubled on the open core")
	var hit := Hit.make(Hit.Kind.BULLET, 40.0, Vector3.ZERO)
	hit.caliber = 8
	var before := boss.core.hp
	_hit_part_with(boss, boss.core, hit)
	check_near(before - boss.core.hp, 10.0, 0.01, "an unburnt core shrugs off coax like the nodes")
	boss.core.hp = 1.0
	_hit_part_with(boss, boss.core, _round())
	check_eq(boss.hp, 0.0, "the last round kills the exposed core")
	check(boss._dying > 0.0, "lethal damage retains the collapse sequence")


func _hit_part_with(boss: Colossus, part: Colossus.Part, hit: Hit) -> void:
	hit.position = boss.global_transform * part.offset
	boss.take_hit(hit)


func test_gunship_crash_clears_stage_once_the_breach_has_played_out() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var cleared := [false]
	var fell := [false]
	world.stage_cleared.connect(func() -> void: cleared[0] = true)
	boss.died.connect(func(_e: Entity) -> void: fell[0] = true)
	boss.phase = Gunship.Phase.INFECTED
	boss.hp = 1.0
	var hit := Hit.make(Hit.Kind.SHELL, 50.0, boss.global_position)
	hit.pierce = true
	boss.take_hit(hit)
	check(boss._crash > 0.0, "zero hp starts the crash")
	check(await wait_until(func() -> bool: return fell[0], 60 * 6), "the gunship hits the dam")
	await frames(30)
	check(not cleared[0], "the stage does not clear before the breach lands")
	var ok := await wait_until(func() -> bool: return cleared[0], 60 * 2)
	check(ok, "the stage clears soon after the crash into the dam")


func test_gunship_crashes_into_the_dam_face_in_plain_view() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	await frames(2)
	check(is_instance_valid(Dam.current), "the dam stands in the arena")
	boss.global_position = Course.to_world(Course.ARENA_CENTER_D, 30.0, 20.0)
	boss.phase = Gunship.Phase.INFECTED
	boss.hp = 1.0
	boss.take_hit(_charged(boss.global_position))
	var target := boss._crash_to
	var at := Course.to_course(target)
	check(at.x < Course.DAM_D - Dam.face_z(target.y), "the impact point is in front of the dam face, not inside it")
	check(Course.DAM_D - Dam.face_z(target.y) - at.x < 12.0, "and hugging the face")
	check(target.y > Course.height_at(target) + 6.0, "well above the ground there, up where the camera sees the face")
	check_near(at.y, 30.0, 0.5, "it comes down on the side of the dam it was over")
	check(Course.to_course(Dam.crash_point(500.0)).y <= 60.5, "a far-off crash is pulled toward the middle of the wall")
	var before := world.fx._transients.size()
	var chained := world.fx._delayed.size()
	boss._crash = 0.01
	boss._update_crash(0.1)
	check(world.fx._transients.size() > before + 10, "the impact throws a heap of fireballs and shockwaves")
	check(world.fx._delayed.size() >= chained + 7, "blasts chain on after the first")
	check(boss.dead, "the crash kills the gunship")


func test_crash_breaks_the_dam_near_the_impact_and_floods_the_arena() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	await frames(2)
	var dam := Dam.current
	check(dam.pieces.size() > 20 and dam.pieces.size() < 100, "the dam is tens of blocks, not hundreds")
	check(dam.pieces.all(func(p: Dam.Piece) -> bool: return p.state == Dam.State.STANDING), "it stands whole before the crash")
	check(dam.torrent == null and dam.flood == null, "no water yet")
	boss.global_position = Course.to_world(Course.ARENA_CENTER_D, -40.0, 20.0)
	boss.phase = Gunship.Phase.INFECTED
	boss.hp = 1.0
	boss.take_hit(_charged(boss.global_position))
	var impact := boss._crash_to
	boss._crash = 0.01
	boss._update_crash(0.1)
	check(dam.breached, "the impact breaches the dam")
	var column := int(floorf(dam.to_local(impact).x / Dam.COLUMN_WIDTH + Dam.COLUMNS * 0.5))
	var broken := dam.pieces.filter(func(p: Dam.Piece) -> bool: return p.state != Dam.State.STANDING)
	check(broken.size() >= 9 and broken.size() < 30, "a section breaks out, not the whole wall (%d blocks)" % broken.size())
	check(dam.pieces.filter(func(p: Dam.Piece) -> bool: return absi(p.column - column) <= 1).all(func(p: Dam.Piece) -> bool: return p.state != Dam.State.STANDING), "every block at the impact is broken through to the ground")
	check(dam.pieces.filter(func(p: Dam.Piece) -> bool: return absi(p.column - column) >= 6).all(func(p: Dam.Piece) -> bool: return p.state == Dam.State.STANDING), "the rest of the wall stands")
	var tops := broken.filter(func(p: Dam.Piece) -> bool: return p.tier == 2 and absi(p.column - column) >= 2)
	check(not tops.is_empty(), "the crest collapses beyond the gap too, leaving a jagged edge")
	var far_tops := dam.pieces.filter(func(p: Dam.Piece) -> bool: return p.tier == 2 and absi(p.column - column) >= 5)
	check(far_tops.all(func(p: Dam.Piece) -> bool: return p.state == Dam.State.STANDING), "and stops short of the ends")
	check(is_instance_valid(dam.torrent) and is_instance_valid(dam.flood), "the torrent and the flood exist after the crash")
	await frames(90)
	check(broken.all(func(p: Dam.Piece) -> bool: return p.state in [Dam.State.FLYING, Dam.State.LANDED] and p.node.position != p.center), "broken blocks have flown off")
	check(dam.torrent.visible and dam.torrent.mesh.get_surface_count() == 1, "water pours through the breach")
	var reach := dam.flood_reach()
	await frames(120)
	check(dam.flood_reach() > reach, "the flood keeps spreading")
	check(dam.flood.mesh.get_aabb().size.z > 10.0, "over the arena floor")
	check(dam.flood.mesh.get_aabb().position.y > 0.0 and dam.flood.mesh.get_aabb().end.y < 3.0, "at a modest depth")
	await frames(60 * 7)
	check(dam.flood_reach() > Dam.FLOOD_REACH * 0.95, "reaching out towards the middle of the arena")
	check(world.player.hp > 0.0 and not world.player.dead, "the flood does not hurt the tank")


func test_flares_catch_shells() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	boss.phase = Gunship.Phase.STRIPPED
	boss._pop_flares()
	var flares := world.enemies.filter(func(e: Entity) -> bool: return e is Flare)
	check(flares.size() >= 4, "pops a spread of flares")
	check(flares.all(func(e: Entity) -> bool: return e.team == Entity.Team.ENEMY), "flares are targets for shells")


func test_gunship_machine_guns_and_fragments_glance_off_its_body() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var coax := Hit.make(Hit.Kind.BULLET, 10.0, _on(boss, Vector3(0, 0.3, 7.0)))
	coax.caliber = 20
	var fragment := Hit.make(Hit.Kind.FRAGMENT, 400.0, _on(boss, Vector3(0, 0.3, 7.0)))
	fragment.caliber = 30
	boss.take_hit(coax)
	boss.take_hit(fragment)
	check_eq(boss.hp, boss.max_hp, "20 mm coax and 30 mm fragments do nothing to the body")
	check(boss.armor >= 40.0, "its armor is 40 mm")

