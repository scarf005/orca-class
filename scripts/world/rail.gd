class_name Rail
extends RefCounted
## The forward-scrolling frame the player moves within. Overdrive and brake share one meter.

enum Mode { RAIL, HOLD, ARENA }

const CRUISE := 13.0
const OVERDRIVE := 25.0
const BRAKE := 4.5
const METER_DRAIN := 0.45 ## Per second while boosting or braking.
const METER_REFILL := 0.3

var mode := Mode.RAIL
var d := 0.0
var speed := CRUISE
var meter := 1.0
var throttle := 0 ## -1 brake, 0 cruise, 1 overdrive; what the rail is actually doing.
var hold_at := INF ## In HOLD mode the rail eases to a stop here.
var _meter_locked := false
var _stop_timer := 0.0


## `command` is the player's wish: -1 brake, 0 cruise, 1 overdrive.
func advance(delta: float, command: int, refill := 1.0) -> void:
	if meter <= 0.0:
		_meter_locked = true
	elif meter > 0.35:
		_meter_locked = false
	throttle = command if not _meter_locked else 0
	if throttle != 0:
		meter = maxf(0.0, meter - METER_DRAIN * delta)
	else:
		meter = minf(1.0, meter + METER_REFILL * refill * delta)
	var target := CRUISE
	match throttle:
		1: target = OVERDRIVE
		-1: target = BRAKE
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
