extends Control
## Title screen: the Orca-class idling under the village's old zelkova, with the main menu.

signal start(checkpoint: String)
signal debug_room
signal quit_requested

const SCENE_D := 575.0

var view := DitherView.new()
var world := World.new()
var font: Font
var _model := TankModel.new()
var _tail := Tail.new()
var _menu: Menu
var _time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = get_theme_default_font()
	add_child(view)
	world.view = view
	world.rail.d = SCENE_D
	view.viewport.add_child(world)
	var scenery := Scenery.new()
	world.add_child(scenery)
	scenery.build()
	scenery.stream(SCENE_D, 100000)
	world.add_child(_model)
	_model.global_position = Course.ground_at(SCENE_D + 6.0, -3.0)
	_model.rotation.y = 0.35
	_model.turret.rotation.y = -0.5
	_model.gun_pivot.rotation.x = 0.12
	_model.set_coax_guns([20, 15])
	_tail.mount = _model.tail_mount
	world.add_child(_tail)
	_show_main()
	Sfx.play_music("res://assets/music/title.ogg")


func _show_main() -> void:
	if _menu:
		_menu.queue_free()
	_menu = Menu.new()
	_menu.center = Vector2(760, 380)
	_menu.width = 300
	_menu.add_item(tr("MENU_START_EASY"), _begin.bind(Game.Difficulty.EASY, ""))
	_menu.add_item(tr("MENU_START_NORMAL"), _begin.bind(Game.Difficulty.NORMAL, ""))
	_menu.add_item(tr("MENU_START_HARD"), _begin.bind(Game.Difficulty.HARD, ""))
	if Game.is_checkpoint_unlocked("midboss"):
		_menu.add_item(tr("MENU_FROM_MIDBOSS"), _begin.bind(Game.Difficulty.NORMAL, "midboss"))
	if Game.is_checkpoint_unlocked("boss"):
		_menu.add_item(tr("MENU_FROM_BOSS"), _begin.bind(Game.Difficulty.NORMAL, "boss"))
	_menu.add_item(tr("MENU_DEBUG_ROOM"), func() -> void: debug_room.emit())
	_menu.add_item(tr("MENU_SETTINGS"), _show_settings)
	if not OS.has_feature("web"):
		_menu.add_item(tr("MENU_QUIT"), func() -> void: quit_requested.emit())
	add_child(_menu)


func _show_settings() -> void:
	_menu.queue_free()
	var settings := SettingsMenu.new()
	settings.center = Vector2(700, 300)
	settings.back.connect(_show_main)
	_menu = settings
	add_child(settings)


func _begin(difficulty: Game.Difficulty, checkpoint: String) -> void:
	Game.difficulty = difficulty
	start.emit(checkpoint)


func _process(delta: float) -> void:
	_time += delta
	# A slow drift around the tank, low and wide, framing the zelkova behind it.
	var center := _model.global_position
	var angle := 2.3 + sin(_time * 0.07) * 0.35
	world.camera.global_position = center + Vector3(cos(angle) * 15.0, 4.0 + sin(_time * 0.2) * 0.4, sin(angle) * 15.0)
	world.camera.look_at(center + Vector3(-5.0, 3.0, 0.0), Vector3.UP)
	world.rail.d = SCENE_D
	_tail.update(delta, _model.global_basis, 0.0)
	_model.turret.rotation.y = -0.5 + sin(_time * 0.4) * 0.25
	queue_redraw()


func _draw() -> void:
	var fade := clampf(_time * 1.5, 0.0, 1.0)
	draw_rect(Rect2(0, 0, 960, 540), Color(Palette.INK, 1.0 - fade))
	var logo := tr("TITLE")
	draw_string(font, Vector2(52, 132), logo, HORIZONTAL_ALIGNMENT_LEFT, -1, 96, Palette.INK)
	draw_string(font, Vector2(48, 128), logo, HORIZONTAL_ALIGNMENT_LEFT, -1, 96, Palette.FUNGUS)
	draw_string(font, Vector2(52, 164), tr("TITLE_SUB"), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Palette.CREAM)
	draw_string(font, Vector2(52, 188), tr("TITLE_TAGLINE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.MIST)
	var best := int(Game.bests.get(Game.best_key("score"), 0))
	if best > 0:
		draw_string(font, Vector2(52, 512), tr("TITLE_BEST") % best, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.BUTTER)
