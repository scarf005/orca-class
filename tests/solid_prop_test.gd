extends TestCase
## A prop with `min_charge` refuses what cannot break it and stops a free-driving tank.


func _solid(world: World, at: Vector3, charge := 3) -> Prop:
	var prop := Prop.new()
	prop.setup("wall", PropKit.mesh("wall"), 1.6, 3.0, 10.0)
	prop.min_charge = charge
	prop.position = at
	world.props.add_child(prop)
	return prop


func _arena(at: Vector3) -> World:
	var world := stage()
	world.rail.mode = Rail.Mode.ARENA
	world.rail.arena_d = world.rail.d
	world.player.input_enabled = true
	world.player._set_pose(at, 0.0)
	world.player._last_position = at
	return world


func test_only_a_full_charge_breaks_a_charge_prop() -> void:
	var world := stage()
	var prop := _solid(world, Course.ground_at(60.0, 0.0))
	var weak := [Hit.make(Hit.Kind.RAM, 99999.0, prop.global_position), Hit.make(Hit.Kind.BULLET, 99999.0, prop.global_position), Hit.make(Hit.Kind.BLAST, 99999.0, prop.global_position)]
	for power in [0.0, Armament.STAGE_1, Armament.STAGE_2, 0.99]:
		var shot := Hit.make(Hit.Kind.SHELL, 99999.0, prop.global_position)
		shot.power = power
		weak.append(shot)
	for hit: Hit in weak:
		prop.take_hit(hit)
	check(not prop.dead and prop.hp == prop.max_hp, "ram, bullet, blast and every partial charge leave it untouched")
	var full := Hit.make(Hit.Kind.SHELL, 99999.0, prop.global_position)
	full.power = 1.0
	prop.take_hit(full)
	check(prop.dead, "a full charge breaks it")


func test_a_plain_prop_still_breaks_to_anything() -> void:
	var world := stage()
	var prop := _solid(world, Course.ground_at(60.0, 0.0), 0)
	prop.take_hit(Hit.make(Hit.Kind.RAM, 99999.0, prop.global_position))
	check(prop.dead, "min_charge 0 is ordinary scenery")


func test_free_driving_stops_against_a_charge_prop_without_crush_feedback() -> void:
	var start := Course.ground_at(20.0, 0.0)
	var world := _arena(start)
	var prop := _solid(world, Course.ground_at(40.0, 0.0))
	world.camera._kick = 0.0
	Input.action_press("move_forward")
	for i in 120:
		world.player.tick(1.0 / 60.0)
	Input.action_release("move_forward")
	var gap := Vector2(world.player.global_position.x - prop.global_position.x, world.player.global_position.z - prop.global_position.z).length()
	check(gap >= Tank.HULL_RADIUS + prop.footprint - 0.01, "the hull never enters the footprint (%.2f m)" % gap)
	check(world.player.global_position.z > prop.global_position.z, "and stays on its near side (z %.1f vs %.1f)" % [world.player.global_position.z, prop.global_position.z])
	check(not prop.dead, "the ram did not break it")
	check_eq(world.camera._kick, 0.0, "no crush feedback")
	check(world.player.local_velocity.length() < 1.0, "the speed into it is gone (%.2f)" % world.player.local_velocity.length())
