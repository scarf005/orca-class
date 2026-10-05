class_name ActorDeform
extends RefCounted
## Per-spawn fungal variation on editable Blender unit meshes, never on static actor parts.
## Keeps LowPoly.blob's displacement, random draw order and flat shading.

var _surfaces := {}


func append(source: Mesh, xf: Transform3D, radius: float, lumpy := 0.0, seed_value := 0) -> ActorDeform:
	for s in source.get_surface_count():
		var arrays := source.surface_get_arrays(s)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for i in vertices.size():
				indices.append(i)
		var displaced := PackedVector3Array()
		for v in vertices:
			var n := 1.0
			if lumpy > 0.0:
				n += lumpy * (LowPoly._hash(v * 17.0 + Vector3.ONE * seed_value) * 2.0 - 1.0)
			displaced.append(xf * (v * radius * n))
		var material := source.surface_get_material(s)
		if not _surfaces.has(material):
			_surfaces[material] = [PackedVector3Array(), PackedColorArray(), PackedVector3Array()]
		var surface: Array = _surfaces[material]
		for i in range(0, indices.size(), 3):
			var a := displaced[indices[i]]
			var b := displaced[indices[i + 1]]
			var c := displaced[indices[i + 2]]
			# Imported Godot triangles are clockwise, just like LowPoly's output.
			var normal := (c - a).cross(b - a).normalized()
			surface[0].append_array([a, b, c])
			surface[1].append_array([colors[indices[i]], colors[indices[i + 1]], colors[indices[i + 2]]])
			surface[2].append_array([normal, normal, normal])
	return self


func mesh() -> ArrayMesh:
	var result := ArrayMesh.new()
	for material: Material in _surfaces:
		var surface: Array = _surfaces[material]
		LowPoly._add_surface(result, surface[0], surface[1], surface[2], material)
	return result
