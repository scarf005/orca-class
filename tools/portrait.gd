extends Node
## Parks one enemy on stage 2's street and shoots it from several angles.
## Usage: xvfb-run -a godot --path . --resolution 960x540 -- --run=res://tools/portrait.gd \
##        --kind=abel[,kain] [--dist=14] [--h=4] [--out=builds/portrait] [--d=300] [--beside] # --beside parks it next to the tank for scale

func run() -> int:
	var args: Dictionary = preload("res://scripts/main.gd").args()
	var out: String = args.get("out", "builds/portrait")
	DirAccess.make_dir_recursive_absolute(out)
	var screen := GameScreen.new()
	screen.stage = 2
	add_child(screen)
	var world := screen.world
	screen.hud.visible = false
	world.player.invulnerable = true
	world.player.input_enabled = false
	var d := float(args.get("d", "300"))
	world.rail.d = d
	world.rail.mode = Rail.Mode.HOLD
	world.rail.hold_at = d
	world.director._next_event = world.director.events.size()
	world.director.scenery.stream(d, 100000)
	for _i in 20:
		await get_tree().process_frame
	world.player.model.visible = args.has("beside")
	var dist := float(args.get("dist", "14"))
	var height := float(args.get("h", "4"))
	for kind: String in String(args.get("kind", "abel")).split(",", false):
		var enemy: Enemy = load(Director.ENEMY_SCRIPTS[kind]).new()
		var spot := Course.ground_at(d + float(args.get("ahead", "40")), 0.0)
		if args.has("beside"):
			spot = world.player.global_position + Course.right(d) * 7.0
		enemy.position = spot + Vector3.UP * float(args.get("lift", "0"))
		world.add_enemy(enemy)
		world.camera.set_process(false)
		for yaw in [0.0, 70.0, 150.0, 250.0]:
			var dir := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
			world.camera.global_position = enemy.global_position + dir * dist + Vector3.UP * height
			world.camera.look_at(enemy.global_position + Vector3.UP * float(args.get("look", "3")), Vector3.UP)
			for _i in 12:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [out, kind, int(yaw)])
		enemy.queue_free()
		await get_tree().process_frame
	return 0
