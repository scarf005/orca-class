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
	model.scale = Vector3.ONE * 1.35
	# The parent builds the nodes (rotor, tail rotor, chin, pods); this gunship dresses them in its own airframe.
	(model.get_child(0) as MeshInstance3D).mesh = _airframe()
	(_rotor.get_child(0) as MeshInstance3D).mesh = _rotor_mesh()
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


static func _xf(pos: Vector3, yaw := 0.0, pitch := 0.0, roll := 0.0) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(pitch, yaw, roll)), pos)


## Mi-24-style Hind: a bulbous tandem canopy over a boxy troop cabin, intakes on the shoulders, a long
## tapering boom and a red-starred fin, in a three-tone green camouflage over a pale belly.
func _airframe() -> Mesh:
	var b := LowPoly.new()
	var dark := Palette.PINE
	var mid := Palette.SAGE
	var light := Palette.LEAF
	b.box(_xf(Vector3(0, 0.15, 0.6)), Vector3(2.2, 1.9, 4.3), mid, light)
	b.box(_xf(Vector3(0, -0.8, 0.5)), Vector3(1.9, 0.16, 4.1), Palette.ASH)
	b.box(_xf(Vector3(0, -0.05, -2.3), 0, 0.14), Vector3(1.75, 1.35, 2.7), dark, mid)
	b.box(_xf(Vector3(0, -0.3, -3.7), 0, 0.2), Vector3(1.0, 0.85, 1.4), dark)
	b.glow = true
	b.box(_xf(Vector3(0, -0.5, -4.45)), Vector3(0.5, 0.3, 0.12), Palette.CYAN)
	b.blob(_xf(Vector3(0, 0.5, -3.0)), 0.75, Palette.SKY, 0, 0.0, 1)
	b.blob(_xf(Vector3(0, 1.2, -1.15)), 0.82, Palette.SKY, 0, 0.0, 2)
	b.glow = false
	for z in [-3.0, -1.15]:
		b.box(_xf(Vector3(0, 0.55 if z < -2.0 else 1.25, z)), Vector3(0.12, 1.3, 0.12), Palette.INK)
	b.box(_xf(Vector3(0, 0.8, -2.05), 0, 0.0), Vector3(1.4, 0.3, 0.3), dark)
	for side in [-1.0, 1.0]:
		b.box(_xf(Vector3(side * 0.88, 1.35, 0.35)), Vector3(0.85, 0.75, 1.7), light, mid)
		b.box(_xf(Vector3(side * 0.88, 1.35, -0.52)), Vector3(0.7, 0.58, 0.06), Palette.INK)
		b.tube(_xf(Vector3(side * 0.9, 1.3, 1.2)), 0.26, 1.2, 8, Palette.DUSK, 0.32)
		b.box(_xf(Vector3(side * 1.12, 0.2, 0.6)), Vector3(0.05, 1.0, 1.0), light)
		b.box(_xf(Vector3(side * 1.12, 0.35, 1.9)), Vector3(0.05, 0.6, 0.9), dark)
		b.box(_xf(Vector3(side * 1.13, 0.1, -0.6)), Vector3(0.04, 1.1, 0.04), Palette.INK)
		b.box(_xf(Vector3(side * 1.5, -0.7, 0.5)), Vector3(0.6, 0.6, 1.3), Palette.DUSK)
		b.prism(_xf(Vector3(side * 1.55, -1.25, 0.5), 0, 0, PI * 0.5), 0.38, 0.35, 8, Palette.INK)
		b.prism(_xf(Vector3(side * 1.45, -1.25, 0.5)), 0.04, 0.8, 4, Palette.ASH)
		b.box(_xf(Vector3(side * 2.8, 0.1, 0.5), 0, 0, side * -0.06), Vector3(3.5, 0.15, 1.15), Palette.ASH, light)
		b.box(_xf(Vector3(side * 4.55, 0.12, 0.5)), Vector3(0.3, 0.18, 1.15), Palette.CORAL)
	b.box(_xf(Vector3(0, 1.8, 0.4)), Vector3(0.9, 0.5, 1.4), dark)
	b.box(_xf(Vector3(0, 0.55, 4.6)), Vector3(0.95, 0.95, 3.4), mid)
	b.box(_xf(Vector3(0, 0.7, 6.9)), Vector3(0.6, 0.65, 2.0), dark)
	b.box(_xf(Vector3(0, 1.75, 7.45), 0, -0.28), Vector3(0.2, 2.5, 1.5), mid)
	b.box(_xf(Vector3(0, 0.8, 7.0)), Vector3(2.6, 0.08, 0.8), dark)
	b.box(_xf(Vector3(0, 2.9, 7.75), 0, -0.28), Vector3(0.22, 0.2, 0.7), Palette.INK)
	# Red stars on the fin: five thin arms.
	for i in 5:
		for side in [-1.0, 1.0]:
			b.box(Transform3D(Basis(Vector3.RIGHT, TAU * i / 5.0 * 0.5 + 0.2), Vector3(side * 0.12, 1.7, 7.55)), Vector3(0.03, 0.18, 0.95), Palette.RED)
	b.box(_xf(Vector3(0, 1.9, 0.2)), Vector3(0.4, 0.5, 0.4), Palette.INK)
	return b.mesh()


func _rotor_mesh() -> Mesh:
	var r := LowPoly.new()
	r.prism(_xf(Vector3(0, -0.12, 0)), 0.34, 0.45, 8, Palette.INK)
	for i in 5:
		var xf := Transform3D(Basis(Vector3.UP, TAU * i / 5.0 + 0.3), Vector3.ZERO)
		r.box(xf.translated_local(Vector3(3.75, 0, 0)), Vector3(7.5, 0.06, 0.5), Palette.INK)
		r.box(xf.translated_local(Vector3(7.0, 0.01, 0)), Vector3(0.9, 0.08, 0.52), Palette.BUTTER)
	return r.mesh()


func _pod_mesh() -> Mesh:
	var b := LowPoly.new()
	b.box(_xf(Vector3(0, 0.55, 0.7)), Vector3(0.14, 0.5, 1.4), Palette.DUSK)
	b.tube(_xf(Vector3(0, 0, 1.1), PI), 0.46, 2.2, 8, Palette.SAGE)
	b.tube(_xf(Vector3(0, 0, -1.1), PI), 0.46, 0.3, 8, Palette.DUSK)
	b.glow = true
	for i in 7:
		var angle := TAU * i / 7.0
		var ring := 0.26 if i < 6 else 0.0
		b.box(_xf(Vector3(cos(angle) * ring, sin(angle) * ring, -1.42)), Vector3(0.13, 0.13, 0.02), Palette.CORAL)
	return b.mesh()


func behave(delta: float) -> void:
	var tank := player()
	if tank == null or tank.dead:
		return
	if Course.stage is Stage2:
		_height = 5.0
		var t := Course.to_course(tank.global_position)
		var c := Course.to_course(global_position)
		var blocked := BipedMech.line_blocked(World.current.camera.global_position, hit_center()) or BipedMech.line_blocked(_chin_muzzle.global_position, tank.hit_center())
		if blocked or c.x - t.x < 40.0 or c.x - t.x > 120.0:
			_telegraph = 0.0
			_burst = 0
			_lane = -8.0 if c.y > 0.0 else 8.0
			var goal := Course.to_world(t.x + 85.0, _lane, maxf(tank.global_position.y, Stage2.WATER_LEVEL) + 5.0)
			global_position = global_position.move_toward(goal, delta * (World.current.rail.speed + 24.0))
		else:
			_lane = clampf(_lane, -12.0, 12.0)
			super(delta)
		global_position.y = minf(global_position.y, maxf(tank.global_position.y, Stage2.WATER_LEVEL) + 6.0)
		for lid in _lids:
			lid.rotation.x = lerpf(lid.rotation.x, -1.7 if attack == Attack.ROCKETS and (_telegraph > 0.0 or _burst > 0) else 0.0, minf(delta * 12.0, 1.0))
		for rail in _rails:
			aim_barrel(rail, tank.hit_center(), BARREL_SLEW, delta)
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
