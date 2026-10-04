class_name BipedMech
extends Enemy
## Shared feet, breakable legs and hard-cover movement for the city bipeds.

var legs_hp := 30.0
var toppled := false
var _hard := false
var _body := Node3D.new()
var _legs: Array[Node3D] = []
var _cover: Prop
var _cover_goal := Vector3.INF
var _cover_wait := 0.0
var _peek := false
var _side := 1.0
var _search := 0.0
var _walk := 0.0


func _init() -> void:
	super()
	wreck_on_death = true
	stabbable = true
	radius = 2.0
	center_height = 3.0
	armor = 12.0
	weakness = {Hit.Kind.TAIL: 1.5, Hit.Kind.THROWN: 1.5, Hit.Kind.FRAGMENT: 0.3}


func build() -> void:
	_hard = Game.difficulty == Game.Difficulty.HARD
	model.add_child(_body)
	_body.position.y = 3.0


func add_mesh(parent: Node3D, mesh: Mesh) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	parent.add_child(instance)


func build_legs(stocky := false, color := Palette.SLATE, girth := 1.0) -> void:
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.85 * girth, 0, 0)
		_body.add_child(leg)
		var b := LowPoly.new()
		var w := girth
		b.blob(Transform3D(), 0.4 * w, Palette.INK)
		b.box(Transform3D(Basis(Vector3.RIGHT, -0.4 if not stocky else 0.1), Vector3(0, -0.65, -0.25)), Vector3((0.65 if stocky else 0.5) * w, 1.45, 0.7 * w), color)
		b.blob(Transform3D(Basis(), Vector3(0, -1.25, -0.55)), 0.4 * w, Palette.CORAL)
		b.box(Transform3D(Basis(Vector3.RIGHT, 0.4 if not stocky else -0.1), Vector3(0, -2, -0.25)), Vector3((0.6 if stocky else 0.42) * w, 1.55, 0.5 * w), color.darkened(0.25))
		b.box(Transform3D(Basis(), Vector3(0, -2.85, -0.45)), Vector3(0.9 * w, 0.3, 1.5 * w), Palette.INK)
		b.box(Transform3D(Basis(), Vector3(0, -2.65, -0.9)), Vector3(0.7 * w, 0.2, 0.5 * w), color.darkened(0.4))
		b.prism(Transform3D(Basis(), Vector3(side * 0.3 * w, -1.8, -0.2)), 0.09, 1.1, 6, Palette.ASH)
		add_mesh(leg, b.mesh())
		_legs.append(leg)


## Only solid scenery hides a hunter; wrecked buildings and light props do not.
static func hard_blocker(a: Vector3, b: Vector3, pad := 0.0) -> Prop:
	var best: Prop
	var distance := INF
	for prop: Prop in World.current.props.near(a, b, 32.0 + pad):
		if prop.dead or not prop.hard:
			continue
		var t := prop.hit_test(a, b, pad)
		if t >= 0.0 and t < distance:
			best = prop
			distance = t
	return best


static func line_blocked(a: Vector3, b: Vector3, pad := 0.0) -> bool:
	return hard_blocker(a, b, pad) != null


func seek_cover(tank: Tank) -> bool:
	var best := INF
	_cover = null
	for prop: Prop in World.current.props.in_radius(global_position, 45.0):
		if not prop.hard or prop.dead or prop.height < center_height + 1.0:
			continue
		var away := prop.global_position - tank.global_position
		away.y = 0.0
		var goal := prop.global_position + away.normalized() * (prop.footprint + radius + 1.0)
		goal.y = Course.height_at(goal)
		var distance := global_position.distance_to(goal)
		if distance < best and line_blocked(tank.hit_center(), goal + Vector3.UP * center_height):
			best = distance
			_cover = prop
			_cover_goal = goal
	_peek = false
	_cover_wait = 0.65
	return _cover != null


func relocate() -> void:
	_side = -_side
	_cover = null
	_cover_goal = Vector3.INF
	_search = 0.0
	_peek = false


## Walk around a footprint, never through it; both feet follow the active stage's ground height.
func walk_to(goal: Vector3, speed: float, delta: float) -> void:
	var offset := goal - global_position
	offset.y = 0.0
	var step := offset.limit_length(speed * delta)
	var next := global_position + step
	var blocker := hard_blocker(global_position + Vector3.UP, next + Vector3.UP, radius)
	if blocker != null:
		var radial := global_position - blocker.global_position
		radial.y = 0.0
		var tangent := Vector3(-radial.z, 0, radial.x).normalized()
		if tangent.dot(offset) < 0.0:
			tangent = -tangent
		next = global_position + tangent * step.length()
		if line_blocked(global_position + Vector3.UP, next + Vector3.UP, radius):
			next = global_position
	_walk += global_position.distance_to(next)
	global_position = next
	global_position.y = Course.height_at(next)


func move_hunter(tank: Tank, delta: float, planted: bool, keep := 65.0) -> void:
	var toward := tank.global_position - global_position
	model.rotation.y = lerp_angle(model.rotation.y, atan2(-toward.x, -toward.z), minf(delta * 4.0, 1.0))
	if toppled:
		_body.position.y = lerpf(_body.position.y, 1.0, minf(delta * 4.0, 1.0))
		model.rotation.z = lerpf(model.rotation.z, 0.9, minf(delta * 4.0, 1.0))
		return
	for i in _legs.size():
		_legs[i].rotation.x = sin(_walk * 1.4 + i * PI) * 0.18
	if planted or is_staggered():
		return
	if toward.length() < 25.0:
		walk_to(global_position - toward.normalized() * 12.0, 9.0 if _hard else 7.0, delta)
		return
	_search -= delta
	if not is_instance_valid(_cover) or _cover.dead:
		_cover = null
		if _search <= 0.0:
			seek_cover(tank)
			_search = 1.5
	if _cover != null:
		walk_to(_cover_goal, 8.0, delta)
		if global_position.distance_to(_cover_goal) < 1.0:
			_cover_wait -= delta
			if not _peek and _cover_wait <= 0.0:
				var away := (_cover.global_position - tank.global_position).normalized()
				var side := Vector3(-away.z, 0, away.x) * _side
				_cover_goal = _cover.global_position + side * (_cover.footprint + radius + 3.0)
				_cover_goal.y = Course.height_at(_cover_goal)
				_peek = true
		return
	var here := Course.to_course(global_position)
	var target_d := World.current.rail.d + tank.course_offset + keep
	if World.current.rail.mode == Rail.Mode.ARENA:
		target_d = Course.to_course(tank.global_position).x + keep
	walk_to(Course.ground_at(target_d, here.y + _side * 6.0), 9.0, delta)


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	if hidden:
		return -1.0
	var best := super(from, to, extra_radius)
	for leg in _legs:
		var t := Entity.segment_sphere(from, to, leg.to_global(Vector3(0, -1.6, -0.3)), 1.0 + extra_radius)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


func damage_multiplier(hit: Hit) -> float:
	return super(hit) * (2.0 if model.to_local(hit.position).y < 1.8 else 1.0)


func on_damaged(hit: Hit, amount: float) -> void:
	super(hit, amount)
	if not toppled and model.to_local(hit.position).y < 1.8:
		legs_hp -= amount
		if legs_hp <= 0.0:
			toppled = true
			interrupt()
			World.current.fx.debris(hit.position, 8, [Fx.Debris.METAL], 8.0, 0.3)
			World.current.award(150, global_position, false)
