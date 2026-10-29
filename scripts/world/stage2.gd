class_name Stage2
extends StageDef
## A drowned downtown: the street threads under expressways, opens onto a plaza, then reaches the bay.

enum Section { BOULEVARD, VIADUCT, PLAZA, CANYON, BAY }

const SECTION_STARTS := [0.0, 700.0, 1650.0, 2150.0, 3200.0]
const LENGTH := 4000.0
const DECK_TOP := 6.25 ## Side viaducts and rooftops hunters stand on, this high above the drowned road.
const HORIZON_SHIFT := 20.0 ## Squads from ahead spawn this much farther out and walk in instead of popping up mid-street.
const WATER_LEVEL := 0.3
const HULL_MARGIN := 3.0
const PLAZA_D := 1900.0
const PLAZA_RADIUS := 72.0
const BAY_D := 3650.0
const BAY_RADIUS := 128.0
## The canyon zigzags through two 80 degree bends (right at d 2290, left at d 2500) and the viaduct bows gently.
const PLAN := [[1200.0, 0.0], [450.0, 16.0], [500.0, -16.0], [500.0, 0.0], [140.0, 0.0], [60.0, 80.0], [150.0, 0.0], [60.0, -80.0], [1440.0, 0.0]]
const SPLITS: Array[Dictionary] = [
	{"d": 300.0, "u": 0.0, "size": 8.0, "kind": "tower"},
]

const STREET_HALF := 30.0 ## Half width of the drowned street; the canyon narrows it to CANYON_HALF.
const CANYON_HALF := 22.0
const KERB_HEIGHT := 0.7 ## Pavement shelf above the drowned road on the boulevard and in the canyon.
const KERB_RAMP := 3.0 ## Metres of road it takes to climb onto the shelf (about 0.22 rise/run).
const BAY_KERB := 1.8 ## The quay shelf along the bay approach is this many times higher: the surge passes over it.

## The tank's elevated expressway: an on-ramp, a deck high over the low roofs, a span that has collapsed into a
## flooded gap, the far span's broken end hanging down into it, and the far deck's off-ramp. Heights are over the street.
const DECK_H := 16.0
const DECK_HALF := 12.0 ## The tank's lateral limit on the deck.
const DECK_NARROW := 8.0 ## Height at which the road has narrowed to the deck's width.
const ON_RAMP := Vector2(705.0, 880.0)
const GAP := Vector2(1256.0, 1325.0) ## Where the near deck snaps off, just past the kicker, and where the far deck's edge stands.
const HANG_FOOT := 1288.0 ## Where the far span's hanging end meets the flooded street in the gap.
const FAR_DECK_H := 11.0
const OFF_RAMP := Vector2(1400.0, 1560.0)
const PIT_FLOOR := -1.25 ## The flooded gap under the broken span.

## Launch ramps (see StageDef.ramp_at): the deck's kicker before the gap, and the fallen tower in the canyon. A track
## climbs `height` over `length` metres by `power`, then falls away over `tail`; `half` and `flank` shape its sides.
const RAMPS: Array[Dictionary] = [
	{"d": 1190.0, "u": 0.0, "length": 60.0, "half": 12.5, "flank": 3.0, "height": 4.5, "power": 4.0, "tail": 6.0},
	{"d": 2428.0, "u": -10.0, "length": 49.0, "half": 7.0, "flank": 3.0, "height": 9.0, "power": 1.0, "tail": 10.0},
]
const SURGE_D := 3330.0 ## Middle of the stretch the tidal surge washes over.
const KICKER := 0
const SLAB := 1
const SLAB_SIZE := Vector3(14.0, 52.0, 6.0) ## The tower that falls across the canyon: width, height, thickness.
const SLAB_VARIANT := 3 ## A glass curtain wall.
const TOPPLE_D := 2300.0 ## Where the tower starts to fall.

## The flooded concourse: the street dives into it, a collapsed block roofs it, and it climbs out again.
const CONCOURSE := Vector4(2700.0, 2745.0, 2905.0, 2950.0) ## Dive starts, floor level, floor ends, street level.
const CONCOURSE_FLOOR := -1.45
const ROOF_Y := 6.0 ## Underside of the roof block over the concourse.

## Smooth bumps (h > 0) and hollows (h < 0) added to the road. The weight falls off as a cosine from the flat
## `flat` fraction of the footprint (half-extents rx across, rz along; rx INF spans the whole street) to zero at its
## edge, so slopes stay below h * PI / 2 / ((1 - flat) * extent) and the tank can ride over all of it.
const RELIEF: Array[Dictionary] = [
	# Rubble and collapsed-road ramps. Off-centre ones narrow one side of the street; the canyon mound sits on it.
	{"d": 150.0, "u": -15.0, "rx": 9.0, "rz": 14.0, "h": 1.2},
	{"d": 230.0, "u": 18.0, "rx": 9.0, "rz": 12.0, "h": 1.0},
	{"d": 430.0, "u": 16.0, "rx": 8.0, "rz": 12.0, "h": 1.1},
	{"d": 520.0, "u": -16.0, "rx": 8.0, "rz": 11.0, "h": 1.4},
	{"d": 1630.0, "u": -17.0, "rx": 10.0, "rz": 14.0, "h": 1.4},
	{"d": 1590.0, "u": 15.0, "rx": 9.0, "rz": 12.0, "h": 1.1},
	{"d": 2200.0, "u": 11.0, "rx": 9.0, "rz": 14.0, "h": 1.6},
	{"d": 2620.0, "u": 0.0, "rx": 8.0, "rz": 11.0, "h": 1.2},
	# Wave-washed rubble along the bay approach: the islands a tidal surge runs over without touching the tank.
	{"d": 3290.0, "u": -12.0, "rx": 10.0, "rz": 13.0, "h": 1.5},
	{"d": 3335.0, "u": 10.0, "rx": 10.0, "rz": 13.0, "h": 1.5},
	{"d": 3380.0, "u": -8.0, "rx": 10.0, "rz": 13.0, "h": 1.5},
	{"d": 3425.0, "u": 14.0, "rx": 10.0, "rz": 13.0, "h": 1.5},
	{"d": 3470.0, "u": -14.0, "rx": 10.0, "rz": 13.0, "h": 1.5},
	# Collapsed subway and sinkholes across the whole street; the deck's broken span is the deepest.
	{"d": 620.0, "u": 0.0, "rx": INF, "rz": 22.0, "h": -1.5, "flat": 0.4},
	{"d": 1280.0, "u": 0.0, "rx": INF, "rz": 22.0, "h": PIT_FLOOR, "flat": 0.6},
	{"d": 3000.0, "u": 0.0, "rx": INF, "rz": 22.0, "h": -1.5, "flat": 0.4},
]

const BACKDROP_ROWS := [45.0, 95.0] ## Setback of each backdrop row from the wall line, beyond the front tower row.
const VIADUCT_SETBACK := 70.0 ## Extra setback of the far row beside the viaduct and the ruins, whose near row is left out.
## Frontage per section: the roof-height range of the blocks along the street and the share of lots built. Only the
## boulevard is a continuous canyon of towers; the others are low, patchy or open.
const FRONTAGE := [
	{"h": [18.0, 48.0], "built": 1.0},
	{"h": [5.0, 9.0], "built": 0.6},
	{"h": [14.0, 30.0], "built": 0.45},
	{"h": [14.0, 52.0], "built": 1.0},
	{"h": [6.0, 11.0], "built": 0.9},
]
## The canyon's ruined frontage by side (-1 left, 1 right): [from, to, kind]. A wall is a row of tall gutted towers
## on the outside of a bend, facing the camera as the street turns; ruins and stumps are gutted towers standing to
## different heights, lean a tower tipped on its footing, and open a flooded lot of rubble that shows the skyline.
## It never walls both sides at once, and its inner corners stay open so the bends read.
const CANYON_LOTS := {
	-1.0: [[2150.0, 2230.0, "ruin"], [2230.0, 2290.0, "open"], [2290.0, 2440.0, "wall"], [2440.0, 2490.0, "stump"], [2490.0, 2640.0, "open"], [2640.0, 2700.0, "lean"], [2950.0, 3020.0, "stump"], [3020.0, 3120.0, "open"], [3120.0, 3200.0, "ruin"]],
	1.0: [[2150.0, 2230.0, "stump"], [2230.0, 2430.0, "open"], [2430.0, 2500.0, "ruin"], [2500.0, 2640.0, "wall"], [2640.0, 2700.0, "stump"], [2950.0, 3050.0, "lean"], [3050.0, 3200.0, "open"]],
}
## Towers that came down across the canyon's open lots and lie half drowned: [d, u, yaw].
const FALLEN := [[2330.0, 46.0, 0.5], [2560.0, -44.0, -0.45], [3070.0, -46.0, 0.35]]
## Bends (from, to, inner side) the backdrop skips on the inside, where it would fold over the road.
const BENDS := [[2230.0, 2420.0, 1.0], [2440.0, 2630.0, -1.0]]

var frontage_gaps: Array[Dictionary] = []


func _init() -> void:
	number = 2
	city = true
	street_level = WATER_LEVEL
	standoff = 0.6
	wade_scale = 0.8
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
	_generate_concourse()
	# Hand-placed landmarks break up the procedural frontage without narrowing the street.
	# Boulevard bus terminal facade gives the opening hunter a readable peek from cover.
	_structure("city_building", 336.0, 45.0, Vector3(22.0, 30.0, 24.0), WATER_LEVEL - 4.5, 6)
	_structure("city_terminal", 430.0, -47.0, Vector3(28.0, 12.0, 34.0), WATER_LEVEL - 4.5, 7)
	_structure("city_department", 560.0, 47.0, Vector3(26.0, 28.0, 24.0), WATER_LEVEL - 4.5, 9)
	_structure("city_building", 1760.0, 48.0, Vector3(26.0, 30.0, 24.0), WATER_LEVEL - 4.5, 9)
	_structure("city_clock", PLAZA_D, 80.0, Vector3(14.0, 30.0, 14.0), WATER_LEVEL - 4.5, 14)
	_structure("city_building", 2200.0, -38.0, Vector3(24.0, 28.0, 22.0), WATER_LEVEL - 4.5, 11)
	_structure("city_leaning", 2670.0, 38.0, Vector3(18.0, 26.0, 22.0), WATER_LEVEL - 4.5, 15, 0.0, Vector3(0.0, 0.0, 0.16))
	for fallen: Array in FALLEN:
		_structure("city_toppled", fallen[0], fallen[1], Vector3(12.0, 4.0, 44.0), WATER_LEVEL - 1.8, int(fallen[0]) % 8, fallen[2])
	# The tower that falls across the canyon (see ToppleTower) stands on the rubble at the end of its slab until then.
	_structure("city_building", ramp_lip(SLAB) - SLAB_SIZE.z * 0.5, float(RAMPS[SLAB].u), SLAB_SIZE, float(RAMPS[SLAB].height) + 0.15, SLAB_VARIANT)
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
	for section_index in ranges.size():
		var section_range: Array = ranges[section_index]
		var style: Dictionary = FRONTAGE[section_index]
		for side: float in [-1.0, 1.0]:
			var d: float = float(section_range[0]) + rng.randf_range(0.0, 10.0)
			var along: float = rng.randf_range(16.0, 34.0)
			while d < section_range[1]:
				var across: float = rng.randf_range(18.0, 30.0)
				var h: float = rng.randf_range(style.h[0], style.h[1])
				var setback: float = street_half(d) + 3.0 + rng.randf_range(0.0, 6.0)
				var centre: float = side * (setback + across * 0.5)
				var gap: float = rng.randf_range(0.0, 14.0)
				var next_along: float = rng.randf_range(16.0, 34.0)
				var next_d := d + (along + next_along) * 0.5 + gap
				var built: bool = style.built >= 1.0 or rng.randf() < float(style.built)
				var within_section := d - along * 0.5 >= float(section_range[0]) and d + along * 0.5 <= float(section_range[1])
				if within_section and not in_arena(d, 10.0 + along * 0.5):
					var variant := _tower_kind(d, rng) + 4 * rng.randi_range(0, 3)
					var lot := _lot(section_index, d, side, built)
					if lot != "open" and not _expressway_occupies(d, along, side) and not _roofed(d, along):
						_frontage(lot, d, centre, Vector3(across, h, along), variant)
					frontage_gaps.append({"d": d + along + gap * 0.5, "u": side * (setback + across + 8.0), "gap": gap, "side": side})
				d = next_d
				along = next_along


## Builds the block on a frontage lot (see _lot) at (d, u): `size.y` is the section's drawn roof height.
func _frontage(lot: String, d: float, u: float, size: Vector3, variant: int) -> void:
	match lot:
		"tall":
			_structure("city_building", d, u, size, WATER_LEVEL - 4.5, variant)
		"wall":
			_structure("city_ruin", d, u, Vector3(size.x, maxf(size.y, 30.0), size.z), WATER_LEVEL - 4.5, variant)
		"ruin":
			_structure("city_ruin", d, u, Vector3(size.x, clampf(size.y, 16.0, 30.0), size.z), WATER_LEVEL - 4.5, variant)
		"stump":
			_structure("city_ruin", d, u, Vector3(size.x, clampf(size.y * 0.3, 8.0, 12.0), size.z), WATER_LEVEL - 4.5, variant)
		"lean":
			_structure("city_leaning", d, u, Vector3(size.x, clampf(size.y, 20.0, 34.0), size.z), WATER_LEVEL - 4.5, variant, 0.0, Vector3(0.0, 0.0, signf(u) * 0.2))


## What stands on a lot at `d` on `side`: a tall tower, a ruin, a stump, a leaning tower or nothing (a flooded lot).
func _lot(section_index: int, d: float, side: float, built: bool) -> String:
	if section_index == Section.BAY and side < 0.0:
		return "open" # The bay opens to the water on the left.
	if section_index == Section.CANYON:
		for lot: Array in CANYON_LOTS[side]:
			if d >= lot[0] and d < lot[1]:
				return lot[2]
		return "open"
	return "tall" if built else "open"


## Whether a block at `d` would stand where the concourse's walls and roof block are built (see _generate_concourse).
func _roofed(d: float, along: float) -> bool:
	return d + along * 0.5 > CONCOURSE.y - 10.0 and d - along * 0.5 < CONCOURSE.z + 10.0


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
				var low_rise := section_at(d) in [Section.VIADUCT, Section.CANYON] # Over the low roofs and the ruins the skyline stands back.
				var inner := street_half(d) + float(BACKDROP_ROWS[row]) + (VIADUCT_SETBACK if low_rise else 0.0) + rng.randf_range(0.0, 6.0)
				var warehouse := d >= SECTION_STARTS[Section.BAY]
				var roof := float(rng.randi_range(4, 7) if warehouse else (rng.randi_range(11, 22) if row == 0 else rng.randi_range(22, 35))) * 2.0
				var variant := rng.randi_range(0, 7)
				if d + along * 0.5 <= land_end and not _backdrop_skips(d, side) and not (low_rise and row == 0):
					_backdrop(d, side * (inner + across * 0.5), Vector3(across, roof + 4.5, along), variant)
				d += along + rng.randf_range(0.0, 10.0)
	# The plaza arena stays clear; blocks ring its rim just outside the keep-out radius.
	var ring := PLAZA_RADIUS + 20.0 + 24.0
	for step in 24:
		var angle := TAU * step / 24.0
		_backdrop(PLAZA_D + cos(angle) * ring, sin(angle) * ring, Vector3(30.0, float(rng.randi_range(11, 22)) * 2.0 + 4.5, 30.0), rng.randi_range(0, 7))


## Whether the backdrop leaves `side` of the road at `d` clear: the inside of one of the canyon's bends, where it
## would fold over the road, and the bay approach's left, which opens onto the water.
func _backdrop_skips(d: float, side: float) -> bool:
	return (d >= SECTION_STARTS[Section.BAY] and side < 0.0) or BENDS.any(func(bend: Array) -> bool: return d >= bend[0] and d <= bend[1] and side == bend[2])


## Each part of town has its own mix of tower kinds (see CityKit.tower): shop signs on the boulevard, apartment
## blocks behind the expressway, glass towers in the canyon.
func _tower_kind(d: float, rng: RandomNumberGenerator) -> int:
	var mix: Array = [[2, 2, 0, 1], [1, 1, 2, 0], [2, 3, 0], [3, 3, 0, 2], [0, 1, 3]][section_at(d)]
	return mix[rng.randi() % mix.size()]


func expressway_side(d: float) -> float:
	return -1.0 if d < 1120.0 or d >= 1480.0 else 1.0


func _expressway_occupies(d: float, along: float, side: float) -> bool:
	if section_at(d) != Section.VIADUCT or side != expressway_side(d):
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


## The flooded concourse: concrete walls and a collapsed block over the street, and a colonnade along each wall.
func _generate_concourse() -> void:
	var length := CONCOURSE.z - CONCOURSE.y + 20.0
	var centre := (CONCOURSE.y + CONCOURSE.z) * 0.5
	var wall := street_half(centre) + 3.0
	for side: float in [-1.0, 1.0]:
		_structure("city_deck", centre, side * (wall + 4.0), Vector3(8.0, ROOF_Y + 6.0, length), -6.0, 2)
	_structure("city_building", centre, 0.0, Vector3((wall + 8.0) * 2.0, 16.0, length), ROOF_Y, 1)
	var d := CONCOURSE.y + 12.0
	while d < CONCOURSE.z - 6.0:
		for side: float in [-1.0, 1.0]:
			_structure("city_pier", d, side * (wall - 1.5), Vector3(2.4, ROOF_Y + 2.0, 2.4), -2.0, 1)
		d += 24.0


## Pushes a wave and its squad from ahead out to the haze; pursuers from behind and units breaking cover close by
## keep their slot. A unit on the expressway deck stays short of the last span on its side, before the deck changes
## sides at d=1120.
func _to_horizon(event: Dictionary, d: float) -> void:
	event.ahead = event.get("ahead", 90.0) # 90 m is the director's default slot, which would pop the unit up mid-street.
	var shift := 0.0 if event.get("close", false) or event.get("formation", "") in ["behind", "flank"] else HORIZON_SHIFT
	if is_equal_approx(float(event.get("height", 0.0)), DECK_TOP):
		shift = clampf(1060.0 - d - float(event.ahead), 0.0, shift)
	event.ahead += shift
	for member: Dictionary in event.get("squad", []):
		_to_horizon(member, d)


## Half width of the street itself: the canyon narrows it, and the bay approach widens it back.
func street_half(d: float) -> float:
	return lerpf(lerpf(STREET_HALF, CANYON_HALF, smoothstep(2120.0, 2170.0, d)), STREET_HALF, smoothstep(3160.0, 3220.0, d))


## Height of the elevated road over the street at `d` (see DECK_H): its on-ramp, the deck, the span that collapsed
## and the far span's end, which hangs from its deck down into the gap like a ramp.
func deck_level(d: float) -> float:
	var near := DECK_H * smoothstep(ON_RAMP.x, ON_RAMP.y, d) * (1.0 - smoothstep(GAP.x, GAP.x + 2.0, d))
	var far := FAR_DECK_H * clampf((d - HANG_FOOT) / (GAP.y - HANG_FOOT), 0.0, 1.0) * (1.0 - smoothstep(OFF_RAMP.x, OFF_RAMP.y, d))
	return near + far


## The tank keeps to the deck's width once it is up on the elevated road, and has the whole street below it. The limit
## closes in no faster than the deck's edge follows it, so the hull's edge never hangs over the drop.
func lateral_limit(d: float) -> float:
	for arena in arenas:
		if absf(d - arena.d) <= arena.radius:
			return arena.radius - 6.0
	return lerpf(street_half(d), DECK_HALF, smoothstep(0.0, DECK_NARROW, deck_level(d)))


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
	return street_half(d) + 16.0


func height(d: float, u: float) -> float:
	for arena in arenas:
		# The hull may roam the whole strip the limit allows, so the floor covers it, not just the drawn circle.
		if Vector2(d - arena.d, u).length() < arena.radius or (absf(d - arena.d) <= arena.radius + 2.0 * HULL_MARGIN and absf(u) <= arena.radius - 6.0 + HULL_MARGIN):
			return -0.15
	# Under the expressway the drowned road runs on to the piers, so its hunters can come down to the street.
	# The floor runs 3 m past the street's edge, fore and aft, so the track samples at the kerb never hang over the drop.
	var reach := maxf(street_half(d - HULL_MARGIN), street_half(d + HULL_MARGIN)) + HULL_MARGIN + (14.0 if section_at(d) == Section.VIADUCT and signf(u) == expressway_side(d) else 0.0)
	if absf(u) > reach:
		return WATER_LEVEL - 4.5
	var h := 0.05 + _kerb(d, absf(u)) + _relief(d, u) + _deck(d, absf(u)) + CONCOURSE_FLOOR * _dive(d)
	for index in RAMPS.size():
		h += _ramp_height(index, d, u)
	return h


## The pavement shelf rises along the boulevard, the canyon and the bay quay, and fades out where its stretch ends.
func _kerb(d: float, au: float) -> float:
	var weight := (1.0 - smoothstep(660.0, 700.0, d)) + smoothstep(2150.0, 2190.0, d) * (1.0 - smoothstep(3460.0, 3520.0, d)) * (1.0 - _dive(d))
	var edge := street_half(d) - 4.0
	var rise := lerpf(1.0, BAY_KERB, smoothstep(3180.0, 3260.0, d)) # The quay shelf is higher, and so its ramp longer.
	return KERB_HEIGHT * weight * rise * clampf((au - edge + KERB_RAMP * rise) / (KERB_RAMP * rise), 0.0, 1.0)


## The elevated road: full height across the deck, then a short fall to the street beyond its edge.
func _deck(d: float, au: float) -> float:
	var edge := maxf(lateral_limit(d - HULL_MARGIN), lateral_limit(d + HULL_MARGIN)) + 2.5 # Wide enough for the hull's track samples.
	return deck_level(d) * (1.0 - smoothstep(edge, edge + 5.0, au))


## 0 on the street, 1 on the concourse's floor: the street dives in and climbs out again.
func _dive(d: float) -> float:
	return band(d, CONCOURSE.x, CONCOURSE.y, CONCOURSE.z, CONCOURSE.w)


## The height launch ramp `index` adds at (d, u): a track that climbs along d to a lip and falls away behind it.
func _ramp_height(index: int, d: float, u: float) -> float:
	var ramp: Dictionary = RAMPS[index]
	var s := d - float(ramp.d)
	if s < 0.0 or s > float(ramp.length) + float(ramp.tail):
		return 0.0
	var across := 1.0 - smoothstep(float(ramp.half), float(ramp.half) + float(ramp.flank), absf(u - float(ramp.u)))
	var along := pow(clampf(s / float(ramp.length), 0.0, 1.0), float(ramp.power)) * (1.0 - smoothstep(0.0, float(ramp.tail), s - float(ramp.length)))
	return float(ramp.height) * along * across


func ramp_at(d: float, u: float) -> float:
	for ramp in RAMPS:
		var s := d - float(ramp.d)
		if s >= 0.0 and s <= float(ramp.length) and absf(u - float(ramp.u)) < float(ramp.half):
			return s / float(ramp.length)
	return -1.0


## Rail distance of launch ramp `index`'s lip.
static func ramp_lip(index: int) -> float:
	return float(RAMPS[index].d) + float(RAMPS[index].length)


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
	if d >= BAY_D - BAY_RADIUS - 8.0:
		return Palette.TEAL
	var ramp := ramp_at(d, u)
	if ramp >= 0.0:
		if d < SECTION_STARTS[Section.PLAZA]:
			return Palette.BUTTER if int(ramp * float(RAMPS[KICKER].length) / 6.0) % 2 == 0 else Palette.SLATE # Hazard stripes up the kicker.
		return Palette.SKY.darkened(0.25) # The fallen tower's glass.
	var limit := lateral_limit(d)
	if d > GAP.x and d < GAP.y + 1.0 and deck_level(d) > 0.4 and au <= limit + 6.0:
		return Palette.ASH if (int(d / 4.0) + int(u / 4.0)) % 3 == 0 else Palette.STONE.darkened(0.2) # The fallen span's broken underside.
	if deck_level(d) > 0.8 and au <= limit + 6.0:
		# The elevated road: dark asphalt between concrete parapets, and a bare concrete wall past its edge.
		if au > limit + 1.2:
			return Palette.CONCRETE.darkened(0.15)
		return Palette.CONCRETE if au > limit - 1.5 else Palette.SLATE.lightened(0.12)
	if _dive(d) > 0.3:
		return Palette.INK.lerp(Palette.SLATE, 0.45)
	var street := street_half(d)
	if au > street:
		return Palette.MOSS
	# Terrain vertices are metres apart, so painted lines would smear into big triangles: only broad surfaces.
	if au > street - 4.0:
		return Palette.CONCRETE
	if h > WATER_LEVEL:
		return Palette.ASH if (int(d / 3.0) + int(u / 3.0)) % 2 == 0 else Palette.STONE
	return Palette.SLATE.darkened(0.35) if h < -0.5 else Palette.SLATE


func water_surface(c: Vector2) -> float:
	return WATER_LEVEL if c.x >= -100.0 and c.x <= LENGTH and absf(c.y) <= 185.0 and height(c.x, c.y) < WATER_LEVEL else -INF


func water_mesh() -> ArrayMesh:
	var b := LowPoly.new()
	for d in range(-100, int(LENGTH), 10):
		for u in range(-180, 180, 10):
			var depth := height(d + 5.0, u + 5.0)
			if minf(depth, minf(height(d, u), minf(height(d + 10.0, u), minf(height(d, u + 10.0), height(d + 10.0, u + 10.0))))) >= WATER_LEVEL:
				continue
			var a := Course.to_world(float(d), float(u), WATER_LEVEL)
			var c := Course.to_world(d + 10.0, float(u), WATER_LEVEL)
			var e := Course.to_world(d + 10.0, u + 10.0, WATER_LEVEL)
			var f := Course.to_world(float(d), u + 10.0, WATER_LEVEL)
			# One sheet of water from wall to wall, darker where it is deeper: drowned avenue, sinkholes, deep lots.
			var shade := 0.0 if depth > WATER_LEVEL - 0.5 else (0.5 if depth > WATER_LEVEL - 1.0 else 1.0)
			var tint := water_tint(d + 5.0)
			var color := Color(tint, 0.82).lerp(Color(tint.darkened(0.4), 0.97), shade)
			b.tri(a, c, e, color, Vector3.UP)
			b.tri(a, e, f, color, Vector3.UP)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for structure in structures:
		if structure.kind == "city_deck" or structure.y >= ROOF_Y:
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
	for i in 7000:
		var d := rng.randf_range(0.0, LENGTH)
		var u := rng.randf_range(-45.0, 45.0)
		if height(d, u) >= WATER_LEVEL - 0.1:
			continue
		var length := rng.randf_range(4.0, 14.0)
		var a := Course.to_world(d, u, WATER_LEVEL + 0.02)
		var c := Course.to_world(d + length, u, WATER_LEVEL + 0.02)
		var side := Course.right(d) * 0.22
		b.tri(a - side, c, a + side, Palette.WHITE, Vector3.UP)
	return b.mesh()


## Each part of town has its own haze, blended over the first 120 m of the section: dawn blush on the boulevard,
## lilac shade under the expressway, bright cream on the plaza, a deep periwinkle canyon, teal over the bay.
func fog_tint(d: float) -> Color:
	return _section_blend([fog_color, fog_color.lerp(Palette.LILAC, 0.4).darkened(0.08), fog_color.lerp(Palette.CREAM, 0.5), fog_color.lerp(Palette.PERIWINKLE, 0.5).darkened(0.1), fog_color.lerp(Palette.TEAL, 0.45)], d).darkened(0.6 * _dive(d))


## The flood's own colour per section, so the water that fills every frame says where the tank is.
func water_tint(d: float) -> Color:
	return _section_blend([Palette.SKY, Palette.PERIWINKLE, Palette.SAGE.lerp(Palette.BUTTER, 0.3), Palette.LILAC.lerp(Palette.INK, 0.45), Palette.MINT.lerp(Palette.SKY, 0.3)], d).darkened(0.5 * _dive(d))


func _section_blend(colors: Array, d: float) -> Color:
	var section := section_at(d)
	return (colors[maxi(section - 1, 0)] as Color).lerp(colors[section], smoothstep(SECTION_STARTS[section], SECTION_STARTS[section] + 120.0, d))


func fog_distance(d: float) -> float:
	return lerpf(_section_fog_distance(d), 110.0, _dive(d))


func _section_fog_distance(d: float) -> float:
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

	# Few hunters, each deadly, in beats: every stretch opens light, builds to a peak where hunters overlap, and
	# releases before the next. Boats run up behind the tank through the flood and mines surface close by.
	# Boulevard: a lone boat, then the torpedo gunboat alone, then Abel, a mortar barge and a second gunboat at once.
	wave.call(30.0, "drone_boat", {"ahead": 120.0}) # Contact within seconds: a lone boat crosses the horizon before the first hunter.
	wave.call(240.0, "torpedo_boat", {"u": -17.0, "ahead": 70.0, "drop": "coax", "squad": [
		{"kind": "sea_mine", "u": 6.0, "ahead": 50.0}]})
	wave.call(330.0, "drone_boat", {"count": 3, "formation": "behind", "spacing": 8.0})
	wave.call(400.0, "drone_boat", {"count": 3, "formation": "v", "u": 12.0, "spacing": 6.0, "ahead": 70.0})
	wave.call(440.0, "abel", {"u": 20.0, "ahead": 70.0, "peak": true, "squad": [
		{"kind": "drone_boat", "u": -6.0, "ahead": 55.0}]})
	wave.call(480.0, "mortar", {"u": -22.0, "ahead": 80.0, "props": {"naval": true}})
	wave.call(520.0, "torpedo_boat", {"u": 14.0, "ahead": 75.0, "squad": [
		{"kind": "sea_mine", "u": -4.0, "ahead": 35.0, "close": true}]})

	# The viaduct is a ground war: rooftop batteries and a hunter on the side viaduct shoot at the tank on its deck,
	# UAVs pass over it, and the first Hind rises beside it with Abel just before the leap. Adam waits at the foot
	# of the off-ramp and boats chase the tank back down into the flood.
	wave.call(700.0, "rooftop_battery", {"u": -40.0, "ahead": 180.0, "height": DECK_TOP}) # On the side deck past the 886-899 m gap between its spans.
	wave.call(800.0, "uav", {"count": 2, "formation": "v", "spacing": 7.0, "ahead": 70.0})
	wave.call(890.0, "kain", {"u": -38.5, "ahead": 65.0, "height": DECK_TOP})
	wave.call(960.0, "uav", {"count": 2, "spacing": 9.0, "ahead": 80.0})
	wave.call(1000.0, "rooftop_battery", {"u": -40.0, "ahead": 45.0, "height": DECK_TOP})
	wave.call(1040.0, "hind", {"u": 8.0, "height": 5.0, "ahead": 70.0, "peak": true})
	e.append({"d": 1070.0, "type": "pickup", "id": "atgm"})
	wave.call(1090.0, "abel", {"u": -26.0, "ahead": 70.0, "drop": "micro"})
	wave.call(1430.0, "adam", {"u": 17.0, "ahead": 60.0, "squad": [
		{"kind": "drone_boat", "u": 10.0, "ahead": 60.0}]})
	wave.call(1480.0, "drone_boat", {"count": 3, "formation": "behind", "spacing": 8.0})
	e.append({"d": 1490.0, "type": "pickup", "id": "micro", "u": -4.0})

	e.append({"d": 1660.0, "type": "checkpoint", "name": "midboss"})
	e.append({"d": 1750.0, "type": "pickup", "id": "micro", "ahead": 15.0}) # Overlapping salvos are what exhaust the hovercraft's laser.
	e.append({"d": PLAZA_D - 110.0, "type": "midboss", "kind": "hovercraft", "ahead": 60.0, "peak": true, "hold": PLAZA_D - 56.0, "music": "res://assets/music/stage2_hovercraft.ogg"})
	wave.call(2060.0, "mortar", {"u": 19.0, "ahead": 45.0, "props": {"naval": true}, "squad": [
		{"kind": "drone_boat", "u": 10.0, "ahead": 60.0}]})

	# The canyon is the heaviest beat: a gunboat opens it, boats chase the tank round the first bend as the tower
	# comes down, mines surface by the fallen slab, and past the second bend Adam, Kain and the second Hind fight
	# together. Mines bob up in the dark concourse and a mortar barge waits at its mouth.
	wave.call(2180.0, "torpedo_boat", {"u": -8.0, "ahead": 70.0, "squad": [
		{"kind": "sea_mine", "u": 8.0, "ahead": 60.0}]})
	wave.call(2260.0, "drone_boat", {"count": 3, "formation": "v", "spacing": 6.0, "ahead": 70.0})
	wave.call(2340.0, "drone_boat", {"count": 3, "formation": "behind", "spacing": 8.0})
	wave.call(2380.0, "sea_mine", {"count": 2, "u": 8.0, "spacing": 8.0, "ahead": 35.0, "close": true})
	wave.call(2470.0, "adam", {"u": -15.0, "ahead": 60.0, "peak": true, "squad": [
		{"kind": "drone_boat", "u": 6.0, "ahead": 70.0}]})
	wave.call(2520.0, "kain", {"u": 14.5, "ahead": 75.0, "squad": [
		{"kind": "sea_mine", "ahead": 70.0}]})
	wave.call(2550.0, "hind", {"u": -6.0, "height": 5.0, "ahead": 70.0})
	wave.call(2600.0, "drone_boat", {"count": 3, "formation": "behind", "spacing": 8.0})
	wave.call(2760.0, "sea_mine", {"count": 2, "u": -6.0, "spacing": 10.0, "ahead": 35.0, "close": true})
	wave.call(2860.0, "drone_boat", {"count": 3, "spacing": 6.0, "ahead": 60.0})
	wave.call(2990.0, "mortar", {"u": -10.0, "ahead": 80.0, "props": {"naval": true}, "squad": [
		{"kind": "drone_boat", "count": 2, "spacing": 5.0, "ahead": 60.0}]})
	e.append({"d": 3100.0, "type": "hold", "at": 3115.0, "timeout": 25.0, "reward": "repair"})
	# The tower across the canyon comes down as the tank rounds the first bend, and has landed before a cruising tank
	# reaches the slab; the surge crosses the bay approach.
	e.append({"d": TOPPLE_D, "type": "topple"})
	e.append({"d": SURGE_D - 95.0, "type": "surge", "d_center": SURGE_D})

	wave.call(3240.0, "torpedo_boat", {"u": 8.0, "ahead": 85.0, "peak": true})
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
		var pressure := {440.0: {"drone_boat": 1}, 2180.0: {"sea_mine": 1}}
		# Remixed firing lanes and earlier escorts compress the build, not the releases or elite health.
		for event in e:
			if event.type != "wave" or not event.has("squad"):
				continue
			for member: Dictionary in event.squad:
				member.count = int(member.get("count", 1)) * 2 + int(pressure.get(event.d, {}).get(member.kind, 0))
				member.u = -float(member.get("u", 0.0))
				member.ahead = 50.0 if member.kind == "drone_boat" else 65.0
		wave.call(720.0, "rooftop_battery", {"u": -40.0, "ahead": 180.0, "height": DECK_TOP})
	for event in e:
		if event.type == "wave":
			_to_horizon(event, event.d)
	e.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	return e
