extends TestCase

const USER_PATH := "user://constants_test.cfg"

class TestMain extends "res://scripts/main.gd":
	func _ready() -> void:
		pass


func _check_defaults(user_config: ConfigFile = null) -> void:
	if not TestCase.is_isolated():
		skip("persistent tuning checks require isolated test storage")
		return
	DirAccess.remove_absolute(USER_PATH)
	if user_config != null:
		check_eq(user_config.save(USER_PATH), OK, "save isolated user settings")
	var defaults := ConfigFile.new()
	check_eq(defaults.load(GameTuning.DEFAULT_PATH), OK, "repository defaults load")
	var tuning := GameTuning.new()
	var originals: Array = []
	for row: Array in tuning._rows:
		originals.append(row[1].call())
		check(defaults.has_section_key("constants", row[0]), "default exists for " + row[0])
	tuning.load_values(USER_PATH)
	for row: Array in tuning._rows:
		var expected: float = defaults.get_value("constants", row[0], originals[tuning._rows.find(row)])
		if user_config != null:
			expected = user_config.get_value("constants", row[0], expected)
		check_near(row[1].call(), expected, 0.0001, "loaded value for " + row[0])
	for i in tuning._rows.size():
		tuning._rows[i][2].call(originals[i])
	DirAccess.remove_absolute(USER_PATH)


func test_missing_user_settings_load_every_repository_default() -> void:
	_check_defaults()


func test_partial_user_settings_override_only_present_keys() -> void:
	var config := ConfigFile.new()
	config.set_value("constants", "ATGM top speed (m/s)", 180.0)
	config.set_value("constants", "helicopter per round", 0.0)
	_check_defaults(config)


func test_full_user_settings_take_precedence() -> void:
	var config := ConfigFile.new()
	var tuning := GameTuning.new()
	for row: Array in tuning._rows:
		config.set_value("constants", row[0], row[3])
	_check_defaults(config)


func test_every_game_start_reloads_all_settings_before_creating_the_world() -> void:
	var tuning := GameTuning.new()
	var originals: Array = []
	for row: Array in tuning._rows:
		originals.append(row[1].call())
	tuning.load_values()
	var expected: Array = []
	for row: Array in tuning._rows:
		expected.append(row[1].call())
	var checkpoint_before := Game.checkpoint
	var mouse_mode := Input.mouse_mode
	for checkpoint: String in ["", "midboss", "boss", "duel", ""]:
		for row: Array in tuning._rows:
			row[2].call(row[3])
		var main := TestMain.new()
		add_child(main)
		main.start_game(checkpoint)
		var screen: GameScreen = main._screen
		for i in tuning._rows.size():
			check_near(tuning._rows[i][1].call(), expected[i], 0.0001, "%s loads %s" % [checkpoint, tuning._rows[i][0]])
		check_eq(screen.world.player.current_round, Director.duel_round if checkpoint == "duel" else Armament.Round.APHE, "only duel starts with the selected round")
		check_near(screen.world.rail.speed, Rail.CRUISE, 0.0001, "rail is constructed with tuned cruise")
		check_eq(screen.find_children("*", "DuelPanel", true, false).size(), 1 if checkpoint == "duel" else 0, "tuning UI stays duel-only")
		main.queue_free()
		await frames(1)
	for i in tuning._rows.size():
		tuning._rows[i][2].call(originals[i])
	Game.checkpoint = checkpoint_before
	Input.mouse_mode = mouse_mode
