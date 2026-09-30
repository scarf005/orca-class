class_name CanalLeech
extends Enemy
## A flat pink leech that stays below the waterline, races in as bubbles, and clamps to the hull.
## It cannot acquire a tank on a dry dike. While latched it drains armour and slows strafing.

enum State { HIDDEN, TELEGRAPH, LATCHED }
const TELEGRAPH_TIME := 0.65
const LATCH_DPS := 2.6

var state := State.HIDDEN
var latched := false
var _state_time := 0.0
var _cooldown := 0.0
var _body: MeshInstance3D
var _eye_material := StandardMaterial3D.new()

func _init() -> void:
	super()
	max_hp = 7.0
	hp = max_hp
	radius = 0.9
	center_height = 0.3
	stabbable = true
	score = 220
	debris = [Fx.Debris.FLESH, Fx.Debris.SPORE]
	weakness = {Hit.Kind.BLAST: 1.7, Hit.Kind.TAIL: 3.0, Hit.Kind.FIRE: 1.5}
	despawn_behind = 15.0

func build() -> void:
	var b := LowPoly.new()
	b.flesh = true
	b.blob(Transform3D(Basis().scaled(Vector3(1.0, 0.3, 1.8)), Vector3(0, 0.22, 0)), 0.8, Palette.FUNGUS, 1, 0.25, 9)
	b.blob(Transform3D(Basis(), Vector3(0, 0.28, -0.55)), 0.35, Palette.BLUSH, 0, 0.15, 2)
	b.glow = true
	b.box(Transform3D(Basis(), Vector3(0, 0.46, -0.7)), Vector3(0.15, 0.08, 0.12), Palette.RED)
	_body = MeshInstance3D.new()
	_body.mesh = b.mesh()
	model.add_child(_body)
	_eye_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_material.albedo_color = Palette.RED
	_body.material_override = _eye_material
	var surface := Water.surface_at(global_position)
	if surface > -INF:
		global_position.y = surface - 0.38

func _wet_at(point: Vector3) -> bool:
	return Water.surface_at(point) > Course.height_at(point) + 0.04

func behave(delta: float) -> void:
	_state_time += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	var tank := player()
	if tank == null:
		return
	if state == State.HIDDEN:
		var to_tank := tank.global_position - global_position
		to_tank.y = 0.0
		if to_tank.length() < 34.0 and _wet_at(tank.global_position) and _wet_at(global_position) and _cooldown <= 0.0:
			state = State.TELEGRAPH
			_state_time = 0.0
			Sfx.play("leech_ripple", global_position)
			World.current.fx.marker(tank.global_position, 1.2, TELEGRAPH_TIME, Palette.TEAL)
	elif state == State.TELEGRAPH:
		var target := tank.global_position
		if not _wet_at(target):
			state = State.HIDDEN
			_state_time = 0.0
			return
		var direction := (target - global_position)
		direction.y = 0.0
		global_position += direction.normalized() * 18.0 * delta
		var surface := Water.surface_at(global_position)
		if surface > -INF:
			global_position.y = surface - 0.2
		_body.scale = Vector3.ONE * (1.0 + sin(_state_time * 35.0) * 0.16)
		World.current.fx.splash(global_position, 0.7, maxf(surface, global_position.y))
		if _state_time >= TELEGRAPH_TIME:
			_latch(tank)
	elif state == State.LATCHED:
		if tank.dead or not is_instance_valid(tank):
			detach()
			return
		global_position = tank.global_position + Vector3(0, 0.55, 1.8)
		var hit := Hit.make(Hit.Kind.BULLET, LATCH_DPS * delta, tank.hit_center(), Vector3.UP)
		hit.caliber = 0
		hit.source = self
		tank.take_hit(hit)
		World.current.fx.sparks(global_position, Vector3.UP, 2, Palette.FUNGUS)
		if fmod(age, 0.5) < delta:
			Sfx.play("leech_latch", global_position)

func _latch(tank: Tank) -> void:
	if not _wet_at(tank.global_position):
		state = State.HIDDEN
		_cooldown = 1.0
		return
	state = State.LATCHED
	latched = true
	set_meta("leech_latched", true)
	global_position = tank.global_position + Vector3(0, 0.55, 1.8)
	World.current.fx.splash(global_position, 1.2, Water.surface_at(global_position))
	Sfx.play("leech_latch", global_position)

func detach() -> void:
	latched = false
	set_meta("leech_latched", false)
	state = State.HIDDEN
	_cooldown = 1.2
	_state_time = 0.0

func interrupt() -> void:
	super()
	if latched:
		detach()

func on_death(hit: Hit) -> void:
	latched = false
	set_meta("leech_latched", false)
	World.current.fx.splash(global_position, 1.5, maxf(Water.surface_at(global_position), global_position.y))
	Sfx.play("leech_pop", global_position)
	super(hit)
