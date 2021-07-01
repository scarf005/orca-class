extends Node2D

const MAPSIZE := Vector2(16, 16)

# TODO: JSON support
const TILES := {
	"crater": {"w": 20, "p": Vector2(1, 2)},
	"floor": {"w": 50, "p": Vector2(0, 11)},
	"dune": {"w": 30, "p": Vector2(1, 11)},
}

export (int, 1, 128) var _period = 20
export (int, 1, 10) var _octaves = 4
export (float) var _persistence = 0.8

var gamemap := []
onready var tilemap := $TileMap


func _weighted_noise_tile(tiledict, r: float):
	var weight_total := 0
	for v in tiledict.values():
		weight_total += v['w']
	r *= weight_total as float

	# var r := randi() % weight_total + 1
	var weight := 0
	for v in tiledict.values():
		weight += v['w']
		if r < weight:
			return v['p']


func _create_noisemap(octaves, period, persistence) -> void:
	var noise := OpenSimplexNoise.new()
	var r: float

	noise.seed = randi()
	noise.octaves = octaves
	noise.period = period
	noise.persistence = persistence

	gamemap.clear()
	for x in MAPSIZE.x:
		gamemap.append([])
		for y in MAPSIZE.y:
			r = noise.get_noise_2d(x, y) * 0.5 + 0.5
			# gamemap[x].append(int(r * 100))
			gamemap[x].append(_weighted_noise_tile(TILES, r))
			tilemap.set_cell_simple2(x, y, gamemap[x][y])
			# tilemap.set_cell_simple2(x, y, gamemap[x][y])
			# tilemap.set_cell(x, y, randi() % 100)
			# gamemap[y].append(int(r * 100))


# Called when the node enters the scene tree for the first time.
func _ready():
	_create_noisemap(_octaves, _period, _persistence)


func _input(event):
	if event is InputEventKey and event.pressed:
		if event.scancode == KEY_R:
			print("reloading")
			_create_noisemap(_octaves, _period, _persistence)
