extends TestCase
## The water skiff warns, commits and can be countered by both guns and the automatic tail, not CIWS.


func _boat(world: World, ahead := 25.0) -> DroneBoat:
	var boat := DroneBoat.new()
	boat.position = world.player.global_position + Vector3(0, 0, -ahead)
	world.add_enemy(boat)
	return boat


func test_warning_flashes_faster_before_a_committed_ram() -> void:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage("", true, 2)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.player.velocity = Vector3.ZERO
	var boat := _boat(world)
	var hp := world.player.hp
	boat.behave(0.01)
	check(boat.telegraphing(), "bow flashes before the charge")
	var period := boat.flash_period()
	boat.behave(0.6)
	check(boat.flash_period() < period, "bow flashes accelerate as the warning ends")
	check_eq(world.player.hp, hp, "warning never deals damage")
	boat.behave(0.41)
	check_eq(boat.state, DroneBoat.State.RAM, "warning ends in a committed ram")
	for i in 60:
		if boat.is_queued_for_deletion():
			break
		boat.behave(1.0 / 60.0)
	check(world.player.hp < hp, "an undodged ram damages the hull")
	check(boat.is_queued_for_deletion(), "ram consumes the boat without awarding a kill")
	check_eq(world.stats.kills, 0, "self-detonation is not a player kill")


func test_coax_shell_and_both_tail_swats_kill_but_ciws_does_not_target() -> void:
	for counter in ["coax", "shell", "automatic_tail", "dash_tail"]:
		var world := stage("", true, 2)
		world.process_mode = Node.PROCESS_MODE_DISABLED
		var boat := _boat(world, 5.0)
		check(not boat.interceptable and world.player._ciws_pick_target() != boat, "laser does not target a surface boat")
		if counter == "coax":
			for i in Armament.COAX_BURST_ROUNDS:
				var hit := Hit.make(Hit.Kind.BULLET, Armament.GUNS[8].damage, boat.hit_center())
				hit.caliber = 8
				hit.source = world.player
				boat.take_hit(hit)
		elif counter == "shell":
			var hit := Hit.make(Hit.Kind.SHELL, Armament.QUICK_DAMAGE.x * Armament.SHELL_DAMAGE_SCALE, boat.hit_center())
			hit.source = world.player
			boat.take_hit(hit)
		else:
			boat.state = DroneBoat.State.TELEGRAPH
			check(world.player._is_imminent(boat), "charging boat has swat priority")
			world.player.swat(counter == "automatic_tail")
		check(boat.dead, "%s destroys the boat" % counter)
		check_eq(world.stats.kills, 1, "counter scores exactly one kill")


func test_easy_warning_is_longer_and_a_dodge_makes_the_ram_miss() -> void:
	Game.difficulty = Game.Difficulty.EASY
	var world := stage("", true, 2)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.player.velocity = Vector3.ZERO
	var boat := _boat(world)
	boat.behave(0.01)
	boat.behave(1.1)
	check(boat.telegraphing(), "easy doubles the warning window")
	boat.behave(1.0)
	var direction := boat._direction
	world.player.global_position.x += 15.0
	var hp := world.player.hp
	for i in 60:
		boat.behave(1.0 / 60.0)
	check_eq(boat._direction, direction, "ram never steers after commitment")
	check_eq(world.player.hp, hp, "a lateral dodge clears its line")
	Game.difficulty = Game.Difficulty.NORMAL
