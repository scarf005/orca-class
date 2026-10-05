extends TestCase
## Encounter density, lane choices and the main-gun contract use the live city.


func test_density_tracks_stage_one_over_the_same_distance() -> void:
	var starts := Stage2.SECTION_STARTS.duplicate()
	starts.append(Stage2.LENGTH)
	for section in Stage2.SECTION_STARTS.size():
		var baseline := 0
		var city := 0
		for event in Stage1.new().events(false):
			if event.type == "wave" and event.d >= starts[section] and event.d < starts[section + 1]:
				baseline += int(event.get("count", 1))
		for event in Stage2.new().events(false):
			if event.type != "wave" or event.d < starts[section] or event.d >= starts[section + 1] or event.kind in ["sea_mine", "rooftop_battery"]:
				continue
			city += int(event.get("count", 1))
			for member: Dictionary in event.get("squad", []):
				city += int(member.get("count", 1))
		check(city >= ceili(baseline * 0.7) and city <= floori(baseline * 0.8), "section %d density: %d city / %d Stage 1" % [section, city, baseline])


func test_every_split_offers_two_different_lane_rewards() -> void:
	var city := Stage2.new()
	var events := city.events(false)
	for index in Stage2.SPLITS.size():
		var split: Dictionary = Stage2.SPLITS[index]
		var lanes := city.split_lane_centres(index)
		var rewards := events.filter(func(e: Dictionary) -> bool: return e.type == "pickup" and absf(e.d + float(e.get("ahead", 40.0)) - float(split.d)) < 1.0)
		check_eq(rewards.size(), 2, "split %d has a reward in both lanes" % index)
		if rewards.size() != 2:
			continue
		check(rewards[0].id != rewards[1].id, "lane rewards are different")
		check_near(rewards[0].u, lanes.x, 0.01, "left reward is reachable")
		check_near(rewards[1].u, lanes.y, 0.01, "right reward is reachable")


func test_adam_takes_three_first_box_shells() -> void:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var adam := Adam.new()
	adam.position = world.player.global_position + Vector3(0, 0, -70)
	world.add_enemy(adam)
	var damage := lerpf(Armament.QUICK_DAMAGE.x, Armament.QUICK_DAMAGE.y, Armament.STAGE_1) * Armament.SHELL_DAMAGE_SCALE
	for i in 3:
		var hit := Hit.make(Hit.Kind.SHELL, damage, adam.hit_center())
		hit.caliber = 100
		hit.source = world.player
		adam.take_hit(hit)
		check_eq(adam.dead, i == 2, "Adam survives %d quick shell(s) until the third" % (i + 1))
