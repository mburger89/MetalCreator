# DR-1: Sheets, views and PDF — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drawing mode: sheets with an ISO 5457 border, zones and an ISO 7200 / Y14.1 title block, base and projected views of
Output nodes computed by exact hidden-line removal and drawn in ISO 128 lines, saved as file format 17, and exported as PDF and
as DXF (the sheet, or one view at 1:1).

**Architecture:** A new kernel call, `Kernel.projection`, runs OpenCascade's `HLRBRep_Algo` and reads `HLRBRep_Data` edge by edge
(`cocct_projection.cpp`), so every visible or hidden piece keeps its source edge or face. A portable module, `CreatorDrawing`,
holds the saved model (`DrawingDocument`), the per-standard style, the sheet geometry, Helvetica's metrics, the
`ProjectionCache` and one composer (`SheetComposer`) that turns a sheet into a `SheetPicture` of strokes and texts in sheet
millimetres; the screen, `PDFWriter` and `DXFWriter` all draw that one picture, so they cannot disagree. A graph-free editor
module, `CreatorDrawingEditor`, draws the picture on a paper-coloured canvas and turns gestures into `DrawingCommit`s (the whole
drawing document, as a `SketchCommit` carries the whole sketch), which the app stores with one graph command,
`.setDrawings`, as one named undo step.

**Tech Stack:** Swift 6.4, Swift Testing, OpenCascade 7.9 (`HLRBRep_Algo`, `HLRBRep_Data`, `HLRBRep_EdgeData`, `HLRAlgo_Projector`,
`HLRBRep_Curve`, `HLRAlgo_EdgeIterator`, `HLRTopoBRep_OutLiner`, `GCPnts_QuasiUniformDeflection`; TKHLR), MetalUI (`Path`,
`StrokeStyle` dashes, `ViewThatFits`, `hoverKeyRegion`, `onKeyPress`, C7 gestures).

**Spec:** `docs/superpowers/specs/2026-11-24-drawings-design.md`. Read it whole; build §DR-1 and the parts of §Model,
§Projection, §Drawing mode, §Export, §Constraints and "Decisions after the builder check" that DR-1 touches (decision 1, decision 5
and the smaller calls on PDF bytes, the title-block date, `drawingHighlight` and a view whose Output is deleted). Dimensions,
sections, details, auxiliary views, GD&T, balloons, parts lists and MCP tools are DR-2 to DR-5: leave them out.

**Errata (drawings minors, 2026-11-26):** R10's polyline sampler is not GCPnts: the shim samples by its own bisection (at least 8 pieces, depth 16). This line corrects the plan.

## Global Constraints

- **Worktree and branch.** `/Users/maxburger/Developer/MetalCreator-dr1`, branch `dr-1`. Never touch `../MetalUI` (read it, never edit
  it). A MetalUI shortcoming is logged in `docs/metalui-gaps.md` (a `DR-1-x` entry with the use case and the stopgap) and reported,
  never worked around in MetalCreator.
- **OCCT only through the kernel,** under `OCCTKernel.serialized`; every C allocation has a `*_free`; no C++ exception crosses into
  Swift (`guarded`). Shim portability: no `M_PI` (`cocct::kPi`), no POSIX headers, no `__attribute__`, never the token `near`
  (reword; never split it across literals). TKHLR is linked on macOS, Linux and Windows.
- **Module rules.** `CreatorDrawing` depends on `CreatorGeometry` and `CreatorKernel` only (never OCCT, MetalUI or CreatorGraph);
  `CreatorDrawingEditor` on `CreatorDrawing`, `CreatorKernel`, `CreatorGeometry`, `CreatorStyle` and MetalUI only (never
  CreatorGraph); `CreatorGraph` gains `CreatorDrawing`. No CoreGraphics, CoreText, ImageIO or Metal anywhere in either module.
  Nothing iterates a dictionary where order reaches output (sheet pictures, PDF and DXF bytes, tab order, warnings).
- **Units.** Model geometry and `Projection2D` are model millimetres in the view plane; sheet geometry is sheet millimetres,
  origin bottom left, y up. A view at scale s draws a model length L as s × L sheet millimetres.
- **Line weights and lettering** (spec §Standards, ISO 128-20 line group 0.5) are `DrawingStyle` constants, never literals at a call
  site: thick 0.5 mm, thin 0.25 mm, hidden dashes 3 mm with 1.5 mm gaps, lettering 3.5 mm on A0 to A2 and 2.5 mm on A3 and A4 for
  notes, 5 mm view labels, 7 mm titles. Dashes are in sheet millimetres, never scaled by zoom.
- **Colours.** The sheet is paper: `drawingPaper` #FFFFFF, `drawingInk` #000000 and `drawingHighlight` #1F6FEB, the same in every
  built-in theme. Hex values only in `CreatorStyle`.
- **PDF bytes are identical on every platform** (one digest), so nothing written depends on the locale, the clock, a hash seed or
  a platform formatter.
- **File format 17** (`GraphFile.currentFormatVersion`): the top-level graph's optional `drawings` key. Files of format 1 to 16 open
  unchanged and are written as 17.
- **Undo names** are fixed strings with no numbers and no typed text (`DrawingStepName`, through `UndoName.drawing(_:)`).
- **Messages** are full sentences in the app's voice; numbers through `Locale.messages` (`Double.display`, `Int.display`).
- **Kernel calls** are refused by default and in `FakeKernel` with `KernelError.unsupported` and a gerund phrase ("projecting views").
  An `async` requirement keeps a synchronous refusing default (Kernel.swift's rule: an `async` default would outrank a kernel's own
  method).
- **Tests and checks.** Swift Testing only; OCCT tests gated `#if canImport(CreatorOCCT)`; never block a pool thread in a test (use
  `HookGate` or a kernel hook that suspends); `swiftlint lint --strict` over the whole tree reports 0; after DR-1, macOS and Linux each
  print **16** "Test run with" lines and never "recorded an issue" or "failed after".
- **Commit trailer** (every commit):
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_0195iKYokoi2BJLpboZBys76`.

## Rulings (where this plan narrows the spec; each says why and what it costs if wrong)

- **R1. Modules and test targets.** `CreatorDrawing` (model, styles, sheet geometry, lettering, symbols, the cache and projector, the
  composer, `PDFWriter`, `DXFWriter`) and `CreatorDrawingEditor` (the editor model and its MetalUI views), each with its own test target
  (`CreatorDrawingTests`, `CreatorDrawingEditorTests`): **16** "Test run with" lines. Why: it mirrors `CreatorSketch` /
  `CreatorSketchEditor`, and keeps the writers testable without MetalUI. Cost: two more targets to build; the spec allowed 15.
- **R2. Where drawings are saved.** `Graph.drawings: DrawingDocument`, encoded as the key `drawings` on the top-level graph object only
  when it holds a sheet, exactly as `Graph.units` is; a definition's graph never carries one (`GraphContent` refuses `.setDrawings`
  inside a definition: "Drawings belong to the document, not to a group."). One command, `GraphCommand.setDrawings(DrawingDocument)`,
  replaces the whole drawing document and returns the old one as its inverse; `affectsResults` is false and `touchedNodes` empty, so
  no evaluation runs. Why: every drawing edit is then one undo step through the existing stack and dirty state (`DocumentModel.content`)
  covers drawings for free, and the editor stays graph-free. Cost: each step keeps a copy of the drawing (kilobytes in DR-1; DR-2's
  annotations grow it). The spec's "top-level graph file gains an optional drawings key" is read as the top-level graph object.
- **R3. Order in the file.** Sheets are written **in tab order** (their order is content: the tabs and "sheet n of m"); views are kept
  sorted by `ViewID` in memory and in the file. Why: the spec's "sorted by id" would lose the tab order. Cost: none.
- **R4. View state.** `ViewState.drawing: DrawingViewState?` (`isOn`, `sheet: SheetID?`), an optional key with no format bump, so a file
  reopens in the mode and on the sheet it was saved with. The sheet's pan and zoom are not saved; entering Drawing or changing sheet
  fits the sheet (F). Switching mode or sheet is never an edit and never an undo step.
- **R5. Projection frames.** A `ProjectionFrame` is `direction` (the way the viewer looks, unit) and `up` (unit, perpendicular);
  `right = direction × up`; a model point p lands at (p · right, p · up). The standard orientations follow the view cube
  (`CubeLabelMapping`, +Z up):

  | Orientation | direction | up |
  |---|---|---|
  | Front | (0, 1, 0) | (0, 0, 1) |
  | Back | (0, −1, 0) | (0, 0, 1) |
  | Left | (1, 0, 0) | (0, 0, 1) |
  | Right | (−1, 0, 0) | (0, 0, 1) |
  | Top | (0, 0, −1) | (0, 1, 0) |
  | Bottom | (0, 0, 1) | (0, −1, 0) |
  | Isometric, front right | (−1, 1, −1)/√3 | +Z made perpendicular |
  | Isometric, front left | (1, 1, −1)/√3 | +Z made perpendicular |

  Why: the drawing's Front is the viewport's FRONT. Cost: none.
- **R6. Projected views** (decision 1). A drop is classified by its offset from the parent's centre: |dx| ≥ |dy| is horizontal (right
  or left), else vertical (above or below). With the parent's frame (d, u, r):

  | Dropped | Third angle (ASME) | First angle (ISO) | Aligned |
  |---|---|---|---|
  | right | direction −r, up u | direction r, up u | horizontally (shares the parent's y) |
  | left | direction r, up u | direction −r, up u | horizontally |
  | above | direction −u, up d | direction u, up −d | vertically (shares the parent's x) |
  | below | direction u, up −d | direction −u, up d | vertically |

  The frame is stored as `.custom(frame)` with `ViewAlignment(parent:axis:)`; the drop's standard never matters again. Changing the
  standard keeps every view's frame and alignment and mirrors each projected view across its parent along the free axis (its offset
  from the parent's centre negated), parents before children. A projected view's parent must be orthographic: an isometric parent is
  refused, "A projected view comes from a front, side, top or bottom view, not an isometric one.". Auxiliary (diagonal) views are DR-3.
- **R7. Placement.** Every view stores `center` (sheet mm): the point the centre of its projection's 2D bounds (visible **and** hidden
  lines, whatever the display flags) lands on. An aligned view's shared coordinate is always its parent's (resolved parents first; a
  missing parent or a cycle leaves the view free at its stored centre). Moving a view moves its aligned descendants by the same delta
  in the same commit; dragging an aligned view moves it along its free axis only. Deleting a view frees its children where they are.
  Why: bounds centres of two orthographic projections of one body agree along the shared axis, so alignment survives any edit of the
  part. Cost: a view's centre drifts with its part's bounds, not with the model origin.
- **R8. Scales** (ISO 5455). Preferred: 50:1, 20:1, 10:1, 5:1, 2:1, 1:1, 1:2, 1:5, 1:10, 1:20, 1:50, 1:100, 1:200, 1:500, 1:1000; a custom
  ratio is two integers 1 to 1000. A sheet has a scale; a view may override it. Placing the first view on a sheet with no views sets the
  sheet's scale, in the same "Add View" step, to the largest preferred scale s with `s × (w + d) + 3g ≤ A.width` and `s × (h + d) +
  3g ≤ A.height`, where (w, h, d) are the source's bounding box extents along the view's right, up and direction, g = 20 mm and A is
  the drawing area (the frame's inside minus a band the title block's height along the whole bottom); none fits gives 1:1000; no bounds
  (an Output with no result yet) gives 1:1. Written "1 : 2" (ISO) or "1:2" (ASME).
- **R9. The kernel call.** `projection(of solid: Solid?, curves: [Curve], frame: ProjectionFrame, options: ProjectionOptions) async
  throws -> Projection2D`: the solid is optional (an Output may hold only curves); a nil solid and no curves give an empty projection.
  Everything is computed every time (visible and hidden; sharp, smooth, outline, sheet boundary and curve), so the display flags never
  re-project; `options` is only the polyline `tolerance` in model mm (`0.01 / scale`). Seams (an edge closed on its face) are dropped;
  a regular-N edge that is not a seam is smooth; iso lines are never drawn. An Output with several solids is projected as one
  `Kernel.compound` of them (tag: the Output node, item 0), so they hide each other. The compound is made **by the cache, on a miss**
  (R19): the cache is keyed on the source solids' own identities, never on the compound's (`Kernel.compound` returns a new `Solid`
  every call, so a key on it would miss every time and re-project an unchanged multi-solid Output after any edit). Cost: one compound
  per cache entry, kept alive by it.
- **R10. The shim reads `HLRBRep_Data` per edge** (spec's spike). HLR data edge i is the shape at index i of the data's own edge map
  (`HLRBRep_Data::EdgeMap()`, which `HLRBRep_ShapeToHLR` builds from the outlined shape by its own exploration); the shim never assumes
  that order equals `TopExp::MapShapes` of anything and matches shapes **by `IsSame` only** (the input's `TopTools_IndexedMapOfShape`
  of edges and of faces, `FindIndex`). The full source rule, in this order, for the shape S of HLR edge i:
  1. S is a **split piece**: the outliner inserts vertices where an outline meets an edge (a cylinder's circles seen side on are cut
     at the outlines), and its `HLRTopoBRep_Data` lists the pieces of an original edge E (`EdgeHasSplE(E)`, `EdgeSplE(E)`). Before
     reading, the shim walks every input edge E that has split pieces and records piece → E (by `IsSame`; `NewSOldS(S)` is the
     cross-check where the outliner recorded one); S resolves to its E, which is then classified by step 2. Several pieces, and so
     several lines, share one source.
  2. S (or its E) `IsSame` an input edge: that edge is the source.
  3. S is in `HLRTopoBRep_Data::FaceOutL(F)` of an input face F (`FaceHasOutL`; looked up through a map built once from every input
     face's outline list, split outlines resolved as in step 1): an `.outline` sourced `.face(F)`.
  4. S is in `FaceIntL(F)` or `FaceIsoL(F)` (internal and iso lines): dropped, never drawn.
  5. Anything else: `source_kind` −1 (none). The tests assert no such line on a box, a cylinder, a filleted box or the bracket; under
     the primary path a sourceless line is a bug, not a fallback.
  Each visible and hidden interval (`HLRAlgo_EdgeIterator` over `EdgeData::Status()`) becomes one line; its 2D geometry is exact when `HLRBRep_Curve::GetType`
  is a line, circle or ellipse, else a polyline by `GCPnts_QuasiUniformDeflection` at the tolerance. Free curve edges go into the same
  run, so solids hide them; step 2 matches them against each input curve's edges (`.curve(index:piece:)`, the piece its place in its
  wire), split pieces resolved by step 1 likewise. **Fallback** (taken only if Task 2's first step shows the mapping can't be made): `HLRBRep_HLRToShape`'s six
  compounds (visible and hidden sharp, smooth, outline), each result edge matched to a model edge by projecting that edge's points with
  the same `HLRAlgo_Projector` (midpoint and both ends within 1e-6 mm); unmatched edges get `source == nil`, and curves are drawn
  unhidden. The outcome is appended to the ledger and becomes an erratum under this ruling. Cancellation: OCCT 7.9's `Update` and
  `Hide` take no progress range, so the shim polls `occt_cancel` before `Update`, before `Hide` and every 64 edges while reading;
  a cancel waits out a running hide. Cost: on a huge part a superseded projection runs to the end of its hide.
- **R11. Line classes on paper** (ISO 128; `DrawingStyle`):

  | Class | Visible | Hidden (only when the view shows hidden lines) | DXF layer |
  |---|---|---|---|
  | sharp, outline, sheet boundary | thick, solid | thin, dashed | VISIBLE / HIDDEN |
  | smooth (tangent) | thin, solid (only when the view shows tangent edges) | never drawn | TANGENT |
  | curve | thick, solid | thin, dashed | VISIBLE / HIDDEN |

  `sheetBoundary` is assigned in Swift: a sharp or smooth line whose source edge is a boundary edge (`EdgeInfo.isBoundary`). Hidden
  lines are off and tangent edges on by default, per view. ASME's `DrawingStyle` is Y14.2's: thick 0.6, thin 0.3, the same dashes,
  lettering 3.0 mm notes and 6.0 mm titles and view labels. The frame is 0.7 mm, zone ticks and the title block's inner lines 0.35 mm,
  its outline 0.7 mm.
- **R12. Screen strokes.** Canvas points = sheet mm × zoom (zoom 0.25 to 40); a stroke's screen width is max(weight × zoom, 1 pt); dashes
  are sheet mm × zoom. Strokes are rebuilt when the zoom changes; a pan only offsets the canvas content, so it re-strokes nothing. Arcs
  and ellipses become cubic Béziers of at most 90° each by one shared function (`SheetSegment.cubics()`) that the screen and the PDF both
  use.
- **R13. Lettering.** A text's height h is its cap height (ISO 3098); Helvetica's cap height is 718/1000 em, so the em size is h / 0.718.
  Widths are Adobe's Core 14 `Helvetica.afm` advances (WinAnsi), no kerning. Each character is mapped to WinAnsi first; one outside it
  is laid out, drawn and written as "?" everywhere (screen, PDF and DXF agree), the text keeps its typed original, and an export warns
  once per **distinct original text** across everything it writes (the same title on three sheets is one warning; deduplicated by the
  original string, in first-seen order of page then drawing order, by one shared `ReplacedTexts.collect(_ texts: [SheetText]) ->
  [String]`): "“<original>” has characters the PDF font can't show, so they're written as “?”.". The PDF and both DXF exports report
  their replacements the same way (`PDFOutput.replacedTexts`, `DXFOutput.replacedTexts`; the sentence says "the PDF font" for every
  format, since the DXF text is the same shown string). A value wider than its title-block field is shrunk to fit, never below 1.8 mm,
  then cut with "…".
  **On screen** each glyph of a run is its own MetalUI `Text` in the app's sans-serif (`.system`) at em size h / 0.718 × zoom points:
  - x: the glyph's left edge is the run's origin x plus its Helvetica offset (`TextRun.offsets`), × zoom, so a line is as wide on screen
    as on paper.
  - y: MetalUI has no public way to read a laid-out text's baseline, but an `HStack(alignment: .firstTextBaseline, spacing: 0)` aligns
    each child's first baseline, and a child with no text (a `Color.clear.frame(width: 0, height: B)`) aligns its bottom. So each glyph
    is `HStack(alignment: .firstTextBaseline, spacing: 0) { Color.clear.frame(width: 0, height: B); Text(glyph) }` with B = 2 × the em
    size (above any face's ascent, so the clear child is always the tallest above the baseline), `.fixedSize()`, its top-left placed at
    (glyph x, screen baseline y − B): the glyph's baseline then lies exactly on `SheetText.origin.y` mapped by the transform, whatever the
    face's ascent or leading. One `SheetTextView` builds the whole run this way; nothing reads the screen font's metrics. If a render test
    shows MetalUI does not honour this (a baseline off by more than 0.5 pt), it is logged as gap `DR-1-a` (a public first-baseline
    reading) and reported, not patched here.
- **R14. Sheets** (ISO 5457 sizes in mm, portrait width × height: A4 210 × 297, A3 297 × 420, A2 420 × 594, A1 594 × 841, A0 841 × 1189; ANSI
  A 215.9 × 279.4, B 279.4 × 431.8, C 431.8 × 558.8, D 558.8 × 863.6, E 863.6 × 1117.6). Frame margins: ISO 20 mm left, 10 mm elsewhere;
  ASME 12.7 mm all round. Zones per frame side: `2 × max(1, round(side / 100 mm))` equal fields (this reproduces ISO 5457's table, A0's 24 × 16
  down to A4 portrait's 4 × 6), ticks 0.35 mm from the frame 5 mm outward, labels 3.5 mm centred 3.5 mm outside the frame; ISO letters run
  from the top down and numbers left to right, ASME letters bottom up and numbers right to left. ISO adds centring marks: 0.7 mm at each
  side's middle, from the trimmed edge to 5 mm inside the frame. ANSI's own Y14.1 zone counts and margins are parked. A new sheet is A3
  landscape (ISO) or ANSI B landscape (ASME), named "Sheet N" with the smallest unused N.
- **R15. Title block** (ISO 7200 / Y14.1 fields), 180 × 40 mm, its bottom-right corner on the frame's inside bottom-right corner. Fields
  (mm from the block's bottom-left; label 1.8 mm at the top left, inset 1.5 mm, baseline 2.5 mm below the field's top; value baseline 1.5 mm
  above its bottom, inset 1.5 mm):

  | Field | x | y | value height | ISO label | ASME label |
  |---|---|---|---|---|---|
  | owner | 0–110 | 30–40 | 3.5 | Owner | COMPANY |
  | drawnBy | 110–145 | 30–40 | 2.5 | Drawn by | DRAWN |
  | date | 145–180 | 30–40 | 2.5 | Date | DATE |
  | title | 0–110 | 10–30 | 7 | Title | TITLE |
  | material | 110–180 | 20–30 | 2.5 | Material | MATERIAL |
  | mass (automatic) | 110–140 | 10–20 | 2.5 | Mass | WEIGHT |
  | scale (automatic) | 140–162 | 10–20 | 2.5 | Scale | SCALE |
  | projection symbol (automatic) | 162–180 | 10–20 | — | — | — |
  | drawingNumber | 0–80 | 0–10 | 5 | Drawing number | DWG NO. |
  | revision | 80–100 | 0–10 | 3.5 | Revision | REV |
  | size (automatic) | 100–120 | 0–10 | 2.5 | Size | SIZE |
  | sheet (automatic) | 120–145 | 0–10 | 2.5 | Sheet | SHEET |
  | tolerance | 145–180 | 0–10 | 2.5 | General tolerances | TOLERANCES |

  Automatic values: size "A3" / "B"; sheet "1 / 3" (ISO) or "1 OF 3" (ASME); scale per R8; mass per R16. The date is typed, filled with
  the creation day (ISO 8601, "2026-11-24") when a sheet is made. The tolerance is `DrawingSettings.generalTolerance`: "ISO 2768-mK" for
  a new ISO drawing, "±0.5, ±0.1, ±0.05 mm" for ASME in millimetres, "±.03, ±.010, ±.005 in" in inches (DR-2 structures it). The typed
  fields a new sheet starts with are `DrawingSettings.titleBlockDefaults`, which an edit of a title-block field updates in the same
  "Edit Title Block" step. Cost if wrong: a table.
- **R16. Mass.** The sheet's views all show one Output and the sheet's title block has a density (g/cm³): mass = the volume of that
  Output's closed solids (`Kernel.properties(of:)`, mm³) × density / 1000 grams; else the field is empty. Shown "8.4 g" under 10 g, "84 g"
  under 1000 g, "1.234 kg" above, or pounds ("2.721 lb") when the document's length unit is inches.
- **R17. The projection symbol** (ISO 5456-2), thin lines, h = **2.5 mm** in the title block: a truncated cone seen side on (a trapezoid,
  its big end 2h tall, its small end h tall, 2h long) and end on (circles of diameters 2h and h), 1.5h apart, with a thin horizontal centre
  line through both that runs 0.25h past each end. Its box is therefore 6h × 2h (`DrawingSymbols.projectionSymbolSize(h:)`), 15 × 5 mm,
  centred in R15's 18 × 10 mm field with 1.5 mm to spare on each side. Why 2.5: ISO 5456-2 sizes the symbol by the lettering height, 2.5 mm
  is the notes height of the sheets DR-1 makes by default, and the field is the same size on every sheet; h = 3.5 would make the box 21 mm,
  wider than the 18 mm field. The symbol takes no width parameter; a caller with a box chooses h so 6h × 2h fits it.
  First angle: trapezoid left with its big end at the left, circles right; third angle: circles left, trapezoid right with its big end
  toward the circles. Drawn by `DrawingSymbols`, never a glyph.
- **R18. View labels.** Off by default. When shown: the orientation's title ("Front", "Isometric"; a projected view whose frame equals a
  standard orientation within 1e-9 takes its title, any other "View"), plus " (1 : 2)" when its scale differs from the sheet's,
  upper case for ASME, 5 mm (6 mm ASME), centred 8 mm below the view's frame.
- **R19. The cache.** One `ProjectionCache` per `AppModel` (emptied on New and Open), keyed by the **ordered identities of the source's
  solids** (each one the Output holds, never a compound of them), the curves' identities, the compound's tag, the frame and the options;
  the entry keeps the solids and curves alive, so an identity can't be reused. On a miss with two or more solids the cache makes the
  compound itself (`kernel.compound(solids, tag:)`) and projects it, so a multi-solid Output costs one compound and one projection per
  entry and an unchanged one is a hit. 512 MB by `Projection2D.estimatedBytes`, least recently used first, always keeping the newest; two
  identical requests in flight share one kernel call (and one compound). An edit re-projects only views whose Output's solids or curves
  changed identity (a hit otherwise); while a projection is pending the old one stays drawn at 40 % opacity.
- **R20. A view's source.**
  - Removed Output: an empty frame (its last drawn size, else 40 × 30 mm) saying "The Output this view showed was removed.";
    undo brings the node back and the view draws again (the view itself never changed).
  - Failed Output: the last projection stays faded with the Output's failure under it in the warning colour.
  - Meshes (decision 5): left out with "This view leaves out the Output's 3 meshes; drawings show solids, sheets and curves." (one mesh:
    "This view leaves out the Output's mesh; drawings show solids, sheets and curves.").
  - Only meshes: "Drawings show solids, sheets and curves; this Output holds a mesh. Mesh to Solid makes a solid of a small mesh.".
  - Nothing yet: "This Output holds nothing to draw yet.".
- **R21. Mode switching.** `AppModel.mode` (`.model` / `.drawing`): the top bar's segmented "Model | Drawing", View ▸ Drawing
  (⌘⇧D, `.primary + .shift`) and View ▸ Model. ⌘⇧D must reach the menu wherever the pointer is: today
  `GraphKeyBindings.commandChord` maps "d" to `.duplicate` with or without ⇧ (`Sources/CreatorEditor/GraphKeyBindings.swift`), so over the
  graph canvas its `hoverKeyRegion` would duplicate the selected nodes instead. DR-1 makes a shifted "d" return `nil` there (⌘D alone
  still duplicates), so the chord falls through to the menu's shortcut.
  Entering Drawing finishes the sketch (`finishSketch()`), cancels a pick (`cancelPick()`),
  ends Measure, the model dimension tool and the control-point mode. In Drawing the viewport's keys (D, M, Z, F, +, −) do nothing and an
  inspector action that needs the viewport ("Edit sketch", a "Pick … in View…" button, "Edit Control Points") switches to Model first,
  then runs. With no sheet the canvas shows "Add Sheet" (nothing is added until it is pressed, so entering never dirties a document).
- **R22. DR-1's editor scope.** Tools: Select, Base View, Projected View (the toolbar's other tools come with DR-2 to DR-5). Base View: a
  click places a Front view of the first Output (`AppModel.outputNodes` order) at the click, refused with no Output: "Add an Output node
  and wire the part into it first.". Projected View: press on a parent and drag; the release places the view (R6). Select: click, ⇧-click
  adds, drag moves (one step per drag, coalesced), Delete, arrows nudge 1 mm (⇧ 10 mm, one step per key-down run), Esc cancels the tool
  then clears the selection, F fits the sheet (centred, at 90 % of the visible rect), hover highlights the nearest view line within 4 pt. Tabs: +, click, double-click renames in
  place, a menu with Rename, Duplicate, Delete, Move Left and Move Right. Duplicate Sheet copies views with new IDs (alignments remapped).
  Copy and paste of views, dragging tabs to reorder and keyboard shortcuts for tools are parked (DR-2 brings the clipboard with
  annotations).
- **R23. PDF.** PDF 1.7, objects in a fixed order: 1 catalog, 2 pages, 3 font (`/Type1 /Helvetica /WinAnsiEncoding`, not embedded), 4
  info (`/Producer (MetalCreator)` and `/Title`), then per page its page object and its content stream; no dates and no `/ID`, LF line
  ends, uncompressed streams, a binary comment line after the header, a classic xref of 20-byte entries. With LF line ends an xref entry
  is `nnnnnnnnnn ggggg n` followed by a space and an LF (PDF 32000-1 §7.5.4's two-byte end of line), so every entry is exactly 20 bytes and
  ends " \n"; the free entry 0 is `0000000000 65535 f \n`. Each page's `MediaBox` is the
  sheet in points (mm × 72 / 25.4) and its content starts with `2.834645669 0 0 2.834645669 0 0 cm`, so every other number is sheet mm.
  Numbers are written by `PDFNumber` from integers (4 decimals in mm, trailing zeros dropped, "-0" written "0"), never by a platform
  formatter. Caps butt (`0 J`), joins round (`1 j`), black ink only (`0 G`, `0 g`). Text: `BT /F1 <em mm> Tf <x> <y> Td (<bytes>) Tj ET`,
  with `\`, `(` and `)` escaped and bytes above 126 written `\ddd`. Highlights, hover and selection never reach the PDF. Cost: arc control
  points use `tan`, which could differ in a last bit across libms; at 4 decimals that only shows on a rounding tie, and the digest test
  on all three platforms would catch it.
- **R24. DXF.** ASCII R2000 (`AC1015`), `$INSUNITS` 4, `$DWGCODEPAGE ANSI_1252`, `$LTSCALE` 1, `$HANDSEED` (one past the largest handle
  written); sections HEADER, CLASSES (empty),
  TABLES (VPORT `*Active`, LTYPE `ByBlock` `ByLayer` `Continuous` `DASHED` [3, −1.5] `CENTER` [6, −0.75, 0, −0.75], LAYER `0` and VISIBLE,
  HIDDEN (DASHED), TANGENT, CENTER (CENTER), DIMENSION, TEXT, HATCH, FRAME, all colour 7, lineweights 50, 25, 25, 25, 25, 25, 25, 70
  (×0.01 mm; ASME 60 and 30), STYLE `Standard`, VIEW, UCS, APPID `ACAD`, DIMSTYLE `Standard`, BLOCK_RECORD `*Model_Space` and
  `*Paper_Space`, each with a 340 naming its LAYOUT), BLOCKS (the two space blocks, each BLOCK and ENDBLK owned by its BLOCK_RECORD),
  ENTITIES (owned by `*Model_Space`'s BLOCK_RECORD), OBJECTS; every object has a handle (code 5, hex, sequential from 0x20) and its owner
  (330) and subclass markers (100). **OBJECTS is what AutoCAD needs beyond what LibreCAD and QCAD accept** (the spec's anti-goal names
  AutoCAD, so the minimum those two read is not enough): the root DICTIONARY (owner 0) names `ACAD_GROUP` (an empty DICTIONARY),
  `ACAD_LAYOUT` (a DICTIONARY naming `Model` and `Layout1`), `ACAD_MLINESTYLE` (a DICTIONARY naming `Standard`, one MLINESTYLE),
  `ACAD_PLOTSETTINGS` (an empty DICTIONARY) and `ACAD_PLOTSTYLENAME` (an ACDBDICTIONARYWDFLT naming `Normal`, an ACDBPLACEHOLDER, which is
  also its default, 340); each LAYOUT carries `AcDbPlotSettings` then `AcDbLayout` (name, tab order 0 for Model and 1 for Layout1, limits
  and extents of the sheet or the view, its BLOCK_RECORD as 330) and is the target of that BLOCK_RECORD's 340, so the two link both ways;
  dictionaries and the objects they own carry their `{ACAD_REACTORS` (102, 330 owner, 102 `}`). The group codes follow Autodesk's *DXF
  Reference* for AutoCAD 2000 and the minimal R2000 file ezdxf documents ("DXF internals: DXF file structure"); the implementer copies
  them from there, not from memory. `DXFReader` (tests) checks these links. Human check DR1-6 opens the file in AutoCAD or Autodesk's free
  DWG TrueView with no repair or audit prompt; a prompt there is a DR-1 bug, not a narrowing of the anti-goal. Cost if wrong: one
  object section to amend. Entities: LINE, ARC (degrees, counter-clockwise),
  CIRCLE (a full arc), ELLIPSE (centre, major axis end, ratio, start and end parameters), LWPOLYLINE, TEXT (height = cap height,
  `Ø` as `%%c`, `±` `%%p`, `°` `%%d`, other non-ASCII `\U+XXXX`; the string written is the run's `shown`, so a character outside WinAnsi
  is already "?", R13). Each stroke carries its layer and its own lineweight (370).
  Sheet mode: the open sheet, sheet mm, border, zones and title block on FRAME (title-block text on TEXT). View at 1:1: one view in
  model mm, x and y as R5's view-plane coordinates (a Top view of a plate keeps its model x and y), no frame. A reader's font widths
  differ from Helvetica's in DXF text; that's accepted (the DXF is for geometry).
- **R25. Export.** `DrawingExportKind` (`pdf`, `dxfSheet`, `dxfView`) beside `ExportKind`, not inside it (STEP/STL/3MF's switches stay
  untouched). File ▸ Export PDF…, Export DXF of Sheet…, Export DXF of View at 1:1… and the top bar's Export menu in Drawing. Each commits a
  pending entry, waits for evaluation, refuses an Output a view shows that failed ("“Bracket” can't be drawn" + its reason) or no sheet
  ("Nothing to export", "Add a sheet with a view first."), projects every view it writes (PDF: every sheet; DXF of Sheet: the open sheet;
  DXF of View: the one selected view, else "Select one view to export it at 1:1."), then writes in one go (no progress sheet) and lists the
  warnings (meshes left out, replaced characters) in the existing summary.
  **How the spec's "the export sheet (the existing one) gains PDF and DXF" is read.** In this codebase "the export sheet" is
  `ExportSheetView` (`ExportSheetDock`): the progress card of the streamed mesh export, with a meshing bar and Cancel. A drawing export
  has nothing for it to show: its projections are the cache's (already drawn on screen, or a few hundred milliseconds cold, row
  `drawing-1`) and the writers take milliseconds, so the card would flash. The spec's intent, that PDF and DXF join the existing export
  path while drawing mode is up, is met by the existing export entry points: the File menu's Export items and the top bar's Export menu,
  with the existing file panel (`withFilePicker`, `tracked(_:)`), the same evaluate-first rule and the same warnings summary. STEP and STL
  stay in that menu in Drawing and still use the export sheet when they stream. Cost if wrong: a huge sheet exported cold shows no
  progress while its views project (the slow-evaluation chip shows while the graph evaluates); a progress card for drawings is parked.
- **R26. Undo names** (`DrawingStepName`): "Add Sheet", "Rename Sheet", "Duplicate Sheet", "Delete Sheet", "Move Sheet", "Change Sheet Size",
  "Edit Title Block", "Change Standard", "Add View", "Move View", "Delete View", "Change Scale", "Change View" (source, orientation and display
  flags). `UndoName.drawing(_:)` falls back to "Edit Drawing". Every editor method that commits has exactly one name:

  | `DrawingEditorModel` method | Step |
  |---|---|
  | `addSheet()` | Add Sheet |
  | `renameSheet(_:to:)` | Rename Sheet |
  | `duplicateSheet(_:)` | Duplicate Sheet |
  | `deleteSheet(_:)` | Delete Sheet |
  | `moveSheet(_:by:)` | Move Sheet |
  | `setSheetSize(_:)`, `setSheetOrientation(_:)` (landscape / portrait) | Change Sheet Size |
  | `setSheetScale(_:)` | Change Scale |
  | `setTitleField(_:to:)` for any typed key, `.tolerance` included (which writes `DrawingSettings.generalTolerance`); `setDensity(_:)` | Edit Title Block |
  | `setStandard(_:)` | Change Standard |
  | a Base View click, a Projected View drop | Add View |
  | a drag of views, a nudge run | Move View |
  | `deleteSelection()` | Delete View |
  | `setScale(_:of:)` (a view's override, or nil for the sheet's) | Change Scale |
  | `setSource(_:of:)`, `setOrientation(_:of:)`, `setShowsHidden(_:of:)`, `setShowsTangent(_:of:)`, `setShowsLabel(_:of:)` | Change View |

  `selectSheet(_:)`, the tool, the selection, hover and the canvas transform never commit. `setTitleField` with an automatic key (mass, scale,
  projection, size, sheet) does nothing and commits nothing. A setter whose value equals the current one commits nothing.
- **R27. Performance.** The canvas builds only views whose frames meet the visible rect grown by 20 %, each view an `.equatable()` component
  over its own strokes, texts and state; the frame and title block one more. Rows `drawing-1` (the bracket's four views projected from cold,
  target under 1 s) and `drawing-2` (a pan and a zoom of that sheet, warm, target 60 fps) are recorded in `docs/verification/performance.md`.
- **R28. The window in Drawing mode** (the spec does not say what happens to the viewport's chrome). The sheet canvas fills the model area
  in place of `ViewportPane`; whatever is about the 3D view goes with it, and whatever is about the document or the graph stays:

  | In Drawing | What |
  |---|---|
  | Hidden | `FieldLegendDock` (the field preview pauses: no sampling is requested), `MeshBadgeDock`, `SectionPanelDock` (the Section, Measure and Zebra panels), the model-dimension and pick banners and `PointerReadoutView` (none can be up: R21 ends them), the control-net views (ended), the face menu (no viewport to open it) |
  | Kept | `SlowEvaluationDock` (the views wait on evaluation, so the chip still says what is building; its insets are the same), `AIConnectedDock`, `ExportSheetDock` (a STEP or STL export started from Drawing still streams), `PaletteDock` and `LibraryDragOverlay` (the graph panel stays), the theme editor |
  | Top bar | the document's name with its drag handle, the segmented "Model \| Drawing", `DrawingToolbar`, Undo, Redo and the Export menu (STEP…, STL…, a divider, PDF…, DXF of Sheet…, DXF of View at 1:1…); the Preview picker and the Analysis menu are hidden (both act on the viewport) |
  | View menu | Show/Hide Section, Flip Section, Measure and Show/Hide Zebra Stripes are disabled |

  The section's, zebra's and measurements' view state is left exactly as it was (`document.section`, `document.zebra`, kept measurements),
  so returning to Model shows them again; hiding them is neither an edit nor an undo step. Cost if wrong: one table.

**Amended after the plan review (2026-11-24).** R9 and R19 (the cache keys on the source solids and compounds on a miss; a key on the
compound missed every time), R10 (the full source rule with split pieces, matched by `IsSame` over the data's own edge map), R13 (warnings
deduplicated by original text, for PDF and DXF alike; the on-screen baseline rule), R17 (h = 2.5 so the symbol fits its field), R21 (⌘⇧D
is no longer the graph's Duplicate), R23 (xref entries end " \n"), R24 (the OBJECTS AutoCAD expects and `$HANDSEED`), R25 (what "the
export sheet" is read as), R26 (every editor method mapped to its step, `setSheetScale` added) and R28 (new: the window in Drawing).

**Backlog.** There was no drawings backlog. Pulled in: a `CIPinTests` pin that `Package.swift`'s OCCT toolkit list and the Linux
Dockerfile's `BUILD_ADDITIONAL_TOOLKITS` agree (TKHLR is the first toolkit added since that list was written twice). Nothing from the
`nurbs-backlog-after-ns2` memory is touched by DR-1. **Parked by DR-1** (start the drawings backlog with these): `HLRBRep_PolyAlgo` for very
large parts (spec); cancelling inside OCCT's hide (R10); embedding a font subset (spec); copy and paste of views, dragging tabs to reorder,
tool shortcuts (R22); ANSI Y14.1's own zone counts and margins (R14); hidden tangent lines (R11); compressed PDF streams; DXF text in the
reader's font widths (R24); a progress sheet for drawing export (R25). Renaming drawing anchors in Group, Ungroup and Make Unique (spec §Model) comes with
DR-2's anchors: DR-1's views name only top-level Output nodes, which no group edit moves.

## Review Focus

1. **A view's Output fails, or is deleted, then undone.** The view keeps its last projection faded with the failure under it, or an empty
   frame with "The Output this view showed was removed."; undo draws it again; PDF and DXF refuse a failed Output by name. Task 12
   (`aRemovedOutputLeavesAFrameAndUndoRestoresIt`, `aFailedOutputFadesTheLastProjection`), Task 13 (`aFailedOutputRefusesTheExport`).
2. **A scale that lies.** A 1:2 view of a 100 mm box is 50 mm in the PDF (141.732 pt between its edges at 100 %) and in the DXF of the sheet,
   and 100 mm in the DXF of the view at 1:1; a 2:1 override on one view of a 1:1 sheet draws that view twice as large and labels it. Tasks 7
   (`aHalfScaleViewMeasuresHalfOnPaper`), 8 (`sheetAndViewModesMeasureTrue`), 6 (`aViewOverrideScalesOnlyThatView`).
3. **Typed text outside WinAnsi** (a title "Ω-Bracket →"): "?" in its place on screen, in the PDF and in the DXF, the inspector keeps the
   typed text, and one warning names it, however many sheets carry it (R13: deduplicated by the original text), in the PDF and in both
   DXF exports. Tasks 5 (`aCharacterOutsideWinAnsiLaysOutAsAQuestionMark`), 7 (`replacedTextsAreReported`), 8
   (`replacedTextsAreReported`), 13 (`theExportWarnsAboutReplacedCharactersOnce`).
4. **Switching the standard after projected views exist.** Every child mirrors across its parent, grandchildren with them, frames and
   alignments unchanged, one "Change Standard" step that undo reverses. Task 6 (`switchingTheStandardMirrorsChildren`), Task 10
   (`changeStandardIsOneStep`).
5. **Editing the model quickly while views are shown** (a slider dragged upstream). Superseded projections never overwrite a newer one,
   the old drawing stays faded until the newest lands, and views of unchanged Outputs are cache hits. Task 9
   (`aSupersededRequestNeverPublishes`, `identicalRequestsShareOneKernelCall`), Task 12 (`onlyViewsOfAChangedOutputReproject`).

---

### Task 1: Projection types and the kernel call

**Files:**
- Create: `Sources/CreatorGeometry/Rect2D.swift`, `Sources/CreatorKernel/Projection/ProjectionFrame.swift`,
  `Sources/CreatorKernel/Projection/Projection2D.swift` (with `ProjectedLine`, `ProjectedCurve`, `LineVisibility`, `LineClass`,
  `ProjectionSource`, `ProjectionOptions`), `Sources/CreatorKernel/Projection/ProjectedCurve+Bounds.swift`,
  `Sources/CreatorKernel/FakeKernel+Projection.swift`
- Modify: `Sources/CreatorKernel/Kernel.swift` (requirement and refusing default), `Sources/CreatorKernel/FakeKernel.swift` (the two hooks'
  storage, the projection override and a `compound` override that keeps today's refusal without a hook)
- Test: `Tests/CreatorGeometryTests/Rect2DTests.swift`, `Tests/CreatorKernelTests/ProjectionTypesTests.swift`,
  `Tests/CreatorKernelTests/FakeKernelProjectionTests.swift`

**Interfaces:**
- Produces (CreatorGeometry): `public struct Rect2D: Hashable, Sendable, Codable { public var min: Vector2; public var max: Vector2 }` with
  `init?(points: [Vector2])`, `union(_:)`, `width`, `height`, `center`, `contains(_ point: Vector2) -> Bool`, `intersects(_:) -> Bool`,
  `insetBy(_ amount: Double) -> Rect2D` (negative grows).
- Produces (CreatorKernel):
  - `public struct ProjectionFrame: Hashable, Sendable, Codable { public let direction: Vector3; public let up: Vector3 }`,
    `public var right: Vector3` (direction × up), `public func place(_ p: Vector3) -> Vector2` (p · right, p · up),
    `public static func make(direction: Vector3, up: Vector3) -> ProjectionFrame?` (normalises, makes `up` perpendicular by Gram–Schmidt,
    nil when parallel or zero), `public func validate() throws(KernelError)` ("The view direction and its up direction must be perpendicular
    unit vectors." beyond 1e-9).
  - `public struct ProjectionOptions: Hashable, Sendable { public var tolerance: Double }`, default 0.01.
  - `public enum ProjectedCurve: Hashable, Sendable { case line(Vector2, Vector2); case arc(center: Vector2, radius: Double, start: Double,
    sweep: Double); case ellipse(center: Vector2, majorAxis: Vector2, majorRadius: Double, minorRadius: Double, start: Double, sweep:
    Double); case polyline([Vector2]) }` (angles in radians, a positive sweep counter-clockwise, a full circle sweep 2π; `majorAxis` unit;
    ellipse angles are the parametric angle), `bounds: Rect2D` (exact: arcs and ellipses by their extreme angles inside the sweep).
  - `public enum LineVisibility: String, Sendable { case visible, hidden }`; `public enum LineClass: String, Sendable { case sharp, smooth,
    outline, sheetBoundary, curve }`; `public enum ProjectionSource: Hashable, Sendable { case edge(EdgeID); case face(FaceID); case
    curve(index: Int, piece: Int) }`.
  - `public struct ProjectedLine: Hashable, Sendable { visibility; lineClass; curve: ProjectedCurve; source: ProjectionSource? }` (nil only
    under R10's fallback).
  - `public struct Projection2D: Hashable, Sendable { public var lines: [ProjectedLine] }`, `bounds: Rect2D?` (all lines), `estimatedBytes:
    Int` (64 per line + 16 per polyline point).
  - `Kernel.projection(of solid: Solid?, curves: [Curve], frame: ProjectionFrame, options: ProjectionOptions) async throws -> Projection2D`;
    the extension's synchronous default throws `KernelError.unsupported("projecting views")`.
  - `FakeKernel`: `setCompoundHook(_ hook: (@Sendable ([Solid]) throws -> Solid)?)`: with a hook, `FakeKernel.compound` returns what it
    returns (tests count calls through it); without one it throws `KernelError.unsupported("compounds")` exactly as today, so no
    existing test changes.
  - `FakeKernel`: `setProjectionHook(_ hook: (@Sendable () async throws -> Void)?)` (runs first, as `setSectionHook` does); a solid's
    bounding box seen along one of the six axis directions gives four visible `.sharp` lines (its silhouette rectangle), each sourced from the
    box edge on that side nearest the viewer; curve i's `polyline` projects as one visible `.curve` polyline sourced `.curve(index: i, piece: 0)`
    (FakeKernel's curves carry no pieces); any other direction throws `KernelError.unsupported("projecting along a tilted direction")`.

- [ ] **Step 1: Tests.**
  - `Rect2DTests`: `unionAndContains`, `insetGrowsWhenNegative`, `pointsGiveTheirBox` (nil for none).
  - `ProjectionTypesTests`: `frontPlacesXAndZ` (`ProjectionFrame(direction: (0,1,0), up: (0,0,1)).place((3, 7, 5)) == (3, 5)`, `right ==
    (1, 0, 0)`); `makeOrthonormalises` (direction (0, 2, 0), up (0, 1, 1) → up (0, 0, 1)); `parallelUpIsNil`; `validateRefuses` (the sentence);
    `arcBoundsUseExtremes` (centre (0, 0), radius 2, start 0, sweep π → min (−2, 0), max (2, 2)); `ellipseBoundsAreExact` (major axis
    (1, 0), radii 5 and 3, full sweep → ±5 × ±3; major axis rotated 90° → ±3 × ±5); `projectionBoundsCoverHiddenLines`.
  - `FakeKernelProjectionTests`: `aBoxSeenFromTheFrontIsItsRectangle` (a 10 × 20 × 30 box at the origin → 4 visible sharp lines spanning x 0…10,
    y 0…30, sources four distinct edges); `aCurveProjectsAsACurveLine`; `aTiltedDirectionIsUnsupported`; `theDefaultRefuses` (a minimal
    `Kernel` conformer without the method throws "projecting views"); `theHookCanHoldACall` (a hook suspending on a continuation; the call
    returns after it is resumed); `compoundRefusesWithoutAHook` (the old sentence) and `aCompoundHookAnswers` (its solid comes back, called
    once).
- [ ] **Step 2: Run** `swift test --filter 'Rect2DTests|ProjectionTypesTests|FakeKernelProjectionTests'`; compile failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter, then `swift test --filter CreatorKernelTests` and `--filter CreatorGeometryTests`; pass.
- [ ] **Step 5: Commit** "Drawings: projection types and the kernel call".

### Task 2: Hidden-line projection in OpenCascade (the spike, the shim, TKHLR everywhere)

**Files:**
- Create: `Sources/COCCT/cocct_projection.cpp`, `Sources/CreatorOCCT/OCCTKernel+Projection.swift`
- Modify: `Sources/COCCT/include/cocct.h`, `Package.swift` (`"TKHLR"` in `occtLibraries`, after `"TKOffset"`), `scripts/linux/Dockerfile`
  (`TKHLR` in `BUILD_ADDITIONAL_TOOLKITS`, same place), `Tests/CreatorAppTests/CIPinTests.swift`
- Test: `Tests/CreatorOCCTTests/ProjectionTests.swift`

**Interfaces:**
- Consumes: Task 1's types and requirement; `OCCTCancelFlag`, `OCCTKernel.shape(of:)`, `curveShape(of:)`, `Self.serialized`.
- Produces: `OCCTKernel.projection(of:curves:frame:options:)` (R9, R10).
  - Shim: `occt_projection(const occt_shape *solid /* may be NULL */, const occt_shape *const *curves, int curve_count, const double
    direction[3], const double up[3], double tolerance, const occt_cancel *cancel, occt_projection_result *out, occt_status *status)`, freed
    by `occt_projection_free`. `occt_projection_result` holds `occt_projected_line *lines; int line_count; double *points; int
    point_count;` and each `occt_projected_line` `int visibility` (0 visible, 1 hidden), `int line_class` (0 sharp, 1 smooth, 2 outline,
    4 curve; 3 is never written: Swift assigns sheet boundaries), `int source_kind` (0 edge, 1 face, 2 curve, −1 none), `int source_index`
    (0-based in the solid's edge or face map, or the input curve's index), `int source_piece` (the curve edge's place in its wire), `int
    geometry` (0 line, 1 arc, 2 ellipse, 3 polyline), `double numbers[9]` (line x0 y0 x1 y1; arc cx cy r start sweep; ellipse cx cy ax ay
    R r start sweep), `int point_offset, point_count` (polyline points as x, y pairs in `points`).
  - The projector is `HLRAlgo_Projector(gp_Ax2(origin, −direction, right))` (the main direction points at the viewer); the shim checks
    that a point on +right lands at +x and one on +up at +y, so the 2D coordinates are R5's.
  - Swift: lines with `source_kind` 0 whose edge `isBoundary` become `.sheetBoundary`; zero-length lines (an edge seen end on) are dropped.

- [ ] **Step 1: The spike.** Before the full shim, write the reading loop over `HLRBRep_Data` for a box and a cylinder and the tests
  `spikeSourcesMapToTheInputsEdges` and `aCylinderSideOnHasTwoOutlines` (below), with R10's five-step source rule (split pieces, input
  edges, outlines, dropped internal and iso lines, by `IsSame` over `EdgeMap()`; never by index order); time the bracket's four views. If
  the data's edges cannot be resolved to the input's this way (R10),
  stop, implement R10's fallback instead, and record which path was taken, the timing and why in the report and in one ledger line;
  the controller adds the erratum to R10.
- [ ] **Step 2: Tests** (all OCCT-gated; a box is 10 × 20 × 30 at the origin, a cylinder radius 5, height 20, axis +Z from the origin):
  - `spikeSourcesMapToTheInputsEdges`: the box from the front → visible sharp lines whose **set** of sources is exactly the 4 edges of the
    face with normal (0, −1, 0) (several lines may share a source, if HLR split an edge; together they cover each edge's projected length
    within 1e-9); every hidden line's source is an edge of the face with normal (0, 1, 0) or an edge running front to back seen end on
    (dropped as zero length); no line has no source. The test never compares HLR's edge order with `TopExp::MapShapes`.
  - `aBoxFromTheFrontIsTrueSize`: the visible lines' bounds are x 0…10, y 0…30 within 1e-9.
  - `anIsometricBoxShowsNineVisibleEdges` (front right): visible lines from 9 distinct edges, hidden lines from the other 3, all sharp, all
    line geometry.
  - `aCylinderSideOnHasTwoOutlines` (front): the visible `.outline` lines lie at x = −5 and x = +5 (one or more pieces at each, all sourced
    `.face(the cylindrical face)`, each side's pieces covering y 0…20); each circle edge's visible lines (split pieces where the outlines meet
    it resolve to that circle edge, R10 step 1) together span x −5…5 at its height; no line is sourced from the seam and none has no source.
  - `aCylinderEndOnIsACircle` (top): visible arcs of radius 5 within 1e-9, all sourced from the top circle edge, whose sweeps add up to 2π
    (one arc unless HLR split the edge).
  - `aTiltedCircleIsAnExactEllipse` (isometric front right): the top circle edge is `.ellipse` with radii 5 and 5/√3 within 1e-9.
  - `aSplineEdgeIsAPolylineWithinTolerance`: a smooth Loft of three circles seen from the front → its side's outlines are polylines; every
    point lies within 0.01 mm of the outline found at tolerance 1e-4.
  - `tangentEdgesAreSmooth`: a box with one 2 mm fillet (Fillet node path via the kernel) from the front → the fillet's two tangent edges are
    `.smooth`, visible.
  - `aSheetsEdgesAreSheetBoundaries`: a Planar Surface square seen from the top → 4 visible `.sheetBoundary` lines.
  - `curvesAreHiddenBehindTheSolid`: a line curve at y = −10 in front of the box → visible `.curve`, source `.curve(index: 0, piece: 0)`; the
    same line at y = 40 behind it → hidden where the box covers it.
  - `severalSolidsHideEachOther`: two boxes compounded (`compound`), one behind the other → the far one's covered edges are hidden.
  - `noSolidAndNoCurvesIsEmpty`; `aZeroDirectionIsRefused` (`validate`'s sentence); `cancellationStops` (a cancelled task throws
    `CancellationError`).
  - `theBracketsFourViewsProject` (the §7.2 bracket built through the kernel as `NamingStabilityTests` builds it; move its builder to
    `Tests/CreatorOCCTTests/Support/` if both need it): Front, Right, Top and Isometric each give
    lines, every source index inside the topology; print `PROJECTION bracket <view> <lines> <ms>`.
  - `CIPinTests.theOCCTToolkitsAgreeEverywhere`: the toolkit list in `Package.swift` equals the `BUILD_ADDITIONAL_TOOLKITS` list in
    `scripts/linux/Dockerfile`, both include `TKHLR`.
- [ ] **Step 3: Run** `swift test --filter 'ProjectionTests|CIPinTests'`; fail.
- [ ] **Step 4: Implement** the shim (R10) and the Swift wrapper (`withTaskCancellationHandler`, a `CancellationError` for the flag's sentence,
  `KernelError.occt("projection", …)` otherwise), and the two toolkit lists.
- [ ] **Step 5: Run** the filter; `swift test --filter CreatorOCCTTests`; `XP_TRACK=dr-1 IMAGE=metalcreator-linux:dr-1 scripts/linux-test.sh
  test --filter ProjectionTests` (the image rebuilds OpenCascade with TKHLR; afterwards remove only this run's volume and image); pass.
  Windows: vcpkg's `opencascade` port builds TKHLR with ModelingAlgorithms; CI's first run confirms it links.
- [ ] **Step 6: Commit** "Drawings: hidden-line projection (HLRBRep), TKHLR on every platform".

### Task 3: The CreatorDrawing module and the drawing model

**Files:**
- Create: `Sources/CreatorDrawing/Model/` (`SheetID.swift`, `ViewID.swift`, `DrawingStandard.swift`, `SheetSize.swift`, `DrawingScale.swift`,
  `StandardOrientation.swift`, `ViewOrientation.swift`, `DrawingView.swift`, `TitleBlock.swift`, `DrawingSheet.swift`, `DrawingSettings.swift`,
  `DrawingDocument.swift`), `Sources/CreatorDrawing/Style/DrawingStyle.swift`
- Modify: `Package.swift` (target `CreatorDrawing` with `["CreatorKernel", "CreatorGeometry"]`; test target `CreatorDrawingTests` with
  `["CreatorDrawing", "CreatorKernel", "CreatorGeometry", "CreatorGraph"]`: CreatorGraph only for `SHA256` in later digest tests)
- Test: `Tests/CreatorDrawingTests/DrawingModelTests.swift`, `Tests/CreatorDrawingTests/DrawingStyleTests.swift`

**Interfaces:**
- Consumes: `ProjectionFrame` (Task 1), `NodeID`.
- Produces (**every public type below is declared `Sendable`**: Swift does not infer `Sendable` for a public type across modules, and
  `DrawingDocument` and `DrawingView` are `Sendable` and hold them, so under Swift 6 each must say it; `ProjectionFrame` and `NodeID` already
  are):
  - `SheetID`, `ViewID`: UUID wrappers shaped exactly like `CommentID` (`Hashable, Sendable, Comparable, Codable`, Codable as a bare UUID,
    `Comparable` by `uuidString`).
  - `public enum DrawingStandard: String, Sendable, Codable, CaseIterable { case iso, asme }`, `isFirstAngle` (iso true).
  - `public enum SheetSize: String, Sendable, Codable, CaseIterable { case a4, a3, a2, a1, a0, ansiA, ansiB, ansiC, ansiD, ansiE }`,
    `portrait: Vector2` (R14's table), `title` ("A3", "B"), `isLarge` (A0 to A2, ANSI C to E: the 3.5 mm notes); `public enum
    SheetOrientation: String, Sendable, Codable { case landscape, portrait }`.
  - `public struct DrawingScale: Hashable, Sendable, Codable { public var numerator: Int; public var denominator: Int }`, `value: Double`,
    `static let preferred: [DrawingScale]` (R8, largest first), `text(for: DrawingStandard) -> String`, `isValid` (1 to 1000 each).
  - `public enum StandardOrientation: String, Sendable, Codable, CaseIterable { case front, back, left, right, top, bottom,
    isometricFrontRight, isometricFrontLeft }`, `frame: ProjectionFrame` (R5), `title` ("Front", …, "Isometric"), `isIsometric`.
  - `public enum ViewOrientation: Hashable, Sendable, Codable { case standard(StandardOrientation); case custom(ProjectionFrame) }`,
    `frame`, `isIsometric` (custom: direction not along an axis within 1e-9).
  - `public enum ViewKind: String, Sendable, Codable { case base, projected }`; `public enum AlignmentAxis: String, Sendable, Codable {
    case horizontal, vertical }`; `public struct ViewAlignment: Hashable, Sendable, Codable { public var parent: ViewID; public var axis:
    AlignmentAxis }`.
  - `public struct DrawingView: Hashable, Sendable, Codable, Identifiable { id: ViewID; kind: ViewKind; source: NodeID; orientation:
    ViewOrientation; scale: DrawingScale?; center: Vector2; alignment: ViewAlignment?; showsHidden = false; showsTangent = true;
    showsLabel = false }`.
  - `public struct TitleBlock: Hashable, Sendable, Codable { owner, title, drawingNumber, revision, material, drawnBy, date: String; density:
    Double? }` (empty strings by default; keys written only when non-empty or non-nil).
  - `public struct DrawingSheet: Hashable, Sendable, Codable, Identifiable { id: SheetID; name: String; size: SheetSize; orientation:
    SheetOrientation; scale: DrawingScale; titleBlock: TitleBlock; views: [DrawingView] }`, `paperSize: Vector2` (landscape swaps), views
    kept sorted by id (`setView(_:)` inserts sorted, `removeView(_:)`), `view(_ id:)`.
  - `public struct DrawingSettings: Hashable, Sendable, Codable { standard = .iso; generalTolerance: String; titleBlockDefaults: TitleBlock }`,
    `static func defaultTolerance(for: DrawingStandard, inches: Bool) -> String` (R15's three strings).
  - `public struct DrawingDocument: Hashable, Sendable, Codable { settings: DrawingSettings; sheets: [DrawingSheet] }`, `isEmpty` (no sheet),
    `sheet(_ id:)`; sheets encoded in order (R3); a view whose alignment names a view not on its sheet's list is **kept** on decoding and
    only its alignment is dropped (`alignment = nil`: the view becomes free at its stored centre); the same for an alignment that would
    make a cycle.
  - `public struct DrawingStyle: Hashable, Sendable` with `thick`, `thin`, `frame` (0.7), `zone` (0.35), `hiddenDash` (3), `hiddenGap` (1.5),
    `notesHeight(for: SheetSize)`, `titleHeight`, `viewLabelHeight`, `fieldLabelHeight` (1.8), `zoneLabelHeight` (3.5); `static let iso`,
    `static let asme` (R11), `static func of(_ standard: DrawingStandard) -> DrawingStyle`.

- [ ] **Step 1: Tests.** `aDocumentRoundTrips` (two sheets, three views with a custom frame and an alignment, a title block with a density: encode
  then decode equal); `sheetsKeepTheirOrder` (sheet ids out of order stay in tab order); `viewsAreSortedById` (inserted in reverse, encoded
  sorted); `emptyTitleFieldsAreNotWritten` (the JSON has no `owner` key); `aDanglingAlignmentIsDropped` (the view is still on the sheet, at its
  centre, with `alignment == nil`); `everyModelTypeIsSendable` (a generic `requireSendable<T: Sendable>(_: T.Type)` called with each public type;
  it compiles only if they are); `landscapeSwapsTheSize` (A3 landscape
  420 × 297); `preferredScalesAreISO5455` (the fifteen of R8, in order); `scaleText` ("1 : 2", "2 : 1", "1:2" for ASME); `orientationFrames`
  (R5's table, each frame orthonormal); `isometricFramesAreIsometric`; `styleConstants` (ISO thick 0.5, thin 0.25, dashes 3 and 1.5, notes 2.5 on
  A3 and 3.5 on A1, titles 7, labels 5; ASME thick 0.6, thin 0.3, notes 3, titles 6); `defaultTolerances` (R15's strings).
- [ ] **Step 2: Run** `swift test --filter CreatorDrawingTests`; compile failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter; pass.
- [ ] **Step 5: Commit** "Drawings: the CreatorDrawing model".

### Task 4: File format 17 and the drawing view state

**Files:**
- Modify: `Package.swift` (`CreatorGraph` gains `"CreatorDrawing"`; `CreatorGraphTests` too), `Sources/CreatorGraph/Graph.swift` (`drawings`),
  `Sources/CreatorGraph/GraphCommand.swift`, `Sources/CreatorGraph/Graph+Commands.swift`, `Sources/CreatorGraph/Groups/GraphContent+Apply.swift`,
  `Sources/CreatorGraph/GraphFile.swift` (17 and its doc comment), `Sources/CreatorGraph/ViewState.swift`, `Sources/CreatorGraph/DocumentModel.swift`
  (`drawings`, `drawingView` with the other view-state properties), `Sources/CreatorGraph/UndoName.swift`, and every exhaustive `switch` over
  `GraphCommand` the compiler names
- Create: `Sources/CreatorGraph/DrawingViewState.swift`
- Test: `Tests/CreatorGraphTests/DrawingsFileTests.swift`

**Interfaces:**
- Consumes: Task 3's `DrawingDocument`, `SheetID`.
- Produces: `Graph.drawings: DrawingDocument` (default empty; key `drawings` written only when it has a sheet); `GraphCommand.setDrawings(DrawingDocument)`
  (R2; refused inside a definition with "Drawings belong to the document, not to a group."); `DocumentModel.drawings: DrawingDocument`
  (`content.graph.drawings`); `GraphFile.currentFormatVersion == 17`; `public struct DrawingViewState: Hashable, Sendable, Codable { isOn: Bool;
  sheet: SheetID? }`, `ViewState.drawing: DrawingViewState?` (optional key, a damaged entry reads nil) and `DocumentModel.drawingView`
  (observable, set without an edit, as `section` is); `UndoName.editDrawing = "Edit Drawing"`, `UndoName.drawing(_ name: String) -> String`.

- [ ] **Step 1: Tests.** `theFormatIs17`; `aDocumentWithoutDrawingsHasNoKey`; `drawingsRoundTripThroughAFile` (`GraphFileIO` write then read);
  `aFormat16FileOpens` (an existing fixture decodes, `drawings` empty); `setDrawingsIsUndoable` (perform, undo restores the old document, redo
  the new; "Undo Add Sheet" with `name: UndoName.drawing("Add Sheet")`); `setDrawingsDoesNotEvaluate` (`affectsResults` false; a held
  evaluation count is unchanged); `drawingsMakeTheDocumentEdited` (content differs from the saved content); `setDrawingsInsideADefinitionIsRefused`;
  `drawingViewStateRoundTrips` and `isNotAnEdit`; `aBlankNameIsEditDrawing`.
- [ ] **Step 2: Run** `swift test --filter DrawingsFileTests`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `swift test --filter CreatorGraphTests`; `swift build` (every target compiles); pass.
- [ ] **Step 5: Commit** "Drawings: file format 17".

### Task 5: Lettering, the sheet frame and the title block

**Files:**
- Create: `Sources/CreatorDrawing/Text/HelveticaMetrics.swift` (the WinAnsi table and the AFM widths), `Sources/CreatorDrawing/Text/DrawingText.swift`,
  `Sources/CreatorDrawing/Picture/SheetPicture.swift` (`SheetPicture`, `SheetStroke`, `SheetSegment`, `SheetText`, `StrokePattern`, `DrawingLayer`),
  `Sources/CreatorDrawing/Picture/SheetSegment+Cubics.swift`, `Sources/CreatorDrawing/Sheet/SheetFrame.swift`,
  `Sources/CreatorDrawing/Sheet/TitleBlockLayout.swift`, `Sources/CreatorDrawing/Sheet/TitleBlockFacts.swift`,
  `Sources/CreatorDrawing/Sheet/DrawingArea.swift`, `Sources/CreatorDrawing/Symbols/DrawingSymbols.swift`,
  `Sources/CreatorDrawing/Text/ReplacedTexts.swift`
- Test: `Tests/CreatorDrawingTests/HelveticaMetricsTests.swift`, `DrawingTextTests.swift`, `SheetFrameTests.swift`, `TitleBlockTests.swift`,
  `DrawingSymbolsTests.swift`, `CubicsTests.swift`, `ReplacedTextsTests.swift`

**Interfaces:**
- Consumes: Task 3.
- Produces:
  - `HelveticaMetrics.winAnsi(_ character: Character) -> UInt8?` (Windows-1252, with its 0x80–0x9F assignments), `advance(of byte: UInt8) -> Int`
    (1/1000 em, Adobe Core 14 `Helvetica.afm`; the implementer copies the table from that public AFM), `capHeight = 718`.
  - `DrawingText.layout(_ text: String, height: Double) -> TextRun`; `public struct TextRun: Hashable, Sendable { bytes: [UInt8]; offsets:
    [Double] (each glyph's x from the run's start, mm); width: Double; hasReplacements: Bool; shown: String (the WinAnsi string drawn, "?"
    in place of what was replaced) }`; `DrawingText.fitted(_ text: String, height: Double, width: Double) -> (run: TextRun, height: Double)` (R13's
    shrink to 1.8 mm, then cut with "…").
  - `public enum SheetSegment: Hashable, Sendable { case line(Vector2, Vector2); case arc(center: Vector2, radius: Double, start: Double, sweep:
    Double); case ellipse(center: Vector2, majorAxis: Vector2, majorRadius: Double, minorRadius: Double, start: Double, sweep: Double); case
    polyline([Vector2]) }`, `cubics() -> [CubicPiece]` (`CubicPiece { start, control1, control2, end: Vector2 }`; lines as one degenerate cubic are not
    produced: `cubics()` is for arcs and ellipses, each piece at most 90°, control length `4/3 tan(θ/4)`), `transformed(scale: Double, offset:
    Vector2)`, `bounds: Rect2D`.
  - `public enum StrokePattern: Hashable, Sendable { case solid, hidden }`; `public enum DrawingLayer: String, CaseIterable, Sendable { case visible =
    "VISIBLE", hidden = "HIDDEN", tangent = "TANGENT", center = "CENTER", dimension = "DIMENSION", text = "TEXT", hatch = "HATCH", frame = "FRAME" }`.
  - `public struct SheetStroke: Hashable, Sendable { segments: [SheetSegment]; width: Double (mm); pattern: StrokePattern; layer: DrawingLayer;
    view: ViewID? }`; `public struct SheetText: Hashable, Sendable { run: TextRun; original: String; origin: Vector2 (baseline left, mm); height: Double;
    layer: DrawingLayer; view: ViewID? }`; `public struct SheetPicture: Hashable, Sendable { size: Vector2; strokes: [SheetStroke]; texts: [SheetText];
    viewFrames: [ViewID: Rect2D] }` (`viewFrames` read only by lookup, never iterated into output).
  - `SheetFrame.picture(for sheet: DrawingSheet, standard: DrawingStandard) -> SheetPicture` (border, frame, zones, labels, centring marks; R14).
  - `public enum TitleBlockKey: String, CaseIterable, Sendable { case owner, drawnBy, date, title, material, mass, scale, projection, drawingNumber,
    revision, size, sheet, tolerance }` (R15's rows in order; `isTyped` for owner, drawnBy, date, title, material, drawingNumber, revision and tolerance,
    whose value is `TitleBlock`'s field, or `DrawingSettings.generalTolerance` for tolerance).
  - `TitleBlockLayout.fields(for: DrawingStandard) -> [TitleBlockField]` (`TitleBlockField { key: TitleBlockKey; rect: Rect2D; valueHeight: Double;
    label: String }`, `Hashable, Sendable`, R15's table in order), `TitleBlockLayout.picture(sheet: DrawingSheet, settings: DrawingSettings, facts: TitleBlockFacts, sheetIndex: Int,
    sheetCount: Int) -> SheetPicture` (placed by R15; the projection symbol from `DrawingSymbols`).
  - `public struct TitleBlockFacts: Hashable, Sendable { massText: String? }` and `TitleBlockFacts.massText(grams: Double, inches: Bool) -> String`
    (R16); `TitleBlockLayout` writes size, sheet ("1 / 3") and scale itself from the sheet and its place.
  - `DrawingArea.rect(for sheet: DrawingSheet, standard: DrawingStandard) -> Rect2D` (R8's area).
  - `DrawingSymbols.projectionSymbol(firstAngle: Bool, center: Vector2, h: Double) -> [SheetStroke]` and
    `DrawingSymbols.projectionSymbolSize(h: Double) -> Vector2` (6h × 2h, the centre line's overrun included; R17). `TitleBlockLayout`
    passes h = 2.5 and the projection field's centre.
  - `ReplacedTexts.collect(_ texts: [SheetText]) -> [String]` (R13: the distinct `original`s of the texts whose `run.hasReplacements`,
    first-seen order; `Sources/CreatorDrawing/Text/ReplacedTexts.swift`), shared by both writers.

- [ ] **Step 1: Tests.**
  - `HelveticaMetricsTests`: `pinnedAdvances` (space 278, "A" 667, "H" 722, "W" 944, "a" 556, "i" 222, "m" 833, "0" to "9" 556, "." 278, "°" 400,
    "±" 584, "×" 584, "Ø" 778, "µ" 556, "…" 1000); `winAnsiMapsTheDrawingSymbols` (Ø 0xD8, ± 0xB1, ° 0xB0, × 0xD7, µ 0xB5, … 0x85, € 0x80);
    `outsideWinAnsiIsNil` (Ω, →, emoji); `theCapHeightIs718`.
  - `DrawingTextTests`: `widthIsTheSumOfAdvances` ("H1" at 3.5 mm = (722 + 556) / 1000 × 3.5 / 0.718); `offsetsAccumulate`;
    `aCharacterOutsideWinAnsiLaysOutAsAQuestionMark` ("Ω-Bracket →": `shown == "?-Bracket ?"`, `hasReplacements`, width uses "?"'s 556);
    `fittingShrinksThenCuts` (a 60-character title in a 107 mm field at 7 mm: smaller height; a 400-character one: 1.8 mm and ends with "…").
  - `SheetFrameTests`: `isoFrameMargins` (A3 landscape: frame from (20, 10) to (410, 287), width 0.7); `zoneCountsMatchISO5457` (A0 24 × 16, A1 16 ×
    12, A2 12 × 8, A3 landscape 8 × 6, A4 portrait 4 × 6); `isoZoneLabels` (A3: letters "A" at the top through "F", numbers "1" at the left through
    "8"); `asmeZoneLabels` (letters from the bottom, numbers from the right); `centringMarksAreISOOnly`; `asmeMarginsAreHalfAnInch`.
  - `TitleBlockTests`: `theBlockSitsInTheFramesCorner` (A3: block from (230, 10) to (410, 50)); `fieldsMatchTheTable` (13 fields, the title's rect
    (0, 10)–(110, 30) offset by the origin); `automaticValues` ("A3", "2 / 3", "1 : 2"; ASME "B", "2 OF 3", "1:2"); `massText` (8.4 g, 84 g, 1.234 kg,
    2.721 lb); `anEmptyMassLeavesTheFieldEmpty`; `labelsPerStandard`.
  - `DrawingSymbolsTests`: `firstAngleHasTheCirclesOnTheRight`; `thirdAngleHasTheCirclesOnTheLeft`; `proportionsFollowH` (circle radii h and h/2,
    trapezoid ends 2h and h, all strokes thin, the strokes' bounds exactly `projectionSymbolSize(h:)` about the centre);
    `theSymbolLiesInsideItsField` (ISO and ASME, A3 and A0: the title block's symbol strokes' bounds lie inside the projection field's rect
    (162–180 × 10–20 from the block's corner) inset by 1 mm).
  - `ReplacedTextsTests`: `eachOriginalOnce` (the same original on two texts is listed once; two different ones in first-seen order; a text
    without replacements is not listed).
  - `CubicsTests`: `aQuarterArcIsOnePiece` (control points within 1e-12 of the 4/3 tan(π/8) construction); `aFullCircleIsFourPieces`;
    `piecesStayOnTheCircle` (the midpoint of each cubic within 3e-4 × radius); `anEllipseIsAnAffineCircle`.
- [ ] **Step 2: Run** `swift test --filter 'HelveticaMetricsTests|DrawingTextTests|SheetFrameTests|TitleBlockTests|DrawingSymbolsTests|CubicsTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: lettering, sheet frame and title block".

### Task 6: Views on the sheet (placement, scale choice, ISO 128 linework, the composer)

**Files:**
- Create: `Sources/CreatorDrawing/Views/ProjectedViewRule.swift`, `ViewPlacement.swift`, `ScaleChooser.swift`, `ViewExtents.swift`, `ViewLinework.swift`,
  `ViewContent.swift`, `ViewLabel.swift`, `Sources/CreatorDrawing/Picture/SheetComposer.swift`, `Sources/CreatorDrawing/Picture/SheetHitTest.swift`
- Test: `Tests/CreatorDrawingTests/ProjectedViewRuleTests.swift`, `ViewPlacementTests.swift`, `ScaleChooserTests.swift`, `ViewLineworkTests.swift`,
  `SheetComposerTests.swift`, `SheetHitTestTests.swift`

**Interfaces:**
- Consumes: Tasks 1, 3, 5.
- Produces:
  - `ProjectedViewRule.view(from parent: ProjectionFrame, dropOffset: Vector2, standard: DrawingStandard) -> (frame: ProjectionFrame, axis:
    AlignmentAxis)` (R6); `ProjectedViewRule.refusal(for parent: DrawingView) -> String?` (the isometric sentence).
  - `ViewPlacement.centers(in sheet: DrawingSheet) -> [ViewID: Vector2]` (R7, parents first); `ViewPlacement.moving(_ id: ViewID, by delta: Vector2, in
    sheet: DrawingSheet) -> DrawingSheet` (descendants follow; an aligned view moves along its free axis only); `ViewPlacement.mirroredForStandardChange(_
    sheet: DrawingSheet) -> DrawingSheet`; `ViewPlacement.removing(_ id: ViewID, from sheet: DrawingSheet) -> DrawingSheet` (children freed).
  - `ViewExtents.of(_ bounds: BoundingBox, frame: ProjectionFrame) -> (width: Double, height: Double, depth: Double)` (the 8 corners).
  - `ScaleChooser.firstScale(extents: (width: Double, height: Double, depth: Double)?, area: Rect2D) -> DrawingScale` (R8).
  - `public struct ViewContent: Hashable, Sendable { projection: Projection2D?; isPending: Bool; problem: String?; warnings: [String]; lastSize: Vector2? }`.
  - `ViewLinework.strokes(for projection: Projection2D, view: DrawingView, center: Vector2, scale: Double, style: DrawingStyle) -> [SheetStroke]` (R11;
    the projection's bounds centre goes to `center`; with `center` = bounds centre and `scale` 1 it is the view in model mm, which Task 8's 1:1 DXF uses);
    `ViewLinework.frame(for projection: Projection2D, center: Vector2, scale: Double) -> Rect2D?`.
  - `ViewLabel.text(for view: DrawingView, sheet: DrawingSheet, standard: DrawingStandard) -> String` (R18).
  - `SheetComposer.compose(_ sheet: DrawingSheet, in document: DrawingDocument, contents: [ViewID: ViewContent], facts: TitleBlockFacts) -> SheetPicture`:
    frame and title block (Task 5), then each view in id order: its strokes, its label, and, for a view without a projection, its frame rectangle
    (thin, solid) with its problem centred inside at the notes height (`lastSize`, else 40 × 30 mm); a pending or failed view's strokes are composed as usual
    (fading is the screen's). `sheetIndex` and `sheetCount` come from `document`.
  - `SheetHitTest.view(at point: Vector2, in picture: SheetPicture, order: [ViewID]) -> ViewID?` (topmost by `order`, frames grown by 2 mm);
    `SheetHitTest.line(near point: Vector2, in picture: SheetPicture, view: ViewID, tolerance: Double) -> Int?` (the index into `picture.strokes`).

- [ ] **Step 1: Tests.**
  - `ProjectedViewRuleTests`: the eight cases of R6's table from a Front parent (e.g. first angle, dropped right → direction (1, 0, 0), up (0, 0, 1),
    horizontal; third angle, dropped above → direction (0, 0, −1), up (0, 1, 0), vertical); `aDiagonalDropTakesTheLargerOffset`; `anIsometricParentIsRefused`.
  - `ViewPlacementTests`: `childrenShareTheirParentsCoordinate`; `movingAParentCarriesItsChildren` (and a grandchild); `draggingAChildSlidesAlongItsAxis`;
    `switchingTheStandardMirrorsChildren` (a first-angle right view at +80 mm becomes −80 mm, a grandchild above it moves with it, frames unchanged);
    `removingAParentFreesChildren`; `aCycleLeavesViewsFree`.
  - `ScaleChooserTests`: `aSmallPartGetsAnEnlargement` (a 10 × 10 × 10 box on A3 → 5:1); `aLargePartGetsAReduction` (300 × 200 × 100 → 1:2);
    `nothingFitsGivesTheSmallest`; `noBoundsGivesFullSize`.
  - `ViewLineworkTests`: `classesFollowISO128` (visible sharp thick solid VISIBLE; hidden sharp thin hidden HIDDEN only with `showsHidden`; smooth thin solid
    TANGENT only with `showsTangent`; hidden smooth never; outline and sheet boundary as sharp; curves thick); `aViewOverrideScalesOnlyThatView` (2:1 on a
    1:1 sheet: a 10 mm line becomes 20 mm, the sheet's other view unchanged, the label reads "Front (2 : 1)" when shown); `theBoundsCentreLandsOnTheCentre`;
    `arcsStayArcs` (a projected circle keeps `.arc` with its radius × scale).
  - `SheetComposerTests`: `aComposedSheetHasFrameTitleBlockAndViews`; `aViewWithoutProjectionDrawsItsFrameAndProblem` ("The Output this view showed was
    removed." inside a 40 × 30 mm rectangle); `composingIsDeterministic` (two composes of the same input are equal, views in id order); `facts` (mass and
    scale texts appear in their fields).
  - `SheetHitTestTests`: `theTopmostViewWins`; `aLineWithinToleranceIsFound`; `nothingNearIsNil`.
- [ ] **Step 2: Run** `swift test --filter 'ProjectedViewRuleTests|ViewPlacementTests|ScaleChooserTests|ViewLineworkTests|SheetComposerTests|SheetHitTestTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: views on the sheet".

### Task 7: PDF export (PDFWriter)

**Files:**
- Create: `Sources/CreatorDrawing/Export/PDFWriter.swift`, `Sources/CreatorDrawing/Export/PDFNumber.swift`
- Test: `Tests/CreatorDrawingTests/PDFWriterTests.swift`, `Tests/CreatorDrawingTests/Support/PDFStructureReader.swift`,
  `Tests/CreatorDrawingTests/Support/DrawingFixtures.swift` (shared with Task 8: a fixed A4 sheet with a box and a cylinder view built from hand-made
  `Projection2D`s, a title block including "Ø20 ±0.1 µm 90°", no kernel)

**Interfaces:**
- Consumes: Tasks 5 and 6 (`SheetPicture`, `SheetSegment.cubics()`).
- Produces: `PDFWriter.write(_ pages: [SheetPicture], title: String) -> PDFOutput`; `public struct PDFOutput: Sendable { data: Data; replacedTexts:
  [String] }` (`ReplacedTexts.collect` over every page's texts in page then drawing order: each distinct original once, R13); `PDFNumber.format(_
  value: Double, decimals: Int) -> String` (R23).
- Test reader (tests only): `PDFStructureReader(data:)` checks the header, finds `startxref`, reads the xref table, checks that each entry's offset starts
  `N 0 obj`, checks every xref entry is exactly 20 bytes ending " \n" (R23), reads the trailer's `/Size` and `/Root`, and returns each page's
  `MediaBox` and decoded content operators.

- [ ] **Step 1: Tests.** `theStructureIsValid` (reader: objects 1 to 4 then two per page, xref entries 20 bytes each and each ending with a space and an
  LF, the free entry `0000000000 65535 f \n`, no CR anywhere in the xref, `/Size` right); `pagesAreTrueSize`
  (A4 portrait `MediaBox` [0 0 595.2756 841.8898]; A3 landscape [0 0 1190.5512 841.8898]); `aHalfScaleViewMeasuresHalfOnPaper` (a 100 mm box line at 1:2: the
  two points of its stroke, through the `cm` matrix, are 141.7323 pt apart); `lineWidthsAndDashesAreISO` (`0.5 w` for thick, `0.25 w` and `[3 1.5] 0 d`
  for hidden); `arcsAreCubics` (a circle is four `c` operators); `textUsesHelveticaWinAnsi` (the font object; "Ø20" written `(\33020)`); `escapes` (`(`, `)`,
  `\`); `replacedTextsAreReported` ("Ω-Bracket →" written `(?-Bracket ?)` and listed once, also when it is the title on both pages of a two-page PDF); `noDatesNoID`; `numbersAreLocaleFree` (`PDFNumber.format(-0.00001,
  decimals: 4) == "0"`, `1.5`, `-2.25`, `1190.5512`); `theFixturesDigestIsPinned` (SHA-256 of the fixture's bytes equals a pinned hex string, the same on
  macOS, Linux and Windows).
- [ ] **Step 2: Run** `swift test --filter PDFWriterTests`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `swift test --filter CreatorDrawingTests`; the Linux run of the filter (`XP_TRACK=dr-1 …`) gives the same digest; pass.
- [ ] **Step 5: Commit** "Drawings: PDF export".

### Task 8: DXF export (DXFWriter, Sheet and View at 1:1)

**Files:**
- Create: `Sources/CreatorDrawing/Export/DXFWriter.swift`, `Sources/CreatorDrawing/Export/DXFTables.swift`
- Test: `Tests/CreatorDrawingTests/DXFWriterTests.swift`, `Tests/CreatorDrawingTests/Support/DXFReader.swift`

**Interfaces:**
- Consumes: Tasks 5 and 6, Task 7's fixtures.
- Produces: `public struct DXFOutput: Sendable { data: Data; replacedTexts: [String] }` (`ReplacedTexts.collect` over the texts written, R13);
  `DXFWriter.write(strokes: [SheetStroke], texts: [SheetText], extent: Rect2D, style: DrawingStyle) -> DXFOutput` (R24; `extent` gives the LAYOUTs'
  limits and extents); `DXFWriter.sheet(_ picture: SheetPicture, style:) -> DXFOutput`; `DXFWriter.view(_ projection: Projection2D, view: DrawingView,
  style:) -> DXFOutput` (R24's 1:1: `ViewLinework.strokes` with `scale` 1 and `center` the projection's bounds centre, then translated back so
  coordinates are R5's view-plane coordinates; a 1:1 view has no texts in DR-1, so its list is empty).
- Test reader (tests only): `DXFReader(data:)` reads code/value pairs, sections, the header variables, the LAYER, LTYPE and BLOCK_RECORD tables, the OBJECTS
  section and the ENTITIES list as `(type, layer, values by code)`; checks every handle is unique, every owner names an existing handle, `$HANDSEED` is greater
  than every handle, and R24's AutoCAD links: the root dictionary names `ACAD_GROUP`, `ACAD_LAYOUT`, `ACAD_MLINESTYLE`, `ACAD_PLOTSETTINGS` and
  `ACAD_PLOTSTYLENAME`; `ACAD_LAYOUT` names `Model` and `Layout1`; each space BLOCK_RECORD's 340 names a LAYOUT whose block-record pointer (330 after
  `AcDbLayout`) names that BLOCK_RECORD back; every entity's owner is `*Model_Space`'s BLOCK_RECORD.

- [ ] **Step 1: Tests.** `theHeaderIsR2000InMillimetres` (`$ACADVER` AC1015, `$INSUNITS` 4, `$HANDSEED` past every handle); `theObjectsAreWhatAutoCADExpects`
  (the reader's link checks above, in Sheet and View mode); `replacedTextsAreReported` (a title "Ω-Bracket →" written `?-Bracket ?` and listed once); `theEightLayersExist` (with HIDDEN on DASHED and CENTER on CENTER, the
  lineweights of R24); `linesArcsCirclesEllipsesAreTrue` (a full circle is one CIRCLE, a half arc one ARC with angles 0 and 180, the iso ellipse one ELLIPSE with
  ratio 1/√3, a polyline one LWPOLYLINE); `layersFollowTheLineClass` (hidden on HIDDEN, tangent on TANGENT, frame and zones on FRAME, title-block text on TEXT);
  `symbolsUseDXFCodes` ("Ø20 ±0.1 90°" → `%%c20 %%p0.1 90%%d`); `sheetAndViewModesMeasureTrue` (the 1:2 view's 100 mm line is 50 units in Sheet mode and 100 in
  View mode; View mode has no FRAME entities and keeps model x and y for a Top view of a box at (5, 7, 0)); `handlesAreUniqueAndOwned`; `writingIsDeterministic`
  (two writes byte-equal); `theFixturesDigestIsPinned`.
- [ ] **Step 2: Run** `swift test --filter DXFWriterTests`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: DXF export".

### Task 9: The projection cache and the projector

**Files:**
- Create: `Sources/CreatorDrawing/Projection/ProjectionCache.swift`, `Sources/CreatorDrawing/Projection/DrawingSourceContent.swift`,
  `Sources/CreatorDrawing/Projection/DrawingProjector.swift`
- Test: `Tests/CreatorDrawingTests/ProjectionCacheTests.swift`, `Tests/CreatorDrawingTests/DrawingProjectorTests.swift`

**Interfaces:**
- Consumes: Task 1 (`Kernel.projection`, `FakeKernel.setProjectionHook`), Task 6 (`ViewContent`).
- Produces:
  - `public actor ProjectionCache { init(limit: Int = 512 * 1024 * 1024); func projection(of solids: [Solid], curves: [Curve], compoundTag: NodeTag, frame:
    ProjectionFrame, options: ProjectionOptions, kernel: any Kernel) async throws -> Projection2D; func removeAll(); var bytesUsed: Int; var count: Int; var
    kernelCalls: Int; var compoundCalls: Int }` (R19). The key is the solids' and curves' `ObjectIdentifier`s in order (both are final classes), `compoundTag`,
    the frame and the options. On a miss: no solid passes
    nil to `Kernel.projection`, one solid passes it, two or more call `kernel.compound(solids, tag: compoundTag)` once and project the compound (R9); the
    entry keeps the input solids and curves (and the compound) alive.
  - `public struct DrawingSourceContent: Sendable { output: NodeID; name: String; state: State }` with `enum State { case removed; case failed(String);
    case evaluating; case ready(solids: [Solid], curves: [Curve], meshCount: Int) }` (the app builds it from results).
  - `public struct DrawingProjector: Sendable { cache: ProjectionCache; kernel: any Kernel }` and `func content(for view: DrawingView, scale: Double,
    source: DrawingSourceContent, previous: ViewContent?) async -> ViewContent` (R9: hands the source's solids to the cache, which compounds several, with
    `compoundTag` the Output node's tag, item 0; R20's sentences; a kernel or compound refusal becomes the
    `problem` in `Evaluator`'s words; `isPending` is false on return; `previous.projection` is kept for removed, failed and evaluating sources).
  - The projector is stateless; superseding requests is the caller's (Task 12).

- [ ] **Step 1: Tests** (`FakeKernel`, boxes from the front; holds by the projection hook suspending on a continuation, never a semaphore).
  - `ProjectionCacheTests`: `aRepeatIsAHit` (one kernel call); `identicalRequestsShareOneKernelCall` (two concurrent requests held by the hook, then released:
    one call, equal results); `aDifferentFrameOrToleranceMisses`; `aNewSolidIdentityMisses`; `theLimitEvictsLeastRecentlyUsed` (a 1 KB limit; the newest kept even
    when alone over the limit); `removeAllEmpties`; `aFailureIsNotCached` (a projection or a compound that throws); `cancellingOneWaiterLeavesTheOther`;
    `twoConcurrentMultiSolidRequestsCompoundOnce` (held by the projection hook: one compound, one projection).
  - `DrawingProjectorTests`: `aReadySourceProjects`; `severalSolidsAreCompounded` (without a compound hook FakeKernel's `compound` refuses → the problem is its sentence and nothing is
    cached; with one, the compound is what is projected; the OCCT variant
    lives in Task 2); `meshesAreLeftOutWithAWarning` (3 meshes beside a solid → the warning of R20; 1 mesh → the singular sentence); `onlyMeshesIsRefused`;
    `nothingYet`; `aRemovedOutputKeepsNoProjection` (problem "The Output this view showed was removed.", `projection == nil`, `lastSize` kept from
    `previous`); `aFailedOutputKeepsTheLastProjection`; `theToleranceFollowsTheScale` (scale 2 → `options.tolerance == 0.005`, seen through the cache key);
    `twoSolidsRequestedTwiceAreOneCompoundAndOneProjection` (`setCompoundHook` returning a box; the same two-solid source projected twice, then a second
    view of it with the same frame: `compoundCalls == 1`, `kernelCalls == 1`; a new identity for either solid misses and compounds again);
    (`aSupersededRequestNeverPublishes` is Task 12's: the ordering of requests is the app's.)
- [ ] **Step 2: Run** `swift test --filter 'ProjectionCacheTests|DrawingProjectorTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: projection cache and projector".

### Task 10: The drawing editor model

**Files:**
- Create: `Sources/CreatorDrawingEditor/` (`DrawingEditorModel.swift`, `DrawingEditorModel+Sheets.swift`, `DrawingEditorModel+Views.swift`,
  `DrawingEditorModel+Pointer.swift`, `DrawingEditorModel+Keys.swift`, `DrawingEditorModel+Inspector.swift`, `DrawingCommit.swift`, `DrawingEditorEvents.swift`,
  `DrawingStepName.swift`, `DrawingTool.swift`, `SheetTransform.swift`, `DrawingSourceOption.swift`, `DrawingKey.swift`)
- Modify: `Package.swift` (target `CreatorDrawingEditor` with `["CreatorDrawing", "CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI]`; test target
  `CreatorDrawingEditorTests` with those plus `metalUITesting`, `metalUIPortableText`, `metalUISystemFonts`)
- Test: `Tests/CreatorDrawingEditorTests/` (`SheetEditingTests.swift`, `ViewToolTests.swift`, `SelectionAndMoveTests.swift`, `CanvasTransformTests.swift`,
  `DrawingStepNameTests.swift`, `Support/DrawingEditorFixtures.swift`)

**Interfaces:**
- Consumes: Tasks 3, 5, 6.
- Produces:
  - `public struct DrawingCommit: Hashable, Sendable { document: DrawingDocument; name: String; coalescingKey: String? }` (`name` required, a `DrawingStepName`).
  - `public struct DrawingEditorEvents { committed: @MainActor (DrawingCommit) -> Void; sheetChanged: @MainActor (SheetID?) -> Void }`.
  - `public enum DrawingStepName` with R26's constants and `all`.
  - `public struct DrawingSourceOption: Hashable, Sendable { id: NodeID; name: String; bounds: BoundingBox? }`.
  - `public enum DrawingTool: Hashable, Sendable { case select, baseView, projectedView }`; `public enum DrawingKey: Hashable, Sendable { case fit, delete,
    nudge(Vector2), escape }`; `public struct SheetTransform: Hashable, Sendable { offset: Vector2; zoom: Double }` (canvas point = sheet mm × zoom + offset, y flipped:
    `screenPoint(_:)`, `sheetPoint(_:)`, zoom clamped 0.25…40).
  - `@MainActor @Observable public final class DrawingEditorModel` with: `init(document: DrawingDocument, sheet: SheetID?, standardUnitsAreInches: Bool,
    today: @escaping () -> String, events: DrawingEditorEvents)`; `document` (read only outside), `currentSheet: SheetID?`, `selection: Set<ViewID>`, `tool`,
    `transform`, `canvasSize: Vector2`, `visibleRect: Rect2D` (canvas points, set by the host), `sources: [DrawingSourceOption]`, `contents: [ViewID:
    ViewContent]`, `facts: TitleBlockFacts`, `refusal: String?`, `hoveredStroke: Int?`, `picture: SheetPicture?` (the current sheet composed by
    `SheetComposer`, rebuilt when the document, sheet, contents or facts change); `replaceDocument(_:)` (undo and redo: keeps the sheet and the selection
    that still exist).
  - Sheets (the current sheet): `addSheet()`, `renameSheet(_:to:)`, `duplicateSheet(_:)`, `deleteSheet(_:)`, `moveSheet(_:by offset: Int)`,
    `selectSheet(_:)`, `setSheetSize(_ size: SheetSize)`, `setSheetOrientation(_ orientation: SheetOrientation)`, `setSheetScale(_ scale: DrawingScale)`
    (the sheet's own scale, which every view without an override uses; refused with "A scale is two whole numbers from 1 to 1000." when not `isValid`),
    `setTitleField(_ key: TitleBlockKey, to: String)` (`.tolerance` writes `DrawingSettings.generalTolerance`; an automatic key does nothing),
    `setDensity(_ density: Double?)`, `setStandard(_:)` (R6's mirroring on every sheet).
  - Views: `press(_ tool: DrawingTool)`, `setSource(_ source: NodeID, of: ViewID)`, `setOrientation(_ orientation: StandardOrientation, of: ViewID)` (base
    views only), `setScale(_ scale: DrawingScale?, of: ViewID)` (nil: the sheet's), `setShowsHidden(_:of:)`, `setShowsTangent(_:of:)`,
    `setShowsLabel(_:of:)`, `deleteSelection()`.
  - Every committing method's step name is R26's table; `DrawingStepNameTests` holds each one.
  - `public struct SheetModifiers: OptionSet, Sendable { shift, primary }` (graph-free, as `CanvasModifiers` is for the graph; the views map MetalUI's
    modifiers into it).
  - Pointer and keys: `pointerDown(at: Vector2, modifiers: SheetModifiers)`, `pointerDragged(to:)`, `pointerUp(at:)`, `pointerCancelled()`, `pointerMoved(to:)`,
    `scrolled(by: Vector2, at: Vector2, zooming: Bool)`, `pinchChanged(_ factor: Double, at: Vector2)`, `pinchEnded()`, `middleDragged(by:)`, `fit()`,
    `keyPressed(_ key: DrawingKey) -> Bool` (canvas points in, sheet mm inside).
- Behaviour: R6 to R8, R15 (new sheets: name, size, date `today()`, title fields from `titleBlockDefaults`, tolerance default when the document has none), R22, R26;
  one commit per click or per drag (`coalescingKey` "drawing-move-<drag serial>"), nudges coalesce per key-down run ("drawing-nudge"); a refusal sets `refusal`
  (shown by the views) and commits nothing.

- [ ] **Step 1: Tests** (no MetalUI drawing; fixtures give sources with bounds and contents with FakeKernel-shaped projections).
  - `SheetEditingTests`: `addSheetNamesAndDatesIt` ("Sheet 1", A3 landscape, date from `today`, step "Add Sheet"); `theSmallestUnusedNumber` ("Sheet 2" after
    deleting nothing, "Sheet 1" again after deleting it); `aNewASMESheetIsANSIB`; `renameIsOneStep`; `duplicateCopiesViewsWithNewIDs` (alignments remapped to the
    copies); `deleteSelectsTheNeighbour`; `moveSheetReorders`; `editingATitleFieldUpdatesTheDefaults` (one "Edit Title Block" commit holding both);
    `changeStandardIsOneStep` (mirrored children on two sheets, one "Change Standard" commit); `sheetChangeIsNotACommit`.
  - `ViewToolTests`: `aBaseViewIsPlacedAtTheClick` (Front, the first source, centre at the click in sheet mm); `theFirstViewSetsTheSheetScale` (R8, same commit
    "Add View"); `noSourceRefuses` (the sentence, no commit); `aProjectedViewIsPlacedByDragging` (first angle, dropped right of a Front view → direction (1, 0, 0),
    horizontal alignment, the parent's y); `thirdAngleDropAbove` (Top); `anIsometricParentRefuses`; `escapeCancelsTheTool`.
  - `SelectionAndMoveTests`: `clickSelectsAndShiftAdds`; `aDragIsOneCoalescedStep` (several `pointerDragged` → commits sharing one key); `aProjectedViewSlides`;
    `movingAParentCarriesChildren`; `deleteFreesChildren` ("Delete View"); `nudgeMovesOneMillimetreAndShiftTen`; `hoverFindsTheNearestLine` (within 4 pt at the
    current zoom); `changeScaleIsOneStep`; `theSheetScaleScalesViewsWithoutAnOverride` (`setSheetScale(1:2)`: a view with no override halves, one with a 2:1
    override keeps its size, and its label now shows "(2 : 1)"); `anInvalidSheetScaleIsRefused`; `toggleHiddenIsChangeView`;
    `replaceDocumentKeepsWhatStillExists`.
  - `CanvasTransformTests`: `fitCentresTheSheetInTheVisibleRect` (A3 in a 1000 × 600 rect: zoom 600 × 0.9 / 297 within 1e-9, centred); `scrollPans`;
    `zoomScrollKeepsThePointUnderThePointer`; `pinchZoomsAboutItsCentre`; `zoomIsClamped`; `middleDragPans`.
  - `DrawingStepNameTests`: every name is R26's, none has digits; `everyMethodCommitsItsStep` (table-driven over R26's table: each method, called on the
    fixture with a value that differs from the current one, makes exactly one commit with its step name: `setSheetSize` and `setSheetOrientation` "Change
    Sheet Size", `setSheetScale` and `setScale(_:of:)` "Change Scale", `setTitleField(.title, …)`, `setTitleField(.tolerance, …)` and `setDensity`
    "Edit Title Block", `setSource`, `setOrientation(_:of:)`, `setShowsHidden`, `setShowsTangent` and `setShowsLabel` "Change View", and the sheet and
    view operations theirs); `noChangeNoCommit` (each setter with the current value, and `setTitleField(.mass, …)`, commit nothing).
- [ ] **Step 2: Run** `swift test --filter CreatorDrawingEditorTests`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter; pass.
- [ ] **Step 5: Commit** "Drawings: the drawing editor model".

### Task 11: The sheet canvas, tabs, toolbar, inspector and the drawing theme roles

**Files:**
- Create: `Sources/CreatorDrawingEditor/Views/` (`SheetCanvas.swift` (the paper, the culled views, input), `SheetViewLayer.swift` (one view, `.equatable()`),
  `SheetFrameLayer.swift` (frame and title block, `.equatable()`), `SheetTextView.swift` (glyphs at Helvetica advances), `SheetStrokeShape.swift` (a
  `Shape` of a stroke's segments through `cubics()`), `SheetTabs.swift`, `DrawingToolbar.swift` (with `DrawingToolbarRow`: the "More" overflow as
  `SketchToolbar` does it), `DrawingInspector.swift`, `ViewInspector.swift`, `SheetInspector.swift`, `DrawingColors.swift`, `EmptyDrawingView.swift`)
- Modify: `Sources/CreatorStyle/ThemeColors.swift`, `ThemeRole+All.swift`, `ThemeRoleGroup.swift` (`.drawing`, "Drawing", last), `ColorTheme+Dracula.swift`,
  `ColorTheme+Alucard.swift`, `ColorTheme+Nord.swift`
- Test: `Tests/CreatorStyleTests/ThemeRoleTests.swift` (52 roles), `Tests/CreatorStyleTests/DrawingRoleTests.swift`,
  `Tests/CreatorDrawingEditorTests/SheetCanvasRenderTests.swift`, `SheetTextViewTests.swift`, `DrawingToolbarTests.swift`, `SheetCanvasSkipTests.swift`,
  `SheetTabsTests.swift`, `Support/PDFStructureReader.swift` (copied from Task 7's), `Support/TestTextSystem.swift` (copied from `CreatorSketchEditorTests`), `Support/EqualityCoverage.swift` (`expectEqualityCovers`, copied from
  `CreatorEditorTests`), `SheetViewEqualityTests.swift`

**Interfaces:**
- Consumes: Task 10's model.
- Produces: `ThemeColors.drawingPaper`, `.drawingInk`, `.drawingHighlight` (roles "drawingPaper" "Paper", "drawingInk" "Ink", "drawingHighlight" "Highlight", group
  `.drawing`; #FFFFFF, #000000, #1F6FEB in all three built-ins; a `.mctheme` without them reads Dracula's); `public struct SheetCanvas: Component` (`model:
  DrawingEditorModel`), `SheetTabs`, `DrawingToolbar`, `DrawingInspector` (each `Component`, `public init(model:)`).
- Behaviour: R12 (widths, dashes, pan as an offset of the content, zoom rebuilds), R13 (each glyph a `Text` at em size h / 0.718 × zoom, its left edge at its Helvetica offset and its baseline on the
  text's baseline by R13's first-baseline `HStack`, so `SheetTextView` never measures the screen font), R19's
  40 % opacity for a pending view, R20's warning colour for problems, R27 (culling, `.equatable()` per view: `==` covers every stored property, held by
  `expectEqualityCovers`-style variants), selection as a thin highlight rectangle around the view's frame, hover as the hovered stroke redrawn in
  `drawingHighlight` (`SheetViewEqualityTests` changes each stored property of `SheetViewLayer` and `SheetFrameLayer` alone). `SheetCanvas` is a `hoverKeyRegion` whose `onKeyPress` maps F, Delete, ⌫, arrows (⇧ for 10 mm) and Esc to `DrawingKey`; one
  `DragGesture(minimumDistance: 0)` (with `onCancelled`), a middle `DragGesture`, `.onScrollWheel` (⌘ zooms) and `MagnifyGesture`, as `GraphPanelInput` wires
  the graph canvas; `onGeometryChange` sets `canvasSize`. The toolbar: "Base View", "Projected View" (a check when chosen), the drag gap, nothing else (DR-2 adds
  its tools). The inspector: no selection → the sheet's name, size, orientation, scale (`setSheetScale`: the preferred list and Custom…), standard (segmented ISO / ASME), title fields, density and general tolerance;
  one view → source (a menu of `sources` by name), orientation (base views), scale (Sheet's, the preferred list, Custom… with two integer fields), Hidden lines,
  Tangent edges, Label; several → "N views selected" and Delete. `EmptyDrawingView`: "No sheets yet" and an "Add Sheet" button. Text fields commit on Return and
  on focus loss, one step each.

- [ ] **Step 1: Tests.** `ThemeRoleTests` count 52 and order (the drawing group last); `DrawingRoleTests`: `theDrawingRolesAreFixed` (same in the three built-ins);
  `aThemeFileWithoutThemReadsTheDefaults`. Render tests through MetalUITesting with `testTextSystem()`: `thePaperIsWhiteAndInkBlack` (pixels inside and outside the
  paper at an A4 sheet's fit); `aThickLineIsThickerThanAThin` (stroke widths in points at zoom 2); `aHiddenLineIsDashed`; `aPendingViewIsFaded`;
  `theSelectionIsHighlighted`. `SheetTextViewTests`: `glyphsSitAtHelveticaAdvances` (the frames of "H1"'s two glyph texts at x 0 and 722/1000 em).
  `aCapitalHSitsOnTheBaseline` (pixels: a SheetText "H" 10 mm high at sheet origin (20, 30) mm, drawn at zoom 1 and at zoom 3; the lowest row of ink of the
  "H" is within 1 pt of the transform's screen y of the origin, which is also where the PDF's `Td` y for the same picture lands through the same transform:
  the test writes the PDF of that picture, reads the text's `Td` y with `PDFStructureReader` (copied into `Tests/CreatorDrawingEditorTests/Support`, as Task 13 copies it) and maps it; an "H" has no descender, so its ink ends on the
  baseline; if this fails because MetalUI's first-baseline alignment is not what R13 relies on, the gap is logged as `DR-1-a` and the test stays,
  `withKnownIssue` naming the gap, never deleted).
  `DrawingToolbarTests`: `theRowsMoveToolsIntoMoreFromTheEnd` (`ViewThatFits` at three widths).
  `SheetTabsTests` (MetalUITesting interaction over a model with sheets "Sheet 1" and "Sheet 2", the way the graph panel's window tests click):
  `aClickSelectsATab` (the second tab clicked → `currentSheet` is it, no commit); `plusAddsASheet` ("Add Sheet", the new tab current);
  `aDoubleClickRenamesInPlace` (a field opens with the name all selected; typing and Return commit one "Rename Sheet"; Esc commits nothing);
  `theMenuHasItsFiveItems` (Rename, Duplicate, Delete, Move Left, Move Right, in that order; Move Left disabled on the first tab, Move Right on the last;
  Duplicate and Move Right each make one commit with their name). Human check DR1-9 covers the look and feel on screen. `SheetCanvasSkipTests` (MetalUI's content-skip counters,
  as `CanvasContentSkipWindowTests` reads them): `aPanSkipsEveryView`; `aSelectionChangeRebuildsTwoViews`; `offscreenViewsAreNotBuilt`.
- [ ] **Step 2: Run** `swift test --filter 'ThemeRoleTests|DrawingRoleTests'` and `--filter CreatorDrawingEditorTests`; fail.
- [ ] **Step 3: Implement.** A MetalUI limit met here (a stroke too slow to rebuild per zoom step, a missing text placement) is logged as a `DR-1-x` gap in
  `docs/metalui-gaps.md` and reported.
- [ ] **Step 4: Run** both filters and `swift test --filter CreatorStyleTests`; pass.
- [ ] **Step 5: Commit** "Drawings: sheet canvas, tabs, toolbar, inspector and theme roles".

### Task 12: Drawing mode in the app

**Files:**
- Create: `Sources/CreatorApp/Drawing/` (`WorkspaceMode.swift`, `DrawingSession.swift` (the editor model, the projector, the request ordering),
  `DrawingSession+Sources.swift` (results → `DrawingSourceContent` and `DrawingSourceOption`), `DrawingSession+Facts.swift` (mass), `AppModel+Drawing.swift`,
  `DrawingDock.swift` (the canvas and the tabs in the model area))
- Modify: `Package.swift` (`CreatorApp` and `CreatorAppTests` gain `"CreatorDrawing"`, `"CreatorDrawingEditor"`), `Sources/CreatorApp/AppModel.swift` (the session
  replaced with the document, the cache), `AppRoot.swift` (the canvas in place of `ViewportPane` in Drawing), `TopBar.swift` (the segmented "Model | Drawing"
  in both modes, `DrawingToolbar` in Drawing; R28's top bar: the Preview picker and the Analysis menu hidden in Drawing, the Export menu's drawing items are
  Task 13's), `InspectorDock.swift` (`DrawingInspector` in `SketchChrome(.inspector)`), `AppCommands.swift` (View ▸ Drawing ⌘⇧D and View ▸ Model; R28's
  disabled View items), `AppInput.swift` (viewport keys declined in Drawing), `AppModel+Picking.swift` (R21's switch back to Model), `DocumentParts.swift`,
  R28's docks: `AppRoot.swift` (`FieldLegendDock` and `MeshBadgeDock` only in Model), `AppWindowRoot.swift` (`SectionPanelDock` only in Model),
  `AppModel+FieldPreview.swift` (`fieldPreviewRequest(for:)` answers nil in Drawing), `Sources/CreatorEditor/GraphKeyBindings.swift` (R21: `case
  "d": shifted ? nil : .duplicate`)
- Test: `Tests/CreatorAppTests/DrawingModeTests.swift`, `Tests/CreatorAppTests/DrawingProjectionTests.swift`, `Tests/CreatorAppTests/DrawingUndoTests.swift`,
  `Tests/CreatorEditorTests/KeyCommandTests.swift`

**Interfaces:**
- Consumes: Tasks 4, 9, 10, 11; `AppModel.outputNodes`, `finishSketch()`, `cancelPick()`, `endMeasure()`, `endModelDimension()`, `endControlPoints()`,
  `Kernel.properties(of:)`, `AppLayout.modelArea(dock:panelWidth:panelHeight:)`.
- Produces: `public enum WorkspaceMode: String, CaseIterable { case model, drawing }`, `AppModel.mode`, `AppModel.setMode(_:)`, `AppModel.drawing: DrawingSession`,
  `AppModel.storeDrawing(_ commit: DrawingCommit)` (`perform(.setDrawings(commit.document), coalescingKey: commit.coalescingKey, name: UndoName.drawing(commit.name))`,
  refused while an alert or a held result blocks edits as other edits are), `DrawingSession.waitForProjections()` (joined into `AppModel.settle()`),
  `DrawingSession.projectAll() async -> DrawingSnapshot` (for export: `public struct DrawingSnapshot: Sendable { contents: [ViewID: ViewContent]; facts:
  [SheetID: TitleBlockFacts] }`, every view of every sheet projected and every sheet's facts computed, read by lookup only), and
  `DrawingSession.facts(for sheet: DrawingSheet) async -> TitleBlockFacts` (R16 for any sheet, not only the current one; the editor's `facts` is this for
  the current sheet).
- Behaviour: R28 (the window in Drawing), R4 (mode and sheet through `document.drawingView`, restored on open), R19 (one request generation per sheet: a newer request's results replace, an older
  one's are dropped; pending views keep the old projection faded), R20, R21, the editor's `visibleRect` from `modelArea`, `sources` from the Output nodes in order, the
  undo, redo and New/Open paths calling `replaceDocument` or replacing the session, facts from R16 (volumes through the kernel, off the main actor, cached by solid
  identity).

- [ ] **Step 1: Tests** (the app over `FakeKernel` boxes from the front; OCCT-gated variants marked).
  - `DrawingModeTests`: `theSwitchShowsTheSheet` (mode drawing; the root shows the canvas, not the viewport); `commandShiftDTogglesTheMode`; `enteringEndsModelTools`
    (an open sketch is finished, a pick cancelled, Measure, the dimension tool and the control-point mode ended); `aPickButtonSwitchesBackToModel`;
    `viewportKeysDoNothingInDrawing` (M, Z, D return unclaimed); `noSheetShowsAddSheet` and `isNotAnEdit`; `theModeAndSheetAreSavedAsViewState` (save, reopen: Drawing
    on the same sheet, the document not edited); `theInspectorShowsTheDrawingInspector`;
    `commandShiftDOverTheCanvasTogglesTheModeAndDuplicatesNothing` (a selected node, the pointer over the graph canvas, ⌘⇧D through the window: the mode is
    Drawing, the graph's node count unchanged, no undo step; ⌘⇧D again returns to Model; ⌘D alone over the canvas still duplicates);
    `drawingModeHidesTheModelOverlays` (section and zebra on, a Fields node selected so the legend shows, a mesh badge up: in Drawing the window has no
    Section, Measure or Zebra panel, no field legend and no mesh badge, the top bar has no Preview picker or Analysis menu, and the slow-evaluation chip still
    shows while an evaluation is held; back in Model all of them show again, `document.section` and `document.zebra` are still on and the document is not
    edited; found the way the existing window tests find panels).
  - `KeyCommandTests`: `commandDDuplicatesAndCommandShiftDIsNotAGraphKey` (`commandChord(for: "d", shifted: false) == .duplicate`, `shifted: true` is
    nil).
  - `DrawingProjectionTests`: `aBaseViewDrawsItsOutput`; `anEditReprojects` (a box width 10 → 20: the view's line spans 20 × scale); `onlyViewsOfAChangedOutputReproject`
    (two Outputs, one edited: `kernelCalls` grows by the edited view's count only; again with the unedited Output holding two solids, compounded through
    `setCompoundHook`: its views stay hits, `compoundCalls` unchanged by the edit); `aSupersededRequestNeverPublishes` (the projection hook holds the first request; a
    second edit's request lands; releasing the first leaves the second's lines); `thePendingProjectionStaysFaded` (`isPending` while held, old lines kept);
    `aRemovedOutputLeavesAFrameAndUndoRestoresIt`; `aFailedOutputFadesTheLastProjection` (a refused upstream node: the view keeps its lines and shows the failure);
    `aMeshOutputWarns` (a Mesh node into the Output: R20's sentence); `alignmentSurvivesAnEdit` (a right view stays on its parent's y after the part grows);
    `massFollowsTheDensity` (OCCT-gated: a 10 mm cube, density 2.7 → "2.7 g"; no density → empty); `theCacheIsEmptiedOnOpen`.
  - `DrawingUndoTests`: `aDrawingEditIsOneNamedStep` ("Undo Add View"); `undoRestoresTheEditorsDocument` (the editor shows the previous sheet list); `aDragIsOneStep`
    ("Undo Move View" once after a drag of ten steps); `drawingEditsMakeTheDocumentEdited` and saving clears it.
- [ ] **Step 2: Run** `swift test --filter 'DrawingModeTests|DrawingProjectionTests|DrawingUndoTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `swift test --filter CreatorAppTests`; pass.
- [ ] **Step 5: Commit** "Drawings: drawing mode in the app".

### Task 13: PDF and DXF export from the app

**Files:**
- Create: `Sources/CreatorApp/Export/DrawingExportKind.swift`, `Sources/CreatorApp/AppModel+DrawingExport.swift`
- Modify: `Sources/CreatorApp/ContentType+MetalCreator.swift` (`.pdf` "com.adobe.pdf" `pdf`, "PDF document"; `.dxf` "com.autodesk.dxf" `dxf`, "DXF drawing"),
  `AppCommands.swift` (File ▸ Export PDF…, Export DXF of Sheet…, Export DXF of View at 1:1…, disabled outside Drawing), `TopBar.swift` (the same three in the Export
  menu in Drawing, after STEP and STL)
- Test: `Tests/CreatorAppTests/DrawingExportTests.swift`

**Interfaces:**
- Consumes: Tasks 7, 8, 12 (`DrawingSession.projectAll()`'s `DrawingSnapshot`: each sheet composed with its own `facts[sheet.id]`), `summarize(_:)`, `withFilePicker`, `tracked(_:)`, `FilePicker.chooseDestination`.
- Produces: `public enum DrawingExportKind: String, CaseIterable { case pdf, dxfSheet, dxfView }`; `AppModel.exportDrawing(_ kind: DrawingExportKind, using:
  any FilePicker) async`; `AppModel.exportDrawingReturningWarnings(_ kind:, to url: URL) async throws(AppProblem) -> [String]` (R25; default names "<exportName>.pdf",
  "<exportName>.dxf", "<exportName> <view title>.dxf").

- [ ] **Step 1: Tests** (a fake picker returning a scratch URL; files read back with Task 7's and Task 8's test readers, copied into `Tests/CreatorAppTests/Support`).
  `aPDFHasAPagePerSheet`; `theDXFOfTheSheetHoldsTheOpenSheet`; `theDXFOfAViewNeedsOneSelectedView` (the sentence; with one selected, model-mm coordinates);
  `aFailedOutputRefusesTheExport` ("“Output” can't be drawn" with the reason; no file); `noSheetRefuses`; `theExportWaitsForEvaluation` (an edit just before export:
  the file shows the new size); `theExportWarnsAboutReplacedCharactersOnce` (title "Ω-Bracket →" on two sheets → exactly one warning, naming it, for the PDF; the same
  one warning for the DXF of a sheet carrying it); `meshesLeftOutAreListed`; `theMenusShowTheDrawingExportsOnlyInDrawing`;
  `theMassShowsOnPage2` (a two-sheet document whose second sheet, not the open one, has a density of 2.7 and a view of a 10 mm FakeKernel box: page 2's
  content holds "2.7 g" in the mass field and page 1's mass field is empty).
- [ ] **Step 2: Run** `swift test --filter DrawingExportTests`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `swift test --filter CreatorAppTests`; pass.
- [ ] **Step 5: Commit** "Drawings: PDF and DXF export from the app".

### Task 14: Benchmarks drawing-1 and drawing-2

**Files:**
- Create: `Tests/CreatorAppTests/Bench/DrawingBench.swift`, `Tests/CreatorAppTests/Bench/DrawingBenchFixtures.swift`,
  `Tests/CreatorAppTests/Bench/DrawingBenchFixturesTests.swift`
- Modify: `docs/verification/performance.md` (a "Drawings" section with both rows)

**Interfaces:**
- Consumes: `makeBracketBenchApp()`, `Bench.isRequested`, `Bench.requireRelease()`, `BenchSamples`, `WarmBenchWindow`, Task 12.
- Produces: `DrawingBenchFixtures.bracketSheet(_ app: AppModel)` (an A3 sheet with the bracket's Front, Right, Top and Isometric views, the scale R8 picks);
  `BENCH drawing-1 …` (cache emptied, the four projections from the edit that adds them to the last one landing, 10 runs, median, p95, max; target under 1 s) and
  `BENCH drawing-2-warm window-cpu (warm frame) …` for 60 pan steps and 60 zoom steps (`Bench.frameBudget`).

- [ ] **Step 1: Test** `DrawingBenchFixturesTests.theBracketSheetHasFourViewsWithLines` (runs in the default suite, OCCT-gated).
- [ ] **Step 2: Run** it; fail. **Step 3: Implement.** **Step 4: Run** it; pass; then `scripts/bench.sh DrawingBench` (release) and record both rows in
  `performance.md` with the machine's load; a loaded Mac's numbers are recorded as saturated, never as a verdict.
- [ ] **Step 5: Commit** "Drawings: benchmarks drawing-1 and drawing-2".

### Task 15: Docs and the suites

**Files:**
- Modify: `CLAUDE.md` (a DR-1 paragraph after NS-5's in "Project state": the two modules, the kernel call and `cocct_projection.cpp`, TKHLR, format 17 and
  `Graph.drawings` / `.setDrawings`, `ViewState.drawing`, the theme roles, R1 to R28 in short, which path R10 took, the parked items; the module list gains
  `CreatorDrawing` and `CreatorDrawingEditor` entries; the file-format sentence becomes "File format is version 17 (… 17 added the top-level graph's optional
  `drawings` key …); files of format 1 to 16 open unchanged and are written as 17"; the pass rules and the `swift test` comment say 16 "Test run with" lines;
  the Commands block gains `swift test --filter CreatorDrawingTests` and `--filter CreatorDrawingEditorTests`), `Tests/CreatorAppTests/CIPinTests.swift`
  (`testRuns = 16`), `.github/workflows/xp.yml` (`EXPECTED_TEST_RUNS: 16` and the comments' counts), `scripts/linux-test.sh` (`EXPECTED_TEST_RUNS:-16` and its
  comment), `docs/verification/human-checks.md` (group DR-1, below), `docs/superpowers/specs/2026-11-24-drawings-design.md` (the Status line: "Status: approved
  for planning (2026-11-24). Sub-projects DR-1 to DR-5, built in that order. DR-1 done (<date>; human checks group DR-1 pending; R10: <the path taken>).")
- Group DR-1 checks: DR1-1 enter Drawing (switch and ⌘⇧D), add a sheet, place a base view and drag out right, above and below views in first angle, then switch
  to ASME and see them mirror; DR1-2 change a width in the graph with the drawing showing: views redraw, faded while pending, alignment kept; DR1-3 hidden lines
  and tangent edges per view; DR1-4 the sheet scale and a 2:1 override with its label; DR1-5 export a PDF, open it in Preview, a browser and Acrobat Reader, print a
  1:1 view at 100 % and measure it with a ruler; DR1-6 export DXF of the sheet and open it in LibreCAD or QCAD, and in AutoCAD or Autodesk's free DWG TrueView: layers, dashed
  hidden lines, true arcs and circles, and no repair or audit prompt in AutoCAD (R24: a prompt is a DR-1 bug);
  DR1-7 DXF of a plate's Top view at 1:1 in laser or CAM software: true size, model coordinates; DR1-8 title block fields, the date, mass with a density, a title
  with "Ω" warned at export; DR1-9 tabs: add, rename, duplicate, delete, move left and right, each one undo step with its name; DR1-10 delete the Output a view
  shows: the frame and sentence, then undo; a mesh Output's warning; DR1-11 Linux and Windows: drawing mode, both exports, the PDF's SHA-256 equal to the
  Mac's for the same document; DR1-12 pan, zoom and F on a full A3 sheet: smooth, text crisp, line weights readable, and text sitting on the same baselines as in the
  exported PDF opened beside it (R13); DR1-13 in Drawing, the field legend, mesh badge and Section, Measure and Zebra panels are gone and the
  slow-evaluation chip still shows; back in Model they return as they were (R28).
- [ ] **Step 1:** docs and counts.
- [ ] **Step 2:** `swift test` on macOS (16 "Test run with" lines, no "recorded an issue" or "failed after"); `XP_TRACK=dr-1 IMAGE=metalcreator-linux:dr-1
  scripts/linux-test.sh test` (16 lines; afterwards remove only this run's Docker volume and image); `swiftlint lint --strict` 0.
- [ ] **Step 3: Commit** "Docs: DR-1".
