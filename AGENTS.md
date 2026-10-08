# Verification loop

- Commands are in the README and `just --list`. Iterate with `just test <file-filter>[,<filter>...]` (about 10 s);
  the full `just test` takes about 4–5 min, so run it once on final bytes as a tracked background task.
- Many worktrees run Godot at once: never wait on `pgrep godot` or sleep loops; wait for the task notification.
- Visual checks: capture with the `tools/*.gd` scripts under `xvfb-run` and inspect the image; save shots in the main
  checkout's `screenshots/<topic>/` (gitignored, has `.gdignore`).
- Commit the `.gd.uid` file Godot creates beside each new script; delete temporary probe scripts before committing.

# Testing policy

- Match every test name to the production oracle it claims to cover.
- Gameplay-effect regressions assert accepted outcomes through the production path, not only events, configuration,
  or invulnerable fixtures.
- Justify numerical tolerances from the contract or scheduling behavior; prove each critical new oracle with a
  mutation test.
- Lifecycle changes to remains/effects cover every production representation (CPU particles, detached `Wreck`
  models) and the reported death path.
- Articulated models: keep hull-fixed mounts separate from aiming pivots, and verify mesh continuity across each joint,
  muzzle tracking, and whole-module detachment in neutral and angled renders; parenting and clearance prove neither.
