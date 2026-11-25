# DR-3: Sections, details and auxiliary views — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Section views from a straight or stepped cutting line drawn on a parent view (the part cut on a copy by the line's half-spaces, the
remainder projected, cut faces hatched per ISO 128-50, the cutting-plane line with thick ends, arrows and letters on the parent, labelled
"SECTION A-A"), detail views (a circle on the parent, its exact projection clipped and magnified, "DETAIL B (5 : 1)") and auxiliary views
(looking square to a picked straight edge, so inclined edges read true length), with DR-2's dimensions working in all three, saved as file
format 19.

**Architecture:** One new kernel call, `Kernel.cutAway(_:by:tag:)`, which OCCT answers by composing its own extrude and boolean internals (no
new C++), names every cut face after the cutting line's segment, and refuses an invalid result. `CreatorDrawing` gains the saved derivations
(`ViewDerivation`: a section's `SectionCutter`, a detail's circle, an auxiliary view's arrow), the pure geometry (section frames, hatching, the
exact circle clip, the auxiliary rule), a cut table in `ProjectionCache`, a section branch in `DrawingProjector`, and the marks on the parent
in `SheetComposer`; hatch, marks and labels are strokes, fills and texts of the one `SheetPicture`, so the screen, the PDF and the DXF agree as
before. A detail is no new projection: the session clips the parent's content. `CreatorDrawingEditor` gains three tools; the app wires the
requests, the refresh of last good values and export.

**Tech Stack:** Swift 6.4, Swift Testing, MetalUI (existing canvas, inspector controls), OpenCascade 7.9 through the existing shim calls only.

**Spec:** `docs/superpowers/specs/2026-11-24-drawings-design.md`. Read it whole; build §DR-3 and what §Model, §Projection, §Drawing mode,
§Export, §Constraints and "Decisions after the builder check" say about views (decisions 1, 2 and 4 in full). DR-1's plan
(`docs/superpowers/plans/2026-11-24-dr-1-sheets-views-pdf.md`, R1 to R28) and DR-2's (`docs/superpowers/plans/2026-11-25-dr-2-dimensions-notes.md`,
R1 to R27) hold the rulings this plan builds on; CLAUDE.md's "Drawings, DR-1" and "Drawings, DR-2" paragraphs say what exists. GD&T, surface
finish, weld symbols, balloons, parts lists, revisions and MCP tools are DR-4 and DR-5: leave them out. Half and broken-out sections stay parked.

## Global Constraints

- **Worktree and branch.** `/Users/maxburger/Developer/MetalCreator-dr3`, branch `dr-3`. Never touch `../MetalUI`. A MetalUI shortcoming is
  logged in `docs/metalui-gaps.md` (a `DR-3-x` entry) and reported, never worked around. Never run `git stash` in any form.
- **OCCT.** Only `CreatorOCCT` touches OCCT, under `OCCTKernel.serialized`; this plan adds **no C++** (R1). Every refusal is a full sentence.
- **Module rules** (unchanged): `CreatorDrawing` depends on `CreatorGeometry` and `CreatorKernel` only; `CreatorDrawingEditor` on `CreatorDrawing`,
  `CreatorKernel`, `CreatorGeometry`, `CreatorStyle` and MetalUI only. No CoreGraphics, CoreText, ImageIO or Metal in either. Nothing iterates a
  dictionary where order reaches output (pictures, hatch, PDF and DXF bytes, lists, warnings, saved order). Files importing CreatorKernel and
  CreatorSketch qualify `ProjectedCurve`, `ProjectionSource`, `MeasuredDimension` and `DimensionKind`; files importing MetalUI and CreatorGeometry
  write `CreatorGeometry.Angle`.
- **Units.** Cutting lines, detail circles and arrows are stored in the **parent's model plane** (millimetres, `frame.place` coordinates, R2),
  so they scale and move with the parent. Hatch, marks and labels are laid out in sheet millimetres, origin bottom left, y up. Views never
  rotate (DR-2's `ViewMapping`: `m × scale + offset`); angles are radians in data, degrees only in text.
- **Constants** are `DrawingStyle` / `SectionMarkStyle` members (R6), never literals at a call site.
- **Bytes.** PDF and DXF bytes stay identical on every platform: one digest per fixture; hatch lines and marks come in a fixed order (R5, R6),
  and their directions and offsets are exact constants built with `squareRoot()`, never `sin` or `cos` (whose last bits differ between Darwin,
  glibc and MSVC).
- **File format 19** (`GraphFile.currentFormatVersion`): files of format 1 to 18 open unchanged and are written as 19 (R12).
- **Undo names** are fixed strings in `DrawingStepName` (R13): no numbers, no typed text.
- **Messages** are full sentences in the app's voice, exactly as written here.
- **Tests and checks.** Swift Testing only; OCCT tests gated `#if canImport(CreatorOCCT)`; never block a pool thread in a test (`HookGate` or a
  suspending kernel hook); `swiftlint lint --strict` reports 0; macOS and Linux each print **16** "Test run with" lines (no new test target) and
  never "recorded an issue" or "failed after".
- **Commit trailer** (every commit):
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_0195iKYokoi2BJLpboZBys76`.

## Rulings (where this plan narrows the spec; each says why and what it costs if wrong)

- **R1. The cut is one kernel call, composed in Swift.** `Kernel.cutAway(_ solid: Solid, by cutter: SectionCutter, tag: NodeTag) async throws
  -> Solid?` removes the material on the viewer's side of the cutting line and returns what is left; `nil` when nothing is left. `tag` is
  the prism tool's tag (its side faces become the cut faces, R4) and the result's name (`solid(from:…tag:operation:)` below); every caller
  passes `NodeTag(node: SectionCutter.toolNode, item: i)`, i the solid's index in the Output's solids: the cache (R14), the projector and every
  test (a test of one solid passes item 0). The default
  and `KernelUnavailable` throw `KernelError.unsupported("cutting sections")`; `FakeKernel` throws the same unless a test sets
  `setSectionCutHook(_:)` (as `setCompoundHook` works). `OCCTKernel` composes what exists: it builds the removed prism with its own public
  `extrude(_:distance:mode:tag:)` (`.symmetric`, R2's polygon on the plane `Plane(origin: direction × (bounds centre · direction), normal:
  −direction, xAxis: right)`, whose plane coordinates are exactly `(p · right, p · up)`, the distance the solid's depth extent along the
  direction plus 2 mm), then, inside one `OCCTKernel.serialized`, `OCCTShape.boolean(.subtract, …)`, checks the result's face count (0 → `nil`)
  and `isValid` (else `KernelError.operationFailed(operation: "section", reason: "the section couldn't be cut through this part.")`, whose
  `userMessage` the view shows), and names it with `solid(from:history:inputs:tag:operation:)` over `[solid.topology, tool.topology]`. Two
  shortcuts run before any boolean, on the rectangle that bounds the solid's eight box corners placed in the frame: wholly inside the removed
  polygon (all four corners inside, no polygon edge crossing it) is `nil`; wholly outside (no corner inside, no polygon vertex inside the
  rectangle, no edge crossing) returns the solid itself. `Task.checkCancellation()` runs before and after the boolean (OCCT's boolean polls
  nothing; cost: a cancelled cut finishes its boolean first). No new C++, so nothing new to free. Cost: a boolean per solid per cutting-line
  edit, cached (R14).
- **R2. The cutting line.** `public struct SectionCutter: Hashable, Sendable, Codable` (CreatorKernel) holds the parent's `frame:
  ProjectionFrame`, `points: [Vector2]` (the parent's model plane) and `viewing: Vector2` (unit, the kept side, square to the first segment).
  Its segments alternate **cut, step, cut, …**: an odd count, even-indexed segments (cuts) parallel to the first and running the same way,
  odd ones (steps) square to it (parallel and square within 1e-9 of the segment's length). The removed region is the polygon `q0, p1, …, p(n−1),
  qn, qn − viewing × R, q0 − viewing × R` with `q0 = p0 − t × R`, `qn = pn + t × R` (t the first segment's unit direction, R = 2 × the diagonal of
  the box holding the solid's placed corners and the points, plus 1), so the first and last cuts reach past the part, and its profile segment k
  is the line's segment k for every k below the line's segment count. `SectionCutter.validate() throws(KernelError)` gives every kernel the
  same refusals (`KernelError.invalidInput`, exact):
  - under two points: "A cutting line needs at least two points.";
  - two points closer than 1e-6 mm: "A cutting line's points must be apart.";
  - an even count of segments, or a step that is not square to the first: "A stepped cutting line alternates cuts and steps at right angles,
    starting and ending with a cut.";
  - a cut not parallel to the first, or running against it: "Every cut of a stepped cutting line runs the same way as the first.";
  - `viewing` not unit or not square to the first segment (1e-9): "The cutting line's view direction must be square to it.".
  Points are **positions, not anchors**: a cutting line through a hole stays where it was drawn when the hole moves. Cost: the user moves the line
  after such an edit; nothing measures from the line, so no number is wrong. A line's shape is never edited after it is placed: it is moved
  whole ("Move Cutting Line", R13), and a different shape is a new section (delete it, draw another). Cost: redrawing loses the old section's
  dimensions, which a fresh line could not keep anyway (R4).
- **R3. A section's frame, its side and its alignment** (`SectionFrame`, CreatorDrawing). With the parent frame (d, u, r = d × u), the first
  segment's unit direction t₂ and the viewing direction v₂ (both in the parent's plane), t₃ = r t₂.x + u t₂.y and s₃ = r v₂.x + u v₂.y:
  - when |t₂.x| ≥ |t₂.y|: t′ = t₃ × sign(t₂.x) and the frame is `ProjectionFrame(direction: s₃, up: t′ × s₃)` (the line reads horizontally);
  - else t′ = t₃ × sign(t₂.y) and the frame is `ProjectionFrame(direction: s₃, up: t′)` (it reads vertically).
  For a horizontal or vertical line this is exactly the frame `ProjectedViewRule.view` gives a projected view looking the same way (test
  `aStraightSectionMatchesTheProjectedView`). The side: with n₂ = t₂ turned +90° and σ = +1 when `(drop − p0) · n₂ ≥ 0` else −1 (the drop
  point and p0 in the parent's model plane), first angle (ISO) looks `v₂ = σ n₂` (the view lies the way the arrows point), third angle
  (ASME) `v₂ = −σ n₂`. A line horizontal on the parent (|t₂.y| ≤ 1e-9) gives a section aligned `.vertical` with its parent, a vertical one
  `.horizontal`, as projected views are; a slanted line gives a free view drawn upright (views never rotate). The editor snaps the first segment
  to horizontal or vertical within 5° unless ⇧ is held, so straight sections are aligned by default. A section view's `orientation` is always
  `.custom(SectionFrame.frame(for: cutter))`: the editor writes it, decoding repairs it. Cost: a slanted section is not projection-aligned (it is
  labelled, which ISO and ASME both accept).
- **R4. Names on a section** (decision 2 holds in section views). The cut tool of solid i is tagged `NodeTag(node: SectionCutter.toolNode, item:
  i)` (`toolNode` a fixed `NodeID`, UUID `5EC7C0DE-0D30-4000-8000-000000000001`, never a graph node's), so a cut face carries `TopoTag(node:
  toolNode, item: i, role: .side(loop: 0, segment: k))` with k the line's segment, and a **cut edge** is named by the part face it bounds and the
  segment that cut it. Such names are lasting (`AnchorNaming.isLasting`): a dimension on a cut edge is picked, resolved and held by DR-2's rules
  unchanged; a width change keeps it held; a line moved so that its cut no longer meets the part (that segment makes no face) or a part face
  gone loses it `.missing`, never re-attached to another cut's edge. Moving the line keeps names by segment index (the segments are the same;
  R2: the shape is never edited). In the
  section view, every projected line whose source edge borders a **step face** (a cut face of odd k) is left out (ISO 128-40: no line where the
  cut changes plane). Hatch regions are drawing only: never anchors, never picked, and their strokes carry no `source`. Cost: none.
- **R5. Hatching** (ISO 128-50; `HatchRegion`, `HatchPattern`). Regions come from `Kernel.section` of the **original** solid by each cut's plane
  (`Plane(origin: frame point of p_k, normal: s₃, xAxis: t₃)`, tolerance `0.01 / scale`), placed in the section's frame, each kept with the
  **band** of its cut (`HatchBand.bands(for: cutter)`, one per cut): along the section view's axis that holds t′ (x when the line reads
  horizontally, y when vertically, R3), with `a_k = (r p_k.x + u p_k.y) · t′` the position of point k in the section view's model plane, cut k
  (segment k, from p_k to p_(k+1)) holds `[min(a_k, a_(k+1)), max(a_k, a_(k+1))]`; the band of cut 0 is open on p0's side and the band of the
  last cut on pn's side (the bound nearer that end's position becomes nil: low when that end's position is the smaller, high when it is the
  larger), so a line drawn right to left or top to bottom (t₂.x < 0 or t₂.y < 0, whose first cut sits at the high end, R3) opens the right ends;
  a straight line's one band is open both ways. Only `SectionRegion.boundary` polylines are used (even-odd), so loops may come in any order and
  the region's triangles (the existing triangulator's fill, which the 3D section cap draws) are not needed for lines.
  **Sheets are never sectioned** (as the 3D cap, `SectionCapModel.follow`, filters them): `Kernel.section` is called only for a solid value
  with no open shell (`!hasOpenShell`); a value that is only sheets (`hasOpenShell && !holdsClosedSolid`) gets no regions and no kernel call,
  so a cut sheet shows its cut edge (the remainder's boundary, projected) and no hatch. A value that holds a closed solid beside a sheet
  (`hasOpenShell && holdsClosedSolid`; no kernel call separates them, NS-5's parked node) is sectioned whole, and a region is kept only when
  every piece of its boundary has a `sourceFace` that is not `isOnOpenShell` in the value's topology (a piece with no `sourceFace` drops its
  region), so only the closed solid is hatched. A `Kernel.section` that throws leaves that part unhatched (its remainder still drawn) with the
  warning, exact, said once per view: "The cut faces of a part couldn't be hatched." Lines are drawn in sheet millimetres: thin
  (`style.thin`), solid, layer `.hatch`, view the section, `source` nil; in the part's direction from the sequence 45°, 135°, 30°, 120°, 60°,
  150° by the solid's index in the Output's solids (repeating), each **an exact constant, never `sin` or `cos`** (`HatchPattern.direction(forPart:)`:
  45° `(√½, √½)`, 135° `(−√½, √½)`, 30° `(√3/2, 1/2)`, 120° `(−1/2, √3/2)`, 60° `(1/2, √3/2)`, 150° `(−√3/2, 1/2)`, with `√½ = (0.5).squareRoot()`
  and `√3/2 = (3.0).squareRoot() / 2`, which IEEE 754 rounds the same on every platform, so the hatched page's bytes match on Darwin, glibc and
  MSVC); spaced `DrawingStyle.hatchSpacing(for: sheet.size)` (2.5 mm when `!size.isLarge`, 4 mm when `size.isLarge`, as `notesHeight` decides:
  A4, A3, ANSI A and B take 2.5, A2 to A0 and ANSI C to E take 4; both standards) on the lines `n · x = j × spacing` (n the unit normal of the
  direction, x the sheet point), so the regions of one part line up
  across a step and the phase never depends on the view's position; each line's inside pieces by even-odd crossing, then cut to the band (and
  to every circle in a detail's `hatchClips`, R8: a piece is kept only inside all of them). A region no line crosses gets one line through the middle of its extent across the lines. Order: solids, then cuts,
  then regions as `Kernel.section` gives them, then j ascending, then pieces along the line: deterministic. One region set per solid; every
  solid hatched at its own angle (decision: "each solid of a multi-solid Output"). Cost: thin areas filled solid (ISO's option for walls under
  2 mm) are parked.
- **R6. Marks on the parent** (`SectionMarks`, `SectionMarkStyle.of(standard)`, sheet mm):

  | Constant | ISO 128-40 | ASME Y14.2 / Y14.3 |
  |---|---|---|
  | chain width (whole line) | `thin` 0.25 | `thick` 0.6 |
  | thick end length (from each end inward) | 5 | 0 (the whole line is thick) |
  | thick length each side of a step's corner | 3 | 0 |
  | `arrowShaft` (from the end, along the viewing direction) | 7 | 8 |
  | `letterGap` | 1 | 1.5 |
  | `viewArrowGap` (auxiliary arrow tip to the edge) | 2 | 2 |

  The cutting-plane line is the stored points through the parent's mapping, a `.centre`-pattern stroke on `.center`, with thick solid pieces
  (`thick`, pattern `.solid`, **also on `.center`**: the cutting line is one layer in CAD) at its ends and corners as the table says. So that CAD
  draws them solid, `DXFWriter`'s `begin` writes group 6 `Continuous` (the LTYPE table's existing record) for a `.solid` stroke on a layer whose
  linetype is not Continuous (CENTER or HIDDEN), as it already writes `DASHED` or `CENTER` for a patterned stroke off its own layer. That also
  fixes DR-2's small centre marks (`.solid` on `.center`, drawn solid on screen and in the PDF but chained in CAD: the same bug), and changes the
  DXF digest of `DrawingFixtures.a4Sheet` (its solid CENTER stroke), which Task 6 re-pins, its commit saying why; at each end a thin shaft on `.dimension` from the end along the viewing direction,
  `arrowShaft` long, a filled arrowhead of `AnnotationStyle.of(standard).arrowLength` at its far end pointing along it, and the view's letter
  (height `style.viewLabelHeight`, `.text`) centred `letterGap + h / 2` beyond the tip. A detail is a thin solid circle on `.dimension` of
  radius `r × parent scale`, its letter centred at `centre + (r × s + letterGap + h / 2) × (√½, √½)` (`SectionMarkStyle.letterDiagonal`, built
  with `(0.5).squareRoot()` as R5's directions are: no `sin` or `cos` anywhere in marks or hatch). An auxiliary view's arrow
  points along its viewing direction at the edge's stored midpoint m: shaft from `m − v × (viewArrowGap + arrowShaft)` to the tip `m − v ×
  viewArrowGap`, its letter centred `letterGap + h / 2` behind the tail. Every mark stroke, fill and text has `view` = the parent and `mark` =
  the derived view's id. Marks are drawn **only while the parent exists and its current frame equals the stored one** (sections and auxiliary
  views store it, R9); otherwise the derived view shows one notice, exact: "The view this section was cut from was deleted, so its cutting line
  isn't shown." / "The view this section was cut from now looks another way, so its cutting line isn't shown." / "The view this auxiliary view
  was projected from was deleted, so its arrow isn't shown." / "The view this auxiliary view was projected from now looks another way, so its
  arrow isn't shown.". The detail view draws its boundary: a thin solid circle on `.dimension` of radius `r × detail scale` round its centre
  (`mark` = the detail). ASME's cutting-plane line uses the `.centre` pattern (Y14.2 draws a phantom line; a phantom linetype is parked).
- **R7. Letters and labels.** A derived view gets a letter when it is made, stored in `DrawingView.letter`: the first not used by another view on
  the sheet in `A … Z` without I, O and Q, then `AA, AB, …` (`ViewLetters`). Letters never renumber when other views come and go; a sheet
  decoded with a repeated or missing letter keeps the first by `ViewID` order and gives the others the next free ones; a duplicated sheet keeps its
  letters (another sheet). Labels (`ViewLabel.text`), always with the view's scale: "SECTION A-A (1 : 1)", "DETAIL B (5 : 1)", "VIEW C (1 : 1)"
  (ASME "SECTION A-A (1:1)"); derived views are made with `showsLabel` on. Cost: a deleted section leaves a gap in the letters.
- **R8. Details.** `DetailCircle { parent: ViewID; center: Vector2; radius: Double }` in the parent's model plane. The detail's content is the
  parent's content clipped (`DetailClip`), so there is no new hidden-line run: lines exactly (a line stays a line, an arc an arc, an ellipse an
  elliptic arc, a polyline a polyline), the parent's topology, warnings and problem carried, `framing` the circle's square (R10's `ViewContent.framing`),
  hatch regions carried with `hatchClips` = the parent's `hatchClips` plus this circle (`ViewContent.hatchClips: [HatchClip]`, default empty):
  the regions are carried unclipped, so a detail of a detail whose inner circle reaches past the outer one still stops its hatch at the outer
  circle (lines need no such list: the inner detail clips the outer detail's already clipped lines). The clip keeps the pieces whose middle is inside or on the circle, drops pieces under
  1e-9 mm, and finds an ellipse's crossings by sampling (256 steps per full turn, at least 16) and bisecting to 1e-12 rad. A detail's source and
  orientation are kept equal to its parent's (setting a parent's orientation sets its details' in the same step, recursively), so every reader
  of `view.orientation.frame` and `view.source` stays right. **Source carries to every derived view** (R10): setting a view's source sets the
  source of all its descendants (details, sections, auxiliary views, theirs too) in the same step, since a section's or an auxiliary view's
  Source is not editable (the inspector hides it) and its cutting line or arrow, whose frame still matches, would otherwise be drawn over a part
  the derived view no longer shows. Orientation carries to details only: a section or auxiliary view keeps its stored frame and its parent's
  turn hides its marks with R6's notice. Default scale: the smallest of `DrawingScale.preferred` at least twice the parent's,
  else 50 : 1. With no parent: no projection, problem "The view this detail enlarged was deleted." (DR-2 R25 state 1: its annotations are listed,
  not drawn). Polylines (curved silhouettes) keep the parent's chord tolerance, magnified: 0.01 mm × detail scale / parent scale on paper. Cost:
  a 5 : 1 detail of a 1 : 1 view shows chords up to 0.05 mm.
- **R9. Auxiliary views.** Picked on one straight edge of a non-pictorial parent (`AuxiliaryRule.arrow(for:click:topology:frame:)`): the
  candidate must be an edge whose `EdgeInfo.curve` is `.line`, else "An auxiliary view looks square to a straight edge; pick a line."; the line
  must be square to the parent's view (decision 4's test, 1e-9 relative), else "This edge isn't square to the view, so a view square to it wouldn't
  show its true size."; a free curve, a face outline or nothing: the first sentence. A `.corner(id, at:)` candidate (which
  `DrawingPick.candidate` returns before `.edge` for a click near a line's end) picks its edge `id` exactly as `.edge(id, stroke:)` does, and
  is then held to the same two tests, so a click near the end of a short line picks that line; a `.centre` candidate is refused with the first
  sentence (a centre is no line). The stored `AuxiliaryArrow { parent; parentFrame; at
  (the edge's midpoint, model plane); viewing }` keeps what was picked; the edge itself is not kept, and the frame is R3's with t₂ the edge's
  direction, stored (decision 1). The side by R3's σ rule against the edge's line. Auxiliary views are free (never aligned), labelled "VIEW C".
  Cost: an edit that turns the inclined face leaves the view looking the old way; its dimensions then turn lost `.foreshortened`, never a wrong
  number.
- **R10. Derived views and their parents.** `ViewKind` gains `section`, `detail`, `auxiliary`; `DrawingView.derivation: ViewDerivation?` (`case
  section(SectionLine)`, `detail(DetailCircle)`, `auxiliary(AuxiliaryArrow)`, `SectionLine { parent: ViewID; cutter: SectionCutter }`) is set
  exactly for those kinds. A derived view's parent is on its sheet. Parents: a section's or an auxiliary view's is any view that is not pictorial
  (R11) and not a detail; a detail's is any view (a detail of a section clips its hatch). Moving a parent carries its derived views: aligned
  sections slide as projected views do, free derived views (details, auxiliary views, slanted sections) move by the same delta
  (`ViewPlacement.moving`). Deleting a parent keeps its derived views (aligned ones freed): sections and auxiliary views keep working from their
  stored data with R6's notice, a detail loses its content with R8's sentence; undo brings the parent back. Duplicating a sheet remaps every
  `derivation.parent`. Setting a view's source carries to all its descendants and its orientation to its details (R8), each in the one step.
  **No derivation cycles**: the editor never makes one (a derived view is made on an existing parent and a derivation is never re-parented except
  by the sheet copy's remap), decoding breaks any a damaged file holds (R12), and every walk up or down the parents (the session's
  parents-before-children order, R14's nearest non-detail ancestor, `ViewPlacement`'s carried descendants, `DrawingSheet.isPictorial`, the
  source and orientation carries) also keeps a visited set and stops at a view it has seen, so a cycle can never loop. A standard switch keeps every derived view's content (decision 1): aligned sections mirror across their parent as
  projected views do, free ones stay. `ViewContent.framing: Rect2D?` (model plane; nil: the projection's bounds) is what a view centres on:
  `ViewMapping.of(content:center:scale:)` and `ViewLinework.frame(for content:center:scale:)` replace the projection-based calls at every site
  that maps a view (the composer, `AnnotationPass`, the editor's pick context, the export, the projector's `lastSize`).
- **R11. Pictorial views take no dimensions; sections and auxiliary views do.** Whether a view is pictorial needs its sheet (a detail copies its
  parent's orientation, which for a detail of an auxiliary view or of a slanted section is a `.custom` frame along no axis, and
  `ViewOrientation.isIsometric` reads every such frame as isometric), so the predicate is `DrawingSheet.isPictorial(_ view: DrawingView) -> Bool`,
  not a member of `DrawingView`: false for every section and auxiliary view; `orientation.isIsometric` for a base or projected view; for a detail,
  its parent's `isPictorial`, recursively (R10's visited set; a cycle reads false), and its own `orientation.isIsometric` when its parent is not on
  the sheet. Every DR-2 site that read `orientation.isIsometric` to refuse dimensions reads it (the editor's `PickContext` stores `isPictorial`,
  computed from the sheet when the context is made), so an auxiliary view of an inclined face, and a detail of it, take dimensions at true
  length (decision 4) though their custom frames run along no axis. **Base and projected views always look along an axis or are isometric**:
  `ProjectedViewRule.refusal(for:)` refuses a pictorial parent with its sentence, a detail parent with "A projected view comes from a whole view,
  not a detail.", and a section or auxiliary view whose frame runs along no axis (a slanted section, an auxiliary view; `orientation.isIsometric`
  of its custom frame) with "A projected view comes from a view that looks along an axis, not from an auxiliary view or a slanted section."
  (exact); a straight section's frame runs along an axis (R3), so a projected view of it is allowed and gets an axis frame. So `isIsometric`
  stays right for base and projected views, and no projected view is ever pictorial by accident. Cost: a projection of an auxiliary view
  (a secondary view folded off it) needs another auxiliary view instead. A section or auxiliary tool on a pictorial parent: "A section or
  auxiliary view is taken from a front, side, top, bottom, section or auxiliary view, not an isometric one."; the Section tool on a detail:
  "Draw the cutting line on the view the detail enlarges."; the Auxiliary tool on a detail, exact: "Pick the edge for an auxiliary view on the
  view the detail enlarges."
- **R12. File format 19.** Format 18 decodes `ViewKind` from a fixed list and would refuse the new kinds with a generic error, so the version is
  bumped and an older build gives its "newer file" refusal. `ViewDerivation` is coded as a keyed container with a `type` string ("section",
  "detail", "auxiliary"), never Swift's synthesized `_0` form; `derivation` and `letter` are written only when present. Decoding drops a derived
  view whose derivation is missing or of the wrong case (its annotations go with it), drops a derivation on a base or projected view, breaks
  derivation cycles, repairs letters (R7) and a section's orientation (R3). **Cycles** (as `repairingAlignments` frees aligned cycles): after the
  drops above, decoding walks each derived view's `derivation.parent` chain over the views on the sheet; a view whose chain returns to a view
  already on it (a view that is its own parent, or A ← B ← A) closes a cycle, and the cycle's member with the lowest `ViewID` is dropped with
  its annotations; the walk repeats until no cycle is left. So A ← B ← A keeps one of the two, whose parent is now missing and reads as a
  deleted parent (R10: a section or auxiliary view keeps working with R6's notice, a detail shows R8's sentence). A parent not on the sheet is
  left as it is (a deleted parent, R10). Cost: a damaged file loses one view per cycle; no build writes one. `GraphFile`'s comment gains "19: DR-3's section, detail and auxiliary views (`derivation`,
  `letter`); a version-18 reader cannot decode the new view kinds."
- **R13. Tools, keys, steps and inspector.**
  - `DrawingTool`: `section`, `detail`, `auxiliaryView` after `projectedView` (titles "Section", "Detail", "Auxiliary"); keys S, E and U over the
    sheet canvas with nothing focused, as D, H, M, L and N work. `DrawingKey.finish` (Return) finishes a cutting line.
  - **Section:** the first click on a view (not pictorial, not a detail) starts the line there (`sectionDraft`, the parent fixed); each click adds a
    point, snapped first to a corner or circle centre under the pointer (`DrawingPick.candidate`'s `.corner` / `.centre`, within the hover
    tolerance), then to R3's 5° snap for the first segment, then constrained (a cut moves only along t₂ from the last point, a step only along
    n₂). A click on the last point (within the hover tolerance) or Return finishes; finishing with an even count of segments refuses "A stepped
    cutting line ends with a cut, not a step." and keeps the draft; a cut that would run against the first refuses with R2's sentence. The next
    click places the view: R3's side and frame, the parent's scale, `showsLabel` on, centre the click (aligned: snapped to the parent's coordinate),
    one "Add View" step, the new view selected. Esc drops the draft, then the tool.
  - **Detail:** a press on a view sets the centre (snapped as above), the drag sets the radius, the release keeps the circle (`detailDraft`); a
    radius under 2 sheet mm refuses "Drag out the detail's circle from its centre."; the next click places it ("Add View", R8's default scale).
  - **Auxiliary:** a click on a line of a view, or near its end (a `.corner` candidate, R9), picks the edge (R9's refusals; on a detail R11's
    Auxiliary sentence); the next click places it ("Add View").
  - A parent with no projection refuses "This view has nothing drawn to cut yet." (Section), "… to enlarge yet." (Detail), "… to project from
    yet." (Auxiliary).
  - Select: a press on a mark selects its derived view and a drag moves the mark (the cutting line or the detail circle, by the motion in the
    parent's model plane; an auxiliary arrow does not move): one coalesced step "Move Cutting Line" / "Move Detail Circle"; arrows nudge a
    selected derived view as a view. The selection layer draws a selected derived view's marks in the highlight colour.
  - `DrawingStepName` gains "Move Cutting Line", "Move Detail Circle" and "Change Detail Circle" (`setDetailRadius(_:of:)`, typed in the
    document's unit, refused "A detail's radius is a length greater than 0."); placing any derived view is "Add View"; the label and display
    flags stay "Change View"; a detail's scale "Change Scale". A setter whose value equals the current one commits nothing.
  - Inspector: a derived view's page shows its title ("Section A-A", "Detail B", "View C"), Scale, the display flags and Label; a detail adds
    Radius; a section shows "Straight" or "Stepped (N cuts)" (read only); Source and Orientation show only for base and projected views.
  - `replaceDocument(_:)` drops a section or detail draft and a picked auxiliary edge whose parent is gone or whose sheet changed.
- **R14. The session** (`DrawingSession`). A section view's `RequestKey` holds its `cutter`; the projector cuts each solid through
  `ProjectionCache.sectionCut(of:index:cutter:tolerance:kernel:)` (keyed by the solid's identity, index, cutter and tolerance; the entry keeps
  the solid alive and counts its remainder's and regions' bytes against the cache's limit, LRU with the rest), projects the remainders (several:
  one compound, `compoundTag` as today), drops R4's step lines and carries the regions as `ViewContent.hatch`. Curves on a section's Output are
  left out with the warning "This section leaves out the Output's curves; a section shows what the cut leaves of solids and sheets."; all
  solids cut away: problem "The cutting line leaves nothing of the part on the side it looks toward.". Details are computed on the main actor
  whenever their parent's content or circle changes (a per-view content generation), parents before children; auxiliary views are requested as
  any view. Pulled from the backlog: `update()` prunes `wanted`, `applied`, `flights` (cancelled), generations and `editor.contents` of views on no
  sheet, and `RequestKey` retains its curves as it does its solids. The refresh of last good values (DR-2 R26) reads a section against its cut
  remainders (the same cache entries) and its section frame, a detail as its nearest non-detail ancestor reads (that view's cutter, if any, and
  frame), an auxiliary view against its own frame. Hatch regions follow R5's sheet rule: the cache entry of a value with an open shell and no
  closed solid holds no regions and makes no `Kernel.section` call; a mixed value's regions are filtered by `sourceFace`.
- **R15. Export.** Hatch, marks and labels are in the picture, so the PDF and the DXF of the sheet carry them (DXF: hatch as LINE entities on
  HATCH, deterministic; a DXF HATCH entity is parked; the cutting line on CENTER, its thick ends with `6 Continuous`, R6). The DXF of a view at 1:1 stays the projection only (a detail's is its clipped
  projection); "with annotations" adds the view's hatch, its detail boundary and the marks it carries for other views, mapped back by its
  mapping as annotations are.
- **R16. Performance.** Cuts are cached per solid identity (R14), so a pan, a zoom or an edit elsewhere cuts nothing. Benchmark row `drawing-4`:
  a straight section through the bracket's holes from cold (cut, hatch regions and projection; cache emptied, 10 runs), target under 1 s as
  `drawing-1`; a loaded Mac's numbers are recorded as saturated, never as a verdict.
- **R17. Parked.** Break lines (a shortened view whose dimensions still read true needs a split mapping through DR-2's layout: not cheap), half and
  broken-out sections, aligned (revolved) sections, flipping a section's arrows in place, rotating a view to its projection direction, editing
  a letter, a phantom linetype, DXF HATCH entities, thin areas filled solid, hatch angle and spacing per region, and a stepped line's points
  anchored to the model.

**Review revisions** (the plan review of 2026-11-26; each is ruled in the R it names):
- A cutting line is moved, never reshaped (R2, R4, R13); the lost-cut test and check DR3-6 move a stepped line until its last cut leaves the part.
- The auxiliary-view test uses a hole square to the inclined face, which only the auxiliary view sees face on (Task 9).
- `isPictorial` lives on `DrawingSheet` (a detail reads its parent's); projected views of auxiliary views and slanted sections are refused (R11).
- Hatch bands open at the line's own ends, whichever way it was drawn (R5, `HatchBand.bands`).
- The thin-region fixture lies between two hatch lines (Task 3).
- The section-cut hook is async (Task 2).
- The cutting line's thick ends are `.solid` on CENTER and the DXF writes `6 Continuous` for them, fixing DR-2's small centre marks too (R6).
- Sheets are never sectioned; a mixed value is hatched on its closed solid only; a failed section warns (R5).
- Derivation cycles are broken on decode and every parent walk keeps a visited set (R10, R12).
- A detail of a detail keeps every ancestor's circle for its hatch (R8, `hatchClips`).
- The Auxiliary tool on a detail has its own sentence (R11); a `.corner` candidate picks its line (R9).
- Hatch spacing follows `SheetSize.isLarge` (R5); hatch directions and the detail letter's diagonal are exact constants (R5, R6).
- Source carries to every derived view (R8, R10); `cutAway`'s `tag` is the tool's tag and the result's name (R1).

**Backlog.** Pulled in: `DrawingSession` pruning of `applied`, `wanted` and `flights` and retaining curves in `RequestKey` (R14: section and
detail views add requests). **Stay parked:** HoleReader's full circle split into two π arcs (section remainders cut holes into half circles,
which are never callouts; face-on holes are DR-2's case), `SheetSegment.transformed` mirroring (no DR-3 view mirrors: scales stay positive and
views never rotate), and every other DR-1 and DR-2 parked item in `.superpowers/sdd/2026-11-26-dr-3-sections-details/backlog.md` and CLAUDE.md.

## Review Focus

1. **A model edit under a dimension on a cut edge.** A width change keeps it held at the new value; moving a stepped line until the cut that made
   the edge leaves the part loses it with "?" and `.missing`, never re-attached to another cut's edge (a line's shape is never edited, R2). Task 2 (`cutFacesCarryTheCuttersNames`), Task 9
   (`aCutEdgeDimensionFollowsAWidthChange`, `aCutEdgeDimensionIsLostWhenItsCutLeavesThePart`).
2. **Cutting lines that miss, swallow or graze the part.** A line clear of the part gives the uncut view, one that leaves nothing gives the
   problem sentence, one through a hole's axis or along a face gives a valid solid or the refusal sentence, never an invalid shape. Task 2
   (`aLineThatMissesReturnsTheSolid`, `aLineThatSwallowsReturnsNil`, `aCutThroughAHoleAxisIsValid`, `aCutAlongAFaceIsValidOrRefused`), Task 4
   (`everythingCutAwayIsAProblem`).
3. **Details that cross arcs, ellipses and polylines, and details of sections.** Exact kinds survive the clip, nothing is drawn outside the
   circle, a wholly inside or outside curve is kept or dropped whole, and a section's hatch stops at the circle. Task 5 (`anArcStaysAnArc`,
   `anEllipseIsCutAtItsCrossings`, `nothingLiesOutsideTheCircle`, `hatchStopsAtTheCircle`).
4. **The parent goes away or turns.** Delete, undo, a changed orientation, a standard switch and a duplicated sheet: derived views keep working
   with the exact notice, letters stay, parents are remapped, undo restores marks, a damaged file's derivation cycle is broken. Task 1
   (`duplicatingRemapsParents`, `lettersRepairOnDecode`, `derivationCyclesAreBroken`),
   Task 6 (`aTurnedParentHidesTheCuttingLine`, `aDeletedParentLeavesANotice`), Task 7 (`deletingAParentKeepsItsSections`), Task 9
   (`undoBringsTheCuttingLineBack`).
5. **Several solids, a sheet, curves.** Each solid hatched at its own angle, a sheet never sectioned and its cut edge drawn with no hatch, a
   value holding a solid and a sheet hatched on its solid only, curves left out with the warning. Task 3 (`eachSolidHasItsOwnAngle`), Task 4
   (`aSheetIsNeverSectioned`, `aSheetIsCutButNotHatched`, `aMixedValueHatchesOnlyItsSolid`, `curvesAreLeftOutWithAWarning`).
6. **An auxiliary view of an inclined face, a slanted section, and details of them.** Dimensions are allowed (not refused as isometric) and
   measure true size; a projected view of either is refused. Task 1 (`isPictorialRule`), Task 7 (`anAuxiliaryViewTakesDimensions`,
   `aDetailOfAnAuxiliaryViewTakesDimensions`, `aProjectedViewOfAnAuxiliaryViewIsRefused`), Task 9 (`aHoleSquareToTheInclinedFaceReadsTrueInItsAuxiliaryView`).
7. **Hatch that must match everywhere.** Bands open at the line's own ends whichever way it was drawn; directions from exact constants, so the
   hatched page's digest is one on every platform; the cutting line's thick ends solid in CAD. Task 3 (`bandsFollowTheLinesEnds`,
   `directionsAreExactConstants`), Task 6 (`hatchedPageDigest`, `theThickEndsAreContinuousInDXF`).

---

### Task 1: Derived views in the model and file format 19

**Files:**
- Create: `Sources/CreatorKernel/Section/SectionCutter.swift` (the type, `toolNode`, `validate()`, `removedPolygon(reach:)`; R2),
  `Sources/CreatorDrawing/Model/ViewDerivation.swift` (`SectionLine`, `DetailCircle`, `AuxiliaryArrow`, `ViewDerivation` and its coding),
  `Sources/CreatorDrawing/Model/ViewLetters.swift`, `Sources/CreatorDrawing/Sections/SectionFrame.swift` (R3; the decoder repairs a section's
  orientation with it)
- Modify: `Sources/CreatorDrawing/Model/DrawingView.swift` (kinds, `derivation`, `letter`), `DrawingSheet.swift` (decode repairs and
  derivation cycles, R12; `isPictorial(_:)`, R11), `Sources/CreatorGraph/GraphFile.swift` (19 and its comment), `Sources/CreatorDrawingEditor/DrawingEditorModel+Sheets.swift`
  (`duplicateSheet` remaps `derivation.parent`)
- Test: `Tests/CreatorKernelTests/SectionCutterTests.swift`, `Tests/CreatorDrawingTests/ViewDerivationTests.swift`,
  `Tests/CreatorDrawingTests/ViewLettersTests.swift`, `Tests/CreatorDrawingTests/SectionFrameTests.swift`, `Tests/CreatorGraphTests/DrawingsFileTests.swift` (additions),
  `Tests/CreatorDrawingEditorTests/SheetEditingTests.swift` (addition)

**Interfaces:**
- Produces:
  - `public struct SectionCutter: Hashable, Sendable, Codable { public var frame: ProjectionFrame; public var points: [Vector2]; public var viewing:
    Vector2 }` with `public static let toolNode: NodeID` (R4's UUID), `public var direction: Vector2` (the first segment's unit direction),
    `public var cutIndices: [Int]` (0, 2, 4, …), `public func validate() throws(KernelError)` (R2's sentences, `.invalidInput`) and `public func
    removedPolygon(reach: Double) -> [Vector2]` (R2's polygon, plane coordinates; vertex k to k + 1 is the line's segment k for k below its count).
  - `public struct SectionLine: Hashable, Sendable, Codable { parent: ViewID; cutter: SectionCutter }`, `public struct DetailCircle: Hashable,
    Sendable, Codable { parent: ViewID; center: Vector2; radius: Double }`, `public struct AuxiliaryArrow: Hashable, Sendable, Codable { parent:
    ViewID; parentFrame: ProjectionFrame; at: Vector2; viewing: Vector2 }`, `public enum ViewDerivation: Hashable, Sendable, Codable { case
    section(SectionLine), detail(DetailCircle), auxiliary(AuxiliaryArrow) }` with `var parent: ViewID` and `func withParent(_: ViewID) -> Self`.
  - `ViewKind` cases `section`, `detail`, `auxiliary`; `DrawingView.derivation: ViewDerivation?`, `letter: String?` (init parameters with nil
    defaults); `DrawingSheet.isPictorial(_ view: DrawingView) -> Bool` (R11: a detail reads its parent's, recursively, with a visited set).
  - `ViewLetters.letter(at index: Int) -> String` (0 "A", 7 "H", 8 "J", 22 "Z", 23 "AA") and `ViewLetters.next(on sheet: DrawingSheet) -> String`.
  - `SectionFrame.frame(parent: ProjectionFrame, along t: Vector2, viewing v: Vector2) -> ProjectionFrame`, `SectionFrame.frame(for cutter:
    SectionCutter) -> ProjectionFrame`, `SectionFrame.viewing(along t: Vector2, from origin: Vector2, drop: Vector2, standard: DrawingStandard) ->
    Vector2`, `SectionFrame.alignment(along t: Vector2) -> AlignmentAxis?` (R3).
  - `GraphFile.currentFormatVersion == 19`.

- [ ] **Step 1: Tests.**
  - `SectionCutterTests`: `aStraightLineIsValid`; `oneSegmentAfterAnotherMustAlternate` (cut, cut is refused with the alternate sentence; cut,
    step, cut is valid); `anEvenCountIsRefused`; `aCutAgainstTheFirstIsRefused`; `aSlantedStepIsRefused`; `pointsMustBeApart`;
    `viewingMustBeSquare`; `thePolygonFollowsTheLine` (points (0,0),(10,0),(10,5),(20,5), viewing (0,1), reach 100: vertices (−100,0), (10,0),
    (10,5), (120,5), (120,−95), (−100,−100)); `codableRoundTrip`; `theToolNodeIsFixed` (its UUID string).
  - `ViewDerivationTests`: `everyCaseRoundTripsByType` (JSON of each case has `"type"` and no `"_0"`); `aDerivedViewWithoutItsDataIsDropped`
    (and its annotations); `aBaseViewDropsAStrayDerivation`; `aSectionsOrientationIsRepaired` (a saved section whose orientation disagrees with
    its cutter decodes with `.custom(SectionFrame.frame(for:))`); `isPictorialRule` (`DrawingSheet.isPictorial`: an isometric base view and a
    detail of it are pictorial; a Front base view, a section, an auxiliary view with a slanted custom frame, a detail of that auxiliary view, a
    detail of a slanted section and a detail of that detail are not; a detail whose parent is not on the sheet reads its own orientation:
    pictorial with an off-axis `.custom` frame, not with Front's); `derivationCyclesAreBroken` (a detail whose parent is itself: dropped with its
    annotations; A ← B ← A: the lower `ViewID` dropped, the other kept with its parent missing; a chain C ← D with no cycle kept whole; a
    section whose parent is not on the sheet kept).
  - `SectionFrameTests`: `aStraightSectionMatchesTheProjectedView` (Top parent; horizontal and vertical lines, both sides, both standards: equal to
    `ProjectedViewRule.view` for the drop on that side); `aSlantedLineReadsHorizontally` (30° line: the frame's right is the line's 3D direction);
    `aSteepLineReadsVertically` (70°: up is the line's direction); `firstAngleLooksTowardTheDrop`, `thirdAngleLooksAway`;
    `alignmentByDirection` (horizontal → `.vertical`, vertical → `.horizontal`, slanted nil); `framesAreUnitAndSquare` (500 random lines).
  - `ViewLettersTests`: `skipsIOQ` (the 23 letters); `doubleLettersFollowZ`; `nextIsTheFirstFree` (A and C used: B); `lettersRepairOnDecode` (two
    views lettered "A": the lower `ViewID` keeps it, the other gets "B"; a derived view with none gets the next free).
  - `DrawingsFileTests`: `aFormat18FileOpensAndIsWrittenAs19`; `aNewerFileIsRefused` (20); `derivedViewsRoundTrip`.
  - `SheetEditingTests`: `duplicatingRemapsParents` (a section and a detail of a base view: the copy's derivations name the copied base view;
    letters kept).
- [ ] **Step 2: Run** `swift test --filter 'SectionCutterTests|ViewDerivationTests|ViewLettersTests|SectionFrameTests|DrawingsFileTests|SheetEditingTests'`;
  compile failure.
- [ ] **Step 3: Implement** R2, R3's frame rule, R7, R10's model, R11's predicate and R12.
- [ ] **Step 4: Run** the filter, then `swift test --filter CreatorDrawingTests`, `--filter CreatorKernelTests`, `--filter CreatorGraphTests`,
  `--filter CreatorDrawingEditorTests`; pass.
- [ ] **Step 5: Commit** "Drawings: section, detail and auxiliary views in the model, file format 19".

### Task 2: `Kernel.cutAway`, and OCCT's cut

**Files:**
- Modify: `Sources/CreatorKernel/Kernel.swift` (the requirement and its default), `Sources/CreatorKernel/FakeKernel.swift` (stored hook),
  `Sources/CreatorKernel/FakeKernel+Section.swift` (`setSectionCutHook`, `cutAway`)
- Create: `Sources/CreatorOCCT/OCCTKernel+SectionCut.swift`
- Test: `Tests/CreatorKernelTests/FakeKernelSectionCutTests.swift`, `Tests/CreatorOCCTTests/SectionCutTests.swift`

**Interfaces:**
- Consumes: Task 1's `SectionCutter`.
- Produces: `func cutAway(_ solid: Solid, by cutter: SectionCutter, tag: NodeTag) async throws -> Solid?` on `Kernel` (default and
  `KernelUnavailable`: `KernelError.unsupported("cutting sections")`); `FakeKernel.setSectionCutHook(_ hook: (@Sendable (Solid, SectionCutter,
  NodeTag) async throws -> Solid?)?)`, **async** as `setProjectionHook` and `setSectionHook` are, so a test can hold a cut on a `HookGate` and
  never block a pool thread (with no hook it validates the cutter, then refuses as the default does).

- [ ] **Step 1: Tests.**
  - `FakeKernelSectionCutTests`: `refusesWithoutAHook` (the unsupported sentence's phrase "cutting sections"); `aHookAnswers` (it receives the
    solid, the cutter and the tag passed); `aHookCanSuspend` (a hook awaiting a `HookGate` holds the call until the gate opens; nothing blocks);
    `anInvalidCutterIsRefusedFirst`. (`HookGate` lives in `Tests/CreatorAppTests/Support`; this test uses a local `AsyncStream` continuation
    as its gate rather than moving the type.)
  - `SectionCutTests` (OCCT, a 40 × 20 × 10 box at the origin, the Top frame, `tag` `NodeTag(node: SectionCutter.toolNode, item: 0)`):
    `aStraightCutKeepsTheFarSide` (points (−5, 5), (45, 5), viewing (0, 1): the remainder's bounds y from 5 to 20, volume 6000 within 1e-6);
    `aSteppedCutLeavesTheStep` (points (−5, 5), (20, 5), (20, 15), (45, 15), viewing (0, 1): volume 20 × 15 × 10 + 20 × 5 × 10 = 4000 within 1e-6); `cutFacesCarryTheCuttersNames` (each cut face's tags include `TopoTag(node: toolNode, item: 0, role:
    .side(loop: 0, segment: k))` for its segment, and a cut edge's key has one part-face side and one cut side, lasting by
    `AnchorNaming`-equivalent check: no `.unnamed` role); `aLineThatMissesReturnsTheSolid` (the same `Solid` instance, no boolean);
    `aLineThatSwallowsReturnsNil`; `aCutThroughAHoleAxisIsValid` (a box minus a cylinder along z, the line through the axis: valid, remainder
    volume half the holed box); `aCutAlongAFaceIsValidOrRefused` (the line on the box's face y = 0: the whole box, or the refusal sentence, never
    an invalid solid); `aSheetIsCut` (a planar sheet 40 × 20: the remainder is a sheet whose new boundary edge lies on the line);
    `cancelledBeforeTheBoolean` (a cancelled task throws `CancellationError`).
- [ ] **Step 2: Run** `swift test --filter 'FakeKernelSectionCutTests|SectionCutTests'`; fail.
- [ ] **Step 3: Implement** R1 exactly (the shortcuts, one serialized block for boolean, face count and validity, then `solid(from:…)`).
- [ ] **Step 4: Run** the filter, `--filter CreatorOCCTTests`, `--filter CreatorKernelTests`; pass.
- [ ] **Step 5: Commit** "Kernel: cutting a part away along a section line".

### Task 3: Hatching and the auxiliary rule (pure geometry)

**Files:**
- Create: `Sources/CreatorDrawing/Sections/HatchRegion.swift`, `HatchPattern.swift`, `AuxiliaryRule.swift`,
  `Sources/CreatorDrawing/Style/SectionMarkStyle.swift`
- Modify: `Sources/CreatorDrawing/Style/DrawingStyle.swift` (`hatchSpacing(for:)`)
- Test: `Tests/CreatorDrawingTests/HatchPatternTests.swift`, `AuxiliaryRuleTests.swift`, `DrawingStyleTests.swift` (addition)

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `public struct HatchBand: Hashable, Sendable { axis: AlignmentAxis /* .horizontal: along the view's x */; low: Double?; high: Double? }` (model
    plane) with `static func bands(for cutter: SectionCutter) -> [HatchBand]` (R5: one per cut, in the section frame's model plane, cut 0's open
    on p0's side, the last's on pn's side); `public struct HatchRegion: Hashable, Sendable { part: Int; edges: [[Vector2]]; band: HatchBand? }`
    (model plane polylines).
  - `public struct HatchClip: Hashable, Sendable { center: Vector2; radius: Double }` (model plane).
  - `HatchPattern.direction(forPart: Int) -> Vector2` (R5's sequence as exact unit constants built with `squareRoot()`; no `sin` or `cos`);
    `HatchPattern.strokes(_ regions: [HatchRegion], mapping: ViewMapping, clips: [HatchClip], spacing: Double, width: Double, view: ViewID) ->
    [SheetStroke]` (a piece kept only inside every clip).
  - `DrawingStyle.hatchSpacing(for: SheetSize) -> Double` (by `size.isLarge`, R5); `public struct SectionMarkStyle: Hashable, Sendable` with R6's
    constants, `letterDiagonal: Vector2` (`(√½, √½)`) and `static func of(_:) -> SectionMarkStyle`.
  - `AuxiliaryRule.arrow(for candidate: PickCandidate, click: Vector2, topology: Topology, frame: ProjectionFrame, mapping: ViewMapping) ->
    Result<(at: Vector2, along: Vector2), DrawingRefusal>` (R9; `at` the edge's midpoint and `along` its unit direction, model plane; `.edge` and
    `.corner` name their edge, `.centre`, `.outline` and nil are refused with the line sentence).

- [ ] **Step 1: Tests.**
  - `HatchPatternTests` (a 40 × 20 rectangle region, 1:1, mapping offset (100, 100), spacing 2.5): `linesAreAt45Degrees`; `phaseFollowsTheSheet`
    (moving the view by (0.7, 0) moves no line's `n · x` off a multiple of 2.5); `aHoleIsLeftEmpty` (a square hole loop: no piece inside it);
    `loopsInAnyOrder` (hole listed first: same strokes); `aBandCutsTheLines` (band x ≤ 120: no point beyond); `aClipStopsAtTheCircle`;
    `everyClipStops` (two circles, the second reaching past the first: no point outside either); `eachSolidHasItsOwnAngle` (parts 0 to 6:
    the directions of 45°, 135°, 30°, 120°, 60°, 150°, 45°, compared with `==` to the constants); `directionsAreExactConstants` (each direction's
    components equal `(0.5).squareRoot()`, `(3.0).squareRoot() / 2`, 0.5 and their negatives exactly, bit for bit, and each is unit within
    1e-15); `aThinRegionGetsOneLine` (a 1 × 1 square, part 0 at 45°, spacing 2.5, placed so its centre c on the sheet has `n · c = 1.25` modulo
    2.5: its extent across the lines, √2 ≈ 1.41, lies between two hatch lines, so no line crosses it; exactly one piece, through c along the
    lines' direction, ends on the square's boundary); `strokesAreThinOnTheHatchLayer` (layer `.hatch`, width given, source nil); `orderIsFixed`
    (two runs equal); `bandsFollowTheLinesEnds` (`HatchBand.bands`: the stepped line (−5, 5), (20, 5), (20, 15), (45, 15) on a Top parent and the
    same line drawn right to left, (45, 15), (20, 15), (20, 5), (−5, 5): both give a band open toward low x holding x ≤ 20 and one open toward high
    x holding x ≥ 20 in the section view's model plane; for the right-to-left line the low-open band is the last cut's; a straight line's band is
    open both ways; a 40 × 20 region cut to the right-to-left line's bands is hatched across its whole width).
  - `DrawingStyleTests` (addition): `hatchSpacingBySize` (A4 and ANSI A 2.5; A2 and ANSI D 4).
  - `AuxiliaryRuleTests` (fixtures from `TopologyFixtures`): `aSquareLineGivesItsMidpointAndDirection`; `aCornerPicksItsLine` (a `.corner`
    candidate at a short line's end gives that line's midpoint and direction); `aCentreIsRefused` (the line sentence); `aCircleIsRefused` (the
    line sentence); `aTiltedLineIsRefused` (R9's true-size sentence); `anOutlineIsRefused`.
- [ ] **Step 2: Run** `swift test --filter 'HatchPatternTests|AuxiliaryRuleTests|DrawingStyleTests'`; fail.
- [ ] **Step 3: Implement** R5 (scanlines in sheet mm after mapping each edge), R6's constants, R9's rule.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: hatching and the auxiliary rule".

### Task 4: Section content (the cut table, the projector, framing)

**Files:**
- Create: `Sources/CreatorDrawing/Sections/SectionMaker.swift` (one solid's cut and regions), `Sources/CreatorDrawing/Sections/SectionLines.swift`
  (R4's step-line filter)
- Modify: `Sources/CreatorDrawing/Projection/ProjectionCache.swift` (`sectionCut`), `DrawingProjector.swift` (the section branch, sentences),
  `Sources/CreatorDrawing/Views/ViewContent.swift` (`hatch`, `hatchClips`, `framing`), `Sources/CreatorDrawing/Layout/ViewMapping+Projection.swift`
  and `Sources/CreatorDrawing/Views/ViewLinework.swift` (the content-based calls, R10), and their callers: `Picture/SheetComposer.swift`,
  `Picture/AnnotationPass.swift`, `Sources/CreatorDrawingEditor/DrawingEditorModel+Picking.swift`, `Sources/CreatorApp/AppModel+DrawingExport.swift`
- Test: `Tests/CreatorDrawingTests/SectionContentTests.swift` (FakeKernel with a section-cut hook), `Tests/CreatorDrawingTests/ProjectionCacheTests.swift`
  (additions), `Tests/CreatorAppTests/SectionContentOCCTTests.swift` (`#if canImport(CreatorOCCT)`)

**Interfaces:**
- Consumes: Tasks 1 to 3.
- Produces:
  - `public struct SectionCutPiece: Sendable { remainder: Solid?; regions: [HatchRegion] }`; `ProjectionCache.sectionCut(of solid: Solid, index:
    Int, cutter: SectionCutter, tolerance: Double, kernel: any Kernel) async throws -> SectionCutPiece` (R14; regions in
    `SectionFrame.frame(for: cutter)`'s plane, `part` = index, a band per cut from `HatchBand.bands(for:)`; R5's sheet rule: no regions and no
    `Kernel.section` call for a value with an open shell and no closed solid, a mixed value's regions kept only when every boundary piece's
    `sourceFace` is on no open shell, a throwing `Kernel.section` giving no regions and `hatchFailed` true) and `public private(set) var cutCalls:
    Int`; `SectionCutPiece.hatchFailed: Bool`.
  - `ViewContent.hatch: [HatchRegion]` (default empty), `hatchClips: [HatchClip]` (default empty; R8), `framing: Rect2D?`; `ViewMapping.of(content: ViewContent, center:
    Vector2, scale: Double) -> ViewMapping?`; `ViewLinework.frame(for content: ViewContent, center: Vector2, scale: Double) -> Rect2D?`.
  - `SectionLines.droppingSteps(_ projection: Projection2D, topology: Topology) -> Projection2D`.
  - `DrawingProjector` statics `curvesLeftOutSentence`, `cutAwaySentence` (R14's sentences), `hatchFailedSentence` (R5's, said once per view
    when any piece has `hatchFailed`); `content(for:scale:source:previous:)` handles
    `.section` by R14 and keeps `previous` in its failure branches exactly as DR-2 R25 does (hatch travels with the projection).

- [ ] **Step 1: Tests.**
  - `SectionContentTests`: `theRemainderIsProjected` (hook returns a smaller box: the projection's bounds are the remainder's);
    `hatchComesFromTheSection` (FakeKernel's axis-plane section of the original box: one region, band set); `everythingCutAwayIsAProblem` (hook
    nil for every solid: problem `cutAwaySentence`, no projection); `curvesAreLeftOutWithAWarning`; `aRefusedCutKeepsThePreviousContent`
    (hook throws: previous projection, topology and hatch kept, problem the error's message); `stepLinesAreDropped` (a hand-built topology whose
    edge borders a face tagged `.side(loop: 0, segment: 1)` of `toolNode`: its line is gone, a segment-0 edge's stays); `aDetailFramingCentresOnTheCircle`
    (`ViewMapping.of(content:)` with `framing` maps the circle's centre to the view's centre); `aSheetIsNeverSectioned` (a hand-built `Solid`
    whose every face `isOnOpenShell`, the cut hook returning it: a section-hook counter stays 0, `hatch` empty, the remainder projected);
    `aFailedSectionLeavesThePartUnhatched` (the section hook throws: remainder projected, `hatch` empty, warning `hatchFailedSentence` once, no
    problem).
  - `ProjectionCacheTests`: `aCutIsMadeOnce` (two requests: `cutCalls` 1); `cutsAreKeyedByCutter` (a moved line cuts again); `cutsAreEvicted`
    (a small limit drops the oldest).
  - `SectionContentOCCTTests`: `aSheetIsCutButNotHatched` (a planar sheet through the projector: lines include its cut boundary, `hatch` empty);
    `aMixedValueHatchesOnlyItsSolid` (`Kernel.compound` of a 40 × 20 × 10 box and a planar sheet crossing the line beside it, one Output value
    with `holdsClosedSolid` and `hasOpenShell`: every region's edges lie within the box's cut, none on the sheet's; the sheet's cut edge is drawn);
    `twoSolidsTwoAngles` (a two-solid Output: regions with `part` 0 and 1); `aSteppedSectionHasNoLineAtTheStep` (a box, a stepped line: no projected
    line lies along the step's x).
- [ ] **Step 2: Run** `swift test --filter 'SectionContentTests|ProjectionCacheTests|SectionContentOCCTTests'`; fail.
- [ ] **Step 3: Implement** R14's projector branch and R10's framing (every listed call site switches; DR-1 and DR-2 tests unchanged).
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`, `--filter CreatorDrawingEditorTests`, `--filter CreatorAppTests`; pass.
- [ ] **Step 5: Commit** "Drawings: section views cut the part and carry their hatch".

### Task 5: Detail clipping

**Files:**
- Create: `Sources/CreatorDrawing/Sections/DetailClip.swift`
- Test: `Tests/CreatorDrawingTests/DetailClipTests.swift`

**Interfaces:**
- Consumes: Tasks 1, 3 (`HatchClip`), 4 (`ViewContent` fields).
- Produces: `DetailClip.clip(_ projection: Projection2D, to circle: HatchClip) -> Projection2D` (R8; visibility, class and source kept per piece,
  input order kept, pieces in curve order); `DetailClip.content(of parent: ViewContent?, circle: DetailCircle) -> ViewContent` (R8: no parent
  gives the problem `DetailClip.parentDeletedSentence` = "The view this detail enlarged was deleted."; `isPending`, `problem`, `warnings` and
  `topology` carried; `hatch` carried unclipped and `hatchClips` the parent's plus the circle; `framing` the circle's square).

- [ ] **Step 1: Tests.** `aLineIsCutAtTheCircle` (a chord's two crossings within 1e-12); `aLineOutsideIsDropped`; `aLineInsideIsKept`;
  `anArcStaysAnArc` (an arc crossing the circle gives one or two `.arc` pieces, centre and radius unchanged); `aFullCircleInsideStaysFull`
  (sweep 2π, so its centre mark survives); `anEllipseIsCutAtItsCrossings` (each piece an `.ellipse` with the same centre and axes, its ends on
  the circle within 1e-9); `aPolylineIsSplitIntoRuns`; `nothingLiesOutsideTheCircle` (500 random curves: every sampled point within radius +
  1e-9); `sourcesAndClassesAreKept`; `hatchStopsAtTheCircle` (the content's hatch strokes through `HatchPattern` with `hatchClips`: no point
  beyond the circle; and a detail of that detail whose circle reaches past the outer one: `hatchClips` holds both circles and no hatch point
  lies outside the outer circle); `noParentIsAProblem`; `aPendingParentIsPending`.
- [ ] **Step 2: Run** `swift test --filter DetailClipTests`; fail.
- [ ] **Step 3: Implement** R8's clip.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: detail views clip their parent's projection".

### Task 6: Marks, labels and hatch on the sheet

**Files:**
- Create: `Sources/CreatorDrawing/Sections/SectionMarks.swift` (cutting lines, detail circles, auxiliary arrows, detail boundaries),
  `Sources/CreatorDrawing/Sections/DerivedViewNotices.swift`
- Modify: `Sources/CreatorDrawing/Picture/SheetPicture.swift` (`mark: ViewID?` on `SheetStroke`, `SheetFill`, `SheetText`, default nil),
  `SheetComposer.swift` (hatch strokes per view, marks after every view, notices, `viewExtents` cover marks), `SheetHitTest.swift`
  (`line(near:)` skips `.hatch` and marks; `mark(at:in:tolerance:) -> ViewID?`), `Sources/CreatorDrawing/Views/ViewLabel.swift` (R7's labels),
  `Sources/CreatorDrawing/Views/ViewPlacement.swift` (R10's carried descendants, with a visited set), `Sources/CreatorDrawing/Export/DXFWriter.swift`
  (`begin` writes `6 Continuous` for a `.solid` stroke on CENTER or HIDDEN, R6)
- Test: `Tests/CreatorDrawingTests/SectionMarksTests.swift`, `SheetComposerTests.swift`, `SheetHitTestTests.swift`, `ViewPlacementTests.swift`
  (additions), `PDFWriterTests.swift`, `DXFWriterTests.swift` and `DXFCentreMarkTests.swift` (additions)

**Interfaces:**
- Consumes: Tasks 1 to 5.
- Produces: `SectionMarks.cuttingLine(_ cutter: SectionCutter, letter: String, mapping: ViewMapping, parent: ViewID, mark: ViewID, standard:
  DrawingStandard) -> (strokes: [SheetStroke], fills: [SheetFill], texts: [SheetText])` and the same shape for `detailCircle(_:letter:mapping:…)`,
  `auxiliaryArrow(_:letter:mapping:…)`, `detailBoundary(center: Vector2, radius: Double, view: ViewID, standard:)`;
  `DerivedViewNotices.notices(for: DrawingView, in: DrawingSheet) -> [String]` (R6's four sentences); `SheetHitTest.mark(at: Vector2, in:
  SheetPicture, tolerance: Double) -> ViewID?`.

- [ ] **Step 1: Tests.**
  - `SectionMarksTests`: `isoThickEndsAndCorners` (a stepped line at 1:1: thick pieces 5 mm at each end and 3 mm either side of each corner, the
    rest a thin `.centre` stroke on `.center`, the thick pieces `.solid` on `.center` too); `asmeIsThickThroughout`; `arrowsPointTheViewingWay` (shaft 7 mm ISO from each end along
    `viewing`, a filled head of 2.5 at its far end); `lettersBeyondTheArrows` (centre `letterGap + h/2` past the tip, h = 5 ISO); `aDetailCircleAndLetter` (the letter
    at `centre + (r × s + letterGap + h/2) × letterDiagonal`, compared with `==` to the value built from `(0.5).squareRoot()`);
    `anAuxiliaryArrowPointsAtTheEdge` (tip 2 mm short of m); `everythingCarriesItsMark`.
  - `SheetComposerTests` additions: `aSectionDrawsItsHatch` (content with one region: `.hatch` strokes tagged with the section);
    `theCuttingLineIsOnTheParent` (strokes with `view` the parent and `mark` the section); `aTurnedParentHidesTheCuttingLine` (parent orientation
    changed: no mark strokes, the section's notice under it); `aDeletedParentLeavesANotice`; `labelsCarryTheScale` ("SECTION A-A (1 : 1)",
    "DETAIL B (5 : 1)", "VIEW C (1 : 1)"; ASME "SECTION A-A (1:1)"); `aDetailDrawsItsBoundary`; `extentsCoverTheMarks`.
  - `SheetHitTestTests` additions: `hatchAndMarksAreNotLines`; `aMarkIsFoundByItsView`.
  - `ViewPlacementTests` additions: `freeDerivedViewsMoveWithTheirParent` (a detail and a slanted section move by the parent's delta; an aligned
    section slides along its axis); `removingAParentFreesAlignedSections`.
  - `PDFWriterTests`: `hatchedPageDigest` (a fixture page with hatch, a stepped cutting line, arrows and letters: its SHA-256 pinned; the DR-1 and
    DR-2 digests unchanged; the fixture builds nothing with `sin` or `cos`, R5). `DXFWriterTests`: `hatchIsOnTheHatchLayer` (LINE entities on
    HATCH); `aHatchedSheetIsDeterministic`; `aSolidStrokeOnTheCentreLayerIsContinuous` (a `.solid` stroke on `.center` and one on `.hidden`
    carry group 6 `Continuous`; a `.centre` stroke on `.center` and a `.hidden` one on `.hidden` carry no group 6; `Continuous` is a record of
    the LTYPE table); `theThickEndsAreContinuousInDXF` (an ISO cutting line's sheet DXF: the LINE entities of the thick pieces, on CENTER,
    carry `6 Continuous`, the chain's carry no group 6); the digest test of `DrawingFixtures.a4Sheet` re-pinned (its solid CENTER stroke now
    writes `6 Continuous`; the commit says so; nothing else in the bytes changes, checked by diffing the old and new outputs once while
    re-pinning). `DXFCentreMarkTests`: `aSmallCentreMarkIsContinuous` (a hole whose centre mark is solid, under `smallCentre` on the sheet: its
    two LINEs on CENTER carry `6 Continuous`).
- [ ] **Step 2: Run** `swift test --filter 'SectionMarksTests|SheetComposerTests|SheetHitTestTests|ViewPlacementTests|PDFWriterTests|DXFWriterTests|DXFCentreMarkTests'`;
  fail.
- [ ] **Step 3: Implement** R5's composing, R6 (with the DXF linetype rule), R7's labels, R10's moves.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: cutting lines, detail circles, hatch and labels on the sheet".

### Task 7: The editor's Section, Detail and Auxiliary tools

**Files:**
- Create: `Sources/CreatorDrawingEditor/DrawingEditorModel+DerivedViews.swift` (drafts, placing), `DrawingEditorModel+Marks.swift` (pressing and
  dragging marks, `setDetailRadius`)
- Modify: `DrawingTool.swift`, `DrawingKey.swift` (`finish`), `DrawingStepName.swift` (R13's three steps, in `all`), `DrawingEditorModel.swift`
  (`sectionDraft`, `detailDraft`, `auxiliaryDraft`; `replaceDocument` pruning), `DrawingEditorModel+Pointer.swift`, `DrawingEditorModel+Keys.swift`,
  `DrawingEditorModel+Picking.swift` (`PickContext.isPictorial` from `DrawingSheet.isPictorial`, R11), `DrawingEditorModel+Views.swift`
  (`setSource` carries to every descendant, `setOrientation` to details, R8),
  `Views/SheetCanvasInput.swift` (S, E, U, Return), `Sources/CreatorDrawing/Views/ProjectedViewRule.swift` (R11's refusals: detail parent, and a
  section or auxiliary view whose frame runs along no axis)
- Test: `Tests/CreatorDrawingEditorTests/SectionToolTests.swift`, `DetailToolTests.swift`, `AuxiliaryToolTests.swift`,
  `DrawingStepNameTests.swift` (additions), `ViewToolTests.swift` (additions)

**Interfaces:**
- Consumes: Tasks 1 to 6.
- Produces: `DrawingTool` cases `section`, `detail`, `auxiliaryView`; `DrawingKey.finish`; `public internal(set) var sectionDraft: SectionDraft?`
  (`SectionDraft { parent: ViewID; points: [Vector2] /* model plane */; isFinished: Bool }`), `detailDraft: DetailDraft?` (`{ parent; center;
  radius; isFinished }`), `auxiliaryDraft: AuxiliaryDraft?` (`{ parent; at; along }`); `public func setDetailRadius(_ radius: Double, of: ViewID)`;
  the draft drawn into `draftPicture` through `SectionMarks` (a finished draft also shows where the view will go: nothing more).

- [ ] **Step 1: Tests** (fixtures: `DrawingEditorFixtures` contents with a FakeKernel plate's Top and Front views).
  - `SectionToolTests`: `twoClicksAndReturnMakeAStraightLine`; `theFirstSegmentSnapsWithinFiveDegrees` (and ⇧ keeps 4°); `laterPointsAreConstrained`
    (a step click moves only across, a cut only along); `clickingTheLastPointFinishes`; `anEvenCountIsRefusedAtFinish` (the sentence; the draft
    kept); `aCutAgainstTheFirstIsRefused`; `pointsSnapToCentres`; `placingMakesAnAlignedSection` (horizontal line on Top, drop below in ISO: one
    "Add View", kind `.section`, frame looking the way the arrows point (first angle: toward the drop), alignment `.vertical`, letter "A",
    `showsLabel`, parent's scale, selected); `placingInASMELooksAway`; `aSlantedLineMakesAFreeSection`; `aPictorialParentIsRefused`;
    `aDetailParentIsRefused`; `aParentWithNothingDrawnIsRefused`; `escapeDropsTheDraftThenTheTool`; `theSKeyChoosesTheTool`;
    `draggingTheCuttingLineMovesIt` (one coalesced "Move Cutting Line"; the points move by the drag over the parent's scale);
    `pressingAMarkSelectsItsView`; `deletingAParentKeepsItsSections` (one "Delete View"; the section remains, alignment freed);
    `undoPrunesTheDraft` (`replaceDocument` without the parent: draft nil).
  - `DetailToolTests`: `pressDragReleaseThenClick` (one "Add View", circle in the parent's model plane, scale 2 : 1 for a 1 : 1 parent, 5 : 1 for 2 : 1,
    50 : 1 for 50 : 1, letter the next free); `aTinyCircleIsRefused`; `radiusIsChangeDetailCircle` (typed in inches stores mm; 0 and −1 refused with
    the sentence, nothing committed); `draggingTheCircleMovesIt`; `parentEditsCarryToDetails` (`setOrientation` of the parent sets the detail's
    and the detail's detail's in the same step, and leaves a section's and an auxiliary view's frames as stored; `setSource` of the parent sets
    the source of the detail, a section, an auxiliary view and a detail of that section in the same step, named as DR-2's `setSource` step is
    today; one undo restores every one).
  - `AuxiliaryToolTests`: `aLineThenAClickPlacesIt` (an inclined edge of a hand-built view: frame direction square to the edge, "VIEW" kind
    `.auxiliary`, free, the arrow's `at` the midpoint); `aClickNearALinesEndPicksIt` (a `.corner` candidate: the same edge picked);
    `aCircleIsRefused`; `aTiltedEdgeIsRefused`; `aDetailParentIsRefused` (exact: "Pick the edge for an auxiliary view on the view the detail
    enlarges."; no draft); `anAuxiliaryViewTakesDimensions` (the Dimension tool on its line: no isometric refusal, one "Add Dimension");
    `aDetailOfAnAuxiliaryViewTakesDimensions` (a detail of it, whose orientation is the auxiliary view's off-axis `.custom` frame: the Dimension
    tool on a line in it is not refused as isometric); `theUKeyChoosesTheTool`.
  - `DrawingStepNameTests`: the three new steps in `all`, each made by its method, `noChangeNoCommit` for `setDetailRadius`.
  - `ViewToolTests`: `aProjectedViewOfADetailIsRefused` ("A projected view comes from a whole view, not a detail."); `aProjectedViewOfAnAuxiliaryViewIsRefused`
    and `aProjectedViewOfASlantedSectionIsRefused` ("A projected view comes from a view that looks along an axis, not from an auxiliary view or
    a slanted section."); `aProjectedViewOfAStraightSectionIsAllowed` (its frame runs along an axis; the new view is not pictorial).
- [ ] **Step 2: Run** `swift test --filter 'SectionToolTests|DetailToolTests|AuxiliaryToolTests|DrawingStepNameTests|ViewToolTests'`; fail.
- [ ] **Step 3: Implement** R3's placing, R8's and R9's tools, R11, R13.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingEditorTests`; pass.
- [ ] **Step 5: Commit** "Drawings: the Section, Detail and Auxiliary tools".

### Task 8: The editor's views (toolbar, canvas, inspector)

**Files:**
- Modify: `Sources/CreatorDrawingEditor/Views/DrawingToolbar.swift` (R13's order: Base View, Projected View, Section, Detail, Auxiliary, then
  DR-2's), `Views/SheetCanvas.swift` (the draft while a derived tool runs), `Views/SheetSelectionLayer.swift` (a selected derived view's marks
  highlighted), `Views/ViewInspector.swift` (R13's page)
- Test: `Tests/CreatorDrawingEditorTests/DrawingToolbarTests.swift`, `DrawingInspectorTests.swift`, `SheetCanvasRenderTests.swift` (additions),
  `SheetViewEqualityTests.swift` (new properties' variants)

**Interfaces:**
- Consumes: Task 7. Produces views only; every new `.equatable()` view's `==` covers its stored properties (`expectEqualityCovers`).

- [ ] **Step 1: Tests.** `DrawingToolbarTests.everyToolHasAButtonOrMore` (fourteen tools in R13's order, overflow into More); `DrawingInspectorTests`:
  `aSectionPageShowsItsTitleAndCut` ("Section A-A", "Stepped (2 cuts)", no Source or Orientation rows), `aDetailPageEditsItsRadius`,
  `anAuxiliaryPageShowsItsTitle`; `SheetCanvasRenderTests` (pixels through `PixelReader`): `hatchIsDrawnInInk`, `aSelectedSectionHighlightsItsCuttingLine`,
  `theSectionDraftIsDrawn`.
- [ ] **Step 2: Run** `swift test --filter 'DrawingToolbarTests|DrawingInspectorTests|SheetCanvasRenderTests|SheetViewEqualityTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingEditorTests`; pass.
- [ ] **Step 5: Commit** "Drawings: section, detail and auxiliary views in the editor's toolbar, canvas and inspector".

### Task 9: Sections, details and auxiliary views in the app

**Files:**
- Modify: `Sources/CreatorApp/Drawing/DrawingSession.swift` (R14: `RequestKey.cutter` and `retainedCurves`, details from their parents by content
  generation, parents first, pruning in `update()`), `Sources/CreatorApp/Drawing/AppModel+DrawingRefresh.swift` (`RefreshKey.cutter`, sections and
  details per R14), `Sources/CreatorApp/AppModel+DrawingExport.swift` (R15), `Sources/CreatorDrawing/Export/DXFWriter.swift` (`view(...annotations:)`
  takes the view's hatch, detail boundary and carried marks)
- Test: `Tests/CreatorAppTests/DrawingSectionTests.swift` (FakeKernel with hooks), `Tests/CreatorAppTests/DrawingSectionOCCTTests.swift`
  (`#if canImport(CreatorOCCT)`), `Tests/CreatorAppTests/DrawingExportTests.swift` (additions), `Tests/CreatorAppTests/DrawingSessionTests.swift`
  (additions; create it if the session's tests live elsewhere, beside them)

**Interfaces:**
- Consumes: Tasks 1 to 8.
- Produces: no new public API beyond R14's behaviour.

- [ ] **Step 1: Tests.**
  - `DrawingSessionTests`: `aDeletedViewsRequestIsPruned` (after deleting a view and `update()`, no `wanted`, `applied` or `flights` entry for it and
    its solids are released: a weak reference to the Output's old solid is nil after the next evaluation); `requestKeysRetainTheirCurves`;
    `aMovedCuttingLineReprojects` (one more `cutCalls`); `aDetailFollowsItsParent` (the parent's content lands: the detail's clipped content
    appears without a kernel call); `detailsOfDetailsResolveInOrder`.
  - `DrawingSectionTests`: `addingASectionIsOneUndoStep` (undo removes it and its marks, redo brings both back); `undoBringsTheCuttingLineBack`
    (delete the parent, undo: the marks return and the notice goes); `aSectionRefreshesItsLastGood` (R26 through the hook's remainder).
  - `DrawingSectionOCCTTests` (Box with a through hole → Output; Top base view; a section from a horizontal line through the hole):
    `theSectionIsHatchedAroundTheHole` (hatch strokes exist; none crosses the hole's cut gap); `aCutEdgeDimensionFollowsAWidthChange` (a horizontal
    dimension on a cut edge reads "40"; width 40 → 60: "60", held); `aCutEdgeDimensionIsLostWhenItsCutLeavesThePart` (its own part, a plain 40 × 20 × 10
    box at the origin, on Top; the stepped line (−5, 5), (20, 5), (20, 15), (45, 15) viewing (0, 1); a dimension on an edge of cut 2's face (y = 15, x from 20 to 40) reads "20";
    the cutting line dragged by its mark 6 model mm along +y (R13's Select drag, one "Move Cutting Line"), so cut 2 runs at y = 21, beyond the part, and makes no face
    while cut 0, now at y = 11, still does: the dimension reads "20?" lost `.missing`, listed, and is not attached to cut 0's edge; undo brings
    it back held); `aDetailOfTheSectionMeasuresModelMillimetres` (a Ø dimension in a 5 : 1 detail of the parent reads the hole's true diameter);
    `aHoleSquareToTheInclinedFaceReadsTrueInItsAuxiliaryView` (a wedge: a trapezoid profile on the Front plane with a 30-40-50 slope, extruded 20;
    a 10 mm hole drilled square to the inclined face: a circle profile on Plane from Face of the inclined face, extruded through and subtracted;
    a Front base view; an auxiliary view from the slope's edge, which is square to Front: the hole's circle there reads "Ø10" (a Ø dimension
    on it is allowed, face on) while the same circle in Front, an ellipse there, is refused with `DrawingPick.circleSentence`; and an aligned
    dimension of the slope's edge in the auxiliary view reads "50", as it does in Front); `aSectionOfTwoSolidsHatchesTwoAngles`.
  - `DrawingExportTests`: `thePDFCarriesHatchAndMarks` (the page's content stream has the hatch lines and the letters); `theSheetDXFHasHatch`;
    `aViewDXFHasNoHatch`; `aViewDXFWithAnnotationsHasItsHatch` (mapped back: hatch lines spaced 2.5 × 2 = 5 model mm apart at 1 : 2).
  - Every hook that holds a projection or a cut suspends (`HookGate`), never blocks.
- [ ] **Step 2: Run** `swift test --filter 'DrawingSessionTests|DrawingSectionTests|DrawingSectionOCCTTests|DrawingExportTests'`; fail.
- [ ] **Step 3: Implement** R14 and R15.
- [ ] **Step 4: Run** `swift test --filter CreatorAppTests`, `--filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: section, detail and auxiliary views in the app".

### Task 10: Benchmark drawing-4

**Files:**
- Modify: `Tests/CreatorAppTests/Bench/DrawingBench.swift`, `DrawingBenchFixtures.swift` (the bracket's straight section through its holes),
  `DrawingBenchFixturesTests.swift` (the fixture's section has hatch and at least one cut edge; checked in the default run),
  `docs/verification/performance.md` (row `drawing-4`)

- [ ] **Step 1:** fixture test first (`theBracketSectionIsHatched`), run, see it fail, then the fixture.
- [ ] **Step 2:** row `drawing-4`: the section from the edit that adds it to its landing, cache emptied, 10 runs (median, p95, max; budget 1 s),
  each round with a new view ID so the session projects again (as `drawing-1` does), checking `cutCalls` grew; run `scripts/bench.sh DrawingBench`
  (release; a loaded Mac's numbers are recorded as saturated).
- [ ] **Step 3: Commit** "Drawings: benchmark drawing-4".

### Task 11: Docs and the suites

**Files:**
- Modify: `CLAUDE.md` (a "Drawings, DR-3" paragraph after DR-2's: the kernel call and its composition (R1), the cutting line's rules (R2),
  frames and alignment (R3), names on a section and the dropped step lines (R4), hatching (R5: bands by the line's ends, sheets never sectioned, exact directions), marks (R6, and the DXF writer's `Continuous` for a
  solid stroke on CENTER or HIDDEN), letters and labels (R7), details (R8),
  auxiliary views (R9), derived views and parents (R10: source carries to every descendant, no cycles), `DrawingSheet.isPictorial` and the
  projected-view refusals (R11), format 19 and the cycle repair (R12), tools, keys and steps (R13), the session and the
  pulled-in backlog (R14), export (R15), `drawing-4` (R16), the parked list (R17); the file-format sentence becomes "File format is version 19 (…
  19 added section, detail and auxiliary views …); files of format 1 to 18 open unchanged and are written as 19"; the `CreatorKernel` entry
  names `cutAway` and `SectionCutter`; the `CreatorDrawing` entry names `Sections/`), `docs/verification/human-checks.md` (group DR-3, below),
  `docs/superpowers/specs/2026-11-24-drawings-design.md` (Status line: "… DR-2 done (…). DR-3 done (<date>; human checks group DR-3 pending; R1:
  the cut composed from OCCT's extrude and boolean, no new C++)."), `docs/metalui-gaps.md` (only if a task logged a `DR-3-x` gap)
- Group DR-3 checks: DR3-1 a straight section through a plate's holes in ISO and ASME: the cutting line (thin chain with thick ends in ISO, thick
  in ASME), arrows the right way, "SECTION A-A" with its scale, the view on the side the standard puts it, hatch at 45° and the holes empty;
  DR3-2 a stepped section through two holes at different heights: no line at the step, the hatch continuous across it; DR3-3 a section of a
  two-solid Output (two angles) and of a sheet (its cut edge, no hatch); DR3-4 a detail of a fillet at 5 : 1, "DETAIL B (5 : 1)", the circle and
  letter on the parent, arcs smooth, a detail of a section clipping the hatch; DR3-5 an auxiliary view of an inclined face, "VIEW C", its arrow,
  the face true size, a dimension on it reading true, a hole drilled square to the face reading its true Ø there and refused in Front, a
  detail of the auxiliary view taking dimensions too; DR3-6 dimension a cut edge, change the width: it follows; on a stepped section, dimension an edge
  of its last cut, then drag the cutting line until that cut leaves the part: "?" in the warning colour, listed, never moved onto another cut's
  edge; undo: held again; DR3-7 drag the cutting line and the detail circle; move the parent: derived views come along;
  delete the parent: the notices, then undo; DR3-8 switch the standard: aligned sections move to the other side, arrows unchanged; DR3-9 the
  keys S, E, U and Return; DR3-10 export PDF and DXF of the sheet: hatch on the HATCH layer, cutting lines on CENTER, letters on TEXT, opening in
  Preview, Acrobat, LibreCAD and AutoCAD/TrueView with no audit prompt; DR3-11 Linux and Windows: the hatched page's PDF SHA-256 equals the Mac's.
- [ ] **Step 1:** docs.
- [ ] **Step 2:** `swift test` on macOS (16 "Test run with" lines, no "recorded an issue" or "failed after"); `XP_TRACK=dr-3 IMAGE=metalcreator-linux:dr-3
  scripts/linux-test.sh test` (16 lines; afterwards remove only this run's Docker volume and image); `swiftlint lint --strict` 0.
- [ ] **Step 3: Commit** "Docs: DR-3 sections, details and auxiliary views".
