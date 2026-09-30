extends Node
## Plays the stage with a simple bot and saves screenshots, for smoke tests and visual checks.
## Usage: xvfb-run -a godot --path . -- --run=res://tools/autoplay.gd --seconds=30 --shots=5,10 \
##        [--checkpoint=boss] [--stage=2] [--out=builds/auto] [--god] [--scale=1] [--seed=1]
##        [--range=3000,3300] # print frame times within a course-distance interval

var screen: GameScreen


func run() -> int:
	var args: Dictionary = preload("res://scripts/main.gd").args()
	if args.has("seed"):
		seed(int(args.seed))
	var out: String = args.get("out", "builds/auto")
	DirAccess.make_dir_recursive_absolute(out)
	var seconds := float(args.get("seconds", "20"))
	var shots: Array = []
	for s: String in String(args.get("shots", "")).split(",", false):
		shots.append(float(s))
	Engine.time_scale = float(args.get("scale", "1"))
	screen = GameScreen.new()
	screen.checkpoint = args.get("checkpoint", "")
	screen.stage = int(args.get("stage", "1"))
	add_child(screen)
	var world := screen.world
	if args.has("god"):
		world.player.invulnerable = true
	var elapsed := 0.0
	var frames := 0
	var slow_frames := 0
	var worst := 0.0
	var frame_times := PackedFloat32Array()
	var range_bounds := String(args.get("range", "")).split(",", false)
	var range_times := PackedFloat32Array()
	var boss_start := -1.0
	var boss_end := -1.0
	while elapsed < seconds:
		var start := Time.get_ticks_usec()
		await get_tree().process_frame
		var frame_ms := (Time.get_ticks_usec() - start) / 1000.0
		var delta := get_process_delta_time()
		elapsed += delta
		frames += 1
		if frames > 30:
			frame_times.append(frame_ms)
			if range_bounds.size() == 2 and world.rail.d >= float(range_bounds[0]) and world.rail.d < float(range_bounds[1]):
				range_times.append(frame_ms)
			worst = maxf(worst, frame_ms)
			if frame_ms > 20.0:
				slow_frames += 1
				if args.has("spikes") and frame_ms > 30.0:
					print("SPIKE %.1fms t=%.1f d=%.0f particles=%d enemies=%d props=%d projectiles=%d" % [frame_ms, elapsed, world.rail.d,
						world.fx.particle_count(), world.enemies.size(), world.props.get_child_count(), world.projectiles.size()])
		_drive(world, elapsed)
		if args.has("profile") and frames % 60 == 0:
			print("t=%.1f frame=%.1fms process=%.1fms draw_calls=%d objects=%d particles=%d enemies=%d props=%d" % [elapsed, frame_ms,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				world.fx.particle_count(), world.enemies.size(),
				world.props.get_child_count()])
		if not shots.is_empty() and elapsed >= shots[0]:
			shots.pop_front()
			get_viewport().get_texture().get_image().save_png("%s/t%03d.png" % [out, int(elapsed)])
		if world.boss != null and boss_start < 0.0:
			boss_start = elapsed
		if world.boss == null and boss_start >= 0.0 and boss_end < 0.0:
			boss_end = elapsed
		if world.player.dead or screen._finished:
			break
	var stats := world.stats
	if boss_start >= 0.0:
		print("AUTOPLAY boss_fight=%.1fs" % ((boss_end if boss_end >= 0.0 else elapsed) - boss_start))
	if not frame_times.is_empty():
		frame_times.sort()
		print("BENCH median=%.2fms p95=%.2fms samples=%d" % [frame_times[frame_times.size() / 2], frame_times[int(frame_times.size() * 0.95)], frame_times.size()])
	if not range_times.is_empty():
		range_times.sort()
		print("RANGE d=%s median=%.2fms p95=%.2fms samples=%d" % [args.range, range_times[range_times.size() / 2], range_times[int(range_times.size() * 0.95)], range_times.size()])
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
		tank.aim_screen = Vector2(DitherView.RESOLUTION) * Vector2(0.5, 0.4)
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
	if int(t * 10) % 53 == 0:
		tank.dash(Vector2(1, 0) if weave < 0.0 else Vector2(-1, 0))
