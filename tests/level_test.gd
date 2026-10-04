extends TestCase
## Level design: attacks from behind and the flanks, readable UAV passes, the laser's feedback.


func test_stage_attacks_from_behind_and_the_flanks() -> void:
	var events := Stage1.events(false)
	var behind := events.filter(func(e: Dictionary) -> bool: return e.type == "wave" and (e.get("formation", "") == "behind" or e.get("props", {}).get("from_behind", false)))
	var flank := events.filter(func(e: Dictionary) -> bool: return e.type == "wave" and e.get("formation", "") == "flank")
	check(behind.size() >= 6, "at least six scripted waves come from behind (got %d); rear drones are the dynamic pursuit now" % behind.size())
	check(not behind.any(func(e: Dictionary) -> bool: return e.kind == "fpv"), "rear FPV drones are not scripted: the pursuit sends them")
	check(behind.any(func(e: Dictionary) -> bool: return e.kind in ["ugv", "walker"]), "ground vehicles run the tank down from behind")
	check(behind.any(func(e: Dictionary) -> bool: return e.kind == "uav"), "UAVs make passes from behind")
	check(flank.size() >= 2, "some waves come in from the valley sides")


func test_waves_from_behind_are_announced_and_overtake() -> void:
	var world := stage()
	await frames(30)
	var warned := []
	world.director.incoming.connect(func(from: Vector3) -> void: warned.append(from))
	var spawned: Array[Enemy] = world.director.spawn_wave({"d": world.rail.d, "kind": "ugv", "count": 1, "formation": "behind", "spacing": 8.0})
	check(warned.size() == 1, "the HUD is told a wave is coming from behind")
	var ugv := spawned[0] as Ugv
	world.player.tail.destroyed = true # Keep the claw from snatching it as it passes.
	# Keep the invulnerable probe out of the tank's ram path so hitstop cannot stall the chase.
	var lane := Tank.lateral_limit(world.rail.d)
	world.player.course_u = -lane
	ugv._lane = lane * 0.8
	ugv._lane_timer = 10.0
	check(Course.to_course(ugv.global_position).x < world.rail.d, "it starts behind the rail")
	ugv.invulnerable = true
	var passed := await wait_until(func() -> bool: return is_instance_valid(ugv) and Course.to_course(ugv.global_position).x > world.rail.d + world.player.course_offset + 5.0, 60 * 8)
	check(passed, "it overtakes the tank instead of falling behind and despawning")


func test_uav_passes_are_slow_enough_to_engage() -> void:
	var world := stage()
	await frames(30)
	var spawned: Array[Enemy] = world.director.spawn_wave({"d": world.rail.d, "kind": "uav", "count": 1, "props": {"attack": "bomb"}})
	var uav := spawned[0] as Uav
	uav.invulnerable = true
	var start := uav.global_position
	await frames(60)
	check(uav.global_position.distance_to(start) < Uav.HEAD_ON_SPEED * 1.3, "the head-on pass is slow")
	var behind: Array[Enemy] = world.director.spawn_wave({"d": world.rail.d, "kind": "uav", "count": 1, "props": {"attack": "strafe", "from_behind": true}})
	var chaser := behind[0] as Uav
	chaser.invulnerable = true
	check(Course.to_course(chaser.global_position).x < world.rail.d, "a rear pass starts behind the tank")
	var time_near := 0
	for i in 60 * 10:
		await frames(1)
		if is_instance_valid(chaser) and chaser.global_position.distance_to(world.player.global_position) < 60.0:
			time_near += 1
	check(time_near > 60 * 3, "it works the tank over for seconds, not a blink (%.1f s)" % (time_near / 60.0))


func test_laser_kills_are_announced() -> void:
	var world := stage()
	await frames(2)
	var got := []
	world.intercepted.connect(func(at: Vector3) -> void: got.append(at))
	var tank := world.player
	var missile := world.spawn_projectile(Entity.Team.ENEMY, tank.global_position + Vector3(0, 6, -20), Vector3(0, -3, 20), "rocket")
	missile.interceptable = true
	missile.intercept_hp = 0.2
	missile.life = 5.0
	var ok := await wait_until(func() -> bool: return not got.is_empty(), 120)
	check(ok, "the laser burning a missile down is signalled for a callout")


func test_full_screen_scales_without_whole_number_letterboxing() -> void:
	check(ProjectSettings.get_setting("display/window/stretch/scale_mode") == "fractional", "the canvas scales to fill the screen")


func test_air_hunters_and_gunship_boss_on_both_difficulties() -> void:
	for hard in [false, true]:
		var events := Stage1.events(hard)
		var waves := events.filter(func(e: Dictionary) -> bool: return e.type == "wave" and e.kind in ["helicopter", "tiltrotor"])
		var tiltrotors := events.filter(func(e: Dictionary) -> bool: return e.type == "wave" and e.kind == "tiltrotor")
		for section in [Course.Section.VILLAGE, Course.Section.RESERVOIR, Course.Section.OVERPASS]:
			check(waves.any(func(e: Dictionary) -> bool: return Course.section_at(e.d) == section), "helicopters or tiltrotors patrol section %d" % section)
			check_eq(tiltrotors.filter(func(e: Dictionary) -> bool: return Course.section_at(e.d) == section).size(), 1, "one tiltrotor in section %d" % section)
		check(tiltrotors.all(func(e: Dictionary) -> bool: return _size(e, hard) == 1), "a tiltrotor wave is never scaled up")
		var bosses := events.filter(func(e: Dictionary) -> bool: return e.type == "boss")
		check_eq(bosses.size(), 1, "stage has one final boss")
		check_eq(bosses[0].kind, "gunship", "stage ends with the new gunship")


func test_ordinary_helicopter_coax_hits_account_for_its_armor() -> void:
	var world := stage()
	var spawned := world.director.spawn_wave({"d": 0.0, "kind": "helicopter", "height": 14.0, "ahead": 100.0})
	var heli := spawned[0] as Helicopter
	check(world.boss == null, "helicopter wave does not claim the boss bar")
	check_eq(world.rail.mode, Rail.Mode.RAIL, "ordinary helicopter does not start the arena")
	var tail := heli.model.to_global(Vector3(0, 1.4, 7.6))
	check(heli.hit_test(tail + Vector3.LEFT * 3.0, tail + Vector3.RIGHT * 3.0) >= 0.0, "the long tail remains hittable")
	var hit := Hit.make(Hit.Kind.BULLET, Armament.GUNS[8].damage, heli.hit_center())
	hit.caliber = 8
	hit.source = world.player
	var needed := ceili(heli.max_hp / (hit.damage * heli.damage_multiplier(hit)))
	for i in needed - 1:
		heli.take_hit(hit)
	check(not heli.dead, "helicopter survives %d basic bullets" % (needed - 1))
	heli.take_hit(hit)
	check(heli.dead, "bullet %d destroys it" % needed)
	check_eq(needed, 48, "6 mm armor blunts tier-1 coax to a quarter")
	check_eq(world.stats.kills, 1, "ordinary helicopter counts as a normal kill")
	check_eq(world.rail.mode, Rail.Mode.RAIL, "ordinary kill keeps the stage scrolling")


func test_plain_shell_kills_helicopter_and_uav_outright() -> void:
	var world := stage()
	for enemy: Enemy in [Helicopter.new(), Uav.new()]:
		enemy.position = Course.ground_at(world.rail.d + 55.0, 0.0) + Vector3.UP * 13.0
		world.add_enemy(enemy)
		var hit := Hit.make(Hit.Kind.SHELL, 1500.0, enemy.hit_center(), Vector3.FORWARD)
		hit.source = world.player
		enemy.take_hit(hit)
		check(enemy.dead, "a plain shell kills a %s" % enemy.get_class())


func test_helicopter_telegraphs_bursts_and_cleans_up() -> void:
	var world := stage()
	var heli := Helicopter.new()
	heli.position = Course.ground_at(55.0, 0.0) + Vector3.UP * 13.0
	world.add_enemy(heli)
	heli._attack_timer = 0.0
	heli.behave(0.01)
	check(heli._telegraph > 0.0, "attack starts with a telegraph")
	check_eq(world.projectiles.size(), 0, "telegraph does not deal damage")
	heli.behave(0.81)
	heli.behave(0.01)
	check_eq(world.projectiles.size(), 1, "telegraphed gun burst fires")
	heli._rockets = true
	heli._fire(world.player)
	var rocket := world.projectiles.back() as Projectile
	check(rocket.interceptable and rocket.blast_damage > 0.0, "rocket can be intercepted and has a warhead")
	heli.interrupt()
	check_eq(heli._burst, 0, "interrupt cancels the burst")
	heli.age = Helicopter.PACE_TIME + 13.0
	heli.behave(0.01)
	check(heli.dead and heli not in world.enemies, "surviving helicopter eventually leaves and unregisters")
	check_eq(world.stats.kills, 0, "leaving is not a player kill")


# --- Pacing: build, peak and release per section (hard scaling as the Director applies it).

const BUDGETS := {Course.Section.FARM: 10, Course.Section.VILLAGE: 20, Course.Section.RESERVOIR: 22, Course.Section.OVERPASS: 20}
const PEAKS := {Course.Section.VILLAGE: Vector2(1085.0, 1195.0), Course.Section.RESERVOIR: Vector2(2185.0, 2370.0), Course.Section.OVERPASS: Vector2(3065.0, 3235.0)}
const GROUND := ["ugv", "walker", "spitter", "crawler", "quad"]


func _waves(hard: bool) -> Array[Dictionary]:
	var waves: Array[Dictionary] = []
	waves.assign(Stage1.events(hard).filter(func(e: Dictionary) -> bool: return e.type == "wave"))
	return waves


func _size(wave: Dictionary, hard: bool) -> int:
	var count: int = wave.get("count", 1)
	return ceili(count * wave.get("hard_scale", 1.4)) if hard else count


func _total(waves: Array[Dictionary], hard: bool) -> int:
	return waves.reduce(func(sum: int, w: Dictionary) -> int: return sum + _size(w, hard), 0)


## Waves spawning in [from, from + span).
func _within(waves: Array[Dictionary], from: float, span: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	found.assign(waves.filter(func(w: Dictionary) -> bool: return w.d >= from and w.d < from + span))
	return found


func _touches_peak(from: float, span: float) -> bool:
	return PEAKS.values().any(func(p: Vector2) -> bool: return from < p.y and from + span > p.x)


func _section_waves(waves: Array[Dictionary], section: Course.Section) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	found.assign(waves.filter(func(w: Dictionary) -> bool: return Course.section_at(w.d) == section))
	return found


func test_section_budgets_hold() -> void:
	var waves := _waves(false)
	for section: Course.Section in BUDGETS:
		var total := _total(_section_waves(waves, section), false)
		check(absf(total - BUDGETS[section]) <= BUDGETS[section] * 0.15, "section %d holds ~%d enemies (got %d)" % [section, BUDGETS[section], total])
	check_eq(_total(_section_waves(waves, Course.Section.SCHOOL), false), 4, "the school holds one crawler pack")


func test_no_window_of_150m_exceeds_the_cap() -> void:
	# Ask the production spawner for each effective count instead of copying its hard-mode formula.
	for hard in [false, true]:
		var world := stage()
		world.director._hard = hard
		var waves := _waves(hard)
		var effective: Array[int] = []
		for wave in waves:
			effective.append(world.director.spawn_wave(wave).size())
		for i in waves.size():
			var w := waves[i]
			var count := 0
			for j in waves.size():
				if waves[j].d >= w.d and waves[j].d < w.d + 150.0:
					count += effective[j]
			var cap := 30 if hard else 22
			if _touches_peak(w.d, 150.0):
				cap = 45 if hard else 30
			check(count <= cap, "%s: %d enemies in the 150 m from d %d (cap %d)" % ["hard" if hard else "normal", count, w.d, cap])
		cleanup()
		await frames(1)


func test_off_peak_windows_mix_at_most_two_kinds() -> void:
	var waves := _waves(false)
	for w in waves:
		if _touches_peak(w.d, 100.0):
			continue
		var kinds := {}
		for other in _within(waves, w.d, 100.0):
			kinds[other.kind] = true
		check(kinds.size() <= 2, "%d kinds within 100 m of d %d: %s" % [kinds.size(), w.d, kinds.keys()])


func test_every_section_has_a_release() -> void:
	var waves := _waves(false)
	var boss := Stage1.events(false).filter(func(e: Dictionary) -> bool: return e.type == "boss")[0].d as float
	for section in [Course.Section.FARM, Course.Section.VILLAGE, Course.Section.RESERVOIR, Course.Section.OVERPASS]:
		var marks: Array[float] = [Course.SECTION_STARTS[section]]
		marks.append_array(_section_waves(waves, section).map(func(w: Dictionary) -> float: return w.d))
		marks.append(boss if section == Course.Section.OVERPASS else Course.SECTION_STARTS[section + 1])
		var gaps: Array[float] = []
		for i in marks.size() - 1:
			gaps.append(marks[i + 1] - marks[i])
		check(gaps.max() >= 120.0, "section %d has a 120 m stretch without a spawn (longest %.0f)" % [section, gaps.max()])
	var reservoir := _section_waves(waves, Course.Section.RESERVOIR)
	check(reservoir.filter(func(w: Dictionary) -> bool: return w.d > 2440.0).size() == 1, "the reservoir release holds only the supply UGV")
	var overpass := _section_waves(waves, Course.Section.OVERPASS)
	check(overpass.all(func(w: Dictionary) -> bool: return w.d <= 3260.0), "the overpass releases from d 3260 to the boss")


func test_reservoir_is_mostly_air() -> void:
	var waves := _section_waves(_waves(false), Course.Section.RESERVOIR)
	var ground := _total(waves.filter(func(w: Dictionary) -> bool: return w.kind in GROUND), false)
	var share := float(ground) / _total(waves, false)
	check(share <= 0.3, "ground units are %.0f%% of the reservoir" % (share * 100.0))


func test_first_uav_pass_and_the_quad_duel_stand_alone() -> void:
	var waves := _waves(false)
	var uav := waves.filter(func(w: Dictionary) -> bool: return w.kind == "uav")[0] as Dictionary
	var quad := waves.filter(func(w: Dictionary) -> bool: return w.kind == "quad" and Course.section_at(w.d) == Course.Section.VILLAGE)[0] as Dictionary
	for other in waves:
		if other != uav:
			check(absf(other.d - uav.d) >= 60.0, "nothing spawns within 60 m of the first UAV pass (%s at %d)" % [other.kind, other.d])
		if other != quad:
			check(absf(other.d - quad.d) >= 100.0, "nothing spawns within 100 m of the quad duel (%s at %d)" % [other.kind, other.d])


func test_telegraphed_blasts_hit_hard_enough_to_matter() -> void:
	var world := stage()
	var tank := world.player
	tank.invulnerable = false
	tank._respawn = 0.0
	tank.invuln = 0.0
	var attacks := [		[Uav.new(), func(enemy: Enemy) -> void: (enemy as Uav)._bomb_run(0.0, tank, 30.0), 30.0, "UAV bomb"],
		[QuadMech.new(), func(enemy: Enemy) -> void:
			(enemy as QuadMech).weapon = "mortar"
			(enemy as QuadMech)._attack(tank), 24.0, "quad mortar"],
		[Spitter.new(), func(enemy: Enemy) -> void: (enemy as Spitter)._volley(tank), 20.0, "spitter spore"],
	]
	for attack in attacks:
		var enemy := attack[0] as Enemy
		world.add_enemy(enemy)
		(attack[1] as Callable).call(enemy)
		var projectile: Projectile = world.projectiles.back()
		check_near(projectile.blast_damage, attack[2], 0.001, "%s keeps its configured warhead" % attack[3])
		tank.hp = tank.max_hp
		tank.dead = false
		tank.invuln = 0.0
		var before := tank.hp
		projectile.detonate(tank.hit_center(), tank)
		check(tank.hp < before, "%s damages a vulnerable tank on direct impact" % attack[3])


func test_a_hold_stops_the_rail_until_its_group_is_gone() -> void:
	var world := stage()
	await frames(10)
	var spawned: Array[Enemy] = world.director.spawn_wave({"d": world.rail.d, "kind": "ugv", "count": 2, "formation": "line", "ahead": 60.0, "spacing": 8.0})
	world.director._fire({"d": world.rail.d, "type": "hold", "at": world.rail.d + 5.0, "timeout": 30.0})
	check_eq(world.rail.mode, Rail.Mode.HOLD, "the rail holds")
	await frames(60)
	check_eq(world.rail.mode, Rail.Mode.HOLD, "and keeps holding while they live")
	spawned[0].die(Hit.make(Hit.Kind.SHELL, 9999.0, spawned[0].global_position))
	spawned[1].despawn()
	await frames(10)
	check_eq(world.rail.mode, Rail.Mode.RAIL, "the rail runs once the group is gone, killed or freed")


func test_a_hold_gives_up_after_its_timeout_and_skips_when_nothing_is_there() -> void:
	var world := stage()
	await frames(10)
	for enemy in world.enemies.duplicate():
		enemy.despawn()
	world.director._fire({"d": world.rail.d, "type": "hold", "at": world.rail.d + 5.0, "timeout": 30.0})
	check_eq(world.rail.mode, Rail.Mode.RAIL, "an empty hold does not stop the rail")
	var spawned: Array[Enemy] = world.director.spawn_wave({"d": world.rail.d, "kind": "ugv", "count": 1, "ahead": 60.0})
	spawned[0].invulnerable = true
	world.director._fire({"d": world.rail.d, "type": "hold", "at": world.rail.d + 5.0, "timeout": 0.5})
	check_eq(world.rail.mode, Rail.Mode.HOLD, "a hold with a live enemy stops the rail")
	await frames(45)
	check_eq(world.rail.mode, Rail.Mode.RAIL, "and lets go after its timeout")
