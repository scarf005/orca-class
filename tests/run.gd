extends Node
## Runs every tests/*_test.gd. Exit code is 1 when any check, compile error, or harness error fails.
## Usage: godot --headless --fixed-fps 60 --path . -- --run=res://tests/run.gd [--only=name]


func run() -> int:
	var only: String = preload("res://scripts/main.gd").args().get("only", "")
	var files: Array[String] = []
	for file in DirAccess.get_files_at("res://tests"):
		if file.ends_with("_test.gd") and (only.is_empty() or file.contains(only)):
			files.append(file)
	files.sort()
	var total_failures: Array[String] = []
	var total_skips: Array[String] = []
	var count := 0
	var passed := 0
	print("Test user data directory: ", OS.get_user_data_dir())
	print("Test sandbox verified: ", TestCase.is_isolated())
	if not TestCase.is_isolated():
		print("Test isolation: use `just test`; direct runs must provide a temporary XDG data directory.")
	if files.is_empty():
		var filter_message := " for filter '%s'" % only if not only.is_empty() else ""
		printerr("FAIL no test files matched%s" % filter_message)
		return 1
	for file in files:
		var script: GDScript = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			total_failures.append("%s: failed to compile" % file)
			continue
		var suite: TestCase = script.new()
		add_child(suite)
		var methods: Array[String] = []
		for method in suite.get_method_list():
			var name: String = method.name
			if name.begins_with("test_"):
				methods.append(name)
		methods.sort()
		for name in methods:
			count += 1
			var failure_start := suite.failures.size()
			var skip_start := suite.skips.size()
			suite.begin("%s.%s" % [file.get_basename(), name])
			await suite.call(name)
			suite.cleanup(true)
			await get_tree().process_frame
			var method_failures: Array = suite.failures.slice(failure_start)
			var method_skips: Array = suite.skips.slice(skip_start)
			total_failures.append_array(method_failures)
			total_skips.append_array(method_skips)
			if method_skips.is_empty() and method_failures.is_empty():
				passed += 1
		suite.queue_free()
	if count == 0 and total_failures.is_empty():
		var method_message := " for filter '%s'" % only if not only.is_empty() else ""
		total_failures.append("FAIL no test methods selected%s" % method_message)
	for failure in total_failures:
		printerr("FAIL ", failure)
	for skipped in total_skips:
		print("SKIP ", skipped)
	print("%d tests, %d passed, %d skipped, %d failed checks" % [count, passed, total_skips.size(), total_failures.size()])
	return 1 if not total_failures.is_empty() else 0
