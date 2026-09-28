class_name Hazard
extends Node3D
## A lingering spore cloud that hurts the player while inside it.

var radius := 3.5
var life := 2.5
var damage_per_second := 8.0
var _tick := 0.0


static func spawn(position: Vector3, radius_value: float, life_value: float, dps: float) -> Hazard:
	var hazard := Hazard.new()
	hazard.radius = radius_value
	hazard.life = life_value
	hazard.damage_per_second = dps
	World.current.add_child(hazard)
	hazard.global_position = position
	return hazard


func _process(delta: float) -> void:
	var world := World.current
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.15
	world.fx.spores(global_position + Vector3.UP * 0.8, 3, radius * 0.7)
	var player := world.player
	if player and not player.dead and player.hit_center().distance_to(global_position) < radius + player.radius * 0.5:
		var hit := Hit.make(Hit.Kind.SPORE, damage_per_second * 0.15, player.hit_center(), (player.global_position - global_position).normalized())
		player.take_hit(hit)
