extends TestCase


func test_gatling_mount_follows_rack_and_lock_and_hit_centers_follow_mount() -> void:
	var world := stage("boss")
	world.director._start_boss({"kind": "gunship"})
	var boss := world.boss as Gunship
	for i in Gunship.GATLINGS.size():
		var name: String = Gunship.GATLINGS[i]
		var rack := boss.parts["pod_l" if i == 0 else "pod_r"].node as MeshInstance3D
		var gun := boss._gatlings[i]
		var joint := boss.parts[name].node as Node3D
		check(joint.get_parent() == rack and gun.get_parent() == joint, "the rack carries the ball joint and its independent aiming pivot")
		var mount := joint.position
		var ball := joint.get_child(0) as MeshInstance3D
		check(is_equal_approx(mount.y + ball.mesh.get_aabb().end.y, rack.mesh.get_aabb().position.y), "the ball top touches the rack bottom without a gap or penetration")
		rack.rotation = Vector3(0.4, 0.5, -0.2)
		var expected := rack.to_global(mount)
		check(gun.global_position.is_equal_approx(expected), "rack rotation moves the gun mount")
		var locks := boss.aim_parts()
		check((locks[name][0] as Vector3).is_equal_approx(expected), "the lock center follows the moving mount")
		check(boss._struck_part(expected) == boss.parts[name], "a hit at the moving mount selects the gatling")
		boss.aim_barrel(gun, world.player.hit_center(), Gunship.GATLING_SLEW, 10.0)
		var bore := -gun.global_basis.z.normalized()
		check(bore.is_equal_approx((world.player.hit_center() - expected).normalized()), "the child gun still aims in world space")


func test_ball_joint_touches_rack_through_production_aiming() -> void:
	var world := stage("boss")
	world.director._start_boss({"kind": "gunship"})
	var boss := world.boss as Gunship
	var target := world.player.global_position
	world.player.velocity = Vector3.ZERO
	for pose in [Vector3.ZERO, Vector3(-20, 5, -10), Vector3(20, -5, 10)]:
		if pose != Vector3.ZERO:
			world.player.global_position = target + pose
			boss._aim_weapons(10.0, world.player)
		for i in Gunship.GATLINGS.size():
			var rack := boss.parts["pod_l" if i == 0 else "pod_r"].node as MeshInstance3D
			var gun := boss._gatlings[i]
			if pose != Vector3.ZERO:
				var bore := -boss._gatling_muzzles[i].global_basis.z.normalized()
				check(bore.is_equal_approx((world.player.hit_center() - gun.global_position).normalized()), "the muzzle tracks the target after its parent rack aims")
			var joint := boss.parts[Gunship.GATLINGS[i]].node as Node3D
			var ball := joint.get_child(0) as MeshInstance3D
			check(joint.basis == Basis.IDENTITY and ball.transform == Transform3D.IDENTITY, "the ball stays rack-fixed while the gun aims")
			var top := rack.to_local(ball.to_global(Vector3(0, ball.mesh.get_aabb().end.y, 0)))
			check(is_equal_approx(top.y, rack.mesh.get_aabb().position.y), "the ball top stays flush with the rack bottom")
			check(not rack.has_node("GatlingMount"), "no separate hanger extends the gun below its ball mount")
			var start := gun.global_position - rack.global_basis.y.normalized() * 0.4
			var end := rack.to_global(Vector3(joint.position.x, rack.mesh.get_aabb().position.y + 0.4, joint.position.z))
			check(_solid_joint([rack, ball], start, end), "actual mesh triangles continuously join the ball directly to the rack in every pose")


func test_destroyed_rack_carries_its_disabled_gatling_in_one_wreck() -> void:
	var world := stage("boss")
	world.director._start_boss({"kind": "gunship"})
	var boss := world.boss as Gunship
	var rack: Node3D = boss.parts.pod_l.node
	var gun: Node3D = boss.parts.gatling_l.node
	var ball := gun.get_child(0)
	var before := Wreck._live.size()
	boss.take_hit(_charged_shell(rack.global_position))
	check(rack.get_parent() is Wreck, "the destroyed rack becomes a wreck")
	check(gun.get_parent() == rack, "the gatling stays attached to its fallen rack")
	check(ball.get_parent() == gun, "the ball falls with its gun and rack")
	check_eq(Wreck._live.size(), before + 1, "the rack and gun share one wreck")
	check(not boss._live("gatling_l") and boss._live("gatling_r"), "only the attached gatling is disabled")
	check_eq(boss._gatlings[0], null, "the fallen gun stops aiming")


func test_destroyed_gatling_detaches_without_destroying_its_rack() -> void:
	var world := stage("boss")
	world.director._start_boss({"kind": "gunship"})
	var boss := world.boss as Gunship
	var gun: Node3D = boss.parts.gatling_r.node
	boss.take_hit(_charged_shell(gun.global_position))
	check(gun.get_parent() is Wreck, "a destroyed gun detaches as its own wreck")
	check(boss._live("pod_r"), "the parent rack survives")
	check((gun.get_child(0) as MeshInstance3D).get_parent() == gun, "the entire ball-mounted gun detaches together")


## Closed-mesh entry/exit pairs on the joint axis prove solid coverage, not AABB overlap.
func _solid_joint(meshes: Array[MeshInstance3D], start: Vector3, end: Vector3) -> bool:
	var axis := (end - start).normalized()
	# Extend past the complete rack so both entry and exit faces are intersected.
	var padding := 10.0
	var from := start - axis * padding
	var to := end + axis * padding
	var intervals: Array[Vector2] = []
	for instance in meshes:
		var crossings: Array[float] = []
		for surface in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			for i in range(0, indices.size() if not indices.is_empty() else vertices.size(), 3):
				var a := vertices[indices[i] if not indices.is_empty() else i]
				var b := vertices[indices[i + 1] if not indices.is_empty() else i + 1]
				var c := vertices[indices[i + 2] if not indices.is_empty() else i + 2]
				var point: Variant = Geometry3D.segment_intersects_triangle(from, to, instance.to_global(a), instance.to_global(b), instance.to_global(c))
				if point != null:
					crossings.append((point - from).dot(axis))
		crossings.sort()
		var unique: Array[float] = []
		for crossing in crossings:
			# Adjacent triangles share edges; transform roundoff can duplicate an intersection.
			if unique.is_empty() or not is_equal_approx(unique.back(), crossing):
				unique.append(crossing)
		for i in range(0, unique.size() - 1, 2):
			intervals.append(Vector2(unique[i], unique[i + 1]))
	intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var covered := padding
	for interval in intervals:
		if interval.y < covered:
			continue
		if interval.x > covered and not is_equal_approx(interval.x, covered):
			return false
		covered = maxf(covered, interval.y)
		if covered >= padding + start.distance_to(end):
			return true
	return false


func _charged_shell(at: Vector3) -> Hit:
	var hit := Hit.make(Hit.Kind.SHELL, 110.0, at, Vector3.FORWARD)
	hit.caliber = 100
	hit.power = 1.0
	return hit
