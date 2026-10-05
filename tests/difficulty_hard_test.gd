extends TestCase


func test_flyer_evasion_goals_are_hard_only_and_do_not_move_the_airframe_directly() -> void:
	var world := stage()
	for mode: Game.Difficulty in [Game.Difficulty.NORMAL, Game.Difficulty.HARD]:
		Game.difficulty = mode
		for kind: String in ["helicopter", "tiltrotor", "uav", "gunship"]:
			var flyer: Enemy = load(Director.ENEMY_SCRIPTS[kind]).new()
			flyer.position = Course.ground_at(80.0, 10.0) + Vector3.UP * 15.0
			world.add_enemy(flyer)
			world.player.charge_lock = flyer
			var before := flyer.global_position
			flyer._evade(0.1)
			check_eq(flyer._jink_offset != Vector3.ZERO, mode == Game.Difficulty.HARD, kind + " evasion goal difficulty gate")
			check_eq(flyer.global_position, before, "the flight controller owns airframe movement")
			check_eq(world.player.charge_lock, flyer, "evasion does not erase the player's lock")
	Game.difficulty = Game.Difficulty.NORMAL


func test_near_shell_jink_preserves_sure_target() -> void:
	Game.difficulty = Game.Difficulty.HARD
	var world := stage()
	var flyer := Helicopter.new()
	flyer.position = Course.ground_at(80.0, 10.0) + Vector3.UP * 15.0
	world.add_enemy(flyer)
	var shot := world.spawn_projectile(Entity.Team.PLAYER, flyer.hit_center() + Vector3.RIGHT * 4.0, Vector3.FORWARD * 100.0, "shell", Palette.BUTTER)
	shot.hit = Hit.make(Hit.Kind.SHELL, 100.0, shot.position)
	shot.sure_target = flyer
	flyer._evade(0.1)
	check(flyer._jink_active, "near shell triggers evasion without a lock")
	check_eq(shot.sure_target, flyer, "fired charge remains sure")
	Game.difficulty = Game.Difficulty.NORMAL


func test_ground_combined_patterns_are_hard_only() -> void:
	var world := stage()
	for mode: Game.Difficulty in [Game.Difficulty.NORMAL, Game.Difficulty.HARD]:
		Game.difficulty = mode
		var hard := mode == Game.Difficulty.HARD
		var ugv := Ugv.new()
		ugv.position = Course.ground_at(60.0, 8.0)
		world.add_enemy(ugv)
		ugv._attack_timer = 0.0
		ugv.behave(0.01)
		check(ugv.telegraphing(), "UGV combined attack is warned")
		var before := world.projectiles.size()
		ugv._attack()
		check_eq(world.projectiles.size() - before, 1 if hard else 0, "hard gun UGV adds ATGM")
		check(ugv._burst > 0, "gun burst remains")
		var walker := Walker.new()
		walker.position = Course.ground_at(60.0, -8.0)
		world.add_enemy(walker)
		walker._attack_timer = 0.0
		walker.behave(0.01)
		check(walker.telegraphing(), "walker combo is warned")
		walker._attack(world.player)
		walker.behave(0.01)
		before = world.projectiles.size()
		walker.behave(0.09)
		check_eq(world.projectiles.size() - before, 2 if hard else 1, "hard walker gun plus missile")
		var quad := QuadMech.new()
		quad.weapon = "mortar"
		quad.position = Course.ground_at(65.0, 0.0)
		world.add_enemy(quad)
		quad._attack(world.player)
		check_eq(quad._burst > 0, hard, "hard mortar quad also spins flak")
	Game.difficulty = Game.Difficulty.NORMAL


func test_air_and_fungal_patterns_are_hard_only() -> void:
	var world := stage()
	for mode: Game.Difficulty in [Game.Difficulty.NORMAL, Game.Difficulty.HARD]:
		Game.difficulty = mode
		var hard := mode == Game.Difficulty.HARD
		var helicopter := Helicopter.new()
		world.add_enemy(helicopter)
		helicopter._strafing = true
		helicopter._next_attack()
		check_eq(helicopter._salvo, hard, "hard strafe chains a warned rocket salvo")
		var transport := Tiltrotor.new()
		transport.squad = "drones"
		world.add_enemy(transport)
		transport._wind = 0.01
		var count := world.enemies.size()
		transport._hover_tasks(0.02, world.player)
		check_eq(world.enemies.size() > count, hard, "hard sweep also drops a squad")
		var drone := FpvDrone.new()
		world.add_enemy(drone)
		drone._set_state(FpvDrone.State.TELEGRAPH)
		var before := world.projectiles.size()
		drone._start_dive(world.player)
		check_eq(world.projectiles.size() - before, 1 if hard else 0, "hard drone throws a rocket after red-light warning")
		var crawler := Crawler.new()
		world.add_enemy(crawler)
		crawler._start_swell()
		before = world.projectiles.size()
		crawler._burst()
		check_eq(world.projectiles.size() - before, 3 if hard else 0, "hard swelling crawler spits a fan")
		var spitter := Spitter.new()
		world.add_enemy(spitter)
		before = world.projectiles.size()
		spitter._volley(world.player)
		check_eq(world.projectiles.size() - before, 4 if hard else 3, "spitter spread retains hard extra round")
		var uav := Uav.new()
		uav.attack = "bomb"
		uav.position = Course.ground_at(70.0, 0.0) + Vector3.UP * 15.0
		world.add_enemy(uav)
		uav.global_position = world.player.global_position - Course.forward(0.0) * 60.0 + Vector3.UP * 15.0
		uav._dir = (world.player.global_position - uav.global_position).normalized()
		uav._dir.y = 0.0
		uav.behave(0.01)
		check_eq(uav._loiter_wind > 0.0, hard, "hard bomber warns a loitering-drone drop")
		count = world.enemies.size()
		uav.behave(0.9)
		check_eq(world.enemies.size() > count, hard, "hard bomber releases a drone without needing a strafe gun")
	Game.difficulty = Game.Difficulty.NORMAL
