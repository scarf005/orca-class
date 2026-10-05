extends Node
## Neutral and angled production-model renders, without scenery or AI.
## xvfb-run -a godot --path . --resolution 960x720 -- --run=res://tools/actor_showcase.gd

const Inventory = preload("res://tools/actor_inventory.gd")


func run() -> int:
	var args: Dictionary = preload("res://scripts/main.gd").args()
	var out: String = args.get("out", ".screenshots/actors")
	DirAccess.make_dir_recursive_absolute(out)
	get_parent().get_node("Performance/FPS").hide()
	Course.flat = true
	var world := World.new()
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.terrain.visible = false
	world.props.visible = false
	world.fx.visible = false
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.16, 0.18, 0.21)
	world.environment.fog_enabled = false
	world.environment.glow_enabled = false
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var actors := {"tank": [""]}
	actors.merge(Inventory.VARIANTS)
	actors.gunship = ["hunter", "stripped", "infected"]
	actors.colossus = ["capped", "core"]
	for actor: String in actors:
		if args.has("actor") and actor != args.actor:
			continue
		for variant: String in actors[actor]:
			seed(12345)
			var entity: Entity = Tank.new() if actor == "tank" else Inventory.create(actor, variant)
			world.add_child(entity)
			entity.position = Vector3.ZERO
			entity.rotation = Vector3.ZERO
			if entity is Enemy:
				entity.model.rotation = Vector3.ZERO
			if entity.has_method("pose_idle"):
				entity.pose_idle()
			if entity is Tank:
				entity.mount_rws()
				for _i in 30:
					entity.tail.update(1.0 / 60.0, Basis.IDENTITY, 0.0)
			if entity is Gunship:
				for _i in {"hunter": 0, "stripped": 1, "infected": 2}[variant]:
					entity._advance_phase()
			if entity is Colossus and variant == "core":
				for part: Colossus.Part in entity.parts:
					var hit := Hit.make(Hit.Kind.FIRE, 1000.0, entity.global_transform * part.offset)
					entity.take_hit(hit)
			for mesh in Inventory.meshes(entity):
				mesh.material_overlay = null
			var bounds := AABB()
			var first := true
			for mesh in Inventory.meshes(entity):
				if not mesh.is_visible_in_tree():
					continue
				var box := mesh.global_transform * mesh.mesh.get_aabb()
				bounds = box if first else bounds.merge(box)
				first = false
			var center := bounds.get_center()
			var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
			camera.size = extent * 1.4
			for pose: String in ["neutral", "angled"]:
				var direction := Vector3(0, 0.18, -1) if pose == "neutral" else Vector3(1, 0.55, -1)
				if actor == "colossus":
					direction.z = -direction.z # Its weak points face +Z, back up the road.
				camera.position = center + direction.normalized() * (extent * 2.0 + 10.0)
				camera.look_at(center)
				for _frame in 3:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var path := "%s/%s%s_%s.png" % [out, actor, "_" + variant if not variant.is_empty() else "", pose]
				get_viewport().get_texture().get_image().save_png(path)
				print("Rendered ", path)
			entity.free()
	world.free()
	return 0
