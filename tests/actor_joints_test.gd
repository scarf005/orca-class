extends TestCase
## The imported geometry stays on code-owned mounts when aimed, stretched or torn off.


func _position_error(point: Vector3) -> float:
	# Up to eight parent transforms, four float32 terms per coordinate.
	return 32.0 / 8388608.0 * maxf(1.0, point.length())


func test_tail_imported_segments_and_knuckles_meet_solver_joints_during_a_stab() -> void:
	var world := stage()
	var tank := world.player
	tank.set_process(false)
	var tail := tank.tail
	tail.update(1.0 / 60.0, tank.global_basis, 0.0)
	var crawler := Crawler.new()
	crawler.position = tail.mount.global_position + tank.global_basis.x * 4.0
	world.add_enemy(crawler)
	crawler.set_process(false)
	tank.auto_tail()
	check_eq(tail.state, Tail.State.STAB, "production targeting starts a stab")
	for _frame in 60:
		if crawler.dead:
			break
		tail.update(1.0 / 60.0, tank.global_basis, 0.0)
		for i in Tail.LENGTHS.size():
			var segment := tail._segments[i]
			var start := segment.to_global(Vector3.ZERO)
			var end := segment.to_global(Vector3.FORWARD)
			check(start.distance_to(tail.joints[i]) <= _position_error(start), "segment root stays at its solver joint")
			check(end.distance_to(tail.joints[i + 1]) <= _position_error(end), "unit imported segment stretches to the next joint")
			check(tail._knuckles[i].global_position.distance_to(start) <= _position_error(start), "knuckle fills the bend at the root")
			# Read the authored root ring, rather than duplicating the old radius formula.
			var ring_radius := 0.0
			for vertex in segment.mesh.get_faces():
				if absf(vertex.z) <= 1.0 / 8388608.0:
					ring_radius = maxf(ring_radius, Vector2(vertex.x, vertex.y).length())
			check(ring_radius > 0.0, "authored segment has a ring at its pivot")
			check(tail._knuckles[i].mesh.get_aabb().size.x * 0.5 > ring_radius, "visible knuckle covers the segment ring")
	check(crawler.dead, "the visible stab reaches and kills its production target")


func test_tank_aim_keeps_sensors_and_muzzle_on_their_imported_mounts() -> void:
	var world := stage()
	var tank := world.player
	var model := tank.model
	world.camera.global_position = tank.global_position + Vector3(0, 8, 15)
	world.camera.look_at(tank.global_position + Vector3(0, 1, -30))
	var bearings: Array[Vector3] = []
	for angle in [-0.8, 0.0, 0.8]:
		tank.aim_screen = Vector2(DitherView.RESOLUTION) * Vector2(0.5 + angle * 0.4, 0.3)
		for _frame in 60:
			tank._update_aim(1.0 / 60.0)
		bearings.append(model.turret.rotation)
		check_eq(model.rws.position, Vector3(-0.85, 0.95, 0.75), "RWS mount remains fixed on the turret")
		check_eq(model.fcs.position, Vector3(0.85, 0.95, 1.25), "FCS mount remains fixed on the turret")
		check_eq(model.gun_pivot.position, Vector3(0, 0.42, -1.55), "gun remains in the mantlet")
		var mesh := model.barrel.get_child(0) as MeshInstance3D
		var tip := mesh.to_global(Vector3(0, 0, mesh.mesh.get_aabb().position.z))
		check(tip.distance_to(model.muzzle.global_position) <= _position_error(tip), "muzzle follows the end of the imported main gun")
	check(bearings[0] != bearings[1] and bearings[1] != bearings[2], "production aiming actually traversed between the three poses")


func test_sensor_damage_detaches_shared_meshes_at_the_mounted_pose() -> void:
	var world := stage()
	var tank := world.player
	for sensor in ["laser", "fcs"]:
		var part := tank.model.rws if sensor == "laser" else tank.model.fcs
		var before := part.global_transform
		var source := (part.get_child(0) as MeshInstance3D).mesh
		check(tank.damage_module(sensor, TankModules.MAX[sensor]), "damage destroys the mounted sensor")
		check_eq(tank.modules.state(sensor), TankModules.State.DESTROYED, "sensor is no longer functional")
		check(not part.visible, "the mounted geometry disappears")
		var wreck := Wreck._live.back() as Wreck
		var loose := wreck.get_child(0) as Node3D
		check(loose.global_position.distance_to(before.origin) <= _position_error(before.origin), "detached piece starts at the mounted pose")
		check((loose.get_child(0) as MeshInstance3D).mesh == source, "detachment reuses the immutable imported mesh")
		check(not wreck.explodes, "sensor wreck lifecycle is unchanged")


func test_gunship_aim_and_module_damage_keep_imported_parts_on_code_owned_pivots() -> void:
	var world := stage("boss")
	world.director._start_boss({"kind": "gunship"})
	var boss := world.boss as Gunship
	boss._next_attack = INF
	for _frame in 120:
		boss.behave(1.0 / 60.0)
	for name: String in Gunship.MODULE_HP:
		var part: Gunship.Part = boss.parts[name]
		check_eq(part.node.position, part.offset, name + " stays attached while weapons traverse")
	var part: Gunship.Part = boss.parts.nose_gun
	var node := part.node
	var source := (node as MeshInstance3D).mesh
	var at := node.global_position
	var hit := Hit.make(Hit.Kind.SHELL, Armament.SHELL_DAMAGE, at, Vector3.UP)
	hit.caliber = 100
	hit.power = 1.0
	hit.source = world.player
	boss.take_hit(hit)
	check_eq(part.hp, 0.0, "charged shell destroys the cannon module")
	check(node.get_parent() is Wreck, "the imported cannon is detached into a wreck")
	check((node as MeshInstance3D).mesh == source, "the detached cannon keeps its shared geometry")
	check(node.global_position.distance_to(at) <= _position_error(at), "detachment preserves the traversed pose")
	check(boss.parts.chin.hp > 0.0 and boss._chin.get_parent() == boss.model, "the neighboring chin mount is unaffected")
