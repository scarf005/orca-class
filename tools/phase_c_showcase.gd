extends Node
## Supplemental posed fixture: one isolated Stage 2 enemy per frame, not ordinary gameplay evidence.
## Usage: xvfb-run -a godot --path . -- --run=res://tools/phase_c_showcase.gd

var screen: GameScreen

func run() -> int:
	DirAccess.make_dir_recursive_absolute("builds/phase-c")
	screen = GameScreen.new()
	screen.stage = 2
	add_child(screen)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(2.4).timeout
	var world := screen.world
	world.director._next_event = world.director.events.size()
	world.rail.mode = Rail.Mode.HOLD
	world.rail.hold_at = world.rail.d
	world.player.input_enabled = false
	world.player.set_process(false)
	var names := ["airboat", "spray_drone", "heron", "leech", "egg_cluster", "lotus_mine", "gnat"]
	var paths := Director.ENEMY_SCRIPTS
	var offsets := [Vector3(-10, 0, -13), Vector3(9, 7, -16), Vector3(-8, 0, -11), Vector3(9, 0, -10), Vector3(-8, 0, -7), Vector3(8, 0, -7), Vector3(0, 5, -18)]
	for i in names.size():
		for old: Entity in world.enemies.duplicate():
			old.queue_free()
		await get_tree().process_frame
		var enemy: Enemy = load(paths[names[i]]).new()
		world.add_enemy(enemy)
		# Freeze AI immediately after _ready so the camera sees the authored silhouette rather than an attack frame.
		enemy.set_process(false)
		await get_tree().process_frame
		enemy.global_position = world.player.global_position + offsets[i]
		if not enemy.flying:
			enemy.global_position.y = Course.height_at(enemy.global_position) + (0.25 if enemy is CanalLeech or enemy is LotusMine else 0.0)
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("builds/phase-c/posed-%s.png" % names[i])
		print("POSED_CAPTURE %s builds/phase-c/posed-%s.png" % [names[i], names[i]])
		enemy.queue_free()
	await get_tree().process_frame
	return 0
