extends Sprite

# onready var camera := $"../Player/Camera"
onready var map := $"../Map/TerrainMap"
# onready var trail := $RocketTrail
onready var label := $Label


# Called when the node enters the scene tree for the first time.
func _ready():
	pass  # Replace with function body.


func _process(_delta):
	# print(camera)
	position = get_global_mouse_position()
	# trail.position = get_global_mouse_position()
	# position = (get_global_mouse_position()  + camera.global_position)
	# position = get_viewport().get_mouse_position()
	var localpos = map.world_to_map(map.to_local(position))
	var tilepos = Vector2(
		clamp(localpos.x, 0, Const.MAPSIZE.x - 1),
		clamp(localpos.y, 0, Const.MAPSIZE.y - 1)
	)
	label.text = str(tilepos, localpos, position)
