extends TestCase


func test_normal_flight_keeps_space_with_damaged_rotors_and_inward_momentum() -> void:
	var world := stage("boss")
	world.director._start_boss({"kind": "gunship"})
	var boss := world.boss as Gunship
	boss._next_attack = 1000.0
	var center := Course.to_world(Course.ARENA_CENTER_D, 0.0)
	for phase in Gunship.Phase.values():
		boss.phase = phase
		for lost in 3:
			boss.parts.rotor_l.hp = 0.0 if lost > 0 else 150.0
			boss.parts.rotor_r.hp = 0.0 if lost > 1 else 150.0
			for edge in [Vector3.ZERO, Vector3.RIGHT * 79.0]:
				world.player.global_position = center + edge
				boss.global_position = world.player.global_position + Vector3(1, 10, 0)
				boss._velocity = Vector3(-60, -40, 0)
				boss.stagger = 1.0
				var nearest := INF
				var lowest := INF
				for i in 120:
					boss.behave(1.0 / 60.0)
					var offset := boss.global_position - world.player.global_position
					nearest = minf(nearest, Vector2(offset.x, offset.z).length())
					lowest = minf(lowest, boss.global_position.y - Course.height_at(boss.global_position))
				check(nearest >= 49.99, "normal flight stays at least 50 m from the tank")
				check(lowest >= 23.99, "even damaged, staggered flight stays at least 24 m above terrain")


func test_dive_can_still_close_in_and_crash_is_not_clamped() -> void:
	var world := stage("boss")
	world.director._start_boss({"kind": "gunship"})
	var boss := world.boss as Gunship
	boss._next_attack = 1000.0
	boss.phase = Gunship.Phase.INFECTED
	boss._attack = Gunship.Attack.DIVE
	boss.global_position = world.player.global_position + Vector3(12, 12, 0)
	boss.behave(1.0 / 60.0)
	var offset := boss.global_position - world.player.global_position
	check(Vector2(offset.x, offset.z).length() < 15.0, "the dive remains a close-range attack")
	check(boss.global_position.y - Course.height_at(boss.global_position) >= 8.99, "the dive retains its ground clearance")
	boss._crash = 0.1
	boss._crash_from = boss.global_position
	boss._crash_to = world.player.global_position
	boss.behave(1.0 / 60.0)
	check(boss.global_position.distance_to(world.player.global_position) < 50.0, "the scripted crash bypasses normal flight spacing")
