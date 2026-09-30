class_name Surge
extends Node3D
## The rush of water let out of a paddy gate (물꼬): a wave runs down-slope from the gate, knocks
## ground enemies back and hurts them. Credited to the tank when it broke the gate.

const SPEED := 16.0
const LENGTH := 34.0
const WIDTH := 4.5 ## Half width of the wave front.
const DAMAGE := 35.0
const SHOVE := 9.0 ## Meters an enemy is thrown along the flow.
const SHOVE_TIME := 0.35

var direction := Vector3.FORWARD
var by_player := false
var _travelled := 0.0
var _hit := {} ## Enemy -> seconds of shove left.
var _next_spray := 0.0


static func release(at: Vector3, direction_value: Vector3, credited: bool) -> Surge:
	var surge := Surge.new()
	surge.direction = direction_value
	surge.by_player = credited
	World.current.add_child(surge)
	surge.global_position = at
	Sfx.play("rush", at, 2.0)
	return surge


func _process(delta: float) -> void:
	var world := World.current
	_travelled += SPEED * delta
	var front := global_position + direction * _travelled
	_next_spray -= delta
	if _next_spray <= 0.0:
		_next_spray = 0.08
		var ground := Course.height_at(front)
		var surface := Water.surface_at(front)
		world.fx.splash(front, 1.6, maxf(surface, ground))
		world.fx.dust(Vector3(front.x, ground, front.z), 2, 2.0, Palette.SKY)
	for enemy in world.enemies.duplicate():
		if enemy.flying or enemy.dead or _hit.has(enemy):
			continue
		if Vector2(enemy.global_position.x - front.x, enemy.global_position.z - front.z).length() < WIDTH + enemy.radius:
			_hit[enemy] = SHOVE_TIME
			var blow := Hit.make(Hit.Kind.BLAST, DAMAGE, enemy.hit_center(), direction)
			blow.source = world.player if by_player else null
			enemy.take_hit(blow)
			if enemy is Enemy and (enemy as Enemy).can_stagger:
				(enemy as Enemy).stagger = maxf((enemy as Enemy).stagger, 1.0)
			if by_player:
				world.style_event("FLOODED", 60.0)
	for enemy: Entity in _hit.keys():
		if not is_instance_valid(enemy) or enemy.dead:
			_hit.erase(enemy)
			continue
		var left: float = _hit[enemy]
		enemy.global_position += direction * (SHOVE / SHOVE_TIME) * minf(delta, left)
		_hit[enemy] = left - delta
		if left - delta <= 0.0:
			_hit.erase(enemy)
	if _travelled >= LENGTH:
		queue_free()
