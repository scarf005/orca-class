extends TestCase
## The stage's spaces and map gimmicks: the open dune sea whose crests throw the tank, the avenue and its bend, the
## borer's sand bulging on the pit's approach, the roofed tunnel and the quicksand around it.

const STEP := 1.0 / 60.0


func _stage3() -> World:
	var world := stage("", false, 3)
	world.director._next_event = world.director.events.size()
	return world


## Whether (d, u) is on a launch ramp or the sand falling away around it, which climb and drop steeply by design.
func _by_a_ramp(stage: Stage3, d: float, u: float) -> bool:
	for index in Stage3.HILL_COUNT:
		var s := d - stage.hill_d(index)
		if s > -31.0 and s < Stage3.HILL_LENGTH + 25.0 and absf(u - stage.hill_side(index) * Stage3.HILL_U) < Stage3.HILL_HALF + Stage3.HILL_FLANK + 1.0:
			return true
	return false


## The share of rail distance in [from, to] where towers stand along both kerbs.
func _walled_share(from: float, to: float) -> float:
	var stage := Course.stage
	var walled := 0
	var count := 0
	for d in range(int(from), int(to), 5):
		var sides := {}
		for structure in stage.structures:
			if structure.kind != "city_building" or absf(structure.d - d) > structure.size.z * 0.5:
				continue
			if absf(structure.u) - structure.size.x * 0.5 < stage.lateral_limit(d) + 20.0:
				sides[signf(structure.u)] = true
		walled += int(sides.size() == 2)
		count += 1
	return float(walled) / count


func test_only_the_avenue_is_a_corridor_of_towers() -> void:
	Course.use(3)
	var starts := Stage3.SECTION_STARTS
	var avenue := _walled_share(starts[Stage3.Section.AVENUE] + 20.0, starts[Stage3.Section.PIT] - 20.0)
	check(avenue > 0.6, "the avenue is walled with towers on both kerbs (%.0f%% of its length)" % (avenue * 100.0))
	for section in [Stage3.Section.OUTSKIRTS, Stage3.Section.PIT, Stage3.Section.CANYON, Stage3.Section.RUN]:
		var share := _walled_share(starts[section], starts[section + 1] if section < Stage3.Section.RUN else Stage3.LENGTH)
		check(share < 0.1, "section %d has no wall of towers (%.0f%% walled)" % [section, share * 100.0])


func test_the_road_bends_70_to_90_degrees_tightly_twice() -> void:
	Course.use(3)
	for window: Vector2 in [Vector2(1360.0, 1700.0), Vector2(2860.0, 3100.0)]:
		var turn := rad_to_deg(Course.forward(window.x).angle_to(Course.forward(window.y)))
		check(turn > 70.0 and turn < 90.0, "the bend over %s turns %.0f degrees" % [window, turn])
		var tightest := INF
		for d in range(int(window.x), int(window.y), 10):
			tightest = minf(tightest, 10.0 / maxf(Course.forward(float(d)).angle_to(Course.forward(d + 10.0)), 0.00001))
		check(tightest < Terrain.HALF_WIDTH, "its radius is %.0f m, tighter than the terrain strip is wide" % tightest)
	check(Course.forward(3300.0).distance_to(Course.forward(0.0)) < 0.01, "the road runs straight again into the run")


func test_the_street_changes_level_into_the_pit_and_the_tunnel() -> void:
	Course.use(3)
	var stage := Course.stage as Stage3
	check(stage.height(1620.0, 0.0) - stage.height(1712.0, 0.0) > 3.5, "the approach descends into the pit")
	check(stage.height(2150.0, 0.0) - stage.height(2400.0, 0.0) > Stage3.TUNNEL_DEPTH - 1.0, "the tunnel lies %.0f m under the street" % Stage3.TUNNEL_DEPTH)
	check(stage.height(2700.0, 0.0) - stage.height(2400.0, 0.0) > Stage3.TUNNEL_DEPTH - 1.0, "and the street climbs back out")


func test_the_hull_never_sinks_or_rolls_off_the_floor_anywhere_it_can_drive() -> void:
	var world := _stage3()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var tank := world.player
	var stage := Course.stage as Stage3
	var d := 10.0
	while d < Stage3.LENGTH - 20.0:
		var at := d + tank.course_offset
		var limit := Tank.lateral_limit(at)
		for step in 13:
			tank.course_u = -limit + limit * 2.0 * step / 12.0
			if _by_a_ramp(stage, at, tank.course_u):
				continue
			tank._place(d)
			var sunk := Course.height(at, tank.course_u) - tank.global_position.y
			var roll := absf(tank.global_basis.get_euler().z)
			check(sunk < 0.8, "the hull at d=%d u=%.1f sits %.2f m under the floor" % [d, tank.course_u, sunk])
			check(roll < 0.3, "the hull at d=%d u=%.1f rolls %.2f rad off a floor that is not there" % [d, tank.course_u, roll])
		d += 5.0


func test_the_hull_stays_on_the_floor_across_a_bursts_crater() -> void:
	var world := _stage3()
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var stage := Course.stage as Stage3
	stage.mounds.append({"d": 1650.0, "u": 0.0, "swell": 0.0, "crater": 1.0})
	var tank := world.player
	for along in range(-14, 15):
		tank.course_u = 0.0
		tank.course_offset = 0.0
		tank._place(1650.0 + along)
		var sunk := Course.height(1650.0 + along, 0.0) - tank.global_position.y
		check(sunk < 0.8, "the hull %d m from the crater's centre sits %.2f m under the floor" % [along, sunk])
	stage.mounds.clear()


# The dune sea ---------------------------------------------------------------------------------------------------

func test_crests_throw_a_cruising_hull_only_on_the_dune_sea_and_the_pits_approach() -> void:
	Course.use(3)
	var stage := Course.stage as Stage3
	for d in [100.0, 300.0, 600.0, 1600.0, 1700.0]:
		check(stage.hops_at(d), "a crest at d=%d throws the tank" % d)
	for d in [800.0, 1200.0, 1900.0, 2100.0, 2500.0, 3000.0, 3500.0, 5000.0, 7000.0]:
		check(not stage.hops_at(d), "a crest at d=%d leaves the tank on the ground" % d)


## Drives the tank down lane `u` from `from` to `to` and returns how high above the ground it flew at most, or 0.
func _fly(world: World, from: float, to: float, u: float, sprint := 0.0) -> float:
	var tank := world.player
	tank.course_u = u
	tank.course_offset = 0.0
	world.rail.d = from
	world.rail.speed = Rail.CRUISE if sprint == 0.0 else sprint
	world.rail.sprint = sprint
	tank._ramp = -1.0
	var peak := 0.0
	while world.rail.d < to:
		tank.tick(STEP)
		peak = maxf(peak, tank.global_position.y - Course.height_at(tank.global_position) if tank.airborne else 0.0)
	return peak


## The sharpest crest on lane `u` of the dune sea: where the ground is highest and bends most.
func _sharpest_crest(u: float) -> float:
	var best := 0.0
	var at := 0.0
	for d in range(100, 600):
		var bend := Course.height(d + 1.0, u) + Course.height(d - 1.0, u) - 2.0 * Course.height(float(d), u)
		if bend < best:
			best = bend
			at = float(d)
	return at


func test_a_crest_throws_a_cruising_hull_into_the_air_but_not_a_slow_one() -> void:
	var world := _stage3()
	var crest := _sharpest_crest(0.0)
	var fast := _fly(world, crest - 10.0, crest + 25.0, 0.0)
	check(fast > 0.25 and fast < 2.5, "a hull at cruise clears the crest at d=%.0f by %.2f m" % [crest, fast])
	var slow := _fly(world, crest - 10.0, crest + 25.0, 0.0, Rail.BRAKE)
	check_near(slow, 0.0, 0.001, "a braking hull stays on the sand")
	world.player.airborne = false
	var avenue := _fly(world, 1000.0, 1100.0, 0.0)
	check_near(avenue, 0.0, 0.001, "the avenue's dunes throw nothing at cruise")


func test_a_hop_lands_softer_than_a_ramps_leap() -> void:
	var world := _stage3()
	var crest := _sharpest_crest(0.0)
	var camera := world.camera
	camera._kick = 0.0
	_fly(world, crest - 10.0, crest + 25.0, 0.0)
	var hop := camera._kick
	camera._kick = 0.0
	world.player._air_vy = -14.0
	world.player._land()
	check(camera._kick > hop, "a leap's landing kicks the camera harder (%.3f) than a hop's (%.3f)" % [camera._kick, hop])


# The borer's bulges ----------------------------------------------------------------------------------------------

func _bulge(world: World, site: Vector2) -> SandBulge:
	var bulge := SandBulge.new()
	bulge.site = site
	world.add_child(bulge)
	return bulge


## Runs the bulge's own frames for `seconds`.
func _age(bulge: SandBulge, seconds: float) -> void:
	for _i in roundi(seconds / STEP):
		bulge._process(STEP)


func test_a_bulge_swells_in_view_for_at_least_1_5_s_before_it_bursts() -> void:
	var world := _stage3()
	var stage := Course.stage as Stage3
	var site := Vector2(1650.0, 2.0)
	var marked := world.fx.get_child_count()
	var bulge := _bulge(world, site)
	check(world.fx.get_child_count() > marked, "the lane is marked on the ground at once")
	check(bulge.warn_time() >= 1.5, "the warning lasts %.1f s" % bulge.warn_time())
	var flat := Course.height(site.x, site.y)
	var last := flat
	for step in 14:
		_age(bulge, 0.1)
		check(not bulge.burst, "the sand has not burst at %.1f s" % (0.1 * (step + 1)))
		var now := Course.height(site.x, site.y)
		check(now >= last - 0.001, "the swell only grows (%.2f m after %.1f s)" % [now - flat, 0.1 * (step + 1)])
		last = now
	check(last - flat > 0.8, "the sand stands %.1f m over the lane before it bursts" % (last - flat))
	_age(bulge, 0.7)
	check(bulge.burst, "it bursts after its warning")
	check_near(Course.terrain_at(site.x, site.y).y, flat, 0.001, "the streamed terrain never carries the moving sand")
	check_near(stage.height(site.x, site.y), flat, 0.001, "nor does the stage's own height")


func test_a_swelling_bulge_stands_a_column_up_that_shows_from_afar_until_it_bursts() -> void:
	var world := _stage3()
	var bulge := _bulge(world, Vector2(1650.0, 2.0))
	_age(bulge, 0.5)
	var early := bulge._mesh.get_aabb().size.y
	check(early > 4.0, "half a second in, the column stands %.1f m over the lane" % early)
	_age(bulge, 1.0)
	var later := bulge._mesh.get_aabb().size.y
	check(later > early + 3.0 and later > 10.0, "it climbs to %.1f m before the burst" % later)
	_age(bulge, 1.2)
	check(bulge._mesh.get_aabb().size.y < 6.0, "the column is gone once the sand has burst")


func test_standing_on_the_burst_hurts_and_a_lane_aside_does_not() -> void:
	var world := _stage3()
	var tank := world.player
	var site := Vector2(1650.0, 0.0)
	world.rail.d = site.x - tank.course_offset
	tank.course_u = 0.0
	tank.tick(STEP)
	var before := tank.hp
	_age(_bulge(world, site), 2.1)
	check(tank.hp < before - 5.0, "the tank on the burst lost %.0f armor" % (before - tank.hp))
	var other := _stage3()
	var aside := other.player
	other.rail.d = site.x - aside.course_offset
	aside.course_u = Stage3.BULGE_RADIUS + Tank.HULL_RADIUS + 1.0
	aside.tick(STEP)
	var safe := aside.hp
	_age(_bulge(other, site), 2.1)
	check_near(aside.hp, safe, 0.001, "a tank in the next lane is untouched")


func test_a_tank_leaping_over_the_burst_is_not_hurt() -> void:
	var world := _stage3()
	var tank := world.player
	var site := Vector2(1650.0, 0.0)
	world.rail.d = site.x - tank.course_offset
	tank.course_u = 0.0
	tank.tick(STEP)
	tank.airborne = true
	var before := tank.hp
	_age(_bulge(world, site), 2.1)
	check_near(tank.hp, before, 0.001, "the tank that leaps over it is untouched")
	tank.airborne = false


func test_the_burst_leaves_a_hole_ringed_with_sand_a_fast_tank_hops_off() -> void:
	var world := _stage3()
	var site := Vector2(1650.0, 0.0)
	var flat := Course.height(site.x, site.y)
	var bulge := _bulge(world, site)
	_age(bulge, 2.5)
	check(Course.height(site.x, site.y) - flat < -1.2, "a hole is left at the centre (%.2f m)" % (Course.height(site.x, site.y) - flat))
	var rim := Course.height(site.x - Stage3.CRATER_RADIUS, site.y) - Course.terrain_at(site.x - Stage3.CRATER_RADIUS, site.y).y
	check(rim > Stage3.CRATER_RIM * 0.8, "the sand thrown up ringing it stands %.2f m" % rim)
	var peak := _fly(world, site.x - 22.0, site.x + 25.0, 0.0)
	check(peak > 0.25, "a cruising tank leaves the ground over the crater (%.2f m)" % peak)
	var slow := _fly(world, site.x - 22.0, site.x + 25.0, 0.0, Rail.BRAKE)
	check_near(slow, 0.0, 0.001, "a braking one rolls through it")


func test_a_bulge_gives_its_sand_back_when_it_is_gone() -> void:
	var world := _stage3()
	var stage := Course.stage as Stage3
	var site := Vector2(1650.0, 0.0)
	var flat := Course.height(site.x, site.y)
	var bulge := _bulge(world, site)
	_age(bulge, 2.5)
	check_eq(stage.mounds.size(), 1, "the live bulge adds its sand")
	bulge.free()
	check_eq(stage.mounds.size(), 0, "a freed bulge leaves none")
	check_near(Course.height(site.x, site.y), flat, 0.001, "the ground is as it was")


func test_the_borers_sand_is_foreshadowed_on_the_pits_approach() -> void:
	var bulges := Stage3.new().events(false).filter(func(e: Dictionary) -> bool: return e.type == "bulge")
	check(bulges.size() >= 3, "the approach holds %d bulges" % bulges.size())
	var arrival := Stage3.BULGE_AHEAD / Rail.CRUISE
	check(arrival > 1.5, "a cruising tank is marked %.1f s before it reaches the sand" % arrival)
	var lanes := {}
	for bulge: Dictionary in bulges:
		var site := StageEvents.spot(bulge)
		check(site.x > Stage3.SECTION_STARTS[Stage3.Section.PIT] and site.x < Stage3.PIT_D - Stage3.PIT_RADIUS, "the sand at d=%.0f lies on the approach" % site.x)
		check(absf(site.y) + Stage3.BULGE_RADIUS < Tank.lateral_limit(site.x) + Stage3.BULGE_RADIUS, "its lane at u=%.0f is one the tank can drive" % site.y)
		lanes[site.y] = true
	check_eq(lanes.size(), bulges.size(), "no two bulges share a lane")
	var world := _stage3()
	world.director._fire(bulges[0])
	check(world.get_children().any(func(n: Node) -> bool: return n is SandBulge), "the director raises the bulge")


# The tunnel -----------------------------------------------------------------------------------------------------

func test_the_tunnel_is_a_dark_roofed_200_to_300_m_with_tiled_walls() -> void:
	Course.use(3)
	var roofs := Course.structure_boxes.filter(func(box: Dictionary) -> bool: return box.kind == "tunnel_roof")
	var walls := Course.structure_boxes.filter(func(box: Dictionary) -> bool: return box.kind == "tunnel_wall")
	var from := INF
	var to := -INF
	for roof in roofs:
		from = minf(from, roof.d - roof.size.z * 0.5)
		to = maxf(to, roof.d + roof.size.z * 0.5)
	check(to - from >= 200.0 and to - from <= 300.0, "the roofed length is %.0f m" % (to - from))
	for d in range(int(from) + 1, int(to), 3):
		var covered := false
		for roof in roofs:
			covered = covered or absf(roof.d - d) <= roof.size.z * 0.5
		check(covered, "a roof lies over d=%d" % d)
		var sides := {}
		for wall in walls:
			if absf(wall.d - d) <= wall.size.z * 0.5:
				sides[signf(wall.u)] = true
				check(absf(wall.u) - wall.size.x * 0.5 > Course.stage.lateral_limit(d) + Tank.HULL_RADIUS, "the wall at d=%d stands clear of the hull" % d)
		check_eq(sides.size(), 2, "a wall on each side of d=%d" % d)
		var floor_y := Course.height(float(d), 0.0)
		for roof in roofs:
			if absf(roof.d - d) <= roof.size.z * 0.5:
				check(roof.y - floor_y >= Stage3.TUNNEL_CLEAR - 0.5, "the soffit at d=%d clears the floor by %.1f m" % [d, roof.y - floor_y])
	var stage := Course.stage as Stage3
	check(stage.sun_scale_at((from + to) * 0.5) < 0.2, "the roof shuts the sun out of the tunnel")
	check(stage.ambient_energy_at((from + to) * 0.5) < stage.ambient_energy, "its sky-light is dimmer inside")
	check_near(stage.sun_scale_at(1000.0), 1.0, 0.001, "the sun is whole outside")
	check_near(stage.ambient_energy_at(1000.0), stage.ambient_energy, 0.001, "and so is the sky-light")
	check(stage.fog_tint((from + to) * 0.5).v < stage.fog_tint(1000.0).v * 0.6, "its haze is dark")


func test_the_camera_rides_under_the_tunnel_roof() -> void:
	var world := _stage3()
	var stage := Course.stage as Stage3
	var d := (Stage3.TUNNEL_D + Stage3.TUNNEL_END) * 0.5
	var floor_point := Course.ground_at(d, 0.0)
	var eye := Course.to_world(d - ChaseCamera.RAIL_BACK, 0.0, floor_point.y + ChaseCamera.RAIL_HEIGHT)
	var pulled := world.director.scenery.camera_position(floor_point + Vector3.UP, eye)
	check(pulled.y < floor_point.y + Stage3.TUNNEL_CLEAR, "the eye at %.1f m is under the soffit at %.1f m" % [pulled.y - floor_point.y, Stage3.TUNNEL_CLEAR])
	check(stage.tunnel_share(d) > 0.99, "this is deep inside the tunnel")


func test_the_tunnel_roof_and_walls_never_fade_for_the_camera() -> void:
	check("tunnel_roof" in ChaseCamera.SOLID_OVERHEAD and "tunnel_wall" in ChaseCamera.SOLID_OVERHEAD, "the roof and the walls stay solid around the camera")


# Quicksand ---------------------------------------------------------------------------------------------------------

## The tank `along` m past the first funnel's centre and `across` m beside it, the rail pinned there.
func _sink_world(across: float, along := 0.0) -> World:
	var world := _stage3()
	var sink := Stage3.SINKS[0]
	world.player.course_u = sink.y + across
	world.player.course_offset = 4.0
	world.rail.d = sink.x + along - 4.0
	world.player.tick(STEP)
	return world


## Frames at the pinned spot (the rail held, the lateral position free), returning the offset from the funnel's centre.
func _sit(world: World, seconds: float) -> float:
	var sink := Stage3.SINKS[0]
	var pinned := world.rail.d
	for _i in roundi(seconds / STEP):
		world.player.tick(STEP)
		world.rail.d = pinned
		world.player.course_offset = 4.0
	return world.player.course_u - sink.y


func test_quicksand_drags_the_hull_toward_its_centre_and_holds_it_there() -> void:
	var world := _sink_world(8.0)
	check(_sit(world, 0.5) < 5.0, "the hull 8 m from the centre is dragged inward")
	check(absf(_sit(world, 1.0)) < 4.0, "and rests near the centre")
	var clear := _sink_world(Stage3.SINK_RADIUS + 12.0)
	var u := clear.player.course_u
	_sit(clear, 0.5)
	check_near(clear.player.course_u, u, 0.01, "beside the funnel nothing drags")


func test_quicksand_slows_the_rail_and_the_steering() -> void:
	var world := _sink_world(5.0)
	_sit(world, 0.6)
	check(world.rail.wading, "the rail wades in quicksand")
	check(world.rail.speed <= Rail.WADE_SPEED * Rail.CRUISE + 0.01, "the rail runs at %.1f m/s, capped to %.1f" % [world.rail.speed, Rail.WADE_SPEED * Rail.CRUISE])
	var clear := _sink_world(Stage3.SINK_RADIUS + 12.0)
	_sit(clear, 0.6)
	check(not clear.rail.wading, "the rail runs free beside it")
	check_near(clear.rail.speed, Rail.CRUISE, 0.01, "at cruise")


func test_steering_alone_cannot_leave_the_middle_of_a_funnel() -> void:
	var world := _sink_world(3.0)
	world.player.input_enabled = true
	Input.action_press("move_right")
	var offset := _sit(world, 1.0)
	Input.action_release("move_right")
	check(offset < 9.0, "full right steering for a second leaves the hull %.1f m from the centre" % offset)
	var clear := _sink_world(Stage3.SINK_RADIUS + 12.0)
	clear.player.input_enabled = true
	Input.action_press("move_left")
	var moved := _sit(clear, 1.0)
	Input.action_release("move_left")
	check(absf(moved - (Stage3.SINK_RADIUS + 12.0)) > 12.0, "the same steering beside it moves the hull %.1f m" % absf(moved - (Stage3.SINK_RADIUS + 12.0)))


func test_a_drift_breaks_the_hull_free_of_quicksand() -> void:
	var world := _sink_world(5.0)
	world.player.dash(Vector2(1.0, 0.0))
	var free := _sit(world, 0.9)
	check(free > Stage3.SINK_RADIUS, "after the drift the hull lies %.1f m out, beyond the funnel" % free)
	var held := _sink_world(5.0)
	check(absf(_sit(held, 0.9)) < 4.0, "the same hull without the drift is still in the middle")


func test_the_quicksand_lies_off_the_tunnel_and_the_ramps() -> void:
	Course.use(3)
	for sink in Stage3.SINKS:
		check(sink.x < Stage3.DIVE_D - 20.0 or sink.x > Stage3.RISE_END + 20.0, "the funnel at d=%.0f is not in the tunnel" % sink.x)
		check(absf(sink.y) + Stage3.SINK_RADIUS < Course.stage.lateral_limit(sink.x) + Stage3.SINK_RADIUS * 0.6, "the funnel at d=%.0f is on the road" % sink.x)
		check(Course.stage.quicksand_at(sink.x + 2.0, sink.y).z > 0.8, "it is deepest at the centre")
	check_eq(Course.stage.quicksand_at(5000.0, 0.0), Vector3.ZERO, "the run has none")
