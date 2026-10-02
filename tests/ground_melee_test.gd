extends TestCase
## The walker kicks and the quad mech stomps a tank that rams up close; staggered, crippled or
## out of reach they do nothing, and both wait out a cooldown.

const STEP := 1.0 / 60.0

var _anchor := Vector3.ZERO


func _setup(world: World, enemy: Enemy) -> Tank:
	enemy.position = Course.ground_at(world.rail.d + world.player.course_offset + 45.0, 0.0)
	_anchor = enemy.position
	world.add_enemy(enemy)
	var tank := world.player
	tank.invulnerable = false
	return tank


## Runs the AI for `seconds` with the enemy held in place and the tank `offset` from it.
func _run(enemy: Enemy, tank: Tank, offset: Vector3, seconds: float) -> void:
	for _i in roundi(seconds / STEP):
		enemy.global_position = _anchor
		tank.global_position = _anchor + offset
		enemy.behave(STEP)


func _walker(world: World) -> Walker:
	var walker := Walker.new()
	walker.weapon = "gun"
	_setup(world, walker)
	walker._attack_timer = INF
	walker.model.rotation.y = 0.0 # Facing -Z.
	return walker


func test_walker_kicks_a_tank_in_front_after_its_wind_up() -> void:
	var world := stage()
	await frames(2)
	var walker := _walker(world)
	var tank := world.player
	tank.local_velocity = Vector2.ZERO
	var hp := tank.hp
	_run(walker, tank, Vector3(3, 0, -5), 0.3)
	check(walker._kick > 0.0, "it plants and flashes its eye")
	check_eq(tank.hp, hp, "and has not kicked yet")
	_run(walker, tank, Vector3(3, 0, -5), 0.3)
	check(tank.hp < hp, "then the kick lands (%.1f of %.1f)" % [tank.hp, hp])
	check_near(absf(tank.local_velocity.x), Walker.KICK_SHOVE, 0.01, "and shoves the tank sideways")
	var shove := signf(tank.local_velocity.x)
	tank.local_velocity = Vector2.ZERO
	walker._kick_cooldown = 0.0
	_run(walker, tank, Vector3(-3, 0, -5), 0.8)
	check_near(signf(tank.local_velocity.x), -shove, 0.01, "away from the walker on the other side")


func test_walker_kick_needs_the_tank_close_and_in_front() -> void:
	var world := stage()
	await frames(2)
	var walker := _walker(world)
	var tank := world.player
	_run(walker, tank, Vector3(0, 0, -7.5), 0.1)
	check_eq(walker._kick, 0.0, "beyond 7 m it stays on its feet")
	_run(walker, tank, Vector3(0, 0, 5), STEP)
	check_eq(walker._kick, 0.0, "a tank behind it is not kicked")
	walker.model.rotation.y = 0.0
	_run(walker, tank, 5.0 * Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(70.0)), STEP)
	check_eq(walker._kick, 0.0, "nor one 70 degrees off its nose")
	walker.model.rotation.y = 0.0
	_run(walker, tank, 5.0 * Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(50.0)), STEP)
	check(walker._kick > 0.0, "but 50 degrees off is inside the arc")


func test_walker_kick_misses_a_tank_that_backs_out() -> void:
	var world := stage()
	await frames(2)
	var walker := _walker(world)
	var tank := world.player
	var hp := tank.hp
	_run(walker, tank, Vector3(0, 0, -5), 0.2)
	_run(walker, tank, Vector3(0, 0, -12), 0.5)
	check_eq(tank.hp, hp, "no damage once the tank is beyond 8 m when it lands")
	check_eq(tank.local_velocity.x, 0.0, "and no shove")
	check(walker._kick_cooldown > 0.0, "the cooldown starts all the same")


func test_walker_kick_is_cancelled_by_stagger_and_crippling() -> void:
	var world := stage()
	await frames(2)
	var walker := _walker(world)
	var tank := world.player
	var hp := tank.hp
	_run(walker, tank, Vector3(0, 0, -5), 0.2)
	walker.stagger = 1.0
	_run(walker, tank, Vector3(0, 0, -5), 0.6)
	check_eq(walker._kick, 0.0, "a stagger during the wind-up cancels it")
	check_eq(tank.hp, hp, "so nothing lands")
	walker.stagger = 0.0
	walker.crippled = true
	_run(walker, tank, Vector3(0, 0, -5), 1.0)
	check_eq(walker._kick, 0.0, "a crippled walker cannot start one")
	check_eq(tank.hp, hp, "and the tank is unharmed")


func test_walker_kick_waits_out_its_cooldown() -> void:
	var world := stage()
	await frames(2)
	var walker := _walker(world)
	var tank := world.player
	tank.invulnerable = true
	var kicks := 0
	var was := 0.0
	for _i in roundi(6.0 / STEP):
		_run(walker, tank, Vector3(0, 0, -5), STEP)
		if walker._kick > was:
			kicks += 1
		was = walker._kick
	# Wind-up 0.45 s then 2.5 s of cooldown: kicks start at 0, ~2.95 and ~5.9 s.
	check_eq(kicks, 3, "three kicks in 6 s, 2.95 s apart")


func _quad(world: World) -> QuadMech:
	var quad := QuadMech.new()
	quad.weapon = "flak"
	_setup(world, quad)
	quad._attack_timer = INF
	return quad


func test_quad_stomps_a_tank_inside_the_ring() -> void:
	var world := stage()
	await frames(2)
	var quad := _quad(world)
	var tank := world.player
	var hp := tank.hp
	_run(quad, tank, Vector3(0, 0, -5), 0.3)
	check(quad._stomp > 0.0, "it rears up inside 8 m")
	check_eq(tank.hp, hp, "and has not landed yet")
	_run(quad, tank, Vector3(0, 0, -5), 0.4)
	check(tank.hp < hp, "the stomp lands on a tank within 6 m (%.1f of %.1f)" % [tank.hp, hp])


func test_quad_stomp_misses_outside_the_ring_and_beyond_range() -> void:
	var world := stage()
	await frames(2)
	var quad := _quad(world)
	var tank := world.player
	var hp := tank.hp
	_run(quad, tank, Vector3(0, 0, -9), 1.0)
	check_eq(quad._stomp, 0.0, "a tank beyond 8 m is left alone")
	_run(quad, tank, Vector3(0, 0, -7), 0.3)
	check(quad._stomp > 0.0, "one at 7 m sets it off")
	_run(quad, tank, Vector3(0, 0, -7), 0.5)
	check_eq(tank.hp, hp, "but 7 m is outside the 6 m ring")


func test_quad_stomp_is_cancelled_by_stagger_and_collapse() -> void:
	var world := stage()
	await frames(2)
	var quad := _quad(world)
	var tank := world.player
	var hp := tank.hp
	_run(quad, tank, Vector3(0, 0, -5), 0.3)
	quad.stagger = 1.0
	_run(quad, tank, Vector3(0, 0, -5), 0.6)
	check_eq(quad._stomp, 0.0, "a stagger cancels the rear-up")
	check_eq(tank.hp, hp, "so nothing lands")
	quad.stagger = 0.0
	for leg in 2:
		quad._legs[leg].lost = true
	_run(quad, tank, Vector3(0, 0, -5), 1.0)
	check_eq(quad._stomp, 0.0, "a collapsed quad cannot start one")
	check_eq(tank.hp, hp, "and the tank is unharmed")


func test_quad_stomp_waits_out_its_cooldown() -> void:
	var world := stage()
	await frames(2)
	var quad := _quad(world)
	var tank := world.player
	tank.invulnerable = true
	var stomps := 0
	var was := 0.0
	for _i in roundi(8.0 / STEP):
		_run(quad, tank, Vector3(0, 0, -5), STEP)
		if quad._stomp > was:
			stomps += 1
		was = quad._stomp
	# Wind-up 0.6 s then 3 s of cooldown: stomps start at 0, ~3.6 and ~7.2 s.
	check_eq(stomps, 3, "three stomps in 8 s, 3 s apart")
