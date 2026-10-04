extends TestCase
## Regression coverage for the test harness itself: a failed assertion must not poison the next method.


func test_sandbox_marker_rejects_mismatch_without_disk_access() -> void:
	var marker := "/tmp/orca-test-marker"
	check(not TestCase._sandbox_isolated(marker, "/tmp/another-root", marker + "/godot/app_userdata/orca class"), "an XDG mismatch is not isolated")
	check(TestCase._sandbox_isolated(marker, marker, marker + "/godot/app_userdata/orca class"), "a matching descendant data path is isolated")


func test_cleanup_restores_mutable_environment() -> void:
	var original_silent := Game.silent
	var original_settings: Dictionary = Game.settings.duplicate(true)
	var original_bests: Dictionary = Game.bests.duplicate(true)
	var original_difficulty := Game.difficulty
	var original_checkpoint := Game.checkpoint
	var original_flat := Course.flat
	var original_speed := GameTuning.duel_speed
	var original_stage := Armament.STAGE_1
	var original_paused := get_tree().paused
	var original_time_scale := Engine.time_scale
	var original_actions := InputMap.get_actions()

	Game.silent = not original_silent
	Game.settings.locale = "en" if original_settings.locale == "ko" else "ko"
	Game.bests["harness_leak"] = 99
	Game.difficulty = Game.Difficulty.HARD if original_difficulty != Game.Difficulty.HARD else Game.Difficulty.EASY
	Game.checkpoint = "harness_leak"
	Course.flat = not original_flat
	GameTuning.duel_speed = 0.25
	Armament.STAGE_1 = 0.23
	Engine.time_scale = 0.25
	get_tree().paused = true
	InputMap.add_action(&"harness_leak")
	Input.action_press(&"harness_leak")

	cleanup(true)

	check_eq(Game.silent, original_silent, "silent state is restored")
	check_eq(Game.settings, original_settings, "settings are restored")
	check_eq(Game.bests, original_bests, "personal bests are restored in memory")
	check_eq(Game.difficulty, original_difficulty, "difficulty is restored")
	check_eq(Game.checkpoint, original_checkpoint, "checkpoint is restored")
	check_eq(Course.flat, original_flat, "course mode is restored")
	check_near(GameTuning.duel_speed, original_speed, 0.00001, "duel speed is restored")
	check_near(Armament.STAGE_1, original_stage, 0.00001, "tuning statics are restored")
	check_eq(get_tree().paused, original_paused, "pause state is restored")
	check_near(Engine.time_scale, original_time_scale, 0.00001, "time scale is restored")
	check(not InputMap.has_action(&"harness_leak"), "an added input action does not leak")
	check_eq(InputMap.get_actions().size(), original_actions.size(), "the input action inventory is restored")


func test_multiple_stages_do_not_leave_stale_worlds_running() -> void:
	var first := stage()
	var second := stage()
	check(first.is_queued_for_deletion(), "starting a new scenario queues the previous world")
	check(World.current == second, "the newest scenario owns World.current")
	cleanup(true)
	await frames(1)
	check(not is_instance_valid(first) and not is_instance_valid(second), "boundary cleanup frees every scenario")


func test_internal_cleanup_keeps_method_state_until_boundary() -> void:
	var original_difficulty := Game.difficulty
	Game.difficulty = Game.Difficulty.HARD
	cleanup()
	check_eq(Game.difficulty, Game.Difficulty.HARD, "internal cleanup does not erase intentional within-test state")
	Game.difficulty = original_difficulty
