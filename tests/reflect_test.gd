extends TestCase
## A dash turns hostile shots near the hull back on their shooters.


func _rig() -> World:
	var world := stage()
	world.set_process(false)
	world.director.set_process(false)
	world.player.set_process(false)
	world.camera.set_process(false)
	return world


func _shooter(world: World, ahead: float) -> Ugv:
	var ugv := Ugv.new()
	ugv.position = world.player.global_position + Vector3(0, 0, -ahead)
	ugv.immobile = true
	ugv.disarmed = true
	world.add_enemy(ugv)
	ugv.set_process(false)
	return ugv


## A rocket from `shooter`, `distance` m from the hull's center, flying at the tank.
func _rocket(world: World, shooter: Entity, distance: float) -> Projectile:
	var tank := world.player
	var from := tank.hit_center() + Vector3(0, 0, -distance)
	var rocket := world.spawn_projectile(Entity.Team.ENEMY, from, Vector3(0, 0, 40.0), "rocket")
	rocket.hit = Hit.make(Hit.Kind.SHELL, 30.0, from)
	rocket.hit.source = shooter
	rocket.hit.warhead = true
	rocket.interceptable = true
	rocket.life = 10.0
	return rocket


func test_a_rocket_inside_5_m_during_a_dash_flies_back_and_kills_its_shooter() -> void:
	var world := _rig()
	var tank := world.player
	var shooter := _shooter(world, 40.0)
	var rocket := _rocket(world, shooter, 4.0)
	tank.dash(Vector2.RIGHT)
	check(tank.is_dashing(), "dashing")
	var style := world.stats.style
	tank._reflect_shots()
	check_eq(rocket.team, Entity.Team.PLAYER, "the rocket changes sides")
	check_near(rocket.velocity.length(), 40.0 * Tank.REFLECT_SPEED, 0.01, "faster by 20 percent")
	var toward := (shooter.hit_center() - rocket.global_position).normalized()
	check(rocket.velocity.normalized().dot(toward) > 0.999, "aimed at the shooter's center")
	check(rocket.hit.damage >= Tank.REFLECT_DAMAGE and rocket.hit.stagger >= 1.0 and not rocket.hit.warhead and rocket.hit.source == tank, "a heavy staggering player hit")
	check(not rocket.interceptable, "the CIWS leaves it alone")
	check(world.stats.style > style, "REFLECT scores style")
	var kills: Array[Hit] = []
	world.killed.connect(func(_victim: Entity, hit: Hit) -> void: kills.append(hit))
	var hp := tank.hp
	for _i in 120:
		if shooter.dead:
			break
		rocket.step(1.0 / 60.0)
	check(shooter.dead, "it kills the UGV that fired it")
	check_eq(kills.size(), 1, "one kill")
	check(kills.size() > 0 and kills[0].weapon == "reflect", "credited to the reflect")
	check_eq(tank.hp, hp, "and nothing heals the tank")


func test_outside_a_dash_or_beyond_5_m_nothing_reflects() -> void:
	var world := _rig()
	var tank := world.player
	var shooter := _shooter(world, 40.0)
	var rocket := _rocket(world, shooter, 4.0)
	tank._reflect_shots()
	check_eq(rocket.team, Entity.Team.ENEMY, "no dash, no reflect")
	tank.dash(Vector2.RIGHT)
	var far := _rocket(world, shooter, 6.0)
	tank._reflect_shots()
	check_eq(far.team, Entity.Team.ENEMY, "6 m out is still too far")
	check_eq(rocket.team, Entity.Team.PLAYER, "while the near one is turned")


func test_a_reflected_shot_without_a_shooter_goes_straight_back_and_a_bomb_flies_straight() -> void:
	var world := _rig()
	var tank := world.player
	var bomb := _rocket(world, null, 3.0)
	bomb.gravity = 20.0
	tank.dash(Vector2.LEFT)
	tank._reflect_shots()
	check_eq(bomb.team, Entity.Team.PLAYER, "reflected")
	check(bomb.velocity.normalized().dot(Vector3.FORWARD) > 0.999, "straight back the way it came")
	check_eq(bomb.gravity, 0.0, "an arcing shot flies straight")
	check_eq(bomb.homing_target, null, "and no longer homes")


func test_reflect_kill_is_named_reflect_and_counted_by_the_probe() -> void:
	var world := _rig()
	var crawler := Crawler.new()
	crawler.position = Course.ground_at(world.rail.d + 60.0, 5.0)
	world.add_enemy(crawler)
	crawler.set_process(false)
	var hit := Hit.make(Hit.Kind.SHELL, 999.0, crawler.hit_center())
	hit.source = world.player
	hit.weapon = "reflect"
	var probe := preload("res://tools/autoplay.gd").new()
	world.killed.connect(probe._killed)
	crawler.take_hit(hit)
	check(world.stats.style_feed.any(func(e: Dictionary) -> bool: return e.name == "REFLECT"), "the kill is a REFLECT")
	check_eq(probe.kill_sources.reflect, 1, "the probe counts it as reflect")
	probe.free()
