extends TestCase
## The jungle-swallowed ruins: terrain the tank can drive, the clearing, the fortress's way in through the trees and the encounter script.

const MAX_SLOPE := 0.32


## Whether `d` lies on the bridge ramp and its cliff or on a fallen fig's roots, which climb and drop steeply by design.
func _by_a_feature(d: float) -> bool:
	if d > Stage4.GORGE_LIP - Stage4.RAMP_LENGTH - 2.0 and d < Stage4.GORGE_FAR + Stage4.GORGE_WALL + 2.0:
		return true
	return Stage4.LOGS.any(func(log: Array) -> bool: return d > log[0] - 3.0 and d < log[0] + Stage4.LOG_LENGTH + 5.0)


## The wall between the bridge lane and the trench, which drops away as the trench deepens.
func _on_the_divider(d: float, u: float) -> bool:
	return d > Stage4.GORGE_LIP - Stage4.GORGE_DESCENT and d < Stage4.GORGE_FAR + Stage4.GORGE_EXIT and u > -2.0 and u < 8.0


func test_driveable_jungle_floor_gradient_stays_tank_safe() -> void:
	Course.use(4)
	var stage := Course.stage as Stage4
	var worst := 0.0
	var at := Vector2.ZERO
	for d in range(0, int(Stage4.LENGTH)):
		if _by_a_feature(d):
			continue
		for u in range(-50, 51, 2):
			var limit := minf(stage.lateral_limit(d), stage.lateral_limit(d + 1.0)) - 1.0
			if absf(u) > limit or _on_the_divider(d, u):
				continue
			var here := stage.height(d, u)
			var slope := Vector2(stage.height(d + 1.0, u) - here, stage.height(d, u + 1.0) - here).length()
			if slope > worst:
				worst = slope
				at = Vector2(d, u)
	check(worst <= MAX_SLOPE, "no 1 m step of the drivable street climbs more than %.2f (worst %.3f at %s)" % [MAX_SLOPE, worst, at])


func test_the_floor_is_there_wherever_the_hull_can_reach() -> void:
	Course.use(4)
	var stage := Course.stage as Stage4
	for d in range(0, int(Stage4.LENGTH), 3):
		var reach := stage.lateral_limit(d) + Stage4.HULL_MARGIN
		for u in [-reach, -reach * 0.5, 0.0, reach * 0.5, reach]:
			var h := stage.height(d, u)
			check(h > -10.0 and h < 10.0, "the floor at d=%d u=%.0f is a driveable height (%.2f)" % [d, u, h])


func test_the_clearing_is_level_so_the_fortress_fights_on_flat_ground() -> void:
	Course.use(4)
	for angle in 24:
		for ring: float in [0.0, 0.5, 0.99]:
			var p := Vector2.from_angle(TAU * angle / 24.0) * Stage4.CLEARING_RADIUS * ring
			check_near(Course.stage.height(Stage4.CLEARING_D + p.x, p.y), 0.1, 0.15, "the clearing floor is level")


func test_the_road_ends_beyond_the_clearing_and_the_arena_lies_on_it() -> void:
	var stage := Stage4.new()
	var length := 0.0
	for piece: Array in stage.plan:
		length += piece[0]
	check(Stage4.CLEARING_D + Stage4.CLEARING_RADIUS < length + stage.plan_start * -1.0, "the whole clearing lies on the road")
	check_eq(stage.arena_center_d, Stage4.CLEARING_D, "the arena is the clearing")
	check_eq(stage.section_at(Stage4.CLEARING_D), int(Stage4.Section.CLEARING), "and its last section")


func test_the_fortress_enters_from_the_jungle_ahead_left_outside_the_rim() -> void:
	Course.use(4)
	var stage := Course.stage as Stage4
	var entry := stage.entry_point(0.0)
	check_near(entry.distance_to(Vector2(Stage4.CLEARING_D, 0.0)), Stage4.CLEARING_RADIUS, 0.01, "the entry lies on the rim")
	check(entry.x > Stage4.CLEARING_D and entry.y < 0.0, "ahead of the clearing's centre and on the left")
	var boss_at := Course.to_course(stage.boss_position())
	check_near(boss_at.distance_to(Vector2(Stage4.CLEARING_D, 0.0)), Stage4.CLEARING_RADIUS + Stage4.ENTRY_OUT, 0.5, "the boss starts %.0f m outside the rim" % Stage4.ENTRY_OUT)


func test_events_are_ordered_and_every_kind_exists() -> void:
	for hard in [false, true]:
		var previous := -INF
		var events := Stage4.new().events(hard)
		for event in events:
			check(event.d >= previous and event.d < Stage4.LENGTH, "events advance within the course")
			previous = event.d
			if event.has("kind"):
				check(Director.ENEMY_SCRIPTS.has(event.kind), "%s is registered" % event.kind)
				if Director.ENEMY_SCRIPTS.has(event.kind):
					check(ResourceLoader.exists(Director.ENEMY_SCRIPTS[event.kind]), "%s script exists" % event.kind)


func test_the_script_ends_with_the_checkpoint_refit_and_the_fortress() -> void:
	var events := Stage4.new().events(false)
	var boss := events.filter(func(e: Dictionary) -> bool: return e.type == "boss")
	var checkpoint := events.filter(func(e: Dictionary) -> bool: return e.type == "checkpoint")
	check_eq(boss.size(), 1, "one boss")
	check_eq(boss[0].kind, "fortress", "the fortress")
	check(not boss[0].get("rail", false), "it fights in the clearing, not along the road")
	check_eq(checkpoint.size(), 1, "one checkpoint")
	check(checkpoint[0].d < boss[0].d and Stage4.new().checkpoints.boss == checkpoint[0].d, "the boss checkpoint comes before it")
	check(events.filter(func(e: Dictionary) -> bool: return e.type == "pickup" and e.d > checkpoint[0].d and e.d < boss[0].d).size() >= 3, "the clearing is stocked before the fight")


func test_every_hunter_wave_is_flame_crews_with_at_most_two_escorts_and_the_swarms_between_carry_no_napalm() -> void:
	var flame := ["crocodile", "burner", "napalm"]
	for event in Stage4.new().events(false):
		if event.type != "wave":
			continue
		if event.kind == "fpv" and event.get("count", 1) > 1:
			check(not event.get("props", {}).get("napalm", false), "the swarm at d=%d is plain drones" % event.d)
			continue
		var kinds: Array = ["napalm" if event.get("props", {}).get("napalm", false) else event.kind]
		var escorts := 0
		for member: Dictionary in event.get("squad", []):
			kinds.append("napalm" if member.get("props", {}).get("napalm", false) else member.kind)
			escorts += int(member.get("count", 1))
		check(kinds.any(func(kind: String) -> bool: return kind in flame), "the wave at d=%d has a flame crew (%s)" % [event.d, kinds])
		check(escorts <= 3, "the squad at d=%d has %d escorts" % [event.d, escorts])


func test_napalm_drones_carry_the_flag_from_the_script_to_the_enemy() -> void:
	var world := stage("", false, 4)
	var spawned := world.director.spawn_wave({"d": 40.0, "type": "wave", "kind": "fpv", "height": 5.0, "props": {"napalm": true}})
	check_eq(spawned.size(), 1, "one drone")
	check((spawned[0] as FpvDrone).napalm, "it is slung with napalm")
	var plain := world.director.spawn_wave({"d": 40.0, "type": "wave", "kind": "fpv", "height": 5.0})
	check(not (plain[0] as FpvDrone).napalm, "an ordinary drone is not")


func test_the_checkpoint_starts_in_the_clearing_before_the_fortress_event() -> void:
	var world := stage("boss", false, 4)
	check_near(world.rail.d, Stage4.CLEARING_D - 260.0, 1.0, "the run starts at the boss checkpoint")
	var pending := world.director.events.filter(func(e: Dictionary) -> bool: return e.d >= world.rail.d - 1.0)
	check(pending.any(func(e: Dictionary) -> bool: return e.get("kind", "") == "fortress"), "the fortress is still to come")


func test_fodder_packs_bring_the_enemy_count_near_stage_ones() -> void:
	var count := func(events: Array[Dictionary]) -> int:
		return events.filter(func(e: Dictionary) -> bool: return e.type == "wave").reduce(func(sum: int, e: Dictionary) -> int:
			return sum + int(e.get("count", 1)) + e.get("squad", []).reduce(func(inner: int, member: Dictionary) -> int: return inner + int(member.get("count", 1)), 0), 0)
	var here: int = count.call(Stage4.new().events(false))
	var farm: int = count.call(Stage1.new().events(false))
	check(here * 3 >= farm * 2, "stage 4 sends %d enemies against stage 1's %d" % [here, farm])


func test_stage_4_has_its_own_road_and_boss_music() -> void:
	Course.use(4)
	var stage := Course.stage as Stage4
	var tracks := [stage.music(Stage4.Section.GORGE), stage.music(Stage4.Section.AVENUE), stage.music(Stage4.Section.VERGE), stage.boss_music()]
	for path: String in tracks:
		check(path.begins_with("res://assets/music/stage4_") and ResourceLoader.exists(path), "stage 4 plays its own existing track: %s" % path)
	check(stage.music(Stage4.Section.GORGE) != stage.boss_music(), "the boss track differs from the road track")


func test_no_roadside_fig_crown_hangs_over_the_road_where_the_chase_camera_rides() -> void:
	var world := stage("", false, 4)
	var stage := Course.stage as Stage4
	var crown := 3.2 + 3.8 # PropKit.jungle_tree: the lowest tier's offset plus its largest blob.
	var over := []
	for spec: Scenery.Spec in (world.director.scenery as Scenery).specs:
		if spec.kind == "jungle_tree" and not stage.in_arena(spec.d, 60.0) and absf(spec.u) - crown < stage.lateral_limit(spec.d):
			over.append(int(spec.d))
	check(over.is_empty(), "%d fig crowns reach inside the hull limit (first at d=%s)" % [over.size(), over.slice(0, 3)])
