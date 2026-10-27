class_name Bestiary
extends Control
## Enemy encyclopedia: every enemy is listed and readable from the start, with a turning model and its stats.
## Up/Down or the wheel pick an entry, Esc goes back to the title.
## Run: godot --path . -- --bestiary

signal back

const FLOOR_D := -400.0 ## On the debug room's flat straight: no scenery, nothing despawns.
const ROW_H := 18.0
const LIST_X := 24.0
const LIST_W := 240.0
const LIST_TOP := 76.0
const VISIBLE_ROWS := 24
## Grouped by role: line enemies, then the bosses. The key is `Director.ENEMY_SCRIPTS`' and names `ENEMY_*` / `DEX_*`.
const KINDS := [
	"crawler", "spitter", "husk", "sporefly", "fpv", "uav", "ugv", "walker", "burner", "quad", "crocodile",
	"helicopter", "hind", "tiltrotor", "rooftop_battery", "sea_mine", "drone_boat", "torpedo_boat",
	"mortar", "skimmer", "burrower", "glinter", "abel", "kain", "adam",
	"colossus", "hovercraft", "borer", "gunship", "hi_mo", "wing", "fortress",
]
const NAME_KEYS := {
	"colossus": "BOSS_COLOSSUS", "hovercraft": "BOSS_HOVERCRAFT", "borer": "BOSS_BORER", "gunship": "BOSS_GUNSHIP",
	"hi_mo": "BOSS_HI_MO", "wing": "BOSS_WING", "fortress": "BOSS_FORTRESS", "hind": "ENEMY_HIND",
	"rooftop_battery": "ENEMY_ROOFTOP_BATTERY", "sea_mine": "ENEMY_SEA_MINE", "drone_boat": "ENEMY_DRONE_BOAT",
	"abel": "ENEMY_ABEL", "kain": "ENEMY_KAIN", "adam": "ENEMY_ADAM",
}
const HIT_KEYS := {
	Hit.Kind.BULLET: "DEX_HIT_BULLET", Hit.Kind.SHELL: "DEX_HIT_SHELL", Hit.Kind.BLAST: "DEX_HIT_BLAST",
	Hit.Kind.FIRE: "DEX_HIT_FIRE", Hit.Kind.RAM: "DEX_HIT_RAM", Hit.Kind.TAIL: "DEX_HIT_TAIL",
	Hit.Kind.LASER: "DEX_HIT_LASER", Hit.Kind.SPORE: "DEX_HIT_SPORE", Hit.Kind.THROWN: "DEX_HIT_THROWN",
	Hit.Kind.FRAGMENT: "DEX_HIT_FRAGMENT",
}

var view := DitherView.new()
var world: World
var selected := 0
var font: Font
var _enemy: Enemy
var _spin := 0.0
var _ui := Control.new() ## Drawn above the 3D view, which as a child would cover this node's own `_draw`.
var _rows: Array[Rect2] = []
var _first := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = get_theme_default_font()
	Course.flat = true
	world = World.new()
	add_child(view)
	world.view = view
	world.rail.d = FLOOR_D + 60.0
	world.rail.mode = Rail.Mode.ARENA
	view.viewport.add_child(world)
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_paint)
	add_child(_ui)
	world.sun.directional_shadow_max_distance = 120.0
	_show(0)


func _exit_tree() -> void:
	Course.flat = false


func _show(index: int) -> void:
	selected = posmod(index, KINDS.size())
	_first = clampi(selected - VISIBLE_ROWS / 2, 0, KINDS.size() - VISIBLE_ROWS)
	if is_instance_valid(_enemy):
		_enemy.queue_free()
	_enemy = load(Director.ENEMY_SCRIPTS[KINDS[selected]]).new()
	var at := Course.ground_at(FLOOR_D + 40.0, 0.0)
	_enemy.position = at
	world.add_enemy(_enemy)
	_enemy.set_process(false) # Posed, not run: no AI, movement or attacks.
	if _enemy.flying:
		at += Vector3.UP * 4.0
	_enemy.global_position = at
	if _enemy.has_method("pose_idle"):
		_enemy.call("pose_idle")
	_ui.queue_redraw()


func _process(delta: float) -> void:
	_spin += delta * 0.5
	if not is_instance_valid(_enemy):
		return
	var bounds := _enemy.visual_bounds()
	var focus := bounds.get_center() if bounds.size != Vector3.ZERO else _enemy.hit_center()
	var reach := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var distance := maxf(reach, 3.0) * 2.1 + 4.0
	var cam := world.camera
	cam.global_position = focus + Vector3(sin(_spin) * distance, reach * 0.3 + 1.0, cos(_spin) * distance)
	cam.look_at(focus, Vector3.UP)
	cam.global_position -= cam.global_basis.x * distance * 0.32 # Parks the model right of the list.
	_ui.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_DOWN:
			_step(-1 if button == MOUSE_BUTTON_WHEEL_UP else 1)
		elif button == MOUSE_BUTTON_LEFT:
			for i in _rows.size():
				if _rows[i].has_point(event.position):
					Sfx.ui("ui_move")
					_show(_first + i)
					break
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_up"):
		_step(-1)
	elif event.is_action_pressed("ui_down"):
		_step(1)
	elif event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B):
		back.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _step(direction: int) -> void:
	Sfx.ui("ui_move")
	_show(selected + direction)


func _enemy_name(kind: String) -> String:
	return tr(NAME_KEYS.get(kind, "ENEMY_" + kind.to_upper()))


## Stats are read from the posed enemy; Easy's reductions are undone so the page shows the same numbers on every difficulty.
func _stats() -> Array[String]:
	var easy := Game.difficulty == Game.Difficulty.EASY
	var lines: Array[String] = []
	lines.append("%s  %d" % [tr("DEX_HP"), roundi(_enemy.max_hp / Game.enemy_hp_scale(_enemy.boss))])
	lines.append("%s  %d mm" % [tr("DEX_ARMOR"), roundi(_enemy.armor * (4.0 if easy else 1.0))])
	lines.append("%s  %d" % [tr("DEX_SCORE"), _enemy.score])
	lines.append("%s  %s" % [tr("DEX_MOVE"), tr("DEX_AIR") if _enemy.flying else tr("DEX_GROUND")])
	return lines


func _weaknesses() -> String:
	var parts: Array[String] = []
	for kind: Hit.Kind in _enemy.weakness:
		var multiplier: float = _enemy.weakness[kind]
		parts.append("%s x%.1f" % [tr(HIT_KEYS[kind]), multiplier])
	return tr("DEX_WEAK_NONE") if parts.is_empty() else ", ".join(parts)


func _paint() -> void:
	_ui.draw_rect(Rect2(0, 0, LIST_X + LIST_W + 16.0, 540), Color(Palette.INK, 0.82))
	_ui.draw_string(font, Vector2(LIST_X, 48), tr("MENU_BESTIARY"), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Palette.FUNGUS)
	_ui.draw_string(font, Vector2(LIST_X + LIST_W - 40.0, 48), "%d/%d" % [selected + 1, KINDS.size()], HORIZONTAL_ALIGNMENT_RIGHT, 56, 12, Palette.MIST)
	_rows.clear()
	for i in mini(VISIBLE_ROWS, KINDS.size() - _first):
		var index := _first + i
		var row := Rect2(LIST_X, LIST_TOP + i * ROW_H, LIST_W, ROW_H)
		_rows.append(row)
		var current := index == selected
		if current:
			_ui.draw_rect(row, Palette.FUNGUS)
		var boss: bool = KINDS[index] in ["colossus", "hovercraft", "borer", "gunship", "hi_mo", "wing", "fortress"]
		var color := Palette.INK if current else (Palette.BUTTER if boss else Palette.CREAM)
		_ui.draw_string(font, row.position + Vector2(6, 13), _enemy_name(KINDS[index]), HORIZONTAL_ALIGNMENT_LEFT, LIST_W - 12.0, 13, color)
	_ui.draw_string(font, Vector2(LIST_X, 524), tr("DEX_HINT"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.MIST)
	if not is_instance_valid(_enemy):
		return
	var panel := Rect2(300, 372, 636, 150)
	_ui.draw_rect(panel, Color(Palette.INK, 0.82))
	var name := _enemy_name(KINDS[selected])
	_ui.draw_string(font, Vector2(318, 404), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Palette.BUTTER if _enemy.boss else Palette.FUNGUS)
	var y := 428.0
	for line in _stats():
		_ui.draw_string(font, Vector2(318, y), line, HORIZONTAL_ALIGNMENT_LEFT, 170, 13, Palette.CREAM)
		y += 18.0
	_ui.draw_string(font, Vector2(318, y + 4.0), tr("DEX_WEAK") + "  " + _weaknesses(), HORIZONTAL_ALIGNMENT_LEFT, 600, 12, Palette.LEAF)
	_ui.draw_multiline_string(font, Vector2(500, 428), tr("DEX_" + KINDS[selected].to_upper()), HORIZONTAL_ALIGNMENT_LEFT, 420, 13, 4, Palette.MIST)
