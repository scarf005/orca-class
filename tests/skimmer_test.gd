extends TestCase
## The dune skimmer rides above the sand and rams down a marked lane like the husk, from farther off and faster.


func test_an_undodged_skimmer_rams_while_riding_above_the_sand() -> void:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage("", true, 3)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.player._respawn = 0.0
	world.player.invuln = 0.0
	world.player.velocity = Vector3.ZERO
	var skimmer := Skimmer.new()
	skimmer.position = world.player.global_position + Vector3(0, 0, -Skimmer.new().charge_range + 5.0)
	world.add_enemy(skimmer)
	var hp := world.player.hp
	skimmer.behave(0.01)
	check(skimmer.telegraphing(), "it marks its lane from far off")
	skimmer.behave(skimmer.wind_time + 0.01)
	check_eq(skimmer.state, Charger.State.CHARGE, "it commits to the lane")
	var lowest := INF
	for i in 120:
		if skimmer.is_queued_for_deletion():
			break
		skimmer.behave(1.0 / 60.0)
		lowest = minf(lowest, skimmer.global_position.y - Course.height_at(skimmer.global_position))
	check(lowest >= skimmer.hover - 0.01, "it never touches the sand (%.2f m up)" % lowest)
	check(world.player.hp < hp, "an undodged skimmer damages the hull")
	check(skimmer.is_queued_for_deletion(), "the ram is spent on the hull")
