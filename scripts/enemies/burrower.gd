class_name Burrower
extends Enemy
## Stage 3 sand ambusher. It tunnels toward the tank under a rippling dust trail, marks the ring where the
## tank will be and erupts there: leave the ring in time, then shoot it while it stands exposed, before it
## drops back under.

enum State { TUNNEL, MARK, EXPOSED }

const TUNNEL_SPEED := 26.0
const STRIKE_RANGE := 45.0 ## Distance at which it marks an eruption.
const MARK_TIME := 1.2
const ERUPT_RADIUS := 5.5
const ERUPT_DAMAGE := 26.0
const EXPOSED_TIME := 3.5

var state := State.TUNNEL
var _state_time := 0.0
var _target := Vector3.ZERO
var _dust := 0.0
var _jaws: Array[Node3D] = []


func _init() -> void:
	super()
	max_hp = 40.0
	hp = 40.0
	radius = 1.8
	center_height = 1.0
	stabbable = true
	score = 350
	debris = [Fx.Debris.FLESH, Fx.Debris.CONCRETE]
	weakness = {Hit.Kind.FIRE: 1.5, Hit.Kind.TAIL: 1.5}


func build() -> void:
	var body := MeshInstance3D.new()
	body.mesh = ActorMeshes.mesh("burrower", "body")
	model.add_child(body)
	for side in [-1.0, 1.0]:
		var jaw := Node3D.new()
		jaw.position = Vector3(side * 1.0, 3.0, -1.35)
		var mesh := MeshInstance3D.new()
		mesh.mesh = ActorMeshes.mesh("burrower", "jaw_left" if side < 0.0 else "jaw_right")
		jaw.add_child(mesh)
		model.add_child(jaw)
		_jaws.append(jaw)
	_bury()


## Buried it is hidden: nothing targets, rams or hits it, and its tunnelling runs in place of the ambush wait.
func _bury() -> void:
	hidden = true
	invulnerable = true
	visible = false
	_set_state(State.TUNNEL)


func _update_ambush(delta: float) -> void:
	age += delta
	behave(delta)


func telegraphing() -> bool:
	return state == State.MARK


func behave(delta: float) -> void:
	var tank := player()
	if tank == null or tank.dead:
		return
	_state_time += delta
	var toward := tank.global_position - global_position
	toward.y = 0.0
	match state:
		State.TUNNEL:
			_slide(toward.normalized() * TUNNEL_SPEED * delta, delta)
			if toward.length() < STRIKE_RANGE:
				_target = tank.global_position + tank.velocity * MARK_TIME
				World.current.fx.marker(_target, ERUPT_RADIUS, MARK_TIME * Game.telegraph_scale(), Palette.HOT)
				Sfx.play("warn", _target, 0.0, 0.6)
				_set_state(State.MARK)
			elif Course.to_course(global_position).x < World.current.rail.d - 60.0:
				despawn()
		State.MARK:
			_slide((_target - global_position).limit_length(70.0 * delta), delta)
			if _state_time >= MARK_TIME * Game.telegraph_scale():
				_erupt(tank)
		State.EXPOSED:
			model.rotation.y = lerp_angle(model.rotation.y, atan2(-toward.x, -toward.z), 4.0 * delta)
			for i in _jaws.size():
				_jaws[i].rotation.y = (1.0 if i == 0 else -1.0) * (0.15 + 0.25 * sin(age * 9.0))
			if _state_time >= EXPOSED_TIME:
				World.current.fx.dust(global_position, 16, 4.0, Palette.STRAW)
				_bury()


## Moves under the sand, trailing dust.
func _slide(motion: Vector3, delta: float) -> void:
	global_position += motion
	global_position.y = Course.height_at(global_position)
	_dust -= delta
	if _dust <= 0.0:
		_dust = 0.1
		World.current.fx.dust(global_position, 3, 1.6, Palette.STRAW)


func _erupt(tank: Tank) -> void:
	var world := World.current
	hidden = false
	invulnerable = false
	visible = true
	_set_state(State.EXPOSED)
	world.fx.explosion(global_position, ERUPT_RADIUS * 0.5)
	world.fx.shockwave(global_position, ERUPT_RADIUS * 2.0, Palette.STRAW)
	world.fx.dust(global_position, 24, ERUPT_RADIUS, Palette.STRAW)
	world.shake(0.4, global_position)
	Sfx.play("blast", global_position)
	var flat := tank.global_position - global_position
	flat.y = 0.0
	if flat.length() <= ERUPT_RADIUS:
		var hit := Hit.make(Hit.Kind.BLAST, ERUPT_DAMAGE, global_position, Vector3.UP)
		hit.source = self
		tank.take_hit(hit)


func _set_state(value: State) -> void:
	state = value
	_state_time = 0.0


func on_death(hit: Hit) -> void:
	soft_death(hit)
