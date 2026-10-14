class_name Wing
extends Enemy
## Stage 3 boss: a flying wing that fights along the dune run while the rail floors it at 140 km/h. It drifts up
## a sand ramp on its skids to build speed, leaves the lip and glides to the next ramp on the other side of
## the road. Its five belly turrets stay shut except for one: each flight the next living turret opens and
## fires back at the chasing tank until it is shot out (or the wing lands and shuts it). The hull itself only
## sparks; the turrets are the boss's health. Past the last ramp the wing keeps station ahead and the turrets
## take turns until none are left, then it falls out of the sky.

enum State { DRIFT, FLIGHT, ORBIT, DYING }

const TURRETS := ["flak", "rocket", "beam", "bomb", "hangar"]
const TURRET_AT := {
	"flak": Vector3(0.0, -0.9, 3.4),
	"rocket": Vector3(-6.5, -0.7, 1.2),
	"beam": Vector3(6.5, -0.7, 1.2),
	"bomb": Vector3(0.0, -1.0, -2.6),
	"hangar": Vector3(12.0, -0.4, 3.6),
}
const LABELS := {"flak": "WING_FLAK", "rocket": "WING_ROCKET", "beam": "WING_BEAM", "bomb": "WING_BOMB", "hangar": "WING_HANGAR"}
const TURRET_HP := 160.0
const ROUND_DAMAGE := 40.0 ## Like the other bosses, main-gun damage counts in rounds.
const TURRET_RADIUS := 3.2
const HULL_RADIUS := 13.0
const HULL_SPHERES: Array[Vector3] = [Vector3(0, 0, 6.0), Vector3(-11, 2, 5.0), Vector3(11, 2, 5.0)] ## (x, z, radius) in the model.
const DRIFT_SPEED := Vector2(34.0, 80.0) ## Metres per second at the foot and at the lip of a ramp.
const FLIGHT_TIME := 6.5
const LOFT := 22.0 ## Extra height the glide arcs to between two ramps.
const HOVER := 1.5 ## The skids ride this high over the sand.
const OPEN_RATE := 2.2
const WIND := 0.9
const ORBIT_CYCLE := 9.0
const STATION := 120.0 ## Metres ahead of the rail the wing keeps once the ramps run out.

var parts: Dictionary = {}
var _state := State.DRIFT
var _ramp := 0
var _s := 0.0 ## Metres up the ramp.
var _flight := 0.0
var _from := Vector3.ZERO
var _from_tangent := Vector3.ZERO
var _to := Vector3.ZERO
var _to_tangent := Vector3.ZERO
var _forward := Vector3.FORWARD
var _active := -1 ## Index of the open turret.
var _next := 0
var _open: Dictionary[String, float] = {}
var _armed: Dictionary[String, bool] = {} ## Turrets that have fired their first volley.
var _pods: Dictionary[String, Node3D] = {}
var _hatches: Dictionary[String, Array] = {}
var _muzzles: Dictionary[String, Node3D] = {}
var _cool := 1.0
var _wind := 0.0
var _shots := 0
var _shot_timer := 0.0
var _aim := Vector3.ZERO
var _cycle := 0.0
var _dust := 0.0
var _dying := 0.0
var _flames := 0.0


func _init() -> void:
	super()
	boss = true
	heavy = true
	flying = true
	trails = true
	armor = 30.0
	for name: String in TURRETS:
		parts[name] = TURRET_HP
		_open[name] = 0.0
	max_hp = TURRET_HP * TURRETS.size()
	hp = max_hp
	radius = HULL_RADIUS
	center_height = 0.0
	score = 25000
	despawn_behind = 0.0
	set_meta("title", "BOSS_WING")
	set_meta("phase_marks", [0.8, 0.6, 0.4, 0.2])
	set_meta("frame", 0.22) # The rail camera leans this far toward it.


func _ready() -> void:
	super()
	if Course.stage is Stage3:
		_place_on_ramp()


func build() -> void:
	var b := LowPoly.new()
	# Planform from the nose round the left tip, along the saw-toothed trailing edge and back up the right side.
	var edge: Array[Vector2] = [Vector2(0, -9), Vector2(-6, -5), Vector2(-18, 3), Vector2(-18, 5.5), Vector2(-12, 4), Vector2(-8, 6.5), Vector2(-4, 4.5), Vector2(0, 7.5), Vector2(4, 4.5), Vector2(8, 6.5), Vector2(12, 4), Vector2(18, 5.5), Vector2(18, 3), Vector2(6, -5)]
	var centre := Vector2(0, -0.5)
	for i in edge.size():
		var a := edge[i]
		var c := edge[(i + 1) % edge.size()]
		var ma := centre + (a - centre) * 0.5
		var mc := centre + (c - centre) * 0.5
		var tip := absf(a.x) > 16.0 or absf(c.x) > 16.0
		var lead := i in [0, 1, 2, 12, 13]
		for side in [1.0, -1.0]:
			var y: float = side
			var ea := Vector3(a.x, 0.22 * y, a.y)
			var ec := Vector3(c.x, 0.22 * y, c.y)
			var ra := Vector3(ma.x, 1.05 * y, ma.y)
			var rc := Vector3(mc.x, 1.05 * y, mc.y)
			var apex := Vector3(centre.x, 1.5 * y, centre.y)
			var skin: Color = (Palette.WHITE if i % 2 == 0 else Palette.HULL_LIGHT) if side > 0.0 else (Palette.ASH if i % 2 == 0 else Palette.STONE)
			var rim: Color = Palette.CORAL if (tip or lead) else skin
			b.quad(ea, ec, rc, ra, rim, Vector3.UP * y)
			b.tri(ra, rc, apex, skin, Vector3.UP * y)
		b.quad(Vector3(a.x, 0.22, a.y), Vector3(c.x, 0.22, c.y), Vector3(c.x, -0.22, c.y), Vector3(a.x, -0.22, a.y), Palette.INK, Vector3(((a + c) * 0.5 - centre).x, 0.0, ((a + c) * 0.5 - centre).y))
	# Canopy, intakes, exhaust slits and landing skids.
	b.glow = true
	b.box(Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 1.55, -4.8)), Vector3(1.8, 0.45, 2.6), Palette.CYAN)
	for side in [-1.0, 1.0]:
		b.glow = true
		b.box(Transform3D(Basis(), Vector3(side * 4.2, 0.0, 6.0)), Vector3(2.4, 0.18, 0.2), Palette.AMBER)
		b.glow = false
		b.box(Transform3D(Basis(), Vector3(side * 3.2, 1.2, 2.4)), Vector3(2.4, 1.0, 3.2), Palette.INK)
		b.box(Transform3D(Basis(Vector3.BACK, side * 0.1), Vector3(side * 3.2, 1.75, 2.0)), Vector3(2.0, 0.12, 3.6), Palette.SLATE)
		b.box(Transform3D(Basis(), Vector3(side * 4.0, -1.7, 0.4)), Vector3(0.5, 0.35, 10.0), Palette.STONE)
		for z in [-3.0, 3.6]:
			b.box(Transform3D(Basis(), Vector3(side * 4.0, -1.1, z)), Vector3(0.3, 1.2, 0.3), Palette.DUSK)
	_add_mesh(model, b.mesh())
	for name: String in TURRETS:
		_make_turret(name)


func _add_mesh(parent: Node3D, mesh: Mesh) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	parent.add_child(node)


func _make_turret(name: String) -> void:
	var root := Node3D.new()
	root.position = TURRET_AT[name]
	model.add_child(root)
	var pod := Node3D.new()
	root.add_child(pod)
	_pods[name] = pod
	var g := LowPoly.new()
	g.blob(Transform3D(), 1.15, Palette.DUSK, 0, 0.1)
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	pod.add_child(muzzle)
	match name:
		"flak":
			for x in [-0.45, 0.45]:
				g.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(x, 0, -0.9)), 0.14, 2.6, 6, Palette.INK)
			g.box(Transform3D(Basis(), Vector3(0, 0.3, -0.5)), Vector3(1.6, 0.5, 1.2), Palette.SLATE)
			muzzle.position = Vector3(0, 0, -3.5)
		"rocket":
			g.box(Transform3D(Basis(), Vector3(0, 0, -1.2)), Vector3(2.2, 1.5, 2.2), Palette.HULL_LIGHT)
			for x in [-0.6, 0.0, 0.6]:
				for y in [-0.35, 0.35]:
					g.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(x, y, -2.3)), 0.2, 0.3, 6, Palette.INK)
			muzzle.position = Vector3(0, 0, -2.5)
		"beam":
			g.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -0.6)), 0.8, 1.6, 10, Palette.SLATE, 0.5)
			g.glow = true
			g.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -2.2)), 0.42, 0.12, 10, Palette.HOT)
			muzzle.position = Vector3(0, 0, -2.4)
		"bomb":
			g.box(Transform3D(Basis(), Vector3(0, 0.4, 0)), Vector3(3.4, 0.9, 2.6), Palette.HULL_LIGHT)
			g.glow = true
			g.box(Transform3D(Basis(), Vector3(0, -0.1, 0)), Vector3(2.6, 0.12, 1.8), Palette.AMBER)
			muzzle.position = Vector3(0, -0.6, 0)
		"hangar":
			g.box(Transform3D(Basis(), Vector3(0, 0.2, -0.6)), Vector3(2.8, 1.3, 2.4), Palette.HULL_LIGHT)
			g.glow = true
			for x in [-0.8, 0.0, 0.8]:
				g.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(x, 0.2, -1.9)), 0.3, 0.1, 8, Palette.CYAN)
			muzzle.position = Vector3(0, 0, -2.0)
	_add_mesh(pod, g.mesh())
	_muzzles[name] = muzzle
	var plates: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		var plate := Node3D.new()
		plate.position = Vector3(side * 0.9, 0.55, 0)
		root.add_child(plate)
		_add_mesh(plate, LowPoly.new().box(Transform3D(), Vector3(1.8, 0.14, 3.0), Palette.ASH, Palette.STONE).mesh())
		plates.append(plate)
	_hatches[name] = plates


func _turret_world(name: String) -> Vector3:
	return _pods[name].global_position


## Turrets whose hatches stand open enough to be hit. Like a hunter walking in, a turret cannot be hit before
## its first volley, so every turret gets to shoot back at least once.
func _exposed() -> Array[String]:
	var result: Array[String] = []
	for name: String in TURRETS:
		if parts[name] > 0.0 and _open[name] >= 0.5 and _armed.has(name):
			result.append(name)
	return result


func aim_parts() -> Dictionary:
	var result := {}
	if _state == State.DYING:
		return result
	for name in _exposed():
		result[name] = [_turret_world(name), TURRET_RADIUS, tr(LABELS[name])]
	return result


func module_states() -> Array:
	return TURRETS.map(func(name: String) -> Array: return [tr(LABELS[name]), maxf(parts[name], 0.0) / TURRET_HP])


## An open turret hangs below the belly, so a round that reaches it is the turret's even where it also
## crosses the hull's outline; otherwise the flat hull is three spheres across the span (body and both wings).
func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	if _state == State.DYING:
		return -1.0
	var best := -1.0
	for spec: Array in aim_parts().values():
		var distance := Entity.segment_sphere(from, to, spec[0], spec[1] + extra_radius)
		if distance >= 0.0 and (best < 0.0 or distance < best):
			best = distance
	if best >= 0.0:
		return best
	for spot in HULL_SPHERES:
		var distance := Entity.segment_sphere(from, to, model.global_transform * Vector3(spot.x, 0.0, spot.y), spot.z + extra_radius)
		if distance >= 0.0 and (best < 0.0 or distance < best):
			best = distance
	return best


func take_hit(hit: Hit) -> void:
	if dead or invulnerable or _state == State.DYING or hit.damage <= 0.0:
		return
	var amount := hit.damage * damage_multiplier(hit)
	if amount <= 0.0:
		return
	if (hit.kind == Hit.Kind.SHELL and (hit.caliber >= 100 or hit.weapon == "cannon")) or (hit.kind == Hit.Kind.BLAST and hit.weapon == "cannon"):
		amount *= ROUND_DAMAGE / Armament.SHELL_DAMAGE
	var struck := ""
	for name in _exposed():
		if hit.position.distance_to(_turret_world(name)) <= TURRET_RADIUS + 1.5:
			struck = name
			break
	if struck.is_empty():
		World.current.fx.sparks(hit.position, -hit.direction, 6)
		Sfx.play("hit_metal", hit.position, -4.0)
		return
	parts[struck] = maxf(0.0, parts[struck] - amount)
	_sum()
	impact_feedback(hit, amount, hp <= 0.0)
	if hit.power >= 1.0:
		World.current.hitstop(0.05)
	if parts[struck] <= 0.0:
		_break_turret(struck, hit.direction)


func _sum() -> void:
	hp = 0.0
	for name: String in TURRETS:
		hp += parts[name]


func _break_turret(name: String, direction: Vector3) -> void:
	var world := World.current
	var pod := _pods[name]
	world.fx.explosion(pod.global_position, 3.0)
	Sfx.play("blast", pod.global_position)
	Wreck.launch(pod, pod.global_position, 2.0, true, direction * 8.0 + Vector3.DOWN * 4.0)
	_open[name] = 0.0
	if _active >= 0 and TURRETS[_active] == name:
		_active = -1
		_end_volley(2.0)
	world.award(800, pod.global_position, false)
	if hp <= 0.0:
		_state = State.DYING
		_dying = 2.6
		killing_hit = Hit.make(Hit.Kind.SHELL, 1.0, pod.global_position, direction)
		world.hitstop(0.2)
		world.shake(0.6, global_position)


func telegraphing() -> bool:
	return _wind > 0.0


## The ramp's track point at `s` metres up, swaying across it as the wing slides from side to side.
func _ramp_point(index: int, s: float) -> Vector3:
	var stage := Course.stage as Stage3
	var sway := sin(s * 0.045) * Stage3.HILL_HALF * 0.55
	var p := Course.to_world(stage.hill_d(index) + s, stage.hill_side(index) * Stage3.HILL_U + sway)
	p.y = Course.height(stage.hill_d(index) + s, stage.hill_side(index) * Stage3.HILL_U + sway) + HOVER
	return p


func _place_on_ramp() -> void:
	global_position = _ramp_point(_ramp, 0.0)
	_forward = (_ramp_point(_ramp, 4.0) - global_position).normalized()


func _hermite(u: float) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	return _from * (2.0 * u3 - 3.0 * u2 + 1.0) + _from_tangent * (u3 - 2.0 * u2 + u) + _to * (-2.0 * u3 + 3.0 * u2) + _to_tangent * (u3 - u2) + Vector3.UP * LOFT * sin(PI * u)


func behave(delta: float) -> void:
	var world := World.current
	var tank := player()
	if _state == State.DYING:
		_die_in_the_air(delta)
		return
	if tank == null:
		return
	var before := global_position
	match _state:
		State.DRIFT:
			_drift(delta)
		State.FLIGHT:
			_glide(delta)
		State.ORBIT:
			_orbit(delta, tank)
	var moved := global_position - before
	if moved.length() > 0.001:
		_forward = _forward.lerp(moved.normalized(), minf(delta * 10.0, 1.0)).normalized()
	_pose(delta)
	_update_turrets(delta, tank)
	_dust -= delta
	if _state == State.DRIFT and _dust <= 0.0:
		_dust = 0.05
		for side in [-1.0, 1.0]:
			var skid := model.global_transform * Vector3(side * 4.0, -1.8, 4.0)
			world.fx.dust(skid, 2, 2.4, Palette.STRAW)
			world.fx.sparks(skid, Vector3.UP, 2, Palette.BUTTER, 12.0)


func _drift(delta: float) -> void:
	var stage := Course.stage as Stage3
	var speed := lerpf(DRIFT_SPEED.x, DRIFT_SPEED.y, smoothstep(0.0, 1.0, _s / Stage3.HILL_LENGTH))
	_s += speed * delta
	if _s >= Stage3.HILL_LENGTH:
		_leave_ramp(stage)
		return
	global_position = _ramp_point(_ramp, _s)
	if fmod(age, 0.5) < delta:
		Sfx.play("skid", global_position, -6.0, 0.9)


func _leave_ramp(stage: Stage3) -> void:
	var world := World.current
	_from = _ramp_point(_ramp, Stage3.HILL_LENGTH)
	var ahead := (_ramp_point(_ramp, Stage3.HILL_LENGTH) - _ramp_point(_ramp, Stage3.HILL_LENGTH - 6.0)).normalized()
	var last := _ramp + 1 >= Stage3.HILL_COUNT
	if last:
		_to = Course.to_world(stage.hill_d(_ramp) + Stage3.HILL_LENGTH + 260.0, 0.0)
		_to.y = Course.height_at(_to) + 30.0
		_to_tangent = Course.forward(stage.hill_d(_ramp)) * 200.0
	else:
		_to = _ramp_point(_ramp + 1, 0.0)
		_to_tangent = Course.forward(stage.hill_d(_ramp + 1)) * 160.0
	var chord := _from.distance_to(_to)
	_from_tangent = (Vector3(ahead.x, 0.0, ahead.z).normalized() * 0.9 + Vector3.UP * 0.35).normalized() * chord * 1.1
	_flight = 0.0
	_state = State.ORBIT if last else State.FLIGHT
	world.fx.shockwave(_from, 18.0, Palette.BUTTER)
	world.fx.dust(_from, 14, 6.0, Palette.STRAW)
	world.shake(0.3, _from)
	Sfx.play("jet", _from, 2.0)
	if last:
		_cycle = 0.0
	else:
		_open_next()


func _glide(delta: float) -> void:
	_flight += delta
	var u := clampf(_flight / FLIGHT_TIME, 0.0, 1.0)
	global_position = _hermite(u)
	if u >= 1.0:
		_ramp += 1
		_s = 0.0
		_state = State.DRIFT
		_close_all()
		World.current.fx.dust(global_position, 10, 5.0, Palette.STRAW)


## Past the last ramp: it holds station ahead of the rail, weaving, and the turrets take turns.
func _orbit(delta: float, _tank: Tank) -> void:
	var world := World.current
	_flight += delta
	if _flight < FLIGHT_TIME:
		global_position = _hermite(clampf(_flight / FLIGHT_TIME, 0.0, 1.0))
	else:
		var d := world.rail.d + STATION
		var u := sin(age * 0.6) * 26.0
		var station := Course.to_world(d, u)
		station.y = Course.height(d, u) + 30.0 + sin(age * 1.1) * 3.0
		global_position = global_position.lerp(station, 1.0 - exp(-2.5 * delta))
	_cycle -= delta
	if _cycle <= 0.0 and _active < 0:
		_cycle = ORBIT_CYCLE
		_open_next()
	elif _cycle <= 0.0 and _active >= 0:
		_cycle = ORBIT_CYCLE
		_close_all()
		_cycle = 1.5


func _pose(delta: float) -> void:
	var slip := 0.0
	var roll := 0.0
	if _state == State.DRIFT:
		slip = cos(_s * 0.045) * 0.5
		roll = -slip * 0.7
	elif _state == State.FLIGHT:
		roll = sin(_flight / FLIGHT_TIME * TAU) * 0.35 * (Course.stage as Stage3).hill_side(_ramp)
	var heading := _forward.rotated(Vector3.UP, slip)
	var up := Vector3.UP.rotated(_forward, roll)
	model.global_basis = model.global_basis.orthonormalized().slerp(Basis.looking_at(heading, up), minf(delta * 8.0, 1.0)) if delta > 0.0 else model.global_basis


func _open_next() -> void:
	for i in TURRETS.size():
		var index := (_next + i) % TURRETS.size()
		if parts[TURRETS[index]] > 0.0:
			_active = index
			_next = index + 1
			_cool = 0.4
			_end_volley(0.8)
			return


func _close_all() -> void:
	_active = -1
	_wind = 0.0
	_shots = 0


func _end_volley(pause: float) -> void:
	_wind = 0.0
	_shots = 0
	_shot_timer = 0.0
	_cool = pause


func _update_turrets(delta: float, tank: Tank) -> void:
	for name: String in TURRETS:
		var want := 1.0 if _active >= 0 and TURRETS[_active] == name and parts[name] > 0.0 else 0.0
		_open[name] = move_toward(_open[name], want, OPEN_RATE * delta)
		if parts[name] <= 0.0:
			continue
		var plates: Array = _hatches[name]
		plates[0].position.x = -0.9 - 1.1 * _open[name]
		plates[1].position.x = 0.9 + 1.1 * _open[name]
		_pods[name].position.y = -1.2 * _open[name]
		if want == 0.0 and _open[name] < 0.5:
			_pods[name].basis = Basis.looking_at(Vector3(0, 0, 1))
	if _active < 0 or _open[TURRETS[_active]] < 0.9:
		return
	var name: String = TURRETS[_active]
	aim_barrel(_pods[name], _aim_point(name, tank), 4.0, delta)
	if _cool > 0.0:
		_cool -= delta
		if _cool <= 0.0:
			_begin_volley(name, tank)
		return
	if _wind > 0.0:
		_wind -= delta
		return
	_shot_timer -= delta
	if _shot_timer <= 0.0:
		_armed[name] = true
		_fire(name, tank)


func _aim_point(name: String, tank: Tank) -> Vector3:
	if name == "flak":
		return Gunnery.sensor_lead(tank, _muzzles[name].global_position, MG_SPEED)
	return tank.hit_center()


func _begin_volley(name: String, tank: Tank) -> void:
	var world := World.current
	_wind = WIND * Game.telegraph_scale()
	_shots = 0
	_shot_timer = 0.0
	var muzzle := _muzzles[name].global_position
	_aim = tank.global_position + tank.velocity * 1.4
	_aim.y = Course.height_at(_aim)
	match name:
		"beam":
			world.fx.beam(muzzle, _aim, Palette.HOT, 0.14, _wind)
			world.fx.marker(_aim, 4.0, _wind, Palette.RED)
		"rocket", "bomb":
			world.fx.beam(muzzle, _aim, Palette.HOT, 0.1, _wind)
		_:
			world.fx.beam(muzzle, tank.hit_center(), Palette.HOT, 0.1, _wind)
	Sfx.play("warn", global_position, 0.0, 0.8)


func _fire(name: String, tank: Tank) -> void:
	var world := World.current
	var muzzle := _muzzles[name]
	match name:
		"flak":
			var shot := fire_along("bullet", muzzle, MG_SPEED, 5.0, Palette.HOT, Gunnery.sensor_lead(tank, muzzle.global_position, MG_SPEED) - muzzle.global_position, 3.0, 0.02, Muzzle.AUTO)
			shot.hit.caliber = 30
			Sfx.play("enemy_gun", muzzle.global_position, -2.0)
			_shots += 1
			_shot_timer = 0.07
			if _shots >= 14:
				_end_volley(1.6)
		"rocket":
			var target := _aim + Course.right(Course.to_course(_aim).x) * (_shots - 2.5) * 3.5
			var from := muzzle.global_position
			var velocity := (target - from) / 1.4 + Vector3.UP * 13.7
			var shot := fire_along("rocket", muzzle, velocity.length(), 0.0, Palette.HOT, velocity)
			shot.gravity = 20.0
			shot.hit = Hit.make(Hit.Kind.SHELL, 0.0, from)
			shot.hit.source = self
			shot.blast_radius = 4.0
			shot.blast_damage = 20.0
			shot.interceptable = true
			shot.trail = Projectile.ROCKET_SMOKE
			world.fx.marker(target, 4.0, 1.4, Palette.RED)
			Sfx.play("launch", from)
			_shots += 1
			_shot_timer = 0.16
			if _shots >= 6:
				_end_volley(2.0)
		"beam":
			var from := muzzle.global_position
			var to := _aim
			world.fx.rail_beam(from, to, Palette.HOT)
			world.fx.explosion(to, 3.0)
			Sfx.play("cannon", from, 2.0)
			var closest := Geometry3D.get_closest_point_to_segment(tank.hit_center(), from, to)
			if closest.distance_to(tank.hit_center()) < 4.5:
				var hit := Hit.make(Hit.Kind.SHELL, 40.0, tank.hit_center(), (to - from).normalized())
				hit.caliber = 120
				hit.source = self
				tank.take_hit(hit)
			_end_volley(2.4)
		"bomb":
			_drop_bomb(muzzle.global_position, tank, _shots)
			_shots += 1
			_shot_timer = 0.14
			if _shots >= 5:
				_end_volley(2.2)
		"hangar":
			world.director.send_pursuers(3, randi() % FpvDrone.Pattern.size())
			Sfx.play("dive", muzzle.global_position, 0.0, 0.8)
			_end_volley(4.0)


## Bombs come down in a line across the road a little way ahead of the tank, one lane left open.
func _drop_bomb(from: Vector3, tank: Tank, index: int) -> void:
	var world := World.current
	var gap := int(_aim.x) % 5
	var centre := Course.to_course(tank.global_position + tank.velocity * 1.8)
	var target := Course.to_world(centre.x, centre.y + (index - 2) * 6.5)
	target.y = Course.height_at(target)
	if index == absi(gap):
		return
	var flight := 1.8
	var velocity := (target - from) / flight + Vector3.UP * 0.5 * 20.0 * flight
	var shell := world.spawn_projectile(Team.ENEMY, from, velocity, "mortar", Palette.HOT)
	shell.gravity = 20.0
	shell.hit = Hit.make(Hit.Kind.SHELL, 0.0, from)
	shell.hit.source = self
	shell.blast_radius = 4.0
	shell.blast_damage = 24.0
	shell.interceptable = true
	shell.intercept_hp = 2.0
	shell.life = flight + 1.0
	shell.trail = Palette.DUSK
	world.fx.marker(target, 4.0, flight, Palette.HOT)
	Sfx.play("launch", from, 0.0, 0.7)


## Hull gone: it loses height trailing fire, then breaks up on the sand.
func _die_in_the_air(delta: float) -> void:
	var world := World.current
	_dying -= delta
	var ground := Course.height_at(global_position)
	global_position += _forward * 30.0 * delta + Vector3.DOWN * (maxf(global_position.y - ground, 0.0) * 1.2 + 4.0) * delta
	model.rotation.z += delta * 2.0
	_flames -= delta
	if _flames <= 0.0:
		_flames = 0.12
		world.fx.explosion(global_position + Vector3(randf_range(-8, 8), 0.0, randf_range(-6, 6)), 2.0)
	world.fx.smoke(global_position, 2, 4.0)
	if _dying <= 0.0 or global_position.y <= ground + 1.0:
		die(killing_hit)


func on_death(_hit: Hit) -> void:
	var world := World.current
	world.fx.explosion(global_position, 12.0)
	world.fx.shockwave(global_position, 40.0, Palette.BUTTER)
	world.fx.debris(global_position, 40, debris, 20.0, 0.8)
	world.fx.dust(global_position, 30, 12.0, Palette.STRAW)
	world.award(score, global_position, true)
	world.style_event("GIANT", 300.0)
	world.shake(0.8, global_position)
	Sfx.play("blast", global_position, 4.0)
