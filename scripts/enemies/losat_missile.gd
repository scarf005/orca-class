class_name LosatMissile
extends Projectile
## A kinetic dart: closing inside the booster distance denies it its striking energy.

const MIN_RANGE := 25.0
const LAUNCH_SPEED := 70.0
const MAX_SPEED := 700.0
const DAMAGE := 110.0
const CIWS_RANGE := 9.0


func _init() -> void:
	team = Entity.Team.ENEMY
	shape = "rocket"
	color = Palette.HOT
	life = 3.0
	intercept_hp = 0.04
	trail = ROCKET_SMOKE
	hit = Hit.make(Hit.Kind.SHELL, 0.0, Vector3.ZERO)
	hit.caliber = 80
	hit.weapon = "losat"


func _ready() -> void:
	super()
	var visuals := World.projectile_visual(shape, color, true)
	for mesh in visuals:
		add_child(mesh)
	core = visuals[0]
	halo = visuals[1]
	_update_interception()


func _update_interception() -> void:
	var tank := World.current.player
	interceptable = tank != null and global_position.distance_to(tank.global_position) <= CIWS_RANGE


func step(delta: float) -> void:
	# Short sweeps keep acceleration and the 25 m booster boundary fair at low frame rates.
	var left := delta
	while left > 0.00001 and not is_queued_for_deletion():
		var dt := minf(left, 1.0 / 240.0)
		var acceleration := 90.0 if _traveled < MIN_RANGE else 2500.0
		velocity = velocity.normalized() * minf(velocity.length() + acceleration * dt, MAX_SPEED)
		super(dt)
		left -= dt
	_update_interception()


func _apply(target: Entity, point: Vector3) -> Hit:
	hit.damage = DAMAGE * pow(velocity.length() / MAX_SPEED, 2.0)
	return super(target, point)


func laser(amount: float) -> bool:
	_update_interception()
	return super(amount) if interceptable else false
