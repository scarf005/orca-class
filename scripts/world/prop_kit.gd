class_name PropKit
## Low-poly meshes for the stage's scenery, cached by kind and variant.

const ROOF_COLORS: Array[Color] = [Palette.PERIWINKLE, Palette.CORAL, Palette.TEAL, Palette.MINT, Palette.SKY, Palette.MAUVE]
const WALL_COLORS: Array[Color] = [Palette.CREAM, Palette.MIST, Palette.CONCRETE, Palette.PEACH, Palette.BUTTER]
const CAR_COLORS: Array[Color] = [Palette.SKY, Palette.BLUSH, Palette.BUTTER, Palette.MIST, Palette.MINT]

static var _cache := {}


static func mesh(kind: String, variant := 0) -> Mesh:
	var key := "%s:%d" % [kind, variant]
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		_cache[key] = Callable(PropKit, kind).call(variant, rng)
	return _cache[key]


static func _xf(pos: Vector3, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)


static func house(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var wall := WALL_COLORS[variant % WALL_COLORS.size()]
	var roof := ROOF_COLORS[variant % ROOF_COLORS.size()]
	var w := rng.randf_range(7.0, 9.0)
	var d := rng.randf_range(5.0, 6.0)
	b.box(_xf(Vector3(0, 0.3, 0)), Vector3(w + 0.3, 0.6, d + 0.3), Palette.STONE)
	b.box(_xf(Vector3(0, 1.8, 0)), Vector3(w, 2.6, d), wall)
	b.gable(_xf(Vector3(0, 3.1, 0)), Vector3(w + 1.2, 1.7, d + 1.4), roof, wall)
	# Front porch (마루), door and windows.
	b.box(_xf(Vector3(0, 0.75, d * 0.5 + 0.6)), Vector3(w * 0.6, 0.2, 1.2), Palette.WOOD)
	b.box(_xf(Vector3(-w * 0.15, 1.5, d * 0.5 + 0.01)), Vector3(1.1, 2.0, 0.05), Palette.WOOD)
	for x in [w * 0.2, w * 0.36]:
		b.box(_xf(Vector3(x, 1.9, d * 0.5 + 0.01)), Vector3(1.0, 0.9, 0.05), Palette.DUSK)
	b.box(_xf(Vector3(-w * 0.35, 1.9, -d * 0.5 - 0.01)), Vector3(1.2, 0.8, 0.05), Palette.DUSK)
	if variant % 3 == 0:
		# ㄱ-shaped wing.
		b.box(_xf(Vector3(w * 0.5 + 1.5, 1.6, d * 0.2)), Vector3(3.0, 2.2, d * 0.7), wall)
		b.gable(_xf(Vector3(w * 0.5 + 1.5, 2.7, d * 0.2), PI * 0.5), Vector3(d * 0.7 + 0.8, 1.2, 3.8), roof, wall)
	# Chimney and a satellite dish.
	b.box(_xf(Vector3(w * 0.3, 4.3, -d * 0.2)), Vector3(0.5, 1.4, 0.5), Palette.STONE)
	b.prism(Transform3D(Basis(Vector3.RIGHT, 1.2), Vector3(-w * 0.4, 3.3, d * 0.5 + 0.3)), 0.45, 0.1, 6, Palette.WHITE)
	return b.mesh()


static func rubble(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var colors := [Palette.STONE, Palette.CONCRETE, Palette.WOOD, ROOF_COLORS[variant % ROOF_COLORS.size()]]
	for i in 9:
		var p := Vector3(rng.randf_range(-3, 3), rng.randf_range(0.0, 0.6), rng.randf_range(-2.5, 2.5))
		b.box(Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5))), p), Vector3(rng.randf_range(0.8, 2.5), rng.randf_range(0.3, 1.0), rng.randf_range(0.8, 2.0)), colors[i % colors.size()])
	return b.mesh()


static func wall(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 0.8, 0)), Vector3(6.0, 1.6, 0.25), WALL_COLORS[(variant + 2) % WALL_COLORS.size()])
	b.box(_xf(Vector3(0, 1.65, 0)), Vector3(6.2, 0.12, 0.4), Palette.STONE)
	return b.mesh()


static func jars(_variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 0.2, 0)), Vector3(3.2, 0.4, 2.2), Palette.STONE)
	for i in 7:
		var p := Vector3(-1.1 + (i % 4) * 0.72, 0.4, -0.5 + (i / 4) * 0.9)
		var s := rng.randf_range(0.8, 1.15)
		b.prism(_xf(p), 0.22 * s, 0.25 * s, 7, Palette.WOOD, 0.36 * s)
		b.prism(_xf(p + Vector3(0, 0.25 * s, 0)), 0.36 * s, 0.35 * s, 7, Palette.WOOD, 0.24 * s)
		b.prism(_xf(p + Vector3(0, 0.6 * s, 0)), 0.26 * s, 0.07, 7, Palette.INK, 0.2 * s)
	return b.mesh()


static func greenhouse(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var length := 16.0
	var r := 3.0
	var steps := 5
	for i in steps:
		var a0 := PI * i / steps
		var a1 := PI * (i + 1) / steps
		var p0 := Vector3(cos(a0) * r, sin(a0) * r * 0.9, 0)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r * 0.9, 0)
		var z := Vector3(0, 0, length * 0.5)
		var color := Palette.MIST if (i + variant) % 2 == 0 else Palette.WHITE
		b.quad(p0 - z, p1 - z, p1 + z, p0 + z, color, (p0 + p1) * 0.5)
		b.tri(Vector3.ZERO - z, p0 - z, p1 - z, Palette.MIST, Vector3.BACK * -1)
		b.tri(Vector3.ZERO + z, p0 + z, p1 + z, Palette.MIST, Vector3.BACK)
	# Ribs and a torn flap.
	for k in 5:
		var zc := -length * 0.5 + k * length / 4.0
		b.box(_xf(Vector3(0, r * 0.9 + 0.02, zc)), Vector3(0.6, 0.06, 0.1), Palette.STONE)
	# Fungus bursting out of the side.
	for i in 3:
		b.blob(_xf(Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(0.5, 1.5), rng.randf_range(-6, 6))), rng.randf_range(0.8, 1.5), Palette.FUNGUS if i % 2 == 0 else Palette.LILAC, 0, 0.35, i)
	return b.mesh()


static func pole(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(), 0.18, 10.0, 6, Palette.CONCRETE, 0.13)
	b.box(_xf(Vector3(0, 9.2, 0)), Vector3(2.4, 0.14, 0.14), Palette.STONE)
	b.prism(_xf(Vector3(0.4, 7.4, 0.3)), 0.3, 0.9, 6, Palette.ASH)
	for x in [-1.0, 0.0, 1.0]:
		b.prism(_xf(Vector3(x, 9.27, 0)), 0.06, 0.2, 4, Palette.WHITE)
	return b.mesh()


static func persimmon(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.15, 0.15)), Vector3.ZERO), 0.25, 2.6, 5, Palette.WOOD, 0.16)
	for i in 4:
		var p := Vector3(rng.randf_range(-1.4, 1.4), rng.randf_range(2.6, 3.8), rng.randf_range(-1.4, 1.4))
		b.blob(_xf(p), rng.randf_range(1.1, 1.7), Palette.PINE if (i + variant) % 3 else Palette.SAGE, 0, 0.3, i + variant)
	b.glow = true
	for i in 9:
		var p := Vector3(rng.randf_range(-2.0, 2.0), rng.randf_range(2.2, 4.4), rng.randf_range(-2.0, 2.0))
		b.blob(_xf(p), 0.2, Palette.PEACH if i % 2 else Palette.CORAL, 0)
	return b.mesh()


static func zelkova(_variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(), 1.1, 5.0, 7, Palette.WOOD, 0.7)
	for i in 4:
		var angle := i * TAU / 4.0 + 0.4
		b.prism(Transform3D(Basis(Vector3(cos(angle), 0, sin(angle)).cross(Vector3.UP), 0.7), Vector3(0, 4.0, 0)), 0.45, 4.5, 5, Palette.WOOD, 0.2)
	for i in 9:
		var p := Vector3(rng.randf_range(-6, 6), rng.randf_range(7, 11), rng.randf_range(-6, 6))
		b.blob(_xf(p), rng.randf_range(2.6, 3.8), [Palette.PINE, Palette.SAGE, Palette.MOSS][i % 3], 1 if i < 2 else 0, 0.25, i)
	# A shrine rope (금줄) around the trunk.
	b.prism(_xf(Vector3(0, 1.6, 0)), 1.12, 0.15, 7, Palette.STRAW)
	return b.mesh()


static func pavilion(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 0.9, 0)), Vector3(4.6, 0.25, 4.6), Palette.WOOD)
	for x in [-2.0, 2.0]:
		for z in [-2.0, 2.0]:
			b.prism(_xf(Vector3(x, 0, z)), 0.16, 3.3, 6, Palette.CORAL)
	b.box(_xf(Vector3(0, 3.4, 0)), Vector3(5.2, 0.3, 5.2), Palette.CORAL)
	# Hip roof with upturned corners.
	b.prism(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 3.55, 0)), 4.6, 1.8, 4, Palette.SLATE, 0.6)
	b.prism(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 5.35, 0)), 0.6, 0.3, 4, Palette.DUSK, 0.2)
	return b.mesh()


static func bus_stop(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 1.3, -0.8)), Vector3(3.6, 2.6, 0.12), Palette.MIST)
	b.box(_xf(Vector3(0, 2.7, 0)), Vector3(4.0, 0.15, 1.9), Palette.SKY)
	for x in [-1.7, 1.7]:
		b.box(_xf(Vector3(x, 1.3, 0.8)), Vector3(0.12, 2.6, 0.12), Palette.STONE)
	b.box(_xf(Vector3(0, 0.5, -0.4)), Vector3(3.0, 0.1, 0.5), Palette.WOOD)
	b.prism(_xf(Vector3(2.3, 0, 0.6)), 0.06, 2.8, 4, Palette.STONE)
	b.box(_xf(Vector3(2.3, 2.9, 0.6)), Vector3(0.7, 0.7, 0.06), Palette.PERIWINKLE)
	return b.mesh()


static func cultivator(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	# Two-wheel tractor pulling a small trailer; long handlebars.
	b.box(_xf(Vector3(0, 1.0, -1.4)), Vector3(0.9, 0.8, 1.2), Palette.CORAL)
	b.prism(_xf(Vector3(0, 1.4, -1.9)), 0.3, 0.5, 6, Palette.SLATE)
	for x in [-0.7, 0.7]:
		b.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x, 0.6, -1.4)), 0.6, 0.3, 8, Palette.INK)
		b.box(Transform3D(Basis(Vector3.RIGHT, -0.4), Vector3(x * 0.6, 1.6, -0.3)), Vector3(0.08, 0.08, 2.2), Palette.STONE)
	b.box(_xf(Vector3(0, 0.9, 1.4)), Vector3(1.8, 0.5, 2.4), Palette.SKY)
	b.box(_xf(Vector3(0, 0.6, 1.4)), Vector3(1.6, 0.1, 2.2), Palette.STONE)
	b.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(1.0, 0.4, 1.6)), 0.4, 0.2, 7, Palette.INK)
	b.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-1.2, 0.4, 1.6)), 0.4, 0.2, 7, Palette.INK)
	return b.mesh()


static func bale(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(-0.75, 0.75, 0)), 0.78, 1.5, 9, Palette.WHITE, -1.0, Palette.CREAM)
	return b.mesh()


static func church(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 3.0, 0)), Vector3(9.0, 6.0, 15.0), Palette.WHITE)
	b.gable(_xf(Vector3(0, 6.0, 0), PI * 0.5), Vector3(16.0, 3.4, 10.0), Palette.CORAL, Palette.WHITE)
	b.box(_xf(Vector3(0, 6.5, 8.5)), Vector3(3.2, 13.0, 3.2), Palette.WHITE)
	b.prism(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, 13.0, 8.5)), 2.4, 5.0, 4, Palette.CORAL, 0.0)
	for z in [-5.0, -1.5, 2.0]:
		b.box(_xf(Vector3(4.51, 3.5, z)), Vector3(0.05, 2.5, 1.0), Palette.SKY)
		b.box(_xf(Vector3(-4.51, 3.5, z)), Vector3(0.05, 2.5, 1.0), Palette.SKY)
	b.glow = true
	b.box(_xf(Vector3(0, 19.5, 8.5)), Vector3(0.3, 3.0, 0.3), Palette.RED)
	b.box(_xf(Vector3(0, 20.2, 8.5)), Vector3(1.8, 0.3, 0.3), Palette.RED)
	return b.mesh()


static func hall(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 2.2, 0)), Vector3(12.0, 4.4, 8.0), Palette.CONCRETE)
	b.box(_xf(Vector3(0, 4.5, 0)), Vector3(12.4, 0.3, 8.4), Palette.STONE)
	b.box(_xf(Vector3(0, 3.6, 4.02)), Vector3(5.0, 0.8, 0.05), Palette.SKY)
	for x in [-4.0, -2.0, 2.0, 4.0]:
		b.box(_xf(Vector3(x, 2.0, 4.02)), Vector3(1.3, 1.4, 0.05), Palette.DUSK)
	b.box(_xf(Vector3(0, 1.3, 4.02)), Vector3(1.6, 2.6, 0.05), Palette.SLATE)
	b.box(_xf(Vector3(3.5, 5.0, -2.0)), Vector3(1.2, 1.0, 1.2), Palette.PERIWINKLE)
	return b.mesh()


static func car(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var color := CAR_COLORS[variant % CAR_COLORS.size()]
	b.box(_xf(Vector3(0, 0.75, 0)), Vector3(1.8, 0.7, 4.3), color)
	b.box(_xf(Vector3(0, 1.4, 0.3)), Vector3(1.6, 0.65, 2.2), color)
	b.box(_xf(Vector3(0, 1.4, -0.82)), Vector3(1.5, 0.55, 0.05), Palette.DUSK)
	b.box(_xf(Vector3(0, 1.4, 1.42)), Vector3(1.5, 0.55, 0.05), Palette.DUSK)
	for x in [-0.9, 0.9]:
		for z in [-1.3, 1.3]:
			b.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x + 0.1 * signf(x), 0.4, z)), 0.38, 0.25, 7, Palette.INK)
	# Rust and moss on the hood.
	b.box(_xf(Vector3(rng.randf_range(-0.4, 0.4), 1.11, -1.4)), Vector3(0.8, 0.02, 0.9), Palette.OCHRE)
	b.blob(_xf(Vector3(0.5, 1.8, 0.8)), 0.4, Palette.FUNGUS, 0, 0.3, variant)
	return b.mesh()


static func truck(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var color := CAR_COLORS[(variant + 1) % CAR_COLORS.size()]
	b.box(_xf(Vector3(0, 1.6, -3.2)), Vector3(2.4, 2.4, 2.0), color)
	b.box(_xf(Vector3(0, 2.1, -4.21)), Vector3(2.1, 0.9, 0.05), Palette.DUSK)
	b.box(_xf(Vector3(0, 2.0, 1.2)), Vector3(2.5, 3.0, 6.8), Palette.MIST)
	b.box(_xf(Vector3(0, 2.0, 1.2)), Vector3(2.52, 0.4, 6.82), Palette.PERIWINKLE)
	for z in [-3.0, -0.2, 3.2]:
		for x in [-1.1, 1.1]:
			b.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(x + 0.15 * signf(x), 0.5, z)), 0.5, 0.3, 7, Palette.INK)
	return b.mesh()


static func mushroom(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var h := rng.randf_range(1.5, 3.5) * (1.0 + (variant % 3) * 0.4)
	var cap := [Palette.FUNGUS, Palette.LILAC, Palette.BLUSH, Palette.PEACH][variant % 4] as Color
	b.prism(Transform3D(Basis(Vector3.BACK, rng.randf_range(-0.2, 0.2)), Vector3.ZERO), 0.35 * (h / 2.5), h, 6, Palette.CREAM, 0.25 * (h / 2.5))
	b.prism(_xf(Vector3(0, h - 0.2, 0)), h * 0.55, h * 0.3, 8, cap, h * 0.12, Palette.MIST)
	b.glow = true
	for i in 4:
		var angle := i * TAU / 4.0 + variant
		b.blob(_xf(Vector3(cos(angle) * h * 0.3, h + 0.05, sin(angle) * h * 0.3)), 0.12 * h / 2.0, Palette.WHITE)
	return b.mesh()


static func spore_tower(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var y := 0.0
	var r := 1.6
	for i in 5:
		var h := rng.randf_range(1.5, 2.5)
		b.prism(_xf(Vector3(rng.randf_range(-0.3, 0.3), y, rng.randf_range(-0.3, 0.3))), r, h, 6, [Palette.MAUVE, Palette.LILAC][i % 2], r * 0.8)
		y += h * 0.9
		r *= 0.8
	b.glow = true
	for i in 6:
		b.blob(_xf(Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(1, y), rng.randf_range(-1.2, 1.2))), rng.randf_range(0.3, 0.6), Palette.FUNGUS, 0, 0.2, i + variant)
	return b.mesh()


static func mycelium(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	# A flat web of veins with lumps, draped over the ground.
	for i in 10:
		var angle := rng.randf() * TAU
		var length := rng.randf_range(2.0, 5.0)
		b.box(Transform3D(Basis(Vector3.UP, angle), Vector3(cos(angle), 0, -sin(angle)) * length * 0.3 + Vector3.UP * 0.05), Vector3(length, 0.12, 0.18), Palette.BLUSH if i % 2 else Palette.FUNGUS)
	for i in 4:
		b.blob(_xf(Vector3(rng.randf_range(-2, 2), 0.2, rng.randf_range(-2, 2))), rng.randf_range(0.4, 0.8), Palette.LILAC, 0, 0.3, i + variant)
	return b.mesh()


static func reeds(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	for i in 14:
		var p := Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
		var h := rng.randf_range(1.6, 2.8)
		var lean := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.25))
		b.prism(Transform3D(lean, p), 0.04, h, 3, Palette.STRAW if (i + variant) % 3 else Palette.OCHRE)
		b.prism(Transform3D(lean, p + lean * Vector3(0, h, 0)), 0.1, 0.5, 4, Palette.CREAM, 0.02)
	return b.mesh()


static func crate(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	var color := Palette.PINE if variant % 2 == 0 else Palette.OCHRE
	b.box(_xf(Vector3(0, 0.6, 0)), Vector3(1.8, 1.2, 1.2), color)
	b.box(_xf(Vector3(0, 0.6, 0.61)), Vector3(1.0, 0.3, 0.02), Palette.BUTTER)
	b.box(_xf(Vector3(0, 1.21, 0)), Vector3(1.9, 0.05, 0.3), Palette.INK)
	return b.mesh()


static func rock(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.blob(Transform3D(Basis().scaled(Vector3(1.4, 0.8, 1.1)), Vector3(0, 0.6, 0)), 1.6, Palette.ASH if variant % 2 else Palette.STONE, 0, 0.3, variant)
	return b.mesh()


static func school(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	# Two-floor branch school with a central entrance and clock.
	b.box(_xf(Vector3(0, 4.0, 0)), Vector3(48.0, 8.0, 10.0), Palette.CREAM)
	b.box(_xf(Vector3(0, 8.2, 0)), Vector3(48.6, 0.4, 10.6), Palette.BLUSH)
	b.box(_xf(Vector3(0, 0.3, 0)), Vector3(48.4, 0.6, 10.4), Palette.STONE)
	b.box(_xf(Vector3(0, 5.0, 5.3)), Vector3(7.0, 10.0, 1.2), Palette.MIST)
	b.prism(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 8.5, 5.9)), 1.2, 0.1, 10, Palette.WHITE)
	b.box(_xf(Vector3(0, 8.8, 6.0)), Vector3(0.1, 0.8, 0.05), Palette.INK)
	for floor_y in [2.0, 5.6]:
		for i in 12:
			var x := -22.0 + i * 3.8
			if absf(x) < 4.0:
				continue
			b.box(_xf(Vector3(x, floor_y, 5.01)), Vector3(2.6, 1.8, 0.05), Palette.SKY if i % 4 else Palette.DUSK)
	# Fungus has taken the east wing.
	for i in 6:
		b.blob(_xf(Vector3(14.0 + i * 1.8, 2.0 + (i % 3) * 2.5, 5.0)), 1.8 + (i % 2), Palette.FUNGUS if i % 2 else Palette.LILAC, 0, 0.35, i)
	b.box(_xf(Vector3(-5.0, 1.6, 5.8)), Vector3(3.0, 3.2, 0.3), Palette.PEACH)
	return b.mesh()


static func gate(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 1.6, 0)), Vector3(1.0, 3.2, 1.0), Palette.CONCRETE)
	b.box(_xf(Vector3(0, 3.3, 0)), Vector3(1.3, 0.3, 1.3), Palette.BLUSH)
	b.box(_xf(Vector3(0.51, 2.0, 0)), Vector3(0.05, 1.8, 0.5), Palette.WOOD)
	return b.mesh()


static func flagpole(_variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(), 0.1, 12.0, 5, Palette.WHITE)
	b.box(_xf(Vector3(0.8, 10.8, 0)), Vector3(1.6, 1.1, 0.05), Palette.WHITE)
	b.glow = true
	b.blob(_xf(Vector3(0.8, 10.8, 0.06)), 0.3, Palette.RED)
	return b.mesh()


static func plane_tree(variant: int, rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	b.prism(Transform3D(), 0.4, 6.0, 6, Palette.MIST, 0.3)
	for i in 5:
		b.blob(_xf(Vector3(rng.randf_range(-2, 2), rng.randf_range(6, 9), rng.randf_range(-2, 2))), rng.randf_range(1.8, 2.6), [Palette.BUTTER, Palette.STRAW, Palette.PEACH][(i + variant) % 3], 0, 0.3, i)
	return b.mesh()


static func pier(variant: int, _rng: RandomNumberGenerator) -> Mesh:
	var b := LowPoly.new()
	# Floating fishing platform (좌대) with a tiny hut.
	b.box(_xf(Vector3(0, 0.3, 0)), Vector3(5.0, 0.4, 4.0), Palette.WOOD)
	b.box(_xf(Vector3(-0.8, 1.5, 0)), Vector3(2.4, 2.0, 2.4), Palette.CREAM)
	b.gable(_xf(Vector3(-0.8, 2.5, 0)), Vector3(3.0, 1.0, 3.0), ROOF_COLORS[variant % ROOF_COLORS.size()])
	for x in [-2.3, 2.3]:
		b.prism(_xf(Vector3(x, -0.4, 1.8)), 0.35, 0.6, 6, Palette.WHITE)
		b.prism(_xf(Vector3(x, -0.4, -1.8)), 0.35, 0.6, 6, Palette.WHITE)
	return b.mesh()
