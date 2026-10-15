class_name JungleWall
extends RefCounted
## The stage 4 jungle that is only scenery: layered walls of undergrowth, palms and emergent figs with hanging vines,
## a leaf canopy arching over the road, boulders and reeds at the ford. One merged mesh per chunk of road keeps the
## live node count low; the figs and brush the tank can ram or burn are the stage's Scenery props.

const CHUNK := 40.0
const DARK := [Palette.PINE, Palette.MOSS, Palette.PINE]
const FROND := [Palette.MOSS, Palette.SAGE, Palette.PINE]


## The wall's strength at `d`, 0 (none) to 1 (solid), and how far the open ground beside the road reaches before it.
static func density(d: float) -> float:
	match Course.stage.section_at(d):
		Stage4.Section.VERGE:
			return 1.0
		Stage4.Section.STUMPS:
			return 0.4
		Stage4.Section.FORD, Stage4.Section.GORGE:
			return 0.8
	return 0.0


## How much canopy closes over the road at `d`.
static func arch(d: float) -> float:
	return 1.0 if Course.stage.section_at(d) == Stage4.Section.VERGE and d > 60.0 else 0.0


## The mesh for the chunk starting at `d0`, in the frame of a decor placed at the chunk's centre on the road (like
## Scenery's ramp rails), or null when nothing grows there.
static func chunk(stage: Stage4, d0: float) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d0) * 7 + 3
	var centre := d0 + CHUNK * 0.5
	var origin := Course.to_world(centre, 0.0, 0.0)
	var yaw := Course.yaw_at(centre)
	var b := LowPoly.new()
	var local := func(d: float, u: float, lift := 0.0) -> Vector3:
		var p := Course.to_world(d, u, Course.height(d, u) + lift) - origin
		return p.rotated(Vector3.UP, -yaw)
	var any := false
	for _i in 6:
		var d := d0 + rng.randf() * CHUNK
		var near := density(d)
		if near <= 0.0:
			continue
		any = true
		var limit := stage.lateral_limit(d)
		var wet := stage.ford_weight(d) > 0.0 or stage.gorge_depth(d, 0.0) > 1.0
		for side: float in [-1.0, 1.0]:
			var gap := 14.0 if stage.section_at(d) == Stage4.Section.STUMPS else 0.0
			if not wet:
				_emergent(b, local, rng, d, side * (limit + gap + rng.randf_range(3.0, 30.0)), near)
				_palm(b, local, rng, d + rng.randf_range(-6.0, 6.0), side * (limit + gap + rng.randf_range(-2.0, 18.0)))
			for _k in 3:
				_bush(b, local, rng, d + rng.randf_range(-6.0, 6.0), side * (limit + gap + rng.randf_range(-3.0, 16.0)))
		if arch(d) > 0.0:
			var crown: Vector3 = local.call(d, rng.randf_range(-1.0, 1.0) * limit, 19.0 + rng.randf() * 3.0)
			b.blob(Transform3D(Basis().scaled(Vector3(1.0, 0.45, 1.0)), crown), rng.randf_range(6.0, 9.0), DARK[rng.randi() % 3], 0, 0.3, rng.randi())
	if absf(centre - Stage4.FORD_D) < Stage4.FORD_HALF + Stage4.BANK + CHUNK:
		any = _ford(b, local, rng, d0, stage) or any
	return b.mesh() if any else null


static func _emergent(b: LowPoly, local: Callable, rng: RandomNumberGenerator, d: float, u: float, near: float) -> void:
	if rng.randf() > near:
		return
	var base: Vector3 = local.call(d, u)
	var height := rng.randf_range(17.0, 28.0)
	b.prism(Transform3D(Basis(), base - Vector3.UP * 1.0), rng.randf_range(0.9, 1.5), height, 6, Palette.WOOD.darkened(0.35), 0.45)
	for i in 5:
		var angle := rng.randf() * TAU
		var reach := rng.randf_range(0.0, 4.0)
		var at := base + Vector3(cos(angle) * reach, height - rng.randf_range(0.0, 5.0), sin(angle) * reach)
		b.blob(Transform3D(Basis().scaled(Vector3(1.0, 0.6, 1.0)), at), rng.randf_range(3.5, 6.0), DARK[i % 3], 0, 0.3, rng.randi())
	for _k in 3: # Vines hang from the crown.
		var angle := rng.randf() * TAU
		var top := base + Vector3(cos(angle) * 3.0, height - 3.0, sin(angle) * 3.0)
		b.prism(Transform3D(Basis(Vector3.RIGHT, PI), top), 0.08, rng.randf_range(6.0, 12.0), 3, Palette.MOSS, 0.02)


static func _palm(b: LowPoly, local: Callable, rng: RandomNumberGenerator, d: float, u: float) -> void:
	var base: Vector3 = local.call(d, u)
	var height := rng.randf_range(7.0, 13.0)
	b.prism(Transform3D(Basis(), base), 0.3, height, 5, Palette.WOOD.darkened(0.3), 0.2)
	for i in 7:
		var angle := TAU * i / 7.0 + rng.randf()
		b.prism(Transform3D(Basis(Vector3.UP, -angle) * Basis(Vector3.FORWARD, -1.1), base + Vector3.UP * height), 0.2, rng.randf_range(4.0, 5.5), 4, FROND[i % 3], 0.02)


static func _bush(b: LowPoly, local: Callable, rng: RandomNumberGenerator, d: float, u: float) -> void:
	var at: Vector3 = local.call(d, u, rng.randf_range(0.4, 1.4))
	b.blob(Transform3D(Basis().scaled(Vector3(1.0, 0.7, 1.0)), at), rng.randf_range(1.4, 2.8), DARK[rng.randi() % 3].lerp(Palette.SAGE, rng.randf() * 0.35), 0, 0.35, rng.randi())
	if rng.randf() < 0.5: # Broad leaves: banana-style blades.
		var base: Vector3 = local.call(d, u)
		for i in 4:
			b.prism(Transform3D(Basis(Vector3.UP, TAU * i / 4.0) * Basis(Vector3.FORWARD, -0.7), base), 0.28, 3.4, 4, FROND[i % 3], 0.03)


## Boulders in the river beside the road and reeds along both banks; returns whether anything was placed.
static func _ford(b: LowPoly, local: Callable, rng: RandomNumberGenerator, d0: float, stage: Stage4) -> bool:
	var placed := false
	for _i in 14:
		var d := d0 + rng.randf() * CHUNK
		var u := rng.randf_range(-1.0, 1.0) * 80.0
		if absf(u) < stage.lateral_limit(d) + 2.0 or stage.water_surface(Vector2(d, u)) == -INF:
			continue
		b.blob(Transform3D(Basis().scaled(Vector3(1.3, 0.8, 1.0)), local.call(d, u, 0.0) + Vector3.UP * 0.2), rng.randf_range(0.9, 2.2), Palette.STONE.lerp(Palette.SLATE, rng.randf() * 0.6), 0, 0.3, rng.randi())
		placed = true
	for _i in 10:
		var d := d0 + rng.randf() * CHUNK
		var u := rng.randf_range(-1.0, 1.0) * 70.0
		var h := stage.height(d, u)
		if absf(u) < stage.lateral_limit(d) - 6.0 or h > Stage4.FORD_WATER + 0.9 or h < Stage4.FORD_WATER - 0.5 or absf(d - Stage4.FORD_D) > Stage4.FORD_HALF + Stage4.BANK:
			continue
		var base: Vector3 = local.call(d, u)
		for k in 6:
			b.prism(Transform3D(Basis(Vector3.UP, TAU * k / 6.0) * Basis(Vector3.FORWARD, rng.randf_range(0.05, 0.3)), base + Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6))), 0.07, rng.randf_range(1.8, 3.0), 3, Palette.SAGE if k % 2 else Palette.MOSS, 0.01)
		placed = true
	return placed
