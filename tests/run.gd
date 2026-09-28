extends Node
## Runs every tests/*_test.gd. Exit code is the number of failed checks (0 = pass).
## Usage: godot --headless --fixed-fps 60 --path . -- --run=res://tests/run.gd [--only=name]


func run() -> int:
	var only: String = preload("res://scripts/main.gd").args().get("only", "")
	var total_failures: Array[String] = []
	var count := 0
	for file in DirAccess.get_files_at("res://tests"):
		if not file.ends_with("_test.gd") or (not only.is_empty() and not file.contains(only)):
			continue
		var script: GDScript = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			total_failures.append("%s: failed to compile" % file)
			continue
		var suite: TestCase = script.new()
		add_child(suite)
		for method in suite.get_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			count += 1
			suite.begin("%s.%s" % [file.get_basename(), name])
			await suite.call(name)
			suite.cleanup()
			await get_tree().process_frame
		total_failures.append_array(suite.failures)
		suite.queue_free()
	for failure in total_failures:
		printerr("FAIL ", failure)
	print("%d tests, %d failed checks" % [count, total_failures.size()])
	return total_failures.size()
