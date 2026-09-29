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
	check_near(data[16], 1.5, 0.00001, "shader size follows particle lifetime")
	check_near(data[15], 1.0 - smoothstep(0.0, 1.0, 0.25), 0.00001, "screen-door fade remains unchanged")
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
		check_near(data[i * Fx.STRIDE + 16], p.layer, 0.00001, "compacted debris keeps its sprite")
		check_near(data[i * Fx.STRIDE + 18], p.spin.x + p.spin.z * p.life, 0.00001, "compacted debris keeps its roll")
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
