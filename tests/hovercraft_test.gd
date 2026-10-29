extends TestCase
## The plaza hunter's missile defense, exposed modules and fair attack windows.


func _boss() -> Hovercraft:
	var world := stage("", false, 2)
	world.director._next_event = world.director.events.size()
	world.rail.mode = Rail.Mode.HOLD
	var boss := Hovercraft.new()
	boss.position = Course.to_world(Stage2.PLAZA_D, 0.0) + Vector3(30, 0, 0)
	world.add_enemy(boss)
	boss._bound()
	boss._next_attack = 1000.0
	world.player.global_position = boss.arena_center()
	return boss


func _missile(boss: Hovercraft, round: Armament.Round) -> Projectile:
	return boss.player()._spawn_missile(round, boss.hit_center() + Vector3(0, 8, -15), Vector3.BACK, boss, "")


func _shell(boss: Hovercraft, at: Vector3, damage := 110.0) -> Hit:
	var hit := Hit.make(Hit.Kind.SHELL, damage * Armament.SHELL_DAMAGE / Hovercraft.ROUND_DAMAGE, boss.model.global_transform * at, Vector3.FORWARD)
	hit.caliber = 100
	hit.source = boss.player()
	return hit


func _laser(boss: Hovercraft, seconds: float) -> void:
	for i in ceili(seconds * 60.0):
		boss._update_laser(1.0 / 60.0)


func test_lasers_intercept_real_player_guided_rounds_and_rockets_only() -> void:
	var boss := _boss()
	var world := World.current
	var atgm := _missile(boss, Armament.Round.ATGM)
	var micro := _missile(boss, Armament.Round.MICRO)
	var rocket := world.spawn_projectile(Entity.Team.PLAYER, atgm.position, Vector3.ZERO, "rocket", Palette.BUTTER)
	var shell := world.spawn_projectile(Entity.Team.PLAYER, atgm.position, Vector3.ZERO, "shell", Palette.BUTTER)
	var dart := world.spawn_projectile(Entity.Team.PLAYER, atgm.position, Vector3.ZERO, "dart", Palette.BUTTER)
	shell.interceptable = true # Projectile CIWS eligibility is not missile identity.
	var hostile := world.spawn_projectile(Entity.Team.ENEMY, atgm.position, Vector3.ZERO, "atgm", Palette.HOT)
	_laser(boss, 0.5)
	check(atgm.is_queued_for_deletion(), "the player's actual ATGM is stopped even without its interceptable flag")
	check(micro.is_queued_for_deletion(), "the actual micro round is stopped too")
	check(rocket.is_queued_for_deletion(), "unguided player rockets are also stopped")
	check(not shell.is_queued_for_deletion() and not dart.is_queued_for_deletion(), "APHE and APFSDS pass the laser")
	check(not hostile.is_queued_for_deletion(), "friendly missiles are never shot down")


func test_overlapping_salvos_saturate_and_cooldown_recovers() -> void:
	var boss := _boss()
	var salvo: Array[Projectile] = []
	for i in 12:
		salvo.append(_missile(boss, Armament.Round.MICRO))
	_laser(boss, 0.6)
	var stopped := salvo.filter(func(p: Projectile) -> bool: return p.is_queued_for_deletion()).size()
	check(stopped > 0 and stopped < salvo.size(), "a salvo loses some missiles but gets the rest through")
	check(boss.laser_overheated, "overlapping missiles force the shared laser heat limit")
	var survivor: Projectile = salvo.filter(func(p: Projectile) -> bool: return not p.is_queued_for_deletion())[0]
	var hp := survivor.intercept_hp
	_laser(boss, 0.5)
	check_eq(survivor.intercept_hp, hp, "both beams cease while overheated")
	for shot in salvo:
		shot.queue_free()
	_laser(boss, 4.0)
	check(not boss.laser_overheated, "cooling restores the defense")
	var next := _missile(boss, Armament.Round.ATGM)
	_laser(boss, 0.3)
	check(next.is_queued_for_deletion(), "the cooled emitter intercepts again")


func test_laser_has_range_and_live_cover_blocks_its_beam() -> void:
	var boss := _boss()
	var shot := _missile(boss, Armament.Round.ATGM)
	shot.global_position = boss.hit_center() + Vector3.RIGHT * (Hovercraft.LASER_RANGE + 1.0)
	_laser(boss, 0.4)
	check_eq(shot.intercept_hp, 1.0, "outside the radius no laser damage is done")
	shot.global_position = boss.hit_center() + Vector3(0, 0, -20)
	var wall := Prop.new()
	wall.setup("city_building", PropKit.mesh("barrel", 1), 6.0, 15.0, 100.0)
	wall.position = boss.hit_center() + Vector3(0, -2, -10)
	World.current.props.add_child(wall)
	_laser(boss, 0.4)
	check_eq(shot.intercept_hp, 1.0, "a building blocks the laser even inside its radius")
	wall.dead = true
	_laser(boss, 0.4)
	check(shot.is_queued_for_deletion(), "lost cover opens line of sight")


func test_shell_breaks_emitter_so_missiles_reach_the_hull() -> void:
	var boss := _boss()
	var bullet := Hit.make(Hit.Kind.BULLET, 10.0, boss.model.global_transform * Hovercraft.PARTS.laser)
	bullet.caliber = 8
	boss.take_hit(bullet)
	check_eq(boss.parts.laser, 70.0, "light coax does not knock off the emitter")
	var heat := _shell(boss, Hovercraft.PARTS.laser)
	heat.pierce = true
	boss.take_hit(heat)
	check_eq(boss.parts.laser, 0.0, "one HEAT shell knocks the laser off")
	check(not boss.aim_parts().has("laser"), "the destroyed emitter is no longer lockable")
	var missile := _missile(boss, Armament.Round.ATGM)
	_laser(boss, 1.0)
	check_eq(missile.intercept_hp, 1.0, "missiles are no longer intercepted")
	missile.hit.damage = 110.0
	missile.hit.caliber = 100
	var before := boss.hp
	missile.global_position = boss.hit_center() + Vector3(0, 0, -10)
	missile.velocity = Vector3.BACK * 60.0
	land(World.current, World.current.projectiles.find(missile))
	check(boss.hp < before, "an actual surviving missile damages the hull")


func test_half_hull_strips_plates_and_unlocks_mlrs() -> void:
	var boss := _boss()
	var speed := boss.move_speed()
	boss._begin_attack(Hovercraft.Attack.MLRS)
	check_eq(boss._attack, Hovercraft.Attack.NONE, "rockets are unavailable in phase one")
	boss.take_hit(_shell(boss, Vector3.ZERO, boss.max_hp * 0.5 - 1.0))
	check_eq(boss.phase, Hovercraft.Phase.ARMORED, "just above half hull the armor holds")
	boss.take_hit(_shell(boss, Vector3.ZERO, 1.0))
	check_eq(boss.phase, Hovercraft.Phase.STRIPPED, "at exactly half hull phase two begins")
	check(boss.move_speed() > speed, "the stripped hull is faster")
	check(boss._plates.all(func(p: Node3D) -> bool: return p.get_parent() != boss.model), "flank plates physically break off")
	boss._begin_attack(Hovercraft.Attack.MLRS)
	boss._update_attack(0.5, boss.player())
	check_eq(World.current.projectiles.size(), 0, "the rocket rack still gives a dodge window")
	for i in 120:
		boss._update_attack(1.0 / 60.0, boss.player())
	check_eq(World.current.projectiles.size(), 6, "phase two fires a six-rocket ripple")


func test_fans_can_be_destroyed_independently_and_slow_the_hull() -> void:
	var boss := _boss()
	var speed := boss.move_speed()
	var origin := boss.global_position
	boss.behave(0.1)
	var travel := origin.distance_to(boss.global_position)
	boss.global_position = origin
	boss.take_hit(_shell(boss, Hovercraft.PARTS.fan_l))
	check_eq(boss.parts.fan_l, 0.0, "shell knocks out the left fan")
	check(boss.parts.fan_r > 0.0, "the other fan keeps working")
	check(boss.move_speed() < speed, "one fan lost slows it")
	boss.behave(0.1)
	check(origin.distance_to(boss.global_position) < travel, "the damaged hull actually covers less water in the same time")
	var one := boss.move_speed()
	boss.take_hit(_shell(boss, Hovercraft.PARTS.fan_r))
	check(boss.move_speed() < one and boss.move_speed() > 0.0, "with neither fan it limps rather than soft-locking")
	check(not boss.aim_parts().has("fan_l") and not boss.aim_parts().has("fan_r"), "lost fans leave the lock list")


func test_charged_shot_staggers_and_cancels_a_ram() -> void:
	var boss := _boss()
	boss._begin_attack(Hovercraft.Attack.RAM)
	var hit := _shell(boss, Vector3.ZERO)
	hit.power = 1.0
	boss.take_hit(hit)
	check(boss.is_staggered(), "one charged shot knocks the hunter back")
	check_eq(boss._attack, Hovercraft.Attack.NONE, "its warned dash is cancelled")
	check(boss._next_attack >= Hovercraft.WINDOW, "another charge fits before the next attack")
	var at := boss.global_position
	boss.behave(0.2)
	check_near(boss.global_position.distance_to(at), 0.0, 0.01, "the staggered hull stops moving")


func test_circle_and_ram_stay_inside_plaza_even_after_displacement() -> void:
	var boss := _boss()
	boss._next_attack = 1000.0
	for i in 600:
		boss.behave(1.0 / 60.0)
		check(Vector2(boss.position.x - boss.arena_center().x, boss.position.z - boss.arena_center().z).length() <= Stage2.PLAZA_RADIUS - boss.radius + 0.01, "the entire hull stays inside the arena")
	check(boss.position.distance_to(boss.arena_center()) > 30.0, "it circles the plaza instead of following the rail")
	boss._begin_attack(Hovercraft.Attack.RAM)
	for i in 240:
		boss.behave(1.0 / 60.0)
	check(Vector2(boss.position.x - boss.arena_center().x, boss.position.z - boss.arena_center().z).length() <= Stage2.PLAZA_RADIUS - boss.radius + 0.01, "a ram stops at the perimeter")
	boss.global_position += Vector3.RIGHT * 500.0
	boss.behave(0.0)
	check(boss.position.distance_to(boss.arena_center()) <= Stage2.PLAZA_RADIUS, "external displacement is clamped too")


func test_circles_the_tank_wherever_it_waits_in_the_plaza() -> void:
	var boss := _boss()
	var tank := boss.player()
	for corner: Vector2 in [Vector2(45.0, 0.0), Vector2(-30.0, -40.0)]:
		tank.global_position = Course.to_world(Stage2.PLAZA_D + corner.x, corner.y)
		boss.global_position = boss.arena_center() - (tank.global_position - boss.arena_center()).normalized() * 40.0
		for _i in 480:
			boss.behave(1.0 / 60.0)
		var nearest := INF
		var farthest := 0.0
		for _i in 240:
			boss.behave(1.0 / 60.0)
			var gap := Vector2(boss.position.x - tank.position.x, boss.position.z - tank.position.z).length()
			nearest = minf(nearest, gap)
			farthest = maxf(farthest, gap)
		check(farthest <= 50.0, "it closes on a tank waiting at %s instead of circling the plaza's middle (%.0f m out)" % [corner, farthest])
		check(nearest >= 15.0, "and circles clear of a ram's run-up (%.0f m)" % nearest)


func test_every_weapon_warns_and_cannon_fires_only_after_aim_is_fixed() -> void:
	var boss := _boss()
	boss.phase = Hovercraft.Phase.STRIPPED
	for kind in [Hovercraft.Attack.GUN, Hovercraft.Attack.CANNON, Hovercraft.Attack.MLRS, Hovercraft.Attack.RAM]:
		var count := World.current.projectiles.size()
		boss._begin_attack(kind)
		var at := boss.global_position
		boss._update_attack(Hovercraft.WIND * Game.telegraph_scale() - 0.01, boss.player())
		check_eq(World.current.projectiles.size(), count, "weapon %d fires nothing during warning" % kind)
		check_near(at.distance_to(boss.position), 0.0, 0.01, "warning does not dash into the player")
		var aim := boss._aim
		boss.player().global_position += Vector3.RIGHT * 10.0
		boss._update_attack(0.02, boss.player())
		check_eq(boss._aim, aim, "the attack stays aimed at the warned spot after a dodge")
		if kind != Hovercraft.Attack.RAM:
			check(World.current.projectiles.size() > count, "the warned weapon fires after its window")
		boss._end_attack()


func test_bow_shell_hits_the_warned_circle_and_a_sideways_dodge_escapes() -> void:
	for dodge in [false, true]:
		var boss := _boss()
		var tank := boss.player()
		tank.invuln = 0.0
		tank.global_position = boss.global_position + Vector3(0, 0, -25)
		tank.global_position.y = Stage2.WATER_LEVEL
		boss._begin_attack(Hovercraft.Attack.CANNON)
		var count := World.current.projectiles.size()
		for i in 30:
			boss.behave(1.0 / 60.0)
		check_eq(tank.hp, tank.max_hp, "the cannon circle warns without doing damage")
		if dodge:
			tank.global_position += Vector3.RIGHT * 15.0
		for i in 35:
			boss.behave(1.0 / 60.0)
		land(World.current, count)
		check(tank.hp == tank.max_hp if dodge else tank.hp < tank.max_hp, "a dodge avoids the actual shell; staying on its circle is punished")
		cleanup()


func test_rear_is_weak_and_ignored_hits_spare_modules() -> void:
	var boss := _boss()
	boss.take_hit(_shell(boss, Vector3.ZERO, 10.0))
	var front := boss.max_hp - boss.hp
	var before := boss.hp
	boss.take_hit(_shell(boss, Vector3(0, 2, 6), 10.0))
	check(boss.hp < before - front, "a rear hit hurts more than a front hit")
	before = boss.hp
	var hit := _shell(boss, Hovercraft.PARTS.laser, 0.0)
	boss.take_hit(hit)
	hit.damage = -20.0
	boss.take_hit(hit)
	boss.invulnerable = true
	hit.damage = 9999.0
	boss.take_hit(hit)
	check_eq(boss.hp, before, "zero, negative and invulnerable hits do not hurt the hull")
	check_eq(boss.parts.laser, 70.0, "ignored hits do not break the emitter")


func test_real_full_charge_staggers_without_skipping_the_encounter() -> void:
	var boss := _boss()
	var tank := boss.player()
	tank.charge_lock = boss
	var from := boss.hit_center() + Vector3(0, 0, -30)
	tank.fire_cannon(from, (boss.hit_center() - from).normalized(), 1.0)
	check(boss.hp > boss.max_hp * 0.5 and boss.hp < boss.max_hp, "one real charged hitscan hurts but does not kill or skip phase one")
	check(boss.is_staggered(), "the actual full-charge hit staggers it")


func test_ram_hits_once_after_warning_and_misses_a_sideways_dodge() -> void:
	var boss := _boss()
	var tank := boss.player()
	tank.global_position = boss.global_position + Vector3(0, 0, -25)
	tank.invuln = 0.0
	boss._begin_attack(Hovercraft.Attack.RAM)
	boss._update_attack(Hovercraft.WIND * Game.telegraph_scale() - 0.01, tank)
	check_eq(tank.hp, tank.max_hp, "the impact lane is safe while warned")
	for i in 60:
		tank.invuln = 0.0
		boss._update_attack(1.0 / 60.0, tank)
	check(tank.hp < tank.max_hp and tank.hp >= tank.max_hp - 35.1, "a tank that stays is rammed once, not once per frame")
	boss._bound()
	tank.hp = tank.max_hp
	tank.global_position = boss.global_position + Vector3(0, 0, -25)
	boss._begin_attack(Hovercraft.Attack.RAM)
	tank.global_position += Vector3.RIGHT * 20.0
	for i in 120:
		boss._update_attack(1.0 / 60.0, tank)
	check_eq(tank.hp, tank.max_hp, "a sideways dodge clears the fixed ram lane")


func test_death_emits_once_and_rewards_without_clearing_stage() -> void:
	var boss := _boss()
	var world := World.current
	var deaths := [0]
	var cleared := [false]
	boss.died.connect(func(_e: Entity) -> void: deaths[0] += 1)
	world.stage_cleared.connect(func() -> void: cleared[0] = true)
	var score := world.stats.score
	boss.take_hit(_shell(boss, Vector3.ZERO, boss.max_hp + 1.0))
	check(not boss.dead, "the killing blow starts death throes")
	boss.behave(1.1)
	check(boss.dead and deaths[0] == 1, "the explosion ends the encounter exactly once")
	check(world.stats.score >= score + boss.score, "the mid-boss awards its score")
	check_eq(world.pickups.size(), 3, "coax, repair and ERA restore the tank")
	check(not cleared[0], "the mid-boss does not clear the whole stage")
	boss.take_hit(_shell(boss, Vector3.ZERO, 9999.0))
	check_eq(deaths[0], 1, "late hits cannot award a second kill")


func test_a_micro_missile_counts_as_one_main_gun_round() -> void:
	var boss := _boss()
	var hit := Hit.make(Hit.Kind.SHELL, Armament.SHELL_DAMAGE, boss.hit_center(), Vector3.FORWARD) # What a micro-missile lands with.
	hit.caliber = Armament.MICRO_CALIBER
	hit.weapon = "cannon"
	hit.source = boss.player()
	var before := boss.hp
	boss.take_hit(hit)
	check(boss.hp < before, "a micro-missile that gets through damages the hull")
	check(before - boss.hp <= Hovercraft.ROUND_DAMAGE * 1.5, "but only as one round (%.0f of %.0f hull)" % [before - boss.hp, boss.max_hp])
