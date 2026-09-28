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
	var hud := Hud.new()
	hud._on_hit_confirmed(true)
	var duration := hud._kill_marker
	hud._on_hit_confirmed(false)
	check_eq(hud._kill_marker, duration, "a later hit does not replace the kill marker")
	check(hud._hit_marker > 0.0, "the later hit still refreshes its own marker")
	hud.free()
