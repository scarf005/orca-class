extends TestCase


func _rig() -> World:
	var world := stage()
	world.director.set_process(false)
	world.player.set_process(false)
	return world


func _target(world: World, at: Vector3, size := 0.4) -> Entity:
	var enemy := Entity.new()
	enemy.position = at
	enemy.radius = size
	enemy.max_hp = 100000.0
	enemy.hp = enemy.max_hp
	world.add_child(enemy)
	return enemy


func _fire(world: World, muzzle: Vector3, power: float) -> void:
	world.player.current_round = Armament.Round.APFSDS
	world.player.round_count = 6
	world.player.fire_cannon(muzzle, Vector3.FORWARD, power)


func test_every_charge_stage_hits_all_overlapping_enemies_once_without_splash() -> void:
	for power in [Armament.STAGE_1, Armament.STAGE_2, 1.0]:
		var world := _rig()
		var muzzle := Vector3(40, 30, 0)
		var victims: Array[Entity] = []
		for distance in [30.0, 30.2, 31.0, 31.0, 70.0]:
			victims.append(_target(world, muzzle + Vector3.FORWARD * distance, 1.0))
		var neighbor := _target(world, muzzle + Vector3(3, 0, -30))
		_fire(world, muzzle, power)
		var damage := Armament.SHELL_DAMAGE * 2.0 * lerpf(Armament.APFSDS_DAMAGE.x, Armament.APFSDS_DAMAGE.y, power) * Armament.SHELL_DAMAGE_SCALE
		for victim in victims:
			# Subtracting damage from 100000 HP introduces floating-point cancellation (< 1e-6 HP).
			check_near(victim.max_hp - victim.hp, damage, 0.000001, "each overlapping target takes exactly one immediate dart hit at charge %s" % power)
		check_eq(neighbor.hp, neighbor.max_hp, "no splash beside the beam")


func test_locked_beam_hits_enemies_before_and_after_lock_and_damages_surviving_scenery() -> void:
	var world := _rig()
	var muzzle := Vector3(40, 30, 0)
	var front := _target(world, muzzle + Vector3.FORWARD * 30.0)
	var locked := _target(world, muzzle + Vector3.FORWARD * 50.0)
	var behind := _target(world, muzzle + Vector3.FORWARD * 70.0)
	var props: Array[Prop] = []
	for distance in [29.0, 29.2, 29.2, 60.0]:
		var prop := Prop.new().setup("test_wall", BoxMesh.new(), 1.0, 4.0, 100000.0)
		prop.position = muzzle + Vector3.FORWARD * distance - Vector3.UP * 2.0
		world.props.add_child(prop)
		props.append(prop)
	world.player.charge_lock = locked
	_fire(world, muzzle, 1.0)
	var damage := Armament.SHELL_DAMAGE * 2.0 * Armament.APFSDS_DAMAGE.y * Armament.SHELL_DAMAGE_SCALE
	for victim in [front, locked, behind] + props:
		check_eq(victim.max_hp - victim.hp, damage, "the locked beam damages every enemy and surviving wall once")


func test_apfsds_uses_aphe_charge_time_and_three_boxes() -> void:
	var world := _rig()
	var tank := world.player
	tank.current_round = Armament.Round.APHE
	var time := tank.charge_time()
	tank.current_round = Armament.Round.APFSDS
	check_eq(tank.charge_time(), time, "same breech-adjusted charge duration")
	check_eq(Tank.round_step(Armament.Round.APFSDS), 1.0, "charges to the third box rather than auto-firing at the first")


func test_discarded_sabot_flies_out_and_deals_small_damage_off_the_beam() -> void:
	var world := _rig()
	var muzzle := Vector3(40, 30, 0)
	# A ring around the bore intercepts all petals, without touching the central dart.
	var victims: Array[Entity] = []
	for i in 4:
		var radial := Vector3(cos(i * TAU / 4), sin(i * TAU / 4), 0)
		victims.append(_target(world, muzzle + Vector3.FORWARD * 4.0 + radial * 2.0, 0.9))
	var before := world.projectiles.size()
	_fire(world, muzzle, 1.0)
	check_eq(victims.filter(func(e: Entity) -> bool: return e.hp < e.max_hp).size(), 0, "sabot pieces travel rather than hitting instantly")
	land(world, before)
	for victim in victims:
		check(victim.hp < victim.max_hp, "a separated sabot petal inflicts accepted damage")
		check(victim.max_hp - victim.hp < 100.0, "sabot damage stays below a main-gun hit")


func test_held_apfsds_waits_for_third_box_and_spends_one_round() -> void:
	var world := _rig()
	var tank := world.player
	tank.input_enabled = true
	var aphe_time := tank.charge_time()
	tank.load_round(Armament.Round.APFSDS)
	Input.action_press("fire")
	tank._update_charge(Armament.TAP_TIME + aphe_time * Armament.STAGE_1)
	tank._update_weapons(0.0)
	check_eq(world.stats.shots, 0, "holding through the first box does not auto-fire")
	tank._update_charge(aphe_time * (Armament.STAGE_2 - Armament.STAGE_1))
	tank._update_weapons(0.0)
	check_eq(world.stats.shots, 0, "holding through the second box does not auto-fire")
	tank._update_charge(aphe_time * (1.0 - Armament.STAGE_2))
	tank._update_weapons(0.0)
	check_eq(world.stats.shots, 1, "fires at the same full-charge deadline as APHE")
	check_eq(world.stats.charged_shots, 1, "the shot has full power")
	check_eq(tank.round_count, Armament.MAGAZINE[Armament.Round.APFSDS] - 1, "one dart consumes one cartridge, not four sabot petals")
	Input.action_release("fire")


func test_beam_stops_at_exact_range_and_solid_earth() -> void:
	var world := _rig()
	Course.flat = true
	var muzzle := Vector3(40, 30, 0)
	var power := Armament.STAGE_2
	var reach := Armament.SHELL_RANGE * lerpf(Armament.APFSDS_RANGE.x, Armament.APFSDS_RANGE.y, power)
	var inside := _target(world, muzzle + Vector3.FORWARD * (reach - 0.5), 0.1)
	var outside := _target(world, muzzle + Vector3.FORWARD * (reach + 0.2), 0.1)
	_fire(world, muzzle, power)
	check(inside.hp < inside.max_hp, "the beam reaches its charge-scaled range")
	check_eq(outside.hp, outside.max_hp, "no hit beyond range from the final 6 m sweep")
	var below := _target(world, Vector3(40, -3, 0))
	world.player.fire_cannon(muzzle, Vector3.DOWN, 1.0)
	check_eq(below.hp, below.max_hp, "solid earth remains the non-penetrable boundary")


func test_beam_kills_real_armored_ugvs_beyond_destroyed_wall() -> void:
	var world := _rig()
	var muzzle := Vector3(40, 30, 0)
	var wall := Prop.new().setup("test_wall", BoxMesh.new(), 1.0, 4.0, 100.0)
	wall.position = muzzle + Vector3.FORWARD * 20.0 - Vector3.UP * 2.0
	world.props.add_child(wall)
	var victims: Array[Ugv] = []
	for distance in [30.0, 65.0, 100.0]:
		var enemy := Ugv.new()
		enemy.position = muzzle + Vector3.FORWARD * distance - Vector3.UP
		world.add_enemy(enemy)
		enemy.set_process(false)
		victims.append(enemy)
	world.player.charge_lock = victims[1]
	_fire(world, muzzle, 1.0)
	check(wall.dead, "the dart destroys scenery through Prop.take_hit")
	for enemy in victims:
		check(enemy.dead, "the production cannon beam kills each real armored UGV, including before the lock")


func test_beam_width_is_proportional_to_charge_stage() -> void:
	for power in [Armament.STAGE_1, Armament.STAGE_2, 1.0]:
		var world := _rig()
		var muzzle := Vector3(40, 30, 0)
		world.player._fire_shell(Armament.Round.APFSDS, muzzle, Vector3.FORWARD, power)
		var cores: Array = world.fx._transients.filter(func(t: Dictionary) -> bool: return t.life == 0.07)
		var glows: Array = world.fx._transients.filter(func(t: Dictionary) -> bool: return t.life == 0.12)
		check_eq(cores.size(), 1, "one bright beam core")
		check_eq(glows.size(), 1, "one colored beam envelope")
		if cores.size() != 1 or glows.size() != 1:
			continue
		var level := Armament.stage(power)
		# Mesh basis lengths use float32; allow less than 1e-6 m of rounding.
		check_near(cores[0].node.basis.x.length(), 0.32 * level, 0.000001, "core width scales 1:2:3 with charge boxes")
		check_near(glows[0].node.basis.x.length(), 0.8 * level, 0.000001, "envelope width scales 1:2:3 with charge boxes")


func test_beam_fades_into_expanding_spiral_smoke() -> void:
	var world := _rig()
	var muzzle := Vector3(40, 30, 0)
	world.player._fire_shell(Armament.Round.APFSDS, muzzle, Vector3.FORWARD, 1.0)
	var spiral: Array = world.fx._pools[Fx.Kind.GLOW].filter(func(p: Fx.Particle) -> bool:
		return p.color in [Palette.SLATE, Palette.STONE, Palette.ASH] and p.position.z < -20.0)
	check(spiral.size() > 30, "a continuous spiral of neutral smoke extends along the beam")
	check(not world.fx._pools[Fx.Kind.FLAME].any(func(p: Fx.Particle) -> bool: return p.color == Palette.CYAN), "the fading trail contains no cyan sparks")
	var quadrants := {}
	for p: Fx.Particle in spiral:
		var offset := p.position - muzzle
		quadrants[Vector2i(int(signf(offset.x)), int(signf(offset.y)))] = true
		check(p.velocity.length() > 0.0, "the spiral disperses after firing")
	check_eq(quadrants.size(), 4, "the trail coils around all sides of the bore")
	if spiral.is_empty():
		return
	var beams := world.fx._transients.duplicate()
	check_eq(beams.size(), 2, "the free beam consists of its core and envelope")
	var first: Fx.Particle = spiral[0]
	var before_radius := Vector2(first.position.x - muzzle.x, first.position.y - muzzle.y).length()
	var trails: Array[Fx.Particle] = []
	var splashes: Array[Fx.Particle] = []
	world.fx._advance_pool(Fx.Kind.GLOW, 0.18, trails, splashes)
	world.fx._update_transients(0.18)
	check(beams.all(func(t: Dictionary) -> bool: return t.node.is_queued_for_deletion()), "the straight beam disappears before the spiral")
	check(first.life < first.max_life, "spiral smoke outlives the beam")
	var smoke_index: int = world.fx._pools[Fx.Kind.GLOW].find(first)
	if smoke_index >= 0:
		check(world.fx._buffers[Fx.Kind.GLOW][smoke_index * Fx.STRIDE + 16] > first.size, "rendered smoke swells instead of shrinking like a spark")
	check(Vector2(first.position.x - muzzle.x, first.position.y - muzzle.y).length() > before_radius, "the helix expands as the beam disintegrates")
