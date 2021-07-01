extends Sprite


func _input(event):
	if ! event.is_pressed():
		return

	if event.is_action("ui_left"):
		print("left")
	if event.is_action("ui_right"):
		print("right")
	if event.is_action("ui_up"):
		print("up")
	if event.is_action("ui_down"):
		print("down")
