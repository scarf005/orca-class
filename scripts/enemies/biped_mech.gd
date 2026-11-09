class_name BipedMech
extends Enemy
## Shared feet, breakable legs and hard-cover movement for the city bipeds.

enum Stance { ADVANCE, COVER, HIDE, PEEK, EXPOSED }

const HIDE_TIME := 1.1 ## Seconds behind cover before it peeks.
const EXPOSE_TIME := 8.0 ## Seconds in the open before it ducks away again.
const VOLLEYS_PER_PEEK := 2 ## Attacks it makes from one firing position before it moves.
const WADE_LIMIT := 2.5 ## Deepest water it strides through: a sinkhole across the street, never a drowned lot.
const STRIDE := 0.42 ## Radians a leg swings either side of upright while it walks.
const BOOST_SPEED := 12.0 ## Metres per second past which it stops stepping and skates.
const BRACE: Array[float] = [0.3, -0.25] ## Skating stance: one leg reached ahead, the other pushed back.
const FOOT_REACH := 0.8 ## Metres a foot steps up or down to the ground under it.
const STEP_LIFT := 0.18 ## Share of the hip height a swinging foot rises.
const STEP_DIP := 0.07 ## Share of the hip height the body sinks as a foot takes its weight.
const STEP_ROLL := 0.09 ## Radians the body rolls over the standing leg at mid-stance.
const STEP_LEAN := 0.1 ## Radians the body pitches forward at full walking pace.
const TOE_SWING := 0.4 ## Radians a swinging foot points its toe down after lift-off and up before it lands.
const STEPS: Array[String] = ["mech_step", "mech_step_2", "mech_step_3"]
const BAND_FAR := 125.0 ## Metres ahead of the tank (at stage 1's standoff) past which a street hunter will not fire.
const BAND_INSET := 0.05 ## Metres inside that edge a pacing hunter holds: float positions round its step far finer.

var min_range := 0.0 ## Nearest it will stand to the tank when picking cover.
var legs_hp := 30.0
var toppled := false
var _hard := false
var _body := Node3D.new()
var _legs: Array[Node3D] = [] ## Hip joints; each carries a knee, which carries the ankle and foot.
var _knees: Array[Node3D] = []
var _ankles: Array[Node3D] = []
var _thigh := Vector2.ZERO ## Hip to knee as (y, z) in the hip's frame.
var _shin := Vector2.ZERO ## Knee to ankle as (y, z).
var _heel := Vector2.ZERO ## Ankle above the sole's contact point as (y, z).
var _ground: Array[float] = [NAN, NAN] ## Eased ground height under each foot.
var _cover: Prop
var _cover_goal := Vector3.INF
var _cover_wait := 0.0
var _peek := false
var _avoid: Prop ## The cover it just left.
var _stance := Stance.ADVANCE
var _stance_time := 0.0
var _volleys := 0
var _progress := INF ## Nearest it has got to its cover goal, and for how long it has made no headway.
var _progress_time := 0.0
var _side := 1.0
var _search := 0.0
var _walk := 0.0 ## Gait cycles stepped so far.
var _moved := Vector3.ZERO ## Ground covered since the last stride.
var _boost := 0.0 ## 0 stepping, 1 braced and skating.
var _pace := 0.0 ## Eased walking speed as a share of a brisk walk; sets the forward lean.
var _planted: Array[bool] = [true, true] ## Whether each foot stood on the last stride, to hear it land.
var _thrust := 0.0
var _hip := 3.0
var _firing_goal := Vector3.INF
var _firing_search := 0.0
var _tank_d := INF ## Where the tank was along the road on the last hunter step.


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


## Two legs hanging from the hips at `hip` metres: "knee" bends forward like a person's, "bird" folds back at a hock
## onto a three-toed foot, "heavy" is a thick armored column on a broad foot. `armor` colors the plates.
func build_legs(hip: float, style: String, armor: Color, frame := Palette.DUSK, spread := 0.75) -> void:
	_hip = hip
	_body.position.y = hip
	var heavy := style == "heavy"
	var w := 1.35 if heavy else 1.0
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * spread, 0, 0)
		_body.add_child(leg)
		# Three parts in leg space; each hangs from its own joint so the knee and ankle bend.
		var b := LowPoly.new()
		var shin := LowPoly.new()
		var foot := LowPoly.new()
		var knee: Vector3
		var ankle: Vector3
		b.blob(Transform3D(), 0.3 * w, Palette.INK)
		b.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(side * 0.34 * w, 0, 0)), 0.24 * w, 0.12, 8, Palette.ASH) # Hip actuator cap.
		if style == "bird":
			# Thigh forward to the knee, shin back to the hock, then a long foot bone down to splayed toes.
			knee = Vector3(0, -hip * 0.36, -0.55)
			ankle = Vector3(0, -hip * 0.78, 0.45)
			var ball := Vector3(0, -hip + 0.22, -0.15)
			limb(b, Vector3.ZERO, knee, Vector2(0.75, 0.85), Vector2(0.48, 0.55), armor)
			b.frustum(Transform3D(Basis(Vector3.RIGHT, 0.9), knee * 0.45 + Vector3(0, 0, -0.35)), Vector2(0.62, 0.5), Vector2(0.5, 0.1), 0.18, armor.lightened(0.12)) # Thigh plate.
			shin.blob(Transform3D(Basis(), knee), 0.3, Palette.INK)
			shin.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), knee + Vector3(side * 0.3, 0, 0)), 0.2, 0.1, 8, Palette.ASH) # Knee actuator cap.
			limb(shin, knee, ankle, Vector2(0.4, 0.45), Vector2(0.3, 0.36), frame)
			shin.prism(Transform3D(Basis(), knee + Vector3(side * 0.28, 0.0, 0.1)), 0.07, 1.0, 6, Palette.ASH) # Shin ram.
			limb(shin, knee.lerp(ankle, 0.2) + Vector3(0, 0, 0.18), knee.lerp(ankle, 0.85) + Vector3(0, 0, 0.16), Vector2(0.12, 0.1), Vector2(0.1, 0.08), Palette.INK) # Hose down the back.
			foot.blob(Transform3D(Basis(), ankle), 0.22, Palette.INK)
			limb(foot, ankle, ball, Vector2(0.28, 0.32), Vector2(0.24, 0.26), armor.darkened(0.15))
			for toe in [-0.45, 0.0, 0.45]:
				foot.frustum(Transform3D(Basis(Vector3.UP, toe), ball + Vector3(0, -0.22, 0)), Vector2(0.24, 1.0), Vector2(0.14, 0.7), 0.22, Palette.INK, Color(0, 0, 0, 0), Vector2(0, -0.1))
			foot.frustum(Transform3D(Basis(), ball + Vector3(0, -0.22, 0.45)), Vector2(0.18, 0.5), Vector2(0.1, 0.3), 0.18, Palette.INK)
		else:
			knee = Vector3(0, -hip * 0.5, -0.22 if heavy else -0.18)
			ankle = Vector3(0, -hip + 0.32, 0.02)
			limb(b, Vector3.ZERO, knee, Vector2(0.5, 0.58) * w, Vector2(0.4, 0.46) * w, frame)
			b.frustum(Transform3D(Basis(), knee * 0.5 + Vector3(0, -0.25, -0.26 * w)), Vector2(0.44, 0.1) * w, Vector2(0.36, 0.08) * w, hip * 0.26, armor.darkened(0.08)) # Thigh plate.
			shin.blob(Transform3D(Basis(), knee), 0.27 * w, Palette.INK)
			shin.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), knee + Vector3(side * 0.26 * w, 0, 0)), 0.2 * w, 0.1, 8, Palette.ASH) # Knee actuator cap.
			limb(shin, knee, ankle, Vector2(0.44, 0.5) * w, Vector2(0.52, 0.56) * w, armor)
			# Knee cap and a shin plate that flares out toward the ankle.
			shin.frustum(Transform3D(Basis(Vector3.RIGHT, -0.25), knee + Vector3(0, -0.2, -0.22 * w)), Vector2(0.46, 0.2) * w, Vector2(0.34, 0.08) * w, 0.55, armor.lightened(0.1))
			shin.frustum(Transform3D(Basis(Vector3.RIGHT, 0.08), ankle + Vector3(0, 0.15, -0.27 * w)), Vector2(0.56, 0.12) * w, Vector2(0.46, 0.1) * w, hip * 0.36, armor.lightened(0.05))
			for bolt in [0.3, 0.55, 0.8]:
				shin.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), knee.lerp(ankle, bolt) + Vector3(0, 0, -0.3 * w)), 0.04, 0.06, 6, Palette.ASH) # Plate bolts.
			if heavy:
				shin.prism(Transform3D(Basis(), knee + Vector3(side * 0.42, -0.1, 0.25)), 0.09, hip * 0.4, 6, Palette.ASH) # Ankle ram.
			foot.blob(Transform3D(Basis(), ankle), 0.22 * w, Palette.INK)
			# Foot: a sloped boot with a toe cap and a heel block.
			foot.frustum(Transform3D(Basis(), Vector3(0, -hip, -0.15)), Vector2(0.62, 1.25) * w, Vector2(0.5, 0.8) * w, 0.34, frame, Color(0, 0, 0, 0), Vector2(0, 0.12))
			foot.frustum(Transform3D(Basis(), Vector3(0, -hip, -0.62 * w)), Vector2(0.64, 0.42) * w, Vector2(0.52, 0.1) * w, 0.24, armor)
			foot.frustum(Transform3D(Basis(), Vector3(0, -hip, 0.42 * w)), Vector2(0.5, 0.3) * w, Vector2(0.44, 0.2) * w, 0.3, Palette.INK) # Heel spur.
		add_mesh(leg, b.mesh())
		var knee_joint := Node3D.new()
		knee_joint.position = knee
		leg.add_child(knee_joint)
		_add_part(knee_joint, shin.mesh(), knee)
		var ankle_joint := Node3D.new()
		ankle_joint.position = ankle - knee
		knee_joint.add_child(ankle_joint)
		_add_part(ankle_joint, foot.mesh(), ankle)
		_legs.append(leg)
		_knees.append(knee_joint)
		_ankles.append(ankle_joint)
		_thigh = Vector2(knee.y, knee.z)
		_shin = Vector2(ankle.y - knee.y, ankle.z - knee.z)
		_heel = Vector2(ankle.y + hip, ankle.z)


## A part built in leg space hung from the joint at `pivot`.
func _add_part(joint: Node3D, mesh: Mesh, pivot: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = -pivot
	joint.add_child(instance)


## A tapered limb from `a` to `b`, `top` size at `a` and `bottom` size at `b`.
static func limb(mesh: LowPoly, a: Vector3, b: Vector3, top: Vector2, bottom: Vector2, color: Color) -> void:
	var up := (a - b).normalized()
	var across := Vector3.RIGHT
	var forward := across.cross(up).normalized()
	mesh.frustum(Transform3D(Basis(across, up, forward), b), bottom, top, a.distance_to(b), color)


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


## A firing edge must stay on the street ahead, or on the expressway's inner parapet, below the roof line.
func firing_spot_valid(at: Vector3, tank: Tank) -> bool:
	if not Course.stage.city:
		return true
	var c := Course.to_course(at)
	var t := Course.to_course(tank.global_position)
	var surface := maxf(tank.global_position.y, Stage2.WATER_LEVEL)
	var deck := get_meta("slot", Vector3.ZERO) as Vector3
	var limit := 40.0 if deck.y > 0.0 else Course.stage.lateral_limit(c.x) - radius
	var supported := deck.y <= 0.0 or (at.y >= Stage2.WATER_LEVEL + 5.5 and absf(Course.surface_height(c.x, c.y, surface + 6.01) - at.y) < 0.1)
	return supported and c.x - t.x >= 65.0 * Course.stage.standoff and c.x - t.x <= BAND_FAR * Course.stage.standoff and absf(c.y) <= limit and at.y <= surface + 6.01


## Within `reach` metres of the tank, or anywhere in the city firing band: a hunter parked at the band's far edge
## must still open fire.
func in_reach(tank: Tank, reach: float) -> bool:
	return global_position.distance_to(tank.global_position) < (maxf(reach, 140.0 * Course.stage.standoff) if Course.stage.city else reach)


func clear_firing_spot(tank: Tank) -> bool:
	return firing_spot_valid(global_position, tank) and not line_blocked(hit_center(), tank.hit_center()) and not World.current.director.scenery.line_blocked(World.current.camera.global_position, hit_center())


func city_firing_spot(tank: Tank) -> Vector3:
	if _firing_search > 0.0:
		return _firing_goal
	_firing_search = 0.25
	_firing_goal = Vector3.INF
	var fallback := Vector3.INF
	var t := Course.to_course(tank.global_position)
	var slot := get_meta("slot", Vector3.ZERO) as Vector3
	var lanes := PackedFloat32Array([signf(slot.x) * 38.5] if slot.y > 0.0 else [clampf(Course.to_course(global_position).y, -12.0, 12.0), -8.0, 8.0, 0.0])
	for ahead: float in [70.0, 85.0, 105.0, 115.0]:
		ahead *= Course.stage.standoff
		for u in lanes:
			var at := Course.to_world(t.x + ahead, u)
			at.y = CityCover.surface_at(at, maxf(tank.global_position.y, Stage2.WATER_LEVEL) + 6.01)
			if slot.y > 0.0 and at.y < Stage2.WATER_LEVEL + 5.5:
				continue
			if not firing_spot_valid(at, tank):
				continue
			if fallback == Vector3.INF:
				fallback = at
			if line_blocked(at + Vector3.UP * center_height, tank.hit_center()) or World.current.director.scenery.line_blocked(World.current.camera.global_position, at + Vector3.UP * center_height):
				continue
			_firing_goal = at
			return at
	_firing_goal = fallback # No open line this moment: still keep up in the band, or the tank drives out of range.
	return fallback


func walk_city_firing(goal: Vector3, speed: float, delta: float) -> void:
	var slot := get_meta("slot", Vector3.ZERO) as Vector3
	var left := delta
	while left > 0.00001:
		var step := minf(left, 1.0 / 30.0)
		if slot.y > 0.0:
			var next := global_position + (goal - global_position).limit_length(speed * step)
			var c := Course.to_course(next)
			if Course.surface_height(c.x, c.y, Stage2.WATER_LEVEL + 6.01) < Stage2.WATER_LEVEL + 5.5:
				# A deck gap is not a bridge. Drop into the street rather than walking under the next span.
				slot.y = 0.0
				set_meta("slot", slot)
				_firing_search = 0.0
				relocate()
				goal = city_firing_spot(player())
				if goal == Vector3.INF:
					return
				continue
		walk_to(goal, speed, step)
		left -= step


func seek_cover(tank: Tank) -> bool:
	if Course.stage.city and (_volleys > 0 or legs_hp < 30.0 or tank.charge_lock == self or tank.charge_candidate == self):
		return false
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
		if Course.stage.city and distance > 10.0:
			continue
		if not firing_spot_valid(goal, tank):
			continue
		if Course.stage.city and absf(Course.to_course(prop.global_position).y) > Course.stage.lateral_limit(Course.to_course(prop.global_position).x):
			continue
		if distance < best and line_blocked(tank.hit_center(), goal + Vector3.UP * center_height):
			best = distance
			_cover = prop
			_cover_goal = goal
	_peek = false
	_cover_wait = HIDE_TIME
	_stance = Stance.COVER if _cover != null else Stance.ADVANCE
	_stance_time = 0.0
	_progress = INF
	_progress_time = 0.0
	return _cover != null


## The nearest spot around the cover, outside its footprint, that sees the tank; one where both shoulders see it
## wins over one where only the body does. INF when none sees it.
func peek_spot(tank: Tank) -> Vector3:
	var best := INF
	var spot := Vector3.INF
	var toward := tank.global_position - _cover.global_position
	toward.y = 0.0
	var sideways := Vector3(-toward.z, 0.0, toward.x).normalized()
	for step in 12:
		var direction := toward.rotated(Vector3.UP, TAU * step / 12.0)
		var candidate := CityCover.outside_point(_cover, direction, radius + 2.0)
		candidate.y = CityCover.surface_at(candidate, global_position.y + 1.0)
		if not firing_spot_valid(candidate, tank):
			continue
		if Course.stage.city and line_blocked(World.current.camera.global_position, candidate + Vector3.UP * center_height):
			continue
		if hard_blocker(candidate + Vector3.UP * (radius + 0.1), candidate + Vector3.UP * (radius + 0.2), radius) != null:
			continue
		if line_blocked(tank.hit_center(), candidate + Vector3.UP * center_height):
			continue
		var wide := true
		for shoulder in [-1.0, 1.0]:
			if line_blocked(tank.hit_center(), candidate + Vector3.UP * center_height + sideways * (shoulder * radius * 1.7)):
				wide = false
				break
		var score := global_position.distance_to(candidate) + (0.0 if wide else 1000.0)
		if score < best:
			best = score
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


## Walks on with the tank, even while winding up, so the street ahead it stands on does not slide out of its firing band.
## It steps the tank's advance along the road at its own lateral offset: a straight step of the same length would
## drift it along the road on bends.
func keep_pace(advance: float, delta: float) -> void:
	if advance > 0.0 and delta > 0.0:
		var c := Course.to_course(global_position)
		var goal := Course.to_world(c.x + advance, c.y, global_position.y)
		walk_to(goal, global_position.distance_to(goal) / delta, delta)


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
			# Round a rectangular building by its corners: head for the corner that gets nearest the goal
			# along a line the hunter can walk.
			var half := blocker.box_size * 0.5 + Vector3.ONE * (radius + 1.5)
			var best := INF
			var waypoint := Vector3.INF
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point := blocker.to_global(Vector3(corner.x * half.x, 0.0, corner.y * half.z))
				point.y = global_position.y
				var cost := global_position.distance_to(point) + point.distance_to(goal)
				if cost < best and not line_blocked(global_position + clearance, point + clearance, radius * 0.5):
					best = cost
					waypoint = point
			if waypoint != Vector3.INF:
				var heading := (waypoint - global_position)
				heading.y = 0.0
				tangent = heading.normalized()
				offset = tangent * 1.0 # direction only
			else:
				var local := blocker.to_local(global_position)
				tangent = blocker.global_basis.z if absf(local.x) / half.x > absf(local.z) / half.z else blocker.global_basis.x
		if tangent.dot(offset) < 0.0:
			tangent = -tangent
		next = global_position + tangent * step.length()
		if line_blocked(global_position + clearance, next + clearance, radius):
			next = global_position
	var floor := CityCover.surface_at(next, next.y + 1.0)
	var here := CityCover.surface_at(global_position, global_position.y + 1.0)
	var course := Course.to_course(next)
	var past_kerb := Course.stage is Stage2 and floor < Stage2.WATER_LEVEL + 3.0 and absf(course.y) > Course.stage.lateral_limit(course.x) and absf(course.y) <= Course.stage.lateral_limit(course.x) + Stage2.HULL_MARGIN and absf(course.y) > absf(Course.to_course(global_position).y)
	if past_kerb or (Water.surface_at(next) - floor > WADE_LIMIT and Water.surface_at(global_position) - here <= WADE_LIMIT):
		next = global_position # Off the avenue (the shelf past the kerb, deep water): the hunter stops at its edge.
		floor = here
	_moved += Vector3(next.x - global_position.x, 0.0, next.z - global_position.z)
	global_position = next
	global_position.y = floor


## Steps with the walk since the last call. The standing foot sweeps back exactly as far as the body moves
## (forward or backing off), so it stays planted while the other swings through lifted; faster than a stride
## can carry it, the mech braces one leg ahead of the other and skates on its heel thrusters. Each foot reaches
## the ground under it, the knee and ankle bending to carry it there.
func stride(delta: float) -> void:
	var facing := -model.global_basis.z
	var along := _moved.length() * signf(_moved.dot(facing) + 0.0001)
	_boost = move_toward(_boost, 1.0 if _moved.length() > BOOST_SPEED * delta else 0.0, delta * 5.0)
	var heading := _moved
	_moved = Vector3.ZERO
	var reach := sin(STRIDE)
	_walk += along / (4.0 * _hip * reach) # One cycle: each foot stands for half of it, sweeping 2 * hip * reach.
	var stance_angle := 0.0
	var walking := 1.0 - _boost
	_pace = move_toward(_pace, clampf(along / maxf(delta, 0.0001) / 4.0, -1.0, 1.0), delta * 3.0)
	var dip := 0.0
	var roll := 0.0
	var feet: Array[Vector2] = []
	var drops: Array[float] = []
	var toes: Array[float] = []
	for i in _legs.size():
		var s := fposmod(_walk + i * 0.5, 1.0) * 2.0
		var standing := s < 1.0
		var swing := smoothstep(1.0, 2.0, s)
		var angle := asin(reach * (1.0 - 2.0 * s)) if standing else asin(reach * (2.0 * swing - 1.0))
		if standing:
			stance_angle = angle
			# The body settles onto the foot just after it lands and rides over it toward mid-stance.
			dip = sin(PI * clampf(s / 0.35, 0.0, 1.0))
			roll = -signf(_legs[i].position.x) * sin(PI * s)
		var z := -_hip * sin(lerpf(angle, BRACE[i], _boost))
		var ground := ground_under(model.global_transform * Vector3(_legs[i].position.x, 0.0, z))
		_ground[i] = ground if is_nan(_ground[i]) else lerpf(_ground[i], ground, 1.0 - exp(-20.0 * delta))
		drops.append(clampf(_ground[i] - global_position.y, -FOOT_REACH, FOOT_REACH))
		feet.append(Vector2(0.0 if standing else sin(PI * swing) * _hip * STEP_LIFT * walking, z))
		toes.append(0.0 if standing else -sin(TAU * swing) * TOE_SWING * walking)
		if standing and not _planted[i] and walking > 0.5 and along != 0.0:
			_footfall(i)
		_planted[i] = standing
	# Hips a little below full reach, so the knees always bend; the body sinks to the lower foot.
	_body.position.y = lerpf(_hip * cos(stance_angle) * 0.95, _hip * 0.9, _boost) + minf(drops[0], drops[1]) - dip * _hip * STEP_DIP * walking
	_body.rotation = Vector3(-_pace * STEP_LEAN * walking, 0.0, roll * STEP_ROLL * walking)
	var pitch := Basis(Vector3.RIGHT, _body.rotation.x)
	for i in _legs.size():
		# Each hip cancels the body's roll so its leg swings upright; the ankle targets are taken in the pitched hip.
		var hip := _body.position + _body.basis * _legs[i].position
		var ankle := Vector3(hip.x, drops[i] + feet[i].x + _heel.x, feet[i].y + _heel.y)
		var local := pitch.inverse() * (ankle - hip)
		var bend := _reach(Vector2(local.y, local.z))
		_legs[i].basis = Basis(Vector3.BACK, -_body.rotation.z) * Basis(Vector3.RIGHT, bend.x)
		_knees[i].rotation.x = bend.y
		_ankles[i].rotation.x = -bend.x - bend.y - _body.rotation.x + toes[i] # The foot stays level, or tips through its swing.
	if _boost < 0.5 or _wet or heading == Vector3.ZERO:
		return
	_thrust -= delta
	if _thrust > 0.0:
		return
	_thrust = 0.05
	var back := -heading.normalized()
	for ankle in _ankles:
		var heel := ankle.to_global(Vector3(0, 0.3 - _heel.x, 0.5 - _heel.y))
		World.current.fx.spawn(Fx.Kind.FLAME, heel, back * 6.0 + Vector3.UP * 1.5, 0.16, 0.35, [Palette.BUTTER, Palette.AMBER][randi() % 2], {"drag": 2.0})
		World.current.fx.dust(heel - Vector3.UP * 0.3, 1, 0.6)


## Hip and knee angles that put the ankle at `target` (y, z) from the hip, the knee bending the way it rests.
func _reach(target: Vector2) -> Vector2:
	var thigh_length := _thigh.length()
	var shin_length := _shin.length()
	var span := clampf(target.length(), absf(thigh_length - shin_length) + 0.001, thigh_length + shin_length - 0.001)
	var open := acos(clampf((thigh_length * thigh_length + span * span - shin_length * shin_length) / (2.0 * thigh_length * span), -1.0, 1.0))
	var thigh := target.normalized().rotated(-signf(_thigh.cross(_shin)) * open) * thigh_length
	var hip := _thigh.angle_to(thigh)
	return Vector2(hip, _shin.rotated(hip).angle_to(target.normalized() * span - thigh))


## A foot landing thumps and kicks up dust; the bigger the mech, the deeper the thump.
func _footfall(i: int) -> void:
	var at := sole(i)
	Sfx.play(STEPS[randi() % STEPS.size()], at, -4.0, clampf(1.3 - _hip * 0.1, 0.8, 1.2) * randf_range(0.95, 1.05))
	World.current.fx.dust(at, 2, _hip * 0.35)


## The point under foot `i` that stands on the ground.
func sole(i: int) -> Vector3:
	return _ankles[i].to_global(Vector3(0, -_heel.x, -_heel.y))


## City hunters stand on rooftops and decks as well as the street.
func ground_under(at: Vector3) -> float:
	return CityCover.surface_at(at, global_position.y + 1.0)


func move_hunter(tank: Tank, delta: float, planted: bool, keep := 52.0) -> void:
	_firing_search = maxf(0.0, _firing_search - delta)
	var tank_d := Course.to_course(tank.global_position).x
	var advance := tank_d - _tank_d if is_finite(_tank_d) else 0.0
	_tank_d = tank_d
	var toward := tank.global_position - global_position
	model.rotation.y = lerp_angle(model.rotation.y, atan2(-toward.x, -toward.z), minf(delta * 4.0, 1.0))
	if toppled:
		_body.position.y = lerpf(_body.position.y, 1.0, minf(delta * 4.0, 1.0))
		model.rotation.z = lerpf(model.rotation.z, 0.9, minf(delta * 4.0, 1.0))
		return
	stride(delta)
	if Course.stage.city and (not firing_spot_valid(global_position, tank) or (_stance == Stance.ADVANCE and not clear_firing_spot(tank))) and not is_staggered():
		relocate()
		var goal := city_firing_spot(tank)
		if goal != Vector3.INF:
			walk_city_firing(goal, World.current.rail.speed + 18.0, delta)
		return
	var slot := get_meta("slot", Vector3.ZERO) as Vector3
	if Course.stage.city and slot.y <= 0.0 and not is_staggered():
		# No further than the far edge as `behave` judges it after this step: a walk-in stops just inside that edge, and
		# riding along from there would put it a step past, dropping every wind-up.
		keep_pace(minf(advance, tank_d + BAND_FAR * Course.stage.standoff - BAND_INSET - Course.to_course(global_position).x), delta)
	if planted or is_staggered():
		return
	if Course.stage.city and slot.y > 0.0:
		var goal := city_firing_spot(tank)
		if goal != Vector3.INF:
			walk_city_firing(goal, World.current.rail.speed + 9.0, delta)
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
			walk_to(_cover_goal, World.current.rail.speed + 18.0 if Course.stage.city else 8.0, delta)
			var left := global_position.distance_to(_cover_goal)
			if left < 1.0 or _stance_time > 12.0:
				_stance = Stance.HIDE
				_stance_time = 0.0
			elif left < _progress - 1.0:
				_progress = left
				_progress_time = 0.0
			else:
				_progress_time += delta
				if _progress_time > 2.5:
					relocate() # Boxed in on the way: pick another building.
			return
		Stance.HIDE:
			if _stance_time >= (0.45 if Course.stage.city else HIDE_TIME):
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
			walk_to(_cover_goal, World.current.rail.speed + 20.0 if Course.stage.city else 8.5, delta)
			if clear_firing_spot(tank):
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
	if Course.stage.city:
		return # keep_pace holds the band; walking up to `keep` would drive it out of its own firing range.
	var here := Course.to_course(global_position)
	var target_d := World.current.rail.d + tank.course_offset + keep
	if World.current.rail.mode == Rail.Mode.ARENA:
		target_d = Course.to_course(tank.global_position).x + keep
	var u := clampf(here.y + _side * 6.0, -12.0, 12.0) if Course.stage.city else here.y + _side * 6.0
	walk_to(Course.ground_at(target_d, u), 9.0, delta)


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	if hidden or arriving:
		return -1.0
	var best := super(from, to, extra_radius)
	for i in _legs.size():
		for joint in [_legs[i].global_position.lerp(_knees[i].global_position, 0.5), _knees[i].global_position.lerp(_ankles[i].global_position, 0.5), _ankles[i].global_position]: # Thigh, shin and ankle.
			var t := Entity.segment_sphere(from, to, joint, 0.7 + extra_radius)
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
