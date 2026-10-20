class_name Scenery
extends Node3D
## Lays out the stage's props and decor from a seeded plan, and streams them in and out around
## the rail so only the nearby stretch exists as nodes.

const BACKDROP_CHUNK := 40.0
const BACKDROP_RANGE := 330.0 ## Visibility range of the skyline; the fog hides what lies beyond.
const AHEAD := 330.0
const BEHIND := 45.0
const STREAM_BUDGET_USEC := 1000

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
	"veins": [1.5, 0.5, 4.0, true, true, 5, false, false],
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
	"overpass_pier": [1.6, 15.0, 200.0, false, false, 300, false, false],
	"overpass_deck": [11.0, 2.6, 150.0, false, false, 200, false, false],
	"city_building": [15.0, 36.0, 200.0, false, false, 0, false, false],
	"jungle_building": [15.0, 36.0, 200.0, false, false, 0, false, false],
	"jungle_tree": [1.4, 13.0, 90.0, false, true, 40, false, false],
	"palm": [0.7, 8.0, 25.0, true, true, 15, false, false],
	"fern": [1.3, 1.2, 4.0, true, true, 5, false, false],
	"city_shop": [4.5, 7.5, 100.0, true, false, 70, false, true],
	"city_terminal": [14.0, 12.0, 180.0, false, false, 0, false, false],
	"city_department": [13.0, 28.0, 200.0, false, false, 0, false, false],
	"city_clock": [7.0, 30.0, 200.0, false, false, 0, false, false],
	"city_ruin": [15.0, 36.0, 200.0, false, false, 0, false, false],
	"city_leaning": [15.0, 36.0, 200.0, false, false, 0, false, false],
	"city_toppled": [12.0, 4.0, 200.0, false, false, 0, false, false],
	"city_sag_span": [12.0, 2.6, 200.0, false, false, 0, false, false],
	"kiosk": [1.6, 2.8, 20.0, true, false, 15, false, false],
	"bus_shelter": [2.4, 3.6, 20.0, true, false, 15, false, false],
	"barricade": [3.0, 1.0, 15.0, true, false, 10, false, false],
	"bus_wreck": [2.0, 2.6, 35.0, false, false, 30, true, false],
	"city_pier": [3.0, 24.0, 200.0, false, false, 0, false, false],
	"city_deck": [12.0, 1.8, 200.0, false, false, 0, false, false],
	"container": [7.0, 2.8, 200.0, false, false, 0, false, false],
	"ship": [8.0, 8.0, 200.0, false, false, 0, false, false],
	"streetlamp": [0.5, 8.5, 12.5, true, false, 10, false, false],
	"traffic_light": [0.5, 6.2, 12.5, true, false, 10, false, false],
	"road_sign": [0.5, 4.6, 10.0, true, false, 5, false, false],
	"raft": [2.5, 1.0, 6.0, true, true, 10, false, false],
	"city_rubble": [2.5, 2.2, 10.0, true, false, 5, false, false],
	"subway_entrance": [4.2, 2.85, 20.0, true, false, 15, false, false],
	"tunnel_roof": [12.0, 2.0, 200.0, false, false, 0, false, false],
	"tunnel_wall": [1.0, 10.5, 200.0, false, false, 0, false, false],
}

## The highway crossing overhead: piers standing in the valley (lateral offsets) and deck spans
## [center, length, pier it rests on]. Knock out a pier and the spans on it come down.
const OVERPASS_PIERS: Array[float] = [-62.0, -40.0, -18.0, 18.0, 40.0, 62.0]
const OVERPASS_SPANS := [[-73.0, 22, -62.0], [-51.0, 22, -62.0], [-29.0, 22, -40.0], [-9.0, 18, -18.0], [9.0, 18, 18.0], [29.0, 22, 40.0], [51.0, 22, 62.0], [73.0, 22, 62.0]]
const OVERPASS_PIER_Y := -4.0
const OVERPASS_DECK_Y := 7.9

## Cars: run over, they are squashed, knocked flying or burst apart instead of blowing up.
const VEHICLES := ["car", "truck", "infested_car", "cultivator"]

## Tall thin props that snap and fall over rather than vanish.
const FALLING := ["pole", "plane_tree", "persimmon", "cordyceps", "jungle_tree", "palm", "streetlamp", "traffic_light", "road_sign"]

## Solid buildings and structures: the tank breaks them but is slowed hard (Rail.jolt).
const HARD := ["house", "infested_house", "hall", "church_nave", "church_tower", "church_spire", "school_wing", "school_center", "gas_station", "overpass_pier", "overpass_deck", "gate", "rock", "fungal_spire", "zelkova_trunk", "city_building", "city_ruin", "city_shop", "city_terminal", "city_department", "city_clock", "city_leaning", "city_toppled", "city_pier", "city_deck", "city_sag_span", "container", "ship", "tunnel_roof", "tunnel_wall", "jungle_building"]

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
	var tilt := Vector3.ZERO
	var pickup := "" ## Loot lying on the ground here instead of a prop.
	var decor := false
	var mesh: Mesh
	var node: Node3D
	var lift := 0.0 ## Height above the ground (pieces resting on other pieces).
	var group := -1 ## Compound this piece belongs to.
	var rests_on := -1 ## Index within the group of the piece holding this one up.
	var index := 0
	var seq := 0 ## Position in the plan before sorting by distance.
	var size := Vector3.ZERO

var specs: Array[Spec] = []
var _rng := RandomNumberGenerator.new()
var _next := 0
var _live: Array[Spec] = []
var _wires_of := {} ## Pole spec -> the wire decor specs strung from it.
var _blinking: Array[Spec] = [] ## Decor that flashes on and off, like a ramp's IN sign.
var _swirling: Array[Spec] = [] ## Decor that turns slowly about its own vertical axis, like quicksand.
var _groups: Array[Dictionary] = [] ## Compound id -> {piece index: Prop}, filled as pieces stream in.


func build() -> void:
	Course.reset_structures()
	_rng.seed = 20260928
	if Course.stage.number == 1:
		_farm()
		_village()
		_school()
		_reservoir()
		_overpass()
		_arena()
		_wires()
		_spires()
		_boom()
	elif Course.stage.number == 2:
		_city()
	elif Course.stage.number == 4:
		_jungle()
	else:
		_buried_city()
	process_priority = 90 # Resolve solid scenery after driving, before the chase camera.
	for i in specs.size():
		specs[i].seq = i
	specs.sort_custom(func(a: Spec, b: Spec) -> bool: return a.d < b.d or (a.d == b.d and a.seq < b.seq)) # Stable: stacked pieces share a d.
	_prewarm()


## Builds every prop mesh the plan uses up front, so streaming never stalls on a first build.
func _prewarm() -> void:
	for spec in specs:
		if not spec.decor and spec.pickup.is_empty():
			if spec.size != Vector3.ZERO:
				PropKit.structure_mesh(spec.kind, spec.size, spec.variant)
			else:
				PropKit.mesh(spec.kind, spec.variant)
			if PROPS[spec.kind][7]:
				PropKit.mesh("rubble", spec.variant)


func add(kind: String, d: float, u: float, yaw := INF, variant := -1) -> Spec:
	if Course.stage.number == 1 and INFESTED.has(kind) and _rng.randf() < clampf((d - 300.0) / 2400.0, 0.1, 0.75):
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


## The towers and the skyline behind them: what every city stage stands on.
func _city_shell() -> StageDef:
	var container_groups := {}
	for structure in Course.stage.structures:
		var spec := add(structure.kind, structure.d, structure.u, structure.yaw, structure.variant)
		spec.size = structure.size
		spec.tilt = structure.get("tilt", Vector3.ZERO)
		spec.set_meta("y", structure.y)
		if structure.kind == "container":
			var key := Vector2(structure.d, signf(structure.u))
			if container_groups.has(key):
				spec.group = container_groups[key]
				spec.index = 1
				spec.rests_on = 0
			else:
				spec.group = _groups.size()
				container_groups[key] = spec.group
				_groups.append({})
	_backdrop_chunks(Course.stage)
	return Course.stage


func _city() -> void:
	var stage := _city_shell() as Stage2
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261004
	for d in range(100, int(Stage2.LENGTH) - 300, 36):
		if stage.in_arena(float(d), 40.0):
			continue
		var side := -1.0 if (d / 36) % 2 == 0 else 1.0
		add("streetlamp", float(d), side * 11.5, 0.0 if side < 0.0 else PI, 0).set_meta("y", stage.height(float(d), side * 11.5))
	for d in range(180, int(Stage2.LENGTH) - 300, 140):
		if stage.in_arena(float(d), 60.0):
			continue
		add("traffic_light", float(d), 11.0, PI, 0).set_meta("y", stage.height(float(d), 11.0))
		add("road_sign", float(d) + 55.0, -11.5, 0.0, d % 4).set_meta("y", stage.height(float(d) + 55.0, -11.5))
	for d in range(150, int(Stage2.LENGTH) - 300, 95):
		if stage.in_arena(float(d), 40.0):
			continue
		var u := rng.randf_range(-12.0, 12.0)
		var variant := rng.randi_range(0, 5)
		add("raft", float(d), u, rng.randf() * TAU, variant).set_meta("y", _afloat(stage, float(d), u))
	for d in range(220, int(Stage2.LENGTH) - 300, 210):
		if stage.in_arena(float(d), 50.0):
			continue
		var u := rng.randf_range(-7.0, 7.0)
		add("bus_wreck", float(d), u, rng.randf_range(-0.4, 0.4), rng.randi_range(0, 5))
	for d in range(330, int(Stage2.LENGTH) - 300, 260):
		if stage.in_arena(float(d), 50.0):
			continue
		add("barricade", float(d), rng.randf_range(-6.0, 6.0), rng.randf_range(-0.3, 0.3), rng.randi_range(0, 3))
		add("city_rubble", float(d) + 20.0, 11.0 if d % 2 == 0 else -11.0, rng.randf() * TAU, d % 4).set_meta("y", stage.height(float(d) + 20.0, 11.0 if d % 2 == 0 else -11.0))
	# Deep-water gap dressing is placed from the generated frontage data, never inside a tower box.
	var gap_index := 0
	for gap: Dictionary in stage.frontage_gaps:
		gap_index += 1
		if gap.gap < 4.0 or gap_index % 6 != 0 or stage.in_arena(float(gap.d), 30.0):
			continue
		if gap_index % 2:
			add("bus_wreck", float(gap.d), float(gap.u), rng.randf_range(-0.4, 0.4), rng.randi_range(0, 5))
		else:
			add("car", float(gap.d), float(gap.u), rng.randf() * TAU, rng.randi_range(0, 11))
		add("streetlamp", float(gap.d) - 5.0, float(gap.u) + gap.side * 3.0, 0.0, int(gap.d) % 6).set_meta("y", _afloat(stage, float(gap.d) - 5.0, float(gap.u) + gap.side * 3.0))
		add("road_sign", float(gap.d) + 6.0, float(gap.u) - gap.side * 2.0, 0.0, int(gap.d) % 4).set_meta("y", _afloat(stage, float(gap.d) + 6.0, float(gap.u) - gap.side * 2.0))
	for i in 5:
		var side := -1.0 if i % 2 == 0 else 1.0
		add_decor(CityKit.decor("crane"), Stage2.BAY_D - 110.0 + i * 55.0, side * 158.0, PI * 0.5 * side, Stage2.WATER_LEVEL - 4.0)
	for i in 14:
		var angle := TAU * i / 14.0 + 0.2
		add("raft", Stage2.BAY_D + sin(angle) * 70.0, cos(angle) * 70.0, angle, i % 6).set_meta("y", Stage2.WATER_LEVEL + 0.02)
	# Traffic stranded on the plaza gives the hovercraft fight something to read distance against and to smash.
	var plaza := RandomNumberGenerator.new()
	plaza.seed = 20261014
	for i in 10:
		var angle := TAU * i / 10.0 + plaza.randf_range(-0.2, 0.2)
		var radius := plaza.randf_range(20.0, Stage2.PLAZA_RADIUS - 14.0)
		add("bus_wreck" if i % 4 == 0 else "car", Stage2.PLAZA_D + sin(angle) * radius, cos(angle) * radius, plaza.randf() * TAU, plaza.randi_range(0, 11 if i % 4 else 5))
	# Drowned rooftops dress the bay arena so the boss fight has landmarks to read distances against; they are decor only.
	var bay := RandomNumberGenerator.new()
	bay.seed = 20261009
	for i in 18:
		var angle := TAU * i / 18.0 + bay.randf_range(-0.12, 0.12)
		var radius := bay.randf_range(48.0, Stage2.BAY_RADIUS - 14.0)
		add_decor(CityKit.decor("roof_island", i), Stage2.BAY_D + sin(angle) * radius, cos(angle) * radius, bay.randf() * TAU, Stage2.WATER_LEVEL - 0.6)
	# The arenas' invisible hull limit gets a visible edge: a ring of buoys just outside it.
	for arena: Dictionary in stage.arenas:
		var ring := add_decor(CityKit.decor("arena_ring", 0 if arena.d == Stage2.PLAZA_D else 1), float(arena.d), 0.0, 0.0, Stage2.WATER_LEVEL - 0.2)
		ring.set_meta("range", float(arena.radius) + 260.0)
	# Stalled traffic filling the drowned lanes, thicker in the quiet opening; wrecks wake out at the harbour.
	for d in range(100, int(Stage2.LENGTH) - 350, 55):
		if stage.in_arena(float(d), 30.0) or rng.randf() < (0.25 if d > 700 else 0.1):
			continue
		var lane := rng.randf_range(-9.0, 9.0)
		add("car", float(d), lane, rng.randf_range(-0.3, 0.3) + (PI if lane > 0.0 else 0.0), rng.randi_range(0, 11))
	# A row of breakable two-to-three-storey shops fronts the towers along each kerb, facing the street, with bus
	# shelters and kiosks on the pavement in front; the boulevard keeps a sparse median of plane trees.
	for side in [-1.0, 1.0]:
		var shop_d := 120.0 + (0.0 if side < 0.0 else 9.0)
		while shop_d < 3150.0:
			var kerb := stage.street_half(shop_d) - 4.0
			# Sample candidates even when a fork removes them, so exclusions do not reshuffle the frontage.
			var has_shop := rng.randf() < 0.65
			var variant := rng.randi_range(0, 11)
			# Under the expressway the kerb stays open, or the shops would hide the street from the hunters on the deck.
			var under_deck := false
			for ahead in [0.0, 50.0, 100.0]: # Deck hunters hold about 100 m ahead, so the gap leads each change of side.
				under_deck = under_deck or (stage.section_at(shop_d + ahead) == Stage2.Section.VIADUCT and side == stage.expressway_side(shop_d + ahead))
			var ruined := stage.section_at(shop_d) == Stage2.Section.CANYON # The canyon's shops lie in its rubble.
			if has_shop and not under_deck and not ruined and not stage.in_arena(shop_d, 35.0) and not _near_split(shop_d, 26.0):
				add("city_shop", shop_d, side * kerb, -side * PI * 0.5, variant)
			elif has_shop and ruined and not _near_split(shop_d, 26.0):
				add("city_rubble", shop_d, side * (kerb + 1.0), variant * 0.5, variant % 4).set_meta("y", stage.height(shop_d, side * (kerb + 1.0)))
			shop_d += rng.randf_range(15.0, 24.0)
	for d in range(180, 3150, 150):
		var side := -1.0 if d / 150 % 2 else 1.0
		var pavement := stage.street_half(float(d)) - 9.0
		if not stage.in_arena(float(d), 30.0) and not _near_split(float(d), 30.0):
			add("bus_shelter" if d / 150 % 3 else "kiosk", float(d), side * pavement, -side * PI * 0.5, d % 4)
	for d in range(140, 3150, 64):
		var section := stage.section_at(float(d))
		if section == Stage2.Section.BOULEVARD and not stage.in_arena(float(d), 30.0) and not _near_split(float(d), 30.0):
			add("plane_tree", float(d), rng.randf_range(-0.4, 0.4), rng.randf() * TAU, d % 3)
	add("subway_entrance", Stage2.PLAZA_D - 65.0, 55.0, 0.0, 0).set_meta("y", stage.height(Stage2.PLAZA_D - 65.0, 55.0))
	for d in range(2250, 3150, 180):
		add("truck", float(d), 8.0, 0.0, 1)
	_expressway_decor(stage)
	_canyon_rubble(stage)
	_concourse_decor()
	_kicker_decor(stage)


## Parapets along the elevated road, in 40 m pieces from the on-ramp to the broken span and again from the far span's
## hanging end to the off-ramp, and the snapped end of the near deck: broken slab and rebar hanging over the gap.
func _expressway_decor(stage: Stage2) -> void:
	for start in range(int(Stage2.ON_RAMP.x), int(Stage2.OFF_RAMP.y), 40):
		var middle := float(start) + 20.0
		add_decor(_parapet_mesh(stage, middle, 40.0), middle, 0.0, 0.0, 0.0).set_meta("range", 420.0)
	add_decor(_snapped_end_mesh(), Stage2.GAP.x, 0.0, 0.0, stage.height(Stage2.GAP.x - 1.0, 0.0)).set_meta("range", 700.0)


## The near deck's broken end in the frame of a decor at (GAP.x, 0) on the deck: chunks of slab tipped over the edge,
## and rebar hanging down into the gap.
func _snapped_end_mesh() -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1256
	var b := LowPoly.new()
	var u := -Stage2.DECK_HALF - 1.0
	while u < Stage2.DECK_HALF + 1.0:
		var width := rng.randf_range(1.5, 3.5)
		b.box(Transform3D(Basis.from_euler(Vector3(rng.randf_range(0.2, 0.9), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.15, 0.15))), Vector3(u + width * 0.5, -0.8, rng.randf_range(0.4, 1.4))), Vector3(width, 0.6, rng.randf_range(1.2, 2.6)), Palette.CONCRETE)
		for k in 2:
			var length := rng.randf_range(2.0, 7.0)
			b.box(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.2, 0.2))), Vector3(u + rng.randf_range(0.0, width), -length * 0.5, rng.randf_range(0.0, 0.8))), Vector3(0.14, length, 0.14), Palette.CORAL.darkened(0.35))
		u += width
	return b.mesh()


## A concrete parapet and its lamp posts on both edges of the deck, following its surface, in the frame of a decor
## placed at (d, 0).
func _parapet_mesh(stage: Stage2, d: float, length: float) -> Mesh:
	var origin := Course.to_world(d, 0.0, 0.0)
	var yaw := Course.yaw_at(d)
	var local := func(p: Vector3) -> Vector3: return (p - origin).rotated(Vector3.UP, -yaw)
	var b := LowPoly.new()
	var step := 4.0
	var s := -length * 0.5
	while s < length * 0.5:
		if stage.deck_level(d + s) < 0.8 or stage.deck_level(d + s + step) < 0.8:
			s += step
			continue
		for side: float in [-1.0, 1.0]:
			var a: Vector3 = local.call(Course.ground_at(d + s, side * (stage.lateral_limit(d + s) + 0.4)))
			var c: Vector3 = local.call(Course.ground_at(d + s + step, side * (stage.lateral_limit(d + s + step) + 0.4)))
			var along := c - a
			b.box(Transform3D(Basis.looking_at(along, Vector3.UP), (a + c) * 0.5 + Vector3.UP * 0.5), Vector3(0.7, 1.0, along.length() + 0.05), Palette.MIST, Palette.CREAM)
			if int(d + s) % 24 == 0:
				b.box(Transform3D(Basis(), a + Vector3.UP * 3.0), Vector3(0.25, 6.0, 0.25), Palette.ASH)
				b.glow = true
				b.box(Transform3D(Basis(), a + Vector3.UP * 6.1 - Vector3(side * 0.8, 0.0, 0.0)), Vector3(0.9, 0.2, 0.5), Palette.BUTTER)
				b.glow = false
		s += step
	return b.mesh()


## Heaps of rubble and drowned roofs strewn over the canyon's open lots, where the towers came down.
func _canyon_rubble(stage: Stage2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2150
	for side: float in Stage2.CANYON_LOTS:
		for lot: Array in Stage2.CANYON_LOTS[side]:
			if lot[2] != "open":
				continue
			var d: float = lot[0] + rng.randf_range(4.0, 12.0)
			while d < lot[1]:
				var u := side * (stage.street_half(d) + rng.randf_range(5.0, 30.0))
				if rng.randf() < 0.4:
					add_decor(CityKit.decor("roof_island", rng.randi_range(0, 5)), d, u, rng.randf() * TAU, Stage2.WATER_LEVEL - 0.6)
				else:
					add_decor(CityKit.decor("rubble", rng.randi_range(0, 7)), d, u, rng.randf() * TAU, Stage2.WATER_LEVEL - 0.4)
				d += rng.randf_range(14.0, 22.0)


## Ceiling lamp panels along the flooded concourse: the only light in it besides the mouths.
func _concourse_decor() -> void:
	var d := Stage2.CONCOURSE.y
	while d < Stage2.CONCOURSE.z:
		var b := LowPoly.new()
		b.glow = true
		for row: float in [-14.0, 0.0, 14.0]:
			b.box(Transform3D(Basis(), Vector3(row, 0.0, 0.0)), Vector3(3.2, 0.2, 1.6), Palette.CREAM if row == 0.0 else Palette.BUTTER)
		add_decor(b.mesh(), d, 0.0, 0.0, Stage2.ROOF_Y - 0.25).set_meta("range", 260.0)
		d += 16.0


## The IN sign and the steel rails up the deck's kicker, like the sand ramps of stage 3.
func _kicker_decor(stage: Stage2) -> void:
	var ramp: Dictionary = Stage2.RAMPS[Stage2.KICKER]
	var d := float(ramp.d)
	add_decor(_ramp_rails_mesh(d, 0.0, float(ramp.length)), d, 0.0, 0.0, 0.0).set_meta("range", 700.0)
	var sign_d := d - 24.0
	var sign := add_decor(_in_sign_mesh(sign_d), sign_d, 0.0, 0.0, stage.height(sign_d, 0.0) + 15.0)
	sign.set_meta("range", 700.0)
	_blinking.append(sign)


## Sand-buried downtown: the street furniture is sunk into the dunes and the cars lie half under them. Only the
## avenue, the canyon and the run are streets; the dune sea and the pit's basin keep just wrecks and signs.
func _buried_city() -> void:
	var stage := _city_shell() as Stage3
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261017
	var last := int(Stage3.LENGTH) - 300
	var street := func(d: float) -> bool: return stage.section_at(d) not in [Stage3.Section.OUTSKIRTS, Stage3.Section.PIT] and not (d > Stage3.DIVE_D - 20.0 and d < Stage3.RISE_END + 20.0)
	var basin := func(d: float) -> bool: return stage.section_at(d) == Stage3.Section.PIT
	# Every loop draws its random numbers as it always did and only then drops what the open stretches do not have, so
	# the run's decor below stays where it was.
	for d in range(100, last, 40):
		if stage.in_arena(float(d), 40.0):
			continue
		var side := -1.0 if (d / 40) % 2 == 0 else 1.0
		var u := side * (stage.lateral_limit(float(d)) - 3.0)
		var buried := rng.randf_range(2.0, 5.0)
		var lean := rng.randf_range(-0.25, 0.25)
		if street.call(float(d)):
			var lamp := add("streetlamp", float(d), u, 0.0 if side < 0.0 else PI, 0)
			lamp.set_meta("y", stage.height(float(d), u) - buried)
			lamp.tilt = Vector3(0.0, 0.0, lean)
	for d in range(180, last, 140):
		if stage.in_arena(float(d), 60.0) or not street.call(float(d)):
			continue
		var u := stage.lateral_limit(float(d)) - 4.0
		add("traffic_light", float(d), u, PI, 0).set_meta("y", stage.height(float(d), u) - 2.5)
		add("road_sign", float(d) + 55.0, -u, 0.0, d % 4).set_meta("y", stage.height(float(d) + 55.0, -u) - 1.8)
	# Cars drowned in sand to the windows, thicker in the quiet opening and scattered wide over the dune sea.
	for d in range(100, last, 55):
		if stage.in_arena(float(d), 30.0) or rng.randf() < (0.25 if d > 700 else 0.1):
			continue
		var lane := rng.randf_range(-9.0, 9.0)
		var yaw := rng.randf_range(-0.3, 0.3) + (PI if lane > 0.0 else 0.0)
		var variant := rng.randi_range(0, 11)
		var tilt := Vector3(rng.randf_range(-0.1, 0.1), 0.0, rng.randf_range(-0.12, 0.12))
		if basin.call(float(d)):
			continue
		lane *= 4.0 if d < int(Stage3.OPEN_END) - 60 else 1.0
		var car := add("car", float(d), lane, yaw, variant)
		car.set_meta("y", stage.height(float(d), lane) - 0.6)
		car.tilt = tilt
	for d in range(220, last, 210):
		if stage.in_arena(float(d), 50.0):
			continue
		var lane := rng.randf_range(-7.0, 7.0)
		var yaw := rng.randf_range(-0.4, 0.4)
		var variant := rng.randi_range(0, 5)
		if not basin.call(float(d)):
			add("bus_wreck", float(d), lane, yaw, variant).set_meta("y", stage.height(float(d), lane) - 0.8)
	for d in range(330, last, 260):
		if stage.in_arena(float(d), 50.0):
			continue
		var u := 11.0 if d % 2 == 0 else -11.0
		var across := rng.randf_range(-6.0, 6.0)
		var yaw := rng.randf_range(-0.3, 0.3)
		var variant := rng.randi_range(0, 3)
		var rubble_yaw := rng.randf() * TAU
		if not basin.call(float(d)):
			add("barricade", float(d), across, yaw, variant)
			add("city_rubble", float(d) + 20.0, u, rubble_yaw, d % 4).set_meta("y", stage.height(float(d) + 20.0, u))
	_dune_sea(stage)
	_tunnel(stage)
	_quicksand(stage)
	# Along the dune run the city is buried to its crowns: tower tops stick out of the sand far beyond the ramps.
	for d in range(int(Stage3.SECTION_STARTS[Stage3.Section.RUN]) + 40, int(Stage3.LENGTH), 70):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var u := side * rng.randf_range(130.0, 220.0)
		var size := Vector3(rng.randf_range(16.0, 26.0), 70.0, rng.randf_range(16.0, 26.0))
		var crown := add_decor(CityKit.tower(size, rng.randi_range(0, 15)), float(d) + rng.randf_range(-20.0, 20.0), u, rng.randf_range(-0.4, 0.4), stage.height(float(d), u) - size.y + rng.randf_range(20.0, 44.0))
		crown.tilt = Vector3(rng.randf_range(-0.12, 0.12), 0.0, rng.randf_range(-0.12, 0.12))
		crown.set_meta("range", 700.0)
	# The canyon's landmark: a glass tower that fell across the street and came to rest on the far roofs. The tank
	# runs under it; its underside stays high over the whole drivable width.
	var fallen := add_decor(CityKit.tower(Stage3.FALLEN_SIZE, 3), Stage3.FALLEN_D, Stage3.FALLEN_U, 0.0, -6.0)
	fallen.tilt = Vector3(0.0, 0.0, Stage3.FALLEN_TILT)
	fallen.set_meta("range", 900.0)
	for arena: Dictionary in stage.arenas:
		var ring := add_decor(CityKit.decor("arena_ring", 2), float(arena.d), 0.0, 0.0, 0.0)
		ring.set_meta("range", float(arena.radius) + 260.0)
	# Launch ramps: two steel rails up each sand ramp to its lip, and a blinking IN sign hung over its foot.
	var dunes := stage as Stage3
	for index in Stage3.HILL_COUNT:
		var d := dunes.hill_d(index)
		var u := dunes.hill_side(index) * Stage3.HILL_U
		add_decor(_ramp_rails_mesh(d, u), d, u, 0.0, 0.0).set_meta("range", 700.0)
		var sign_d := d - 24.0
		var sign := add_decor(_in_sign_mesh(sign_d), sign_d, u, 0.0, stage.height(sign_d, u) + 15.0)
		sign.set_meta("range", 700.0)
		_blinking.append(sign)


## The dune sea: tower tops and broken signs poking out of the sand at every distance from the road.
func _dune_sea(stage: Stage3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	for d in range(30, int(Stage3.OPEN_END), 24):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var u := side * (stage.lateral_limit(float(d)) + 6.0 + 130.0 * pow(rng.randf(), 2.0))
		var size := Vector3(rng.randf_range(14.0, 26.0), 70.0, rng.randf_range(14.0, 26.0))
		var top := add_decor(CityKit.tower(size, rng.randi_range(0, 15)), float(d) + rng.randf_range(-12.0, 12.0), u, rng.randf_range(-0.4, 0.4), stage.height(float(d), u) - size.y + rng.randf_range(8.0, 34.0))
		top.tilt = Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))
		top.set_meta("range", 700.0)
	# Signs on the lanes themselves: a broken one stands in the way, or topples for a point.
	for d in range(60, int(Stage3.OPEN_END) - 40, 46):
		var u := rng.randf_range(-48.0, 48.0)
		var sign := add("road_sign", float(d) + rng.randf_range(-10.0, 10.0), u, rng.randf() * TAU, rng.randi_range(0, 3))
		sign.set_meta("y", stage.height(sign.d, u) - 1.8)
		sign.tilt = Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))


## The subway tunnel: a lintel at each mouth and painted lane lines down the floor. Its roof and walls are structures.
func _tunnel(stage: Stage3) -> void:
	var floor_y := stage.height(Stage3.TUNNEL_D + Stage3.TUNNEL_BAY, 0.0)
	var mouth := add_decor(CityKit.decor("tunnel_portal"), Stage3.TUNNEL_D - 2.0, 0.0, 0.0, floor_y)
	mouth.set_meta("range", 500.0)
	var exit_mouth := add_decor(CityKit.decor("tunnel_portal"), Stage3.TUNNEL_END + 2.0, 0.0, PI, floor_y)
	exit_mouth.set_meta("range", 500.0)
	var b := LowPoly.new()
	var length := Stage3.TUNNEL_END - Stage3.TUNNEL_D
	for lane: float in [-Stage3.TUNNEL_HALF * 0.5, Stage3.TUNNEL_HALF * 0.5, 0.0]:
		var z := 3.0
		while z < length:
			b.box(Transform3D(Basis(), Vector3(lane, 0.04, -z)), Vector3(0.25 if lane != 0.0 else 0.5, 0.04, 5.0), Palette.CREAM if lane != 0.0 else Palette.AMBER)
			z += 12.0
	add_decor(b.mesh(), Stage3.TUNNEL_D, 0.0, 0.0, floor_y).set_meta("range", 500.0)


## The quicksand: a swirl of ochre arms over each funnel that turns slowly, so the sink reads from afar.
func _quicksand(stage: Stage3) -> void:
	for sink in Stage3.SINKS:
		var b := LowPoly.new()
		var rings := 8
		var sectors := 24
		var heights: Array[float] = []
		for ring in rings + 1:
			var total := 0.0
			for sector in sectors:
				var angle := TAU * sector / sectors
				total += stage.height(sink.x + cos(angle) * Stage3.SINK_RADIUS * ring / rings, sink.y + sin(angle) * Stage3.SINK_RADIUS * ring / rings)
			heights.append(total / sectors + 0.3)
		var vertex := func(ring: int, sector: int) -> Vector3:
			var angle := TAU * sector / sectors
			var r := Stage3.SINK_RADIUS * ring / rings
			return Vector3(cos(angle) * r, heights[ring], sin(angle) * r)
		for ring in rings:
			for sector in sectors:
				var arm := (sector + ring) % 8 < 4
				var color := Palette.OCHRE.darkened(0.35) if arm else Palette.STRAW.darkened(0.1)
				var next := (sector + 1) % sectors
				b.tri(vertex.call(ring, sector), vertex.call(ring, next), vertex.call(ring + 1, next), color, Vector3.UP)
				b.tri(vertex.call(ring, sector), vertex.call(ring + 1, next), vertex.call(ring + 1, sector), color, Vector3.UP)
		var swirl := add_decor(b.mesh(), sink.x, sink.y, 0.0, 0.0)
		swirl.set_meta("range", 450.0)
		_swirling.append(swirl)


## The jungle-swallowed valley. Each stretch grows its own cover: figs crowd the switchbacks, brush fuels the meadow,
## reeds fringe the ford, the avenue keeps its tangled street furniture, and the clearing is ringed so thickly that the
## fortress has to fell its way in.
func _jungle() -> void:
	var stage := _city_shell() as Stage4
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022
	var last := int(Stage4.LENGTH) - 100
	var avenue_from := int(Stage4.SECTION_STARTS[Stage4.Section.AVENUE])
	var avenue_to := int(Stage4.SECTION_STARTS[Stage4.Section.CLEARING])
	for d in range(avenue_from + 20, avenue_to, 40):
		var side := -1.0 if (d / 40) % 2 == 0 else 1.0
		var lamp := add("streetlamp", float(d), side * (stage.lateral_limit(float(d)) - 3.0), 0.0 if side < 0.0 else PI, 0)
		lamp.tilt = Vector3(0.0, 0.0, rng.randf_range(-0.3, 0.3))
	for d in range(avenue_from + 40, avenue_to, 140):
		var u := stage.lateral_limit(float(d)) - 4.0
		add("traffic_light", float(d), u, PI, 0)
		add("road_sign", float(d) + 55.0, -u, 0.0, d % 4)
	for d in range(100, last, 55):
		var keep := 0.75 if d >= avenue_from else 0.3
		if stage.in_arena(float(d), 30.0) or rng.randf() > keep or absf(d - Stage4.FORD_D) < Stage4.FORD_HALF + Stage4.BANK or absf(d - Stage4.GORGE_LIP) < 90.0:
			continue
		var lane := rng.randf_range(-9.0, 9.0)
		var car := add("car", float(d), lane, rng.randf_range(-0.3, 0.3) + (PI if lane > 0.0 else 0.0), rng.randi_range(0, 11))
		car.tilt = Vector3(rng.randf_range(-0.08, 0.08), 0.0, rng.randf_range(-0.1, 0.1))
	for d in range(220, last, 210):
		if not stage.in_arena(float(d), 50.0) and stage.section_at(float(d)) != Stage4.Section.FORD and stage.section_at(float(d)) != Stage4.Section.GORGE:
			add("bus_wreck", float(d), rng.randf_range(-7.0, 7.0), rng.randf_range(-0.4, 0.4), rng.randi_range(0, 5))
	for d in range(avenue_from + 30, avenue_to, 120):
		add("barricade", float(d), rng.randf_range(-6.0, 6.0), rng.randf_range(-0.3, 0.3), rng.randi_range(0, 3))
		add("city_rubble", float(d) + 20.0, 11.0 if d % 2 == 0 else -11.0, rng.randf() * TAU, d % 4)
	# Figs line the kerbs and the brush crowds the verge, densest in the switchbacks and the reeds. The meadow's brush
	# also spills across the lanes: it is the dry fuel the flame crews set alight.
	var tree_density := [0.9, 0.3, 0.55, 0.5, 0.4, 0.5]
	var brush_density := [0.5, 1.1, 1.3, 0.6, 0.5, 0.5]
	for d in range(60, last, 6):
		if stage.in_arena(float(d), 6.0):
			continue
		var section := stage.section_at(float(d))
		var limit := stage.lateral_limit(float(d))
		var wet := stage.ford_weight(float(d)) > 0.0 or stage.gorge_depth(float(d), 0.0) > 1.0
		for side in [-1.0, 1.0]:
			if rng.randf() < tree_density[section] and not wet:
				# Trunks stand a crown's width past the kerb, so no canopy hangs over the road at the chase camera's height.
				add("jungle_tree", float(d) + rng.randf_range(-4.0, 4.0), side * (limit + rng.randf_range(7.0, 26.0)), rng.randf() * TAU, rng.randi_range(0, 5))
		for i in 0 if wet else int(brush_density[section] * 2.0):
			if rng.randf() < minf(brush_density[section], 0.9):
				var reach := limit * (1.0 if section == Stage4.Section.STUMPS else 0.6) + (6.0 if section == Stage4.Section.STUMPS else 2.0)
				add("fern" if rng.randf() < 0.7 else "palm", float(d) + rng.randf_range(-3.0, 3.0), rng.randf_range(-1.0, 1.0) * reach, rng.randf() * TAU, rng.randi_range(0, 5))
	for d0 in range(0, avenue_from, int(JungleWall.CHUNK)):
		var mesh := JungleWall.chunk(stage, float(d0))
		if mesh:
			add_decor(mesh, d0 + JungleWall.CHUNK * 0.5, 0.0, 0.0, 0.0).set_meta("range", 320.0)
	_fallen_logs(stage)
	_bridge(stage)
	# The clearing is ringed with jungle: figs stand shoulder to shoulder past the rim, densest where the fortress comes in.
	for arena: Dictionary in stage.arenas:
		var ring := add_decor(CityKit.decor("arena_ring", 3), float(arena.d), 0.0, 0.0, 0.0)
		ring.set_meta("range", float(arena.radius) + 260.0)
		for i in 420:
			var toward := absf(wrapf(TAU * i / 420.0 - Stage4.ENTRY_ANGLE, -PI, PI))
			if toward > 1.0 and i % 2 != 0:
				continue
			var angle := TAU * i / 420.0 + rng.randf_range(-0.01, 0.01)
			var radius := float(arena.radius) + rng.randf_range(3.0, 40.0 if toward > 1.0 else 130.0)
			add("jungle_tree" if i % 4 else "palm", float(arena.d) + cos(angle) * radius, sin(angle) * radius, rng.randf() * TAU, rng.randi_range(0, 5))
		for i in 120:
			var angle := Stage4.ENTRY_ANGLE + rng.randf_range(-0.7, 0.7)
			var radius := float(arena.radius) + rng.randf_range(2.0, 100.0)
			add("fern", float(arena.d) + cos(angle) * radius, sin(angle) * radius, rng.randf() * TAU, rng.randi_range(0, 5))
		# The fortress's way in lies in ruins: trees already crushed flat along its line and broken slabs on the plaza, all decor so no shell is stopped by it.
		_crushed_swath(float(arena.d), float(arena.radius), rng)
		# Wrecks stranded on the plaza give the fight something to read distance against and to smash.
		for i in 14:
			var angle := TAU * i / 14.0 + rng.randf_range(-0.2, 0.2)
			var radius := rng.randf_range(20.0, float(arena.radius) - 18.0)
			add("bus_wreck" if i % 4 == 0 else "car", float(arena.d) + cos(angle) * radius, sin(angle) * radius, rng.randf() * TAU, rng.randi_range(0, 5))


## A strangler fig lies across the road at each hump: a drift up the roots hops it.
func _fallen_logs(stage: Stage4) -> void:
	var b := LowPoly.new()
	b.box(Transform3D(Basis(), Vector3(0.0, 0.6, 0.0)), Vector3(Stage4.LOG_HALF * 2.0 + 4.0, 1.2, 1.4), Palette.WOOD, Palette.MOSS)
	b.box(Transform3D(Basis(), Vector3(2.0, 1.4, 0.0)), Vector3(1.0, 0.8, 2.0), Palette.LEAF)
	var mesh := b.mesh()
	for log: Array in Stage4.LOGS:
		var d := float(log[0]) + Stage4.LOG_LENGTH + 1.2
		add_decor(mesh, d, float(log[1]), 0.0, stage.height(d, float(log[1])) - 0.1).set_meta("range", 500.0)


## The broken bridge: steel truss girders along the ramp to the lip, a snapped deck hanging from it, concrete piers
## broken off over the river, the far half's deck dangling from the opposite bank, and the blinking IN sign.
func _bridge(stage: Stage4) -> void:
	var d := Stage4.GORGE_LIP - Stage4.RAMP_LENGTH
	var u := Stage4.RAMP_U
	var origin := Course.to_world(d, u, 0.0)
	var yaw := Course.yaw_at(d)
	var at := func(dd: float, uu: float, y: float) -> Vector3: return (Course.to_world(dd, uu, y) - origin).rotated(Vector3.UP, -yaw)
	var beam := func(b: LowPoly, from: Vector3, to: Vector3, width: float, color: Color) -> void:
		var dir := (to - from).normalized()
		b.box(Transform3D(Basis.looking_at(dir, Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP), (from + to) * 0.5), Vector3(width, width, from.distance_to(to)), color)
	var steel := Palette.WOOD.lerp(Palette.OCHRE, 0.3)
	var b := LowPoly.new()
	var rise := 2.6
	for side: float in [-1.0, 1.0]:
		var x := u + side * (Stage4.RAMP_HALF + 0.4)
		var previous := Vector3.INF
		var previous_foot := Vector3.INF
		for s in range(0, int(Stage4.RAMP_LENGTH) + 1, 4):
			var foot: Vector3 = at.call(d + s, x, stage.height(d + s, x))
			var top := foot + Vector3.UP * rise
			beam.call(b, foot, top, 0.35, steel)
			if previous != Vector3.INF:
				beam.call(b, previous + Vector3.UP * rise, top, 0.3, steel)
				beam.call(b, previous_foot, top, 0.22, steel)
			previous = top - Vector3.UP * rise
			previous_foot = foot
		# The girders end in a snapped, bent tangle past the lip.
		var lip: Vector3 = at.call(Stage4.GORGE_LIP, x, Stage4.RAMP_RISE)
		beam.call(b, lip + Vector3.UP * rise, lip + Vector3(side * 0.6, rise - 1.4, -4.5), 0.3, steel)
		beam.call(b, lip, lip + Vector3(side * 0.4, -2.5, -3.2), 0.3, steel)
		b.glow = true
		b.blob(Transform3D(Basis(), lip + Vector3.UP * (rise + 0.5)), 0.35, Palette.AMBER)
		b.glow = false
	# The deck's last slab, snapped and hanging from the lip.
	var deck: Vector3 = at.call(Stage4.GORGE_LIP + 5.0, u, Stage4.RAMP_RISE - 2.0)
	b.box(Transform3D(Basis(Vector3.RIGHT, -0.55), deck), Vector3(Stage4.RAMP_HALF * 2.0, 0.7, 11.0), Palette.CONCRETE, Palette.ASH)
	# Piers standing in the river, broken off at different heights with rebar sticking out.
	for pier: Array in [[Stage4.GORGE_LIP + 12.0, 4.0], [Stage4.GORGE_LIP + 24.0, 0.0]]:
		for side: float in [-1.0, 1.0]:
			var x: float = u + side * 3.8
			var base: Vector3 = at.call(float(pier[0]), x, Stage4.GORGE_WATER)
			var top: float = float(pier[1]) - Stage4.GORGE_WATER
			b.box(Transform3D(Basis(), base + Vector3.UP * top * 0.5), Vector3(2.6, top, 2.6), Palette.CONCRETE.darkened(0.15))
			b.box(Transform3D(Basis(Vector3.FORWARD, 0.5) * Basis(Vector3.RIGHT, 0.3), base + Vector3.UP * (top + 0.3)), Vector3(2.2, 0.9, 2.2), Palette.CONCRETE)
			for k in 4:
				b.prism(Transform3D(Basis(Vector3.RIGHT, (k - 1.5) * 0.25) * Basis(Vector3.FORWARD, (k % 2 - 0.5) * 0.4), base + Vector3(-0.9 + k * 0.6, top, 0.0)), 0.07, 2.2, 3, Palette.ASH, 0.02)
	# Pylons of the cable-stayed bridge tower over the lip, so the gorge is read from far up the road: stays run back
	# down to the deck in the pylons' own plane, outside the chase camera's lane, and snapped ones hang beyond.
	for side: float in [-1.0, 1.0]:
		var x: float = u + side * (Stage4.RAMP_HALF + PYLON_OUT)
		var foot: Vector3 = at.call(Stage4.GORGE_LIP - 2.0, x, stage.height(Stage4.GORGE_LIP - 2.0, x) - 1.0)
		b.box(Transform3D(Basis(), foot + Vector3.UP * 12.0), Vector3(2.2, 24.0, 2.2), Palette.CONCRETE)
		b.box(Transform3D(Basis(), foot + Vector3.UP * 24.5), Vector3(2.6, 1.2, 2.6), Palette.ASH)
		var top := foot + Vector3.UP * 23.0
		for k in range(1, 7):
			beam.call(b, top, at.call(Stage4.GORGE_LIP - 2.0 - 5.0 * k, x, stage.height(Stage4.GORGE_LIP - 5.0 * k, x)) + Vector3.UP * 0.5, 0.18, Palette.INK)
		for k in 3:
			var hang := top + Vector3(-side * 0.3 * k, 0.0, -2.0 - 2.5 * k)
			beam.call(b, hang, hang + Vector3(-side * 1.2, -7.0 + k * 1.5, -1.5), 0.18, Palette.INK)
	b.box(Transform3D(Basis(), at.call(Stage4.GORGE_LIP - 2.0, u, stage.height(Stage4.GORGE_LIP - 2.0, u) + 25.0)), Vector3((Stage4.RAMP_HALF + PYLON_OUT) * 2.0 + 2.6, 1.1, 1.6), Palette.CONCRETE)
	# The far half: its deck dangles from the opposite bank into the gorge.
	var far: Vector3 = at.call(Stage4.GORGE_FAR - 4.0, u, -2.0)
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.6), far), Vector3(Stage4.RAMP_HALF * 2.0, 0.7, 10.0), Palette.CONCRETE, Palette.ASH)
	var posts := b.mesh()
	add_decor(posts, d, u, 0.0, 0.0).set_meta("range", 700.0)
	var sign_d := d - 24.0
	var sign := add_decor(_in_sign_mesh(sign_d), sign_d, u, 0.0, stage.height(sign_d, u) + 12.0)
	sign.set_meta("range", 700.0)
	_blinking.append(sign)


## Felled trunks and flattened crowns lying along the line the fortress drove in on, rim to centre, as one merged mesh.
func _crushed_swath(centre_d: float, radius: float, rng: RandomNumberGenerator) -> void:
	var origin := Course.to_world(centre_d, 0.0, 0.0)
	var yaw := Course.yaw_at(centre_d)
	var heading := Vector2.from_angle(Stage4.ENTRY_ANGLE)
	var b := LowPoly.new()
	for i in 60:
		var along := rng.randf_range(0.2, 1.45) * radius
		var at := heading * along + heading.orthogonal() * rng.randf_range(-30.0, 30.0)
		var p := (Course.to_world(centre_d + at.x, at.y, Course.height(centre_d + at.x, at.y) + 0.5) - origin).rotated(Vector3.UP, -yaw)
		var fall := Basis(Vector3.UP, -heading.angle() + rng.randf_range(-0.5, 0.5)) * Basis(Vector3.RIGHT, -PI * 0.5)
		b.prism(Transform3D(fall, p), rng.randf_range(0.5, 1.0), rng.randf_range(9.0, 16.0), 6, Palette.WOOD.darkened(0.3), 0.3)
		b.blob(Transform3D(Basis().scaled(Vector3(1.4, 0.35, 1.4)), p + fall * Vector3(0.0, 13.0, 0.0)), rng.randf_range(2.5, 4.0), Palette.PINE.lerp(Palette.WOOD, 0.4), 0, 0.3, rng.randi())
	for i in 30: # Broken walls and rubble heaps scattered over the plaza.
		var angle := TAU * i / 30.0 + rng.randf_range(-0.1, 0.1)
		var at := Vector2.from_angle(angle) * rng.randf_range(24.0, radius - 14.0)
		var p := (Course.to_world(centre_d + at.x, at.y, Course.height(centre_d + at.x, at.y)) - origin).rotated(Vector3.UP, -yaw)
		var tilt := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
		b.box(Transform3D(tilt, p + Vector3.UP * 0.9), Vector3(rng.randf_range(4.0, 9.0), rng.randf_range(1.2, 2.6), 1.1), Palette.CONCRETE.darkened(0.15), Palette.ASH)
		b.blob(Transform3D(Basis().scaled(Vector3(1.4, 0.5, 1.2)), p + Vector3.UP * 0.4), rng.randf_range(1.2, 2.4), Palette.STONE.lerp(Palette.MOSS, 0.3), 0, 0.4, rng.randi())
	add_decor(b.mesh(), centre_d, 0.0, 0.0, 0.0).set_meta("range", radius + 300.0)


## The skyline behind the front towers, merged into one mesh per BACKDROP_CHUNK of street to keep the live count low.
func _backdrop_chunks(stage: StageDef) -> void:
	var chunks := {}
	for block in stage.backdrop:
		var chunk := int(block.d / BACKDROP_CHUNK)
		var centre := (float(chunk) + 0.5) * BACKDROP_CHUNK
		var blocks: Array = chunks.get_or_add(chunk, [])
		blocks.append({"x": block.u, "z": centre - block.d, "size": block.size, "variant": block.variant})
	for chunk: int in chunks:
		var spec := add_decor(CityKit.backdrop(chunks[chunk], stage.number == 4), (float(chunk) + 0.5) * BACKDROP_CHUNK, 0.0, 0.0, stage.street_level - 4.5)
		spec.set_meta("range", BACKDROP_RANGE)


## Where a prop floating at the waterline sits: on top of rubble or pavement that rises above the water.
static func _afloat(stage: Stage2, d: float, u: float) -> float:
	return maxf(Stage2.WATER_LEVEL + 0.02, stage.height(d, u))


var _last_tank := Vector3.INF


## Whether `d` is within `reach` of one of stage 2's splitter towers, where the street divides into lanes.
static func _near_split(d: float, reach: float) -> bool:
	return Stage2.SPLITS.any(func(split: Dictionary) -> bool: return absf(d - float(split.d)) < maxf(reach, 100.0))


func _process(delta: float) -> void:
	var lit := fmod(Time.get_ticks_msec() * 0.001, 0.6) < 0.4
	for spec in _blinking:
		if is_instance_valid(spec.node):
			spec.node.visible = lit
	for spec in _swirling:
		if is_instance_valid(spec.node):
			spec.node.rotate_y(-delta * 0.5)
	var world := World.current
	if not world or not world.player or Course.stage.structures.is_empty():
		return
	var tank := world.player
	var to := tank.global_position
	var from := _last_tank if _last_tank != Vector3.INF and _last_tank.distance_to(to) < 200.0 else to
	if world.rail.mode == Rail.Mode.ARENA:
		to = arena_position(to, world.rail.d, 6.0)
	var corrected := drive_position(from, to, Tank.HULL_RADIUS)
	if not corrected.is_equal_approx(tank.global_position):
		var c := Course.to_course(corrected)
		tank.course_u = c.y
		if world.rail.mode == Rail.Mode.ARENA:
			tank._set_pose(Course.ground_at(c.x, c.y), tank.hull_yaw)
		else:
			tank._place(world.rail.d)
	_last_tank = tank.global_position


## A swept hull is sent sideways, not stopped inside a broad building or tunneled through it.
func drive_position(from: Vector3, to: Vector3, radius: float) -> Vector3:
	var result := to
	var destination := Course.to_course(to)
	var d := destination.x
	for pass_index in 8:
		var moved := false
		var travel := from.distance_to(result)
		for structure in Course.structure_boxes:
			var pose: Transform3D = structure.pose
			var reach: float = structure.size.length() * 0.5 + radius + travel
			if Vector2(result.x - pose.origin.x, result.z - pose.origin.z).length_squared() > reach * reach:
				continue
			var distance := Prop.box_hit(pose, structure.size, from, result, radius)
			if distance < 0.0:
				continue
			var contact := from.lerp(result, distance / maxf(from.distance_to(result), 0.0001))
			var side := -signf(structure.u) if structure.u != 0.0 else (1.0 if Course.to_course(result).y >= 0.0 else -1.0)
			var right := Course.right(structure.d) * side
			var local := pose.affine_inverse() * contact
			var dir := pose.basis.inverse() * right
			var shift := INF
			for axis in [0, 2]:
				if absf(dir[axis]) > 0.0001:
					var edge: float = structure.size[axis] * 0.5 + radius + 0.1
					shift = minf(shift, (edge * signf(dir[axis]) - local[axis]) / dir[axis])
			result += right * maxf(shift, 0.1)
			result = Course.to_world(d, Course.to_course(result).y, result.y)
			moved = true
		# The old position may itself have been inside (e.g. a checkpoint or a teleport).
		from = result
		if not moved:
			break
	return result


## Pull the eye toward the hull before it enters a deck underside or a facade.
func camera_position(target: Vector3, eye: Vector3) -> Vector3:
	if Course.stage.city:
		var camera_course := Course.to_course(eye)
		if not Course.stage.in_arena(camera_course.x):
			var eye_clear := true
			for structure in Course.structure_boxes:
				if Prop.box_hit(structure.pose, structure.size, eye, eye, 0.8) >= 0.0:
					eye_clear = false
					break
			if eye_clear:
				return eye
			for offset in [-8.0, 8.0, -14.0, 14.0]:
				var candidate: Vector3 = eye + Course.right(camera_course.x) * offset
				var candidate_clear := true
				for structure in Course.structure_boxes:
					if Prop.box_hit(structure.pose, structure.size, candidate, candidate, 0.8) >= 0.0:
						candidate_clear = false
						break
				if candidate_clear:
					return candidate
	var reach := target.distance_to(eye)
	var clear := reach
	for structure in Course.structure_boxes:
		var distance := Prop.box_hit(structure.pose, structure.size, target, eye, 0.8)
		if distance >= 0.0:
			clear = minf(clear, maxf(distance - 0.2, 0.0))
	return target.lerp(eye, clear / maxf(reach, 0.0001))


func arena_position(point: Vector3, d: float, margin := 0.0) -> Vector3:
	var arena := Course.stage.arena_at(d)
	var center := Course.to_world(arena.d, 0.0)
	var offset := Vector2(point.x - center.x, point.z - center.z).limit_length(maxf(arena.radius - margin, 0.0))
	return Vector3(center.x + offset.x, point.y, center.z + offset.y)


## Boss impacts remove both the visual prop and its persistent solid, even outside the stream.
## Only explicitly named cover is affected.
func crush_cover(from: Vector3, to: Vector3, reach: float, kinds: Array[String]) -> int:
	var removed := 0
	for spec in specs:
		if spec.kind not in kinds or spec.has_meta("destroyed"):
			continue
		var at := Course.to_world(spec.d, spec.u, float(spec.get_meta("y", Course.height(spec.d, spec.u))))
		var closest := Geometry3D.get_closest_point_to_segment(at, from, to)
		var extent := spec.size.length() * 0.5 if spec.size != Vector3.ZERO else float(PROPS[spec.kind][0])
		if Vector2(at.x - closest.x, at.z - closest.z).length() > reach + extent:
			continue
		_destroy_spec(spec)
		if is_instance_valid(spec.node):
			var prop := spec.node as Prop
			if prop != null and not prop.dead:
				prop.die(Hit.make(Hit.Kind.RAM, 0.0, at, (to - from).normalized()))
			else:
				spec.node.queue_free()
		World.current.fx.debris(at + Vector3.UP, 12, [Fx.Debris.METAL, Fx.Debris.CONCRETE], 12.0, 0.6)
		removed += 1
	return removed


## Takes a solid structure away at run time: its collision box and its prop, if streamed in.
func remove_structure(kind: String, d: float, u: float) -> void:
	for spec in specs:
		if spec.kind == kind and spec.size != Vector3.ZERO and spec.d == d and spec.u == u and not spec.has_meta("destroyed"):
			_destroy_spec(spec)
			if is_instance_valid(spec.node):
				spec.node.queue_free()


func _destroy_spec(spec: Spec) -> void:
	spec.set_meta("destroyed", true)
	if spec.size == Vector3.ZERO:
		return
	for i in range(Course.structure_boxes.size() - 1, -1, -1):
		var box: Dictionary = Course.structure_boxes[i]
		if box.d == spec.d and box.u == spec.u and box.size == spec.size:
			Course.structure_boxes.remove_at(i)


## HARD cover, including streamed-out city boxes; destroyed ordinary props no longer block sight.
func line_blocked(from: Vector3, to: Vector3) -> bool:
	for structure in Course.structure_boxes:
		if Prop.box_hit(structure.pose, structure.size, from, to) >= 0.0:
			return true
	if World.current:
		for prop: Prop in World.current.props.near(from, to, 24.0):
			if prop.hard and not prop.dead and prop.hit_test(from, to) >= 0.0:
				return true
	return false


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
			add("veins", d, u, yaw, _rng.randi_range(0, 5))
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
	add_pickup("micro", 470.0, 5.0)
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
	add_pickup("dragon", 1520.0, 0.0)
	_fungus(1560.0, 1760.0, 1.4)


func _reservoir() -> void:
	var d := 1780.0
	while d < 2640.0:
		add("reeds", d, _rng.randf_range(-24.0, -17.0))
		if _rng.randf() < 0.5:
			add("reeds", d + 4.0, _rng.randf_range(-20.0, -15.0))
		d += _rng.randf_range(6.0, 12.0)
	for pd in [1900.0, 2150.0, 2400.0]:
		add_decor(PropKit.mesh("pier", int(pd)), pd, -60.0 - _rng.randf_range(0, 20), _rng.randf() * TAU, Stage1.WATER_LEVEL)
	_scatter("house", 1780.0, 2640.0, 6, 22.0, 40.0, false)
	_scatter("car", 1800.0, 2640.0, 18, 0.0, 12.0)
	add_pickup("atgm", 2000.0, 6.0)
	add_pickup("era", 2150.0, -4.0)
	add_pickup("tail", 2450.0, 3.0)
	add_pickup("coax", 2300.0, -5.0)
	add_pickup("repair", 2560.0, 4.0)
	_fungus(1760.0, 2660.0, 1.6)


func _overpass() -> void:
	var group := _groups.size()
	_groups.append({})
	for i in OVERPASS_PIERS.size():
		var pier := add("overpass_pier", Stage1.UNDERPASS_D, OVERPASS_PIERS[i], 0.0, 0)
		pier.set_meta("y", OVERPASS_PIER_Y)
		pier.group = group
		pier.index = i
	for j in OVERPASS_SPANS.size():
		var span: Array = OVERPASS_SPANS[j]
		var deck := add("overpass_deck", Stage1.UNDERPASS_D, span[0], 0.0, span[1])
		deck.set_meta("y", OVERPASS_DECK_Y)
		deck.group = group
		deck.index = OVERPASS_PIERS.size() + j
		deck.rests_on = OVERPASS_PIERS.find(span[2])
	var d := Stage1.RAMP_UP.y
	while d < Stage1.RAMP_DOWN.x:
		add_decor(_rail_mesh(), d, -14.6, 0.0)
		add_decor(_rail_mesh(), d, 14.6, 0.0)
		d += 12.0
	add_decor(_gantry_mesh(), 3080.0, 0.0, 0.0)
	add_decor(_gantry_mesh(), 3260.0, 0.0, 0.0)
	for td in [3040.0, 3140.0, 3220.0, 3300.0]:
		add("truck" if _rng.randf() < 0.5 else "car", td, _rng.randf_range(-9.0, 9.0), _rng.randf_range(-0.4, 0.4))
	_scatter("car", 2680.0, 2890.0, 10, 0.0, 12.0)
	add_pickup("era", 2950.0, -3.0)
	add_pickup("tail", 3050.0, 4.0)
	_fungus(2660.0, 2900.0, 1.8)
	if Game.difficulty == Game.Difficulty.HARD:
		for site in [Vector2(2725.0, -18.0), Vector2(2780.0, 18.0), Vector2(2860.0, -20.0)]:
			add("house", site.x, site.y, 0.0, 0)


func _arena() -> void:
	var dam := Spec.new()
	dam.kind = "dam"
	dam.decor = true
	dam.d = Stage1.DAM_D
	specs.append(dam)
	for i in 10:
		var angle := TAU * i / 10.0 + 0.3
		var r := _rng.randf_range(35.0, 70.0)
		add("rock", Stage1.ARENA_CENTER_D + sin(angle) * r, cos(angle) * r)
	for i in 8:
		var angle := TAU * i / 8.0
		add("spore_tower", Stage1.ARENA_CENTER_D + sin(angle) * 80.0, cos(angle) * 80.0)
	_scatter("car", 3440.0, 3600.0, 4, 10.0, 60.0)
	_fungus(3420.0, 3620.0, 1.2)


## Explosive barrels in clusters along the road, and a gas station whose pumps go up like bombs.
func _boom() -> void:
	var d := 180.0
	while d < Stage1.SECTION_STARTS[Stage1.Section.ARENA]:
		if Course.section_at(d) != Stage1.Section.SCHOOL:
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
	while d < Stage1.DAM_D - 40.0:
		var u := side * _rng.randf_range(26.0, 48.0)
		if Course.section_at(d) == Stage1.Section.RESERVOIR and side < 0.0:
			u = side * _rng.randf_range(18.0, 22.0)
		add("fungal_spire", d, u, _rng.randf() * TAU, _rng.randi_range(0, 5))
		d += lerpf(170.0, 80.0, d / Stage1.DAM_D) + _rng.randf_range(-20.0, 20.0)
		side = -side


## Utility poles along the road with sagging wires between them.
func _wires() -> void:
	for side in [-1.0, 1.0]:
		var d := 10.0 if side < 0.0 else 30.0
		var previous := Vector3.INF
		var previous_pole: Spec = null
		while d < Stage1.SECTION_STARTS[Stage1.Section.OVERPASS]:
			var u: float = side * 9.5
			if Course.section_at(d) == Stage1.Section.RESERVOIR and side < 0.0:
				previous = Vector3.INF
				d += 40.0
				continue
			if Course.section_at(d) == Stage1.Section.SCHOOL:
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


const RAMP_GAUGE := TrackMarks.TRACK_OFFSET * 2.0 ## The rails run under the tank's tracks.
const PYLON_OUT := 9.0 ## How far the broken bridge's pylons and their stays stand outside its deck: clear of the chase camera.


## Rails, sleepers and guide lights from just short of a ramp's foot to its lip, in the frame of a decor placed at
## (d, u) on the ground's zero.
func _ramp_rails_mesh(d: float, u: float, length := Stage3.HILL_LENGTH) -> Mesh:
	var origin := Course.to_world(d, u, 0.0)
	var yaw := Course.yaw_at(d)
	var local := func(p: Vector3) -> Vector3: return (p - origin).rotated(Vector3.UP, -yaw)
	var b := LowPoly.new()
	var step := 4.0
	var s := -12.0
	while s < length:
		var next := minf(s + step, length)
		for side: float in [-1.0, 1.0]:
			var x := u + side * RAMP_GAUGE * 0.5
			var a: Vector3 = local.call(Course.ground_at(d + s, x) + Vector3.UP * 0.25)
			var c: Vector3 = local.call(Course.ground_at(d + next, x) + Vector3.UP * 0.25)
			b.glow = false
			b.box(Transform3D(Basis.looking_at(c - a, Vector3.UP), (a + c) * 0.5), Vector3(0.5, 0.5, a.distance_to(c) + 0.05), Palette.DUSK, Palette.ASH)
			if int(s) % 8 == 0:
				b.glow = true
				b.box(Transform3D(Basis.looking_at(c - a, Vector3.UP), a + (a - local.call(Course.ground_at(d + s, u) + Vector3.UP * 0.25)).normalized() * 0.9), Vector3(0.3, 0.2, 0.6), Palette.AMBER)
		var tie_a: Vector3 = local.call(Course.ground_at(d + s, u))
		var tie_c: Vector3 = local.call(Course.ground_at(d + s + 1.0, u))
		b.glow = false
		b.box(Transform3D(Basis.looking_at(tie_c - tie_a, Vector3.UP), tie_a + Vector3.UP * 0.05), Vector3(RAMP_GAUGE + 1.4, 0.2, 0.6), Palette.WOOD)
		s += step
	return b.mesh()


## A Metal Slug style IN marker: pixel letters over a down arrow on a dark board, facing the tank coming up the
## road at `d`, centred on the decor's origin.
func _in_sign_mesh(d: float) -> Mesh:
	var yaw := Course.yaw_at(d)
	var ahead := Course.forward(d).rotated(Vector3.UP, -yaw)
	var right := ahead.cross(Vector3.UP).normalized()
	var facing := Basis(right, Vector3.UP, -ahead)
	var rows := ["###.#...#", ".#..##..#", ".#..#.#.#", ".#..#..##", "###.#...#", ".........", "..#####..", "...###...", "....#...."]
	var cell := 0.7
	var b := LowPoly.new()
	b.box(Transform3D(facing, ahead * 0.3 + Vector3.UP * -cell * 0.5), Vector3(cell * 11.0, cell * 11.0, 0.3), Palette.INK)
	b.glow = true
	for r in rows.size():
		for c in rows[r].length():
			if rows[r][c] == "#":
				var at: Vector3 = right * (c - 4) * cell + Vector3.UP * (4 - r) * cell
				b.box(Transform3D(facing, at), Vector3(cell * 0.9, cell * 0.9, 0.3), Palette.AMBER if r < 5 else Palette.HOT)
	return b.mesh()


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


## Limits both the count and time spent attaching nodes. Explicit large budgets are used by
## loading/screenshots and still finish synchronously before the world is displayed.
func stream(d: float, budget := 8) -> void:
	var deadline := Time.get_ticks_usec() + STREAM_BUDGET_USEC if budget <= 8 else 0
	while _next < specs.size() and specs[_next].d < d + AHEAD and budget > 0:
		var spec := specs[_next]
		_next += 1
		if spec.d < d - BEHIND or is_instance_valid(spec.node) or spec.has_meta("destroyed"):
			continue
		_instantiate(spec)
		budget -= 1
		if deadline > 0 and Time.get_ticks_usec() >= deadline:
			break
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


## Drops what is live and streams the plan afresh around `d`, so a jump in either direction shows its props.
func seek(d: float) -> void:
	for spec in _live:
		if is_instance_valid(spec.node):
			spec.node.queue_free()
		spec.node = null
	_live.clear()
	_next = 0
	stream(d, 100000)


func _instantiate(spec: Spec) -> void:
	var y: float = spec.get_meta("y") if spec.has_meta("y") else Course.height(spec.d, spec.u) + spec.lift
	var position := Course.to_world(spec.d, spec.u, y)
	var yaw := spec.yaw + Course.yaw_at(spec.d)
	if not spec.pickup.is_empty():
		# Loot is only laid out for a tank to collect; the title backdrop has none.
		if World.current.player:
			spec.node = World.current.spawn_pickup(spec.pickup, position + Vector3.UP * 1.6)
	elif spec.kind == "dam":
		var dam := Dam.new()
		add_child(dam)
		dam.global_position = Course.to_world(spec.d, 0.0, 0.0)
		dam.rotation.y = yaw
		spec.node = dam
	elif spec.decor:
		var decor := MeshInstance3D.new()
		decor.mesh = spec.mesh
		decor.visibility_range_end = spec.get_meta("range", 260.0)
		add_child(decor)
		decor.global_position = position
		decor.rotation = Vector3(spec.tilt.x, yaw, spec.tilt.z)
		spec.node = decor
	else:
		var cfg: Array = PROPS[spec.kind]
		var prop := Prop.new()
		if spec.size != Vector3.ZERO:
			prop.setup(spec.kind, PropKit.structure_mesh(spec.kind, spec.size, spec.variant), minf(spec.size.x, spec.size.z) * 0.5, spec.size.y, cfg[2])
			prop.box_size = spec.size
			prop.invulnerable = spec.kind not in ["container", "ship"]
		else:
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
		prop.hard = spec.kind in HARD
		prop.fungal = spec.kind in FUNGAL
		prop.flattens = spec.kind == "veins"
		prop.debris = _debris(spec.kind)
		# Position before entering the tree: props register into spatial buckets on entry.
		prop.position = position
		prop.rotation = Vector3(spec.tilt.x, yaw, spec.tilt.z)
		World.current.props.add_child(prop)
		spec.node = prop
		prop.died.connect(func(_prop: Entity) -> void: _destroy_spec(spec))
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
		"jungle_building", "house", "hall", "church_nave", "church_tower", "church_spire", "school_wing", "school_center":
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
		"pole", "streetlamp", "traffic_light", "road_sign":
			return [Fx.Debris.CONCRETE, Fx.Debris.METAL]
		"raft":
			return [Fx.Debris.WOOD, Fx.Debris.METAL]
		"city_rubble", "subway_entrance":
			return [Fx.Debris.CONCRETE, Fx.Debris.METAL]
		"container", "ship":
			return [Fx.Debris.METAL, Fx.Debris.PAINT]
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
		"mushroom", "spore_tower", "fungal_spire", "flesh_mound", "cordyceps", "egg_sacs", "husk_cow", "veins":
			return [Fx.Debris.FLESH, Fx.Debris.SPORE]
		"persimmon", "plane_tree", "zelkova_trunk", "zelkova_canopy", "jungle_tree", "palm", "fern":
			return [Fx.Debris.WOOD, Fx.Debris.FOLIAGE]
		"gas_station":
			return [Fx.Debris.CONCRETE, Fx.Debris.METAL, Fx.Debris.GLASS, Fx.Debris.PAINT]
		"crate":
			return [Fx.Debris.WOOD]
		"rock":
			return [Fx.Debris.ROCK]
		"overpass_pier", "overpass_deck":
			return [Fx.Debris.CONCRETE, Fx.Debris.ROCK, Fx.Debris.METAL]
	return [Fx.Debris.CONCRETE, Fx.Debris.WOOD]
