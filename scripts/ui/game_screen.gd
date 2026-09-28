class_name GameScreen
extends Control
## One play session: the dithered 3D view, HUD, and the pause, game over and results overlays.

signal quit_to_title
signal restart(checkpoint: String)

var view := DitherView.new()
var world := World.new()
var hud := Hud.new()
var checkpoint := ""
var _reached_checkpoint := ""
var _overlay: Menu
var _results: Results
var _storm_time := 0.0
var _storm_total := 0.0
var _finished := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The screen keeps handling pause input while the world and HUD are paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(view)
	world.view = view
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	view.viewport.add_child(world)
	world.start_stage(checkpoint)
	_reached_checkpoint = checkpoint
	hud.world = world
	add_child(hud)
	world.director.storm.connect(_on_storm)
	world.director.checkpoint_reached.connect(func(name: String) -> void:
		_reached_checkpoint = name
		Game.unlock_checkpoint(name))
	world.game_over.connect(_on_game_over)
	world.stage_cleared.connect(_on_cleared)
	hud.shout(tr("SHOUT_MISSION_START"), Palette.AMBER, 2.0)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if OS.has_feature("web") else Input.MOUSE_MODE_CONFINED_HIDDEN


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:
	if _storm_time > 0.0:
		_storm_time -= delta
		var k := clampf(minf(_storm_time, _storm_total - _storm_time) / 2.0, 0.0, 1.0)
		world.environment.fog_depth_end = lerpf(420.0, 110.0, k)
		world.environment.fog_depth_begin = lerpf(90.0, 20.0, k)
		world.environment.fog_light_color = Color("f3d9d0").lerp(Palette.BLUSH, k)
		hud.set_storm(k)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _finished:
		if get_tree().paused:
			_close_overlay()
		else:
			_open_pause()
		get_viewport().set_input_as_handled()


func _on_storm(duration: float) -> void:
	_storm_time = duration
	_storm_total = duration


func _open_pause() -> void:
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var menu := Menu.new()
	menu.title = tr("MENU_PAUSED")
	menu.add_item(tr("MENU_RESUME"), _close_overlay)
	menu.add_item(tr("MENU_RESTART"), func() -> void: restart.emit(checkpoint))
	menu.add_item(tr("MENU_SETTINGS"), _open_settings)
	menu.add_item(tr("MENU_QUIT_TITLE"), func() -> void: quit_to_title.emit())
	menu.back.connect(_close_overlay)
	_show_overlay(menu)


func _open_settings() -> void:
	var settings := SettingsMenu.new()
	settings.back.connect(_open_pause)
	_show_overlay(settings)


func _show_overlay(menu: Menu) -> void:
	if _overlay:
		_overlay.queue_free()
	_overlay = menu
	add_child(menu)


func _close_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if OS.has_feature("web") else Input.MOUSE_MODE_CONFINED_HIDDEN


func _on_game_over() -> void:
	_finished = true
	await get_tree().create_timer(2.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var menu := Menu.new()
	menu.title = tr("GAME_OVER")
	menu.accent = Palette.RED
	menu.subtitle = tr("GAME_OVER_SCORE") % world.stats.score
	if not _reached_checkpoint.is_empty():
		menu.add_item(tr("MENU_CONTINUE_CHECKPOINT"), func() -> void: restart.emit(_reached_checkpoint))
	menu.add_item(tr("MENU_RESTART_STAGE"), func() -> void: restart.emit(""))
	menu.add_item(tr("MENU_QUIT_TITLE"), func() -> void: quit_to_title.emit())
	_show_overlay(menu)
	get_tree().paused = true


func _on_cleared() -> void:
	_finished = true
	hud.shout(tr("SHOUT_MISSION_COMPLETE"), Palette.FUNGUS, 2.5)
	await get_tree().create_timer(2.2).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.player.input_enabled = false
	_results = Results.new()
	_results.stats = world.stats
	_results.retry.connect(func() -> void: restart.emit(""))
	_results.title_pressed.connect(func() -> void: quit_to_title.emit())
	add_child(_results)
