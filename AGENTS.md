# Verification loop

- Commands are in the README and `just --list`. Iterate with `just test <file-filter>[,<filter>...]` (about 10 s);
  the full `just test` takes about 4–5 min, so run it once on final bytes as a tracked background task.
- Many worktrees run Godot at once: never wait on `pgrep godot` or sleep loops; wait for the task notification.
- Visual checks: capture with the `tools/*.gd` scripts through `just capture` and inspect the image; save shots in the
  main checkout's `screenshots/<topic>/` (gitignored, has `.gdignore`). A bare `godot` or `xvfb-run` falls back to the
  desktop's Wayland when Xvfb fails and opens a window over the user's work.
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

# Model art

- Remodelling an actor means a new design from references, built from scratch. The user rejected surface greebles
  ("모델 texture detail을 올리는게 목적이 아니라 모델 생김새를 개선하는게 목적") and the old shapes with more polygons
  and rounded edges ("기존 모델을 폴리곤만 더한거잖아요. 게다가 찰흙같아서 못생겼어요").
