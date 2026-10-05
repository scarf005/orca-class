class_name Spitter
extends Enemy
## Rooted fungal mortar. Its sac swells and glows, then it lobs spore shells onto marked circles
## around where the tank will be.

const RANGE := Vector2(-15.0, 100.0) ## Fires while the tank is this far behind/ahead along the road.
const SPORE_TRAIL := Palette.CREAM ## Pale spore cloud streamed behind a shell.

var _timer := 1.5
var _telegraph := 0.0
var _sac: MeshInstance3D
var _stalk := Node3D.new()
var _hard := false


func _init() -> void:
	super()
	max_hp = 40.0
	hp = 40.0
	radius = 1.6
	center_height = 2.4
	stabbable = true
	can_stagger = true
	score = 350
	debris = [Fx.Debris.FLESH, Fx.Debris.SPORE]
	weakness = {Hit.Kind.FIRE: 2.5, Hit.Kind.TAIL: 1.5}


func build() -> void:
	_hard = Game.difficulty == Game.Difficulty.HARD
	global_position.y = Course.height_at(global_position)
	var base_mesh := MeshInstance3D.new()
	base_mesh.mesh = ActorMeshes.mesh("spitter", "base")
	model.add_child(base_mesh)
	model.add_child(_stalk)
	var stalk_mesh := MeshInstance3D.new()
	stalk_mesh.mesh = ActorMeshes.mesh("spitter", "stalk")
	_stalk.add_child(stalk_mesh)
	_sac = MeshInstance3D.new()
	_sac.mesh = ActorMeshes.mesh("spitter", "sac")
	_sac.position = Vector3(0, 2.8, 0)
	_stalk.add_child(_sac)


func telegraphing() -> bool:
	return _telegraph > 0.0


func behave(delta: float) -> void:
	var tank := player()
	if tank == null:
		return
	var along := Course.to_course(global_position).x - Course.to_course(tank.global_position).x
	var local := model.global_transform.affine_inverse() * tank.global_position
	_stalk.rotation.x = lerpf(_stalk.rotation.x, -0.25, delta)
	_stalk.rotation.y = lerp_angle(_stalk.rotation.y, atan2(-local.x, -local.z), 2.0 * delta)
	_stalk.rotation.z = sin(age * 1.7) * 0.06
	if is_staggered():
		_telegraph = 0.0
		_sac.scale = _sac.scale.lerp(Vector3.ONE * 0.8, 6.0 * delta)
		return
	if _telegraph > 0.0:
		_telegraph -= delta
		var k := 1.0 - _telegraph / (0.8 * Game.telegraph_scale())
		_sac.scale = Vector3.ONE * (1.0 + k * 0.5 + sin(age * 30.0) * 0.05)
		if fmod(_telegraph, 0.16) < 0.08:
			flash()
		if _telegraph <= 0.0:
			_volley(tank)
		return
	_sac.scale = _sac.scale.lerp(Vector3.ONE, 4.0 * delta)
	_timer -= delta
	if _timer <= 0.0 and along > RANGE.x and along < RANGE.y:
		_telegraph = 0.8 * Game.telegraph_scale()
		_timer = (2.2 if _hard else 2.8) + randf() * 0.6
		Sfx.play("squelch", global_position, 0.0, 0.6)


func _volley(tank: Tank) -> void:
	var world := World.current
	var from := _sac.global_position + Vector3.UP * 0.8
	var shots := 4 if _hard else 3
	for i in shots:
		var flight := (1.6 + i * 0.15) * Game.telegraph_scale()
		var target := tank.global_position + tank.velocity * flight
		if _hard:
			target += tank.global_basis.x * (i - (shots - 1) * 0.5) * 6.0
		elif i > 0:
			target += Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
		target.y = Course.height_at(target)
		var velocity_out := (target - from) / flight
		velocity_out.y += 0.5 * 20.0 * flight
		var mortar := world.spawn_projectile(Team.ENEMY, from, velocity_out, "mortar", Palette.FUNGUS)
		mortar.gravity = 20.0
		mortar.hit = Hit.make(Hit.Kind.SPORE, 0.0, from)
		mortar.hit.source = self
		mortar.blast_radius = 3.2
		mortar.blast_damage = 20.0
		mortar.blast_colors = [Palette.WHITE, Palette.BLUSH, Palette.FUNGUS, Palette.LILAC]
		mortar.interceptable = true
		mortar.intercept_hp = 1.0
		mortar.life = flight + 1.0
		mortar.trail = SPORE_TRAIL
		mortar.impacted.connect(func(_p: Projectile, point: Vector3, _t: Entity) -> void: Hazard.spawn(point, 2.8, 2.0, 7.0))
		world.fx.marker(target, 3.2, flight, Palette.FUNGUS)
	world.fx.spores(from, 12, 1.2)
	Sfx.play("spore", from)
