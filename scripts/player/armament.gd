class_name Armament
## Weapon data for the Orca-class: coaxial gun tiers and 100 mm cannon rounds.

## Each tier lists its coaxial guns by caliber.
const COAX_TIERS: Array = [[8], [15], [20], [20, 8], [20, 15], [20, 20, 8]]

const GUNS := {
	8: {"interval": 0.065, "damage": 3.4, "speed": 150.0, "spread": 0.014, "color": Palette.BUTTER, "sound": "coax8", "blast": 0.0},
	15: {"interval": 0.09, "damage": 7.5, "speed": 150.0, "spread": 0.011, "color": Palette.PEACH, "sound": "coax15", "blast": 0.0},
	20: {"interval": 0.115, "damage": 12.0, "speed": 140.0, "spread": 0.009, "color": Palette.CORAL, "sound": "coax20", "blast": 1.3},
}

enum Round { APHE, HEAT, CANISTER, DRAGON, APFSDS, AIRBURST }

const ROUND_IDS := {
	Round.APHE: "aphe", Round.HEAT: "heat", Round.CANISTER: "canister", Round.DRAGON: "dragon",
	Round.APFSDS: "apfsds", Round.AIRBURST: "airburst",
}

## Rounds loaded per special-round pickup.
const MAGAZINE := {Round.HEAT: 6, Round.CANISTER: 8, Round.DRAGON: 6, Round.APFSDS: 6, Round.AIRBURST: 8}

const RELOAD := 1.0
const SHELL_SPEED := 190.0 ## Slow enough that the glowing shell reads in flight.
const HEAT_RELOAD := 1.25

const ROUND_COLORS := {
	Round.APHE: Palette.WHITE, Round.HEAT: Palette.CORAL, Round.CANISTER: Palette.SKY, Round.DRAGON: Palette.FUNGUS,
	Round.APFSDS: Palette.MINT, Round.AIRBURST: Palette.LILAC,
}


static func round_from_id(id: String) -> Round:
	for key: Round in ROUND_IDS:
		if ROUND_IDS[key] == id:
			return key
	return Round.APHE


static func tier_calibers(tier: int) -> Array:
	return COAX_TIERS[clampi(tier, 0, COAX_TIERS.size() - 1)]
