class_name Glinter
extends Enemy
## Stage 3 solar sniper: a mirror dish on a pylon that glints, tracks the tank with a thin sight line, then locks
## a ground ring and fires a laser at it. Break the line of sight, leave the ring before it fires, or shoot it.

enum State { IDLE, TRACK, LOCK }

const REACH := Vector2(-10.0, 190.0) ## Fires while the tank is this far behind/ahead along the road.
const TRACK_TIME := 1.4
const LOCK_TIME := 0.7
const LOCK_LEAD := 0.7 ## Seconds ahead the tank's motion is predicted for the locked ring.
const BEAM_RADIUS := 4.0
const BEAM_DAMAGE := 22.0
const COOLDOWN := 3.0
const SIGHT := Palette.CORAL

var state := State.IDLE
var _state_time := 0.0
var _timer := 2.0
var _aim := Vector3.ZERO
var _dish := Node3D.new()


func _init() -> void:
	super()
	max_hp = 35.0
	hp = 35.0
	radius = 1.6
	center_height = 3.6
	stabbable = true
	score = 400
	debris = [Fx.Debris.METAL, Fx.Debris.PAINT]
	weakness = {Hit.Kind.BLAST: 1.3}


func build() -> void:
	global_position.y = Course.height_at(global_position)
	var base := MeshInstance3D.new()
	base.mesh = ActorMeshes.mesh("glinter", "base")
	model.add_child(base)
	_dish.position = Vector3(0, 3.8, 0)
	model.add_child(_dish)
	var mirror := MeshInstance3D.new()
	mirror.mesh = ActorMeshes.mesh("glinter", "dish")
	_dish.add_child(mirror)


func telegraphing() -> bool:
	return state == State.LOCK


func interrupt() -> void:
	super()
	_end()


func behave(delta: float) -> void:
	var tank := player()
	if tank == null or tank.dead:
		return
	_state_time += delta
	if is_staggered():
		_end()
		return
	var emitter := _dish.global_position
	var sees := _sees(emitter, tank.hit_center())
	if state != State.LOCK:
		_dish.look_at(tank.hit_center(), Vector3.UP)
	match state:
		State.IDLE:
			_timer -= delta
			var along := Course.to_course(global_position).x - Course.to_course(tank.global_position).x
			if _timer <= 0.0 and sees and along > REACH.x and along < REACH.y:
				_set_state(State.TRACK)
				World.current.fx.impact_star(emitter, 3.0, Palette.WHITE)
				World.current.fx.light_flash(emitter, 6.0, Palette.WHITE, 10.0)
				Sfx.play("warn", emitter, 0.0, 1.4)
		State.TRACK:
			if not sees:
				_end() # Behind a dune or a wall: the sight line is cut.
				return
			World.current.fx.beam(emitter, tank.hit_center(), SIGHT, 0.06, 0.05)
			if _state_time >= TRACK_TIME:
				_aim = tank.hit_center() + tank.velocity * LOCK_LEAD
				World.current.fx.marker(_aim, BEAM_RADIUS, LOCK_TIME * Game.telegraph_scale(), Palette.HOT)
				Sfx.play("lock", emitter)
				_set_state(State.LOCK)
		State.LOCK:
			World.current.fx.beam(emitter, _aim, Palette.HOT, 0.1, 0.05)
			if _state_time >= LOCK_TIME * Game.telegraph_scale():
				_fire(tank, emitter)


func _fire(tank: Tank, emitter: Vector3) -> void:
	var world := World.current
	world.fx.beam(emitter, _aim, Palette.WHITE, 0.6, 0.18, true)
	world.fx.impact_star(_aim, 4.0, Palette.WHITE)
	world.fx.scorch(Vector3(_aim.x, Course.height_at(_aim), _aim.z), 2.0)
	Sfx.play("zap", emitter, 4.0)
	if tank.hit_center().distance_to(_aim) <= BEAM_RADIUS:
		var hit := Hit.make(Hit.Kind.LASER, BEAM_DAMAGE, _aim, (_aim - emitter).normalized())
		hit.source = self
		tank.take_hit(hit)
	_end()


func _end() -> void:
	_timer = COOLDOWN
	_set_state(State.IDLE)


func _set_state(value: State) -> void:
	state = value
	_state_time = 0.0


## True when no ground or building stands between the dish and the tank.
func _sees(from: Vector3, to: Vector3) -> bool:
	for i in range(1, 12):
		var point := from.lerp(to, i / 12.0)
		if Course.height_at(point) > point.y:
			return false
	return CityCover.blocker(from, to) == null
