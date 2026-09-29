class_name Water
extends RefCounted
## Every body of water in one query: the reservoir along the road, the dam's lake behind the wall
## and the flood after it breaks. Effects and units ask here instead of assuming one water level.

const RESERVOIR_D := Vector2(1740.0, 2700.0) ## Along the road, as far as the reservoir's surface reaches.
const RESERVOIR_U := Vector2(-135.0, -8.0) ## Across it.


## The height of the water surface at `p`'s x and z, or -INF when there is no water there.
static func surface_at(p: Vector3) -> float:
	var dam := Dam.current
	if dam != null:
		var surface := dam.surface_at(p)
		if surface > -INF:
			return surface
	var c := Course.to_course(p)
	if c.x >= RESERVOIR_D.x and c.x <= RESERVOIR_D.y and c.y >= RESERVOIR_U.x and c.y <= RESERVOIR_U.y and Course.is_water(c.x, c.y):
		return Course.WATER_LEVEL
	return -INF
