class_name Stage2
extends StageDef
## A drowned downtown: the street threads under expressways, opens onto a plaza, then reaches the bay.

enum Section { BOULEVARD, VIADUCT, PLAZA, CANYON, BAY }

const SECTION_STARTS := [0.0, 700.0, 1650.0, 2150.0, 3200.0]
const LENGTH := 4000.0
const WATER_LEVEL := 0.3
const PLAZA_D := 1900.0
const PLAZA_RADIUS := 72.0
const BAY_D := 3650.0
const BAY_RADIUS := 128.0
const PLAN := [[1100.0, 0.0], [500.0, 35.0], [500.0, -35.0], [600.0, 0.0], [500.0, -40.0], [500.0, 40.0], [800.0, 0.0]]


func _init() -> void:
	number = 2
	plan = PLAN
	section_starts.assign(SECTION_STARTS)
	start_rws = true
	water_slows = true
	coax_tiers = {"": 2}
	midboss_d = PLAZA_D
	arena_center_d = BAY_D
	arena_radius = BAY_RADIUS
	arenas = [{"d": PLAZA_D, "radius": PLAZA_RADIUS}, {"d": BAY_D, "radius": BAY_RADIUS}]
	sky_top = Palette.SLATE
	sky_horizon = Palette.SKY
	sky_ground = Palette.STONE
	ambient = Palette.SKY
	ambient_energy = 0.7
	fog_color = Palette.SKY
	fog_begin = 65.0
	fog_end = 310.0
	sun_color = Palette.CREAM
	sun_rotation = Vector3(-18.0, 145.0, 0.0)
	sun_energy = 0.65
	# Broad sidewalks keep the opening readable; the canyon leaves a narrow driving corridor.
	for d in range(60, 3200, 48):
		if d > 1770 and d < 2030:
			continue
		for side in [-1.0, 1.0]:
			var setback := 25.0 if d < 700 else 30.0 if d < 1650 else 23.0
			_building(float(d), side * setback, (d / 48 + int(side > 0.0)) % 6)
	for arena in arenas:
		for i in 24:
			var angle := TAU * i / 24.0
			if absf(cos(angle)) < 0.24:
				continue # The street enters and leaves through gaps in the perimeter.
			_building(arena.d + sin(angle) * (arena.radius + 17.0), cos(angle) * (arena.radius + 17.0), i % 6)
	for d in [800.0, 1050.0, 1330.0, 1560.0]:
		_structure("city_deck", d, 0.0, Vector3(150.0, 1.8, 14.0), 20.0 + float(int(d) % 3) * 3.0)
		for u in [-58.0, -30.0, 30.0, 58.0]:
			_structure("city_pier", d, u, Vector3(3.2, 21.5 + float(int(d) % 3) * 3.0, 4.0), -1.5)
	for d in range(780, 1580, 48):
		for u in [-42.0, 42.0]:
			_structure("city_deck", float(d), u, Vector3(13.0, 1.8, 48.0), 27.0)
			_structure("city_pier", float(d), u, Vector3(3.2, 28.5, 4.0), -1.5)
	# Broken spans lie in the harbour, with space to circle either end.
	_structure("city_deck", 3590.0, -45.0, Vector3(58.0, 1.8, 14.0), 0.8)
	_structure("city_pier", 3580.0, -65.0, Vector3(4.0, 6.0, 4.0), -1.5)
	for d in [3530.0, 3570.0, 3710.0, 3750.0]:
		for u in [-85.0, 85.0]:
			_structure("container", d, u, Vector3(12.0, 2.8, 5.0), -1.3)


func _building(d: float, u: float, variant: int) -> void:
	_structure("city_building", d, u, Vector3(18.0, 18.0 + variant * 3.6, 24.0), height(d, u), variant)


func _structure(kind: String, d: float, u: float, size: Vector3, y: float, variant := 0) -> void:
	structures.append({"kind": kind, "d": d, "u": u, "size": size, "y": y, "yaw": 0.0, "variant": variant})


func valley_half_width(d: float) -> float:
	var width := 46.0 if section_at(d) != Section.CANYON else 32.0
	for arena in arenas:
		width = lerpf(width, arena.radius + 20.0, band(d, arena.d - arena.radius - 60.0, arena.d - arena.radius, arena.d + arena.radius, arena.d + arena.radius + 60.0))
	return width


func height(d: float, u: float) -> float:
	var lane := 1.0 - smoothstep(9.0, 15.0, absf(u))
	var h := lerpf(-1.5, 0.05, lane)
	for arena in arenas:
		var radius := Vector2(d - arena.d, u).length()
		h = lerpf(h, -0.15, 1.0 - smoothstep(arena.radius - 8.0, arena.radius, radius))
	return h + smoothstep(valley_half_width(d), valley_half_width(d) + 15.0, absf(u)) * 4.0


func ground_color(d: float, u: float, _h: float, _slope: float) -> Color:
	if absf(u) < 10.0:
		if absf(absf(u) - 3.5) < 0.3 and fposmod(d, 14.0) < 7.0:
			return Palette.CREAM
		return Palette.SLATE
	if section_at(d) == Section.PLAZA:
		return Palette.MIST if int(Vector2(d - PLAZA_D, u).length() / 8.0) % 2 else Palette.STONE
	return Palette.TEAL if section_at(d) == Section.BAY else Palette.CONCRETE


func water_surface(c: Vector2) -> float:
	return WATER_LEVEL if c.x >= -100.0 and c.x <= LENGTH and absf(c.y) <= 185.0 and height(c.x, c.y) < WATER_LEVEL else -INF


func water_mesh() -> ArrayMesh:
	var b := LowPoly.new()
	for d in range(-100, int(LENGTH), 20):
		for u in range(-180, 180, 10):
			if height(d + 10.0, u + 5.0) >= WATER_LEVEL:
				continue
			var a := Course.to_world(float(d), float(u), WATER_LEVEL)
			var c := Course.to_world(d + 20.0, float(u), WATER_LEVEL)
			var e := Course.to_world(d + 20.0, u + 10.0, WATER_LEVEL)
			var f := Course.to_world(float(d), u + 10.0, WATER_LEVEL)
			var color := Palette.SKY if absf(u + 5.0) < 10.0 or section_at(float(d)) == Section.BAY else Palette.TEAL
			b.tri(a, c, e, color, Vector3.UP)
			b.tri(a, e, f, color, Vector3.UP)
	return b.mesh()


func fog_distance(d: float) -> float:
	var canyon := band(d, 2100.0, 2200.0, 3100.0, 3250.0)
	return lerpf(lerpf(310.0, 390.0, smoothstep(3200.0, 3400.0, d)), 230.0, canyon)


func music(section: int) -> String:
	return "res://assets/music/stage_b.ogg" if section in [Section.VIADUCT, Section.CANYON] else "res://assets/music/stage_a.ogg"
