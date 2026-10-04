class_name TestCase
extends Node
## Base for tests. Methods named `test_*` run in deterministic name order; each gets a fresh stage
## world when it calls `stage()`. Run all tests: godot --headless --fixed-fps 60 --path . -- --run=res://tests/run.gd

var failures: Array[String] = []
var skips: Array[String] = []
var _world: World
var _worlds: Array[World] = []
var _current := ""
var _environment: Dictionary = {}


## True only when the caller explicitly marked a temporary data root and Godot is using it.
## Direct runs remain allowed, but persistence-sensitive tests can skip with this diagnostic.
static func is_isolated() -> bool:
	return _sandbox_isolated(OS.get_environment("ORCA_TEST_DATA_HOME"), OS.get_environment("XDG_DATA_HOME"), OS.get_user_data_dir())


static func _sandbox_isolated(marker: String, xdg_data_home: String, user_data_dir: String) -> bool:
	if marker.is_empty() or xdg_data_home != marker:
		return false
	var root := marker.simplify_path().trim_suffix("/")
	var data := user_data_dir.simplify_path()
	return data.begins_with(root + "/")


func begin(name: String) -> void:
	_current = name
	_environment = _capture_environment()
	# The method name makes incidental randomness reproducible. Tests that need a particular
	# sequence can still call seed(...) after begin(), overriding this baseline locally.
	seed(hash(name))


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append("%s: %s" % [_current, message])


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual - expected) <= tolerance, "%s (expected %.3f ± %.3f, got %.3f)" % [message, expected, tolerance, actual])


## Mark the current test as unsupported without treating it as a passing test.
## The runner prints this reason in its skip report and keeps failures separate.
func skip(reason: String) -> void:
	skips.append("%s: %s" % [_current, reason])


## A running stage with the player, as the game creates it. Input is disabled so tests drive it.
## The game starts without an RWS; tests get one unless they are about picking it up.
func stage(checkpoint := "", rws := true) -> World:
	# A method may construct several scenarios without an await between them. Queue every
	# previous scenario before making the next one so stale worlds cannot process against the
	# new World.current or clear it during their later teardown.
	_queue_owned_worlds()
	_world = World.new()
	_worlds.append(_world)
	add_child(_world)
	_world.start_stage(checkpoint)
	_world.player.input_enabled = false
	if rws:
		_world.player.mount_rws()
	return _world


## Flies the projectiles fired since `before` (a `world.projectiles.size()`) to their end, without frames passing.
func land(world: World, before: int) -> void:
	for projectile: Projectile in world.projectiles.slice(before):
		for _i in 600:
			if projectile.is_queued_for_deletion():
				break
			projectile.step(1.0 / 60.0)


func frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


## Waits until `condition` holds or `limit` frames pass; returns whether it held.
func wait_until(condition: Callable, limit := 600) -> bool:
	for _i in limit:
		if condition.call():
			return true
		await get_tree().process_frame
	return condition.call()


## Condition for `wait_until`: the object has been freed. Holds only a weak reference.
func gone(object: Object) -> Callable:
	var ref: WeakRef = weakref(object)
	return func() -> bool: return ref.get_ref() == null


## Remove all owned stages. Internal cleanup deliberately does not restore the method baseline:
## tests commonly call cleanup() before constructing their next legitimate stage. The runner calls
## cleanup(true) at the method boundary to restore every captured global instead.
func cleanup(restore_environment := false) -> void:
	_queue_owned_worlds()
	Engine.time_scale = 1.0
	_release_input()
	if restore_environment:
		_restore_environment()


func _queue_owned_worlds() -> void:
	var worlds: Array[World] = _worlds.duplicate()
	if is_instance_valid(_world) and not worlds.has(_world):
		worlds.append(_world)
	for world: World in worlds:
		if is_instance_valid(world):
			world.queue_free()
	_worlds.clear()
	_world = null


func _capture_environment() -> Dictionary:
	var actions := {}
	for action: StringName in InputMap.get_actions():
		var events: Array = []
		for event: InputEvent in InputMap.action_get_events(action):
			events.append(event.duplicate(true))
		actions[action] = {
			"deadzone": InputMap.action_get_deadzone(action),
			"events": events,
		}
	var tuning_values: Array = []
	for row: Array in GameTuning.new()._rows:
		tuning_values.append(row[1].call())
	return {
		"silent": Game.silent,
		"settings": Game.settings.duplicate(true),
		"bests": Game.bests.duplicate(true),
		"difficulty": Game.difficulty,
		"checkpoint": Game.checkpoint,
		"course_flat": Course.flat,
		"tuning": tuning_values,
		"actions": actions,
		"paused": get_tree().paused,
		"time_scale": Engine.time_scale,
		"mouse_mode": Input.mouse_mode,
	}


func _restore_environment() -> void:
	if _environment.is_empty():
		return
	Game.silent = _environment.silent
	Game.settings = _environment.settings.duplicate(true)
	Game.bests = _environment.bests.duplicate(true)
	Game.difficulty = _environment.difficulty
	Game.checkpoint = _environment.checkpoint
	Course.flat = _environment.course_flat
	var rows: Array = GameTuning.new()._rows
	var tuning_values: Array = _environment.tuning
	for i in rows.size():
		rows[i][2].call(tuning_values[i])
	var actions: Dictionary = _environment.actions
	Input.mouse_mode = _environment.mouse_mode
	get_tree().paused = _environment.paused
	Engine.time_scale = _environment.time_scale
	Game.apply_settings()
	# apply_settings is production's authoritative settings path; restore the exact captured
	# action map afterwards so a test that edited InputMap directly cannot leak its edit.
	for action: StringName in InputMap.get_actions():
		InputMap.erase_action(action)
	for action: StringName in actions:
		var snapshot: Dictionary = actions[action]
		InputMap.add_action(action, snapshot.deadzone)
		for event: InputEvent in snapshot.events:
			InputMap.action_add_event(action, event.duplicate(true))
	_release_input()


func _release_input() -> void:
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)
