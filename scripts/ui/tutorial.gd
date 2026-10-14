class_name Tutorial
extends Control
## A training ground of floating islands, driven freely. It starts with a maze of crushable walls seen from above;
## past it the islands turn left and right, and each station holds the tank until it has used the skill a TV
## beside it demonstrates, so no station lies in another's line of fire.

signal exit
signal start(checkpoint: String)
signal restart

enum Step { COURSE, DONE }
## Wall lines as (u, d) pairs: a box of three lanes by three rows of 12 m cells from d = -470 (open above the left lane) and the dividers that leave only the route.
const WALLS := [
	[Vector2(-18, -470), Vector2(-18, -434)], [Vector2(18, -470), Vector2(18, -434)], [Vector2(-18, -470), Vector2(18, -470)],
	[Vector2(-6, -434), Vector2(18, -434)], [Vector2(-6, -458), Vector2(-6, -434)],
	[Vector2(-6, -458), Vector2(6, -458)], [Vector2(-6, -446), Vector2(18, -446)],
]
## From the middle cell: right, back, left twice along the bottom row, forward twice up the left lane, as (u, d).
const ROUTE := [Vector2(0, -452), Vector2(12, -452), Vector2(12, -464), Vector2(0, -464), Vector2(-12, -464), Vector2(-12, -452), Vector2(-12, -440)]
const MAZE_EXIT_D := -434.0 ## The maze's top wall: the camera leaves the overhead view past it.
const NORTH := Vector2(0, 1) ## Headings, as (u, d).
const EAST := Vector2(1, 0)
const WEST := Vector2(-1, 0)
## The islands, as (u, d) rectangles with the heading the camera looks along on each, in order. Gaps between them
## are drops the tank cannot drive over: past the range (wider than a dash), beside the pillbox's causeway, under
## the drawbridge, and the narrow one a dash crosses.
const ISLANDS := [
	[Rect2(-24, -476, 48, 44), NORTH], ## The maze, with room to drive out through its walls.
	[Rect2(-22, -432, 20, 12), NORTH], ## The range's near side.
	[Rect2(-22, -408, 20, 30), NORTH], ## Its far side, where the targets slide; it turns right.
	[Rect2(-2, -398, 14, 20), EAST], ## Before the pillbox.
	[Rect2(12, -392, 12, 8), EAST], ## The causeway it blocks.
	[Rect2(24, -398, 28, 20), EAST], ## After it; turns left.
	[Rect2(32, -378, 20, 16), NORTH], ## Before the drawbridge.
	[Rect2(32, -350, 20, 10), NORTH], ## After it; turns left.
	[Rect2(30, -340, 22, 9.5), WEST], ## The broken road, ending well before the next corner so "right" is still across.
	[Rect2(4, -325.5, 40, 9.5), WEST], ## The way on, a dash to the right across the break; turns right.
	[Rect2(4, -316, 20, 46), NORTH], ## The turret's run, wide enough to land a sideways dash on.
	[Rect2(4, -270, 20, 28), NORTH], ## The thorns, then the scarecrows' pen.
	[Rect2(4, -232, 20, 14), NORTH], ## The armoury, over the bridge that full armour raises: a crate of micro-missiles.
	[Rect2(4, -206, 20, 12), NORTH], ## The goal, over the bridge the swarm holds up.
]
const BRIDGE := Rect2(-16, -421, 8, 14) ## Rises over the range's gap once every target is down.
const DRAWBRIDGE := Rect2(38, -363, 8, 14) ## Comes down once the drone is.
## The way through the islands past the maze, as (u, d) points; the chase camera looks along it, CAMERA_LEAD on.
const PATH := [Vector2(-12, -440), Vector2(-12, -388), Vector2(42, -388), Vector2(42, -335), Vector2(14, -335), Vector2(14, -185)]
const CAMERA_LEAD := 14.0
const TARGET_D := -398.0
const TARGET_TRACK := Vector2(-19, -5) ## u from, to.
const PILLBOX := Vector2(16, -388) ## At the mouth of the causeway, which is no ground while it stands.
const DRONE := Vector3(58, 6, -356) ## (u, height, d) the drone jinks around: off the drawbridge's right, low.
const TURRET := Vector2(14, -180) ## On its own island past the goal, firing down the run.
const TURRET_RUN := Vector2(-316, -270) ## d from, to: the turret fires while the tank is in here.
const SHOT_SPEED := 16.0 ## The paint walls the turret pushes down its run, as wide as the run: no stepping aside.
const SHOT_EVERY := 2.4
const SHOT_HIT := 1.8 ## How near the hull's centre, along the run, a wall splashes it unless a dash has it untouchable.
const THORNS := Rect2(4, -266, 20, 5) ## Across the way: crossing them costs THORN_DAMAGE armour.
const THORN_DAMAGE := 30.0
const PEN := Rect2(6, -259, 16, 13) ## Where the unarmed scarecrows wander; a melee kill heals, a shot does not.
const SCARECROWS := 5 ## Kept wandering while the armour is short of full.
const HEAL_BRIDGE := Rect2(10, -243, 8, 12) ## Rises once the armour is full again.
const SWARM := Vector3(14, 7, -212) ## (u, height, d): four drones circling over the last gap, as many as a micro salvo locks.
const SWARM_RADIUS := 5.0
const REGROUP := 2.5 ## Seconds before a drone shot down alone takes its place again: only a salvo clears them.
const SWARM_BRIDGE := Rect2(10, -219, 8, 14) ## Rises once the swarm is down.
const CRATE := Vector2(8, -224)
const FINISH_D := -202.0
const TV_SCALE := 2.4 ## So a TV reads from the chase view.
const RESPAWN := 0.7 ## Seconds before a broken TV rises again.
const COURSE_CENTER_D := -360.0
const WALL_LENGTH := 6.0 ## The scenery wall's mesh.
const GAMEPAD_GLYPHS := {&"fire": "RT", &"coax": "X", &"move_forward": "↑", &"move_back": "↓", &"move_left": "←", &"move_right": "→", &"dash": "LB RB", &"restart": "BACK"}
const SKILL_ACTIONS := {"move": [&"move_forward"], "fire": [&"fire", &"coax"], "charge": [&"fire"], "lock": [&"fire"], "drift": [&"dash"], "dodge": [&"dash"], "heal": [&"move_forward", &"dash"], "armor": [], "micro": [&"fire"]}

## A fixed top-down view over the maze; past it, the game's chase view behind the tank, looking along the way
## through the islands and turning ahead of each corner (see heading_at).
class CourseCamera extends ChaseCamera:
	var heading := NORTH
	var _stand := Vector3.INF ## Where the player last stood: a fall is watched from there.

	func follow(delta: float) -> void:
		var player := World.current.player
		if not player:
			return
		var falling := player.is_falling() and _stand != Vector3.INF
		if not falling:
			_stand = player.global_position
		var at := _stand
		var c := Course.to_course(at)
		var eye := at + Vector3(0, 30, 26)
		var look := at + Vector3(0, 0, -10)
		var k := 1.0 - exp(-5.0 * delta) if _initialized else 1.0
		if c.x > MAZE_EXIT_D:
			heading = heading.slerp(Tutorial.heading_at(Vector2(c.y, c.x)), k).normalized()
			var spot := Vector2(c.y, c.x)
			var back := spot - heading * RAIL_BACK
			eye = Course.to_world(back.y, back.x, at.y + RAIL_HEIGHT)
			var ahead := spot + heading * RAIL_LOOK_AHEAD
			look = player.global_position if falling else Course.to_world(ahead.y, ahead.x, at.y - 1.0)
		_eye = _eye.lerp(eye, k)
		_look = _look.lerp(look, k)
		_initialized = true
		global_position = _eye
		look_at(_look, Vector3.UP)
		_apply_shake(delta)

class Sight extends Hud:
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		font = get_theme_default_font()

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		_draw_reticle()

static var _open := 0 ## Tutorials in the tree: the course stays flat while any is (a restart overlaps two).
var view := DitherView.new()
var world := World.new()
var tank := Tank.new()
var maze := Scenery.new()
var trees := Scenery.new()
var step := Step.COURSE
var targets: Array[Training.Target] = []
var pillbox: Training.Pillbox
var drone: Training.Drone
var turret: Training.Turret
var bridge_up := false
var heal_bridge_up := false
var swarm_bridge_up := false
var swarm: Array = [] ## The swarm's drones by slot; a slot is null while its drone waits to regroup.
var _swarm_bridge: MeshInstance3D
var _heal_bridge: MeshInstance3D
var _scarecrows: Array = []
var _scarecrow_wait := 0.0
var _in_thorns := false
var _hurt := false ## The thorns have cost armour: full armour now raises the bridge.
var drawbridge_down := false
var _bridge: MeshInstance3D
var _leaves: Array[Node3D] = [] ## The drawbridge: a leaf hinged on each side of the gap, raised.
## Teaching props, as {at (u, d), heading, kind ("tv" or "slab"), skill (a TV's demo) or actions (painted on a
## slab)}, plus the prop, face and screen built for it now.
var _signs: Array[Dictionary] = []
var _shots: Array[MeshInstance3D] = [] ## The turret's paint walls on their way down the run.
var _turret_clock := 0.0
var _course_objects := Node3D.new()
var _clouds := Node3D.new()
var _streaks: Array = [] ## [mesh, fall height] of every waterfall's running streak.
var _rocks := Node3D.new()
var _paint: Array[Node3D] = []
var _overlay: Menu
var _play := Button.new()
var _replay := Button.new()
var _restart_button := Button.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	# No valley, as in the debug room: the islands float over nothing.
	_open += 1
	Course.flat = true
	add_child(view)
	world.view = view
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.rail.mode = Rail.Mode.ARENA
	world.rail.d = COURSE_CENTER_D
	world.rail.speed = 0
	world.rail.arena_d = COURSE_CENTER_D
	world.rail.arena_radius = 1000.0
	world.camera.free()
	world.camera = CourseCamera.new()
	view.viewport.add_child(world)
	world.terrain.visible = false
	# The sky goes on below the islands.
	var sky := world.environment.sky.sky_material as ProceduralSkyMaterial
	sky.ground_horizon_color = sky.sky_horizon_color
	sky.ground_bottom_color = sky.sky_top_color
	tank.invulnerable = true
	world.player = tank
	world.add_child(tank)
	world.add_child(maze)
	world.add_child(trees)
	world.add_child(_course_objects)
	world.add_child(_clouds)
	world.add_child(_rocks)
	tank._set_pose(Course.ground_at(ROUTE[0].y, ROUTE[0].x), Course.yaw_at(ROUTE[0].y))
	tank._last_position = tank.global_position
	_build_maze()
	_build_stations()
	_build_sky()
	var sight := Sight.new()
	sight.world = world
	add_child(sight)
	_button(_replay, Rect2(192, 484, 260, 42), _restart)
	_button(_restart_button, Rect2(12, 12, 230, 36), _restart)
	_restart_button.focus_mode = Control.FOCUS_NONE # Space dashes; a focused button would restart on it.
	_button(_play, Rect2(472, 484, 296, 42), _start_game)
	world.camera.follow(0)
	_refresh_buttons()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _exit_tree() -> void:
	_open -= 1
	Course.flat = _open > 0


func _button(button: Button, rect: Rect2, action: Callable) -> void:
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(action)
	add_child(button)


## The ground under a (u, d) point.
func _ground(point: Vector2) -> Vector3:
	return Course.ground_at(point.y, point.x)


## Where the way heads from the point on PATH nearest the (u, d) point `at` to CAMERA_LEAD metres further on: down
## a straight, and swinging round as a corner comes near.
static func heading_at(at: Vector2) -> Vector2:
	var nearest := INF
	var along := 0.0
	var walked := 0.0
	for i in PATH.size() - 1:
		var a: Vector2 = PATH[i]
		var b: Vector2 = PATH[i + 1]
		var length := a.distance_to(b)
		var t := clampf((at - a).dot(b - a) / (length * length), 0.0, 1.0)
		var distance := at.distance_to(a.lerp(b, t))
		if distance < nearest:
			nearest = distance
			along = walked + t * length
		walked += length
	var from := _path_point(along)
	var to := _path_point(along + CAMERA_LEAD)
	return (to - from).normalized() if not to.is_equal_approx(from) else (PATH[-1] - PATH[-2]).normalized()


## The point `along` metres down PATH, held at its ends.
static func _path_point(along: float) -> Vector2:
	for i in PATH.size() - 1:
		var length: float = PATH[i].distance_to(PATH[i + 1])
		if along <= length:
			return PATH[i].lerp(PATH[i + 1], maxf(along, 0.0) / length)
		along -= length
	return PATH[-1]


## Crushable scenery walls along every wall line.
func _build_maze() -> void:
	var pieces := 0
	for line: Array in WALLS:
		var from: Vector2 = line[0]
		var length := from.distance_to(line[1])
		var count := ceili(length / WALL_LENGTH)
		for k in count:
			var at := from.lerp(line[1], (k + 0.5) / count)
			maze.add("wall", at.y, at.x, PI * 0.5 if from.x == line[1].x else 0.0, pieces)
			pieces += 1
	maze.specs.sort_custom(func(a: Scenery.Spec, b: Scenery.Spec) -> bool: return a.d < b.d)
	# Scenery streams the walls behind its anchor away, so anchor the stream at the maze's first wall.
	maze.stream(maze.specs[0].d + Scenery.BEHIND, 100000)
	# Trees on the islands' corners, off the way: they break like everything else.
	for tree: Vector2 in [Vector2(-22, -474), Vector2(22, -474), Vector2(22, -436), Vector2(-20, -381), Vector2(49, -381), Vector2(49, -341), Vector2(21, -264), Vector2(7, -264)]:
		trees.add("persimmon", tree.y, tree.x, INF, pieces)
		pieces += 1
	trees.specs.sort_custom(func(a: Scenery.Spec, b: Scenery.Spec) -> bool: return a.d < b.d)
	trees.stream(trees.specs[0].d + Scenery.BEHIND, 100000)


## Everything past the maze: the islands and their crossings, the range's targets, the pillbox, the drone, the
## broken road and the turret, each with a TV demonstrating what it asks.
func _build_stations() -> void:
	for island: Array in ISLANDS:
		_island(island[0], Palette.CONCRETE if island[0] == ISLANDS[4][0] else Palette.LEAF)
	_bridge = _box(BRIDGE, 0.4, Palette.WOOD)
	_bridge.position.y -= 8.0
	for side in [-1.0, 1.0]:
		var leaf := Node3D.new()
		_course_objects.add_child(leaf)
		var hinge := DRAWBRIDGE.position.y + 1.0 if side < 0.0 else DRAWBRIDGE.end.y - 1.0
		leaf.global_transform = _frame(Vector2(DRAWBRIDGE.get_center().x, hinge), NORTH if side < 0.0 else -NORTH)
		var deck := MeshInstance3D.new()
		deck.mesh = LowPoly.new().box(Transform3D(Basis(), Vector3(0, 0.15, -DRAWBRIDGE.size.y * 0.25 + 0.5)), Vector3(DRAWBRIDGE.size.x, 0.3, DRAWBRIDGE.size.y * 0.5 - 1), Palette.WOOD).mesh()
		leaf.add_child(deck)
		leaf.rotate_object_local(Vector3.RIGHT, 1.1) # Raised.
		_leaves.append(leaf)
	for i in 4:
		var target := Training.Target.new()
		target.steel = i % 2 == 1
		target.d = TARGET_D
		target.track = TARGET_TRACK
		target.period = 3.2 + i * 0.7
		target.phase = i * 1.7
		target.died.connect(_on_target_down)
		targets.append(target)
		world.add_enemy(target)
	pillbox = Training.Pillbox.new()
	pillbox.transform = _frame(PILLBOX, -EAST) # Gun slit toward the tank.
	pillbox.died.connect(func(_pillbox: Entity) -> void: _update_land())
	world.add_enemy(pillbox)
	drone = Training.Drone.new()
	drone.center = Course.ground_at(DRONE.z, DRONE.x) + Vector3.UP * DRONE.y
	drone.died.connect(func(_drone: Entity) -> void: _lower_drawbridge())
	world.add_enemy(drone)
	turret = Training.Turret.new()
	turret.transform = _frame(TURRET, -NORTH)
	world.props.add_child(turret)
	_island(Rect2(TURRET - Vector2(4, 4), Vector2(8, 8)), Palette.CONCRETE)
	_teacher({"at": Vector2(8, -446), "heading": NORTH, "kind": "tv", "skill": "move", "tilt": 0.6})
	_teacher({"at": Vector2(8, -428), "heading": NORTH, "kind": "tv", "skill": "fire"})
	_teacher({"at": Vector2(6, -408), "heading": EAST, "kind": "tv", "skill": "charge"})
	_teacher({"at": Vector2(22, -372), "heading": NORTH, "kind": "tv", "skill": "lock"})
	_teacher({"at": Vector2(30, -348), "heading": WEST, "kind": "tv", "skill": "drift"})
	_teacher({"at": Vector2(30, -300), "heading": NORTH, "kind": "tv", "skill": "dodge"})
	_teacher({"at": Vector2(31, -256), "heading": NORTH, "kind": "tv", "skill": "heal"})
	_teacher({"at": Vector2(-3, -246), "heading": NORTH, "kind": "tv", "skill": "armor"})
	_heal_bridge = _box(HEAL_BRIDGE, 0.4, Palette.WOOD)
	_heal_bridge.position.y -= 8.0
	_swarm_bridge = _box(SWARM_BRIDGE, 0.4, Palette.WOOD)
	_swarm_bridge.position.y -= 8.0
	_teacher({"at": Vector2(31, -224), "heading": NORTH, "kind": "tv", "skill": "micro"})
	for slot in 4:
		swarm.append(null)
		_regroup(slot)
	_thorns()
	# The break: road slabs fallen into the gap, the dash binding still painted on one.
	for k in 3:
		var slab := MeshInstance3D.new()
		slab.mesh = LowPoly.new().box(Transform3D(), Vector3(5.0, 0.6, 4.4), Palette.CONCRETE, Palette.LEAF).mesh()
		_course_objects.add_child(slab)
		slab.global_transform = _frame(Vector2(36 - k * 5, -328), WEST) * Transform3D(Basis(Vector3.FORWARD, 0.35 * (1 if k % 2 == 0 else -1)) * Basis(Vector3.RIGHT, 0.3), Vector3(0, -1.6 - k * 0.6, 0))
		if k == 1:
			var face := Node3D.new()
			slab.add_child(face)
			face.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.32, 0))
			_signs.append({"kind": "slab", "face": face, "actions": [&"dash"]})
	_update_land()
	_refresh_paint()


## A transform on the ground at a (u, d) point facing along `heading`: -z ahead, +z back toward the camera.
func _frame(at: Vector2, heading := NORTH) -> Transform3D:
	return Transform3D(Basis.looking_at(Course.to_world(at.y + heading.y, at.x + heading.x) - Course.to_world(at.y, at.x)), _ground(at))


## A box over a (u, d) rectangle, its top `height` above the ground at its centre.
func _box(area: Rect2, height: float, color: Color, top := Color(0, 0, 0, 0)) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = LowPoly.new().box(Transform3D(Basis(), Vector3(0, height * 0.5, 0)), Vector3(area.size.x, height, area.size.y), color, top).mesh()
	_course_objects.add_child(mesh)
	mesh.global_transform = _frame(area.get_center())
	return mesh


## An island: a grass top with chamfered corners and a sunlit earth rim, over an underside that narrows in two
## jittered rings of pastel crystal facets to a point far below, with a few smaller crystals hanging beside it.
func _island(area: Rect2, top: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(area)
	var b := LowPoly.new()
	b.vivid = true
	var half := area.size * 0.5 + Vector2(0.6, 0.6)
	var cut := minf(half.x, half.y) * 0.45
	var outline: Array[Vector2] = [Vector2(-half.x + cut, -half.y), Vector2(half.x - cut, -half.y), Vector2(half.x, -half.y + cut), Vector2(half.x, half.y - cut), Vector2(half.x - cut, half.y), Vector2(-half.x + cut, half.y), Vector2(-half.x, half.y - cut), Vector2(-half.x, -half.y + cut)]
	var rim := 0.9
	for i in outline.size():
		var p: Vector2 = outline[i]
		var q: Vector2 = outline[(i + 1) % outline.size()]
		b.tri(Vector3(0, 0.05, 0), Vector3(p.x, 0.05, p.y), Vector3(q.x, 0.05, q.y), top, Vector3.UP)
		b.quad(Vector3(p.x, 0.05, p.y), Vector3(q.x, 0.05, q.y), Vector3(q.x, -rim, q.y), Vector3(p.x, -rim, p.y), Palette.STRAW if i % 2 == 0 else Palette.OCHRE, Vector3(p.x + q.x, 0, p.y + q.y))
	var reach := maxf(area.size.x, area.size.y)
	var depth := reach * rng.randf_range(0.55, 0.8) + 4.0
	var apex := Vector3(rng.randf_range(-0.15, 0.15) * half.x, -rim - depth, rng.randf_range(-0.15, 0.15) * half.y)
	var ring: Array[Vector3] = []
	for p: Vector2 in outline:
		ring.append(Vector3(p.x * rng.randf_range(0.55, 0.7), -rim - depth * rng.randf_range(0.28, 0.4), p.y * rng.randf_range(0.55, 0.7)))
	var facets := [Palette.LILAC, Palette.PERIWINKLE, Palette.MAUVE, Palette.LILAC, Palette.DUSK]
	for i in outline.size():
		var j := (i + 1) % outline.size()
		var p0 := Vector3(outline[i].x, -rim, outline[i].y)
		var p1 := Vector3(outline[j].x, -rim, outline[j].y)
		var out := Vector3(outline[i].x + outline[j].x, 0, outline[i].y + outline[j].y)
		b.quad(p0, p1, ring[j], ring[i], facets[i % facets.size()], out)
		b.tri(ring[i], ring[j], apex, facets[(i + 2) % facets.size()], out)
	for k in rng.randi_range(2, 4):
		var at: Vector3 = ring[rng.randi_range(0, ring.size() - 1)] * rng.randf_range(0.7, 0.95)
		var r := reach * rng.randf_range(0.06, 0.12)
		b.prism(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), at - Vector3.UP * r * 3.0), 0.05, r * 3.0, 4, facets[k % facets.size()], r)
	var mesh := MeshInstance3D.new()
	mesh.mesh = b.mesh()
	_course_objects.add_child(mesh)
	mesh.global_transform = _frame(area.get_center())


## A waterfall pouring off the edge at (u, d) `at`, falling away along `out`: a stream across the grass, a sheet of
## water with white streaks running down it (animated in _process), and spray billowing where it fades.
func _waterfall(at: Vector2, out: Vector2, height := 60.0, width := 4.0) -> void:
	var fall := Node3D.new()
	_course_objects.add_child(fall)
	fall.global_transform = _frame(at, -out) # +z points out over the drop.
	var b := LowPoly.new()
	b.vivid = true
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(0, 0.08, -3.0)), Vector3(width * 0.7, 0.1, 6.0), Palette.TEAL)
	b.box(Transform3D(Basis(Vector3.RIGHT, -0.25), Vector3(0, -0.4, 0.4)), Vector3(width, 1.2, 0.5), Palette.CREAM)
	b.box(Transform3D(Basis(), Vector3(0, -height * 0.5, 0.9)), Vector3(width, height, 0.4), Palette.SKY)
	var sheet := MeshInstance3D.new()
	sheet.mesh = b.mesh()
	fall.add_child(sheet)
	for k in 7:
		var streak := MeshInstance3D.new()
		var s := LowPoly.new()
		s.glow = true
		s.box(Transform3D(), Vector3(randf_range(0.2, 0.6), randf_range(3.0, 7.0), 0.1), Palette.WHITE)
		streak.mesh = s.mesh()
		fall.add_child(streak)
		streak.position = Vector3(randf_range(-0.42, 0.42) * width, -randf() * height, 1.15)
		_streaks.append([streak, height])
	var spray := LowPoly.new()
	spray.vivid = true
	for p in 6:
		spray.blob(Transform3D(Basis(), Vector3(randf_range(-1.5, 1.5) * width, -height + randf_range(-2, 4), randf_range(0.5, 4.0))), randf_range(2.5, 5.0), Palette.WHITE, 1, 0.25, p)
	var mist := MeshInstance3D.new()
	mist.mesh = spray.mesh()
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fall.add_child(mist)


## The sky around the course: a sea of cloud far below, banks of cumulus drifting between the islands' undersides,
## waterfalls off the islands, distant islands of their own, and loose rocks floating beside the way.
func _build_sky() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for c in 70:
		var low := c < 40
		var at := Vector2(rng.randf_range(-160, 200), rng.randf_range(-640, -120)) if low else Vector2(rng.randf_range(-60, 100), rng.randf_range(-500, -230))
		_cloud(at, rng.randf_range(-62, -50) if low else rng.randf_range(-34, -16), rng.randf_range(1.4, 2.4) if low else rng.randf_range(0.7, 1.2), rng)
	for fall: Array in [[Vector2(-24.4, -455), WEST, 70.0], [Vector2(-22.4, -394), WEST, 60.0], [Vector2(36, -398.4), -NORTH, 55.0], [Vector2(52.4, -372), EAST, 65.0], [Vector2(24.4, -262), EAST, 60.0]]:
		_waterfall(fall[0], fall[1], fall[2])
	for far: Array in [[Rect2(-140, -470, 50, 36), 10.0], [Rect2(-120, -330, 34, 28), -8.0], [Rect2(110, -440, 44, 40), 4.0], [Rect2(130, -300, 60, 34), 16.0], [Rect2(-40, -200, 40, 26), 24.0]]:
		var island_rect: Rect2 = far[0]
		var before := _course_objects.get_child_count()
		_island(island_rect, Palette.LEAF)
		_waterfall(Vector2(island_rect.end.x + 0.4, island_rect.get_center().y), EAST, 70.0, 6.0)
		for child in _course_objects.get_children().slice(before):
			(child as Node3D).position.y += far[1]
	for k in 12:
		var rock := MeshInstance3D.new()
		var b := LowPoly.new()
		b.vivid = true
		var r := rng.randf_range(0.8, 2.6)
		b.blob(Transform3D(), r, Palette.STONE, 0, 0.45, k)
		b.box(Transform3D(Basis(), Vector3(0, r * 0.75, 0)), Vector3(r * 1.3, 0.3, r * 1.3), Palette.LEAF)
		rock.mesh = b.mesh()
		_rocks.add_child(rock)
		var at := Vector2(rng.randf_range(-50, 90), rng.randf_range(-490, -240))
		if at.x > -30.0 and at.x < 62.0:
			at.x += 95.0 * signf(at.x - 16.0)
		rock.global_position = _ground(at) + Vector3.UP * rng.randf_range(-8, 10)


## A cumulus in two toon tones: smooth lobes heaped on a flat base, white above and periwinkle beneath, unlit so
## they read as clean shapes against the sky. `scale` times a modest one.
func _cloud(at: Vector2, height: float, scale: float, rng: RandomNumberGenerator) -> void:
	var b := LowPoly.new()
	b.vivid = true
	b.glow = true
	var lobes := rng.randi_range(4, 7)
	for p in lobes:
		var x := (p - (lobes - 1) * 0.5) * 3.2 + rng.randf_range(-1.0, 1.0)
		var r := rng.randf_range(2.6, 4.2) * (1.15 - absf(x) / 16.0)
		var z := rng.randf_range(-1.5, 1.5)
		b.blob(Transform3D(Basis(), Vector3(x, r * 0.55, z)), r, Palette.WHITE, 1)
		b.blob(Transform3D(Basis(), Vector3(x, r * 0.15, z)), r * 0.95, Palette.PERIWINKLE.lerp(Palette.WHITE, 0.35), 1)
	b.prism(Transform3D(), (lobes * 1.6 + 2.0), 0.3, 10, Palette.PERIWINKLE.lerp(Palette.WHITE, 0.2))
	var cloud := MeshInstance3D.new()
	cloud.mesh = b.mesh()
	cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_clouds.add_child(cloud)
	cloud.global_position = _ground(at) + Vector3.UP * height
	cloud.rotation.y = rng.randf() * TAU
	cloud.scale = Vector3(1.0, 0.75, 0.8) * scale


## The ground the tank may drive on: the islands, and the bridges once they are down.
func _update_land() -> void:
	var land: Array[Rect2] = []
	for island: Array in ISLANDS:
		if island[0] != ISLANDS[4][0] or not is_instance_valid(pillbox) or pillbox.dead: # Freed a while after it breaks.
			land.append(island[0])
	if bridge_up:
		land.append(BRIDGE)
	if drawbridge_down:
		land.append(DRAWBRIDGE)
	if heal_bridge_up:
		land.append(HEAL_BRIDGE)
	if swarm_bridge_up:
		land.append(SWARM_BRIDGE)
	world.rail.arena_land = land


func _on_target_down(_target: Entity) -> void:
	if bridge_up or targets.any(func(target: Variant) -> bool: return is_instance_valid(target) and not target.dead):
		return
	bridge_up = true
	_update_land()
	create_tween().tween_property(_bridge, "position:y", _bridge.position.y + 8.0, 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _lower_drawbridge() -> void:
	drawbridge_down = true
	_update_land()
	for leaf in _leaves:
		create_tween().tween_property(leaf, "transform:basis", leaf.basis.rotated(leaf.basis.x.normalized(), -1.1), 1.0).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _teacher(entry: Dictionary) -> Dictionary:
	_signs.append(entry)
	_make(entry)
	return entry


## Builds `entry`'s TV on its own small island: a post and a screen looping `skill`'s demonstration (see
## Training.Screen), tilted back by `tilt` toward the camera. Broken, it comes back (_respawn).
func _make(entry: Dictionary) -> void:
	var board := Transform3D(Basis(Vector3.RIGHT, -entry.get("tilt", 0.2)), Vector3(0, 3.6, 0))
	var b := LowPoly.new()
	b.box(Transform3D(Basis(), Vector3(0, 1.4, 0)), Vector3(0.3, 2.8, 0.3), Palette.SLATE)
	b.box(board, Vector3(5.2, 3.4, 0.6), Palette.INK)
	var prop := Prop.new().setup("tv", b.mesh(), 1.6, 4.0, 5.0)
	prop.transform = _frame(entry.at, entry.heading).scaled_local(Vector3.ONE * TV_SCALE)
	world.props.add_child(prop)
	if not entry.has("pad"):
		entry.pad = true
		_island(Rect2(entry.at - Vector2(7, 3), Vector2(14, 6)), Palette.LEAF)
	var face := Node3D.new()
	prop.add_child(face)
	face.transform = Transform3D(board.basis, board.origin + board.basis.z * 0.31)
	var screen := Training.Screen.new()
	screen.skill = entry.skill
	screen.source = tank
	prop.add_child(screen)
	var quad := MeshInstance3D.new()
	var shape := QuadMesh.new()
	shape.size = Vector2(4.6, 2.9)
	quad.mesh = shape
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = screen.get_texture()
	quad.material_override = material
	face.add_child(quad)
	entry.prop = prop
	entry.face = face
	entry.screen = screen
	prop.died.connect(_respawn.bind(entry).unbind(1))


## Rebuilds a broken TV after RESPAWN, rising out of its island, and repaints the bindings.
func _respawn(entry: Dictionary) -> void:
	await get_tree().create_timer(RESPAWN, false).timeout
	if not is_instance_valid(world) or world.process_mode == Node.PROCESS_MODE_DISABLED:
		return
	_make(entry)
	var prop: Prop = entry.prop
	var rest := prop.position.y
	prop.position.y -= prop.height * TV_SCALE
	create_tween().tween_property(prop, "position:y", rest, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh_paint()


func _floor_text(at: Vector2, text: String, yaw := 0.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = get_theme_default_font()
	label.font_size = 160
	label.pixel_size = 0.025
	label.modulate = Palette.BUTTER
	label.outline_size = 0
	label.shaded = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_course_objects.add_child(label)
	label.global_position = _ground(at) + Vector3.UP * 0.35
	label.global_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI / 2)
	_paint.append(label)


func _binding(action: StringName) -> String:
	if not tank.using_gamepad:
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				return OS.get_keycode_string(event.physical_keycode if event.physical_keycode else event.keycode)
			if event is InputEventMouseButton:
				return "M%d" % (event.button_index - 4 if event.button_index in [8, 9] else event.button_index)
	return GAMEPAD_GLYPHS.get(action, "")


## The maze's route as the movement key to press at each leg's start and arrows along it, and every TV's and
## slab's bindings.
func _refresh_paint() -> void:
	for paint in _paint:
		if is_instance_valid(paint):
			paint.queue_free()
	_paint.clear()
	for i in ROUTE.size() - 1:
		var from: Vector2 = ROUTE[i]
		var direction: Vector2 = (ROUTE[i + 1] - from).normalized()
		var action: StringName = &"move_forward" if direction.y > 0 else &"move_back" if direction.y < 0 else &"move_right" if direction.x > 0 else &"move_left"
		var length := from.distance_to(ROUTE[i + 1])
		_floor_text(from + direction * minf(4.0, length * 0.4), _binding(action))
		for distance in [8.0, 16.0, 24.0]:
			if distance < length - 3.0:
				_floor_text(from + direction * distance, "↑", atan2(-direction.x, direction.y))
	for entry in _signs:
		if entry.has("screen") and is_instance_valid(entry.screen):
			var keys := []
			for i in SKILL_ACTIONS[entry.skill].size():
				for glyph: Dictionary in _glyphs(SKILL_ACTIONS[entry.skill][i]):
					keys.append(glyph.merged({"action": i}))
			entry.screen.glyphs = keys
		if entry.has("actions") and is_instance_valid(entry.face):
			for child in entry.face.get_children():
				child.free()
			_paint_glyphs(entry.face, entry.actions)


## The bindings of `actions` side by side on `face` (its xy plane, +z out), ink on the sign: key names as text,
## mouse buttons as a mouse with the bound button filled.
func _paint_glyphs(face: Node3D, actions: Array) -> void:
	var glyphs := []
	for action: StringName in actions:
		glyphs.append_array(_glyphs(action))
	for i in glyphs.size():
		var x := (i - (glyphs.size() - 1) * 0.5) * 2.2
		var glyph: Dictionary = glyphs[i]
		if glyph.has("text"):
			var label := Label3D.new()
			label.text = glyph.text
			label.font = get_theme_default_font()
			label.font_size = 160
			label.pixel_size = 0.006 if glyph.text.length() > 2 else 0.009
			label.modulate = Palette.INK
			label.outline_size = 0
			label.shaded = false
			face.add_child(label)
			label.position = Vector3(x, 0, 0.02)
		for rectangle: Rect2 in glyph.get("rects", []):
			var mesh := MeshInstance3D.new()
			mesh.mesh = LowPoly.new().box(Transform3D(), Vector3(rectangle.size.x, rectangle.size.y, 0.04) * 0.28, Palette.INK).mesh()
			face.add_child(mesh)
			mesh.position = Vector3(x + rectangle.get_center().x * 0.28, rectangle.get_center().y * 0.28 - 0.1, 0.02)


## What a sign shows for `action`: {text} per key, {rects} per mouse button, or the controller's glyph.
func _glyphs(action: StringName) -> Array:
	if tank.using_gamepad:
		return [{"text": GAMEPAD_GLYPHS.get(action, "")}]
	var result := []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			result.append({"text": OS.get_keycode_string(event.physical_keycode if event.physical_keycode else event.keycode)})
		elif event is InputEventMouseButton:
			result.append({"rects": _mouse(event.button_index)})
	return result


## A mouse outline (y up) with `button` filled.
static func _mouse(button: MouseButton) -> Array[Rect2]:
	var pressed := Rect2(-1.8 if button == MOUSE_BUTTON_LEFT else 0.2, 0.3, 1.6, 2.4) if button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] else Rect2(-3.2, 0.4 if button == MOUSE_BUTTON_XBUTTON1 else -1.2, 0.8, 1.2) if button in [MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2] else Rect2(-0.3, 1, 0.6, 1)
	return [Rect2(-2, -3, 4, 0.22), Rect2(-2, 3, 4, 0.22), Rect2(-2, -3, 0.22, 6), Rect2(2, -3, 0.22, 6.22), Rect2(-0.11, 0, 0.22, 3), Rect2(-2, 0, 4, 0.22), pressed]


func _process(delta: float) -> void:
	if get_tree().paused:
		return
	var t := Time.get_ticks_msec() / 1000.0
	_clouds.position = Vector3(sin(t * 0.05) * 10.0, 0, cos(t * 0.04) * 6.0)
	_rocks.position.y = sin(t * 0.6) * 0.8
	for streak: Array in _streaks:
		var mesh: MeshInstance3D = streak[0]
		mesh.position.y = -fposmod(-mesh.position.y + delta * 14.0, streak[1])
	var at := Course.to_course(tank.global_position)
	if step == Step.COURSE and at.x >= FINISH_D:
		_finish()
	_run_turret(delta, Vector2(at.y, at.x))
	_run_heal(delta, Vector2(at.y, at.x))
	_run_armoury(Vector2(at.y, at.x))


## The paint turret: while the tank is on its run it pushes a wall of paint the run's full width down it. A wall
## that reaches the hull splashes it back to the run's start, unless a dash has it untouchable (Tank.invuln) as
## the wall goes through; past the hull it is harmless.
func _run_turret(delta: float, at: Vector2) -> void:
	var armed := step == Step.COURSE and at.y > TURRET_RUN.x and at.y < TURRET_RUN.y
	_turret_clock = _turret_clock + delta if armed else 0.0
	turret.warn(_turret_clock > SHOT_EVERY - 0.6)
	if _turret_clock >= SHOT_EVERY:
		_turret_clock = 0.0
		var b := LowPoly.new()
		b.glow = true
		var run: Rect2 = ISLANDS[10][0]
		b.box(Transform3D(Basis(), Vector3(0, 1.3, 0)), Vector3(run.size.x + 1.0, 2.6, 0.8), Palette.HOT)
		b.box(Transform3D(Basis(), Vector3(0, 2.75, 0)), Vector3(run.size.x + 1.0, 0.3, 1.0), Palette.BLUSH)
		var wall := MeshInstance3D.new()
		wall.mesh = b.mesh()
		_course_objects.add_child(wall)
		wall.global_transform = _frame(Vector2(run.get_center().x, TURRET.y - 4.0))
		_shots.append(wall)
	for wall in _shots.duplicate():
		var d := Course.to_course(wall.global_position).x - SHOT_SPEED * delta
		wall.global_transform = _frame(Vector2((ISLANDS[10][0] as Rect2).get_center().x, d))
		if d < TURRET_RUN.x - 4.0:
			_shots.erase(wall)
			wall.queue_free()
		elif d < at.y - SHOT_HIT:
			wall.set_meta("past", true)
		elif not wall.has_meta("past") and at.y < TURRET_RUN.y and absf(d - at.y) < SHOT_HIT and tank.invuln <= 0.0:
			_shots.erase(wall)
			wall.queue_free()
			_splash()


## Bramble across the way: dark thorns with red tips, too dense to see a path through.
func _thorns() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var b := LowPoly.new()
	b.vivid = true
	for k in 70:
		var at := Vector3(rng.randf_range(-0.5, 0.5) * THORNS.size.x, 0, rng.randf_range(-0.5, 0.5) * THORNS.size.y)
		var tall := rng.randf_range(0.8, 2.0)
		var lean := Basis(Vector3.FORWARD, rng.randf_range(-0.5, 0.5)) * Basis(Vector3.RIGHT, rng.randf_range(-0.5, 0.5))
		b.prism(Transform3D(lean, at), 0.18, tall, 4, Palette.MOSS if k % 3 else Palette.INK, 0.0)
		b.prism(Transform3D(lean, at + lean.y * tall * 0.7), 0.07, tall * 0.3, 4, Palette.RED, 0.0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = b.mesh()
	_course_objects.add_child(mesh)
	mesh.global_transform = _frame(THORNS.get_center())


## The heal station: thorns cost armour as the hull pushes in; unarmed scarecrows wander the pen, and a melee kill
## (a ram or a dash lash) sends their salvage back as armour (World._release_nanites). Full armour raises the bridge.
func _run_heal(delta: float, at: Vector2) -> void:
	var in_thorns := THORNS.has_point(at)
	if in_thorns and not _in_thorns and step == Step.COURSE:
		tank.hp = maxf(tank.hp - THORN_DAMAGE, 1.0)
		_hurt = true
		tank.flash()
		world.fx.sparks(tank.hit_center(), Vector3.UP, 14, Palette.RED, 10.0)
		world.shake(0.3)
	_in_thorns = in_thorns
	_scarecrows = _scarecrows.filter(func(scarecrow: Variant) -> bool: return is_instance_valid(scarecrow) and not scarecrow.dead)
	_scarecrow_wait -= delta
	if _hurt and tank.hp < tank.max_hp and _scarecrows.size() < SCARECROWS and _scarecrow_wait <= 0.0:
		_scarecrow_wait = 0.8
		var scarecrow := Training.Scarecrow.new()
		scarecrow.pen = PEN
		world.add_enemy(scarecrow)
		_scarecrows.append(scarecrow)
	if _hurt and not heal_bridge_up and tank.hp >= tank.max_hp:
		heal_bridge_up = true
		_update_land()
		create_tween().tween_property(_heal_bridge, "position:y", _heal_bridge.position.y + 8.0, 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A swarm drone takes `slot`'s place on the circle.
func _regroup(slot: int) -> void:
	if swarm_bridge_up or not is_instance_valid(world) or world.process_mode == Node.PROCESS_MODE_DISABLED:
		return
	var drone_in := Training.Swarmling.new()
	drone_in.center = Course.ground_at(SWARM.z, SWARM.x) + Vector3.UP * SWARM.y
	drone_in.radius_around = SWARM_RADIUS
	drone_in.slot = slot
	drone_in.died.connect(_on_swarmling_down.bind(slot).unbind(1))
	world.add_enemy(drone_in)
	swarm[slot] = drone_in


## A drone down: with all four gone at once the bridge rises; otherwise it regroups after REGROUP.
func _on_swarmling_down(slot: int) -> void:
	swarm[slot] = null
	if swarm.all(func(drone_in: Variant) -> bool: return drone_in == null):
		swarm_bridge_up = true
		_update_land()
		create_tween().tween_property(_swarm_bridge, "position:y", _swarm_bridge.position.y + 8.0, 1.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return
	await get_tree().create_timer(REGROUP, false).timeout
	if swarm[slot] == null:
		_regroup(slot)


## The armoury: while the swarm flies, a crate of micro-missiles waits there whenever the tank has none loaded.
func _run_armoury(at: Vector2) -> void:
	var armoury: Rect2 = ISLANDS[12][0]
	if swarm_bridge_up or not armoury.has_point(at) or tank.current_round == Armament.Round.MICRO or not world.pickups.is_empty():
		return
	world.spawn_pickup("micro", _ground(CRATE) + Vector3.UP * 1.5)


## Paint on the hull: the tank goes back to the start of the turret's run.
func _splash() -> void:
	world.fx.debris(tank.global_position + Vector3.UP, 16, [Fx.Debris.PAINT], 8.0)
	world.fx.explosion(tank.global_position + Vector3.UP, 1.5, [Palette.HOT, Palette.BLUSH, Palette.WHITE])
	var back := Vector2(TURRET.x, TURRET_RUN.x + 3.0)
	tank._set_pose(_ground(back), tank.hull_yaw)
	tank._last_position = tank.global_position
	tank.local_velocity = Vector2.ZERO
	tank.course_u = back.x
	_turret_clock = 0.0


## Input is off before the end buttons take focus, so nothing the tank reads can press them.
func _finish() -> void:
	step = Step.DONE
	tank.input_enabled = false
	_refresh_buttons()
	_play.grab_focus()


func _refresh_buttons() -> void:
	_restart_button.text = "%s  %s" % [_binding(&"restart"), tr("TUTORIAL_RESTART_KEY")]
	_play.text = tr("TUTORIAL_START_GAME")
	_replay.text = tr("TUTORIAL_RESTART")
	_play.visible = step == Step.DONE
	_replay.visible = step == Step.DONE


## Hands a fresh tutorial to the screen switcher; the world stops first so nothing of this run acts on the next one.
func _restart() -> void:
	if world.process_mode == Node.PROCESS_MODE_DISABLED:
		return
	world.process_mode = Node.PROCESS_MODE_DISABLED
	restart.emit()


func _start_game() -> void:
	if step == Step.DONE and not get_tree().paused:
		Game.difficulty = Game.Difficulty.EASY
		start.emit("")


func _input(event: InputEvent) -> void:
	var gamepad := tank.using_gamepad
	if event is InputEventJoypadMotion and absf(event.axis_value) > 0.25 or event is InputEventJoypadButton:
		tank.using_gamepad = true
	elif event is InputEventMouseMotion or event is InputEventKey or event is InputEventMouseButton:
		tank.using_gamepad = false
	if gamepad != tank.using_gamepad:
		_refresh_paint()
		_refresh_buttons()
	if not get_tree().paused and (event is InputEventKey or event is InputEventJoypadMotion):
		for action in ["fire", "dash", "move_forward", "move_left", "move_back", "move_right"]:
			if event.is_action(action):
				get_viewport().set_input_as_handled()
				break


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and not get_tree().paused:
		var viewport := get_viewport() # The swap that restart triggers takes this node out of the tree.
		_restart()
		viewport.set_input_as_handled()
	elif event.is_action_pressed("pause"):
		if _overlay:
			_close_pause()
		else:
			_pause()
		get_viewport().set_input_as_handled()


func _pause() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused:
		focused.release_focus()
	get_tree().paused = true
	_overlay = Menu.new()
	_overlay.title = tr("MENU_PAUSED")
	_overlay.add_item(tr("MENU_RESUME"), _close_pause)
	_overlay.add_item(tr("TUTORIAL_RESTART"), func() -> void:
		_close_pause()
		_restart())
	_overlay.add_item(tr("MENU_SETTINGS"), _settings)
	_overlay.add_item(tr("TUTORIAL_LEAVE"), func() -> void: exit.emit())
	_overlay.back.connect(_close_pause)
	add_child(_overlay)


func _settings() -> void:
	_overlay.queue_free()
	var settings := SettingsMenu.new()
	settings.back.connect(_close_pause)
	_overlay = settings
	add_child(settings)


## Every way out of the pause menu, settings included, repaints the cues for the bindings and language now in force.
func _close_pause() -> void:
	_overlay.queue_free()
	_overlay = null
	get_tree().paused = false
	_refresh_paint()
	_refresh_buttons()
	if step == Step.DONE:
		_play.grab_focus()
