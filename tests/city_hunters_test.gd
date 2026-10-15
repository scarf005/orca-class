extends TestCase
## City hunters warn before firing, respect cover and lose to the tank's counters.


func _hind(world: World) -> Hind:
	var heli := Hind.new()
	heli.position = world.player.global_position + Vector3(0, 8, -45)
	world.add_enemy(heli)
	return heli


func _roof(world: World, at: Vector3, height: float) -> Prop:
	var prop := Prop.new()
	prop.setup("overpass_deck", PropKit.mesh("overpass_deck", 0), 5.0, height, 1000.0)
	prop.position = at
	world.props.add_child(prop)
	return prop


func test_hind_warns_then_ripples_and_holds_its_aim() -> void:
	var world := stage()
	var heli := _hind(world)
	heli._next_attack()
	heli._attack_timer = 0.0
	var before := world.projectiles.size()
	heli.behave(0.01)
	check(heli.telegraphing(), "pods warn before firing")
	check_eq(world.projectiles.size(), before, "no rocket during the warning")
	heli.behave(0.3)
	check(heli._lids[0].rotation.x < -1.0, "pod flaps open during the warning")
	heli.behave(0.8)
	var fixed := heli._rocket_aim
	for i in 6:
		heli.behave(0.23)
	check_eq(world.projectiles.size() - before, 6, "six rockets arrive in a ripple")
	check(heli._rocket_aim.is_equal_approx(fixed), "the volley does not chase a dodge")
	for shot: Projectile in world.projectiles.slice(before):
		check(shot.interceptable, "CIWS can catch each rocket")


func test_atgm_survives_long_flight_and_ciws_shoots_it() -> void:
	var world := stage()
	world.director.events.clear()
	world.rail.mode = Rail.Mode.HOLD
	var heli := _hind(world)
	heli._next_attack()
	heli._next_attack()
	heli._attack_timer = 0.0
	heli.behave(0.01)
	check(heli.telegraphing(), "ATGM sights before launch")
	var before := world.projectiles.size()
	heli.behave(1.0)
	heli.behave(0.01)
	check_eq(world.projectiles.size() - before, 1, "one guided missile launches")
	if world.projectiles.size() == before:
		return
	var missile := world.projectiles.back() as Projectile
	check(missile.life >= 6.0 and missile.hit.warhead, "long-lived shaped-charge threat")
	check(missile.homing_target == world.player, "missile guides toward the tank")
	missile.global_position = world.player.hit_center() + Vector3(0, 8, -20)
	missile.velocity = (world.player.hit_center() - missile.global_position).normalized() * 10.0
	heli.stagger = 10.0
	var hp := world.player.hp
	check(await wait_until(gone(missile), 180), "CIWS destroys the missile")
	check(world.player.heat > 0.0, "the laser actually engaged")
	check_eq(world.player.hp, hp, "intercept prevents damage")


func test_cover_cancels_fire_then_hind_pops_up() -> void:
	var world := stage()
	world.rail.mode = Rail.Mode.ARENA
	var heli := _hind(world)
	var wall := _roof(world, heli.global_position.lerp(world.player.global_position, 0.5) - Vector3.UP * 4.0, 20.0)
	check(CityCover.blocker(heli._chin_muzzle.global_position, world.player.hit_center()) == wall, "live world geometry blocks the sight")
	var shelter := CityCover.shelter(heli.global_position, world.player.hit_center())
	check(CityCover.blocker(shelter, world.player.hit_center()) != null, "resting hunter selects a screened low position")
	heli._attack_timer = 0.0
	var before := world.projectiles.size()
	var start := heli.global_position.y
	for i in 20:
		heli.behave(0.1)
	check(heli.global_position.y > start + 5.0, "hunter rises out of low cover")
	check_eq(world.projectiles.size(), before, "never fires through cover")
	wall.dead = true
	for i in 20:
		heli.behave(0.1)
	check(world.projectiles.size() > before, "with LOS it telegraphs and attacks")


func test_battery_uses_roof_and_warns_before_ripple() -> void:
	var world := stage()
	var site := world.player.global_position + Vector3(0, 0, -35)
	var roof := _roof(world, site, 12.0)
	var battery := RooftopBattery.new()
	battery.position = site + Vector3(0, 0, 4.5) # Fire from the roof edge without intersecting its top.
	world.add_enemy(battery)
	check_near(battery.global_position.y, roof.global_position.y + roof.height, 0.01, "launcher stands on elevated world surface")
	battery._timer = 0.0
	var before := world.projectiles.size()
	battery.behave(0.01)
	check(battery.telegraphing(), "impact circles precede launch")
	check_eq(world.projectiles.size(), before, "warning is not a shot")
	battery.behave(1.0)
	for i in 4:
		battery.behave(0.2)
	check_eq(world.projectiles.size() - before, 4, "roof launcher sends a ripple")


func test_mine_proximity_warns_and_shot_chains_only_nearby() -> void:
	var world := stage()
	var mines: Array[SeaMine] = []
	for offset in [Vector3(0, 0, -20), Vector3(2, 0, -20), Vector3(0, 0, -40)]:
		var mine := SeaMine.new()
		mine.position = world.player.global_position + offset
		world.add_enemy(mine)
		mines.append(mine)
	var hit := Hit.make(Hit.Kind.BULLET, 8.0, mines[0].hit_center())
	hit.source = world.player
	mines[0].take_hit(hit)
	check(mines[0].dead and mines[1].dead, "one shot chains through the neighbouring mine")
	check(not mines[2].dead, "distant mine survives blast falloff")
	mines[2].global_position = world.player.global_position + Vector3(0, 0, -3)
	mines[2].behave(0.01)
	check(mines[2].telegraphing() and not mines[2].dead, "proximity flashes before detonation")
	mines[2].behave(0.8)
	check(mines[2].dead, "armed mine detonates after the warning")


func test_tail_rotor_coax_and_shell_counters() -> void:
	var world := stage()
	var heli := _hind(world)
	for i in 3:
		var hit := Hit.make(Hit.Kind.BULLET, 3.0, heli._tail_rotor.global_position)
		hit.source = world.player
		heli.take_hit(hit)
	check(heli.dead, "three light coax hits to the tail rotor bring it down")
	var battery := RooftopBattery.new()
	battery.position = world.player.global_position + Vector3(15, 0, -70)
	world.add_enemy(battery)
	var shell := Hit.make(Hit.Kind.SHELL, 100.0, battery.hit_center())
	shell.source = world.player
	battery.take_hit(shell)
	check(battery.dead, "a shell knocks out the roof battery")
	var other := _hind(world)
	shell.position = other.hit_center()
	other.take_hit(shell)
	check(other.dead, "a cannon hit knocks down the Hind")
	var mine := SeaMine.new()
	mine.position = world.player.global_position + Vector3(4, 0, 0)
	world.add_enemy(mine)
	world.player.swat(false)
	check(mine.dead, "dash tail lash destroys a nearby mine")
