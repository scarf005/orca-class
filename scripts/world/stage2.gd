class_name Stage2
extends StageDef
## Stage 2 "Plasmodium": the flooded paddies and marsh downstream of the dam, ending at the
## drainage floodgate. Pacing per section: quiet opening, build, peak, then a short release.

enum Section { FLOODPLAIN, PADDIES, MILL, MARSH, LEVEE, ARENA }

const SECTION_STARTS := [0.0, 420.0, 1000.0, 1260.0, 1880.0, 2300.0]
const MIDBOSS_D := 1150.0
const ARENA_CENTER_D := 2410.0
const ARENA_RADIUS := 85.0
const FLOOD_LEVEL := 0.35 ## The floodplain's sheet of shallow water.
const LEVEL := 0.5 ## Canal, marsh and levee water, and where the arena's water starts.
const CANAL_U := Vector2(-33.0, -27.0) ## The concrete irrigation canal beside the paddies.
const CANAL_D := Vector2(440.0, 1000.0)
const CANAL_BED := -1.2
const WET_D := Vector2(430.0, 2317.0) ## Along the road, as far as the deep water meshes go.
const WET_U := 50.0 ## Marsh and levee water reaches this far from the road.
const GATE_D := ARENA_CENTER_D + 80.0 ## Where the floodgate stands; the ground is flat and clear up to it.
const GATE_HALF := 50.0 ## Half width of the basin at the gate.
const CELL := 6.0 ## Grid of the deep water meshes.

## About 2,400 m of rail through a few gentle bends, straight into the arena.
const PLAN := [
	[650.0, 0.0], [300.0, 40.0], [200.0, 0.0], [350.0, -60.0], [250.0, 0.0], [300.0, 50.0], [250.0, 0.0],
	[350.0, -70.0], [150.0, 0.0], [900.0, 0.0],
]

## The arena's water surface. Setting it moves both the water query and the mesh.
var arena_level := LEVEL

var _noise := make_noise(31, 0.004)
var _detail := make_noise(37, 0.05)
var _fungus := make_noise(41, 0.018)
var _marsh := make_noise(53, 0.025)
var _mud := make_noise(59, 0.03)


func _init() -> void:
	number = 2
	plan = PLAN
	section_starts.assign(SECTION_STARTS)
	checkpoints = {"": 0.0, "midboss": MIDBOSS_D - 110.0, "boss": SECTION_STARTS[Section.ARENA] - 40.0}
	start_rws = true
	water_slows = true
	coax_tiers = {"": 2, "midboss": 2, "boss": 3}
	midboss_d = MIDBOSS_D
	arena_center_d = ARENA_CENTER_D
	arena_radius = ARENA_RADIUS
	sky_top = Color("7f8fd0")
	sky_horizon = Color("ecc9d6")
	sky_ground = Color("a898d8")
	ambient = Color("a8a0d0")
	fog_color = Color("dccadc")
	fog_begin = 60.0
	fog_end = 320.0
	sun_rotation = Vector3(-24.0, 200.0, 0.0)
	sun_color = Color("ffe0d0")
	sun_energy = 0.95


func music(section: int) -> String:
	match section:
		Section.ARENA:
			return ""
		Section.PADDIES, Section.MILL, Section.LEVEE:
			return "res://assets/music/stage_b.ogg"
	return "res://assets/music/stage_a.ogg"


func valley_half_width(d: float) -> float:
	var width := lerpf(40.0, 70.0, band(d, 980.0, 1040.0, 1250.0, 1310.0))
	return lerpf(width, ARENA_RADIUS + 25.0, band(d, 2260.0, 2320.0, 2560.0, 2700.0))


## Paddy terraces step up away from the road; each holds a hand of water above its ground.
func _terrace(au: float) -> float:
	return floorf((au + 0.9) / 18.0) * 0.45 - 0.3


## Raised paddy dikes: long ones (논두렁) along the road where the terraces meet, short ones across.
func _dike(d: float, u: float) -> float:
	var au := absf(u)
	var eu := minf(fposmod(au, 18.0), 18.0 - fposmod(au, 18.0))
	var lane := (1.0 - smoothstep(0.9, 1.7, eu)) * smoothstep(9.0, 12.0, au)
	var ed := minf(fposmod(d, 24.0), 24.0 - fposmod(d, 24.0))
	return maxf(lane * 0.6, (1.0 - smoothstep(0.5, 1.2, ed)) * 0.45)


func _road_height(d: float) -> float:
	var r := 0.65
	r = lerpf(r, -0.3, band(d, 400.0, 450.0, 980.0, 1020.0))
	r = lerpf(r, 0.95, band(d, 990.0, 1030.0, 1270.0, 1300.0))
	r = lerpf(r, 0.35, band(d, 1250.0, 1290.0, 1850.0, 1880.0))
	r = lerpf(r, 1.6, band(d, 1860.0, 1890.0, 2250.0, 2280.0))
	return lerpf(r, 0.8, smoothstep(2280.0, 2330.0, d))


## Signed distance from the arena basin's edge: a circle around the centre joined to a box out to
## the gate, negative inside.
func _basin(d: float, u: float) -> float:
	var radial := Vector2(d - ARENA_CENTER_D, u).length() - ARENA_RADIUS
	var box := maxf(absf(u) - GATE_HALF, maxf(d - (GATE_D + 3.0), ARENA_CENTER_D - 10.0 - d))
	return minf(radial, box)


func height(d: float, u: float) -> float:
	var au := absf(u)
	var half := valley_half_width(d)
	var rise := smoothstep(half, half + 70.0, au)
	var h := _noise.get_noise_2d(d, u) * 0.25
	# Hills rise beyond the flooded floor.
	h += rise * (18.0 + 22.0 * (_noise.get_noise_2d(d * 0.6 + 500.0, u * 0.6) + 0.5)) + rise * rise * 14.0
	h += _detail.get_noise_2d(d, u) * 0.3 * (0.3 + rise)
	# Paddies: terraces with dikes, flooded a hand deep.
	var paddy := band(d, 380.0, 440.0, 980.0, 1040.0) * (1.0 - rise)
	if paddy > 0.0:
		h = lerpf(h, _terrace(au) + _dike(d, u), paddy)
	# The concrete canal cut into the terraces beside the road.
	var canal_reach := band(d, CANAL_D.x - 10.0, CANAL_D.x + 10.0, CANAL_D.y - 10.0, CANAL_D.y + 10.0)
	var outside := maxf(CANAL_U.x - u, u - CANAL_U.y)
	h = lerpf(h, maxf(h, LEVEL + 0.3), canal_reach * smoothstep(0.8, 1.4, outside) * (1.0 - smoothstep(1.8, 2.6, outside)))
	h = lerpf(h, CANAL_BED, canal_reach * (1.0 - smoothstep(0.0, 1.2, outside)))
	# Marsh: pools and hummocks.
	var marsh := band(d, 1230.0, 1290.0, 1860.0, 1890.0) * (1.0 - rise) * smoothstep(5.0, 10.0, au)
	h = lerpf(h, 0.05 + _marsh.get_noise_2d(d, u) * 0.9, marsh)
	# The levee stands above deep water on both sides.
	var levee := band(d, 1860.0, 1890.0, 2250.0, 2280.0)
	h = lerpf(h, -1.3 + _detail.get_noise_2d(d, u) * 0.2, levee * smoothstep(10.0, 15.0, au) * (1.0 - rise))
	# The road is a flat strip; the levee's is wider.
	var road_edge := lerpf(4.0, 6.0, 1.0 - levee)
	var road := 1.0 - smoothstep(road_edge, road_edge + lerpf(2.0, 4.0, levee), au)
	h = lerpf(h, _road_height(d) + _noise.get_noise_2d(d, 0.0) * 0.2, road * (1.0 - rise))
	# The mill yard is flat and dry.
	var yard := band(d, 990.0, 1030.0, 1270.0, 1300.0) * (1.0 - smoothstep(60.0, 75.0, au))
	h = lerpf(h, 0.95 + _detail.get_noise_2d(d, u) * 0.1, yard)
	# The arena: a basin, shallow in the middle and deep around, inside a rim, with a bank behind the gate.
	var sd := _basin(d, u)
	var radial := Vector2(d - ARENA_CENTER_D, u).length()
	var floor_h := -0.15 - 1.0 * smoothstep(45.0, 70.0, radial) + _detail.get_noise_2d(d, u) * 0.15
	h = lerpf(h, floor_h, 1.0 - smoothstep(0.0, 8.0, sd))
	var rim := smoothstep(-1.0, 6.0, sd) * (1.0 - smoothstep(20.0, 34.0, sd))
	if d < ARENA_CENTER_D:
		rim *= smoothstep(6.0, 16.0, au) # The road comes in through a gap in the rim.
	h = lerpf(h, 1.3 + _detail.get_noise_2d(d, u) * 0.3, rim)
	return lerpf(h, maxf(h, 20.0), smoothstep(GATE_D + 4.0, GATE_D + 14.0, d))


## The surface of the water over ground of height `h` at (d, u), or -INF when it is dry there.
func _surface(d: float, u: float, h: float) -> float:
	var surface := -INF
	var au := absf(u)
	if _basin(d, u) < 5.0 and d > ARENA_CENTER_D - 100.0:
		surface = arena_level
	elif d >= WET_D.x and d <= WET_D.y and au <= WET_U and (d > 1230.0 or u < CANAL_U.y + 3.0 and u > CANAL_U.x - 3.0):
		surface = LEVEL
	elif band(d, 380.0, 440.0, 980.0, 1040.0) > 0.5 and au < valley_half_width(d):
		surface = _terrace(au) + 0.35
	elif d < 410.0 and au < valley_half_width(d):
		surface = FLOOD_LEVEL
	return surface if surface > h else -INF


func water_surface(c: Vector2) -> float:
	return _surface(c.x, c.y, height(c.x, c.y))


func water_level(index: int) -> float:
	return LEVEL if index == 0 else arena_level


## Where the tank churns mud: marked patches of the floodplain and the marsh.
func mud_at(d: float, u: float) -> bool:
	var zone := band(d, 200.0, 260.0, 380.0, 420.0) + band(d, 1250.0, 1290.0, 1850.0, 1880.0)
	return zone > 0.5 and _mud.get_noise_2d(d, u) > 0.25


## Flat meshes over the deep water: the canal, marsh and levee, and the arena basin. Shallow water
## is painted ground instead. Built at height 0; `water_level` places each.
func water_meshes() -> Array[ArrayMesh]:
	return [_cells(WET_D.x, WET_D.y), _cells(ARENA_CENTER_D - 100.0, GATE_D + 6.0)]


## Quads over every grid cell with deep water in it.
func _cells(d0: float, d1: float) -> ArrayMesh:
	var triangles := PackedVector3Array()
	var d := d0
	while d < d1:
		var u := -110.0
		while u < 110.0:
			var deep := false
			for corner in [Vector2(0, 0), Vector2(CELL, 0), Vector2(0, CELL), Vector2(CELL, CELL), Vector2(CELL * 0.5, CELL * 0.5)]:
				var cd: float = d + corner.x
				var cu: float = u + corner.y
				var h := height(cd, cu)
				if _surface(cd, cu, h) - h > Water.DEEP * 0.75:
					deep = true
					break
			if deep:
				var a := Course.to_world(d, u)
				var b := Course.to_world(d, u + CELL)
				var c := Course.to_world(d + CELL, u + CELL)
				var e := Course.to_world(d + CELL, u)
				triangles.append_array([a, b, c, a, c, e])
			u += CELL
		d += CELL
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = triangles
	var normals := PackedVector3Array()
	normals.resize(triangles.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	if not triangles.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func fungus_at(d: float, u: float) -> float:
	var progress := clampf(d / 2300.0, 0.0, 1.0)
	var n := _fungus.get_noise_2d(d, u) * 0.5 + 0.5
	return smoothstep(0.8 - progress * 0.14, 0.88 - progress * 0.14, n)


func ground_color(d: float, u: float, h: float, slope: float) -> Color:
	var au := absf(u)
	var half := valley_half_width(d)
	var rise := smoothstep(half, half + 70.0, au)
	var depth := _surface(d, u, h) - h
	var color := Palette.SAGE
	if rise > 0.35:
		color = Palette.PINE if slope < 0.9 else Palette.MOSS
	elif band(d, CANAL_D.x - 10.0, CANAL_D.x + 10.0, CANAL_D.y - 10.0, CANAL_D.y + 10.0) > 0.3 and u > CANAL_U.x - 3.0 and u < CANAL_U.y + 3.0:
		color = Palette.CONCRETE
	elif mud_at(d, u) and depth < Water.DEEP:
		color = Palette.OCHRE
	elif depth > 0.0:
		color = Palette.SKY if depth < 0.4 else Palette.TEAL
	elif band(d, 990.0, 1030.0, 1270.0, 1300.0) > 0.5 and au < 70.0:
		color = Palette.CONCRETE if au < 6.0 or fposmod(d, 30.0) < 3.0 else Palette.OCHRE
	elif au < 6.0 and section_at(d) != Section.PADDIES:
		color = Palette.CONCRETE
		if absf(u) < 0.25 and fposmod(d, 12.0) < 6.0 and section_at(d) >= Section.PADDIES:
			color = Palette.BUTTER
	elif section_at(d) == Section.PADDIES:
		color = Palette.LEAF if h > _terrace(au) + 0.2 else Palette.BUTTER
	elif section_at(d) == Section.MARSH:
		color = Palette.MOSS if h > LEVEL else Palette.PINE
	elif d > 2280.0:
		color = Palette.STONE
	if fungus_at(d, u) > 0.5 and depth <= 0.0 and rise < 0.35:
		color = Palette.FUNGUS if fungus_at(d, u) > 0.8 else Palette.LILAC
	return color


func events(hard: bool) -> Array[Dictionary]:
	var e: Array[Dictionary] = []
	var wave := func(d: float, kind: String, extra: Dictionary) -> void:
		var event := {"d": d, "type": "wave", "kind": kind}
		event.merge(extra)
		e.append(event)

	# Floodplain (quiet -> build): night mist, sparse drones, the first ground contact.
	wave.call(90.0, "fpv", {"count": 2, "formation": "line", "height": 9.0, "spacing": 7.0, "hover": 26.0})
	wave.call(190.0, "fpv", {"count": 4, "formation": "v", "height": 8.0, "spacing": 5.0})
	wave.call(300.0, "crawler", {"count": 4, "formation": "sides", "spacing": 16.0, "ahead": 70.0})
	# Release 300-440: nothing spawns.

	# Paddies (build -> peak): the ground war returns along the dikes.
	wave.call(440.0, "ugv", {"count": 3, "formation": "sides", "spacing": 8.0, "ahead": 95.0})
	wave.call(520.0, "uav", {"count": 2, "formation": "line", "spacing": 10.0, "props": {"attack": "strafe"}})
	wave.call(600.0, "spitter", {"count": 4, "formation": "sides", "spacing": 15.0, "ahead": 80.0})
	wave.call(680.0, "crawler", {"count": 6, "formation": "scatter", "spacing": 18.0, "ahead": 60.0})
	wave.call(760.0, "walker", {"count": 3, "formation": "behind", "spacing": 9.0})
	wave.call(830.0, "fpv", {"count": 5, "formation": "ring", "height": 9.0, "spacing": 8.0, "stagger": 0.25})
	wave.call(900.0, "ugv", {"count": 3, "formation": "column", "spacing": 14.0, "ahead": 100.0, "u": 4.0, "drop": "coax"})
	wave.call(950.0, "helicopter", {"count": 1, "height": 13.0, "ahead": 110.0, "u": -10.0})

	# Rice mill: the mid-boss holds the rail.
	e.append({"d": 1010.0, "type": "checkpoint", "name": "midboss"})
	wave.call(1060.0, "crawler", {"count": 5, "formation": "scatter", "spacing": 20.0, "ahead": 60.0})
	e.append({"d": MIDBOSS_D - 110.0, "type": "midboss", "kind": "colossus", "hold": MIDBOSS_D - 56.0})

	# Marsh (build -> peak): drones out of the reeds, then helicopters over the water.
	wave.call(1290.0, "fpv", {"count": 4, "formation": "scatter", "height": 1.5, "spacing": 3.0, "ahead": 60.0})
	wave.call(1370.0, "uav", {"count": 3, "formation": "v", "spacing": 10.0, "props": {"attack": "bomb", "from_behind": true}})
	wave.call(1450.0, "spitter", {"count": 5, "formation": "line", "spacing": 4.0, "u": 20.0, "ahead": 85.0})
	wave.call(1530.0, "crawler", {"count": 6, "formation": "flank", "u": -1.0, "spacing": 6.0, "ahead": 10.0})
	wave.call(1610.0, "helicopter", {"count": 2, "formation": "sides", "height": 14.0, "spacing": 22.0, "ahead": 65.0})
	wave.call(1690.0, "fpv", {"count": 8, "formation": "ring", "height": 5.0, "spacing": 8.0, "stagger": 0.18})
	wave.call(1770.0, "ugv", {"count": 2, "formation": "line", "spacing": 8.0, "u": 4.0, "ahead": 100.0, "props": {"weapon": "atgm"}})
	wave.call(1840.0, "ugv", {"count": 1, "u": 0.0, "ahead": 90.0, "props": {"weapon": "supply"}, "drop": "repair"})

	# Levee, the heaviest mixed gauntlet. Release from 2200 to the boss.
	wave.call(1900.0, "walker", {"count": 4, "formation": "line", "spacing": 6.0, "ahead": 80.0, "props": {"weapon": "missile"}})
	wave.call(1960.0, "quad", {"count": 2, "formation": "sides", "spacing": 7.0, "ahead": 100.0})
	wave.call(2020.0, "helicopter", {"count": 3, "formation": "v", "height": 15.0, "spacing": 20.0, "ahead": 105.0})
	wave.call(2080.0, "ugv", {"count": 5, "formation": "column", "spacing": 10.0, "ahead": 100.0})
	wave.call(2130.0, "fpv", {"count": 8, "formation": "ring", "height": 9.0, "spacing": 9.0, "stagger": 0.15})
	wave.call(2170.0, "uav", {"count": 3, "formation": "line", "spacing": 10.0, "props": {"attack": "bomb", "from_behind": true}})
	e.append({"d": 2275.0, "type": "checkpoint", "name": "boss"})
	# The boss is wired to an existing kind for now.
	e.append({"d": 2345.0, "type": "boss", "kind": "gunship"})

	if hard:
		# Hard adds flankers to the build beats, never inside a release.
		wave.call(60.0, "fpv", {"count": 2, "formation": "sides", "height": 7.0, "spacing": 10.0})
		wave.call(560.0, "ugv", {"count": 2, "formation": "sides", "spacing": 9.0, "ahead": 100.0, "props": {"weapon": "atgm"}})
		wave.call(1330.0, "fpv", {"count": 3, "formation": "behind", "height": 6.0, "spacing": 5.0, "hover": 14.0, "approach": 1.0})
		wave.call(2050.0, "fpv", {"count": 4, "formation": "ring", "height": 9.0, "spacing": 9.0})
	return e
