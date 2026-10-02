class_name FireZone
extends Node3D
## A patch of burning ground left by dragon's breath. Burns enemies and fungus inside it.
## A carpet of flame tongues, taller toward the middle, burns over a hot glowing patch of ground
## that flares up when lit, pulses, cools as the zone ages and dies down before the scorch mark.

const MAX_ZONES := 40
const RADIUS := 3.5
const DAMAGE_PER_SECOND := 20.0
const LIFE := 6.0
const RAMP_IN := 0.35 ## Seconds to flare up after ignition.
const DIE_DOWN := 1.5 ## Seconds over which it sinks before it goes out.
const TONGUES_PER_SECOND := 28.0 ## At full heat and full budget.
const SMOKE_PER_SECOND := 2.0
const EMBERS_PER_SECOND := 3.0
const CROWD_ZONES := 20.0 ## With more zones than this each one throws less, so forty stay in budget.
const FAR := Vector2(50.0, 130.0) ## Distances from the camera over which a zone thins out to a third.

static var _zones: Array[FireZone] = []

var life := LIFE
var weapon := "collateral"
var _age := 0.0
var _tick := 0.0
var _phase := randf() * TAU
var _tongues := 0.0
var _smoke := 0.0
var _embers := 0.0
var _rim := MeshInstance3D.new()
var _core := MeshInstance3D.new()


static func ignite(point: Vector3, cause := "collateral") -> void:
	for zone in _zones:
		if is_instance_valid(zone) and zone.global_position.distance_to(point) < RADIUS:
			zone.life = maxf(zone.life, LIFE)
			return
	var zone := FireZone.new()
	zone.weapon = cause
	World.current.add_child(zone)
	zone.global_position = point
	_zones.append(zone)
	if _zones.size() > MAX_ZONES:
		var oldest: FireZone = _zones.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


## Dragon's breath sets the ground alight wherever a flame lands.
static func on_flame_impact(_projectile: Projectile, point: Vector3, target: Entity) -> void:
	if target == null:
		ignite(point, "cannon")


static func _patch(b: LowPoly, color: Color) -> void:
	var sides := 9
	for i in sides:
		var r0 := 0.85 + 0.15 * sin(i * 2.7)
		var r1 := 0.85 + 0.15 * sin((i + 1) % sides * 2.7)
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		b.tri(Vector3.ZERO, Vector3(cos(a0) * r0, 0, sin(a0) * r0), Vector3(cos(a1) * r1, 0, sin(a1) * r1), color, Vector3.UP)


func _ready() -> void:
	var fx := World.current.fx
	for layer in [[_rim, "fire_ground_rim", Palette.HOSTILE_SHOT_RIM, 0.06], [_core, "fire_ground_core", Palette.AMBER, 0.1]]:
		var glow: MeshInstance3D = layer[0]
		glow.mesh = Fx._cached(layer[1], layer[2], func(b: LowPoly, c: Color) -> void: _patch(b, c))
		glow.material_override = Fx._glow_material
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.position.y = layer[3] + 0.25 # Above the smooth ground by more than the terrain mesh strays from it.
		add_child(glow)
	_glow(0.0)
	# The breath sets it off with a burst of tongues and a flash.
	for i in 10:
		_tongue(fx, 1.0)
	fx.light_flash(global_position, 4.0, Palette.AMBER, 10.0)


func _exit_tree() -> void:
	_zones.erase(self)


## How hot it burns, 0 to 1: it flares up in the first moments, cools as it ages and dies down over
## the last seconds.
func heat() -> float:
	return smoothstep(0.0, RAMP_IN, _age) * smoothstep(0.0, DIE_DOWN, life) * lerpf(0.65, 1.0, clampf(life / LIFE, 0.0, 1.0))


## How brightly the ground glows under the flames: the heat, pulsing.
func ground_glow() -> float:
	return heat() * (0.85 + 0.15 * sin(_age * 9.0 + _phase))


## The share of the full flame rate this zone gets: less with many zones alight, less far from the camera.
func _budget() -> float:
	var camera := World.current.camera
	var distance := camera.global_position.distance_to(global_position)
	return clampf(CROWD_ZONES / _zones.size(), 0.35, 1.0) * lerpf(1.0, 0.35, smoothstep(FAR.x, FAR.y, distance))


func _glow(level: float) -> void:
	# The rim fades out first as it cools and the core last, so the hot patch shrinks to its middle.
	_rim.set_instance_shader_parameter("instance_alpha", level * 0.7)
	_core.set_instance_shader_parameter("instance_alpha", level * level * 0.9)
	_rim.scale = Vector3(1, 1, 1) * RADIUS * (0.7 + 0.3 * level)
	_core.scale = Vector3(1, 1, 1) * RADIUS * 0.5 * (0.7 + 0.3 * level)
	_rim.visible = level > 0.02


func _tongue(fx: Fx, heat_now: float) -> void:
	var angle := randf() * TAU
	var reach := RADIUS * 0.9 * sqrt(randf())
	var height := lerpf(0.9, 3.0, pow(1.0 - reach / RADIUS, 1.5)) * (0.5 + 0.5 * heat_now) * randf_range(0.7, 1.2)
	var at := global_position + Vector3(cos(angle), 0.1, sin(angle)) * reach
	fx.tongue(at, height, 1.0 - reach / RADIUS, Vector3.ZERO)


func _process(delta: float) -> void:
	var world := World.current
	life -= delta
	if life <= 0.0:
		world.fx.scorch(global_position, RADIUS * 0.8)
		queue_free()
		return
	_age += delta
	_glow(ground_glow())
	var heat_now := heat()
	var rate := heat_now * _budget() * delta
	_tongues += TONGUES_PER_SECOND * rate
	_smoke += SMOKE_PER_SECOND * rate
	_embers += EMBERS_PER_SECOND * rate
	for i in mini(int(_tongues), 8):
		_tongue(world.fx, heat_now)
	_tongues = fmod(_tongues, 1.0)
	if _smoke >= 1.0:
		_smoke -= 1.0
		var spot := global_position + Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1)) * RADIUS * 0.4
		world.fx.smoke_puff(spot, 1.0 + heat_now * 0.6)
	if _embers >= 1.0:
		_embers -= 1.0
		world.fx.embers(global_position + Vector3.UP * 0.5, 1, RADIUS * 0.6)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.2
	for entity in world.enemies.duplicate():
		if not entity.flying and entity.global_position.distance_to(global_position) < RADIUS + entity.radius:
			var burn := Hit.make(Hit.Kind.FIRE, DAMAGE_PER_SECOND * 0.2, global_position)
			burn.incendiary = true
			burn.source = World.current.player
			burn.weapon = weapon
			entity.take_hit(burn)
	for prop: Prop in world.props.in_radius(global_position, RADIUS):
		if prop.burnable:
			prop.take_hit(Hit.make(Hit.Kind.FIRE, 10.0, global_position))
