extends Node
## Screenshots of every debug room row plus an overview.
## Usage: xvfb-run -a godot --path . --resolution 960x540 -- --run=res://tools/debug_room_shots.gd --out=builds/debug_room


func run() -> int:
	var out: String = preload("res://scripts/main.gd").args().get("out", "builds/debug_room")
	DirAccess.make_dir_recursive_absolute(out)
	var room := DebugRoom.new()
	add_child(room)
	for _i in 30:
		await get_tree().process_frame
	for row in DebugRoom.ROWS.size():
		room.jump_to(row)
		room._play_stations()
		await get_tree().create_timer(0.35).timeout
		get_viewport().get_texture().get_image().save_png("%s/row%d.png" % [out, row + 1])
	var cam := room.world.camera
	cam.global_position = Course.to_world(DebugRoom.START_D - 40.0, 0.0, 75.0)
	cam.look_at(Course.to_world(DebugRoom.START_D + 150.0, 0.0, 0.0), Vector3.UP)
	room._yaw = cam.rotation.y
	room._pitch = cam.rotation.x
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png("%s/overview.png" % out)
	return 0
