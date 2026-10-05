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
			check_eq(victim.max_hp - victim.hp, damage, "each overlapping target takes exactly one immediate dart hit at charge %s" % power)
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
		world.props.add(prop)
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


func test_beam_fades_into_a_spiral_trail() -> void:
	var world := _rig()
	var muzzle := Vector3(40, 30, 0)
	_fire(world, muzzle, 1.0)
	var spiral: Array = world.fx._pools[Fx.Kind.GLOW].filter(func(p: Fx.Particle) -> bool:
		return p.color == Palette.CYAN and p.position.z < -20.0)
	check(spiral.size() > 30, "a continuous spiral extends along the beam")
	var quadrants := {}
	for p: Fx.Particle in spiral:
		var offset := p.position - muzzle
		quadrants[Vector2i(signi(int(signf(offset.x))), signi(int(signf(offset.y))))] = true
		check(p.velocity.length() > 0.0, "the spiral disperses after firing")
	check_eq(quadrants.size(), 4, "the trail coils around all sides of the bore")
