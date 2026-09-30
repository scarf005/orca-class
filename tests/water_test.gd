extends TestCase
## The reservoir, the dam's lake and the flood all behave as water.


func _arena() -> World:
	var world := stage("boss")
	world.director._start_boss({"kind": "gunship"})
	world.boss._next_attack = 1000.0
	return world


func _lake_point() -> Vector3:
	return Dam.current.to_global(Vector3(0.0, 40.0, -50.0))


## Breaches the dam and sets the flood `seconds` into its spread.
func _flood(seconds: float) -> void:
	var dam := Dam.current
	dam.breach(dam.to_global(Vector3(0.0, 10.0, 5.0)))
	dam._clock = Dam.FLOOD_DELAY + seconds


func _flood_point(fraction: float) -> Vector3:
	var dam := Dam.current
	var start := dam._spill_at(dam._landing_time(), 0.0).z
	var local := Vector3((dam._gap.x + dam._gap.y) * 0.5, 0.0, start + dam.flood_reach() * fraction)
	var p := dam.to_global(local)
	p.y = Course.height_at(p)
	return p


func _splash_count(fx: Fx) -> int:
	return fx._transients.size()


func test_surface_at_finds_each_body_of_water() -> void:
	var world := _arena()
	await frames(2)
	var reservoir := Course.to_world(2100.0, -30.0)
	check_eq(Water.surface_at(reservoir), Stage1.WATER_LEVEL, "the reservoir is at its level")
	check_eq(Water.surface_at(Course.to_world(2100.0, 0.0)), -INF, "the road beside it is dry")
	check_eq(Water.surface_at(Course.to_world(2100.0, -136.0)), -INF, "past the water's edge is dry")
	check_eq(Water.surface_at(Course.to_world(1700.0, -30.0)), -INF, "before the reservoir starts is dry")
	check_eq(Water.surface_at(world.player.global_position), -INF, "the road under the tank is dry")
	check_eq(Water.surface_at(_lake_point()), Dam.LAKE_LEVEL, "the lake behind the dam is at its level")
	check_eq(Water.surface_at(Dam.current.to_global(Vector3(0.0, 0.0, -111.0))), -INF, "beyond the lake's far end is dry")
	check_eq(Water.surface_at(Dam.current.to_global(Vector3(150.0, 0.0, -50.0))), -INF, "beside the lake is dry")
	check_eq(Water.surface_at(Dam.current.to_global(Vector3(0.0, 0.0, 30.0))), -INF, "the arena floor is dry before the breach")
	cleanup()


func test_flood_is_water_only_inside_its_current_reach() -> void:
	_arena()
	await frames(2)
	var dam := Dam.current
	_flood(2.0)
	var reach := dam.flood_reach()
	check_eq(Water.surface_at(_flood_point(0.5)), Dam.FLOOD_Y, "inside the reach the flood is at its plane")
	check_eq(Water.surface_at(_flood_point(1.2)), -INF, "beyond the reach it is dry")
	var behind := dam.to_global(Vector3(dam._gap.x, 0.0, dam._spill_at(dam._landing_time(), 0.0).z - 3.0))
	check_eq(Water.surface_at(behind), -INF, "the ground under the wall's foot is not flooded")
	var beyond_far_side := dam.to_global(Vector3(dam._gap.x - 100.0, 0.0, _flood_point(0.5).z))
	check_eq(Water.surface_at(beyond_far_side), -INF, "well off to the side it is dry")
	var later := _flood_point(0.5)
	dam._clock = Dam.FLOOD_DELAY + 5.0
	check(dam.flood_reach() > reach, "the reach grows over time")
	check_eq(Water.surface_at(_flood_point(1.2)), -INF, "a point past the reach stays dry")
	check_eq(Water.surface_at(dam.to_global(dam.to_local(later) + Vector3(0, 0, reach * 0.9))), Dam.FLOOD_Y, "and the spread covers ground the earlier reach did not")
	cleanup()


func _sink(world: World, at: Vector3, surface: float) -> void:
	var fx := world.fx
	var before := _splash_count(fx)
	fx.spawn(Fx.Kind.SOLID, at, Vector3(1, -6, 0), 5.0, 1.0, Color.WHITE, {"bounce": true, "gravity": 20.0})
	var p: Fx.Particle = fx._pools[Fx.Kind.SOLID][-1]
	check(p.water, "debris over the water knows it")
	check_eq(p.ground, surface, "and lands on its surface")
	for i in 60:
		if not p in fx._pools[Fx.Kind.SOLID]:
			break
		fx._process(1.0 / 60.0)
	check(not p in fx._pools[Fx.Kind.SOLID], "debris sinks")
	check_eq(_splash_count(fx) - before, 3, "with three rings on the water")
	var ring: MeshInstance3D = fx._transients[-1].node
	check_near(ring.position.y, surface + 0.05, 0.0001, "lying on the surface")


func test_debris_splashes_into_the_lake_and_the_flood() -> void:
	var world := _arena()
	await frames(2)
	_sink(world, _lake_point() - Vector3(0, 8, 0), Dam.LAKE_LEVEL)
	_flood(3.0)
	_sink(world, _flood_point(0.4) + Vector3(0, 4, 0), Dam.FLOOD_Y)
	world.fx.spawn(Fx.Kind.SOLID, _flood_point(1.3) + Vector3(0, 3, 0), Vector3.ZERO, 5.0, 1.0, Color.WHITE, {"bounce": true})
	var dry: Fx.Particle = world.fx._pools[Fx.Kind.SOLID][-1]
	check(not dry.water, "debris past the flood's edge lands on the ground")
	cleanup()


func test_wreck_splashes_into_the_lake() -> void:
	var world := _arena()
	await frames(2)
	var wreck := Wreck.new()
	world.add_child(wreck)
	wreck.global_position = _lake_point() - Vector3(0, 10.6, 0)
	wreck.velocity = Vector3(0, -5, 0)
	var before := _splash_count(world.fx)
	wreck._process(0.05)
	check(wreck.is_queued_for_deletion(), "a wreck falling into the lake is gone")
	check(_splash_count(world.fx) >= before + 3, "with a splash")
	var high := Wreck.new()
	world.add_child(high)
	high.global_position = _lake_point()
	high.velocity = Vector3(0, -5, 0)
	high._process(0.01)
	check(not high.is_queued_for_deletion(), "one still above the surface flies on")
	cleanup()


func test_vehicles_wade_through_the_flood() -> void:
	var world := _arena()
	await frames(2)
	_flood(4.0)
	var tank := world.player
	var dam := Dam.current
	tank.global_position = dam.to_global(Vector3(dam._gap.x, 0.0, dam._spill_at(dam._landing_time(), 0.0).z - 3.0))
	tank.wade(0.016, Vector3.ZERO, 2.0)
	check(not tank._wet, "the tank is dry at the wall's foot")
	tank.global_position = _flood_point(0.5)
	var before := _splash_count(world.fx)
	tank.wade(0.016, Vector3(0, 0, -15), 2.0)
	check(tank._wet, "the tank driving into the flood is wet")
	check(_splash_count(world.fx) >= before + 4, "with a splash and a wake")
	check_near((world.fx._transients[-1].node as Node3D).position.y, Dam.FLOOD_Y + 0.05, 0.0001, "the rings lie at the flood's height")
	var ugv := Ugv.new()
	world.add_enemy(ugv)
	ugv.global_position = _flood_point(0.6)
	before = _splash_count(world.fx)
	ugv.wade(0.016, Vector3(0, 0, 10), 1.5)
	check(ugv._wet, "so is a UGV")
	check(_splash_count(world.fx) >= before + 4, "and it splashes")
	check_near((world.fx._transients[-1].node as Node3D).position.y, Dam.FLOOD_Y + 0.05, 0.0001, "with rings at the flood's height")
	tank.global_position = _flood_point(1.3)
	tank.wade(0.016, Vector3.ZERO, 2.0)
	check(not tank._wet, "and dries off past its edge")
	cleanup()


func test_explosion_over_the_flood_throws_water() -> void:
	var world := _arena()
	await frames(2)
	_flood(4.0)
	var at := _flood_point(0.5) + Vector3(0, 1.5, 0)
	var fx := world.fx
	var scorches := fx._scorches.size()
	var rings := _splash_count(fx)
	fx.explosion(at, 3.0)
	var plume: Array = fx._pools[Fx.Kind.GLOW].filter(func(p: Fx.Particle) -> bool: return p.gravity == 14.0)
	check(not plume.is_empty(), "the blast throws a plume of water")
	check(plume.all(func(p: Fx.Particle) -> bool: return is_equal_approx(p.position.y, Dam.FLOOD_Y)), "from the flood's surface")
	check(_splash_count(fx) >= rings + 3, "with rings")
	var dust: Array = fx._pools[Fx.Kind.GLOW].filter(func(p: Fx.Particle) -> bool: return p.drag == 3.5)
	check(dust.is_empty() and fx._scorches.size() == scorches, "and no dust or scorch mark on the ground")
	var dry := _flood_point(1.3) + Vector3(0, 1.5, 0)
	fx.explosion(dry, 3.0)
	check(not fx._pools[Fx.Kind.GLOW].filter(func(p: Fx.Particle) -> bool: return p.drag == 3.5).is_empty() and fx._scorches.size() == scorches + 1, "dry ground still gets dust and a scorch")
	cleanup()
