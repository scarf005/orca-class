extends TestCase
## Tread prints turn wine-dark and wide over fungus patches, and the tracks fling juice there.


## The start (d, u) of an 8 m stretch of ground, both tracks' width, that is fungus all along, or has none.
func _stretch(fungus: bool) -> Vector2:
	for d in range(100, 3300, 2):
		for u in range(-40, 41, 2):
			var whole := true
			for k in 5:
				for lateral in [-1.8, 0.0, 1.8]:
					var f := Course.fungus_at(d + k * 2.0, u + lateral)
					var height := Course.height(d + k * 2.0, u + lateral)
					if fungus and (f < 0.6 or height < Course.WATER_LEVEL + 1.0) or not fungus and f > 0.2:
						whole = false
			if whole:
				return Vector2(d, u)
	return Vector2(-1, -1)


func _hull(start: Vector2, along: float) -> Transform3D:
	var here := Course.ground_at(start.x + along, start.y)
	var ahead := Course.ground_at(start.x + along + 1.0, start.y)
	return Transform3D(Basis.looking_at(ahead - here, Vector3.UP), here)


## Drives a fresh set of prints along the stretch, `passes` steps of a meter, back and forth.
func _drive(world: World, start: Vector2, passes: int) -> TrackMarks:
	var marks := TrackMarks.new()
	world.add_child(marks)
	marks.press(_hull(start, 0.0), 0.016)
	for i in passes:
		marks.press(_hull(start, 1.0 + (i % 2)), 0.016)
	return marks


func test_prints_over_fungus_are_crushed_and_over_plain_ground_mud() -> void:
	var world := stage()
	var fungus := _stretch(true)
	var plain := _stretch(false)
	check(fungus.x >= 0.0 and plain.x >= 0.0, "the course has both a fungus stretch and a plain one")
	var crushed := _drive(world, fungus, 4)
	var mud := _drive(world, plain, 4)
	check(crushed.count() >= 4 and mud.count() >= 4, "both laid prints")
	check_eq(crushed.crushed_prints, crushed.count(), "every print over fungus is crushed")
	check_eq(mud.crushed_prints, 0, "no print on plain ground is")
	check(TrackMarks.CRUSHED != TrackMarks.MUD and TrackMarks.CRUSHED.v < TrackMarks.MUD.v, "crushed is the darker of the two")
	check(TrackMarks.CRUSHED_WIDTH > 1.0, "and wider")
	check(crushed.multimesh.use_colors, "each print carries its own color")


func test_fungus_splashes_and_squelches_are_rate_limited_and_absent_on_plain_ground() -> void:
	var world := stage()
	seed(5)
	var particles := world.fx.particle_count()
	var mud := _drive(world, _stretch(false), 400)
	check_eq(mud.squelches, 0, "no squelch on plain ground")
	check_eq(world.fx.particle_count(), particles, "and no splashes")
	var crushed := _drive(world, _stretch(true), 400)
	check(world.fx.particle_count() > particles + 20, "juice and spores fly over fungus (%d)" % (world.fx.particle_count() - particles))
	var seconds := 400 * 0.016
	check(crushed.squelches >= 3, "it squelches now and then (%d)" % crushed.squelches)
	check(crushed.squelches <= int(seconds / TrackMarks.SQUELCH_INTERVAL) + 1, "but no more often than every %.2f s (%d in %.1f s)" % [TrackMarks.SQUELCH_INTERVAL, crushed.squelches, seconds])
	var prints := crushed.count()
	check(prints >= 400, "many prints were laid (%d)" % prints)
	check(float(crushed.squelches) / prints < 0.05, "squelches are a small fraction of the prints")
