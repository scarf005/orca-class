extends TestCase
## The flying wing and the borer centipede: turrets sniped from a drifted ramp leap, burrow and telegraphs.

const STEP := 1.0 / 60.0
const SHOT_WINDOW := 0.75 ## Seconds a drifted leap must keep a part in sight to lock and fire.


func _stage3() -> World:
	var world := stage("", false, 3)
	world.director._next_event = world.director.events.size()
	return world


## The wing over the run, the tank at 140 km/h a little short of ramp 0's foot, in its lane.
func _wing(shift := 0.0) -> Wing:
	var world := _stage3()
	var stage := Course.stage as Stage3
	world.rail.sprint = Stage3.SPRINT_KMH / 3.6
	world.rail.speed = world.rail.sprint
	world.rail.d = stage.hill_d(0) - 60.0 + shift
	world.player.course_u = stage.hill_side(0) * Stage3.HILL_U
	world.player.tick(STEP)
	var wing := Wing.new()
	world.add_enemy(wing)
	world.boss = wing
	return wing


## Opens turret `name` as if it had already fired its first volley.
func _open(wing: Wing, name: String) -> void:
	wing._active = name
	wing._open[name] = 1.0
	wing._armed[name] = true
	wing._cool = 1000.0


## Drives the tank up ramp 0 and off its lip, drifting across the track every `every` seconds (0: never), until
## it lands, firing at `part` when it comes into sight if `fire`. Returns [whether `part` came into sight in the air, slowest time scale seen, peak height over the lip,
## whether a main-gun round fired the moment it came into sight struck it rather than the hull, seconds it stayed in
## sight].
func _leap(wing: Wing, every: float, part := "flak", fire := true) -> Array:
	var world := World.current
	var tank := world.player
	var lip := (Course.stage as Stage3).hill_point(0, 1.0)
	var sight := false
	var slow := 1.0
	var peak := -INF
	var flew := false
	var side := 1.0
	var wait := 0.0
	var seen := 0.0
	for _i in ceili(12.0 / STEP):
		if every > 0.0 and not tank.airborne:
			wait -= STEP
			if wait <= 0.0:
				wait = every
				tank.dash(Vector2(side, 0))
				side = -side
		tank.tick(STEP)
		wing.behave(STEP)
		flew = flew or tank.airborne
		peak = maxf(peak, tank.global_position.y - lip.y)
		if fire and tank.airborne and wing.in_sight(part) and not sight:
			# A main-gun round fired down the line of sight the moment it opens.
			tank.fire_cannon(tank.hit_center(), wing._turret_world(part) - tank.hit_center(), 1.0)
		sight = sight or (tank.airborne and wing.in_sight(part))
		if tank.airborne and wing.in_sight(part):
			seen += STEP
		world._process(STEP)
		if world._hitstop <= 0.0:
			slow = minf(slow, Engine.time_scale / world.game_speed)
		if flew and not tank.airborne:
			break
	check(flew, "the tank leaves the lip")
	check(not tank.airborne, "and lands again")
	return [sight, slow, peak, wing.parts[part] < Wing.TURRET_HP, seen]


func _borer() -> Borer:
	var world := _stage3()
	world.rail.mode = Rail.Mode.HOLD
	var borer := Borer.new()
	borer.position = Course.to_world(Stage3.PIT_D, 0.0) + Vector3(30, 0, 0)
	world.add_enemy(borer)
	borer._bound()
	borer._next_attack = 1000.0
	world.player.global_position = Course.to_world(Stage3.PIT_D, 0.0)
	return borer


func _shell(source: Node3D, at: Vector3, rounds: float, model_round := Wing.ROUND_DAMAGE) -> Hit:
	var hit := Hit.make(Hit.Kind.SHELL, rounds * Armament.SHELL_DAMAGE / model_round, at, Vector3.FORWARD)
	hit.caliber = 100
	hit.source = source
	return hit


func _run(wing: Wing, seconds: float) -> void:
	for _i in ceili(seconds / STEP):
		wing.behave(STEP)


func test_closed_wing_turrets_cannot_be_shot() -> void:
	var wing := _wing()
	var before := wing.hp
	wing.take_hit(_shell(wing.player(), wing._turret_world("flak"), 100.0))
	check_eq(wing.hp, before, "a shell on a shut hatch only sparks the hull")
	check(wing.aim_parts().is_empty(), "no turret is a lock target while every hatch is shut")


func test_the_open_turret_is_out_of_the_roads_sight_over_the_ramps() -> void:
	var wing := _wing()
	_run(wing, 3.0)
	_open(wing, "flak")
	check(not wing.in_sight("flak"), "the belly skirts hide the turret from the tank on the road")
	var before := wing.hp
	wing.take_hit(_shell(wing.player(), wing._turret_world("flak"), 100.0))
	check_eq(wing.hp, before, "a shell from the road only sparks the hull")
	check(wing.aim_parts().is_empty(), "nothing to lock from the road")


func test_a_tank_drifting_up_a_ramp_leaps_into_the_open_turrets_sight_at_full_speed() -> void:
	var wing := _wing()
	_run(wing, 3.0)
	_open(wing, "flak")
	var result := _leap(wing, Tank.ANCHOR_COOLDOWN)
	check(result[0], "the drifted leap rises into the open turret's sight (peak %.1f m over the lip)" % result[2])
	# Long enough to lock and fire by hand at full speed.
	check(result[4] >= SHOT_WINDOW, "it holds the turret in sight for %.2f s" % result[4])
	check(result[3], "a round fired then reaches the turret, not the hull around its bay")
	check_eq(result[1], 1.0, "time never slows while the tank has the shot")


func test_a_tank_driving_straight_up_a_ramp_leaps_short_of_the_turrets_sight() -> void:
	var wing := _wing()
	_run(wing, 3.0)
	_open(wing, "flak")
	var result := _leap(wing, 0.0)
	check(not result[0], "an undrifted leap never sees past the skirts (peak %.1f m over the lip)" % result[2])
	check_eq(result[1], 1.0, "and time never slows")


func test_drifting_on_a_ramp_speeds_the_rail_and_holds_the_hull_on_the_track() -> void:
	var wing := _wing()
	var world := World.current
	var stage := Course.stage as Stage3
	world.rail.d = stage.hill_d(0) + 10.0
	world.player.tick(STEP)
	var cruise := world.rail.speed
	for direction: float in [1.0, -1.0, 1.0]:
		world.player.dash(Vector2(direction, 0))
		for _i in ceili(Tank.ANCHOR_COOLDOWN / STEP) + 1:
			world.player.tick(STEP)
			wing.behave(STEP)
			var c := Course.to_course(world.player.global_position)
			check(stage.ramp_at(c.x, c.y) >= 0.0 or c.x > stage.hill_d(0) + Stage3.HILL_LENGTH, "the hull stays on the track")
	check(world.rail.speed > cruise + Tank.RAMP_KICK, "three drifts sped the rail up (%.0f -> %.0f km/h)" % [cruise * 3.6, world.rail.speed * 3.6])


func test_past_the_last_ramp_the_wing_comes_down_into_the_roads_sight() -> void:
	var wing := _wing()
	var world := World.current
	world.rail.d = (Course.stage as Stage3).ramps_end() + 20.0
	world.player.course_u = 0.0
	world.player.tick(STEP)
	_run(wing, 4.0)
	_open(wing, "flak")
	check(wing.in_sight("flak"), "the low wing's open turret can be shot from the road")


func test_where_the_rail_stops_past_the_last_ramp_every_belly_turret_opens_into_the_roads_sight() -> void:
	for name: String in Wing.TURRETS:
		var wing := _wing()
		var world := World.current
		var stop := (Course.stage as Stage3).ramps_end() + 170.0
		world.rail.mode = Rail.Mode.HOLD
		world.rail.hold_at = stop
		world.rail.d = stop
		world.player.course_u = 0.0
		for other: String in Wing.TURRETS:
			wing.parts[other] = Wing.TURRET_HP if other == name else 0.0
		var exposed := 0.0
		for _i in ceili(20.0 / STEP):
			world.player.tick(STEP)
			wing.behave(STEP)
			exposed += STEP * float(wing._exposed().has(name))
		check(exposed >= 15.0, "the %s turret, the last one left, is open to the stopped tank's gun for %.1f s of 20" % [name, exposed])


func test_open_turret_in_sight_takes_round_damage_and_small_arms_glance() -> void:
	var wing := _wing()
	_open(wing, "flak")
	wing.player().global_position = wing._turret_world("flak") + Vector3(0, -5, 60)
	var bullet := Hit.make(Hit.Kind.BULLET, 30.0, wing._turret_world("flak"), Vector3.FORWARD)
	bullet.caliber = 12
	bullet.source = wing.player()
	wing.take_hit(bullet)
	check_eq(wing.parts.flak, Wing.TURRET_HP, "a 12 mm round cannot hurt the open turret")
	wing.take_hit(_shell(wing.player(), wing._turret_world("flak"), 60.0))
	check_near(wing.parts.flak, Wing.TURRET_HP - 60.0, 1.0, "a main-gun shell counts in rounds")
	check_near(wing.hp, Wing.TURRET_HP * wing.parts.size() - 60.0, 1.0, "the boss's health is the sum of its parts")
	check(wing.aim_parts().has("flak"), "the open turret is a lock target")


func test_an_opened_turret_cannot_be_shot_before_its_first_volley() -> void:
	var wing := _wing()
	var tank := wing.player()
	var hittable_before_fire := false
	var name := ""
	for _i in ceili(6.0 / STEP):
		wing.behave(STEP)
		if wing._active.is_empty():
			continue
		name = wing._active
		tank.global_position = wing._turret_world(name) + Vector3(0, -5, 60) # Level with it, as from a leap.
		if wing._open[name] >= 0.5 and not wing._armed.has(name):
			wing.take_hit(_shell(tank, wing._turret_world(name), 10.0))
			hittable_before_fire = hittable_before_fire or wing.parts[name] < Wing.TURRET_HP
		if wing._armed.has(name):
			break
	check(not hittable_before_fire, "the open turret shrugs off shells until it has fired")
	check(wing._armed.has(name), "it opens and fires on its own")
	wing.take_hit(_shell(tank, wing._turret_world(name), 10.0))
	check(wing.parts[name] < Wing.TURRET_HP, "once it has fired it can be shot")


func test_the_next_turret_opens_only_when_the_open_one_is_shot_out() -> void:
	var wing := _wing()
	_run(wing, 2.0)
	var first := wing._active
	_run(wing, 10.0)
	check_eq(wing._active, first, "the same turret stays open while it lives")
	wing._armed[first] = true
	wing.player().global_position = wing._turret_world(first) + Vector3(0, -5, 60)
	wing.take_hit(_shell(wing.player(), wing._turret_world(first), Wing.TURRET_HP + 1.0))
	_run(wing, 1.0)
	check(not wing._active.is_empty() and wing._active != first, "the next one opens")
	var open := Wing.TURRETS.filter(func(n: String) -> bool: return wing._open[n] >= 0.5)
	check_eq(open.size(), 1, "exactly one turret stands open")


## Shoots out every belly turret, each from level with it as from a leap.
func _strip_belly(wing: Wing) -> void:
	for name: String in Wing.TURRETS:
		_open(wing, name)
		wing.player().global_position = wing._turret_world(name) + Vector3(0, -5, 60)
		wing.take_hit(_shell(wing.player(), wing._turret_world(name), Wing.TURRET_HP + 1.0))
	wing.player().tick(STEP)


func test_a_bare_belly_keeps_the_wing_up_and_makes_the_ramps_throw_higher() -> void:
	var wing := _wing()
	_strip_belly(wing)
	_run(wing, 1.0)
	check(wing.hp > 0.0 and not wing.dead and wing._state == Wing.State.CRUISE, "the wing flies on with its back intact")
	check_eq(wing.player().ramp_lift, Wing.BARE_LIFT, "the ramps now throw the tank higher")
	check(not wing.in_sight("spine"), "the back is out of the road's sight")
	check(wing.aim_parts().is_empty(), "nothing to lock from the road")


func test_after_the_belly_a_drifted_leap_tops_out_over_the_wings_back_at_full_speed() -> void:
	var wing := _wing()
	_strip_belly(wing)
	_run(wing, 3.0)
	var result := _leap(wing, Tank.ANCHOR_COOLDOWN, "spine")
	check(result[0], "the higher leap rises over the wing's back (peak %.1f m over the lip)" % result[2])
	check(result[4] >= SHOT_WINDOW, "it holds the rack in sight for %.2f s" % result[4])
	check(result[3], "a round fired then reaches the rack, not the hull around it")
	check_eq(result[1], 1.0, "time never slows while the tank has the shot")


func test_with_the_belly_intact_a_drifted_leap_stays_under_the_wings_back() -> void:
	var wing := _wing()
	_run(wing, 3.0)
	var result := _leap(wing, Tank.ANCHOR_COOLDOWN, "spine")
	check(not result[0], "the ordinary leap never sees the back (peak %.1f m over the lip)" % result[2])


func test_the_back_is_hit_only_once_the_belly_is_bare_and_its_loss_brings_the_wing_down() -> void:
	var wing := _wing()
	var tank := wing.player()
	tank.global_position = wing._turret_world("spine") + Vector3(0, 25, 60)
	wing.take_hit(_shell(tank, wing._turret_world("spine"), 100.0))
	check_eq(wing.parts.spine, Wing.TURRET_HP, "the back shrugs off shells while a belly turret lives")
	_strip_belly(wing)
	for name: String in Wing.UPPER:
		tank.global_position = wing._turret_world(name) + Vector3(0, 25, 60)
		check(wing.aim_parts().has(name), "%s is a lock target from above" % name)
		wing.take_hit(_shell(tank, wing._turret_world(name), Wing.TURRET_HP + 1.0))
	check(wing.hp <= 0.0, "belly and back gone empties the hull")
	_run(wing, 6.0)
	check(wing.dead, "the wing crashes and dies")
	check_eq(tank.ramp_lift, 1.0, "the ramps throw as before once it is down")


func test_each_engine_trails_its_nozzles_until_it_is_shot_out() -> void:
	var wing := _wing()
	_strip_belly(wing)
	var tank := wing.player()
	tank.global_position = wing._turret_world("engine_l") + Vector3(0, 25, 60)
	wing.take_hit(_shell(tank, wing._turret_world("engine_l"), Wing.TURRET_HP + 1.0))
	check_eq(wing.parts.engine_l, 0.0, "the left engine is shot out")
	_run(wing, 0.5)
	for name: String in ["engine_l", "engine_r"]:
		check_eq(wing._exhausts[name].size(), Wing.NOZZLES.size(), name + " trails one ribbon per nozzle")
		for trail: FlyerTrail in wing._exhausts[name]:
			trail._process(STEP)
			var head := trail._points[trail._live][0]
			if name == "engine_r":
				check(Vector3(head.x, head.y, head.z).distance_to(trail.source.global_position) < 0.01, "a live engine's trail starts at its nozzle")
			else:
				check(not trail._following(), "a shot-out engine's trail no longer follows its falling wreck")


func test_past_the_last_ramp_a_bare_wing_rears_its_back_into_the_roads_sight() -> void:
	var wing := _wing()
	_strip_belly(wing)
	var world := World.current
	world.rail.d = (Course.stage as Stage3).ramps_end() + 20.0
	world.player.course_u = 0.0
	world.player.tick(STEP)
	_run(wing, 4.0)
	check(wing.in_sight("spine"), "the low wing rears its back toward the tank on the road")


func test_wing_fires_at_the_tank_from_its_open_turret() -> void:
	var wing := _wing()
	var world := World.current
	var before := world.projectiles.size()
	_run(wing, 5.0)
	check(world.projectiles.size() > before or wing._shots > 0, "the opened turret has shot at the chasing tank")


## Runs one volley (4 s, before the next is called) from turret `name` at the tank sprinting down the road's
## centre short of the ramps, the tank drifting aside once at the first telegraph if `dodge`. Returns the hull lost.
func _volley(name: String, dodge: bool) -> float:
	var wing := _wing()
	var world := World.current
	var tank := world.player
	world.rail.d = Stage3.HILL_FIRST - 350.0
	tank.course_u = 0.0
	for _i in ceili(1.0 / STEP):
		tank.tick(STEP)
	wing.global_position = wing._station(wing.age)
	_open(wing, name)
	wing._end_volley(0.3)
	var before := tank.hp
	var dodged := false
	for _i in ceili(4.0 / STEP):
		if dodge and not dodged and (wing.telegraphing() or wing._shots > 0):
			dodged = true
			tank.dash(Vector2(1, 0))
		tank.tick(STEP)
		wing.behave(STEP)
		world._process(STEP)
	check(dodged or not dodge, "the %s volley showed its telegraph" % name)
	return before - tank.hp


func test_wing_volleys_land_on_a_tank_holding_its_line_at_full_sprint() -> void:
	for name: String in ["rocket", "beam", "bomb"]:
		check(_volley(name, false) > 0.0, "the %s volley hits a tank that keeps straight on" % name)


func test_a_tank_drifting_aside_at_the_telegraph_escapes_the_rockets_and_the_beam() -> void:
	for name: String in ["rocket", "beam"]:
		check_eq(_volley(name, true), 0.0, "a drift at the %s telegraph clears it" % name)


func test_wing_volleys_called_mid_leap_meet_the_tank_in_the_air_or_on_its_landing() -> void:
	for name: String in ["rocket", "beam", "bomb"]:
		# The bombs leave a gap in the lane picked by the tank's world x; a start a metre on moves it off the tank's own.
		for shift in [0.0, 1.0]:
			var wing := _wing(shift)
			var world := World.current
			var tank := world.player
			wing.global_position = wing._station(wing.age)
			_open(wing, name)
			var before := tank.hp
			var called := false
			var over := false
			var side := 1.0
			for _i in ceili(12.0 / STEP):
				if not tank.airborne and not called and tank.anchor_cooldown <= 0.0:
					tank.dash(Vector2(side, 0))
					side = -side
				if tank.airborne and not called:
					called = true
					wing._end_volley(0.01)
				tank.tick(STEP)
				wing.behave(STEP)
				world._process(STEP)
				over = over or (called and wing._cool > 1.0)
				if over and (world.projectiles.is_empty() or wing.telegraphing()):
					break # This volley has come down, or the next is being called.
			check(called, "the tank leapt and the %s volley was called in the air" % name)
			if tank.hp < before or name != "bomb" or int(wing._aim.x) % 5 != 2:
				check(tank.hp < before, "the %s volley reaches the leaping tank" % name)
				break


func test_borer_burrowed_is_untouchable() -> void:
	var borer := _borer()
	borer._burrowed = true
	var before := borer.hp
	borer.take_hit(_shell(borer.player(), borer.hit_center(), 100.0, Borer.ROUND_DAMAGE))
	check_eq(borer.hp, before, "no damage under the sand")
	check_eq(borer.hit_test(borer.hit_center() + Vector3.BACK * 5, borer.hit_center(), 0.0), -1.0, "shots pass through the burrowed borer")
	check(borer.aim_parts().is_empty(), "nothing to lock while it is under the sand")


func test_borer_pod_and_cutter_break_and_small_arms_glance() -> void:
	var borer := _borer()
	var bullet := Hit.make(Hit.Kind.BULLET, 30.0, borer._pod_world("pod_1"), Vector3.FORWARD)
	bullet.caliber = 12
	bullet.source = borer.player()
	borer.take_hit(bullet)
	check_eq(borer.parts.pod_1, Borer.POD_HP, "machine-gun fire glances off the pod")
	borer.take_hit(_shell(borer.player(), borer._pod_world("pod_1"), Borer.POD_HP + 1.0, Borer.ROUND_DAMAGE))
	check_eq(borer.parts.pod_1, 0.0, "a shell bursts the pod")
	borer.take_hit(_shell(borer.player(), borer._cutter.global_position, Borer.CUTTER_HP + 1.0, Borer.ROUND_DAMAGE))
	check_eq(borer.parts.cutter, 0.0, "a shell breaks the cutterhead")


func test_borer_strips_its_plates_at_half_hull() -> void:
	var borer := _borer()
	borer.hp = borer.max_hp * 0.5 + 1.0
	borer.take_hit(_shell(borer.player(), borer.hit_center() + Vector3.UP, 20.0, Borer.ROUND_DAMAGE))
	check_eq(borer.phase, Borer.Phase.STRIPPED, "half hull switches the phase")
	check(borer.move_speed() > Borer.SPEED, "the stripped borer is faster")


func test_bore_charge_is_telegraphed_before_it_moves() -> void:
	var borer := _borer()
	borer.global_position = Course.to_world(Stage3.PIT_D, -50.0)
	var tank := borer.player()
	borer._begin_attack(Borer.Attack.BORE)
	var start := borer.global_position
	check(borer.telegraphing(), "the charge winds up")
	for _i in ceili(0.5 / STEP):
		borer.behave(STEP)
	check(borer.global_position.distance_to(start) < 6.0, "it does not move during the wind-up")
	for _i in ceili(1.0 / STEP):
		borer.behave(STEP)
	check(borer.global_position.distance_to(start) > 20.0, "after the wind-up it charges across the pit")
	check_eq(tank.hp, tank.max_hp, "the tank, away from the line, is unharmed")


func test_burrow_erupts_under_a_marker_and_hurts_a_tank_standing_there() -> void:
	var borer := _borer()
	var tank := borer.player()
	borer._begin_attack(Borer.Attack.BURROW)
	var before := tank.hp
	var burrowed := false
	for _i in ceili(6.0 / STEP):
		borer.behave(STEP)
		burrowed = burrowed or borer._burrowed
		tank.global_position = borer._aim if borer._burrowed else tank.global_position
		if borer._attack == Borer.Attack.ERUPT:
			break
	check(burrowed, "the borer dives")
	check_eq(borer._attack, Borer.Attack.ERUPT, "it comes back up")
	check(not borer._burrowed and borer._exposed > 0.0, "the head is out and exposed afterwards")
	check(tank.hp < before, "a tank left on the marker is hit by the eruption")


func test_rail_camera_leans_toward_the_wing_ahead() -> void:
	var wing := _wing()
	var world := World.current
	# Swung wide across the road from the tank and low enough that the view need not tilt up for it.
	var d := world.rail.d + Wing.STATION
	wing.global_position = Course.ground_at(d, -world.player.course_u * 2.0) + Vector3.UP * Wing.LOW_ALTITUDE
	var toward := func() -> float:
		world.camera.snap()
		world.camera.follow(STEP)
		var to_wing := (wing.global_position - world.camera.global_position).normalized()
		return rad_to_deg((-world.camera.global_basis.z).angle_to(to_wing))
	var framed: float = toward.call()
	wing.remove_meta("frame")
	var plain: float = toward.call()
	check(framed < plain - 2.0, "the view turns toward the wing (%.0f vs %.0f degrees off)" % [framed, plain])
	check(framed < 45.0, "the wing sits inside the frame (%.0f degrees off centre)" % framed)
	var size := world.camera.get_viewport().get_visible_rect().size
	var unframed := world.camera.unproject_position(world.player.hit_center()) / size
	wing.set_meta("frame", 0.22)
	toward.call()
	var tank := world.camera.unproject_position(world.player.hit_center()) / size
	check(tank.x > 0.25 and tank.x < 0.75, "the tank stays between the bottom-corner panels (x %.2f)" % tank.x)
	check_near(tank.y, unframed.y, 0.03, "leaning toward the wing keeps the tank's height on screen")


func test_rail_camera_tilts_up_to_keep_the_high_wing_in_frame() -> void:
	var wing := _wing()
	var world := World.current
	_run(wing, 3.0)
	world.camera.snap()
	world.camera.follow(STEP)
	var size := world.camera.get_viewport().get_visible_rect().size
	var seen := world.camera.unproject_position(wing.global_position) / size
	var tank := world.camera.unproject_position(world.player.hit_center()) / size
	check(seen.y > 0.12, "the wing's hull clears the top edge (y %.2f)" % seen.y)
	check(tank.y < 0.85, "the tank stays above the bottom panels (y %.2f)" % tank.y)


func test_a_player_shell_aimed_at_the_open_turret_breaks_it_not_the_hull() -> void:
	var wing := _wing()
	var world := World.current
	_open(wing, "flak")
	var turret := wing._turret_world("flak")
	# From behind and a little below, the way the leaping tank sees it: the line crosses the hull outline first.
	var from := turret + Vector3(0, -5, 40)
	world.player.global_position = from
	var to := turret + (turret - from).normalized() * 6.0
	var shot := world.spawn_projectile(Entity.Team.PLAYER, from, (to - from).normalized() * 600.0, "shell", Palette.BUTTER)
	shot.hit = _shell(world.player, from, 60.0)
	shot._sweep(from, to)
	check_near(wing.parts.flak, Wing.TURRET_HP - 60.0, 1.0, "the shell reaches the turret")


func test_a_borer_crawling_between_the_chase_camera_and_the_tank_turns_see_through() -> void:
	var borer := _borer()
	var world := World.current
	var camera := world.camera
	camera.snap()
	camera.follow(STEP)
	var target := world.player.hit_center()
	var seg: Node3D = borer._segments[2]
	seg.global_position = camera.global_position.lerp(target, 0.5) - Vector3.UP * 1.5
	check(borer.hit_test(camera.global_position, target) >= 0.0, "a body segment sits on the sight line to the tank")
	camera._fade_occluders(target)
	var faded := seg.find_children("*", "MeshInstance3D", true, false).all(func(mesh: MeshInstance3D) -> bool: return mesh.material_override != null)
	check(faded, "the segment over the line to the tank is drawn see-through")
	seg.global_position += Vector3.RIGHT * 60.0
	borer.global_position += Vector3.RIGHT * 60.0
	camera._fade_occluders(target)
	var restored := seg.find_children("*", "MeshInstance3D", true, false).all(func(mesh: MeshInstance3D) -> bool: return mesh.material_override == null)
	check(restored, "clear of the line, it is solid again")
