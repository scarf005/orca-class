class_name Stage4
extends StageDef
## A downtown the jungle has swallowed: vines and strangler figs hold the towers up, roots buckle the avenue and a
## green canopy closes over the road. Flame crews work the ruins; the last stretch opens on a clearing where the
## tracked fortress comes through the trees.

enum Section { VERGE, RUINS, CANOPY, HOLLOW, CLEARING }

const SECTION_STARTS := [0.0, 700.0, 1700.0, 2900.0, 4100.0]
const LENGTH := 4900.0
const HORIZON_SHIFT := 120.0 ## Squads spawn this much farther out, in the haze, and walk in.
const HULL_MARGIN := 3.0 ## The floor extends this far past the hull limit so the track samples at the edge never hang.
const CLEARING_D := 4500.0
const CLEARING_RADIUS := 110.0
const ENTRY_ANGLE := deg_to_rad(-50.0) ## Where the fortress breaks out of the jungle, seen from the clearing's centre: ahead and to the left.
const STORM_D := 1750.0
const PLAN := [[1000.0, 0.0], [400.0, 25.0], [500.0, -25.0], [400.0, 0.0], [600.0, -35.0], [500.0, 35.0], [400.0, 0.0], [500.0, 30.0], [500.0, -30.0], [700.0, 0.0]]

var _swell := make_noise(81, 0.008)
var _roots := make_noise(83, 0.03)
var _ripple := make_noise(89, 0.09)
var _patch := make_noise(97, 0.05)
var _far := make_noise(101, 0.006)


func _init() -> void:
	number = 4
	city = true
	standoff = 0.6
	plan = PLAN
	section_starts.assign(SECTION_STARTS)
	checkpoints = {"": 0.0, "boss": CLEARING_D - 260.0}
	coax_tiers = {"": 2, "boss": 2}
	arena_center_d = CLEARING_D
	arena_radius = CLEARING_RADIUS
	arenas = [{"d": CLEARING_D, "radius": CLEARING_RADIUS}]
	sky_top = Palette.SKY.lerp(Palette.TEAL, 0.5)
	sky_horizon = Palette.MINT.lerp(Palette.BUTTER, 0.35)
	sky_ground = Palette.SAGE
	# Green light through leaves: the shade falls cool teal, the clearing's sun warm.
	ambient = Palette.TEAL.lerp(Palette.MINT, 0.5)
	ambient_energy = 0.7
	fog_color = Palette.MINT.lerp(Palette.SAGE, 0.5)
	storm_color = Palette.TEAL.lerp(Palette.PINE, 0.4)
	storm_motes = [Palette.LEAF, Palette.SAGE, Palette.MINT]
	fog_begin = 60.0
	fog_end = 330.0
	sun_color = Palette.BUTTER.lerp(Palette.CREAM, 0.4)
	sun_rotation = Vector3(-38.0, 130.0, 0.0)
	sun_energy = 1.0
	_generate_walls()
	_generate_entry()
	_generate_backdrop()


func boss_position() -> Vector3:
	var at := entry_point(95.0)
	return Course.ground_at(at.x, at.y)


## The point on the clearing's rim (in course d, u) where the fortress comes out of the trees, `out` metres past the rim.
func entry_point(out: float) -> Vector2:
	return Vector2(CLEARING_D, 0.0) + Vector2.from_angle(ENTRY_ANGLE) * (CLEARING_RADIUS + out)


func _street_half(d: float) -> float:
	var half := 26.0
	half = lerpf(half, 20.0, band(d, 650.0, 750.0, 1650.0, 1750.0))
	half = lerpf(half, 24.0, band(d, 1700.0, 1800.0, 2850.0, 2950.0))
	half = lerpf(half, 22.0, band(d, 2900.0, 3000.0, 4050.0, 4150.0))
	return half


func lateral_limit(d: float) -> float:
	for arena in arenas:
		if absf(d - arena.d) <= arena.radius:
			return arena.radius - 6.0
	return _street_half(d)


func valley_half_width(d: float) -> float:
	return lateral_limit(d) + 16.0


func _generate_walls() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261020
	var ranges := [[0.0, 700.0], [700.0, 1700.0], [1700.0, 2900.0], [2900.0, 4100.0]]
	var tall := [[8.0, 18.0], [20.0, 42.0], [10.0, 26.0], [22.0, 46.0]]
	for index in ranges.size():
		var section_range: Array = ranges[index]
		for side: float in [-1.0, 1.0]:
			var d: float = float(section_range[0]) + rng.randf_range(0.0, 10.0)
			var along: float = rng.randf_range(16.0, 34.0)
			while d < section_range[1]:
				var across: float = rng.randf_range(18.0, 30.0)
				var visible: float = rng.randf_range(tall[index][0], tall[index][1])
				var setback: float = lateral_limit(d) + HULL_MARGIN + 6.0 + rng.randf_range(0.0, 8.0)
				var next_along: float = rng.randf_range(16.0, 34.0)
				# The jungle has taken some lots whole: an empty plot is a thicket the tank can see across.
				var gap: float = rng.randf_range(0.0, 30.0 if rng.randf() < 0.3 else 12.0)
				var next_d := d + (along + next_along) * 0.5 + gap
				var inside := d - along * 0.5 >= float(section_range[0]) and d + along * 0.5 <= float(section_range[1])
				if inside and not in_arena(d, 10.0 + along * 0.5):
					_structure("jungle_building", d, side * (setback + across * 0.5), Vector3(across, visible + 6.0, along), -6.0, rng.randi_range(0, 15))
				d = next_d
				along = next_along


## Overgrown ruins standing in the fortress's way through the trees: it drives through them on its way in.
func _generate_entry() -> void:
	var across := Vector2.from_angle(ENTRY_ANGLE + PI * 0.5)
	for step in 3:
		for lane: float in [-1.0, 1.0]:
			var at := entry_point(30.0 + 38.0 * step) + across * lane * (12.0 + 4.0 * step)
			_structure("jungle_building", at.x, at.y, Vector3(18.0, 22.0 + 8.0 * step, 20.0), -6.0, step * 2 + int(lane > 0.0))


## Two rows of lower overgrown blocks behind the front towers so the street never ends in a void.
func _generate_backdrop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261021
	for row in 2:
		for side: float in [-1.0, 1.0]:
			var d := rng.randf_range(0.0, 20.0)
			while d < LENGTH - 300.0:
				var along := float(rng.randi_range(0, 2)) * 6.0 + 28.0
				var across := float(rng.randi_range(0, 2)) * 6.0 + 24.0
				var inner := lateral_limit(d) + 36.0 + 45.0 * row + rng.randf_range(0.0, 6.0)
				var roof := float(rng.randi_range(8, 18) if row == 0 else rng.randi_range(14, 30)) * 2.0
				_backdrop(d, side * (inner + across * 0.5), Vector3(across, roof + 4.5, along), rng.randi_range(0, 7))
				d += along + rng.randf_range(0.0, 10.0)


func height(d: float, u: float) -> float:
	var outside := INF
	for arena in arenas:
		var rect := Vector2(maxf(absf(d - arena.d) - (arena.radius + 2.0 * HULL_MARGIN), 0.0), maxf(absf(u) - (arena.radius - 6.0 + HULL_MARGIN), 0.0)).length()
		outside = minf(outside, minf(rect, maxf(Vector2(d - arena.d, u).length() - arena.radius, 0.0)))
	var floor_h := 0.1 + _ripple.get_noise_2d(d, u) * 0.08
	if outside == 0.0:
		return floor_h
	var au := absf(u)
	var limit := lateral_limit(d)
	var ridged := 1.0 - absf(_roots.get_noise_2d(d, u))
	# Root-heaved ground: long gentle swells with tangled ridges, low enough to drive over.
	var h := _swell.get_noise_2d(d, u) * 1.2 + ridged * ridged * 0.5 + _ripple.get_noise_2d(d, u) * 0.1
	# The ground rises into the forest floor behind the towers and rolls away into hills.
	h += smoothstep(limit + HULL_MARGIN, limit + 25.0, au) * 3.0
	h += smoothstep(limit + 25.0, limit + 120.0, au) * (6.0 + 16.0 * (_far.get_noise_2d(d, u) * 0.5 + 0.5))
	return lerpf(floor_h, h, smoothstep(0.0, 24.0, outside)) if outside < INF else h


func ground_color(d: float, u: float, h: float, slope: float) -> Color:
	var au := absf(u)
	var patch := _patch.get_noise_2d(d, u)
	var growth := smoothstep(-0.3, 0.6, patch)
	var floor_color := Palette.PINE.lerp(Palette.MOSS, clampf(slope * 2.0 + smoothstep(0.0, 4.0, h) * 0.3, 0.0, 1.0) * 0.6)
	floor_color = floor_color.lerp(Palette.SAGE, growth * 0.45).lerp(Palette.LEAF, smoothstep(0.55, 0.9, patch) * 0.35)
	for arena in arenas:
		var r := Vector2(d - arena.d, u).length()
		if r < arena.radius + 6.0:
			# The clearing: a cracked concrete plaza under a skin of moss, torn up where the fortress will drive.
			var plaza := Palette.CONCRETE.lerp(Palette.STONE, 0.3 + patch * 0.3).lerp(Palette.SAGE, growth * 0.4)
			return plaza.lerp(floor_color, smoothstep(arena.radius - 10.0, arena.radius + 2.0, r))
	if au < lateral_limit(d) - 2.0:
		# The avenue: cracked asphalt with moss and ferns where the roots have lifted it.
		var tarmac := Palette.STONE.lerp(Palette.ASH, 0.4 + patch * 0.3)
		return tarmac.lerp(floor_color, clampf(growth * 0.8 + smoothstep(6.0, lateral_limit(d), au) * 0.5, 0.0, 1.0))
	return floor_color


func camera_u(d: float, u: float) -> float:
	var reach := lateral_limit(d - ChaseCamera.RAIL_BACK) - 6.0
	return clampf(u * 0.75, -reach, reach)


## Haze that gets greener and thicker as the canopy closes, and opens up on the clearing.
func fog_tint(d: float) -> Color:
	return _section_blend([fog_color, fog_color.lerp(Palette.TEAL, 0.25), fog_color.lerp(Palette.PINE, 0.35), fog_color.lerp(Palette.TEAL, 0.3), fog_color.lerp(Palette.BUTTER, 0.25)], d)


func fog_distance(d: float) -> float:
	match section_at(d):
		Section.VERGE:
			return 380.0
		Section.RUINS:
			return 320.0
		Section.CANOPY:
			return 250.0
		Section.HOLLOW:
			return 300.0
		Section.CLEARING:
			return 420.0
	return fog_end


func _section_blend(colors: Array, d: float) -> Color:
	var section := section_at(d)
	return (colors[maxi(section - 1, 0)] as Color).lerp(colors[section], smoothstep(SECTION_STARTS[section], SECTION_STARTS[section] + 120.0, d))


func music(section: int) -> String:
	match section:
		Section.CLEARING:
			return ""
		Section.CANOPY, Section.HOLLOW:
			return "res://assets/music/stage2_canyon.ogg"
	return "res://assets/music/stage2_boulevard.ogg"


func boss_music(_phase := 0) -> String:
	return "res://assets/music/stage3_boss.ogg"


## Pushes a wave and its squad out to the haze.
func _to_horizon(event: Dictionary) -> void:
	if event.kind == "fpv" and not event.has("ahead"):
		event.ahead = 90.0 # The director's default slot, which would pop the drone up mid-street.
	if event.has("ahead"):
		event.ahead += HORIZON_SHIFT
	for member: Dictionary in event.get("squad", []):
		_to_horizon(member)


func events(hard: bool) -> Array[Dictionary]:
	var e: Array[Dictionary] = []
	var wave := func(d: float, kind: String, extra: Dictionary) -> void:
		var event := {"d": d, "type": "wave", "kind": kind, "hard_scale": 1.0}
		event.merge(extra)
		e.append(event)
	var napalm := {"napalm": true}

	# The verge teaches the flame: one tank, then the walkers, each alone, and bug drones that scatter fire where they fall.
	wave.call(40.0, "fpv", {"height": 5.0, "props": napalm})
	wave.call(230.0, "crocodile", {"u": -10.0, "ahead": 80.0, "drop": "coax"})
	wave.call(430.0, "burner", {"u": 12.0, "ahead": 75.0, "squad": [
		{"kind": "fpv", "height": 5.0, "props": napalm}]})
	e.append({"d": 640.0, "type": "pickup", "id": "atgm"})

	# The ruins crowd the street: flame crews working in pairs under the towers.
	wave.call(760.0, "crocodile", {"u": 10.0, "ahead": 80.0, "squad": [
		{"kind": "ugv", "u": -8.0, "ahead": 75.0, "props": {"weapon": "atgm"}}]})
	wave.call(980.0, "burner", {"u": -12.0, "ahead": 70.0, "peak": true, "drop": "micro", "squad": [
		{"kind": "burner", "u": 12.0, "ahead": 90.0}]})
	wave.call(1220.0, "crocodile", {"u": 0.0, "ahead": 85.0, "squad": [
		{"kind": "fpv", "count": 2, "height": 5.0, "props": napalm}]})
	e.append({"d": 1400.0, "type": "pickup", "id": "micro", "u": -4.0})
	wave.call(1450.0, "burner", {"u": 8.0, "ahead": 70.0, "squad": [
		{"kind": "crocodile", "u": -12.0, "ahead": 95.0}]})
	e.append({"d": 1620.0, "type": "pickup", "id": "repair", "u": 4.0})

	# Under the canopy a monsoon thickens the haze and the fire has nowhere to go but the road.
	e.append({"d": STORM_D, "type": "storm", "duration": 35.0})
	wave.call(1830.0, "crocodile", {"u": -12.0, "ahead": 85.0, "squad": [
		{"kind": "crocodile", "u": 12.0, "ahead": 100.0}]})
	wave.call(2060.0, "burner", {"u": 12.0, "ahead": 70.0, "peak": true, "squad": [
		{"kind": "fpv", "count": 2, "height": 5.0, "props": napalm}]})
	wave.call(2290.0, "crocodile", {"u": 0.0, "ahead": 85.0, "squad": [
		{"kind": "burner", "u": -10.0, "ahead": 95.0}]})
	e.append({"d": 2450.0, "type": "pickup", "id": "era", "u": -4.0})
	wave.call(2560.0, "burner", {"u": -10.0, "ahead": 70.0, "squad": [
		{"kind": "burner", "u": 10.0, "ahead": 85.0},
		{"kind": "ugv", "u": 0.0, "ahead": 100.0, "props": {"weapon": "atgm"}}]})
	e.append({"d": 2780.0, "type": "hold", "at": 2795.0, "timeout": 25.0, "reward": "repair"})

	# The hollow: collapsed overpasses, the densest fire of the stage.
	wave.call(2960.0, "crocodile", {"u": 10.0, "ahead": 85.0, "peak": true, "squad": [
		{"kind": "burner", "u": -12.0, "ahead": 95.0},
		{"kind": "fpv", "count": 2, "height": 5.0, "props": napalm}]})
	wave.call(3220.0, "burner", {"u": 0.0, "ahead": 70.0, "squad": [
		{"kind": "crocodile", "u": -12.0, "ahead": 100.0},
		{"kind": "crocodile", "u": 12.0, "ahead": 115.0}]})
	e.append({"d": 3400.0, "type": "pickup", "id": "atgm", "u": 4.0})
	wave.call(3500.0, "crocodile", {"u": -8.0, "ahead": 85.0, "squad": [
		{"kind": "burner", "count": 2, "u": 10.0, "ahead": 90.0}]})
	wave.call(3780.0, "burner", {"u": 12.0, "ahead": 70.0, "peak": true, "squad": [
		{"kind": "crocodile", "u": -12.0, "ahead": 95.0},
		{"kind": "fpv", "count": 2, "height": 5.0, "props": napalm}]})
	e.append({"d": 3950.0, "type": "hold", "at": 3965.0, "timeout": 25.0, "reward": "repair"})

	# The clearing: refit, then the trees go down.
	e.append({"d": CLEARING_D - 260.0, "type": "checkpoint", "name": "boss"})
	e.append({"d": CLEARING_D - 230.0, "type": "pickup", "id": "repair", "u": -4.0, "ahead": 15.0})
	e.append({"d": CLEARING_D - 200.0, "type": "pickup", "id": "micro", "u": 4.0, "ahead": 15.0})
	e.append({"d": CLEARING_D - 170.0, "type": "pickup", "id": "dragon", "ahead": 15.0})
	e.append({"d": CLEARING_D - 130.0, "type": "boss", "kind": "fortress"})

	if hard:
		for event in e:
			if event.type != "wave" or not event.has("squad"):
				continue
			for member: Dictionary in event.squad:
				member.count = int(member.get("count", 1)) * 2
				member.u = -float(member.get("u", 0.0))
				member.ahead = 65.0
	for event in e:
		if event.type == "wave":
			_to_horizon(event)
	e.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	return e
