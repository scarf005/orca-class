class_name Tutorial
extends Control
## Learn by driving to marked pads and hitting a target with the real cannon.

signal exit
signal start(checkpoint: String)

enum Step { FORWARD, LEFT, BACK, RIGHT, AIM, FIRE, ROAD, DONE }
const MOVE_ACTIONS := [&"move_forward", &"move_left", &"move_back", &"move_right"]
const DIRECTIONS := [Vector2.UP, Vector2.LEFT, Vector2.DOWN, Vector2.RIGHT]
const DIRECTION_KEYS := ["TUTORIAL_UP", "TUTORIAL_LEFT", "TUTORIAL_DOWN", "TUTORIAL_RIGHT"]
const PAD_RADIUS := 2.6
const ROAD_LENGTH := 120.0 ## Repeat the straight road instead of running beyond the finite course.

class PracticeTank extends Tank:
	var moving := true
	var shooting := false
	var slow := true

	func tick(delta: float) -> void:
		# Small simulation steps keep the tail stable without slowing charging to one step per frame.
		var remaining := minf(delta, 0.25)
		while remaining > 0.00001:
			var piece := minf(remaining, 1.0 / 30.0)
			super.tick(piece)
			remaining -= piece

	func _input_vector() -> Vector2:
		return super._input_vector() * (0.2 if slow else 1.0) if moving else Vector2.ZERO

	func _read_dash(_direction: Vector2) -> void:
		pass

	func _update_charge(delta: float) -> void:
		if shooting:
			super._update_charge(delta)
		else:
			_cancel_charge()

	func _update_weapons(delta: float) -> void:
		if shooting:
			super._update_weapons(delta)

	func _aim_assist(_delta: float) -> void:
		pass

	# The learner, not an automatic weapon, must aim and land the shot.
	func _fire_coax(_muzzle: Node3D, _caliber: int, _spec: Dictionary, _target: Entity) -> void:
		pass

	func auto_tail() -> void:
		pass

class PracticeCamera extends ChaseCamera:
	func follow(_delta: float) -> void:
		var world := World.current
		if not world.player:
			return
		var d := world.rail.d + world.player.course_offset - 4.0
		var u := world.player.course_u
		global_position = Course.ground_at(d - 12.0, u * 0.6) + Vector3.UP * 22.0
		look_at(Course.ground_at(d + 8.0, u * 0.6), Vector3.UP)

class PracticeTarget extends Entity:
	signal cannon_hit

	func _init() -> void:
		radius = 2.6
		center_height = 3.5
		team = Team.NEUTRAL

	func _ready() -> void:
		var post := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.4, center_height, 0.4)
		post.mesh = box
		post.position.y = center_height / 2.0
		add_child(post)
		for ring in [[2.6, Palette.CREAM], [2.0, Palette.INK], [1.4, Palette.BUTTER], [0.6, Palette.INK]]:
			var mesh := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = ring[0]
			disc.bottom_radius = ring[0]
			disc.height = 0.12
			mesh.mesh = disc
			var material := StandardMaterial3D.new()
			material.albedo_color = ring[1]
			mesh.material_override = material
			mesh.rotation.x = PI / 2.0
			mesh.position = Vector3(0, center_height, (2.6 - ring[0]) * 0.1)
			add_child(mesh)
		track_meshes(self)

	func take_hit(hit: Hit) -> void:
		if hit.source is PracticeTank and hit.weapon == "cannon":
			flash()
			cannon_hit.emit()

var view := DitherView.new()
var world := World.new()
var tank := PracticeTank.new()
var target := PracticeTarget.new()
var step := Step.FORWARD
var reached := false
var goal := Vector2.ZERO ## Course (u, offset) of the current parking pad.
var _move_action: StringName = &"move_forward"
var _aim_origin := Vector2.ZERO
var _aim_moved := false
var _road_start := 0.0
var _fire_ready := false
var _overlay: Menu
var _ink := Control.new()
var _instruction := Label.new()
var _caption := Label.new()
var _menu_button := Button.new()
var _play := Button.new()
var _replay := Button.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(view)
	world.view = view
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.rail.mode = Rail.Mode.HOLD
	world.rail.hold_at = 0.0
	world.rail.speed = 0.0
	world.camera.free()
	world.camera = PracticeCamera.new()
	view.viewport.add_child(world)
	world.player = tank
	tank.invulnerable = true
	world.add_child(tank)
	world.add_child(target)
	target.cannon_hit.connect(func() -> void:
		if step == Step.FIRE:
			reached = true
			_refresh_text())
	world.camera.follow(0.0)
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink.draw.connect(_draw_guidance)
	add_child(_ink)
	_label(_caption, Vector2(24, 18), Vector2(560, 30), 20)
	_button(_menu_button, Rect2(784, 12, 152, 36), _pause)
	_label(_instruction, Vector2(284, 434), Vector2(544, 86), 26)
	_instruction.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_button(_replay, Rect2(192, 484, 260, 42), restart_practice)
	_button(_play, Rect2(472, 484, 296, 42), _start_game)
	_set_step(Step.FORWARD)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _label(label: Label, at: Vector2, dimensions: Vector2, font_size: int) -> void:
	label.position = at
	label.size = dimensions
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Palette.CREAM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _button(button: Button, rect: Rect2, action: Callable) -> void:
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 22)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Palette.INK
		style.border_color = Palette.BUTTER if state in ["hover", "focus"] else Palette.MIST
		style.set_border_width_all(2)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	add_child(button)


func _set_step(value: Step) -> void:
	step = value
	reached = false
	_aim_origin = tank.aim_screen
	_aim_moved = false
	_fire_ready = not Input.is_action_pressed("fire")
	tank.moving = step <= Step.RIGHT or step >= Step.ROAD
	tank.slow = step < Step.ROAD
	tank.shooting = step == Step.FIRE and _fire_ready or step == Step.DONE
	tank._cancel_charge()
	if step <= Step.RIGHT:
		_move_action = MOVE_ACTIONS[step]
		goal = Vector2(tank.course_u, tank.course_offset) + Vector2(DIRECTIONS[step].x, -DIRECTIONS[step].y) * (9.0 if step == Step.FORWARD else 7.0)
		if step in [Step.LEFT, Step.RIGHT]:
			goal.x = clampf(goal.x, -Tank.lateral_limit(world.rail.d + goal.y) + PAD_RADIUS, Tank.lateral_limit(world.rail.d + goal.y) - PAD_RADIUS)
		else:
			goal.y = clampf(goal.y, Tank.FORWARD_LIMIT.x + PAD_RADIUS, Tank.FORWARD_LIMIT.y - PAD_RADIUS)
	if step == Step.AIM or step == Step.DONE:
		_place_target()
	if step == Step.ROAD:
		_road_start = world.rail.d
		world.rail.mode = Rail.Mode.RAIL
	target.visible = step in [Step.AIM, Step.FIRE, Step.DONE]
	target.team = Entity.Team.ENEMY if target.visible else Entity.Team.NEUTRAL
	if target.visible:
		world.register(target)
	else:
		world.unregister(target)
	_refresh_text()
	if step == Step.DONE:
		_play.grab_focus()


func _place_target() -> void:
	var d := world.rail.d + tank.course_offset + 30.0
	var forward := Course.forward(d)
	target.position = Course.ground_at(d, tank.course_u + 7.0)
	target.rotation.y = atan2(-forward.x, -forward.z)


func _movement_action() -> StringName:
	var distance := goal - Vector2(tank.course_u, tank.course_offset)
	if absf(distance.x) > absf(distance.y):
		return &"move_left" if distance.x < 0.0 else &"move_right"
	return &"move_back" if distance.y < 0.0 else &"move_forward"


func _event_for(action: StringName) -> InputEvent:
	for event in InputMap.action_get_events(action):
		if tank.using_gamepad == (event is InputEventJoypadMotion or event is InputEventJoypadButton):
			return event
	return null


func binding(action: StringName) -> String:
	var event := _event_for(action)
	if event is InputEventKey:
		return tr("TUTORIAL_KEY") % OS.get_keycode_string(event.physical_keycode)
	if event is InputEventMouseButton:
		return tr("TUTORIAL_MOUSE_%d" % event.button_index)
	return tr("TUTORIAL_TRIGGER") if action == &"fire" else tr("TUTORIAL_STICK")


func _refresh_text() -> void:
	_caption.text = tr("TUTORIAL_TITLE")
	_menu_button.text = tr("TUTORIAL_MENU")
	_play.text = tr("TUTORIAL_START_GAME")
	_replay.text = tr("TUTORIAL_RESTART")
	_play.visible = step == Step.DONE
	_replay.visible = step == Step.DONE
	_instruction.position.y = 408 if step == Step.DONE else 434
	_instruction.size.y = 68 if step == Step.DONE else 86
	if step <= Step.RIGHT:
		_instruction.text = tr("TUTORIAL_STOP_PAD" if tank.using_gamepad else "TUTORIAL_STOP") if reached else tr("TUTORIAL_MOVE_PAD") % tr(DIRECTION_KEYS[MOVE_ACTIONS.find(_move_action)]) if tank.using_gamepad else tr("TUTORIAL_MOVE") % binding(_move_action)
	elif step == Step.AIM:
		_instruction.text = tr("TUTORIAL_AIM_PAD" if tank.using_gamepad else "TUTORIAL_AIM")
	elif step == Step.FIRE:
		_instruction.text = tr("TUTORIAL_HIT") if reached else tr("TUTORIAL_FIRE" if _fire_ready else "TUTORIAL_RELEASE") % binding(&"fire")
	elif step == Step.ROAD:
		_instruction.text = tr("TUTORIAL_RELEASE") % binding(&"move_back") if reached else tr("TUTORIAL_ROAD_PAD") if tank.using_gamepad else tr("TUTORIAL_ROAD") % binding(&"move_back")
	else:
		_instruction.text = tr("TUTORIAL_DONE")
	_ink.queue_redraw()


func restart_practice() -> void:
	world.rail.mode = Rail.Mode.HOLD
	world.rail.hold_at = 0.0
	world.rail.speed = 0.0
	tank.course_u = 0.0
	tank.course_offset = 4.0
	tank.local_velocity = Vector2.ZERO
	_rewind_road()
	_set_step(Step.FORWARD)


func _rewind_road() -> void:
	world.rail.d = 0.0
	_road_start = 0.0
	tank._place(0.0)
	tank._last_position = tank.position
	tank.tracks._last = Vector3.INF
	tank.tail._initialized = false
	tank.tail._claw_velocity = Vector3.ZERO
	for projectile in world.projectiles.duplicate():
		projectile.queue_free()
	_place_target()
	world.camera.follow(0.0)


func _start_game() -> void:
	if step == Step.DONE and not get_tree().paused:
		Game.difficulty = Game.Difficulty.EASY
		start.emit("")


func _process(_delta: float) -> void:
	if get_tree().paused:
		return
	if step >= Step.ROAD and world.rail.d >= ROAD_LENGTH:
		_rewind_road()
	if step <= Step.RIGHT and not reached:
		var action := _movement_action()
		if action != _move_action:
			_move_action = action
			_refresh_text()
		if not tank._input_vector().is_zero_approx() and Vector2(tank.course_u, tank.course_offset).distance_to(goal) <= PAD_RADIUS:
			reached = true
			Sfx.ui("ui_select")
			_refresh_text()
	elif step == Step.AIM:
		_aim_moved = _aim_moved or tank.aim_screen.distance_to(_aim_origin) > 8.0
		if _aim_moved and tank.aim_screen.distance_to(world.camera.unproject_position(target.hit_center())) < 24.0:
			_set_step(Step.FIRE)
	elif step == Step.FIRE and not _fire_ready and not Input.is_action_pressed("fire"):
		_fire_ready = true
		tank.shooting = true
		_refresh_text()
	elif step == Step.ROAD and not reached and world.rail.d - _road_start >= 6.0 and Input.is_action_pressed("move_back") and world.rail.throttle == -1 and world.rail.speed < Rail.CRUISE:
		reached = true
		_refresh_text()
	elif step == Step.DONE and (target.position.distance_to(tank.position) > 65.0 or Course.to_course(target.position).x < world.rail.d + tank.course_offset + 14.0):
		_place_target()
	if reached and Input.get_vector("move_left", "move_right", "move_back", "move_forward").is_zero_approx() and tank.local_velocity.length() < 0.1 and not Input.is_action_pressed("fire"):
		_set_step((step + 1) as Step)
	_ink.queue_redraw()


func _draw_guidance() -> void:
	var font := get_theme_default_font()
	_ink.draw_rect(Rect2(16, 12, font.get_string_size(_caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 24, 36), Palette.INK)
	_ink.draw_rect(Rect2(180, 428 if step != Step.DONE else 402, 660, 98 if step != Step.DONE else 76), Palette.INK)
	var action: StringName = _move_action if step <= Step.RIGHT else &"move_back" if step == Step.ROAD else &"aim_right" if step == Step.AIM else &"fire"
	_draw_input(action)
	if step <= Step.RIGHT:
		var corners := PackedVector2Array()
		for offset in [Vector2(-PAD_RADIUS, -PAD_RADIUS), Vector2(PAD_RADIUS, -PAD_RADIUS), Vector2(PAD_RADIUS, PAD_RADIUS), Vector2(-PAD_RADIUS, PAD_RADIUS), Vector2(-PAD_RADIUS, -PAD_RADIUS)]:
			corners.append(world.camera.unproject_position(Course.ground_at(world.rail.d + goal.y + offset.y, goal.x + offset.x) + Vector3.UP * 0.15))
		_ink.draw_colored_polygon(corners.slice(0, 4), Color(Palette.INK, 0.85))
		_ink.draw_polyline(corners, Palette.INK, 10.0)
		_ink.draw_polyline(corners, Palette.NANITE if reached else Palette.AMBER, 5.0)
		var at := world.camera.unproject_position(Course.ground_at(world.rail.d + goal.y, goal.x) + Vector3.UP * 1.0)
		if reached:
			_ink.draw_polyline(PackedVector2Array([at + Vector2(-12, 0), at + Vector2(-3, 8), at + Vector2(14, -10)]), Palette.NANITE, 4.0)
		else:
			_draw_arrow(at - DIRECTIONS[MOVE_ACTIONS.find(_move_action)] * 36, at, Palette.AMBER)
		if step == Step.FORWARD:
			var player_at := world.camera.unproject_position(tank.hit_center() + Vector3.UP * 2.0)
			_ink.draw_string(font, player_at + Vector2(-136, 16), tr("TUTORIAL_YOUR_TANK"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Palette.INK)
			_ink.draw_string(font, player_at + Vector2(-138, 14), tr("TUTORIAL_YOUR_TANK"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Palette.CREAM)
	elif step in [Step.AIM, Step.FIRE, Step.DONE]:
		var at := world.camera.unproject_position(target.hit_center())
		_ink.draw_arc(at, 28, 0, TAU, 48, Palette.NANITE if reached else Palette.AMBER, 3.0)
		var sight := tank.aim_screen
		for axis in [Vector2.RIGHT, Vector2.DOWN]:
			_ink.draw_line(sight - axis * 10, sight + axis * 10, Palette.INK, 6.0)
			_ink.draw_line(sight - axis * 10, sight + axis * 10, Palette.CREAM, 2.0)
		if tank.charge > 0.0:
			_ink.draw_arc(sight, 19, -PI / 2, -PI / 2 + TAU * tank.charge, 48, Palette.BUTTER, 4.0)


func _draw_arrow(from: Vector2, to: Vector2, color: Color) -> void:
	var direction := (to - from).normalized()
	var side := direction.orthogonal()
	_ink.draw_line(from, to, Palette.INK, 8.0)
	_ink.draw_line(from, to, color, 4.0)
	_ink.draw_colored_polygon(PackedVector2Array([to, to - direction * 14 + side * 9, to - direction * 14 - side * 9]), color)


func _draw_input(action: StringName) -> void:
	var event := _event_for(action)
	var at := Vector2(220, 477 if step != Step.DONE else 440)
	var font := get_theme_default_font()
	if tank.using_gamepad and action != &"fire":
		_ink.draw_rect(Rect2(at - Vector2(38, 26), Vector2(76, 52)), Palette.MIST, false, 2.0)
		for side in [-1, 1]:
			_ink.draw_circle(at + Vector2(side * 18, 0), 13, Palette.MIST, false, 2.0)
		var active := at + Vector2(-18 if action in MOVE_ACTIONS else 18, 0)
		_ink.draw_circle(active, 8, Palette.BUTTER)
		var direction: Vector2 = DIRECTIONS[MOVE_ACTIONS.find(action)] if action in MOVE_ACTIONS else Vector2.RIGHT
		if not reached:
			_draw_arrow(active, active + direction * 30, Palette.BUTTER)
	elif event is InputEventMouseButton or step == Step.AIM and not tank.using_gamepad:
		var rect := Rect2(at - Vector2(23, 32), Vector2(46, 64))
		_ink.draw_rect(rect, Palette.MIST, false, 2.0)
		_ink.draw_line(at + Vector2(0, -32), at, Palette.MIST, 2.0)
		_ink.draw_line(at - Vector2(23, 0), at + Vector2(23, 0), Palette.MIST, 2.0)
		if step == Step.AIM:
			_draw_arrow(at + Vector2(-32, 4), at + Vector2(-32, -20), Palette.BUTTER)
			_draw_arrow(at + Vector2(32, -4), at + Vector2(32, 20), Palette.BUTTER)
		else:
			var button: int = event.button_index
			var button_rect := Rect2(at + Vector2(-21 if button == 1 else 2, -30), Vector2(19, 28)) if button in [1, 2] else Rect2(at + Vector2(-4, -22), Vector2(8, 16)) if button == 3 else Rect2(at + Vector2(-29, 4 if button == 8 else 18), Vector2(10, 12))
			_ink.draw_rect(button_rect, Palette.BUTTER)
	else:
		var key := OS.get_keycode_string(event.physical_keycode) if event is InputEventKey else "RT"
		_ink.draw_rect(Rect2(at - Vector2(28, 28), Vector2(56, 56)), Palette.BUTTER, false, 3.0)
		var font_size := mini(28, int(48.0 / maxf(font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 1).x, 1.0)))
		var width := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		_ink.draw_string(font, at + Vector2(-width / 2, 10), key, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Palette.CREAM)


func _input(event: InputEvent) -> void:
	var gamepad := tank.using_gamepad
	if event is InputEventJoypadMotion and absf(event.axis_value) > 0.25 or event is InputEventJoypadButton:
		tank.using_gamepad = true
	elif event is InputEventMouseMotion or event is InputEventKey or event is InputEventMouseButton:
		tank.using_gamepad = false
	if gamepad != tank.using_gamepad:
		_refresh_text()
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
		_refresh_text())
	_overlay = settings
	add_child(settings)


func _close_pause() -> void:
	_overlay.queue_free()
	_overlay = null
	get_tree().paused = false
	if step == Step.DONE:
		_play.grab_focus()
