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
var _shout := ""
var _shout_time := 0.0
var _shout_total := 1.0
var _shout_color := Palette.AMBER
var _hint := ""
var _hint_time := 0.0
var _armor_shake := 0.0
var _last_armor := 100.0
var _time := 0.0
var _storm := 0.0
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
	_laser_view.show_mesh(TankModel._rws_mesh(), Palette.MINT)
	world.radio.connect(_on_radio)
	world.scored.connect(_on_scored)
	world.player.pickup_collected.connect(_on_pickup)
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
	var name := tr("PICKUP_" + id.to_upper()) + "!!"
	if id == "coax":
		name = _coax_label() + "!!"
	var color := Palette.AMBER
	if Armament.round_from_id(id) != Armament.Round.APHE:
		color = Armament.ROUND_COLORS[Armament.round_from_id(id)]
	shout(name, color)


func _process(delta: float) -> void:
	_time += delta
	_banner_time -= delta
	_shout_time -= delta
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
	_draw_weapons()
	_draw_score()
	_draw_progress()
	_draw_boss()
	_draw_radio()
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
	_update_xray(delta_time())
	draw_texture(_tank_view.get_texture(), origin + Vector2(8, 2))
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


var _last_draw := 0


func delta_time() -> float:
	var now := Time.get_ticks_msec()
	var delta := clampf((now - _last_draw) / 1000.0, 0.0, 0.1)
	_last_draw = now
	return delta


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


## Mirrors the player's tank onto the x-ray: turret and gun aim, coax fit, ERA left, tail pose,
## and every module in its state color. Hull color follows armor; the engine flashes it when hurt.
func _update_xray(delta: float) -> void:
	var p := world.player
	var m := p.modules
	if p.coax_tier != _shown_tier:
		_shown_tier = p.coax_tier
		_xray.set_coax_guns(Armament.tier_calibers(p.coax_tier))
		_painted.erase(_xray.coax_root)
		_rebuild_coax_view(Armament.tier_calibers(p.coax_tier))
	_xray.turret.rotation.y = p.model.turret.rotation.y
	_xray.gun_pivot.rotation.x = p.model.gun_pivot.rotation.x
	_xray.set_era(m.era)
	_xray_tail.update(delta, _xray.global_basis, 0.0)
	_xray_tail.visible = not p.tail.destroyed or fmod(_time, 0.5) < 0.3
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
	for facing in _xray.era_blocks:
		for brick in _xray.era_blocks[facing]:
			_paint(brick, Palette.SKY)
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
	var origin := Vector2(724, 432)
	var round_color: Color = Armament.ROUND_COLORS[p.current_round]
	_panel(Rect2(origin, Vector2(220, 96)), round_color)
	# Main gun: the loaded round's model, its magazine count, and the reload bar.
	if p.current_round != _shown_round:
		_shown_round = p.current_round
		var round_mesh := _round_view.show_mesh(Pickup.mesh_of(Armament.ROUND_IDS[p.current_round]), round_color)
		round_mesh.rotation.z = -PI * 0.5
	(_round_view.root.get_child(-1) as Node3D).rotation.x += 0.02
	draw_texture(_round_view.get_texture(), origin + Vector2(4, 6))
	_text(origin + Vector2(52, 24), "∞" if p.current_round == Armament.Round.APHE else "×%d" % p.round_count, round_color)
	var reload := 1.0 - p.reload / (Armament.RELOAD * p.modules.reload_factor())
	_bar(Rect2(origin + Vector2(120, 14), Vector2(90, 6)), reload, Palette.CREAM if reload >= 1.0 else Palette.STONE, 8)
	# Coax: the mounted guns themselves, then tier pips.
	draw_texture(_coax_view.get_texture(), origin + Vector2(4, 34))
	for i in Armament.COAX_TIERS.size():
		draw_rect(Rect2(origin + Vector2(120 + i * 15, 46), Vector2(11, 6)), Palette.BUTTER if i <= p.coax_tier else Palette.DUSK)
	# Laser CIWS: the RWS model and its heat.
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
	_bar(Rect2(origin + Vector2(42, 76), Vector2(168, 8)), p.ciws_heat, heat_color, 13)


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
	var origin := Vector2(800, 60)
	_panel(Rect2(origin, Vector2(144, 58 + stats.style_feed.size() * 14)), color)
	var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * rank * 0.5
	_text(origin + Vector2(8, 34) + jitter, stats.STYLE_LETTERS[rank], color, 36)
	_text(origin + Vector2(62, 22), tr("STYLE_RANK_%d" % rank), color)
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


## Combat assist announcements: a terse terminal line beside a waveform, typed out.
func _draw_radio() -> void:
	if _radio_time <= 0.0 or _radio_line == &"":
		return
	var text := tr(_radio_line)
	var shown := int(clampf((RADIO_TIME - _radio_time) * 45.0, 0.0, text.length()))
	var warning := text.begins_with("경고") or text.begins_with("Warning")
	var accent := Palette.CORAL if warning else Palette.MINT
	var origin := Vector2(16, 374)
	var slide := clampf((RADIO_TIME - _radio_time) * 8.0, 0.0, 1.0) * clampf(_radio_time * 6.0, 0.0, 1.0)
	origin.x -= (1.0 - slide) * 380.0
	_panel(Rect2(origin, Vector2(370, 34)), accent)
	for i in 8:
		var h := absf(sin(_time * 22.0 + i * 1.7)) * 16.0 * (1.0 if shown < text.length() else 0.25) + 2.0
		draw_rect(Rect2(origin + Vector2(8 + i * 3, 19 - h * 0.5), Vector2(2, h)), accent)
	var caret := "_" if fmod(_time, 0.5) < 0.25 else ""
	_text(origin + Vector2(40, 23), text.substr(0, shown) + caret, Palette.PEACH if warning else Palette.CREAM, 12, HORIZONTAL_ALIGNMENT_LEFT, 322)


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
