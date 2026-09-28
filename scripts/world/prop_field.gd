class_name PropField
extends Node3D
## Holds props in a flat grid of buckets so queries only test nearby ones.

const BUCKET := 12.0

var _buckets := {}


func add(prop: Prop) -> void:
	var key := _key(prop.global_position)
	if not _buckets.has(key):
		_buckets[key] = []
	_buckets[key].append(prop)


func remove(prop: Prop) -> void:
	var key := _key(prop.global_position)
	if _buckets.has(key):
		_buckets[key].erase(prop)


func _key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET))


## Props in buckets overlapping the box around the given points, padded by `pad`.
func near(a: Vector3, b: Vector3, pad: float) -> Array:
	var result := []
	var k0 := _key(Vector3(minf(a.x, b.x) - pad, 0, minf(a.z, b.z) - pad))
	var k1 := _key(Vector3(maxf(a.x, b.x) + pad, 0, maxf(a.z, b.z) + pad))
	for x in range(k0.x, k1.x + 1):
		for z in range(k0.y, k1.y + 1):
			var key := Vector2i(x, z)
			if _buckets.has(key):
				result.append_array(_buckets[key])
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
		if not prop.dead and Vector2(prop.global_position.x - center.x, prop.global_position.z - center.z).length() < r + prop.footprint:
			result.append(prop)
	return result
