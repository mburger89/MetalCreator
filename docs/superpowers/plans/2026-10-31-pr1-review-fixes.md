# PR #1 review fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every finding that survived the deep review of PR #1 (`main..b667495`, 2026-10-31): 39 findings, 12 of
them duplicates, so 27 distinct fixes: one medium bug, the slicer's speed, the causes of three known bugs, small bugs,
speed-ups and dead code.

**Architecture:** No new features. Each task owns one area (the OCCT section shim, the mesh slicer, the triangulator, the
cap renderers, the Section app layer, the Measure app layer) and ends green on its own. Runs **after** Measure part B
(`2026-10-31-measure-b-keep.md`), so the Measure task checks each finding against the code part B left.

**Tech Stack:** Swift 6.4, Swift Testing, OpenCascade 7.9 C shim, Metal (MSL) and SDL GPU (HLSL).

**Spec:** `docs/superpowers/specs/2026-10-30-section-measure-design.md`. The review's findings are summarised in each task
below (finding numbers `#n` are the review's, for the record).

## Global Constraints

- OCCT only behind `Kernel`, every shim call under `OCCTKernel.serialized`; no C++ exception crosses into Swift; every C
  allocation has a `*_free`; shim stays portable (`ShimPortabilityTests`).
- MSL (`SectionShaders.swift`) and HLSL (`Shaders/viewport/section.*.hlsl`) change together; `GPUDataTests` and
  `ShaderSourceTests` stay green; `scripts/build-shaders.sh` runs on Linux.
- Swift Testing; `swiftlint lint --strict` 0; 12 "Test run with" lines on macOS and Linux; only the known
  `HLSLEngineTests.onTheCutTheHLSLEngineAgreesWithTheMetalEngine` failure.
- A speed-up preserves behaviour: same sections, same caps, same picks. Where a fix changes output (the slicer's loops,
  the triangulator's triangles) a test says what the new output is and why it is right.
- Benchmarks record, they never gate (spec §9). Numbers from a loaded Mac are labelled saturated in
  `docs/verification/performance.md`.

## Rulings (my calls on the review's open choices)

1. **A failed cap fill** returns the face's region with its boundary pieces and no triangles (not a skip, not a throw), so
   the existing "The cut face couldn't be filled for every part." message shows. (#4)
2. **The figure-eight** is fixed by splitting a walk on a revisited node, not by angular ordering. (#5, #8)
3. **The cap inset** scales with the scene: `max(1e-4, 1e-6 × largest absolute coordinate of the capped solids' bounds)`
   millimetres; the shaders' clip is unchanged. (#17b)
4. **Selected-node preview:** an unresolved face while the preview is not Final keeps the remembered frame and says
   "The face isn't part of this preview." instead of "no longer exists". (#18)
5. **A pick session** leaves the section and its caps as they were: `refreshScene` skips `section.update` and
   `sectionCaps.follow` while `pick != nil`. (#9)
6. **A circle's centre** is its own hover target: before the edge and face fallbacks, the pointer is tested against the
   projected centres of every full-circle edge of the pickable solids (centres cached per scene), and the centre wins
   only within `min(10, 0.5 × the circle's on-screen radius)` points, so a small circle still picks as its edge. (#11, #15)
7. **The triangulator's scan order** may change (resume after a clip) only if the tests that pin triangles still pass or
   pin a set, not an order; otherwise only the allocation-free changes go in. (#25)

---

### Task 1: OCCT section shim

**Files:** `Sources/COCCT/cocct_section.cpp`, `Sources/CreatorOCCT/OCCTShape+Section.swift` (if needed),
tests in `Tests/CreatorOCCTTests` (find the section tests with `grep -rl "section(" Tests/CreatorOCCTTests`).

- [ ] **Step 1: Failing tests.** `aSectionLeavesTheSolidUntouched` (record the largest sub-shape tolerance and the face
  and edge counts of a filleted box's shape before and after ten sections at different offsets: unchanged; add a shim
  query only if none exists — prefer comparing `Topology` and a re-section's result); `aPlaneClearOfThePartIsEmpty`
  (a plane 1 mm beyond a box's top: empty `PlaneSection`, and a plane exactly on the top face, inset as `SectionCaps`
  insets, still gives one region); `anUnfillableFaceKeepsItsOutline` (if a face whose mesh fails can be made reliably;
  otherwise a unit test of the shim's result building with a region of zero triangles — say in the report which).
- [ ] **Step 2: Fix.**
  - #0 (medium): build `BRepAlgoAPI_Common` as `occt_boolean` does (`cocct_ops.cpp:~115-123`): arguments list, tools
    list, `SetNonDestructive(Standard_True)`, `Build()`, then the existing error check.
  - #4: a face left without triangulation keeps its boundary pieces and gives a region with zero triangles (Ruling 1);
    an all-failed section returns those regions, never the empty "miss" result.
  - #19: after the bounds check, return the empty result when all eight corners of the box enlarged by `tolerance` lie
    strictly on one side of the plane.
  - #20: the winding test reads the already-transformed `positions` instead of transforming each node again.
  - #32: delete `BRepTools::Clean(result)` and its include (the copy has no triangulation). Keep the copy.
- [ ] **Step 3:** `swift test --filter CreatorOCCTTests`, `--filter CreatorAppTests`; lint. Commit
  `fix(section): non-destructive section, keep unfilled outlines, skip planes that miss`.

### Task 2: Mesh slicer speed

**Files:** `Sources/CreatorImplicit/Mesh/MeshSlicer.swift`, `Sources/CreatorApp/Section/SectionCaps.swift`,
`Sources/CreatorApp/Section/SectionCapModel.swift`, tests in `Tests/CreatorImplicitTests` (the slicer's) and
`Tests/CreatorAppTests/Bench/SectionBench*`.

**Interfaces:** `MeshSlicer.Prepared` (a `Sendable` final class or struct: the welded vertices, the remapped `UInt32`
triangles with degenerate ones removed), `MeshSlicer.prepare(positions:triangles:) -> Prepared`,
`MeshSlicer.slice(_ prepared: Prepared, plane: Plane) -> PlaneSection`; the existing
`slice(positions:triangles:plane:)` becomes `slice(prepare(…), plane:)`. `SectionCaps` keeps the prepared weld per
`DisplayMesh` by identity in a small bounded cache (8 meshes, LRU) owned by `SectionCapModel`.

- [ ] **Step 1: Tests.** `aPreparedSliceEqualsAFreshSlice` (a lattice-like mesh from the existing fixtures sliced at
  five planes both ways: equal `PlaneSection`s); `aDegenerateTriangleIsDroppedAtPrepare`; `theWeldIsBuiltOncePerMesh`
  (`SectionCapModel` slicing one mesh at three planes prepares once: count through a test hook like `slicesStarted`).
- [ ] **Step 2: Fix** #1, #2, #3, #21, #22: cache the weld (above); the triangle loop reads three remapped indices and
  three distances into locals and skips a non-crossing triangle before any allocation, choosing the lone corner by
  comparing signs; adjacency becomes two `Int32` slots per node with an overflow dictionary; `chains()` counts unused
  neighbours without `filter`; `reserveCapacity` on the arrays it grows.
- [ ] **Step 3:** Run the slicer and `SectionCapModel` tests; run `scripts/bench.sh SectionBench` before (on the base
  commit) and after, and put both `sa-2` rows in the report. Commit `perf(section): weld a mesh once and slice without
  per-triangle allocations`.

### Task 3: Mesh slicer correctness and tidying

**Files:** `Sources/CreatorImplicit/Mesh/MeshSlicer.swift`, its tests.

- [ ] **Step 1: Failing tests.** `twoBoxesSharingAnEdgeGiveTwoLoops` (two welded boxes touching along an edge, sliced
  across it: two closed loops, neither repeating a node; this is the figure-eight); `anIslandTouchingAHoleAtAPointIsAnIsland`
  (a frame and a block inside its hole touching the hole's side at one vertex on the plane: the block is filled, the
  hole stays open).
- [ ] **Step 2: Fix.** #5/#8: `walk` keeps `firstSeen[node]`; on reaching a node already on the chain it cuts that run
  off as its own closed loop and continues (open chains too) (Ruling 2). #6: the nesting test uses the first point of the
  inner loop not within 1e-9 mm of the outer loop's edges, else the majority vote over its points. #33: the identity
  index array is `Array(0..<UInt32(count))` (the indexed variant is not worth it). #34: drop the repeated condition and
  the `changed` flag in `simplified()` as the review wrote it.
- [ ] **Step 3:** Run the slicer tests and `--filter CreatorAppTests`. Commit `fix(section): split pinched mesh loops and
  test nesting off the outline`.

### Task 4: Polygon triangulator

**Files:** `Sources/CreatorGeometry/PolygonTriangulator.swift`, `Tests/CreatorGeometryTests` (its tests).

- [ ] **Step 1: Tests.** `manyHolesTriangulateCompletely` (a square with 200 small square holes: triangles cover the
  area minus the holes to 1e-9 relative, no triangle inside a hole); keep every existing test.
- [ ] **Step 2: Fix.** #23: one private wrapping-edge loop helper replaces `zip(loop, loop.dropFirst() + loop.prefix(1))`
  at its three sites. #24/#31: bridging compares squared distances and takes candidates by lazy minimum instead of a full
  sort; `isClear` skips loops whose padded bounding box misses the segment. #25: `isEar` uses three index locals instead
  of an array; resuming the scan near the clipped vertex follows Ruling 7.
- [ ] **Step 3:** `swift test --filter CreatorGeometryTests` and `--filter CreatorSketchEditorTests` (region fills use
  it); `scripts/bench.sh SectionBench` after, rows in the report. Commit `perf(geometry): triangulate holes without
  copies or full sorts`.

### Task 5: Cap rendering, Metal and SDL

**Files:** `Sources/CreatorViewport/Render/SectionUniforms.swift`, `ViewportRenderer+Section.swift`,
`SectionShaders.swift`, `Sources/CreatorViewport/RenderSDL/SDLViewportRenderer+Section.swift`, `SDLViewportPipelines.swift`,
`SDLViewportShaders.swift`, `Shaders/viewport/section.frag.hlsl`, delete `Shaders/viewport/id_section.vert.hlsl`,
`Sources/CreatorApp/Section/SectionCaps.swift` (inset), tests `GPUDataTests`, `ShaderSourceTests`, the section render tests.

- [ ] **Step 1: Tests.** `aPaletteChangeKeepsTheCapBuffers` (both renderers' caches: a new palette with the same
  generation rebuilds only the outline instances); `theInsetGrowsWithTheScene` (`SectionCaps.plane(for:bounds:)`: 1e-4 for
  a part near the origin, 5e-4 for one at 500 mm); update the stage-count pins from 24 to 23.
- [ ] **Step 2: Fix.** #17a: the hatch is antialiased: distance to the stripe's centre line blended with `smoothstep` over
  `fwidth`, identical in MSL and HLSL. #17b: Ruling 3. #27/#29: `SectionVertex.vertices(of:)` indexes the three corners
  directly, converts positions to float once, reserves capacity, still skips a triangle with a bad index. #28/#30: cap
  buffers keyed by generation, outline instances by generation and `sectionEdge`; SDL's `idPassInputs` stops comparing
  palettes. #37: delete `id_section.vert.hlsl`; the SDL `idSection` pipeline uses `section` as its vertex stage and
  `id_section` as its fragment; the shader list knows fragment-only names. #38: delete the dead `setCullMode(.none)`.
- [ ] **Step 3:** `swift test --filter CreatorViewportTests`, `--filter CreatorAppTests`; `scripts/linux-test.sh test
  --filter CreatorViewportTests` (the HLSL compiles and the SDL render tests pass). Commit `perf(section): cap buffers
  survive theme changes; antialiased hatch; one section vertex shader`.

### Task 6: Section app layer

**Files:** `Sources/CreatorApp/AppModel+Scene.swift`, `AppModel+Section.swift`, `Section/SectionModel.swift`,
`Section/SectionCapModel.swift`, `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift`,
`Sources/CreatorKernel/FakeKernel+Section.swift` (and the fake's prism faces if needed), tests in `Tests/CreatorAppTests`.

- [ ] **Step 1: Failing tests.** `aPickSessionLeavesTheSectionAlone` (section on, start an Edges by Tag pick: the
  section's note, handle and caps' `revision` unchanged until the pick ends); `noSectionFromFaceOnAGhost` (the face menu
  of a ghosted item has no Section from Face, and `sectionFromFace` on it does nothing); `aFaceOutsideTheSelectedPreviewIsNotLost`
  (Selected-node preview of a node that is not the face's: the frame stays, the note is "The face isn't part of this
  preview."); `theFakeKernelNamesThePrismSideFaces` (a fake extrusion's section pieces carry `sourceFace`).
- [ ] **Step 2: Fix.** #9 Ruling 5; #10 both the guard and the menu; #18 Ruling 4; #35 replace `discardsRunning` with
  `Task.isCancelled` read after the loop (the existing order tests must stay green); #7 fix the stale comment and give
  the fake's planar prism sides their outward normal so `sourceFace` resolves.
- [ ] **Step 3:** `swift test --filter CreatorAppTests`, `--filter CreatorKernelTests`, `--filter CreatorViewportTests`.
  Commit `fix(section): leave the section alone while picking; no section from ghosts; preview note`.

### Task 7: Measure app layer

**Files:** `Sources/CreatorApp/Measure/*`, `Sources/CreatorApp/AppModel+Measure.swift`, tests in
`Tests/CreatorAppTests/Measure`.

Measure part B rewrote `MeasureSession`. First check each finding below against the current code and say in the report
which part B already fixed (no change, no test needed for those).

- [ ] **Step 1: Failing tests.** `aLargeHoleCentreSnaps` (a 40 mm hole seen at about 100 pt radius: the pointer at its
  centre hovers and picks `.corner(…, .centre, …)`); `aSmallCircleStillPicksAsItsEdge` (on-screen radius 8 pt, pointer on
  the rim: `.edge`); `oneVertexThroughTwoEdgesTogglesOff` (#12); `measureStartedDuringALoadFollowsTheLoadedScene` (#13);
  `anAngleIsDrawnWithoutADistance` (#14: the kernel refuses the distance; the angle dimension still draws, its vertex the
  midpoint of the two picks' anchor points: an edge's midpoint, a face's centroid); `aHoverOnAReplacedSolidIsDropped` (#16).
- [ ] **Step 2: Fix.** #11/#15 Ruling 6; #12 corners equal by solid and point within 1e-6 mm when toggling; #13
  re-register the scene observation when Measure starts; #14 as the test says; #16 drop a hover whose solid was replaced;
  #26 `showMeasureOverlay` appends the session's overlay to a layout overlay cached in `refreshScene` (invalidated
  wherever `layoutOverlay`'s inputs change); #36 delete `revision` if part B left it unread.
- [ ] **Step 3:** `swift test --filter CreatorAppTests`. Commit `fix(measure): centre snap on real holes, one vertex one
  pick, angle without a distance`.

### Task 8: Records

**Files:** `docs/verification/performance.md`, `docs/verification/human-checks.md`, `CLAUDE.md`.

- [ ] **Step 1:** `performance.md`: the `sa-1` to `sa-3` rows after Tasks 2 and 4, with the machine's load noted.
- [ ] **Step 2:** human checks: SA-B gains "the hatch has no shimmer while orbiting" and "a section during an Edges by
  Tag pick is unchanged"; ME-A gains "a large hole's centre snaps".
- [ ] **Step 3:** CLAUDE.md: the section's shader count (24 → 23 stages), `MeshSlicer.prepare`, the preview note. Remove
  the known limitations these fixes closed from wherever they are recorded (the PR body is updated at push time).
- [ ] **Step 4:** full `swift test` (12 lines), `swiftlint lint --strict`, `scripts/linux-test.sh test`. Commit
  `docs(section): records after the review fixes`.
