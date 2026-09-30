class_name StageSelect
extends Control
## Two square stage cards with checkpoint choices below the focused stage.

signal selected(difficulty: Game.Difficulty, checkpoint: String, stage: int)
signal back

# The persistent FPS label occupies (16, 44)-(112, 60), plus its 2px outline.
const HEADING_POSITION := Vector2(218, 48)
const CARD_SIZE := Vector2(250, 250)
const CARD_TOP := 82.0
const CARD_GAP := 24.0
const CARD_LEFT := 218.0
const STAGE_NAMES := [&"STAGE_1_NAME", &"STAGE_2_NAME"]
const MAPS := [preload("res://assets/ui/stage1.png"), preload("res://assets/ui/stage2.png")]

var difficulty := Game.Difficulty.NORMAL
enum Focus { CARD, CHECKPOINT, BACK }

var selected_stage := 1
var focus := Focus.CARD
var selected_checkpoint := 0
var font: Font
var _time := 0.0
var _cards: Array[Rect2] = []
var _checkpoint_rows: Array[Rect2] = []
var _back_rect := Rect2(820, 478, 100, 30)
var _axis_x_sign := 0
var _axis_y_sign := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = get_theme_default_font()
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var point: Vector2 = event.position
		for i in _cards.size():
			if _cards[i].has_point(point):
				if selected_stage != i + 1 or focus != Focus.CARD:
					selected_stage = i + 1
					focus = Focus.CARD
					selected_checkpoint = 0
					Sfx.ui("ui_move")
				queue_redraw()
		for i in _checkpoint_rows.size():
			if _checkpoint_rows[i].has_point(point):
				if focus != Focus.CHECKPOINT or selected_checkpoint != i:
					Sfx.ui("ui_move")
				focus = Focus.CHECKPOINT
				selected_checkpoint = i
				queue_redraw()
		if _back_rect.has_point(point) and focus != Focus.BACK:
			focus = Focus.BACK
			Sfx.ui("ui_move")
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for i in _cards.size():
				if _cards[i].has_point(event.position):
					_activate(i + 1)
					accept_event()
					return
			for i in _checkpoint_rows.size():
				if _checkpoint_rows[i].has_point(event.position):
					_activate_checkpoint(i)
					accept_event()
					return
			if _back_rect.has_point(event.position):
				back.emit()
				accept_event()
				return

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var left: bool = event.is_action_pressed("ui_left") or (event is InputEventKey and event.pressed and ((event as InputEventKey).physical_keycode == KEY_A or (event as InputEventKey).keycode == KEY_A))
	var right: bool = event.is_action_pressed("ui_right") or (event is InputEventKey and event.pressed and ((event as InputEventKey).physical_keycode == KEY_D or (event as InputEventKey).keycode == KEY_D))
	var up: bool = event.is_action_pressed("ui_up")
	var down: bool = event.is_action_pressed("ui_down")
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion.axis == JOY_AXIS_LEFT_X:
			var x_sign := 0 if absf(motion.axis_value) <= 0.5 else (1 if motion.axis_value > 0.0 else -1)
			left = x_sign < 0 and x_sign != _axis_x_sign
			right = x_sign > 0 and x_sign != _axis_x_sign
			_axis_x_sign = x_sign
		elif motion.axis == JOY_AXIS_LEFT_Y:
			var y_sign := 0 if absf(motion.axis_value) <= 0.5 else (1 if motion.axis_value > 0.0 else -1)
			# Physical stick down is positive Y; do not use the tank's reversed movement actions here.
			down = y_sign > 0 and y_sign != _axis_y_sign
			up = y_sign < 0 and y_sign != _axis_y_sign
			_axis_y_sign = y_sign
	if event is InputEventKey and event.pressed:
		up = up or (event as InputEventKey).physical_keycode == KEY_UP or (event as InputEventKey).keycode == KEY_UP
		down = down or (event as InputEventKey).physical_keycode == KEY_DOWN or (event as InputEventKey).keycode == KEY_DOWN
	var accept: bool = event.is_action_pressed("ui_accept") or (event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A)
	var cancel: bool = event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and ((event as InputEventKey).physical_keycode == KEY_ESCAPE or (event as InputEventKey).keycode == KEY_ESCAPE)) or (event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B)
	if left or right:
		selected_stage = 1 if left else 2
		focus = Focus.CARD
		selected_checkpoint = 0
		Sfx.ui("ui_move")
	elif up:
		_move_vertical(-1)
	elif down:
		_move_vertical(1)
	elif accept:
		_activate_focus()
	elif cancel:
		back.emit()
	else:
		return
	get_viewport().set_input_as_handled()
	queue_redraw()

func _move_vertical(direction: int) -> void:
	var checkpoints := _checkpoints()
	match focus:
		Focus.CARD:
			if direction > 0:
				if checkpoints.is_empty():
					focus = Focus.BACK
				else:
					focus = Focus.CHECKPOINT
					selected_checkpoint = 0
			else:
				focus = Focus.BACK
		Focus.CHECKPOINT:
			if direction < 0:
				if selected_checkpoint > 0:
					selected_checkpoint -= 1
				else:
					focus = Focus.CARD
			elif selected_checkpoint + 1 < checkpoints.size():
				selected_checkpoint += 1
			else:
				focus = Focus.BACK
		Focus.BACK:
			if direction < 0:
				if checkpoints.is_empty():
					focus = Focus.CARD
				else:
					focus = Focus.CHECKPOINT
					selected_checkpoint = checkpoints.size() - 1
	Sfx.ui("ui_move")

func _activate_focus() -> void:
	match focus:
		Focus.CARD:
			_activate(selected_stage)
		Focus.CHECKPOINT:
			_activate_checkpoint(selected_checkpoint)
		Focus.BACK:
			back.emit()

func _activate(stage: int) -> void:
	selected_stage = stage
	Sfx.ui("ui_select")
	selected.emit(difficulty, "", stage)

func _activate_checkpoint(index: int) -> void:
	var checkpoints := _checkpoints()
	if index < checkpoints.size():
		Sfx.ui("ui_select")
		selected.emit(difficulty, checkpoints[index], selected_stage)

func best_score(stage_number: int) -> int:
	var suffix := "hard" if difficulty == Game.Difficulty.HARD else "normal"
	var key := "%s_%s" % [Game.stage_key("score", stage_number), suffix]
	return int(Game.bests.get(key, 0))

func _checkpoints() -> Array[String]:
	var result: Array[String] = []
	for checkpoint in ["midboss", "boss"]:
		if Game.is_checkpoint_unlocked(checkpoint, selected_stage):
			result.append(checkpoint)
	return result

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.INK, 0.82))
	var heading := tr("STAGE_SELECT")
	draw_string(font, HEADING_POSITION, heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Palette.FUNGUS)
	var mode := tr("DIFFICULTY_NORMAL" if difficulty == Game.Difficulty.NORMAL else "DIFFICULTY_HARD")
	draw_string(font, Vector2(912 - font.get_string_size(mode, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 40), mode, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.BUTTER)
	_cards.clear()
	for i in 2:
		var rect := Rect2(Vector2(CARD_LEFT + i * (CARD_SIZE.x + CARD_GAP), CARD_TOP), CARD_SIZE)
		_cards.append(rect)
		var card_focus := focus == Focus.CARD and selected_stage == i + 1
		var pop := 5.0 if card_focus else 0.0
		var draw_rect_at := Rect2(rect.position - Vector2.ONE * pop, rect.size + Vector2.ONE * pop * 2.0)
		draw_rect(draw_rect_at, Palette.FUNGUS if card_focus else Palette.STONE, false, 4.0)
		draw_texture_rect(MAPS[i], draw_rect_at, false)
		if selected_stage != i + 1:
			draw_rect(draw_rect_at, Color(0, 0, 0, 0.12))
		draw_rect(draw_rect_at, Color(Palette.INK, 0.5), false, 1.0)
		var label := "%d  %s" % [i + 1, tr(STAGE_NAMES[i])]
		draw_string(font, draw_rect_at.position + Vector2(10, 25), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.CREAM)
		var best := best_score(i + 1)
		if best > 0:
			var best_text := tr("STAGE_BEST") % best
			draw_string(font, draw_rect_at.position + Vector2(10, draw_rect_at.size.y - 12), best_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.BUTTER)
	var checkpoints := _checkpoints()
	var prompt_y := 372.0
	var focus_name := "%d  %s" % [selected_stage, tr(STAGE_NAMES[selected_stage - 1])]
	draw_string(font, Vector2(218, prompt_y), tr("STAGE_CHECKPOINTS") % focus_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.MIST)
	_checkpoint_rows.clear()
	for i in checkpoints.size():
		var row := Rect2(218 + i * 260, prompt_y + 16, 240, 28)
		_checkpoint_rows.append(row)
		draw_rect(row, Palette.FUNGUS if focus == Focus.CHECKPOINT and selected_checkpoint == i else Palette.DUSK)
		draw_rect(row, Palette.CYAN if focus == Focus.CHECKPOINT and selected_checkpoint == i else Palette.FUNGUS, false, 1.0)
		draw_string(font, row.position + Vector2(10, 19), tr(Game.string_key("MENU_FROM_" + checkpoints[i].to_upper(), selected_stage)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.CREAM)
	var hint := tr("STAGE_SELECT_HINT")
	draw_string(font, Vector2(218, 500), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.STONE)
	var back_color := Palette.CYAN if focus == Focus.BACK else Palette.MIST
	draw_rect(_back_rect, Color(Palette.CYAN, 0.18) if focus == Focus.BACK else Color.TRANSPARENT)
	draw_string(font, Vector2(850, 500), tr("MENU_BACK"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, back_color)
