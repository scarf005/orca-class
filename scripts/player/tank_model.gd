class_name TankModel
extends Node3D
## The Orca-class's low-poly body: hull and tracks, a turret with the 100 mm gun, coaxial guns
## that change with the upgrade tier, the laser RWS and the gunner's FCS sight on the roof. The tail is built by `Tail`.

# Receivers sit behind the mantlet; only the short barrels emerge beside the main gun.
const COAX_SLOTS: Array[Vector3] = [Vector3(0.31, 0.0, 0.1), Vector3(-0.31, 0.0, 0.1), Vector3(0.0, 0.20, 0.1)]
const COAX_LENGTHS := {8: 0.7, 15: 0.85, 20: 1.0}

var hull := Node3D.new()
var turret := Node3D.new()
var gun_pivot := Node3D.new()
var barrel := Node3D.new()
var muzzle := Node3D.new()
var rws := Node3D.new()
var rws_lens := Node3D.new()
var fcs := Node3D.new()
var coax_root := Node3D.new()
var coax_muzzles: Array[Node3D] = []
var tail_mount := Node3D.new()
var track_meshes: Array[MeshInstance3D] = []
var _track_phase := 0.0


func _ready() -> void:
	add_child(hull)
	_mesh(hull, _hull_mesh())
	for side in [-1.0, 1.0]:
		var track := MeshInstance3D.new()
		track.mesh = _track_mesh()
		track.position = Vector3(1.45 * side, 0.0, 0.0)
		hull.add_child(track)
		track_meshes.append(track)
	turret.position = Vector3(0, 1.62, -0.35)
	hull.add_child(turret)
	_mesh(turret, _turret_mesh())
	gun_pivot.position = Vector3(0, 0.42, -1.55)
	turret.add_child(gun_pivot)
	gun_pivot.add_child(barrel)
	_mesh(barrel, _barrel_mesh())
	muzzle.position = Vector3(0, 0, -5.9)
	barrel.add_child(muzzle)
	gun_pivot.add_child(coax_root)
	rws.position = Vector3(-0.85, 0.95, 0.75)
	turret.add_child(rws)
	_mesh(rws, _rws_mesh())
	rws_lens.position = Vector3(0, 0.42, -0.45)
	rws.add_child(rws_lens)
	fcs.position = Vector3(0.85, 0.95, 1.25)
	turret.add_child(fcs)
	_mesh(fcs, _fcs_mesh())
	tail_mount.position = Vector3(0, 1.45, 3.45)
	hull.add_child(tail_mount)
	set_coax_guns([8])


func _mesh(parent: Node3D, mesh: Mesh) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	parent.add_child(instance)
	return instance


## World position of a roof sensor's middle ("laser" is the RWS, "fcs" the sight).
func sensor_position(name: String) -> Vector3:
	return (rws if name == "laser" else fcs).to_global(Vector3(0, 0.4, 0))


## Copies a roof sensor into the world as a loose piece at its own pose and hides the mounted one;
## the caller throws it.
func detach(part: Node3D) -> Node3D:
	var piece := part.duplicate() as Node3D
	World.current.add_child(piece)
	piece.global_transform = part.global_transform
	part.visible = false
	return piece


## Rebuilds the coaxial guns for an upgrade tier, e.g. [20, 15].
func set_coax_guns(calibers: Array) -> void:
	for child in coax_root.get_children():
		child.queue_free()
	coax_muzzles.clear()
	for i in calibers.size():
		var gun := Node3D.new()
		gun.position = COAX_SLOTS[i]
		coax_root.add_child(gun)
		var length := COAX_LENGTHS[calibers[i]] as float
		_mesh(gun, _coax_mesh(calibers[i], length))
		var tip := Node3D.new()
		tip.position = Vector3(0, 0.02, -length - 0.3)
		gun.add_child(tip)
		coax_muzzles.append(tip)


## Scrolls the track tread pattern by swapping mesh offsets; `speed` in m/s per side.
func animate_tracks(delta: float, left_speed: float, right_speed: float) -> void:
	_track_phase += delta
	for i in track_meshes.size():
		var speed := left_speed if i == 0 else right_speed
		track_meshes[i].position.y = 0.02 * sin(_track_phase * 30.0 + i) * clampf(absf(speed) / 10.0, 0.0, 1.0)


func _hull_mesh() -> Mesh:
	var b := LowPoly.new()
	# Lower hull between the tracks.
	b.box(Transform3D(Basis(), Vector3(0, 0.95, 0.2)), Vector3(2.3, 0.9, 6.4), Palette.HULL)
	# Upper hull deck, wider than the lower hull, overhanging the tracks.
	var deck := [Vector3(-1.85, 1.4, -2.2), Vector3(1.85, 1.4, -2.2), Vector3(1.85, 1.4, 3.4), Vector3(-1.85, 1.4, 3.4)]
	var belly := [Vector3(-1.85, 1.05, -2.6), Vector3(1.85, 1.05, -2.6), Vector3(1.85, 1.05, 3.5), Vector3(-1.85, 1.05, 3.5)]
	b.quad(deck[0], deck[1], deck[2], deck[3], Palette.HULL_LIGHT, Vector3.UP)
	b.quad(belly[0], belly[1], belly[2], belly[3], Palette.PINE, Vector3.DOWN)
	b.quad(deck[1], deck[2], belly[2], belly[1], Palette.HULL, Vector3.RIGHT)
	b.quad(deck[0], deck[3], belly[3], belly[0], Palette.HULL, Vector3.LEFT)
	b.quad(deck[2], deck[3], belly[3], belly[2], Palette.PINE, Vector3.BACK)
	# Sloped upper glacis and a lower nose plate.
	var nose := [Vector3(-1.85, 0.55, -3.5), Vector3(1.85, 0.55, -3.5)]
	b.quad(deck[0], deck[1], belly[1], belly[0], Palette.HULL_LIGHT, Vector3(0, 0.6, -1))
	b.quad(belly[0], belly[1], nose[1], nose[0], Palette.HULL, Vector3(0, -0.3, -1))
	b.tri(deck[0], belly[0], nose[0], Palette.HULL, Vector3.LEFT)
	b.tri(deck[1], belly[1], nose[1], Palette.HULL, Vector3.RIGHT)
	# Driver's hatch and periscopes on the glacis (Ha Yoon's seat).
	b.box(Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0.0, 1.38, -2.05)), Vector3(0.9, 0.12, 0.6), Palette.PINE)
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(-0.25, 1.46, -1.9)), Vector3(0.18, 0.05, 0.08), Palette.SKY)
	b.box(Transform3D(Basis(), Vector3(0.25, 1.46, -1.9)), Vector3(0.18, 0.05, 0.08), Palette.SKY)
	b.glow = false
	# Engine deck grilles and exhausts at the rear.
	for i in 4:
		b.box(Transform3D(Basis(), Vector3(-0.9 + i * 0.6, 1.43, 2.6)), Vector3(0.4, 0.06, 1.2), Palette.PINE)
	b.box(Transform3D(Basis(), Vector3(1.3, 1.25, 3.55)), Vector3(0.5, 0.3, 0.2), Palette.DUSK)
	# Side skirts with a stripe.
	for side in [-1.0, 1.0]:
		b.box(Transform3D(Basis(), Vector3(1.95 * side, 0.9, 0.3)), Vector3(0.12, 0.55, 6.4), Palette.HULL)
		b.box(Transform3D(Basis(), Vector3(2.02 * side, 0.95, -1.2)), Vector3(0.03, 0.14, 1.6), Palette.FUNGUS)
	# Tow hooks, headlights.
	b.box(Transform3D(Basis(), Vector3(-1.2, 0.95, -3.0)), Vector3(0.3, 0.2, 0.2), Palette.CREAM)
	b.box(Transform3D(Basis(), Vector3(1.2, 0.95, -3.0)), Vector3(0.3, 0.2, 0.2), Palette.CREAM)
	return b.mesh()


func _track_mesh() -> Mesh:
	var b := LowPoly.new()
	# Tread band with a sloped front and rear.
	var top_front := Vector3(0, 1.0, -3.1)
	var top_back := Vector3(0, 1.0, 3.3)
	var low_front := Vector3(0, 0.12, -2.5)
	var low_back := Vector3(0, 0.12, 2.8)
	var w := 0.38
	var pts := [top_front, top_back, Vector3(0, 0.55, 3.6), low_back, low_front, Vector3(0, 0.6, -3.4)]
	for i in pts.size():
		var a: Vector3 = pts[i]
		var c: Vector3 = pts[(i + 1) % pts.size()]
		var mid := (a + c) * 0.5
		var out := mid - Vector3(0, 0.6, 0)
		out.x = 0.0
		b.quad(a + Vector3(-w, 0, 0), c + Vector3(-w, 0, 0), c + Vector3(w, 0, 0), a + Vector3(w, 0, 0), Palette.DUSK if i % 2 == 0 else Palette.INK, out)
	for side in [-1.0, 1.0]:
		var face := []
		for p: Vector3 in pts:
			face.append(p + Vector3(w * side, 0, 0))
		for i in range(1, face.size() - 1):
			b.tri(face[0], face[i], face[i + 1], Palette.INK, Vector3(side, 0, 0))
	# Road wheels.
	for i in 6:
		var z := -2.3 + i * 0.95
		b.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.42, 0.45, z)), 0.36, 0.06, 8, Palette.SLATE, -1.0, Palette.ASH)
	return b.mesh()


func _turret_mesh() -> Mesh:
	var b := LowPoly.new()
	var top := [Vector3(-1.3, 0.85, -1.2), Vector3(1.3, 0.85, -1.2), Vector3(1.45, 0.85, 1.9), Vector3(-1.45, 0.85, 1.9)]
	var bottom := [Vector3(-1.55, 0.0, -1.7), Vector3(1.55, 0.0, -1.7), Vector3(1.6, 0.0, 1.9), Vector3(-1.6, 0.0, 1.9)]
	var cheek := [Vector3(-0.7, 0.55, -1.95), Vector3(0.7, 0.55, -1.95)]
	b.quad(top[0], top[1], top[2], top[3], Palette.HULL_LIGHT, Vector3.UP)
	b.quad(top[1], top[2], bottom[2], bottom[1], Palette.HULL, Vector3.RIGHT)
	b.quad(top[0], top[3], bottom[3], bottom[0], Palette.HULL, Vector3.LEFT)
	b.quad(top[2], top[3], bottom[3], bottom[2], Palette.PINE, Vector3.BACK)
	# Angled cheek armor forms a wedge nose around the mantlet.
	b.quad(top[0], top[1], cheek[1], cheek[0], Palette.HULL_LIGHT, Vector3(0, 0.5, -1))
	b.quad(cheek[0], cheek[1], bottom[1], bottom[0], Palette.HULL, Vector3(0, -0.2, -1))
	b.tri(top[1], cheek[1], bottom[1], Palette.HULL, Vector3(1, 0, -0.6))
	b.tri(top[0], cheek[0], bottom[0], Palette.HULL, Vector3(-1, 0, -0.6))
	# Mantlet.
	b.box(Transform3D(Basis(), Vector3(0, 0.42, -1.95)), Vector3(0.9, 0.62, 0.5), Palette.PINE)
	# Commander's cupola and sight.
	b.prism(Transform3D(Basis(), Vector3(0.7, 0.85, 0.3)), 0.42, 0.28, 7, Palette.HULL, 0.36, Palette.HULL_LIGHT)
	b.box(Transform3D(Basis(), Vector3(0.35, 1.05, -0.6)), Vector3(0.4, 0.3, 0.4), Palette.HULL)
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(0.35, 1.08, -0.81)), Vector3(0.28, 0.14, 0.02), Palette.SKY)
	b.glow = false
	# Rear stowage bins and antenna base.
	b.box(Transform3D(Basis(), Vector3(0, 0.45, 2.1)), Vector3(2.8, 0.6, 0.5), Palette.PINE)
	b.box(Transform3D(Basis(), Vector3(-1.1, 0.95, 1.5)), Vector3(0.08, 0.2, 0.08), Palette.INK)
	b.prism(Transform3D(Basis(), Vector3(-1.1, 1.0, 1.5)), 0.02, 1.8, 3, Palette.INK)
	b.box(Transform3D(Basis(), Vector3(1.61, 0.4, 0.4)), Vector3(0.04, 0.12, 1.4), Palette.FUNGUS)
	return b.mesh()


func _barrel_mesh() -> Mesh:
	var b := LowPoly.new()
	b.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(0, 0, 0.1)), 0.17, 1.2, 8, Palette.HULL)
	b.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(0, 0, -1.1)), 0.12, 4.6, 8, Palette.HULL)
	# Fume extractor and muzzle brake.
	b.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(0, 0, -2.6)), 0.19, 0.8, 8, Palette.HULL_LIGHT)
	b.box(Transform3D(Basis(), Vector3(0, 0, -5.65)), Vector3(0.4, 0.3, 0.5), Palette.PINE)
	return b.mesh()


static func _coax_mesh(caliber: int, length: float) -> Mesh:
	var b := LowPoly.new()
	var body := {8: Vector3(0.18, 0.2, 0.6), 15: Vector3(0.26, 0.28, 0.8), 20: Vector3(0.34, 0.36, 1.0)}[caliber] as Vector3
	var color := {8: Palette.SLATE, 15: Palette.DUSK, 20: Palette.INK}[caliber] as Color
	b.box(Transform3D(Basis(), Vector3(0, 0, 0.45)), body, color)
	var radius := {8: 0.035, 15: 0.055, 20: 0.075}[caliber] as float
	var breech := 0.45 - body.z * 0.5
	b.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(0, 0.02, breech)), radius, length + 0.3 + breech, 6, color)
	if caliber == 20:
		b.box(Transform3D(Basis(), Vector3(0.24, -0.05, 0.45)), Vector3(0.14, 0.3, 0.5), Palette.OCHRE)
		b.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(0, 0.02, -length + 0.1)), radius * 1.6, 0.3, 6, color)
	return b.mesh()


static func _rws_mesh() -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(), 0.3, 0.3, 6, Palette.HULL)
	b.box(Transform3D(Basis(), Vector3(0, 0.45, 0)), Vector3(0.55, 0.35, 0.8), Palette.HULL_LIGHT)
	b.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(0, 0.42, -0.4)), 0.13, 0.12, 8, Palette.SLATE)
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(0, 0.42, -0.53)), Vector3(0.16, 0.16, 0.02), Palette.MINT)
	return b.mesh()


## The gunner's sight: a boxy periscope head with a glowing lens and a rangefinder window.
static func _fcs_mesh() -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(), 0.26, 0.2, 6, Palette.HULL)
	b.box(Transform3D(Basis(), Vector3(0, 0.42, 0)), Vector3(0.6, 0.4, 0.55), Palette.HULL_LIGHT)
	b.box(Transform3D(Basis(), Vector3(0, 0.7, 0.05)), Vector3(0.5, 0.08, 0.4), Palette.PINE)
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(-0.14, 0.44, -0.29)), Vector3(0.2, 0.18, 0.02), Palette.SKY)
	b.box(Transform3D(Basis(), Vector3(0.16, 0.44, -0.29)), Vector3(0.12, 0.12, 0.02), Palette.BUTTER)
	return b.mesh()
