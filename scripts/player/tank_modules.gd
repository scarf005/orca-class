class_name TankModules
extends RefCounted
## War Thunder-style internal modules and reactive armor for the Orca-class.
## Modules degrade to DAMAGED then DESTROYED; the crew field-repairs them one step at a time.
## ERA blocks each stop one shaped-charge warhead from their facing. The tail is tracked by
## `Tail` itself and only comes back from a pickup.

enum State { OK, DAMAGED, DESTROYED }

const MAX := {"track_l": 60.0, "track_r": 60.0, "engine": 70.0, "breech": 60.0, "turret": 60.0, "laser": 40.0}
const ERA := {"front": 4, "left": 3, "right": 3, "rear": 0}
const REPAIR_TIME := 7.0 ## Seconds for the crew to fix one step of damage on a module.

## Which modules a hit from each facing can reach.
const EXPOSED := {
	"front": ["breech", "turret", "track_l", "track_r"],
	"left": ["track_l", "turret", "laser"],
	"right": ["track_r", "turret", "laser"],
	"rear": ["engine", "turret"],
}

var hp := {}
var era := {}
var _repair := {}


func _init() -> void:
	restore()


func restore() -> void:
	for name in MAX:
		hp[name] = MAX[name]
		_repair[name] = 0.0
	era = ERA.duplicate()


func state(name: String) -> State:
	var ratio: float = hp[name] / MAX[name]
	if ratio <= 0.0:
		return State.DESTROYED
	if ratio < 0.5:
		return State.DAMAGED
	return State.OK


## Returns true when the hit knocked the module down a state.
func damage(name: String, amount: float) -> bool:
	var before := state(name)
	hp[name] = maxf(0.0, hp[name] - amount)
	_repair[name] = 0.0
	return state(name) != before


## Field repair: every REPAIR_TIME seconds a hurt module climbs one state.
func update(delta: float) -> void:
	for name in MAX:
		if state(name) == State.OK:
			continue
		_repair[name] += delta
		if _repair[name] >= REPAIR_TIME:
			_repair[name] = 0.0
			hp[name] = MAX[name] * (0.6 if state(name) == State.DAMAGED else 0.3)


func repair_all() -> void:
	for name in MAX:
		hp[name] = MAX[name]
		_repair[name] = 0.0


## Consumes one ERA block on a facing; false when that facing has none left.
func consume_era(facing: String) -> bool:
	if era.get(facing, 0) <= 0:
		return false
	era[facing] -= 1
	return true


func restore_era() -> void:
	era = ERA.duplicate()


func _factor(name: String, damaged: float, destroyed: float) -> float:
	match state(name):
		State.DAMAGED:
			return damaged
		State.DESTROYED:
			return destroyed
	return 1.0


func move_factor() -> float:
	return _factor("track_l", 0.75, 0.5) * _factor("track_r", 0.75, 0.5)


func reload_factor() -> float:
	return _factor("breech", 1.5, 3.0)


func traverse_factor() -> float:
	return _factor("turret", 0.5, 0.2)


func laser_online() -> bool:
	return state("laser") != State.DESTROYED


func overdrive_online() -> bool:
	return state("engine") != State.DESTROYED


func meter_refill_factor() -> float:
	return _factor("engine", 0.5, 0.0)
