extends TestCase
## Walkers and quad mechs roll on the wheels of their feet: the legs hold one stance while they move,
## each foot reaching the ground under it, and only the wheels show the speed.

const BAND := 0.12 ## Metres a wheel may lift off or sink into the eased ground under it while rolling: the legs do not correct the small lean of the body into acceleration.
const BUMP := 0.4 ## Metres the ground is raised under some feet.


## A walker on a perfectly flat floor at its own height, so only the crouch moves its joints.
class FlatWalker extends Walker:
	func ground_under(_at: Vector3) -> float:
		return global_position.y


## A walker whose right foot always finds ground BUMP higher than the course.
class BumpWalker extends Walker:
	func ground_under(at: Vector3) -> float:
		return super(at) + (BUMP if model.to_local(at).x > 0.0 else 0.0)


## A quad whose front right foot always finds ground BUMP higher than the course.
class BumpQuad extends QuadMech:
	func ground_under(at: Vector3) -> float:
		var local := model.to_local(at)
		return super(at) + (BUMP if local.x > 0.0 and local.z < 0.0 else 0.0)


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


## How high each wheel centre rides above the ground under it, or above the ground its foot eases onto.
func _clearances(enemy: Enemy, eased := false) -> Array[float]:
	var heights: Array[float] = []
	for leg: Dictionary in enemy._legs:
		var wheel: Node3D = leg.wheel
		heights.append(wheel.global_position.y - (leg.ground as float if eased else enemy.ground_under(wheel.global_position)))
	return heights


## Drives `enemy` for `count` frames and returns {band, touching, spin, path}: the widest range any wheel's height
## above its eased ground went through (metres), the share of wheel-frames resting within BAND of the ground under the
## wheel, the wheels' total turn, and the ground covered.
func _roll(enemy: Enemy, count: int) -> Dictionary:
	var low := _clearances(enemy, true)
	var high := low.duplicate()
	var spin := 0.0
	var path := 0.0
	var off := 0
	var wheel := enemy._legs[0].wheel as Node3D
	var wheel_angle := wheel.rotation.x
	var last := enemy.global_position
	for i in count:
		await frames(1)
		var heights := _clearances(enemy, true)
		for h in _clearances(enemy):
			off += 1 if absf(h - enemy.WHEEL_RADIUS) > BAND else 0
		for k in heights.size():
			low[k] = minf(low[k], heights[k])
			high[k] = maxf(high[k], heights[k])
		spin += absf(wheel.rotation.x - wheel_angle)
		wheel_angle = wheel.rotation.x
		path += enemy.global_position.distance_to(last)
		last = enemy.global_position
	var band := 0.0
	for k in low.size():
		band = maxf(band, high[k] - low[k])
	return {"band": band, "touching": 1.0 - float(off) / (count * low.size()), "spin": spin, "path": path}


func test_walker_keeps_its_wheels_on_the_ground_and_turns_them_with_the_distance() -> void:
	var world := stage()
	var walker := _spawn(world, Walker.new(), 90.0) as Walker
	walker._attack_timer = 999.0
	await frames(30)
	var result := await _roll(walker, 90)
	check(result.path > 8.0, "the walker rolled (%.1f m)" % result.path)
	check(result.band < BAND, "its wheels hold steady over the ground they ease onto (%.3f m)" % result.band)
	check(result.touching > 0.9, "and roll on the ground under them (%.0f%% of frames)" % (result.touching * 100.0))
	check_near(result.spin * Walker.WHEEL_RADIUS, result.path, result.path * 0.1, "the wheels turned once per wheel circumference travelled")


func test_quad_keeps_its_wheels_on_the_ground_and_turns_them_with_the_distance() -> void:
	var world := stage()
	var quad := _spawn(world, QuadMech.new(), 110.0) as QuadMech
	quad._attack_timer = 999.0
	await frames(30)
	var result := await _roll(quad, 90)
	check(result.path > 8.0, "the quad rolled (%.1f m)" % result.path)
	check(result.band < BAND, "its wheels hold steady over the ground they ease onto (%.3f m)" % result.band)
	check(result.touching > 0.9, "and roll on the ground under them (%.0f%% of frames)" % (result.touching * 100.0))
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
	var walker := _spawn(world, FlatWalker.new(), 60.0) as Walker
	walker._attack_timer = 999.0
	walker._lane_timer = 999.0 # Holds its lane, so no sideways lean folds one leg.
	walker._lane = Course.to_course(walker.global_position).y
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
	check_near(walker._body.position.y, height, 0.05, "it rises again")


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
	for leg: Dictionary in quad._legs:
		var at := quad.model.to_local((leg.wheel as Node3D).global_position)
		check_near(Vector2(at.x, at.z).distance_to(Vector2(leg.foot.x, leg.foot.z)), 0.0, 0.05, "it reads the ground under each standing wheel")


func test_walker_feet_each_reach_the_ground_under_them() -> void:
	var world := stage()
	var walker := _spawn(world, BumpWalker.new(), 90.0) as Walker
	walker._attack_timer = 999.0
	walker.stagger = 999.0 # Held in place so the course under it stays put.
	await frames(60)
	var heights := _clearances(walker)
	check_near(heights[0], Walker.WHEEL_RADIUS, 0.05, "the left wheel stands on the street (%.2f m above it)" % heights[0])
	check_near(heights[1], heights[0], 0.08, "the right foot steps up onto the raised ground (%.2f vs %.2f m)" % [heights[1], heights[0]])
	check(walker._body.rotation.z > 0.02, "and the body rolls toward it (%.3f)" % walker._body.rotation.z)


func test_quad_feet_each_reach_the_ground_under_them() -> void:
	var world := stage()
	var quad := _spawn(world, BumpQuad.new(), 110.0) as QuadMech
	quad._attack_timer = 999.0
	quad.stagger = 999.0
	await frames(60)
	var heights := _clearances(quad)
	for i in heights.size():
		check_near(heights[i], QuadMech.WHEEL_RADIUS, 0.1, "wheel %d stands on the ground under it (%.2f m above it)" % [i, heights[i]])
