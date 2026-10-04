class_name SeaMine
extends Enemy
## Horned floating mine. Drifts in, flashes before contact and chains through nearby mines.

var _wind := -1.0


func _init() -> void:
	super()
	max_hp = 4.0
	hp = max_hp
	radius = 0.9
	center_height = 0.2
	stabbable = true
	score = 100
	debris = [Fx.Debris.METAL]


func build() -> void:
	var b := LowPoly.new()
	b.prism(Transform3D(Basis(), Vector3(0, -0.5, 0)), 0.65, 0.8, 8, Palette.DUSK, 0.8)
	b.prism(Transform3D(Basis(), Vector3(0, 0.3, 0)), 0.8, 0.4, 8, Palette.MOSS, 0.35)
	for i in 6:
		var angle := TAU * i / 6.0
		b.prism(Transform3D(Basis(Vector3.FORWARD, -0.7) * Basis(), Vector3(cos(angle) * 0.7, 0.1, sin(angle) * 0.7)), 0.12, 0.4, 5, Palette.STONE, 0.06)
	b.glow = true
	b.prism(Transform3D(Basis(), Vector3(0, 0.7, 0)), 0.15, 0.12, 6, Palette.HOT)
	var mesh := MeshInstance3D.new()
	mesh.mesh = b.mesh()
	model.add_child(mesh)


func behave(delta: float) -> void:
	var tank := player()
	if tank == null or tank.dead or is_staggered():
		return
	var toward := tank.global_position - global_position
	toward.y = 0.0
	global_position += toward.normalized() * minf(3.0 * delta, toward.length())
	var water := Water.surface_at(global_position)
	global_position.y = (water if water > -INF else Course.height_at(global_position)) + sin(age * 2.4) * 0.15
	model.rotation.z = sin(age * 1.7) * 0.12
	if _wind >= 0.0:
		_wind -= delta
		if _wind <= 0.0:
			die(Hit.make(Hit.Kind.BLAST, 0.0, hit_center()))
	elif toward.length() <= tank.radius + 2.0:
		_wind = 0.55 * Game.telegraph_scale()
		World.current.fx.marker(global_position, 5.0, _wind, Palette.HOT)
		Sfx.play("warn", global_position)


func telegraphing() -> bool:
	return _wind > 0.0


func interrupt() -> void:
	super()
	_wind = -1.0


func on_death(hit: Hit) -> void:
	var blast := hit.copy() if hit else Hit.new()
	blast.weapon = "collateral"
	World.current.blast(hit_center(), 5.0, 18.0, Team.NEUTRAL, blast, self)
	super(hit)
