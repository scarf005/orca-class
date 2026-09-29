class_name Enemy
extends Entity
## Base for hostile units: score, weaknesses, stagger, burning, telegraphs, tail grabs and cleanup.

const TRACK_RATE := 8.0 ## Per second `track_velocity` closes on `velocity`.
const MIN_TRACK_DELTA := 0.002 ## Frames shorter than this (hitstop) say nothing about speed.
const TELEPORT_DISTANCE := 6.0 ## A one-frame move this long is a jump, not travel.

var score := 100
var velocity := Vector3.ZERO
var track_velocity := Vector3.ZERO ## Smoothed `velocity` for lead: steady through hitstop and lane hops.
var stabbable := false
var weakness := {} ## Hit.Kind -> damage multiplier.
var death_radius := 2.0 ## Size of the death blast: half the model's longest side, set once it is built.
var debris: Array = [Fx.Debris.ARMOR, Fx.Debris.METAL] ## Fx.Debris materials it breaks into.
var drop := ""
var stagger := 0.0
var burning := 0.0
var can_stagger := true
var trails := false ## Flyers leave a fading trail (FlyerTrail).
var despawn_behind := 30.0 ## Removed once this far behind the rail; 0 keeps it.
var mark_offsets: Array[float] = [] ## Ground vehicles print a line into World.enemy_marks at each of these lateral offsets.
var mark_width := 1.0 ## How wide those prints are next to a tank's tread.
var _mark_last := Vector3.INF
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
	if trails:
		FlyerTrail.follow(self)
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
	var moved := global_position - _last_position
	velocity = moved / maxf(delta, 0.0001)
	if delta > MIN_TRACK_DELTA and moved.length() < TELEPORT_DISTANCE:
		track_velocity = track_velocity.lerp(velocity, 1.0 - exp(-TRACK_RATE * delta))
	_last_position = global_position
	wade(delta, velocity, death_radius)
	_leave_marks()
	if despawn_behind > 0.0:
		var world := World.current
		if world.rail.mode != Rail.Mode.ARENA and Course.to_course(global_position).x < world.rail.d - despawn_behind:
			despawn()


## Prints for what it drove over since the last frame; none while it is in the reservoir.
func _leave_marks() -> void:
	if mark_offsets.is_empty():
		return
	var side := Vector3(model.global_basis.x.x, 0.0, model.global_basis.x.z).normalized()
	var hull := Transform3D(Basis(side, Vector3.UP, side.cross(Vector3.UP)), global_position)
	_mark_last = World.current.enemy_marks.lay(_mark_last, hull, mark_offsets, mark_width, _wet, false)


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


enum Muzzle { DERIVE, LIGHT, AUTO, HEAVY } ## Weapon class: what a shot's muzzle blast looks like. DERIVE reads it off the shape.

const HEAVY_SHOTS := ["rocket", "atgm", "mortar", "shell"]
const LAUNCHED_SHOTS := ["rocket", "atgm"] ## These leave a backblast behind the tube.
const FLASH_SIZE := {Muzzle.LIGHT: 1.8, Muzzle.AUTO: 1.8, Muzzle.HEAVY: 3.75}
const GROUND_DUST_HEIGHT := 4.0 ## A muzzle this close to the ground kicks up dust.


static func muzzle_class(shape: String) -> Muzzle:
	return Muzzle.HEAVY if shape in HEAVY_SHOTS else Muzzle.LIGHT


## Every enemy shot leaves the barrel in a hot flash and gun smoke, by weapon class: light guns a
## big flash and a short puff; autocannons and gatlings the same plus a brief cone of fire; heavy
## weapons a huge star flash, a thick smoke cloud, a light flash, backblast for launchers and dust
## when the muzzle is near the ground.
func muzzle_blast(from: Vector3, dir: Vector3, weapon: Muzzle, shape := "") -> void:
	var fx := World.current.fx
	fx.muzzle_flash(from + dir * 0.3, dir, FLASH_SIZE[weapon], Palette.HOT)
	match weapon:
		Muzzle.LIGHT:
			fx.smoke(from + dir * 0.5, 2, 0.5, [Palette.ASH, Palette.STONE, Palette.MIST])
		Muzzle.AUTO:
			for i in 3:
				fx.spawn(Fx.Kind.FLAME, from + dir * 0.6, (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.18).normalized() * randf_range(14, 24), 0.09, 0.5, [Palette.BUTTER, Palette.AMBER][i % 2], {"drag": 4.0})
			fx.smoke(from + dir * 0.5, 2, 0.6, [Palette.ASH, Palette.STONE, Palette.MIST])
		Muzzle.HEAVY:
			fx.impact_star(from + dir * 0.8, 3.0, Palette.WHITE)
			fx.smoke(from + dir * 0.8, 6, 1.6, [Palette.ASH, Palette.STONE, Palette.MIST])
			fx.light_flash(from, 8.0, Palette.CORAL, 12.0)
			if shape in LAUNCHED_SHOTS:
				fx.muzzle_flash(from - dir * 0.8, -dir, 2.4, Palette.AMBER)
				fx.smoke(from - dir * 1.5, 4, 1.2, [Palette.ASH, Palette.MIST])
			var ground := Course.height_at(from)
			if from.y - ground < GROUND_DUST_HEIGHT:
				fx.dust(Vector3(from.x, ground + 0.3, from.z), 5, 2.5, Palette.STRAW)


func fire_at(shape: String, from: Vector3, target: Vector3, speed: float, damage: float, color := Palette.HOT, weapon := Muzzle.DERIVE) -> Projectile:
	return _launch(shape, from, (target - from).normalized(), speed, damage, color, weapon)


func _launch(shape: String, from: Vector3, dir: Vector3, speed: float, damage: float, color: Color, weapon: Muzzle) -> Projectile:
	muzzle_blast(from, dir, muzzle_class(shape) if weapon == Muzzle.DERIVE else weapon, shape)
	var projectile := World.current.spawn_projectile(Team.ENEMY, from, dir * speed, shape, color)
	projectile.hit = Hit.make(Hit.Kind.BULLET, damage, from)
	projectile.hit.source = self
	projectile.life = 3.0
	return projectile


## Turns a gun's `barrel` pivot (its bore is local -Z) toward the world direction `dir` by at most
## `rate` radians per second, whatever its parent is doing. Returns the angle still to go.
func slew_barrel(barrel: Node3D, dir: Vector3, rate: float, delta: float) -> float:
	var frame := barrel.get_parent_node_3d().global_basis.orthonormalized().inverse()
	var want := (frame * dir).normalized()
	var have := -barrel.basis.z.normalized()
	var angle := have.angle_to(want)
	if angle < 0.0001:
		return 0.0
	var step := minf(angle, rate * delta)
	var next := have.slerp(want, step / angle)
	barrel.basis = Basis.looking_at(next, Vector3.UP if absf(next.y) < 0.99 else Vector3.RIGHT)
	return angle - step


## `slew_barrel` toward a point in the world.
func aim_barrel(barrel: Node3D, point: Vector3, rate: float, delta: float) -> float:
	return slew_barrel(barrel, point - barrel.global_position, rate, delta)


## Which way a round leaves `muzzle`: along its bore. The fire computer may correct toward
## `wanted` by at most `max_degrees` (a gun still traversing never fires where it does not point).
static func bore_direction(muzzle: Node3D, wanted := Vector3.ZERO, max_degrees := 3.0) -> Vector3:
	var bore := -muzzle.global_basis.z.normalized()
	return bore if wanted == Vector3.ZERO else Tank.along_barrel(bore, wanted.normalized(), max_degrees)


## Fires from a barrel: the round leaves the `muzzle` node along its -Z, corrected toward `wanted`
## by at most `max_degrees`, scattered by `spread` (a cone of about that many radians). `weapon` is
## its class for the muzzle blast.
func fire_along(shape: String, muzzle: Node3D, speed: float, damage: float, color := Palette.HOT, wanted := Vector3.ZERO, max_degrees := 3.0, spread := 0.0, weapon := Muzzle.DERIVE) -> Projectile:
	var dir := bore_direction(muzzle, wanted, max_degrees)
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread).normalized()
	return _launch(shape, muzzle.global_position, dir, speed, damage, color, weapon)
