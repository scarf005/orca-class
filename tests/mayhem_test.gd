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


func test_a_shell_kill_throws_the_wreck_on_along_the_shot() -> void:
	var world := stage()
	var ugv := Ugv.new()
	ugv.position = Course.ground_at(world.rail.d + 60.0, 0.0)
	world.add_enemy(ugv)
	await frames(2)
	var shot_dir := Course.right(world.rail.d + 60.0)
	var shot := Hit.make(Hit.Kind.SHELL, 9999.0, ugv.hit_center(), shot_dir)
	shot.caliber = 100
	shot.source = world.player
	ugv.take_hit(shot)
	var wrecks := world.get_children().filter(func(n: Node) -> bool: return n is Wreck)
	check_eq(wrecks.size(), 2, "hull and turret fly off as separate wrecks")
	var hull: Wreck = wrecks.filter(func(w: Wreck) -> bool: return w.explodes)[0]
	check(Vector3(hull.velocity.x, 0, hull.velocity.z).dot(shot_dir) > 8.0, "the hull is thrown on along the shot")
	check(wrecks.any(func(w: Wreck) -> bool: return not w.explodes), "the turret is a piece that just crashes")


func test_blast_push_follows_the_attack() -> void:
	check(Enemy.kill_push(null) == Vector3.ZERO, "no hit, no push")
	var shell := Hit.make(Hit.Kind.SHELL, 1.0, Vector3.ZERO, Vector3(1, -0.5, 0).normalized())
	check(Enemy.kill_push(shell).dot(Vector3.RIGHT) > 0.99 and Enemy.kill_push(shell).y >= 0.0, "shells push along the flight, never into the ground")
	var bullet := Hit.make(Hit.Kind.BULLET, 1.0, Vector3.ZERO, Vector3.RIGHT)
	check(Enemy.kill_push(bullet).length() < Enemy.kill_push(shell).length() * 0.5, "bullets barely nudge")


func test_held_pieces_fall_away_from_the_blow() -> void:
	var world := stage()
	var tank := world.player
	var trunk := _prop(world, "zelkova_trunk", tank.global_position + Vector3(0, 0, -40.0), 260.0)
	var crown := _prop(world, "zelkova_canopy", trunk.global_position + Vector3.UP * 5.0, 150.0)
	trunk.supports.append(crown)
	var shot := Hit.make(Hit.Kind.SHELL, 999.0, trunk.global_position, Vector3.RIGHT)
	shot.source = tank
	trunk.take_hit(shot)
	await frames(20)
	check(crown.global_basis.y.x > 0.05, "the crown tips over toward +X, the way the shot went")


func test_rammed_pole_snaps_falls_and_drops_its_wires() -> void:
	var world := stage()
	var scenery := world.director.scenery
	var pole: Scenery.Spec = null
	for spec in scenery.specs:
		if spec.kind == "pole" and scenery._wires_of.has(spec) and is_instance_valid(spec.node):
			pole = spec
			break
	check(pole != null, "a streamed-in pole with wires exists")
	if pole == null:
		return
	var prop := pole.node as Prop
	var ram := Hit.make(Hit.Kind.RAM, 99999.0, prop.global_position, Vector3.RIGHT)
	ram.source = world.player
	prop.take_hit(ram)
	check(not prop.dead and prop.is_falling(), "the pole snaps and goes over instead of vanishing")
	var wires: Array = scenery._wires_of[pole]
	check(wires.all(func(w: Scenery.Spec) -> bool: return w.has_meta("cut")), "its wires snap")
	var fell := await wait_until(gone(prop), 90)
	check(fell, "it breaks up when it hits the ground")


func test_kill_chains_escalate_and_break_on_a_gap() -> void:
	var world := stage()
	var chains: Array[String] = []
	world.kill_chain.connect(func(trick: String, _kills: int) -> void: chains.append(trick))
	var kill := func() -> void:
		var crawler := Crawler.new()
		crawler.position = Course.ground_at(world.rail.d + 60.0, 5.0)
		world.add_enemy(crawler)
		var hit := Hit.make(Hit.Kind.SHELL, 999.0, crawler.hit_center())
		hit.source = world.player
		crawler.take_hit(hit)
	for i in 10:
		kill.call()
	check_eq(chains, ["MULTIKILL", "MASSACRE", "ANNIHILATION"] as Array[String], "a chain earns each step once")
	chains.clear()
	world.stats.time += World.CHAIN_GAP + 0.1
	for i in 2:
		kill.call()
	check(chains.is_empty(), "a gap starts a new chain")
	kill.call()
	check_eq(chains, ["MULTIKILL"] as Array[String], "the new chain counts from one")
