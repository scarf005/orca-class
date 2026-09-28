extends TestCase
## Score, combo, rank and best records.


func test_combo_multiplier_and_decay() -> void:
	var stats := RunStats.new()
	for i in 5:
		stats.add_score(100, true)
	check_eq(stats.multiplier(), 1, "x1 below six kills")
	check_eq(stats.add_score(100, true), 200, "sixth kill at x2")
	for i in 60:
		stats.add_score(1, true)
	check_eq(stats.multiplier(), RunStats.MAX_MULTIPLIER, "multiplier caps")
	check_eq(stats.add_score(100, false), 100, "bonuses are not multiplied")
	stats.tick(RunStats.COMBO_WINDOW + 0.1)
	check_eq(stats.combo, 0, "combo drops after the window")
	check(stats.max_combo >= 66, "max combo remembered")


func test_rank_rewards_score_and_punishes_damage() -> void:
	var good := RunStats.new()
	good.score = 180000
	good.kills = 200
	good.spawned = 210
	good.shots = 100
	good.shot_hits = 70
	check_eq(good.rank(), "S", "high score, clean run")
	var hurt := RunStats.new()
	hurt.score = 20000
	hurt.kills = 50
	hurt.spawned = 210
	hurt.damage_taken = 900.0
	check_eq(hurt.rank(), "C", "low score, heavy damage")


func test_best_only_improves() -> void:
	var key := "test_best_%d" % Time.get_ticks_usec()
	check(Game.submit_best(key, 100), "first result is a best")
	check(not Game.submit_best(key, 50), "lower is not")
	check(Game.submit_best(key, 150), "higher is")
	Game.bests.erase(key)
