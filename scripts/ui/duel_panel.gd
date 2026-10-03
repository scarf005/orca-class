class_name DuelPanel
extends PanelContainer
## Tab opens live gameplay tuning and pauses the duel.

signal restart_requested

var _tuning := GameTuning.new()
var _grid := GridContainer.new()
var _difficulty := GameTuning.duel_difficulty


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	position = Vector2(16, 50)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.INK, 0.92)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 12)
	# Too many rows for the screen: they scroll, the panel stays inside the view.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, get_viewport_rect().size.y - 100.0)
	scroll.add_child(_grid)
	add_child(scroll)
	for row: Array in _tuning._rows:
		var name := Label.new()
		name.text = row[0]
		name.add_theme_color_override("font_color", Palette.MIST)
		var slider := HSlider.new()
		slider.custom_minimum_size = Vector2(220, 18)
		slider.min_value = row[3]
		slider.max_value = row[4]
		slider.step = row[5]
		slider.focus_mode = Control.FOCUS_NONE # Tab stays the panel's toggle.
		slider.value = row[1].call()
		var value := Label.new()
		value.custom_minimum_size = Vector2(56, 0)
		value.add_theme_color_override("font_color", Palette.BUTTER)
		var text: Callable = row[6] if row.size() > 6 else func(v: float) -> String: return _format(v, row[5], row[4])
		value.text = text.call(slider.value)
		slider.value_changed.connect(func(v: float) -> void:
			row[2].call(v)
			if row[0] == "Round" and World.current != null and World.current.player != null:
				World.current.player.load_round(Director.duel_round)
			if row[0] == "Duel speed (x)" and World.current != null and World.current.director._duel:
				World.current.game_speed = GameTuning.duel_speed
			value.text = text.call(v)
			_tuning.save_values())
		_grid.add_child(name)
		_grid.add_child(slider)
		_grid.add_child(value)


# _input, not _unhandled_input: a focused slider would take Tab for focus navigation first.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		visible = not visible
		get_tree().paused = visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CONFINED_HIDDEN
		get_viewport().set_input_as_handled()
		if not visible and _difficulty != GameTuning.duel_difficulty:
			_difficulty = GameTuning.duel_difficulty
			restart_requested.emit()


static func _format(v: float, step: float, top: float) -> String:
	if top == Enemy.KILL_THROW_UNCAPPED and v >= top:
		return "no cap"
	return str(int(v)) if step >= 1.0 else ("%.3f" % v if step < 0.01 else "%.2f" % v)
