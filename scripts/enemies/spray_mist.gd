class_name SprayMist
extends Node3D
## Rectangular corrosive spore mist. Unlike a radial Hazard, its local rectangle is the counter-readable strip.

var width := 7.0
var length := 42.0
var life := 6.0
var damage_per_second := 7.0
var _tick := 0.0

static func spawn(at: Vector3, direction: Vector3) -> SprayMist:
	var mist := SprayMist.new()
	World.current.add_child(mist)
	mist.global_position = at
	var flat := Vector3(direction.x, 0.0, direction.z).normalized()
	if flat.length() > 0.1:
		mist.global_basis = Basis.looking_at(flat, Vector3.UP)
	return mist

func inside_strip(point: Vector3) -> bool:
	var local := global_transform.affine_inverse() * point
	return absf(local.x) <= width and absf(local.z) <= length * 0.5 and absf(local.y) <= 4.0

func _ready() -> void:
	# A low strip plus staggered translucent puffs hides the ground across its whole length.
	var base := MeshInstance3D.new()
	var base_poly := LowPoly.new()
	base_poly.glow = true
	base_poly.box(Transform3D(Basis(), Vector3(0, 0.08, 0)), Vector3(width * 2.0, 0.04, length), Palette.MAUVE)
	base.mesh = base_poly.mesh()
	base.transparency = 0.65
	add_child(base)
	for i in 9:
		var puff := MeshInstance3D.new()
		var puff_poly := LowPoly.new()
		puff_poly.glow = true
		var z := -length * 0.45 + i * length / 8.0
		puff_poly.blob(Transform3D(Basis(), Vector3(sin(i * 2.1) * width * 0.65, 0.35 + (i % 3) * 0.12, z)), 0.8 + (i % 2) * 0.25, Palette.MIST, 0, 0.25, i)
		puff.mesh = puff_poly.mesh()
		puff.transparency = 0.7
		add_child(puff)
	ActorLayer.mark(self, ActorLayer.HOSTILE)

func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.12
	World.current.fx.spores(global_position + Vector3.UP * 0.7, 5, width * 0.7)
	var tank := World.current.player
	if tank and not tank.dead and inside_strip(tank.hit_center()):
		var hit := Hit.make(Hit.Kind.SPORE, damage_per_second * 0.12, tank.hit_center(), Vector3.UP)
		hit.source = self
		tank.take_hit(hit)
