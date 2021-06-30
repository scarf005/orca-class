extends Node2D

const MAPSIZE := [10, 10]

export (int) var _octaves = 4
export (float) var _period = 20.0
export (float) var _persistence = 0.8

var _gamemap


func _create_noisemap(octaves, period, persistence) -> Array:
    var noise := OpenSimplexNoise.new()
    var gamemap := []

    noise.seed = randi()
    noise.octaves = octaves
    noise.period = period
    noise.persistence = persistence

    for y in MAPSIZE[1]:
        gamemap.append([])
        for x in MAPSIZE[0]:
            gamemap[y].append(noise.get_noise_2d(x, y))

    return gamemap


# Called when the node enters the scene tree for the first time.
func _ready():
    _gamemap = _create_noisemap(_octaves, _period, _persistence)

    for y in MAPSIZE[1]:
        print(_gamemap[y])
