extends Sprite

# onready var camera := $"../Player/Camera"
onready var map := $"../Map/TerrainMap"
# onready var trail := $RocketTrail
onready var label := $Label


func _process(_delta):
	position = get_global_mouse_position()
	label.text = str(map.selected_tile, map.mouse_in_tilemap())
