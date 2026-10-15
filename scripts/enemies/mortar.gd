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
	var base_mesh := MeshInstance3D.new()
	base_mesh.mesh = ActorMeshes.mesh("mortar", "base_barge" if naval else "base_dune")
	model.add_child(base_mesh)
	model.add_child(_stalk)
	_stalk.position = Vector3(0, 0.9, 0)
	var tube_mesh := MeshInstance3D.new()
	tube_mesh.mesh = ActorMeshes.mesh("mortar", "tube")
	_stalk.add_child(tube_mesh)
	_sac = MeshInstance3D.new()
	_sac.mesh = ActorMeshes.mesh("mortar", "bulb")
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
