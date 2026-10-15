class_name Mortar
extends Spitter
## Indirect-fire crew: a tube behind the dunes, or on a flood barge with depth charges, that walks a barrage of
## marked shells down the tank's lane. Change lanes before they land, burn the shells down, or close in and
## kill the crew.

const BARRAGE_STEP := 9.0 ## Meters between the impacts of a walking barrage.

var naval := false ## A barge of depth charges, not a dune crew.


func _init() -> void:
	super()
	max_hp = 30.0
	hp = 30.0
	radius = 1.8
	center_height = 1.2
	score = 300
	debris = [Fx.Debris.METAL, Fx.Debris.PAINT]
	weakness = {Hit.Kind.TAIL: 1.5}
	_shell_color = Palette.HOT


func build() -> void:
	_hard = Game.difficulty == Game.Difficulty.HARD
	var surface := Water.surface_at(global_position)
	global_position.y = surface if surface > -INF else Course.height_at(global_position)
	var b := LowPoly.new()
	if naval:
		b.frustum(Transform3D(Basis(), Vector3(0, -0.4, 0)), Vector2(3.4, 6.6), Vector2(3.0, 6.0), 1.2, Palette.SLATE, Palette.DUSK)
		b.box(Transform3D(Basis(), Vector3(0, 1.4, 2.0)), Vector3(1.6, 1.0, 1.4), Palette.CONCRETE)
		for i in 3:
			b.prism(Transform3D(Basis(), Vector3((i - 1) * 0.9, 0.8, 1.2)), 0.38, 0.9, 6, Palette.OCHRE, 0.34, Palette.RED)
	else:
		b.prism(Transform3D(), 1.9, 0.8, 8, Palette.STRAW, 1.6, Palette.OCHRE)
		for side in [-1.0, 1.0]:
			b.box(Transform3D(Basis(), Vector3(side * 1.1, 1.1, 0.7)), Vector3(0.4, 0.8, 0.4), Palette.MOSS)
			b.blob(Transform3D(Basis(), Vector3(side * 1.1, 1.7, 0.7)), 0.25, Palette.PEACH)
	var base_mesh := MeshInstance3D.new()
	base_mesh.mesh = b.mesh()
	model.add_child(base_mesh)
	model.add_child(_stalk)
	_stalk.position = Vector3(0, 0.9, 0)
	var tube := LowPoly.new()
	tube.prism(Transform3D(Basis(Vector3.RIGHT, -0.45), Vector3.ZERO), 0.3, 2.2, 6, Palette.SLATE, 0.22)
	var tube_mesh := MeshInstance3D.new()
	tube_mesh.mesh = tube.mesh()
	_stalk.add_child(tube_mesh)
	var bulb := LowPoly.new()
	bulb.glow = true
	bulb.blob(Transform3D(), 0.3, Palette.AMBER)
	_sac = MeshInstance3D.new()
	_sac.mesh = bulb.mesh()
	_sac.position = Vector3(0, 2.0, -0.95)
	_stalk.add_child(_sac)


func behave(delta: float) -> void:
	super(delta)
	if naval:
		model.rotation.z = sin(age * 1.3) * 0.04


func _flight(i: int) -> float:
	return (1.8 + i * 0.35) * Game.telegraph_scale()


func _aim(tank: Tank, i: int, _shots: int, flight: float) -> Vector3:
	var lane := Course.to_course(tank.global_position + tank.velocity * flight)
	return Course.ground_at(lane.x + (i - 1) * BARRAGE_STEP, lane.y)


func _arm(shell: Projectile) -> void:
	shell.hit.kind = Hit.Kind.BLAST
	shell.blast_damage = 24.0
	shell.blast_radius = 4.0 if naval else 3.6
	shell.trail = Palette.ASH
	shell.impacted.connect(func(_p: Projectile, point: Vector3, _t: Entity) -> void:
		if naval:
			World.current.fx.splash(point, 4.0, Water.surface_at(point))
		else:
			World.current.fx.dust(point, 10, 3.0, Palette.STRAW))


func _puff(from: Vector3) -> void:
	muzzle_blast(from, Vector3.UP, Muzzle.HEAVY, "mortar")
	Sfx.play("launch", from, 2.0, 0.6)
