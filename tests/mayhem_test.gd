extends TestCase
## Destruction: crushing buildings and enemies, collateral chains, style from kills, mayhem healing.


func _prop(world: World, kind: String, at: Vector3, hp: float, solid := true) -> Prop:
	var prop := Prop.new()
	prop.setup(kind, PropKit.mesh(kind, 0), 2.5, 4.0, hp)
	prop.solid = solid
	prop.position = at
	world.props.add_child(prop)
	return prop


func test_tank_bulldozes_houses_at_speed() -> void:
	var world := stage()
	var tank := world.player
	await frames(3)
	var house := _prop(world, "house", tank.global_position + Vector3(0, 0, -1.0), 150.0)
	var crushed := await wait_until(gone(house), 10)
	check(crushed, "a house in the way is flattened immediately")
	check(world.stats.style > 0.0, "demolition earns style")


func test_landmarks_break_into_pieces_that_topple() -> void:
	var world := stage()
	var tank := world.player
	var trunk := _prop(world, "zelkova_trunk", tank.global_position + Vector3(0, 0, -40.0), 260.0)
	var crown := _prop(world, "zelkova_canopy", trunk.global_position + Vector3.UP * 5.0, 150.0)
	trunk.supports.append(crown)
	var shot := Hit.make(Hit.Kind.SHELL, 999.0, trunk.global_position)
	shot.source = tank
	trunk.take_hit(shot)
	check(trunk.dead, "the old tree's trunk can be destroyed")
	check(crown._topple >= 0.0, "the crown it held starts to fall")
	var fell := await wait_until(gone(crown), 180)
	check(fell, "and breaks apart when it lands")


func test_ramming_hurts_ground_enemies() -> void:
	var world := stage()
	var tank := world.player
	await frames(3)
	var ugv: Ugv = load("res://scripts/enemies/ugv.gd").new()
	ugv.position = tank.global_position + Vector3(0, 0, -1.0)
	world.add_enemy(ugv)
	var hp := ugv.hp
	await frames(2)
	check(not is_instance_valid(ugv) or ugv.hp <= hp - Tank.RAM_DAMAGE + 0.1, "a UGV in the way takes a crushing hit")


func test_collateral_chain_kill_scores_style() -> void:
	var world := stage()
	var crawler := Crawler.new()
	crawler.position = Course.ground_at(world.rail.d + 50.0, 0.0)
	world.add_enemy(crawler)
	var car := _prop(world, "car", crawler.position + Vector3(1.5, 0, 0), 10.0)
	car.explosive = true
	var shot := Hit.make(Hit.Kind.SHELL, 999.0, car.global_position)
	shot.source = world.player
	car.take_hit(shot)
	check(crawler.dead, "the wreck's blast kills the crawler")
	check(world.stats.style_feed.any(func(e: Dictionary) -> bool: return e.name == "COLLATERAL"), "credited as collateral")


func test_kill_tricks_named_by_weapon() -> void:
	var world := stage()
	for kind: Hit.Kind in [Hit.Kind.RAM, Hit.Kind.FIRE, Hit.Kind.THROWN]:
		var crawler := Crawler.new()
		crawler.position = Course.ground_at(world.rail.d + 60.0, 5.0)
		world.add_enemy(crawler)
		var hit := Hit.make(kind, 999.0, crawler.hit_center())
		hit.source = world.player
		crawler.take_hit(hit)
	var names := world.stats.style_feed.map(func(e: Dictionary) -> String: return e.name)
	for name in ["CRUSH", "BURNED", "THROWN", "MULTIKILL"]:
		check(name in names, "%s awarded" % name)


func test_high_style_heals_and_hits_cost_style() -> void:
	var world := stage()
	var tank := world.player
	world.stats.style = RunStats.STYLE_RANKS[3]
	tank.hp = 50.0
	world.style_event("CRUSH", 100.0)
	check(tank.hp > 50.0, "mayhem at rank B+ patches the hull")
	var style := world.stats.style
	tank.take_hit(Hit.make(Hit.Kind.SHELL, 20.0, tank.hit_center(), Vector3.FORWARD))
	check(world.stats.style < style, "getting hit costs style")
