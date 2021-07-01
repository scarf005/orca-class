extends TileMap


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
