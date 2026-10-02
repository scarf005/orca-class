extends Node
## Plays the stage with a simple bot and saves screenshots, for smoke tests and visual checks.
## Usage: xvfb-run -a godot --path . -- --run=res://tools/autoplay.gd --seconds=30 --shots=5,10 \
##        [--checkpoint=boss] [--out=builds/auto] [--god] [--scale=1] [--seed=1]
##        [--range=3000,3300] # print frame times within a course-distance interval

var screen: GameScreen
var bot := "hold"
var cleared := false
var kill_sources := {"coax": 0, "cannon": 0, "ram": 0, "dash": 0, "tail": 0, "ciws": 0, "collateral": 0, "reflect": 0, "other": 0}
var _tap_down := false
var _charge_started := -1.0
var _section := 0


func run() -> int:
	var args: Dictionary = preload("res://scripts/main.gd").args()
	if args.has("seed"):
		seed(int(args.seed))
	bot = args.get("bot", "hold")
	if bot not in ["hold", "idle", "tap", "charge"]:
		push_error("Unknown bot mode: %s" % bot)
		return 1
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
	world.killed.connect(_killed)
	world.stage_cleared.connect(func() -> void:
		cleared = true
		_section_end(world))
	_section = world.director.section
	world.director.section_changed.connect(func(section: Course.Section) -> void:
		_section_end(world)
		_section = section)
	if args.has("god"):
		world.player.invulnerable = true
	var elapsed := 0.0
	var frames := 0
	var slow_frames := 0
	var worst := 0.0
	var frame_times := PackedFloat32Array()
	var range_bounds := String(args.get("range", "")).split(",", false)
	var range_times := PackedFloat32Array()
	var front_total := 0.0
	var boss_start := -1.0
	var boss_end := -1.0
	var boss_phase := 0
	while elapsed < seconds:
		var start := Time.get_ticks_usec()
		await get_tree().process_frame
		var frame_ms := (Time.get_ticks_usec() - start) / 1000.0
		var delta := get_process_delta_time()
		elapsed += delta
		frames += 1
		for enemy in world.enemies:
			if not enemy.dead and not world.camera.is_position_behind(enemy.hit_center()):
				front_total += 1.0
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
		if boss_end < 0.0 and is_instance_valid(world.boss) and world.boss is Gunship:
			boss_phase = maxi(boss_phase, world.boss.phase + 1)
		if world.boss == null and boss_start >= 0.0 and boss_end < 0.0:
			boss_end = elapsed
		if world.player.dead or screen._finished:
			break
	var stats := world.stats
	if boss_start >= 0.0:
		print("AUTOPLAY boss_fight=%.1fs phase=%d" % [(boss_end if boss_end >= 0.0 else elapsed) - boss_start, boss_phase])
	if not frame_times.is_empty():
		frame_times.sort()
		print("BENCH median=%.2fms p95=%.2fms samples=%d" % [frame_times[frame_times.size() / 2], frame_times[int(frame_times.size() * 0.95)], frame_times.size()])
	if not range_times.is_empty():
		range_times.sort()
		print("RANGE d=%s median=%.2fms p95=%.2fms samples=%d" % [args.range, range_times[range_times.size() / 2], range_times[int(range_times.size() * 0.95)], range_times.size()])
	print("AUTOPLAY d=%.0f score=%d kills=%d/%d lives=%d hp=%.0f enemies=%d projectiles=%d frames=%d slow=%d worst=%.1fms" % [
		world.rail.d, stats.score, stats.kills, stats.spawned, stats.lives, world.player.hp, world.enemies.size(),
		world.projectiles.size(), frames, slow_frames, worst])
	print("PROBE bot=%s cleared=%s dead=%s time=%.2f d=%.0f lives=%d damage_taken=%.2f kills=%d/%d front_mean=%.2f coax=%d cannon=%d ram=%d dash=%d tail=%d ciws=%d collateral=%d reflect=%d other=%d cannon_shots=%d charged_shots=%d healing_melee=%.2f healing_repair=%.2f" % [
		bot, cleared and not world.player.dead, world.player.dead, stats.time, world.rail.d, stats.lives, stats.damage_taken, stats.kills, stats.spawned, front_total / maxi(frames, 1),
		kill_sources.coax, kill_sources.cannon, kill_sources.ram, kill_sources.dash, kill_sources.tail, kill_sources.ciws, kill_sources.collateral, kill_sources.reflect, kill_sources.other, stats.shots, stats.charged_shots, stats.melee_healing, stats.repair_healing])
	for action in ["fire_coax", "fire_cannon", "move_left", "move_right"]:
		Input.action_release(action)
	Engine.time_scale = 1.0
	return 0


func _section_end(world: World) -> void:
	print("SECTION section=%d lives=%d hp=%.2f kills=%d/%d" % [_section, world.stats.lives, world.player.hp, world.stats.kills, world.stats.spawned])


func _killed(_victim: Entity, hit: Hit) -> void:
	var source := "other"
	if hit:
		if hit.is_collateral() or hit.weapon == "collateral":
			source = "collateral"
		elif hit.weapon in ["cannon", "dash", "reflect"]:
			source = hit.weapon
		elif hit.by_player():
			match hit.kind:
				Hit.Kind.BULLET: source = "coax"
				Hit.Kind.SHELL, Hit.Kind.BLAST, Hit.Kind.FRAGMENT: source = "cannon"
				Hit.Kind.RAM: source = "ram" if hit.source is Tank else "other"
				Hit.Kind.TAIL: source = "tail"
				Hit.Kind.LASER: source = "ciws"
	kill_sources[source] += 1


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
	else:
		tank.aim_screen = Vector2(DitherView.RESOLUTION) * Vector2(0.5, 0.4)
	if bot == "idle":
		Input.action_release("fire_coax")
		Input.action_release("fire_cannon")
	else:
		Input.action_press("fire_coax")
		if bot == "tap":
			if _tap_down:
				Input.action_release("fire_cannon")
				_tap_down = false
			elif target:
				Input.action_press("fire_cannon")
				_tap_down = true
		elif bot == "charge":
			if _charge_started >= 0.0 and tank.charge >= 1.0 and (is_instance_valid(tank.charge_lock) or t - _charge_started >= 1.5):
				Input.action_release("fire_cannon")
				_charge_started = -1.0
			elif target and _charge_started < 0.0:
				Input.action_press("fire_cannon")
				_charge_started = t
		else:
			Input.action_press("fire_cannon")
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
	if bot != "idle":
		_dodge(world)


## Dashes toward open space when a hostile shot is within 12 m and closing; the dash's own cooldown
## allows one per cooldown.
func _dodge(world: World) -> void:
	var tank := world.player
	if tank.anchor_cooldown > 0.0:
		return
	for projectile in world.projectiles:
		var offset := tank.hit_center() - projectile.global_position
		if projectile.team == Entity.Team.PLAYER or projectile.is_queued_for_deletion() or offset.length() > 12.0 or projectile.velocity.dot(offset) <= 0.0:
			continue
		var side := signf(offset.dot(tank.global_basis.x))
		side = side if side != 0.0 else 1.0
		if absf(tank.course_u + side * Tank.DASH_DISTANCE) > Tank.lateral_limit(world.rail.d + tank.course_offset):
			side = -side
		tank.dash(Vector2(side, 0))
		return
