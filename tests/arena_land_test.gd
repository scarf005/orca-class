extends TestCase
## Arena land holds a free-driving hull on its rectangles; only a dash that clears a gap carries it over.

const DT := 1.0 / 60.0
## Two strips 5 m apart along d, so the hull-widened gap (9.6 m) is under a dash (13 m), and a strip beyond a
## 12 m gap ahead, wider than a dash once the hull is added (16.6 m).
const NEAR := Rect2(-30.0, -330.0, 27.5, 60.0)
const FAR := Rect2(2.5, -330.0, 27.5, 60.0)
const AHEAD := Rect2(-30.0, -258.0, 27.5, 30.0)
const LAND: Array[Rect2] = [NEAR, FAR, AHEAD]


func _arena(at: Vector2) -> World:
	var world := stage()
	world.rail.mode = Rail.Mode.ARENA
	world.rail.arena_d = at.y
	world.rail.arena_radius = 200.0
	world.rail.arena_land = LAND
	world.player.input_enabled = true
	world.player._set_pose(Course.ground_at(at.y, at.x), 0.0)
	world.player._last_position = world.player.global_position
	return world


func _drive(tank: Tank, action: String, seconds: float) -> void:
	Input.action_press(action)
	for _i in roundi(seconds * 60.0):
		tank.tick(DT)
	Input.action_release(action)


func _at(tank: Tank) -> Vector2:
	var c := Course.to_course(tank.global_position)
	return Vector2(c.y, c.x)


func test_driving_to_each_edge_stops_the_rim_on_it() -> void:
	var edge := Tank.HULL_RADIUS
	var cases := [
		["the gap's edge", "move_right", func(at: Vector2) -> float: return NEAR.end.x - edge - at.x],
		["the outer edge", "move_left", func(at: Vector2) -> float: return at.x - (NEAR.position.x + edge)],
		["the near end", "move_back", func(at: Vector2) -> float: return at.y - (NEAR.position.y + edge)],
		["the far end", "move_forward", func(at: Vector2) -> float: return NEAR.end.y - edge - at.y],
	]
	for item: Array in cases:
		var world := _arena(Vector2(-16.0, -300.0))
		_drive(world.player, item[1], 3.0)
		var gap: float = item[2].call(_at(world.player))
		check(gap >= -0.01, "%s: the rim never leaves the land (%.2f m over)" % [item[0], -gap])
		check(gap <= 0.6, "%s: and the hull rests at it (%.2f m short)" % [item[0], gap])


func test_the_hull_slides_along_an_edge_it_drives_into_at_an_angle() -> void:
	var world := _arena(Vector2(-6.0, -300.0))
	Input.action_press("move_right")
	_drive(world.player, "move_forward", 0.5)
	Input.action_release("move_right")
	check(_at(world.player).y > -300.0 + 8.0, "pushing into the edge while driving on still moves along it (d=%.2f)" % _at(world.player).y)


func test_plain_driving_cannot_cross_a_gap_a_dash_can() -> void:
	var world := _arena(Vector2(-9.0, -300.0))
	_drive(world.player, "move_right", 3.0)
	check(_at(world.player).x < NEAR.end.x, "three seconds of full right input stay on the near strip (u=%.2f)" % _at(world.player).x)
	world.player.dash(Vector2.RIGHT)
	var printed_over_gap := false
	for _i in 60:
		world.player.tick(DT)
		var u := _at(world.player).x
		printed_over_gap = printed_over_gap or (u > NEAR.end.x and u < FAR.position.x and not world.player._off_land())
	check(not printed_over_gap, "no tread prints are laid while the hull is over the gap")
	check(_at(world.player).x > FAR.position.x + Tank.HULL_RADIUS - 0.01, "a dash from the edge lands on the far strip (u=%.2f)" % _at(world.player).x)
	_drive(world.player, "move_left", 1.0)
	check(_at(world.player).x > FAR.position.x, "which then keeps it (u=%.2f)" % _at(world.player).x)


func test_a_dash_short_of_the_far_side_falls_under_gravity_then_puts_the_hull_back_where_it_started() -> void:
	# Eleven metres back from the edge, a forward dash (12 m) leaves it slow, too slow to clear the 12 m gap.
	var world := _arena(Vector2(-16.0, NEAR.end.y - 11.0))
	world.player.tick(DT)
	var start := _at(world.player)
	var ground := world.player.global_position.y
	world.player.dash(Vector2(0, 1))
	var left := -1 ## The frame the hull's centre passed the edge.
	var takeoff := Vector2.ZERO
	var speed := 0.0
	var lowest := INF
	for i in roundi(60 * (Tank.DASH_TIME + Tank.FALL_TIME)) + 10:
		var before := _at(world.player)
		world.player.tick(DT)
		var now := _at(world.player)
		if left < 0 and now.y > NEAR.end.y:
			left = i
			takeoff = now
			speed = (now.y - before.y) / DT
		if left >= 0 and i == left + 18:
			# Semi-implicit Euler at 60 Hz drops g·dt²·n(n+1)/2, 0.47 m after 18 frames against the exact 0.44 m.
			check_near(ground - world.player.global_position.y, 0.5 * Tank.FALL_GRAVITY * 0.3 * 0.3, 0.05, "0.3 s after leaving the edge the hull has dropped as under real gravity, no hanging")
			check(now.y - takeoff.y > speed * 0.3 * 0.95, "and kept the speed it left with (%.1f m in 0.3 s at %.1f m/s)" % [now.y - takeoff.y, speed])
		lowest = minf(lowest, world.player.global_position.y)
	check(left >= 0, "the dash carries the hull's centre past the edge")
	check(lowest < ground - 5.0, "the hull is seen falling below the far side (%.1f m down)" % (ground - lowest))
	check_near(world.player.global_position.y, ground, 0.05, "and stands on the land again")
	check(_at(world.player).distance_to(start) < 0.6, "where the dash started (%s vs %s)" % [_at(world.player), start])


func test_a_dash_that_lands_with_its_centre_on_the_land_is_nudged_on_not_dropped() -> void:
	var world := _arena(Vector2(-9.0, -300.0))
	_drive(world.player, "move_right", 2.0)
	world.player.dash(Vector2.RIGHT)
	world.player._drift = Tank.DASH_TIME * 0.55 # Cut short: it leaves the edge slow enough to land just past it, rim still over the gap.
	for _i in 60:
		world.player.tick(DT)
	check(_at(world.player).x >= FAR.position.x + Tank.HULL_RADIUS - 0.01, "the hull is nudged wholly onto the far strip (u=%.2f)" % _at(world.player).x)
	check(_at(world.player).x < FAR.position.x + Tank.HULL_RADIUS + 1.0, "right beside where it landed (u=%.2f)" % _at(world.player).x)


func test_no_land_leaves_free_driving_alone() -> void:
	var world := _arena(Vector2(0.0, -310.0))
	world.rail.arena_land = []
	_drive(world.player, "move_forward", 1.0)
	check(_at(world.player).y > -310.0 + Tank.ARENA_SPEED * 0.5, "driving is free (d=%.2f)" % _at(world.player).y)
