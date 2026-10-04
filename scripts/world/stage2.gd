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
	checkpoints = {"": 0.0, "midboss": 1660.0, "boss": 3390.0}
	coax_tiers = {"": 2, "midboss": 2, "boss": 2}
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
	# A sunken container yard on both flanks, stacked two high, and two grounded freighters as cover.
	for d in [3530.0, 3570.0, 3710.0, 3750.0]:
		for u in [-85.0, 85.0]:
			var tint := int(d / 10.0 + u) % 6
			_structure("container", d, u, Vector3(12.0, 2.8, 5.0), -1.3, tint)
			if tint % 2 == 0:
				_structure("container", d, u + 0.4, Vector3(12.0, 2.8, 5.0), 1.5, tint + 1)
	_structure("ship", BAY_D + 26.0, -104.0, Vector3(64.0, 7.0, 16.0), -3.5, 1)
	_structure("ship", BAY_D - 52.0, 108.0, Vector3(54.0, 6.0, 14.0), -3.0, 3)


## Towers keep their inner face where it was and vary in size, so no two neighbours match.
## Local x is across the road and local z along it.
func _building(d: float, u: float, variant: int) -> void:
	var h := hash(Vector2(d, u))
	var across := 18.0 + float((h >> 4) % 9)
	var along := 20.0 + float(h % 5)
	var centre := signf(u) * (absf(u) - 9.0 + across * 0.5) if u != 0.0 else u
	_structure("city_building", d, centre, Vector3(across, 18.0 + variant * 3.6 + float((h >> 9) % 4), along), height(d, centre), variant + int((h >> 13) % 8))


func _in_any_arena(d: float, u: float) -> bool:
	for arena in arenas:
		if Vector2(d - arena.d, u).length() < arena.radius + 8.0:
			return true
	return section_at(d) == Section.BAY


func in_arena(d: float, margin := 0.0) -> bool:
	for arena in arenas:
		if absf(d - arena.d) < arena.radius + margin:
			return true
	return false


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
			var color := Color(Palette.SKY if absf(u + 5.0) < 10.0 or _in_any_arena(d + 10.0, u + 5.0) else Palette.SLATE.lerp(Palette.TEAL, 0.5), 0.85)
			b.tri(a, c, e, color, Vector3.UP)
			b.tri(a, e, f, color, Vector3.UP)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for structure in structures:
		if structure.kind == "city_deck":
			continue
		for rect: Array in CityKit.foam(structure.size):
			var lo: Vector2 = rect[0]
			var hi: Vector2 = rect[1]
			var centre := Course.to_world(structure.d, structure.u, WATER_LEVEL + 0.03)
			var yaw: float = Course.yaw_at(structure.d) + float(structure.yaw)
			var basis := Basis(Vector3.UP, yaw)
			var corners := [Vector3(lo.x, 0, lo.y), Vector3(hi.x, 0, lo.y), Vector3(hi.x, 0, hi.y), Vector3(lo.x, 0, hi.y)]
			var p: Array[Vector3] = []
			for corner: Vector3 in corners:
				p.append(centre + basis * corner)
			b.tri(p[0], p[1], p[2], Palette.CREAM, Vector3.UP)
			b.tri(p[0], p[2], p[3], Palette.CREAM, Vector3.UP)
	# Current streaks: pale slivers drifting along the street, so the flood reads as moving water.
	for i in 3200:
		var d := rng.randf_range(0.0, LENGTH)
		var u := rng.randf_range(-70.0, 70.0)
		if height(d, u) >= WATER_LEVEL - 0.1:
			continue
		var length := rng.randf_range(4.0, 14.0)
		var a := Course.to_world(d, u, WATER_LEVEL + 0.02)
		var c := Course.to_world(d + length, u, WATER_LEVEL + 0.02)
		var side := Course.right(d) * 0.22
		b.tri(a - side, c, a + side, Palette.WHITE, Vector3.UP)
	return b.mesh()


func fog_distance(d: float) -> float:
	var canyon := band(d, 2100.0, 2200.0, 3100.0, 3250.0)
	return lerpf(lerpf(310.0, 390.0, smoothstep(3200.0, 3400.0, d)), 230.0, canyon)


func music(section: int) -> String:
	match section:
		Section.BAY:
			return ""
		Section.PLAZA:
			return "res://assets/music/stage2_hovercraft.ogg"
		Section.CANYON:
			return "res://assets/music/stage2_canyon.ogg"
	return "res://assets/music/stage2_boulevard.ogg"


func boss_music(phase := 0) -> String:
	return "res://assets/music/stage2_boss.ogg" if phase == 0 else "res://assets/music/stage2_boss_phase2.ogg"


func events(hard: bool) -> Array[Dictionary]:
	var e: Array[Dictionary] = []
	var wave := func(d: float, kind: String, extra: Dictionary) -> void:
		var event := {"d": d, "type": "wave", "kind": kind, "hard_scale": 1.0}
		event.merge(extra)
		e.append(event)

	# Boulevard: time to read the flooded street, then one LOSAT hunter behind the 336 m building.
	e.append({"d": 160.0, "type": "pickup", "id": "heat", "ahead": 30.0})
	wave.call(240.0, "abel", {"u": 25.0, "ahead": 120.0, "drop": "coax"})
	e.append({"d": 520.0, "type": "pickup", "id": "apfsds"})

	# Viaduct: the deck shooters make looking up matter; mines leave a gap down the road.
	wave.call(720.0, "kain", {"u": -42.0, "ahead": 80.0, "height": 30.3})
	wave.call(870.0, "sea_mine", {"count": 2, "u": -12.0, "spacing": 4.0, "ahead": 45.0})
	wave.call(970.0, "rooftop_battery", {"u": 42.0, "ahead": 80.0})
	e.append({"d": 1070.0, "type": "pickup", "id": "atgm"})
	wave.call(1140.0, "hind", {"u": -16.0, "height": 7.0, "ahead": 90.0, "drop": "micro"})
	wave.call(1330.0, "kain", {"u": 10.0, "ahead": 80.0})
	wave.call(1350.0, "adam", {"u": 4.0, "ahead": 35.0, "drop": "heat"})
	e.append({"d": 1390.0, "type": "hold", "at": 1405.0, "timeout": 30.0, "reward": "atgm"})
	e.append({"d": 1480.0, "type": "pickup", "id": "micro", "u": -4.0})

	# Plaza: missiles are an option, not the only supply. Direct rounds bypass its missile defense.
	e.append({"d": 1660.0, "type": "checkpoint", "name": "midboss"})
	e.append({"d": 1680.0, "type": "pickup", "id": "repair", "u": 4.0, "ahead": 25.0})
	e.append({"d": 1720.0, "type": "pickup", "id": "heat", "u": -4.0, "ahead": 20.0})
	e.append({"d": 1750.0, "type": "pickup", "id": "apfsds", "ahead": 15.0})
	e.append({"d": PLAZA_D - 110.0, "type": "midboss", "kind": "hovercraft", "hold": PLAZA_D - 56.0, "music": "res://assets/music/stage2_hovercraft.ogg"})

	# Canyon: paired hunters use opposite buildings, then an Adam screens the gun carrier.
	e.append({"d": 2180.0, "type": "pickup", "id": "era"})
	wave.call(2240.0, "abel", {"count": 2, "formation": "sides", "spacing": 23.0, "ahead": 144.0})
	wave.call(2260.0, "hind", {"u": 16.0, "height": 7.0, "ahead": 85.0})
	wave.call(2440.0, "sea_mine", {"count": 2, "u": 12.0, "spacing": 4.0, "ahead": 45.0})
	# Release 2440-2660, with a round to answer the next pair.
	e.append({"d": 2540.0, "type": "pickup", "id": "apfsds"})
	wave.call(2660.0, "kain", {"u": -8.0, "ahead": 70.0})
	wave.call(2670.0, "adam", {"u": -4.0, "ahead": 40.0})
	wave.call(2710.0, "helicopter", {"u": 16.0, "height": 14.0, "ahead": 90.0, "drop": "airburst"})
	wave.call(2880.0, "abel", {"count": 2, "formation": "sides", "spacing": 23.0, "ahead": 132.0})
	wave.call(2900.0, "hind", {"u": -16.0, "height": 7.0, "ahead": 112.0})
	wave.call(3000.0, "sea_mine", {"count": 2, "u": -12.0, "spacing": 4.0, "ahead": 45.0})
	e.append({"d": 3040.0, "type": "hold", "at": 3055.0, "timeout": 35.0, "reward": "repair"})

	# Bay: a long release to refit, then the all-range fight. Phase two owns its own music.
	e.append({"d": 3260.0, "type": "pickup", "id": "era", "u": -4.0})
	e.append({"d": 3330.0, "type": "pickup", "id": "heat", "u": 4.0})
	e.append({"d": 3390.0, "type": "checkpoint", "name": "boss"})
	e.append({"d": 3450.0, "type": "pickup", "id": "repair", "u": -4.0, "ahead": 20.0})
	e.append({"d": 3490.0, "type": "pickup", "id": "apfsds", "ahead": 15.0})
	e.append({"d": BAY_D - 110.0, "type": "boss", "kind": "landsword", "height": 0.0, "music": "res://assets/music/stage2_boss.ogg"})

	if hard:
		# Pressure from the other deck and an extra flanker, never during an opening or release.
		wave.call(990.0, "rooftop_battery", {"u": -42.0, "ahead": 80.0})
		wave.call(2300.0, "kain", {"u": -10.0, "ahead": 80.0})
		wave.call(2940.0, "helicopter", {"u": 16.0, "height": 14.0, "ahead": 90.0})
	e.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	return e
