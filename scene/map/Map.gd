extends Node2D

export (int, 1, 128) var _period = 20
export (int, 1, 10) var _octaves = 4
export (float) var _persistence = 0.8

onready var terrainmap := $TerrainMap
onready var mapinfo := $MapInfo

var gamemap := []


# Called when the node enters the scene tree for the first time.
func _ready():
	gamemap = terrainmap.create_noisemap(_octaves, _period, _persistence)
	mapinfo.print_mapinfo(gamemap)


func _input(event):
	if event is InputEventKey and event.pressed:
		if event.scancode == KEY_R:
			print("reloading")
			gamemap = terrainmap.create_noisemap(
				_octaves, _period, _persistence
			)
