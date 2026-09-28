extends Node
## Plays the stage with a simple bot and saves screenshots, for smoke tests and visual checks.
## Usage: xvfb-run -a godot --path . -- --run=res://tools/autoplay.gd --seconds=30 --shots=5,10 \
##        [--checkpoint=boss] [--out=builds/auto] [--god] [--scale=1]

var screen: GameScreen


func run() -> int:
	var args: Dictionary = preload("res://scripts/main.gd").args()
	var out: String = args.get("out", "builds/auto")
	DirAccess.make_dir_recursive_absolute(out)
	var seconds := float(args.get("seconds", "20"))
	var shots: Array = []
	for s: String in String(args.get("shots", "")).split(",", false):
		shots.append(float(s))
	Engine.time_scale = float(args.get("scale", "1"))
	screen = GameScreen.new()
	screen.checkpoint = args.get("checkpoint", "")
	add_child(screen)
	var world := screen.world
	if args.has("god"):
		world.player.invulnerable = true
	var elapsed := 0.0
	var frames := 0
	var slow_frames := 0
	var worst := 0.0
	while elapsed < seconds:
		var start := Time.get_ticks_usec()
		await get_tree().process_frame
		var frame_ms := (Time.get_ticks_usec() - start) / 1000.0
		var delta := get_process_delta_time()
		elapsed += delta
		frames += 1
		if frames > 30:
			worst = maxf(worst, frame_ms)
			if frame_ms > 20.0:
				slow_frames += 1
		_drive(world, elapsed)
		if args.has("profile") and frames % 60 == 0:
			print("t=%.1f frame=%.1fms process=%.1fms draw_calls=%d objects=%d particles=%d enemies=%d props=%d" % [elapsed, frame_ms,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				world.fx._pools[Fx.Kind.SOLID].size() + world.fx._pools[Fx.Kind.GLOW].size(), world.enemies.size(),
				world.props.get_child_count()])
		if not shots.is_empty() and elapsed >= shots[0]:
			shots.pop_front()
			get_viewport().get_texture().get_image().save_png("%s/t%03d.png" % [out, int(elapsed)])
		if world.player.dead or screen._finished:
			break
	var stats := world.stats
	print("AUTOPLAY d=%.0f score=%d kills=%d/%d lives=%d hp=%.0f enemies=%d projectiles=%d frames=%d slow=%d worst=%.1fms" % [
		world.rail.d, stats.score, stats.kills, stats.spawned, stats.lives, world.player.hp, world.enemies.size(),
		world.projectiles.size(), frames, slow_frames, worst])
	Engine.time_scale = 1.0
	return 0


## A bot that aims at the nearest enemy, fires everything and weaves.
func _drive(world: World, t: float) -> void:
	var tank := world.player
	tank.using_gamepad = true
	var target: Entity = null
	var best := INF
	for enemy in world.enemies:
		var distance := enemy.global_position.distance_to(tank.global_position)
		if distance < best and not world.camera.is_position_behind(enemy.hit_center()):
			best = distance
			target = enemy
	if target:
		tank.aim_screen = world.camera.unproject_position(target.hit_center())
		Input.action_press("fire_cannon")
	else:
		tank.aim_screen = Vector2(240, 110)
		Input.action_release("fire_cannon")
	Input.action_press("fire_coax")
	var weave := sin(t * 0.7)
	if weave > 0.3:
		Input.action_press("move_right")
		Input.action_release("move_left")
	elif weave < -0.3:
		Input.action_press("move_left")
		Input.action_release("move_right")
	else:
		Input.action_release("move_left")
		Input.action_release("move_right")
	if int(t * 10) % 37 == 0:
		Input.action_press("tail")
	else:
		Input.action_release("tail")
