extends Node
## Shutdown smoke test: --run=res://tests/shutdown.gd --mode=title|duel


func run() -> int:
	Game.silent = false
	var main := get_parent()
	var mode: String = main.args().get("mode", "title")
	if mode == "duel":
		main.start_game("duel")
	else:
		main.show_title()
	var world: World = main._screen.world
	if world._drop_shadows.get_parent() != world:
		printerr("FAIL: the world must own its shadows before the first frame")
		return 1
	for _i in 3:
		await get_tree().process_frame
	if not Sfx.music.playing:
		printerr("FAIL: shutdown must exercise active music")
		return 1
	print("Shutdown with active audio: ", mode)
	if mode == "duel":
		main.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	else:
		main._screen.quit_requested.emit()
	return 0
