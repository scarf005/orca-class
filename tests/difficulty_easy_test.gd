extends TestCase


func test_easy_stats_and_normal_baselines() -> void:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage()
	var baseline := {}
	for kind: String in Director.ENEMY_SCRIPTS:
		var enemy: Enemy = load(Director.ENEMY_SCRIPTS[kind]).new()
		enemy.position = Course.ground_at(100.0, 0.0)
		world.add_enemy(enemy)
		baseline[kind] = [enemy.max_hp, enemy.armor]
	check_eq(baseline.ugv, [60.0, 12.0], "normal UGV unchanged")
	check_eq(baseline.walker, [60.0, 10.0], "normal walker unchanged")
	check_eq(baseline.helicopter, [40.0, 6.0], "normal helicopter unchanged")
	Game.difficulty = Game.Difficulty.EASY
	for kind: String in Director.ENEMY_SCRIPTS:
		var enemy: Enemy = load(Director.ENEMY_SCRIPTS[kind]).new()
		enemy.position = Course.ground_at(100.0, 0.0)
		world.add_enemy(enemy)
		check_near(enemy.max_hp, baseline[kind][0] * (0.6 if enemy.boss else 0.7), 0.01, kind + " easy HP")
		check_eq(enemy.hp, enemy.max_hp, kind + " starts with scaled HP")
		check_near(enemy.armor, baseline[kind][1] * 0.25, 0.01, kind + " thin armor")
		if enemy is Colossus:
			check_near(enemy._total_hp(), enemy.hp, 0.01, "colossus parts retain scaled HP after damage")
	var ugv := Ugv.new()
	world.add_enemy(ugv)
	var hit := Hit.make(Hit.Kind.BULLET, 1.0, ugv.hit_center(), ugv.model.global_basis.z)
	check_near(ugv.frontal_armor(hit, 0.2), 0.8, 0.001, "easy front plate weakened")
	Game.difficulty = Game.Difficulty.NORMAL


func test_easy_never_sends_pursuit() -> void:
	Game.difficulty = Game.Difficulty.EASY
	var world := stage()
	world.rail.speed = 0.0
	world.director.slow_meter = 1.0
	world.director._update_pursuit(10.0)
	check_eq(world.enemies.size(), 0, "no slow-tank pursuit")
	check_eq(world.director.slow_meter, 0.0, "no pursuit pressure")
	check_eq(world.director.send_pursuers(2, FpvDrone.Pattern.ARC).size(), 0, "explicit pursuit also blocked")
	Game.difficulty = Game.Difficulty.NORMAL
	world.director._update_pursuit(10.0)
	check_eq(world.enemies.size(), 2, "normal pursuit unchanged")


func test_easy_doubles_attack_warnings() -> void:
	var world := stage()
	for mode: Game.Difficulty in [Game.Difficulty.NORMAL, Game.Difficulty.EASY]:
		Game.difficulty = mode
		var factor := 2.0 if mode == Game.Difficulty.EASY else 1.0
		var ugv := Ugv.new()
		ugv.weapon = "atgm"
		ugv.position = Course.ground_at(65.0, 10.0)
		world.add_enemy(ugv)
		ugv._attack_timer = 0.0
		ugv.behave(0.01)
		check_near(ugv._telegraph, 1.4 * factor, 0.001, "ATGM warning")
		var walker := Walker.new()
		walker.weapon = "missile"
		walker.position = Course.ground_at(65.0, -10.0)
		world.add_enemy(walker)
		walker._attack_timer = 0.0
		walker.behave(0.01)
		check_near(walker._telegraph, Walker.MISSILE_WIND * factor, 0.001, "missile ripple warning")
		var spitter := Spitter.new()
		spitter.position = Course.ground_at(65.0, 15.0)
		world.add_enemy(spitter)
		spitter._timer = 0.0
		spitter.behave(0.01)
		check_near(spitter._telegraph, 0.8 * factor, 0.001, "spitter warning")
		var drone := FpvDrone.new()
		drone.position = Course.ground_at(40.0, 0.0) + Vector3.UP * 8.0
		world.add_enemy(drone)
		drone._set_state(FpvDrone.State.TELEGRAPH)
		drone.behave(FpvDrone.TELEGRAPH_TIME * factor - 0.01)
		check_eq(drone.state, FpvDrone.State.TELEGRAPH, "FPV waits through warning")
		drone.behave(0.02)
		check_eq(drone.state, FpvDrone.State.DIVE, "FPV dives after scaled warning")
	Game.difficulty = Game.Difficulty.NORMAL


func test_easy_records_are_separate() -> void:
	Game.difficulty = Game.Difficulty.EASY
	check_eq(Game.best_key("score"), "score_easy", "easy cannot replace normal records")
	Game.difficulty = Game.Difficulty.NORMAL
	check_eq(Game.best_key("score"), "score_normal", "normal record key unchanged")
	Game.difficulty = Game.Difficulty.HARD
	check_eq(Game.best_key("score"), "score_hard", "hard record key unchanged")
	Game.difficulty = Game.Difficulty.NORMAL
