class_name DuelPanel
extends PanelContainer
## Live tuning for the duel mode: Tab opens sliders for the gun's timing, the hit's weight and the
## hunters each round sends, and pauses the fight. Values are saved to user://duel_tuning.cfg and
## loaded again on the next duel.

const PATH := "user://duel_tuning.cfg"
## [label, getter, setter, min, max, step]
var _rows: Array = [
	["Coax burst (rounds)", func() -> float: return Armament.COAX_BURST_ROUNDS, func(v: float) -> void: Armament.COAX_BURST_ROUNDS = int(v), 1.0, 20.0, 1.0],
	["Tap / lock delay (s)", func() -> float: return Armament.TAP_TIME, func(v: float) -> void: Armament.TAP_TIME = v, 0.0, 0.6, 0.01],
	["Full charge (s)", func() -> float: return Armament.FULL_TIME, func(v: float) -> void: Armament.FULL_TIME = v, 0.3, 3.0, 0.05],
	["Auto fire (s)", func() -> float: return Armament.AUTO_FIRE_TIME, func(v: float) -> void: Armament.AUTO_FIRE_TIME = v, 0.5, 5.0, 0.05],
	["Recover after shot (s)", func() -> float: return Armament.CANNON_RECOVER, func(v: float) -> void: Armament.CANNON_RECOVER = v, 0.0, 2.5, 0.05],
	["Lock radius (px)", func() -> float: return Armament.LOCK_RADIUS, func(v: float) -> void: Armament.LOCK_RADIUS = v, 16.0, 200.0, 2.0],
	["Quick shell speed (m/s)", func() -> float: return Armament.QUICK_SPEED, func(v: float) -> void: Armament.QUICK_SPEED = v, 60.0, 800.0, 10.0],
	["Turret traverse (rad/s)", func() -> float: return Tank.TURRET_RATE, func(v: float) -> void: Tank.TURRET_RATE = v, 2.0, 30.0, 0.5],
	["Gun elevation (rad/s)", func() -> float: return Tank.PITCH_RATE, func(v: float) -> void: Tank.PITCH_RATE = v, 1.0, 30.0, 0.5],
	["Kill throw cap (x)", func() -> float: return Enemy.KILL_THROW_MAX, func(v: float) -> void: Enemy.KILL_THROW_MAX = v, 0.5, Enemy.KILL_THROW_UNCAPPED, 0.5],
	["Dismember speed (m/s)", func() -> float: return Enemy.DISMEMBER_SPEED, func(v: float) -> void: Enemy.DISMEMBER_SPEED = v, 0.0, 200.0, 1.0],
	["Dismember focus by momentum", func() -> float: return Enemy.DISMEMBER_FOCUS, func(v: float) -> void: Enemy.DISMEMBER_FOCUS = v, 0.0, 3.0, 0.05],
	["Blast throw (m/s per dmg)", func() -> float: return Wreck.BLAST_THROW, func(v: float) -> void: Wreck.BLAST_THROW = v, 0.0, 0.3, 0.005],
	["HE blast radius (x)", func() -> float: return Armament.HE_RADIUS_SCALE, func(v: float) -> void: Armament.HE_RADIUS_SCALE = v, 0.5, 4.0, 0.1],
	["Shockwave reach (x blast)", func() -> float: return World.SHOCKWAVE_SCALE, func(v: float) -> void: World.SHOCKWAVE_SCALE = v, 0.5, 5.0, 0.1],
	["Hit weight (x)", func() -> float: return Tank.HIT_WEIGHT, func(v: float) -> void: Tank.HIT_WEIGHT = v, 0.0, 3.0, 0.05],
]
var _grid := GridContainer.new()


func _init() -> void:
	for kind: String in Director.duel_counts:
		_rows.append(["%s per round" % kind, func() -> float: return Director.duel_counts[kind], func(v: float) -> void: Director.duel_counts[kind] = int(v), 0.0, 6.0, 1.0])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	position = Vector2(16, 60)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.INK, 0.92)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 12)
	add_child(_grid)
	load_values()
	for row: Array in _rows:
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
		value.text = _format(slider.value, row[5], row[4])
		slider.value_changed.connect(func(v: float) -> void:
			row[2].call(v)
			value.text = _format(v, row[5], row[4])
			save_values())
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


static func _format(v: float, step: float, top: float) -> String:
	if top == Enemy.KILL_THROW_UNCAPPED and v >= top:
		return "no cap"
	return str(int(v)) if step >= 1.0 else ("%.3f" % v if step < 0.01 else "%.2f" % v)


func save_values() -> void:
	var config := ConfigFile.new()
	for row: Array in _rows:
		config.set_value("duel", row[0], row[1].call())
	config.save(PATH)


func load_values() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	for row: Array in _rows:
		if config.has_section_key("duel", row[0]):
			row[2].call(float(config.get_value("duel", row[0])))
