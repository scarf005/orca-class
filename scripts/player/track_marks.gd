class_name TrackMarks
extends MultiMeshInstance3D
## Tread prints pressed into the ground behind both tracks. A ring buffer of flat, dark tread
## plates: the oldest are reused as new ones are laid, so the trail stretches a few hundred meters.

const COUNT := 1600
const SPACING := 0.8 ## Meters of travel between prints; each print is a bit longer.
const TRACK_OFFSET := 1.55 ## Half the distance between the tracks.

var _next := 0
var _last := Vector3.INF


func _init() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plate := LowPoly.new()
	# One stretch of tread print: churned mud a little longer than the spacing, so prints join into
	# a continuous track, with dark cleat grooves across it.
	plate.quad(Vector3(-0.36, 0, -0.48), Vector3(0.36, 0, -0.48), Vector3(0.36, 0, 0.48), Vector3(-0.36, 0, 0.48), Palette.WOOD, Vector3.UP)
	for z in [-0.3, 0.0, 0.3]:
		plate.quad(Vector3(-0.36, 0.01, z - 0.06), Vector3(0.36, 0.01, z - 0.06), Vector3(0.36, 0.01, z + 0.06), Vector3(-0.36, 0.01, z + 0.06), Palette.INK, Vector3.UP)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = plate.mesh()
	multimesh.instance_count = COUNT
	multimesh.visible_instance_count = 0


## Lays prints under both tracks for however far the hull moved since the last call.
func press(hull: Transform3D, airborne := false) -> void:
	var at := hull.origin
	if _last == Vector3.INF or airborne:
		_last = at
		return
	var travelled := at.distance_to(_last)
	if travelled < SPACING:
		return
	if travelled > 12.0:
		_last = at # Teleported (respawn): no smear across the gap.
		return
	var yaw := Basis(Vector3.UP, atan2(-hull.basis.z.x, -hull.basis.z.z))
	# Fill the whole stretch covered since the last call, so fast frames leave no gaps.
	var steps := int(travelled / SPACING)
	for k in range(1, steps + 1):
		var along := _last.lerp(at, float(k) / steps)
		for side in [-1.0, 1.0]:
			var p: Vector3 = along + hull.basis.x * side * TRACK_OFFSET
			p.y = Course.height_at(p) + 0.06
			multimesh.set_instance_transform(_next, Transform3D(yaw, p))
			_next = (_next + 1) % COUNT
			multimesh.visible_instance_count = mini(multimesh.visible_instance_count + 1, COUNT)
	_last = at


func count() -> int:
	return multimesh.visible_instance_count
