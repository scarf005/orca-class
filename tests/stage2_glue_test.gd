extends TestCase
## City checkpoint sorties and elevated hunters use the same paths as a full run.


func test_checkpoint_sorties_start_before_the_fight_with_city_loadout() -> void:
	for checkpoint in ["midboss", "boss"]:
		var world := stage(checkpoint, false, 2)
		world.director.set_process(false)
		check_near(world.rail.d, 1660.0 if checkpoint == "midboss" else 3390.0, 0.01, "checkpoint starts at its city approach")
		check(not world.stats.ranked, "checkpoint sortie is unranked")
		check(not world.player.modules.laser_online(), "checkpoint starts without the RWS")
		check(world.player.coax_tier >= 2, "checkpoint keeps the city coax")
		var fired := []
		world.director.checkpoint_reached.connect(func(name: String) -> void: fired.append(name))
		world.director._process(0.0)
		check_eq(fired, [checkpoint], "retry skips earlier unlocks and reaches its own checkpoint")
		var next: Dictionary = world.director.events[world.director._next_event]
		check(next.d > world.rail.d and next.d < (1780.0 if checkpoint == "midboss" else 3540.0), "retry keeps supplies before the boss entrance")
		await frames(1)
		check(not world.player.model.rws.visible, "checkpoint first rendered frame has no RWS")


func test_director_deck_events_use_the_live_parallel_expressway() -> void:
	for hard in [false, true]:
		var world := stage("", false, 2)
		world.director._hard = hard
		world.rail.d = 890.0
		var specs := Stage2.new().events(hard)
		var kain_event: Dictionary = specs.filter(func(event: Dictionary) -> bool: return event.type == "wave" and event.kind == "kain" and event.d == 890.0)[0]
		world.rail.d = kain_event.d
		var kain := world.director.spawn_wave(kain_event)[0]
		var kc := Course.to_course(kain.global_position)
		check_near(kc.y, -38.5, 0.1, "director Kain stands at the street-facing parapet")
		check_near(kain.global_position.y, Stage2.WATER_LEVEL + 6.0, 0.2, "Kain feet are on the low deck")
		var battery_event: Dictionary = specs.filter(func(event: Dictionary) -> bool: return event.type == "wave" and event.kind == "rooftop_battery" and event.d == (720.0 if hard else 700.0))[0]
		world.rail.d = battery_event.d
		var battery := world.director.spawn_wave(battery_event)[0]
		var bc := Course.to_course(battery.global_position)
		check_near(bc.y, -40.0, 0.1, "normal and hard rooftop batteries share the deck")
		check_near(battery.global_position.y, Stage2.WATER_LEVEL + 6.0, 0.2, "rooftop battery build finds the deck surface")


func test_city_mechs_move_on_the_deck_but_street_mechs_stay_underneath() -> void:
	var world := stage("", false, 2)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.director.scenery.stream(1000.0, 100000)
	for kind in ["abel", "kain", "adam"]:
		var mech: BipedMech = load(Director.ENEMY_SCRIPTS[kind]).new()
		var deck_height := Course.surface_height(1000.0, -40.0)
		mech.position = Course.to_world(1000.0, -40.0, deck_height)
		world.add_enemy(mech)
		mech.walk_to(Course.to_world(1010.0, -40.0), 4.0, 0.5)
		check_near(mech.global_position.y, deck_height, 0.01, "%s feet retain the deck height after movement" % kind)
		mech.position = Course.ground_at(800.0, 0.0)
		mech.walk_to(Course.ground_at(805.0, 0.0), 4.0, 0.5)
		check_near(mech.global_position.y, Course.height_at(mech.global_position), 0.01, "%s under the expressway cannot teleport onto it" % kind)
		mech.position = Course.to_world(1000.0, -48.4, deck_height)
		mech.walk_to(Course.to_world(1000.0, -52.0), 4.0, 0.5)
		check_near(mech.global_position.y, Course.height_at(mech.global_position), 0.01, "%s leaving the deck no longer has phantom support" % kind)


func test_roof_battery_uses_actual_rectangle_and_unstreamed_deck() -> void:
	var world := stage("", false, 2)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var battery := RooftopBattery.new()
	var deck_height := Course.surface_height(1000.0, -40.0)
	battery.position = Course.to_world(1000.0, -40.0, deck_height)
	world.add_enemy(battery)
	check_near(battery.position.y, deck_height, 0.01, "spawn height does not depend on whether the deck streamed yet")
	world.director.scenery.stream(1000.0, 100000)
	var edge := RooftopBattery.new()
	edge.position = Course.ground_at(1000.0, -70.0)
	world.add_enemy(edge)
	check_near(edge.position.y, Course.height_at(edge.position), 0.01, "outside the rectangular deck cannot count as its roof")


func test_hunter_reaches_rectangular_city_cover_then_peeks_into_line_of_sight() -> void:
	var world := stage("", false, 2)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.player.global_position = Course.ground_at(200.0, 0.0)
	var hunter := Abel.new()
	hunter.position = Course.ground_at(313.0, 9.0)
	world.director.scenery.stream(280.0, 100000)
	world.add_enemy(hunter)
	hunter._attack_timer = INF
	check(hunter.seek_cover(world.player), "a real street splitter provides cover")
	var goal := hunter._cover_goal
	check(not BipedMech.line_blocked(goal + Vector3.UP * (hunter.radius + 0.1), goal + Vector3.UP * (hunter.radius + 0.1), hunter.radius), "hide goal is outside the real padded rectangular footprint")
	for _i in 900:
		hunter.behave(1.0 / 60.0)
		if hunter._peek:
			break
	check(hunter._peek, "hunter reaches shelter and starts its peek rather than stalling")
	var clear_peek := false
	for _i in 600:
		hunter.behave(1.0 / 60.0)
		clear_peek = clear_peek or (hunter._peek and not BipedMech.line_blocked(world.player.hit_center(), hunter.hit_center()))
	check(clear_peek, "the hunter reaches a visible firing edge during its peek")


func test_surviving_deck_hunter_crosses_the_gap_with_a_street_fallback() -> void:
	for rate in [60.0, 12.0]:
		var world := stage("", true, 2)
		world.process_mode = Node.PROCESS_MODE_DISABLED
		world.director.scenery.stream(800.0, 100000)
		for prop: Prop in world.props.get_children():
			prop.dead = true
		world.rail.d = 720.0
		world.player._place(720.0)
		world.camera.follow(0.0)
		var hunter := world.director.spawn_wave({"kind": "kain", "u": -38.5, "height": 10.5, "ahead": 65.0})[0] as Kain
		hunter._attack_timer = INF
		var unsupported := false
		for i in int(rate * 10.0):
			world.rail.d = 720.0 + i * 16.0 / rate
			world.player._place(world.rail.d)
			world.camera.follow(1.0 / rate)
			hunter.move_hunter(world.player, 1.0 / rate, false)
			var slot: Vector3 = hunter.get_meta("slot")
			unsupported = unsupported or (slot.y > 0.0 and hunter.global_position.y < Stage2.WATER_LEVEL + 5.5)
		check(not unsupported, "a live deck hunter never retains deck-only metadata under an unsupported span")
		var slot: Vector3 = hunter.get_meta("slot")
		check_eq(slot.y, 0.0, "the 806-814 m gap sends the hunter to a street firing lane")
		check(absf(Course.to_course(hunter.global_position).y) <= Stage2.new().lateral_limit(world.rail.d), "fallback returns to the street instead of stranding the hunter below the deck")
		var ahead := Course.to_course(hunter.global_position).x - Course.to_course(world.player.global_position).x
		check(ahead >= 40.0 and ahead <= 120.0, "a relocating hunter keeps its firing range at %.0f FPS (%.1f m)" % [rate, ahead])


func test_city_relocation_consumes_the_full_low_fps_step() -> void:
	var world := stage("", true, 2)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	for prop: Prop in world.props.get_children():
		prop.dead = true
	var hunter := Kain.new()
	hunter.position = Course.ground_at(100.0, -12.0)
	world.add_enemy(hunter)
	hunter.walk_city_firing(Course.ground_at(110.0, -12.0), 30.0, 1.0 / 12.0)
	check_near(Course.to_course(hunter.global_position).x, 102.5, 0.01, "relocation at 30 m/s travels 2.5 m in a 1/12-second frame")


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
