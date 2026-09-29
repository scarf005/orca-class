class_name TrackMarks
extends MultiMeshInstance3D
## Tread prints pressed into the ground behind both tracks. A ring buffer of flat, dark tread
## plates: the oldest are reused as new ones are laid, so the trail stretches a few hundred meters.
## Over fungus patches the prints are wider and wine-dark and the tracks fling juice and spores.
## The world keeps a second, larger buffer that every enemy ground vehicle prints into (`lay`).

const COUNT := 1600
const SHARED_COUNT := 3000 ## The enemies' shared buffer.
const SPACING := 0.8 ## Meters of travel between prints; each print is a bit longer.
const TRACK_OFFSET := 1.55 ## Half the distance between the tracks.
const MUD := Palette.WOOD
const CRUSHED := Color("613c52") ## Trampled fungus: wine-dark mauve.
const CRUSHED_WIDTH := 1.4
const FUNGUS_THRESHOLD := 0.5 ## Course.fungus_at above this is a fungus patch.
const SPLASH_CHANCE := 0.06 ## Per print over fungus.
const SQUELCH_INTERVAL := 0.45 ## Seconds between squelches.

var crushed_prints := 0 ## How many prints were laid over fungus.
var squelches := 0 ## How many squelches have played.
var count_max := COUNT
var _next := 0
var _last := Vector3.INF
var _squelch_wait := 0.0


func _init(capacity := COUNT) -> void:
	count_max = capacity
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plate := LowPoly.new()
	# One stretch of tread print: churned mud a little longer than the spacing, so prints join into
	# a continuous track, with dark cleat grooves across it.
	# The plate is white and takes its color from the instance: mud or crushed fungus.
	plate.quad(Vector3(-0.36, 0, -0.48), Vector3(0.36, 0, -0.48), Vector3(0.36, 0, 0.48), Vector3(-0.36, 0, 0.48), Palette.WHITE, Vector3.UP)
	for z in [-0.3, 0.0, 0.3]:
		plate.quad(Vector3(-0.36, 0.01, z - 0.06), Vector3(0.36, 0.01, z - 0.06), Vector3(0.36, 0.01, z + 0.06), Vector3(-0.36, 0.01, z + 0.06), Palette.DUSK, Vector3.UP)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = plate.mesh()
	multimesh.instance_count = capacity
	multimesh.visible_instance_count = 0


## Lays prints under both tracks for however far the hull moved since the last call.
func press(hull: Transform3D, delta: float, airborne := false) -> void:
	_squelch_wait = maxf(_squelch_wait - delta, 0.0)
	_last = lay(_last, hull, [-TRACK_OFFSET, TRACK_OFFSET], 1.0, airborne, true)


## Lays a line of prints at each lateral offset from `hull` (`width` scales the plate across) for the
## stretch from `last` to the hull, and returns where the next stretch starts: `last` itself until
## a full spacing was travelled. `Vector3.INF` starts a vehicle; `airborne` restarts it too.
## `loud` prints over fungus fling juice and squelch; enemies leave quiet prints.
func lay(last: Vector3, hull: Transform3D, offsets: Array, width: float, airborne: bool, loud: bool) -> Vector3:
	var at := hull.origin
	if last == Vector3.INF or airborne:
		return at
	var travelled := at.distance_to(last)
	if travelled < SPACING:
		return last
	if travelled > 12.0:
		return at # Teleported (respawn): no smear across the gap.
	# Prints lie along the path actually travelled (a sideways slide smears them sideways too).
	var moved := at - last
	var yaw := Basis(Vector3.UP, atan2(-moved.x, -moved.z))
	# Fill the whole stretch covered since the last call, so fast frames leave no gaps.
	var steps := int(travelled / SPACING)
	for k in range(1, steps + 1):
		var along := last.lerp(at, float(k) / steps)
		for offset: float in offsets:
			var p: Vector3 = along + hull.basis.x * offset
			# Above the smooth height by more than the terrain mesh strays from it between samples.
			p.y = Course.height_at(p) + 0.22
			var crushed := _over_fungus(p)
			crushed_prints += int(crushed)
			multimesh.set_instance_transform(_next, Transform3D(yaw.scaled_local(Vector3(width * (CRUSHED_WIDTH if crushed else 1.0), 1.0, 1.0)), p))
			multimesh.set_instance_color(_next, CRUSHED if crushed else MUD)
			if loud and crushed and randf() < SPLASH_CHANCE:
				_splash(p, -moved.normalized())
			_next = (_next + 1) % count_max
			multimesh.visible_instance_count = mini(multimesh.visible_instance_count + 1, count_max)
	return at


func _over_fungus(p: Vector3) -> bool:
	var course := Course.to_course(p)
	return Course.fungus_at(course.x, course.y) > FUNGUS_THRESHOLD and p.y > Course.WATER_LEVEL


## Juice and spores flung up behind the tracks, with a squelch no more often than every 0.45 s.
func _splash(at: Vector3, back: Vector3) -> void:
	World.current.fx.juice(at, back)
	if _squelch_wait <= 0.0:
		_squelch_wait = SQUELCH_INTERVAL
		squelches += 1
		Sfx.play("squelch", at, -6.0, randf_range(0.8, 1.3))


func count() -> int:
	return multimesh.visible_instance_count
