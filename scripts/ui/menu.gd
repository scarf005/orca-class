class_name Menu
extends Control
## A vertical pixel-art menu driven by keyboard, gamepad or mouse. Items either run an action or
## show a value that left/right adjusts.

signal back

class Item:
	var label := ""
	var action := Callable()
	var value := Callable() ## Returns the displayed value; items with a value can be adjusted.
	var adjust := Callable() ## Called with -1 or 1.
	var enabled := true

var items: Array[Item] = []
var selected := 0
var title := ""
var subtitle := ""
var width := 320.0
var accent := Palette.FUNGUS
var center := Vector2(480, 300)
var font: Font
var _time := 0.0
var _rows: Array[Rect2] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = get_theme_default_font()
	mouse_filter = Control.MOUSE_FILTER_STOP


func add_item(label: String, action := Callable(), enabled := true) -> Item:
	var item := Item.new()
	item.label = label
	item.action = action
	item.enabled = enabled
	items.append(item)
	return item


func add_value(label: String, value: Callable, adjust: Callable) -> Item:
	var item := add_item(label)
	item.value = value
	item.adjust = adjust
	return item


func clear() -> void:
	items.clear()
	selected = 0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _move(step: int) -> void:
	if items.is_empty():
		return
	for _i in items.size():
		selected = posmod(selected + step, items.size())
		if items[selected].enabled:
			break
	Sfx.ui("ui_move")


func _activate() -> void:
	if items.is_empty():
		return
	var item := items[selected]
	if not item.enabled:
		return
	if item.action.is_valid():
		Sfx.ui("ui_select")
		item.action.call()
	elif item.adjust.is_valid():
		item.adjust.call(1)
		Sfx.ui("ui_move")


## Leaves the menu; pages override this to step back first.
func cancel() -> void:
	back.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		for i in _rows.size():
			if _rows[i].has_point(event.position) and i != selected and items[i].enabled:
				selected = i
				Sfx.ui("ui_move")
	elif event is InputEventMouseButton and event.pressed:
		for i in _rows.size():
			if _rows[i].has_point(event.position) and items[i].enabled:
				selected = i
				var item := items[i]
				if item.adjust.is_valid() and not item.action.is_valid():
					item.adjust.call(-1 if event.button_index == MOUSE_BUTTON_RIGHT else 1)
					Sfx.ui("ui_move")
				elif event.button_index == MOUSE_BUTTON_LEFT:
					_activate()
				accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_down"):
		_move(1)
	elif event.is_action_pressed("ui_up"):
		_move(-1)
	elif event.is_action_pressed("ui_accept"):
		_activate()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		var item := items[selected] if not items.is_empty() else null
		if item and item.adjust.is_valid():
			item.adjust.call(-1 if event.is_action_pressed("ui_left") else 1)
			Sfx.ui("ui_move")
	elif event.is_action_pressed("ui_cancel"):
		cancel()
	else:
		return
	get_viewport().set_input_as_handled()


func _draw() -> void:
	var row_h := 22.0
	var height := items.size() * row_h + (44.0 if not title.is_empty() else 12.0) + (16.0 if not subtitle.is_empty() else 0.0)
	var top := center.y - height * 0.5
	var rect := Rect2(center.x - width * 0.5, top, width, height)
	draw_rect(rect, Color(Palette.INK, 0.9))
	draw_rect(Rect2(rect.position, Vector2(width, 3)), accent)
	draw_rect(rect, Palette.DUSK, false, 1.0)
	var y := top + 12.0
	if not title.is_empty():
		_center_text(title, y + 16.0, Palette.CREAM, 24)
		y += 34.0
	if not subtitle.is_empty():
		_center_text(subtitle, y + 6.0, Palette.MIST, 12)
		y += 16.0
	_rows.clear()
	for i in items.size():
		var item := items[i]
		var row := Rect2(rect.position.x + 8, y, width - 16, row_h - 2)
		_rows.append(row)
		var chosen := i == selected
		if chosen:
			draw_rect(row, Color(accent, 0.25))
			var bob := sin(_time * 8.0) * 2.0
			draw_colored_polygon(PackedVector2Array([Vector2(row.position.x + 4 + bob, y + 5), Vector2(row.position.x + 10 + bob, y + 10), Vector2(row.position.x + 4 + bob, y + 15)]), accent)
		var color := Palette.CREAM if chosen else Palette.MIST
		if not item.enabled:
			color = Palette.STONE
		draw_string(font, Vector2(row.position.x + 16, y + 15), item.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
		if item.value.is_valid():
			var value := str(item.value.call())
			var text := ("‹ %s ›" % value) if chosen else value
			var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, Vector2(row.end.x - 8 - text_width, y + 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.BUTTER if chosen else Palette.MIST)
		y += row_h


func _center_text(text: String, y: float, color: Color, size: int) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(center.x - w * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
