class_name TestCase
extends Node
## Base for tests. Methods named `test_*` run in order; each gets a fresh stage world when it
## calls `stage()`. Run all tests: godot --headless --fixed-fps 60 --path . -- --run=res://tests/run.gd

var failures: Array[String] = []
var _world: World
var _current := ""


func begin(name: String) -> void:
	_current = name


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append("%s: %s" % [_current, message])


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	check(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual - expected) <= tolerance, "%s (expected %.3f ± %.3f, got %.3f)" % [message, expected, tolerance, actual])


## A running stage with the player, as the game creates it. Input is disabled so tests drive it.
## The game starts without an RWS; tests get one unless they are about picking it up.
func stage(checkpoint := "", rws := true) -> World:
	_world = World.new()
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


func cleanup() -> void:
	if is_instance_valid(_world):
		_world.queue_free()
		_world = null
	Engine.time_scale = 1.0
