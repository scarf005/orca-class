class_name Scenery
extends Node3D
## Lays out the stage's props and decor from a seeded plan, and streams them in and out around
## the rail so only the nearby stretch exists as nodes.

const AHEAD := 330.0
const BEHIND := 45.0

## kind -> [footprint, height, hp, crushable, burnable, score, explosive, rubble]
const PROPS := {
	"house": [4.2, 5.0, 75.0, false, false, 50, false, true],
	"wall": [1.6, 1.7, 10.0, true, false, 5, false, false],
	"jars": [1.6, 1.0, 5.0, true, false, 10, false, false],
	"greenhouse": [3.2, 2.8, 20.0, true, true, 30, false, false],
	"pole": [0.5, 10.0, 12.5, true, false, 10, false, false],
	"persimmon": [1.1, 4.5, 15.0, true, true, 10, false, false],
	"zelkova_trunk": [1.3, 5.0, 130.0, false, true, 60, false, false],
	"zelkova_canopy": [5.0, 7.0, 75.0, false, true, 60, false, false],
	"pavilion": [3.0, 5.0, 110.0, false, false, 80, false, true],
	"bus_stop": [1.8, 3.0, 15.0, true, false, 20, false, false],
	"cultivator": [1.8, 1.6, 15.0, true, false, 30, true, false],
	"bale": [1.0, 1.6, 6.0, true, true, 10, false, false],
	"church_nave": [4.8, 9.0, 190.0, false, false, 150, false, true],
	"church_tower": [2.2, 13.0, 160.0, false, false, 150, false, true],
	"church_spire": [2.4, 8.0, 60.0, false, false, 200, false, false],
	"school_wing": [5.5, 8.5, 210.0, false, false, 120, false, true],
	"school_center": [5.0, 10.5, 240.0, false, false, 200, false, true],
	"hall": [6.0, 5.0, 210.0, false, false, 150, false, true],
	"car": [2.1, 1.8, 35.0, false, false, 40, true, false],
	"truck": [3.2, 3.5, 80.0, false, false, 80, true, false],
	"mushroom": [0.9, 3.0, 7.5, true, true, 20, false, false],
	"spore_tower": [1.7, 8.0, 60.0, false, true, 150, false, false],
	"reeds": [1.3, 2.4, 4.0, true, true, 5, false, false],
	"crate": [1.1, 1.2, 9.0, true, false, 50, false, false],
	"rock": [2.2, 1.6, 200.0, false, false, 60, false, false],
	"gate": [0.8, 3.3, 100.0, false, false, 20, false, false],
	"infested_house": [4.2, 5.0, 75.0, false, true, 70, false, true],
	"infested_car": [2.1, 1.8, 35.0, false, true, 50, true, false],
	"flesh_mound": [2.4, 4.0, 45.0, false, true, 80, false, false],
	"cordyceps": [1.2, 5.0, 15.0, true, true, 30, false, false],
	"husk_cow": [1.4, 2.2, 12.5, true, true, 40, false, false],
	"egg_sacs": [1.4, 2.0, 7.5, true, true, 40, false, false],
	"barrel": [0.5, 1.0, 5.0, false, false, 20, true, false],
	"gas_pump": [0.7, 1.8, 10.0, false, false, 60, true, false],
	"gas_station": [4.5, 6.0, 100.0, false, false, 150, false, true],
	"fungal_spire": [4.0, 14.0, 350.0, false, true, 400, false, false],
	"plane_tree": [0.9, 9.0, 22.5, true, true, 10, false, false],
}

## Cars: run over, they are squashed, knocked flying or burst apart instead of blowing up.
const VEHICLES := ["car", "truck", "infested_car", "cultivator"]

## Tall thin props that snap and fall over rather than vanish.
const FALLING := ["pole", "plane_tree", "persimmon", "cordyceps"]

## Plain props that spawn overgrown more often the deeper the stage goes.
const INFESTED := {"house": "infested_house", "car": "infested_car"}
const FUNGAL := ["fungal_spire", "infested_house", "infested_car", "flesh_mound", "cordyceps", "husk_cow", "egg_sacs", "mushroom", "spore_tower"]

## Multi-piece landmarks: [kind, along the building's local x, local z, height lift, index it rests on (-1 = ground)].
const COMPOUNDS := {
	"church": [["church_nave", 0.0, -3.7, 0.0, -1], ["church_nave", 0.0, 3.7, 0.0, -1], ["church_tower", 0.0, 9.0, 0.0, -1], ["church_spire", 0.0, 9.0, 13.2, 2]],
	"zelkova": [["zelkova_trunk", 0.0, 0.0, 0.0, -1], ["zelkova_canopy", 0.0, 0.0, 5.0, 0]],
	"school": [["school_wing", -21.0, 0.0, 0.0, -1], ["school_wing", -10.5, 0.0, 0.0, -1], ["school_center", 0.0, 0.3, 0.0, -1], ["school_wing", 10.5, 0.0, 0.0, -1], ["school_wing", 21.0, 0.0, 0.0, -1]],
}

class Spec:
	var kind := ""
	var variant := 0
	var d := 0.0
	var u := 0.0
	var yaw := 0.0
	var pickup := "" ## Loot lying on the ground here instead of a prop.
	var decor := false
	var mesh: Mesh
	var node: Node3D
	var lift := 0.0 ## Height above the ground (pieces resting on other pieces).
	var group := -1 ## Compound this piece belongs to.
	var rests_on := -1 ## Index within the group of the piece holding this one up.
	var index := 0

var specs: Array[Spec] = []
var _rng := RandomNumberGenerator.new()
var _next := 0
var _live: Array[Spec] = []
var _wires_of := {} ## Pole spec -> the wire decor specs strung from it.
var _groups: Array[Dictionary] = [] ## Compound id -> {piece index: Prop}, filled as pieces stream in.


func build() -> void:
	_rng.seed = 20260928
	_farm()
	_village()
	_school()
	_reservoir()
	_overpass()
	_arena()
	_wires()
	_spires()
	_boom()
	specs.sort_custom(func(a: Spec, b: Spec) -> bool: return a.d < b.d)
	_prewarm()


## Builds every prop mesh the plan uses up front, so streaming never stalls on a first build.
func _prewarm() -> void:
	for spec in specs:
		if not spec.decor and spec.pickup.is_empty():
			PropKit.mesh(spec.kind, spec.variant)
			if PROPS[spec.kind][7]:
				PropKit.mesh("rubble", spec.variant)


func add(kind: String, d: float, u: float, yaw := INF, variant := -1) -> Spec:
	if INFESTED.has(kind) and _rng.randf() < clampf((d - 300.0) / 2400.0, 0.1, 0.75):
		kind = INFESTED[kind]
	var spec := Spec.new()
	spec.kind = kind
	spec.d = d
	spec.u = u
	spec.yaw = yaw if yaw != INF else (-PI * 0.5 if u > 0.0 else PI * 0.5) + _rng.randf_range(-0.15, 0.15)
	spec.variant = variant if variant >= 0 else _rng.randi_range(0, 11)
	specs.append(spec)
	return spec


## Places a power-up on the ground, floating like any other loot.
func add_pickup(id: String, d: float, u: float) -> Spec:
	var spec := Spec.new()
	spec.pickup = id
	spec.d = d
	spec.u = u
	specs.append(spec)
	return spec


## Places a multi-piece landmark. Pieces are separate props; upper pieces rest on lower ones.
func add_compound(name: String, d: float, u: float, yaw: float) -> void:
	var group := _groups.size()
	_groups.append({})
	var pieces: Array = COMPOUNDS[name]
	for i in pieces.size():
		var piece: Array = pieces[i]
		var offset := Vector3(piece[1], 0.0, piece[2]).rotated(Vector3.UP, yaw)
		var spec := add(piece[0], d - offset.z, u + offset.x, yaw, i)
		spec.lift = piece[3]
		spec.group = group
		spec.rests_on = piece[4]
		spec.index = i


func add_decor(mesh: Mesh, d: float, u: float, yaw := 0.0, y := INF) -> Spec:
	var spec := Spec.new()
	spec.decor = true
	spec.mesh = mesh
	spec.d = d
	spec.u = u
	spec.yaw = yaw
	spec.variant = 0
	if y != INF:
		spec.set_meta("y", y)
	specs.append(spec)
	return spec


func _clear(d: float, u: float, r: float) -> bool:
	for spec in specs:
		if absf(spec.d - d) < r + 4.0 and absf(spec.u - u) < r + 4.0:
			return false
	return true


func _scatter(kind: String, d0: float, d1: float, count: int, u_min: float, u_max: float, both_sides := true) -> void:
	for i in count:
		var d := _rng.randf_range(d0, d1)
		var u := _rng.randf_range(u_min, u_max) * (1.0 if not both_sides or _rng.randf() < 0.5 else -1.0)
		if _clear(d, u, PROPS[kind][0] if PROPS.has(kind) else 2.0):
			add(kind, d, u, _rng.randf() * TAU)


## Overgrowth thickens with distance: lone mushrooms early, heaving flesh and fruiting stalks later.
func _fungus(d0: float, d1: float, density: float) -> void:
	var count := int((d1 - d0) / 10.0 * density * 2.5 * (1.0 + (d0 + d1) / 6800.0))
	for i in count:
		var d := _rng.randf_range(d0, d1)
		# Most growth crowds the road edges where the camera sees it.
		var reach := 22.0 if _rng.randf() < 0.7 else 42.0
		var u := _rng.randf_range(6.5, reach) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var roll := _rng.randf()
		var yaw := _rng.randf() * TAU
		if roll < 0.2:
			add("mushroom", d, u, yaw)
		elif roll < 0.4:
			add_decor(PropKit.mesh("veins", _rng.randi_range(0, 5)), d, u, yaw)
		elif roll < 0.6:
			add("cordyceps", d, u, yaw)
		elif roll < 0.75:
			if absf(u) > 10.0:
				add("flesh_mound", d, u, yaw)
		elif roll < 0.88:
			add("egg_sacs", d, u, yaw)
		elif absf(u) > 16.0:
			add("spore_tower", d, u, yaw)


func _farm() -> void:
	_scatter("bale", 20.0, 540.0, 38, 14.0, 60.0)
	_scatter("persimmon", 40.0, 540.0, 10, 20.0, 45.0)
	for d in [120.0, 260.0, 420.0]:
		add("house", d + _rng.randf_range(-10, 10), 48.0 * (1.0 if int(d) % 2 else -1.0))
	add("cultivator", 180.0, 6.0, 0.4)
	for cd in [110.0, 230.0, 340.0, 440.0, 520.0]:
		add("husk_cow", cd, _rng.randf_range(12.0, 30.0) * (1.0 if int(cd) % 2 else -1.0), _rng.randf() * TAU)
	add("bus_stop", 300.0, -8.0)
	add("car", 360.0, 3.0, 0.3, 2)
	_scatter("car", 60.0, 560.0, 10, 1.0, 14.0)
	add_pickup("coax", 150.0, -4.0)
	add_pickup("canister", 470.0, 5.0)
	_fungus(200.0, 560.0, 0.5)


func _village() -> void:
	add_compound("zelkova", 590.0, -17.0, 0.0)
	add("pavilion", 590.0, -8.5, 0.1)
	add("hall", 900.0, -16.0)
	add_compound("church", 1160.0, 26.0, -PI * 0.5)
	var d := 610.0
	while d < 1440.0:
		for side in [-1.0, 1.0]:
			if _rng.randf() < 0.75:
				var u: float = side * _rng.randf_range(13.0, 24.0)
				if _clear(d, u, 5.0):
					add("house", d, u)
					add("wall", d + 5.5, side * 8.5, PI * 0.5 + _rng.randf_range(-0.05, 0.05))
					if _rng.randf() < 0.5:
						add("jars", d - 4.0, u - side * 5.5)
			if _rng.randf() < 0.3:
				add("house", d + 10.0, side * _rng.randf_range(28.0, 40.0))
		d += _rng.randf_range(18.0, 26.0)
	# A few houses stand in the road: blast through or go around.
	for od in [760.0, 1030.0, 1290.0]:
		add("house", od, _rng.randf_range(-8.0, 8.0), _rng.randf() * TAU)
	for gd in [700.0, 1000.0]:
		for k in 3:
			add("greenhouse", gd + k * 20.0, 20.0 + k * 1.5, 0.0)
			add("greenhouse", gd + 10.0 + k * 20.0, -22.0 - k * 1.5, 0.0)
	_scatter("car", 620.0, 1430.0, 22, 2.0, 16.0)
	_scatter("persimmon", 620.0, 1430.0, 14, 9.0, 30.0)
	add_pickup("dragon", 880.0, 7.0)
	add_pickup("era", 640.0, -5.0)
	add_pickup("tail", 1100.0, 5.0)
	add_pickup("coax", 1210.0, -6.0)
	add_pickup("repair", 1400.0, 3.0)
	_fungus(600.0, 1450.0, 0.9)


func _school() -> void:
	add("gate", 1560.0, -8.5, 0.0)
	add("gate", 1560.0, 8.5, 0.0)
	add_compound("school", 1760.0, -46.0, PI * 0.5)
	add_decor(PropKit.mesh("flagpole", 0), 1640.0, -30.0, 0.0)
	for i in 8:
		add("plane_tree", 1570.0 + i * 22.0, 60.0 * (1.0 if i % 2 else -1.0) + _rng.randf_range(-4, 4))
	add_pickup("heat", 1520.0, 0.0)
	_fungus(1560.0, 1760.0, 1.4)


func _reservoir() -> void:
	var d := 1780.0
	while d < 2640.0:
		add("reeds", d, _rng.randf_range(-24.0, -17.0))
		if _rng.randf() < 0.5:
			add("reeds", d + 4.0, _rng.randf_range(-20.0, -15.0))
		d += _rng.randf_range(6.0, 12.0)
	for pd in [1900.0, 2150.0, 2400.0]:
		add_decor(PropKit.mesh("pier", int(pd)), pd, -60.0 - _rng.randf_range(0, 20), _rng.randf() * TAU, Course.WATER_LEVEL)
	_scatter("house", 1780.0, 2640.0, 6, 22.0, 40.0, false)
	_scatter("car", 1800.0, 2640.0, 18, 0.0, 12.0)
	add_pickup("airburst", 2000.0, 6.0)
	add_pickup("era", 2150.0, -4.0)
	add_pickup("tail", 2450.0, 3.0)
	add_pickup("coax", 2300.0, -5.0)
	add_pickup("repair", 2560.0, 4.0)
	_fungus(1760.0, 2660.0, 1.6)


func _overpass() -> void:
	add_decor(_bridge_mesh(), Course.UNDERPASS_D, 0.0, 0.0, 0.0)
	var d := Course.RAMP_UP.y
	while d < Course.RAMP_DOWN.x:
		add_decor(_rail_mesh(), d, -14.6, 0.0)
		add_decor(_rail_mesh(), d, 14.6, 0.0)
		d += 12.0
	add_decor(_gantry_mesh(), 3080.0, 0.0, 0.0)
	add_decor(_gantry_mesh(), 3260.0, 0.0, 0.0)
	for td in [3040.0, 3140.0, 3220.0, 3300.0]:
		add("truck" if _rng.randf() < 0.5 else "car", td, _rng.randf_range(-9.0, 9.0), _rng.randf_range(-0.4, 0.4))
	_scatter("car", 2680.0, 2890.0, 10, 0.0, 12.0)
	add_pickup("apfsds", 2700.0, 0.0)
	add_pickup("era", 2950.0, -3.0)
	add_pickup("tail", 3050.0, 4.0)
	add_pickup("heat", 3180.0, 4.0)
	_fungus(2660.0, 2900.0, 1.8)


func _arena() -> void:
	add_decor(_dam_mesh(), Course.DAM_D, 0.0, 0.0, 0.0)
	for i in 10:
		var angle := TAU * i / 10.0 + 0.3
		var r := _rng.randf_range(35.0, 70.0)
		add("rock", Course.ARENA_CENTER_D + sin(angle) * r, cos(angle) * r)
	for i in 8:
		var angle := TAU * i / 8.0
		add("spore_tower", Course.ARENA_CENTER_D + sin(angle) * 80.0, cos(angle) * 80.0)
	_scatter("car", 3440.0, 3600.0, 4, 10.0, 60.0)
	_fungus(3420.0, 3620.0, 1.2)


## Explosive barrels in clusters along the road, and a gas station whose pumps go up like bombs.
func _boom() -> void:
	var d := 180.0
	while d < Course.SECTION_STARTS[Course.Section.ARENA]:
		if Course.section_at(d) != Course.Section.SCHOOL:
			var u := _rng.randf_range(4.0, 11.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
			for i in _rng.randi_range(2, 3):
				add("barrel", d + _rng.randf_range(-2.0, 2.0), u + _rng.randf_range(-2.0, 2.0), _rng.randf() * TAU)
		d += _rng.randf_range(220.0, 320.0)
	for station in [[980.0, -14.0], [2880.0, 10.0]]:
		add("gas_station", station[0], station[1], PI * 0.5)
		for k in 3:
			add("gas_pump", station[0] - 2.0 + k * 2.0, station[1], PI * 0.5, k)
		for k in 4:
			add("barrel", station[0] + 5.0 + k * 0.8, station[1] + signf(station[1]) * 3.0, 0.0, k)


## Giant fungal spires rising from the fields, more often as the stage goes on.
func _spires() -> void:
	var d := 300.0
	var side := 1.0
	while d < Course.DAM_D - 40.0:
		var u := side * _rng.randf_range(26.0, 48.0)
		if Course.section_at(d) == Course.Section.RESERVOIR and side < 0.0:
			u = side * _rng.randf_range(18.0, 22.0)
		add("fungal_spire", d, u, _rng.randf() * TAU, _rng.randi_range(0, 5))
		d += lerpf(170.0, 80.0, d / Course.DAM_D) + _rng.randf_range(-20.0, 20.0)
		side = -side


## Utility poles along the road with sagging wires between them.
func _wires() -> void:
	for side in [-1.0, 1.0]:
		var d := 10.0 if side < 0.0 else 30.0
		var previous := Vector3.INF
		var previous_pole: Spec = null
		while d < Course.SECTION_STARTS[Course.Section.OVERPASS]:
			var u: float = side * 9.5
			if Course.section_at(d) == Course.Section.RESERVOIR and side < 0.0:
				previous = Vector3.INF
				d += 40.0
				continue
			if Course.section_at(d) == Course.Section.SCHOOL:
				previous = Vector3.INF
				d += 40.0
				continue
			var pole := add("pole", d, u, 0.0)
			var top := Course.ground_at(d, u) + Vector3.UP * 9.2
			if previous != Vector3.INF:
				var wire := add_decor(_wire_mesh(previous, top, Course.yaw_at(d)), d, u, 0.0, 0.0)
				wire.set_meta("ends", [previous, top])
				for end: Spec in [previous_pole, pole]:
					if not _wires_of.has(end):
						_wires_of[end] = []
					_wires_of[end].append(wire)
			previous = top
			previous_pole = pole
			d += 40.0


func _wire_mesh(a: Vector3, b: Vector3, yaw: float) -> Mesh:
	# Wire vertices are stored relative to `b`, which is where the decor is placed turned by `yaw`.
	var builder := LowPoly.new()
	for offset in [-1.0, 0.0, 1.0]:
		var points: Array[Vector3] = []
		for i in 7:
			var t := i / 6.0
			var p := (a.lerp(b, t) - Vector3(b.x, 0.0, b.z)).rotated(Vector3.UP, -yaw)
			p.x += offset
			p.y += -sin(t * PI) * 1.4
			points.append(p)
		for i in 6:
			var dir := points[i + 1] - points[i]
			builder.box(Transform3D(Basis.looking_at(dir, Vector3.UP), (points[i] + points[i + 1]) * 0.5), Vector3(0.05, 0.05, dir.length()), Palette.INK)
	return builder.mesh()


func _bridge_mesh() -> Mesh:
	var b := LowPoly.new()
	var h := 9.0
	b.box(Transform3D(Basis(), Vector3(0, h, 0)), Vector3(220.0, 1.4, 14.0), Palette.CONCRETE)
	b.box(Transform3D(Basis(), Vector3(0, h + 1.1, 6.8)), Vector3(220.0, 0.8, 0.4), Palette.MIST)
	b.box(Transform3D(Basis(), Vector3(0, h + 1.1, -6.8)), Vector3(220.0, 0.8, 0.4), Palette.MIST)
	b.box(Transform3D(Basis(), Vector3(0, h - 0.9, 0)), Vector3(220.0, 0.4, 10.0), Palette.STONE)
	for x in [-60.0, -38.0, -18.0, 18.0, 38.0, 60.0]:
		b.box(Transform3D(Basis(), Vector3(x, h * 0.5 - 2.0, 0)), Vector3(2.0, h + 4.0, 3.0), Palette.CONCRETE)
	# Fungus drips from the deck.
	for i in 8:
		b.blob(Transform3D(Basis(), Vector3(-40.0 + i * 11.0, h - 1.2, 3.0 - (i % 3) * 3.0)), 1.0 + (i % 2) * 0.6, Palette.FUNGUS if i % 2 else Palette.LILAC, 0, 0.4, i)
	b.box(Transform3D(Basis(), Vector3(0, h + 0.2, -7.05)), Vector3(8.0, 1.2, 0.1), Palette.PINE)
	return b.mesh()


func _rail_mesh() -> Mesh:
	if PropKit._cache.has("guardrail"):
		return PropKit._cache["guardrail"]
	var b := LowPoly.new()
	for z in [-6.0, 0.0]:
		b.box(Transform3D(Basis(), Vector3(0, 0.45, z)), Vector3(0.15, 0.9, 0.15), Palette.STONE)
	b.box(Transform3D(Basis(), Vector3(0, 0.75, -3.0)), Vector3(0.08, 0.3, 12.0), Palette.MIST)
	PropKit._cache["guardrail"] = b.mesh()
	return PropKit._cache["guardrail"]


func _gantry_mesh() -> Mesh:
	var b := LowPoly.new()
	for x in [-15.5, 15.5]:
		b.box(Transform3D(Basis(), Vector3(x, 4.0, 0)), Vector3(0.5, 8.0, 0.5), Palette.STONE)
	b.box(Transform3D(Basis(), Vector3(0, 8.0, 0)), Vector3(31.5, 0.5, 0.5), Palette.STONE)
	b.box(Transform3D(Basis(), Vector3(-5.0, 7.0, 0.3)), Vector3(8.0, 2.2, 0.1), Palette.PINE)
	b.box(Transform3D(Basis(), Vector3(5.0, 7.0, 0.3)), Vector3(8.0, 2.2, 0.1), Palette.PERIWINKLE)
	for x in [-7.5, -3.0, 2.5, 7.0]:
		b.box(Transform3D(Basis(), Vector3(x, 7.2, 0.36)), Vector3(2.0, 0.3, 0.02), Palette.WHITE)
	return b.mesh()


func _dam_mesh() -> Mesh:
	var b := LowPoly.new()
	var width := 260.0
	for i in 6:
		var y := i * 5.0
		b.box(Transform3D(Basis(), Vector3(0, y + 2.5, -i * 2.5)), Vector3(width, 5.0, 4.0 + i * 0.5), Palette.CONCRETE if i % 2 else Palette.MIST)
	b.box(Transform3D(Basis(), Vector3(0, 31.0, -15.0)), Vector3(width, 2.0, 8.0), Palette.STONE)
	for x in [-24.0, -8.0, 8.0, 24.0]:
		b.box(Transform3D(Basis(), Vector3(x, 34.0, -15.0)), Vector3(6.0, 6.0, 6.0), Palette.ASH)
		b.box(Transform3D(Basis(), Vector3(x, 15.0, 0.5)), Vector3(5.0, 30.0, 1.0), Palette.STONE)
	for i in 14:
		b.blob(Transform3D(Basis(), Vector3(-90.0 + i * 14.0, 3.0 + (i % 4) * 7.0, 1.0 - (i % 4) * 2.5)), 2.5 + (i % 3), [Palette.FUNGUS, Palette.LILAC, Palette.BLUSH][i % 3], 0, 0.4, i)
	return b.mesh()


## Instantiates specs entering the window (at most `budget` per call) and frees those behind.
func stream(d: float, budget := 8) -> void:
	while _next < specs.size() and specs[_next].d < d + AHEAD and budget > 0:
		var spec := specs[_next]
		_next += 1
		if spec.d < d - BEHIND:
			continue
		_instantiate(spec)
		budget -= 1
	var keep: Array[Spec] = []
	var arena := World.current.rail.mode == Rail.Mode.ARENA
	for spec in _live:
		if spec.d < d - BEHIND and not arena:
			if is_instance_valid(spec.node):
				spec.node.queue_free()
			spec.node = null
		else:
			keep.append(spec)
	_live = keep


func _instantiate(spec: Spec) -> void:
	var y: float = spec.get_meta("y") if spec.has_meta("y") else Course.height(spec.d, spec.u) + spec.lift
	var position := Course.to_world(spec.d, spec.u, y)
	var yaw := spec.yaw + Course.yaw_at(spec.d)
	if not spec.pickup.is_empty():
		spec.node = World.current.spawn_pickup(spec.pickup, position + Vector3.UP * 1.6)
	elif spec.decor:
		var decor := MeshInstance3D.new()
		decor.mesh = spec.mesh
		decor.visibility_range_end = 260.0
		add_child(decor)
		decor.global_position = position
		decor.rotation.y = yaw
		spec.node = decor
	else:
		var cfg: Array = PROPS[spec.kind]
		var prop := Prop.new()
		prop.setup(spec.kind, PropKit.mesh(spec.kind, spec.variant), cfg[0], cfg[1], cfg[2])
		prop.crushable = cfg[3]
		prop.burnable = cfg[4]
		prop.score = cfg[5]
		prop.explosive = cfg[6]
		prop.blast_size = {"barrel": 4.0, "gas_pump": 8.0}.get(spec.kind, 4.5)
		if cfg[7]:
			prop.rubble_mesh = PropKit.mesh("rubble", spec.variant)
		prop.falls = spec.kind in FALLING
		prop.vehicle = spec.kind in VEHICLES
		prop.fungal = spec.kind in FUNGAL
		prop.debris = _debris(spec.kind)
		# Position before entering the tree: props register into spatial buckets on entry.
		prop.position = position
		prop.rotation.y = yaw
		World.current.props.add_child(prop)
		spec.node = prop
		if spec.group >= 0:
			_link(spec, prop)
		if _wires_of.has(spec):
			prop.felled.connect(func(_p: Prop) -> void: _cut_wires(spec))
			prop.died.connect(func(_e: Entity) -> void: _cut_wires(spec))
	_live.append(spec)


## A pole went down: its wires snap in a shower of sparks and fall.
func _cut_wires(pole: Spec) -> void:
	for wire: Spec in _wires_of.get(pole, []):
		if wire.has_meta("cut"):
			continue
		wire.set_meta("cut", true)
		var world := World.current
		for end: Vector3 in wire.get_meta("ends"):
			world.fx.sparks(end, Vector3.UP, 26, Palette.WHITE, 14.0)
			world.fx.sparks(end, Vector3.DOWN, 14, Palette.CYAN, 10.0)
			world.fx.light_flash(end, 10.0, Palette.CYAN, 18.0)
		Sfx.play("zap", wire.get_meta("ends")[1], 4.0, 0.6)
		if not is_instance_valid(wire.node):
			continue
		var node := wire.node
		var drop := node.create_tween()
		drop.tween_property(node, "position:y", node.position.y - 8.4, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		drop.tween_callback(func() -> void:
			var ends: Array = wire.get_meta("ends")
			for i in 5:
				var p: Vector3 = (ends[0] as Vector3).lerp(ends[1], (i + 0.5) / 5.0)
				p.y = Course.height_at(p) + 0.2
				World.current.fx.sparks(p, Vector3.UP, 8, Palette.CYAN, 7.0)
			World.current.fx.dust((ends[0] as Vector3).lerp(ends[1], 0.5), 5, 3.0, Palette.OCHRE)
			Sfx.play("zap", ends[1], 0.0, 0.9))


## Connects a compound piece to whatever it rests on and whatever rests on it, whichever streamed first.
func _link(spec: Spec, prop: Prop) -> void:
	var members: Dictionary = _groups[spec.group]
	members[spec.index] = prop
	for other in specs:
		if other.group != spec.group or not is_instance_valid(other.node):
			continue
		if other.index == spec.rests_on:
			(other.node as Prop).supports.append(prop)
		elif other.rests_on == spec.index:
			prop.supports.append(other.node as Prop)


## What each kind of prop breaks into, as Fx.Debris materials.
func _debris(kind: String) -> Array:
	match kind:
		"house", "hall", "church_nave", "church_tower", "church_spire", "school_wing", "school_center":
			return [Fx.Debris.CONCRETE, Fx.Debris.ROOF, Fx.Debris.WOOD, Fx.Debris.GLASS]
		"infested_house":
			return [Fx.Debris.CONCRETE, Fx.Debris.ROOF, Fx.Debris.FLESH]
		"pavilion":
			return [Fx.Debris.WOOD, Fx.Debris.ROOF]
		"wall":
			return [Fx.Debris.CONCRETE]
		"gate":
			return [Fx.Debris.CONCRETE, Fx.Debris.METAL]
		"jars":
			return [Fx.Debris.CERAMIC]
		"greenhouse":
			return [Fx.Debris.VINYL, Fx.Debris.METAL, Fx.Debris.FOLIAGE]
		"pole":
			return [Fx.Debris.CONCRETE, Fx.Debris.METAL]
		"bus_stop":
			return [Fx.Debris.METAL, Fx.Debris.GLASS, Fx.Debris.CONCRETE]
		"cultivator", "barrel", "gas_pump":
			return [Fx.Debris.METAL, Fx.Debris.PAINT]
		"bale", "reeds":
			return [Fx.Debris.STRAW]
		"car", "truck":
			return [Fx.Debris.PAINT, Fx.Debris.METAL, Fx.Debris.GLASS]
		"infested_car":
			return [Fx.Debris.PAINT, Fx.Debris.METAL, Fx.Debris.FLESH]
		"mushroom", "spore_tower", "fungal_spire", "flesh_mound", "cordyceps", "egg_sacs", "husk_cow":
			return [Fx.Debris.FLESH, Fx.Debris.SPORE]
		"persimmon", "plane_tree", "zelkova_trunk", "zelkova_canopy":
			return [Fx.Debris.WOOD, Fx.Debris.FOLIAGE]
		"gas_station":
			return [Fx.Debris.CONCRETE, Fx.Debris.METAL, Fx.Debris.GLASS, Fx.Debris.PAINT]
		"crate":
			return [Fx.Debris.WOOD]
		"rock":
			return [Fx.Debris.ROCK]
	return [Fx.Debris.CONCRETE, Fx.Debris.WOOD]
