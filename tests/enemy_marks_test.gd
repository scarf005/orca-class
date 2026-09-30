extends TestCase
## Enemy ground vehicles print into one shared world buffer: treads under UGVs, thin wheel lines
## under the mechs' feet.


func _spawn(world: World, enemy: Enemy, ahead: float) -> Enemy:
	enemy.position = Course.ground_at(world.rail.d + ahead, 0.0)
	world.add_enemy(enemy)
	return enemy


func test_a_moving_ugv_prints_its_tread_gauge_and_a_stationary_one_prints_nothing() -> void:
	var world := stage()
	var marks := world.enemy_marks
	var still := _spawn(world, Ugv.new(), 70.0) as Ugv
	still.immobile = true
	still.disarmed = true
	await frames(120)
	check_eq(marks.count(), 0, "a parked UGV lays no prints")
	still.queue_free()
	var mover := _spawn(world, Ugv.new(), 90.0) as Ugv
	mover.disarmed = true
	await frames(1)
	var path := 0.0
	var last := mover.global_position
	for i in 120:
		await frames(1)
		path += mover.global_position.distance_to(last)
		last = mover.global_position
	var expected := int(path / (TrackMarks.SPACING * 1.1)) * 2 # A frame's leftover stretch is not counted.
	check(path > 20.0, "the UGV drove (%.1f m)" % path)
	check(absi(marks.count() - expected) <= 8, "two prints per %.1f m along its %.1f m path: %d (expected about %d)" % [TrackMarks.SPACING, path, marks.count(), expected])
	check_eq(marks.count() % 2, 0, "in pairs, one under each track")
	check_near(mover.mark_offsets[1] - mover.mark_offsets[0], 1.9, 0.01, "the tracks are 1.9 m apart")
	check(mover.mark_offsets[1] - mover.mark_offsets[0] < TrackMarks.TRACK_OFFSET * 2.0, "narrower than the tank's gauge")
	check(mover.mark_width < 1.0, "and each print narrower")


func test_walker_and_quad_lay_thin_wheel_lines_into_the_same_buffer() -> void:
	var world := stage()
	var walker := _spawn(world, Walker.new(), 80.0) as Walker
	walker._attack_timer = 999.0
	await frames(90)
	var walker_prints := world.enemy_marks.count()
	check(walker_prints >= 10, "the walker's wheels leave lines (%d)" % walker_prints)
	check(walker.mark_width < 0.4 and walker.mark_offsets[1] < 1.0, "thin lines under the feet")
	var quad := _spawn(world, QuadMech.new(), 100.0) as QuadMech
	quad._attack_timer = 999.0
	await frames(120)
	check(quad.mark_width < 0.4, "thin quad lines")
	check(world.enemy_marks.count() > walker_prints, "the quad adds its wheel lines")
	var owners := 0
	for node in world.find_children("*", "TrackMarks", true, false):
		owners += 1
	check_eq(owners, 2, "the tank's buffer and one shared enemy buffer, however many enemies")


func test_no_prints_while_in_the_reservoir_or_dead() -> void:
	var world := stage()
	var marks := world.enemy_marks
	var ugv := _spawn(world, Ugv.new(), 60.0) as Ugv
	ugv.disarmed = true
	await frames(2)
	ugv._wet = true
	marks._last = Vector3.INF
	var before := marks.count()
	for i in 20:
		ugv._mark_last = ugv.global_position + Vector3(i * 2.0, 0, 0)
		ugv._leave_marks()
	check_eq(marks.count(), before, "a submerged vehicle prints nothing")
	ugv._wet = false
	ugv._mark_last = Vector3.INF
	ugv._leave_marks()
	ugv.global_position += Vector3(0, 0, -3.0)
	ugv._leave_marks()
	check(marks.count() > before, "it prints again on dry ground")
	var after := marks.count()
	ugv.take_hit(Hit.make(Hit.Kind.SHELL, 999.0, ugv.hit_center()))
	await frames(30)
	check_eq(marks.count(), after, "a dead vehicle prints nothing")


func test_the_shared_buffer_wraps_and_enemy_prints_over_fungus_are_quiet() -> void:
	var world := stage()
	var marks := world.enemy_marks
	var start := Course.ground_at(world.rail.d + 30.0, 0.0)
	var last := Vector3.INF
	var offsets: Array = [-1.0, 1.0]
	for i in TrackMarks.SHARED_COUNT:
		var hull := Transform3D(Basis(), start + Vector3(0, 0, -i * 1.0))
		last = marks.lay(last, hull, offsets, 1.0, false, false)
	check_eq(marks.count(), TrackMarks.SHARED_COUNT, "the buffer holds at its size once it wrapped")
	check_eq(marks.multimesh.instance_count, TrackMarks.SHARED_COUNT, "with room for that many prints")
	check(TrackMarks.SHARED_COUNT > TrackMarks.COUNT, "larger than the tank's own")
	var fungus := TrackMarks.new()
	world.add_child(fungus)
	var cell := Vector2(-1, -1)
	for d in range(100, 3300, 2):
		for u in range(-40, 41, 2):
			if Course.fungus_at(d, u) > 0.8 and Course.height(d, u) > Stage1.WATER_LEVEL + 1.0 and cell.x < 0.0:
				cell = Vector2(d, u)
	check(cell.x >= 0.0, "the course has a fungus patch")
	var particles := world.fx.particle_count()
	seed(3)
	var here := Course.ground_at(cell.x, cell.y)
	var mark_last := Vector3.INF
	for i in 300:
		mark_last = fungus.lay(mark_last, Transform3D(Basis(), here + Vector3(0, 0, -i * 0.9)), [0.0], 1.0, false, false)
	check(fungus.crushed_prints > 0, "some enemy prints crushed fungus")
	check_eq(fungus.squelches, 0, "without a squelch")
	check_eq(world.fx.particle_count(), particles, "or a splash")
