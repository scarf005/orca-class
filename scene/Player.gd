extends Sprite

var x = 14
var y = 14


func _ready():
	position = index_to_vector(x, y)


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
	x += dx
	y += dy
	position = index_to_vector(x, y)
	return
	# Sprite.position += Vector2(dx * 32, dy * 32)


const STARTPOS := Vector2(0, 0)
const TILESIZE := Vector2(32, 32)


func vector_to_array(vector_coord: Vector2) -> Array:
	var res := (vector_coord - STARTPOS) / TILESIZE
	return [res.x, res.y]


func index_to_vector(x: int, y: int, x_offset: int = 0, y_offset: int = 0) -> Vector2:
	return STARTPOS + Vector2(x, y) * TILESIZE + Vector2(x_offset, y_offset)
