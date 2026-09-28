class_name Course
## Stage 1 geography. The course runs toward -Z; `d` is distance along it and `u` is the lateral
## offset from the road center, so every world point maps to exactly one (d, u).

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

## Road center x at control distances; interpolated with Catmull-Rom.
const CENTER_POINTS: Array[Vector2] = [
	Vector2(-200, 0), Vector2(0, 0), Vector2(300, 12), Vector2(600, -14), Vector2(900, -6), Vector2(1200, 18),
	Vector2(1450, 8), Vector2(1700, 0), Vector2(2000, -24), Vector2(2300, -10), Vector2(2650, 14), Vector2(3000, 4),
	Vector2(3350, 0), Vector2(3700, 0), Vector2(4000, 0),
]

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


static func center_x(d: float) -> float:
	var i := 1
	while i < CENTER_POINTS.size() - 3 and d > CENTER_POINTS[i + 1].x:
		i += 1
	var p0 := CENTER_POINTS[i - 1]
	var p1 := CENTER_POINTS[i]
	var p2 := CENTER_POINTS[i + 1]
	var p3 := CENTER_POINTS[i + 2]
	var t := clampf((d - p1.x) / (p2.x - p1.x), 0.0, 1.0)
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (2.0 * p1.y + (p2.y - p0.y) * t + (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2 + (3.0 * p1.y - p0.y - 3.0 * p2.y + p3.y) * t3)


## Unit forward vector of the road at distance d.
static func forward(d: float) -> Vector3:
	var slope := (center_x(d + 2.0) - center_x(d - 2.0)) / 4.0
	return Vector3(slope, 0.0, -1.0).normalized()


static func to_world(d: float, u: float, y := 0.0) -> Vector3:
	return Vector3(center_x(d) + u, y, -d)


static func ground_at(d: float, u: float) -> Vector3:
	return Vector3(center_x(d) + u, height(d, u), -d)


static func to_course(p: Vector3) -> Vector2:
	var d := -p.z
	return Vector2(d, p.x - center_x(d))


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
		var basin := smoothstep(-16.0, -34.0, u) * (1.0 - smoothstep(-110.0, -150.0, u))
		h = lerpf(h, -6.0, lake * basin)
	# Highway embankment.
	var deck := deck_blend(d)
	if deck > 0.0:
		var on_deck := 1.0 - smoothstep(15.0, 22.0, au)
		h = lerpf(h, DECK_HEIGHT * deck, on_deck)
	# The schoolyard and boss arena are flat.
	var yard := _band(d, SCHOOL_YARD.x - 30.0, SCHOOL_YARD.x, SCHOOL_YARD.y, SCHOOL_YARD.y + 30.0) * (1.0 - smoothstep(50.0, 62.0, au))
	h = lerpf(h, 0.3, yard)
	var arena := _band(d, 3400.0, 3440.0, DAM_D - 25.0, DAM_D - 10.0) * (1.0 - smoothstep(ARENA_RADIUS, ARENA_RADIUS + 15.0, au))
	h = lerpf(h, 0.2 + _noise.get_noise_2d(d, u) * 0.6, arena)
	# Behind the dam the valley is full to its crest.
	h = lerpf(h, maxf(h, 31.0), smoothstep(DAM_D - 16.0, DAM_D - 6.0, d))
	return h


## Returns (plot id hash, dike amount 0..1) for paddy plots of about 18 × 24 m.
static func _paddy_plot(d: float, u: float) -> Vector2:
	var cell := Vector2(floorf(d / 24.0), floorf(u / 18.0))
	var local := Vector2(fposmod(d, 24.0), fposmod(u, 18.0))
	var edge := minf(minf(local.x, 24.0 - local.x), minf(local.y, 18.0 - local.y))
	return Vector2(fposmod(sin(cell.dot(Vector2(12.9898, 78.233))) * 43758.5453, 1.0), 1.0 - smoothstep(0.4, 1.0, edge))


## 0 before a, ramps to 1 over [a, b], holds, then ramps back to 0 over [c, e].
static func _band(x: float, a: float, b: float, c: float, e: float) -> float:
	return smoothstep(a, b, x) * (1.0 - smoothstep(c, e, x))


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
	if h < WATER_LEVEL + 0.4:
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
