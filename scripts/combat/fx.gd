class_name Fx
extends Node3D
## CPU particles drawn through two MultiMeshes (lit chunks and glowing sparks), plus short-lived
## meshes for blasts, rings, beams and ground scorch marks. Everything fades by dithering.

const MAX_PARTICLES := 2400
const MAX_SCORCH := 60

enum Kind { SOLID, GLOW }

class Particle:
	var position: Vector3
	var velocity: Vector3
	var life := 0.0
	var max_life := 1.0
	var size := 0.3
	var end_size := 0.0
	var color := Color.WHITE
	var gravity := 0.0
	var drag := 0.0
	var spin := Vector3.ZERO
	var bounce := false
	var fade_start := 0.55 ## Fraction of life after which it dithers away.

static var _solid_material := _fade_material(false)
static var _glow_material := _fade_material(true)

var _pools := {Kind.SOLID: [], Kind.GLOW: []}
var _multimeshes := {}
var _transients: Array[Dictionary] = []
var _scorches: Array[MeshInstance3D] = []
var _flashes: Array[OmniLight3D] = []


static func _fade_material(glow: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/dither_fade.gdshader")
	material.set_shader_parameter("unshaded", glow)
	return material


func _ready() -> void:
	for kind: Kind in [Kind.SOLID, Kind.GLOW]:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = _particle_mesh(kind)
		multimesh.instance_count = MAX_PARTICLES
		multimesh.visible_instance_count = 0
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = _glow_material if kind == Kind.GLOW else _solid_material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind == Kind.GLOW else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		instance.custom_aabb = AABB(Vector3(-5000, -500, -5000), Vector3(10000, 1000, 10000))
		add_child(instance)
		_multimeshes[kind] = multimesh
	for i in 4:
		var light := OmniLight3D.new()
		light.light_color = Palette.PEACH
		light.omni_range = 14.0
		light.light_energy = 0.0
		light.shadow_enabled = false
		add_child(light)
		_flashes.append(light)


static func _particle_mesh(kind: Kind) -> Mesh:
	var builder := LowPoly.new()
	if kind == Kind.GLOW:
		builder.blob(Transform3D(), 0.5, Color.WHITE)
	else:
		# A chunky, irregular shard reads as debris, dirt or smoke depending on its color.
		builder.blob(Transform3D(), 0.5, Color.WHITE, 0, 0.35, 3)
	var mesh := builder.mesh()
	return mesh


func spawn(kind: Kind, position: Vector3, velocity: Vector3, life: float, size: float, color: Color, options := {}) -> void:
	var pool: Array = _pools[kind]
	if pool.size() >= MAX_PARTICLES:
		pool.pop_front()
	var p := Particle.new()
	p.position = position
	p.velocity = velocity
	p.max_life = life
	p.size = size
	p.end_size = options.get("end_size", size * 0.2)
	p.color = color
	p.gravity = options.get("gravity", 0.0)
	p.drag = options.get("drag", 0.0)
	p.bounce = options.get("bounce", false)
	p.fade_start = options.get("fade", 0.55)
	p.spin = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8)) * options.get("spin", 0.0)
	pool.append(p)


func _process(delta: float) -> void:
	for kind: Kind in _pools:
		var pool: Array = _pools[kind]
		var multimesh: MultiMesh = _multimeshes[kind]
		var alive: Array = []
		var index := 0
		for p: Particle in pool:
			p.life += delta
			if p.life >= p.max_life:
				continue
			p.velocity.y -= p.gravity * delta
			p.velocity *= maxf(0.0, 1.0 - p.drag * delta)
			p.position += p.velocity * delta
			if p.bounce:
				var ground := Course.height_at(p.position)
				if p.position.y < ground:
					p.position.y = ground
					p.velocity = Vector3(p.velocity.x * 0.5, absf(p.velocity.y) * 0.3, p.velocity.z * 0.5)
			var t := p.life / p.max_life
			var s := lerpf(p.size, p.end_size, t)
			var basis := Basis.from_euler(p.spin * p.life).scaled(Vector3.ONE * s)
			multimesh.set_instance_transform(index, Transform3D(basis, p.position))
			var color := p.color
			color.a = 1.0 - smoothstep(p.fade_start, 1.0, t)
			multimesh.set_instance_color(index, color)
			alive.append(p)
			index += 1
		_pools[kind] = alive
		multimesh.visible_instance_count = index
	_update_transients(delta)
	for light in _flashes:
		light.light_energy = move_toward(light.light_energy, 0.0, delta * 30.0)


func _update_transients(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for t in _transients:
		t.age += delta
		var node: Node3D = t.node
		var k: float = t.age / t.life
		if k >= 1.0:
			node.queue_free()
			continue
		if t.grow != Vector2.ONE:
			node.scale = Vector3.ONE * lerpf(t.grow.x, t.grow.y, 1.0 - pow(1.0 - k, 3.0))
		var material: ShaderMaterial = t.material
		material.set_shader_parameter("alpha_scale", 1.0 - smoothstep(t.get("fade_from", 0.3), 1.0, k))
		keep.append(t)
	_transients = keep


func _transient(mesh: Mesh, xf: Transform3D, life: float, glow: bool, grow := Vector2.ONE, fade_from := 0.3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.transform = xf
	var material := (_glow_material if glow else _solid_material).duplicate() as ShaderMaterial
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_transients.append({"node": node, "age": 0.0, "life": life, "grow": grow, "material": material, "fade_from": fade_from})
	return node


func light_flash(position: Vector3, energy: float, color := Palette.PEACH, radius := 14.0) -> void:
	var light := _flashes[0]
	for candidate in _flashes:
		if candidate.light_energy < light.light_energy:
			light = candidate
	light.position = position + Vector3.UP
	light.light_color = color
	light.omni_range = radius
	light.light_energy = energy


## A fireball blast with shockwave, sparks, smoke, debris and a scorch mark.
func explosion(position: Vector3, radius: float, palette := [Palette.WHITE, Palette.BUTTER, Palette.PEACH, Palette.CORAL]) -> void:
	var fireball := LowPoly.new()
	fireball.blob(Transform3D(), 1.0, palette[0], 1, 0.25, randi())
	_transient(fireball.mesh(), Transform3D(Basis(), position), 0.32 + radius * 0.03, true, Vector2(radius * 0.3, radius), 0.15)
	shockwave(position, radius * 1.8, palette[mini(1, palette.size() - 1)])
	light_flash(position, 6.0 + radius, palette[mini(2, palette.size() - 1)], radius * 4.0)
	for i in int(8 + radius * 5):
		var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 1.4), randf_range(-1, 1)).normalized()
		spawn(Kind.GLOW, position, dir * randf_range(4, 12) * (0.6 + radius * 0.25), randf_range(0.2, 0.55), randf_range(0.2, 0.5) * (0.6 + radius * 0.15), palette[randi() % palette.size()], {"gravity": 8.0, "drag": 2.0})
	smoke(position, int(4 + radius * 2), radius)
	debris(position, int(4 + radius * 2), [Palette.WOOD, Palette.INK, Palette.OCHRE], radius * 2.5)
	var ground := Course.height_at(position)
	if position.y - ground < radius:
		scorch(Vector3(position.x, ground, position.z), radius * 0.9)


## Flat, unlit puffs that rise, swell and dither away: reads as smoke, not rocks.
func smoke(position: Vector3, count: int, radius := 1.0, colors := [Palette.MIST, Palette.CREAM, Palette.ASH]) -> void:
	for i in count:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.4, 1.0), randf_range(-1, 1)).normalized()
		spawn(Kind.GLOW, position + dir * radius * 0.4, dir * randf_range(1.0, 3.0) + Vector3.UP * 1.5, randf_range(0.8, 1.6), randf_range(0.5, 0.9) * (0.4 + radius * 0.15), colors[i % colors.size()], {"end_size": 0.8 + radius * 0.35, "drag": 2.2, "gravity": -1.0, "fade": 0.15})


func debris(position: Vector3, count: int, colors: Array, force := 6.0, size := 0.35) -> void:
	for i in count:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)).normalized()
		spawn(Kind.SOLID, position, dir * randf_range(0.4, 1.0) * force, randf_range(1.2, 2.4), randf_range(0.6, 1.3) * size, colors[i % colors.size()], {"gravity": 22.0, "bounce": true, "spin": 1.0, "end_size": size * 0.8})


func sparks(position: Vector3, normal: Vector3, count: int, color := Palette.BUTTER, speed := 10.0) -> void:
	for i in count:
		var dir := (normal + Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)) * 0.8).normalized()
		spawn(Kind.GLOW, position, dir * randf_range(0.4, 1.0) * speed, randf_range(0.08, 0.25), randf_range(0.08, 0.16), color, {"gravity": 20.0})


func dust(position: Vector3, count: int, spread := 2.0, color := Palette.STRAW) -> void:
	for i in count:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.1, 0.5), randf_range(-1, 1)).normalized()
		spawn(Kind.GLOW, position + dir * randf() * spread, dir * randf_range(1.0, 4.0) * spread * 0.5, randf_range(0.5, 1.2), randf_range(0.4, 0.8), color, {"end_size": 1.4, "drag": 3.0, "gravity": -0.4, "fade": 0.1})


func spores(position: Vector3, count: int, spread := 1.5) -> void:
	for i in count:
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.2, 1.0), randf_range(-1, 1)).normalized()
		var color := [Palette.FUNGUS, Palette.BLUSH, Palette.LILAC][i % 3] as Color
		spawn(Kind.GLOW if i % 4 == 0 else Kind.SOLID, position + dir * randf() * spread, dir * randf_range(0.5, 3.0) * spread, randf_range(0.8, 1.8), randf_range(0.2, 0.5), color, {"end_size": 0.9, "drag": 2.0, "gravity": -0.3})


func shockwave(position: Vector3, radius: float, color: Color) -> void:
	var ring := LowPoly.new()
	ring.glow = true
	for i in 16:
		var a0 := TAU * i / 16.0
		var a1 := TAU * (i + 1) / 16.0
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var o1 := Vector3(cos(a1), 0, sin(a1))
		ring.quad(o0 * 0.8, o1 * 0.8, o1, o0, color, Vector3.UP)
	_transient(ring.mesh(), Transform3D(Basis(), position + Vector3.UP * 0.2), 0.3, true, Vector2(radius * 0.2, radius), 0.1)


## A straight glowing line, used for laser zaps and designator lines.
func beam(from: Vector3, to: Vector3, color: Color, width := 0.12, life := 0.06) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var builder := LowPoly.new()
	builder.glow = true
	builder.box(Transform3D(Basis(), Vector3(0, 0, -length * 0.5)), Vector3(width, width, length), color)
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT
	_transient(builder.mesh(), Transform3D(Basis.looking_at(to - from, up), from), life, true, Vector2.ONE, 0.5)


## A pulsing ring on the ground that tightens until `time` runs out: where something will land.
func marker(position: Vector3, radius: float, time: float, color := Palette.RED) -> void:
	var ring := LowPoly.new()
	ring.glow = true
	for i in 20:
		var a0 := TAU * i / 20.0
		var a1 := TAU * (i + 0.6) / 20.0
		var o0 := Vector3(cos(a0), 0, sin(a0))
		var o1 := Vector3(cos(a1), 0, sin(a1))
		ring.quad(o0 * 0.86, o1 * 0.86, o1, o0, color, Vector3.UP)
	ring.box(Transform3D(), Vector3(0.5, 0.02, 0.08), color)
	ring.box(Transform3D(), Vector3(0.08, 0.02, 0.5), color)
	var ground := Vector3(position.x, Course.height_at(position) + 0.15, position.z)
	var node := _transient(ring.mesh(), Transform3D(Basis(), ground), time, true, Vector2(radius * 1.6, radius), 0.97)
	node.scale = Vector3.ONE * radius * 1.6


func scorch(position: Vector3, radius: float) -> void:
	var builder := LowPoly.new()
	var sides := 7
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var r0 := radius * randf_range(0.7, 1.1)
		var r1 := radius * randf_range(0.7, 1.1)
		builder.tri(Vector3.ZERO, Vector3(cos(a0) * r0, 0, sin(a0) * r0), Vector3(cos(a1) * r1, 0, sin(a1) * r1), Palette.DUSK, Vector3.UP)
	var mark := MeshInstance3D.new()
	mark.mesh = builder.mesh()
	mark.position = position + Vector3.UP * 0.08
	mark.rotation.y = randf() * TAU
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mark)
	_scorches.append(mark)
	if _scorches.size() > MAX_SCORCH:
		_scorches.pop_front().queue_free()

