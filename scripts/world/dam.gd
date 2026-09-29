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
const LAKE_END := -110.0 ## Where the lake ends, behind the wall.
const HEIGHT := 32.0
const LAKE_LEVEL := 29.5 ## The reservoir's surface, just under the crest.
const CRASH_HEIGHT := 14.0
const CRASH_STANDOFF := 8.0
const GRAVITY := 24.0
const LIP := Vector3(0.0, 29.0, -8.0) ## Where the reservoir spills over the bank behind a broken section.
const SPILL_SPEED := 10.0
const SPILL_GRAVITY := 20.0
const TORRENT_DELAY := 0.8 ## Seconds after the impact before water breaks through.
const FLOOD_DELAY := 1.5
const FLOOD_TIME := 7.0 ## The flood takes this long to reach its full spread.
const FLOOD_REACH := 130.0 ## How far from the foot it ends up, in metres.
const FLOOD_Y := 1.1
const SHEET_COLORS := [Palette.TEAL, Palette.SKY, Palette.WHITE, Palette.SKY, Palette.TEAL]
const FLOOD_COLORS := [Palette.TEAL, Palette.TEAL, Palette.SKY, Palette.TEAL, Palette.SKY, Palette.TEAL]

enum State { STANDING, BROKEN, FLYING, LANDED } ## BROKEN: doomed, waiting for its turn to go.

class Piece:
	var node: MeshInstance3D
	var column := 0
	var tier := 0
	var center := Vector3.ZERO ## Local centre while it stands.
	var state := State.STANDING
	var velocity := Vector3.ZERO
	var spin := Vector3.ZERO
	var launch_at := 0.0 ## Seconds after the impact.
	var landed_at := 0.0
	var rest_y := 0.0

static var current: Dam

var pieces: Array[Piece] = []
var breached := false
var torrent: MeshInstance3D ## The falling sheet of water through the gap.
var flood: MeshInstance3D ## The water spreading over the arena floor.
var _clock := 0.0
var _gap := Vector2.ZERO ## Local x range of the columns broken through to the ground.
var _rates := {}
var _next_rumble := 0.0


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


## The surface of the lake behind the wall or of the flood over the arena floor at `p`, else -INF.
func surface_at(p: Vector3) -> float:
	var local := to_local(p)
	if local.z < BACK and local.z > LAKE_END and absf(local.x) < COLUMNS * COLUMN_WIDTH * 0.5:
		return LAKE_LEVEL if Course.height_at(p) < LAKE_LEVEL else -INF
	if not breached:
		return -INF
	var reach := flood_reach()
	var start := _spill_at(_landing_time(), 0.0).z
	var f := (local.z - start) / maxf(reach, 0.001)
	if f < 0.0 or f > 1.0:
		return -INF
	var mid := (_gap.x + _gap.y) * 0.5
	var half := minf(115.0, 22.0 + reach * 0.85)
	if absf(local.x - mid) > lerpf(_gap.y - _gap.x, half * 2.0, f * flood_spread()) * 0.5:
		return -INF
	return FLOOD_Y


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
	var points := PackedVector3Array([Vector3(-extent, LAKE_LEVEL, BACK), Vector3(extent, LAKE_LEVEL, BACK), Vector3(extent, LAKE_LEVEL, LAKE_END), Vector3(-extent, LAKE_LEVEL, LAKE_END)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([points[0], points[3], points[2], points[0], points[2], points[1]])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, Terrain.water_material())
	return mesh


## The wall breaks around `at` (a world point on or near the face): the blocks nearest go first
## and the crest there collapses, leaving a jagged breach that the reservoir then pours through.
func breach(at: Vector3) -> void:
	if breached:
		return
	breached = true
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var center := clampi(int(floorf(to_local(at).x / COLUMN_WIDTH + COLUMNS * 0.5)), 3, COLUMNS - 4)
	_gap = Vector2(column_x(center - 1) - COLUMN_WIDTH * 0.5, column_x(center + 1) + COLUMN_WIDTH * 0.5)
	var top := TIERS.size() - 1
	for piece in pieces:
		var reach := absi(piece.column - center)
		var lost := 0
		match reach:
			0, 1: lost = top
			2: lost = 2 if rng.randf() < 0.85 else 1
			3: lost = 1 if rng.randf() < 0.7 else 0
			4: lost = 1 if rng.randf() < 0.25 else 0
		if piece.tier < top - lost:
			continue
		piece.state = State.BROKEN
		piece.launch_at = 0.05 + reach * 0.08 + piece.tier * 0.15 + rng.randf() * 0.1
		# Everything is flung clear of the gap, so the water has room to fall.
		piece.velocity = Vector3((piece.column - center) * 2.5 + rng.randf_range(-3.0, 3.0), rng.randf_range(6.0, 14.0), rng.randf_range(14.0, 26.0))
		piece.spin = Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(-1.5, 1.5), rng.randf_range(-2.5, 2.5))
	torrent = MeshInstance3D.new()
	torrent.mesh = ArrayMesh.new()
	torrent.material_override = Terrain.water_material(true)
	torrent.visible = false
	add_child(torrent)
	flood = MeshInstance3D.new()
	flood.mesh = ArrayMesh.new()
	flood.material_override = Terrain.water_material(true)
	flood.visible = false
	add_child(flood)


func _process(delta: float) -> void:
	if not breached:
		return
	_clock += delta
	for piece in pieces:
		if piece.state == State.BROKEN and _clock >= piece.launch_at:
			_launch(piece)
		if piece.state == State.FLYING:
			_fly(piece, delta)
		elif piece.state == State.LANDED:
			# A landed block crumbles down into a low heap of rubble.
			var crumble := clampf((_clock - piece.landed_at) / 1.2, 0.0, 1.0)
			piece.node.scale = Vector3.ONE * lerpf(1.0, 0.4, crumble)
			piece.node.position.y = lerpf(piece.rest_y, piece.rest_y - 1.5, crumble)
	var flow := clampf((_clock - TORRENT_DELAY) / 1.0, 0.0, 1.0)
	if flow > 0.0:
		_update_torrent(flow)
		_emit_spray(delta, flow)
	var spread := flood_spread()
	if spread > 0.0:
		_update_flood(spread)


## 0..1 progress of the flood over the arena floor.
func flood_spread() -> float:
	return clampf((_clock - FLOOD_DELAY) / FLOOD_TIME, 0.0, 1.0)


## How far the flood has come from the dam's foot, in metres.
func flood_reach() -> float:
	return FLOOD_REACH * (1.0 - pow(1.0 - flood_spread(), 2.0))


func _launch(piece: Piece) -> void:
	var world := World.current
	piece.state = State.FLYING
	var at := to_global(piece.center)
	world.fx.shatter(AABB(at - Vector3.ONE * 5.0, Vector3.ONE * 10.0), [Fx.Debris.CONCRETE, Fx.Debris.ROCK], global_basis * Vector3(0, 0, 0.6), 0.12)
	world.fx.dust(at, 6, 4.0, Palette.MIST)
	Sfx.play("rubble", at, 3.0, randf_range(0.5, 0.8))


func _fly(piece: Piece, delta: float) -> void:
	piece.velocity.y -= GRAVITY * delta
	piece.node.position += piece.velocity * delta
	piece.node.rotation += piece.spin * delta
	var ground := Course.height_at(to_global(piece.node.position))
	if to_global(piece.node.position).y < ground + 3.0 and piece.velocity.y < 0.0:
		var at := to_global(piece.node.position)
		piece.state = State.LANDED
		piece.velocity = Vector3.ZERO
		piece.node.position.y = ground + 2.5
		piece.rest_y = piece.node.position.y
		piece.landed_at = _clock
		piece.spin = Vector3.ZERO
		var world := World.current
		world.fx.dust(Vector3(at.x, ground + 0.5, at.z), 10, 5.0, Palette.OCHRE)
		world.fx.shockwave(Vector3(at.x, ground, at.z), 14.0, Palette.MIST, 0.4)
		world.shake(0.15, at)
		Sfx.play("impact", at, 2.0, randf_range(0.5, 0.8))


## A flickering water colour: bands run along `along` and scroll with the clock, so a sheet reads as flowing.
func _water_color(colors: Array, across: int, along: int, speed: float) -> Color:
	var band := along - int(floorf(_clock * speed))
	return colors[posmod(across * 2 + (band + across) / 3, colors.size())]


## Replaces `node`'s mesh with the quads in `quads` ([a, b, c, d, color] each, all facing `normal`).
static func _set_quads(node: MeshInstance3D, quads: Array, normal: Vector3) -> void:
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for q: Array in quads:
		points.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
		colors.append_array([q[4], q[4], q[4], q[4], q[4], q[4]])
	var mesh: ArrayMesh = node.mesh
	mesh.clear_surfaces()
	if points.is_empty():
		return
	var normals := PackedVector3Array()
	normals.resize(points.size())
	normals.fill(normal.normalized())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## Where the spilling water is after `t` seconds in the air, at lateral offset `x`.
func _spill_at(t: float, x: float) -> Vector3:
	return Vector3(x, LIP.y - 0.5 * SPILL_GRAVITY * t * t, LIP.z + SPILL_SPEED * t)


func _landing_time() -> float:
	return sqrt(2.0 * (LIP.y - FLOOD_Y) / SPILL_GRAVITY)


## The sheet that falls from the bank through the gap: a ribbon along the spill's arc, its colours
## streaming down, whiter towards the bottom where it turns to foam.
func _update_torrent(flow: float) -> void:
	torrent.visible = true
	var rows := 18
	var columns := 15
	var fall := _landing_time() * flow
	var quads := []
	for j in rows:
		var t0 := fall * j / rows
		var t1 := fall * (j + 1) / rows
		var wide0 := 1.0 + 0.1 * t0
		var wide1 := 1.0 + 0.1 * t1
		for i in columns:
			var f0 := float(i) / columns - 0.5
			var f1 := float(i + 1) / columns - 0.5
			var w := _gap.y - _gap.x - 1.0
			var mid := (_gap.x + _gap.y) * 0.5
			var color := _water_color(SHEET_COLORS, i, j, 9.0)
			if i == 0 or i == columns - 1 or j > rows - 4:
				color = color.lerp(Palette.WHITE, 0.6)
			quads.append([_spill_at(t0, mid + f0 * w * wide0), _spill_at(t0, mid + f1 * w * wide0), _spill_at(t1, mid + f1 * w * wide1), _spill_at(t1, mid + f0 * w * wide1), color])
	_set_quads(torrent, quads, Vector3.UP) # Lit like the flood, so it reads as the same water.


## Water over the floor, from the foot of the wall out towards the middle of the arena. The near
## rows are foam where the sheet lands; the leading row is a white surge.
func _update_flood(spread: float) -> void:
	flood.visible = true
	var start := _spill_at(_landing_time(), 0.0).z
	var reach := flood_reach()
	var half := minf(115.0, 22.0 + reach * 0.85)
	var rows := 10
	var columns := 24
	var mid := (_gap.x + _gap.y) * 0.5
	var quads := []
	for j in rows:
		for i in columns:
			var corners := []
			for corner in [Vector2(i, j), Vector2(i + 1, j), Vector2(i + 1, j + 1), Vector2(i, j + 1)]:
				var f: float = corner.y / rows
				var lateral: float = lerpf(-1.0, 1.0, corner.x / columns)
				# The front is ragged and surges; the sides fan out from the gap as it spreads.
				var front: float = 0.92 + 0.08 * sin(corner.x * 2.3 + _clock * 2.0)
				var z: float = start + reach * f * (1.0 if corner.y < rows else front)
				var x: float = mid + lateral * lerpf(_gap.y - _gap.x, half * 2.0, f * spread) * 0.5
				corners.append(Vector3(x, FLOOD_Y + 0.07 * sin(x * 0.4 + z * 0.3 + _clock * 3.0), z))
			var color := _water_color(FLOOD_COLORS, i, j, 5.0)
			if j == 0 or j == rows - 1:
				color = color.lerp(Palette.WHITE, 0.7)
			elif j == 1:
				color = color.lerp(Palette.WHITE, 0.3)
			quads.append([corners[0], corners[1], corners[2], corners[3], color])
	_set_quads(flood, quads, Vector3.UP)


## Spray and mist at the lip, a plume where the sheet lands and foam at the flood's leading edge.
func _emit_spray(delta: float, flow: float) -> void:
	var fx := World.current.fx
	var basis := global_basis
	var from := _gap.x + 2.0
	var span := _gap.y - _gap.x - 4.0
	var landing := _spill_at(_landing_time(), 0.0).z
	for kind: String in ["lip", "plume", "mist", "foam"]:
		var rate: float = {"lip": 60.0, "plume": 150.0, "mist": 45.0, "foam": 70.0}[kind]
		_rates[kind] = _rates.get(kind, 0.0) + rate * flow * delta
		while _rates[kind] >= 1.0:
			_rates[kind] -= 1.0
			var x := from + randf() * span
			match kind:
				"lip":
					fx.spawn(Fx.Kind.GLOW, to_global(Vector3(x, LIP.y, LIP.z + 1.0)), basis * Vector3(randf_range(-2, 2), randf_range(2, 6), randf_range(5, 10)), randf_range(0.9, 1.4), 1.4, [Palette.WHITE, Palette.SKY][randi() % 2], {"end_size": 4.0, "gravity": 10.0, "fade": 0.3})
				"plume":
					fx.spawn(Fx.Kind.GLOW, to_global(Vector3(x, FLOOD_Y + 0.4, landing + randf_range(-1, 3))), basis * Vector3(randf_range(-5, 5), randf_range(8, 18), randf_range(0, 8)), randf_range(0.9, 1.5), 0.9, [Palette.WHITE, Palette.SKY, Palette.CREAM][randi() % 3], {"end_size": 2.6, "gravity": 16.0, "fade": 0.4})
				"mist":
					fx.spawn(Fx.Kind.GLOW, to_global(Vector3(x, FLOOD_Y + 1.5, landing + randf_range(0, 6))), basis * Vector3(randf_range(-6, 6), randf_range(3, 7), randf_range(2, 9)), randf_range(2.0, 2.8), 2.5, [Palette.MIST, Palette.WHITE][randi() % 2], {"end_size": 7.0, "gravity": -1.0, "drag": 0.8, "fade": 0.4})
				"foam":
					if flood_spread() > 0.0:
						var edge := landing + flood_reach() * 0.95
						var half := minf(115.0, 22.0 + flood_reach() * 0.85)
						fx.spawn(Fx.Kind.GLOW, to_global(Vector3(randf_range(-half, half), FLOOD_Y + 0.3, edge + randf_range(-3, 1))), basis * Vector3(0, randf_range(1, 3), randf_range(2, 6)), randf_range(0.5, 0.9), 0.8, Palette.WHITE, {"end_size": 1.6, "gravity": 4.0, "fade": 0.4})
	_next_rumble -= delta
	if _next_rumble <= 0.0:
		_next_rumble = 1.4
		Sfx.play("launch", to_global(Vector3((_gap.x + _gap.y) * 0.5, 10.0, landing)), 8.0, 0.35)
