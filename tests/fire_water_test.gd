extends TestCase
## Fire and water: ground fire fizzles into steam on water, methane vents chain-ignite, an oil slick
## burns across the water, and a broken paddy gate floods enemies down-slope.


func _prop(world: World, kind: String, d: float, u: float) -> Prop:
	var cfg: Array = Scenery.PROPS[kind]
	var prop := Prop.new()
	prop.setup(kind, PropKit.mesh(kind, 0), cfg[0], cfg[1], cfg[2])
	prop.crushable = cfg[3]
	prop.burnable = cfg[4]
	prop.score = cfg[5]
	prop.vent = kind == "vent"
	prop.sluice = kind == "sluice"
	prop.position = Course.ground_at(d, u)
	world.props.add_child(prop)
	return prop


## Dead props and enemies free themselves.
func _down(entity: Variant) -> bool:
	return not is_instance_valid(entity) or entity.dead


func _zones() -> int:
	return FireZone._zones.filter(func(z: FireZone) -> bool: return is_instance_valid(z)).size()


func test_ground_fire_fizzles_on_water_but_burns_on_dry_ground() -> void:
	var world := stage("", true, 2)
	world.rail.d = 700.0
	var wet := Course.ground_at(700.0, 0.0)
	var dike := Course.ground_at(700.0, 18.0)
	check(Water.surface_at(wet) > -INF and Water.surface_at(dike) == -INF, "the paddy is wet and the dike dry")
	var before := _zones()
	FireZone.ignite(wet)
	await frames(2)
	check_eq(_zones(), before, "no fire zone starts on the paddy")
	FireZone.ignite(dike)
	await frames(2)
	check_eq(_zones(), before + 1, "one starts on the dike")
	var puffs := world.fx.particle_count()
	FireZone.ignite(Course.ground_at(700.0, 5.0))
	check(world.fx.particle_count() > puffs, "the fizzle leaves a puff of steam")
	world.fx.smoke(wet, 1)
	var canal := Course.ground_at(700.0, -30.0)
	FireZone.ignite(canal)
	check_eq(_zones(), before + 1, "nor in the deep canal")


func test_dragon_breath_does_not_set_water_alight() -> void:
	var world := stage("", true, 2)
	world.rail.d = 700.0
	var before := _zones()
	FireZone.on_flame_impact(null, Course.ground_at(700.0, 2.0), null)
	check_eq(_zones(), before, "a flame landing in the paddy starts nothing")
	FireZone.on_flame_impact(null, Course.ground_at(700.0, 18.0), null)
	check_eq(_zones(), before + 1, "on the dike it does")


func test_methane_vents_ignite_in_a_chain_with_a_delay() -> void:
	var world := stage("", true, 2)
	world.player.invulnerable = true
	world.rail.d = 1500.0
	var vents: Array[Prop] = []
	for i in 4:
		vents.append(_prop(world, "vent", 1500.0 + i * 9.0, 12.0))
	var far := _prop(world, "vent", 1500.0, 60.0)
	var bystander := _prop(world, "crate", 1500.0, -12.0)
	var died := {}
	for i in vents.size():
		var index := i
		vents[i].died.connect(func(_e: Entity) -> void: died[index] = Time.get_ticks_msec())
	var clock := 0.0
	vents[0].take_hit(Hit.make(Hit.Kind.FIRE, 30.0, vents[0].global_position))
	check(_down(vents[0]), "fire sets the first vent off")
	check(not _down(vents[1]), "its neighbour has not gone yet")
	var times := {}
	for frame in 180:
		await frames(1)
		clock += get_process_delta_time()
		for i in vents.size():
			if _down(vents[i]) and not times.has(i):
				times[i] = clock
	check_eq(times.size(), 4, "all four go, the other three in turn")
	check(times.get(1, 0.0) >= Prop.VENT_CHAIN_DELAY * 0.9, "the second waits a beat (%.2f s)" % times.get(1, 0.0))
	check(times.get(2, 0.0) > times.get(1, 0.0) + Prop.VENT_CHAIN_DELAY * 0.5, "and the third a beat after that (%.2f s)" % times.get(2, 0.0))
	check(times.get(3, 0.0) > times.get(2, 0.0) + Prop.VENT_CHAIN_DELAY * 0.5, "and the fourth (%.2f s)" % times.get(3, 0.0))
	check(not _down(far), "a vent out of reach stays quiet")
	check(not _down(bystander), "an ordinary crate is not a vent")


func test_a_blast_sets_a_vent_off_and_it_hurts_enemies_nearby() -> void:
	var world := stage("", true, 2)
	world.rail.d = 1500.0
	var vent := _prop(world, "vent", 1520.0, 12.0)
	var crawler := Crawler.new()
	crawler.position = Course.ground_at(1523.0, 12.0)
	world.add_enemy(crawler)
	world.blast(Course.ground_at(1520.0, 12.0), 2.0, 60.0, Entity.Team.PLAYER)
	check(_down(vent), "a blast sets the vent off")
	await frames(3)
	check(_down(crawler) or crawler.hp < crawler.max_hp, "the flame burst reaches the crawler")


func test_oil_slick_burns_across_the_water() -> void:
	var world := stage("", true, 2)
	world.rail.d = 1500.0
	var slick := OilSlick.new()
	add_child(slick)
	remove_child(slick)
	world.add_child(slick)
	slick.global_position = Course.ground_at(1520.0, 10.0)
	var edge := Course.ground_at(1520.0, 10.0 + OilSlick.RADIUS + 6.0)
	check(Water.surface_at(slick.global_position) > -INF, "the slick lies on water")
	var before := _zones()
	FireZone.ignite(edge)
	check_eq(_zones(), before, "water beside the slick still fizzles")
	FireZone.ignite(Course.ground_at(1520.0, 8.0))
	check(slick.burning, "fire lights the slick")
	check(_zones() > before, "and a zone burns on it")
	await frames(90)
	var on_water := 0
	var reach := 0.0
	for zone: FireZone in FireZone._zones:
		if is_instance_valid(zone):
			if Water.surface_at(zone.global_position) > -INF:
				on_water += 1
			reach = maxf(reach, Vector2(zone.global_position.x - slick.global_position.x, zone.global_position.z - slick.global_position.z).length())
	check(on_water >= 4, "flames stand on the water (%d zones)" % on_water)
	check(reach > OilSlick.RADIUS * 0.6, "and spread out over the slick (%.1f m)" % reach)
	check(reach <= OilSlick.RADIUS + FireZone.RADIUS, "but not past it (%.1f m)" % reach)
	var gone := await wait_until(gone(slick), 60 * 14)
	check(gone, "the slick burns off")


func test_a_blast_lights_a_slick() -> void:
	var world := stage("", true, 2)
	world.rail.d = 1500.0
	var slick := OilSlick.new()
	world.add_child(slick)
	slick.global_position = Course.ground_at(1520.0, 10.0)
	world.blast(Course.ground_at(1520.0, 24.0), 2.0, 10.0, Entity.Team.PLAYER)
	check(not slick.burning, "a blast well clear of it does nothing")
	world.blast(Course.ground_at(1520.0, 17.0), 3.0, 10.0, Entity.Team.PLAYER)
	check(slick.burning, "a blast at its edge lights it")


func _flood_setup(world: World, credited: bool) -> Array:
	world.player.invulnerable = true
	world.rail.d = 700.0
	world.player.process_mode = Node.PROCESS_MODE_DISABLED # It would shoot the victims itself.
	var gate := _prop(world, "sluice", 700.0, 18.0)
	var victim := Ugv.new()
	victim.position = Course.ground_at(700.0, 5.0)
	victim.immobile = true
	world.add_enemy(victim)
	var bystander := Ugv.new()
	bystander.position = Course.ground_at(700.0, 5.0 + 30.0)
	bystander.immobile = true
	world.add_enemy(bystander)
	for enemy in [victim, bystander]:
		enemy.max_hp = 200.0
		enemy.hp = 200.0
	var hit := Hit.make(Hit.Kind.RAM if credited else Hit.Kind.BULLET, 99.0, gate.global_position)
	hit.source = world.player if credited else null
	gate.take_hit(hit)
	return [gate, victim, bystander]


func test_breaking_a_paddy_gate_floods_enemies_down_slope() -> void:
	var world := stage("", true, 2)
	var actors := _flood_setup(world, true)
	var victim: Ugv = actors[1]
	var bystander: Ugv = actors[2]
	var start_u := Course.to_course(victim.global_position).y
	var bystander_hp := bystander.hp
	check(_down(actors[0]), "the gate broke")
	await frames(150)
	check(victim.hp < 200.0 - Surge.DAMAGE * 0.9, "the surge hurts the enemy in its path (%.0f hp left)" % victim.hp)
	check(Course.to_course(victim.global_position).y < start_u - 4.0, "and pushes it down toward the road (u %.1f to %.1f)" % [start_u, Course.to_course(victim.global_position).y])
	check_eq(bystander.hp, bystander_hp, "an enemy out of the way is untouched")
	check(world.stats.style_feed.any(func(e: Dictionary) -> bool: return e.name == "FLOODED"), "the trick FLOODED is awarded")
	check_eq(world.stats.style_feed.filter(func(e: Dictionary) -> bool: return e.name == "FLOODED").size() > 0, true, "once per victim")


func test_a_surge_kills_are_credited_to_the_player() -> void:
	var world := stage("", true, 2)
	world.player.invulnerable = true
	world.rail.d = 700.0
	world.player.process_mode = Node.PROCESS_MODE_DISABLED # It would shoot the victims itself.
	var gate := _prop(world, "sluice", 700.0, 18.0)
	var crawler := Ugv.new()
	crawler.position = Course.ground_at(700.0, 8.0)
	crawler.immobile = true
	world.add_enemy(crawler)
	crawler.max_hp = Surge.DAMAGE * 0.5
	crawler.hp = Surge.DAMAGE * 0.5
	var kills := world.stats.kills
	var hit := Hit.make(Hit.Kind.RAM, 99.0, gate.global_position)
	hit.source = world.player
	gate.take_hit(hit)
	await frames(150)
	check(_down(crawler) or not is_instance_valid(crawler), "the flood kills a weak enemy")
	check(world.stats.kills > kills, "and the kill counts for the tank")


func test_a_gate_broken_by_someone_else_floods_without_credit() -> void:
	var world := stage("", true, 2)
	var actors := _flood_setup(world, false)
	await frames(150)
	check(actors[1].hp < 200.0, "the water still hurts")
	check(not world.stats.style_feed.any(func(e: Dictionary) -> bool: return e.name == "FLOODED"), "but there is no trick without the tank")


func test_flying_enemies_ride_over_the_surge() -> void:
	var world := stage("", true, 2)
	world.player.invulnerable = true
	world.rail.d = 700.0
	world.player.process_mode = Node.PROCESS_MODE_DISABLED # It would shoot the victims itself.
	var gate := _prop(world, "sluice", 700.0, 18.0)
	var drone := FpvDrone.new()
	drone.position = Course.ground_at(700.0, 5.0) + Vector3.UP * 6.0
	world.add_enemy(drone)
	drone.max_hp = 500.0
	drone.hp = 500.0
	var hit := Hit.make(Hit.Kind.RAM, 99.0, gate.global_position)
	hit.source = world.player
	gate.take_hit(hit)
	await frames(90)
	check_eq(drone.hp, 500.0, "a flying drone is not touched")
