extends TestCase


func test_coax_mesh_has_no_longitudinal_gap_between_barrel_and_receiver() -> void:
	for caliber in TankModel.COAX_LENGTHS:
		var length: float = TankModel.COAX_LENGTHS[caliber]
		var mesh := TankModel._coax_mesh(caliber, length)
		check(_covers_z(mesh, -length - 0.3, 0.45), "%d mm barrel joins its receiver in the mesh used by the HUD" % caliber)


func test_gunship_body_mesh_has_no_longitudinal_gap_to_tail_stabilizer() -> void:
	var world := stage("boss")
	world.director._start_boss({"kind": "gunship"})
	var boss := world.boss as Gunship
	var body := boss.model.get_child(0) as MeshInstance3D
	check(_covers_z(body.mesh, 0.0, 12.5), "the built airframe spans the hull through the tail stabilizer without an empty cross-section")


## Project actual triangles onto the longitudinal axis: an empty interval is a visible gap.
func _covers_z(mesh: Mesh, start: float, end: float) -> bool:
	var intervals: Array[Vector2] = []
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		for i in range(0, indices.size() if not indices.is_empty() else vertices.size(), 3):
			var a := vertices[indices[i] if not indices.is_empty() else i].z
			var b := vertices[indices[i + 1] if not indices.is_empty() else i + 1].z
			var c := vertices[indices[i + 2] if not indices.is_empty() else i + 2].z
			intervals.append(Vector2(minf(a, minf(b, c)), maxf(a, maxf(b, c))))
	intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var covered := start
	for interval in intervals:
		if interval.y < covered:
			continue
		# Shared endpoints can differ by floating-point rotation roundoff.
		if interval.x > covered and not is_equal_approx(interval.x, covered):
			return false
		covered = maxf(covered, interval.y)
		if covered >= end:
			return true
	return false
