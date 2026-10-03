extends Node
## Plays the stage 1 tiltrotor encounter for the promo clip: the tank drifts clear of the door gun's
## sweep, then charges the main gun to the third lock box and tears the aircraft apart. Run it through
## `just promo`, which records it with Godot's movie writer.
## Usage: xvfb-run -a godot --path . --resolution 1920x1080 --fixed-fps 60 --write-movie builds/promo/promo.avi \
##        -- --run=res://tools/promo.gd --sound [--start=1030] [--tail=3.5]

var _tiltrotor: Tiltrotor
var _seen := false
var _dashed := false
var _dash_at := 0.0
var _fire_since := -1.0
var _killed_at := -1.0


func run() -> int:
	var args: Dictionary = preload("res://scripts/main.gd").args()
	var start := float(args.get("start", "1030"))
	var tail := float(args.get("tail", "3.5"))
	get_parent().get_node("Performance").hide()
	var screen := GameScreen.new()
	add_child(screen)
	var world := screen.world
	world.rail.d = start
	var director := world.director
	director.events = director.events.filter(func(event: Dictionary) -> bool: return event.get("kind") == "tiltrotor")
	director._next_event = 0
	while director._next_event < director.events.size() and director.events[director._next_event].d < start:
		director._next_event += 1
	director.scenery.stream(start, 100000)
	world.player.using_gamepad = true
	world.player.invulnerable = true
	for _i in 30:
		await get_tree().process_frame
	var t := 0.0
	while t < 40.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		_drive(world, t)
		if _killed_at >= 0.0 and t - _killed_at > tail:
			return 0
	push_error("The tiltrotor encounter did not finish.")
	return 1


func _drive(world: World, t: float) -> void:
	var tank := world.player
	if not _seen:
		for enemy in world.enemies:
			if enemy is Tiltrotor:
				_tiltrotor = enemy
				_seen = true
		if not _seen:
			return
	if not is_instance_valid(_tiltrotor) or _tiltrotor.dead or _tiltrotor.state == Tiltrotor.State.CRASH:
		Input.action_release("fire")
		_killed_at = t if _killed_at < 0.0 else _killed_at
		return
	if world.camera.is_position_behind(_tiltrotor.hit_center()):
		return
	tank.aim_screen = world.camera.unproject_position(_tiltrotor.hit_center())
	# Drift away from the beam the moment the door gun starts to fire its sweep.
	if not _dashed and _tiltrotor._sweep > 0.0 and _tiltrotor._sweep < Tiltrotor.SWEEP_TIME - 0.2:
		_dashed = true
		_dash_at = t
		tank.dash(Vector2(1, 0))
	# Once the drift ends, hold the main gun through all three lock boxes; it fires on its own at full.
	if _dashed and t - _dash_at > 0.5 and _fire_since < 0.0:
		_fire_since = t
		Input.action_press("fire")
