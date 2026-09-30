class_name GnatSwarm
extends Enemy
## A dense cloud of tiny micro-drones. It is a CIWS saturation target, but its attack is a small
## ordinary blast: `warhead` is deliberately false, so ERA never decides it.

enum State { CLOUD, TELEGRAPH, ATTACK }
const TELEGRAPH_TIME := 0.7

var state := State.CLOUD
var attack_timer := 1.8
var swarm_size := 32
var _state_time := 0.0
var _phase := randf() * TAU
var _rotors: Array[MeshInstance3D] = []

func _init() -> void:
	super()
	max_hp = 10.0
	hp = max_hp
	radius = 2.4
	center_height = 0.8
	flying = true
	interceptable = true
	stabbable = true
	score = 180
	debris = [Fx.Debris.METAL, Fx.Debris.PAINT]
	weakness = {Hit.Kind.BLAST: 3.0, Hit.Kind.FIRE: 2.0, Hit.Kind.TAIL: 3.0}

func damage_multiplier(hit: Hit) -> float:
	var multiplier := super(hit)
	# A cloud takes longer to clear under the laser, deliberately making CIWS heat visible.
	if hit.kind == Hit.Kind.LASER:
		multiplier *= 0.35
	return multiplier

func build() -> void:
	for i in swarm_size:
		var drone := MeshInstance3D.new()
		var b := LowPoly.new()
		b.glow = true
		var a := TAU * i / swarm_size
		var offset := Vector3(cos(a) * (1.0 + (i % 4) * 0.35), sin(a * 2.3) * 1.3, sin(a) * (1.0 + (i % 5) * 0.25))
		b.box(Transform3D(Basis(Vector3.UP, a), offset), Vector3(0.32, 0.08, 0.08), Palette.HOT)
		b.blob(Transform3D(Basis(), offset + Vector3.UP * 0.08), 0.12, Palette.BUTTER)
		drone.mesh = b.mesh()
		model.add_child(drone)
		_rotors.append(drone)
	var sound := Sfx.loop("gnat_whine", self, -8.0)
	if sound:
		sound.pitch_scale = randf_range(1.05, 1.25)

func behave(delta: float) -> void:
	_state_time += delta
	var tank := player()
	if tank == null:
		return
	for i in _rotors.size():
		var phase := _phase + i * 0.37
		_rotors[i].position += Vector3(sin(age * 4.0 + phase), cos(age * 3.0 + phase), sin(age * 2.5 + phase)) * delta * 0.35
	if state == State.CLOUD:
		var target := tank.global_position + Vector3(0, 3.5 + sin(age * 2.0) * 1.2, 8.0)
		velocity = velocity.move_toward((target - global_position).limit_length(18.0), 22.0 * delta)
		global_position += velocity * delta
		model.rotation.y += delta * 1.3
		attack_timer -= delta
		if attack_timer <= 0.0 and global_position.distance_to(tank.global_position) < 28.0:
			state = State.TELEGRAPH
			_state_time = 0.0
			Sfx.play("gnat_warn", global_position)
	elif state == State.TELEGRAPH:
		velocity = velocity.move_toward(Vector3.ZERO, 25.0 * delta)
		model.scale = Vector3.ONE * (1.0 + sin(_state_time * 30.0) * 0.12)
		World.current.fx.spores(global_position, 8, radius)
		if _state_time >= TELEGRAPH_TIME:
			_attack(tank)
	elif state == State.ATTACK:
		if global_position.distance_to(tank.global_position) < 7.0 and not tank.dead:
			var hit := Hit.make(Hit.Kind.BLAST, 6.0, tank.hit_center(), (tank.global_position - global_position).normalized())
			hit.source = self
			hit.warhead = false
			tank.take_hit(hit)
		state = State.CLOUD
		attack_timer = 2.4
		_state_time = 0.0

func _attack(tank: Tank) -> void:
	state = State.ATTACK
	_state_time = 0.0
	var hit := Hit.make(Hit.Kind.BLAST, 6.0, tank.hit_center(), (tank.global_position - global_position).normalized())
	hit.source = self
	hit.warhead = false
	if global_position.distance_to(tank.global_position) < 8.0:
		tank.take_hit(hit)
	World.current.fx.impact_star(tank.hit_center(), 1.7, Palette.HOT)
	Sfx.play("gnat_attack", global_position)

func interrupt() -> void:
	super()
	if state == State.TELEGRAPH:
		state = State.CLOUD
		attack_timer = 1.0

func on_death(hit: Hit) -> void:
	World.current.fx.sparks(hit_center(), Vector3.UP, 25, Palette.BUTTER)
	World.current.fx.spores(hit_center(), 18, 2.0)
	Sfx.play("gnat_pop", global_position)
	super(hit)
