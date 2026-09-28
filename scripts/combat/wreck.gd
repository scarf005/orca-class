class_name Wreck
extends Node3D
## A destroyed vehicle's hull, blown into the air spinning. It trails fire and black smoke, blows
## up again where it lands (hurting whatever is nearby), and burns there for a while.

var velocity := Vector3.ZERO
var spin := Vector3.ZERO
var blast_radius := 4.0
var by_player := false
var _smoke := 0.0


## Takes over `model` (already in the world) and throws it up from `center`.
static func launch(model: Node3D, center: Vector3, size: float, player_kill: bool) -> Wreck:
	var wreck := Wreck.new()
	World.current.add_child(wreck)
	wreck.global_position = center
	model.reparent(wreck, true)
	wreck.velocity = Vector3(randf_range(-4, 4), randf_range(9, 14) / sqrt(maxf(size, 1.0)), randf_range(-4, 4))
	wreck.spin = Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-6, 6)) / sqrt(maxf(size, 1.0))
	wreck.blast_radius = 2.5 + size
	wreck.by_player = player_kill
	return wreck


func _process(delta: float) -> void:
	var world := World.current
	velocity.y -= 22.0 * delta
	global_position += velocity * delta
	rotation += spin * delta
	_smoke -= delta
	if _smoke <= 0.0:
		_smoke = 0.04
		world.fx.spawn(Fx.Kind.FLAME, global_position, Vector3.UP, 0.25, 0.9, [Palette.AMBER, Palette.HOT, Palette.BUTTER][randi() % 3], {"drag": 2.0})
		world.fx.spawn(Fx.Kind.GLOW, global_position, Vector3.UP * 1.5, 1.4, 0.9, [Palette.DUSK, Palette.INK, Palette.SLATE][randi() % 3], {"end_size": 2.4, "drag": 1.2, "fade": 0.2})
	var ground := Course.height_at(global_position)
	if global_position.y <= ground + 0.3 and velocity.y < 0.0:
		_land(ground)


func _land(ground: float) -> void:
	var world := World.current
	var at := Vector3(global_position.x, ground + 0.5, global_position.z)
	var chain := Hit.new()
	chain.source = world.player if by_player else null
	world.blast(at, blast_radius, 45.0, Entity.Team.PLAYER if by_player else Entity.Team.NEUTRAL, chain, null, [Palette.WHITE, Palette.AMBER, Palette.HOT, Palette.INK])
	world.fx.smoke_column(at, blast_radius, [Palette.DUSK, Palette.INK, Palette.SLATE])
	world.fx.burn(at, 5.0, 0.9)
	world.fx.debris(at, 10, [Palette.INK, Palette.SLATE, Palette.AMBER], 10.0, 0.45)
	world.shake(0.35, at)
	queue_free()
