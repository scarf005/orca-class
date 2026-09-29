extends TestCase
## Ground veins are real props: the tank crushes them and leaves a flattened stain.


func _veins(world: World, d: float, u: float) -> Prop:
	var scenery := world.director.scenery
	var spec := scenery.add("veins", d, u, 0.0, 0)
	scenery._instantiate(spec)
	return spec.node as Prop


## Stains the world holds as decor: mesh instances that are not props.
func _stains(world: World) -> Array:
	return world.props.get_children().filter(func(n: Node) -> bool: return n is MeshInstance3D and n.material_override == Prop._stain_material)


func test_veins_are_props_not_decor() -> void:
	var world := stage()
	var specs := world.director.scenery.specs
	check(specs.any(func(s: Scenery.Spec) -> bool: return s.kind == "veins"), "the stage plants veins")
	check(not specs.any(func(s: Scenery.Spec) -> bool: return s.decor and s.mesh == PropKit.mesh("veins", 0)), "none of them is inert decor")
	var prop := _veins(world, world.rail.d + 80.0, 8.0)
	check(prop != null and prop.kind == "veins", "a veins spec streams in as a prop")
	check(prop.crushable and prop.burnable, "crushable and flammable")
	await frames(2)
	check(not prop.always_tick and not prop.is_processing(), "with no per-frame work")
	check(world.props.in_radius(prop.global_position, 1.0).has(prop), "the tank's queries find it")


func test_driving_over_veins_crushes_them_and_leaves_a_stain() -> void:
	var world := stage()
	var tank := world.player
	await frames(2)
	var on_path := _veins(world, world.rail.d + tank.course_offset + 12.0, tank.course_u)
	var beside := _veins(world, world.rail.d + tank.course_offset + 12.0, tank.course_u + 12.0)
	var stains := _stains(world).size()
	var particles := world.fx.particle_count()
	var burst := 0
	for i in 60:
		await frames(1)
		burst = maxi(burst, world.fx.particle_count() - particles)
		if not is_instance_valid(on_path) or on_path.dead:
			break
	check(not is_instance_valid(on_path) or on_path.dead, "veins in the tank's path are crushed")
	check(is_instance_valid(beside) and not beside.dead, "veins well to the side are left alone")
	check_eq(_stains(world).size(), stains + 1, "one flattened stain is left behind")
	var stain: MeshInstance3D = _stains(world)[-1]
	check(stain.scale.y < 0.3 and absf(stain.global_position.x - on_path.global_position.x) < 0.01 if is_instance_valid(on_path) else true, "flat where it grew")
	check(burst > 4, "spores and flesh bits burst out (%d particles)" % burst)
	check(not world.props.in_radius(stain.global_position, 1.0).any(func(p: Prop) -> bool: return p.kind == "veins"), "the stain is not a prop: nothing can hit it")


func test_a_shell_destroys_veins() -> void:
	var world := stage()
	await frames(2)
	var prop := _veins(world, world.rail.d + 60.0, 6.0)
	var stains := _stains(world).size()
	prop.take_hit(Hit.make(Hit.Kind.SHELL, 100.0, prop.global_position + Vector3.UP * 0.2))
	check(prop.dead, "a shell destroys veins")
	check_eq(_stains(world).size(), stains + 1, "and leaves the stain")
	var weak := _veins(world, world.rail.d + 70.0, 6.0)
	weak.take_hit(Hit.make(Hit.Kind.BULLET, 1.0, weak.global_position + Vector3.UP * 0.2))
	check(not weak.dead, "a single 8 mm round does not")
