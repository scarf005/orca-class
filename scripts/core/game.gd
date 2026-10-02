extends Node
## Global state: settings, input bindings, personal bests and the current run's options.

const SETTINGS_PATH := "user://settings.cfg"
const BESTS_PATH := "user://bests.cfg"

enum Difficulty { NORMAL, HARD }

## Default bindings. Each entry is a list of InputEvents; keyboard/mouse events are rebindable.
## The keyboard needs only WASD, Space and the mouse: W/S also boost and brake the rail, Space dashes
## toward the held direction (gamepad: shoulder buttons), the left button fires the coax and the right
## charges the main gun. The laser works on its own.
static func default_bindings() -> Dictionary:
	return {
		"move_forward": [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)],
		"move_back": [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)],
		"move_left": [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)],
		"move_right": [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)],
		"aim_up": [_axis(JOY_AXIS_RIGHT_Y, -1.0)],
		"aim_down": [_axis(JOY_AXIS_RIGHT_Y, 1.0)],
		"aim_left": [_axis(JOY_AXIS_RIGHT_X, -1.0)],
		"aim_right": [_axis(JOY_AXIS_RIGHT_X, 1.0)],
		"fire_coax": [_mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
		"fire_cannon": [_mouse(MOUSE_BUTTON_RIGHT), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		"dash": [_key(KEY_SPACE)],
		"roll_left": [_button(JOY_BUTTON_LEFT_SHOULDER)],
		"roll_right": [_button(JOY_BUTTON_RIGHT_SHOULDER)],
		"pause": [_key(KEY_ESCAPE), _button(JOY_BUTTON_START)],
	}

const REBINDABLE: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right", &"fire_coax", &"fire_cannon", &"dash", &"pause"]

## Tools and tests run silent (pass `--sound` to hear them).
var silent := false
var settings := {
	"locale": "ko",
	"master_volume": 0.8,
	"music_volume": 0.7,
	"sfx_volume": 0.9,
	"mouse_sensitivity": 1.0,
	"screen_shake": 1.0,
	"dither": 1.0,
	"bindings": {},
}

var difficulty := Difficulty.NORMAL
## Name of the checkpoint the next stage load starts from; empty means the stage start.
var checkpoint := ""
var bests := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The HUD draws real models as wireframes; meshes only get wireframe data if this is on first.
	RenderingServer.set_debug_generate_wireframes(true)
	load_settings()
	_load_bests()


static func _key(code: Key) -> InputEvent:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event


static func _mouse(button: MouseButton) -> InputEvent:
	var event := InputEventMouseButton.new()
	event.button_index = button
	return event


static func _button(button: JoyButton) -> InputEvent:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


static func _axis(axis: JoyAxis, value: float) -> InputEvent:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	return event


func load_settings() -> void:
	var file := ConfigFile.new()
	if file.load(SETTINGS_PATH) == OK:
		for key in settings:
			settings[key] = file.get_value("settings", key, settings[key])
	apply_settings()


func save_settings() -> void:
	var file := ConfigFile.new()
	for key in settings:
		file.set_value("settings", key, settings[key])
	file.save(SETTINGS_PATH)


func apply_settings() -> void:
	TranslationServer.set_locale(settings.locale)
	_set_bus_volume("Master", settings.master_volume)
	_set_bus_volume("Music", settings.music_volume)
	_set_bus_volume("SFX", settings.sfx_volume)
	var defaults := default_bindings()
	for action: String in defaults:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		InputMap.action_erase_events(action)
		var events: Array = defaults[action]
		var custom: Variant = settings.bindings.get(action)
		if custom is InputEvent:
			# A custom binding replaces the default keyboard/mouse event and keeps the gamepad ones.
			events = events.filter(func(e: InputEvent) -> bool: return e is InputEventJoypadButton or e is InputEventJoypadMotion)
			events.push_front(custom)
		for event: InputEvent in events:
			InputMap.action_add_event(action, event)


func rebind(action: StringName, event: InputEvent) -> void:
	settings.bindings[String(action)] = event
	apply_settings()
	save_settings()


func reset_bindings() -> void:
	settings.bindings = {}
	apply_settings()
	save_settings()


## Display name of the keyboard/mouse binding for an action.
func binding_label(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return OS.get_keycode_string((event as InputEventKey).physical_keycode)
		if event is InputEventMouseButton:
			return tr("MOUSE_%d" % (event as InputEventMouseButton).button_index)
	return "-"


func _set_bus_volume(bus_name: String, value: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(value, 0.0001)))
		AudioServer.set_bus_mute(bus, value <= 0.001 or (silent and bus_name == "Master"))


func _load_bests() -> void:
	var file := ConfigFile.new()
	if file.load(BESTS_PATH) == OK:
		for key in file.get_section_keys("bests"):
			bests[key] = file.get_value("bests", key)


## Records a result if it beats the stored best. Returns true for a new best.
func submit_best(key: String, value: int) -> bool:
	if value <= int(bests.get(key, -1)):
		return false
	bests[key] = value
	var file := ConfigFile.new()
	for k in bests:
		file.set_value("bests", k, bests[k])
	file.save(BESTS_PATH)
	return true


func unlock_checkpoint(name: String) -> void:
	var key := "checkpoint_" + name
	if not bests.has(key):
		submit_best(key, 1)


func is_checkpoint_unlocked(name: String) -> bool:
	return bests.has("checkpoint_" + name)


func best_key(name: String) -> String:
	return "%s_%s" % [name, "hard" if difficulty == Difficulty.HARD else "normal"]
