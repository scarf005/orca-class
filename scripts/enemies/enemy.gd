class_name Enemy
extends Entity
## Base for hostile units: score, weaknesses, stagger, burning, telegraphs, tail grabs and cleanup.

const TRACK_RATE := 8.0 ## Per second `track_velocity` closes on `velocity`.
const MIN_TRACK_DELTA := 0.002 ## Frames shorter than this (hitstop) say nothing about speed.
const TELEPORT_DISTANCE := 6.0 ## A one-frame move this long is a jump, not travel.
const BURN_FLAME_INTERVAL := 0.1 ## Seconds between the tongues a burning body throws.
const BURN_LIGHT_RADIUS := 2.2 ## Bodies this big light the ground while they burn.
const SWAY_LIMIT := 30.0 ## Acceleration (m/s²) that the body's lean and bob stop reading.
const SWAY_RATE := 6.0 ## Per second the smoothed acceleration closes on the measured one.
const MG_SPEED := 150.0 ## Every enemy machine gun fires as fast a round as the coax: the telegraph is the warning, not a slow round.

var score := 100
var velocity := Vector3.ZERO
var track_velocity := Vector3.ZERO ## Smoothed `velocity` for lead: steady through hitstop and lane hops.
var stabbable := false
var weakness := {} ## Hit.Kind -> damage multiplier.
var death_radius := 2.0 ## Size of the death blast: half the model's longest side, set once it is built.
var debris: Array = [Fx.Debris.ARMOR, Fx.Debris.METAL] ## Fx.Debris materials it breaks into.
var drop := ""
var boss := false
var heavy := false ## A boss's hide: canister balls and airbursts barely scratch it.
var stagger := 0.0
var burning := 0.0
var can_stagger := true
var trails := false ## Flyers leave a fading trail (FlyerTrail).
var despawn_behind := 30.0 ## Removed once this far behind the rail; 0 keeps it.
var mark_offsets: Array[float] = [] ## Ground vehicles print a line into World.enemy_marks at each of these lateral offsets.
var mark_width := 1.0 ## How wide those prints are next to a tank's tread.
var _mark_last := Vector3.INF
var _sway_velocity := Vector3.ZERO
var _sway := Vector3.ZERO
var _shudder := 0.0 ## Seconds of hit shudder left.
var wreck_on_death := false ## Vehicles: the hull is blown into the air and blows up again on landing.
var pop_parts: Array[Node3D] = [] ## Parts (turrets) that blow off and fly separately when it dies as a wreck.
var model := Node3D.new()
var age := 0.0
var _last_position := Vector3.ZERO
var _burn_tick := 0.0
var _burn_hit: Hit
var killing_hit: Hit ## The lethal hit retained through a delayed crash or death throes.
var _flame_tick := 0.0
var hidden := false
var ambush_host: Prop
var _ambush_wind := -1.0
var _ambush_roof := Vector3.ZERO
var _ambush_exit := Vector3.ZERO
var _ambush_interceptable := false
var evasive := false
var _jink_active := false
var _jink_phase := 0.0
var _jink_offset := Vector3.ZERO
var _jink_velocity := Vector3.ZERO
var _jink_acceleration := Vector3.ZERO
var _jink_axis := Vector3.RIGHT
var _jink_previous := Vector3.ZERO
var _shell_watch := 0.0
var _shell_threat := false
var _jink_banking := false
var _jink_up := Vector3.UP


func _init() -> void:
	team = Team.ENEMY


func _ready() -> void:
	model.name = "Model"
	add_child(model)
	build()
	apply_difficulty()
	track_meshes(model)
	if trails:
		FlyerTrail.follow(self)
	var extent := visual_bounds().size
	if extent != Vector3.ZERO:
		death_radius = maxf(extent.x, maxf(extent.y, extent.z)) * 0.5
	ActorLayer.mark(self, ActorLayer.HOSTILE)
	_last_position = global_position
	World.current.stats.spawned += 1


func apply_difficulty() -> void:
	armor *= 0.25 if Game.difficulty == Game.Difficulty.EASY else 1.0
	max_hp *= Game.enemy_hp_scale(boss)
	hp *= Game.enemy_hp_scale(boss)


## Subclasses add meshes to `model` here.
func build() -> void:
	pass


func tick(delta: float) -> void:
	if hidden:
		_update_ambush(delta)
		return
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


func hide_in(host: Prop, site := Vector3.ZERO, height := 5.0, footprint := 4.2) -> void:
	ambush_host = host
	if is_instance_valid(host):
		site = host.global_position
		height = host.height
		footprint = host.footprint
	hidden = true
	invulnerable = true
	visible = false
	_ambush_interceptable = interceptable
	interceptable = false
	global_position = site + Vector3.UP
	_ambush_roof = site + Vector3.UP * height
	var toward := player().global_position - site
	toward.y = 0.0
	_ambush_exit = _ambush_roof + Vector3.UP * 2.0 if flying else site + toward.normalized() * (footprint + radius + 1.0)
	_ambush_exit.y = maxf(_ambush_exit.y, Course.height_at(_ambush_exit))
	if is_instance_valid(host) and not host.dead:
		host.died.connect(func(_host: Entity) -> void: _warn_ambush())
	else:
		_warn_ambush()


func _warn_ambush() -> void:
	if not hidden or _ambush_wind >= 0.0:
		return
	_ambush_wind = 0.65
	var fx := World.current.fx
	fx.dust(_ambush_roof, 18, 2.5, Palette.STRAW)
	fx.marker(_ambush_roof, 4.0, _ambush_wind, Palette.HOT)
	fx.light_flash(_ambush_roof, 5.0, Palette.BUTTER, 8.0)
	Sfx.play("warn", _ambush_roof, -2.0, 0.8)


func _update_ambush(delta: float) -> void:
	if _ambush_wind < 0.0:
		if not is_instance_valid(ambush_host) or ambush_host.dead or player().global_position.distance_to(global_position) < 55.0:
			_warn_ambush()
		return
	_ambush_wind = maxf(0.0, _ambush_wind - delta)
	if _ambush_wind > 0.0:
		return
	if is_instance_valid(ambush_host) and not ambush_host.dead:
		ambush_host.die(Hit.make(Hit.Kind.RAM, 0.0, _ambush_roof, (_ambush_exit - global_position).normalized()))
	World.current.fx.debris(_ambush_roof, 26, [Fx.Debris.CONCRETE, Fx.Debris.WOOD], 16.0, 0.5, (_ambush_exit - global_position).normalized())
	World.current.fx.dust(_ambush_roof, 12, 3.0, Palette.STRAW)
	global_position = _ambush_exit
	_last_position = global_position
	hidden = false
	invulnerable = false
	visible = true
	interceptable = _ambush_interceptable
	ambush_host = null


func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	return -1.0 if hidden else super.hit_test(from, to, extra_radius)


## Move the flight goal, not the airframe: rotorcraft follow it with their flight controller;
## fixed-wing aircraft turn into it with a bank. React to a nearby bore before it locks.
func _evade(delta: float, rotorcraft := false) -> void:
	var tank := player()
	var threatened := false
	if evasive and Game.difficulty == Game.Difficulty.HARD and not invulnerable and not is_staggered() and tank != null and not tank.dead:
		threatened = tank.charge_lock == self
		if not threatened:
			var muzzle := tank.model.muzzle.global_position
			var bore := -tank.model.barrel.global_basis.z.normalized()
			threatened = hit_test(muzzle, muzzle + bore * Armament.SHELL_RANGE, 6.0) >= 0.0
		if not threatened:
			# At most 10 scans/s without a bore threat; the look-ahead covers the scan interval.
			_shell_watch -= delta
			if _shell_watch <= 0.0:
				_shell_watch = 0.1
				_shell_threat = false
				for shot in World.current.projectiles:
					if shot.team != Team.PLAYER or shot.hit == null or shot.hit.kind != Hit.Kind.SHELL or shot.is_queued_for_deletion():
						continue
					var closest := Geometry3D.get_closest_point_to_segment(hit_center(), shot.global_position, shot.global_position + shot.velocity * 0.15)
					if closest.distance_to(hit_center()) < radius + 6.0:
						_shell_threat = true
						break
			threatened = _shell_threat
	if threatened and not _jink_active:
		if rotorcraft:
			_jink_up = model.global_basis.y.normalized()
			_jink_banking = true
			_jink_acceleration = Vector3(_jink_up.x, 0.0, _jink_up.z) * 9.81 / maxf(_jink_up.y, 0.1)
		_jink_axis = Vector3(model.global_basis.x.x, 0.0, model.global_basis.x.z).normalized()
		_jink_phase = 0.0
	_jink_active = threatened
	if threatened:
		_jink_phase += delta * 0.9
	var goal := _jink_axis * sin(_jink_phase) * 12.0 if threatened else Vector3.ZERO
	# Altitude-holding thrust at a 0.65 rad tilt supplies g*tan(tilt) horizontally.
	# Limiting jerk to g*roll_rate also bounds the tilt's angular speed.
	var desired := ((goal - _jink_offset) * 2.0 - _jink_velocity * 4.0).limit_length(9.81 * tan(0.65))
	_jink_acceleration = _jink_acceleration.move_toward(desired, 9.81 * 0.9 * delta)
	_jink_velocity += _jink_acceleration * delta
	_jink_previous = _jink_offset
	_jink_offset += _jink_velocity * delta


## The model's rotor thrust axis supplies the same horizontal acceleration as its movement.
func _bank_evasion(delta: float) -> void:
	if not _jink_banking:
		return
	# Below 5 cm of displacement and 5 cm/s of drift, finish the attitude handoff.
	var settling := _jink_active or _jink_offset.length_squared() > 0.0025 or _jink_velocity.length_squared() > 0.0025 or _jink_acceleration.length_squared() > 0.0025
	var up := (Vector3.UP * 9.81 + _jink_acceleration).normalized() if settling else model.global_basis.y.normalized()
	var angle := _jink_up.angle_to(up)
	_jink_up = _jink_up.slerp(up, minf(1.0, delta * 0.9 / maxf(angle, 0.00001))).normalized()
	if not settling and angle <= delta * 0.9:
		_jink_banking = false
		return
	var heading := Vector3.FORWARD.rotated(Vector3.UP, model.rotation.y).slide(_jink_up).normalized()
	model.basis = Basis.looking_at(heading, _jink_up)


## Prints for what it drove over since the last frame; none while it is in the reservoir.
func _leave_marks() -> void:
	if mark_offsets.is_empty():
		return
	var side := Vector3(model.global_basis.x.x, 0.0, model.global_basis.x.z).normalized()
	var hull := Transform3D(Basis(side, Vector3.UP, side.cross(Vector3.UP)), global_position)
	_mark_last = World.current.enemy_marks.lay(_mark_last, hull, mark_offsets, mark_width, _wet, false)


## Meters the model rolled along its heading since the last frame; negative when it backs away
## from where it faces. Spins the wheels of a mech that rolls on its feet.
func rolled() -> float:
	var moved := global_position - _last_position
	return moved.length() * (-1.0 if moved.dot(-model.global_basis.z) < 0.0 else 1.0)


## How hard the body is accelerating in the model's frame (x right, y up, z back), smoothed: the
## suspension compresses with y and the hull leans into x and z.
func sway(delta: float) -> Vector3:
	if delta <= MIN_TRACK_DELTA:
		return _sway
	var velocity := (global_position - _last_position) / delta
	var accel := ((velocity - _sway_velocity) / delta).limit_length(SWAY_LIMIT)
	_sway_velocity = velocity
	_sway = _sway.lerp(model.global_basis.inverse() * accel, 1.0 - exp(-SWAY_RATE * delta))
	return _sway


## Per-frame AI for subclasses. Not called while dead.
func behave(_delta: float) -> void:
	pass


func player() -> Tank:
	return World.current.player


func is_staggered() -> bool:
	return stagger > 0.0


func damage_multiplier(hit: Hit) -> float:
	var multiplier: float = super.damage_multiplier(hit) * weakness.get(hit.kind, 1.0)
	if heavy and is_area_round(hit):
		multiplier *= HEAVY_AREA
	if hit.incendiary:
		multiplier *= weakness.get(Hit.Kind.FIRE, 1.0) if hit.kind != Hit.Kind.FIRE else 1.0
	return multiplier


func on_damaged(hit: Hit, amount: float) -> void:
	impact_feedback(hit, amount, hp <= 0.0)
	if can_stagger and hit.stagger > 0.0:
		stagger = maxf(stagger, hit.stagger)
	if hit.incendiary:
		burning = 3.0
		_burn_hit = hit.copy()


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
		Sfx.confirm_hit(killed, heavy)
		world.shake(0.16 if heavy else 0.05, hit.position)
		if killed:
			world.hitstop(0.09 if heavy else 0.05)
			world.shake(0.28 if heavy else 0.18, hit.position)
			world.fx.shockwave(hit_center(), 3.0 + radius * 2.0, Palette.WHITE)
			world.fx.impact_star(hit_center(), 2.4 + radius, Palette.BUTTER)


func _burn(delta: float) -> void:
	burning -= delta
	_burn_tick -= delta
	_burn_flames(delta)
	if _burn_tick <= 0.0:
		_burn_tick = 0.25
		if not dead:
			var burn := Hit.make(Hit.Kind.FIRE, 5.0, hit_center())
			if _burn_hit:
				burn.source = _burn_hit.source if is_instance_valid(_burn_hit.source) else null
				burn.weapon = _burn_hit.weapon
			take_hit(burn)


## Flames engulf the body: several tongues a tick over its whole volume, bigger with its size and
## bent back by its motion, with a smoke column, embers and, on big bodies, a flickering light.
func _burn_flames(delta: float) -> void:
	_flame_tick -= delta
	if _flame_tick > 0.0 or dead:
		return
	_flame_tick = BURN_FLAME_INTERVAL
	var fx := World.current.fx
	var center := hit_center()
	var lick := -Vector3(track_velocity.x, 0.0, track_velocity.z).limit_length(20.0) * 0.25
	var reach := Vector3(radius * 0.8, center_height * 0.9, radius * 0.8)
	for i in clampi(roundi(1.0 + death_radius * 1.3), 2, 7):
		var offset := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		fx.tongue(center + offset * reach, (0.6 + death_radius * 0.5) * randf_range(0.7, 1.3), 0.5 + offset.y * -0.5, lick)
	if randf() < 0.5:
		fx.smoke_puff(center + Vector3.UP * center_height, 0.6 + death_radius * 0.3, lick)
	if randf() < 0.35:
		fx.embers(center, 1, radius)
	if death_radius >= BURN_LIGHT_RADIUS and randf() < 0.5:
		fx.light_flash(center, randf_range(2.5, 4.0), Palette.AMBER, 5.0 + death_radius * 2.0)


## True during an attack wind-up that a hard enough hit breaks.
func telegraphing() -> bool:
	return false


## A full-charge main-gun hit that lands on a wind-up earns INTERRUPT, kill or not.
func take_hit(hit: Hit) -> void:
	if hit.power >= 1.0 and not dead and not invulnerable and telegraphing() and hit.damage * damage_multiplier(hit) > 0.0:
		World.current.style_event("INTERRUPT", 90.0)
	super(hit)


## Cancels a telegraphed attack (tail stab, heavy stagger).
func interrupt() -> void:
	stagger = maxf(stagger, 1.0)


func despawn() -> void:
	dead = true
	World.current.unregister(self)
	queue_free()


func die(hit: Hit) -> void:
	if not dead:
		var lethal := killing_hit if killing_hit else hit
		if lethal and lethal.kind == Hit.Kind.THROWN and lethal.source is Tank:
			lethal.salvage = true
		World.current.killed.emit(self, lethal)
	super.die(hit)


func on_death(hit: Hit) -> void:
	var world := World.current
	var center := hit_center()
	var by_player := hit != null and hit.by_player()
	var push := kill_push(hit)
	# The death blast hurts whatever is close, so packed enemies go up in chains.
	var chain := Hit.new()
	chain.weapon = "collateral"
	chain.source = world.player if by_player else null
	world.blast(center, death_radius * 1.4, 35.0, Team.PLAYER if by_player else Team.NEUTRAL, chain, self, [Palette.WHITE, Palette.AMBER, Palette.HOT, Palette.CORAL], push)
	# A hull stays whole as a wreck and sheds only some of itself; an overkill (a 100 mm hit) tears
	# off more and throws it harder. Anything without a hull goes to pieces.
	var remains := wreck_on_death
	var share := (0.7 if overkilled else 0.35) if wreck_on_death else 1.0
	if torn_apart(hit):
		# A shell's energy sets how fast the chips fly; only the focus decides how much they follow the shot.
		world.fx.shatter(visual_bounds(), debris, push.normalized() * dismember_focus(push), share, 1.0 + push.length() * 0.5)
	else:
		world.fx.shatter(visual_bounds(), debris, push, share)
	world.fx.smoke_column(center, death_radius, [Palette.DUSK, Palette.INK, Palette.ASH])
	if remains:
		# The entity stops ticking after death, so its flash cannot expire on detached wrecks.
		for mesh in _meshes:
			if is_instance_valid(mesh):
				mesh.material_overlay = rest_overlay
		# Remains are no longer a threat: drop the hostile outline.
		ActorLayer.unmark(model, ActorLayer.HOSTILE)
		if torn_apart(hit):
			_dismember(center, push, by_player)
		else:
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


static var DISMEMBER_SPEED := 16.0 ## Outward speed (m/s) a shell kill tears the pieces apart at (tuned live in the duel mode).
static var DISMEMBER_FOCUS := 1.0 ## How much a harder shot narrows the burst toward its own flight (0: always a full burst).


## A shell tears the hull apart: every piece of the model flies off on its own, outward from the
## middle and up, with only some of the shot's push, so the kill reads as a burst instead of one lump
## carried straight along the line of fire. The biggest piece still blows up where it lands.
func _dismember(center: Vector3, push: Vector3, by_player: bool) -> void:
	var pieces: Array[MeshInstance3D] = []
	pieces.assign(model.find_children("*", "MeshInstance3D", true, false))
	var sizes: Array[float] = []
	var biggest := 0
	for i in pieces.size():
		sizes.append((pieces[i].global_basis * pieces[i].mesh.get_aabb().size).length() if pieces[i].mesh else 0.5)
		if sizes[i] > sizes[biggest]:
			biggest = i
	var focus := dismember_focus(push)
	for i in pieces.size():
		var piece := pieces[i]
		var at := piece.global_transform * piece.mesh.get_aabb().get_center() if piece.mesh else piece.global_position
		var out := at - center
		out.y = maxf(out.y, 0.0) + 0.8
		out = (out.normalized() + Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)) * 0.6).normalized()
		if push.length_squared() > 0.0001:
			out = out.slerp(push.normalized(), focus)
		var size := maxf(sizes[i] * 0.5, 0.3)
		# The shot's energy only makes them fly faster; their direction is the burst bent by the focus.
		var speed := (DISMEMBER_SPEED + push.length() * 6.0) * randf_range(0.7, 1.4)
		Wreck.launch(piece, at, size, by_player, out * speed * sqrt(maxf(size, 1.0)), i == biggest)
	model.queue_free()


## A main-gun round tears what it kills to pieces: a direct hit, or the blast of its filler next to it.
static func torn_apart(hit: Hit) -> bool:
	return hit != null and (hit.weapon == "canister" or (hit.caliber >= 100 and hit.kind in [Hit.Kind.SHELL, Hit.Kind.BLAST]))


## How far (0..1) a shell kill's pieces bend from a full burst toward the shot: more with more
## momentum, scaled by DISMEMBER_FOCUS; at 0 they always burst all round.
static func dismember_focus(push: Vector3) -> float:
	return clampf(1.0 - exp(-DISMEMBER_FOCUS * push.length() * 0.3), 0.0, 0.95)


const CANISTER_THROW := 3.0
const HEAVY_AREA := 0.08 ## What a boss's hide lets through of a canister ball or an airburst.


## Canister balls and airburst fragments: they wreck ordinary enemies and only scratch a boss's hide.
static func is_area_round(hit: Hit) -> bool:
	return hit.kind == Hit.Kind.FRAGMENT or hit.weapon == "canister"
const KILL_SHELL_SPEED := 260.0 ## A shell this fast throws the remains at the base push; faster ones by their kinetic energy.
static var KILL_THROW_MAX := 3.0 ## Cap on that energy multiplier (tuned live in the duel mode); KILL_THROW_UNCAPPED or more lifts it.
const KILL_THROW_UNCAPPED := 45.0


## How hard and which way the killing blow throws the remains: shells send them flying on along the
## shot as hard as their kinetic energy (speed squared), rams fling them, blasts shove them out,
## bullets barely nudge.
static func kill_push(hit: Hit) -> Vector3:
	if hit == null:
		return Vector3.ZERO
	var dir := Vector3(hit.direction.x, maxf(hit.direction.y, 0.0) * 0.5, hit.direction.z).normalized()
	if hit.weapon == "canister":
		return dir * CANISTER_THROW # A face full of tungsten throws what it kills straight back.
	match hit.kind:
		Hit.Kind.SHELL:
			var energy := pow(hit.speed / KILL_SHELL_SPEED, 2.0) if hit.speed > 0.0 else 1.0
			return dir * maxf(energy, 0.5) if KILL_THROW_MAX >= KILL_THROW_UNCAPPED else dir * clampf(energy, 0.5, KILL_THROW_MAX)
		Hit.Kind.RAM, Hit.Kind.THROWN, Hit.Kind.TAIL:
			return dir
		Hit.Kind.BLAST:
			# Out from the blast, harder the more of it reached this one.
			return dir * clampf(hit.damage / 150.0, 0.6, 4.0)
		Hit.Kind.FRAGMENT:
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


## `factor` for a coax round that strikes inside the front arc (60° either side of where the model
## faces, level), else 1: the plate that turns small arms from ahead.
func frontal_armor(hit: Hit, factor: float) -> float:
	var facing := -model.global_basis.z
	var incoming := -hit.direction
	facing.y = 0.0
	incoming.y = 0.0
	if hit.kind != Hit.Kind.BULLET or incoming.length_squared() < 0.0001:
		return 1.0
	var front := lerpf(1.0, factor, 0.25) if Game.difficulty == Game.Difficulty.EASY else factor
	return front if facing.angle_to(incoming) <= deg_to_rad(60.0) else 1.0
