class_name Hud
extends Control
## In-game HUD drawn by hand at 960×540: armor, weapons, laser heat, throttle, score and combo,
## the reticle with lead marker, boss bar, threat arrows and score popups.

const SCALE := 960.0 / DitherView.RESOLUTION.x ## Screen pixels per 3D-view pixel.

var world: World
var font: Font
var _popups: Array[Dictionary] = []
var _incoming: Array[Dictionary] = [] ## {position, time}: waves arriving from outside the view.
var _intercepts := 0
var _banner := ""
var _sensor_warning := "" ## A lost roof sensor, said small just above the hull schematic.
var _sensor_warning_time := 0.0
const SENSOR_WARNING_TIME := 1.6
var _banner_time := 0.0
var _shout := ""
var _shout_time := 0.0
var _shout_total := 1.0
var _shout_color := Palette.AMBER
var _armor_shake := 0.0
var _last_armor := 100.0
var _time := 0.0
var _storm := 0.0
var _hit_marker := 0.0
var _kill_marker := 0.0
var _style_rank := 0 ## Last rank drawn, to catch rank changes.
var _style_pop := 0.0 ## Punch on the meter after a rank up.
var _style_drop := 0.0 ## Shudder on the meter after a rank down.
# Wireframe x-ray views of the real models.
# Straight down, front of the tank at the top of the view.
var _tank_view := WireView.new(Vector2i(84, 108), Vector3(0.6, 20.0, -0.6), Vector3(0.6, 0.0, -0.6), 16.0, Vector3.FORWARD)
var _life_view := WireView.new(Vector2i(20, 30), Vector3(0, 20.0, -1.5), Vector3(0, 0.0, -1.5), 14.0, Vector3.FORWARD)
var _round_view := WireView.new(Vector2i(44, 26), Vector3(0, 0.2, 4.0), Vector3(0, 0.1, 0), 1.3)
var _coax_view := WireView.new(Vector2i(72, 34), Vector3(4.0, 0.3, -0.8), Vector3(0, 0, -0.8), 2.2)
var _laser_view := WireView.new(Vector2i(30, 26), Vector3(1.6, 1.6, -1.8), Vector3(0, 0.35, 0), 1.3)
var _xray := TankModel.new()
var _xray_tail := Tail.new()
var _shown_round := -1
var _tail_posed := false
var _shown_tier := -1
var _painted := {} ## Node -> color it was last painted, so materials change only when states do.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = get_theme_default_font()
	for view in [_tank_view, _life_view, _round_view, _coax_view, _laser_view]:
		add_child(view)
	_tank_view.root.add_child(_xray)
	_xray_tail.mount = _xray.tail_mount
	_tank_view.root.add_child(_xray_tail)
	var life := TankModel.new()
	_life_view.root.add_child(life)
	WireView.paint.call_deferred(life, Palette.HULL_LIGHT)
	_life_view.refresh.call_deferred()
	_laser_view.show_mesh(TankModel._rws_mesh(), Palette.MINT)
	world.scored.connect(_on_scored)
	world.intercepted.connect(_on_intercepted)
	world.hit_confirmed.connect(_on_hit_confirmed)
	world.director.incoming.connect(func(from: Vector3) -> void:
		_incoming.append({"position": from, "time": 0.0})
		Sfx.ui("warn", 0.0, 1.3))
	world.player.pickup_collected.connect(_on_pickup)
	world.player.sensor_lost.connect(func(name: String) -> void:
		_sensor_warning = tr("WARN_FCS_LOST" if name == "fcs" else "WARN_RWS_LOST")
		_sensor_warning_time = SENSOR_WARNING_TIME
		Sfx.ui("warn", -10.0))
	world.director.section_changed.connect(func(section: Course.Section) -> void: banner(tr("SECTION_%d" % section)))
	world.director.checkpoint_reached.connect(func(_name: String) -> void: banner(tr("CHECKPOINT")))


func banner(text: String, time := 2.6) -> void:
	_banner = text
	_banner_time = time


## A huge arcade call-out that slams onto the screen (weapon pickups, mission start and clear).
func shout(text: String, color := Palette.AMBER, time := 1.4) -> void:
	_shout = text
	_shout_color = color
	_shout_time = time
	_shout_total = time
	Sfx.ui("shout")


func set_storm(amount: float) -> void:
	_storm = amount


func _on_scored(points: int, position: Vector3, combo: int) -> void:
	if points <= 0:
		return
	_popups.append({"text": str(points), "position": position, "time": 0.0, "combo": combo})
	if combo > 0 and combo % 10 == 0:
		Sfx.ui("combo", 0.0, 1.0 + combo / 60.0)


## Every laser kill says so where it happened.
func _on_intercepted(position: Vector3) -> void:
	_intercepts += 1
	_popups.append({"text": tr("CALLOUT_INTERCEPT"), "position": position, "time": 0.0, "combo": 0, "color": Palette.MINT})


func _on_hit_confirmed(killed: bool) -> void:
	_hit_marker = 0.16
	if killed:
		_kill_marker = 0.32
	queue_redraw()


## Climbing a rank punches the meter with a rising sting; the meter itself is the only call-out.
func _update_style_rank(delta: float) -> void:
	_style_pop = maxf(0.0, _style_pop - delta)
	_style_drop = maxf(0.0, _style_drop - delta)
	var rank := world.stats.style_rank()
	if rank > _style_rank:
		_style_pop = 0.35
		Sfx.ui("combo", 4.0, 1.0 + rank * 0.12)
	elif rank < _style_rank:
		_style_drop = 0.3
	_style_rank = rank


func _on_pickup(id: String) -> void:
	var name := tr("PICKUP_" + id.to_upper()) + "!!"
	if id == "coax":
		name = _coax_label() + "!!"
	var color := Palette.AMBER
	if Armament.round_from_id(id) != Armament.Round.APHE:
		color = Armament.ROUND_COLORS[Armament.round_from_id(id)]
	shout(name, color)


func _process(delta: float) -> void:
	_time += delta
	_hit_marker = maxf(0.0, _hit_marker - delta)
	_kill_marker = maxf(0.0, _kill_marker - delta)
	_banner_time -= delta
	_shout_time -= delta
	for popup in _popups:
		popup.time += delta
	_popups = _popups.filter(func(p: Dictionary) -> bool: return p.time < 0.9)
	for warning in _incoming:
		warning.time += delta
	_incoming = _incoming.filter(func(w: Dictionary) -> bool: return w.time < INCOMING_TIME)
	var armor := world.player.hp
	if armor < _last_armor:
		_armor_shake = 0.3
	_last_armor = armor
	_armor_shake = maxf(0.0, _armor_shake - delta)
	_update_style_rank(delta)
	queue_redraw()


func _draw() -> void:
	if world == null or world.player == null:
		return
	if _storm > 0.0:
		_draw_storm()
	_draw_reticle()
	_draw_hit_marker()
	_draw_threats()
	_draw_popups()
	_draw_status()
	_draw_weapons()
	_draw_score()
	_draw_progress()
	_draw_boss()
	_draw_banner()
	_draw_shout()


func _text(pos: Vector2, text: String, color: Color, size := 12, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	if align == HORIZONTAL_ALIGNMENT_CENTER and width <= 0.0:
		pos.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
		align = HORIZONTAL_ALIGNMENT_LEFT
		width = -1.0
	draw_string(font, pos + Vector2(1, 1), text, align, width, size, Palette.INK)
	draw_string(font, pos, text, align, width, size, color)


func _panel(rect: Rect2, accent := Palette.FUNGUS) -> void:
	draw_rect(rect, Color(Palette.INK, 0.82))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 2)), accent)
	draw_rect(rect, Color(Palette.DUSK), false, 1.0)


func _bar(rect: Rect2, value: float, color: Color, segments := 20, back := Palette.DUSK) -> void:
	var gap := 2.0
	var w := (rect.size.x - gap * (segments - 1)) / segments
	for i in segments:
		var filled := value * segments > i + 0.001
		draw_rect(Rect2(rect.position + Vector2(i * (w + gap), 0), Vector2(w, rect.size.y)), color if filled else back)


func _draw_status() -> void:
	var p := world.player
	var shake := Vector2(randf_range(-2, 2), randf_range(-2, 2)) * (_armor_shake / 0.3) * 3.0
	var origin := Vector2(16, 416) + shake
	_panel(Rect2(origin, Vector2(210, 112)), Palette.MINT)
	_update_xray()
	draw_texture(_tank_view.get_texture(), origin + Vector2(8, 2))
	if _sensor_warning_time > 0.0:
		_sensor_warning_time -= get_process_delta_time()
		if fmod(_sensor_warning_time, 0.4) > 0.12:
			_text(origin + Vector2(4, -6), _sensor_warning, Palette.RED, 12)
	var armor := p.hp / p.max_hp
	_bar(Rect2(origin + Vector2(104, 12), Vector2(96, 8)), armor, _armor_color(armor), 10)
	_bar(Rect2(origin + Vector2(104, 28), Vector2(96, 5)), p.tail.hp / Tail.MAX_HP, _tail_color(), 10)
	for i in world.stats.lives:
		draw_texture(_life_view.get_texture(), origin + Vector2(104 + i * 24, 76))
	# Throttle meter between brake and boost chevrons.
	var rail := world.rail
	var m := Vector2(392, 508)
	_panel(Rect2(m - Vector2(8, 12), Vector2(192, 26)), Palette.SKY)
	var meter_color := Palette.SKY
	if rail.is_meter_locked():
		meter_color = Palette.STONE
	elif rail.throttle == 1:
		meter_color = Palette.BUTTER
	elif rail.throttle == -1:
		meter_color = Palette.PERIWINKLE
	_chevrons(m + Vector2(8, 1), -1.0, Palette.PERIWINKLE if rail.throttle == -1 else Palette.STONE)
	_bar(Rect2(m + Vector2(22, -3), Vector2(132, 8)), rail.meter, meter_color, 12)
	_chevrons(m + Vector2(166, 1), 1.0, Palette.BUTTER if rail.throttle == 1 else Palette.STONE)


func _armor_color(armor: float) -> Color:
	var color := Palette.MINT if armor > 0.5 else (Palette.BUTTER if armor > 0.25 else Palette.RED)
	if armor <= 0.25 and fmod(_time, 0.4) < 0.2:
		color = Palette.CORAL
	return color


func _tail_color() -> Color:
	var tail := world.player.tail
	if tail.destroyed:
		return Palette.RED if fmod(_time, 0.5) < 0.3 else Palette.DUSK
	return Palette.FUNGUS if not tail.is_hurt() else Palette.BUTTER


func _module_color(state: TankModules.State) -> Color:
	match state:
		TankModules.State.DAMAGED:
			return Palette.BUTTER
		TankModules.State.DESTROYED:
			return Palette.RED if fmod(_time, 0.5) < 0.3 else Palette.DUSK
	return Palette.MINT


func _paint(node: Node, color: Color) -> void:
	if _painted.get(node) != color:
		_painted[node] = color
		WireView.paint(node, color)
		(node.get_viewport() as WireView).refresh()


## A static schematic of the player's tank: coax fit, ERA left and every module in its state
## color. Nothing on it moves. Hull color follows armor; the engine flashes it when hurt.
func _update_xray() -> void:
	var p := world.player
	var m := p.modules
	if p.coax_tier != _shown_tier:
		_shown_tier = p.coax_tier
		_xray.set_coax_guns(Armament.tier_calibers(p.coax_tier))
		_painted.erase(_xray.coax_root)
		_rebuild_coax_view(Armament.tier_calibers(p.coax_tier))
	if not _tail_posed:
		# Settle the tail into its resting curl once; after that the drawing stays still.
		_tail_posed = true
		for _i in 60:
			_xray_tail.update(1.0 / 60.0, _xray.global_basis, 0.0)
		_tank_view.refresh()
	var tail_visible := not p.tail.destroyed or fmod(_time, 0.5) < 0.3
	if _xray_tail.visible != tail_visible:
		_xray_tail.visible = tail_visible
		_tank_view.refresh()
	var hull := _armor_color(p.hp / p.max_hp)
	if m.state("engine") != TankModules.State.OK and fmod(_time, 0.6) < 0.3:
		hull = _module_color(m.state("engine"))
	_paint(_xray.hull.get_child(0), hull)
	_paint(_xray.track_meshes[0], _module_color(m.state("track_l")))
	_paint(_xray.track_meshes[1], _module_color(m.state("track_r")))
	_paint(_xray.turret.get_child(0), _module_color(m.state("turret")))
	_paint(_xray.barrel, _module_color(m.state("breech")))
	_paint(_xray.coax_root, Palette.AMBER)
	_paint(_xray.rws, _module_color(m.state("laser")))
	_paint(_xray.fcs, _module_color(m.state("fcs")))
	# A lost FCS blinks red where it sat: without it there is no lock and no lead.
	var fcs_lost := m.state("fcs") == TankModules.State.DESTROYED
	var sensors := [m.laser_online(), not fcs_lost or fmod(_time, 0.5) < 0.3]
	if _xray.rws.visible != sensors[0] or _xray.fcs.visible != sensors[1]:
		_xray.rws.visible = sensors[0]
		_xray.fcs.visible = sensors[1]
		_tank_view.refresh()
	_paint(_xray_tail, _tail_color())


func _rebuild_coax_view(calibers: Array) -> void:
	for child in _coax_view.root.get_children():
		child.queue_free()
	for i in calibers.size():
		var caliber: int = calibers[i]
		var gun := MeshInstance3D.new()
		gun.mesh = TankModel._coax_mesh(caliber, {8: 1.3, 15: 1.8, 20: 2.4}[caliber])
		gun.position = Vector3(0, 0.35 - i * 0.35, 0)
		gun.material_override = WireView.line(Armament.GUNS[caliber].color)
		_coax_view.root.add_child(gun)
	_coax_view.refresh()


func _coax_label() -> String:
	var calibers := Armament.tier_calibers(world.player.coax_tier)
	var counts := {}
	for c in calibers:
		counts[c] = counts.get(c, 0) + 1
	var parts: Array[String] = []
	for c in counts:
		parts.append(("%d×" % counts[c] if counts[c] > 1 else "") + "%dMM" % c)
	return " + ".join(parts)


## Short codes for the loaded round, as on an ammunition rack.
const ROUND_CODES := {
	Armament.Round.APHE: "APHE", Armament.Round.HEAT: "HEAT", Armament.Round.CANISTER: "CAN",
	Armament.Round.DRAGON: "DRAGON", Armament.Round.APFSDS: "APFSDS", Armament.Round.AIRBURST: "AHEAD", Armament.Round.ATGM: "ATGM",
}


func _draw_weapons() -> void:
	var p := world.player
	var origin := Vector2(724, 432)
	var round_color: Color = Armament.ROUND_COLORS[p.current_round]
	_panel(Rect2(origin, Vector2(220, 96)), round_color)
	# Main gun: the loaded round's model, its magazine count, and the charge bar.
	if p.current_round != _shown_round:
		_shown_round = p.current_round
		var round_mesh := _round_view.show_mesh(Pickup.mesh_of(Armament.ROUND_IDS[p.current_round]), round_color)
		round_mesh.rotation.z = -PI * 0.5
	draw_texture(_round_view.get_texture(), origin + Vector2(4, 6))
	_text(origin + Vector2(52, 20), ROUND_CODES[p.current_round], round_color, 14)
	_text(origin + Vector2(52, 32), "∞" if p.current_round == Armament.Round.APHE else "×%d" % p.round_count, Palette.CREAM, 12)
	_bar(Rect2(origin + Vector2(120, 14), Vector2(90, 6)), p.charge, Palette.CREAM if p.charge >= 1.0 else Palette.STONE, 8)
	# Coax: the mounted guns themselves, then tier pips.
	draw_texture(_coax_view.get_texture(), origin + Vector2(4, 34))
	for i in Armament.COAX_TIERS.size():
		draw_rect(Rect2(origin + Vector2(120 + i * 15, 46), Vector2(11, 6)), Palette.BUTTER if i <= p.coax_tier else Palette.DUSK)
	# Laser CIWS: the RWS model and its heat; empty and dim until an RWS is mounted.
	var heat_color := Palette.MINT
	if p.ciws_overheated:
		heat_color = Palette.RED if fmod(_time, 0.3) < 0.15 else Palette.CORAL
	elif p.ciws_heat > 0.7:
		heat_color = Palette.BUTTER
	if not p.modules.laser_online():
		heat_color = Palette.DUSK
	_paint(_laser_view.root, heat_color)
	draw_texture(_laser_view.get_texture(), origin + Vector2(6, 68))
	if p.ciws_target != null and not p.ciws_overheated and fmod(_time, 0.1) < 0.06:
		draw_line(origin + Vector2(30, 78), origin + Vector2(40, 78), Palette.WHITE, 2.0)
	_bar(Rect2(origin + Vector2(42, 76), Vector2(130, 8)), p.ciws_heat, heat_color, 10)
	_text(origin + Vector2(178, 86), "×%d" % _intercepts, Palette.MINT if p.modules.laser_online() else Palette.DUSK, 12)


func _chevrons(at: Vector2, direction: float, color: Color) -> void:
	for i in 2:
		var x := at.x + i * 7.0 * direction
		draw_colored_polygon(PackedVector2Array([Vector2(x, at.y - 5), Vector2(x + 6 * direction, at.y), Vector2(x, at.y + 5)]), color)


const STYLE_COLORS: Array[Color] = [Palette.MIST, Palette.SKY, Palette.MINT, Palette.BUTTER, Palette.PEACH, Palette.CORAL, Palette.FUNGUS]


func _draw_score() -> void:
	var stats := world.stats
	_text(Vector2(16, 32), "%08d" % stats.score, Palette.CREAM, 24)
	_draw_style()


## ULTRAKILL-style meter on the right: rank letter, rank name, drain bar and the recent tricks.
func _draw_style() -> void:
	var stats := world.stats
	if stats.style <= 0.0 and stats.style_feed.is_empty():
		return
	var rank := stats.style_rank()
	var color := STYLE_COLORS[rank]
	var origin := Vector2(800, 60) + Vector2(randf_range(-4, 4), 0) * _style_drop / 0.3
	var panel := Rect2(origin, Vector2(144, 58 + stats.style_feed.size() * 14))
	_panel(panel, color)
	if _style_pop > 0.0:
		draw_rect(panel, Color(Palette.WHITE, _style_pop * 1.6))
	var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * rank * 0.5
	_text(origin + Vector2(8, 34) + jitter, stats.STYLE_LETTERS[rank], color, int(36 * (1.0 + _style_pop * 1.4)))
	var word: String = stats.STYLE_WORDS[rank]
	_text(origin + Vector2(62, 22), word, color, 12 if word.length() <= 10 else 9)
	_text(origin + Vector2(62, 38), "×%d" % stats.multiplier(), Palette.CREAM)
	_bar(Rect2(origin + Vector2(8, 44), Vector2(128, 5)), stats.style_progress(), color, 16)
	for i in stats.style_feed.size():
		var entry: Dictionary = stats.style_feed[i]
		var fade := clampf(2.5 - entry.age, 0.0, 1.0)
		var count: String = " ×%d" % entry.count if entry.count > 1 else ""
		_text(origin + Vector2(8, 66 + i * 14), "+ " + tr("STYLE_" + entry.name) + count, Color(Palette.CREAM, fade))


func _draw_progress() -> void:
	# A thin stage strip in the top right: sections as ticks, the tank as a pip.
	var origin := Vector2(700, 18)
	var width := 244.0
	draw_rect(Rect2(origin, Vector2(width, 3)), Palette.DUSK)
	for start: float in Course.SECTION_STARTS:
		draw_rect(Rect2(origin + Vector2(width * start / Course.ARENA_CENTER_D, -3), Vector2(2, 9)), Palette.MIST)
	var k := clampf(world.rail.d / Course.ARENA_CENTER_D, 0.0, 1.0)
	draw_rect(Rect2(origin + Vector2(width * k - 3, -3), Vector2(6, 9)), Palette.FUNGUS)


func _draw_boss() -> void:
	var boss := world.boss
	if not is_instance_valid(boss) or boss.dead:
		return
	var rect := Rect2(280, 14, 400, 10)
	_text(Vector2(280, 12), tr(boss.get_meta("title")), Palette.CORAL)
	_bar(rect, boss.hp / boss.max_hp, Palette.CORAL, 40)
	for mark: float in boss.get_meta("phase_marks", []):
		draw_rect(Rect2(rect.position + Vector2(rect.size.x * mark - 1, -3), Vector2(2, 16)), Palette.CREAM)
	# One chip per module under the bar: its name over its health; struck through once wrecked.
	var modules := boss.module_states()
	var width := rect.size.x / maxf(modules.size(), 1.0)
	for i in modules.size():
		var label: String = modules[i][0]
		var health: float = modules[i][1]
		var at := rect.position + Vector2(i * width, 16)
		var color := Palette.CORAL if health > 0.0 else Palette.STONE
		_text(at + Vector2(width * 0.5, 10), label, color, 9, HORIZONTAL_ALIGNMENT_CENTER, 0)
		_bar(Rect2(at + Vector2(3, 14), Vector2(width - 6, 3)), health, color, 8)
		if health <= 0.0:
			draw_line(at + Vector2(4, 6), at + Vector2(width - 4, 6), Palette.STONE, 1.0)


func _draw_shout() -> void:
	if _shout_time <= 0.0:
		return
	var age := _shout_total - _shout_time
	var punch := 1.0 + maxf(0.0, 0.15 - age) * 8.0
	var size := int(48 * punch)
	var w := font.get_string_size(_shout, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := Vector2(480 - w * 0.5, 210) + Vector2(randf_range(-3, 3), randf_range(-3, 3)) * clampf(1.0 - age * 3.0, 0.0, 1.0)
	var color := _shout_color if fmod(_time, 0.12) < 0.08 else Palette.WHITE
	for offset: Vector2 in [Vector2(-3, 0), Vector2(3, 0), Vector2(0, -3), Vector2(0, 4), Vector2(3, 4)]:
		draw_string(font, at + offset, _shout, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Palette.INK)
	draw_string(font, at, _shout, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, clampf(_shout_time * 4.0, 0.0, 1.0)))


func _draw_banner() -> void:
	if _banner_time > 0.0:
		var alpha := clampf(_banner_time * 3.0, 0.0, 1.0)
		var w := font.get_string_size(_banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		var y := 150.0
		draw_rect(Rect2(480 - w * 0.5 - 16, y - 24, w + 32, 34), Color(Palette.INK, 0.75 * alpha))
		_text(Vector2(480 - w * 0.5, y), _banner, Color(Palette.CREAM, alpha), 24)


const CALLSIGNS := {"FpvDrone": "FPV", "Ugv": "UGV", "Uav": "UAV", "Walker": "WALKER", "QuadMech": "QUAD",
	"Crawler": "CRAWLER", "Spitter": "SPITTER", "Colossus": "COLOSSUS", "Helicopter": "HELICOPTER", "Gunship": "GUNSHIP", "Flare": "FLARE"}
var _lock: Entity
var _lock_part := ""
var _lock_time := 0.0


## The fire-control sight: a gunner's chevron with stadia ticks and a live range readout, a
## segmented charge ring, the loaded round's code, where the barrel actually
## points, and an animated lock on the soft-locked target with its callsign, range and lead point.
func _draw_reticle() -> void:
	var p := world.player
	if p.dead:
		return
	var cam := world.camera
	var cursor := p.aim_screen * SCALE
	var charged_lock := is_instance_valid(p.charge_lock)
	# While charging, the brackets show what the charge has (or would) lock; otherwise the coax's soft lock.
	var target: Entity = p.charge_lock if charged_lock else (p.charge_candidate if p.is_charging() else p.coax_target)
	var color := Palette.HOSTILE if is_instance_valid(target) else Palette.CYAN
	# Star Fox's two sights, as a gunner's sight: both sit on the line the barrel points along, a
	# ranging box close in front of the muzzle and the chevron out at the range the sight rests on.
	# Lined up over a target, the gun is on it. The mouse only leaves a dot the turret swings toward.
	var far := p.sight_point()
	var near := p.model.muzzle.global_position.lerp(far, NEAR_SIGHT)
	_draw_cursor(cursor)
	if not cam.is_position_behind(near):
		_draw_near_sight(cam.unproject_position(near) * SCALE, Palette.CREAM)
	if cam.is_position_behind(far):
		return
	var c := cam.unproject_position(far) * SCALE
	if p.is_charging() and p.current_round in Tank.AREA_ROUNDS:
		# Rounds without a lock stack the same boxes on the far sight, where they will burst; the
		# canister's boxes are its cone's footprint, choking down step by step.
		var box := p.charge_ring_radius() * SCALE * 0.7 if p.current_round == Armament.Round.CANISTER else 16.0
		_draw_lock_boxes(c, box, p.charge, Armament.ROUND_COLORS[p.current_round])
	# Chevron and stadia.
	draw_polyline(PackedVector2Array([c + Vector2(-9, 9), c, c + Vector2(9, 9)]), color, 2.0)
	for side in [-1.0, 1.0]:
		draw_line(c + Vector2(side * 16, 0), c + Vector2(side * 44, 0), color, 2.0)
		for k in 3:
			var x: float = side * (22.0 + k * 8.0)
			draw_line(c + Vector2(x, -3), c + Vector2(x, 3), color, 1.0)
	draw_line(c + Vector2(0, 14), c + Vector2(0, 26), color, 2.0)
	# Range to whatever the sight rests on.
	if p.modules.lock_factor() > 0.0:
		_text(c + Vector2(50, -4), "%04d" % int(p.sight_range), color, 12)
	_text(c + Vector2(50, 10), ROUND_CODES[p.current_round], Armament.ROUND_COLORS[p.current_round], 12)
	# Lock: brackets snap in from wide when a new target (or a new module of it) is acquired.
	var part := p.charge_part if charged_lock else p.coax_part
	if target != _lock or part != _lock_part:
		_lock = target
		_lock_part = part
		_lock_time = 0.0
	_lock_time += get_process_delta_time()
	if not is_instance_valid(target) or cam.is_position_behind(target.hit_center()):
		return
	var focus := target.hit_center()
	var size := target.radius
	var name: String = CALLSIGNS.get(String(target.get_script().get_global_name()), "TGT")
	var parts := target.aim_parts()
	if parts.has(part):
		focus = parts[part][0]
		size = parts[part][1] * 0.5
		name = parts[part][2]
	if cam.is_position_behind(focus):
		return
	var center := cam.unproject_position(focus) * SCALE
	var k := clampf(_lock_time / 0.2, 0.0, 1.0)
	var s := lerpf(46.0, 18.0 + size * 3.0, ease(k, 0.4))
	var candidate := p.is_charging() and not charged_lock
	# A fresh charge lock clamps on white-hot, then settles to the friendly colour; a candidate is a thin hint.
	var bracket_color := Palette.HOSTILE
	if charged_lock:
		bracket_color = Palette.WHITE if _lock_time < 0.12 else Palette.FRIENDLY
	elif candidate:
		bracket_color = Color(Palette.FRIENDLY, 0.6)
	var width := 1.0 if candidate else 2.0
	if charged_lock:
		_draw_lock_boxes(center, s, p.charge, Armament.ROUND_COLORS[p.current_round])
	else:
		if not p.is_charging():
			_lock_boxes = 0
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var at := center + corner * s
			draw_line(at, at - Vector2(corner.x * 9.0, 0), bracket_color, width)
			draw_line(at, at - Vector2(0, corner.y * 9.0), bracket_color, width)
	if candidate:
		return
	if k >= 1.0:
		var distance := int(focus.distance_to(p.global_position))
		_text(center + Vector2(0, s + 14), "%s  %dm" % [name, distance], Palette.HOSTILE, 12, HORIZONTAL_ALIGNMENT_CENTER, 0)
		# Lead diamond for the main gun, while the FCS can still compute one.
		if not p.modules.lead_online():
			return
		var lead := p.lead_point(p.model.muzzle.global_position, p.shell_speed(), target, focus)
		if not cam.is_position_behind(lead):
			var lp := cam.unproject_position(lead) * SCALE
			draw_line(center, lp, Color(Palette.HOSTILE, 0.5), 1.0)
			draw_colored_polygon(PackedVector2Array([lp + Vector2(0, -6), lp + Vector2(6, 0), lp + Vector2(0, 6), lp + Vector2(-6, 0)]), Palette.BUTTER)
			draw_polyline(PackedVector2Array([lp + Vector2(0, -6), lp + Vector2(6, 0), lp + Vector2(0, 6), lp + Vector2(-6, 0), lp + Vector2(0, -6)]), Palette.INK, 1.0)


## The mouse cursor: just a dot, so the two barrel sights carry the aim.
func _draw_cursor(at: Vector2) -> void:
	draw_circle(at, 3.0, Palette.INK)
	draw_circle(at, 1.5, Palette.WHITE)


## How far along the way from the muzzle to the far sight the near sight sits (tuned live in the duel mode).
static var NEAR_SIGHT := 0.7


## The near sight: a gunner's ranging box, four corner brackets with a short tick at each side,
## drawn big because it is close, and always in the gunner's own pale color so it never reads as a
## mark on an enemy.
func _draw_near_sight(at: Vector2, color: Color) -> void:
	const HALF := 22.0
	const ARM := 8.0
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var c := at + corner * HALF
		for seg: Array in [[c, c - Vector2(corner.x * ARM, 0)], [c, c - Vector2(0, corner.y * ARM)]]:
			draw_line(seg[0], seg[1], Palette.INK, 4.0)
			draw_line(seg[0], seg[1], color, 2.0)
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
		draw_line(at + dir * (HALF + 3.0), at + dir * (HALF + 9.0), Palette.INK, 4.0)
		draw_line(at + dir * (HALF + 3.0), at + dir * (HALF + 9.0), color, 2.0)


## The charge, around the cursor at the radius it locks within: segments fill clockwise from the
## top; full, the ring closes solid with a notch at the top and pulses, and a thin outer arc drains
## to the moment the gun fires by itself (`auto_left`, 1 to 0).
## Ex-Zodiac style: the charge stacks up to LOCK_BOXES orange square sights on the lock, each one
## spinning in from wide as it is added (one at the lock, the last at full charge).
const LOCK_BOXES := 3
const LOCK_BOX_IN := 0.16 ## Seconds a new box takes to spin in and settle.
var _lock_boxes := 0
var _lock_box_times: Array[float] = [0.0, 0.0, 0.0]


## `tint` is the loaded round's color, so the sight says what is about to fire.
func _draw_lock_boxes(center: Vector2, size: float, charge: float, tint: Color) -> void:
	var count := Armament.stage(charge)
	while _lock_boxes < count:
		_lock_box_times[_lock_boxes] = _time
		_lock_boxes += 1
	_lock_boxes = mini(_lock_boxes, count)
	var full := charge >= 1.0
	for i in _lock_boxes:
		var k := clampf((_time - _lock_box_times[i]) / LOCK_BOX_IN, 0.0, 1.0)
		var settle := ease(k, 0.35)
		# Spins in a half turn as it lands, then keeps turning slowly, alternate boxes the other way.
		var angle := (1.0 - settle) * PI * 0.5 + _time * (0.8 + i * 0.5) * (1.0 if i % 2 == 0 else -1.0)
		var color := Palette.WHITE if k < 1.0 or (full and fmod(_time, 0.2) < 0.08) else tint
		_draw_lock_box(center, lerpf(size * 3.0, size * (1.0 + i * 0.32), settle), angle, color)
	# The next box is already on its way: it swings in from wide as the charge climbs to its step,
	# so even a round that fires on its first box shows that box locking in.
	if count < LOCK_BOXES:
		var steps := [0.0, Armament.STAGE_1, Armament.STAGE_2, 1.0]
		var progress := clampf(inverse_lerp(steps[count], steps[count + 1], charge), 0.0, 1.0)
		var settle := ease(progress, 0.6)
		var color := Color(Palette.WHITE, 0.35 + 0.65 * progress)
		_draw_lock_box(center, lerpf(size * 3.4, size * (1.0 + count * 0.32), settle), (1.0 - settle) * PI + _time * 0.8, color)


## One lock box: four corner brackets of a square `half` wide, turned by `angle`.
func _draw_lock_box(center: Vector2, half: float, angle: float, color: Color) -> void:
	var corners: Array[Vector2] = []
	for c in 4:
		corners.append(center + Vector2(half, 0).rotated(angle + PI * 0.25 + c * PI * 0.5) * sqrt(2.0))
	for c in 4:
		var a := corners[c]
		var b := corners[(c + 1) % 4]
		var arm := (b - a) * 0.28
		for seg: Array in [[a, a + arm], [b, b - arm]]:
			draw_line(seg[0], seg[1], Color(Palette.INK, color.a), 5.0)
			draw_line(seg[0], seg[1], color, 2.0)


func _draw_hit_marker() -> void:
	if world.player.dead or (_hit_marker <= 0.0 and _kill_marker <= 0.0):
		return
	var killed := _kill_marker > 0.0
	var at := world.player.aim_screen * SCALE
	var color := Palette.HOT if killed else Palette.WHITE
	var outer := 22.0 if killed else 14.0
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		draw_line(at + corner * 7.0, at + corner * outer, Palette.INK, 6.0)
		draw_line(at + corner * 7.0, at + corner * outer, color, 3.0)


func _draw_threats() -> void:
	var cam := world.camera
	var center := size * 0.5
	for projectile in world.projectiles:
		if projectile.team == Entity.Team.PLAYER or not projectile.interceptable or projectile.is_queued_for_deletion():
			continue
		_edge_arrow(cam, projectile.global_position, Palette.CORAL, center)
	for enemy in world.enemies:
		if enemy is Flare:
			continue
		if enemy is FpvDrone and (enemy as FpvDrone).state != FpvDrone.State.APPROACH:
			_edge_arrow(cam, enemy.hit_center(), Palette.RED, center, 1.4)
		elif enemy.has_meta("locking") and enemy.get_meta("locking"):
			_edge_arrow(cam, enemy.hit_center(), Palette.BUTTER, center, 1.4)
		elif enemy.hit_center().distance_to(world.player.global_position) < THREAT_RANGE:
			# Anything close but out of view gets a marker, sized by how near it is.
			var near := 1.0 - enemy.hit_center().distance_to(world.player.global_position) / THREAT_RANGE
			_edge_arrow(cam, enemy.hit_center(), Palette.HOSTILE, center, 0.7 + near * 0.6, true)
	for warning in _incoming:
		_draw_incoming(cam, warning, center)
	_draw_ciws_lock(cam)


const THREAT_RANGE := 140.0
const INCOMING_TIME := 1.8


## Direction on screen toward a world point, and whether it is out of view.
func _screen_direction(cam: Camera3D, point: Vector3, center: Vector2) -> Array:
	var behind := cam.is_position_behind(point)
	var screen := cam.unproject_position(point) * SCALE
	var inside := Rect2(Vector2(24, 24), size - Vector2(48, 48)).has_point(screen)
	var dir := (screen - center).normalized()
	if behind:
		dir = -dir
		if dir.y < 0.3:
			dir = (dir + Vector2(0, 1)).normalized()
	return [dir, inside and not behind]


func _edge_point(center: Vector2, dir: Vector2, inset := 0.45) -> Vector2:
	return center + dir * minf(size.x * inset / maxf(absf(dir.x), 0.01), size.y * inset / maxf(absf(dir.y), 0.01))


func _edge_arrow(cam: Camera3D, point: Vector3, color: Color, center: Vector2, scale := 1.0, steady := false) -> void:
	var found := _screen_direction(cam, point, center)
	if found[1]:
		return
	var dir: Vector2 = found[0]
	var at := _edge_point(center, dir)
	var side := Vector2(-dir.y, dir.x)
	if steady or fmod(_time, 0.25) < 0.17:
		var tip := PackedVector2Array([at + dir * 10 * scale, at - dir * 4 * scale + side * 7 * scale, at - dir * 4 * scale - side * 7 * scale])
		var ink := PackedVector2Array()
		for p in tip:
			ink.append(p + (p - at).normalized() * 2.0)
		draw_colored_polygon(ink, Palette.INK)
		draw_colored_polygon(tip, color)


## A big flashing double chevron and callout at the edge a wave is coming from, before it shows.
func _draw_incoming(cam: Camera3D, warning: Dictionary, center: Vector2) -> void:
	if fmod(warning.time, 0.3) > 0.2:
		return
	var dir: Vector2 = _screen_direction(cam, warning.position, center)[0]
	var at := _edge_point(center, dir, 0.4)
	var side := Vector2(-dir.y, dir.x)
	for k in 2:
		var o := at + dir * (k * 16.0 - 8.0)
		draw_colored_polygon(PackedVector2Array([o + dir * 14, o - dir * 4 + side * 18, o - dir * 4 + side * 10, o + dir * 6, o - dir * 4 - side * 10, o - dir * 4 - side * 18]), Palette.HOSTILE)
	_text(at - dir * 34 + Vector2(0, 4), tr("CALLOUT_INCOMING"), Palette.HOSTILE, 14, HORIZONTAL_ALIGNMENT_CENTER, 0)


## Brackets on whatever the laser is burning, so its work is visible.
func _draw_ciws_lock(cam: Camera3D) -> void:
	var target: Object = world.player.ciws_target
	if not is_instance_valid(target) or not target is Node3D:
		return
	var point := (target as Node3D).global_position
	if cam.is_position_behind(point):
		return
	var at := cam.unproject_position(point) * SCALE
	var r := 9.0
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var c: Vector2 = at + corner * r
		draw_line(c, c - Vector2(corner.x * 5, 0), Palette.MINT, 2.0)
		draw_line(c, c - Vector2(0, corner.y * 5), Palette.MINT, 2.0)


func _draw_popups() -> void:
	var cam := world.camera
	for popup in _popups:
		var pos: Vector3 = popup.position
		if cam.is_position_behind(pos):
			continue
		var screen := cam.unproject_position(pos) * SCALE - Vector2(0, popup.time * 30.0)
		var color: Color = popup.get("color", Palette.BUTTER if popup.combo < 12 else Palette.FUNGUS)
		_text(screen, popup.text, color, 12, HORIZONTAL_ALIGNMENT_CENTER, 0)


func _draw_storm() -> void:
	# Drifting spore motes over the view while a spore storm lasts.
	for i in int(80 * _storm):
		var seed_value := float(i) * 12.9898
		var x := fposmod(sin(seed_value) * 43758.5 + _time * (40.0 + fposmod(seed_value, 30.0)), size.x)
		var y := fposmod(cos(seed_value) * 24634.6 + _time * 16.0, size.y)
		draw_rect(Rect2(x, y, 2, 2), [Palette.FUNGUS, Palette.BLUSH, Palette.LILAC][i % 3])
