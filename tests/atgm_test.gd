extends TestCase
## The ATGM round: a special round that flies a strongly guided missile and re-locks when its target dies.

const DT := 1.0 / 60.0


func _rig() -> World:
	var world := stage()
	world.set_process(false)
	world.director.set_process(false)
	world.player.set_process(false)
	world.player.input_enabled = true
	world.camera.set_process(false)
	world.camera.follow(0.0)
	Input.action_release("fire")
	return world


func _enemy(world: World, at: Vector3) -> Enemy:
	var enemy := Enemy.new()
	enemy.position = at
	world.add_enemy(enemy)
	enemy.set_process(false)
	return enemy


func _missiles(world: World) -> Array:
	return world.projectiles.filter(func(p: Projectile) -> bool: return p.shape == "atgm" and not p.is_queued_for_deletion())


## Flies every projectile for `seconds`, moving `mover` along `velocity` as it goes.
func _fly(world: World, seconds: float, mover: Enemy = null, velocity := Vector3.ZERO) -> void:
	for _i in roundi(seconds / DT):
		if mover:
			mover.global_position += velocity * DT
			mover.velocity = velocity
		for projectile: Projectile in world.projectiles.duplicate():
			if not projectile.is_queued_for_deletion():
				projectile.step(DT)


func test_atgm_charges_twice_as_fast_and_fires_at_the_first_lock_box() -> void:
	var world := _rig()
	var tank := world.player
	tank.load_round(Armament.Round.ATGM)
	check_eq(tank.round_count, 6, "six missiles")
	check_eq(Tank.round_step(Armament.Round.ATGM), Armament.STAGE_1, "it fires at the first lock box")
	check_near(tank.charge_time(), Armament.FULL_TIME * 0.5, 0.001, "its charge runs twice as fast as the APHE's")
	var enemy := _enemy(world, tank.hit_center() - Vector3(0, 0, 60))
	tank.aim_screen = world.camera.unproject_position(enemy.hit_center())
	Input.action_press("fire")
	var held := 0.0
	while _missiles(world).is_empty() and held < 2.0:
		tank._update_charge(DT)
		tank._update_charge_lock()
		tank._update_weapons(DT)
		held += DT
	check_near(held, Armament.STAGE_1 * Armament.FULL_TIME * 0.5, 2.0 * DT, "fired after %.2f s of holding" % held)
	check_eq(tank.round_count, 5, "one missile spent")
	check_eq(_missiles(world)[0].homing_target, enemy, "homing on the charge lock")
	Input.action_release("fire")


func test_the_missile_catches_a_target_crossing_at_20_mps() -> void:
	var world := _rig()
	var tank := world.player
	tank.load_round(Armament.Round.ATGM)
	var enemy := _enemy(world, tank.hit_center() + Vector3(-25, 0, -60))
	enemy.velocity = Vector3(20, 0, 0)
	var hp := enemy.hp
	tank.coax_target = enemy
	tank.fire_cannon()
	_fly(world, 3.0, enemy, Vector3(20, 0, 0))
	check(enemy.hp < hp or enemy.dead, "the missile struck it (hp %.0f of %.0f)" % [enemy.hp, hp])


func test_a_missile_re_locks_the_nearest_enemy_when_its_target_dies() -> void:
	var world := _rig()
	var tank := world.player
	tank.load_round(Armament.Round.ATGM)
	var origin := tank.hit_center() - Vector3(0, 0, 40)
	var first := _enemy(world, origin)
	var second := _enemy(world, origin + Vector3(30, 0, -40))
	var behind := _enemy(world, tank.hit_center() + Vector3(0, 0, 30))
	tank.coax_target = first
	tank.fire_cannon()
	var missile: Projectile = _missiles(world)[0]
	_fly(world, 0.05)
	first.dead = true
	var hp := second.hp
	_fly(world, 0.03)
	check(missile.homing_target == second, "it turned on the nearest living enemy ahead, not the one behind")
	_fly(world, 2.0)
	check(second.hp < hp or second.dead, "and struck it")
	check(not behind.dead, "the one behind it was left alone")


func test_a_missile_with_nothing_to_lock_flies_straight_and_expires() -> void:
	var world := _rig()
	var tank := world.player
	tank.load_round(Armament.Round.ATGM)
	tank.fire_cannon()
	var missile: Projectile = _missiles(world)[0]
	_fly(world, 0.5)
	check(missile.homing_target == null, "nothing to lock")
	_fly(world, Armament.ATGM_LIFE)
	check(missile.is_queued_for_deletion() or not is_instance_valid(missile), "it expires")


func test_atgm_hits_like_the_full_charge_aphe_shell() -> void:
	var world := _rig()
	var tank := world.player
	tank.load_round(Armament.Round.ATGM)
	tank.fire_cannon()
	var missile: Projectile = _missiles(world)[0]
	var scale := Armament.SHELL_DAMAGE_SCALE
	check_near(missile.hit.damage, Armament.SHELL_DAMAGE * Armament.APHE_DAMAGE.y * scale, 0.01, "hit damage")
	check_near(missile.blast_damage, Armament.APHE_BLAST.y * scale, 0.01, "blast damage")
	check_near(missile.blast_radius, Armament.APHE_RADIUS.y * Armament.HE_RADIUS_SCALE, 0.01, "blast radius")
	check_eq(missile.hit.caliber, 100, "caliber")
	check_eq(missile.hit.kind, Hit.Kind.SHELL, "a shell, so it tears and dismembers")
	check_near(missile.hit.power, 1.0, 0.001, "a full-charge hit")
	check(missile.pierce_entities, "it pierces")
	check_eq(missile.hit.weapon, "cannon", "not an area round")


func test_an_empty_magazine_falls_back_to_aphe() -> void:
	var world := _rig()
	var tank := world.player
	tank.load_round(Armament.Round.ATGM)
	for _i in 6:
		tank.fire_cannon()
	check_eq(tank.current_round, Armament.Round.APHE, "back to the plain shell")
