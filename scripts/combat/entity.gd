class_name Entity
extends Node3D
## Anything that can be hit: the player, enemies, destructible props.

signal died(entity: Entity)
signal damaged(entity: Entity, hit: Hit)

enum Team { PLAYER, ENEMY, NEUTRAL }

const FLASH_TIME := 0.07

static var _flash_material := _make_flash_material()

var team := Team.ENEMY
var max_hp := 10.0
var hp := 10.0
var radius := 1.0 ## Hit sphere radius around `hit_center()`.
var center_height := 0.0
var flying := false
var dead := false
var interceptable := false ## The player's laser CIWS may target this.
var armor := 0.0 ## Fraction of small-caliber damage (below 20 mm) that is stopped.
var invulnerable := false
var _flash := 0.0
var _meshes: Array[GeometryInstance3D] = []


static func _make_flash_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Palette.WHITE
	return material


func _enter_tree() -> void:
	if World.current:
		World.current.register(self)


func _exit_tree() -> void:
	if World.current:
		World.current.unregister(self)


func hit_center() -> Vector3:
	return global_position + Vector3.UP * center_height


## Returns the distance along the segment where it first touches this entity, or -1.
func hit_test(from: Vector3, to: Vector3, extra_radius := 0.0) -> float:
	return segment_sphere(from, to, hit_center(), radius + extra_radius)


static func segment_sphere(from: Vector3, to: Vector3, center: Vector3, r: float) -> float:
	var d := to - from
	var length := d.length()
	if length < 0.0001:
		return 0.0 if from.distance_to(center) <= r else -1.0
	var dir := d / length
	var m := from - center
	var b := m.dot(dir)
	var c := m.dot(m) - r * r
	if c <= 0.0:
		return 0.0
	if b > 0.0:
		return -1.0
	var disc := b * b - c
	if disc < 0.0:
		return -1.0
	var t := -b - sqrt(disc)
	return t if t <= length else -1.0


func damage_multiplier(hit: Hit) -> float:
	# Armor stops rifle-caliber rounds outright and half as much of heavy machine gun rounds.
	if hit.kind == Hit.Kind.BULLET and hit.caliber < 20 and not hit.pierce:
		return 1.0 - armor * (1.0 if hit.caliber < 12 else 0.5)
	return 1.0


func take_hit(hit: Hit) -> void:
	if dead or invulnerable:
		return
	var amount := hit.damage * damage_multiplier(hit)
	if amount <= 0.0:
		return
	hp -= amount
	flash()
	damaged.emit(self, hit)
	on_damaged(hit, amount)
	if hp <= 0.0:
		die(hit)


func die(hit: Hit) -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	on_death(hit)
	died.emit(self)
	if World.current:
		World.current.unregister(self)
	queue_free()


func on_damaged(_hit: Hit, _amount: float) -> void:
	pass


func on_death(_hit: Hit) -> void:
	pass


## Collects mesh instances so hit flashes can overlay them.
func track_meshes(root: Node) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D:
			_meshes.append(child)
		track_meshes(child)


func flash() -> void:
	_flash = FLASH_TIME
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = _flash_material


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			for mesh in _meshes:
				if is_instance_valid(mesh):
					mesh.material_overlay = null
	tick(delta)


## Per-frame behavior for subclasses; keeps hit flash handling in one place.
func tick(_delta: float) -> void:
	pass
