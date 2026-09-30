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
var midboss_d := 0.0
var arena_center_d := 0.0
var arena_radius := 0.0

## The sky, fog and sun.
var sky_top := Color.WHITE
var sky_horizon := Color.WHITE
var sky_ground := Color.WHITE
var ambient := Color.WHITE
var ambient_energy := 0.5
var fog_color := Color.WHITE
var fog_begin := 90.0
var fog_end := 420.0
var sun_rotation := Vector3(-32.0, 125.0, 0.0)
var sun_color := Color.WHITE
var sun_energy := 1.0


func section_at(d: float) -> int:
	var result := 0
	for i in section_starts.size():
		if d >= section_starts[i]:
			result = i
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


## The height of standing water at course position `c` (d, u), or -INF when there is none.
func water_surface(_c: Vector2) -> float:
	return -INF


## Flat meshes over the stage's deep water, built at height 0; `water_level` lifts each to its surface.
func water_meshes() -> Array[ArrayMesh]:
	return []


func water_level(_index: int) -> float:
	return 0.0


## Whether the ground is mud at course position (d, u): the tank keeps sliding on it.
func mud_at(_d: float, _u: float) -> bool:
	return false


func events(_hard: bool) -> Array[Dictionary]:
	return []


## Music track for a section; empty leaves the current music (the boss event starts its own).
func music(_section: int) -> String:
	return ""


## Where the boss appears: above the far side of the arena.
func boss_position() -> Vector3:
	return Course.to_world(arena_center_d + 70.0, 0.0, 45.0)


## 0 before a, ramps to 1 over [a, b], holds, then ramps back to 0 over [c, e].
static func band(x: float, a: float, b: float, c: float, e: float) -> float:
	return smoothstep(a, b, x) * (1.0 - smoothstep(c, e, x))


static func make_noise(seed_value: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return noise
