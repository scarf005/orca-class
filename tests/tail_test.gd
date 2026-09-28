extends TestCase
## Tail: snatch, grab and throw, swat, anchor, damage floor.


func test_snatches_pickup_in_reach() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var pickup := world.spawn_pickup("repair", tank.tail.mount.global_position + tank.global_basis.x * 6.0)
	tank.hp = 50.0
	tank.tail_action()
	check_eq(tank.tail.state, Tail.State.REACH, "claw reaches for the pickup")
	var ok := await wait_until(gone(pickup), 240)
	check(ok, "pickup arrives and is used")
	check(tank.hp > 50.0, "repair applied")


func test_grab_and_throw_enemy() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var crawler := Crawler.new()
	crawler.position = tank.tail.mount.global_position + tank.global_basis.x * 5.0
	world.add_enemy(crawler)
	crawler.stagger = 10.0
	var crawler_ref: WeakRef = weakref(crawler)
	tank.tail_action()
	var held := await wait_until(func() -> bool: return is_instance_valid(tank.tail.held), 240)
	check(held, "claw holds the crawler")
	check(crawler_ref.get_ref() == null or not world.enemies.has(crawler_ref.get_ref()), "grabbed enemy leaves the fight")
	await wait_until(func() -> bool: return tank.tail.is_ready(), 120)
	tank.aim_point = tank.global_position + (-tank.global_basis.z) * 40.0
	var before := world.projectiles.size()
	tank.tail_action()
	check(not is_instance_valid(tank.tail.held), "throw releases it")
	check(world.projectiles.size() > before, "thrown wreck becomes a projectile")


func test_swat_hits_nearby_drone() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var drone := FpvDrone.new()
	drone.position = tank.global_position + Vector3(4, 3, 0)
	drone.grabbable = false
	world.add_enemy(drone)
	tank.tail_action()
	check_eq(tank.tail.state, Tail.State.SWAT, "nothing grabbable in reach: swat")
	check(drone.dead, "swat kills the drone")


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


func test_hurt_tail_is_slower_but_never_disabled() -> void:
	var tail := Tail.new()
	tail.damage(1000.0)
	check(tail.hp > 0.0, "tail never fully disabled")
	check(tail.is_hurt(), "heavy damage marks it hurt")
	tail.start_cooldown()
	check(tail.cooldown > Tail.COOLDOWN, "hurt tail recovers slower")
	tail.repair(200.0)
	check_eq(tail.hp, Tail.MAX_HP, "repair caps at max")
	tail.free()
