extends Node
## Deterministic rendered particle snapshots, including fade, rotation and live-pool compaction.
## godot --path . -- --run=res://tools/capture_particles.gd --out=builds/particles


func run() -> int:
	var args: Dictionary = preload("res://scripts/main.gd").args()
	var out: String = args.get("out", "builds/particles")
	DirAccess.make_dir_recursive_absolute(out)
	var view := SubViewport.new()
	view.size = Vector2i(320, 240)
	view.own_world_3d = true
	var preview := TextureRect.new()
	preview.size = Vector2(320, 240)
	preview.texture = view.get_texture()
	add_child(preview)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	var camera := Camera3D.new()
	camera.position = Vector3(4, 3, 15)
	view.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var fx := Fx.new()
	view.add_child(fx)
	fx.set_process(false)
	seed(42)
	for kind in [Fx.Kind.SOLID, Fx.Kind.GLOW, Fx.Kind.FLAME]:
		for i in 5:
			fx.spawn(kind, Vector3((i - 2) * 2.0, (1 - kind) * 3.0, 0), Vector3(0.1, 0.2, 0),
				0.5 if i == 0 else 2.0, 1.0, Color(1.0, 0.4 + i * 0.1, 0.2),
				{"spin": 0.0 if i % 2 == 0 else 1.0, "fade": 0.0 if i == 2 else 0.3,
					"end_size": 0.0 if i == 2 else 0.2, "material": Fx.Debris.METAL})
	var age := 0.0
	for next in [0.1, 0.6, 1.2, 1.9]:
		fx._process(next - age)
		age = next
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		view.get_texture().get_image().save_png("%s/age_%.1f.png" % [out, age])
	return 0
