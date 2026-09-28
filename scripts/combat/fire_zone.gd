class_name FireZone
extends Node3D
## A patch of burning ground left by dragon's breath. Burns enemies and fungus inside it.

const MAX_ZONES := 40
const RADIUS := 2.6
const DAMAGE_PER_SECOND := 14.0

static var _zones: Array[FireZone] = []

var life := 4.5
var _tick := 0.0


static func ignite(point: Vector3) -> void:
	for zone in _zones:
		if is_instance_valid(zone) and zone.global_position.distance_to(point) < RADIUS:
			zone.life = maxf(zone.life, 4.5)
			return
	var zone := FireZone.new()
	World.current.add_child(zone)
	zone.global_position = point
	_zones.append(zone)
	if _zones.size() > MAX_ZONES:
		var oldest: FireZone = _zones.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _exit_tree() -> void:
	_zones.erase(self)


func _process(delta: float) -> void:
	var world := World.current
	life -= delta
	if life <= 0.0:
		world.fx.scorch(global_position, RADIUS * 0.8)
		queue_free()
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.2
	for i in 2:
		var offset := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * RADIUS * 0.8
		world.fx.spawn(Fx.Kind.GLOW, global_position + offset, Vector3(0, randf_range(2, 5), 0), randf_range(0.3, 0.6), randf_range(0.4, 0.8), [Palette.FUNGUS, Palette.PEACH, Palette.BUTTER, Palette.CORAL][randi() % 4], {"drag": 1.0})
	for entity in world.enemies.duplicate():
		if not entity.flying and entity.global_position.distance_to(global_position) < RADIUS + entity.radius:
			var burn := Hit.make(Hit.Kind.FIRE, DAMAGE_PER_SECOND * 0.2, global_position)
			burn.incendiary = true
			burn.source = World.current.player
			entity.take_hit(burn)
	for prop: Prop in world.props.in_radius(global_position, RADIUS):
		if prop.burnable:
			prop.take_hit(Hit.make(Hit.Kind.FIRE, 10.0, global_position))
