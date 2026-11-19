# NS-5: Back to solids — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sew, Thicken, Offset Surface, Cap Planar Holes and Split Solid: the nodes that turn sheets back into closed solids that
Boolean, Fillet, Section and every export accept, with picks on their results that keep their names.

**Architecture:** Five kernel calls, each one shim builder under `OCCTKernel.serialized` whose result is checked by
`BRepCheck_Analyzer` and named from tables the shim returns (face history as today, plus a new per-edge history so a sewn edge
remembers the boundary edges it was sewn from). Sew and Cap Planar Holes end in `BRepBuilderAPI_Sewing` and a shared
`solidify_closed_shell`; Thicken is Offset Surface's offset shell plus ruled walls, sewn and solidified; Split Solid runs the
splitter NS-4 already uses and names pieces by NS-4's cut-side rule. No new saved kind: the names reuse existing roles, so the file
format stays 16. Free edges of a Sew or Cap result are drawn in the theme's warning colour.

**Tech Stack:** Swift 6.4, Swift Testing, OpenCascade 7.9 (`BRepBuilderAPI_Sewing`, `BRepBuilderAPI_MakeSolid`,
`BRepOffsetAPI_MakeOffsetShape`, `BRepFill::Face`, `ShapeAnalysis_FreeBounds`, `BRepBuilderAPI_MakeFace`, `BRepAlgoAPI_Splitter`,
`GeomLProp_SLProps`, `Message_ProgressIndicator`, `BRepCheck_Analyzer`), MetalUI.

**Spec:** `docs/superpowers/specs/2026-11-17-nurbs-surfaces-design.md`. Read §Anti-goals, §Naming (the Sew paragraph), §Rules every
surface node follows and §NS-5. CLAUDE.md's NS-1 to NS-4 paragraphs describe sheets (`hasOpenShell`, boundary roles), the fold
check, cut naming (R2, R17) and the splitter this plan builds on.

## Global Constraints

- **Worktree and branch.** Worktree `/Users/maxburger/Developer/MetalCreator-ns5`, branch `ns-5`. Never touch MetalUI.
- **OCCT only through the kernel,** under `OCCTKernel.serialized`; every C allocation has a `*_free`; no C++ exception crosses into
  Swift (`guarded`). Shim portability: no `M_PI` (`cocct::kPi`), no POSIX headers, no `__attribute__`, never the token `near`
  (reword; never split it across literals).
- **Valid results only.** Every result is checked with `BRepCheck_Analyzer`; an invalid one is never returned. Thicken and Offset
  Surface also hold their results to R8.
- **Closed means closed.** A result called a solid has no face on an open shell (`Solid.hasOpenShell == false`), a positive volume,
  and is accepted by Boolean, Fillet, Section caps, STEP, STL and 3MF export.
- **Picks don't drift** (spec anti-goal): every name below is fixed by R3 to R6, R12 and R13 and tested in Task 10.
- **File format stays 16** (R2). No new `ConstantValue`, `TopoRole`, `BoundaryRole` or socket type.
- **Limits and refusals** are full sentences, numbers through `Locale.messages` (`Double.display`, `Int.display`,
  `millimetreText(locale:)`); the exact sentences in the tasks are verbatim requirements.
- **Kernel calls** are refused by default and in `FakeKernel` with `KernelError.unsupported` and a gerund phrase ("sewing",
  "thickening", "offsetting surfaces", "capping holes", "splitting solids").
- **Cancellation** reaches OCCT's long algorithms through R15's progress indicator and is checked between search tries.
- **Tests and checks.** Swift Testing only; OCCT tests gated `#if canImport(CreatorOCCT)`; `swiftlint lint --strict` over the whole
  tree; macOS and Linux each print 14 "Test run with" lines and never "recorded an issue" or "failed after"; never block a pool
  thread in a test (use `HookGate`).
- **Commit trailer:** `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_0195iKYokoi2BJLpboZBys76`.

## Rulings (where this plan narrows the spec; each says why and what it costs if wrong)

- **R1. Names and places.** Sew (`creator.sew`), Thicken (`creator.thicken`), Offset Surface (`creator.offsetSurface`), Cap Planar
  Holes (`creator.capPlanarHoles`) in `.surface`; Sew, Thicken and Cap in a new library section "Solids" (after "Edit"), Offset
  Surface in "Edit" (it gives a sheet). Split Solid (`creator.splitSolid`) in `.solid` beside Boolean, since it takes a solid and
  Boolean's refusal points to it. 115 built-in nodes, `.surface` 24, `.solid` 8. Cost if wrong: a rename is a `typeID` migration.
- **R2. No format bump: names reuse existing roles.** A face made from one input edge (a Thicken wall, a cap) is
  `TopoRole.blend(sourceEdge:)`, whose doc becomes "a face generated from the edge `sourceEdge`: a fillet's or chamfer's blend, a
  Thicken wall or a cap (NS-5)"; the two sides of a Thicken are `.startCap`/`.endCap`; Split Solid uses NS-4's `.cutSide` and
  `CutterName.face`. Why: older readers decode every saved pick, and the shim's existing `OCCT_FROM_EDGE` record already names
  such faces. Cost: the sort key reads `blend(…)` for a wall; any future reader that takes `.blend` to mean a fillet face would
  mislabel walls and caps (none does today: only `OCCTTagger` and `FakeKernel` construct it).
- **R3. Thicken's names.** The face on the sheet's back side (toward −normal) is the source face's tags plus
  `TopoTag(tag, .startCap)`, the face on its front side the source's tags plus `.endCap`, so the name follows which way a face looks:
  Front keeps the sheet as the start face and puts the end face at +distance, Back puts the start face at −distance and keeps the
  sheet as the end face, Both puts them at ∓distance/2. A wall is `.blend(sourceEdge: key)` of the boundary edge it stands on (an
  `OCCT_FROM_EDGE` record). Cost: switching Front to Back moves a pick on "the sheet's own face" from the start to the end face's
  name (by design: a pick names the face that looks the same way).
- **R4. Offset Surface's names.** Each face is its source's tags plus `TopoTag(tag, .endCap)`; each boundary edge keeps its paired
  source edge's tags (R7's pairing). Cost (review 2026-11-19; the earlier claim that such names never collide was wrong): picks
  match by subset (`Topology.faces(matching:)` takes a face whose tags include all of the pick's, and `Topology.edge(_:matches:)`
  a side whose tags include the key's), so a `FacePick` on a source face (tags S) also matches its offset face (S ∪ endCap), and a
  boundary key (S, E) also matches the offset's boundary edge (S ∪ endCap, E). In one value that holds a sheet and its own offset
  (a Sew of the two, a hand-made thicken) a pick on the source face or its boundary edge therefore matches two and warns in the
  existing multi-match words (`FacePickWording`, "matches several faces"); a pick on the offset face names it alone. Thicken has no
  such case (neither of its side faces is the bare S). Parked: offset names that aren't supersets of their source's.
- **R5. A sewn edge remembers its boundary names.** `EdgeInfo.tags` on a two-face edge made by sewing holds the union of the tags of
  the boundary edges sewn into it, and `Topology.edge(_:matches:)` also matches such an edge to a key whose one side is a subset of
  one of its faces' tags and whose other side is a subset of its own tags. `Topology.key(of:)` is unchanged (a new pick of a sewn
  edge is the ordinary two-face key). Why: the spec promises that a pick made on a boundary edge before a sew resolves after it,
  and `EdgeKey.operandKeys` can't do that (it only splits a side that merged several origins; it never looks at edge tags). Cost:
  `EdgeInfo.tags` no longer implies a boundary edge; every reader must test `isBoundary`, never `tags.isEmpty`. Only Sew and Cap
  Planar Holes write edge records; Thicken, Offset (beyond R4) and Split Solid don't.
- **R6. Sew.** Every face of every input body (sheets and solids alike, the spec's "solids' faces") is offered to
  `BRepBuilderAPI_Sewing` at `tolerance` (default 0.01 mm, non-manifold mode off), in input order. Each closed shell of the result
  becomes a solid through `solidify_closed_shell` (lifted out of `cocct_import.cpp`: outward by signed volume, valid by
  `BRepCheck_Analyzer`, else a null shape); a closed shell that makes no valid solid stays a sheet and is warned about; open shells
  stay sheets and the free edges are counted in a warning. The result is one body (a compound when several), each face keeping its
  input face's tags (history `OCCT_FROM_FACE`, operand = the input's index) and each edge the edge records of R5. An invalid sewn
  shape is refused. A closed solid in the list re-sews into its own closed shell, so it passes through as a solid with its names.
  **What one sheet is** (review 2026-11-19): `SewResult.sheets` counts the connected open pieces of the result, two faces being
  connected when they share an edge: each open shell is one sheet, each face in no shell is one sheet, and each closed shell that
  made no valid solid is one sheet (also counted in `unclosable`, so `unclosable ≤ sheets`); `solids` counts solids. A single shell
  is one sheet however many faces it has; a lone face the sewer wraps in a one-face shell is still one. So a box of six faces with
  one face moved off by more than the tolerance is two sheets (a five-face open box and the lone face) with 8 free edges (the open
  box's 4 rim edges and the lone face's own 4). The node's "Result" fact is built from these counts (Task 9).
  **Duplicate faces** (review 2026-11-19, so the result never depends on how OCCT's sewer pairs three coincident edges): before
  sewing, a face that coincides with a face offered earlier (bounding boxes equal within `tolerance`, areas within 1e-6 relative,
  and a 5 × 5 grid of points over its parameter domain plus each edge's midpoint within `tolerance` of the earlier face, by
  `BRepExtrema_DistShapeShape`; only pairs whose boxes agree are compared) is not offered to the sewer; it is added to the result as
  a loose face with its own tags and edge records, so it counts as one sheet and its edges as free edges. The earlier face (input
  order) is the one sewn. Cost: a face doubled on purpose stays loose; the comparison is quadratic in faces whose boxes agree.
- **R7. Offset shell, and Thicken built from it.** Offset Surface is `BRepOffsetAPI_MakeOffsetShape::PerformByJoin` (mode
  `BRepOffset_Skin`, join `GeomAbs_Intersection`, no intersection or self-intersection flags). Its face history is `Generated(face)`
  (spike, 2026-11-19: `Modified` is empty and edges get no history), so each source boundary edge is paired with a free edge of its
  own face's image, one to one per face, by the smallest sum of the distances between the two ends (either direction) plus the
  midpoints; an unpaired edge refuses "The offset changed the surface's open edges, so it can't be offset." Thicken is: the offset
  shell(s) (Front: the sheet and +d; Back: −d and the sheet; Both: −d/2 and +d/2), a ruled wall `BRepFill::Face(e, e')` per paired
  edge pair, sewn at max(1e-6 mm, 2 × the largest tolerance of the pieces), every closed shell solidified; a sheet with no free
  edges (a closed bare shell, such as a revolved sphere) gives one solid of two shells (outer, and the inner as a void), built by
  `cocct::solid_with_void(const TopoDS_Shape &a, const TopoDS_Shape &b) -> TopoDS_Shape` (Task 1, `cocct_solids.hpp`/`.cpp`): each
  closed shell is made a solid alone through `solidify_closed_shell` (null if either fails); the one of larger volume is the outer,
  oriented outward (its solid's volume positive); a vertex of the inner shell must classify `TopAbs_IN` against the outer solid
  (`BRepClass3d_SolidClassifier`, tolerance 1e-7), else null; the result is `BRepBuilderAPI_MakeSolid(outer shell)` with
  `Add(inner shell)` oriented inward (the reverse of the orientation that gave its own solid a positive volume); it is returned only
  when `BRepCheck_Analyzer` accepts it and its volume is positive and equals V(outer) − V(inner) within 1e-6 relative, else null.
  A null result is a failed build for R8's search. Why not
  `BRepOffset_MakeSimpleOffset`: on an L-shaped two-face sheet it returned a solid `BRepCheck_Analyzer` accepts with 1.4 mm
  tolerances and the wrong volume; why not `MakeThickSolidByJoin`: on an open shell it only offsets (no solid). The spike's offset
  plus walls gave the L (10 × 10 × 10 mm legs) thickened by 1 mm at 190 mm³ one way and 210 mm³ the other, tolerance 2e-7.
- **R8. When an offset counts as valid.** `BRepCheck_Analyzer` accepts it, no edge or vertex tolerance exceeds 0.01 mm, and the
  curvature rule holds: at the fold check's samples (8 × 8 cell centres per knot span, fewer when over 1,000,000 per face) both
  principal curvatures κ, signed positive when the centre of curvature lies on the +normal side, satisfy `d × κ < 1` for each offset
  distance d used; a Thicken result is also closed with a positive volume. A failure (build error or any rule) searches a
  0.01 mm grid below `min(|d|, the curvature limit)` by bisection (at most 20 builds, cancellable between them, the
  `largestValidBlend` pattern) and names the largest distance that passes. Cost: up to 20 builds before a refusal on a large sheet.
- **R9. A folded sheet is refused, not thickened.** Thicken and Offset Surface ask `Kernel.folds` first (the warning Edit Surface
  gives says "thickening and offsets will misbehave there"); a fold is refused in words before any build. Cost: a false fold would
  block a good sheet, so R10 is pulled in.
- **R10. Fold confirmation** (backlog: the needle false positive). A neighbour pair whose normals oppose is confirmed by refining the
  parameter segment between the two samples into 64 equal steps: it is a fold only if some consecutive pair at that resolution still
  has opposing normals or one degenerate normal. A fold's normal passes through zero (`Su × Sv` changes sign), so it never resolves;
  a steep spike's normal turns smoothly, so it does.
- **R11. Loose pieces that touch.** Thicken and Offset Surface refuse a sheet whose separate shells or loose faces meet along edges
  that sewing at 0.01 mm would join (a dry `BRepBuilderAPI_Sewing` pass finds contiguous edges): "Parts of the surface touch but
  aren't joined; Sew them first." Pieces that don't touch are each offset or thickened, one value holding them all. This is what
  makes an unsewn Import Model sheet (loose faces) a Sew job, not a wrong Thicken. **Only contiguity between different pieces
  counts** (review 2026-11-19): a piece is a connected open shell or a face in no shell (R6's unit); each free edge is mapped to its
  piece, and a contiguous couple the dry pass reports (`NbContigousEdges`, `ContigousEdge`, `ContigousEdgeCouple`) refuses only
  when its edges belong to two different pieces. A piece whose own free edges coincide (a wrapped non-periodic B-spline face, a
  shell whose two free boundaries touch) is not refused by R11 (what Offset or Thicken make of it is theirs to accept or refuse).
- **R12. Cap Planar Holes.** The free loops come from `ShapeAnalysis_FreeBounds` (closed wires only). A loop is flat when every
  sample of its edges lies within 0.01 mm of its least-squares plane (fixed, not an input). Flat loops in one plane (normals within
  1e-6 rad, offsets within 0.01 mm) are nested even-odd into faces with holes (`BRepBuilderAPI_MakeFace(plane, outer)` plus `Add`);
  the caps are sewn to the sheet at 0.01 mm and every closed shell solidified. A loop that isn't flat stays open and is warned about.
  A cap is `.blend(sourceEdge: key)` of the edge with the smallest key (by `sortKey`) among its outer loop's source edges, so caps of
  different loops differ and keep their names while their loop's edges do. A closed solid passes through unchanged; a closed bare
  shell (no free loop) becomes a solid. Sewing writes R5's edge records. Cost: a loop more than 0.01 mm out of flat is never capped.
- **R13. Split Solid.** `solid` (closed, else its own sentence, `ClosedSolidCheck.requireForSplitSolid`: "Split Solid takes a
  closed solid; “solid” is an open surface. Use Split to cut a surface, or Thicken or Sew it first."; `requireInput`'s sentence,
  which names Split as the way out, is not used here) and `tools` (a list of sheets or closed solids), cut
  with `BRepAlgoAPI_Splitter` through the splitter NS-4 uses (lifted into `cocct_splitter.hpp`). Elements are the tools' faces in
  input order (`CutterName.face(tags)`). Every face of a piece keeps the tags of the face it came from (a piece of the solid's face,
  or of a tool face for a cut face) plus `TopoTag(tag, .cutSide(element, side))` for each element it borders or is made from; the
  side is `.inside`/`.outside` for a tool face inside a closed solid (`!isOnOpenShell`) and `.front`/`.back` for a tool face on an
  open shell, front being the side the tool face's oriented normal points to, decided per face, so a tool value that holds a solid
  and a sheet names each face by its own kind. The lifted `run_splitter` takes the sentence it throws when the splitter fails
  (`const char *failure`): Trim and Split pass NS-4's "The cutter couldn't divide this surface.", Split Solid passes "The tools
  couldn't divide this solid.", so no surface wording reaches Split Solid. A tool face left inside one piece (it doesn't reach across) is removed from that piece and warned about; no
  division at all is a refusal; an empty tool list gives the solid back as a list of one. Pieces are ordered by
  `SheetPieces.ordered`. Cost: as NS-4's R2, pieces bordered by the same elements on the same sides share names.
- **R14. Free edges in the warning colour.** `ViewportItem.warningEdges` (edge IDs) are drawn in `ViewportPalette.warning`,
  2.5 points wide, by both renderers through `GPUGeometry.edgeInstances` (no shader change), in every display mode; selection wins
  over warning. `SceneBuilder` fills them with every boundary edge of an item whose source node's definition has
  `NodeDefinition.showsFreeEdges` (new, default false; true for Sew and Cap Planar Holes), so they show in Selected-node preview
  and in Final preview through an Output wired straight from one.
- **R15. Cancellation inside OCCT.** `cocct::cancel_progress` (new, `cocct_progress.hpp`) is a `Message_ProgressIndicator` whose
  `UserBreak()` reads an `occt_cancel` flag; sewing, the splitter (`run_splitter`, so NS-4's split gains it too) and the offset take
  its range, and a break throws `cocct::kCancelled`.
- **R16. No benchmark rows.** The spec names none for NS-5.
- **R17. Values that hold solids and sheets** (review 2026-11-19). One `Solid` value may hold closed solids and sheets
  (`hasOpenShell` is then true). `Solid.holdsClosedSolid` (new, Task 1: some face is not on an open shell; a closed bare shell's
  faces are on an open shell, so it doesn't count) tells them apart. Thicken and Offset Surface refuse such a value before any
  build, since `MakeOffsetShape` would offset the solid's faces too: "Thicken takes sheets only; this value also holds a closed
  solid." and "Offset Surface takes sheets only; this value also holds a closed solid." (a value that is only solids keeps the
  sentence "… takes a sheet; this is a closed solid."). Cap Planar Holes passes the solids through untouched: the shim splits the
  input into its `TopAbs_SOLID`s and the rest, caps and sews only the rest, and puts the solids back into the result compound with
  `OCCT_FROM_FACE` records for their faces, so their names are unchanged. Sew needs no rule (R6 offers every face), and Split Solid's
  `solid` is refused by `hasOpenShell` while its tools are named per face (R13). Cost: a user with a mixed value must split it
  first (no node does that yet; parked).
- **R18. Tests never assume a curved sheet's normal** (review 2026-11-19). Revolve Curve's normal depends on the line's direction
  and the angle's sign, so the tests on the quarter cylinder and the revolved sphere either assert the pair of results (the two
  signs or sides give the two expected values in either order) or read the direction first: `towardAxisSign` (a test helper in
  `OffsetSurfaceTests`, reused by `ThickenTests`) offsets the quarter cylinder by +1 mm and returns −1 when the area grew (the
  normal points away from the axis), else +1; the sign of every "toward the axis" distance and the Thicken side (Back when the
  sign is −1, else Front) follow from it. Planar Surface on the XY plane has normal +z, which the tests that rely on it assert first
  through the face's `FaceInfo.normal`.
- **R19. Loose-face fixtures** (review 2026-11-19). The six (or seven) box faces written as loose faces to STEP are each copied on
  their own first (`BRepBuilderAPI_Copy` through a FOR TESTS ONLY `OCCTShape.independentCopy()`, added in Task 3 if none exists;
  the whole fixture is `OCCTKernel.looseBoxFaces`, Task 3), so no two share an edge in the file, and every test that reads them back first asserts its precondition: one sheet of 6 faces with
  24 boundary edges (7 and 28 for the duplicate case). Otherwise a reader that shared edges would give a closed bare shell, and
  Thicken would build a hollow solid instead of refusing with R11's sentence.

**Backlog (`nurbs-backlog-after-ns2` memory).** Pulled in: the fold check's needle false positive (R10, Task 2), because R9 makes a
fold a refusal; `orderedPieces`' run-dependent order for pieces that tie (Task 1), because Split Solid orders pieces the same way;
a test for the split shim's cancellation (Task 1, R15); Import Model's unsewn loose faces, which Sew now joins and Thicken refuses
in words (R11, Task 10). Parked: the guide sweep's fixed 1e-3 mm tolerance and multi-face guide edges; Network Surface's tolerance
against arc approximations; the G2 Boundary Patch limits; twist parallel transport; the `unsupported` sentence's grammar for
plural names; the fold check's seam pair; `extraDemand` reference counting; cancelling superseded net reads; the theme editor's
Esc; the closed degree-3 Curve through Points' C1 seam; NS-4's parked Extend, Match and Blend limits, unique names for pieces that
share a tag set, the `.cut(.curve(index: -1))` placeholder, `EditorModel.insert` and scoped IDs, and quadratic coincident-pole
grouping. New parked items: Thicken with per-face distances or open faces removed (a shell of a solid), a Cap flatness input,
Sew in non-manifold mode, edge records for Thicken and Split Solid (R5), offset names that aren't supersets of their source's
(R4), and a node that separates a value's solids from its sheets (R17).

## Review Focus

1. **A sheet with a hole, and a sheet with no free edges.** A ring (Planar Surface of a circle with a round hole) thickens with walls
   on both loops; a closed bare shell (a 360° revolved half circle) thickens to one solid with a void. Task 5
   (`aRingGetsTwoWalls`, `aClosedSheetThickensToAHollowSolid`).
2. **Too far for the curvature, or onto a fold.** A quarter cylinder (radius 10) thickened 12 mm toward its axis (found by R18's
   probe, never assumed) is refused naming
   a distance under 10 mm, never a self-overlapping solid; a folded Edit Surface is refused in words. Tasks 4 and 5
   (`pastTheRadiusNamesTheLargest`, `aFoldIsRefused`).
3. **Gaps wider than the tolerance, and duplicate faces.** Six box faces with one moved 0.05 mm sew at 0.01 mm to two sheets (a
   five-face open box and the lone face, R6's unit) with 8 free edges, and to a solid at 0.1 mm; the same face given twice makes
   one valid solid of volume 1000 and leaves the later copy loose (R6). Task 3 (`aGapWiderThanTheToleranceStaysOpen`,
   `aDuplicateFaceNeverMakesAnInvalidSolid`).
4. **A tool that only partly enters the solid.** The internal face is removed and warned about, each piece is valid, closed and
   accepted by Boolean; a tool that divides nothing is a refusal. Task 7 (`aDanglingToolWarnsAndLeavesNoInternalFace`,
   `aToolThatMissesIsRefused`).
5. **A pick after an upstream change.** A pick on a Thicken wall survives the distance changing, on its end face survives Front to
   Both, on a sewn face and a pre-sew boundary edge survives the tolerance changing, on a cap survives the loft section growing, and
   on a Split Solid cut face survives the cutting plane moving. Task 10 (`BackToSolidsNamingTests`).

---

### Task 1: Kernel surface, sewn-edge names and shared shim helpers

**Files:**
- Create: `Sources/CreatorKernel/BackToSolids.swift` (the types and `Solid.holdsClosedSolid`), `Sources/COCCT/cocct_progress.hpp`, `Sources/COCCT/cocct_solids.hpp`,
  `Sources/COCCT/cocct_solids.cpp`, `Sources/COCCT/cocct_splitter.hpp`, `Sources/CreatorOCCT/OCCTEdgeHistoryRecord.swift`
- Modify: `Sources/CreatorKernel/Kernel.swift` (five requirements and refusing defaults), `Sources/CreatorKernel/EdgeInfo.swift`
  (doc of `tags`), `Sources/CreatorKernel/Topology+EdgePicks.swift` (R5), `Sources/CreatorKernel/TopoRole.swift` (R2's doc),
  `Sources/CreatorKernel/SheetPieces.swift` (tie), `Sources/COCCT/include/cocct.h` (`occt_edge_history`),
  `Sources/COCCT/cocct_import.cpp` (use the lifted `solidify_closed_shell`), `Sources/COCCT/cocct_trim.cpp` (use the lifted
  `run_splitter` with R15's range), `Sources/CreatorOCCT/OCCTTagger.swift` and `OCCTKernel.swift` (`edgeHistory:` parameter)
- Test: `Tests/CreatorKernelTests/SewnEdgeMatchingTests.swift`, `Tests/CreatorKernelTests/SheetPiecesOrderTests.swift`,
  `Tests/CreatorKernelTests/SolidKindTests.swift`, `Tests/CreatorOCCTTests/SplitCancellationTests.swift`

**Interfaces:**
- Produces (CreatorKernel):
  - `public enum ThickenSide: Int, Sendable, CaseIterable { case front = 0, back = 1, both = 2 }`
  - `public struct SewResult: Sendable { public var body: Solid; public var solids: Int; public var sheets: Int; public var unclosable: Int }`
    (`unclosable`: closed shells that made no valid solid and stay sheets)
  - `public struct CapResult: Sendable { public var body: Solid; public var capped: Int; public var notFlat: Int }`
  - `public struct SolidSplit: Sendable { public var pieces: [Solid]; public var warnings: [String] }`
  - `Kernel` requirements, each with a default that throws `.unsupported(<phrase>)`:
    `sewn(_ bodies: [Solid], tolerance: Double, tag: NodeTag) async throws -> SewResult` ("sewing"),
    `offsetSurface(_ sheet: Solid, distance: Double, tag: NodeTag) async throws -> Solid` ("offsetting surfaces"),
    `thickened(_ sheet: Solid, distance: Double, side: ThickenSide, tag: NodeTag) async throws -> Solid` ("thickening"),
    `cappingPlanarHoles(_ sheet: Solid, tag: NodeTag) async throws -> CapResult` ("capping holes"),
    `splitSolid(_ solid: Solid, by tools: [Solid], tag: NodeTag) async throws -> SolidSplit` ("splitting solids").
  - `Topology.edge(_:matches:)` per R5; `SheetPieces.ordered` breaks a remaining tie by the piece's smallest face index.
  - `Solid.holdsClosedSolid: Bool` (R17: `topology.faces.contains { !$0.isOnOpenShell }`).
- Produces (shim, C): `typedef struct { int out_edge; int operand; int index; } occt_edge_record;` (1-based edge indices),
  `typedef struct { occt_edge_record *records; int count; } occt_edge_history;`, `void occt_edge_history_free(occt_edge_history *)`.
- Produces (shim, C++): `cocct::cancel_progress` and `cocct::progress_range(const occt_cancel *)` in `cocct_progress.hpp`;
  `cocct::solidify_closed_shell(const TopoDS_Shape &) -> TopoDS_Shape` in `cocct_solids.hpp` (moved unchanged from
  `cocct_import.cpp`) and `cocct::solid_with_void(const TopoDS_Shape &, const TopoDS_Shape &) -> TopoDS_Shape` beside it (R7's
  rules, consumed by Task 5); `run_splitter(sheet, tools, cancel, const char *failure)` and `SplitRun` in `cocct_splitter.hpp`,
  taking the cancel flag through R15 and the failure sentence of R13 (`cocct_trim.cpp` passes NS-4's sentence unchanged).
- Produces (Swift): `OCCTEdgeHistoryRecord(outEdge:operand:index:)` (0-based once read) and
  `OCCTKernel.solid(from:history:inputs:tag:operation:…, edgeHistory: [OCCTEdgeHistoryRecord] = [])`; `OCCTTagger.topology` sets an
  edge's tags to the union of `inputs[operand].edges[index].tags` over its records (after `edgeTagOverrides`, before roles).

- [ ] **Step 1: Tests.**
  - `aSewnEdgeMatchesItsPreSewBoundaryKey`: a two-face topology whose shared edge has `tags = [t]`; the key `EdgeKey(faceA.tags, [t])`
    matches it, `EdgeKey(faceB.tags, [t])` matches it, `EdgeKey([unrelated], [t])` doesn't, and `key(of:)` of the edge is
    `EdgeKey(faceA.tags, faceB.tags)`.
  - `aTwoFaceEdgeWithoutTagsMatchesAsBefore`: the existing two-face rule unchanged.
  - `piecesThatTieAreOrderedByTheirSmallestFace`: two groups with equal keys and centroids within 1e-9 come out in the order of their
    smallest face index, both ways round the input.
  - `aCancelledSplitStopsInTheShimsWords` (OCCT): `OCCTShape.splitSheet` with a pre-set `OCCTCancelFlag` throws
    `OCCTCancelFlag.message`; `kernel.split` under a cancelled task throws `CancellationError`.
  - `theNewCallsAreRefusedByDefault`: `FakeKernel().thickened(…)` throws `KernelError.unsupported("thickening")`, and the userMessage
    reads "Thickening isn't supported by this kernel yet."; the same for the other four phrases.
  - `aMixedValueHoldsAClosedSolid` (`SolidKindTests`): hand-made topologies: all faces on open shells → `hasOpenShell` and not
    `holdsClosedSolid`; none → `holdsClosedSolid` and not `hasOpenShell`; one of each → both true.
- [ ] **Step 2: Run** `swift test --filter 'SewnEdgeMatchingTests|SheetPiecesOrderTests|SplitCancellationTests|SolidKindTests'`;
  expect failures.
- [ ] **Step 3: Implement** the above. Grep every reader of `EdgeInfo.tags` and make sure none treats non-empty tags as "boundary".
  `ReadShapesTests`, `TrimTests` and every split test must pass unchanged after the lifts.
- [ ] **Step 4: Run** the filter, then `swift test --filter 'CreatorKernelTests|CreatorOCCTTests'`; pass.
- [ ] **Step 5: Commit** "NS-5: kernel surface, sewn-edge names, shared shim helpers".

### Task 2: Fold confirmation (R10)

**Files:**
- Modify: `Sources/COCCT/cocct_control_net.cpp` (`occt_surface_folds`)
- Test: `Tests/CreatorOCCTTests/FoldConfirmationTests.swift`

**Interfaces:**
- Consumes: `Kernel.folds(_:)` (unchanged signature).

- [ ] **Step 1: Tests.**
  - `aSteepSpikeIsNotAFold`: `kernel.bsplineSheet(uCount: 9, vCount: 9, degree: 3, tag:)` (`OCCTKernel+ControlNet.swift`; it gives
    a `Solid`, which `movingPoles` and `folds` take) with the middle pole (4, 4) raised along z by 40 × the net spacing (the distance
    from pole (4, 4) to pole (5, 4), read from `controlNet(of:)`) through `kernel.movingPoles` → `folds == false`.
  - `aCornerDraggedAcrossStillFolds`: the existing `PoleMoveTests` fold case (corner pole across the net) still `true`.
  - `aTrimmedFoldStillCounts`: `FoldTrimTests` pass unchanged.
- [ ] **Step 2: Run** `swift test --filter FoldConfirmationTests`; `aSteepSpikeIsNotAFold` must fail because today's check flags the
  spike (`folds == true`). If it passes today, the test proves nothing: raise the factor (60, 80, 120 × the spacing) until today's
  check flags it, keep that factor in the test and note it in the ledger; if no factor up to 120 is flagged, stop and report (the
  backlog's needle case isn't reproduced by this fixture) rather than implement R10 blind.
- [ ] **Step 3: Implement** R10 in the comparison loop: confirm a flagged pair before setting `*folds`; poll nothing new (the check is
  bounded by its sample cap).
- [ ] **Step 4: Run** the filter, `FoldTrimTests`, `PoleMoveTests` and `EditSurfaceNodeTests`; pass.
- [ ] **Step 5: Commit** "NS-5: confirm folds by refining flagged pairs".

### Task 3: Sew (kernel)

**Files:**
- Create: `Sources/COCCT/cocct_sew.cpp`, `Sources/CreatorOCCT/OCCTKernel+Sew.swift`, `Sources/CreatorOCCT/OCCTKernel+LooseFaces.swift`
  (R19's fixture as an internal FOR TESTS ONLY `OCCTKernel.looseBoxFaces(size:movingTopBy:doublingTop:) -> Data`: a box's faces,
  the top optionally moved outward or written twice (the copy last), each independently copied, as STEP bytes; internal, so
  `CreatorOCCTTests`, `CreatorNodesTests` and `CreatorAppTests`, which all `@testable import CreatorOCCT`, share it in Tasks 3, 9
  and 10)
- Modify: `Sources/COCCT/include/cocct.h`; `OCCTShape` gains the FOR TESTS ONLY `independentCopy()` if no such helper exists
- Test: `Tests/CreatorOCCTTests/SewTests.swift`

**Interfaces:**
- Consumes: Task 1's types, edge history, `solidify_closed_shell`, `progress_range`.
- Produces: `occt_shape *occt_sew(const occt_shape *const *bodies, int count, double tolerance, const occt_cancel *cancel,
  occt_history *history, occt_edge_history *edges, int *solids, int *sheets, int *unclosable, occt_status *status)` and
  `OCCTKernel.sewn(_:tolerance:tag:)` per R6.
- Refusals: "Sew needs at least one surface." (empty list), "The tolerance must be greater than 0." (≤ 0 or not finite),
  "Sewing made an invalid shape; try a smaller tolerance." The kernel only refuses; the warnings are the node's (Task 9).

- [ ] **Step 1: Tests.**
  - `sixFacesOfABoxSewIntoASolid`: a 10 × 10 × 10 box's six faces, each copied on its own (R19), written to STEP as loose faces and
    read back (`ReadShapesTests`' route); precondition: one sheet of 6 faces with 24 boundary edges → `solids == 1`, `sheets == 0`,
    `!hasOpenShell`, volume 1000 (1e-6 relative), each face's tags equal to its source face's tags.
  - `aGapWiderThanTheToleranceStaysOpen`: the same with the top face moved 0.05 mm outward before writing (precondition as above)
    → at 0.01 mm `solids == 0`, `sheets == 2` (the five-face open box and the lone top face, R6's unit), the body has 8 boundary
    edges (the open box's 4 rim edges and the top face's own 4); at 0.1 mm `solids == 1`, `sheets == 0`.
  - `aDuplicateFaceNeverMakesAnInvalidSolid`: the six faces plus a copy of the top written last (seven loose faces; precondition:
    7 faces, 28 boundary edges; the copy's tags name `.imported(face: 6)`, so they differ from the top's) → the result is valid
    (`occt_is_valid`), `solids == 1` with volume 1000 (1e-6 relative), `sheets == 1`, and exactly one face is on an open shell: the
    copy (its tags include `.imported(face: 6)`), with 4 boundary edges in the body (R6's duplicate rule keeps the earlier face).
  - `aSewnEdgeRemembersItsBoundaryNames`: two Planar Surface squares sharing a side → the sewn edge has two faces and the union of
    both source edges' tags; a still-free edge keeps exactly its source edge's tags.
  - `aSolidInTheListPassesThrough`: a box solid and an unrelated sheet → `solids == 1`, `sheets == 1`, the box's face tags unchanged.
  - `refusals`: the three sentences; a cancelled task throws `CancellationError`.
- [ ] **Step 2: Run** `swift test --filter SewTests`; fail.
- [ ] **Step 3: Implement.** Faces are added one by one (`sewing.Add(face)`), so history is per face: `sewing.Modified(face)` (or the
  face itself) located in the result's face map gives an `OCCT_FROM_FACE` record (operand = body index, index = face). Edge records:
  each source edge's image (`ModifiedSubShape`, possibly several pieces) located in the result's edge map. R6's duplicate pre-pass
  runs before any `Add`; `sheets` and `unclosable` are counted by R6's unit (connected pieces of the result after solidifying).
- [ ] **Step 4: Run** the filter; pass.
- [ ] **Step 5: Commit** "NS-5: sew sheets into solids".

### Task 4: Offset Surface (kernel)

**Files:**
- Create: `Sources/COCCT/cocct_offset.cpp`, `Sources/COCCT/cocct_offset.hpp`, `Sources/CreatorOCCT/OCCTKernel+Offset.swift`,
  `Sources/CreatorOCCT/KernelError+Offset.swift`
- Modify: `Sources/COCCT/include/cocct.h`
- Test: `Tests/CreatorOCCTTests/OffsetSurfaceTests.swift`

**Interfaces:**
- Consumes: Task 1, `Kernel.folds`, `progress_range`.
- Produces (shim, shared with Task 5 through `cocct_offset.hpp`): `offset_shell(sheet, distance, cancel) -> offset_result` holding
  the shell, the image face of each source face, and the source-edge to image-edge pairs (R7); `curvature_limit(sheet, sign)` (the
  smallest positive d with d × κ = 1 on that side, +∞ when none, R8); `touching_pieces(sheet)` (R11's dry sew).
- Produces (C): `occt_offset_surface(sheet, distance, cancel, occt_history *, occt_edge_history *, status)`,
  `occt_offset_limit(sheet, int sign, double *limit, status)`, `occt_touching_pieces(sheet, int *touching, status)`.
- Produces (Swift): `OCCTKernel.offsetSurface(_:distance:tag:)` per R4, R7 to R9, R11; `KernelError.offsetFailed(distance:largest:
  thickening:locale:) -> KernelError` (an `.invalidInput` sentence) shared with Task 5; an internal
  `largestValidOffset(below:limit:build:)` search on the 0.01 mm grid (R8), also used by Task 5.
- Sentences: "Offset Surface takes a sheet; this is a closed solid.", "Offset Surface takes sheets only; this value also holds a
  closed solid." (R17), "The distance can't be 0.", "The surface folds over itself, so
  it can't be offset; move its control points apart first.", "Parts of the surface touch but aren't joined; Sew them first.",
  "The offset changed the surface's open edges, so it can't be offset.", "The surface can't be offset by -12 mm; the most that works
  is -9.99 mm." and, when nothing on the grid works, "The surface can't be offset by -12 mm; even -0.01 mm fails."

- [ ] **Step 1: Tests.**
  - `aPlaneMovesAlongItsNormal`: a 10 mm Planar Surface square (normal +z) at 2 → one face at z = 2 (bounds), area 100, its tags the
    source's plus `endCap`, each boundary edge's tags its source edge's.
  - `aQuarterCylinderOffsetsToTheRightRadius`: Revolve Curve of a 20 mm line parallel to z at radius 10, about z by 90° (its
    normal's direction is not assumed, R18) at +3 and −3 → the two areas are (π/2)·13·20 and (π/2)·7·20 in either order (1e-6
    relative; OCCT may report the face as a cylinder or a surface of revolution, so the area is what is compared); the smaller one
    is at `towardAxisSign(…) × 3` (R18's helper, defined in this file).
  - `pastTheRadiusNamesTheLargest`: the same at s × 12, s = `towardAxisSign` → `KernelError.invalidInput` whose text starts "The
    surface can't be offset by \((s × 12).display) mm; the most that works is \(s < 0 ? "-" : "")9.9" (the named distance between
    9.9 and 9.99 in size); at −s × 12 it builds.
  - `anLSheetOffsetsAcrossItsSharpEdge`: Extrude Curve of the polyline (0,0)–(10,0)–(10,10) by 10 along z → valid, two faces, every
    tolerance ≤ 0.01 mm.
  - `aFoldIsRefused`: a folded Edit Surface result (the corner-across move of `PoleMoveTests`) → the fold sentence.
  - `touchingLooseFacesAreRefused`: two Planar Surface squares sharing a side, not sewn (`kernel.compound`) → R11's sentence; two
    squares 5 mm apart offset fine.
  - `aSheetWhoseOwnEdgesTouchIsNotRefused` (R11's negative case): a one-face non-periodic cubic B-spline sheet wrapped round a
    radius-10 circle so its first and last pole columns coincide (a FOR TESTS ONLY `kernel.wrappedSheet(radius:height:tag:)` beside
    `bsplineSheet` in `OCCTKernel+ControlNet.swift`, 8 pole columns, the last equal to the first; its two side edges are distinct
    free edges lying on each other) → `occt_touching_pieces` reports none, and `offsetSurface` at +1 and −1 doesn't throw R11's
    sentence (it either builds or refuses in another sentence; the test asserts which and records it).
  - `aValueHoldingASolidIsRefused` (R17): `kernel.compound` of a 10 mm box and a Planar Surface square 5 mm away → "Offset Surface
    takes sheets only; this value also holds a closed solid."
  - `aCancelledOffsetThrows`: `offsetSurface` under a cancelled task throws `CancellationError`.
  - `theSearchStopsWhenCancelled`: the internal `largestValidOffset(below:limit:build:)` (`@testable`) with a `build` that always
    fails and cancels its task on its second call → throws `CancellationError` after at most 3 builds (no pool thread is blocked:
    the closure cancels and returns).
  - `refusals`: a box → the closed-solid sentence; distance 0.
- [ ] **Step 2: Run** `swift test --filter OffsetSurfaceTests`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter; pass.
- [ ] **Step 5: Commit** "NS-5: offset a sheet".

### Task 5: Thicken (kernel)

**Files:**
- Create: `Sources/COCCT/cocct_thicken.cpp`, `Sources/CreatorOCCT/OCCTKernel+Thicken.swift`
- Modify: `Sources/COCCT/include/cocct.h`
- Test: `Tests/CreatorOCCTTests/ThickenTests.swift`

**Interfaces:**
- Consumes: Task 4's `offset_shell`, `curvature_limit`, `touching_pieces`, `largestValidOffset`, `KernelError.offsetFailed`; Task 1's
  `solidify_closed_shell` and `solid_with_void` (R7; Task 5 builds no solid any other way).
- Produces: `occt_thicken(sheet, double distance, int side, cancel, occt_history *, status)` (history: `OCCT_FROM_FACE` plus
  `OCCT_FROM_START_CAP` or `OCCT_FROM_END_CAP` on each side face, `OCCT_FROM_EDGE` with the source edge on each wall) and
  `OCCTKernel.thickened(_:distance:side:tag:)` per R3, R7 to R9, R11.
- Sentences: "Thicken takes a sheet; this is a closed solid.", "Thicken takes sheets only; this value also holds a closed solid."
  (R17), "The distance must be greater than 0.", the fold sentence with
  "thickened", R11's sentence, and "The surface can't be thickened by 12 mm; the most that works is 9.99 mm." / "…; even 0.01 mm
  fails." (Both checks each half against the curvature limit.)

- [ ] **Step 1: Tests.**
  - `aPlateThickensToItsVolume` (spec): a 20 × 30 Planar Surface at 2 mm → volume 1200 (1e-6 relative), `!hasOpenShell`, 6 faces: one
    with `startCap`, one with `endCap` (at z = 2), four walls each `.blend(sourceEdge:)` of a distinct boundary edge key.
  - `sidesPutTheFacesWhereR3Says`: Back → the `endCap` face at z = 0 and `startCap` at z = −2; Both → ±1; the volume 1200 each time.
  - `anLSheetThickensToTheSpikesVolumes`: the L sheet of Task 4 at 1 mm, Front and Back → 190 and 210 mm³ (whichever side the
    sheet's normal gives; assert the pair), tolerances ≤ 0.01 mm.
  - `aRingGetsTwoWalls`: Planar Surface of a radius-10 circle with a radius-4 hole at 1 mm → volume π(100 − 16) (1e-4 relative), two
    walls.
  - `aClosedSheetThickensToAHollowSolid`: Revolve Curve of a half circle (radius 10) by 360° (a closed bare shell; its normal's
    direction is not assumed, R18) at 1 mm, Front and Back → valid, `!hasOpenShell`, the two volumes 4/3 π (11³ − 10³) and
    4/3 π (10³ − 9³) in either order (1e-4 relative); Both at 2 mm → 4/3 π (11³ − 9³) (no normal needed). A volume below the full
    sphere's shows the void (R7's `solid_with_void`).
  - `pastTheRadiusNamesTheLargest`: the quarter cylinder of Task 4 at 12 mm on the side toward the axis (Back when
    `towardAxisSign` is −1, else Front; R18) → text starts "The surface can't be thickened by 12 mm; the most that works is 9.9";
    the other side at 12 mm builds.
  - `aThickenedSheetIsAcceptedDownstream`: the plate result through `boolean(.subtract, …)` with a cylinder through it, `fillet` of
    one wall edge at 0.5 mm and `export` to STEP and STL all succeed.
  - `aFoldIsRefused` and `touchingLooseFacesAreRefused` as in Task 4, with "thickened".
  - `aValueHoldingASolidIsRefused` (R17): the compound of Task 4's case → "Thicken takes sheets only; this value also holds a closed
    solid."
  - `aCancelledThickenThrows`: `thickened` under a cancelled task throws `CancellationError`.
- [ ] **Step 2: Run** `swift test --filter ThickenTests`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `OffsetSurfaceTests`; pass.
- [ ] **Step 5: Commit** "NS-5: thicken a sheet into a solid".

### Task 6: Cap Planar Holes (kernel)

**Files:**
- Create: `Sources/COCCT/cocct_cap.cpp`, `Sources/CreatorOCCT/OCCTKernel+Cap.swift`
- Modify: `Sources/COCCT/include/cocct.h`
- Test: `Tests/CreatorOCCTTests/CapPlanarHolesTests.swift`

**Interfaces:**
- Consumes: Task 1 (edge history, `solidify_closed_shell`, R5).
- Produces: `occt_cap_planar_holes(sheet, double flatness, occt_history *, occt_edge_history *, occt_cap_loops *, int *capped,
  int *not_flat, status)`, where `occt_cap_loops` lists, per cap face (1-based in the result), the source edges of its outer loop
  (with its `*_free`); Swift turns each into one `OCCT_FROM_EDGE` record on the edge with the smallest key (R12). Uncapped faces carry
  `OCCT_FROM_FACE` records; the input's `TopAbs_SOLID`s are set aside before capping and put back unchanged, with `OCCT_FROM_FACE`
  records (R17). `OCCTKernel.cappingPlanarHoles(_:tag:)`.

- [ ] **Step 1: Tests.**
  - `aLoftedTubeCapsIntoASolid`: Loft Surface of two closed coaxial circles (radius 10 at z = 0, radius 6 at z = 20) → `capped == 2`,
    `!hasOpenShell`, volume of the frustum π·20·(100 + 60 + 36)/3 (1e-4 relative); the two caps carry different
    `.blend(sourceEdge:)` tags naming the `.boundary(.start)` and `.boundary(.end)` edges.
  - `concentricLoopsMakeAnAnnulus`: two coaxial open cylinder sheets (radii 10 and 6, height 20) in one body (`kernel.compound`) →
    capped into one solid with two annular caps (each one face with a hole), volume π(100 − 36)·20.
  - `aBentLoopStaysOpen`: Task 4's L sheet (Extrude Curve of an open polyline: its one boundary loop isn't flat) → `capped == 0`,
    `notFlat == 1`, the input's faces and tags unchanged.
  - `aClosedSolidPassesThrough` (a box, same object or same face count and tags) and `aClosedBareShellBecomesASolid` (the revolved
    sphere sheet of Task 5 → `!hasOpenShell`).
  - `capEdgesRememberTheirNames`: an edge between a cap and the tube carries the tube's boundary edge tags (R5).
  - `aMixedValueCapsOnlyItsSheets` (R17): `kernel.compound` of a 10 mm box placed clear of the tube and the lofted tube → `capped ==
    2`, `!hasOpenShell`, two solids (volumes 1000 and the frustum's), the box's faces with exactly their input tags.
- [ ] **Step 2: Run** `swift test --filter CapPlanarHolesTests`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter; pass.
- [ ] **Step 5: Commit** "NS-5: cap planar holes".

### Task 7: Split Solid (kernel)

**Files:**
- Create: `Sources/COCCT/cocct_split_solid.cpp`, `Sources/CreatorOCCT/OCCTKernel+SplitSolid.swift`
- Modify: `Sources/COCCT/include/cocct.h`
- Test: `Tests/CreatorOCCTTests/SplitSolidTests.swift`

**Interfaces:**
- Consumes: `run_splitter` (Task 1), `SheetPieces.ordered`, NS-4's `CutterName`, `CutSide`, `TopoRole.cutSide`.
- Produces: `occt_split_solid(solid, const occt_shape *const *tools, int tool_count, cancel, occt_split_solid_result *out, status)`
  returning the compound of pieces; `out` gives, per face of the compound's face map, its piece, its source (operand 0 the solid,
  operand k ≥ 1 tool k's face) and its (element, side) pairs, plus a `dangling` flag (with its `*_free`). Swift names the whole with
  R13, orders the pieces with `SheetPieces.ordered`, and makes each piece a `Solid` whose faces carry the whole's names.
  `OCCTKernel.splitSolid(_:by:tag:)`.
- Sentences: "The tools don't cut the solid into pieces." (refusal), "The tools couldn't divide this solid." (the splitter failed,
  R13's `run_splitter` failure sentence); "Part of a tool doesn't cross the solid from side to side, so it cut nothing there."
  (`SolidSplit.warnings`).

- [ ] **Step 1: Tests.**
  - `aPlaneCutsABoxInTwo`: a 10 mm box and a 30 mm Planar Surface at z = 5 → two pieces, each valid, `!hasOpenShell`, volume 500;
    the lower piece's cut face carries the plane face's tags plus `.cutSide(.face(planeTags), .back)` (normal +z), the upper piece's
    `.front`; a side face of each half carries the matching `cutSide`.
  - `aSolidToolCutsInsideAndOutside`: the 10 mm box cut by a closed cylinder solid of radius 3 and length 20 along z, its axis
    through the box's centre and its middle at the box's centre, so its caps lie 5 mm beyond the box's top and bottom faces (none
    coplanar) → two pieces: the one inside the cylinder (volume π·9·10) has its cylindrical faces named `.cutSide(…, .inside)`
    and the other (1000 − π·9·10) `.outside` (1e-6 relative).
  - `aDanglingToolWarnsAndLeavesNoInternalFace`: a plane that reaches half way across plus a full plane → two pieces, the warning, and
    no face of any piece lies inside it (every piece valid; `boolean(.union, piece, [box])` succeeds).
  - `aToolThatMissesIsRefused`: a plane outside the box → the refusal.
  - `orderIsStable`: the two halves come out in the same order when the tools' list order or the plane's height (4 vs 6) changes.
  - `aCancelledSplitThrows`: a cancelled task throws `CancellationError`.
  - `aMixedToolNamesEachFaceByItsKind` (R13): one tool value holding the cylinder of `aSolidToolCutsInsideAndOutside` and a
    30 mm Planar Surface square at z = 8 (box from z = 0 to 10; it crosses the box and the cylinder) made into one value with
    `kernel.compound` → four pieces; faces cut by the cylinder carry `.inside`/`.outside` and faces cut by the plane
    `.front`/`.back`, every piece valid and closed, volumes summing to 1000 (1e-6 relative).
- [ ] **Step 2: Run** `swift test --filter SplitSolidTests`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and NS-4's split suites; pass.
- [ ] **Step 5: Commit** "NS-5: split a solid with surfaces".

### Task 8: Free edges in the warning colour (R14)

**Files:**
- Modify: `Sources/CreatorViewport/Model/ViewportItem.swift` (`warningEdges`), `Sources/CreatorViewport/Render/FrameItem.swift`,
  `Sources/CreatorViewport/Model/ViewportModel+Frame.swift`, `Sources/CreatorViewport/Render/EdgeInstanceKey.swift` (`warning`),
  `Sources/CreatorViewport/Render/GPUGeometry.swift` (`edgeInstances(… warning:)`), `Sources/CreatorViewport/Render/GPUMesh.swift`,
  `Sources/CreatorViewport/RenderSDL/SDLViewportMesh.swift`, the edge loops in `ViewportRenderer.swift` and
  `SDLViewportRenderer+Plan.swift` (draw an item with warning edges in Shaded mode too), `Sources/CreatorApp/ViewportItem+Comparison.swift`,
  `Sources/CreatorGraph/NodeDefinition.swift` (`showsFreeEdges`), `Sources/CreatorApp/SceneBuilder.swift`
- Test: `Tests/CreatorViewportTests/WarningEdgeTests.swift`, `Tests/CreatorAppTests/FreeEdgeSceneTests.swift`, a case each in
  `ViewportClipRenderTests` (Metal) and `SDLRenderTests`

**Interfaces:**
- Produces: `ViewportItem.warningEdges: Set<EdgeID>` (init parameter, default empty); `NodeDefinition.showsFreeEdges: Bool`
  (static, default false). Consumed by Task 9's Sew and Cap nodes.

- [ ] **Step 1: Tests.**
  - `warningEdgesTakeTheWarningColour`: `GPUGeometry.edgeInstances` with `warning: [EdgeID(1)]` gives that edge's instances
    `palette.warning` at width 2.5 × scale; an edge both selected and warned is the selection colour.
  - `shadedModeStillDrawsWarningEdges`: with `selectedOnly` true, the warned edge is drawn and the plain ones aren't.
  - `aFreeEdgeNodesBoundaryIsWarned`: a registry with a stub definition (`showsFreeEdges = true`) whose result is a hand-made `Solid`
    (two faces, three boundary edges, one shared) → its item's `warningEdges` are the three boundary edges; through an Output wired
    from it, the same; from a node without the flag, none.
  - `warnedEdgesChangeTheItem`: `drawsTheSame` is false when only `warningEdges` differ.
  - Render (Metal and SDL, skipped without a device as the suites do): a sheet item with one warned edge in Shaded mode → pixels on
    that edge are the warning colour.
- [ ] **Step 2: Run** `swift test --filter 'WarningEdgeTests|FreeEdgeSceneTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filters and `swift test --filter 'CreatorViewportTests|CreatorAppTests'`; pass.
- [ ] **Step 5: Commit** "NS-5: free edges in the warning colour".

### Task 9: The five nodes

**Files:**
- Create: `Sources/CreatorNodes/Surfaces/SewNode.swift`, `ThickenNode.swift`, `OffsetSurfaceNode.swift`,
  `CapPlanarHolesNode.swift`, `Sources/CreatorNodes/Solids/SplitSolidNode.swift`
- Modify: `Sources/CreatorNodes/BuiltInNodes.swift`, `Sources/CreatorGraph/NodeCategory.swift` (`.surface` subgroups
  `["Curves", "Make", "Edit", "Solids"]`), `Sources/CreatorNodes/Support/ClosedSolidCheck.swift` (a tool variant and `requireForSplitSolid`, R13),
  `Sources/CreatorNodes/Solids/BooleanNode.swift`, `Tests/CreatorNodesTests/OutputNodeTests.swift` (115; `.solid` 8, `.surface` 24),
  `Tests/CreatorNodesTests/SheetRefusalTests.swift`
- Test: `Tests/CreatorNodesTests/BackToSolidsNodeTests.swift`

**Interfaces:**
- Consumes: Tasks 1, 3 to 8.
- Produces:
  - `creator.sew`: inputs `bodies` (`.solid`, list access), `tolerance` (number, mm, default 0.01, range 0.0001…1); output `solid`;
    `factsTitle` "Sew"; facts "Result" ("1 solid", "2 solids", "1 sheet", "2 sheets", "1 solid and 1 sheet": `SewResult.solids`
    then `sheets`, each in R6's unit, a zero count left out), "Free edges" (count), "Faces"; `showsFreeEdges` true. Warnings: "The
    sewn surface still has 8 free edges, so it stays open." ("1 free edge"; the number is the body's boundary edges), and for `unclosable` "A closed shell couldn't be made into a valid solid, so it stays a surface." ("2 closed
    shells couldn't be made into valid solids, so they stay surfaces.").
  - `creator.thicken`: inputs `surface` (`.solid`), `distance` (number, mm, default 1, range 0.01…100), `side` (integer, segmented
    "Front", "Back", "Both", default Front); output `solid`.
  - `creator.offsetSurface`: inputs `surface`, `distance` (number, mm, default 1, range −100…100); output `surface`; subgroup "Edit".
  - `creator.capPlanarHoles`: input `surface`; output `solid`; `factsTitle` "Caps"; facts "Holes capped", "Left open";
    `showsFreeEdges` true. Warnings: "2 holes aren't flat, so they were left open." ("1 hole isn't flat, so it was left open."), and
    when free edges remain "The capped surface still has 8 free edges, so it stays open." ("1 free edge").
  - `creator.splitSolid` (`.solid`): inputs `solid`, `tools` (`.solid`, list access); output `solids` (list);
    `ClosedSolidCheck.requireForSplitSolid(solid)` (R13's own sentence, not `requireInput`'s); the kernel's warnings forwarded.
  - Boolean's `tools` refusal becomes "“tools” is an open surface; use Split Solid to cut with it, or Thicken or Sew it first."; every
    other `requireInput` sentence is unchanged.

- [ ] **Step 1: Tests** (OCCT-gated, through the real Evaluator as the other node suites do): `sewFactsAndWarnings` (the open-gap
  case of Task 3 through R19's fixture: "Result" "2 sheets", "Free edges" "8", the warning "The sewn surface still has 8 free
  edges, so it stays open."), `sewClosesABox` ("Result" "1 solid", no warning), `thickenSidesAreSegmented`,
  `thickenRefusesASolid` (the sentence reaches the node's error), `thickenRefusesAMixedValue` (R17's sentence),
  `offsetSurfaceNegativeDistance`, `capWarnsAboutABentLoop`, `splitSolidListsItsPieces` (2 solids),
  `splitSolidWithNoToolsGivesTheSolidBack`, `splitSolidRefusesASheetInItsOwnWords` (a Planar Surface on `solid` → "Split Solid
  takes a closed solid; “solid” is an open surface. Use Split to cut a surface, or Thicken or Sew it first."),
  `booleanPointsToSplitSolid` (the new sentence;
  `SheetRefusalTests` updated for `tools` only), and `OutputNodeTests`' counts.
- [ ] **Step 2: Run** `swift test --filter 'BackToSolidsNodeTests|OutputNodeTests|SheetRefusalTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filters and `swift test --filter CreatorNodesTests`; pass.
- [ ] **Step 5: Commit** "NS-5: Sew, Thicken, Offset Surface, Cap Planar Holes and Split Solid nodes".

### Task 10: Back to solids end to end, and names that hold

**Files:**
- Test: `Tests/CreatorOCCTTests/BackToSolidsNamingTests.swift`, `Tests/CreatorAppTests/BackToSolidsAcceptanceTests.swift`
- Modify: only what a failing test shows is wrong (report each fix).

**Interfaces:**
- Consumes: everything above; `Topology.resolution(of:)` for face picks, `Topology.edges(resolving:)` for edge keys, the group
  pick path (`GroupScopes`, `EvaluationScope.naming`) as the existing group naming tests use it.

- [ ] **Step 1: Tests.**
  - Naming (kernel level, each: build, record a key or `FacePick`, change one input, resolve exactly one match with no warning):
    `aWallSurvivesTheDistance` (Thicken 2 → 3 mm), `theEndFaceSurvivesFrontToBoth`, `aSewnFaceSurvivesTheTolerance` (0.01 → 0.05),
    `aPreSewBoundaryKeyNamesTheSewnEdge` (R5: a key recorded on Planar Surface A's shared side before the sew resolves to the sewn
    edge), `aCapSurvivesTheSectionGrowing` (Task 6's loft, top radius 6 → 7), `aCutFaceSurvivesThePlaneMoving` (Task 7, z 5 → 6),
    `anOffsetFaceSurvivesTheDistance`.
  - Acceptance (graph level, `DocumentModel` over `OCCTKernel` and `BuiltInNodes.registry`, as `AppAcceptanceTests` runs):
    `anImportedLooseBoxSewsAndExports` (six faces written as loose faces to STEP by R19's fixture, Import Model → its one sheet,
    whose precondition is asserted first: 6 faces and 24 boundary edges → Thicken refuses with R11's sentence; → Sew → a solid of
    volume 1000 → Fillet one edge at 1 mm → Output; STEP, STL and 3MF export succeed);
    `aLoftCappedAndSectioned` (Loft Surface tube → Cap Planar Holes → Output; the Section caps it like any solid);
    `aThickenedPlateMinusAHole` (Planar Surface → Thicken → Boolean subtract a cylinder → Output; volume as expected);
    `splitSolidPiecesFeedBoolean` (Split Solid → List Item 0 → Boolean union with a box);
    `aThickenInsideAGroupNamesEachInstance` (a group holding Planar Surface → Thicken with two instances: a face pick stored in the
    definition resolves in each instance to that instance's face).
- [ ] **Step 2: Run** `swift test --filter 'BackToSolidsNamingTests|BackToSolidsAcceptanceTests'`; record any failure and fix it in the
  owning code.
- [ ] **Step 3: Run** `swift test --filter 'CreatorOCCTTests|CreatorAppTests'`; pass.
- [ ] **Step 4: Commit** "NS-5: back to solids end to end".

### Task 11: Docs and the suites

**Files:**
- Modify: `CLAUDE.md` (an NS-5 paragraph after NS-4's: the five nodes and their places (R1), the kernel calls and shim files, R2 to
  R15, no format change, 115 nodes, `.surface` 24 and `.solid` 8, the pulled-in and parked backlog; the NS-1 paragraph's "a file's
  loose faces … until Sew in NS-5" now says Sew joins them and Thicken refuses them unsewn; the `EdgeInfo.tags` rule of R5; the fold
  check's confirmation (R10) in the NS-3 paragraph; the `CreatorNodes` module line "the 104 built-in node definitions" corrected to
  115; the rules sentence on file format unchanged at 16), `docs/verification/human-checks.md` (group NS-5: sew an imported loose
  box and see the free edges in the warning colour while a gap is open, then close it with a larger tolerance; thicken a plate
  Front, Back and Both and watch a face pick follow; thicken past a curved sheet's radius and read the largest distance; offset a
  sheet both ways; cap a lofted tube and section it; split a box with a sheet and with a cylinder, and a half-crossing sheet's
  warning; Boolean's sentence pointing to Split Solid; a fold refusal after dragging a control point), the spec's status line ("NS-5
  done (2026-11-19; human checks group NS-5 pending; R2: no format change, names reuse existing roles; R5: a sewn edge remembers its
  boundary names)"). No benchmark rows (R16).
- [ ] **Step 1:** docs.
- [ ] **Step 2:** `swift test` on macOS (14 "Test run with" lines, no "recorded an issue" or "failed after"); `XP_TRACK=ns-5
  scripts/linux-test.sh test` (14 lines; afterwards remove only the Docker volume this run made); `swiftlint lint --strict` 0.
- [ ] **Step 3: Commit** "Docs: NS-5".
