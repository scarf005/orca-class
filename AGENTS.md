# Effect lifecycle changes

- Enumerate all production representations of the requested remains/effect before changing lifecycle limits, including CPU particles and detached `Wreck` models. Test the reported death path, not only a particle pool.

# Articulated weapon models

- Separate hull-fixed mounts from aiming pivots. Validate fixed-part transforms, joint connections, muzzle tracking, and whole-module detachment through production aiming and damage paths; inspect neutral and angled renders before declaring the model complete.

# Testing policy

- For articulated models, parenting and clearance do not prove a visible connection: verify actual mesh continuity across each joint.
- Match every test name to the production oracle it claims to cover.
- Gameplay-effect regressions must assert accepted outcomes through the production path, not only events, configuration, or invulnerable fixtures.
- Justify numerical tolerances from the contract or scheduling behavior; prove each critical new oracle with a mutation test.
- Failed, skipped, and runtime-error tests never count as passing.
