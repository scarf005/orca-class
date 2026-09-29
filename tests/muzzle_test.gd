extends TestCase
## Enemy muzzle blasts scale with the weapon: light guns a big flash and puff, autocannons add a cone
## of fire, heavy launches a star flash, thick smoke, backblast and ground dust; particle use stays bounded.


## Runs `blast` and returns {flash: largest flash scale, particles: new particles, transients: new effect nodes}.
func _measure(world: World, blast: Callable) -> Dictionary:
	var fx := world.fx
	var particles := fx.particle_count()
	var transients := fx._transients.size()
	blast.call()
	var flash := 0.0
	for i in range(transients, fx._transients.size()):
		flash = maxf(flash, (fx._transients[i].node as Node3D).scale.x)
	return {"flash": flash, "particles": fx.particle_count() - particles, "transients": fx._transients.size() - transients}


func test_heavier_weapons_blast_bigger() -> void:
	var world := stage("", false)
	var enemy := Enemy.new()
	world.add_enemy(enemy)
	var high := Vector3(0, 40, 0) + world.player.global_position + Vector3(0, 0, -30)
	var light := _measure(world, func() -> void: enemy.muzzle_blast(high, Vector3.FORWARD, Enemy.Muzzle.LIGHT))
	var auto := _measure(world, func() -> void: enemy.muzzle_blast(high, Vector3.FORWARD, Enemy.Muzzle.AUTO))
	var heavy := _measure(world, func() -> void: enemy.muzzle_blast(high, Vector3.FORWARD, Enemy.Muzzle.HEAVY, "mortar"))
	var launcher := _measure(world, func() -> void: enemy.muzzle_blast(high, Vector3.FORWARD, Enemy.Muzzle.HEAVY, "rocket"))
	check(light.flash >= 1.8 - 0.01, "a light gun's flash is twice the old 0.9 (%.2f)" % light.flash)
	check(auto.flash >= 1.8 - 0.01, "an autocannon's too (%.2f)" % auto.flash)
	check(heavy.flash >= 3.7, "a heavy launch's is 2.5 times the old 1.5 (%.2f)" % heavy.flash)
	check(auto.particles > light.particles, "the autocannon adds a cone of fire (%d vs %d)" % [auto.particles, light.particles])
	check(heavy.particles > auto.particles, "a heavy launch throws a thicker smoke cloud (%d vs %d)" % [heavy.particles, auto.particles])
	check(heavy.transients > light.transients, "with a star flash on top of the flash (%d vs %d)" % [heavy.transients, light.transients])
	check(launcher.particles > heavy.particles, "a rocket or ATGM tube also blows backblast (%d vs %d)" % [launcher.particles, heavy.particles])
	check(launcher.transients > heavy.transients, "and flashes backwards")


func test_heavy_launch_near_the_ground_kicks_up_dust() -> void:
	var world := stage("", false)
	var enemy := Enemy.new()
	world.add_enemy(enemy)
	var at := world.player.global_position + Vector3(0, 0, -30)
	at.y = Course.height_at(at) + 1.0
	var low := _measure(world, func() -> void: enemy.muzzle_blast(at, Vector3.FORWARD, Enemy.Muzzle.HEAVY, "mortar"))
	var up := _measure(world, func() -> void: enemy.muzzle_blast(at + Vector3.UP * 30.0, Vector3.FORWARD, Enemy.Muzzle.HEAVY, "mortar"))
	check(low.particles > up.particles, "a muzzle near the ground raises dust (%d vs %d)" % [low.particles, up.particles])


func test_fire_at_derives_the_class_from_the_shot() -> void:
	var world := stage("", false)
	var enemy := Enemy.new()
	world.add_enemy(enemy)
	var from := world.player.global_position + Vector3(0, 40, -30)
	var bullet := _measure(world, func() -> void: enemy.fire_at("orb", from, from + Vector3.FORWARD, 100.0, 1.0))
	var rocket := _measure(world, func() -> void: enemy.fire_at("rocket", from, from + Vector3.FORWARD, 50.0, 0.0))
	check(rocket.flash > bullet.flash and rocket.particles > bullet.particles, "a rocket blasts bigger than a bullet")


func test_gunship_rocket_volley_stays_within_the_particle_budget() -> void:
	var world := stage("boss")
	world.director._start_boss({"kind": "gunship"})
	var boss := world.boss as Gunship
	boss._next_attack = 1000.0
	boss.phase = Gunship.Phase.INFECTED
	boss._attack = Gunship.Attack.ROCKETS
	boss._attack_time = 0.0
	var peak := 0
	for _i in 240:
		await get_tree().process_frame
		peak = maxi(peak, world.fx.particle_count())
	print("PEAK gunship infected rocket volley particles: ", peak)
	check(peak < Fx.MAX_PARTICLES * 0.8, "a full gunship rocket volley (before: about 2900 with its exhaust) stays well under the pool cap (%d)" % peak)


func test_busy_wave_stays_within_the_particle_budget() -> void:
	var world := stage("", false)
	world.player.invulnerable = true
	var tank := world.player
	var d := world.rail.d + tank.course_offset + 40.0
	var made: Array[Enemy] = []
	for i in 4:
		var ugv := Ugv.new()
		ugv.weapon = "gun" if i % 2 == 0 else "atgm"
		made.append(ugv)
	for i in 3:
		var walker := Walker.new()
		walker.weapon = "gun" if i % 2 == 0 else "missile"
		made.append(walker)
	for weapon in ["flak", "mortar"]:
		var quad := QuadMech.new()
		quad.weapon = weapon
		made.append(quad)
	for i in 3:
		var heli := Helicopter.new()
		heli.set_meta("slot", Vector3(i * 6 - 6, 13, 45))
		made.append(heli)
	for i in made.size():
		made[i].position = Course.ground_at(d + i * 2.0, float(i % 5 - 2) * 4.0)
		world.add_enemy(made[i])
		made[i]._attack_timer = 0.2 + i * 0.1
	var peak := 0
	for _i in 600:
		await get_tree().process_frame
		peak = maxi(peak, world.fx.particle_count())
	print("PEAK busy wave particles: ", peak)
	check(peak < Fx.MAX_PARTICLES * 0.8, "a busy wave (before: about 2200) stays well under the pool cap (%d)" % peak)
