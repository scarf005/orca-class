extends TestCase
## CPU simulation and the shader payload must agree through expiry, bounce and pool growth.


func test_gravity_drag_and_fade_preserve_simulation() -> void:
	var fx := Fx.new()
	add_child(fx)
	fx.spawn(Fx.Kind.GLOW, Vector3(1, 5, 3), Vector3(4, 6, 8), 2.0, 2.0, Color.RED,
		{"gravity": 10.0, "drag": 0.5, "end_size": 0.0, "fade": 0.0})
	fx._process(0.5)
	var p: Fx.Particle = fx._pools[Fx.Kind.GLOW][0]
	check(p.velocity.is_equal_approx(Vector3(3, 0.75, 6)), "gravity precedes drag")
	check(p.position.is_equal_approx(Vector3(2.5, 5.375, 6)), "motion uses the damped velocity")
	var data: PackedFloat32Array = fx._buffers[Fx.Kind.GLOW]
	check_near(lerpf(data[0], data[1], data[16] / data[2]), 1.5, 0.00001, "shader size follows particle lifetime")
	check_near(1.0 - smoothstep(data[4], 1.0, data[16] / data[2]), 1.0 - smoothstep(0.0, 1.0, 0.25), 0.00001, "screen-door fade remains unchanged")
	fx.free()


func test_bounce_and_water_keep_their_effects() -> void:
	var fx := Fx.new()
	add_child(fx)
	fx.spawn(Fx.Kind.SOLID, Vector3(0, 1, 0), Vector3(4, -10, 2), 3.0, 1.0, Color.WHITE)
	var p: Fx.Particle = fx._pools[Fx.Kind.SOLID][0]
	p.bounce = true
	p.ground = 0.0
	fx._process(0.2)
	check_near(p.position.y, 0.0, 0.00001, "debris rests on its sampled ground")
	check(p.velocity.is_equal_approx(Vector3(2, 3, 1)), "ground bounce retains its damping")
	p.water = true
	p.ground = Course.WATER_LEVEL
	p.position.y = Course.WATER_LEVEL + 0.1
	p.velocity.y = -10.0
	fx._process(0.2)
	check(fx._pools[Fx.Kind.SOLID].is_empty(), "debris sinks on hitting water")
	check(not fx._pools[Fx.Kind.GLOW].is_empty(), "water impact still throws spray")
	check_eq(fx._transients.size(), 3, "water impact still makes three rings")
	fx.free()


func test_growth_and_compaction_keep_shader_data_with_the_particle() -> void:
	var fx := Fx.new()
	add_child(fx)
	for i in 200:
		fx.spawn(Fx.Kind.SOLID, Vector3(i, 2, 0), Vector3.ZERO, 0.05 if i % 2 == 0 else 2.0, 1.0, Color.WHITE)
	fx._process(0.1)
	var mesh: MultiMesh = fx._multimeshes[Fx.Kind.SOLID]
	check_eq(mesh.visible_instance_count, 100, "only live particles are drawn")
	check(mesh.instance_count >= 200 and mesh.instance_count < Fx.MAX_PARTICLES, "capacity follows demand instead of allocating the maximum")
	var data: PackedFloat32Array = fx._buffers[Fx.Kind.SOLID]
	for i in 100:
		var p: Fx.Particle = fx._pools[Fx.Kind.SOLID][i]
		check_near(data[i * Fx.STRIDE + 3], i * 2 + 1, 0.00001, "compacted translation stays in order")
		check_near(data[i * Fx.STRIDE + 9], p.layer, 0.00001, "compacted debris keeps its sprite")
		check_near(data[i * Fx.STRIDE + 5] + data[i * Fx.STRIDE + 8] * data[i * Fx.STRIDE + 16], p.spin.x + p.spin.z * p.life, 0.00001, "compacted debris keeps its roll")
	fx._process(3.0)
	check_eq(mesh.visible_instance_count, 0, "expiry hides the whole pool")
	fx.free()


func test_warm_effect_geometry_does_not_change_randomness() -> void:
	seed(913)
	var expected := randi()
	seed(913)
	var fx := Fx.new()
	add_child(fx)
	check_eq(randi(), expected, "warming deterministic meshes does not consume combat randomness")
	var count := Fx._mesh_cache.size()
	fx.fireball(Vector3.ZERO, 1.0, 2.0, 1.0)
	for color in [Palette.WHITE, Palette.BUTTER, Palette.FRIENDLY, Palette.HOSTILE]:
		for variant in 3:
			Fx._flash_mesh(variant, color)
	check_eq(Fx._mesh_cache.size(), count, "first common hits reuse prepared geometry")
	fx.free()


func test_capacity_stops_at_the_particle_limit() -> void:
	var fx := Fx.new()
	add_child(fx)
	for i in Fx.MAX_PARTICLES:
		var p := Fx.Particle.new()
		p.position.x = i
		fx._pools[Fx.Kind.GLOW].append(p)
	fx._process(0.01)
	var mesh: MultiMesh = fx._multimeshes[Fx.Kind.GLOW]
	check_eq(mesh.instance_count, Fx.MAX_PARTICLES, "power-of-two growth respects the hard limit")
	check_eq(mesh.visible_instance_count, Fx.MAX_PARTICLES, "the final slot remains drawable")
	var data: PackedFloat32Array = fx._buffers[Fx.Kind.GLOW]
	check_near(data[(Fx.MAX_PARTICLES - 1) * Fx.STRIDE + 3], Fx.MAX_PARTICLES - 1, 0.00001, "the last particle is uploaded without truncation")
	fx.free()


func test_wake_throws_spray_only_while_moving() -> void:
	var fx := Fx.new()
	add_child(fx)
	fx.wake(Vector3(0, -5, 0), Vector3.ZERO, 2.0)
	check_eq(fx._transients.size(), 1, "standing still leaves a ripple ring")
	check(fx._pools[Fx.Kind.GLOW].is_empty(), "standing still throws no spray")
	var ring: MeshInstance3D = fx._transients[0].node
	check_near(ring.position.y, Course.WATER_LEVEL + 0.05, 0.0001, "ripples lie on the water surface")
	fx.wake(Vector3(0, -5, 0), Vector3(0, 3, -20), 2.0)
	check_eq(fx._transients.size(), 2, "moving leaves a ring too")
	var spray: Array = fx._pools[Fx.Kind.GLOW]
	check(spray.size() >= 4, "moving throws a bow wave")
	check(spray.any(func(p: Fx.Particle) -> bool: return p.velocity.x > 0.0) and spray.any(func(p: Fx.Particle) -> bool: return p.velocity.x < 0.0), "the bow wave spreads to both sides")
	fx.free()


func test_ground_units_splash_into_the_reservoir() -> void:
	var world := stage()
	var dry := world.player.global_position
	world.player.wade(0.016, Vector3.ZERO, 2.0)
	check(not world.player._wet, "the road is dry")
	var transients := world.fx._transients.size()
	world.rail.d = 2100.0
	world.player.course_u = -30.0
	await frames(3)
	check(world.player.global_position.y < Course.WATER_LEVEL, "the tank can drive into the reservoir")
	check(world.player._wet, "the tank knows it is wading")
	check(world.fx._transients.size() > transients + 3, "driving in splashes and leaves a wake")
	var drone := FpvDrone.new()
	drone.position = Vector3(dry.x, Course.WATER_LEVEL - 1.0, dry.z)
	world.add_enemy(drone)
	drone.wade(0.016, Vector3.ZERO, 1.0)
	check(not drone._wet, "flying units never wade")
	cleanup()


func _trail_of(fx: Fx, material: Fx.Debris) -> Color:
	fx._pools[Fx.Kind.SOLID].clear()
	fx._shard(Vector3(0, 20, 0), Vector3(3, 5, 0), 0.4, material)
	return (fx._pools[Fx.Kind.SOLID][-1] as Fx.Particle).trail


func test_debris_trails_follow_the_material() -> void:
	var fx := Fx.new()
	add_child(fx)
	check_eq(Fx.DEBRIS_TRAILS.size(), Fx.Debris.size(), "every debris material has a trail entry")
	check_eq(_trail_of(fx, Fx.Debris.WOOD), Palette.WOOD.lerp(Palette.ASH, 0.5), "a wood shard trails brown-grey dust")
	check_eq(_trail_of(fx, Fx.Debris.ROOF), Palette.SLATE, "a roof slate shard trails slate")
	check_eq(_trail_of(fx, Fx.Debris.FOLIAGE), Palette.SAGE, "foliage trails sage")
	check_eq(_trail_of(fx, Fx.Debris.SPORE), Palette.LILAC, "spores trail lilac")
	check_eq(_trail_of(fx, Fx.Debris.DIRT), Palette.OCHRE, "dirt trails ochre dust")
	check_eq(_trail_of(fx, Fx.Debris.GLASS).a, 0.0, "a glass shard leaves no trail")
	check_eq(_trail_of(fx, Fx.Debris.BRASS).a, 0.0, "nor does brass")
	var seen := {}
	for material in Fx.Debris.values():
		var trail := _trail_of(fx, material)
		if trail.a > 0.0:
			seen[trail.to_html()] = true
	check(seen.size() >= 8, "the trails are not all one color (%d distinct)" % seen.size())
	fx.queue_free()


func test_flying_shards_puff_their_own_color() -> void:
	var fx := Fx.new()
	add_child(fx)
	fx._pools[Fx.Kind.GLOW].clear()
	fx._shard(Vector3(0, 30, 0), Vector3(8, 6, 0), 0.4, Fx.Debris.FOLIAGE)
	for i in 12:
		fx._process(0.05)
	var puffs: Array = fx._pools[Fx.Kind.GLOW]
	check(not puffs.is_empty() and puffs.all(func(p: Fx.Particle) -> bool: return p.color == Palette.SAGE), "a foliage shard leaves sage puffs (%d)" % puffs.size())
	fx._pools[Fx.Kind.GLOW].clear()
	fx._pools[Fx.Kind.SOLID].clear()
	fx._shard(Vector3(0, 30, 0), Vector3(8, 6, 0), 0.4, Fx.Debris.GLASS)
	for i in 12:
		fx._process(0.05)
	check(fx._pools[Fx.Kind.GLOW].is_empty(), "a glass shard leaves no puffs")
	fx.queue_free()


func test_reused_slots_refresh_parameters_and_growth_keeps_live_payloads() -> void:
	for kind in [Fx.Kind.SOLID, Fx.Kind.GLOW, Fx.Kind.FLAME]:
		var fx := Fx.new()
		add_child(fx)
		fx.spawn(kind, Vector3.ZERO, Vector3.ZERO, 0.1, 2.0, Color.RED)
		fx._process(0.05)
		fx._process(0.1)
		fx.spawn(kind, Vector3.ONE, Vector3.ZERO, 3.0, 4.0, Color.BLUE, {"fade": 0.2})
		fx._process(0.05)
		for i in 200:
			fx.spawn(kind, Vector3(i, 5, 0), Vector3.ZERO, 2.0, 1.0, Color.GREEN)
		fx._process(0.05)
		var data: PackedFloat32Array = fx._buffers[kind]
		check_near(data[0], 4.0, 0.00001, "a reused slot gets the new particle's size")
		check_near(data[2], 3.0, 0.00001, "a reused slot gets the new lifetime")
		check_near(data[4], 0.2, 0.00001, "a reused slot gets the new fade threshold")
		check_eq(Color(data[12], data[13], data[14]), Color.BLUE, "growth preserves the live slot's color")
		check_near(data[16], 0.1, 0.00001, "growth preserves the live slot's age")
		for i in range(1, 201):
			check_eq(Color(data[i * Fx.STRIDE + 12], data[i * Fx.STRIDE + 13], data[i * Fx.STRIDE + 14]), Color.GREEN, "new slots upload their own color")
		fx.free()
