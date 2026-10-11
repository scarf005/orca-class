extends TestCase
## Each training station past the maze holds the tank until the skill it shows has been used, through the
## production tank, hits and free-drive water.

const DT := 1.0 / 60.0

var course: Tutorial


func practice() -> Tutorial:
	course = Tutorial.new()
	add_child(course)
	return course


func cleanup(restore_environment := false) -> void:
	get_tree().paused = false
	if is_instance_valid(course):
		course.queue_free()
	for action in Game.REBINDABLE:
		Input.action_release(action)
	super.cleanup(restore_environment)


func place(u: float, d: float) -> void:
	var at := Course.ground_at(d, u)
	course.tank._set_pose(at, 0.0)
	course.tank._last_position = at
	course.tank.course_u = u
	course.tank.local_velocity = Vector2.ZERO


func at() -> Vector2:
	var c := Course.to_course(course.tank.global_position)
	return Vector2(c.y, c.x)


## Holds `action` for `seconds` of the tank's own 60 Hz tick.
func hold(action: String, seconds: float) -> void:
	Input.action_press(action)
	for _i in roundi(seconds * 60.0):
		course.tank.tick(DT)
	Input.action_release(action)


func coax(target: Entity) -> void:
	var hit := Hit.make(Hit.Kind.BULLET, 12.0, target.hit_center())
	hit.caliber = Armament.COAX_TIERS[-1][0]
	target.take_hit(hit)


## A real main-gun round from above the tank at `target`, flown on the world's projectile step until it lands.
func cannon(target: Entity, power: float) -> void:
	var from := target.hit_center() + Vector3(0, 3, 14)
	course.tank.fire_cannon(from, target.hit_center() - from, power)
	for _i in 60:
		for projectile in course.world.projectiles.duplicate():
			if is_instance_valid(projectile) and not projectile.is_queued_for_deletion():
				projectile.step(DT)


## Holds the key for `heading` (as (u, d)) for `seconds`, the camera settled on the tank's island first.
func push(heading: Vector2, seconds: float) -> void:
	for _i in 120:
		course.world.camera.follow(DT)
	var camera_heading: Vector2 = course.world.camera.heading
	var side := camera_heading.x * heading.y - camera_heading.y * heading.x
	hold("move_forward" if heading.dot(camera_heading) > 0.7 else "move_back" if heading.dot(camera_heading) < -0.7 else "move_left" if side > 0.0 else "move_right", seconds)


func test_the_range_gap_holds_the_tank_until_paper_and_steel_targets_fall_to_their_weapons() -> void:
	practice()
	place(-12, Tutorial.BRIDGE.position.y - 4)
	push(Tutorial.NORTH, 2.0)
	check(at().y < Tutorial.BRIDGE.position.y + 1, "the gap stops the tank (d=%.1f)" % at().y)
	var paper := course.targets.filter(func(target: Training.Target) -> bool: return not target.steel)
	var steel := course.targets.filter(func(target: Training.Target) -> bool: return target.steel)
	check(not paper.is_empty() and not steel.is_empty(), "the range has paper (%d) and steel (%d) targets" % [paper.size(), steel.size()])
	var gone := func(target: Variant) -> bool: return not is_instance_valid(target) or target.dead
	for target: Training.Target in course.targets:
		coax(target)
	check(paper.all(gone), "the coax tears every paper target")
	check(steel.all(func(target: Entity) -> bool: return not target.dead and target.hp == target.max_hp), "and ricochets off steel for nothing")
	check(not course.bridge_up, "no bridge while steel stands")
	for target: Variant in steel:
		await frames(2) # Targets shot earlier are freed by now, as in play.
		if not gone.call(target):
			cannon(target, 0.0)
	check(steel.all(gone), "a main-gun shell drops steel")
	check(course.bridge_up, "the last target raises the bridge")
	place(-12, Tutorial.BRIDGE.position.y - 4)
	push(Tutorial.NORTH, 1.5)
	check(at().y > Tutorial.BRIDGE.end.y, "and the tank drives over it (d=%.1f)" % at().y)
	place(-5, Tutorial.BRIDGE.position.y - 4)
	push(Tutorial.NORTH, 1.5)
	check(at().y < Tutorial.BRIDGE.position.y + 1, "beside the bridge the gap still holds it (d=%.1f)" % at().y)


func test_the_pillbox_turns_everything_but_a_full_charge() -> void:
	practice()
	var pillbox := course.pillbox
	place(4, Tutorial.PILLBOX.y)
	push(Tutorial.EAST, 2.0)
	check(not pillbox.dead, "a ram does not crush it")
	check(at().x < Tutorial.PILLBOX.x - pillbox.radius, "and the tank stops in front of it (u=%.1f)" % at().x)
	check(pillbox in course.world.enemies, "it is an enemy, so a held charge can lock onto it")
	var camera := course.world.camera
	course.tank.aim_screen = camera.unproject_position(pillbox.hit_center()) * Vector2(DitherView.RESOLUTION) / Vector2(course.view.viewport.size)
	check_eq(course.tank._nearest_lockable()[0], pillbox, "with the reticle on it, the lock picks it")
	coax(pillbox)
	cannon(pillbox, 0.0)
	cannon(pillbox, Armament.STAGE_2)
	check(not pillbox.dead and pillbox.hp == pillbox.max_hp, "coax, a quick shell and a two-box charge leave it whole")
	cannon(pillbox, 1.0)
	check(pillbox.dead, "a full charge breaks it")
	place(4, Tutorial.PILLBOX.y)
	push(Tutorial.EAST, 1.5)
	check(at().x > Tutorial.PILLBOX.x + 6.0, "and the causeway is open (u=%.1f)" % at().x)


func test_the_drawbridge_stays_up_until_the_drone_is_shot_down() -> void:
	practice()
	cannon(course.pillbox, 1.0)
	check(await wait_until(func() -> bool: return not is_instance_valid(course.pillbox), 1200), "the pillbox, broken earlier as in play, is freed by now")
	var x := Tutorial.DRAWBRIDGE.get_center().x
	place(x, Tutorial.DRAWBRIDGE.position.y - 4)
	push(Tutorial.NORTH, 2.0)
	check(at().y < Tutorial.DRAWBRIDGE.position.y + 1, "the raised drawbridge leaves a gap in the way (d=%.1f)" % at().y)
	coax(course.drone)
	check(course.drone.hp == course.drone.max_hp and not course.drawbridge_down, "the coax glances off the drone's plating")
	cannon(course.drone, 1.0)
	check(course.drone.dead and course.drawbridge_down, "a shell drops the drone and the drawbridge comes down")
	place(x, Tutorial.DRAWBRIDGE.position.y - 4)
	push(Tutorial.NORTH, 1.5)
	check(at().y > Tutorial.DRAWBRIDGE.end.y, "and the tank crosses (d=%.1f)" % at().y)


func test_every_bridge_takes_a_tank_that_drives_up_off_its_centre() -> void:
	practice()
	course.bridge_up = true
	course.heal_bridge_up = true
	course.swarm_bridge_up = true
	cannon(course.drone, 1.0)
	for bridge: Rect2 in [Tutorial.BRIDGE, Tutorial.DRAWBRIDGE, Tutorial.HEAL_BRIDGE, Tutorial.SWARM_BRIDGE]:
		for off: float in [-4.0, 4.0]:
			place(bridge.get_center().x + off, bridge.position.y - 5)
			push(Tutorial.NORTH, 2.0)
			check(at().y > bridge.end.y, "a tank %+.0f m off the bridge at u=%.0f crosses it (d=%.1f)" % [off, bridge.get_center().x, at().y])


func test_the_drone_flies_beside_the_drawbridge_not_behind_it() -> void:
	practice()
	var seen := -INF
	for _i in 600:
		course.drone.tick(DT)
		var c := Course.to_course(course.drone.global_position)
		seen = maxf(seen, -absf(c.y - Tutorial.DRAWBRIDGE.get_center().x) + Tutorial.DRAWBRIDGE.size.x * 0.5)
	check(seen < 0.0, "ten seconds of jinking never cross over the drawbridge (closest %.1f m beside it)" % -seen)


func test_the_broken_road_is_crossed_only_by_a_dash() -> void:
	practice()
	var south: Rect2 = Tutorial.ISLANDS[8][0]
	var north: Rect2 = Tutorial.ISLANDS[9][0]
	place(south.position.x + 4, south.get_center().y)
	push(Tutorial.WEST, 1.5)
	check(at().x > south.position.x, "the broken road ends at a drop (u=%.1f)" % at().x)
	push(Tutorial.NORTH, 2.0)
	check(at().y < south.end.y, "driving right stops at the break (d=%.1f)" % at().y)
	course.tank.dash(Vector2.RIGHT)
	for _i in 60:
		course.tank.tick(DT)
	check(at().y > north.position.y, "a dash carries the tank over it (d=%.1f)" % at().y)
	push(Tutorial.WEST, 1.5)
	check(at().x < south.position.x, "and the way on leads past the break (u=%.1f)" % at().x)


## Waits on frames, the tank standing still, until the turret's next wall is within `distance` of the hull along the run.
func wall_within(distance: float) -> bool:
	return await wait_until(func() -> bool: return course._shots.any(func(wall: Node3D) -> bool: return is_instance_valid(wall) and not wall.has_meta("past") and absf(Course.to_course(wall.global_position).x - at().y) < distance), 600)


func test_a_paint_wall_sends_a_standing_tank_back_and_a_dash_takes_it_through() -> void:
	practice()
	var start := Vector2(Tutorial.TURRET.x, Tutorial.TURRET_RUN.y - 10)
	place(start.x, start.y)
	check(await wall_within(40.0), "the turret pushes a wall down the run at a tank on it")
	var sent_back := await wait_until(func() -> bool: return at().y < start.y - 5.0, 600)
	check(sent_back, "a wall that reaches a standing tank splashes it back down the run (d=%.1f)" % at().y)
	place(start.x - 5.0, start.y)
	course._turret_clock = 0.0
	check(await wall_within(Tutorial.SHOT_HIT + 2.5), "the next wall comes in")
	course.tank.dash(Vector2.RIGHT)
	await frames(90)
	check(at().y > start.y - 1.0, "a dash as it arrives takes the tank through untouched (d=%.1f)" % at().y)
	check(at().x > start.x, "and lands on the run beside where it started (u=%.1f)" % at().x)
	cannon(course.turret, 1.0)
	check(not course.turret.dead, "nothing breaks the armoured turret")


func test_a_broken_tv_rises_again_painted() -> void:
	practice()
	var entry: Dictionary = course._signs[1]
	var tv: Prop = entry.prop
	var first := tv.get_instance_id()
	tv.take_hit(Hit.make(Hit.Kind.RAM, 99999.0, tv.global_position))
	check(tv.dead, "a TV breaks like any scenery")
	await wait_until(func() -> bool: return is_instance_valid(entry.prop) and entry.prop.get_instance_id() != first and not entry.prop.dead, roundi(60 * (Tutorial.RESPAWN + 1.0)))
	var back: bool = is_instance_valid(entry.prop) and entry.prop.get_instance_id() != first
	check(back, "a new one stands within RESPAWN")
	if not back:
		return
	await frames(40)
	check_eq(entry.screen.glyphs.size(), Tutorial.SKILL_ACTIONS[entry.skill].size(), "showing the keys of its skill")
	check_near(entry.prop.global_position.y, Course.ground_at(entry.at.y, entry.at.x).y, 0.05, "risen back onto its island")


func test_every_skill_has_a_tv() -> void:
	practice()
	var skills := course._signs.filter(func(entry: Dictionary) -> bool: return entry.kind == "tv").map(func(entry: Dictionary) -> String: return entry.skill)
	for skill: String in Tutorial.SKILL_ACTIONS:
		check(skill in skills, "a TV demonstrates %s" % skill)


## No station's targets lie in another station's line of fire: from where each is attacked, shooting at it
## points away from every other gate.
func test_no_station_is_in_another_stations_line_of_fire() -> void:
	practice()
	var stations := [
		["range", Vector2(-12, -426), Vector2(-12, Tutorial.TARGET_D)],
		["pillbox", Vector2(4, Tutorial.PILLBOX.y), Tutorial.PILLBOX],
		["drone", Vector2(42, -370), Vector2(Tutorial.DRONE.x, Tutorial.DRONE.z)],
	]
	for i in stations.size():
		var from: Vector2 = stations[i][1]
		var direction: Vector2 = (stations[i][2] - from).normalized()
		for j in stations.size():
			if j == i:
				continue
			var gate: Vector2 = stations[j][2]
			var along := (gate - from).dot(direction)
			var off := absf((gate - from).cross(direction))
			check(along < 0.0 or off > 12.0, "%s fire passes %.1f m from the %s" % [stations[i][0], off, stations[j][0]])


## Holds `action` while the game runs on its own frames, so the course's stations see every step.
func roll(action: String, seconds: float) -> void:
	Input.action_press(action)
	await frames(roundi(seconds * 60.0))
	Input.action_release(action)


func test_thorns_cost_armour_and_only_melee_kills_heal_it_back_to_raise_the_bridge() -> void:
	practice()
	place(Tutorial.THORNS.get_center().x, Tutorial.THORNS.position.y - 4.0)
	await roll("move_forward", 0.5)
	check_near(course.tank.hp, course.tank.max_hp - Tutorial.THORN_DAMAGE, 0.01, "pushing through the thorns costs THORN_DAMAGE armour")
	await frames(120)
	check(course._scarecrows.size() >= 2, "unarmed scarecrows wander the pen (%d)" % course._scarecrows.size())
	var shot: Entity = course._scarecrows[0]
	cannon(shot, 0.0)
	await frames(90)
	check(not is_instance_valid(shot) or shot.dead, "a shell drops a scarecrow")
	check_near(course.tank.hp, course.tank.max_hp - Tutorial.THORN_DAMAGE, 0.01, "but a shot one gives nothing back")
	check(not course.heal_bridge_up, "and the bridge stays down short of full armour")
	for attempt in 12:
		if course.tank.hp >= course.tank.max_hp:
			break
		await wait_until(func() -> bool: return course._scarecrows.size() > 0, 120)
		var scarecrow: Entity = course._scarecrows[0]
		var at := Course.to_course(scarecrow.global_position)
		place(at.y, at.x - 6.0)
		await roll("move_forward", 0.5)
		await frames(90)
	check_near(course.tank.hp, course.tank.max_hp, 0.01, "ramming scarecrows heals the armour back to full")
	await frames(2)
	check(course.heal_bridge_up, "and full armour raises the bridge")
	place(Tutorial.HEAL_BRIDGE.get_center().x, Tutorial.HEAL_BRIDGE.position.y - 3.0)
	await roll("move_forward", 1.0)
	check(at().y > Tutorial.HEAL_BRIDGE.end.y, "which carries the tank to the goal (d=%.1f)" % at().y)


func test_the_swarm_regroups_after_single_kills_and_falls_only_all_at_once() -> void:
	practice()
	await frames(2)
	var first: Entity = course.swarm[0]
	first.take_hit(Hit.make(Hit.Kind.BLAST, 99999.0, first.hit_center()))
	check(not first.dead, "a blast does not drop a swarm drone")
	coax(first)
	check(first.hp == first.max_hp, "nor does the coax")
	first.take_hit(Hit.make(Hit.Kind.SHELL, 99999.0, first.hit_center()))
	check(first.dead, "a direct hit drops one")
	await frames(roundi(60 * (Tutorial.REGROUP + 0.5)))
	check(course.swarm[0] != null and is_instance_valid(course.swarm[0]) and course.swarm[0] != first, "and another takes its place after REGROUP")
	check(not course.swarm_bridge_up, "the bridge stays down")
	var armoury: Rect2 = Tutorial.ISLANDS[12][0]
	place(armoury.get_center().x, armoury.get_center().y)
	await wait_until(func() -> bool: return course.tank.current_round == Armament.Round.MICRO, 240)
	check_eq(course.tank.current_round, Armament.Round.MICRO, "on the armoury a crate of micro-missiles comes to the tank")
	for drone_in: Entity in course.swarm.duplicate():
		drone_in.take_hit(Hit.make(Hit.Kind.SHELL, 99999.0, drone_in.hit_center()))
	check(course.swarm_bridge_up, "all four down at once raise the bridge")
	place(Tutorial.SWARM_BRIDGE.get_center().x, Tutorial.SWARM_BRIDGE.position.y - 3.0)
	await roll("move_forward", 1.0)
	check(course.step == Tutorial.Step.DONE, "and the tank drives over it to the goal (d=%.1f)" % at().y)
