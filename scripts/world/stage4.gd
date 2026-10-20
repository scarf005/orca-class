class_name Stage4
extends StageDef
## A river valley the jungle has swallowed. The road winds through tight switchbacks under the canopy, crosses a
## meadow of overgrown ruin stumps where fire runs through the brush, wades a river ford, leaps a broken bridge over
## a gorge, climbs the one tower-walled avenue and opens on the clearing where the tracked fortress comes through
## the trees.

enum Section { VERGE, STUMPS, FORD, GORGE, AVENUE, CLEARING }

const SECTION_STARTS := [0.0, 1100.0, 1900.0, 2500.0, 3300.0, 4100.0]
const LENGTH := 4900.0
const HORIZON_SHIFT := 50.0 ## Squads spawn this much farther out, in the haze, and walk in.
const HULL_MARGIN := 3.0 ## The floor extends this far past the hull limit so the track samples at the edge never hang.
const CLEARING_D := 4500.0
const CLEARING_RADIUS := 160.0
const ENTRY_OUT := 80.0 ## How far outside the rim the fortress starts.
const ENTRY_ANGLE := deg_to_rad(-50.0) ## Where the fortress breaks out of the jungle, seen from the clearing's centre: ahead and to the left.
const STORM_D := 1750.0
## Switchbacks, a meadow, a straight ford, the bend into the gorge, the avenue and the long straight to the clearing.
const PLAN := [[500.0, 0.0], [260.0, 0.0], [150.0, 80.0], [80.0, 0.0], [150.0, -85.0], [80.0, 0.0], [150.0, 75.0], [60.0, 0.0], [150.0, -70.0],
	[300.0, 0.0], [250.0, 20.0], [250.0, -20.0], [600.0, 0.0], [200.0, -60.0], [500.0, 0.0], [200.0, 60.0], [1700.0, 0.0]]

const FORD_D := 2200.0
const FORD_HALF := 32.0 ## Half the length of the ford's level bed; banks slope away over BANK on each side.
const BANK := 26.0
const FORD_DEPTH := 1.05
const FORD_WATER := -0.35 ## Over the bed that leaves 0.7 m of water: wading, not swimming.
const GORGE_LIP := 2960.0 ## Where the broken bridge's deck ends in a cliff, on the left lane.
const GORGE_FAR := 2994.0 ## The far end of the bowl; its floor climbs out over GORGE_EXIT.
const GORGE_EXIT := 64.0 ## The trench lane's long climb out of the riverbed.
const GORGE_WALL := 16.0 ## The far bank the leap lands on: a steep climb out of the bowl on the bridge side.
const GORGE_DESCENT := 72.0 ## The right lane's long ramp down into the riverbed.
const GORGE_DEPTH := 9.0
const GORGE_WATER := -8.3
const RAMP_LENGTH := 40.0 ## The bridge ramp up to the lip: a drift on it builds the speed to clear the bowl.
const RAMP_RISE := 8.0
const RAMP_U := -9.0
const RAMP_HALF := 5.0
## Fallen strangler figs across the road: [d, u]. Each is a low ramp a drift can hop.
const LOGS := [[210.0, 0.0], [820.0, 4.0], [1320.0, -6.0], [1560.0, 7.0], [1790.0, -4.0]]
const LOG_LENGTH := 12.0
const LOG_RISE := 1.5
const LOG_HALF := 5.0

var _swell := make_noise(81, 0.008)
var _roots := make_noise(83, 0.03)
var _ripple := make_noise(89, 0.09)
var _patch := make_noise(97, 0.05)
var _far := make_noise(101, 0.006)


func _init() -> void:
	number = 4
	city = true
	water_slows = true
	standoff = 0.6
	plan = PLAN
	section_starts.assign(SECTION_STARTS)
	checkpoints = {"": 0.0, "boss": CLEARING_D - 260.0}
	coax_tiers = {"": 2, "boss": 2}
	arena_center_d = CLEARING_D
	arena_radius = CLEARING_RADIUS
	arenas = [{"d": CLEARING_D, "radius": CLEARING_RADIUS}]
	sky_top = Palette.SKY.lerp(Palette.TEAL, 0.5)
	sky_horizon = Palette.MINT.lerp(Palette.BUTTER, 0.35)
	sky_ground = Palette.PINE
	# Green light through leaves: the shade falls cool teal, the clearing's sun warm.
	ambient = Palette.TEAL.lerp(Palette.PINE, 0.35)
	ambient_energy = 0.7
	fog_color = Palette.TEAL.lerp(Palette.PINE, 0.45)
	storm_color = Palette.TEAL.lerp(Palette.PINE, 0.4)
	storm_motes = [Palette.LEAF, Palette.SAGE, Palette.MINT]
	fog_begin = 60.0
	fog_end = 330.0
	sun_color = Palette.BUTTER.lerp(Palette.CREAM, 0.4)
	sun_rotation = Vector3(-38.0, 130.0, 0.0)
	sun_energy = 1.0
	_generate_walls()
	_generate_stumps()
	_generate_entry()
	_generate_backdrop()


func boss_position() -> Vector3:
	var at := entry_point(ENTRY_OUT)
	return Course.ground_at(at.x, at.y)


## The point on the clearing's rim (in course d, u) where the fortress comes out of the trees, `out` metres past the rim.
func entry_point(out: float) -> Vector2:
	return Vector2(CLEARING_D, 0.0) + Vector2.from_angle(ENTRY_ANGLE) * (CLEARING_RADIUS + out)


func _street_half(d: float) -> float:
	var half := 17.0
	half = lerpf(half, 26.0, band(d, 1050.0, 1150.0, 1850.0, 1950.0))
	half = lerpf(half, 30.0, band(d, 1850.0, 1950.0, 2450.0, 2550.0))
	half = lerpf(half, 20.0, band(d, 2450.0, 2550.0, 3250.0, 3350.0))
	half = lerpf(half, 22.0, band(d, 3250.0, 3350.0, 4050.0, 4150.0))
	return half


func lateral_limit(d: float) -> float:
	for arena in arenas:
		if absf(d - arena.d) <= arena.radius:
			return arena.radius - 6.0
	return _street_half(d)


func valley_half_width(d: float) -> float:
	return lateral_limit(d) + 16.0


## Overgrown towers wall the avenue, the stage's one corridor.
func _generate_walls() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261020
	var first := SECTION_STARTS[Section.AVENUE]
	var last := SECTION_STARTS[Section.CLEARING]
	for side: float in [-1.0, 1.0]:
		var d: float = first + rng.randf_range(0.0, 10.0)
		var along: float = rng.randf_range(16.0, 34.0)
		while d < last:
			var across: float = rng.randf_range(18.0, 30.0)
			var visible: float = rng.randf_range(22.0, 46.0)
			var setback: float = lateral_limit(d) + HULL_MARGIN + 6.0 + rng.randf_range(0.0, 8.0)
			var next_along: float = rng.randf_range(16.0, 34.0)
			var gap: float = rng.randf_range(0.0, 30.0 if rng.randf() < 0.3 else 12.0)
			var next_d := d + (along + next_along) * 0.5 + gap
			if d - along * 0.5 >= first and d + along * 0.5 <= last:
				_structure("jungle_building", d, side * (setback + across * 0.5), Vector3(across, visible + 6.0, along), -6.0, rng.randi_range(0, 15))
			d = next_d
			along = next_along


## Everywhere else the ruins are broken stumps of buildings, scattered about the valley instead of lining the road.
func _generate_stumps() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261023
	var d := 120.0
	while d < SECTION_STARTS[Section.AVENUE]:
		var meadow := section_at(d) == Section.STUMPS
		d += rng.randf_range(28.0, 60.0) if meadow else rng.randf_range(90.0, 170.0)
		if in_arena(d, 40.0) or absf(d - FORD_D) < FORD_HALF + BANK + 20.0 or absf(d - (GORGE_LIP + GORGE_FAR) * 0.5) < 120.0:
			continue
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var reach := lateral_limit(d) + HULL_MARGIN + rng.randf_range(2.0 if meadow else 8.0, 40.0)
		var across := rng.randf_range(10.0, 18.0)
		var along := rng.randf_range(10.0, 18.0)
		_structure("jungle_building", d, side * (reach + across * 0.5), Vector3(across, rng.randf_range(5.0, 12.0) + 6.0, along), -6.0, rng.randi_range(0, 15), rng.randf() * 0.8 - 0.4)


## Overgrown ruins standing in the fortress's way through the trees: it drives through them on its way in.
func _generate_entry() -> void:
	var across := Vector2.from_angle(ENTRY_ANGLE + PI * 0.5)
	for step in 3:
		for lane: float in [-1.0, 1.0]:
			var at := entry_point(12.0 + 22.0 * step) + across * lane * (20.0 + 6.0 * step)
			_structure("jungle_building", at.x, at.y, Vector3(26.0, 26.0 + 8.0 * step, 28.0), -6.0, step * 2 + int(lane > 0.0))


## Two rows of lower overgrown blocks behind the avenue's front towers; elsewhere only a few stumps stand far back.
func _generate_backdrop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261021
	for row in 2:
		for side: float in [-1.0, 1.0]:
			var d := rng.randf_range(0.0, 20.0)
			while d < LENGTH - 300.0:
				var along := float(rng.randi_range(0, 2)) * 6.0 + 28.0
				var across := float(rng.randi_range(0, 2)) * 6.0 + 24.0
				var inner := lateral_limit(d) + 36.0 + 45.0 * row + rng.randf_range(0.0, 6.0)
				var roof := float(rng.randi_range(8, 18) if row == 0 else rng.randi_range(14, 30)) * 2.0
				var town := section_at(d) == Section.AVENUE or rng.randf() < 0.12
				if town:
					_backdrop(d, side * (inner + across * 0.5), Vector3(across, roof + 4.5, along), rng.randi_range(0, 7))
				d += along + rng.randf_range(0.0, 10.0)


## The ford: how far the riverbed lowers the road at `d` (0 off the ford, FORD_DEPTH on its level bed).
func ford_weight(d: float) -> float:
	return band(d, FORD_D - FORD_HALF - BANK, FORD_D - FORD_HALF, FORD_D + FORD_HALF, FORD_D + FORD_HALF + BANK)


## The gorge: how far below the road the floor lies at (d, u). The left lane ends in a cliff at the bridge's lip, the
## right lane slopes down a long ramp into the riverbed, and both climb out together on the far side.
func gorge_depth(d: float, u: float) -> float:
	var left := smoothstep(GORGE_LIP + 1.0, GORGE_LIP + 3.5, d) - smoothstep(GORGE_FAR, GORGE_FAR + GORGE_WALL, d)
	var right := smoothstep(GORGE_LIP - GORGE_DESCENT, GORGE_LIP - 4.0, d) - smoothstep(GORGE_FAR, GORGE_FAR + GORGE_EXIT, d)
	return GORGE_DEPTH * lerpf(left, right, smoothstep(-1.0, 7.0, u))


## The bridge ramp's height at (d, u): a straight climb to the lip.
func bridge_ramp(d: float, u: float) -> float:
	var s := d - (GORGE_LIP - RAMP_LENGTH)
	if s < 0.0 or s > RAMP_LENGTH + 1.0:
		return 0.0
	var across := 1.0 - smoothstep(RAMP_HALF, RAMP_HALF + 3.0, absf(u - RAMP_U))
	return RAMP_RISE * smoothstep(0.0, 6.0, s) * clampf(s / RAMP_LENGTH, 0.0, 1.0) * across


## A fallen fig's hump at (d, u): a short climb to the trunk, then a drop.
func log_hump(d: float, u: float) -> float:
	var result := 0.0
	for log: Array in LOGS:
		var s: float = d - float(log[0])
		if s < -2.0 or s > LOG_LENGTH + 3.0:
			continue
		var across := 1.0 - smoothstep(LOG_HALF, LOG_HALF + 3.0, absf(u - float(log[1])))
		result = maxf(result, LOG_RISE * clampf(s / LOG_LENGTH, 0.0, 1.0) * (1.0 - smoothstep(LOG_LENGTH, LOG_LENGTH + 3.0, s)) * across)
	return result


func height(d: float, u: float) -> float:
	var outside := INF
	for arena in arenas:
		var rect := Vector2(maxf(absf(d - arena.d) - (arena.radius + 2.0 * HULL_MARGIN), 0.0), maxf(absf(u) - (arena.radius - 6.0 + HULL_MARGIN), 0.0)).length()
		outside = minf(outside, minf(rect, maxf(Vector2(d - arena.d, u).length() - arena.radius, 0.0)))
	var floor_h := 0.1 + _ripple.get_noise_2d(d, u) * 0.08
	if outside == 0.0:
		return floor_h
	var au := absf(u)
	var limit := lateral_limit(d)
	var ridged := 1.0 - absf(_roots.get_noise_2d(d, u))
	# Root-heaved ground: long gentle swells with tangled ridges, low enough to drive over.
	var h := _swell.get_noise_2d(d, u) * 1.2 + ridged * ridged * 0.5 + _ripple.get_noise_2d(d, u) * 0.1
	# The ground rises into the forest floor beside the road and rolls away into hills.
	h += smoothstep(limit + HULL_MARGIN, limit + 25.0, au) * 3.0
	h += smoothstep(limit + 25.0, limit + 120.0, au) * (6.0 + 16.0 * (_far.get_noise_2d(d, u) * 0.5 + 0.5))
	# The ford's bed is level and the river runs across the whole valley floor.
	var bed := ford_weight(d) * (1.0 - smoothstep(limit + 10.0, limit + 70.0, au))
	h = lerpf(h, -FORD_DEPTH + _ripple.get_noise_2d(d, u) * 0.06, bed)
	var gorge := gorge_depth(d, u) * (1.0 - smoothstep(limit + 4.0, limit + 40.0, au))
	h = lerpf(h, floor_h, minf(gorge * 0.12, 1.0)) - gorge + bridge_ramp(d, u) + log_hump(d, u)
	return lerpf(floor_h, h, smoothstep(0.0, 24.0, outside)) if outside < INF else h


func ramp_at(d: float, u: float) -> float:
	var s := d - (GORGE_LIP - RAMP_LENGTH)
	if s >= 0.0 and s <= RAMP_LENGTH and absf(u - RAMP_U) < RAMP_HALF:
		return s / RAMP_LENGTH
	for log: Array in LOGS:
		var along: float = d - float(log[0])
		if along >= 0.0 and along <= LOG_LENGTH and absf(u - float(log[1])) < LOG_HALF:
			return along / LOG_LENGTH
	return -1.0


## Rail distance beyond which the stage holds no more water or leaps.
func water_surface(c: Vector2) -> float:
	var level := -INF
	if absf(c.x - FORD_D) < FORD_HALF + BANK:
		level = FORD_WATER
	elif c.x > GORGE_LIP - GORGE_DESCENT and c.x < GORGE_FAR + GORGE_EXIT:
		level = GORGE_WATER
	return level if level > -INF and height(c.x, c.y) < level else -INF


func water_mesh() -> ArrayMesh:
	var b := LowPoly.new()
	for span: Array in [[FORD_D - FORD_HALF - BANK, FORD_D + FORD_HALF + BANK, FORD_WATER], [GORGE_LIP - GORGE_DESCENT, GORGE_FAR + GORGE_EXIT, GORGE_WATER]]:
		var level: float = span[2]
		var d: float = span[0]
		while d < span[1]:
			for u in range(-90, 90, 6):
				var corners := [height(d, u), height(d + 6.0, u), height(d + 6.0, u + 6.0), height(d, u + 6.0), height(d + 3.0, u + 3.0)]
				if corners.min() >= level:
					continue
				var a := Course.to_world(d, float(u), level)
				var c := Course.to_world(d + 6.0, float(u), level)
				var e := Course.to_world(d + 6.0, u + 6.0, level)
				var f := Course.to_world(d, u + 6.0, level)
				var shallow := clampf(1.0 - (level - float(corners[4])) * 1.4, 0.0, 1.0)
				var tint := Palette.CYAN.lerp(Palette.TEAL, 0.35 + 0.3 * shallow)
				b.tri(a, c, e, Color(tint, 0.85), Vector3.UP)
				b.tri(a, e, f, Color(tint, 0.85), Vector3.UP)
				# Current: pale streaks run with the flow, across the road, thickest over the shallows.
				var chance := fposmod(sin(d * 12.9898 + u * 78.233) * 43758.5453, 1.0)
				if chance < 0.18 + 0.2 * shallow:
					var head := Course.to_world(d + 1.0 + 3.0 * chance, float(u) + 1.0, level + 0.04)
					b.tri(head, Course.to_world(d + 1.8 + 3.0 * chance, float(u) + 1.0, level + 0.04), Course.to_world(d + 1.4 + 3.0 * chance, float(u) + 4.0 + 8.0 * chance, level + 0.04), Color(Palette.CREAM, 0.7), Vector3.UP)
			d += 6.0
	return b.mesh()


func ground_color(d: float, u: float, h: float, slope: float) -> Color:
	var au := absf(u)
	var patch := _patch.get_noise_2d(d, u)
	var growth := smoothstep(-0.3, 0.6, patch)
	var floor_color := Palette.PINE.darkened(0.15 * (1.0 - smoothstep(1100.0, 1300.0, d) )).lerp(Palette.MOSS, clampf(slope * 2.0 + smoothstep(0.0, 4.0, h) * 0.3, 0.0, 1.0) * 0.6)
	floor_color = floor_color.lerp(Palette.SAGE, growth * 0.2).lerp(Palette.LEAF, smoothstep(0.55, 0.9, patch) * 0.2)
	for arena in arenas:
		var r := Vector2(d - arena.d, u).length()
		if r < arena.radius + 6.0:
			# The clearing: a cracked concrete plaza under a skin of moss, torn up where the fortress will drive.
			var plaza := Palette.CONCRETE.lerp(Palette.STONE, 0.3 + patch * 0.3).lerp(floor_color, 0.5 + growth * 0.4)
			return plaza.lerp(floor_color, smoothstep(arena.radius - 10.0, arena.radius + 2.0, r))
	var ramp := ramp_at(d, u)
	if ramp >= 0.0 and h > 0.4:
		return Palette.CREAM if int(ramp * 4.0 * (RAMP_LENGTH if d > GORGE_LIP - RAMP_LENGTH - 1.0 else LOG_LENGTH) / 4.0) % 2 == 0 else Palette.STONE
	if h < FORD_WATER and absf(d - FORD_D) < FORD_HALF + BANK + 10.0:
		return Palette.OCHRE.lerp(Palette.WOOD, 0.45)
	if gorge_depth(d, u) > 0.5:
		return Palette.STONE.lerp(Palette.SLATE, clampf(gorge_depth(d, u) / GORGE_DEPTH, 0.0, 1.0) * 0.6).lerp(Palette.MOSS, growth * 0.25)
	if au < lateral_limit(d) - 2.0:
		# The road: pale laterite dust over the old asphalt, moss creeping in only at the verges and where roots lifted it.
		var dust := Palette.OCHRE.lerp(Palette.CONCRETE, 0.2 + patch * 0.15)
		return dust.lerp(floor_color, clampf(0.05 + growth * 0.3 + smoothstep(6.0, lateral_limit(d), au) * 0.7, 0.0, 1.0))
	return floor_color


func camera_u(d: float, u: float) -> float:
	var reach := lateral_limit(d - ChaseCamera.RAIL_BACK) - 6.0
	return clampf(u * 0.75, -reach, reach)


## Each stretch has its own haze: green dusk in the valley, hot haze over the meadow, river mist at the ford, gorge
## shadow, the avenue's cool shade and the clearing's open light.
func fog_tint(d: float) -> Color:
	return _section_blend([fog_color.lerp(Palette.INK, 0.3), fog_color.lerp(Palette.BUTTER, 0.12), fog_color.lerp(Palette.MINT, 0.3), fog_color.lerp(Palette.INK, 0.15), fog_color.lerp(Palette.MOSS, 0.35), fog_color.lerp(Palette.BUTTER, 0.12)], d)


func fog_distance(d: float) -> float:
	match section_at(d):
		Section.VERGE:
			return 170.0
		Section.STUMPS:
			return 420.0
		Section.FORD:
			return 360.0
		Section.GORGE:
			return 330.0
		Section.AVENUE:
			return 260.0
		Section.CLEARING:
			return 420.0
	return fog_end


func _section_blend(colors: Array, d: float) -> Color:
	var section := section_at(d)
	return (colors[maxi(section - 1, 0)] as Color).lerp(colors[section], smoothstep(SECTION_STARTS[section], SECTION_STARTS[section] + 120.0, d))


func music(section: int) -> String:
	match section:
		Section.CLEARING:
			return ""
		Section.GORGE, Section.AVENUE:
			return "res://assets/music/stage4_jungle.ogg"
	return "res://assets/music/stage4_ruins.ogg"


func boss_music(_phase := 0) -> String:
	return "res://assets/music/stage4_boss.ogg"


## Pushes a wave and its squad out to the haze.
func _to_horizon(event: Dictionary) -> void:
	if event.kind == "fpv" and not event.has("ahead"):
		event.ahead = 90.0 # The director's default slot, which would pop the drone up mid-street.
	if event.has("ahead") and not event.get("close", false):
		event.ahead += HORIZON_SHIFT
	for member: Dictionary in event.get("squad", []):
		_to_horizon(member)


func events(hard: bool) -> Array[Dictionary]:
	var e: Array[Dictionary] = []
	var wave := func(d: float, kind: String, extra: Dictionary) -> void:
		var event := {"d": d, "type": "wave", "kind": kind, "hard_scale": 1.0}
		event.merge(extra)
		e.append(event)
	var napalm := {"napalm": true}

	# The verge teaches the flame: one tank, then the walkers, each alone, and bug drones that scatter fire where they fall.
	wave.call(40.0, "fpv", {"height": 5.0, "props": napalm})
	wave.call(230.0, "crocodile", {"u": -10.0, "ahead": 80.0, "drop": "coax"})
	wave.call(430.0, "burner", {"u": 12.0, "ahead": 75.0, "squad": [
		{"kind": "fpv", "height": 5.0, "props": napalm}]})
	e.append({"d": 640.0, "type": "pickup", "id": "atgm"})

	# The meadow: flame crews work in pairs between the stumps and the brush they light carries the fire along the road.
	wave.call(760.0, "crocodile", {"u": 10.0, "ahead": 80.0, "squad": [
		{"kind": "ugv", "u": -8.0, "ahead": 75.0, "props": {"weapon": "atgm"}}]})
	wave.call(980.0, "burner", {"u": -12.0, "ahead": 70.0, "peak": true, "drop": "micro", "squad": [
		{"kind": "burner", "u": 12.0, "ahead": 90.0}]})
	wave.call(1220.0, "crocodile", {"u": 0.0, "ahead": 85.0, "squad": [
		{"kind": "fpv", "count": 2, "height": 5.0, "props": napalm}]})
	e.append({"d": 1400.0, "type": "pickup", "id": "micro", "u": -4.0})
	wave.call(1450.0, "burner", {"u": 8.0, "ahead": 70.0, "squad": [
		{"kind": "crocodile", "u": -12.0, "ahead": 95.0}]})
	e.append({"d": 1620.0, "type": "pickup", "id": "repair", "u": 4.0})

	# A monsoon thickens the haze over the meadow's end and the ford.
	e.append({"d": STORM_D, "type": "storm", "duration": 35.0})
	wave.call(1830.0, "crocodile", {"u": -12.0, "ahead": 85.0, "squad": [
		{"kind": "crocodile", "u": 12.0, "ahead": 100.0}]})
	wave.call(2060.0, "burner", {"u": 12.0, "ahead": 70.0, "peak": true, "squad": [
		{"kind": "fpv", "count": 2, "height": 5.0, "props": napalm}]})
	# The ford: a crocodile waits in the reeds and breaks cover at close range.
	wave.call(2130.0, "crocodile", {"u": 14.0, "ahead": 42.0, "close": true, "squad": [
		{"kind": "crocodile", "u": -14.0, "ahead": 60.0, "close": true}]})
	wave.call(2340.0, "crocodile", {"u": 0.0, "ahead": 85.0, "squad": [
		{"kind": "burner", "u": -10.0, "ahead": 95.0}]})
	e.append({"d": 2450.0, "type": "pickup", "id": "era", "u": -4.0})
	wave.call(2600.0, "burner", {"u": -10.0, "ahead": 70.0, "squad": [
		{"kind": "burner", "u": 10.0, "ahead": 85.0},
		{"kind": "ugv", "u": 0.0, "ahead": 100.0, "props": {"weapon": "atgm"}}]})
	e.append({"d": 2780.0, "type": "hold", "at": 2795.0, "timeout": 25.0, "reward": "repair"})

	# The gorge is left alone to be crossed; the avenue after it holds the densest fire of the stage.
	wave.call(3110.0, "crocodile", {"u": 10.0, "ahead": 85.0, "peak": true, "squad": [
		{"kind": "burner", "u": -12.0, "ahead": 95.0},
		{"kind": "fpv", "count": 2, "height": 5.0, "props": napalm}]})
	wave.call(3250.0, "burner", {"u": 0.0, "ahead": 70.0, "squad": [
		{"kind": "crocodile", "u": -12.0, "ahead": 100.0},
		{"kind": "crocodile", "u": 12.0, "ahead": 115.0}]})
	e.append({"d": 3400.0, "type": "pickup", "id": "atgm", "u": 4.0})
	wave.call(3500.0, "crocodile", {"u": -8.0, "ahead": 85.0, "squad": [
		{"kind": "burner", "count": 2, "u": 10.0, "ahead": 90.0}]})
	wave.call(3780.0, "burner", {"u": 12.0, "ahead": 70.0, "peak": true, "squad": [
		{"kind": "crocodile", "u": -12.0, "ahead": 95.0},
		{"kind": "fpv", "count": 2, "height": 5.0, "props": napalm}]})
	e.append({"d": 3950.0, "type": "hold", "at": 3965.0, "timeout": 25.0, "reward": "repair"})

	# The clearing: refit, then the trees go down.
	e.append({"d": CLEARING_D - 260.0, "type": "checkpoint", "name": "boss"})
	e.append({"d": CLEARING_D - 230.0, "type": "pickup", "id": "repair", "u": -4.0, "ahead": 15.0})
	e.append({"d": CLEARING_D - 200.0, "type": "pickup", "id": "micro", "u": 4.0, "ahead": 15.0})
	e.append({"d": CLEARING_D - 170.0, "type": "pickup", "id": "dragon", "ahead": 15.0})
	e.append({"d": CLEARING_D - 130.0, "type": "boss", "kind": "fortress"})

	# Between the flame crews, plain drone swarms the tank mows down on the move: napalm stays with the crews, or the
	# fodder would carpet the road in fire.
	var swarms := [135.0, 330.0, 600.0, 870.0, 1100.0, 1335.0, 1940.0, 2470.0, 3180.0, 3640.0]
	for index in swarms.size():
		wave.call(swarms[index], "fpv", {"count": 3, "u": 10.0 * (1 - index % 2 * 2), "spacing": 6.0, "ahead": 70.0, "height": 5.0})

	if hard:
		for event in e:
			if event.type != "wave" or not event.has("squad"):
				continue
			for member: Dictionary in event.squad:
				member.count = int(member.get("count", 1)) * 2
				member.u = -float(member.get("u", 0.0))
				member.ahead = 65.0
	for event in e:
		if event.type == "wave":
			_to_horizon(event)
	e.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	return e
