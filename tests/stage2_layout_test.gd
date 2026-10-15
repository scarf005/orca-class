extends TestCase
## The drowned downtown is five different spaces, and its gimmicks change how the tank drives.

const STEP := 1.0 / 60.0


func _city() -> World:
	var world := stage("", false, 2)
	world.director._next_event = world.director.events.size()
	return world


## Drives the tank up the kicker and off its lip, drifting across its track at the given `kicks` (rail metres past the
## ramp's foot); returns [whether it flew, rail distance where it came down, the height of the floor there, the tank's
## height over the floor two seconds later].
func _kicker_run(kicks: Array) -> Array:
	var world := _city()
	var tank := world.player
	var foot := float(Stage2.RAMPS[Stage2.KICKER].d)
	world.rail.d = foot - 20.0
	tank.course_u = 0.0
	tank.tick(STEP)
	var flew := false
	var next := 0
	var side := 1.0
	for _i in ceili(14.0 / STEP):
		var progress := world.rail.d - foot
		if next < kicks.size() and progress >= float(kicks[next]) and not tank.airborne and tank.anchor_cooldown <= 0.0:
			tank.dash(Vector2(side, 0))
			side = -side
			next += 1
		tank.tick(STEP)
		world._process(STEP)
		flew = flew or tank.airborne
		if flew and not tank.airborne:
			break
	var d := world.rail.d + tank.course_offset
	var landed := Course.height(d, tank.course_u)
	for _i in ceili(2.0 / STEP):
		tank.tick(STEP)
		world._process(STEP)
	return [flew, d, landed, tank.global_position.y - Course.height(world.rail.d + tank.course_offset, tank.course_u)]


func test_a_drifted_run_up_the_kicker_leaps_the_collapsed_span() -> void:
	var result := _kicker_run([2.0, 22.0, 42.0])
	check(result[0], "the drifted tank leaves the lip")
	check(result[1] >= Stage2.GAP.y - 2.0, "it lands on the far deck, past the break at d=%d (landed at %.0f)" % [int(Stage2.GAP.y), result[1]])
	check(result[2] >= Stage2.FAR_DECK_H - 0.5, "up on the far deck (floor %.2f)" % result[2])


func test_a_plain_run_up_the_kicker_falls_short_onto_the_hanging_span_and_climbs_out() -> void:
	var result := _kicker_run([])
	check(result[0], "the tank still leaves the lip")
	check(result[1] < Stage2.GAP.y - 2.0, "an undrifted leap comes down inside the break (landed at %.0f)" % result[1])
	check(result[2] < Stage2.FAR_DECK_H - 3.0, "low on the far span's hanging end (floor %.2f)" % result[2])
	check(absf(result[3]) < 0.5, "and drives on up it rather than sinking or flying (%.2f m off the floor)" % result[3])


## The slab's hinge tower as a collision box, or an empty dictionary once it has come down.
func _slab_box() -> Dictionary:
	var lip := Stage2.ramp_lip(Stage2.SLAB)
	for box: Dictionary in Course.structure_boxes:
		if box.kind == "city_building" and absf(box.d - (lip - 3.0)) < 0.01:
			return box
	return {}


func test_the_tower_groans_before_it_falls_and_lands_flush_with_the_slab_ramp() -> void:
	var world := _city()
	var scenery := world.director.scenery
	scenery.stream(Stage2.ramp_lip(Stage2.SLAB), 100000)
	check(not _slab_box().is_empty(), "the tower stands on the rubble before the event")
	world.director._fire({"type": "topple"})
	var tower: ToppleTower
	for child in world.get_children():
		if child is ToppleTower:
			tower = child
	check(tower != null, "the topple event adds the falling tower")
	check(_slab_box().is_empty(), "the standing tower's collision is gone once it is replaced by the falling one")
	var lean := func() -> float: return tower._tower.global_basis.y.angle_to(Vector3.UP)
	var time := 0.0
	while time < ToppleTower.GROAN - 0.1:
		tower._process(STEP)
		time += STEP
	check(lean.call() < 0.12 and not tower._landed, "for %.1f s it only groans and leans (%.2f rad)" % [ToppleTower.GROAN, lean.call()])
	while time < ToppleTower.GROAN + ToppleTower.FALL + 0.2:
		tower._process(STEP)
		time += STEP
	check(tower._landed, "after the fall it has landed")
	var arrival := (float(Stage2.RAMPS[Stage2.SLAB].d) - Stage2.TOPPLE_D) / Rail.CRUISE
	check(arrival >= ToppleTower.GROAN + ToppleTower.FALL, "a cruising tank reaches the slab %.1f s after the groan starts, once it has landed" % arrival)
	var axis := tower._tower.global_basis.y
	var slope := atan2(-axis.y, Vector2(axis.x, axis.z).length())
	var ramp: Dictionary = Stage2.RAMPS[Stage2.SLAB]
	check_near(slope, atan2(float(ramp.height), float(ramp.length)), 0.01, "the fallen slab lies at the slope of the ramp it lands on")


func test_the_slab_ramp_throws_a_tank_off_its_lip_and_the_other_lane_stays_open() -> void:
	var world := _city()
	var tank := world.player
	var ramp: Dictionary = Stage2.RAMPS[Stage2.SLAB]
	world.rail.d = float(ramp.d) - 20.0
	tank.course_u = float(ramp.u)
	tank.tick(STEP)
	var flew := false
	for _i in ceili(8.0 / STEP):
		tank.tick(STEP)
		world._process(STEP)
		flew = flew or tank.airborne
		if flew and not tank.airborne:
			break
	check(flew, "driving up the fallen slab leaps off its lip")
	var lip := Stage2.ramp_lip(Stage2.SLAB)
	var swerve := Stage2.new()
	check(swerve.ramp_at(lip - 10.0, float(ramp.u) + 12.0) < 0.0, "the lane beside the slab is not a ramp")
	check(swerve.height(lip - 10.0, float(ramp.u) + 12.0) < 1.0, "and stays low ground a tank swerves round it on")


## Puts the tank at (d, u) in the surge's stretch and lets a surge whose front has just reached it run one frame.
## Returns the surge so the caller can read its effect on the tank and the rail.
func _surged(u: float, d := Stage2.SURGE_D) -> TidalSurge:
	var world := _city()
	world.rail.d = d
	world.player.course_u = u
	world.player.tick(STEP)
	var surge := TidalSurge.new()
	surge.d = Stage2.SURGE_D
	world.add_child(surge)
	surge.front = Course.to_course(world.player.global_position).y + 2.0
	surge._process(0.0)
	return surge


func test_the_surge_line_is_in_sight_two_seconds_before_it_reaches_the_street() -> void:
	check(TidalSurge.warning(Stage2.new().street_half(Stage2.SURGE_D)) >= 2.0, "the white line crosses the bay for at least 2 s before the street's edge")
	var event: Dictionary = Stage2.new().events(false).filter(func(e: Dictionary) -> bool: return e.type == "surge")[0]
	check_eq(event.d_center, Stage2.SURGE_D, "the event washes over the stretch with the rubble islands")
	check(event.d < Stage2.SURGE_D - 40.0, "it is released before the tank reaches the stretch")


func test_the_surge_shoves_and_slows_a_tank_on_the_low_road() -> void:
	var surge := _surged(0.0)
	var world := World.current
	check(surge.hitting, "low road is struck")
	check_eq(world.player.flow, TidalSurge.PUSH, "the hull is swept sideways")
	check_eq(world.rail.undertow, TidalSurge.UNDERTOW, "and the rail is held back")
	var before := Course.to_course(world.player.global_position).y
	for _i in 30:
		world.player.tick(STEP)
	check(Course.to_course(world.player.global_position).y > before + 1.0, "the tank is carried toward the far kerb")


func test_the_surge_passes_over_rubble_and_the_kerb() -> void:
	var island: Dictionary = Stage2.RELIEF.filter(func(f: Dictionary) -> bool: return f.h > 1.0 and f.d > 3200.0)[1]
	var surge := _surged(float(island.u), float(island.d))
	check(not surge.hitting, "the tank on a rubble island stays dry (floor %.2f)" % Course.height(float(island.d), float(island.u)))
	check_eq(World.current.player.flow, 0.0, "nothing sweeps it")
	var stage := Stage2.new()
	var quay := _surged(stage.street_half(Stage2.SURGE_D) - 1.0)
	check(not quay.hitting, "the tank up on the quay shelf stays dry (floor %.2f)" % stage.height(Stage2.SURGE_D, stage.street_half(Stage2.SURGE_D) - 1.0))


func test_the_surge_passes_under_a_leaping_or_drifting_tank() -> void:
	var world := _city()
	world.rail.d = Stage2.SURGE_D
	world.player.course_u = 0.0
	world.player.tick(STEP)
	world.player.airborne = true
	var surge := TidalSurge.new()
	surge.d = Stage2.SURGE_D
	world.add_child(surge)
	surge.front = 2.0
	surge._process(0.0)
	check(not surge.hitting, "a leaping tank clears it")
	world.player.airborne = false
	world.player.dash(Vector2(1, 0))
	check(world.player.invuln > 0.0, "a drift is invulnerable")
	surge._process(0.0)
	check(not surge.hitting, "a drifting tank is not swept")


## Share of the section's road (every 10 m, no arenas) that has a tower at least 18 m tall standing on `side`.
func _tower_wall(stage: Stage2, section: int, side: float) -> float:
	var from: float = Stage2.SECTION_STARTS[section]
	var to: float = Stage2.SECTION_STARTS[section + 1] if section + 1 < Stage2.SECTION_STARTS.size() else Stage2.LENGTH
	var walled := 0
	var total := 0
	for d in range(int(from), int(to), 10):
		if stage.in_arena(float(d), 60.0):
			continue
		total += 1
		for box: Dictionary in stage.structures:
			if box.kind == "city_building" and signf(box.u) == side and box.size.y >= 18.0 and absf(box.d - d) <= box.size.z * 0.5 and absf(box.u) - box.size.x * 0.5 < stage.street_half(d) + 10.0:
				walled += 1
				break
	return float(walled) / maxf(float(total), 1.0)


func test_at_most_one_section_is_walled_by_towers_on_both_sides() -> void:
	var stage := Stage2.new()
	var walled := []
	for section in Stage2.SECTION_STARTS.size():
		if _tower_wall(stage, section, -1.0) >= 0.7 and _tower_wall(stage, section, 1.0) >= 0.7:
			walled.append(section)
	check_eq(walled, [Stage2.Section.BOULEVARD], "only the boulevard is a corridor of towers")


func test_the_road_bends_tightly_and_never_folds_the_valley_over_itself() -> void:
	Course.use(2)
	var stage := Course.stage as Stage2
	var tightest := INF
	var sharpest := 0.0
	for d in range(2100, 2700, 5):
		var turn := absf(angle_difference(Course.yaw_at(float(d)), Course.yaw_at(float(d) + 5.0)))
		tightest = minf(tightest, 5.0 / maxf(turn, 0.0001))
		sharpest = maxf(sharpest, absf(angle_difference(Course.yaw_at(float(d)), Course.yaw_at(float(d) + 130.0))))
	check(rad_to_deg(sharpest) >= 70.0, "a bend turns the road by at least 70 deg inside 130 m (%.0f deg)" % rad_to_deg(sharpest))
	check(tightest <= 90.0, "its radius is tight, at most 90 m (%.0f m)" % tightest)
	check(tightest >= stage.valley_half_width(2300.0), "yet no tighter than the valley is wide, or its walls would fold over (%.0f m)" % tightest)


func test_the_road_climbs_to_a_deck_and_dives_under_a_roofed_concourse() -> void:
	Course.use(2)
	var stage := Course.stage as Stage2
	check(stage.height(900.0, 0.0) >= stage.height(600.0, 0.0) + 5.0, "the road rises at least 5 m onto the deck")
	check(stage.height(Stage2.CONCOURSE.y + 30.0, 0.0) <= stage.height(2500.0, 0.0) - 1.0, "and sinks below the street into the concourse")
	var length := Stage2.CONCOURSE.z - Stage2.CONCOURSE.y
	check(length >= 150.0 and length <= 250.0, "the roofed concourse is 150-250 m long (%.0f m)" % length)
	var middle := (Stage2.CONCOURSE.y + Stage2.CONCOURSE.z) * 0.5
	var roofed := Course.structure_boxes.filter(func(box: Dictionary) -> bool: return box.kind == "city_building" and box.y >= Stage2.ROOF_Y - 0.5 and absf(box.d - middle) < 1.0 and box.size.x >= 2.0 * stage.street_half(middle) and box.size.z >= length)
	check_eq(roofed.size(), 1, "a slab of building roofs the whole concourse")
	check(stage.fog_distance(middle) < stage.fog_distance(Stage2.CONCOURSE.x - 60.0) * 0.6, "the concourse is dim and short of sight")
	check(stage.fog_tint(middle).get_luminance() < stage.fog_tint(Stage2.CONCOURSE.x - 60.0).get_luminance() * 0.7, "and darker")
