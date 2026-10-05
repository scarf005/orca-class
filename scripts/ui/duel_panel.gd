class_name DuelPanel
extends PanelContainer
## Tab opens live gameplay tuning and pauses the duel.

signal restart_requested

var _tuning := GameTuning.new()
const GROUPS := {
	"Duel": ["Duel difficulty", "Duel speed (x)", "Round"],
	"Cannon": ["Charge for box 1 (0-1)", "Charge for box 2 (0-1)", "Charge delay (s)", "Full charge (s)", "Recover after shot (s)", "Quick shell speed, 1 box (m/s)", "Quick shell speed, 2 boxes (m/s)", "Airburst round speed (m/s)", "Shell damage (x)", "HE blast radius (x)"],
	"Coax": ["Coax burst (rounds)", "Coax burst gap (s)"],
	"Missiles": ["ATGM top speed (m/s)", "ATGM turn rate (rad/s)", "ATGM turn rate increment rate (rad/s)", "Micro-Missile turn rate (rad/s)", "Micro-missile turn rate increment rate (rad/s)", "Micro-missile intial split (rad)", "Micro-missile lock interval (s)", "Micro-missile stack interval (s)", "Micro-missile damage (x full shell)"],
	"Tank & aiming": ["Turret traverse (rad/s)", "Gun elevation (rad/s)", "Lock radius (px)", "Near sight along the barrel (0-1)", "Drift nose swing (deg)", "Drift tail lash damage", "Tail stab damage", "Hit weight (x)"],
	"Movement & pursuit": ["Scroll speed (km/h)", "Hard building slows to (share of cruise)", "Hard building recovery (s)", "Water and mud cap (share of cruise)", "Pursuit: slow below (share of cruise)", "Pursuit: fill time (s)", "Pursuit: first group size", "Pursuit: group interval (s)"],
	"Enemies": ["Gunners aim at tail (share)"],
	"Destruction": ["Kill throw cap (x)", "Dismember speed (m/s)", "Dismember focus by momentum", "Blast throw (m/s per dmg)", "Shockwave reach (x blast)", "Topple time (s)", "Collapse time (s)", "Knock-flying speed (m/s)"],
	"Visual effects": ["Secondary blast pops", "Fragments/smoke duration (s)", "Fragments/smoke travel (m)", "Debris life (s)", "Debris smoke life (s)", "Rail smoke shrink (0-1)", "Rail smoke fade speed (x)", "Hitscan beam shrink speed (x)", "Track marks last (s)", "Track marks wear away (s)", "Explosion pace (x time)", "Scenery dither (x)", "Drop shadow density"],
}
var _difficulty := GameTuning.duel_difficulty


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	position = Vector2(16, 50)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.INK, 0.92)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	var sections := VBoxContainer.new()
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grids := {}
	for title: String in GROUPS:
		var header := Button.new()
		header.text = "+ " + title
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.toggle_mode = true
		header.focus_mode = Control.FOCUS_NONE
		header.add_theme_color_override("font_color", Palette.MIST)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		grid.visible = false
		header.toggled.connect(func(expanded: bool) -> void:
			grid.visible = expanded
			header.text = ("- " if expanded else "+ ") + title)
		sections.add_child(header)
		sections.add_child(grid)
		grids[title] = grid
	# Too many rows for the screen: they scroll, the panel stays inside the view.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(740, get_viewport_rect().size.y - 100.0)
	scroll.add_child(sections)
	add_child(scroll)
	for row: Array in _tuning._rows:
		var group := "Enemies" if row[0].ends_with(" per round") else ""
		for title: String in GROUPS:
			if row[0] in GROUPS[title]:
				group = title
				break
		var grid: GridContainer = grids[group]
		var name := Label.new()
		name.text = row[0]
		name.add_theme_color_override("font_color", Palette.MIST)
		var slider := HSlider.new()
		slider.custom_minimum_size = Vector2(220, 18)
		slider.min_value = row[3]
		slider.max_value = row[4]
		slider.step = row[5]
		slider.focus_mode = Control.FOCUS_NONE # Tab stays the panel's toggle.
		slider.value = row[1].call()
		var value := Label.new()
		value.custom_minimum_size = Vector2(56, 0)
		value.add_theme_color_override("font_color", Palette.BUTTER)
		var text: Callable = row[6] if row.size() > 6 else func(v: float) -> String: return _format(v, row[5], row[4])
		value.text = text.call(slider.value)
		slider.value_changed.connect(func(v: float) -> void:
			row[2].call(v)
			if row[0] == "Round" and World.current != null and World.current.player != null:
				World.current.player.load_round(Director.duel_round)
			if row[0] == "Duel speed (x)" and World.current != null and World.current.director._duel:
				World.current.game_speed = GameTuning.duel_speed
			value.text = text.call(v)
			_tuning.save_values())
		grid.add_child(name)
		grid.add_child(slider)
		grid.add_child(value)


# _input, not _unhandled_input: a focused slider would take Tab for focus navigation first.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		visible = not visible
		get_tree().paused = visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CONFINED_HIDDEN
		get_viewport().set_input_as_handled()
		if not visible and _difficulty != GameTuning.duel_difficulty:
			_difficulty = GameTuning.duel_difficulty
			restart_requested.emit()


static func _format(v: float, step: float, top: float) -> String:
	if top == Enemy.KILL_THROW_UNCAPPED and v >= top:
		return "no cap"
	return str(int(v)) if step >= 1.0 else ("%.3f" % v if step < 0.01 else "%.2f" % v)
