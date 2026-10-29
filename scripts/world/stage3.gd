class_name Stage3
extends StageDef
## A downtown the desert has swallowed. The outskirts are an open dune sea whose crests throw the tank into the air;
## the avenue is the one corridor of half-buried towers and ends in a tight bend; a terraforming borer's pit opens
## beyond it, its sand bulging and bursting along the approach; the street then dives under the sand into a subway
## tunnel between two fields of quicksand; and the last third is a dune highway at 140 km/h where the tank drifts up
## sand ramps and leaps into the flying wing's sight.

enum Section { OUTSKIRTS, AVENUE, PIT, CANYON, RUN }

const SECTION_STARTS := [0.0, 650.0, 1550.0, 2000.0, 3300.0]
const LENGTH := 7100.0
const HORIZON_SHIFT := 20.0 ## Squads from ahead spawn this much farther out and walk in.
const DRIFT := 9.0 ## How high the sand banks against the towers.
const HULL_MARGIN := 3.0 ## The floor extends this far past the hull limit so the track samples at the edge never hang.
const PIT_D := 1800.0
const PIT_RADIUS := 80.0
const SPRINT_KMH := 140.0
## The avenue's wide S ends in a 85 degree right bend into the pit; a 85 degree left bend after the tunnel straightens
## the road again before the run.
const PLAN := [[1100.0, 0.0], [380.0, 20.0], [380.0, -20.0], [200.0, 85.0], [440.0, 0.0], [860.0, 0.0], [200.0, -85.0], [240.0, 0.0], [2500.0, 0.0], [2600.0, 0.0]]
## Sand ramps along the run, inside the tank's reach and alternating sides: drifting up one builds speed, and the
## faster the tank leaves its lip the higher it flies.
const HILL_FIRST := 3560.0
const HILL_SPACING := 400.0 ## Room for the longest leap off one ramp to land short of the next.
const HILL_COUNT := 8 ## Five belly turrets and three structures on the back; a missed leap is finished past the last ramp.
const HILL_LENGTH := 120.0
const HILL_HEIGHT := 12.0
const HILL_U := 22.0 ## Lateral offset of a ramp's track.
const HILL_HALF := 8.0 ## Half width of its track.
const HILL_FLANK := 10.0 ## Width of the sand falling away beside the track.
const OPEN_END := 650.0 ## The dune sea closes into the avenue by here.
const DUNE_WAVE := 64.0 ## Metres between the crests of the outskirts' dunes.
const HOP_ZONES := [Vector2(40.0, 640.0), Vector2(1555.0, 1740.0)] ## Where a crest throws the tank: the dune sea and the pit's approach.
const CRATER_WALL := 8.0 ## Height of the ring of dunes round the pit.
const PIT_RISE := 5.0 ## How far the plateau before the pit stands above its floor.
const BULGE_RADIUS := 6.5 ## Of the burst that hurts, and the mound the borer leaves.
const BULGE_AHEAD := 64.0 ## Where a bulge is marked: the distance the tank covers in 2.2 s at cruise.
const BULGE_HEIGHT := 2.4 ## Of the sand as it swells before the burst.
const CRATER_RIM := 1.0 ## Of the ring of sand a burst throws up, at CRATER_RADIUS from its centre.
const CRATER_RADIUS := 5.5
const CRATER_DEPTH := 1.8
const DIVE_D := 2200.0 ## The street starts down under the sand...
const TUNNEL_D := 2290.0 ## ...and is roofed from here...
const TUNNEL_END := 2560.0 ## ...to here, then climbs back out by RISE_END.
const RISE_END := 2650.0
const TUNNEL_DEPTH := 9.0 ## Of the tunnel floor under the street.
const TUNNEL_HALF := 14.0 ## Hull limit inside the tunnel.
const TUNNEL_CLEAR := 10.0 ## From the tunnel floor to its soffit.
const TUNNEL_BAY := 30.0
const SINK_RADIUS := 15.0 ## Of a quicksand funnel.
const SINK_DEPTH := 1.2
const SINK_PULL := 24.0 ## Metres per second the funnel drags toward its centre at the steepest.
## Centres (d, u) of the quicksand: a field before the tunnel and one after it.
const SINKS: Array[Vector2] = [Vector2(2050.0, -14.0), Vector2(2100.0, 13.0), Vector2(2150.0, -6.0), Vector2(2690.0, 12.0), Vector2(2745.0, -12.0), Vector2(2800.0, 6.0)]
const STORM_D := 2640.0 ## The storm meets the tank as it climbs out of the tunnel.
const FALLEN_D := 3150.0 ## The fallen tower that arches over the road into the run.
const FALLEN_U := -70.0 ## Its base.
const FALLEN_SIZE := Vector3(14.0, 110.0, 18.0)
const FALLEN_TILT := -PI / 3.0 ## Leaning 60 degrees from upright, across the street.

var _swell := make_noise(61, 0.008)
var _crest := make_noise(67, 0.013)
var _ripple := make_noise(71, 0.09)
var _grain := make_noise(73, 0.05)
var _far := make_noise(79, 0.006)
var mounds: Array[Dictionary] = [] ## {d, u, swell, crater}: the live bulges, which add their sand to the ground.


func _init() -> void:
	number = 3
	city = true
	standoff = 0.6
	plan = PLAN
	section_starts.assign(SECTION_STARTS)
	checkpoints = {"": 0.0, "midboss": PIT_D - 270.0, "boss": SECTION_STARTS[Section.RUN] + 20.0}
	coax_tiers = {"": 2, "midboss": 2, "boss": 2}
	midboss_d = PIT_D
	arena_center_d = PIT_D
	arena_radius = PIT_RADIUS
	arenas = [{"d": PIT_D, "radius": PIT_RADIUS}]
	sky_top = Palette.SKY.lerp(Palette.TEAL, 0.25)
	sky_horizon = Palette.CREAM.lerp(Palette.SKY, 0.3)
	sky_ground = Palette.CREAM.lerp(Palette.SKY, 0.3)
	# Hard desert light: a high afternoon sun rakes the dunes and the shade falls cool lilac, so facets keep their value range.
	ambient = Palette.LILAC.lerp(Palette.PEACH, 0.6)
	ambient_energy = 0.62
	fog_color = Palette.PEACH.lerp(Palette.BUTTER, 0.5)
	storm_color = Palette.OCHRE.lerp(Palette.PEACH, 0.35)
	storm_motes = [Palette.STRAW, Palette.OCHRE, Palette.BUTTER]
	storm_wind = 1.0
	fog_begin = 70.0
	fog_end = 360.0
	sun_color = Palette.BUTTER.lerp(Palette.CREAM, 0.5)
	sun_rotation = Vector3(-32.0, 120.0, 0.0)
	sun_energy = 1.15
	_generate_walls()
	_generate_tunnel()
	_generate_ruins()
	_generate_backdrop()


func hill_d(index: int) -> float:
	return HILL_FIRST + HILL_SPACING * index


## Lateral side (-1 left, 1 right) of ramp `index`: they alternate, the first on the left.
func hill_side(index: int) -> float:
	return -1.0 if index % 2 == 0 else 1.0


func _street_half(d: float) -> float:
	var half := lerpf(62.0, 34.0, smoothstep(520.0, OPEN_END, d))
	half = lerpf(half, 28.0, band(d, 600.0, 700.0, 1500.0, 1600.0))
	half = lerpf(half, 36.0, band(d, 1560.0, 1620.0, 1700.0, 1720.0)) # Room on the pit's approach to dodge the bulges.
	half = lerpf(half, 22.0, band(d, 1950.0, 2050.0, 3250.0, 3350.0))
	half = lerpf(half, 32.0, band(d, 2000.0, 2040.0, 2160.0, 2200.0)) # The quicksand fields...
	half = lerpf(half, 32.0, band(d, 2650.0, 2690.0, 2830.0, 2870.0))
	half = lerpf(half, TUNNEL_HALF, band(d, DIVE_D, TUNNEL_D, TUNNEL_END, RISE_END)) # ...and the tunnel between them.
	return lerpf(half, 48.0, smoothstep(3250.0, 3400.0, d))


func lateral_limit(d: float) -> float:
	for arena in arenas:
		if absf(d - arena.d) <= arena.radius:
			return arena.radius - 6.0
	return _street_half(d)


func valley_half_width(d: float) -> float:
	return lateral_limit(d) + 16.0


## The avenue is the stage's one corridor: both kerbs are walled with towers. The other stretches draw the same random
## numbers so the avenue's towers stay where they were, but stand no wall.
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
					var variant := _tower_kind(index, rng) + 4 * rng.randi_range(0, 3)
					if index == Section.AVENUE:
						_structure("city_building", d, side * (setback + across * 0.5), Vector3(across, visible + DRIFT + 6.0, along), -6.0, variant)
				d = next_d
				along = next_along


## Half-buried towers leaning out of the sand beside the pit and the quicksand: landmarks, never a wall.
func _generate_ruins() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	for site: Vector3 in [Vector3(1585.0, -1.0, 62.0), Vector3(1640.0, 1.0, 74.0), Vector3(1930.0, -1.0, 78.0), Vector3(2005.0, 1.0, 70.0), Vector3(2080.0, -1.0, 66.0), Vector3(2150.0, 1.0, 80.0), Vector3(2700.0, -1.0, 70.0), Vector3(2770.0, 1.0, 66.0), Vector3(2840.0, -1.0, 84.0)]:
		var size := Vector3(rng.randf_range(18.0, 26.0), rng.randf_range(38.0, 60.0), rng.randf_range(18.0, 26.0))
		var tilt := Vector3(rng.randf_range(-0.05, 0.05), 0.0, -site.y * rng.randf_range(0.12, 0.26))
		_structure("city_building", site.x, site.y * site.z, size, -size.y + rng.randf_range(16.0, 30.0), _tower_kind(Section.PIT, rng) + 4 * rng.randi_range(0, 3), rng.randf_range(-0.3, 0.3), tilt)
	# The fallen tower leans on this one.
	_structure("city_building", FALLEN_D, 40.0, Vector3(24.0, 56.0, 24.0), -5.0, 2)


## The tunnel: a roof over its whole length and a tiled wall down each side, one bay at a time.
func _generate_tunnel() -> void:
	var floor_y := height(TUNNEL_D + TUNNEL_BAY, 0.0)
	var wall_u := TUNNEL_HALF + HULL_MARGIN + 1.0
	var d := TUNNEL_D + TUNNEL_BAY * 0.5
	while d < TUNNEL_END:
		_structure("tunnel_roof", d, 0.0, Vector3(wall_u * 2.0 + 6.0, 2.0, TUNNEL_BAY), floor_y + TUNNEL_CLEAR)
		for side in [-1.0, 1.0]:
			_structure("tunnel_wall", d, side * wall_u, Vector3(2.0, TUNNEL_CLEAR + 0.5, TUNNEL_BAY), floor_y - 0.5, 0 if side > 0.0 else 1)
		d += TUNNEL_BAY


## Two rows of lower blocks behind the avenue's towers so the street never ends in a void, and across the run. The
## other stretches stay open to the horizon but draw the same random numbers.
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
				var placed := not run or rng.randf() < 0.8
				var variant := rng.randi_range(0, 7) if placed else 0
				if placed and (run or section_at(d) == Section.AVENUE):
					_backdrop(d, side * (inner + across * 0.5), Vector3(across, roof + 4.5, along), variant)
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
	# The avenue shows through in the troughs; sand banks against the towers and rolls away behind them. The dune sea has
	# no banks, and over the tunnel the sand lies flush with its roof.
	var open := 1.0 - smoothstep(520.0, OPEN_END, d) if d < OPEN_END else 0.0
	h += open * _dunes(d, u)
	h += smoothstep(limit + HULL_MARGIN, limit + 20.0, au) * DRIFT * (1.0 - open) * (1.0 - 0.85 * band(d, TUNNEL_D - 30.0, TUNNEL_D, TUNNEL_END, TUNNEL_END + 30.0))
	h += smoothstep(limit + 20.0, limit + 110.0, au) * (5.0 + 14.0 * (_far.get_noise_2d(d, u) * 0.5 + 0.5)) * (1.0 - 0.75 * open)
	h += PIT_RISE * band(d, 1555.0, 1610.0, 1630.0, 1712.0)
	h += CRATER_WALL * _rim(d, u)
	# The street dives under the sand: a flat floor between steep sand walls, wide enough for the hull.
	var cut := tunnel_depth(d)
	if cut > 0.0:
		var inside := 1.0 - smoothstep(limit + HULL_MARGIN + 0.5, limit + 10.0, au)
		h = lerpf(h, lerpf(floor_h, 0.2, cut / TUNNEL_DEPTH), inside * cut / TUNNEL_DEPTH) - cut * inside # The tunnel floor is dead flat.
	h += _spill(d, u)
	h -= SINK_DEPTH * sink_at(d, u)
	for index in HILL_COUNT:
		var hill := _hill(index, d, u)
		h = lerpf(h, floor_h, hill.y) + hill.x
	return lerpf(floor_h, h, smoothstep(0.0, 24.0, outside)) if outside < INF else h


## The dune sea's transverse dunes: tents of sand with rounded crests across the road, their lines skewed and
## their height varying with the lane. The crest's radius makes it throw a tank going faster than about 17 m/s.
func _dunes(d: float, u: float) -> float:
	var warp := _swell.get_noise_2d(d * 0.6 + 400.0, u * 0.6) * 22.0 + u * 0.22
	var tent := 1.0 - sqrt(pow(sin(PI * (d + warp) / DUNE_WAVE), 2.0) + 0.0144)
	return tent * (1.6 + 1.4 * (_crest.get_noise_2d(d * 0.3, u * 0.3) * 0.5 + 0.5)) * smoothstep(20.0, 80.0, d)


## The sand the drill threw up round the pit: a ring of dunes with a gate where the road enters and leaves.
func _rim(d: float, u: float) -> float:
	if absf(d - PIT_D) > PIT_RADIUS + 90.0:
		return 0.0
	var r := Vector2(d - PIT_D, u).length()
	return exp(-pow((r - PIT_RADIUS - 45.0) / 20.0, 2.0)) * smoothstep(40.0, 75.0, absf(u))


## Sand that has blown in at both portals: drifts piled against the tunnel's walls, heaped just inside the mouth and thinning out down the tunnel.
func _spill(d: float, u: float) -> float:
	var depth := minf(d - TUNNEL_D, TUNNEL_END - d)
	if depth < 0.0 or depth > 40.0:
		return 0.0
	return 1.4 * smoothstep(0.0, 14.0, depth) * (1.0 - smoothstep(14.0, 40.0, depth)) * smoothstep(2.0, TUNNEL_HALF, absf(u)) * (0.7 + 0.3 * _swell.get_noise_2d(d, u))


## How far the street lies under the sand's level at d.
func tunnel_depth(d: float) -> float:
	return TUNNEL_DEPTH * band(d, DIVE_D, TUNNEL_D, TUNNEL_END, RISE_END)


## How deep in a quicksand funnel (d, u) lies, 0 outside every one and 1 at a centre.
func sink_at(d: float, u: float) -> float:
	var depth := 0.0
	for sink in SINKS:
		if absf(d - sink.x) < SINK_RADIUS:
			depth += 1.0 - smoothstep(0.0, SINK_RADIUS, Vector2(d - sink.x, u - sink.y).length())
	return minf(depth, 1.0)


## What the quicksand does to a tank at (d, u): x and y the pull toward the nearest centre in u and d (m/s), z how deep
## in it the tank is (0..1), which slows it.
func quicksand_at(d: float, u: float) -> Vector3:
	var pull := Vector2.ZERO
	var depth := 0.0
	for sink in SINKS:
		var toward := Vector2(sink.y - u, sink.x - d)
		var r := toward.length()
		if r >= SINK_RADIUS or r < 0.001:
			continue
		depth = maxf(depth, 1.0 - smoothstep(0.0, SINK_RADIUS, r))
		pull += toward / r * SINK_PULL * smoothstep(SINK_RADIUS, SINK_RADIUS * 0.6, r)
	return Vector3(pull.x, pull.y, depth)


## Whether a crest here throws a fast tank into the air (see Tank._leap).
func hops_at(d: float) -> bool:
	return HOP_ZONES.any(func(zone: Vector2) -> bool: return d >= zone.x and d <= zone.y)


## Sand the borer's bulges (see SandBulge) swell and leave behind, summed over the live ones.
func dynamic_height(d: float, u: float) -> float:
	var h := 0.0
	for mound in mounds:
		var r := Vector2(d - mound.d, u - mound.u).length()
		if r < BULGE_RADIUS * 2.2:
			h += mound.swell * swell_profile(r) + mound.crater * crater_profile(r)
	return h


static func swell_profile(r: float) -> float:
	return BULGE_HEIGHT * exp(-pow(r / (BULGE_RADIUS * 0.55), 2.0))


## What a burst leaves: a hole with a ring of thrown sand around it, which a fast tank hops off.
static func crater_profile(r: float) -> float:
	return CRATER_RIM * exp(-pow((r - CRATER_RADIUS) / 3.0, 2.0)) - CRATER_DEPTH * exp(-pow(r / 3.2, 2.0))


## The sand ramp `index` at (d, u): x is the height it adds, a track that climbs along d to a lip and falls away
## behind it; y how much it smooths the dunes under it away, so the track's gradient is its own.
func _hill(index: int, d: float, u: float) -> Vector2:
	var s := d - hill_d(index)
	if s < -30.0 or s > HILL_LENGTH + 40.0:
		return Vector2.ZERO
	var across := 1.0 - smoothstep(HILL_HALF, HILL_HALF + HILL_FLANK, absf(u - hill_side(index) * HILL_U))
	var along := pow(clampf(s / HILL_LENGTH, 0.0, 1.0), 4.0) * (1.0 - smoothstep(0.0, 24.0, s - HILL_LENGTH))
	return Vector2(HILL_HEIGHT * along, band(s, -30.0, 0.0, HILL_LENGTH, HILL_LENGTH + 24.0)) * across


## Where ramp `index`'s track lies at fraction `t` (0 foot, 1 lip), on its centre line.
func hill_point(index: int, t: float) -> Vector3:
	return Course.ground_at(hill_d(index) + HILL_LENGTH * t, hill_side(index) * HILL_U)


func ramp_at(d: float, u: float) -> float:
	for index in HILL_COUNT:
		var s := d - hill_d(index)
		if s >= 0.0 and s <= HILL_LENGTH and absf(u - hill_side(index) * HILL_U) < HILL_HALF:
			return s / HILL_LENGTH
	return -1.0


## Rail distance past which no ramp is left to leap from.
func ramps_end() -> float:
	return hill_d(HILL_COUNT - 1) + HILL_LENGTH + 250.0


func ground_color(d: float, u: float, h: float, slope: float) -> Color:
	var au := absf(u)
	var grain := _grain.get_noise_2d(d, u)
	var ramp := ramp_at(d, u)
	if ramp >= 0.0:
		return Palette.CREAM if int(ramp * HILL_LENGTH / 10.0) % 2 == 0 else Palette.STONE
	# Colours blend continuously with height, slope and grain so the facets shade softly instead of breaking into
	# hard-edged blotches at thresholds.
	# Crests catch the light, troughs settle into peach, and a face climbing toward the camera glows while the lee
	# side falls into ochre shade, so even low drivable swells read as dunes.
	var ridge := 1.0 - absf(_crest.get_noise_2d(d, u))
	var rise := height(d + 1.5, u) - height(d - 1.5, u)
	if d < 1800.0 and (d < OPEN_END or band(d, 1540.0, 1580.0, 1740.0, 1790.0) > 0.0):
		rise = (height(d + 6.0, u) - height(d - 6.0, u)) * 0.25 # The slope of the dune, not of its ripples.
	var sand := Palette.PEACH.lerp(Palette.BUTTER, smoothstep(0.6, 1.0, ridge) * 0.6 + smoothstep(2.0, 8.0, h) * 0.2)
	sand = sand.lerp(Palette.STRAW, clampf(-grain, 0.0, 1.0) * 0.35)
	# The open stretches' gentle swells read with the same light and shade as steeper sand: the windward face glows, the
	# lee falls into dark ochre, the crest keeps a lit edge, the troughs shade and ripple bands run across the sand.
	var open := 1.0 - smoothstep(520.0, OPEN_END, d) if d < OPEN_END else 0.0
	var wide := maxf(open, band(d, 1540.0, 1580.0, 1740.0, 1790.0))
	var lit := lerpf(0.2, 0.1, wide)
	var shade := lerpf(0.8, 0.35, wide)
	sand = sand.lerp(Palette.CREAM, smoothstep(lit, shade, rise) * lerpf(0.3, 0.75, wide))
	sand = sand.lerp(Palette.OCHRE.darkened(0.3 * wide), smoothstep(-lit, -shade, rise) * (0.3 + 0.6 * wide))
	if wide > 0.0:
		var bend := (height(d + 8.0, u) + height(d - 8.0, u) - 2.0 * h) * 9.0 / 64.0 # Curvature of the dune itself, not its ripples.
		sand = sand.lerp(Palette.CREAM, smoothstep(0.1, 0.5, -bend) * 0.7 * wide).lerp(Palette.OCHRE, smoothstep(0.1, 0.5, bend) * 0.4 * wide)
	sand = sand.lerp(Palette.OCHRE, smoothstep(0.5, 0.9, sin((d + u * 0.35) * 0.45 + _ripple.get_noise_2d(d, u) * 3.0)) * 0.3 * (0.4 + 0.6 * wide))
	sand = sand.lerp(Palette.OCHRE, smoothstep(0.25, 0.8, slope) * 0.6)
	for arena in arenas:
		var r := Vector2(d - arena.d, u).length()
		if r < arena.radius + 6.0:
			# The pit floor: swept concrete under a skin of sand, with the drill's scoured ring at the rim.
			var floor_color := Palette.CONCRETE.lerp(Palette.STRAW, 0.35 + grain * 0.3)
			return floor_color.lerp(Palette.STONE, smoothstep(arena.radius - 8.0, arena.radius, r) * 0.6)
	sand = sand.lerp(Palette.OCHRE.darkened(0.3), sink_at(d, u) * 0.85)
	if tunnel_depth(d) > 1.0 and au < lateral_limit(d) + HULL_MARGIN + 0.5:
		# Asphalt, dark between the lamps' pools of light (the lamps hang at d = 5 mod 10).
		var pool := 1.0 - absf(fposmod(d, 10.0) - 5.0) / 5.0
		var asphalt := Palette.SLATE.lerp(Palette.ASH, pool * pool * 0.3)
		return asphalt.lerp(sand, maxf(smoothstep(2.0, 0.5, tunnel_depth(d)), smoothstep(0.1, 0.5, _spill(d, u))))
	if au < lateral_limit(d) - 2.0:
		return sand.lerp(Palette.ASH, smoothstep(0.3, -0.6, h) * 0.5)
	return sand


func camera_u(d: float, u: float) -> float:
	var reach := lateral_limit(d - ChaseCamera.RAIL_BACK) - 6.0
	return clampf(u * 0.75, -reach, reach)


## The camera drops under the soffit before the tank reaches the portal and climbs back once it is out behind the tank.
func camera_height(d: float) -> float:
	var under := band(d, TUNNEL_D - 70.0, TUNNEL_D - 15.0, TUNNEL_END + ChaseCamera.RAIL_BACK + 5.0, TUNNEL_END + 70.0)
	return lerpf(ChaseCamera.RAIL_HEIGHT, TUNNEL_CLEAR - 2.5, under)


## Each stretch has its own haze: peach on the outskirts, amber in the avenue, rose over the pit, a dim brown
## storm in the canyon and white-gold on the run.
func fog_tint(d: float) -> Color:
	return _section_blend([fog_color, fog_color.lerp(Palette.AMBER, 0.2), fog_color.lerp(Palette.BLUSH, 0.4), fog_color.lerp(Palette.OCHRE, 0.5).darkened(0.1), fog_color.lerp(Palette.CREAM, 0.55)], d).lerp(Palette.DUSK, 0.75 * tunnel_share(d))


## How far inside the tunnel the rail is (0 outside, 1 well in), easing over the portals.
func tunnel_share(d: float) -> float:
	return band(d, TUNNEL_D - 40.0, TUNNEL_D + 20.0, TUNNEL_END - 20.0, TUNNEL_END + 40.0)


## The tunnel is dark and cool: the roof shuts the sun out and only a dim blue sky-light and its lamps light it.
func ambient_energy_at(d: float) -> float:
	return lerpf(ambient_energy, 0.45, tunnel_share(d))


func ambient_color_at(d: float) -> Color:
	return ambient.lerp(Palette.PERIWINKLE, 0.8 * tunnel_share(d))


func sun_scale_at(d: float) -> float:
	return 1.0 - 0.9 * tunnel_share(d)


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
			return "res://assets/music/stage3_borer.ogg"
		Section.CANYON:
			return "res://assets/music/stage3_storm.ogg"
	return "res://assets/music/stage3_road.ogg"


func boss_music(_phase := 0) -> String:
	return "res://assets/music/stage3_boss.ogg"


## Pushes a wave and its squad from ahead out to the haze; pursuers from behind and flankers keep their slot.
func _to_horizon(event: Dictionary) -> void:
	event.ahead = event.get("ahead", 90.0) # 90 m is the director's default slot, which would pop the unit up mid-street.
	if not event.get("close", false) and event.get("formation", "") not in ["behind", "flank"]:
		event.ahead += HORIZON_SHIFT
	for member: Dictionary in event.get("squad", []):
		_to_horizon(member)


func events(hard: bool) -> Array[Dictionary]:
	var e: Array[Dictionary] = []
	var wave := func(d: float, kind: String, extra: Dictionary) -> void:
		var event := {"d": d, "type": "wave", "kind": kind, "hard_scale": 1.0}
		event.merge(extra)
		e.append(event)

	# Few hunters, each deadly, in beats: every stretch opens light, builds to a peak where hunters overlap, and
	# releases before the next. The outskirts are open dunes, so skimmers sweep in from the flanks: a lone skimmer,
	# a burrower to read, then a sniper, a mortar crew and a second burrower with its flankers at once.
	wave.call(30.0, "skimmer", {"ahead": 70.0})
	wave.call(135.0, "skimmer", {"count": 3, "formation": "v", "u": 10.0, "spacing": 7.0, "ahead": 70.0})
	wave.call(240.0, "burrower", {"u": -17.0, "ahead": 70.0, "drop": "coax", "squad": [
		{"kind": "skimmer", "u": 6.0, "ahead": 60.0}]})
	wave.call(330.0, "skimmer", {"count": 2, "formation": "flank", "u": 1.0, "spacing": 10.0, "ahead": 20.0})
	wave.call(420.0, "glinter", {"u": 21.0, "ahead": 80.0, "peak": true})
	wave.call(450.0, "mortar", {"u": -20.0, "ahead": 85.0})
	wave.call(480.0, "burrower", {"u": 8.0, "ahead": 60.0, "squad": [
		{"kind": "skimmer", "count": 2, "formation": "flank", "u": -1.0, "spacing": 10.0, "ahead": 15.0}]})
	e.append({"d": 640.0, "type": "pickup", "id": "atgm"})

	# The avenue: a mortar crew among the towers, a Hind low over the street, then a sniper, a burrower and a
	# mortar crew with its own sniper before the bend.
	wave.call(700.0, "mortar", {"u": 8.0, "ahead": 80.0, "drop": "micro", "squad": [
		{"kind": "skimmer", "u": 6.0, "ahead": 60.0}]})
	wave.call(800.0, "skimmer", {"count": 4, "u": -10.0, "spacing": 7.0, "ahead": 70.0})
	wave.call(900.0, "hind", {"u": 10.0, "height": 5.0, "ahead": 70.0})
	wave.call(990.0, "skimmer", {"count": 3, "formation": "v", "spacing": 7.0, "ahead": 70.0})
	wave.call(1040.0, "glinter", {"u": -14.5, "ahead": 80.0, "peak": true})
	wave.call(1080.0, "burrower", {"u": 17.0, "ahead": 60.0, "squad": [
		{"kind": "skimmer", "u": 6.0, "ahead": 60.0}]})
	wave.call(1120.0, "mortar", {"u": 12.0, "ahead": 85.0, "squad": [
		{"kind": "glinter", "u": -8.0, "ahead": 90.0}]})
	wave.call(1260.0, "skimmer", {"count": 4, "formation": "v", "u": -8.0, "spacing": 7.0, "ahead": 70.0})
	e.append({"d": 1470.0, "type": "pickup", "id": "micro", "u": -4.0})

	e.append({"d": PIT_D - 270.0, "type": "checkpoint", "name": "midboss"})
	e.append({"d": PIT_D - 220.0, "type": "pickup", "id": "micro", "ahead": 15.0})
	# The borer's sand swells under three lanes in turn on the way down into the pit, each marked 2 s before it bursts.
	for bulge: Vector2 in [Vector2(1620.0, -9.0), Vector2(1650.0, 2.0), Vector2(1676.0, 9.0)]:
		e.append({"d": bulge.x - BULGE_AHEAD, "type": "bulge", "u": bulge.y, "ahead": BULGE_AHEAD})
	e.append({"d": PIT_D - 160.0, "type": "pickup", "id": "repair", "u": -4.0, "ahead": 28.0})
	e.append({"d": PIT_D - 110.0, "type": "midboss", "kind": "borer", "ahead": 60.0, "peak": true, "hold": PIT_D - 56.0})

	# The canyon: a mortar walks its shells over the first quicksand, skimmers charge up the tunnel behind the tank
	# and down it ahead, and where the storm meets the second quicksand a Hind, a sniper, a burrower coming up
	# behind and a mortar crew close in together.
	wave.call(2060.0, "mortar", {"u": -8.0, "ahead": 80.0})
	wave.call(2140.0, "skimmer", {"count": 3, "formation": "v", "spacing": 7.0, "ahead": 70.0})
	wave.call(2330.0, "skimmer", {"count": 2, "formation": "behind", "spacing": 6.0})
	wave.call(2420.0, "skimmer", {"count": 3, "formation": "column", "spacing": 10.0, "ahead": 70.0})
	e.append({"d": STORM_D, "type": "storm", "duration": 22.0})
	wave.call(2660.0, "hind", {"u": -10.0, "height": 5.0, "ahead": 70.0, "peak": true})
	wave.call(2700.0, "glinter", {"u": 14.5, "ahead": 80.0})
	wave.call(2720.0, "burrower", {"formation": "behind"})
	wave.call(2760.0, "mortar", {"u": 15.0, "ahead": 70.0, "squad": [
		{"kind": "skimmer", "count": 2, "u": -6.0, "spacing": 8.0, "ahead": 60.0}]})
	wave.call(2900.0, "skimmer", {"count": 4, "formation": "v", "spacing": 7.0, "ahead": 70.0})
	e.append({"d": 3000.0, "type": "hold", "at": 3015.0, "timeout": 25.0, "reward": "repair"})
	wave.call(3100.0, "burrower", {"u": 8.0, "ahead": 70.0})
	e.append({"d": 3160.0, "type": "pickup", "id": "era", "u": -4.0})
	e.append({"d": 3220.0, "type": "pickup", "id": "atgm", "u": 4.0})

	# The run: the rail floors it to 140 km/h and the flying wing shows itself above the ramps.
	e.append({"d": SECTION_STARTS[Section.RUN] + 20.0, "type": "checkpoint", "name": "boss"})
	e.append({"d": SECTION_STARTS[Section.RUN] + 60.0, "type": "pickup", "id": "repair", "u": -4.0, "ahead": 20.0})
	e.append({"d": SECTION_STARTS[Section.RUN] + 90.0, "type": "pickup", "id": "dragon", "ahead": 15.0})
	e.append({"d": SECTION_STARTS[Section.RUN] + 130.0, "type": "sprint", "kmh": SPRINT_KMH})
	e.append({"d": hill_d(0) - 62.0, "type": "boss", "kind": "wing", "rail": true})
	# Past the last ramp the rail stops short of the road's end and the wing comes down to finish the tank.
	e.append({"d": ramps_end(), "type": "hold", "at": ramps_end() + 170.0, "timeout": 600.0})

	if hard:
		var pressure := {1120.0: {"glinter": 1}, 700.0: {"skimmer": 1}}
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
