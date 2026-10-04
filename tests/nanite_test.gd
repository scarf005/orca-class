extends TestCase
## Hull health comes from driver-controlled melee salvage and repair, never style or guns.


func _rig() -> World:
	var world := stage()
	world.set_process(false)
	world.director.set_process(false)
	world.player.set_process(false)
	world.player.hp = 40.0
	world.camera.follow(0.0)
	world.player.tail.update(0.0, world.player.global_basis, 0.0)
	return world


func _enemy(world: World, at: Vector3) -> Enemy:
	var enemy := Enemy.new()
	enemy.position = at
	world.add_enemy(enemy)
	enemy.set_process(false)
	enemy.death_radius = 1.5
	return enemy


func _arrive(world: World) -> void:
	for i in 61:
		world.player.global_position += Vector3.RIGHT * 0.1
		world._update_nanites(1.0 / 60.0)


func test_ram_kill_heals_over_time_and_follows_tank() -> void:
	var world := _rig()
	var enemy := Ugv.new()
	enemy.position = world.player.global_position
	world.add_enemy(enemy)
	enemy.set_process(false)
	enemy.hp = 1.0
	var expected := clampf(enemy.death_radius * 4.0, 2.0, 15.0)
	world.player._ram_enemies()
	check(enemy.dead, "tank's ram kills")
	check_near(world.player.hp, 40.0, 0.001, "no instant healing on death")
	check_eq(world._nanites.size(), ceili(expected / World.NANITE_HP), "one particle per half HP")
	world._update_nanites(0.49)
	check_near(world.player.hp, 40.0, 0.001, "no particle arrives before half a second")
	_arrive(world)
	check_near(world.player.hp, 40.0 + expected, 0.001, "moving tank receives exact total")
	check_near(world.stats.melee_healing, expected, 0.001, "probe counts actual healing")
	check_eq(world._nanites.size(), 0, "all particles arrive within one second")


func test_dash_lash_kill_heals() -> void:
	var world := _rig()
	var enemy := _enemy(world, world.player.global_position + Vector3.RIGHT * 5.0)
	world.player.dash(Vector2.RIGHT)
	check(enemy.dead, "dash lash kills")
	_arrive(world)
	check_near(world.player.hp, 46.0, 0.001, "dash kill yields nanites")


func test_autonomous_stab_and_swat_heal_nothing() -> void:
	var world := _rig()
	var enemy := _enemy(world, world.player.global_position + Vector3.RIGHT * 5.0)
	world.player._grab_target = enemy
	world.player.tail.set_state(Tail.State.STAB)
	world.player._on_tail_arrived()
	check(enemy.dead, "autonomous stab kills a small enemy")
	_arrive(world)
	check_near(world.player.hp, 40.0, 0.001, "autonomous stab heals nothing")
	var swatted := _enemy(world, world.player.global_position + Vector3.RIGHT * 5.0)
	world.player.swat(true)
	check(not swatted.dead, "autonomous swat only staggers")
	_arrive(world)
	check_near(world.player.hp, 40.0, 0.001, "autonomous swat heals nothing")
	check_eq(world.stats.melee_healing, 0.0, "no melee healing credited")


func test_gun_and_ciws_kills_heal_nothing() -> void:
	var world := _rig()
	for kind: Hit.Kind in [Hit.Kind.BULLET, Hit.Kind.SHELL, Hit.Kind.LASER]:
		var enemy := _enemy(world, world.player.global_position + Vector3(30, 0, 0))
		var hit := Hit.make(kind, 999.0, enemy.hit_center())
		hit.source = world.player
		enemy.take_hit(hit)
		check(enemy.dead, "weapon kind %d kills" % kind)
		_arrive(world)
		check_near(world.player.hp, 40.0, 0.001, "weapon kind %d heals nothing" % kind)
	check_eq(world.stats.melee_healing, 0.0, "no gun healing credited")


func test_style_b_and_above_heals_nothing() -> void:
	var world := _rig()
	for rank in range(2, RunStats.STYLE_RANKS.size()):
		world.stats.style = RunStats.STYLE_RANKS[rank]
		world.style_event("CRUSH", 100.0)
		_arrive(world)
		check_near(world.player.hp, 40.0, 0.001, "style rank %d yields no health" % rank)


func test_repair_is_exactly_ten_and_other_repairs_unchanged() -> void:
	var world := _rig()
	var tank := world.player
	tank.modules.damage("engine", 20.0)
	tank.tail.hp = 10.0
	var pickup := Pickup.new()
	pickup.id = "repair"
	world.add_child(pickup)
	tank.collect(pickup)
	check_near(tank.hp, 50.0, 0.001, "repair adds exactly ten hull HP")
	check_eq(tank.modules.state("engine"), TankModules.State.OK, "repair still restores modules")
	check_near(tank.tail.hp, 70.0, 0.001, "repair still adds sixty tail HP")
	check_near(world.stats.repair_healing, 10.0, 0.001, "probe counts repair healing")


func test_cap_and_tail_torn_off_in_flight() -> void:
	var world := _rig()
	world.player.hp = world.player.max_hp - 1.0
	var enemy := _enemy(world, world.player.global_position + Vector3(30, 0, 0))
	var hit := Hit.make(Hit.Kind.RAM, 999.0, enemy.hit_center())
	hit.source = world.player
	hit.salvage = true
	enemy.take_hit(hit)
	check_eq(hit.copy().salvage, true, "copy retains salvage")
	world._update_nanites(0.25)
	world.player.tail.damage(Tail.MAX_HP)
	check(world.player.tail.destroyed, "tail is torn off while nanites fly")
	_arrive(world)
	check_near(world.player.hp, world.player.max_hp, 0.001, "nanites arrive at hull rear and cap health")
	check_near(world.stats.melee_healing, 1.0, 0.001, "only received HP is credited")
	check_eq(world._nanites.size(), 0, "tail loss strands no particles")


func test_thrown_by_player_only_and_no_blast_salvage() -> void:
	var world := _rig()
	var at := world.player.global_position + Vector3(30, 0, 0)
	var enemy := _enemy(world, at)
	var hit := Hit.make(Hit.Kind.THROWN, 999.0, enemy.hit_center())
	hit.source = world.player
	enemy.take_hit(hit)
	_arrive(world)
	check_near(world.player.hp, 46.0, 0.001, "tank-thrown melee yields nanites")
	enemy = _enemy(world, at)
	hit = Hit.make(Hit.Kind.THROWN, 999.0, enemy.hit_center())
	enemy.take_hit(hit)
	_arrive(world)
	check_near(world.player.hp, 46.0, 0.001, "non-player thrown hit yields none")
	enemy = _enemy(world, at)
	hit = Hit.make(Hit.Kind.RAM, 999.0, at)
	hit.source = world.player
	hit.salvage = true
	world.blast(at, 2.0, 999.0, Entity.Team.PLAYER, hit)
	_arrive(world)
	check_near(world.player.hp, 46.0, 0.001, "melee's collateral blast never yields salvage")
