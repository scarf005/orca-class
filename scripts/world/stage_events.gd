class_name StageEvents
extends RefCounted
## A stage's event list as data. `<dir>/stage<N>.json` replaces the coded list of stage N, and the map editor's
## playtest replaces both for one run. Each event's marker spot (d, u) is where it shows up on the course.

const SPAWN_AHEAD := {"wave": 90.0, "pickup": 40.0} ## The director's default `ahead` per event type.
const TEMPLATES := {
	"wave": {"type": "wave", "kind": "fpv", "count": 1, "ahead": 90.0},
	"pickup": {"type": "pickup", "id": "repair", "ahead": 40.0},
	"hold": {"type": "hold", "at": 15.0, "timeout": 30.0},
	"checkpoint": {"type": "checkpoint", "name": "checkpoint"},
}
const SNAP := 0.5 ## Metres an edited position snaps to.

static var dir := "res://data/stages"
## The editor's unsaved list under test: {stage, hard, events, d}, empty outside a playtest.
static var playtest := {}


## Normal and easy share `stage<N>.json`; hard has its own `stage<N>_hard.json`.
static func path(number: int, hard := false) -> String:
	return "%s/stage%d%s.json" % [dir, number, "_hard" if hard else ""]


## The list a run of stage `number` on that difficulty plays instead of the coded one, or null when none is saved.
static func edited(number: int, hard := false) -> Variant:
	if playtest.get("stage", 0) == number and playtest.hard == hard:
		return playtest.events.duplicate(true)
	if not FileAccess.file_exists(path(number, hard)):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path(number, hard)))
	if not parsed is Array:
		push_error("%s is not an event list" % path(number, hard))
		return null
	var events: Array[Dictionary] = []
	events.assign(parsed)
	return events


static func save(number: int, events: Array[Dictionary], hard := false) -> Error:
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path(number, hard), FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(events, "\t") + "\n")
	return OK


## Where the event appears on the course: (d, u) of what it spawns, or of its trigger when it spawns nothing.
static func spot(event: Dictionary) -> Vector2:
	return Vector2(event.d + event.get("ahead", SPAWN_AHEAD.get(event.type, 0.0)), event.get("u", 0.0))


## Moves the event so its spot lies at `at`; keys that are rail distances (`at`, `hold`) move with it.
static func place(event: Dictionary, at: Vector2) -> void:
	var shift := snappedf(at.x - spot(event).x, SNAP)
	event.d += shift
	for key in ["at", "hold"]:
		if event.has(key):
			event[key] += shift
	var u := snappedf(at.y, SNAP)
	if (event.has("u") or SPAWN_AHEAD.has(event.type)) and u != event.get("u", 0.0):
		event["u"] = u


static func create(type: String, at: Vector2) -> Dictionary:
	var event: Dictionary = TEMPLATES[type].duplicate(true)
	event["d"] = 0.0
	place(event, at)
	return event
