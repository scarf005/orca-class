extends TestCase
## The color language: warm is the tank's, hot pink-red is the enemy's, cyan is loot.


func test_shots_are_colored_by_team_not_weapon() -> void:
	check(World.team_color(Entity.Team.ENEMY, "mortar", Palette.FUNGUS) == Palette.HOSTILE, "enemy spit is hostile red, not fungus green")
	check(World.team_color(Entity.Team.ENEMY, "orb", Color(0, 0, 0, 0)) == Palette.HOSTILE, "enemy bullets are hostile")
	for shape in ["bullet", "shell", "dart", "pellet", "fragment"]:
		var color := World.team_color(Entity.Team.PLAYER, shape, Palette.CYAN)
		check(color in [Palette.FRIENDLY, Palette.BUTTER], "player %s is warm" % shape)
	check(World.team_color(Entity.Team.PLAYER, "fire", Palette.PEACH) == Palette.PEACH, "flames keep fire colors")
	for spec: Dictionary in Armament.GUNS.values():
		check(spec.color != Palette.HOSTILE, "no coax gun fires in the hostile color")


func test_spawned_projectiles_follow_the_language() -> void:
	var world := stage()
	var enemy_shot := world.spawn_projectile(Entity.Team.ENEMY, Vector3.ZERO, Vector3.FORWARD, "orb", Palette.CORAL)
	check(enemy_shot.color == Palette.HOSTILE, "an enemy shot asked for coral still spawns hostile")
	var shell := world.spawn_projectile(Entity.Team.PLAYER, Vector3.ZERO, Vector3.FORWARD, "shell", Palette.HOT)
	check(shell.color != Palette.HOSTILE, "a HEAT shell never looks like enemy fire")


func test_enemy_shot_cores_are_white_hot_and_bigger_than_the_tanks() -> void:
	var core_color := func(mesh: Mesh) -> Color:
		var best := Color.BLACK
		for c: Color in mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
			best = c if c.get_luminance() > best.get_luminance() else best
		return best
	for shape in ["bullet", "orb"]:
		var enemy := World._projectile_meshes(shape, Palette.HOSTILE, true)[0]
		var friendly := World._projectile_meshes(shape, Palette.HOSTILE, false)[0]
		var brightest: Color = core_color.call(enemy)
		check(brightest.r > 0.9 and brightest.g > 0.8 and brightest.b > 0.8, "%s enemy core is white-ish (%s)" % [shape, brightest])
		check(enemy.get_aabb().size.x > friendly.get_aabb().size.x * 1.3, "%s enemy core is noticeably larger" % shape)


func test_enemy_shot_halos_flicker_out_of_step() -> void:
	var world := stage()
	var sky := Vector3(0.0, 400.0, 0.0)
	var a := world.spawn_projectile(Entity.Team.ENEMY, sky, Vector3.ZERO, "bullet")
	var b := world.spawn_projectile(Entity.Team.ENEMY, sky, Vector3.ZERO, "bullet")
	var scales: Array[float] = []
	for _i in 12:
		a.step(0.02)
		scales.append(a.halo.scale.x)
		await frames(1)
	check(scales.max() - scales.min() > 0.1, "the halo pulses over time")
	check(not is_equal_approx(a._phase, b._phase), "each shot has its own phase")


func test_actors_are_outlined_by_class_and_pickups_stand_in_a_beacon() -> void:
	var world := stage()
	var ugv := Ugv.new()
	ugv.position = Course.ground_at(world.rail.d + 60.0, 0.0)
	world.add_enemy(ugv)
	ugv.invulnerable = true
	await frames(1)
	var on := func(root: Node, bits: int) -> bool:
		var meshes := root.find_children("*", "MeshInstance3D", true, false)
		return not meshes.is_empty() and meshes.all(func(m: MeshInstance3D) -> bool: return m.layers & bits)
	check(on.call(ugv, ActorLayer.HOSTILE), "every enemy mesh is on the hostile outline layer")
	check(on.call(world.player.model, ActorLayer.FRIENDLY), "the tank is on the friendly outline layer")
	var pickup := world.spawn_pickup("heat", Course.ground_at(world.rail.d + 20.0, 0.0))
	check(on.call(pickup, ActorLayer.LOOT), "pickups are on the loot outline layer")
	check(pickup.get_children().any(func(n: Node) -> bool: return n is MeshInstance3D and (n as MeshInstance3D).mesh == Pickup._pillar_mesh()), "pickups stand in a cyan beacon")
	var shot := world.spawn_projectile(Entity.Team.ENEMY, Vector3.ZERO, Vector3.FORWARD, "orb")
	var core := shot.get_child(0) as MeshInstance3D
	check(not (core.layers & ActorLayer.HOSTILE), "enemy shots carry no enemy rim, only enemies do")
	check(on.call(shot, ActorLayer.HOSTILE_SHOT), "every enemy shot mesh, halo too, is on the orange shot rim layer")
	check(core.layers & ActorLayer.LAYER, "enemy shots stay on the actor layer, undithered")
	check(shot.halo != null, "enemy shots have a flickering halo")
	var player_shot := world.spawn_projectile(Entity.Team.PLAYER, Vector3.ZERO, Vector3.FORWARD, "orb")
	check(player_shot.halo == null, "the tank's shots do not twinkle")
	var player_meshes := player_shot.find_children("*", "MeshInstance3D", true, false)
	check(player_meshes.all(func(m: MeshInstance3D) -> bool: return not (m.layers & (ActorLayer.HOSTILE_SHOT | ActorLayer.HOSTILE))), "the tank's shots wear no rim")
	check(player_meshes.all(func(m: MeshInstance3D) -> bool: return m.layers & ActorLayer.LAYER), "but stay undithered")
	check(not (ActorLayer.HOSTILE_SHOT & (ActorLayer.LAYER | ActorLayer.HOSTILE | ActorLayer.FRIENDLY | ActorLayer.LOOT)), "the shot rim class has a render layer of its own")
	var view := DitherView.new()
	add_child(view)
	await frames(1)
	check(view.class_masks.size() == 3, "the final pass has an outline mask for enemies, pickups and enemy shots")
	check_eq(DitherView.OUTLINED[2], ActorLayer.HOSTILE_SHOT, "the third mask is the enemy shots")
	check_eq(DitherView.OUTLINE_COLORS[2], Palette.HOSTILE_SHOT_RIM, "their rim is the shot orange")
	check(DitherView.OUTLINE_COLORS[2] != Palette.FRIENDLY and DitherView.OUTLINE_COLORS[2] != Palette.HOSTILE, "distinct from the amber tracers and the enemy red")
	check(view.class_masks.all(func(v: SubViewport) -> bool: return v.size == DitherView.MASK_RESOLUTION), "every class mask renders at half resolution")
	check(view.class_masks[2].get_child(0).cull_mask == ActorLayer.HOSTILE_SHOT, "the shot mask draws only shots")
	check(view.viewport.size == Vector2i(960, 540), "the 3D view renders at 960x540")
	view.queue_free()


func test_outline_masks_sleep_until_their_class_is_present() -> void:
	_world = World.new()
	add_child(_world)
	var world := _world
	var view := DitherView.new()
	add_child(view)
	view._process(0.0)
	check_eq(view.class_masks[0].render_target_update_mode, SubViewport.UPDATE_DISABLED, "empty hostile mask does not render")
	check_eq(view.class_masks[1].render_target_update_mode, SubViewport.UPDATE_DISABLED, "empty loot mask does not render")
	check_eq(view.class_masks[2].render_target_update_mode, SubViewport.UPDATE_DISABLED, "empty shot mask does not render")
	var shot := world.spawn_projectile(Entity.Team.ENEMY, Vector3.ZERO, Vector3.FORWARD, "orb")
	view._process(0.0)
	check_eq(view.class_masks[2].render_target_update_mode, SubViewport.UPDATE_ALWAYS, "enemy shots wake the shot mask")
	check_eq(view.class_masks[0].render_target_update_mode, SubViewport.UPDATE_DISABLED, "but not the enemy mask")
	var player_shot := world.spawn_projectile(Entity.Team.PLAYER, Vector3.ZERO, Vector3.FORWARD, "orb")
	shot.queue_free()
	await frames(1)
	view._process(0.0)
	check_eq(view.class_masks[2].render_target_update_mode, SubViewport.UPDATE_DISABLED, "the tank's own shots do not wake it")
	if is_instance_valid(player_shot):
		player_shot.queue_free()
	shot = world.spawn_projectile(Entity.Team.ENEMY, Vector3.ZERO, Vector3.FORWARD, "orb")
	view._process(0.0)
	var pickup := world.spawn_pickup("heat", Vector3.ZERO)
	view._process(0.0)
	check_eq(view.class_masks[1].render_target_update_mode, SubViewport.UPDATE_ALWAYS, "pickups wake the loot mask")
	shot.queue_free()
	pickup.queue_free()
	await frames(1)
	view._process(0.0)
	check_eq(view.class_masks[2].render_target_update_mode, SubViewport.UPDATE_DISABLED, "shot mask sleeps after its last shot")
	check_eq(view.class_masks[1].render_target_update_mode, SubViewport.UPDATE_DISABLED, "loot mask sleeps after its last pickup")
	view.queue_free()


func test_cached_dither_parameters_follow_settings_and_hitstop() -> void:
	var view := DitherView.new()
	add_child(view)
	var strength: float = Game.settings.dither
	Game.settings.dither = 0.25
	view._process(0.0)
	check_near(view.material.get_shader_parameter("strength"), 0.25 * DitherView.SCENERY_DITHER, 0.00001, "changing settings updates the shader")
	view.flash(Color.RED, 0.8)
	view._process(0.0)
	check_eq(view.material.get_shader_parameter("flash"), Color(1, 0, 0, 0.8), "a hitstop frame still uploads a new flash")
	view._process(1.0)
	check_near(view.material.get_shader_parameter("flash").a, 0.0, 0.00001, "the last fade update clears the shader")
	Game.settings.dither = strength
	view.queue_free()
