extends TestCase
## Long rendering frames must not make the tail's spring produce non-finite transforms.


func test_tail_spring_stays_finite_during_long_frames() -> void:
	var world := stage()
	world.player.set_process(false)
	var tail := world.player.tail
	tail.set_state(Tail.State.SWAT, world.player.global_position, null, 300.0)
	var finite := true
	for i in 240:
		tail.update(0.2, world.player.global_basis, 24.0)
		finite = tail._claw.is_finite() and tail._claw_velocity.is_finite() \
			and tail.joints.all(func(p: Vector3) -> bool: return p.is_finite()) \
			and tail._segments.all(func(s: MeshInstance3D) -> bool: return s.global_transform.is_finite()) \
			and tail._claw_root.global_transform.is_finite()
		if not finite:
			break
	check(finite, "200 ms frames keep the tail spring, joints and rendered transforms finite")
