extends Node2D

const MAPSIZE := Vector2(16, 16)
enum TILES {
	FLOOR = 50,
	DUNE = 50,
}
const TILEPOS := {
	TILES.FLOOR: Vector2(0, 11),
	TILES.DUNE: Vector2(1, 11),
}

export (int, 1, 128) var _period = 20
export (int, 1, 10) var _octaves = 4
export (float) var _persistence = 0.8

var gamemap := []
onready var tilemap := $TileMap


func _weighted_random(enums, r: float):
	var weight_total := 0
	for v in enums.values():
		weight_total += v
	assert(weight_total == 100, "weight sum's not 100 but %s" % weight_total)
	r *= weight_total as float

	# var r := randi() % weight_total + 1
	var weight := 0
	for i in enums.size():
		weight += enums.values()[i]
		if r < weight:
			return i


func _int_to_vector2(i: int) -> Vector2:
	return Vector2(i % 16, i / 16)


func _create_noisemap(octaves, period, persistence) -> void:
	var noise := OpenSimplexNoise.new()
	var r: float

	noise.seed = randi()
	noise.octaves = octaves
	noise.period = period
	noise.persistence = persistence

	for x in MAPSIZE.x:
		gamemap.append([])
		for y in MAPSIZE.y:
			r = noise.get_noise_2d(x, y) * 0.5 + 0.5
			gamemap[x].append(_weighted_random(TILES, r))
			# tilemap.set_cell(x, y, gamemap[x][y])
			tilemap.set_cell(x, y, 0, false, false, false, _int_to_vector2(gamemap[x][y]))
			# tilemap.set_cell(x, y, randi() % 100)
			# gamemap[y].append(int(r * 100))


# Called when the node enters the scene tree for the first time.
func _ready():
	_create_noisemap(_octaves, _period, _persistence)
	# _noisemap_to_gamemap()

	# for y in MAPSIZE.y:
	# 	print(gamemap[y])
