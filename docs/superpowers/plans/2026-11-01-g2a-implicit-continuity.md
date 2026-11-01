# G-a: Implicit blend continuity — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** G1, G2 or G3 smooth union, subtract, intersect, lattice skin and strut joints.

**Architecture:** A `BlendContinuity` enum travels with every polynomial smooth minimum in `ImplicitSolid` (and `StrutLattice`'s
node blend); the CPU evaluator, the MSL library and its HLSL twin get one smooth-minimum function per continuity, chosen by the
compiler from the tree's structure. Nodes expose a `continuity` integer socket; old files migrate to G1.

**Tech Stack:** Swift 6.4, Swift Testing, Metal (MSL text), HLSL via the SDL backend.

**Spec:** `docs/superpowers/specs/2026-11-01-g2-surfacing-design.md` §G-a.

## Global Constraints

- Swift Testing; `swiftlint lint --strict` 0 (with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`); 12 "Test run with"
  lines on macOS and on Linux (`scripts/linux-test.sh test`); only the known `HLSLEngineTests.onTheCutTheHLSLEngineAgreesWithTheMetalEngine` failure.
- Every float computation in HLSL is `precise` (D21). Edit an MSL library function and its HLSL twin together.
- Width meaning unchanged: `h = max(k − |a − b|, 0) / k`; `k = 0` is plain min.
- Formulas: G1 `min(a,b) − h²·k/4`; G2 `min(a,b) − h³·k/6`; G3 `min(a,b) − h⁴(h² − 6h + 10)·k/32` (erratum 2026-11-01: C3, deepest dip 5k/32, dipSlope 5/32).
- Old files evaluate to the same geometry (G1). New nodes default to G2.
- The field Smooth Blend node stays quadratic (non-goal).

## Review Focus

1. A pre-G-a file with a graded (field) blend opens as G1 and meshes identically (same triangle count, same vertices within 1e-9).
2. A blend width of 0 at every continuity is a plain min (no division by zero, CPU and GPU).
3. A union of three or more shapes chains the chosen continuity at every step, on CPU and GPU alike.
4. The lipschitz bound for a graded G3 blend is never below the sampled slope (no missed surface in `BrickPlan`).
5. A Strut Lattice saved at typeVersion 1 runs both migrations (blend 0, then G1) in order.

---

### Task 1: `BlendContinuity` and the CPU smooth minimums

**Files:**
- Create: `Sources/CreatorGeometry/Fields/BlendContinuity.swift`
- Modify: `Sources/CreatorGeometry/Fields/FieldMath.swift` (smoothMinimum gains a continuity), `Sources/CreatorImplicit/Solid/ImplicitSolid.swift`
  (union/subtract/intersect cases), `ImplicitSolid+Lipschitz.swift`, every `ImplicitSolid` switch that breaks, `CPUEvaluation.swift`,
  `CPUEvaluation+Lattices.swift`, the strut lattice value (`Sources/CreatorImplicit/Lattice/StrutLattice*.swift`)
- Test: `Tests/CreatorGeometryTests/BlendContinuityTests.swift`, `Tests/CreatorImplicitTests/ImplicitSolidPropertyTests.swift`

**Interfaces — Produces:**
- `public enum BlendContinuity: Int, Hashable, Sendable, Codable, CaseIterable { case g1 = 0, g2 = 1, g3 = 2 }` with
  `public var dipSlope: Double` (the bound on ∂dip/∂k: g1 0.25, g2 1/6, g3 5/32, pinned by test) and `public var label: String` ("G1", "G2", "G3").
- `FieldMath.smoothMinimum(_ a: Double, _ b: Double, width k: Double, continuity: BlendContinuity = .g1) -> Double` (keep the existing
  call sites' behaviour through the default; the field node keeps calling it without a continuity).
- `ImplicitSolid.union(_:blend:continuity:)`, `.subtract(…continuity:)`, `.intersect(…continuity:)` with `continuity: BlendContinuity`;
  `StrutLattice` gains `nodeContinuity: BlendContinuity`. `description` mentions the continuity only when not g1.

- [ ] **Step 1: Failing tests** `eachContinuityMatchesItsFormula` (closed forms above at 20 points), `zeroWidthIsMin` (all three),
  `continuityAtTheBlendEdge` (finite differences at `|a − b| = k`: G1 value and first derivative continuous, G2 also the second,
  G3 also the third; each tested to 1e-6 relative), `deepestDipIsAtEquality` (k/4, k/6, 5k/32), `dipSlopeBoundsTheSampledSlope`
  (sample ∂dip/∂k over a grid of `|a−b|/k` in [0,1]; max ≤ `dipSlope`, and within 1 % of it).
- [ ] **Step 2:** Run `swift test --filter BlendContinuityTests`; expect compile failure.
- [ ] **Step 3: Implement** the enum, the formulas, the cases (lipschitz: `max(1, children) + blend.slope × continuity.dipSlope`),
  CPU evaluation through `FieldMath.smoothMinimum(…, continuity:)`, strut joints likewise.
- [ ] **Step 4:** `swift test --filter 'BlendContinuityTests|CreatorImplicitTests'` — the GPU suites will fail to compile or
  disagree until Task 2; if they are blocked by compile errors only, stub the compiler to emit G1 for every continuity and mark that
  stub `// Task 2` (the GPU agreement for G2/G3 fixtures lands in Task 2). Everything else passes.
- [ ] **Step 5: Commit** `feat(implicit): blend continuity on the CPU`.

### Task 2: GPU smooth minimums (Metal and HLSL)

**Files:**
- Modify: `Sources/CreatorImplicit/GPU/ImplicitShaderLibrary.swift` (+`+Lattices`), `HLSLShaderLibrary.swift` (+`+Lattices`),
  `ImplicitCompiler.swift` (the `combine` emission and the strut call), `Tests/CreatorImplicitTests/Support/MetalSourceDigests.swift`,
  `GPUFixtures.swift`, `ImplicitCompilerTests.swift`
- Test: the GPU agreement suites (`GPUAgreementTests`, `GPUMeshAgreementTests`, `HLSLEngineTests`, `HLSLSourceTests`)

**Interfaces — Consumes:** Task 1. **Produces:** MSL `smoothMin`, `smoothMin2`, `smoothMin3` (G1 keeps today's name and text, so
every G1 digest is unchanged) and their HLSL twins; the compiler picks by `continuity`.

- [ ] **Step 1: Failing tests:** GPU fixtures `unionG2`, `subtractG3`, `strutsG2` (in `GPUFixtures`, run by every GPU suite);
  `ImplicitCompilerTests` asserts the text of `smoothMin2`/`smoothMin3` appears only when a tree uses them; `g1DigestsAreUnchanged`
  (every pre-existing digest in `MetalSourceDigests` still matches).
- [ ] **Step 2:** Run them; expect failures.
- [ ] **Step 3: Implement**; record the new fixtures' digests (the `MSLDIGEST` helper in `HLSLSourceTests`); remove Task 1's stub.
- [ ] **Step 4:** `swift test --filter CreatorImplicitTests` on macOS (Metal and MSL-runtime HLSL paths), then
  `scripts/linux-test.sh test --filter CreatorImplicitTests`.
- [ ] **Step 5: Commit** `feat(implicit): G2 and G3 smooth minimums on the GPU`.

### Task 3: Nodes, migration and a zebra check

**Files:**
- Modify: `Sources/CreatorNodes/Implicit/ImplicitCombining.swift`, `ImplicitUnionNode.swift`, `ImplicitSubtractNode.swift`,
  `ImplicitIntersectNode.swift`, `Lattices/LatticeSetup.swift`, `Lattices/LatticeFill.swift`, `TPMSNode.swift`, `StrutLatticeNode.swift`,
  `VoronoiLatticeNode.swift`
- Test: `Tests/CreatorNodesTests/Implicit/ImplicitCombineNodeTests.swift`, `LatticeSkinBlendTests.swift`, a new
  `Tests/CreatorNodesTests/Implicit/BlendContinuityMigrationTests.swift`, `Tests/CreatorImplicitTests/BlendZebraTests.swift`

**Interfaces — Consumes:** Task 1. **Produces:** socket `SocketSpec("continuity", .integer, defaultValue: .integer(1), range: 0...2)`
(option index into `BlendContinuity`), shown as a segmented control "G1 / G2 / G3" right after the blend in each inspector;
`ImplicitCombining.continuityMigration(_ node:)` stores `.integer(0)` when absent. typeVersions: Union/Subtract/Intersect 1 → 2;
TPMS/Strut/Voronoi 2 → 3 (their `migrate` applies `sharpJoin` when `from < 2`, then the G1 store when `from < 3`).

- [ ] **Step 1: Failing tests:** `aNewUnionIsG2`, `continuityReachesTheSolid` (each index 0…2 gives that case),
  `aSavedUnionOpensAsG1` (decode a typeVersion-1 node through `GraphFileIO`; continuity 0 and the meshed result identical to
  today's: same triangle count, vertices within 1e-9), `aVersionOneStrutLatticeRunsBothMigrations` (blend 0 and continuity 0),
  `oneContinuityGovernsTheSkinAndTheJoints` (Strut Lattice), and `aG2UnionHasNoZebraKink`: mesh a sphere-sphere union at G1 and
  G2, evaluate `ZebraBand.value` from the mesh normals along a line across the blend's edge, assert the G1 band's derivative jumps
  there and the G2's stays within 10 % of its neighbours.
- [ ] **Step 2:** Run; expect failures.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** `swift test --filter 'CreatorNodesTests|CreatorImplicitTests'`, lint.
- [ ] **Step 5: Commit** `feat(implicit): continuity on Union, Subtract, Intersect and the lattices`.

### Task 4: Records

- [ ] CLAUDE.md: the Implicit geometry paragraph notes `BlendContinuity` (formulas, default G2, the typeVersions). Human checks: a
  new group **GA** in `docs/verification/human-checks.md` (G1 vs G2 vs G3 union under zebra; an old file opens unchanged; strut
  joints G2).
- [ ] Full `swift test` (12 lines), lint, `scripts/linux-test.sh test` (12 lines). Commit `docs(implicit): blend continuity records`.
