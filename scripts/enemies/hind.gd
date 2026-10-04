class_name Hind
extends Helicopter
## Low-flying city hunter: ducks behind cover, rises to sight, then ripples rockets or guides an ATGM.

enum Attack { GUN, ROCKETS, ATGM }

var attack := Attack.GUN
var _cover_wait := 0.0
var _tail_hp := 8.0
var _lids: Array[Node3D] = []
var _rails: Array[Node3D] = []


func build() -> void:
	super()
	_height = 7.0
	_attack_timer = 1.0
	# Retain the tandem airframe and five-bladed rotor, with a longer nose and outboard missile rails.
	model.get_child(0).scale = Vector3(0.9, 1.0, 1.12)
	var gun := LowPoly.new()
	for i in 4:
		var angle := TAU * i / 4.0
		gun.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(cos(angle) * 0.13, sin(angle) * 0.13, -0.2)), 0.045, 1.4, 5, Palette.INK)
	var barrels := MeshInstance3D.new()
	barrels.mesh = gun.mesh()
	_chin.add_child(barrels)
	for side in [-1.0, 1.0]:
		var rail := Node3D.new()
		rail.position = Vector3(side * 3.3, -0.2, 0.0)
		model.add_child(rail)
		var b := LowPoly.new()
		b.box(Transform3D(), Vector3(0.18, 0.15, 2.4), Palette.STONE)
		for x in [-0.22, 0.22]:
			b.tube(Transform3D(Basis(Vector3.UP, PI), Vector3(x, -0.15, 0.8)), 0.1, 2.0, 6, Palette.MOSS)
		var mesh := MeshInstance3D.new()
		mesh.mesh = b.mesh()
		rail.add_child(mesh)
		_rails.append(rail)
	for pod in _pods:
		var lid := Node3D.new()
		lid.position = Vector3(0, 0.42, -1.02)
		pod.add_child(lid)
		var b := LowPoly.new()
		b.box(Transform3D(Basis(), Vector3(0, -0.42, 0)), Vector3(0.86, 0.84, 0.06), Palette.DUSK)
		var mesh := MeshInstance3D.new()
		mesh.mesh = b.mesh()
		lid.add_child(mesh)
		_lids.append(lid)


func behave(delta: float) -> void:
	var tank := player()
	if tank == null or tank.dead:
		return
	var cover := CityCover.blocker(_chin_muzzle.global_position, tank.hit_center())
	if cover != null:
		_telegraph = 0.0
		_burst = 0
		_cover_wait += delta
		_height = 7.0 if _cover_wait < 0.7 else maxf(7.0, cover.global_position.y + cover.height + 8.0 - Course.height_at(global_position))
		_attack_timer = maxf(_attack_timer, 0.15)
	else:
		_cover_wait = 0.0
		if _burst == 0 and _telegraph <= 0.0 and _attack_timer > 0.6:
			_height = 7.0
	var shelter := global_position
	if _burst == 0 and _telegraph <= 0.0 and _attack_timer > 0.6:
		shelter = CityCover.shelter(global_position, tank.hit_center())
	var seeking := shelter != global_position
	var had_burst := _burst > 0
	super(delta)
	if seeking and _attack_timer > 0.6 and _telegraph <= 0.0 and _burst == 0:
		global_position = global_position.move_toward(shelter, delta * 16.0)
	if had_burst and _burst == 0:
		_attack_timer = 1.5
	for lid in _lids:
		lid.rotation.x = lerpf(lid.rotation.x, -1.7 if attack == Attack.ROCKETS and (_telegraph > 0.0 or _burst > 0) else 0.0, minf(delta * 12.0, 1.0))
	for rail in _rails:
		aim_barrel(rail, tank.hit_center(), BARREL_SLEW, delta)


func _next_attack() -> void:
	attack = (attack + 1) % Attack.size() as Attack
	_rockets = attack == Attack.ROCKETS
	_salvo = _rockets
	_strafing = false


func _fire(tank: Tank) -> void:
	if CityCover.blocker(_chin_muzzle.global_position, tank.hit_center()) != null:
		_burst = 1
		return
	if attack == Attack.ATGM:
		var rail := _rails[0]
		var missile := fire_along("atgm", rail, 32.0, 0.0, Palette.HOT, tank.hit_center() - rail.global_position)
		missile.hit.kind = Hit.Kind.SHELL
		missile.hit.warhead = true
		missile.blast_radius = 2.8
		missile.blast_damage = 30.0
		missile.homing_target = tank
		missile.turn_rate = 1.6
		missile.interceptable = true
		missile.intercept_hp = 1.0
		missile.life = 7.0
		missile.trail = Projectile.ROCKET_SMOKE
		_burst = 1
		Sfx.play("launch", rail.global_position)
	else:
		var fixed := _rocket_aim
		if _rockets:
			_rocket_aim += Course.right(Course.to_course(tank.global_position).x) * ((_burst - 3.5) * 2.4)
		super(tank)
		_rocket_aim = fixed


func take_hit(hit: Hit) -> void:
	if hit.kind == Hit.Kind.BULLET and not dead and hit.position.distance_to(_tail_rotor.global_position) < 1.2:
		_tail_hp -= hit.damage
		if _tail_hp <= 0.0:
			die(hit)
			return
	super(hit)
