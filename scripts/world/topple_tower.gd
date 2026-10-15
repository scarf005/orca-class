class_name ToppleTower
extends Node3D
## The ruined tower that comes down across the canyon. It groans and sheds dust, leaning a little further, then
## topples toward the oncoming tank and lands on its rubble heap as a slab (Stage2's second launch ramp): its far
## face is the slab's top, flush with the ramp's track.

const GROAN := 1.8 ## Seconds of telegraph before it goes.
const FALL := 1.2

var _tower: Node3D
var _hinge := Vector3.ZERO ## The edge of its base the tower turns about, on the rubble heap.
var _final := 0.0 ## How far it turns: past horizontal by the ramp's slope.
var _time := 0.0
var _landed := false


func _ready() -> void:
	var ramp: Dictionary = Stage2.RAMPS[Stage2.SLAB]
	var lip := Stage2.ramp_lip(Stage2.SLAB)
	var size := Stage2.SLAB_SIZE
	_hinge = Course.ground_at(lip, float(ramp.u)) + Vector3.UP * 0.1
	_final = PI * 0.5 + atan2(float(ramp.height), float(ramp.length))
	_tower = MeshInstance3D.new()
	(_tower as MeshInstance3D).mesh = CityKit.tower(Vector3(size.x, size.y, size.z), Stage2.SLAB_VARIANT)
	add_child(_tower)
	_pose(0.0)
	# The standing tower gives way to this animated one in the same frame.
	World.current.director.scenery.remove_structure("city_building", lip - size.z * 0.5, float(ramp.u))
	Sfx.play("rubble", _hinge, 4.0, 0.45)


func _process(delta: float) -> void:
	if _landed:
		return
	_time += delta
	var fx := World.current.fx
	if _time < GROAN:
		var tremble := sin(_time * 38.0) * 0.012 * (_time / GROAN)
		_pose(0.05 * smoothstep(0.0, GROAN, _time) + tremble)
		if fmod(_time, 0.3) < delta:
			fx.dust(_hinge, 6, 5.0, Palette.STONE)
			fx.debris(_hinge + Vector3.UP * 20.0, 3, [Fx.Debris.CONCRETE, Fx.Debris.GLASS], 3.0, 0.5)
			Sfx.play("rubble", _hinge, -2.0, 0.5 + _time * 0.15)
		World.current.shake(0.05, _hinge)
		return
	var t := clampf((_time - GROAN) / FALL, 0.0, 1.0)
	_pose(lerpf(0.05, _final, t * t))
	if fmod(_time, 0.1) < delta:
		fx.dust(_hinge, 8, 6.0, Palette.STONE)
	if t >= 1.0:
		_land()


func _land() -> void:
	_landed = true
	_pose(_final)
	var world := World.current
	var tip := Course.ground_at(float(Stage2.RAMPS[Stage2.SLAB].d), float(Stage2.RAMPS[Stage2.SLAB].u)) + Vector3.UP * 0.5
	world.fx.dust(tip, 40, 10.0, Palette.STONE)
	world.fx.debris(tip, 24, [Fx.Debris.CONCRETE, Fx.Debris.GLASS], 10.0, 0.7)
	world.fx.shockwave(tip, 18.0, Palette.CREAM, 0.5)
	world.shake(0.9, tip)
	Sfx.play("blast", tip, 4.0, 0.6)
	Sfx.play("rubble", tip, 4.0, 0.5)


## Turns the tower `angle` radians about its hinge, from upright toward the oncoming tank.
func _pose(angle: float) -> void:
	var yaw := Basis(Vector3.UP, Course.yaw_at(Stage2.ramp_lip(Stage2.SLAB)))
	var basis := yaw * Basis(Vector3.RIGHT, angle)
	_tower.global_transform = Transform3D(basis, _hinge + basis * Vector3(0.0, 0.0, Stage2.SLAB_SIZE.z * 0.5))
