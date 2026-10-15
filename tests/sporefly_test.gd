extends TestCase
## The sporefly flies the FPV drone's dive but strikes with spores: no warhead, a lingering cloud, a spore glob on Hard.


func _dive_at_hull(world: World) -> Sporefly:
	var fly := Sporefly.new()
	world.add_enemy(fly)
	fly.global_position = world.player.hit_center() + Vector3(0, 0, -1.0)
	fly.state = FpvDrone.State.DIVE
	fly._dive_dir = Vector3.BACK
	return fly


func test_a_dive_lands_a_spore_hit_and_leaves_a_cloud_not_a_warhead() -> void:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage("", true, 1)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.player._respawn = 0.0
	world.player.invuln = 0.0
	var kinds := []
	var warheads := []
	world.player.damaged.connect(func(_e: Entity, hit: Hit) -> void:
		kinds.append(hit.kind)
		warheads.append(hit.warhead))
	var hp := world.player.hp
	var fly := _dive_at_hull(world)
	fly.behave(0.01)
	check(world.player.hp < hp, "the dive damages the hull")
	check_eq(kinds, [Hit.Kind.SPORE], "it lands one spore hit")
	check_eq(warheads, [false], "reactive armor has no warhead to stop")
	check(world.get_children().any(func(node: Node) -> bool: return node is Hazard), "a spore cloud lingers")
	check(fly.is_queued_for_deletion(), "the sporefly is spent")
	check_eq(world.stats.kills, 0, "spending itself is not a player kill")


func test_hard_telegraph_lobs_a_spore_glob_instead_of_a_rocket() -> void:
	Game.difficulty = Game.Difficulty.HARD
	var world := stage("", true, 1)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	var fly := Sporefly.new()
	world.add_enemy(fly)
	fly.global_position = world.player.hit_center() + Vector3(0, 6, -30)
	fly.state = FpvDrone.State.TELEGRAPH
	fly._start_dive(world.player)
	var glob: Projectile = world.projectiles.back()
	check_eq(glob.hit.kind, Hit.Kind.SPORE, "the glob is a spore hit")
	check(glob.interceptable, "the CIWS can burn it down")
	Game.difficulty = Game.Difficulty.NORMAL


func test_a_killed_sporefly_pops_without_a_fireball_and_the_pursuit_sends_them() -> void:
	Game.difficulty = Game.Difficulty.NORMAL
	var world := stage("", true, 1)
	await frames(2)
	var fly := Sporefly.new()
	world.add_enemy(fly)
	var hit := Hit.make(Hit.Kind.BULLET, 99.0, fly.hit_center())
	hit.source = world.player
	fly.take_hit(hit)
	check(fly.dead and world.stats.kills == 1, "one coax burst kills and scores it")
	var sent := world.director.send_pursuers(2, FpvDrone.Pattern.ARC)
	check_eq(sent.size(), 2, "the pursuit launches a group")
	check(sent.all(func(e: Enemy) -> bool: return e is Sporefly), "stage 1's pursuers are sporeflies")
