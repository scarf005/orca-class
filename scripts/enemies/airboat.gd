class_name Airboat
extends Enemy
## Fast fungal airboat. It is constrained to a wet course, sprays a wake, and fires a low 12.7 mm burst.
## The rear fan cage is a true module: breaking it strands the boat immediately.

enum State { APPROACH, TELEGRAPH, BURST, STRANDED }

const TELEGRAPH_TIME := 0.75
const SPEED := 24.0
const FAN_HP := 5.0
const BURST_COUNT := 8

var state := State.APPROACH
var fan_hp := FAN_HP
var fan_destroyed := false
var _state_time := 0.0
var _attack_timer := 1.6
var _burst := 0
var _burst_timer := 0.0
var _lane := 0.0
var _hull: Node3D
var _gun := Node3D.new()
var _muzzle := Node3D.new()
var _fan := Node3D.new()
var _fan_material := StandardMaterial3D.new()

func _init() -> void:
	super()
	max_hp = 24.0
	hp = max_hp
	radius = 2.2
	center_height = 1.2
	stabbable = true
	score = 600
	wreck_on_death = true
	debris = [Fx.Debris.METAL, Fx.Debris.ARMOR, Fx.Debris.PAINT]
	weakness = {Hit.Kind.SHELL: 1.15, Hit.Kind.RAM: 1.4, Hit.Kind.TAIL: 1.2}

func build() -> void:
	_hull = Node3D.new()
	model.add_child(_hull)
	var b := LowPoly.new()
	b.box(Transform3D(Basis(Vector3.RIGHT, -0.08), Vector3(0, 0.65, 0)), Vector3(3.5, 0.65, 4.3), Palette.SLATE, Palette.TEAL)
	b.box(Transform3D(Basis(), Vector3(0, 1.15, -0.35)), Vector3(2.7, 0.75, 1.6), Palette.DUSK, Palette.MAUVE)
	b.gable(Transform3D(Basis(), Vector3(0, 1.55, 0.2)), Vector3(2.3, 0.55, 1.5), Palette.CORAL, Palette.RED)
	b.box(Transform3D(Basis(), Vector3(0, 1.7, 1.65)), Vector3(2.4, 0.22, 0.22), Palette.OCHRE)
	var hull_mesh := MeshInstance3D.new()
	hull_mesh.mesh = b.mesh()
	_hull.add_child(hull_mesh)
	# The gunner is a separate readable silhouette over the bow.
	_gun.position = Vector3(0, 1.55, -1.1)
	_hull.add_child(_gun)
	var gun_mesh := LowPoly.new()
	gun_mesh.box(Transform3D(), Vector3(0.55, 0.5, 0.65), Palette.FUNGUS)
	gun_mesh.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(0, 0, -0.35)), 0.1, 1.8, 6, Palette.INK)
	var gun_instance := MeshInstance3D.new()
	gun_instance.mesh = gun_mesh.mesh()
	_gun.add_child(gun_instance)
	_muzzle.position = Vector3(0, 0, -1.35)
	_gun.add_child(_muzzle)
	# Rear fan cage: blades and a hot centre make the module legible in a screenshot.
	_fan.position = Vector3(0, 1.15, 1.95)
	_hull.add_child(_fan)
	var fan_mesh := LowPoly.new()
	fan_mesh.box(Transform3D(), Vector3(2.0, 1.9, 0.18), Palette.INK)
	fan_mesh.box(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO), Vector3(0.18, 1.8, 1.8), Palette.CORAL)
	fan_mesh.glow = true
	fan_mesh.prism(Transform3D(), 0.38, 0.12, 8, Palette.BUTTER)
	var fan_instance := MeshInstance3D.new()
	fan_instance.mesh = fan_mesh.mesh()
	_fan.add_child(fan_instance)
	_fan_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fan_material.albedo_color = Palette.BUTTER
	fan_instance.material_override = _fan_material
	_lane = Course.to_course(global_position).y
	_keep_on_water()
	_buzz()

func _buzz() -> void:
	var sound := Sfx.loop("airboat_roar", self, -7.0)
	if sound:
		sound.pitch_scale = randf_range(0.9, 1.1)

func _is_water() -> bool:
	var ground := Course.height_at(global_position)
	return Water.surface_at(global_position) > ground + 0.02

func _keep_on_water() -> void:
	if _is_water():
		global_position.y = Water.surface_at(global_position) - 0.15
		return
	# A boat never drives onto a dry dike: look in the stage's canal or nearest wet lateral.
	var c := Course.to_course(global_position)
	var candidates := [-30.0, -24.0, 0.0, 24.0, 30.0]
	for u in candidates:
		var p := Course.to_world(c.x, u)
		var surface := Water.surface_at(p)
		if surface > Course.height_at(p) + 0.02:
			global_position = Vector3(p.x, surface - 0.15, p.z)
			_lane = u
			return
	state = State.STRANDED
	velocity = Vector3.ZERO

func behave(delta: float) -> void:
	_state_time += delta
	_keep_on_water()
	var tank := player()
	if tank == null or state == State.STRANDED:
		return
	var c := Course.to_course(global_position)
	_lane = lerpf(_lane, clampf(Course.to_course(tank.global_position).y + sin(age * 1.7) * 12.0, -42.0, 42.0), delta * 0.35)
	if state == State.APPROACH:
		var target_d := World.current.rail.d + tank.course_offset + 42.0
		var target := Course.to_world(target_d, _lane)
		var surface := Water.surface_at(target)
		if surface <= Course.height_at(target) + 0.02:
			# The gunboat follows the canal rather than steering toward a dry tank on a dike.
			target = Course.to_world(target_d, -30.0)
			surface = Water.surface_at(target)
		if surface <= Course.height_at(target) + 0.02:
			velocity = Vector3.ZERO
			return
		target.y = surface - 0.15
		var direction := target - global_position
		if direction.length() > 0.1:
			velocity = velocity.move_toward(direction.normalized() * SPEED, 20.0 * delta)
			global_position += velocity * delta
			_keep_on_water()
			if velocity.length() > 0.1:
				model.look_at(global_position + Vector3(velocity.x, 0, velocity.z), Vector3.UP)
		_attack_timer -= delta
		if _attack_timer <= 0.0 and global_position.distance_to(tank.global_position) < 90.0:
			state = State.TELEGRAPH
			_state_time = 0.0
			Sfx.play("airboat_warn", global_position)
	elif state == State.TELEGRAPH:
		velocity = velocity.move_toward(Vector3.ZERO, 25.0 * delta)
		_flash_fan()
		if _state_time >= TELEGRAPH_TIME:
			state = State.BURST
			_state_time = 0.0
			_burst = BURST_COUNT
			_burst_timer = 0.0
	elif state == State.BURST:
		_attack_burst(delta, tank)

func _flash_fan() -> void:
	_fan_material.albedo_color = Palette.WHITE if fmod(_state_time, 0.14) < 0.07 else Palette.HOT

func _attack_burst(delta: float, tank: Tank) -> void:
	_burst_timer -= delta
	if _burst <= 0:
		state = State.APPROACH
		_attack_timer = 2.2
		_state_time = 0.0
		_fan_material.albedo_color = Palette.BUTTER
		return
	if _burst_timer > 0.0:
		return
	_burst -= 1
	_burst_timer = 0.1
	var wanted := tank.hit_center()
	# Keep 12.7 mm as a genuine BULLET. Tank.take_hit then applies small-arms armour and sensor rules.
	var shot := fire_at("orb", _muzzle.global_position, wanted, 115.0, 4.0, Palette.HOT, Muzzle.AUTO)
	shot.hit.caliber = 12
	shot.hit.position = tank.model.sensor_position("laser") if tank.modules.laser_online() else tank.model.sensor_position("fcs")
	shot.hit.direction = (shot.hit.position - _muzzle.global_position).normalized()
	Sfx.play("airboat_gun", _muzzle.global_position, -3.0, randf_range(0.9, 1.1))

func destroy_fan() -> void:
	if fan_destroyed:
		return
	fan_destroyed = true
	fan_hp = 0.0
	state = State.STRANDED
	velocity = Vector3.ZERO
	_fan_material.albedo_color = Palette.ASH
	World.current.fx.sparks(_fan.global_position, Vector3.BACK, 18, Palette.BUTTER)
	World.current.fx.smoke_column(_fan.global_position, 1.2, [Palette.INK, Palette.ASH])
	Sfx.play("airboat_fan", _fan.global_position)
	World.current.award(150, global_position, false)

func on_damaged(hit: Hit, amount: float) -> void:
	super(hit, amount)
	if fan_destroyed or dead:
		return
	var local := model.global_transform.affine_inverse() * hit.position
	if local.z > 1.25 and local.y > 0.0:
		fan_hp -= amount
		if fan_hp <= 0.0:
			destroy_fan()

func on_death(hit: Hit) -> void:
	World.current.fx.splash(global_position, 3.0, maxf(Water.surface_at(global_position), global_position.y))
	Sfx.play("airboat_death", global_position)
	super(hit)
