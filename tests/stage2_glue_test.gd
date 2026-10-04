extends TestCase
## City checkpoint sorties and elevated hunters use the same paths as a full run.


func test_checkpoint_sorties_start_before_the_fight_with_city_loadout() -> void:
	for checkpoint in ["midboss", "boss"]:
		var world := stage(checkpoint, false, 2)
		world.director.set_process(false)
		check_near(world.rail.d, 1660.0 if checkpoint == "midboss" else 3390.0, 0.01, "checkpoint starts at its city approach")
		check(not world.stats.ranked, "checkpoint sortie is unranked")
		check(world.player.modules.laser_online(), "checkpoint keeps the fitted RWS")
		check(world.player.coax_tier >= 2, "checkpoint keeps the city coax")
		var fired := []
		world.director.checkpoint_reached.connect(func(name: String) -> void: fired.append(name))
		world.director._process(0.0)
		check_eq(fired, [checkpoint], "retry skips earlier unlocks and reaches its own checkpoint")
		var next: Dictionary = world.director.events[world.director._next_event]
		check(next.d > world.rail.d and next.d < (1780.0 if checkpoint == "midboss" else 3540.0), "retry keeps supplies before the boss entrance")


func test_city_mechs_move_on_the_deck_but_street_mechs_stay_underneath() -> void:
	var world := stage("", false, 2)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.director.scenery.stream(1000.0, 100000)
	for kind in ["abel", "kain", "adam"]:
		var mech: BipedMech = load(Director.ENEMY_SCRIPTS[kind]).new()
		mech.position = Course.to_world(1000.0, -42.0, Course.surface_height(1000.0, -42.0))
		world.add_enemy(mech)
		mech.walk_to(Course.to_world(1010.0, -42.0), 4.0, 0.5)
		check(mech.global_position.distance_to(Course.to_world(1000.0, -42.0, 28.8)) > 1.0, "%s actually walks along the deck" % kind)
		check_near(mech.global_position.y, 28.8, 0.01, "%s feet retain the deck height after movement" % kind)
		mech.position = Course.ground_at(800.0, 0.0)
		mech.walk_to(Course.ground_at(805.0, 0.0), 4.0, 0.5)
		check_near(mech.global_position.y, Course.height_at(mech.global_position), 0.01, "%s under the expressway cannot teleport onto it" % kind)
		mech.position = Course.to_world(1000.0, -48.4, 28.8)
		mech.walk_to(Course.to_world(1000.0, -52.0), 4.0, 0.5)
		check_near(mech.global_position.y, Course.height_at(mech.global_position), 0.01, "%s leaving the deck no longer has phantom support" % kind)


func test_roof_battery_uses_actual_rectangle_and_unstreamed_deck() -> void:
	var world := stage("", false, 2)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var battery := RooftopBattery.new()
	battery.position = Course.ground_at(1000.0, -42.0)
	world.add_enemy(battery)
	check_near(battery.position.y, 28.8, 0.01, "spawn height does not depend on whether the deck streamed yet")
	world.director.scenery.stream(1000.0, 100000)
	var edge := RooftopBattery.new()
	edge.position = Course.ground_at(1000.0, -49.0)
	world.add_enemy(edge)
	check_near(edge.position.y, Course.height_at(edge.position), 0.01, "outside the rectangular deck cannot count as its roof")


func test_hunter_reaches_rectangular_city_cover_then_peeks_into_line_of_sight() -> void:
	var world := stage("", false, 2)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.player.global_position = Course.ground_at(20.0, -25.0)
	var hunter := Abel.new()
	hunter.position = Course.ground_at(90.0, -25.0)
	world.add_enemy(hunter)
	hunter._attack_timer = INF
	check(hunter.seek_cover(world.player), "a real city facade provides cover")
	var goal := hunter._cover_goal
	check(not BipedMech.line_blocked(goal + Vector3.UP * (hunter.radius + 0.1), goal + Vector3.UP * (hunter.radius + 0.1), hunter.radius), "hide goal is outside the real padded rectangular footprint")
	for _i in 900:
		hunter.behave(1.0 / 60.0)
		if hunter._peek:
			break
	check(hunter._peek, "hunter reaches shelter and starts its peek rather than stalling")
	for _i in 600:
		hunter.behave(1.0 / 60.0)
	check(not BipedMech.line_blocked(world.player.hit_center(), hunter.hit_center()), "real city firing edge restores sight: at %s, goal %s, blocker %s" % [hunter.global_position, hunter._cover_goal, BipedMech.hard_blocker(world.player.hit_center(), hunter.hit_center())])


func test_boss_start_uses_active_stage_theme_before_any_deferred_call() -> void:
	var silent := Game.silent
	Game.silent = false
	for number in [1, 2]:
		var world := stage("", false, number)
		world.process_mode = Node.PROCESS_MODE_DISABLED
		world.director._start_boss({"kind": "gunship" if number == 1 else "hi_mo"})
		check_eq(Sfx._music_path, "res://assets/music/boss.ogg" if number == 1 else "res://assets/music/stage2_boss.ogg", "director immediately starts the active stage's boss theme")
		Sfx.stop_music()
	Game.silent = silent
