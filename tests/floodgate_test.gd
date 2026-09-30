extends TestCase
## The real arena spawn, module hit volumes, fair warnings, current and clear sequence.

func _boss() -> Floodgate:
	var world := stage("boss", true, 2)
	check(await wait_until(func() -> bool: return world.boss is Floodgate, 60 * 12), "checkpoint reaches the fortress")
	world.player.invulnerable = true
	return world.boss as Floodgate

func _hit_battery(boss: Floodgate, index: int, damage := Floodgate.BATTERY_HP) -> void:
	var hit := Hit.make(Hit.Kind.SHELL, damage, boss.batteries[index].node.global_position + Vector3.UP)
	hit.source = World.current.player
	boss.take_hit(hit)

func _drain(boss: Floodgate) -> void:
	for i in 4:
		_hit_battery(boss, i)

func test_checkpoint_spawns_fortress_in_arena_with_bar_and_music() -> void:
	var silent := Game.silent
	Game.silent = false
	var boss := await _boss()
	check_eq(World.current.rail.mode, Rail.Mode.ARENA, "boss checkpoint enters all-range movement")
	check_near(Course.to_course(boss.global_position).x, Stage2.GATE_D, 0.01, "fortress stands on the reserved footprint")
	check_eq(boss.get_meta("title"), "BOSS_FLOODGATE", "HUD names the fortress")
	check_eq(boss.module_states().size(), 5, "bar shows four batteries and core")
	check_eq(Sfx._music_path, "res://assets/music/boss2.ogg", "director starts boss2")
	Game.silent = silent
	Sfx.stop_music()
	check(boss._pieces.size() > 25, "the facade consists of real independent blocks")
	check_near(boss.global_basis.x.dot(Course.right(Stage2.GATE_D)), 1.0, 0.001, "gate bays face the basin")

func test_each_battery_visibly_warns_before_its_attack() -> void:
	var boss := await _boss()
	boss.set_process(false)
	for i in 4:
		boss._attack_index = i
		boss._attack_timer = 0.0
		boss.behave(0.01)
		var battery := boss.batteries[i]
		check(battery.telegraph > 0.0, "battery %d starts a warning" % i)
		check_eq(battery.attack_count, 0, "battery %d has not fired at warning start" % i)
		for _j in 30:
			boss.behave(1.0 / 60.0)
		check_eq(battery.attack_count, 0, "battery %d allows at least half a second to dodge" % i)
		match battery.kind:
			Floodgate.BatteryKind.FLAK:
				check(absf(battery.barrels.rotation.z) > 0.1, "only the flak barrels visibly spin up")
			Floodgate.BatteryKind.ATGM:
				check(battery.target != Vector3.ZERO, "designator has a tracked target before launch")
			Floodgate.BatteryKind.MORTAR:
				check(battery.target != Vector3.ZERO, "impact circle is fixed before the mortar fires")
			Floodgate.BatteryKind.SPORE:
				check(battery.sac.scale.x > 1.15, "spore sac swells before firing")
		for _j in 50:
			boss.behave(1.0 / 60.0)
		check_eq(battery.attack_count, 1, "battery %d fires after its warning" % i)
		battery.burst = 0

func test_each_broken_battery_lowers_query_and_mesh_by_one_step() -> void:
	var boss := await _boss()
	var definition := Course.stage as Stage2
	var sample := Course.to_world(Stage2.ARENA_CENTER_D, 68)
	for i in 4:
		var before := definition.arena_level
		_hit_battery(boss, i)
		await frames(60)
		check(definition.arena_level < before and definition.arena_level > Floodgate.DROP_LEVELS[i], "gate %d animates, not teleports, down" % i)
		check_near(Water.surface_at(sample), definition.arena_level, 0.001, "water query follows gate %d mid-step" % i)
		await frames(70)
		check_near(definition.arena_level, Floodgate.DROP_LEVELS[i], 0.001, "gate %d reaches its own step" % i)
		check_near(World.current.terrain._waters[1].position.y, definition.arena_level, 0.001, "rendered basin follows gate %d" % i)
		if i < 3:
			check_eq(boss.phase, Floodgate.Phase.GATES, "remaining batteries keep phase one")
	check_eq(boss.phase, Floodgate.Phase.DRAINED, "all four broken gates begin drained phase")
	check(boss._core.visible and not boss.core_exposed, "water reveals a protected root before exposure")
	check_eq(boss._torrents.size(), 4, "each bay gets its own torrent")

func test_module_shapes_route_real_projectiles_and_immune_concrete() -> void:
	var boss := await _boss()
	boss.set_process(false)
	var battery := boss.batteries[2]
	var center := battery.node.global_position + Vector3.UP
	var from := center + boss.global_basis.z * 15
	var ray_end := center - boss.global_basis.z * 15
	check(boss.hit_test(from, ray_end) >= 0.0, "battery has an actual shot volume")
	var shell := World.current.spawn_projectile(Entity.Team.PLAYER, from, (center - from).normalized() * 100, "shell")
	shell.hit = Hit.make(Hit.Kind.SHELL, 100, from)
	shell.hit.source = World.current.player
	await frames(15)
	check(battery.hp < Floodgate.BATTERY_HP, "a moving projectile damages the aimed module")
	check_eq(boss.batteries[1].hp, Floodgate.BATTERY_HP, "neighboring volume does not steal that hit")
	var before := boss.hp
	boss.take_hit(Hit.make(Hit.Kind.SHELL, 99999, boss.to_global(Vector3(40, 20, 4))))
	check_eq(boss.hp, before, "concrete is not a hidden damage shortcut")

func test_intake_really_moves_idle_tank_but_full_strafe_escapes() -> void:
	var boss := await _boss()
	var tank := World.current.player
	var center := boss._intakes[0].global_position
	var start := center + (Course.to_world(Stage2.ARENA_CENTER_D, 0) - center).normalized() * 15
	start.y = Course.height_at(start)
	check_eq(boss.current_force_for(start), Vector3.ZERO, "phase one has no current")
	_drain(boss)
	tank.global_position = start
	tank.local_velocity = Vector2.ZERO
	var before := Vector2(start.x - center.x, start.z - center.z).length()
	await frames(30)
	var pulled := Vector2(tank.global_position.x - center.x, tank.global_position.z - center.z).length()
	check(pulled < before - 1, "idle tank is visibly carried toward the intake")
	var away := tank.global_position - center
	away.y = 0
	away = away.normalized()
	var cam_forward := -World.current.camera.global_basis.z
	cam_forward.y = 0
	cam_forward = cam_forward.normalized()
	var right := cam_forward.cross(Vector3.UP)
	var input := Vector2(away.dot(right), away.dot(cam_forward)).normalized()
	for _i in 60:
		tank._move_arena(1.0 / 60.0, input)
	var escaped := Vector2(tank.global_position.x - center.x, tank.global_position.z - center.z).length()
	check(escaped > pulled + 8, "full movement out-drives the real current even in the wet basin")
	check_near(boss.current_force_for(start).y, 0, 0.001, "current never pulls through the floor")

func test_drained_spawns_then_core_exposes_naturally() -> void:
	var boss := await _boss()
	var point := boss.model.global_transform * Floodgate.CORE_OFFSET
	boss.take_hit(Hit.make(Hit.Kind.SHELL, 99999, point))
	check_eq(boss.core_hp, Floodgate.CORE_HP, "core cannot take damage in gates phase")
	_drain(boss)
	boss.take_hit(Hit.make(Hit.Kind.SHELL, 99999, point))
	check_eq(boss.core_hp, Floodgate.CORE_HP, "revealed sheath still protects the root in drained phase")
	await frames(120)
	check(World.current.enemies.any(func(e: Entity) -> bool: return e is CanalLeech), "root releases leeches into remaining moat water")
	check(World.current.enemies.any(func(e: Entity) -> bool: return e is GnatSwarm), "vents release gnat swarms")
	check(World.current.enemies.any(func(e: Entity) -> bool: return e.get_script() == load(Director.ENEMY_SCRIPTS.crawler)), "root releases crawlers")
	check(await wait_until(func() -> bool: return boss.core_exposed, 60 * 13), "drained phase opens naturally without test exposure")
	check_eq(boss.phase, Floodgate.Phase.CORE, "exposed core enables the desperate geyser pattern")
	boss.take_hit(Hit.make(Hit.Kind.SHELL, 100, boss.model.global_transform * Floodgate.CORE_OFFSET))
	check(boss.core_hp < Floodgate.CORE_HP, "exposed root takes aimed damage")

func test_geyser_warns_then_hurts_inside_circle_only_and_cancels_on_death() -> void:
	var boss := await _boss()
	_drain(boss)
	boss.expose_core()
	boss.set_process(false)
	var tank := World.current.player
	tank.invulnerable = false
	var center := Course.ground_at(Stage2.ARENA_CENTER_D, 0)
	tank.global_position = center
	var before := tank.hp
	boss._geyser_time = 0
	boss.behave(0.01)
	check_eq(boss._geysers.size(), 1, "a geyser first queues its marked circle")
	check_eq(tank.hp, before, "warning does no damage")
	boss.behave(0.5)
	check_eq(tank.hp, before, "geyser allows half a second to leave")
	boss.behave(0.8)
	check(tank.hp < before, "eruption damages a tank inside its marked circle")
	tank.hp = before
	tank.global_position = center + Vector3(4.1, 0, 0)
	boss.geyser_impact(center)
	check_eq(tank.hp, before, "hull overlap outside the visible circle does not hurt")
	boss._geyser_time = 0
	boss.behave(0.01)
	boss.die(Hit.new())
	boss.behave(2)
	check_eq(tank.hp, before, "death cancels pending geysers")

func test_core_death_drains_sunrises_collapses_and_clears_once() -> void:
	var boss := await _boss()
	_drain(boss)
	boss.expose_core()
	var cleared := [0]
	World.current.stage_cleared.connect(func() -> void: cleared[0] += 1)
	var hit := Hit.make(Hit.Kind.SHELL, Floodgate.CORE_HP, boss.model.global_transform * Floodgate.CORE_OFFSET)
	hit.source = World.current.player
	boss.take_hit(hit)
	boss.take_hit(hit)
	check(boss.dead, "root death ends the encounter")
	check_eq((Course.stage as Stage2).dawn, 1.0, "sunrise follows root death")
	check(not boss.intake_active, "suction stops when the root dies")
	check_eq(World.current.stats.kills, 1, "fortress scores one death, not each repeated hit")
	await frames(150)
	check_eq((Course.stage as Stage2).arena_level, -3.0, "final animation drains below the basin floor")
	check_eq(Water.surface_at(Course.to_world(Stage2.ARENA_CENTER_D, 60)), -INF, "fully drained basin is dry")
	check(boss._pieces.any(func(p: Dam.Piece) -> bool: return p.state == Dam.State.LANDED), "real facade blocks fall and land")
	check_eq(cleared[0], 0, "results wait while the ruin plays")
	check(await wait_until(func() -> bool: return cleared[0] > 0, 60 * 6), "Stage 1-style delay clears Stage 2")
	check_eq(cleared[0], 1, "stage clears only once")
