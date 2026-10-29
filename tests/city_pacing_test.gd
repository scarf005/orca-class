extends TestCase
## Stages 2-4 pace their hunters in beats like stage 1: each stretch builds to a peak and releases, threats come
## from behind and the flanks as well as the haze ahead, and they show and fight close enough to read.

const FODDER := ["drone_boat", "uav", "sea_mine", "skimmer", "fpv"]
## The stretches the tank fights through on the rail, between the start and the arenas, per stage.
const STRETCHES := {
	2: [Vector2(0.0, 700.0), Vector2(700.0, 1650.0), Vector2(2150.0, 3200.0)],
	3: [Vector2(0.0, 650.0), Vector2(650.0, 1550.0), Vector2(2000.0, 3300.0)],
	4: [Vector2(0.0, 1100.0), Vector2(1100.0, 1900.0), Vector2(1900.0, 2500.0), Vector2(3300.0, 4100.0)],
}
const PEAK_WINDOW := 150.0
const RELEASE := 150.0


func _waves(number: int) -> Array[Dictionary]:
	var stage: StageDef = [Stage2, Stage3, Stage4][number - 2].new()
	return stage.events(false).filter(func(e: Dictionary) -> bool: return e.type == "wave")


## Hunters a wave sends: its own units if its kind hunts, plus every hunting escort.
func _hunters(event: Dictionary) -> int:
	var units := 0 if event.kind in FODDER else int(event.get("count", 1))
	for member: Dictionary in event.get("squad", []):
		units += 0 if member.kind in FODDER else int(member.get("count", 1))
	return units


func test_each_stretch_opens_light_builds_to_a_peak_of_hunters_then_releases() -> void:
	for number: int in STRETCHES:
		var waves := _waves(number)
		for stretch: Vector2 in STRETCHES[number]:
			var inside := waves.filter(func(e: Dictionary) -> bool: return e.d >= stretch.x and e.d < stretch.y)
			var best_groups := 0
			var best_units := 0
			for start: Dictionary in inside:
				var window := inside.filter(func(e: Dictionary) -> bool: return e.d >= start.d and e.d < start.d + PEAK_WINDOW and _hunters(e) > 0)
				var units: int = window.reduce(func(sum: int, e: Dictionary) -> int: return sum + _hunters(e), 0)
				if units > best_units:
					best_units = units
					best_groups = window.size()
			var opening: int = inside.filter(func(e: Dictionary) -> bool: return e.d < inside[0].d + PEAK_WINDOW).reduce(func(sum: int, e: Dictionary) -> int: return sum + _hunters(e), 0) if not inside.is_empty() else 0
			var label := "stage %d %d-%d m" % [number, stretch.x, stretch.y]
			check(best_groups >= 2 and best_units >= 3, "%s peaks with %d hunters in %d groups inside %d m" % [label, best_units, best_groups, PEAK_WINDOW])
			check(opening < best_units, "%s opens with %d hunters, lighter than its peak of %d" % [label, opening, best_units])
			var marks: Array = inside.map(func(e: Dictionary) -> float: return e.d)
			marks.append(stretch.y)
			var longest := 0.0
			for i in range(1, marks.size()):
				longest = maxf(longest, marks[i] - marks[i - 1])
			check(longest >= RELEASE, "%s lets the tank breathe: its longest quiet stretch is %d m" % [label, longest])


func test_every_stage_sends_threats_from_behind_and_the_flanks_as_well_as_ahead() -> void:
	for number in [2, 3, 4]:
		var entries: Array[Dictionary] = []
		for event in _waves(number):
			entries.append(event)
			entries.append_array(event.get("squad", []))
		var behind := entries.filter(func(e: Dictionary) -> bool: return e.get("formation", "") == "behind").size()
		var flank := entries.filter(func(e: Dictionary) -> bool: return e.get("formation", "") == "flank" or e.get("close", false)).size()
		check(behind >= 2, "stage %d comes up behind the tank %d times" % [number, behind])
		check(flank >= 2, "stage %d breaks in from the flanks or close cover %d times" % [number, flank])


func test_the_hind_hunts_the_viaduct_and_the_canyon() -> void:
	var hinds := _waves(2).filter(func(e: Dictionary) -> bool: return e.kind == "hind" or e.get("squad", []).any(func(m: Dictionary) -> bool: return m.kind == "hind"))
	check(hinds.any(func(e: Dictionary) -> bool: return e.d >= Stage2.SECTION_STARTS[Stage2.Section.VIADUCT] and e.d < Stage2.SECTION_STARTS[Stage2.Section.PLAZA]), "the first Hind meets the tank on the viaduct")
	check(hinds.any(func(e: Dictionary) -> bool: return e.d >= Stage2.SECTION_STARTS[Stage2.Section.CANYON] and e.d < Stage2.SECTION_STARTS[Stage2.Section.BAY]), "and another hunts it through the canyon")


func test_scripted_enemies_appear_within_reading_range_of_the_tank() -> void:
	for number in [2, 3, 4]:
		var world := stage("", false, number)
		world.process_mode = Node.PROCESS_MODE_DISABLED
		var distances: Array[float] = []
		for event in _waves(number):
			world.rail.d = event.d
			world.player._place(event.d)
			var tank_d := Course.to_course(world.player.global_position).x
			for enemy in world.director.spawn_wave(event):
				var ahead := Course.to_course(enemy.global_position).x - tank_d
				if ahead > 0.0:
					distances.append(ahead)
				enemy.despawn()
		distances.sort()
		var median := distances[distances.size() / 2] if not distances.is_empty() else INF
		check(median <= 95.0, "stage %d's enemies appear a median %.0f m ahead" % [number, median])


func test_street_hunters_close_to_fire_from_inside_80_m_of_a_driving_tank() -> void:
	for spec: Array in [[2, Kain], [2, Hind], [3, Hind]]:
		var world := stage("", false, spec[0])
		world.director.events.clear()
		world.rail.mode = Rail.Mode.HOLD
		var tank := world.player
		var d := Course.to_course(tank.global_position).x
		var hunter: Enemy = (spec[1] as GDScript).new()
		hunter.position = Course.ground_at(d + 95.0, 0.0) + (Vector3.UP * 5.0 if hunter is Hind else Vector3.ZERO)
		world.add_enemy(hunter)
		hunter.set("_attack_timer", 0.0)
		var farthest := 0.0
		var last := world.projectiles.size()
		for i in 400:
			d += 23.0 * 0.025
			tank.global_position = Course.to_world(d, 0.0, tank.global_position.y)
			hunter.behave(0.025)
			if world.projectiles.size() > last:
				farthest = maxf(farthest, Course.to_course(hunter.global_position).x - d)
			last = world.projectiles.size()
		var label := "stage %d %s" % [spec[0], (spec[1] as GDScript).get_global_name()]
		check(farthest > 0.0, "%s fires while the tank drives" % label)
		check(farthest <= 80.0, "%s fires from at most 80 m ahead (farthest %.0f m)" % [label, farthest])
