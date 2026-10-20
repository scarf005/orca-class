class_name Fortress
extends Enemy
## Stage 4 boss: a tracked mobile fortress the size of a city block that crashes out of the jungle onto the clearing,
## felling trees and flattening ruins on its way in. Its hull is armour that only sparks; the fight is against its
## modules. Two tracks drive it (a shot-out track slumps that side and makes it circle, both leave it stranded), two
## sponson flame guns burn a wall of fire out to 48 m, the main turret lobs incendiary shells that CIWS can swat, and
## two rear fuel tanks burst into a rain of fire. It also charges: a lane of markers shows where it will go before it
## floors the throttle. Keep clear of the front, circle behind the slow turn and shoot the modules out one by one.

enum State { ENTER, FIGHT, DYING }
enum Attack { NONE, FLAME, SALVO, CRUSH }

const MODULES := ["track_l", "track_r", "flame_l", "flame_r", "turret", "fuel_l", "fuel_r"]
const LABELS := {"track_l": "FORTRESS_TRACK_L", "track_r": "FORTRESS_TRACK_R", "flame_l": "FORTRESS_FLAME_L", "flame_r": "FORTRESS_FLAME_R", "turret": "FORTRESS_TURRET", "fuel_l": "FORTRESS_FUEL_L", "fuel_r": "FORTRESS_FUEL_R"}
const MODULE_HP := {"track_l": 800.0, "track_r": 800.0, "flame_l": 550.0, "flame_r": 550.0, "turret": 1000.0, "fuel_l": 400.0, "fuel_r": 400.0} ## About 60 s of every full charge landing.
const MODULE_RADIUS := {"track_l": 24.0, "track_r": 24.0, "flame_l": 8.5, "flame_r": 8.5, "turret": 14.0, "fuel_l": 8.5, "fuel_r": 8.5}
const ROUND_DAMAGE := 40.0 ## Like the other bosses, main-gun damage counts in rounds.
const SCALE := 1.75 ## The model is built this much bigger than its 64 m design sheet; the measures below are the sheet's times this.
const HULL_BOX := AABB(Vector3(-19.5, 0.0, -33.0) * SCALE, Vector3(39.0, 32.0, 64.5) * SCALE) ## The slab and decks in model space.
const TRACK_AT := 15.0 * SCALE ## Lateral offset of each track's middle.
const TURRET_AT := Vector3(0.0, 23.5, -9.0) * SCALE
const BARREL_AT := Vector3(0.0, 3.2, -7.0) * SCALE ## On the turret ring.
const MUZZLE_AT := Vector3(0.0, 0.0, -18.6) * SCALE
const FLAME_AT := Vector3(16.0, 16.5, -21.0) * SCALE ## The hull-fixed sponson, mirrored for the left; the gun pivots 2.8 m above it.
const GUN_MUZZLE := Vector3(0.0, 0.0, -9.2) * SCALE
const FUEL_AT := Vector3(7.5, 19.5, 21.0) * SCALE
const WHEEL_Z := [-33.25, -23.8, -14.35, -4.9, 4.55, 14.0, 23.45, 32.9] ## Eight road wheels in two bogies per side.
const WHEEL_RADIUS := 2.2 * SCALE
const ENTER_SPEED := 18.0
const DRIVE_SPEED := 12.0
const CHARGE_SPEED := 26.0
const TURN := 0.22 ## Radians per second the hull swings onto the tank.
const LIMP_TURN := 0.18 ## Radians per second it veers toward a shot-out track.
const RIM_KEEP := 30.0 ## Closest its middle comes to the clearing's rim while it fights.
const FLAME_REACH := 80.0
const FLAME_ARC := deg_to_rad(100.0) ## How far either side of the bow a flame gun can swing.
const FLAME_BURN := 2.0 ## Per tick: the wall of fire is too wide to dodge at once, so it burns lighter than a crew's jet.
const SHELL_FLIGHT := 1.6
const WIND := 1.2
const CRUSH_TIME := 2.4
const HULL_FRONT := 33.0 * SCALE
const HULL_REAR := 31.5 * SCALE
const HULL_HALF := 19.5 * SCALE
const HULL_DAMAGE := 20.0
const HULL_SHOVE := 14.0 ## Metres per second the hull throws the tank off its flank at.
const CRUSH_KINDS: Array[String] = ["jungle_tree", "palm", "fern", "jungle_building", "car", "bus_wreck", "barricade", "city_rubble", "streetlamp", "traffic_light", "road_sign", "truck"]
const CRUSH_REACH := 30.0
const SALVO_SHELLS := [4, 5, 6]
const WINDOW := [2.6, 2.0, 1.5] ## Seconds between attacks by phase.

static var _hull_shape: TriangleMesh ## The hull mesh, for rounds that cross the box around it.

var parts: Dictionary[String, float] = {}
var phase := 0 ## 0..2: the hull's health bands, each faster than the last.
var _state := State.ENTER
var _attack := Attack.NONE
var _attack_time := 0.0
var _next_attack := 2.0
var _pattern := 0
var _yaw := 0.0
var _speed := 0.0
var _shots := 0
var _shot_timer := 0.0
var _lane := Vector3.ZERO
var _dying := 0.0
var _bump := 0.0
var _crush_from := Vector3.ZERO
var _crush_timer := 0.0
var _smoke := 0.0
var _nodes: Dictionary[String, Node3D] = {}
var _guns: Dictionary[String, Node3D] = {}
var _muzzles: Dictionary[String, Node3D] = {}
var _wheels: Dictionary[String, Array] = {}
var _jets: Array[FlameJet] = []
var _turret := Node3D.new()
var _barrel := Node3D.new()
var _muzzle := Node3D.new()
var _sag := {"track_l": 0.0, "track_r": 0.0}


func _init() -> void:
	super()
	boss = true
	heavy = true
	can_stagger = false
	armor = 30.0
	for name: String in MODULES:
		parts[name] = MODULE_HP[name]
	max_hp = MODULE_HP.values().reduce(func(a: float, b: float) -> float: return a + b)
	hp = max_hp
	radius = 60.0
	center_height = 18.0
	score = 30000
	despawn_behind = 0.0
	invulnerable = true # It is out of reach until it has crashed in.
	set_meta("title", "BOSS_FORTRESS")
	set_meta("phase_marks", [0.66, 0.33])
	set_meta("frame", 0.3)
	set_meta("giant", 34.0 * SCALE) # How far above its origin the camera keeps in frame.
	set_meta("zoom", 2.2) # The arena camera backs off this many times: lower, the modules hide behind the hull.


func _ready() -> void:
	super()
	var arena := Course.to_world(Stage4.CLEARING_D, 0.0)
	global_position = Course.stage.boss_position()
	var toward := arena - global_position
	_yaw = atan2(-toward.x, -toward.z)
	_speed = ENTER_SPEED
	_crush_from = global_position
	_pose(1.0)


func build() -> void:
	_add_mesh(model, "hull")
	for side in [-1.0, 1.0]:
		var tag := "_l" if side < 0.0 else "_r"
		var track := Node3D.new()
		model.add_child(track)
		_nodes["track" + tag] = track
		_add_mesh(track, "track" + tag)
		_wheels["track" + tag] = []
		for z: float in WHEEL_Z:
			var wheel := Node3D.new()
			wheel.position = Vector3(side * 19.3, 3.6, 0.0) * SCALE + Vector3(0.0, 0.0, z)
			track.add_child(wheel)
			_add_mesh(wheel, "wheel")
			_wheels["track" + tag].append(wheel)
		var base := Node3D.new()
		base.position = FLAME_AT * Vector3(side, 1.0, 1.0)
		model.add_child(base)
		_add_mesh(base, "flame_base")
		var gun := Node3D.new()
		gun.position = Vector3(0.0, 2.8, 0.0) * SCALE
		base.add_child(gun)
		_add_mesh(gun, "flame_gun")
		var muzzle := Node3D.new()
		muzzle.position = GUN_MUZZLE
		gun.add_child(muzzle)
		_nodes["flame" + tag] = gun
		_guns["flame" + tag] = gun
		_muzzles["flame" + tag] = muzzle
		var fuel := Node3D.new()
		fuel.position = FUEL_AT * Vector3(side, 1.0, 1.0)
		model.add_child(fuel)
		_add_mesh(fuel, "fuel")
		_nodes["fuel" + tag] = fuel
	_turret.position = TURRET_AT
	model.add_child(_turret)
	_add_mesh(_turret, "turret")
	_barrel.position = BARREL_AT
	_turret.add_child(_barrel)
	_add_mesh(_barrel, "barrel")
	_muzzle.position = MUZZLE_AT
	_barrel.add_child(_muzzle)
	_nodes.turret = _turret


func _add_mesh(parent: Node3D, part: String) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = ActorMeshes.mesh("fortress", part)
	parent.add_child(instance)


## The middle of module `name` in the world.
func module_at(name: String) -> Vector3:
	match name:
		"track_l", "track_r":
			return model.to_global(Vector3(TRACK_AT * (-1.0 if name == "track_l" else 1.0), 5.5 * SCALE, 0.0))
		"turret":
			return _turret.global_position + model.global_basis.y * 3.0 * SCALE
	return _nodes[name].global_position


func aim_parts() -> Dictionary:
	var result := {}
	if _state != State.FIGHT:
		return result
	for name: String in MODULES:
		if parts[name] > 0.0:
			result[name] = [module_at(name), MODULE_RADIUS[name], tr(LABELS[name])]
	return result


func module_states() -> Array:
	return MODULES.map(func(name: String) -> Array: return [tr(LABELS[name]), maxf(parts[name], 0.0) / MODULE_HP[name]])


## A module's sphere where a round reaches it, else the hull box around the whole fortress, which only sparks.
func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	if _state == State.DYING:
		return -1.0
	var best := -1.0
	for spec: Array in aim_parts().values():
		var distance := Entity.segment_sphere(from, to, spec[0], spec[1] + extra_radius)
		if distance >= 0.0 and (best < 0.0 or distance < best):
			best = distance
	if best >= 0.0:
		return best
	var to_model := model.global_transform.affine_inverse()
	var local_from := to_model * from
	var local_to := to_model * to
	var box := HULL_BOX.grow(extra_radius)
	if box.intersects_segment(local_from, local_to) == null and not box.has_point(local_from):
		return -1.0
	# Inside its bounds, only the hull's own surface stops a round: the box would bury the modules on its decks.
	if _hull_shape == null:
		_hull_shape = ActorMeshes.mesh("fortress", "hull").generate_triangle_mesh()
	var surface := _hull_shape.intersect_segment(local_from, local_to)
	return from.distance_to(model.global_transform * (surface.position as Vector3)) if not surface.is_empty() else -1.0


func take_hit(hit: Hit) -> void:
	if dead or invulnerable or _state != State.FIGHT or hit.damage <= 0.0 or hit.kind == Hit.Kind.FIRE:
		return
	var amount := hit.damage * damage_multiplier(hit)
	if amount <= 0.0:
		return
	if (hit.kind == Hit.Kind.SHELL and (hit.caliber >= 100 or hit.weapon == "cannon")) or (hit.kind == Hit.Kind.BLAST and hit.weapon == "cannon"):
		amount *= ROUND_DAMAGE / Armament.SHELL_DAMAGE
	var struck := ""
	var nearest := INF
	for name: String in MODULES:
		if parts[name] <= 0.0:
			continue
		var gap: float = hit.position.distance_to(module_at(name)) - MODULE_RADIUS[name]
		if gap <= 1.5 and gap < nearest:
			struck = name
			nearest = gap
	if struck.is_empty():
		World.current.fx.sparks(hit.position, -hit.direction, 6)
		Sfx.play("impact", hit.position, -6.0)
		return
	parts[struck] = maxf(0.0, parts[struck] - amount)
	hp = parts.values().reduce(func(a: float, b: float) -> float: return a + b)
	impact_feedback(hit, amount, hp <= 0.0)
	if hit.power >= 1.0:
		World.current.hitstop(0.05)
	if parts[struck] <= 0.0:
		_break(struck, hit.direction)
	phase = int(hp <= max_hp * 0.66) + int(hp <= max_hp * 0.33)
	if hp <= 0.0:
		_state = State.DYING
		_dying = 3.2
		killing_hit = hit.copy()
		_end_attack()
		World.current.hitstop(0.2)


## A module blows off its mount and tumbles away as a whole; a track slumps its side of the hull, a fuel tank bursts and rains fire.
func _break(name: String, direction: Vector3) -> void:
	var world := World.current
	var node := _nodes[name]
	var at := module_at(name)
	world.fx.explosion(at, 2.5) # The camera hangs close to a hull this big, so a bigger ball would hide it.
	world.award(1000, at, false)
	Sfx.play("blast", at)
	world.shake(0.5, at)
	if name.begins_with("fuel"):
		var ground := Vector3(at.x, Course.height_at(at), at.z)
		FireZone.ignite(ground, "fuel", true)
		FireZone.ignite(ground + model.global_basis.z * 6.0, "fuel", true)
		world.fx.burn(at, 8.0, 3.0)
	Wreck.launch(node, node.global_position, 14.0 if name.begins_with("track") else 6.0, true, direction * 6.0 + Vector3.UP * 4.0, name != "turret" and not name.begins_with("track"))
	if name == "flame_l" or name == "flame_r":
		_end_attack() # A jet that lost its gun goes out.


func telegraphing() -> bool:
	return _attack != Attack.NONE and _attack_time < WIND * Game.telegraph_scale()


func interrupt() -> void:
	_end_attack()


func _tracks() -> int:
	return int(parts.track_l > 0.0) + int(parts.track_r > 0.0)


func behave(delta: float) -> void:
	var world := World.current
	var tank := player()
	if tank == null:
		return
	_wheel_spin(delta)
	_exhaust(delta)
	match _state:
		State.ENTER:
			_enter(delta)
		State.FIGHT:
			_fight(delta, tank)
		State.DYING:
			_die(delta)
	if _state != State.DYING:
		_collide(tank, delta)
	_pose(delta)
	_crush_timer -= delta
	if _crush_timer <= 0.0 and _speed > 1.0:
		_crush_timer = 0.12
		var crushed := (world.director.scenery as Scenery).crush_cover(_crush_from, global_position, CRUSH_REACH, CRUSH_KINDS)
		_crush_from = global_position
		if crushed > 0:
			world.shake(0.3, global_position)
			Sfx.play("wood", global_position, 2.0, 0.7)


## Drives in from the jungle along the line to the clearing's centre, untouchable until it has crashed through.
func _enter(delta: float) -> void:
	_drive(ENTER_SPEED, delta)
	if _rim_gap() > 62.0:
		_state = State.FIGHT
		invulnerable = false
		World.current.shake(0.6, global_position)
		Sfx.play("roar", global_position, 6.0, 0.5)


## How far inside the clearing's rim the hull's middle is.
func _rim_gap() -> float:
	var center := Course.to_world(Stage4.CLEARING_D, 0.0)
	return Stage4.CLEARING_RADIUS - Vector2(global_position.x - center.x, global_position.z - center.z).length()


func _fight(delta: float, tank: Tank) -> void:
	_aim_turret(delta, tank)
	var factor := 0.0 if _tracks() == 0 else (1.0 if _tracks() == 2 else 0.55)
	var center := Course.to_world(Stage4.CLEARING_D, 0.0)
	var goal := tank.global_position - global_position
	if _rim_gap() < 70.0 and (global_position - center).dot(Vector3(-sin(_yaw), 0.0, -cos(_yaw))) > 0.0:
		goal = center - global_position # Swings back from the rim.
	var turn := TURN * (1.0 + 0.4 * phase) * factor
	if _attack in [Attack.CRUSH, Attack.FLAME] and _attack_time >= WIND * Game.telegraph_scale():
		turn = 0.0 # Committed: the charge and the lit jets keep the line the telegraph showed.
	elif _tracks() == 1:
		_yaw += LIMP_TURN * (1.0 if parts.track_l > 0.0 else -1.0) * delta # The dead side drags: it veers toward it.
	_yaw = rotate_toward(_yaw, atan2(-goal.x, -goal.z), turn * delta)
	var speed := DRIVE_SPEED * (1.0 + 0.2 * phase) * factor
	match _attack:
		Attack.CRUSH:
			speed = 0.0 if telegraphing() else CHARGE_SPEED
		Attack.FLAME:
			speed *= 0.5
	_drive(speed, delta)
	var center_gap := _rim_gap() - RIM_KEEP
	if center_gap < 0.0: # Limping, it veers harder than it can steer: the clearing's edge holds it in.
		var out := Vector3(global_position.x - center.x, 0.0, global_position.z - center.z).normalized()
		global_position += out * center_gap
	_update_attack(delta, tank)


func _drive(target: float, delta: float) -> void:
	_speed = move_toward(_speed, target, (12.0 if target > DRIVE_SPEED * 2.0 else 5.0) * delta)
	global_position += Vector3(-sin(_yaw), 0.0, -cos(_yaw)) * _speed * delta


func _aim_turret(delta: float, tank: Tank) -> void:
	if parts.turret <= 0.0:
		return
	var local := model.global_transform.affine_inverse() * tank.hit_center()
	_turret.rotation.y = rotate_toward(_turret.rotation.y, atan2(-local.x, -local.z), 0.7 * delta)
	var lob := tank.hit_center() + Vector3.UP * 25.0 if _attack == Attack.SALVO else tank.hit_center()
	aim_barrel(_barrel, lob, 1.2, delta)


## Settles the hull onto the ground under it: pitch and roll from four samples, slumped toward a shot-out track.
func _pose(delta: float) -> void:
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := forward.cross(Vector3.UP)
	var front := Course.height_at(global_position + forward * 26.0 * SCALE)
	var back := Course.height_at(global_position - forward * 26.0 * SCALE)
	var left := Course.height_at(global_position - right * 16.0 * SCALE)
	var right_h := Course.height_at(global_position + right * 16.0 * SCALE)
	for side: String in _sag:
		_sag[side] = move_toward(_sag[side], 0.0 if parts[side] > 0.0 else 1.0, delta)
	var roll: float = atan2(right_h - left, 32.0 * SCALE) + (_sag.track_l - _sag.track_r) * 0.07
	var target := Basis.from_euler(Vector3(atan2(front - back, 52.0 * SCALE), _yaw, -roll), EULER_ORDER_YXZ)
	global_position.y = (front + back + left + right_h) * 0.25
	model.global_basis = model.global_basis.orthonormalized().slerp(target, minf(delta * 6.0, 1.0)) if delta < 0.5 else target


func _wheel_spin(delta: float) -> void:
	for side: String in _wheels:
		if parts[side] > 0.0:
			for wheel: Node3D in _wheels[side]:
				wheel.rotation.x -= _speed / WHEEL_RADIUS * delta


## Stack smoke and the dust the tracks throw.
func _exhaust(delta: float) -> void:
	_smoke -= delta
	if _smoke > 0.0 or _state == State.DYING:
		return
	_smoke = 0.5
	var fx := World.current.fx
	for side in [-1.0, 1.0]:
		fx.smoke_puff(model.to_global(Vector3(side * 12.5, 21.0, 8.0) * SCALE), 2.5)
	if _speed > 3.0:
		for side in [-1.0, 1.0]:
			fx.dust(model.to_global(Vector3(side * TRACK_AT, 1.0, 30.0 * SCALE)), 3, 9.0, Palette.STRAW)


## The hull is solid: a tank on it is thrown off the nearest flank and hurt.
func _collide(tank: Tank, delta: float) -> void:
	_bump = maxf(0.0, _bump - delta)
	var yaw := Basis(Vector3.UP, _yaw)
	var local := yaw.inverse() * (tank.global_position - global_position)
	var inner := Vector3(HULL_HALF + tank.radius, 0.0, 0.0)
	if tank.dead or absf(local.x) >= inner.x or local.z <= -HULL_FRONT - tank.radius or local.z >= HULL_REAR + tank.radius:
		return
	var gaps := [Vector2(inner.x - absf(local.x), signf(local.x)), Vector2(local.z + HULL_FRONT + tank.radius, -1.0), Vector2(HULL_REAR + tank.radius - local.z, 1.0)]
	var nearest := 0
	for i in 3:
		if gaps[i].x < gaps[nearest].x:
			nearest = i
	if nearest == 0:
		local.x = gaps[0].y * inner.x
	else:
		local.z = -HULL_FRONT - tank.radius if nearest == 1 else HULL_REAR + tank.radius
	var pushed := global_position + yaw * local
	tank.displace(Vector3(pushed.x, Course.height_at(pushed), pushed.z))
	if _bump <= 0.0:
		_bump = 1.0
		var away := Vector3(tank.global_position.x - global_position.x, 0.0, tank.global_position.z - global_position.z).normalized()
		var hit := Hit.make(Hit.Kind.RAM, HULL_DAMAGE, tank.hit_center(), away)
		hit.source = self
		tank.take_hit(hit)
		tank.local_velocity += Vector2(away.x, away.z) * HULL_SHOVE
		World.current.shake(0.5, tank.global_position)
		Sfx.play("impact", tank.global_position)


# --- Attacks -----------------------------------------------------------------------------------

func _flames_alive() -> Array[String]:
	var result: Array[String] = []
	for name in ["flame_l", "flame_r"]:
		if parts[name] > 0.0:
			result.append(name)
	return result


## Whether the tank lies inside the swing of the gun `name` (in the hull's frame).
func _in_arc(name: String, tank: Tank) -> bool:
	var local := model.global_transform.affine_inverse() * tank.hit_center() - (_guns[name].get_parent() as Node3D).position
	return Vector3(local.x, 0.0, local.z).angle_to(Vector3.FORWARD) <= FLAME_ARC


## A hull this big would white out the screen with every hit; its hits read as sparks and damage numbers instead.
func flash() -> void:
	pass


func _end_attack() -> void:
	_attack = Attack.NONE
	_next_attack = WINDOW[phase]
	for jet in _jets:
		if is_instance_valid(jet):
			jet.life = 0.0
	_jets.clear()


func _update_attack(delta: float, tank: Tank) -> void:
	if _attack == Attack.NONE:
		_next_attack -= delta
		if _next_attack <= 0.0:
			_begin_attack(tank)
		return
	_attack_time += delta
	var wind := WIND * Game.telegraph_scale()
	match _attack:
		Attack.FLAME:
			_update_flame(delta, tank, wind)
		Attack.SALVO:
			_update_salvo(delta, tank, wind)
		Attack.CRUSH:
			if _attack_time >= wind + CRUSH_TIME or _rim_gap() < 30.0:
				_end_attack()


## Picks the next attack from the cycle, skipping what the fortress can no longer do or the tank is out of reach of.
func _begin_attack(tank: Tank) -> void:
	var world := World.current
	for i in 4:
		var kind: Attack = [Attack.SALVO, Attack.FLAME, Attack.CRUSH, Attack.FLAME][(_pattern + i) % 4]
		var reach := global_position.distance_to(tank.global_position) < FLAME_REACH + 10.0 and _flames_alive().any(func(name: String) -> bool: return _in_arc(name, tank))
		if (kind == Attack.SALVO and parts.turret <= 0.0) or (kind == Attack.FLAME and not reach) or (kind == Attack.CRUSH and _tracks() < 2):
			continue
		_pattern += i + 1
		_attack = kind
		_attack_time = 0.0
		_shots = 0
		_shot_timer = 0.0
		var wind := WIND * Game.telegraph_scale()
		match kind:
			Attack.CRUSH:
				_lane = Vector3(-sin(_yaw), 0.0, -cos(_yaw))
				for step in 6:
					world.fx.marker(global_position + _lane * (HULL_FRONT + 12.0 + step * 20.0), HULL_HALF * 0.6, wind, Palette.RED)
				Sfx.play("roar", global_position, 4.0, 0.6)
			Attack.SALVO:
				world.fx.beam(_muzzle.global_position, tank.hit_center(), Palette.HOT, 0.2, wind)
			_:
				Sfx.play("warn", global_position, 2.0, 0.5)
		return
	_next_attack = 0.8


func _update_flame(delta: float, tank: Tank, wind: float) -> void:
	var world := World.current
	var burning := _attack_time >= wind
	for name in _flames_alive():
		var gun := _guns[name]
		if _in_arc(name, tank) and not burning:
			aim_barrel(gun, tank.hit_center(), 1.0, delta)
		if not burning and randf() < delta * 8.0:
			world.fx.marker(_muzzles[name].global_position - _muzzles[name].global_basis.z * FLAME_REACH, 10.0, 0.15, Palette.AMBER)
			world.fx.tongue(_muzzles[name].global_position, 1.5, 0.8)
	if burning and _jets.is_empty():
		for name in _flames_alive():
			var jet := FlameJet.start(self, _muzzles[name], 2.6 + 0.4 * phase, FLAME_REACH, 3.0)
			jet.burn = FLAME_BURN
			_jets.append(jet)
	if burning and _jets.all(func(jet) -> bool: return not is_instance_valid(jet)):
		_end_attack()


func _update_salvo(delta: float, tank: Tank, wind: float) -> void:
	if _attack_time < wind:
		return
	_shot_timer -= delta
	if _shot_timer > 0.0:
		return
	var world := World.current
	var count: int = SALVO_SHELLS[phase]
	var forward := tank.predicted(SHELL_FLIGHT) - global_position
	var across := Vector3(forward.z, 0.0, -forward.x).normalized()
	var target := tank.predicted(SHELL_FLIGHT) + across * (_shots - (count - 1) * 0.5) * 12.0
	target.y = Course.height_at(target)
	var from := _muzzle.global_position
	var velocity := (target - from) / SHELL_FLIGHT + Vector3.UP * 0.5 * 20.0 * SHELL_FLIGHT
	muzzle_blast(from, velocity.normalized(), Muzzle.HEAVY, "mortar")
	var shell := world.spawn_projectile(Team.ENEMY, from, velocity, "mortar", Palette.HOT)
	shell.gravity = 20.0
	shell.hit = Hit.make(Hit.Kind.SHELL, 0.0, from)
	shell.hit.source = self
	shell.blast_radius = 5.0
	shell.blast_damage = 18.0
	shell.interceptable = true
	shell.intercept_hp = 2.5
	shell.life = SHELL_FLIGHT + 1.0
	shell.trail = Palette.DUSK
	shell.impacted.connect(func(_shot: Projectile, point: Vector3, _target: Entity) -> void: FireZone.ignite(Vector3(point.x, Course.height_at(point), point.z), "shell", true))
	world.fx.marker(target, 5.0, SHELL_FLIGHT, Palette.HOT)
	Sfx.play("cannon", from, 4.0, 0.7)
	_shots += 1
	_shot_timer = 0.4
	if _shots >= count:
		_end_attack()


# --- Death -------------------------------------------------------------------------------------

## The hull burns and blows from the inside, then goes up.
func _die(delta: float) -> void:
	var world := World.current
	_dying -= delta
	_speed = move_toward(_speed, 0.0, 6.0 * delta)
	global_position += Vector3(-sin(_yaw), 0.0, -cos(_yaw)) * _speed * delta
	if randf() < delta * 7.0:
		world.fx.explosion(model.to_global(Vector3(randf_range(-15, 15), randf_range(12, 32), randf_range(-28, 28)) * SCALE), 7.0)
		world.shake(0.4, global_position)
	world.fx.smoke_puff(model.to_global(Vector3(randf_range(-15, 15), 30.0, randf_range(-25, 25)) * SCALE), 4.0)
	if _dying <= 0.0:
		die(killing_hit)


func on_death(_hit: Hit) -> void:
	var world := World.current
	var at := model.to_global(Vector3(0.0, 14.0, 0.0) * SCALE)
	world.fx.explosion(at, 38.0)
	world.fx.shockwave(at, 150.0, Palette.BUTTER)
	world.fx.debris(at, 50, debris, 30.0, 1.0)
	world.fx.smoke_column(at, 20.0)
	world.award(score, at, true)
	world.style_event("GIANT", 300.0)
	world.shake(0.9, at)
	for kind in ["coax", "repair", "era"]:
		world.spawn_pickup(kind, global_position + Vector3(randf_range(-50, 50), 1, randf_range(-50, 50)))
	Sfx.play("blast", at, 4.0)
