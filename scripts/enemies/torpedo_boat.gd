class_name TorpedoBoat
extends Enemy
## Stage 2 gunboat with a bow torpedo tube. It holds station ahead of the tank, marks a row of foam along the
## lane its torpedo will run, then launches: change lanes, burn the torpedo down, or sink the boat.

enum State { PACE, AIM, REARM }

const KEEP_AHEAD := 60.0
const PACE_SPEED := 18.0
const LANE_SPEED := 10.0
const AIM_TIME := 1.1
const REARM_TIME := 2.8
const TORPEDO_SPEED := 26.0
const TORPEDO_DAMAGE := 28.0
const MARKS := 5
const FAN := 0.2 ## Radians between the torpedoes of a Hard salvo.

var state := State.PACE
var _state_time := 0.0
var _lane := 0.0 ## Lateral offset it sails to before the next shot.
var _aim := Vector3.ZERO
var _lamp := MeshInstance3D.new()
var _wake := 0.0


func _init() -> void:
	super()
	max_hp = 40.0
	hp = 40.0
	armor = 6.0
	radius = 1.8
	center_height = 0.8
	stabbable = true
	score = 400
	debris = [Fx.Debris.METAL, Fx.Debris.PAINT]
	weakness = {Hit.Kind.BLAST: 1.3, Hit.Kind.SHELL: 1.2}


func build() -> void:
	var b := LowPoly.new()
	b.frustum(Transform3D(Basis(), Vector3(0, -0.3, 0)), Vector2(2.2, 8.0), Vector2(1.8, 7.0), 1.0, Palette.SLATE, Palette.DUSK)
	b.box(Transform3D(Basis(), Vector3(0, 1.3, 1.4)), Vector3(1.4, 1.0, 1.6), Palette.CONCRETE)
	b.prism(Transform3D(Basis(), Vector3(0, 1.8, 1.4)), 0.06, 1.4, 4, Palette.INK)
	b.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.9, -1.2)), 0.35, 2.8, 6, Palette.OCHRE)
	var body := MeshInstance3D.new()
	body.mesh = b.mesh()
	model.add_child(body)
	var lamp := LowPoly.new()
	lamp.glow = true
	lamp.box(Transform3D(), Vector3(0.4, 0.2, 0.1), Palette.RED)
	_lamp.mesh = lamp.mesh()
	_lamp.position = Vector3(0, 1.3, -2.5)
	model.add_child(_lamp)
	_lane = Course.to_course(global_position).y


func telegraphing() -> bool:
	return state == State.AIM


func interrupt() -> void:
	super()
	_lamp.show()
	_set_state(State.REARM)


func behave(delta: float) -> void:
	var tank := player()
	if tank == null or tank.dead or is_staggered():
		return
	_state_time += delta
	var world := World.current
	var previous := global_position
	match state:
		State.PACE:
			var lane := Course.to_course(global_position)
			var station := world.rail.d + tank.course_offset + KEEP_AHEAD
			lane.x = move_toward(lane.x, station, PACE_SPEED * delta)
			lane.y = move_toward(lane.y, _lane, LANE_SPEED * delta)
			global_position = Course.to_world(lane.x, lane.y)
			if absf(lane.x - station) < 8.0 and absf(lane.y - _lane) < 1.0 and Water.surface_at(global_position) > -INF:
				_set_state(State.AIM)
				_aim_lane(tank)
		State.AIM:
			_lamp.visible = fmod(_state_time, 0.2) < 0.1
			if _state_time >= AIM_TIME * Game.telegraph_scale():
				_fire_torpedoes()
		State.REARM:
			if _state_time >= REARM_TIME:
				var reach := Tank.lateral_limit(world.rail.d) - 4.0
				_lane = clampf(tank.course_u + randf_range(-14.0, 14.0), -reach, reach)
				_set_state(State.PACE)
	var surface := Water.surface_at(global_position)
	global_position.y = (surface if surface > -INF else Course.height_at(global_position)) + sin(age * 3.0) * 0.05
	var toward := tank.global_position - global_position
	model.rotation.y = lerp_angle(model.rotation.y, atan2(-toward.x, -toward.z), 3.0 * delta)
	_wake -= delta
	if _wake <= 0.0 and (global_position - previous).length() > 0.05:
		_wake = 0.1
		world.fx.wake(global_position, (global_position - previous) / maxf(delta, 0.001), 1.6, global_position.y)


## Chooses the lane the torpedo will run and lays foam markers down it.
func _aim_lane(tank: Tank) -> void:
	_aim = FpvDrone.intercept(global_position, tank.global_position, tank.velocity, TORPEDO_SPEED)
	_aim.y = global_position.y
	var run := _aim - global_position
	var reach := maxf(run.length(), 20.0)
	for i in MARKS:
		var at := global_position + run.normalized() * reach * (i + 1.0) / MARKS
		World.current.fx.marker(at, 2.5, AIM_TIME * Game.telegraph_scale() + at.distance_to(global_position) / TORPEDO_SPEED, Palette.HOT)
	Sfx.play("boat_warn", global_position)


func _fire_torpedoes() -> void:
	_lamp.show()
	var from := global_position + Vector3.UP * 0.4 - model.global_basis.z * 2.8
	var heading := (_aim - from) * Vector3(1, 0, 1)
	var shots := 3 if Game.difficulty == Game.Difficulty.HARD else 1
	for i in shots:
		var dir := heading.normalized().rotated(Vector3.UP, (i - (shots - 1) * 0.5) * FAN)
		var torpedo := World.current.spawn_projectile(Team.ENEMY, from, dir * TORPEDO_SPEED, "torpedo", Palette.CREAM)
		torpedo.hit = Hit.make(Hit.Kind.BLAST, 0.0, from)
		torpedo.hit.source = self
		torpedo.blast_radius = 3.2
		torpedo.blast_damage = TORPEDO_DAMAGE
		torpedo.interceptable = true
		torpedo.intercept_hp = 1.4
		torpedo.life = 6.0
		torpedo.trail = Palette.WHITE
		torpedo.impacted.connect(func(_p: Projectile, point: Vector3, _t: Entity) -> void: World.current.fx.splash(point, 3.5, Water.surface_at(point)))
	muzzle_blast(from, heading.normalized(), Muzzle.HEAVY, "torpedo")
	Sfx.play("launch", from, 0.0, 0.8)
	_set_state(State.REARM)


func _set_state(value: State) -> void:
	state = value
	_state_time = 0.0
