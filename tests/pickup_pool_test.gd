extends TestCase
## Disabled rounds stay out of stage loot and surplus-pickup replacements.


func test_stage_loot_never_offers_canister_or_airburst() -> void:
	var world := stage()
	var blocked := ["canister", "airburst"]
	check(not Armament.OFFERED.any(func(r: Armament.Round) -> bool: return Armament.ROUND_IDS[r] in blocked), "disabled rounds are outside the replacement pool")
	for spec: Scenery.Spec in world.director.scenery.specs:
		check(spec.pickup not in blocked, "placed loot excludes disabled rounds")
	for hard in [false, true]:
		for event: Dictionary in Stage1.events(hard):
			check(event.get("drop", "") not in blocked, "enemy drops exclude disabled rounds")
			check(event.get("reward", "") not in blocked, "hold rewards exclude disabled rounds")
			if event.type == "pickup":
				check(event.id not in blocked, "scripted pickups exclude disabled rounds")
	var tank := world.player
	tank.set_process(false)
	tank.set_coax_tier(Armament.COAX_TIERS.size() - 1)
	var offered := Armament.OFFERED.map(func(r: Armament.Round) -> String: return Armament.ROUND_IDS[r])
	for round: Armament.Round in [Armament.Round.APHE] + Armament.OFFERED:
		tank.load_round(round)
		for id in ["coax", "repair", "era", "tail"]:
			var pickup := world.spawn_pickup(id, tank.global_position + Vector3.UP * 30.0)
			check(pickup.id in offered, "surplus pickups spawn only offered rounds")
			check(pickup.id != Armament.ROUND_IDS[round], "the replacement differs from the loaded round")
