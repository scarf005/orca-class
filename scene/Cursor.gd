extends Sprite

# onready var camera := $"../Player/Camera"
onready var map := $"../Map/TerrainMap"
# onready var trail := $RocketTrail
onready var label := $Label


func _process(_delta):
	if map.mouse_in_tilemap:
		position = map.map_to_world(map.selected_tile)
		label.text = str(map.selected_tile)
	else:
		position = get_global_mouse_position() - (Const.TILESIZE / 2)
		label.text = ""
