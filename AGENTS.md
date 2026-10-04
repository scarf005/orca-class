# Testing policy

- Match every test name to the production oracle it claims to cover.
- Gameplay-effect regressions must assert accepted outcomes through the production path, not only events, configuration, or invulnerable fixtures.
- Justify numerical tolerances from the contract or scheduling behavior; prove each critical new oracle with a mutation test.
- Failed, skipped, and runtime-error tests never count as passing.
