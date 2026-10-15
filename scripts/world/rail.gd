class_name Rail
extends RefCounted
## The forward-scrolling frame the player moves within.

enum Mode { RAIL, HOLD, ARENA }

## Tuned live in the duel mode, hence static vars; overdrive and brake keep their ratio to cruise.
static var CRUISE := 105.0 / 3.6 ## 105 km/h.
static var OVERDRIVE := CRUISE * 1.9
static var BRAKE := CRUISE * 0.36


static func set_cruise(kmh: float) -> void:
	CRUISE = kmh / 3.6
	OVERDRIVE = CRUISE * 1.9
	BRAKE = CRUISE * 0.36

## Tuned live in the duel mode, hence static vars.
static var HARD_HIT_SPEED := 0.25 ## Share of cruise a hard building leaves the tank at.
static var HARD_RECOVER := 1.5 ## Seconds the speed cap from a hard building takes to lift.
static var WADE_SPEED := 0.55 ## Share of cruise the speed is capped at in water and mud.

var mode := Mode.RAIL
var d := 0.0
var speed := CRUISE
var throttle := 0 ## -1 brake, 0 cruise, 1 overdrive; what the rail is actually doing.
var hold_at := INF ## In HOLD mode the rail eases to a stop here.
var arena_d := INF: ## In ARENA mode the tank drives freely inside this circle: centre distance along the road (the stage's arena unless set)...
	get: return Course.stage.arena_center_d if arena_d == INF else arena_d
var arena_radius := INF: ## ...and radius.
	get: return Course.stage.arena_radius if arena_radius == INF else arena_radius
var arena_u := INF ## ARENA mode also keeps the tank this near the road's centreline.
var arena_land: Array[Rect2] = [] ## When set, ARENA mode keeps the hull on these (u, d) rectangles; only a dash carries it over a gap.
var wading := false ## The tank is in water or mud: the speed is capped.
var _stop_timer := 0.0
var _since_jolt := INF ## Seconds since the tank hit a hard building.


## `command` is the player's wish: -1 brake, 0 cruise, 1 overdrive.
func advance(delta: float, command: int) -> void:
	throttle = command
	_since_jolt += delta
	var target := CRUISE
	match throttle:
		1: target = OVERDRIVE
		-1: target = BRAKE
	target = minf(target, speed_cap())
	if _stop_timer > 0.0:
		_stop_timer -= delta
		target = 0.0
	if mode == Mode.HOLD:
		target = clampf((hold_at - d) * 0.8, 0.0, CRUISE)
	elif mode == Mode.ARENA:
		target = 0.0
	var rate := 40.0 if target < speed else 14.0
	speed = move_toward(speed, target, rate * delta)
	d += speed * delta


## The tank rammed a hard building: the speed drops at once and the cap lifts over HARD_RECOVER.
func jolt() -> void:
	_since_jolt = 0.0
	speed = minf(speed, speed_cap())


## The fastest the rail may run right now; above overdrive means no cap.
func speed_cap() -> float:
	var hit_speed := lerpf(1.0, HARD_HIT_SPEED, 0.25) if Game.difficulty == Game.Difficulty.EASY else HARD_HIT_SPEED
	var jolted := lerpf(hit_speed * CRUISE, OVERDRIVE + 1.0, clampf(_since_jolt / HARD_RECOVER, 0.0, 1.0))
	var wade := Course.stage.wade_scale if Course.stage != null and Course.stage.wade_scale > 0.0 else WADE_SPEED
	return minf(jolted, wade * CRUISE if wading else INF)


## Anchor stop: the rail halts almost instantly, then resumes.
func anchor_stop(duration: float) -> void:
	_stop_timer = duration
	speed = minf(speed, 2.0)


func forward() -> Vector3:
	return Course.forward(d)


func basis() -> Basis:
	var f := forward()
	return Basis(f.cross(Vector3.UP).normalized(), Vector3.UP, -f).orthonormalized()
