extends TestCase
## The sniper tracks with a thin line, locks a ring and fires: a tank that holds the ring is zapped, one that leaves
## it, breaks the line of sight or stays out of reach is not.


func _duel(range_ahead := 80.0) -> Array:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage("", true, 3)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.player._respawn = 0.0
	world.player.invuln = 0.0
	world.player.velocity = Vector3.ZERO
	var glinter := Glinter.new()
	glinter.position = world.player.global_position + Vector3(0, 0, -range_ahead)
	world.add_enemy(glinter)
	glinter._timer = 0.0
	return [world, glinter]


## Steps until `state`, at most `limit` seconds.
func _until(glinter: Glinter, state: Glinter.State, limit := 5.0) -> void:
	for i in int(limit * 60.0):
		if glinter.state == state:
			return
		glinter.behave(1.0 / 60.0)


func test_a_tank_that_holds_the_locked_ring_is_zapped_and_one_that_leaves_it_is_not() -> void:
	for dodge in [false, true]:
		var made := _duel()
		var world: World = made[0]
		var glinter: Glinter = made[1]
		var kinds := []
		world.player.damaged.connect(func(_e: Entity, hit: Hit) -> void: kinds.append(hit.kind))
		var hp := world.player.hp
		_until(glinter, Glinter.State.LOCK)
		check_eq(glinter.state, Glinter.State.LOCK, "the sight line ends in a locked ring")
		check(glinter.telegraphing(), "the ring is the warning")
		check_eq(world.player.hp, hp, "tracking and locking deal no damage")
		if dodge:
			world.player.global_position.x += Glinter.BEAM_RADIUS + 4.0
		for i in 60:
			glinter.behave(1.0 / 60.0)
		if dodge:
			check_eq(world.player.hp, hp, "a tank that leaves the ring is untouched")
		else:
			check(world.player.hp < hp, "a tank that holds the ring is zapped")
			check_eq(kinds, [Hit.Kind.LASER], "the zap is a laser hit")


func test_a_cut_sight_line_cancels_the_shot() -> void:
	var made := _duel()
	var world: World = made[0]
	var glinter: Glinter = made[1]
	var hp := world.player.hp
	_until(glinter, Glinter.State.TRACK)
	check_eq(glinter.state, Glinter.State.TRACK, "it tracks a tank it sees")
	glinter.global_position.y -= 80.0 # The dish drops behind the ground.
	for i in 300:
		glinter.behave(1.0 / 60.0)
	check_eq(glinter.state, Glinter.State.IDLE, "terrain between them ends the track")
	check_eq(world.player.hp, hp, "and nothing is fired")


func test_it_waits_for_a_tank_out_of_reach() -> void:
	var made := _duel(Glinter.REACH.y + 60.0)
	var glinter: Glinter = made[1]
	for i in 300:
		glinter.behave(1.0 / 60.0)
	check_eq(glinter.state, Glinter.State.IDLE, "a tank beyond its reach is not tracked")
