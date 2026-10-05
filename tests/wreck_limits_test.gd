extends TestCase


func test_shell_killed_body_and_parts_disappear_at_one_second() -> void:
	Fx.PARTICLE_LIFE = 1.0
	Fx.PARTICLE_DISTANCE = 50.0
	var world := stage()
	var ugv := Ugv.new()
	ugv.position = world.player.position + Vector3(0, 100, -60)
	world.add_enemy(ugv)
	await frames(2)
	var shot := Hit.make(Hit.Kind.SHELL, ugv.max_hp * 2.0, ugv.hit_center(), Vector3.RIGHT)
	shot.caliber = 100
	shot.speed = Armament.SHELL_SPEED
	shot.source = world.player
	ugv.take_hit(shot)
	check(ugv.dead, "shell kills the vehicle through its damage path")
	var pieces := Wreck._live.duplicate()
	check(pieces.size() > 2, "death creates a body and detached parts")
	world._hitstop = 0.0
	Engine.time_scale = 1.0
	var refs: Array[WeakRef] = []
	for wreck: Wreck in pieces:
		refs.append(weakref(wreck))
		wreck.set_process(false)
		wreck.global_position = world.player.global_position + Vector3.UP * 100
		wreck.velocity = Vector3.ZERO
		wreck._process(0.75)
		check(not wreck.is_queued_for_deletion(), "airborne body and parts survive before 1 s")
		wreck._process(0.25)
		check(wreck.is_queued_for_deletion(), "airborne body and parts disappear at exactly 1 s")
	await frames(1)
	for ref: WeakRef in refs:
		check(ref.get_ref() == null, "expired detached models are actually freed")


func test_wreck_expires_after_fifty_metres_of_cumulative_travel() -> void:
	Fx.PARTICLE_LIFE = 8.0
	Fx.PARTICLE_DISTANCE = 50.0
	var world := stage()
	var model := Node3D.new()
	world.add_child(model)
	var wreck := Wreck.launch(model, world.player.position + Vector3.UP * 100, 1.0, false)
	wreck.set_process(false)
	# Counter gravity for each explicit step so two exactly 25 m segments return to the start.
	wreck.velocity = Vector3(100, 5.5, 0)
	wreck._process(0.25)
	check(not wreck.is_queued_for_deletion(), "wreck survives after 25 m")
	wreck.velocity = Vector3(-100, 5.5, 0)
	wreck._process(0.25)
	check(wreck.is_queued_for_deletion(), "wreck expires at 50 m even when it returns to its origin")
	check(world.fx._emitters.is_empty(), "expiry does not trigger a landing fire")
	await frames(1)
	check(not is_instance_valid(model), "distance expiry frees the detached model too")


func test_live_duel_limits_apply_to_existing_wrecks() -> void:
	var world := stage()
	var model := Node3D.new()
	world.add_child(model)
	var wreck := Wreck.launch(model, world.player.position + Vector3.UP * 100, 1.0, false)
	wreck.set_process(false)
	var tuning := GameTuning.new()
	var duration: Array = tuning._rows.filter(func(row: Array) -> bool: return row[0] == "Fragments/smoke duration (s)")[0]
	var distance: Array = tuning._rows.filter(func(row: Array) -> bool: return row[0] == "Fragments/smoke travel (m)")[0]
	duration[2].call(4.0)
	distance[2].call(100.0)
	wreck.velocity = Vector3(60, 27.5, 0)
	wreck._process(1.25)
	check(not wreck.is_queued_for_deletion(), "extended duel limits allow a wreck beyond 1 s and 50 m")
	distance[2].call(50.0)
	wreck._process(0.0)
	check(wreck.is_queued_for_deletion(), "lowering the live travel limit removes an existing wreck")
