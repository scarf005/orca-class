class_name Results
extends Control
## Stage results: stats counted up one line at a time, then the rank stamp and best records.

signal retry
signal next_stage
signal title_pressed

var stats: RunStats
var has_next_stage := false
var font: Font
var _time := 0.0
var _rows: Array = []
var _rank := ""
var _new_best := false
var _menu: Menu


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = get_theme_default_font()
	_rank = stats.rank()
	_rows = [
		[tr("RESULT_SCORE"), stats.score, "%d"],
		[tr("RESULT_KILLS"), stats.kill_ratio() * 100.0, "%d%%"],
		[tr("RESULT_ACCURACY"), stats.accuracy() * 100.0, "%d%%"],
		[tr("RESULT_MAX_COMBO"), stats.max_combo, "%d"],
		[tr("RESULT_DAMAGE"), stats.damage_taken, "%d"],
		[tr("RESULT_TIME"), stats.time, "time"],
	]
	if stats.ranked:
		_new_best = Game.submit_best(Game.best_key("score"), stats.score)
		Game.submit_best(Game.best_key("rank_" + _rank), 1)
	Sfx.play_music("res://assets/music/clear.ogg", false)


func _process(delta: float) -> void:
	var before := int(_time / 0.45)
	_time += delta
	if int(_time / 0.45) != before and int(_time / 0.45) <= _rows.size() + 1:
		Sfx.ui("ui_select" if int(_time / 0.45) == _rows.size() + 1 else "ui_move")
	if _time > (_rows.size() + 2) * 0.45 and _menu == null:
		_menu = Menu.new()
		_menu.center = Vector2(480, 470)
		_menu.width = 240
		if has_next_stage:
			_menu.add_item(tr("MENU_NEXT_STAGE"), func() -> void: next_stage.emit())
		_menu.add_item(tr("MENU_RETRY"), func() -> void: retry.emit())
		_menu.add_item(tr("MENU_QUIT_TITLE"), func() -> void: title_pressed.emit())
		add_child(_menu)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.INK, clampf(_time * 2.0, 0.0, 0.85)))
	var header := tr("STAGE_CLEAR")
	var w := font.get_string_size(header, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x
	draw_string(font, Vector2(480 - w * 0.5, 90), header, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Palette.FUNGUS)
	for i in _rows.size():
		var appear := _time - (i + 1) * 0.45
		if appear < 0.0:
			break
		var row: Array = _rows[i]
		var k := clampf(appear / 0.35, 0.0, 1.0)
		var value: float = row[1] * k
		var text := _format(value, row[2])
		var y := 150 + i * 30
		draw_string(font, Vector2(260, y), row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.MIST)
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string(font, Vector2(560 - tw, y + 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Palette.CREAM)
	var stamp := _time - (_rows.size() + 1) * 0.45
	if stamp > 0.0:
		var scale := lerpf(3.0, 1.0, clampf(stamp / 0.2, 0.0, 1.0))
		var size_px := int(72 * scale)
		var color := {"S": Palette.FUNGUS, "A": Palette.BUTTER, "B": Palette.SKY, "C": Palette.MIST}[_rank] as Color
		var rw := font.get_string_size(_rank, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
		draw_string(font, Vector2(700 - rw * 0.5, 280 + size_px * 0.3), _rank, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
		draw_string(font, Vector2(660, 190), tr("RESULT_RANK"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.MIST)
		if _new_best:
			draw_string(font, Vector2(640, 330), tr("RESULT_NEW_BEST"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.BUTTER if fmod(_time, 0.5) < 0.3 else Palette.PEACH)
		if not stats.ranked:
			draw_string(font, Vector2(640, 350), tr("RESULT_UNRANKED"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.STONE)


func _format(value: float, kind: String) -> String:
	if kind == "time":
		var seconds := int(value)
		return "%d:%02d" % [seconds / 60, seconds % 60]
	return kind % int(value)
