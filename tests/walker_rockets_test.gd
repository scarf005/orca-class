extends TestCase
## Walker rockets lead the tank: a tank that holds course is hit, one that strafes hard escapes.

const LAUNCHES := 100 ## Walkers per volley; each fires a ripple of four.


## Rockets fired by walkers where they pace the tank (KEEP_AHEAD ahead, random lane) with the rail
## running and no CIWS. Returns the share that land on the hull (a direct hit or a blast reaching it).
func _volley(world: World, strafe: float, lead := true) -> float:
	var tank := world.player
	tank.invulnerable = true
	await frames(2)
	var limit := Tank.lateral_limit(world.rail.d + Walker.KEEP_AHEAD)
	var landed := [0]
	var fired := [0]
	for i in LAUNCHES:
		var walker: Walker = load("res://scripts/enemies/walker.gd").new()
		walker.weapon = "missile"
		walker.position = Course.ground_at(world.rail.d + tank.course_offset + Walker.KEEP_AHEAD, randf_range(-0.8, 0.8) * limit)
		world.add_enemy(walker)
		walker._attack_timer = INF
		var before := world.projectiles.duplicate()
		walker.aim_barrel(walker._pod, tank.hit_center() + Walker.POD_LOFT, 100.0, 1.0) # The pod has finished training onto the tank.
		walker._attack(tank)
		check_eq(walker._burst, Walker.RIPPLE, "the salvo is a ripple of four")
		for _j in Walker.RIPPLE:
			walker._fire_missile(tank)
		for rocket in world.projectiles:
			if rocket in before:
				continue
			fired[0] += 1
			rocket.homing_lead = lead
			rocket.impacted.connect(func(p: Projectile, point: Vector3, target: Entity) -> void:
				if target == tank or point.distance_to(tank.hit_center()) - tank.radius <= p.blast_radius:
					landed[0] += 1)
	tank.input_enabled = strafe != 0.0
	if strafe != 0.0:
		Input.action_press(&"move_right" if strafe > 0.0 else &"move_left")
	await wait_until(func() -> bool: return world.projectiles.is_empty(), 400)
	Input.action_release(&"move_right")
	Input.action_release(&"move_left")
	return float(landed[0]) / maxf(fired[0], 1.0)


func test_rockets_hit_a_tank_holding_course() -> void:
	seed(3)
	var share := await _volley(stage("", false), 0.0)
	check(share >= 0.7, "at least 70%% of rockets hit a tank holding course (%.2f)" % share)


func test_rockets_without_lead_overfly_a_tank_holding_course() -> void:
	seed(3)
	var share := await _volley(stage("", false), 0.0, false)
	check(share < 0.35, "chasing the tank's current position mostly misses (%.2f)" % share)


func test_rockets_miss_a_tank_strafing_hard() -> void:
	seed(3)
	var share := await _volley(stage("", false), 1.0)
	check(share <= 0.3, "at most 30%% of rockets hit a tank strafing hard (%.2f)" % share)
	seed(4)
	cleanup()
	share = await _volley(stage("", false), -1.0)
	check(share <= 0.3, "and the other way (%.2f)" % share)
