class_name Tail
extends Node3D
## The Orca-class's five-segment muscular tail. A spring drives the claw toward a goal and a
## FABRIK pass bends the segments to follow. Segments stretch and thin when reaching far.
## Radii taper continuously from root to tip and ball joints fill every bend, so it reads as one
## limb rather than floating pieces. It ends in an orca's two flukes.

signal arrived ## The claw reached its current goal.
signal missed ## A reach or stab ran out of time before arriving.

enum State { IDLE, REACH, RETURN, STAB, SWAT, ANCHOR }

const LENGTHS: Array[float] = [0.78, 0.68, 0.62, 0.52, 0.42] ## 3 m at rest.
const ROOT_RADIUS := 0.34
const TIP_RADIUS := 0.1
const MAX_STRETCH := 1.74 ## How far it can stretch reaching out; REACH matches.
const REACH := 5.2 ## Max claw distance from the mount, measured by action code.
const COOLDOWN := 0.45
const MAX_HP := 100.0
const REACH_TIMEOUT := 0.7
## Claw speeds (m/s) for strikes that must land even while the tank races past the target.
const STRIKE_SPEED := {State.REACH: 55.0, State.STAB: 65.0, State.RETURN: 40.0}

var state := State.IDLE
var hp := MAX_HP
var cooldown := 0.0
var goal := Vector3.ZERO ## World-space claw goal.
var goal_node: Node3D ## When set, the goal follows this node.
var held: Node3D ## Thing carried by the claw.
var mount: Node3D ## The tail's attachment point on the hull.
var joints: Array[Vector3] = []
var claw_open := 0.0
var destroyed := false

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
	joints.resize(LENGTHS.size() + 1)
	joints.fill(Vector3.ZERO)
	for i in LENGTHS.size():
		var segment := MeshInstance3D.new()
		segment.mesh = _segment_mesh(i)
		add_child(segment)
		_segments.append(segment)
		var knuckle := MeshInstance3D.new()
		knuckle.mesh = _knuckle_mesh(_radius(i))
		add_child(knuckle)
		_knuckles.append(knuckle)
	add_child(_claw_root)
	var palm := MeshInstance3D.new()
	palm.mesh = _palm_mesh()
	_claw_root.add_child(palm)
	for side in [-1.0, 1.0]:
		var pincer := Node3D.new()
		pincer.position = Vector3(0.04 * side, 0, -0.15)
		_claw_root.add_child(pincer)
		var mesh := MeshInstance3D.new()
		mesh.mesh = _pincer_mesh(side)
		pincer.add_child(mesh)
		_pincers.append(pincer)


func is_ready() -> bool:
	return not destroyed and cooldown <= 0.0 and state == State.IDLE


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


## Returns true when this hit tore the tail off. It only grows back from a pickup.
func damage(amount: float) -> bool:
	if destroyed:
		return false
	hp = maxf(hp - amount, 0.0)
	if hp > 0.0:
		return false
	destroyed = true
	held = null
	set_state(State.IDLE)
	visible = false
	return true


func regrow() -> void:
	destroyed = false
	hp = MAX_HP
	visible = true


func repair(amount: float) -> void:
	hp = minf(hp + amount, MAX_HP)


func update(delta: float, hull: Basis, lateral_velocity: float) -> void:
	_time += delta
	_state_time += delta
	cooldown = maxf(0.0, cooldown - delta)
	var base := mount.global_position
	if not _initialized:
		_claw = base + hull.z * 3.0 + Vector3.UP * 1.5
		for i in joints.size():
			joints[i] = base.lerp(_claw, float(i) / LENGTHS.size())
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
		State.REACH, State.STAB:
			claw_open = 1.0
		State.RETURN:
			target = base + hull.z * 1.0 + Vector3.UP * 3.0
			claw_open = 0.0
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
	if state in [State.REACH, State.STAB, State.RETURN] and _claw.distance_to(target) < 0.8:
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
	var last := LENGTHS.size()
	for j in range(1, last):
		joints[j] += Vector3.UP * 0.3 * sin(PI * j / last) - hull.z * 0.03
	for _i in 4:
		joints[last] = _claw
		for j in range(last - 1, -1, -1):
			joints[j] = joints[j + 1] + (joints[j] - joints[j + 1]).normalized() * lengths[j]
		joints[0] = base
		for j in range(0, last):
			joints[j + 1] = joints[j] + (joints[j + 1] - joints[j]).normalized() * lengths[j]


func _update_visuals() -> void:
	var last := LENGTHS.size()
	var stretch := clampf(joints[0].distance_to(joints[last]) / _total_length(), 1.0, MAX_STRETCH)
	var thin := 1.0 / sqrt(stretch)
	for i in last:
		var a := joints[i]
		var b := joints[i + 1]
		var dir := b - a
		var length := dir.length()
		if length < 0.001:
			continue
		var up := Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.BACK
		var basis := Basis.looking_at(dir, up)
		# Segment meshes point along local -Z with unit length.
		_segments[i].global_transform = Transform3D(basis * Basis.from_scale(Vector3(thin, thin, length)), a)
		_knuckles[i].global_transform = Transform3D(Basis.from_scale(Vector3.ONE * thin), a)
	var tip_dir := joints[last] - joints[last - 1]
	var up := Vector3.UP if absf(tip_dir.normalized().y) < 0.95 else Vector3.BACK
	_claw_root.global_transform = Transform3D(Basis.looking_at(tip_dir, up), joints[last])
	for i in _pincers.size():
		var side := -1.0 if i == 0 else 1.0
		# The flukes flex up and down as the tail works, and spread when it strikes.
		_pincers[i].rotation.z = side * (sin(_time * 5.0) * 0.12 + claw_open * 0.25)


## Radius at joint `index` (0 = root): a straight taper, shared by the segments meeting there.
func _radius(index: int) -> float:
	return lerpf(ROOT_RADIUS, TIP_RADIUS, float(index) / LENGTHS.size())


func _segment_mesh(index: int) -> Mesh:
	var b := LowPoly.new()
	var r0 := _radius(index)
	var r1 := _radius(index + 1)
	b.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3.ZERO), r0, 1.0, 8, Palette.HULL_LIGHT, r1)
	# Muscle ridges along the top and a pale belly plate underneath.
	b.box(Transform3D(Basis(), Vector3(0, (r0 + r1) * 0.46, -0.5)), Vector3((r0 + r1) * 0.35, 0.06, 0.8), Palette.FUNGUS)
	b.box(Transform3D(Basis(), Vector3(0, -(r0 + r1) * 0.44, -0.5)), Vector3((r0 + r1) * 0.5, 0.05, 0.7), Palette.BLUSH)
	return b.mesh()


func _knuckle_mesh(r: float) -> Mesh:
	return LowPoly.new().blob(Transform3D(), r * 1.04, Palette.HULL_LIGHT, 1, 0.0, 9).mesh()


func _palm_mesh() -> Mesh:
	# The narrow tail stock where the flukes join.
	var b := LowPoly.new()
	b.box(Transform3D(Basis(), Vector3(0, 0, -0.05)), Vector3(0.22, 0.2, 0.4), Palette.HULL_LIGHT)
	return b.mesh()


## One fluke of an orca's tail: a broad, flat lobe swept back and out to one side, dark on top
## and pale underneath, with a notched trailing edge.
func _pincer_mesh(side: float) -> Mesh:
	var b := LowPoly.new()
	var t := 0.05
	var root_front := Vector3(0.0, 0, -0.12)
	var root_back := Vector3(0.0, 0, 0.18)
	var tip := Vector3(0.95 * side, 0, 0.42)
	var lead := Vector3(0.55 * side, 0, -0.1)
	var trail := Vector3(0.45 * side, 0, 0.22)
	var up := Vector3.UP * t
	for face in [[root_front, lead, tip], [root_front, tip, trail], [root_front, trail, root_back]]:
		b.tri(face[0] + up, face[1] + up, face[2] + up, Palette.INK, Vector3.UP)
		b.tri(face[0] - up, face[1] - up, face[2] - up, Palette.CREAM, Vector3.DOWN)
	# Edges, so the lobe has a little thickness from the side.
	var outline := [root_front, lead, tip, trail, root_back]
	for i in outline.size() - 1:
		var a: Vector3 = outline[i]
		var c: Vector3 = outline[i + 1]
		b.quad(a + up, c + up, c - up, a - up, Palette.SLATE, ((a + c) * 0.5 - Vector3(0, 0, 0.1)).normalized())
	return b.mesh()
