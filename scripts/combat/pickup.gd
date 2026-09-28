class_name Pickup
extends Node3D
## A floating power-up. Driving through it or snatching it with the tail applies it.

const COLLECT_RADIUS := 3.4
const IDS := ["coax", "heat", "canister", "dragon", "apfsds", "airburst", "repair", "life"]

var id := "coax"
var collected := false
var _time := 0.0
var _model := Node3D.new()
var _base_y := 0.0
var _carried := false


func _ready() -> void:
	add_child(_model)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _mesh_for(id)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(mesh)
	var ring := MeshInstance3D.new()
	ring.mesh = _ring_mesh(color())
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
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


func _mesh_for(kind: String) -> Mesh:
	var b := LowPoly.new()
	b.glow = true
	var c := color()
	match kind:
		"coax":
			# A stack of three glowing rounds.
			for i in 3:
				b.tube(Transform3D(Basis(), Vector3(-0.35 + i * 0.35, 0, -0.5)), 0.12, 0.8, 6, c, 0.02)
			b.glow = false
			b.box(Transform3D(Basis(), Vector3(0, -0.2, 0)), Vector3(1.2, 0.2, 0.9), Palette.OCHRE)
		"repair":
			b.box(Transform3D(), Vector3(1.0, 0.3, 0.3), c)
			b.box(Transform3D(), Vector3(0.3, 1.0, 0.3), c)
		"life":
			b.blob(Transform3D(), 0.55, c, 0, 0.2, 4)
			b.glow = false
			b.box(Transform3D(Basis(), Vector3(0, -0.2, 0)), Vector3(0.9, 0.35, 1.2), Palette.HULL)
		_:
			# A 100 mm round: case plus a colored projectile tip.
			b.glow = false
			b.prism(Transform3D(Basis(), Vector3(0, -0.6, 0)), 0.22, 0.8, 7, Palette.OCHRE)
			b.glow = true
			b.prism(Transform3D(Basis(), Vector3(0, 0.2, 0)), 0.2, 0.6, 7, c, 0.0)
	return b.mesh()


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
