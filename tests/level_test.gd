extends TestCase
## Level design: attacks from behind and the flanks, readable UAV passes, the laser's feedback.


func test_stage_attacks_from_behind_and_the_flanks() -> void:
	var events := Stage1.events(false)
	var behind := events.filter(func(e: Dictionary) -> bool: return e.type == "wave" and (e.get("formation", "") == "behind" or e.get("props", {}).get("from_behind", false)))
	var flank := events.filter(func(e: Dictionary) -> bool: return e.type == "wave" and e.get("formation", "") == "flank")
	check(behind.size() >= 8, "at least eight waves come from behind (got %d)" % behind.size())
	check(behind.any(func(e: Dictionary) -> bool: return e.kind in ["ugv", "walker"]), "ground vehicles run the tank down from behind")
	check(behind.any(func(e: Dictionary) -> bool: return e.kind == "uav"), "UAVs make passes from behind")
	check(flank.size() >= 2, "some waves come in from the valley sides")


func test_waves_from_behind_are_announced_and_overtake() -> void:
	var world := stage()
	await frames(30)
	var warned := []
	world.director.incoming.connect(func(from: Vector3) -> void: warned.append(from))
	var spawned: Array[Enemy] = world.director.spawn_wave({"d": world.rail.d, "kind": "ugv", "count": 1, "formation": "behind", "spacing": 8.0})
	check(warned.size() == 1, "the HUD is told a wave is coming from behind")
	var ugv := spawned[0]
	world.player.tail.destroyed = true # Keep the claw from snatching it as it passes.
	check(Course.to_course(ugv.global_position).x < world.rail.d, "it starts behind the rail")
	ugv.invulnerable = true
	var passed := await wait_until(func() -> bool: return is_instance_valid(ugv) and Course.to_course(ugv.global_position).x > world.rail.d + world.player.course_offset + 5.0, 60 * 8)
	check(passed, "it overtakes the tank instead of falling behind and despawning")


func test_uav_passes_are_slow_enough_to_engage() -> void:
	var world := stage()
	await frames(30)
	var spawned: Array[Enemy] = world.director.spawn_wave({"d": world.rail.d, "kind": "uav", "count": 1, "props": {"attack": "bomb"}})
	var uav := spawned[0] as Uav
	uav.invulnerable = true
	var start := uav.global_position
	await frames(60)
	check(uav.global_position.distance_to(start) < Uav.HEAD_ON_SPEED * 1.3, "the head-on pass is slow")
	var behind: Array[Enemy] = world.director.spawn_wave({"d": world.rail.d, "kind": "uav", "count": 1, "props": {"attack": "strafe", "from_behind": true}})
	var chaser := behind[0] as Uav
	chaser.invulnerable = true
	check(Course.to_course(chaser.global_position).x < world.rail.d, "a rear pass starts behind the tank")
	var time_near := 0
	for i in 60 * 10:
		await frames(1)
		if is_instance_valid(chaser) and chaser.global_position.distance_to(world.player.global_position) < 60.0:
			time_near += 1
	check(time_near > 60 * 3, "it works the tank over for seconds, not a blink (%.1f s)" % (time_near / 60.0))


func test_laser_kills_are_announced() -> void:
	var world := stage()
	await frames(2)
	var got := []
	world.intercepted.connect(func(at: Vector3) -> void: got.append(at))
	var tank := world.player
	var missile := world.spawn_projectile(Entity.Team.ENEMY, tank.global_position + Vector3(0, 6, -20), Vector3(0, -3, 20), "rocket")
	missile.interceptable = true
	missile.intercept_hp = 0.2
	missile.life = 5.0
	var ok := await wait_until(func() -> bool: return not got.is_empty(), 120)
	check(ok, "the laser burning a missile down is signalled for a callout")


func test_full_screen_scales_without_whole_number_letterboxing() -> void:
	check(ProjectSettings.get_setting("display/window/stretch/scale_mode") == "fractional", "the canvas scales to fill the screen")
