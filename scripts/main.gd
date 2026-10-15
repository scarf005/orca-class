extends Node
## Entry point and screen switching. `-- --run=res://path.gd` runs a tool or test script (a Node
## with `run() -> int`) instead of the game; its return value becomes the exit code.

var _screen: Node
var _quitting := false


func _ready() -> void:
	get_tree().auto_accept_quit = false
	var script_path := _arg("run")
	if not script_path.is_empty():
		_run_script(script_path)
		return
	if OS.get_cmdline_user_args().has("--tutorial"):
		_open_tutorial()
	elif OS.get_cmdline_user_args().has("--play"):
		Game.stage = int(_arg("stage")) if not _arg("stage").is_empty() else 1
		start_game(_arg("checkpoint"))
	elif OS.get_cmdline_user_args().has("--map-editor"):
		Game.stage = int(_arg("stage")) if not _arg("stage").is_empty() else 1
		_open_map_editor()
	elif OS.get_cmdline_user_args().has("--duel"):
		start_game("duel")
	elif OS.get_cmdline_user_args().has("--debug-room"):
		_open_debug_room()
	else:
		show_title()


func show_title() -> void:
	StageEvents.playtest = {}
	_swap(load("res://scripts/ui/title.gd").new())
	_screen.start.connect(start_game)
	_screen.debug_room.connect(_open_debug_room)
	_screen.tutorial.connect(_open_tutorial)
	_screen.quit_requested.connect(_quit)


func _open_tutorial() -> void:
	GameTuning.new().load_values()
	var tutorial := Tutorial.new()
	tutorial.exit.connect(show_title)
	tutorial.start.connect(start_game)
	tutorial.restart.connect(_open_tutorial)
	_swap(tutorial)


## The editor's PLAY starts the game with its list; leaving that game returns to the editor with the list intact.
func _open_map_editor() -> void:
	var editor := MapEditor.new()
	editor.stage_number = Game.stage
	editor.hard = StageEvents.playtest.get("hard", false)
	editor.play.connect(start_game.bind(""))
	editor.exit.connect(_quit)
	_swap(editor)


func _open_debug_room() -> void:
	var room := DebugRoom.new()
	room.exit.connect(show_title)
	_swap(room)


func start_game(checkpoint: String) -> void:
	GameTuning.new().load_values()
	Game.checkpoint = checkpoint
	var screen := GameScreen.new()
	screen.checkpoint = checkpoint
	screen.stage = Game.stage
	_swap(screen)
	screen.quit_to_title.connect(show_title if StageEvents.playtest.is_empty() else _open_map_editor)
	screen.restart.connect(start_game)


func _swap(screen: Node) -> void:
	if _screen:
		# Leave the tree first so the old terrain's worker tasks finish before a new stage rebuilds the course.
		remove_child(_screen)
		_screen.queue_free()
	get_tree().paused = false
	Engine.time_scale = 1.0
	_screen = screen
	add_child(screen)


func _run_script(path: String) -> void:
	Game.silent = not OS.get_cmdline_user_args().has("--sound")
	Game.apply_settings()
	var node: Node = load(path).new()
	add_child(node)
	var code: int = await node.run()
	_quit(code)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


func _quit(code := 0) -> void:
	if _quitting:
		return
	_quitting = true
	get_tree().paused = true
	Sfx.stop_all()
	# Real time, not frame time: fixed-FPS tools can outrun the audio thread.
	# Let stopped voices mix out before the server shuts down.
	OS.delay_msec(100)
	get_tree().quit(code)


static func _arg(name: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--%s=" % name):
			return arg.split("=", true, 1)[1]
	return ""


static func args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		result[parts[0]] = parts[1] if parts.size() > 1 else ""
	return result
