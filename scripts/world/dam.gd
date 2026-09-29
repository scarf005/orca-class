class_name Dam
extends Node3D
## The valley's dam: a wall of concrete blocks, three tiers by 28 columns, sloping up from the arena
## floor to a crest with the reservoir behind it. Its origin is the crest's centre at ground level
## (local +z faces the arena, +x is the road's right). Each block is its own mesh so the wall can
## break where the gunship hits it.

const COLUMNS := 28
const COLUMN_WIDTH := 10.0
const TIERS := [0.0, 10.0, 21.0, 32.0] ## Heights of the tier boundaries.
const FOOT := 12.0 ## Where the sloped face meets the ground (local z).
const CREST := 1.0 ## Where it meets the crest.
const BACK := -5.0 ## The vertical back face, against the reservoir.
const HEIGHT := 32.0
const LAKE_LEVEL := 29.5 ## The reservoir's surface, just under the crest.
const CRASH_HEIGHT := 14.0
const CRASH_STANDOFF := 8.0

class Piece:
	var node: MeshInstance3D
	var column := 0
	var tier := 0
	var center := Vector3.ZERO ## Local centre while it stands.

static var current: Dam

var pieces: Array[Piece] = []


## Local z of the sloped face at height `y`.
static func face_z(y: float) -> float:
	return lerpf(FOOT, CREST, clampf(y / HEIGHT, 0.0, 1.0))


## Where the face is, in the world, at lateral offset `u` and height `y`.
static func face_point(u: float, y: float) -> Vector3:
	return Course.to_world(Course.DAM_D - face_z(y), u, y)


## Where the gunship comes down: in front of the face, at a height the arena camera sees.
static func crash_point(u: float) -> Vector3:
	var lateral := clampf(u, -60.0, 60.0)
	return Course.to_world(Course.DAM_D - face_z(CRASH_HEIGHT) - CRASH_STANDOFF, lateral, CRASH_HEIGHT)


func _init() -> void:
	name = "Dam"
	var rng := RandomNumberGenerator.new()
	rng.seed = 3640
	for column in COLUMNS:
		for tier in TIERS.size() - 1:
			var piece := Piece.new()
			piece.column = column
			piece.tier = tier
			piece.node = MeshInstance3D.new()
			piece.node.mesh = _piece_mesh(piece, rng)
			piece.node.position = piece.center
			add_child(piece.node)
			pieces.append(piece)
	var lake := MeshInstance3D.new()
	lake.mesh = _lake_mesh()
	add_child(lake)


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


static func column_x(column: int) -> float:
	return (column - (COLUMNS - 1) * 0.5) * COLUMN_WIDTH


## One block, built around its own centre so it can tumble when it breaks.
func _piece_mesh(piece: Piece, rng: RandomNumberGenerator) -> Mesh:
	var y0: float = TIERS[piece.tier] if piece.tier > 0 else -2.0 # The foot is sunk into the ground.
	var y1: float = TIERS[piece.tier + 1]
	var x := column_x(piece.column)
	var hw := COLUMN_WIDTH * 0.5 - 0.06 # A hairline seam between columns.
	var z0 := face_z(maxf(y0, 0.0))
	var z1 := face_z(y1)
	piece.center = Vector3(x, (y0 + y1) * 0.5, (maxf(z0, z1) + BACK) * 0.5)
	var o := piece.center
	var front := Palette.MIST if piece.tier % 2 == 1 else Palette.CONCRETE
	if rng.randf() < 0.12:
		front = Palette.ASH # A weathered panel.
	var b := LowPoly.new()
	var fl := Vector3(x - hw, y0, z0) - o
	var fr := Vector3(x + hw, y0, z0) - o
	var tl := Vector3(x - hw, y1, z1) - o
	var tr := Vector3(x + hw, y1, z1) - o
	var bl := Vector3(x - hw, y0, BACK) - o
	var br := Vector3(x + hw, y0, BACK) - o
	var ul := Vector3(x - hw, y1, BACK) - o
	var ur := Vector3(x + hw, y1, BACK) - o
	b.quad(fl, fr, tr, tl, front, Vector3(0, 0.3, 1.0))
	b.quad(tl, tr, ur, ul, Palette.STONE, Vector3.UP)
	b.quad(bl, br, ur, ul, Palette.STONE, Vector3.BACK)
	b.quad(fl, tl, ul, bl, Palette.ASH, Vector3.LEFT)
	b.quad(fr, tr, ur, br, Palette.ASH, Vector3.RIGHT)
	if piece.tier == TIERS.size() - 2:
		# A parapet along the crest's front edge.
		b.box(Transform3D(Basis(), Vector3(x, y1 + 0.7, z1 - 0.3) - o), Vector3(hw * 2.0, 1.4, 0.7), Palette.ASH)
	if piece.tier == 0 and rng.randf() < 0.4:
		b.blob(Transform3D(Basis(), Vector3(x + rng.randf_range(-3, 3), 3.0, z0 - 1.0) - o), 2.5 + rng.randi() % 3, [Palette.FUNGUS, Palette.LILAC, Palette.BLUSH][rng.randi() % 3], 0, 0.4, rng.randi())
	return b.mesh()


func _lake_mesh() -> Mesh:
	var extent := COLUMNS * COLUMN_WIDTH * 0.5
	var mesh := ArrayMesh.new()
	var points := PackedVector3Array([Vector3(-extent, LAKE_LEVEL, BACK), Vector3(extent, LAKE_LEVEL, BACK), Vector3(extent, LAKE_LEVEL, -110.0), Vector3(-extent, LAKE_LEVEL, -110.0)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([points[0], points[3], points[2], points[0], points[2], points[1]])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, Terrain.water_material())
	return mesh
