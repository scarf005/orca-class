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
	check((shot.get_child(0) as MeshInstance3D).layers & ActorLayer.HOSTILE, "enemy shots are outlined hostile too")
	var view := DitherView.new()
	add_child(view)
	await frames(1)
	check(view.class_masks.size() == 2, "the final pass has an outline mask for enemies and for pickups")
	check(view.viewport.size == Vector2i(960, 540), "the 3D view renders at 960x540")
	view.queue_free()
