extends TestCase

const KINDS := ["streetlamp", "traffic_light", "road_sign", "raft", "city_rubble", "subway_entrance", "container", "ship"]


func _placed(world: World, kind: String) -> Scenery.Spec:
	var scenery := world.director.scenery
	for spec in scenery.specs:
		if spec.kind != kind or absf(spec.u) > Course.stage.lateral_limit(spec.d) or (kind == "container" and spec.d != 3570.0):
			continue
		if not is_instance_valid(spec.node):
			scenery._instantiate(spec)
		if spec.group >= 0:
			for piece in scenery.specs:
				if piece.group == spec.group and not is_instance_valid(piece.node):
					scenery._instantiate(piece)
		return spec
	return null


func test_cannon_destroys_each_placed_city_breakable() -> void:
	for kind in KINDS:
		var world := stage("", false, 2)
		var spec := _placed(world, kind)
		check(spec != null, "%s has a placed damageable prop" % kind)
		if spec == null:
			continue
		var prop := spec.node as Prop
		check(prop != null, "%s streams as a Prop" % kind)
		if prop == null:
			continue
		# Shoot the ship far from its central bucket; hit stacked containers below the upper box.
		var at := prop.global_transform * Vector3(20.0 if kind == "ship" else 0.0, prop.height * 0.5, 0.0)
		var approach := prop.box_size.z * 0.5 + 3.0 if prop.box_size != Vector3.ZERO else prop.footprint + 3.0
		world.player.current_round = Armament.Round.APFSDS
		world.player.round_count = 6
		world.player.fire_cannon(at + prop.global_basis.z * approach, -prop.global_basis.z, 1.0)
		check(prop.dead, "%s is destroyed by a main-gun hit" % kind)
		check(spec.has_meta("destroyed"), "%s destruction persists in the streaming plan" % kind)


func test_tank_rams_each_placed_city_breakable() -> void:
	for kind in KINDS:
		var world := stage("", false, 2)
		var spec := _placed(world, kind)
		check(spec != null, "%s has a placed ram target" % kind)
		if spec == null:
			continue
		var prop := spec.node as Prop
		if prop == null:
			check(false, "%s streams as a Prop" % kind)
			continue
		var at := prop.global_transform * Vector3(20.0 if kind == "ship" else 0.0, 0.0, 0.0)
		at.y = Course.height_at(at)
		world.player.global_position = at
		world.player._collide_props()
		check(prop.dead, "%s is destroyed through tank collision" % kind)


func test_destroyed_harbour_cover_releases_movement_sight_and_roof() -> void:
	for kind in ["container", "ship"]:
		var world := stage("", false, 2)
		var spec := _placed(world, kind)
		var prop := spec.node as Prop
		var at := prop.global_transform * Vector3(0.0, 1.0, 0.0)
		var from := at - prop.global_basis.z * (spec.size.z + 4.0)
		var to := at + prop.global_basis.z * (spec.size.z + 4.0)
		var scenery := world.director.scenery
		check(scenery.line_blocked(from, to), "%s initially blocks sight" % kind)
		prop.take_hit(Hit.make(Hit.Kind.SHELL, 9000.0, at))
		check(prop.dead, "%s accepts lethal damage" % kind)
		# Unsupported upper containers must fall through production's topple/death path.
		for upper: Prop in prop.supports:
			for _i in ceili(Prop.TOPPLE_TIME * 60.0) + 1:
				if upper.dead:
					break
				upper._process(1.0 / 60.0)
			check(upper.dead, "the unsupported upper container breaks after its fall")
		check(not Course.structure_boxes.any(func(box: Dictionary) -> bool: return box.d == spec.d and box.u == spec.u and box.size == spec.size), "%s persistent collision box is removed" % kind)
		check(not scenery.line_blocked(from, to), "%s no longer blocks sight" % kind)
		check(scenery.drive_position(at, at, Tank.HULL_RADIUS).is_equal_approx(at), "%s leaves no invisible movement barrier" % kind)
		check_eq(Course.surface_height(spec.d, spec.u), Course.height(spec.d, spec.u), "%s leaves no invisible roof" % kind)
		# Stream out first: a valid node must not mask a broken destroyed-metadata guard.
		scenery.stream(spec.d + Scenery.BEHIND + 1.0, 100000)
		check(spec.node == null, "%s dead node leaves the stream window" % kind)
		scenery._next = 0
		scenery.stream(spec.d, 100000)
		check(spec.node == null, "%s stays destroyed when its stream window is revisited" % kind)


func test_tower_and_crane_remain_outside_breakable_scope() -> void:
	var world := stage("", false, 2)
	var scenery := world.director.scenery
	var tower: Prop
	for spec in scenery.specs:
		if spec.kind == "city_building" and is_instance_valid(spec.node):
			tower = spec.node as Prop
			break
	check(tower != null, "the real stage streams a boundary tower")
	if tower != null:
		tower.take_hit(Hit.make(Hit.Kind.SHELL, 9000.0, tower.hit_center()))
		check(not tower.dead, "boundary towers remain invulnerable")
	check(scenery.specs.any(func(spec: Scenery.Spec) -> bool: return spec.decor and spec.mesh == CityKit.decor("crane")), "unreachable harbour cranes remain decorations")
