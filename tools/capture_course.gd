extends Node
## Renders the course from a camera at given distances and saves dithered screenshots.
## Usage: xvfb-run -a godot --path . -- --run=res://tools/capture_course.gd --d=600 --out=assets/ui/stage1.png [--stage=1] [--square] [--size=256] [--props] [--reference=frame.png]
## Regenerate stage maps: xvfb-run -a godot --path . -- --run=res://tools/capture_course.gd --stage=1 --d=700 --u=8 --h=5 --props --square --size=256 --out=assets/ui/stage1.png and
## xvfb-run -a godot --path . -- --run=res://tools/capture_course.gd --stage=2 --d=700 --u=0 --h=5 --props --square --size=256 --out=assets/ui/stage2.png (run `just stage-thumbnails`).


func run() -> int:
	var args: Dictionary = preload("res://scripts/main.gd").args()
	var out: String = args.get("out", "builds/shots")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir() if args.has("square") else out)
	var output_size := int(args.get("size", "256"))
	if args.has("benchmark"):
		return await _benchmark(int(args.get("stage", "2")))
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
	for _i in 3:
		await get_tree().process_frame
	for d_text: String in String(args.get("d", "0")).split(","):
		var d := float(d_text)
		world.rail.d = d
		var start := Time.get_ticks_msec()
		world.terrain.stream(d, true)
		if args.has("props"):
			scenery.stream(d, 100000)
		print("stream ms ", Time.get_ticks_msec() - start)
		if args.has("top"):
			# Straight down from high above, road running up the frame, with every prop visible.
			world.environment.fog_enabled = false
			world.camera.far = 5000.0
			if scenery:
				_stream_all(scenery)
			var center := Course.ground_at(d + 120.0, 0.0)
			world.camera.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Course.forward(d + 120.0)), center + Vector3.UP * 330.0)
		else:
			var capture_u := float(args.get("u", "0"))
			# A gameplay tank is shoved into a lane before a splitter; use that real tank pose.
			if world.stage_number == 2:
				var city := Course.stage as Stage2
				for index in city.SPLITS.size():
					if absf(d - float(city.SPLITS[index].d)) < 20.0:
						capture_u = city.split_lane_centres(index).x
						break
			var tank_ground := Course.ground_at(d, capture_u)
			if scenery:
				var corrected := scenery.drive_position(tank_ground, tank_ground, Tank.HULL_RADIUS)
				capture_u = Course.to_course(corrected).y
				tank_ground = Course.ground_at(d, capture_u)
			var target := tank_ground + Vector3.UP
			var eye := Course.to_world(d - ChaseCamera.RAIL_BACK, capture_u * 0.75)
			eye.y = maxf(Course.height(d - ChaseCamera.RAIL_BACK, capture_u * 0.75), tank_ground.y - 1.0) + ChaseCamera.RAIL_HEIGHT
			var look := Course.to_world(d + ChaseCamera.RAIL_LOOK_AHEAD, capture_u * 0.85, tank_ground.y)
			world.camera.global_position = scenery.camera_position(target, eye) if scenery else eye
			world.camera.look_at(look, Vector3.UP)
		for _i in 30:
			await get_tree().process_frame
		if args.has("profile"):
			var profile_start := Time.get_ticks_usec()
			for _i in 120:
				await get_tree().process_frame
			print("RENDER stage=%d d=%.0f props=%d fps=%.1f frame=%.2fms" % [world.stage_number, d, world.props.get_child_count(), 120000000.0 / (Time.get_ticks_usec() - profile_start), (Time.get_ticks_usec() - profile_start) / 120000.0])
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


func _stream_all(scenery: Scenery) -> void:
	for spec: Scenery.Spec in scenery.specs:
		if spec.pickup.is_empty() and not spec.has_meta("destroyed") and not is_instance_valid(spec.node):
			scenery._instantiate(spec)
	for spec: Scenery.Spec in scenery.specs:
		if not is_instance_valid(spec.node):
			continue
		for node in [spec.node] + spec.node.find_children("*", "GeometryInstance3D", true, false):
			if node is GeometryInstance3D:
				(node as GeometryInstance3D).visibility_range_end = 5000.0


## CPU timings of the actual city stream, hull sweep and twelve hunter cover queries, not rendered FPS.
func _benchmark(number: int) -> int:
	var world := World.new()
	world.stage_number = number
	add_child(world)
	world.set_process(false)
	var scenery := Scenery.new()
	world.add_child(scenery)
	scenery.build()
	scenery.set_process(false)
	scenery.stream(0.0, 100000)
	var samples: Array[float] = []
	var peak := 0
	var last := Course.ground_at(0.0, 0.0)
	for frame in 8000:
		var d := frame * 0.5
		world.rail.d = d
		var start := Time.get_ticks_usec()
		world.terrain.stream(d)
		scenery.stream(d)
		var next := Course.ground_at(d, 0.0)
		last = scenery.drive_position(last, next, Tank.HULL_RADIUS)
		for i in 12:
			scenery.line_blocked(Course.to_world(d + 30.0 + i * 4.0, -25.0 if i % 2 else 25.0, 5.0), last + Vector3.UP * 2.0)
		samples.append((Time.get_ticks_usec() - start) / 1000.0)
		peak = maxi(peak, scenery._live.size())
		if frame % 120 == 0:
			await get_tree().process_frame
	samples.sort()
	print("BENCH city_stage%d plan=%d peak_live=%d median=%.3fms p95=%.3fms p99=%.3fms max=%.3fms samples=%d" % [number,
		scenery.specs.size(), peak, samples[samples.size() / 2], samples[int(samples.size() * 0.95)], samples[int(samples.size() * 0.99)], samples[-1], samples.size()])
	world.free()
	return 0
