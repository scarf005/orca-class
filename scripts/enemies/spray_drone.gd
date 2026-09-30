class_name SprayDrone
extends Enemy
## Agricultural hexacopter that paints one six-second corrosive strip across the lane.

enum State { FLY, TELEGRAPH, SPRAY, EXIT }
const TELEGRAPH_TIME := 0.8
const MIST_TIME := 6.0

var state := State.FLY
var mist_active := false
var mist_life := 0.0
var _state_time := 0.0
var _attack_timer := 2.0
var _lane := 0.0
var _rotors: Array[Node3D] = []
var _nozzle_material := StandardMaterial3D.new()

func _init() -> void:
	super()
	max_hp = 8.0
	hp = max_hp
	radius = 1.3
	center_height = 7.0
	flying = true
	interceptable = true
	stabbable = true
	score = 250
	trails = true
	weakness = {Hit.Kind.BLAST: 1.5, Hit.Kind.FIRE: 1.8, Hit.Kind.TAIL: 1.5}
	debris = [Fx.Debris.METAL, Fx.Debris.PAINT]

func build() -> void:
	var b := LowPoly.new()
	b.box(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3.ZERO), Vector3(2.8, 0.18, 0.22), Palette.SLATE)
	b.box(Transform3D(Basis(Vector3.UP, -PI * 0.25), Vector3.ZERO), Vector3(2.8, 0.18, 0.22), Palette.SLATE)
	b.blob(Transform3D(Basis(), Vector3(0, 0.2, 0)), 0.5, Palette.TEAL, 0, 0.2, 3)
	b.box(Transform3D(Basis(), Vector3(0, -0.25, 0.25)), Vector3(1.7, 0.12, 0.35), Palette.OCHRE)
	b.tube(Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0, 0)), Vector3(0, -0.45, 0.1)), 0.06, 0.9, 6, Palette.INK)
	var body := MeshInstance3D.new()
	body.mesh = b.mesh()
	model.add_child(body)
	for i in 6:
		var rotor := Node3D.new()
		var a := TAU * i / 6.0
		rotor.position = Vector3(cos(a), 0.15, sin(a)) * 1.0
		var r := LowPoly.new()
		r.glow = true
		r.prism(Transform3D(), 0.25, 0.04, 6, Palette.MIST)
		var instance := MeshInstance3D.new()
		instance.mesh = r.mesh()
		rotor.add_child(instance)
		model.add_child(rotor)
		_rotors.append(rotor)
	var nozzles := LowPoly.new()
	nozzles.glow = true
	nozzles.box(Transform3D(), Vector3(1.5, 0.18, 0.18), Palette.CYAN)
	var nozzle_mesh := MeshInstance3D.new()
	nozzle_mesh.mesh = nozzles.mesh()
	nozzle_mesh.position = Vector3(0, -0.5, -0.1)
	model.add_child(nozzle_mesh)
	_nozzle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_nozzle_material.albedo_color = Palette.CYAN
	nozzle_mesh.material_override = _nozzle_material
	_lane = Course.to_course(global_position).y
	var sound := Sfx.loop("spray_drone", self, -10.0)
	if sound:
		sound.pitch_scale = randf_range(0.95, 1.1)

func behave(delta: float) -> void:
	_state_time += delta
	for rotor in _rotors:
		rotor.rotation.y += delta * 55.0
	var tank := player()
	if tank == null:
		return
	if state == State.FLY:
		var c := Course.to_course(global_position)
		_lane = lerpf(_lane, Course.to_course(tank.global_position).y + sin(age * 1.9) * 10.0, delta * 0.4)
		var target := Course.to_world(World.current.rail.d + tank.course_offset + 32.0, _lane)
		target.y = Course.height_at(target) + 8.0
		velocity = velocity.move_toward((target - global_position).limit_length(23.0), 28.0 * delta)
		global_position += velocity * delta
		model.look_at(global_position + velocity, Vector3.UP)
		_attack_timer -= delta
		if _attack_timer <= 0.0 and global_position.distance_to(tank.global_position) < 75.0:
			state = State.TELEGRAPH
			_state_time = 0.0
			Sfx.play("spray_warn", global_position)
	elif state == State.TELEGRAPH:
		velocity = velocity.move_toward(Vector3.ZERO, 30.0 * delta)
		_nozzle_material.albedo_color = Palette.WHITE if fmod(_state_time, 0.12) < 0.06 else Palette.CYAN
		if _state_time >= TELEGRAPH_TIME:
			_spray(tank)
	elif state == State.SPRAY:
		mist_life = maxf(0.0, mist_life - delta)
		_nozzle_material.albedo_color = Palette.FUNGUS
		if mist_life <= 0.0:
			mist_active = false
			state = State.EXIT
			_state_time = 0.0
	elif state == State.EXIT:
		_nozzle_material.albedo_color = Palette.CYAN
		global_position += Vector3(0, 5.0, 0) * delta
		if _state_time > 1.5:
			despawn()

func _spray(tank: Tank) -> void:
	state = State.SPRAY
	_state_time = 0.0
	mist_active = true
	mist_life = MIST_TIME
	var direction := velocity if velocity.length() > 0.2 else (tank.global_position - global_position)
	var mist := SprayMist.spawn(global_position + Vector3.DOWN * 6.5, direction)
	mist.life = MIST_TIME
	World.current.fx.spores(global_position + Vector3.DOWN * 5.0, 25, 4.0)
	Sfx.play("spray_full", global_position)

func on_death(hit: Hit) -> void:
	World.current.fx.spores(hit_center(), 18, 2.2)
	Sfx.play("spray_death", global_position)
	super(hit)
