class_name LowPoly
extends RefCounted
## Builds flat-shaded, vertex-colored meshes from simple primitives.
## Faces are oriented away from an "outward" hint, so primitives never render inside out.
## Glowing parts go to an unshaded surface; `flesh` parts pulse like living tissue.

static var lit_material: StandardMaterial3D = _make_material(false)
static var glow_material: StandardMaterial3D = _make_material(true)
static var flesh_material: ShaderMaterial = _make_flesh(false)
static var flesh_glow_material: ShaderMaterial = _make_flesh(true)
## Actors (enemies, the tank, pickups) read their vertex colors as sRGB: true, saturated colors
## that stand out against the scenery, which the default material washes toward pastel.
static var vivid_lit_material: StandardMaterial3D = _make_material(false, true)
static var vivid_glow_material: StandardMaterial3D = _make_material(true, true)

var vivid := false ## Read vertex colors as sRGB when a model needs its actual material colors.
var glow := false ## When true, following primitives go to the unshaded surface.
var flesh := false ## When true, following primitives pulse (combines with `glow`).
var _surfaces := {} ## (glow, flesh) key -> [points, colors, normals]


static func _make_flesh(glowing: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/flesh.gdshader")
	material.set_shader_parameter("glow", glowing)
	return material


static func _make_material(unshaded: bool, vivid := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = vivid
	material.roughness = 1.0
	material.metallic_specular = 0.15
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.disable_receive_shadows = true
	return material


func tri(a: Vector3, b: Vector3, c: Vector3, color: Color, outward := Vector3.ZERO) -> void:
	var normal := (b - a).cross(c - a)
	if outward != Vector3.ZERO and normal.dot(outward) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	normal = normal.normalized()
	# Godot treats clockwise triangles as front-facing.
	var key := int(glow) + 2 * int(flesh)
	if not _surfaces.has(key):
		_surfaces[key] = [PackedVector3Array(), PackedColorArray(), PackedVector3Array()]
	var surface: Array = _surfaces[key]
	var points: PackedVector3Array = surface[0]
	var colors: PackedColorArray = surface[1]
	var normals: PackedVector3Array = surface[2]
	points.append_array([a, c, b])
	colors.append_array([color, color, color])
	normals.append_array([normal, normal, normal])
	surface[0] = points
	surface[1] = colors
	surface[2] = normals


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, outward: Vector3) -> void:
	tri(a, b, c, color, outward)
	tri(a, c, d, color, outward)


## Box centered on `xf.origin`. `top` recolors the upward face (e.g. roofs, grass tops).
func box(xf: Transform3D, size: Vector3, color: Color, top := Color(0, 0, 0, 0)) -> LowPoly:
	var h := size * 0.5
	var p := func(x: float, y: float, z: float) -> Vector3: return xf * Vector3(x * h.x, y * h.y, z * h.z)
	var center := xf.origin
	for axis in 3:
		for sign_value in [-1.0, 1.0]:
			var corners: Array[Vector3] = []
			for uv in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var v := Vector3.ZERO
				v[axis] = sign_value
				v[(axis + 1) % 3] = uv.x
				v[(axis + 2) % 3] = uv.y
				corners.append(p.call(v.x, v.y, v.z))
			var face_color := top if axis == 1 and sign_value > 0.0 and top.a > 0.0 else color
			var mid := (corners[0] + corners[2]) * 0.5
			quad(corners[0], corners[1], corners[2], corners[3], face_color, mid - center)
	return self


## Prism along local +Y from `xf.origin` (bottom) with `sides` sides. A zero top radius makes a cone.
func prism(xf: Transform3D, radius: float, height: float, sides: int, color: Color, top_radius := -1.0, cap := Color(0, 0, 0, 0)) -> LowPoly:
	var top := radius if top_radius < 0.0 else top_radius
	var bottom_center := xf.origin
	var top_center := xf * Vector3(0, height, 0)
	var axis := (top_center - bottom_center).normalized()
	var cap_color := cap if cap.a > 0.0 else color
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var b0 := xf * Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var b1 := xf * Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var t0 := xf * Vector3(cos(a0) * top, height, sin(a0) * top)
		var t1 := xf * Vector3(cos(a1) * top, height, sin(a1) * top)
		var side_mid := (b0 + b1 + t0 + t1) * 0.25
		var out := side_mid - (bottom_center + top_center) * 0.5
		out -= axis * out.dot(axis)
		if top > 0.001:
			quad(b0, b1, t1, t0, color, out)
			tri(top_center, t0, t1, cap_color, axis)
		else:
			tri(b0, b1, top_center, color, out)
		if radius > 0.001:
			tri(bottom_center, b0, b1, color, -axis)
	return self


## Prism lying along local +Z, e.g. gun barrels.
func tube(xf: Transform3D, radius: float, length: float, sides: int, color: Color, end_radius := -1.0) -> LowPoly:
	return prism(xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), radius, length, sides, color, end_radius)


## Gable roof: ridge along local X, footprint `size.x` × `size.z`, rising `size.y`.
func gable(xf: Transform3D, size: Vector3, color: Color, gable_color := Color(0, 0, 0, 0)) -> LowPoly:
	var h := Vector3(size.x * 0.5, size.y, size.z * 0.5)
	var end_color := gable_color if gable_color.a > 0.0 else color
	var a := xf * Vector3(-h.x, 0, -h.z)
	var b := xf * Vector3(h.x, 0, -h.z)
	var c := xf * Vector3(h.x, 0, h.z)
	var d := xf * Vector3(-h.x, 0, h.z)
	var r0 := xf * Vector3(-h.x, h.y, 0)
	var r1 := xf * Vector3(h.x, h.y, 0)
	var center := xf * Vector3(0, h.y * 0.3, 0)
	quad(a, b, r1, r0, color, (a + b + r0 + r1) * 0.25 - center)
	quad(d, c, r1, r0, color, (c + d + r0 + r1) * 0.25 - center)
	tri(a, d, r0, end_color, (a + d + r0) / 3.0 - center)
	tri(b, c, r1, end_color, (b + c + r1) / 3.0 - center)
	return self


## Icosphere with optional deterministic lumpiness, for fungus, foliage and blasts.
func blob(xf: Transform3D, radius: float, color: Color, detail := 0, lumpy := 0.0, seed_value := 0) -> LowPoly:
	var mesh := _icosphere(detail)
	var verts: Array = mesh[0]
	var displaced: Array[Vector3] = []
	for v: Vector3 in verts:
		var n := 1.0
		if lumpy > 0.0:
			n += lumpy * (_hash(v * 17.0 + Vector3.ONE * seed_value) * 2.0 - 1.0)
		displaced.append(xf * (v * radius * n))
	for face: Vector3i in mesh[1]:
		var a := displaced[face.x]
		var b := displaced[face.y]
		var c := displaced[face.z]
		tri(a, b, c, color, (a + b + c) / 3.0 - xf.origin)
	return self


func mesh() -> ArrayMesh:
	var result := ArrayMesh.new()
	var materials: Array[Material] = [vivid_lit_material if vivid else lit_material, vivid_glow_material if vivid else glow_material, flesh_material, flesh_glow_material]
	for key in 4:
		if _surfaces.has(key):
			_add_surface(result, _surfaces[key][0], _surfaces[key][1], _surfaces[key][2], materials[key])
	return result


static func _add_surface(target: ArrayMesh, points: PackedVector3Array, colors: PackedColorArray, normals: PackedVector3Array, material: Material) -> void:
	if points.is_empty():
		return
	# Normals were generated with the faces, on the worker or within its time budget.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	target.surface_set_material(target.get_surface_count() - 1, material)


static func _hash(v: Vector3) -> float:
	return fposmod(sin(v.dot(Vector3(12.9898, 78.233, 37.719))) * 43758.5453, 1.0)


static var _ico_cache := {}


static func _icosphere(detail: int) -> Array:
	if _ico_cache.has(detail):
		return _ico_cache[detail]
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = []
	for v in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
			Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append(v.normalized())
	var faces: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1)]
	for _i in detail:
		var midpoints := {}
		var next: Array[Vector3i] = []
		var mid := func(a: int, b: int) -> int:
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not midpoints.has(key):
				midpoints[key] = verts.size()
				verts.append(((verts[a] + verts[b]) * 0.5).normalized())
			return midpoints[key]
		for f in faces:
			var ab: int = mid.call(f.x, f.y)
			var bc: int = mid.call(f.y, f.z)
			var ca: int = mid.call(f.z, f.x)
			next.append_array([Vector3i(f.x, ab, ca), Vector3i(f.y, bc, ab), Vector3i(f.z, ca, bc), Vector3i(ab, bc, ca)])
		faces = next
	_ico_cache[detail] = [verts, faces]
	return _ico_cache[detail]
