extends Node

func world_to_coord(world_pos: Vector2) -> Array:
	var res := (world_pos - Const.MAPSTART) / Const.TILESIZE
	return [res.x, res.y]


func coord_to_world(coord_vec: Vector2, offset: Vector2 = Vector2(0, 0)) -> Vector2:
	return Const.MAPSTART + coord_vec * Const.TILESIZE + offset

func zsign(value: Vector2) -> Vector2:
	"""
	works similar to Vector2.sign() method but 0 returns 0
	works properly only on int Vector2!
	will return (0.54, -0.17) or some shit like that on float prob.
	"""
	return Vector2(clamp(value.x, -1, 1), clamp(value.y, -1, 1))