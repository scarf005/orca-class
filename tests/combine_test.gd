extends TestCase
## The rice-mill hold, real hit shapes, committed warnings and module counters.


func _fight() -> Combine:
	var world := stage("midboss", true, 2)
	world.director._start_midboss({"kind": "combine", "hold": Stage2.MIDBOSS_D - 56.0})
	world.director._next_event = world.director.events.size()
	world.rail.d = world.rail.hold_at
	world.player._place(world.rail.d)
	world.player.set_process(false)
	world.player.tail.set_process(false)
	world.camera.global_position = world.player.global_position + Vector3(0, 20, 20)
	var boss := world.boss as Combine
	boss.set_process(false)
	return boss


func _hit(boss: Combine, name: String, damage: float, kind := Hit.Kind.SHELL) -> Hit:
	var part: Combine.Part = boss.parts[name]
	var hit := Hit.make(kind, damage, boss._part_frame(part).origin)
	hit.source = _world.player
	return hit


func test_checkpoint_spawns_combine_and_holds_before_the_mill() -> void:
	var world := stage("midboss", false, 2)
	check(world.rail.d < Stage2.MIDBOSS_D, "checkpoint starts before the combine")
	check_eq(world.player.coax_tier, 2, "checkpoint has 20 mm coax")
	check(world.player.modules.laser_online(), "RWS fitted at checkpoint")
	check(not world.stats.ranked, "checkpoint is unranked")
	check(await wait_until(func() -> bool: return world.boss is Combine, 30), "the checkpoint fires the combine event")
	check_eq(world.rail.mode, Rail.Mode.HOLD, "rail holds")
	world.player.invulnerable = true
	await frames(240)
	check(world.rail.d <= world.rail.hold_at + 0.5, "rail stays before the mill")
	check(Stage1.new().events(false).any(func(e: Dictionary) -> bool: return e.type == "midboss" and e.kind == "colossus"), "Stage 1 still uses colossus")


func test_mow_waits_a_full_second_hits_locked_lane_and_returns() -> void:
	var boss := _fight()
	var tank := _world.player
	boss._start_mow(tank)
	var start := boss.global_position
	var before := tank.hp
	for i in 59:
		boss.behave(1.0 / 60.0)
	check_eq(boss.global_position, start, "no charge before 1 s")
	check_eq(tank.hp, before, "telegraph does not damage")
	for i in 90:
		boss.behave(1.0 / 60.0)
	check(tank.hp < before, "the real header reaches a tank left in its lane")
	for i in 300:
		if boss._attack == Combine.Attack.NONE:
			break
		boss.behave(1.0 / 60.0)
	check_eq(boss._attack, Combine.Attack.NONE, "mow backs off and finishes")
	check_near(Course.to_course(boss.global_position).x, Stage2.MIDBOSS_D, 0.05, "back at its standoff")


func test_mow_locks_the_lane_so_sideways_dodge_is_safe() -> void:
	var boss := _fight()
	var tank := _world.player
	boss._start_mow(tank)
	tank.course_u = 14.0
	tank._place(_world.rail.d)
	var before := tank.hp
	for i in 200:
		if boss._attack == Combine.Attack.NONE:
			break
		boss.behave(1.0 / 60.0)
	check_eq(tank.hp, before, "moving sideways escapes the locked header corridor")
	check_near(boss._lane, 0.0, 0.01, "mow does not home after warning")


func test_mow_crushes_noncrushable_props_and_dash_is_safe() -> void:
	var boss := _fight()
	var prop := Prop.new()
	prop.setup("wall", PropKit.mesh("wall", 0), 1.6, 1.7, 10.0)
	prop.crushable = false
	prop.position = Course.ground_at(1120.0, 0.0)
	_world.props.add_child(prop)
	var tank := _world.player
	boss._start_mow(tank)
	tank.invuln = 1.0
	var before := tank.hp
	for i in 140:
		boss.behave(1.0 / 60.0)
	check(prop.dead, "the header crushes props, not just explicitly crushable ones")
	check_eq(tank.hp, before, "dash invulnerability applies to header damage")


func test_header_break_stops_active_and_future_mows_and_cartwheels() -> void:
	var boss := _fight()
	boss._start_mow(_world.player)
	boss.take_hit(_hit(boss, "header", Combine.HEADER_HP))
	check_eq(boss._attack, Combine.Attack.NONE, "breaking reel immediately cancels mow")
	var part: Combine.Part = boss.parts.header
	check(part.node.get_parent() is Wreck and part.node.visible, "header is a visible cartwheeling wreck")
	for i in 8:
		boss._choose_attack(_world.player)
		check(boss._attack != Combine.Attack.MOW, "lost header cannot choose mow")
		boss._end_attack()


func test_chaff_sweep_warns_for_point_eight_and_broken_auger_stops_it() -> void:
	var boss := _fight()
	boss._start_chaff(_world.player)
	var before := _world.projectiles.size()
	var angle := boss._auger.rotation.y
	boss._update_chaff(0.79)
	check_eq(_world.projectiles.size(), before, "no pellets before .8 s")
	check(absf(boss._auger.rotation.y - angle) > 0.1, "arm visibly swings toward locked target")
	boss._update_chaff(0.011)
	check_eq(_world.projectiles.size() - before, 9, "full hostile fan after the sweep")
	var fan := _world.projectiles.slice(before)
	check(fan.all(func(p: Projectile) -> bool: return p.team == Entity.Team.ENEMY and p.hit.kind == Hit.Kind.SPORE), "pellets hurt hull instead of glancing off as small arms")
	check(fan[0].velocity.angle_to(fan[8].velocity) > 0.5, "fan spans a readable arc")
	boss._start_chaff(_world.player)
	boss.take_hit(_hit(boss, "auger", Combine.AUGER_HP))
	check_eq(boss._attack, Combine.Attack.NONE, "auger break cancels a warning")
	before = _world.projectiles.size()
	boss._spray()
	check_eq(_world.projectiles.size(), before, "broken auger cannot emit more pellets")
	for i in 8:
		boss._choose_attack(_world.player)
		check(boss._attack != Combine.Attack.CHAFF, "future attacks respect the lost auger")
		boss._end_attack()


func test_grain_heat_doubles_but_darts_and_tail_do_not() -> void:
	var boss := _fight()
	var normal := _hit(boss, "grain", 100.0)
	var before := boss.hp
	boss.take_hit(normal)
	var plain_damage := before - boss.hp
	var heat := _hit(boss, "grain", 100.0)
	heat.heat = true
	heat.pierce = true
	before = boss.hp
	boss.take_hit(heat)
	check_near(before - boss.hp, plain_damage * 2.0, 0.001, "HEAT doubles the actual grain hit")
	var dart := _hit(boss, "grain", 100.0)
	dart.pierce = true
	before = boss.hp
	boss.take_hit(dart)
	check_near(before - boss.hp, plain_damage, 0.001, "APFSDS pierce is not mistaken for HEAT")
	var body := Hit.make(Hit.Kind.SHELL, 100.0, boss.hit_center())
	body.heat = true
	before = boss.hp
	boss.take_hit(body)
	check_near(before - boss.hp, plain_damage * 0.5, 0.001, "body has no grain bonus")


func test_actual_heat_shell_identifies_grain_and_tail_stab_interrupts() -> void:
	var boss := _fight()
	var tank := _world.player
	var grain: Vector3 = boss.aim_parts().grain[0]
	var before := boss.hp
	tank.load_round(Armament.Round.HEAT)
	tank.fire_cannon(grain + Vector3.UP * 10.0, Vector3.DOWN)
	check(before - boss.hp >= Armament.SHELL_DAMAGE * 1.5 * 0.06 * 4.0, "real HEAT projectile carries the weak-point bonus (%.1f damage)" % (before - boss.hp))
	boss._start_mow(tank)
	boss._attack_time = 0.4
	tank._grab_target = boss
	tank.tail.set_state(Tail.State.STAB, boss.hit_center(), boss)
	tank._on_tail_arrived()
	check_eq(boss._attack, Combine.Attack.NONE, "actual tail arrival interrupts the warning")
	check(boss.stagger > 0.0, "tail leaves a stagger")
	boss.stagger = 0.0
	boss._start_chaff(tank)
	boss.interrupt()
	check_eq(boss._attack, Combine.Attack.NONE, "tail also interrupts auger warning")


func test_tracks_slow_reposition_and_hit_volumes_follow_detached_parts() -> void:
	var boss := _fight()
	var grain := boss.aim_parts().grain[0] as Vector3
	check(boss.hit_test(grain + Vector3.UP * 10.0, grain - Vector3.UP * 10.0) >= 0.0, "grain is physically shootable")
	var header: Combine.Part = boss.parts.header
	var tip := boss._part_frame(header) * Vector3(4.9, 0, 0)
	check(boss.hit_test(tip + Vector3.UP * 4.0, tip - Vector3.UP * 4.0) >= 0.0, "wide header end is shootable")
	boss.take_hit(_hit(boss, "header", Combine.HEADER_HP))
	check_eq(boss.hit_test(tip + Vector3.UP * 4.0, tip - Vector3.UP * 4.0), -1.0, "detached header stops blocking shots")
	var speed := boss.reposition_speed()
	boss.take_hit(_hit(boss, "track_l", Combine.TRACK_HP))
	check(boss.reposition_speed() < speed, "one track slows repositioning")
	speed = boss.reposition_speed()
	boss.take_hit(_hit(boss, "track_r", Combine.TRACK_HP))
	check(boss.reposition_speed() < speed, "two tracks slow it further")
	var auger: Combine.Part = boss.parts.auger
	boss._auger.rotation.y = 1.1
	check_eq(boss._part_at(boss._part_frame(auger).origin), auger, "auger hit region follows its swing")


func test_crawlers_only_drop_after_hurt_once_and_ignored_hits_do_nothing() -> void:
	var boss := _fight()
	var crawlers := func() -> Array: return _world.enemies.filter(func(e: Entity) -> bool: return e is Crawler)
	check_eq(crawlers.call().size(), 0, "no crawlers on spawn")
	for amount in [0.0, -10.0]:
		boss.take_hit(_hit(boss, "header", amount))
	boss.invulnerable = true
	boss.take_hit(_hit(boss, "header", 30.0))
	boss.invulnerable = false
	check_eq(crawlers.call().size(), 0, "ignored hits do not hatch crawlers")
	boss.take_hit(_hit(boss, "header", 10.0))
	check_eq(crawlers.call().size(), 3, "first hurt drops three, not a flood")
	check(crawlers.call().all(func(e: Crawler) -> bool: return e.global_position.y > boss.global_position.y + 5.0), "crawlers visibly fall from the grain tank")
	for i in 5:
		boss.take_hit(_hit(boss, "header", 10.0))
	check_eq(crawlers.call().size(), 3, "later hits do not flood the arena")
	await frames(120)
	check_eq(crawlers.call().size(), 3, "dropped crawlers do not burst harmlessly on touchdown")
	check(crawlers.call().all(func(e: Crawler) -> bool: return e.state == Crawler.State.RUN and e.global_position.distance_to(_world.player.global_position) < 50.0), "after landing crawlers pursue the tank")


func test_death_bursts_then_hurls_a_wreck_drops_loot_and_releases() -> void:
	var boss := _fight()
	boss.set_process(true)
	var died := [false]
	boss.died.connect(func(_e: Entity) -> void: died[0] = true)
	var pickups := _world.pickups.size()
	boss.hp = 1.0
	boss.take_hit(_hit(boss, "grain", 100.0))
	check(boss._dying > 0.0 and not boss.dead, "burning chaff burst precedes final wreck")
	check(await wait_until(func() -> bool: return died[0], 180), "death completes")
	check(_world.get_children().any(func(n: Node) -> bool: return n is Wreck), "hull is hurled as wreck")
	check(_world.pickups.size() > pickups, "death drops a pickup")
	check(await wait_until(func() -> bool: return _world.rail.mode == Rail.Mode.RAIL, 120), "Director resumes rail after death")
	check_eq(_world.boss, null, "boss bar clears")
