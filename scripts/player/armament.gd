class_name Armament
## Weapon data for the Orca-class: coaxial gun tiers and 100 mm cannon rounds.

## Each tier lists its coaxial guns by caliber.
const COAX_TIERS: Array = [[8], [15], [20], [20, 8], [20, 15], [20, 20, 8]]

const GUNS := {
	8: {"interval": 0.065, "damage": 3.4, "speed": 150.0, "spread": 0.014, "color": Palette.AMBER, "sound": "coax8", "blast": 0.0},
	15: {"interval": 0.09, "damage": 7.5, "speed": 150.0, "spread": 0.011, "color": Palette.AMBER, "sound": "coax15", "blast": 0.0},
	20: {"interval": 0.115, "damage": 12.0, "speed": 140.0, "spread": 0.009, "color": Palette.AMBER, "sound": "coax20", "blast": 1.3},
}

enum Round { APHE, HEAT, CANISTER, DRAGON, APFSDS, AIRBURST }

const ROUND_IDS := {
	Round.APHE: "aphe", Round.HEAT: "heat", Round.CANISTER: "canister", Round.DRAGON: "dragon",
	Round.APFSDS: "apfsds", Round.AIRBURST: "airburst",
}

## Special rounds the stage hands out. HEAT and APFSDS are held back for now.
const OFFERED: Array[Round] = [Round.CANISTER, Round.DRAGON, Round.AIRBURST]

## Rounds loaded per special-round pickup.
const MAGAZINE := {Round.HEAT: 6, Round.CANISTER: 6, Round.DRAGON: 6, Round.APFSDS: 6, Round.AIRBURST: 6}

## A real 100 mm gun, Star Fox style: no reload, only the charge. Holding the button charges a shell that
## wrecks any ordinary vehicle outright and blasts the pack around it, so the charge time is the gun's cadence.
const SHELL_SPEED := 1700.0 ## Main-gun rounds are hitscan; this only sets their lead (none, in effect).
const SHELL_RANGE := 420.0
const SHELL_DAMAGE := 1500.0

const CHARGE_DELAY := 0.15
const CHARGE_TIME := 0.55
const CHARGE_DRAIN := 3.0 ## A release short of full drains the charge this many times faster than it builds, so a quick re-press resumes.
const LOCK_RADIUS := 64.0 ## 3D-view pixels around the reticle that a charge picks and locks its target within.
const APHE_DAMAGE := Vector2(1.0, 2.0)
const APHE_RADIUS := Vector2(5.0, 9.0)
const APHE_BLAST := Vector2(600.0, 600.0)
const HEAT_STAGGER := Vector2(1.0, 2.5)
const HEAT_RADIUS := Vector2(9.0, 12.0)
const APFSDS_RANGE := Vector2(1.0, 1.4)
const APFSDS_DAMAGE := Vector2(1.0, 1.5)
const CANISTER_SPREAD := 0.13 ## Radians: a wide cone, the close-swarm round, the same however the gun is charged.
const CANISTER_RANGE := 70.0
const AIRBURST_FRAGMENTS := Vector2(70.0, 110.0)
const AIRBURST_ARM := 30.0 ## The proximity fuse arms this far from the muzzle.
const AIRBURST_PROXIMITY := Vector2(5.0, 8.0) ## It bursts within this of a flying hostile.
const RECOIL := Vector2(8.0, 14.0)
const MUZZLE_SIZE := Vector2(4.2, 6.0)
const HITSTOP := Vector2(0.03, 0.1)

const ROUND_COLORS := {
	Round.APHE: Palette.AMBER, Round.HEAT: Palette.HOT, Round.CANISTER: Palette.CYAN, Round.DRAGON: Palette.FUNGUS,
	Round.APFSDS: Palette.CYAN, Round.AIRBURST: Palette.PERIWINKLE,
}


static func round_from_id(id: String) -> Round:
	for key: Round in ROUND_IDS:
		if ROUND_IDS[key] == id:
			return key
	return Round.APHE


static func tier_calibers(tier: int) -> Array:
	return COAX_TIERS[clampi(tier, 0, COAX_TIERS.size() - 1)]
