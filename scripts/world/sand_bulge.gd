class_name SandBulge
extends Node3D
## The borer foreshadowing itself on the pit's approach: a swell of sand grows under a marked lane with a rumble and
## rings of dust, then bursts, hurting whatever still stands on it, and leaves a crater. The rim of sand it throws up
## is ground a fast tank hops off. The sand is Stage3.mounds, so the ground under the tank follows the mesh.

const WARN := 2.0 ## Seconds from the first rumble to the burst, before the difficulty's telegraph scale.
const COLLAPSE := 0.35 ## Seconds the swell takes to fall into the crater.
const DAMAGE := 22.0
const RING_EVERY := 0.3
const MESH_RADIUS := 13.0
const RINGS := 9
const SECTORS := 20
const LEFT_BEHIND := 200.0 ## Metres behind the tank at which the crater is dropped.

var site := Vector2.ZERO ## (d, u) of the centre.
var burst := false
var _age := 0.0
var _ring_wait := 0.0
var _mound := {}
var _mesh := MeshInstance3D.new()
var _stage: Stage3


func _ready() -> void:
	_stage = Course.stage as Stage3
	_mound = {"d": site.x, "u": site.y, "swell": 0.0, "crater": 0.0}
	_stage.mounds.append(_mound)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	var ground := Course.terrain_at(site.x, site.y)
	World.current.fx.marker(ground, Stage3.BULGE_RADIUS + 3.0, warn_time(), Palette.RED)
	Sfx.play("warn", ground, 0.0, 0.7)
	_rebuild()


func _exit_tree() -> void:
	_stage.mounds.erase(_mound)


func warn_time() -> float:
	return WARN * Game.telegraph_scale()


func _process(delta: float) -> void:
	_age += delta
	var ground := Course.terrain_at(site.x, site.y)
	if not burst:
		var growth := clampf(_age / warn_time(), 0.0, 1.0)
		_mound.swell = growth * growth
		_ring_wait -= delta
		if _ring_wait <= 0.0:
			_ring_wait = RING_EVERY
			_rumble(ground, growth)
		if _age >= warn_time():
			_burst(ground)
	else:
		var fall := clampf((_age - warn_time()) / COLLAPSE, 0.0, 1.0)
		_mound.swell = 1.0 - fall
		_mound.crater = fall
	if not burst or _age < warn_time() + COLLAPSE + 0.05:
		_rebuild()
	var tank := World.current.player
	if tank and World.current.rail.d - site.x > LEFT_BEHIND:
		queue_free()


## A ring of dust puffs round the swell and a growl, louder as it nears bursting.
func _rumble(ground: Vector3, growth: float) -> void:
	var world := World.current
	for i in 8:
		var angle := TAU * i / 8.0 + _age
		var at := ground + Vector3(cos(angle), 0.0, sin(angle)) * Stage3.BULGE_RADIUS
		at.y = Course.terrain_at(site.x, site.y).y + 0.3
		world.fx.dust(at, 2, 1.0 + growth, Palette.STRAW)
	var top := ground + Vector3.UP * (Stage3.BULGE_HEIGHT * growth * growth)
	world.fx.dust(top, 4, 3.0 + 3.0 * growth, Palette.STRAW)
	world.fx.debris(top, 2 + int(4.0 * growth), [Fx.Debris.DIRT], 6.0 + 6.0 * growth, 0.4)
	world.shake(0.04 + 0.12 * growth, ground)
	Sfx.play("impact", ground, -8.0 + 8.0 * growth, 0.5)


func _burst(ground: Vector3) -> void:
	burst = true
	var world := World.current
	world.fx.explosion(ground, 4.0, [Palette.STRAW, Palette.BUTTER, Palette.OCHRE])
	world.fx.shockwave(ground, Stage3.BULGE_RADIUS * 1.6, Palette.STRAW)
	world.fx.dust(ground, 24, 6.0, Palette.STRAW)
	world.fx.debris(ground, 12, [Fx.Debris.DIRT], 9.0, 0.4)
	world.shake(0.5, ground)
	Sfx.play("blast", ground, 0.0, 0.8)
	if standing_on(world.player):
		var hit := Hit.make(Hit.Kind.BLAST, DAMAGE, ground, Vector3.UP)
		hit.source = self
		world.player.take_hit(hit)


## Whether a tank sits on the swell: within its radius on the ground, not leaping over it.
func standing_on(tank: Tank) -> bool:
	if tank == null or tank.airborne:
		return false
	var ground := Course.terrain_at(site.x, site.y)
	var offset := tank.global_position - ground
	return Vector2(offset.x, offset.z).length() <= Stage3.BULGE_RADIUS


## The sand as a disc of facets over the streamed terrain, lifted by the mound's current shape.
func _rebuild() -> void:
	var b := LowPoly.new()
	var points: Array[Vector3] = []
	for ring in RINGS + 1:
		var r := MESH_RADIUS * ring / RINGS
		for sector in SECTORS:
			var angle := TAU * sector / SECTORS
			var d := site.x + cos(angle) * r
			var u := site.y + sin(angle) * r
			var p := Course.terrain_at(d, u)
			p.y += 0.08 + _mound.swell * Stage3.swell_profile(r) + _mound.crater * Stage3.crater_profile(r)
			points.append(p)
	for ring in RINGS:
		for sector in SECTORS:
			var next := (sector + 1) % SECTORS
			var a := points[ring * SECTORS + sector]
			var c := points[ring * SECTORS + next]
			var e := points[(ring + 1) * SECTORS + sector]
			var f := points[(ring + 1) * SECTORS + next]
			var shade := Palette.PEACH.lerp(Palette.OCHRE, _mound.crater * 0.6)
			# The swelling sand glows in hot rings, strongest at the centre, so it reads from the lane ahead.
			shade = shade.lerp(Palette.RED if ring % 2 == 0 else Palette.CORAL, (1.0 - float(ring) / RINGS) * minf(_mound.swell * 6.0, 1.0) * 0.85)
			shade = shade.lerp(Palette.CREAM, 0.2 * float((ring + sector) % 2) * (1.0 - _mound.swell))
			shade = shade.lerp(Palette.CREAM if ring == 4 else Palette.OCHRE.darkened(0.25), _mound.crater * (0.8 if ring == 4 else 0.7 * (1.0 - float(ring) / 4.0)) * (1.0 if ring <= 4 else 0.0))
			b.tri(a, c, f, shade, Vector3.UP)
			b.tri(a, f, e, shade, Vector3.UP)
	if not burst:
		# A glowing geyser stands up out of the swell and climbs with it, a column that shows against the horizon.
		var centre := Course.terrain_at(site.x, site.y)
		var height := 2.0 + 14.0 * sqrt(_mound.swell)
		b.glow = true
		b.prism(Transform3D(Basis.IDENTITY, centre + Vector3.UP * _mound.swell * Stage3.BULGE_HEIGHT * 0.8), 2.2, height, 6, Palette.HOT, 1.0)
	_mesh.mesh = b.mesh()
