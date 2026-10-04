extends TestCase
## Destruction: crushing buildings and enemies, collateral chains, style from kills.


func _prop(world: World, kind: String, at: Vector3, hp: float) -> Prop:
	var prop := Prop.new()
	prop.setup(kind, PropKit.mesh(kind, 0), 2.5, 4.0, hp)
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


func test_high_style_does_not_heal_and_hits_cost_style() -> void:
	var world := stage()
	var tank := world.player
	world.stats.style = RunStats.STYLE_RANKS[3]
	tank.hp = 50.0
	world.style_event("CRUSH", 100.0)
	check_eq(tank.hp, 50.0, "high style does not patch the hull")
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
	# A shell kill dismembers even below the overkill threshold.
	var shot := Hit.make(Hit.Kind.SHELL, ugv.max_hp * 2.0, ugv.hit_center(), shot_dir)
	shot.caliber = 100
	shot.source = world.player
	ugv.take_hit(shot)
	var wrecks := world.get_children().filter(func(n: Node) -> bool: return n is Wreck)
	check(wrecks.size() > 2, "the hull, turret and other model pieces fly separately")
	check_eq(wrecks.filter(func(w: Wreck) -> bool: return w.explodes).size(), 1, "only the biggest piece explodes on landing")
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


func test_rammed_pole_shatters_at_once_and_drops_its_wires() -> void:
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
	check(prop.dead, "the pole breaks the moment the tank hits it")
	var wires: Array = scenery._wires_of[pole]
	check(wires.all(func(w: Scenery.Spec) -> bool: return w.has_meta("cut")), "its wires snap")


func test_shot_pole_still_topples() -> void:
	var world := stage()
	var pole := _prop(world, "pole", world.player.global_position + Vector3(0, 0, -40.0), 25.0)
	pole.falls = true
	var shot := Hit.make(Hit.Kind.SHELL, 50.0, pole.global_position, Vector3.RIGHT)
	shot.source = world.player
	var before := Wreck._live.size()
	pole.take_hit(shot)
	check(pole.dead, "the snapped pole stops being a collision target immediately")
	var pieces := Wreck._live.slice(before)
	check(not pieces.is_empty() and pieces.all(func(w: Wreck) -> bool: return w.velocity.x > 0.0 and not w.explodes), "pole pieces topple along the blow without exploding")


func test_overkill_hurls_wrecks_and_shatters_the_rest() -> void:
	var world := stage()
	var shot_dir := Course.right(world.rail.d + 60.0)
	var ugv := Ugv.new()
	ugv.position = Course.ground_at(world.rail.d + 60.0, 0.0)
	world.add_enemy(ugv)
	var drone := FpvDrone.new()
	drone.position = Course.ground_at(world.rail.d + 60.0, 8.0) + Vector3.UP * 6.0
	world.add_enemy(drone)
	await frames(2)
	# The real 100 mm round, the way every cannon kill lands.
	var shot := Hit.make(Hit.Kind.SHELL, Armament.SHELL_DAMAGE, ugv.hit_center(), shot_dir)
	shot.caliber = 100
	shot.source = world.player
	var shards: int = world.fx._pools[Fx.Kind.SOLID].size()
	ugv.take_hit(shot)
	check(ugv.overkilled, "more than three times its health is an overkill")
	var hulls := world.get_children().filter(func(n: Node) -> bool: return n is Wreck and n.explodes)
	check_eq(hulls.size(), 1, "a vehicle still leaves a wreck to fly and blow up again")
	if hulls.size() == 1:
		var hull: Wreck = hulls[0]
		check(Vector3(hull.velocity.x, 0, hull.velocity.z).dot(shot_dir) > 12.0, "an overkill throws it harder than a plain kill")
	check(world.fx._pools[Fx.Kind.SOLID].size() > shards + 20, "and tears plenty of shards off it")
	var wrecks := world.get_children().filter(func(n: Node) -> bool: return n is Wreck).size()
	drone.take_hit(Hit.make(Hit.Kind.SHELL, Armament.SHELL_DAMAGE, drone.hit_center(), shot_dir))
	check_eq(world.get_children().filter(func(n: Node) -> bool: return n is Wreck).size(), wrecks, "anything without a hull only bursts into shards")
	var pole := _prop(world, "house", world.player.global_position + Vector3(0, 0, -40.0), 100.0)
	pole.rubble_mesh = PropKit.mesh("rubble", 0)
	var before := world.props.get_child_count()
	pole.take_hit(Hit.make(Hit.Kind.SHELL, 301.0, pole.global_position))
	check_eq(world.props.get_child_count(), before, "an overkilled building leaves no rubble")
	var house := _prop(world, "house", world.player.global_position + Vector3(0, 0, -60.0), 100.0)
	house.rubble_mesh = PropKit.mesh("rubble", 0)
	before = Wreck._live.size()
	house.take_hit(Hit.make(Hit.Kind.SHELL, 299.0, house.global_position))
	check(Wreck._live.size() > before + 1, "a plain building kill also tears off its roof and walls")


func test_shards_scale_with_the_size_of_what_broke() -> void:
	var world := stage()
	var pool: Array = world.fx._pools[Fx.Kind.SOLID]
	world.fx.shatter(AABB(Vector3.ZERO, Vector3.ONE), [Fx.Debris.ROCK])
	var small := pool.size()
	var small_size: float = pool.map(func(p: Fx.Particle) -> float: return p.size).max()
	pool.clear()
	world.fx.shatter(AABB(Vector3.ZERO, Vector3.ONE * 6.0), [Fx.Debris.ROCK])
	check(pool.size() > small * 5, "a big thing breaks into many more shards")
	check(pool.map(func(p: Fx.Particle) -> float: return p.size).max() > small_size * 2.5, "and bigger ones")
	check(pool.all(func(p: Fx.Particle) -> bool: return p.trail.a > 0.0), "every shard trails smoke")


## Runs `breaks` shatters of `bounds` and returns each one's shards as an array of particles.
func _breaks(world: World, breaks: int, bounds: AABB, materials: Array, push := Vector3.ZERO) -> Array:
	var pool: Array = world.fx._pools[Fx.Kind.SOLID]
	var all := []
	for _i in breaks:
		pool.clear()
		world.fx.shatter(bounds, materials, push)
		all.append(pool.duplicate())
	pool.clear()
	return all


func _mean_flat(shards: Array) -> Vector2:
	var sum := Vector2.ZERO
	for p: Fx.Particle in shards:
		sum += Vector2(p.velocity.x, p.velocity.z)
	return sum / shards.size()


func test_shatter_count_varies_per_break_within_bounds() -> void:
	seed(7)
	var world := stage()
	var box := AABB(Vector3(-1.5, 0, -1.5), Vector3(3, 3, 3))
	var counts := _breaks(world, 60, box, [Fx.Debris.ROCK]).map(func(b: Array) -> int: return b.size())
	var distinct := {}
	for c: int in counts:
		distinct[c] = true
		check(c >= 3 and c <= 70, "count %d stays within the clamp" % c)
	check(distinct.size() >= 3, "the same box sheds different counts (%d distinct)" % distinct.size())
	var old := int(1.5 * pow(27.0, 2.0 / 3.0))
	var mean := float(counts.reduce(func(a: int, b: int) -> int: return a + b, 0)) / counts.size()
	check(mean <= old * 1.1, "the average count stays near the old formula (%.1f vs %d)" % [mean, old])
	var tiny := _breaks(world, 40, AABB(Vector3.ZERO, Vector3.ONE * 0.3), [Fx.Debris.ROCK]).map(func(b: Array) -> int: return b.size())
	check(tiny.all(func(c: int) -> bool: return c == 3), "tiny things keep the minimum")
	var huge := _breaks(world, 20, AABB(Vector3.ZERO, Vector3.ONE * 30.0), [Fx.Debris.ROCK]).map(func(b: Array) -> int: return b.size())
	check(huge.all(func(c: int) -> bool: return c <= 70), "huge things stay under the cap")


func test_shatter_mixes_a_few_big_chunks_with_many_small_bits() -> void:
	seed(11)
	var world := stage()
	var box := AABB(Vector3(-2, 0, -2), Vector3(4, 4, 4))
	var ratios := 0
	for shards: Array in _breaks(world, 30, box, [Fx.Debris.ROCK]):
		var sizes := shards.map(func(p: Fx.Particle) -> float: return p.size)
		sizes.sort()
		if sizes[-1] >= sizes[sizes.size() / 2] * 2.0:
			ratios += 1
	check_eq(ratios, 30, "the largest shard is at least twice the median in every break")


func test_shatter_direction_differs_per_break_but_follows_a_push() -> void:
	seed(3)
	var world := stage()
	var box := AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
	var means := _breaks(world, 40, box, [Fx.Debris.ROCK]).map(_mean_flat)
	var off_center := means.filter(func(m: Vector2) -> bool: return m.length() > 0.8)
	check(off_center.size() >= 10, "many breaks lean to one side (%d of 40)" % off_center.size())
	var pushed := _breaks(world, 40, box, [Fx.Debris.ROCK], Vector3.RIGHT * 2.0)
	var along := 0
	for shards: Array in pushed:
		if _mean_flat(shards).x > 5.0:
			along += 1
	check_eq(along, 40, "a strong push carries the pieces on along the blow")


func test_shatter_picks_materials_at_random() -> void:
	seed(5)
	var world := stage()
	var mats := [Fx.Debris.ROCK, Fx.Debris.WOOD, Fx.Debris.METAL]
	var box := AABB(Vector3(-2, 0, -2), Vector3(4, 4, 4))
	var ordered := 0
	var seen := {}
	for shards: Array in _breaks(world, 20, box, mats):
		var in_order := true
		for i in shards.size():
			var material: int = shards[i].layer / Fx.DEBRIS_VARIANTS
			seen[material] = true
			in_order = in_order and material == mats[i % 3]
		if in_order:
			ordered += 1
	check(ordered < 3, "materials do not cycle in list order (%d of 20 did)" % ordered)
	check_eq(seen.size(), 3, "every listed material shows up")


func test_ramming_a_landmark_takes_what_it_holds_at_once_without_stopping_the_tank() -> void:
	var world := stage()
	var tank := world.player
	await frames(3)
	var trunk := _prop(world, "zelkova_trunk", tank.global_position + Vector3(0, 0, -1.0), 260.0)
	var crown := _prop(world, "zelkova_canopy", trunk.global_position + Vector3.UP * 5.0, 150.0)
	trunk.supports.append(crown)
	var speed := tank.local_velocity.y
	await frames(2)
	check(not is_instance_valid(trunk) or trunk.dead, "the trunk breaks on contact")
	check(not is_instance_valid(crown) or crown.dead, "the crown goes with it instead of toppling later")
	check_eq(world._hitstop, 0.0, "no frozen frame")
	check(tank.local_velocity.y >= speed - 0.01, "no lost speed")


func test_kill_chains_escalate_and_break_on_a_gap() -> void:
	var world := stage()
	var chains := func() -> Array:
		var names := world.stats.style_feed.map(func(e: Dictionary) -> String: return e.name)
		return names.filter(func(n: String) -> bool: return n in ["MULTIKILL", "MASSACRE", "ANNIHILATION"])
	var kill := func() -> void:
		var crawler := Crawler.new()
		crawler.position = Course.ground_at(world.rail.d + 60.0, 5.0)
		world.add_enemy(crawler)
		var hit := Hit.make(Hit.Kind.SHELL, 999.0, crawler.hit_center())
		hit.source = world.player
		crawler.take_hit(hit)
	for i in 10:
		kill.call()
	check_eq(chains.call(), ["ANNIHILATION", "MASSACRE", "MULTIKILL"], "a chain earns each step once")
	world.stats.style_feed.clear()
	world.stats.time += World.CHAIN_GAP + 0.1
	for i in 2:
		kill.call()
	check(chains.call().is_empty(), "a gap starts a new chain")
	kill.call()
	check_eq(chains.call(), ["MULTIKILL"], "the new chain counts from one")
