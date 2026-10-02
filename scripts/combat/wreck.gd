class_name Wreck
extends Node3D
## A destroyed vehicle's hull, blown into the air spinning. It trails fire and black smoke, blows
## up again where it lands (hurting whatever is nearby), and burns there for a while.

var velocity := Vector3.ZERO
var spin := Vector3.ZERO
var blast_radius := 4.0
var by_player := false
var explodes := true ## Pieces (a blown-off turret) just crash and burn.
var _smoke := 0.0
var _size := 1.0
static var _live: Array[Wreck] = []
static var BLAST_THROW := 0.04 ## m/s a blast adds to a wreck per point of its damage, at its middle (tuned live in the duel mode).


## Takes over `model` (already in the world) and throws it up from `center`, plus `push` along
## the killing blow.
static func launch(model: Node3D, center: Vector3, size: float, player_kill: bool, push := Vector3.ZERO, explode := true) -> Wreck:
	var wreck := Wreck.new()
	World.current.add_child(wreck)
	wreck.global_position = center
	model.reparent(wreck, true)
	wreck.explodes = explode
	# A hard push (a shell kill) overrides the random tumble so the wreck clearly flies with the shot.
	var scatter := 4.0 * (1.0 - clampf(push.length() / 18.0, 0.0, 1.0) * 0.6)
	wreck.velocity = Vector3(randf_range(-scatter, scatter), randf_range(9, 14) / sqrt(maxf(size, 1.0)), randf_range(-scatter, scatter)) + push / sqrt(maxf(size, 1.0))
	wreck.spin = Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-6, 6)) / sqrt(maxf(size, 1.0))
	wreck.blast_radius = 2.5 + size
	wreck.by_player = player_kill
	wreck._size = size
	return wreck


func _enter_tree() -> void:
	_live.append(self)


func _exit_tree() -> void:
	_live.erase(self)


## A blast throws the wrecks around it: outward from its middle (and on along `push`), harder the
## closer and the bigger the blast, lighter pieces more.
static func blast_push(point: Vector3, radius: float, damage: float, push := Vector3.ZERO) -> void:
	for wreck in _live:
		var away := wreck.global_position - point
		var distance := away.length()
		var reach := radius * World.SHOCKWAVE_SCALE
		if distance > reach:
			continue
		var falloff := 1.0 - clampf(distance / reach, 0.0, 1.0)
		var dir := (away.normalized() + Vector3.UP * 0.4 + push * 0.5).normalized()
		wreck.velocity += dir * damage * BLAST_THROW * falloff / sqrt(maxf(wreck._size, 1.0))


func _process(delta: float) -> void:
	var world := World.current
	delta = world.unfrozen(delta)
	velocity.y -= 22.0 * delta
	global_position += velocity * delta
	rotation += spin * delta
	_smoke -= delta
	if _smoke <= 0.0:
		_smoke = 0.04
		world.fx.spawn(Fx.Kind.FLAME, global_position, Vector3.UP, 0.25, 0.9, [Palette.AMBER, Palette.HOT, Palette.BUTTER][randi() % 3], {"drag": 2.0})
		world.fx.spawn(Fx.Kind.GLOW, global_position, Vector3.UP * 1.5, Fx.DEBRIS_SMOKE_LIFE, 0.9, [Palette.DUSK, Palette.INK, Palette.SLATE][randi() % 3], {"end_size": 2.4, "drag": 1.2, "fade": 0.2})
	var ground := Course.height_at(global_position)
	var surface := Water.surface_at(global_position) if velocity.y < 0.0 else -INF
	if surface > ground and global_position.y <= surface:
		# Into the water: a big splash and it is gone, fire and all.
		world.fx.splash(global_position, 1.5 + blast_radius * 0.3, surface)
		Sfx.play("squelch", global_position, 0.0, 0.5)
		queue_free()
		return
	if global_position.y <= ground + 0.3 and velocity.y < 0.0:
		_land(ground)


func _land(ground: float) -> void:
	var world := World.current
	var at := Vector3(global_position.x, ground + 0.5, global_position.z)
	if not explodes:
		world.fx.debris(at, 6, [Fx.Debris.METAL, Fx.Debris.ARMOR], 7.0, 0.3, velocity.normalized())
		world.fx.dust(at, 4, 1.2, Palette.OCHRE)
		world.fx.burn(at, 3.0, 0.5)
		Sfx.play("rubble", at, -4.0, 1.3)
		queue_free()
		return
	var chain := Hit.new()
	chain.weapon = "collateral"
	chain.source = world.player if by_player else null
	world.blast(at, blast_radius, 45.0, Entity.Team.PLAYER if by_player else Entity.Team.NEUTRAL, chain, null, [Palette.WHITE, Palette.AMBER, Palette.HOT, Palette.INK])
	world.fx.smoke_column(at, blast_radius, [Palette.DUSK, Palette.INK, Palette.SLATE])
	world.fx.burn(at, 5.0, 0.9)
	world.fx.debris(at, 10, [Fx.Debris.METAL, Fx.Debris.ARMOR, Fx.Debris.DIRT], 10.0, 0.45, Vector3(velocity.x, 0.0, velocity.z).normalized())
	world.shake(0.35, at)
	queue_free()
