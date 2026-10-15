# 7c-1g GPU Meshing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Marching cubes runs on the GPU: `ImplicitGPUEngine` gains a mesh-bricks requirement, `MetalImplicitEngine` implements it (the CPU mesher's case table, one vertex per lattice edge by a global edge key, the Newton snap, triangles through an atomic cursor), `ImplicitMesher` uses it whenever the evaluator's engine provides one, and a CPU-against-GPU agreement suite holds the two to the same topology and to 1e-4 mm. Rows i-1 and i-2 of `ImplicitBench` are re-measured on that path.

**Architecture:** The protocol speaks plain values: a `BrickMeshRequest` (lattice origin, voxel size, brick coordinates, snap flag) in, a `BrickMesh` (flat position, normal and index arrays) out, so no GPU type crosses it and an SDL3 GPU compute engine (track xp-c) implements the same requirement. The engine's maths is portable text and data (`BrickLattice` numbers the lattice edges in a window around the bricks so the keys fit 32 bits wherever the part is; `MarchingCubesBuffers` is the CPU's `MarchingCubesTable` as one flat buffer; `ImplicitMeshShaderLibrary` is the Metal source of five kernels appended to a compiled solid's `sdf`); only `MetalImplicitEngine+Meshing.swift` touches Metal. The CPU mesher is not changed: it stays the reference and the fall-back, and `ImplicitMesher` falls back to it, silently, when the engine says unsupported, fails, returns arrays that do not fit, or the request is beyond the engine's limits.

**Tech Stack:** Swift 6.4 (strict concurrency), Swift Testing, SwiftPM, Metal (runtime-compiled Metal Shading Language, no `.metal` files), MetalUI untouched. No third-party libraries, no new target, no `Package.swift` change.

**Spec:** `docs/superpowers/specs/2026-10-13-implicit-lattices-design.md` §4.1 to §4.3, §6 (rows i-1 and i-2) and §7, and its **Errata D11** (portability) and **D13** (meshing runs on the GPU too), under the parent spec `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` with all its Errata. Base code: the 7c-core plan `docs/superpowers/plans/2026-10-13-7c-core.md` (**not merged yet**; this plan was written and verified against its full implementation at branch `r2`, HEAD `60f1c2d`, and uses its real names: `ImplicitGPUEngine`, `GPUBatchEvaluator`, `ImplicitGPUEngines`, `MetalImplicitEngine`, `ImplicitMesher`, `BrickPlan`, `PreviewSchedule`, `MeshTopology`, `GPUAgreementTests`). Start this branch from 7c-core once it merges. That plan's user decisions U5 (7c-1g is a separate plan, this one) and U6 (the benchmark rows are records, never gates) are what this plan follows.

## Files shared with other tracks

7c-core is the only track whose code this one builds on; 7c-2 (lattices), 7c-3 (mesh tools) and xp-c (the SDL3 engine) touch the same files from the other side. The side that merges second keeps the following. New files of this plan that nobody else edits are listed under "File structure".

| File | Who else touches it | What the side that merges second keeps |
|---|---|---|
| `Sources/CreatorImplicit/GPU/ImplicitGPUEngine.swift` | 7c-core (defines it), xp-c | the requirement `meshBricks(_:_:progress:)` and its default (throws `.unsupported("meshing bricks")`), beside the protocol's other members (`name`, `deviceName`, `compile` with its default, `prepare`, `evaluate`, `cancel`) |
| `Sources/CreatorImplicit/GPU/GPUBatchEvaluator.swift`, `Sources/CreatorImplicit/Sampling/ImplicitBatchEvaluator.swift` | 7c-core, 7c-3 (its streamed export, D12, adds a brick-by-brick entry point here) | `ImplicitBatchEvaluator.meshBricks(_:progress:)` with its `nil` default, and `GPUBatchEvaluator.meshBricks` mapping `ImplicitCompileError` to `nil` (the CPU mesher then runs) and passing `CancellationError` through |
| `Sources/CreatorImplicit/Meshing/ImplicitMesher.swift` | 7c-core, 7c-3 | `mesh(_:resolution:quality:snap:source:progress:)` unchanged in signature and result; `meshReportingPath` and `MeshingPath`; the order "ask the evaluator for the mesh first, then the CPU loop"; the `isConsistent` guard. 7c-3's windowed export must build its own `BrickMeshRequest` per window and call `evaluator.meshBricks`, not reach into the engine |
| `Sources/CreatorImplicit/Metal/MetalImplicitEngine.swift` | 7c-core, 7c-2 | the members this plan made internal for the meshing extension (`device`, `queue`, `epoch`, `Prepared`, `buffers(for:)`) and the four stored properties for meshing (`meshPipelines`, `meshTuning`, `meshCompileCount`, `meshesMade`) |
| `Sources/CreatorImplicit/Metal/ImplicitCompiler.swift`, `ImplicitShaderLibrary.swift` | 7c-core, **7c-2** (adds lattice cases) | **the meshing kernels call `sdf(e, p)` and build `Env e = { P, I, tables, pool, images }`.** If 7c-2 changes `Env`, the `sdf` signature or the five data buffers, `ImplicitMeshShaderLibrary` (its `Binding` constants and the `Env` line in `meshSample` and `meshPlace`) and `MetalImplicitEngine.bind(...)` change with it, and `GPUMeshAgreementTests` must run over the new lattice fixtures (7c-2 adds each to `ImplicitFixtures`/`GPUFixtures`, which this suite reads) |
| `Tests/CreatorImplicitTests/Support/StubGPUEngine.swift` | 7c-core, xp-c | the `Meshing` enum and `meshRequests`, which the portable mesher tests need |
| `Tests/CreatorImplicitTests/Support/GPUFixtures.swift` | 7c-core, 7c-2 | the fixtures list the agreement suite iterates (`GPUFixtures.all`); a fixture that has no surface must be excluded by name in `GPUMeshAgreementTests.names`, as "implicit leaf" is |
| `Tests/CreatorAppTests/Bench/ImplicitBench.swift`, `ImplicitBenchFixtures.swift`, `ImplicitBenchFixturesTests.swift` | 7c-core, 7c-2 (swaps the sheet for the TPMS node), 7c-3 (rows i-5, i-6) | `Sheet.band`, `ImplicitBenchFixtures.solid(of:)` and the `i-1m` test (they take the sheet's solid whatever builds it); the rows' ids and targets |
| `CLAUDE.md`, `docs/verification/performance.md`, `docs/verification/human-checks.md` | every track | **Not append-only: Task 5 rewrites four existing sentences, and 7c-2 and 7c-3 will rewrite the same ones, so expect text conflicts and resolve them as follows.** `CLAUDE.md`: (1) the "not built" sentence of the 7c-1 paragraph is a list, "Lattices (7c-2), the mesh tools, checks and 3MF (7c-3) and the mappings (7c-4) are not built, nor ... meshing on the GPU ... and the streamed export (D12, with 7c-3)": **each track deletes only its own item** (this plan deletes only "meshing on the GPU (spec Errata D13, plan 7c-1g)" and the clause "until they are, meshing runs on the CPU"; if 7c-3 merged first it has already removed the streamed export, if 7c-2 merged first the lattices), so the second side keeps the other tracks' items and this plan's removal; (2) the GPU-engine parenthetical "(`GPU/`: prepare, compile, evaluate a batch, mesh bricks, cancel)": keep "mesh bricks" and whatever the other side added; (3) the new 7c-1g paragraph and the new "Meshing on the GPU" sentences in the `ImplicitMesher` paragraph are additions, keep both sides'. `performance.md`: the intro paragraph's sentence "The first run below measured Metal evaluation with the CPU mesher; the 7c-1g run after it measures i-1 and i-2 with the GPU mesher" replaces "Until then these rows measure Metal evaluation with the CPU mesher, and i-2 and i-4 are expected to miss"; the second side keeps the 7c-1g sentence and adds its own (7c-3 adds its streamed-export sentence for i-4 beside it, 7c-2 its gyroid one), and keeps the "7c-1g run" block and its raw output. `human-checks.md`: IM-13 is added after IM-12 (other tracks add their checks after it, or renumber theirs; keep every check). |
| `Package.swift`, `Sources/CreatorImplicit/Meshing/MarchingCubesTable.swift` | xp-1 (moves targets, portable list), 7c-core | not touched by this plan. xp-1's portable list must keep `CreatorImplicit` and `CreatorImplicitTests` in it; the Metal files are guarded by `#if canImport(Metal)` and need nothing else |

xp-1's portable-code rules are met without exception: the new portable files import only `CreatorGeometry` or nothing (no Metal, simd, CoreGraphics, `os`, CryptoKit); the three portable test files run on Linux and Windows, and the Metal ones are inside `#if canImport(Metal)` and skipped without a device. On Linux a full `swift test` loses the 16 Metal-only tests of this plan and keeps the other 26.

## Global Constraints

Every task's requirements include these (copied from 7c-core's, with this plan's counts).

- Swift 6 strict concurrency (`swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`). No `@unchecked Sendable` or `nonisolated(unsafe)`; shared mutable state is an actor, `Mutex` or `@MainActor`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), never XCTest. Models are `@MainActor @Observable`; behaviour lives in models and views are thin; one type per file (an extension of a type, or a small helper beside it, is fine); no force unwraps, no `try!`; no `DispatchQueue`; `Task.sleep(for:)`; `FormatStyle`, never `String(format:)` or a `Formatter` subclass.
- `swiftlint lint --strict` reports zero violations (lines up to 140 columns, which counts the lines of a multi-line string, trailing commas in multi-line collection literals, function bodies up to 50 lines).
- **A full `swift test` passes only if** the exit code is 0, no line says "recorded an issue" or "failed after" (Swift Testing uses glyphs, not ✘), and **12** "Test run with" lines appear: 7c-core's base has 12 (it added the `CreatorImplicitTests` target) and this plan adds no target. Counts are "master + N", master being 4,163.
- **`CreatorImplicit` is portable (Errata D11).** Nothing in it imports Metal, simd, CoreGraphics, `os` or another Apple-only framework except files named `Metal*.swift`, each wholly inside `#if canImport(Metal)`; no other file names an `MTL…` type. `ImplicitPortabilityTests` enforces it (it is run in Tasks 1 and 3 and passes unchanged). The Metal source of the kernels is plain text in `ImplicitMeshShaderLibrary` (not a `Metal*.swift` file).
- The CPU mesher (`MeshBuilder`, `ImplicitMesher.snap`, `MarchingCubesTable`) is the reference and is not edited by this plan.
- MetalUI gaps are logged in `docs/metalui-gaps.md` (entry and summary row) and never worked around; this plan found none. Never modify `../MetalUI`, never edit the MetalUI path in `Package.swift`, never take screenshots.
- Never `pkill` or `killall` by a broad pattern (`swift-test`, `swift-build`, `xctest`): other sessions run `swift test` on this Mac. Kill only your own processes, by PID or by a pattern containing your own worktree path.
- Run every command from the worktree. Commit messages end with the session's attribution lines.
- Verification per task is light: `swift build --build-tests` (no warning beyond the baseline's `ContextMenuTests.swift` one and linker `ld: warning` lines), the touched suites with `--filter`, and `swiftlint lint --strict`. One full `swift test` runs after the last task.

## Review Focus

Inputs and conditions the spec implies and the happy path does not exercise, most likely to bite first. Each has its test in the task named.

1. **The GPU mesher silently not running.** A kernel that fails to compile (this plan's own first run hit `vertex`, a reserved word in Metal) throws `.engine`, `GPUBatchEvaluator` maps it to `nil`, and the CPU mesher quietly makes a correct mesh: every test that only looks at the mesh passes with the GPU path dead. Expected: tests and benchmarks assert `meshReportingPath(...).path == .gpu`, and the rows that go through the Mesh node (i-1, i-2), which cannot see the path, assert that the engine's `meshesMade` rose by a mesh a round. Tests: Task 3 `aSphereMeshedOnTheGPUIsAClosedManifoldWithTheRightVolume`, Task 4 `theGPUMeshAgreesWithTheCPUMesh`, Task 5 `theFirstPassOnTheGPUMesherAndOnTheCPUMesherOverGPUValues`, and the `expectMeshedOnTheGPU` check of rows i-1 and i-2.
2. **A seam where bricks meet, above all between two batches.** A vertex on a brick face must be one vertex whichever brick (and whichever batch of 4,096) reaches it, or the mesh has a crack the topology check would call open. Expected: closed manifold, the same set of vertices and triangles with 7 bricks a batch as with all of them. Tests: Task 4 `manySmallBatchesMakeTheMeshOneBigBatchDoes`, Task 2 `aBrickFaceEdgeHasOneKeyFromBothBricks`, Task 4 `theGPUMeshAgreesWithTheCPUMesh` (every fixture is a closed manifold).
3. **An engine that returns nonsense** (an index past the vertices, a normal missing, a partial triangle). Expected: the mesher does not trust it and meshes on the CPU, not a crash in the viewport. Tests: Task 1 `arraysThatDoNotFitTogetherAreNotTrusted`, `anEngineThatFailsToMeshFallsBackToTheCPU`.
4. **A part far from the origin, or bricks very far apart.** Edge keys are 32 bits; a lattice counted from the origin would overflow for a part at 4 m, and a window of two bricks 10 m apart cannot be numbered at all. Expected: keys are counted from the window's lowest brick, so a far part meshes on the GPU; a window beyond 32-bit keys is unsupported and the CPU does it. Tests: Task 4 `aPartFarFromTheOriginIsMeshedInASmallWindow`, `bricksTooFarApartForThirtyTwoBitKeysAreUnsupported`, Task 2 `aWindowTooBigForThirtyTwoBitKeysIsSaidSo`.
5. **An edit or a cancel in the middle of a mesh.** Expected: the mesh in flight ends with `CancellationError` at its next batch (never swallowed into a CPU fall-back that restarts the work), the next mesh runs normally. Tests: Task 1 `aCancelledEngineIsNotSwallowed`; Task 4 `cancellingTheTaskEndsAMeshAtItsNextBatchAndNotTheNextMesh` and `anEngineCancelEndsAMeshAtItsNextBatchAndNotTheNextMesh`, which cancel from the progress callback and from the engine's `afterBatch` hook, at a known batch, and expect the throw (not "a throw or a whole mesh"); deleting either cancellation check of `checkRunning` fails one of them.
6. **A table that is too small, or a mesh that does not fit.** Expected: the table doubles until it fits; past its limit (or a buffer the device cannot make) the engine says unsupported and the CPU does it. Tests: Task 4 `aTableThatIsTooSmallIsDoubledUntilItFits`, `aMeshBeyondTheLargestTableIsLeftToTheCPU`.
7. **No Metal at all.** Expected: the portable tests run (the mesher's choice, the lattice, the table buffer, the comparison yardstick) and the Metal ones are skipped, the module still free of Apple-only imports. Tests: Task 1 and Task 2 suites, `ImplicitPortabilityTests`.
8. **A command buffer too long for the GPU.** The place step does nine evaluations of the solid for each occupied slot of a table that may be 2^27 slots; one dispatch over it could run past the GPU's watchdog (an `.engine` error, a wasted CPU fall-back, and possibly a reset that affects other apps). Expected: the number and place steps run over the table in ranges of `slotsPerDispatch` slots (2^20), a command buffer each, with a cancel check between, and the mesh is the same as with one range. Test: Task 4 `aMeshOfSeveralRangesOfSlotsIsTheMeshOneRangeMakes`.
9. **A mesh with the right vertices and the wrong shading or winding.** Vertex positions can agree while the stored normals are inverted (the shading is inside out) or every triangle is wound clockwise (back faces are culled and the volume is negative); `MeshTopology` checks only that triangles agree with each other. Expected: normals within 0.9999 of the CPU's (same samples) and 0.999 (whole pipeline) by dot product, and the enclosed volume equal and positive, on every fixture. Tests: Task 4 `theGPUMeshAgreesWithTheCPUMesh` (`smallestNormalDot`, `signedVolume`), `MeshComparisonTests.aNormalTurnedAroundOrTippedIsCountedInSmallestNormalDot`.

## User decisions

Product behaviour the spec leaves open. Each is built for the recommended default.

| # | Question | Options | Recommended (built) |
|---|---|---|---|
| U1 | Where the GPU mesher is used | (a) every mesh the engine can take, preview passes and export, with the CPU as the fall-back (b) preview passes only; an export always meshes on the CPU reference (c) a setting | (a): D13 asks for GPU meshing without limiting it to the preview, and the fall-back covers what does not fit. Costs: an export's triangle order is not reproducible (U3); **`MeshingBudget.check` still runs first for an export and still uses the CPU mesher's estimate (about 100 bytes a triangle), so the GPU path does not widen which exports are accepted**; and an export that is accepted may hold up to about three copies of its mesh at once (the GPU's buffers, the Swift arrays read back from them, and the `TriangleMesh`), so i-4's 4 GB peak is not expected to hold for the largest exports and is not re-measured here (it is 7c-3's, with the streamed export). (b) is a one-line change in `ImplicitMesher` (skip the engine when `quality == .export`). |
| U2 | What "vertices within 1e-4 mm after the snap" (D13) is measured as | (a) two comparisons: the GPU mesher against the CPU mesher **on the same sample values**, every vertex within 1e-4 mm (measured 1.7e-5); and the **whole GPU pipeline against the CPU pipeline**, the surfaces within 1e-4 mm along the normal (measured 1.9e-5) and the vertices within 2e-3 mm (measured 9.1e-4) (b) the whole pipeline, vertex to vertex, 1e-4 mm (c) the whole pipeline, vertex to vertex, 1e-3 mm | (a). (b) cannot hold: where a lattice edge runs nearly tangent to the surface, a 1e-6 difference between the float GPU evaluator and the double CPU evaluator slides the vertex 1e-4 to 9e-4 mm *along* the surface, and 3 of the 25 fixtures miss (noise offset 9.1e-4, graded centred shell 1.6e-4, graded offset 1.0e-4). The surface itself agrees; the suite says so and keeps (b)'s number where it is meaningful. Triangle counts are within 0.1% (they are equal on every fixture). **Both statements are for parts within a few hundred millimetres of the origin:** the output positions are `Float`, and one unit in the last place is 5e-4 mm at 4 m from the origin, more than 1e-4 mm, so a far part cannot meet D13's number whatever the mesher does (`aPartFarFromTheOriginIsMeshedInASmallWindow` checks its bounds to 1 mm only; the Mesh node already warns past 10,000 mm). |
| U3 | The order of vertices and triangles in a GPU mesh | (a) the threads' order: the same set every time, the arrays in a different order (b) a canonical order, from a sort or a scan pass | (a): nothing reads the order, the cost of (b) is another pass over millions of entries, and the agreement suite compares sets. Cost: two STL exports of one shape differ byte for byte though they hold the same triangles (IM-13 says so). |
| U4 | Telling the person that meshing fell back to the CPU | (a) say nothing; the mesh is the same, only slower (b) show "Running on the CPU" for meshing as for evaluation | (a): the CPU mesh is correct, `Selection.warning` is about a solid the GPU cannot evaluate, and a second reason for the same words would need a channel from the mesher to the node's warnings that nothing else wants. The path is visible to tests and benchmarks (`meshReportingPath`, `MetalImplicitEngine.meshesMade`). |
| U5 | How fine the Auto preview now gets. `PreviewSchedule.next(after:seconds:)` with `.automatic` goes on to a pass half the voxel size (four times the triangles) while four times the last pass's time is under 1 s. On the CPU the bench sheet's first pass took about 366 ms, so Auto stopped after it (0.78 mm, about 0.5 million triangles). At the GPU's 25 to 60 ms it goes on: 0.78, 0.39 and about 0.2 mm, ending near 16 times the triangles (about 8 million for the sheet), with more memory and a slower orbit in the viewport. Nothing in this plan changes `PreviewSchedule`; this is what its rule does with a faster mesher | (a) let Auto refine as far as the time budget allows, now finer (b) cap the GPU's Auto preview at a triangle count or a finest resolution (c) keep the CPU's timing as the schedule's yardstick, so Auto stays as coarse as it was | (a): "the finest resolution that meshes in about a second" is what Auto says, and a finer preview is the point of a faster mesher. It is built that way (no code). IM-13 asks the person to orbit the last pass and watch the frame rate and the memory; if that is too heavy, (b) is a small change in `PreviewSchedule` (7c-core's file) and should be decided before 7c-2's lattices, which make heavier surfaces still. |

## Risks

- **The kernels are verified on this Mac's GPU only.** The agreement suite holds them to the CPU on 25 fixtures and is skipped without a device. 32-bit atomics and compare-and-swap are used with `memory_order_relaxed` only (the one order Metal has); correctness rests on the table being written in one dispatch and read in later ones (a barrier between dispatches of one serial encoder), never on a thread waiting for another.
- **Coarse voxels amplify evaluator noise at kinks.** The Newton step divides by the gradient's squared length; near a shell's medial surface or a noisy field's kink it is small. At 1.5 mm voxels the noisy shell's surfaces were 6e-4 mm apart (CPU evaluator against GPU); at the suite's ~60 voxels across they are 5e-6. Nothing is wrong with the kernels (the same-samples comparison holds at both), but the 1e-4 mm of D13 is a statement about fine meshes, and the suite says so.
- **Memory.** The GPU path holds the edge table (8 bytes a slot, 256 slots a brick asked for first, doubled when too small) and the output buffers, then Swift copies of the output, then the `TriangleMesh`: estimated, not measured, at about 40 bytes a triangle on the GPU plus 28 for the arrays plus the mesh's own, so up to about three copies of an export's mesh live at once. `MeshingBudget.check` for an export is unchanged and still decides by the CPU mesher's estimate (U1). `largestTable` (2^27 slots, 1 GB) and `MTLDevice.maxBufferLength` send what does not fit back to the CPU. An export at 0.1 mm of the bench sheet may take either path (it depends on its brick count against `largestTable`); i-4 was not re-measured here (it is 7c-3's, D12), and a run of it will say.
- **Precision far from the origin.** Positions are `Float` (the contract of `BrickMesh`); at 4 m from the origin one unit in the last place is about 5e-4 mm. D13's 1e-4 mm is a statement for parts within a few hundred millimetres of the origin (U2), and the suite says so.
- **The Auto preview gets finer on the GPU** (U5): a product change that follows from `PreviewSchedule`'s rule, not from this plan's code. IM-13 watches it.
- **The silent fall-back** (Review Focus 1) is a deliberate design (U4) and a trap for tests. CLAUDE.md gets a sentence that says so.
- **A compiler abort found while writing the tests:** an async test helper that returned an unnamed tuple of an actor, a program and a request and used `try #require` aborted the test process with "freed pointer was not the last allocation". The tests use a struct with an async initializer (`MetalMeshingLimitsTests.Prepared`) instead; do not turn it back into a tuple-returning helper.
- **Order of the arrays differs from run to run** (U3).
- **The base of this revision.** The plan was first verified against 7c-core's `r2` (`60f1c2d`), which no longer exists; 7c-core's `7c-core` branch (its lanes merged, a second round in progress) differs from it: `ImplicitMesher.mesh` has no `source:` or `meshingSeconds` yet, `GPUFixtures.all` has three "empty …" fixtures (the agreement suite now excludes names starting "empty"), `MetalImplicitEngine` has a `ShapeKey` pipeline cache and an `afterDispatch` hook, and there is no `ImplicitBench` yet. Tasks 1 to 4's code was re-verified on a copy of it (see "How this plan was verified"); Task 5's bench edits need `ImplicitBench` and are verified only by compiling their helper in isolation. The anchors of Tasks 1 to 4 that name `source:`, `meshingSeconds` and the engine's old layout match `r2` and the final 7c-core; whoever applies the plan on another base adapts those lines and nothing else.
- **Benchmarks on a saturated Mac.** The 7c-1g run was taken at a load average of 150, so it is a record and not an idle measurement; the GPU rows are GPU-bound and met their budgets by a wide margin all the same. It says so in `performance.md` and asks for an idle re-run.
- **New MetalUI gaps: none.** The work is in `CreatorImplicit` and its tests; the SDL3 engine's needs (XP-G1, XP-G2) are already in `docs/metalui-gaps.md`'s cross-platform rows and are not changed here.

## Tasks

| # | Task | Tests after a full `swift test` (this Mac, with Metal) |
|---|---|---|
| 1 | The mesh-bricks requirement, its values, and the mesher's choice of path | 4,174 (master + 11) |
| 2 | The edge numbering of a window of bricks and the case table as a buffer | 4,183 (master + 20) |
| 3 | The Metal kernels and `MetalImplicitEngine.meshBricks` | 4,188 (master + 25) |
| 4 | The GPU against the CPU: the agreement suite and the limits | 4,203 (master + 40) |
| 5 | Re-measure i-1 and i-2 on the GPU path, and record them | 4,205 (master + 42) |

Without a Metal device the totals are 16 lower from Task 3 on (Task 3: 5, Task 4: 11): master + 26 at the end.

## File structure

New, all under `Sources/CreatorImplicit/` unless said:

| File | Responsibility |
|---|---|
| `GPU/BrickMeshRequest.swift` | the bricks to mesh, as plain values: origin, voxel size, brick coordinates, snap |
| `GPU/BrickMesh.swift` | what an engine returns: flat positions, normals, indices, and `isConsistent` |
| `GPU/BrickLattice.swift` | the window around the bricks, the 32-bit edge keys counted from it, the relative brick buffer and the CPU's coordinates per axis |
| `Metal/MarchingCubesBuffers.swift` | `MarchingCubesTable` as one flat `[UInt32]`, the buffer the kernels read |
| `Metal/ImplicitMeshShaderLibrary.swift` | the five meshing kernels as Metal source text, the buffer bindings and counters they share |
| `Metal/MetalImplicitEngine+Meshing.swift` | the one file that runs them: pipelines, buffers, the dispatches, the retry of a too-small table (inside `#if canImport(Metal)`) |

Modified: `GPU/ImplicitGPUEngine.swift` (the requirement and its default), `GPU/GPUBatchEvaluator.swift`, `Sampling/ImplicitBatchEvaluator.swift` (the evaluator's `meshBricks` and its `nil` default), `Meshing/ImplicitMesher.swift` (`MeshingPath`, `meshReportingPath`, the choice), `Metal/MetalImplicitEngine.swift` (members made internal, four stored properties).

Tests, under `Tests/CreatorImplicitTests/`: `BrickMeshingTests.swift` (Task 1), `BrickLatticeTests.swift` (Task 2), `MetalMeshingTests.swift` (Task 3), `MeshComparisonTests.swift`, `GPUMeshAgreementTests.swift`, `MetalMeshingLimitsTests.swift` and `Support/MeshComparison.swift` (Task 4), `Support/StubGPUEngine.swift` modified (Task 1). Under `Tests/CreatorAppTests/Bench/`: `ImplicitBench.swift`, `ImplicitBenchFixtures.swift`, `ImplicitBenchFixturesTests.swift` modified (Task 5). Docs: `CLAUDE.md`, `docs/verification/performance.md`, `docs/verification/human-checks.md` (Task 5).

## The contract for another engine (xp-c)

An engine written against this protocol needs no Metal type and no Apple framework:

- **In:** `meshBricks(_ program: CompiledImplicit, _ request: BrickMeshRequest, progress:)`. `program.source` is Metal Shading Language text, `ImplicitMeshShaderLibrary.source(extending: program)` appends the meshing kernels (also text; an SDL3 engine translates both, the way it will have to translate the evaluator's), and `program.parameters/integers/tables/pool/images` are the five data buffers. The request's bricks are sorted by x, then y, then z.
- **Numbering:** `BrickLattice(request.bricks)` gives the window, `fitsEdgeKeys`, `relativeBricks`, `axisCoordinates` (the CPU's `Float` coordinates per lattice axis, so the sample points are bit for bit the CPU's) and the key formula; `MarchingCubesBuffers.words` is the case table. An engine that cannot take a request (no 32-bit keys, a buffer the device cannot make) throws `ImplicitCompileError.unsupported`, and the CPU mesher does the work.
- **Out:** a `BrickMesh` whose `isConsistent` is true: counter-clockwise triangles seen from outside, one vertex per crossed lattice edge, unit normals from the snap, pointing outwards like the surface's gradient (or zero vectors when `request.snap` is false), in any order. Work in bounded command buffers: the per-vertex steps over a table in ranges, not one dispatch over millions of slots.
- **Held to:** `GPUMeshAgreementTests` (topology, vertices, normals, enclosed volume) is written against `ImplicitMesher` and `ImplicitEvaluators`, not against Metal; an SDL3 engine copies the suite with its own `#if` and device guard, and `StubGPUEngine.Meshing` shows how the mesher's side is tested without a device.

---

## Task 1: The mesh-bricks requirement, its values, and the mesher's choice of path

Everything here is portable and tested on every platform through `StubGPUEngine`. No Metal yet: after this task the mesher asks every evaluator for a mesh first, every engine answers "unsupported", and nothing changes for the person.

**Files:**
- Create: `Sources/CreatorImplicit/GPU/BrickMeshRequest.swift`, `Sources/CreatorImplicit/GPU/BrickMesh.swift`
- Modify: `Sources/CreatorImplicit/GPU/ImplicitGPUEngine.swift`, `Sources/CreatorImplicit/GPU/GPUBatchEvaluator.swift`, `Sources/CreatorImplicit/Sampling/ImplicitBatchEvaluator.swift`, `Sources/CreatorImplicit/Meshing/ImplicitMesher.swift`
- Test: `Tests/CreatorImplicitTests/BrickMeshingTests.swift` (new), `Tests/CreatorImplicitTests/Support/StubGPUEngine.swift` (modify)

**Interfaces:**
- Consumes: `BrickPlan` (`origin: Vector3`, `resolution: Double`, `bricks: [SIMD3<Int32>]`), `ImplicitBatchEvaluator`, `GPUBatchEvaluator`, `ImplicitGPUEngine`, `CompiledImplicit`, `ImplicitCompileError`, `ImplicitMeshingError.empty`, `MeshTopology`, `ProgressLog` (in `ImplicitMesherTests.swift`).
- Produces (later tasks and other tracks rely on these names):
  - `struct BrickMeshRequest: Sendable, Equatable { var origin: SIMD3<Double>; var resolution: Double; var bricks: [SIMD3<Int32>]; var snap: Bool; init(origin:resolution:bricks:snap:); init(plan: BrickPlan, snap: Bool) }`
  - `struct BrickMesh: Sendable, Equatable { var positions: [SIMD3<Float>]; var normals: [SIMD3<Float>]; var triangles: [UInt32]; init(positions:normals:triangles:); var isConsistent: Bool }`
  - `ImplicitGPUEngine.meshBricks(_ program: CompiledImplicit, _ request: BrickMeshRequest, progress: @Sendable (Double) -> Void) async throws -> BrickMesh`, with a default that throws `ImplicitCompileError.unsupported("meshing bricks")`.
  - `ImplicitBatchEvaluator.meshBricks(_ request: BrickMeshRequest, progress: @Sendable (Double) -> Void) async throws -> BrickMesh?`, default `nil`; `GPUBatchEvaluator` implements it by calling its engine and answering `nil` for any `ImplicitCompileError`.
  - `enum MeshingPath { case cpu, gpu }` and `ImplicitMesher.meshReportingPath(_:resolution:quality:snap:source:progress:) async throws -> (mesh: TriangleMesh, path: MeshingPath)`; `mesh(...)` is unchanged and calls it.
  - Test support: `StubGPUEngine(failure:meshing:)` with `StubGPUEngine.Meshing` = `.unsupported | .answers(BrickMesh) | .fails(ImplicitCompileError) | .cancels`, and `meshRequests`.

- [ ] **Step 1: Write the failing tests**

The stub learns to answer, fail or cancel a mesh request and to remember what it was asked; the suite pins the mesher's choice: an engine's mesh is used when it is consistent; the CPU does the work when the engine does not mesh, fails or lies; a cancel is not a failure.

**Create `Tests/CreatorImplicitTests/BrickMeshingTests.swift`**

````swift
import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The mesher's choice between an engine that meshes bricks and the CPU (implicit spec Errata D13), tested with `StubGPUEngine` so it
/// runs on every platform.
struct BrickMeshingTests {
    /// A closed tetrahedron, as an engine might answer.
    static let tetrahedron = BrickMesh(
        positions: [SIMD3<Float>(1, 1, 1), SIMD3<Float>(1, -1, -1), SIMD3<Float>(-1, 1, -1), SIMD3<Float>(-1, -1, 1)],
        normals: [SIMD3<Float>](repeating: .zero, count: 4), triangles: [0, 1, 2, 0, 3, 1, 0, 2, 3, 1, 3, 2])

    func mesher(_ engine: StubGPUEngine, for solid: ImplicitSolid) async -> ImplicitMesher {
        ImplicitMesher(evaluator: await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine).evaluator)
    }

    @Test func anEngineThatMeshesBricksMakesTheMesh() async throws {
        let engine = StubGPUEngine(meshing: .answers(Self.tetrahedron))
        let solid = ImplicitFixtures.sphere
        let (mesh, path) = try await mesher(engine, for: solid).meshReportingPath(solid, resolution: 1, quality: .preview)
        #expect(path == .gpu)
        #expect(mesh.positions == Self.tetrahedron.positions && mesh.triangles == Self.tetrahedron.triangles)
        #expect(mesh.resolution == 1 && mesh.quality == .preview && mesh.meshingSeconds >= 0)
    }

    @Test func theRequestCarriesThePlansBricksAndTheSnapFlag() async throws {
        let engine = StubGPUEngine(meshing: .answers(Self.tetrahedron))
        let solid = ImplicitFixtures.cylinder
        let plan = try await BrickPlan.build(for: solid, resolution: 0.8, using: CPUBatchEvaluator(solid))
        _ = try await mesher(engine, for: solid).mesh(solid, resolution: 0.8, quality: .preview, snap: false)
        let requests = await engine.meshRequests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.bricks == plan.bricks && request.resolution == 0.8 && request.snap == false)
        #expect(request.origin == SIMD3(plan.origin.x, plan.origin.y, plan.origin.z))
        #expect(BrickMeshRequest(plan: plan, snap: true).snap)
    }

    @Test func anEngineThatDoesNotMeshLeavesItToTheCPU() async throws {
        let engine = StubGPUEngine()
        let solid = ImplicitFixtures.sphere
        let (mesh, path) = try await mesher(engine, for: solid).meshReportingPath(solid, resolution: 0.7, quality: .preview)
        #expect(path == .cpu)
        #expect(MeshTopology(mesh).isClosedManifold)
        #expect(await engine.meshRequests.count == 1, "it was asked, and said no")
    }

    @Test func anEngineThatFailsToMeshFallsBackToTheCPU() async throws {
        for failure in [ImplicitCompileError.engine("a made-up error"), .unsupported("too large")] {
            let engine = StubGPUEngine(meshing: .fails(failure))
            let solid = ImplicitFixtures.sphere
            let (mesh, path) = try await mesher(engine, for: solid).meshReportingPath(solid, resolution: 0.7, quality: .preview)
            #expect(path == .cpu && MeshTopology(mesh).isClosedManifold)
        }
    }

    @Test func aCancelledEngineIsNotSwallowed() async {
        let engine = StubGPUEngine(meshing: .cancels)
        let solid = ImplicitFixtures.sphere
        let mesher = await mesher(engine, for: solid)
        await #expect(throws: CancellationError.self) { try await mesher.mesh(solid, resolution: 0.7, quality: .preview) }
    }

    @Test(arguments: [
        BrickMesh(positions: [.zero, .zero, .zero], normals: [.zero, .zero, .zero], triangles: [0, 1, 7]),
        BrickMesh(positions: [.zero, .zero, .zero], normals: [.zero], triangles: [0, 1, 2]),
        BrickMesh(positions: [.zero, .zero, .zero], normals: [.zero, .zero, .zero], triangles: [0, 1]),
    ])
    func arraysThatDoNotFitTogetherAreNotTrusted(_ wrong: BrickMesh) async throws {
        #expect(!wrong.isConsistent)
        let engine = StubGPUEngine(meshing: .answers(wrong))
        let solid = ImplicitFixtures.sphere
        let (mesh, path) = try await mesher(engine, for: solid).meshReportingPath(solid, resolution: 0.7, quality: .preview)
        #expect(path == .cpu && MeshTopology(mesh).isClosedManifold)
    }

    @Test func aConsistentMeshIsConsistent() {
        #expect(Self.tetrahedron.isConsistent)
        #expect(BrickMesh(positions: [], normals: [], triangles: []).isConsistent)
    }

    @Test func anEmptyAnswerIsNothingToMesh() async {
        let engine = StubGPUEngine(meshing: .answers(BrickMesh(positions: [], normals: [], triangles: [])))
        let solid = ImplicitFixtures.sphere
        let mesher = await mesher(engine, for: solid)
        await #expect(throws: ImplicitMeshingError.empty) { try await mesher.mesh(solid, resolution: 0.7, quality: .preview) }
    }

    @Test func theCPUEvaluatorMeshesOnTheCPUWithoutAskingAnyone() async throws {
        let solid = ImplicitFixtures.sphere
        let (_, path) = try await ImplicitMesher(evaluator: CPUBatchEvaluator(solid))
            .meshReportingPath(solid, resolution: 0.7, quality: .preview)
        #expect(path == .cpu)
    }

    @Test func progressIncludesTheEnginesAndEndsAtOne() async throws {
        let engine = StubGPUEngine(meshing: .answers(Self.tetrahedron))
        let solid = ImplicitFixtures.sphere
        let seen = ProgressLog()
        _ = try await mesher(engine, for: solid).mesh(solid, resolution: 1, quality: .preview) { seen.append($0) }
        #expect(seen.values == [0, 0.5, 1])
    }

    @Test func theDefaultRequirementSaysNotSupportedAndTheEvaluatorAnswersNil() async throws {
        let engine = StubGPUEngine()
        let program = try await engine.compile(.sphere(radius: 5))
        let request = BrickMeshRequest(origin: .zero, resolution: 1, bricks: [SIMD3(0, 0, 0)], snap: true)
        let evaluator = GPUBatchEvaluator(engine: engine, program: program)
        #expect(try await evaluator.meshBricks(request) { _ in } == nil)
        #expect(try await CPUBatchEvaluator(.sphere(radius: 5)).meshBricks(request) { _ in } == nil)
    }
}
````

**Edit `Tests/CreatorImplicitTests/Support/StubGPUEngine.swift`**

Replace:

````swift

/// A GPU engine that is the CPU underneath, so the code that depends on `ImplicitGPUEngine` is tested on every platform.
actor StubGPUEngine: ImplicitGPUEngine {
    /// What `prepare` throws, when set.
    private let failure: ImplicitCompileError?
    private(set) var prepared = 0
    private(set) var evaluated = 0
    private(set) var cancels = 0
````

With:

````swift

/// A GPU engine that is the CPU underneath, so the code that depends on `ImplicitGPUEngine` is tested on every platform.
actor StubGPUEngine: ImplicitGPUEngine {
    /// What `meshBricks` does.
    enum Meshing: Sendable {
        /// The protocol's default: this engine does not mesh.
        case unsupported
        /// Reports halfway, then returns this mesh whatever the request.
        case answers(BrickMesh)
        /// Throws this.
        case fails(ImplicitCompileError)
        /// Throws `CancellationError`, as an engine does when its task is cancelled between dispatches.
        case cancels
    }

    /// What `prepare` throws, when set.
    private let failure: ImplicitCompileError?
    private let meshing: Meshing
    /// The requests `meshBricks` was asked for, in order.
    private(set) var meshRequests: [BrickMeshRequest] = []
    private(set) var prepared = 0
    private(set) var evaluated = 0
    private(set) var cancels = 0
````

**Edit `Tests/CreatorImplicitTests/Support/StubGPUEngine.swift`**

Replace:

````swift
    nonisolated let name = "Stub"
    var deviceName: String { "stub device" }

    init(failure: ImplicitCompileError? = nil) {
        self.failure = failure
    }

    /// Remembers which solid a program came from, so `evaluate` can answer with the CPU.
````

With:

````swift
    nonisolated let name = "Stub"
    var deviceName: String { "stub device" }

    init(failure: ImplicitCompileError? = nil, meshing: Meshing = .unsupported) {
        self.failure = failure
        self.meshing = meshing
    }

    /// Remembers which solid a program came from, so `evaluate` can answer with the CPU.
````

**Edit `Tests/CreatorImplicitTests/Support/StubGPUEngine.swift`**

Replace:

````swift
    func cancel() async {
        cancels += 1
    }
}
````

With:

````swift
    func cancel() async {
        cancels += 1
    }

    func meshBricks(_ program: CompiledImplicit, _ request: BrickMeshRequest,
                    progress: @Sendable (Double) -> Void) async throws -> BrickMesh {
        meshRequests.append(request)
        switch meshing {
        case .unsupported: throw ImplicitCompileError.unsupported("meshing bricks")
        case .answers(let mesh):
            progress(0.5)
            return mesh
        case .fails(let error): throw error
        case .cancels: throw CancellationError()
        }
    }
}
````

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head`
Expected: errors such as `cannot find type 'BrickMesh' in scope` and `cannot find 'BrickMeshRequest' in scope`.

- [ ] **Step 3: Implement**

The requirement lives on the engine with a default, so an engine that only evaluates still conforms. The evaluator gets the same requirement with a `nil` default, which is what lets the mesher stay ignorant of engines. The mesher's CPU loop is untouched and moves behind the choice. `isConsistent` is checked before an engine's arrays are believed.

**Create `Sources/CreatorImplicit/GPU/BrickMesh.swift`**

````swift
/// What an engine returns for a `BrickMeshRequest`: the mesh as flat arrays (implicit spec Errata D13).
///
/// The triangles are counter-clockwise seen from outside, with one vertex per lattice edge the surface crosses. The order of
/// vertices and triangles is the engine's: the CPU mesher's is the order the bricks and cubes are visited, a GPU's need not be the
/// same twice. The set is what is fixed.
public struct BrickMesh: Sendable, Equatable {
    public var positions: [SIMD3<Float>]
    /// One unit normal per vertex, or zero vectors when the request did not snap.
    public var normals: [SIMD3<Float>]
    /// Three indices into `positions` per triangle.
    public var triangles: [UInt32]

    public init(positions: [SIMD3<Float>], normals: [SIMD3<Float>], triangles: [UInt32]) {
        self.positions = positions
        self.normals = normals
        self.triangles = triangles
    }

    /// Whether the arrays fit together: whole triangles, a normal for every vertex, every index in range. The mesher checks it
    /// before it trusts an engine, so a buggy one costs a fall-back to the CPU and not a crash in the viewport.
    public var isConsistent: Bool {
        triangles.count.isMultiple(of: 3) && normals.count == positions.count && triangles.allSatisfy { Int($0) < positions.count }
    }
}
````

**Create `Sources/CreatorImplicit/GPU/BrickMeshRequest.swift`**

````swift
import CreatorGeometry

/// The bricks an engine is asked to mesh (implicit spec Errata D13), as plain values: no GPU type, so any engine can take them.
///
/// The lattice is the `BrickPlan`'s: lattice point (i, j, k) is at `origin + (i, j, k) * resolution`, and brick (a, b, c) holds the
/// voxels from lattice point (8a, 8b, 8c) to (8a + 7, 8b + 7, 8c + 7), plus the shared layer of points to 8a + 8. Only the bricks listed
/// are meshed; the surface closes across their faces because every edge of the lattice has one vertex, whichever bricks reach it.
public struct BrickMeshRequest: Sendable, Equatable {
    /// The world position of lattice point (0, 0, 0), in millimetres.
    public var origin: SIMD3<Double>
    /// The voxel size in millimetres.
    public var resolution: Double
    /// Integer brick coordinates, as `BrickPlan.bricks` lists them (sorted by x, then y, then z, which an engine may rely on).
    public var bricks: [SIMD3<Int32>]
    /// Whether each vertex takes the Newton step towards f = 0 and gets its normal from the gradient (the mesher's `snap`).
    public var snap: Bool

    public init(origin: SIMD3<Double>, resolution: Double, bricks: [SIMD3<Int32>], snap: Bool) {
        self.origin = origin
        self.resolution = resolution
        self.bricks = bricks
        self.snap = snap
    }

    /// The request for every brick of `plan`.
    public init(plan: BrickPlan, snap: Bool) {
        self.init(origin: SIMD3(plan.origin.x, plan.origin.y, plan.origin.z), resolution: plan.resolution, bricks: plan.bricks,
                  snap: snap)
    }
}
````

**Edit `Sources/CreatorImplicit/GPU/GPUBatchEvaluator.swift`**

Replace:

````swift
    public func evaluate(_ points: [SIMD3<Float>]) async throws -> [Float] {
        try await engine.evaluate(program, at: points)
    }
}
````

With:

````swift
    public func evaluate(_ points: [SIMD3<Float>]) async throws -> [Float] {
        try await engine.evaluate(program, at: points)
    }

    /// The engine's mesh of the bricks, or `nil` when it does not mesh or cannot take this request: the CPU mesher then does it.
    public func meshBricks(_ request: BrickMeshRequest, progress: @Sendable (Double) -> Void) async throws -> BrickMesh? {
        do {
            return try await engine.meshBricks(program, request, progress: progress)
        } catch is ImplicitCompileError {
            return nil
        }
    }
}
````

**Edit `Sources/CreatorImplicit/GPU/ImplicitGPUEngine.swift`**

Replace:

````swift
/// and an SDL3 GPU compute engine for Linux and Windows follows (track xp-c). Where there is no engine the CPU evaluator, which is
/// complete, does everything.
///
/// D13 adds meshing bricks to this protocol (plan 7c-1g); an implementation written now needs only evaluation.
public protocol ImplicitGPUEngine: Sendable {
    /// "Metal" (or the next implementation's name), for the preview badge and the inspector.
    nonisolated var name: String { get }
````

With:

````swift
/// and an SDL3 GPU compute engine for Linux and Windows follows (track xp-c). Where there is no engine the CPU evaluator, which is
/// complete, does everything.
///
/// D13 adds meshing bricks (plan 7c-1g): `meshBricks` is a requirement with a default that says "not supported", so an engine may
/// evaluate only and leave meshing to the CPU mesher, which stays the reference and the fall-back. The protocol's types are plain
/// values (`CompiledImplicit`, `BrickMeshRequest`, `BrickMesh`): buffers in and buffers out, with no GPU type in them, so an SDL3 GPU
/// compute engine (track xp-c) implements it the way `MetalImplicitEngine` does.
public protocol ImplicitGPUEngine: Sendable {
    /// "Metal" (or the next implementation's name), for the preview badge and the inspector.
    nonisolated var name: String { get }
````

**Edit `Sources/CreatorImplicit/GPU/ImplicitGPUEngine.swift`**

Replace:

````swift
    /// called, between dispatches.
    func evaluate(_ program: CompiledImplicit, at points: [SIMD3<Float>]) async throws -> [Float]

    /// Ends the batches in flight with `CancellationError`. Batches started after the call run normally.
    func cancel() async
}
````

With:

````swift
    /// called, between dispatches.
    func evaluate(_ program: CompiledImplicit, at points: [SIMD3<Float>]) async throws -> [Float]

    /// The surface of `request`'s bricks, meshed on the GPU with the CPU mesher's marching cubes table, one vertex per lattice edge,
    /// and the Newton snap when `request.snap`. `progress` is called with the fraction done, 0 to 1, in order. Throws `.unsupported`
    /// when this engine does not mesh, or when this request is beyond it (too large for its tables or buffers); the CPU mesher then
    /// does the work. Throws `CancellationError` when the task is cancelled, or `cancel()` is called, between dispatches.
    func meshBricks(_ program: CompiledImplicit, _ request: BrickMeshRequest,
                    progress: @Sendable (Double) -> Void) async throws -> BrickMesh

    /// Ends the batches in flight with `CancellationError`. Batches started after the call run normally.
    func cancel() async
}
````

**Edit `Sources/CreatorImplicit/GPU/ImplicitGPUEngine.swift`**

Replace:

````swift
        try await prepare(program)
        return program
    }
}
````

With:

````swift
        try await prepare(program)
        return program
    }

    /// Engines that do not mesh need not say so.
    public func meshBricks(_ program: CompiledImplicit, _ request: BrickMeshRequest,
                           progress: @Sendable (Double) -> Void) async throws -> BrickMesh {
        throw ImplicitCompileError.unsupported("meshing bricks")
    }
}
````

**Edit `Sources/CreatorImplicit/Meshing/ImplicitMesher.swift`**

Replace:

````swift
import CreatorGeometry
import CreatorGraph
import Foundation

/// Meshes an implicit solid by marching cubes over the sparse bricks of a `BrickPlan` (implicit spec §4.3). The mesh is watertight and
/// manifold by construction: the table (`MarchingCubesTable`) draws the same outline on a face from either side, and a vertex on an edge
/// of the lattice is made once, whichever brick or cube reaches it first, by a global key. Each vertex then takes one Newton step
/// towards f = 0 along the gradient (central differences), at most half a voxel, and the gradient gives its normal.
public struct ImplicitMesher: Sendable {
    public let evaluator: any ImplicitBatchEvaluator
    public let budget: MeshingBudget
````

With:

````swift
import CreatorGeometry
import CreatorGraph
import Foundation

/// Where a mesh was made.
public enum MeshingPath: Sendable, Equatable {
    /// By the CPU mesher over the evaluator's values: the reference, and the fall-back.
    case cpu
    /// By the evaluator's GPU engine (Errata D13).
    case gpu
}

/// Meshes an implicit solid by marching cubes over the sparse bricks of a `BrickPlan` (implicit spec §4.3). The mesh is watertight and
/// manifold by construction: the table (`MarchingCubesTable`) draws the same outline on a face from either side, and a vertex on an edge
/// of the lattice is made once, whichever brick or cube reaches it first, by a global key. Each vertex then takes one Newton step
/// towards f = 0 along the gradient (central differences), at most half a voxel, and the gradient gives its normal.
///
/// When the evaluator can mesh bricks itself (`ImplicitBatchEvaluator.meshBricks`, which a GPU engine implements: Errata D13) the
/// bricks go to it and the CPU does none of this; when it cannot, or fails, or returns arrays that do not fit together, the CPU
/// mesher below does, so it is the reference and the fall-back.
public struct ImplicitMesher: Sendable {
    public let evaluator: any ImplicitBatchEvaluator
    public let budget: MeshingBudget
````

**Edit `Sources/CreatorImplicit/Meshing/ImplicitMesher.swift`**

Replace:

````swift
    /// - Throws: `ImplicitMeshingError` and `CancellationError`.
    public func mesh(_ solid: ImplicitSolid, resolution: Double, quality: MeshQuality, snap: Bool = true,
                     source: MeshSource? = nil, progress: @Sendable (Double) -> Void = { _ in }) async throws -> TriangleMesh {
        let start = ContinuousClock.now
        progress(0)
        if quality == .export { try await budget.check(solid, resolution: resolution, using: evaluator) }
        let plan = try await BrickPlan.build(for: solid, resolution: resolution, using: evaluator)
        guard !plan.bricks.isEmpty else { throw ImplicitMeshingError.empty }
        var builder = MeshBuilder(plan: plan)
        let total = plan.bricks.count
        for start in stride(from: 0, to: total, by: bricksPerBatch) {
````

With:

````swift
    /// - Throws: `ImplicitMeshingError` and `CancellationError`.
    public func mesh(_ solid: ImplicitSolid, resolution: Double, quality: MeshQuality, snap: Bool = true,
                     source: MeshSource? = nil, progress: @Sendable (Double) -> Void = { _ in }) async throws -> TriangleMesh {
        try await meshReportingPath(solid, resolution: resolution, quality: quality, snap: snap, source: source, progress: progress).mesh
    }

    /// `mesh`, and which path made it: the benchmarks and the tests say so, since a fall-back to the CPU is silent.
    public func meshReportingPath(_ solid: ImplicitSolid, resolution: Double, quality: MeshQuality, snap: Bool = true,
                                  source: MeshSource? = nil, progress: @Sendable (Double) -> Void = { _ in })
        async throws -> (mesh: TriangleMesh, path: MeshingPath) {
        let start = ContinuousClock.now
        progress(0)
        if quality == .export { try await budget.check(solid, resolution: resolution, using: evaluator) }
        let plan = try await BrickPlan.build(for: solid, resolution: resolution, using: evaluator)
        guard !plan.bricks.isEmpty else { throw ImplicitMeshingError.empty }
        if let fromEngine = try await evaluator.meshBricks(BrickMeshRequest(plan: plan, snap: snap), progress: progress),
           fromEngine.isConsistent {
            guard !fromEngine.triangles.isEmpty else { throw ImplicitMeshingError.empty }
            progress(1)
            let mesh = TriangleMesh(positions: fromEngine.positions, normals: fromEngine.normals, triangles: fromEngine.triangles,
                                    resolution: resolution, quality: quality, source: source,
                                    meshingSeconds: start.duration(to: .now) / .seconds(1))
            return (mesh, .gpu)
        }
        var builder = MeshBuilder(plan: plan)
        let total = plan.bricks.count
        for start in stride(from: 0, to: total, by: bricksPerBatch) {
````

**Edit `Sources/CreatorImplicit/Meshing/ImplicitMesher.swift`**

Replace:

````swift
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        if snap { try await Self.snap(&positions, &normals, solid: solid, resolution: resolution, evaluator: evaluator) }
        progress(1)
        return TriangleMesh(positions: positions, normals: normals, triangles: builder.triangles, resolution: resolution,
                            quality: quality, source: source, meshingSeconds: start.duration(to: .now) / .seconds(1))
    }

    /// Moves each vertex one Newton step towards f = 0 and sets its normal from the gradient. The gradient is the central difference
````

With:

````swift
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        if snap { try await Self.snap(&positions, &normals, solid: solid, resolution: resolution, evaluator: evaluator) }
        progress(1)
        let mesh = TriangleMesh(positions: positions, normals: normals, triangles: builder.triangles, resolution: resolution,
                                quality: quality, source: source, meshingSeconds: start.duration(to: .now) / .seconds(1))
        return (mesh, .cpu)
    }

    /// Moves each vertex one Newton step towards f = 0 and sets its normal from the gradient. The gradient is the central difference
````

**Edit `Sources/CreatorImplicit/Sampling/ImplicitBatchEvaluator.swift`**

Replace:

````swift

    /// "CPU" or the GPU engine's name ("Metal"), for the preview badge and the inspector.
    var engineName: String { get }
}

/// The reference evaluation, in `Double`, spread over the processors.
````

With:

````swift

    /// "CPU" or the GPU engine's name ("Metal"), for the preview badge and the inspector.
    var engineName: String { get }

    /// The mesh of `request`'s bricks when this evaluator can mesh them itself (a GPU engine can, Errata D13); `nil` when it cannot,
    /// or will not for this request, and the CPU mesher meshes them over `evaluate`. Throws `CancellationError`.
    func meshBricks(_ request: BrickMeshRequest, progress: @Sendable (Double) -> Void) async throws -> BrickMesh?
}

extension ImplicitBatchEvaluator {
    public func meshBricks(_ request: BrickMeshRequest, progress: @Sendable (Double) -> Void) async throws -> BrickMesh? {
        nil
    }
}

/// The reference evaluation, in `Double`, spread over the processors.
````

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --filter "BrickMeshingTests|GPUBatchEvaluatorTests|ImplicitMesherTests|ImplicitEvaluatorsTests|ImplicitPortabilityTests"`
Expected: PASS, no "recorded an issue"; `BrickMeshingTests` is 11 tests.

- [ ] **Step 5: Build, warnings, lint**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning"; swiftlint lint --strict 2>&1 | tail -1`
Expected: no output from the build (or only the baseline `ContextMenuTests.swift` warning) and `Found 0 violations, 0 serious`.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorImplicit Tests/CreatorImplicitTests
git commit -m "feat(implicit): ImplicitGPUEngine.meshBricks and the mesher's choice of path (7c-1g T1)"
```

## Task 2: The edge numbering of a window of bricks and the case table as a buffer

Portable data the kernels need and the CPU can test: which window of the lattice the bricks touch, the 32-bit key of every lattice edge counted from it (the CPU mesher's key made relative), the brick coordinates as a flat buffer, the CPU's `Float` coordinates per axis, and the case table as words. After this task nothing calls them; Task 3 does.

**Files:**
- Create: `Sources/CreatorImplicit/GPU/BrickLattice.swift`, `Sources/CreatorImplicit/Metal/MarchingCubesBuffers.swift`
- Test: `Tests/CreatorImplicitTests/BrickLatticeTests.swift` (new)

**Interfaces:**
- Consumes: `BrickPlan.brickSize` (8), `BrickPlan.point(_:_:_:)`, `MarchingCubesTable.triangles`, `MarchingCubesTable.edgeCorners`, `BrickMeshRequest`.
- Produces:
  - `struct BrickLattice: Sendable, Equatable { let minBrick: SIMD3<Int32>; let extent: SIMD3<Int>; static let emptyKey: UInt32; init?(_ bricks: [SIMD3<Int32>]); var points: SIMD3<Int>; var fitsEdgeKeys: Bool; func edgeKey(point: SIMD3<Int>, axis: Int) -> UInt32; func edge(of key: UInt32) -> (point: SIMD3<Int>, axis: Int); func relativeBricks(_ bricks: [SIMD3<Int32>]) -> [UInt32]; func axisCoordinates(origin: SIMD3<Double>, resolution: Double) -> [Float] }`. Key = `((z * ny + y) * nx + x) * 3 + axis` over the window's lattice points `(nx, ny, nz) = points`; `UInt32.max` is the empty slot, never a key.
  - `enum MarchingCubesBuffers` (internal) with `words: [UInt32]` and the offsets `startsOffset` (0), `lowerCornersOffset` (257), `upperCornersOffset` (269), `edgesOffset` (281), `patternCount` (256). Pattern `p`'s edges are `words[edgesOffset + words[p] ..< edgesOffset + words[p + 1]]`.

- [ ] **Step 1: Write the failing tests**

They pin the numbering (every edge of a window has its own key and the key names it back), the seam (the same key from both bricks of a face), the 32-bit limit including extremes that would overflow the arithmetic, the CPU-identical coordinates, the table as words, and that the table uses exactly the edges a pattern crosses, which is what lets a kernel claim one table slot per crossing edge.

**Create `Tests/CreatorImplicitTests/BrickLatticeTests.swift`**

````swift
import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The numbering an engine meshes bricks by (implicit spec Errata D13): keys unique per edge, the same from every brick that reaches the
/// edge, and fitting 32 bits; the table as the shader reads it; sample positions the CPU's, bit for bit.
struct BrickLatticeTests {
    static let bricks: [SIMD3<Int32>] = [SIMD3(-2, 5, 3), SIMD3(-1, 5, 3), SIMD3(-1, 6, 3), SIMD3(0, 6, 4)]

    @Test func noBricksNoWindow() {
        #expect(BrickLattice([]) == nil)
    }

    @Test func theWindowIsTheBoxAroundTheBricks() throws {
        let lattice = try #require(BrickLattice(Self.bricks))
        #expect(lattice.minBrick == SIMD3(-2, 5, 3) && lattice.extent == SIMD3(3, 2, 2))
        #expect(lattice.points == SIMD3(25, 17, 17))
        #expect(lattice.fitsEdgeKeys)
    }

    @Test func everyEdgeOfTheWindowHasItsOwnKeyAndTheKeyNamesTheEdgeBack() throws {
        let lattice = try #require(BrickLattice([SIMD3(4, 4, 4), SIMD3(5, 4, 4)]))
        let size = lattice.points
        var seen = Set<UInt32>()
        for z in 0..<size.z {
            for y in 0..<size.y {
                for x in 0..<size.x {
                    for axis in 0..<3 {
                        let key = lattice.edgeKey(point: SIMD3(x, y, z), axis: axis)
                        #expect(seen.insert(key).inserted)
                        let edge = lattice.edge(of: key)
                        #expect(edge.point == SIMD3(x, y, z) && edge.axis == axis)
                    }
                }
            }
        }
        #expect(seen.count == 3 * size.x * size.y * size.z && !seen.contains(BrickLattice.emptyKey))
    }

    @Test func aBrickFaceEdgeHasOneKeyFromBothBricks() throws {
        // The edge along y at lattice x = 8, z = 2 is the far face of brick (0, 0, 0) and the near face of brick (1, 0, 0).
        let lattice = try #require(BrickLattice([SIMD3(0, 0, 0), SIMD3(1, 0, 0)]))
        let fromFirst = lattice.edgeKey(point: SIMD3(0 * 8 + 8, 3, 2), axis: 1)
        let fromSecond = lattice.edgeKey(point: SIMD3(1 * 8 + 0, 3, 2), axis: 1)
        #expect(fromFirst == fromSecond)
    }

    @Test func bricksAreCountedFromTheWindowsLowestOne() throws {
        let lattice = try #require(BrickLattice(Self.bricks))
        #expect(lattice.relativeBricks(Self.bricks) == [0, 0, 0, 1, 0, 0, 1, 1, 0, 2, 1, 1])
    }

    @Test func aWindowTooBigForThirtyTwoBitKeysIsSaidSo() throws {
        let lattice = try #require(BrickLattice([SIMD3(0, 0, 0), SIMD3(1_200, 1_200, 1_200)]))
        #expect(!lattice.fitsEdgeKeys)
        let far = try #require(BrickLattice([SIMD3(1_000_000, -1_000_000, 70_000)]))
        #expect(far.fitsEdgeKeys, "a lone brick far from the origin is a small window")
        let wide = try #require(BrickLattice([SIMD3(Int32.min, Int32.min, Int32.min), SIMD3(Int32.max, Int32.max, Int32.max)]))
        #expect(!wide.fitsEdgeKeys, "extremes don't overflow the check")
    }

    @Test func theCoordinatesAreTheCPUPlansBitForBit() async throws {
        let solid = ImplicitFixtures.cylinder
        let plan = try await BrickPlan.build(for: solid, resolution: 0.37, using: CPUBatchEvaluator(solid))
        let lattice = try #require(BrickLattice(plan.bricks))
        let request = BrickMeshRequest(plan: plan, snap: true)
        let coordinates = lattice.axisCoordinates(origin: request.origin, resolution: request.resolution)
        let size = lattice.points
        #expect(coordinates.count == size.x + size.y + size.z)
        let first = SIMD3<Int>(Int(lattice.minBrick.x), Int(lattice.minBrick.y), Int(lattice.minBrick.z)) &* BrickPlan.brickSize
        for index in 0..<size.x {
            #expect(coordinates[index] == Float(plan.point(first.x + index, 0, 0).x))
        }
        for index in 0..<size.y {
            #expect(coordinates[size.x + index] == Float(plan.point(0, first.y + index, 0).y))
        }
        for index in 0..<size.z {
            #expect(coordinates[size.x + size.y + index] == Float(plan.point(0, 0, first.z + index).z))
        }
    }

    @Test func theTableBufferIsTheMarchingCubesTable() {
        let words = MarchingCubesBuffers.words
        #expect(words.count == MarchingCubesBuffers.edgesOffset + MarchingCubesTable.triangles.reduce(0) { $0 + $1.count })
        for pattern in 0..<MarchingCubesBuffers.patternCount {
            let starts = MarchingCubesBuffers.startsOffset + pattern
            let base = MarchingCubesBuffers.edgesOffset
            let edges = words[(base + Int(words[starts]))..<(base + Int(words[starts + 1]))].map { UInt8($0) }
            #expect(edges == MarchingCubesTable.triangles[pattern])
        }
        for edge in 0..<12 {
            #expect(Int(words[MarchingCubesBuffers.lowerCornersOffset + edge]) == MarchingCubesTable.edgeCorners[edge].0)
            #expect(Int(words[MarchingCubesBuffers.upperCornersOffset + edge]) == MarchingCubesTable.edgeCorners[edge].1)
        }
    }

    @Test func theTableUsesEveryEdgeAPatternCrossesAndNoOther() {
        // The shader claims a table slot for each edge whose ends differ in sign, and the triangles name vertices by edge.
        for pattern in 0..<MarchingCubesBuffers.patternCount {
            let used = Set(MarchingCubesTable.triangles[pattern])
            let crossing = Set((0..<12).filter { edge in
                let (a, b) = MarchingCubesTable.edgeCorners[edge]
                return (pattern >> a & 1) != (pattern >> b & 1)
            }.map(UInt8.init))
            #expect(used == crossing, "pattern \(pattern)")
        }
    }
}
````

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head`
Expected: `cannot find 'BrickLattice' in scope`, `cannot find 'MarchingCubesBuffers' in scope`.

- [ ] **Step 3: Implement**

`relativeBricks` subtracts with wrapping (`&-`) and reads the bits back as `UInt32`, so a window as wide as the `Int32` range cannot trap; callers check `fitsEdgeKeys` first anyway. `fitsEdgeKeys` multiplies in `Double` for the same reason.

**Create `Sources/CreatorImplicit/GPU/BrickLattice.swift`**

````swift
/// The window of the lattice a set of bricks touches, and the numbering an engine meshes it by (implicit spec Errata D13).
///
/// Every edge of the lattice has one key, `((z * ny + y) * nx + x) * 3 + axis` for the edge from lattice point (x, y, z) along `axis`,
/// counted from the lowest brick of the window: the CPU mesher's global edge key, made relative so that it fits 32 bits for any window
/// of up to about a billion lattice points, however far the part is from the origin. A cube reaches the key of an edge the same way from
/// whichever brick it is in, so a vertex on a brick's face is made once. `UInt32.max` is never a key: engines use it for an empty slot.
public struct BrickLattice: Sendable, Equatable {
    /// The lowest brick coordinates among the bricks.
    public let minBrick: SIMD3<Int32>
    /// How many bricks the window spans on each axis.
    public let extent: SIMD3<Int>

    /// The key an engine uses for "no edge here".
    public static let emptyKey = UInt32.max

    /// The window around `bricks`, or `nil` when there are none.
    public init?(_ bricks: [SIMD3<Int32>]) {
        guard var low = bricks.first else { return nil }
        var high = low
        for brick in bricks {
            low = low.replacing(with: brick, where: brick .< low)
            high = high.replacing(with: brick, where: brick .> high)
        }
        minBrick = low
        extent = SIMD3(Int(high.x) - Int(low.x) + 1, Int(high.y) - Int(low.y) + 1, Int(high.z) - Int(low.z) + 1)
    }

    /// The lattice points on each axis: eight voxels a brick, and the last brick's far layer.
    public var points: SIMD3<Int> { extent &* BrickPlan.brickSize &+ 1 }

    /// Whether every edge key of the window is below `emptyKey`. A window past this is beyond the engines' 32-bit tables, and the CPU
    /// mesher does it.
    public var fitsEdgeKeys: Bool {
        let size = points
        return 3 * Double(size.x) * Double(size.y) * Double(size.z) < Double(Self.emptyKey)
    }

    /// The key of the edge from `point` (counted from the window's lowest lattice point) along `axis` (0 for x, 1 for y, 2 for z).
    /// Only meaningful when `fitsEdgeKeys`.
    public func edgeKey(point: SIMD3<Int>, axis: Int) -> UInt32 {
        let size = points
        return UInt32(((point.z * size.y + point.y) * size.x + point.x) * 3 + axis)
    }

    /// The edge a key names: its lowest lattice point, counted from the window's, and its axis.
    public func edge(of key: UInt32) -> (point: SIMD3<Int>, axis: Int) {
        let size = points
        let index = Int(key) / 3
        return (SIMD3(index % size.x, index / size.x % size.y, index / (size.x * size.y)), Int(key) % 3)
    }

    /// The bricks as x, y, z of each counted from the window's lowest brick, flat: the buffer an engine reads.
    public func relativeBricks(_ bricks: [SIMD3<Int32>]) -> [UInt32] {
        var flat: [UInt32] = []
        flat.reserveCapacity(bricks.count * 3)
        for brick in bricks {
            flat.append(UInt32(bitPattern: brick.x &- minBrick.x))
            flat.append(UInt32(bitPattern: brick.y &- minBrick.y))
            flat.append(UInt32(bitPattern: brick.z &- minBrick.z))
        }
        return flat
    }

    /// The world coordinate of every lattice point of the window along x, then y, then z, as the CPU mesher would compute it in
    /// `Double` and round to `Float`. An engine reads its sample positions from this, so they are the CPU's, bit for bit, and its
    /// vertices need not agree with the CPU's by luck: the same signs, the same crossings.
    public func axisCoordinates(origin: SIMD3<Double>, resolution: Double) -> [Float] {
        let size = points
        let first = SIMD3<Int>(Int(minBrick.x), Int(minBrick.y), Int(minBrick.z)) &* BrickPlan.brickSize
        var coordinates: [Float] = []
        coordinates.reserveCapacity(size.x + size.y + size.z)
        for axis in 0..<3 {
            for index in 0..<size[axis] { coordinates.append(Float(origin[axis] + Double(first[axis] + index) * resolution)) }
        }
        return coordinates
    }
}
````

**Create `Sources/CreatorImplicit/Metal/MarchingCubesBuffers.swift`**

````swift
/// `MarchingCubesTable` as one flat array of 32-bit words, the buffer a GPU engine reads (implicit spec Errata D13), so the GPU meshes
/// with the very table the CPU does. The layout is part of the shader's source (`ImplicitMeshShaderLibrary`):
///
/// - words 0 ... 256: `starts`, where pattern `p`'s edges are `edges[starts[p] ..< starts[p + 1]]` (three edges a triangle);
/// - words 257 ... 268: the lower corner of each of the twelve edges, then 269 ... 280 the upper corner;
/// - words 281 on: `edges`, every pattern's triangles one after the other.
enum MarchingCubesBuffers {
    static let patternCount = 256
    static let startsOffset = 0
    static let lowerCornersOffset = patternCount + 1
    static let upperCornersOffset = lowerCornersOffset + 12
    static let edgesOffset = upperCornersOffset + 12

    static let words: [UInt32] = {
        var starts: [UInt32] = []
        var edges: [UInt32] = []
        for pattern in MarchingCubesTable.triangles {
            starts.append(UInt32(edges.count))
            edges += pattern.map(UInt32.init)
        }
        starts.append(UInt32(edges.count))
        return starts + MarchingCubesTable.edgeCorners.map { UInt32($0.0) } + MarchingCubesTable.edgeCorners.map { UInt32($0.1) } + edges
    }()
}
````

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --filter "BrickLatticeTests"`
Expected: PASS, 9 tests.

- [ ] **Step 5: Build, warnings, lint**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning"; swiftlint lint --strict 2>&1 | tail -1`
Expected: nothing new; `Found 0 violations, 0 serious`.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorImplicit Tests/CreatorImplicitTests
git commit -m "feat(implicit): BrickLattice edge keys and the case table as a buffer (7c-1g T2)"
```

## Task 3: The Metal kernels and `MetalImplicitEngine.meshBricks`

The GPU mesher. Five kernels (`ImplicitMeshShaderLibrary`), appended to a compiled solid's source so they call its `sdf`, run by an extension of the Metal engine:

1. `meshSample`: the solid's value at each lattice point of a batch of up to 4,096 bricks, at the coordinates `BrickLattice.axisCoordinates` gives (so bit for bit the CPU's).
2. `meshClassify`: per cube, the sign pattern from the batch's samples; the cube's triangles are added to a total (`counters[triangleTotal]`), and for each of its twelve edges whose ends differ in sign a **slot of the edge table** is claimed with a compare-and-swap on the 32-bit key. An edge shared by four cubes, or by two bricks, claims one slot: this is the shared-edge vertex merge. Steps 1 and 2 run for every batch first, so the table holds every edge.
3. `meshNumber`: per slot, an occupied slot takes the next vertex number from an atomic counter.
4. `meshPlace`: per slot, the vertex: linear interpolation along the edge from the two end values, then the Newton step (six more values, at most half a voxel) and the normal, the CPU's `snap` line for line. Steps 3 and 4 run over the table in ranges of 2^20 slots (`MeshParams.firstSlot`), a command buffer each: a slot costs nine evaluations of the solid, so this keeps one command buffer to the order of work the evaluator's 4M-point dispatch is, and a cancel can end a mesh between ranges.
5. `meshEmit`: samples again, per batch; per cube, its triangles take a place from an atomic cursor and each corner is the vertex numbered in its edge's slot.

The table is a flat buffer of 32-bit keys filled with `0xFFFFFFFF` and sized to a power of two; a key that finds no slot within 128 probes sets an overflow flag and the whole attempt reruns with a table twice the size. Nothing waits for another thread: the table is written in one dispatch and only read in the others.

**Files:**
- Create: `Sources/CreatorImplicit/Metal/ImplicitMeshShaderLibrary.swift` (Metal source as text, builds everywhere), `Sources/CreatorImplicit/Metal/MetalImplicitEngine+Meshing.swift` (inside `#if canImport(Metal)`)
- Modify: `Sources/CreatorImplicit/Metal/MetalImplicitEngine.swift` (`device`, `queue`, `Prepared`, `buffers(for:)` and `epoch` lose `private`; stored properties `meshPipelines`, `meshCompileCount` and `meshesMade` are added)
- Test: `Tests/CreatorImplicitTests/MetalMeshingTests.swift` (new)

**Interfaces:**
- Consumes: Task 1's `meshBricks` requirement and `BrickMesh`; Task 2's `BrickLattice`, `MarchingCubesBuffers`; `CompiledImplicit` (`source`, `parameters`, `integers`, `tables`, `pool`, `images`, `id`), `MetalImplicitEngine.Prepared`, `buffers(for:)`.
- Produces:
  - `MetalImplicitEngine.meshBricks(_:_:progress:)` (the actor's implementation of the requirement), `meshCompileCount: Int` (sets of meshing kernels compiled; one per shape) and `meshesMade: Int` (meshes `meshBricks` has returned; the benchmarks read it).
  - `ImplicitMeshShaderLibrary.source(extending: CompiledImplicit) -> String`, `.kernelNames`, `.Binding` (buffer indices 0 to 15), `.Counter` (`vertices`, `triangleTotal`, `triangleCursor`, `overflow`), `.probeLimit` (128).
  - `MetalMeshingTests.request(_ solid:, resolution:, snap:) async throws -> BrickMeshRequest` (the request for every brick of a CPU-planned solid), which Task 4's tests use.

- [ ] **Step 1: Write the failing tests**

The first test is Review Focus 1: it fails if the kernels do not run, whatever the mesh looks like. (Only `meshCompileCount` stops these tests compiling; the requirement's default means `MetalImplicitEngine` already conforms, and without that line they would fail at run time with the mesher falling back to the CPU, `path == .cpu`, and the engine throwing `unsupported`.)

**Create `Tests/CreatorImplicitTests/MetalMeshingTests.swift`**

````swift
#if canImport(Metal)
import CreatorGeometry
import Synchronization
import Testing
@testable import CreatorImplicit

/// Meshing on the Metal engine (implicit spec Errata D13): the basics of what comes back. Its agreement with the CPU mesher is
/// `GPUMeshAgreementTests`; its limits are `MetalMeshingLimitsTests`. Skipped on a machine without a Metal device.
@Suite(.enabled(if: MetalImplicitEngine.shared != nil, "needs a Metal device"))
struct MetalMeshingTests {
    /// The request for every brick of `solid` at `resolution`, planned on the CPU.
    static func request(_ solid: ImplicitSolid, resolution: Double, snap: Bool = true) async throws -> BrickMeshRequest {
        BrickMeshRequest(plan: try await BrickPlan.build(for: solid, resolution: resolution, using: CPUBatchEvaluator(solid)), snap: snap)
    }

    @Test func aSphereMeshedOnTheGPUIsAClosedManifoldWithTheRightVolume() async throws {
        let engine = try #require(MetalImplicitEngine.shared)
        let solid = ImplicitSolid.sphere(radius: 10)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine)
        #expect(selection.evaluator.engineName == "Metal")
        let (mesh, path) = try await ImplicitMesher(evaluator: selection.evaluator)
            .meshReportingPath(solid, resolution: 0.53, quality: .export)
        #expect(path == .gpu)
        let topology = MeshTopology(mesh)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2)
        let exact = 4.0 / 3 * Double.pi * 1000
        #expect(abs(mesh.signedVolume - exact) / exact < 0.005, "volume \(mesh.signedVolume) against \(exact)")
        #expect(mesh.normals.count == mesh.positions.count && mesh.normals.allSatisfy { abs(($0 * $0).sum() - 1) < 1e-4 })
    }

    @Test func withoutTheSnapTheNormalsAreZeroAndTheVerticesAreOnTheLattice() async throws {
        let engine = try #require(MetalImplicitEngine.shared)
        let solid = ImplicitFixtures.sphere
        let program = try await engine.compile(solid)
        let request = try await Self.request(solid, resolution: 0.53, snap: false)
        let mesh = try await engine.meshBricks(program, request) { _ in }
        #expect(mesh.isConsistent && !mesh.triangles.isEmpty)
        #expect(mesh.normals.allSatisfy { $0 == .zero })
        // Each vertex is on a lattice edge, so two of its coordinates are lattice coordinates (to Float precision).
        let step = Float(request.resolution)
        for position in mesh.positions.prefix(500) {
            let onLattice = (0..<3).filter { axis in
                let steps = (position[axis] - Float(request.origin[axis])) / step
                return abs(steps - steps.rounded()) < 1e-3
            }
            #expect(onLattice.count >= 2, "\(position) is not on an edge of the lattice")
        }
    }

    @Test func noBricksIsAnEmptyMesh() async throws {
        let engine = try #require(MetalImplicitEngine.shared)
        let program = try await engine.compile(.sphere(radius: 5))
        let mesh = try await engine.meshBricks(program, BrickMeshRequest(origin: .zero, resolution: 1, bricks: [], snap: true)) { _ in }
        #expect(mesh == BrickMesh(positions: [], normals: [], triangles: []))
    }

    @Test func solidsOfOneShapeShareTheMeshingKernels() async throws {
        let engine = try #require(MetalImplicitEngine())
        for radius in [5.0, 7.5] {
            let solid = ImplicitSolid.sphere(radius: radius)
            let program = try await engine.compile(solid)
            let mesh = try await engine.meshBricks(program, try await Self.request(solid, resolution: 0.7)) { _ in }
            let asMesh = TriangleMesh(positions: mesh.positions, normals: mesh.normals, triangles: mesh.triangles)
            #expect(MeshTopology(asMesh).isClosedManifold)
        }
        #expect(await engine.meshCompileCount == 1)
        let box = ImplicitSolid.box(halfSize: Vector3(3, 3, 3), cornerRadius: 0.5)
        _ = try await engine.meshBricks(try await engine.compile(box), try await Self.request(box, resolution: 0.7)) { _ in }
        #expect(await engine.meshCompileCount == 2)
        #expect(await engine.meshesMade == 3)
    }

    @Test func progressRisesAndNeverPassesOne() async throws {
        let engine = try #require(MetalImplicitEngine.shared)
        let solid = ImplicitFixtures.cylinder
        let seen = ProgressLog()
        _ = try await engine.meshBricks(try await engine.compile(solid), try await Self.request(solid, resolution: 0.6)) { seen.append($0) }
        let values = seen.values
        #expect(values.count >= 3 && values == values.sorted() && (values.last ?? 0) > 0.9 && (values.last ?? 2) <= 1)
    }
}
#endif
````

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head`
Expected: `value of type 'MetalImplicitEngine' has no member 'meshCompileCount'`. (On a machine without a Metal device the suite is not compiled and there is nothing to run.)

- [ ] **Step 3: Implement**

Notes that cost time once and need not again. `vertex`, `kernel`, `device`, `constant`, `thread` and `threadgroup` are reserved in Metal: a variable named `vertex` fails the library compile, which `meshBricks` reports as `.engine`, which the mesher turns into a silent CPU mesh; the kernels name it `number`. A local named `step` or `length` shadows a Metal function; they are `delta` and `moved`. The output buffers are `float4` per vertex so the bytes read straight into `[SIMD3<Float>]` (16-byte stride). Counters and the table are cleared on the GPU (`fill`) and by the CPU (shared storage). Every batch (and each range of slots of the number and place steps, and each of the other steps) is its own command buffer, awaited, with a cancellation check after it: that is where `cancel()` and a cancelled task end a mesh.

**Create `Sources/CreatorImplicit/Metal/ImplicitMeshShaderLibrary.swift`**

````swift
/// The meshing kernels of a GPU engine (implicit spec §4.3, Errata D13), as Metal Shading Language text appended to a
/// `CompiledImplicit`'s source so they call its `sdf`. Text only: it imports nothing and builds everywhere, and an SDL3 engine (track
/// xp-c) translates it, as it will the evaluator's source. Every kernel is a line-for-line port of the CPU mesher (`MeshBuilder`,
/// `ImplicitMesher.snap`) and reads the same `MarchingCubesTable` through `MarchingCubesBuffers`.
///
/// One mesh is five dispatches over a shared table of edge keys (`BrickLattice`'s numbering):
/// 1. `meshSample`, per lattice point of a batch of bricks: the solid's value, at the CPU's coordinates;
/// 2. `meshClassify`, per cube: its pattern; adds its triangles to the total; claims a table slot for each lattice edge it crosses
///    (compare and swap on the key, so an edge shared by four cubes, or by two bricks, is one slot);
///    steps 1 and 2 run for every batch before step 3, so the table holds every edge;
/// 3. `meshNumber`, per table slot: the slot's vertex number;
/// 4. `meshPlace`, per table slot: the vertex on its edge by linear interpolation, then the Newton step and the normal; steps 3 and 4
///    run over the table in ranges of slots (`MeshParams.firstSlot`), a command buffer each, so no one buffer holds millions of
///    evaluations of a heavy `sdf` (the GPU's watchdog) and a cancel can end a mesh between them;
/// 5. `meshEmit`, per cube (samples again, per batch): its triangles, each corner the vertex of its edge's slot, at a place in the
///    index buffer taken from an atomic cursor.
///
/// Slots and cursor places are taken in whatever order the threads run, so the *order* of vertices and triangles differs from run to
/// run; the set does not.
enum ImplicitMeshShaderLibrary {
    /// Buffer indices every kernel shares. A kernel declares the ones it reads.
    enum Binding {
        static let bricks = 0
        static let axes = 1
        static let samples = 2
        static let parameters = 3, integers = 4, tables = 5, pool = 6, images = 7
        static let meshParameters = 8
        static let cubeTable = 9
        static let keys = 10
        static let slotVertex = 11
        static let counters = 12
        static let positions = 13
        static let normals = 14
        static let indices = 15
    }

    /// Indices into the counters buffer.
    enum Counter {
        /// Vertices numbered by `meshNumber`.
        static let vertices = 0
        /// Triangles `meshClassify` found, over every batch.
        static let triangleTotal = 1
        /// The next free triangle of the index buffer.
        static let triangleCursor = 2
        /// Set when a key found no slot within `probeLimit` steps: the table is too small.
        static let overflow = 3
        static let count = 4
    }

    /// The longest run of occupied slots a key will walk past before the table is called too small.
    static let probeLimit = 128

    /// The kernels' names, in the order of the five steps.
    static let kernelNames = ["meshSample", "meshClassify", "meshNumber", "meshPlace", "meshEmit"]

    /// The Metal source of `program` with the meshing kernels added.
    static func source(extending program: CompiledImplicit) -> String {
        program.source + "\n" + kernels
    }

    private static let kernels = """
    struct MeshParams {
        uint firstBrick;
        uint brickCount;
        uint nx;
        uint ny;
        uint nz;
        uint mask;
        uint snap;
        float resolution;
        uint firstSlot;
    };

    constant uint EMPTY_KEY = 0xFFFFFFFFu;
    constant uint CUBE_STARTS = \(MarchingCubesBuffers.startsOffset)u;
    constant uint CUBE_LOWER = \(MarchingCubesBuffers.lowerCornersOffset)u;
    constant uint CUBE_UPPER = \(MarchingCubesBuffers.upperCornersOffset)u;
    constant uint CUBE_EDGES = \(MarchingCubesBuffers.edgesOffset)u;
    constant uint BRICK = \(BrickPlan.brickSize)u;
    constant uint SIDE = \(BrickPlan.brickSize + 1)u;
    constant uint CUBES = \(BrickPlan.brickSize * BrickPlan.brickSize * BrickPlan.brickSize)u;
    constant uint POINTS = \((BrickPlan.brickSize + 1) * (BrickPlan.brickSize + 1) * (BrickPlan.brickSize + 1))u;

    inline uint tableHash(uint key, uint mask) {
        uint h = key * 0x9E3779B1u;
        h ^= h >> 16;
        h *= 0x85EBCA6Bu;
        h ^= h >> 13;
        return h & mask;
    }

    inline float3 latticePoint(device const float* axes, constant MeshParams& m, uint x, uint y, uint z) {
        return float3(axes[x], axes[m.nx + y], axes[m.nx + m.ny + z]);
    }

    // The key of the edge between corners a and b of the cube whose lowest lattice point is (x, y, z): the CPU's formula.
    inline uint edgeKey(constant MeshParams& m, uint x, uint y, uint z, uint a, uint b) {
        uint lx = x + (a & 1u), ly = y + ((a >> 1) & 1u), lz = z + ((a >> 2) & 1u);
        uint axis = ((a ^ b) == 1u) ? 0u : (((a ^ b) == 2u) ? 1u : 2u);
        return ((lz * m.ny + ly) * m.nx + lx) * 3u + axis;
    }

    inline float cornerValue(device const float* samples, uint base, uint x, uint y, uint z, uint corner) {
        return samples[base + ((z + (corner >> 2)) * SIDE + y + ((corner >> 1) & 1u)) * SIDE + x + (corner & 1u)];
    }

    inline uint cubePattern(device const float* samples, uint base, uint x, uint y, uint z) {
        uint pattern = 0u;
        for (uint corner = 0u; corner < 8u; ++corner) {
            if (cornerValue(samples, base, x, y, z, corner) < 0.0) { pattern |= 1u << corner; }
        }
        return pattern;
    }

    inline void claimSlot(device atomic_uint* keys, device atomic_uint* counters, uint mask, uint key) {
        uint slot = tableHash(key, mask);
        for (uint probe = 0u; probe < \(probeLimit)u; ++probe) {
            uint expected = EMPTY_KEY;
            bool won = atomic_compare_exchange_weak_explicit(&keys[slot], &expected, key,
                                                             memory_order_relaxed, memory_order_relaxed);
            if (won || expected == key) { return; }
            // A spurious failure leaves the slot empty: try it again. Otherwise it holds another key: go on.
            if (expected != EMPTY_KEY) { slot = (slot + 1u) & mask; }
        }
        atomic_store_explicit(&counters[\(Counter.overflow)], 1u, memory_order_relaxed);
    }

    inline uint vertexOfKey(device const uint* keys, device const uint* slotVertex, uint mask, uint key) {
        uint slot = tableHash(key, mask);
        for (uint probe = 0u; probe <= mask; ++probe) {
            if (keys[slot] == key) { return slotVertex[slot]; }
            slot = (slot + 1u) & mask;
        }
        return 0u;
    }

    kernel void meshSample(device const uint* bricks [[buffer(\(Binding.bricks))]],
                           device const float* axes [[buffer(\(Binding.axes))]],
                           device float* samples [[buffer(\(Binding.samples))]],
                           device const float* P [[buffer(\(Binding.parameters))]],
                           device const int* I [[buffer(\(Binding.integers))]],
                           device const int* tables [[buffer(\(Binding.tables))]],
                           device const float* pool [[buffer(\(Binding.pool))]],
                           device const float* images [[buffer(\(Binding.images))]],
                           constant MeshParams& m [[buffer(\(Binding.meshParameters))]],
                           uint gid [[thread_position_in_grid]]) {
        if (gid >= m.brickCount * POINTS) { return; }
        uint b = gid / POINTS, r = gid % POINTS;
        uint x = r % SIDE, y = (r / SIDE) % SIDE, z = r / (SIDE * SIDE);
        uint at = (m.firstBrick + b) * 3u;
        Env e = { P, I, tables, pool, images };
        float3 point = latticePoint(axes, m, bricks[at] * BRICK + x, bricks[at + 1u] * BRICK + y, bricks[at + 2u] * BRICK + z);
        samples[gid] = sdf(e, point);
    }

    kernel void meshClassify(device const uint* bricks [[buffer(\(Binding.bricks))]],
                             device const float* samples [[buffer(\(Binding.samples))]],
                             constant MeshParams& m [[buffer(\(Binding.meshParameters))]],
                             device const uint* cubeTable [[buffer(\(Binding.cubeTable))]],
                             device atomic_uint* keys [[buffer(\(Binding.keys))]],
                             device atomic_uint* counters [[buffer(\(Binding.counters))]],
                             uint gid [[thread_position_in_grid]]) {
        if (gid >= m.brickCount * CUBES) { return; }
        uint b = gid / CUBES, c = gid % CUBES;
        uint x = c % BRICK, y = (c / BRICK) % BRICK, z = c / (BRICK * BRICK);
        uint pattern = cubePattern(samples, b * POINTS, x, y, z);
        uint begin = cubeTable[CUBE_STARTS + pattern], end = cubeTable[CUBE_STARTS + pattern + 1u];
        if (begin == end) { return; }
        atomic_fetch_add_explicit(&counters[\(Counter.triangleTotal)], (end - begin) / 3u, memory_order_relaxed);
        uint at = (m.firstBrick + b) * 3u;
        uint lx = bricks[at] * BRICK + x, ly = bricks[at + 1u] * BRICK + y, lz = bricks[at + 2u] * BRICK + z;
        for (uint edge = 0u; edge < 12u; ++edge) {
            uint low = cubeTable[CUBE_LOWER + edge], high = cubeTable[CUBE_UPPER + edge];
            if (((pattern >> low) & 1u) != ((pattern >> high) & 1u)) {
                claimSlot(keys, counters, m.mask, edgeKey(m, lx, ly, lz, low, high));
            }
        }
    }

    kernel void meshNumber(constant MeshParams& m [[buffer(\(Binding.meshParameters))]],
                           device const uint* keys [[buffer(\(Binding.keys))]],
                           device uint* slotVertex [[buffer(\(Binding.slotVertex))]],
                           device atomic_uint* counters [[buffer(\(Binding.counters))]],
                           uint gid [[thread_position_in_grid]]) {
        uint slot = m.firstSlot + gid;
        if (slot > m.mask || keys[slot] == EMPTY_KEY) { return; }
        slotVertex[slot] = atomic_fetch_add_explicit(&counters[\(Counter.vertices)], 1u, memory_order_relaxed);
    }

    kernel void meshPlace(device const float* axes [[buffer(\(Binding.axes))]],
                          device const float* P [[buffer(\(Binding.parameters))]],
                          device const int* I [[buffer(\(Binding.integers))]],
                          device const int* tables [[buffer(\(Binding.tables))]],
                          device const float* pool [[buffer(\(Binding.pool))]],
                          device const float* images [[buffer(\(Binding.images))]],
                          constant MeshParams& m [[buffer(\(Binding.meshParameters))]],
                          device const uint* keys [[buffer(\(Binding.keys))]],
                          device const uint* slotVertex [[buffer(\(Binding.slotVertex))]],
                          device float4* positions [[buffer(\(Binding.positions))]],
                          device float4* normals [[buffer(\(Binding.normals))]],
                          uint gid [[thread_position_in_grid]]) {
        uint slot = m.firstSlot + gid;
        if (slot > m.mask) { return; }
        uint key = keys[slot];
        if (key == EMPTY_KEY) { return; }
        uint axis = key % 3u, index = key / 3u;
        uint x = index % m.nx, y = (index / m.nx) % m.ny, z = index / (m.nx * m.ny);
        Env e = { P, I, tables, pool, images };
        float3 low = latticePoint(axes, m, x, y, z);
        float3 high = latticePoint(axes, m, x + (axis == 0u ? 1u : 0u), y + (axis == 1u ? 1u : 0u),
                                   z + (axis == 2u ? 1u : 0u));
        float fa = sdf(e, low), fb = sdf(e, high);
        float t = fa / (fa - fb);
        float3 position = low;
        position[axis] = low[axis] + m.resolution * t;
        float3 normal = float3(0.0);
        if (m.snap != 0u) {
            float delta = m.resolution / 4.0, limit = m.resolution / 2.0;
            float value = sdf(e, position);
            float3 gradient = float3(
                (sdf(e, position + float3(delta, 0.0, 0.0)) - sdf(e, position - float3(delta, 0.0, 0.0))) / (2.0 * delta),
                (sdf(e, position + float3(0.0, delta, 0.0)) - sdf(e, position - float3(0.0, delta, 0.0))) / (2.0 * delta),
                (sdf(e, position + float3(0.0, 0.0, delta)) - sdf(e, position - float3(0.0, 0.0, delta))) / (2.0 * delta));
            float squared = dot(gradient, gradient);
            if (squared > 1e-12) {
                normal = gradient / sqrt(squared);
                float3 move = gradient * (-value / squared);
                float moved = sqrt(dot(move, move));
                if (moved > limit) { move *= limit / moved; }
                position += move;
            }
        }
        uint number = slotVertex[slot];
        positions[number] = float4(position, 0.0);
        normals[number] = float4(normal, 0.0);
    }

    kernel void meshEmit(device const uint* bricks [[buffer(\(Binding.bricks))]],
                         device const float* samples [[buffer(\(Binding.samples))]],
                         constant MeshParams& m [[buffer(\(Binding.meshParameters))]],
                         device const uint* cubeTable [[buffer(\(Binding.cubeTable))]],
                         device const uint* keys [[buffer(\(Binding.keys))]],
                         device const uint* slotVertex [[buffer(\(Binding.slotVertex))]],
                         device atomic_uint* counters [[buffer(\(Binding.counters))]],
                         device uint* indices [[buffer(\(Binding.indices))]],
                         uint gid [[thread_position_in_grid]]) {
        if (gid >= m.brickCount * CUBES) { return; }
        uint b = gid / CUBES, c = gid % CUBES;
        uint x = c % BRICK, y = (c / BRICK) % BRICK, z = c / (BRICK * BRICK);
        uint pattern = cubePattern(samples, b * POINTS, x, y, z);
        uint begin = cubeTable[CUBE_STARTS + pattern], end = cubeTable[CUBE_STARTS + pattern + 1u];
        if (begin == end) { return; }
        uint at = (m.firstBrick + b) * 3u;
        uint lx = bricks[at] * BRICK + x, ly = bricks[at + 1u] * BRICK + y, lz = bricks[at + 2u] * BRICK + z;
        uint place = atomic_fetch_add_explicit(&counters[\(Counter.triangleCursor)], (end - begin) / 3u, memory_order_relaxed);
        uint first = place * 3u;
        for (uint corner = 0u; corner < end - begin; ++corner) {
            uint edge = cubeTable[CUBE_EDGES + begin + corner];
            uint key = edgeKey(m, lx, ly, lz, cubeTable[CUBE_LOWER + edge], cubeTable[CUBE_UPPER + edge]);
            indices[first + corner] = vertexOfKey(keys, slotVertex, m.mask, key);
        }
    }
    """
}
````

**Create `Sources/CreatorImplicit/Metal/MetalImplicitEngine+Meshing.swift`**

````swift
#if canImport(Metal)
import Foundation
@preconcurrency import Metal

/// Marching cubes on the GPU (implicit spec §4.3, Errata D13): the five kernels of `ImplicitMeshShaderLibrary` run over the bricks of
/// a `BrickMeshRequest`. The CPU mesher stays the reference; this is the same algorithm with the same table, one vertex per lattice
/// edge and the same Newton step, and `GPUMeshAgreementTests` holds the two to the same topology and 1e-4 mm.
extension MetalImplicitEngine {
    /// The compiled meshing kernels of one shape.
    struct MeshPipelines {
        var sample: any MTLComputePipelineState
        var classify: any MTLComputePipelineState
        var number: any MTLComputePipelineState
        var place: any MTLComputePipelineState
        var emit: any MTLComputePipelineState
    }

    /// `MeshParams` of the shader, field for field.
    struct MeshParameters {
        var firstBrick: UInt32 = 0
        var brickCount: UInt32 = 0
        var nx: UInt32 = 0
        var ny: UInt32 = 0
        var nz: UInt32 = 0
        var mask: UInt32 = 0
        var snap: UInt32 = 0
        var resolution: Float = 0
        var firstSlot: UInt32 = 0
    }

    /// What one mesh needs that does not change from attempt to attempt.
    private struct MeshJob {
        var pipelines: MeshPipelines
        var solid: Prepared
        var bricks: any MTLBuffer
        var axes: any MTLBuffer
        var cube: any MTLBuffer
        var parameters: MeshParameters
        var brickCount: Int
        var started: Int
        /// How many table slots one command buffer takes in the number and place steps.
        var slotsPerDispatch: Int
    }

    /// One attempt at one table size: its buffers and the parameters the dispatches are made with.
    private struct MeshRun {
        var job: MeshJob
        var buffers: MeshBuffers
        var parameters: MeshParameters
        let slots: Int
        let batch: Int
    }

    /// The buffers of one attempt at one table size.
    private struct MeshBuffers {
        var samples: any MTLBuffer
        var keys: any MTLBuffer
        var slotVertex: any MTLBuffer
        var counters: any MTLBuffer
        var positions: any MTLBuffer
        var normals: any MTLBuffer
        var indices: any MTLBuffer
    }

    /// How many bricks are sampled and meshed in one pair of dispatches (4,096 as in implicit spec §4.2: 12 MB of samples).
    static let meshBatchBricks = 4096
    /// The first table has this many slots for each brick; a table that proves too small is doubled.
    static let tableSlotsPerBrick = 256
    /// The most slots a table gets (8 bytes each); a mesh needing more is left to the CPU.
    static let largestTable = 1 << 27
    /// How many table slots one command buffer numbers or places: a slot costs up to nine evaluations of the solid, so this keeps one
    /// buffer to the same order of work as the evaluator's (`pointsPerDispatch` points).
    static let slotsPerDispatch = 1 << 20

    public func meshBricks(_ program: CompiledImplicit, _ request: BrickMeshRequest,
                           progress: @Sendable (Double) -> Void) async throws -> BrickMesh {
        try Task.checkCancellation()
        guard !request.bricks.isEmpty else { return BrickMesh(positions: [], normals: [], triangles: []) }
        guard let lattice = BrickLattice(request.bricks), lattice.fitsEdgeKeys else {
            throw ImplicitCompileError.unsupported("the bricks span more lattice edges than a 32-bit key numbers")
        }
        let started = epoch
        let pipelines = try await meshPipelines(for: program)
        let size = lattice.points
        var parameters = MeshParameters()
        (parameters.nx, parameters.ny, parameters.nz) = (UInt32(size.x), UInt32(size.y), UInt32(size.z))
        parameters.snap = request.snap ? 1 : 0
        parameters.resolution = Float(request.resolution)
        let job = MeshJob(
            pipelines: pipelines, solid: try buffers(for: program), bricks: try meshUpload(lattice.relativeBricks(request.bricks)),
            axes: try meshUpload(lattice.axisCoordinates(origin: request.origin, resolution: request.resolution)),
            cube: try meshUpload(MarchingCubesBuffers.words), parameters: parameters, brickCount: request.bricks.count, started: started,
            slotsPerDispatch: Self.slotsPerDispatch)
        var slots = 1 << max(12, Int.bitWidth - (request.bricks.count * Self.tableSlotsPerBrick - 1).leadingZeroBitCount)
        while true {
            guard slots <= Self.largestTable else {
                throw ImplicitCompileError.unsupported("the edge table would pass \(Self.largestTable) slots")
            }
            if let mesh = try await meshAttempt(job, slots: slots, batch: Self.meshBatchBricks, progress: progress) {
                meshesMade += 1
                return mesh
            }
            slots *= 2
        }
    }

    /// One run of the five steps with a table of `slots`; `nil` when the table proved too small.
    private func meshAttempt(_ job: MeshJob, slots: Int, batch: Int, progress: @Sendable (Double) -> Void) async throws -> BrickMesh? {
        var run = try await startRun(job, slots: slots, batch: batch)
        // Steps 1 and 2 for every batch: afterwards the table holds every edge the surface crosses.
        try await sweep(&run, emitting: false, from: 0, to: 0.4, progress: progress)
        var counts = readCounters(run.buffers)
        if counts[ImplicitMeshShaderLibrary.Counter.overflow] != 0 { return nil }
        let triangles = Int(counts[ImplicitMeshShaderLibrary.Counter.triangleTotal])
        try await sweepSlots(&run, run.job.pipelines.number)
        counts = readCounters(run.buffers)
        let vertices = Int(counts[ImplicitMeshShaderLibrary.Counter.vertices])
        guard vertices > 0, triangles > 0 else { return BrickMesh(positions: [], normals: [], triangles: []) }
        run.buffers.positions = try meshBuffer(vertices * 16)
        run.buffers.normals = try meshBuffer(vertices * 16)
        run.buffers.indices = try meshBuffer(triangles * 12)
        try await sweepSlots(&run, run.job.pipelines.place)
        progress(0.55)
        try await sweep(&run, emitting: true, from: 0.55, to: 0.95, progress: progress)
        guard readCounters(run.buffers)[ImplicitMeshShaderLibrary.Counter.triangleCursor] == UInt32(triangles) else {
            throw ImplicitCompileError.engine("the GPU emitted a different number of triangles than it counted")
        }
        return BrickMesh(positions: Self.read(run.buffers.positions, SIMD3<Float>.self, count: vertices),
                         normals: Self.read(run.buffers.normals, SIMD3<Float>.self, count: vertices),
                         triangles: Self.read(run.buffers.indices, UInt32.self, count: triangles * 3))
    }

    /// The buffers of an attempt, the counters cleared and the table emptied.
    private func startRun(_ job: MeshJob, slots: Int, batch: Int) async throws -> MeshRun {
        var parameters = job.parameters
        parameters.mask = UInt32(slots - 1)
        let counterCount = ImplicitMeshShaderLibrary.Counter.count
        let buffers = MeshBuffers(
            samples: try meshBuffer(batch * 729 * 4), keys: try meshBuffer(slots * 4), slotVertex: try meshBuffer(slots * 4),
            counters: try meshBuffer(counterCount * 4), positions: try meshBuffer(16), normals: try meshBuffer(16),
            indices: try meshBuffer(16))
        buffers.counters.contents().initializeMemory(as: UInt32.self, repeating: 0, count: counterCount)
        try await submit { commands in
            let blit = commands.makeBlitCommandEncoder()
            blit?.fill(buffer: buffers.keys, range: 0..<buffers.keys.length, value: 0xFF)
            blit?.endEncoding()
        }
        return MeshRun(job: job, buffers: buffers, parameters: parameters, slots: slots, batch: batch)
    }

    /// Samples every batch of bricks and then classifies its cubes (step 2) or emits its triangles (step 5); progress runs `from` to `to`.
    private func sweep(_ run: inout MeshRun, emitting: Bool, from: Double, to: Double, progress: @Sendable (Double) -> Void) async throws {
        let total = run.job.brickCount
        for first in stride(from: 0, to: total, by: run.batch) {
            let count = min(run.batch, total - first)
            (run.parameters.firstBrick, run.parameters.brickCount) = (UInt32(first), UInt32(count))
            try await submit { encoder in
                bind(encoder, run.job, run.buffers, &run.parameters)
                dispatch(encoder, run.job.pipelines.sample, threads: count * 729)
                dispatch(encoder, emitting ? run.job.pipelines.emit : run.job.pipelines.classify, threads: count * 512)
            }
            try checkRunning(run.job)
            progress(from + (to - from) * Double(first + count) / Double(total))
        }
    }

    /// Runs a per-slot kernel (`meshNumber`, `meshPlace`) over the whole table, `slotsPerDispatch` slots to a command buffer.
    private func sweepSlots(_ run: inout MeshRun, _ pipeline: any MTLComputePipelineState) async throws {
        for first in stride(from: 0, to: run.slots, by: run.job.slotsPerDispatch) {
            run.parameters.firstSlot = UInt32(first)
            let count = min(run.job.slotsPerDispatch, run.slots - first)
            try await submit { encoder in
                bind(encoder, run.job, run.buffers, &run.parameters)
                dispatch(encoder, pipeline, threads: count)
            }
            try checkRunning(run.job)
        }
    }

    // MARK: Pipelines

    /// The meshing kernels for `program`'s shape, compiled once: they are the program's source with the kernels appended.
    private func meshPipelines(for program: CompiledImplicit) async throws -> MeshPipelines {
        if let known = meshPipelines[program.source] { return known }
        do {
            let library = try await device.makeLibrary(source: ImplicitMeshShaderLibrary.source(extending: program), options: nil)
            var made: [any MTLComputePipelineState] = []
            for name in ImplicitMeshShaderLibrary.kernelNames {
                guard let function = library.makeFunction(name: name) else {
                    throw ImplicitCompileError.engine("the kernel \(name) is missing")
                }
                made.append(try await device.makeComputePipelineState(function: function))
            }
            let pipelines = MeshPipelines(sample: made[0], classify: made[1], number: made[2], place: made[3], emit: made[4])
            meshCompileCount += 1
            if let raced = meshPipelines[program.source] { return raced }
            meshPipelines[program.source] = pipelines
            return pipelines
        } catch let error as ImplicitCompileError {
            throw error
        } catch {
            throw ImplicitCompileError.engine(error.localizedDescription)
        }
    }

    // MARK: Encoding

    private func bind(_ encoder: any MTLComputeCommandEncoder, _ job: MeshJob, _ buffers: MeshBuffers, _ parameters: inout MeshParameters) {
        typealias Binding = ImplicitMeshShaderLibrary.Binding
        encoder.setBuffer(job.bricks, offset: 0, index: Binding.bricks)
        encoder.setBuffer(job.axes, offset: 0, index: Binding.axes)
        encoder.setBuffer(buffers.samples, offset: 0, index: Binding.samples)
        encoder.setBuffer(job.solid.parameters, offset: 0, index: Binding.parameters)
        encoder.setBuffer(job.solid.integers, offset: 0, index: Binding.integers)
        encoder.setBuffer(job.solid.tables, offset: 0, index: Binding.tables)
        encoder.setBuffer(job.solid.pool, offset: 0, index: Binding.pool)
        encoder.setBuffer(job.solid.images, offset: 0, index: Binding.images)
        encoder.setBytes(&parameters, length: MemoryLayout<MeshParameters>.stride, index: Binding.meshParameters)
        encoder.setBuffer(job.cube, offset: 0, index: Binding.cubeTable)
        encoder.setBuffer(buffers.keys, offset: 0, index: Binding.keys)
        encoder.setBuffer(buffers.slotVertex, offset: 0, index: Binding.slotVertex)
        encoder.setBuffer(buffers.counters, offset: 0, index: Binding.counters)
        encoder.setBuffer(buffers.positions, offset: 0, index: Binding.positions)
        encoder.setBuffer(buffers.normals, offset: 0, index: Binding.normals)
        encoder.setBuffer(buffers.indices, offset: 0, index: Binding.indices)
    }

    private func dispatch(_ encoder: any MTLComputeCommandEncoder, _ pipeline: any MTLComputePipelineState, threads: Int) {
        guard threads > 0 else { return }
        encoder.setComputePipelineState(pipeline)
        let width = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        encoder.dispatchThreads(MTLSize(width: threads, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
    }

    /// Encodes with `encode` into one command buffer, runs it and waits.
    private func submit(_ encode: (any MTLCommandBuffer) -> Void) async throws {
        guard let commands = queue.makeCommandBuffer() else { throw ImplicitCompileError.engine("a GPU command buffer could not be made") }
        encode(commands)
        await withCheckedContinuation { continuation in
            commands.addCompletedHandler { _ in continuation.resume() }
            commands.commit()
        }
        if let error = commands.error { throw ImplicitCompileError.engine(error.localizedDescription) }
    }

    /// Runs one compute encoder: `encode` fills it.
    private func submit(_ encode: (any MTLComputeCommandEncoder) -> Void) async throws {
        try await submit { (commands: any MTLCommandBuffer) in
            guard let encoder = commands.makeComputeCommandEncoder() else { return }
            encode(encoder)
            encoder.endEncoding()
        }
    }

    private func checkRunning(_ job: MeshJob) throws {
        try Task.checkCancellation()
        if epoch != job.started { throw CancellationError() }
    }

    // MARK: Buffers

    /// A buffer of `length` bytes, or "unsupported": a request this big is the CPU's.
    private func meshBuffer(_ length: Int) throws -> any MTLBuffer {
        guard length <= device.maxBufferLength, let buffer = device.makeBuffer(length: max(length, 16), options: .storageModeShared) else {
            throw ImplicitCompileError.unsupported("a GPU buffer of \(length) bytes could not be made")
        }
        return buffer
    }

    private func meshUpload<T>(_ values: [T]) throws -> any MTLBuffer {
        let buffer = try meshBuffer(values.count * MemoryLayout<T>.stride)
        values.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress { buffer.contents().copyMemory(from: base, byteCount: bytes.count) }
        }
        return buffer
    }

    private func readCounters(_ buffers: MeshBuffers) -> [UInt32] {
        Self.read(buffers.counters, UInt32.self, count: ImplicitMeshShaderLibrary.Counter.count)
    }

    private static func read<T>(_ buffer: any MTLBuffer, _ type: T.Type, count: Int) -> [T] {
        Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: T.self, capacity: count), count: count))
    }
}
#endif
````

**Edit `Sources/CreatorImplicit/Metal/MetalImplicitEngine.swift`**

Replace:

````swift
    public static let shared: MetalImplicitEngine? = MetalImplicitEngine()

    /// A solid's uploaded parameters.
    private struct Prepared {
        var parameters: any MTLBuffer
        var integers: any MTLBuffer
        var tables: any MTLBuffer
````

With:

````swift
    public static let shared: MetalImplicitEngine? = MetalImplicitEngine()

    /// A solid's uploaded parameters.
    struct Prepared {
        var parameters: any MTLBuffer
        var integers: any MTLBuffer
        var tables: any MTLBuffer
````

**Edit `Sources/CreatorImplicit/Metal/MetalImplicitEngine.swift`**

Replace:

````swift
        var used: Int
    }

    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private var pipelines: [String: any MTLComputePipelineState] = [:]
    private var prepared: [UUID: Prepared] = [:]
    private var clock = 0
````

With:

````swift
        var used: Int
    }

    let device: any MTLDevice
    let queue: any MTLCommandQueue
    private var pipelines: [String: any MTLComputePipelineState] = [:]
    private var prepared: [UUID: Prepared] = [:]
    private var clock = 0
````

**Edit `Sources/CreatorImplicit/Metal/MetalImplicitEngine.swift`**

Replace:

````swift

    public nonisolated let name = "Metal"

    /// Bumped by `cancel()`: a batch that started before it ends at its next dispatch.
    private var epoch = 0

    public init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
````

With:

````swift

    public nonisolated let name = "Metal"

    /// The meshing kernels of each shape, keyed by the program's source (`MetalImplicitEngine+Meshing.swift`).
    var meshPipelines: [String: MeshPipelines] = [:]
    /// How many sets of meshing pipelines were compiled.
    public internal(set) var meshCompileCount = 0
    /// How many meshes `meshBricks` has made: the benchmarks use it to see that a row's meshes were made on the GPU.
    public internal(set) var meshesMade = 0

    /// Bumped by `cancel()`: a batch that started before it ends at its next dispatch.
    var epoch = 0

    public init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
````

**Edit `Sources/CreatorImplicit/Metal/MetalImplicitEngine.swift`**

Replace:

````swift
    }

    /// The solid's buffers, uploaded on first use; the least recently used solid's are dropped past `preparedLimit`.
    private func buffers(for program: CompiledImplicit) throws -> Prepared {
        clock += 1
        if var known = prepared[program.id] {
            known.used = clock
````

With:

````swift
    }

    /// The solid's buffers, uploaded on first use; the least recently used solid's are dropped past `preparedLimit`.
    func buffers(for program: CompiledImplicit) throws -> Prepared {
        clock += 1
        if var known = prepared[program.id] {
            known.used = clock
````

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --filter "MetalMeshingTests|ImplicitPortabilityTests|GPUAgreementTests|GPUBatchEvaluatorTests|BrickMeshingTests|BrickLatticeTests"`
Expected: PASS; `MetalMeshingTests` is 5 tests. `ImplicitPortabilityTests` passes unchanged: `ImplicitMeshShaderLibrary.swift` imports nothing and names no `MTL…` type, and `MetalImplicitEngine+Meshing.swift` is wholly inside `#if canImport(Metal)`.

- [ ] **Step 5: Build, warnings, lint**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning"; swiftlint lint --strict 2>&1 | tail -1`
Expected: nothing new; `Found 0 violations, 0 serious`. (The kernel text has lines up to 140 columns like any Swift; wrap them as the file does.)

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorImplicit Tests/CreatorImplicitTests
git commit -m "feat(implicit): marching cubes on the GPU, MetalImplicitEngine.meshBricks (7c-1g T3)"
```

## Task 4: The GPU against the CPU: the agreement suite and the limits

The suite D13 asks for, and the engine's edges. Two comparisons per fixture, because two things can differ (U2): the mesher alone (same samples) and the whole pipeline (CPU evaluator against GPU evaluator). Its yardstick, `MeshComparison`, is portable and has its own tests. The engine gains `MeshTuning`, a struct of the three sizes meshing works in (batch of bricks, first table size per brick, largest table), so the limits tests can reach the multi-batch, multi-range, retry and fall-back paths on a small mesh (and, through its `afterBatch` hook, cancel at a known batch); the defaults are Task 3's constants.

**Files:**
- Modify: `Sources/CreatorImplicit/Metal/MetalImplicitEngine.swift` (the `meshTuning` stored property), `Sources/CreatorImplicit/Metal/MetalImplicitEngine+Meshing.swift` (`MeshTuning`, `tune(_:)`, constants become tuning)
- Create: `Tests/CreatorImplicitTests/Support/MeshComparison.swift`, `Tests/CreatorImplicitTests/MeshComparisonTests.swift`, `Tests/CreatorImplicitTests/GPUMeshAgreementTests.swift`, `Tests/CreatorImplicitTests/MetalMeshingLimitsTests.swift`

**Interfaces:**
- Consumes: Tasks 1 to 3; `GPUFixtures.all`, `MeshFixtures.cube`, `ProgressLog`, `MetalMeshingTests.request`.
- Produces:
  - `MetalImplicitEngine.MeshTuning { var batchBricks = 4096; var slotsPerBrick = 256; var largestTable = 1 << 27; var slotsPerDispatch = 1 << 20; var afterBatch: (@Sendable (Int) async -> Void)? }` and `MetalImplicitEngine.tune(_:)` (internal; tests only; nothing in the engine sets `afterBatch`).
  - `MeshComparison(reference:candidate:searchRadius:)` with `farthest`, `farthestAlongNormal`, `smallestNormalDot`, `unmatched`; `BrickMesh.triangleMesh`; `SamplesOnlyEvaluator(inner:)` (an evaluator that never meshes: the CPU mesher over a GPU's values), all in `Tests/CreatorImplicitTests/Support/MeshComparison.swift`.
  - `GPUMeshAgreementTests.vertexTolerance` (1e-4), `slideTolerance` (2e-3), `mesherNormalDot` (0.9999), `pipelineNormalDot` (0.999), `volumeTolerance` (1e-3), `triangleTolerance` (0.001), `names`, `resolution(of:)`.

- [ ] **Step 1: Write the failing tests**

The yardstick's own tests (a known slide, a known rise, a normal turned around, an unmatched vertex), the agreement suite over every fixture of `GPUFixtures.all` that makes a surface (topology, vertices, **normals and the enclosed volume**: positions alone leave an inverted normal or a reversed winding undetected), and the limits: a batch of 7 bricks gives the set a batch of 4,096 does; ranges of 1,000 slots give the set one range does; a table of one slot a brick is doubled until it fits; a table capped at 4,096 slots sends the mesh to the CPU through the mesher; two bricks 1,200 bricks apart are unsupported; a part 4 m from the origin meshes in a small window; the same bricks twice give the same set; a cancel, from the task or from the engine, ends a mesh at its next batch (the test cancels at a known batch and expects the throw) and not the next mesh. The resolution is about 60 voxels across a fixture, not coarser (Risks).

**Create `Tests/CreatorImplicitTests/GPUMeshAgreementTests.swift`**

````swift
#if canImport(Metal)
import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The GPU mesher against the CPU mesher (implicit spec §4.3, §7, Errata D13): the same fixtures as the evaluator's agreement suite,
/// meshed both ways. Compiled only where Metal exists and skipped on a machine without a Metal device.
///
/// Two comparisons, because there are two things that can differ:
/// - **The mesher**, with the same sample values: the CPU mesher over the GPU engine's values (what meshing was before D13) against
///   the GPU mesher. The same topology, the same triangle count, and every vertex within 1e-4 mm (D13). On the fixtures the largest
///   difference is about 2e-5 mm.
/// - **The whole pipeline**: the CPU mesher over the CPU evaluator, the reference, against the GPU's. The evaluators agree to 1e-4
///   mm (`GPUAgreementTests`) and the mesh interpolates along lattice edges, so where an edge runs nearly tangent to the surface a
///   value difference of 1e-6 slides the vertex along the surface by 1e-4 or more: on the fixtures up to 9e-4 mm, with the surfaces
///   themselves within 2e-5 mm. So the surfaces must agree within 1e-4 mm (along the reference's normal), the vertices within 2e-3.
///
/// Both numbers are for parts within a few hundred millimetres of the origin: positions are `Float`, and one unit in the last place
/// is 5e-4 mm at 4 m, so D13's 1e-4 mm cannot hold for a far part (`MetalMeshingLimitsTests` checks that one's bounds to 1 mm).
/// The normals (dot product at least 0.9999 on the same samples, 0.999 whole) and the enclosed volume (1e-3, and positive: a
/// reversed winding is negative) are held too, because `MeshTopology` sees neither an inverted normal nor an inside-out mesh.
@Suite(.enabled(if: MetalImplicitEngine.shared != nil, "needs a Metal device"))
struct GPUMeshAgreementTests {
    /// Errata D13: vertices within 1e-4 mm after the snap.
    static let vertexTolerance: Float = 1e-4
    /// The whole pipeline's slide along the surface (see above).
    static let slideTolerance: Float = 2e-3
    /// The normals of the two meshers on the same samples: the dot product of a vertex's two normals, at least. They are the snap's
    /// gradient, so the same values give the same direction to rounding.
    static let mesherNormalDot: Float = 0.9999
    /// The normals of the two whole pipelines (the evaluators differ by 1e-6, which turns a gradient by a little more).
    static let pipelineNormalDot: Float = 0.999
    /// The volumes the two meshes enclose, as a fraction: it is the same surface, and a reversed winding changes its sign.
    static let volumeTolerance = 1e-3
    /// The triangle counts of the two meshers, as a fraction. They are equal on every fixture; a sample within a rounding of zero
    /// can move a handful of triangles, so a thousandth is allowed.
    static let triangleTolerance = 0.001

    /// The fixtures that make a surface. (The GPU suite's "implicit leaf" offsets a ball by its own distance and has none, and an
    /// "empty …" fixture is an empty combination, which meshing refuses: `ImplicitMeshingError.empty`.)
    static let names = GPUFixtures.all.map(\.name).filter { $0 != "implicit leaf" && !$0.hasPrefix("empty") }

    /// A voxel size off the lattice's round numbers, so no sample lands on a surface, about 60 voxels across the fixture. Coarser
    /// than that the Newton step lands on the kinks of a shell or a noisy field, where its gradient is small and it amplifies the
    /// difference between two evaluators (the noisy shell's surfaces were 6e-4 mm apart at 1.5 mm voxels): see the plan's risks.
    static func resolution(of solid: ImplicitSolid) -> Double {
        let size = solid.bounds.size
        return max(0.53, max(size.x, size.y, size.z) / 60)
    }

    static func expectSameTopology(_ gpu: TriangleMesh, _ cpu: TriangleMesh, _ name: String) {
        let (g, c) = (MeshTopology(gpu), MeshTopology(cpu))
        #expect(g.isClosedManifold && c.isClosedManifold, "\(name): closed and manifold")
        #expect(g.eulerCharacteristic == c.eulerCharacteristic, "\(name): Euler \(g.eulerCharacteristic) against \(c.eulerCharacteristic)")
        let difference = Double(abs(g.triangleCount - c.triangleCount)) / Double(c.triangleCount)
        #expect(difference <= triangleTolerance, "\(name): \(g.triangleCount) triangles against \(c.triangleCount)")
        #expect(abs(gpu.vertexCount - cpu.vertexCount) <= max(1, Int(Double(cpu.vertexCount) * triangleTolerance)), "\(name): vertices")
        // Triangles wind counter-clockwise seen from outside, like the CPU's: `MeshTopology` only checks that they agree with each
        // other, so the enclosed volume (negative for a mesh turned inside out) is what tells.
        #expect(cpu.signedVolume > 0, "\(name): the reference is wound outwards")
        #expect(gpu.signedVolume > 0 && abs(gpu.signedVolume - cpu.signedVolume) <= volumeTolerance * cpu.signedVolume,
                "\(name): volume \(gpu.signedVolume) against \(cpu.signedVolume)")
    }

    @Test(arguments: names)
    func theGPUMeshAgreesWithTheCPUMesh(_ name: String) async throws {
        let engine = try #require(MetalImplicitEngine.shared)
        let solid = try #require(GPUFixtures.all.first { $0.name == name }?.solid)
        let resolution = Self.resolution(of: solid)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine)
        let gpu = try await ImplicitMesher(evaluator: selection.evaluator)
            .meshReportingPath(solid, resolution: resolution, quality: .preview)
        #expect(gpu.path == .gpu, "\(name): the GPU mesher ran")

        // The mesher alone: the same sample values.
        let sameSamples = try await ImplicitMesher(evaluator: SamplesOnlyEvaluator(inner: selection.evaluator))
            .meshReportingPath(solid, resolution: resolution, quality: .preview)
        #expect(sameSamples.path == .cpu)
        Self.expectSameTopology(gpu.mesh, sameSamples.mesh, name)
        let mesher = MeshComparison(reference: sameSamples.mesh, candidate: gpu.mesh)
        #expect(mesher.unmatched == 0, "\(name): vertices without a match")
        #expect(mesher.farthest <= Self.vertexTolerance, "\(name): the largest vertex difference is \(mesher.farthest) mm")
        #expect(mesher.smallestNormalDot >= Self.mesherNormalDot, "\(name): a normal differs: dot \(mesher.smallestNormalDot)")

        // The whole pipeline: the CPU evaluator is the reference.
        let reference = try await ImplicitMesher(evaluator: CPUBatchEvaluator(solid)).mesh(solid, resolution: resolution, quality: .preview)
        Self.expectSameTopology(gpu.mesh, reference, name)
        let pipeline = MeshComparison(reference: reference, candidate: gpu.mesh)
        #expect(pipeline.unmatched == 0, "\(name): vertices without a match")
        #expect(pipeline.farthestAlongNormal <= Self.vertexTolerance, "\(name): the surfaces are \(pipeline.farthestAlongNormal) mm apart")
        #expect(pipeline.farthest <= Self.slideTolerance, "\(name): the largest vertex difference is \(pipeline.farthest) mm")
        #expect(pipeline.smallestNormalDot >= Self.pipelineNormalDot, "\(name): a normal differs: dot \(pipeline.smallestNormalDot)")
    }

    @Test(arguments: ["sphere", "box", "smooth union", "graded offset"])
    func withoutTheSnapTheVerticesStillAgreeAndTheNormalsAreZero(_ name: String) async throws {
        let engine = try #require(MetalImplicitEngine.shared)
        let solid = try #require(GPUFixtures.all.first { $0.name == name }?.solid)
        let resolution = Self.resolution(of: solid)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine)
        let gpu = try await ImplicitMesher(evaluator: selection.evaluator)
            .meshReportingPath(solid, resolution: resolution, quality: .preview, snap: false)
        let cpu = try await ImplicitMesher(evaluator: SamplesOnlyEvaluator(inner: selection.evaluator))
            .mesh(solid, resolution: resolution, quality: .preview, snap: false)
        #expect(gpu.path == .gpu && gpu.mesh.normals.allSatisfy { $0 == .zero })
        Self.expectSameTopology(gpu.mesh, cpu, name)
        let comparison = MeshComparison(reference: cpu, candidate: gpu.mesh)
        #expect(comparison.unmatched == 0 && comparison.farthest <= Self.vertexTolerance, "\(name): \(comparison.farthest) mm")
    }
}
#endif
````

**Create `Tests/CreatorImplicitTests/MeshComparisonTests.swift`**

````swift
import Testing
@testable import CreatorImplicit

/// The yardstick of the GPU agreement suite, tried on meshes whose difference is known.
struct MeshComparisonTests {
    static let cube = MeshFixtures.cube

    @Test func aMeshAgreesWithItself() {
        let comparison = MeshComparison(reference: Self.cube, candidate: Self.cube)
        #expect(comparison.farthest == 0 && comparison.unmatched == 0)
    }

    @Test func aSlideAlongTheSurfaceIsCountedInFarthestAndNotAlongTheNormal() {
        let normals = [SIMD3<Float>](repeating: SIMD3(0, 0, 1), count: 8)
        let reference = TriangleMesh(positions: Self.cube.positions, normals: normals, triangles: Self.cube.triangles)
        var slid = reference
        slid.positions = slid.positions.map { $0 + SIMD3(0.001, 0, 0) }
        let slide = MeshComparison(reference: reference, candidate: slid)
        #expect(abs(slide.farthest - 0.001) < 1e-6 && slide.farthestAlongNormal < 1e-6 && slide.unmatched == 0)
        var raised = reference
        raised.positions = raised.positions.map { $0 + SIMD3(0, 0, 0.002) }
        let rise = MeshComparison(reference: reference, candidate: raised)
        #expect(abs(rise.farthest - 0.002) < 1e-6 && abs(rise.farthestAlongNormal - 0.002) < 1e-6)
    }

    @Test func aNormalTurnedAroundOrTippedIsCountedInSmallestNormalDot() {
        let up = [SIMD3<Float>](repeating: SIMD3(0, 0, 1), count: 8)
        let reference = TriangleMesh(positions: Self.cube.positions, normals: up, triangles: Self.cube.triangles)
        func comparison(_ normal: SIMD3<Float>?) -> MeshComparison {
            var candidate = reference
            if let normal { candidate.normals[3] = normal }
            return MeshComparison(reference: reference, candidate: candidate)
        }
        #expect(comparison(nil).smallestNormalDot == 1)
        #expect(comparison(SIMD3(0, 0, -1)).smallestNormalDot == -1)
        #expect(abs(comparison(SIMD3(0, 0.6, 0.8)).smallestNormalDot - 0.8) < 1e-6)
        // Vertices without normals (a mesh made without the snap) are not counted.
        var bare = reference
        bare.normals = [SIMD3<Float>](repeating: .zero, count: 8)
        #expect(MeshComparison(reference: reference, candidate: bare).smallestNormalDot == 1)
    }

    @Test func aVertexWithNoMatchIsCountedFromEitherSide() {
        var extra = Self.cube
        extra.positions.append(SIMD3(5, 5, 5))
        extra.normals = []
        let comparison = MeshComparison(reference: Self.cube, candidate: extra)
        #expect(comparison.unmatched == 1)
        #expect(MeshComparison(reference: extra, candidate: Self.cube).unmatched == 1)
    }
}
````

**Create `Tests/CreatorImplicitTests/MetalMeshingLimitsTests.swift`**

````swift
#if canImport(Metal)
import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// What the Metal mesher does at its edges (implicit spec Errata D13): small batches, a table that is too small, a request beyond its
/// limits, a part far from the origin, a cancel. Skipped on a machine without a Metal device.
@Suite(.enabled(if: MetalImplicitEngine.shared != nil, "needs a Metal device"))
struct MetalMeshingLimitsTests {
    static let solid = ImplicitSolid.sphere(radius: 10)

    /// A fresh engine, tuned, and the program and request for `solid`.
    struct Prepared {
        let engine: MetalImplicitEngine
        let program: CompiledImplicit
        let request: BrickMeshRequest

        init(_ solid: ImplicitSolid = MetalMeshingLimitsTests.solid, resolution: Double = 0.53,
             tuning: MetalImplicitEngine.MeshTuning = MetalImplicitEngine.MeshTuning()) async throws {
            guard let engine = MetalImplicitEngine() else { throw ImplicitCompileError.engine("no Metal device") }
            await engine.tune(tuning)
            self.engine = engine
            program = try await engine.compile(solid)
            request = try await MetalMeshingTests.request(solid, resolution: resolution)
        }

        func mesh() async throws -> BrickMesh {
            try await engine.meshBricks(program, request) { _ in }
        }
    }

    static func sameSet(_ a: BrickMesh, _ b: BrickMesh) -> Bool {
        let comparison = MeshComparison(reference: a.triangleMesh, candidate: b.triangleMesh)
        return comparison.unmatched == 0 && comparison.farthest < 1e-6 && a.positions.count == b.positions.count
            && a.triangles.count == b.triangles.count
    }

    @Test func manySmallBatchesMakeTheMeshOneBigBatchDoes() async throws {
        let job = try await Prepared()
        let whole = try await job.mesh()
        #expect(job.request.bricks.count > 50)
        var tuning = MetalImplicitEngine.MeshTuning()
        tuning.batchBricks = 7
        await job.engine.tune(tuning)
        let small = try await job.mesh()
        #expect(Self.sameSet(whole, small))
        #expect(MeshTopology(small.triangleMesh).isClosedManifold)
    }

    @Test func aTableThatIsTooSmallIsDoubledUntilItFits() async throws {
        var tuning = MetalImplicitEngine.MeshTuning()
        tuning.slotsPerBrick = 1
        let mesh = try await Prepared(tuning: tuning).mesh()
        let expected = try await Prepared().mesh()
        #expect(mesh.positions.count > 4096, "more vertices than the first table has slots")
        #expect(Self.sameSet(mesh, expected))
    }

    @Test func aMeshBeyondTheLargestTableIsLeftToTheCPU() async throws {
        var tuning = MetalImplicitEngine.MeshTuning()
        tuning.slotsPerBrick = 1
        tuning.largestTable = 4096
        let job = try await Prepared(tuning: tuning)
        await #expect(throws: ImplicitCompileError.self) { _ = try await job.mesh() }
        let (mesh, path) = try await ImplicitMesher(evaluator: GPUBatchEvaluator(engine: job.engine, program: job.program))
            .meshReportingPath(Self.solid, resolution: 0.53, quality: .preview)
        #expect(path == .cpu && MeshTopology(mesh).isClosedManifold)
    }

    @Test func bricksTooFarApartForThirtyTwoBitKeysAreUnsupported() async throws {
        let engine = try #require(MetalImplicitEngine.shared)
        let program = try await engine.compile(Self.solid)
        let request = BrickMeshRequest(origin: .zero, resolution: 0.5, bricks: [SIMD3(0, 0, 0), SIMD3(1_200, 1_200, 1_200)], snap: true)
        await #expect(throws: ImplicitCompileError.unsupported("the bricks span more lattice edges than a 32-bit key numbers")) {
            _ = try await engine.meshBricks(program, request) { _ in }
        }
    }

    @Test func aPartFarFromTheOriginIsMeshedInASmallWindow() async throws {
        let engine = try #require(MetalImplicitEngine.shared)
        let move = RigidMove(origin: Vector3(4_000, -3_000, 2_500), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ)
        let far = ImplicitSolid.moved(Self.solid, move)
        let selection = await ImplicitEvaluators.make(for: far, choice: .automatic, engine: engine)
        let (mesh, path) = try await ImplicitMesher(evaluator: selection.evaluator)
            .meshReportingPath(far, resolution: 0.53, quality: .preview)
        #expect(path == .gpu)
        let topology = MeshTopology(mesh)
        #expect(topology.isClosedManifold && topology.eulerCharacteristic == 2)
        let bounds = try #require(mesh.bounds)
        #expect(abs(bounds.min.x - 3_990) < 1 && abs(bounds.max.z - 2_510) < 1)
    }

    @Test func theSameBricksMakeTheSameSetOfVerticesAndTriangles() async throws {
        let job = try await Prepared()
        let first = try await job.mesh()
        let second = try await job.mesh()
        // Their order is the threads' and may differ; what they hold may not.
        #expect(Self.sameSet(first, second))
    }

    @Test func aMeshOfSeveralRangesOfSlotsIsTheMeshOneRangeMakes() async throws {
        var tuning = MetalImplicitEngine.MeshTuning()
        tuning.slotsPerDispatch = 1_000
        let ranges = try await Prepared(tuning: tuning).mesh()
        let whole = try await Prepared().mesh()
        #expect(ranges.positions.count > 1_000, "more vertices than one range of slots")
        #expect(Self.sameSet(ranges, whole))
        #expect(MeshTopology(ranges.triangleMesh).isClosedManifold)
    }

    /// A mesh of many small batches, so a cancel has somewhere to land between two of them.
    static func manyBatches() async throws -> Prepared {
        var tuning = MetalImplicitEngine.MeshTuning()
        tuning.batchBricks = 4
        let job = try await Prepared(.sphere(radius: 20), resolution: 0.4, tuning: tuning)
        #expect(job.request.bricks.count > 40, "ten batches or more")
        return job
    }

    /// The next mesh on the engine, after a cancel: it runs whole.
    static func expectTheNextMeshRuns(_ engine: MetalImplicitEngine) async throws {
        let small = try await MetalMeshingTests.request(.sphere(radius: 3), resolution: 0.5)
        let after = try await engine.meshBricks(try await engine.compile(.sphere(radius: 3)), small) { _ in }
        #expect(MeshTopology(after.triangleMesh).isClosedManifold)
    }

    @Test func cancellingTheTaskEndsAMeshAtItsNextBatchAndNotTheNextMesh() async throws {
        let job = try await Self.manyBatches()
        let seen = ProgressLog()
        // The progress callback runs on the meshing task after each batch: it cancels that task after the first.
        let running = Task {
            try await job.engine.meshBricks(job.program, job.request) { fraction in
                seen.append(fraction)
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await #expect(throws: CancellationError.self) { _ = try await running.value }
        #expect(seen.values.count == 1, "it ended at the next batch, not after the whole mesh: \(seen.values.count) reports")
        try await Self.expectTheNextMeshRuns(job.engine)
    }

    @Test func anEngineCancelEndsAMeshAtItsNextBatchAndNotTheNextMesh() async throws {
        let job = try await Self.manyBatches()
        var tuning = MetalImplicitEngine.MeshTuning()
        tuning.batchBricks = 4
        // After the first batch the engine itself is cancelled, which bumps its epoch (an edit does this to a running mesh).
        tuning.afterBatch = { [engine = job.engine] batch in
            if batch == 1 { await engine.cancel() }
        }
        await job.engine.tune(tuning)
        let seen = ProgressLog()
        await #expect(throws: CancellationError.self) {
            _ = try await job.engine.meshBricks(job.program, job.request) { seen.append($0) }
        }
        #expect(seen.values.isEmpty, "the first batch's check ended it before its report")
        tuning.afterBatch = nil
        await job.engine.tune(tuning)
        try await Self.expectTheNextMeshRuns(job.engine)
    }
}
#endif
````

**Create `Tests/CreatorImplicitTests/Support/MeshComparison.swift`**

````swift
import CreatorGeometry
@testable import CreatorImplicit

/// How far apart two meshes' vertices are, matched by nearness: every vertex of each mesh against the nearest of the other's. Two
/// meshes of one lattice have one vertex per crossed edge, so the nearest vertex is the same edge's, unless the surface is within a
/// voxel of itself, which the fixtures keep clear of.
struct MeshComparison {
    /// The largest distance from a vertex of either mesh to the nearest of the other's.
    var farthest: Float = 0
    /// The largest distance, taken along the reference's normal at the matched vertex, from a candidate vertex to its match: the
    /// distance between the two *surfaces*, where `farthest` also counts a slide along the surface. Zero when the reference has no normals.
    var farthestAlongNormal: Float = 0
    /// The smallest dot product of a candidate vertex's normal and the reference's at its match: 1 when they point the same way, 0
    /// at a right angle, -1 when inside out. Vertices without a normal on either side (a mesh made without the snap) are not counted;
    /// 1 when none is.
    var smallestNormalDot: Float = 1
    /// Vertices of either mesh with none of the other's within `searchRadius`.
    var unmatched = 0

    init(reference: TriangleMesh, candidate: TriangleMesh, searchRadius: Float = 0.01) {
        let forward = Self.directed(from: candidate, to: reference, radius: searchRadius)
        let backward = Self.directed(from: reference, to: candidate, radius: searchRadius)
        farthest = max(forward.farthest, backward.farthest)
        farthestAlongNormal = forward.alongNormal
        smallestNormalDot = forward.smallestDot
        unmatched = forward.unmatched + backward.unmatched
    }

    private static func cell(_ point: SIMD3<Float>, _ radius: Float) -> SIMD3<Int32> {
        SIMD3(Int32((point.x / radius).rounded(.down)), Int32((point.y / radius).rounded(.down)), Int32((point.z / radius).rounded(.down)))
    }

    /// The dot product of the normals of `source`'s vertex `at` and `target`'s vertex `other`; `nil` when either has none (a mesh made
    /// without the snap has zero vectors).
    private static func normalDot(_ source: TriangleMesh, _ at: Int, _ target: TriangleMesh, _ other: Int) -> Float? {
        guard source.normals.indices.contains(at), target.normals.indices.contains(other) else { return nil }
        let (mine, theirs) = (source.normals[at], target.normals[other])
        guard (mine * mine).sum() > 0.25, (theirs * theirs).sum() > 0.25 else { return nil }
        return (mine * theirs).sum()
    }

    /// Each vertex of `source` against the nearest vertex of `target`.
    private static func directed(from source: TriangleMesh, to target: TriangleMesh,
                                 radius: Float) -> (farthest: Float, alongNormal: Float, smallestDot: Float, unmatched: Int) {
        var grid: [SIMD3<Int32>: [Int]] = [:]
        for (index, point) in target.positions.enumerated() { grid[cell(point, radius), default: []].append(index) }
        var result: (farthest: Float, alongNormal: Float, smallestDot: Float, unmatched: Int) = (0, 0, 1, 0)
        for (at, point) in source.positions.enumerated() {
            let home = cell(point, radius)
            var nearest: (index: Int, distance: Float)?
            for dx in Int32(-1)...1 {
                for dy in Int32(-1)...1 {
                    for dz in Int32(-1)...1 {
                        for index in grid[home &+ SIMD3(dx, dy, dz), default: []] {
                            let offset = point - target.positions[index]
                            let distance = (offset * offset).sum().squareRoot()
                            if distance < (nearest?.distance ?? .infinity) { nearest = (index, distance) }
                        }
                    }
                }
            }
            guard let nearest else { result.unmatched += 1; continue }
            result.farthest = max(result.farthest, nearest.distance)
            if target.normals.indices.contains(nearest.index) {
                let along = abs(((point - target.positions[nearest.index]) * target.normals[nearest.index]).sum())
                result.alongNormal = max(result.alongNormal, along)
                if let dot = normalDot(source, at, target, nearest.index) { result.smallestDot = min(result.smallestDot, dot) }
            }
        }
        return result
    }
}

extension BrickMesh {
    /// The same arrays as a mesh, for `MeshTopology` and `MeshComparison`.
    var triangleMesh: TriangleMesh {
        TriangleMesh(positions: positions, normals: normals, triangles: triangles)
    }
}

/// An evaluator that only evaluates: the CPU mesher over a GPU engine's values, which is what meshing was before D13.
struct SamplesOnlyEvaluator: ImplicitBatchEvaluator {
    let inner: any ImplicitBatchEvaluator

    var engineName: String { inner.engineName }

    func evaluate(_ points: [SIMD3<Float>]) async throws -> [Float] {
        try await inner.evaluate(points)
    }
}
````

- [ ] **Step 2: Run the tests to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head`
Expected: `type 'MetalImplicitEngine' has no member 'MeshTuning'` and `value of type 'MetalImplicitEngine' has no member 'tune'`.

- [ ] **Step 3: Implement**

The tuning struct replaces Task 3's three constants; nothing else about the engine changes.

**Edit `Sources/CreatorImplicit/Metal/MetalImplicitEngine+Meshing.swift`**

Replace:

````swift
        var indices: any MTLBuffer
    }

    /// How many bricks are sampled and meshed in one pair of dispatches (4,096 as in implicit spec §4.2: 12 MB of samples).
    static let meshBatchBricks = 4096
    /// The first table has this many slots for each brick; a table that proves too small is doubled.
    static let tableSlotsPerBrick = 256
    /// The most slots a table gets (8 bytes each); a mesh needing more is left to the CPU.
    static let largestTable = 1 << 27
    /// How many table slots one command buffer numbers or places: a slot costs up to nine evaluations of the solid, so this keeps one
    /// buffer to the same order of work as the evaluator's (`pointsPerDispatch` points).
    static let slotsPerDispatch = 1 << 20

    public func meshBricks(_ program: CompiledImplicit, _ request: BrickMeshRequest,
                           progress: @Sendable (Double) -> Void) async throws -> BrickMesh {
````

With:

````swift
        var indices: any MTLBuffer
    }

    /// The sizes meshing works in. The defaults are the engine's; the tests turn them down to reach the paths a small mesh never takes.
    struct MeshTuning {
        /// How many bricks are sampled and meshed in one pair of dispatches (4,096 as in implicit spec §4.2: 12 MB of samples).
        var batchBricks = 4096
        /// The first table has this many slots for each brick; a table that proves too small is doubled.
        var slotsPerBrick = 256
        /// The most slots a table gets (8 bytes each); a mesh needing more is left to the CPU.
        var largestTable = 1 << 27
        /// How many table slots one command buffer numbers or places.
        var slotsPerDispatch = 1 << 20
        /// Called with the number of the batch just run (from 1), after its command buffer and before the check for a cancel: the
        /// tests cancel from it, at a known point. Nothing in the engine sets it.
        var afterBatch: (@Sendable (Int) async -> Void)?
    }

    /// Replaces the sizes meshing works in, for the tests.
    func tune(_ tuning: MeshTuning) {
        meshTuning = tuning
    }

    public func meshBricks(_ program: CompiledImplicit, _ request: BrickMeshRequest,
                           progress: @Sendable (Double) -> Void) async throws -> BrickMesh {
````

**Edit `Sources/CreatorImplicit/Metal/MetalImplicitEngine+Meshing.swift`**

Replace:

````swift
            pipelines: pipelines, solid: try buffers(for: program), bricks: try meshUpload(lattice.relativeBricks(request.bricks)),
            axes: try meshUpload(lattice.axisCoordinates(origin: request.origin, resolution: request.resolution)),
            cube: try meshUpload(MarchingCubesBuffers.words), parameters: parameters, brickCount: request.bricks.count, started: started,
            slotsPerDispatch: Self.slotsPerDispatch)
        var slots = 1 << max(12, Int.bitWidth - (request.bricks.count * Self.tableSlotsPerBrick - 1).leadingZeroBitCount)
        while true {
            guard slots <= Self.largestTable else {
                throw ImplicitCompileError.unsupported("the edge table would pass \(Self.largestTable) slots")
            }
            if let mesh = try await meshAttempt(job, slots: slots, batch: Self.meshBatchBricks, progress: progress) {
                meshesMade += 1
                return mesh
            }
            slots *= 2
        }
    }
````

With:

````swift
            pipelines: pipelines, solid: try buffers(for: program), bricks: try meshUpload(lattice.relativeBricks(request.bricks)),
            axes: try meshUpload(lattice.axisCoordinates(origin: request.origin, resolution: request.resolution)),
            cube: try meshUpload(MarchingCubesBuffers.words), parameters: parameters, brickCount: request.bricks.count, started: started,
            slotsPerDispatch: meshTuning.slotsPerDispatch)
        let tuning = meshTuning
        var slots = 1 << max(12, Int.bitWidth - (request.bricks.count * tuning.slotsPerBrick - 1).leadingZeroBitCount)
        while true {
            guard slots <= tuning.largestTable else {
                throw ImplicitCompileError.unsupported("the edge table would pass \(tuning.largestTable) slots")
            }
            if let mesh = try await meshAttempt(job, slots: slots, batch: tuning.batchBricks, progress: progress) {
                meshesMade += 1
                return mesh
            }
            slots *= 2
        }
    }
````

**Edit `Sources/CreatorImplicit/Metal/MetalImplicitEngine+Meshing.swift`**

Replace:

````swift
                dispatch(encoder, emitting ? run.job.pipelines.emit : run.job.pipelines.classify, threads: count * 512)
            }
            try checkRunning(run.job)
````

With:

````swift
                dispatch(encoder, emitting ? run.job.pipelines.emit : run.job.pipelines.classify, threads: count * 512)
            }
            await meshTuning.afterBatch?(first / run.batch + 1)
            try checkRunning(run.job)
````

**Edit `Sources/CreatorImplicit/Metal/MetalImplicitEngine.swift`**

Replace:

````swift

    /// The meshing kernels of each shape, keyed by the program's source (`MetalImplicitEngine+Meshing.swift`).
    var meshPipelines: [String: MeshPipelines] = [:]
    /// How many sets of meshing pipelines were compiled.
    public internal(set) var meshCompileCount = 0
````

With:

````swift

    /// The meshing kernels of each shape, keyed by the program's source (`MetalImplicitEngine+Meshing.swift`).
    var meshPipelines: [String: MeshPipelines] = [:]
    /// The sizes meshing works in.
    var meshTuning = MeshTuning()
    /// How many sets of meshing pipelines were compiled.
    public internal(set) var meshCompileCount = 0
````

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --filter "MeshComparisonTests|GPUMeshAgreementTests|MetalMeshingLimitsTests|MetalMeshingTests"`
Expected: PASS. `MeshComparisonTests` 4 tests, `GPUMeshAgreementTests` 2 tests (25 and 4 argument cases), `MetalMeshingLimitsTests` 9, `MetalMeshingTests` 5; about 20 seconds in a debug build. Measured on the fixtures: the mesher alone differs by at most 1.7e-5 mm, the whole pipeline's surfaces by 1.9e-5 mm along the normal and its vertices by 9.1e-4 mm; the smallest normal dot is 0.9999996 (both comparisons); the enclosed volumes agree to 1e-7 of the volume; triangle counts are equal on every fixture. Mutations that this suite catches (each makes it fail, and each was made and undone): the normal written as `-normal` (every fixture), every triangle wound the other way (every fixture, by the volume), `firstSlot` ignored by `meshNumber` (the ranges test), and the two cancellation checks of `checkRunning` deleted one at a time and together (one cancel test each).

- [ ] **Step 5: Build, warnings, lint**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning"; swiftlint lint --strict 2>&1 | tail -1; swift test --filter CreatorImplicitTests 2>&1 | grep -E "recorded an issue|failed after|Test run with"`
Expected: nothing new; `Found 0 violations, 0 serious`; the whole `CreatorImplicitTests` target passes (191 tests with Metal at this point).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorImplicit Tests/CreatorImplicitTests
git commit -m "test(implicit): GPU mesher against the CPU mesher, and the limits of the Metal mesher (7c-1g T4)"
```

## Task 5: Re-measure i-1 and i-2 on the GPU path, and record them

`ImplicitMesher` takes the GPU path by itself wherever the evaluator is a GPU one, so rows i-1 and i-2 of `ImplicitBench` (which run the Mesh node through the `Evaluator` with `.automatic`) are on it already. This task adds what they need to be trusted (a check that their meshes were made on the GPU: the Mesh node falls back to the CPU silently, and a CPU mesh of the sheet still meets i-1's 1 s) and compared, runs them, and writes the numbers down by 7c-core's U6 ruling: records, never gates; a miss is a miss.

**Files:**
- Modify: `Tests/CreatorAppTests/Bench/ImplicitBenchFixtures.swift` (`Sheet.band`, `solid(of:)`), `Tests/CreatorAppTests/Bench/ImplicitBench.swift` (the `i-1m` test), `Tests/CreatorAppTests/Bench/ImplicitBenchFixturesTests.swift`
- Modify (docs): `docs/verification/performance.md`, `docs/verification/human-checks.md`, `CLAUDE.md`

**Interfaces:**
- Consumes: Tasks 1 to 4 (`ImplicitMesher.meshReportingPath`, `MeshingPath`), `PreviewSchedule(.automatic).firstResolution(for:)`, `ImplicitEvaluators.make`, `BenchSamples`, `Bench.requireRelease()`.
- Produces: `ImplicitBench.meshesMade()` and `ImplicitBench.expectMeshedOnTheGPU(since:atLeast:row:)` (a run of i-1 or i-2 fails unless the Metal engine's `meshesMade` rose by a mesh for each round), `ImplicitBenchFixtures.Sheet.band` (the Subtract node), `ImplicitBenchFixtures.solid(of: Sheet) async throws -> ImplicitSolid`, the benchmark `i-1m` (the first pass on the GPU mesher and on the CPU mesher over the GPU's values, with the check that the first was made on the GPU), IM-13 in the human checks.

- [ ] **Step 1: Write the failing test**

The fixtures test reads the sheet back as the solid the Mesh node meshes.

**Edit `Tests/CreatorAppTests/Bench/ImplicitBenchFixturesTests.swift`**

Replace:

````swift
        #expect(second.evaluatedNodes.count == 5)
    }

    @Test func peakMemoryIsReadable() {
        #expect(ImplicitBenchFixtures.peakMemory > 1_000_000)
    }
````

With:

````swift
        #expect(second.evaluatedNodes.count == 5)
    }

    @Test func theSheetIsAnImplicitSolidFillingTheCube() async throws {
        let sheet = ImplicitBenchFixtures.sheet(side: 20, scale: 8, exportResolution: 0.5)
        let solid = try await ImplicitBenchFixtures.solid(of: sheet)
        let size = solid.bounds.size
        #expect(size.x <= 20.01 && size.y <= 20.01 && size.z <= 20.01 && size.x > 5)
    }

    @Test func peakMemoryIsReadable() {
        #expect(ImplicitBenchFixtures.peakMemory > 1_000_000)
    }
````

- [ ] **Step 2: Run the test to see it fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head`
Expected: `type 'ImplicitBenchFixtures' has no member 'solid'`.

- [ ] **Step 3: Implement the fixture and the comparison benchmark**

`solid(of:)` evaluates the sheet's Subtract node on the CPU and reads the solid back (an implicit is a tree, the same on any engine). `i-1m` times the same first pass twice per round, once by `ImplicitMesher` over the GPU evaluator and once over `SamplesOnlyEvaluator`, a private evaluator that only evaluates (the same idea as the test support's, in the app tests' target), and records an issue if the first was not on the GPU.

**Edit `Tests/CreatorAppTests/Bench/ImplicitBench.swift`**

Replace:

````swift
///   too and not judged.
/// - i-2: a thickness edit (the gap between the two levels) on a warm evaluator, so the noise and the cube are cached and no shader
///   is recompiled: one coarse pass under 100 ms.
/// - i-3: To Implicit of the slice's bracket on OCCT at the default tolerance, the bake cache emptied each time: under 500 ms.
/// - i-4: the export of i-1 at 0.1 mm to an STL, the whole pipeline: under 60 s and a peak memory under 4 GB.
@MainActor
````

With:

````swift
///   too and not judged.
/// - i-2: a thickness edit (the gap between the two levels) on a warm evaluator, so the noise and the cube are cached and no shader
///   is recompiled: one coarse pass under 100 ms.
/// - i-1m: the same first pass made by the mesher alone, on the GPU mesher and on the CPU mesher over the GPU's values (meshing
///   before Errata D13), to see what GPU meshing bought; i-2 is that coarse pass again. Not judged. The run also checks the pass was
///   made on the GPU, since a fall-back to the CPU is silent.
/// - i-3: To Implicit of the slice's bracket on OCCT at the default tolerance, the bake cache emptied each time: under 500 ms.
/// - i-4: the export of i-1 at 0.1 mm to an STL, the whole pipeline: under 60 s and a peak memory under 4 GB.
@MainActor
````

**Edit `Tests/CreatorAppTests/Bench/ImplicitBench.swift`** (rows i-1 and i-2 count the meshes the Metal engine makes)

Replace:

````swift
        var warm = BenchSamples("i-1 first preview pass of a 100 mm sheet")
        for round in 0..<8 {
````

With:

````swift
        var warm = BenchSamples("i-1 first preview pass of a 100 mm sheet")
        let madeBefore = await Self.meshesMade()
        for round in 0..<8 {
````

**Edit `Tests/CreatorAppTests/Bench/ImplicitBench.swift`**

Replace:

````swift
        print(cold.line())
        print(warm.line(budget: Self.firstPassBudget))
    }
````

With:

````swift
        print(cold.line())
        print(warm.line(budget: Self.firstPassBudget))
        await Self.expectMeshedOnTheGPU(since: madeBefore, atLeast: 8, row: "i-1")
    }
````

**Edit `Tests/CreatorAppTests/Bench/ImplicitBench.swift`**

Replace:

````swift
        _ = try await evaluator.evaluate(sheet.graph, demand: [sheet.output.id])
        let clock = ContinuousClock()
        var samples = BenchSamples("i-2 thickness edit of a 100 mm sheet (one coarse pass, no recompile)")
````

With:

````swift
        _ = try await evaluator.evaluate(sheet.graph, demand: [sheet.output.id])
        let madeBefore = await Self.meshesMade()
        let clock = ContinuousClock()
        var samples = BenchSamples("i-2 thickness edit of a 100 mm sheet (one coarse pass, no recompile)")
````

**Edit `Tests/CreatorAppTests/Bench/ImplicitBench.swift`**

Replace:

````swift
        print(samples.line(budget: Self.editBudget))
    }

    @Test func toImplicitOfTheBracket() async throws {
        guard Bench.requireRelease() else { return }
        let (app, bracket) = try await makeBracketBenchApp()
````

With:

````swift
        print(samples.line(budget: Self.editBudget))
        await Self.expectMeshedOnTheGPU(since: madeBefore, atLeast: 25, row: "i-2")
    }

    @Test func theFirstPassOnTheGPUMesherAndOnTheCPUMesherOverGPUValues() async throws {
        guard Bench.requireRelease() else { return }
        let solid = try await ImplicitBenchFixtures.solid(of: ImplicitBenchFixtures.sheet())
        let resolution = PreviewSchedule(.automatic).firstResolution(for: solid.bounds)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic)
        guard selection.evaluator.engineName != "CPU" else {
            print("BENCH i-1m skipped: this machine has no GPU engine")
            return
        }
        let clock = ContinuousClock()
        let size = resolution.formatted(.number.precision(.fractionLength(2)))
        var gpu = BenchSamples("i-1m first pass of the sheet at \(size) mm, GPU mesher")
        var cpu = BenchSamples("i-1m the same pass, CPU mesher over the GPU's values (before D13)")
        var triangles = (gpu: 0, cpu: 0)
        for round in 0..<8 {
            let gpuStart = clock.now
            let onGPU = try await ImplicitMesher(evaluator: selection.evaluator)
                .meshReportingPath(solid, resolution: resolution, quality: .preview)
            let gpuEnd = clock.now
            let onCPU = try await ImplicitMesher(evaluator: SamplesOnlyEvaluator(inner: selection.evaluator))
                .meshReportingPath(solid, resolution: resolution, quality: .preview)
            let cpuEnd = clock.now
            #expect(onGPU.path == .gpu && onCPU.path == .cpu)
            guard round >= 2 else { continue }
            gpu.append(from: gpuStart, to: gpuEnd)
            cpu.append(from: gpuEnd, to: cpuEnd)
            triangles = (onGPU.mesh.triangleCount, onCPU.mesh.triangleCount)
        }
        print(gpu.line())
        print(cpu.line())
        print("BENCH i-1m triangles: GPU \(triangles.gpu), CPU \(triangles.cpu)")
    }

    @Test func toImplicitOfTheBracket() async throws {
        guard Bench.requireRelease() else { return }
        let (app, bracket) = try await makeBracketBenchApp()
````

**Edit `Tests/CreatorAppTests/Bench/ImplicitBench.swift`**

Replace:

````swift
        print("BENCH i-4 peak memory \(gigabytes) GB (file \(size / 1_000_000) MB); budget 4.00 GB: \(verdict)")
    }
}
````

With:

````swift
        print("BENCH i-4 peak memory \(gigabytes) GB (file \(size / 1_000_000) MB); budget 4.00 GB: \(verdict)")
    }
}

extension ImplicitBench {
    /// How many meshes the platform's Metal engine has made so far, or `nil` where there is none (the CPU engine records its numbers
    /// without a budget, D11).
    static func meshesMade() async -> Int? {
        #if canImport(Metal)
        return await MetalImplicitEngine.shared?.meshesMade
        #else
        return nil
        #endif
    }

    /// Rows i-1 and i-2 run the Mesh node, which falls back to the CPU mesher without a word (U4), and a CPU mesh of the sheet still
    /// meets i-1's second: so a row's run fails unless the engine made a mesh for each of its `rounds`.
    static func expectMeshedOnTheGPU(since before: Int?, atLeast rounds: Int, row: String) async {
        guard let before, let after = await meshesMade() else { return }
        #expect(after - before >= rounds, "BENCH \(row): \(after - before) of \(rounds) meshes were made on the GPU")
    }
}

/// The CPU mesher over a GPU engine's values: an evaluator that only evaluates, so `ImplicitMesher` does not ask it to mesh.
private struct SamplesOnlyEvaluator: ImplicitBatchEvaluator {
    let inner: any ImplicitBatchEvaluator

    var engineName: String { inner.engineName }

    func evaluate(_ points: [SIMD3<Float>]) async throws -> [Float] {
        try await inner.evaluate(points)
    }
}
````

**Edit `Tests/CreatorAppTests/Bench/ImplicitBenchFixtures.swift`**

Replace:

````swift
        var graph: Graph
        /// The Series node that makes the two levels, outer then inner: its `step` is the sheet's thickness in noise units.
        var levels: Node
        var output: Node
    }
````

With:

````swift
        var graph: Graph
        /// The Series node that makes the two levels, outer then inner: its `step` is the sheet's thickness in noise units.
        var levels: Node
        /// The Subtract node that cuts the lower level from the upper: the sheet as an implicit solid.
        var band: Node
        var output: Node
    }
````

**Edit `Tests/CreatorAppTests/Bench/ImplicitBenchFixtures.swift`**

Replace:

````swift
        builder.wire(iso, "implicit", to: band, "shapes")
        builder.wire(band, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: output, "mesh")
        return Sheet(graph: builder.graph, levels: levels, output: output)
    }

    /// The process's peak resident memory so far, in bytes.
````

With:

````swift
        builder.wire(iso, "implicit", to: band, "shapes")
        builder.wire(band, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: output, "mesh")
        return Sheet(graph: builder.graph, levels: levels, band: band, output: output)
    }

    /// The sheet as the implicit solid the Mesh node meshes, evaluated on the CPU (an implicit is a tree, and builds the same on any engine).
    static func solid(of sheet: Sheet) async throws -> ImplicitSolid {
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
            .evaluate(sheet.graph, demand: [sheet.band.id])
        guard case .implicit(let reference)? = report.results[sheet.band.id]?.outputs?["implicit"]?.items.first,
              let solid = reference.solid else {
            throw BenchFixtureError.noSolid(String(describing: report.results[sheet.band.id]?.state))
        }
        return solid
    }

    /// The process's peak resident memory so far, in bytes.
````

**Edit `Tests/CreatorAppTests/Bench/ImplicitBenchFixtures.swift`**

Replace:

````swift
        return Int(usage.ru_maxrss)
    }
}
````

With:

````swift
        return Int(usage.ru_maxrss)
    }
}

/// Why a benchmark fixture could not be made.
enum BenchFixtureError: Error {
    case noSolid(String)
}
````

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --filter "ImplicitBenchFixturesTests|ImplicitBench"`
Expected: PASS, 9 tests (the benchmarks themselves are skipped without `METALCREATOR_BENCH=1`).

- [ ] **Step 5: Run the benchmarks**

On an idle Mac if there is one (the Mac was not idle when this plan was verified; see the numbers' caveat):

Run: `scripts/bench.sh "ImplicitBench/(theFirstPreview|aThicknessEdit|theFirstPassOnTheGPU)"`
Expected: it prints the machine and load lines, then `BENCH i-1 …`, `BENCH i-2 …`, `BENCH i-1m …` (twice) and the triangle counts, and exits 0. Rows i-1 and i-2 print `met` or `missed` against 1,000 ms and 100 ms; **neither fails the run, and neither may be edited to meet**. Both `i-1m` meshers must make the same number of triangles. The run takes a few minutes for the release build; its output is in `.build/bench.log`.

Verified on this plan's machine, at a load average of about 150 (a shared Mac, not idle): i-1 median 25.65 ms (met; 366 ms with the CPU mesher in 7c-core's equally loaded run), i-2 median 23.00 ms (met; 395.50 ms before), `i-1m`: 29.43 ms for the GPU mesher against 185.84 ms for the CPU mesher over the same values, 507,760 triangles each.

- [ ] **Step 6: Record the numbers and update the docs**

Replace the numbers in the `performance.md` block below with your run's, keeping the machine and load lines and the wording about the load (if the Mac was idle, say so and drop the caveat). Rows i-3 and i-4 are not re-measured here: i-3 is not on this path, i-4 is 7c-3's (D12), and the text says so. `CLAUDE.md` gets the 7c-1g paragraph and the sentence that the fall-back is silent; the human checks get IM-13.

**Edit `CLAUDE.md`**

Replace:

````markdown
`docs/superpowers/plans/2026-10-13-7c-core.md`, spec `docs/superpowers/specs/2026-10-13-implicit-lattices-design.md` §2 to §6 and the
7c-1 errata in the plan's header) code is done; its human checks (group IM) are pending and its benchmark numbers are recorded in
`docs/verification/performance.md`. Lattices (7c-2), the mesh tools, checks and 3MF (7c-3) and the mappings (7c-4) are not built, nor
are meshing on the GPU (spec Errata D13, plan 7c-1g) and the streamed export (D12, with 7c-3); until they are, meshing runs on the CPU
and row i-4 is expected to miss.

Module boundaries (dependency order):
- `CreatorGeometry`: value types (vectors, planes, profiles, bounds). Millimetres.
````

With:

````markdown
`docs/superpowers/plans/2026-10-13-7c-core.md`, spec `docs/superpowers/specs/2026-10-13-implicit-lattices-design.md` §2 to §6 and the
7c-1 errata in the plan's header) code is done; its human checks (group IM) are pending and its benchmark numbers are recorded in
`docs/verification/performance.md`. Lattices (7c-2), the mesh tools, checks and 3MF (7c-3) and the mappings (7c-4) are not built, nor
is the streamed export (D12, with 7c-3); until it is, row i-4 is expected to miss.
Implicit geometry, sub-project 7c-1g (meshing on the GPU, spec Errata D13: `ImplicitGPUEngine.meshBricks`, the Metal marching-cubes
kernels with a CPU-against-GPU mesh agreement suite, and rows i-1 and i-2 measured on that path; plan
`docs/superpowers/plans/2026-10-14-7c-1g-gpu-meshing.md`) code is done; its human check (IM-13) is pending and its benchmark numbers are
recorded in `docs/verification/performance.md`. The SDL3 engine for Linux and Windows is track xp-c.

Module boundaries (dependency order):
- `CreatorGeometry`: value types (vectors, planes, profiles, bounds). Millimetres.
````

**Edit `CLAUDE.md`** (one line, so another track's edits to the paragraph around it do not collide)

Replace:

````markdown
  GPU sits behind `ImplicitGPUEngine` (`GPU/`: prepare, compile, evaluate a batch, cancel; D13 adds meshing bricks), whose only
````

With:

````markdown
  GPU sits behind `ImplicitGPUEngine` (`GPU/`: prepare, compile, evaluate a batch, mesh bricks, cancel), whose only
````

**Edit `CLAUDE.md`** (one line again: the sentence is split in two where the new text goes)

Replace:

````markdown
  `MeshingBudget`); `PreviewSchedule` is the passes of the progressive preview. `SignedDistanceMesh` (BVH, pseudonormal sign),
````

With:

````markdown
  `MeshingBudget`); `PreviewSchedule` is the passes of the progressive preview (Auto goes on while four times the last pass is under a
  second, so with a fast GPU mesher it ends much finer than it did on the CPU). **Meshing on the GPU (Errata D13):** `ImplicitMesher`
  first offers the plan's bricks to the evaluator (`ImplicitBatchEvaluator.meshBricks`, which `GPUBatchEvaluator` passes to
  `ImplicitGPUEngine.meshBricks(_:_:progress:)`: a `BrickMeshRequest` in, a `BrickMesh` of flat arrays out, no GPU type in either). The
  default requirement throws `.unsupported`, and the mesher then meshes on the CPU, which stays the reference and the fall-back: it also
  takes over when the engine fails, returns arrays that do not fit (`BrickMesh.isConsistent`), or a request is beyond the engine's
  limits (a window of more than 32-bit edge keys, a table over `largestTable`). **That fall-back is silent: test and measure
  `ImplicitMesher.meshReportingPath(...).path` (or `MetalImplicitEngine.meshesMade`), never just the mesh.**
  `MetalImplicitEngine+Meshing` runs the five kernels of `ImplicitMeshShaderLibrary` (Metal source as text, so an SDL3 engine
  translates it) over `BrickLattice`'s window with `MarchingCubesBuffers`, the CPU's table as a buffer; the order of vertices and
  triangles is the threads', the set is fixed. `GPUMeshAgreementTests` holds the GPU mesher to the CPU mesher's topology, triangle
  count, vertices (1e-4 mm on the same samples, for parts near the origin), normals and enclosed volume. `SignedDistanceMesh` (BVH, pseudonormal sign),
````

**Edit `docs/verification/human-checks.md`**

Replace:

````markdown
- [ ] **IM-12 Files.** Save the document, quit, reopen it: the same graph, the same shape, the same badge. Open a file saved before
  this build (any earlier .mcgraph): it opens unchanged and the next save writes `"formatVersion" : 8`. Pinned: `ImplicitFileTests`,
  `ImplicitDocumentFileTests`. **Observed:**
````

With:

````markdown
- [ ] **IM-12 Files.** Save the document, quit, reopen it: the same graph, the same shape, the same badge. Open a file saved before
  this build (any earlier .mcgraph): it opens unchanged and the next save writes `"formatVersion" : 8`. Pinned: `ImplicitFileTests`,
  `ImplicitDocumentFileTests`. **Observed:**
- [ ] **IM-13 The GPU mesher shows no seams, and the finest preview is bearable (7c-1g).** On the build above, watch the finished refinement and orbit it: smooth shading
  everywhere, no dark specks (a vertex without a normal), no cracks or doubled lines where bricks meet (a brick is 8 voxels, 6 mm at the
  first pass), no holes. Export an STL at 0.2 and open it in a slicer: no open or non-manifold edges. Export it again: the same triangle
  count and size (the order of triangles in the file may differ from run to run, which is expected). Also watch the last refinement pass of
  the Auto preview: with the GPU mesher it goes on to about 0.2 mm (some 8 million triangles for the sheet, user decision U5), so orbit it
  for frame rate and look at the memory in Activity Monitor. Pinned:
  `GPUMeshAgreementTests`, `MetalMeshingLimitsTests`; the look and the load are human-only. **Observed:**
````

**Edit `docs/verification/performance.md`**

Replace:

````markdown
from another), because the lattice nodes (7c-2) do not exist yet; 7c-2 swaps in the gyroid and keeps the rows. A gyroid of 8 mm cells
has about 150 million triangles at 0.1 mm, which no in-memory mesh holds in 4 GB, so row i-4 is only reachable for a sparse sheet.
Per the spec's Errata, the budgets of i-1 and i-2 are for the Metal path measured with Metal meshing (D13, plan 7c-1g), and the streamed
export that i-4 needs (D12) belongs to 7c-3. **Until then these rows measure Metal evaluation with the CPU mesher, and i-2 and i-4 are
expected to miss;** the CPU engine records its numbers without a budget (D11).

| Row | Case | Target |
|---|---|---|
````

With:

````markdown
from another), because the lattice nodes (7c-2) do not exist yet; 7c-2 swaps in the gyroid and keeps the rows. A gyroid of 8 mm cells
has about 150 million triangles at 0.1 mm, which no in-memory mesh holds in 4 GB, so row i-4 is only reachable for a sparse sheet.
Per the spec's Errata, the budgets of i-1 and i-2 are for the Metal path measured with Metal meshing (D13, plan 7c-1g), and the streamed
export that i-4 needs (D12) belongs to 7c-3. The first run below measured Metal evaluation with the CPU mesher; **the 7c-1g run after it
measures i-1 and i-2 with the GPU mesher**, which is what the budgets are for. Row i-4 was not re-measured by 7c-1g: it is 7c-3's row,
and its run below predates GPU meshing. The CPU engine records its numbers without a budget (D11). A budget is a record here, never a
gate (7c-1's ruling U6): a miss is written down as a miss.

| Row | Case | Target |
|---|---|---|
````

**Edit `docs/verification/performance.md`**

Replace:

````markdown
BENCH load after: 117.08 110.72 110.68
```

Where the misses are likely to stay on an idle Mac, and who owns them: **i-2** is the first coarse pass again (128 cells across, marching
cubes and the Newton snap on the CPU), so it is about as long as i-1 and cannot be under 100 ms without a coarser first pass or marching
cubes on the GPU (D13, plan 7c-1g, which re-measures it); the spec's targets for i-1 and i-2 are not consistent with each other while
the first pass is the same pass. **i-3** is the tessellation, the BVH and 600 to
2,000 blocks of samples in parallel on the CPU. **i-4** holds the whole mesh and its vertex map in memory (about 150 bytes a triangle);
streaming bricks to the STL, which the user decided on (D12) and 7c-3 builds, cuts the memory; the time is the mesher's, so GPU
meshing (7c-1g) is what moves it.

## Raw output
````

With:

````markdown
BENCH load after: 117.08 110.72 110.68
```

The 7c-1g run: `scripts/bench.sh "ImplicitBench/(theFirstPreview|aThicknessEdit|theFirstPassOnTheGPU)"`, rows i-1 and i-2 with marching
cubes and the Newton snap on the GPU (`MetalImplicitEngine.meshBricks`), and the comparison `i-1m`: the same first pass by the GPU mesher
and by the CPU mesher over the GPU's values, which is how i-1 and i-2 were made before. **The Mac was at a load average of about 150
(other sessions) for the whole run**, so these are not idle-Mac numbers; the GPU rows are GPU-bound and the CPU comparison row is the one
the load inflates. **Re-run on an idle Mac and replace them, keeping the load lines.**

```text
BENCH machine: MacBookPro18,2, 10 cores, macOS 27.0.1
BENCH load before: 145.46 171.87 173.00
BENCH i-1 first preview pass of a 100 mm sheet, cold (shaders compiled): median 474.34 ms, p95 474.34 ms, max 474.34 ms (n 1)
BENCH i-1 first preview pass of a 100 mm sheet: median 25.65 ms, p95 37.04 ms, max 37.04 ms (n 6); budget 1000.00 ms: met
BENCH i-2 thickness edit of a 100 mm sheet (one coarse pass, no recompile): median 23.00 ms, p95 40.39 ms, max 51.61 ms (n 22); budget 100.00 ms: met
BENCH i-1m first pass of the sheet at 0.78 mm, GPU mesher: median 29.43 ms, p95 40.39 ms, max 40.39 ms (n 6)
BENCH i-1m the same pass, CPU mesher over the GPU's values (before D13): median 185.84 ms, p95 203.32 ms, max 203.32 ms (n 6)
BENCH i-1m triangles: GPU 507760, CPU 507760
BENCH load after: 139.40 156.64 165.79
```

Both meshers made 507,760 triangles. The GPU mesh orders its vertices and triangles by thread timing, so the same shape is not the same
file twice (the set is the same). These rows time the first pass only. With a first pass this fast the Auto preview does not stop there:
its rule (four times the last pass under a second) takes it on through 0.39 mm to about 0.2 mm, near 16 times the triangles (about 8
million for the sheet), which this run did not measure and IM-13 asks a person to watch (user decision U5 of the plan). The cold row (474 ms, against 557 ms in the first run) includes the compile of the meshing kernels, a
second library of the same source, which happens on the first mesh of a shape; later passes and edits of that shape reuse it.

The first run's reading of the misses, kept for the record: **i-2** was the first coarse pass again (128 cells across, marching
cubes and the Newton snap on the CPU), so it was about as long as i-1 and could not be under 100 ms without marching cubes on the GPU,
which 7c-1g built; the spec's targets for i-1 and i-2 are not consistent with each other while
the first pass is the same pass. **i-3** is the tessellation, the BVH and 600 to
2,000 blocks of samples in parallel on the CPU. **i-4** holds the whole mesh and its vertex map in memory (about 150 bytes a triangle);
streaming bricks to the STL, which the user decided on (D12) and 7c-3 builds, cuts the memory; the time is the mesher's, so GPU
meshing (7c-1g) was expected to move it, and has not been measured: an export at 0.1 mm meshes on the GPU only while its edge table
fits (`MetalImplicitEngine`'s `largestTable`, 2^27 slots) and its buffers fit the device; otherwise it falls back to the CPU as before.

## Raw output
````

- [ ] **Step 7: Build, warnings, lint, commit**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning"; swiftlint lint --strict 2>&1 | tail -1`
Expected: nothing new; `Found 0 violations, 0 serious`.

```bash
git add Tests/CreatorAppTests CLAUDE.md docs/verification
git commit -m "bench(implicit): i-1 and i-2 on the GPU path, recorded (7c-1g T5)"
```

- [ ] **Step 8: The one full run**

Run (from the worktree, nothing else of yours running): `swift test 2>&1 | tee /tmp/7c-1g-full.log | grep -E "recorded an issue|failed after|Test run with"; echo "exit ${PIPESTATUS[0]}"`
Expected: exit 0, no "recorded an issue" or "failed after" line, 12 "Test run with" lines, and 42 more tests than master: 4,205 on a Mac with Metal (4,189 without).

## Self-review

**Spec coverage (D13 and the task text).**
- "`ImplicitGPUEngine` gains a mesh-bricks requirement": Task 1, with a default so an evaluate-only engine conforms.
- "`MetalImplicitEngine` runs marching cubes on the GPU: the same case table as the CPU mesher": Task 2 `MarchingCubesBuffers` (`theTableBufferIsTheMarchingCubesTable`) and Task 3 kernels read it.
- "shared-edge vertex merge via global edge keys": Task 2 `BrickLattice` keys (the CPU's formula made relative to a window), Task 3 `meshClassify` and `claimSlot`; Task 4 `manySmallBatchesMakeTheMeshOneBigBatchDoes` and every fixture closed manifold.
- "the Newton snap": Task 3 `meshPlace`; Task 4 compares snapped and unsnapped vertices.
- "triangle output through an atomic counter or an append buffer": the cursor in `meshEmit`, the total in `meshClassify`, checked against each other in `meshAttempt`.
- "Keep it behind `#if canImport(Metal)` (D11)": the one engine file is wholly guarded, the shader text is a plain Swift string, `ImplicitPortabilityTests` unchanged and passing.
- "The CPU mesher stays the reference and the fallback; `ImplicitMesher` chooses the GPU path when an engine provides one": Task 1; the CPU loop is untouched.
- "Agreement suite: same topology class (manifold, Euler characteristic, triangle count within the documented tolerance), vertices within 1e-4 mm after the snap, skipped without Metal": Task 4, tolerances documented in the suite's doc comment and in U2; it also holds the normals (dot product) and the enclosed volume (so the winding), which positions alone do not show.
- "Re-measure i-1 and i-2 on the GPU path, record per U6": Task 5.
- "Design the requirement so an SDL3 engine can implement it: buffers in and out, no Metal types": the protocol, `BrickMeshRequest`, `BrickMesh`, and the contract section.
- Not done, by design: i-3 and i-4 are not on this path or are 7c-3's; windowed (streamed) meshing is 7c-3's (the `BrickLattice` window and the request are what it will call per window); a deterministic output order (U3).

**Placeholder scan.** No TBD or TODO; every code step is a complete block generated from the verified commits of this plan (the blocks were applied task by task to a clean copy of 7c-core's `r2` and built, tested and linted after each).

**Type consistency.** `BrickMeshRequest`, `BrickMesh`, `meshBricks`, `MeshingPath`, `meshReportingPath`, `BrickLattice`, `MarchingCubesBuffers`, `ImplicitMeshShaderLibrary` (`Binding`, `Counter`, `probeLimit`, `kernelNames`, `source(extending:)`), `MeshTuning`/`tune` (`afterBatch`, `slotsPerDispatch`), `meshesMade`, `MeshComparison` (`smallestNormalDot`), `SamplesOnlyEvaluator`, `MetalMeshingTests.request`, `Prepared` have one spelling throughout; the buffer indices in the shader text and in `bind(...)` come from the same `Binding` constants.

**Review Focus.** Each of the nine has its test named in its line and in the task that owns it.

**How this plan was verified.** First (the original plan): every Create/Edit block was applied, task by task and step by step, to a fresh clone of 7c-core's `r2` (HEAD `60f1c2d`) with `../MetalUI` linked beside it, by a script that reads the blocks from this file; each task's failing step failed as written, its implementation built with no warning beyond the baseline's `ContextMenuTests.swift` one, its suites passed and `swiftlint lint --strict` reported 0 violations; the one full `swift test` after Task 5 exited 0 with 12 "Test run with" lines and 4,202 tests, and a reviewer repeated it independently (188 tests in `CreatorImplicitTests`, the release bench at i-1 58 ms, i-2 66 ms, i-1m 91.5 ms GPU against 375 ms CPU).

Then (the revision for the review's findings): `r2` was gone and 7c-core had moved on (see Risks, "The base of this revision"), so Tasks 1 to 4 were applied by the same script to a copy of 7c-core's working tree with three hand adaptations that belong to that base and not to the plan (the `source:`-less `ImplicitMesher.mesh`, the engine's stored properties, the `meshingSeconds` line of `BrickMeshingTests`). Built clean (no warning but the linker's); `swiftlint lint --strict` 0 violations; one full `swift test` of that copy exited 0 with no "recorded an issue" or "failed after" line and 12 "Test run with" lines (4,187 tests: that base's own count plus Tasks 1 to 4's 40; its base is not master's 4,163); the six suites filtered (`MeshComparisonTests`, `GPUMeshAgreementTests`, `MetalMeshingLimitsTests`, `MetalMeshingTests`, `BrickMeshingTests`, `BrickLatticeTests`) passed; and the mutations listed under Task 4 step 4 were each made in the copy, failed the suite as described, and were undone. Task 5's bench edits could not be built (no `ImplicitBench` in that base): their helper was compiled in isolation, and the numbers recorded in Task 5 are those of the original run, which the revision's changes (slot ranges, a counter) do not move in kind.
