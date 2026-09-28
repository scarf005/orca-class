class_name Pickup
extends Node3D
## A floating power-up. Driving through it or snatching it with the tail applies it.

const COLLECT_RADIUS := 3.4
const IDS := ["coax", "heat", "canister", "dragon", "apfsds", "airburst", "repair", "life", "era", "tail"]

var id := "coax"
var collected := false
var _time := 0.0
var _model := Node3D.new()
var _base_y := 0.0
var _carried := false


func _ready() -> void:
	add_child(_model)
	_model.scale = Vector3.ONE * 1.4
	var mesh := MeshInstance3D.new()
	mesh.mesh = _mesh_for(id)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(mesh)
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh(color())
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ActorLayer.mark(self)
	if World.current:
		World.current.pickups.append(self)


func _exit_tree() -> void:
	if World.current:
		World.current.pickups.erase(self)


func color() -> Color:
	match id:
		"coax": return Palette.BUTTER
		"repair": return Palette.MINT
		"life": return Palette.FUNGUS
		"era": return Palette.SKY
		"tail": return Palette.BLUSH
	return Armament.ROUND_COLORS[Armament.round_from_id(id)]


## Carried by the tail; stops bobbing and despawn checks.
func carry() -> void:
	_carried = true


func release() -> void:
	_carried = false


func _process(delta: float) -> void:
	_time += delta
	_model.rotation.y = _time * 2.5
	if _carried:
		return
	var ground := Course.height_at(global_position)
	_base_y = ground + 1.6
	global_position.y = _base_y + sin(_time * 3.0) * 0.35
	var world := World.current
	if world and world.rail.mode != Rail.Mode.ARENA and Course.to_course(global_position).x < world.rail.d - 25.0:
		queue_free()


static var _meshes := {}


func _mesh_for(kind: String) -> Mesh:
	if not _meshes.has(kind):
		var b := LowPoly.new()
		var c := color()
		match kind:
			"coax":
				_ammo_box(b, c)
			"repair":
				_toolbox(b, c)
			"era":
				_era_stack(b, c)
			"tail":
				_tail_coil(b, c)
			"life":
				_mini_tank(b, c)
			_:
				_round(b, kind, c)
		_meshes[kind] = b.mesh()
	return _meshes[kind]


## A 100 mm round standing upright: rimmed brass case with primer, driving band and a nose shaped
## by type.
static func _round(b: LowPoly, kind: String, c: Color) -> void:
	var up := func(y: float) -> Transform3D: return Transform3D(Basis(), Vector3(0, y, 0))
	b.prism(up.call(-0.95), 0.27, 0.06, 12, Palette.OCHRE)
	b.prism(up.call(-0.89), 0.24, 0.75, 12, Palette.BUTTER, 0.23, Palette.OCHRE)
	b.prism(up.call(-0.14), 0.23, 0.08, 12, Palette.OCHRE)
	b.prism(up.call(-0.97), 0.07, 0.02, 8, Palette.STONE)
	match kind:
		"apfsds":
			# Sabot petals around a long finned dart.
			b.prism(up.call(-0.06), 0.22, 0.35, 12, Palette.STONE, 0.2)
			for i in 3:
				b.box(Transform3D(Basis(Vector3.UP, TAU * i / 3.0), Vector3(0, 0.12, 0)), Vector3(0.44, 0.3, 0.03), Palette.INK)
			b.prism(up.call(0.29), 0.06, 0.8, 8, c, 0.04)
			b.glow = true
			b.prism(up.call(1.09), 0.04, 0.18, 8, c, 0.0)
			b.glow = false
			for i in 4:
				b.box(Transform3D(Basis(Vector3.UP, PI * 0.5 * i), Vector3(0, 0.36, 0)), Vector3(0.22, 0.12, 0.02), Palette.SLATE)
		"heat":
			b.prism(up.call(-0.06), 0.22, 0.3, 12, c, 0.2)
			b.prism(up.call(0.24), 0.2, 0.35, 12, c, 0.08)
			b.prism(up.call(0.59), 0.035, 0.35, 6, Palette.STONE)
			b.glow = true
			b.blob(up.call(0.95), 0.06, Palette.WHITE)
			b.glow = false
		"canister":
			b.prism(up.call(-0.06), 0.22, 0.55, 12, c, 0.22, Palette.STONE)
			b.glow = true
			for i in 7:
				var angle := TAU * i / 7.0
				b.blob(Transform3D(Basis(), Vector3(cos(angle) * 0.13, 0.5, sin(angle) * 0.13)), 0.05, Palette.WHITE)
			b.glow = false
		"airburst":
			b.prism(up.call(-0.06), 0.22, 0.3, 12, c, 0.2)
			b.prism(up.call(0.24), 0.2, 0.3, 12, Palette.INK, 0.13)
			b.prism(up.call(0.54), 0.13, 0.22, 12, c, 0.0)
			b.glow = true
			b.prism(up.call(0.2), 0.225, 0.04, 12, Palette.CYAN)
			b.glow = false
		_:
			# Dragon's breath: a stubby incendiary nose with glowing vents.
			b.prism(up.call(-0.06), 0.22, 0.3, 12, c, 0.21)
			b.prism(up.call(0.24), 0.21, 0.3, 12, c, 0.0)
			b.glow = true
			for i in 4:
				b.box(Transform3D(Basis(Vector3.UP, PI * 0.5 * i), Vector3(0, 0.1, 0)).translated_local(Vector3(0.215, 0, 0)), Vector3(0.02, 0.12, 0.06), Palette.AMBER)
			b.glow = false


## An open ammo box with a belt of cartridges hanging over the side.
static func _ammo_box(b: LowPoly, c: Color) -> void:
	b.box(Transform3D(Basis(), Vector3(0, -0.35, 0)), Vector3(1.0, 0.6, 0.55), Palette.PINE, Palette.MOSS)
	b.box(Transform3D(Basis(Vector3.RIGHT, -0.9), Vector3(0, 0.05, -0.38)), Vector3(1.02, 0.05, 0.56), Palette.PINE)
	b.box(Transform3D(Basis(), Vector3(0, -0.35, 0.285)), Vector3(0.5, 0.18, 0.02), Palette.BUTTER)
	b.box(Transform3D(Basis(), Vector3(0, 0.0, 0)), Vector3(0.3, 0.05, 0.08), Palette.INK)
	for i in 7:
		var t := i / 6.0
		var p := Vector3(-0.42 + t * 0.95, -0.02 + sin(t * PI) * 0.25 - t * 0.45, 0.1 + t * 0.3)
		var tilt := Basis(Vector3.BACK, -0.3 + t * 1.2)
		b.prism(Transform3D(tilt, p), 0.05, 0.3, 8, Palette.BUTTER)
		b.glow = true
		b.prism(Transform3D(tilt, p + tilt * Vector3(0, 0.3, 0)), 0.05, 0.12, 8, c, 0.0)
		b.glow = false
		b.box(Transform3D(tilt, p + tilt * Vector3(0, 0.08, 0)), Vector3(0.13, 0.04, 0.12), Palette.SLATE)


## A mint toolbox with a wrench across the lid and a cross badge.
static func _toolbox(b: LowPoly, c: Color) -> void:
	b.box(Transform3D(Basis(), Vector3(0, -0.3, 0)), Vector3(1.0, 0.5, 0.5), c, Palette.MINT)
	b.box(Transform3D(Basis(), Vector3(0, -0.02, 0)), Vector3(1.02, 0.06, 0.52), Palette.TEAL)
	b.box(Transform3D(Basis(), Vector3(0, 0.12, 0)), Vector3(0.08, 0.22, 0.08), Palette.STONE)
	b.box(Transform3D(Basis(), Vector3(0, 0.22, 0)), Vector3(0.5, 0.06, 0.08), Palette.STONE)
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(0, -0.3, 0.26)), Vector3(0.3, 0.1, 0.02), Palette.WHITE)
	b.box(Transform3D(Basis(), Vector3(0, -0.3, 0.26)), Vector3(0.1, 0.3, 0.02), Palette.WHITE)
	b.glow = false
	# Wrench: handle and an open jaw ring.
	var tilt := Basis(Vector3.UP, 0.5) * Basis(Vector3.BACK, 0.25)
	b.box(Transform3D(tilt, Vector3(0, 0.45, 0)), Vector3(0.9, 0.08, 0.12), Palette.ASH)
	for i in 6:
		var angle := PI * 0.3 + i * PI * 0.28
		b.box(Transform3D(tilt, tilt * Vector3(0.5 + cos(angle) * 0.14, 0.45, sin(angle) * 0.14)), Vector3(0.08, 0.08, 0.08), Palette.ASH)


## Three reactive armor bricks with bolts and hazard stripes.
static func _era_stack(b: LowPoly, c: Color) -> void:
	for i in 3:
		var y := -0.45 + i * 0.32
		var twist := Basis(Vector3.UP, (i - 1) * 0.18)
		b.box(Transform3D(twist, Vector3(0, y, 0)), Vector3(0.95, 0.26, 0.65), Palette.SAGE, Palette.HULL_LIGHT)
		for k in 3:
			b.box(Transform3D(twist, twist * Vector3(-0.3 + k * 0.3, y, 0.33)), Vector3(0.14, 0.2, 0.02), Palette.BUTTER if k % 2 == 0 else Palette.INK)
		b.glow = true
		for corner in [Vector3(-0.4, 0.14, -0.26), Vector3(0.4, 0.14, -0.26), Vector3(-0.4, 0.14, 0.26), Vector3(0.4, 0.14, 0.26)]:
			b.box(Transform3D(twist, twist * corner + Vector3(0, y, 0)), Vector3(0.06, 0.03, 0.06), c)
		b.glow = false


## A coiled five-joint tail with the pink claw.
static func _tail_coil(b: LowPoly, c: Color) -> void:
	var points: Array[Vector3] = []
	for i in 7:
		var angle := i * 0.9
		points.append(Vector3(cos(angle) * (0.55 - i * 0.05), -0.45 + i * 0.16, sin(angle) * (0.55 - i * 0.05)))
	for i in points.size() - 1:
		var a := points[i]
		var d := points[i + 1] - a
		var r0 := 0.2 - i * 0.022
		b.blob(Transform3D(Basis(), a), r0 * 1.05, Palette.HULL_LIGHT, 1, 0.0, i)
		b.prism(Transform3D(Basis(Vector3.UP.cross(d).normalized(), Vector3.UP.angle_to(d)), a), r0, d.length(), 8, Palette.HULL_LIGHT, r0 - 0.022)
		b.box(Transform3D(Basis(), (a + points[i + 1]) * 0.5 + Vector3.UP * r0 * 0.8), Vector3(0.08, 0.05, 0.08), Palette.FUNGUS)
	var tip := points[-1]
	b.glow = true
	for side in [-1.0, 1.0]:
		b.prism(Transform3D(Basis(Vector3.BACK, side * 0.5), tip + Vector3(side * 0.06, 0, 0)), 0.07, 0.35, 4, c, 0.0)
	b.glow = false


## A miniature Orca-class: the spare hull.
static func _mini_tank(b: LowPoly, c: Color) -> void:
	var s := 0.28
	b.box(Transform3D(Basis(), Vector3(0, -0.15, 0)), Vector3(3.4, 0.9, 6.4) * s, Palette.HULL, Palette.HULL_LIGHT)
	for side in [-1.0, 1.0]:
		b.box(Transform3D(Basis(), Vector3(side * 1.45 * s, -0.25, 0)), Vector3(0.7, 0.8, 6.6) * s, Palette.INK)
	b.box(Transform3D(Basis(), Vector3(0, 0.2, -0.1)), Vector3(2.6, 0.7, 3.2) * s, Palette.HULL_LIGHT)
	b.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(0, 0.22, -0.5)), 0.05, 1.3, 8, Palette.HULL)
	b.glow = true
	b.blob(Transform3D(Basis(), Vector3(0, 0.1, 1.15)), 0.12, c)
	b.box(Transform3D(Basis(), Vector3(0, 0.5, 0)), Vector3(0.12, 0.12, 0.12), c)
	b.glow = false


static func _ring_mesh(c: Color) -> Mesh:
	var b := LowPoly.new()
	b.glow = true
	for i in 12:
		var a0 := TAU * i / 12.0
		var a1 := TAU * (i + 0.5) / 12.0
		var o0 := Vector3(cos(a0), 0, sin(a0)) * 1.2
		var o1 := Vector3(cos(a1), 0, sin(a1)) * 1.2
		b.quad(o0, o1, o1 * 1.15, o0 * 1.15, c, Vector3.UP)
	return b.mesh()
