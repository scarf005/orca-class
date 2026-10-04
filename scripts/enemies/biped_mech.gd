class_name BipedMech
extends Enemy
## Shared feet, breakable legs and hard-cover movement for the city bipeds.

enum Stance { ADVANCE, COVER, HIDE, PEEK, EXPOSED }

const HIDE_TIME := 1.1 ## Seconds behind cover before it peeks.
const EXPOSE_TIME := 8.0 ## Seconds in the open before it ducks away again.
const VOLLEYS_PER_PEEK := 2 ## Attacks it makes from one firing position before it moves.

var min_range := 0.0 ## Nearest it will stand to the tank when picking cover.
var legs_hp := 30.0
var toppled := false
var _hard := false
var _body := Node3D.new()
var _legs: Array[Node3D] = []
var _cover: Prop
var _cover_goal := Vector3.INF
var _cover_wait := 0.0
var _peek := false
var _avoid: Prop ## The cover it just left.
var _stance := Stance.ADVANCE
var _stance_time := 0.0
var _volleys := 0
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
		if prop == _avoid or not prop.hard or prop.dead or prop.global_position.y + prop.height < global_position.y + center_height + 1.0:
			continue
		var away := prop.global_position - tank.global_position
		away.y = 0.0
		var goal := CityCover.outside_point(prop, away, radius + 1.0)
		goal.y = CityCover.surface_at(goal, global_position.y + 1.0)
		var distance := global_position.distance_to(goal)
		if goal.distance_to(tank.global_position) < min_range:
			continue
		if distance < best and line_blocked(tank.hit_center(), goal + Vector3.UP * center_height):
			best = distance
			_cover = prop
			_cover_goal = goal
	_peek = false
	_cover_wait = HIDE_TIME
	_stance = Stance.COVER if _cover != null else Stance.ADVANCE
	_stance_time = 0.0
	return _cover != null


## The nearest spot around the cover, outside its footprint, that sees the tank; INF when none does.
func peek_spot(tank: Tank) -> Vector3:
	var best := INF
	var spot := Vector3.INF
	var toward := tank.global_position - _cover.global_position
	toward.y = 0.0
	for step in 12:
		var direction := toward.rotated(Vector3.UP, TAU * step / 12.0)
		var candidate := CityCover.outside_point(_cover, direction, radius + 2.0)
		candidate.y = CityCover.surface_at(candidate, global_position.y + 1.0)
		if hard_blocker(candidate + Vector3.UP * (radius + 0.1), candidate + Vector3.UP * (radius + 0.2), radius) != null:
			continue
		if line_blocked(tank.hit_center(), candidate + Vector3.UP * center_height):
			continue
		var distance := global_position.distance_to(candidate)
		if distance < best:
			best = distance
			spot = candidate
	return spot


## Leaves the current cover for another one, never straight back to it.
func relocate() -> void:
	_side = -_side
	_avoid = _cover
	_cover = null
	_cover_goal = Vector3.INF
	_search = 0.0
	_peek = false
	_stance = Stance.ADVANCE
	_stance_time = 0.0


## An attack finished: it fires again from the same spot, then moves on.
func volley_done() -> void:
	_volleys += 1
	if _volleys >= VOLLEYS_PER_PEEK:
		_volleys = 0
		relocate()


## Called when the hunter steps into a firing position: an attack should follow at once.
func on_exposed() -> void:
	pass


## Walk around a footprint, keeping the current deck without climbing overhead roofs.
func walk_to(goal: Vector3, speed: float, delta: float) -> void:
	var offset := goal - global_position
	offset.y = 0.0
	var step := offset.limit_length(speed * delta)
	var next := global_position + step
	var clearance := Vector3.UP * (radius + 0.1)
	var blocker := hard_blocker(global_position + clearance, next + clearance, radius)
	if blocker != null:
		var radial := global_position - blocker.global_position
		radial.y = 0.0
		var tangent := Vector3(-radial.z, 0, radial.x).normalized()
		if blocker.box_size != Vector3.ZERO:
			var local := blocker.to_local(global_position)
			var half := blocker.box_size * 0.5 + Vector3.ONE * radius
			tangent = blocker.global_basis.z if absf(local.x) / half.x > absf(local.z) / half.z else blocker.global_basis.x
		if tangent.dot(offset) < 0.0:
			tangent = -tangent
		next = global_position + tangent * step.length()
		if line_blocked(global_position + clearance, next + clearance, radius):
			next = global_position
	_walk += global_position.distance_to(next)
	global_position = next
	global_position.y = CityCover.surface_at(next, next.y + 1.0)


func move_hunter(tank: Tank, delta: float, planted: bool, keep := 52.0) -> void:
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
	if toward.length() < maxf(25.0, min_range * 0.7):
		walk_to(global_position - toward.normalized() * 12.0, 9.0 if _hard else 7.0, delta)
		return
	_stance_time += delta
	if _stance != Stance.ADVANCE and (not is_instance_valid(_cover) or _cover.dead):
		relocate()
	match _stance:
		Stance.ADVANCE:
			_search -= delta
			if _search <= 0.0:
				_search = 1.2
				if seek_cover(tank):
					return
				_avoid = null
		Stance.COVER:
			walk_to(_cover_goal, 8.0, delta)
			if global_position.distance_to(_cover_goal) < 1.0 or _stance_time > 8.0:
				_stance = Stance.HIDE
				_stance_time = 0.0
			return
		Stance.HIDE:
			if _stance_time >= HIDE_TIME:
				var spot := peek_spot(tank)
				if spot == Vector3.INF:
					relocate()
				else:
					_cover_goal = spot
					_peek = true
					_stance = Stance.PEEK
					_stance_time = 0.0
			return
		Stance.PEEK:
			walk_to(_cover_goal, 8.5, delta)
			if not line_blocked(hit_center(), tank.hit_center()):
				_stance = Stance.EXPOSED
				_stance_time = 0.0
				on_exposed()
			elif global_position.distance_to(_cover_goal) < 1.0 or _stance_time > 4.0:
				relocate()
			return
		Stance.EXPOSED:
			# Stand and fight; a hunter that cannot see the tank any more, or has fought long enough, moves on.
			if _stance_time > EXPOSE_TIME or line_blocked(hit_center(), tank.hit_center()):
				relocate()
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
