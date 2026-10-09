extends TestCase
## The flooded street has rubble, sinkholes and a pavement shelf, all of which the tank must be able to drive over.

const MAX_SLOPE := 0.30
const CANYON_MOUNDS := [2600.0, 2950.0]


func _hollow(feature: Dictionary) -> bool:
	return feature.h < 0.0


## Whether (d, u) lies on a deliberate mid-street obstacle: a canyon mound or a sinkhole across the street.
func _obstacle(d: float) -> bool:
	return Stage2.RELIEF.any(func(f: Dictionary) -> bool: return absf(d - f.d) < f.rz and (_hollow(f) or CANYON_MOUNDS.has(f.d)))


func test_driveable_terrain_gradient_stays_tank_safe() -> void:
	Course.use(2)
	var stage := Course.stage as Stage2
	var worst := 0.0
	for d in range(0, int(Stage2.LENGTH)):
		for u in range(-30, 30, 2):
			var limit := minf(stage.lateral_limit(d), stage.lateral_limit(d + 1.0)) - 1.0
			if absf(u) > limit or stage.in_arena(d, 2.0):
				continue
			var here := stage.height(d, u)
			worst = maxf(worst, Vector2(stage.height(d + 1.0, u) - here, stage.height(d, u + 1.0) - here).length())
	check(worst <= MAX_SLOPE, "no 1 m step of the drivable street climbs more than %.2f (worst %.3f)" % [MAX_SLOPE, worst])


func test_centre_strip_stays_flat_except_named_obstacles() -> void:
	Course.use(2)
	var stage := Course.stage as Stage2
	for d in range(0, int(Stage2.LENGTH), 2):
		if _obstacle(d):
			continue
		for u in range(-6, 7, 2):
			var h := stage.height(d, u)
			check(h >= -0.2 and h <= 0.4, "centre strip at d=%d u=%d stays within [-0.2, 0.4] (got %.2f)" % [d, u, h])
	for d in CANYON_MOUNDS:
		check(stage.height(d, 0.0) >= 1.0, "the canyon mound at d=%d rises over the road" % int(d))


func test_arenas_stay_exactly_flat() -> void:
	Course.use(2)
	for arena in Course.stage.arenas:
		for angle in 24:
			for ring in [0.0, 0.5, 0.99]:
				var p: Vector2 = Vector2.from_angle(TAU * angle / 24.0) * float(arena.radius) * ring
				check_eq(Course.stage.height(arena.d + p.x, p.y), -0.15, "arena at d=%d is level" % int(arena.d))


func test_sinkholes_cross_the_whole_street_and_stay_wadeable() -> void:
	Course.use(2)
	var stage := Course.stage as Stage2
	var hollows := Stage2.RELIEF.filter(_hollow)
	check_eq(hollows.size(), 4, "four sinkholes cross the street")
	for hollow: Dictionary in hollows:
		for u in [-stage.lateral_limit(hollow.d), -10.0, 0.0, 10.0, stage.lateral_limit(hollow.d)]:
			var h := stage.height(hollow.d, u)
			check(h <= stage.height(hollow.d + 40.0, u) - 1.0, "sinkhole at d=%d is at least 1 m below the road at u=%.0f" % [int(hollow.d), u])
			check(h >= -2.0, "sinkhole at d=%d is shallow enough for the tank and hunters to cross (%.2f)" % [int(hollow.d), h])


func test_pavement_shelf_stands_above_the_water_on_boulevard_and_canyon_only() -> void:
	Course.use(2)
	var stage := Course.stage as Stage2
	for d in [100.0, 420.0, 2300.0, 3100.0]:
		var wall := stage.lateral_limit(d)
		check(stage.height(d, wall - 1.0) >= Stage2.WATER_LEVEL + 0.3, "the shelf at d=%d is dry" % int(d))
		check_near(stage.height(d, wall - 8.0), 0.05, 0.9, "the road at d=%d stays low" % int(d))
		check(stage.ground_color(d, wall - 2.0, 0.75, 0.0) == Palette.CONCRETE, "the shelf is painted as pavement")
	for d in [800.0, 1200.0, 1600.0]:
		check_near(stage.height(d, stage.lateral_limit(d) - 1.0), 0.05, 0.001, "the viaduct keeps its flat awash road edge")


func test_rubble_is_painted_stone_and_awash_road_stays_slate() -> void:
	Course.use(2)
	var stage := Course.stage as Stage2
	var mound := stage.ground_color(790.0, 17.0, stage.height(790.0, 17.0), 0.0)
	check(mound == Palette.STONE or mound == Palette.ASH, "a rubble mound reads as stone or ash")
	check(stage.ground_color(1260.0, 0.0, -1.45, 0.0) == Palette.SLATE.darkened(0.35), "a sinkhole floor is darker than the road")
	check(stage.ground_color(790.0, 0.0, 0.05, 0.0) == Palette.SLATE, "the drowned road stays slate")


func test_wave_spawn_lanes_do_not_land_in_deep_sinkholes() -> void:
	Course.use(2)
	var stage := Course.stage as Stage2
	for hard in [false, true]:
		for event in stage.events(hard):
			if event.type != "wave":
				continue
			for member: Dictionary in [event] + event.get("squad", []):
				var d: float = event.d + float(member.get("ahead", event.get("ahead", 90.0)))
				var u: float = member.get("u", event.get("u", 0.0))
				if absf(u) <= stage.lateral_limit(d):
					check(stage.height(d, u) >= -2.0, "%s wave at d=%d spawns at d=%d u=%.1f on ground above -2 m" % [event.kind, int(event.d), int(d), u])


func test_pinned_scenery_is_never_buried_by_relief() -> void:
	var scenery := stage("", false, 2).director.scenery
	var checked := 0
	for spec in scenery.specs:
		if spec.size != Vector3.ZERO or spec.decor or not spec.has_meta("y"):
			continue
		checked += 1
		check(float(spec.get_meta("y")) >= Course.stage.height(spec.d, spec.u) - 0.001, "%s at d=%d u=%.1f stands on the ground, not inside it" % [spec.kind, int(spec.d), spec.u])
	check(checked > 100, "streetlamps, signs, rafts and rubble are all checked (%d)" % checked)


func _footprint(block: Dictionary) -> Rect2:
	return Rect2(block.d - block.size.z * 0.5, block.u - block.size.x * 0.5, block.size.z, block.size.x)


func test_backdrop_never_touches_front_structures_road_or_arenas() -> void:
	var stage := Stage2.new()
	check(not stage.backdrop.is_empty(), "the street has a skyline behind its frontage")
	for block in stage.backdrop:
		var rect := _footprint(block)
		check(minf(absf(rect.position.y), absf(rect.end.y)) >= stage.lateral_limit(block.d) + 30.0, "backdrop at d=%d u=%.0f keeps clear of the street" % [int(block.d), block.u])
		for structure in stage.structures:
			check(not rect.intersects(Rect2(structure.d - structure.size.z * 0.5, structure.u - structure.size.x * 0.5, structure.size.z, structure.size.x)), "backdrop at d=%d u=%.0f is clear of the %s at d=%d" % [int(block.d), block.u, structure.kind, int(structure.d)])
		for arena in stage.arenas:
			var corner := Vector2(clampf(arena.d, rect.position.x, rect.end.x), clampf(0.0, rect.position.y, rect.end.y))
			check(corner.distance_to(Vector2(arena.d, 0.0)) >= arena.radius + 20.0, "backdrop at d=%d u=%.0f stays out of the arena at d=%d" % [int(block.d), block.u, int(arena.d)])
		check(block.d + block.size.z * 0.5 <= Stage2.BAY_D - Stage2.BAY_RADIUS, "backdrop at d=%d stays on the land side of the bay" % int(block.d))
	for index in stage.backdrop.size():
		for other in range(index + 1, stage.backdrop.size()):
			check(not _footprint(stage.backdrop[index]).intersects(_footprint(stage.backdrop[other])), "backdrop blocks %d and %d do not overlap" % [index, other])


func test_backdrop_count_and_heights_are_bounded() -> void:
	var stage := Stage2.new()
	check(stage.backdrop.size() >= 250 and stage.backdrop.size() <= 350, "backdrop holds 250..350 blocks (%d)" % stage.backdrop.size())
	var rows := [[], []] # roof heights of the near and far rows
	for block in stage.backdrop:
		var roof: float = block.size.y - 4.5
		var warehouse: bool = block.d >= Stage2.SECTION_STARTS[Stage2.Section.BAY]
		check(roof >= (8.0 if warehouse else 22.0) and roof <= (14.0 if warehouse else 70.0), "backdrop at d=%d rises %.0f m, inside its class's range" % [int(block.d), roof])
		var setback: float = absf(block.u) - block.size.x * 0.5 - stage.lateral_limit(block.d)
		if not warehouse and (setback < 60.0 or setback > 85.0) and absf(block.u) < 150.0 and not stage.in_arena(block.d, 100.0):
			rows[0 if setback < 60.0 else 1].append(roof)
	check(not rows[0].is_empty() and not rows[1].is_empty(), "both backdrop rows exist")
	check(rows[1].reduce(func(a: float, b: float) -> float: return a + b, 0.0) / maxi(rows[1].size(), 1) >= rows[0].reduce(func(a: float, b: float) -> float: return a + b, 0.0) / maxi(rows[0].size(), 1) + 10.0, "the far row averages at least 10 m taller so the skyline rises")


func test_backdrop_plan_is_deterministic() -> void:
	var first := Stage2.new().backdrop
	var second := Stage2.new().backdrop
	check_eq(first.size(), second.size(), "the same seed lays out the same number of blocks")
	check_eq(first, second, "the same seed lays out the same blocks")


func test_backdrop_streams_as_non_colliding_chunked_decor() -> void:
	var scenery := stage("", false, 2).director.scenery
	var decor := scenery.specs.filter(func(spec: Scenery.Spec) -> bool: return spec.decor and spec.has_meta("range"))
	var boxes := Course.structure_boxes.size()
	check(decor.size() > 80 and decor.size() <= Stage2.LENGTH / Scenery.BACKDROP_CHUNK, "backdrop is merged to at most one decor per chunk (%d)" % decor.size())
	check_eq(Course.structure_boxes.size(), boxes, "backdrop adds no collision boxes")
	scenery.stream(900.0, 100000)
	var live := decor.filter(func(spec: Scenery.Spec) -> bool: return is_instance_valid(spec.node))
	check(not live.is_empty(), "backdrop chunks near the rail are streamed in")
	for spec: Scenery.Spec in live:
		check_near((spec.node as GeometryInstance3D).visibility_range_end, Scenery.BACKDROP_RANGE, 0.01, "backdrop stays visible out to the fog")


func test_ground_units_ride_over_a_sinkhole_instead_of_sinking_into_it() -> void:
	Course.use(2)
	var hole := Enemy.wading_at(620.0, 0.0)
	check_near(hole.y, Stage2.WATER_LEVEL - Enemy.WADE_DEPTH, 0.001, "a unit over the sinkhole rides just under the surface")
	var road := Enemy.wading_at(300.0, 4.0)
	check_near(road.y, Course.height(300.0, 4.0), 0.001, "a unit on the shallow road keeps the street bed")
