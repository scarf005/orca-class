class_name Tail
extends Node3D
## The Orca-class's three-segment muscular tail. A spring drives the claw toward a goal and a
## FABRIK pass bends the segments to follow. Segments stretch and thin when reaching far.

signal arrived ## The claw reached its current goal.
signal missed ## A reach or stab ran out of time before arriving.

enum State { IDLE, REACH, RETURN, HOLD, THROW, STAB, SWAT, ANCHOR }

const LENGTHS: Array[float] = [1.8, 1.55, 1.3]
const MAX_STRETCH := 1.9
const REACH := 9.0 ## Max claw distance from the mount, measured by action code.
const COOLDOWN := 0.45
const MAX_HP := 100.0
const REACH_TIMEOUT := 0.7
## Claw speeds (m/s) for strikes that must land even while the tank races past the target.
const STRIKE_SPEED := {State.REACH: 55.0, State.STAB: 65.0, State.RETURN: 40.0, State.THROW: 50.0}

var state := State.IDLE
var hp := MAX_HP
var cooldown := 0.0
var goal := Vector3.ZERO ## World-space claw goal.
var goal_node: Node3D ## When set, the goal follows this node.
var held: Node3D ## Thing carried by the claw.
var mount: Node3D ## The tail's attachment point on the hull.
var joints: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var claw_open := 0.0

var _claw := Vector3.ZERO
var _claw_velocity := Vector3.ZERO
var _stiffness := 90.0
var _time := 0.0
var _state_time := 0.0
var _segments: Array[MeshInstance3D] = []
var _knuckles: Array[MeshInstance3D] = []
var _claw_root := Node3D.new()
var _pincers: Array[Node3D] = []
var _initialized := false


func _ready() -> void:
	top_level = true
	for i in LENGTHS.size():
		var segment := MeshInstance3D.new()
		segment.mesh = _segment_mesh(i)
		add_child(segment)
		_segments.append(segment)
		var knuckle := MeshInstance3D.new()
		knuckle.mesh = _knuckle_mesh(0.34 - i * 0.06)
		add_child(knuckle)
		_knuckles.append(knuckle)
	add_child(_claw_root)
	var palm := MeshInstance3D.new()
	palm.mesh = _palm_mesh()
	_claw_root.add_child(palm)
	for side in [-1.0, 1.0]:
		var pincer := Node3D.new()
		pincer.position = Vector3(0.14 * side, 0, -0.2)
		_claw_root.add_child(pincer)
		var mesh := MeshInstance3D.new()
		mesh.mesh = _pincer_mesh(side)
		pincer.add_child(mesh)
		_pincers.append(pincer)


func is_ready() -> bool:
	return cooldown <= 0.0 and state in [State.IDLE, State.HOLD]


func is_hurt() -> bool:
	return hp < MAX_HP * 0.5


func claw_position() -> Vector3:
	return _claw


func set_state(value: State, target := Vector3.ZERO, node: Node3D = null, stiffness := 90.0) -> void:
	state = value
	goal = target
	goal_node = node
	_stiffness = stiffness * (0.65 if is_hurt() else 1.0)
	_state_time = 0.0


func start_cooldown(scale := 1.0) -> void:
	cooldown = COOLDOWN * scale * (1.6 if is_hurt() else 1.0)


func damage(amount: float) -> void:
	hp = maxf(hp - amount, 12.0) # Never fully disabled.


func repair(amount: float) -> void:
	hp = minf(hp + amount, MAX_HP)


func update(delta: float, hull: Basis, lateral_velocity: float) -> void:
	_time += delta
	_state_time += delta
	cooldown = maxf(0.0, cooldown - delta)
	var base := mount.global_position
	if not _initialized:
		_claw = base + hull.z * 3.0 + Vector3.UP * 1.5
		for i in 4:
			joints[i] = base.lerp(_claw, i / 3.0)
		_initialized = true
	if is_instance_valid(goal_node):
		goal = goal_node.global_position + Vector3.UP * 0.6
	var target := goal
	match state:
		State.IDLE:
			# Rests high behind the tank, swaying like a living thing and trailing on turns.
			# The camera sits behind the tank, so the tail rests curled off to the right side
			# instead of trailing straight back into the view.
			target = base + hull.z * 1.2 + Vector3.UP * (1.1 + sin(_time * 2.1) * 0.2) \
				+ hull.x * (2.6 + sin(_time * 1.3) * 0.35 - lateral_velocity * 0.1)
			claw_open = 0.15 + sin(_time * 3.0) * 0.1
		State.HOLD:
			target = base + hull.z * 0.8 + Vector3.UP * 3.2 + hull.x * sin(_time * 2.0) * 0.2
			claw_open = 0.0
		State.REACH, State.STAB:
			claw_open = 1.0
		State.RETURN:
			target = base + hull.z * 1.0 + Vector3.UP * 3.0
			claw_open = 0.0
		State.THROW:
			claw_open = 1.0 if _state_time > 0.08 else 0.0
		State.SWAT:
			var angle := _state_time * 22.0
			target = base + Vector3.UP * 1.2 + (hull.z * cos(angle) + hull.x * sin(angle)) * 6.5
			claw_open = 0.3
		State.ANCHOR:
			claw_open = 0.0
	if STRIKE_SPEED.has(state):
		# Strikes chase the goal directly; a spring would trail a target moving at rail speed.
		var speed: float = STRIKE_SPEED[state] * (0.7 if is_hurt() else 1.0)
		var previous := _claw
		_claw = _claw.move_toward(target, speed * delta)
		_claw_velocity = (_claw - previous) / maxf(delta, 0.0001)
		if state in [State.REACH, State.STAB] and _state_time > REACH_TIMEOUT:
			set_state(State.IDLE)
			start_cooldown()
			missed.emit()
	else:
		# Critically damped spring for idle sway, holding and swats.
		var k := _stiffness
		var accel := (target - _claw) * k - _claw_velocity * 2.0 * sqrt(k)
		_claw_velocity += accel * delta
		_claw += _claw_velocity * delta
	if state == State.ANCHOR:
		_claw = _claw.lerp(target, 0.6)
	var offset := _claw - base
	var max_reach := _total_length() * MAX_STRETCH
	if offset.length() > max_reach:
		_claw = base + offset.normalized() * max_reach
	if state in [State.REACH, State.STAB, State.RETURN, State.THROW] and _claw.distance_to(target) < 0.8:
		arrived.emit()
	_solve(base, hull)
	_update_visuals()
	if is_instance_valid(held):
		held.global_position = _claw + Vector3.DOWN * 0.5


func _total_length() -> float:
	var total := 0.0
	for l in LENGTHS:
		total += l
	return total


func _solve(base: Vector3, hull: Basis) -> void:
	var distance := base.distance_to(_claw)
	var stretch := clampf(distance / (_total_length() * 0.98), 1.0, MAX_STRETCH)
	var lengths: Array[float] = []
	for l in LENGTHS:
		lengths.append(l * stretch)
	# Bias the middle joints upward so the tail arches like a scorpion instead of sagging.
	joints[1] += Vector3.UP * 0.3 - hull.z * 0.05
	joints[2] += Vector3.UP * 0.2
	for _i in 4:
		joints[3] = _claw
		for j in range(2, -1, -1):
			joints[j] = joints[j + 1] + (joints[j] - joints[j + 1]).normalized() * lengths[j]
		joints[0] = base
		for j in range(0, 3):
			joints[j + 1] = joints[j] + (joints[j + 1] - joints[j]).normalized() * lengths[j]


func _update_visuals() -> void:
	var stretch := clampf(joints[0].distance_to(joints[3]) / _total_length(), 1.0, MAX_STRETCH)
	var thin := 1.0 / sqrt(stretch)
	for i in 3:
		var a := joints[i]
		var b := joints[i + 1]
		var dir := b - a
		var length := dir.length()
		if length < 0.001:
			continue
		var up := Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.BACK
		var basis := Basis.looking_at(dir, up)
		# Segment meshes point along local -Z with unit length.
		_segments[i].global_transform = Transform3D(basis.scaled(Vector3(thin, thin, length)), a)
		_knuckles[i].global_position = a
	var tip_dir := joints[3] - joints[2]
	var up := Vector3.UP if absf(tip_dir.normalized().y) < 0.95 else Vector3.BACK
	_claw_root.global_transform = Transform3D(Basis.looking_at(tip_dir, up), joints[3])
	for i in _pincers.size():
		var side := -1.0 if i == 0 else 1.0
		_pincers[i].rotation.y = side * lerpf(0.05, 0.7, claw_open)


func _segment_mesh(index: int) -> Mesh:
	var b := LowPoly.new()
	var r0 := 0.3 - index * 0.06
	var r1 := r0 - 0.06
	b.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3.ZERO), r0, 1.0, 6, Palette.HULL_LIGHT if index % 2 == 0 else Palette.BLUSH, r1)
	# A muscle band along the top.
	b.box(Transform3D(Basis(), Vector3(0, r0 * 0.85, -0.5)), Vector3(r0 * 0.7, 0.08, 0.6), Palette.FUNGUS)
	return b.mesh()


func _knuckle_mesh(r: float) -> Mesh:
	return LowPoly.new().blob(Transform3D(), r, Palette.MAUVE, 0, 0.1, 9).mesh()


func _palm_mesh() -> Mesh:
	var b := LowPoly.new()
	b.box(Transform3D(Basis(), Vector3(0, 0, 0.05)), Vector3(0.45, 0.3, 0.45), Palette.MAUVE)
	return b.mesh()


func _pincer_mesh(side: float) -> Mesh:
	var b := LowPoly.new()
	var root_a := Vector3(0.0, 0.12, 0)
	var root_b := Vector3(0.0, -0.12, 0)
	var outer := Vector3(0.28 * side, 0, -0.45)
	var tip := Vector3(-0.08 * side, 0, -0.95)
	b.tri(root_a, outer, tip, Palette.FUNGUS, Vector3.UP)
	b.tri(root_b, outer, tip, Palette.CORAL, Vector3.DOWN)
	b.tri(root_a, root_b, tip, Palette.BLUSH, Vector3(-side, 0, 0))
	b.tri(root_a, root_b, outer, Palette.FUNGUS, Vector3(side, 0, 0.3))
	return b.mesh()
