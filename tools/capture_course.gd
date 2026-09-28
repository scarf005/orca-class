extends Node
## Renders the course from a camera at given distances and saves dithered screenshots.
## Usage: xvfb-run -a godot --path . -- --run=res://tools/capture_course.gd --d=0,600 --out=builds/shots [--top]


func run() -> int:
	var args: Dictionary = preload("res://scripts/main.gd").args()
	var out: String = args.get("out", "builds/shots")
	DirAccess.make_dir_recursive_absolute(out)
	var view := DitherView.new()
	add_child(view)
	var world := World.new()
	view.viewport.add_child(world)
	for d_text: String in String(args.get("d", "0")).split(","):
		var d := float(d_text)
		world.rail.d = d
		var start := Time.get_ticks_msec()
		world.terrain.stream(d, true)
		print("stream ms ", Time.get_ticks_msec() - start)
		if args.has("top"):
			# Straight down from high above, road running up the frame, to show its shape.
			world.environment.fog_enabled = false
			var center := Course.ground_at(d + 120.0, 0.0)
			world.camera.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), center + Vector3.UP * 330.0)
		else:
			var eye := Course.ground_at(d - 14.0, float(args.get("u", "0")))
			eye.y += float(args.get("h", "7"))
			world.camera.position = eye
			world.camera.look_at(Course.ground_at(d + 30.0, 0.0) + Vector3.UP * 1.5)
		for _i in 4:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/course_%04d.png" % [out, int(d)])
		view.viewport.get_texture().get_image().save_png("%s/raw_%04d.png" % [out, int(d)])
		print("saved ", d)
	return 0
