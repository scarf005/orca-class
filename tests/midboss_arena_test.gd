extends TestCase
## A mid-boss met in one of its stage's arenas is fought all-range there: the rail rolls the tank in, the drive
## turns free with the camera on the boss, and the boss's death resumes the course.


func test_a_mid_boss_in_an_arena_is_fought_all_range_once_the_tank_has_rolled_in() -> void:
	for number in [2, 3]:
		var event: Dictionary = StageDef.of(number).events(false).filter(func(e: Dictionary) -> bool: return e.type == "midboss")[0]
		var label := "stage %d's %s" % [number, event.kind]
		var world := stage("", false, number)
		world.director._next_event = world.director.events.size()
		world.player.invulnerable = true
		world.rail.d = event.d
		world.player._place(event.d)
		world.director._fire(event)
		var boss := world.boss
		boss.process_mode = Node.PROCESS_MODE_DISABLED # Posed: this watches the drive and the camera, not the fight.
		var last := world.player.global_position
		var longest := 0.0
		var settled := 0
		for i in 900:
			await frames(1)
			longest = maxf(longest, world.player.global_position.distance_to(last))
			last = world.player.global_position
			settled += int(world.rail.mode == Rail.Mode.ARENA)
			if settled >= 10:
				break
		check_eq(world.rail.mode, Rail.Mode.ARENA, "%s: the tank drives freely round the arena" % label)
		# At the tests' fixed 60 fps a drive step at 180 km/h is under 1 m; snapping into the drive circle jumped 32-40 m.
		check(longest < 3.0, "%s: the tank rolls in without a jump (longest step %.1f m)" % [label, longest])
		var side := Course.forward(world.rail.d).cross(Vector3.UP).normalized()
		boss.global_position = world.player.global_position + side * 40.0
		await frames(90)
		var eye := ((world.camera.global_position - world.player.global_position) * Vector3(1, 0, 1)).normalized()
		check(eye.dot(-side) > 0.9, "%s: the camera swings behind the tank to face the boss beside it (%.2f)" % [label, eye.dot(-side)])
		boss.died.emit(boss)
		await frames(100)
		check_eq(world.rail.mode, Rail.Mode.RAIL, "%s: its death resumes the course" % label)
