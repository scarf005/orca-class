extends TestCase
## The sand-buried city: terrain the tank can drive, the boss ramps, the encounter script and the 140 km/h run.

const MAX_SLOPE := 0.32


func test_driveable_sand_gradient_stays_tank_safe() -> void:
	Course.use(3)
	var stage := Course.stage as Stage3
	var worst := 0.0
	var at := Vector2.ZERO
	for d in range(0, int(Stage3.LENGTH)):
		for u in range(-50, 51, 2):
			var limit := minf(stage.lateral_limit(d), stage.lateral_limit(d + 1.0)) - 1.0
			if absf(u) > limit:
				continue
			var here := stage.height(d, u)
			var slope := Vector2(stage.height(d + 1.0, u) - here, stage.height(d, u + 1.0) - here).length()
			if slope > worst:
				worst = slope
				at = Vector2(d, u)
	check(worst <= MAX_SLOPE, "no 1 m step of the drivable street climbs more than %.2f (worst %.3f at %s)" % [MAX_SLOPE, worst, at])


func test_the_floor_is_there_wherever_the_hull_can_reach() -> void:
	Course.use(3)
	var stage := Course.stage as Stage3
	for d in range(0, int(Stage3.LENGTH), 3):
		var reach := stage.lateral_limit(d) + Stage3.HULL_MARGIN
		for u in [-reach, -reach * 0.5, 0.0, reach * 0.5, reach]:
			var h := stage.height(d, u)
			check(h > -1.5 and h < 10.0, "the floor at d=%d u=%.0f is a driveable height (%.2f)" % [d, u, h])


func test_the_pit_arena_is_level() -> void:
	Course.use(3)
	for angle in 24:
		for ring: float in [0.0, 0.5, 0.99]:
			var p := Vector2.from_angle(TAU * angle / 24.0) * Stage3.PIT_RADIUS * ring
			check_near(Course.stage.height(Stage3.PIT_D + p.x, p.y), 0.2, 0.15, "the pit floor is level")


func test_sand_ramps_alternate_sides_and_climb_to_a_lip() -> void:
	Course.use(3)
	var stage := Course.stage as Stage3
	for index in Stage3.HILL_COUNT:
		var side := stage.hill_side(index)
		check_eq(side, -1.0 if index % 2 == 0 else 1.0, "ramp %d is on its own side" % index)
		var foot := stage.hill_point(index, 0.0)
		var lip := stage.hill_point(index, 1.0)
		check(lip.y - foot.y > Stage3.HILL_HEIGHT * 0.8, "ramp %d climbs to a lip (%.1f m)" % [index, lip.y - foot.y])
		var past := Course.ground_at(stage.hill_d(index) + Stage3.HILL_LENGTH + 40.0, side * Stage3.HILL_U)
		check(past.y < lip.y - Stage3.HILL_HEIGHT * 0.7, "ramp %d drops away behind its lip" % index)
		check(absf(Course.to_course(lip).y - side * Stage3.HILL_U) < 0.5, "the lip lies on the track")
		check(Stage3.HILL_U - Stage3.HILL_HALF - 22.0 > stage.lateral_limit(stage.hill_d(index)) + Stage3.HULL_MARGIN, "the ramp and its flank stay outside the tank's reach")
	for index in Stage3.HILL_COUNT - 1:
		check(stage.hill_d(index + 1) - stage.hill_d(index) > Stage3.HILL_LENGTH + 100.0, "ramps %d and %d leave room to land between them" % [index, index + 1])


func test_events_are_ordered_and_every_kind_exists() -> void:
	for hard in [false, true]:
		var previous := -INF
		var events := Stage3.new().events(hard)
		for event in events:
			check(event.d >= previous and event.d < Stage3.LENGTH, "events advance within the course")
			previous = event.d
			if event.has("kind"):
				check(Director.ENEMY_SCRIPTS.has(event.kind), "%s is registered" % event.kind)
				if Director.ENEMY_SCRIPTS.has(event.kind):
					check(ResourceLoader.exists(Director.ENEMY_SCRIPTS[event.kind]), "%s script exists" % event.kind)


func test_a_squad_is_one_hunter_and_at_most_two_escorts() -> void:
	for event in Stage3.new().events(false):
		if event.type != "wave" or not event.has("squad"):
			continue
		var escorts := 0
		for member: Dictionary in event.squad:
			escorts += int(member.get("count", 1))
		check(escorts <= 2, "the squad at d=%d has %d escorts" % [event.d, escorts])


func test_the_run_is_floored_to_140_kmh_before_the_boss_appears() -> void:
	var events := Stage3.new().events(false)
	var sprint := events.filter(func(e: Dictionary) -> bool: return e.type == "sprint")
	var boss := events.filter(func(e: Dictionary) -> bool: return e.type == "boss")
	check_eq(sprint.size(), 1, "one sprint event")
	check_eq(boss.size(), 1, "one boss event")
	check_eq(float(sprint[0].kmh), 140.0, "the sprint is 140 km/h")
	check(sprint[0].d < boss[0].d, "the rail is already at speed when the boss shows")
	check(boss[0].get("rail", false), "the boss fights along the road, not in an arena")
	check(boss[0].d > Stage3.SECTION_STARTS[Stage3.Section.RUN], "the boss belongs to the dune run")


func test_the_rail_runs_at_the_sprint_speed_whatever_the_throttle() -> void:
	var rail := Rail.new()
	rail.sprint = 140.0 / 3.6
	for _i in 600:
		rail.advance(0.05, -1)
	check_near(rail.speed, 140.0 / 3.6, 0.01, "braking cannot slow the sprint")
	for _i in 100:
		rail.advance(0.05, 1)
	check_near(rail.speed, 140.0 / 3.6, 0.01, "overdrive cannot speed it up")
	check_eq(rail.throttle, 0, "the throttle stands at cruise")
	rail.sprint = 0.0
	for _i in 200:
		rail.advance(0.05, 0)
	check_near(rail.speed, Rail.CRUISE, 0.01, "cruise comes back when the sprint ends")


func test_the_sprint_event_sets_the_rail_speed() -> void:
	var world := stage("", false, 3)
	world.director._fire({"d": 0.0, "type": "sprint", "kmh": 140.0})
	check_near(world.rail.sprint, 140.0 / 3.6, 0.001, "the director floors the rail")
	check_eq(Course.stage.number, 3, "this is stage 3")


func test_the_fallen_tower_clears_the_drivable_street() -> void:
	var world := stage("", false, 3)
	world.director.scenery.stream(Stage3.FALLEN_D, 100000)
	var fallen: MeshInstance3D = null
	for child in world.director.scenery.get_children():
		if child is MeshInstance3D and is_equal_approx(child.rotation.z, Stage3.FALLEN_TILT):
			fallen = child
	check(fallen != null, "the fallen tower is placed")
	if fallen == null:
		return
	var half := Stage3.FALLEN_SIZE * 0.5
	var lowest := INF
	var limit := Course.stage.lateral_limit(Stage3.FALLEN_D) + Stage3.HULL_MARGIN
	for along in range(-12, 13, 3):
		for u in range(-int(limit), int(limit) + 1):
			var ground := Course.ground_at(Stage3.FALLEN_D + along, u)
			for lift in range(0, 40):
				var local := fallen.global_transform.affine_inverse() * (ground + Vector3.UP * lift)
				if absf(local.x) <= half.x and absf(local.z) <= half.z and local.y >= 0.0 and local.y <= Stage3.FALLEN_SIZE.y:
					lowest = minf(lowest, lift)
					break
	check(lowest < INF, "the tower spans the street")
	check(lowest >= 12.0, "its underside stays at least 12 m over every drivable spot (lowest %.0f m)" % lowest)
