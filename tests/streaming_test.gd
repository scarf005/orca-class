extends TestCase
## Terrain must be identical with and without workers, including interrupted generation.


func test_sliced_chunks_match_complete_geometry() -> void:
	var terrain := Terrain.new()
	for index in [-1, 40, 60, 80]:
		var job := Terrain.ChunkBuild.new(index)
		check(not terrain._advance(job, Time.get_ticks_usec() - 1), "an expired budget does no work")
		check_eq(job.cursor, 0, "expired budget preserves the build cursor")
		var slices := 0
		while not terrain._advance(job, Time.get_ticks_usec() + 100):
			slices += 1
		check(slices > 1, "a chunk can span many small time budgets")
		var complete := terrain._build_chunk(index).mesh().surface_get_arrays(0)
		var sliced := job.builder.mesh().surface_get_arrays(0)
		for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
			check_eq(sliced[attribute], complete[attribute], "slicing preserves chunk %d attribute %d" % [index, attribute])
	terrain.free()


func test_serial_stream_cancels_obsolete_work_and_loading_finishes_it() -> void:
	var terrain := Terrain.new()
	terrain.threaded = false
	add_child(terrain)
	terrain.stream(0.0)
	check(not terrain._serial.is_empty(), "ordinary streaming leaves unfinished chunks queued")
	check(terrain._pending.is_empty(), "serial streaming never schedules a synchronous worker task")
	var obsolete := terrain._serial.keys()
	terrain.stream(3400.0)
	for index in obsolete:
		check(not terrain._serial.has(index), "a checkpoint jump drops old queued geometry")
	terrain.stream(3400.0, true)
	check(terrain._serial.is_empty(), "loading completes all remaining serial work")
	check(terrain._chunks.has(85), "checkpoint terrain is present")
	var count := terrain._chunks.size()
	terrain.stream(3400.0, true)
	check_eq(terrain._chunks.size(), count, "repeated loading does not duplicate chunks")
	terrain.queue_free()


func test_loading_joins_already_pending_workers() -> void:
	if not OS.has_feature("threads"):
		skip("worker threads unavailable")
		return
	var terrain := Terrain.new()
	add_child(terrain)
	terrain.stream(0.0)
	terrain.stream(0.0, true)
	check(terrain._pending.is_empty(), "loading waits for already scheduled tasks")
	check(terrain._built.is_empty(), "completed worker results are consumed once")
	check(terrain._chunks.has(0), "loading has attached the nearby ground")
	terrain.queue_free()


func test_prepared_normals_follow_winding_and_survive_mesh_reuse() -> void:
	var builder := LowPoly.new()
	builder.tri(Vector3.ZERO, Vector3.RIGHT * 2.0, Vector3.UP, Color.RED, Vector3.BACK)
	var first := builder.mesh()
	builder.tri(Vector3.ZERO, Vector3.RIGHT * 2.0, Vector3.UP, Color.BLUE, Vector3.FORWARD)
	builder.tri(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Color.WHITE)
	var arrays := builder.mesh().surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# ArrayMesh packs normals (including degenerate ones); check the prepared data before
	# that lossy engine conversion so the assertion tests generation rather than encoding.
	var normals: PackedVector3Array = builder._surfaces[0][2]
	for i in range(0, vertices.size(), 3):
		var expected := (vertices[i + 2] - vertices[i]).cross(vertices[i + 1] - vertices[i]).normalized()
		for j in 3:
			check(normals[i + j].is_equal_approx(expected), "cached flat normals follow the final clockwise face")
	check_eq(first.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), 3, "extending a builder does not change a mesh already in use")
