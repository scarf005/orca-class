class_name StageSelect
extends Control
## Square stage cards with checkpoint choices below the focused stage.

signal selected(difficulty: Game.Difficulty, checkpoint: String, stage: int)
signal back

const HEADING_BASELINE := 48.0
const CARD_SIZE := Vector2(256, 256)
const CARD_TOP := 82.0
const CARD_GAP := 24.0
const CARD_LEFT := 72.0
const STAGE_NAMES := [&"STAGE_1_NAME", &"STAGE_2_NAME", &"STAGE_3_NAME"]
const DIFFICULTY_NAMES := {Game.Difficulty.EASY: &"DIFFICULTY_EASY", Game.Difficulty.NORMAL: &"DIFFICULTY_NORMAL", Game.Difficulty.HARD: &"DIFFICULTY_HARD"}
const MAPS := [preload("res://assets/ui/stage1.png"), preload("res://assets/ui/stage2.png"), preload("res://assets/ui/stage3.png")]

enum Focus { CARD, CHECKPOINT, BACK }

var difficulty := Game.Difficulty.NORMAL
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
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
		selected_stage = clampi(selected_stage + (1 if right else -1), 1, Game.STAGE_COUNT)
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
	return int(Game.bests.get(Game.best_key("score", stage_number, difficulty), 0))


func _checkpoints() -> Array[String]:
	var result: Array[String] = []
	var defined := StageDef.of(selected_stage).checkpoints
	for checkpoint in ["midboss", "boss"]:
		if defined.has(checkpoint) and Game.is_checkpoint_unlocked(checkpoint, selected_stage):
			result.append(checkpoint)
	return result


## Centred over the row of cards, clear of the persistent FPS counter at the top left.
func heading_position(heading: String) -> Vector2:
	var row := Game.STAGE_COUNT * CARD_SIZE.x + (Game.STAGE_COUNT - 1) * CARD_GAP
	return Vector2(CARD_LEFT + (row - font.get_string_size(heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x) * 0.5, HEADING_BASELINE)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.INK, 0.82))
	var heading := tr("STAGE_SELECT")
	draw_string(font, heading_position(heading), heading, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Palette.FUNGUS)
	var mode := tr(DIFFICULTY_NAMES[difficulty])
	draw_string(font, Vector2(912 - font.get_string_size(mode, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, 40), mode, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.BUTTER)
	_cards.clear()
	for i in Game.STAGE_COUNT:
		var rect := Rect2(Vector2(CARD_LEFT + i * (CARD_SIZE.x + CARD_GAP), CARD_TOP), CARD_SIZE)
		_cards.append(rect)
		var card_focus := focus == Focus.CARD and selected_stage == i + 1
		var pop := 5.0 if card_focus else 0.0
		var draw_rect_at := Rect2(rect.position - Vector2.ONE * pop, rect.size + Vector2.ONE * pop * 2.0)
		draw_rect(draw_rect_at, Palette.FUNGUS if card_focus else Palette.STONE, false, 4.0)
		# Only the focus border pops out; the map remains a native 1:1 crop.
		draw_texture_rect(MAPS[i], rect, false)
		if selected_stage != i + 1:
			draw_rect(rect, Color(0, 0, 0, 0.12))
		draw_rect(rect, Color(Palette.INK, 0.5), false, 1.0)
		var label := "%d  %s" % [i + 1, tr(STAGE_NAMES[i])]
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 36)), Color(Palette.INK, 0.6)) # Keeps the name legible over a bright map.
		draw_string(font, rect.position + Vector2(10, 25), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Palette.CREAM)
		if i >= 1:
			var band := Rect2(rect.position + Vector2(0, 202), Vector2(rect.size.x, 32))
			draw_rect(band, Color.BLACK)
			for x in range(0, int(band.size.x), 16):
				for y in [0.0, band.size.y - 6.0]:
					var origin := band.position + Vector2(x, y)
					draw_colored_polygon(PackedVector2Array([
						origin + Vector2(0, 6), origin + Vector2(6, 0),
						origin + Vector2(14, 0), origin + Vector2(8, 6),
					]), Palette.BUTTER)
			var wip := "WIP / 작업중"
			var text_width := font.get_string_size(wip, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string(font, band.position + Vector2((band.size.x - text_width) / 2.0, 21), wip, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.BUTTER)
		var best := best_score(i + 1)
		if best > 0:
			var best_text := tr("STAGE_BEST") % best
			draw_string(font, rect.position + Vector2(10, rect.size.y - 12), best_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.BUTTER)
	var checkpoints := _checkpoints()
	var prompt_y := 372.0
	var focus_name := "%d  %s" % [selected_stage, tr(STAGE_NAMES[selected_stage - 1])]
	draw_string(font, Vector2(CARD_LEFT, prompt_y), tr("STAGE_CHECKPOINTS") % focus_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Palette.MIST)
	_checkpoint_rows.clear()
	for i in checkpoints.size():
		var row := Rect2(CARD_LEFT + i * 260, prompt_y + 16, 240, 28)
		_checkpoint_rows.append(row)
		draw_rect(row, Palette.FUNGUS if focus == Focus.CHECKPOINT and selected_checkpoint == i else Palette.DUSK)
		draw_rect(row, Palette.CYAN if focus == Focus.CHECKPOINT and selected_checkpoint == i else Palette.FUNGUS, false, 1.0)
		draw_string(font, row.position + Vector2(10, 19), tr(Game.string_key("MENU_FROM_" + checkpoints[i].to_upper(), selected_stage)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.CREAM)
	var hint := tr("STAGE_SELECT_HINT")
	draw_string(font, Vector2(CARD_LEFT, 500), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.STONE)
	var back_color := Palette.CYAN if focus == Focus.BACK else Palette.MIST
	draw_rect(_back_rect, Color(Palette.CYAN, 0.18) if focus == Focus.BACK else Color.TRANSPARENT)
	draw_string(font, Vector2(850, 500), tr("MENU_BACK"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, back_color)
