extends Sprite

var coord: Vector2 setget _set_coord, _get_coord


func _ready():
	_set_coord(Vector2(4, 4))


func _set_coord(value: Vector2) -> void:
	coord = value
	position = _coord_to_world(value)


func _get_coord() -> Vector2:
	return coord


func _input(event):
	if ! event.is_pressed():
		return

	# HACK: determine to give y inversion a go
	if event.is_action("ui_left_up"):
		_try_move(-1, -1)
	elif event.is_action("ui_right_up"):
		_try_move(1, -1)
	elif event.is_action("ui_left_down"):
		_try_move(-1, 1)
	elif event.is_action("ui_right_down"):
		_try_move(1, 1)
	if event.is_action("ui_left"):
		_try_move(-1, 0)
	if event.is_action("ui_right"):
		_try_move(1, 0)
	if event.is_action("ui_up"):
		_try_move(0, -1)
	if event.is_action("ui_down"):
		_try_move(0, 1)


func _try_move(dx, dy):
	_set_coord(coord + Vector2(dx, dy))
	# Sprite.position += Vector2(dx * 32, dy * 32)


func _world_to_coord(world_pos: Vector2) -> Array:
	var res := (world_pos - Const.MAPSTART) / Const.TILESIZE
	return [res.x, res.y]


func _coord_to_world(coord_vec: Vector2, offset: Vector2 = Vector2(0, 0)) -> Vector2:
	return Const.MAPSTART + coord_vec * Const.TILESIZE + offset
