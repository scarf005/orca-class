extends TestCase
## Farmhouse renovations stay inside the existing gameplay height and break into their actual mesh.

func test_all_house_variants_have_valid_bounded_geometry() -> void:
	for kind in ["house", "infested_house"]:
		for variant in 12:
			var mesh := PropKit.mesh(kind, variant)
			var bounds := mesh.get_aabb()
			# Fungal stalks extend past the building; only the plain house defines the shell.
			if kind == "house":
				check(bounds.position.y >= -0.01, "the building does not sink below ground")
				check(bounds.end.y <= Scenery.PROPS[kind][1], "the roof fits its gameplay height")
			check(mesh == PropKit.mesh(kind, variant), "streaming reuses the cached mesh")
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				check_eq(vertices.size() % 3, 0, "complete triangles")
				check_eq(normals.size(), vertices.size(), "every vertex has a normal")
				check(vertices.size() > 0, "nonempty surface")
				for vertex in vertices:
					if not vertex.is_finite():
						check(false, "finite vertices")
						break
				for normal in normals:
					if not normal.is_finite() or normal.length_squared() < 0.99:
						check(false, "finite nondegenerate normals")
						break

func test_flat_roof_variants_have_a_horizontal_green_rooftop() -> void:
	for variant in 12:
		var mesh := PropKit.mesh("house", variant)
		var green_area := 0.0
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			for i in range(0, vertices.size(), 3):
				if colors[i] != Palette.PINE:
					continue
				var a := vertices[i]
				var b := vertices[i + 1]
				var c := vertices[i + 2]
				if a.y > 3.0 and is_equal_approx(a.y, b.y) and is_equal_approx(a.y, c.y):
					green_area += (b - a).cross(c - a).length() * 0.5
		if variant % 4 in [1, 3]:
			check(green_area > 25.0, "flat houses have a usable green roof, not a green pitched facade")
		else:
			check_eq(green_area, 0.0, "pitched farmhouses remain a different building type")

func test_demolition_preserves_every_house_triangle_and_material() -> void:
	for kind in ["house", "infested_house"]:
		for variant in 12:
			var mesh := PropKit.mesh(kind, variant)
			var pieces := PropKit.collapse_pieces(mesh)
			check(not pieces.is_empty() and pieces.size() <= PropKit.COLLAPSE_PIECES, "bounded demolition pieces")
			var source_count := 0
			var piece_count := 0
			var source_by_material := {}
			var piece_by_material := {}
			for surface in mesh.get_surface_count():
				var source_vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				var source_material := mesh.surface_get_material(surface)
				var source_material_id := source_material.get_instance_id()
				source_count += source_vertices.size()
				source_by_material[source_material_id] = source_by_material.get(source_material_id, 0) + source_vertices.size()
			for piece in pieces:
				for surface in piece.get_surface_count():
					var piece_vertices: PackedVector3Array = piece.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					var piece_material := piece.surface_get_material(surface)
					var piece_material_id := piece_material.get_instance_id()
					piece_count += piece_vertices.size()
					piece_by_material[piece_material_id] = piece_by_material.get(piece_material_id, 0) + piece_vertices.size()
			check_eq(piece_by_material, source_by_material, "each %s %d material keeps its triangles" % [kind, variant])
			check_eq(piece_count, source_count, "%s %d loses no roof, window or wall triangles" % [kind, variant])
