extends TileMap


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

	for x in get_parent().MAPSIZE.x:
		gamemap.append([])
		for y in get_parent().MAPSIZE.y:
			r = noise.get_noise_2d(x, y)
			gamemap[x].append(_threshold_noise_tile(get_parent().TILES, r))
			set_cell_simple2(x, y, gamemap[x][y])
	return gamemap


func _int_to_vector2(i: int) -> Vector2:
	return Vector2(i % 16, i / 16)
	# FIXME: change to constant


func set_cell_simple(x, y, tile_index: int) -> void:
	"""
	TODO: Add documentation
	"""
	.set_cell(x, y, 0, false, false, false, _int_to_vector2(tile_index))


func set_cell_simple2(x, y, tile_coord = Vector2()) -> void:
	"""
	TODO: Add documentation
	"""
	.set_cell(x, y, 0, false, false, false, tile_coord)
