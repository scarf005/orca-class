class_name TankModel
extends Node3D
## The Orca-class's imported body and code-owned joints. The tail is posed by `Tail`.

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
	_mesh(hull, ActorMeshes.mesh("tank", "hull"))
	for side in [-1.0, 1.0]:
		var track := MeshInstance3D.new()
		track.mesh = ActorMeshes.mesh("tank", "track")
		track.position = Vector3(1.45 * side, 0.0, 0.0)
		hull.add_child(track)
		track_meshes.append(track)
	turret.position = Vector3(0, 1.62, -0.35)
	hull.add_child(turret)
	_mesh(turret, ActorMeshes.mesh("tank", "turret"))
	gun_pivot.position = Vector3(0, 0.42, -1.55)
	turret.add_child(gun_pivot)
	gun_pivot.add_child(barrel)
	_mesh(barrel, ActorMeshes.mesh("tank", "barrel"))
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
	_mesh(fcs, ActorMeshes.mesh("tank", "fcs"))
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


## Rebuilds the coaxial guns for an upgrade tier, e.g. [20, 15]. Mesh resources remain shared.
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


## Also used by the HUD's weapon preview.
static func _coax_mesh(caliber: int, length: float) -> Mesh:
	assert(length == COAX_LENGTHS[caliber], "Coax length is authored in tank.blend")
	return ActorMeshes.mesh("tank", "coax_%d" % caliber)


static func _rws_mesh() -> Mesh:
	return ActorMeshes.mesh("tank", "rws")
