extends Sprite

var pos: Vector2 setget _addpos, _getpos


func _addpos(value: Vector2) -> void:
	pos += value
	position = _pos_to_screenvec(pos)


func _getpos() -> Vector2:
	return pos


func _ready():
	pos = Vector2(4, 4)


func _input(event):
	if ! event.is_pressed():
		return

	if event.is_action("ui_left"):
		_try_move(-1, 0)
	if event.is_action("ui_right"):
		_try_move(1, 0)
	if event.is_action("ui_up"):
		_try_move(0, -1)
	if event.is_action("ui_down"):
		_try_move(0, 1)


func _try_move(dx, dy):
	_addpos(Vector2(dx, dy))
	# Sprite.position += Vector2(dx * 32, dy * 32)


const STARTPOS := Vector2(0, 0)
const TILESIZE := Vector2(32, 32)


func _screenvec_to_pos(vector_coord: Vector2) -> Array:
	var res := (vector_coord - STARTPOS) / TILESIZE
	return [res.x, res.y]


func _pos_to_screenvec(pos_vec: Vector2, offset: Vector2 = Vector2(0, 0)) -> Vector2:
	return STARTPOS + pos_vec * TILESIZE + offset
