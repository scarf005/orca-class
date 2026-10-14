class_name Stage3
extends StageDef
## A downtown the desert has swallowed: dunes bank against the towers up to their middle floors, the avenue shows
## through the sand in the troughs, a terraforming borer's pit opens in the middle, and the last third is a
## dune highway where the boss drifts up sand ramps and takes off at 140 km/h.

enum Section { OUTSKIRTS, AVENUE, PIT, CANYON, RUN }

const SECTION_STARTS := [0.0, 650.0, 1550.0, 2000.0, 3300.0]
const LENGTH := 6000.0
const HORIZON_SHIFT := 120.0 ## Squads spawn this much farther out, in the haze, and walk in.
const DRIFT := 9.0 ## How high the sand banks against the towers.
const HULL_MARGIN := 3.0 ## The floor extends this far past the hull limit so the track samples at the edge never hang.
const PIT_D := 1800.0
const PIT_RADIUS := 80.0
const SPRINT_KMH := 140.0
const PLAN := [[1100.0, 0.0], [500.0, 30.0], [500.0, -30.0], [500.0, 0.0], [600.0, -40.0], [600.0, 40.0], [2500.0, 0.0], [700.0, 0.0]]
## Sand ramps along the run: the boss drifts up one, leaves its lip and flies to the next. {d, side}.
const HILL_FIRST := 3560.0
const HILL_SPACING := 400.0
const HILL_COUNT := 6
const HILL_LENGTH := 200.0
const HILL_HEIGHT := 24.0
const HILL_U := 92.0 ## Lateral offset of a ramp's track.
const HILL_HALF := 12.0 ## Half width of its track.
const STORM_D := 2100.0

var _swell := make_noise(61, 0.008)
var _crest := make_noise(67, 0.013)
var _ripple := make_noise(71, 0.09)
var _grain := make_noise(73, 0.05)
var _far := make_noise(79, 0.006)


func _init() -> void:
	number = 3
	city = true
	standoff = 1.0
	plan = PLAN
	section_starts.assign(SECTION_STARTS)
	checkpoints = {"": 0.0, "midboss": PIT_D - 270.0, "boss": SECTION_STARTS[Section.RUN] + 20.0}
	coax_tiers = {"": 2, "midboss": 2, "boss": 2}
	midboss_d = PIT_D
	arena_center_d = PIT_D
	arena_radius = PIT_RADIUS
	arenas = [{"d": PIT_D, "radius": PIT_RADIUS}]
	sky_top = Palette.PEACH.lerp(Palette.CORAL, 0.55)
	sky_horizon = Palette.BUTTER
	sky_ground = Palette.PEACH
	# Hard desert light: a low sun rakes the dunes and the shade falls cool lilac, so facets keep their value range.
	ambient = Palette.LILAC.lerp(Palette.PEACH, 0.6)
	ambient_energy = 0.62
	fog_color = Palette.PEACH.lerp(Palette.BUTTER, 0.5)
	storm_color = Palette.OCHRE.lerp(Palette.PEACH, 0.35)
	storm_motes = [Palette.STRAW, Palette.OCHRE, Palette.BUTTER]
	fog_begin = 70.0
	fog_end = 360.0
	sun_color = Palette.BUTTER.lerp(Palette.CREAM, 0.5)
	sun_rotation = Vector3(-17.0, 120.0, 0.0)
	sun_energy = 1.15
	_generate_walls()
	_generate_backdrop()


func hill_d(index: int) -> float:
	return HILL_FIRST + HILL_SPACING * index


## Lateral side (-1 left, 1 right) of ramp `index`: they alternate, the first on the left.
func hill_side(index: int) -> float:
	return -1.0 if index % 2 == 0 else 1.0


func _street_half(d: float) -> float:
	var half := 34.0
	half = lerpf(half, 28.0, band(d, 600.0, 700.0, 1500.0, 1600.0))
	half = lerpf(half, 22.0, band(d, 1950.0, 2050.0, 3250.0, 3350.0))
	return lerpf(half, 48.0, smoothstep(3250.0, 3400.0, d))


func lateral_limit(d: float) -> float:
	for arena in arenas:
		if absf(d - arena.d) <= arena.radius:
			return arena.radius - 6.0
	return _street_half(d)


func valley_half_width(d: float) -> float:
	return lateral_limit(d) + 16.0


func _generate_walls() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261015
	var ranges := [[0.0, 650.0], [650.0, 1550.0], [1550.0, 2000.0], [2000.0, 3300.0]]
	var tall := [[8.0, 16.0], [16.0, 34.0], [14.0, 26.0], [30.0, 60.0]]
	for index in ranges.size():
		var section_range: Array = ranges[index]
		for side: float in [-1.0, 1.0]:
			var d: float = float(section_range[0]) + rng.randf_range(0.0, 10.0)
			var along: float = rng.randf_range(16.0, 34.0)
			while d < section_range[1]:
				var across: float = rng.randf_range(18.0, 30.0)
				var visible: float = rng.randf_range(tall[index][0], tall[index][1])
				var setback: float = lateral_limit(d) + HULL_MARGIN + 6.0 + rng.randf_range(0.0, 6.0)
				var next_along: float = rng.randf_range(16.0, 34.0)
				var gap: float = rng.randf_range(0.0, 14.0)
				var next_d := d + (along + next_along) * 0.5 + gap
				var inside := d - along * 0.5 >= float(section_range[0]) and d + along * 0.5 <= float(section_range[1])
				if inside and not in_arena(d, 10.0 + along * 0.5):
					_structure("city_building", d, side * (setback + across * 0.5), Vector3(across, visible + DRIFT + 6.0, along), -6.0, _tower_kind(index, rng) + 4 * rng.randi_range(0, 3))
				d = next_d
				along = next_along


## Two rows of lower blocks behind the front towers so the street never ends in a void, thinning out along the run.
func _generate_backdrop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261016
	for row in 2:
		for side: float in [-1.0, 1.0]:
			var d := rng.randf_range(0.0, 20.0)
			while d < LENGTH - 400.0:
				var along := float(rng.randi_range(0, 2)) * 6.0 + 28.0
				var across := float(rng.randi_range(0, 2)) * 6.0 + 24.0
				var run := d >= SECTION_STARTS[Section.RUN]
				var inner := lateral_limit(d) + 36.0 + (40.0 if run else 0.0) + 45.0 * row + rng.randf_range(0.0, 6.0)
				var roof := float(rng.randi_range(8, 16) if (row == 0 or d < SECTION_STARTS[Section.AVENUE]) else rng.randi_range(14, 30)) * 2.0
				if not run or rng.randf() < 0.8:
					_backdrop(d, side * (inner + across * 0.5), Vector3(across, roof + 4.5, along), rng.randi_range(0, 7))
				d += along + rng.randf_range(0.0, 10.0)


func _tower_kind(section: int, rng: RandomNumberGenerator) -> int:
	var mix: Array = [[2, 2, 0, 1], [1, 1, 2, 0], [2, 3, 0], [3, 3, 0, 2]][section]
	return mix[rng.randi() % mix.size()]


func height(d: float, u: float) -> float:
	var outside := INF
	for arena in arenas:
		var rect := Vector2(maxf(absf(d - arena.d) - (arena.radius + 2.0 * HULL_MARGIN), 0.0), maxf(absf(u) - (arena.radius - 6.0 + HULL_MARGIN), 0.0)).length()
		outside = minf(outside, minf(rect, maxf(Vector2(d - arena.d, u).length() - arena.radius, 0.0)))
	var floor_h := 0.2 + _ripple.get_noise_2d(d, u) * 0.1
	if outside == 0.0:
		return floor_h
	var au := absf(u)
	var limit := lateral_limit(d)
	var ridged := 1.0 - absf(_crest.get_noise_2d(d, u))
	# Dunes: long swells with sharper crests, low enough to drive over.
	var h := _swell.get_noise_2d(d, u) * 2.0 + ridged * ridged * 1.1 + _ripple.get_noise_2d(d, u) * 0.14
	# The avenue shows through in the troughs; sand banks against the towers and rolls away behind them.
	h += smoothstep(limit + HULL_MARGIN, limit + 20.0, au) * DRIFT
	h += smoothstep(limit + 20.0, limit + 110.0, au) * (5.0 + 14.0 * (_far.get_noise_2d(d, u) * 0.5 + 0.5))
	for index in HILL_COUNT:
		h += _hill(index, d, u)
	return lerpf(floor_h, h, smoothstep(0.0, 24.0, outside)) if outside < INF else h


## The sand ramp `index` adds at (d, u): a track that climbs along d to a lip and falls away behind it.
func _hill(index: int, d: float, u: float) -> float:
	var s := d - hill_d(index)
	if s < -30.0 or s > HILL_LENGTH + 40.0:
		return 0.0
	var across := 1.0 - smoothstep(HILL_HALF, HILL_HALF + 22.0, absf(u - hill_side(index) * HILL_U))
	var along := pow(clampf(s / HILL_LENGTH, 0.0, 1.0), 2.0) * (1.0 - smoothstep(0.0, 34.0, s - HILL_LENGTH))
	return HILL_HEIGHT * along * across


## Where a boss on ramp `index` stands at fraction `t` (0 foot, 1 lip), centred on the track.
func hill_point(index: int, t: float) -> Vector3:
	return Course.ground_at(hill_d(index) + HILL_LENGTH * t, hill_side(index) * HILL_U)


func ground_color(d: float, u: float, h: float, slope: float) -> Color:
	var au := absf(u)
	var grain := _grain.get_noise_2d(d, u)
	for index in HILL_COUNT:
		var s := d - hill_d(index)
		if s >= 0.0 and s <= HILL_LENGTH + 6.0 and absf(u - hill_side(index) * HILL_U) < HILL_HALF:
			return Palette.CREAM if int(s / 10.0) % 2 == 0 else Palette.STONE
	# Colours blend continuously with height, slope and grain so the facets shade softly instead of breaking into
	# hard-edged blotches at thresholds.
	# Crests catch the light, troughs settle into peach, and a face climbing toward the camera glows while the lee
	# side falls into ochre shade, so even low drivable swells read as dunes.
	var ridge := 1.0 - absf(_crest.get_noise_2d(d, u))
	var rise := height(d + 1.5, u) - height(d - 1.5, u)
	var sand := Palette.PEACH.lerp(Palette.BUTTER, smoothstep(0.82, 0.98, ridge) * 0.85 + smoothstep(2.0, 8.0, h) * 0.2)
	sand = sand.lerp(Palette.STRAW, clampf(-grain, 0.0, 1.0) * 0.35)
	sand = sand.lerp(Palette.CREAM, smoothstep(0.2, 0.8, rise) * 0.3).lerp(Palette.OCHRE, smoothstep(-0.2, -0.8, rise) * 0.3)
	sand = sand.lerp(Palette.OCHRE, smoothstep(0.25, 0.8, slope) * 0.6)
	for arena in arenas:
		var r := Vector2(d - arena.d, u).length()
		if r < arena.radius + 6.0:
			# The pit floor: swept concrete under a skin of sand, with the drill's scoured ring at the rim.
			var floor_color := Palette.CONCRETE.lerp(Palette.STRAW, 0.35 + grain * 0.3)
			return floor_color.lerp(Palette.STONE, smoothstep(arena.radius - 8.0, arena.radius, r) * 0.6)
	if au < lateral_limit(d) - 2.0:
		return sand.lerp(Palette.ASH, smoothstep(0.3, -0.6, h) * 0.5)
	return sand


func camera_u(d: float, u: float) -> float:
	var reach := lateral_limit(d - ChaseCamera.RAIL_BACK) - 6.0
	return clampf(u * 0.75, -reach, reach)


## Each stretch has its own haze: peach on the outskirts, amber in the avenue, rose over the pit, a dim brown
## storm in the canyon and white-gold on the run.
func fog_tint(d: float) -> Color:
	return _section_blend([fog_color, fog_color.lerp(Palette.AMBER, 0.2), fog_color.lerp(Palette.BLUSH, 0.4), fog_color.lerp(Palette.OCHRE, 0.5).darkened(0.1), fog_color.lerp(Palette.CREAM, 0.55)], d)


func fog_distance(d: float) -> float:
	match section_at(d):
		Section.OUTSKIRTS:
			return 400.0
		Section.AVENUE:
			return 340.0
		Section.PIT:
			return 380.0
		Section.CANYON:
			return 250.0
		Section.RUN:
			return 470.0
	return fog_end


func _section_blend(colors: Array, d: float) -> Color:
	var section := section_at(d)
	return (colors[maxi(section - 1, 0)] as Color).lerp(colors[section], smoothstep(SECTION_STARTS[section], SECTION_STARTS[section] + 120.0, d))


func music(section: int) -> String:
	match section:
		Section.RUN:
			return ""
		Section.PIT:
			return "res://assets/music/stage2_hovercraft.ogg"
		Section.CANYON:
			return "res://assets/music/stage2_canyon.ogg"
	return "res://assets/music/stage2_boulevard.ogg"


func boss_music(_phase := 0) -> String:
	return "res://assets/music/stage2_boss.ogg"


## Pushes a wave and its squad out to the haze.
func _to_horizon(event: Dictionary) -> void:
	if event.kind == "fpv" and not event.has("ahead"):
		event.ahead = 90.0 # The director's default slot, which would pop the drone up mid-street.
	if event.has("ahead"):
		event.ahead += HORIZON_SHIFT
	for member: Dictionary in event.get("squad", []):
		_to_horizon(member)


func events(hard: bool) -> Array[Dictionary]:
	var e: Array[Dictionary] = []
	var wave := func(d: float, kind: String, extra: Dictionary) -> void:
		var event := {"d": d, "type": "wave", "kind": kind, "hard_scale": 1.0}
		event.merge(extra)
		e.append(event)

	# Few enemies, each deadly: one hunter and at most one escort every 230 m, never a crowd. Outskirts build from a
	# drone to a mech pair, the avenue adds air and rocket threats, the canyon repeats them tighter inside the
	# storm, and quiet stretches before the pit and the run let the tank refit.
	wave.call(30.0, "fpv", {"height": 5.0})
	wave.call(240.0, "abel", {"u": -17.0, "ahead": 85.0, "drop": "coax", "squad": [
		{"kind": "fpv", "height": 5.0}]})
	wave.call(450.0, "kain", {"u": 21.0, "ahead": 85.0, "peak": true, "squad": [
		{"kind": "ugv", "u": -8.0, "ahead": 80.0, "props": {"weapon": "atgm"}}]})
	e.append({"d": 640.0, "type": "pickup", "id": "atgm"})

	wave.call(700.0, "hind", {"u": 8.0, "height": 5.0, "ahead": 90.0, "drop": "micro", "squad": [
		{"kind": "fpv", "height": 5.0}]})
	wave.call(930.0, "adam", {"u": 17.0, "ahead": 65.0, "squad": [
		{"kind": "walker", "u": -10.0, "ahead": 90.0, "props": {"weapon": "missile"}}]})
	wave.call(1150.0, "kain", {"u": -14.5, "ahead": 85.0, "peak": true, "squad": [
		{"kind": "fpv", "height": 5.0}]})
	wave.call(1370.0, "abel", {"u": 19.0, "ahead": 80.0, "squad": [
		{"kind": "ugv", "u": 8.0, "ahead": 75.0, "props": {"weapon": "atgm"}}]})
	e.append({"d": 1470.0, "type": "pickup", "id": "micro", "u": -4.0})

	e.append({"d": PIT_D - 270.0, "type": "checkpoint", "name": "midboss"})
	e.append({"d": PIT_D - 220.0, "type": "pickup", "id": "micro", "ahead": 15.0})
	e.append({"d": PIT_D - 160.0, "type": "pickup", "id": "repair", "u": 4.0, "ahead": 15.0})
	e.append({"d": PIT_D - 110.0, "type": "midboss", "kind": "borer", "ahead": 60.0, "peak": true, "hold": PIT_D - 56.0})

	e.append({"d": STORM_D, "type": "storm", "duration": 35.0})
	wave.call(2160.0, "hind", {"u": -8.0, "height": 5.0, "ahead": 85.0, "squad": [
		{"kind": "ugv", "u": 8.0, "ahead": 75.0, "props": {"weapon": "atgm"}}]})
	wave.call(2390.0, "kain", {"u": 14.5, "ahead": 85.0, "squad": [
		{"kind": "walker", "u": -6.0, "ahead": 90.0, "props": {"weapon": "missile"}}]})
	wave.call(2620.0, "abel", {"u": -10.0, "ahead": 100.0, "peak": true, "squad": [
		{"kind": "fpv", "count": 2, "height": 5.0}]})
	wave.call(2850.0, "adam", {"u": 15.0, "ahead": 65.0, "squad": [
		{"kind": "ugv", "u": -8.0, "ahead": 75.0, "props": {"weapon": "atgm"}}]})
	e.append({"d": 3000.0, "type": "hold", "at": 3015.0, "timeout": 25.0, "reward": "repair"})
	wave.call(3100.0, "hind", {"u": 8.0, "height": 5.0, "ahead": 85.0, "peak": true})
	e.append({"d": 3160.0, "type": "pickup", "id": "era", "u": -4.0})
	e.append({"d": 3220.0, "type": "pickup", "id": "atgm", "u": 4.0})

	# The run: the rail floors it to 140 km/h and the flying wing shows itself.
	e.append({"d": SECTION_STARTS[Section.RUN] + 20.0, "type": "checkpoint", "name": "boss"})
	e.append({"d": SECTION_STARTS[Section.RUN] + 60.0, "type": "pickup", "id": "repair", "u": -4.0, "ahead": 20.0})
	e.append({"d": SECTION_STARTS[Section.RUN] + 90.0, "type": "pickup", "id": "dragon", "ahead": 15.0})
	e.append({"d": SECTION_STARTS[Section.RUN] + 130.0, "type": "sprint", "kmh": SPRINT_KMH})
	e.append({"d": hill_d(0) - 62.0, "type": "boss", "kind": "wing", "rail": true})
	# Past the last ramp the rail stops short of the road's end, so the wing cannot simply fly away.
	e.append({"d": hill_d(HILL_COUNT - 1) + HILL_LENGTH, "type": "hold", "at": hill_d(HILL_COUNT - 1) + HILL_LENGTH + 150.0, "timeout": 600.0})

	if hard:
		var pressure := {450.0: {"ugv": 1}, 700.0: {"fpv": 1}}
		for event in e:
			if event.type != "wave" or not event.has("squad"):
				continue
			for member: Dictionary in event.squad:
				member.count = int(member.get("count", 1)) * 2 + int(pressure.get(event.d, {}).get(member.kind, 0))
				member.u = -float(member.get("u", 0.0))
				member.ahead = 65.0
				if member.kind == "ugv":
					member.props = {"weapon": "atgm"}
	for event in e:
		if event.type == "wave":
			_to_horizon(event)
	e.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	return e
