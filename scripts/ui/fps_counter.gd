extends Label
## Render FPS stays visible through screen changes, pause and hitstop.


func _ready() -> void:
	var update := func() -> void: text = tr("HUD_FPS") % Engine.get_frames_per_second()
	update.call()
	var timer := Timer.new()
	timer.wait_time = 0.5
	timer.ignore_time_scale = true
	timer.timeout.connect(update)
	add_child(timer)
	timer.start()
