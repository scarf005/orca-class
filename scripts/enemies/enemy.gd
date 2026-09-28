class_name Enemy
extends Entity
## Base for hostile units: score, weaknesses, stagger, burning, telegraphs, tail grabs and cleanup.

var score := 100
var velocity := Vector3.ZERO
var grabbable := false
var stabbable := false
var weakness := {} ## Hit.Kind -> damage multiplier.
var death_radius := 2.0
var debris_colors: Array = [Palette.INK, Palette.SLATE, Palette.HULL]
var drop := ""
var stagger := 0.0
var burning := 0.0
var can_stagger := true
var despawn_behind := 30.0 ## Removed once this far behind the rail; 0 keeps it.
var wreck_on_death := false ## Vehicles: the hull is blown into the air and blows up again on landing.
var model := Node3D.new()
var age := 0.0
var _last_position := Vector3.ZERO
var _burn_tick := 0.0


func _init() -> void:
	team = Team.ENEMY


func _ready() -> void:
	model.name = "Model"
	add_child(model)
	build()
	track_meshes(model)
	_last_position = global_position
	World.current.stats.spawned += 1


## Subclasses add meshes to `model` here.
func build() -> void:
	pass


func tick(delta: float) -> void:
	age += delta
	stagger = maxf(0.0, stagger - delta)
	if burning > 0.0:
		_burn(delta)
	if dead:
		return
	behave(delta)
	velocity = (global_position - _last_position) / maxf(delta, 0.0001)
	_last_position = global_position
	if despawn_behind > 0.0:
		var world := World.current
		if world.rail.mode != Rail.Mode.ARENA and Course.to_course(global_position).x < world.rail.d - despawn_behind:
			despawn()


## Per-frame AI for subclasses. Not called while dead.
func behave(_delta: float) -> void:
	pass


func player() -> Tank:
	return World.current.player


func player_target() -> Vector3:
	var p := player()
	return p.global_position + Vector3.UP * 1.2 if p else global_position + Vector3.FORWARD


func is_staggered() -> bool:
	return stagger > 0.0


func damage_multiplier(hit: Hit) -> float:
	var multiplier: float = super.damage_multiplier(hit) * weakness.get(hit.kind, 1.0)
	if hit.incendiary:
		multiplier *= weakness.get(Hit.Kind.FIRE, 1.0) if hit.kind != Hit.Kind.FIRE else 1.0
	return multiplier


func on_damaged(hit: Hit, _amount: float) -> void:
	if can_stagger and hit.stagger > 0.0:
		stagger = maxf(stagger, hit.stagger)
	if hit.incendiary:
		burning = 3.0


func _burn(delta: float) -> void:
	burning -= delta
	_burn_tick -= delta
	if _burn_tick <= 0.0:
		_burn_tick = 0.25
		var world := World.current
		world.fx.spawn(Fx.Kind.GLOW, hit_center() + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * radius * 0.6, Vector3(0, randf_range(2, 4), 0), 0.4, 0.5, [Palette.FUNGUS, Palette.PEACH, Palette.BUTTER][randi() % 3])
		if not dead:
			var burn := Hit.make(Hit.Kind.FIRE, 5.0, hit_center())
			take_hit(burn)


## Cancels a telegraphed attack (tail stab, heavy stagger).
func interrupt() -> void:
	stagger = maxf(stagger, 1.0)


## Called when the tail grabs this enemy. Returns the model, now owned by the tail.
func grab() -> Node3D:
	var held := model
	model = Node3D.new()
	held.reparent(World.current, true)
	return held


## Removes the enemy after a grab without a death explosion; the grab already scored it.
func die_silently() -> void:
	dead = true
	World.current.unregister(self)
	queue_free()


func despawn() -> void:
	dead = true
	World.current.unregister(self)
	queue_free()


func on_death(hit: Hit) -> void:
	var world := World.current
	var center := hit_center()
	var by_player := hit != null and hit.by_player()
	# The death blast hurts whatever is close, so packed enemies go up in chains.
	var chain := Hit.new()
	chain.source = world.player if by_player else null
	world.blast(center, death_radius * 1.4, 35.0, Team.PLAYER if by_player else Team.NEUTRAL, chain, self, [Palette.WHITE, Palette.AMBER, Palette.HOT, Palette.CORAL])
	world.fx.debris(center, int(4 + death_radius * 3), debris_colors, 6.0 + death_radius * 2.0, 0.25 + death_radius * 0.08)
	world.fx.smoke_column(center, death_radius, [Palette.DUSK, Palette.INK, Palette.ASH])
	if wreck_on_death:
		Wreck.launch(model, center, death_radius, by_player)
		model = Node3D.new()
	world.award(score, center, true)
	world.kill_style(hit, self)
	if death_radius >= 3.0:
		world.hitstop(0.05)
	if not drop.is_empty():
		world.spawn_pickup(drop, center + Vector3.UP * 0.5)
	if hit and hit.kind == Hit.Kind.SHELL and death_radius < 3.0:
		# Heavy kills fling debris further.
		world.fx.debris(center, 6, debris_colors, 14.0, 0.3)


func fire_at(shape: String, from: Vector3, target: Vector3, speed: float, damage: float, color := Palette.HOT) -> Projectile:
	var projectile := World.current.spawn_projectile(Team.ENEMY, from, (target - from).normalized() * speed, shape, color)
	projectile.hit = Hit.make(Hit.Kind.BULLET, damage, from)
	projectile.hit.source = self
	projectile.life = 3.0
	return projectile
