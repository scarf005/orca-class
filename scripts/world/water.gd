class_name Water
extends RefCounted
## Every body of water in one query: the stage's own water (Stage 1's reservoir), the dam's lake
## behind the wall and the flood after it breaks. Effects and units ask here instead of assuming
## one water level.


## The height of the water surface at `p`'s x and z, or -INF when there is no water there.
static func surface_at(p: Vector3) -> float:
	var dam := Dam.current
	if dam != null:
		var surface := dam.surface_at(p)
		if surface > -INF:
			return surface
	return Course.stage.water_surface(Course.to_course(p))
