class_name DuelPanel
extends PanelContainer
## Live tuning for the duel mode: Tab opens sliders for the gun's timing, the hit's weight and the
## hunters each round sends, and pauses the fight. Values are saved to user://duel_tuning.cfg and
## loaded again on the next duel.

const PATH := "user://duel_tuning.cfg"
## [label, getter, setter, min, max, step, optional value text]
var _rows: Array = [
	["Round", func() -> float: return Director.duel_round, func(v: float) -> void: _set_round(int(v)), 0.0, Armament.Round.size() - 1.0, 1.0,
		func(v: float) -> String: return Armament.ROUND_IDS[int(v)].to_upper()],
	["Coax burst (rounds)", func() -> float: return Armament.COAX_BURST_ROUNDS, func(v: float) -> void: Armament.COAX_BURST_ROUNDS = int(v), 1.0, 20.0, 1.0],
	["Coax burst gap (s)", func() -> float: return Armament.COAX_BURST_GAP, func(v: float) -> void: Armament.COAX_BURST_GAP = v, 0.0, 2.0, 0.05],
	["Charge for box 1 (0-1)", func() -> float: return Armament.STAGE_1, func(v: float) -> void: Armament.STAGE_1 = v, 0.0, 0.95, 0.01],
	["Charge for box 2 (0-1)", func() -> float: return Armament.STAGE_2, func(v: float) -> void: Armament.STAGE_2 = v, 0.05, 0.99, 0.01],
	["Airburst round speed (m/s)", func() -> float: return Armament.AIRBURST_SPEED, func(v: float) -> void: Armament.AIRBURST_SPEED = v, 30.0, 400.0, 5.0],
	["ATGM top speed (m/s)", func() -> float: return Armament.ATGM_SPEED, func(v: float) -> void: Armament.ATGM_SPEED = v, 60.0, 400.0, 5.0],
	["ATGM turn rate (rad/s)", func() -> float: return Armament.ATGM_TURN, func(v: float) -> void: Armament.ATGM_TURN = v, 1.0, 40.0, 0.5],
	["Micro-missile lock interval (s)", func() -> float: return Armament.MICRO_LOCK_INTERVAL, func(v: float) -> void: Armament.MICRO_LOCK_INTERVAL = v, 0.02, 0.5, 0.01],
	["Micro-missile stack interval (s)", func() -> float: return Armament.MICRO_STACK_INTERVAL, func(v: float) -> void: Armament.MICRO_STACK_INTERVAL = v, 0.05, 1.5, 0.05],
	["Micro-missile damage (x full shell)", func() -> float: return Armament.MICRO_DAMAGE, func(v: float) -> void: Armament.MICRO_DAMAGE = v, 0.05, 1.0, 0.05],
	["Scroll speed (km/h)", func() -> float: return Rail.CRUISE * 3.6, func(v: float) -> void: Rail.set_cruise(v), 40.0, 200.0, 5.0],
	["Charge delay (s)", func() -> float: return Armament.TAP_TIME, func(v: float) -> void: Armament.TAP_TIME = v, 0.0, 0.6, 0.01],
	["Full charge (s)", func() -> float: return Armament.FULL_TIME, func(v: float) -> void: Armament.FULL_TIME = v, 0.3, 3.0, 0.05],
	["Recover after shot (s)", func() -> float: return Armament.CANNON_RECOVER, func(v: float) -> void: Armament.CANNON_RECOVER = v, 0.0, 2.5, 0.05],
	["Lock radius (px)", func() -> float: return Armament.LOCK_RADIUS, func(v: float) -> void: Armament.LOCK_RADIUS = v, 16.0, 200.0, 2.0],
	["Quick shell speed, 1 box (m/s)", func() -> float: return Armament.QUICK_SPEED_1, func(v: float) -> void: Armament.QUICK_SPEED_1 = v, 60.0, 1200.0, 10.0],
	["Quick shell speed, 2 boxes (m/s)", func() -> float: return Armament.QUICK_SPEED_2, func(v: float) -> void: Armament.QUICK_SPEED_2 = v, 60.0, 1200.0, 10.0],
	["Turret traverse (rad/s)", func() -> float: return Tank.TURRET_RATE, func(v: float) -> void: Tank.TURRET_RATE = v, 2.0, 30.0, 0.5],
	["Gun elevation (rad/s)", func() -> float: return Tank.PITCH_RATE, func(v: float) -> void: Tank.PITCH_RATE = v, 1.0, 30.0, 0.5],
	["Kill throw cap (x)", func() -> float: return Enemy.KILL_THROW_MAX, func(v: float) -> void: Enemy.KILL_THROW_MAX = v, 0.5, Enemy.KILL_THROW_UNCAPPED, 0.5],
	["Dismember speed (m/s)", func() -> float: return Enemy.DISMEMBER_SPEED, func(v: float) -> void: Enemy.DISMEMBER_SPEED = v, 0.0, 200.0, 1.0],
	["Dismember focus by momentum", func() -> float: return Enemy.DISMEMBER_FOCUS, func(v: float) -> void: Enemy.DISMEMBER_FOCUS = v, 0.0, 3.0, 0.05],
	["Blast throw (m/s per dmg)", func() -> float: return Wreck.BLAST_THROW, func(v: float) -> void: Wreck.BLAST_THROW = v, 0.0, 0.3, 0.005],
	["Shell damage (x)", func() -> float: return Armament.SHELL_DAMAGE_SCALE, func(v: float) -> void: Armament.SHELL_DAMAGE_SCALE = v, 0.25, 6.0, 0.05],
	["Secondary blast pops", func() -> float: return Fx.BLAST_POPS, func(v: float) -> void: Fx.BLAST_POPS = int(v), 0.0, 8.0, 1.0],
	["HE blast radius (x)", func() -> float: return Armament.HE_RADIUS_SCALE, func(v: float) -> void: Armament.HE_RADIUS_SCALE = v, 0.5, 4.0, 0.1],
	["Shockwave reach (x blast)", func() -> float: return World.SHOCKWAVE_SCALE, func(v: float) -> void: World.SHOCKWAVE_SCALE = v, 0.5, 5.0, 0.1],
	["Debris life (s)", func() -> float: return Fx.DEBRIS_LIFE, func(v: float) -> void: Fx.DEBRIS_LIFE = v, 0.1, 8.0, 0.1],
	["Debris smoke life (s)", func() -> float: return Fx.DEBRIS_SMOKE_LIFE, func(v: float) -> void: Fx.DEBRIS_SMOKE_LIFE = v, 0.05, 3.0, 0.05],
	["Drift nose swing (deg)", func() -> float: return rad_to_deg(Tank.DRIFT_ANGLE), func(v: float) -> void: Tank.DRIFT_ANGLE = deg_to_rad(v), 0.0, 120.0, 1.0],
	["Gunners aim at tail (share)", func() -> float: return Gunnery.TAIL_CHANCE, func(v: float) -> void: Gunnery.TAIL_CHANCE = v, 0.0, 1.0, 0.05],
	["Near sight along the barrel (0-1)", func() -> float: return Hud.NEAR_SIGHT, func(v: float) -> void: Hud.NEAR_SIGHT = v, 0.1, 0.95, 0.05],
	["Track marks last (s)", func() -> float: return TrackMarks.FADE_START, func(v: float) -> void: TrackMarks.FADE_START = v, 0.5, 30.0, 0.5],
	["Track marks wear away (s)", func() -> float: return TrackMarks.FADE_TIME, func(v: float) -> void: TrackMarks.FADE_TIME = v, 0.2, 20.0, 0.2],
	["Explosion pace (x time)", func() -> float: return Fx.BLAST_PACE, func(v: float) -> void: Fx.BLAST_PACE = v, 0.2, 1.5, 0.05],
	["Drift tail lash damage", func() -> float: return Tank.LASH_DAMAGE, func(v: float) -> void: Tank.LASH_DAMAGE = v, 0.0, 400.0, 5.0],
	["Tail stab damage", func() -> float: return Tank.STAB_DAMAGE, func(v: float) -> void: Tank.STAB_DAMAGE = v, 0.0, 200.0, 5.0],
	["Hard building slows to (share of cruise)", func() -> float: return Rail.HARD_HIT_SPEED, func(v: float) -> void: Rail.HARD_HIT_SPEED = v, 0.0, 1.0, 0.05],
	["Hard building recovery (s)", func() -> float: return Rail.HARD_RECOVER, func(v: float) -> void: Rail.HARD_RECOVER = v, 0.1, 5.0, 0.1],
	["Water and mud cap (share of cruise)", func() -> float: return Rail.WADE_SPEED, func(v: float) -> void: Rail.WADE_SPEED = v, 0.1, 1.0, 0.05],
	["Pursuit: slow below (share of cruise)", func() -> float: return Director.PURSUIT_SLOW, func(v: float) -> void: Director.PURSUIT_SLOW = v, 0.1, 1.0, 0.05],
	["Pursuit: fill time (s)", func() -> float: return Director.PURSUIT_FILL, func(v: float) -> void: Director.PURSUIT_FILL = v, 0.2, 6.0, 0.1],
	["Pursuit: first group size", func() -> float: return Director.PURSUIT_GROUP, func(v: float) -> void: Director.PURSUIT_GROUP = int(v), 2.0, 4.0, 1.0],
	["Pursuit: group interval (s)", func() -> float: return Director.PURSUIT_INTERVAL, func(v: float) -> void: Director.PURSUIT_INTERVAL = v, 0.5, 8.0, 0.1],
	["Scenery dither (x)", func() -> float: return DitherView.SCENERY_DITHER, func(v: float) -> void: DitherView.SCENERY_DITHER = v, 0.0, 1.5, 0.05],
	["Drop shadow density", func() -> float: return World.DROP_SHADOW, func(v: float) -> void: World.DROP_SHADOW = v, 0.0, 1.0, 0.05],
	["Topple time (s)", func() -> float: return Prop.TOPPLE_TIME, func(v: float) -> void: Prop.TOPPLE_TIME = v, 0.1, 2.0, 0.05],
	["Collapse time (s)", func() -> float: return Prop.COLLAPSE_TIME, func(v: float) -> void: Prop.COLLAPSE_TIME = v, 0.1, 2.0, 0.05],
	["Knock-flying speed (m/s)", func() -> float: return Prop.KNOCK_SPEED, func(v: float) -> void: Prop.KNOCK_SPEED = v, 2.0, 40.0, 0.5],
	["Hit weight (x)", func() -> float: return Tank.HIT_WEIGHT, func(v: float) -> void: Tank.HIT_WEIGHT = v, 0.0, 3.0, 0.05],
]
var _grid := GridContainer.new()


func _init() -> void:
	for kind: String in Director.duel_counts:
		_rows.append(["%s per round" % kind, func() -> float: return Director.duel_counts[kind], func(v: float) -> void: Director.duel_counts[kind] = int(v), 0.0, 6.0, 1.0])


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
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 12)
	# Too many rows for the screen: they scroll, the panel stays inside the view.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, get_viewport_rect().size.y - 100.0)
	scroll.add_child(_grid)
	add_child(scroll)
	load_values()
	for row: Array in _rows:
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
			value.text = text.call(v)
			save_values())
		_grid.add_child(name)
		_grid.add_child(slider)
		_grid.add_child(value)


# _input, not _unhandled_input: a focused slider would take Tab for focus navigation first.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		visible = not visible
		get_tree().paused = visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CONFINED_HIDDEN
		get_viewport().set_input_as_handled()


## Picked mid-duel, the round is loaded at once as well as on every refit.
static func _set_round(round: int) -> void:
	Director.duel_round = round as Armament.Round
	if World.current != null and World.current.player != null:
		World.current.player.load_round(Director.duel_round)


static func _format(v: float, step: float, top: float) -> String:
	if top == Enemy.KILL_THROW_UNCAPPED and v >= top:
		return "no cap"
	return str(int(v)) if step >= 1.0 else ("%.3f" % v if step < 0.01 else "%.2f" % v)


func save_values() -> void:
	var config := ConfigFile.new()
	for row: Array in _rows:
		config.set_value("duel", row[0], row[1].call())
	config.save(PATH)


func load_values() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	for row: Array in _rows:
		if config.has_section_key("duel", row[0]):
			row[2].call(float(config.get_value("duel", row[0])))
