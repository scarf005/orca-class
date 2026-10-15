class_name MapEditor
extends Control
## Edits a stage's event list on its real course. Fly with WASD (Q/E down/up, Shift fast), look by dragging the
## right mouse button; click the timeline to scrub along the rail. Select a tool, click the ground to add an event;
## with SELECT, click a marker to pick it and drag to move it. Delete removes, SAVE writes
## data/stages/stage<N>.json, PLAY starts the game at the selected event with the edited list, Esc quits.
## Run: just map-editor 3

signal play
signal exit

const SPEED := 60.0
const FAST := 4.0
const LOOK := 0.003
const PICK_PIXELS := 28.0 ## How close a click must be to a marker's pole.
const PICK_STEP := 2.0 ## Metres the ground ray marches per step.
const PICK_REACH := 3000.0
const MARKER_HEIGHT := 12.0
const TOOLS := ["select", "wave", "pickup", "hold", "checkpoint"]
const TYPES := ["wave", "pickup", "hold", "release", "checkpoint", "midboss", "boss", "storm", "sprint", "music", "ambush"]

var stage_number := 1
var events: Array[Dictionary] = []
var world: World
var scenery := Scenery.new()
var timeline := EventTimeline.new()
var _tool := "select"
var _selected := -1
var _yaw := 0.0
var _pitch := -0.4
var _looking := false
var _dragging := false
var _streamed := 0.0
var _markers := Node3D.new()
var _info := Label.new()
var _fields := VBoxContainer.new()
var _materials := {}
var _choices: Dictionary


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _flat_theme()
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED ## Event keys such as CHECKPOINT are also string table keys.
	Game.stage = stage_number
	world = World.new()
	world.stage_number = stage_number
	add_child(world)
	world.camera.far = 1500.0
	world.add_child(scenery)
	scenery.build()
	world.add_child(_markers)
	_choices = {"type": TYPES, "kind": Director.ENEMY_SCRIPTS.keys(), "id": Pickup.IDS}
	events = Course.stage.run_events(false)
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	timeline.events = events
	timeline.length = Course.stage.plan_start + Course.stage.plan.reduce(func(sum: float, piece: Array) -> float: return sum + piece[0], 0.0)
	timeline.scrubbed.connect(scrub)
	timeline.picked.connect(func(index: int) -> void:
		select(index)
		scrub(events[index].d))
	_build_ui()
	scrub(0.0)
	_rebuild()


func _build_ui() -> void:
	var toolbar := HBoxContainer.new()
	for tool_name: String in TOOLS:
		toolbar.add_child(_button(tool_name.to_upper(), func() -> void: _tool = tool_name))
	toolbar.add_child(_button("DELETE", delete_selected))
	toolbar.add_child(_button("SAVE", save))
	toolbar.add_child(_button("PLAY", start_playtest))
	toolbar.add_child(_info)
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.add_child(toolbar)
	add_child(top)
	var side := PanelContainer.new()
	side.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -300.0
	side.offset_top = 40.0
	side.offset_bottom = -timeline.custom_minimum_size.y
	side.add_child(_fields)
	add_child(side)
	timeline.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	timeline.offset_top = -timeline.custom_minimum_size.y
	add_child(timeline)


func _process(delta: float) -> void:
	var camera := world.camera
	if not get_viewport().gui_get_focus_owner() is LineEdit:
		var move := Vector3(_axis(KEY_A, KEY_D), _axis(KEY_Q, KEY_E), _axis(KEY_W, KEY_S))
		camera.global_position += camera.global_basis * move * SPEED * (FAST if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0) * delta
	var d := clampf(Course.to_course(camera.global_position).x, 0.0, timeline.length)
	if d < _streamed - 20.0 or d > _streamed + 400.0:
		scenery.seek(d)
	else:
		scenery.stream(d)
	_streamed = d
	world.rail.d = d
	world.terrain.stream(d)
	timeline.view_d = d
	timeline.queue_redraw()
	var ground := pick_ground(camera.global_position, camera.project_ray_normal(get_viewport().get_mouse_position()))
	_info.text = "  STAGE %d  CAMERA %.0f  CURSOR %.0f %.1f" % [stage_number, d, ground.x, ground.y] if ground.is_finite() else "  STAGE %d  CAMERA %.0f" % [stage_number, d]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_looking = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed and _click(event.position)
			if not event.pressed:
				_dragging = false
	elif event is InputEventMouseMotion:
		if _looking:
			_yaw -= event.relative.x * LOOK
			_pitch = clampf(_pitch - event.relative.y * LOOK, -1.5, 1.5)
			world.camera.rotation = Vector3(_pitch, _yaw, 0.0)
		elif _dragging:
			var ground := pick_ground(world.camera.global_position, world.camera.project_ray_normal(event.position))
			if ground.is_finite():
				StageEvents.place(events[_selected], ground)
				_rebuild()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_DELETE:
			delete_selected()
		elif event.keycode == KEY_ESCAPE:
			StageEvents.playtest = {}
			exit.emit()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


static func _axis(negative: Key, positive: Key) -> float:
	return float(Input.is_physical_key_pressed(positive)) - float(Input.is_physical_key_pressed(negative))


## Course position (d, u) where a ray meets the ground, or Vector2.INF when it never does.
static func pick_ground(from: Vector3, direction: Vector3) -> Vector2:
	var below := from
	for step in int(PICK_REACH / PICK_STEP):
		var at := from + direction * (step * PICK_STEP)
		if at.y > Course.height_at(at):
			below = at
			continue
		for _i in 8:
			var middle := (below + at) * 0.5
			if middle.y > Course.height_at(middle):
				below = middle
			else:
				at = middle
		return Course.to_course(at)
	return Vector2.INF


## Flies the camera to look down the rail at distance `d`.
func scrub(d: float) -> void:
	var camera := world.camera
	camera.global_position = Course.ground_at(d - 30.0, 0.0) + Vector3.UP * 25.0
	camera.look_at(Course.ground_at(d + 30.0, 0.0), Vector3.UP)
	_yaw = camera.rotation.y
	_pitch = camera.rotation.x


## A click on the viewport: selects a marker, or with an add tool puts a new event on the ground. Returns whether a drag may follow.
func _click(at: Vector2) -> bool:
	if _tool == "select":
		var nearest := PICK_PIXELS
		var index := -1
		for i in events.size():
			var top := _marker_position(events[i]) + Vector3.UP * MARKER_HEIGHT
			if not world.camera.is_position_behind(top) and world.camera.unproject_position(top).distance_to(at) < nearest:
				nearest = world.camera.unproject_position(top).distance_to(at)
				index = i
		select(index)
		return index >= 0
	var ground := pick_ground(world.camera.global_position, world.camera.project_ray_normal(at))
	if ground.is_finite():
		events.append(StageEvents.create(_tool, ground))
		select_event(events[-1])
	return false


func select(index: int) -> void:
	_selected = index
	_rebuild()
	_show_fields()


func select_event(event: Dictionary) -> void:
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	for i in events.size():
		if is_same(events[i], event):
			select(i)


func delete_selected() -> void:
	if _selected >= 0:
		events.remove_at(_selected)
		select(-1)


func save() -> void:
	var status := StageEvents.save(stage_number, events)
	_info.text = "  SAVED %s" % StageEvents.path(stage_number) if status == OK else "  SAVE FAILED %s" % error_string(status)


## Starts the game at the selected event, or at the camera's distance, with this list instead of the stage's own.
func start_playtest() -> void:
	StageEvents.playtest = {"stage": stage_number, "events": events.duplicate(true), "d": events[_selected].d if _selected >= 0 else snappedf(timeline.view_d, 1.0)}
	play.emit()


func _marker_position(event: Dictionary) -> Vector3:
	var spot := StageEvents.spot(event)
	return Course.ground_at(spot.x, spot.y) + Vector3.UP * float(event.get("height", 0.0))


## Redraws every marker pole and the timeline after the list or the selection changed.
func _rebuild() -> void:
	for marker in _markers.get_children():
		marker.free()
	for i in events.size():
		var color: Color = EventTimeline.COLORS.get(events[i].type, Palette.LILAC)
		if i == _selected:
			color = Palette.CREAM
		var pole := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.0, MARKER_HEIGHT, 1.0)
		mesh.material = _material(color)
		pole.mesh = mesh
		_markers.add_child(pole)
		pole.global_position = _marker_position(events[i]) + Vector3.UP * MARKER_HEIGHT * 0.5
		var label := Label3D.new()
		label.text = str(events[i].get("kind", events[i].get("id", events[i].get("name", events[i].type))))
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.04
		label.modulate = color
		label.outline_modulate = Palette.INK
		_markers.add_child(label)
		label.global_position = pole.global_position + Vector3.UP * (MARKER_HEIGHT * 0.5 + 2.0)
	timeline.selected = _selected
	timeline.queue_redraw()


func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		_materials[color] = material
	return _materials[color]


## One row per key of the selected event, plus an empty row that adds a key. An emptied value drops the key.
func _show_fields() -> void:
	for row in _fields.get_children():
		row.free()
	if _selected < 0:
		return
	var event := events[_selected]
	for key: String in event.keys():
		_fields.add_child(_row(event, key))
	_fields.add_child(_row(event, ""))


func _row(event: Dictionary, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_field := LineEdit.new()
	name_field.text = key
	name_field.editable = key.is_empty()
	name_field.custom_minimum_size.x = 110.0
	row.add_child(name_field)
	var value: Variant = event.get(key)
	if _choices.has(key):
		var options := OptionButton.new()
		for choice: String in _choices[key]:
			options.add_item(choice)
		options.selected = _choices[key].find(value)
		options.item_selected.connect(func(index: int) -> void: _apply(event, key, _choices[key][index]))
		options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(options)
		return row
	var field := LineEdit.new()
	field.text = "" if value == null else (value if value is String else JSON.stringify(value))
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var commit := func(text: String) -> void: _apply(event, name_field.text, text)
	field.text_submitted.connect(commit)
	field.focus_exited.connect(func() -> void: commit.call(field.text))
	row.add_child(field)
	return row


func _apply(event: Dictionary, key: String, value: Variant) -> void:
	if key.is_empty():
		return
	var json := JSON.new()
	if value is String and json.parse(value) == OK:
		value = json.data
	if event.get(key) == value or (value is String and value.is_empty() and not event.has(key)):
		return
	var shape := event.keys()
	if value is String and value.is_empty():
		event.erase(key)
	else:
		event[key] = value
	var selected := events[_selected]
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.d < b.d)
	_selected = events.find_custom(func(e: Dictionary) -> bool: return is_same(e, selected))
	_rebuild()
	if event.keys() != shape:
		_show_fields()


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button


static func _flat_theme() -> Theme:
	var result := Theme.new()
	var states := {"Button": ["normal", "hover", "pressed", "focus"], "OptionButton": ["normal", "hover", "pressed", "focus"], "LineEdit": ["normal", "focus"], "PanelContainer": ["panel"]}
	for control: String in states:
		for state: String in states[control]:
			var box := StyleBoxFlat.new()
			box.bg_color = Palette.SLATE if state in ["hover", "pressed", "focus"] else Palette.DUSK
			box.set_content_margin_all(4.0)
			result.set_stylebox(state, control, box)
	return result
