# NS-4: Editing surfaces — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trim Surface, Split Surface, Intersection Curves, Extend Surface, Match Surface and Blend Surface, the naming and file
format that keep picks on their results from drifting, the viewport picks they need, and the owed NS-3 follow-up.

**Architecture:** One kernel call (`Kernel.split`) cuts a sheet by curves (projected) or a body with OCCT's `BRepAlgoAPI_Splitter`
and names every piece by the cutter elements it borders and the side it lies on (`TopoRole.cutSide`), and every cut edge by its
cutter element (`BoundaryRole.cut`); Trim and Split choose pieces from that one result. Extend and Match change one untrimmed
face's B-spline in place on a copy (NS-3's `replace_face_surface` path), so the topology, and every tag, is the input's. Blend
builds a new sheet from quintic sections (`cocct_g2_section.hpp`) skinned with the G2 fillet's skinning code, lifted into a
shared header. Every G1/G2 promise is measured after the build with the two-body continuity grade and refused in words when it
misses.

**Tech Stack:** Swift 6.4, Swift Testing, OpenCascade 7.9 (`BRepAlgoAPI_Splitter`, `BRepAlgoAPI_Section`,
`BRepOffsetAPI_NormalProjection`, `BRepPrimAPI_MakePrism`, `GeomLib::ExtendSurfByLength`, `ShapeAnalysis_FreeBounds`,
`BRepClass_FaceClassifier`, `BRepClass3d_SolidClassifier`, `BRepCheck_Analyzer`), MetalUI.

**Spec:** `docs/superpowers/specs/2026-11-17-nurbs-surfaces-design.md`. Read §Anti-goals, §Naming, §Joining a part, §Rules every
surface node follows and §NS-4. CLAUDE.md's NS-1, NS-2 and NS-3 paragraphs describe the sheet contract, boundary naming, the
two-body continuity call and the control-point code this plan builds on.

## Global Constraints

- **Worktree and branch.** Worktree `/Users/maxburger/Developer/MetalCreator-ns4`, branch `ns-4`. Never touch MetalUI.
- **OCCT only through the kernel,** under `OCCTKernel.serialized`; every C allocation has a `*_free`; no C++ exception crosses into
  Swift (`guarded`). Shim portability: no `M_PI` (`cocct::kPi`), no POSIX headers, no `__attribute__`, never the token `near`
  (reword; never split it across literals).
- **Valid results only.** Every result is checked with `BRepCheck_Analyzer`; an invalid one is refused in a sentence.
- **Promises are measured** (spec anti-goal): a G1 or G2 join is graded after the build with `edge_continuity_against` (the
  thresholds of `Kernel.continuity`: position 1e-4 mm, angle 0.01°, curvature within 1 %) and a miss is refused in words; a
  result is never labelled better than it measured.
- **Picks don't drift:** Extend Surface and Match Surface keep the input's topology tables unchanged (`carryingTopology`); Trim
  and Split name pieces and cut edges by R2.
- **Separate sheets** (spec §Joining a part): Blend Surface outputs a new sheet; nothing is sewn into a part.
- **Limits:** at most 100,000 control points per surface; every limit and refusal is a full sentence, numbers through
  `Locale.messages` (`Double.display`, `Int.display`).
- **Cancellation** is asked between sections, curves, refinement passes and splitter stages (`occt_cancel`, as
  `networkSurface` polls it).
- **File format 16** (`GraphFile.currentFormatVersion`): `ConstantValue.facePicks`, `TopoRole.cutSide` and `BoundaryRole.cut` in
  saved picks. Files of format 1 to 15 open unchanged and are written as 16.
- **Undo names** have no numbers and no typed text: "Pick Trim Regions", "Clear Trim Regions"; edge picks keep "Pick Edges".
- **Kernel calls** are refused by default and in `FakeKernel` with `KernelError.unsupported`, named as gerund phrases ("splitting
  surfaces"), so the existing "<Operation> isn't supported by this kernel yet." sentence reads correctly.
- **Tests and checks.** Swift Testing only; OCCT tests gated `#if canImport(CreatorOCCT)`; `swiftlint lint --strict` over the whole
  tree; macOS and Linux each print 14 "Test run with" lines and never "recorded an issue" or "failed after"; never block a pool
  thread in a test (use `HookGate`).
- **Commit trailer:** `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_0195iKYokoi2BJLpboZBys76`.

## Rulings (where this plan narrows the spec; each says why and what it costs if wrong)

- **R1. Names.** Trim Surface (`creator.trimSurface`), Split Surface (`creator.splitSurface`), Intersection Curves
  (`creator.intersectionCurves`), Extend Surface (`creator.extendSurface`), Match Surface (`creator.matchSurface`), Blend Surface
  (`creator.blendSurface`). "Intersect" is taken by the Implicit node and NS-5 adds Split Solid, so every NS-4 name says what it
  works on. Five sit in a new `.surface` library section "Edit", Intersection Curves in "Curves". 110 built-in nodes after NS-4,
  `.surface` 20. Cost if wrong: a rename later is a `typeID` migration.
- **R2. Naming pieces and cut edges.** A cutter is made of elements (`CutterName`): `.curve(index:piece:)`, piece `piece` of curve
  `index` in the cutter list as the node flattens it (a profile gives its outer loop, then its holes), or `.face(tags)`, a face of a
  cutting body by its tags. A piece's faces keep their source face's tags plus one `TopoTag(node, .cutSide(element, side))` per
  element bordering the face. `CutSide` is `.inside` / `.outside` for an element of a closed flat curve (inside the loop, seen along
  the projection) or of a closed solid, else `.front` / `.back`: front is the side the cutting surface's normal points to, where the
  normal is t × d (along a direction d), t × N (along normals; N the sheet face's oriented normal), or the cutter face's oriented
  normal (a sheet cutter). A cut edge carries `TopoTag(node, .boundary(.cut(element)))` (also when it is a two-face edge of the whole
  split); a piece of an input edge keeps that edge's tags. Why: a pick on the disk cut by a circle must still name the disk when the
  circle grows or the sheet changes. Cost: reversing an open cutter curve swaps front and back, so a keep pick then names the other
  side; closed cutters (the common hole) are immune. Documented in CLAUDE.md and the human checks.
- **R3. Format 16** for R2's two roles and the `facePicks` kind (older readers can't decode them).
- **R4. Trim's `keep`** is Picked (default), Inside or Outside. Picked with no picks keeps every piece and warns. Each pick keeps
  one face of the whole split: its single match, the match nearest its centroid when it names several (warned), or the narrowed
  part (`Topology.resolution(of:)`, warned in `FacePickWording`'s words); a pick naming nothing warns; all picks naming nothing is a
  refusal. Inside and Outside are even-odd over the cutter's closed flat curves (classified in the curves' plane along the
  projection) or the closed solid's inside, and are refused for any other cutter. Why: deterministic, never silent.
- **R5. Trim has a second output, `pieces`:** the whole split as one sheet (every piece, cut edges shared). It is what keep picks
  name and what "Pick regions in view…" shows; the node lists it in `NodeDefinition.previewHiddenOutputs`, so a selected Trim
  shows only the kept surface. Cost: one more output to explain; the alternative (the app re-running the split) duplicates the
  node's input reading.
- **R6. Split Surface's list** holds one sheet per connected piece (faces joined across uncut edges), ordered by the canonical sort
  key of the piece's smallest face tag set (tag `sortKey`s sorted and joined by "+"), ties by centroid x, then y, then z.
- **R7. Projection.** Along a direction the cutter is the curves' prism through the sheet both ways (`BRepPrimAPI_MakePrism` over
  twice the sheet's bounding diagonal, centred), each prism face named `.curve(index:piece:)`; along normals,
  `BRepOffsetAPI_NormalProjection` puts edges on the faces. Both are cut with `BRepAlgoAPI_Splitter`. A cutter part that doesn't
  divide a face (it ends inside it) is dropped with a warning; no division at all is a refusal.
- **R8. Extend Surface** takes a sheet of one face and edges that are untrimmed iso-boundaries of its (converted) B-spline surface.
  Natural is `GeomLib::ExtendSurfByLength` with continuity 2. Linear is ours: one span appended across the edge whose poles lie
  evenly on the line from each boundary pole along `P0 − P1` (the cross tangent), scaled so the extension at the edge's middle pole
  is `length` (it varies where the cross speed varies). The face keeps its edges (pcurves moved to the new iso values), so the
  topology is the input's. The join is graded across the old iso line at 32 samples (G2 Natural, G1 Linear) and refused on a miss.
  Cost: Extend on a multi-face or trimmed sheet is refused (parked).
- **R9. Match Surface** changes a sheet of one face along an untrimmed iso edge, to one target edge. Rows 0..c (c = continuity) move;
  the cross degree is raised to at least c + 1 and knots inserted in the first cross span until there are at least c + 2 rows, so
  the opposite edge never moves. The target is reparametrised by arc-length fraction from the end nearer the edge's start. A solid
  target edge has two faces: the one whose outward cross direction at the target's midpoint best agrees with the sheet's inward
  cross direction is matched. Refinement doubles the spans along the edge up to 5 times (or to 100,000 poles), then refuses
  naming the grade it reached. Ends more than 0.01 mm apart refuse in the spec's words. Never refused for being ugly; a fold warns.
- **R10. Blend Surface** takes one edge on each side (a sheet's or a solid's). A solid edge uses the face whose outward cross
  direction at the edge's midpoint points most toward the other edge's midpoint. The second edge is reversed when that makes the
  sum of end-to-end distances smaller. Each section is `quintic_poles` with tangent length `bulge × circular_tangent_length`;
  a G2 end takes the face's normal curvature as acceleration, a G1 end zero acceleration (so G1 and G2 differ). Sections start at
  9, skinned cubic, then quintic, doubling to at most 129, as the G2 fillet strips do (their skinning moves to
  `cocct_g2_skin.hpp`, unchanged). Naming as Network Surface's R6: face `.side(loop: 0, segment: 0)`, first edge
  `.boundary(.start)`, second `.boundary(.end)`, sides `.boundary(.rail(0))` (from the first edge's start) and `.rail(1)`.
- **R11. Scrubbing.** Match Surface and Blend Surface asked for G2 build at G1 while `context.isScrubbing`, with no warnings, and
  `readsScrubbing(for:)` is true only when G2 is chosen (the G2 fillet's rule), so a drag stays fast and the G2 build follows.
- **R12. Continuity type.** Match and Blend reuse `PatchContinuity` (G0/G1/G2); Blend refuses `.g0` ("Blend Surface joins at G1 or
  G2.") though its control offers only G1 and G2.
- **R13. Two-body grade needs most samples** (backlog item): `edge_continuity_against` throws "Too few points along the edge lie on
  the other face to grade it." when fewer than 24 of its 32 samples are usable, so a G2 grade can't rest on half an edge.
- **R14. Intersection Curves** chains the section edges into wires (`ShapeAnalysis_FreeBounds::ConnectEdgesToWires`, 1e-6 mm); an
  open curve runs from its lexicographically smaller end (x, y, z with 1e-6 ties), a closed one starts at its lexicographically
  smallest vertex, and the list is ordered by start point the same way, so the order survives a common move.
- **R15. Edge picks for a second socket.** `AppModel.beginPick(for:socket:)` generalises `beginPick(for:)` (socket "edges"); two
  new actions, `pickTargetEdgesInView` (socket "target", Match) and `pickOtherEdgesInView` (socket "other edges", Blend), wire an
  Edges by Tag rule exactly as Fillet's button does.
- **R16. NS-3 follow-up** (owed): one tolerance `SurfaceNet.coincidence = 1e-6` mm (Swift) and `cocct::kNetCoincidence` (shim) for
  pole grouping, the rebuild pin and the apex/seam guard; the guard refuses when an edge's gap grows by more than the tolerance
  over its gap before (per edge), so a vendor apex 1e-6 to 1e-4 mm wide is still guarded; Rebuild pins a row whose poles all lie
  within the tolerance of their centroid to that centroid; grouping is the transitive closure within the tolerance, bucketed by
  quantised position; typing applies to a selection that is one coincident group, as one "Change Control Point" step; a drag on a
  partly selected group selects the whole group first. Also pulled in: a face covering only part of a periodic surface's period
  rebuilds clamped over the face's range, so it no longer earns "A closed surface needs at least N spans…".

**Backlog (`nurbs-backlog-after-ns2` memory).** Pulled in: the NS-3 follow-up (R16, Tasks 1 and 2), the partial periodic Rebuild
(Task 1), the two-body half-sample grade (R13, Task 8), `into_face_range`'s periodic remap test (Task 4). Parked: the guide
sweep's fixed 1e-3 mm tolerance and multi-face guide edges; Network Surface's tolerance against arc approximations; the G2
Boundary Patch limits; twist parallel transport; the `unsupported` sentence's grammar (NS-4's names are gerunds); the fold
check's false positives; `extraDemand` reference counting; cancelling superseded net reads; the theme editor's Esc; the closed
degree-3 Curve through Points' C1 seam. New parked items from this plan: Extend on multi-face or trimmed sheets, Match on trimmed
edges, chains of edges for Match and Blend.

## Review Focus

1. **A cutter that only partly crosses the sheet** (a curve ending inside a face): that part is dropped with the warning, the rest
   still cuts; nothing cut is a refusal, never an unchanged sheet passed off as trimmed. Task 4 (`aDanglingCurveWarns`).
2. **A keep pick after the cutter moves** (the picked piece splits in two, or vanishes): Trim keeps one piece deterministically and
   warns, never silently the other side. Task 5 (`aPickThatNamesTwoPiecesWarns`, `aVanishedPickWarns`).
3. **Trimming a closed (360°) sheet across its seam:** the pieces are right and grading on the trimmed periodic face works
   (`into_face_range`). Task 4 (`aPeriodicSheetSplitsAcrossItsSeam`).
4. **Match or Blend against a solid's edge** (two faces) **or a target running the other way:** the face and direction are chosen
   by R9 and R10 and the result grades as promised. Tasks 8 and 9 (`aSolidTargetUsesTheContinuedFace`, `aReversedEdgeIsPaired`).
5. **A slider dragged upstream of a G2 Match or Blend:** G1 while dragging, no stale warning, the G2 build after; never a G2 claim
   on a G1 surface. Task 10 (`matchBuildsG1WhileScrubbing`, `blendBuildsG1WhileScrubbing`).

---

### Task 1: NS-3 follow-up, kernel (one tolerance, per-edge guard, centroid pin, partial periodic rebuild)

**Files:**
- Modify: `Sources/COCCT/cocct_control_net.hpp` (`kNetCoincidence`), `Sources/COCCT/cocct_control_net.cpp` (the `opening` guard;
  a test-only `occt_test_spread_apex` and `occt_test_partial_periodic_sheet`), `Sources/COCCT/cocct_rebuild.cpp` (`pin_collapsed`,
  periodic detection), `Sources/COCCT/include/cocct.h` (`occt_net_coincidence`, the two test helpers),
  `Sources/CreatorKernel/ControlNet.swift`, `Sources/CreatorOCCT/OCCTShape+TestSupport.swift`
- Test: `Tests/CreatorOCCTTests/ApexSeamTests.swift`, `Tests/CreatorOCCTTests/RebuildTests.swift`

**Interfaces:**
- Produces: `SurfaceNet.coincidence: Double = 1e-6` (static, CreatorKernel); `double occt_net_coincidence(void)` returning
  `cocct::kNetCoincidence`; test helpers `OCCTKernel.spreadingApex(of: Solid, by: Double) throws -> Solid` (moves the apex row's
  poles apart by `distance` around their point, bypassing the guard) and `OCCTKernel.partialPeriodicSheet(fraction: Double, tag:)
  throws -> Solid` (a periodic degree-3 B-spline tube of radius 10, one face over `fraction` of its u period).
- Guard: for every degenerated edge and every seam, the gap before and after (max over nine samples); refuse (existing sentences,
  unchanged) when some edge's `after > before + kNetCoincidence`.
- Rebuild pin: a clamped boundary row is collapsed when every pole lies within `kNetCoincidence` of the row's centroid; it is
  pinned to that centroid. Periodic fit in a direction only when the face's UV bounds span the surface's whole period (within
  1e-9 relative); otherwise clamped over the face's UV range.

- [ ] **Step 1: Tests.**
  - `theToleranceIsShared`: `occt_net_coincidence() == SurfaceNet.coincidence`.
  - `aWideApexIsStillGuarded`: a revolved dome sheet (Revolve Curve of a quarter arc about its axis), apex spread by 1e-4 mm, then
    one apex pole moved by (0, 0, 1) → "Moving these control points opens the surface at its apex; move the matching points together."
    (today it is accepted).
  - `aWideApexAllowsInteriorMoves`: the same spread dome, an interior pole moved by (0, 0, 1) → accepted, valid.
  - `aNearlyCollapsedRowIsPinnedToItsCentroid`: apex spread by 5e-7 → `rebuilt(_:as:)` at 3 × 3, 4 × 4 → the rebuilt apex row's poles
    all equal the source row's centroid within 1e-12.
  - `aWideApexRebuildNeverWidens`: apex spread by 1e-4 → Rebuild either refuses "Rebuilding opens the surface at its apex." or
    gives an apex gap ≤ 1e-4 + 1e-6.
  - `aPartOfAPeriodicSurfaceRebuildsClamped`: `partialPeriodicSheet(fraction: 0.5)` rebuilt at degree 3, 2 spans → succeeds (no
    "closed surface" refusal), deviation < 0.05 mm; `fraction: 1` still rebuilds periodic.
- [ ] **Step 2: Run** `swift test --filter 'ApexSeamTests|RebuildTests'`; the new tests fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter, then `swift test --filter 'ControlNetTests|PoleMoveTests|PoleMoveBoundsTests'`; pass.
- [ ] **Step 5: Commit** "NURBS: one control-net tolerance, per-edge apex guard".

### Task 2: NS-3 follow-up, the mode (grouping, typing a group, partly selected drags)

**Files:**
- Modify: `Sources/CreatorApp/ControlNet/ControlNetSession.swift` (`coincidentPoles`, `setOffset`, `typedTarget`),
  `ControlNetSession+Drag.swift` (`dragBegan`), `ControlNetInspector.swift` (fields and `selectionText`)
- Test: `Tests/CreatorAppTests/ControlNetGroupTests.swift`

**Interfaces:**
- Consumes: `SurfaceNet.coincidence` (Task 1).
- Produces: `ControlNetSession.typedTarget: PoleIndex?` — the selection's smallest index when the selection is exactly one
  coincident group (a lone pole is a group of one), else `nil`; the inspector shows the x, y, z fields when it is non-nil.
  `ControlNetInspector.selectionText(points:)` counts a group once ("1 point selected").
- Grouping: poles bucketed by `floor(coordinate / coincidence)` per axis; neighbours searched in the 27 surrounding buckets; groups
  are the connected sets (union-find) of poles within `coincidence` of a neighbour.

- [ ] **Step 1: Tests** (session-level with the existing fake projector; app-level through `AppModel` as `ControlNetModeTests` does):
  `groupingIsTransitiveWithinTheTolerance` (poles at x = 0, 0.6e-6, 1.2e-6 → one group); `polesFurtherApartAreSeparate` (2e-6
  → two); `aConstantXNetGroupsQuickly` (a 300 × 300 net, x = 0 everywhere, distinct y and z → no groups, under 5 s by
  `ContinuousClock`); `typingOnAnApexMovesTheWholeGroup` (apex of 3 poles selected, `setOffset(2, to: 2)` → one `moved` report
  of 3 moves with offset (0, 0, 2), phase `.typed`); `typingAGroupIsOneStep` (app: one undo step, "Undo Change Control Point");
  `aDragOnAPartlySelectedGroupMovesTheWholeGroup` (⌘-click removes one apex pole, a drag on another → all 3 move);
  `theSelectionCountsAGroupOnce` ("1 point selected" for an apex).
- [ ] **Step 2: Run** `swift test --filter ControlNetGroupTests`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `swift test --filter 'ControlNet'`; pass.
- [ ] **Step 5: Commit** "NURBS: control-point groups follow-up".

### Task 3: Cut naming, format 16 and the NS-4 kernel surface

**Files:**
- Create: `Sources/CreatorKernel/CutterName.swift`, `Sources/CreatorKernel/SurfaceEditing.swift`,
  `Sources/CreatorKernel/TopoRole+NestedTags.swift`
- Modify: `Sources/CreatorKernel/BoundaryRole.swift`, `TopoRole.swift`, `TopoRole+Codable.swift`, `TopoRole+Stability.swift`,
  `TopoTag+Item.swift`, `TopoTag+Instance.swift`, `Kernel.swift` (requirements and refusing defaults),
  `Sources/CreatorGraph/Groups/ConstantValue+TagRenaming.swift`, `Sources/CreatorGraph/ConstantValue.swift`, `NodeSetting.swift`,
  `GraphFile.swift`, and every exhaustive `switch` the compiler names (`Scalar.swift`, `InspectorBuilder.swift`,
  `CreatorMCP/Tools/ReadTools+Values.swift`)
- Test: `Tests/CreatorKernelTests/CutNamingTests.swift`, `Tests/CreatorGraphTests/FacePicksFileTests.swift`

**Interfaces:**
- Produces (CreatorKernel):
  - `public enum CutterName: Hashable, Sendable, Codable { case curve(index: Int, piece: Int); case face(Set<TopoTag>) }`, `sortKey`
    `"curve(i:k)"` / `"face(<tag sortKeys sorted, joined by +>)"`; JSON `{"kind":"curve","index","piece"}` / `{"kind":"face","tags":[…]}`
    (tags sorted by `sortKey`).
  - `public enum CutSide: String, Hashable, Sendable, Codable { case front, back, inside, outside }`.
  - `BoundaryRole.cut(CutterName)` (JSON kind `cut`, key `cutter`; `sortKey` `"cut(<name>)"`); `TopoRole.cutSide(CutterName, CutSide)`
    (JSON role `cutSide`, keys `cutter`, `side`; `sortKey` `"cutSide(<name>:<side>)"`).
  - `TopoRole.nestedTags: Set<TopoTag>` and `TopoRole.mappingNestedTags(_ transform: (TopoTag) -> TopoTag) -> TopoRole` (blend
    source edges, `.cutSide(.face)` and `.boundary(.cut(.face))`); `withItem`, `qualified(item:_:)`, `instanceTags`, `isUnstable` and
    the group renaming use them instead of matching `.blend` alone.
  - `SurfaceEditing.swift`: `public enum TrimProjection: Int, Sendable { case alongDirection = 0, alongNormals = 1 }`;
    `public enum TrimCutter: Sendable { case curves([Curve], projection: TrimProjection, direction: Vector3); case body(Solid) }`;
    `public struct SheetSplit: Sendable { public var whole: Solid; public var pieces: [[FaceID]]; public var inside: Set<FaceID>?;
    public var warnings: [String] }` (`inside` is `nil` when the cutter isn't closed, R4); `public enum ExtendMode: Int, Sendable {
    case natural = 0, linear = 1 }`; `public struct SurfaceBlendEnd: Sendable { public var body: Solid; public var edge: EdgeID;
    public var continuity: PatchContinuity; public var bulge: Double }`.
  - `Kernel` requirements, each refused by default with `KernelError.unsupported` (name in brackets):
    `split(_ sheet: Solid, by cutter: TrimCutter, tag: NodeTag) async throws -> SheetSplit` ("splitting surfaces");
    `subSheet(_ faces: [FaceID], of sheet: Solid) throws -> Solid` ("keeping faces of a sheet");
    `intersectionCurves(_ a: Solid, _ b: Solid, tag: NodeTag) async throws -> [Curve]` ("intersecting bodies");
    `extended(_ sheet: Solid, edges: [EdgeID], length: Double, mode: ExtendMode) async throws -> Solid` ("extending surfaces");
    `matched(_ sheet: Solid, edge: EdgeID, to target: EdgeID, of body: Solid, continuity: PatchContinuity) async throws -> Solid`
    ("matching surfaces"); `blendSurface(_ first: SurfaceBlendEnd, _ second: SurfaceBlendEnd, tag: NodeTag) async throws -> Solid`
    ("blending surfaces").
- Produces (CreatorGraph): `ConstantValue.facePicks([FacePick])` (Codable kind `facePicks`; always finite);
  `NodeSetting.keepRegions: SocketName = "keepRegions"` (in `all` and `reservedForSockets`); `GraphFile.currentFormatVersion == 16`;
  group renaming (`ConstantValue+TagRenaming`) renames every pick in a `facePicks`.

- [ ] **Step 1: Tests.**
  - `cutSideRoundTrips`: `.cutSide(.curve(index: 1, piece: 2), .inside)` and `.cutSide(.face([a, b]), .front)` encode and decode
    equal; `sortKey` of the first is `"cutSide(curve(1:2):inside)"`.
  - `cutEdgeRoundTrips`: `.boundary(.cut(.curve(index: 0, piece: 0)))`, sortKey `"boundary(cut(curve(0:0)))"`.
  - `nestedTagsAreRenamed`: a `.cutSide(.face([t]))` tag → `withItem(5)` gives the nested `t.item == 5`; `qualified` qualifies it;
    `isUnstable` is true when `t` is `.unnamed`; group renaming of a `facePicks` value renames nested tags.
  - `facePicksRoundTrip`, `aFormat15FileOpens` (an existing format-15 fixture decodes), `theFormatIs16`, `keepRegionsIsReserved` (a
    group socket named "keepRegions" is refused).
  - `fakeKernelRefusesTheNewCalls`: each of the six calls on `FakeKernel` throws `.unsupported` with its name.
- [ ] **Step 2: Run** `swift test --filter 'CutNamingTests|FacePicksFileTests'`; compile failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter, then `swift test --filter CreatorKernelTests` and `--filter CreatorGraphTests`; pass.
- [ ] **Step 5: Commit** "NURBS: cut naming and format 16".

### Task 4: Splitting a sheet (kernel)

**Files:**
- Create: `Sources/COCCT/cocct_trim.cpp`, `Sources/CreatorOCCT/OCCTKernel+Trim.swift`, `Sources/CreatorOCCT/OCCTShape+Trim.swift`
- Modify: `Sources/COCCT/include/cocct.h`, `Sources/CreatorOCCT/OCCTTagger.swift` (extra face tags per output face; per-edge tag
  overrides)
- Test: `Tests/CreatorOCCTTests/SheetSplitTests.swift`, `Tests/CreatorOCCTTests/TwoBodyContinuityTests.swift`

**Interfaces:**
- Consumes: Task 3's types.
- Produces: `OCCTKernel.split(_:by:tag:)` and `OCCTKernel.subSheet(_:of:)`.
  - The shim (`occt_split_sheet`, freed by `occt_split_result_free`) returns the split shape and tables: per output face, its
    source face index, its piece index and inside flag (1, 0, or −1 when not classified), and its (element, side) pairs; per output
    edge, the source edge index or −1 and the cutter element or −1. Elements are numbered over curve pieces in input order, or are
    the cutter body's face indices; Swift turns them into `CutterName`s (a body face by its tags).
  - Swift names the result (R2) with the node's `tag` and orders `pieces` (R6).
  - `subSheet` (`occt_sub_sheet`) keeps the listed faces of `sheet` sharing their edges; each output face and edge maps to the same
    shape in `sheet`, whose tags it carries, so a cut edge between two pieces becomes a boundary edge already tagged `.cut`.
- Algorithm (the shim): refuse a closed solid ("Trim and Split take a sheet; this is a closed solid."); build the cutter (R7: a
  centred prism both ways for curves along a direction, refusing a zero direction "The direction can't be zero."; normal projection
  per face; the body itself); `BRepAlgoAPI_Splitter` (arguments: the sheet, tools: the cutter), polling cancellation; history
  `Modified` maps faces and edges back to the sheet's; a cut edge whose face lies on both its sides (it ends inside the face) is
  removed and warned; no face divided refuses "The cutter doesn't cut the surface."; a point inside each piece face (the face's UV
  box sampled 8 × 8, then 32 × 32, until `BRepClass_FaceClassifier` says IN) decides sides and inside (even-odd against each closed
  flat curve's polyline in its plane, projected along the direction, or along the plane's normal for normal projection; a direction
  lying in the curves' plane leaves `inside` nil; `BRepClass3d_SolidClassifier` for a closed solid); pieces are the connected sets of
  faces over uncut edges.
- Warning: "Part of the cutter doesn't cross the surface from edge to edge, so it cut nothing there."

- [ ] **Step 1: Tests** (fixtures: a 20 × 20 Planar Surface square at z = 0 centred on the origin; a circle of radius 5 at z = 5 as a
  curve; direction (0, 0, 1) unless said):
  - `aCircleCutsADisk`: 2 faces in `whole`, 2 pieces; `inside` is the disk; areas 25π and 400 − 25π (relative 1e-6).
  - `cutEdgesAreNamedByTheCutter`: the circle edge carries `TopoTag(tag, .boundary(.cut(.curve(index: 0, piece: 0))))`.
  - `piecesCarrySideTags`: the disk's tags are the square face's plus `.cutSide(.curve(index: 0, piece: 0), .inside)`; the ring's
    `.outside`.
  - `inputEdgesKeepTheirTags`: the four square edges keep their `.boundary(.piece(loop: 0, segment: k))` tags.
  - `aPickSurvivesTheCutterGrowing`: the disk's `facePick(for:)` at radius 5 matches exactly the disk (`faces(matching:)`) at radius 6.
  - `anOpenCurveCutsFrontAndBack`: a line from (−20, 0, 5) to (20, 0, 5) → the `.front` piece has centroid y < 0 (t × d = −y).
  - `aSheetCutterCuts`: a vertical sheet at x = 3 → two pieces named `.cutSide(.face(cutterTags), .front/.back)`; `inside == nil`.
  - `aClosedSolidCutterGivesInside`: a 4 × 4 × 4 box centred on the origin → `inside` is the 16 mm² square.
  - `alongNormalsOnACurvedSheet`: a lofted bump sheet and a circle of radius 3 projected along normals → 2 pieces, `inside` non-nil.
  - `aHoledProfileCutsAnAnnulusInside`: an outer circle radius 6 and a hole circle radius 3 (two curves) → `inside` is the annulus,
    area 27π.
  - `aDanglingCurveWarns`: the circle plus a line from (0, 0, 5) to (30, 0, 5) (ends inside) → split still made by the circle, the
    warning above; the line alone → "The cutter doesn't cut the surface."
  - `aMissingCutterRefuses`: a circle centred at (100, 100) → "The cutter doesn't cut the surface."
  - `aClosedSolidIsRefused`: a box as the sheet → "Trim and Split take a sheet; this is a closed solid."
  - `piecesAreConnectedSets`: a ruled Loft Surface of three open curves (2 faces) cut by one plane sheet across both → 2 pieces of 2
    faces, in R6 order.
  - `subSheetCarriesNames`: `subSheet([disk])` → one face with the disk's tags, its circle edge a boundary edge tagged `.cut`
    (`Topology.key(of:)` non-nil); `subSheet` of every face → the cut edge has two faces.
  - `aPeriodicSheetSplitsAcrossItsSeam` (backlog `into_face_range`): a 360° Revolve Curve sheet (radius 10, height 20) cut by a plane
    sheet at z = 10 → 2 pieces; `continuity(of: cut edge of piece A, in: A, against: piece B's face, of: B)` is `.g2`.
  - `cancellationStops`: a cancelled task throws `CancellationError`.
- [ ] **Step 2: Run** `swift test --filter SheetSplitTests`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter, `TwoBodyContinuityTests`, `TaggerTests` and `SheetPickTests`; pass.
- [ ] **Step 5: Commit** "NURBS: split sheets by curves or bodies".

### Task 5: Trim Surface and Split Surface nodes

**Files:**
- Create: `Sources/CreatorNodes/Surfaces/TrimSurfaceNode.swift`, `SplitSurfaceNode.swift`, `TrimCutterInput.swift` (the shared
  cutter reading), `TrimRegions.swift`
- Modify: `Sources/CreatorNodes/BuiltInNodes.swift`, `Sources/CreatorGraph/NodeDefinition.swift` (`previewHiddenOutputs`),
  `Sources/CreatorGraph/InspectorAction.swift` (`pickTrimRegions`, `clearTrimRegions`, with `break` arms where the compiler asks:
  Task 11 carries them out)
- Test: `Tests/CreatorNodesTests/TrimRegionsTests.swift`, `Tests/CreatorNodesTests/TrimSurfaceNodeTests.swift`,
  `Tests/CreatorNodesTests/OutputNodeTests.swift`

**Interfaces:**
- Consumes: Tasks 3 and 4.
- Produces:
  - `NodeDefinition.previewHiddenOutputs: Set<SocketName>` (default `[]`).
  - `creator.trimSurface`: inputs `surface` (`.solid`), `curves` (`.curve`, list, optional), `cutter` (`.solid`, optional),
    `projection` (integer, segmented "Along Direction" / "Along Normals", default 0), `direction` (vector, default (0, 0, 1), shown only
    along a direction via `inspector(for:)`), `keep` (integer, segmented "Picked" / "Inside" / "Outside", default 0); setting
    `keepRegions` (seeded `.facePicks([])`); outputs `surface` and `pieces` (`previewHiddenOutputs == ["pieces"]`). In Picked: a note
    "No regions picked" / "1 region picked" / "N regions picked" and the buttons "Pick regions in view…" (`.pickTrimRegions`) and
    "Clear regions" (`.clearTrimRegions`).
  - `creator.splitSurface`: inputs `surface`, `curves`, `cutter`, `projection`, `direction`; output `pieces` (`.solid`, list).
  - `TrimCutterInput.read(_ inputs: NodeInputs, node: String, kernel:, tag:) async throws -> TrimCutter`: curves through
    `CurveInput.loops(_, holes: .all, …)`; both wired → "<node> takes cutting curves or a cutting body, not both."; neither →
    "Wire curves or a body to cut with."
  - `TrimRegions.resolve(_ picks: [FacePick], in topology: Topology) -> (faces: [FaceID], warnings: [String])` (R4), pure.
- Wording (R4): "Pick the regions to keep; until then Trim Surface keeps every piece."; "A picked region now names 2 pieces; Trim
  Surface kept the one nearest where it was picked."; "A picked region no longer exists; pick the regions again."; refusal "None of
  the picked regions exist any more; pick the regions to keep again."; narrowed picks use `FacePickWording.merged("Trim Surface
  keeps")`, `.unnamed("trim")` and `.vanished(_:)`; Inside/Outside without a closed cutter: "Inside and Outside need a closed cutter:
  closed flat curves or a closed solid. Pick the regions to keep instead."

- [ ] **Step 1: Tests.**
  - `TrimRegionsTests` over hand-built `Topology` values: `aSingleMatchIsKept`; `aPickThatNamesTwoPiecesWarns` (keeps the one nearer
    the pick's centroid, the warning); `aVanishedPickWarns`; `noPicksMatchingIsARefusal` (the caller's refusal when `faces` is empty
    and picks were given); `aNarrowedPickIsKeptWithTheMergedWarning`.
  - `TrimSurfaceNodeTests` (OCCT-gated, graph-level through the real Evaluator): `insideKeepsTheDisk` (area 25π);
    `outsideKeepsTheRing`; `aPickedRegionIsKept`; `noPicksKeepsEverythingAndWarns`; `piecesOutputIsTheWholeSplit`;
    `aPickFollowsTheDiskWhenTheRadiusChanges` (Circle radius 5 → 6 upstream, the kept area is 36π); `insideNeedsAClosedCutter`;
    `curvesAndBodyRefuse`; `splitListsPieces` (two sheets in R6 order); `aProfileWithAHoleTrimsAnAnnulus` (a Circle profile with a
    hole wired into `curves`, Inside → area of the annulus); `piecesAreHiddenInPreview`.
  - `OutputNodeTests`: 106 nodes, `.surface` 16.
- [ ] **Step 2: Run** `swift test --filter 'TrimRegionsTests|TrimSurfaceNodeTests|OutputNodeTests'`; fail.
- [ ] **Step 3: Implement**, in the `.surface` category, library section "Edit".
- [ ] **Step 4: Run** the filter and `swift test --filter CreatorNodesTests`; pass.
- [ ] **Step 5: Commit** "NURBS: Trim Surface and Split Surface nodes".

### Task 6: Intersection Curves (kernel and node)

**Files:**
- Create: `Sources/COCCT/cocct_intersect.cpp`, `Sources/CreatorOCCT/OCCTKernel+Intersect.swift`,
  `Sources/CreatorNodes/Surfaces/IntersectionCurvesNode.swift`
- Modify: `Sources/COCCT/include/cocct.h`, `Sources/CreatorNodes/BuiltInNodes.swift`
- Test: `Tests/CreatorOCCTTests/IntersectionCurvesTests.swift`, `Tests/CreatorNodesTests/IntersectionCurvesNodeTests.swift`,
  `OutputNodeTests.swift`

**Interfaces:**
- Consumes: Task 3's requirement.
- Produces: `OCCTKernel.intersectionCurves(_:_:tag:)`: `BRepAlgoAPI_Section` (exact, no approximation), chained and ordered by R14,
  each wire a `Curve` through the existing curve-from-wire path (pieces in wire order); the same object twice refuses "Intersection
  Curves needs two different bodies."; no section is an empty list. `creator.intersectionCurves`: inputs `a`, `b` (`.solid`); output
  `curves` (`.curve`, list); empty → warning "The bodies don't meet, so there are no intersection curves."; library section "Curves".

- [ ] **Step 1: Tests.** `aPlaneThroughABoxGivesItsSquare` (a 10 mm box and a sheet at half height → one closed curve of 4 pieces,
  length 40 within 1e-6); `twoSheetsGiveAnOpenCurve` (two crossing Loft Surface sheets → one open curve, its start the smaller end);
  `disjointBodiesGiveNothing`; `aHoledBlockGivesTwoLoopsInOrder` (a box minus a cylinder cut by a sheet → the square first, then the
  circle, by R14); `orderIsStableUnderACommonMove` (both translated by (1, 1, 1) → the same order and lengths); the node:
  `theNodeListsCurves`, `noMeetingWarns`; `OutputNodeTests` 107, `.surface` 17.
- [ ] **Step 2: Run** `swift test --filter 'IntersectionCurves|OutputNodeTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter; pass.
- [ ] **Step 5: Commit** "NURBS: Intersection Curves".

### Task 7: Extend Surface (kernel and node)

**Files:**
- Create: `Sources/COCCT/cocct_extend.cpp`, `Sources/CreatorOCCT/OCCTKernel+Extend.swift`,
  `Sources/CreatorNodes/Surfaces/ExtendSurfaceNode.swift`
- Modify: `Sources/COCCT/include/cocct.h`, `Sources/CreatorNodes/BuiltInNodes.swift`
- Test: `Tests/CreatorOCCTTests/ExtendSurfaceTests.swift`, `Tests/CreatorNodesTests/ExtendSurfaceNodeTests.swift`,
  `OutputNodeTests.swift`

**Interfaces:**
- Consumes: Task 3's requirement; `make_edit_copy` and `replace_face_surface` (`cocct_control_net.hpp`, NS-3);
  `carryingTopology(of:from:source:operation:)`. `replace_face_surface` keeps pcurves as given, so Extend first moves the extended
  side's iso pcurve to its new value and widens the two neighbouring sides' pcurve ranges (their corner vertices moved to the new
  corners); the face's edges stay the same edges, in the same order.
- Produces: `OCCTKernel.extended(_:edges:length:mode:)` (R8). Sentences: "Extend Surface takes a sheet with one face; this one has
  3."; "Extend Surface takes a sheet; this is a closed solid."; "Only a sheet's open edges can be extended."; "Only an untrimmed edge
  can be extended; this edge is a trim."; "The length must be greater than 0 mm."; a missed join: "The extension isn't curvature
  continuous with the surface; use Linear." (Natural) or "The extension isn't tangent continuous with the surface." (Linear). Two
  picked edges on one side count once.
- `creator.extendSurface`: inputs `edges` (`.edgeSet`), `length` (number, mm, default 5), `mode` (segmented "Natural" / "Linear",
  default 0); output `surface`; inspector: the segmented control, `.ruleSummary("edges")`, "Pick edges in view…"
  (`.pickEdgesInView`); library section "Edit".

- [ ] **Step 1: Tests** (a smooth Loft Surface of three open curves, one face; its `.boundary(.end)` edge):
  `naturalGrowsTheEdge` (the new edge's midpoint is 5 ± 0.5 mm from the old one, area grows); `theOldSurfaceIsUnchanged` (25 points of
  the input face's display mesh lie on the result within 1e-7 by `shortestDistance`); `naturalIsCurvatureContinuous` (cut the result
  along the old edge with Task 4's `split` by a sheet made from the old edge (Curve from Edges, Extrude Curve along the face normal
  both ways) → `continuity(along:of:)` on the cut edge is `.g2`); `linearIsTangentAndStraight` (Linear on a curved sheet → the same
  cut grades at least `.g1`, and the new edge's midpoint lies on the old edge's tangent plane within 1e-6); `topologyIsKept`
  (`result.topology == input.topology`, so an Edges by Tag pick names the same edge); the refusals (a 2-face ruled loft, a box, a
  Planar Surface circle's edge, length 0); node: `theNodeExtends`, `OutputNodeTests` 108, `.surface` 18.
- [ ] **Step 2: Run** `swift test --filter 'ExtendSurface|OutputNodeTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `ControlNetTests`; pass.
- [ ] **Step 5: Commit** "NURBS: Extend Surface".

### Task 8: Matching an edge (kernel) and the two-body grade's sample rule

**Files:**
- Create: `Sources/COCCT/cocct_match.cpp`, `Sources/CreatorOCCT/OCCTKernel+Match.swift`
- Modify: `Sources/COCCT/include/cocct.h`, `Sources/COCCT/cocct_continuity.cpp` (R13), `Sources/COCCT/cocct_internal.hpp`
- Test: `Tests/CreatorOCCTTests/MatchSurfaceTests.swift`, `Tests/CreatorOCCTTests/TwoBodyContinuityTests.swift`

**Interfaces:**
- Consumes: Task 3's requirement, `make_edit_copy` and `replace_face_surface` (`cocct_control_net.hpp`), `edge_continuity_against`.
- Produces: `OCCTKernel.matched(_:edge:to:of:continuity:)` (R9), the result carrying the input's topology. Sentences: "Match Surface
  changes a sheet with one face; this one has 3."; "Match Surface takes a sheet; this is a closed solid."; "Match Surface changes an
  open edge of the sheet; this edge has two faces."; "Match Surface works on an untrimmed edge of its surface; this edge is a trim.";
  "The target edge must be on another body."; "The edges' ends are 0.8 mm apart; Match needs them to meet." (the larger end gap);
  a miss after refining: "Match couldn't make the edge curvature continuous with the target; it reached G1. Choose G1, or rebuild the
  surface with more spans." (G1 asked: "… tangent continuous with the target; it reached G0. …"; G0: "Match couldn't make the edge
  meet the target within 0.0001 mm.").
- The rows (the shim, our code), with s along the edge and r across it (r = 0 at the edge), after R9's degree raise and knot
  insertion, at each refinement level:

```text
row 0: least squares in the s-basis to C(σ(s)) at 4 × (poles) + 1 samples, end poles pinned to C's ends
row 1 (G1, G2): fit P1 − P0 so the cross derivative is m(s)·d(s): d the target face's continuation direction (unit, in its tangent
       plane, perpendicular to C', pointing away from the target face), m the sheet's cross speed before the match
row 2 (G2): fit P2 so S_rr's normal part is κ(s)·|S_r|²·N(s) (κ the target's normal curvature across the edge, N its oriented normal),
       its tangential part kept from before
measure edge_continuity_against(edge, sheet face, target face): pass when positionGap ≤ 1e-4 and grade ≥ requested;
       else insert a knot at the middle of every span along s and repeat (≤ 5 times, ≤ 100,000 poles)
```

- R13 in `cocct_continuity.cpp`: fewer than 24 of 32 usable samples throws `user_error("Too few points along the edge lie on the other
  face to grade it.")`.

- [ ] **Step 1: Tests.** Fixtures: A, a Loft Surface of the lines (0, 0, 0)–(0, 10, 0) and (10, 0, 0)–(10, 10, 0) (its
  `.boundary(.end)` edge on x = 10); B, a Revolve Curve sheet of the line (10, 0, 0)–(10, 10, 0) about the axis through
  (0, 0, 17.3205) along +y, 60°, turned so it leaves the edge along (cos 30°, 0, sin 30°) (G0 to A).
  `g1MakesTheEdgeTangent` and `g2MakesItCurvatureContinuous` (`continuity(of:in:against:of:)` of the result against B's face:
  grade ≥ requested, positionGap ≤ 1e-4); `g0MeetsAWavyTarget` (B replaced by a sheet whose start edge bulges 0.3 mm mid-span →
  positionGap ≤ 1e-4); `theOppositeEdgeStays` (A's start edge at 9 samples unchanged within 1e-9, G2); `topologyIsKept`;
  `endsApartRefuse` (B moved by (0, 0.8, 0) → the sentence with "0.8 mm"); `aTwoFaceEdgeRefuses`; `aTrimmedEdgeRefuses`;
  `aSolidTargetUsesTheContinuedFace` (target: an edge of a box whose top face continues A → graded ≥ G1 against that face);
  `aReversedEdgeIsPaired` (B's edge running −y → still G1); `aSteepMatchIsNotRefused` (B leaving at 150° → a valid result);
  `tooFewSamplesThrow` (TwoBody: an edge only a third of which lies on the other face → the R13 sentence).
- [ ] **Step 2: Run** `swift test --filter 'MatchSurfaceTests|TwoBodyContinuityTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `BoundaryPatchTests`, `EdgeContinuityOCCTTests`; pass.
- [ ] **Step 5: Commit** "NURBS: match an edge at G0, G1 or G2".

### Task 9: Blending two edges (kernel)

**Files:**
- Create: `Sources/COCCT/cocct_g2_skin.hpp` (the OCCT-free skinning lifted from `cocct_g2_strip.cpp`: `Spline`, `basis_at`, `solve`,
  `open_piece`, `interpolate_open`, `interpolate_periodic`), `Sources/COCCT/cocct_blend_surface.cpp`,
  `Sources/CreatorOCCT/OCCTKernel+BlendSurface.swift`
- Modify: `Sources/COCCT/cocct_g2_strip.cpp` (uses the header; behaviour unchanged), `Sources/COCCT/include/cocct.h`
- Test: `Tests/CreatorOCCTTests/BlendSurfaceTests.swift`

**Interfaces:**
- Consumes: Task 3's requirement, `cocct::g2::quintic_poles` and `circular_tangent_length`, `edge_continuity_against`.
- Produces: `OCCTKernel.blendSurface(_:_:tag:)` (R10, R12). Sentences: "Blend Surface joins at G1 or G2."; "The bulge must be from
  0.1 to 2."; "The edges touch; a blend needs a gap between them." (any section chord under 0.01 mm); misses after 129 sections: "The
  blend can't be made curvature continuous along these edges." (G2 on a side) / "The blend can't be made tangent continuous along
  these edges.".

- [ ] **Step 1: Tests.** Fixtures: A, a flat Loft Surface at z = 0 over x 0…10, y 0…10 (its edge on x = 10); B, the same at z = 10 over x
  20…30 (its edge on x = 20). `g1BlendIsTangentAtBothEnds` and `g2BlendIsCurvatureContinuous` (each side graded against its face:
  ≥ requested, positionGap ≤ 1e-4); `bulgeChangesTheShape` (0.5 against 1.5: the blend's midpoint moves more than 0.1 mm);
  `edgesAreNamed` (the face and four edges by R10); `aReversedEdgeIsPaired` (B's edge reversed → the same surface within 1e-6 at 9
  points); `edgesThatTouchRefuse`; `aSolidEdgeUsesTheFaceThatFacesTheOtherEdge` (a box's top edge against A → G1 graded against the
  box's top face); `cancellationStops`. Regression: the G2 fillet suites pass unchanged.
- [ ] **Step 2: Run** `swift test --filter BlendSurfaceTests`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `swift test --filter 'G2Fillet|LoftEnd'`; pass.
- [ ] **Step 5: Commit** "NURBS: blend two edges".

### Task 10: Match Surface and Blend Surface nodes

**Files:**
- Create: `Sources/CreatorNodes/Surfaces/MatchSurfaceNode.swift`, `BlendSurfaceNode.swift`
- Modify: `Sources/CreatorNodes/BuiltInNodes.swift`, `Sources/CreatorGraph/InspectorAction.swift` (`pickTargetEdgesInView`,
  `pickOtherEdgesInView`, `break` arms until Task 11)
- Test: `Tests/CreatorNodesTests/MatchBlendNodeTests.swift`, `OutputNodeTests.swift`

**Interfaces:**
- Consumes: Tasks 8 and 9; `EditSurfaceNode.foldWarning`.
- Produces:
  - `creator.matchSurface`: inputs `edges` (`.edgeSet`), `target` (`.edgeSet`), `continuity` (segmented "G0" / "G1" / "G2", default
    1); output `surface`; inspector: the segmented control, `.ruleSummary("edges")`, "Pick edge in view…" (`.pickEdgesInView`),
    `.ruleSummary("target")`, "Pick target edge in view…" (`.pickTargetEdgesInView`). Each set must hold one edge: "Match Surface takes
    one edge to change; “edges” gives 3." / "… one target edge; “target” gives 2." A fold warns `EditSurfaceNode.foldWarning` (not
    while scrubbing).
  - `creator.blendSurface`: inputs `edges`, `other edges` (`.edgeSet`), `continuity` and `other continuity` (segmented "G1" / "G2",
    default 0, mapped to `.g1` / `.g2`), `bulge` and `other bulge` (number 0.1 to 2, default 1); output `surface`; inspector with both
    rule summaries and "Pick edge in view…" / "Pick other edge in view…" (`.pickOtherEdgesInView`). "Blend Surface takes one edge on
    each side; “edges” gives 3."
  - R11 on both: `readsScrubbing(for:)` true only when a G2 is chosen; under `context.isScrubbing` the G2 sides build as G1 with no
    warnings.
  - Library section "Edit".

- [ ] **Step 1: Tests** (OCCT-gated, graph-level, Task 8 and 9 fixtures): `matchNodeMatches`; `matchCountsEdges`;
  `matchBuildsG1WhileScrubbing` (an `EvalContext` with `isScrubbing` → graded G1 not G2, no warnings; `readsScrubbing(for:)` false at
  G1, true at G2); `blendNodeBlends`; `blendTakesOneEdgeEachSide`; `blendBuildsG1WhileScrubbing`; `OutputNodeTests` 110, `.surface` 20.
- [ ] **Step 2: Run** `swift test --filter 'MatchBlendNodeTests|OutputNodeTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `swift test --filter CreatorNodesTests`; pass.
- [ ] **Step 5: Commit** "NURBS: Match Surface and Blend Surface nodes".

### Task 11: Picks in the app (trim regions, target and other edges, hidden pieces)

**Files:**
- Create: `Sources/CreatorApp/AppModel+TrimRegions.swift`
- Modify: `Sources/CreatorApp/PickSession.swift` (`trimRegions: NodeID?`, `pickedFaces: [FaceID]`, `Prompt.trimRegions`),
  `AppModel+Picking.swift` (`beginPick(for:socket:)`, routing the four new actions, region clicks, Done), `AppModel+Scene.swift`
  (a region pick's item shows `selectedFaces`), `SceneBuilder.swift` (skips `previewHiddenOutputs`), `Sources/CreatorGraph/UndoName.swift`
  (`pickTrimRegions = "Pick Trim Regions"`, `clearTrimRegions = "Clear Trim Regions"`), `Sources/CreatorEditor/EditorModel+Inspector.swift`
- Test: `Tests/CreatorAppTests/TrimRegionPickTests.swift`, `Tests/CreatorAppTests/SecondEdgePickTests.swift`

**Interfaces:**
- Consumes: Tasks 5 and 10; `TrimRegions.resolve`, `Topology.facePick(for:)`.
- Produces: `AppModel.beginTrimRegionPick(for: NodeID)`, `AppModel.clearTrimRegions(of: NodeID)`, `AppModel.beginPick(for:socket:)`.
- Behaviour: the region pick shows the Trim node's `pieces` sheet alone, starting from the faces its current picks resolve to; a click
  on a face toggles it; Done writes `.facePicks` (each face's `facePick(for:)`, in face order) to `keepRegions` as one step "Pick Trim
  Regions" and selects the node; Cancel changes nothing; the banner reads "Click the regions to keep · N picked". Refusals: inside a
  group "A region can't be picked inside a group yet. Pick it from the top level."; no pieces "“<node>” has no pieces to pick yet: wire a
  sheet and a cutter first."; refused while control points are being edited (as every pick is). Clear is one step "Clear Trim Regions".
  The two edge actions pick for sockets "target" and "other edges" as Fillet's button does for "edges".

- [ ] **Step 1: Tests:** `pickRegionsShowsTheWholeSplit`; `clickingTogglesARegion`; `doneWritesFacePicksAsOneStep` ("Undo Pick Trim
  Regions"; the setting holds the picks; the kept area follows); `cancelLeavesTheGraph`; `clearRegionsIsOneStep`;
  `insideAGroupIsRefused`; `noPiecesRefuses`; `refusedWhileEditingControlPoints`; `pickTargetEdgeWiresARuleIntoTarget` (Match: Done adds
  an Edges by Tag rule wired from B into `target`); `pickOtherEdgeWiresARuleIntoOtherEdges` (Blend); `piecesAreNotDrawnInPreview` (a
  selected Trim shows one item, the kept surface).
- [ ] **Step 2: Run** `swift test --filter 'TrimRegionPickTests|SecondEdgePickTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `swift test --filter CreatorAppTests`; pass.
- [ ] **Step 5: Commit** "NURBS: trim region and second edge picks".

### Task 12: Docs and the suites

**Files:**
- Modify: `CLAUDE.md` (an NS-4 paragraph after NS-3's: the six nodes, the kernel calls and shim files, R1 to R16, format 16, 110
  nodes and `.surface` 20, the R2 cost, the parked items; the NS-3 paragraph's tolerance sentences updated to 1e-6 and the
  partial periodic Rebuild), `docs/verification/human-checks.md` (group NS-4: trim a disk out of a sheet and change the circle's
  radius; pick regions and undo; Inside on a holed profile; split a revolved sheet and zebra-check the pieces; extend Natural and
  Linear and compare stripes; match G1 and G2 and read Measure's continuity row; blend two sheets at G2 with two bulges; drag a slider
  upstream of a G2 blend and see it build at G1 while dragging; an apex typed as one point), the spec's status line ("NS-4 done
  (2026-11-18; human checks group NS-4 pending; R1: the nodes are named … Surface; R2: pieces are named by cutter element and side)").
  No benchmark rows: the spec names none for NS-4.
- [ ] **Step 1:** docs.
- [ ] **Step 2:** `swift test` on macOS (14 "Test run with" lines, no "recorded an issue" or "failed after"); `XP_TRACK=ns-4
  scripts/linux-test.sh test` (14 lines; afterwards remove only the Docker volume this run made); `swiftlint lint --strict` 0.
- [ ] **Step 3: Commit** "Docs: NS-4".
