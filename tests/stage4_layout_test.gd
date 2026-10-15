extends TestCase
## The river valley's shape and gimmicks: switchbacks, the ford, the broken bridge's leap and trench, fallen figs and the spreading brush fire.


func _quiet(d: float, u: float) -> World:
	var world := stage("", false, 4)
	world.director.events.clear()
	world.rail.d = d
	world.player.course_u = u
	return world


func _heading_change(from: float, span: float) -> float:
	return rad_to_deg(absf(angle_difference(Course.yaw_at(from), Course.yaw_at(from + span))))


func test_the_road_bends_at_least_70_degrees_within_250_m_and_no_more_than_100() -> void:
	Course.use(4)
	var worst := 0.0
	for d in range(0, int(Stage4.CLEARING_D - Stage4.CLEARING_RADIUS), 10):
		worst = maxf(worst, _heading_change(d, 250.0))
	check(worst >= 70.0 and worst <= 100.0, "the sharpest 250 m of road turns %.0f degrees" % worst)


func test_the_road_climbs_and_dips_outside_the_arena() -> void:
	Course.use(4)
	var stage := Course.stage as Stage4
	check(stage.height(Stage4.FORD_D, 0.0) < -0.9, "the ford's bed lies a metre under the banks (%.2f)" % stage.height(Stage4.FORD_D, 0.0))
	check(stage.height(Stage4.GORGE_LIP + 10.0, 12.0) < -8.0, "the gorge floor lies 8 m down (%.2f)" % stage.height(Stage4.GORGE_LIP + 10.0, 12.0))
	check(stage.height(Stage4.GORGE_LIP - 1.0, Stage4.RAMP_U) > Stage4.RAMP_RISE * 0.9, "the bridge ramp climbs 8 m (%.2f)" % stage.height(Stage4.GORGE_LIP - 1.0, Stage4.RAMP_U))


func test_only_the_avenue_is_walled_by_towers_on_both_sides() -> void:
	var stage := Stage4.new()
	var walled := []
	for section in stage.section_starts.size():
		var from: float = stage.section_starts[section]
		var to: float = stage.section_starts[section + 1] if section + 1 < stage.section_starts.size() else Stage4.LENGTH
		var bins := 0
		var closed := 0
		for d in range(int(from), int(to), 40):
			bins += 1
			var sides := {}
			for block in stage.structures:
				if absf(block.d - d) <= 40.0 and block.size.y > 20.0 and absf(block.u) < 60.0:
					sides[signf(block.u)] = true
			closed += 1 if sides.size() == 2 else 0
		if closed > bins * 0.6:
			walled.append(section)
	check_eq(walled, [int(Stage4.Section.AVENUE)], "the walled sections")


func test_the_ford_is_wading_depth_and_slows_the_rail_to_wading_speed() -> void:
	var world := _quiet(Stage4.FORD_D - 120.0, 0.0)
	var stage := Course.stage as Stage4
	var depth := stage.water_surface(Vector2(Stage4.FORD_D, 0.0)) - stage.height(Stage4.FORD_D, 0.0)
	check(depth > 0.4 and depth < 1.0, "the water over the bed is wading deep, %.2f m" % depth)
	await wait_until(func() -> bool: return world.rail.d > Stage4.FORD_D)
	check(world.rail.wading, "the tank wades in the ford")
	await frames(30)
	check(world.rail.speed < Rail.CRUISE * (Rail.WADE_SPEED + 0.1), "the rail slows to wading speed (%.1f m/s)" % world.rail.speed)
	cleanup()


## Runs up the bridge ramp from 150 m out and off its lip, drifting `drifts` times on the way; returns the landing as (d, ground height, u).
func _bridge_run(drifts: int) -> Vector3:
	var world := _quiet(Stage4.GORGE_LIP - 150.0, Stage4.RAMP_U)
	var left := drifts
	var flew := await wait_until(func() -> bool:
		if left > 0 and Course.stage.ramp_at(world.rail.d, world.player.course_u) > 0.1 and world.player.lateral_velocity == 0.0:
			left -= 1
			world.player.dash(Vector2(1.0 if left % 2 == 0 else -1.0, 0.0))
		return world.player.airborne)
	check(flew, "the tank leaves the lip")
	await wait_until(func() -> bool: return not world.player.airborne)
	var at := Course.to_course(world.player.global_position)
	var ground := Course.stage.height(at.x, at.y)
	cleanup()
	return Vector3(at.x, ground, at.y)


func test_a_drifted_run_up_the_bridge_ramp_clears_the_gorge_to_dry_ground() -> void:
	var landing := await _bridge_run(2)
	check(landing.x > Stage4.GORGE_LIP + 30.0, "it lands far past the cliff (d=%.1f)" % landing.x)
	check(landing.y > Stage4.GORGE_WATER + 2.0, "on ground well above the river (%.1f m)" % landing.y)


func test_an_undrifted_run_up_the_bridge_ramp_drops_short_into_the_river() -> void:
	var landing := await _bridge_run(0)
	check(landing.y < Stage4.GORGE_WATER + 1.5, "it comes down in the river bed (%.1f m)" % landing.y)


func test_the_gorge_cliff_off_the_ramp_drops_the_tank_into_the_river() -> void:
	var world := _quiet(Stage4.GORGE_LIP - 150.0, -22.0)
	await wait_until(func() -> bool: return world.rail.d > Stage4.GORGE_LIP + 12.0)
	check(world.player.global_position.y < -7.0, "the tank is down in the gorge (%.1f)" % world.player.global_position.y)
	check(world.rail.wading, "wading the river")
	cleanup()


func test_the_right_lane_trench_reaches_the_riverbed_without_a_leap() -> void:
	var world := _quiet(Stage4.GORGE_LIP - 150.0, 12.0)
	var flew := false
	await wait_until(func() -> bool:
		flew = flew or world.player.airborne
		return world.rail.d > Stage4.GORGE_LIP + 12.0)
	check(not flew, "the trench is driven, not leaped")
	check(world.player.global_position.y < -7.0 and world.rail.wading, "the tank wades the riverbed at %.1f m" % world.player.global_position.y)
	cleanup()


func test_a_fallen_fig_hops_a_tank_that_drives_up_its_roots() -> void:
	var log: Array = Stage4.LOGS[0]
	var world := _quiet(float(log[0]) - 60.0, float(log[1]))
	var flew := await wait_until(func() -> bool: return world.player.airborne)
	check(flew, "the fig's roots throw the hull up")
	cleanup()


func test_a_fallen_fig_is_a_hop_not_a_wall_one_lane_over() -> void:
	var log: Array = Stage4.LOGS[0]
	var world := _quiet(float(log[0]) - 60.0, float(log[1]) + 12.0)
	var flew := false
	await wait_until(func() -> bool:
		flew = flew or world.player.airborne
		return world.rail.d > float(log[0]) + 30.0)
	check(not flew, "beside the roots the road is flat")
	cleanup()


## Two palms, a fern in reach of the second and one far off, in a quiet world far from any scripted fire.
func _brush(world: World) -> Array[Prop]:
	var props: Array[Prop] = []
	for at: Vector2 in [Vector2(1500.0, 4.0), Vector2(1505.0, 4.0), Vector2(1511.0, 4.0), Vector2(1560.0, 4.0)]:
		var prop := Prop.new().setup("palm", PropKit.mesh("palm"), 0.7, 8.0, 25.0)
		prop.burnable = true
		prop.position = Course.ground_at(at.x, at.y)
		world.props.add_child(prop)
		props.append(prop)
	return props


func _burn(prop: Prop, weapon: String) -> void:
	var hit := Hit.make(Hit.Kind.FIRE, 500.0, prop.global_position)
	hit.weapon = weapon
	prop.take_hit(hit)


func _fires_near(prop: Prop) -> int:
	return FireZone._zones.filter(func(zone: FireZone) -> bool: return is_instance_valid(zone) and zone.hostile and zone.global_position.distance_to(prop.global_position) < 2.0).size()


func test_enemy_flame_marks_the_next_brush_then_lights_it_after_the_warning() -> void:
	var world := _quiet(1300.0, 0.0)
	var brush := _brush(world)
	await frames(2)
	_burn(brush[0], "flame")
	check(brush[1].has_meta("burn_generation"), "the neighbour is marked")
	check_eq(_fires_near(brush[1]), 0, "but not yet alight: the ring warns first")
	await wait_until(func() -> bool: return _fires_near(brush[1]) > 0, int(60.0 * (Wildfire.DELAY + 1.0)))
	check(_fires_near(brush[1]) > 0, "it catches after the warning")
	check_eq(_fires_near(brush[3]), 0, "brush out of reach stays green")
	cleanup()


func test_the_players_own_fire_does_not_spread() -> void:
	var world := _quiet(1300.0, 0.0)
	var brush := _brush(world)
	await frames(2)
	_burn(brush[0], "")
	await frames(int(60.0 * (Wildfire.DELAY + 0.5)))
	check(not brush[1].has_meta("burn_generation") and _fires_near(brush[1]) == 0, "the neighbour is untouched")
	cleanup()


func test_a_burning_chain_dies_out_after_its_generation_cap() -> void:
	var world := _quiet(1300.0, 0.0)
	var brush := _brush(world)
	await frames(2)
	brush[0].set_meta("burn_generation", Wildfire.MAX_GENERATION)
	_burn(brush[0], "flame")
	check(not brush[1].has_meta("burn_generation"), "the chain ends at its cap")
	cleanup()
