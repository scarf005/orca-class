extends Node2D

const MAPSIZE := Vector2(16, 16)

# TODO: JSON support
const TILES := {
	"peak": {"t": 70, "p": Vector2(0, 11)},
	"dune": {"t": 55, "p": Vector2(1, 11)},
	"plain": {"t": 0, "p": Vector2(2, 11)}
}

export (int, 1, 128) var _period = 20
export (int, 1, 10) var _octaves = 4
export (float) var _persistence = 0.8

var gamemap := []
onready var terrainmap := $TerrainMap


# Called when the node enters the scene tree for the first time.
func _ready():
	gamemap = terrainmap.create_noisemap(_octaves, _period, _persistence)


func _input(event):
	if event is InputEventKey and event.pressed:
		if event.scancode == KEY_R:
			print("reloading")
			gamemap = terrainmap.create_noisemap(_octaves, _period, _persistence)
