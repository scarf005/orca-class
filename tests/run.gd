extends Node
## Runs every tests/*_test.gd. Exit code is 1 when any check, compile error, or harness error fails.
## Usage: godot --headless --fixed-fps 60 --path . -- --run=res://tests/run.gd [--only=name]


class TestLogger extends Logger:
	var _errors: Array[Dictionary] = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == 1: # Logger.ERROR_TYPE_WARNING
			return
		_mutex.lock()
		_errors.append({"function": function, "file": file, "line": line, "code": code, "rationale": rationale, "error_type": error_type})
		_mutex.unlock()

	func take_errors() -> Array[Dictionary]:
		_mutex.lock()
		var result: Array[Dictionary] = _errors
		_errors = []
		_mutex.unlock()
		return result


func _runtime_failures(errors: Array[Dictionary], label: String) -> Array[String]:
	var failures: Array[String] = []
	for error: Dictionary in errors:
		failures.append("%s: runtime error in %s:%d (%s) %s" % [label, error.file, error.line, error.code, error.rationale])
	return failures


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
	var isolated := TestCase.is_isolated()
	print("Test sandbox verified: ", isolated)
	var marker := OS.get_environment("ORCA_TEST_DATA_HOME")
	if not isolated and not marker.is_empty():
		printerr("FAIL marked test sandbox is not active; refusing to load test suites")
		return 1
	if not isolated:
		print("Test isolation: use `just test`; direct runs must provide a temporary XDG data directory.")
	if files.is_empty():
		var filter_message := " for filter '%s'" % only if not only.is_empty() else ""
		printerr("FAIL no test files matched%s" % filter_message)
		return 1
	var logger := TestLogger.new()
	OS.add_logger(logger)
	for file in files:
		var script: GDScript = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			total_failures.append("%s: failed to compile" % file)
			total_failures.append_array(_runtime_failures(logger.take_errors(), "%s setup" % file))
			continue
		var suite: TestCase = script.new()
		add_child(suite)
		var setup_errors := logger.take_errors()
		if not setup_errors.is_empty():
			total_failures.append_array(_runtime_failures(setup_errors, "%s setup" % file))
			suite.queue_free()
			await get_tree().process_frame
			total_failures.append_array(_runtime_failures(logger.take_errors(), "%s teardown" % file))
			continue
		var suite_passed := 0
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
			var method_label := "%s.%s" % [file.get_basename(), name]
			suite.begin(method_label)
			await suite.call(name)
			suite.cleanup(true)
			await get_tree().process_frame
			var method_failures: Array = suite.failures.slice(failure_start)
			var method_skips: Array = suite.skips.slice(skip_start)
			method_failures.append_array(_runtime_failures(logger.take_errors(), method_label))
			total_failures.append_array(method_failures)
			total_skips.append_array(method_skips)
			if method_skips.is_empty() and method_failures.is_empty():
				passed += 1
				suite_passed += 1
		suite.queue_free()
		await get_tree().process_frame
		var teardown_errors := logger.take_errors()
		total_failures.append_array(_runtime_failures(teardown_errors, "%s teardown" % file))
		if not teardown_errors.is_empty():
			passed -= suite_passed
	await get_tree().process_frame
	var final_errors := logger.take_errors()
	OS.remove_logger(logger)
	# A callback racing removal can append before remove_logger returns; drain after removal
	# as well, while the logger journal remains Mutex-protected.
	final_errors.append_array(logger.take_errors())
	total_failures.append_array(_runtime_failures(final_errors, "runner finalization"))
	if not final_errors.is_empty():
		passed = 0
	if count == 0 and total_failures.is_empty():
		var method_message := " for filter '%s'" % only if not only.is_empty() else ""
		total_failures.append("FAIL no test methods selected%s" % method_message)
	for failure in total_failures:
		printerr("FAIL ", failure)
	for skipped in total_skips:
		print("SKIP ", skipped)
	print("%d tests, %d passed, %d skipped, %d failed checks" % [count, passed, total_skips.size(), total_failures.size()])
	return 1 if not total_failures.is_empty() else 0
