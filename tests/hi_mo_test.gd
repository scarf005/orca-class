extends TestCase
## Bay boss: fair wind-ups, a sideways escape and heavy-shell reversals.


func _boss() -> HiMo:
	var world := stage("", false, 2)
	world.rail.d = Stage2.BAY_D
	world.rail.mode = Rail.Mode.ARENA
	world.director._next_event = world.director.events.size()
	var boss := HiMo.new()
	boss.position = Course.ground_at(Stage2.BAY_D, 0.0)
	world.add_enemy(boss)
	world.boss = boss
	world.player.global_position = boss.position + Vector3(0, 0, -35)
	world.player.global_position.y = Course.height_at(world.player.global_position)
	boss._next_attack = 1000.0
	return boss


func _shell(boss: HiMo, at: Vector3, damage: float, charged := false) -> void:
	var hit := Hit.make(Hit.Kind.SHELL, damage, at, Vector3.BACK)
	hit.caliber = 100
	hit.power = 1.0 if charged else 0.0
	hit.source = _world.player
	boss.take_hit(hit)


func _advance(boss: HiMo, seconds: float) -> void:
	for _i in ceili(seconds * 60.0):
		boss.behave(1.0 / 60.0)


func test_phase_boundaries_and_music() -> void:
	var boss := _boss()
	check_eq(boss.phase, HiMo.Phase.SKATER, "full hull starts skating")
	check(boss.music_track().ends_with("stage2_boss.ogg"), "first boss theme")
	_shell(boss, boss.hit_center(), boss.max_hp * 0.35)
	check_eq(boss.phase, HiMo.Phase.STRIPPED, "65 percent enters phase two")
	check(boss._plates.is_empty(), "armor tears off at the transition")
	check(boss.music_track().ends_with("stage2_boss_phase2.ogg"), "stripped phase changes theme")
	_shell(boss, boss.hit_center(), boss.max_hp * 0.35)
	check_eq(boss.phase, HiMo.Phase.DESPERATE, "30 percent enters phase three")
	check(boss.legs_lost() >= 1, "last phase visibly fights on a broken wheel leg")
	check(boss.skate_speed() > (HiMo.SPEED[HiMo.Phase.STRIPPED] as float), "desperate drive is faster despite the first broken wheel")
	check(boss.music_track().ends_with("stage2_boss_phase2.ogg"), "last phase keeps the second theme")
	_shell(boss, boss.hit_center(), -100.0)
	check_eq(boss.phase, HiMo.Phase.DESPERATE, "ignored hits cannot reverse phases")


func test_eight_real_charged_shells_clear_all_phases() -> void:
	var boss := _boss()
	var damage := Armament.SHELL_DAMAGE * Armament.APHE_DAMAGE.y * Armament.SHELL_DAMAGE_SCALE
	for i in 7:
		_shell(boss, boss.hit_center(), damage, true)
		check(not boss.dead, "a full charge advances the fight without skipping every phase")
		if i == 2:
			check_eq(boss.phase, HiMo.Phase.STRIPPED, "third full charge strips armor")
		if i == 5:
			check_eq(boss.phase, HiMo.Phase.DESPERATE, "sixth full charge exposes the last phase")
	_shell(boss, boss.hit_center(), damage, true)
	check(boss.dead, "eighth actual APHE charge finishes the boss, with no recovery gate")


func test_actual_music_player_switches() -> void:
	var boss := _boss()
	var silent := Game.silent
	Game.silent = false
	boss._play_music()
	check_eq(Sfx._music_path, boss.music_track(), "existing crossfade starts the bay theme")
	_shell(boss, boss.hit_center(), boss.max_hp * 0.36)
	check_eq(Sfx._music_path, boss.music_track(), "hull transition plays the phase-two track")
	Sfx.stop_music()
	Game.silent = silent


func test_all_attacks_warn_before_projectiles_or_contact() -> void:
	for attack: HiMo.Attack in [HiMo.Attack.GUN, HiMo.Attack.MISSILES, HiMo.Attack.RAIL, HiMo.Attack.CHARGE, HiMo.Attack.STOMP, HiMo.Attack.SWEEP]:
		var boss := _boss()
		boss.phase = HiMo.Phase.DESPERATE
		var tank := _world.player
		if attack in [HiMo.Attack.CHARGE, HiMo.Attack.SWEEP]:
			tank.global_position = boss.global_position + Vector3(0, 0, -8)
		var before := tank.hp
		var shots := _world.projectiles.size()
		boss._begin_attack(attack)
		_advance(boss, (HiMo.WIND[attack] as float) * Game.telegraph_scale() * 0.8)
		check(boss.telegraphing(), "%s is still warning" % attack)
		check_eq(_world.projectiles.size(), shots, "%s has not fired during warning" % attack)
		check_eq(tank.hp, before, "%s cannot hurt during warning" % attack)
		_advance(boss, 1.5)
		if attack in [HiMo.Attack.GUN, HiMo.Attack.MISSILES, HiMo.Attack.RAIL]:
			check(_world.projectiles.size() > shots, "%s fires after warning" % attack)
		else:
			check(tank.hp < before, "%s contact hurts after warning" % attack)


func test_missiles_home_gently_and_ciws_can_intercept() -> void:
	var boss := _boss()
	boss._begin_attack(HiMo.Attack.MISSILES)
	_advance(boss, 1.2 * Game.telegraph_scale())
	check(not _world.projectiles.is_empty(), "rack launches missiles")
	for shot: Projectile in _world.projectiles:
		check(shot.interceptable, "CIWS can select every missile")
		check(shot.turn_rate > 0.0 and shot.turn_rate < 1.0, "gentle homing leaves room to evade")
		check_eq(shot.homing_target, _world.player, "missile follows the tank")
	var missile := _world.projectiles[0]
	_world.player.mount_rws()
	missile.global_position = _world.player.hit_center() + Vector3(0, 0, -8)
	missile.velocity = (_world.player.global_position - missile.global_position).normalized() * 65.0
	for _i in 30:
		_world.player._update_ciws(1.0 / 60.0)
	check(missile.is_queued_for_deletion(), "actual CIWS destroys the approaching missile")


func test_wheel_shots_cripple_and_two_losses_crawl() -> void:
	var boss := _boss()
	var speed := boss.skate_speed()
	for i in 2:
		var wheel: Node3D = boss._legs[i].wheel
		var at := wheel.global_position
		check(boss.hit_test(at + Vector3.UP * 3.0, at - Vector3.UP * 3.0) >= 0.0, "low aimed shell can hit a wheel")
		_shell(boss, at, HiMo.LEG_HP, true)
		check_eq(boss.legs_lost(), i + 1, "heavy shell tears off the targeted wheel only")
		check(boss.skate_speed() < speed, "each loss slows the walker")
		speed = boss.skate_speed()
	boss.stagger = 0.0
	var before := boss.position
	_advance(boss, 0.5)
	check(boss.position.distance_to(before) > 0.1, "two lost legs crawl rather than becoming a stationary sponge")
	check(boss._body.position.y < 2.2, "collapse visibly lowers the hull")
	boss.phase = HiMo.Phase.DESPERATE
	for _i in 12:
		boss._choose_attack()
		check(boss._attack not in [HiMo.Attack.CHARGE, HiMo.Attack.STOMP, HiMo.Attack.SWEEP], "crawl cannot use intact-leg attacks")


func test_charged_shot_interrupts_and_sheds_armor() -> void:
	var boss := _boss()
	boss._begin_attack(HiMo.Attack.RAIL)
	_shell(boss, boss.hit_center(), 100.0, true)
	check_eq(boss._attack, HiMo.Attack.NONE, "full charge cancels the warned heavy shot")
	check_eq(boss._plates.size(), 1, "one charged hit visibly knocks a plate off")
	check(boss.hp < boss.max_hp, "armor loss does not absorb hull damage")
	boss.stagger = 0.0
	boss._next_attack = 0.0
	boss.tick(1.1)
	check(not boss.is_staggered(), "stagger expires instead of perpetually renewing itself")


func test_shell_and_its_splash_count_once() -> void:
	var boss := _boss()
	_shell(boss, boss.hit_center(), 100.0)
	var hp := boss.hp
	var splash := Hit.make(Hit.Kind.BLAST, 70.0, boss.hit_center())
	splash.weapon = "cannon"
	splash.caliber = 100
	boss.take_hit(splash)
	check_eq(boss.hp, hp, "same shell's splash does not double hull damage")
	boss.age += Gunship.SHELL_WINDOW + 0.01
	boss.take_hit(splash)
	check(boss.hp < hp, "a later missed shell's splash still hurts")


func test_arena_clamps_skating_charge_and_hops() -> void:
	var boss := _boss()
	var center := Course.to_world(Stage2.BAY_D, 0.0)
	boss.position = center + Vector3(500, 0, 0)
	boss.behave(0.1)
	check(Vector2(boss.position.x - center.x, boss.position.z - center.z).length() <= Stage2.BAY_RADIUS - boss.radius + 0.01, "even an outside spawn is brought into the bay")
	boss._begin_attack(HiMo.Attack.CHARGE)
	_advance(boss, 5.0)
	check(Vector2(boss.position.x - center.x, boss.position.z - center.z).length() <= Stage2.BAY_RADIUS - boss.radius + 0.01, "drift charge stays inside")
	boss._start_hop(center + Vector3(-500, 0, 0))
	for _i in 60:
		boss.behave(1.0 / 60.0)
		check(Vector2(boss.position.x - center.x, boss.position.z - center.z).length() <= Stage2.BAY_RADIUS - boss.radius + 0.01, "every airborne hop sample stays inside")


func test_charge_stops_at_cover_without_hidden_contact() -> void:
	var boss := _boss()
	var tank := _world.player
	var mid := boss.position.lerp(tank.position, 0.5)
	Course.structure_boxes.append({"pose": Transform3D(Basis(), mid), "size": Vector3(24, 6, 3)})
	var hp := tank.hp
	boss._begin_attack(HiMo.Attack.CHARGE)
	_advance(boss, 2.0 * Game.telegraph_scale())
	check_eq(tank.hp, hp, "container stops the drift instead of letting it ram through")
	check(boss.position.distance_to(tank.position) > boss.radius + tank.radius, "charge remains on the near side of cover")
	Course.structure_boxes.pop_back()


func test_hull_shots_leave_wheels_and_front_shrugs_mg() -> void:
	var boss := _boss()
	_shell(boss, boss.hit_center(), 100.0)
	check_eq(boss.legs_lost(), 0, "hull hit cannot tear off a distant wheel")
	boss._begin_attack(HiMo.Attack.GUN)
	_advance(boss, 1.1 * Game.telegraph_scale())
	var tank := _world.player
	var hp := tank.hp
	land(_world, 0)
	check(tank.hp > hp - 10.0, "flat 30 mm bursts glance off the tank's armor, at most one round biting")


func test_cover_blocks_guns_and_melee() -> void:
	var boss := _boss()
	var tank := _world.player
	var mid := boss.position.lerp(tank.position, 0.5)
	Course.structure_boxes.append({"pose": Transform3D(Basis(), mid), "size": Vector3(24, 10, 3)})
	for attack: HiMo.Attack in [HiMo.Attack.GUN, HiMo.Attack.MISSILES, HiMo.Attack.RAIL]:
		boss._begin_attack(attack)
		boss._update_attack(2.0, tank)
		check(_world.projectiles.is_empty(), "hard cover cancels %s rather than firing through it" % attack)
	var hp := tank.hp
	boss._area_hit(tank, 50.0, 100.0)
	check_eq(tank.hp, hp, "container shelters the tank from an impact wave")
	Course.structure_boxes.pop_back()
	boss._begin_attack(HiMo.Attack.GUN)
	boss._update_attack(2.0, tank)
	check(not _world.projectiles.is_empty(), "clear sight restores gunfire")


func test_hops_clear_cover_and_land_on_roof() -> void:
	var boss := _boss()
	var from := boss.position
	var roof := from + Vector3(20, 0, 0)
	Course.structure_boxes.append({"pose": Transform3D(Basis(), roof), "size": Vector3(8, 6, 12)})
	boss._start_hop(roof)
	boss.behave(0.5)
	check(boss.position.y > roof.y + 6.0, "jump rises above the container roof")
	boss.behave(0.5)
	check_near(boss.position.y, roof.y + 6.0, 0.01, "wheel feet land on cover, not inside it")
	Course.structure_boxes.pop_back()


func test_impact_falloff_and_circle_boundary() -> void:
	var boss := _boss()
	var tank := _world.player
	tank.position = boss.position + Vector3(0, 0, HiMo.STOMP_REACH)
	var hp := tank.hp
	boss._area_hit(tank, HiMo.STOMP_REACH, 40.0)
	check_eq(tank.hp, hp, "outside and exact ring edge are safe")
	tank.position = boss.position + Vector3(0, 0, 2)
	boss._area_hit(tank, HiMo.STOMP_REACH, 40.0)
	var close_damage := hp - tank.hp
	tank.hp = hp
	tank.position = boss.position + Vector3(0, 0, 10)
	boss._area_hit(tank, HiMo.STOMP_REACH, 40.0)
	check(hp - tank.hp < close_damage, "impact falls off toward the ring edge")


func test_rail_lock_allows_lateral_escape() -> void:
	var boss := _boss()
	var tank := _world.player
	boss._begin_attack(HiMo.Attack.RAIL)
	_advance(boss, 0.9 * Game.telegraph_scale())
	var aim := boss._aim
	tank.global_position += Vector3.RIGHT * 20.0
	_advance(boss, 0.4 * Game.telegraph_scale())
	check_eq(boss._aim, aim, "late lateral dash cannot be tracked by the locked laser")
	var hp := tank.hp
	land(_world, 0)
	check_eq(tank.hp, hp, "locked fast shell misses the lateral escape")


func test_director_spawns_bay_boss_and_deferred_theme() -> void:
	_boss().despawn()
	await frames(2) # The real Director updates the section before firing its boss event.
	var silent := Game.silent
	Game.silent = false
	_world.director._start_boss({"kind": "hi_mo"})
	await frames(2)
	var boss := _world.boss as HiMo
	check(boss != null, "registered Director path creates HiMo")
	check_eq(_world.rail.mode, Rail.Mode.ARENA, "Director enters all-range movement")
	check_eq(Sfx._music_path, boss.music_track(), "deferred bay theme replaces Director's stage-one default")
	Sfx.stop_music()
	Game.silent = silent


func test_death_clears_boss_and_bar() -> void:
	var boss := _boss()
	var hidden: Array[bool] = []
	_world.boss_changed.connect(func(entity: Entity) -> void: hidden.append(entity == null))
	_shell(boss, boss.hit_center(), boss.max_hp * 2.0, true)
	check(boss.dead, "lethal hull hit kills without phase-gated recovery")
	check(_world.boss == null, "death clears active boss reference")
	check(not boss.boss, "death clears the boss flag")
	check(hidden.has(true), "death hides the boss bar")
