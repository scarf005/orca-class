class_name Tutorial
extends Control
## A quiet practice range using the game's tank, sight and projectiles.

signal exit
signal start(checkpoint: String)

enum Step { WELCOME, LEFT, RIGHT, FORWARD, BACK, STOP, AIM, FIRE, DONE }
const MOVE_ACTIONS := [&"move_left", &"move_right", &"move_forward", &"move_back"]
const STEP_KEYS := ["TUTORIAL_WELCOME", "TUTORIAL_LEFT", "TUTORIAL_RIGHT", "TUTORIAL_FORWARD", "TUTORIAL_BACK", "TUTORIAL_STOP", "TUTORIAL_AIM", "TUTORIAL_FIRE", "TUTORIAL_DONE"]

class PracticeTank extends Tank:
	var moving := false
	var shooting := false

	func tick(delta: float) -> void:
		# Keep the idle tail's spring stable on slow machines, like the world's projectile step.
		super.tick(minf(delta, 1.0 / 30.0))

	func _input_vector() -> Vector2:
		return super._input_vector() if moving else Vector2.ZERO

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

	# Automatic guns and melee must not do the learner's task for them.
	func _fire_coax(_muzzle: Node3D, _caliber: int, _spec: Dictionary, _target: Entity) -> void:
		pass

	func auto_tail() -> void:
		pass

class PracticeTarget extends Entity:
	signal cannon_hit

	func _init() -> void:
		radius = 2.5
		center_height = 3.0

	func _ready() -> void:
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		mesh.mesh = sphere
		var material := StandardMaterial3D.new()
		material.albedo_color = Palette.BUTTER
		mesh.material_override = material
		mesh.position.y = center_height
		add_child(mesh)
		track_meshes(mesh)

	func take_hit(hit: Hit) -> void:
		if hit.source is PracticeTank and hit.weapon == "cannon":
			flash()
			cannon_hit.emit()

var view := DitherView.new()
var world := World.new()
var tank := PracticeTank.new()
var target := PracticeTarget.new()
var step := Step.WELCOME
var achieved := false
var _origin := Vector2.ZERO
var _aim_origin := Vector2.ZERO
var _aim_moved := false
var _overlay: Menu
var _sight := Control.new()
var _heading := Label.new()
var _instruction := Label.new()
var _feedback := Label.new()
var _next := Button.new()
var _leave := Button.new()
var _restart := Button.new()


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
	view.viewport.add_child(world)
	world.player = tank
	tank.invulnerable = true
	world.add_child(tank)
	target.position = Course.ground_at(45.0, 9.0)
	world.add_child(target)
	target.cannon_hit.connect(func() -> void:
		if step == Step.FIRE:
			_complete())
	world.camera.follow(0.0)
	_sight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sight.draw.connect(_draw_sight)
	add_child(_sight)
	var panel := ColorRect.new()
	panel.color = Color(Palette.INK, 0.95)
	panel.position = Vector2(16, 12)
	panel.size = Vector2(928, 162)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_label(_heading, Vector2(32, 20), Vector2(880, 34), 28)
	_label(_instruction, Vector2(32, 60), Vector2(880, 106), 24)
	_label(_feedback, Vector2(32, 420), Vector2(880, 44), 24)
	_button(_next, Vector2(660, 474), Vector2(268, 50), advance)
	_button(_leave, Vector2(32, 474), Vector2(260, 50), func() -> void: exit.emit())
	_button(_restart, Vector2(308, 474), Vector2(320, 50), restart_practice)
	_set_step(Step.WELCOME)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _label(label: Label, at: Vector2, dimensions: Vector2, font_size: int) -> void:
	label.position = at
	label.size = dimensions
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Palette.CREAM)
	label.add_theme_color_override("font_shadow_color", Palette.INK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _button(button: Button, at: Vector2, dimensions: Vector2, action: Callable) -> void:
	button.position = at
	button.size = dimensions
	button.add_theme_font_size_override("font_size", 24)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Palette.DUSK if state == "disabled" else Palette.INK
		style.border_color = Palette.BUTTER if state in ["hover", "focus"] else Palette.MIST
		style.set_border_width_all(2)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	add_child(button)


func _set_step(value: Step) -> void:
	step = value
	achieved = step in [Step.WELCOME, Step.DONE]
	_origin = Vector2(tank.course_u, tank.course_offset)
	_aim_origin = tank.aim_screen
	_aim_moved = false
	if step != Step.STOP:
		tank.local_velocity = Vector2.ZERO
	tank.moving = step in [Step.LEFT, Step.RIGHT, Step.FORWARD, Step.BACK, Step.STOP, Step.DONE]
	tank.shooting = step in [Step.FIRE, Step.DONE]
	tank._cancel_charge()
	_feedback.text = ""
	_refresh_text()


func _refresh_text() -> void:
	_leave.text = tr("TUTORIAL_LEAVE")
	_restart.text = tr("TUTORIAL_RESTART")
	_heading.text = tr("TUTORIAL_TITLE") if step == Step.WELCOME else tr("TUTORIAL_STEP") % [mini(step, 7), 7]
	_instruction.text = tr("TUTORIAL_AIM_PAD") if step == Step.AIM and tank.using_gamepad else tr("TUTORIAL_STOP_PAD") if step == Step.STOP and tank.using_gamepad else tr(STEP_KEYS[step])
	if step in [Step.LEFT, Step.RIGHT, Step.FORWARD, Step.BACK]:
		_instruction.text = _instruction.text % binding(MOVE_ACTIONS[step - Step.LEFT])
	elif step == Step.FIRE:
		_instruction.text = _instruction.text % binding(&"fire")
	_next.text = tr("TUTORIAL_BEGIN") if step == Step.WELCOME else tr("TUTORIAL_START_GAME") if step == Step.DONE else tr("TUTORIAL_NEXT")
	_next.disabled = not achieved
	if achieved:
		_next.grab_focus()
	if achieved and step not in [Step.WELCOME, Step.DONE]:
		_feedback.text = tr("TUTORIAL_HIT") if step == Step.FIRE else tr("TUTORIAL_OK")


func binding(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if tank.using_gamepad:
			if event is InputEventJoypadMotion:
				return tr("TUTORIAL_TRIGGER") if action == &"fire" else tr("TUTORIAL_STICK") % tr("ACTION_" + String(action).to_upper())
		elif event is InputEventKey:
			return tr("TUTORIAL_KEY") % OS.get_keycode_string(event.physical_keycode)
		elif event is InputEventMouseButton:
			return tr("TUTORIAL_MOUSE_%d" % event.button_index)
	return Game.binding_label(action)


func _complete() -> void:
	if achieved:
		return
	achieved = true
	if step in [Step.LEFT, Step.RIGHT, Step.FORWARD, Step.BACK]:
		tank.moving = false
		tank.local_velocity = Vector2.ZERO
	_next.disabled = false
	_next.grab_focus()
	_feedback.text = tr("TUTORIAL_HIT") if step == Step.FIRE else tr("TUTORIAL_OK")


func advance() -> void:
	if not achieved or get_tree().paused:
		return
	if step == Step.DONE:
		Game.difficulty = Game.Difficulty.EASY
		start.emit("")
	else:
		_set_step((step + 1) as Step)


func restart_practice() -> void:
	tank.course_u = 0.0
	tank.course_offset = 4.0
	tank._place(world.rail.d)
	_set_step(Step.WELCOME)


func _process(_delta: float) -> void:
	if get_tree().paused:
		return
	var moved := Vector2(tank.course_u, tank.course_offset) - _origin
	match step:
		Step.LEFT:
			if moved.x <= -2.0 and Input.is_action_pressed("move_left"):
				_complete()
		Step.RIGHT:
			if moved.x >= 2.0 and Input.is_action_pressed("move_right"):
				_complete()
		Step.FORWARD:
			if moved.y >= 2.0 and Input.is_action_pressed("move_forward"):
				_complete()
		Step.BACK:
			if moved.y <= -2.0 and Input.is_action_pressed("move_back"):
				_complete()
		Step.STOP:
			if tank._input_vector().is_zero_approx() and tank.local_velocity.length() < 0.1:
				_complete()
		Step.AIM:
			_aim_moved = _aim_moved or tank.aim_screen.distance_to(_aim_origin) > 8.0
			if _aim_moved and tank.aim_screen.distance_to(world.camera.unproject_position(target.hit_center())) < 32.0:
				_complete()
	_sight.queue_redraw()


func _draw_sight() -> void:
	if not is_instance_valid(world.player):
		return
	if step >= Step.AIM:
		var at := world.camera.unproject_position(target.hit_center())
		_sight.draw_arc(at, 32, 0, TAU, 64, Palette.BUTTER, 3.0)
		var sight := tank.aim_screen
		_sight.draw_line(sight - Vector2(12, 0), sight + Vector2(12, 0), Palette.CREAM, 3.0)
		_sight.draw_line(sight - Vector2(0, 12), sight + Vector2(0, 12), Palette.CREAM, 3.0)
		if tank.charge > 0.0:
			_sight.draw_arc(sight, 20, -PI / 2, -PI / 2 + TAU * tank.charge, 64, Palette.FUNGUS, 4.0)


func _input(event: InputEvent) -> void:
	var gamepad := tank.using_gamepad
	if event is InputEventJoypadMotion and absf(event.axis_value) > 0.25:
		tank.using_gamepad = true
	elif event is InputEventMouseMotion or event is InputEventKey or event is InputEventMouseButton:
		tank.using_gamepad = false
	if gamepad != tank.using_gamepad:
		_refresh_text()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _overlay:
			_close_pause()
		else:
			get_tree().paused = true
			_overlay = Menu.new()
			_overlay.title = tr("MENU_PAUSED")
			_overlay.add_item(tr("MENU_RESUME"), _close_pause)
			_overlay.add_item(tr("MENU_SETTINGS"), _settings)
			_overlay.add_item(tr("TUTORIAL_LEAVE"), func() -> void: exit.emit())
			_overlay.back.connect(_close_pause)
			add_child(_overlay)
		get_viewport().set_input_as_handled()


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
