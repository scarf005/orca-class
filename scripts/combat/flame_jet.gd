class_name FlameJet
extends Node3D
## A short-range flame jet streaming from an enemy's muzzle along its bore. It follows the muzzle while it lasts,
## burns the tank inside its cone (Hit.Kind.FIRE), scorches props along it and sets the ground it licks alight in
## a hostile FireZone. It ends when its time runs out or the owner dies, staggers or is interrupted.

const TICK := 0.2 ## Seconds between burns.
const TANK_DAMAGE := 5.0 ## Per tick, before the tank's facing armor.
const SPEED := 55.0 ## m/s the flame stream travels at.
const CONE_START := 0.7 ## Metres wide (half) at the nozzle ...
const CONE_SPREAD := 0.12 ## ... and how much wider per metre of reach.
const PROP_DAMAGE := 15.0
const FALL_HEIGHT := 6.0 ## Fuel that ends its flight higher than this over the ground burns out in the air.

var reach := 30.0
var life := 1.5
var thickness := 1.0 ## Scales the cone and the flames: a fortress's jet is a wall of fire.
var burn := TANK_DAMAGE ## Per tick to the tank inside the cone.
var _owner: Enemy
var _muzzle: Node3D
var _tick := 0.0
var _puffs := 0.0


## Starts a jet of `time` seconds from `muzzle` that burns out to `jet_reach` metres.
static func start(owner: Enemy, muzzle: Node3D, time: float, jet_reach: float, jet_thickness := 1.0) -> FlameJet:
	var jet := FlameJet.new()
	jet._owner = owner
	jet._muzzle = muzzle
	jet.life = time
	jet.reach = jet_reach
	jet.thickness = jet_thickness
	World.current.add_child(jet)
	Sfx.play("launch", muzzle.global_position, 2.0, 0.55) # The rocket whoosh, pitched down, is the jet's roar.
	return jet


## Half width of the cone `along` metres out.
static func half_width(along: float, scale := 1.0) -> float:
	return (CONE_START + CONE_SPREAD * along) * scale


## How far along a jet from `origin` towards `dir` the point `target` lies when it is inside the cone, else -1.
static func along_cone(origin: Vector3, dir: Vector3, jet_reach: float, target: Vector3, target_radius: float, scale := 1.0) -> float:
	var along := (target - origin).dot(dir)
	if along < 0.0 or along > jet_reach + target_radius:
		return -1.0
	var off := (target - origin - dir * along).length()
	return along if off <= half_width(along, scale) + target_radius else -1.0


func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0 or not is_instance_valid(_owner) or _owner.dead or _owner.is_staggered() or not is_instance_valid(_muzzle):
		queue_free()
		return
	var world := World.current
	var origin := _muzzle.global_position
	var dir := -_muzzle.global_basis.z.normalized()
	_puffs += delta * 90.0 * thickness
	for i in mini(int(_puffs), 12 + int(thickness * 4.0)):
		var spread := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * CONE_SPREAD
		var color: Color = Fx.FIRE_COLORS[randi() % Fx.FIRE_COLORS.size()]
		world.fx.spawn(Fx.Kind.FLAME, origin + dir * 0.4, (dir + spread).normalized() * SPEED * randf_range(0.7, 1.0), reach / SPEED, CONE_START * 1.4 * thickness, color, {"end_size": CONE_START * 4.0 * thickness, "drag": 0.0, "fade": 0.5})
	_puffs = fmod(_puffs, 1.0)
	world.fx.light_flash(origin + dir * 3.0, 5.0, Palette.AMBER, 12.0)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	var tank := world.player
	if tank != null and not tank.dead:
		var along := along_cone(origin, dir, reach, tank.hit_center(), tank.radius * 0.6, thickness)
		if along >= 0.0:
			var burn := Hit.make(Hit.Kind.FIRE, burn, tank.hit_center(), dir)
			burn.source = _owner
			burn.weapon = "flame"
			tank.take_hit(burn)
	var landing := origin + dir * reach # Past a level bore's reach the burning fuel falls to the ground.
	for step in range(1, int(reach / 4.0) + 1):
		var point := origin + dir * (step * 4.0)
		for prop: Prop in world.props.in_radius(point, half_width(step * 4.0, thickness) + 1.0):
			if prop.burnable:
				var burn := Hit.make(Hit.Kind.FIRE, PROP_DAMAGE, point, dir)
				burn.weapon = "flame"
				prop.take_hit(burn)
		if point.y <= Course.height_at(point) + 0.6:
			landing = point
			break
	if landing.y - Course.height_at(landing) < FALL_HEIGHT:
		FireZone.ignite(Vector3(landing.x, Course.height_at(landing), landing.z), "flame", true)
