class_name PropField
extends Node3D
## Holds props in a flat grid of buckets so queries only test nearby ones.

const BUCKET := 12.0

var _buckets := {}
var _cells := {}


func add(prop: Prop) -> void:
	var bounds := AABB(prop.global_position, Vector3.ZERO)
	if prop.box_size != Vector3.ZERO:
		bounds = prop.global_transform * AABB(Vector3(-prop.box_size.x * 0.5, 0.0, -prop.box_size.z * 0.5), prop.box_size)
	var cells: Array[Vector2i] = []
	var lo := _key(bounds.position)
	var hi := _key(bounds.end)
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var key := Vector2i(x, z)
			if not _buckets.has(key):
				_buckets[key] = []
			_buckets[key].append(prop)
			cells.append(key)
	_cells[prop] = cells


func remove(prop: Prop) -> void:
	for key: Vector2i in _cells.get(prop, []):
		_buckets[key].erase(prop)
	_cells.erase(prop)


func _key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET))


## Props in buckets overlapping the box around the given points, padded by `pad`.
func near(a: Vector3, b: Vector3, pad: float) -> Array:
	var result := []
	var seen := {}
	var k0 := _key(Vector3(minf(a.x, b.x) - pad, 0, minf(a.z, b.z) - pad))
	var k1 := _key(Vector3(maxf(a.x, b.x) + pad, 0, maxf(a.z, b.z) + pad))
	for x in range(k0.x, k1.x + 1):
		for z in range(k0.y, k1.y + 1):
			var key := Vector2i(x, z)
			if _buckets.has(key):
				for prop: Prop in _buckets[key]:
					if not seen.has(prop):
						seen[prop] = true
						result.append(prop)
	return result


## Nearest prop hit along a segment: {prop, t} or empty.
func segment_hit(from: Vector3, to: Vector3, radius := 0.0) -> Dictionary:
	var best := {}
	for prop: Prop in near(from, to, 12.0):
		if prop.dead:
			continue
		var t := prop.hit_test(from, to, radius)
		if t >= 0.0 and (best.is_empty() or t < best.t):
			best = {"prop": prop, "t": t}
	return best


func in_radius(center: Vector3, r: float) -> Array:
	var result := []
	for prop: Prop in near(center, center, r + 12.0):
		if prop.dead:
			continue
		if prop.box_size != Vector3.ZERO:
			var local := prop.global_transform.affine_inverse() * center
			var outside := Vector2(maxf(absf(local.x) - prop.box_size.x * 0.5, 0.0), maxf(absf(local.z) - prop.box_size.z * 0.5, 0.0))
			if outside.length() < r:
				result.append(prop)
		elif Vector2(prop.global_position.x - center.x, prop.global_position.z - center.z).length() < r + prop.footprint:
			result.append(prop)
	return result
