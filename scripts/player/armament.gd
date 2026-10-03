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

## A real 100 mm gun on the same button as the coax, Star Fox style: a click is a coax burst, a hold past
## TAP_TIME locks the target and charges the shell. Let go early for a quick shell, at full charge for a
## hitscan that pierces.
const SHELL_SPEED := 1700.0 ## Full-charge rounds are hitscan; this only sets their lead (none, in effect).
const SHELL_RANGE := 420.0
const SHELL_DAMAGE := 1500.0
## Tuned live in the duel mode, hence static vars.
## A quick shell is a visible projectile along the barrel, without gravity, at the speed of the charge
## step it left at: one lock box, or two.
static var QUICK_SPEED_1 := 400.0
static var QUICK_SPEED_2 := 400.0


static func quick_speed(power: float) -> float:
	return QUICK_SPEED_1 if stage(power) <= 1 else QUICK_SPEED_2


## The charge at which the first and second lock boxes land; the third is full (tuned live in the
## duel mode). The gun only fires from the first box on, so it cannot be clicked into a rapid fire.
static var STAGE_1 := 0.3
static var STAGE_2 := 0.65


## How many lock boxes a charge has earned: 0 (nothing fires yet) to 3 (full).
static func stage(power: float) -> int:
	return 3 if power >= 1.0 else (2 if power >= STAGE_2 else (1 if power >= STAGE_1 else 0))

static var COAX_BURST_GAP := 0.35 ## Seconds between the coax's bursts while it keeps firing (tuned live in the duel mode).
static var COAX_BURST_ROUNDS := 6 ## Rounds a press fires from the coax (from each gun of the tier), however long the button is held.
static var TAP_TIME := 0.0 ## Seconds a press waits before it locks and starts charging (0: at once).
static var FULL_TIME := 1.0 ## Seconds of hold for a full charge.
static var AUTO_FIRE_TIME := 1.5 ## Seconds of hold at which the gun fires by itself; the button must be pressed again.
static var CANNON_RECOVER := 0.8 ## After a shot the gun cannot fire or charge for this long.
static var LOCK_RADIUS := 64.0 ## 3D-view pixels around the reticle that a charge picks and locks its target within.
const QUICK_DAMAGE := Vector2(800.0, 1500.0) ## APHE quick shell by charge.
const QUICK_RADIUS := Vector2(4.0, 6.0)
const QUICK_BLAST := Vector2(300.0, 600.0)
const APHE_DAMAGE := Vector2(1.0, 2.0) ## Times SHELL_DAMAGE; the full charge uses y, a quick shell QUICK_DAMAGE.
const APHE_RADIUS := Vector2(5.0, 9.0)
static var SHELL_DAMAGE_SCALE := 2.0 ## Multiplies every main-gun shell's hit and blast damage (tuned live in the duel mode).
static var HE_RADIUS_SCALE := 1.6 ## Widens the APHE filler's blast, so a near miss still tears what stands beside it (tuned live in the duel mode).
const APHE_BLAST := Vector2(600.0, 600.0)
const HEAT_STAGGER := Vector2(1.0, 2.5)
const HEAT_RADIUS := Vector2(9.0, 12.0)
const APFSDS_RANGE := Vector2(1.0, 1.4)
const APFSDS_DAMAGE := Vector2(1.0, 1.5)
const CANISTER_SPREAD := 0.13 ## Radians of cone: a wide close-swarm round, fired the moment its one step is charged.
const CANISTER_RANGE := 70.0
const AIRBURST_FRAGMENTS := Vector2(120.0, 160.0)
const AIRBURST_ARM := 15.0 ## The proximity fuse arms this far from the muzzle.
const AIRBURST_PROXIMITY := Vector2(6.0, 8.0) ## It bursts within this of any enemy.
const AIRBURST_FRAGMENT_DAMAGE := 400.0 ## Each fragment of the ring, whatever the shell damage scale: one shell wrecks an ordinary enemy.
const AIRBURST_FRAGMENT_CALIBER := 30 ## Armor in mm at or above this turns the fragments (the gunship's 40 mm does).
static var AIRBURST_SPEED := 110.0 ## The airburst is a slow round you can watch fly (tuned live in the duel mode).
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
