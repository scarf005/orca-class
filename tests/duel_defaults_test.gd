extends TestCase

const USER_PATH := "user://duel_defaults_test.cfg"


func _check_defaults(user_config: ConfigFile = null) -> void:
	DirAccess.remove_absolute(USER_PATH)
	if user_config != null:
		check_eq(user_config.save(USER_PATH), OK, "save isolated user settings")
	var defaults := ConfigFile.new()
	check_eq(defaults.load(DuelPanel.DEFAULT_PATH), OK, "repository defaults load")
	var panel := DuelPanel.new()
	var originals: Array = []
	for row: Array in panel._rows:
		originals.append(row[1].call())
		check(defaults.has_section_key("duel", row[0]), "default exists for " + row[0])
	panel.load_values(USER_PATH)
	for row: Array in panel._rows:
		var expected: float = defaults.get_value("duel", row[0], originals[panel._rows.find(row)])
		if user_config != null:
			expected = user_config.get_value("duel", row[0], expected)
		check_near(row[1].call(), expected, 0.0001, "loaded value for " + row[0])
	for i in panel._rows.size():
		panel._rows[i][2].call(originals[i])
	panel._grid.free() # _ready has not parented the grid.
	panel.free()
	DirAccess.remove_absolute(USER_PATH)


func test_missing_user_settings_load_every_repository_default() -> void:
	_check_defaults()


func test_partial_user_settings_override_only_present_keys() -> void:
	var config := ConfigFile.new()
	config.set_value("duel", "ATGM top speed (m/s)", 180.0)
	config.set_value("duel", "helicopter per round", 0.0)
	_check_defaults(config)


func test_full_user_settings_take_precedence() -> void:
	var config := ConfigFile.new()
	var panel := DuelPanel.new()
	for row: Array in panel._rows:
		config.set_value("duel", row[0], row[3])
	panel._grid.free()
	panel.free()
	_check_defaults(config)
