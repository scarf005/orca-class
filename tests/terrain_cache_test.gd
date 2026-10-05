extends TestCase
## Repeated worlds share immutable terrain geometry, never their scene nodes or flat-mode geometry.

class CountingTerrain extends Terrain:
	var advances := 0
	func _advance(job: ChunkBuild, deadline := 0) -> bool:
		advances += 1
		return super._advance(job, deadline)


func test_recreated_terrain_reuses_identical_meshes_without_regeneration() -> void:
	Course.flat = false
	var first := CountingTerrain.new()
	add_child(first)
	first.stream(0.0, true)
	var original: MeshInstance3D = first._chunks[0]
	var mesh := original.mesh
	var expected := first._build_chunk(0).mesh().surface_get_arrays(0)
	var second := CountingTerrain.new()
	add_child(second)
	second.stream(0.0, true)
	var reused: MeshInstance3D = second._chunks[0]
	check(reused != original, "each world owns a fresh terrain node")
	check(reused.mesh == mesh, "recreated terrain shares the immutable mesh")
	check_eq(second.advances, 0, "cache hits do not regenerate ground")
	original.hide()
	check(reused.visible, "node visibility does not leak between worlds")
	for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
		check_eq(reused.mesh.surface_get_arrays(0)[attribute], expected[attribute], "cached geometry matches fresh production generation")
	first.free()
	second.free()


func test_flat_ground_does_not_reuse_valley_geometry() -> void:
	Course.flat = false
	var valley := Terrain.new()
	add_child(valley)
	valley.stream(2000.0, true)
	var valley_mesh: Mesh = valley._chunks[50].mesh
	Course.flat = true
	var flat := Terrain.new()
	add_child(flat)
	flat.stream(2000.0, true)
	var flat_mesh: Mesh = flat._chunks[50].mesh
	var expected := flat._build_chunk(50).mesh().surface_get_arrays(0)
	check(flat_mesh != valley_mesh, "flat mode has its own mesh")
	check(flat_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] != valley_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "debug ground differs from the reservoir valley")
	for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
		check_eq(flat_mesh.surface_get_arrays(0)[attribute], expected[attribute], "flat cached geometry matches fresh production generation")
	valley.free()
	flat.free()


func test_eviction_bounds_shared_meshes_without_changing_live_geometry() -> void:
	Terrain._meshes.clear()
	Course.flat = false
	var terrain := Terrain.new()
	add_child(terrain)
	terrain._attach(0, terrain._build_chunk(0))
	var live: Mesh = terrain._chunks[0].mesh
	var expected := live.surface_get_arrays(0)
	for index in range(1, Terrain.CACHE_LIMIT + 1):
		terrain._attach(index, terrain._build_chunk(index))
	check_eq(Terrain._meshes.size(), Terrain.CACHE_LIMIT, "shared geometry has a fixed upper bound")
	check(not Terrain._meshes.has(Terrain._mesh_key(0)), "the oldest cached chunk is evicted")
	for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
		check_eq(live.surface_get_arrays(0)[attribute], expected[attribute], "eviction preserves geometry retained by a live node")
	terrain._chunks[0].free()
	terrain._chunks.erase(0)
	terrain.stream(0.0, true)
	for attribute in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
		check_eq(terrain._chunks[0].mesh.surface_get_arrays(0)[attribute], expected[attribute], "an evicted chunk regenerates identical ground")
	terrain.free()
	Terrain._meshes.clear()
