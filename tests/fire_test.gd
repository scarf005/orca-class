extends TestCase
## Burning enemies and fire zones read as real fire: many tongues scaled to the body, smoke, embers
## and a glowing hot ground under a zone, within the particle budget and with the old damage.


## A stage whose rail stands still, so nothing gets rammed while it burns.
func _stage() -> World:
	var world := stage("", false)
	world.rail.mode = Rail.Mode.ARENA
	return world


func _dummy(world: World, ahead: float, lateral := 0.0) -> Ugv:
	var ugv := Ugv.new()
	ugv.position = Course.ground_at(world.rail.d + ahead, lateral)
	world.add_enemy(ugv)
	ugv.immobile = true
	ugv.disarmed = true
	ugv.max_hp = 100000.0
	ugv.hp = 100000.0
	return ugv


func _pool(world: World, kind: Fx.Kind) -> Array:
	return world.fx._pools[kind]


## Burns a `radius`-sized enemy for `seconds` and returns the flame particles that appeared around it.
func _flames_of(world: World, radius: float, seconds: float) -> Dictionary:
	var enemy := _dummy(world, 40.0)
	enemy.death_radius = radius
	world.fx._pools[Fx.Kind.FLAME].clear()
	var spawned := 0
	var size := 0.0
	var seen := {}
	for i in int(seconds * 60.0):
		enemy.burning = 3.0
		await frames(1)
		for p in world.fx._pools[Fx.Kind.FLAME]:
			if not seen.has(p) and p.size >= 0.25 and p.position.distance_to(enemy.global_position) < 8.0: # Not the sparks of the burn hits.
				seen[p] = true
				spawned += 1
				size += p.size
	enemy.queue_free()
	await frames(2)
	return {"per_second": spawned / seconds, "size": size / maxi(spawned, 1)}


func test_a_burning_enemy_throws_many_flames_scaled_to_its_size() -> void:
	var world := _stage()
	var small := await _flames_of(world, 1.0, 1.0)
	var big := await _flames_of(world, 3.0, 1.0)
	check(small.per_second > 16.0, "a small enemy sheds more than the old 4 flames a second (%.0f)" % small.per_second)
	check(big.per_second > small.per_second * 1.3, "a big one sheds more (%.0f against %.0f)" % [big.per_second, small.per_second])
	check(small.size > 0.5 and big.size > small.size * 1.4, "bigger, taller flames on the bigger body (%.2f against %.2f)" % [big.size, small.size])


func test_a_burning_enemy_smokes_and_lights_up_only_when_big() -> void:
	var world := _stage()
	var enemy := _dummy(world, 40.0)
	enemy.death_radius = 3.0
	await frames(2)
	var smoke := _pool(world, Fx.Kind.GLOW).size()
	var lit := 0.0
	for i in 90:
		enemy.burning = 3.0
		await frames(1)
		for light in world.fx._flashes:
			lit = maxf(lit, light.light_energy)
	check(_pool(world, Fx.Kind.GLOW).size() > smoke + 5, "a smoke column rises from it")
	check(lit > 1.0, "and a flickering warm light plays on the ground (%.1f)" % lit)
	var small := _dummy(world, 60.0)
	small.death_radius = 1.0
	for light in world.fx._flashes:
		light.light_energy = 0.0
	for i in 60:
		small.burning = 3.0
		enemy.burning = 0.0
		await frames(1)
	var glow := 0.0
	for light in world.fx._flashes:
		glow = maxf(glow, light.light_energy)
	check(glow == 0.0, "a small one lights nothing")


func test_burning_damage_per_second_is_unchanged() -> void:
	var world := _stage()
	var enemy := _dummy(world, 40.0)
	await frames(2)
	var before := enemy.hp
	for i in 60:
		enemy.burning = 3.0
		await frames(1)
	check_near(before - enemy.hp, 20.0, 5.0, "about 5 damage per quarter second (%.1f)" % (before - enemy.hp))


func test_a_fire_zone_keeps_its_stats_and_burns_what_stands_in_it() -> void:
	var world := _stage()
	check_eq(FireZone.RADIUS, 3.5, "radius")
	check_eq(FireZone.LIFE, 6.0, "life")
	check_eq(FireZone.DAMAGE_PER_SECOND, 20.0, "damage")
	check_eq(FireZone.MAX_ZONES, 40, "zone cap")
	var enemy := _dummy(world, 40.0)
	FireZone.ignite(enemy.global_position)
	await frames(2)
	var before := enemy.hp
	await frames(60)
	check_near(before - enemy.hp, 31.0, 10.0, "the zone and the fire it sets (31 before the change) (%.1f)" % (before - enemy.hp))


func test_a_fire_zone_has_a_ground_glow_that_ramps_in_pulses_and_cools() -> void:
	var world := _stage()
	var at := Course.ground_at(world.rail.d + 30.0, 0.0)
	FireZone.ignite(at)
	var zone: FireZone = FireZone._zones[-1]
	await frames(2)
	var start := zone.ground_glow()
	check(zone._rim.is_inside_tree() and zone._core.is_inside_tree(), "a hot patch of ground lies under the flames")
	await frames(30)
	var young := zone.ground_glow()
	check(young > start, "it flares up quickly after ignition (%.2f then %.2f)" % [start, young])
	check(young > 0.6, "to a strong glow (%.2f)" % young)
	zone.life = FireZone.LIFE * 0.5
	await frames(2)
	var middle := zone.ground_glow()
	zone.life = 0.4
	await frames(2)
	var dying := zone.ground_glow()
	check_near(zone._rim.get_instance_shader_parameter("instance_alpha"), dying * 0.7, 0.001, "drawn with that brightness")
	check(dying < middle * 0.5, "it dies down over the last seconds (%.2f then %.2f)" % [middle, dying])
	check(middle < young + 0.15, "and cools as it ages")
	var seen := {}
	for i in 60:
		zone.life = 4.0
		await frames(1)
		seen[snappedf(zone.ground_glow(), 0.01)] = true
	check(seen.size() > 4, "the glow pulses (%d levels)" % seen.size())
	zone.life = 0.05
	await frames(10)
	check(not is_instance_valid(zone) or zone.is_queued_for_deletion(), "then it leaves its scorch mark")


func test_forty_zones_and_ten_burning_enemies_stay_within_the_particle_cap() -> void:
	var world := _stage()
	for i in 10:
		_dummy(world, 20.0 + i * 5.0, (i % 5 - 2) * 4.0)
	for i in FireZone.MAX_ZONES:
		FireZone.ignite(Course.ground_at(world.rail.d + 15.0 + (i % 8) * 8.0, (i / 8 - 2) * 8.0))
	check_eq(FireZone._zones.size(), FireZone.MAX_ZONES, "all forty zones are alight")
	var peak := {Fx.Kind.SOLID: 0, Fx.Kind.GLOW: 0, Fx.Kind.FLAME: 0}
	var total := 0
	for frame in 300:
		for enemy in world.enemies:
			enemy.burning = 3.0
			enemy.hp = enemy.max_hp
		await frames(1)
		for kind in peak:
			peak[kind] = maxi(peak[kind], _pool(world, kind).size())
		total = maxi(total, world.fx.particle_count())
	for kind in peak:
		check(peak[kind] <= Fx.SOFT_CAP, "pool %d peaks at %d, within %d" % [kind, peak[kind], Fx.SOFT_CAP])
