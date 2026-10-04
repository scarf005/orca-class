extends TestCase
## Walkers and quad mechs roll on the wheels of their feet: the legs hold one stance while they move
## and only the wheels show the speed.

const BAND := 5.0 ## Degrees a joint may wander while rolling at a steady speed.


func _spawn(world: World, enemy: Enemy, ahead: float) -> Enemy:
	enemy.position = Course.ground_at(world.rail.d + ahead, 0.0)
	world.add_enemy(enemy)
	return enemy


## The joint angles (radians) of a walker's legs or a quad's, in a fixed order.
func _joints(enemy: Enemy) -> Array[float]:
	var angles: Array[float] = []
	for leg: Dictionary in enemy._legs:
		angles.append_array([leg.hip.rotation.x, leg.hip.rotation.z, leg.knee.rotation.x, leg.knee.rotation.z])
		if leg.has("ankle"):
			angles.append(leg.ankle.rotation.x)
	return angles


## Drives `enemy` for `count` frames and returns {band, spin, path, speed}: the widest range any joint
## went through (degrees), the wheels' total turn, and the ground covered.
func _roll(enemy: Enemy, count: int) -> Dictionary:
	var low := _joints(enemy)
	var high := low.duplicate()
	var spin := 0.0
	var path := 0.0
	var wheel := enemy._legs[0].wheel as Node3D
	var wheel_angle := wheel.rotation.x
	var last := enemy.global_position
	for i in count:
		await frames(1)
		var angles := _joints(enemy)
		for k in angles.size():
			low[k] = minf(low[k], angles[k])
			high[k] = maxf(high[k], angles[k])
		spin += absf(wheel.rotation.x - wheel_angle)
		wheel_angle = wheel.rotation.x
		path += enemy.global_position.distance_to(last)
		last = enemy.global_position
	var band := 0.0
	for k in low.size():
		band = maxf(band, rad_to_deg(high[k] - low[k]))
	return {"band": band, "spin": spin, "path": path}


func test_walker_holds_its_legs_while_the_wheels_turn_with_the_distance() -> void:
	var world := stage()
	var walker := _spawn(world, Walker.new(), 90.0) as Walker
	walker._attack_timer = 999.0
	await frames(30)
	var result := await _roll(walker, 90)
	check(result.path > 8.0, "the walker rolled (%.1f m)" % result.path)
	check(result.band < BAND, "its joints stay within %.0f deg (%.2f)" % [BAND, result.band])
	check_near(result.spin * Walker.WHEEL_RADIUS, result.path, result.path * 0.1, "the wheels turned once per wheel circumference travelled")


func test_quad_holds_its_legs_while_the_wheels_turn_with_the_distance() -> void:
	var world := stage()
	var quad := _spawn(world, QuadMech.new(), 110.0) as QuadMech
	quad._attack_timer = 999.0
	await frames(30)
	var result := await _roll(quad, 90)
	check(result.path > 8.0, "the quad rolled (%.1f m)" % result.path)
	check(result.band < BAND, "its joints stay within %.0f deg (%.2f)" % [BAND, result.band])
	check_near(result.spin * QuadMech.WHEEL_RADIUS, result.path, result.path * 0.1, "the wheels turned once per wheel circumference travelled")
	check_eq(quad._legs.filter(func(leg: Dictionary) -> bool: return leg.has("wheel")).size(), 4, "a wheel on each foot")


func test_a_walker_that_stands_still_does_not_spin_its_wheels() -> void:
	var world := stage()
	var walker := _spawn(world, Walker.new(), 90.0) as Walker
	walker.crippled = true
	await frames(5)
	var wheel := walker._legs[0].wheel as Node3D
	var angle := wheel.rotation.x
	await frames(30)
	check_near(wheel.rotation.x, angle, 0.001, "planted wheels stay put")


func test_walker_still_crouches_to_fire_and_rises_after() -> void:
	var world := stage()
	var walker := _spawn(world, Walker.new(), 60.0) as Walker
	walker._attack_timer = 999.0
	await frames(60)
	var rolling := _joints(walker)
	var height := walker._body.position.y
	walker._telegraph = 5.0
	await frames(40)
	var crouched := _joints(walker)
	check(rad_to_deg(rolling[0] - crouched[0]) > 8.0, "the hips fold for the telegraph (%.1f deg)" % rad_to_deg(rolling[0] - crouched[0]))
	check(rad_to_deg(crouched[2] - rolling[2]) > 15.0, "and the knees bend")
	check(walker._body.position.y < height - 0.1, "lowering the body")
	walker._telegraph = 0.0
	await frames(60)
	check_near(_joints(walker)[0], rolling[0], 0.05, "it rises again")


func test_crippled_walker_and_collapsed_quad_still_go_down() -> void:
	var world := stage()
	var walker := _spawn(world, Walker.new(), 60.0) as Walker
	walker.take_hit(Hit.make(Hit.Kind.SHELL, walker.legs_hp + 1.0, walker.global_position + Vector3.UP * 0.6))
	# Keep stage movement from ramming the stationary walker while its collapse animates.
	world.director.set_process(false)
	world.player.set_process(false)
	world.set_process(false)
	var quad := _spawn(world, QuadMech.new(), 70.0) as QuadMech
	for corner in [Vector2(-1, -1), Vector2(1, 1)]:
		var at: Vector3 = quad._body.global_transform * Vector3(corner.x * 1.8, -1.5, corner.y * 1.4)
		quad.take_hit(Hit.make(Hit.Kind.SHELL, QuadMech.LEG_HP + 1.0, at))
	await frames(120)
	check(walker.crippled and walker.model.rotation.z > 0.6, "the crippled walker slumps over (%.2f)" % walker.model.rotation.z)
	check(walker._body.position.y < 2.3, "and sinks (%.2f)" % walker._body.position.y)
	check(quad.collapsed() and quad._body.position.y < 1.2, "the collapsed quad drops its body (%.2f)" % quad._body.position.y)
	var lost := quad._legs.filter(func(leg: Dictionary) -> bool: return leg.lost)
	check(absf(lost[0].knee.rotation.z) > 0.8, "with its lost legs hanging limp")


func test_debug_room_poses_settle_without_ai() -> void:
	var world := stage()
	var walker := Walker.new()
	world.add_child(walker)
	walker.pose_idle()
	check(walker._body.position.y < 2.4, "the walker sits in its crouch")
	var quad := QuadMech.new()
	world.add_child(quad)
	quad.pose_idle()
	check_near(quad._body.position.y, 2.6, 0.2, "the quad stands on its stance")
