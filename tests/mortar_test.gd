extends TestCase
## The crew walks a barrage of marked shells down the tank's lane: holding the lane is hit, leaving it is safe,
## and the spitter it shares its volley with still spits spore clouds.


func _ready_world(number: int) -> World:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage("", true, number)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.player._respawn = 0.0
	world.player.invuln = 0.0
	world.player.velocity = Vector3.ZERO
	world.player.tail.destroyed = true
	return world


func _crew(world: World, naval := false) -> Mortar:
	var crew := Mortar.new()
	crew.naval = naval
	crew.position = world.player.global_position + Vector3(0, 0, -80)
	world.add_enemy(crew)
	return crew


func _hazards(world: World) -> int:
	return world.get_children().filter(func(node: Node) -> bool: return node is Hazard).size()


func test_the_barrage_walks_down_the_tanks_lane_in_even_steps() -> void:
	var world := _ready_world(3)
	var crew := _crew(world)
	var lane := Course.to_course(world.player.global_position)
	for i in 3:
		var landing := Course.to_course(crew._aim(world.player, i, 3, crew._flight(i)))
		check_near(landing.y, lane.y, 0.01, "shell %d lands in the tank's lane" % i)
		check_near(landing.x, lane.x + (i - 1) * Mortar.BARRAGE_STEP, 0.01, "shell %d lands %d steps from the tank" % [i, i - 1])


func test_a_tank_that_holds_the_lane_is_shelled_and_one_that_leaves_it_is_not() -> void:
	for dodge in [false, true]:
		var world := _ready_world(3)
		var crew := _crew(world)
		var before := world.projectiles.size()
		crew._volley(world.player)
		check_eq(world.projectiles.size() - before, 3, "the volley is three shells")
		if dodge:
			world.player.global_position.x += 15.0
		var hp := world.player.hp
		land(world, before)
		if dodge:
			check_eq(world.player.hp, hp, "a tank 15 m out of the lane is untouched")
		else:
			check(world.player.hp < hp, "a tank that holds the lane is shelled")


func test_dune_and_barge_shells_differ_and_leave_no_spore_cloud() -> void:
	var world := _ready_world(2)
	var dune := _crew(world)
	var barge := _crew(world, true)
	var before := world.projectiles.size()
	dune._volley(world.player)
	var dune_shell: Projectile = world.projectiles[before]
	barge._volley(world.player)
	var barge_shell: Projectile = world.projectiles[before + 3]
	check(barge_shell.blast_radius > dune_shell.blast_radius, "a depth charge blasts wider than a mortar shell")
	check(dune_shell.interceptable and barge_shell.interceptable, "the CIWS can burn either down")
	land(world, before)
	check_eq(_hazards(world), 0, "high explosive leaves no cloud behind")


func test_the_spitter_still_leaves_a_spore_cloud_where_its_shells_land() -> void:
	var world := _ready_world(1)
	var spitter := Spitter.new()
	spitter.position = world.player.global_position + Vector3(0, 0, -80)
	world.add_enemy(spitter)
	var before := world.projectiles.size()
	spitter._volley(world.player)
	land(world, before)
	check(_hazards(world) > 0, "spore shells leave a cloud")
