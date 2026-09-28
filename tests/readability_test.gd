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


func test_enemies_wear_a_hostile_rim_and_pickups_a_cyan_beacon() -> void:
	var world := stage()
	var ugv := Ugv.new()
	ugv.position = Course.ground_at(world.rail.d + 60.0, 0.0)
	world.add_enemy(ugv)
	await frames(1)
	check(ugv._meshes.all(func(m: GeometryInstance3D) -> bool: return m.material_overlay == Enemy._hostile_rim), "every enemy mesh has the rim")
	ugv.flash()
	await frames(20)
	check(ugv._meshes.all(func(m: GeometryInstance3D) -> bool: return not is_instance_valid(m) or m.material_overlay == Enemy._hostile_rim), "the rim comes back after a hit flash")
	var pickup := world.spawn_pickup("heat", Course.ground_at(world.rail.d + 20.0, 0.0))
	check(pickup.get_children().any(func(n: Node) -> bool: return n is MeshInstance3D and (n as MeshInstance3D).mesh == Pickup._pillar_mesh()), "pickups stand in a cyan beacon")
