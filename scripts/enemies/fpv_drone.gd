class_name FpvDrone
extends Enemy
## Kamikaze quadcopter. Weaves in, hangs ahead of the tank, flashes red and whines, then dives.
## The dive commits to a predicted point, so a drift or brake makes it miss. A pursuer (sent by the
## Director after a slow tank) instead flies one pattern up behind the tank, a little faster than
## cruise, and dives once it is close: a tank at speed outruns it and it peels off.

enum State { APPROACH, TELEGRAPH, DIVE, TUMBLE, PURSUE }
enum Pattern { SPIRAL, ARC, WEAVE, PINCER, ORBIT }

## Tuned live in the duel mode, hence a static var.
static var PURSUIT_SPEED := Rail.CRUISE * 1.25 ## Pursuers close on the tank this fast (m/s).
const PURSUIT_START := 42.0 ## Meters behind the tank a pursuer launches from.
const DIVE_LAG := 14.0 ## It stops flying its pattern and dives this close behind the tank.
const PEEL_LAG := 90.0 ## Fallen this far behind it gives up and peels off.
const HIT_HEIGHT := 1.3 ## Height over the ground every pattern ends at: the hull.

const TELEGRAPH_TIME := 0.6
const DIVE_SPEED := 34.0
const CRUISE_SPEED := 30.0
const DIVE_TIME := 5.0 ## A dive that has not landed by now gives up: the tank got away.

var state := State.APPROACH
var slot := Vector3(0, 8, 22) ## (u, height, distance ahead of the tank) it hovers at before diving.
var approach_time := 2.5
var from_behind := false
var pattern := Pattern.SPIRAL ## Pursuers: the path flown up behind the tank.
var side := 1.0 ## Pursuers: which flank a pincer takes.
var lag := PURSUIT_START ## Pursuers: meters behind the tank along the road.
var _state_time := 0.0
var _dive_dir := Vector3.ZERO
var _light: MeshInstance3D
var _rotors: Array[Node3D] = []
var _buzz: AudioStreamPlayer3D
var phase := randf() * TAU


func _init() -> void:
	super()
	max_hp = 4.0
	hp = 4.0
	radius = 0.9
	flying = true
	trails = true
	interceptable = true
	stabbable = true
	score = 150
	debris = [Fx.Debris.METAL, Fx.Debris.PAINT]
	weakness = {Hit.Kind.BLAST: 1.5, Hit.Kind.FIRE: 2.0, Hit.Kind.FRAGMENT: 2.0}


func build() -> void:
	var body := MeshInstance3D.new()
	body.mesh = ActorMeshes.mesh("fpv_drone", "body")
	model.add_child(body)
	for i in 4:
		var angle := PI * 0.25 + i * PI * 0.5
		var rotor := MeshInstance3D.new()
		rotor.mesh = ActorMeshes.mesh("fpv_drone", "rotor")
		rotor.position = Vector3(cos(angle), 0.08, sin(angle)) * 0.53
		rotor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.add_child(rotor)
		_rotors.append(rotor)
	_light = MeshInstance3D.new()
	_light.mesh = ActorMeshes.mesh("fpv_drone", "light")
	_light.position = Vector3(0, 0.05, -0.4)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Palette.SKY
	_light.material_override = material
	model.add_child(_light)
	_buzz = Sfx.loop("buzz", self, -8.0)
	if _buzz:
		_buzz.pitch_scale = randf_range(0.9, 1.15)


func behave(delta: float) -> void:
	_state_time += delta
	for rotor in _rotors:
		rotor.rotation.y += delta * 60.0
	var tank := player()
	if tank == null:
		return
	if is_staggered() and state != State.DIVE:
		_tumble(delta)
		return
	match state:
		State.APPROACH:
			var world := World.current
			var target: Vector3
			if world.rail.mode == Rail.Mode.ARENA:
				# No rail to pace: circle in at hover distance from wherever the tank is.
				var away := global_position - tank.global_position
				away.y = 0.0
				target = tank.global_position + away.normalized().rotated(Vector3.UP, 0.4 * delta) * absf(slot.z)
				target.y = Course.height_at(target) + 7.0 + sin(age * 3.1 + phase) * 0.8
			else:
				var d := world.rail.d + tank.course_offset + slot.z
				target = Course.to_world(d, slot.x + sin(age * 2.3 + phase) * 2.5, 0.0)
				target.y = Course.height(d, slot.x) + slot.y + sin(age * 3.1 + phase) * 0.8
			_steer(target, CRUISE_SPEED, 45.0, delta)
			model.look_at(global_position + (tank.global_position - global_position) * Vector3(1, 0, 1) + Vector3(0.001, 0, 0), Vector3.UP)
			if _state_time > approach_time and global_position.distance_to(tank.global_position) < 60.0:
				_set_state(State.TELEGRAPH)
				(_light.material_override as StandardMaterial3D).albedo_color = Palette.RED
				if _buzz:
					_buzz.pitch_scale *= 1.35
				Sfx.play("dive", global_position, -4.0, randf_range(0.9, 1.1))
		State.TELEGRAPH:
			velocity = velocity.move_toward(Vector3.ZERO, 40.0 * delta)
			global_position += velocity * delta + Vector3.UP * sin(_state_time * 40.0) * 0.02
			model.look_at(tank.global_position + Vector3.UP, Vector3.UP)
			_light.visible = fmod(_state_time, 0.12) < 0.07
			if _state_time >= TELEGRAPH_TIME * Game.telegraph_scale():
				_light.visible = true
				_start_dive(tank)
		State.DIVE:
			# Commits to its line with only a little steering, so dodges work.
			var to_tank := (intercept(global_position, tank.hit_center(), tank.velocity, DIVE_SPEED) - global_position).normalized()
			_dive_dir = _dive_dir.slerp(to_tank, clampf(0.6 * delta, 0.0, 1.0))
			global_position += _dive_dir * DIVE_SPEED * delta
			global_position.y = maxf(global_position.y, Course.height_at(global_position) + 0.5) # Skims the ground, never crashes into it.
			model.look_at(global_position + _dive_dir, Vector3.UP if absf(_dive_dir.y) < 0.95 else Vector3.BACK)
			if tank.hit_center().distance_to(global_position) < tank.radius + 0.8 and not tank.dead:
				var boom := Hit.make(Hit.Kind.BLAST, 14.0, global_position, _dive_dir)
				boom.source = self
				boom.warhead = true
				tank.take_hit(boom)
				_explode()
			elif _state_time > DIVE_TIME:
				despawn() # Outrun or dodged: it gives up quietly, no blast.
		State.PURSUE:
			_pursue(tank, delta)
		State.TUMBLE:
			_tumble(delta)


## Flies the pattern while the tank's own speed decides the gap: it closes at PURSUIT_SPEED less
## what the tank runs ahead at, so a faster tank leaves it behind.
func _pursue(tank: Tank, delta: float) -> void:
	var rail := World.current.rail
	if rail.mode == Rail.Mode.ARENA:
		_start_dive(tank)
		return
	lag += (rail.speed + tank.local_velocity.y - PURSUIT_SPEED) * delta
	if lag <= DIVE_LAG:
		_start_dive(tank)
		return
	if lag > PEEL_LAG:
		despawn() # Outrun: it peels off without a blast.
		return
	global_position = pursuit_spot(tank)
	if _buzz:
		_buzz.pitch_scale = 0.9 + (1.0 - lag / PURSUIT_START) * 0.9 # The whine climbs as it closes.
	var ahead := velocity.normalized() if velocity.length() > 1.0 else (tank.hit_center() - global_position).normalized()
	model.look_at(global_position + ahead, Vector3.UP if absf(ahead.y) < 0.95 else Vector3.BACK)


## Where the pattern puts this pursuer now, in the road's frame around the tank.
func pursuit_spot(tank: Tank) -> Vector3:
	var offset := pursuit_offset(pattern, lag / PURSUIT_START, side, phase)
	var d := World.current.rail.d + tank.course_offset - lag - offset.z
	var u := tank.course_u + offset.x
	return Course.to_world(d, u, Course.height(d, u) + offset.y)


## The pattern at `s`, the share of the launch gap still left (1 at launch, 0 on the tank), as
## (across the road, height over the ground, extra distance behind the tank). Every pattern is
## on the hull at s = 0.
static func pursuit_offset(kind: Pattern, s: float, flank: float, phase: float) -> Vector3:
	match kind:
		Pattern.SPIRAL: # A corkscrew around the road's axis that tightens onto the tank.
			var radius := 6.5 * s
			var angle := phase + s * TAU * 3.0
			return Vector3(cos(angle) * radius, HIT_HEIGHT + 2.0 * s + radius * (1.0 + sin(angle)) * 0.5, 0.0)
		Pattern.ARC: # High above the tank, stooping onto it.
			return Vector3(flank * 3.0 * s * sin(s * TAU * 1.5), HIT_HEIGHT + 26.0 * s * s, 0.0)
		Pattern.WEAVE: # Low S-curves skimming the ground.
			return Vector3(9.0 * sqrt(s) * sin(s * TAU * 2.5 + phase), HIT_HEIGHT + 0.6 * s, 0.0)
		Pattern.PINCER: # Splits wide to either flank, then converges.
			return Vector3(flank * 20.0 * sin(PI * s), HIT_HEIGHT + 2.0 * sin(PI * s), 0.0)
		_: # Orbit: a loop around the tank before it dives.
			var radius := 12.0 * sin(PI * s)
			var angle := (1.0 - s) * TAU * 1.5 + phase
			return Vector3(radius * sin(angle), HIT_HEIGHT + 3.0 * s + radius * 0.15 * (1.0 + sin(angle)), radius * (cos(angle) - 1.0))


func _start_dive(tank: Tank) -> void:
	(_light.material_override as StandardMaterial3D).albedo_color = Palette.RED
	_light.visible = true
	if Game.difficulty == Game.Difficulty.HARD and state == State.TELEGRAPH:
		var rocket := fire_at("rocket", hit_center(), tank.hit_center() + tank.velocity * 0.4, 32.0, 0.0)
		rocket.hit.kind = Hit.Kind.SHELL
		rocket.blast_radius = 2.0
		rocket.blast_damage = 8.0
		rocket.interceptable = true
		rocket.trail = Projectile.ROCKET_SMOKE
	_dive_dir = (intercept(global_position, tank.hit_center(), tank.velocity, DIVE_SPEED) - global_position).normalized()
	_set_state(State.DIVE)


func _tumble(delta: float) -> void:
	velocity.y -= 18.0 * delta
	global_position += velocity * delta
	model.rotate_x(delta * 9.0)
	if global_position.y < Course.height_at(global_position):
		die(Hit.make(Hit.Kind.BLAST, 99.0, global_position))


## Where a flyer at `speed` meets a target moving at `target_velocity`; the target's own spot
## when it cannot catch up.
static func intercept(from: Vector3, target: Vector3, target_velocity: Vector3, speed: float) -> Vector3:
	var offset := target - from
	var a := target_velocity.length_squared() - speed * speed
	var b := 2.0 * offset.dot(target_velocity)
	var c := offset.length_squared()
	var time := -1.0
	if absf(a) < 0.0001:
		time = -c / b if b < 0.0 else -1.0
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var roots := [(-b - sqrt(disc)) / (2.0 * a), (-b + sqrt(disc)) / (2.0 * a)]
			roots = roots.filter(func(t: float) -> bool: return t > 0.0)
			time = roots.min() if not roots.is_empty() else -1.0
	return target + target_velocity * minf(time, 2.0) if time > 0.0 else target


func _steer(target: Vector3, max_speed: float, accel: float, delta: float) -> void:
	var desired := (target - global_position)
	desired = desired.limit_length(max_speed) if desired.length() > 1.0 else desired * 2.0
	velocity = velocity.move_toward(desired, accel * delta)
	global_position += velocity * delta


func _set_state(value: State) -> void:
	state = value
	_state_time = 0.0


## Batted off its line by the tail: it tumbles away and never reaches the hull.
func bat(direction: Vector3) -> void:
	velocity = direction * 16.0 + Vector3.UP * 5.0
	_set_state(State.TUMBLE)


func telegraphing() -> bool:
	return state == State.TELEGRAPH


func interrupt() -> void:
	super()
	if state == State.TELEGRAPH:
		_set_state(State.APPROACH)
		(_light.material_override as StandardMaterial3D).albedo_color = Palette.SKY


## Blows up on contact without scoring a kill for the player.
func _explode() -> void:
	World.current.fx.explosion(global_position, 1.6)
	Sfx.play("blast_small", global_position)
	despawn()
