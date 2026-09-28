extends TestCase
## Armor rules, hit geometry, props and blasts.


func test_segment_sphere() -> void:
	check_near(Entity.segment_sphere(Vector3(-5, 0, 0), Vector3(5, 0, 0), Vector3.ZERO, 1.0), 4.0, 0.001, "hits the near side")
	check_eq(Entity.segment_sphere(Vector3(-5, 2, 0), Vector3(5, 2, 0), Vector3.ZERO, 1.0), -1.0, "misses above")
	check_eq(Entity.segment_sphere(Vector3(2, 0, 0), Vector3(5, 0, 0), Vector3.ZERO, 1.0), -1.0, "moving away misses")
	check_eq(Entity.segment_sphere(Vector3(0.5, 0, 0), Vector3(5, 0, 0), Vector3.ZERO, 1.0), 0.0, "starting inside hits at 0")


func test_small_calibers_barely_scratch_ugv_armor() -> void:
	var world := stage()
	var ugv := Ugv.new()
	ugv.position = Course.ground_at(world.rail.d + 60.0, 0.0)
	world.add_enemy(ugv)
	var hit8 := Hit.make(Hit.Kind.BULLET, 10.0, ugv.hit_center())
	hit8.caliber = 8
	var hit15 := hit8.copy()
	hit15.caliber = 15
	var heat := Hit.make(Hit.Kind.SHELL, 10.0, ugv.hit_center())
	heat.pierce = true
	check_near(ugv.damage_multiplier(hit8), 1.0, 0.001, "an unarmored UGV takes full coax damage")
	ugv.armor = 0.5
	check_near(ugv.damage_multiplier(hit8), 0.5, 0.001, "armor stops its share of 8 mm")
	check_near(ugv.damage_multiplier(hit15), 0.75, 0.001, "armor stops half its share of 15 mm")
	check_near(ugv.damage_multiplier(heat), 1.0, 0.001, "HEAT ignores armor")
	var thrown := Hit.make(Hit.Kind.THROWN, 10.0, ugv.hit_center())
	check_near(ugv.damage_multiplier(thrown), 1.5, 0.001, "thrown wrecks are extra effective")


func test_tank_frontal_armor_and_weak_rear() -> void:
	var world := stage()
	var tank := world.player
	var forward := -tank.global_basis.z
	var front := Hit.make(Hit.Kind.SHELL, 10.0, tank.hit_center(), -forward)
	var rear := Hit.make(Hit.Kind.SHELL, 10.0, tank.hit_center(), forward)
	check_near(tank.damage_multiplier(front), 0.6, 0.001, "front hits reduced")
	check_near(tank.damage_multiplier(rear), 1.4, 0.001, "rear hits amplified")
	tank.invuln = 1.0
	check_eq(tank.damage_multiplier(front), 0.0, "invulnerable while dodging or respawning")


func test_crawler_weak_to_fire() -> void:
	var world := stage()
	var crawler := Crawler.new()
	crawler.position = Course.ground_at(world.rail.d + 60.0, 8.0)
	world.add_enemy(crawler)
	var fire := Hit.make(Hit.Kind.FIRE, 5.0, crawler.hit_center())
	fire.incendiary = true
	crawler.take_hit(fire)
	check(crawler.dead, "one dragon's breath flame kills a crawler")
	check(world.stats.kills >= 1, "counts as a kill")


func test_blast_hits_enemies_and_props_not_player() -> void:
	var world := stage()
	var tank := world.player
	var crawler := Crawler.new()
	crawler.position = Course.ground_at(world.rail.d + 40.0, 0.0)
	world.add_enemy(crawler)
	var hp := tank.hp
	world.blast(crawler.hit_center(), 4.0, 100.0, Entity.Team.PLAYER)
	check(crawler.dead, "player blast kills the crawler")
	check_eq(tank.hp, hp, "player blast does not hurt the player")


func test_explosive_wreck_rammed_by_player_spares_player() -> void:
	var world := stage()
	var tank := world.player
	var prop := Prop.new()
	prop.setup("car", PropKit.mesh("car", 0), 2.0, 1.8, 50.0)
	prop.explosive = true
	prop.position = tank.global_position + Vector3(2, 0, 0)
	world.props.add_child(prop)
	var hp := tank.hp
	prop.take_hit(Hit.make(Hit.Kind.RAM, 999.0, prop.global_position))
	check(prop.dead, "car destroyed")
	check_eq(tank.hp, hp, "tank unharmed by a wreck it set off")


func test_projectile_hits_ground() -> void:
	var world := stage()
	var tank := world.player
	var from := tank.global_position + Vector3(0, 10, -20)
	var shot := world.spawn_projectile(Entity.Team.PLAYER, from, Vector3(0, -80, 0), "bullet")
	shot.hit = Hit.make(Hit.Kind.BULLET, 1.0, from)
	var ok := await wait_until(gone(shot), 30)
	check(ok, "falling bullet stops at the ground")


func test_props_block_and_break_under_ram() -> void:
	var world := stage()
	var tank := world.player
	var prop := Prop.new()
	prop.setup("bale", PropKit.mesh("bale", 0), 1.0, 1.6, 12.0)
	prop.crushable = true
	prop.position = tank.global_position
	world.props.add_child(prop)
	var crushed := await wait_until(gone(prop), 5)
	check(crushed, "crushable prop under the tank is crushed")
