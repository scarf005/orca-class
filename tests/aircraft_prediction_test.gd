extends TestCase
## Aircraft predict observed ground motion without moving an already announced attack.

const DT := 1.0 / 60.0


func _world_at(d: float, u := 0.0) -> World:
	var world := stage("", false)
	world.set_process(false)
	world.player.set_process(false)
	world.director.events.clear()
	world.rail.d = d
	world.player.course_u = u
	world.player._place(d)
	world.player._last_position = world.player.global_position
	return world


func _heli(world: World) -> Helicopter:
	var heli := Helicopter.new()
	heli.position = Course.ground_at(world.rail.d + world.player.course_offset + 55.0, 0.0) + Vector3.UP * 13.0
	world.add_enemy(heli)
	heli.set_process(false)
	heli._attack_timer = INF
	return heli


func _rotor(world: World) -> Tiltrotor:
	var rotor := Tiltrotor.new()
	world.add_enemy(rotor)
	rotor.set_process(false)
	rotor.global_position = Course.ground_at(world.rail.d + world.player.course_offset + 36.0, 16.0) + Vector3.UP * 10.0
	rotor.state = Tiltrotor.State.HOVER
	rotor._tilt = 1.0
	rotor._ramp = 1.0
	rotor._dropped = true
	rotor._hover = Tiltrotor.SWEEP_AT + DT
	return rotor


func _step(world: World, enemy: Enemy) -> void:
	world.player.tick(DT)
	enemy.tick(DT)
	for shot: Projectile in world.projectiles.duplicate():
		if not shot.is_queued_for_deletion():
			shot.step(DT)


func test_helicopter_drift_lead_does_not_extrapolate_terrain_rise_into_the_air() -> void:
	var world := _world_at(800.0, 12.0)
	var tank := world.player
	var heli := _heli(world)
	tank.dash(Vector2.RIGHT)
	for frame in 8:
		tank.tick(DT)
	check(tank.velocity.y > 10.0, "production drift changes terrain footprint height, not sustained altitude")
	var aim := heli._aim_point(tank)
	var offset := tank.model.sensor_position("fcs").y - tank.global_position.y
	# Terrain footprint may differ from centre height by up to its local relief, not metres of flight.
	check(absf(aim.y - Course.height_at(aim) - offset) < 1.0, "the lead remains at sensor height over predicted terrain")


func test_tiltrotor_warning_predicts_dash_deceleration_instead_of_a_mountain_lane() -> void:
	for difficulty in [Game.Difficulty.EASY, Game.Difficulty.NORMAL, Game.Difficulty.HARD]:
		for side in [-1.0, 1.0]:
			Game.difficulty = difficulty
			var world := _world_at(100.0)
			var tank := world.player
			tank.dash(Vector2(side, 0.0))
			tank.tick(DT)
			var rotor := _rotor(world)
			rotor.behave(DT)
			var a := rotor._line_a
			var b := rotor._line_b
			var predicted := Course.to_course((a + b) * 0.5).y
			for frame in int(ceil((Tiltrotor.SWEEP_WIND * Game.telegraph_scale() + Tiltrotor.SWEEP_TIME) / DT)):
				tank.tick(DT)
			# A transverse line must cover the no-new-input dash endpoint: its half-width is the contract.
			check(absf(predicted - tank.course_u) < Tiltrotor.SWEEP_HALF, "the committed line covers the observed dash, not the valley wall")
			check(rotor._line_a == a and rotor._line_b == b, "player movement does not move the committed warning")
			cleanup()


func test_tiltrotor_sweep_hits_a_vulnerable_tank_that_stays_in_its_announced_path() -> void:
	var world := _world_at(100.0)
	var tank := world.player
	tank.dash(Vector2.RIGHT)
	tank.tick(DT)
	var rotor := _rotor(world)
	var hp := tank.hp
	var modules := tank.modules.hp.duplicate()
	for frame in 240:
		_step(world, rotor)
	check(tank.hp < hp or tank.modules.hp != modules, "the actual sweep rounds affect the tank after its dash invulnerability ends")
