class_name Gunship
extends Enemy
## Stage 1 boss: a heavy synchrocopter gunship overtaken by mycelium, after Armored Core VI's
## AH12 HC: a long armored hull, two intermeshing rotors on masts splayed in a V above it, stub
## wings ending in huge missile racks, gatling turrets on the shoulders and a searchlight nose.
## Nose and flank plates protect the hull; three bare-airframe cannon hits bring it down.
## Every weapon and rotor is its own module with its own health: hitting one hurts only it, and
## wrecking it tears it off the airframe and silences that attack. One rotor lost lowers and banks
## the craft, both lost crash it. Weapons: two shoulder gatlings, a nose cannon, a chin ATGM drum,
## two wing rocket racks and a belly bomb bay. The three phases add flares, drone calls and the
## infected dive before the crash into the dam.

enum Phase { HUNTER, STRIPPED, INFECTED }
enum Attack { NONE, GUN, ROCKETS, ATGM, DRONES, DIVE, BOMBS, CANNON }

const BODY_HP := 1600.0
const CANNON_SHARE := 0.34 ## Hull taken by one main-gun shell on bare airframe: three clean hits.
const PLATED_SHARE := 0.03 ## Hull taken when an ERA plate eats the shell.
const ERA_HP := 100.0 ## One shell pops a plate; machine guns chew through it slowly.
const MODULE_HP := {"rotor_l": 150.0, "rotor_r": 150.0, "chin": 90.0, "pod_l": 140.0, "pod_r": 140.0,
	"gatling_l": 80.0, "gatling_r": 80.0, "nose_gun": 110.0, "bay": 120.0}
const GATLINGS := ["gatling_l", "gatling_r"]
const PART_LABELS := {"rotor_l": "ROTOR L", "rotor_r": "ROTOR R", "chin": "ATGM", "pod_l": "RACK L", "pod_r": "RACK R",
	"gatling_l": "GUN L", "gatling_r": "GUN R", "nose_gun": "CANNON", "bay": "BOMBS"}
const GUN_SPEED := 180.0
const ROCKET_SPEED := 85.0
const ATGM_SPEED := 45.0
const BOMB_FLIGHT := 0.9 ## Seconds from the bay to the ground for the first bomb.
const CANNON_SPEED := 450.0 ## The nose cannon's shells arrive almost at once, so each shot is warned first.
const CANNON_AIM := 0.7 ## Seconds of warning before each cannon shot.
const CANNON_LOCK := 0.35 ## For the last of the warning the aim holds still: move now and it misses.
const MIN_CLEARANCE := 9.0 ## Its belly and underslung guns hang this far below it: never lower than this over the ground.
const PART_PRIORITY := 3.0 ## A module this close behind the airframe skin still takes the hit.
const ROTORS := ["rotor_l", "rotor_r"]
const ROTOR_RADIUS := 11.5
const ROTOR_TILT := 0.22 ## Each mast leans outward, so the two rotors mesh like an eggbeater.
const MODEL_SCALE := 1.8 ## The whole airframe is drawn this much bigger than its model-space layout.
const PLATES := ["era_front", "era_left", "era_right"]

class Part:
	var name := ""
	var offset := Vector3.ZERO
	var radius := 1.0
	var hp := 0.0
	var node: Node3D
	var module := false ## A working component; armor plates are not.

var phase := Phase.HUNTER
var parts := {}
var _attack := Attack.NONE
var _attack_time := 0.0
var _next_attack := 2.5
var _orbit_angle := 0.0
var _orbit_dir := 1.0
var _velocity := Vector3.ZERO
var _rotors: Dictionary = {}
var _discs: Array[MeshInstance3D] = []
var _gatlings: Array[Node3D] = [] ## Shoulder turrets that track the tank; barrels spin while firing.
var _barrels: Array[Node3D] = []
var _chin := Node3D.new()
var _fungus := Node3D.new()
var _shots := 0
var _shot_timer := 0.0
var _flare_cooldown := 0.0
var _spore_timer := 0.0
var _crash := 0.0
var _crash_from := Vector3.ZERO
var _crash_to := Vector3.ZERO ## Where it hits the dam: in front of the face, up where the camera sees it.
var _cannon_aim := Vector3.ZERO ## Where the nose cannon's next shell is locked to go.
var _hard := false
var _rotor_sound: AudioStreamPlayer3D
var _jitter := Vector3.ZERO


func _init() -> void:
	super()
	radius = 6.0
	armor = 0.6
	center_height = 0.0
	flying = true
	trails = true
	can_stagger = true
	score = 50000
	despawn_behind = 0.0
	debris = [Fx.Debris.ARMOR, Fx.Debris.METAL, Fx.Debris.GLASS, Fx.Debris.FLESH]
	set_meta("title", "BOSS_GUNSHIP")
	set_meta("phase_marks", [0.7, 0.34])


func build() -> void:
	_hard = Game.difficulty == Game.Difficulty.HARD
	max_hp = BODY_HP * (1.35 if _hard else 1.0)
	hp = max_hp
	# Every part offset below is in model space, so hit tests scale with the model.
	model.scale = Vector3.ONE * MODEL_SCALE
	var b := LowPoly.new()
	# The hull: hexagonal armored sections from the sensor nose back to the boom, dark gunmetal
	# below, lighter plates above, with the patrol force's yellow bands.
	var hull := [[-6.2, 1.6, 1.3, 2.2], [-4.4, 2.4, 2.0, 2.4], [-1.8, 2.7, 2.4, 3.0], [1.4, 2.6, 2.2, 3.0], [4.2, 2.0, 1.4, 2.6]]
	for i in hull.size():
		var seg: Array = hull[i]
		var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, seg[0] - seg[3] * 0.5))
		b.prism(xf, seg[1], seg[3], 6, Palette.ASH if i % 2 == 0 else Palette.MIST, seg[2])
	b.box(Transform3D(Basis(), Vector3(0, 1.9, -0.4)), Vector3(3.2, 1.0, 7.4), Palette.MIST)
	b.box(Transform3D(Basis(), Vector3(0, 2.45, -0.4)), Vector3(2.2, 0.3, 6.0), Palette.ASH)
	for z in [-3.2, 2.0]:
		b.box(Transform3D(Basis(), Vector3(0, 0.0, z)), Vector3(5.5, 0.35, 0.5), Palette.BUTTER)
	b.box(Transform3D(Basis(), Vector3(0, -2.25, -0.5)), Vector3(2.6, 0.7, 7.0), Palette.INK)
	# Sensor nose: a cluster of glowing lenses around a big searchlight.
	b.glow = true
	b.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, -0.2, -7.4)), 0.55, 0.2, 10, Palette.CREAM)
	for lens in [Vector3(-0.8, 0.5, -7.1), Vector3(0.8, 0.5, -7.1), Vector3(-1.0, -0.6, -7.0), Vector3(1.0, -0.6, -7.0)]:
		b.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), lens), 0.22, 0.15, 6, Palette.HOT)
	b.glow = false
	# Tail boom with twin fins and a stabilizer, like the K-MAX it copies.
	b.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0.6, 12.5)), 0.9, 7.0, 6, Palette.ASH, 0.55)
	b.box(Transform3D(Basis(), Vector3(0, 0.7, 12.6)), Vector3(6.0, 0.25, 1.6), Palette.SLATE)
	for side in [-1.0, 1.0]:
		b.box(Transform3D(Basis(Vector3.BACK, side * -0.15), Vector3(side * 3.0, 1.6, 12.7)), Vector3(0.25, 2.4, 1.8), Palette.STONE)
		b.box(Transform3D(Basis(Vector3.BACK, side * -0.15), Vector3(side * 3.12, 2.5, 12.7)), Vector3(0.05, 0.5, 1.7), Palette.BUTTER)
	# Stub wings drooping to the missile racks, and the side booster pods under them.
	for side in [-1.0, 1.0]:
		b.box(Transform3D(Basis(Vector3.BACK, side * 0.12), Vector3(side * 3.9, -0.2, 0.2)), Vector3(4.2, 0.45, 2.6), Palette.ASH)
		b.box(Transform3D(Basis(Vector3.BACK, side * 0.12), Vector3(side * 3.9, 0.05, 0.2)), Vector3(3.8, 0.05, 0.6), Palette.BUTTER)
		b.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(side * 2.5, -1.4, 3.6)), 0.75, 4.2, 8, Palette.STONE, 0.6)
		b.glow = true
		b.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(side * 2.5, -1.4, 3.65)), 0.5, 0.05, 8, Palette.AMBER)
		b.glow = false
	# Mast pylon on the spine that carries both rotor heads.
	b.box(Transform3D(Basis(), Vector3(0, 3.2, 0.2)), Vector3(3.4, 1.5, 2.6), Palette.STONE)
	var body := MeshInstance3D.new()
	body.mesh = b.mesh()
	model.add_child(body)
	# Intermeshing rotors: each head leans outward on its mast and spins the opposite way.
	for side in [-1.0, 1.0]:
		var part_name := "rotor_l" if side < 0.0 else "rotor_r"
		var hub := Vector3(side * 1.3, 5.2, 0.2)
		_add_part(part_name, hub, 1.4, MODULE_HP[part_name], _mast_mesh())
		var mast: Node3D = parts[part_name].node
		mast.rotation.z = -side * ROTOR_TILT
		var rotor := Node3D.new()
		mast.add_child(rotor)
		var r := LowPoly.new()
		r.prism(Transform3D(), 0.75, 0.55, 8, Palette.INK)
		for i in 2:
			var xf := Transform3D(Basis(Vector3.UP, PI * i), Vector3.ZERO)
			r.box(xf.translated_local(Vector3(ROTOR_RADIUS * 0.5, 0.3, 0)), Vector3(ROTOR_RADIUS, 0.16, 1.0), Palette.SLATE)
			r.box(xf.translated_local(Vector3(ROTOR_RADIUS - 0.65, 0.39, 0)), Vector3(1.3, 0.04, 1.0), Palette.BUTTER)
		var blades := MeshInstance3D.new()
		blades.mesh = r.mesh()
		rotor.add_child(blades)
		var d := LowPoly.new()
		d.glow = true
		for i in 24:
			var a0 := TAU * i / 24.0
			var a1 := TAU * (i + 1) / 24.0
			d.tri(Vector3(0, 0.3, 0), Vector3(cos(a0) * ROTOR_RADIUS, 0.3, sin(a0) * ROTOR_RADIUS), Vector3(cos(a1) * ROTOR_RADIUS, 0.3, sin(a1) * ROTOR_RADIUS), Palette.MIST, Vector3.UP)
		var disc := MeshInstance3D.new()
		disc.mesh = d.mesh()
		disc.material_override = World._halo_material
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mast.add_child(disc)
		_discs.append(disc)
		_rotors[part_name] = rotor
	# Shoulder gatling turrets: four barrels each on a ball mount.
	for side in [-1.0, 1.0]:
		var turret := Node3D.new()
		turret.position = Vector3(side * 6.4, -2.4, -0.6) # Slung under the rocket rack.
		model.add_child(turret)
		var t := LowPoly.new()
		t.blob(Transform3D(), 0.75, Palette.STONE, 1, 0.0, 3)
		t.box(Transform3D(Basis(), Vector3(0, 0, -0.6)), Vector3(0.8, 0.6, 0.6), Palette.INK)
		var mount := MeshInstance3D.new()
		mount.mesh = t.mesh()
		turret.add_child(mount)
		var barrels := Node3D.new()
		barrels.position = Vector3(0, 0, -0.9)
		turret.add_child(barrels)
		var g := LowPoly.new()
		for k in 4:
			var o := Vector3(cos(TAU * k / 4.0), sin(TAU * k / 4.0), 0) * 0.16
			g.tube(Transform3D(Basis(Vector3.UP, PI), o), 0.07, 1.8, 6, Palette.INK)
		g.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -1.2)), 0.28, 0.15, 8, Palette.SLATE)
		var spin := MeshInstance3D.new()
		spin.mesh = g.mesh()
		barrels.add_child(spin)
		_gatlings.append(turret)
		_barrels.append(barrels)
		var gatling := "gatling_l" if side < 0.0 else "gatling_r"
		_add_part(gatling, turret.position, 1.1, MODULE_HP[gatling], null)
		parts[gatling].node = turret
	# Chin rocket turret: an eight-tube drum under the nose; losing it silences the gun runs too.
	_chin.position = Vector3(0, -2.3, -5.2)
	model.add_child(_chin)
	var c := LowPoly.new()
	c.box(Transform3D(), Vector3(1.6, 1.0, 1.4), Palette.STONE)
	for k in 8:
		var o := Vector3(cos(TAU * k / 8.0), sin(TAU * k / 8.0), 0) * 0.45
		c.tube(Transform3D(Basis(Vector3.UP, PI), o + Vector3(0, 0, -0.6)), 0.14, 0.9, 6, Palette.INK)
	var chin_mesh := MeshInstance3D.new()
	chin_mesh.mesh = c.mesh()
	_chin.add_child(chin_mesh)
	_add_part("era_left", Vector3(-2.6, 0.0, -1.2), 2.0, ERA_HP, _panel_mesh(-1.0))
	_add_part("era_right", Vector3(2.6, 0.0, -1.2), 2.0, ERA_HP, _panel_mesh(1.0))
	_add_part("era_front", Vector3(0, 0.4, -6.9), 1.6, ERA_HP, _nose_mesh())
	_add_part("pod_l", Vector3(-6.4, -0.4, 0.2), 2.4, MODULE_HP.pod_l, _pod_mesh())
	_add_part("pod_r", Vector3(6.4, -0.4, 0.2), 2.4, MODULE_HP.pod_r, _pod_mesh())
	_add_part("chin", _chin.position, 1.1, MODULE_HP.chin, null)
	parts.chin.node = _chin
	_add_part("nose_gun", Vector3(0, -1.3, -7.6), 1.0, MODULE_HP.nose_gun, _nose_gun_mesh())
	_add_part("bay", Vector3(0, -2.6, 2.0), 1.6, MODULE_HP.bay, _bay_mesh())
	for part: Part in parts.values():
		part.module = MODULE_HP.has(part.name)
	model.add_child(_fungus)
	_grow_fungus(6)
	_rotor_sound = Sfx.loop("rotor", self, 4.0)


func _ready() -> void:
	super()
	# The spinning discs are blur, not airframe: no hostile outline around a rotor's whole sweep.
	for disc in _discs:
		ActorLayer.unmark(disc, ActorLayer.HOSTILE)


## A rotor head: the swashplate and hub on a short mast (the mast rises from the spine pylon).
func _mast_mesh() -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(Basis(), Vector3(0, -1.8, 0)), 0.42, 1.8, 8, Palette.INK, 0.28)
	b.prism(Transform3D(Basis(), Vector3(0, -0.3, 0)), 0.95, 0.4, 8, Palette.STONE, 0.6)
	return b.mesh()


func _add_part(part_name: String, offset: Vector3, r: float, part_hp: float, mesh: Mesh) -> void:
	var part := Part.new()
	part.name = part_name
	part.offset = offset
	part.radius = r
	part.hp = part_hp
	if mesh:
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = offset
		model.add_child(node)
		part.node = node
	parts[part_name] = part


## Bolt-on armor slab along a flank.
func _panel_mesh(side: float) -> Mesh:
	var b := LowPoly.new()
	b.box(Transform3D(Basis(Vector3.BACK, side * -0.25), Vector3(side * 0.1, 0, 0)), Vector3(0.25, 2.2, 5.6), Palette.ASH)
	for z in [-2.0, 0.0, 2.0]:
		b.box(Transform3D(Basis(Vector3.BACK, side * -0.25), Vector3(side * 0.24, 0, z)), Vector3(0.05, 1.8, 0.12), Palette.SLATE)
	b.box(Transform3D(Basis(Vector3.BACK, side * -0.25), Vector3(side * 0.24, 0.8, 0)), Vector3(0.05, 0.2, 5.0), Palette.BUTTER)
	return b.mesh()


## Layered armor over the upper nose, above the sensor cluster.
func _nose_mesh() -> Mesh:
	var b := LowPoly.new()
	for i in 3:
		b.box(Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 0.4 - i * 0.28, 0.3 * i)), Vector3(2.8 - i * 0.3, 0.3, 1.4), Palette.ASH if i % 2 == 0 else Palette.STONE)
	return b.mesh()


## A wingtip missile rack: a tall box of launch cells with warhead noses showing.
func _pod_mesh() -> Mesh:
	var b := LowPoly.new()
	b.box(Transform3D(), Vector3(1.8, 2.8, 4.8), Palette.ASH)
	b.box(Transform3D(Basis(), Vector3(0, 1.45, 0)), Vector3(1.6, 0.1, 4.4), Palette.BUTTER)
	for x in [-0.45, 0.45]:
		for y in [-0.9, 0.0, 0.9]:
			b.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(x, y, -2.4)), 0.3, 0.45, 6, Palette.ASH, 0.0)
	return b.mesh()


## A long-barreled autocannon slung under the sensor nose.
func _nose_gun_mesh() -> Mesh:
	var b := LowPoly.new()
	b.box(Transform3D(), Vector3(1.2, 0.9, 1.6), Palette.STONE)
	b.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -0.8)), 0.22, 3.2, 8, Palette.INK)
	b.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -3.8)), 0.34, 0.5, 8, Palette.SLATE)
	return b.mesh()


## A belly bomb bay: a boxy pannier with its doors and a row of bomb noses showing.
func _bay_mesh() -> Mesh:
	var b := LowPoly.new()
	b.box(Transform3D(), Vector3(2.6, 1.2, 4.2), Palette.ASH)
	b.box(Transform3D(Basis(), Vector3(0, -0.62, 0)), Vector3(2.2, 0.05, 3.8), Palette.BUTTER)
	for z in [-1.4, 0.0, 1.4]:
		b.blob(Transform3D(Basis(), Vector3(0, -0.6, z)), 0.35, Palette.RED, 0, 0.0, 2)
	return b.mesh()


func _grow_fungus(count: int) -> void:
	for i in count:
		var blob := MeshInstance3D.new()
		var p := Vector3(randf_range(-2.0, 2.0), randf_range(-1.5, 2.0), randf_range(-5.0, 9.0))
		blob.mesh = LowPoly.new().blob(Transform3D(), randf_range(0.5, 1.1), [Palette.FUNGUS, Palette.LILAC, Palette.BLUSH][i % 3], 0, 0.35, randi()).mesh()
		blob.position = p
		_fungus.add_child(blob)
		_meshes.append(blob)


func _live(part_name: String) -> bool:
	return parts[part_name].hp > 0.0


func aim_parts() -> Dictionary:
	var result := {}
	if _crash > 0.0:
		return result
	for name: String in MODULE_HP:
		if _live(name):
			var part: Part = parts[name]
			result[name] = [model.global_transform * part.offset, part.radius * MODEL_SCALE, PART_LABELS[name]]
	return result


func module_states() -> Array:
	return MODULE_HP.keys().map(func(name: String) -> Array: return [PART_LABELS[name], clampf(parts[name].hp / MODULE_HP[name], 0.0, 1.0)])


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	if _crash > 0.0:
		return -1.0
	var best := -1.0 # The airframe; modules are tested after it.
	for sphere: Vector4 in [Vector4(0, 0.2, -5.0, 2.2), Vector4(0, 0.4, -1.8, 2.7), Vector4(0, 0.4, 1.4, 2.6), Vector4(0, 0.4, 4.4, 2.0), Vector4(0, 0.6, 8.5, 1.0), Vector4(0, 0.6, 12.5, 1.2), Vector4(-3.9, -0.2, 0.2, 1.2), Vector4(3.9, -0.2, 0.2, 1.2)]:
		var t := Entity.segment_sphere(from, to, model.global_transform * Vector3(sphere.x, sphere.y, sphere.z), sphere.w * MODEL_SCALE + extra_radius)
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	var module := -1.0
	for part: Part in parts.values():
		if part.hp <= 0.0:
			continue
		var t := Entity.segment_sphere(from, to, model.global_transform * part.offset, part.radius * MODEL_SCALE + extra_radius)
		if t >= 0.0 and (module < 0.0 or t < module):
			module = t
	var local_from := model.to_local(from)
	var local_to := model.to_local(to)
	for name: String in ROTORS:
		if not _live(name):
			continue
		var center: Vector3 = parts[name].offset
		var extent := Vector3(ROTOR_RADIUS, 0.35, ROTOR_RADIUS) + Vector3.ONE * extra_radius
		var a := (local_from - center) / extent
		var b := (local_to - center) / extent
		var t := Entity.segment_sphere(a, b, Vector3.ZERO, 1.0)
		if t >= 0.0:
			t *= from.distance_to(to) / maxf(a.distance_to(b), 0.0001)
			if module < 0.0 or t < module:
				module = t
	# Modules stick out of the airframe, so one just behind where a shot meets the skin still
	# takes it: a shot aimed at a rack is not stolen by the wing it hangs from.
	if module >= 0.0 and (best < 0.0 or module - best < PART_PRIORITY):
		return module
	return best


func take_hit(hit: Hit) -> void:
	if dead or invulnerable or _crash > 0.0 or hit.damage <= 0.0:
		return
	var world := World.current
	var cannon := hit.kind == Hit.Kind.SHELL and hit.caliber >= 100
	var amount := hit.damage * damage_multiplier(hit)
	var hull := max_hp * CANNON_SHARE if cannon else amount
	var local := model.global_transform.affine_inverse() * hit.position
	var struck := _struck_part(hit.position)
	var plate := _plate_facing(local)
	if struck and struck.module:
		# A module takes the hit alone and shields the airframe behind it; a shell wrecks it outright.
		struck.hp -= INF if cannon else amount
		world.fx.sparks(hit.position, -hit.direction, 10, Palette.BUTTER, 12.0)
		if struck.hp <= 0.0:
			_lose_part(struck, hit.direction)
		hull = 0.0
	elif plate != "" and _live(plate) and hit.kind != Hit.Kind.FIRE:
		# ERA on the struck facing detonates outward and eats the shell.
		var era: Part = parts[plate]
		era.hp -= amount
		world.fx.sparks(hit.position, -hit.direction, 8, Palette.WHITE, 9.0)
		if era.hp <= 0.0:
			_lose_part(era, hit.direction)
		hull = max_hp * PLATED_SHARE if cannon else amount * 0.1
	hp -= hull
	impact_feedback(hit, amount, hp <= 0.0 or not (_live("rotor_l") or _live("rotor_r")))
	if cannon:
		# A 100 mm shell lands like a truck: a blast on the skin, the whole craft lurches and rolls.
		world.fx.explosion(hit.position, 2.2, [Palette.WHITE, Palette.BUTTER, Palette.AMBER, Palette.CORAL], hit.direction)
		world.fx.debris(hit.position, 10, debris, 14.0, 0.5, hit.direction)
		_velocity += hit.direction.normalized() * 9.0 + Vector3.UP * 3.0
		model.rotation.z += randf_range(-0.2, 0.2)
		model.rotation.x += randf_range(-0.12, 0.12)
		world.hitstop(0.08)
		world.shake(0.45, hit.position)
		world.screen_flash(Palette.WHITE, 0.15)
		world.camera.kick(0.03)
		Sfx.play("blast_small", hit.position, 4.0, 0.8)
	if hit.stagger >= 1.0:
		stagger = maxf(stagger, 0.6)
		if _attack in [Attack.GUN, Attack.ATGM] and _attack_time < 0.8:
			_end_attack()
	if hp <= 0.0 or not (_live("rotor_l") or _live("rotor_r")):
		_begin_crash()
		return
	_update_phase()


## The live part whose shell the impact landed in, if any.
func _struck_part(at: Vector3) -> Part:
	var local := model.to_local(at)
	for name: String in ROTORS:
		var part: Part = parts[name]
		var blade := (local - part.offset) / Vector3(ROTOR_RADIUS + 0.35, 0.9, ROTOR_RADIUS + 0.35)
		if part.hp > 0.0 and blade.length_squared() <= 1.0:
			return part
	var nearest: Part = null
	var nearest_distance := 0.35
	for part: Part in parts.values():
		if part.hp <= 0.0 or part.name in PLATES:
			continue
		var distance := at.distance_to(model.global_transform * part.offset) - part.radius * MODEL_SCALE
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = part
	return nearest


## Which ERA plate covers the airframe at a local impact point: the nose, a flank below the
## rotors, or none (top, belly, tail boom).
static func _plate_facing(local: Vector3) -> String:
	if local.z < -5.6 and absf(local.x) < 2.4:
		return "era_front"
	if local.z < 2.0 and local.z > -4.4 and local.y < 1.6 and absf(local.x) > 1.8:
		return "era_left" if local.x < 0.0 else "era_right"
	return ""


func damage_multiplier(hit: Hit) -> float:
	var multiplier := super(hit)
	match hit.kind:
		Hit.Kind.FRAGMENT:
			multiplier *= 1.5 # Airburst fragments shred rotorcraft.
		Hit.Kind.BULLET:
			multiplier *= 0.4 # Machine guns only scratch it; the main gun does the work.
	return multiplier


func _lose_part(part: Part, direction := Vector3.ZERO) -> void:
	var world := World.current
	var at: Vector3 = model.global_transform * part.offset
	part.hp = 0.0
	var push := (at - global_position).normalized() if direction == Vector3.ZERO else direction.normalized()
	world.fx.explosion(at, 2.5 if part.module else 1.6)
	world.fx.debris(at, 14, [Fx.Debris.ARMOR, Fx.Debris.METAL], 14.0, 0.4, push)
	world.shake(0.4)
	world.hitstop(0.06)
	world.award(1500, at, false)
	Sfx.play("blast", at)
	if part.node:
		# Torn off, it tumbles away burning and blows up where it lands.
		Wreck.launch(part.node, at, part.radius * MODEL_SCALE, true, push * 10.0 + Vector3.UP * 6.0)
	match part.name:
		"rotor_l", "rotor_r":
			_rotors.erase(part.name)
			stagger = maxf(stagger, 1.2)
		"chin":
			if _attack == Attack.ATGM:
				_end_attack()
		"gatling_l", "gatling_r":
			var index := GATLINGS.find(part.name)
			_gatlings[index] = null
			_barrels[index] = null
			if _attack == Attack.GUN and GATLINGS.all(func(name: String) -> bool: return not _live(name)):
				_end_attack()
		"nose_gun":
			if _attack == Attack.CANNON:
				_end_attack()
		"bay":
			if _attack == Attack.BOMBS:
				_end_attack()
		"pod_l", "pod_r":
			# Cooking off the remaining rockets.
			hp -= max_hp * 0.05
			if not (_live("pod_l") or _live("pod_r")) and _attack == Attack.ROCKETS:
				_end_attack()
			# The gatling slung under the rack goes down with it.
			var gatling: Part = parts["gatling_l" if part.name == "pod_l" else "gatling_r"]
			if gatling.hp > 0.0:
				_lose_part(gatling, direction)
	_update_phase()


func _update_phase() -> void:
	if _crash > 0.0 or hp <= 0.0:
		return
	var world := World.current
	var ratio := hp / max_hp
	var lost := MODULE_HP.keys().filter(func(name: String) -> bool: return not _live(name)).size()
	if phase == Phase.HUNTER and (ratio < 0.7 or lost >= 3 or PLATES.all(func(plate: String) -> bool: return not _live(plate))):
		phase = Phase.STRIPPED
		_resupply()
		_grow_fungus(6)
		_next_attack = 1.0
	elif phase == Phase.STRIPPED and (ratio < 0.34 or lost >= 6):
		phase = Phase.INFECTED
		_resupply()
		_grow_fungus(14)
		world.screen_flash(Palette.FUNGUS, 0.4)
		Sfx.play("roar", global_position, 6.0, 0.7)
		_next_attack = 0.8


## Drops fresh ERA and a regrowth pod near the tank at each phase change.
func _resupply() -> void:
	var world := World.current
	var tank := player()
	if tank == null:
		return
	world.spawn_pickup("era", tank.global_position + tank.global_basis.x * 8.0 + Vector3.UP * 1.5)
	world.spawn_pickup("tail", tank.global_position - tank.global_basis.x * 8.0 + Vector3.UP * 1.5)


func behave(delta: float) -> void:
	var world := World.current
	var tank := player()
	for name: String in _rotors:
		_rotors[name].rotation.y += delta * 28.0 * (-1.0 if name == "rotor_l" else 1.0)
	if _crash > 0.0:
		_update_crash(delta)
		return
	if tank == null:
		return
	_flare_cooldown -= delta
	_watch_for_shells()
	# Orbit the arena center, keeping the tank in front.
	var center := Course.to_world(Course.ARENA_CENTER_D, 0.0)
	var orbit_radius := [70.0, 50.0, 42.0][phase] as float
	var altitude := [24.0, 18.0, 15.0][phase] as float
	var speed := [0.18, 0.3, 0.42][phase] as float
	if not (_live("rotor_l") and _live("rotor_r")):
		speed *= 0.6
		altitude *= 0.7
	_smoke_modules(delta)
	if randf() < delta * 0.15:
		_orbit_dir = -_orbit_dir
	_orbit_angle += _orbit_dir * speed * delta * (0.3 if is_staggered() else 1.0)
	var focus := tank.global_position.lerp(center, 0.5)
	var goal := focus + Vector3(cos(_orbit_angle), 0, sin(_orbit_angle)) * orbit_radius
	goal.y = Course.height_at(goal) + altitude
	if phase == Phase.INFECTED:
		_jitter = _jitter.lerp(Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-6, 6)), delta * 2.0)
		goal += _jitter
		_spore_timer -= delta
		if _spore_timer <= 0.0:
			_spore_timer = 0.7
			var drop := global_position
			drop.y = Course.height_at(drop)
			Hazard.spawn(drop + Vector3.UP, 3.0, 3.0, 6.0)
			world.fx.spores(global_position, 16, 3.0)
	if _attack == Attack.DIVE:
		goal = tank.global_position + Vector3.UP * 5.0
	if is_staggered():
		goal.y -= 5.0
	goal.y = maxf(goal.y, Course.height_at(goal) + MIN_CLEARANCE)
	var accel := (goal - global_position) * 1.6 - _velocity * 1.4
	_velocity += accel * delta
	global_position += _velocity * delta
	# However hard it is knocked about, it stays in the air until it actually crashes.
	var floor_y := Course.height_at(global_position) + MIN_CLEARANCE
	if global_position.y < floor_y:
		global_position.y = floor_y
		_velocity.y = maxf(_velocity.y, 0.0)
	# Nose at the tank, bank into the turn.
	var to_tank := tank.global_position - global_position
	var yaw := atan2(-to_tank.x, -to_tank.z)
	model.rotation.y = lerp_angle(model.rotation.y, yaw, 2.5 * delta)
	var lateral := _velocity.dot(model.global_basis.x)
	var damaged_bank := 0.0
	if not _live("rotor_l"):
		damaged_bank = 0.3
	elif not _live("rotor_r"):
		damaged_bank = -0.3
	model.rotation.z = lerpf(model.rotation.z, clampf(-lateral * 0.04, -0.15, 0.15) + damaged_bank, 3.0 * delta)
	model.rotation.x = lerpf(model.rotation.x, -_velocity.dot(-model.global_basis.z) * 0.02 - 0.08, 3.0 * delta)
	if _live("chin"):
		_chin.look_at(tank.hit_center(), Vector3.UP)
	for gatling in _gatlings:
		if gatling:
			gatling.look_at(tank.hit_center(), Vector3.UP)
	for barrels in _barrels:
		if barrels:
			barrels.rotation.z += delta * (30.0 if _attack == Attack.GUN else 2.0)
	_update_attack(delta, tank)


## Fire and smoke from the stumps of wrecked modules.
func _smoke_modules(delta: float) -> void:
	var world := World.current
	for name: String in MODULE_HP:
		if not _live(name) and randf() < delta * 16.0:
			var at: Vector3 = model.global_transform * parts[name].offset
			for i in 2:
				world.fx.spawn(Fx.Kind.FLAME, at + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), Vector3.UP * randf_range(3.0, 5.0), randf_range(0.4, 0.6), randf_range(1.8, 2.8), [Palette.AMBER, Palette.BUTTER, Palette.CORAL][randi() % 3], {"drag": 1.0})
			world.fx.spawn(Fx.Kind.GLOW, at, Vector3(randf_range(-0.6, 0.6), randf_range(3.0, 5.0), randf_range(-0.6, 0.6)), randf_range(2.0, 3.0), 2.4, [Palette.INK, Palette.DUSK, Palette.SLATE][randi() % 3], {"end_size": 8.0, "drag": 0.6, "fade": 0.3})


func _watch_for_shells() -> void:
	if phase == Phase.HUNTER or _flare_cooldown > 0.0:
		return
	var world := World.current
	for projectile in world.projectiles:
		if projectile.team != Team.PLAYER or projectile.hit.caliber < 100:
			continue
		if projectile.global_position.distance_to(global_position) < 45.0 and projectile.velocity.dot(global_position - projectile.global_position) > 0.0:
			_pop_flares()
			return


func _pop_flares() -> void:
	var world := World.current
	_flare_cooldown = 5.0 if not _hard else 3.5
	Sfx.play("launch", global_position, 0.0, 1.5)
	for i in 6:
		var flare: Flare = Flare.new()
		var side := -1.0 if i % 2 == 0 else 1.0
		flare.drift = model.global_basis.x * side * randf_range(8, 14) + Vector3.UP * randf_range(2, 6) - model.global_basis.z * randf_range(-4, 4)
		flare.position = global_position + model.global_basis.x * side
		world.add_enemy(flare)


func _update_attack(delta: float, tank: Tank) -> void:
	if _attack == Attack.NONE:
		_next_attack -= delta
		if _next_attack <= 0.0 and not is_staggered():
			_choose_attack()
		return
	_attack_time += delta
	match _attack:
		Attack.GUN:
			_gun(delta, tank)
		Attack.ROCKETS:
			_rockets(delta, tank)
		Attack.BOMBS:
			_bombs(tank)
		Attack.CANNON:
			_cannon(delta, tank)
		Attack.ATGM:
			if _attack_time < 1.3:
				set_meta("locking", true)
				if fmod(_attack_time, 0.1) < 0.05:
					World.current.fx.beam(_chin.global_position, tank.hit_center(), Palette.RED, 0.05, 0.05)
			else:
				set_meta("locking", false)
				for i in (2 if phase == Phase.STRIPPED else 3):
					_launch_atgm(tank, i)
				_end_attack()
		Attack.DRONES:
			if _attack_time > 0.6:
				var wave := {"d": 0.0, "kind": "fpv", "count": 3 if not _hard else 5, "formation": "ring", "height": 0.0, "spacing": 5.0, "ahead": 0.0, "hover": 18.0, "approach": 1.0}
				var spawned: Array[Enemy] = World.current.director.spawn_wave(wave)
				for drone in spawned:
					drone.global_position = global_position + Vector3(randf_range(-4, 4), -1.0, randf_range(-4, 4))
				_end_attack()
		Attack.DIVE:
			if _attack_time > 2.2:
				_end_attack()
			elif tank.global_position.distance_to(global_position) < 9.0:
				var hit := Hit.make(Hit.Kind.RAM, 20.0, global_position, (tank.global_position - global_position).normalized())
				hit.source = self
				tank.take_hit(hit)
				_end_attack()


func _choose_attack() -> void:
	var options: Array[Attack] = [Attack.GUN, Attack.ROCKETS, Attack.CANNON]
	match phase:
		Phase.STRIPPED:
			options = [Attack.GUN, Attack.ROCKETS, Attack.CANNON, Attack.ATGM, Attack.DRONES, Attack.BOMBS]
		Phase.INFECTED:
			options = [Attack.GUN, Attack.ROCKETS, Attack.CANNON, Attack.ATGM, Attack.BOMBS, Attack.DIVE, Attack.ROCKETS]
	# A wrecked module takes its attack with it.
	var armed := {
		Attack.GUN: GATLINGS.any(func(name: String) -> bool: return _live(name)),
		Attack.ROCKETS: _live("pod_l") or _live("pod_r"),
		Attack.ATGM: _live("chin"),
		Attack.CANNON: _live("nose_gun"),
		Attack.BOMBS: _live("bay"),
	}
	options = options.filter(func(attack: Attack) -> bool: return armed.get(attack, true))
	if options.is_empty():
		options = [Attack.DIVE]
	_attack = options.pick_random()
	_attack_time = 0.0
	_shots = 0
	match _attack:
		Attack.GUN:
			Sfx.play("warn", global_position, 0.0, 1.2)
		Attack.ROCKETS:
			Sfx.play("warn", global_position, 2.0, 0.8)
		Attack.ATGM:
			Sfx.play("lock", global_position)
		Attack.CANNON, Attack.BOMBS:
			Sfx.play("warn", global_position, 2.0, 0.6)
		Attack.DIVE:
			Sfx.play("roar", global_position, 0.0, 1.4)


func _end_attack() -> void:
	_attack = Attack.NONE
	set_meta("locking", false)
	var pause := [2.2, 1.6, 1.1][phase] as float
	_next_attack = pause * (0.8 if _hard else 1.0) + randf() * 0.6


func _gun(delta: float, tank: Tank) -> void:
	var world := World.current
	var live: Array = _barrels.filter(func(b: Node3D) -> bool: return is_instance_valid(b))
	if live.is_empty():
		_end_attack()
		return
	if _attack_time < 0.6:
		# Telegraph: sight beam sweeping onto the tank.
		if fmod(_attack_time, 0.12) < 0.06:
			var sight: Node3D = _chin if _live("chin") else live[0]
			world.fx.beam(sight.global_position, tank.hit_center(), Palette.CORAL, 0.04, 0.05)
		return
	_shot_timer -= delta
	var total := [14, 18, 24][phase] as int
	if _shot_timer <= 0.0 and _shots < total:
		_shots += 1
		_shot_timer = 0.07
		# The shoulder gatlings take turns, so the stream visibly comes from both sides.
		var from: Vector3 = (live[_shots % live.size()] as Node3D).global_transform * Vector3(0, 0, -2.0)
		var lead := tank.hit_center() + tank.velocity * (from.distance_to(tank.hit_center()) / GUN_SPEED) * 0.7
		var wild := 1.0 if _live("rotor_l") and _live("rotor_r") else 2.0
		# 40 mm high-explosive rounds: each one hits hard and bursts where it lands.
		var shot := fire_at("orb", from, lead + Vector3(randf_range(-1.5, 1.5), randf_range(-0.5, 0.5), randf_range(-1.5, 1.5)) * wild, GUN_SPEED, 9.0)
		shot.hit.caliber = 40
		shot.blast_radius = 2.2
		shot.blast_damage = 5.0
		world.fx.spawn(Fx.Kind.FLAME, from, Vector3.ZERO, 0.05, 0.4, Palette.CORAL)
		Sfx.play("enemy_gun", from, 4.0, 0.55)
	elif _shots >= total:
		_end_attack()


func _rockets(delta: float, tank: Tank) -> void:
	if not (_live("pod_l") or _live("pod_r")):
		_end_attack()
		return
	var world := World.current
	if _attack_time < 0.8:
		for side in ["pod_l", "pod_r"]:
			var part: Part = parts[side]
			if part.hp > 0.0 and fmod(_attack_time, 0.16) < 0.08:
				flash()
		return
	_shot_timer -= delta
	var total := [12, 14, 20][phase] as int
	if _shot_timer <= 0.0 and _shots < total:
		var side: String = "pod_l" if _shots % 2 == 0 else "pod_r"
		if not _live(side):
			side = "pod_r" if side == "pod_l" else "pod_l"
		_shots += 1
		_shot_timer = 0.09 if phase != Phase.INFECTED else 0.06
		var from: Vector3 = model.global_transform * (parts[side].offset + Vector3(0, 0, -1.0))
		var spread := 7.0 if phase != Phase.INFECTED else 11.0
		var target := tank.global_position + tank.velocity * 0.8 + Vector3(randf_range(-spread, spread), 0, randf_range(-spread, spread))
		if phase == Phase.INFECTED:
			var angle := _shots * 0.7
			target = tank.global_position + Vector3(cos(angle), 0, sin(angle)) * (4.0 + _shots * 0.4)
		target.y = Course.height_at(target)
		var rocket := fire_at("rocket", from, target, ROCKET_SPEED, 0.0)
		rocket.hit = Hit.make(Hit.Kind.SHELL, 0.0, from)
		rocket.hit.source = self
		rocket.blast_radius = 4.0
		rocket.blast_damage = 20.0
		rocket.interceptable = true
		rocket.intercept_hp = 1.1 # Twice the laser's work of an ordinary rocket.
		rocket.trail = Projectile.ROCKET_SMOKE
		rocket.life = 4.0
		world.fx.spawn(Fx.Kind.FLAME, from, Vector3.ZERO, 0.08, 0.6, Palette.BUTTER)
		Sfx.play("launch", from, -2.0, randf_range(1.1, 1.3))
	elif _shots >= total:
		_end_attack()


## Nose cannon: three shells that arrive almost the instant they are fired, so each is warned
## first: the barrel glows hotter, a warning tone sounds and a sight line settles on where the
## shell will land, then it fires.
func _cannon(delta: float, tank: Tank) -> void:
	var world := World.current
	var muzzle: Vector3 = model.global_transform * (parts.nose_gun.offset + Vector3(0, 0, -4.2))
	var cycle := CANNON_AIM + 0.25
	var index := int(_attack_time / cycle)
	if index >= 3:
		_end_attack()
		return
	if _shots > index:
		return
	var aiming := _attack_time - index * cycle
	if aiming < CANNON_AIM - CANNON_LOCK:
		# Tracking: a flickering sight line follows the tank.
		_cannon_aim = tank.hit_center() + tank.velocity * (muzzle.distance_to(tank.hit_center()) / CANNON_SPEED)
		if aiming < delta:
			Sfx.play("lock", muzzle, 4.0, 1.3)
		if fmod(aiming, 0.1) < 0.06:
			world.fx.beam(muzzle, _cannon_aim, Palette.HOT, 0.06 + aiming * 0.15, 0.05)
	if aiming < CANNON_AIM:
		if aiming >= CANNON_AIM - CANNON_LOCK:
			# Locked: the line goes solid and stops following. This is the moment to dash.
			if aiming - delta < CANNON_AIM - CANNON_LOCK:
				Sfx.play("warn", muzzle, 4.0, 1.6)
			world.fx.beam(muzzle, _cannon_aim, Palette.HOT, 0.2, 0.03)
		world.fx.spawn(Fx.Kind.FLAME, muzzle, Vector3.ZERO, 0.06, 0.3 + aiming * 1.2, Palette.HOT)
		return
	var lead := _cannon_aim
	_shots += 1
	var shell := fire_at("shell", muzzle, lead, CANNON_SPEED, 0.0)
	shell.hit = Hit.make(Hit.Kind.SHELL, 10.0, muzzle)
	shell.hit.source = self
	shell.blast_radius = 4.5
	shell.blast_damage = 30.0
	shell.interceptable = true
	shell.intercept_hp = 10.0 # Ten times what the laser could burn through before.
	_velocity -= (lead - muzzle).normalized() * 3.0
	Sfx.play("cannon", muzzle, 0.0, 1.3)


## Bomb bay: red circles walk along the tank's path, then the bombs fall onto them.
func _bombs(tank: Tank) -> void:
	if _attack_time < 0.4 or _shots > 0:
		if _shots > 0 and _attack_time > 2.6:
			_end_attack()
		return
	var world := World.current
	var from: Vector3 = model.global_transform * parts.bay.offset
	var count := [6, 8, 10][phase] as int
	_shots = count
	for i in count:
		var flight := BOMB_FLIGHT + i * 0.08
		var target := tank.global_position + tank.velocity * flight + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		target.y = Course.height_at(target)
		var velocity_out := (target - from) / flight
		velocity_out.y += 0.5 * 20.0 * flight
		var bomb := world.spawn_projectile(Team.ENEMY, from, velocity_out, "bomb", Palette.HOT)
		bomb.gravity = 20.0
		bomb.hit = Hit.make(Hit.Kind.BLAST, 0.0, from)
		bomb.hit.source = self
		bomb.blast_radius = 5.0
		bomb.blast_damage = 30.0
		bomb.interceptable = true
		bomb.intercept_hp = 0.8
		bomb.life = flight + 1.0
		world.fx.marker(target, 5.0, flight, Palette.RED)
	Sfx.play("launch", from, 0.0, 0.7)


func _launch_atgm(tank: Tank, index: int) -> void:
	var from := _chin.global_position + model.global_basis.x * (index - 1) * 1.5
	var missile := fire_at("atgm", from, from + Vector3.UP * 2.0 + model.global_basis.x * (index - 1) * 4.0 + (tank.hit_center() - from).normalized() * 4.0, ATGM_SPEED, 0.0)
	missile.hit = Hit.make(Hit.Kind.SHELL, 0.0, from)
	missile.hit.source = self
	missile.blast_radius = 4.0
	missile.blast_damage = 40.0
	missile.hit.warhead = true
	missile.homing_target = tank
	missile.turn_rate = 2.0
	missile.interceptable = true
	missile.intercept_hp = 5.6 # Four times as hard for the laser to burn down as before.
	missile.life = 7.0
	missile.trail = Projectile.ROCKET_SMOKE
	Sfx.play("launch", from, 2.0, 0.8)


func _begin_crash() -> void:
	var world := World.current
	_crash = 3.2
	_end_attack()
	if _rotor_sound:
		_rotor_sound.stop()
	_crash_from = global_position
	_crash_to = Dam.crash_point(Course.to_course(_crash_from).y)
	world.camera.watch(self)
	hp = 0.0
	world.boss_changed.emit(null)
	world.shake(0.7)
	world.hitstop(0.25)
	world.screen_flash(Palette.WHITE, 0.7)
	Sfx.play("blast", global_position)
	for side in ["pod_l", "pod_r"]:
		if _live(side):
			_lose_part(parts[side])
	hp = 0.0


## Engine on fire, spinning, it arcs into the dam face and explodes against it.
func _update_crash(delta: float) -> void:
	var world := World.current
	_crash -= delta
	var k := 1.0 - _crash / 3.2
	global_position = _crash_from.lerp(_crash_to, k * k) + Vector3.UP * sin(k * PI) * 6.0
	model.rotation.y += delta * (4.0 + k * 10.0)
	model.rotation.z = lerpf(model.rotation.z, 0.6, delta)
	if randf() < delta * 20.0:
		world.fx.spawn(Fx.Kind.FLAME, global_position + Vector3(randf_range(-1, 1), 1, randf_range(-1, 1)), Vector3(0, 3, 0), 0.5, 1.2, [Palette.PEACH, Palette.CORAL, Palette.BUTTER][randi() % 3])
		world.fx.smoke(global_position, 1, 2.0, [Palette.STONE, Palette.ASH, Palette.DUSK])
	if _crash <= 0.0:
		global_position = _crash_to
		_crash_blast(_crash_to)
		die(Hit.make(Hit.Kind.BLAST, 9999.0, global_position))


## The wreck slams into the dam: a chain of big fireballs, shockwaves, a ring of dust and burning
## chunks of airframe and concrete thrown out over the arena.
func _crash_blast(at: Vector3) -> void:
	var world := World.current
	var fx := world.fx
	var ground := Vector3(at.x, Course.height_at(at), at.z)
	var out := -Course.forward(Course.DAM_D) # From the face, into the arena.
	for i in 4:
		fx.explosion(at + Vector3(randf_range(-9, 9), randf_range(-4, 8), randf_range(-6, 6)), 6.0 + i % 3, [Palette.WHITE, Palette.BUTTER, Palette.AMBER, Palette.CORAL], out * 0.3)
	for i in 4:
		fx.fireball(at + Vector3(randf_range(-8, 8), randf_range(-3, 7), randf_range(-4, 6)), 4.0, randf_range(13.0, 19.0), randf_range(0.9, 1.3))
	for i in 7:
		fx.explosion_after(0.14 + i * 0.14 + randf() * 0.08, at + Vector3(randf_range(-14, 14), randf_range(-6, 10), randf_range(-8, 8)), randf_range(4.5, 8.0))
	fx.shockwave(at, 70.0, Palette.BUTTER, 0.6)
	fx.shockwave(at, 110.0, Palette.WHITE, 0.9)
	fx.shockwave(ground, 95.0, Palette.MIST, 1.2)
	fx.dust(ground, 45, 14.0, Palette.MIST)
	fx.dust(ground, 30, 10.0, Palette.OCHRE)
	fx.debris(at, 28, debris + [Fx.Debris.CONCRETE, Fx.Debris.ROCK], 30.0, 0.9, out * 0.3)
	fx.shatter(AABB(at - Vector3(10, 8, 6), Vector3(20, 16, 12)), [Fx.Debris.CONCRETE, Fx.Debris.ROCK], out * 0.3, 0.2)
	for i in 20:
		var dir := (Vector3(randf_range(-1, 1), randf_range(0.5, 1.6), randf_range(-1, 1)).normalized() + out * 0.4).normalized()
		fx.spawn(Fx.Kind.FLAME, at, dir * randf_range(10, 26), randf_range(1.2, 2.4), randf_range(0.5, 0.9), Palette.PEACH, {"gravity": 18.0, "trail": Palette.ASH, "end_size": 0.2, "fade": 0.8})
	fx.smoke_column(at, 12.0)
	fx.smoke(at, 14, 7.0)
	for spot in [Vector3(-8, 0, 0), Vector3(6, 0, 4), Vector3(0, 0, -3)]:
		fx.burn(ground + spot, 9.0, 2.4)
	fx.light_flash(at, 40.0, Palette.WHITE, 120.0)
	world.shake(1.0)
	world.hitstop(0.3)
	world.screen_flash(Palette.WHITE, 0.9)
	Sfx.play("blast", at, 8.0, 0.55)
	Sfx.play("blast", at, 4.0, 0.8)
	if is_instance_valid(Dam.current):
		Dam.current.breach(at)


func on_death(_hit: Hit) -> void:
	var world := World.current
	world.fx.debris(global_position, 30, debris, 18.0, 0.7)
	world.fx.spores(global_position, 60, 8.0)
	world.award(score, global_position, true)
	world.style_event("GIANT", 400.0)
	Sfx.play("blast", global_position, 6.0, 0.7)
