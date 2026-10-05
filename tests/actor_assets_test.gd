extends TestCase
## Migration oracles captured from production builders at 32ac4a7 (before their removal).

const Inventory = preload("res://tools/actor_inventory.gd")
const FIXTURE := "res://tests/fixtures/actor_geometry.json"
# An octahedral normal has two UNORM16 coordinates. Each decode's unnormalized
# error is <= 2*sqrt(6)/65535; normalization amplifies it by at most sqrt(3).
# Allow two encodings (import then ArrayMesh), plus eight float32 rounding steps.
const NORMAL_ERROR := 4.0 * sqrt(18.0) / 65535.0 + 8.0 / 8388608.0


func _fixture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


func _indices(arrays: Array) -> PackedInt32Array:
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty():
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			indices.append(i)
	return indices


func _fingerprint(mesh: Mesh) -> Dictionary:
	var triangles: Array[String] = []
	var materials := [LowPoly.lit_material, LowPoly.glow_material, LowPoly.flesh_material, LowPoly.flesh_glow_material, LowPoly.vivid_lit_material, LowPoly.vivid_glow_material]
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var indices := _indices(a)
		var role := materials.find(mesh.surface_get_material(s))
		for i in range(0, indices.size(), 3):
			var corners: Array[String] = []
			for j in 3:
				var index := indices[i + j]
				var v: Vector3 = a[Mesh.ARRAY_VERTEX][index]
				var c: Color = a[Mesh.ARRAY_COLOR][index]
				var values := PackedFloat32Array([v.x, v.y, v.z, c.r, c.g, c.b, c.a])
				for k in values.size():
					if values[k] == 0.0:
						values[k] = 0.0 # Canonicalize signed zero, not small coordinates.
				corners.append(values.to_byte_array().hex_encode())
			var rotations := [corners[0] + corners[1] + corners[2], corners[1] + corners[2] + corners[0], corners[2] + corners[0] + corners[1]]
			rotations.sort()
			triangles.append(str(role) + rotations[0])
	triangles.sort()
	return {"triangles": float(triangles.size()), "sha256": "\n".join(triangles).sha256_text()}


func test_imported_parts_preserve_triangle_winding_positions_colors_and_shader_roles() -> void:
	var fixture := _fixture()
	check_eq(ActorMeshes.ACTORS.size(), fixture.assets.size(), "every actor has a baseline")
	for actor: String in fixture.assets:
		for part: String in fixture.assets[actor]:
			var mesh := ActorMeshes.mesh(actor, part)
			check(mesh != null, actor + "/" + part + " loads")
			if mesh:
				check_eq(_fingerprint(mesh), fixture.assets[actor][part], actor + "/" + part + " preserves every oriented colored triangle")


func _normal_error(mesh: Mesh) -> float:
	var worst := 0.0
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var indices := _indices(a)
		for i in range(0, indices.size(), 3):
			var p: Vector3 = a[Mesh.ARRAY_VERTEX][indices[i]]
			var q: Vector3 = a[Mesh.ARRAY_VERTEX][indices[i + 1]]
			var r: Vector3 = a[Mesh.ARRAY_VERTEX][indices[i + 2]]
			var normal := (r - p).cross(q - p).normalized()
			for j in 3:
				worst = maxf(worst, normal.distance_to(a[Mesh.ARRAY_NORMAL][indices[i + j]]))
	return worst


func test_imported_normals_preserve_flat_faces_within_import_encoding_precision() -> void:
	for actor: String in _fixture().assets:
		for part: String in _fixture().assets[actor]:
			var worst := _normal_error(ActorMeshes.mesh(actor, part))
			check(worst <= NORMAL_ERROR, "%s/%s flat normals: %.8f <= %.8f" % [actor, part, worst, NORMAL_ERROR])


func test_all_production_variants_share_imported_static_parts() -> void:
	var world := stage()
	for actor: String in Inventory.VARIANTS:
		for variant: String in Inventory.VARIANTS[actor]:
			var names := Inventory.names(actor, variant)
			for _copy in 2:
				var entity := Inventory.create(actor, variant)
				world.add_child(entity)
				var nodes := Inventory.meshes(entity)
				check_eq(nodes.size(), names.size(), actor + "/" + variant + " mesh inventory")
				for i in mini(nodes.size(), names.size()):
					if not String(names[i]).begins_with("random_"):
						check(nodes[i].mesh == ActorMeshes.mesh(actor, names[i]), actor + "/" + names[i] + " uses the shared imported resource")
				entity.free()
	var boss := Colossus.new()
	world.add_child(boss)
	for id in ["spike", "geyser", "strip", "puff"]:
		check(boss._mesh(id) == ActorMeshes.mesh("colossus", id), "attack part " + id + " is imported too")


func test_random_bodies_preserve_seeded_geometry_flat_normals_and_variation() -> void:
	var world := stage()
	var fixture := _fixture()
	for actor in ["crawler", "gunship"]:
		var first := {}
		for seed_value in [int(fixture.seed), 54321]:
			seed(seed_value)
			var entity := Inventory.create(actor, "")
			world.add_child(entity)
			var nodes := Inventory.meshes(entity)
			var names := Inventory.names(actor, "")
			for i in names.size():
				if not String(names[i]).begins_with("random_"):
					continue
				var key: String = actor + "/" + names[i]
				var actual := _fingerprint(nodes[i].mesh)
				check(_normal_error(nodes[i].mesh) <= NORMAL_ERROR, key + " keeps flat normals after displacement")
				if seed_value == int(fixture.seed):
					check_eq(actual, fixture.samples[key], key + " retains the production random geometry")
					first[key] = actual
				else:
					check(actual != first[key], key + " still varies between spawns")
			entity.free()


func test_tank_tail_and_every_coax_tier_use_shared_imported_parts() -> void:
	var world := stage()
	var tank := world.player
	for part in ["hull", "turret", "barrel", "rws", "fcs"]:
		var pivot: Node3D = tank.model.get(part)
		check((pivot.get_child(0) as MeshInstance3D).mesh == ActorMeshes.mesh("tank", part), "tank " + part + " uses its shared imported mesh")
	check(tank.model.track_meshes[0].mesh == tank.model.track_meshes[1].mesh, "tracks share a mesh")
	for i in Tail.LENGTHS.size():
		check(tank.tail._segments[i].mesh == ActorMeshes.mesh("tank", "tail_segment_%d" % i), "tail segments are authored, not rebuilt by the solver")
		check(tank.tail._knuckles[i].mesh == ActorMeshes.mesh("tank", "tail_knuckle_%d" % i), "knuckles share imported meshes")
	for tier in Armament.COAX_TIERS.size():
		tank.set_coax_tier(tier)
		for i in tank.model.coax_muzzles.size():
			var node := tank.model.coax_muzzles[i].get_parent().get_child(0) as MeshInstance3D
			check(node.mesh == ActorMeshes.mesh("tank", "coax_%d" % Armament.COAX_TIERS[tier][i]), "tier %d uses its imported caliber" % tier)


func test_unknown_actor_part_and_shader_role_have_no_fallback() -> void:
	check(not ActorMeshes.has_part("../tank", "hull"), "actor IDs do not escape the asset directory")
	check(not ActorMeshes.has_part("missing", "body"), "unknown actors are unavailable")
	check(not ActorMeshes.has_part("tank", "missing"), "unknown parts are unavailable")
	check(ActorMeshes.role("missing") == null, "unknown shader roles are not silently lit")


func test_per_instance_eye_material_does_not_mutate_shared_geometry() -> void:
	var world := stage()
	var first := Walker.new()
	var second := Walker.new()
	world.add_enemy(first)
	world.add_enemy(second)
	var original := second._eye_material.albedo_color
	first._eye_material.albedo_color = Palette.WHITE
	check_eq(second._eye_material.albedo_color, original, "another walker's telegraph material is unchanged")
	check_eq(_fingerprint(ActorMeshes.mesh("walker", "eye")), _fixture().assets.walker.eye, "per-instance telegraphs leave the shared eye intact")
