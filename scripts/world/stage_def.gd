class_name StageDef
extends RefCounted
## What differs from stage to stage: road plan, sections, geography, water, encounters, look and
## music. `Course` keeps the road machinery and asks the active stage for everything else.

var number := 1
var plan_start := -500.0 ## Where the road plan begins; the road runs straight before it.
var plan: Array = [] ## [length, turn in degrees] pieces from plan_start.
var section_starts: Array[float] = []
var checkpoints := {"": 0.0} ## Name -> rail distance to start from.
var coax_tiers := {} ## Checkpoint name -> the coax tier a run starts with there.
var start_rws := false ## Whether the tank starts with the RWS fitted.
var city := false ## A street fight: hunters take cover, hold firing spots and walk in from the haze.
var street_level := 0.0 ## Height of the street (or flood) low-flying aircraft keep above.
var standoff := 1.0 ## How far ahead of the tank hunters hold, relative to stage 1.
var wade_scale := 0.0 ## Share of cruise the rail may run at in water; 0 uses the tuned `Rail.WADE_SPEED`.
var water_slows := false ## Whether wading changes how the tank drives.
var midboss_d := 0.0
var arena_center_d := 0.0
var arena_radius := 0.0
var arenas: Array[Dictionary] = [] ## Bounded all-range spaces: {d, radius}.
var structures: Array[Dictionary] = [] ## Solid boxes in the road frame: {kind, d, u, size, y, yaw, variant}.
## Non-colliding skyline blocks behind the front towers: {"d", "u", "size", "variant"}; size.y includes the sunken base.
var backdrop: Array[Dictionary] = []

## The sky, fog and sun.
var sky_top := Color.WHITE
var sky_horizon := Color.WHITE
var sky_ground := Color.WHITE
var ambient := Color.WHITE
var ambient_energy := 0.5
var fog_color := Color.WHITE
var storm_color := Palette.BLUSH ## Fog the storm event thickens the haze to.
var storm_motes: Array[Color] = [Palette.FUNGUS, Palette.BLUSH, Palette.LILAC] ## What drifts across the view in the storm.
var storm_wind := 0.0 ## 0 lets storm motes drift; 1 drives them as fast streaks under a veil (a sand storm).
var fog_begin := 90.0
var fog_end := 420.0
var sun_rotation := Vector3(-32.0, 125.0, 0.0)
var sun_color := Color.WHITE
var sun_energy := 1.0


## The definition of stage `number` (1-based).
static func of(number: int) -> StageDef:
	return [Stage1, Stage2, Stage3][number - 1].new()


func section_at(d: float) -> int:
	var result := 0
	for i in section_starts.size():
		if d >= section_starts[i]:
			result = i
	return result


## The all-range space nearest the current rail hold; stage 1 keeps its original single arena.
func arena_at(d: float) -> Dictionary:
	var result := {"d": arena_center_d, "radius": arena_radius}
	var nearest := INF
	for arena in arenas:
		if absf(arena.d - d) < nearest:
			nearest = absf(arena.d - d)
			result = arena
	return result


## Ground height at course distance d and lateral offset u.
func height(_d: float, _u: float) -> float:
	return 0.0


func ground_color(_d: float, _u: float, _h: float, _slope: float) -> Color:
	return Palette.SAGE


## How overgrown the ground is (0..1).
func fungus_at(_d: float, _u: float) -> float:
	return 0.0


## Half width of the flat valley floor around the road.
func valley_half_width(_d: float) -> float:
	return 34.0


## How far the road is raised onto a highway deck (0..1).
func deck_blend(_d: float) -> float:
	return 0.0


## Maximum tank offset from the road centerline outside an all-range arena.
func lateral_limit(d: float) -> float:
	if deck_blend(d) > 0.5:
		return 12.0
	return maxf(valley_half_width(d) - 4.0, 14.0)


## Where the chase camera rides across the road (its u) while the tank is at `u` at rail distance `d`.
func camera_u(_d: float, u: float) -> float:
	return u * 0.75


## The height of standing water at course position `c` (d, u), or -INF when there is none.
func water_surface(_c: Vector2) -> float:
	return -INF


## The flat surface mesh of the stage's water, or null.
func water_mesh() -> ArrayMesh:
	return null


func events(_hard: bool) -> Array[Dictionary]:
	return []


## Music track for a section; empty leaves the current music (the boss event starts its own).
func music(_section: int) -> String:
	return ""


## Boss theme by phase; stages without a phase change keep the same track.
func boss_music(_phase := 0) -> String:
	return "res://assets/music/boss.ogg"


func fog_tint(_d: float) -> Color:
	return fog_color


func fog_distance(_d: float) -> float:
	return fog_end


## Where the boss appears: above the far side of the arena.
func boss_position() -> Vector3:
	return Course.to_world(arena_center_d + 70.0, 0.0, 45.0)


func in_arena(d: float, margin := 0.0) -> bool:
	for arena in arenas:
		if absf(d - arena.d) < arena.radius + margin:
			return true
	return false


func _structure(kind: String, d: float, u: float, size: Vector3, y: float, variant := 0, yaw := 0.0, tilt := Vector3.ZERO) -> void:
	structures.append({"kind": kind, "d": d, "u": u, "size": size, "y": y, "yaw": yaw, "tilt": tilt, "variant": variant})


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


## 0 before a, ramps to 1 over [a, b], holds, then ramps back to 0 over [c, e].
static func band(x: float, a: float, b: float, c: float, e: float) -> float:
	if x <= a or x >= e:
		return 0.0
	return smoothstep(a, b, x) * (1.0 - smoothstep(c, e, x))


static func make_noise(seed_value: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return noise
