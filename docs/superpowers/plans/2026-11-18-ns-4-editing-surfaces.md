# NS-4: Editing surfaces — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trim Surface, Split Surface, Intersection Curves, Extend Surface, Match Surface and Blend Surface, the naming and file
format that keep picks on their results from drifting, the viewport picks they need, and the owed NS-3 follow-up.

**Architecture:** One kernel call (`Kernel.split`) cuts a sheet by curves (projected) or a body with OCCT's `BRepAlgoAPI_Splitter`
and names every piece by the cutter elements it borders and the side it lies on (`TopoRole.cutSide`), and every cut edge by its
cutter element (`BoundaryRole.cut`); Trim and Split choose pieces from that one result. Extend and Match change one untrimmed
face's B-spline in place on a copy (NS-3's `replace_face_surface` path), so every tag and the adjacency are the input's. Blend
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
- **Picks don't drift:** Extend Surface and Match Surface keep the input's tags and adjacency (`carryingTopology`): the same
  faces and edges in the same order, `faces.map(\.tags)`, `edges.map(\.tags)` and `edges.map(\.faces)` equal to the input's (as
  `RebuildTests.aTrimmedFaceKeepsItsTrim` compares). The measured geometry in the tables (`FaceInfo` area, centroid and normal,
  `EdgeInfo` length and midpoint) changes with the surface, so tests never compare whole `Topology` values. Trim and Split name
  pieces and cut edges by R2.
- **Separate sheets** (spec §Joining a part): Blend Surface outputs a new sheet; nothing is sewn into a part.
- **Limits:** at most 100,000 control points per surface; every limit and refusal is a full sentence, numbers through
  `Locale.messages` (`Double.display`, `Int.display`).
- **Cancellation** is asked between sections, curves, refinement passes and splitter stages (`occt_cancel`, as
  `networkSurface` polls it).
- **File format 16** (`GraphFile.currentFormatVersion`): `ConstantValue.regionPicks`, `TopoRole.cutSide` and `BoundaryRole.cut` in
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
  side; reordering the cutter curves, or inserting or removing one before another, shifts `.curve(index:)` and renames every piece
  bordered by the shifted curves, so their keep picks vanish (warned, never a silent swap); closed cutters wired in a fixed order
  (the common hole) are immune. Documented in CLAUDE.md and the human checks. R2 does not make every piece's name unique: pieces
  bordered by the same elements on the same sides share one tag set (a circle crossing a strip leaves two `.outside` pieces both
  named {source, cutSide(c0, outside)}; an open curve crossing a face twice does the same). R17 says how picks live with that.
- **R3. Format 16** for R2's two roles and the `regionPicks` kind (older readers can't decode them).
- **R4. Trim's `keep`** is Picked (default), Inside or Outside. Picked with no picks keeps every piece and warns. **The unit of
  keep is a piece** (a connected set of faces, `SheetSplit.pieces`), never a lone face, because the spec keeps "picked regions" and
  one region of a multi-face sheet (a two-face ruled loft, a sweep along a polyline) spans several faces. Each pick resolves to faces
  (its matches, or the narrowed part by `Topology.resolution(of:)`, warned in `FacePickWording`'s words), each face maps to the piece
  holding it, and the pick keeps one piece: its single piece, or, when it names more pieces than R17's `sharedBy`, the piece whose
  area-weighted centroid is nearest the pick's recorded centroid (warned); a pick naming nothing warns; all picks naming nothing is
  a refusal. The kept sheet is `subSheet` of the kept pieces' faces. Inside and Outside are even-odd over the cutter's closed flat
  curves (classified in the curves' plane along the projection) or the closed solid's inside, keep every piece whose faces are all
  inside (outside), and are refused for any other cutter. Why: deterministic, never silent.
- **R5. Trim has a second output, `pieces`:** the whole split as one sheet (every piece, cut edges shared). It is what keep picks
  name and what "Pick regions in view…" shows; the node lists it in `NodeDefinition.previewHiddenOutputs`, so a selected Trim
  shows only the kept surface. Cost: one more output to explain; the alternative (the app re-running the split) duplicates the
  node's input reading.
- **R6. Split Surface's list** holds one sheet per connected piece (faces joined across uncut edges), ordered by the canonical sort
  key of the piece's smallest face tag set (tag `sortKey`s sorted and joined by "+"), ties by centroid x, then y, then z. Pieces
  that share a name (R2) are therefore ordered by centroid alone, so moving one past the other swaps their places in the list.
- **R7. Projection.** Along a direction d the cutter is the curves' prism (`BRepPrimAPI_MakePrism`), each prism face named
  `.curve(index:piece:)` through the prism's `Generated` history. Its extent along d is taken from the union of the curves' and the
  sheet's bounds, so projection never depends on how far the curves are from the sheet: with `[s₀, s₁]` the sheet's range of
  `p · d̂`, `c₁` the curves' largest `p · d̂` and `c₀` their smallest, and the margin `m = 1 mm + 1 %` of `(max(s₁, c₁) − min(s₀, c₀))`,
  the curves are moved by `(s₀ − m − c₁) d̂` and swept by `(s₁ + m − c₀ − (s₀ − m − c₁)) d̂`, so every curve point's line along d
  passes the whole sheet. Along normals, `BRepOffsetAPI_NormalProjection` puts edges on the faces. Both are cut with
  `BRepAlgoAPI_Splitter`. Why not the spec's `BRepProj_Projection`: it returns projected wires, not a cutting tool; a prism of
  faces is something the splitter's Boolean intersects exactly, its `Generated` history names each cut edge by its curve piece, and
  it takes the same splitter path as a body cutter (one naming code, R2). A cutter part that doesn't divide a face (it ends inside
  it) is dropped with a warning; no division at all is a refusal.
- **R8. Extend Surface** takes a sheet of one face and edges that are untrimmed iso-boundaries of its (converted) B-spline surface.
  Natural is `GeomLib::ExtendSurfByLength` with continuity 2 (it extends a rational surface in homogeneous coordinates). Linear is
  ours: one span appended across the edge whose poles lie evenly on the line from each boundary pole along `P0 − P1` (the cross
  tangent), scaled so the extension at the edge's middle pole is `length` (it varies where the cross speed varies). Linear needs a
  non-rational net: a rational surface (Revolve Curve's, a converted cylinder's) is first approximated by a non-rational one over
  the same parameter domain (`GeomConvert_ApproxSurface`, 1e-7 mm, C2, degree ≤ 9), refused when it can't reach that: "This
  surface can't be extended Linear exactly; use Natural.". The face keeps its edges, so tags and adjacency are the input's.
  **Parameters:** `ExtendSurfByLength` may raise the degree, re-knot or rescale the old domain, so after either mode the map from
  old to new parameters is found per direction (affine, from the knots, then checked: 25 points of the old surface at their mapped
  parameters within 1e-7 mm, else "The extension moved the surface; this edge can't be extended.") and applied to **every** pcurve
  of the face (both seam pcurves of a periodic face included), not only the extended side's; the extended side's pcurve then moves
  to the new iso value and its two neighbours' ranges widen to the new corners. A direction that was periodic and is no longer
  periodic after the extension keeps its seam edge, now a closed seam on a non-periodic surface whose two pcurves are the two iso
  lines `u₀` and `u₀ + period` of the mapped range; the result is held to `BRepCheck_Analyzer`. The join is graded across the old
  iso line at 32 samples (G2 Natural, G1 Linear) and refused on a miss. Cost: Extend on a multi-face or trimmed sheet is refused
  (parked).
- **R8 erratum (Task 7).** Linear does **not** approximate a rational surface. It appends the span in homogeneous coordinates (the
  weights extended linearly with the poles, so a rational net is extended exactly and the old surface is untouched); where the weights
  would fall below 1e-3 of the last weight the edge is refused: "This edge can't be extended Linear: the surface weakens too fast
  across it; use Natural." in place of "This surface can't be extended Linear exactly; use Natural." (also "... the surface doesn't run
  across it; use Natural." for a zero cross speed). The appended knot span is `last span x factor / degree`, so the parametric speed across
  the join is continuous (C1 in parameter), not only the tangent plane. Both modes are calibrated until the distance between the old
  and new edge's middle points is `length` (once for Linear, which is linear in its scale; by correction for Natural), and the join is
  graded after the build: a knot that cannot be found where the map says is refused with the "moved" sentence, never passed unmeasured.
  Tasks 8 and 9 and the spec read R8 with this.
- **R9. Match Surface** changes a sheet of one face along an untrimmed iso edge, to one target edge. Rows 0..c (c = continuity) move;
  the cross degree is raised to at least c + 1 and knots inserted in the first cross span until there are at least c + 2 rows, so
  the opposite edge never moves. The target is reparametrised by arc-length fraction from the end nearer the edge's start. A solid
  target edge has two faces: the one whose outward cross direction at the target's midpoint (the direction leaving that face across
  the edge) best agrees with the sheet's inward cross direction (from the edge into the sheet) is matched. Refinement doubles the
  spans along the edge up to 5 times (or to 100,000 poles), then refuses naming the grade it reached. Ends more than 0.01 mm apart
  refuse in the spec's words. Never refused for being ugly; a fold warns. **Rational sheets** (Revolve Curve's, converted cylinders
  and circles) are matched exactly with their weights held fixed: degree raising and knot insertion are exact in homogeneous
  coordinates, and with every weight fixed `S = Σ wᵢⱼ Nᵢⱼ Pᵢⱼ / Σ wᵢⱼ Nᵢⱼ` is linear in the poles, as are its r-derivatives, so
  each row's fit below is a linear least-squares problem in the rational basis `Rᵢⱼ = wᵢⱼ Nᵢⱼ / W` and its r-derivatives (for a
  non-rational net, all weights 1, it is the plain basis); the moved rows keep their weights. The pole rows of the fit are only
  those whose basis functions or their first c r-derivatives are non-zero at r = 0 (rows 0..c of a clamped edge), so the opposite
  edge still never moves.
- **R10. Blend Surface** takes one edge on each side (a sheet's or a solid's). A solid edge uses the face whose outward cross
  direction at the edge's midpoint (the direction leaving that face across the edge) points most toward the other edge's midpoint.
  The second edge is reversed when that makes the sum of end-to-end distances smaller. Section k joins the points at the same
  arc-length fraction `k / (n − 1)` from the paired starts of the two edges (as R9 reparametrises the target). The two edges may be
  edges of one body (a sheet of two faces, or two free edges of one face); the same edge twice refuses "Blend Surface needs two
  different edges.". Each section is `quintic_poles` with tangent length `bulge × circular_tangent_length`;
  a G2 end takes the face's normal curvature as acceleration, a G1 end zero acceleration (so G1 and G2 differ). Sections start at
  9, skinned cubic, then quintic, doubling to at most 129, as the G2 fillet strips do (their skinning moves to
  `cocct_g2_skin.hpp`, unchanged). Naming as Network Surface's R6: face `.side(loop: 0, segment: 0)`, first edge
  `.boundary(.start)`, second `.boundary(.end)`, sides `.boundary(.rail(0))` (from the first edge's start) and `.rail(1)`.
- **R11. Scrubbing.** Match Surface and Blend Surface asked for G2 build at G1 while `context.isScrubbing`, with no warnings, and
  `readsScrubbing(for:)` is true only when G2 is chosen (the G2 fillet's rule), so a drag stays fast and the G2 build follows.
  Match's fold check follows the same line: at G0 and G1 it **always** runs, scrubbing or not, because a G0/G1 node's cache key has
  no `isScrubbing` and its last drag step's result is the one kept after the release (a skipped check would never warn); at G2 it is
  skipped only for the G1 stand-in built while scrubbing, and the G2 build after the release, under its own key, runs it. Why not
  Edit Surface's "always reads scrubbing": Match re-runs its whole fit and grade on every drag step anyway, so the fold query is a
  small part of a step, and keeping G0/G1 cached across drags elsewhere is worth more. Cost if wrong: a G0/G1 match drag is slower
  by one fold query per step.
- **R12. Continuity type.** Match and Blend reuse `PatchContinuity` (G0/G1/G2); Blend refuses `.g0` ("Blend Surface joins at G1 or
  G2.") though its control offers only G1 and G2.
- **R13. Two-body grade needs most samples** (backlog item), in bands of `used` (usable samples of 32) in `grade_samples`'s two-body
  branch: 0 to 15 (none, or under half) keeps today's "The edge doesn't run along that face." (pinned by
  `TwoBodyContinuityTests.aFaceOnTheSamePlaneBeyondItsBoundaryIsRefused` and `aFaceElsewhereIsRefused` and the doc comment of
  `Kernel.continuity(of:in:against:of:)`, all unchanged); 16 to 23 throws the new "Too few points along the edge lie on the other face
  to grade it."; 24 or more grades. So a G2 grade can't rest on half an edge, and an edge that misses the face still reads as one.
  The doc comment gains the middle band. Boundary Patch grades its patch edges with this call (`OCCTKernel+Patch.swift`), so its
  suites are rerun.
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
- **R17. Picks of pieces that share a name** (R2's gap). A Trim keep pick is a `RegionPick`: the `FacePick` (tags, normal,
  centroid) plus `sharedBy`, the number of pieces its tags named in the split it was picked on (1 when it named its piece alone).
  `TrimRegions.resolve` warns "A picked region now names N pieces; …" only when a pick names more pieces than its `sharedBy`; when
  it names `sharedBy` or fewer (but at least one) it keeps the piece nearest its recorded centroid without a warning, because nothing
  changed that the user can act on. So a keep pick on either `.outside` piece of a band cut picks cleanly and still follows the
  circle's radius. Why not make names unique (adding the bordering input edges' tags to piece faces): a face carrying edge roles
  confuses `Topology.key` and edge picks, and on a periodic sheet two pieces can border the same input edges anyway. Cost: between
  pieces that share a name the choice is geometric, so a cutter change that moves one such piece past the other's old centroid can
  swap them silently; documented beside R2's cost.

- **R9 erratum (Task 8).** Match Surface raises the along degree to at least 3, which is exact for the edge it follows, and refuses a
  periodic (closed) edge: "Match Surface can't match an edge of a surface that closes on itself yet."

**Backlog (`nurbs-backlog-after-ns2` memory).** Pulled in: the NS-3 follow-up (R16, Tasks 1 and 2), the partial periodic Rebuild
(Task 1), the two-body half-sample grade (R13, Task 8), `into_face_range`'s periodic remap test (Task 4). Parked: the guide
sweep's fixed 1e-3 mm tolerance and multi-face guide edges; Network Surface's tolerance against arc approximations; the G2
Boundary Patch limits; twist parallel transport; the `unsupported` sentence's grammar (NS-4's names are gerunds); the fold
check's false positives; `extraDemand` reference counting; cancelling superseded net reads; the theme editor's Esc; the closed
degree-3 Curve through Points' C1 seam. New parked items from this plan: Extend on multi-face or trimmed sheets, Match on trimmed
edges, Match on closed (periodic) edges, chains of edges for Match and Blend, unique names for pieces that share a tag set (R17).

## Review Focus

1. **A cutter that only partly crosses the sheet** (a curve ending inside a face): that part is dropped with the warning, the rest
   still cuts; nothing cut is a refusal, never an unchanged sheet passed off as trimmed. Task 4 (`aDanglingCurveWarns`).
2. **A keep pick after the cutter moves** (the picked piece splits in two, or vanishes): Trim keeps one piece deterministically and
   warns, never silently the other side; a pick on one of two pieces that share a name (R17) keeps its piece without a false
   warning, and a pick on a multi-face region keeps the whole region (R4). Task 5 (`aPickThatNamesTwoPiecesWarns`,
   `aVanishedPickWarns`, `aBandCutLeavesTwoOutsidePiecesThatPickCleanly`, `aPickKeepsItsWholePiece`).
3. **Trimming a closed (360°) sheet across its seam:** the pieces are right and grading on the trimmed periodic face works
   (`into_face_range`). Task 4 (`aPeriodicSheetSplitsAcrossItsSeam`).
4. **Match or Blend against a solid's edge** (two faces) **or a target running the other way:** the face and direction are chosen
   by R9 and R10 and the result grades as promised. Tasks 8 and 9 (`aSolidTargetUsesTheContinuedFace`, `aReversedEdgeIsPaired`).
5. **A slider dragged upstream of a G2 Match or Blend:** G1 while dragging, no stale warning, the G2 build after; never a G2 claim
   on a G1 surface; a G0/G1 Match dragged into a fold still warns after the release (R11). Task 10 (`matchBuildsG1WhileScrubbing`,
   `blendBuildsG1WhileScrubbing`, `aG1FoldWarnsAfterADrag`).

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
  `Sources/CreatorKernel/TopoRole+NestedTags.swift`, `Sources/CreatorKernel/RegionPick.swift`
- Modify: `Sources/CreatorKernel/BoundaryRole.swift`, `TopoRole.swift`, `TopoRole+Codable.swift`, `TopoRole+Stability.swift`,
  `TopoTag+Item.swift`, `TopoTag+Instance.swift`, `Kernel.swift` (requirements and refusing defaults),
  `Sources/CreatorGraph/Groups/ConstantValue+TagRenaming.swift` (and `GroupScopes+PickRenaming.swift` where it lists pick kinds),
  `Sources/CreatorGraph/ConstantValue.swift`, `NodeSetting.swift`,
  `GraphFile.swift`, and every exhaustive `switch` the compiler names (`Scalar.swift`, `InspectorBuilder.swift`,
  `CreatorMCP/Tools/ReadTools+Values.swift`)
- Test: `Tests/CreatorKernelTests/CutNamingTests.swift`, `Tests/CreatorGraphTests/RegionPicksFileTests.swift`

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
  - `RegionPick.swift` (R17): `public struct RegionPick: Hashable, Sendable { public var pick: FacePick; public var sharedBy: Int }`
    (`sharedBy` ≥ 1; JSON `{"pick": <FacePick as saved today>, "sharedBy": n}`, `sharedBy` written only when greater than 1 and read
    as 1 when missing).
- Produces (CreatorGraph): `ConstantValue.regionPicks([RegionPick])` (Codable kind `regionPicks`; always finite; named apart from
  the existing single `ConstantValue.facePick`); `NodeSetting.keepRegions: SocketName = "keepRegions"`, in `all` only, **not** in
  `reservedForSockets` (only Trim Surface has it, so by `NodeSetting.swift`'s convention for `poleMoves`, `startFace`, `image` and
  the file settings, an older file with a group socket or exposed dimension of that name keeps working; its doc comment gains
  `keepRegions` in the list); `GraphFile.currentFormatVersion == 16`; group renaming (`ConstantValue+TagRenaming`, so
  `EvaluationScope.naming` and `GroupScopes.renamingPicks`) renames the `FacePick` in every `RegionPick`, keeping `sharedBy`.

- [ ] **Step 1: Tests.**
  - `cutSideRoundTrips`: `.cutSide(.curve(index: 1, piece: 2), .inside)` and `.cutSide(.face([a, b]), .front)` encode and decode
    equal; `sortKey` of the first is `"cutSide(curve(1:2):inside)"`.
  - `cutEdgeRoundTrips`: `.boundary(.cut(.curve(index: 0, piece: 0)))`, sortKey `"boundary(cut(curve(0:0)))"`.
  - `nestedTagsAreRenamed`: a `.cutSide(.face([t]))` tag → `withItem(5)` gives the nested `t.item == 5`; `qualified` qualifies it;
    `isUnstable` is true when `t` is `.unnamed`; group renaming of a `regionPicks` value renames nested tags and keeps `sharedBy`.
  - `regionPicksRoundTrip` (with `sharedBy` 1, written without the key, and 2), `aFormat15FileOpens` (an existing format-15 fixture
    decodes), `theFormatIs16`, `keepRegionsIsNotReserved` (`keepRegions` is in `NodeSetting.all` and not in `reservedForSockets`; a
    group socket named "keepRegions" is accepted, as `PoleMovesFileTests` asserts for `poleMoves`).
  - `fakeKernelRefusesTheNewCalls`: each of the six calls on `FakeKernel` throws `.unsupported` with its name.
- [ ] **Step 2: Run** `swift test --filter 'CutNamingTests|RegionPicksFileTests'`; compile failure.
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
  prism along the direction sized and placed from the union of the curves' and the sheet's extents along it, refusing a zero
  direction "The direction can't be zero."; normal projection
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
  - `aDistantCurveStillCuts` (R7): the circle at z = 100, then at z = −250 → the same 2 pieces and the same disk area as at z = 5;
    a circle at z = 5 with direction (0, 0, −1) cuts the same disk.
  - `aBandCutLeavesTwoOutsidePiecesWithOneName` (R2's documented gap): a 20 × 6 strip (x −10…10, y −3…3) cut by the circle → 3
    pieces; the two `.outside` pieces have equal tag sets and R6 orders them by centroid (x < 0 first).
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
    `keepRegions` (seeded `.regionPicks([])`); outputs `surface` and `pieces` (`previewHiddenOutputs == ["pieces"]`). In Picked: a note
    "No regions picked" / "1 region picked" / "N regions picked" and the buttons "Pick regions in view…" (`.pickTrimRegions`) and
    "Clear regions" (`.clearTrimRegions`).
  - `creator.splitSurface`: inputs `surface`, `curves`, `cutter`, `projection`, `direction`; output `pieces` (`.solid`, list).
  - `TrimCutterInput.read(_ inputs: NodeInputs, node: String, kernel:, tag:) async throws -> TrimCutter`: curves through
    `CurveInput.loops(_, holes: .all, …)`; both wired → "<node> takes cutting curves or a cutting body, not both."; neither →
    "Wire curves or a body to cut with."
  - `TrimRegions.resolve(_ picks: [RegionPick], pieces: [[FaceID]], in topology: Topology) -> (pieces: [Int], warnings:
    [String])` (R4, R17), pure: the indices into `pieces` to keep, sorted and without repeats (two picks of one piece keep it once);
    the node keeps `subSheet` of the union of their faces. A piece's centroid is its faces' `FaceInfo.centroid` weighted by area.
  - `TrimRegions.pick(forPiece: Int, pieces: [[FaceID]], in topology: Topology) -> RegionPick?`: the `RegionPick` Task 11 writes for a
    kept piece: `facePick(for:)` of the piece's face with the smallest tag-set sort key (R6's key), and `sharedBy` the number of
    pieces that pick names in this split.
- Wording (R4): "Pick the regions to keep; until then Trim Surface keeps every piece."; "A picked region now names 2 pieces; Trim
  Surface kept the one nearest where it was picked."; "A picked region no longer exists; pick the regions again."; refusal "None of
  the picked regions exist any more; pick the regions to keep again."; narrowed picks use `FacePickWording.merged("Trim Surface
  keeps")`, `.unnamed("trim")` and `.vanished(_:)`; Inside/Outside without a closed cutter: "Inside and Outside need a closed cutter:
  closed flat curves or a closed solid. Pick the regions to keep instead."

- [ ] **Step 1: Tests.**
  - `TrimRegionsTests` over hand-built `Topology` values: `aSingleMatchIsKept`; `aPickThatNamesTwoPiecesWarns` (`sharedBy` 1, now
    names 2: keeps the one nearer the pick's centroid, the warning); `aPickSharedWhenMadeDoesNotWarn` (`sharedBy` 2, names 2: the
    nearer piece, no warning); `aPickNamingMorePiecesThanWhenMadeWarns` (`sharedBy` 2, names 3); `aPickKeepsItsWholePiece` (a piece
    of two faces; the pick matches one → the piece index, both faces kept); `twoPicksOfOnePieceKeepItOnce`; `aVanishedPickWarns`;
    `noPicksMatchingIsARefusal` (the caller's refusal when `pieces` is empty and picks were given);
    `aNarrowedPickIsKeptWithTheMergedWarning`; `pickForPieceRecordsSharedBy` (1 for the disk, 2 for an `.outside` piece of a band).
  - `TrimSurfaceNodeTests` (OCCT-gated, graph-level through the real Evaluator): `insideKeepsTheDisk` (area 25π);
    `outsideKeepsTheRing`; `aPickedRegionIsKept`; `noPicksKeepsEverythingAndWarns`; `piecesOutputIsTheWholeSplit`;
    `aPickFollowsTheDiskWhenTheRadiusChanges` (Circle radius 5 → 6 upstream, the kept area is 36π); `insideNeedsAClosedCutter`;
    `curvesAndBodyRefuse`; `splitListsPieces` (two sheets in R6 order); `aProfileWithAHoleTrimsAnAnnulus` (a Circle profile with a
    hole wired into `curves`, Inside → area of the annulus); `piecesAreHiddenInPreview`;
    `aBandCutLeavesTwoOutsidePiecesThatPickCleanly` (Task 4's band: a pick written by `TrimRegions.pick(forPiece:)` for the x < 0
    outside piece keeps it with no warning; after the radius goes 5 → 4 it still keeps the x < 0 piece, no warning);
    `aPickKeepsTheWholeRegionOfAMultiFaceSheet` (Task 4's two-face ruled loft cut by the plane sheet: a pick on one face of a piece
    keeps both its faces, area of the piece); `aPickSurvivesGroupingAndTwoInstances` (naming through groups: Planar Surface, Circle
    and a Trim with a disk pick at the top level are grouped by `GroupCommands` with the radius exposed (`GroupScopes.renamingPicks`
    renames the pick into the definition), then a second group node uses the same definition; radii 5 and 6 → the instances keep
    disks of 25π and 36π, no warnings, each read through `EvaluationScope.naming` over the `regionPicks` setting).
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
  `carryingTopology(of:from:source:operation:)`. `replace_face_surface` keeps pcurves as given, so Extend first remaps every pcurve
  of the face through R8's old-to-new parameter map (both seam pcurves of a periodic face included), then moves the extended side's
  iso pcurve to its new value and widens the two neighbouring sides' pcurve ranges (their corner vertices moved to the new corners);
  the face's edges stay the same edges, in the same order.
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
  (`faces.map(\.tags)`, `edges.map(\.tags)` and `edges.map(\.faces)` equal the input's, so an Edges by Tag pick names the same
  edge; areas and lengths are not compared); `aRevolvedSheetExtends` (a 90° Revolve Curve sheet of a line, rational: Natural grades
  `.g2` at the old line and `topologyIsKept`'s three tables hold; Linear grades ≥ `.g1` through the non-rational approximation);
  `aPeriodicSheetsEndExtends` (a 360° Revolve Curve sheet, radius 10, height 20: its top end edge extended 5 mm in both modes → valid
  (`BRepCheck_Analyzer`), the seam edge still has the face on both sides, the old line grades as promised, every pcurve, both seam
  pcurves included, lies on the new surface within 1e-7 at 9 samples, and the bottom edge is unchanged within 1e-9); the refusals (a
  2-face ruled loft, a box, a Planar Surface circle's edge, length 0); node: `theNodeExtends`, `OutputNodeTests` 108, `.surface` 18.
- [ ] **Step 2: Run** `swift test --filter 'ExtendSurface|OutputNodeTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `ControlNetTests`; pass.
- [ ] **Step 5: Commit** "NURBS: Extend Surface".

### Task 8: Matching an edge (kernel) and the two-body grade's sample rule

**Files:**
- Create: `Sources/COCCT/cocct_match.cpp`, `Sources/CreatorOCCT/OCCTKernel+Match.swift`
- Modify: `Sources/COCCT/include/cocct.h`, `Sources/COCCT/cocct_continuity.cpp` (R13), `Sources/COCCT/cocct_internal.hpp`,
  `Sources/CreatorKernel/Kernel.swift` (the doc comment of `continuity(of:in:against:of:)` gains R13's middle band)
- Test: `Tests/CreatorOCCTTests/MatchSurfaceTests.swift`, `Tests/CreatorOCCTTests/TwoBodyContinuityTests.swift`

**Interfaces:**
- Consumes: Task 3's requirement, `make_edit_copy` and `replace_face_surface` (`cocct_control_net.hpp`), `edge_continuity_against`.
- Produces: `OCCTKernel.matched(_:edge:to:of:continuity:)` (R9), the result carrying the input's tags and adjacency
  (`carryingTopology`). Sentences: "Match Surface changes a sheet with one face; this one has 3."; "Match Surface takes a sheet; this
  is a closed solid."; "Match Surface changes an open edge of the sheet; this edge has two faces."; "Match Surface works on an
  untrimmed edge of its surface; this edge is a trim."; "The target edge must be on another body."; "The edges' ends are 0.8 mm apart;
  Match needs them to meet." (the larger end gap); a miss after refining: "Match couldn't make the edge curvature continuous with the
  target; it reached G1. Choose G1, or rebuild the surface with more spans." (G1 asked: "… tangent continuous with the target; it
  reached G0. …"; G0: "Match couldn't make the edge meet the target within 0.0001 mm.").
- The rows (the shim, our code), with s along the edge and r across it (r = 0 at the edge), after R9's degree raise and knot
  insertion, at each refinement level. Every fit is linear least squares in the rational basis `Rᵢⱼ = wᵢⱼ Nᵢⱼ / W` and its
  r-derivatives with every weight held fixed (R9; all weights 1 for a non-rational net), solving for one row at a time with the
  rows before it fixed:

```text
row 0: S(s, 0) = C(σ(s)) at 4 × (poles) + 1 samples, end poles pinned to C's ends
row 1 (G1, G2): S_r(s, 0) = m(s)·d(s): d the target face's continuation direction (unit, in its tangent plane, perpendicular to C',
       pointing away from the target face), m the sheet's cross speed |S_r| before the match
row 2 (G2): S_rr(s, 0) = its tangential part from before + κ(s)·|S_r|²·N(s) (κ the target's normal curvature across the edge, N its
       oriented normal)
measure edge_continuity_against(edge, sheet face, target face): pass when positionGap ≤ 1e-4 and grade ≥ requested;
       else insert a knot at the middle of every span along s and repeat (≤ 5 times, ≤ 100,000 poles)
```

- R13 in `cocct_continuity.cpp`, two-body branch only: `used` 0 to 15 keeps `user_error("The edge doesn't run along that face.")`;
  16 to 23 throws `user_error("Too few points along the edge lie on the other face to grade it.")`; 24 or more grades. The one-body
  branch (`edge_continuity`) is unchanged.

- [ ] **Step 1: Tests.** Fixtures: A, a Loft Surface of the lines (0, 0, 0)–(0, 10, 0) and (10, 0, 0)–(10, 10, 0) (its
  `.boundary(.end)` edge on x = 10); B, a Revolve Curve sheet of the line (10, 0, 0)–(10, 10, 0) about the axis through
  (0, 0, 17.3205) along +y, 60°, turned so it leaves the edge along (cos 30°, 0, sin 30°) (G0 to A).
  `g1MakesTheEdgeTangent` and `g2MakesItCurvatureContinuous` (`continuity(of:in:against:of:)` of the result against B's face:
  grade ≥ requested, positionGap ≤ 1e-4); `g0MeetsAWavyTarget` (B replaced by a sheet whose start edge bulges 0.3 mm mid-span →
  positionGap ≤ 1e-4); `theOppositeEdgeStays` (A's start edge at 9 samples unchanged within 1e-9, G2); `topologyIsKept` (the
  three tables of the Global Constraints equal A's); `endsApartRefuse` (B moved by (0, 0.8, 0) → the sentence with "0.8 mm");
  `aTwoFaceEdgeRefuses`; `aTrimmedEdgeRefuses`; `aSolidTargetUsesTheContinuedFace` (A tilted: its start line lowered to
  (0, 0, −2)–(0, 10, −2), so it meets the box only at G0 (asserted before the match); target: the edge x = 10, z = 0 of a box over
  x 10…20, y 0…10, z −10…0, whose faces there are the top (z = 0, leaving across the edge along −x) and the side x = 10 (leaving
  along +z); A's inward direction ≈ (−0.98, 0, −0.2) agrees best with −x, so R9 picks the top → the result graded ≥ G1 against the
  top face); `aReversedEdgeIsPaired` (B's edge running −y → still G1); `aSteepMatchIsNotRefused` (B leaving at 150° → a valid
  result); `aRationalSheetIsMatched` (the roles swapped: B, a rational Revolve Curve sheet, matched at G1 and at G2 to A's edge, so
  the fixed-weight fit is exercised → graded ≥ requested, positionGap ≤ 1e-4, B's far edge unchanged within 1e-9, B's weights
  unchanged); `tooFewSamplesThrow` (TwoBody: an edge of which 60 % lies on the other face, about 19 usable samples → "Too few points
  along the edge lie on the other face to grade it."; one a third of which does → still "The edge doesn't run along that face.").
- [ ] **Step 2: Run** `swift test --filter 'MatchSurfaceTests|TwoBodyContinuityTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter, then `swift test --filter 'BoundaryPatch|EdgeContinuityOCCTTests'` (the regex covers
  `BoundaryPatchTests`, `BoundaryPatchG2Tests`, `BoundaryPatchR2Tests` and `BoundaryPatchNodeTests`: Boundary Patch grades with this
  call); pass.
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
- Produces: `OCCTKernel.blendSurface(_:_:tag:)` (R10, R12). Sections pair points at equal arc-length fractions from the paired
  starts (R10). Sentences: "Blend Surface joins at G1 or G2."; "Blend Surface needs two different edges."; "The bulge must be from
  0.1 to 2."; "The edges touch; a blend needs a gap between them." (any section chord under 0.01 mm); misses after 129 sections: "The
  blend can't be made curvature continuous along these edges." (G2 on a side) / "The blend can't be made tangent continuous along
  these edges.".

- [ ] **Step 1: Tests.** Fixtures: A, a flat Loft Surface at z = 0 over x 0…10, y 0…10 (its edge on x = 10); B, the same at z = 10 over x
  20…30 (its edge on x = 20). `g1BlendIsTangentAtBothEnds` and `g2BlendIsCurvatureContinuous` (each side graded against its face:
  ≥ requested, positionGap ≤ 1e-4); `bulgeChangesTheShape` (0.5 against 1.5: the blend's midpoint moves more than 0.1 mm);
  `edgesAreNamed` (the face and four edges by R10); `aReversedEdgeIsPaired` (B's edge reversed → the same surface within 1e-6 at 9
  points); `edgesThatTouchRefuse`; `aSolidEdgeUsesTheFaceThatFacesTheOtherEdge` (B replaced by a box over x 20…30, y 0…10, z 0…10;
  its edge x = 20, z = 10 against A's: the top face leaves across it along −x, the side x = 20 along +z, and the direction to A's
  edge midpoint (10, 5, 0) is (−0.71, 0, −0.71), so R10 picks the top → G1 graded against the box's top face);
  `twoEdgesOfOneBodyBlend` (A and B joined by `Kernel.compound` into one sheet: its two edges blend to the same surface as A's and
  B's within 1e-6 at 9 points); `theSameEdgeTwiceRefuses`; `sectionsPairByArcLength` (B's edge 20 mm long against A's 10: the
  blend's middle section joins the two edges' midpoints within 1e-6); `cancellationStops`. Regression: the G2 fillet suites pass unchanged.
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
    one edge to change; “edges” gives 3." / "… one target edge; “target” gives 2." A fold warns `EditSurfaceNode.foldWarning` (R11:
    always at G0 and G1; at G2 not for the G1 stand-in built while scrubbing).
  - `creator.blendSurface`: inputs `edges`, `other edges` (`.edgeSet`), `continuity` and `other continuity` (segmented "G1" / "G2",
    default 0, mapped to `.g1` / `.g2`), `bulge` and `other bulge` (number 0.1 to 2, default 1); output `surface`; inspector with both
    rule summaries and "Pick edge in view…" / "Pick other edge in view…" (`.pickOtherEdgesInView`). "Blend Surface takes one edge on
    each side; “edges” gives 3."
  - R11 on both: `readsScrubbing(for:)` true only when a G2 is chosen; under `context.isScrubbing` the G2 sides build as G1 with no
    warnings.
  - Library section "Edit".

- [ ] **Step 1: Tests** (OCCT-gated, graph-level, Task 8 and 9 fixtures): `matchNodeMatches`; `matchCountsEdges`;
  `matchBuildsG1WhileScrubbing` (G2 chosen, an `EvalContext` with `isScrubbing` → graded G1 not G2, no warnings;
  `readsScrubbing(for:)` false at G0 and G1, true at G2); `aG1FoldWarnsAfterADrag` (a G1 Match whose target, moved by an upstream
  number, folds the sheet: evaluated with `isScrubbing` true it already warns `foldWarning`, and the evaluation after the flag clears
  reuses that cached result, warning included; the G2 version warns only after the flag clears); `blendNodeBlends`; `blendTakesOneEdgeEachSide`; `blendBuildsG1WhileScrubbing`; `OutputNodeTests` 110, `.surface` 20.
- [ ] **Step 2: Run** `swift test --filter 'MatchBlendNodeTests|OutputNodeTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `swift test --filter CreatorNodesTests`; pass.
- [ ] **Step 5: Commit** "NURBS: Match Surface and Blend Surface nodes".

### Task 11: Picks in the app (trim regions, target and other edges, hidden pieces)

**Files:**
- Create: `Sources/CreatorApp/AppModel+TrimRegions.swift`
- Modify: `Sources/CreatorApp/PickSession.swift` (`trimRegions: NodeID?`, `pickedPieces: [Int]`, `Prompt.trimRegions`),
  `AppModel+Picking.swift` (`beginPick(for:socket:)`, routing the four new actions, region clicks, Done), `AppModel+Scene.swift`
  (a region pick's item shows `selectedFaces`), `SceneBuilder.swift` (skips `previewHiddenOutputs`), `Sources/CreatorGraph/UndoName.swift`
  (`pickTrimRegions = "Pick Trim Regions"`, `clearTrimRegions = "Clear Trim Regions"`), `Sources/CreatorEditor/EditorModel+Inspector.swift`
- Test: `Tests/CreatorAppTests/TrimRegionPickTests.swift`, `Tests/CreatorAppTests/SecondEdgePickTests.swift`

**Interfaces:**
- Consumes: Tasks 5 and 10; `TrimRegions.resolve`, `TrimRegions.pick(forPiece:pieces:in:)`, the Trim node's split pieces (the
  `pieces` output's faces grouped into connected pieces, as `SheetSplit.pieces`).
- Produces: `AppModel.beginTrimRegionPick(for: NodeID)`, `AppModel.clearTrimRegions(of: NodeID)`, `AppModel.beginPick(for:socket:)`.
- Behaviour: the region pick shows the Trim node's `pieces` sheet alone, starting from the pieces its current picks resolve to (all
  of a piece's faces shown selected); a click on any face toggles the whole piece holding it (R4); Done writes `.regionPicks` (one
  `TrimRegions.pick(forPiece:)` per kept piece, in piece order) to `keepRegions` as one step "Pick Trim Regions" and selects the
  node; Cancel changes nothing; the banner reads "Click the regions to keep · N picked". Refusals: inside a
  group "A region can't be picked inside a group yet. Pick it from the top level."; no pieces "“<node>” has no pieces to pick yet: wire a
  sheet and a cutter first."; refused while control points are being edited (as every pick is). Clear is one step "Clear Trim Regions".
  The two edge actions pick for sockets "target" and "other edges" as Fillet's button does for "edges".

- [ ] **Step 1: Tests:** `pickRegionsShowsTheWholeSplit`; `clickingTogglesARegion`; `clickingTogglesAWholePiece` (Task 4's two-face
  ruled loft cut by the plane sheet: a click on one face selects both faces of its piece, a second click on the other face clears
  both; Done writes one pick); `doneWritesFacePicksAsOneStep` ("Undo Pick Trim
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
- Modify: `CLAUDE.md` (an NS-4 paragraph after NS-3's: the six nodes, the kernel calls and shim files, R1 to R17, format 16, 110
  nodes and `.surface` 20, the R2 and R17 costs, the parked items; the NS-3 paragraph's tolerance sentences updated to 1e-6 and the
  partial periodic Rebuild; the rules sentence "File format is version 15 (…)" becomes "version 16" with a clause "16 added
  `ConstantValue.regionPicks` (Trim Surface's `keepRegions`), `TopoRole.cutSide` and `BoundaryRole.cut` in saved picks" before the
  closing "files of format 1 to 15 open unchanged and are written as 16"; the `CreatorNodes` module line "the 104 built-in node
  definitions" becomes 110), `docs/verification/human-checks.md` (group NS-4: trim a disk out of a sheet and change the circle's
  radius; pick regions and undo; Inside on a holed profile; split a revolved sheet and zebra-check the pieces; extend Natural and
  Linear and compare stripes; match G1 and G2 and read Measure's continuity row; blend two sheets at G2 with two bulges; drag a slider
  upstream of a G2 blend and see it build at G1 while dragging; an apex typed as one point), the spec's status line ("NS-4 done
  (2026-11-18; human checks group NS-4 pending; R1: the nodes are named … Surface; R2: pieces are named by cutter element and side)").
  No benchmark rows: the spec names none for NS-4.
- [ ] **Step 1:** docs.
- [ ] **Step 2:** `swift test` on macOS (14 "Test run with" lines, no "recorded an issue" or "failed after"); `XP_TRACK=ns-4
  scripts/linux-test.sh test` (14 lines; afterwards remove only the Docker volume this run made); `swiftlint lint --strict` 0.
- [ ] **Step 3: Commit** "Docs: NS-4".
