extends TestCase
## The sand kite flying wing and the borer centipede: exposed turrets, route up the ramps, burrow and telegraphs.

const STEP := 1.0 / 60.0


func _stage3() -> World:
	var world := stage("", false, 3)
	world.director._next_event = world.director.events.size()
	return world


func _wing() -> Wing:
	var world := _stage3()
	var wing := Wing.new()
	world.add_enemy(wing)
	wing.global_position = wing._ramp_point(0, 0.0)
	return wing


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


func test_open_turret_takes_round_damage_and_small_arms_glance() -> void:
	var wing := _wing()
	wing._active = 0
	wing._open.flak = 1.0
	var bullet := Hit.make(Hit.Kind.BULLET, 30.0, wing._turret_world("flak"), Vector3.FORWARD)
	bullet.caliber = 12
	bullet.source = wing.player()
	wing.take_hit(bullet)
	check_eq(wing.parts.flak, Wing.TURRET_HP, "a 12 mm round cannot hurt the open turret")
	wing.take_hit(_shell(wing.player(), wing._turret_world("flak"), 60.0))
	check_near(wing.parts.flak, Wing.TURRET_HP - 60.0, 1.0, "a main-gun shell counts in rounds")
	check_near(wing.hp, Wing.TURRET_HP * 5.0 - 60.0, 1.0, "the boss's health is the sum of its turrets")
	check(wing.aim_parts().has("flak"), "the open turret is a lock target")


func test_losing_every_turret_brings_the_wing_down() -> void:
	var wing := _wing()
	for name: String in Wing.TURRETS:
		wing._active = Wing.TURRETS.find(name)
		wing._open[name] = 1.0
		wing.take_hit(_shell(wing.player(), wing._turret_world(name), Wing.TURRET_HP + 1.0))
	check(wing.hp <= 0.0, "all five turrets gone empties the hull")
	_run(wing, 6.0)
	check(wing.dead, "the wing crashes and dies after its turrets are shot out")


func test_wing_drifts_up_a_ramp_then_lands_on_the_opposite_side() -> void:
	var wing := _wing()
	var stage := Course.stage as Stage3
	var seen_flight := false
	var peak := 0.0
	for _i in ceili(30.0 / STEP):
		wing.behave(STEP)
		if wing._state == Wing.State.FLIGHT:
			seen_flight = true
			peak = maxf(peak, wing.global_position.y)
		if wing._ramp == 1 and wing._state == Wing.State.DRIFT:
			break
	check(seen_flight, "the wing leaves the first lip")
	var lip := stage.hill_point(0, 1.0)
	check(peak > lip.y, "it arcs above the lip (%.1f > %.1f)" % [peak, lip.y])
	check_eq(wing._ramp, 1, "it lands on the next ramp")
	var u := Course.to_course(wing.global_position).y
	check(u * stage.hill_side(0) < 0.0, "the landing is on the opposite side of the road (u=%.0f)" % u)
	check(wing.global_position.distance_to(stage.hill_point(1, 0.0)) < 6.0, "it touches down at the foot of the next ramp")


func test_one_turret_opens_per_flight_and_shuts_on_landing() -> void:
	var wing := _wing()
	wing._s = Stage3.HILL_LENGTH
	wing.behave(STEP)
	check_eq(wing._state, Wing.State.FLIGHT, "the lip launches it")
	check(wing._active >= 0, "a turret is selected for the flight")
	_run(wing, 1.5)
	var open := Wing.TURRETS.filter(func(n: String) -> bool: return wing._open[n] >= 0.5)
	check_eq(open.size(), 1, "exactly one turret stands open")
	_run(wing, Wing.FLIGHT_TIME)
	check_eq(wing._state, Wing.State.DRIFT, "it lands")
	check_eq(wing._active, -1, "the hatch is shut on landing")


func test_wing_fires_at_the_tank_from_its_open_turret() -> void:
	var wing := _wing()
	wing.player().global_position = wing.global_position + Vector3(0, -12, 60)
	wing._s = Stage3.HILL_LENGTH
	wing._active = -1
	wing.behave(STEP)
	var world := World.current
	var before := world.projectiles.size()
	_run(wing, 5.0)
	check(world.projectiles.size() > before or wing._shots > 0, "the opened turret has shot at the chasing tank")


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
