extends Node
## Plays the stage with a simple bot and saves screenshots, for smoke tests and visual checks.
## Usage: xvfb-run -a godot --path . -- --run=res://tools/autoplay.gd --seconds=30 --shots=5,10 \
##        [--checkpoint=boss] [--stage=2] [--out=builds/auto] [--god] [--scale=1] [--seed=1]
##        [--range=3000,3300] # print frame times within a course-distance interval
##        [--milestones] [--verify] # capture sections, authored peaks, boss phases and results; fail unless results arrive
##        [--compare-city] [--trace-elites] # same-distance Stage 1 census and hunter sight/fire diagnostics
##        [--lane=-1|1] # hold the tank against the left or right kerb
##        [--trace-ranges] # every 6 frames: each live enemy's distance ahead of the tank and lateral offset
##        [--trace-fire] # one line per enemy projectile with the shooter's kind, to see who actually attacks and how often
##        [--storm=30] # start the stage's storm right away for that many seconds, to judge its look
##        [--trace-damage] # one line per hit on the tank: where, by what, and the hull left after it
## Every leap off a launch ramp prints a LEAP line and its landing a LAND line.

var screen: GameScreen
var bot := "hold"
var cleared := false
var deaths := 0
var kill_sources := {"coax": 0, "cannon": 0, "ram": 0, "dash": 0, "tail": 0, "ciws": 0, "collateral": 0, "reflect": 0, "other": 0}
var _last_tap := -1.0
var _charge_started := -1.0
var _shots_seen := 0
var _section := 0
var _out := ""
var _milestones := false
var _elite_time := 0.0
var _elite_visible := 0.0
var _enemy_frames := 0 ## Live-enemy frames within 150 m, for the submerged and hidden-behind-buildings counts.
var _submerged: Array[String] = []
var _hidden: Array[String] = []
var _section_kills := 0
var _section_spawned := 0
var _section_damage := 0.0
var _section_deaths := 0
var _peak_enemies := 0
var _peaks := {}
var _peak_capture_at := -1.0
var _compare_city := false
var _compare_section := 0
var _compare_kills := 0
var _lane := 0.0 ## -1 or 1 pins the tank against that kerb.
var _compare_spawned := 0
var _fired := {}


func run() -> int:
	var args: Dictionary = preload("res://scripts/main.gd").args()
	seed(int(args.get("seed", "1")))
	var difficulty: String = args.get("difficulty", "normal")
	if difficulty not in ["easy", "normal", "hard"]:
		push_error("Unknown difficulty: %s" % difficulty)
		return 1
	Game.difficulty = {"easy": Game.Difficulty.EASY, "normal": Game.Difficulty.NORMAL, "hard": Game.Difficulty.HARD}[difficulty]
	bot = args.get("bot", "hold")
	if bot not in ["hold", "idle", "tap", "charge"]:
		push_error("Unknown bot mode: %s" % bot)
		return 1
	var out: String = args.get("out", "builds/auto")
	_out = out
	_milestones = args.has("milestones")
	_compare_city = args.has("compare-city")
	_lane = float(args.get("lane", "0"))
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
	for event: Dictionary in world.director.events:
		if event.get("peak", false):
			_peaks[Course.section_at(event.d)] = float(event.d)
	world.killed.connect(_killed)
	world.player.life_lost.connect(func() -> void: deaths += 1)
	if args.has("trace-damage"):
		world.player.damaged.connect(func(_tank: Entity, hit: Hit) -> void: print("DAMAGE t=%.2f d=%.0f source=%s kind=%s hp=%.1f" % [world.stats.time, world.rail.d, hit.source.get_script().resource_path.get_file().get_basename() if is_instance_valid(hit.source) else "none", Hit.Kind.keys()[hit.kind], world.player.hp]))
	world.stage_cleared.connect(func() -> void:
		cleared = true
		_section_end(world))
	_section = world.director.section
	world.director.section_changed.connect(func(section: int) -> void:
		_section_end(world)
		_section = section
		_capture("section-%d" % section))
	world.director.checkpoint_reached.connect(func(checkpoint: String) -> void:
		print("CHECKPOINT name=%s t=%.2f d=%.0f" % [checkpoint, world.stats.time, world.rail.d]))
	if args.has("god"):
		world.player.invulnerable = true
	if args.has("storm"):
		world.director.storm.emit(float(args.storm))
	var elapsed := 0.0
	var frames := 0
	var slow_frames := 0
	var worst := 0.0
	var frame_times := PackedFloat32Array()
	var range_bounds := String(args.get("range", "")).split(",", false)
	var range_times := PackedFloat32Array()
	var front_total := 0.0
	var boss_start := -1.0
	var boss_phase := 0
	var boss_kind := ""
	var active_boss: Entity
	var tank_structure_violations := 0
	var camera_pull_ins := 0
	var mode := world.rail.mode
	var leaping := false
	var telegraphs := {}
	await get_tree().process_frame
	await _capture("section-%d" % _section)
	while elapsed < seconds:
		var start := Time.get_ticks_usec()
		await get_tree().process_frame
		var frame_ms := (Time.get_ticks_usec() - start) / 1000.0
		var delta := get_process_delta_time()
		elapsed += delta
		frames += 1
		if _compare_city and _compare_section + 1 < Stage2.SECTION_STARTS.size() and world.rail.d >= Stage2.SECTION_STARTS[_compare_section + 1]:
			_comparison_end(world)
			_compare_section += 1
		var elite_present := false
		for enemy in world.enemies:
			if not enemy.dead and not world.camera.is_position_behind(enemy.hit_center()):
				front_total += 1.0
			_check_enemy(world, enemy)
			if enemy.dead or not (enemy is BipedMech or enemy is Hind):
				continue
			_elite_time += delta
			var at := enemy.hit_center()
			if world.camera.is_position_behind(at):
				continue
			var pixel := world.camera.unproject_position(at) / Vector2(DitherView.RESOLUTION)
			if pixel.x >= 0.2 and pixel.x <= 0.8 and pixel.y >= 0.2 and pixel.y <= 0.8 and not world.director.scenery.line_blocked(world.camera.global_position, at):
				_elite_visible += delta
				elite_present = true
		if _peaks.has(_section) and world.rail.d >= float(_peaks[_section]):
			_peak_capture_at = elapsed + 0.4
			_peaks.erase(_section)
		if _peak_capture_at >= 0.0 and elapsed >= _peak_capture_at:
			await _capture("section-%d-peak" % _section)
			_peak_capture_at = -1.0
		if not Course.stage is Stage2 and elite_present and world.enemies.size() > _peak_enemies:
			_peak_enemies = world.enemies.size()
			await _capture("section-%d-peak" % _section)
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
		for structure in Course.structure_boxes:
			if Prop.box_hit(structure.pose, structure.size, world.player.global_position, world.player.global_position, Tank.HULL_RADIUS - 0.01) >= 0.0:
				tank_structure_violations += 1
				break
		_drive(world, elapsed)
		if world.rail.mode != Rail.Mode.ARENA and Course.stage is Stage2:
			var camera_u := Course.stage.camera_u(world.rail.d, world.player.course_u)
			var expected_eye := Course.to_world(world.rail.d - ChaseCamera.RAIL_BACK, camera_u)
			expected_eye.y = maxf(Course.height(world.rail.d - ChaseCamera.RAIL_BACK, camera_u), world.player.global_position.y - 1.0) + ChaseCamera.RAIL_HEIGHT
			var safe_eye := world.director.scenery.camera_position(world.player.hit_center(), expected_eye)
			if safe_eye.distance_to(expected_eye) > 0.05 and not Course.stage.in_arena(world.rail.d):
				camera_pull_ins += 1
				if camera_pull_ins <= 10:
					var blockers := []
					for structure in Course.structure_boxes:
						if Prop.box_hit(structure.pose, structure.size, world.player.hit_center(), expected_eye, 0.8) >= 0.0:
							blockers.append("%s@%.0f,%.0f" % [structure.kind, structure.d, structure.u])
					print("CAMERA_PULL d=%.1f u=%.1f amount=%.2f blockers=%s" % [world.rail.d, world.player.course_u, safe_eye.distance_to(expected_eye), blockers])
		if args.has("trace-elites") and frames % 60 == 0:
			for enemy in world.enemies:
				if enemy is BipedMech or enemy is Hind:
					print("ELITE t=%.2f kind=%s hp=%.0f position=%s warning=%s timer=%s shots=%d" % [elapsed, enemy.get_script().resource_path.get_file(), enemy.hp, Course.to_course(enemy.global_position), enemy.telegraphing(), enemy.get("_attack_timer"), world.projectiles.size()])
					print("ELITE_VIEW pixel=%s blocked=%s stance=%s" % [world.camera.unproject_position(enemy.hit_center()) / Vector2(DitherView.RESOLUTION), world.director.scenery.line_blocked(world.camera.global_position, enemy.hit_center()), enemy.get("_stance")])
		if args.has("trace-fire"):
			for projectile in world.projectiles:
				if not _fired.has(projectile.get_instance_id()):
					_fired[projectile.get_instance_id()] = true
					if projectile.hit != null and projectile.hit.source is Enemy:
						print("FIRE t=%.2f id=%d kind=%s" % [elapsed, projectile.hit.source.get_instance_id(), projectile.hit.source.get_script().resource_path.get_file().get_basename()])
		if args.has("trace-ranges") and frames % 6 == 0:
			for enemy in world.enemies:
				if not enemy.dead:
					print("RANGE t=%.1f id=%d kind=%s ahead=%.0f u=%.0f" % [elapsed, enemy.get_instance_id(), enemy.get_script().resource_path.get_file().get_basename(), Course.to_course(enemy.global_position).x - world.rail.d - world.player.course_offset, Course.to_course(enemy.global_position).y])
		if args.has("profile") and frames % 60 == 0:
			print("t=%.1f frame=%.1fms process=%.1fms draw_calls=%d objects=%d particles=%d enemies=%d props=%d" % [elapsed, frame_ms,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				world.fx.particle_count(), world.enemies.size(),
				world.props.get_child_count()])
		if not shots.is_empty() and elapsed >= shots[0]:
			var at: float = shots.pop_front()
			var stamp := "%03d" % int(at) if at == floorf(at) else "%06.2f" % at # Bursts of fractional shots keep their own files.
			get_viewport().get_texture().get_image().save_png("%s/t%s.png" % [out, stamp])
		if world.player.airborne != leaping:
			leaping = world.player.airborne
			print("%s t=%.2f d=%.0f u=%.1f floor=%.2f speed=%.0f" % ["LEAP" if leaping else "LAND", world.stats.time, world.rail.d + world.player.course_offset, world.player.course_u, Course.height(world.rail.d + world.player.course_offset, world.player.course_u), world.rail.speed])
		if world.rail.mode != mode:
			mode = world.rail.mode
			print("MODE mode=%s t=%.2f d=%.0f" % [Rail.Mode.keys()[mode], world.stats.time, world.rail.d])
		if is_instance_valid(world.boss) and not world.boss.dead:
			var boss_state: Variant = world.boss.get("phase")
			var phase := int(boss_state if boss_state != null else 0) + 1
			if active_boss != world.boss or boss_phase != phase:
				if active_boss != world.boss:
					boss_start = elapsed
				active_boss = world.boss
				boss_kind = world.boss.get_script().resource_path.get_file().get_basename()
				boss_phase = phase
				print("BOSS kind=%s phase=%d t=%.2f d=%.0f hp=%.0f music=%s" % [world.boss.get_script().resource_path.get_file().get_basename(), phase, world.stats.time, world.rail.d, world.boss.hp, Sfx._music_path])
				_capture("%s-phase-%d" % [world.boss.get_script().resource_path.get_file().get_basename(), phase])
			var attack_time: Variant = world.boss.get("_attack_time") # Bosses that fire by turret (the wing) have none.
			if _milestones and attack_time != null and world.boss is Enemy and (world.boss as Enemy).telegraphing() and float(attack_time) > 0.3:
				var kind := int(world.boss.get("_attack"))
				var attack: String = HiMo.Attack.keys()[kind] if world.boss is HiMo else Hovercraft.Attack.keys()[kind] if world.boss is Hovercraft else str(kind)
				var key := "%s-phase-%d-%s" % [boss_kind, phase, attack.to_lower()]
				if world.boss is HiMo and (world.boss as HiMo)._overcharge:
					key += "-overcharged"
				var ready := not world.boss is HiMo or kind != HiMo.Attack.RAIL or (world.boss as HiMo)._attack_time > (world.boss as HiMo)._wind() - 0.7
				if ready and not telegraphs.has(key):
					telegraphs[key] = true
					_capture(key)
		elif not boss_kind.is_empty():
			print("BOSS_END kind=%s t=%.2f d=%.0f fight=%.2fs" % [boss_kind, world.stats.time, world.rail.d, elapsed - boss_start])
			boss_kind = ""
			active_boss = null
		if world.player.dead or screen._finished:
			break
	if cleared:
		while screen._results == null:
			await get_tree().process_frame
		await get_tree().process_frame
		await _capture("results")
		print("RESULTS stage=%d heading=%s ranked=%s" % [screen.stage, screen._results.clear_heading(), world.stats.ranked])
	var stats := world.stats
	if _compare_city:
		_comparison_end(world)
	if not cleared:
		_section_end(world)
	if not frame_times.is_empty():
		frame_times.sort()
		print("BENCH median=%.2fms p95=%.2fms samples=%d" % [frame_times[frame_times.size() / 2], frame_times[int(frame_times.size() * 0.95)], frame_times.size()])
	if not range_times.is_empty():
		range_times.sort()
		print("RANGE d=%s median=%.2fms p95=%.2fms samples=%d" % [args.range, range_times[range_times.size() / 2], range_times[int(range_times.size() * 0.95)], range_times.size()])
	print("AUTOPLAY d=%.0f score=%d kills=%d/%d lives=%d hp=%.0f enemies=%d projectiles=%d frames=%d slow=%d worst=%.1fms" % [
		world.rail.d, stats.score, stats.kills, stats.spawned, stats.lives, world.player.hp, world.enemies.size(),
		world.projectiles.size(), frames, slow_frames, worst])
	print("STRUCTURE_CHECK tank_inside_structure=%d samples=%d" % [tank_structure_violations, frames])
	print("ENEMY_CHECK submerged_frames=%d hidden_frames=%d enemy_frames=%d submerged=%s hidden=%s" % [_submerged.size(), _hidden.size(), _enemy_frames, _worst(_submerged), _worst(_hidden)])
	print("CAMERA_CHECK pull_in_outside_arenas=%d samples=%d" % [camera_pull_ins, frames])
	print("PROBE difficulty=%s bot=%s cleared=%s dead=%s time=%.2f d=%.0f lives=%d deaths=%d damage_taken=%.2f kills=%d/%d front_mean=%.2f coax=%d cannon=%d ram=%d dash=%d tail=%d ciws=%d collateral=%d reflect=%d other=%d cannon_shots=%d charged_shots=%d healing_melee=%.2f healing_repair=%.2f" % [
		difficulty, bot, cleared and not world.player.dead, world.player.dead, stats.time, world.rail.d, stats.lives, deaths, stats.damage_taken, stats.kills, stats.spawned, front_total / maxi(frames, 1),
		kill_sources.coax, kill_sources.cannon, kill_sources.ram, kill_sources.dash, kill_sources.tail, kill_sources.ciws, kill_sources.collateral, kill_sources.reflect, kill_sources.other, stats.shots, stats.charged_shots, stats.melee_healing, stats.repair_healing])
	for action in ["fire", "move_left", "move_right"]:
		Input.action_release(action)
	Engine.time_scale = 1.0
	return 1 if args.has("verify") and (not cleared or screen._results == null or tank_structure_violations > 0 or camera_pull_ins > 0) else 0


## The most frequent offenders as "kind@where xframes".
func _worst(samples: Array[String]) -> String:
	var counts := {}
	for sample in samples:
		counts[sample] = counts.get(sample, 0) + 1
	var keys := counts.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b])
	return ", ".join(keys.slice(0, 8).map(func(key: String) -> String: return "%s x%d" % [key, counts[key]]))


## Counts a ground enemy whose body is under water, and an enemy in front of the camera that a building hides.
func _check_enemy(world: World, enemy: Enemy) -> void:
	var at := enemy.hit_center()
	if enemy.dead or at.distance_to(world.player.global_position) > 150.0:
		return
	_enemy_frames += 1
	var c := Course.to_course(at)
	var where := "%s@d%d,u%d" % [enemy.get_script().resource_path.get_file().get_basename(), snappedi(int(c.x), 50), snappedi(int(c.y), 10)]
	if not enemy.flying and not (enemy is DroneBoat or enemy is SeaMine) and Water.surface_at(at) > at.y:
		_submerged.append(where)
	if not world.camera.is_position_behind(at) and Course.structure_boxes.any(func(box: Dictionary) -> bool: return Prop.box_hit(box.pose, box.size, world.camera.global_position, at) >= 0.0):
		_hidden.append(where)


func _capture(name: String) -> void:
	if _milestones:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])


func _section_end(world: World) -> void:
	var stats := world.stats
	print("SECTION section=%d t=%.2f d=%.0f lives=%d hp=%.2f kills=%d/%d section_kills=%d section_spawned=%d lives_lost=%d damage_taken=%.2f elite_visible=%.2f%% elite_seconds=%.2f" % [_section, stats.time, world.rail.d, stats.lives, world.player.hp, stats.kills, stats.spawned, stats.kills - _section_kills, stats.spawned - _section_spawned, deaths - _section_deaths, stats.damage_taken - _section_damage, 100.0 * _elite_visible / maxf(_elite_time, 0.0001), _elite_time])
	_elite_time = 0.0
	_elite_visible = 0.0
	_peak_enemies = 0
	_section_kills = stats.kills
	_section_spawned = stats.spawned
	_section_damage = stats.damage_taken
	_section_deaths = deaths


## Measures either stage over the city's distances, separately from its actual section/music boundaries.
func _comparison_end(world: World) -> void:
	print("REFERENCE stage=%d section=%d d=%.0f kills=%d spawned=%d" % [screen.stage, _compare_section, world.rail.d, world.stats.kills - _compare_kills, world.stats.spawned - _compare_spawned])
	_compare_kills = world.stats.kills
	_compare_spawned = world.stats.spawned


func _killed(_victim: Entity, hit: Hit) -> void:
	var source := "other"
	if hit:
		if hit.is_collateral() or hit.weapon == "collateral":
			source = "collateral"
		elif hit.weapon in ["cannon", "canister", "dash", "reflect"]:
			source = "cannon" if hit.weapon == "canister" else hit.weapon
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
	if _lane != 0.0:
		tank.course_u = _lane * Tank.lateral_limit(world.rail.d)
	var target: Entity = null
	var best := INF
	for enemy in world.enemies:
		if enemy is Enemy and (enemy as Enemy).hidden:
			continue
		var distance := enemy.global_position.distance_to(tank.global_position)
		if distance < best and not world.camera.is_position_behind(enemy.hit_center()):
			best = distance
			target = enemy
	if target is Wing and not (target as Wing).aim_parts().is_empty():
		tank.aim_screen = world.camera.unproject_position((target as Wing).aim_parts().values()[0][0])
	elif target:
		tank.aim_screen = world.camera.unproject_position(target.hit_center())
	else:
		tank.aim_screen = Vector2(DitherView.RESOLUTION) * Vector2(0.5, 0.4)
	if bot == "idle":
		Input.action_release("fire")
	elif bot == "tap":
		# A press for one frame every 0.3 s at the nearest target: coax bursts only.
		Input.action_release("fire")
		if target and t - _last_tap >= 0.3:
			Input.action_press("fire")
			_last_tap = t
	elif bot == "charge":
		# Let go at full charge, or once a special round has fired itself at its step.
		if _charge_started >= 0.0 and (tank.charge >= 1.0 or world.stats.shots != _shots_seen):
			_shots_seen = world.stats.shots
			Input.action_release("fire")
			_charge_started = -1.0
		elif target and _charge_started < 0.0:
			Input.action_press("fire")
			_charge_started = t
	elif world.stats.shots != _shots_seen:
		# Mashing: let go for a frame after every shot, so the next hold starts a new charge.
		_shots_seen = world.stats.shots
		Input.action_release("fire")
	else:
		Input.action_press("fire")
	if _ride_ramp(world):
		return
	# Hold measures sustained fire without dodging; other bots retain the evasive probe.
	if bot == "hold":
		Input.action_release("move_left")
		Input.action_release("move_right")
		return
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
	if bot not in ["idle", "hold"]:
		_dodge(world)


## Lines up on a launch ramp a little ahead and drifts across its track all the way up. Returns whether it is on one.
func _ride_ramp(world: World) -> bool:
	var tank := world.player
	var d := world.rail.d + tank.course_offset
	for ahead in range(0, 300, 10):
		var u := _ramp_lane(d + ahead, tank.course_u)
		if is_nan(u):
			continue
		Input.action_release("move_left")
		Input.action_release("move_right")
		if Course.stage.ramp_at(d, tank.course_u) < 0.0:
			Input.action_press("move_right" if u > tank.course_u else "move_left")
		elif tank.anchor_cooldown <= 0.0:
			tank.dash(Vector2(-signf(tank.course_u - u) if absf(tank.course_u - u) > 1.0 else 1.0, 0))
		return true
	return false


## The lateral offset nearest `near` at which a launch ramp's track (StageDef.ramp_at) crosses `d`, or NAN.
func _ramp_lane(d: float, near: float) -> float:
	var limit := Tank.lateral_limit(d)
	var best := NAN
	for u in range(-int(limit), int(limit) + 1, 2):
		if Course.stage.ramp_at(d, float(u)) >= 0.0 and (is_nan(best) or absf(u - near) < absf(best - near)):
			best = float(u)
	return best


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
