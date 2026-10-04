extends TestCase
## Animated effects use independent material uniforms, including on WebGL.


func _fx() -> Fx:
	var fx := Fx.new()
	add_child(fx)
	fx.set_process(false)
	return fx


func test_beams_fade_independently_without_instance_uniforms() -> void:
	var fx := _fx()
	fx.beam(Vector3.ZERO, Vector3.FORWARD * 20.0, Palette.WHITE, 0.5, 1.0)
	fx.beam(Vector3.RIGHT, Vector3.FORWARD * 20.0, Palette.WHITE, 0.5, 2.0)
	var first: ShaderMaterial = fx._transients[0].node.material_override
	var second: ShaderMaterial = fx._transients[1].node.material_override
	fx._update_transients(0.75)
	check_eq(first.get_shader_parameter("instance_alpha"), 0.5, "the older beam fades through a material uniform")
	check_eq(second.get_shader_parameter("instance_alpha"), 1.0, "the younger beam stays bright")
	check(Fx._flame_material != first and Fx._flame_material != second, "particle pools do not share the animated beam material")
	fx.queue_free()


func test_fireballs_cool_independently() -> void:
	var fx := _fx()
	fx.fireball(Vector3.ZERO, 1.0, 3.0, 1.0)
	fx.fireball(Vector3.RIGHT, 1.0, 3.0, 2.0)
	var first: ShaderMaterial = fx._transients[0].node.material_override
	var second: ShaderMaterial = fx._transients[1].node.material_override
	fx._update_transients(0.25)
	check_eq(first.get_shader_parameter("progress"), 0.25, "the first fireball cools")
	check_eq(second.get_shader_parameter("progress"), 0.125, "the second fireball cools more slowly")
	check(Fx._fireball_material != first and Fx._fireball_material != second, "new fireballs use an unmodified template")
	fx.queue_free()


func test_afterimage_tint_does_not_leak_into_beams() -> void:
	var fx := _fx()
	var source := MeshInstance3D.new()
	source.mesh = BoxMesh.new()
	add_child(source)
	fx.afterimage([source], Palette.MINT)
	var ghost: ShaderMaterial = fx._transients[0].node.material_override
	fx.beam(Vector3.ZERO, Vector3.FORWARD * 20.0, Palette.WHITE)
	var beam: ShaderMaterial = fx._transients[1].node.material_override
	check_eq(ghost.get_shader_parameter("instance_tint"), Color(Palette.MINT, 0.8), "the ghost has its own tint")
	check_eq(beam.get_shader_parameter("instance_tint"), Fx._flame_material.get_shader_parameter("instance_tint"), "the beam retains its default vertex color")
	source.queue_free()
	fx.queue_free()


func test_fire_zone_layers_and_zones_have_independent_brightness() -> void:
	var world := stage()
	var at := Course.ground_at(world.rail.d + 30.0, 0.0)
	FireZone.ignite(at)
	var first: FireZone = FireZone._zones[-1]
	FireZone.ignite(at + Vector3.RIGHT * FireZone.RADIUS * 3.0)
	var second: FireZone = FireZone._zones[-1]
	first._glow(0.5)
	second._glow(0.25)
	check_near(first._rim.material_override.get_shader_parameter("instance_alpha"), 0.35, 0.001, "the first rim stays bright")
	check_near(first._core.material_override.get_shader_parameter("instance_alpha"), 0.225, 0.001, "its core has a different brightness")
	check_near(second._rim.material_override.get_shader_parameter("instance_alpha"), 0.175, 0.001, "the second zone has its own heat")


func test_hostile_halo_alpha_does_not_leak_into_other_shots() -> void:
	var first := World.projectile_visual("orb", Palette.HOSTILE, true)
	var second := World.projectile_visual("orb", Palette.HOSTILE, true)
	second[1].material_override.set_shader_parameter("instance_alpha", 1.0)
	first[1].material_override.set_shader_parameter("instance_alpha", 0.3)
	check_eq(second[1].material_override.get_shader_parameter("instance_alpha"), 1.0, "another shot's halo stays bright")
	for mesh in first + second:
		mesh.free()
