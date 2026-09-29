class_name Projectile
extends Node3D
## A ballistic or guided projectile. Moves by sweeping a segment each frame against entities,
## props and the terrain. Interceptable projectiles are CIWS targets and have their own HP.

signal impacted(projectile: Projectile, point: Vector3, target: Entity)

var team := Entity.Team.PLAYER
var velocity := Vector3.ZERO
var gravity := 0.0
var life := 2.0
var hit := Hit.new()
var blast_radius := 0.0
var blast_damage := 0.0
var blast_colors: Array = [Palette.BUTTER, Palette.AMBER, Palette.HOT, Palette.CORAL]
var pierce_entities := false ## Keeps flying after hitting entities (APFSDS).
var fuse_distance := 0.0 ## Detonates in the air after this distance (airburst); 0 disables.
var airburst_fragments := 0
var homing_target: Node3D
var turn_rate := 0.0 ## Radians per second toward the homing target.
var interceptable := false
var intercept_hp := 1.0 ## Laser dwell damage needed to destroy it.
var radius := 0.0 ## Sweep radius; small for bullets, larger for thrown wrecks.
const ROCKET_SMOKE := Color("8c4a34") ## Reddish-brown motor smoke, readable against the pastel sky.

var trail := Color(0, 0, 0, 0) ## Smoke trail color; transparent disables. A trail also means a lit motor.
var color := Palette.FRIENDLY ## Body color, set from the team when spawned.
var terrain_only_after := 0.0 ## Ignores entities until this distance (avoids hitting the shooter).
var ricochet := false ## Small-caliber rounds glance off the ground with sparks.
var impact_sound := ""
var halo: MeshInstance3D ## Enemy shots twinkle: this glow flickers, each shot out of step.

const FLICKER_RATE := 70.0 ## Radians per second of the enemy shot halo flicker.

var _traveled := 0.0
var _phase := randf() * TAU
var _age := 0.0
var _hit_entities: Array[Entity] = []
var _trail_timer := 0.0
var _motor_light: OmniLight3D


func _ready() -> void:
	if World.current:
		World.current.projectiles.append(self)


func _exit_tree() -> void:
	if World.current:
		World.current.projectiles.erase(self)


func step(delta: float) -> void:
	_age += delta
	if halo:
		var wave := sin(_age * FLICKER_RATE + _phase)
		halo.set_instance_shader_parameter(&"instance_alpha", 0.75 + 0.25 * wave)
		halo.scale = Vector3.ONE * (1.0 + 0.2 * wave)
	life -= delta
	if life <= 0.0:
		if fuse_distance > 0.0:
			detonate(global_position, null)
		else:
			queue_free()
		return
	if is_instance_valid(homing_target) and turn_rate > 0.0:
		var desired := (homing_target.global_position + Vector3.UP - global_position).normalized() * velocity.length()
		velocity = velocity.slerp(desired, clampf(turn_rate * delta, 0.0, 1.0))
	velocity.y -= gravity * delta
	var from := global_position
	var to := from + velocity * delta
	var step_length := from.distance_to(to)
	if fuse_distance > 0.0 and _traveled + step_length >= fuse_distance:
		to = from + velocity.normalized() * (fuse_distance - _traveled)
		if not _sweep(from, to):
			detonate(to, null)
		return
	_traveled += step_length
	if _sweep(from, to):
		return
	global_position = to
	if velocity.length_squared() > 0.01:
		look_at(to + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)
	if trail.a > 0.0:
		_burn_motor(delta, to)


## A rocket motor: a flickering light that washes over the ground below, a jet of flame out the
## back and a thick billow of smoke left hanging along the flight path.
func _burn_motor(delta: float, at: Vector3) -> void:
	if _motor_light == null:
		_motor_light = OmniLight3D.new()
		_motor_light.light_color = Palette.AMBER
		_motor_light.omni_range = 12.0
		_motor_light.shadow_enabled = false
		add_child(_motor_light)
	_motor_light.light_energy = randf_range(3.0, 5.0)
	_trail_timer -= delta
	if _trail_timer > 0.0:
		return
	_trail_timer = 0.025
	var fx := World.current.fx
	var back := -velocity.normalized()
	fx.spawn(Fx.Kind.FLAME, at + back * 0.4, back * 6.0, 0.1, randf_range(0.5, 0.8), [Palette.WHITE, Palette.BUTTER, Palette.AMBER][randi() % 3], {"drag": 6.0})
	fx.spawn(Fx.Kind.GLOW, at + back * 0.8, Vector3(randf_range(-0.4, 0.4), 0.7, randf_range(-0.4, 0.4)), randf_range(1.4, 2.0), 0.7, trail.lerp(Palette.INK, randf() * 0.3), {"end_size": 2.6, "drag": 1.6, "fade": 0.3})


## Hitscan: flies the whole path this frame in short sweeps, so the round lands the instant it is
## fired. Returns where it stopped (impact point, or the end of its range).
func resolve_now(max_range: float) -> Vector3:
	var end := [global_position]
	impacted.connect(func(_p: Projectile, point: Vector3, _t: Entity) -> void: end[0] = point)
	var speed := maxf(velocity.length(), 1.0)
	life = max_range / speed + 1.0
	while not is_queued_for_deletion() and _traveled < max_range:
		end[0] = global_position
		step(6.0 / speed)
	if not is_queued_for_deletion():
		end[0] = global_position
		queue_free()
	return end[0]


## Returns true when the projectile stopped.
func _sweep(from: Vector3, to: Vector3) -> bool:
	var world := World.current
	var best_t := INF
	var best_entity: Entity = null
	if _traveled >= terrain_only_after:
		for entity in world.targets_for(team):
			if entity in _hit_entities:
				continue
			var t := entity.hit_test(from, to, radius)
			if t >= 0.0 and t < best_t:
				best_t = t
				best_entity = entity
	var prop_hit := world.props.segment_hit(from, to, radius)
	if not prop_hit.is_empty() and prop_hit.t < best_t:
		best_t = prop_hit.t
		best_entity = prop_hit.prop
	var ground_t := _ground_hit(from, to)
	if ground_t >= 0.0 and ground_t < best_t:
		var point := from.lerp(to, ground_t / maxf(from.distance_to(to), 0.0001))
		if ricochet and velocity.normalized().y > -0.35 and randf() < 0.5:
			world.fx.sparks(point, Vector3.UP, 3, Palette.BUTTER, 8.0)
			velocity = Vector3(velocity.x, absf(velocity.y) * 0.5 + 2.0, velocity.z) * 0.45
			global_position = point + Vector3.UP * 0.1
			hit.damage *= 0.5
			ricochet = false
			return false
		detonate(point, null)
		return true
	if best_entity:
		var point := from + (to - from).normalized() * best_t
		if pierce_entities:
			_hit_entities.append(best_entity)
			_apply(best_entity, point)
			world.fx.sparks(point, -velocity.normalized(), 6, Palette.WHITE, 14.0)
			return false
		detonate(point, best_entity)
		return true
	return false


func _ground_hit(from: Vector3, to: Vector3) -> float:
	var h_to := Course.height_at(to)
	if to.y >= h_to:
		return -1.0
	# Bisect between the last point above ground and the first below it.
	var a := 0.0
	var b := 1.0
	for _i in 6:
		var m := (a + b) * 0.5
		var p := from.lerp(to, m)
		if p.y >= Course.height_at(p):
			a = m
		else:
			b = m
	return b * from.distance_to(to)


func _apply(target: Entity, point: Vector3) -> void:
	var applied := hit.copy()
	if applied.source == null and team == Entity.Team.PLAYER:
		applied.source = World.current.player
	applied.position = point
	applied.direction = velocity.normalized()
	target.take_hit(applied)


func detonate(point: Vector3, target: Entity) -> void:
	var world := World.current
	if hit.source == null and team == Entity.Team.PLAYER:
		hit.source = world.player
	if target:
		_apply(target, point)
	if airburst_fragments > 0:
		_airburst(point)
	elif blast_radius > 0.0:
		world.blast(point, blast_radius, blast_damage, team, hit, target, blast_colors, splash_direction())
	else:
		var normal := -velocity.normalized()
		var color := Palette.BUTTER if team == Entity.Team.PLAYER else Palette.CORAL
		world.fx.sparks(point, normal, 4 + hit.caliber / 3, color, 9.0)
		if target == null:
			world.fx.dust(point, 2, 0.3, Palette.OCHRE)
	if not impact_sound.is_empty():
		Sfx.play(impact_sound, point)
	impacted.emit(self, point, target)
	queue_free()


## Where a blast from this round carries: on along its flight, deflected up off the ground.
func splash_direction() -> Vector3:
	var dir := velocity.normalized()
	dir.y = absf(dir.y) * 0.5 + 0.35
	return dir.normalized()


## Programmable airburst: a fragment cone sweeping forward from the burst point.
func _airburst(point: Vector3) -> void:
	var world := World.current
	world.fx.explosion(point, 2.8, [Palette.WHITE, Palette.SKY, Palette.BUTTER])
	var forward := velocity.normalized()
	for i in airburst_fragments:
		var dir := (forward + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.55).normalized()
		var fragment := World.current.spawn_projectile(team, point, dir * 90.0, "fragment")
		fragment.hit = Hit.make(Hit.Kind.FRAGMENT, hit.damage, point)
		fragment.life = 0.26
		fragment.terrain_only_after = 0.0
	Sfx.play("airburst", point)


## CIWS laser damage. Returns true when destroyed.
func laser(amount: float) -> bool:
	intercept_hp -= amount
	if intercept_hp <= 0.0:
		World.current.fx.explosion(global_position, 0.9, [Palette.WHITE, Palette.SKY, Palette.MINT])
		Sfx.play("pop", global_position)
		queue_free()
		return true
	return false
