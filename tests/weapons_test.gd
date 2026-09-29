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
		tank.reload = 0.0
		tank.fire_cannon()
	check_eq(tank.current_round, Armament.Round.APHE, "empty magazine falls back to APHE")
	tank.reload = 0.0
	tank.fire_cannon()
	check_eq(tank.current_round, Armament.Round.APHE, "APHE is unlimited")


func test_new_round_replaces_current() -> void:
	var world := stage()
	var tank := world.player
	tank.collect(world.spawn_pickup("canister", tank.global_position + Vector3(0, 30, 0)))
	tank.reload = 0.0
	tank.fire_cannon()
	tank.collect(world.spawn_pickup("apfsds", tank.global_position + Vector3(0, 30, 0)))
	check_eq(tank.current_round, Armament.Round.APFSDS, "pickup swaps the round type")
	check_eq(tank.round_count, Armament.MAGAZINE[Armament.Round.APFSDS], "magazine refilled for the new type")


func test_canister_fires_a_pellet_cone() -> void:
	var world := stage()
	var tank := world.player
	tank.load_round(Armament.Round.CANISTER)
	var before := world.projectiles.size()
	tank.reload = 0.0
	tank.fire_cannon()
	check(world.projectiles.size() - before >= 20, "canister spawns many pellets")
	check(tank.reload > 0.0, "firing starts the reload")


func test_airburst_detonates_at_fuse_distance() -> void:
	var world := stage()
	var tank := world.player
	tank.load_round(Armament.Round.AIRBURST)
	var muzzle := tank.model.muzzle.global_position
	tank.aim_point = muzzle + -tank.model.barrel.global_basis.z * 40.0 # The shell follows the barrel.
	tank.reload = 0.0
	var before := world.projectiles.size()
	tank.fire_cannon() # Hitscan: the shell flies and bursts within this call.
	var fragments := world.projectiles.slice(before).filter(func(p: Projectile) -> bool: return not p.is_queued_for_deletion()) # Minus the spent shell.
	check(fragments.size() > 0, "burst releases fragments")
	var burst: Vector3 = fragments[0].global_position if fragments.size() > 0 else muzzle
	check_near(muzzle.distance_to(burst), muzzle.distance_to(tank.aim_point) - 2.0, 1.0, "fuse bursts just short of the aim point")
	check(burst.y > Course.height_at(burst) + 1.0, "the burst is in the air")


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
	tank.reload = 0.0
	var target := ugvs[0].hit_center()
	tank.fire_cannon(target + Vector3.UP * 20.0, Vector3.DOWN)
	return ugvs.map(func(ugv: Ugv) -> bool: return ugv.dead)


func test_aphe_wrecks_its_target_and_its_neighbor_not_the_wave() -> void:
	var world := stage()
	var dead: Array = await _cannon_volley(world, Armament.Round.APHE, 3.0, 9.0)
	check_eq(dead, [true, true, false], "APHE kills what it hits and what is right beside it")
	check_near(world.player.reload, Armament.RELOAD, 0.01, "then cycles for the next round")


func test_heat_hits_harder_and_wider_on_the_same_reload() -> void:
	var world := stage()
	var dead: Array = await _cannon_volley(world, Armament.Round.HEAT, 7.0, 14.0)
	check_eq(dead, [true, true, false], "HEAT's blast reaches past APHE's")
	check_near(world.player.reload, Armament.RELOAD, 0.01, "HEAT loads as fast as APHE")


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
