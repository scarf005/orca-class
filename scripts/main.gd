extends Node
## Entry point and screen switching. `-- --run=res://path.gd` runs a tool or test script (a Node
## with `run() -> int`) instead of the game; its return value becomes the exit code.

var _screen: Node


func _ready() -> void:
	var script_path := _arg("run")
	if not script_path.is_empty():
		_run_script(script_path)
		return
	if OS.get_cmdline_user_args().has("--play"):
		start_game("")
	elif OS.get_cmdline_user_args().has("--debug-room"):
		_open_debug_room()
	else:
		show_title()


func show_title() -> void:
	_swap(load("res://scripts/ui/title.gd").new())
	_screen.start.connect(start_game)
	_screen.debug_room.connect(_open_debug_room)


func _open_debug_room() -> void:
	var room := DebugRoom.new()
	room.exit.connect(show_title)
	_swap(room)


func start_game(checkpoint: String) -> void:
	Game.checkpoint = checkpoint
	var screen := GameScreen.new()
	screen.checkpoint = checkpoint
	_swap(screen)
	screen.quit_to_title.connect(show_title)
	screen.restart.connect(start_game)


func _swap(screen: Node) -> void:
	if _screen:
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
