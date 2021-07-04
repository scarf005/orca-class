extends Node


func _threshold_noise_tile(tiledict, noise: float):
	var r := (noise * 0.5 + 0.5) * 100 as int

	for v in tiledict.values():
		if r > v['t']:  # threshold
			return v['p']


func create_noisemap(octaves, period, persistence) -> Array:
	var noise := OpenSimplexNoise.new()
	var r: float
	var gamemap := []

	noise.seed = randi()
	noise.octaves = octaves
	noise.period = period
	noise.persistence = persistence

	for x in Const.MAPSIZE.x:
		gamemap.append([])
		for y in Const.MAPSIZE.y:
			r = noise.get_noise_2d(x, y)
			gamemap[x].append(_threshold_noise_tile(Const.TILES, r))
			get_parent().set_cell_simple2(x, y, gamemap[x][y])
	return gamemap




