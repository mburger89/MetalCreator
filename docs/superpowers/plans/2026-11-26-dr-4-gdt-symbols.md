# DR-4: GD&T and manufacturing symbols — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Datum feature symbols (A, B, C…), feature control frames (ISO 1101's fourteen characteristics, a diameter zone, Ⓜ Ⓛ Ⓟ Ⓕ Ⓣ,
up to three datum references with modifiers, composite frames) and surface texture symbols (ISO 21920-1: basic, material removal
required or prohibited, Ra or Rz, lay), attached to a view's lines or to a dimension by lasting anchors, checked by four rules that
warn in words, plus a sheet's general notes, its edge-break note and its general surface requirement beside the title block; all
drawn as strokes, fills and texts of the one `SheetPicture`, so the screen, the PDF and the DXF agree; saved as file format 20.

**Architecture:** `CreatorDrawing` gains three annotation kinds (`datumFeature`, `featureControl`, `surfaceTexture`) and a
`SymbolAttachment` (a lasting anchor on a line, or a dimension of the same view), the glyphs in `DrawingSymbols` (vector strokes,
never font characters), pure layouts for frames, datum symbols and surface symbols, a rule checker, and a second composing pass
that hangs symbols on the dimensions the first pass drew. A symbol on a line is resolved by DR-2's `DrawingAnchorResolver` and is
lost by DR-2's rules (warning colour, listed, exported with a warning, never re-attached by itself). `CreatorDrawingEditor` gains
three tools and their inspector pages; the app lists the rule warnings in exports. No kernel or shim change.

**Tech Stack:** Swift 6.4, Swift Testing, MetalUI (existing canvas and inspector controls). No OpenCascade change.

**Spec:** `docs/superpowers/specs/2026-11-24-drawings-design.md`. Read it whole; build §DR-4 and what §Model, §Drawing mode, §Export,
§Constraints and "Decisions after the builder check" say about annotations (decision 2 in full: a symbol never guesses its anchor).
DR-1's, DR-2's and DR-3's plans (`docs/superpowers/plans/2026-11-24-dr-1-sheets-views-pdf.md`, `2026-11-25-dr-2-dimensions-notes.md`,
`2026-11-26-dr-3-sections-details.md`) hold the rulings this plan builds on; CLAUDE.md's "Drawings, DR-1", "Drawings, DR-2" and
"Drawings, DR-3" paragraphs say what exists. Assemblies, balloons, parts lists, revisions, templates, SVG and MCP tools are DR-5:
leave them out.

## Global Constraints

- **Worktree and branch.** `/Users/maxburger/Developer/MetalCreator-dr4`, branch `dr-4`. Never touch `../MetalUI`. A MetalUI shortcoming is
  logged in `docs/metalui-gaps.md` (a `DR-4-x` entry) and reported, never worked around. Never run `git stash` in any form.
- **No kernel change.** No new `Kernel` call, no C++. Symbols read only `Topology`, `EdgeInfo.curve`, `FaceInfo` and the frame, as DR-2's
  dimensions do (`DrawingAnchorResolver`, never `Topology.resolution`, never `EdgeKey.operandKeys`).
- **Module rules** (unchanged): `CreatorDrawing` depends on `CreatorGeometry` and `CreatorKernel` only; `CreatorDrawingEditor` on `CreatorDrawing`,
  `CreatorKernel`, `CreatorGeometry`, `CreatorStyle` and MetalUI only. No CoreGraphics, CoreText, ImageIO or Metal in either. Nothing iterates a
  dictionary where order reaches output (pictures, warnings, lists, PDF and DXF bytes, saved order). Files importing MetalUI and
  CreatorGeometry write `CreatorGeometry.Angle`.
- **Glyphs.** Every GD&T characteristic symbol, every circle of a circled modifier, the datum triangle, the surface texture symbol and the
  lay symbol ⊥ are strokes or fills from `DrawingSymbols` (R3). Only WinAnsi characters go into a `SheetText` (letters, digits, "Ø", "=",
  "(", ")"). Slanted glyph lines use exact constants built with `(3.0).squareRoot()` and `(0.5).squareRoot()`, never `sin` or `cos`.
- **Units.** Symbol layouts are in sheet millimetres, origin bottom left, y up, scaled by the sheet's lettering height `h =
  DrawingStyle.notesHeight(for: sheet.size)`; a leader's anchor hint is in the view's model plane (as DR-2's `LeaderEnd.hint`). Tolerance
  values are stored in millimetres, roughness values in micrometres.
- **Constants** are `SymbolStyle` members (R4 to R6), never literals at a call site.
- **Bytes.** PDF and DXF bytes stay identical on every platform: one digest per fixture. The DR-1, DR-2 and DR-3 digests do not change.
- **File format 20** (`GraphFile.currentFormatVersion`): files of format 1 to 19 open unchanged and are written as 20 (R14).
- **Undo names** are fixed strings in `DrawingStepName` (R15): no numbers, no typed text (a datum letter is typed text).
- **Messages** are full sentences in the app's voice, exactly as written here.
- **Tests and checks.** Swift Testing only; OCCT tests gated `#if canImport(CreatorOCCT)`; never block a pool thread in a test (`HookGate` or a
  suspending kernel hook); `swiftlint lint --strict` reports 0; macOS and Linux each print **16** "Test run with" lines (no new test target) and
  never "recorded an issue" or "failed after".
- **Commit trailer** (every commit):
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_0195iKYokoi2BJLpboZBys76`.

## Rulings (where this plan narrows the spec; each says why and what it costs if wrong)

- **R1. Three annotation kinds.** `AnnotationKind` gains `datumFeature(DatumFeature)`, `featureControl(FeatureControlFrame)` and
  `surfaceTexture(SurfaceTexture)` (coded `"datumFeature"`, `"featureControl"`, `"surfaceTexture"`), all `Hashable, Codable, Sendable`:
  - `DatumFeature { letter: String; attachment: SymbolAttachment; distance: Double; dimensionEnd: Int }`: `distance` is sheet mm from the
    foot to the square's centre, its sign the side (R5); `dimensionEnd` (0 or 1) is which end of a dimension line it stands on.
  - `FeatureControlFrame { characteristic: GeometricCharacteristic; rows: [ToleranceRow]; attachment: SymbolAttachment; offset: Vector2 }`
    (one row, or two for a composite frame; `offset` sheet mm, R4). `ToleranceRow { zone: ToleranceZone /* .width, .diameter */; value:
    Double /* mm */; material: MaterialCondition? /* .maximum "M", .least "L" */; freeState: Bool; tangentPlane: Bool; projected:
    ProjectedZone? /* { length: Double? } mm */; datums: [DatumReference] /* at most 3 */ }`, `DatumReference { letter: String; material:
    MaterialCondition? }`.
  - `SurfaceTexture { requirement: SurfaceRequirement; lay: SurfaceLay?; feature: LeaderEnd; offset: Vector2? }` (`offset` nil: the symbol
    stands on the line, R6), `SurfaceRequirement { process: SurfaceProcess /* .any, .removalRequired, .removalProhibited */; parameter:
    RoughnessParameter? /* .ra "Ra", .rz "Rz" */; value: Double? /* µm */ }`, `SurfaceLay` cases `parallel` "=", `perpendicular` "⊥",
    `crossed` "X", `multidirectional` "M", `circular` "C", `radial` "R", `particulate` "P".
  - `SymbolAttachment`: `case feature(LeaderEnd)` (a line of the view by a lasting `AnchorTarget` and a model-plane hint) or `case
    dimension(AnnotationID)` (a dimension or hole callout of the same view), coded with a `type` string `"feature"` / `"dimension"`.
  Every symbol has a `view` (never a free sheet annotation); one on a dimension has its dimension's `view`. Cost: none.
- **R2. Anchors and attachment.** A symbol on a line holds DR-2's anchors only, picked by three new `PickPurpose`s: `.datum` and `.surface`
  take a straight edge (`EdgeInfo.curve` `.line`) or a cylinder's outline seen side on; `.frame` takes those and a circle seen face on (a
  hole's rim). A `.corner` candidate picks its edge and a `.centre` candidate its circle (`.frame` only), as DR-3's `AuxiliaryRule` does.
  Names are DR-2's (`Picker.name`, lasting, one run); refusals (exact): `.datum` on a circle "A datum symbol stands on a straight line of a
  view or on a dimension."; `.surface` on a circle "A surface symbol stands on a straight line of a view."; `.frame` on a circle not face on,
  DR-2's `DrawingPick.circleSentence`; any symbol in a pictorial view (`DrawingSheet.isPictorial`) "Isometric views take notes and leaders, not
  datum, tolerance or surface symbols." (`DrawingPick.symbolIsometricSentence`). The **foot** is computed from exact geometry, never a projected
  polyline (`SymbolFoot.of(_ geometry: AnchorGeometry, hint: Vector2, frame: ProjectionFrame)`): a segment's or outline's **infinite** line
  nearest the hint (so a hint beyond the edge's ends stands on its extension line), a face-on circle's nearest point; with `along` the unit
  tangent there (model plane). Lost (by `AnnotationEvaluator`): every `LostReason` the resolver gives; a held edge that is no longer straight
  for `.datum`/`.surface` (a new `LostReason.notStraight`, "What it stands on is no longer a straight line."); a line seen end on (projected
  length under 1e-9) or a circle no longer face on, `.foreshortened`. Never re-attached by itself; Select's click on a line re-attaches it
  (DR-2 R15, step "Reattach Symbol"). A symbol on a dimension takes a dimension or hole callout of the same view, never a note or another
  symbol: datum symbols take `.linear` dimensions (any direction) and `.diameter` dimensions and hole callouts, else "A datum symbol goes on a
  size: a linear dimension, a diameter or a hole callout."; frames take `.linear`, `.radius`, `.diameter` and hole callouts, else "A tolerance
  frame goes on a size: a linear dimension, a radius, a diameter or a hole callout."; surface symbols take none, "A surface symbol stands on a
  straight line of a view."; a press on a note or a symbol, "Attach the symbol to a line of a view or to a dimension.". A symbol on a
  dimension follows it (drawn from the dimension's drawing, R11), is lost exactly when the dimension is lost (with its reason), and is not
  re-attachable itself: Select's re-attach click on it refuses "This symbol hangs on a dimension; reattach the dimension and the symbol follows
  it.". Deleting a dimension deletes the symbols on it in the same step (`DrawingSheet.removeAnnotation` cascades); undo brings both. Cost: a
  symbol on a dimension cannot outlive it (the user re-adds it).
- **R3. Glyphs are strokes.** `DrawingSymbols.characteristic(_ c: GeometricCharacteristic, origin: Vector2, h: Double) -> [SheetSegment]` draws
  in the box h × h whose bottom left is `origin`, from this table (unit box coordinates, scaled by h; `k = (3.0).squareRoot() / 3`, `s =
  (3.0).squareRoot() / 2`; arcs `.arc(center:radius:start:sweep:)` with start 0 and sweep 2π for full circles):

  | Characteristic | Segments |
  |---|---|
  | straightness | line (0, 0.5)–(1, 0.5) |
  | flatness | polyline (0, 0.2), (0.7, 0.2), (1, 0.8), (0.3, 0.8), (0, 0.2) |
  | circularity | arc c (0.5, 0.5) r 0.5 full |
  | cylindricity | arc c (0.5, 0.5) r 0.3 full; lines p ± 0.5 d for p = (0.5, 0.5) ± 0.3 n, d = (0.5, s), n = (s, −0.5) |
  | lineProfile | arc c (0.5, 0.25) r 0.5 start 0 sweep π |
  | surfaceProfile | that arc; line (0, 0.25)–(1, 0.25) |
  | parallelism | lines (0.1, 0)–(0.1 + k, 1), (0.4, 0)–(0.4 + k, 1) |
  | perpendicularity | lines (0.5, 0)–(0.5, 1), (0, 0)–(1, 0) |
  | angularity | polyline (1, k), (0, 0), (1, 0) |
  | position | arc c (0.5, 0.5) r 0.35 full; lines (0, 0.5)–(1, 0.5), (0.5, 0)–(0.5, 1) |
  | concentricity | arcs c (0.5, 0.5) r 0.5 and r 0.25 full |
  | symmetry | lines (0.15, 0.2)–(0.85, 0.2), (0, 0.5)–(1, 0.5), (0.15, 0.8)–(0.85, 0.8) |
  | circularRunout | line (0.1, 0.1)–(0.9, 0.9); polyline (0.6, 0.9), (0.9, 0.9), (0.9, 0.6) |
  | totalRunout | lines (0, 0.1)–(0.6, 0.7), (0.4, 0.1)–(1, 0.7), (0, 0.1)–(0.4, 0.1); polylines (0.35, 0.7), (0.6, 0.7), (0.6, 0.45) and (0.75, 0.7), (1, 0.7), (1, 0.45) |

  Run-out arrowheads are open (strokes). A circled modifier (`DrawingSymbols.circled(_ letter: String, center: Vector2, h: Double)`) is a
  full arc of radius `SymbolStyle.circleRadius` (0.6h) and the letter as a `SheetText` of cap height 0.7h centred on it (Helvetica's advance;
  the letter itself is WinAnsi). The lay symbol ⊥ is the perpendicularity glyph at 0.8h; the other lay symbols are text. The datum triangle is
  a `SheetFill`. Cost: proportions are ours within the standards' figures (human check DR4-1 compares them with ISO 1101's table).
- **R4. The feature control frame** (`FrameLayout.draw(_:at:h:format:standard:) -> AnnotationDrawing`, sheet mm). Rows are `frameHeight` =
  2h tall; compartments left to right: the characteristic (a 2h × 2h square, its glyph h × h centred), the tolerance, then one per datum
  reference. The tolerance compartment holds "Ø" when the zone is `.diameter`, the value, then the modifiers in this order, each 0.3h after
  the previous piece: Ⓜ or Ⓛ, Ⓕ, Ⓣ, Ⓟ followed (0.3h) by its length when set; a circled modifier advances `circledAdvance` = 1.2h. A datum
  compartment holds its letter, then Ⓜ or Ⓛ. Text is cap height h, baselines `h / 2` above each row's bottom, padding `framePadding` = 0.5h
  each side of a compartment's content; a datum compartment is at least `datumCellMinimum` = 2h wide; in a composite frame each column is
  as wide as its widest row. Lines are thin (`DrawingStyle.thin`), solid, on `.dimension`. **Composite** (two rows; position, line profile and
  surface profile only): ASME draws one characteristic compartment spanning both rows (glyph centred in 2h × 4h, Y14.5 composite); ISO draws
  each row with its own characteristic compartment (ISO 5458's stacked frames). Values are `GDTNumber.tolerance(_ mm: Double, format:)`: the
  document's unit with as many decimals as the value needs (up to 4; `DimensionNumber.neededPlaces`), never rounded to the document's precision,
  inches keeping at least the document's precision (`.005` in ASME), the decimal sign and leading zero as DR-2's `NumberFormat`. Placement:
  on a line (`.feature`), `offset` is from the foot on the sheet to the frame's top left; a leader (arrowhead at the foot, DR-2's
  `SheetDimensionLayout.leader`) runs to the middle of the first row's left side when the foot lies left of the frame's centre, else its right
  side, its shoulder `AnnotationStyle.shoulder` long ending on the frame. On a dimension (`.dimension`), the frame's top left is `(labelRect.min.x,
  labelRect.min.y − textGap) + offset`, `labelRect` the bounding rectangle of the dimension's first label (R11); several frames on one dimension
  stack in id order, each `textGap` below the previous. A frame is always upright. Cost: the modifier order is one rule for both standards; a
  reorder is a layout change, never a data change.
- **R5. The datum feature symbol** (`DatumLayout`). A square `datumSquare` = 2h, thin, its letter centred (cap h); a filled equilateral triangle
  of side `datumTriangle` = 1.2h (height `datumTriangle × s`); a thin leader from the triangle's apex to the square's edge, toward its centre.
  Three placements:
  - on a line: the triangle's base on the line (rotated with it) centred on the foot, its apex on the side of `distance`'s sign along n =
    (−along.y, along.x); the square's centre at foot + n × distance; when the foot lies beyond the edge's ends, a thin extension line runs from
    `AnnotationStyle.extensionGap` past the nearer end to `extensionOvershoot` past the triangle (ISO 5459 and Y14.5: the symbol on an extension
    line);
  - on a dimension that has a dimension line (R11: a linear dimension's first run, an ISO diameter drawn across its circle): the triangle's base
    on the extension line at the line's end `dimensionEnd`, square to the dimension line, its apex pointing outward along the dimension line,
    the square's centre `|distance|` outward;
  - on a dimension without one (an ASME diameter, a hole callout): the triangle's base centred on the bottom of `labelRect` (below any frames
    stacked there, R4), apex down, the square `|distance|` below.
  `|distance|` is at least `triangle height + datumLeaderMinimum (h) + h` (clamped when drawn, never written). Cost: ASME's form for a datum
  on a size dimension is drawn hanging under the label; a symbol on a frame (Y14.5's other form) is parked.
- **R6. The surface texture symbol** (ISO 21920-1, ASME Y14.36; `SurfaceLayout`). From its apex (on the surface): a short leg up-left to
  (−H1 × k, H1) and a long leg up-right to (H2 × k, H2) (60° to the surface), H1 = `surfaceShort` = 1.4h, H2 = `surfaceLong` = 3h; material
  removal required adds the bar (−H1 × k, H1)–(H1 × k, H1); removal prohibited adds a full circle of radius H1 / 3 centred (0, 2H1 / 3). With
  a parameter, a horizontal line runs from the long leg's top 0.3h + the text's width + 0.3h to the right, and the text ("Ra 1.6") sits under
  it, origin (H2 × k + 0.3h, H2 − 1.3h); the lay sits at origin (h, 0.2h) (text, or the ⊥ glyph). Lines thin on `.dimension`. Standing
  (`offset` nil) is allowed only on a line horizontal on the sheet (|along.y| ≤ 1e-9) with the symbol above it: the apex on the foot. Otherwise
  the symbol is upright at foot + `offset` with a leader from its apex to an arrowhead on the foot (ISO 21920-1's leader form). A standing
  symbol whose line is no longer horizontal is drawn on a leader at `SymbolStyle.defaultSurfaceOffset` = (2h, 4h). Values:
  `GDTNumber.roughness(_ µm: Double, format:)`: micrometres with the decimals they need (up to 3) in a millimetre document, microinches rounded
  to a whole number in an inch document (1.6 µm reads "63"), the unit never written (shop practice). Cost: symbols standing on vertical or
  slanted lines (ISO reads them from the right) are parked; they take leaders.
- **R7. What each characteristic takes** (`GeometricCharacteristic` members; the editor refuses the rest, R15):

  | Characteristic (title) | Family | Ø zone | Ⓜ/Ⓛ | Ⓣ | Ⓟ | Composite | ASME |
  |---|---|---|---|---|---|---|---|
  | straightness ("Straightness") | form | yes | yes | no | no | no | yes |
  | flatness ("Flatness") | form | no | no | yes | no | no | yes |
  | circularity ("Circularity") | form | no | no | no | no | no | yes |
  | cylindricity ("Cylindricity") | form | no | no | no | no | no | yes |
  | lineProfile ("Profile of a line") | profile | no | no | yes | no | yes | yes |
  | surfaceProfile ("Profile of a surface") | profile | no | no | yes | no | yes | yes |
  | parallelism ("Parallelism") | orientation | yes | yes | yes | yes | no | yes |
  | perpendicularity ("Perpendicularity") | orientation | yes | yes | yes | yes | no | yes |
  | angularity ("Angularity") | orientation | yes | yes | yes | yes | no | yes |
  | position ("Position") | location | yes | yes | no | yes | yes | yes |
  | concentricity ("Concentricity") | location | yes | no | no | no | no | **no** |
  | symmetry ("Symmetry") | location | no | no | no | no | no | **no** |
  | circularRunout ("Circular run-out") | runout | no | no | no | no | no | yes |
  | totalRunout ("Total run-out") | runout | no | no | no | no | no | yes |

  Ⓕ (free state) is allowed everywhere. Raw values (coding) are the case names. Cost: rarer forms (Y14.5's derived median plane flatness Ⓜ,
  ISO's CZ, UZ, statistical tolerancing) are parked.
- **R8. Rules are warnings in words** (`GDTRules.warnings(for:in:sheet:document:) -> [String]`), in this order, exact:
  1. a form characteristic with any datum: "\(title) is a form tolerance and takes no datum." ("Flatness is a form tolerance and takes no datum.");
  2. an orientation, location or run-out characteristic with no datum in its first row: "\(title) needs a datum reference.";
  3. position whose frame's view has no dimension with `DimensionTolerance.basic` (DR-2's boxed tolerance is the basic-dimension flag; no new
     flag): "A position tolerance's feature should be located by basic (boxed) dimensions, and no dimension in this view is basic.";
  4. each datum letter (in row, then reference order, each letter once) that no datum feature symbol on any sheet of the document carries:
     "Datum \(L) isn't defined: no datum symbol on this drawing has that letter.";
  5. ASME with concentricity: "Concentricity isn't in ASME Y14.5-2018; use position, runout or profile instead."; with symmetry: "Symmetry isn't in
     ASME Y14.5-2018; use position or profile instead.";
  6. a composite frame whose second row's datums are not a prefix of the first row's: "The lower row of a composite frame takes the upper row's
     datums or fewer, in the same order.".
  A datum feature symbol whose letter another datum feature symbol of the document also carries: "Datum \(L) is defined by more than one datum
  symbol on this drawing." Rules check what is saved, so a lost frame is still checked. They are `AnnotationReport.warnings`, shown on the
  symbol's inspector page, listed under "CHECKS" in the sheet inspector ("\(label): \(warning)") and in every export's warnings (R13). Nothing
  is refused for a rule. Cost: rule 3 asks only whether the view has a basic dimension, not whether that dimension locates this feature; a
  stricter check (which edges the basic dimensions reach) is parked.
- **R9. The standard switch** (decision 1: content is kept). A saved concentricity or symmetry frame under ASME is kept and drawn with its ISO
  glyph, and warns (R8 rule 5); the characteristic menu under ASME lists the twelve ASME characteristics plus the frame's own when it is one of
  the two. Choosing concentricity or symmetry under ASME refuses "ASME Y14.5-2018 has no concentricity or symmetry symbol.". Composite frames
  restyle (R4). Cost: none.
- **R10. Datum letters** (`DatumLetters`). Valid: one or two capitals A to Z, never I, O or Q (both standards); typed small letters are
  uppercased; anything else refuses "A datum letter is one or two capitals from A to Z, without I, O or Q." A new datum symbol takes the first
  of `ViewLetters.letter(at:)`'s sequence (A … Z without I, O, Q, then AA, AB…) that no datum feature symbol of the **document** carries
  (datums are per drawing, all sheets). A duplicated sheet keeps its letters (the duplicates then warn, R8). Decoding keeps a saved letter as it
  is. Cost: duplicating a sheet makes duplicate-datum warnings until the copy is re-lettered.
- **R11. Composing** (`AnnotationPass`). Per view: every annotation that is not on a dimension, in id order (DR-2's loop; symbols on lines are
  among them); then frames on dimensions, in id order; then datum symbols on dimensions, in id order, so a hanging datum sits below the frames
  on the same dimension. `AnnotationDrawing` and `AnnotationReport` gain `labelRect: Rect2D?` (the first label's bounding rectangle, box
  included) and `dimensionLine: [Vector2]?` (a linear dimension's first run's two arrow tips in feet order, or an ISO diameter's two tips;
  nil otherwise), set for held and lost-drawn dimensions alike, and `warnings: [String]`. A symbol on a held dimension is held; on a lost one it
  is lost with the same reason and drawn (`isLost`) from that dimension's lost drawing; on a dimension that drew nothing it is listed and not
  drawn. A **lost** symbol on a line draws from its last figure (`AnnotationFigure.attachment(foot:along:)`, model plane, saved like DR-2's
  figures) with every piece `isLost`, plus a "?" text (cap h, `.dimension`, `isLost`) `textGap` right of its frame's top right; with no last
  figure, DR-2's lone "?". A symbol's `LastGood` is `values: []`, `lines: [its plain text]`, figure `.attachment`; a symbol on a dimension has no
  figure of its own (`AnnotationRefresh` returns nil for it, as for a note). Plain texts (lists and warnings, never drawn): a frame "\(title)
  Ø0.1 (M) | A | B (M)" (rows joined " / ", modifiers "(M)", "(L)", "(F)", "(T)", "(P) 20"), a datum "Datum A", a surface "Surface texture",
  then " Ra 1.6" and " lay X" when set. `SheetPicture.checkedAnnotations: [AnnotationID]` lists, in sheet order, the annotations whose report
  has warnings. Cost: a frame stacked under a dimension's label can overlap neighbours; the user drags it (`offset`).
- **R12. Sheet notes** (`SheetNotes` on `DrawingSheet.notes`, written only when not empty). `SheetNotes { lines: [String]; edgeBreak: EdgeBreak?;
  surface: SurfaceRequirement? }`, `EdgeBreak { minimum: Double; maximum: Double }` (mm, 0 < minimum ≤ maximum). Drawn by `SheetNotesLayout`
  above the title block (ISO 21920-1 and ISO 7200 put the general requirements beside it; the block's table is full): the general surface
  requirement first, its symbol standing with its apex `notesGap` = 4 mm above the block's top, right-aligned to the block's right edge,
  followed, when the sheet has any surface texture symbol, by "(", the basic symbol, ")" (ISO's "unless otherwise stated" form); above it (or
  above the block when there is none), left-aligned to the block's left edge, the notes numbered "1. …", one per line, the first on top, cap h,
  pitch `AnnotationStyle.linePitch × h`, the edge-break note last: ISO "Break all sharp edges \(min) to \(max)." (or "Break all sharp edges
  \(min)." when equal), ASME "BREAK ALL SHARP EDGES \(min)-\(max)" (or "BREAK ALL SHARP EDGES \(min)"), numbers by `GDTNumber.tolerance`.
  Texts on `.text`, the surface strokes on `.text`. Typed lines are never wrapped. Cost: ISO 13715's graphical edge symbol is parked (words
  only).
- **R13. Layers and export.** Datum, frame and surface symbols draw on `.dimension` (strokes, fills, texts), like dimensions; sheet notes on
  `.text`; no new DXF layer. The PDF and the DXF of the sheet carry them; "DXF of View at 1:1 with Annotations" maps a view's symbols back as it
  maps its dimensions. Every export adds, after the lost-annotation sentences, one sentence per warning of `checkedAnnotations` (ten per sheet,
  then a count): "On “\(sheet)”, “\(label)”: \(warning)", then "On “\(sheet)”, 1 more symbol has a warning." / "On “\(sheet)”, \(n) more symbols
  have warnings.". Cost: none.
- **R14. File format 20.** A format-19 reader refuses an unknown annotation kind with a generic error, so the version is bumped and an older
  build gives its "newer file" refusal. `GraphFile`'s comment gains "20: DR-4's datum feature symbols, feature control frames and surface
  texture symbols (`AnnotationKind`), `AnnotationFigure.attachment` and a sheet's `notes`; a version-19 reader cannot decode the new annotation
  kinds." Decoding repairs: a symbol on a dimension that is not on the sheet, is not a dimension or hole callout, or lies in another view is
  dropped; a symbol with no view is dropped; a frame with no rows is dropped, one with more than two keeps two, a composite of a characteristic
  that takes none keeps its first row, datum references past three are dropped. Group, Ungroup and Make Unique rename a symbol's
  `LeaderEnd.target` (`DrawingAnnotation.renamingTags`). Cost: none.
- **R15. Tools, keys, steps and inspector.**
  - `DrawingTool` gains `datum` ("Datum"), `featureControlFrame` ("Feature Control Frame") and `surfaceFinish` ("Surface Finish") after
    `note`; keys A, G and R over the sheet canvas with nothing focused; all three are annotation tools.
  - Flow: the first click names the target (a dimension or hole callout under the click by `SheetHitTest.annotation`, else a line by R2's
    purpose, refusals as R2), shown as the draft following the pointer; the next click places it (datum: `distance` from the foot's line, or the
    nearer `dimensionEnd` and the distance along the line; frame: `offset`; surface: standing when R6 allows it and the click lies above the line
    within `standSnap` = 3 mm of it, else `offset`), one step, the new symbol selected, the tool kept. Esc drops the target, then the tool.
  - New symbols: a datum takes R10's next letter; a frame copies the last frame placed in this editor session (`frameTemplate`, not saved),
    else Flatness 0.05 mm, width zone, no modifiers, no datums; a surface symbol copies the last placed (`surfaceTemplate`), else material
    removal required, Ra 3.2 µm, no lay.
  - `DrawingStepName` gains "Add Datum", "Add Feature Control Frame", "Add Surface Symbol", "Change Datum Letter", "Change Feature Control Frame",
    "Change Surface Symbol", "Move Symbol", "Delete Symbol", "Reattach Symbol", "Edit Notes", "Change Edge Break" and "Change General Surface"
    (in `all`). Moving or deleting only symbols is "Move Symbol" / "Delete Symbol"; a mix stays "Move Annotations" / "Delete Annotations".
    A setter whose value equals the current one commits nothing.
  - Inspector pages: Datum (Letter, "On a line" or "On a dimension", warnings, a lost reason, Delete); Feature Control Frame (Characteristic,
    then per row Zone (Width / Ø, shown when R7 allows Ø), Tolerance, Material (None / M / L, when allowed), Free state, Tangent plane (when
    allowed), Projected and its length (when allowed), Datum 1 to 3 with their Material, then Composite (when allowed), warnings, a lost
    reason, Delete); Surface (Process: Any / Removal required / Removal prohibited, Parameter: None / Ra / Rz, Value in µm or µin, Lay, Stands
    on the line / On a leader, Delete); the sheet page gains NOTES (a multi-line box, one note per line), Edge break (two fields), General
    surface (Process: None / Any / Removal required / Removal prohibited, Parameter, Value) and CHECKS (R8).
  - Sentences (exact): a tolerance value "A tolerance is a number greater than 0, such as 0.05."; a projected length "A projected zone's length is
    a length greater than 0."; a roughness value "A roughness value is a number greater than 0, such as 1.6."; an edge break "An edge break is
    one or two lengths greater than 0, the smaller first."; a modifier the characteristic does not take "\(title) takes no diameter zone." /
    "\(title) takes no material condition." / "\(title) takes no tangent plane." / "\(title) takes no projected zone."; a fourth datum "A frame
    takes at most three datum references."; composite "Only position and profile frames can be composite."; standing "A surface symbol stands
    only on a horizontal line, with the symbol above it.".
- **R16. Moving, deleting and copying.** Dragging or nudging: a datum on a line slides its foot along the line (`hint` moves by the along part
  over the view's scale) and changes `distance` by the across part; a datum on a dimension moves to the nearer end and the pointer's distance
  (with a line) or changes `distance` by the downward part (hanging); a frame changes `offset`; a standing surface symbol slides its foot, one on
  a leader changes `offset`. A symbol whose dimension moves in the same gesture is not moved itself. `duplicateSheet` remaps `.dimension`
  attachments to the copies' new ids. `replaceDocument` drops a symbol target whose view or dimension is gone. Cost: none.
- **R17. Pictorial views take no symbols** (R2's sentence), as they take no dimensions (decision 4). Cost: none.
- **R18. Performance.** Symbols compose in time linear in the sheet's annotations; R8's datum letters are gathered once per compose (one set
  for the document, passed to every check), so no rule scans the sheet per symbol. No benchmark row (DR-2's `drawing-3` already measures a full
  annotation compose; this adds no kernel call and no projection). Cost: none.
- **R19. Parked.** A datum symbol on a frame, ASME's datum targets, ISO's CZ, UZ and statistical modifiers, Y14.5's derived-median-plane
  flatness Ⓜ, stacked frames that are not composite, surface symbols standing on non-horizontal lines, all-around and manufacturing-method
  surface notes, ISO 13715's edge symbol, a stricter basic-dimension check (R8 rule 3), datum letters per sheet, and symbols in pictorial views.

**Backlog.** Pulled in: `DimensionNumber.render` gives "?" for a non-finite value (never "0") and a measurement with a non-finite value is lost
`.refused("What it measures has no finite size here.")` (Task 3, Task 5: frames print numbers through it); a lost dimension's label keeps its
stack and box (Task 5: rebuilt from `LastGood.values` and the dimension's own tolerance, so a lost basic dimension stays boxed); `setDimensionKind`
refuses a mismatch "A dimension keeps its kind of measure; delete it and dimension again to measure something else." instead of ignoring it
(Task 8); the screen's arrowheads are wound one way so overlapping fills (a datum triangle on a dimension line's end) never cancel (Task 9);
a derived view's marks on a parent with nothing drawn now give a notice, "The view this section was cut from has nothing drawn yet, so its
cutting line isn't shown." / "The view this auxiliary view was projected from has nothing drawn yet, so its arrow isn't shown." (Task 6).
**Stay parked:** `PDFNumber.format` writing "0" for a non-finite value (no DR-4 geometry is non-finite: feet come from finite held geometry and
glyphs from constants), HoleReader's full circle split into two arcs (frames hang on callouts and dimensions, not on HoleReader), and every other
DR-1, DR-2 and DR-3 item in `.superpowers/sdd/2026-11-26-dr-4-gdt-symbols/backlog.md` and CLAUDE.md's parked lists.

## Review Focus

1. **A model edit under a symbol.** A width change keeps a datum, a frame and a surface symbol on their lines (foot moved, still held); the edge
   gone loses them with "?", listed and exported with a warning, never re-attached to a neighbour. Task 5 (`aSymbolFollowsItsLineThroughAWidthChange`,
   `aLostSymbolKeepsItsLastPlaceWithAQuestionMark`), Task 10 (`symbolsStayHeldThroughAWidthChange`, `aRemovedEdgeLosesItsDatum`).
2. **A symbol on a dimension that moves, is lost, is deleted or changes its layout.** It follows the dimension, is lost with it, goes with it
   in one step and comes back with undo, and a datum hangs under the label when the dimension line goes (an ISO diameter switched to ASME).
   Task 1 (`removingADimensionRemovesItsSymbols`), Task 5 (`aFrameFollowsItsDimension`, `aSymbolOnALostDimensionIsLost`,
   `aDatumHangsWhenTheDimensionLineGoes`), Task 7 (`deletingADimensionDeletesItsSymbolsInOneStep`).
3. **The standard switch and characteristics ASME lacks.** A concentricity frame survives a switch to ASME, draws, and warns; the inspector
   refuses a new one under ASME. Task 4 (`asmeWarnsAboutConcentricityAndSymmetry`), Task 8 (`asmeRefusesConcentricity`).
4. **Datum letters.** Lowercase typed, I, O and Q, duplicates across sheets, undefined references, a duplicated sheet. Task 1 (`datumLetterRules`,
   `nextLetterSpansTheDocument`), Task 4 (`duplicateAndUndefinedLetters`), Task 8 (`aLetterIsValidated`).
5. **Screen, PDF and DXF agree.** Glyphs are strokes, no text outside WinAnsi, PDF bytes pinned, symbols on DIMENSION, overlapping fills drawn
   whole. Task 2 (`noTextIsOutsideWinAnsi`), Task 6 (`symbolsPageDigest`, `symbolsAreOnTheDimensionLayer`), Task 9 (`overlappingFillsDoNotCancel`).
6. **Inch documents.** Frames read ".005" (ASME) and "0.005" (ISO in inches), roughness reads microinches. Task 3 (`inchTolerancesKeepPrecision`,
   `roughnessInInchesIsMicroinches`).
7. **Moving and nudging symbols** with and without their dimension selected: a symbol is never moved twice. Task 7 (`aSymbolMovesWithItsDimensionOnce`).

---

### Task 1: The symbol kinds in the model, and file format 20

**Files:**
- Create: `Sources/CreatorDrawing/Model/Annotations/GeometricTolerance.swift` (`GeometricCharacteristic` with R7's members, `ToleranceFamily`,
  `ToleranceZone`, `MaterialCondition`, `ProjectedZone`, `DatumReference`, `ToleranceRow`, `FeatureControlFrame`),
  `Sources/CreatorDrawing/Model/Annotations/DatumFeature.swift`, `SurfaceTexture.swift` (`SurfaceProcess`, `RoughnessParameter`, `SurfaceLay`,
  `SurfaceRequirement`, `SurfaceTexture`), `SymbolAttachment.swift`, `Sources/CreatorDrawing/Model/SheetNotes.swift` (`SheetNotes`, `EdgeBreak`),
  `Sources/CreatorDrawing/Model/DatumLetters.swift`
- Modify: `Model/Annotations/DrawingAnnotation.swift` and `Annotations+Coding.swift` (the kinds), `AnnotationFigure.swift` (`.attachment`),
  `Model/DrawingSheet.swift` (`notes`, R14's repairs, `removeAnnotation` cascade, `symbols(on:)`), `Sources/CreatorGraph/GraphFile.swift` (20 and
  its comment), `Sources/CreatorGraph/Groups/DrawingDocument+TagRenaming.swift`, `Sources/CreatorDrawingEditor/DrawingEditorModel+Sheets.swift`
  (`duplicateSheet` remaps attachments). Every exhaustive `switch` over `AnnotationKind` or `AnnotationFigure` that stops compiling gets the new
  cases as "draws nothing / not movable / no anchors" placeholders, each marked `// DR-4 Task N` naming the task that fills it (5, 7 or 8).
- Test: `Tests/CreatorDrawingTests/SymbolModelTests.swift`, `Tests/CreatorDrawingTests/DatumLettersTests.swift`, `Tests/CreatorGraphTests/DrawingsFileTests.swift`
  (additions), `Tests/CreatorGraphTests/` the existing drawing-anchor renaming test file (addition; find it with `grep -rl renamingTags Tests/CreatorGraphTests`),
  `Tests/CreatorDrawingEditorTests/SheetEditingTests.swift` (addition)

**Interfaces:**
- Produces: R1's types exactly, with `public init`s whose optional parameters default to nil/false/empty; `GeometricCharacteristic: String,
  CaseIterable` in R7's order with `title: String`, `family: ToleranceFamily` (`.form`, `.profile`, `.orientation`, `.location`, `.runout`),
  `takesDiameterZone`, `takesMaterialCondition`, `takesTangentPlane`, `takesProjectedZone`, `allowsComposite`, `isInASME: Bool`;
  `FeatureControlFrame.isComposite: Bool`; `AnnotationFigure.attachment(foot: Vector2, along: Vector2)` (coded `"attachment"`, keys `foot`,
  `along`); `DrawingSheet.notes: SheetNotes` (`SheetNotes.isEmpty`), `DrawingSheet.symbols(on dimension: AnnotationID) -> [DrawingAnnotation]`
  (sheet order); `DatumLetters.isValid(_ letter: String) -> Bool`, `DatumLetters.normalized(_ typed: String) -> String?` (uppercased and
  trimmed, nil when invalid), `DatumLetters.letters(in document: DrawingDocument) -> [String]` (every datum symbol's letter, sheets then
  annotation order), `DatumLetters.next(in document: DrawingDocument) -> String`; `DrawingAnnotation.symbolAttachment: SymbolAttachment?` (the
  attachment of a datum or frame, `.feature` of a surface symbol, nil otherwise); `GraphFile.currentFormatVersion == 20`.

- [ ] **Step 1: Tests.**
  - `SymbolModelTests`: `everyKindRoundTripsByType` (each kind's JSON has its `"type"` string and no `"_0"`; a frame with two rows, Ø, M, F, T,
    P 20, three datums with modifiers; a surface symbol standing and one with an offset); `attachmentsRoundTrip` (`.feature` and `.dimension`,
    `"type"` keys); `theAttachmentFigureRoundTrips`; `capabilitiesFollowTheTable` (every row of R7's table, including `isInASME` false for
    concentricity and symmetry only); `removingADimensionRemovesItsSymbols` (a dimension with a frame and a datum on it, and a datum on a line:
    `removeAnnotation(dimension)` leaves only the datum on the line); `aSymbolOnAMissingDimensionIsDropped` (decode); `aSymbolOnANoteIsDropped`;
    `aSymbolOnAnotherViewsDimensionIsDropped`; `aSymbolWithoutAViewIsDropped`; `framesAreRepaired` (no rows dropped; three rows keep two; a
    composite flatness keeps one row; four datums keep three); `sheetNotesAreWrittenOnlyWhenSet` (an empty `SheetNotes` writes no `notes` key;
    lines, an edge break and a general surface round-trip).
  - `DatumLettersTests`: `datumLetterRules` ("A", "Z", "AA" valid; "I", "O", "Q", "AI", "AAA", "1", "", "Ä" invalid; " b " normalizes to "B");
    `nextLetterSpansTheDocument` (A on sheet 1 and B on sheet 2: "C"; A and C used: "B"; after Z: "AA").
  - `DrawingsFileTests`: `aFormat19FileOpensAndIsWrittenAs20`; `aNewerFileIsRefused` (21); `symbolsRoundTrip` (a document with all three kinds and
    sheet notes).
  - Renaming test: `symbolsAreRenamed` (Group's table renames a datum's, a frame's and a surface symbol's `LeaderEnd.target` picks; a `.dimension`
    attachment is unchanged).
  - `SheetEditingTests`: `duplicatingRemapsSymbolAttachments` (a frame on a dimension: the copy's frame names the copied dimension; letters kept).
- [ ] **Step 2: Run** `swift test --filter 'SymbolModelTests|DatumLettersTests|DrawingsFileTests|SheetEditingTests'` and the renaming test;
  compile failure.
- [ ] **Step 3: Implement** R1, R7's table, R10's letter rules, R12's model, R14 (repairs in `DrawingSheet.init(from:)` after the annotations
  are filtered by view; the cascade in `removeAnnotation`).
- [ ] **Step 4: Run** the filter, then `swift test --filter CreatorDrawingTests`, `--filter CreatorGraphTests`, `--filter CreatorDrawingEditorTests`; pass.
- [ ] **Step 5: Commit** "Drawings: datum, tolerance frame and surface symbols in the model, file format 20".

### Task 2: The glyphs

**Files:**
- Create: `Sources/CreatorDrawing/Symbols/DrawingSymbols+Tolerances.swift` (R3's table, `circled`, the lay ⊥),
  `Sources/CreatorDrawing/Symbols/DrawingSymbols+Surface.swift` (R6's symbol from its apex), `Sources/CreatorDrawing/Symbols/DrawingSymbols+Datum.swift`
  (the square and triangle), `Sources/CreatorDrawing/Style/SymbolStyle.swift`
- Test: `Tests/CreatorDrawingTests/ToleranceGlyphTests.swift`, `Tests/CreatorDrawingTests/SurfaceSymbolTests.swift`, `Tests/CreatorDrawingTests/DatumSymbolTests.swift`

**Interfaces:**
- Consumes: Task 1's enums.
- Produces:
  - `public struct SymbolStyle: Hashable, Sendable` with factors of h (`frameHeight` 2, `framePadding` 0.5, `datumCellMinimum` 2,
    `circleRadius` 0.6, `circledLetter` 0.7, `circledAdvance` 1.2, `modifierGap` 0.3, `datumSquare` 2, `datumTriangle` 1.2, `datumLeaderMinimum` 1,
    `surfaceShort` 1.4, `surfaceLong` 3, `surfaceTextGap` 0.3, `layOrigin` (1, 0.2), `layGlyph` 0.8, `defaultSurfaceOffset` (2, 4)) and mm
    constants `notesGap` 4, `standSnap` 3; `static func of(_ standard: DrawingStandard) -> SymbolStyle` (the same values for both standards today,
    so a later difference is one place). Factor members are multiplied by h at the call site (`style.frameHeight * h`).
  - `DrawingSymbols.characteristic(_ c: GeometricCharacteristic, origin: Vector2, h: Double) -> [SheetSegment]`;
    `DrawingSymbols.circled(_ letter: String, center: Vector2, h: Double) -> (segments: [SheetSegment], text: PlacedText)`;
    `DrawingSymbols.layPerpendicular(origin: Vector2, h: Double) -> [SheetSegment]`;
    `DrawingSymbols.surface(_ process: SurfaceProcess, apex: Vector2, h: Double, extension: Double?) -> [SheetSegment]` (`extension`: the
    horizontal line's length past the long leg, nil without a parameter);
    `DrawingSymbols.datumTriangle(foot: Vector2, along: Vector2, toward n: Vector2, h: Double) -> [Vector2]` (the fill: base ends, then apex);
    `DrawingSymbols.datumSquare(center: Vector2, h: Double) -> [Vector2]` (closed polyline, five points).

- [ ] **Step 1: Tests.**
  - `ToleranceGlyphTests` (h = 2.5, origin (10, 20)): one test per characteristic, `straightnessIsOneLine` … `totalRunoutIsTwoArrowsOnABase`, each
    comparing the segments with R3's table within 1e-12 (arcs by centre, radius, start and sweep); `slantsAreExactConstants` (parallelism's and
    angularity's x offsets equal `(3.0).squareRoot() / 3 × h` exactly, `==`); `everyGlyphFitsItsCellLoosely` (every point within the box grown by
    0.05h); `circledLetterIsCentred` (the text's run centre within 1e-9 of the circle's centre horizontally, its cap middle vertically; radius
    0.6h; cap 0.7h); `noTextIsOutsideWinAnsi` (for every characteristic and modifier, no `PlacedText` from this file holds a byte that
    `DrawingText.layout` had to replace, `hasReplacements` false).
  - `SurfaceSymbolTests` (apex (0, 0), h 2.5): `theBasicSymbolHasTwoLegsAt60Degrees` (legs to (−1.4h × k, 1.4h) and (3h × k, 3h), k as R6);
    `removalRequiredAddsTheBar`; `removalProhibitedAddsTheInscribedCircle` (radius 1.4h / 3 at (0, 2 × 1.4h / 3), tangent to both legs within 1e-12);
    `aParameterAddsTheExtension`; `layPerpendicularIsTheGlyph`.
  - `DatumSymbolTests`: `theTriangleSitsOnTheLine` (base ends at foot ± along × 0.6h, apex at foot + n × 1.2h × s); `theSquareIsTwoH`.
- [ ] **Step 2: Run** `swift test --filter 'ToleranceGlyphTests|SurfaceSymbolTests|DatumSymbolTests'`; fail.
- [ ] **Step 3: Implement** R3, R5's and R6's shapes, `SymbolStyle`.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: GD&T, datum and surface texture glyphs as strokes".

### Task 3: Frame, datum and surface layouts, and their numbers

**Files:**
- Create: `Sources/CreatorDrawing/Layout/FrameLayout.swift`, `Sources/CreatorDrawing/Layout/DatumLayout.swift`, `Sources/CreatorDrawing/Layout/SurfaceLayout.swift`,
  `Sources/CreatorDrawing/Dimensions/GDTNumber.swift`
- Modify: `Sources/CreatorDrawing/Dimensions/DimensionNumber.swift` (non-finite renders "?")
- Test: `Tests/CreatorDrawingTests/FrameLayoutTests.swift`, `DatumLayoutTests.swift`, `SurfaceLayoutTests.swift`, `GDTNumberTests.swift`,
  `DimensionNumberTests.swift` (addition)

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces (all return DR-2's `AnnotationDrawing`, `fitFrame()` called):
  - `FrameLayout.draw(_ frame: FeatureControlFrame, topLeft: Vector2, h: Double, format: NumberFormat, style: DrawingStyle) -> AnnotationDrawing`
    (R4's compartments; `style.standard` picks composite's form) and `FrameLayout.size(of:h:format:standard:) -> Vector2`;
    `FrameLayout.leader(from foot: Vector2, toFrameAt rect: Rect2D, rowHeight: Double, style: AnnotationStyle) -> AnnotationDrawing` (R4's side rule).
  - `DatumLayout.onLine(letter: String, foot: Vector2, along: Vector2, distance: Double, edgeEnds: (Vector2, Vector2)?, h: Double, style: AnnotationStyle)`,
    `DatumLayout.onDimensionLine(letter:end:other:distance:h:style:)` (`end` the line end it stands on, `other` the other end), `DatumLayout.hanging(letter:below
    bottomMiddle: Vector2, distance: Double, h:style:)`; `edgeEnds` (sheet) given when the foot may lie beyond them (the extension line, R5).
  - `SurfaceLayout.draw(_ texture: SurfaceTexture, foot: Vector2, along: Vector2, h: Double, format: NumberFormat, style: AnnotationStyle) -> AnnotationDrawing`
    (standing or on a leader by R6) and `SurfaceLayout.requirement(_ requirement: SurfaceRequirement, apex: Vector2, h: Double, format: NumberFormat) -> AnnotationDrawing`
    (the standing symbol alone, for R12).
  - `GDTNumber.tolerance(_ mm: Double, format: NumberFormat) -> String`, `GDTNumber.roughness(_ micrometres: Double, format: NumberFormat) -> String`.
  - `FeatureControlFrame.plainText`, `DatumFeature.plainText`, `SurfaceTexture.plainText` (R11's texts; they need `GDTNumber`, so they live here).

- [ ] **Step 1: Tests.**
  - `GDTNumberTests`: `tolerancesTakeTheDecimalsTheyNeed` (0.05 in a 1-decimal mm document reads "0.05"; 0.1 reads "0.1"; 0.12345 reads "0.1235");
    `inchTolerancesKeepPrecision` (0.127 mm in a 3-decimal inch ASME document reads ".005"; in ISO with inches "0.005"); `theCommaIsUsed` (ISO
    comma: "0,05"); `roughnessInMillimetreDocuments` (1.6 → "1.6", 0.8 → "0.8", 12.5 → "12.5"); `roughnessInInchesIsMicroinches` (1.6 → "63",
    3.2 → "126", 0.8 → "31").
  - `DimensionNumberTests`: `nonFiniteRendersAQuestionMark` (`.nan`, `.infinity`: text "?", `isZero` false).
  - `FrameLayoutTests` (h 2.5, ISO, mm): `aSingleRowFrame` (flatness 0.05: two compartments, height 5, the glyph cell 5 × 5, the value text's
    baseline 1.25 above the bottom, compartments as wide as content + 2 × 1.25); `datumCellsAreAtLeastTwoH` ("A" cell width 5);
    `modifiersComeInOrder` (Ø0.1 Ⓜ Ⓕ Ⓣ Ⓟ 20: the circles' centres in that x order, each 0.3h after the previous piece, "20" after Ⓟ);
    `aDiameterZoneWritesØ` (the first text starts "Ø"); `asmeCompositeSpansTheSymbol` (one glyph cell 5 × 10, two rows' value cells);
    `isoCompositeStacksTwoFrames` (two glyph cells, each 5 × 5); `compositeColumnsAlign` (row 2's datum cell edges equal row 1's);
    `linesAreThinOnTheDimensionLayer`; `theLeaderMeetsTheNearerSide` (a foot left of the frame: the shoulder ends on the left side's middle;
    right: the right side).
  - `DatumLayoutTests`: `onALine` (foot (100, 50), along (1, 0), distance 10: triangle base y 50, square centre (100, 60));
    `belowALine` (distance −10: apex below, square centre (100, 40)); `theDistanceIsClamped` (distance 1: drawn at the minimum);
    `onAnExtensionLine` (foot beyond the edge's end: an extension line from `extensionGap` past the end to `extensionOvershoot` past the
    triangle); `onADimensionLine` (end (120, 80), other (80, 80): triangle base vertical at x 120, apex toward +x, square centre (120 + distance, 80));
    `hangingUnderALabel`.
  - `SurfaceLayoutTests`: `standsOnAHorizontalLine` (apex on the foot); `takesALeaderOtherwise` (arrowhead on the foot, a line from it to the
    apex at foot + offset); `aStandingSymbolOnASlantedLineTakesTheDefaultLeader`; `theValueSitsUnderTheExtension` (origin (3h k + 0.3h, 3h − 1.3h)
    from the apex; "Ra 1.6"); `layTextAndGlyph` ("X" as text at (h, 0.2h); ⊥ as strokes).
  - `plainTexts` (in `FrameLayoutTests`): "Position Ø0.1 (M) | A | B (M)", the composite joined " / ", "Datum A", "Surface texture Ra 1.6 lay X".
- [ ] **Step 2: Run** `swift test --filter 'GDTNumberTests|DimensionNumberTests|FrameLayoutTests|DatumLayoutTests|SurfaceLayoutTests'`; fail.
- [ ] **Step 3: Implement** R4, R5, R6's placement, `GDTNumber`, and the non-finite render.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: tolerance frame, datum and surface symbol layouts".

### Task 4: The rules

**Files:**
- Create: `Sources/CreatorDrawing/Rules/GDTRules.swift`
- Test: `Tests/CreatorDrawingTests/GDTRulesTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces: `GDTRules.Context { standard: DrawingStandard; definedLetters: [String: Int] /* letter → how many datum symbols carry it in the
  document; built once per compose with DatumLetters.letters */; basicViews: Set<ViewID> /* views of the sheet with a basic dimension */ }`
  (`static func make(document:sheet:) -> Context`), `GDTRules.warnings(for annotation: DrawingAnnotation, context: Context) -> [String]` (R8,
  in its order; datum symbols get the duplicate sentence; surface symbols none), and the sentence builders as statics (`formWithDatum(_:)`,
  `needsDatum(_:)`, `positionNeedsBasic`, `undefined(_:)`, `duplicate(_:)`, `asmeConcentricity`, `asmeSymmetry`, `compositeDatums`).

- [ ] **Step 1: Tests.** `formTakesNoDatum` (flatness | A: the exact sentence); `orientationNeedsADatum` (perpendicularity with none);
  `runoutNeedsADatum`; `profileMayGoEitherWay` (none); `positionNeedsABasicDimensionInItsView` (no basic: the sentence; a basic dimension in
  another view: still the sentence; in its view: none); `duplicateAndUndefinedLetters` (a frame referencing D with no D symbol: the undefined
  sentence once though D appears in both rows; two datum symbols "A" on two sheets: each gets the duplicate sentence); `asmeWarnsAboutConcentricityAndSymmetry`
  (ISO: none; ASME: the sentences); `compositeLowerDatumsArePrefix` (A B / A: none; A B / B: the sentence); `warningsComeInOrder` (a frame
  breaking rules 2, 3 and 4: in that order); `aLostFrameIsStillChecked` (the rules read only the saved frame).
- [ ] **Step 2: Run** `swift test --filter GDTRulesTests`; fail.
- [ ] **Step 3: Implement** R8.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: GD&T rules as warnings".

### Task 5: Composing symbols on views

**Files:**
- Create: `Sources/CreatorDrawing/Anchors/SymbolFoot.swift` (R2's foot), `Sources/CreatorDrawing/Picture/AnnotationComposer+Symbols.swift`
  (symbols on lines and on dimensions, lost drawing, the "?"), `Sources/CreatorDrawing/Picture/AnnotationEvaluator+Symbols.swift`
- Modify: `Picture/AnnotationComposer.swift` (dispatch; `lostLabel` rebuilds a dimension's labels from `LastGood.values` with its own tolerance,
  falling back to the remembered lines when that throws or the values are empty), `Picture/AnnotationComposer+Kinds.swift` (the evaluator's new
  kinds; a non-finite measured value is lost `.refused("What it measures has no finite size here.")`), `Picture/AnnotationPass.swift` (R11's
  order, `GDTRules.Context` made once per compose and passed in), `Picture/AnnotationReport.swift` (`labelRect`, `dimensionLine`, `warnings`),
  `Layout/AnnotationDrawing.swift` and `Layout/SheetDimensionLayout+Linear.swift`, `SheetDimensionLayout+Leaders.swift`, `SheetDimensionLayout.swift`
  (set `labelRect` in `DrawingBuilder.label` for the first label and `dimensionLine` in the linear first run and the ISO diameter across),
  `Picture/SheetPicture.swift` (`checkedAnnotations`), `Picture/SheetComposer.swift` (pass the document to the pass), `Anchors/LostReason.swift`
  (`.notStraight`), `Picks/DrawingPick.swift` (`.datum`, `.frame`, `.surface` purposes and R2's sentences, `symbolIsometricSentence`; the
  purpose of a reattach), `Picture/AnnotationRefresh.swift` (doc comment: symbols on dimensions are skipped like notes)
- Test: `Tests/CreatorDrawingTests/SymbolComposerTests.swift`, `SymbolPickTests.swift`, `AnnotationRefreshTests.swift` (additions),
  `AnnotationComposerTests.swift` (additions)

**Interfaces:**
- Consumes: Tasks 1 to 4.
- Produces: `SymbolFoot.of(_ geometry: AnchorGeometry, hint: Vector2, frame: ProjectionFrame) -> Result<(foot: Vector2, along: Vector2,
  segment: (Vector2, Vector2)?), LostReason>` (model plane; `segment` the edge's projected ends for a line, nil otherwise); `PickPurpose`
  cases `datum`, `frame`, `surface`; `DrawingPick.symbolIsometricSentence`, `datumCircleSentence`, `surfaceCircleSentence`; `AnnotationReport.labelRect:
  Rect2D?`, `dimensionLine: [Vector2]?`, `warnings: [String]` (defaults nil, nil, []); `SheetPicture.checkedAnnotations: [AnnotationID]`;
  `AnnotationComposer.symbolOnDimensionSentence` ("This symbol hangs on a dimension; reattach the dimension and the symbol follows it.").

- [ ] **Step 1: Tests** (`AnnotationFixtures`: Top view of the plate, edge 102 the horizontal line y = 0 from x 0 to 40, 100 and 103 vertical, ring 0
  the Ø6 hole at (20, 10)).
  - `SymbolPickTests`: `aDatumTakesAStraightLine`; `aDatumRefusesACircle` (R2's sentence); `aCornerPicksItsLine`; `aFrameTakesAFaceOnCircle`;
    `aFrameTakesACentreAsItsCircle`; `aSurfaceRefusesACircle`; `symbolsAreRefusedInIsometricViews`; `anUnnamedEdgeIsRefused` (DR-2's sentence).
  - `SymbolComposerTests`: `aDatumStandsOnItsLine` (strokes, fill and text tagged with the annotation, on `.dimension`; the triangle's base on
    y = the line's sheet y); `aDatumBeyondTheEdgeDrawsAnExtensionLine` (hint x = 50); `aFrameLeadsToItsLine`; `aSurfaceSymbolStands`;
    `aSymbolFollowsItsLineThroughAWidthChange` (topology with edge 102 from x 0 to 60 and the same names: the foot's x unchanged relative to the hint,
    held); `aLostSymbolKeepsItsLastPlaceWithAQuestionMark` (edge 102 removed, `remembered` holding its `.attachment` figure: every piece `isLost`, a
    "?" text, `lostAnnotations` holds it, the report's reason `.missing`); `aSlantedEdgeTurnedCurvedIsNotStraight` (a held edge whose curve is now a
    circle: `.notStraight` for a datum, held for a frame when face on); `aFrameFollowsItsDimension` (a frame on a horizontal dimension: its top
    left is `(labelRect.min.x, labelRect.min.y − textGap) + offset`; moving the dimension's placement moves the frame);
    `framesStackUnderOneDimension`; `aDatumOnADimensionLineEnd`; `aDatumHangsWhenTheDimensionLineGoes` (an ISO diameter with a datum composed in ASME:
    hanging under the label, held); `aHangingDatumSitsBelowTheFrames`; `aSymbolOnALostDimensionIsLost` (same reason, drawn `isLost`, listed);
    `aSymbolOnADimensionThatDrewNothingIsListed`; `warningsReachTheReport` (flatness | A: the report's warnings and `checkedAnnotations`);
    `lostSymbolsReportTheirPlainText` (the report label "Datum A").
  - `AnnotationComposerTests` additions: `aLostBasicDimensionStaysBoxed` (a basic dimension lost: one box stroke and "40?"); `aLostDeviationKeepsItsStack`
    ("40?" with the stack's two texts); `aNonFiniteMeasureIsLost` (the refused sentence).
  - `AnnotationRefreshTests` additions: `aSymbolOnALineRefreshes` (`.attachment` figure, its plain text in `lines`); `aSymbolOnADimensionIsSkipped` (nil).
- [ ] **Step 2: Run** `swift test --filter 'SymbolPickTests|SymbolComposerTests|AnnotationComposerTests|AnnotationRefreshTests'`; fail.
- [ ] **Step 3: Implement** R2's purposes and foot, R11, the lost-label rebuild and the non-finite refusal. DR-1, DR-2 and DR-3 tests unchanged.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: datum, tolerance and surface symbols on views and dimensions".

### Task 6: Sheet notes, the general surface requirement, writers and a notice

**Files:**
- Create: `Sources/CreatorDrawing/Sheet/SheetNotesLayout.swift`
- Modify: `Picture/SheetComposer.swift` (append R12's block after the title block), `Sections/DerivedViewNotices.swift` and
  `Picture/SheetComposer+Marks.swift` (the two backlog sentences when a section's or auxiliary view's parent has no mapping),
  `Tests/CreatorDrawingTests/Support/DrawingFixtures.swift` (`symbolsSheet(standard:)`: a frame of every modifier, a composite, a datum on a line
  and on a dimension, two surface symbols, sheet notes with an edge break and a general surface)
- Test: `Tests/CreatorDrawingTests/SheetNotesTests.swift`, `PDFWriterTests.swift`, `DXFWriterTests.swift` (additions), `SheetComposerDerivedTests.swift`
  (additions)

**Interfaces:**
- Consumes: Tasks 1 to 5.
- Produces: `SheetNotesLayout.picture(for sheet: DrawingSheet, settings: DrawingSettings, format: NumberFormat) -> SheetPicture` (R12; nothing
  for empty notes); `DerivedViewNotices.sectionParentEmpty`, `auxiliaryParentEmpty` (the backlog sentences); `DerivedViewNotices.notices(for:in:contents:)`
  taking the contents (the old signature removed, its callers updated).

- [ ] **Step 1: Tests.**
  - `SheetNotesTests`: `notesSitAboveTheTitleBlock` (bottom line's baseline `notesGap` above the block's top, left edges equal, first line on
    top, "1. " numbering); `theEdgeBreakIsTheLastNote` (ISO mm 0.2 and 0.5: "Break all sharp edges 0.2 to 0.5."; ASME in a 3-decimal inch
    document, 0.2032 and 0.508 mm: "BREAK ALL SHARP EDGES .008-.020"; equal values one number); `theGeneralSurfaceStandsRightAligned`; `parenthesesFollowWhenTheSheetHasSurfaceSymbols` (texts "(" and ")" around the
    basic symbol's strokes; none on a sheet without surface symbols); `notesAreOnTheTextLayer`; `emptyNotesDrawNothing`.
  - `SheetComposerDerivedTests` additions: `aParentWithNothingDrawnGivesANotice` (section and auxiliary: the exact sentences; no mark strokes).
  - `PDFWriterTests`: `symbolsPageDigest` (`DrawingFixtures.symbolsSheet()`: SHA-256 pinned; DR-1 to DR-3 digests unchanged; the page's
    content stream has no text byte outside WinAnsi).
  - `DXFWriterTests`: `symbolsAreOnTheDimensionLayer` (every LINE, ARC, CIRCLE, SOLID and TEXT of a symbol on DIMENSION; notes on TEXT);
    `aSymbolsSheetIsDeterministic` (two writes equal; its digest pinned).
- [ ] **Step 2: Run** `swift test --filter 'SheetNotesTests|SheetComposerDerivedTests|PDFWriterTests|DXFWriterTests'`; fail.
- [ ] **Step 3: Implement** R12, R13's layers (no writer change expected; if one is needed, say why in the commit), the notice.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: sheet notes, the general surface requirement, and symbol pages pinned".

### Task 7: The editor's Datum, Feature Control Frame and Surface Finish tools

**Files:**
- Create: `Sources/CreatorDrawingEditor/SymbolDraft.swift` (the target and the placing rule), `Sources/CreatorDrawingEditor/DrawingEditorModel+Symbols.swift`
  (clicks, draft picture, placing, templates)
- Modify: `DrawingTool.swift` (R15's cases and titles), `DrawingStepName.swift` (R15's names, in `all`), `DrawingEditorModel.swift` (`symbolDraft`,
  `frameTemplate`, `surfaceTemplate`; `replaceDocument` pruning), `DrawingEditorModel+Pointer.swift`, `DrawingEditorModel+Keys.swift`,
  `DrawingEditorModel+Annotations.swift` (Esc order), `DrawingEditorModel+AnnotationSelection.swift` (seeds and moves of R16, `groupName` with a
  symbol name, a symbol moved with its dimension once), `DrawingEditorModel+Picking.swift` (`targets(of:)`, `purpose(of:)`, `replacing` for symbols
  on lines; the reattach refusal for symbols on dimensions; step "Reattach Symbol"), `Views/SheetCanvasInput.swift` (A, G, R)
- Test: `Tests/CreatorDrawingEditorTests/SymbolToolTests.swift`, `SymbolSelectionTests.swift`, `DrawingStepNameTests.swift` (additions),
  `SheetCanvasInputTests.swift` (additions), `ReattachTests.swift` (additions)

**Interfaces:**
- Consumes: Tasks 1 to 5.
- Produces: `DrawingTool` cases `datum`, `featureControlFrame`, `surfaceFinish`; `public internal(set) var symbolDraft: SymbolDraft?` (`SymbolDraft
  { tool: DrawingTool; view: ViewID; target: SymbolTarget }`, `SymbolTarget` `.feature(PickedAnchor, hint: Vector2)` or `.dimension(AnnotationID)`);
  `public internal(set) var frameTemplate: FeatureControlFrame?`, `surfaceTemplate: SurfaceTexture?`; `DrawingStepName.addDatum` …
  `changeGeneralSurface` (R15's twelve).

- [ ] **Step 1: Tests** (fixtures: `AnnotationEditorFixtures`' Top view of the plate with its hole, a horizontal dimension and a Ø dimension).
  - `SymbolToolTests`: `aDatumOnALine` (A, a click on the bottom line, a click 10 mm below: one "Add Datum", letter "A", `distance` −10 within
    1e-9, selected, tool kept); `theNextDatumIsB`; `aDatumOnADimension` (a click on the dimension's text: `.dimension(id)`, `dimensionEnd` the end
    nearer the placing click); `aDatumRefusesAnAngle`; `aFrameOnALine` (`offset` = click − foot on the sheet; Flatness 0.05 the first time);
    `theNextFrameCopiesTheLast`; `aFrameOnTheHole` (a click on the circle, then a placing click: `.feature` with the circle's pick);
    `aFrameOnADimension` (`offset` zero when placed at the default spot); `aSurfaceSymbolStandsOnATopLine` (a click within 3 mm above a horizontal
    line: `offset` nil); `aSurfaceSymbolOnALeader` (below it: `offset` set); `aSurfaceSymbolRefusesADimension`; `aSymbolRefusesANote`;
    `isometricViewsRefuseSymbols`; `escapeDropsTheTargetThenTheTool`; `theDraftFollowsThePointer` (`draftPicture` has the symbol at the pointer;
    no commit); `undoPrunesTheTarget` (`replaceDocument` without the dimension: `symbolDraft` nil).
  - `SymbolSelectionTests`: `draggingADatumSlidesItsFoot` (one coalesced "Move Symbol"; `hint` moved by the along part over the scale, `distance` by
    the across part); `draggingAFrameMovesItsOffset`; `draggingAStandingSurfaceSymbolSlidesIt`; `aSymbolMovesWithItsDimensionOnce` (dimension and
    its frame selected and dragged: the frame's `offset` unchanged); `nudgingSymbols` ("Move Symbol"); `deletingADimensionDeletesItsSymbolsInOneStep`
    ("Delete Dimension"; undo restores both); `deletingSymbolsIsDeleteSymbol`.
  - `ReattachTests` additions: `aLostDatumReattachesToAnotherLine` ("Reattach Symbol"); `aSymbolOnADimensionSaysReattachTheDimension` (the sentence).
  - `DrawingStepNameTests`: R15's twelve names in `all`, each made by its method (the setters' ones in Task 8's tests).
  - `SheetCanvasInputTests`: `theLettersAGAndRChooseSymbolTools` (lower and capital).
- [ ] **Step 2: Run** `swift test --filter 'SymbolToolTests|SymbolSelectionTests|ReattachTests|DrawingStepNameTests|SheetCanvasInputTests'`; fail.
- [ ] **Step 3: Implement** R15's flow, R16, R17 and the reattach rules.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingEditorTests`; pass.
- [ ] **Step 5: Commit** "Drawings: the Datum, Feature Control Frame and Surface Finish tools".

### Task 8: The editor's symbol and sheet-note setters

**Files:**
- Create: `Sources/CreatorDrawingEditor/DrawingEditorModel+SymbolInspector.swift`, `Sources/CreatorDrawingEditor/DrawingEditorModel+SheetNotes.swift`
- Modify: `DrawingEditorModel+AnnotationInspector.swift` (`setDimensionKind` refuses a mismatch with the backlog sentence)
- Test: `Tests/CreatorDrawingEditorTests/SymbolInspectorModelTests.swift`, `SheetNotesModelTests.swift`, `AnnotationInspectorTests.swift` (addition)

**Interfaces:**
- Consumes: Tasks 1, 3, 7.
- Produces (each one step named as R15 says, refusing with R15's sentences, committing nothing when unchanged):
  `setDatumLetter(_ text: String, of: AnnotationID)`; `setCharacteristic(_: GeometricCharacteristic, of:)` (drops what the new characteristic
  does not take: Ø to width, Ⓜ/Ⓛ, Ⓣ, Ⓟ, the second row); `setZone(_: ToleranceZone, row: Int, of:)`; `setToleranceValue(text: String, row:, of:)`
  (the document's unit, `units.parse(_, quantity: .length)`); `setMaterialCondition(_: MaterialCondition?, row:, of:)`; `setFreeState(_: Bool,
  row:, of:)`; `setTangentPlane(_: Bool, row:, of:)`; `setProjectedZone(_ isOn: Bool, lengthText: String, row:, of:)` (empty length: none);
  `setDatum(_ index: Int, letterText: String, material: MaterialCondition?, row:, of:)` (empty text removes it and the ones after; index may be
  at most the count); `setComposite(_: Bool, of:)` (on copies row 0); `setSurfaceProcess(_:of:)`, `setRoughness(parameter: RoughnessParameter?,
  valueText: String, of:)` (µm, or µin in an inch document; `Double` after replacing a comma by a point; a parameter with no value keeps the
  previous or 3.2), `setLay(_: SurfaceLay?, of:)`, `setSurfaceStands(_: Bool, of:)`; `setGeneralNotes(_ text: String)` (lines split on "\n",
  trailing whitespace trimmed, empty lines dropped; "Edit Notes"), `setEdgeBreak(minimumText: String, maximumText: String)` (both empty: none;
  one empty: the other for both), `setGeneralSurface(_: SurfaceRequirement?)`, `setGeneralSurfaceValue(text: String)`. Every frame and surface
  setter updates the matching template (R15).

- [ ] **Step 1: Tests.**
  - `SymbolInspectorModelTests`: `aLetterIsValidated` ("b" stores "B"; "I" refused with R10's sentence, nothing committed); `asmeRefusesConcentricity`
    (and a saved one keeps its value when another field changes); `changingTheCharacteristicDropsWhatItTakesNot` (position Ø Ⓜ Ⓟ composite →
    circularity: width, no modifiers, one row, one step); `diameterIsRefusedForFlatness`; `valuesParseInTheDocumentsUnit` (0.005 in inches stores
    0.127); `zeroAndNegativeAreRefused`; `datumsAreAListOfThree` (a fourth refused; clearing datum 2 removes 2 and 3); `compositeOnlyForPositionAndProfile`;
    `roughnessInMicroinches` (63 in an inch document stores 1.6002 within 1e-9); `standingNeedsAHorizontalLine`; `settersUpdateTheTemplates`;
    `noChangeNoCommit` (each setter with the current value).
  - `SheetNotesModelTests`: `notesSplitIntoLines`; `anEdgeBreakNeedsOrderedLengths` (0.5 and 0.2 refused; "" and "" clears; "0.3" and "" stores 0.3
    and 0.3); `theGeneralSurfaceIsSet` ("Change General Surface").
  - `AnnotationInspectorTests`: `aMismatchedKindIsRefused` (linear → radius: the sentence; nothing committed).
- [ ] **Step 2: Run** `swift test --filter 'SymbolInspectorModelTests|SheetNotesModelTests|AnnotationInspectorTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingEditorTests`; pass.
- [ ] **Step 5: Commit** "Drawings: editing symbols and sheet notes".

### Task 9: The editor's views (toolbar, inspector pages, fills)

**Files:**
- Create: `Sources/CreatorDrawingEditor/Views/DatumInspector.swift`, `FrameInspector.swift`, `SurfaceInspector.swift`, `SheetNotesSection.swift`
- Modify: `Views/AnnotationInspector.swift` (the three pages), `Views/SheetInspector.swift` (NOTES, Edge break, General surface, CHECKS),
  `Views/NoteInspector.swift` (`NoteTextEntry` takes a submit closure so the notes box reuses it), `Views/SheetFillShape.swift` (each polygon
  wound counter-clockwise in sheet coordinates before it is added, so overlapping fills never cancel), `Views/DrawingToolbar.swift` (doc comment:
  seventeen tools)
- Test: `Tests/CreatorDrawingEditorTests/DrawingToolbarTests.swift`, `DrawingInspectorTests.swift`, `SheetCanvasRenderTests.swift` (additions),
  `SheetViewEqualityTests.swift` (new properties' variants)

**Interfaces:**
- Consumes: Tasks 7 and 8. Produces views only; every new `.equatable()` view's `==` covers its stored properties (`expectEqualityCovers`).

- [ ] **Step 1: Tests.** `DrawingToolbarTests.everyToolHasAButtonOrMore` (seventeen tools, Datum, Feature Control Frame and Surface Finish after
  Note, overflow into More); `DrawingInspectorTests`: `aFramePageShowsOnlyWhatTheCharacteristicTakes` (flatness: no Zone, Material or Projected
  rows; position: all), `aFramePageListsItsWarnings`, `asmeHidesConcentricityInTheMenu` (and shows it for a frame that has it), `aDatumPageEditsItsLetter`,
  `aSurfacePageShowsMicroinchesInInches`, `theSheetPageHasNotesAndChecks`; `SheetCanvasRenderTests` (pixels through `PixelReader`): `aFrameIsDrawnInInk`,
  `overlappingFillsDoNotCancel` (two triangles, one wound each way, overlapping: the overlap is inked), `aLostSymbolIsWarningColoured`.
- [ ] **Step 2: Run** `swift test --filter 'DrawingToolbarTests|DrawingInspectorTests|SheetCanvasRenderTests|SheetViewEqualityTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingEditorTests`; pass.
- [ ] **Step 5: Commit** "Drawings: symbol tools and pages in the toolbar and inspector".

### Task 10: Symbols in the app

**Files:**
- Modify: `Sources/CreatorApp/AppModel+DrawingExport.swift` (R13's check sentences after the lost ones, in every kind: `checkWarnings(on:in:view:)`,
  `listedChecksPerSheet` = 10)
- Test: `Tests/CreatorAppTests/DrawingSymbolTests.swift` (FakeKernel with hooks), `Tests/CreatorAppTests/DrawingSymbolOCCTTests.swift`
  (`#if canImport(CreatorOCCT)`), `Tests/CreatorAppTests/DrawingExportTests.swift` (additions)

**Interfaces:**
- Consumes: Tasks 1 to 9.
- Produces: `static func checkWarnings(on sheet: DrawingSheet, in picture: SheetPicture, view: ViewID?) -> [String]`; no other API.

- [ ] **Step 1: Tests.**
  - `DrawingSymbolTests`: `addingADatumIsOneUndoStep` (undo removes it, redo brings it back); `aSymbolRefreshesItsLastGood` (after an evaluation
    the editor's `remembered` holds its `.attachment` figure; the document is not marked edited); `savingWritesTheSymbolsLastGood`;
    `groupingKeepsASymbolHeld` (Group the part's producer: the datum stays held).
  - `DrawingSymbolOCCTTests` (a 60 × 40 × 10 Box minus a Ø10 Cylinder through at (30, 20) → Output; Top base view at 1 : 1; datum A on the
    bottom edge, datum B on the left edge; two basic linear dimensions from the hole's centre to A's and B's edges; a Ø dimension on the hole with
    a frame Position Ø0.1 Ⓜ | A | B on it; a surface symbol Ra 1.6 standing on the top edge): `symbolsAreHeldAndWarnNothing` (every report held,
    no warnings); `symbolsStayHeldThroughAWidthChange` (60 → 80: all held, the frame still under the Ø label, A's foot on the bottom edge);
    `aRemovedEdgeLosesItsDatum` (a 2 mm Chamfer, by an Edges by Tag rule, of the edge between the top face and the front face (y = 0), inserted
    between the subtract and the Output: that edge is gone, so datum A and the basic dimension to it are lost `.missing` with "?" and listed;
    the frame on the Ø stays held and warns nothing, since A is still defined by its symbol, lost or not, and the lost dimension is still basic,
    R8 reading what is saved); `aFlatnessWithADatumWarns` (a frame Flatness 0.05 | A: the exact sentence in its report and in
    the PDF export's warnings).
  - `DrawingExportTests`: `thePDFCarriesSymbols` (the page's content stream has the frame's lines and texts "0.1", "A", "B"); `theSheetDXFHasSymbolsOnDimension`;
    `aViewDXFWithAnnotationsMapsSymbolsBack` (at 1 : 2 the datum square is 2h × 2 = 10 model mm wide on A4); `checksAreListedTenPerSheet` (twelve
    warning frames: ten sentences, then "On “Sheet 1”, 2 more symbols have warnings.").
  - Every hook that holds a projection suspends (`HookGate`), never blocks.
- [ ] **Step 2: Run** `swift test --filter 'DrawingSymbolTests|DrawingSymbolOCCTTests|DrawingExportTests'`; fail.
- [ ] **Step 3: Implement** R13's export sentences; fix anything the app integration finds (with a test).
- [ ] **Step 4: Run** `swift test --filter CreatorAppTests`, `--filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: symbols in the app and its exports".

### Task 11: Docs and the suites

**Files:**
- Modify: `CLAUDE.md` (a "Drawings, DR-4" paragraph after DR-3's: the kinds and attachments (R1, R2), glyphs as strokes (R3), the frame,
  datum and surface layouts (R4 to R6), the capability table (R7), the rules and where they show (R8), the standard switch (R9), datum
  letters (R10), composing and lost symbols (R11), sheet notes (R12), layers and export (R13), format 20 (R14), tools, keys and steps (R15),
  moving and copying (R16), pictorial views (R17), no benchmark row (R18), the pulled-in backlog and the parked list (R19); the file-format
  sentence becomes "File format is version 20 (… 20 added datum feature symbols, feature control frames, surface texture symbols and a sheet's
  notes …); files of format 1 to 19 open unchanged and are written as 20"; the `CreatorDrawing` entry names `Rules/` and `SymbolStyle`),
  `docs/verification/human-checks.md` (group DR-4, below), `docs/superpowers/specs/2026-11-24-drawings-design.md` (Status line: "… DR-3 done (…).
  DR-4 done (<date>; human checks group DR-4 pending; R3: every GD&T and surface glyph drawn as strokes, never a font character)."),
  `docs/metalui-gaps.md` (only if a task logged a `DR-4-x` gap)
- Group DR-4 checks: DR4-1 the fourteen characteristic glyphs side by side against ISO 1101's table, and Ⓜ Ⓛ Ⓟ Ⓕ Ⓣ, on screen and in the PDF
  at 400 %; DR4-2 datum A on a line, on an extension line and on a dimension line, in ISO and ASME; DR4-3 a position frame on a hole's Ø with
  A | B | C, Ⓜ, a composite position frame in ISO (two frames) and ASME (one spanning symbol); DR4-4 a surface symbol standing on a top line and
  on a leader, removal required and prohibited, Ra 1.6 and lay ⊥, in a millimetre and an inch document (µin); DR4-5 the rules: flatness with a
  datum, perpendicularity without, position without basic dimensions, an undefined letter, a duplicated letter, concentricity after switching to
  ASME, each in the inspector, the CHECKS list and the export's warnings; DR4-6 change the part's width: every symbol follows; delete the edge a
  datum stands on: "?" in the warning colour, listed, reattach it by a click; DR4-7 drag and nudge symbols, with and without their dimension;
  delete a dimension with a frame on it, then undo; DR4-8 notes, an edge break and a general surface requirement above the title block, ISO and
  ASME; DR4-9 the keys A, G and R; DR4-10 export PDF and DXF: symbols on DIMENSION, notes on TEXT, opening in Preview, Acrobat, LibreCAD and
  AutoCAD/TrueView with no audit prompt; DR4-11 Linux and Windows: the symbols page's PDF SHA-256 equals the Mac's.
- [ ] **Step 1:** docs.
- [ ] **Step 2:** `swift test` on macOS (16 "Test run with" lines, no "recorded an issue" or "failed after"); `XP_TRACK=dr-4 IMAGE=metalcreator-linux:dr-4
  scripts/linux-test.sh test` (16 lines; afterwards remove only this run's Docker volume and image); `swiftlint lint --strict` 0.
- [ ] **Step 3: Commit** "Docs: DR-4 GD&T and manufacturing symbols".
