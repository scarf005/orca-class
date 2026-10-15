extends TestCase
## The burrower tunnels unseen, marks a ring and erupts in it. Only a tank inside the ring is hurt, and once it
## stands exposed it can be shot, then it drops back under.


func _setup(distance := 100.0) -> Array:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage("", true, 3)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.player._respawn = 0.0
	world.player.invuln = 0.0
	world.player.velocity = Vector3.ZERO
	world.player.tail.destroyed = true
	var burrower := Burrower.new()
	burrower.position = world.player.global_position + Vector3(0, 0, -distance)
	world.add_enemy(burrower)
	return [world, burrower]


func _until(burrower: Burrower, state: Burrower.State, limit := 10.0) -> void:
	for i in int(limit * 60.0):
		if burrower.state == state:
			return
		burrower.tick(1.0 / 60.0)


func test_buried_it_cannot_be_hit_and_tunnels_toward_the_tank_until_it_marks_a_ring() -> void:
	var made := _setup()
	var world: World = made[0]
	var burrower: Burrower = made[1]
	check(burrower.hidden and burrower.invulnerable, "it starts buried")
	check_eq(burrower.hit_test(burrower.hit_center() + Vector3(-5, 0, 0), burrower.hit_center() + Vector3(5, 0, 0)), -1.0, "a shot passes over the buried sand")
	var start := burrower.global_position.distance_to(world.player.global_position)
	_until(burrower, Burrower.State.MARK)
	check_eq(burrower.state, Burrower.State.MARK, "it surfaces its ring once within strike range")
	check(burrower.global_position.distance_to(world.player.global_position) < start, "it tunnelled toward the tank")
	check(burrower.telegraphing() and burrower.hidden, "the ring is shown while the burrower is still unseen")


func test_the_eruption_hurts_only_a_tank_inside_the_ring() -> void:
	for dodge in [false, true]:
		var made := _setup(Burrower.STRIKE_RANGE + 5.0)
		var world: World = made[0]
		var burrower: Burrower = made[1]
		var hp := world.player.hp
		_until(burrower, Burrower.State.MARK)
		if dodge:
			world.player.global_position.x += Burrower.ERUPT_RADIUS + 6.0
		_until(burrower, Burrower.State.EXPOSED)
		check_eq(burrower.state, Burrower.State.EXPOSED, "it erupts when the ring runs out")
		if dodge:
			check_eq(world.player.hp, hp, "a tank outside the ring is untouched")
		else:
			check(world.player.hp < hp, "a tank inside the ring is blasted")


func test_exposed_it_takes_a_shell_and_otherwise_drops_back_under() -> void:
	var made := _setup(Burrower.STRIKE_RANGE + 5.0)
	var world: World = made[0]
	var burrower: Burrower = made[1]
	_until(burrower, Burrower.State.EXPOSED)
	check(not burrower.hidden and not burrower.invulnerable, "an exposed burrower is a target")
	check(burrower.hit_test(burrower.hit_center() + Vector3(-5, 0, 0), burrower.hit_center() + Vector3(5, 0, 0)) >= 0.0, "a shot finds it")
	for i in int((Burrower.EXPOSED_TIME + 0.2) * 60.0):
		burrower.tick(1.0 / 60.0)
	check(burrower.hidden and burrower.state != Burrower.State.EXPOSED, "it drops back under the sand")
	_until(burrower, Burrower.State.EXPOSED, 15.0)
	var hit := Hit.make(Hit.Kind.SHELL, 999.0, burrower.hit_center())
	hit.source = world.player
	burrower.take_hit(hit)
	check(burrower.dead and world.stats.kills == 1, "a shell kills the exposed burrower and scores")
