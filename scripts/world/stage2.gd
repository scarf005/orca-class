class_name Stage2
extends StageDef
## A drowned downtown: the street threads under expressways, opens onto a plaza, then reaches the bay.

enum Section { BOULEVARD, VIADUCT, PLAZA, CANYON, BAY }

const SECTION_STARTS := [0.0, 700.0, 1650.0, 2150.0, 3200.0]
const LENGTH := 4000.0
const DECK_TOP := 6.25 ## Expressway deck hunters stand this high above the drowned road under it.
const HORIZON_SHIFT := 120.0 ## Squads spawn this much farther out, in the haze, and walk in instead of popping up mid-street.
const WATER_LEVEL := 0.3
const PLAZA_D := 1900.0
const PLAZA_RADIUS := 72.0
const BAY_D := 3650.0
const BAY_RADIUS := 128.0
const PLAN := [[1100.0, 0.0], [500.0, 35.0], [500.0, -35.0], [600.0, 0.0], [500.0, -40.0], [500.0, 40.0], [800.0, 0.0]]
const SPLITS: Array[Dictionary] = [
	{"d": 300.0, "u": 0.0, "size": 8.0, "kind": "tower"},
]

const KERB_HEIGHT := 0.7 ## Pavement shelf above the drowned road on the boulevard and in the canyon.
const KERB_RAMP := 3.0 ## Metres of road it takes to climb onto the shelf (about 0.22 rise/run).
## Smooth bumps (h > 0) and hollows (h < 0) added to the road. The weight falls off as a cosine from the flat
## `flat` fraction of the footprint (half-extents rx across, rz along; rx INF spans the whole street) to zero at its
## edge, so slopes stay below h * PI / 2 / ((1 - flat) * extent) and the tank can ride over all of it.
const RELIEF: Array[Dictionary] = [
	# Rubble and collapsed-road ramps. Off-centre ones narrow one side of the street; the two canyon mounds sit on it.
	{"d": 150.0, "u": -15.0, "rx": 9.0, "rz": 14.0, "h": 1.2},
	{"d": 230.0, "u": 18.0, "rx": 9.0, "rz": 12.0, "h": 1.0},
	{"d": 430.0, "u": 16.0, "rx": 8.0, "rz": 12.0, "h": 1.1},
	{"d": 520.0, "u": -16.0, "rx": 8.0, "rz": 11.0, "h": 1.4},
	{"d": 790.0, "u": 17.0, "rx": 10.0, "rz": 15.0, "h": 1.3},
	{"d": 960.0, "u": -18.0, "rx": 12.0, "rz": 13.0, "h": 1.2},
	{"d": 1050.0, "u": 16.0, "rx": 9.0, "rz": 12.0, "h": 1.0},
	{"d": 1420.0, "u": -17.0, "rx": 10.0, "rz": 14.0, "h": 1.4},
	{"d": 1590.0, "u": 15.0, "rx": 9.0, "rz": 12.0, "h": 1.1},
	{"d": 2600.0, "u": 0.0, "rx": 8.0, "rz": 11.0, "h": 1.2},
	{"d": 2950.0, "u": -2.0, "rx": 8.0, "rz": 10.0, "h": 1.2},
	# Collapsed subway and sinkholes across the whole street.
	{"d": 620.0, "u": 0.0, "rx": INF, "rz": 22.0, "h": -1.5, "flat": 0.4},
	{"d": 1260.0, "u": 0.0, "rx": INF, "rz": 22.0, "h": -1.5, "flat": 0.4},
	{"d": 2430.0, "u": 0.0, "rx": INF, "rz": 22.0, "h": -1.5, "flat": 0.4},
	{"d": 3000.0, "u": 0.0, "rx": INF, "rz": 22.0, "h": -1.5, "flat": 0.4},
]

const BACKDROP_ROWS := [45.0, 95.0] ## Setback of each backdrop row from the wall line, beyond the front tower row.

var frontage_gaps: Array[Dictionary] = []
## Non-colliding skyline blocks behind the front towers: {"d", "u", "size", "variant"}; size.y includes the sunken base.
var backdrop: Array[Dictionary] = []


func _init() -> void:
	number = 2
	standoff = 1.4
	plan = PLAN
	section_starts.assign(SECTION_STARTS)
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
	_generate_backdrop()


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


## Two rows of lower, plainer blocks behind the frontage so the street never ends in a void. They climb with
## distance, ring the plaza rim, and stop on the land side of the bay where low warehouses stand instead.
func _generate_backdrop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261008
	var land_end := BAY_D - BAY_RADIUS - 2.0
	for row in BACKDROP_ROWS.size():
		for side: float in [-1.0, 1.0]:
			var d := rng.randf_range(0.0, 20.0)
			while d < land_end:
				var along := float(rng.randi_range(0, 2)) * 6.0 + 28.0
				var across := float(rng.randi_range(0, 2)) * 6.0 + 24.0
				var base := 22.0 if section_at(d) == Section.CANYON else 30.0
				var inner := base + float(BACKDROP_ROWS[row]) + rng.randf_range(0.0, 6.0)
				var warehouse := d >= SECTION_STARTS[Section.BAY]
				var roof := float(rng.randi_range(4, 7) if warehouse else (rng.randi_range(11, 22) if row == 0 else rng.randi_range(22, 35))) * 2.0
				var variant := rng.randi_range(0, 7)
				if d + along * 0.5 <= land_end:
					_backdrop(d, side * (inner + across * 0.5), Vector3(across, roof + 4.5, along), variant)
				d += along + rng.randf_range(0.0, 10.0)
	# The plaza arena stays clear; blocks ring its rim just outside the keep-out radius.
	var ring := PLAZA_RADIUS + 20.0 + 24.0
	for step in 24:
		var angle := TAU * step / 24.0
		_backdrop(PLAZA_D + cos(angle) * ring, sin(angle) * ring, Vector3(30.0, float(rng.randi_range(11, 22)) * 2.0 + 4.5, 30.0), rng.randi_range(0, 7))


## Adds a backdrop block unless it would touch the street, an arena's rim, a front structure or an earlier block.
func _backdrop(d: float, u: float, size: Vector3, variant: int) -> void:
	var rect := Rect2(d - size.z * 0.5, u - size.x * 0.5, size.z, size.x)
	for arena in arenas:
		var near := Vector2(clampf(arena.d, rect.position.x, rect.end.x), clampf(0.0, rect.position.y, rect.end.y))
		if near.distance_to(Vector2(arena.d, 0.0)) < arena.radius + 20.0:
			return
	if _backdrop_clear(rect):
		backdrop.append({"d": d, "u": u, "size": size, "variant": variant})


## Whether a (d, u) footprint overlaps neither the street, a front structure, nor another backdrop block.
func _backdrop_clear(rect: Rect2) -> bool:
	if absf(rect.get_center().y) - rect.size.y * 0.5 < lateral_limit(rect.get_center().x) + 30.0:
		return false
	for structure in structures:
		var other := Rect2(structure.d - structure.size.z * 0.5, structure.u - structure.size.x * 0.5, structure.size.z, structure.size.x)
		if rect.grow(4.0).intersects(other):
			return false
	for block in backdrop:
		if rect.intersects(Rect2(block.d - block.size.z * 0.5, block.u - block.size.x * 0.5, block.size.z, block.size.x)):
			return false
	return true


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


## Pushes a wave and its squad out to the haze. A unit on the expressway deck stays short of the last span on its side, before the deck changes sides at d=1120.
func _to_horizon(event: Dictionary, d: float) -> void:
	if event.kind == "fpv" and not event.has("ahead"):
		event.ahead = 90.0 # The director's default slot, which would pop the drone up mid-street.
	if event.has("ahead"):
		var shift := HORIZON_SHIFT
		if is_equal_approx(float(event.get("height", 0.0)), DECK_TOP):
			shift = clampf(1060.0 - d - float(event.ahead), 0.0, shift)
		event.ahead += shift
	for member: Dictionary in event.get("squad", []):
		_to_horizon(member, d)


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


## An invisible median eases out to the lane centres before the tower, then rejoins the street.
## Remapping the remaining lane width preserves steering without snapping at the building face.
func fork_u(from_d: float, d: float, u: float) -> float:
	var split: Dictionary = SPLITS[0]
	var before := _fork_width(from_d)
	var after := _fork_width(d)
	if before == 0.0 and after == 0.0:
		return u
	var side := -1.0 if u < float(split.u) else 1.0
	var limit := lateral_limit(float(split.d))
	var offset := maxf(absf(u - float(split.u)) - before, 0.0)
	return float(split.u) + side * (after + offset * (limit - after) / (limit - before))


func _fork_width(d: float) -> float:
	var distance := absf(d - float(SPLITS[0].d))
	return split_lane_centres(0).y * (1.0 - smoothstep(12.0, 100.0, distance))


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
	if absf(u) > reach:
		return WATER_LEVEL - 4.5
	return 0.05 + _kerb(d, absf(u)) + _relief(d, u)


## The pavement shelf rises along the boulevard and canyon walls and fades out where the section ends.
func _kerb(d: float, au: float) -> float:
	var weight := (1.0 - smoothstep(660.0, 700.0, d)) + smoothstep(2150.0, 2190.0, d) * (1.0 - smoothstep(3160.0, 3200.0, d))
	var edge := lateral_limit(d) - 4.0
	return KERB_HEIGHT * weight * clampf((au - edge + KERB_RAMP) / KERB_RAMP, 0.0, 1.0)


func _relief(d: float, u: float) -> float:
	var total := 0.0
	for feature in RELIEF:
		var r := Vector2((d - feature.d) / feature.rz, (u - feature.u) / feature.rx).length()
		if r < 1.0:
			var flat: float = feature.get("flat", 0.0)
			total += feature.h * 0.5 * (1.0 + cos(PI * clampf((r - flat) / (1.0 - flat), 0.0, 1.0)))
	return total


func ground_color(d: float, u: float, h: float, _slope: float) -> Color:
	var au := absf(u)
	if section_at(d) == Section.PLAZA and Vector2(d - PLAZA_D, u).length() < PLAZA_RADIUS:
		return Palette.MIST if int(Vector2(d - PLAZA_D, u).length() / 8.0) % 2 else Palette.STONE
	if section_at(d) == Section.BAY:
		return Palette.TEAL
	var limit := lateral_limit(d)
	if au > limit:
		return Palette.MOSS
	# Terrain vertices are metres apart, so painted lines would smear into big triangles: only broad surfaces.
	if au > limit - 4.0:
		return Palette.CONCRETE
	if h > WATER_LEVEL:
		return Palette.ASH if (int(d / 3.0) + int(u / 3.0)) % 2 == 0 else Palette.STONE
	return Palette.SLATE.darkened(0.35) if h < -0.5 else Palette.SLATE


func water_surface(c: Vector2) -> float:
	return WATER_LEVEL if c.x >= -100.0 and c.x <= LENGTH and absf(c.y) <= 185.0 and height(c.x, c.y) < WATER_LEVEL else -INF


func water_mesh() -> ArrayMesh:
	var b := LowPoly.new()
	for d in range(-100, int(LENGTH), 20):
		for u in range(-180, 180, 10):
			var depth := height(d + 10.0, u + 5.0)
			if minf(depth, minf(height(d, u), minf(height(d + 20.0, u), minf(height(d, u + 10.0), height(d + 20.0, u + 10.0))))) >= WATER_LEVEL:
				continue
			var a := Course.to_world(float(d), float(u), WATER_LEVEL)
			var c := Course.to_world(d + 20.0, float(u), WATER_LEVEL)
			var e := Course.to_world(d + 20.0, u + 10.0, WATER_LEVEL)
			var f := Course.to_world(float(d), u + 10.0, WATER_LEVEL)
			# One sheet of water from wall to wall, darker where it is deeper: drowned avenue, sinkholes, deep lots.
			var shade := 0.0 if depth > WATER_LEVEL - 0.5 else (0.5 if depth > WATER_LEVEL - 1.0 else 1.0)
			var color := Color(Palette.SKY, 0.82).lerp(Color(Palette.SKY.darkened(0.4), 0.97), shade)
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
	# Foam lines where the water drops into a sinkhole, so its edge reads from the road.
	for feature in RELIEF:
		if feature.h >= 0.0:
			continue
		for edge: float in [-0.78, 0.78]:
			var d: float = feature.d + edge * feature.rz
			var reach := lateral_limit(d)
			b.tri(Course.to_world(d - 0.7, -reach, WATER_LEVEL + 0.03), Course.to_world(d + 0.7, -reach, WATER_LEVEL + 0.03), Course.to_world(d + 0.7, reach, WATER_LEVEL + 0.03), Palette.CREAM, Vector3.UP)
			b.tri(Course.to_world(d - 0.7, -reach, WATER_LEVEL + 0.03), Course.to_world(d + 0.7, reach, WATER_LEVEL + 0.03), Course.to_world(d - 0.7, reach, WATER_LEVEL + 0.03), Palette.CREAM, Vector3.UP)
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
	wave.call(900.0, "rooftop_battery", {"u": -40.0, "ahead": 150.0, "height": DECK_TOP})
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
	e.append({"d": 1750.0, "type": "pickup", "id": "dragon", "ahead": 15.0})
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
	e.append({"d": 3330.0, "type": "pickup", "id": "atgm", "u": 4.0})
	e.append({"d": 3390.0, "type": "checkpoint", "name": "boss"})
	e.append({"d": 3450.0, "type": "pickup", "id": "repair", "u": -4.0, "ahead": 20.0})
	e.append({"d": 3490.0, "type": "pickup", "id": "dragon", "ahead": 15.0})
	e.append({"d": BAY_D - 110.0, "type": "boss", "kind": "hi_mo", "height": 0.0, "music": "res://assets/music/stage2_boss.ogg"})

	var counters := Armament.OFFERED.map(func(round: Armament.Round) -> String: return Armament.ROUND_IDS[round])
	for index in SPLITS.size():
		var split: Dictionary = SPLITS[index]
		var lanes := split_lane_centres(index)
		var rich_left := index % 2 == 0
		for side in 2:
			e.append({"d": split.d - 70.0, "ahead": 70.0, "type": "pickup", "u": lanes[side], "id": counters[index % counters.size()] if (side == 0) == rich_left else ("repair" if index % 3 == 0 else "era")})

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
		wave.call(920.0, "rooftop_battery", {"u": -40.0, "ahead": 150.0, "height": DECK_TOP})
	for event in e:
		if event.type == "wave":
			_to_horizon(event, event.d)
	e.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	return e
