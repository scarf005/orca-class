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
	var only: String = preload("res://scripts/main.gd").args().get("row", "")
	for row in DebugRoom.ROWS.size():
		if not only.is_empty() and str(row + 1) != only:
			continue
		room.jump_to(row)
		room._play_stations()
		await get_tree().create_timer(0.35).timeout
		get_viewport().get_texture().get_image().save_png("%s/row%d.png" % [out, row + 1])
	var closeup: String = preload("res://scripts/main.gd").args().get("closeup", "")
	if not closeup.is_empty():
		# Frame every posed enemy of the given classes, e.g. --closeup=Walker,QuadMech.
		if closeup == "projectiles":
			var cam_p := room.world.camera
			for part in 2:
				var focus := Course.ground_at(room._row_d[7], (part - 0.5) * 14.0) + Vector3.UP * 2.0
				cam_p.global_position = focus + Vector3(0, 0.8, 7.5)
				cam_p.look_at(focus, Vector3.UP)
				room._yaw = cam_p.rotation.y
				room._pitch = cam_p.rotation.x
				await get_tree().create_timer(0.2).timeout
				get_viewport().get_texture().get_image().save_png("%s/projectiles_%d.png" % [out, part])
			return 0
		var targets := room.world.enemies.filter(func(e: Entity) -> bool: return e.get_script().get_global_name() in closeup.split(","))
		var center := Vector3.ZERO
		for e: Entity in targets:
			center += e.global_position
		center /= maxf(targets.size(), 1)
		var cam := room.world.camera
		cam.global_position = center + Vector3(0, 6.0, 16.0)
		cam.look_at(center + Vector3.UP * 2.5, Vector3.UP)
		room._yaw = cam.rotation.y
		room._pitch = cam.rotation.x
		await get_tree().create_timer(0.3).timeout
		get_viewport().get_texture().get_image().save_png("%s/closeup.png" % out)
		return 0
	if not only.is_empty():
		return 0
	var cam := room.world.camera
	cam.global_position = Course.to_world(DebugRoom.START_D - 40.0, 0.0, 75.0)
	cam.look_at(Course.to_world(DebugRoom.START_D + 150.0, 0.0, 0.0), Vector3.UP)
	room._yaw = cam.rotation.y
	room._pitch = cam.rotation.x
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png("%s/overview.png" % out)
	return 0
