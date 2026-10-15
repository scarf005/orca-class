class_name CityKit
extends RefCounted
## Street furniture and wreckage for the Submerged City, plus the facades of its towers.
## Decor meshes are cached by kind; towers vary by size and variant.

static var _cache := {}

const ARENA_RING_INSET := 4.0 ## Metres inside the arena radius; the hull is held 6 m inside, so the ring sits just beyond it.

const FACADES := [Palette.CONCRETE, Palette.STONE, Palette.SKY, Palette.ASH, Palette.TEAL, Palette.MIST, Palette.BLUSH, Palette.PEACH]
const AWNINGS := [Palette.CORAL, Palette.TEAL, Palette.BUTTER, Palette.LILAC, Palette.MINT]
const SIGNS := [Palette.CORAL, Palette.BUTTER, Palette.MINT, Palette.SKY, Palette.BLUSH, Palette.LILAC, Palette.WHITE, Palette.RED]
## Seven-segment digits for painted apartment block numbers: a, b, c, d, e, f, g.
const SEGMENTS := ["1111110", "0110000", "1101101", "1111001", "0110011", "1011011", "1011111", "1110000", "1111111", "1111011"]


static func decor(kind: String, variant := 0) -> Mesh:
	var key := "%s:%d" % [kind, variant]
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		_cache[key] = Callable(CityKit, "_" + kind).call(variant, rng)
	return _cache[key]


static func _xf(pos: Vector3, yaw := 0.0, pitch := 0.0, roll := 0.0) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(pitch, yaw, roll)), pos)


static func _streetlamp(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(_xf(Vector3.ZERO), 0.22, 0.5, 6, Palette.STONE, 0.18)
	b.prism(_xf(Vector3(0, 0.5, 0)), 0.11, 8.0, 6, Palette.ASH, 0.08)
	b.box(_xf(Vector3(1.0, 8.4, 0), 0, 0, -0.08), Vector3(2.4, 0.16, 0.16), Palette.ASH)
	b.box(_xf(Vector3(2.0, 8.25, 0)), Vector3(0.9, 0.22, 0.4), Palette.STONE)
	b.glow = true
	b.box(_xf(Vector3(2.0, 8.1, 0)), Vector3(0.7, 0.08, 0.28), Palette.BUTTER)
	return b.mesh()


static func _traffic_light(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(_xf(Vector3.ZERO), 0.16, 6.2, 6, Palette.SLATE, 0.12)
	b.box(_xf(Vector3(-2.2, 6.0, 0)), Vector3(4.6, 0.18, 0.18), Palette.SLATE)
	for i in 2:
		var x := -1.6 - i * 2.0
		b.box(_xf(Vector3(x, 5.5, 0)), Vector3(0.5, 1.4, 0.5), Palette.INK)
		b.glow = true
		b.box(_xf(Vector3(x, 5.9, 0.27)), Vector3(0.28, 0.28, 0.04), Palette.RED)
		b.box(_xf(Vector3(x, 5.5, 0.27)), Vector3(0.28, 0.28, 0.04), Palette.BUTTER)
		b.box(_xf(Vector3(x, 5.1, 0.27)), Vector3(0.28, 0.28, 0.04), Palette.NANITE if i == 0 else Palette.INK)
		b.glow = false
	return b.mesh()


static func _kiosk(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var color: Color = AWNINGS[variant % AWNINGS.size()]
	b.box(_xf(Vector3(0, 1.2, 0)), Vector3(2.6, 2.4, 2.0), Palette.STONE)
	b.box(_xf(Vector3(0, 2.55, 0)), Vector3(3.0, 0.25, 2.4), color)
	b.box(_xf(Vector3(0, 1.8, 1.02)), Vector3(2.0, 0.8, 0.08), Palette.INK)
	return b.mesh()


static func _bus_shelter(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 1.8, 0)), Vector3(0.16, 3.6, 0.16), Palette.ASH)
	b.box(_xf(Vector3(-2.2, 1.8, 0)), Vector3(0.16, 3.6, 0.16), Palette.ASH)
	b.box(_xf(Vector3(-1.1, 3.55, 0)), Vector3(2.4, 0.18, 0.16), Palette.ASH)
	b.box(_xf(Vector3(-1.1, 1.7, -0.55)), Vector3(2.4, 1.8, 0.08), Palette.SKY.darkened(0.2))
	b.box(_xf(Vector3(-1.1, 0.7, 0.2)), Vector3(2.3, 0.3, 0.9), Palette.STONE)
	return b.mesh()


static func _subway_entrance(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 0.5, 0)), Vector3(8.0, 1.0, 4.0), Palette.STONE)
	b.box(_xf(Vector3(0, 1.45, -0.4)), Vector3(7.2, 1.0, 0.3), Palette.INK)
	for x in [-2.5, 0.0, 2.5]:
		b.box(_xf(Vector3(x, 1.6, 0.8)), Vector3(0.35, 2.2, 0.35), Palette.ASH)
	b.box(_xf(Vector3(0, 2.7, 0)), Vector3(8.4, 0.3, 4.4), Palette.PERIWINKLE)
	return b.mesh()


static func _road_sign(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(_xf(Vector3.ZERO), 0.08, 4.0, 5, Palette.ASH)
	var face: Color = [Palette.PERIWINKLE, Palette.MINT, Palette.BUTTER, Palette.CORAL][variant % 4]
	b.box(_xf(Vector3(0, 4.0, 0.1)), Vector3(2.4, 1.2, 0.1), face)
	b.box(_xf(Vector3(0, 4.0, 0.17)), Vector3(1.8, 0.14, 0.03), Palette.WHITE)
	b.box(_xf(Vector3(-0.3, 3.7, 0.17)), Vector3(1.0, 0.1, 0.03), Palette.WHITE)
	return b.mesh()


## A city bus on its side in the water, the roof and one flank above the surface.
static func _bus_wreck(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var tilt := 0.35
	b.box(_xf(Vector3(0, 0.9, 0), 0, 0, tilt), Vector3(2.5, 2.6, 11.0), Palette.CORAL)
	b.box(_xf(Vector3(0, 1.0, 0), 0, 0, tilt), Vector3(2.58, 0.4, 11.08), Palette.CREAM)
	for z in range(-4, 5, 2):
		b.box(_xf(Vector3(1.0, 1.7, float(z)), 0, 0, tilt), Vector3(0.1, 0.8, 1.2), Palette.SLATE)
	b.box(_xf(Vector3(0, 2.45, 0), 0, 0, tilt), Vector3(1.8, 0.2, 10.0), Palette.MIST)
	for z in [-3.6, 3.6]:
		b.prism(_xf(Vector3(-1.5, 0.5, z), 0, 0, PI * 0.5 + tilt), 0.55, 0.4, 8, Palette.INK)
	return b.mesh()


## A jersey-barrier line with a stripe, askew in the current.
static func _barricade(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	for i in 4:
		var xf := _xf(Vector3(i * 2.1 - 3.2, 0.5, i * 0.12), 0.1 * i)
		b.box(xf, Vector3(2.0, 1.0, 0.7), Palette.MIST)
		b.box(xf * Transform3D(Basis(), Vector3(0, 0.15, 0.36)), Vector3(1.9, 0.25, 0.03), Palette.CORAL)
	return b.mesh()


## Planks, drums and a tyre bobbing together on the surface.
static func _raft(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	for i in 4 + variant % 3:
		b.box(_xf(Vector3(rng.randf_range(-2, 2), 0.05, rng.randf_range(-1.5, 1.5)), rng.randf() * TAU), Vector3(rng.randf_range(2.0, 3.5), 0.12, 0.35), Palette.WOOD)
	for i in 1 + variant % 3:
		var c: Color = [Palette.CORAL, Palette.TEAL, Palette.BUTTER][i % 3]
		b.prism(_xf(Vector3(rng.randf_range(-1.5, 1.5), 0.0, rng.randf_range(-1.2, 1.2))), 0.4, 0.9, 8, c)
	b.prism(_xf(Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1))), 0.6, 0.25, 10, Palette.INK)
	b.box(_xf(Vector3(1.5, 0.1, 1.0), 0.6), Vector3(1.2, 0.5, 0.8), Palette.WHITE)
	return b.mesh()


static func _rubble(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	for i in 5 + variant % 4:
		var color: Color = [Palette.CONCRETE, Palette.STONE, Palette.ASH][i % 3]
		var r := rng.randf_range(0.6, 1.6)
		b.blob(_xf(Vector3(rng.randf_range(-2.5, 2.5), r * 0.2, rng.randf_range(-2.5, 2.5))), r, color, 0, 0.35, i + variant)
	b.box(_xf(Vector3(0.5, 1.0, -0.5), 0.5, 0.2, 0.3), Vector3(0.18, 2.2, 0.18), Palette.RED)
	return b.mesh()


## The roof of a drowned block breaking the surface: slab, parapet, stair hut, water tank and a few units.
static func _roof_island(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var w := rng.randf_range(10.0, 18.0)
	var l := rng.randf_range(8.0, 14.0)
	b.box(_xf(Vector3(0, 0.3, 0)), Vector3(w, 1.4, l), Palette.CONCRETE)
	for side in [-1.0, 1.0]:
		b.box(_xf(Vector3(side * (w * 0.5 - 0.15), 1.25, 0)), Vector3(0.3, 0.7, l), Palette.STONE)
		b.box(_xf(Vector3(0, 1.25, side * (l * 0.5 - 0.15))), Vector3(w, 0.7, 0.3), Palette.STONE)
	b.box(_xf(Vector3(-w * 0.25, 2.2, -l * 0.15)), Vector3(3.4, 2.4, 3.0), Palette.SLATE)
	b.box(_xf(Vector3(-w * 0.25, 3.5, -l * 0.15)), Vector3(3.8, 0.3, 3.4), Palette.ASH)
	b.prism(_xf(Vector3(w * 0.22, 1.0, l * 0.12)), 1.3, 2.2, 8, [Palette.TEAL, Palette.CORAL, Palette.BUTTER][variant % 3])
	for i in 2 + variant % 2:
		b.box(_xf(Vector3(rng.randf_range(-0.4, 0.4) * w, 1.3, rng.randf_range(-0.4, 0.4) * l), rng.randf() * TAU), Vector3(1.6, 0.9, 1.2), Palette.MIST)
	return b.mesh()


## The visible edge of an arena: a ring of buoys with a lamp on every fourth, just outside where the hull is held.
## variant 0 rings the plaza, 1 the bay, 2 the pit, 3 the clearing.
static func _arena_ring(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var radius: float = [Stage2.PLAZA_RADIUS, Stage2.BAY_RADIUS, Stage3.PIT_RADIUS, Stage4.CLEARING_RADIUS][variant] - ARENA_RING_INSET
	var count := int(TAU * radius / 5.0)
	for i in count:
		var angle := TAU * i / count
		var at := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		b.prism(_xf(at + Vector3(0, 0.3, 0)), 0.55, 1.3, 6, Palette.CORAL if i % 2 == 0 else Palette.CREAM, 0.35)
		if i % 4 == 0:
			b.box(_xf(at + Vector3(0, 1.9, 0)), Vector3(0.12, 2.6, 0.12), Palette.ASH)
			b.glow = true
			b.box(_xf(at + Vector3(0, 3.3, 0)), Vector3(0.45, 0.45, 0.45), Palette.BUTTER)
			b.glow = false
	return b.mesh()


## A road-wide gantry with the drowned route's signs.
static func _gantry(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	for x in [-14.5, 14.5]:
		b.box(_xf(Vector3(x, 4.5, 0)), Vector3(0.6, 9.0, 0.6), Palette.ASH)
	b.box(_xf(Vector3(0, 9.0, 0)), Vector3(30.0, 0.6, 0.6), Palette.ASH)
	b.box(_xf(Vector3(-6.0, 7.4, 0.35)), Vector3(8.0, 2.4, 0.15), Palette.MINT)
	b.box(_xf(Vector3(6.0, 7.4, 0.35)), Vector3(8.0, 2.4, 0.15), Palette.PERIWINKLE)
	for x in [-9.0, -6.0, -3.0, 3.0, 6.0, 9.0]:
		b.box(_xf(Vector3(x, 7.7, 0.45)), Vector3(2.0, 0.28, 0.04), Palette.WHITE)
		b.box(_xf(Vector3(x, 7.0, 0.45)), Vector3(1.2, 0.2, 0.04), Palette.WHITE)
	return b.mesh()


## Foam collar around a pier or a building base: a ring of pale flat quads on the water.
static func foam(size: Vector3) -> Array:
	var rects := []
	var margin := 1.2
	rects.append([Vector2(-size.x * 0.5 - margin, -size.z * 0.5 - margin), Vector2(size.x * 0.5 + margin, -size.z * 0.5)])
	rects.append([Vector2(-size.x * 0.5 - margin, size.z * 0.5), Vector2(size.x * 0.5 + margin, size.z * 0.5 + margin)])
	rects.append([Vector2(-size.x * 0.5 - margin, -size.z * 0.5), Vector2(-size.x * 0.5, size.z * 0.5)])
	rects.append([Vector2(size.x * 0.5, -size.z * 0.5), Vector2(size.x * 0.5 + margin, size.z * 0.5)])
	return rects


## A half-sunk bus terminal with a canopy and a readable terminal sign.
static func terminal(size: Vector3, variant: int) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, size.y * 0.5, 0)), size, Palette.CONCRETE)
	b.box(_xf(Vector3(0, size.y + 0.8, 0)), Vector3(size.x + 4.0, 1.0, size.z + 2.0), Palette.STONE)
	b.box(_xf(Vector3(0, size.y + 2.0, -size.z * 0.25)), Vector3(size.x * 0.75, 0.4, 0.3), Palette.CORAL)
	for x in [-size.x * 0.35, 0.0, size.x * 0.35]:
		b.box(_xf(Vector3(x, size.y * 0.5, size.z * 0.3)), Vector3(0.3, size.y, 0.3), Palette.ASH)
	b.box(_xf(Vector3(0, size.y * 0.72, size.z * 0.5 + 0.2)), Vector3(size.x * 0.7, 2.4, 0.12), Palette.INK)
	b.box(_xf(Vector3(0, size.y * 0.72, size.z * 0.58)), Vector3(size.x * 0.55, 0.2, 0.05), Palette.BUTTER)
	return b.mesh()


## A department store facade with a giant sign, distinct from a residential tower.
static func department(size: Vector3, variant: int) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, size.y * 0.5, 0)), size, FACADES[variant % FACADES.size()])
	b.box(_xf(Vector3(0, size.y * 0.86, size.z * 0.5 + 0.35)), Vector3(size.x * 0.9, 3.2, 0.18), Palette.CORAL)
	b.box(_xf(Vector3(0, size.y * 0.86, size.z * 0.48 + 0.46)), Vector3(size.x * 0.72, 1.4, 0.04), Palette.CREAM)
	for floor_index in range(1, int(size.y / 4.0)):
		b.box(_xf(Vector3(0, floor_index * 4.0, size.z * 0.5 + 0.08)), Vector3(size.x * 0.86, 0.2, 0.1), Palette.MIST)
	return b.mesh()


## Clock tower landmark at the plaza rim.
static func clock(size: Vector3, variant: int) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, size.y * 0.5, 0)), size, Palette.STONE)
	b.box(_xf(Vector3(0, size.y + 1.5, 0)), Vector3(size.x * 1.15, 3.0, size.z * 1.15), Palette.CONCRETE)
	for side in [-1.0, 1.0]:
		b.prism(_xf(Vector3(0, size.y + 1.6, side * (size.z * 0.58)), PI * 0.5), 1.8, 0.18, 12, Palette.INK)
	b.prism(_xf(Vector3(0, size.y + 3.5, 0)), 1.0, 3.0, 8, Palette.CORAL)
	return b.mesh()


## A canyon tower lying along the road; the collision box is the visible horizontal slab.
static func toppled(size: Vector3, variant: int) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, size.y * 0.5, 0)), size, Palette.CONCRETE)
	b.box(_xf(Vector3(0, size.y + 0.25, 0)), Vector3(size.x * 0.9, 0.25, size.z * 0.9), Palette.STONE)
	for z in range(-int(size.z * 0.4), int(size.z * 0.4), 5):
		b.box(_xf(Vector3(0, size.y + 0.4, float(z))), Vector3(size.x * 0.55, 0.2, 1.5), Palette.SLATE)
	for side in [-1.0, 1.0]:
		for z in range(-int(size.z * 0.35), int(size.z * 0.35), 5):
			b.box(_xf(Vector3(side * (size.x * 0.5 + 0.04), size.y * 0.55, float(z))), Vector3(0.08, 1.1, 1.8), Palette.INK)
	return b.mesh()


## A broken parallel-span mesh: the two ends sag toward a missing center section.
static func sag_span(size: Vector3, variant: int) -> Mesh:
	var b := LowPoly.new()
	var half := size.z * 0.5
	for piece in 2:
		var z := (-half * 0.62 if piece == 0 else half * 0.62)
		var length := half * 0.7
		var y := size.y * 0.55 - (0.55 if piece == 0 else 0.35)
		b.box(_xf(Vector3(0, y, z)), Vector3(size.x, 0.7, length), Palette.STONE)
		b.box(_xf(Vector3(0, y + 0.45, z)), Vector3(size.x + 0.5, 0.2, length), Palette.MIST)
		for side in [-1.0, 1.0]:
			b.box(_xf(Vector3(side * (size.x * 0.5 - 0.15), y + 0.65, z)), Vector3(0.25, 1.0, length), Palette.ASH)
	# Broken ends expose short lengths of rebar over the missing middle.
	for side in [-1.0, 1.0]:
		for z in [-half * 0.34, half * 0.34]:
			b.box(_xf(Vector3(side * 1.2, size.y * 0.35, z)), Vector3(0.12, 0.12, 2.2), Palette.CORAL)
	return b.mesh()


## A tower: size is the exact collision box. Facade, windows, ground-floor shops, waterline stain and roof clutter vary by variant.
## Towers come in four kinds by `variant % 4`: 0 offices, 1 apartment slabs, 2 offices hung with shop signs,
## 3 glass curtain walls.
static func tower(size: Vector3, variant: int) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([size, variant])
	if variant % 4 == 1:
		return _apartment(size, variant, rng)
	if variant % 4 == 3:
		return _glass(size, variant, rng)
	var b := LowPoly.new()
	var wall: Color = FACADES[variant % FACADES.size()]
	var trim: Color = wall.lightened(0.35)
	var dark: Color = wall.darkened(0.35)
	b.box(_xf(Vector3(0, size.y * 0.5, 0)), size, wall)
	var floors := int(size.y / 3.6)
	var style := variant % 3 # 0 punched windows, 1 ribbon strips, 2 tall slits
	var cols_x := maxi(2, int(size.x / 3.4))
	var cols_z := maxi(2, int(size.z / 3.4))
	# Vertical piers, floor bands and a cornice read as concrete frame, not a painted box.
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box(_xf(Vector3(sx * (size.x * 0.5 - 0.35), size.y * 0.5, sz * (size.z * 0.5 - 0.35))), Vector3(0.9, size.y + 0.1, 0.9), trim)
	for floor_index in range(2, floors, 3):
		b.box(_xf(Vector3(0, floor_index * 3.6, 0)), Vector3(size.x + 0.25, 0.3, size.z + 0.25), trim)
	b.box(_xf(Vector3(0, size.y + 0.3, 0)), Vector3(size.x + 0.8, 0.6, size.z + 0.8), trim)
	# Windows on all four faces: [face center, along-axis, outward sign, columns, face width]
	var faces := [
		[Vector3(0, 0, size.z * 0.5 + 0.02), Vector3.RIGHT, 1.0, cols_x, size.x],
		[Vector3(0, 0, -size.z * 0.5 - 0.02), Vector3.RIGHT, -1.0, cols_x, size.x],
		[Vector3(size.x * 0.5 + 0.02, 0, 0), Vector3.BACK, -1.0, cols_z, size.z],
		[Vector3(-size.x * 0.5 - 0.02, 0, 0), Vector3.BACK, 1.0, cols_z, size.z],
	]
	for face in faces:
		var columns: int = face[3]
		var width: float = face[4]
		for floor_index in range(1, floors):
			var y := 1.8 + floor_index * 3.6
			for c in columns:
				var offset := (float(c) + 0.5) / columns * (width - 3.0) - (width - 3.0) * 0.5
				var lit := rng.randf() < 0.18
				var out := rng.randf() < 0.05
				var color: Color = Palette.BUTTER if lit else (Palette.INK if out else Palette.SLATE)
				b.glow = lit
				var half := (0.55 if style == 2 else (1.3 if style == 1 else 0.85))
				var pos: Vector3 = face[0] + (face[1] as Vector3) * offset + Vector3(0, y, 0)
				_window(b, pos, (face[1] as Vector3) * half, color, face[0].normalized(), 0.55 if style == 2 else (0.4 if style == 1 else 0.85))
		b.glow = false
		# Ground floor: dark glass, a coloured awning and a flooded waterline stain.
		var awning: Color = AWNINGS[(variant + int(width)) % AWNINGS.size()]
		for c in columns:
			var offset := (float(c) + 0.5) / columns * (width - 3.0) - (width - 3.0) * 0.5
			var pos: Vector3 = face[0] + (face[1] as Vector3) * offset
			var out_dir := Vector3(face[0].x, 0, face[0].z).normalized()
			_window(b, pos + Vector3(0, 1.9, 0), (face[1] as Vector3) * 1.2, Palette.INK, out_dir, 1.0)
			b.box(Transform3D(Basis(), pos + Vector3(0, 3.0, 0) + out_dir * 0.7), (face[1] as Vector3).abs() * 2.8 + out_dir.abs() * 1.4 + Vector3(0, 0.12, 0), awning)
	b.box(_xf(Vector3(0, 0.8, 0)), Vector3(size.x * 1.01, 1.6, size.z * 1.01), dark)
	# A dark wet band marks the permanent second-floor waterline on every drowned tower.
	b.box(_xf(Vector3(0, 4.55, 0)), Vector3(size.x * 1.015, 0.42, size.z * 1.015), Palette.INK.darkened(0.25))
	# Roof clutter.
	b.box(_xf(Vector3(-size.x * 0.25, size.y + 1.1, -size.z * 0.2)), Vector3(4, 2.2, 3), Palette.SLATE)
	b.prism(_xf(Vector3(size.x * 0.2, size.y + 0.6, size.z * 0.25)), 1.4, 2.4, 8, Palette.TEAL)
	b.prism(_xf(Vector3(size.x * 0.2, size.y + 3.0, size.z * 0.25)), 1.6, 0.5, 8, Palette.STONE, 0.1)
	for leg in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		b.box(_xf(Vector3(size.x * 0.2 + leg.x, size.y + 1.4, size.z * 0.25 + leg.y)), Vector3(0.12, 2.8, 0.12), Palette.STONE)
	if variant % 2 == 0:
		b.box(_xf(Vector3(0, size.y + 4.5, 0)), Vector3(0.18, 8.0, 0.18), Palette.ASH)
		b.glow = true
		b.box(_xf(Vector3(0, size.y + 8.6, 0)), Vector3(0.4, 0.4, 0.4), Palette.HOT)
		b.glow = false
	else:
		b.box(_xf(Vector3(0, size.y + 3.0, size.z * 0.5 - 0.6)), Vector3(size.x * 0.5, 3.0, 0.3), Palette.CORAL if variant % 4 == 1 else Palette.PERIWINKLE)
		b.glow = true
		b.box(_xf(Vector3(0, size.y + 3.0, size.z * 0.5 - 0.4)), Vector3(size.x * 0.4, 1.6, 0.05), Palette.CREAM)
		b.glow = false
	# A scar of broken windows and bare concrete where something hit the corner.
	if variant % 3 != 1:
		var y := rng.randf_range(0.5, 0.8) * size.y
		b.box(_xf(Vector3(size.x * 0.5 - 0.1, y, size.z * 0.3)), Vector3(0.3, 5.0, 4.0), dark)
	if variant % 4 == 2:
		_shop_signs(b, size, rng)
	return b.mesh()


## A tower the jungle has taken: vines hang down its faces, strangler roots buttress the corners, and ferns and a
## crown of foliage grow on the ledges and the roof.
static func overgrown(size: Vector3, variant: int) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([size, variant, "overgrown"])
	var b := LowPoly.new()
	var greens: Array[Color] = [Palette.MOSS, Palette.PINE, Palette.LEAF, Palette.SAGE]
	for face: Vector3 in [Vector3(size.x * 0.5, 0, 0), Vector3(-size.x * 0.5, 0, 0), Vector3(0, 0, size.z * 0.5), Vector3(0, 0, -size.z * 0.5)]:
		var wide: bool = face.x == 0.0
		for _curtain in 3 + int(size.y / 14.0): # Sheets of creeper that swallow whole bays of the facade.
			var reach := rng.randf_range(0.4, 1.0) * size.y
			var offset := rng.randf_range(-0.4, 0.4) * (size.x if wide else size.z)
			var sheet := rng.randf_range(2.5, 6.0)
			var centre: Vector3 = face + (Vector3(offset, 0, 0) if wide else Vector3(0, 0, offset)) + Vector3(0, size.y - reach * 0.5, 0)
			var thickness := Vector3(sheet if wide else 0.5, reach, 0.5 if wide else sheet)
			b.box(_xf(centre), thickness + face.abs().normalized() * 0.2, greens[rng.randi() % 2])
		for strand in 4 + int(size.x * size.z / 150.0):
			var length := rng.randf_range(0.35, 0.95) * size.y
			var offset := rng.randf_range(-0.45, 0.45) * (size.x if wide else size.z)
			var at: Vector3 = face + (Vector3(offset, 0, 0) if wide else Vector3(0, 0, offset))
			b.box(_xf(at + Vector3(0, size.y - length * 0.5, 0)), Vector3(0.3, length, 0.3) + face.abs().normalized() * 0.25, greens[rng.randi() % 4])
			b.blob(_xf(at + Vector3(0, size.y - length, 0)), rng.randf_range(0.7, 1.4), greens[rng.randi() % 4], 0, 0.3, rng.randi())
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		b.blob(_xf(Vector3(corner.x * size.x * 0.5, 1.5, corner.y * size.z * 0.5)), rng.randf_range(2.0, 3.0), Palette.WOOD.lerp(Palette.MOSS, 0.4), 0, 0.35, rng.randi())
	for i in 10 + int((size.x + size.z) * 0.5): # A thicket around the foot that climbs the ground floor.
		var angle := TAU * i / float(10 + int((size.x + size.z) * 0.5)) + rng.randf_range(-0.2, 0.2)
		b.blob(_xf(Vector3(cos(angle) * size.x * 0.58, rng.randf_range(0.5, 3.5), sin(angle) * size.z * 0.58)), rng.randf_range(1.8, 3.4), greens[rng.randi() % 2], 0, 0.35, rng.randi())
	for i in 4 + int(size.x * size.z / 200.0):
		b.blob(_xf(Vector3(rng.randf_range(-0.45, 0.45) * size.x, size.y + rng.randf_range(0.2, 1.4), rng.randf_range(-0.45, 0.45) * size.z)), rng.randf_range(1.5, 3.0), greens[rng.randi() % 4], 0, 0.3, rng.randi())
	var merged := ArrayMesh.new()
	for source: Mesh in [tower(size, variant), b.mesh()]:
		for surface in source.get_surface_count():
			merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(surface))
			merged.surface_set_material(merged.get_surface_count() - 1, source.surface_get_material(surface))
	return merged


## Floors just above the waterline crowded with Korean shop signs on both long faces, plus a vertical sign
## standing out from one corner.
static func _shop_signs(b: LowPoly, size: Vector3, rng: RandomNumberGenerator) -> void:
	for side in [-1.0, 1.0]:
		var x: float = side * (size.x * 0.5 + 0.12)
		for row in 3:
			var y := 5.6 + row * 3.6
			var z := -size.z * 0.5 + rng.randf_range(0.4, 1.5)
			while z < size.z * 0.5 - 2.5:
				var width := minf(rng.randf_range(2.5, 7.0), size.z * 0.5 - 0.6 - z)
				var height := rng.randf_range(1.3, 2.3)
				var color: Color = SIGNS[rng.randi() % SIGNS.size()]
				b.glow = rng.randf() < 0.3
				b.box(_xf(Vector3(x, y, z + width * 0.5)), Vector3(0.2, height, width), color)
				b.glow = false
				_glyphs(b, Vector3(x + side * 0.12, y, z + width * 0.5), Vector3.BACK, Vector3(side, 0, 0), width - 0.6, height * 0.62, Palette.INK if color.get_luminance() > 0.6 else Palette.WHITE, rng)
				z += width + rng.randf_range(0.2, 1.5)
		var corner_z: float = rng.randf_range(-0.4, 0.4) * size.z
		var color: Color = SIGNS[rng.randi() % SIGNS.size()]
		var at := Vector3(side * (size.x * 0.5 + 0.9), 11.0, corner_z)
		b.glow = true
		b.box(_xf(at), Vector3(1.6, 8.0, 0.35), color)
		b.glow = false
		for i in 4:
			_glyphs(b, at + Vector3(0, 2.7 - i * 1.8, -0.2), Vector3.RIGHT, Vector3.FORWARD, 1.1, 1.1, Palette.INK if color.get_luminance() > 0.6 else Palette.WHITE, rng, 1)


## Hangul-like syllable blocks across a sign: an initial, a vowel stroke and sometimes a final. `along` runs
## across the sign, `out` faces the viewer.
static func _glyphs(b: LowPoly, center: Vector3, along: Vector3, out: Vector3, width: float, height: float, color: Color, rng: RandomNumberGenerator, count := 0) -> void:
	var n := count if count > 0 else clampi(int(width / height), 1, 5)
	var cell := minf(width / n, height)
	for i in n:
		var c := center + along * ((i + 0.5) * cell - n * cell * 0.5)
		var depth := out.abs() * 0.04
		var final := rng.randf() < 0.5
		var top := 0.18 if final else 0.0
		b.box(Transform3D(Basis(), c + along * (-cell * 0.12) + Vector3.UP * (cell * top)), along.abs() * cell * 0.38 + Vector3.UP * cell * 0.36 + depth, color)
		b.box(Transform3D(Basis(), c + along * (cell * 0.22) + Vector3.UP * (cell * top * 0.5)), along.abs() * cell * 0.1 + Vector3.UP * cell * (0.7 - top) + depth, color)
		if final:
			b.box(Transform3D(Basis(), c + Vector3.UP * (-cell * 0.3)), along.abs() * cell * 0.62 + Vector3.UP * cell * 0.1 + depth, color)


## A Korean apartment slab: balcony bands on every floor of the long faces, the block number painted large on
## both gable ends under a brand stripe, and lift housings on the roof.
static func _apartment(size: Vector3, variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var wall: Color = [Palette.CREAM, Palette.WHITE, Palette.MIST, Palette.PEACH][variant / 4 % 4]
	var accent: Color = [Palette.CORAL, Palette.TEAL, Palette.PERIWINKLE, Palette.MAUVE][variant / 4 % 4]
	b.box(_xf(Vector3(0, size.y * 0.5, 0)), size, wall)
	var floors := int(size.y / 2.8)
	for floor_index in range(2, floors):
		var y := floor_index * 2.8
		for side in [-1.0, 1.0]:
			b.box(_xf(Vector3(side * (size.x * 0.5 + 0.35), y + 0.5, 0)), Vector3(0.7, 1.0, size.z - 1.0), wall.lightened(0.3))
			var lit := rng.randf() < 0.25
			b.glow = lit
			b.box(_xf(Vector3(side * (size.x * 0.5 + 0.03), y + 1.75, 0)), Vector3(0.08, 1.4, size.z - 1.4), Palette.BUTTER if lit else Palette.SLATE)
			b.glow = false
			for k in range(1, int(size.z / 6.0)):
				b.box(_xf(Vector3(side * (size.x * 0.5 + 0.36), y + 1.3, -size.z * 0.5 + k * 6.0)), Vector3(0.72, 2.6, 0.25), wall.darkened(0.12))
	var number := 101 + variant % 9
	for side in [-1.0, 1.0]:
		var z: float = side * (size.z * 0.5 + 0.06)
		b.box(_xf(Vector3(0, size.y - 3.5, z)), Vector3(size.x, 2.2, 0.06), accent)
		var digits := str(number)
		for i in digits.length():
			var x: float = (i - 1) * 2.6 * side
			_digit(b, Vector3(x, size.y - 9.5, z + side * 0.04), Vector3(side, 0, 0), int(digits[i]), 3.6, Palette.DUSK)
	b.box(_xf(Vector3(0, 0.8, 0)), Vector3(size.x * 1.01, 1.6, size.z * 1.01), wall.darkened(0.4))
	b.box(_xf(Vector3(0, 4.55, 0)), Vector3(size.x * 1.015, 0.42, size.z * 1.015), Palette.INK.darkened(0.25))
	b.box(_xf(Vector3(0, size.y + 0.25, 0)), Vector3(size.x + 0.3, 0.5, size.z + 0.3), wall.darkened(0.15))
	for z in [-size.z * 0.25, size.z * 0.25]:
		b.box(_xf(Vector3(0, size.y + 1.6, z)), Vector3(4.0, 2.7, 3.0), wall.darkened(0.08))
	return b.mesh()


## A seven-segment digit `height` tall centred on `at`, drawn toward `right` on a face.
static func _digit(b: LowPoly, at: Vector3, right: Vector3, value: int, height: float, color: Color) -> void:
	var w := height * 0.5
	var t := height * 0.12
	var bars := [[Vector2(0, 0.5), true], [Vector2(0.5, 0.25), false], [Vector2(0.5, -0.25), false], [Vector2(0, -0.5), true], [Vector2(-0.5, -0.25), false], [Vector2(-0.5, 0.25), false], [Vector2(0, 0), true]]
	var depth := Vector3(absf(right.z), 0, absf(right.x)) * 0.06
	for i in 7:
		if SEGMENTS[value][i] != "1":
			continue
		var spot: Vector2 = bars[i][0]
		var across: bool = bars[i][1]
		var size: Vector3 = right.abs() * (w if across else t) + Vector3.UP * (t if across else height * 0.5) + depth
		b.box(Transform3D(Basis(), at + right * (spot.x * w) + Vector3.UP * (spot.y * height)), size, color)


## A glass curtain-wall tower: tinted glass on a mullion grid, a set-back crown and a mast.
static func _glass(size: Vector3, variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var glass: Color = [Palette.SKY, Palette.TEAL, Palette.PERIWINKLE, Palette.MINT][variant / 4 % 4]
	b.box(_xf(Vector3(0, size.y * 0.5, 0)), size, glass)
	var frame := glass.darkened(0.35)
	for y in range(1, int(size.y / 3.6)):
		b.box(_xf(Vector3(0, y * 3.6, 0)), Vector3(size.x + 0.12, 0.14, size.z + 0.12), frame)
	for axis in [0, 2]:
		var width: float = size.z if axis == 0 else size.x
		for k in range(1, int(width / 2.4)):
			var offset := -width * 0.5 + k * 2.4
			var at := Vector3(0, size.y * 0.5, offset) if axis == 0 else Vector3(offset, size.y * 0.5, 0)
			b.box(_xf(at), Vector3(size.x + 0.12, size.y, 0.12) if axis == 0 else Vector3(0.12, size.y, size.z + 0.12), frame)
	b.glow = true
	for i in 10:
		var y := rng.randf_range(6.0, size.y - 3.0)
		var z := rng.randf_range(-0.4, 0.4) * size.z
		b.box(_xf(Vector3(signf(rng.randf() - 0.5) * (size.x * 0.5 + 0.08), y, z)), Vector3(0.05, 1.2, 2.0), Palette.BUTTER)
	b.glow = false
	b.box(_xf(Vector3(0, 0.8, 0)), Vector3(size.x * 1.01, 1.6, size.z * 1.01), frame.darkened(0.3))
	b.box(_xf(Vector3(0, 4.55, 0)), Vector3(size.x * 1.015, 0.42, size.z * 1.015), Palette.INK.darkened(0.25))
	b.box(_xf(Vector3(0, size.y + 2.0, 0)), Vector3(size.x * 0.7, 4.0, size.z * 0.7), frame)
	b.box(_xf(Vector3(0, size.y + 4.2, 0)), Vector3(size.x * 0.72, 0.4, size.z * 0.72), glass.lightened(0.3))
	b.box(_xf(Vector3(0, size.y + 9.0, 0)), Vector3(0.25, 10.0, 0.25), Palette.ASH)
	b.glow = true
	b.box(_xf(Vector3(0, size.y + 14.1, 0)), Vector3(0.45, 0.45, 0.45), Palette.HOT)
	b.glow = false
	return b.mesh()


## A gutted tower: size is the collision box. Each bay of the block keeps a few storeys of wall, and above them
## only its concrete skeleton stands, columns and bare floor slabs, to a different height per bay; the top slabs hang
## tipped where the rest came down, with rebar sticking out.
static func ruin(size: Vector3, variant: int) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([size, variant, "ruin"])
	var b := LowPoly.new()
	var wall: Color = (FACADES[variant % FACADES.size()] as Color).lerp(Palette.CONCRETE, 0.5).darkened(0.12)
	var cells := Vector2i(2, maxi(2, int(size.z / 9.0)))
	var cell := Vector2(size.x / cells.x, size.z / cells.y)
	var tallest := rng.randi_range(0, cells.x * cells.y - 1)
	for i in cells.x * cells.y:
		var at := Vector2(-size.x * 0.5 + cell.x * (i % cells.x + 0.5), -size.z * 0.5 + cell.y * (i / cells.x + 0.5))
		var h := size.y if i == tallest else size.y * rng.randf_range(0.2, 0.9)
		var shell := minf(h, maxf(7.2, size.y * rng.randf_range(0.15, 0.45))) # Storeys that keep their walls.
		b.box(_xf(Vector3(at.x, shell * 0.5, at.y)), Vector3(cell.x, shell, cell.y), wall)
		for f in range(1, int(shell / 3.6)):
			b.box(_xf(Vector3(at.x, f * 3.6 + 1.6, at.y)), Vector3(cell.x + 0.06, 1.3, cell.y + 0.06), Palette.INK)
		if h <= shell + 1.0:
			continue
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var column := h - rng.randf_range(0.0, 3.6) if rng.randf() < 0.75 else shell + rng.randf_range(1.0, 4.0)
			b.box(_xf(Vector3(at.x + corner.x * (cell.x * 0.5 - 0.5), (shell + column) * 0.5, at.y + corner.y * (cell.y * 0.5 - 0.5))), Vector3(0.8, column - shell, 0.8), Palette.STONE)
		var floors := int((h - shell) / 3.6)
		for f in range(1, floors + 1):
			if rng.randf() < 0.2 and f < floors:
				continue # A slab that fell through.
			var top := f == floors
			var tip := rng.randf_range(0.15, 0.45) * (1.0 if rng.randf() < 0.5 else -1.0) if top else 0.0
			b.box(_xf(Vector3(at.x, shell + f * 3.6, at.y), 0.0, tip, rng.randf_range(-0.08, 0.08)), Vector3(cell.x + 0.4, 0.35, cell.y + 0.4), Palette.CONCRETE)
		for k in 3:
			var p := Vector3(at.x + rng.randf_range(-0.45, 0.45) * cell.x, h + 1.0, at.y + rng.randf_range(-0.45, 0.45) * cell.y)
			b.box(_xf(p, 0.0, rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5)), Vector3(0.15, 2.4, 0.15), Palette.CORAL.darkened(0.35))
	b.box(_xf(Vector3(0, 4.55, 0)), Vector3(size.x * 1.015, 0.42, size.z * 1.015), Palette.INK.darkened(0.25))
	return b.mesh()


## A shipping container: corrugated sides, door end and a painted stripe; the colour varies.
static func container(size: Vector3, variant: int) -> Mesh:
	var b := LowPoly.new()
	var color: Color = [Palette.CORAL, Palette.TEAL, Palette.BUTTER, Palette.PERIWINKLE, Palette.MINT, Palette.LILAC][variant % 6]
	b.box(_xf(Vector3(0, size.y * 0.5, 0)), size, color)
	var along_x := size.x >= size.z
	var length := size.x if along_x else size.z
	for i in range(-int(length * 0.5) + 1, int(length * 0.5), 1):
		for side in [-1.0, 1.0]:
			var at := Vector3(float(i), size.y * 0.5, side * (size.z * 0.5 + 0.03)) if along_x else Vector3(side * (size.x * 0.5 + 0.03), size.y * 0.5, float(i))
			b.box(_xf(at), Vector3(0.14, size.y - 0.3, 0.06) if along_x else Vector3(0.06, size.y - 0.3, 0.14), color.darkened(0.2))
	b.box(_xf(Vector3(0, size.y + 0.03, 0)), Vector3(size.x - 0.4, 0.06, size.z - 0.4), color.lightened(0.2))
	return b.mesh()


## A grounded freighter: hull, deck cargo, bridge house, funnel and a derrick; long axis along x.
static func ship(size: Vector3, variant: int) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, size.y * 0.5, 0)), size, Palette.SLATE)
	b.box(_xf(Vector3(0, size.y * 0.5 - size.y * 0.12, 0)), Vector3(size.x + 0.1, size.y * 0.3, size.z + 0.1), Palette.CORAL.darkened(0.2))
	b.box(_xf(Vector3(0, size.y + 0.1, 0)), Vector3(size.x - 1.0, 0.2, size.z - 1.0), Palette.ASH)
	for i in 5:
		var color: Color = [Palette.CORAL, Palette.TEAL, Palette.BUTTER, Palette.PERIWINKLE, Palette.MINT][(i + variant) % 5]
		b.box(_xf(Vector3(-size.x * 0.4 + i * 6.0, size.y + 1.5, 0)), Vector3(5.2, 2.8, size.z - 3.0), color)
	b.box(_xf(Vector3(size.x * 0.34, size.y + 4.0, 0)), Vector3(8.0, 8.0, size.z - 4.0), Palette.WHITE)
	for r in 3:
		b.glow = r == 1
		b.box(_xf(Vector3(size.x * 0.34, size.y + 2.4 + r * 2.2, 0)), Vector3(8.1, 0.9, size.z - 3.0), Palette.INK if r != 1 else Palette.BUTTER)
	b.glow = false
	b.prism(_xf(Vector3(size.x * 0.34 + 2.0, size.y + 8.0, 0)), 1.3, 3.5, 8, Palette.RED, 1.0)
	b.box(_xf(Vector3(-size.x * 0.1, size.y + 6.0, 0)), Vector3(0.5, 10.0, 0.5), Palette.ASH)
	b.box(_xf(Vector3(-size.x * 0.1 - 5.0, size.y + 11.0, 0), 0, 0, 0.6), Vector3(12.0, 0.3, 0.3), Palette.ASH)
	return b.mesh()


## A quay crane: legs, boom and a hanging spreader, for the harbour skyline.
static func _crane(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	for x in [-6.0, 6.0]:
		for z in [-5.0, 5.0]:
			b.box(_xf(Vector3(x, 14.0, z)), Vector3(1.0, 28.0, 1.0), Palette.CORAL)
	b.box(_xf(Vector3(0, 28.5, 0)), Vector3(14.0, 1.4, 12.0), Palette.CORAL)
	b.box(_xf(Vector3(0, 32.0, 0), 0, 0.0), Vector3(2.0, 7.0, 2.0), Palette.CORAL)
	b.box(_xf(Vector3(0, 30.5, -18.0)), Vector3(1.6, 1.6, 52.0), Palette.CREAM)
	b.box(_xf(Vector3(0, 21.0, -26.0)), Vector3(2.4, 0.5, 5.0), Palette.INK)
	b.box(_xf(Vector3(0, 25.8, -26.0)), Vector3(0.1, 9.5, 0.1), Palette.INK)
	b.glow = true
	b.box(_xf(Vector3(0, 34.0, 0)), Vector3(0.6, 0.6, 0.6), Palette.HOT)
	return b.mesh()


## Distant skyline for one chunk of street: plain blocks with floor bands, a roof box and a few lit ribbons, no per-window
## geometry. Each block is {"x": across, "z": along (local -Z is forward), "size", "variant"}; y = 0 is the block's base.
static func backdrop(blocks: Array, green := false) -> Mesh:
	var b := LowPoly.new()
	for block: Dictionary in blocks:
		var size: Vector3 = block.size
		var variant: int = block.variant
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([block.x, block.z, size, variant])
		var wall: Color = FACADES[variant % FACADES.size()]
		if green: # Overgrown skyline: the facades sit in deep green and creeper hangs off every storey.
			wall = wall.lerp(Palette.MOSS, 0.6)
		var at := Vector3(block.x, 0.0, block.z)
		b.box(_xf(at + Vector3(0, size.y * 0.5, 0)), size, wall)
		if green:
			for i in 3 + int(size.y / 14.0):
				var sheet := rng.randf_range(3.0, 7.0)
				var reach := rng.randf_range(0.4, 0.95) * size.y
				b.box(_xf(at + Vector3(-signf(block.x) * (size.x * 0.5 + 0.2), size.y - reach * 0.5, rng.randf_range(-0.4, 0.4) * size.z)), Vector3(0.6, reach, sheet), [Palette.MOSS, Palette.PINE, Palette.MOSS, Palette.LEAF][i % 4])
			for i in 6:
				b.blob(_xf(at + Vector3(rng.randf_range(-0.5, 0.5) * size.x, size.y + rng.randf_range(0.0, 1.5), rng.randf_range(-0.5, 0.5) * size.z)), rng.randf_range(2.0, 4.0), [Palette.PINE, Palette.MOSS][i % 2], 0, 0.3, rng.randi())
		for band in 2 + variant % 2:
			b.box(_xf(at + Vector3(0, size.y * (0.4 + 0.22 * band), 0)), Vector3(size.x + 0.5, 0.6, size.z + 0.5), wall.lightened(0.3))
		b.box(_xf(at + Vector3(-size.x * 0.1, size.y + 1.25, 0)), Vector3(size.x * 0.45, 2.5, size.z * 0.4), Palette.SLATE)
		# Dark window strips on the face toward the street read as storeys instead of a bare slab.
		var toward := -signf(block.x)
		for strip in int(size.y / 6.0) - 1:
			b.box(_xf(at + Vector3(toward * (size.x * 0.5 + 0.05), 7.0 + strip * 6.0, 0)), Vector3(0.12, 2.2, size.z - 3.0), Palette.SLATE)
		b.glow = true
		for face in [Vector3(size.x * 0.5, 0, 0), Vector3(-size.x * 0.5, 0, 0), Vector3(0, 0, size.z * 0.5), Vector3(0, 0, -size.z * 0.5)]:
			if rng.randf() < 0.6:
				var ribbon := Vector3(0.1, 1.0, size.z * 0.5) if face.x != 0.0 else Vector3(size.x * 0.5, 1.0, 0.1)
				b.box(_xf(at + face + Vector3(0, size.y * rng.randf_range(0.3, 0.9), 0)), ribbon, Palette.BUTTER)
		b.glow = false
	return b.mesh()


## One bay of a subway tunnel's roof: a sand-skinned slab over a slate soffit with a dark rib at each end and two rows of
## lamps every 10 m (the floor's pools of light lie under them). `size` is the exact collision box, its base at the soffit.
static func tunnel_roof(size: Vector3, _variant: int) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, size.y * 0.5, 0)), size, Palette.SLATE, Palette.PEACH)
	for z in [-size.z * 0.5 + 0.5, size.z * 0.5 - 0.5]:
		b.box(_xf(Vector3(0, -0.45, z)), Vector3(size.x, 0.9, 1.0), Palette.DUSK)
	b.glow = true
	for x in [-size.x * 0.22, size.x * 0.22]:
		for z in [-10.0, 0.0, 10.0]:
			b.box(_xf(Vector3(x, -0.12, z)), Vector3(1.1, 0.2, 3.2), Palette.CREAM)
	b.glow = false
	return b.mesh()


## One bay of a tunnel wall: light glazed tiles with grout lines up to a teal line stripe, plaster above and a lamp.
## Variant 0 is the wall on the right of the road (its inside faces -X), 1 the left.
static func tunnel_wall(size: Vector3, variant: int) -> Mesh:
	var b := LowPoly.new()
	var inside := -1.0 if variant == 0 else 1.0
	var face := inside * (size.x * 0.5 + 0.03)
	b.box(_xf(Vector3(0, size.y * 0.5, 0)), size, Palette.STONE)
	b.box(_xf(Vector3(face, 1.7, 0)), Vector3(0.1, 3.4, size.z), Palette.MIST)
	b.box(_xf(Vector3(face, 3.7, 0)), Vector3(0.12, 0.7, size.z), Palette.TEAL)
	b.box(_xf(Vector3(face, 6.8, 0)), Vector3(0.1, 5.4, size.z), Palette.MIST)
	for z in range(-int(size.z * 0.5) + 3, int(size.z * 0.5), 3):
		b.box(_xf(Vector3(face + inside * 0.03, size.y * 0.5, float(z))), Vector3(0.06, size.y - 1.0, 0.08), Palette.ASH)
	b.glow = true
	for z in [-10.0, 0.0, 10.0]:
		b.box(_xf(Vector3(face + inside * 0.1, 8.4, z)), Vector3(0.2, 0.5, 1.6), Palette.AMBER)
	return b.mesh()


## The mouth of the tunnel: a lintel over the lanes on two piers, hazard-striped, with a lit sign board.
static func _tunnel_portal(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var half: float = Stage3.TUNNEL_HALF + Stage3.HULL_MARGIN + 3.0
	for side in [-1.0, 1.0]:
		b.box(_xf(Vector3(side * half, 5.5, 0)), Vector3(3.0, 11.0, 4.0), Palette.CONCRETE)
	b.box(_xf(Vector3(0, 11.0, 0)), Vector3(half * 2.0 + 3.0, 2.2, 4.0), Palette.CONCRETE)
	for i in 10:
		b.box(_xf(Vector3(-half + 1.5 + i * (half * 2.0 - 3.0) / 9.0, 11.0, 2.02)), Vector3(2.0, 1.6, 0.06), Palette.AMBER if i % 2 == 0 else Palette.INK)
	b.box(_xf(Vector3(0, 14.0, 0)), Vector3(18.0, 3.0, 0.5), Palette.INK)
	b.glow = true
	b.box(_xf(Vector3(0, 14.0, 0.3)), Vector3(15.0, 1.2, 0.1), Palette.CYAN)
	return b.mesh()


static func _window(b: LowPoly, center: Vector3, half_width: Vector3, color: Color, outward: Vector3, half_height: float) -> void:
	var up := Vector3.UP * half_height
	var a := center - half_width - up
	var c := center + half_width - up
	var e := center + half_width + up
	var f := center - half_width + up
	b.tri(a, c, e, color, outward)
	b.tri(a, e, f, color, outward)
