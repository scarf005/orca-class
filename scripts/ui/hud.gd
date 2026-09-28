class_name Hud
extends Control
## In-game HUD drawn by hand at 960×540: armor, weapons, laser heat, throttle, score and combo,
## the reticle with lead marker, radio chatter, boss bar, threat arrows and score popups.

const SCALE := 2.0 ## Screen pixels per 3D-view pixel.
const RADIO_TIME := 3.6

var world: World
var font: Font
var _radio_queue: Array[StringName] = []
var _radio_line := &""
var _radio_time := 0.0
var _popups: Array[Dictionary] = []
var _banner := ""
var _banner_time := 0.0
var _hint := ""
var _hint_time := 0.0
var _armor_shake := 0.0
var _last_armor := 100.0
var _time := 0.0
var _storm := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = get_theme_default_font()
	world.radio.connect(_on_radio)
	world.scored.connect(_on_scored)
	world.player.pickup_collected.connect(_on_pickup)
	world.director.section_changed.connect(func(section: Course.Section) -> void: banner(tr("SECTION_%d" % section)))
	world.director.checkpoint_reached.connect(func(_name: String) -> void: banner(tr("CHECKPOINT")))


func banner(text: String, time := 2.6) -> void:
	_banner = text
	_banner_time = time


func hint(text: String, time := 4.0) -> void:
	_hint = text
	_hint_time = time


func set_storm(amount: float) -> void:
	_storm = amount


func _on_radio(line: StringName) -> void:
	if line == _radio_line or line in _radio_queue:
		return
	_radio_queue.append(line)


func _on_scored(points: int, position: Vector3, combo: int) -> void:
	if points <= 0:
		return
	_popups.append({"text": str(points), "position": position, "time": 0.0, "combo": combo})
	if combo > 0 and combo % 10 == 0:
		Sfx.ui("combo", 0.0, 1.0 + combo / 60.0)


func _on_pickup(id: String) -> void:
	var name := tr("PICKUP_" + id.to_upper())
	if Armament.round_from_id(id) != Armament.Round.APHE:
		name += " ×%d" % world.player.round_count
	elif id == "coax":
		name = tr("PICKUP_COAX") + " " + _coax_label()
	banner(name, 1.6)


func _process(delta: float) -> void:
	_time += delta
	_banner_time -= delta
	_hint_time -= delta
	_radio_time -= delta
	if _radio_time <= 0.0 and not _radio_queue.is_empty():
		_radio_line = _radio_queue.pop_front()
		_radio_time = RADIO_TIME
		Sfx.ui("ai")
	for popup in _popups:
		popup.time += delta
	_popups = _popups.filter(func(p: Dictionary) -> bool: return p.time < 0.9)
	var armor := world.player.hp
	if armor < _last_armor:
		_armor_shake = 0.3
	_last_armor = armor
	_armor_shake = maxf(0.0, _armor_shake - delta)
	queue_redraw()


func _draw() -> void:
	if world == null or world.player == null:
		return
	if _storm > 0.0:
		_draw_storm()
	_draw_reticle()
	_draw_threats()
	_draw_popups()
	_draw_status()
	_draw_modules()
	_draw_weapons()
	_draw_score()
	_draw_progress()
	_draw_boss()
	_draw_radio()
	_draw_banner()


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
	var origin := Vector2(16, 480) + shake
	_panel(Rect2(origin, Vector2(210, 48)), Palette.MINT)
	var armor := p.hp / p.max_hp
	var color := Palette.MINT if armor > 0.5 else (Palette.BUTTER if armor > 0.25 else Palette.RED)
	if armor <= 0.25 and fmod(_time, 0.4) < 0.2:
		color = Palette.CORAL
	_icon_shield(origin + Vector2(10, 8), color)
	_bar(Rect2(origin + Vector2(28, 9), Vector2(172, 10)), armor, color)
	var tail := p.tail.hp / Tail.MAX_HP
	var tail_color := Palette.FUNGUS if not p.tail.is_hurt() else Palette.CORAL
	_icon_tail(origin + Vector2(10, 28), tail_color if p.tail.cooldown <= 0.0 else Palette.STONE)
	_bar(Rect2(origin + Vector2(28, 29), Vector2(84, 6)), tail, tail_color, 10)
	# Lives as small hull silhouettes.
	for i in world.stats.lives:
		var at := origin + Vector2(124 + i * 22, 32)
		draw_rect(Rect2(at, Vector2(16, 6)), Palette.HULL)
		draw_rect(Rect2(at + Vector2(4, -3), Vector2(7, 3)), Palette.HULL_LIGHT)
		draw_rect(Rect2(at + Vector2(10, -2), Vector2(8, 1)), Palette.HULL_LIGHT)
	# Throttle meter between brake and boost chevrons.
	var rail := world.rail
	var m := Vector2(400, 510)
	_panel(Rect2(m - Vector2(8, 10), Vector2(176, 22)), Palette.SKY)
	var meter_color := Palette.SKY
	if rail.is_meter_locked():
		meter_color = Palette.STONE
	elif rail.throttle == 1:
		meter_color = Palette.BUTTER
	elif rail.throttle == -1:
		meter_color = Palette.PERIWINKLE
	_chevrons(m + Vector2(7, 1), -1.0, Palette.PERIWINKLE if rail.throttle == -1 else Palette.STONE)
	_bar(Rect2(m + Vector2(24, -3), Vector2(112, 8)), rail.meter, meter_color, 12)
	_chevrons(m + Vector2(146, 1), 1.0, Palette.BUTTER if rail.throttle == 1 else Palette.STONE)


func _module_color(state: TankModules.State) -> Color:
	match state:
		TankModules.State.DAMAGED:
			return Palette.BUTTER
		TankModules.State.DESTROYED:
			return Palette.RED if fmod(_time, 0.5) < 0.3 else Palette.DUSK
	return Palette.MINT


## Top-down schematic of the tank, front up: ERA bricks, tracks, engine, turret, breech, laser, tail.
func _draw_modules() -> void:
	var p := world.player
	var m := p.modules
	var origin := Vector2(232, 452)
	_panel(Rect2(origin, Vector2(64, 76)), Palette.MINT)
	var c := origin + Vector2(32, 34)
	draw_rect(Rect2(c + Vector2(-10, -20), Vector2(20, 38)), Palette.DUSK)
	draw_rect(Rect2(c + Vector2(-16, -18), Vector2(5, 34)), _module_color(m.state("track_l")))
	draw_rect(Rect2(c + Vector2(11, -18), Vector2(5, 34)), _module_color(m.state("track_r")))
	draw_rect(Rect2(c + Vector2(-7, 8), Vector2(14, 8)), _module_color(m.state("engine")))
	draw_circle(c + Vector2(0, -3), 7.0, _module_color(m.state("turret")))
	draw_rect(Rect2(c + Vector2(-1.5, -24), Vector2(3, 16)), _module_color(m.state("breech")))
	draw_rect(Rect2(c + Vector2(-6, -3), Vector2(3, 3)), _module_color(m.state("laser")))
	for i in TankModules.ERA.front:
		draw_rect(Rect2(c + Vector2(-10 + i * 5, -27), Vector2(4, 3)), Palette.SKY if i < m.era.front else Palette.DUSK)
	for i in TankModules.ERA.left:
		draw_rect(Rect2(c + Vector2(-21, -16 + i * 9), Vector2(3, 7)), Palette.SKY if i < m.era.left else Palette.DUSK)
		draw_rect(Rect2(c + Vector2(18, -16 + i * 9), Vector2(3, 7)), Palette.SKY if i < m.era.right else Palette.DUSK)
	var tail_color := Palette.FUNGUS if not p.tail.is_hurt() else Palette.CORAL
	if p.tail.destroyed:
		tail_color = Palette.RED if fmod(_time, 0.5) < 0.3 else Palette.DUSK
	for i in 3:
		draw_rect(Rect2(c + Vector2(-2 + i * 2, 19 + i * 4), Vector2(4, 4)), tail_color)


func _coax_label() -> String:
	var calibers := Armament.tier_calibers(world.player.coax_tier)
	var counts := {}
	for c in calibers:
		counts[c] = counts.get(c, 0) + 1
	var parts: Array[String] = []
	for c in counts:
		parts.append(("%d×" % counts[c] if counts[c] > 1 else "") + "%dMM" % c)
	return " + ".join(parts)


func _draw_weapons() -> void:
	var p := world.player
	var origin := Vector2(734, 456)
	var round_color: Color = Armament.ROUND_COLORS[p.current_round]
	_panel(Rect2(origin, Vector2(210, 72)), round_color)
	# Main gun: round icon, magazine pips (infinity for APHE) and a reload bar.
	_icon_shell(origin + Vector2(10, 7), round_color)
	if p.current_round != Armament.Round.APHE:
		for i in p.round_count:
			draw_rect(Rect2(origin + Vector2(30 + i * 8, 9), Vector2(5, 11)), round_color)
	else:
		_text(origin + Vector2(30, 20), "∞", Palette.STONE)
	var reload := 1.0 - p.reload / Armament.RELOAD
	_bar(Rect2(origin + Vector2(110, 12), Vector2(90, 6)), reload, Palette.CREAM if reload >= 1.0 else Palette.STONE, 8)
	# Coax: one bullet glyph per mounted gun, sized by caliber, plus tier pips.
	var x := 10.0
	for caliber in Armament.tier_calibers(p.coax_tier):
		_icon_bullet(origin + Vector2(x, 28), caliber, Armament.GUNS[caliber].color)
		x += 8.0 + caliber * 0.35
	for i in Armament.COAX_TIERS.size():
		draw_rect(Rect2(origin + Vector2(110 + i * 15, 33), Vector2(11, 6)), Palette.BUTTER if i <= p.coax_tier else Palette.DUSK)
	# Laser CIWS heat.
	var heat_color := Palette.MINT
	if p.ciws_overheated:
		heat_color = Palette.RED if fmod(_time, 0.3) < 0.15 else Palette.CORAL
	elif p.ciws_heat > 0.7:
		heat_color = Palette.BUTTER
	_icon_laser(origin + Vector2(10, 52), heat_color, p.ciws_target != null and not p.ciws_overheated)
	_bar(Rect2(origin + Vector2(30, 54), Vector2(170, 8)), p.ciws_heat, heat_color, 13)


func _draw_score() -> void:
	var stats := world.stats
	_text(Vector2(16, 32), "%08d" % stats.score, Palette.CREAM, 24)
	if stats.combo > 1:
		var mult := stats.multiplier()
		var color := [Palette.CREAM, Palette.BUTTER, Palette.PEACH, Palette.CORAL, Palette.FUNGUS][mini(mult - 1, 4)] as Color
		_text(Vector2(16, 60), "×%d" % mult, color, 24)
		_text(Vector2(64, 58), str(stats.combo), color)
		draw_rect(Rect2(16, 66, 96 * stats.combo_timer / RunStats.COMBO_WINDOW, 3), color)


func _draw_progress() -> void:
	# A thin stage strip in the top right: sections as ticks, the tank as a pip.
	var origin := Vector2(700, 18)
	var width := 244.0
	draw_rect(Rect2(origin, Vector2(width, 3)), Palette.DUSK)
	for start: float in Course.SECTION_STARTS:
		draw_rect(Rect2(origin + Vector2(width * start / Course.ARENA_CENTER_D, -3), Vector2(2, 9)), Palette.MIST)
	var k := clampf(world.rail.d / Course.ARENA_CENTER_D, 0.0, 1.0)
	draw_rect(Rect2(origin + Vector2(width * k - 3, -3), Vector2(6, 9)), Palette.FUNGUS)


func _icon_shield(at: Vector2, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([at, at + Vector2(12, 0), at + Vector2(12, 7), at + Vector2(6, 12), at + Vector2(0, 7)]), color)
	draw_rect(Rect2(at + Vector2(5, 2), Vector2(2, 7)), Palette.INK)


func _icon_tail(at: Vector2, color: Color) -> void:
	for i in 3:
		draw_rect(Rect2(at + Vector2(i * 3, 6 - i * 3), Vector2(4, 4)), color)
	draw_colored_polygon(PackedVector2Array([at + Vector2(9, -2), at + Vector2(14, -3), at + Vector2(11, 1)]), color)
	draw_colored_polygon(PackedVector2Array([at + Vector2(9, 2), at + Vector2(14, 4), at + Vector2(10, 4)]), color)


func _icon_shell(at: Vector2, color: Color) -> void:
	draw_rect(Rect2(at + Vector2(0, 4), Vector2(9, 6)), Palette.OCHRE)
	draw_colored_polygon(PackedVector2Array([at + Vector2(9, 3), at + Vector2(15, 7), at + Vector2(9, 11)]), color)


func _icon_bullet(at: Vector2, caliber: int, color: Color) -> void:
	var h := 6.0 + caliber * 0.4
	var w := 2.0 + caliber * 0.2
	draw_rect(Rect2(at + Vector2(0, 14 - h * 0.7), Vector2(w, h * 0.7)), Palette.OCHRE)
	draw_rect(Rect2(at + Vector2(0, 14 - h), Vector2(w, h * 0.3)), color)


func _icon_laser(at: Vector2, color: Color, firing: bool) -> void:
	draw_rect(Rect2(at + Vector2(0, 2), Vector2(6, 8)), Palette.HULL_LIGHT)
	draw_rect(Rect2(at + Vector2(6, 4), Vector2(3, 4)), color)
	if firing and fmod(_time, 0.1) < 0.06:
		draw_line(at + Vector2(9, 6), at + Vector2(18, 6), Palette.WHITE, 2.0)


func _chevrons(at: Vector2, direction: float, color: Color) -> void:
	for i in 2:
		var x := at.x + i * 7.0 * direction
		draw_colored_polygon(PackedVector2Array([Vector2(x, at.y - 5), Vector2(x + 6 * direction, at.y), Vector2(x, at.y + 5)]), color)


func _draw_boss() -> void:
	var boss := world.boss
	if not is_instance_valid(boss) or boss.dead:
		return
	var rect := Rect2(280, 14, 400, 10)
	_text(Vector2(280, 12), tr(boss.get_meta("title")), Palette.CORAL)
	_bar(rect, boss.hp / boss.max_hp, Palette.CORAL, 40)
	for mark: float in boss.get_meta("phase_marks", []):
		draw_rect(Rect2(rect.position + Vector2(rect.size.x * mark - 1, -3), Vector2(2, 16)), Palette.CREAM)


## Combat assist announcements: a terse terminal line beside a waveform, typed out.
func _draw_radio() -> void:
	if _radio_time <= 0.0 or _radio_line == &"":
		return
	var text := tr(_radio_line)
	var shown := int(clampf((RADIO_TIME - _radio_time) * 45.0, 0.0, text.length()))
	var warning := text.begins_with("경고") or text.begins_with("Warning")
	var accent := Palette.CORAL if warning else Palette.MINT
	var origin := Vector2(16, 400)
	var slide := clampf((RADIO_TIME - _radio_time) * 8.0, 0.0, 1.0) * clampf(_radio_time * 6.0, 0.0, 1.0)
	origin.x -= (1.0 - slide) * 380.0
	_panel(Rect2(origin, Vector2(370, 34)), accent)
	for i in 8:
		var h := absf(sin(_time * 22.0 + i * 1.7)) * 16.0 * (1.0 if shown < text.length() else 0.25) + 2.0
		draw_rect(Rect2(origin + Vector2(8 + i * 3, 19 - h * 0.5), Vector2(2, h)), accent)
	var caret := "_" if fmod(_time, 0.5) < 0.25 else ""
	_text(origin + Vector2(40, 23), text.substr(0, shown) + caret, Palette.PEACH if warning else Palette.CREAM, 12, HORIZONTAL_ALIGNMENT_LEFT, 322)


func _draw_banner() -> void:
	if _banner_time > 0.0:
		var alpha := clampf(_banner_time * 3.0, 0.0, 1.0)
		var w := font.get_string_size(_banner, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		var y := 150.0
		draw_rect(Rect2(480 - w * 0.5 - 16, y - 24, w + 32, 34), Color(Palette.INK, 0.75 * alpha))
		_text(Vector2(480 - w * 0.5, y), _banner, Color(Palette.CREAM, alpha), 24)
	if _hint_time > 0.0:
		var w := font.get_string_size(_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		_text(Vector2(480 - w * 0.5, 430), _hint, Color(Palette.BUTTER, clampf(_hint_time, 0.0, 1.0)))


func _draw_reticle() -> void:
	var p := world.player
	if p.dead:
		return
	var c := p.aim_screen * SCALE
	var ready := p.reload <= 0.0
	var color := Palette.CREAM if ready else Palette.MIST
	if is_instance_valid(p.aim_target):
		color = Palette.CORAL
	# Crosshair with a gap; the ring fills as the cannon reloads.
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + dir * 6, c + dir * 12, color, 2.0)
	draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), color)
	var reload := 1.0 - p.reload / Armament.RELOAD
	draw_arc(c, 18, -PI * 0.5, -PI * 0.5 + TAU * reload, 24, Armament.ROUND_COLORS[p.current_round] if ready else Palette.STONE, 2.0)
	var target := p.aim_target
	if is_instance_valid(target):
		var cam := world.camera
		var center := cam.unproject_position(target.hit_center()) * SCALE
		var s := 14.0
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var at := center + corner * s
			draw_rect(Rect2(at - Vector2(1, 1), Vector2(2, 2)), Palette.CORAL)
			draw_line(at, at - Vector2(corner.x * 5, 0), Palette.CORAL, 2.0)
			draw_line(at, at - Vector2(0, corner.y * 5), Palette.CORAL, 2.0)
		# Lead marker for the cannon.
		var lead := p.lead_point(p.model.muzzle.global_position, Armament.SHELL_SPEED, target)
		if not cam.is_position_behind(lead):
			var lp := cam.unproject_position(lead) * SCALE
			draw_line(center, lp, Color(Palette.CORAL, 0.5), 1.0)
			draw_colored_polygon(PackedVector2Array([lp + Vector2(0, -5), lp + Vector2(5, 0), lp + Vector2(0, 5), lp + Vector2(-5, 0)]), Palette.BUTTER)


func _draw_threats() -> void:
	var cam := world.camera
	var center := size * 0.5
	for projectile in world.projectiles:
		if projectile.team == Entity.Team.PLAYER or not projectile.interceptable or projectile.is_queued_for_deletion():
			continue
		_edge_arrow(cam, projectile.global_position, Palette.CORAL, center)
	for enemy in world.enemies:
		if enemy is FpvDrone and (enemy as FpvDrone).state != FpvDrone.State.APPROACH:
			_edge_arrow(cam, enemy.hit_center(), Palette.RED, center)
		elif enemy.has_meta("locking") and enemy.get_meta("locking"):
			_edge_arrow(cam, enemy.hit_center(), Palette.BUTTER, center)


func _edge_arrow(cam: Camera3D, point: Vector3, color: Color, center: Vector2) -> void:
	var behind := cam.is_position_behind(point)
	var screen := cam.unproject_position(point) * SCALE
	var inside := Rect2(Vector2(24, 24), size - Vector2(48, 48)).has_point(screen)
	if inside and not behind:
		return
	var dir := (screen - center).normalized()
	if behind:
		dir = -dir
		if dir.y < 0.3:
			dir = (dir + Vector2(0, 1)).normalized()
	var at := center + dir * minf(size.x * 0.45 / maxf(absf(dir.x), 0.01), size.y * 0.45 / maxf(absf(dir.y), 0.01))
	var side := Vector2(-dir.y, dir.x)
	if fmod(_time, 0.25) < 0.17:
		draw_colored_polygon(PackedVector2Array([at + dir * 10, at - dir * 4 + side * 7, at - dir * 4 - side * 7]), color)


func _draw_popups() -> void:
	var cam := world.camera
	for popup in _popups:
		var pos: Vector3 = popup.position
		if cam.is_position_behind(pos):
			continue
		var screen := cam.unproject_position(pos) * SCALE - Vector2(0, popup.time * 30.0)
		_text(screen, popup.text, Palette.BUTTER if popup.combo < 12 else Palette.FUNGUS, 12, HORIZONTAL_ALIGNMENT_CENTER, 0)


func _draw_storm() -> void:
	# Drifting spore motes over the view while a spore storm lasts.
	for i in int(80 * _storm):
		var seed_value := float(i) * 12.9898
		var x := fposmod(sin(seed_value) * 43758.5 + _time * (40.0 + fposmod(seed_value, 30.0)), size.x)
		var y := fposmod(cos(seed_value) * 24634.6 + _time * 16.0, size.y)
		draw_rect(Rect2(x, y, 2, 2), [Palette.FUNGUS, Palette.BLUSH, Palette.LILAC][i % 3])
