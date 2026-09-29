class_name Fx
extends Node3D
## CPU particles drawn through MultiMeshes (flat debris shards, glowing puffs and flames), plus
## short-lived meshes for blasts, rings, beams and ground scorch marks. Everything fades by dithering.

const MAX_PARTICLES := 4000
const SOFT_CAP := 1200
const MAX_SCORCH := 60
const FLASH_LIGHTS := 12 ## Pooled lights for blasts, muzzles and fires; the dimmest one is reused.
const BLAST_PACE := 0.8 ## Explosions play out in this fraction of their original time.
const DEBRIS_SIZE := 1.8 ## Flat shards are drawn this much bigger than the size callers ask for.
const DEBRIS_SMOKE := Color("9c93a3") ## Every flying shard trails a thin line of smoke.
const TRAIL_MIN_SPEED := 4.0 ## Shards stop trailing once they slow down on the ground.

## SOLID: flat pixel-art debris sprites that face the camera and tumble in the screen plane.
## GLOW: unlit puffs (smoke, dust, spores), dithered. FLAME: fire, sparks and flashes, drawn
## without dithering.
enum Kind { SOLID, GLOW, FLAME }

## What a shard is made of. Each has DEBRIS_VARIANTS sprites in assets/debris, drawn by
## tools/debris.py; keep the order in step with its MATERIALS list.
enum Debris { WOOD, CONCRETE, ROOF, GLASS, METAL, PAINT, ARMOR, VINYL, FLESH, SPORE, FOLIAGE, STRAW, CERAMIC, ROCK, BRASS, DIRT }
const DEBRIS_FILES: Array[String] = ["wood", "concrete", "roof", "glass", "metal", "paint", "armor", "vinyl", "flesh", "spore", "foliage", "straw", "ceramic", "rock", "brass", "dirt"]
const DEBRIS_VARIANTS := 6
const STRIDE := 20 ## Transform, color and shader data: size/rotation (and debris sprite layer).

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
	var trail := Color(0, 0, 0, 0) ## Leaves smoke puffs behind while alive (burning debris).
	var ground := -INF ## Ground height for bouncing, sampled once: debris lands near where it starts.
	var trail_timer := 0.0
	var layer := 0 ## Debris sprite in the texture array.
	var water := false ## Bouncing over the reservoir: it splashes in and sinks instead.

static var _solid_material := _debris_material()
static var _glow_material := _fade_material(true)
static var _flame_material := _flame()


static func _flame() -> ShaderMaterial:
	var material := _fade_material(true)
	material.set_shader_parameter("hard_cut", true)
	return material

var _pools := {Kind.SOLID: [], Kind.GLOW: [], Kind.FLAME: []}
var _multimeshes := {}
var _buffers := {} ## Kind -> PackedFloat32Array uploaded to the MultiMesh in one call per frame.
static var _mesh_cache := {} ## Unit-sized transient meshes by name and color.
static var _shaders_warmed := false
var _transients: Array[Dictionary] = []
var _scorches: Array[MeshInstance3D] = []
var _flashes: Array[OmniLight3D] = []
var _delayed: Array[Dictionary] = [] ## Secondary blasts waiting to go off.
var _emitters: Array[Dictionary] = [] ## Burning wrecks: flames and a smoke column for a while.


## Every debris sprite stacked into one texture array, so all shards draw in a single call.
static func _debris_material() -> ShaderMaterial:
	var images: Array[Image] = []
	for file in DEBRIS_FILES:
		for i in DEBRIS_VARIANTS:
			var image: Image = load("res://assets/debris/%s_%d.png" % [file, i]).get_image()
			if image.is_compressed():
				image.decompress()
			image.convert(Image.FORMAT_RGBA8)
			images.append(image)
	var sprites := Texture2DArray.new()
	sprites.create_from_images(images)
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/debris_sprite.gdshader")
	material.set_shader_parameter("sprites", sprites)
	return material


static func _fade_material(glow: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/dither_fade.gdshader")
	material.set_shader_parameter("unshaded", glow)
	return material


func _ready() -> void:
	_fireball_mesh() # The first hit must not build the detailed blast sphere during combat.
	for color in [Palette.WHITE, Palette.BUTTER, Palette.FRIENDLY, Palette.HOSTILE]:
		for variant in 3:
			_flash_mesh(variant, color)
	for kind: Kind in [Kind.SOLID, Kind.GLOW, Kind.FLAME]:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = _particle_mesh(kind)
		multimesh.visible_instance_count = 0
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = [_solid_material, _glow_material, _flame_material][kind].duplicate()
		instance.material_override.set_shader_parameter("particles", true)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if kind == Kind.FLAME:
			instance.layers |= ActorLayer.LAYER
		instance.custom_aabb = AABB(Vector3(-5000, -500, -5000), Vector3(10000, 1000, 10000))
		add_child(instance)
		_multimeshes[kind] = multimesh
		_buffers[kind] = PackedFloat32Array()
	for i in FLASH_LIGHTS:
		var light := OmniLight3D.new()
		light.light_color = Palette.PEACH
		light.omni_range = 14.0
		light.light_energy = 0.0
		light.shadow_enabled = false
		add_child(light)
		_flashes.append(light)
	_warm_shaders()


## Compatibility compiles shader variants on first draw. Render the actual material/vertex
## formats once during loading, in a tiny world that is never composited onto the game screen.
func _warm_shaders() -> void:
	if _shaders_warmed or DisplayServer.get_name() == "headless":
		return
	_shaders_warmed = true
	var view := SubViewport.new()
	view.size = Vector2i(16, 16)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)
	var camera := Camera3D.new()
	camera.position.z = 3.0
	view.add_child(camera)
	view.add_child(DirectionalLight3D.new())
	for kind: Kind in [Kind.SOLID, Kind.GLOW, Kind.FLAME]:
		var source := get_child(kind) as MultiMeshInstance3D
		var instance := MultiMeshInstance3D.new()
		var mesh := MultiMesh.new()
		mesh.transform_format = MultiMesh.TRANSFORM_3D
		mesh.use_colors = true
		mesh.use_custom_data = true
		mesh.mesh = source.multimesh.mesh
		mesh.instance_count = 1
		mesh.set_instance_transform(0, Transform3D.IDENTITY)
		mesh.set_instance_color(0, Color.WHITE)
		mesh.set_instance_custom_data(0, Color(0, 1, 0, 0) if kind == Kind.SOLID else Color(1, 0, 0, 0))
		instance.multimesh = mesh
		instance.material_override = source.material_override
		view.add_child(instance)
	for mat in [_fireball_material, _glow_material, _flame_material, LowPoly.flesh_material,
			LowPoly.flesh_glow_material, LowPoly.vivid_lit_material, LowPoly.vivid_glow_material]:
		var instance := MeshInstance3D.new()
		instance.mesh = _fireball_mesh()
		instance.material_override = mat
		view.add_child(instance)
	RenderingServer.frame_post_draw.connect(func() -> void:
		if is_instance_valid(view):
			view.queue_free(), CONNECT_ONE_SHOT)


static func _particle_mesh(kind: Kind) -> Mesh:
	if kind == Kind.SOLID:
		# A flat sprite card; the sprite fills about two thirds of it.
		var card := QuadMesh.new()
		card.size = Vector2(1.5, 1.5)
		return card
	var builder := LowPoly.new()
	builder.blob(Transform3D(), 0.5, Color.WHITE)
	return builder.mesh()


func particle_count() -> int:
	var total := 0
	for pool: Array in _pools.values():
		total += pool.size()
	return total


func spawn(kind: Kind, position: Vector3, velocity: Vector3, life: float, size: float, color: Color, options := {}) -> void:
	var pool: Array = _pools[kind]
	# Past the soft cap, big chain explosions thin out instead of stalling the frame.
	if pool.size() > SOFT_CAP and randf() < 0.5:
		return
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
	p.trail = options.get("trail", Color(0, 0, 0, 0))
	if p.bounce:
		p.ground = Course.height_at(position)
		if p.ground < Course.WATER_LEVEL:
			p.ground = Course.WATER_LEVEL
			p.water = true
	p.spin = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8)) * options.get("spin", 0.0)
	if kind == Kind.SOLID:
		var material: Debris = options.get("material", Debris.DIRT)
		p.layer = material * DEBRIS_VARIANTS + randi() % DEBRIS_VARIANTS
		p.spin.x = randf() * TAU # Starting roll.
	pool.append(p)


func _process(delta: float) -> void:
	var trails: Array[Particle] = []
	var splashes: Array[Particle] = []
	for kind: Kind in _pools:
		var pool: Array = _pools[kind]
		var multimesh: MultiMesh = _multimeshes[kind]
		var buffer: PackedFloat32Array = _buffers[kind]
		if pool.size() > multimesh.instance_count:
			var capacity := mini(MAX_PARTICLES, maxi(128, nearest_po2(pool.size())))
			var previous := multimesh.instance_count
			multimesh.instance_count = capacity
			buffer.resize(capacity * STRIDE)
			for i in range(previous, capacity):
				buffer[i * STRIDE] = 1.0
				buffer[i * STRIDE + 5] = 1.0
				buffer[i * STRIDE + 10] = 1.0
		var index := 0
		for read in pool.size():
			var p: Particle = pool[read]
			var age := p.life + delta
			p.life = age
			if age >= p.max_life:
				continue
			var velocity := p.velocity
			velocity.y -= p.gravity * delta
			velocity *= maxf(0.0, 1.0 - p.drag * delta)
			var position := p.position + velocity * delta
			if p.bounce and position.y < p.ground:
				if p.water:
					p.position = position
					p.velocity = velocity
					splashes.append(p)
					continue
				position.y = p.ground
				velocity = Vector3(velocity.x * 0.5, absf(velocity.y) * 0.3, velocity.z * 0.5)
			p.position = position
			p.velocity = velocity
			var t := age / p.max_life
			var s := lerpf(p.size, p.end_size, t)
			# Translation stays on the CPU for collisions and trails. The vertex shader handles
			# size, rotation and billboarding, avoiding nine matrix writes per particle/frame.
			var o := index * STRIDE
			if kind == Kind.SOLID:
				buffer[o + 16] = p.layer
				buffer[o + 17] = s
				buffer[o + 18] = p.spin.x + p.spin.z * age
			else:
				buffer[o + 16] = s
				buffer[o + 17] = p.spin.x * age
				buffer[o + 18] = p.spin.y * age
				buffer[o + 19] = p.spin.z * age
			buffer[o + 3] = position.x
			buffer[o + 7] = position.y
			buffer[o + 11] = position.z
			buffer[o + 12] = p.color.r
			buffer[o + 13] = p.color.g
			buffer[o + 14] = p.color.b
			buffer[o + 15] = 1.0 - smoothstep(p.fade_start, 1.0, t)
			if p.trail.a > 0.0:
				p.trail_timer -= delta
				if p.trail_timer <= 0.0 and (kind != Kind.SOLID or velocity.length_squared() > TRAIL_MIN_SPEED * TRAIL_MIN_SPEED):
					p.trail_timer = 0.05 if kind == Kind.FLAME else 0.08
					trails.append(p)
			if index != read:
				pool[index] = p
			index += 1
		if index < pool.size():
			pool.resize(index)
		_buffers[kind] = buffer
		if index > 0:
			multimesh.buffer = buffer
		multimesh.visible_instance_count = index
	for p in splashes:
		splash(p.position, p.size)
	for p in trails:
		if p.bounce:
			# A flying shard: a thin smoke line, no fire.
			spawn(Kind.GLOW, p.position, Vector3.UP * 0.4, 0.5, p.size * 0.6, p.trail, {"end_size": p.size * 1.6, "drag": 2.0, "fade": 0.1})
			continue
		spawn(Kind.GLOW, p.position, Vector3.UP * 0.8, 0.9, p.size * 0.9, p.trail, {"end_size": p.size * 2.5, "drag": 1.5, "fade": 0.1})
		if randf() < 0.5:
			spawn(Kind.FLAME, p.position, Vector3.ZERO, 0.12, p.size * 0.8, [Palette.BUTTER, Palette.PEACH][randi() % 2])
	_update_delayed(delta)
	_update_emitters(delta)
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
		if t.has("fireball"):
			node.set_instance_shader_parameter("progress", k)
			node.position.y += delta * 1.5
		else:
			node.set_instance_shader_parameter("instance_alpha", 1.0 - smoothstep(t.fade_from, 1.0, k))
		keep.append(t)
	_transients = keep


static var _fireball_material := _make_fireball()


static func _make_fireball() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/fireball.gdshader")
	return material


static func _fireball_mesh() -> Mesh:
	return _cached("fireball", Palette.WHITE, func(b: LowPoly, c: Color) -> void: b.blob(Transform3D(), 1.0, c, 2, 0.12, 4))


## One ball of an explosion: it swells from `start` to `end` radius while its bands cool and it
## breaks up. Drawn crisp (never dithered) on the actor layer.
func fireball(position: Vector3, start: float, end: float, life: float) -> void:
	var mesh := _fireball_mesh()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = position
	node.rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
	node.material_override = _fireball_material
	node.layers |= ActorLayer.LAYER
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_instance_shader_parameter("seed", randf())
	add_child(node)
	_transients.append({"node": node, "age": 0.0, "life": life, "grow": Vector2(start, end), "fade_from": 1.0, "fireball": true})


func _transient(mesh: Mesh, xf: Transform3D, life: float, glow: bool, grow := Vector2.ONE, fade_from := 0.3, flame := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.transform = xf
	node.material_override = _flame_material if flame else (_glow_material if glow else _solid_material)
	if flame:
		node.layers |= ActorLayer.LAYER
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	_transients.append({"node": node, "age": 0.0, "life": life, "grow": grow, "fade_from": fade_from})
	return node


## Builds a unit-sized effect mesh once per name and color; callers scale the node instead.
static func _cached(name: String, color: Color, build: Callable) -> Mesh:
	var key := "%s_%s" % [name, color.to_html()]
	if not _mesh_cache.has(key):
		var b := LowPoly.new()
		b.glow = true
		build.call(b, color)
		_mesh_cache[key] = b.mesh()
	return _mesh_cache[key]


func light_flash(position: Vector3, energy: float, color := Palette.PEACH, radius := 14.0) -> void:
	var light := _flashes[0]
	for candidate in _flashes:
		if candidate.light_energy < light.light_energy:
			light = candidate
	light.position = position + Vector3.UP
	light.light_color = color
	light.omni_range = radius
	light.light_energy = energy


## A layered blast: a cluster of cartoon fireballs that bloom, cool and break up, a crisp shock ring,
## a ground dust ring, a few embers, burning debris trailing smoke, a smoke column and, for big ones,
## secondary pops.
## `push` is the attack direction: the fireball, embers, dust and debris are thrown on along it and
## the secondary pops march down it, so a shell's blast carries through what it hit.
func explosion(position: Vector3, damage_radius: float, palette := [Palette.BUTTER, Palette.AMBER, Palette.HOT, Palette.CORAL], push := Vector3.ZERO) -> void:
	# Visuals read bigger than the damage area: it has to register at 480x270 across the valley.
	# Capped so a heavy shell's blast reads huge without swallowing the screen.
	var radius := minf(damage_radius * 1.5, 8.0)
	var smoke_radius := minf(radius, 4.0)
	# Particle counts grow slower than the visual size: big blasts read big without flooding the frame.
	var n := radius * 0.75
	var pick := func(i: int) -> Color: return palette[mini(i, palette.size() - 1)]
	# The main ball, then smaller ones budding off around it (thrown on along the attack).
	var life := (0.45 + radius * 0.06) * BLAST_PACE
	fireball(position + Vector3.UP * radius * 0.15, radius * 0.25, radius * 0.75, life)
	for i in 3 + int(n * 0.6):
		var out := (Vector3(randf_range(-1, 1), randf_range(-0.2, 1.0), randf_range(-1, 1)).normalized() + push * 0.8).normalized()
		fireball(position + out * radius * randf_range(0.35, 0.7) + Vector3.UP * radius * 0.2, radius * 0.12, radius * randf_range(0.3, 0.5), life * randf_range(0.7, 1.1))
	shockwave(position, radius * 2.2, Palette.WHITE, 0.3 * BLAST_PACE)
	light_flash(position, 8.0 + radius * 1.5, pick.call(2), radius * 5.0)
	for i in int(4 + n * 3):
		var dir := (Vector3(randf_range(-1, 1), randf_range(0.2, 1.4), randf_range(-1, 1)).normalized() + push * 1.3).normalized()
		spawn(Kind.FLAME, position, dir * randf_range(4, 14) * (0.6 + radius * 0.3), randf_range(0.25, 0.7) * BLAST_PACE, randf_range(0.25, 0.6) * (0.6 + radius * 0.15), palette[randi() % palette.size()], {"gravity": 8.0, "drag": 2.0})
	var ground := Course.height_at(position)
	if ground < Course.WATER_LEVEL and position.y - Course.WATER_LEVEL < radius * 1.5:
		# Over the reservoir: a tall plume of water instead of dust and a scorch mark.
		splash(position, radius * 0.8)
		for i in int(6 + n * 4):
			var up := Vector3(randf_range(-0.25, 0.25), 1.0, randf_range(-0.25, 0.25)).normalized()
			spawn(Kind.GLOW, Vector3(position.x, Course.WATER_LEVEL, position.z), up * randf_range(8.0, 16.0) * (0.5 + radius * 0.15), randf_range(0.8, 1.3), randf_range(0.5, 0.9) * (0.6 + radius * 0.15), [Palette.WHITE, Palette.SKY, Palette.MIST][i % 3], {"gravity": 14.0, "end_size": 1.4, "drag": 0.6, "fade": 0.4})
		ground = Course.WATER_LEVEL
	var low := position.y - ground < radius * 1.5 and ground > Course.WATER_LEVEL
	if low:
		# Dust thrown out along the ground.
		for i in int(8 + n * 4):
			var angle := randf() * TAU
			var out := (Vector3(cos(angle), 0.0, sin(angle)) + Vector3(push.x, 0.0, push.z) * 1.2).normalized()
			spawn(Kind.GLOW, Vector3(position.x, ground + 0.4, position.z) + out * radius * 0.4, out * randf_range(6, 12) * (0.5 + radius * 0.2) + Vector3.UP, randf_range(0.6, 1.2), randf_range(0.6, 1.1), [Palette.STRAW, Palette.OCHRE, Palette.MIST][i % 3], {"end_size": 1.8 + radius * 0.3, "drag": 3.5, "fade": 0.1})
		scorch(Vector3(position.x, ground, position.z), radius * 0.9)
	smoke(position, int(4 + n * 2), smoke_radius)
	smoke_column(position, smoke_radius)
	debris(position, int(4 + n * 2), [Debris.DIRT, Debris.ROCK], radius * 2.5, 0.35, push)
	for i in int(1 + n * 0.8):
		var dir := Vector3(randf_range(-1, 1), randf_range(0.8, 1.6), randf_range(-1, 1)).normalized()
		spawn(Kind.FLAME, position, dir * randf_range(6, 12) * (0.7 + radius * 0.15), randf_range(1.0, 1.8), 0.35, Palette.PEACH, {"gravity": 18.0, "trail": Palette.ASH, "end_size": 0.2, "fade": 0.8})
	if damage_radius >= 3.0:
		for i in int(damage_radius * 0.5):
			var along := push * damage_radius * (0.8 + i * 0.7)
			_delayed.append({"time": (randf_range(0.12, 0.3) + i * 0.1) * BLAST_PACE, "position": position + along + Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)) * damage_radius * 0.6, "radius": damage_radius * 0.4, "palette": palette, "push": push})


## A see-through copy of `meshes` where they stand now, washed in `color`, that dithers away.
func afterimage(meshes: Array, color: Color, life := 0.45) -> void:
	for node in meshes:
		var source := node as MeshInstance3D if is_instance_valid(node) else null
		if source == null or not source.is_visible_in_tree() or source.mesh == null:
			continue
		var ghost := _transient(source.mesh, source.global_transform, life, true, Vector2.ONE, 0.0)
		ghost.layers |= ActorLayer.LAYER # In true colors, like the tank itself.
		ghost.set_instance_shader_parameter("instance_tint", Color(color, 0.8))
		ghost.set_instance_shader_parameter("instance_alpha", 0.8)


## Something hits the water: a crown of spray and rings spreading out over the surface.
func splash(position: Vector3, size: float) -> void:
	var at := Vector3(position.x, Course.WATER_LEVEL + 0.05, position.z)
	for ring in [[2.5, 0.8], [4.5, 1.3], [7.0, 1.9]]:
		_transient(_cached("ring", Palette.CREAM, _ring_builder), Transform3D(Basis(), at), ring[1] * (0.6 + size * 0.4), true, Vector2(size * 0.5, size * ring[0]), 0.2, false)
	for i in int(4 + size * 6):
		var dir := Vector3(randf_range(-0.4, 0.4), 1.0, randf_range(-0.4, 0.4)).normalized()
		spawn(Kind.GLOW, at, dir * randf_range(3.0, 7.0) * (0.6 + size * 0.5), randf_range(0.4, 0.8), randf_range(0.15, 0.3) * (1.0 + size), [Palette.WHITE, Palette.SKY, Palette.CREAM][i % 3], {"gravity": 18.0, "end_size": 0.05, "fade": 0.6})


## Something ploughing through the water: a bow wave thrown out to both sides and a ring spreading
## behind it. Standing still, it only leaves slow ripples.
func wake(position: Vector3, velocity: Vector3, size: float) -> void:
	var at := Vector3(position.x, Course.WATER_LEVEL + 0.05, position.z)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var pace := clampf(flat.length() / 20.0, 0.0, 1.0)
	# Moving, rings are laid close together: small and brief, so they read as a trail, not a sheet.
	_transient(_cached("ring", Palette.CREAM, _ring_builder), Transform3D(Basis(), at), lerpf(1.4, 0.5, pace), true, Vector2(size * 0.3, size * lerpf(2.0, 0.9, pace)), 0.2, false)
	if pace < 0.1:
		return
	var ahead := flat.normalized()
	var side := ahead.cross(Vector3.UP)
	for i in int(2 + size * 2.0 * pace):
		var out := 1.0 if i % 2 == 0 else -1.0
		var push := side * out * randf_range(2.0, 5.0) + Vector3.UP * randf_range(3.0, 7.0) + flat * 0.4
		spawn(Kind.GLOW, at + ahead * size * 0.7 + side * out * size * 0.5, push * (0.5 + pace * 0.5), randf_range(0.35, 0.6), randf_range(0.15, 0.3) * (1.0 + size * 0.5), [Palette.WHITE, Palette.SKY, Palette.CREAM][i % 3], {"gravity": 18.0, "end_size": 0.05, "fade": 0.6})


static func _ring_builder(b: LowPoly, c: Color) -> void:
	for i in 16:
		var o0 := Vector3(cos(TAU * i / 16.0), 0, sin(TAU * i / 16.0))
		var o1 := Vector3(cos(TAU * (i + 1) / 16.0), 0, sin(TAU * (i + 1) / 16.0))
		b.quad(o0 * 0.8, o1 * 0.8, o1, o0, c, Vector3.UP)


## A slow column of smoke that lingers where something blew up.
func smoke_column(position: Vector3, radius: float, colors := [Palette.ASH, Palette.STONE, Palette.MIST]) -> void:
	for i in int(3 + radius * 1.5):
		var drift := Vector3(randf_range(-0.6, 0.6), randf_range(1.5, 3.0), randf_range(-0.6, 0.6))
		spawn(Kind.GLOW, position + Vector3.UP * randf() * radius, drift, randf_range(2.5, 4.0), randf_range(0.8, 1.4) * (0.5 + radius * 0.2), colors[i % colors.size()], {"end_size": 1.5 + radius * 0.8, "drag": 0.6, "fade": 0.35})


## Flames and a smoke column rising from a wreck for `duration` seconds.
func burn(position: Vector3, duration: float, size := 1.0) -> void:
	_emitters.append({"position": position, "time": duration, "size": size, "tick": 0.0})


func _update_delayed(delta: float) -> void:
	var ready: Array[Dictionary] = []
	for d in _delayed:
		d.time -= delta
		if d.time <= 0.0:
			ready.append(d)
	for d in ready:
		_delayed.erase(d)
		explosion(d.position, d.radius, d.palette, d.get("push", Vector3.ZERO))
		Sfx.play("blast_small", d.position, -4.0, randf_range(1.0, 1.3))


func _update_emitters(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for e in _emitters:
		e.time -= delta
		e.tick -= delta
		if e.tick <= 0.0:
			e.tick = 0.1
			var s: float = e.size
			var p: Vector3 = e.position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * s * 0.6
			# Fires light up what is around them, flickering.
			light_flash(e.position + Vector3.UP * s, randf_range(2.0, 3.5) * s, Palette.AMBER, 7.0 * s + 4.0)
			spawn(Kind.FLAME, p, Vector3(0, randf_range(2, 4), 0), randf_range(0.3, 0.6), randf_range(0.4, 0.8) * s, [Palette.BUTTER, Palette.PEACH, Palette.CORAL, Palette.FUNGUS][randi() % 4], {"drag": 1.0})
			if randf() < 0.6:
				spawn(Kind.GLOW, p + Vector3.UP * s, Vector3(randf_range(-0.4, 0.4), randf_range(2, 3.5), randf_range(-0.4, 0.4)), randf_range(2.0, 3.0), 0.8 * s, [Palette.ASH, Palette.STONE, Palette.DUSK][randi() % 3], {"end_size": 2.6 * s, "drag": 0.5, "fade": 0.3})
		if e.time > 0.0:
			keep.append(e)
	_emitters = keep


## Flat, unlit puffs that rise, swell and dither away: reads as smoke, not rocks.
func smoke(position: Vector3, count: int, radius := 1.0, colors := [Palette.MIST, Palette.CREAM, Palette.ASH]) -> void:
	for i in count:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.4, 1.0), randf_range(-1, 1)).normalized()
		spawn(Kind.GLOW, position + dir * radius * 0.4, dir * randf_range(1.0, 3.0) + Vector3.UP * 1.5, randf_range(0.8, 1.6), randf_range(0.5, 0.9) * (0.4 + radius * 0.15), colors[i % colors.size()], {"end_size": 0.8 + radius * 0.35, "drag": 2.2, "gravity": -1.0, "fade": 0.15})


## A per-break fountain: its axis leans up to `max_tilt` off vertical (toward `push` when there is one),
## with a random upward strength and speed scale, so no two breaks spray alike.
func _break_character(push: Vector3, max_tilt: float) -> Dictionary:
	var flat := Vector2(push.x, push.z)
	var azimuth := flat.angle() + randf_range(-1.2, 1.2) if flat.length() > 0.1 else randf() * TAU
	var tilt := randf_range(0.0, max_tilt)
	return {"axis": Vector3(sin(tilt) * cos(azimuth), cos(tilt), sin(tilt) * sin(azimuth)), "lift": randf_range(0.2, 1.3), "speed": randf_range(0.7, 1.35)}


## Chunk size relative to the base: a few big ones, the rest mostly small.
func _shard_scale(big: bool) -> float:
	return randf_range(1.6, 2.4) if big else 0.3 + 0.7 * pow(randf(), 1.6)


## `push` biases the spray along the attack: chunks fly on through, away from the shooter.
func debris(position: Vector3, count: int, materials: Array, force := 6.0, size := 0.35, push := Vector3.ZERO) -> void:
	var feel := _break_character(push, deg_to_rad(22.0))
	var axis: Vector3 = feel.axis
	var lean: float = feel.lift
	var speed_scale: float = feel.speed
	for i in count:
		var big := randf() < 0.12
		var scale := randf_range(1.5, 2.0) if big else 0.45 + 0.65 * pow(randf(), 1.5)
		var jitter := Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1))
		var dir := (jitter.normalized() * 0.6 + axis * lean).normalized() + push * 1.6
		_shard(position, dir.normalized() * randf_range(0.4, 1.0) * force * speed_scale * (0.7 if big else 1.0), scale * size * DEBRIS_SIZE, materials[randi() % materials.size()], 1.0 if big else 0.0)


## Breaks something apart: shards spread through its box and flung out from its middle (and on
## along `push`), as many and as big as the thing was. `share` < 1 when part of it stays behind.
## The count varies about 30% per break; a few chunks are big and slow, the rest small, quick and
## some skid low along the ground.
func shatter(bounds: AABB, materials: Array, push := Vector3.ZERO, share := 1.0) -> void:
	var extent := bounds.size
	var volume := maxf(extent.x * extent.y * extent.z, 0.05)
	var count := int(clampf(1.5 * pow(volume, 2.0 / 3.0) * share * randf_range(0.7, 1.3), 3.0, 70.0))
	var size := clampf(maxf(extent.x, maxf(extent.y, extent.z)) * 0.14, 0.2, 1.8)
	var center := bounds.get_center()
	var feel := _break_character(push, deg_to_rad(35.0))
	var axis: Vector3 = feel.axis
	var speed_scale: float = feel.speed
	var bigs := mini(randi_range(1, 3), count)
	for i in count:
		var big := i < bigs
		var at := bounds.position + extent * Vector3(randf(), randf(), randf())
		var skid := not big and randf() < 0.25
		var lift: float = float(feel.lift) * (0.6 if big else 1.2) * (0.15 if skid else 1.0)
		var jitter := Vector3(randf_range(-0.7, 0.7), randf_range(-0.2, 0.3), randf_range(-0.7, 0.7))
		var out := ((at - center).normalized() + axis * lift + jitter).normalized()
		if skid:
			out.y = minf(out.y, 0.12)
		out += push * 1.4
		var speed := randf_range(5.0, 12.0) * speed_scale * (0.55 if big else 1.1)
		_shard(at, out * speed, _shard_scale(big) * size, materials[randi() % materials.size()], 1.0 if big else 0.0)


## `heft` 1 for a big chunk: it lingers, tumbles slowly and drops harder.
func _shard(position: Vector3, velocity: Vector3, size: float, material: Debris, heft := 0.0) -> void:
	var life := randf_range(2.2, 3.6) if heft > 0.0 else randf_range(0.9, 2.6)
	spawn(Kind.SOLID, position, velocity, life, size, Color.WHITE, {"gravity": 22.0 + 6.0 * heft, "bounce": true, "spin": randf_range(0.7, 1.7) * (0.4 if heft > 0.0 else 1.0), "end_size": size * 0.8, "trail": DEBRIS_SMOKE, "material": material})


func sparks(position: Vector3, normal: Vector3, count: int, color := Palette.BUTTER, speed := 10.0) -> void:
	for i in count:
		var dir := (normal + Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)) * 0.8).normalized()
		spawn(Kind.FLAME, position, dir * randf_range(0.4, 1.0) * speed, randf_range(0.08, 0.25), randf_range(0.08, 0.16), color, {"gravity": 20.0})


func dust(position: Vector3, count: int, spread := 2.0, color := Palette.STRAW) -> void:
	for i in count:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.1, 0.5), randf_range(-1, 1)).normalized()
		spawn(Kind.GLOW, position + dir * randf() * spread, dir * randf_range(1.0, 4.0) * spread * 0.5, randf_range(0.5, 1.2), randf_range(0.4, 0.8), color, {"end_size": 1.4, "drag": 3.0, "gravity": -0.4, "fade": 0.1})


func spores(position: Vector3, count: int, spread := 1.5) -> void:
	for i in count:
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.2, 1.0), randf_range(-1, 1)).normalized()
		var color := [Palette.FUNGUS, Palette.BLUSH, Palette.LILAC][i % 3] as Color
		var kind := Kind.GLOW if i % 4 == 0 else Kind.SOLID
		spawn(kind, position + dir * randf() * spread, dir * randf_range(0.5, 3.0) * spread, randf_range(0.8, 1.8), randf_range(0.2, 0.5), color if kind == Kind.GLOW else Color.WHITE, {"end_size": 0.9, "drag": 2.0, "gravity": -0.3, "material": Debris.SPORE})


func shockwave(position: Vector3, radius: float, color: Color, life := 0.3) -> void:
	var mesh := _cached("ring", color, _ring_builder)
	_transient(mesh, Transform3D(Basis(), position + Vector3.UP * 0.2), life, true, Vector2(radius * 0.2, radius), 0.1, true)


static func _flash_mesh(variant: int, color: Color) -> Mesh:
	return _cached("flash%d" % variant, color, func(b: LowPoly, c: Color) -> void:
		b.prism(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO), 0.35, 2.2, 5, Palette.WHITE, 0.0)
		for i in 4:
			var petal := Basis(Vector3.BACK, i * PI * 0.5 + variant * 0.35) * Basis(Vector3.BACK, PI * 0.5)
			b.prism(Transform3D(petal, Vector3.ZERO), 0.22, 1.1, 4, c, 0.0)
		b.blob(Transform3D(), 0.5, c))


## A star-shaped muzzle flash: a forward spike and a cross of side petals, gone in a blink.
func muzzle_flash(position: Vector3, dir: Vector3, size: float, color := Palette.BUTTER) -> void:
	var variant := randi() % 3
	var mesh := _flash_mesh(variant, color)
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	_transient(mesh, Transform3D(Basis.looking_at(dir, up).scaled(Vector3.ONE * size), position), 0.06, true, Vector2.ONE, 0.6, true)


## A bright star where a round lands, turned toward the camera so it always reads full size.
func impact_star(position: Vector3, size: float, color := Palette.WHITE) -> void:
	var camera := get_viewport().get_camera_3d()
	var toward := (camera.global_position - position).normalized() if camera else Vector3.BACK
	muzzle_flash(position, toward, size, color)


## A straight glowing line, used for laser zaps and designator lines.
func beam(from: Vector3, to: Vector3, color: Color, width := 0.12, life := 0.06) -> void:
	var length := from.distance_to(to)
	if length < 0.01:
		return
	var mesh := _cached("beam", color, func(b: LowPoly, c: Color) -> void:
		b.box(Transform3D(Basis(), Vector3(0, 0, -0.5)), Vector3.ONE, c))
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT
	# Scale in the beam's own frame: `Basis.scaled` would stretch it along world axes instead.
	var basis := Basis.looking_at(to - from, up) * Basis.from_scale(Vector3(width, width, length))
	_transient(mesh, Transform3D(basis, from), life, true, Vector2.ONE, 0.5, true)


## A pulsing ring on the ground that tightens until `time` runs out: where something will land.
func marker(position: Vector3, radius: float, time: float, color := Palette.RED) -> void:
	var mesh := _cached("marker", color, func(b: LowPoly, c: Color) -> void:
		for i in 20:
			var o0 := Vector3(cos(TAU * i / 20.0), 0, sin(TAU * i / 20.0))
			var o1 := Vector3(cos(TAU * (i + 0.6) / 20.0), 0, sin(TAU * (i + 0.6) / 20.0))
			b.quad(o0 * 0.86, o1 * 0.86, o1, o0, c, Vector3.UP)
		b.box(Transform3D(), Vector3(0.5, 0.02, 0.08), c)
		b.box(Transform3D(), Vector3(0.08, 0.02, 0.5), c))
	var ground := Vector3(position.x, Course.height_at(position) + 0.15, position.z)
	var node := _transient(mesh, Transform3D(Basis(), ground), time, true, Vector2(radius * 1.6, radius), 0.97)
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
