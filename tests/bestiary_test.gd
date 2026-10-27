extends TestCase
## The encyclopedia shows every enemy from the first launch, each with a name, a description and readable stats.


func _page() -> Bestiary:
	var page := Bestiary.new()
	add_child(page)
	return page


func test_every_spawnable_enemy_is_listed_exactly_once() -> void:
	var listed := Bestiary.KINDS.duplicate()
	listed.sort()
	var spawnable := Director.ENEMY_SCRIPTS.keys()
	spawnable.sort()
	check_eq(listed, spawnable, "the list holds each enemy the director can spawn, once")


func test_every_entry_has_a_name_and_description_in_both_languages() -> void:
	var locale := TranslationServer.get_locale()
	for language in ["ko", "en"]:
		TranslationServer.set_locale(language)
		for kind: String in Bestiary.KINDS:
			var key: String = Bestiary.NAME_KEYS.get(kind, "ENEMY_" + kind.to_upper())
			check(tr(key) != key, "%s has a %s name" % [kind, language])
			check(tr("DEX_" + kind.to_upper()) != "DEX_" + kind.to_upper(), "%s has a %s description" % [kind, language])
	TranslationServer.set_locale(locale)


func test_each_entry_shows_a_posed_enemy_with_its_own_stats() -> void:
	var page := _page()
	for i in Bestiary.KINDS.size():
		page._show(i)
		check(is_instance_valid(page._enemy) and page._enemy.max_hp > 0.0, "%s is posed with health" % Bestiary.KINDS[i])
		check_eq(page._stats().size(), 4, "%s lists health, armor, score and movement" % Bestiary.KINDS[i])
	page.queue_free()


func test_stats_match_the_enemy_on_every_difficulty() -> void:
	var difficulty := Game.difficulty
	var shown: Array[String] = []
	for level in [Game.Difficulty.NORMAL, Game.Difficulty.EASY]:
		Game.difficulty = level
		var page := _page()
		page._show(Bestiary.KINDS.find("ugv"))
		shown.append(" ".join(page._stats()))
		page.queue_free()
	Game.difficulty = difficulty
	check_eq(shown[1], shown[0], "Easy's reduced health and armor do not change the page")
