class_name Projectile
extends Node3D
## A ballistic or guided projectile. Moves by sweeping a segment each frame against entities,
## props and the terrain. Interceptable projectiles are CIWS targets and have their own HP.

signal impacted(projectile: Projectile, point: Vector3, target: Entity)

var team := Entity.Team.PLAYER
var shape := "" ## Its look (see World.PROJECTILE_SHAPES).
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
var proximity := 0.0 ## Airburst: once armed, detonates when it passes this close to a flying hostile; 0 disables.
var homing_target: Node3D
var turn_rate := 0.0 ## Radians per second toward the homing target.
var homing_lead := false ## Steers to where the target will be on arrival, from the target's `velocity`.
var lead_response := 3.0 ## Per second the estimate of that velocity catches up with a change of course.
var flame_trail := false ## Leaves a stream of flame behind: white-hot young, red where it ends.
var interceptable := false
var intercept_hp := 1.0 ## Laser dwell damage needed to destroy it.
var radius := 0.0 ## Sweep radius; small for bullets, larger for thrown wrecks.
var sure_target: Entity ## A locked full charge: nothing else stops it until it has struck this.
var glow_trail := Color(0, 0, 0, 0) ## A glowing tracer streamed behind it; transparent disables.
const ROCKET_SMOKE := Color("8c4a34") ## Reddish-brown motor smoke, readable against the pastel sky.

var trail := Color(0, 0, 0, 0) ## Smoke trail color; transparent disables. A trail also means a lit motor.
var color := Palette.FRIENDLY ## Body color, set from the team when spawned.
var terrain_only_after := 0.0 ## Ignores entities until this distance (avoids hitting the shooter).
var ricochet := false ## Small-caliber rounds glance off the ground with sparks.
var impact_sound := ""
var halo: MeshInstance3D ## Enemy shots blink: this glow and `core` flash, each shot out of step.
var core: MeshInstance3D

const FLAME_TRAIL_INTERVAL := 0.05
const FLAME_TRAIL_LIFE := 0.3
const FLICKER_RATE := 50.0 ## Radians per second of the enemy shot blink (about 8 flashes a second).
const GLANCE_LIFE := 0.6 ## Seconds a round that glanced off the hull tumbles on before it is gone.

var _traveled := 0.0
var _phase := randf() * TAU
var _age := 0.0
var _hit_entities: Array[Entity] = []
var _trail_timer := 0.0
var _motor_light: OmniLight3D
var _lead_velocity := Vector3.INF ## The target velocity the lead is computed from.
var _glanced := false ## Bounced off the hull: it only tumbles away, harmless, and touches nothing.


func _ready() -> void:
	if World.current:
		World.current.projectiles.append(self)


func _exit_tree() -> void:
	if World.current:
		World.current.projectiles.erase(self)


func step(delta: float) -> void:
	_age += delta
	if _glanced:
		# A turned round is no threat: it stops blinking and shrinks away as it tumbles.
		scale = Vector3.ONE * lerpf(0.25, 0.7, clampf(life / GLANCE_LIFE, 0.0, 1.0))
	elif halo:
		# A hard on/off blink, not a soft shimmer, so every enemy round catches the eye.
		var on := sin(_age * FLICKER_RATE + _phase) > -0.2
		halo.set_instance_shader_parameter(&"instance_alpha", 1.0 if on else 0.3)
		halo.scale = Vector3.ONE * (1.5 if on else 0.9)
		if core:
			core.scale = Vector3.ONE * (1.25 if on else 1.0)
	life -= delta
	if life <= 0.0:
		if fuse_distance > 0.0:
			detonate(global_position, null)
		else:
			queue_free()
		return
	if is_instance_valid(homing_target) and turn_rate > 0.0:
		var desired := (_homing_point(delta) - global_position).normalized() * velocity.length()
		velocity = velocity.slerp(desired, clampf(turn_rate * delta, 0.0, 1.0))
	velocity.y -= gravity * delta
	var from := global_position
	var to := from + velocity * delta
	if _glanced:
		global_position = to
		if velocity.length_squared() > 0.01:
			look_at(to + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)
		return
	var step_length := from.distance_to(to)
	if fuse_distance > 0.0 and _traveled + step_length >= fuse_distance:
		to = from + velocity.normalized() * (fuse_distance - _traveled)
		if not _sweep(from, to) and not _burst_near_enemy(from, to, _traveled):
			detonate(to, null)
		return
	_traveled += step_length
	if _sweep(from, to) or _burst_near_enemy(from, to, _traveled - step_length):
		return
	global_position = to
	if velocity.length_squared() > 0.01:
		look_at(to + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)
	if glow_trail.a > 0.0:
		var fx := World.current.fx
		fx.spawn(Fx.Kind.GLOW, to, Vector3.ZERO, 0.16, 0.9, glow_trail, {"end_size": 0.1, "fade": 0.0})
		fx.spawn(Fx.Kind.GLOW, from.lerp(to, 0.5), Vector3.ZERO, 0.12, 0.5, Palette.WHITE, {"end_size": 0.05, "fade": 0.0})
	if trail.a > 0.0:
		_burn_motor(delta, to)
	if flame_trail:
		_stream_flame(delta, to)


## Where the homing shot steers: the target, or with `homing_lead` the intercept point for this
## shot's speed (the target itself when it is faster than the shot and cannot be caught).
func _homing_point(delta: float) -> Vector3:
	var at := homing_target.global_position + Vector3.UP
	var target_velocity: Variant = homing_target.get(&"velocity")
	if not homing_lead or not target_velocity is Vector3:
		return at
	var v := target_velocity as Vector3 if _lead_velocity == Vector3.INF else _lead_velocity.lerp(target_velocity, clampf(lead_response * delta, 0.0, 1.0))
	_lead_velocity = v
	var relative := at - global_position
	var a := v.length_squared() - velocity.length_squared()
	if a >= 0.0:
		return at
	var b := 2.0 * relative.dot(v)
	var t := (-b - sqrt(b * b - 4.0 * a * relative.length_squared())) / (2.0 * a)
	return at + v * minf(t, life)


## One flame puff every so often along the path, shifting from white-hot to red and swelling as
## the shot nears the end of its life, so a jet of these reads to its tip.
func _stream_flame(delta: float, at: Vector3) -> void:
	_trail_timer -= delta
	if _trail_timer > 0.0:
		return
	_trail_timer = FLAME_TRAIL_INTERVAL
	var age := _age / (_age + life)
	var heat: Color = [Palette.WHITE, Palette.BUTTER, Palette.AMBER, Palette.HOT][mini(int(age * 4.0), 3)]
	World.current.fx.spawn(Fx.Kind.FLAME, at, Vector3.UP * randf_range(0.5, 2.0), FLAME_TRAIL_LIFE, 0.7 + age * 0.9, heat, {"drag": 3.0, "end_size": 1.2 + age * 1.6})


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
	while not is_queued_for_deletion() and not _glanced and _traveled < max_range:
		end[0] = global_position
		step(6.0 / speed)
	if _glanced:
		return end[0] # The line ends where it glanced; the round tumbles off on its own from there.
	if not is_queued_for_deletion():
		end[0] = global_position
		queue_free()
	return end[0]


## Returns true when the projectile stopped.
func _sweep(from: Vector3, to: Vector3) -> bool:
	var world := World.current
	if is_instance_valid(sure_target) and not sure_target.dead:
		var t := sure_target.hit_test(from, to, maxf(radius, 1.0))
		if t < 0.0:
			return false # Through terrain, props and other enemies on its way.
		var struck := sure_target
		sure_target = null
		var point := from + (to - from).normalized() * t
		if pierce_entities:
			_hit_entities.append(struck)
			_apply(struck, point)
			_pierce_blast(point, struck)
			world.fx.sparks(point, -velocity.normalized(), 6, Palette.WHITE, 14.0)
			return false
		detonate(point, struck)
		return true
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
			_pierce_blast(point, best_entity)
			world.fx.sparks(point, -velocity.normalized(), 6, Palette.WHITE, 14.0)
			return false
		detonate(point, best_entity)
		return true
	return false


## The proximity fuse: once armed (`traveled` is the distance flown up to `from`), detonates where
## the path comes closest to any hostile it passes within `proximity` of. Returns true when it did.
func _burst_near_enemy(from: Vector3, to: Vector3, traveled: float) -> bool:
	var length := from.distance_to(to)
	var skip := clampf(Armament.AIRBURST_ARM - traveled, 0.0, length)
	if proximity <= 0.0 or skip >= length:
		return false
	var start := from.lerp(to, skip / length)
	var burst := Vector3.INF
	var best := INF
	for entity in World.current.targets_for(team):
		var point := Geometry3D.get_closest_point_to_segment(entity.hit_center(), start, to)
		if point.distance_to(entity.hit_center()) <= proximity and start.distance_to(point) < best:
			best = start.distance_to(point)
			burst = point
	if burst == Vector3.INF:
		return false
	detonate(burst, null)
	return true


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


func _apply(target: Entity, point: Vector3) -> Hit:
	var applied := hit.copy()
	if applied.source == null and team == Entity.Team.PLAYER:
		applied.source = World.current.player
	applied.position = point
	applied.direction = velocity.normalized()
	applied.speed = velocity.length()
	target.take_hit(applied)
	return applied


func detonate(point: Vector3, target: Entity) -> void:
	var world := World.current
	if hit.source == null and team == Entity.Team.PLAYER:
		hit.source = world.player
	if target:
		var applied := _apply(target, point)
		if target.glances(applied):
			_glance(point, target)
			return
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


## A piercing round bursts where it first strikes an enemy, not where it finally stops far behind;
## past that it only drills on.
func _pierce_blast(point: Vector3, struck: Entity) -> void:
	if blast_radius <= 0.0:
		return
	World.current.blast(point, blast_radius, blast_damage, team, hit, struck, blast_colors, splash_direction())
	blast_radius = 0.0


## A small-arms round that the hull turned: it keeps its look and tumbles off in a random direction
## away from the armor at nearly its own speed, with the armor's ping.
func _glance(point: Vector3, target: Entity) -> void:
	var normal := (point - target.hit_center()).normalized()
	var out := velocity.normalized().bounce(normal) + normal * 0.6 + Vector3(randf_range(-1, 1), randf_range(-0.3, 1), randf_range(-1, 1)) * 0.8
	velocity = out.normalized() * velocity.length() * randf_range(0.85, 1.1)
	gravity = 6.0
	life = GLANCE_LIFE
	interceptable = false
	_glanced = true
	global_position = point + normal * 0.3
	if halo:
		halo.set_instance_shader_parameter(&"instance_alpha", 0.5)
	Sfx.play("hit_confirm", point, -6.0, randf_range(1.7, 2.1)) # The armor's ping.


## Where a blast from this round carries: on along its flight, deflected up off the ground.
func splash_direction() -> Vector3:
	var dir := velocity.normalized()
	dir.y = absf(dir.y) * 0.5 + 0.35
	return dir.normalized()


## Programmable airburst: a fragment cone sweeping forward from the burst point.
func _airburst(point: Vector3) -> void:
	var world := World.current
	world.fx.explosion(point, 2.8, [Palette.WHITE, Palette.SKY, Palette.BUTTER])
	# A flak burst: a black puff that hangs in the sky where the shell went off, ringed by a dark shock.
	for i in 6:
		world.fx.smoke_puff(point + Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)) * 1.4, 3.2, Vector3(0, -2.5, 0))
	world.fx.shockwave(point, 7.0, Palette.INK, 0.25)
	# A wide ring of shot: the fragments fly out all round from the burst, not on along the shell.
	for i in airburst_fragments:
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.35, 0.35), randf_range(-1, 1)).normalized()
		var fragment := World.current.spawn_projectile(team, point, dir * 90.0, "fragment")
		fragment.hit = Hit.make(Hit.Kind.FRAGMENT, hit.damage, point)
		fragment.hit.caliber = Armament.AIRBURST_FRAGMENT_CALIBER # Heavy fragments: armor thicker than this turns them.
		fragment.hit.source = hit.source if is_instance_valid(hit.source) else null
		fragment.hit.weapon = hit.weapon
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
