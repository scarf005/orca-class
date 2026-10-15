extends TestCase
## The shared heat pool: drift, CIWS and throttle fill it, flame and beam hits fill it, and a full pool vents.


func _rocket(world: World) -> Projectile:
	var tank := world.player
	var from := tank.global_position + Vector3(0, 12, -25)
	var rocket := world.spawn_projectile(Entity.Team.ENEMY, from, (tank.hit_center() - from).normalized() * 4.0, "rocket")
	rocket.interceptable = true
	rocket.intercept_hp = 100.0
	rocket.life = 10.0
	rocket.gravity = 0.0
	rocket.hit = Hit.make(Hit.Kind.SHELL, 5.0, from)
	return rocket


func _burn(tank: Tank, kind: Hit.Kind, damage: float) -> void:
	tank.invuln = 0.0
	tank.take_hit(Hit.make(kind, damage, tank.hit_center()))


func _cool_until_rearmed(tank: Tank) -> Array[bool]:
	var states: Array[bool] = []
	for _i in 2000:
		tank._update_heat(1.0 / 60.0)
		states.append(tank.overheated)
		if not tank.overheated:
			break
	return states


func test_each_drift_adds_heat_and_the_fourth_overloads() -> void:
	var tank := stage().player
	for i in 3:
		tank.anchor_cooldown = 0.0
		tank.dash(Vector2.RIGHT)
		check_near(tank.heat, Tank.DASH_HEAT * (i + 1), 0.001, "drift %d adds one chunk" % (i + 1))
		check(not tank.overheated, "three drifts stay under the limit")
	tank.anchor_cooldown = 0.0
	tank.dash(Vector2.RIGHT)
	check(tank.overheated and tank.heat == 1.0, "the fourth drift fills the pool and vents")


func test_dash_is_refused_while_venting_until_heat_falls_to_the_rearm_level() -> void:
	var tank := stage().player
	tank.add_heat(1.0)
	tank.anchor_cooldown = 0.0
	tank.dash(Vector2.RIGHT)
	check_eq(tank._drift, 0.0, "no drift while venting")
	check_eq(tank.heat, 1.0, "a refused dash adds no heat")
	var states := _cool_until_rearmed(tank)
	check(states.size() > 60, "venting lasts seconds, not a blink (%d frames)" % states.size())
	check(tank.heat <= Tank.VENT_REARM and tank.heat > Tank.VENT_REARM - 0.01, "it re-arms at the threshold (%.3f)" % tank.heat)
	tank.dash(Vector2.RIGHT)
	check(tank._drift > 0.0, "the drift works again")


func test_idle_cools_faster_than_working() -> void:
	var tank := stage().player
	tank.heat = 0.8
	tank.add_heat(0.0)
	tank._update_heat(Tank.HEAT_IDLE * 0.5)
	var working := 0.8 - tank.heat
	tank._update_heat(Tank.HEAT_IDLE)
	var before := tank.heat
	tank._update_heat(Tank.HEAT_IDLE * 0.5)
	check((before - tank.heat) > working * 2.0, "after the idle wait the same time sheds more")


func test_a_wrecked_engine_cools_slowly_but_still_recovers() -> void:
	var tank := stage().player
	tank.modules.damage("engine", 999.0)
	tank.add_heat(1.0)
	var frames_needed := _cool_until_rearmed(tank).size()
	check(frames_needed < 2000, "venting still ends with a wrecked engine (%d frames)" % frames_needed)


func test_fire_and_laser_hits_add_heat_in_proportion_to_the_damage_taken() -> void:
	var tank := stage().player
	var hp := tank.hp
	_burn(tank, Hit.Kind.FIRE, 20.0)
	var taken := hp - tank.hp
	check(taken > 0.0, "the flame still hurts")
	check_near(tank.heat, taken * Tank.HEAT_PER_DAMAGE, 0.0001, "heat follows the armor damage")
	var before := tank.heat
	_burn(tank, Hit.Kind.SHELL, 20.0)
	check_eq(tank.heat, before, "a shell of the same damage adds none")


func test_beam_hits_can_push_the_tank_into_overload() -> void:
	var tank := stage().player
	tank.invulnerable = false
	for _i in 4:
		_burn(tank, Hit.Kind.LASER, 40.0)
		if tank.dead:
			break
	check(tank.overheated, "enough beam damage vents the tank")


func test_a_dashing_tank_takes_no_heat_from_a_flame() -> void:
	var tank := stage().player
	tank.invuln = 1.0
	tank.take_hit(Hit.make(Hit.Kind.FIRE, 40.0, tank.hit_center()))
	check_eq(tank.heat, 0.0, "a dodged flame adds no heat")


func test_ciws_holds_fire_while_venting_and_resumes_when_rearmed() -> void:
	var world := stage()
	var tank := world.player
	var rocket := _rocket(world)
	tank.add_heat(1.0)
	await frames(30)
	check(tank.ciws_target == null, "no target while venting")
	check(is_instance_valid(rocket) and rocket.intercept_hp == 100.0, "the laser never touches the rocket")
	var resumed := await wait_until(func() -> bool: return tank.ciws_target != null, 600)
	check(resumed, "once re-armed the laser engages again")
	check(tank.heat > 0.0, "and its fire fills the pool")


func test_main_gun_recovers_slower_while_venting() -> void:
	var world := stage()
	world.set_process(false)
	world.director.set_process(false)
	world.player.set_process(false)
	var tank := world.player
	tank.input_enabled = true
	var recover := {}
	for venting in [false, true]:
		tank.heat = 1.0 if venting else 0.0
		tank.overheated = venting
		tank._recover = 0.0
		tank._spent = false
		var shots := world.stats.shots
		Input.action_press("fire")
		for _i in 200:
			tank._update_charge(1.0 / 60.0)
			tank._update_weapons(1.0 / 60.0)
			if world.stats.shots > shots:
				break
		Input.action_release("fire")
		recover[venting] = tank._recover
		check(world.stats.shots > shots, "the gun fires (venting %s)" % venting)
	check_near(recover[false], Armament.CANNON_RECOVER, 0.02, "normal recovery")
	check_near(recover[true], Armament.CANNON_RECOVER * Tank.VENT_RELOAD, 0.02, "venting recovery")


func test_overdrive_adds_heat_and_venting_cuts_it() -> void:
	var world := stage()
	var tank := world.player
	tank.input_enabled = true
	Input.action_press("move_forward")
	await frames(30)
	check_eq(world.rail.throttle, 1, "W boosts while cool")
	check(tank.heat > 0.0, "boosting heats the tank")
	tank.add_heat(1.0)
	await frames(10)
	check_eq(world.rail.throttle, 0, "venting drops the throttle to cruise")
	Input.action_release("move_forward")
	tank.input_enabled = false


func test_the_hud_gauge_colour_follows_heat_and_venting() -> void:
	var world := stage()
	var hud := Hud.new()
	hud.world = world
	add_child(hud)
	var tank := world.player
	await frames(2)
	check_eq(hud.heat_color(), Palette.SKY, "cool")
	tank.heat = 0.8
	check_eq(hud.heat_color(), Palette.BUTTER, "near overload")
	tank.add_heat(1.0)
	check(hud.heat_color() in [Palette.RED, Palette.CORAL], "venting flashes red")
	hud.free()


func test_respawn_clears_heat() -> void:
	var tank := stage().player
	tank.add_heat(1.0)
	tank._finish_respawn()
	check(tank.heat == 0.0 and not tank.overheated, "a fresh hull starts cool")
