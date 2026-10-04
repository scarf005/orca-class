class_name PropKit
## Low-poly meshes for the stage's scenery, cached by kind and variant.

const ROOF_COLORS: Array[Color] = [Palette.PERIWINKLE, Palette.CORAL, Palette.TEAL, Palette.MINT, Palette.SKY, Palette.MAUVE]
const WALL_COLORS: Array[Color] = [Palette.CREAM, Palette.MIST, Palette.CONCRETE, Palette.PEACH, Palette.BUTTER]
const CAR_COLORS: Array[Color] = [Palette.SKY, Palette.BLUSH, Palette.BUTTER, Palette.MIST, Palette.MINT]

static var _cache := {}
static var _pieces := {}
const COLLAPSE_PIECES := 12


## Partition the actual vertex-colored scenery into at most twelve chunks. Materials (including
## fungal glow) survive; the upper third is separate so the roof can cave before the walls.
static func collapse_pieces(source: Mesh) -> Array[Mesh]:
	var key := source.get_instance_id()
	if _pieces.has(key):
		return _pieces[key]
	var bounds := source.get_aabb()
	var chunks: Array[ArrayMesh] = []
	for i in COLLAPSE_PIECES:
		chunks.append(ArrayMesh.new())
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var bins: Array[Array] = []
		for i in COLLAPSE_PIECES:
			bins.append([PackedVector3Array(), PackedVector3Array(), PackedColorArray()])
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for triangle in range(0, count, 3):
			var ids: Array[int] = []
			var center := Vector3.ZERO
			for corner in 3:
				var id := indices[triangle + corner] if not indices.is_empty() else triangle + corner
				ids.append(id)
				center += vertices[id] / 3.0
			var relative := (center - bounds.position) / bounds.size.max(Vector3.ONE * 0.001)
			var bin := mini(int(relative.y * 3.0), 2) * 4 + int(relative.x >= 0.5) * 2 + int(relative.z >= 0.5)
			for id in ids:
				bins[bin][0].append(vertices[id])
				bins[bin][1].append(normals[id])
				bins[bin][2].append(colors[id])
		for i in COLLAPSE_PIECES:
			if bins[i][0].is_empty():
				continue
			var piece := []
			piece.resize(Mesh.ARRAY_MAX)
			piece[Mesh.ARRAY_VERTEX] = bins[i][0]
			piece[Mesh.ARRAY_NORMAL] = bins[i][1]
			piece[Mesh.ARRAY_COLOR] = bins[i][2]
			chunks[i].add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, piece)
			chunks[i].surface_set_material(chunks[i].get_surface_count() - 1, source.surface_get_material(surface))
	var result: Array[Mesh] = []
	for chunk in chunks:
		if chunk.get_surface_count() > 0:
			result.append(chunk)
	_pieces[key] = result
	return result


static func mesh(kind: String, variant := 0) -> Mesh:
	var key := "%s:%d" % [kind, variant]
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		_cache[key] = Callable(PropKit, kind).call(variant, rng)
	return _cache[key]


static func _xf(pos: Vector3, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)


static func house(variant: int, rng: RandomNumberGenerator) -> Mesh:
	return _house(LowPoly.new(), variant, Vector2(rng.randf_range(7.0, 9.0), rng.randf_range(5.0, 6.0))).mesh()


static func _house(b: LowPoly, variant: int, size: Vector2) -> LowPoly:
	if variant % 4 in [1, 3]:
		return _flat_house(b, variant, size)
	var wall: Color = [Palette.CREAM, Palette.CONCRETE, Palette.MIST][variant % 3]
	var roof: Color = [Palette.SLATE, Palette.CORAL, Palette.TEAL, Palette.SKY, Palette.STONE, Palette.SAGE][variant % 6]
	var w := size.x
	var d := size.y
	var front := d * 0.5 + 0.65
	b.box(_xf(Vector3(0, 0.3, 0)), Vector3(w + 0.3, 0.6, d + 0.3), Palette.STONE)
	b.box(_xf(Vector3(0, 1.8, 0)), Vector3(w, 2.6, d), wall)
	# A renovated farmhouse: metal roof over the old body, glazed-in 툇마루 below the eaves.
	_farm_roof(b, Vector3(0, 3.1, 0), Vector3(w + 1.2, 1.1, d + 1.6), roof, variant % 3 == 2)
	b.box(_xf(Vector3(0, 0.65, d * 0.5 + 0.35)), Vector3(w * 0.84, 0.3, 0.9), Palette.CONCRETE)
	b.box(_xf(Vector3(0, 1.65, front - 0.35)), Vector3(w * 0.84, 1.9, 0.7), wall)
	b.box(_xf(Vector3(w * 0.12, 1.85, front + 0.01)), Vector3(w * 0.48, 1.25, 0.06), Palette.SLATE)
	for y in [1.2, 1.85, 2.5]:
		b.box(_xf(Vector3(w * 0.12, y, front + 0.06)), Vector3(w * 0.5, 0.07, 0.06), Palette.MIST)
	for x in [-0.12, 0.0, 0.12, 0.24, 0.36]:
		b.box(_xf(Vector3(w * x, 1.85, front + 0.07)), Vector3(0.07, 1.35, 0.07), Palette.ASH)
	var door := -w * 0.28
	b.box(_xf(Vector3(door, 1.65, front + 0.02)), Vector3(1.05, 1.9, 0.07), Palette.ASH)
	b.box(_xf(Vector3(door, 1.9, front + 0.07)), Vector3(0.85, 1.15, 0.06), Palette.SLATE)
	b.box(_xf(Vector3(door + 0.33, 1.45, front + 0.12)), Vector3(0.06, 0.25, 0.08), Palette.INK)
	for step in 2:
		b.box(_xf(Vector3(door, 0.15 + step * 0.15, front + 0.7 - step * 0.2)), Vector3(1.5, 0.3, 1.0 - step * 0.4), Palette.CONCRETE)
	b.box(_xf(Vector3(0, 2.68, front - 0.25)), Vector3(w * 0.9, 0.12, 1.0), roof)
	# Broad sliding windows on the sides, with a small sill and metal frames.
	for side in [-1.0, 1.0]:
		b.box(_xf(Vector3(side * (w * 0.5 + 0.02), 1.85, -0.4)), Vector3(0.06, 1.25, 2.1), Palette.ASH)
		b.box(_xf(Vector3(side * (w * 0.5 + 0.06), 1.85, -0.4)), Vector3(0.05, 1.08, 1.94), Palette.SLATE)
		b.box(_xf(Vector3(side * (w * 0.5 + 0.1), 1.85, -0.4)), Vector3(0.06, 1.16, 0.07), Palette.MIST)
		b.box(_xf(Vector3(side * (w * 0.5 + 0.08), 1.18, -0.4)), Vector3(0.22, 0.12, 2.25), Palette.CONCRETE)
		if variant % 3 == 1:
			# Exposed masonry along the lower wall; keep it broad enough to survive dithering.
			b.box(_xf(Vector3(side * (w * 0.5 + 0.01), 0.88, 0)), Vector3(0.04, 0.55, d), Palette.OCHRE)
			for y in [0.7, 0.9, 1.1]:
				b.box(_xf(Vector3(side * (w * 0.5 + 0.04), y, 0)), Vector3(0.03, 0.025, d), Palette.CONCRETE)
	# Gutter and downpipe replace the oversized chimney on the ridge.
	b.box(_xf(Vector3(0, 3.08, d * 0.5 + 0.81)), Vector3(w + 1.3, 0.12, 0.12), Palette.ASH)
	b.prism(_xf(Vector3(w * 0.46, 0.6, d * 0.5 + 0.81)), 0.07, 2.5, 6, Palette.ASH)
	if variant % 2 == 0:
		b.prism(Transform3D(Basis(Vector3.RIGHT, 1.2), Vector3(-w * 0.4, 3.2, -d * 0.4)), 0.35, 0.08, 6, Palette.WHITE)
	return b


## Masonry village houses with a usable, green waterproofed concrete rooftop.
static func _flat_house(b: LowPoly, variant: int, size: Vector2) -> LowPoly:
	b.vivid = true
	var w := size.x
	var d := size.y
	var brick := variant % 4 == 1
	var two_storeys := variant % 8 == 1
	var roof_y := 4.5 if two_storeys else 3.1
	var wall := Palette.OCHRE if brick else Palette.CONCRETE
	var front := d * 0.5
	b.box(_xf(Vector3(0, 0.3, 0)), Vector3(w + 0.25, 0.6, d + 0.25), Palette.STONE)
	b.box(_xf(Vector3(0, (roof_y + 0.6) * 0.5, 0)), Vector3(w, roof_y - 0.6, d), wall)
	if brick:
		# Staggered mortar joints on the actual facade, without a texture or extra material.
		for side in [-1.0, 1.0]:
			for axis in 2:
				var length := w if axis == 0 else d
				var face := Transform3D(Basis(Vector3.UP, PI * 0.5 * axis), Vector3(0, 0, side * (d * 0.5 + 0.01)) if axis == 0 else Vector3(side * (w * 0.5 + 0.01), 0, 0))
				for row in int((roof_y - 0.6) / 0.25):
					var y := 0.6 + row * 0.25
					b.quad(face * Vector3(-length * 0.5, y, 0), face * Vector3(length * 0.5, y, 0), face * Vector3(length * 0.5, y + 0.025, 0), face * Vector3(-length * 0.5, y + 0.025, 0), Palette.STONE, face.basis.z * side)
					for column in range(1, int(length / 0.7)):
						var x := -length * 0.5 + column * 0.7 + (row % 2) * 0.35
						b.quad(face * Vector3(x, y, 0), face * Vector3(x + 0.025, y, 0), face * Vector3(x + 0.025, y + 0.25, 0), face * Vector3(x, y + 0.25, 0), Palette.STONE, face.basis.z * side)
	# The roof is an inset green plane, not a green pitched roof.
	b.box(_xf(Vector3(0, roof_y + 0.05, 0)), Vector3(w + 0.35, 0.2, d + 0.35), Palette.CONCRETE)
	b.box(_xf(Vector3(0, roof_y + 0.16, 0)), Vector3(w - 0.25, 0.04, d - 0.25), Palette.PINE)
	for side in [-1.0, 1.0]:
		b.box(_xf(Vector3(0, roof_y + 0.32, side * d * 0.5)), Vector3(w + 0.2, 0.35, 0.2), wall, Palette.CONCRETE)
		b.box(_xf(Vector3(side * w * 0.5, roof_y + 0.32, 0)), Vector3(0.2, 0.35, d), wall, Palette.CONCRETE)
	if two_storeys:
		b.box(_xf(Vector3(0, 2.7, 0)), Vector3(w + 0.12, 0.16, d + 0.12), Palette.CREAM)
	else:
		# Rooftop access room on the lower houses; taller houses keep their roof unobstructed.
		b.box(_xf(Vector3(-w * 0.28, 4.05, -d * 0.25)), Vector3(1.45, 1.6, 1.35), wall)
		b.box(_xf(Vector3(-w * 0.28, 4.9, -d * 0.25)), Vector3(1.65, 0.1, 1.55), Palette.CONCRETE, Palette.PINE)
		b.box(_xf(Vector3(-w * 0.28, 4.0, -d * 0.25 + 0.69)), Vector3(0.65, 1.4, 0.05), Palette.DUSK)
	var door := -w * 0.28
	b.box(_xf(Vector3(door, 1.6, front + 0.03)), Vector3(1.1, 2.0, 0.08), Palette.CONCRETE)
	b.box(_xf(Vector3(door, 1.6, front + 0.08)), Vector3(0.9, 1.85, 0.06), Palette.DUSK)
	b.box(_xf(Vector3(door, 2.1, front + 0.12)), Vector3(0.65, 0.65, 0.05), Palette.SLATE)
	b.box(_xf(Vector3(door, 2.7, front + 0.35)), Vector3(1.5, 0.12, 0.8), Palette.CONCRETE)
	for step in 2:
		b.box(_xf(Vector3(door, 0.15 + step * 0.15, front + 0.65 - step * 0.2)), Vector3(1.4, 0.3, 0.95 - step * 0.4), Palette.CONCRETE)
	for y in ([1.85, 3.65] if two_storeys else [1.85]):
		for x in ([door, 0.0, w * 0.28] if y > 3.0 else [0.0, w * 0.28]):
			b.box(_xf(Vector3(x, y, front + 0.03)), Vector3(1.55, 1.25, 0.08), Palette.CONCRETE)
			b.box(_xf(Vector3(x, y, front + 0.08)), Vector3(1.35, 1.05, 0.06), Palette.SLATE)
			b.box(_xf(Vector3(x, y, front + 0.12)), Vector3(0.06, 1.1, 0.06), Palette.MIST)
		for side in [-1.0, 1.0]:
			b.box(_xf(Vector3(side * (w * 0.5 + 0.03), y, 0)), Vector3(0.08, 1.25, 2.0), Palette.CONCRETE)
			b.box(_xf(Vector3(side * (w * 0.5 + 0.08), y, 0)), Vector3(0.06, 1.05, 1.8), Palette.SLATE)
			b.box(_xf(Vector3(side * (w * 0.5 + 0.12), y, 0)), Vector3(0.06, 1.1, 0.06), Palette.MIST)
	return b


## Shallow corrugated roof, hipped on older bodies and gabled on simpler renovations.
static func _farm_roof(b: LowPoly, p: Vector3, size: Vector3, color: Color, gabled: bool) -> void:
	var x := size.x * 0.5
	var z := size.z * 0.5
	var ridge := x if gabled else x - z * 0.65
	var left := p + Vector3(-ridge, size.y, 0)
	var right := p + Vector3(ridge, size.y, 0)
	b.box(_xf(p), Vector3(size.x, 0.14, size.z), color)
	for side in [-1.0, 1.0]:
		var a := p + Vector3(-x, 0, side * z)
		var c := p + Vector3(x, 0, side * z)
		b.quad(a, c, right, left, color, Vector3(0, z, side * size.y))
		var end := p + Vector3(side * x, 0, 0)
		b.tri(end + Vector3(0, 0, -z), end + Vector3(0, 0, z), right if side > 0 else left, color, Vector3(side, 1, 0))
		# Raised seams, not a high-frequency texture that aliases through the dither pass.
		for i in range(-int(ridge / 0.65), int(ridge / 0.65) + 1):
			var seam := p + Vector3(i * 0.65, 0.025, side * z)
			var top := p + Vector3(i * 0.65, size.y + 0.025, 0)
			b.quad(seam, seam + Vector3.RIGHT * 0.035, top + Vector3.RIGHT * 0.035, top, Palette.ASH, Vector3.UP)
	b.box(_xf(p + Vector3(0, size.y, 0)), Vector3(ridge * 2.0 + 0.15, 0.12, 0.18), color)


static func rubble(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var colors := [Palette.STONE, Palette.CONCRETE, Palette.WOOD, ROOF_COLORS[variant % ROOF_COLORS.size()]]
	for i in 9:
		var p := Vector3(rng.randf_range(-3, 3), rng.randf_range(0.0, 0.6), rng.randf_range(-2.5, 2.5))
		b.box(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))), p), Vector3(rng.randf_range(0.8, 2.5), rng.randf_range(0.3, 1.0), rng.randf_range(0.8, 2.0)), colors[i % colors.size()])
	return b.mesh()


static func wall(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 0.8, 0)), Vector3(6.0, 1.6, 0.25), WALL_COLORS[(variant + 2) % WALL_COLORS.size()])
	b.box(_xf(Vector3(0, 1.65, 0)), Vector3(6.2, 0.12, 0.4), Palette.STONE)
	return b.mesh()


static func jars(_variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 0.2, 0)), Vector3(3.2, 0.4, 2.2), Palette.STONE)
	for i in 7:
		var p := Vector3(-1.1 + (i % 4) * 0.72, 0.4, -0.5 + (i / 4) * 0.9)
		var s := rng.randf_range(0.8, 1.15)
		b.prism(_xf(p), 0.22 * s, 0.25 * s, 7, Palette.WOOD, 0.36 * s)
		b.prism(_xf(p + Vector3(0, 0.25 * s, 0)), 0.36 * s, 0.35 * s, 7, Palette.WOOD, 0.24 * s)
		b.prism(_xf(p + Vector3(0, 0.6 * s, 0)), 0.26 * s, 0.07, 7, Palette.INK, 0.2 * s)
	return b.mesh()


static func greenhouse(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var length := 16.0
	var r := 3.0
	var steps := 5
	for i in steps:
		var a0 := PI * i / steps
		var a1 := PI * (i + 1) / steps
		var p0 := Vector3(cos(a0) * r, sin(a0) * r * 0.9, 0)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r * 0.9, 0)
		var z := Vector3(0, 0, length * 0.5)
		var color := Palette.MIST if (i + variant) % 2 == 0 else Palette.WHITE
		b.quad(p0 - z, p1 - z, p1 + z, p0 + z, color, (p0 + p1) * 0.5)
		b.tri(Vector3.ZERO - z, p0 - z, p1 - z, Palette.MIST, Vector3.BACK * -1)
		b.tri(Vector3.ZERO + z, p0 + z, p1 + z, Palette.MIST, Vector3.BACK)
	# Ribs and a torn flap.
	for k in 5:
		var zc := -length * 0.5 + k * length / 4.0
		b.box(_xf(Vector3(0, r * 0.9 + 0.02, zc)), Vector3(0.6, 0.06, 0.1), Palette.STONE)
	# Fungus bursting out of the side.
	for i in 3:
		b.blob(_xf(Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(0.5, 1.5), rng.randf_range(-6, 6))), rng.randf_range(0.8, 1.5), Palette.FUNGUS if i % 2 == 0 else Palette.LILAC, 0, 0.35, i)
	return b.mesh()


static func pole(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(), 0.18, 10.0, 6, Palette.CONCRETE, 0.13)
	b.box(_xf(Vector3(0, 9.2, 0)), Vector3(2.4, 0.14, 0.14), Palette.STONE)
	b.prism(_xf(Vector3(0.4, 7.4, 0.3)), 0.3, 0.9, 6, Palette.ASH)
	for x in [-1.0, 0.0, 1.0]:
		b.prism(_xf(Vector3(x, 9.27, 0)), 0.06, 0.2, 4, Palette.WHITE)
	return b.mesh()


static func persimmon(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.15, 0.15)), Vector3.ZERO), 0.25, 2.6, 5, Palette.WOOD, 0.16)
	for i in 4:
		var p := Vector3(rng.randf_range(-1.4, 1.4), rng.randf_range(2.6, 3.8), rng.randf_range(-1.4, 1.4))
		b.blob(_xf(p), rng.randf_range(1.1, 1.7), Palette.PINE if (i + variant) % 3 else Palette.SAGE, 0, 0.3, i + variant)
	b.glow = true
	for i in 9:
		var p := Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(2.2, 4.4), rng.randf_range(-2.0, 2.0))
		b.blob(_xf(p), 0.2, Palette.PEACH if i % 2 else Palette.CORAL, 0)
	return b.mesh()


static func zelkova(_variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(), 1.1, 5.0, 7, Palette.WOOD, 0.7)
	for i in 4:
		var angle := i * TAU / 4.0 + 0.4
		b.prism(Transform3D(Basis(Vector3(cos(angle), 0, sin(angle)).cross(Vector3.UP), 0.7), Vector3(0, 4.0, 0)), 0.45, 4.5, 5, Palette.WOOD, 0.2)
	for i in 9:
		var p := Vector3(rng.randf_range(-6, 6), rng.randf_range(7, 11), rng.randf_range(-6, 6))
		b.blob(_xf(p), rng.randf_range(2.6, 3.8), [Palette.PINE, Palette.SAGE, Palette.MOSS][i % 3], 1 if i < 2 else 0, 0.25, i)
	# A shrine rope (금줄) around the trunk.
	b.prism(_xf(Vector3(0, 1.6, 0)), 1.12, 0.15, 7, Palette.STRAW)
	return b.mesh()


static func pavilion(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 0.9, 0)), Vector3(4.6, 0.25, 4.6), Palette.WOOD)
	for x in [-2.0, 2.0]:
		for z in [-2.0, 2.0]:
			b.prism(_xf(Vector3(x, 0, z)), 0.16, 3.3, 6, Palette.CORAL)
	b.box(_xf(Vector3(0, 3.4, 0)), Vector3(5.2, 0.3, 5.2), Palette.CORAL)
	# Hip roof with upturned corners.
	b.prism(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 3.55, 0)), 4.6, 1.8, 4, Palette.SLATE, 0.6)
	b.prism(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 5.35, 0)), 0.6, 0.3, 4, Palette.DUSK, 0.2)
	return b.mesh()


static func bus_stop(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 1.3, -0.8)), Vector3(3.6, 2.6, 0.12), Palette.MIST)
	b.box(_xf(Vector3(0, 2.7, 0)), Vector3(4.0, 0.15, 1.9), Palette.SKY)
	for x in [-1.7, 1.7]:
		b.box(_xf(Vector3(x, 1.3, 0.8)), Vector3(0.12, 2.6, 0.12), Palette.STONE)
	b.box(_xf(Vector3(0, 0.5, -0.4)), Vector3(3.0, 0.1, 0.5), Palette.WOOD)
	b.prism(_xf(Vector3(2.3, 0, 0.6)), 0.06, 2.8, 4, Palette.STONE)
	b.box(_xf(Vector3(2.3, 2.9, 0.6)), Vector3(0.7, 0.7, 0.06), Palette.PERIWINKLE)
	return b.mesh()


static func cultivator(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	# Two-wheel tractor pulling a small trailer; long handlebars.
	b.box(_xf(Vector3(0, 1.0, -1.4)), Vector3(0.9, 0.8, 1.2), Palette.CORAL)
	b.prism(_xf(Vector3(0, 1.4, -1.9)), 0.3, 0.5, 6, Palette.SLATE)
	for x in [-0.7, 0.7]:
		b.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x, 0.6, -1.4)), 0.6, 0.3, 8, Palette.INK)
		b.box(Transform3D(Basis(Vector3.RIGHT, -0.4), Vector3(x * 0.6, 1.6, -0.3)), Vector3(0.08, 0.08, 2.2), Palette.STONE)
	b.box(_xf(Vector3(0, 0.9, 1.4)), Vector3(1.8, 0.5, 2.4), Palette.SKY)
	b.box(_xf(Vector3(0, 0.6, 1.4)), Vector3(1.6, 0.1, 2.2), Palette.STONE)
	b.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(1.0, 0.4, 1.6)), 0.4, 0.2, 7, Palette.INK)
	b.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-1.2, 0.4, 1.6)), 0.4, 0.2, 7, Palette.INK)
	return b.mesh()


static func bale(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.75, 0.75, 0)), 0.78, 1.5, 9, Palette.WHITE, -1.0, Palette.CREAM)
	return b.mesh()


static func church(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 3.0, 0)), Vector3(9.0, 6.0, 15.0), Palette.WHITE)
	b.gable(_xf(Vector3(0, 6.0, 0), PI * 0.5), Vector3(16.0, 3.4, 10.0), Palette.CORAL, Palette.WHITE)
	b.box(_xf(Vector3(0, 6.5, 8.5)), Vector3(3.2, 13.0, 3.2), Palette.WHITE)
	b.prism(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 13.0, 8.5)), 2.4, 5.0, 4, Palette.CORAL, 0.0)
	for z in [-5.0, -1.5, 2.0]:
		b.box(_xf(Vector3(4.51, 3.5, z)), Vector3(0.05, 2.5, 1.0), Palette.SKY)
		b.box(_xf(Vector3(-4.51, 3.5, z)), Vector3(0.05, 2.5, 1.0), Palette.SKY)
	b.glow = true
	b.box(_xf(Vector3(0, 19.5, 8.5)), Vector3(0.3, 3.0, 0.3), Palette.RED)
	b.box(_xf(Vector3(0, 20.2, 8.5)), Vector3(1.8, 0.3, 0.3), Palette.RED)
	return b.mesh()


static func hall(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 2.2, 0)), Vector3(12.0, 4.4, 8.0), Palette.CONCRETE)
	b.box(_xf(Vector3(0, 4.5, 0)), Vector3(12.4, 0.3, 8.4), Palette.STONE)
	b.box(_xf(Vector3(0, 3.6, 4.02)), Vector3(5.0, 0.8, 0.05), Palette.SKY)
	for x in [-4.0, -2.0, 2.0, 4.0]:
		b.box(_xf(Vector3(x, 2.0, 4.02)), Vector3(1.3, 1.4, 0.05), Palette.DUSK)
	b.box(_xf(Vector3(0, 1.3, 4.02)), Vector3(1.6, 2.6, 0.05), Palette.SLATE)
	b.box(_xf(Vector3(3.5, 5.0, -2.0)), Vector3(1.2, 1.0, 1.2), Palette.PERIWINKLE)
	return b.mesh()


static func car(variant: int, rng: RandomNumberGenerator) -> Mesh:
	return _car(LowPoly.new(), variant, rng).mesh()


static func _car(b: LowPoly, variant: int, rng: RandomNumberGenerator) -> LowPoly:
	var color := CAR_COLORS[variant % CAR_COLORS.size()]
	b.box(_xf(Vector3(0, 0.75, 0)), Vector3(1.8, 0.7, 4.3), color)
	b.box(_xf(Vector3(0, 1.4, 0.3)), Vector3(1.6, 0.65, 2.2), color)
	b.box(_xf(Vector3(0, 1.4, -0.82)), Vector3(1.5, 0.55, 0.05), Palette.DUSK)
	b.box(_xf(Vector3(0, 1.4, 1.42)), Vector3(1.5, 0.55, 0.05), Palette.DUSK)
	for x in [-0.9, 0.9]:
		for z in [-1.3, 1.3]:
			b.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x + 0.1 * signf(x), 0.4, z)), 0.38, 0.25, 7, Palette.INK)
	# Rust and moss on the hood.
	b.box(_xf(Vector3(rng.randf_range(-0.4, 0.4), 1.11, -1.4)), Vector3(0.8, 0.02, 0.9), Palette.OCHRE)
	b.blob(_xf(Vector3(0.5, 1.8, 0.8)), 0.4, Palette.FUNGUS, 0, 0.3, variant)
	return b


static func truck(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var color := CAR_COLORS[(variant + 1) % CAR_COLORS.size()]
	b.box(_xf(Vector3(0, 1.6, -3.2)), Vector3(2.4, 2.4, 2.0), color)
	b.box(_xf(Vector3(0, 2.1, -4.21)), Vector3(2.1, 0.9, 0.05), Palette.DUSK)
	b.box(_xf(Vector3(0, 2.0, 1.2)), Vector3(2.5, 3.0, 6.8), Palette.MIST)
	b.box(_xf(Vector3(0, 2.0, 1.2)), Vector3(2.52, 0.4, 6.82), Palette.PERIWINKLE)
	for z in [-3.0, -0.2, 3.2]:
		for x in [-1.1, 1.1]:
			b.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x + 0.15 * signf(x), 0.5, z)), 0.5, 0.3, 7, Palette.INK)
	return b.mesh()


static func mushroom(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var h := rng.randf_range(1.5, 3.5) * (1.0 + (variant % 3) * 0.4)
	var cap := [Palette.FUNGUS, Palette.LILAC, Palette.BLUSH, Palette.PEACH][variant % 4] as Color
	b.prism(Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.2, 0.2)), Vector3.ZERO), 0.35 * (h / 2.5), h, 6, Palette.CREAM, 0.25 * (h / 2.5))
	b.prism(_xf(Vector3(0, h - 0.2, 0)), h * 0.55, h * 0.3, 8, cap, h * 0.12, Palette.MIST)
	b.glow = true
	for i in 4:
		var angle := i * TAU / 4.0 + variant
		b.blob(_xf(Vector3(cos(angle) * h * 0.3, h + 0.05, sin(angle) * h * 0.3)), 0.12 * h / 2.0, Palette.WHITE)
	return b.mesh()


static func spore_tower(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var y := 0.0
	var r := 1.6
	for i in 5:
		var h := rng.randf_range(1.5, 2.5)
		b.prism(_xf(Vector3(rng.randf_range(-0.3, 0.3), y, rng.randf_range(-0.3, 0.3))), r, h, 6, [Palette.MAUVE, Palette.LILAC][i % 2], r * 0.8)
		y += h * 0.9
		r *= 0.8
	b.glow = true
	for i in 6:
		b.blob(_xf(Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(1, y), rng.randf_range(-1.2, 1.2))), rng.randf_range(0.3, 0.6), Palette.FUNGUS, 0, 0.2, i + variant)
	return b.mesh()


static func mycelium(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	# A flat web of veins with lumps, draped over the ground.
	for i in 10:
		var angle := rng.randf() * TAU
		var length := rng.randf_range(2.0, 5.0)
		b.box(Transform3D(Basis(Vector3.UP, angle), Vector3(cos(angle), 0, -sin(angle)) * length * 0.3 + Vector3.UP * 0.05), Vector3(length, 0.12, 0.18), Palette.BLUSH if i % 2 else Palette.FUNGUS)
	for i in 4:
		b.blob(_xf(Vector3(rng.randf_range(-2, 2), 0.2, rng.randf_range(-2, 2))), rng.randf_range(0.4, 0.8), Palette.LILAC, 0, 0.3, i + variant)
	return b.mesh()


static func reeds(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	for i in 14:
		var p := Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
		var h := rng.randf_range(1.6, 2.8)
		var lean := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.25))
		b.prism(Transform3D(lean, p), 0.04, h, 3, Palette.STRAW if (i + variant) % 3 else Palette.OCHRE)
		b.prism(Transform3D(lean, p + lean * Vector3(0, h, 0)), 0.1, 0.5, 4, Palette.CREAM, 0.02)
	return b.mesh()


static func crate(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var color := Palette.PINE if variant % 2 == 0 else Palette.OCHRE
	b.box(_xf(Vector3(0, 0.6, 0)), Vector3(1.8, 1.2, 1.2), color)
	b.box(_xf(Vector3(0, 0.6, 0.61)), Vector3(1.0, 0.3, 0.02), Palette.BUTTER)
	b.box(_xf(Vector3(0, 1.21, 0)), Vector3(1.9, 0.05, 0.3), Palette.INK)
	return b.mesh()


static func rock(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.blob(Transform3D(Basis().scaled(Vector3(1.4, 0.8, 1.1)), Vector3(0, 0.6, 0)), 1.6, Palette.ASH if variant % 2 else Palette.STONE, 0, 0.3, variant)
	return b.mesh()


static func school(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	# Two-floor branch school with a central entrance and clock.
	b.box(_xf(Vector3(0, 4.0, 0)), Vector3(48.0, 8.0, 10.0), Palette.CREAM)
	b.box(_xf(Vector3(0, 8.2, 0)), Vector3(48.6, 0.4, 10.6), Palette.BLUSH)
	b.box(_xf(Vector3(0, 0.3, 0)), Vector3(48.4, 0.6, 10.4), Palette.STONE)
	b.box(_xf(Vector3(0, 5.0, 5.3)), Vector3(7.0, 10.0, 1.2), Palette.MIST)
	b.prism(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 8.5, 5.9)), 1.2, 0.1, 10, Palette.WHITE)
	b.box(_xf(Vector3(0, 8.8, 6.0)), Vector3(0.1, 0.8, 0.05), Palette.INK)
	for floor_y in [2.0, 5.6]:
		for i in 12:
			var x := -22.0 + i * 3.8
			if absf(x) < 4.0:
				continue
			b.box(_xf(Vector3(x, floor_y, 5.01)), Vector3(2.6, 1.8, 0.05), Palette.SKY if i % 4 else Palette.DUSK)
	# Fungus has taken the east wing.
	for i in 6:
		b.blob(_xf(Vector3(14.0 + i * 1.8, 2.0 + (i % 3) * 2.5, 5.0)), 1.8 + (i % 2), Palette.FUNGUS if i % 2 else Palette.LILAC, 0, 0.35, i)
	b.box(_xf(Vector3(-5.0, 1.6, 5.8)), Vector3(3.0, 3.2, 0.3), Palette.PEACH)
	return b.mesh()


## A highway pier: a stained concrete column from below the road bed up into the deck.
static func overpass_pier(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 7.5, 0)), Vector3(2.0, 15.0, 3.0), Palette.CONCRETE)
	b.box(_xf(Vector3(0, 14.6, 0)), Vector3(3.2, 0.8, 4.0), Palette.STONE)
	b.box(_xf(Vector3(1.01, 5.0, 0)), Vector3(0.05, 6.0, 1.2), Palette.ASH)
	return b.mesh()


## One span of the highway deck, `variant` meters long, with its crash barriers and fungus
## dripping from the underside.
static func overpass_deck(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var length := float(variant)
	b.box(_xf(Vector3(0, 0.2, 0)), Vector3(length, 0.4, 10.0), Palette.STONE)
	b.box(_xf(Vector3(0, 1.1, 0)), Vector3(length, 1.4, 14.0), Palette.CONCRETE)
	for side in [-1.0, 1.0]:
		b.box(_xf(Vector3(0, 2.2, side * 6.8)), Vector3(length, 0.8, 0.4), Palette.MIST)
	for i in int(length / 8.0):
		var x := -length * 0.5 + 4.0 + i * 8.0
		b.blob(_xf(Vector3(x, -0.2, rng.randf_range(-3.0, 3.0))), rng.randf_range(0.8, 1.5), Palette.FUNGUS if i % 2 else Palette.LILAC, 0, 0.4, i)
	return b.mesh()


static func gate(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 1.6, 0)), Vector3(1.0, 3.2, 1.0), Palette.CONCRETE)
	b.box(_xf(Vector3(0, 3.3, 0)), Vector3(1.3, 0.3, 1.3), Palette.BLUSH)
	b.box(_xf(Vector3(0.51, 2.0, 0)), Vector3(0.05, 1.8, 0.5), Palette.WOOD)
	return b.mesh()


static func flagpole(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(), 0.1, 12.0, 5, Palette.WHITE)
	b.box(_xf(Vector3(0.8, 10.8, 0)), Vector3(1.6, 1.1, 0.05), Palette.WHITE)
	b.glow = true
	b.blob(_xf(Vector3(0.8, 10.8, 0.06)), 0.3, Palette.RED)
	return b.mesh()


static func plane_tree(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(), 0.4, 6.0, 6, Palette.MIST, 0.3)
	for i in 5:
		b.blob(_xf(Vector3(rng.randf_range(-2, 2), rng.randf_range(6, 9), rng.randf_range(-2, 2))), rng.randf_range(1.8, 2.6), [Palette.BUTTER, Palette.STRAW, Palette.PEACH][(i + variant) % 3], 0, 0.3, i)
	return b.mesh()


static func pier(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	# Floating fishing platform (좌대) with a tiny hut.
	b.box(_xf(Vector3(0, 0.3, 0)), Vector3(5.0, 0.4, 4.0), Palette.WOOD)
	b.box(_xf(Vector3(-0.8, 1.5, 0)), Vector3(2.4, 2.0, 2.4), Palette.CREAM)
	b.gable(_xf(Vector3(-0.8, 2.5, 0)), Vector3(3.0, 1.0, 3.0), ROOF_COLORS[variant % ROOF_COLORS.size()])
	for x in [-2.3, 2.3]:
		b.prism(_xf(Vector3(x, -0.4, 1.8)), 0.35, 0.6, 6, Palette.WHITE)
		b.prism(_xf(Vector3(x, -0.4, -1.8)), 0.35, 0.6, 6, Palette.WHITE)
	return b.mesh()


# --- Infestation -------------------------------------------------------------------------------

## A heaving mass of fleshy lobes with bracket shelves, weeping pustules, hanging strands and a
## ring-toothed maw.
static func flesh_mound(variant: int, rng: RandomNumberGenerator) -> Mesh:
	return _flesh_mass(LowPoly.new(), Vector3.ZERO, 1.3 + (variant % 3) * 0.45, rng).mesh()


## A towering heap of fused flesh, shelves and fruiting stalks, visible from across the valley.
static func fungal_spire(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var y := 0.0
	for size in [2.6, 2.0, 1.5, 1.1]:
		_flesh_mass(b, Vector3(rng.randf_range(-0.8, 0.8), y, rng.randf_range(-0.8, 0.8)), size, rng)
		y += size * 2.2
	_cordyceps_into(b, Vector3(0, y, 0), 4 + variant % 3, 1.6, rng)
	return b.mesh()


static func _flesh_mass(b: LowPoly, at: Vector3, size: float, rng: RandomNumberGenerator) -> LowPoly:
	b.flesh = true
	var colors := [Palette.MAUVE, Palette.BLUSH, Palette.LILAC, Palette.FUNGUS]
	var lobes := 6
	for i in lobes:
		var angle := TAU * i / lobes + rng.randf() * 0.5
		var r := rng.randf_range(0.5, 1.4) * size
		var p := at + Vector3(cos(angle) * r, rng.randf_range(0.3, 1.8) * size, sin(angle) * r)
		b.blob(Transform3D(Basis().scaled(Vector3(1.0, rng.randf_range(0.7, 1.3), 1.0)), p), rng.randf_range(0.8, 1.4) * size, colors[i % colors.size()], 1, 0.35, rng.randi())
	# Bracket shelves with pale gills underneath.
	for i in 4:
		var angle := rng.randf() * TAU
		var p := at + Vector3(cos(angle) * 1.3, rng.randf_range(1.0, 2.6), sin(angle) * 1.3) * size
		var tilt := Basis(Vector3(-sin(angle), 0, cos(angle)), rng.randf_range(-0.3, 0.3))
		b.prism(Transform3D(tilt, p), 0.9 * size, 0.18 * size, 9, Palette.CREAM, 0.25 * size, Palette.PEACH)
		# Strands hanging from the shelf rim.
		for k in 3:
			var hang := p + Vector3(cos(angle + k), 0, sin(angle + k)) * 0.6 * size
			b.prism(Transform3D(Basis(Vector3.RIGHT, PI), hang), 0.06 * size, rng.randf_range(0.6, 1.4) * size, 4, Palette.BLUSH, 0.01)
	# A maw: dark pit ringed with pale teeth.
	var maw := at + Vector3(0, 1.4 * size, 1.1 * size)
	b.blob(Transform3D(Basis().scaled(Vector3(1, 1, 0.4)), maw), 0.55 * size, Palette.INK, 0)
	for i in 7:
		var angle := TAU * i / 7.0
		var tooth := maw + Vector3(cos(angle) * 0.55, sin(angle) * 0.55, 0.15) * size
		b.prism(Transform3D(Basis(Vector3(sin(angle), -cos(angle), 0), PI * 0.5), tooth), 0.08 * size, 0.3 * size, 3, Palette.CREAM, 0.0)
	# Weeping, glowing pustules.
	b.glow = true
	for i in 8:
		var angle := rng.randf() * TAU
		b.blob(Transform3D(Basis(), at + Vector3(cos(angle) * 1.2, rng.randf_range(0.5, 2.4), sin(angle) * 1.2) * size), rng.randf_range(0.12, 0.26) * size, Palette.FUNGUS if i % 3 else Palette.WHITE)
	b.glow = false
	b.flesh = false
	return b


## Stalks burst out of the ground, twisting as they climb, each ending in a swollen glowing club.
static func cordyceps(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	_cordyceps_into(b, Vector3.ZERO, 3 + variant % 3, 1.0, rng)
	b.blob(Transform3D(Basis().scaled(Vector3(1.4, 0.3, 1.4)), Vector3(0, 0.1, 0)), 0.9, Palette.DUSK, 0, 0.4, variant)
	for i in 6:
		var angle := TAU * i / 6.0
		b.box(Transform3D(Basis(Vector3.UP, angle), Vector3(cos(angle), 0.06, -sin(angle)) * 1.2), Vector3(1.8, 0.1, 0.14), Palette.MAUVE)
	return b.mesh()


static func _cordyceps_into(b: LowPoly, at: Vector3, stalks: int, scale: float, rng: RandomNumberGenerator) -> void:
	b.flesh = true
	for s in stalks:
		var p := at + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6)) * scale
		var dir := Vector3(rng.randf_range(-0.4, 0.4), 1.0, rng.randf_range(-0.4, 0.4)).normalized()
		var radius := rng.randf_range(0.14, 0.22) * scale
		for k in 5:
			var length := rng.randf_range(0.5, 0.9) * scale
			var basis := Basis(Vector3.UP.cross(dir).normalized(), Vector3.UP.angle_to(dir)) if dir.cross(Vector3.UP).length() > 0.01 else Basis()
			b.prism(Transform3D(basis, p), radius, length, 5, Palette.CREAM if k % 2 else Palette.PEACH, radius * 0.85)
			p += dir * length
			dir = (dir + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.1, 0.3), rng.randf_range(-0.5, 0.5))).normalized()
			radius *= 0.85
		b.glow = true
		b.blob(Transform3D(Basis().scaled(Vector3(1, 1.6, 1)), p), rng.randf_range(0.22, 0.35) * scale, Palette.FUNGUS, 0, 0.3, rng.randi())
		b.glow = false
	b.flesh = false


## A village house with the fungus bursting through its roof and windows.
static func infested_house(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var size := Vector2(rng.randf_range(7.0, 9.0), rng.randf_range(5.0, 6.0))
	var b := _house(LowPoly.new(), variant, size)
	var roof_y := 4.5 if variant % 8 == 1 else 3.1
	_flesh_mass(b, Vector3(rng.randf_range(-1.5, 1.5), roof_y + 0.1, 0), 1.1, rng)
	b.flesh = true
	# Strands follow the renovated door and windows, outside the glazed porch.
	var front := size.y * 0.5 + (0.2 if variant % 4 in [1, 3] else 0.8)
	for x in [-0.28, 0.0, 0.24]:
		b.box(Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(x * size.x, 1.0, front)), Vector3(0.7, 1.9, 0.12), Palette.BLUSH)
		b.blob(Transform3D(Basis(), Vector3(x * size.x, 0.2, front + 0.3)), 0.45, Palette.MAUVE, 0, 0.3, rng.randi())
	b.flesh = false
	_cordyceps_into(b, Vector3(-3.0, roof_y + 0.3, -1.0), 2, 0.8, rng)
	return b.mesh()


## A wreck with stalks growing out of the cabin.
static func infested_car(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := _car(LowPoly.new(), variant, rng)
	_cordyceps_into(b, Vector3(0, 1.6, 0.2), 3, 0.8, rng)
	b.flesh = true
	b.blob(Transform3D(Basis().scaled(Vector3(1.0, 0.5, 1.6)), Vector3(0, 1.3, -1.2)), 0.8, Palette.MAUVE, 0, 0.35, variant)
	b.flesh = false
	return b.mesh()


## A farm cow standing where it died, fruiting bodies splitting its back.
static func husk_cow(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var hide := Palette.OCHRE if variant % 2 else Palette.WOOD
	b.box(_xf(Vector3(0, 1.2, 0)), Vector3(1.0, 0.9, 2.1), hide)
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 1.15, -1.3)), Vector3(0.55, 0.5, 0.7), hide)
	b.box(_xf(Vector3(0, 1.0, -1.65)), Vector3(0.45, 0.3, 0.2), Palette.PEACH)
	for x in [-0.3, 0.3]:
		b.prism(Transform3D(Basis(Vector3.BACK, -0.9 * signf(x)), Vector3(x, 1.45, -1.35)), 0.05, 0.3, 3, Palette.CREAM, 0.0)
		for z in [-0.75, 0.75]:
			b.box(_xf(Vector3(x, 0.4, z)), Vector3(0.2, 0.8, 0.2), hide)
	_cordyceps_into(b, Vector3(0, 1.6, 0.2), 3, 0.9, rng)
	b.flesh = true
	b.blob(Transform3D(Basis(), Vector3(0.5, 1.2, 0.3)), 0.45, Palette.BLUSH, 0, 0.4, variant)
	b.flesh = false
	return b.mesh()


## Swollen translucent egg sacs on short stalks, glowing from inside.
static func egg_sacs(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.flesh = true
	for i in 7 + variant % 4:
		var p := Vector3(rng.randf_range(-1.1, 1.1), 0, rng.randf_range(-1.1, 1.1))
		var h := rng.randf_range(0.3, 0.8)
		b.prism(Transform3D(Basis(), p), 0.08, h, 4, Palette.MAUVE, 0.05)
		b.glow = true
		b.blob(Transform3D(Basis().scaled(Vector3(1, 1.5, 1)), p + Vector3.UP * (h + 0.35)), rng.randf_range(0.28, 0.45), Palette.BLUSH, 0, 0.2, i)
		b.glow = false
		b.blob(Transform3D(Basis(), p + Vector3.UP * (h + 0.3)), 0.14, Palette.DUSK)
	b.flesh = false
	return b.mesh()


## Raised veins spreading over the ground from a central pod.
static func veins(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.flesh = true
	for i in 7:
		var angle := TAU * i / 7.0 + rng.randf() * 0.4
		var p := Vector3.ZERO
		var dir := Vector3(cos(angle), 0, sin(angle))
		var width := 0.28
		for k in 4:
			var length := rng.randf_range(1.2, 2.2)
			var next := p + dir * length
			b.box(Transform3D(Basis.looking_at(dir, Vector3.UP), (p + next) * 0.5 + Vector3.UP * 0.08), Vector3(width, 0.16, length), Palette.BLUSH if k % 2 else Palette.MAUVE)
			if rng.randf() < 0.4:
				b.glow = true
				b.blob(Transform3D(Basis(), next + Vector3.UP * 0.15), 0.18, Palette.FUNGUS)
				b.glow = false
			p = next
			dir = dir.rotated(Vector3.UP, rng.randf_range(-0.6, 0.6))
			width *= 0.75
	b.blob(Transform3D(Basis().scaled(Vector3(1, 0.6, 1)), Vector3(0, 0.3, 0)), 0.8 + (variant % 3) * 0.2, Palette.MAUVE, 1, 0.3, variant)
	b.flesh = false
	return b.mesh()


# --- Modular landmarks: each piece is its own destructible prop -------------------------------

## Half of the church nave: walls, windows and its half of the roof. Variant 1 is the rear half.
static func church_nave(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 3.0, 0)), Vector3(9.0, 6.0, 7.4), Palette.WHITE)
	b.gable(_xf(Vector3(0, 6.0, 0), PI * 0.5), Vector3(7.6, 3.4, 10.0), Palette.CORAL, Palette.WHITE)
	for z in [-1.8, 1.8]:
		b.box(_xf(Vector3(4.51, 3.5, z)), Vector3(0.05, 2.5, 1.0), Palette.SKY)
		b.box(_xf(Vector3(-4.51, 3.5, z)), Vector3(0.05, 2.5, 1.0), Palette.SKY)
	if variant == 1:
		b.box(_xf(Vector3(0, 1.4, -3.72)), Vector3(1.8, 2.8, 0.05), Palette.WOOD)
	return b.mesh()


static func church_tower(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 6.5, 0)), Vector3(3.2, 13.0, 3.2), Palette.WHITE)
	b.box(_xf(Vector3(0, 11.0, 1.61)), Vector3(1.0, 1.6, 0.05), Palette.DUSK)
	b.box(_xf(Vector3(0, 13.1, 0)), Vector3(3.5, 0.3, 3.5), Palette.CONCRETE)
	return b.mesh()


static func church_spire(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3.ZERO), 2.4, 5.0, 4, Palette.CORAL, 0.0)
	b.glow = true
	b.box(_xf(Vector3(0, 6.5, 0)), Vector3(0.3, 3.0, 0.3), Palette.RED)
	b.box(_xf(Vector3(0, 7.2, 0)), Vector3(1.8, 0.3, 0.3), Palette.RED)
	return b.mesh()


static func zelkova_trunk(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(), 1.1, 5.0, 7, Palette.WOOD, 0.7)
	for i in 4:
		var angle := i * TAU / 4.0 + 0.4
		b.prism(Transform3D(Basis(Vector3(cos(angle), 0, sin(angle)).cross(Vector3.UP), 0.7), Vector3(0, 4.0, 0)), 0.45, 3.0, 5, Palette.WOOD, 0.25)
	b.prism(_xf(Vector3(0, 1.6, 0)), 1.12, 0.15, 7, Palette.STRAW)
	return b.mesh()


## The crown of the old tree; it sits on the trunk and falls with it.
static func zelkova_canopy(_variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	for i in 9:
		var p := Vector3(rng.randf_range(-6, 6), rng.randf_range(2, 6), rng.randf_range(-6, 6))
		b.blob(_xf(p), rng.randf_range(2.6, 3.8), [Palette.PINE, Palette.SAGE, Palette.MOSS][i % 3], 1 if i < 2 else 0, 0.25, i)
	return b.mesh()


## One classroom block of the branch school, two floors of windows.
static func school_wing(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 4.0, 0)), Vector3(10.0, 8.0, 10.0), Palette.CREAM)
	b.box(_xf(Vector3(0, 8.2, 0)), Vector3(10.4, 0.4, 10.6), Palette.BLUSH)
	b.box(_xf(Vector3(0, 0.3, 0)), Vector3(10.2, 0.6, 10.4), Palette.STONE)
	for floor_y in [2.0, 5.6]:
		for x in [-3.2, 0.0, 3.2]:
			b.box(_xf(Vector3(x, floor_y, 5.01)), Vector3(2.6, 1.8, 0.05), Palette.SKY if rng.randf() < 0.8 else Palette.DUSK)
	if variant >= 2:
		# The fungus has taken the east wing.
		for i in 3:
			b.flesh = true
			b.blob(_xf(Vector3(-3.0 + i * 3.0, 2.0 + (i % 2) * 3.0, 5.0)), 1.8, Palette.FUNGUS if i % 2 else Palette.LILAC, 0, 0.35, i + variant)
			b.flesh = false
	return b.mesh()


static func school_center(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 5.0, 0)), Vector3(7.0, 10.0, 11.2), Palette.MIST)
	b.box(_xf(Vector3(0, 10.2, 0)), Vector3(7.4, 0.4, 11.6), Palette.BLUSH)
	b.prism(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 8.5, 5.61)), 1.2, 0.1, 10, Palette.WHITE)
	b.box(_xf(Vector3(0, 8.8, 5.72)), Vector3(0.1, 0.8, 0.05), Palette.INK)
	b.box(_xf(Vector3(0, 1.6, 5.61)), Vector3(3.0, 3.2, 0.1), Palette.PEACH)
	return b.mesh()


# --- Things that go boom ------------------------------------------------------------------------

## A 200 L oil drum, hazard-striped.
static func barrel(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var body := [Palette.HOT, Palette.AMBER, Palette.CORAL][variant % 3] as Color
	b.prism(Transform3D(), 0.38, 1.0, 10, body, -1.0, Palette.INK)
	for y in [0.2, 0.75]:
		b.prism(_xf(Vector3(0, y, 0)), 0.395, 0.06, 10, Palette.INK)
	b.box(_xf(Vector3(0, 0.5, 0.38)), Vector3(0.3, 0.25, 0.02), Palette.BUTTER)
	return b.mesh()


static func gas_station(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	for x in [-3.5, 3.5]:
		b.box(_xf(Vector3(x, 2.5, 0)), Vector3(0.4, 5.0, 0.4), Palette.CONCRETE)
	b.box(_xf(Vector3(0, 5.2, 0)), Vector3(10.0, 0.6, 6.0), Palette.WHITE)
	b.box(_xf(Vector3(0, 5.2, 3.02)), Vector3(10.0, 0.4, 0.05), Palette.HOT)
	b.box(_xf(Vector3(0, 0.1, 0)), Vector3(9.0, 0.2, 4.0), Palette.STONE)
	b.box(_xf(Vector3(6.5, 3.5, 2.5)), Vector3(0.3, 7.0, 0.3), Palette.STONE)
	b.box(_xf(Vector3(6.5, 6.8, 2.5)), Vector3(2.2, 1.6, 0.2), Palette.HOT)
	b.glow = true
	b.box(_xf(Vector3(6.5, 6.8, 2.62)), Vector3(1.6, 0.4, 0.02), Palette.WHITE)
	return b.mesh()


static func gas_pump(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 0.9, 0)), Vector3(0.8, 1.8, 0.5), Palette.WHITE)
	b.box(_xf(Vector3(0, 1.5, 0.26)), Vector3(0.5, 0.4, 0.02), Palette.DUSK)
	b.box(_xf(Vector3(0, 0.6, 0.26)), Vector3(0.8, 0.3, 0.02), [Palette.HOT, Palette.AMBER][variant % 2])
	b.box(_xf(Vector3(0.45, 1.0, 0)), Vector3(0.1, 0.5, 0.1), Palette.INK)
	return b.mesh()
