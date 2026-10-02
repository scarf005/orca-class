class_name QuadMech
extends Enemy
## Four-legged heavy mech on wheeled feet. It rolls ahead of the tank with its legs held in one stance and a turret on its back:
## "flak" spins up four 20 mm barrels and hoses the tank; "mortar" lobs shells onto marked circles.
## Each leg can be shot off; with two gone it collapses.

const KEEP_AHEAD := 55.0
const PACE_TIME := 16.0
const LEG_HP := 8.0
const BARREL_SLEW := 2.5 ## Radians per second the gun (or mortar tube) turns onto its aim.
const GUN_SPREAD := 0.03 ## Radians of scatter on every flak round.
const MORTAR_CORRECTION := 8.0 ## Degrees a shell may leave off the tube: it then lands where it actually flies.
const MORTAR_GRAVITY := 20.0
const WHEEL_RADIUS := 0.4
const STANCE_SPLAY := 0.12 ## Radians the shins splay outward.
const STOMP_RANGE := 8.0 ## A tank this close is stomped.
const STOMP_REACH := 6.0 ## The stomp shakes this far; the ring shows it.
const STOMP_WIND := 0.6
const STOMP_COOLDOWN := 3.0
const STOMP_DAMAGE := 25.0
const FRONT_ARMOR := 0.25 ## Share of coax damage that gets through the front plate.

var weapon := "flak" ## "flak" or "mortar".
var turret_hp := 10.0
var disarmed := false
var _lane := 0.0
var _lane_timer := 0.0
var _attack_timer := 2.0
var _telegraph := 0.0
var _burst := 0
var _burst_timer := 0.0
var _stomp := 0.0 ## Seconds of the stomp's wind-up left.
var _stomp_cooldown := 0.0
var _body := Node3D.new()
var _turret := Node3D.new()
var _gun := Node3D.new() ## Pivot the flak barrels or the mortar tube turn on; its -Z is the bore.
var _barrels := Node3D.new() ## The spinning flak cluster inside `_gun`.
var _muzzle := Node3D.new()
var _legs: Array[Dictionary] = [] ## {hip, knee, wheel, corner, hp, lost}
var _hard := false


func _init() -> void:
	super()
	wreck_on_death = true
	max_hp = 2400.0
	hp = 2400.0
	radius = 2.6
	center_height = 2.6
	armor = 0.0
	stabbable = true
	score = 900
	debris = [Fx.Debris.ARMOR, Fx.Debris.METAL]
	weakness = {Hit.Kind.THROWN: 1.3, Hit.Kind.FRAGMENT: 0.3}
	mark_offsets = [-3.0, 3.0] # Thin lines under the wheels on its feet.
	mark_width = 0.3


func build() -> void:
	pop_parts = [_turret]
	_hard = Game.difficulty == Game.Difficulty.HARD
	_body.position = Vector3(0, 2.6, 0)
	model.add_child(_body)
	var b := LowPoly.new()
	b.box(Transform3D(), Vector3(2.6, 0.9, 3.6), Palette.SLATE, Palette.ASH)
	b.box(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.1, -1.95)), Vector3(2.2, 0.6, 0.6), Palette.DUSK)
	b.box(Transform3D(Basis(), Vector3(0, -0.2, 2.0)), Vector3(1.8, 0.7, 0.5), Palette.DUSK)
	for x in [-1.31, 1.31]:
		b.box(Transform3D(Basis(), Vector3(x, 0.1, 0)), Vector3(0.02, 0.15, 3.0), Palette.CORAL)
	b.glow = true
	for x in [-0.5, 0.0, 0.5]:
		b.box(Transform3D(Basis(), Vector3(x, 0.2, -2.24)), Vector3(0.18, 0.1, 0.02), Palette.HOT)
	_add_mesh(_body, b.mesh())
	_turret.position = Vector3(0, 0.45, 0.2)
	_body.add_child(_turret)
	var t := LowPoly.new()
	t.prism(Transform3D(), 0.9, 0.6, 8, Palette.DUSK, 0.8, Palette.SLATE)
	_add_mesh(_turret, t.mesh())
	_turret.add_child(_gun)
	_gun.add_child(_barrels)
	if weapon == "flak":
		_gun.position = Vector3(0, 0.6, -0.5)
		var r := LowPoly.new()
		r.box(Transform3D(Basis(), Vector3(0, 0, 0.3)), Vector3(0.9, 0.6, 0.8), Palette.MOSS)
		for x in [-0.25, 0.25]:
			for y in [-0.15, 0.15]:
				r.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(x, y, 0)), 0.07, 1.8, 6, Palette.INK)
		_add_mesh(_barrels, r.mesh())
		_muzzle.position = Vector3(0, 0, -1.9)
		_barrels.add_child(_muzzle)
	else:
		_gun.position = Vector3(0, 0.5, 0)
		var m := LowPoly.new()
		m.tube(Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3.ZERO), 0.3, 1.6, 8, Palette.MOSS)
		_add_mesh(_gun, m.mesh())
		_muzzle.position = Vector3(0, 0, -1.6)
		_gun.add_child(_muzzle)
	# Four legs: hip up and out, a long shin down to a splayed foot.
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var hip := Node3D.new()
		hip.position = Vector3(corner.x * 1.2, -0.2, corner.y * 1.4)
		_body.add_child(hip)
		var thigh := LowPoly.new()
		thigh.blob(Transform3D(), 0.35, Palette.INK)
		thigh.box(Transform3D(Basis(Vector3.BACK, corner.x * 0.9), Vector3(corner.x * 0.55, 0.45, 0)), Vector3(1.4, 0.35, 0.4), Palette.SLATE)
		_add_mesh(hip, thigh.mesh())
		var knee := Node3D.new()
		knee.position = Vector3(corner.x * 1.1, 0.9, 0)
		hip.add_child(knee)
		var shin := LowPoly.new()
		shin.blob(Transform3D(), 0.28, Palette.CORAL)
		shin.box(Transform3D(Basis(Vector3.BACK, -corner.x * 0.25), Vector3(corner.x * 0.35, -1.55, 0)), Vector3(0.32, 3.2, 0.36), Palette.DUSK)
		shin.prism(Transform3D(Basis(), Vector3(corner.x * 0.75, -3.25, 0)), 0.45, 0.2, 6, Palette.INK, 0.3)
		_add_mesh(knee, shin.mesh())
		var wheel := Node3D.new()
		wheel.position = Vector3(corner.x * 0.75, -3.05, 0)
		knee.add_child(wheel)
		var w := LowPoly.new()
		w.prism(Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO), WHEEL_RADIUS, 0.35, 8, Palette.STONE, -1.0, Palette.BUTTER)
		_add_mesh(wheel, w.mesh())
		_legs.append({"hip": hip, "knee": knee, "wheel": wheel, "corner": corner, "hp": LEG_HP, "lost": false})
	_lane = Course.to_course(global_position).y
	_attack_timer = randf_range(1.5, 2.5)


func _add_mesh(parent: Node3D, mesh: Mesh) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	parent.add_child(instance)


func legs_lost() -> int:
	return _legs.filter(func(leg: Dictionary) -> bool: return leg.lost).size()


func collapsed() -> bool:
	return legs_lost() >= 2


func behave(delta: float) -> void:
	var world := World.current
	var tank := player()
	if tank == null:
		return
	var here := Course.to_course(global_position)
	_lane_timer -= delta
	if _lane_timer <= 0.0:
		_lane_timer = randf_range(3.0, 5.0)
		_lane = randf_range(-9.0, 9.0)
	var target_d := here.x
	if age < PACE_TIME and world.rail.mode != Rail.Mode.ARENA:
		target_d = world.rail.d + tank.course_offset + KEEP_AHEAD
	var pace := 1.0 - legs_lost() * 0.35
	var move := Vector2.ZERO
	if not collapsed() and not is_staggered() and _stomp <= 0.0:
		move = Vector2(clampf(target_d - here.x, -16.0, 16.0), clampf(_lane - here.y, -3.5, 3.5)) * pace
	var next := here + move * delta
	global_position = Course.ground_at(next.x, next.y)
	_animate(delta)
	_stomp_cooldown = maxf(0.0, _stomp_cooldown - delta)
	if collapsed() or is_staggered():
		_stomp = 0.0
	elif _stomp > 0.0:
		_stomp -= delta
		if _stomp <= 0.0:
			_land_stomp(tank)
		return
	elif _stomp_cooldown <= 0.0 and _telegraph <= 0.0 and _burst == 0 and _flat_distance(tank) < STOMP_RANGE:
		_stomp = STOMP_WIND
		world.fx.marker(global_position, STOMP_REACH, STOMP_WIND, Palette.HOT)
		Sfx.play("warn", global_position, 0.0, 0.6)
		return
	if disarmed or collapsed() or is_staggered():
		_telegraph = 0.0
		return
	var local := model.global_transform.affine_inverse() * tank.hit_center()
	_turret.rotation.y = lerp_angle(_turret.rotation.y, atan2(-local.x, -local.z), 2.5 * delta)
	if weapon == "flak":
		aim_barrel(_gun, _flak_aim(tank), BARREL_SLEW, delta)
	else:
		slew_barrel(_gun, _lob(_muzzle.global_position, _mortar_target(tank, 0), 1.7), BARREL_SLEW, delta)
	if _burst > 0:
		_burst_timer -= delta
		_barrels.rotation.z += delta * 30.0
		if _burst_timer <= 0.0:
			_burst -= 1
			_burst_timer = 0.07
			var shot := fire_along("orb", _muzzle, 90.0, 4.0, Palette.HOT, _flak_aim(tank) - _muzzle.global_position, 3.0, GUN_SPREAD, Muzzle.AUTO)
			shot.hit.caliber = 20
			Sfx.play("enemy_gun", _muzzle.global_position, -2.0, 0.85)
		return
	if _telegraph > 0.0:
		_telegraph -= delta
		_barrels.rotation.z += delta * (20.0 - _telegraph * 20.0)
		if fmod(_telegraph, 0.14) < 0.07:
			flash()
		if _telegraph <= 0.0:
			_attack(tank)
		return
	_attack_timer -= delta
	var distance := global_position.distance_to(tank.global_position)
	if _attack_timer <= 0.0 and distance < 110.0 and distance > 12.0:
		_telegraph = 0.8
		_attack_timer = (3.0 if weapon == "flak" else 3.6) * (0.75 if _hard else 1.0)
		Sfx.play("warn", global_position, 0.0, 0.7)


func _attack(tank: Tank) -> void:
	if weapon == "flak":
		_burst = 16 if _hard else 12
		_burst_timer = 0.0
		return
	var world := World.current
	var from := _muzzle.global_position
	muzzle_blast(from, -_muzzle.global_basis.z, Muzzle.HEAVY, "mortar")
	for i in (4 if _hard else 3):
		var flight := 1.7 + i * 0.12
		var target := _mortar_target(tank, i)
		var lob := _lob(from, target, flight)
		# The shell leaves the tube along its bore (the tube may be a few degrees off this arc) and
		# lands where that flight actually ends.
		var velocity_out := bore_direction(_muzzle, lob, MORTAR_CORRECTION) * lob.length()
		var rise := velocity_out.y * velocity_out.y + 2.0 * MORTAR_GRAVITY * (from.y - target.y)
		var air := (velocity_out.y + sqrt(maxf(rise, 0.0))) / MORTAR_GRAVITY
		target = Vector3(from.x + velocity_out.x * air, target.y, from.z + velocity_out.z * air)
		var shell := world.spawn_projectile(Team.ENEMY, from, velocity_out, "mortar", Palette.HOT)
		shell.gravity = MORTAR_GRAVITY
		shell.hit = Hit.make(Hit.Kind.SHELL, 0.0, from)
		shell.hit.source = self
		shell.blast_radius = 3.4
		shell.blast_damage = 24.0
		shell.interceptable = true
		shell.intercept_hp = 1.0
		shell.life = air + 1.0
		world.fx.marker(target, 3.4, air, Palette.HOT)
	Sfx.play("launch", from, 2.0, 0.6)


func _flat_distance(tank: Tank) -> float:
	return Vector2(tank.global_position.x - global_position.x, tank.global_position.z - global_position.z).length()


## The stomp lands: a ram hit on the tank if it is still inside the ring.
func _land_stomp(tank: Tank) -> void:
	var world := World.current
	_stomp_cooldown = STOMP_COOLDOWN
	world.shake(0.5, global_position)
	world.fx.shockwave(global_position, STOMP_REACH * 2.0, Palette.HOT)
	world.fx.dust(global_position, 10, 3.0, Palette.OCHRE)
	Sfx.play("blast_small", global_position, 2.0, 0.7)
	if _flat_distance(tank) > STOMP_REACH:
		return
	var hit := Hit.make(Hit.Kind.RAM, STOMP_DAMAGE, tank.hit_center(), (tank.global_position - global_position).normalized())
	hit.source = self
	tank.take_hit(hit)


## Where flak is aimed: the tank, a little ahead of where it is going.
func _flak_aim(tank: Tank) -> Vector3:
	return tank.hit_center() + tank.velocity * 0.4


## Where mortar shell `index` of a volley is meant to come down: the tank's path, the later ones scattered.
func _mortar_target(tank: Tank, index: int) -> Vector3:
	var target := tank.global_position + tank.velocity * (1.7 + index * 0.12) + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5)) * float(index > 0)
	target.y = Course.height_at(target)
	return target


## The launch velocity that lands a shell on `target` after `flight` seconds.
func _lob(from: Vector3, target: Vector3, flight: float) -> Vector3:
	var velocity_out := (target - from) / flight
	velocity_out.y += 0.5 * MORTAR_GRAVITY * flight
	return velocity_out


## Settles into its stance without running any AI (debug room).
func pose_idle() -> void:
	for _i in 10:
		_animate(0.05)


## Rolling stance: the legs stay planted in one pose with a small suspension bob over the ground and
## a lean into acceleration, and the wheels spin at the ground speed. Lost legs hang limp; collapse
## drops the body.
func _animate(delta: float) -> void:
	var lean := sway(delta)
	var bob := clampf(lean.y * 0.02, -1.0, 1.0)
	var spin := rolled() / WHEEL_RADIUS
	var tilt := Vector2.ZERO
	for leg in _legs:
		var corner: Vector2 = leg.corner
		if leg.lost:
			tilt += corner
			(leg.knee as Node3D).rotation.z = lerpf((leg.knee as Node3D).rotation.z, corner.x * 1.2, 4.0 * delta)
			continue
		(leg.hip as Node3D).rotation.x = 0.0
		(leg.knee as Node3D).rotation.z = (STANCE_SPLAY + bob * 0.04) * corner.x
		(leg.wheel as Node3D).rotation.x -= spin
	var sag := 1.8 if collapsed() else 0.0
	_body.position.y = lerpf(_body.position.y, 2.6 - sag - bob * 0.08, 5.0 * delta)
	_body.rotation.x = lerpf(_body.rotation.x, -tilt.y * 0.12 + clampf(lean.z * 0.005, -0.08, 0.08) + (0.3 if _stomp > 0.0 else 0.0), 3.0 * delta)
	_body.rotation.z = lerpf(_body.rotation.z, tilt.x * 0.12 - clampf(lean.x * 0.005, -0.08, 0.08), 3.0 * delta)


func damage_multiplier(hit: Hit) -> float:
	return super(hit) * frontal_armor(hit, FRONT_ARMOR)


func telegraphing() -> bool:
	return _telegraph > 0.0 or _stomp > 0.0


func on_damaged(hit: Hit, amount: float) -> void:
	super(hit, amount)
	amount /= frontal_armor(hit, FRONT_ARMOR) # The front plate guards the hull, not the legs or the turret.
	var world := World.current
	var local := _body.global_transform.affine_inverse() * hit.position
	if local.y < -0.4:
		# Legs: the nearest corner takes it.
		var best: Dictionary = {}
		var best_distance := INF
		for leg in _legs:
			if leg.lost:
				continue
			var corner: Vector2 = leg.corner
			var distance := Vector2(local.x, local.z).distance_to(Vector2(corner.x * 1.8, corner.y * 1.4))
			if distance < best_distance:
				best_distance = distance
				best = leg
		if not best.is_empty():
			best.hp -= amount
			if best.hp <= 0.0:
				best.lost = true
				world.fx.explosion((best.knee as Node3D).global_position, 1.5)
				world.fx.debris((best.knee as Node3D).global_position, 8, [Fx.Debris.METAL], 8.0, 0.35)
				world.award(150, global_position, false)
				if collapsed():
					world.shake(0.4, global_position)
					world.fx.dust(global_position, 12, 3.0, Palette.OCHRE)
	elif not disarmed and local.y > 0.4:
		turret_hp -= amount
		if turret_hp <= 0.0:
			disarmed = true
			_gun.rotation.x = 0.5
			world.fx.explosion(_turret.global_position + Vector3.UP * 0.5, 1.6)
			world.fx.burn(_turret.global_position + Vector3.UP * 0.5, 8.0, 0.7)
			world.award(150, global_position, false)


func interrupt() -> void:
	super()
	_telegraph = 0.0
	_stomp = 0.0
	_burst = 0
