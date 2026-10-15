extends TestCase
## Encounter density, lane choices and the main-gun contract use the live city.


func test_stage_sends_few_enemies_one_group_at_a_time_at_an_even_pace() -> void:
	for hard in [false, true]:
		var waves := Stage2.new().events(hard).filter(func(e: Dictionary) -> bool: return e.type == "wave" and e.kind not in ["sea_mine", "rooftop_battery"])
		var total := 0
		var last := -INF
		for event in waves:
			var group := int(event.get("count", 1))
			for member: Dictionary in event.get("squad", []):
				group += int(member.get("count", 1))
			total += group
			check(group <= (6 if hard else 3), "the group at d=%d is %d enemies, a hunter with at most two escorts (hard=%s)" % [event.d, group, hard])
			check(event.d - last >= 200.0, "the group at d=%d follows the previous one by %d m, no bunching (hard=%s)" % [event.d, event.d - last, hard])
			last = event.d
		check(total <= (41 if hard else 25), "the whole course sends %d enemies besides the bosses (hard=%s)" % [total, hard])


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
		rewards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.u < b.u)
		check(rewards[0].id != rewards[1].id, "lane rewards are different")
		check_near(rewards[0].u, lanes.x, 0.01, "left reward is reachable")
		check_near(rewards[1].u, lanes.y, 0.01, "right reward is reachable")
		var rich: Dictionary = rewards[0] if rewards[0].id not in ["repair", "era"] else rewards[1]
		check(events.any(func(e: Dictionary) -> bool: return e.type == "wave" and e.has("squad") and e.d <= split.d and split.d - e.d < 100.0 and absf(float(e.get("u", 0.0)) - float(rich.u)) < 1.0), "split %d's counter lane has an elite guarding it" % index)


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


func test_abel_and_kain_hull_take_one_charge_or_two_first_box_shells() -> void:
	for kind: GDScript in [Abel, Kain]:
		for power in [Armament.STAGE_1, 1.0]:
			var world := stage()
			world.process_mode = Node.PROCESS_MODE_DISABLED
			var hunter: BipedMech = kind.new()
			hunter.position = world.player.global_position + Vector3(0, 0, -70)
			world.add_enemy(hunter)
			var direction := hunter.model.global_basis.z
			var count := 1 if power == 1.0 else 2
			for i in count:
				world.player._fire_shell(Armament.Round.APHE, hunter.hit_center() - direction * 8.0, direction, power)
				if power < 1.0:
					land(world, 0)
				check_eq(hunter.dead, i == count - 1, "%s dies to %d real APHE shell(s) at %.2f charge" % [kind.get_global_name(), count, power])


func test_squad_arrives_with_exactly_one_elite() -> void:
	for hard in [false, true]:
		var world := stage("", true, 2)
		world.process_mode = Node.PROCESS_MODE_DISABLED
		world.director._hard = hard
		for event in Stage2.new().events(hard):
			if event.type != "wave" or not event.has("squad"):
				continue
			world.rail.d = event.d
			world.player._place(event.d)
			var before := world.stats.spawned
			var spawned := world.director.spawn_wave(event)
			var expected := 1
			for member: Dictionary in event.squad:
				expected += int(member.get("count", 1))
			check_eq(spawned.size(), expected, "all escorts arrive in the leader's frame")
			check_eq(world.stats.spawned - before, expected, "squad contributes to real spawn accounting")
			check_eq(spawned.filter(func(e: Enemy) -> bool: return e is BipedMech or e is TorpedoBoat or e is Mortar).size(), 1, "one elite leads every squad")
			for enemy in spawned:
				enemy.despawn()


func test_city_mortar_leads_the_whole_warning_and_flight_without_rebalancing_duels() -> void:
	for number in [1, 2]:
		var world := stage("", true, number)
		world.process_mode = Node.PROCESS_MODE_DISABLED
		for prop: Prop in world.props.get_children():
			prop.dead = true
		world.camera.follow(0.0)
		world.player.velocity = Vector3.FORWARD * 16.0
		var hunter := world.director.spawn_wave({"kind": "kain", "ahead": 110.0})[0] as Kain
		hunter._attack_timer = 0.0
		hunter.behave(0.01)
		var aim := hunter._aim
		for i in 70:
			hunter.behave(1.0 / 60.0)
		check(not world.projectiles.is_empty(), "warned mortar actually fires in stage %d" % number)
		if world.projectiles.is_empty():
			continue
		var shell := world.projectiles[0]
		check_near(shell.hit.damage, 110.0 if number == 2 else 26.0, 0.01, "city pressure leaves the non-city mortar unchanged")
		check_eq(hunter._aim, aim, "the marked landing does not track a dodge")
		if number == 2:
			world.player.global_position = aim
			var hp := world.player.hp
			land(world, 0)
			check(world.player.hp < hp, "a tank that follows the predicted rail enters the warned impact patch")


func test_firing_spots_reject_side_towers_rear_and_high_roofs() -> void:
	var world := stage("", true, 2)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.rail.d = 500.0
	world.player._place(500.0)
	world.camera.follow(0.0)
	world.director.scenery.stream(500.0, 100000)
	var hunter := Abel.new()
	hunter.position = Course.ground_at(565.0, -10.0)
	world.add_enemy(hunter)
	var t := Course.to_course(world.player.global_position)
	for spec in [[100.0, 8.0, 0.05, true], [65.0 * Course.stage.standoff - 5.0, 0.0, 0.05, false], [125.0 * Course.stage.standoff + 10.0, 0.0, 0.05, false], [110.0, 45.0, 0.05, false], [110.0, 0.0, 7.0, false]]:
		check_eq(hunter.firing_spot_valid(Course.to_world(t.x + spec[0], spec[1], spec[2]), world.player), spec[3], "front/height/street envelope at %s" % [spec])
	var spot := hunter.city_firing_spot(world.player)
	check(spot != Vector3.INF and hunter.firing_spot_valid(spot, world.player), "a legal street firing spot exists")
	check(not world.director.scenery.line_blocked(world.camera.global_position, spot + Vector3.UP * hunter.center_height), "chosen spot offers an unoccluded camera shot")
