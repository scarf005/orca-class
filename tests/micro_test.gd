extends TestCase
## The micro-missile round: instant Ex-Zodiac locks (up to four, repeats allowed) and a rippled salvo.

const DT := 1.0 / 60.0


func _rig() -> World:
	var world := stage()
	world.set_process(false)
	world.director.set_process(false)
	world.player.set_process(false)
	world.player.input_enabled = true
	world.camera.set_process(false)
	world.camera.follow(0.0)
	world.player.load_round(Armament.Round.MICRO)
	Input.action_release("fire")
	return world


func _enemy(world: World, at: Vector3) -> Enemy:
	var enemy := Enemy.new()
	enemy.position = at
	world.add_enemy(enemy)
	enemy.set_process(false)
	return enemy


## Holds fire for `seconds`, with the sight on `enemy`.
func _hold_on(world: World, enemy: Enemy, seconds: float) -> void:
	var tank := world.player
	tank.aim_screen = world.camera.unproject_position(enemy.hit_center())
	Input.action_press("fire")
	for _i in roundi(seconds / DT):
		tank._update_charge(DT)
		tank._update_weapons(DT)


func _release(world: World) -> void:
	var tank := world.player
	Input.action_release("fire")
	tank._update_charge(DT)
	tank._update_weapons(DT)
	for _i in 12:
		tank._update_weapons(DT)


func _missiles(world: World) -> Array:
	return world.projectiles.filter(func(p: Projectile) -> bool: return p.shape == "micro" and not p.is_queued_for_deletion())


func _row(world: World, count: int) -> Array[Enemy]:
	var row: Array[Enemy] = []
	var origin := world.player.hit_center() - Vector3(0, 0, 40)
	for i in count:
		row.append(_enemy(world, origin + Vector3((i - count * 0.5) * 7.0, 0, 0)))
	return row


func test_sweeping_three_enemies_locks_each_then_holding_adds_the_fourth_to_one_of_them() -> void:
	var world := _rig()
	var tank := world.player
	var row := _row(world, 3)
	for enemy in row:
		_hold_on(world, enemy, Armament.MICRO_LOCK_INTERVAL + DT)
	check_eq(tank.micro_locks.map(func(l: Array) -> Entity: return l[0]), row, "one lock on each, in the order swept")
	check(_missiles(world).is_empty(), "nothing fires while the button is held short of four")
	_hold_on(world, row[1], Armament.MICRO_STACK_INTERVAL + DT)
	for _i in 12:
		tank._update_weapons(DT)
	var targets := _missiles(world).map(func(m: Projectile) -> Node3D: return m.homing_target)
	check_eq(targets.size(), 4, "four locks, four missiles")
	check_eq(targets.filter(func(t: Node3D) -> bool: return t == row[1]).size(), 2, "the fourth went to the enemy under the reticle, which now holds two")
	check(row[0] in targets and row[2] in targets, "the others hold one each")
	Input.action_release("fire")


func test_the_fourth_lock_fires_the_salvo_at_once() -> void:
	var world := _rig()
	var tank := world.player
	var enemy := _row(world, 1)[0]
	_hold_on(world, enemy, Armament.MICRO_STACK_INTERVAL - 0.05)
	check_eq(tank.micro_locks.size(), 1, "one lock: staying on a locked enemy stacks slowly, leaving time to sweep on")
	_hold_on(world, enemy, Armament.MICRO_STACK_INTERVAL * 2.0)
	check(_missiles(world).is_empty() and tank.micro_locks.size() == 3, "three locks: nothing has left")
	_hold_on(world, enemy, Armament.MICRO_STACK_INTERVAL + 0.02)
	_hold_on(world, enemy, Armament.MICRO_RIPPLE * 4.0)
	check_eq(_missiles(world).size(), Armament.MICRO_LOCKS, "four missiles left without letting go")
	check(_missiles(world).all(func(m: Projectile) -> bool: return m.homing_target == enemy), "all of them on the one enemy")
	check_eq(tank.round_count, Armament.MAGAZINE[Armament.Round.MICRO] - 1, "one round for the whole salvo")
	check(tank.micro_locks.is_empty(), "the locks are spent")
	check_eq(tank.micro_marked.size(), Armament.MICRO_LOCKS, "but they stay marked on the target while the missiles fly")
	enemy.dead = true
	tank._update_charge(DT)
	check(tank.micro_marked.is_empty(), "until it dies")
	Input.action_release("fire")


func test_release_fires_one_missile_per_lock_and_they_ripple_out() -> void:
	var world := _rig()
	var tank := world.player
	var row := _row(world, 2)
	_hold_on(world, row[0], Armament.MICRO_LOCK_INTERVAL + DT)
	_hold_on(world, row[1], Armament.MICRO_LOCK_INTERVAL + DT)
	check_eq(tank.micro_locks.size(), 2, "two locks")
	Input.action_release("fire")
	tank._update_charge(DT)
	tank._update_weapons(DT)
	tank._update_weapons(DT)
	check_eq(_missiles(world).size(), 1, "the first missile leaves with the release")
	for _i in 6:
		tank._update_weapons(DT)
	var shots := _missiles(world)
	check_eq(shots.size(), 2, "the second follows a ripple later, none more")
	check_eq(shots.map(func(m: Projectile) -> Node3D: return m.homing_target), row, "each on its own lock")
	check_eq(tank.round_count, Armament.MAGAZINE[Armament.Round.MICRO] - 1, "one round per salvo")


func test_micro_lock_ring_shrinks_with_fcs_damage_but_still_fires_without_it() -> void:
	var world := _rig()
	var tank := world.player
	var enemy := _row(world, 1)[0]
	for condition in [[TankModules.MAX.fcs, 1.0], [1.0, 0.5], [0.0, 0.2]]:
		tank.modules.hp.fcs = condition[0]
		tank._cancel_charge()
		tank._recover = 0.0
		tank.load_round(Armament.Round.MICRO)
		var center := world.camera.unproject_position(enemy.hit_center())
		var radius: float = Armament.LOCK_RADIUS * condition[1]
		tank.aim_screen = center + Vector2(radius + 1.0, 0)
		Input.action_press("fire")
		tank._update_charge(DT)
		check(tank.micro_locks.is_empty(), "no lock outside the FCS-scaled seeker ring")
		tank.aim_screen = center + Vector2(radius - 1.0, 0)
		tank._update_charge(DT)
		check_eq(tank.micro_locks.size(), 1, "micro locks inside the reduced ring even without FCS")
		_release(world)
		check_eq(_missiles(world).size(), 1, "micro fires even with the FCS destroyed")
		check_eq(tank.round_count, Armament.MAGAZINE[Armament.Round.MICRO] - 1, "the salvo consumes one round")
		for shot: Projectile in _missiles(world):
			check(shot.homing_target == enemy, "the missile keeps its own target")
			shot.queue_free()
		await frames(2)


func test_releasing_without_a_lock_fires_nothing_and_keeps_the_round() -> void:
	var world := _rig()
	var tank := world.player
	var far := _enemy(world, tank.hit_center() - Vector3(0, 0, 40))
	tank.aim_screen = world.camera.unproject_position(far.hit_center()) + Vector2(400, 0)
	Input.action_press("fire")
	for _i in 30:
		tank._update_charge(DT)
		tank._update_weapons(DT)
	check(tank.micro_locks.is_empty(), "nothing under the reticle to lock")
	_release(world)
	check(_missiles(world).is_empty(), "no missiles")
	check_eq(tank.round_count, Armament.MAGAZINE[Armament.Round.MICRO], "the round is kept")
	check(tank.current_round == Armament.Round.MICRO, "and still loaded")


func test_a_lock_drops_when_its_enemy_dies() -> void:
	var world := _rig()
	var tank := world.player
	var row := _row(world, 2)
	_hold_on(world, row[0], DT)
	_hold_on(world, row[1], Armament.MICRO_LOCK_INTERVAL + DT)
	row[0].dead = true
	tank._update_charge(DT)
	check_eq(tank.micro_locks.size(), 1, "the dead one's lock is gone")
	Input.action_release("fire")


func test_four_micro_missiles_carry_one_full_charge_between_them() -> void:
	var world := _rig()
	var tank := world.player
	var enemy := _row(world, 1)[0]
	_hold_on(world, enemy, Armament.MICRO_STACK_INTERVAL * 3.0 + 0.05)
	_hold_on(world, enemy, Armament.MICRO_RIPPLE * 4.0)
	var shots := _missiles(world)
	check_eq(shots.size(), 4, "four missiles")
	var full := Armament.SHELL_DAMAGE * Armament.APHE_DAMAGE.y * Armament.SHELL_DAMAGE_SCALE
	var hit := 0.0
	var blast := 0.0
	for shot: Projectile in shots:
		hit += shot.hit.damage
		blast += shot.blast_damage
		check_eq(shot.hit.kind, Hit.Kind.SHELL, "a shell hit, so armor rules apply")
		check_eq(shot.hit.caliber, Armament.MICRO_CALIBER, "caliber")
		check(shot.hit.caliber < 100, "short of tearing its target apart")
		check_eq(shot.hit.weapon, "cannon", "not an area round")
	check_near(hit, full, 0.01, "hit damage adds up to the full APHE shell")
	check_near(blast, Armament.APHE_BLAST.y * Armament.SHELL_DAMAGE_SCALE, 0.01, "so does the blast")
	var hp := enemy.hp
	for _i in 240:
		for shot: Projectile in world.projectiles.duplicate():
			if not shot.is_queued_for_deletion():
				shot.step(DT)
	check(enemy.hp < hp or enemy.dead, "they struck it (hp %.0f of %.0f)" % [enemy.hp, hp])
	Input.action_release("fire")
