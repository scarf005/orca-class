extends TestCase
## Score, combo, rank and best records.


func test_style_ranks_multiply_score_and_decay() -> void:
	var stats := RunStats.new()
	check_eq(stats.multiplier(), 1, "rank D is x1")
	check_eq(stats.add_score(100, true), 100, "base points at D")
	stats.style = RunStats.STYLE_RANKS[4]
	check_eq(stats.STYLE_LETTERS[stats.style_rank()], "S", "enough style reaches S")
	check_eq(stats.add_score(100, true), 100 * RunStats.STYLE_MULTIPLIERS[4], "S multiplies score")
	stats.tick(5.0)
	check(stats.style < RunStats.STYLE_RANKS[4], "style drains over time")
	stats.lose_style(9999.0)
	check_eq(stats.style, 0.0, "never below zero")


func test_repeating_a_trick_pays_less() -> void:
	var stats := RunStats.new()
	var first := stats.add_style("CRUSH", 80.0)
	var second := stats.add_style("CRUSH", 80.0)
	var varied := stats.add_style("BURNED", 80.0)
	check_near(second, first * 0.5, 0.01, "second in a row is halved")
	check_near(varied, 80.0, 0.01, "a different trick pays in full")
	check_eq(stats.style_feed[0].name, "BURNED", "newest trick leads the feed")


func test_other_tricks_do_not_refresh_a_repeat() -> void:
	var stats := RunStats.new()
	stats.add_style("MULTIKILL", 80.0)
	for i in 8:
		stats.add_style("DEMOLITION", 10.0)
	check_near(stats.add_style("MULTIKILL", 80.0), 40.0, 0.01, "still halved after many other tricks")


func test_spammed_trick_bottoms_out_and_recovers_with_rest() -> void:
	var stats := RunStats.new()
	for i in 20:
		stats.add_style("COAX", 80.0)
	check_near(stats.add_style("COAX", 80.0), 80.0 * pow(0.5, RunStats.FATIGUE_MAX), 0.01, "spam still pays the floor")
	stats.tick(RunStats.FATIGUE_MAX / RunStats.FATIGUE_RECOVERY * 0.5)
	var partial := stats.add_style("COAX", 80.0)
	check(partial > 10.0 and partial < 80.0, "a short rest brings part of it back")
	stats.tick(RunStats.FATIGUE_MAX / RunStats.FATIGUE_RECOVERY + 0.1)
	check_near(stats.add_style("COAX", 80.0), 80.0, 0.01, "a full rest pays in full")


func test_rank_rewards_score_and_punishes_damage() -> void:
	var good := RunStats.new()
	good.score = 600000
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
