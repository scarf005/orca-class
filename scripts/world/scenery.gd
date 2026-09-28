class_name Scenery
extends Node3D
## Lays out the stage's props and decor from a seeded plan, and streams them in and out around
## the rail so only the nearby stretch exists as nodes.

const AHEAD := 330.0
const BEHIND := 45.0

## kind -> [footprint, height, hp, solid, crushable, burnable, score, explosive, rubble]
const PROPS := {
	"house": [4.2, 5.0, 150.0, true, false, false, 50, false, true],
	"wall": [1.6, 1.7, 20.0, false, true, false, 5, false, false],
	"jars": [1.6, 1.0, 10.0, false, true, false, 10, false, false],
	"greenhouse": [3.2, 2.8, 40.0, false, true, true, 30, false, false],
	"pole": [0.5, 10.0, 25.0, false, true, false, 10, false, false],
	"persimmon": [1.1, 4.5, 30.0, false, true, true, 10, false, false],
	"zelkova": [2.2, 12.0, 1e9, true, false, false, 0, false, false],
	"pavilion": [3.0, 5.0, 220.0, true, false, false, 80, false, true],
	"bus_stop": [1.8, 3.0, 30.0, false, true, false, 20, false, false],
	"cultivator": [1.8, 1.6, 30.0, false, true, false, 30, true, false],
	"bale": [1.0, 1.6, 12.0, false, true, true, 10, false, false],
	"church": [7.0, 20.0, 1e9, true, false, false, 0, false, false],
	"hall": [6.0, 5.0, 420.0, true, false, false, 150, false, true],
	"car": [2.1, 1.8, 70.0, true, false, false, 40, true, false],
	"truck": [3.2, 3.5, 160.0, true, false, false, 80, true, false],
	"mushroom": [0.9, 3.0, 15.0, false, true, true, 20, false, false],
	"spore_tower": [1.7, 8.0, 120.0, true, false, true, 150, false, false],
	"reeds": [1.3, 2.4, 8.0, false, true, true, 5, false, false],
	"crate": [1.1, 1.2, 18.0, false, true, false, 50, false, false],
	"rock": [2.2, 1.6, 400.0, true, false, false, 60, false, false],
	"gate": [0.8, 3.3, 200.0, true, false, false, 20, false, false],
	"infested_house": [4.2, 5.0, 150.0, true, false, true, 70, false, true],
	"infested_car": [2.1, 1.8, 70.0, true, false, true, 50, true, false],
	"flesh_mound": [2.4, 4.0, 90.0, true, false, true, 80, false, false],
	"cordyceps": [1.2, 5.0, 30.0, false, true, true, 30, false, false],
	"husk_cow": [1.4, 2.2, 25.0, false, true, true, 40, false, false],
	"egg_sacs": [1.4, 2.0, 15.0, false, true, true, 40, false, false],
	"fungal_spire": [4.0, 14.0, 700.0, true, false, true, 400, false, false],
	"plane_tree": [0.9, 9.0, 45.0, false, true, true, 10, false, false],
}

## Plain props that spawn overgrown more often the deeper the stage goes.
const INFESTED := {"house": "infested_house", "car": "infested_car"}
const FUNGAL := ["fungal_spire", "infested_house", "infested_car", "flesh_mound", "cordyceps", "husk_cow", "egg_sacs", "mushroom", "spore_tower"]

class Spec:
	var kind := ""
	var variant := 0
	var d := 0.0
	var u := 0.0
	var yaw := 0.0
	var drop := ""
	var decor := false
	var mesh: Mesh
	var node: Node3D

var specs: Array[Spec] = []
var _rng := RandomNumberGenerator.new()
var _next := 0
var _live: Array[Spec] = []


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
	specs.sort_custom(func(a: Spec, b: Spec) -> bool: return a.d < b.d)


func add(kind: String, d: float, u: float, yaw := INF, variant := -1, drop := "") -> Spec:
	if INFESTED.has(kind) and _rng.randf() < clampf((d - 300.0) / 2400.0, 0.1, 0.75):
		kind = INFESTED[kind]
	var spec := Spec.new()
	spec.kind = kind
	spec.d = d
	spec.u = u
	spec.yaw = yaw if yaw != INF else (-PI * 0.5 if u > 0.0 else PI * 0.5) + _rng.randf_range(-0.15, 0.15)
	spec.variant = variant if variant >= 0 else _rng.randi_range(0, 11)
	spec.drop = drop
	specs.append(spec)
	return spec


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
	add("crate", 150.0, -4.0, 0.2, 0, "coax")
	add("crate", 470.0, 5.0, -0.2, 1, "canister")
	_fungus(200.0, 560.0, 0.5)


func _village() -> void:
	add("zelkova", 590.0, -17.0, 0.0)
	add("pavilion", 590.0, -8.5, 0.1)
	add("hall", 900.0, -16.0)
	add("church", 1160.0, 26.0)
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
	_scatter("car", 620.0, 1430.0, 7, 2.0, 11.0)
	_scatter("persimmon", 620.0, 1430.0, 14, 9.0, 30.0)
	add("crate", 880.0, 7.0, 0.0, 0, "dragon")
	add("crate", 640.0, -5.0, 0.0, 1, "era")
	add("crate", 1100.0, 5.0, 0.0, 0, "tail")
	add("crate", 1210.0, -6.0, 0.0, 1, "coax")
	add("crate", 1400.0, 3.0, 0.0, 0, "repair")
	_fungus(600.0, 1450.0, 0.9)


func _school() -> void:
	add("gate", 1560.0, -8.5, 0.0)
	add("gate", 1560.0, 8.5, 0.0)
	add_decor(PropKit.mesh("school", 0), 1760.0, -46.0, PI * 0.5)
	add_decor(PropKit.mesh("flagpole", 0), 1640.0, -30.0, 0.0)
	for i in 8:
		add("plane_tree", 1570.0 + i * 22.0, 60.0 * (1.0 if i % 2 else -1.0) + _rng.randf_range(-4, 4))
	add("crate", 1520.0, 0.0, 0.0, 0, "heat")
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
	_scatter("car", 1800.0, 2640.0, 6, 0.0, 9.0)
	add("crate", 2000.0, 6.0, 0.0, 0, "airburst")
	add("crate", 2150.0, -4.0, 0.0, 1, "era")
	add("crate", 2450.0, 3.0, 0.0, 0, "tail")
	add("crate", 2300.0, -5.0, 0.0, 1, "coax")
	add("crate", 2560.0, 4.0, 0.0, 0, "repair")
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
	_scatter("car", 2680.0, 2890.0, 5, 0.0, 10.0)
	add("crate", 2700.0, 0.0, 0.0, 0, "apfsds")
	add("crate", 2950.0, -3.0, 0.0, 1, "era")
	add("crate", 3050.0, 4.0, 0.0, 0, "tail")
	add("crate", 3180.0, 4.0, 0.0, 1, "heat")
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
			add("pole", d, u, 0.0)
			var top := Course.ground_at(d, u) + Vector3.UP * 9.2
			if previous != Vector3.INF:
				add_decor(_wire_mesh(previous, top), d, u, 0.0, 0.0)
			previous = top
			d += 40.0


func _wire_mesh(a: Vector3, b: Vector3) -> Mesh:
	# Wire vertices are stored relative to `b`, which is where the decor is placed.
	var builder := LowPoly.new()
	for offset in [-1.0, 0.0, 1.0]:
		var points: Array[Vector3] = []
		for i in 7:
			var t := i / 6.0
			var p := a.lerp(b, t) - Vector3(b.x, 0.0, b.z)
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
	var y: float = spec.get_meta("y") if spec.has_meta("y") else Course.height(spec.d, spec.u)
	var position := Vector3(Course.center_x(spec.d) + spec.u, y, -spec.d)
	if spec.decor:
		var decor := MeshInstance3D.new()
		decor.mesh = spec.mesh
		decor.visibility_range_end = 260.0
		add_child(decor)
		decor.global_position = position
		decor.rotation.y = spec.yaw
		spec.node = decor
	else:
		var cfg: Array = PROPS[spec.kind]
		var prop := Prop.new()
		prop.setup(spec.kind, PropKit.mesh(spec.kind, spec.variant), cfg[0], cfg[1], cfg[2])
		prop.solid = cfg[3]
		prop.crushable = cfg[4]
		prop.burnable = cfg[5]
		prop.score = cfg[6]
		prop.explosive = cfg[7]
		if cfg[8]:
			prop.rubble_mesh = PropKit.mesh("rubble", spec.variant)
		prop.drop = spec.drop
		prop.fungal = spec.kind in FUNGAL
		prop.debris_colors = _debris_colors(spec.kind, spec.variant)
		# Position before entering the tree: props register into spatial buckets on entry.
		prop.position = position
		prop.rotation.y = spec.yaw
		World.current.props.add_child(prop)
		spec.node = prop
	_live.append(spec)


func _debris_colors(kind: String, variant: int) -> Array:
	match kind:
		"house", "hall", "infested_house":
			return [PropKit.WALL_COLORS[variant % PropKit.WALL_COLORS.size()], PropKit.ROOF_COLORS[variant % PropKit.ROOF_COLORS.size()], Palette.STONE]
		"greenhouse":
			return [Palette.WHITE, Palette.MIST, Palette.FUNGUS]
		"mushroom", "spore_tower", "fungal_spire", "flesh_mound", "cordyceps", "egg_sacs", "husk_cow":
			return [Palette.FUNGUS, Palette.LILAC, Palette.CREAM]
		"bale":
			return [Palette.WHITE, Palette.STRAW]
		"car", "truck", "infested_car":
			return [PropKit.CAR_COLORS[variant % PropKit.CAR_COLORS.size()], Palette.INK, Palette.DUSK]
		"persimmon", "plane_tree", "reeds":
			return [Palette.PINE, Palette.WOOD, Palette.PEACH]
		"crate":
			return [Palette.PINE, Palette.OCHRE, Palette.BUTTER]
	return [Palette.CONCRETE, Palette.STONE, Palette.WOOD]
