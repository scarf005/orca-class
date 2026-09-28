class_name Flare
extends Entity
## A decoy flare from the boss. Burns bright, drifts down, and catches shells aimed past it.

var drift := Vector3.ZERO
var life := 2.2


func _init() -> void:
	team = Team.ENEMY
	max_hp = 1.0
	hp = 1.0
	radius = 1.4
	flying = true


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var b := LowPoly.new()
	b.glow = true
	b.blob(Transform3D(), 0.4, Palette.WHITE)
	mesh.mesh = b.mesh()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)


func tick(delta: float) -> void:
	life -= delta
	drift.y -= 6.0 * delta
	drift *= 1.0 - 0.8 * delta
	global_position += drift * delta
	var world := World.current
	world.fx.spawn(Fx.Kind.GLOW, global_position, Vector3.UP, 0.25, 0.5, [Palette.WHITE, Palette.BUTTER, Palette.PEACH][randi() % 3])
	if life <= 0.0:
		die(null)


func on_death(hit: Hit) -> void:
	if hit:
		World.current.fx.explosion(global_position, 1.2, [Palette.WHITE, Palette.BUTTER])
