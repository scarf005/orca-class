extends TestCase
## Coax tiers and cannon round magazines.


func test_coax_tier_climbs_to_max_then_scores() -> void:
	var world := stage()
	var tank := world.player
	# All spawned while still needed: at max tier a fresh coax drop turns into something else.
	var pickups: Array[Pickup] = []
	for i in Armament.COAX_TIERS.size():
		pickups.append(world.spawn_pickup("coax", tank.global_position + Vector3(0, 30, 0)))
	for i in Armament.COAX_TIERS.size() - 1:
		tank.collect(pickups[i])
	check_eq(tank.coax_tier, Armament.COAX_TIERS.size() - 1, "tier after five upgrades")
	check_eq(tank.model.coax_muzzles.size(), 3, "max tier mounts three guns")
	var before := world.stats.score
	tank.collect(pickups[-1])
	check_eq(tank.coax_tier, Armament.COAX_TIERS.size() - 1, "tier stays at max")
	check(world.stats.score - before >= 2000, "extra coax at max gives a score bonus")


func test_coax_tier_clamps_and_drops_on_life_loss() -> void:
	var world := stage()
	var tank := world.player
	tank.set_coax_tier(-3)
	check_eq(tank.coax_tier, 0, "negative tier clamps to 0")
	tank.set_coax_tier(3)
	tank.take_hit(Hit.make(Hit.Kind.BLAST, 9999.0, tank.global_position + Vector3.FORWARD, Vector3.BACK))
	check_eq(tank.coax_tier, 2, "losing a life drops one tier")
	check_eq(world.stats.lives, 2, "one life lost")
	check(not tank.dead, "tank respawns while lives remain")


func test_special_round_magazine_runs_out_to_aphe() -> void:
	var world := stage()
	var tank := world.player
	tank.collect(world.spawn_pickup("heat", tank.global_position + Vector3(0, 30, 0)))
	check_eq(tank.current_round, Armament.Round.HEAT, "HEAT loaded")
	check_eq(tank.round_count, Armament.MAGAZINE[Armament.Round.HEAT], "full HEAT magazine")
	for i in Armament.MAGAZINE[Armament.Round.HEAT]:
		tank.fire_cannon()
	check_eq(tank.current_round, Armament.Round.APHE, "empty magazine falls back to APHE")
	tank.fire_cannon()
	check_eq(tank.current_round, Armament.Round.APHE, "APHE is unlimited")


func test_new_round_replaces_current() -> void:
	var world := stage()
	var tank := world.player
	tank.collect(world.spawn_pickup("canister", tank.global_position + Vector3(0, 30, 0)))
	tank.fire_cannon()
	tank.collect(world.spawn_pickup("apfsds", tank.global_position + Vector3(0, 30, 0)))
	check_eq(tank.current_round, Armament.Round.APFSDS, "pickup swaps the round type")
	check_eq(tank.round_count, Armament.MAGAZINE[Armament.Round.APFSDS], "magazine refilled for the new type")


func test_canister_fires_a_pellet_cone() -> void:
	var world := stage()
	var tank := world.player
	tank.load_round(Armament.Round.CANISTER)
	var before := world.projectiles.size()
	tank.fire_cannon()
	check(world.projectiles.size() - before >= 20, "canister spawns many pellets")


func test_airburst_flies_slowly_and_bursts_at_max_range_not_the_reticle() -> void:
	var world := stage()
	var tank := world.player
	tank.load_round(Armament.Round.AIRBURST)
	var muzzle := tank.model.muzzle.global_position + Vector3.UP * 100.0
	tank.aim_point = muzzle + Vector3.FORWARD * 40.0
	var before := world.projectiles.size()
	tank.fire_cannon(muzzle, Vector3.FORWARD, Armament.STAGE_1)
	var shell := world.projectiles[before]
	check(not shell.is_queued_for_deletion(), "special round remains a visible projectile")
	check_near(shell.velocity.length(), 110.0, 0.001, "slow enough to watch in flight")
	shell.step(0.1)
	check_near(muzzle.distance_to(shell.global_position), 11.0, 0.01, "it advances rather than resolving hitscan")
	land(world, before)
	var fragments := world.projectiles.slice(before + 1)
	check(not fragments.is_empty(), "range fuse releases fragments")
	if fragments.is_empty():
		return
	check_near(muzzle.distance_to(fragments[0].global_position), Armament.SHELL_RANGE, 2.0, "without a nearby enemy it bursts at maximum range")
	check(fragments.all(func(p: Projectile) -> bool: return p.hit.damage == 400.0 and p.hit.caliber == 30), "fragments have flat damage and 30 mm penetration")


## Fires an airburst from the muzzle along the barrel with the reticle `reticle` m out and returns where the
## fragments were released (INF when nothing burst) with a UAV `ahead` m out and `off` m beside the line.
func _burst_beside_uav(world: World, ahead: float, off: float, reticle: float, power: float) -> Array:
	var tank := world.player
	tank.load_round(Armament.Round.AIRBURST)
	var muzzle := tank.model.muzzle.global_position
	var forward := -tank.model.barrel.global_basis.z
	var uav := Uav.new()
	world.add_enemy(uav)
	uav.set_process(false)
	uav.global_position = muzzle + forward * ahead + tank.model.barrel.global_basis.x * off - Vector3.UP * uav.center_height
	tank.aim_point = muzzle + forward * reticle
	var before := world.projectiles.size()
	tank.fire_cannon(Vector3.INF, Vector3.ZERO, power)
	land(world, before)
	var fragments := world.projectiles.slice(before).filter(func(p: Projectile) -> bool: return not p.is_queued_for_deletion())
	return [muzzle, fragments[0].global_position if not fragments.is_empty() else Vector3.INF, uav]


func test_airburst_does_not_arm_inside_15_m() -> void:
	var world := stage()
	var burst := await _burst_beside_uav(world, 8.0, 3.0, 100.0, Armament.STAGE_1)
	check(burst[1] != Vector3.INF, "the shell still bursts farther away")
	check(burst[0].distance_to(burst[1]) >= 15.0, "it cannot proximity-burst before arming")


func test_airburst_bursts_on_passing_a_uav_off_its_line() -> void:
	var world := stage()
	var burst := await _burst_beside_uav(world, 60.0, 4.0, 120.0, 0.0)
	var uav: Uav = burst[2]
	check(burst[1] != Vector3.INF, "it bursts")
	check_near(burst[0].distance_to(burst[1]), 60.0, 6.0, "abeam of the UAV, not at the reticle")
	check(burst[1].distance_to(uav.hit_center()) <= Armament.AIRBURST_PROXIMITY.x, "within 6 m of it")


func test_airburst_proximity_reaches_5_m_but_not_7_m() -> void:
	var world := stage()
	var plain := await _burst_beside_uav(world, 60.0, 7.0, 120.0, 0.0)
	check(plain[0].distance_to(plain[1]) > 100.0, "a UAV 7 m off the line is out of the 6 m fuse (burst %.0f m out)" % plain[0].distance_to(plain[1]))
	var inside := await _burst_beside_uav(world, 60.0, 5.0, 120.0, Armament.STAGE_1)
	check_near(inside[0].distance_to(inside[1]), 60.0, 6.0, "a special-round snap shot bursts beside an enemy inside 6 m")


func test_airburst_fragments_favor_flyers_over_ground_armor() -> void:
	var world := stage()
	var fragment := Hit.make(Hit.Kind.FRAGMENT, 400.0, Vector3.ZERO)
	fragment.caliber = 30
	var cases := [[Uav.new(), 2.0], [FpvDrone.new(), 2.0], [Helicopter.new(), 1.6], [Ugv.new(), 0.18], [Walker.new(), 0.2], [QuadMech.new(), 0.1]]
	for case in cases:
		var enemy: Enemy = case[0]
		enemy.position = world.player.global_position + Vector3(50, 20, 0)
		world.add_enemy(enemy)
		check_near(enemy.damage_multiplier(fragment), case[1], 0.001, "%s applies its fragment counter and millimeter armor" % enemy.get_script().get_global_name())


func test_canister_clears_a_crawler_pack_at_20_m() -> void:
	var world := stage()
	var tank := world.player
	tank.load_round(Armament.Round.CANISTER)
	var muzzle := tank.model.muzzle.global_position
	var forward := -tank.model.barrel.global_basis.z
	var side := tank.model.barrel.global_basis.x
	var crawlers: Array[Crawler] = []
	for k in 6:
		var crawler := Crawler.new()
		var spot := muzzle + forward * (20.0 + (k % 2) * 1.5) + side * (k - 2.5) * 0.6
		spot.y = Course.height_at(spot)
		crawler.position = spot
		world.add_enemy(crawler)
		crawler.set_process(false)
		crawlers.append(crawler)
	seed(1)
	tank.fire_cannon(Vector3.INF, Vector3.ZERO, 1.0)
	check_eq(crawlers.filter(func(c: Crawler) -> bool: return c.dead).size(), 6, "one canister shot kills the whole pack")


## Two UGVs beside the one the shot lands on: one at `near`, one at `far` meters across the road.
func _cannon_volley(world: World, round: Armament.Round, near: float, far: float) -> Array:
	var tank := world.player
	var d := world.rail.d + 60.0
	var ugvs: Array[Ugv] = []
	for u in [0.0, near, far]:
		var ugv := Ugv.new()
		ugv.position = Course.ground_at(d, u)
		ugv.immobile = true
		world.add_enemy(ugv)
		ugvs.append(ugv)
	await frames(1)
	tank.load_round(round)
	var target := ugvs[0].hit_center()
	var before := world.projectiles.size()
	tank.fire_cannon(target + Vector3.UP * 20.0, Vector3.DOWN, 0.99)
	land(world, before)
	return ugvs.map(func(ugv: Ugv) -> bool: return ugv.dead)


func test_aphe_wrecks_its_target_and_its_neighbor_not_the_wave() -> void:
	var world := stage()
	var dead: Array = await _cannon_volley(world, Armament.Round.APHE, 3.0, 18.0)
	check_eq(dead, [true, true, false], "APHE kills what it hits and what is right beside it")


func test_heat_hits_harder_and_wider_than_aphe() -> void:
	var world := stage()
	var dead: Array = await _cannon_volley(world, Armament.Round.HEAT, 7.0, 14.0)
	check_eq(dead, [true, true, false], "HEAT's blast reaches past APHE's")


func test_the_stage_hands_out_no_heat_or_apfsds() -> void:
	var world := stage()
	var held_back := ["heat", "apfsds"]
	var placed: Array = world.director.scenery.specs.map(func(spec: Scenery.Spec) -> String: return spec.pickup).filter(func(id: String) -> bool: return not id.is_empty())
	check(not placed.is_empty(), "the stage places pickups")
	check(not placed.any(func(id: String) -> bool: return id in held_back), "no HEAT or APFSDS crate is placed")
	var tank := world.player
	tank.set_coax_tier(Armament.COAX_TIERS.size() - 1)
	# With nothing else needed, a spare pickup turns into a special round.
	check(tank.useful_pickup("coax") in Armament.ROUND_IDS.values(), "a spare coax turns into a round")
	for i in 40:
		var id := tank.useful_pickup("coax" if i % 2 == 0 else "repair")
		check(id not in held_back, "a spare pickup never becomes %s" % id)
		tank.load_round(Armament.round_from_id(id))
