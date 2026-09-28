class_name Hit
extends RefCounted
## One instance of damage. Receivers scale `damage` by their own armor and weaknesses.

enum Kind { BULLET, SHELL, BLAST, FIRE, RAM, TAIL, LASER, SPORE, THROWN, FRAGMENT }

var damage := 0.0
var kind := Kind.BULLET
var caliber := 0 ## Millimeters; small calibers are stopped by armor.
var position := Vector3.ZERO
var direction := Vector3.FORWARD
var source: Node3D
var pierce := false ## Ignores armor (HEAT, APFSDS).
var incendiary := false
var stagger := 0.0 ## Seconds of stagger inflicted on enemies that can be staggered.
var warhead := false ## Shaped charge (FPV, ATGM): stopped by ERA, lethal where there is none.


static func make(kind_value: Kind, damage_value: float, position_value: Vector3, direction_value := Vector3.FORWARD) -> Hit:
	var hit := Hit.new()
	hit.kind = kind_value
	hit.damage = damage_value
	hit.position = position_value
	hit.direction = direction_value
	return hit


func copy() -> Hit:
	var hit := Hit.new()
	hit.damage = damage
	hit.kind = kind
	hit.caliber = caliber
	hit.position = position
	hit.direction = direction
	hit.source = source if is_instance_valid(source) else null
	hit.pierce = pierce
	hit.incendiary = incendiary
	hit.stagger = stagger
	hit.warhead = warhead
	return hit
