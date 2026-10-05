extends Node
## Poses enemies beside the tank on the flat checkered floor (10 m squares) and saves four views of each, for
## judging silhouettes and size against the hull.
## Usage: xvfb-run -a godot --path . --resolution 960x540 -- --run=res://tools/model_sheet.gd --kind=abel,kain \
##        [--dist=16] [--h=4] [--far=60] [--solo] [--out=builds/model_sheet] # --far adds a view from the chase
##        distance; --solo frames the enemy alone


func run() -> int:
	var args: Dictionary = preload("res://scripts/main.gd").args()
	var out: String = args.get("out", "builds/model_sheet")
	DirAccess.make_dir_recursive_absolute(out)
	var view := DitherView.new()
	add_child(view)
	Course.flat = true
	var world := World.new()
	world.view = view
	world.rail.d = DebugRoom.START_D + 60.0
	world.rail.mode = Rail.Mode.ARENA
	view.viewport.add_child(world)
	var at := Course.to_world(DebugRoom.START_D + 120.0, 0.0)
	var tank := TankModel.new()
	world.add_child(tank)
	tank.global_position = at + Course.right(DebugRoom.START_D + 120.0) * -5.0
	var dist := float(args.get("dist", "16"))
	var height := float(args.get("h", "4"))
	for kind: String in String(args.get("kind", "abel")).split(",", false):
		var enemy: Enemy = load(Director.ENEMY_SCRIPTS[kind]).new()
		enemy.position = at
		world.add_enemy(enemy)
		enemy.set_process(false)
		enemy.set_physics_process(false)
		enemy.global_position = at
		var views := [[0.0, dist, height], [60.0, dist, height], [150.0, dist, height], [250.0, dist, height]]
		if args.has("far"):
			views.append([200.0, float(args.far), 12.5]) # From the chase camera's height.
		for spec: Array in views:
			var yaw := deg_to_rad(spec[0])
			var focus := at + Vector3.UP * 2.5 + Course.right(DebugRoom.START_D + 120.0) * (0.0 if args.has("solo") else -2.5)
			world.camera.global_position = focus + Vector3(sin(yaw), 0, cos(yaw)) * spec[1] + Vector3.UP * spec[2]
			world.camera.look_at(focus, Vector3.UP)
			for _i in 10:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [out, kind, int(spec[0]) if spec[1] == dist else 999])
		enemy.queue_free()
		await get_tree().process_frame
	Course.flat = false
	return 0
