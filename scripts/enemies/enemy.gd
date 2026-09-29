class_name Enemy
extends Entity
## Base for hostile units: score, weaknesses, stagger, burning, telegraphs, tail grabs and cleanup.

var score := 100
var velocity := Vector3.ZERO
var stabbable := false
var weakness := {} ## Hit.Kind -> damage multiplier.
var death_radius := 2.0 ## Size of the death blast: half the model's longest side, set once it is built.
var debris: Array = [Fx.Debris.ARMOR, Fx.Debris.METAL] ## Fx.Debris materials it breaks into.
var drop := ""
var stagger := 0.0
var burning := 0.0
var can_stagger := true
var despawn_behind := 30.0 ## Removed once this far behind the rail; 0 keeps it.
var _shudder := 0.0 ## Seconds of hit shudder left.
var wreck_on_death := false ## Vehicles: the hull is blown into the air and blows up again on landing.
var pop_parts: Array[Node3D] = [] ## Parts (turrets) that blow off and fly separately when it dies as a wreck.
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
	var extent := visual_bounds().size
	if extent != Vector3.ZERO:
		death_radius = maxf(extent.x, maxf(extent.y, extent.z)) * 0.5
	ActorLayer.mark(self, ActorLayer.HOSTILE)
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
	# Shudder from recent hits, settling back onto the body.
	_shudder = maxf(0.0, _shudder - delta)
	var jitter := Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)) * _shudder * 1.6
	model.position = model.position.lerp(Vector3.ZERO, 1.0 - exp(-22.0 * delta)) + jitter
	behave(delta)
	show_damage(delta, death_radius)
	velocity = (global_position - _last_position) / maxf(delta, 0.0001)
	_last_position = global_position
	wade(delta, velocity, death_radius)
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


func on_damaged(hit: Hit, amount: float) -> void:
	impact_feedback(hit, amount, hp <= 0.0)
	if can_stagger and hit.stagger > 0.0:
		stagger = maxf(stagger, hit.stagger)
	if hit.incendiary:
		burning = 3.0


## Shared by ordinary enemies and bosses with their own module damage rules.
func impact_feedback(hit: Hit, amount: float, killed := false) -> void:
	if amount <= 0.0:
		return
	flash()
	_flash = 0.09
	var heavy := hit.kind in [Hit.Kind.SHELL, Hit.Kind.BLAST, Hit.Kind.RAM, Hit.Kind.TAIL, Hit.Kind.THROWN]
	var kick := 0.7 if heavy else 0.3
	model.position = (model.position + global_basis.inverse() * hit.direction.normalized() * kick).limit_length(0.9)
	_shudder = maxf(_shudder, 0.14 if heavy else 0.08)
	var world := World.current
	var caliber_size := clampf(hit.caliber / 20.0, 0.4, 1.0)
	world.fx.impact_star(hit.position, (2.6 if heavy else 1.2 + caliber_size * 0.8), Palette.WHITE)
	world.fx.sparks(hit.position, -hit.direction, 14 if heavy else 8, Palette.BUTTER, 18.0 if heavy else 13.0)
	# Chips of the enemy itself spray back out of the hole.
	var out := (-hit.direction * 0.6 + Vector3.UP * 0.6).normalized()
	world.fx.debris(hit.position, 8 if heavy else 3, debris, 12.0 if heavy else 8.0, 0.3 if heavy else 0.2, out)
	if hit.by_player():
		world.hit_confirmed.emit(killed)
		Sfx.confirm_hit(killed)
		world.shake(0.16 if heavy else 0.05, hit.position)
		if killed:
			world.hitstop(0.09 if heavy else 0.05)
			world.shake(0.28 if heavy else 0.18, hit.position)
			world.fx.shockwave(hit_center(), 3.0 + radius * 2.0, Palette.WHITE)
			world.fx.impact_star(hit_center(), 2.4 + radius, Palette.BUTTER)


func _burn(delta: float) -> void:
	burning -= delta
	_burn_tick -= delta
	if _burn_tick <= 0.0:
		_burn_tick = 0.25
		var world := World.current
		world.fx.spawn(Fx.Kind.FLAME, hit_center() + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * radius * 0.6, Vector3(0, randf_range(2, 4), 0), 0.4, 0.5, [Palette.FUNGUS, Palette.PEACH, Palette.BUTTER][randi() % 3])
		if not dead:
			var burn := Hit.make(Hit.Kind.FIRE, 5.0, hit_center())
			take_hit(burn)


## Cancels a telegraphed attack (tail stab, heavy stagger).
func interrupt() -> void:
	stagger = maxf(stagger, 1.0)


func despawn() -> void:
	dead = true
	World.current.unregister(self)
	queue_free()


func on_death(hit: Hit) -> void:
	var world := World.current
	var center := hit_center()
	var by_player := hit != null and hit.by_player()
	var push := kill_push(hit)
	# The death blast hurts whatever is close, so packed enemies go up in chains.
	var chain := Hit.new()
	chain.source = world.player if by_player else null
	world.blast(center, death_radius * 1.4, 35.0, Team.PLAYER if by_player else Team.NEUTRAL, chain, self, [Palette.WHITE, Palette.AMBER, Palette.HOT, Palette.CORAL], push)
	# A hull stays whole as a wreck and sheds only some of itself; an overkill (a 100 mm hit) tears
	# off more and throws it harder. Anything without a hull goes to pieces.
	var remains := wreck_on_death
	world.fx.shatter(visual_bounds(), debris, push, (0.7 if overkilled else 0.35) if remains else 1.0)
	world.fx.smoke_column(center, death_radius, [Palette.DUSK, Palette.INK, Palette.ASH])
	if remains:
		# The entity stops ticking after death, so its flash cannot expire on detached wrecks.
		for mesh in _meshes:
			if is_instance_valid(mesh):
				mesh.material_overlay = rest_overlay
		# Remains are no longer a threat: drop the hostile outline.
		ActorLayer.unmark(model, ActorLayer.HOSTILE)
		for part in pop_parts:
			if is_instance_valid(part):
				# Turrets blow clean off and cartwheel away on their own.
				Wreck.launch(part, part.global_position, death_radius * 0.4, by_player, push * 8.0 + Vector3.UP * 10.0, false)
		Wreck.launch(model, center, death_radius, by_player, push * (28.0 if overkilled else 18.0))
		model = null
	world.award(score, center, true)
	world.kill_style(hit, self)
	if death_radius >= 3.0:
		world.hitstop(0.05)
	if not drop.is_empty():
		world.spawn_pickup(drop, center + Vector3.UP * 0.5)


## How hard and which way the killing blow throws the remains: shells and rams send them flying
## on along the shot, blasts shove them out, bullets barely nudge.
static func kill_push(hit: Hit) -> Vector3:
	if hit == null:
		return Vector3.ZERO
	var dir := Vector3(hit.direction.x, maxf(hit.direction.y, 0.0) * 0.5, hit.direction.z).normalized()
	match hit.kind:
		Hit.Kind.SHELL, Hit.Kind.RAM, Hit.Kind.THROWN, Hit.Kind.TAIL:
			return dir
		Hit.Kind.BLAST, Hit.Kind.FRAGMENT:
			return dir * 0.6
	return dir * 0.25


const HEAVY_SHOTS := ["rocket", "atgm", "mortar"]


## Every enemy shot leaves the barrel in a hot flash and a puff of gun smoke; launches and mortars
## kick out a bigger cloud and light up the ground.
func muzzle_blast(from: Vector3, dir: Vector3, heavy: bool) -> void:
	var fx := World.current.fx
	fx.muzzle_flash(from + dir * 0.3, dir, 1.5 if heavy else 0.9, Palette.HOT)
	fx.smoke(from + dir * 0.5, 4 if heavy else 2, 0.8 if heavy else 0.35, [Palette.ASH, Palette.STONE, Palette.MIST])
	if heavy:
		fx.smoke(from - dir * 1.2, 3, 0.8, [Palette.ASH, Palette.MIST])
		fx.light_flash(from, 6.0, Palette.CORAL, 10.0)


func fire_at(shape: String, from: Vector3, target: Vector3, speed: float, damage: float, color := Palette.HOT) -> Projectile:
	muzzle_blast(from, (target - from).normalized(), shape in HEAVY_SHOTS)
	var projectile := World.current.spawn_projectile(Team.ENEMY, from, (target - from).normalized() * speed, shape, color)
	projectile.hit = Hit.make(Hit.Kind.BULLET, damage, from)
	projectile.hit.source = self
	projectile.life = 3.0
	return projectile
