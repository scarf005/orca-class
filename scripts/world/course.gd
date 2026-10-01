class_name Course
## Stage 1 geography. The road starts out toward -Z and winds through bends; `d` is distance along
## it and `u` the offset to its right, so every point near the road maps to exactly one (d, u).

enum Section { FARM, VILLAGE, SCHOOL, RESERVOIR, OVERPASS, ARENA }

const SECTION_STARTS := [0.0, 560.0, 1450.0, 1760.0, 2660.0, 3420.0]
const LENGTH := 3700.0
const WATER_LEVEL := -2.2
const DECK_HEIGHT := 8.0
const RAMP_UP := Vector2(2900.0, 3000.0) ## Highway embankment rises over this span of d.
const RAMP_DOWN := Vector2(3300.0, 3400.0)
const UNDERPASS_D := 2750.0 ## An elevated highway crosses overhead here.
const SCHOOL_YARD := Vector2(1560.0, 1700.0)
const MIDBOSS_D := 1655.0
const ARENA_CENTER_D := 3530.0
const ARENA_RADIUS := 85.0
const DAM_D := 3640.0

## The road plan as [length, turn in degrees] pieces from d = PLAN_START; positive turns bend right
## and 0 is a straight. Curvature is smoothed so bends ease in and out. Every bend keeps its
## radius above the terrain's half width, so the valley never folds over itself. Straight before the
## start (where the debug room sits), through the schoolyard, under the crossing highway and into
## the arena.
const PLAN_START := -500.0
const PLAN := [
	[650.0, 0.0], [260.0, 60.0], [90.0, 0.0], [360.0, -90.0], [150.0, 0.0], [320.0, 75.0], [430.0, 0.0],
	[400.0, -90.0], [90.0, 0.0], [370.0, 90.0], [180.0, 0.0], [250.0, -45.0], [900.0, 0.0],
]
const STEP := 1.0 ## Spacing of the precomputed centerline samples.
const SMOOTH := 30 ## Curvature box-filter half width, in samples (applied twice).
const MAP_REACH := 260.0 ## How far from the road `to_course` resolves points through the lookup grid.
const MAP_CELL := 8.0

## The debug room swaps the valley for a flat, open floor.
static var flat := false

static var _noise := _make_noise(7, 0.004)
static var _detail := _make_noise(11, 0.05)
static var _fungus := _make_noise(23, 0.018)


static func _make_noise(seed_value: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return noise


static func section_at(d: float) -> Section:
	var result := Section.FARM
	for i in SECTION_STARTS.size():
		if d >= SECTION_STARTS[i]:
			result = i as Section
	return result


## Centerline samples every STEP metres: position (x, z), heading (0 = -Z, positive turns right)
## and signed curvature.
static var _points := PackedVector2Array()
static var _headings := PackedFloat32Array()
static var _curvature := PackedFloat32Array()
static var _map_origin := Vector2.ZERO
static var _map_size := Vector2i.ZERO
## A coarse world grid holding the nearest course d of each cell, seeding `to_course`.
static var _map := _build()


static func _build() -> PackedFloat32Array:
	var raw := PackedFloat32Array()
	for piece: Array in PLAN:
		var length: float = piece[0]
		var k: float = deg_to_rad(piece[1]) / length
		for i in int(length / STEP):
			raw.append(k)
	for pass_index in 2:
		var prefix := PackedFloat32Array([0.0])
		for k in raw:
			prefix.append(prefix[-1] + k)
		var smoothed := PackedFloat32Array()
		for i in raw.size():
			smoothed.append((prefix[mini(i + SMOOTH + 1, raw.size())] - prefix[maxi(i - SMOOTH, 0)]) / (SMOOTH * 2 + 1))
		raw = smoothed
	_curvature = raw
	var heading := 0.0
	var at := Vector2(0.0, -PLAN_START)
	for i in raw.size():
		_points.append(at)
		_headings.append(heading)
		var mid := heading + raw[i] * STEP * 0.5
		at += Vector2(sin(mid), -cos(mid)) * STEP
		heading += raw[i] * STEP
	# Rasterize the valley ribbon into the lookup grid, nearer-to-road samples winning.
	var low := Vector2.INF
	var high := -Vector2.INF
	for point in _points:
		low = low.min(point)
		high = high.max(point)
	_map_origin = low - Vector2.ONE * (MAP_REACH + MAP_CELL)
	_map_size = Vector2i(((high - low + Vector2.ONE * (MAP_REACH + MAP_CELL) * 2.0) / MAP_CELL).ceil())
	var map := PackedFloat32Array()
	map.resize(_map_size.x * _map_size.y)
	map.fill(NAN)
	var nearest := PackedFloat32Array()
	nearest.resize(map.size())
	nearest.fill(INF)
	var i := 0
	while i < _points.size():
		var normal := Vector2(cos(_headings[i]), sin(_headings[i]))
		var inside := 0.9 / maxf(absf(_curvature[i]), 0.0001)
		var u := -MAP_REACH
		while u <= MAP_REACH:
			if absf(u) < inside or signf(u) != signf(_curvature[i]):
				var cell := Vector2i(((_points[i] + normal * u - _map_origin) / MAP_CELL).floor())
				var index := cell.y * _map_size.x + cell.x
				if absf(u) < nearest[index]:
					nearest[index] = absf(u)
					map[index] = PLAN_START + i * STEP
			u += MAP_CELL * 0.7
		i += int(MAP_CELL * 0.5)
	return map


static func _center(d: float) -> Vector2:
	var x := clampf((d - PLAN_START) / STEP, 0.0, _points.size() - 1.001)
	var i := int(x)
	return _points[i].lerp(_points[i + 1], x - i)


static func _heading(d: float) -> float:
	var x := clampf((d - PLAN_START) / STEP, 0.0, _points.size() - 1.001)
	var i := int(x)
	return lerpf(_headings[i], _headings[i + 1], x - i)


static func _curvature_at(d: float) -> float:
	return _curvature[clampi(int((d - PLAN_START) / STEP), 0, _curvature.size() - 1)]


## Unit forward vector of the road at distance d.
static func forward(d: float) -> Vector3:
	var heading := _heading(d)
	return Vector3(sin(heading), 0.0, -cos(heading))


## Unit vector pointing to +u (the road's right) at distance d.
static func right(d: float) -> Vector3:
	var heading := _heading(d)
	return Vector3(cos(heading), 0.0, sin(heading))


## Yaw that turns a node's -Z to face along the road at d.
static func yaw_at(d: float) -> float:
	return -_heading(d)


static func to_world(d: float, u: float, y := 0.0) -> Vector3:
	var c := _center(d)
	var heading := _heading(d)
	return Vector3(c.x + cos(heading) * u, y, c.y + sin(heading) * u)


static func ground_at(d: float, u: float) -> Vector3:
	var p := to_world(d, u)
	p.y = height(d, u)
	return p


## Inverse of `to_world` for points within MAP_REACH of the road: a grid lookup seeds d, then a
## few curvature-corrected projection steps settle it onto the nearest centerline point.
static func to_course(p: Vector3) -> Vector2:
	var flat := Vector2(p.x, p.z)
	var cell := Vector2i(((flat - _map_origin) / MAP_CELL).floor())
	var d := NAN
	if cell.x >= 0 and cell.y >= 0 and cell.x < _map_size.x and cell.y < _map_size.y:
		d = _map[cell.y * _map_size.x + cell.x]
	if is_nan(d):
		d = _nearest_sample(flat)
	var u := 0.0
	for i in 3:
		var c := _center(d)
		var heading := _heading(d)
		var offset := flat - c
		u = offset.dot(Vector2(cos(heading), sin(heading)))
		var along := offset.dot(Vector2(sin(heading), -cos(heading)))
		d += along / maxf(1.0 - _curvature_at(d) * u, 0.1)
	var heading := _heading(d)
	u = (flat - _center(d)).dot(Vector2(cos(heading), sin(heading)))
	return Vector2(d, u)


## Brute-force fallback for points outside the lookup grid.
static func _nearest_sample(flat: Vector2) -> float:
	var best := 0
	var best_distance := INF
	for i in range(0, _points.size(), 10):
		var distance := _points[i].distance_squared_to(flat)
		if distance < best_distance:
			best_distance = distance
			best = i
	return PLAN_START + best * STEP


static func height_at(p: Vector3) -> float:
	var c := to_course(p)
	return height(c.x, c.y)


## Half width of the flat valley floor around the road.
static func valley_half_width(d: float) -> float:
	var width := 34.0
	width = lerpf(width, 70.0, _band(d, 1500.0, 1580.0, 1690.0, 1760.0))
	width = lerpf(width, ARENA_RADIUS + 25.0, _band(d, 3390.0, 3450.0, 3700.0, 3800.0))
	return width


static func deck_blend(d: float) -> float:
	return _band(d, RAMP_UP.x, RAMP_UP.y, RAMP_DOWN.x, RAMP_DOWN.y)


static func is_water(d: float, u: float) -> bool:
	return height(d, u) < WATER_LEVEL


static func height(d: float, u: float) -> float:
	if flat:
		return 0.0
	var au := absf(u)
	var half := valley_half_width(d)
	var h := _noise.get_noise_2d(d, u) * 1.2
	# Hills and mountains rise beyond the valley floor.
	var rise := smoothstep(half, half + 70.0, au)
	h += rise * (22.0 + 26.0 * (_noise.get_noise_2d(d * 0.6 + 500.0, u * 0.6) + 0.5)) + rise * rise * 18.0
	h += _detail.get_noise_2d(d, u) * 0.35 * (0.3 + rise)
	var section := section_at(d)
	# Rice paddies: flat terraces stepping down toward the road, with raised dikes between plots.
	var paddy := _band(d, -100.0, 20.0, 1500.0, 1560.0) * smoothstep(7.0, 9.0, au) * (1.0 - rise)
	if paddy > 0.0:
		var plot := _paddy_plot(d, u)
		var terrace := floorf(au / 18.0) * 0.45 - 0.5
		h = lerpf(h, terrace + plot.y * 0.25, paddy)
	# The road is a slightly raised, flat strip.
	var road := 1.0 - smoothstep(4.0, 6.0, au)
	h = lerpf(h, 0.15 + _noise.get_noise_2d(d, 0.0) * 0.8, road * (1.0 - rise))
	# Reservoir: water on the left of the road, behind a low embankment.
	if section == Section.RESERVOIR or d > SECTION_STARTS[Section.RESERVOIR] - 60.0:
		var lake := _band(d, 1760.0, 1840.0, 2560.0, 2680.0)
		var basin := smoothstep(-16.0, -34.0, u) * (1.0 - smoothstep(-95.0, -125.0, u))
		h = lerpf(h, -6.0, lake * basin)
	# Highway embankment.
	var deck := deck_blend(d)
	if deck > 0.0:
		var on_deck := 1.0 - smoothstep(15.0, 22.0, au)
		h = lerpf(h, DECK_HEIGHT * deck, on_deck)
	# The schoolyard and boss arena are flat.
	var yard := _band(d, SCHOOL_YARD.x - 30.0, SCHOOL_YARD.x, SCHOOL_YARD.y, SCHOOL_YARD.y + 30.0) * (1.0 - smoothstep(50.0, 62.0, au))
	h = lerpf(h, 0.3, yard)
	var arena := _band(d, 3400.0, 3440.0, DAM_D + 2.0, DAM_D + 6.0) * (1.0 - smoothstep(ARENA_RADIUS, ARENA_RADIUS + 15.0, au))
	h = lerpf(h, 0.2 + _noise.get_noise_2d(d, u) * 0.6, arena)
	# Behind the dam the reservoir bed is a bank as high as the wall's back face (see Dam), which
	# stands on the flat arena floor in front of it.
	h = lerpf(h, maxf(h, 27.0), smoothstep(DAM_D + 4.0, DAM_D + 7.0, d))
	return h


## Returns (plot id hash, dike amount 0..1) for paddy plots of about 18 × 24 m.
static func _paddy_plot(d: float, u: float) -> Vector2:
	var cell := Vector2(floorf(d / 24.0), floorf(u / 18.0))
	var local := Vector2(fposmod(d, 24.0), fposmod(u, 18.0))
	var edge := minf(minf(local.x, 24.0 - local.x), minf(local.y, 18.0 - local.y))
	return Vector2(fposmod(sin(cell.dot(Vector2(12.9898, 78.233))) * 43758.5453, 1.0), 1.0 - smoothstep(0.4, 1.0, edge))


## 0 before a, ramps to 1 over [a, b], holds, then ramps back to 0 over [c, e].
static func _band(x: float, a: float, b: float, c: float, e: float) -> float:
	if x <= a or x >= e:
		return 0.0
	if x < b:
		return smoothstep(a, b, x)
	if x > c:
		return 1.0 - smoothstep(c, e, x)
	return 1.0


## How overgrown the ground is (0..1). Fungus thickens as the stage goes on.
static func fungus_at(d: float, u: float) -> float:
	var progress := clampf(d / 3400.0, 0.0, 1.0)
	var n := _fungus.get_noise_2d(d, u) * 0.5 + 0.5
	return smoothstep(0.8 - progress * 0.14, 0.88 - progress * 0.14, n)


static func ground_color(d: float, u: float, h: float, slope: float) -> Color:
	if flat:
		return Palette.SAGE if (int(floorf(d / 10.0)) + int(floorf(u / 10.0))) % 2 == 0 else Palette.LEAF
	var au := absf(u)
	var rise := smoothstep(valley_half_width(d), valley_half_width(d) + 70.0, au)
	var color := Palette.SAGE
	if d > DAM_D + 3.0 and d < DAM_D + 9.0:
		color = Palette.STONE # The bank the dam's back face leans on.
	elif h < WATER_LEVEL + 0.4:
		color = Palette.OCHRE if h > WATER_LEVEL - 0.6 else Palette.TEAL
	elif au < 5.0 and deck_blend(d) < 0.5:
		color = Palette.CONCRETE if section_at(d) != Section.FARM else Palette.OCHRE
		if absf(au - 2.6) < 0.15 and section_at(d) >= Section.VILLAGE:
			color = Palette.CREAM
	elif deck_blend(d) > 0.9 and au < 15.0:
		color = Palette.STONE if au < 13.0 else Palette.CONCRETE
		if absf(u) < 0.25 and fposmod(d, 12.0) < 6.0:
			color = Palette.BUTTER
	elif _band(d, SCHOOL_YARD.x - 20.0, SCHOOL_YARD.x, SCHOOL_YARD.y, SCHOOL_YARD.y + 20.0) > 0.5 and au < 55.0:
		color = Palette.OCHRE if au > 3.0 else Palette.PEACH
	elif _band(d, -100.0, 20.0, 1500.0, 1560.0) > 0.5 and au > 8.0 and rise < 0.2:
		var plot := _paddy_plot(d, u)
		if plot.y > 0.5:
			color = Palette.PINE if section_at(d) == Section.VILLAGE else Palette.SAGE
		elif section_at(d) == Section.VILLAGE and plot.x > 0.55:
			color = Palette.SAGE
		else:
			color = Palette.BUTTER if plot.x > 0.35 else Palette.STRAW
	elif rise > 0.35:
		color = Palette.PINE if slope < 0.9 else Palette.MOSS
		if h > 36.0 and slope < 0.7:
			color = Palette.SAGE
	if fungus_at(d, u) > 0.5 and h > WATER_LEVEL:
		color = Palette.FUNGUS if fungus_at(d, u) > 0.8 else Palette.LILAC
	return color
