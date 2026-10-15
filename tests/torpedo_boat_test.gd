extends TestCase
## The gunboat marks its torpedo's lane, then launches one that runs it: a tank that holds the lane is hit, one
## that leaves it is not, the CIWS can burn the torpedo down, and Hard sends a fan.


func _boat(world: World) -> TorpedoBoat:
	var boat := TorpedoBoat.new()
	boat.position = world.player.global_position + Vector3(0, 0, -TorpedoBoat.KEEP_AHEAD)
	world.add_enemy(boat)
	return boat


## A stage 2 world with its tank vulnerable and still, and a boat that has marked its lane and is about to launch.
func _aimed(difficulty := Game.Difficulty.NORMAL) -> Array:
	Game.difficulty = difficulty
	var world := stage("", true, 2)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.player._respawn = 0.0
	world.player.invuln = 0.0
	world.player.velocity = Vector3.ZERO
	world.player.tail.destroyed = true # A frozen tail would stay in the lane when the hull leaves it.
	var boat := _boat(world)
	boat._set_state(TorpedoBoat.State.AIM)
	boat._aim_lane(world.player)
	return [world, boat]


func test_a_tank_that_holds_the_marked_lane_is_hit_and_one_that_leaves_it_is_not() -> void:
	for dodge in [false, true]:
		var made := _aimed()
		var world: World = made[0]
		var boat: TorpedoBoat = made[1]
		var before := world.projectiles.size()
		boat.behave(TorpedoBoat.AIM_TIME + 0.01)
		check_eq(world.projectiles.size() - before, 1, "one torpedo leaves the tube")
		check_eq(boat.state, TorpedoBoat.State.REARM, "the boat rearms after launching")
		if dodge:
			world.player.global_position.x += 14.0
		var hp := world.player.hp
		land(world, before)
		if dodge:
			check_eq(world.player.hp, hp, "a tank 14 m out of the lane is untouched")
		else:
			check(world.player.hp < hp, "a tank that holds the lane takes the torpedo")


func test_the_wind_up_marks_the_lane_and_costs_nothing() -> void:
	var made := _aimed()
	var world: World = made[0]
	var boat: TorpedoBoat = made[1]
	var hp := world.player.hp
	var before := world.projectiles.size()
	boat.behave(0.01)
	check(boat.telegraphing(), "the lamp flashes before the launch")
	check_eq(world.projectiles.size(), before, "the wind-up launches nothing")
	check_eq(world.player.hp, hp, "and deals no damage")
	boat.interrupt()
	boat.behave(TorpedoBoat.AIM_TIME + 0.1)
	check_eq(world.projectiles.size(), before, "an interrupted boat never launches")


func test_the_torpedo_can_be_burned_down_and_hard_fans_three() -> void:
	var made := _aimed()
	var world: World = made[0]
	var boat: TorpedoBoat = made[1]
	boat.behave(TorpedoBoat.AIM_TIME + 0.01)
	var torpedo: Projectile = world.projectiles.back()
	check(torpedo.interceptable, "the CIWS can burn the torpedo down")
	check_eq(torpedo.shape, "torpedo", "it is drawn as a torpedo")
	var hard := _aimed(Game.Difficulty.HARD)
	var count_before: int = (hard[0] as World).projectiles.size()
	(hard[1] as TorpedoBoat).behave(TorpedoBoat.AIM_TIME + 0.01)
	check_eq((hard[0] as World).projectiles.size() - count_before, 3, "Hard fans three torpedoes")
	Game.difficulty = Game.Difficulty.NORMAL
