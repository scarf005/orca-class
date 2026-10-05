class_name Tutorial
extends Control
## A drivable course: painted controls, concrete turns, a breakable gate and a locked shot.

signal exit
signal start(checkpoint: String)

enum Step { DRIVE, GATE, LOCK, DONE }
const ROUTE := [Vector2(-36, -50), Vector2(-36, -12), Vector2(-4, -12), Vector2(-4, -34), Vector2(28, -34), Vector2(28, 16), Vector2(28, 50), Vector2(-8, 50)]
const LANES := [Rect2(-43, -57, 14, 52), Rect2(-43, -19, 46, 14), Rect2(-11, -41, 14, 36), Rect2(-11, -41, 46, 14), Rect2(21, -41, 14, 98), Rect2(-15, 43, 50, 14)]

class CourseTank extends Tank:
	var course: Tutorial
	var firing_lock: Entity
	var _dash_read := false

	func tick(delta: float) -> void:
		# Integrate all elapsed time at the normal speed; small steps prevent wall tunnelling.
		_dash_read = false
		var steps := clampi(ceili(delta * 60.0), 1, 32)
		for i in steps:
			super.tick(delta / steps)

	func _update_movement(delta: float) -> void:
		var before := course.floor_position(global_position)
		super._update_movement(delta)
		var proposed := course.floor_position(global_position)
		var resolved := course.slide(before, proposed)
		if not resolved.is_equal_approx(proposed):
			_set_pose(course.floor_world(resolved), hull_yaw)
			course_u = Course.to_course(global_position).y
			var actual := (global_position - course.floor_world(before)) / maxf(delta, 0.000001)
			local_velocity = Vector2(actual.x, actual.z)

	func _read_dash(wish: Vector2) -> void:
		if not _dash_read:
			_dash_read = true
			super._read_dash(wish)

	func _collide_props() -> void:
		# This course has persistent barriers, not crushable scenery. slide() owns contact.
		pass

	func _fire_shell(round: Armament.Round, muzzle: Vector3, direction: Vector3, power := 0.0) -> void:
		firing_lock = charge_lock if round == Armament.Round.APHE and power >= 1.0 else null
		super._fire_shell(round, muzzle, direction, power)
		firing_lock = null

class CourseWorld extends World:
	func _process(delta: float) -> void:
		# Keep World's non-projectile upkeep; sweep each shot's live interval before expiry.
		if _hitstop > 0:
			_hitstop -= delta / maxf(Engine.time_scale, 0.001)
			if _hitstop <= 0:
				Engine.time_scale = game_speed
		for projectile in projectiles.duplicate():
			if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
				continue
			var life: float = projectile.life
			var flight := minf(delta, maxf(life, 0))
			# Projectile.step otherwise expires before sweeping its last live segment.
			projectile.life += delta
			projectile.step(flight)
			if not projectile.is_queued_for_deletion():
				projectile.life = life - flight
				if projectile.life <= 0:
					projectile.step(0)
		terrain.stream(rail.d)
		var step := minf(delta, 1.0 / 30.0)
		stats.tick(step)
		_update_nanites(step)
		_update_drop_shadows()

class CourseCamera extends ChaseCamera:
	var course: Tutorial

	func follow(_delta: float) -> void:
		if not World.current.player:
			return
		var at := World.current.player.global_position
		global_position = at + course.floor_basis * Vector3(0, 30, 26)
		look_at(at + course.floor_basis * Vector3(0, 0, -10), Vector3.UP)

class Gate extends Prop:
	func take_hit(hit: Hit) -> void:
		if hit.source is CourseTank and hit.weapon == "cannon":
			super.take_hit(hit)

	func _exit_tree() -> void:
		if World.current:
			World.current.enemies.erase(self)
		super._exit_tree()

class LockTarget extends Entity:
	func take_hit(hit: Hit) -> void:
		if hit.source is CourseTank and hit.weapon == "cannon" and (hit.source as CourseTank).firing_lock == self:
			super.take_hit(hit)

	func on_death(hit: Hit) -> void:
		World.current.fx.shatter(visual_bounds(), [Fx.Debris.METAL], hit.direction, 0.5)
		Sfx.play("blast", global_position)

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

var view := DitherView.new()
var world := CourseWorld.new()
var tank := CourseTank.new()
var gate: Gate
var target: LockTarget
var step := Step.DRIVE
var floor_basis := Basis.IDENTITY
var floor_origin := Vector3.ZERO
var walls: Array[Rect2] = []
var _course_objects := Node3D.new()
var _paint: Array[Node3D] = []
var _overlay: Menu
var _play := Button.new()
var _replay := Button.new()


func floor_world(point: Vector2) -> Vector3:
	var at := floor_origin + floor_basis * Vector3(point.x, 0, -point.y)
	at.y = Course.height_at(at)
	return at


func floor_position(at: Vector3) -> Vector2:
	var local := floor_basis.inverse() * (at - floor_origin)
	return Vector2(local.x, -local.z)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	floor_origin = Course.to_world(Course.ARENA_CENTER_D, 0)
	floor_basis = Basis(Vector3.UP, Course.yaw_at(Course.ARENA_CENTER_D))
	add_child(view)
	world.view = view
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.rail.mode = Rail.Mode.ARENA
	world.rail.d = Course.ARENA_CENTER_D
	world.rail.speed = 0
	world.camera.free()
	var camera := CourseCamera.new()
	camera.course = self
	world.camera = camera
	view.viewport.add_child(world)
	tank.course = self
	tank.invulnerable = true
	world.player = tank
	world.add_child(tank)
	world.add_child(_course_objects)
	_build_course()
	var sight := Sight.new()
	sight.world = world
	add_child(sight)
	_button(_replay, Rect2(192, 484, 260, 42), restart_practice)
	_button(_play, Rect2(472, 484, 296, 42), _start_game)
	restart_practice()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _button(button: Button, rect: Rect2, action: Callable) -> void:
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(action)
	add_child(button)


func _box(at: Vector2, dimensions: Vector3, color: Color, parent: Node3D = _course_objects) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	parent.add_child(mesh)
	mesh.global_position = floor_world(at) + Vector3.UP * dimensions.y / 2
	mesh.global_basis = floor_basis
	return mesh


func _inside(point: Vector2) -> bool:
	for lane in LANES:
		if lane.has_point(point):
			return true
	return false


func _build_course() -> void:
	var xs: Array[float] = []
	var ys: Array[float] = []
	for lane in LANES:
		for x in [lane.position.x, lane.end.x]:
			if x not in xs:
				xs.append(x)
		for y in [lane.position.y, lane.end.y]:
			if y not in ys:
				ys.append(y)
	xs.sort()
	ys.sort()
	for i in xs.size() - 1:
		for j in ys.size() - 1:
			var cell := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			if not _inside(cell.get_center()):
				continue
			_box(cell.get_center(), Vector3(cell.size.x, 0.18, cell.size.y), Palette.STONE)
			for edge in [Rect2(cell.position.x - 0.5, cell.position.y, 1, cell.size.y), Rect2(cell.end.x - 0.5, cell.position.y, 1, cell.size.y), Rect2(cell.position.x, cell.position.y - 0.5, cell.size.x, 1), Rect2(cell.position.x, cell.end.y - 0.5, cell.size.x, 1)]:
				var outward: Vector2 = (edge.get_center() - cell.get_center()).normalized()
				if _inside(edge.get_center() + outward * 0.6):
					continue
				walls.append(edge)
				_box(edge.get_center(), Vector3(edge.size.x, 2.4, edge.size.y), Palette.CREAM)
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
	label.global_position = floor_world(at) + Vector3.UP * 0.35
	label.global_basis = floor_basis * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI / 2)
	_paint.append(label)


func _binding(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and not tank.using_gamepad:
			return OS.get_keycode_string(event.physical_keycode if event.physical_keycode else event.keycode)
		if event is InputEventMouseButton and not tank.using_gamepad:
			return "M%d" % (event.button_index - 4 if event.button_index in [8, 9] else event.button_index)
	return "↑" if action == &"move_forward" else "↓" if action == &"move_back" else "←" if action == &"move_left" else "→"


func _refresh_paint() -> void:
	for paint in _paint:
		paint.queue_free()
	_paint.clear()
	for i in ROUTE.size() - 1:
		var from: Vector2 = ROUTE[i]
		var direction: Vector2 = (ROUTE[i + 1] - from).normalized()
		var action: StringName = &"move_forward" if direction.y > 0 else &"move_back" if direction.y < 0 else &"move_right" if direction.x > 0 else &"move_left"
		_floor_text(from + direction * 8, _binding(action))
		var length := from.distance_to(ROUTE[i + 1])
		for distance in range(15, int(length) - 3, 10):
			_floor_text(from + direction * distance, "↑", atan2(-direction.x, direction.y))
	_floor_text(Vector2(0, 50), tr("TUTORIAL_LOCK"))
	_mouse_paint()
	_floor_text(Vector2(24, -7), "↔")
	_floor_text(Vector2(32, -7), "↕")


func _mouse_paint() -> void:
	var at := Vector2(28, -7)
	if tank.using_gamepad:
		_floor_text(at, "RT")
		return
	var button := MOUSE_BUTTON_LEFT
	for event in InputMap.action_get_events("fire"):
		if event is InputEventKey:
			_floor_text(at, OS.get_keycode_string(event.physical_keycode if event.physical_keycode else event.keycode))
			return
		if event is InputEventMouseButton:
			button = event.button_index
			break
	var pressed := Rect2(-1.8 if button == MOUSE_BUTTON_LEFT else 0.2, 0.3, 1.6, 2.4) if button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] else Rect2(-3.2, 0.4 if button == MOUSE_BUTTON_XBUTTON1 else -1.2, 0.8, 1.2) if button in [MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2] else Rect2(-0.3, 1, 0.6, 1)
	for rectangle in [Rect2(-2, -3, 4, 0.22), Rect2(-2, 3, 4, 0.22), Rect2(-2, -3, 0.22, 6), Rect2(2, -3, 0.22, 6), Rect2(0, 0, 0.22, 3), Rect2(-2, 0, 4, 0.22), pressed]:
		var mesh := _box(at + rectangle.get_center(), Vector3(rectangle.size.x, 0.04, rectangle.size.y), Palette.BUTTER)
		mesh.global_position.y += 0.24
		_paint.append(mesh)


func _make_gate() -> void:
	gate = Gate.new()
	gate.kind = "gate"
	gate.footprint = 7
	gate.height = 5
	gate.radius = 7
	gate.center_height = 2.5
	gate.max_hp = 100
	gate.hp = 100
	gate.team = Entity.Team.NEUTRAL
	gate.position = floor_world(Vector2(28, 16))
	var panel := LowPoly.new()
	panel.box(Transform3D(Basis.IDENTITY, Vector3(0, 2.5, 0)), Vector3(13, 5, 0.8), Palette.INK)
	panel.box(Transform3D(Basis.IDENTITY, Vector3(0, 2.5, 0.45)), Vector3(2.0, 2.0, 0.12), Palette.AMBER)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = panel.mesh()
	gate.add_child(mesh)
	gate.basis = floor_basis
	gate.track_meshes(gate)
	_course_objects.add_child(gate)
	# Props belong to the scenery registry; this panel also needs an elevated aim surface.
	world.enemies.append(gate)
	gate.died.connect(func(_entity: Entity) -> void:
		world.enemies.erase(gate)
		step = Step.LOCK
		_make_target())


func _make_target() -> void:
	target = LockTarget.new()
	target.radius = 2.5
	target.center_height = 3
	target.max_hp = 100
	target.hp = 100
	target.position = floor_world(Vector2(-8, 50))
	var model := MeshInstance3D.new()
	model.mesh = PropKit.mesh("crate")
	model.scale = Vector3(2, 3, 2)
	target.add_child(model)
	target.track_meshes(target)
	_course_objects.add_child(target)
	target.died.connect(func(_entity: Entity) -> void:
		step = Step.DONE
		_refresh_buttons()
		_play.grab_focus())


func slide(from: Vector2, to: Vector2) -> Vector2:
	var closed := is_instance_valid(gate) and not gate.dead
	var position := from
	var motion := to - from
	for attempt in 3:
		var fraction := 1.0
		var normal := Vector2.ZERO
		for i in walls.size() + int(closed):
			var obstacle: Rect2 = walls[i] if i < walls.size() else Rect2(21, 15.5, 14, 1)
			var rect := obstacle.grow(Tank.HULL_RADIUS)
			var near := 0.0
			var far := 1.0
			var face := Vector2.ZERO
			var intersects := true
			for axis in 2:
				if absf(motion[axis]) < 0.000001:
					if position[axis] <= rect.position[axis] or position[axis] >= rect.end[axis]:
						intersects = false
					continue
				var enter := (rect.position[axis] - position[axis]) / motion[axis]
				var leave := (rect.end[axis] - position[axis]) / motion[axis]
				if enter > leave:
					var swap := enter
					enter = leave
					leave = swap
				if enter >= near:
					near = enter
					face = Vector2.ZERO
					face[axis] = -signf(motion[axis])
				far = minf(far, leave)
			if intersects and near <= far and near < fraction and far > 0 and not face.is_zero_approx():
				fraction = near
				normal = face
		position += motion * fraction
		# Centimetre clearance exceeds float precision at the arena's kilometre-scale coordinates.
		position += normal * 0.01
		if normal.is_zero_approx():
			break
		motion *= 1.0 - fraction
		motion -= normal * motion.dot(normal)
	return position


func restart_practice() -> void:
	for projectile in world.projectiles.duplicate():
		projectile.queue_free()
	world.projectiles.clear()
	if is_instance_valid(gate):
		world.enemies.erase(gate)
		world.props.remove(gate)
		gate.queue_free()
	if is_instance_valid(target):
		world.unregister(target)
		target.queue_free()
	target = null
	step = Step.DRIVE
	tank._cancel_charge()
	tank.local_velocity = Vector2.ZERO
	tank.velocity = Vector3.ZERO
	tank._drift = 0
	tank._drift_dir = 0
	tank._drift_yaw = 0
	tank.anchor_cooldown = 0
	tank.tail.set_state(Tail.State.IDLE)
	tank._set_pose(floor_world(ROUTE[0]), Course.yaw_at(Course.ARENA_CENTER_D))
	tank._last_position = tank.global_position
	tank.tail._initialized = false
	tank.tail._claw_velocity = Vector3.ZERO
	tank.tracks._last = Vector3.INF
	_make_gate()
	world.camera.follow(0)
	_refresh_buttons()


func _refresh_buttons() -> void:
	_play.text = tr("TUTORIAL_START_GAME")
	_replay.text = tr("TUTORIAL_RESTART")
	_play.visible = step == Step.DONE
	_replay.visible = step == Step.DONE


func _process(_delta: float) -> void:
	if get_tree().paused:
		return
	if step == Step.DRIVE and floor_position(tank.global_position).distance_to(Vector2(28, 5)) < 12:
		step = Step.GATE


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
	if not get_tree().paused and (event is InputEventKey or event is InputEventJoypadMotion):
		for action in ["fire", "move_forward", "move_left", "move_back", "move_right"]:
			if event.is_action(action):
				get_viewport().set_input_as_handled()
				break


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
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
		restart_practice())
	_overlay.add_item(tr("MENU_SETTINGS"), _settings)
	_overlay.add_item(tr("TUTORIAL_LEAVE"), func() -> void: exit.emit())
	_overlay.back.connect(_close_pause)
	add_child(_overlay)


func _settings() -> void:
	_overlay.queue_free()
	var settings := SettingsMenu.new()
	settings.back.connect(func() -> void:
		_close_pause()
		_refresh_paint()
		_refresh_buttons())
	_overlay = settings
	add_child(settings)


func _close_pause() -> void:
	_overlay.queue_free()
	_overlay = null
	get_tree().paused = false
	if step == Step.DONE:
		_play.grab_focus()
