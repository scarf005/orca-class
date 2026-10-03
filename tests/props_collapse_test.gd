extends TestCase
## Cause-driven scenery deaths; no unrelated stage encounters or stale suite expectations.


func _scene() -> World:
	_world = World.new()
	add_child(_world)
	_world.set_process(false)
	return _world


func _prop(world: World, kind := "house") -> Prop:
	var cfg: Array = Scenery.PROPS[kind]
	var prop := Prop.new()
	prop.setup(kind, PropKit.mesh(kind, 1), cfg[0], cfg[1], cfg[2])
	prop.position = Course.ground_at(100.0, 12.0)
	prop.falls = kind in Scenery.FALLING
	world.props.add_child(prop)
	return prop


func _motion(world: World) -> Prop.Collapse:
	for child in world.props.get_children():
		if child is Prop.Collapse:
			child.set_process(false)
			return child
	return null


func test_shell_and_its_blast_tear_buildings_apart() -> void:
	var world := _scene()
	var house := _prop(world)
	for kind: Hit.Kind in [Hit.Kind.SHELL, Hit.Kind.BLAST]:
		var hit := Hit.make(kind, 100.0, house.hit_center(), Vector3.RIGHT)
		hit.caliber = 100
		check_eq(house.collapse_style(hit), Prop.CollapseStyle.TORN, "100 mm direct and splash tear apart")
		hit.caliber = 99
		check_eq(house.collapse_style(hit), Prop.CollapseStyle.SINK, "smaller shell and blast sink")


func test_coax_and_chain_blast_sink_in_smoke_with_roof_first() -> void:
	var world := _scene()
	var house := _prop(world)
	var hit := Hit.make(Hit.Kind.BULLET, 100.0, house.hit_center())
	hit.caliber = 8
	check_eq(house.collapse_style(hit), Prop.CollapseStyle.SINK, "coax kill sinks")
	var chain := Hit.make(Hit.Kind.BLAST, 250.0, house.hit_center())
	chain.weapon = "collateral"
	check_eq(house.collapse_style(chain), Prop.CollapseStyle.SINK, "heavy chain blast is not a main-gun shell")
	house.take_hit(hit)
	var motion := _motion(world)
	check(motion != null, "dead prop leaves an animated visual")
	if motion == null:
		return
	motion._process(0.2)
	check(motion.pieces.any(func(p: MeshInstance3D) -> bool: return p.position.y < -0.1), "upper chunks cave first")
	check(motion.pieces.any(func(p: MeshInstance3D) -> bool: return p.position.y == 0.0), "walls have not caved with the roof")
	check(world.fx._pools[Fx.Kind.GLOW].size() > 0, "base and window smoke emitted")
	motion._process(1.0)
	check(motion.is_queued_for_deletion(), "sink finishes in 1.2 seconds")


func test_ram_flattens_along_travel_and_throws_debris_ahead() -> void:
	var world := _scene()
	var house := _prop(world)
	var hit := Hit.make(Hit.Kind.RAM, 100.0, house.hit_center(), Vector3.RIGHT)
	hit.speed = 22.0
	check_eq(house.collapse_style(hit), Prop.CollapseStyle.RAM, "speed ram flattens")
	house.take_hit(hit)
	var motion := _motion(world)
	check(motion != null, "ram has an animated visual")
	if motion == null:
		return
	var start := motion.global_position
	motion._process(0.3)
	check(motion.global_position.x > start.x, "building moves along travel, not its own forward axis")
	check(motion.global_basis.y.length() < 0.8, "building compresses while it falls")
	var shards: Array = world.fx._pools[Fx.Kind.SOLID]
	check(shards.any(func(p: Fx.Particle) -> bool: return p.velocity.x > 12.0), "ram debris flies ahead")


func test_tall_props_topple_but_shell_and_fire_override() -> void:
	var world := _scene()
	for kind in ["church_tower", "church_spire", "overpass_pier", "pole", "fungal_spire"]:
		var prop := _prop(world, kind)
		var hit := Hit.make(Hit.Kind.BULLET, 999.0, prop.hit_center(), Vector3.RIGHT)
		check_eq(prop.collapse_style(hit), Prop.CollapseStyle.TOPPLE, "%s falls rigidly" % kind)
		hit.kind = Hit.Kind.SHELL
		hit.caliber = 100
		check_eq(prop.collapse_style(hit), Prop.CollapseStyle.TORN, "%s shell wins over height" % kind)
		hit.kind = Hit.Kind.FIRE
		check_eq(prop.collapse_style(hit), Prop.CollapseStyle.BURN, "%s fire wins over height" % kind)
	var pier := _prop(world, "overpass_pier")
	pier.take_hit(Hit.make(Hit.Kind.RAM, 99999.0, pier.hit_center(), Vector3.RIGHT))
	var motion := _motion(world)
	check(motion != null, "overkill still topples the pier")
	if motion == null:
		return
	motion._process(0.6)
	check(motion.global_basis.y.x > 0.2, "topples in the push direction")
	check_near(motion.global_basis.y.length(), 1.0, 0.001, "rigid body is not flattened")
	motion._process(0.6)
	check(motion.is_queued_for_deletion(), "breaks on impact")
	check(not world.fx._transients.is_empty(), "ground shock ring emitted")


func test_fire_burns_before_collapsing_and_leaves_a_heap() -> void:
	var world := _scene()
	var house := _prop(world)
	var hit := Hit.make(Hit.Kind.FIRE, 1000.0, house.hit_center())
	check_eq(house.collapse_style(hit), Prop.CollapseStyle.BURN, "burning ground burns down")
	var dragon := Hit.make(Hit.Kind.BLAST, 100.0, house.hit_center())
	dragon.incendiary = true
	dragon.caliber = 100
	check_eq(house.collapse_style(dragon), Prop.CollapseStyle.BURN, "incendiary main-gun delivery burns instead of tearing")
	house.take_hit(hit)
	var motion := _motion(world)
	check(motion != null, "fire leaves an animated visual")
	if motion == null:
		return
	var start := motion.global_position
	motion._process(2.0)
	check_near(motion.global_position.y, start.y, 0.001, "still standing during the burn")
	check(not world.fx._pools[Fx.Kind.FLAME].is_empty(), "visible flames while standing")
	motion._process(1.4)
	check(motion.global_position.y < start.y - 0.1, "sinks after the burn")
	motion._process(0.7)
	check(motion.is_queued_for_deletion(), "burn and collapse finish")
	check(motion.pieces.all(func(p: MeshInstance3D) -> bool: return p.get_parent() == world.props), "leaves flattened smoking heap without bespoke rubble")


func test_flying_piece_cap_and_exactly_one_landing_blast() -> void:
	var world := _scene()
	for kind in Prop.BUILDINGS:
		if not Scenery.PROPS.has(kind):
			continue
		var prop := _prop(world, kind)
		var before := Wreck._live.size()
		var hit := Hit.make(Hit.Kind.SHELL, 99999.0, prop.hit_center(), Vector3.RIGHT)
		hit.caliber = 100
		hit.speed = 400.0
		prop.take_hit(hit)
		var pieces := Wreck._live.slice(before)
		check(pieces.size() > 1 and pieces.size() <= PropKit.COLLAPSE_PIECES, "%s flies as 2–12 pieces" % kind)
		check_eq(pieces.filter(func(w: Wreck) -> bool: return w.explodes).size(), 1, "%s only biggest piece explodes on landing" % kind)
		check(pieces.all(func(w: Wreck) -> bool: return w.velocity.y > 0.0), "%s pieces launch upward" % kind)


func test_shell_speed_scales_energy_for_direct_and_splash() -> void:
	var world := _scene()
	for kind: Hit.Kind in [Hit.Kind.SHELL, Hit.Kind.BLAST]:
		var speeds: Array[float] = []
		for speed in [130.0, 520.0]:
			seed(17)
			var prop := _prop(world)
			var before := Wreck._live.size()
			var hit := Hit.make(kind, 999.0, prop.hit_center(), Vector3.RIGHT)
			hit.caliber = 100
			hit.speed = speed
			prop.take_hit(hit)
			var wreck := Wreck._live[before]
			speeds.append(wreck.velocity.length())
		check(speeds[1] > speeds[0] * 1.3, "faster direct and splash hits launch faster")


func test_hitstop_and_death_callbacks_do_not_wait_for_animation() -> void:
	var world := _scene()
	var house := _prop(world)
	house.score = 50
	var callbacks: Array[Entity] = []
	house.died.connect(func(e: Entity) -> void: callbacks.append(e))
	house.take_hit(Hit.make(Hit.Kind.BULLET, 100.0, house.hit_center()))
	check_eq(callbacks.size(), 1, "loot/death callback happens immediately once")
	check(house.dead and house not in world.props.in_radius(house.global_position, 1.0), "dead building is no longer a collision target")
	var motion := _motion(world)
	if motion == null:
		check(false, "collapse visual exists")
		return
	world.hitstop(0.5)
	motion._process(0.02)
	check_near(motion.age, 0.4, 0.001, "visual motion uses unfrozen time")
	var crate := _prop(world, "crate")
	check_eq(crate.collapse_style(Hit.make(Hit.Kind.SHELL, 999.0, crate.hit_center())), Prop.CollapseStyle.NONE, "small clutter keeps existing break path")
