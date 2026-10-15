class_name TidalSurge
extends Node3D
## A wave out of the bay. A white line of foam races in across the water from the bay side and, once it reaches the
## street, sweeps over the low ground in front of the tank: there it shoves the hull sideways and holds the rail back.
## Raised rubble and kerb, a leap, and a drift (its dash is invulnerable) all let it pass.

const SPEED := 34.0 ## Metres per second the front travels across the street.
const START := -110.0 ## Where the front begins, out on the bay water (u).
const BODY := 18.0 ## How far behind the front the water stays high.
const LENGTH := 80.0 ## Metres of street it washes over.
const SAFE := 0.9 ## Ground higher than this stays dry.
const PUSH := 12.0 ## Sideways speed (m/s) it sweeps the hull along.
const UNDERTOW := 0.6 ## Share of the rail's speed it holds back.
const CREST := 2.4

var d := 0.0 ## Centre of the stretch it washes over (rail distance).
var front := START ## Lateral position of its leading edge.
var hitting := false
var _struck := false


## Seconds the foam line is in sight before it reaches the street's left edge.
static func warning(street_half: float) -> float:
	return (-START - street_half) / SPEED


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _mesh()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	_place()
	var world := World.current
	world.director.incoming.emit(global_position)
	Sfx.play("roar", global_position, 3.0, 0.5)


func _process(delta: float) -> void:
	front += SPEED * delta
	_place()
	var world := World.current
	var tank := world.player
	var c := Course.to_course(tank.global_position)
	var wet := absf(c.x - d) < LENGTH * 0.5 and c.y <= front and c.y >= front - BODY
	hitting = wet and not tank.dead and not tank.airborne and tank.invuln <= 0.0 and Course.height(c.x, c.y) < SAFE
	tank.flow = PUSH if hitting else 0.0
	world.rail.undertow = UNDERTOW if hitting else 0.0
	if hitting:
		if not _struck:
			_struck = true
			world.shake(0.5)
			Sfx.play("impact", tank.global_position, 2.0, 0.6)
		world.fx.splash(tank.global_position, 2.0, Stage2.WATER_LEVEL, false)
	if front - BODY > Course.stage.lateral_limit(d) + 12.0:
		queue_free()


func _exit_tree() -> void:
	var world := World.current
	if world != null and world.player != null:
		world.player.flow = 0.0
		world.rail.undertow = 0.0


func _place() -> void:
	global_position = Course.to_world(d, front, Stage2.WATER_LEVEL)
	rotation.y = Course.yaw_at(d)


## The wave in its own frame: +x is the way it travels, the crest at x = 0, a foam apron ahead and a long back.
func _mesh() -> Mesh:
	var b := LowPoly.new()
	var step := 4.0
	var z := -LENGTH * 0.5
	var back := Palette.SKY.lerp(Palette.MINT, 0.4)
	while z < LENGTH * 0.5:
		var rise := CREST * (0.75 + 0.25 * sin(z * 0.41)) # A ragged crest.
		var lean := 1.2 * sin(z * 0.23 + 1.0)
		var a := Vector3(1.5 + lean, 0.08, z)
		var a2 := Vector3(1.5 + lean, 0.08, z + step)
		var top := Vector3(0.0, rise, z)
		var top2 := Vector3(0.0, rise * (0.75 + 0.25 * sin((z + step) * 0.41)) / (0.75 + 0.25 * sin(z * 0.41)), z + step)
		var tail := Vector3(-BODY, 0.2, z)
		var tail2 := Vector3(-BODY, 0.2, z + step)
		b.quad(a, a2, top2, top, Palette.WHITE, Vector3(1, 0.4, 0))
		b.quad(top, top2, tail2, tail, back, Vector3(-0.2, 1, 0))
		# The foam apron on the water ahead of the crest: the line that gives the wave away.
		var apron := Vector3(4.5 + lean * 2.0, 0.1, z)
		var apron2 := Vector3(4.5 + lean * 2.0, 0.1, z + step)
		b.quad(apron, apron2, a2, a, Palette.CREAM, Vector3.UP)
		z += step
	return b.mesh()
