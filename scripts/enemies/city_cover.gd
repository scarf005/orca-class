class_name CityCover
extends RefCounted
## City hunters share the world's live prop collision and roof heights.


static func blocker(from: Vector3, to: Vector3) -> Prop:
	var nearest: Prop
	var best := INF
	for node in World.current.props.get_children():
		var prop := node as Prop
		if prop == null or prop.dead:
			continue
		var t := prop.hit_test(from, to)
		if t >= 0.0 and t < best:
			best = t
			nearest = prop
	return nearest


static func shelter(at: Vector3, threat: Vector3) -> Vector3:
	var spot := at
	var best := 45.0
	for node in World.current.props.get_children():
		var prop := node as Prop
		if prop == null or prop.dead or prop.height < 8.0:
			continue
		var away := prop.global_position - threat
		away.y = 0.0
		var candidate := prop.global_position + away.normalized() * (prop.footprint + 5.0)
		candidate.y = Course.height_at(candidate) + 7.0
		var distance := at.distance_to(candidate)
		if distance < best and blocker(candidate, threat) != null:
			best = distance
			spot = candidate
	return spot


static func surface_at(at: Vector3) -> float:
	var height := Course.height_at(at)
	for node in World.current.props.get_children():
		var prop := node as Prop
		if prop == null or prop.dead:
			continue
		if prop.kind not in Prop.BUILDINGS and not prop.hard:
			continue
		var local := prop.to_local(at)
		if Vector2(local.x, local.z).length() <= prop.footprint:
			height = maxf(height, prop.global_position.y + prop.height)
	return height
