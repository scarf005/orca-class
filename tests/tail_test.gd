extends TestCase
## Tail: snatch, grab and throw, swat, anchor, damage floor.


func test_snatches_pickup_in_reach() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	tank.hp = 50.0 # Hurt first, or the spawn swaps the unneeded repair for something else.
	var pickup := world.spawn_pickup("repair", tank.tail.mount.global_position + tank.global_basis.x * (Tail.REACH - 1.0))
	tank.auto_tail()
	check_eq(tank.tail.state, Tail.State.REACH, "claw reaches for the pickup")
	var ok := await wait_until(gone(pickup), 240)
	check(ok, "pickup arrives and is used")
	check(tank.hp > 50.0, "repair applied")


func test_tail_stabs_small_enemies_instead_of_grabbing() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var crawler := Crawler.new()
	crawler.position = tank.tail.mount.global_position + tank.global_basis.x * 5.0
	world.add_enemy(crawler)
	crawler.stagger = 10.0
	tank.auto_tail()
	check_eq(tank.tail.state, Tail.State.STAB, "the claw stabs it")
	var crawler_ref: WeakRef = weakref(crawler)
	var dead := await wait_until(func() -> bool:
		var target := crawler_ref.get_ref() as Crawler
		return target == null or target.dead
	, 120)
	check(dead, "a stab kills a small enemy")
	check(not is_instance_valid(tank.tail.held), "nothing is carried")


func test_swat_hits_nearby_drone() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var drone := FpvDrone.new()
	drone.position = tank.global_position + Vector3(4, 3, 0)
	world.add_enemy(drone)
	drone.state = FpvDrone.State.DIVE
	tank.auto_tail()
	check_eq(tank.tail.state, Tail.State.SWAT, "a diving drone next to the hull gets swatted first")
	check(drone.dead, "swat kills the drone")


func test_tail_idles_when_nothing_is_near() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	tank.auto_tail()
	check_eq(tank.tail.state, Tail.State.IDLE, "no target, no action")


func test_drift_lashes_nearby_enemies() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var crawler := Crawler.new()
	crawler.position = tank.global_position + tank.global_basis.x * 5.0
	world.add_enemy(crawler)
	crawler.stagger = 10.0
	tank._anchor(Vector2(1, 0))
	check(crawler.dead, "the drift's tail spin kills a crawler beside the tank")


func test_anchor_drift_dodges() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var u := tank.course_u
	tank._anchor(Vector2(1, 0))
	check(tank.invuln > 0.0, "drift gives a dodge window")
	await frames(12)
	check(tank.course_u > u + 3.0, "drift throws the hull sideways")
	check(tank.anchor_cooldown > 0.0, "anchor has a cooldown")


func test_anchor_hard_stop_halts_rail() -> void:
	var world := stage()
	await frames(10)
	world.player._anchor(Vector2.ZERO)
	await frames(6)
	check(world.rail.speed < 3.0, "rail almost stops")
	await frames(90)
	check(world.rail.speed > 8.0, "rail resumes")


func test_tail_can_be_torn_off_and_regrown() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	tank.tail.damage(60.0)
	check(tank.tail.is_hurt(), "heavy damage marks it hurt")
	tank.tail.start_cooldown()
	check(tank.tail.cooldown > Tail.COOLDOWN, "hurt tail recovers slower")
	check(tank.tail.damage(1000.0), "enough damage tears it off")
	check(not tank.tail.is_ready(), "a lost tail does nothing")
	world.spawn_pickup("repair", tank.tail.mount.global_position + tank.global_basis.x * 5.0)
	tank.auto_tail()
	check_eq(tank.tail.state, Tail.State.IDLE, "no snatching without a tail")
	tank.collect(world.spawn_pickup("tail", tank.global_position + Vector3(0, 30, 0)))
	check(not tank.tail.destroyed and tank.tail.hp == Tail.MAX_HP, "the regrowth pickup brings it back")


func _reaching_for_a_pickup(world: World, tank: Tank) -> Pickup:
	tank.hp = 50.0
	var pickup := world.spawn_pickup("repair", tank.tail.mount.global_position + tank.global_basis.x * (Tail.REACH - 1.0))
	tank.auto_tail()
	return pickup


func test_a_tail_torn_off_mid_reach_lets_the_pickup_go() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var pickup := _reaching_for_a_pickup(world, tank)
	check_eq(tank.tail.state, Tail.State.REACH, "the claw is after the pickup")
	check(tank.tail.damage(Tail.MAX_HP), "a hit tears the tail off")
	check(not pickup._carried, "the pickup is no longer claimed by the claw")
	check(await wait_until(gone(pickup), 240), "the tank collects it by driving on")
	check(tank.hp > 50.0, "repair applied")


func test_a_tail_torn_off_while_carrying_drops_the_pickup() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var pickup := _reaching_for_a_pickup(world, tank)
	await wait_until(func() -> bool: return tank.tail.state == Tail.State.RETURN, 120)
	check(is_instance_valid(tank.tail.held), "the claw carries it back")
	tank.tail.damage(Tail.MAX_HP)
	check(not is_instance_valid(tank.tail.held), "the torn tail holds nothing")
	check(is_instance_valid(pickup) and not pickup._carried, "the pickup is free again")


func test_losing_a_life_mid_reach_keeps_the_pickup() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var pickup := _reaching_for_a_pickup(world, tank)
	tank.die(null)
	await frames(2)
	check(is_instance_valid(pickup), "the pickup is not destroyed with the hull")
	check(not pickup._carried, "and it is free")


func test_a_tail_torn_off_with_nothing_in_the_claw_changes_nothing_else() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var pickup := world.spawn_pickup("coax", tank.global_position + Vector3(60, 0, 0))
	check(tank.tail.damage(Tail.MAX_HP), "the tail is torn off")
	check(not pickup._carried, "an unrelated pickup is untouched")
	check(not tank.tail.damage(1.0), "a tail already gone cannot be torn off again")
