class_name Rail
extends RefCounted
## The forward-scrolling frame the player moves within. Overdrive and brake share one meter.

enum Mode { RAIL, HOLD, ARENA }

## Tuned live in the duel mode, hence static vars; overdrive and brake keep their ratio to cruise.
static var CRUISE := 105.0 / 3.6 ## 105 km/h.
static var OVERDRIVE := CRUISE * 1.9
static var BRAKE := CRUISE * 0.36


static func set_cruise(kmh: float) -> void:
	CRUISE = kmh / 3.6
	OVERDRIVE = CRUISE * 1.9
	BRAKE = CRUISE * 0.36
const METER_DRAIN := 0.45 ## Per second while boosting or braking.
const METER_REFILL := 0.3

## Tuned live in the duel mode, hence static vars.
static var HARD_HIT_SPEED := 0.25 ## Share of cruise a hard building leaves the tank at.
static var HARD_RECOVER := 1.5 ## Seconds the speed cap from a hard building takes to lift.
static var WADE_SPEED := 0.55 ## Share of cruise the speed is capped at in water and mud.

var mode := Mode.RAIL
var d := 0.0
var speed := CRUISE
var meter := 1.0
var throttle := 0 ## -1 brake, 0 cruise, 1 overdrive; what the rail is actually doing.
var hold_at := INF ## In HOLD mode the rail eases to a stop here.
var wading := false ## The tank is in water or mud: the speed is capped.
var _meter_locked := false
var _stop_timer := 0.0
var _since_jolt := INF ## Seconds since the tank hit a hard building.


## `command` is the player's wish: -1 brake, 0 cruise, 1 overdrive.
func advance(delta: float, command: int, refill := 1.0) -> void:
	if meter <= 0.0:
		_meter_locked = true
	elif meter > 0.35:
		_meter_locked = false
	throttle = command if not _meter_locked else 0
	_since_jolt += delta
	if throttle != 0:
		meter = maxf(0.0, meter - METER_DRAIN * delta)
	else:
		meter = minf(1.0, meter + METER_REFILL * refill * delta)
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
	var jolted := lerpf(HARD_HIT_SPEED * CRUISE, OVERDRIVE + 1.0, clampf(_since_jolt / HARD_RECOVER, 0.0, 1.0))
	return minf(jolted, WADE_SPEED * CRUISE if wading else INF)


## Anchor stop: the rail halts almost instantly, then resumes.
func anchor_stop(duration: float) -> void:
	_stop_timer = duration
	speed = minf(speed, 2.0)


func is_meter_locked() -> bool:
	return _meter_locked


func forward() -> Vector3:
	return Course.forward(d)


func basis() -> Basis:
	var f := forward()
	return Basis(f.cross(Vector3.UP).normalized(), Vector3.UP, -f).orthonormalized()
