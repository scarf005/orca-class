class_name Training
## The tutorial's training-ground pieces: targets that slide on a track, a jinking target drone, the armoured
## pillbox and a TV that loops an in-engine demonstration of a skill.

const STEEL_ARMOR := 40.0 ## Thicker than every coax caliber, so the coax only ricochets off steel.


## A round bullseye on a post, sliding back and forth across `track` (u from, u to) at `d`. Paper tears to
## any hit; steel turns the coax and falls to a main-gun shell.
class Target extends Enemy:
	var steel := false
	var d := 0.0
	var track := Vector2(-16.0, 16.0)
	var period := 4.0 ## Seconds for a full sweep there and back.
	var phase := 0.0

	func _init() -> void:
		super()
		score = 0
		despawn_behind = 0.0
		can_stagger = false
		radius = 1.3
		center_height = 2.0
		debris = [Fx.Debris.PAINT]

	func apply_difficulty() -> void:
		pass

	func build() -> void:
		armor = STEEL_ARMOR if steel else 0.0
		max_hp = 30.0 if steel else 1.0
		hp = max_hp
		debris = [Fx.Debris.METAL] if steel else [Fx.Debris.PAINT]
		var b := LowPoly.new()
		b.box(Transform3D(Basis(), Vector3(0, 0.5, 0)), Vector3(0.25, 1.0, 0.25), Palette.WOOD if not steel else Palette.SLATE)
		var face := Basis(Vector3.RIGHT, PI * 0.5 - 0.5) # Leaned back toward the overhead view.
		var rings := [Palette.SLATE, Palette.ASH, Palette.SLATE] if steel else [Palette.CREAM, Palette.RED, Palette.CREAM]
		b.prism(Transform3D(face, Vector3(0, 2.0, 0)), 1.3, 0.12, 12, Palette.INK if steel else Palette.CREAM, -1.0, rings[0])
		for i in 2:
			b.prism(Transform3D(face, Vector3(0, 2.0, 0) + face.y * (0.13 + i * 0.01)), 0.9 - i * 0.5, 0.01, 12, rings[i + 1])
		var mesh := MeshInstance3D.new()
		mesh.mesh = b.mesh()
		model.add_child(mesh)
		behave(0.0)

	func behave(_delta: float) -> void:
		var k := 0.5 - 0.5 * cos(TAU * age / period + phase)
		global_position = Course.ground_at(d, lerpf(track.x, track.y, k))


## A small target drone that jinks hard around `center`: free-aimed shots mostly miss, a held lock follows it.
## Its plating turns the coax.
class Drone extends Enemy:
	var center := Vector3.ZERO

	func _init() -> void:
		super()
		score = 0
		despawn_behind = 0.0
		flying = true
		can_stagger = false
		radius = 1.2
		max_hp = 30.0
		hp = 30.0
		armor = STEEL_ARMOR
		debris = [Fx.Debris.METAL, Fx.Debris.PAINT]

	func apply_difficulty() -> void:
		pass

	func build() -> void:
		var mesh := MeshInstance3D.new()
		mesh.mesh = Training.drone_mesh()
		model.add_child(mesh)
		global_position = center

	func behave(_delta: float) -> void:
		var t := age
		global_position = center + Vector3(sin(t * 1.7) * 7.0 + sin(t * 5.1) * 2.5, sin(t * 3.3) * 1.5, sin(t * 2.3) * 3.0)


## An unarmed scarecrow on a wheeled base, ambling about `pen` ((u, d) rectangle). Anything kills it; only a melee
## kill (a ram, a dash lash) heals the tank.
class Scarecrow extends Enemy:
	var pen := Rect2()
	var _goal := Vector2.INF

	func _init() -> void:
		super()
		score = 0
		despawn_behind = 0.0
		can_stagger = false
		radius = 1.4
		center_height = 1.8
		max_hp = 10.0
		hp = 10.0
		debris = [Fx.Debris.STRAW, Fx.Debris.WOOD]

	func apply_difficulty() -> void:
		pass

	func build() -> void:
		var mesh := MeshInstance3D.new()
		mesh.mesh = Training.scarecrow_mesh()
		model.add_child(mesh)
		global_position = Course.ground_at(pen.get_center().y + randf_range(-0.4, 0.4) * pen.size.y, pen.get_center().x + randf_range(-0.4, 0.4) * pen.size.x)

	func behave(delta: float) -> void:
		var c := Course.to_course(global_position)
		var at := Vector2(c.y, c.x)
		if _goal == Vector2.INF or at.distance_to(_goal) < 1.0:
			_goal = pen.position + Vector2(randf(), randf()) * pen.size
		at = at.move_toward(_goal, 2.0 * delta)
		global_position = Course.ground_at(at.y, at.x)


## One of the swarm circling `center`: plated against the coax and shrugging off blasts and fragments, so only
## direct hits drop it, one at a time unless a micro salvo locks them all.
class Swarmling extends Enemy:
	var center := Vector3.ZERO
	var radius_around := 5.0
	var slot := 0

	func _init() -> void:
		super()
		score = 0
		despawn_behind = 0.0
		flying = true
		can_stagger = false
		radius = 1.0
		max_hp = 10.0
		hp = 10.0
		armor = STEEL_ARMOR
		debris = [Fx.Debris.METAL, Fx.Debris.PAINT]

	func apply_difficulty() -> void:
		pass

	func build() -> void:
		var mesh := MeshInstance3D.new()
		mesh.mesh = Training.drone_mesh()
		model.add_child(mesh)
		behave(0.0)

	func take_hit(hit: Hit) -> void:
		if hit.kind in [Hit.Kind.BLAST, Hit.Kind.FRAGMENT]:
			return
		super.take_hit(hit)

	func behave(_delta: float) -> void:
		var angle := TAU * slot / 4.0 + age * 0.6
		global_position = center + Vector3(cos(angle) * radius_around, sin(age * 2.0 + slot) * 0.6, sin(angle) * radius_around * 0.5)


static func scarecrow_mesh() -> Mesh:
	var b := LowPoly.new()
	b.box(Transform3D(Basis(), Vector3(0, 0.3, 0)), Vector3(1.6, 0.6, 1.6), Palette.WOOD)
	b.box(Transform3D(Basis(), Vector3(0, 1.8, 0)), Vector3(0.25, 2.6, 0.25), Palette.WOOD)
	b.box(Transform3D(Basis(), Vector3(0, 2.4, 0)), Vector3(3.2, 0.22, 0.22), Palette.WOOD)
	b.prism(Transform3D(Basis(), Vector3(0, 1.2, 0)), 0.7, 1.4, 6, Palette.STRAW, 0.45)
	b.blob(Transform3D(Basis(), Vector3(0, 3.3, 0)), 0.5, Palette.BUTTER, 0)
	b.prism(Transform3D(Basis(), Vector3(0, 3.7, 0)), 0.8, 0.5, 8, Palette.OCHRE, 0.0)
	return b.mesh()


static func drone_mesh() -> Mesh:
	var b := LowPoly.new()
	b.box(Transform3D(), Vector3(1.0, 0.4, 1.0), Palette.RED)
	for corner in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		b.box(Transform3D(Basis(Vector3.UP, atan2(corner.x, corner.y)), Vector3(corner.x, 0, corner.y) * 0.55), Vector3(0.14, 0.1, 1.5), Palette.INK)
		b.prism(Transform3D(Basis(), Vector3(corner.x, 0.12, corner.y) * 1.05), 0.55, 0.04, 8, Palette.MIST)
	return b.mesh()


## The pillbox: an armoured casemate on tracks, an enemy so a held charge locks onto it. Only a full charge
## breaks it; everything else sparks off.
class Pillbox extends Enemy:
	func _init() -> void:
		super()
		score = 0
		despawn_behind = 0.0
		can_stagger = false
		radius = 3.2
		center_height = 2.0
		max_hp = 400.0
		hp = 400.0
		armor = STEEL_ARMOR
		debris = [Fx.Debris.ARMOR, Fx.Debris.CONCRETE]

	func apply_difficulty() -> void:
		pass

	func build() -> void:
		var mesh := MeshInstance3D.new()
		mesh.mesh = Training.pillbox_mesh()
		model.add_child(mesh)

	func take_hit(hit: Hit) -> void:
		if Armament.stage(hit.power) < 3:
			if not dead and hit.kind != Hit.Kind.FIRE:
				World.current.fx.sparks(hit.position, -hit.direction, 6, Palette.WHITE, 14.0)
			return
		super.take_hit(hit)


## The pillbox: a squat armoured casemate on tracks, gun slit to the front (-z faces the tank).
static func pillbox_mesh() -> Mesh:
	var b := LowPoly.new()
	for side in [-1.0, 1.0]:
		b.box(Transform3D(Basis(), Vector3(side * 2.5, 0.65, 0)), Vector3(1.1, 1.3, 6.2), Palette.INK)
		for k in 5:
			b.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(side * 3.1, 0.6, -2.4 + k * 1.2)), 0.45, 0.1, 8, Palette.STONE)
	b.box(Transform3D(Basis(), Vector3(0, 1.5, 0)), Vector3(5.6, 1.4, 6.6), Palette.SLATE)
	b.prism(Transform3D(Basis(), Vector3(0, 2.2, 0)), 3.0, 1.9, 8, Palette.STONE, 2.0, Palette.SLATE)
	b.box(Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, 1.9, -3.1)), Vector3(5.4, 1.6, 0.6), Palette.SLATE)
	b.box(Transform3D(Basis(), Vector3(0, 3.0, -2.75)), Vector3(2.6, 0.35, 0.5), Palette.INK)
	b.tube(Transform3D(Basis(), Vector3(0, 3.0, -2.9)), 0.14, -1.2, 6, Palette.INK)
	for x in [-1.6, 0.0, 1.6]:
		for z in [-1.4, 1.4]:
			b.box(Transform3D(Basis(), Vector3(x, 4.15, z)), Vector3(0.3, 0.12, 0.3), Palette.INK)
	return b.mesh()


## The paint turret: a squat mount with a fat barrel down local -z.
static func turret_mesh() -> Mesh:
	var b := LowPoly.new()
	b.box(Transform3D(Basis(), Vector3(0, 0.8, 0)), Vector3(3.2, 1.6, 3.2), Palette.SLATE)
	b.prism(Transform3D(Basis(), Vector3(0, 1.6, 0)), 1.3, 1.0, 8, Palette.CREAM)
	b.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 2.1, -0.8)), 0.45, 2.2, 8, Palette.HOT)
	return b.mesh()


## The armoured paint turret at the end of the tutorial: everything only sparks off it.
class Turret extends Prop:
	var _warning := MeshInstance3D.new()

	func _init() -> void:
		setup("turret", Training.turret_mesh(), 2.0, 2.6, 100.0)
		min_charge = 3
		var b := LowPoly.new()
		b.glow = true
		_warning.mesh = b.blob(Transform3D(), 0.7, Palette.HOT, 1).mesh()
		_warning.position = Vector3(0, 2.1, -3.1)
		_warning.visible = false
		add_child(_warning)

	func muzzle() -> Vector3:
		return global_transform * Vector3(0, 2.1, -3.2)

	## The muzzle glows, blinking, while a shot is coming.
	func warn(on: bool) -> void:
		_warning.visible = on and fmod(Time.get_ticks_msec() / 1000.0, 0.16) < 0.1

	func take_hit(hit: Hit) -> void:
		if hit.kind != Hit.Kind.FIRE:
			World.current.fx.sparks(hit.position, -hit.direction, 6, Palette.WHITE, 14.0)


## A TV screen looping a demonstration in its own small scene, the keys it presses drawn below in the tutorial's
## glyphs: "move" (forward through a wall), "fire" (the cannon drops steel, the coax tears paper), "charge" (hold,
## three lock boxes, the shot breaks the pillbox), "lock" (the boxes ride a jinking drone until it drops), "drift"
## (a dash over a gap) and "dodge" (a dash as the paint ball arrives lets it pass through).
class Screen extends SubViewport:
	const LOOP := 4.0
	var skill := "charge"
	var glyphs: Array = [] ## Every key bound to the actions the demo presses, as Tutorial._glyphs gives them, each with its `action` index.
	var pressed := -1 ## Which action is held down now: all of its keys light up.
	var charge := 0.0 ## Lock boxes drawn on the target.
	var source: Tank ## Whose armour the "armor" screen shows, live.
	var _time := 0.0
	var _scene := Node3D.new()
	var _tank := TankModel.new()
	var _target := Node3D.new()
	var _paper := Node3D.new()
	var _wall := MeshInstance3D.new()
	var _shell := MeshInstance3D.new()
	var _burst := MeshInstance3D.new()
	var _puff := MeshInstance3D.new()
	var _ghosts: Array[Node3D] = [] ## Dash afterimages, as the game leaves them (Tank._dash_trail).
	var _yaw := 0.0
	var _nanites: Array[MeshInstance3D] = []
	var _swarm: Array[Node3D] = []
	var _bursts: Array[MeshInstance3D] = []
	var locks := 0 ## Micro locks painted so far, drawn as a box on each of the first `locks` drones.
	var _camera := Camera3D.new()
	var _overlay: Overlay

	class Overlay extends Hud:
		var screen: Screen

		func _ready() -> void:
			world = World.current # The tutorial's: the sights pace their spin-in by its tank's charge time.
			set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			font = get_theme_default_font()

		func _process(_delta: float) -> void:
			pass # Redrawn by its Screen, on the demo's clock.

		func _draw() -> void:
			_time = screen._time
			if screen.skill == "armor":
				# The tank's own armour, as the game's status bar draws it, filling the screen.
				var armor := screen.source.hp / screen.source.max_hp if is_instance_valid(screen.source) else 0.0
				draw_rect(Rect2(Vector2.ZERO, size), Palette.INK)
				_bar(Rect2(Vector2(14, 52), size - Vector2(28, 104)), armor, _armor_color(armor), 10)
				if armor >= 1.0 and fmod(Time.get_ticks_msec() / 1000.0, 0.6) < 0.4:
					draw_rect(Rect2(Vector2(8, 46), size - Vector2(16, 92)), Palette.MINT, false, 3.0)
				return
			for i in screen.glyphs.size():
				var held: bool = screen.pressed == screen.glyphs[i].get("action", 0)
				var key := Rect2(10 + i * 68, size.y - 58, 60, 48)
				var ink := Palette.INK if held else Palette.BUTTER
				draw_rect(key, Palette.BUTTER if held else Palette.INK)
				draw_rect(key, Palette.BUTTER, false, 2.0)
				var glyph: Dictionary = screen.glyphs[i]
				if glyph.has("text"):
					draw_string(font, key.position + Vector2(0, 32), glyph.text, HORIZONTAL_ALIGNMENT_CENTER, key.size.x, 22 if glyph.text.length() < 4 else 14, ink)
				for rectangle: Rect2 in glyph.get("rects", []):
					draw_rect(Rect2(key.get_center() + Vector2(rectangle.position.x, -rectangle.end.y) * 6.0, rectangle.size * 6.0), ink)
			if screen.skill == "heal":
				# The demo's armour, topping up as the salvage arrives.
				var armor := 0.55 + 0.45 * clampf((screen._time - 1.3) / 0.9, 0.0, 1.0)
				_bar(Rect2(10, 10, 96, 8), armor, _armor_color(armor), 10)
			for i in screen.locks:
				var at: Vector3 = screen._swarm[i].global_position
				if not screen._camera.is_position_behind(at):
					_draw_lock_box(screen._camera.unproject_position(at), 9.0, _time * 0.8 + i, Armament.ROUND_COLORS[Armament.Round.MICRO])
			if screen.charge > 0.0 and screen._target.visible:
				var at: Vector3 = screen._target.global_position + Vector3.UP * 1.5
				if not screen._camera.is_position_behind(at):
					_draw_lock_boxes(screen._camera.unproject_position(at), 10.0, screen.charge, Palette.AMBER)

	func _init() -> void:
		size = Vector2i(240, 150)
		own_world_3d = true
		render_target_update_mode = SubViewport.UPDATE_ALWAYS

	func _ready() -> void:
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Palette.SKY
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Palette.MIST
		environment.ambient_light_energy = 0.5
		var world_environment := WorldEnvironment.new()
		world_environment.environment = environment
		add_child(world_environment)
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(-0.9, 0.5, 0)
		sun.light_energy = 0.7
		add_child(sun)
		add_child(_scene)
		var ground := LowPoly.new()
		if skill == "drift":
			for x in [-6.0, 7.0 + Tank.HULL_RADIUS]:
				ground.box(Transform3D(Basis(), Vector3(x, -0.6, -6)), Vector3(5.0 + Tank.HULL_RADIUS, 1.2, 24), Palette.STONE, Palette.LEAF)
		else:
			ground.box(Transform3D(Basis(), Vector3(0, -0.6, -8)), Vector3(16, 1.2, 28), Palette.STONE, Palette.LEAF)
		_scene.add_child(_mesh(ground.mesh()))
		_scene.add_child(_tank)
		var target_mesh: Mesh = {"charge": Training.pillbox_mesh(), "lock": Training.drone_mesh(), "dodge": Training.turret_mesh(), "fire": _disc(Palette.SLATE), "heal": Training.scarecrow_mesh(), "micro": Training.drone_mesh()}.get(skill)
		if target_mesh:
			_target.add_child(_mesh(target_mesh))
		_target.position = Vector3(-2.5 if skill == "fire" else 0.0, 0, -6 if skill == "heal" else -11)
		if skill == "lock":
			_target.scale = Vector3.ONE * 2.0
		if skill == "fire":
			_target.scale = Vector3.ONE * 1.6
			_paper.scale = Vector3.ONE * 1.6
		if skill in ["charge", "dodge"]:
			_target.rotation.y = PI # Gun toward the tank.
		_scene.add_child(_target)
		_scene.add_child(_paper)
		_scene.add_child(_wall)
		_paper.visible = skill == "fire"
		_wall.visible = skill == "move"
		if skill == "fire":
			_paper.add_child(_mesh(_disc(Palette.CREAM)))
			_paper.position = Vector3(2.5, 0, -11)
		if skill == "move":
			_wall.mesh = LowPoly.new().box(Transform3D(Basis(), Vector3(0, 0.85, 0)), Vector3(6, 1.7, 0.5), Palette.CONCRETE).mesh()
			_wall.position = Vector3(0, 0, -6)
		var b := LowPoly.new()
		b.glow = true
		if skill == "dodge":
			b.box(Transform3D(Basis(), Vector3(0, 1.3, 0)), Vector3(20, 2.6, 0.8), Palette.HOT)
		else:
			b.box(Transform3D(), Vector3(0.3, 0.3, 1.6), Palette.BUTTER)
		_shell.mesh = b.mesh()
		_scene.add_child(_shell)
		_burst.mesh = LowPoly.new().blob(Transform3D(), 1.0, Palette.AMBER, 1).mesh()
		_burst.material_override = LowPoly.glow_material
		_scene.add_child(_burst)
		_puff.mesh = LowPoly.new().blob(Transform3D(), 0.8, Palette.CREAM, 1, 0.4).mesh()
		_scene.add_child(_puff)
		if skill == "micro":
			for i in 4:
				var drone_node := Node3D.new()
				drone_node.add_child(_mesh(Training.drone_mesh()))
				drone_node.scale = Vector3.ONE * 1.6
				_scene.add_child(drone_node)
				_swarm.append(drone_node)
				var burst := MeshInstance3D.new()
				burst.mesh = _burst.mesh
				burst.material_override = LowPoly.glow_material
				_scene.add_child(burst)
				_bursts.append(burst)
		if skill == "heal":
			for i in 6:
				var nanite := MeshInstance3D.new()
				var n := LowPoly.new()
				n.glow = true
				n.blob(Transform3D(), 0.25, Palette.NANITE, 0)
				nanite.mesh = n.mesh()
				_scene.add_child(nanite)
				_nanites.append(nanite)
		if skill in ["drift", "dodge"]:
			for i in 4:
				var ghost := TankModel.new()
				_scene.add_child(ghost)
				var material := StandardMaterial3D.new()
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				material.albedo_color = Color.from_hsv(0.5 + i * 0.12, 0.65, 1.0, 0.55 - i * 0.1)
				for mesh in ghost.find_children("*", "MeshInstance3D", true, false):
					(mesh as MeshInstance3D).material_override = material
				_ghosts.append(ghost)
		_scene.add_child(_camera)
		if skill in ["drift", "dodge"]:
			_camera.position = Vector3(2.0, 9.0, 15.0)
			_camera.look_at(Vector3(2.0, 0.0, -3.0))
		else:
			_camera.position = Vector3(6.5, 6.0, 5.0)
			_camera.look_at(Vector3(-1.0, 1.5, -6.5))
		_camera.current = true
		_overlay = Overlay.new()
		_overlay.screen = self
		add_child(_overlay)

	func _mesh(mesh: Mesh) -> MeshInstance3D:
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		return instance

	static func _disc(face: Color) -> Mesh:
		var b := LowPoly.new()
		b.box(Transform3D(Basis(), Vector3(0, 0.6, 0)), Vector3(0.2, 1.2, 0.2), Palette.WOOD)
		b.prism(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 2.0, 0)), 1.2, 0.12, 12, face)
		return b.mesh()

	## Shows the shell flying from the tank to `to` over [`from_time`, `from_time` + `time`].
	func _fly(t: float, from_time: float, time: float, to: Vector3, from := Vector3(0, 2.2, -3)) -> bool:
		var k := (t - from_time) / time
		_shell.visible = k >= 0.0 and k < 1.0
		if _shell.visible and not to.is_equal_approx(from):
			_shell.transform = Transform3D(Basis.looking_at(to - from), from.lerp(to, k))
		return k >= 1.0

	## How far a dash has carried the hull `time` seconds in: Tank's DASH_SPEED easing to a stop over DASH_TIME,
	## DASH_DISTANCE in all.
	static func _dash_offset(time: float) -> float:
		var tau := clampf(time, 0.0, Tank.DASH_TIME)
		return Tank.DASH_SPEED * (tau - tau * tau / (2.0 * Tank.DASH_TIME))

	## The nose swinging against a rightward slide and back, at the tank's own DRIFT_TURN rates.
	func _drift_yaw(delta: float, dashing: bool) -> float:
		_yaw = move_toward(_yaw, Tank.DRIFT_ANGLE if dashing else 0.0, (Tank.DRIFT_TURN.x if dashing else Tank.DRIFT_TURN.y) * delta)
		return _yaw

	## Afterimages trailing the hull through a dash that starts at `start` (`path` gives the hull's place at a
	## time), each a different hue, and a puff of dust where the tail kicked off.
	func _dash_effects(t: float, start: float, path: Callable) -> void:
		for i in _ghosts.size():
			var at := t - 0.05 * (i + 1)
			_ghosts[i].visible = at > start and at < start + 0.45
			_ghosts[i].position = path.call(at)
		_puff.visible = t > start and t < start + 0.6
		_puff.position = path.call(start) + Vector3(-1.5, 0.4, 2.5)
		_puff.scale = Vector3.ONE * (1.0 + (t - start) * 3.0)

	func _boom_at(i: int, t: float, at: float, where: Vector3) -> void:
		_bursts[i].visible = t >= at and t < at + 0.4
		_bursts[i].position = where
		_bursts[i].scale = Vector3.ONE * (0.6 + (t - at) * 6.0)

	func _boom(t: float, at: float, where: Vector3) -> void:
		_burst.visible = t >= at and t < at + 0.5
		_burst.position = where
		_burst.scale = Vector3.ONE * (1.0 + (t - at) * 8.0)

	func _process(delta: float) -> void:
		_time = fmod(_time + delta, LOOP)
		var t := _time
		var aim := _target.position + Vector3.UP * 1.5
		pressed = -1
		charge = 0.0
		locks = 0
		_tank.position = Vector3.ZERO
		_shell.visible = false
		_burst.visible = false
		_puff.visible = false
		match skill:
			"micro":
				# Held, the sight paints a lock on each drone in turn; released, a missile leaves for every lock.
				pressed = 0 if t > 0.3 and t < 1.8 else -1
				for i in _swarm.size():
					var drone_node: Node3D = _swarm[i]
					drone_node.position = Vector3(-4.5 + i * 3.0, 5.0 + sin(t * 3.0 + i) * 0.4, -11.0)
					drone_node.visible = t < 2.1 + i * 0.05 or t > 3.6
				_target.visible = false
				locks = clampi(int((t - 0.3) / 0.35), 0, _swarm.size()) if t < 1.8 else (_swarm.size() if t < 2.1 else 0)
				for i in _swarm.size():
					_boom_at(i, t, 2.1 + i * 0.05, _swarm[i].position)
			"heal":
				# A ram: the scarecrow bursts and its salvage streams back into the hull.
				pressed = 0 if t > 0.4 and t < 1.6 else -1
				_tank.position.z = -clampf((t - 0.4) / 1.2, 0.0, 1.0) * 7.0
				_target.visible = t < 1.3 or t > 3.6
				_boom(t, 1.3, _target.position + Vector3.UP * 1.5)
				for i in _nanites.size():
					var k := clampf((t - 1.3 - i * 0.08) / 0.7, 0.0, 1.0)
					_nanites[i].visible = k > 0.0 and k < 1.0
					_nanites[i].position = (_target.position + Vector3(0, 2.0, 0)).lerp(_tank.position + Vector3(0, 1.5, 2.5), k * k) + Vector3(sin(i * 2.1), sin(k * PI) * 1.5, 0)
			"move":
				pressed = 0 if t > 0.4 and t < 2.4 else -1
				_tank.position.z = -clampf((t - 0.4) / 2.0, 0.0, 1.0) * 9.0
				_wall.visible = _tank.position.z > -3.0
				_boom(t, 0.4 + 2.0 * 3.0 / 9.0, _wall.position + Vector3.UP)
			"fire":
				pressed = 0 if t > 0.4 and t < 0.6 else (1 if t > 2.0 and t < 2.6 else -1)
				_fly(t, 0.6, 0.3, aim)
				_target.rotation.x = -clampf((t - 0.9) * 6.0, 0.0, PI * 0.5) if t < 3.6 else 0.0
				if t > 2.0 and t < 2.6:
					_fly(fmod(t - 2.0, 0.15), 0.0, 0.15, _paper.position + Vector3.UP * 2.0, Vector3(0.3, 2.0, -2))
				_paper.visible = t < 2.6 or t > 3.6
				_boom(t, 2.6, _paper.position + Vector3.UP * 2.0)
			"charge", "lock":
				if skill == "lock":
					_target.position = Vector3(sin(t * 3.4) * 3.0, 5.0 + sin(t * 6.6) * 0.6, -11.0)
					aim = _target.position
				var held := t > 0.4 and t < 1.6
				pressed = 0 if held else -1
				charge = clampf((t - 0.4) / Armament.FULL_TIME, 0.0, 1.0) if held else 0.0
				_fly(t, 1.6, 0.3, aim)
				_target.visible = t < 1.9 or t > 3.4
				_boom(t, 1.9, aim)
			"drift":
				pressed = 0 if t > 1.0 and t < 1.2 else -1
				_tank.position.x = -6.0 + _dash_offset(t - 1.0)
				_tank.rotation.y = _drift_yaw(delta, t > 1.0 and t < 1.0 + Tank.DASH_TIME)
				_dash_effects(t, 1.0, func(at: float) -> Vector3: return Vector3(-6.0 + _dash_offset(at - 1.0), 0, 0))
			"dodge":
				# The wall reaches the hull as the dash starts and goes through it while the hull is untouchable.
				var dash := 1.6
				pressed = 0 if t > dash and t < dash + 0.2 else -1
				_shell.visible = t > 0.2 and t < 2.6
				_shell.position = Vector3(2.0, 0, -11.0 + (t - 0.2) * 7.5)
				_tank.position.x = -4.0 + _dash_offset(t - dash) * 0.75
				_tank.rotation.y = _drift_yaw(delta, t > dash and t < dash + Tank.DASH_TIME)
				_dash_effects(t, dash, func(at: float) -> Vector3: return Vector3(-4.0 + _dash_offset(at - dash) * 0.75, 0, 0))
		_overlay.queue_redraw()
