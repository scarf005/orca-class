class_name SnailEggCluster
extends Enemy
## Pink apple-snail egg stalks. Proximity makes the whole cluster brighten and hatch three crawlers.

enum State { DORMANT, SWELL, HATCHED }
const TELEGRAPH_TIME := 1.4
const TRIGGER_DISTANCE := 16.0

var state := State.DORMANT
var hatch_count := 0
var _state_time := 0.0
var _eggs: Array[MeshInstance3D] = []
var _egg_materials: Array[StandardMaterial3D] = []

func _init() -> void:
	super()
	max_hp = 12.0
	hp = max_hp
	radius = 1.3
	center_height = 1.1
	stabbable = true
	score = 280
	debris = [Fx.Debris.FLESH, Fx.Debris.PAINT]
	weakness = {Hit.Kind.FIRE: 2.2, Hit.Kind.BULLET: 1.2, Hit.Kind.TAIL: 1.5}
	despawn_behind = 20.0

func build() -> void:
	var base := LowPoly.new()
	base.prism(Transform3D(), 1.2, 0.28, 7, Palette.MAUVE, 0.8)
	var base_mesh := MeshInstance3D.new()
	base_mesh.mesh = base.mesh()
	model.add_child(base_mesh)
	for i in 7:
		var a := TAU * i / 7.0
		var stalk := Node3D.new()
		stalk.position = Vector3(cos(a) * 0.75, 0.2, sin(a) * 0.75)
		var poly := LowPoly.new()
		poly.prism(Transform3D(), 0.07, 0.65 + fmod(i * 0.13, 0.4), 5, Palette.CORAL)
		poly.glow = true
		poly.blob(Transform3D(Basis(), Vector3(0, 0.9, 0)), 0.22, Palette.FUNGUS, 0, 0.1, i)
		var egg := MeshInstance3D.new()
		egg.mesh = poly.mesh()
		stalk.add_child(egg)
		model.add_child(stalk)
		_eggs.append(egg)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Palette.FUNGUS
		egg.material_override = material
		_egg_materials.append(material)
	global_position.y = Course.height_at(global_position)

func behave(delta: float) -> void:
	_state_time += delta
	if state == State.HATCHED:
		return
	var tank := player()
	if tank == null:
		return
	if state == State.DORMANT:
		if global_position.distance_to(tank.global_position) < TRIGGER_DISTANCE:
			state = State.SWELL
			_state_time = 0.0
			Sfx.play("eggs_warn", global_position)
	elif state == State.SWELL:
		var k := clampf(_state_time / TELEGRAPH_TIME, 0.0, 1.0)
		model.scale = Vector3.ONE * (1.0 + k * 0.45 + sin(_state_time * 28.0) * 0.04)
		for material in _egg_materials:
			material.albedo_color = Palette.WHITE if fmod(_state_time, 0.18) < 0.09 else Palette.FUNGUS
		if _state_time >= TELEGRAPH_TIME:
			hatch()

func hatch() -> void:
	if state == State.HATCHED or dead:
		return
	state = State.HATCHED
	hatch_count = 3
	World.current.fx.spores(global_position + Vector3.UP, 20, 2.0)
	Sfx.play("eggs_hatch", global_position)
	for i in hatch_count:
		var crawler := Crawler.new()
		crawler.position = global_position + Vector3(cos(TAU * i / hatch_count), 0, sin(TAU * i / hatch_count)) * 1.8
		World.current.add_enemy(crawler)
	for egg in _eggs:
		egg.visible = false
	World.current.award(40, global_position, false)
	# The stalk remains as a harmless husk for the camera; it is not an enemy anymore.
	set_process(false)

func on_death(hit: Hit) -> void:
	if state == State.SWELL:
		World.current.fx.spores(global_position, 8, 1.0)
	Sfx.play("eggs_pop", global_position)
	super(hit)
