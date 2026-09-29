class_name DragonBreath
extends Node
## Dragon's breath: a jet of burning magnesium pouring out of the muzzle for a third of a second. It
## flies 60 m in a cone that widens to 11 degrees, every flame trailing fire, with an incendiary
## blast at 20 m and another at 40 m. Whatever is inside the cone when it leaves catches fire.

const DURATION := 0.35 ## Emission time.
const RANGE := 60.0
const FLAMES := 44
const HALF_ANGLE := deg_to_rad(11.0)
const SPEED := Vector2(70.0, 95.0)
const MEAN_SPEED := (SPEED.x + SPEED.y) * 0.5
const FLAME_DAMAGE := 60.0
const SCORCH_DAMAGE := 1.0 ## Enough to set alight, so flyers in the cone burn even when no flame lands on them.
const BLASTS := [20.0, 40.0]
const BLAST_RADIUS := 6.0
const BLAST_DAMAGE := 220.0
const HEAT: Array[Color] = [Palette.WHITE, Palette.PEACH, Palette.BUTTER, Palette.AMBER]

var tank: Tank
var direction := Vector3.FORWARD
var origin := Vector3.INF ## Fixed muzzle position, or INF to follow the tank's muzzle as it moves.
var _time := 0.0
var _emitted := 0
var _blasts := 0
var _scorched: Array[Entity] = []


static func fire(shooter: Tank, dir: Vector3, from := Vector3.INF) -> DragonBreath:
	var breath := DragonBreath.new()
	breath.tank = shooter
	breath.direction = dir.normalized()
	breath.origin = from
	World.current.add_child(breath)
	World.current.fx.light_flash(breath._muzzle() + breath.direction * 10.0, 26.0, Palette.AMBER, 40.0)
	return breath


func _muzzle() -> Vector3:
	return tank.model.muzzle.global_position if origin == Vector3.INF else origin


func _process(delta: float) -> void:
	if not is_instance_valid(tank):
		queue_free()
		return
	var world := World.current
	var from := _muzzle()
	_time += delta
	var due := ceili(FLAMES * minf(_time / DURATION, 1.0))
	while _emitted < due:
		_emit(from, _emitted)
		_emitted += 1
	if _time <= DURATION:
		_scorch(from)
		var reach := randf_range(6.0, 30.0)
		world.fx.spawn(Fx.Kind.GLOW, from + direction * reach + Vector3.UP * (1.0 + reach * 0.08), direction * 10.0 + Vector3.UP * 4.0, randf_range(1.0, 1.8), 1.2 + reach * 0.04, [Palette.INK, Palette.DUSK, Palette.SLATE][randi() % 3], {"end_size": 4.0, "drag": 1.5, "fade": 0.3})
	# Each blast goes off as the head of the jet gets there.
	while _blasts < BLASTS.size() and _time >= BLASTS[_blasts] / MEAN_SPEED:
		var burst := Hit.make(Hit.Kind.BLAST, 0.0, from)
		burst.source = tank
		burst.stagger = 1.0
		burst.incendiary = true
		world.blast(from + direction * BLASTS[_blasts], BLAST_RADIUS, BLAST_DAMAGE, Entity.Team.PLAYER, burst, null, [Palette.WHITE, Palette.BUTTER, Palette.AMBER, Palette.HOT], direction)
		_blasts += 1
	if _time >= DURATION and _blasts >= BLASTS.size():
		queue_free()


func _emit(from: Vector3, index: int) -> void:
	var side := direction.cross(Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT).normalized()
	var up := side.cross(direction)
	var offset := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * tan(HALF_ANGLE)
	var dir := (direction + side * offset.x + up * offset.y).normalized()
	var speed := randf_range(SPEED.x, SPEED.y)
	var flame := World.current.spawn_projectile(Entity.Team.PLAYER, from, dir * speed, "fire", HEAT[index % HEAT.size()])
	flame.hit = Hit.make(Hit.Kind.FIRE, FLAME_DAMAGE, from, dir)
	flame.hit.source = tank
	flame.hit.incendiary = true
	flame.gravity = 6.0
	flame.life = RANGE / speed
	flame.radius = 0.9
	flame.flame_trail = true
	flame.impacted.connect(FireZone.on_flame_impact)


## Enemies inside the cone, flyers included, catch fire the moment the jet leaves the muzzle.
func _scorch(from: Vector3) -> void:
	for enemy: Entity in World.current.enemies.duplicate():
		if enemy.dead or enemy in _scorched:
			continue
		var to := enemy.hit_center() - from
		var distance := to.length()
		if distance - enemy.radius > RANGE or direction.angle_to(to) > HALF_ANGLE + asin(minf(enemy.radius / maxf(distance, 0.01), 1.0)):
			continue
		_scorched.append(enemy)
		var burn := Hit.make(Hit.Kind.FIRE, SCORCH_DAMAGE, enemy.hit_center(), direction)
		burn.incendiary = true
		burn.source = tank
		enemy.take_hit(burn)
