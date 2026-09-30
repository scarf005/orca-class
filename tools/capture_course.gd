extends Node
## Renders the course from a camera at given distances and saves dithered screenshots.
## Usage: xvfb-run -a godot --path . -- --run=res://tools/capture_course.gd --d=600 --out=assets/ui/stage1.png [--stage=1] [--square] [--size=256] [--props] [--reference=frame.png]
## Regenerate stage maps: xvfb-run -a godot --path . -- --run=res://tools/capture_course.gd --stage=1 --d=700 --u=8 --h=5 --props --square --size=256 --out=assets/ui/stage1.png and
## xvfb-run -a godot --path . -- --run=res://tools/capture_course.gd --stage=2 --d=1500 --u=-10 --h=5 --props --square --size=256 --out=assets/ui/stage2.png (run `just stage-thumbnails`).


func run() -> int:
	var args: Dictionary = preload("res://scripts/main.gd").args()
	var out: String = args.get("out", "builds/shots")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir() if args.has("square") else out)
	var output_size := int(args.get("size", "256"))
	var view := DitherView.new()
	add_child(view)
	# Keep the game's native 960x540 view and shader grid. A square is a crop of the
	# final displayed frame, not a smaller render or a resampled Bayer pattern.
	var world := World.new()
	world.stage_number = int(args.get("stage", "1"))
	view.viewport.add_child(world)
	var scenery: Scenery
	if args.has("props"):
		scenery = Scenery.new()
		world.add_child(scenery)
		scenery.build()
	for d_text: String in String(args.get("d", "0")).split(","):
		var d := float(d_text)
		world.rail.d = d
		var start := Time.get_ticks_msec()
		world.terrain.stream(d, true)
		if args.has("props"):
			scenery.stream(d, 100000)
		print("stream ms ", Time.get_ticks_msec() - start)
		if args.has("top"):
			# Straight down from high above, road running up the frame, to show its shape.
			world.environment.fog_enabled = false
			var center := Course.ground_at(d + 120.0, 0.0)
			world.camera.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Course.forward(d + 120.0)), center + Vector3.UP * 330.0)
		else:
			var eye := Course.ground_at(d - 14.0, float(args.get("u", "0")))
			eye.y += float(args.get("h", "7"))
			world.camera.position = eye
			world.camera.look_at(Course.ground_at(d + 30.0, 0.0) + Vector3.UP * 1.5)
		for _i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		assert(image.get_size() == DitherView.RESOLUTION, "Capture must use the native displayed frame")
		if args.has("reference"):
			var reference: String = args.reference
			DirAccess.make_dir_recursive_absolute(reference.get_base_dir())
			image.save_png(reference)
		if args.has("square"):
			assert(output_size > 0 and output_size <= image.get_height())
			var origin := (image.get_size() - Vector2i(output_size, output_size)) / 2
			image.get_region(Rect2i(origin, Vector2i(output_size, output_size))).save_png(out)
		else:
			image.save_png("%s/course_%04d.png" % [out, int(d)])
			view.viewport.get_texture().get_image().save_png("%s/raw_%04d.png" % [out, int(d)])
		print("saved ", d)
	return 0
