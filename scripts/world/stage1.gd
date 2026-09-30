class_name Stage1
extends StageDef
## Stage 1 "Hypha": the village valley, its reservoir, the overpass and the dam. Hand-placed
## encounters by rail distance. Pacing per section: quiet opening, build, peak, then a short
## release before the next section.

enum Section { FARM, VILLAGE, SCHOOL, RESERVOIR, OVERPASS, ARENA }

const SECTION_STARTS := [0.0, 560.0, 1450.0, 1760.0, 2660.0, 3420.0]
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
const RESERVOIR_D := Vector2(1740.0, 2700.0) ## Along the road, as far as the reservoir's surface reaches.
const RESERVOIR_U := Vector2(-135.0, -8.0) ## Across it.

## The road plan: straight before the start (where the debug room sits), through the schoolyard,
## under the crossing highway and into the arena. Every bend keeps its radius above the terrain's
## half width, so the valley never folds over itself.
const PLAN := [
	[650.0, 0.0], [260.0, 60.0], [90.0, 0.0], [360.0, -90.0], [150.0, 0.0], [320.0, 75.0], [430.0, 0.0],
	[400.0, -90.0], [90.0, 0.0], [370.0, 90.0], [180.0, 0.0], [250.0, -45.0], [900.0, 0.0],
]

var _noise := make_noise(7, 0.004)
var _detail := make_noise(11, 0.05)
var _fungus := make_noise(23, 0.018)


func _init() -> void:
	number = 1
	plan = PLAN
	section_starts.assign(SECTION_STARTS)
	checkpoints = {"": 0.0, "midboss": MIDBOSS_D - 110.0, "boss": SECTION_STARTS[Section.ARENA] - 40.0}
	coax_tiers = {"midboss": 2, "boss": 3}
	midboss_d = MIDBOSS_D
	boss_music = "res://assets/music/boss.ogg"
	arena_center_d = ARENA_CENTER_D
	arena_radius = ARENA_RADIUS
	sky_top = Color("8f9fe0")
	sky_horizon = Color("f7d6c4")
	sky_ground = Color("c3a6e8")
	ambient = Color("b8a8d8")
	fog_color = Color("f3d9d0")
	sun_color = Color("fff0dc")
	sun_energy = 1.05


func music(section: int) -> String:
	match section:
		Section.ARENA:
			return ""
		Section.SCHOOL, Section.RESERVOIR, Section.OVERPASS:
			return "res://assets/music/stage_b.ogg"
	return "res://assets/music/stage_a.ogg"


func water_surface(c: Vector2) -> float:
	if c.x >= RESERVOIR_D.x and c.x <= RESERVOIR_D.y and c.y >= RESERVOIR_U.x and c.y <= RESERVOIR_U.y and is_water(c.x, c.y):
		return WATER_LEVEL
	return -INF


func is_water(d: float, u: float) -> bool:
	return height(d, u) < WATER_LEVEL


## The reservoir surface: a strip following the bend over the basin, reaching under its banks.
func water_meshes() -> Array[ArrayMesh]:
	var vertices := PackedVector3Array()
	var d := RESERVOIR_D.x
	while d < RESERVOIR_D.y:
		for step in [0.0, 20.0]:
			var a := Course.to_world(d + step, RESERVOIR_U.y)
			var b := Course.to_world(d + step, RESERVOIR_U.x)
			vertices.append(a)
			vertices.append(b)
		d += 20.0
	var triangles := PackedVector3Array()
	for i in range(0, vertices.size(), 4):
		triangles.append_array([vertices[i], vertices[i + 1], vertices[i + 3], vertices[i], vertices[i + 3], vertices[i + 2]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = triangles
	var normals := PackedVector3Array()
	normals.resize(triangles.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return [mesh]


func water_level(_index: int) -> float:
	return WATER_LEVEL


## Half width of the flat valley floor around the road.
func valley_half_width(d: float) -> float:
	var width := 34.0
	width = lerpf(width, 70.0, band(d, 1500.0, 1580.0, 1690.0, 1760.0))
	width = lerpf(width, ARENA_RADIUS + 25.0, band(d, 3390.0, 3450.0, 3700.0, 3800.0))
	return width


func deck_blend(d: float) -> float:
	return band(d, RAMP_UP.x, RAMP_UP.y, RAMP_DOWN.x, RAMP_DOWN.y)


func height(d: float, u: float) -> float:
	var au := absf(u)
	var half := valley_half_width(d)
	var h := _noise.get_noise_2d(d, u) * 1.2
	# Hills and mountains rise beyond the valley floor.
	var rise := smoothstep(half, half + 70.0, au)
	h += rise * (22.0 + 26.0 * (_noise.get_noise_2d(d * 0.6 + 500.0, u * 0.6) + 0.5)) + rise * rise * 18.0
	h += _detail.get_noise_2d(d, u) * 0.35 * (0.3 + rise)
	var section := section_at(d)
	# Rice paddies: flat terraces stepping down toward the road, with raised dikes between plots.
	var paddy := band(d, -100.0, 20.0, 1500.0, 1560.0) * smoothstep(7.0, 9.0, au) * (1.0 - rise)
	if paddy > 0.0:
		var plot := _paddy_plot(d, u)
		var terrace := floorf(au / 18.0) * 0.45 - 0.5
		h = lerpf(h, terrace + plot.y * 0.25, paddy)
	# The road is a slightly raised, flat strip.
	var road := 1.0 - smoothstep(4.0, 6.0, au)
	h = lerpf(h, 0.15 + _noise.get_noise_2d(d, 0.0) * 0.8, road * (1.0 - rise))
	# Reservoir: water on the left of the road, behind a low embankment.
	if section == Section.RESERVOIR or d > section_starts[Section.RESERVOIR] - 60.0:
		var lake := band(d, 1760.0, 1840.0, 2560.0, 2680.0)
		var basin := smoothstep(-16.0, -34.0, u) * (1.0 - smoothstep(-95.0, -125.0, u))
		h = lerpf(h, -6.0, lake * basin)
	# Highway embankment.
	var deck := deck_blend(d)
	if deck > 0.0:
		var on_deck := 1.0 - smoothstep(15.0, 22.0, au)
		h = lerpf(h, DECK_HEIGHT * deck, on_deck)
	# The schoolyard and boss arena are flat.
	var yard := band(d, SCHOOL_YARD.x - 30.0, SCHOOL_YARD.x, SCHOOL_YARD.y, SCHOOL_YARD.y + 30.0) * (1.0 - smoothstep(50.0, 62.0, au))
	h = lerpf(h, 0.3, yard)
	var arena := band(d, 3400.0, 3440.0, DAM_D + 2.0, DAM_D + 6.0) * (1.0 - smoothstep(ARENA_RADIUS, ARENA_RADIUS + 15.0, au))
	h = lerpf(h, 0.2 + _noise.get_noise_2d(d, u) * 0.6, arena)
	# Behind the dam the reservoir bed is a bank as high as the wall's back face (see Dam), which
	# stands on the flat arena floor in front of it.
	h = lerpf(h, maxf(h, 27.0), smoothstep(DAM_D + 4.0, DAM_D + 7.0, d))
	return h


## Returns (plot id hash, dike amount 0..1) for paddy plots of about 18 × 24 m.
func _paddy_plot(d: float, u: float) -> Vector2:
	var cell := Vector2(floorf(d / 24.0), floorf(u / 18.0))
	var local := Vector2(fposmod(d, 24.0), fposmod(u, 18.0))
	var edge := minf(minf(local.x, 24.0 - local.x), minf(local.y, 18.0 - local.y))
	return Vector2(fposmod(sin(cell.dot(Vector2(12.9898, 78.233))) * 43758.5453, 1.0), 1.0 - smoothstep(0.4, 1.0, edge))


## How overgrown the ground is (0..1). Fungus thickens as the stage goes on.
func fungus_at(d: float, u: float) -> float:
	var progress := clampf(d / 3400.0, 0.0, 1.0)
	var n := _fungus.get_noise_2d(d, u) * 0.5 + 0.5
	return smoothstep(0.8 - progress * 0.14, 0.88 - progress * 0.14, n)


func ground_color(d: float, u: float, h: float, slope: float) -> Color:
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
	elif band(d, SCHOOL_YARD.x - 20.0, SCHOOL_YARD.x, SCHOOL_YARD.y, SCHOOL_YARD.y + 20.0) > 0.5 and au < 55.0:
		color = Palette.OCHRE if au > 3.0 else Palette.PEACH
	elif band(d, -100.0, 20.0, 1500.0, 1560.0) > 0.5 and au > 8.0 and rise < 0.2:
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


func events(hard: bool) -> Array[Dictionary]:
	var e: Array[Dictionary] = []
	var wave := func(d: float, kind: String, extra: Dictionary) -> void:
		var event := {"d": d, "type": "wave", "kind": kind}
		event.merge(extra)
		e.append(event)

	# Farm road (quiet -> build): FPVs alone while the CIWS learns its job, then the first ground contact.
	wave.call(90.0, "fpv", {"count": 2, "formation": "line", "height": 9.0, "spacing": 7.0, "hover": 26.0})
	wave.call(170.0, "fpv", {"count": 4, "formation": "v", "height": 8.0, "spacing": 5.0})
	wave.call(250.0, "fpv", {"count": 5, "formation": "ring", "height": 10.0, "spacing": 8.0, "stagger": 0.25})
	wave.call(330.0, "crawler", {"count": 4, "formation": "sides", "spacing": 16.0, "ahead": 70.0})
	# Release 330-460: nothing spawns.
	wave.call(460.0, "fpv", {"count": 3, "formation": "behind", "height": 6.0, "spacing": 6.0, "hover": 14.0, "approach": 1.2})
	wave.call(510.0, "ugv", {"count": 2, "u": 5.0, "spacing": 8.0, "ahead": 100.0})
	wave.call(540.0, "ugv", {"count": 2, "formation": "behind", "spacing": 10.0})

	# Village, a ground war. Intro: UGVs in the lanes. Build: a lone bombing run, walkers, a crawler flank.
	# Release 945-1085. Peak 1085-1195: helicopter, UGV column, missile walkers, crawlers, FPVs from behind.
	# Release to the mid-boss, broken only by a quad duel.
	wave.call(600.0, "ugv", {"count": 4, "formation": "sides", "spacing": 8.0, "ahead": 95.0})
	wave.call(650.0, "crawler", {"count": 4, "formation": "scatter", "spacing": 18.0, "ahead": 60.0, "u": 0.0})
	wave.call(705.0, "fpv", {"count": 4, "formation": "line", "height": 9.0, "spacing": 6.0})
	wave.call(770.0, "uav", {"count": 2, "formation": "line", "spacing": 10.0, "props": {"attack": "bomb"}})
	wave.call(840.0, "walker", {"count": 4, "formation": "behind", "spacing": 9.0})
	wave.call(890.0, "spitter", {"count": 4, "formation": "sides", "spacing": 15.0, "ahead": 80.0})
	wave.call(945.0, "crawler", {"count": 6, "formation": "flank", "u": -1.0, "spacing": 6.0, "ahead": 10.0})
	wave.call(1085.0, "helicopter", {"count": 1, "height": 13.0, "ahead": 110.0, "u": -10.0})
	wave.call(1100.0, "ugv", {"count": 3, "formation": "column", "spacing": 14.0, "ahead": 100.0, "u": 4.0, "drop": "coax"})
	wave.call(1125.0, "walker", {"count": 3, "formation": "line", "spacing": 7.0, "ahead": 85.0, "props": {"weapon": "missile"}})
	wave.call(1150.0, "crawler", {"count": 7, "formation": "scatter", "spacing": 16.0, "ahead": 50.0})
	wave.call(1175.0, "fpv", {"count": 4, "formation": "behind", "height": 6.0, "spacing": 5.0, "hover": 14.0, "approach": 1.0})
	wave.call(1195.0, "ugv", {"count": 2, "formation": "sides", "spacing": 10.0, "ahead": 90.0, "props": {"weapon": "atgm"}})
	wave.call(1300.0, "quad", {"count": 1, "u": 0.0, "ahead": 100.0, "props": {"weapon": "mortar"}})

	# Branch school: the mid-boss holds the rail.
	e.append({"d": 1470.0, "type": "checkpoint", "name": "midboss"})
	wave.call(1500.0, "crawler", {"count": 6, "formation": "scatter", "spacing": 20.0, "ahead": 60.0})
	e.append({"d": MIDBOSS_D - 110.0, "type": "midboss", "kind": "colossus", "hold": MIDBOSS_D - 56.0})

	# Reservoir, an air war over the water (ground units stay a minority). Intro: drones rise out of the reeds.
	# Build: UAV passes, a helicopter, spitters on the bank. Release 2050-2185. Peak 2185-2400 with the storm:
	# bombers from behind, helicopters, a reed ring, ATGM UGVs. Release to the overpass, only the supply UGV.
	wave.call(1830.0, "fpv", {"count": 4, "formation": "scatter", "height": 1.5, "spacing": 3.0, "u": -17.0, "ahead": 60.0})
	wave.call(1885.0, "fpv", {"count": 4, "formation": "scatter", "height": 1.5, "spacing": 3.0, "u": -17.0, "ahead": 60.0})
	wave.call(1940.0, "uav", {"count": 4, "formation": "v", "spacing": 10.0, "props": {"attack": "strafe"}})
	wave.call(1995.0, "helicopter", {"count": 1, "formation": "line", "height": 14.0, "spacing": 24.0, "ahead": 105.0})
	wave.call(2050.0, "spitter", {"count": 5, "formation": "line", "spacing": 4.0, "u": 20.0, "ahead": 85.0})
	e.append({"d": 2185.0, "type": "storm", "duration": 22.0})
	wave.call(2185.0, "uav", {"count": 3, "formation": "line", "spacing": 12.0, "props": {"attack": "bomb", "from_behind": true}})
	wave.call(2215.0, "fpv", {"count": 10, "formation": "ring", "height": 1.5, "spacing": 4.0, "u": -17.0, "stagger": 0.18})
	wave.call(2245.0, "helicopter", {"count": 2, "formation": "sides", "height": 14.0, "spacing": 22.0, "ahead": 65.0})
	wave.call(2270.0, "ugv", {"count": 2, "formation": "line", "spacing": 8.0, "u": 4.0, "ahead": 100.0, "props": {"weapon": "atgm"}})
	wave.call(2300.0, "uav", {"count": 3, "formation": "line", "spacing": 10.0, "props": {"attack": "bomb", "from_behind": true}})
	wave.call(2340.0, "fpv", {"count": 5, "formation": "v", "height": 8.0, "spacing": 5.0})
	wave.call(2370.0, "uav", {"count": 3, "formation": "v", "spacing": 10.0, "props": {"attack": "strafe"}})
	wave.call(2560.0, "ugv", {"count": 1, "u": 0.0, "ahead": 90.0, "props": {"weapon": "supply"}, "drop": "repair"})


	# Overpass, a ground gauntlet. Intro: an ambush under the bridge. Build: up the ramp. Peak 3065-3240 on the
	# deck. Release from there to the boss.
	wave.call(2740.0, "ugv", {"count": 5, "formation": "behind", "spacing": 9.0})
	wave.call(2775.0, "crawler", {"count": 5, "formation": "flank", "u": 1.0, "spacing": 6.0, "ahead": 15.0})
	wave.call(2830.0, "ugv", {"count": 7, "formation": "column", "spacing": 12.0, "ahead": 100.0})
	wave.call(2890.0, "walker", {"count": 5, "formation": "behind", "spacing": 8.0})
	wave.call(2945.0, "crawler", {"count": 4, "formation": "scatter", "spacing": 10.0, "ahead": 70.0})
	wave.call(3065.0, "quad", {"count": 2, "formation": "sides", "spacing": 7.0, "ahead": 100.0})
	wave.call(3090.0, "walker", {"count": 4, "formation": "line", "spacing": 6.0, "ahead": 80.0, "props": {"weapon": "missile"}})
	wave.call(3115.0, "helicopter", {"count": 3, "formation": "v", "height": 15.0, "spacing": 20.0, "ahead": 105.0})
	wave.call(3145.0, "ugv", {"count": 5, "formation": "column", "spacing": 10.0, "ahead": 100.0})
	wave.call(3175.0, "fpv", {"count": 8, "formation": "ring", "height": 9.0, "spacing": 9.0, "stagger": 0.15})
	wave.call(3205.0, "uav", {"count": 3, "formation": "line", "spacing": 10.0, "props": {"attack": "bomb", "from_behind": true}})
	wave.call(3235.0, "walker", {"count": 3, "formation": "line", "spacing": 6.0, "ahead": 80.0, "props": {"weapon": "missile"}})
	e.append({"d": 3395.0, "type": "checkpoint", "name": "boss"})
	e.append({"d": 3465.0, "type": "boss", "kind": "gunship"})

	if hard:
		# Hard adds flankers to the build beats, never inside a release, so the peaks keep their breathing room.
		wave.call(60.0, "fpv", {"count": 2, "formation": "sides", "height": 7.0, "spacing": 10.0})
		wave.call(915.0, "uav", {"count": 2, "formation": "line", "spacing": 10.0, "props": {"attack": "strafe"}})
		wave.call(1800.0, "ugv", {"count": 2, "formation": "sides", "spacing": 9.0, "ahead": 100.0, "props": {"weapon": "atgm"}})
		wave.call(2665.0, "fpv", {"count": 3, "formation": "behind", "height": 6.0, "spacing": 5.0, "hover": 14.0, "approach": 1.0})
		wave.call(2990.0, "fpv", {"count": 4, "formation": "ring", "height": 9.0, "spacing": 9.0})
	return e
