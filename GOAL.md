# orca class — Goal

A Star Fox-style action shooter in pastel, ditherpunk 3D. You play Ha Yoon (하윤), driver of the tank
*Orca-class*, pushing through a fungus-infested, abandoned Korean countryside. This goal covers one complete,
polished **Stage 1**, with enemies, a mid-boss, a final boss, power-ups, scoring and a results screen.

The bar: intense, fun, readable, and "one more run" addictive. It must feel hand-made, not like AI slop (see
[Quality bar](#quality-bar)).

## Platform and tech

- Engine: Godot **4.7.2-stable** (latest stable, 2026-08-18; `/home/scarf/opt/bin/godot`). Typed GDScript.
  Forward+ on desktop; Compatibility on Web.
- Target: desktop Linux and Windows, 60 FPS at 1080p on a mid-range GPU, plus desktop browsers through Web export.
- Input: keyboard + mouse (WASD drive, mouse aims turret) and gamepad dual stick (left stick drive, right stick aims).
- Text: Korean by default, switchable to English in settings. All strings go through Godot translation files; no
  hard-coded UI text.
- Runs with `godot --path .`. Headless tests run with `godot --headless --path . -s <test>`.

## Core loop and camera

- Star Fox-style **on-rails stage**: the stage scrolls forward at 80 km/h along a hand-authored road that winds
  through real bends (straights and arcs laid out by arc length). The camera sits high behind the tank so the
  whole corridor reads; the tank strafes fast enough to dodge boss fire, left/right and forward/back relative to
  the rail.
- Throttle control, like Star Fox boost and brake: **overdrive** (surge forward, dodge through danger) and
  **brake** (hold ground, let enemies cross the sights). Both share a heat/capacitor meter.
- The turret aims independently of the hull. A 3D reticle follows the mouse or right stick, ranging to terrain and
  targets, with a lead indicator for moving targets.
- The boss fight switches to an **all-range arena**: free movement in a bounded valley around the boss.

## The tank: Orca-class

Adapted from [`scarf005/orca-class`](https://github.com/scarf005/orca-class) (`models/manifest.json`,
`scripts/player.gd`). This game uses a **100 mm** main gun, by request (orca-class uses 120 mm). Stats below are
starting values for tuning.

| System | Spec | Role |
| --- | --- | --- |
| Hull | Armored tracked hull; high front armor, weak rear; shield/HP bar | Front-facing damage is reduced, so the player learns to face threats |
| 100 mm gun | ~1.0 s reload, direct hit and blast, heavy recoil pushes the tank back | The big punch; one shot kills most small enemies and staggers large ones |
| 8 mm coaxial gun | High rate of fire, low damage, follows the turret | Always-on fire; upgradable (below) |
| RWS: 200 kW laser CIWS | Not fitted at the start: an RWS pickup (the first sits before the first FPV wave) mounts it. Automatic; zaps incoming missiles, rockets, shells and FPV drones in a short radius; heats with each engagement | Defensive layer. Saturation attacks can overheat it, and then the player must dodge |
| Tracks | At speed the tank flattens every building, wreck and ground enemy in its path. Big landmarks (church, branch school, the old zelkova) are modular: each piece breaks on its own, and what rested on it topples. Only the dam stands | Aggressive driving is rewarded |
| Reactive armor | ERA bricks: 4 front, 3 per side, none at the rear | Each brick stops one shaped charge from its facing |
| Bio tail | Three-segment muscular tail with a pink claw; no weapon; acts on its own | Melee, pickup and defense (below) |

### Modules (War Thunder-style)

The hull has an armor bar for kinetic damage, and internal modules that break separately:

| Module | Damaged / destroyed | Exposed from |
| --- | --- | --- |
| Tracks (left, right) | Slower movement | Front, that side |
| Engine | Slower meter refill / no overdrive | Rear |
| Breech | Reload ×1.5 / ×3 | Front |
| Turret drive | Slower traverse | Any |
| Laser RWS | — / knocked off: CIWS gone until another RWS pickup | Sides, and small arms that strike it |
| FCS (gunner's sight) | Soft-lock radius halved, no lead / knocked off: no soft lock, no lead, no range readout | Front, sides, and small arms that strike it |
| Tail | Slower / gone until a regrowth pickup | Rear |

- Shaped-charge warheads (FPV drones, ATGMs) are decided by ERA: a brick on that facing absorbs the hit;
  where there is none left (always at the rear), the hit is fatal and costs a life.
- Small arms (bullets under 40 mm: all enemy machine guns and cannons except the gunship's chin gun) ricochet off the
  armor for no damage, unless they strike the RWS or FCS on the roof. A knocked-off RWS or FCS flies away in flames
  and is not field-repaired: the FCS comes back with a repair pickup or a spare hull, the RWS only with an RWS pickup
  (a spare hull comes without one).
- The crew field-repairs damaged modules one step at a time. A lost tail only returns from a regrowth pickup.
  ERA refills from ERA pickups. A spare hull (a new life) restores everything.
- Enemies have modules too: a UGV hit low loses its tracks and stops; hit high, it loses its weapon. A UAV hit in
  its pusher engine glides into the ground.

Orca-class visual identity to keep: grey-green boxy hull, long main gun with a coax beside it, and the
three-segment biological tail with its pink claw at the rear.

### Tail

The tail carries no weapon (orca-class's 3 MW tail laser is dropped). The driver is busy with the hull and the
turret, so the tail needs no button: it acts on its own, with a short cooldown, and should feel alive, whipping,
coiling and lashing with visible muscle and follow-through. Priorities:

1. **Throw:** a held enemy dangles briefly, then is flung at the aimed target (or the nearest enemy ahead).
   Thrown enemies are projectiles that damage what they hit.
2. **Swat:** a diving drone or a swelling crawler close to the hull is batted away first (a "deflect").
3. **Snatch:** a power-up in reach is yanked straight to the tank.
4. **Grab / stab:** small enemies in reach are grabbed; large ones are stabbed, which staggers them and interrupts
   telegraphed attacks.

The tail also powers the **dash**: double-tap a direction and the claw kicks off the ground to hurl the hull that
way. Sideways it dodges and lashes anything beside the hull (or hurls what the claw holds), forward it surges the
rail, back it digs in to a near-instant stop. Each gives a brief dodge window and gouges the terrain.

Controls are WASD and the mouse only: W/S steer forward and back and double as boost and brake, the left button
fires the coax (it leads whatever the sight soft-locks), the right button fires the main gun. Rounds leave along
the barrel, never more than a few degrees off where the turret points.

The tail is a target: rear hits hurt it, and it can be torn off (see Modules).

### Coaxial upgrades

Each pickup raises the coax one tier; losing a life drops one tier.

| Tier | Coax | Feel |
| --- | --- | --- |
| 1 | 8 mm | Fast, light tracers; pops drones and spores |
| 2 | 15 mm | Heavier thump; chews UGV sensors and light armor |
| 3 | 20 mm | Explosive rounds; small splash |
| 4 | 20 mm + 8 mm | Twin streams |
| 5 | 20 mm + 15 mm | Twin streams, heavier |
| 6 (MAX) | 2 × 20 mm + 8 mm | Wall of fire; the turret mount visibly changes |

Each tier changes the model, muzzle flash, sound and tracer color, not just the numbers.

### Cannon rounds

The default round is unlimited APHE. Pickups load a limited magazine of a special round (e.g. 6 shots), shown on the
HUD. When it runs out, the gun falls back to APHE. Picking up a new type replaces the current one.

| Round | Behavior | Best against |
| --- | --- | --- |
| APHE (default) | Single target plus a small blast | General use |
| HEAT | High single-target damage; ignores armor; can knock parts off the boss | UGVs, boss armor |
| Canister | Short-range shotgun cone of tungsten balls | FPV drone swarms, close fungi |
| Dragon's breath | Incendiary cone; sets fungi and grass on fire; fire spreads | Fungi (they burn), spore clouds |
| APFSDS | Pierces through every enemy in a line; very fast | Lines of UGVs, the boss's rotor mast |
| Airburst (AHEAD) | Detonates at the reticle's range; fragment cloud | UAVs, the helicopter |

Rounds and enemy types form deliberate counters. No round is strictly best, and pickups sit where their counter
matters next.

## Stage 1: Hypha (균사)

An abandoned Korean farming village in early autumn, overgrown by pastel pink, lilac and cream mycelium. Setting
details must be specifically Korean-rural, not generic: terraced rice paddies (논), vinyl greenhouses (비닐하우스),
slate- and tin-roofed houses, stacked soy-sauce jars (장독대), a village hall (마을회관), a country bus stop, a
pavilion (정자), cultivators (경운기), persimmon trees, utility poles with sagging wires, a church with a steeple, a
closed-down branch school (폐교), a reservoir (저수지) with its dam, and a highway overpass.

Target length is 8–12 minutes for a first clear. Sections:

1. **Farm road (농로):** a quiet opening; the combat assist boots up. FPV drones arrive in sparse waves while the player
   learns to aim, fire and let the CIWS work. First coax pickup.
2. **Village:** UGVs come out of alleys; fungal crawlers burst out of greenhouses. Buildings and walls are
   destructible cover. Tempo rises.
3. **Branch school, mid-boss:** a fungal colossus rooted in the schoolyard. Weak points glow; dragon's breath is
   placed right before it.
4. **Reservoir and dam:** UAVs make bombing and strafing runs over the water; FPV swarms rise from the reeds;
   spore storms reduce visibility.
5. **Overpass:** the heaviest mixed wave, a gauntlet under and over the highway. A brief calm, then rotor noise.
6. **Boss: twin-rotor gunship**, in an all-range arena over the reservoir valley (below).
7. **Results:** score, kill %, accuracy, damage taken, time, rank (S/A/B/C), personal bests.

### Enemies

Each enemy has a distinct silhouette, a clear telegraph before it attacks, a satisfying death, and a counter.

| Enemy | Behavior | Telegraph | Counter |
| --- | --- | --- | --- |
| FPV drone | Fast kamikaze swarm; weaves, then dives | Buzzing rises in pitch; its camera light turns red before the dive | Coax, canister, CIWS |
| UGV (tracked) | Armored gun or ATGM carrier; strafes from cover | ATGM: laser designator line, then launch | HEAT, APFSDS; CIWS catches ATGMs |
| UAV (fixed-wing) | Makes bombing and strafing passes; drops loitering munitions | Shadow and dither sweep across the ground before the pass | Airburst, coax |
| Attack helicopter | Paces the tank through the village, reservoir and overpass; alternates gun bursts and rocket pairs | Chin-gun sight beam before firing | A few coax hits, any cannon round; CIWS catches rockets |
| Fungal crawler | Swarms over terrain; bursts into spores | Swells and brightens before bursting | Dragon's breath, ramming |
| Spore spitter | Rooted; lobs arcing spore mortars | Glowing sac inflates | Any cannon round |
| Bipedal walker | Reverse-jointed legs with wheeled feet; skates between lanes, then plants and fires a 15 mm burst or a missile pair | Crouches, eye flashes | Shoot the legs to topple it; grab and throw |
| Quad mech | Heavy four-legged walker with a quad 20 mm flak turret or a mortar | Barrels spin up / impact circles | Shoot legs off (two lost: it collapses) or the turret |
| Fungal colossus (mid-boss) | Large rooted mass; tendril sweeps, spore barrages, spawns crawlers | Tendrils rear up; the ground cracks along the sweep line | Burn the weak points, then shoot the core |

### Boss: twin-rotor gunship

A broad, heavily armed gunship partly overtaken by mycelium, with a rotor on each wing, a chin cannon,
outboard missile racks, ATGMs and flares. Nose and flank plates pop when a shell hits them; three clean cannon
hits on bare airframe bring it down. Each rotor is a separate module: losing one slows the gunship and leaves
it banking at lower altitude; losing both starts its crash. Destroying the chin gun or both missile racks stops
that attack. It fights in three phases, each with new patterns and visible damage:

1. **Hunter:** circles at range, strafes with its chin gun, and fires rocket volleys that test the CIWS heat limit.
2. **Stripped:** below 70% hull (or once every plate is gone) it closes in, pops flares to spoof, fires ATGMs, and
   calls in FPV drones.
3. **Infected:** the fungus takes over. The rotor sheds spores and the attacks become erratic and desperate. It
   finishes with a burning crash into the dam.

Readable patterns, fair dodge windows, and no damage-sponge phases.

## Presentation

### Art direction

- Flat-shaded meshes with a strict, hand-picked pastel palette of about 24 colors for the scenery: sage, mint,
  butter, peach, lilac, sky, blush, with warm grey-greens. Fungus is the loudest color of the land.
- **Ditherpunk post-process:** render at 960×540, upscale with nearest-neighbor, quantize the scenery to the palette
  with ordered (Bayer) dithering. Use dithered fog, shadows, transparency and fade-outs. Keep dither stable in screen
  space and avoid crawling shimmer when the camera moves.
- **Actors pop off the scenery:** enemies, the tank and pickups are drawn in their true saturated colors (never
  quantized to the pastel palette) with a glowing outline around the whole rendered object: hot red for enemies and
  their shots, white for pickups; the tank has none. Outlines show through cover, so nothing hides behind a house.
- Lighting: late-afternoon sun, long dithered shadows, spore haze. The boss arena shifts toward dusk.

### Game feel

Hitstop on big hits; screen shake scaled by source and with a cap; cannon recoil that moves the camera and the
tank; muzzle blasts that flatten grass and kick up dust; debris and persistent scorch marks; fungi that pop with
spores; enemies that stagger. Every weapon has a distinct, punchy sound.

Effects in the spirit of Project Landsword and Metal Slug: oversized, glowing projectiles (a white-hot core in a
dithered colored halo; tracer streaks, with enemy fire as red bolts), star-shaped muzzle flashes and muzzle-brake
jets, cartoon fireballs in hard bands that bloom, cool to smoke and break up (with a shock ring, ground dust ring,
embers and secondary pops), burning debris that trails smoke, lingering smoke columns, burning wrecks, and tread
prints pressed into the ground behind the tank. Ramming at 80 km/h throws debris ahead and jolts the hull; cars are
crushed flat, not blown up. Shake is capped so chaos never blurs the view.

### Mayhem and style

Destruction is the point, as in ULTRAKILL and Metal Slug: destroyed vehicles are blown into the air spinning and
blow up again where they land; every death blast hurts what is packed around it, so kills chain; explosive drums
and gas stations line the road; swarm enemies come in large numbers; weapon pickups and mission start and clear
are announced with huge arcade call-outs. Blasts, debris and wrecks carry on along the attack that caused them;
turrets blow off and cartwheel away. A strict color language makes sides readable at a glance: the tank's fire
is warm yellow, every enemy shot and the rim on every enemy is hot pink-red, and loot is cyan (a beacon pillar and
ring). Projectiles use these saturated accents with ink outlines so they cut through the pastel scene. A style meter ranks play from D to SSS and multiplies score:

- Kills are named by how they happened (crushed, tail whip, thrown, burned, airburst, sky shot, collateral from a
  wreck the tank set off, multikill, deflect, demolition, close call). Repeating the same trick earns less.
- Style drains over time and when the tank is hit.
- From rank B up, mayhem patches the hull a little.

### Combat assist AI

The only voice is the tank's combat assist AI, in the style of the HEV suit in Half-Life: terse, clinical
announcements in Korean or English. It covers threats, module damage, ERA, section hazards and boss phases. There
is no character dialogue.

### Audio

A music track per section, plus a boss theme with a phase change. SFX for every weapon tier, CIWS zaps, drone
buzz, rotor wash, tail lashes, and fungus squelch. Sources must be license-clean with attribution recorded in the
repo.

### Assets from orca-class

Reuse only the orca-class audio (keeping its `ATTRIBUTION.md`) and the DenkiChip Hangul font. All 3D models are
made new for this game; the orca-class voxel models do not fit the style.

### HUD and menus

A minimal HUD that uses symbols wherever a symbol suffices: shield and tail icons with bars, a top-down module
schematic (ERA bricks, tracks, engine, turret, breech, laser, tail, colored by state), shell and bullet glyphs for the
loaded round and coax guns, a laser heat bar, brake/boost chevrons, score, and the style meter. Title screen, pause,
settings (language, volume, mouse sensitivity, screen shake, dither intensity, key rebinding), game over with
instant retry, and a results screen.

### Fungus

The infestation must read as grotesque, not as scattered mushrooms: heaving flesh masses with bracket shelves,
weeping pustules, hanging strands and toothed maws; stalks bursting from the ground; houses and cars with growth
erupting through roofs and windows; livestock husks with fruiting bodies splitting their backs; vein webs and egg
sacs; and towering fungal spires visible across the valley. The growth pulses like living tissue and thickens as the
stage goes on.

## Replayability

- Score attack: the style multiplier, no-damage section bonuses, a kill-% bonus, and ranks.
- Local personal bests per section and for the stage.
- Instant restart; a checkpoint at the mid-boss and at the boss (checkpoint runs are marked as unranked).
- Difficulty: Normal and Hard. Hard remixes enemy placements and increases aggression, not just health.

## Quality bar

"Not AI-sloppy" means:

- No placeholder primitives, generic stock UI, lorem-ipsum text or filler dialogue in the shipped stage.
- Every enemy, round and coax tier looks, sounds and plays differently.
- Encounters are hand-authored and paced (quiet, build, peak, release), not random spawns.
- The Korean rural setting is specific and recognizable, not a generic "village".
- Tuning is tested by actual play; numbers exist to serve feel.
- The code is clean, typed and data-driven (enemy and weapon definitions as resources), with no dead code or
  speculative abstraction.

## Done when

- [ ] Stage 1 is playable start to finish: title → stage → mid-boss → boss → results, with no soft-locks.
- [ ] All listed enemies, the mid-boss, the boss (all three phases), every coax tier, every cannon round and all
      four tail actions are implemented with unique visuals and audio.
- [ ] Every string is available in Korean and English, and switching language works in-game.
- [ ] The ditherpunk pastel look holds up in screenshots of every section. Captures live in `docs/screens/`.
- [ ] Keyboard + mouse and gamepad both work, including rebinding.
- [ ] 60 FPS in the heaviest wave (overpass) and the boss fight on the target hardware.
- [ ] Headless tests cover weapon damage and counters, coax tier up/down, round magazines, CIWS heat and
      intercepts, tail grab/throw/snatch/anchor, boss phase transitions, checkpoint and retry, and score/rank calculation.
- [ ] A full playtest pass is recorded, with the tuning changes it caused.

## Out of scope

Stages 2+, a story campaign, online features, a loadout or shop screen, and voice acting (unless decided
otherwise).
