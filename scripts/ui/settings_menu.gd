class_name SettingsMenu
extends Menu
## Settings and key rebinding. Emits `back` when the player leaves the top page.

var _capturing := &""
var _page := "main"


func _ready() -> void:
	super()
	accent = Palette.SKY
	_show_main()


func cancel() -> void:
	if _page == "controls":
		_show_main()
		selected = items.size() - 2
	else:
		back.emit()


func _percent(key: String) -> Callable:
	return func() -> String: return "%d%%" % roundi(Game.settings[key] * 100.0)


func _step(key: String, step: float, lo: float, hi: float) -> Callable:
	return func(dir: int) -> void:
		Game.settings[key] = clampf(snappedf(Game.settings[key] + dir * step, 0.01), lo, hi)
		Game.apply_settings()
		Game.save_settings()


func _show_main() -> void:
	_page = "main"
	clear()
	title = tr("MENU_SETTINGS")
	subtitle = ""
	add_value(tr("SET_LANGUAGE"), func() -> String: return tr("LANGUAGE_NAME"), func(_dir: int) -> void:
		Game.settings.locale = "en" if Game.settings.locale == "ko" else "ko"
		Game.apply_settings()
		Game.save_settings()
		_show_main())
	add_value(tr("SET_MASTER"), _percent("master_volume"), _step("master_volume", 0.1, 0.0, 1.0))
	add_value(tr("SET_MUSIC"), _percent("music_volume"), _step("music_volume", 0.1, 0.0, 1.0))
	add_value(tr("SET_SFX"), _percent("sfx_volume"), _step("sfx_volume", 0.1, 0.0, 1.0))
	add_value(tr("SET_SENSITIVITY"), _percent("mouse_sensitivity"), _step("mouse_sensitivity", 0.1, 0.3, 3.0))
	add_value(tr("SET_SHAKE"), _percent("screen_shake"), _step("screen_shake", 0.25, 0.0, 1.5))
	add_value(tr("SET_DITHER"), _percent("dither"), _step("dither", 0.25, 0.0, 1.0))
	add_item(tr("SET_CONTROLS"), _show_controls)
	add_item(tr("MENU_BACK"), cancel)


func _show_controls() -> void:
	_page = "controls"
	clear()
	title = tr("SET_CONTROLS")
	subtitle = tr("SET_REBIND_HELP")
	for action in Game.REBINDABLE:
		var item := add_item(tr("ACTION_" + String(action).to_upper()), _capture.bind(action))
		item.value = func() -> String: return tr("PRESS_KEY") if _capturing == action else Game.binding_label(action)
	add_item(tr("SET_RESET_BINDINGS"), func() -> void: Game.reset_bindings())
	add_item(tr("MENU_BACK"), _show_main)


func _capture(action: StringName) -> void:
	_capturing = action


func _input(event: InputEvent) -> void:
	if _capturing == &"":
		return
	var accepted: bool = event is InputEventKey or (event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2])
	if not accepted or not event.is_pressed():
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE and _capturing != &"pause":
		_capturing = &""
		return
	var bound: InputEvent
	if event is InputEventKey:
		var key := InputEventKey.new()
		key.physical_keycode = (event as InputEventKey).physical_keycode
		bound = key
	else:
		var button := InputEventMouseButton.new()
		button.button_index = (event as InputEventMouseButton).button_index
		bound = button
	Game.rebind(_capturing, bound)
	_capturing = &""
	Sfx.ui("ui_select")
