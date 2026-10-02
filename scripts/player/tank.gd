class_name Tank
extends Entity
## The player's Orca-class. Moves within the rail frame (or freely in the arena), aims the turret
## at the reticle, fires the coax and 100 mm gun, runs the laser CIWS (once an RWS is mounted) and drives the tail.

signal pickup_collected(id: String)
signal round_changed
signal life_lost
signal charge_locked(target: Entity)

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
const ANCHOR_COOLDOWN := 0.6
const REFLECT_RANGE := 5.0 ## A dash turns back every hostile shot this close to the hull.
const REFLECT_SPEED := 1.2
const REFLECT_DAMAGE := 120.0
const DASH_DISTANCE := 13.0 ## Twice the hull's length.
const DASH_TIME := 0.35
const DASH_SPEED := 2.0 * DASH_DISTANCE / DASH_TIME ## Starts this fast and eases to a stop, covering DASH_DISTANCE.
const COAX_RANGE := 140.0
const SOFT_LOCK_RADIUS := 40.0 ## Screen pixels (3D view) around the reticle; the FCS scales it.
const LOCK_HOLD := 1.4 ## A held soft lock lasts out to this many radii from the reticle.
const LOCK_SWITCH := 0.6 ## Another enemy takes a held lock only when this much nearer the reticle.
const SIGHT_RATE := 10.0 ## Per second the chevron's range eases toward the range it rests on.
const PART_LOCK_RADIUS := 90.0 ## Screen pixels: on a target made of modules, the nearest one within this is locked.
const RESPAWN_DELAY := 1.8
const RESPAWN_INVULN := 2.6
const CRUSH_SPEED := 5.0 ## Ground speed above which the tank runs down ground enemies.
const RAM_DAMAGE := 150.0
const CANISTER_RANGE := 70.0
const SMALL_ARMS_CALIBER := 40 ## Bullets below this glance off the armor; only the exposed sensors feel them.
const TOP_ATTACK_ANGLE := deg_to_rad(7.0) ## Descent that makes a bullet hit the roof. Helicopters (8-15 deg at station) and UAVs (10+) fire down at this; ground gunners stay under 5 (95th percentile).
const ROOF_CALIBER := 20 ## Bullets from this caliber up, coming down on the roof, punch through it.
## How close (angle from the hull's center) a small-arms hit must land to a roof sensor to break it.
## Enemy fire arrives low, the sensors sit high on the roof: this wide cone is what makes about one
## in seven of the rounds that reach the hull count (see small_arms_test).
const SENSOR_STRIKE_ANGLE := deg_to_rad(82.0)

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
var sight_range := 0.0 ## Smoothed range of the chevron along the barrel.
var _sight_lock: Entity
var _lay_offset := Vector3.ZERO ## Eased offset of the aimed spot from the locked target's center.
var using_gamepad := false

var coax_tier := 0
var current_round := Armament.Round.APHE
var round_count := 0
var charge := 0.0
var charge_lock: Entity
var charge_part := ""
var _charge_time := 0.0
var _cannon_held := false
var _cannon_released := false
var _full_click := false
var _coax_timers: Array[float] = []

var ciws_heat := 0.0
var ciws_overheated := false
var ciws_target: Object
var _ciws_sound_cooldown := 0.0

var invuln := 0.0
var _blink := 0.0 ## Blinks while the fresh hull's respawn cover lasts; dashes and hits never blink.
var _ghost_timer := 0.0
var _ghost_hue := 0.0
var anchor_cooldown := 0.0
var _drift := 0.0
var _drift_dir := 0.0
var _respawn := 0.0
var _barrel_recoil := 0.0
var _last_position := Vector3.ZERO
var _grab_target: Node3D
var coax_target: Entity ## What the coax is tracking on its own.
var coax_part := "" ## Which module of the locked target the guns are on, if it has several.
var _last_lateral := 1.0 ## The way the tank last steered sideways: where Space dashes with nothing held.
var _engine_sound: AudioStreamPlayer3D
var input_enabled := true:
	set(value):
		input_enabled = value
		if not value:
			_cancel_charge()


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
	tail.missed.connect(_drop_grab)
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


## The roof sensors show only while mounted.
func _sync_sensors() -> void:
	model.rws.visible = modules.laser_online()
	model.fcs.visible = modules.state("fcs") != TankModules.State.DESTROYED


## Lets go of what the claw reaches for or carries: a pickup stays in the world to be collected.
func _drop_grab() -> void:
	for thing: Variant in [_grab_target, tail.held]:
		if is_instance_valid(thing) and thing is Pickup:
			(thing as Pickup).release()
	_grab_target = null
	tail.held = null


func mount_rws() -> void:
	modules.mount_rws()
	_sync_sensors()


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
	show_damage(delta, HULL_RADIUS)
	anchor_cooldown = maxf(0.0, anchor_cooldown - delta)
	_update_charge(delta)
	modules.update(delta)
	_sync_sensors()
	_blink = maxf(0.0, _blink - delta)
	model.visible = _blink <= 0.0 or fmod(_blink, 0.16) < 0.1
	tail.visible = model.visible and not tail.destroyed
	if _drift > 0.0:
		_dash_trail(delta)
	_update_movement(delta)
	_update_aim(delta)
	_update_weapons(delta)
	_update_ciws(delta)
	_reflect_shots()
	tail.update(delta, global_basis, lateral_velocity)
	auto_tail() # The tail and the coax work on their own; only driving and the main gun take input.
	_update_pickups()
	tracks.press(global_transform, delta)
	model.rotation.x = move_toward(model.rotation.x, 0.0, delta * 0.8)
	velocity = (global_position - _last_position) / maxf(delta, 0.0001)
	_last_position = global_position
	wade(delta, velocity, HULL_RADIUS)
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
	_read_dash(input)
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
			local_velocity.x = _drift_dir * DASH_SPEED * (_drift / DASH_TIME)
	course_u += local_velocity.x * delta
	course_offset += local_velocity.y * delta
	var limit := lateral_limit(rail.d + course_offset)
	course_u = clampf(course_u, -limit, limit)
	course_offset = clampf(course_offset, FORWARD_LIMIT.x, FORWARD_LIMIT.y)
	lateral_velocity = local_velocity.x
	_collide_props()
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
		current = right * _drift_dir * DASH_SPEED * (_drift / DASH_TIME) if absf(_drift_dir) > 0.0 else current
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
	_collide_props()
	_ram_enemies()
	model.animate_tracks(delta, current.length(), current.length())


## Space dashes the way the tank is steered: sideways if A or D is held, else forward on W alone or a
## hard stop on S alone, and with nothing held the way it last steered sideways. Gamepad shoulders
## dash sideways.
func _read_dash(input: Vector2) -> void:
	if absf(input.x) > 0.3:
		_last_lateral = signf(input.x)
	if not input_enabled:
		return
	if Input.is_action_just_pressed("roll_left"):
		dash(Vector2(-1, 0))
	elif Input.is_action_just_pressed("roll_right"):
		dash(Vector2(1, 0))
	elif Input.is_action_just_pressed("dash"):
		dash(Vector2(signf(input.x), 0) if absf(input.x) > 0.3 else Vector2(0, signf(input.y)) if absf(input.y) > 0.3 else Vector2(_last_lateral, 0))


## A burst of speed the way it was asked for, kicked off by the tail slamming the ground: sideways it
## is a dodge that lashes whatever is beside the hull, forward it surges the rail, back it digs in.
func dash(direction: Vector2) -> void:
	if _respawn > 0.0:
		return
	if absf(direction.x) > 0.3:
		_last_lateral = signf(direction.x)
	_anchor(direction)


## Sandevistan-style: while dashing, the hull leaves a string of afterimages behind it, each a
## different hue, fading as the next one appears.
func _dash_trail(delta: float) -> void:
	_ghost_timer -= delta
	if _ghost_timer > 0.0:
		return
	_ghost_timer = 0.03
	_ghost_hue = fmod(_ghost_hue + 0.09, 1.0)
	World.current.fx.afterimage(_meshes, Color.from_hsv(_ghost_hue, 0.65, 1.0))


func is_dashing() -> bool:
	return _drift > 0.0


## While dashing, every hostile shot within REFLECT_RANGE of the hull is turned back on its shooter.
func _reflect_shots() -> void:
	if not is_dashing():
		return
	for projectile in World.current.projectiles.duplicate():
		if projectile.team != Team.PLAYER and not projectile.is_queued_for_deletion() and projectile.global_position.distance_to(hit_center()) < REFLECT_RANGE:
			_reflect(projectile)


## The shot becomes the player's and flies straight back at where its shooter is now (or the way it came
## if the shooter is gone), faster, as a heavy hit that staggers.
func _reflect(projectile: Projectile) -> void:
	var world := World.current
	var shooter: Variant = projectile.hit.source
	var back := -projectile.velocity
	if is_instance_valid(shooter) and shooter is Entity and not shooter.dead:
		back = shooter.hit_center() - projectile.global_position
	var speed := projectile.velocity.length() * REFLECT_SPEED
	projectile.velocity = back.normalized() * speed
	projectile.team = Team.PLAYER
	projectile.gravity = 0.0
	projectile.homing_target = null
	projectile.interceptable = false
	projectile.life = maxf(projectile.life, back.length() / speed + 1.0)
	projectile.hit.kind = Hit.Kind.SHELL
	projectile.hit.damage = maxf(projectile.hit.damage, REFLECT_DAMAGE)
	projectile.hit.stagger = 1.0
	projectile.hit.warhead = false
	projectile.hit.source = self
	projectile.hit.weapon = "reflect"
	world.reskin_projectile(projectile)
	world.style_event("REFLECT", 70.0)
	world.fx.sparks(projectile.global_position, back.normalized(), 10, Palette.CYAN, 14.0)
	world.fx.shockwave(projectile.global_position, 3.0, Palette.CYAN, 0.15)
	Sfx.play("impact", projectile.global_position, -4.0, 1.5)


func _anchor(input: Vector2) -> void:
	var world := World.current
	if anchor_cooldown > 0.0:
		return
	anchor_cooldown = ANCHOR_COOLDOWN
	invuln = maxf(invuln, DASH_TIME)
	_ghost_timer = 0.0
	world.screen_flash(Palette.CYAN, 0.1)
	var ground := global_position - global_basis.z * -3.0
	if absf(input.x) > 0.3:
		# Pivot drift: the claw bites the ground and the hull whips sideways around it.
		_drift = DASH_TIME
		_drift_dir = signf(input.x)
		swat(false)
		ground = global_position + global_basis.x * -_drift_dir * 2.5 + global_basis.z * 3.0
		Sfx.play("skid", global_position)
	elif input.y > 0.3:
		# Forward surge: the tail kicks off behind and the hull lunges ahead of the rail.
		_drift = DASH_TIME
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
	world.fx.debris(ground, 6, [Fx.Debris.DIRT], 5.0, 0.25)
	world.shake(0.2)
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		if tail.state == Tail.State.ANCHOR:
			tail.set_state(Tail.State.IDLE)
			world.fx.scorch(ground, 1.2))


## Sixty tons flatten anything they touch the moment they touch it, landmarks included.
func _collide_props() -> void:
	for prop: Prop in World.current.props.in_radius(global_position, HULL_RADIUS):
		if prop.is_falling():
			continue
		if prop.global_position.y > global_position.y + 2.5:
			continue # Resting up high (a tree crown, a spire): the hull passes under it.
		var ram := Hit.make(Hit.Kind.RAM, 99999.0, prop.global_position, -global_basis.z)
		ram.source = self
		prop.take_hit(ram)
		_ram_jolt(prop.footprint)


## The camera bucks and the hull rocks, more for bigger things, but nothing stops the tank: no
## frozen frame, no lost speed.
func _ram_jolt(size: float) -> void:
	var world := World.current
	var heavy := clampf(size / 4.0, 0.15, 1.0) * clampf(_ground_speed() / Rail.CRUISE, 0.5, 1.5)
	world.shake(0.1 + heavy * 0.3)
	world.camera.kick(0.01 + heavy * 0.03)
	model.rotation.x = -0.05 - heavy * 0.12
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
			ram.salvage = true
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
	# Against each enemy's real hit shape, so the sight rests on the exact part under the cursor
	# (a boss's rotor or rocket rack, not just its middle).
	for enemy in world.enemies:
		var t := enemy.hit_test(origin, origin + dir * best, 0.6)
		if t >= 0.0 and t < best:
			best = t
			aim_target = enemy
	var ground := _ray_ground(origin, dir, best)
	if ground >= 0.0 and ground < best:
		best = ground
		aim_target = null
	aim_point = origin + dir * best
	# Turret traverse and gun elevation follow the soft-locked target's lead point, else the aim
	# point. Seen from the low muzzle, a drone and the ground past it on the sight line are far
	# apart, and rounds may only leave a few degrees off the barrel.
	var lay := aim_point
	var lock := _pick_coax_target()
	_update_charge_lock()
	if is_instance_valid(charge_lock):
		lock = charge_lock
	var ease_in := 1.0 if lock != _sight_lock else 1.0 - exp(-SIGHT_RATE * delta) # Snaps when the lock changes hands.
	if is_instance_valid(lock):
		var speed: float = Armament.SHELL_SPEED if lock == charge_lock else Armament.GUNS[Armament.tier_calibers(coax_tier)[0]].speed
		# The aimed spot eases, so the sight sliding on and off the target's shape does not jerk the barrel.
		var spot := _aimed_spot(lock)
		_lay_offset = _lay_offset.lerp(Vector3.ZERO if spot == Vector3.INF else spot - lock.hit_center(), ease_in)
		lay = lead_point(model.muzzle.global_position, speed, lock, lock.hit_center() + _lay_offset)
	# The sight's range follows the locked target's lay point, else the aim point, and eases too.
	sight_range = lerpf(sight_range, model.muzzle.global_position.distance_to(lay), ease_in)
	_sight_lock = lock
	var local := model.turret.global_transform.affine_inverse() * lay
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
	var lock := charge_lock if is_instance_valid(charge_lock) else coax_target
	if is_instance_valid(lock) and lock is Enemy:
		target = lead_point(from, speed, lock, _aimed_spot(lock))
	return along_barrel(-model.barrel.global_basis.z, (target - from).normalized())


## Where to aim so a round at `speed` meets `target`: a few passes settle the flight time.
## Where to shoot to hit `target` (at `spot` on it, or its middle) as it moves.
func lead_point(from: Vector3, speed: float, target: Entity, spot := Vector3.INF) -> Vector3:
	var enemy_velocity := (target as Enemy).track_velocity if target is Enemy and modules.lead_online() else Vector3.ZERO
	var p := target.hit_center() if spot == Vector3.INF else spot
	var aim := p
	for i in 3:
		aim = p + enemy_velocity * (from.distance_to(aim) / speed)
	return aim


func _cancel_charge() -> void:
	charge = 0.0
	_charge_time = 0.0
	_cannon_held = false
	_cannon_released = false
	_full_click = false
	charge_lock = null
	charge_part = ""


func is_charging() -> bool:
	return input_enabled and _cannon_held and _charge_time >= Armament.CHARGE_DELAY


## Seconds a full charge takes after the delay: a damaged breech loads slower.
func charge_time() -> float:
	return Armament.CHARGE_TIME * modules.breech_factor()


func _update_charge(delta: float) -> void:
	if not input_enabled or dead or _respawn > 0.0:
		_cancel_charge()
		return
	var held := Input.is_action_pressed("fire_cannon")
	_cannon_released = _cannon_held and not held
	if held:
		var before := _charge_time
		_charge_time += delta
		if before < Armament.CHARGE_DELAY and _charge_time >= Armament.CHARGE_DELAY:
			Sfx.play("charge", global_position)
		charge = clampf((_charge_time - Armament.CHARGE_DELAY) / charge_time(), 0.0, 1.0)
		if charge >= 1.0 and not _full_click:
			_full_click = true
			Sfx.play("charge_full", global_position)
	_cannon_held = held


## Canister shows the actual cone footprint at the sight's range, in 3D-view pixels.
func charge_ring_radius() -> float:
	if current_round != Armament.Round.CANISTER:
		return lerpf(Armament.CHARGE_RING.x, Armament.CHARGE_RING.y, charge)
	var cam := World.current.camera
	var distance := model.muzzle.global_position.distance_to(aim_point)
	var radius := distance * Armament.CANISTER_SPREAD
	var center := cam.unproject_position(aim_point)
	var pixels := maxf(center.distance_to(cam.unproject_position(aim_point + cam.global_basis.x * radius)), center.distance_to(cam.unproject_position(aim_point + cam.global_basis.y * radius)))
	return clampf(pixels, 8.0, 220.0)


func _charge_distance(target: Entity, part: String) -> float:
	if _lock_distance(target) == INF:
		return INF
	var parts := target.aim_parts()
	var at: Vector3 = parts[part][0] if parts.has(part) else target.hit_center()
	var cam := World.current.camera
	return INF if cam.is_position_behind(at) else cam.unproject_position(at).distance_to(aim_screen)


func _update_charge_lock() -> void:
	if (not is_charging() and not _cannon_released) or modules.lock_factor() <= 0.0:
		charge_lock = null
		charge_part = ""
		return
	if is_instance_valid(charge_lock) and _charge_distance(charge_lock, charge_part) <= Armament.CHARGE_RING.y * LOCK_HOLD:
		return
	charge_lock = null
	charge_part = ""
	var candidate: Entity
	var part := ""
	var best := charge_ring_radius() * modules.lock_factor()
	for enemy in World.current.enemies:
		var nearest_part := _pick_part(enemy)
		var distance := _charge_distance(enemy, nearest_part)
		if distance < best:
			best = distance
			candidate = enemy
			part = nearest_part
	if charge >= 1.0 and candidate:
		charge_lock = candidate
		charge_part = part
		charge_locked.emit(candidate)


func _update_weapons(delta: float) -> void:
	coax_part = _pick_part(coax_target)
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
	if _cannon_released:
		if input_enabled and charge >= 1.0:
			fire_cannon(Vector3.INF, Vector3.ZERO, 1.0)
		_cancel_charge()


## The fire-control system's soft lock: the enemy under the reticle, else the one nearest it on
## screen within a small radius. The coax leads it automatically.
## The point to lead on a locked target: the locked module's middle, else exactly where the sight
## rests when it is on the target, otherwise its middle (a soft lock pulls toward the center).
func _aimed_spot(target: Entity) -> Vector3:
	if target == charge_lock and not charge_part.is_empty():
		var parts := target.aim_parts()
		if parts.has(charge_part):
			return parts[charge_part][0]
	if target == coax_target and not coax_part.is_empty():
		var parts := target.aim_parts()
		if parts.has(coax_part):
			return parts[coax_part][0]
	return aim_point if target == aim_target else Vector3.INF


## On a target made of modules, the one nearest the sight on screen.
func _pick_part(target: Entity) -> String:
	if not is_instance_valid(target):
		return ""
	var cam := World.current.camera
	var best := ""
	var best_distance := PART_LOCK_RADIUS
	var parts := target.aim_parts()
	for name: String in parts:
		var at: Vector3 = parts[name][0]
		if cam.is_position_behind(at):
			continue
		var distance := cam.unproject_position(at).distance_to(aim_screen)
		if distance < best_distance:
			best = name
			best_distance = distance
	return best


## Picks once a frame (in _update_aim) into `coax_target`, which the guns and the sight then share.
## A held lock stays while it is in range, on screen and within LOCK_HOLD radii of the reticle;
## another enemy takes it only by being clearly nearer the reticle (LOCK_SWITCH).
func _pick_coax_target() -> Entity:
	var held: Entity = coax_target if is_instance_valid(coax_target) else null
	coax_target = null
	if modules.lock_factor() <= 0.0:
		return null # The sight is gone: the guns go where the reticle points.
	if is_instance_valid(aim_target) and not aim_target.dead:
		coax_target = aim_target
		return coax_target
	var radius := SOFT_LOCK_RADIUS * modules.lock_factor()
	var limit := radius
	var held_distance := _lock_distance(held)
	if held_distance <= radius * LOCK_HOLD:
		coax_target = held
		limit = minf(radius, held_distance * LOCK_SWITCH)
	for enemy in World.current.enemies:
		if enemy == held:
			continue
		var distance := _lock_distance(enemy)
		if distance < limit:
			limit = distance
			coax_target = enemy
	return coax_target


## Screen distance from the reticle to an enemy the FCS could lock, else INF.
func _lock_distance(enemy: Entity) -> float:
	if not is_instance_valid(enemy) or enemy.dead or enemy is Flare:
		return INF
	var cam := World.current.camera
	if cam.is_position_behind(enemy.hit_center()) or enemy.hit_center().distance_to(global_position) > COAX_RANGE:
		return INF
	return cam.unproject_position(enemy.hit_center()).distance_to(aim_screen)


## Where the chevron sits: along the barrel at the smoothed sight range.
func sight_point() -> Vector3:
	return model.muzzle.global_position - model.barrel.global_basis.z * maxf(sight_range, 30.0)


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
	var aim := lead_point(from, spec.speed, target, _aimed_spot(target)) if is_instance_valid(target) else aim_point
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
	world.fx.muzzle_flash(from + dir * 0.2, dir, 0.55 + caliber * 0.04, spec.color)
	_barrel_recoil = maxf(_barrel_recoil, 0.08 + caliber * 0.006)
	world.shake(0.01 + caliber * 0.001)
	# Brass spills out of the mantlet and bounces off the deck.
	var eject := global_basis.x * randf_range(2.0, 4.0) + Vector3.UP * randf_range(3.0, 5.0)
	world.fx.spawn(Fx.Kind.SOLID, from - dir * 0.6, eject, 0.9, 0.15 + caliber * 0.01, Color.WHITE, {"gravity": 22.0, "bounce": true, "spin": 1.0, "material": Fx.Debris.BRASS})
	Sfx.gun(spec.sound, randf_range(0.93, 1.07))


## Fires the loaded round from the barrel, or from `from` along `toward` when given (the debug
## room shoots from its camera).
func fire_cannon(from := Vector3.INF, toward := Vector3.ZERO, power := 0.0) -> void:
	var muzzle := model.muzzle.global_position if from == Vector3.INF else from
	var barrel_dir := -model.barrel.global_basis.z if toward == Vector3.ZERO else toward.normalized()
	var shot_dir := func(speed: float) -> Vector3: return barrel_dir if toward != Vector3.ZERO else _fire_direction(muzzle, speed)
	var round := current_round
	power = clampf(power, 0.0, 1.0)
	World.current.stats.shots += 1
	if power >= 1.0:
		World.current.stats.charged_shots += 1
	match round:
		Armament.Round.CANISTER:
			_fire_canister(muzzle, shot_dir.call(200.0))
		Armament.Round.DRAGON:
			DragonBreath.fire(self, shot_dir.call(DragonBreath.MEAN_SPEED), from, power)
		_:
			_fire_shell(round, muzzle, shot_dir.call(Armament.SHELL_SPEED), power)
	if round != Armament.Round.APHE:
		round_count -= 1
		if round_count <= 0:
			current_round = Armament.Round.APHE
		round_changed.emit()
	_cannon_feedback(muzzle, barrel_dir, power)


## A wall of tungsten balls, and a muzzle blast that flattens everything just ahead.
func _fire_canister(muzzle: Vector3, aim_dir: Vector3) -> void:
	var world := World.current
	world.blast(muzzle + aim_dir * 7.0, 6.0, 260.0, Team.PLAYER, _cannon_hit(), null, [Palette.WHITE, Palette.BUTTER, Palette.AMBER], aim_dir)
	# Fifty hitscan balls land at once, each drawn as a yellow streak.
	var side := aim_dir.cross(Vector3.UP if absf(aim_dir.y) < 0.99 else Vector3.RIGHT).normalized()
	var up := side.cross(aim_dir)
	for i in 50:
		var spread := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * Armament.CANISTER_SPREAD
		var dir := (aim_dir + side * spread.x + up * spread.y).normalized()
		var pellet := world.spawn_projectile(Team.PLAYER, muzzle, dir * 200.0, "pellet", Palette.BUTTER)
		pellet.hit = Hit.make(Hit.Kind.BULLET, 90.0, muzzle)
		pellet.hit.caliber = 20
		pellet.hit.source = self
		pellet.hit.weapon = "cannon"
		pellet.impacted.connect(_count_hit, CONNECT_ONE_SHOT)
		var end := pellet.resolve_now(Armament.CANISTER_RANGE)
		world.fx.beam(muzzle, end, Palette.WHITE, 0.06, 0.08)
		world.fx.beam(muzzle, end, Palette.BUTTER, 0.18, 0.14)
		world.fx.spawn(Fx.Kind.FLAME, end, Vector3.UP * 2.0, 0.12, 0.5, Palette.BUTTER)


## A 100 mm hitscan shell (APHE, HEAT, APFSDS or airburst): it lands this very frame and a tracer
## flash marks its line.
func _fire_shell(round: Armament.Round, muzzle: Vector3, dir: Vector3, power := 0.0) -> void:
	var world := World.current
	var color: Color = Armament.ROUND_COLORS[round]
	var shell := world.spawn_projectile(Team.PLAYER, muzzle, dir * Armament.SHELL_SPEED, "dart" if round == Armament.Round.APFSDS else "shell", color)
	shell.hit = Hit.make(Hit.Kind.SHELL, Armament.SHELL_DAMAGE, muzzle)
	shell.hit.caliber = 100
	shell.hit.source = self
	shell.hit.weapon = "cannon"
	shell.hit.power = power
	shell.hit.stagger = 0.4
	shell.gravity = 0.0
	shell.life = 2.0
	shell.impact_sound = "impact"
	shell.impacted.connect(_count_hit, CONNECT_ONE_SHOT)
	match round:
		Armament.Round.APHE:
			# A small filler: it wrecks what it hits and, charged, the pack around it.
			shell.hit.damage *= lerpf(Armament.APHE_DAMAGE.x, Armament.APHE_DAMAGE.y, power)
			shell.blast_radius = lerpf(Armament.APHE_RADIUS.x, Armament.APHE_RADIUS.y, power)
			shell.blast_damage = lerpf(Armament.APHE_BLAST.x, Armament.APHE_BLAST.y, power)
			shell.pierce_entities = power >= 1.0
		Armament.Round.HEAT:
			shell.hit.damage = Armament.SHELL_DAMAGE * 1.5
			shell.hit.pierce = true
			shell.hit.stagger = lerpf(Armament.HEAT_STAGGER.x, Armament.HEAT_STAGGER.y, power)
			shell.blast_radius = lerpf(Armament.HEAT_RADIUS.x, Armament.HEAT_RADIUS.y, power)
			shell.blast_damage = 500.0
			shell.blast_colors = [Palette.WHITE, Palette.CORAL, Palette.RED, Palette.PEACH]
		Armament.Round.APFSDS:
			shell.hit.damage = Armament.SHELL_DAMAGE * 2.0 * lerpf(Armament.APFSDS_DAMAGE.x, Armament.APFSDS_DAMAGE.y, power)
			shell.hit.pierce = true
			shell.pierce_entities = true
			# The dart goes through everything in line and slams into the ground with a crater.
			shell.blast_radius = 7.0
			shell.blast_damage = 450.0
		Armament.Round.AIRBURST:
			shell.hit.damage = 70.0
			shell.fuse_distance = muzzle.distance_to(_aimed_spot(charge_lock) if _aimed_spot(charge_lock) != Vector3.INF else charge_lock.hit_center()) if is_instance_valid(charge_lock) else maxf(muzzle.distance_to(aim_point) - 2.0, 6.0)
			shell.airburst_fragments = roundi(lerpf(Armament.AIRBURST_FRAGMENTS.x, Armament.AIRBURST_FRAGMENTS.y, power))
			shell.proximity = lerpf(Armament.AIRBURST_PROXIMITY.x, Armament.AIRBURST_PROXIMITY.y, power)
	var reach := Armament.SHELL_RANGE * (lerpf(Armament.APFSDS_RANGE.x, Armament.APFSDS_RANGE.y, power) if round == Armament.Round.APFSDS else 1.0)
	var end := shell.resolve_now(reach)
	world.fx.beam(muzzle, end, Palette.WHITE, 0.5, 0.1)
	world.fx.beam(muzzle, end, color, 1.4, 0.18)
	world.fx.beam(muzzle, end, color, 2.6, 0.08)
	world.fx.light_flash(end, 20.0, color, 30.0)
	var length := muzzle.distance_to(end)
	for k in int(length / 6.0):
		var at := muzzle.lerp(end, (k + 0.5) * 6.0 / length)
		world.fx.spawn(Fx.Kind.GLOW, at, Vector3(randf_range(-0.4, 0.4), 0.8, randf_range(-0.4, 0.4)), randf_range(0.5, 0.9), 0.5, Palette.MIST, {"end_size": 1.4, "drag": 2.0, "fade": 0.2})


## A player cannon hit template for blasts fired straight from the muzzle.
func _cannon_hit() -> Hit:
	var hit := Hit.make(Hit.Kind.BLAST, 0.0, global_position)
	hit.source = self
	hit.stagger = 1.0
	hit.weapon = "cannon"
	return hit


func _cannon_feedback(muzzle: Vector3, dir: Vector3, power := 0.0) -> void:
	var world := World.current
	_barrel_recoil = 0.7
	if world.rail.mode != Rail.Mode.ARENA:
		local_velocity.y -= lerpf(Armament.RECOIL.x, Armament.RECOIL.y, power) * dir.dot(world.rail.forward())
	world.camera.kick(lerpf(0.05, 0.08, power))
	world.shake(lerpf(0.4, 0.6, power))
	world.screen_flash(Palette.BUTTER, lerpf(0.18, 0.3, power))
	world.hitstop(lerpf(Armament.HITSTOP.x, Armament.HITSTOP.y, power))
	world.fx.light_flash(muzzle, 24.0, Palette.BUTTER, 40.0)
	world.fx.muzzle_flash(muzzle, dir, lerpf(Armament.MUZZLE_SIZE.x, Armament.MUZZLE_SIZE.y, power))
	world.fx.muzzle_flash(muzzle + dir * 1.5, dir, 2.6, Palette.WHITE)
	world.fx.fireball(muzzle + dir * 2.0, 0.6, 2.4, 0.22)
	if power >= 0.5:
		world.fx.shockwave(muzzle, 9.0, Palette.WHITE, 0.2)
	# Muzzle-brake jets blast out sideways.
	var side_dir := dir.cross(Vector3.UP).normalized()
	for side in [-1.0, 1.0]:
		world.fx.muzzle_flash(muzzle - dir * 0.3, (side_dir * side + dir * 0.3).normalized(), 1.1, Palette.PEACH)
	for i in 40:
		var spread := (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.35).normalized()
		world.fx.spawn(Fx.Kind.FLAME, muzzle, spread * randf_range(10, 30), randf_range(0.08, 0.2), randf_range(0.6, 1.2), [Palette.WHITE, Palette.BUTTER, Palette.PEACH][i % 3], {"drag": 8.0})
	for i in 22:
		var side := dir.cross(Vector3.UP).normalized() * (1.0 if i % 2 == 0 else -1.0)
		world.fx.spawn(Fx.Kind.GLOW, muzzle, (side * randf_range(3, 7) + dir * randf_range(2, 8) + Vector3.UP), randf_range(0.8, 1.5), 0.6, [Palette.MIST, Palette.CREAM][i % 2], {"end_size": 2.2, "drag": 2.5, "gravity": -0.5, "fade": 0.15})
	# The blast flattens the ground below the muzzle.
	var ground := muzzle
	ground.y = Course.height_at(muzzle)
	if muzzle.y - ground.y < 4.0:
		world.fx.dust(ground, 8, 2.5, Palette.STRAW)
	Sfx.gun("cannon", randf_range(0.95, 1.05))


## Main-gun impacts. A shell landing on an enemy freezes the frame for a beat and bucks the camera.
func _count_hit(projectile: Projectile, point: Vector3, target: Entity) -> void:
	var world := World.current
	world.shake(0.3, point)
	if target and target.team == Team.ENEMY:
		world.stats.shot_hits += 1
		world.hitstop(0.045)
		world.fx.light_flash(point, 16.0, Palette.WHITE, 22.0)
		world.fx.sparks(point, projectile.splash_direction(), 18, Palette.WHITE, 18.0)


## What the laser burns next: the incoming projectile that arrives soonest, or a drone close enough
## to zap, whichever is sooner.
func _ciws_pick_target() -> Object:
	var world := World.current
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
	return target


func _update_ciws(delta: float) -> void:
	var world := World.current
	_ciws_sound_cooldown = maxf(0.0, _ciws_sound_cooldown - delta)
	if not modules.laser_online():
		ciws_target = null
		ciws_heat = 0.0
		ciws_overheated = false
		return
	if ciws_overheated:
		ciws_heat = maxf(0.0, ciws_heat - CIWS_COOL_RATE * delta)
		if ciws_heat <= 0.3:
			ciws_overheated = false
		ciws_target = null
		return
	var origin := model.rws_lens.global_position
	var target := _ciws_pick_target()
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


## The tail acts on its own so the driver only drives and shoots. Priorities: swat anything about
## to hit the hull, snatch pickups in reach, stab enemies in reach.
func auto_tail() -> void:
	if tail.destroyed:
		return
	var world := World.current
	var mount := tail.mount.global_position
	if is_instance_valid(tail.held):
		# A carried pickup is delivered at once if a dash interrupted the return.
		if tail.state != Tail.State.RETURN:
			collect(tail.held as Pickup)
			tail.held = null
			tail.set_state(Tail.State.IDLE)
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
		if entity is Enemy and (entity as Enemy).stabbable:
			var distance := entity.hit_center().distance_to(mount) - entity.radius
			if distance < best_distance:
				best_distance = distance
				best_enemy = entity
	if best_enemy:
		_grab_target = best_enemy
		tail.set_state(Tail.State.STAB, best_enemy.hit_center(), best_enemy, 260.0)
		Sfx.play("whip", mount)


## Diving drones and bursting crawlers close to the hull.
func _is_imminent(entity: Entity) -> bool:
	var distance := entity.hit_center().distance_to(hit_center())
	if entity is FpvDrone:
		return (entity as FpvDrone).state != FpvDrone.State.APPROACH and distance < 9.0
	if entity is Crawler:
		return (entity as Crawler).state != Crawler.State.RUN and distance < 7.0
	return false


## A full-circle lash that bats away drones and crawlers and flattens small props. On its own it only
## staggers; the driver's dash lash (`start_state` false) hurts and heals.
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
			var direction: Vector3 = (entity.hit_center() - global_position).normalized()
			if start_state:
				_tail_stagger(entity, 0.6)
				if entity is FpvDrone:
					(entity as FpvDrone).bat(direction)
			else:
				var hit := Hit.make(Hit.Kind.TAIL, 30.0, entity.hit_center(), direction)
				hit.stagger = 0.6
				hit.source = self
				hit.weapon = "dash"
				hit.salvage = true
				entity.take_hit(hit)
			world.fx.sparks(entity.hit_center(), direction, 8, Palette.FUNGUS)
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
				var direction := (enemy.hit_center() - global_position).normalized()
				_tail_stagger(enemy, 1.4)
				if enemy is Enemy:
					(enemy as Enemy).interrupt()
				world.fx.sparks(tail.claw_position(), -direction, 14, Palette.FUNGUS, 12.0)
				world.fx.spores(tail.claw_position(), 6, 0.6)
				world.hitstop(0.06)
				world.shake(0.25)
				Sfx.play("stab", tail.claw_position())
			_grab_target = null
			tail.set_state(Tail.State.IDLE)
			tail.start_cooldown()


## The tail on its own never hurts: it only staggers whatever it strikes.
func _tail_stagger(entity: Entity, seconds: float) -> void:
	if entity is Enemy and (entity as Enemy).can_stagger:
		(entity as Enemy).stagger = maxf((entity as Enemy).stagger, seconds)


func _update_pickups() -> void:
	for pickup in World.current.pickups.duplicate():
		if not pickup.collected and pickup != tail.held and pickup.global_position.distance_to(global_position + Vector3.UP) < Pickup.COLLECT_RADIUS:
			collect(pickup)


## Whether a pickup would do anything right now. Rounds and lives are never wasted.
func needs(id: String) -> bool:
	match id:
		"repair":
			return hp < max_hp or TankModules.MAX.keys().any(modules.repairable)
		"era":
			return modules.era != TankModules.ERA
		"tail":
			return tail.destroyed or tail.hp < Tail.MAX_HP
		"rws":
			return not modules.laser_online()
		"coax":
			return coax_tier < Armament.COAX_TIERS.size() - 1
	return true


## What a pickup should turn into so it is never wasted: what the tank needs most, else a special
## round other than the one loaded.
func useful_pickup(id: String) -> String:
	if needs(id):
		return id
	for want in ["repair", "era", "tail", "rws", "coax"]:
		if needs(want):
			return want
	var rounds: Array = Armament.OFFERED.filter(func(r: Armament.Round) -> bool: return r != current_round)
	return Armament.ROUND_IDS[rounds.pick_random()]


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
			var before := hp
			hp = minf(hp + 10.0, max_hp)
			world.stats.repair_healing += hp - before
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
		"rws":
			mount_rws()
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


## Whether a bullet comes down on the roof: it descends at least TOP_ATTACK_ANGLE.
static func is_top_attack(hit: Hit) -> bool:
	return hit.kind == Hit.Kind.BULLET and hit.direction.normalized().y < -sin(TOP_ATTACK_ANGLE)


## Which side of the hull a hit arrives from: "top" for a bullet from above, else "front", "left",
## "right" or "rear".
func facing_of(hit: Hit) -> String:
	if is_top_attack(hit):
		return "top"
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
	# Frontal armor is thick, the rear and the roof are weak.
	match facing_of(hit):
		"front":
			multiplier *= 0.6
		"rear", "top":
			multiplier *= 1.4
	return multiplier


## Shaped charges are decided by ERA: a block on that facing eats it, otherwise it is fatal.
func take_hit(hit: Hit) -> void:
	if dead or invulnerable or _respawn > 0.0:
		return
	if is_small_arms(hit):
		_glance_off(hit)
		return
	if hit.warhead and invuln <= 0.0:
		var world := World.current
		var facing := facing_of(hit)
		if modules.consume_era(facing):
			world.fx.explosion(hit.position, 1.8, [Palette.WHITE, Palette.SKY, Palette.BUTTER])
			world.fx.debris(hit.position, 8, [Fx.Debris.ARMOR], 8.0, 0.3)
			world.shake(0.35)
			world.screen_flash(Palette.SKY, 0.2)
			Sfx.play("blast_small", hit.position, 2.0, 0.8)
			world.style_event("CLOSE_CALL", 40.0)
			invuln = 0.15
			return
		world.stats.damage_taken += hp
		die(hit)
		return
	super(hit)


static func is_small_arms(hit: Hit) -> bool:
	return hit.kind == Hit.Kind.BULLET and hit.caliber < SMALL_ARMS_CALIBER and not (is_top_attack(hit) and hit.caliber >= ROOF_CALIBER)


## Small arms do nothing to the hull (no damage taken, no flash): they whine off the armor, unless
## they land on an exposed roof sensor, which takes the hit.
func _glance_off(hit: Hit) -> void:
	var world := World.current
	world.fx.sparks(hit.position, -hit.direction, 5, Palette.WHITE, 12.0)
	world.fx.ricochet(hit, hit_center())
	Sfx.play("hit_confirm", hit.position, -8.0, randf_range(1.7, 2.1))
	var sensor := struck_sensor(hit)
	if invuln <= 0.0 and not sensor.is_empty():
		damage_module(sensor, hit.damage)


## The mounted roof sensor ("laser" or "fcs") a hit lands on: the one whose direction from the
## hull's center is within SENSOR_STRIKE_ANGLE of the hit's, nearest first; "" for bare armor.
func struck_sensor(hit: Hit) -> String:
	var toward := hit.position - hit_center()
	if toward.length() < 0.01:
		return ""
	var best := ""
	var best_angle := SENSOR_STRIKE_ANGLE
	for name: String in TankModules.KNOCKED_OFF:
		if modules.state(name) == TankModules.State.DESTROYED:
			continue
		var angle := toward.angle_to(model.sensor_position(name) - hit_center())
		if angle < best_angle:
			best = name
			best_angle = angle
	return best


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


## Heavy hits knock out the modules exposed on the facing they come from.
func _damage_modules(hit: Hit, amount: float) -> void:
	var world := World.current
	var facing := facing_of(hit)
	if facing == "rear" and tail.damage(amount * 1.2):
		world.fx.explosion(tail.mount.global_position, 1.5, [Palette.WHITE, Palette.FUNGUS, Palette.BLUSH])
	# A sensor that is already gone cannot be hit again.
	var exposed: Array = TankModules.EXPOSED[facing].filter(func(name: String) -> bool: return modules.state(name) != TankModules.State.DESTROYED or name not in TankModules.KNOCKED_OFF)
	damage_module(exposed[randi() % exposed.size()], amount * 1.3)


## Hurts a module. A roof sensor destroyed is knocked clean off and
## cartwheels away in flames.
func damage_module(name: String, amount: float) -> bool:
	if not modules.damage(name, amount):
		return false
	var world := World.current
	var out := modules.state(name) == TankModules.State.DESTROYED
	if out and name in TankModules.KNOCKED_OFF:
		var piece := model.detach(model.rws if name == "laser" else model.fcs)
		Wreck.launch(piece, piece.global_position, 0.8, false, (piece.global_position - hit_center()).normalized() * 8.0, false)
	world.fx.sparks(hit_center(), Vector3.UP, 14, Palette.BUTTER, 10.0)
	return true


## Losing all armor costs a life instead of removing the tank.
func die(_hit: Hit) -> void:
	_cancel_charge()
	var world := World.current
	world.fx.explosion(global_position + Vector3.UP, 5.0)
	world.fx.debris(global_position + Vector3.UP, 20, [Fx.Debris.ARMOR, Fx.Debris.METAL], 12.0, 0.5)
	world.shake(1.0)
	world.hitstop(0.2)
	world.screen_flash(Palette.WHITE, 0.8)
	Sfx.play("blast", global_position)
	world.stats.lives -= 1
	world.stats.combo = 0
	set_coax_tier(coax_tier - 1)
	_drop_grab()
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


func _finish_respawn() -> void:
	_cancel_charge()
	hp = max_hp
	modules.restore()
	_sync_sensors()
	tail.regrow()
	invuln = RESPAWN_INVULN
	_blink = RESPAWN_INVULN
	course_u = 0.0
	course_offset = 4.0
	local_velocity = Vector2.ZERO
	model.visible = true
	tail.visible = true
	World.current.fx.shockwave(global_position, 6.0, Palette.MINT)
