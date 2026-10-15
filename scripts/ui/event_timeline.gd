class_name EventTimeline
extends Control
## The map editor's strip along the rail: one tick per event in a lane per kind, the section starts and the camera.
## Click or drag to scrub; click a tick to select its event.

signal scrubbed(d: float)
signal picked(index: int)

const LANES := {"wave": 0, "pickup": 1, "hold": 2, "release": 2}
const LANE_COUNT := 4
const PICK_PIXELS := 5.0
const COLORS := {"wave": Palette.HOSTILE, "pickup": Palette.LOOT, "hold": Palette.AMBER, "release": Palette.AMBER, "checkpoint": Palette.MINT}

var events: Array[Dictionary] = []
var length := 1.0
var selected := -1
var view_d := 0.0 ## Where the camera is.
var _scrubbing := false


func _init() -> void:
	custom_minimum_size.y = 72.0


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.INK)
	for start in Course.stage.section_starts:
		draw_line(Vector2(_x(start), 0.0), Vector2(_x(start), size.y), Palette.DUSK)
	var lane_height := size.y / LANE_COUNT
	for i in events.size():
		var type: String = events[i].type
		var lane: int = LANES.get(type, LANE_COUNT - 1)
		var x := _x(events[i].d)
		draw_rect(Rect2(x - 1.0, lane * lane_height + 2.0, 2.0, lane_height - 4.0), Palette.CREAM if i == selected else COLORS.get(type, Palette.LILAC))
	draw_line(Vector2(_x(view_d), 0.0), Vector2(_x(view_d), size.y), Palette.WHITE)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_scrubbing = event.pressed
		if event.pressed:
			var index := nearest(event.position.x)
			if index >= 0:
				picked.emit(index)
			else:
				scrubbed.emit(_d(event.position.x))
	elif event is InputEventMouseMotion and _scrubbing:
		scrubbed.emit(_d(event.position.x))


## The event whose tick lies within a few pixels of x, or -1.
func nearest(x: float) -> int:
	var best := -1
	var best_distance := PICK_PIXELS
	for i in events.size():
		var distance := absf(_x(events[i].d) - x)
		if distance <= best_distance:
			best = i
			best_distance = distance
	return best


func _x(d: float) -> float:
	return clampf(d / length, 0.0, 1.0) * size.x


func _d(x: float) -> float:
	return clampf(x / maxf(size.x, 1.0), 0.0, 1.0) * length
