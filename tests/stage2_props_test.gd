extends TestCase
## Stage 2's props and layout: the new meshes, what they break into, floating debris and where
## everything stands.

const NEW_KINDS := ["silage", "transplanter", "watch_hut", "scarecrow", "willow", "pylon", "pump_house", "mill_hall", "rpc_silo", "vent", "sluice"]


func _specs() -> Array[Scenery.Spec]:
	Course.use(2)
	var scenery := Scenery.new()
	add_child(scenery)
	scenery.build()
	var specs := scenery.specs.duplicate()
	remove_child(scenery)
	scenery.free()
	var typed: Array[Scenery.Spec] = []
	typed.assign(specs)
	return typed


func test_every_new_prop_has_a_mesh_of_its_size_and_its_own_debris() -> void:
	var scenery := Scenery.new()
	for kind: String in NEW_KINDS + ["lotus"]:
		var mesh := PropKit.mesh(kind, 0)
		check(mesh.get_faces().size() > 30, "%s has a mesh" % kind)
		if kind == "lotus":
			continue
		check(Scenery.PROPS.has(kind), "%s is a prop" % kind)
		var box := mesh.get_aabb()
		var cfg: Array = Scenery.PROPS[kind]
		check(absf(box.end.y - cfg[1]) < cfg[1] * 0.4 + 0.5, "%s stands about as tall as its table says (%.1f vs %.1f)" % [kind, box.end.y, cfg[1]])
		check(maxf(box.size.x, box.size.z) * 0.5 > cfg[0] * 0.6, "%s is about as wide as its footprint (%.1f vs %.1f)" % [kind, maxf(box.size.x, box.size.z) * 0.5, cfg[0]])
		var debris: Array = scenery._debris(kind)
		if kind not in ["vent"]:
			check(debris != [Fx.Debris.CONCRETE, Fx.Debris.WOOD], "%s breaks into its own materials" % kind)
	scenery.free()
	var expected := {"silage": Fx.Debris.VINYL, "transplanter": Fx.Debris.METAL, "watch_hut": Fx.Debris.STRAW, "scarecrow": Fx.Debris.STRAW, "willow": Fx.Debris.FOLIAGE, "pylon": Fx.Debris.METAL, "pump_house": Fx.Debris.METAL, "mill_hall": Fx.Debris.ROOF, "rpc_silo": Fx.Debris.ROCK, "sluice": Fx.Debris.CONCRETE}
	var checker := Scenery.new()
	for kind: String in expected:
		check(expected[kind] in checker._debris(kind), "%s breaks into the right stuff" % kind)
	checker.free()
	check("willow" in Scenery.FALLING and "pylon" in Scenery.FALLING, "willows and pylons topple")
	check("transplanter" in Scenery.VEHICLES, "the transplanter is run over like a vehicle")


func test_the_layout_stands_where_it_should() -> void:
	var specs := _specs()
	check(specs.size() > 300, "a full course (%d specs)" % specs.size())
	var kinds := {}
	for spec in specs:
		if spec.decor or not spec.pickup.is_empty():
			continue
		kinds[spec.kind] = true
		check(Scenery.PROPS.has(spec.kind) or spec.kind == "slick", "%s is a known prop" % spec.kind)
		check(spec.d < Course.stage.gate_d + 5.0, "%s is not behind the gate" % spec.kind)
		var floating := spec.has_meta("floats")
		var depth := Course.stage.water_surface(Vector2(spec.d, spec.u)) - Course.height(spec.d, spec.u)
		if not floating and spec.kind not in ["rock", "spore_tower"] and Course.stage.water_surface(Vector2(spec.d, spec.u)) > -INF: # Those two stand tall out of the basin.
			check(depth <= Water.DEEP, "%s stands in %.2f m of water at %.0f,%.0f" % [spec.kind, depth, spec.d, spec.u])
		if spec.d > Course.stage.gate_d - 25.0:
			check(absf(spec.u) > Course.stage.gate_half + 10.0 or spec.kind == "rock" and false, "%s leaves the gate's footprint clear at %.0f,%.0f" % [spec.kind, spec.d, spec.u])
	for kind: String in NEW_KINDS:
		check(kinds.has(kind), "the course has %s" % kind)
	check(kinds.has("gas_station") and kinds.has("gas_pump"), "the flooded gas station")


func test_sluices_stand_on_dry_dikes_and_vents_and_slicks_in_the_marsh() -> void:
	var specs := _specs()
	var slicks := 0
	var lotus := 0
	for spec in specs:
		match spec.kind:
			"sluice":
				check_eq(absf(spec.u), 18.0, "a gate sits on the dike at u=18 (d=%.0f)" % spec.d)
				check_eq(Course.stage.water_surface(Vector2(spec.d, spec.u)), -INF, "and dry at d=%.0f" % spec.d)
				check(spec.d > 420.0 and spec.d < 1000.0, "in the paddies")
			"vent":
				check(Course.section_at(spec.d) == Stage2.Section.MARSH, "vents are in the marsh")
			"slick":
				slicks += 1
				check(Course.stage.water_surface(Vector2(spec.d, spec.u)) > -INF, "a slick lies on water")
				check(absf(spec.d - 1500.0) < 40.0, "near the gas station")
		if spec.decor and spec.mesh == PropKit.mesh("lotus", 0):
			lotus += 1
	check_eq(slicks, 2, "two slicks")
	check(lotus >= 3, "lotus pads float in the marsh (%d)" % lotus)


func test_the_mill_compound_fills_the_yard_and_holds_together() -> void:
	var specs := _specs()
	var pieces := specs.filter(func(s: Scenery.Spec) -> bool: return s.kind in ["mill_hall", "rpc_silo"])
	check_eq(pieces.size(), 4, "a mill and three silos")
	for spec: Scenery.Spec in pieces:
		check(spec.d > 1000.0 and spec.d < 1260.0 and absf(spec.u) < 70.0, "%s stands in the mill yard (%.0f, %.0f)" % [spec.kind, spec.d, spec.u])
		check(absf(spec.u) > 30.0, "clear of the mid-boss's lane")


func test_floating_debris_bobs_drifts_and_can_be_rammed() -> void:
	var world := stage("", true, 2)
	world.player.invulnerable = true
	world.rail.d = 100.0
	await frames(3)
	var floaters: Array[Prop] = []
	for node in world.props.get_children():
		if node is Prop and (node as Prop).floats:
			floaters.append(node)
	check(floaters.size() >= 5, "there are floaters in reach (%d)" % floaters.size())
	var start := {}
	var lows := {}
	var highs := {}
	for prop in floaters:
		start[prop] = Course.to_course(prop.global_position).x
		lows[prop] = INF
		highs[prop] = -INF
	for i in 120:
		await frames(1)
		for prop in floaters:
			if is_instance_valid(prop):
				lows[prop] = minf(lows[prop], prop.global_position.y)
				highs[prop] = maxf(highs[prop], prop.global_position.y)
	var moved := 0
	var bobbed := 0
	for prop in floaters:
		if not is_instance_valid(prop):
			continue
		var surface := Water.surface_at(prop.global_position)
		check(surface > -INF and absf(prop.global_position.y - surface) < prop.height * 0.5 + 0.2, "%s rides the surface" % prop.kind)
		if Course.to_course(prop.global_position).x - start[prop] > Prop.DRIFT_SPEED * 1.5:
			moved += 1
		if highs[prop] - lows[prop] > 0.03:
			bobbed += 1
	check(moved >= floaters.size() / 2, "most drift downstream, the rest are aground (%d of %d)" % [moved, floaters.size()])
	check(bobbed >= floaters.size() / 2, "and bob (%d of %d)" % [bobbed, floaters.size()])
	var alive := floaters.filter(func(p: Variant) -> bool: return is_instance_valid(p) and not p.dead)
	var victim: Prop = alive[0]
	victim.take_hit(Hit.make(Hit.Kind.RAM, 99.0, victim.global_position))
	check(victim.dead, "ramming one breaks it")
	var crushable := alive.filter(func(p: Variant) -> bool: return is_instance_valid(p) and not p.dead and p.crushable)
	check(crushable.size() > 0, "and some give way to the tail")


func test_a_tower_that_falls_takes_its_lines_down() -> void:
	var world := stage("", true, 2)
	world.player.invulnerable = true
	world.rail.d = 470.0
	world.director.scenery.stream(470.0, 100000)
	var pylons := world.director.scenery.specs.filter(func(s: Scenery.Spec) -> bool: return s.kind == "pylon" and is_instance_valid(s.node))
	check(pylons.size() >= 2, "towers stand along the paddies")
	var spec: Scenery.Spec = pylons[1]
	var wires: Array = world.director.scenery._wires_of.get(spec, [])
	check(wires.size() >= 3, "each carries lines to its neighbours (%d)" % wires.size())
	check(wires.all(func(w: Scenery.Spec) -> bool: return not w.has_meta("cut")), "intact at first")
	(spec.node as Prop).take_hit(Hit.make(Hit.Kind.RAM, 9999.0, spec.node.global_position))
	check(wires.all(func(w: Scenery.Spec) -> bool: return w.has_meta("cut")), "felling the tower snaps every line")
	check((spec.node as Prop).is_falling() or (spec.node as Prop).dead, "and the tower goes over")
