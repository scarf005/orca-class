extends TestCase
## Every translation key used by the code exists in Korean and English.

## Families built by concatenation (e.g. "PICKUP_" + id) are checked explicitly below.
const KEY_PATTERNS := ["\"title\", \"([A-Z0-9_]+)\"", "\"key\": \"([A-Z0-9_]+)\""]
const TR_LITERAL := "\"([A-Z][A-Z0-9_]*)\""
const STYLE_LITERAL_PATTERNS := ["style_event\\(\"([A-Z0-9_]+)\"", "trick\\s*=\\s*\"([A-Z0-9_]+)\""]


func test_all_keys_translated() -> void:
	var table := {}
	var file := FileAccess.open("res://i18n/strings.csv", FileAccess.READ)
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() >= 3 and not row[0].is_empty():
			table[row[0]] = row
	var used := {}
	var style_names := {}
	for path in _scripts("res://scripts"):
		var text := FileAccess.get_file_as_string(path)
		for pattern in KEY_PATTERNS:
			var regex := RegEx.create_from_string(pattern)
			for m in regex.search_all(text):
				used[m.get_string(1)] = path
		# Extract every literal inside a tr(...) expression, including both arms of conditionals.
		var tr_regex := RegEx.create_from_string("tr\\(([^\\)]*)\\)")
		var literal_regex := RegEx.create_from_string(TR_LITERAL)
		for expression in tr_regex.search_all(text):
			for literal in literal_regex.search_all(expression.get_string(1)):
				used[literal.get_string(1)] = path
		for pattern in STYLE_LITERAL_PATTERNS:
			var style_regex := RegEx.create_from_string(pattern)
			for m in style_regex.search_all(text):
				style_names[m.get_string(1)] = path
	for style in style_names:
		used["STYLE_" + style] = style_names[style]
	for key in used:
		if key.ends_with("_"):
			continue # A concatenated family is checked from its authoritative IDs below.
		check(table.has(key), "%s used in %s is missing" % [key, used[key]])
		if table.has(key):
			check(not table[key][1].is_empty() and not table[key][2].is_empty(), "%s has both languages" % key)
	for i in 6:
		check(table.has("SECTION_%d" % i), "section %d named" % i)
	for id in Pickup.IDS:
		check(table.has("PICKUP_" + id.to_upper()), "pickup %s named" % id)
	for round_id in Armament.ROUND_IDS.values():
		check(table.has("ROUND_" + round_id.to_upper()), "round %s named" % round_id)
	for action in Game.REBINDABLE:
		check(table.has("ACTION_" + String(action).to_upper()), "action %s named" % action)


func test_language_switch() -> void:
	var previous: String = Game.settings.locale
	Game.settings.locale = "en"
	Game.apply_settings()
	check_eq(tr("SECTION_1"), "VILLAGE", "English")
	Game.settings.locale = "ko"
	Game.apply_settings()
	check_eq(tr("SECTION_1"), "마을", "Korean")
	Game.settings.locale = previous
	Game.apply_settings()


func _scripts(dir: String) -> Array[String]:
	var result: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			result.append(dir + "/" + file)
	for sub in DirAccess.get_directories_at(dir):
		result.append_array(_scripts(dir + "/" + sub))
	return result
