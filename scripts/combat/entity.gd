class_name Entity
extends Node3D
## Anything that can be hit: the player, enemies, destructible props.

signal died(entity: Entity)
signal damaged(entity: Entity, hit: Hit)

enum Team { PLAYER, ENEMY, NEUTRAL }

const FLASH_TIME := 0.07
const OVERKILL := 3.0 ## A killing hit this many times the full health shatters scenery and hurls wrecks.

static var _flash_material := _make_flash_material()
var rest_overlay: Material = null ## Overlay the meshes wear between hit flashes.

var team := Team.ENEMY
var max_hp := 10.0
var hp := 10.0
var radius := 1.0 ## Hit sphere radius around `hit_center()`.
var center_height := 0.0
var flying := false
var dead := false
var overkilled := false ## Killed by an overkill hit: scenery leaves no rubble, a wreck flies harder.
var interceptable := false ## The player's laser CIWS may target this.
var armor := 0.0 ## Fraction of small-caliber damage (below 20 mm) that is stopped.
var invulnerable := false
var always_tick := true ## False for scenery: it only processes while a hit flash is showing.
var _flash := 0.0
var _smoke_tick := 0.0
var _wet := false ## Standing in the reservoir.
var _wake_tick := 0.0
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
	var length_squared := d.length_squared()
	if length_squared < 0.00000001:
		return 0.0 if from.distance_to(center) <= r else -1.0
	var m := from - center
	var b := m.dot(d)
	var c := m.dot(m) - r * r
	if c <= 0.0:
		return 0.0
	if b > 0.0:
		return -1.0
	var disc := b * b - length_squared * c
	if disc < 0.0:
		return -1.0
	var fraction := (-b - sqrt(disc)) / length_squared
	return fraction * sqrt(length_squared) if fraction <= 1.0 else -1.0


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
		if hit.kind == Hit.Kind.BULLET and armor > 0.0 and World.current:
			World.current.fx.ricochet(hit, hit_center())
		return
	hp -= amount
	flash()
	damaged.emit(self, hit)
	on_damaged(hit, amount)
	if hp <= 0.0:
		overkilled = amount > max_hp * OVERKILL
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


## Parts the sight can lock onto one by one (a boss's modules): name -> [world position, hit
## radius, label]. Empty for anything that is a single piece.
func aim_parts() -> Dictionary:
	return {}


## [label, health 0..1] for each module, shown under the boss bar.
func module_states() -> Array:
	return []


## World-space box around everything the entity draws, so its shards match its size.
func visual_bounds() -> AABB:
	var box := AABB(hit_center(), Vector3.ZERO)
	for mesh in _meshes:
		if is_instance_valid(mesh) and mesh.is_inside_tree():
			box = box.merge(mesh.global_transform * mesh.get_aabb())
	return box


## A hurt machine smokes, and a badly hurt one burns, from all over its body: the worse the
## damage, the thicker, bigger and faster it pours out. `size` is roughly half the body's length.
func show_damage(delta: float, size: float) -> void:
	var hurt := 1.0 - hp / maxf(max_hp, 0.001)
	if hurt < 0.15:
		return
	_smoke_tick -= delta
	if _smoke_tick > 0.0:
		return
	_smoke_tick = lerpf(0.12, 0.03, hurt)
	var fx := World.current.fx
	var at := hit_center() + Vector3(randf_range(-1, 1), randf_range(0.0, 0.8), randf_range(-1, 1)) * size * 0.6
	var puff := (0.8 + size * 0.35) * (1.0 + hurt)
	fx.spawn(Fx.Kind.GLOW, at, Vector3(randf_range(-0.6, 0.6), randf_range(3.0, 5.0), randf_range(-0.6, 0.6)), randf_range(1.6, 2.6), puff, [Palette.INK, Palette.DUSK, Palette.SLATE, Palette.ASH][randi() % 4], {"end_size": puff * 4.0, "drag": 0.7, "fade": 0.3})
	if hurt > 0.4:
		for i in 2:
			var flame_at := at + Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * size * 0.3
			fx.spawn(Fx.Kind.FLAME, flame_at, Vector3(0, randf_range(3.0, 6.0), 0), randf_range(0.35, 0.7), puff * 0.9, [Palette.BUTTER, Palette.AMBER, Palette.CORAL, Palette.HOT][randi() % 4], {"drag": 1.0})


## Ground units in water: a splash as they drive in, then a bow wave while they move and
## ripples while they stand. `moving` is their velocity; `size` roughly half the body's length.
func wade(delta: float, moving: Vector3, size: float) -> void:
	var surface := -INF if flying else Water.surface_at(global_position)
	var wet := surface > global_position.y
	if wet and not _wet:
		World.current.fx.splash(global_position, size, surface)
		Sfx.play("squelch", global_position, -4.0, 0.6)
	_wet = wet
	if not wet:
		return
	_wake_tick -= delta
	if _wake_tick > 0.0:
		return
	_wake_tick = lerpf(0.3, 0.06, clampf(Vector2(moving.x, moving.z).length() / 20.0, 0.0, 1.0))
	World.current.fx.wake(global_position, moving, size, surface)


## Collects mesh instances so hit flashes can overlay them.
func track_meshes(root: Node) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D:
			_meshes.append(child)
		track_meshes(child)


func flash() -> void:
	_flash = FLASH_TIME
	set_process(true)
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = _flash_material


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			for mesh in _meshes:
				if is_instance_valid(mesh):
					mesh.material_overlay = rest_overlay
	if not always_tick:
		if _flash <= 0.0:
			set_process(false)
		return
	tick(delta)


## Per-frame behavior for subclasses; keeps hit flash handling in one place.
func tick(_delta: float) -> void:
	pass
