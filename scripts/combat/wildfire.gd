class_name Wildfire
## Brush that enemy flame burns down passes the fire to the brush around it: an ember ring marks each neighbour for
## DELAY seconds, then the ground there catches. The player's own fire never spreads.

const ENEMY_FIRE := ["flame", "fuel", "napalm", "shell"] ## Weapon tags of hostile FIRE hits.
const RADIUS := 9.0 ## How far from a burnt prop the fire looks for fuel.
const NEIGHBOURS := 2 ## Most props one burnt prop lights.
const DELAY := 1.2 ## Seconds between the warning ring and the fire.
const MAX_GENERATION := 6 ## Links a chain may run before it dies out.


## Marks the fuel around `prop`, which just burnt down to enemy flame.
static func spread(prop: Prop) -> void:
	var generation: int = prop.get_meta("burn_generation", 0)
	if generation >= MAX_GENERATION:
		return
	var world := World.current
	var fuel := world.props.in_radius(prop.global_position, RADIUS).filter(func(p: Prop) -> bool: return p != prop and p.burnable and not p.has_meta("burn_generation"))
	fuel.sort_custom(func(a: Prop, b: Prop) -> bool: return a.global_position.distance_squared_to(prop.global_position) < b.global_position.distance_squared_to(prop.global_position))
	for neighbour: Prop in fuel.slice(0, NEIGHBOURS):
		neighbour.set_meta("burn_generation", generation + 1)
		world.fx.marker(neighbour.global_position, FireZone.RADIUS, DELAY, Palette.AMBER)
		world.get_tree().create_timer(DELAY).timeout.connect(_ignite.bind(neighbour))


static func _ignite(prop) -> void: # Untyped: the prop may have been freed during the warning.
	if is_instance_valid(prop) and not prop.dead:
		FireZone.ignite(Vector3(prop.global_position.x, Course.height_at(prop.global_position), prop.global_position.z), "flame", true)
