class_name Tank
extends Entity
## The player's Orca-class. Moves within the rail frame (or freely in the arena), aims the turret
## at the reticle, fires the coax and 100 mm gun, runs the laser CIWS and drives the tail.

signal pickup_collected(id: String)
signal round_changed
signal life_lost

const MAX_ARMOR := 100.0
const EDGE_MARGIN := 4.0 ## How close to the foot of the valley walls the tank may go.
const FORWARD_LIMIT := Vector2(-3.0, 16.0)
## Arwing-like handling: it crosses the corridor in about a second and stops on a dime.
const MOVE_SPEED := Vector2(34.0, 20.0) ## Lateral, forward (m/s) in the rail frame.
const ARENA_SPEED := 32.0
const ACCEL := 220.0
const HULL_RADIUS := 2.3
const CIWS_RANGE := 24.0
const CIWS_DRONE_RANGE := 15.0
const CIWS_HEAT_RATE := 0.8
const CIWS_COOL_RATE := 0.22
const CIWS_LASER_DPS := 6.0
const CIWS_ENTITY_DPS := 22.0
const ANCHOR_COOLDOWN := 0.8
const DOUBLE_TAP := 0.28 ## Seconds between taps that make a double tap.
const DASH_SPEED := 46.0
## In the input vector's convention: +y is forward (Vector2.UP would be backward here).
const TAP_DIRECTIONS := {&"move_left": Vector2(-1, 0), &"move_right": Vector2(1, 0), &"move_forward": Vector2(0, 1), &"move_back": Vector2(0, -1)}
const COAX_RANGE := 140.0
const SOFT_LOCK_RADIUS := 56.0 ## Screen pixels (3D view) around the reticle.
const RESPAWN_DELAY := 1.8
const RESPAWN_INVULN := 2.6
const HOLD_TIME := 0.35 ## A grabbed enemy dangles this long before it is thrown.
const CRUSH_SPEED := 5.0 ## Ground speed above which buildings and wrecks give way.
const RAM_DAMAGE := 150.0

var model := TankModel.new()
var tail := Tail.new()
var tracks := TrackMarks.new()
var modules := TankModules.new()

var course_u := 0.0
var course_offset := 4.0 ## Distance ahead of the rail position.
var local_velocity := Vector2.ZERO ## (lateral, forward) in the rail frame, or world XZ in the arena.
var lateral_velocity := 0.0
var velocity := Vector3.ZERO
var hull_yaw := 0.0

var aim_screen := Vector2(DitherView.RESOLUTION) * Vector2(0.5, 0.45)
var aim_point := Vector3.ZERO
var aim_target: Entity
var using_gamepad := false

var coax_tier := 0
var current_round := Armament.Round.APHE
var round_count := 0
var reload := 0.0
var _coax_timers: Array[float] = []

var ciws_heat := 0.0
var ciws_overheated := false
var ciws_target: Object
var _ciws_sound_cooldown := 0.0

var invuln := 0.0
var anchor_cooldown := 0.0
var _drift := 0.0
var _drift_dir := 0.0
var _respawn := 0.0
var _barrel_recoil := 0.0
var _last_position := Vector3.ZERO
var _grab_target: Node3D
var coax_target: Entity ## What the coax is tracking on its own.
var _last_tap := {&"move_left": -1.0, &"move_right": -1.0, &"move_forward": -1.0, &"move_back": -1.0}
var _engine_sound: AudioStreamPlayer3D
var input_enabled := true


func _init() -> void:
	team = Team.PLAYER
	max_hp = MAX_ARMOR
	hp = MAX_ARMOR
	radius = HULL_RADIUS
	center_height = 1.2


func _ready() -> void:
	add_child(model)
	tail.mount = model.tail_mount
	add_child(tail)
	add_child(tracks)
	tail.arrived.connect(_on_tail_arrived)
	tail.missed.connect(func() -> void:
		if is_instance_valid(_grab_target) and _grab_target is Pickup:
			(_grab_target as Pickup).release()
		_grab_target = null)
	track_meshes(model)
	set_coax_tier(0)
	ActorLayer.mark(self, ActorLayer.FRIENDLY)
	_place(World.current.rail.d)
	_last_position = global_position
	_engine_sound = Sfx.loop("engine", self, -10.0)


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	if _respawn > 0.0:
		return -1.0
	return super.hit_test(from, to, extra_radius)


func set_coax_tier(tier: int) -> void:
	coax_tier = clampi(tier, 0, Armament.COAX_TIERS.size() - 1)
	var calibers := Armament.tier_calibers(coax_tier)
	model.set_coax_guns(calibers)
	ActorLayer.mark(model.coax_root, ActorLayer.FRIENDLY)
	_coax_timers.resize(calibers.size())
	_coax_timers.fill(0.0)


func load_round(value: Armament.Round) -> void:
	current_round = value
	round_count = Armament.MAGAZINE.get(value, 0)
	round_changed.emit()


func tick(delta: float) -> void:
	var world := World.current
	if _respawn > 0.0:
		_respawn -= delta
		model.visible = false
		tail.visible = false
		if _respawn <= 0.0:
			_finish_respawn()
		_place(world.rail.d)
		return
	invuln = maxf(0.0, invuln - delta)
	anchor_cooldown = maxf(0.0, anchor_cooldown - delta)
	reload = maxf(0.0, reload - delta)
	modules.update(delta)
	model.visible = invuln <= 0.0 or fmod(invuln, 0.16) < 0.1
	tail.visible = model.visible and not tail.destroyed
	_update_movement(delta)
	_update_aim(delta)
	_update_weapons(delta)
	_update_ciws(delta)
	tail.update(delta, global_basis, lateral_velocity)
	auto_tail() # The tail and the coax work on their own; only driving and the main gun take input.
	_update_pickups()
	tracks.press(global_transform)
	model.rotation.x = move_toward(model.rotation.x, 0.0, delta * 0.8)
	velocity = (global_position - _last_position) / maxf(delta, 0.0001)
	_last_position = global_position
	if _engine_sound:
		_engine_sound.pitch_scale = 0.8 + clampf(velocity.length() / 25.0, 0.0, 0.6)


## How far from the road the tank may range at d: out to the foot of the valley walls, and within
## the guardrails on the highway deck.
static func lateral_limit(d: float) -> float:
	if Course.deck_blend(d) > 0.5:
		return 12.0
	return maxf(Course.valley_half_width(d) - EDGE_MARGIN, 14.0)


func _input_vector() -> Vector2:
	if not input_enabled:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_back", "move_forward")


func _update_movement(delta: float) -> void:
	var world := World.current
	var rail := world.rail
	var input := _input_vector()
	_read_double_taps()
	# W and S double as the throttle: pushing forward boosts the rail, pulling back brakes it.
	var command := 0
	if input.y > 0.5 and modules.overdrive_online():
		command = 1
	elif input.y < -0.5:
		command = -1
	if rail.mode == Rail.Mode.ARENA:
		_move_arena(delta, input)
		rail.advance(delta, 0, modules.meter_refill_factor())
		return
	rail.advance(delta, command, modules.meter_refill_factor())
	var target := Vector2(input.x * MOVE_SPEED.x, input.y * MOVE_SPEED.y) * modules.move_factor()
	local_velocity = local_velocity.move_toward(target, ACCEL * delta)
	if _drift > 0.0:
		_drift -= delta
		if _drift_dir != 0.0:
			local_velocity.x = _drift_dir * DASH_SPEED * (_drift / 0.3)
	course_u += local_velocity.x * delta
	course_offset += local_velocity.y * delta
	var limit := lateral_limit(rail.d + course_offset)
	course_u = clampf(course_u, -limit, limit)
	course_offset = clampf(course_offset, FORWARD_LIMIT.x, FORWARD_LIMIT.y)
	lateral_velocity = local_velocity.x
	_collide_props(delta)
	_ram_enemies()
	_place(rail.d)
	model.animate_tracks(delta, rail.speed + local_velocity.y, rail.speed + local_velocity.y)


func _move_arena(delta: float, input: Vector2) -> void:
	var cam := World.current.camera
	var forward := -cam.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP)
	var wish := (right * input.x + forward * input.y) * ARENA_SPEED * modules.move_factor()
	var current := Vector3(local_velocity.x, 0, local_velocity.y)
	current = current.move_toward(wish, ACCEL * delta)
	if _drift > 0.0:
		_drift -= delta
		current = right * _drift_dir * DASH_SPEED * (_drift / 0.3) if absf(_drift_dir) > 0.0 else current
	local_velocity = Vector2(current.x, current.z)
	var p := global_position + current * delta
	var center := Course.to_world(Course.ARENA_CENTER_D, 0.0)
	var flat := Vector2(p.x - center.x, p.z - center.z)
	if flat.length() > Course.ARENA_RADIUS - 6.0:
		flat = flat.normalized() * (Course.ARENA_RADIUS - 6.0)
		p.x = center.x + flat.x
		p.z = center.z + flat.y
	var c := Course.to_course(p)
	course_u = c.y
	lateral_velocity = current.dot(right)
	if current.length() > 1.0:
		var target_yaw := atan2(-current.x, -current.z)
		hull_yaw = rotate_toward(hull_yaw, target_yaw, 3.2 * delta)
	_set_pose(Course.ground_at(c.x, c.y), hull_yaw)
	_collide_props(delta)
	_ram_enemies()
	model.animate_tracks(delta, current.length(), current.length())


## Double taps: tap a direction twice to dash that way. Gamepad shoulders dash sideways.
func _read_double_taps() -> void:
	if not input_enabled:
		return
	if Input.is_action_just_pressed("roll_left"):
		dash(Vector2(-1, 0))
	elif Input.is_action_just_pressed("roll_right"):
		dash(Vector2(1, 0))
	var now := Time.get_ticks_msec() / 1000.0
	for action: StringName in _last_tap:
		if not Input.is_action_just_pressed(action):
			continue
		if now - float(_last_tap[action]) < DOUBLE_TAP:
			_last_tap[action] = -1.0
			dash(TAP_DIRECTIONS[action])
		else:
			_last_tap[action] = now


## A burst of speed the way it was tapped, kicked off by the tail slamming the ground: sideways it
## is a dodge that lashes whatever is beside the hull, forward it surges the rail, back it digs in.
func dash(direction: Vector2) -> void:
	if _respawn > 0.0:
		return
	_anchor(direction)


func is_dashing() -> bool:
	return _drift > 0.0


func _anchor(input: Vector2) -> void:
	var world := World.current
	if anchor_cooldown > 0.0:
		return
	anchor_cooldown = ANCHOR_COOLDOWN
	invuln = maxf(invuln, 0.3)
	var ground := global_position - global_basis.z * -3.0
	if absf(input.x) > 0.3:
		# Pivot drift: the claw bites the ground and the hull whips sideways around it.
		_drift = 0.3
		_drift_dir = signf(input.x)
		if is_instance_valid(tail.held) and not tail.held is Pickup:
			_throw_held()
			Sfx.play("skid", global_position)
			return
		swat(false)
		ground = global_position + global_basis.x * -_drift_dir * 2.5 + global_basis.z * 3.0
		Sfx.play("skid", global_position)
	elif input.y > 0.3:
		# Forward surge: the tail kicks off behind and the hull lunges ahead of the rail.
		_drift = 0.3
		_drift_dir = 0.0
		if world.rail.mode != Rail.Mode.ARENA:
			local_velocity.y = DASH_SPEED
			world.rail.speed = maxf(world.rail.speed, Rail.OVERDRIVE)
		else:
			var ahead := -world.camera.global_basis.z
			local_velocity = Vector2(ahead.x, ahead.z).normalized() * DASH_SPEED
		ground = global_position + global_basis.z * 3.0
		world.camera.kick(0.03)
		Sfx.play("skid", global_position, 0.0, 1.2)
	else:
		# Hard stop: the rail halts and the tank digs in.
		if world.rail.mode != Rail.Mode.ARENA:
			world.rail.anchor_stop(0.55)
			local_velocity.y = -6.0
		else:
			local_velocity = Vector2.ZERO
		Sfx.play("skid", global_position, 0.0, 0.8)
	ground.y = Course.height_at(ground)
	if is_instance_valid(tail.held):
		return # Never drop what the claw carries just to dig in.
	tail.set_state(Tail.State.ANCHOR, ground, null, 400.0)
	world.fx.dust(ground, 10, 1.5, Palette.OCHRE)
	world.fx.debris(ground, 6, [Palette.OCHRE, Palette.WOOD], 5.0, 0.25)
	world.shake(0.2)
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		if tail.state == Tail.State.ANCHOR:
			tail.set_state(Tail.State.IDLE)
			world.fx.scorch(ground, 1.2))


func _collide_props(delta: float) -> void:
	var world := World.current
	for prop: Prop in world.props.in_radius(global_position, HULL_RADIUS):
		if prop.is_falling():
			continue
		if prop.global_position.y > global_position.y + 2.5:
			continue # Resting up high (a tree crown, a spire): the hull passes under it.
		# Sixty tons at speed flattens anything that is not a landmark.
		if prop.crushable or _ground_speed() > CRUSH_SPEED:
			var ram := Hit.make(Hit.Kind.RAM, 99999.0, prop.global_position, -global_basis.z)
			ram.source = self
			prop.take_hit(ram)
			_ram_jolt(prop.footprint)
			continue
		if not prop.solid:
			continue
		# Bulldoze: heavy ram damage to the prop while it shoves the tank aside and back.
		var ram := Hit.make(Hit.Kind.RAM, 260.0 * delta, prop.global_position)
		ram.source = self
		prop.take_hit(ram)
		if prop.dead:
			world.shake(0.3)
			continue
		var away := global_position - prop.global_position
		away.y = 0.0
		var overlap := HULL_RADIUS + prop.footprint - away.length()
		if overlap > 0.0 and world.rail.mode != Rail.Mode.ARENA:
			course_u += signf(away.dot(World.current.rail.basis().x) + 0.001) * overlap * 0.5
			course_offset -= overlap * 0.3
		elif overlap > 0.0:
			var push := away.normalized() * overlap
			global_position += push
		world.shake(0.04)


## Sixty tons at 80 km/h: the camera bucks, the hull rocks back and the frame catches a beat,
## more for bigger things.
func _ram_jolt(size: float) -> void:
	var world := World.current
	var heavy := clampf(size / 4.0, 0.15, 1.0) * clampf(_ground_speed() / Rail.CRUISE, 0.5, 1.5)
	world.shake(0.1 + heavy * 0.3)
	world.camera.kick(0.01 + heavy * 0.03)
	if heavy > 0.4:
		world.hitstop(0.02 + heavy * 0.03)
	model.rotation.x = -0.05 - heavy * 0.12
	if world.rail.mode != Rail.Mode.ARENA:
		local_velocity.y -= 3.0 + heavy * 6.0
	Sfx.play("impact", global_position, -6.0 + heavy * 6.0, 0.8)


func _ground_speed() -> float:
	if World.current.rail.mode == Rail.Mode.ARENA:
		return local_velocity.length()
	return World.current.rail.speed + local_velocity.y


## Ramming ground enemies: crawlers pop, UGVs and spitters take a crushing hit.
func _ram_enemies() -> void:
	var world := World.current
	if _ground_speed() < CRUSH_SPEED:
		return
	for entity: Entity in world.enemies.duplicate():
		if entity.flying or not entity is Enemy or entity is Colossus:
			continue
		var offset := entity.global_position - global_position
		offset.y = 0.0
		if offset.length() < HULL_RADIUS + entity.radius:
			var ram := Hit.make(Hit.Kind.RAM, RAM_DAMAGE, entity.hit_center(), (-global_basis.z))
			ram.source = self
			ram.stagger = 1.5
			entity.take_hit(ram)
			world.shake(0.3)
			world.hitstop(0.04)
			world.fx.sparks(entity.hit_center(), -global_basis.z, 14, Palette.BUTTER, 12.0)
			Sfx.play("impact", entity.global_position)


func _place(d: float) -> void:
	var rail := World.current.rail
	if rail.mode == Rail.Mode.ARENA:
		return
	var p := Course.ground_at(d + course_offset, course_u)
	var f := Course.forward(d + course_offset)
	var yaw := atan2(-f.x, -f.z) - atan2(local_velocity.x, rail.speed + local_velocity.y + 4.0) * 0.6
	hull_yaw = yaw
	_set_pose(p, yaw)


func _set_pose(p: Vector3, yaw: float) -> void:
	# Tilt the hull to the terrain under the tracks.
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := fwd.cross(Vector3.UP)
	var front := Course.height_at(p + fwd * 3.0)
	var back := Course.height_at(p - fwd * 3.0)
	var left := Course.height_at(p - right * 1.6)
	var right_h := Course.height_at(p + right * 1.6)
	var pitch := atan2(front - back, 6.0)
	var roll := atan2(right_h - left, 3.2)
	global_position = Vector3(p.x, (front + back + left + right_h) * 0.25, p.z)
	global_basis = Basis.from_euler(Vector3(pitch, yaw, -roll), EULER_ORDER_YXZ)


func _update_aim(delta: float) -> void:
	var world := World.current
	var view_size := Vector2(DitherView.RESOLUTION)
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() > 0.15:
		using_gamepad = true
		aim_screen += stick * 600.0 * delta * Game.settings.mouse_sensitivity
		_aim_assist(delta)
	elif not using_gamepad and world.view:
		var mouse := world.view.get_local_mouse_position()
		aim_screen = mouse * view_size / world.view.size
	elif using_gamepad:
		_aim_assist(delta)
	aim_screen = aim_screen.clamp(Vector2(16, 16), view_size - Vector2(16, 16))
	var cam := world.camera
	var origin := cam.project_ray_origin(aim_screen)
	var dir := cam.project_ray_normal(aim_screen)
	var best := 320.0
	aim_target = null
	for enemy in world.enemies:
		var t := Entity.segment_sphere(origin, origin + dir * best, enemy.hit_center(), enemy.radius + 0.6)
		if t >= 0.0 and t < best:
			best = t
			aim_target = enemy
	var ground := _ray_ground(origin, dir, best)
	if ground >= 0.0 and ground < best:
		best = ground
		aim_target = null
	aim_point = origin + dir * best
	# Turret traverse and gun elevation follow the aim point.
	var local := model.turret.global_transform.affine_inverse() * aim_point
	var yaw := atan2(-local.x, -local.z)
	model.turret.rotation.y = rotate_toward(model.turret.rotation.y, model.turret.rotation.y + yaw, 7.0 * modules.traverse_factor() * delta)
	var to_aim := local - model.gun_pivot.position
	var pitch := clampf(atan2(to_aim.y, Vector2(to_aim.x, to_aim.z).length()), deg_to_rad(-8.0), deg_to_rad(55.0))
	model.gun_pivot.rotation.x = move_toward(model.gun_pivot.rotation.x, pitch, 3.0 * delta)
	_barrel_recoil = move_toward(_barrel_recoil, 0.0, delta * 2.5)
	model.barrel.position.z = _barrel_recoil


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		using_gamepad = false


func _aim_assist(delta: float) -> void:
	var cam := World.current.camera
	var best_distance := 68.0
	var best := Vector2.INF
	for enemy in World.current.enemies:
		if cam.is_position_behind(enemy.hit_center()):
			continue
		var screen := cam.unproject_position(enemy.hit_center())
		var distance := screen.distance_to(aim_screen)
		if distance < best_distance:
			best_distance = distance
			best = screen
	if best != Vector2.INF:
		aim_screen = aim_screen.lerp(best, clampf(6.0 * delta, 0.0, 1.0))


func _ray_ground(origin: Vector3, dir: Vector3, max_distance: float) -> float:
	var t := 0.0
	var step := 2.0
	var previous := 0.0
	while t < max_distance:
		var p := origin + dir * t
		if p.y < Course.height_at(p):
			var a := previous
			var b := t
			for _i in 8:
				var m := (a + b) * 0.5
				var q := origin + dir * m
				if q.y < Course.height_at(q):
					b = m
				else:
					a = m
			return b
		previous = t
		t += step
		step = minf(step * 1.08, 8.0)
	return -1.0


## Direction from a muzzle to the aim point, lead-corrected for the locked target, but never more
## than a few degrees off where the barrel points.
func _fire_direction(from: Vector3, speed: float) -> Vector3:
	var target := aim_point
	var lock := _pick_coax_target()
	if is_instance_valid(lock) and lock is Enemy:
		target = lead_point(from, speed, lock)
	return along_barrel(-model.barrel.global_basis.z, (target - from).normalized())


## Where to aim so a round at `speed` meets `target`: a few passes settle the flight time.
func lead_point(from: Vector3, speed: float, target: Entity) -> Vector3:
	var enemy_velocity := (target as Enemy).velocity if target is Enemy else Vector3.ZERO
	var p := target.hit_center()
	var aim := p
	for i in 3:
		aim = p + enemy_velocity * (from.distance_to(aim) / speed)
	return aim


func _update_weapons(delta: float) -> void:
	coax_target = _pick_coax_target()
	if input_enabled and Input.is_action_pressed("fire_coax"):
		var calibers := Armament.tier_calibers(coax_tier)
		for i in calibers.size():
			_coax_timers[i] -= delta
			if _coax_timers[i] <= 0.0:
				var spec: Dictionary = Armament.GUNS[calibers[i]]
				_coax_timers[i] += spec.interval
				_fire_coax(model.coax_muzzles[i], calibers[i], spec, coax_target)
	else:
		for i in _coax_timers.size():
			_coax_timers[i] = maxf(_coax_timers[i] - delta, 0.0)
	if input_enabled and Input.is_action_pressed("fire_cannon") and reload <= 0.0:
		fire_cannon()


## The fire-control system's soft lock: the enemy under the reticle, else the one nearest it on
## screen within a small radius. The coax leads it automatically.
func _pick_coax_target() -> Entity:
	if is_instance_valid(aim_target) and not aim_target.dead:
		return aim_target
	var cam := World.current.camera
	var best: Entity = null
	var best_distance := SOFT_LOCK_RADIUS
	for enemy in World.current.enemies:
		if enemy.dead or enemy is Flare or cam.is_position_behind(enemy.hit_center()):
			continue
		if enemy.hit_center().distance_to(global_position) > COAX_RANGE:
			continue
		var distance := cam.unproject_position(enemy.hit_center()).distance_to(aim_screen)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


## Rounds leave along the barrel: the ballistic computer may correct only a few degrees off it,
## so a gun still traversing never fires somewhere it is not pointing.
static func along_barrel(barrel: Vector3, wanted: Vector3, max_degrees := 6.0) -> Vector3:
	var angle := barrel.angle_to(wanted)
	if angle <= deg_to_rad(max_degrees):
		return wanted
	return barrel.slerp(wanted, deg_to_rad(max_degrees) / angle).normalized()


func _fire_coax(muzzle: Node3D, caliber: int, spec: Dictionary, target: Entity) -> void:
	var world := World.current
	var from := muzzle.global_position
	var aim := lead_point(from, spec.speed, target) if is_instance_valid(target) else aim_point
	var dir := along_barrel(-model.barrel.global_basis.z, (aim - from).normalized())
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spec.spread).normalized()
	var bullet := world.spawn_projectile(Team.PLAYER, from, dir * spec.speed, "bullet", spec.color)
	bullet.hit = Hit.make(Hit.Kind.BULLET, spec.damage, from)
	bullet.hit.caliber = caliber
	bullet.hit.source = self
	bullet.life = 0.9
	bullet.ricochet = caliber < 20
	if spec.blast > 0.0:
		bullet.blast_radius = spec.blast
		bullet.blast_damage = spec.damage * 0.5
		bullet.blast_colors = [Palette.WHITE, Palette.PEACH, Palette.CORAL]
	world.fx.muzzle_flash(from + dir * 0.2, dir, 0.3 + caliber * 0.025, spec.color)
	# Brass spills out of the mantlet and bounces off the deck.
	var eject := global_basis.x * randf_range(2.0, 4.0) + Vector3.UP * randf_range(3.0, 5.0)
	world.fx.spawn(Fx.Kind.SOLID, from - dir * 0.6, eject, 0.9, 0.05 + caliber * 0.004, Palette.BUTTER, {"gravity": 22.0, "bounce": true, "spin": 1.0})
	Sfx.play(spec.sound, from, -4.0, randf_range(0.95, 1.08))


func fire_cannon() -> void:
	var world := World.current
	var muzzle := model.muzzle.global_position
	var barrel_dir := -model.barrel.global_basis.z
	var round := current_round
	world.stats.shots += 1
	match round:
		Armament.Round.CANISTER:
			# A wall of tungsten balls, and a muzzle blast that flattens everything just ahead.
			var aim_dir := _fire_direction(muzzle, 200.0)
			world.blast(muzzle + aim_dir * 7.0, 6.0, 260.0, Team.PLAYER, _cannon_hit(), null, [Palette.WHITE, Palette.BUTTER, Palette.AMBER], aim_dir)
			for i in 40:
				var dir := (aim_dir + Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)) * 0.13).normalized()
				var pellet := world.spawn_projectile(Team.PLAYER, muzzle, dir * randf_range(170, 210), "pellet", Palette.SKY)
				pellet.hit = Hit.make(Hit.Kind.BULLET, 90.0, muzzle)
				pellet.hit.caliber = 20
				pellet.life = 0.36
				pellet.impacted.connect(_count_hit, CONNECT_ONE_SHOT)
		Armament.Round.DRAGON:
			# A roaring cone of burning magnesium: a fireball right ahead and a long gout of flame.
			var aim_dir := _fire_direction(muzzle, 60.0)
			var burst := _cannon_hit()
			burst.incendiary = true
			world.blast(muzzle + aim_dir * 9.0, 7.0, 220.0, Team.PLAYER, burst, null, [Palette.WHITE, Palette.BUTTER, Palette.AMBER, Palette.HOT], aim_dir)
			for i in 52:
				var dir := (aim_dir + Vector3(randf_range(-1, 1), randf_range(-0.4, 0.8), randf_range(-1, 1)) * 0.18).normalized()
				var flame := world.spawn_projectile(Team.PLAYER, muzzle, dir * randf_range(45, 75), "fire", [Palette.WHITE, Palette.PEACH, Palette.BUTTER, Palette.AMBER][i % 4])
				flame.hit = Hit.make(Hit.Kind.FIRE, 45.0, muzzle)
				flame.hit.incendiary = true
				flame.gravity = 6.0
				flame.life = randf_range(0.6, 0.95)
				flame.radius = 0.6
				flame.impacted.connect(_on_flame_impact)
		_:
			var speed := 600.0 if round == Armament.Round.APFSDS else Armament.SHELL_SPEED
			var shape := "dart" if round == Armament.Round.APFSDS else "shell"
			var dir := _fire_direction(muzzle, speed)
			var shell := world.spawn_projectile(Team.PLAYER, muzzle, dir * speed, shape, Armament.ROUND_COLORS[round])
			shell.hit = Hit.make(Hit.Kind.SHELL, Armament.SHELL_DAMAGE, muzzle)
			shell.hit.caliber = 100
			shell.hit.source = self
			shell.hit.stagger = 0.4
			shell.gravity = 2.0
			shell.life = 2.0
			shell.impact_sound = "impact"
			shell.impacted.connect(_count_hit, CONNECT_ONE_SHOT)
			match round:
				Armament.Round.APHE:
					shell.blast_radius = 12.0
					shell.blast_damage = 600.0
				Armament.Round.HEAT:
					shell.hit.damage = Armament.SHELL_DAMAGE * 1.5
					shell.hit.pierce = true
					shell.hit.stagger = 1.0
					shell.blast_radius = 9.0
					shell.blast_damage = 500.0
					shell.blast_colors = [Palette.WHITE, Palette.CORAL, Palette.RED, Palette.PEACH]
				Armament.Round.APFSDS:
					shell.hit.damage = Armament.SHELL_DAMAGE * 2.0
					shell.hit.pierce = true
					shell.pierce_entities = true
					shell.gravity = 0.0
					shell.life = 0.7
					# The dart goes through everything in line and slams into the ground with a crater.
					shell.blast_radius = 7.0
					shell.blast_damage = 450.0
				Armament.Round.AIRBURST:
					shell.hit.damage = 70.0
					shell.fuse_distance = maxf(muzzle.distance_to(aim_point) - 2.0, 6.0)
					shell.airburst_fragments = 70
	if round != Armament.Round.APHE:
		round_count -= 1
		if round_count <= 0:
			current_round = Armament.Round.APHE
		round_changed.emit()
	reload = (Armament.HEAT_RELOAD if round == Armament.Round.HEAT else Armament.RELOAD) * modules.reload_factor()
	_cannon_feedback(muzzle, barrel_dir)


## A player cannon hit template for blasts fired straight from the muzzle.
func _cannon_hit() -> Hit:
	var hit := Hit.make(Hit.Kind.BLAST, 0.0, global_position)
	hit.source = self
	hit.stagger = 1.0
	return hit


func _cannon_feedback(muzzle: Vector3, dir: Vector3) -> void:
	var world := World.current
	_barrel_recoil = 0.7
	if world.rail.mode != Rail.Mode.ARENA:
		local_velocity.y -= 8.0 * dir.dot(world.rail.forward())
	world.camera.kick(0.035)
	world.shake(0.28)
	world.fx.light_flash(muzzle, 12.0, Palette.BUTTER, 26.0)
	world.fx.muzzle_flash(muzzle, dir, 2.4)
	# Muzzle-brake jets blast out sideways.
	var side_dir := dir.cross(Vector3.UP).normalized()
	for side in [-1.0, 1.0]:
		world.fx.muzzle_flash(muzzle - dir * 0.3, (side_dir * side + dir * 0.3).normalized(), 1.1, Palette.PEACH)
	for i in 20:
		var spread := (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.35).normalized()
		world.fx.spawn(Fx.Kind.FLAME, muzzle, spread * randf_range(8, 22), randf_range(0.06, 0.14), randf_range(0.5, 0.9), [Palette.WHITE, Palette.BUTTER, Palette.PEACH][i % 3], {"drag": 8.0})
	for i in 10:
		var side := dir.cross(Vector3.UP).normalized() * (1.0 if i % 2 == 0 else -1.0)
		world.fx.spawn(Fx.Kind.GLOW, muzzle, (side * randf_range(3, 7) + dir * randf_range(2, 8) + Vector3.UP), randf_range(0.8, 1.5), 0.6, [Palette.MIST, Palette.CREAM][i % 2], {"end_size": 2.2, "drag": 2.5, "gravity": -0.5, "fade": 0.15})
	# The blast flattens the ground below the muzzle.
	var ground := muzzle
	ground.y = Course.height_at(muzzle)
	if muzzle.y - ground.y < 4.0:
		world.fx.dust(ground, 8, 2.5, Palette.STRAW)
	Sfx.play("cannon", muzzle, 0.0, randf_range(0.95, 1.05))


## Main-gun impacts. A shell landing on an enemy freezes the frame for a beat and bucks the camera.
func _count_hit(projectile: Projectile, point: Vector3, target: Entity) -> void:
	var world := World.current
	world.shake(0.3, point)
	if target and target.team == Team.ENEMY:
		world.stats.shot_hits += 1
		world.hitstop(0.045)
		world.fx.light_flash(point, 16.0, Palette.WHITE, 22.0)
		world.fx.sparks(point, projectile.splash_direction(), 18, Palette.WHITE, 18.0)


## Dragon's breath sets the ground alight where flames land.
func _on_flame_impact(_projectile: Projectile, point: Vector3, target: Entity) -> void:
	if target == null and randf() < 0.3:
		FireZone.ignite(point)


func _update_ciws(delta: float) -> void:
	var world := World.current
	_ciws_sound_cooldown = maxf(0.0, _ciws_sound_cooldown - delta)
	if not modules.laser_online():
		ciws_target = null
		return
	if ciws_overheated:
		ciws_heat = maxf(0.0, ciws_heat - CIWS_COOL_RATE * delta)
		if ciws_heat <= 0.3:
			ciws_overheated = false
		ciws_target = null
		return
	var origin := model.rws_lens.global_position
	var target: Object = null
	var best := INF
	for projectile in world.projectiles:
		if not projectile.interceptable or projectile.team == Team.PLAYER or projectile.is_queued_for_deletion():
			continue
		var offset := global_position - projectile.global_position
		var distance := offset.length()
		if distance > CIWS_RANGE or projectile.velocity.dot(offset) <= 0.0:
			continue
		var eta := distance / maxf(projectile.velocity.length(), 1.0)
		if eta < best:
			best = eta
			target = projectile
	for enemy in world.enemies:
		if not enemy.interceptable:
			continue
		var distance := enemy.hit_center().distance_to(global_position)
		if distance > CIWS_DRONE_RANGE:
			continue
		var eta := distance / 20.0
		if eta < best:
			best = eta
			target = enemy
	if target == null:
		ciws_target = null
		ciws_heat = maxf(0.0, ciws_heat - CIWS_COOL_RATE * delta)
		model.rws.rotation.y = rotate_toward(model.rws.rotation.y, 0.0, 3.0 * delta)
		return
	if target != ciws_target and _ciws_sound_cooldown <= 0.0:
		Sfx.play("zap", origin, -6.0, randf_range(0.9, 1.2))
		_ciws_sound_cooldown = 0.12
	ciws_target = target
	var point: Vector3 = (target as Node3D).global_position
	if target is Entity:
		point = (target as Entity).hit_center()
	var local := model.turret.global_transform.affine_inverse() * point
	model.rws.rotation.y = atan2(-local.x, -local.z)
	var flicker := randf_range(0.7, 1.0)
	world.fx.beam(origin, point, Palette.WHITE, 0.07 * flicker, 0.04)
	world.fx.beam(origin, point, Palette.MINT, 0.2 * flicker, 0.04)
	world.fx.spawn(Fx.Kind.FLAME, point, Vector3(randf_range(-2, 2), randf_range(0, 3), randf_range(-2, 2)), 0.1, 0.3, Palette.WHITE)
	if target is Projectile:
		if (target as Projectile).laser(CIWS_LASER_DPS * delta):
			ciws_heat += 0.06
			world.award(10, point, false)
			world.intercepted.emit(point)
	else:
		var zap := Hit.make(Hit.Kind.LASER, CIWS_ENTITY_DPS * delta, point)
		zap.source = self
		(target as Entity).take_hit(zap)
		if (target as Entity).dead:
			world.intercepted.emit(point)
	ciws_heat += CIWS_HEAT_RATE * delta
	if ciws_heat >= 1.0:
		ciws_heat = 1.0
		ciws_overheated = true
		ciws_target = null
		Sfx.play("overheat", origin)
		world.radio.emit(&"AI_OVERHEAT")


## Tail button: throw what is held, else snatch a pickup, grab or stab an enemy, or swat around.
## The tail acts on its own so the driver only drives and shoots. Priorities: throw what it
## holds, swat anything about to hit the hull, snatch pickups, grab small enemies, stab big ones.
func auto_tail() -> void:
	if tail.destroyed:
		return
	var world := World.current
	var mount := tail.mount.global_position
	if is_instance_valid(tail.held):
		# Whatever the claw holds is dealt with at once, whatever state a drift or roll left it in:
		# pickups are delivered, enemies are thrown after a short dangle.
		if tail.held is Pickup:
			if tail.state != Tail.State.RETURN:
				collect(tail.held as Pickup)
				tail.held = null
				tail.set_state(Tail.State.IDLE)
		elif tail.state != Tail.State.HOLD or tail.state_time() >= HOLD_TIME:
			_throw_held()
		return
	if not tail.is_ready():
		return
	for entity in world.enemies:
		if _is_imminent(entity):
			swat()
			return
	var best_pickup: Pickup = null
	var best_distance := Tail.REACH
	for pickup in world.pickups:
		var distance := pickup.global_position.distance_to(mount)
		if not pickup.collected and distance < best_distance:
			best_distance = distance
			best_pickup = pickup
	if best_pickup:
		best_pickup.carry()
		_grab_target = best_pickup
		tail.set_state(Tail.State.REACH, best_pickup.global_position, best_pickup, 220.0)
		Sfx.play("whip", mount, 0.0, 1.2)
		return
	var best_enemy: Enemy = null
	best_distance = Tail.REACH
	for entity in world.enemies:
		if entity is Enemy and ((entity as Enemy).grabbable or (entity as Enemy).stabbable):
			var distance := entity.hit_center().distance_to(mount) - entity.radius
			if distance < best_distance:
				best_distance = distance
				best_enemy = entity
	if best_enemy:
		_grab_target = best_enemy
		var state := Tail.State.REACH if best_enemy.grabbable else Tail.State.STAB
		tail.set_state(state, best_enemy.hit_center(), best_enemy, 260.0)
		Sfx.play("whip", mount)


## Diving drones and bursting crawlers close to the hull.
func _is_imminent(entity: Entity) -> bool:
	var distance := entity.hit_center().distance_to(hit_center())
	if entity is FpvDrone:
		return (entity as FpvDrone).state != FpvDrone.State.APPROACH and distance < 9.0
	if entity is Crawler:
		return (entity as Crawler).state != Crawler.State.RUN and distance < 7.0
	return false


## A full-circle lash that bats away drones and crawlers and flattens small props.
func swat(start_state := true) -> void:
	var world := World.current
	var mount := tail.mount.global_position
	if start_state:
		tail.set_state(Tail.State.SWAT, mount, null, 300.0)
		tail.start_cooldown(1.2)
		get_tree().create_timer(0.3).timeout.connect(func() -> void:
			if tail.state == Tail.State.SWAT:
				tail.set_state(Tail.State.IDLE))
	Sfx.play("whip", mount, 0.0, 0.8)
	for entity in world.enemies.duplicate():
		if entity.hit_center().distance_to(global_position) < 7.5 + entity.radius:
			if _is_imminent(entity):
				world.style_event("DEFLECT", 80.0)
			var hit := Hit.make(Hit.Kind.TAIL, 30.0, entity.hit_center(), (entity.hit_center() - global_position).normalized())
			hit.stagger = 0.6
			hit.source = self
			entity.take_hit(hit)
			world.fx.sparks(entity.hit_center(), hit.direction, 8, Palette.FUNGUS)
	for prop: Prop in world.props.in_radius(global_position, 7.0):
		if prop.crushable:
			prop.take_hit(Hit.make(Hit.Kind.TAIL, 999.0, prop.global_position))


func _on_tail_arrived() -> void:
	var world := World.current
	match tail.state:
		Tail.State.REACH:
			if not is_instance_valid(_grab_target):
				tail.set_state(Tail.State.IDLE)
			elif _grab_target is Pickup:
				var pickup := _grab_target as Pickup
				tail.held = pickup
				tail.set_state(Tail.State.RETURN, Vector3.ZERO, null, 200.0)
			elif is_instance_valid(_grab_target) and _grab_target is Enemy and not (_grab_target as Enemy).dead:
				var enemy := _grab_target as Enemy
				tail.held = enemy.grab()
				world.award(enemy.score / 2, enemy.global_position, true)
				world.style_event("SNATCH", 45.0)
				enemy.die_silently()
				tail.set_state(Tail.State.HOLD, Vector3.ZERO, null, 120.0)
				world.shake(0.15)
				Sfx.play("grab", tail.claw_position())
			else:
				tail.set_state(Tail.State.IDLE)
			_grab_target = null
		Tail.State.RETURN:
			if is_instance_valid(tail.held) and tail.held is Pickup:
				collect(tail.held as Pickup)
			tail.held = null
			tail.set_state(Tail.State.IDLE)
			tail.start_cooldown(0.6)
		Tail.State.STAB:
			if is_instance_valid(_grab_target) and _grab_target is Entity:
				var enemy := _grab_target as Entity
				var stab := Hit.make(Hit.Kind.TAIL, 75.0, tail.claw_position(), (enemy.hit_center() - global_position).normalized())
				stab.stagger = 1.4
				stab.source = self
				stab.pierce = true
				enemy.take_hit(stab)
				if enemy is Enemy:
					(enemy as Enemy).interrupt()
				world.fx.sparks(tail.claw_position(), -stab.direction, 14, Palette.FUNGUS, 12.0)
				world.fx.spores(tail.claw_position(), 6, 0.6)
				world.hitstop(0.06)
				world.shake(0.25)
				Sfx.play("stab", tail.claw_position())
			_grab_target = null
			tail.set_state(Tail.State.IDLE)
			tail.start_cooldown()
		Tail.State.THROW:
			pass


func _throw_held() -> void:
	var world := World.current
	var held := tail.held
	tail.held = null
	var from := tail.claw_position()
	var target := _throw_target()
	# Lob with a slight arc so thrown wrecks read as heavy.
	var flat := Vector3(target.x - from.x, 0, target.z - from.z)
	var speed := 48.0
	var time := maxf(flat.length() / speed, 0.15)
	var velocity_out := flat / time
	velocity_out.y = (target.y - from.y) / time + 0.5 * 18.0 * time
	var thrown := world.spawn_projectile(Team.PLAYER, from, velocity_out, "mortar", Palette.WOOD)
	for child in thrown.get_children():
		child.queue_free()
	held.reparent(thrown, false)
	held.position = Vector3.ZERO
	thrown.gravity = 18.0
	thrown.radius = 1.3
	thrown.life = 3.0
	thrown.hit = Hit.make(Hit.Kind.THROWN, 120.0, from)
	thrown.hit.stagger = 1.0
	thrown.hit.source = self
	thrown.blast_radius = 5.0
	thrown.blast_damage = 70.0
	thrown.impacted.connect(func(_p: Projectile, point: Vector3, _t: Entity) -> void:
		World.current.hitstop(0.05)
		World.current.fx.debris(point, 10, [Palette.INK, Palette.HULL, Palette.OCHRE], 9.0, 0.4))
	tail.set_state(Tail.State.THROW, from + velocity_out.normalized() * 6.0, null, 300.0)
	tail.start_cooldown()
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		if tail.state == Tail.State.THROW:
			tail.set_state(Tail.State.IDLE))
	Sfx.play("whip", from, 2.0, 0.7)
	world.shake(0.15)


func _throw_target() -> Vector3:
	if is_instance_valid(aim_target):
		return aim_target.hit_center()
	var best := aim_point
	var best_distance := 70.0
	var forward := -global_basis.z
	for enemy in World.current.enemies:
		var offset := enemy.hit_center() - global_position
		if offset.dot(forward) > 0.0 and offset.length() < best_distance:
			best_distance = offset.length()
			best = enemy.hit_center()
	return best


func _update_pickups() -> void:
	for pickup in World.current.pickups.duplicate():
		if not pickup.collected and pickup != tail.held and pickup.global_position.distance_to(global_position + Vector3.UP) < Pickup.COLLECT_RADIUS:
			collect(pickup)


func collect(pickup: Pickup) -> void:
	if pickup.collected:
		return
	pickup.collected = true
	var world := World.current
	match pickup.id:
		"coax":
			if coax_tier < Armament.COAX_TIERS.size() - 1:
				set_coax_tier(coax_tier + 1)
			else:
				world.award(2000, global_position, false)
		"repair":
			hp = minf(hp + 35.0, max_hp)
			modules.repair_all()
			if not tail.destroyed:
				tail.repair(60.0)
		"era":
			modules.restore_era()
		"tail":
			if tail.destroyed:
				tail.regrow()
			else:
				tail.repair(Tail.MAX_HP)
		"life":
			world.stats.lives += 1
		_:
			load_round(Armament.round_from_id(pickup.id))
	world.award(100, pickup.global_position, false)
	world.fx.shockwave(pickup.global_position, 4.0, pickup.color())
	world.fx.sparks(pickup.global_position, Vector3.UP, 16, pickup.color(), 8.0)
	Sfx.play("pickup", pickup.global_position)
	pickup_collected.emit(pickup.id)
	pickup.queue_free()


## Which side of the hull a hit arrives from: "front", "left", "right" or "rear".
func facing_of(hit: Hit) -> String:
	var incoming := -hit.direction
	incoming.y = 0.0
	if incoming.length() < 0.01:
		incoming = hit.position - global_position
		incoming.y = 0.0
	if incoming.length() < 0.01:
		return "front"
	incoming = incoming.normalized()
	var front := (-global_basis.z).dot(incoming)
	if front > 0.5:
		return "front"
	if front < -0.5:
		return "rear"
	return "right" if global_basis.x.dot(incoming) > 0.0 else "left"


func damage_multiplier(hit: Hit) -> float:
	if invuln > 0.0 or _respawn > 0.0:
		return 0.0
	var multiplier := 1.0
	if hit.kind == Hit.Kind.BULLET and hit.caliber < 20:
		multiplier *= 0.35
	# Frontal armor is thick, the rear is weak.
	match facing_of(hit):
		"front":
			multiplier *= 0.6
		"rear":
			multiplier *= 1.4
	return multiplier


## Shaped charges are decided by ERA: a block on that facing eats it, otherwise it is fatal.
func take_hit(hit: Hit) -> void:
	if dead or invulnerable or _respawn > 0.0:
		return
	if hit.warhead and invuln <= 0.0:
		var world := World.current
		var facing := facing_of(hit)
		if modules.consume_era(facing):
			world.fx.explosion(hit.position, 1.8, [Palette.WHITE, Palette.SKY, Palette.BUTTER])
			world.fx.debris(hit.position, 8, [Palette.HULL, Palette.INK], 8.0, 0.3)
			world.shake(0.35)
			world.screen_flash(Palette.SKY, 0.2)
			Sfx.play("blast_small", hit.position, 2.0, 0.8)
			world.radio.emit(&"AI_ERA" if modules.era[facing] > 0 else &"AI_ERA_GONE")
			world.style_event("CLOSE_CALL", 40.0)
			invuln = 0.15
			return
		world.radio.emit(&"AI_PENETRATION")
		world.stats.damage_taken += hp
		die(hit)
		return
	super(hit)


func on_damaged(hit: Hit, amount: float) -> void:
	var world := World.current
	world.stats.damage_taken += amount
	world.stats.section_damage += amount
	world.stats.lose_style(RunStats.STYLE_HIT_PENALTY * clampf(amount / 15.0, 0.3, 1.5))
	world.shake(clampf(amount / 25.0, 0.1, 0.6))
	world.screen_flash(Palette.CORAL, clampf(amount / 40.0, 0.12, 0.45))
	world.fx.sparks(hit.position, -hit.direction, 6, Palette.CORAL)
	Sfx.play("hurt", global_position, 0.0, randf_range(0.9, 1.1))
	_damage_modules(hit, amount)
	invuln = maxf(invuln, 0.12)
	if hp < MAX_ARMOR * 0.3 and hp + amount >= MAX_ARMOR * 0.3:
		world.radio.emit(&"AI_LOW_ARMOR")


## Heavy hits knock out the modules exposed on the facing they come from.
func _damage_modules(hit: Hit, amount: float) -> void:
	var world := World.current
	var facing := facing_of(hit)
	if facing == "rear" and tail.damage(amount * 1.2):
		world.fx.explosion(tail.mount.global_position, 1.5, [Palette.WHITE, Palette.FUNGUS, Palette.BLUSH])
		world.radio.emit(&"AI_MOD_TAIL")
	if hit.kind == Hit.Kind.BULLET and hit.caliber < 20:
		return
	var exposed: Array = TankModules.EXPOSED[facing]
	var name: String = exposed[randi() % exposed.size()]
	if modules.damage(name, amount * 1.3):
		world.radio.emit(StringName("AI_MOD_" + name.to_upper() + ("_OUT" if modules.state(name) == TankModules.State.DESTROYED else "")))
		world.fx.sparks(hit_center(), Vector3.UP, 14, Palette.BUTTER, 10.0)


## Losing all armor costs a life instead of removing the tank.
func die(_hit: Hit) -> void:
	var world := World.current
	world.fx.explosion(global_position + Vector3.UP, 5.0)
	world.fx.debris(global_position + Vector3.UP, 20, [Palette.HULL, Palette.PINE, Palette.INK], 12.0, 0.5)
	world.shake(1.0)
	world.hitstop(0.2)
	world.screen_flash(Palette.WHITE, 0.8)
	Sfx.play("blast", global_position)
	world.stats.lives -= 1
	world.stats.combo = 0
	set_coax_tier(coax_tier - 1)
	if is_instance_valid(tail.held):
		tail.held.queue_free()
		tail.held = null
	tail.set_state(Tail.State.IDLE)
	life_lost.emit()
	hp = 0.0
	if world.stats.lives <= 0:
		dead = true
		model.visible = false
		tail.visible = false
		input_enabled = false
		world.game_over.emit()
		return
	_respawn = RESPAWN_DELAY
	world.radio.emit(&"AI_LIFE_LOST")


func _finish_respawn() -> void:
	hp = max_hp
	modules.restore()
	tail.regrow()
	invuln = RESPAWN_INVULN
	course_u = 0.0
	course_offset = 4.0
	local_velocity = Vector2.ZERO
	model.visible = true
	tail.visible = true
	World.current.fx.shockwave(global_position, 6.0, Palette.MINT)
