extends Sprite

onready var camera := $"../Player/Camera"

var wait := 300


# Called when the node enters the scene tree for the first time.
func _ready():
	pass  # Replace with function body.


func _process(_delta):
	var mpos = get_viewport().get_mouse_position() + camera.global_position
	if wait > 0:
		wait -= 1
	else:
		print(mpos)
		wait = 300
