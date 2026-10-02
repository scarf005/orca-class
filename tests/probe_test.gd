extends TestCase
## Death reporting includes custom deaths, but never despawns or detached modules.


func test_killed_once_and_retains_delivery() -> void:
	var world := stage()
	var events: Array[Hit] = []
	world.killed.connect(func(_victim: Entity, hit: Hit) -> void: events.append(hit))
	var enemy := world.add_enemy(Ugv.new())
	enemy.global_position = world.player.global_position + Vector3(40, 0, 0)
	var hit := Hit.make(Hit.Kind.SHELL, 9999.0, enemy.hit_center())
	hit.source = world.player
	hit.weapon = "cannon"
	enemy.take_hit(hit)
	enemy.die(hit)
	check_eq(events.size(), 1, "one kill event per enemy")
	check_eq(events[0].weapon, "cannon", "killing delivery retained")
	check_eq(hit.copy().weapon, "cannon", "splash retains delivery")


func test_probe_excludes_enemy_self_ram() -> void:
	var world := stage()
	var probe := preload("res://tools/autoplay.gd").new()
	var hit := Hit.make(Hit.Kind.RAM, 999.0, Vector3.ZERO)
	probe._killed(null, hit)
	check_eq(probe.kill_sources.ram, 0, "enemy self-ram is not player ram")
	check_eq(probe.kill_sources.other, 1, "enemy self-ram remains accounted for")
	hit.source = world.player
	probe._killed(null, hit)
	check_eq(probe.kill_sources.ram, 1, "tank ram is credited")
	probe.free()


func test_despawn_is_not_a_kill() -> void:
	var world := stage()
	var events: Array[Entity] = []
	world.killed.connect(func(victim: Entity, _hit: Hit) -> void: events.append(victim))
	var enemy := world.add_enemy(Ugv.new()) as Enemy
	enemy.despawn()
	check_eq(events.size(), 0, "despawns emit no kill")


func test_delayed_death_reports_original_hit() -> void:
	var world := stage()
	var events: Array[Hit] = []
	world.killed.connect(func(_victim: Entity, hit: Hit) -> void: events.append(hit))
	var enemy := world.add_enemy(Uav.new()) as Enemy
	enemy.global_position = world.player.global_position + Vector3(40, 20, 0)
	var original := Hit.make(Hit.Kind.BULLET, 100.0, enemy.hit_center())
	original.source = world.player
	enemy.killing_hit = original.copy()
	enemy.die(Hit.make(Hit.Kind.RAM, 999.0, enemy.global_position))
	check_eq(events.size(), 1, "one delayed death event")
	check_eq(events[0].kind, Hit.Kind.BULLET, "crash reports its initiating hit")
