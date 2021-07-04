extends Node


func _world_to_coord(world_pos: Vector2) -> Array:
	var res := (world_pos - Const.MAPSTART) / Const.TILESIZE
	return [res.x, res.y]


func _coord_to_world(coord_vec: Vector2, offset: Vector2 = Vector2(0, 0)) -> Vector2:
	return Const.MAPSTART + coord_vec * Const.TILESIZE + offset
