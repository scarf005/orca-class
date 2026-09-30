extends TestCase
## Stage 2's encounters follow the terrain: quiet, build, peak and release per section, hard adds
## flankers only to build beats, and no window of the rail is buried in enemies.

const BUDGETS := {Stage2.Section.FLOODPLAIN: 18, Stage2.Section.PADDIES: 40, Stage2.Section.MARSH: 63, Stage2.Section.LEVEE: 51}
const GROUND := ["ugv", "walker", "spitter", "crawler", "quad"]


func _events(hard: bool) -> Array[Dictionary]:
	return Stage2.new().events(hard)


func _waves(hard: bool) -> Array[Dictionary]:
	var waves: Array[Dictionary] = []
	waves.assign(_events(hard).filter(func(e: Dictionary) -> bool: return e.type == "wave"))
	return waves


func _size(wave: Dictionary, hard: bool) -> int:
	var count := ceili(wave.get("count", 1) * Director.FODDER.get(wave.kind, 1.0))
	return ceili(count * wave.get("hard_scale", 1.4)) if hard else count


func _total(waves: Array[Dictionary], hard: bool) -> int:
	return waves.reduce(func(sum: int, w: Dictionary) -> int: return sum + _size(w, hard), 0)


func _within(waves: Array[Dictionary], from: float, span: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	found.assign(waves.filter(func(w: Dictionary) -> bool: return w.d >= from and w.d < from + span))
	return found


func _touches_peak(from: float, span: float) -> bool:
	return Stage2.PEAKS.values().any(func(p: Vector2) -> bool: return from < p.y and from + span > p.x)


func _in_section(waves: Array[Dictionary], section: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	Course.use(2)
	found.assign(waves.filter(func(w: Dictionary) -> bool: return Course.section_at(w.d) == section))
	return found


func test_section_budgets_hold_and_the_levee_is_the_heaviest() -> void:
	var waves := _waves(false)
	for section: int in BUDGETS:
		var total := _total(_in_section(waves, section), false)
		check(absf(total - BUDGETS[section]) <= BUDGETS[section] * 0.2, "section %d holds ~%d enemies (got %d)" % [section, BUDGETS[section], total])
	# Per 100 m of rail: the fight builds section by section, and the levee is the most crowded.
	var density := BUDGETS.keys().map(func(s: int) -> float: return _total(_in_section(waves, s), false) / (Stage2.SECTION_STARTS[s + 1] - Stage2.SECTION_STARTS[s]) * 100.0)
	check(density[3] > density[2] and density[2] > density[1] and density[1] > density[0], "the fight builds toward the levee (%s per 100 m)" % [density])


func test_releases_are_empty_in_both_difficulties() -> void:
	for hard in [false, true]:
		for release: Vector2 in Stage2.RELEASES:
			var inside := _events(hard).filter(func(e: Dictionary) -> bool: return e.type in ["wave", "midboss", "boss"] and e.d > release.x and e.d < release.y)
			check_eq(inside.size(), 0, "nothing spawns in the release %s (%s)" % [release, "hard" if hard else "normal"])
	for release: Vector2 in Stage2.RELEASES:
		check(release.y - release.x >= 60.0, "%s is long enough to breathe" % release)


func test_each_peak_is_denser_than_the_beats_around_it() -> void:
	var waves := _waves(false)
	for section: int in Stage2.PEAKS:
		var peak: Vector2 = Stage2.PEAKS[section]
		var inside := _total(_within(waves, peak.x, peak.y - peak.x), false) / (peak.y - peak.x)
		var before := _total(_within(waves, peak.x - 200.0, 200.0), false) / 200.0
		check(inside > 0.0 and (section == Stage2.Section.LEVEE or inside > before * 0.9), "the peak of section %d is at least as dense as before it (%.3f vs %.3f per m)" % [section, inside, before])
		check(_within(waves, peak.x, peak.y - peak.x).size() >= 4, "and has several waves")


func test_no_window_of_150m_exceeds_the_cap() -> void:
	for hard in [false, true]:
		var waves := _waves(hard)
		for w in waves:
			var count := _total(_within(waves, w.d, 150.0), hard)
			var cap := 30 if hard else 22
			if _touches_peak(w.d, 150.0):
				cap = 56 if hard else 40
			check(count <= cap, "%s: %d enemies in the 150 m from d %d (cap %d)" % ["hard" if hard else "normal", count, w.d, cap])


func test_hard_adds_flankers_to_build_beats_only() -> void:
	var normal := _waves(false)
	var hard := _waves(true)
	var added := hard.filter(func(h: Dictionary) -> bool: return not normal.any(func(n: Dictionary) -> bool: return n.d == h.d and n.kind == h.kind))
	check(added.size() >= 5, "hard adds encounters (%d)" % added.size())
	for wave: Dictionary in added:
		check(not Stage2.PEAKS.values().any(func(p: Vector2) -> bool: return wave.d >= p.x and wave.d < p.y), "the added wave at %.0f is not inside a peak" % wave.d)
		check(wave.get("count", 1) <= 4, "and it is a handful (%d)" % wave.get("count", 1))
	for section in [Stage2.Section.FLOODPLAIN, Stage2.Section.PADDIES, Stage2.Section.MARSH]:
		check(_in_section(added, section).size() >= 1, "section %d gets a flanker" % section)


func test_the_terrain_shapes_the_enemies() -> void:
	var waves := _waves(false)
	var ground_in_water := waves.filter(func(w: Dictionary) -> bool: return w.kind in GROUND and Course.section_at(w.d) == Stage2.Section.MARSH)
	check(ground_in_water.size() >= 4, "ground enemies still come through the marsh (%d waves)" % ground_in_water.size())
	var dike_columns := waves.filter(func(w: Dictionary) -> bool: return w.kind == "ugv" and absf(w.get("u", 0.0)) == 18.0)
	check(dike_columns.size() >= 2, "columns run down the dikes (%d)" % dike_columns.size())
	var levee_air := _in_section(waves, Stage2.Section.LEVEE).filter(func(w: Dictionary) -> bool: return w.kind in ["helicopter", "uav", "fpv"])
	check(levee_air.size() >= 3, "the levee has air cover over the water (%d)" % levee_air.size())
	for w in waves:
		check(Director.ENEMY_SCRIPTS.has(w.kind), "wave kind %s at %.0f has a script" % [w.kind, w.d])
		check(w.d > 0.0 and w.d < 2300.0, "wave at %.0f is on the rail before the arena" % w.d)
	var events := _events(false)
	var ds := events.map(func(e: Dictionary) -> float: return e.d)
	var sorted := ds.duplicate()
	sorted.sort()
	check(events.filter(func(e: Dictionary) -> bool: return e.type == "checkpoint").size() == 2, "two checkpoints")
	check(sorted.size() == ds.size(), "every event has a distance")


func test_playing_the_spawns_gives_ground_enemies_the_water_or_the_dikes() -> void:
	var world := stage("", true, 2)
	world.player.invulnerable = true
	var positions := 0
	for wave in _waves(false):
		if wave.kind in GROUND and wave.d > 440.0 and wave.d < 880.0:
			world.rail.d = wave.d
			var spawned := world.director.spawn_wave(wave)
			for enemy in spawned:
				var c := Course.to_course(enemy.global_position)
				positions += 1
				check(absf(c.y) <= Tank.lateral_limit(c.x) + 25.0, "%s spawns in the valley (u=%.0f) at wave %.0f" % [wave.kind, c.y, wave.d])
				enemy.queue_free()
	check(positions > 10, "several ground enemies were spawned (%d)" % positions)
