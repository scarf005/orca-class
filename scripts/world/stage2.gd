class_name Stage2
extends StageDef
## Stage 2 "Plasmodium": the flooded paddies and marsh downstream of the dam, ending at the
## drainage floodgate. Pacing per section: quiet opening, build, peak, then a short release.

enum Section { FLOODPLAIN, PADDIES, MILL, MARSH, LEVEE, ARENA }

const SECTION_STARTS := [0.0, 420.0, 1000.0, 1260.0, 1880.0, 2300.0]
const MIDBOSS_D := 1150.0
const ARENA_CENTER_D := 2410.0
const ARENA_RADIUS := 85.0
const FLOOR := -0.35 ## The flooded valley floor.

## About 2,400 m of rail through a few gentle bends, straight into the arena.
const PLAN := [
	[650.0, 0.0], [300.0, 40.0], [200.0, 0.0], [350.0, -60.0], [250.0, 0.0], [300.0, 50.0], [250.0, 0.0],
	[350.0, -70.0], [150.0, 0.0], [900.0, 0.0],
]

var _noise := make_noise(31, 0.004)
var _detail := make_noise(37, 0.05)
var _fungus := make_noise(41, 0.018)


func _init() -> void:
	number = 2
	plan = PLAN
	section_starts.assign(SECTION_STARTS)
	checkpoints = {"": 0.0, "midboss": MIDBOSS_D - 110.0, "boss": SECTION_STARTS[Section.ARENA] - 40.0}
	start_rws = true
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
	return lerpf(40.0, ARENA_RADIUS + 25.0, band(d, 2260.0, 2320.0, 2560.0, 2700.0))


func height(d: float, u: float) -> float:
	var au := absf(u)
	var half := valley_half_width(d)
	var h := FLOOR + _noise.get_noise_2d(d, u) * 0.25
	# Hills rise beyond the flooded floor.
	var rise := smoothstep(half, half + 70.0, au)
	h += rise * (18.0 + 22.0 * (_noise.get_noise_2d(d * 0.6 + 500.0, u * 0.6) + 0.5)) + rise * rise * 14.0
	h += _detail.get_noise_2d(d, u) * 0.3 * (0.3 + rise)
	# The road is a slightly raised, flat strip.
	var road := 1.0 - smoothstep(4.0, 6.0, au)
	h = lerpf(h, 0.15 + _noise.get_noise_2d(d, 0.0) * 0.3, road * (1.0 - rise))
	# The arena floor is flat.
	var arena := band(d, 2280.0, 2320.0, ARENA_CENTER_D + 200.0, ARENA_CENTER_D + 240.0) * (1.0 - smoothstep(ARENA_RADIUS, ARENA_RADIUS + 15.0, au))
	return lerpf(h, 0.0 + _noise.get_noise_2d(d, u) * 0.3, arena)


func fungus_at(d: float, u: float) -> float:
	var progress := clampf(d / 2300.0, 0.0, 1.0)
	var n := _fungus.get_noise_2d(d, u) * 0.5 + 0.5
	return smoothstep(0.8 - progress * 0.14, 0.88 - progress * 0.14, n)


func ground_color(d: float, u: float, h: float, slope: float) -> Color:
	var au := absf(u)
	var half := valley_half_width(d)
	var color := Palette.TEAL
	if au < 5.0:
		color = Palette.CONCRETE
		if absf(au - 2.6) < 0.15 and section_at(d) >= Section.PADDIES:
			color = Palette.CREAM
	elif au > half + 25.0:
		color = Palette.PINE if slope < 0.9 else Palette.MOSS
	elif h > FLOOR + 0.35:
		color = Palette.SAGE
	if fungus_at(d, u) > 0.5 and au > 5.0:
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
