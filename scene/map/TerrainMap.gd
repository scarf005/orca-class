extends TileMap

onready var selected_tile: Vector2
onready var mouse_in_tilemap: bool


func _input(event):
	if event is InputEventMouseMotion:
		var localpos: Vector2 = world_to_map(
			to_local(get_global_mouse_position())
		)
		selected_tile = Vector2(
			clamp(localpos.x, 0, Const.MAPSIZE.x - 1),
			clamp(localpos.y, 0, Const.MAPSIZE.y - 1)
		)
		mouse_in_tilemap = selected_tile == localpos


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
			set_cell_simple2(x, y, gamemap[x][y])
	return gamemap


func _int_to_vector2(i: int) -> Vector2:
	return Vector2(i % int(Const.ATLASSIZE.x), i / int(Const.ATLASSIZE.y))


func set_cell_simple(x, y, tile_index: int) -> void:
	.set_cell(x, y, 0, false, false, false, _int_to_vector2(tile_index))


func set_cell_simple2(x, y, tile_coord = Vector2()) -> void:
	.set_cell(x, y, 0, false, false, false, tile_coord)
