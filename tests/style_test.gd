extends TestCase
## Style weights: melee tricks outrank guns, a full charge names its kill, and CIWS and demolition pay little.


func _rig() -> World:
	var world := stage()
	world.set_process(false)
	world.director.set_process(false)
	world.player.set_process(false)
	return world


func _crawler(world: World) -> Crawler:
	var crawler := Crawler.new()
	crawler.position = Course.ground_at(world.rail.d + 60.0, 5.0)
	world.add_enemy(crawler)
	crawler.set_process(false)
	return crawler


## Style gained by hitting `enemy` with a `kind` hit that carries `power`.
func _style_from(world: World, enemy: Enemy, kind: Hit.Kind, power := 0.0, damage := 999.0) -> float:
	world._chain = 0 # Isolate the trick from the chain bonus.
	var before := world.stats.style
	var hit := Hit.make(kind, damage, enemy.hit_center())
	hit.source = world.player
	hit.power = power
	enemy.take_hit(hit)
	return world.stats.style - before


func _fed(world: World, trick: String) -> bool:
	return world.stats.style_feed.any(func(e: Dictionary) -> bool: return e.name == trick)


func test_melee_tricks_are_weighted() -> void:
	var world := _rig()
	check_near(_style_from(world, _crawler(world), Hit.Kind.RAM), 90.0, 0.01, "ram crush")
	check_near(_style_from(world, _crawler(world), Hit.Kind.THROWN), 90.0, 0.01, "thrown")
	check_near(_style_from(world, _crawler(world), Hit.Kind.TAIL), 80.0, 0.01, "dash lash")
	check(_fed(world, "LASH"), "the lash has its own trick name")
	check(not _fed(world, "TAILWHIP"), "the old name is gone")


func test_ciws_kill_pays_ten() -> void:
	var world := _rig()
	check_near(_style_from(world, _crawler(world), Hit.Kind.LASER), 10.0, 0.01, "zapped")


func test_full_charge_kill_is_charged_not_direct() -> void:
	var world := _rig()
	check_near(_style_from(world, _crawler(world), Hit.Kind.SHELL, 1.0), 80.0, 0.01, "charged kill")
	check(_fed(world, "CHARGED"), "named CHARGED")
	check(not _fed(world, "DIRECT"), "and not DIRECT")
	check_near(_style_from(world, _crawler(world), Hit.Kind.SHELL, 0.99), 35.0, 0.01, "a nearly full charge is an ordinary direct hit")


func test_interrupt_needs_full_charge_on_a_wind_up() -> void:
	var world := _rig()
	var ugv := Ugv.new()
	ugv.position = Course.ground_at(world.rail.d + 60.0, 0.0)
	world.add_enemy(ugv)
	ugv.set_process(false)
	ugv._telegraph = 0.5
	check(ugv.telegraphing(), "the wind-up counts")
	check_near(_style_from(world, ugv, Hit.Kind.SHELL, 0.99, 5.0), 0.0, 0.01, "a partial charge does not interrupt")
	check_near(_style_from(world, ugv, Hit.Kind.SHELL, 1.0, 5.0), 90.0, 0.01, "a full charge on a wind-up interrupts without killing")
	check(not ugv.dead, "and it lives")
	ugv._telegraph = 0.0
	check_near(_style_from(world, ugv, Hit.Kind.SHELL, 1.0, 5.0), 0.0, 0.01, "no wind-up, no interrupt")


func test_interrupting_kill_pays_both() -> void:
	var world := _rig()
	var ugv := Ugv.new()
	ugv.position = Course.ground_at(world.rail.d + 60.0, 0.0)
	world.add_enemy(ugv)
	ugv.set_process(false)
	ugv._telegraph = 0.5
	var gained := _style_from(world, ugv, Hit.Kind.SHELL, 1.0)
	check(ugv.dead, "the shell kills")
	check_near(gained, 90.0 + 80.0, 0.01, "INTERRUPT plus CHARGED")


func test_wind_up_states_report_telegraphing() -> void:
	var fpv := FpvDrone.new()
	check(not fpv.telegraphing(), "an approaching drone is not winding up")
	fpv.state = FpvDrone.State.TELEGRAPH
	check(fpv.telegraphing(), "its red-light pre-dive is")
	var walker := Walker.new()
	walker._kick = 0.3
	check(walker.telegraphing(), "a walker kick wind-up is")
	var quad := QuadMech.new()
	quad._stomp = 0.3
	check(quad.telegraphing(), "a quad stomp wind-up is")
	check(not Crawler.new().telegraphing(), "enemies without a wind-up never are")
	for node: Node in [fpv, walker, quad]:
		node.free()


func test_demolition_style_is_halved() -> void:
	var world := _rig()
	var prop := Prop.new()
	prop.setup("house", PropKit.mesh("house", 0), 2.5, 4.0, 10.0)
	prop.position = Course.ground_at(world.rail.d + 40.0, 0.0)
	world.props.add_child(prop)
	var before := world.stats.style
	var hit := Hit.make(Hit.Kind.SHELL, 999.0, prop.global_position)
	hit.source = world.player
	prop.take_hit(hit)
	check(prop.dead, "the house falls")
	check_near(world.stats.style - before, (8.0 + prop.footprint * 6.0) * 0.5, 0.01, "demolition pays half")
