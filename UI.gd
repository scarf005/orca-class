extends CanvasLayer

onready var showpaused := $ShowPaused


func _input(event):
	if event.is_action_pressed("ui_fullscreen"):
		OS.window_fullscreen = ! OS.window_fullscreen

	if event is InputEventKey and event.pressed:
		if event.scancode == KEY_ESCAPE:
			get_tree().paused = ! get_tree().paused
			showpaused.visible = get_tree().paused
