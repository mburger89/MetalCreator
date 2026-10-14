# 7c-core final fixes report

1. BrickPlan/MeshingBudget traps. `BrickPlan.build` now preconditions resolution finite and > 0, throws `.empty` for non-finite bounds, and throws `.tooBig` when the brick grid would overflow. `MeshingBudget` computes the estimate in Double and clamps to Int.max/2, so `check` throws `.tooBig`. Test: `aTinyResolutionIsRefusedNotATrap` (resolution 1e-9).
   Ruling: a non-positive or NaN resolution is a caller bug (precondition); upstream U2 "Auto" resolves it before direct callers.
2. `.empty` was never thrown. `check()` now throws `.empty` when the coarse pass finds no brick (pruning is conservative, so the finer pass would find none either). Test: `aSolidWithNoSurfaceIsRefusedAsEmpty` (disjoint intersect). Ruling: the Task 7 mesher still throws `.empty` for shapes smaller than a voxel (plan test `nothingToMeshIsRefusedWithAMessage`).
3. Baked distance slope. Ruling: not fixable before the baker exists; recorded as a binding requirement with a test in the plan's Task 5 (GradingBaker): add `max(0, blocks.lipschitz - 1)` per baked leaf to `Grading.slope`.

Verification: focused suites pass (14 tests); full `swift test` and swiftlint results below.

Results: full `swift test` exit 0, 12 "Test run with" lines, 601 tests in 115 suites passed, no "recorded an issue"/"failed after". The only change after that run was a pure helper extraction in BrickPlan (`brickCounts`) to satisfy function_body_length; the focused suites were re-run (14 pass). `swiftlint lint --strict`: 0 violations.
