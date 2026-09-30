class_name OilSlick
extends Node3D
## A slick of oil leaking on the water. Fire lights it, and it burns across its whole surface, water
## and all, where any other ground fire would fizzle out.

const RADIUS := 9.0
const SPREAD_SPEED := 14.0 ## How fast the fire runs over the slick.
const BURN_TIME := 5.0 ## Seconds it keeps burning once the flames have covered it.
const ZONE_SPACING := 3.0 ## Fire zones are laid about this far apart along the flame front.

static var _slicks: Array[OilSlick] = []

var radius := RADIUS
var burning := false
var _origin := Vector3.ZERO
var _reach := 0.0
var _left := BURN_TIME


## The slick lying under `point`, if any.
static func at(point: Vector3) -> OilSlick:
	for slick in _slicks:
		if is_instance_valid(slick) and slick.contains(point):
			return slick
	return null


## Lights every slick within `reach` of a blast or flame at `point`.
static func light_near(point: Vector3, reach: float) -> void:
	for slick in _slicks:
		if is_instance_valid(slick) and not slick.burning and Vector2(slick.global_position.x - point.x, slick.global_position.z - point.z).length() < slick.radius + reach:
			slick.light(point)


static func _mesh(sides := 11) -> Mesh:
	var b := LowPoly.new()
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var r0 := 0.8 + 0.2 * sin(i * 2.3)
		var r1 := 0.8 + 0.2 * sin((i + 1) % sides * 2.3)
		var color := Palette.INK if i % 3 else Palette.MAUVE.darkened(0.5)
		b.tri(Vector3.ZERO, Vector3(cos(a0) * r0, 0, sin(a0) * r0), Vector3(cos(a1) * r1, 0, sin(a1) * r1), color, Vector3.UP)
	return b.mesh()


func _ready() -> void:
	var sheen := MeshInstance3D.new()
	sheen.mesh = _mesh()
	sheen.scale = Vector3(radius, 1.0, radius)
	sheen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sheen)


func _enter_tree() -> void:
	_slicks.append(self)


func _exit_tree() -> void:
	_slicks.erase(self)


func contains(point: Vector3) -> bool:
	return Vector2(global_position.x - point.x, global_position.z - point.z).length() < radius


func light(point: Vector3) -> void:
	if burning:
		return
	burning = true
	_origin = point
	Sfx.play("whoomp", point, 2.0, 0.8)


func _process(delta: float) -> void:
	if not burning:
		return
	var before := _reach
	_reach += SPREAD_SPEED * delta
	# Flames run outward from where it was lit, one ring of zones per few metres of front.
	var ring := floorf(_reach / ZONE_SPACING) * ZONE_SPACING
	if ring > floorf(before / ZONE_SPACING) * ZONE_SPACING:
		var count := maxi(int(TAU * ring / ZONE_SPACING), 1)
		var offset := randf() * TAU
		for i in count:
			var angle := offset + TAU * i / count
			var point := _origin + Vector3(cos(angle), 0.0, sin(angle)) * ring
			if contains(point):
				point.y = Water.surface_at(point)
				FireZone.ignite(point)
		if ring == 0.0:
			FireZone.ignite(Vector3(_origin.x, Water.surface_at(_origin), _origin.z))
	if _reach > radius * 2.0:
		_left -= delta
		if _left <= 0.0:
			queue_free()
