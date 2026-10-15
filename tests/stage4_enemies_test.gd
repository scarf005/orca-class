extends TestCase
## The flame crews: jets burn inside their cone and nowhere else, every attack is announced first, the fuel they
## carry is the answer to them, and burning ground hurts the tank but not the enemies.

const STEP := 1.0 / 60.0


func _setup() -> World:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage("", true, 4)
	await frames(2)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.player.velocity = Vector3.ZERO
	for prop: Prop in world.props.get_children():
		prop.dead = true
	world.rail.mode = Rail.Mode.HOLD
	return world


## Puts `enemy` `ahead` metres in front of the tank and `across` to its right, facing it.
func _spawn(world: World, enemy: Enemy, ahead: float, across := 0.0) -> void:
	enemy.position = Course.ground_at(world.rail.d + world.player.course_offset + ahead, across)
	world.add_enemy(enemy)
	enemy.age = 99.0 # Past its pacing time: it holds its ground.
	var toward := world.player.global_position - enemy.global_position
	enemy.model.rotation.y = atan2(-toward.x, -toward.z)


## Runs the enemy and its jets for `seconds`; returns [seconds until it was telegraphing, seconds until the first FIRE hit on the tank, number of FIRE hits].
func _fight(world: World, enemy: Enemy, seconds: float) -> Array:
	var tank := world.player
	var log := {"clock": 0.0, "warned": -1.0, "burned": -1.0, "hits": 0} # A lambda captures locals by value: its counters live in a dictionary.
	var on_hit := func(_who: Entity, hit: Hit) -> void:
		if hit.kind == Hit.Kind.FIRE:
			log.hits += 1
			if log.burned < 0.0:
				log.burned = log.clock
	tank.damaged.connect(on_hit)
	for _i in roundi(seconds / STEP):
		enemy.behave(STEP)
		for node in world.get_children():
			if node is FlameJet:
				node._process(STEP)
		tank.invuln = 0.0
		log.clock += STEP
		if log.warned < 0.0 and enemy.telegraphing():
			log.warned = log.clock
	tank.damaged.disconnect(on_hit)
	return [log.warned, log.burned, log.hits]


func _hostile_zones() -> Array:
	return FireZone._zones.filter(func(zone: FireZone) -> bool: return is_instance_valid(zone) and zone.hostile)


func test_a_jet_burns_only_inside_its_cone_and_reach() -> void:
	var origin := Vector3.ZERO
	var forward := Vector3.FORWARD
	check(FlameJet.along_cone(origin, forward, 28.0, Vector3(0, 0, -20), 0.0) >= 0.0, "straight ahead inside the reach is burned")
	check_near(FlameJet.along_cone(origin, forward, 28.0, Vector3(0, 0, -20), 0.0), 20.0, 0.001, "and reports how far along the jet it is")
	check(FlameJet.along_cone(origin, forward, 28.0, Vector3(0, 0, -31), 0.0) < 0.0, "beyond the reach is safe")
	check(FlameJet.along_cone(origin, forward, 28.0, Vector3(0, 0, 5), 0.0) < 0.0, "behind the nozzle is safe")
	var half := FlameJet.half_width(20.0)
	check_near(half, 0.7 + 0.12 * 20.0, 0.001, "the cone is 0.7 m wide at the nozzle and widens 0.12 m per metre")
	check(FlameJet.along_cone(origin, forward, 28.0, Vector3(half - 0.05, 0, -20), 0.0) >= 0.0, "just inside the cone's edge burns")
	check(FlameJet.along_cone(origin, forward, 28.0, Vector3(half + 0.05, 0, -20), 0.0) < 0.0, "just outside it is safe")
	check(FlameJet.along_cone(origin, forward, 28.0, Vector3(half + 1.0, 0, -20), 1.4) >= 0.0, "a hull's own radius counts toward the edge")
	check(FlameJet.along_cone(origin, forward, 28.0, Vector3(half * 2.0 + 0.05, 0, -20), 0.0, 2.0) < 0.0 and FlameJet.along_cone(origin, forward, 28.0, Vector3(half * 2.0 - 0.05, 0, -20), 0.0, 2.0) >= 0.0, "a thicker jet widens the cone in proportion")


func test_the_crocodile_lights_its_nozzle_before_the_jet_burns_the_tank() -> void:
	var world := await _setup()
	var croc := Crocodile.new()
	_spawn(world, croc, 22.0)
	croc._cooldown = 0.0
	var result := _fight(world, croc, 4.0)
	check(result[0] >= 0.0, "it winds up")
	check(result[1] >= 0.0, "the jet reaches the tank at 22 m")
	check(result[1] - result[0] >= Crocodile.WIND * 0.95, "the wind-up lasts at least %.1f s before any burn (%.2f s)" % [Crocodile.WIND, result[1] - result[0]])
	check(result[2] >= 3, "and burns it for as long as it stays in the jet (%d ticks)" % result[2])
	check(world.player.hp < world.player.max_hp, "the tank loses armor to the fire")


func test_the_crocodile_never_lights_up_on_a_tank_out_of_range_or_off_its_bow() -> void:
	var world := await _setup()
	var far := Crocodile.new()
	_spawn(world, far, 45.0)
	far._cooldown = 0.0
	var result := _fight(world, far, 4.0)
	check_eq(result[0], -1.0, "it does not wind up at 45 m")
	check_eq(result[2], 0, "and burns nothing")
	var world2 := await _setup()
	var side := Crocodile.new()
	_spawn(world2, side, 10.0, 20.0)
	side.age = 0.0
	side._cooldown = 0.0
	side.model.rotation.y = PI * 0.5 # Its bow points across the road, away from the tank.
	side._yaw = side.model.rotation.y
	side.behave(STEP)
	check(not side._can_burn(world2.player), "a tank abeam the hull is outside the bow's arc")


func test_the_jet_stops_short_of_a_tank_past_its_reach() -> void:
	var world := await _setup()
	var croc := Crocodile.new()
	_spawn(world, croc, 40.0)
	var jet := FlameJet.start(croc, croc._muzzle, 1.0, Crocodile.REACH)
	var muzzle_to_tank := croc._muzzle.global_position.distance_to(world.player.hit_center())
	check(muzzle_to_tank > Crocodile.REACH + 3.0, "the tank stands well past 28 m")
	var before := world.player.hp
	for _i in 60:
		jet._process(STEP)
		world.player.invuln = 0.0
	check_eq(world.player.hp, before, "a jet 40 m away leaves the armor untouched")


func test_the_jet_scorches_burnable_scenery_and_lights_the_ground_where_it_lands() -> void:
	var world := await _setup()
	var croc := Crocodile.new()
	_spawn(world, croc, 20.0)
	world.player.global_position += Vector3(30.0, 0.0, 0.0) # Out of the line of fire: this is about the ground and the scenery.
	var bore := -croc._muzzle.global_basis.z
	var fern := Prop.new()
	fern.setup("fern", PropKit.mesh("fern", 0), 1.3, 1.2, 100.0)
	fern.burnable = true
	fern.position = croc._muzzle.global_position + bore * 10.0
	fern.position.y = Course.height_at(fern.position)
	world.props.add_child(fern)
	var wall := Prop.new()
	wall.setup("wall", PropKit.mesh("wall", 0), 1.6, 1.7, 100.0)
	wall.position = croc._muzzle.global_position + bore * 14.0
	wall.position.y = Course.height_at(wall.position)
	world.props.add_child(wall)
	var jet := FlameJet.start(croc, croc._muzzle, 1.0, Crocodile.REACH)
	for _i in 30:
		jet._process(STEP)
	check(fern.hp < 100.0, "a fern in the jet burns (%.0f)" % fern.hp)
	check_eq(wall.hp, 100.0, "a wall in the same jet does not")
	check(not _hostile_zones().is_empty(), "the ground it licks is left burning")
	check(_hostile_zones().all(func(zone: FireZone) -> bool: return zone.global_position.distance_to(croc._muzzle.global_position) <= Crocodile.REACH + 1.0), "within the jet's reach")


func test_a_shell_in_the_trailer_bursts_it_and_the_tank_goes_with_it() -> void:
	var world := await _setup()
	var croc := Crocodile.new()
	_spawn(world, croc, 40.0)
	var before := FireZone._zones.size()
	var shell := Hit.make(Hit.Kind.SHELL, 60.0, croc.trailer_center(), Vector3.FORWARD)
	shell.caliber = 100
	shell.source = world.player
	croc.take_hit(shell)
	check(croc.fuel_gone, "the bowser is gone")
	check(croc.dead, "the flame tank dies with it")
	check(_hostile_zones().size() > before, "the fuel leaves burning ground")


func test_the_trailer_hides_behind_the_hull_head_on_and_shows_when_the_tank_turns_broadside() -> void:
	var world := await _setup()
	var croc := Crocodile.new()
	_spawn(world, croc, 40.0)
	var tank_eye := world.player.hit_center()
	var trailer := croc.trailer_center()
	var head_on := croc.hit_test(tank_eye, tank_eye + (trailer - tank_eye).normalized() * 100.0)
	var contact := tank_eye + (trailer - tank_eye).normalized() * head_on
	check(head_on >= 0.0 and contact.distance_to(trailer) > Crocodile.TRAILER_RADIUS + 0.6, "head-on the shot lands on the hull in front of the trailer (%.1f m from it)" % contact.distance_to(trailer))
	var hull_hit := Hit.make(Hit.Kind.SHELL, 60.0, contact, Vector3.FORWARD)
	hull_hit.caliber = 100
	hull_hit.source = world.player
	croc.take_hit(hull_hit)
	check(not croc.fuel_gone and croc.fuel_hp == 14.0, "a hull hit leaves the fuel alone")
	croc.model.rotation.y += PI * 0.5 # The hull swings broadside.
	croc.behave(STEP)
	var side := croc.hit_test(tank_eye, tank_eye + (croc.trailer_center() - tank_eye).normalized() * 100.0)
	var side_contact := tank_eye + (croc.trailer_center() - tank_eye).normalized() * side
	check(side >= 0.0 and side_contact.distance_to(croc.trailer_center()) <= Crocodile.TRAILER_RADIUS + 0.6, "broadside the shot reaches the trailer")


func test_a_hit_on_the_tracks_immobilizes_the_crocodile() -> void:
	var world := await _setup()
	var croc := Crocodile.new()
	_spawn(world, croc, 40.0)
	croc.age = 0.0
	var low := croc.global_position + croc.model.global_basis.x * 1.6 + Vector3.UP * 0.5
	var hit := Hit.make(Hit.Kind.SHELL, 12.0, low, Vector3.FORWARD)
	hit.caliber = 100
	hit.source = world.player
	croc.take_hit(hit)
	check(croc.immobile, "the tracks are out")
	var at := croc.global_position
	for _i in 60:
		croc.behave(STEP)
	check(croc.global_position.distance_to(at) < 0.05, "it no longer drives")


func test_the_burner_winds_up_before_a_short_jet_and_cannot_reach_far() -> void:
	var world := await _setup()
	var burner := Burner.new()
	_spawn(world, burner, 12.0)
	burner._attack_timer = 0.0
	var result := _fight(world, burner, 3.0)
	check(result[0] >= 0.0 and result[1] >= 0.0, "it winds up and then burns the tank at 12 m")
	check(result[1] - result[0] >= Burner.WIND * 0.95, "the wind-up lasts at least %.1f s (%.2f s)" % [Burner.WIND, result[1] - result[0]])
	var world2 := await _setup()
	var far := Burner.new()
	_spawn(world2, far, 30.0)
	far._attack_timer = 0.0
	var idle := _fight(world2, far, 3.0)
	check_eq(idle[2], 0, "at 30 m the short jet burns nothing")


func test_the_burners_fuel_pack_stands_over_its_shoulders_and_its_burst_takes_it_down() -> void:
	var world := await _setup()
	var burner := Burner.new()
	_spawn(world, burner, 30.0)
	var eye := world.player.hit_center()
	var pack := burner.pack_center()
	var t := burner.hit_test(eye, eye + (pack - eye).normalized() * 100.0)
	var contact := eye + (pack - eye).normalized() * t
	check(t >= 0.0 and contact.distance_to(pack) <= Burner.PACK_RADIUS + 0.6, "a shot at the pack from the tank reaches it, not the body (%.2f m off)" % contact.distance_to(pack))
	var shell := Hit.make(Hit.Kind.SHELL, 60.0, pack, Vector3.FORWARD)
	shell.caliber = 100
	shell.source = world.player
	burner.take_hit(shell)
	check(burner.pack_gone and burner.dead, "the pack bursts and the walker goes with it")
	check(not _hostile_zones().is_empty(), "leaving burning ground")


func test_burning_ground_hurts_the_tank_but_not_the_enemies_and_player_fire_the_reverse() -> void:
	var world := await _setup()
	var ugv := Ugv.new()
	_spawn(world, ugv, 30.0)
	ugv.immobile = true
	ugv.disarmed = true
	var tank := world.player
	FireZone.ignite(tank.global_position, "napalm", true)
	FireZone.ignite(ugv.global_position, "napalm", true)
	var tank_hp := tank.hp
	var ugv_hp := ugv.hp
	for zone in _hostile_zones():
		for _i in 30:
			zone._process(0.2)
			tank.invuln = 0.0
	check(tank.hp < tank_hp, "hostile fire burns the tank standing in it (%.0f to %.0f)" % [tank_hp, tank.hp])
	check_eq(ugv.hp, ugv_hp, "and leaves the enemy standing in its own fire alone")
	for zone in _hostile_zones():
		zone.queue_free()
	FireZone._zones.clear()
	FireZone.ignite(ugv.global_position, "cannon")
	FireZone.ignite(tank.global_position + Vector3(0, 0, 40.0), "cannon")
	var friendly: FireZone = FireZone._zones[0]
	var before := tank.hp
	for _i in 20:
		friendly._process(0.2)
	check(ugv.hp < ugv_hp, "the tank's own fire still burns enemies")
	check_eq(tank.hp, before, "and never the tank")


func test_a_napalm_drone_leaves_burning_ground_where_it_falls_and_a_plain_one_does_not() -> void:
	var world := await _setup()
	var napalm := FpvDrone.new()
	napalm.napalm = true
	_spawn(world, napalm, 30.0)
	napalm.global_position.y += 5.0
	var plain := FpvDrone.new()
	_spawn(world, plain, 60.0)
	plain.global_position.y += 5.0
	plain.die(Hit.make(Hit.Kind.BULLET, 99.0, plain.global_position))
	check(_hostile_zones().is_empty(), "a plain drone leaves no fire")
	var from := napalm.global_position
	napalm.die(Hit.make(Hit.Kind.BULLET, 99.0, from))
	var zones := _hostile_zones()
	check_eq(zones.size(), 1, "the napalm drone leaves one burning patch")
	if not zones.is_empty():
		check_near(zones[0].global_position.x, from.x, 0.01, "under where it was shot")
		check_near(zones[0].global_position.y, Course.height_at(from), 0.01, "on the ground")
