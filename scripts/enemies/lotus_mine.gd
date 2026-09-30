class_name LotusMine
extends Enemy
## A floating, spiked water-lily mine. It arms only near a wet tank, then throws a shaped-looking
## upward blast that is ordinary BLAST damage: ERA is never consulted.

enum State { FLOATING, ARMING, ARMED }
const ARM_TIME := 0.85
const BLAST_RADIUS := 5.0

var state := State.FLOATING
var armed := false
var detonated := false
var _state_time := 0.0
var _leaf_material := StandardMaterial3D.new()

func _init() -> void:
	super()
	max_hp = 6.0
	hp = max_hp
	radius = 1.5
	center_height = 0.15
	stabbable = false
	score = 300
	debris = [Fx.Debris.FLESH, Fx.Debris.METAL]
	weakness = {Hit.Kind.BULLET: 1.4, Hit.Kind.BLAST: 1.8, Hit.Kind.FIRE: 1.6}
	despawn_behind = 12.0

func build() -> void:
	var leaf := LowPoly.new()
	leaf.glow = true
	leaf.prism(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), 1.5, 0.12, 8, Palette.TEAL, 0.9)
	for i in 8:
		var a := TAU * i / 8.0
		leaf.prism(Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * 0.9, 0.1, sin(a) * 0.9)), 0.16, 0.65, 4, Palette.CORAL, 0.0)
	leaf.blob(Transform3D(Basis(), Vector3(0, 0.45, 0)), 0.38, Palette.FUNGUS, 0, 0.15, 8)
	var mesh := MeshInstance3D.new()
	mesh.mesh = leaf.mesh()
	model.add_child(mesh)
	_leaf_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_leaf_material.albedo_color = Palette.TEAL
	mesh.material_override = _leaf_material
	_keep_afloat()

func _keep_afloat() -> bool:
	var surface := Water.surface_at(global_position)
	if surface <= Course.height_at(global_position) + 0.02:
		return false
	global_position.y = surface + 0.04 + sin(age * 2.2) * 0.08
	return true

func behave(delta: float) -> void:
	_state_time += delta
	if not _keep_afloat():
		state = State.FLOATING
		armed = false
		return
	var tank := player()
	if tank == null or detonated:
		return
	if state == State.FLOATING and global_position.distance_to(tank.global_position) < 9.0:
		state = State.ARMING
		_state_time = 0.0
		Sfx.play("lotus_tick", global_position)
	elif state == State.ARMING:
		_leaf_material.albedo_color = Palette.WHITE if fmod(_state_time, 0.16) < 0.08 else Palette.FUNGUS
		World.current.fx.marker(global_position, BLAST_RADIUS, maxf(ARM_TIME - _state_time, 0.0), Palette.HOT)
		if _state_time >= ARM_TIME:
			state = State.ARMED
			armed = true
			_state_time = 0.0
	elif state == State.ARMED:
		_leaf_material.albedo_color = Palette.RED if fmod(_state_time, 0.12) < 0.06 else Palette.HOT
		if global_position.distance_to(tank.global_position) < 5.0:
			detonate(tank)

func detonate(tank: Tank) -> void:
	if detonated:
		return
	detonated = true
	var center := global_position + Vector3.UP * 0.8
	World.current.fx.explosion(center, BLAST_RADIUS, [Palette.WHITE, Palette.AMBER, Palette.HOT, Palette.CORAL])
	Sfx.play("lotus_blast", center)
	var hit := Hit.make(Hit.Kind.BLAST, 28.0, center, Vector3.UP)
	hit.source = self
	hit.warhead = false
	if tank and tank.hit_center().distance_to(center) < BLAST_RADIUS:
		tank.take_hit(hit)
	World.current.award(80, center, false)
	despawn()

func on_death(hit: Hit) -> void:
	World.current.fx.splash(global_position, 2.0, maxf(Water.surface_at(global_position), global_position.y))
	Sfx.play("lotus_pop", global_position)
	super(hit)
