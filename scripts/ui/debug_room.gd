class_name DebugRoom
extends Control
## A gallery of every model and effect in labeled rows on a flat checkered floor (10 m squares).
## Fly with WASD (Q/E down/up, Shift fast), look by dragging with the right mouse button,
## jump between rows with 1-9. Left click fires the main gun from the camera; the mouse wheel
## picks the round. Effect stations replay every two seconds.
## Run: godot --path . -- --debug-room

const START_D := -440.0 ## On the long straight before the stage start, so the rows line up.
const ROWS := ["TANK", "ENEMIES", "BOSSES", "PICKUPS", "PROPS", "BUILDINGS", "FUNGUS", "PROJECTILES", "VFX"]
## Per row: distance ahead of the previous row, camera distance back, camera height.
const LAYOUT := [[0.0, 16.0, 6.0], [34.0, 34.0, 10.0], [44.0, 48.0, 20.0], [44.0, 16.0, 3.5], [30.0, 30.0, 11.0], [40.0, 46.0, 18.0], [52.0, 42.0, 16.0], [44.0, 17.0, 3.0], [30.0, 62.0, 22.0]]

var view := DitherView.new()
var world: World
var _row_d: Array[float] = []
var _yaw := 0.0
var _pitch := -0.25
var _looking := false
var _vfx_timer := 0.0
var _stations: Array[Dictionary] = [] ## {position, effect}
var _tails: Array[Tail] = []
var _gunner := Tank.new() ## Never seen or moved: it only owns the rounds fired from the camera.
var _round := Armament.Round.APHE
var _round_label := Label.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Let clicks and drags through to _input instead of being eaten by this Control.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Course.flat = true
	var d := START_D
	for spec: Array in LAYOUT:
		d += spec[0]
		_row_d.append(d)
	world = World.new()
	add_child(view)
	world.view = view
	world.rail.d = START_D + 60.0
	world.rail.mode = Rail.Mode.ARENA # No rail scrolling: nothing despawns behind it.
	view.viewport.add_child(world)
	world.environment.fog_depth_begin = 220.0
	world.environment.fog_depth_end = 900.0
	world.sun.directional_shadow_max_distance = 220.0
	_build_tanks(_row_d[0])
	_build_enemies(_row_d[1])
	_build_bosses(_row_d[2])
	_build_pickups(_row_d[3])
	_build_props(_row_d[4], 4, ["wall", "jars", "pole", "persimmon", "bus_stop", "cultivator", "bale", "car", "reeds", "crate", "rock", "gate", "plane_tree", "rubble"])
	_build_props(_row_d[5], 5, ["house", "greenhouse", "pavilion", "hall", "truck", "zelkova_trunk", "church_nave", "church_tower", "school_wing", "school_center"])
	_build_props(_row_d[6], 6, ["mushroom", "veins", "mycelium", "egg_sacs", "cordyceps", "husk_cow", "infested_car", "flesh_mound", "spore_tower", "infested_house", "fungal_spire"])
	_build_projectiles(_row_d[7])
	_build_vfx(_row_d[8])
	world.add_child(_gunner)
	_gunner.process_mode = Node.PROCESS_MODE_DISABLED
	_gunner.visible = false
	_gunner._engine_sound.stop()
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(crosshair)
	_round_label.position = Vector2(16, 16)
	add_child(_round_label)
	_show_round()
	jump_to(0)


func _show_round() -> void:
	_round_label.text = String(Armament.ROUND_IDS[_round]).to_upper()


## Fires the chosen round from just below the camera toward the middle of the view.
func _fire() -> void:
	var cam := world.camera
	var forward := -cam.global_basis.z
	var from := cam.global_position + forward * 2.0 - cam.global_basis.y * 0.6
	var target := from + forward * 150.0
	for k in 150:
		var p := from + forward * k
		if p.y < Course.height_at(p):
			target = p
			break
	_gunner.aim_point = target
	_gunner.load_round(_round)
	_gunner.fire_cannon(from, forward)


func _exit_tree() -> void:
	Course.flat = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Camera preset looking at a row from the front and a little above.
func jump_to(row: int) -> void:
	var spec: Array = LAYOUT[row]
	var d := _row_d[row]
	world.camera.global_position = Course.to_world(d - spec[1], 0.0, spec[2])
	world.camera.look_at(Course.to_world(d + 4.0, 0.0, maxf(1.8, spec[2] * 0.25)), Vector3.UP)
	_yaw = world.camera.rotation.y
	_pitch = world.camera.rotation.x


func _label(text: String, at: Vector3, color := Palette.CREAM, size := 1.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = get_theme_default_font()
	label.font_size = 24
	label.pixel_size = 0.05 * size
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.modulate = color
	label.outline_modulate = Palette.INK
	label.outline_size = 6
	label.no_depth_test = true
	world.add_child(label)
	label.global_position = at


## Slot `i` of `count`, spread across the row.
func _slot(d: float, i: int, count: int, spacing: float) -> Vector3:
	return Course.ground_at(d, (i - (count - 1) * 0.5) * spacing)


func _row_title(row: int) -> void:
	_label("%d  %s" % [row + 1, ROWS[row]], Course.ground_at(_row_d[row] + 10.0, 0.0) + Vector3.UP * 10.0, Palette.FUNGUS, 1.4)


func _build_tanks(d: float) -> void:
	_row_title(0)
	var setups := [["COAX 8MM", 0], ["20+15MM", 4], ["MAX COAX", 5]]
	for i in setups.size():
		var model := TankModel.new()
		world.add_child(model)
		model.global_position = _slot(d, i, setups.size(), 12.0)
		model.rotation.y = 0.6
		model.set_coax_guns(Armament.tier_calibers(setups[i][1]))
		var tail := Tail.new()
		tail.mount = model.tail_mount
		world.add_child(tail)
		_tails.append(tail)
		_label(setups[i][0], model.global_position + Vector3.UP * 5.0)


func _build_enemies(d: float) -> void:
	_row_title(1)
	var kinds := [["FPV", "fpv", {}], ["UGV GUN", "ugv", {"weapon": "gun"}], ["UGV ATGM", "ugv", {"weapon": "atgm"}], ["UGV SUPPLY", "ugv", {"weapon": "supply"}], ["UAV", "uav", {}], ["HELICOPTER", "helicopter", {}], ["CRAWLER", "crawler", {}], ["SPITTER", "spitter", {}], ["WALKER GUN", "walker", {"weapon": "gun"}], ["WALKER MISSILE", "walker", {"weapon": "missile"}], ["QUAD FLAK", "quad", {"weapon": "flak"}], ["QUAD MORTAR", "quad", {"weapon": "mortar"}]]
	for i in kinds.size():
		var enemy: Enemy = load(Director.ENEMY_SCRIPTS[kinds[i][1]]).new()
		for key in kinds[i][2]:
			enemy.set(key, kinds[i][2][key])
		var at := _slot(d, i, kinds.size(), 12.0)
		_pose(enemy, at + (Vector3.UP * 3.0 if enemy.flying else Vector3.ZERO))
		_label(kinds[i][0], at + Vector3.UP * 6.0)


func _build_bosses(d: float) -> void:
	_row_title(2)
	var colossus: Enemy = load(Director.ENEMY_SCRIPTS["colossus"]).new()
	_pose(colossus, _slot(d, 0, 2, 40.0))
	_label("COLOSSUS", colossus.global_position + Vector3.UP * 16.0)
	var gunship: Enemy = load(Director.ENEMY_SCRIPTS["gunship"]).new()
	_pose(gunship, _slot(d, 1, 2, 40.0) + Vector3.UP * 5.0)
	_label("GUNSHIP", gunship.global_position + Vector3.UP * 7.0)


## Enemies are posed, not run: no AI, movement or attacks.
func _pose(enemy: Enemy, at: Vector3) -> void:
	enemy.position = at
	world.add_enemy(enemy)
	enemy.set_process(false)
	enemy.global_position = at # Some builds place themselves (the UAV enters far ahead).
	if enemy.has_method("pose_idle"):
		enemy.pose_idle()


func _build_pickups(d: float) -> void:
	_row_title(3)
	for i in Pickup.IDS.size():
		var id: String = Pickup.IDS[i]
		var pickup := world.spawn_pickup(id, _slot(d, i, Pickup.IDS.size(), 3.2) + Vector3.UP * 1.6)
		_label(id.to_upper(), pickup.global_position + Vector3.UP * 2.4, pickup.color(), 0.7)


func _build_props(d: float, row: int, kinds: Array) -> void:
	_row_title(row)
	var widths: Array[float] = []
	var total := 0.0
	for kind: String in kinds:
		var width: float = (Scenery.PROPS[kind][0] * 2.0 if Scenery.PROPS.has(kind) else 5.0) + 4.0
		widths.append(width)
		total += width
	var u := -total * 0.5
	for i in kinds.size():
		var kind: String = kinds[i]
		u += widths[i] * 0.5
		var at := Course.ground_at(d, u)
		var mesh := MeshInstance3D.new()
		mesh.mesh = PropKit.mesh(kind, 1)
		world.add_child(mesh)
		mesh.global_position = at
		var height: float = Scenery.PROPS[kind][1] if Scenery.PROPS.has(kind) else 2.0
		_label(kind.to_upper().replace("_", " "), at + Vector3.UP * (height + 2.5), Palette.CREAM, 0.8)
		u += widths[i] * 0.5


func _build_projectiles(d: float) -> void:
	_row_title(7)
	var shapes := World.PROJECTILE_SHAPES.keys()
	for i in shapes.size():
		var at := _slot(d, i, shapes.size(), 2.6) + Vector3.UP * 2.0
		var enemy_shot: bool = shapes[i] in ["orb", "rocket", "atgm", "bomb", "mortar"]
		var color := Palette.HOT if enemy_shot else Palette.AMBER
		for node in World.projectile_visual(shapes[i], color):
			world.add_child(node)
			node.global_position = at
			node.rotation.y = PI * 0.5
		_label(String(shapes[i]).to_upper(), at + Vector3.UP * (1.2 + (i % 2) * 0.8), color, 0.45)


func _build_vfx(d: float) -> void:
	_row_title(8)
	var effects := ["EXPLOSION", "BIG BLAST", "MUZZLE", "LASER", "MARKER", "SHOCKWAVE", "SPORES", "SMOKE", "BURNING", "FIRE ZONE", "DEBRIS"]
	for i in effects.size():
		var at := _slot(d, i, effects.size(), 9.0)
		_stations.append({"position": at, "effect": effects[i]})
		_label(effects[i], at + Vector3.UP * 8.0, Palette.PEACH, 0.8)
		if effects[i] == "BURNING":
			world.fx.burn(at, 1e9, 1.2)
	_play_stations()


func _play_stations() -> void:
	var fx := world.fx
	for station in _stations:
		var p: Vector3 = station.position
		match station.effect:
			"EXPLOSION":
				fx.explosion(p + Vector3.UP, 1.5)
			"BIG BLAST":
				fx.explosion(p + Vector3.UP, 4.0)
			"MUZZLE":
				for k in 3:
					fx.muzzle_flash(p + Vector3.UP * (1.0 + k * 1.8), Vector3.RIGHT, 0.6 + k * 0.9)
			"LASER":
				fx.beam(p + Vector3(-3, 1, 0), p + Vector3(3, 5, 0), Palette.MINT, 0.15, 1.0)
			"MARKER":
				fx.marker(p, 3.0, 1.9)
			"SHOCKWAVE":
				fx.shockwave(p + Vector3.UP * 0.5, 6.0, Palette.BUTTER)
			"SPORES":
				fx.spores(p + Vector3.UP, 30, 2.0)
			"SMOKE":
				fx.smoke_column(p, 2.5)
			"FIRE ZONE":
				FireZone.ignite(p)
			"DEBRIS":
				fx.debris(p + Vector3.UP, 16, [Fx.Debris.WOOD, Fx.Debris.CONCRETE, Fx.Debris.METAL], 8.0, 0.4)


func _process(delta: float) -> void:
	_vfx_timer += delta
	if _vfx_timer >= 2.0:
		_vfx_timer = 0.0
		_play_stations()
	for tail in _tails:
		tail.update(delta, tail.mount.global_basis, 0.0)
	var cam := world.camera
	var move := Vector3(Input.get_axis("move_left", "move_right"), 0.0, Input.get_axis("move_forward", "move_back"))
	if Input.is_key_pressed(KEY_E):
		move.y += 1.0
	if Input.is_key_pressed(KEY_Q):
		move.y -= 1.0
	var speed := 60.0 if Input.is_key_pressed(KEY_SHIFT) else 20.0
	cam.global_position += cam.global_basis * move * speed * delta
	cam.rotation = Vector3(_pitch, _yaw, 0.0)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_fire()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var step := 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
		_round = posmod(_round + step, Armament.ROUND_IDS.size()) as Armament.Round
		_show_round()
	elif event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * 0.004
		_pitch = clampf(_pitch - event.relative.y * 0.004, -1.4, 1.4)
	elif event is InputEventKey and event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		jump_to(event.keycode - KEY_1)
