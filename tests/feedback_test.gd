extends TestCase
## Confirm accepted player damage, preserve kill markers, and recover visual recoil.


func _target(world: World) -> Enemy:
	var enemy := Ugv.new()
	enemy.position = Course.ground_at(world.rail.d + 80.0, 0.0)
	world.add_enemy(enemy)
	enemy.hp = 100.0
	return enemy


func _shot(world: World, enemy: Enemy, damage := 1.0) -> Hit:
	var hit := Hit.make(Hit.Kind.BULLET, damage, enemy.hit_center(), Vector3.RIGHT)
	hit.caliber = 20
	hit.source = world.player
	return hit


func test_only_accepted_player_hits_are_confirmed() -> void:
	var world := stage()
	var enemy := _target(world)
	var events: Array[bool] = []
	world.hit_confirmed.connect(func(killed: bool) -> void: events.append(killed))
	enemy.take_hit(_shot(world, enemy, 0.0))
	enemy.invulnerable = true
	enemy.take_hit(_shot(world, enemy))
	enemy.invulnerable = false
	var hostile := _shot(world, enemy)
	hostile.source = enemy
	enemy.take_hit(hostile)
	check(events.is_empty(), "zero damage, invulnerability and hostile fire do not confirm player hits")
	enemy.take_hit(_shot(world, enemy))
	check_eq(events, [false], "accepted player damage confirms one hit")


func test_hit_flashes_recoils_and_recovers() -> void:
	var world := stage()
	var enemy := _target(world)
	var origin := enemy.global_position
	enemy.take_hit(_shot(world, enemy))
	check(enemy._flash > 0.0, "accepted damage starts a flash")
	check(enemy.model.position.x > 0.0, "model recoils along the incoming shot")
	check_eq(enemy.global_position, origin, "visual recoil preserves the AI position")
	for mesh in enemy._meshes:
		check_eq(mesh.material_overlay, Entity._flash_material, "all tracked meshes flash")
	var offset := enemy.model.position.length()
	enemy.tick(0.1)
	check(enemy.model.position.length() < offset, "recoil settles during normal enemy movement")
	check_eq(world._hitstop, 0.0, "ordinary nonlethal gun hits do not stop time")


func test_kill_confirms_once_and_stops_time() -> void:
	var world := stage()
	var enemy := _target(world)
	var events: Array[bool] = []
	world.hit_confirmed.connect(func(killed: bool) -> void: events.append(killed))
	var hit := _shot(world, enemy, 1000.0)
	enemy.take_hit(hit)
	enemy.take_hit(hit)
	check_eq(events, [true], "a lethal hit confirms once, further hits on the corpse do nothing")
	check(world._hitstop > 0.0, "even a machine-gun kill briefly stops time")


func test_followup_hits_preserve_kill_marker() -> void:
	var world := stage()
	var hud := Hud.new()
	hud.world = world
	world.add_child(hud)
	hud._on_hit_confirmed(true)
	var duration := hud._kill_marker
	hud._on_hit_confirmed(false)
	check_eq(hud._kill_marker, duration, "a later hit does not replace the kill marker")
	check(hud._hit_marker > 0.0, "the later hit still refreshes its own marker")


func test_detached_wreck_does_not_keep_hit_flash() -> void:
	var world := stage()
	var enemy := _target(world)
	var meshes := enemy._meshes.duplicate()
	enemy.max_hp = enemy.hp
	enemy.take_hit(_shot(world, enemy, enemy.hp + 1.0))
	for mesh: GeometryInstance3D in meshes:
		check(mesh.material_overlay != Entity._flash_material, "detached wreck restores its material before the enemy stops ticking")


func test_dash_afterimage_skips_torn_off_meshes() -> void:
	var world := stage()
	var tank := world.player
	var ghosts := func() -> int:
		var before: int = world.fx._transients.size()
		world.fx.afterimage(tank._meshes, Color.RED)
		return world.fx._transients.size() - before
	var intact: int = ghosts.call()
	check(intact > 0, "the hull leaves ghosts")
	var torn := MeshInstance3D.new()
	torn.mesh = BoxMesh.new()
	tank.model.add_child(torn)
	tank._meshes.append(torn)
	torn.free()
	check_eq(ghosts.call(), intact, "a freed mesh in the list is skipped, the rest still ghost")


func test_particle_compaction_keeps_survivors_visible() -> void:
	var world := stage()
	var fx := world.fx
	for i in 100:
		fx.spawn(Fx.Kind.GLOW, Vector3(i, 2, 0), Vector3.ZERO, 0.05 if i % 2 == 0 else 1.0, 1.0, Palette.MIST)
	fx._process(0.1)
	var mesh: MultiMesh = fx._multimeshes[Fx.Kind.GLOW]
	check_eq(mesh.visible_instance_count, 50, "expired particles leave the visible range")
	check_eq(fx._pools[Fx.Kind.GLOW][0].position.x, 1.0, "the first surviving particle stays in order")
	check_eq(fx._pools[Fx.Kind.GLOW][-1].position.x, 99.0, "the last surviving particle stays in order")
	fx._process(1.0)
	check_eq(mesh.visible_instance_count, 0, "expired particles are hidden")


func test_flash_lights_leave_rendering_when_dark_and_reactivate_on_reuse() -> void:
	var fx := Fx.new()
	add_child(fx)
	check(fx._flashes.all(func(light: OmniLight3D) -> bool: return not light.visible), "unused flash lights do not enter light culling")
	fx.light_flash(Vector3.ONE, 3.0)
	var light := fx._flashes[0]
	check(light.visible, "an active flash still lights the scene")
	fx._process(0.05)
	check_near(light.light_energy, 1.5, 0.00001, "visibility does not alter the fade rate")
	check(light.visible, "a fading flash stays visible until it reaches zero")
	fx._process(0.05)
	check(not light.visible and light.light_energy == 0.0, "an extinguished flash leaves rendering immediately")
	fx.light_flash(Vector3.ZERO, 1.0)
	check(light.visible and light.light_energy == 1.0, "the pooled light reactivates on reuse")
	fx.free()
