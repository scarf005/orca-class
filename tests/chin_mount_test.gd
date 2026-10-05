extends TestCase


func _gunship(world: World) -> Gunship:
	world.director._start_boss({"kind": "gunship"})
	var boss := world.boss as Gunship
	boss._next_attack = 1000.0
	return boss


func test_chin_mount_stays_hull_fixed_while_canisters_and_muzzles_aim() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var meshes := boss._chin.find_children("*", "MeshInstance3D", true, false)
	var mount := meshes[0] as MeshInstance3D
	var canisters := meshes[1] as MeshInstance3D
	var fixed := boss.model.global_transform.affine_inverse() * mount.global_transform
	var initial := canisters.global_basis
	for direction in [Vector3(0, -1, -1), Vector3(-1, -1, -1), Vector3(1, -3, -1)]:
		world.player.global_position = boss._chin.global_position + boss.model.global_basis * direction * 25.0
		boss._aim_weapons(10.0, world.player)
		var relative := boss.model.global_transform.affine_inverse() * mount.global_transform
		check(relative.is_equal_approx(fixed), "the mount stays fixed relative to the hull during pitch and yaw")
		check(not canisters.global_basis.is_equal_approx(initial), "the canisters turn onto the target")
		var pivot := boss._chin_muzzles[0].get_parent() as Node3D
		var wanted := (world.player.hit_center() - pivot.global_position).normalized()
		for muzzle: Node3D in boss._chin_muzzles:
			check((-muzzle.global_basis.z.normalized()).is_equal_approx(wanted), "every muzzle follows the aimed bore")
		var before := world.projectiles.size()
		for i in 3:
			boss._launch_atgm(world.player, i)
		check_eq(world.projectiles.size() - before, 3, "the aimed launcher keeps its three-missile salvo")
		for i in 3:
			check(world.projectiles[before + i].global_position.is_equal_approx(boss._chin_muzzles[i].global_position), "each missile starts at its moving canister face")
	boss.model.rotate_z(0.3)
	check((boss.model.global_transform.affine_inverse() * mount.global_transform).is_equal_approx(fixed), "the fixed mount follows the airframe's bank")


func test_charged_hit_detaches_chin_mount_and_launcher_together_and_stops_atgm() -> void:
	var world := stage("boss")
	var boss := _gunship(world)
	var assembly: Node3D = boss.parts.chin.node
	var meshes := boss._chin.find_children("*", "MeshInstance3D", true, false)
	var mount := meshes[0] as MeshInstance3D
	var canisters := meshes[1] as MeshInstance3D
	var mount_before := mount.global_transform
	var canisters_before := canisters.global_transform
	boss._attack = Gunship.Attack.ATGM
	var hit := Hit.make(Hit.Kind.SHELL, 110.0, assembly.global_position)
	hit.caliber = 100
	hit.power = 1.0
	hit.source = world.player
	boss.take_hit(hit)
	check(not boss._live("chin"), "the accepted full-charge hit destroys the ATGM module")
	check_eq(boss._attack, Gunship.Attack.NONE, "destroying the module cancels its ATGM attack")
	check(assembly.get_parent() is Wreck, "the whole assembly is detached as one wreck")
	check(assembly.is_ancestor_of(mount) and assembly.is_ancestor_of(canisters), "both the fixed mount and rotating launcher leave with the wreck")
	check(mount.global_transform.is_equal_approx(mount_before), "detachment preserves the mount pose")
	check(canisters.global_transform.is_equal_approx(canisters_before), "detachment preserves the launcher pose")
	for muzzle: Node3D in boss._chin_muzzles:
		check(assembly.is_ancestor_of(muzzle), "the wreck owns every launch point")
