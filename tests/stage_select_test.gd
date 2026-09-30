extends TestCase
## Stage cards remain usable from a fresh save with every supported input family.

var _saved_bests := {}
var _saved_path := ""
var _title: Control

func begin(name: String) -> void:
	super.begin(name)
	seed(11)
	_saved_bests = Game.bests
	_saved_path = Game.bests_path
	Game.bests = {}
	Game.bests_path = "user://stage_select_test.cfg"
	DirAccess.remove_absolute(Game.bests_path)

func cleanup() -> void:
	if is_instance_valid(_title):
		remove_child(_title)
		_title.queue_free()
		_title = null
	DirAccess.remove_absolute(Game.bests_path)
	Game.bests = _saved_bests
	Game.bests_path = _saved_path
	Game.stage = 1
	Game.difficulty = Game.Difficulty.NORMAL
	super.cleanup()

func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event

func _pad(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	return event

func _click(point: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event

func test_stage_maps_preserve_the_dither_palette_at_native_size() -> void:
	for number in [1, 2]:
		var image := Image.new()
		check_eq(image.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/ui/stage%d.png" % number)), OK, "stage map PNG loads")
		check_eq(image.get_size(), Vector2i(256, 256), "stage map has its final native size")
		var colors := {}
		for y in image.get_height():
			for x in image.get_width():
				colors[image.get_pixel(x, y)] = true
		for color: Color in colors:
			var matched := false
			for palette_color: Color in Palette.ALL:
				# Account for the PNG's 8-bit channels, not post-capture interpolation.
				if absf(color.r - palette_color.r) <= 1.1 / 255.0 and absf(color.g - palette_color.g) <= 1.1 / 255.0 and absf(color.b - palette_color.b) <= 1.1 / 255.0:
					matched = true
					break
			check(matched, "stage %d map color %s comes from the game's palette" % [number, color])
			if not matched:
				break

func test_fresh_save_starts_both_stages_in_both_difficulties() -> void:
	for difficulty in [Game.Difficulty.NORMAL, Game.Difficulty.HARD]:
		for number in [1, 2]:
			_title = load("res://scripts/ui/title.gd").new()
			add_child(_title)
			await frames(2)
			var started := []
			_title.start.connect(func(checkpoint: String) -> void: started.append([checkpoint, Game.stage, Game.difficulty]))
			var menu := _title._menu as Menu
			if difficulty == Game.Difficulty.HARD:
				menu._unhandled_input(_key(KEY_DOWN))
			menu._unhandled_input(_key(KEY_ENTER))
			var select := _title._menu as StageSelect
			check(select != null, "sortie opens the stage cards")
			select._unhandled_input(_key(KEY_D if number == 2 else KEY_A))
			select._unhandled_input(_key(KEY_SPACE))
			check_eq(started, [["", number, difficulty]], "fresh-save stage %d starts with difficulty %d" % [number, difficulty])
			remove_child(_title)
			_title.queue_free()
			_title = null
			await frames(1)
			var world := stage("", false, number)
			check_eq(world.stage_number, number, "the chosen course starts")
			check(world.stats.ranked, "a full-stage sortie is ranked")
			check_eq(Game.difficulty, difficulty, "difficulty survives loading the world")
			remove_child(_world)
			_world.queue_free()
			_world = null
			await frames(1)

func test_mouse_and_gamepad_back_return_to_the_main_menu() -> void:
	_title = load("res://scripts/ui/title.gd").new()
	add_child(_title)
	await frames(2)
	(_title._menu as Menu)._unhandled_input(_key(KEY_ENTER))
	await frames(2)
	var select := _title._menu as StageSelect
	select._gui_input(_click(select._back_rect.get_center()))
	check(_title._menu is Menu, "clicking Back restores the main menu")
	(_title._menu as Menu)._unhandled_input(_key(KEY_ENTER))
	(_title._menu as StageSelect)._unhandled_input(_pad(JOY_BUTTON_B))
	check(_title._menu is Menu, "gamepad B restores the main menu")

func test_mouse_cards_and_checkpoints_follow_the_focused_stage() -> void:
	_title = load("res://scripts/ui/title.gd").new()
	add_child(_title)
	await frames(2)
	(_title._menu as Menu)._unhandled_input(_key(KEY_ENTER))
	var select := _title._menu as StageSelect
	await frames(2)
	var started := []
	_title.start.connect(func(checkpoint: String) -> void: started.append([checkpoint, Game.stage, Game.difficulty]))
	var hover := InputEventMouseMotion.new()
	hover.position = Vector2(StageSelect.CARD_LEFT + StageSelect.CARD_SIZE.x + StageSelect.CARD_GAP + 50, StageSelect.CARD_TOP + 50)
	select._gui_input(hover)
	check_eq(select.selected_stage, 2, "mouse hover focuses the second square")
	select._gui_input(_click(hover.position))
	check_eq(started, [["", 2, Game.Difficulty.NORMAL]], "clicking the second square starts stage two")
	Game.stage = 1
	Game.unlock_checkpoint("boss")
	check(select._checkpoints().is_empty(), "stage one's unlock does not expose stage two's checkpoints")
	Game.stage = 2
	Game.unlock_checkpoint("midboss")
	await frames(2)
	check_eq(select._checkpoint_rows.size(), 1, "only the unlocked checkpoint is drawn")
	select._gui_input(_click(Vector2(230, 400)))
	check_eq(started.back(), ["midboss", 2, Game.Difficulty.NORMAL], "mouse checkpoint click starts the focused stage's checkpoint")
	select._unhandled_input(_pad(JOY_BUTTON_DPAD_LEFT))
	check_eq(select.selected_stage, 1, "d-pad left focuses stage one")
	select._unhandled_input(_pad(JOY_BUTTON_DPAD_RIGHT))
	check_eq(select.selected_stage, 2, "d-pad right focuses stage two")
	remove_child(_title)
	_title.queue_free()
	_title = null
	await frames(1)
	check(not stage("midboss", false, 2).stats.ranked, "checkpoint sorties remain unranked")
