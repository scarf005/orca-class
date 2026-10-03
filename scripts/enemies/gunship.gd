class_name Gunship
extends Enemy
## Stage 1 boss: a heavy synchrocopter gunship overtaken by mycelium, after Armored Core VI's
## AH12 HC: a long armored hull, two intermeshing rotors on masts splayed in a V above it, stub
## wings ending in huge missile racks, gatling turrets on the shoulders and a searchlight nose.
## Nose and flank plates protect the hull: a full charge or a HEAT round pops one, a plain shell only
## cracks it. A few bare-airframe cannon hits empty the hull, and a full charge counts as two.
## Every weapon and rotor is its own module with its own health: hitting one hurts only it (a rotor
## takes three cannon hits, anything else two), and wrecking it tears it off the airframe and
## silences that attack. One rotor lost lowers and banks the craft. Only the last phase can crash:
## earlier, losing both rotors or the hull makes it recover into the next phase instead. Weapons: two shoulder gatlings, a nose cannon, a chin ATGM drum,
## two wing rocket racks and a belly bomb bay. The three phases add flares, drone calls and the
## infected dive before the crash into the dam.

enum Phase { HUNTER, STRIPPED, INFECTED }
enum Attack { NONE, GUN, ROCKETS, ATGM, DRONES, DIVE, BOMBS, CANNON }

const BODY_HP := 1600.0
const CANNON_SHARE := 0.1 ## Hull taken by one full-charge main-gun hit wherever it lands: ten of them bring it down.
const QUICK_WEIGHT := 0.5 ## A quick shell, or the blast of one that missed, counts as this much of a hit.
const SHELL_WINDOW := 0.3 ## Seconds in which a shell's direct hit and its blast count as one: together never more than its own weight.
const AREA_ROUNDS := ["airburst", "canister"] ## Their hits, like every machine-gun round and fragment, glance off its armor.
const SIDE_RATE := 16.0 ## Most hull per second that everything but the main gun and the machine guns takes together (wreck and chain blasts, rams, the tail, a dragon's breath).
const ROTOR_HITS := 3 ## Full-charge hits that wreck a rotor.
const MODULE_HITS := 2 ## Full-charge hits that wreck any other module.
const COAX_MODULE := 0.2 ## Share of a machine-gun round's damage a weapon takes; the airframe and plates shrug it off.
const PHASE_MARKS := [0.7, 0.34] ## Hull fraction at which the next phase begins.
const ERA_HP := 100.0 ## A full charge or HEAT pops a plate, a plain shell cracks half of it; machine guns glance off.
const MODULE_HP := {"rotor_l": 150.0, "rotor_r": 150.0, "chin": 90.0, "pod_l": 140.0, "pod_r": 140.0,
	"gatling_l": 80.0, "gatling_r": 80.0, "nose_gun": 110.0, "bay": 120.0}
const GATLINGS := ["gatling_l", "gatling_r"]
const PART_LABELS := {"rotor_l": "ROTOR L", "rotor_r": "ROTOR R", "chin": "ATGM", "pod_l": "RACK L", "pod_r": "RACK R",
	"gatling_l": "GUN L", "gatling_r": "GUN R", "nose_gun": "CANNON", "bay": "BOMBS"}
const WINDOW := [2.2, 1.6, 1.6] ## Seconds of steady hover after each attack, per phase: time for a full charge and its aim.
const GUN_SPEED := MG_SPEED
const ROCKET_SPEED := 85.0
const ATGM_SPEED := 45.0
const BOMB_FLIGHT := 0.9 ## Seconds from the bay to the ground for the first bomb.
const CANNON_SPEED := 450.0 ## The nose cannon's shells arrive almost at once, so each shot is warned first.
const CANNON_AIM := 0.7 ## Seconds of warning before each cannon shot.
const CANNON_LOCK := 0.35 ## For the last of the warning the aim holds still: move now and it misses.
const CANNON_BRAKE := 8.0 ## Per second the airframe sheds its drift while the cannon takes its shots.
const GATLING_TRACER := 22.0 ## Length of the bright streak each gatling round draws.
const GATLING_SLEW := 3.0 ## Radians per second the shoulder guns, the chin drum and the racks turn onto their aim.
const CHIN_SLEW := 2.0
const RACK_SLEW := 4.0
const CANNON_SLEW := 6.0 ## The nose cannon traverses onto its target while the line follows; the lock then holds it.
const GUN_SPREAD := 0.025 ## Radians of scatter on a gatling round (doubled with a rotor gone).
const RACK_CELLS := [Vector2(-0.45, -0.9), Vector2(0.45, 0.0), Vector2(-0.45, 0.9), Vector2(0.45, -0.9), Vector2(-0.45, 0.0), Vector2(0.45, 0.9)]
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
var _gatling_muzzles: Array[Node3D] = []
var _chin := Node3D.new()
var _chin_muzzles: Array[Node3D] = [] ## One per launch tube of the ATGM drum.
var _rack_muzzles := {} ## Rack part name -> muzzle node; it steps from cell to cell.
var _rack_aim := {} ## Rack part name -> world point its next rocket is meant for.
var _nose_muzzle := Node3D.new()
var _cannon_hold := Vector3.ZERO ## While locked, the world direction the cannon barrel holds.
var _fungus := Node3D.new()
var _shots := 0
var _spin := 2.0 ## Radians per second the gatling barrels turn.
var _shot_timer := 0.0
var _flare_cooldown := 0.0
var _spore_timer := 0.0
var _crash := 0.0
var _crash_from := Vector3.ZERO
var _crash_to := Vector3.ZERO ## Where it hits the dam: in front of the face, up where the camera sees it.
var _cannon_aim := Vector3.ZERO ## Where the nose cannon's next shell is locked to go.
var _hard := false
var _shell_time := -1.0 ## Age at the last direct main-gun hit.
var _splash := 0.0 ## Weight of the last blast of the main gun, and the age it landed at: a direct hit just after it only adds the rest.
var _splash_time := -1.0
var _side_time := -1.0 ## Start of the second the hull taken from side hits is counted in.
var _side_taken := 0.0
var _rotor_sound: AudioStreamPlayer3D
var _jitter := Vector3.ZERO


func _init() -> void:
	super()
	radius = 6.0
	armor = 40.0
	center_height = 0.0
	flying = true
	trails = true
	can_stagger = true
	score = 50000
	despawn_behind = 0.0
	debris = [Fx.Debris.ARMOR, Fx.Debris.METAL, Fx.Debris.GLASS, Fx.Debris.FLESH]
	set_meta("title", "BOSS_GUNSHIP")
	set_meta("phase_marks", PHASE_MARKS)


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
	for side in [-1.0, 1.0]:
		_build_rotor(side)
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
		var muzzle := Node3D.new()
		muzzle.position = Vector3(0, 0, -2.8)
		turret.add_child(muzzle)
		_gatlings.append(turret)
		_barrels.append(barrels)
		_gatling_muzzles.append(muzzle)
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
	for x in [-0.45, 0.0, 0.45]:
		var tube := Node3D.new()
		tube.position = Vector3(x, 0, -1.6)
		_chin.add_child(tube)
		_chin_muzzles.append(tube)
	_add_part("era_left", Vector3(-2.6, 0.0, -1.2), 2.0, ERA_HP, _panel_mesh(-1.0))
	_add_part("era_right", Vector3(2.6, 0.0, -1.2), 2.0, ERA_HP, _panel_mesh(1.0))
	_add_part("era_front", Vector3(0, 0.4, -6.9), 1.6, ERA_HP, _nose_mesh())
	_add_part("pod_l", Vector3(-6.4, -0.4, 0.2), 2.4, MODULE_HP.pod_l, _pod_mesh())
	_add_part("pod_r", Vector3(6.4, -0.4, 0.2), 2.4, MODULE_HP.pod_r, _pod_mesh())
	_add_part("chin", _chin.position, 1.1, MODULE_HP.chin, null)
	parts.chin.node = _chin
	_add_part("nose_gun", Vector3(0, -1.3, -7.6), 1.0, MODULE_HP.nose_gun, _nose_gun_mesh())
	for side in ["pod_l", "pod_r"]:
		var rack_muzzle := Node3D.new()
		rack_muzzle.position = Vector3(0, 0, -2.9)
		(parts[side].node as Node3D).add_child(rack_muzzle)
		_rack_muzzles[side] = rack_muzzle
	(parts.nose_gun.node as Node3D).add_child(_nose_muzzle)
	_nose_muzzle.position = Vector3(0, 0, -4.2)
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


## Intermeshing rotors: each head leans outward on its mast and spins the opposite way.
func _build_rotor(side: float) -> void:
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
	var glance := hit.kind in [Hit.Kind.BULLET, Hit.Kind.FRAGMENT] or hit.weapon in AREA_ROUNDS
	var splash := not glance and hit.kind == Hit.Kind.BLAST and hit.weapon == "cannon" and hit.caliber >= 100
	var cannon := not glance and (splash or hit.kind == Hit.Kind.SHELL and hit.caliber >= 100)
	var hull := _cannon_strike(hit, splash) if cannon else _side_strike(hit, glance)
	hp -= hull
	var amount := hit.damage * damage_multiplier(hit) if cannon else hull
	var falls := hp <= 0.0
	impact_feedback(hit, amount, falls and phase == Phase.INFECTED)
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
	if falls and phase == Phase.INFECTED:
		killing_hit = hit.copy()
		_begin_crash()
		return
	if falls:
		_recover()
		return
	_update_phase()


## A main-gun hit: a full charge is one share of the hull wherever it lands, a quick shell or a blast
## half of one, and one shell's direct hit and blasts together never add up to more than its own
## weight. The struck module or plate takes its own fixed share on top. Returns the hull taken.
func _cannon_strike(hit: Hit, splash: bool) -> float:
	var world := World.current
	var charged := hit.power >= 1.0
	var weight := 1.0 if charged and not splash else QUICK_WEIGHT
	var share := max_hp * CANNON_SHARE
	if splash:
		if age - _shell_time < SHELL_WINDOW:
			return 0.0
		_splash = weight
		_splash_time = age
		return share * weight # A blast bursts in the air or on the ground, not on the airframe: it only ever takes the hull share.
	var owed := weight - (_splash if age - _splash_time < SHELL_WINDOW else 0.0)
	_shell_time = age
	_splash = 0.0
	var hull := share * owed
	var struck := _struck_part(hit.position)
	var plate := _plate_facing(model.to_local(hit.position))
	if struck and struck.module:
		struck.hp -= MODULE_HP[struck.name] / float(ROTOR_HITS if struck.name in ROTORS else MODULE_HITS) * weight
		world.fx.sparks(hit.position, -hit.direction, 10, Palette.BUTTER, 12.0)
		if struck.hp <= 0.0:
			_lose_part(struck, hit.direction)
	elif plate != "" and _live(plate):
		# ERA on the struck facing detonates outward and eats the shell.
		var era: Part = parts[plate]
		era.hp -= ERA_HP * (1.0 if charged or hit.pierce else 0.5)
		world.fx.sparks(hit.position, -hit.direction, 8, Palette.WHITE, 9.0)
		if era.hp <= 0.0:
			_lose_part(era, hit.direction)
		else:
			# A plate that held: cracked, glowing and shedding chips.
			world.fx.sparks(hit.position, -hit.direction, 14, Palette.AMBER, 14.0)
			world.fx.debris(hit.position, 6, [Fx.Debris.ARMOR], 9.0, 0.3, -hit.direction)
	return hull


## Everything but the main gun's shells. Machine-gun rounds, fragments and the area rounds glance off the
## airframe and plates for nothing; only a machine-gun round that meets a weapon (not a rotor) hurts it, a
## fifth as much. Blasts of wrecks, rams, the tail and the rest together take at most SIDE_RATE hull a second,
## so none of them shortcuts the fight. Returns the hull taken.
func _side_strike(hit: Hit, glance: bool) -> float:
	var world := World.current
	if glance:
		var struck := _struck_part(hit.position)
		if hit.kind == Hit.Kind.BULLET and hit.weapon not in AREA_ROUNDS and struck and struck.module and struck.name not in ROTORS:
			struck.hp -= hit.damage * COAX_MODULE
			world.fx.sparks(hit.position, -hit.direction, 3, Palette.BUTTER, 8.0)
			if struck.hp <= 0.0:
				_lose_part(struck, hit.direction)
		else:
			world.fx.ricochet(hit, hit_center())
		return 0.0
	if age - _side_time >= 1.0:
		_side_time = age
		_side_taken = 0.0
	var taken := clampf(hit.damage * damage_multiplier(hit), 0.0, SIDE_RATE - _side_taken)
	_side_taken += taken
	return taken


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
	var ratio := hp / max_hp
	var lost := MODULE_HP.keys().filter(func(name: String) -> bool: return not _live(name)).size()
	if phase == Phase.HUNTER and (ratio < PHASE_MARKS[0] or lost >= 3 or PLATES.all(func(plate: String) -> bool: return not _live(plate))):
		_advance_phase()
	elif phase == Phase.STRIPPED and (ratio < PHASE_MARKS[1] or lost >= 6):
		_advance_phase()


func _advance_phase() -> void:
	phase = (phase + 1) as Phase
	_resupply()
	if phase == Phase.STRIPPED:
		_grow_fungus(6)
		_next_attack = 1.0
	else:
		_grow_fungus(14)
		World.current.screen_flash(Palette.FUNGUS, 0.4)
		Sfx.play("roar", global_position, 6.0, 0.7)
		_next_attack = 0.8


## Before the last phase it cannot fall: with the hull emptied it comes back into the next phase at that phase's hull.
func _recover() -> void:
	hp = max_hp * PHASE_MARKS[phase]
	_end_attack()
	_advance_phase()


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
	var window := _attack == Attack.NONE ## Between attacks it hangs almost still: the moment to charge a shot.
	if window:
		speed *= 0.15
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
		if not window:
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
	if _attack == Attack.CANNON:
		# Steadies itself for the shot: a bore held still only hits if the muzzle stays put too.
		_velocity = _velocity.lerp(Vector3.ZERO, 1.0 - exp(-CANNON_BRAKE * delta))
	global_position += _velocity * delta
	# However hard it is knocked about, it stays in the air until it actually crashes.
	var floor_y := Course.height_at(global_position) + MIN_CLEARANCE
	if global_position.y < floor_y:
		global_position.y = floor_y
		_velocity.y = maxf(_velocity.y, 0.0)
	# Nose at the tank, bank into the turn.
	var to_tank := tank.global_position - global_position
	var yaw := atan2(-to_tank.x, -to_tank.z)
	if _cannon_hold == Vector3.ZERO:
		model.rotation.y = lerp_angle(model.rotation.y, yaw, 2.5 * delta)
	var lateral := _velocity.dot(model.global_basis.x)
	var damaged_bank := 0.0
	if not _live("rotor_l"):
		damaged_bank = 0.3
	elif not _live("rotor_r"):
		damaged_bank = -0.3
	model.rotation.z = lerpf(model.rotation.z, clampf(-lateral * 0.04, -0.15, 0.15) + damaged_bank, 3.0 * delta)
	model.rotation.x = lerpf(model.rotation.x, -_velocity.dot(-model.global_basis.z) * 0.02 - 0.08, 3.0 * delta)
	_aim_weapons(delta, tank)
	# The gatling barrels wind up during the warning and spool down after the burst.
	_spin = move_toward(_spin, 34.0 if _attack == Attack.GUN else 2.0, 45.0 * delta)
	for barrels in _barrels:
		if barrels:
			barrels.rotation.z += delta * _spin
	_update_attack(delta, tank)


## Every barrel turns toward its aim at its own slew rate: the chin drum and gatlings follow the
## tank, the racks the point their next rocket is meant for, and the nose cannon its lead (held
## dead still once the aim locks).
func _aim_weapons(delta: float, tank: Tank) -> void:
	if _live("chin"):
		aim_barrel(_chin, tank.hit_center(), CHIN_SLEW, delta)
	for i in _gatlings.size():
		var gatling := _gatlings[i]
		if gatling:
			var lead := tank.hit_center() + tank.velocity * (gatling.global_position.distance_to(tank.hit_center()) / GUN_SPEED) * 0.7
			aim_barrel(gatling, lead, GATLING_SLEW, delta)
	for side: String in _rack_muzzles:
		if _live(side):
			aim_barrel(parts[side].node, _rack_aim.get(side, tank.global_position), RACK_SLEW, delta)
	if _live("nose_gun"):
		var gun: Node3D = parts.nose_gun.node
		if _cannon_hold != Vector3.ZERO:
			slew_barrel(gun, _cannon_hold, CANNON_SLEW * 4.0, delta)
		else:
			aim_barrel(gun, _cannon_aim if _attack == Attack.CANNON and _cannon_aim != Vector3.ZERO else tank.hit_center(), CANNON_SLEW, delta)


## Fire and smoke from the stumps of wrecked modules.
func _smoke_modules(delta: float) -> void:
	var world := World.current
	for name: String in MODULE_HP:
		var part: Part = parts[name]
		var wear: float = 1.0 - part.hp / MODULE_HP[name]
		if part.hp > 0.0 and wear > 0.0 and randf() < delta * 12.0 * wear:
			# A hurt module trails smoke and throws sparks the worse it is.
			var at: Vector3 = model.global_transform * part.offset
			world.fx.smoke(at, 1, 1.5, [Palette.STONE, Palette.ASH, Palette.DUSK])
			world.fx.sparks(at, Vector3.UP, 3, Palette.BUTTER, 6.0)
		if part.hp <= 0.0 and randf() < delta * 16.0:
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
				# They rise in front of the tank, low and outside the laser's reach, so some meet the tail or the hull.
				var ahead := -tank.global_basis.z
				for drone in spawned:
					drone.global_position = tank.global_position + ahead.rotated(Vector3.UP, randf_range(-0.7, 0.7)) * randf_range(26.0, 34.0)
					drone.global_position.y = Course.height_at(drone.global_position) + 1.5
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
	_cannon_hold = Vector3.ZERO
	_rack_aim.clear()
	set_meta("locking", false)
	_next_attack = (WINDOW[phase] as float) * (0.8 if _hard else 1.0) + randf() * 0.6


func _gun(delta: float, tank: Tank) -> void:
	var world := World.current
	var live := range(_barrels.size()).filter(func(i: int) -> bool: return is_instance_valid(_barrels[i]))
	if live.is_empty():
		_end_attack()
		return
	if _attack_time < 0.6:
		# Telegraph: sight beam sweeping onto the tank.
		if fmod(_attack_time, 0.12) < 0.06:
			var sight: Node3D = _chin if _live("chin") else _gatlings[live[0]]
			world.fx.beam(sight.global_position, tank.hit_center(), Palette.CORAL, 0.04, 0.05)
		return
	_shot_timer -= delta
	var total := [14, 18, 24][phase] as int
	if _shot_timer <= 0.0 and _shots < total:
		_shots += 1
		_shot_timer = 0.07
		# The shoulder gatlings take turns, so the stream visibly comes from both sides.
		var muzzle := _gatling_muzzles[live[_shots % live.size()]]
		var from := muzzle.global_position
		var lead := tank.hit_center() + tank.velocity * (from.distance_to(tank.hit_center()) / GUN_SPEED) * 0.7
		var wild := 1.0 if _live("rotor_l") and _live("rotor_r") else 2.0
		# 40 mm high-explosive rounds: each one hits hard and bursts where it lands.
		var shot := fire_along("orb", muzzle, GUN_SPEED, 9.0, Palette.HOT, lead - from, 3.0, GUN_SPREAD * wild, Muzzle.AUTO)
		shot.hit.caliber = 40
		shot.blast_radius = 2.2
		shot.blast_damage = 5.0
		# Every round draws a bright tracer streak down the bore, so the stream reads from across the arena.
		world.fx.beam(from, from + shot.velocity.normalized() * GATLING_TRACER, Palette.HOT, 0.22, 0.09)
		world.fx.spawn(Fx.Kind.FLAME, from, Vector3.ZERO, 0.05, 0.4, Palette.CORAL)
		Sfx.play("enemy_gun", from, 6.0, 0.7)
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
			if part.hp > 0.0:
				# The racks train onto their first targets while they warn.
				_rack_aim[side] = _rocket_target(tank, 0 if side == "pod_l" else 1)
				if fmod(_attack_time, 0.16) < 0.08:
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
		# The rocket leaves the next cell of the rack, along the rack, and the rack turns on to the next target.
		var muzzle: Node3D = _rack_muzzles[side]
		var cell: Vector2 = RACK_CELLS[_shots % RACK_CELLS.size()]
		muzzle.position = Vector3(cell.x, cell.y, -2.9)
		var from := muzzle.global_position
		var target: Vector3 = _rack_aim.get(side, _rocket_target(tank, _shots))
		_rack_aim[side] = _rocket_target(tank, _shots + 2)
		var rocket := fire_along("rocket", muzzle, ROCKET_SPEED, 0.0, Palette.HOT, target - from, 4.0, 0.01)
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


## Where rocket number `shot` of a volley is meant to come down: around the tank's path, or in a
## widening spiral in the infected phase.
func _rocket_target(tank: Tank, shot: int) -> Vector3:
	var spread := 7.0 if phase != Phase.INFECTED else 11.0
	var target := tank.global_position + tank.velocity * 0.8 + Vector3(randf_range(-spread, spread), 0, randf_range(-spread, spread))
	if phase == Phase.INFECTED:
		var angle := shot * 0.7
		target = tank.global_position + Vector3(cos(angle), 0, sin(angle)) * (4.0 + shot * 0.4)
	target.y = Course.height_at(target)
	return target


## Nose cannon: three shells that arrive almost the instant they are fired, so each is warned
## first: the barrel glows hotter, a warning tone sounds and a sight line settles on where the
## shell will land, then it fires. The barrel follows the line and, once it locks, stays put: the
## shell leaves along that bore.
func _cannon(delta: float, tank: Tank) -> void:
	var world := World.current
	var muzzle := _nose_muzzle.global_position
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
			# Locked: the line goes solid and stops following, and so does the barrel. This is the moment to dash.
			if _cannon_hold == Vector3.ZERO:
				_cannon_hold = -_nose_muzzle.global_basis.z.normalized()
				Sfx.play("warn", muzzle, 4.0, 1.6)
			world.fx.beam(muzzle, muzzle - _nose_muzzle.global_basis.z.normalized() * muzzle.distance_to(_cannon_aim), Palette.HOT, 0.2, 0.03)
		world.fx.spawn(Fx.Kind.FLAME, muzzle, Vector3.ZERO, 0.06, 0.3 + aiming * 1.2, Palette.HOT)
		return
	_shots += 1
	_cannon_hold = Vector3.ZERO
	var shell := fire_along("shell", _nose_muzzle, CANNON_SPEED, 0.0)
	shell.hit = Hit.make(Hit.Kind.SHELL, 10.0, muzzle)
	shell.hit.source = self
	shell.blast_radius = 4.5
	shell.blast_damage = 30.0
	shell.interceptable = true
	shell.intercept_hp = 10.0 # Ten times what the laser could burn through before.
	_velocity -= shell.velocity.normalized() * 3.0
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
	var muzzle := _chin_muzzles[index]
	var from := muzzle.global_position
	# Out of the tube along the drum, then it steers: the tubes splay a little so the three fan out.
	var missile := fire_along("atgm", muzzle, ATGM_SPEED, 0.0, Palette.HOT, Vector3.ZERO, 3.0, 0.06)
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
