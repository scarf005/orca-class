extends TestCase
## The husk marks a lane and charges down it. An undodged charge is spent on the hull, a sidestep makes it
## overshoot and stand winded, and its horned shell turns the coax from the front only.


func _husk(world: World, ahead := 30.0) -> Husk:
	var husk := Husk.new()
	husk.position = world.player.global_position + Vector3(0, 0, -ahead)
	world.add_enemy(husk)
	return husk


func _charging(world: World) -> Husk:
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.player.velocity = Vector3.ZERO
	var husk := _husk(world)
	husk.behave(0.01)
	husk.behave(husk.wind_time + 0.01)
	return husk


func test_wind_up_marks_the_lane_and_an_undodged_charge_is_spent_on_the_hull() -> void:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage("", true, 1)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.player.velocity = Vector3.ZERO
	var husk := _husk(world)
	var hp := world.player.hp
	husk.behave(0.01)
	check(husk.telegraphing(), "it paws the ground before the charge")
	check_eq(world.player.hp, hp, "the wind-up never deals damage")
	husk.behave(husk.wind_time + 0.01)
	check_eq(husk.state, Charger.State.CHARGE, "the wind-up ends in a committed charge")
	for i in 120:
		if husk.is_queued_for_deletion():
			break
		husk.behave(1.0 / 60.0)
	check(world.player.hp < hp, "an undodged charge damages the hull")
	check(husk.is_queued_for_deletion(), "the charge is spent on the hull")
	check_eq(world.stats.kills, 0, "a spent charge is not a player kill")


func test_a_sidestep_makes_the_charge_overshoot_and_leaves_the_husk_winded() -> void:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage("", true, 1)
	var husk := _charging(world)
	var direction := husk._dir
	world.player.global_position.x += 15.0
	var hp := world.player.hp
	for i in int((Charger.CHARGE_TIME + 0.1) * 60.0):
		husk.behave(1.0 / 60.0)
	check_eq(husk._dir, direction, "the charge never steers after the lane is locked")
	check_eq(world.player.hp, hp, "a lateral dodge clears the lane")
	check_eq(husk.state, Charger.State.WINDED, "it stands winded after the overshoot")
	check(not husk.dead and not husk.is_queued_for_deletion(), "it survives to be shot")
	husk.behave(Charger.WINDED_TIME + 0.01)
	check_eq(husk.state, Charger.State.STALK, "then it stalks again")


func test_interrupting_the_wind_up_cancels_the_charge() -> void:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage("", true, 1)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.player.velocity = Vector3.ZERO
	var husk := _husk(world)
	husk.behave(0.01)
	husk.interrupt()
	var hp := world.player.hp
	for i in 120:
		husk.tick(1.0 / 60.0)
	check(not husk.telegraphing() and husk.state != Charger.State.CHARGE, "an interrupted wind-up never becomes a charge")
	check_eq(world.player.hp, hp, "and costs the tank nothing")


func test_the_horned_shell_turns_the_coax_from_the_front_only() -> void:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage("", true, 1)
	var husk := _husk(world)
	var front := Hit.make(Hit.Kind.BULLET, Armament.GUNS[8].damage, husk.hit_center(), Vector3.BACK)
	front.caliber = 8
	var side := Hit.make(Hit.Kind.BULLET, Armament.GUNS[8].damage, husk.hit_center(), Vector3.RIGHT)
	side.caliber = 8
	check_near(husk.damage_multiplier(front), Husk.FRONT_ARMOR, 0.001, "a head-on coax round loses most of its bite")
	check_near(husk.damage_multiplier(side), 1.0, 0.001, "a flank round does full damage")


func test_a_killed_husk_bursts_softly_without_a_fireball() -> void:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage("", true, 1)
	var husk := _husk(world)
	var neighbor := _husk(world, 31.0)
	var hit := Hit.make(Hit.Kind.SHELL, 999.0, husk.hit_center(), Vector3.BACK)
	hit.source = world.player
	husk.take_hit(hit)
	check(husk.dead, "a shell kills it")
	check_eq(world.stats.kills, 1, "the kill scores")
	check_eq(neighbor.hp, neighbor.max_hp, "a soft body sends no blast through its neighbor")
