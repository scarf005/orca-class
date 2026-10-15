class_name Wing
extends Enemy
## Stage 3 boss: a flying wing that keeps station high over the dune run while the rail floors it at 140 km/h.
## Its five belly turrets open one at a time and fire down at the tank, each until it is shot out. Skirts under
## the belly hide them from any shot climbing steeper than SKIRT_ANGLE, so the ground cannot reach them: the tank
## drifts up a ramp to build speed and leaps off its lip high enough to snipe the open turret, with time slowed
## while it has the shot. Once the belly is bare the ramps throw the tank higher, over the wing, and the structures on
## its back come into play: a dorsal missile rack and the two engines. The hull itself only sparks; the turrets and
## those structures are the boss's health. Past the last ramp it comes down low enough to be shot from the road,
## rearing nose-high to show its back to the road once the belly is bare, and when the last part goes it falls out of the sky.

enum State { CRUISE, DYING }

const TURRETS := ["flak", "rocket", "beam", "bomb", "hangar"]
const TURRET_AT := {
	"flak": Vector3(0.0, -0.9, 3.4),
	"rocket": Vector3(-6.5, -0.7, 1.2),
	"beam": Vector3(6.5, -0.7, 1.2),
	"bomb": Vector3(0.0, -1.0, -2.6),
	"hangar": Vector3(12.0, -0.4, 3.6),
}
const UPPER := ["spine", "engine_l", "engine_r"] ## On its back: only a tank above the wing sees them.
const UPPER_AT := {"spine": Vector3(-3.2, 1.95, 0.8), "engine_l": Vector3(-4.4, 1.25, 3.2), "engine_r": Vector3(4.4, 1.25, 3.2)}
const LABELS := {"flak": "WING_FLAK", "rocket": "WING_ROCKET", "beam": "WING_BEAM", "bomb": "WING_BOMB", "hangar": "WING_HANGAR", "spine": "WING_SPINE", "engine_l": "WING_ENGINE_L", "engine_r": "WING_ENGINE_R"}
const MODEL_SCALE := 8.0 ## The airframe is drawn this much bigger than its model-space layout: a carrier's span.
const TURRET_SCALE := 3.0 ## The turrets and back structures are drawn this much bigger than their own layout.
const TURRET_HP := 160.0
const ROUND_DAMAGE := 40.0 ## Like the other bosses, main-gun damage counts in rounds.
const TURRET_RADIUS := 6.0
const HULL_RADIUS := 40.0
const HULL_BOX := AABB(Vector3(-18.0, -1.0, -9.0), Vector3(36.0, 2.0, 16.5)) ## The flat airframe in model space, its mean thickness.
const DROP := 3.0 ## How far an open turret lowers out of its bay, in its own layout: clear below the hull.
const OPEN_RATE := 2.2
const WIND := 0.9
const STATION := 150.0 ## Metres ahead of the rail the wing's centre keeps.
const BARE_STATION := 120.0 ## Closer once the belly is bare, so a leap tops out over its back.
const WEAVE := 20.0 ## Metres it sways across the road.
const ALTITUDE := 58.0 ## Over the road along the ramps: out of the ground's sight, inside a drifted leap's.
const BARE_ALTITUDE := 46.0 ## Lower once the belly is bare, its wingtips still clear of the buried towers.
const LOW_ALTITUDE := 24.0 ## Past the last ramp: low enough for the road to reach.
const LOW_BARE_ALTITUDE := 36.0 ## High enough for its tail to clear the sand while it rears.
const SKIRT_ANGLE := deg_to_rad(10.0) ## Steepest climb a shot can take into the belly's turret bays.
const SLOW := 0.4 ## Time scale while the tank has a turret in sight in the air.
const REAR := 0.55 ## Radians it pitches nose-up past the last ramp once its belly is bare.
const BARE_LIFT := 1.7 ## How much harder the ramps throw the tank up once the belly is bare.
const FLIGHT := {"rocket": 1.4, "bomb": 1.8, "spine": 1.4} ## Seconds the ground-attack rounds fall; held while a leap would outlast them.

var parts: Dictionary = {}
var _state := State.CRUISE
var _forward := Vector3.FORWARD
var _active := "" ## The open belly turret, or the spine once the belly is bare.
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
var _aim_u := 0.0 ## The tank's lane when the volley was called: a rocket salvo keeps to it.
var _dying := 0.0
var _flames := 0.0


func _init() -> void:
	super()
	boss = true
	heavy = true
	flying = true
	trails = true
	armor = 30.0
	for name: String in TURRETS + UPPER:
		parts[name] = TURRET_HP
		_open[name] = 0.0
	max_hp = TURRET_HP * parts.size()
	hp = max_hp
	radius = HULL_RADIUS
	center_height = 0.0
	score = 25000
	despawn_behind = 0.0
	set_meta("title", "BOSS_WING")
	set_meta("phase_marks", range(parts.size() - 1, 0, -1).map(func(i: int) -> float: return float(i) / parts.size()))
	set_meta("frame", 0.22) # The rail camera leans this far toward it.


func _ready() -> void:
	super()
	global_position = _station(0.0)


## Spanwise sections of the airframe from the centreline out to the right tip, mirrored for the left: (x, leading
## edge z, trailing edge z, crest height above the chord, keel depth below it). The fat middle is a blended hull
## carrying the flight deck; the wings sweep back to a saw-toothed trailing edge.
const SECTIONS: Array[Array] = [
	[0.0, -9.0, 7.0, 2.1, 1.7],
	[2.6, -8.2, 7.0, 2.0, 1.6],
	[5.5, -6.0, 6.6, 1.5, 1.2],
	[9.0, -3.2, 3.6, 0.8, 0.55],
	[13.0, -0.4, 6.0, 0.5, 0.35],
	[17.0, 2.6, 4.6, 0.3, 0.2],
	[18.0, 3.4, 4.8, 0.2, 0.15],
]
const RING := [0.0, 0.28, 0.72, 1.0, 0.72, 0.3] ## Chord fraction of each point round a section, upper side first.


func build() -> void:
	var b := LowPoly.new()
	var sections: Array[Array] = []
	for i in range(SECTIONS.size() - 1, 0, -1):
		var mirrored: Array = SECTIONS[i].duplicate()
		mirrored[0] = -mirrored[0]
		sections.append(mirrored)
	sections.append_array(SECTIONS)
	var rings: Array[Array] = []
	for section in sections:
		rings.append(_ring(section))
	for i in rings.size() - 1:
		var x := absf((sections[i][0] + sections[i + 1][0]) * 0.5)
		var centre: Vector3 = (rings[i][1] + rings[i + 1][4]) * 0.5
		for k in RING.size():
			var a: Vector3 = rings[i][k]
			var c: Vector3 = rings[i + 1][k]
			var d: Vector3 = rings[i + 1][(k + 1) % RING.size()]
			var e: Vector3 = rings[i][(k + 1) % RING.size()]
			b.quad(a, c, d, e, _skin(k, i, x), (a + c + d + e) * 0.25 - centre)
	for tip in [rings[0], rings[rings.size() - 1]]:
		var middle: Vector3 = (tip[1] + tip[4]) * 0.5
		for k in RING.size():
			b.tri(middle, tip[k], tip[(k + 1) % RING.size()], Palette.CORAL, Vector3(signf(middle.x), 0, 0))
	_deck(b)
	_belly(b)
	_underside(b, rings)
	# Navigation lights on the tips and exhaust slits along the hull's trailing edge.
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(-18.1, 0.0, 4.1)), Vector3(0.3, 0.3, 0.8), Palette.RED)
	b.box(Transform3D(Basis(), Vector3(18.1, 0.0, 4.1)), Vector3(0.3, 0.3, 0.8), Palette.MINT)
	for x in [-2.0, 2.0]:
		b.box(Transform3D(Basis(), Vector3(x, 0.35, 6.9)), Vector3(1.6, 0.25, 0.12), Palette.AMBER)
	_add_mesh(model, b.mesh())
	model.scale = Vector3.ONE * MODEL_SCALE
	for name: String in TURRETS:
		_make_turret(name)
	for name: String in UPPER:
		_make_upper(name)


## The points round a section: leading edge, upper crest, upper aft, trailing edge, lower aft, keel.
func _ring(section: Array) -> Array[Vector3]:
	var heights := [0.0, section[3], section[3] * 0.55, 0.05, -section[4] * 0.5, -section[4]]
	var ring: Array[Vector3] = []
	for k in RING.size():
		ring.append(Vector3(section[0], heights[k], lerpf(section[1], section[2], RING[k])))
	return ring


## Colour of face `k` round the section (see RING) between sections `i` and `i + 1`, `x` out from the centreline:
## a pale upper skin in alternating panels, darker control surfaces aft, coral leading edges at the tips, and a
## lighter underside in panels, so the belly the tank mostly sees keeps its shape against the sky.
func _skin(k: int, i: int, x: float) -> Color:
	match k:
		0:
			return Palette.CORAL if x > 12.0 else Palette.MIST
		1:
			return Palette.WHITE if i % 2 == 0 else Palette.ASH
		2:
			return Palette.STONE
		3:
			return Palette.ASH
		4:
			if x > 10.0 and x < 14.0:
				return Palette.CORAL # A band under each wing, the boss's marking.
			if x < 2.0:
				return Palette.DUSK # The keel.
			return Palette.WHITE if i % 2 == 0 else Palette.CREAM
	return Palette.CORAL if x > 10.0 and x < 14.0 else Palette.MIST


## The flight deck along the hull's crest, its centreline and edge lights, and the bridge beside it.
func _deck(b: LowPoly) -> void:
	b.glow = false
	b.box(Transform3D(Basis(), Vector3(0, 2.1, -1.0)), Vector3(2.8, 0.08, 7.6), Palette.SLATE)
	for z in range(-4, 3):
		b.box(Transform3D(Basis(), Vector3(0, 2.15, z + 0.0)), Vector3(0.12, 0.04, 0.5), Palette.WHITE)
	b.glow = true
	for z in range(-4, 3):
		for x in [-1.35, 1.35]:
			b.box(Transform3D(Basis(), Vector3(x, 2.16, z + 0.5)), Vector3(0.1, 0.06, 0.1), Palette.AMBER)
	# The nose's bridge windows.
	b.box(Transform3D(Basis(Vector3.RIGHT, -0.42), Vector3(0, 1.0, -7.0)), Vector3(3.2, 0.12, 0.7), Palette.CYAN)
	b.glow = false
	var bridge := Vector3(3.2, 1.95, -2.4)
	b.box(Transform3D(Basis(), bridge + Vector3(0, 0.45, 0)), Vector3(0.9, 0.9, 2.0), Palette.HULL_LIGHT, Palette.MIST)
	b.box(Transform3D(Basis(), bridge + Vector3(0, 1.0, -0.2)), Vector3(0.7, 0.3, 1.2), Palette.ASH)
	b.tube(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), bridge + Vector3(0, 1.1, 0.3)), 0.05, 1.2, 4, Palette.INK)
	b.glow = true
	b.box(Transform3D(Basis(), bridge + Vector3(0, 1.0, -0.82)), Vector3(0.6, 0.1, 0.04), Palette.CYAN)


## What the chasing tank sees of the hull, from behind and below: the lit mouth of the hangar in the hull's tail, a
## row of lights along the trailing edge, ribs down the belly and fins hanging under the tips.
func _underside(b: LowPoly, rings: Array[Array]) -> void:
	b.glow = false
	b.box(Transform3D(Basis(), Vector3(0, -0.3, 6.75)), Vector3(3.2, 0.6, 0.5), Palette.INK)
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(0, -0.3, 6.98)), Vector3(2.8, 0.4, 0.05), Palette.AMBER)
	for x in [-0.7, 0.7]:
		b.box(Transform3D(Basis(), Vector3(x, -0.3, 7.0)), Vector3(0.1, 0.42, 0.06), Palette.INK)
	for i in rings.size() - 1:
		for t in [0.25, 0.75]:
			var at: Vector3 = rings[i][4].lerp(rings[i][3], 0.8).lerp(rings[i + 1][4].lerp(rings[i + 1][3], 0.8), t)
			b.box(Transform3D(Basis(), at + Vector3.DOWN * 0.05), Vector3(0.35, 0.1, 0.35), Palette.CYAN if absf(at.x) > 6.0 else Palette.BUTTER)
	b.glow = false
	for x in [-3.6, 3.6, -8.0, 8.0]:
		var depth := lerpf(1.25, 0.6, (absf(x) - 3.6) / 4.4)
		b.box(Transform3D(Basis(), Vector3(x, -depth - 0.1, 0.8)), Vector3(0.35, 0.35, 8.0 - absf(x) * 0.4), Palette.SLATE)
	for side in [-1.0, 1.0]:
		var fin := Vector3(side * 15.5, -0.6, 4.4)
		b.quad(fin + Vector3(0, 0.5, -1.6), fin + Vector3(0, 0.5, 1.0), fin + Vector3(0, -1.3, 1.4), fin + Vector3(0, -1.1, -0.4), Palette.HULL_LIGHT, Vector3(side, 0, 0))
		b.quad(fin + Vector3(0, 0.5, -1.6), fin + Vector3(0, 0.5, 1.0), fin + Vector3(0, -1.3, 1.4), fin + Vector3(0, -1.1, -0.4), Palette.ASH, Vector3(-side, 0, 0))
		b.glow = true
		b.box(Transform3D(Basis(), fin + Vector3(0, -1.2, 1.3)), Vector3(0.15, 0.25, 0.25), Palette.RED if side < 0.0 else Palette.MINT)
		b.glow = false


## Recessed bays round the belly turrets, framed in amber so the open one reads from the ground.
func _belly(b: LowPoly) -> void:
	for name: String in TURRETS:
		var at: Vector3 = TURRET_AT[name] + Vector3(0, 0.12, 0)
		b.glow = false
		b.box(Transform3D(Basis(), at), Vector3(2.0, 0.1, 2.4), Palette.INK)
		b.glow = true
		for side in [-1.0, 1.0]:
			b.box(Transform3D(Basis(), at + Vector3(side * 1.05, -0.06, 0)), Vector3(0.1, 0.06, 2.5), Palette.AMBER)
			b.box(Transform3D(Basis(), at + Vector3(0, -0.06, side * 1.25)), Vector3(2.2, 0.06, 0.1), Palette.AMBER)


func _add_mesh(parent: Node3D, mesh: Mesh) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	parent.add_child(node)


func _make_turret(name: String) -> void:
	var root := Node3D.new()
	root.position = TURRET_AT[name]
	root.scale = Vector3.ONE * TURRET_SCALE / MODEL_SCALE
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


## The dorsal missile rack and the engine intakes: fixed on the back, no hatches.
func _make_upper(name: String) -> void:
	var pod := Node3D.new()
	pod.position = UPPER_AT[name]
	pod.scale = Vector3.ONE * TURRET_SCALE / MODEL_SCALE
	model.add_child(pod)
	_pods[name] = pod
	var g := LowPoly.new()
	if name == "spine":
		# A block of vertical launch cells opposite the bridge, its lids lit.
		g.box(Transform3D(Basis(), Vector3(0, 0.2, 0)), Vector3(3.0, 0.7, 4.0), Palette.SLATE, Palette.ASH)
		g.glow = true
		for x in [-0.9, 0.0, 0.9]:
			for z in [-1.35, -0.45, 0.45, 1.35]:
				g.box(Transform3D(Basis(), Vector3(x, 0.58, z)), Vector3(0.6, 0.06, 0.6), Palette.AMBER)
		var muzzle := Node3D.new()
		muzzle.position = Vector3(0, 0.8, 0)
		pod.add_child(muzzle)
		_muzzles[name] = muzzle
	else:
		# A long engine nacelle on a pylon: dark intake with a lit fan ahead, glowing exhaust behind.
		g.box(Transform3D(Basis(), Vector3(0, -0.9, 0.4)), Vector3(0.6, 0.8, 6.0), Palette.STONE)
		g.tube(Transform3D(Basis(), Vector3(0, 0, -4.5)), 1.1, 9.0, 8, Palette.HULL_LIGHT)
		g.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -4.55)), 1.0, 0.1, 8, Palette.INK)
		g.glow = true
		g.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -4.62)), 0.5, 0.05, 8, Palette.CYAN)
		g.prism(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 4.55)), 0.85, 0.1, 8, Palette.AMBER)
	_add_mesh(pod, g.mesh())


func _turret_world(name: String) -> Vector3:
	return _pods[name].global_position


## Turrets whose hatches stand open enough to be hit and that the tank can see past the skirts, and once the belly
## is bare the structures on the back the tank sees from above. Like a hunter walking in, a turret cannot be hit
## before its first volley, so every turret gets to shoot back at least once.
func _exposed() -> Array[String]:
	var result: Array[String] = []
	for name: String in TURRETS:
		if parts[name] > 0.0 and _open[name] >= 0.5 and _armed.has(name) and in_sight(name):
			result.append(name)
	for name: String in UPPER:
		if parts[name] > 0.0 and bare() and in_sight(name):
			result.append(name)
	return result


## Whether every belly turret is shot out.
func bare() -> bool:
	return TURRETS.all(func(name: String) -> bool: return parts[name] <= 0.0)


## Whether the tank's gun sees part `name`: a belly turret past the skirts, climbing no steeper than SKIRT_ANGLE to
## it; a part on the back from at least SKIRT_ANGLE above the wing's upper surface.
func in_sight(name: String) -> bool:
	var tank := player()
	if tank == null:
		return false
	var to := _turret_world(name) - tank.hit_center()
	if name in UPPER:
		return -to.normalized().dot(model.global_basis.y.normalized()) >= sin(SKIRT_ANGLE)
	return atan2(to.y, Vector2(to.x, to.z).length()) <= SKIRT_ANGLE


func aim_parts() -> Dictionary:
	var result := {}
	if _state == State.DYING:
		return result
	for name in _exposed():
		result[name] = [_turret_world(name), TURRET_RADIUS, tr(LABELS[name])]
	return result


func module_states() -> Array:
	return (TURRETS + UPPER).map(func(name: String) -> Array: return [tr(LABELS[name]), maxf(parts[name], 0.0) / TURRET_HP])


## An open turret hangs below the belly, so a round that reaches it is the turret's even where it also
## crosses the hull's outline; otherwise the hull is a flat box around the planform.
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
	var to_model := model.global_transform.affine_inverse()
	var hull := HULL_BOX.grow(extra_radius / MODEL_SCALE)
	var entry: Variant = hull.intersects_segment(to_model * from, to_model * to)
	if hull.has_point(to_model * from):
		best = 0.0
	elif entry != null:
		best = from.distance_to(model.global_transform * (entry as Vector3))
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
	for name: String in parts:
		hp += parts[name]


func _break_turret(name: String, direction: Vector3) -> void:
	var world := World.current
	var pod := _pods[name]
	world.fx.explosion(pod.global_position, 3.0 * TURRET_SCALE)
	Sfx.play("blast", pod.global_position)
	Wreck.launch(pod, pod.global_position, 2.0, true, direction * 8.0 + Vector3.DOWN * 4.0)
	_open[name] = 0.0
	if _active == name:
		_active = ""
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


## Where it keeps station: ahead of the rail, swaying across the road, high over the ramps and low past them.
func _station(weave_time: float) -> Vector3:
	var rail := World.current.rail
	var d := rail.d + (BARE_STATION if bare() and not _low() else STATION)
	var u := sin(weave_time * 0.5) * WEAVE
	var p := Course.to_world(d, u)
	var altitude: float = [[ALTITUDE, BARE_ALTITUDE], [LOW_ALTITUDE, LOW_BARE_ALTITUDE]][int(_low())][int(bare())]
	p.y = Course.height(d, u) + altitude + sin(weave_time * 1.1) * 2.0
	return p


## Past the last ramp: down where the road reaches it.
func _low() -> bool:
	return Course.stage is Stage3 and World.current.rail.d > (Course.stage as Stage3).ramps_end()


func behave(delta: float) -> void:
	var world := World.current
	var tank := player()
	if _state == State.DYING:
		world.slow = 1.0
		_die_in_the_air(delta)
		return
	if tank == null:
		return
	tank.ramp_lift = BARE_LIFT if bare() else 1.0
	var before := global_position
	global_position = global_position.lerp(_station(age), 1.0 - exp(-2.5 * delta))
	var moved := global_position - before
	if moved.length() > 0.001:
		_forward = _forward.lerp(moved.normalized(), minf(delta * 10.0, 1.0)).normalized()
	_pose(delta)
	if _active.is_empty():
		_open_next()
	_update_turrets(delta, tank)
	world.slow = SLOW if tank.airborne and not _exposed().is_empty() else 1.0


## Banks into its sway; down low with a bare belly it rears nose-high, its back to the chasing tank.
func _pose(delta: float) -> void:
	var ahead := _forward
	var up := Vector3.UP.rotated(_forward, -cos(age * 0.5) * 0.3)
	if bare() and _low():
		var right := _forward.cross(Vector3.UP).normalized()
		ahead = _forward.rotated(right, REAR)
		up = Vector3.UP.rotated(right, REAR)
	if delta > 0.0:
		model.global_basis = model.global_basis.orthonormalized().slerp(Basis.looking_at(ahead, up), minf(delta * 8.0, 1.0)).scaled(Vector3.ONE * MODEL_SCALE)


func _open_next() -> void:
	for i in TURRETS.size():
		var index := (_next + i) % TURRETS.size()
		if parts[TURRETS[index]] > 0.0:
			_active = TURRETS[index]
			_next = index + 1
			_end_volley(0.8)
			return
	if parts.spine > 0.0:
		_active = "spine"
		_end_volley(0.8)


func _end_volley(pause: float) -> void:
	_wind = 0.0
	_shots = 0
	_shot_timer = 0.0
	_cool = pause


func _update_turrets(delta: float, tank: Tank) -> void:
	for name: String in TURRETS:
		var want := 1.0 if _active == name and parts[name] > 0.0 else 0.0
		_open[name] = move_toward(_open[name], want, OPEN_RATE * delta)
		if parts[name] <= 0.0:
			continue
		var plates: Array = _hatches[name]
		plates[0].position.x = -0.9 - 1.1 * _open[name]
		plates[1].position.x = 0.9 + 1.1 * _open[name]
		_pods[name].position.y = -DROP * _open[name]
		if want == 0.0 and _open[name] < 0.5:
			_pods[name].basis = Basis.looking_at(Vector3(0, 0, 1))
	if _active.is_empty() or (_active in TURRETS and _open[_active] < 0.9):
		return
	var name := _active
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
	if _shot_timer <= 0.0 and tank.landing_in() <= FLIGHT.get(name, INF):
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
	# The beam passes where the hull will be when it fires, in the air or not; the rest show where they will fall.
	_aim = tank.predicted(_wind if name == "beam" else 1.4)
	_aim_u = Course.to_course(tank.global_position).y
	match name:
		"beam":
			var end := _through(muzzle, _aim)
			world.fx.beam(muzzle, end, Palette.HOT, 0.14, _wind)
			world.fx.marker(end, 4.0, _wind, Palette.RED)
		"rocket", "bomb", "spine":
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
		"rocket", "spine":
			# Each rocket falls where the tank will be when it arrives, held while the tank is in the air until it
			# would come down on the landing, the salvo spread across the lane it was in when the volley was called,
			# narrow enough that one drift out of the lane at the first marker clears it.
			var flight: float = FLIGHT.rocket
			var target := Course.ground_at(Course.to_course(tank.predicted(flight)).x, _aim_u + (_shots - 2.5) * 2.0)
			var from := muzzle.global_position
			var velocity := (target - from) / flight + Vector3.UP * 0.5 * 20.0 * flight
			var shot := fire_along("rocket", muzzle, velocity.length(), 0.0, Palette.HOT, velocity, 180.0) # Lofted off the rail, not down the barrel.
			shot.gravity = 20.0
			shot.life = flight + 1.0
			shot.hit = Hit.make(Hit.Kind.SHELL, 0.0, from)
			shot.hit.source = self
			shot.blast_radius = 4.0
			shot.blast_damage = 20.0
			shot.interceptable = true
			shot.trail = Projectile.ROCKET_SMOKE
			world.fx.marker(target, 4.0, flight, Palette.RED)
			Sfx.play("launch", from)
			_shots += 1
			_shot_timer = 0.16
			if _shots >= 6:
				_end_volley(2.0)
		"beam":
			var from := muzzle.global_position
			var to := _through(from, _aim)
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


## Bombs come down in a line across the road where the tank will be when they land, one lane left open.
func _drop_bomb(from: Vector3, tank: Tank, index: int) -> void:
	var world := World.current
	var gap := int(_aim.x) % 5
	var flight: float = FLIGHT.bomb
	var centre := Course.to_course(tank.predicted(flight))
	var target := Course.ground_at(centre.x, centre.y + (index - 2) * 6.5)
	if index == absi(gap):
		return
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


## Where a straight line from `from` through `point` meets the ground.
func _through(from: Vector3, point: Vector3) -> Vector3:
	var ground := Course.height_at(point)
	return from + (point - from) * (from.y - ground) / maxf(from.y - point.y, 0.1)


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
		world.fx.explosion(model.global_transform * Vector3(randf_range(-16, 16), 0.0, randf_range(-6, 6)), 2.0 * TURRET_SCALE)
	world.fx.smoke(global_position, 2, 4.0 * TURRET_SCALE)
	if _dying <= 0.0 or global_position.y <= ground + 1.0:
		die(killing_hit)


func on_death(_hit: Hit) -> void:
	var world := World.current
	world.slow = 1.0
	if player() != null:
		player().ramp_lift = 1.0
	world.fx.explosion(global_position, 12.0 * TURRET_SCALE)
	world.fx.shockwave(global_position, 40.0 * TURRET_SCALE, Palette.BUTTER)
	world.fx.debris(global_position, 40, debris, 20.0 * TURRET_SCALE, 0.8)
	world.fx.dust(global_position, 30, 12.0 * TURRET_SCALE, Palette.STRAW)
	world.award(score, global_position, true)
	world.style_event("GIANT", 300.0)
	world.shake(0.8, global_position)
	Sfx.play("blast", global_position, 4.0)
