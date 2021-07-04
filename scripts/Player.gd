extends Sprite

onready var debug := $Debug
onready var map := $"../Map"
onready var world := $"/root/World"
onready var smoke := preload("res://scene/entities/Smoke.tscn")

var coord: Vector2 setget _set_coord, _get_coord
var destination: Vector2


func _smoke():  # TODO: needs to be in gamemap as well since it's an entity
	var s = smoke.instance()
	s.rotation = destination.angle_to_point(coord)
	s.position = position + Const.TILESIZE / 2  # match offset
	world.add_child(s)


func _ready():
	_set_coord(Vector2(4, 4))
	destination = coord


func _process(_delta):
	var temp = Utils.zsign(destination - coord)
	debug.text = str(coord, destination)
	_try_move(temp.x, temp.y)


func _set_coord(value: Vector2) -> void:
	coord = value
	position = Utils.coord_to_world(value)


func _get_coord() -> Vector2:
	return coord


func _input(event):
	if ! event.is_pressed():
		return

	if event.is_action("ui_accept"):
		destination = map.selected_tile
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
	if coord != destination:
		_smoke()
	var temp := coord + Vector2(dx, dy)
	_set_coord(
		Vector2(
			clamp(temp.x, 0, Const.MAPSIZE.x - 1),
			clamp(temp.y, 0, Const.MAPSIZE.y - 1)
		)
	)
