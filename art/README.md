# Actor models

Edit `actors/<actor>.blend`, then run:

```sh
export BLENDER=/path/to/blender
just export-actors # or: just export-actors tank gunship
just import
just test actor_
just test-actor-export
```

Blender is needed only for editing/exporting. `actors/.gdignore` excludes the sources
from Godot's importer and release builds. Commit both the edited `.blend` and its
`assets/actors/*.glb` export. The exporter never saves over a source file.

## Editing contract

- Hidden objects marked `orca_part` are runtime parts. Keep their names and material
  slots. `Assembly` collections show linked copies at the production bind poses;
  editing a linked copy's mesh edits the runtime part too. Toggle collections for
  weapon variants. Unused weapons, attack props and deformation templates remain
  available among the hidden parts.
- Edit mesh-local geometry in Edit Mode, including the `Color` vertex attribute.
  Object transforms are only the authoring layout; gameplay owns pivots, hit areas,
  muzzle offsets and attachment transforms. Do not use object scaling to resize a part.
- Materials name shader roles: `lit`, `glow`, `flesh`, `flesh_glow`, `vivid_lit`,
  `vivid_glow`. Godot maps these to the existing LowPoly materials. Per-instance
  eye flashes, rotor blur overrides and actor layers remain code-owned.
- Apply modifiers before export. Keep flat shading unless intentionally changing it.
  Import settings disable position compression, LODs, light baking and generated
  tangents. Normals pass through the native Blender/glTF/Godot normal encodings.
- Shared parts (tracks, wheels, rotor blades) have one mesh datablock; runtime
  instances reuse the same imported Mesh. Alternate weapons have separate objects
  in the same file. Crawler assembly previews show the unit surfaces before their
  random displacement; gameplay poses the tank's tail.

## Coverage

| Source | Representations |
| --- | --- |
| tank | Hull, tracks, turret, barrel, RWS, FCS; 8/15/20 mm coax; five tail segments and knuckles, palm, left/right flukes |
| crawler | Left/right legs; unit body/crown/spot surfaces for per-spawn deformation |
| spitter | Root base, stalk, sac |
| ugv | Gun/ATGM and supply hulls, turret, both barrels, eye |
| walker | Gun/missile variants share body, eye, arm, pod/lid, thighs/shins/feet/wheels |
| quad_mech | Flak/mortar, body/turret, left/right thighs/shins, wheel |
| fpv_drone | Body, rotors, light; all approach/pursuit patterns share geometry |
| uav | Bomb/strafe body and propeller; strafe gun |
| helicopter | Body, main/tail rotors, chin gun, rocket pods |
| tiltrotor | Body, ramp, nacelles, blades, door gun; all squad choices share geometry |
| colossus | Body, three distinct nodes/caps, core, nine tendril segments, spike/geyser/strip/puff attack parts; all phases |
| gunship | Body, masts/blades/discs, gatling mounts/barrels, chin, flank/nose armor, racks, cannon, bay, three fungus templates; all phases |
| flare | Decoy body: an enemy-team Entity that intercepts shells, not just a particle |

Only Crawler bodies and Gunship fungus need per-spawn mesh deformation. `ActorDeform`
uses the authored unit surfaces and the original random displacement, radii and
placement; it does not regenerate primitive topology. Tail stretching, aiming,
rotors, blinking, swelling, phase visibility and destruction still transform nodes
or per-instance materials. Detached wrecks retain the same imported resources.
Particle debris, smoke, trails, projectiles, pickups and scenery are outside this
migration; their lifecycle limits are unchanged.

`tests/fixtures/actor_geometry.json` records oriented-triangle fingerprints from
production builders at `32ac4a7`, including seeded random bodies. Update the relevant
fingerprint only after reviewing an intentional art change; do not refresh it to
hide an export regression. `tools/actor_inventory.gd` enumerates runtime variants.
