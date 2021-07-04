extends TileMap

export (int, 1, 128) var _period = 20
export (int, 1, 10) var _octaves = 4
export (float) var _persistence = 0.8

onready var mapgen := $MapGen
# onready var mapinfo := $MapInfo

onready var selected_tile: Vector2
onready var mouse_in_tilemap: bool

onready var gamemap = mapgen.create_noisemap(_octaves, _period, _persistence)


func _input(event):
	if event is InputEventKey and event.pressed:
		if event.scancode == KEY_R:
			print("reloading")
			gamemap = mapgen.create_noisemap(_octaves, _period, _persistence)

	if event is InputEventMouseMotion:
		var localpos: Vector2 = world_to_map(
			to_local(get_global_mouse_position())
		)
		selected_tile = Vector2(
			clamp(localpos.x, 0, Const.MAPSIZE.x - 1),
			clamp(localpos.y, 0, Const.MAPSIZE.y - 1)
		)
		mouse_in_tilemap = selected_tile == localpos


func _int_to_vector2(i: int) -> Vector2:
	return Vector2(i % int(Const.ATLASSIZE.x), i / int(Const.ATLASSIZE.y))


func set_cell_simple(x, y, tile_index: int) -> void:
	.set_cell(x, y, 0, false, false, false, _int_to_vector2(tile_index))


func set_cell_simple2(x, y, tile_coord = Vector2()) -> void:
	.set_cell(x, y, 0, false, false, false, tile_coord)
