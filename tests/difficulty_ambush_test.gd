extends TestCase


func test_events_match_real_buildings_only_on_hard() -> void:
	Game.difficulty = Game.Difficulty.HARD
	var world := stage()
	var ambushes := Stage1.events(true).filter(func(e: Dictionary) -> bool: return e.type == "ambush")
	check_eq(ambushes.size(), 7, "seven authored urban ambushes")
	check_eq(Stage1.events(false).filter(func(e: Dictionary) -> bool: return e.type == "ambush").size(), 0, "normal and easy have no ambush events")
	for event: Dictionary in ambushes:
		var enemy := world.director.spawn_ambush(event)
		check(enemy != null and enemy.hidden, "event has a real host at %.0f m" % event.building_d)
		if enemy:
			check(enemy.ambush_host.kind in ["house", "infested_house", "hall"], "ambush uses a building, not a substitute")
			check_near(Course.to_course(enemy.ambush_host.global_position).x, event.building_d, 0.1, "host is at event distance")
	Game.difficulty = Game.Difficulty.NORMAL


func test_hidden_walker_is_unhittable_and_unlocked_then_attacks() -> void:
	Game.difficulty = Game.Difficulty.HARD
	var world := stage()
	world.director.set_process(false)
	var enemy := world.director.spawn_ambush({"building_d": 900.0, "kind": "walker"}) as Walker
	var before := enemy.hp
	enemy.take_hit(Hit.make(Hit.Kind.SHELL, 10000.0, enemy.hit_center()))
	check_eq(enemy.hp, before, "hidden enemy is invulnerable")
	check_eq(enemy.hit_test(enemy.hit_center() - Vector3.RIGHT * 20.0, enemy.hit_center() + Vector3.RIGHT * 20.0), -1.0, "shell cannot intersect hidden enemy")
	check_eq(world.player._lock_distance(enemy), INF, "hidden enemy cannot lock")
	check(not enemy.visible and enemy.invulnerable, "no hostile outline before emergence")
	var host := enemy.ambush_host
	world.player.global_position = Course.ground_at(850.0, -16.0)
	enemy.tick(0.01)
	check(enemy._ambush_wind > 0.0 and enemy.hidden, "approach starts a hidden dust warning")
	enemy.tick(0.3)
	check(enemy.hidden, "warning does not instantly expose the enemy")
	enemy.tick(0.36)
	check(not enemy.hidden and not enemy.invulnerable and enemy.visible, "emerged enemy is hittable and visible")
	check(host.dead, "walker breaks through the wall")
	world.player.global_position = Course.ground_at(840.0, 0.0)
	enemy.tick(0.01)
	check(enemy.telegraphing(), "walker begins its attack after emergence")
	enemy.tick(0.9)
	var count := world.projectiles.size()
	enemy.tick(0.01)
	check(world.projectiles.size() > count, "walker attacks after its own warning")
	Game.difficulty = Game.Difficulty.NORMAL


func test_destroying_host_releases_drone_after_warning() -> void:
	Game.difficulty = Game.Difficulty.HARD
	var world := stage()
	world.director.set_process(false)
	var drone := world.director.spawn_ambush({"building_d": 760.0, "kind": "fpv"}) as FpvDrone
	var host := drone.ambush_host
	var roof := host.global_position.y + host.height
	host.die(Hit.make(Hit.Kind.SHELL, 1000.0, host.hit_center()))
	check(drone.hidden and drone._ambush_wind > 0.0, "destroyed house triggers warning, not an immediate attack")
	drone.tick(0.66)
	check(not drone.hidden and drone.interceptable, "drone emerges and CIWS can target it")
	check(drone.global_position.y > roof, "drone bursts through the roof")
	check(drone.hit_test(drone.hit_center(), drone.hit_center()) >= 0.0, "emerged drone intersects shells")
	Game.difficulty = Game.Difficulty.NORMAL


func test_already_destroyed_house_still_releases_ambush() -> void:
	Game.difficulty = Game.Difficulty.HARD
	var world := stage()
	world.director.scenery.stream(500.0, 100000)
	var spec: Scenery.Spec
	for candidate in world.director.scenery.specs:
		if candidate.d == 760.0 and candidate.kind in ["house", "infested_house"]:
			spec = candidate
	var host := spec.node as Prop
	host.die(Hit.make(Hit.Kind.SHELL, 1000.0, host.hit_center()))
	await frames(2)
	var drone := world.director.spawn_ambush({"building_d": 760.0, "kind": "fpv"})
	check(drone.hidden and drone._ambush_wind > 0.0, "destroyed streamed building still triggers its ambush")
	drone.tick(0.66)
	check(not drone.hidden, "fallback uses destroyed house position and emerges")
	Game.difficulty = Game.Difficulty.NORMAL
