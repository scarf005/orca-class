class_name Stage2
extends StageDef
## A drowned downtown: the street threads under expressways, opens onto a plaza, then reaches the bay.

enum Section { BOULEVARD, VIADUCT, PLAZA, CANYON, BAY }

const SECTION_STARTS := [0.0, 700.0, 1650.0, 2150.0, 3200.0]
const LENGTH := 4000.0
const DECK_TOP := 6.25 ## Expressway deck hunters stand this high above the drowned road under it.
const WATER_LEVEL := 0.3
const PLAZA_D := 1900.0
const PLAZA_RADIUS := 72.0
const BAY_D := 3650.0
const BAY_RADIUS := 128.0
const PLAN := [[1100.0, 0.0], [500.0, 35.0], [500.0, -35.0], [600.0, 0.0], [500.0, -40.0], [500.0, 40.0], [800.0, 0.0]]
const SPLITS: Array[Dictionary] = [
	{"d": 300.0, "u": 0.0, "size": 8.0, "kind": "tower"},
	{"d": 580.0, "u": 8.0, "size": 8.0, "kind": "tower"},
	{"d": 900.0, "u": -8.0, "size": 8.0, "kind": "tower"},
	{"d": 1450.0, "u": 0.0, "size": 8.0, "kind": "span"},
	{"d": 1720.0, "u": 0.0, "size": 8.0, "kind": "tower"},
	{"d": 2080.0, "u": 5.0, "size": 6.0, "kind": "tower"},
	{"d": 2400.0, "u": -5.0, "size": 6.0, "kind": "toppled"},
	{"d": 2750.0, "u": 4.0, "size": 6.0, "kind": "tower"},
]

var frontage_gaps: Array[Dictionary] = []


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
	sky_top = Palette.PERIWINKLE.darkened(0.35)
	sky_horizon = Palette.BLUSH.lerp(Palette.SKY, 0.45)
	sky_ground = Palette.STONE
	ambient = Palette.SKY
	ambient_energy = 0.7
	fog_color = Palette.BLUSH.lerp(Palette.SKY, 0.55)
	fog_begin = 65.0
	fog_end = 310.0
	sun_color = Palette.PEACH.lerp(Palette.CREAM, 0.5)
	sun_rotation = Vector3(-18.0, 145.0, 0.0)
	sun_energy = 0.65
	_generate_walls()
	_generate_splitters()
	_generate_expressway()
	# Hand-placed landmarks break up the procedural frontage without narrowing the street.
	# Boulevard bus terminal facade gives the opening hunter a readable peek from cover.
	_structure("city_building", 336.0, 45.0, Vector3(22.0, 30.0, 24.0), WATER_LEVEL - 4.5, 6)
	_structure("city_terminal", 430.0, -47.0, Vector3(28.0, 12.0, 34.0), WATER_LEVEL - 4.5, 7)
	_structure("city_department", 560.0, 47.0, Vector3(26.0, 28.0, 24.0), WATER_LEVEL - 4.5, 9)
	_structure("city_building", 1760.0, 48.0, Vector3(26.0, 30.0, 24.0), WATER_LEVEL - 4.5, 9)
	_structure("city_clock", PLAZA_D, 80.0, Vector3(14.0, 30.0, 14.0), WATER_LEVEL - 4.5, 14)
	_structure("city_building", 2200.0, -38.0, Vector3(24.0, 28.0, 22.0), WATER_LEVEL - 4.5, 11)
	_structure("city_leaning", 2500.0, 38.0, Vector3(18.0, 26.0, 22.0), WATER_LEVEL - 4.5, 15, 0.0, Vector3(0.0, 0.0, 0.16))
	# A bay-facing rim remains outside the boss arena; the yard and ships fill the water beyond it.
	_structure("city_building", PLAZA_D - PLAZA_RADIUS - 20.0, -54.0, Vector3(24.0, 32.0, 22.0), WATER_LEVEL - 4.5, 12)
	# Container yard, freighters and cranes stay in the harbour.
	for d in [3530.0, 3570.0, 3710.0, 3750.0]:
		for u in [-85.0, 85.0]:
			var tint := int(d / 10.0 + u) % 6
			_structure("container", d, u, Vector3(12.0, 2.8, 5.0), WATER_LEVEL - 1.3, tint)
			if tint % 2 == 0:
				_structure("container", d, u + 0.4, Vector3(12.0, 2.8, 5.0), WATER_LEVEL + 1.5, tint + 1)
	_structure("ship", BAY_D + 26.0, -104.0, Vector3(64.0, 7.0, 16.0), WATER_LEVEL - 3.5, 1)
	_structure("ship", BAY_D - 52.0, 108.0, Vector3(54.0, 6.0, 14.0), WATER_LEVEL - 3.0, 3)


func _generate_walls() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261004
	var ranges := [[0.0, 700.0], [700.0, 1650.0], [1650.0, 2150.0], [2150.0, 3200.0], [3200.0, LENGTH]]
	for section_range: Array in ranges:
		for side: float in [-1.0, 1.0]:
			var d: float = float(section_range[0]) + rng.randf_range(0.0, 10.0)
			var along: float = rng.randf_range(16.0, 34.0)
			while d < section_range[1]:
				var across: float = rng.randf_range(18.0, 30.0)
				var h: float = rng.randf_range(18.0, 48.0)
				var setback: float = lateral_limit(d) + 3.0 + rng.randf_range(0.0, 6.0)
				var centre: float = side * (setback + across * 0.5)
				var gap: float = rng.randf_range(0.0, 14.0)
				var next_along: float = rng.randf_range(16.0, 34.0)
				var next_d := d + (along + next_along) * 0.5 + gap
				var within_section := d - along * 0.5 >= float(section_range[0]) and d + along * 0.5 <= float(section_range[1])
				if within_section and not in_arena(d, 10.0 + along * 0.5):
					if not _expressway_occupies(d, along, side):
						_structure("city_building", d, centre, Vector3(across, h, along), WATER_LEVEL - 4.5, _tower_kind(d, rng) + 4 * rng.randi_range(0, 3))
					frontage_gaps.append({"d": d + along + gap * 0.5, "u": side * (setback + across + 8.0), "gap": gap, "side": side})
				d = next_d
				along = next_along


## Each part of town has its own mix of tower kinds (see CityKit.tower): shop signs on the boulevard, apartment
## blocks behind the expressway, glass towers in the canyon.
func _tower_kind(d: float, rng: RandomNumberGenerator) -> int:
	var mix: Array = [[2, 2, 0, 1], [1, 1, 2, 0], [2, 3, 0], [3, 3, 0, 2], [0, 1, 3]][section_at(d)]
	return mix[rng.randi() % mix.size()]


func _expressway_side(d: float) -> float:
	return -1.0 if d < 1120.0 or d >= 1480.0 else 1.0


func _expressway_occupies(d: float, along: float, side: float) -> bool:
	if section_at(d) != Section.VIADUCT or side != _expressway_side(d):
		return false
	for span_d in range(760, 1640, 90):
		var span := 72.0 + float(int(span_d / 90.0) % 3) * 10.0
		if absf(d - float(span_d)) < (along + span) * 0.5:
			return true
	return false


func _generate_splitters() -> void:
	for index in SPLITS.size():
		var split: Dictionary = SPLITS[index]
		var size := float(split.size)
		if split.kind == "toppled":
			_structure("city_toppled", split.d, split.u, Vector3(size, 4.0, 24.0), WATER_LEVEL - 0.1, index + 20)
		else:
			var h := 8.5 if split.kind == "tower" else 2.0 # A sunken block whose roof storey stands 4 m clear: the camera sees over it.
			var base := WATER_LEVEL - 4.5 if split.kind == "tower" else WATER_LEVEL - 0.1
			_structure("city_building" if split.kind == "tower" else "city_deck", split.d, split.u, Vector3(size, h, 14.0), base, index + 20)


func _generate_expressway() -> void:
	var side := -1.0
	for d in range(760, 1640, 90):
		if d == 1120 or d == 1480:
			side *= -1.0
		var span := 72.0 + float(int(d / 90.0) % 3) * 10.0
		var deck_y := WATER_LEVEL + 4.2
		_structure("city_sag_span" if d == 1390 else "city_deck", float(d), side * 40.0, Vector3(6.0, 2.6 if d == 1390 else 1.8, span), deck_y - (0.4 if d == 1390 else 0.0), int(d / 90) % 6)
		for offset: float in [-span * 0.32, span * 0.32]:
			_structure("city_pier", float(d) + offset, side * 40.0, Vector3(3.0, 10.5, 3.0), WATER_LEVEL - 4.5, int(d / 90) % 4)


func in_arena(d: float, margin := 0.0) -> bool:
	for arena in arenas:
		if absf(d - arena.d) < arena.radius + margin:
			return true
	return false


func _structure(kind: String, d: float, u: float, size: Vector3, y: float, variant := 0, yaw := 0.0, tilt := Vector3.ZERO) -> void:
	structures.append({"kind": kind, "d": d, "u": u, "size": size, "y": y, "yaw": yaw, "tilt": tilt, "variant": variant})


func lateral_limit(d: float) -> float:
	for arena in arenas:
		if absf(d - arena.d) <= arena.radius:
			return arena.radius - 6.0
	return 22.0 if section_at(d) == Section.CANYON else 30.0


func split_lane_centres(index: int) -> Vector2:
	var split: Dictionary = SPLITS[index]
	var limit := lateral_limit(float(split.d))
	var left_edge := float(split.u) - float(split.size) * 0.5
	var right_edge := float(split.u) + float(split.size) * 0.5
	return Vector2((-limit + left_edge) * 0.5, (right_edge + limit) * 0.5)


## The camera trails the tank's lane but keeps 6 m inside the wall line at its own distance, so on bends it never
## runs into the towers and has to be pulled in behind the hull.
func camera_u(d: float, u: float) -> float:
	var reach := lateral_limit(d - ChaseCamera.RAIL_BACK) - 6.0
	return clampf(u * 0.75, -reach, reach)


func valley_half_width(d: float) -> float:
	return lateral_limit(d) + 16.0


func height(d: float, u: float) -> float:
	for arena in arenas:
		if Vector2(d - arena.d, u).length() < arena.radius:
			return -0.15
	# Under the expressway the drowned road runs on to the piers, so its hunters can come down to the street.
	var reach := lateral_limit(d) + (14.0 if section_at(d) == Section.VIADUCT and signf(u) == _expressway_side(d) else 0.0)
	return 0.05 if absf(u) <= reach else WATER_LEVEL - 4.5


func ground_color(d: float, u: float, _h: float, _slope: float) -> Color:
	var au := absf(u)
	if section_at(d) == Section.PLAZA and Vector2(d - PLAZA_D, u).length() < PLAZA_RADIUS:
		return Palette.MIST if int(Vector2(d - PLAZA_D, u).length() / 8.0) % 2 else Palette.STONE
	if section_at(d) == Section.BAY:
		return Palette.TEAL
	var limit := lateral_limit(d)
	if au > limit:
		return Palette.MOSS
	# Terrain vertices are metres apart, so painted lines would smear into big triangles: only broad surfaces.
	return Palette.CONCRETE if au > limit - 4.0 else Palette.SLATE


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
			# One sheet of water from wall to wall, a shade darker over the deep lots than over the drowned avenue.
			var shallow := height(d + 10.0, u + 5.0) > WATER_LEVEL - 1.0
			var color := Color(Palette.SKY, 0.82) if shallow else Color(Palette.SKY.darkened(0.22), 0.95)
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
	match section_at(d):
		Section.BOULEVARD:
			return lerpf(280.0, 320.0, smoothstep(0.0, 700.0, d))
		Section.VIADUCT:
			return 340.0
		Section.PLAZA:
			return 300.0
		Section.CANYON:
			return 230.0
		Section.BAY:
			return 360.0
	return fog_end


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

	# All scripted Stage 1 enemies over these ranges, bosses included: 14 / 21 / 9 / 30 / 4.
	# City totals excluding mines/batteries: 11 / 15 / 7 / 23 / 3.
	# Each section builds to a mixed squad, then leaves a supply-only release.
	wave.call(240.0, "abel", {"u": -17.0, "ahead": 85.0, "drop": "coax", "squad": [
		{"kind": "fpv", "count": 2, "height": 5.0, "spacing": 6.0},
		{"kind": "ugv", "count": 1, "u": 8.0, "ahead": 70.0},
		{"kind": "drone_boat", "count": 1, "u": -14.0, "ahead": 60.0}]})
	wave.call(500.0, "kain", {"u": 21.0, "ahead": 85.0, "peak": true, "squad": [
		{"kind": "drone_boat", "count": 3, "spacing": 5.0, "ahead": 65.0},
		{"kind": "ugv", "u": -8.0, "ahead": 80.0, "props": {"weapon": "atgm"}},
		{"kind": "walker", "u": 6.0, "ahead": 75.0}]})

	wave.call(720.0, "kain", {"u": -38.5, "ahead": 65.0, "height": DECK_TOP, "squad": [
		{"kind": "ugv", "count": 2, "spacing": 12.0, "ahead": 75.0},
		{"kind": "fpv", "height": 5.0}]})
	wave.call(840.0, "abel", {"u": -21.0, "ahead": 85.0, "squad": [
		{"kind": "ugv", "u": -16.0, "ahead": 75.0, "props": {"weapon": "atgm"}},
		{"kind": "drone_boat", "u": 10.0, "ahead": 65.0}]})
	wave.call(870.0, "sea_mine", {"count": 2, "u": 12.0, "spacing": 4.0, "ahead": 45.0})
	wave.call(970.0, "rooftop_battery", {"u": -40.0, "ahead": 80.0, "height": DECK_TOP})
	e.append({"d": 1070.0, "type": "pickup", "id": "atgm"})
	wave.call(1140.0, "hind", {"u": 8.0, "height": 5.0, "ahead": 90.0, "drop": "micro", "squad": [
		{"kind": "fpv", "count": 2, "height": 5.0, "spacing": 7.0},
		{"kind": "walker", "u": -8.0, "ahead": 75.0, "props": {"weapon": "missile"}}]})
	wave.call(1370.0, "adam", {"u": 17.0, "ahead": 65.0, "peak": true, "squad": [
		{"kind": "ugv", "u": 8.0, "ahead": 90.0, "props": {"weapon": "atgm"}},
		{"kind": "drone_boat", "count": 2, "spacing": 6.0, "ahead": 70.0}]})
	e.append({"d": 1480.0, "type": "pickup", "id": "micro", "u": -4.0})

	e.append({"d": 1660.0, "type": "checkpoint", "name": "midboss"})
	wave.call(1665.0, "kain", {"u": -17.0, "ahead": 50.0, "squad": [
		{"kind": "ugv", "u": -10.0, "ahead": 70.0},
		{"kind": "drone_boat", "count": 1, "spacing": 6.0, "ahead": 65.0}]})
	e.append({"d": 1750.0, "type": "pickup", "id": "apfsds", "ahead": 15.0})
	e.append({"d": PLAZA_D - 110.0, "type": "midboss", "kind": "hovercraft", "peak": true, "hold": PLAZA_D - 56.0, "music": "res://assets/music/stage2_hovercraft.ogg"})
	wave.call(2050.0, "abel", {"u": 19.0, "ahead": 45.0, "squad": [
		{"kind": "walker", "u": 10.0, "ahead": 75.0},
		{"kind": "drone_boat", "u": -10.0, "ahead": 65.0}]})

	wave.call(2240.0, "hind", {"u": -8.0, "height": 5.0, "ahead": 85.0, "squad": [
		{"kind": "fpv", "count": 2, "height": 5.0, "spacing": 7.0},
		{"kind": "ugv", "count": 2, "spacing": 12.0, "ahead": 75.0, "props": {"weapon": "atgm"}}]})
	wave.call(2340.0, "adam", {"u": -15.0, "ahead": 65.0, "squad": [
		{"kind": "walker", "count": 2, "spacing": 10.0, "ahead": 90.0, "props": {"weapon": "missile"}},
		{"kind": "drone_boat", "count": 3, "spacing": 5.0, "ahead": 70.0}]})
	wave.call(2440.0, "sea_mine", {"count": 2, "u": 12.0, "spacing": 4.0, "ahead": 45.0})
	# Quiet 2440-2690 lets the tank refit before the canyon peak.
	wave.call(2690.0, "kain", {"u": 14.5, "ahead": 85.0, "squad": [
		{"kind": "ugv", "count": 2, "spacing": 12.0, "ahead": 80.0, "props": {"weapon": "atgm"}},
		{"kind": "fpv", "count": 3, "height": 5.0, "spacing": 6.0}]})
	wave.call(2870.0, "abel", {"u": -10.0, "ahead": 100.0, "peak": true, "squad": [
		{"kind": "walker", "count": 2, "spacing": 12.0, "ahead": 80.0, "props": {"weapon": "missile"}},
		{"kind": "drone_boat", "count": 3, "spacing": 5.0, "ahead": 65.0}]})
	e.append({"d": 3040.0, "type": "hold", "at": 3055.0, "timeout": 25.0, "reward": "repair"})

	wave.call(3240.0, "hind", {"u": 8.0, "height": 5.0, "ahead": 85.0, "peak": true, "squad": [{"kind": "drone_boat", "u": -8.0, "ahead": 65.0}]})
	e.append({"d": 3260.0, "type": "pickup", "id": "era", "u": -4.0})
	e.append({"d": 3330.0, "type": "pickup", "id": "heat", "u": 4.0})
	e.append({"d": 3390.0, "type": "checkpoint", "name": "boss"})
	e.append({"d": 3450.0, "type": "pickup", "id": "repair", "u": -4.0, "ahead": 20.0})
	e.append({"d": 3490.0, "type": "pickup", "id": "apfsds", "ahead": 15.0})
	e.append({"d": BAY_D - 110.0, "type": "boss", "kind": "hi_mo", "height": 0.0, "music": "res://assets/music/stage2_boss.ogg"})

	var counters := ["heat", "apfsds", "airburst", "heat", "apfsds", "airburst", "canister", "apfsds"]
	for index in SPLITS.size():
		var split: Dictionary = SPLITS[index]
		var lanes := split_lane_centres(index)
		var rich_left := index % 2 == 0
		for side in 2:
			e.append({"d": split.d - 70.0, "ahead": 70.0, "type": "pickup", "u": lanes[side], "id": counters[index] if (side == 0) == rich_left else ("repair" if index % 3 == 0 else "era")})

	if hard:
		var pressure := {240.0: {"fpv": 2}, 1140.0: {"fpv": 2}, 1665.0: {"drone_boat": 1}}
		# Remixed firing lanes and earlier escorts compress the build, not the releases or elite health.
		for event in e:
			if event.type != "wave" or not event.has("squad"):
				continue
			for member: Dictionary in event.squad:
				member.count = int(member.get("count", 1)) * (3 if event.d == 3240.0 else 2) + int(pressure.get(event.d, {}).get(member.kind, 0))
				member.u = -float(member.get("u", 0.0))
				member.ahead = 50.0 if member.kind == "drone_boat" else 65.0
				if member.kind == "ugv":
					member.props = {"weapon": "atgm"}
		wave.call(990.0, "rooftop_battery", {"u": -40.0, "ahead": 80.0, "height": DECK_TOP})
	e.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	return e
