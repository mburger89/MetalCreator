# DR-2: Dimensions and notes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Associative annotation on drawing sheets: linear (horizontal, vertical, aligned), baseline, chain, ordinate, radius, diameter,
angle and chamfer dimensions and hole callouts (with counterbores and countersinks) measured from the model's exact geometry, held to
the part by `DrawingAnchorResolver` and never re-attached by a guess, with ISO 2768 / ASME general tolerances, ±, deviations, limits,
reference, basic and ISO 286 fits, centre marks and centre lines, notes with leaders, drawn in ISO 129 or ASME Y14.5 style by one
placement rule that the screen, the PDF and the DXF share, saved as file format 18.

**Architecture:** Everything new is portable Swift over what the kernel already gives: `Topology` (tags, `EdgeInfo.curve`'s exact lines and
circles, `FaceInfo`'s cylinder axis and radius) and DR-1's `Projection2D`, whose every line names its source edge or face. No kernel call
and no shim change. `CreatorDrawing` gains the saved annotation model, the tolerance tables, the anchor resolver, the measurer, the hole
reader, the label and number formatting and a sheet-millimetre layout; `SheetComposer` appends each annotation to the one `SheetPicture`
DR-1 already draws on screen and writes to PDF and DXF, so the three cannot disagree. A lost annotation is drawn from its last good
figure with "?" and listed; the last good figure is written into the file only when it is saved. `CreatorDrawingEditor` gains the tools,
selection, dragging and inspector pages; the app wires units, saving, group renaming and export warnings.

**Tech Stack:** Swift 6.4, Swift Testing, MetalUI (`Path` fills, `rotationEffect`, `TextEditor`, `Picker`, `Toggle`, C7 gestures, C9 key
regions). No new OpenCascade code.

**Spec:** `docs/superpowers/specs/2026-11-24-drawings-design.md`. Read it whole; build §DR-2 and what §Model, §Drawing mode, §Export,
§Constraints and "Decisions after the builder check" say about annotation (decisions 1 to 4 in full, and the smaller call on a lost
dimension's last good value). DR-1's plan, `docs/superpowers/plans/2026-11-24-dr-1-sheets-views-pdf.md`, holds the rulings R1 to R28 this
plan builds on; CLAUDE.md's "Drawings, DR-1" paragraph says what exists. Sections, details, auxiliary views, GD&T, datum symbols, surface
texture, balloons, parts lists, revisions and MCP tools are DR-3 to DR-5: leave them out.

## Global Constraints

- **Worktree and branch.** `/Users/maxburger/Developer/MetalCreator-dr2`, branch `dr-2`. Never touch `../MetalUI` (read it, never edit it).
  A MetalUI shortcoming is logged in `docs/metalui-gaps.md` (a `DR-2-x` entry with the use case and the stopgap) and reported, never worked
  around here. Never run `git stash` in any form.
- **No kernel or shim change.** Dimensions measure `EdgeInfo.curve` (`EdgeCurve.line`, `.circle`) and `FaceInfo` (`radius`, `axisPoint`,
  `normal`, `kind`) projected by `ProjectionFrame.place`, never a projected polyline and never a `ProjectedCurve` (decision: "from the model's
  exact geometry"). The projected lines are used only to find what was clicked, to place leaders and to draw automatic centre marks.
- **Module rules** (DR-1's, unchanged): `CreatorDrawing` depends on `CreatorGeometry` and `CreatorKernel` only; `CreatorDrawingEditor` on
  `CreatorDrawing`, `CreatorKernel`, `CreatorGeometry`, `CreatorStyle` and MetalUI only. No CoreGraphics, CoreText, ImageIO or Metal in either.
  Nothing iterates a dictionary where order reaches output (pictures, PDF and DXF bytes, lists, warnings, saved order). A file that imports
  both MetalUI and CreatorGeometry writes `CreatorGeometry.Angle` / `MetalUI.Angle`; one that imports CreatorKernel and CreatorSketch qualifies
  `ProjectedCurve`, `ProjectionSource`, `MeasuredDimension` and `DimensionKind`.
- **Units.** Model geometry and figures are model millimetres in the view plane (R5 of DR-1: `frame.place`); placements, layout and pictures are
  sheet millimetres, origin bottom left, y up. A view at scale s maps a model-plane point m to `m × s + (centre − bounds.center × s)`
  (`ViewMapping`, Task 7). Angles are radians in data, degrees only in text.
- **Constants** (line weights, arrow sizes, gaps, lettering heights, dashes) are `DrawingStyle` / `AnnotationStyle` members, never literals at
  a call site.
- **Text is bytes-identical everywhere.** Numbers in labels come from integers (`DimensionNumber`, R9), never a platform formatter or the
  locale; the minus sign is ASCII "-" (U+2212 is outside WinAnsi and would print "?"); the multiplication sign is "×" (WinAnsi 0xD7) in ISO and
  "X" in ASME. PDF and DXF bytes stay identical on every platform (DR-1 R23): one digest per fixture.
- **File format 18** (`GraphFile.currentFormatVersion`): files of format 1 to 17 open unchanged and are written as 18.
- **Undo names** are fixed strings with no numbers and no typed text (`DrawingStepName`, R19).
- **Messages** are full sentences in the app's voice; counts through `formatted(.number.locale(.messages))` (CreatorDrawing has no
  `Int.display`).
- **Tests and checks.** Swift Testing only; OCCT tests gated `#if canImport(CreatorOCCT)`; never block a pool thread in a test (`HookGate` or
  a suspending kernel hook); `swiftlint lint --strict` over the tree reports 0; after DR-2, macOS and Linux each print **16** "Test run with"
  lines (no new test target) and never "recorded an issue" or "failed after".
- **Commit trailer** (every commit):
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_0195iKYokoi2BJLpboZBys76`.

## Rulings (where this plan narrows the spec; each says why and what it costs if wrong)

- **R1. A layout of our own, beside the viewport's.** `DimensionLayout` / `DimensionStyle` live in `CreatorViewport` (internal, screen points,
  ANSI only, a `TextMeasure` from the screen font, a camera). `CreatorDrawing` cannot depend on `CreatorViewport`, and the drawing must lay
  text out by Helvetica's metrics, in sheet millimetres, in two standards. So DR-2 writes `SheetDimensionLayout` in `CreatorDrawing` and leaves
  the viewport's alone. "One placement rule per standard shared by screen, PDF and DXF" holds because all three draw the composed
  `SheetPicture`. Cost: two dimension layouts in the codebase; the viewport's is for live model dimensions and stays ANSI.
- **R2. The annotation model.** A sheet holds `annotations: [DrawingAnnotation]`, sorted by `AnnotationID` in memory and in the file, beside its
  views. An annotation has an `id`, a `view: ViewID?` (nil: free on the sheet; every anchor of an annotation is in its one view, so the view
  is on the annotation, not on each anchor as §Model sketches it), a `kind` and `last: LastGood?` (R15). Kinds: `dimension`, `holeCallout`,
  `centreMark`, `centreLine`, `note`. Deleting a view deletes its annotations in the same step; duplicating a sheet copies them with new IDs
  pointing at the copied views. A note made inside a view's frame belongs to that view, elsewhere to the sheet. Cost: none.
- **R3. Anchors** (`AnchorTarget`, saved): `edge(EdgePick)` (a line or circle edge, or a run of pieces), `corner(EdgePick, EdgePick)` (the one
  point where two named edges meet: "a vertex as an edge end", named by its neighbour so an edge whose direction flips after a rebuild
  can't swap its ends), `centre(EdgePick)` (a circular edge's centre), `outline(FacePick, side: Vector2)` (a cylinder's silhouette on the side
  the unit sheet vector `side` points to), `axis(FacePick)` (a cylinder's axis, for centre lines and the diameter of a cylinder seen side on)
  and `point(Vector2)` (a leader's free end, sheet mm relative to the view's centre, or absolute for a sheet note). At pick time an edge is
  accepted only when its key (`Topology.key(of:)`) names edges forming exactly one run (`Topology.runCount == 1`), recorded as
  `EdgePick(key:, matchCount:, runCount: matches > 1 ? 1 : nil)`, and not `touchesUnnamedFace`; a face pick (`Topology.facePick(for:)`) is
  accepted only when `faces(matching:)` gives exactly that face. Refusals in R5.
- **R4. Resolving** (decision 2; `DrawingAnchorResolver.resolve(_:in:frame:)`, never through `Topology.resolution`, whose operand keys and
  nearest-count fallbacks guess):
  - edge: `matches = topology.edges(matching: key)`. One match: **held**. Several forming one run (`Topology.runCount(matches) == 1` and the
    pick's `runCount ?? matchCount` was 1): **held, measuring the run** (a line run is the segment between its two extreme ends; a circle run
    keeps its centre, axis and radius, its sweep the sum). Several forming more than one run (a run count that changed, or a key that
    now fits separate edges): lost `.several(n)`, n the number of runs. None: `key.narrowed`'s matches; exactly one is held, more is `.several(n)`,
    none is `.missing`. `EdgeKey.operandKeys` is never tried.
  - corner: both edges held, and exactly one end of the first (`EdgeCurve.ends`, over the run's pieces) lies within `Topology.runJoinTolerance`
    (1e-4 mm) of an end of the second; else `.cornerGone`.
  - centre: the edge held and a circle (`.notLineOrCircle` otherwise).
  - outline and axis: `faces(matching:)` exactly one, or `Topology.resolution(of:)` narrowed with `isAmbiguous == false` and one face; a
    narrowed ambiguous answer is `.guessed`, none `.missing`; the face must have `kind == .cylinder`, `radius`, `axisPoint` and `normal`
    (`.notCylinder`). An outline's side: with the axis projected to the view and turned +90° as p, `|p · side| ≥ 0.5` picks the sign of
    `p · side`; under 0.5 is `.outlineTurned`.
  - An edge whose `curve` is nil can be held (a leader may point at it) but no dimension measures it: `.notLineOrCircle`.
  - Lost reasons (`LostReason.sentence`, exact):

    | Case | Sentence |
    |---|---|
    | `missing` | What it was attached to is no longer in the part. |
    | `several(n)` | What it was attached to now fits N edges, and a dimension never guesses which. |
    | `guessed` | Its face can now only be found by guessing, and a dimension never guesses. |
    | `notLineOrCircle` | What it measured is no longer a straight line or a circle. |
    | `cornerGone` | The two edges that met at its corner no longer meet at one point. |
    | `notCylinder` | The face it was attached to is no longer a cylinder. |
    | `outlineTurned` | The cylinder it was attached to has turned, so the side of its outline can't be told. |
    | `foreshortened` | What it measures now runs at an angle to the view, so its size here would be foreshortened. |
    | `notAHole` | The hole it called out is no longer a plain, counterbored or countersunk hole. |
    | `sourceRemoved` | The Output this view showed was removed. (= `DrawingProjector.removedSentence`) |
    | `viewFailed(message)` | the view's own failure sentence |
    | `noPart` | This view has no part to measure. |
    | `refused(sentence)` | the refusal's own sentence (a fit whose size has left ISO 286's range) |

  A baseline, chain or ordinate dimension is one annotation: if any of its anchors is lost, the whole annotation is lost (every value shows
  "?"). Cost: one lost point greys a whole chain; the alternative, part-lost chains, is a layout problem with no standard answer.
- **R5. No foreshortened number** (decision 4). With d the view direction and tolerance 1e-9 relative:
  - a line edge (any dimension measuring it or taking its ends): `|(end − start) · d| ≤ 1e-9 × |end − start|`;
  - a circle (radius, diameter, centre, hole callout, centre mark): `|axis · d| ≥ 1 − 1e-9`;
  - a cylinder outline or axis: `|axis · d| ≤ 1e-9`;
  - an aligned dimension between two points: the 3D segment between them obeys the line rule; horizontal and vertical dimensions between
    points measure along the view's right or up and are always true;
  - an angle: both lines obey the line rule.
  Refused at the pick (`DrawingRefusal.sentence`, exact):
  - a line: "This edge isn't square to the view, so its length here would be foreshortened. Dimension it in a view that sees it face on, or in
    an auxiliary view." (decision 4's sentence);
  - a circle: "This circle isn't seen face on, so its size here would be foreshortened. Dimension it in a view that looks along its axis.";
  - a cylinder outline: "This cylinder isn't seen side on, so its size here would be foreshortened.";
  - an angle: "These edges aren't both square to the view, so the angle here would be distorted.";
  - any dimension tool in an isometric view (`ViewOrientation.isIsometric`): "Isometric views take notes and leaders, not dimensions.".
  Other pick refusals: "This edge has no lasting name, so a dimension can't hold on to it." (unnamed or ordinals needed), "This line's edge
  shares its name with other edges, so a dimension can't hold on to it." (key forms more than one run), "This line is a free curve;
  dimensions attach to a part's edges." (`.curve` source), "This edge isn't a straight line or a circle, so it can't be dimensioned here.",
  "Only a cylinder's outline can be dimensioned here.", "This corner can't be named; dimension the edge instead.". A held dimension whose
  geometry a model edit tilts out of the plane is lost `.foreshortened`. Cost: a horizontal dimension of a slanted-in-depth edge is refused
  even though its x-extent would read true; pick its two corners instead.
- **R6. What each kind measures** (`DrawingMeasure`, model-plane mm; `AnnotationFigure` is what the layout draws):

  | Kind | Anchors | Value(s) | Figure |
  |---|---|---|---|
  | `linear(.horizontal/.vertical)` | two of: corner, centre, a line perpendicular to the direction (a line contributes its end nearer the dimension line); or one line | the distance along (1, 0) or (0, 1) | `linear(points: [a, b], direction:)` |
  | `linear(.aligned)` | one line (its length); two points (their distance); a point and a line, or two parallel lines (perpendicular distance; non-parallel lines are an angle) | the distance | `linear` with direction along the measure |
  | `baseline(dir)`, `chain(dir)` (`dir` horizontal or vertical only) | n ≥ 3 points or perpendicular lines, the first the base | n − 1 distances: from the base (baseline) or from the previous (chain) | `linear(points: all n, direction:)` |
  | `ordinate(axis)` | n ≥ 2, the first the origin | n − 1 coordinates from the origin along x (`.horizontal`) or y | `ordinate(origin:points:direction:)` |
  | `radius` / `diameter` | `edge` of a circle | radius / 2 × radius | `radial(center:radius:isDiameter:)` |
  | `diameter` | `axis` of a cylinder seen side on | 2 × radius | `linear` between the two outlines across the axis |
  | `angle` | two non-parallel lines | the angle of the sector the placement's direction lies in (0…π) | `angle(vertex:first:second:)`, each a line's two ends |
  | `chamfer` | the chamfer line, then a reference line | leg = chamfer length × cos θ along the reference, θ the angle between them | `chamfer(start:end:)` |

  The smart Dimension tool's inference (`DimensionInference`): one line horizontal in the view (|Δy| ≤ 1e-9 × length) gives `linear(.horizontal)`,
  vertical gives `.vertical`, slanted `.aligned`; a full circle `diameter`, an arc `radius`; a cylinder outline `diameter` of its `axis`; two
  points, a point and a perpendicular line, or two lines perpendicular to one axis give horizontal or vertical by the placing click
  (dx_out, dy_out = how far the click lies outside the anchors' x and y spans: horizontal when dy_out ≥ dx_out) and `.aligned` when ⇧ is held on
  the placing click; a point and a slanted line, or two parallel slanted lines, `.aligned`; two non-parallel lines an `angle`. A circle given
  with another pick contributes its centre. Baseline, Chain and Ordinate take their direction from the placing click by the same dx_out/dy_out
  rule (Ordinate: a click above or below the origin measures x); a line pick there must be perpendicular to that direction, else "A line in a
  baseline, chain or ordinate dimension must cross the direction it measures.". The kind and direction can be changed afterwards in the
  inspector. Cost: one table.
- **R7. Placement** (decision 1: annotations move with their view). Dimensions store `DimensionPlacement { offset, angle, textShift }` in sheet
  mm and radians, relative to the measured geometry, so a dimension stays the same distance from its edge when the part grows:
  - linear, baseline, chain: with d the measuring direction and n = d turned +90°, the (first) dimension line is the line
    `{x : x · n = a · n + offset}` (a the first feature point on the sheet); baseline line k (k = 1…n−1) sits at `offset + (k − 1) ×
    stackSpacing × sign(offset)`; `textShift` is the text centre's distance along d from the middle of its feet, `nil` for automatic (R8);
  - ordinate: every leader ends on the line `x · n = origin · n + offset`;
  - radius, diameter, hole callout, chamfer: `angle` is the leader's direction from the centre (or the chamfer's midpoint) on the sheet,
    `offset` how far the text sits beyond the circle (or the midpoint);
  - angle: `offset` is the arc's radius, `angle` the direction from the vertex that picks the sector;
  - notes: `position` (the block's top-left), relative to the view's resolved centre (`ViewPlacement.centers`), or absolute on the sheet.
  A drag adds the pointer's motion to `offset` (its component along n) and, when the press was on the label, to `textShift` (along d, starting
  from the automatic shift's centre); radial kinds and callouts take `angle` and `offset` from the pointer; a note moves its `position`.
- **R8. The placement rule** (`SheetDimensionLayout`, sheet mm; `AnnotationStyle.of(standard)`):

  | Constant | ISO 129 | ASME Y14.5 |
  |---|---|---|
  | `arrowLength` (filled, width = length / 3) | 2.5 | 3.0 |
  | `extensionGap` (feature to extension line) | 0 | 1.5 |
  | `extensionOvershoot` (past the dimension line) | 2.0 | 3.0 |
  | `textLift` (baseline above the dimension line) | 1.0 | — |
  | `textGap` (text to a line it is clear of) | 1.0 | 1.5 |
  | `stackSpacing` (baseline dimensions) | 8.0 | 10.0 |
  | `shoulder` (leader's horizontal end) | 3.0 | 3.0 |
  | `centreOvershoot` (centre lines past the circle or the cylinder) | 2.0 | 3.0 |
  | `smallCentre` (a centre mark on a circle of smaller sheet radius is a solid cross) | 3.0 | 3.0 |
  | `toleranceScale` (stacked tolerance text height / h) | 0.75 | 1.0 |
  | `linePitch` (note line spacing / h) | 1.6 | 1.6 |
  | `boxPadding` (basic dimension frame) | 1.0 | 1.0 |

  h is `DrawingStyle.notesHeight(for:)` (2.5 mm on A3 and A4, 3.5 mm on A0 to A2; ASME 3 mm). Dimension, extension and leader lines are thin,
  on `DrawingLayer.dimension`; dimension text and callout symbols are on `.dimension` too; notes' text is on `.text`.
  **Text.** ISO: parallel to the dimension line, its baseline `textLift` above it on the side that reads from the bottom or the right (the
  line's angle folded into (−90°, 90°]). ASME: unidirectional (horizontal), centred on the dimension line in a break `textGap` wider than the
  text each side.
  **The rule** for a linear dimension of inner length L (between the extension lines, sheet mm) and label width w:
  - text inside when `w + 2 × textGap ≤ L` (ISO) or `w + 2 × textGap + 2 × arrowLength ≤ L` (ASME);
  - arrows inside when `L ≥ 2 × arrowLength + 1`, else each arrowhead sits outside its extension line pointing in, with a dimension-line tail
    `arrowLength` long beyond it;
  - automatic text outside sits beyond the extension line on the +d side, its near edge `textGap` (plus `arrowLength` when the arrows are
    outside) past it, and the dimension line runs on under it (ISO) or up to it (ASME);
  - a `textShift` puts the text centre there, and the dimension line runs on to reach it when it lies past an extension line.
  Radius: a line from the centre through the arc point at `angle`, on by `offset` when positive, one arrowhead at the arc pointing out; ISO text
  along the outer part, ASME horizontal at the end on a shoulder. Diameter of a face-on circle: ISO draws a line through the centre at `angle`
  with both arrowheads inside pointing at the circle when `2r ≥ w + 2 × arrowLength + 2`, else (and always in ASME) a leader from outside
  with its arrowhead at the circle pointing at the centre, text on a shoulder. Angle: an arc of radius `offset` about the vertex between the
  sector's rays, extension lines from the lines' nearer ends when the arc lies beyond them, arrows at the arc's ends (outside when the arc is
  shorter than `2 × arrowLength + 1`), ISO text tangent at the arc's middle, ASME horizontal in a break. Ordinate: per feature a leader from
  the feature (`extensionGap` off) to the ordinate line, text at its end aligned with the leader, the origin's text "0". Chamfer, hole callout:
  a leader at `angle`, arrowhead on the edge or circle, horizontal text on a shoulder on the side the leader points to. Cost: no jogged ordinate
  leaders and no automatic de-cluttering (parked).
- **R9. Numbers** (`DimensionNumber`, from integers; decision 3). Lengths are the document's unit (`DocumentUnits`), rounded half away from
  zero to `precision ?? units.fractionDigits` decimals; millimetres drop trailing zeros (25, 25.4), inches keep them (Y14.5: 1.000). ASME in
  inches drops the leading zero (.250); everything else keeps it (0.25). The decimal sign is `DrawingSettings.decimalSign` in ISO (point by
  default, comma allowed) and always a point in ASME. Angles are degrees, up to `precision ?? 1` decimals, trailing zeros dropped, then "°".
  No unit is written after a value (ISO 129, Y14.5). "-0" is never written.
- **R10. Tolerances and their text** (`DimensionLabel`; values typed in the document's unit or degrees, stored in mm or radians):

  | Tolerance | Text (mm, ISO) | Notes |
  |---|---|---|
  | `general` | 25 | nothing written (applied silently); the inspector shows the value it gets |
  | `symmetric(0.1)` | 25 ±0.1 | inches: the tolerance takes at least the value's decimals (1.000 ±.005) |
  | `deviation(+0.1, −0.2)` | 25 then stacked +0.1 over -0.2 | stacked at `toleranceScale × h`; a zero is "0" in mm and "+.000"/"-.000" with the value's decimals in inches; the two padded to the same decimals |
  | `limits(+0.1, −0.1)` | stacked 25.1 over 24.9 | the limit sizes, upper first, same decimals |
  | `reference` | (25) | |
  | `basic` | 25 in a thin box | `boxPadding` round the text |
  | `fit(.hole(.H, 7), showsDeviations: true)` | Ø20 H7 (+0.021/0) | the deviations in mm to their own decimals (zero "0"); in inches converted, 4 decimals (+.0008/0) |

  Fits apply to sizes only (a linear, aligned or diameter dimension): anything else is refused "Fits apply to sizes: a diameter or a distance
  between two faces.". The general tolerance is structured (`GeneralTolerance`): ISO is an ISO 2768-1 class f, m, c or v with an optional
  ISO 2768-2 class H, K or L ("ISO 2768-mK", the default); ASME is a table by number of decimals typed by the user, in one unit, defaults
  `X ±0.5, X.X ±0.1, X.XX ±0.05` (rows of 0, 1, 2 places, mm) and `.X ±.03, .XX ±.010, .XXX ±.005` (rows of 1, 2, 3 places, in), written in the
  title block as "±0.5, ±0.1, ±0.05 mm" and "±.03, ±.010, ±.005 in". A format-17 string decodes: "ISO 2768-" followed by a class letter and an
  optional geometric letter to `.iso2768`, either ASME default string to its table, anything else to `.text(original)`, shown as typed. The
  title block's tolerance field becomes automatic (`TitleBlockKey.tolerance.isTyped == false`). The inspector's "General" row: ISO 2768-1 Table
  1 for lengths and diameters, Table 2 for radii and chamfer heights, the class's name only for angles; ASME the row with the dimension's
  decimals, "—" when none.
- **R11. ISO 286** (`ISO286`; nominal sizes over 0 up to 500 mm, ranges "over a up to and including b"; grades IT5 to IT11; µm):

  Ranges: (0,3] (3,6] (6,10] (10,18] (18,30] (30,50] (50,80] (80,120] (120,180] (180,250] (250,315] (315,400] (400,500].

  | | values per range |
  |---|---|
  | IT4 (for Δ only) | 3 4 4 5 6 7 8 10 12 14 16 18 20 |
  | IT5 | 4 5 6 8 9 11 13 15 18 20 23 25 27 |
  | IT6 | 6 8 9 11 13 16 19 22 25 29 32 36 40 |
  | IT7 | 10 12 15 18 21 25 30 35 40 46 52 57 63 |
  | IT8 | 14 18 22 27 33 39 46 54 63 72 81 89 97 |
  | IT9 | 25 30 36 43 52 62 74 87 100 115 130 140 155 |
  | IT10 | 40 48 58 70 84 100 120 140 160 185 210 230 250 |
  | IT11 | 60 75 90 110 130 160 190 220 250 290 320 360 400 |
  | f es | −6 −10 −13 −16 −20 −25 −30 −36 −43 −50 −56 −62 −68 |
  | g es | −2 −4 −5 −6 −7 −9 −10 −12 −14 −15 −17 −18 −20 |
  | k ei (IT5–IT7; 0 for IT8–IT11) | 0 1 1 1 2 2 2 3 3 4 4 4 5 |
  | n ei | 4 8 10 12 15 17 20 23 27 31 34 37 40 |
  | p ei | 6 12 15 18 22 26 32 37 43 50 56 62 68 |
  | s ei | 14 19 23 28 35 43, then (50,65] 53, (65,80] 59, (80,100] 71, (100,120] 79, (120,140] 92, (140,160] 100, (160,180] 108, (180,200] 122, (200,225] 130, (225,250] 140, (250,280] 158, (280,315] 170, (315,355] 190, (355,400] 208, (400,450] 232, (450,500] 252 |

  Shafts: h es = 0; f, g: ei = es − IT; k, n, p, s: es = ei + IT; js: ±IT/2 exactly (ISO 286-1:2010; half micrometres kept: ±10.5 µm, so
  "±0.0105"). Holes (Δ = ITn − IT(n−1), used only above 3 mm): F, G: EI = −es of f, g; H: EI = 0; JS: ±IT/2; ES = EI + IT and EI = ES − IT.
  K: ES = −ei(k) + Δ for grades ≤ 8, 0 above; N: ES = −ei(n) + Δ for grades ≤ 8, 0 above; P: ES = −ei(p) + Δ for grades ≤ 7, −ei(p) above;
  in (0,3] K's ES is 0, N's −4 and P's −6 for every grade. Out of range: "ISO 286 fits are given here for sizes over 0 up to 500 mm.", grade:
  "ISO 286 grades here run from IT5 to IT11.". The implementer checks the tables against a published ISO 286-2 table and reports any
  disagreement rather than changing a value silently. Cost: sizes over 500 mm and grades outside 5–11 are refused (parked).
- **R12. Hole callouts** (`HoleReader`, over `Topology` only). From the picked face-on circle edge the reader first walks out to the mouth: while
  the circle's non-wall face is a plane perpendicular to the axis bordered by a larger coaxial circle that is a coaxial cylinder's or cone's
  edge, step to that larger circle. Then it reads inward along the axis (coaxial: centre within 1e-6 mm of the axis line, axis parallel within
  1e-9): an entry cone is a countersink (diameter 2 × its outer circle's radius, angle 2 × atan((R − r) / h)); an entry cylinder followed by a
  plane annulus and a smaller coaxial cylinder is a counterbore (diameter, depth = its axial length from the entry); then the hole's cylinder:
  its far end met by a plane disc (no edge but that circle) or a cone ending at an apex or a disc is blind, depth from the plane where the hole's
  own cylinder starts (the counterbore floor, or the entry for a plain or countersunk hole) to its far circle, the drill point excluded;
  anything else at the far end is THRU. Any other stack: "This circle isn't the mouth of a plain, counterbored or countersunk hole." (at the
  pick) or lost `.notAHole`. Text (both standards; symbols are `DrawingSymbols` strokes, never glyphs; `LabelSymbol.depth` ↧, `.counterbore` ⌴,
  `.countersink` ⌵, each a box h wide with 0.3h either side): "Ø6 THRU" or "Ø6 ↧10" on the first line, then "⌴Ø11 ↧6" or "⌵Ø12 × 90°" (ASME
  "⌵Ø12 X 90°"). A count prefix ("4×") and tolerances in callouts are parked.
- **R13. Centre marks and centre lines.** Automatic centre marks (`DrawingView.showsCentreMarks`, default on, also for DR-1 files) for every
  visible projected full circle (|sweep| ≥ 2π − 1e-9) sourced to an edge; concentric circles (centres within 1e-6 model mm) get one mark sized
  by the largest. A mark is two thin lines through the centre on `.center`, reaching `radius × scale + centreOvershoot` each way, drawn with
  the `.centre` pattern, or solid when the sheet radius is under `smallCentre`. The Centre Mark tool adds the same mark as an annotation on any
  circle edge (an arc, or a circle whose automatic mark is off); the Centre Line tool adds a chain line along a side-on cylinder's axis
  (`axis(FacePick)`), from the axial extremes of the face's circular edges, `centreOvershoot` past each. The `.centre` pattern: ISO long dash
  6, gap 0.75, dot 0.25 (drawn as a 0.25 mm dash so it shows with butt caps), gap 0.75; ASME long 19, gap 1.5, short 3, gap 1.5. The DXF's
  CENTER linetype takes the standard's (ISO [6, −0.75, 0, −0.75], ASME [19, −1.5, 3, −1.5]).
- **R14. Notes and leaders.** A note's text is typed in the inspector (multi-line, one `SheetText` per line, `linePitch × h` apart, top line's
  cap at `position`), "Note" when made; an empty text is refused "A note needs some text; delete it instead.". A leader (`LeaderEnd`:
  `target`, `hint: Vector2` model-plane, `lastPoint` via R15) runs from the block's nearer side, at the first line's middle, a `shoulder` long,
  then straight to its end, a filled arrowhead there. An edge target ends at the point of the edge's projected lines nearest the hint; a corner
  or centre at that point; a free `point` where it was put. A note's leaders point into its own view: "A note's leaders point into one view."
  Notes' text goes through R13 of DR-1 (WinAnsi, "?" and one export warning per distinct text).
- **R15. A lost annotation** (the anti-goal and the smaller call). Every composed annotation reports `held` with its current `LastGood`
  (values, label lines, figure in model-plane mm, leader points) or `lost(reason)`. The editor remembers the newest held `LastGood` per
  annotation (`DrawingEditorModel.remembered`, in memory, never an edit). A lost annotation is drawn from `remembered[id] ?? annotation.last`:
  its figure through the view's current mapping, every value or the callout's first line with "?" appended ("25?", "Ø6 THRU?"), on screen in
  the warning colour (`isLost`), in files in ink; with neither, a lone "?" at the view frame's bottom-left corner. An annotation of a view with
  no projection (removed, never projected) is listed but not drawn. Lost annotations are listed in the sheet inspector ("Lost references", each
  row the label text and the reason, a click selects it) and in every export's warnings, one sentence per sheet: "On “Sheet 1”, 2 annotations
  lost what they were attached to and show “?”." (one: "On “Sheet 1”, 1 annotation lost what it was attached to and shows “?”."). Lost
  annotations never block an export. On save the app writes `remembered` into each annotation's `last` (`DrawingEditorModel.documentForSaving()`)
  through `DocumentModel.fileData(savingTo:drawings:)` and `didSave(to:drawings:)`: no undo step, not an edit, the saved document not dirty.
  Re-attaching: with exactly one lost annotation selected, a click on a line of its view (within the hover tolerance) replaces its first lost
  anchor with that pick, validated as a fresh pick and of the same case (edge, corner, centre, outline or axis), else "Pick the same kind of
  thing the annotation lost: a line, a circle, a corner or a centre."; one step "Reattach Dimension".
- **R16. Picture primitives.** `SheetPicture` gains `fills: [SheetFill]` (closed polygons: arrowheads), `standard: DrawingStandard` (so the
  writers dash by the page's style: the DR-1 backlog's hard-coded ISO dashes), `annotationReports: [AnnotationID: AnnotationReport]` (lookup
  only), `lostAnnotations: [AnnotationID]` (sheet order) and `viewExtents: [ViewID: Rect2D]` (frame ∪ its annotations, for culling; hit
  testing keeps `viewFrames`). `SheetStroke` and `SheetText` gain `annotation: AnnotationID?` and `isLost: Bool`; `SheetStroke` gains
  `source: ProjectionSource?` (the projected line it draws); `SheetText` gains `angle: Double` (radians about its origin). `StrokePattern` gains
  `.centre`. PDF: a fill is `x y m … h f`; a text with an angle is `BT /F1 em Tf c s -s c x y Tm (…) Tj ET` (c, s exact 0 and ±1 for multiples of
  π/2); dashes by `DrawingStyle.of(page.standard)`. DXF: a fill is one `SOLID` per fan triangle (vertex 4 = vertex 3), a text angle is code 50
  in degrees, a `.centre` stroke off the CENTER layer carries linetype `CENTER`. Screen: fills are `Path` fills, rotated text is the DR-1
  per-glyph view under `rotationEffect` about its baseline origin; if a render test shows the baseline more than 0.5 pt off, gap `DR-2-a` is
  logged and reported.
- **R17. Tools and keys.** `DrawingTool` (toolbar order): Base View, Projected View, Dimension (D), Baseline, Chain, Ordinate, Chamfer, Hole
  Callout (H), Centre Mark (M), Centre Line (L), Note (N); the letters act over the sheet canvas with nothing focused (the DR-1 backlog's tool
  shortcuts), as F does. Picking: over a view, the candidate under the pointer is, in order, a face-on circle's centre within the hover
  tolerance (4 pt at the zoom), a line's end within it (a corner), then the nearest line; hover draws the line or a 1.5 mm ring at the point in
  the highlight colour. Dimension: clicks pick until the inference is complete (a circle or outline at once; a line, then either a second pick
  or a click on empty space; two points; two lines), and the next click on empty space places it; Baseline, Chain, Ordinate: picks until a click
  on empty space places; Chamfer: two lines, then a place; Hole Callout: a circle, then a place; Centre Mark and Centre Line: one pick commits;
  Note: a click places a note and selects it. While picking, a preview of the annotation follows the pointer (`draftPicture`, never committed);
  Esc drops the picks, then the tool. A refused pick sets `refusal`. With a note selected, the inspector's "Add Leader" makes the next click a
  leader end (a line, a corner, a centre or empty space).
- **R18. Selection and moving.** In Select, a press hits annotations before views (an annotation's report frame grown by 1 mm); ⇧ adds; a drag
  moves the selected annotations by R7 (views selected too: the views move and carry their annotations), one coalesced step; arrows nudge
  selected annotations by 1 mm (⇧ 10) as R7's drag would. Delete removes them. `pointerCancelled()` (the DR-1 backlog) now restores the drag's
  base document and reports `events.discarded(key)`, which the app turns into `DocumentModel.discardCoalescedStep(key:)`: a cancelled drag
  leaves no step, of views or annotations.
- **R19. Undo names** (`DrawingStepName`, added to `all`):

  | Editor method or gesture | Step |
  |---|---|
  | placing a Dimension, Baseline, Chain, Ordinate or Chamfer | Add Dimension |
  | placing a Hole Callout / Centre Mark / Centre Line / Note | Add Hole Callout / Add Centre Mark / Add Centre Line / Add Note |
  | a leader end click / `removeLeader(_:of:)` | Add Leader / Remove Leader |
  | a drag or nudge of annotations only: all dimensions and callouts / all notes / mixed or centre marks | Move Dimension / Move Note / Move Annotations |
  | `deleteSelection()` with views selected / only dimensions and callouts / only notes / otherwise | Delete View / Delete Dimension / Delete Note / Delete Annotations |
  | `setDimensionKind(_:of:)`, `setPrecision(_:of:)`, `setPrefix(_:of:)`, `setSuffix(_:of:)` | Change Dimension |
  | `setTolerance(_:of:)` | Change Tolerance |
  | `setNoteText(_:of:)` | Edit Note |
  | a re-attaching click | Reattach Dimension |
  | `setGeneralTolerance(_:)` | Edit Title Block |
  | `setDecimalSign(_:)` | Change Number Format |
  | `setShowsCentreMarks(_:of:)` | Change View |

  A setter whose value equals the current one commits nothing.
- **R20. Inspector.** One annotation selected: a dimension shows its kind (Horizontal / Vertical / Aligned for linear; Radius / Diameter for a
  circle), its value (with "?" and the reason when lost, and "Click a line to attach it again."), Precision (Document (n), 0 to 4), Tolerance
  (General, Symmetric, Deviation, Limits, Reference, Basic, Fit) with its fields (values typed in the document's unit through
  `DocumentUnits.parse`, degrees for angles; a bad number refused "A tolerance is a number, such as 0.1."), a fit's Hole / Shaft, letter, grade
  (IT5 to IT11) and "Show deviations", the "General" row (R10), Prefix and Suffix; a hole callout its lines and Prefix and Suffix; a note its text
  (`TextEditor`, committed on focus loss or ⌘↩ as a comment is) and leaders (Add Leader, a Remove per leader); centre marks and lines only
  Delete. Several selected: "N items selected" and Delete. The sheet page gains General tolerance (ISO: class menu and geometric menu; ASME:
  a field per row), Decimal sign (ISO only) and the Lost references list; a view's page gains "Centre marks".
- **R21. Group, Ungroup and Make Unique rename drawing anchors** (spec §Model; DR-1 parked it). `GroupScopes.renamingPicks` appends one
  `.setDrawings` with every anchor's tags renamed by the same table whenever the host graph is the top level and something changed, so a
  dimension on a regrouped feature stays held. Cost: none.
- **R22. Export.** Annotations are part of every picture, so the PDF and the DXF of the sheet carry them. DXF of a view at 1:1 stays geometry
  only; a new kind `dxfViewWithAnnotations` ("DXF of View at 1:1 with Annotations…" in File ▸ Export and the top bar's Export menu) adds the
  view's annotations mapped back to model mm (sheet ÷ scale, text heights ÷ scale), so geometry measures true and lettering keeps its size
  relative to the part. Lost annotations add R15's warning to the summary.
- **R23. File format 18.** The `drawings` key gains annotations, `DrawingView.showsCentreMarks`, a structured `DrawingSettings.generalTolerance`
  and `decimalSign`. A DR-1 build would drop annotations silently on its next save (its decoder ignores unknown keys) and would misread the new
  tolerance, so the version is bumped and an older build refuses the file. Enums with payloads are coded as keyed containers with a `type`
  string (never Swift's synthesized `_0` form), pinned by a JSON test.
- **R24. Performance.** Composing resolves every annotation of the sheet each time (a drag step included; DR-1 already recomposes per step).
  Benchmark rows `drawing-3` (composing the bracket's sheet with 30 dimensions) and `drawing-3-warm` (a dimension dragged, warm window CPU per
  frame, budget 16.67 ms) are recorded; caching resolutions by topology identity is parked unless `drawing-3` is over 4 ms.

**Backlog.** Pulled in from DR-1's parked items: `PDFWriter`'s hard-coded ISO dashes (R16: dashes by the page's standard, needed by
centre lines); `pointerCancelled` leaving a half-moved view (R18); tool shortcuts (R17); renaming drawing anchors in Group, Ungroup and Make
Unique (R21). **Stay parked:** `ProjectionFrame.make`'s near-parallel `up`; the `ProjectedCurve`/`ProjectionSource` name clash (worked around
by qualifying, Global Constraints); the shim's own polyline sampler, `.curve(index:piece:)` with piece > 0 and the in-flight OCCT cancel test;
`repairingAlignments` freeing too many views; `SheetSegment.transformed` on mirroring scales; the placeholder on FRAME; `PDFNumber.format`'s "0"
for non-finite values (labels have their own formatter); "The view was cancelled." not in the spec; mesh-count grouping untested; duplicate
sheet names and whitespace renames; every drag step recomposing the sheet (measured by `drawing-3`, R24); the "+" tab icon; `ScaleControl`'s
`@State`; the 1 pt stroke floor and Custom… scale tests; the late re-fit; `HLRBRep_PolyAlgo`, OCCT-hide cancel, font subsets, copy and paste
of views and annotations, tab reordering by drag, ANSI zone counts, hidden tangent lines, compressed streams, DXF text widths and a progress
sheet. **Parked by DR-2:** dual dimensioning (decision 3), isometric dimensioning (decision 4), jogged ordinate leaders and automatic
de-cluttering (R8), fits over 500 mm or outside IT5–IT11 (R11), hole counts and tolerances in callouts (R12), ellipse and B-spline edges'
dimensions (R5), part-lost chains (R4), in-canvas note editing, caching anchor resolution (R24).

## Review Focus

1. **A model edit under a dimension** (a chamfer added on the dimensioned edge, a rib that splits it, a width that tilts it, a feature
   regrouped). It must be held, held measuring the run, or lost with "?" and its reason, never re-attached to a neighbour. Task 4
   (`aSplitEdgeIsMeasuredAsItsRun`, `aChangedRunCountIsLost`, `operandKeysAreNeverTried`, `aTiltedEdgeIsForeshortened`), Task 13
   (`groupingKeepsADimensionHeld`), Task 14 (`aChamferOnTheEdgeLosesTheDimension`).
2. **An inch document in ASME, and a comma in ISO.** ".250", "1.000 ±.005", "+.000", "25,4", never "−" (U+2212) and never "0.250" in ASME
   inches, in the PDF bytes as on screen. Task 3 (`asmeInchesDropTheLeadingZero`, `theMinusIsAscii`, `aCommaInISO`), Task 6
   (`annotatedPageDigest`), Task 14 (`anInchDocumentRestylesItsNumbers`).
3. **Short dimensions and small circles.** A 2 mm gap at 1:1 flips the arrows and puts the text outside, clear of both extension lines, in both
   standards; a Ø3 circle's diameter goes on a leader. Task 7 (`aShortDimensionFlipsItsArrows`, `textOutsideClearsTheExtensionLines`,
   `aSmallCircleTakesALeader`).
4. **Saving while a dimension is lost, then reopening.** The save writes the last good value without an undo step or a dirty document; the
   reopened file shows "25?" from it in the warning colour, listed, and the PDF writes "25?" in ink. Task 11 (`documentForSavingWritesRemembered`),
   Task 14 (`savingWritesLastGoodValuesWithoutAnEdit`, `aReopenedLostDimensionShowsItsLastValue`).
5. **A drag that MetalUI cancels, and deleting a view under its dimensions.** No undo step is left by the cancelled drag; Delete View takes its
   annotations in the same step and undo brings both back. Task 11 (`aCancelledDragRestoresAndDiscards`, `deletingAViewDeletesItsAnnotations`),
   Task 14 (`aCancelledDragLeavesNoStep`).

---

### Task 1: The annotation model and file format 18

**Files:**
- Create in `Sources/CreatorDrawing/Model/`: `DrawingRefusal.swift`, `DecimalSign.swift`, `GeneralTolerance.swift`; in
  `Sources/CreatorDrawing/Model/Annotations/`: `AnnotationID.swift`, `DrawingAnnotation.swift`, `DrawingDimension.swift`,
  `DimensionTolerance.swift`, `AnchorTarget.swift`, `AnnotationFigure.swift`, `DrawingNote.swift`, `HoleCallout.swift`,
  `CentreAnnotations.swift`, `Annotations+Coding.swift`
- Modify: `Sources/CreatorDrawing/Model/DrawingSheet.swift`, `DrawingView.swift`, `DrawingSettings.swift`,
  `Sources/CreatorDrawing/Views/ViewPlacement.swift` (`removing` drops the view's annotations), `Sources/CreatorDrawing/Sheet/TitleBlockLayout.swift`
  (`.tolerance` automatic: `settings.generalTolerance.text`), `Sources/CreatorGraph/GraphFile.swift` (18), and to keep the editor compiling:
  `Sources/CreatorDrawingEditor/DrawingEditorModel+Inspector.swift` (`setTitleField(.tolerance, …)` now does nothing; `setStandard` compares
  `GeneralTolerance.standardDefault`), `Sources/CreatorDrawingEditor/Views/SheetInspector.swift` (`.tolerance` leaves `fields`)
- Test: `Tests/CreatorDrawingTests/AnnotationModelTests.swift`, `Tests/CreatorDrawingTests/GeneralToleranceModelTests.swift`,
  `Tests/CreatorGraphTests/DrawingsFileTests.swift` (additions), DR-1 tests that wrote the tolerance as a string (updated, not weakened)

**Interfaces:**
- Produces:
  - `public struct DrawingRefusal: Error, Hashable, Sendable { public var sentence: String }`.
  - `public enum DecimalSign: String, Codable, Sendable, CaseIterable { case point, comma }`.
  - `public enum ISO2768Class: String, Codable, Sendable, CaseIterable { case f, m, c, v }`, `public enum ISO2768GeometricClass: String, …
    { case H, K, L }`, `public struct ASMEToleranceRow: Hashable, Codable, Sendable { places: Int; text: String }`, `public struct
    ASMEToleranceTable: Hashable, Codable, Sendable { unit: LengthUnit; rows: [ASMEToleranceRow] }`, `public enum GeneralTolerance:
    Hashable, Codable, Sendable { case iso2768(ISO2768Class, ISO2768GeometricClass?); case asme(ASMEToleranceTable); case text(String) }`
    with `var text: String` ("ISO 2768-mK", "ISO 2768-m", "±0.5, ±0.1, ±0.05 mm", "±.03, ±.010, ±.005 in", the legacy text),
    `static func standardDefault(for: DrawingStandard, inches: Bool) -> GeneralTolerance` and `init(legacy: String, standard: DrawingStandard)`
    (R10's decoding).
  - `public struct AnnotationID` shaped like `ViewID` (bare UUID, `Comparable` by text).
  - `public enum LinearDirection: String, Codable { case horizontal, vertical, aligned }`, `public enum OrdinateAxis: String, Codable { case
    horizontal, vertical }`, `public enum DrawingDimensionKind: Hashable, Codable, Sendable { case linear(LinearDirection), baseline(LinearDirection),
    chain(LinearDirection), ordinate(OrdinateAxis), radius, diameter, angle, chamfer }`.
  - `public struct DimensionPlacement: Hashable, Codable, Sendable { offset: Double; angle: Double; textShift: Double? }` (R7).
  - `public enum HoleFitLetter: String, CaseIterable, Codable { case F, G, H, JS, K, N, P }`, `public enum ShaftFitLetter: String, … { case f, g, h,
    js, k, n, p, s }`, `public enum FitDesignation: Hashable, Codable, Sendable { case hole(HoleFitLetter, grade: Int); case shaft(ShaftFitLetter,
    grade: Int) }` with `var text: String` ("H7", "js6"), `public enum DimensionTolerance: Hashable, Codable, Sendable { case general;
    symmetric(Double); deviation(upper: Double, lower: Double); limits(upper: Double, lower: Double); reference; basic; fit(FitDesignation,
    showsDeviations: Bool) }` (mm or radians; a fit grade outside 5…11 decodes as `.general`).
  - `public enum AnchorTarget: Hashable, Codable, Sendable { case edge(EdgePick); corner(EdgePick, EdgePick); centre(EdgePick); outline(FacePick,
    side: Vector2); axis(FacePick); point(Vector2) }` with `var caseName: String` ("edge", "corner", …, used by R15's same-case check).
  - `public enum AnnotationFigure: Hashable, Codable, Sendable { case linear(points: [Vector2], direction: Vector2); ordinate(origin: Vector2,
    points: [Vector2], direction: Vector2); radial(center: Vector2, radius: Double, isDiameter: Bool); angle(vertex: Vector2, first: [Vector2],
    second: [Vector2]); chamfer(start: Vector2, end: Vector2); hole(center: Vector2, radius: Double); centreMark(center: Vector2, radius: Double);
    centreLine(start: Vector2, end: Vector2); leaders([Vector2]) }` (model-plane mm).
  - `public struct LastGood: Hashable, Codable, Sendable { values: [Double]; lines: [String]; figure: AnnotationFigure }`.
  - `public struct DrawingDimension: Hashable, Codable, Sendable { kind; anchors: [AnchorTarget]; placement; tolerance = .general; precision:
    Int?; prefix = ""; suffix = "" }`; `public struct HoleCallout { anchor: AnchorTarget; placement; prefix; suffix }`; `public struct CentreMark
    { anchor: AnchorTarget }`; `public struct CentreLine { anchor: AnchorTarget }`; `public struct LeaderEnd { target: AnchorTarget; hint: Vector2 }`;
    `public struct DrawingNote { text: String; position: Vector2; leaders: [LeaderEnd] }`.
  - `public enum AnnotationKind: Hashable, Codable, Sendable { case dimension(DrawingDimension), holeCallout(HoleCallout), centreMark(CentreMark),
    centreLine(CentreLine), note(DrawingNote) }`; `public struct DrawingAnnotation: Hashable, Codable, Sendable, Identifiable { id; view: ViewID?;
    kind; last: LastGood? }`.
  - `DrawingSheet`: `public private(set) var annotations: [DrawingAnnotation]` (sorted by id), `annotation(_:)`, `setAnnotation(_:)`,
    `removeAnnotation(_:)`, `annotations(of view: ViewID) -> [DrawingAnnotation]`; decoding drops an annotation whose `view` is not on the sheet;
    encoded only when non-empty. `DrawingView.showsCentreMarks: Bool` (default true; missing decodes true). `DrawingSettings.generalTolerance:
    GeneralTolerance`, `decimalSign: DecimalSign` (default `.point`, encoded only when `.comma`); a string `generalTolerance` decodes through
    `GeneralTolerance(legacy:standard:)`.
  - `TitleBlockKey.tolerance.isTyped == false`; `GraphFile.currentFormatVersion == 18`.

- [ ] **Step 1: Tests.**
  - `AnnotationModelTests`: `annotationsStaySortedById`; `everyKindRoundTrips` (one annotation of each kind with every anchor case and every
    tolerance case, encode then decode equal); `kindsAreCodedByType` (a horizontal dimension with one `.edge` anchor encodes to JSON whose
    `kind` object has `"type":"dimension"` and whose anchor has `"type":"edge"`, with no `"_0"` key anywhere); `aFitGradeOutOfRangeReadsGeneral`;
    `anAnnotationOfAMissingViewIsDropped`; `removingAViewRemovesItsAnnotations` (`ViewPlacement.removing`); `freeAnnotationsSurviveViewRemoval`;
    `centreMarksDefaultOnForOldViews`; `noAnnotationsKeyWhenEmpty`.
  - `GeneralToleranceModelTests`: `legacyISOStringsParse` ("ISO 2768-mK" → `.iso2768(.m, .K)`, "ISO 2768-f" → `.iso2768(.f, nil)`);
    `legacyASMEDefaultsParse` (both default strings to their tables); `anythingElseIsKeptAsText`; `textsMatchTheTitleBlock` (R10's four
    strings); `theToleranceFieldIsAutomatic`; `decimalSignDefaultsToPoint`.
  - `DrawingsFileTests` additions: `aFormat17FileOpensAndIsWrittenAs18` (a format-17 fixture with `"generalTolerance":"ISO 2768-mK"` reads, its
    tolerance structured, and writes `formatVersion` 18); `aNewerFileIsRefused` (19); `annotationsRoundTripThroughTheGraphFile`.
- [ ] **Step 2: Run** `swift test --filter 'AnnotationModelTests|GeneralToleranceModelTests|DrawingsFileTests'`; compile failure.
- [ ] **Step 3: Implement.** Codable by hand where R23 says so; keep every DR-1 test's meaning (a DR-1 test that typed the tolerance through
  `setTitleField(.tolerance, …)` now asserts it commits nothing; Task 11 adds `setGeneralTolerance`).
- [ ] **Step 4: Run** the filter, then `swift test --filter CreatorDrawingTests`, `--filter CreatorDrawingEditorTests`, `--filter CreatorGraphTests`; pass.
- [ ] **Step 5: Commit** "Drawings: the annotation model and file format 18".

### Task 2: Tolerance tables (ISO 286, ISO 2768, the ASME table)

**Files:**
- Create: `Sources/CreatorDrawing/Tolerances/ISO286.swift`, `Sources/CreatorDrawing/Tolerances/ISO286Tables.swift`,
  `Sources/CreatorDrawing/Tolerances/ISO2768.swift`, `Sources/CreatorDrawing/Tolerances/GeneralTolerance+Values.swift`
- Test: `Tests/CreatorDrawingTests/ISO286Tests.swift`, `Tests/CreatorDrawingTests/ISO2768Tests.swift`

**Interfaces:**
- Consumes: Task 1's `FitDesignation`, `GeneralTolerance`, `DrawingRefusal`.
- Produces:
  - `public struct FitLimits: Hashable, Sendable { public var upper: Double; public var lower: Double }` (deviations in mm).
  - `ISO286.standardTolerance(grade: Int, size: Double) throws(DrawingRefusal) -> Double` (mm) and `ISO286.limits(of: FitDesignation, size:
    Double) throws(DrawingRefusal) -> FitLimits` (R11's rules and sentences).
  - `ISO2768.linear(_ size: Double, class: ISO2768Class) -> Double?` and `ISO2768.brokenEdge(_ size: Double, class: ISO2768Class) -> Double?`
    (nil outside the table: under 0.5 mm, v below 3 mm, f above 2000 mm, over 4000 mm).
  - `public enum GeneralToleranceUse: Sendable { case length, brokenEdge, angle }`; `GeneralTolerance.value(for size: Double, use:
    GeneralToleranceUse, places: Int) -> Double?` (mm; ISO by table, ASME the row with `places`, parsed with `Double(text)` in the table's unit,
    `.text` and angles nil) and `GeneralTolerance.summary(for:use:places:) -> String?` (the inspector's info text: "±0.2 (ISO 2768-m)",
    "ISO 2768-m" for angles, nil when none).
- ISO 2768-1 Table 1 (±mm; ranges [0.5,3] (3,6] (6,30] (30,120] (120,400] (400,1000] (1000,2000] (2000,4000]): f 0.05 0.05 0.1 0.15 0.2 0.3 0.5 —;
  m 0.1 0.1 0.2 0.3 0.5 0.8 1.2 2; c 0.2 0.3 0.5 0.8 1.2 2 3 4; v — 0.5 1 1.5 2.5 4 6 8. Table 2 (radii and chamfer heights; [0.5,3] (3,6] over 6):
  f and m 0.2 0.5 1; c and v 0.4 1 2.

- [ ] **Step 1: Tests** (`ISO286Tests`, each vector upper / lower in mm, within 1e-12): `holeH7At20` (+0.021 / 0); `shaftG6At20` (−0.007 / −0.020);
  `shaftF7At25` (−0.020 / −0.041); `shaftK6At50` (+0.018 / +0.002); `shaftN6At30` (+0.028 / +0.015, 30 is in (18,30]); `shaftP6At40` (+0.042 / +0.026);
  `shaftS6At60` (+0.072 / +0.053); `holeK7At20` (+0.006 / −0.015); `holeK8At20` (+0.010 / −0.023); `holeN7At20` (−0.007 / −0.028); `holeN9At20`
  (0 / −0.052); `holeP7At20` (−0.014 / −0.035); `holeP8At20` (−0.022 / −0.055); `holeF8At10` (+0.035 / +0.013); `holeG7At10` (+0.020 / +0.005);
  `holeJS7At20` (+0.0105 / −0.0105); `shaftJs6At20` (+0.0065 / −0.0065); `smallSizesUseTheirOwnRule` (Ø2 N7 −0.004 / −0.014, Ø2 K7 0 / −0.010, Ø2
  P7 −0.006 / −0.016); `shaftH11At100` (0 / −0.220); `holeH11At500` (+0.400 / 0); `theRangeIsInclusiveAbove` (Ø18 H7 +0.018, Ø18.001 H7 +0.021);
  `outOfRangeIsRefused` (Ø0 and Ø500.001: R11's sentence); `gradeOutOfRangeIsRefused` (IT4, IT12); `everyITValueMatchesTheTable` (R11's rows).
  `ISO2768Tests`: `mediumAt25` (0.2); `mediumAt30` (0.2) and `At30001` (0.3); `underHalfAMillimetreHasNone`; `veryCoarseBelowThreeHasNone`;
  `fineAbove2000HasNone`; `brokenEdges` (m 2 → 0.2, c 5 → 1, f 10 → 1); `asmeRowsByPlaces` (default mm table, places 1 → 0.1; inches places 2 → 0.254;
  places 5 → nil); `summaries` ("±0.2 (ISO 2768-m)", "ISO 2768-m" for an angle, "±0.1" for an ASME mm row, nil for `.text`).
- [ ] **Step 2: Run** `swift test --filter 'ISO286Tests|ISO2768Tests'`; compile failure.
- [ ] **Step 3: Implement** the tables as arrays indexed by range (no dictionary iteration), the rules of R11.
- [ ] **Step 4: Run** the filter; pass.
- [ ] **Step 5: Commit** "Drawings: ISO 286 fits and general tolerances".

### Task 3: Numbers, labels and callout symbols

**Files:**
- Create: `Sources/CreatorDrawing/Dimensions/NumberFormat.swift`, `DimensionNumber.swift`, `DimensionLabel.swift`,
  `DimensionLabel+Tolerance.swift`, `HoleShape.swift`; `Sources/CreatorDrawing/Symbols/DrawingSymbols+Callouts.swift`
- Test: `Tests/CreatorDrawingTests/DimensionNumberTests.swift`, `DimensionLabelTests.swift`, `CalloutSymbolTests.swift`

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces:
  - `public struct NumberFormat: Hashable, Sendable { units: DocumentUnits; standard: DrawingStandard; decimalSign: DecimalSign }` with
    `init(units:settings:)`.
  - `DimensionNumber.length(_ mm: Double, precision: Int?, format: NumberFormat) -> String`, `.angle(_ radians: Double, precision: Int?, format:)
    -> String`, `.places(of text: String) -> Int`, `.signed(_ mm: Double, places: Int, format:) -> String` (R10's deviation forms).
  - `public enum LabelSymbol: Hashable, Sendable { case depth, counterbore, countersink }`; `public enum LabelPiece: Hashable, Sendable { case
    text(String); case symbol(LabelSymbol) }`; `public struct StackedText: Hashable, Sendable { upper: String; lower: String }`;
    `public struct DimensionLabel: Hashable, Sendable { lines: [[LabelPiece]]; stack: StackedText?; trailing: String; isBoxed: Bool }` with
    `var plainText: String` (symbols as "↧", "⌴", "⌵"; for lists, never drawn) and `func lost() -> DimensionLabel` ("?" after the first line's
    text, before any stack).
  - `public enum SizeSymbol: Sendable { case none, radius, diameter }`; `DimensionLabel.size(_ mm: Double, symbol: SizeSymbol, tolerance:
    DimensionTolerance, precision: Int?, prefix: String, suffix: String, format: NumberFormat) throws(DrawingRefusal) -> DimensionLabel`
    (radius refuses a fit); `DimensionLabel.angle(_ radians: Double, tolerance:, precision:, prefix:, suffix:, format:)
    throws(DrawingRefusal)`; `DimensionLabel.chamfer(leg: Double, angle: Double, precision: Int?, format:) -> DimensionLabel` (ISO "C2" when
    |angle − 45°| ≤ 1e-9 rad, else "2 × 30°"; ASME "2 X 45°"); `DimensionLabel.hole(_ shape: HoleShape, precision: Int?, prefix:, suffix:,
    format:) -> DimensionLabel`; `DimensionLabel.ordinate(_ mm: Double, precision: Int?, format: NumberFormat) -> DimensionLabel` (the origin's "0").
  - `public struct HoleShape: Hashable, Sendable { diameter: Double; depth: Double?; counterbore: Counterbore?; countersink: Countersink? }`
    (`Counterbore { diameter; depth }`, `Countersink { diameter; angle }`).
  - `DrawingSymbols.labelSymbol(_ symbol: LabelSymbol, origin: Vector2, h: Double) -> [SheetSegment]` (origin the box's baseline left, the box
    h × h): depth: a line (0.5h, h)→(0.5h, 0), a V (0.15h, 0.35h)→(0.5h, 0)→(0.85h, 0.35h), a bar (0, 0)→(h, 0); counterbore: (0, 0.6h)→(0, 0)→(h, 0)→
    (h, 0.6h); countersink: (0, 0.6h)→(0.5h, 0)→(h, 0.6h). `DrawingSymbols.labelSymbolAdvance(h:) = 1.6h` (the box and 0.3h either side).

- [ ] **Step 1: Tests.**
  - `DimensionNumberTests`: `millimetresDropTrailingZeros` (25.0 at 2 → "25", 25.40 → "25.4"); `inchesKeepThem` (25.4 mm at 3 in ISO → "1.000");
    `asmeInchesDropTheLeadingZero` (6.35 mm at 3 → ".250"; ISO inches "0.250"; ASME mm 0.25 → "0.25"); `aCommaInISO` ("25,4"); `asmeIgnoresTheComma`;
    `roundsHalfAwayFromZero` (0.125 at 2 → "0.13", −0.125 → "-0.13"); `neverMinusZero`; `theMinusIsAscii` (no U+2212 in any output);
    `anglesInDegrees` (π/6 → "30°", 0.5236 rad → "30°" at 0 decimals, 30.25° at 1 → "30.3°"); `precisionOverridesTheDocument`;
    `deviationForms` (mm +0.1 → "+0.1", 0 → "0"; in 0 at 3 places → "+.000" and "-.000").
  - `DimensionLabelTests`: `general` ("25"); `symmetric` ("25 ±0.1"; inch "1.000 ±.005"); `deviationStacksPadded` (+0.1/−0.25 → upper "+0.10", lower
    "-0.25"); `limitsStack` ("25.1" over "24.9"); `reference` ("(25)"); `basicIsBoxed`; `fitWithDeviations` ("Ø20 H7" trailing "(+0.021/0)");
    `fitInInches` ("(+.0008/0)"); `fitOnARadiusIsRefused` (the sentence); `fitOutOfRangeIsRefused`; `prefixAndSuffix` ("2× Ø6 TYP" from prefix "2×",
    suffix "TYP" joined by spaces); `chamferForms` (ISO 2 mm 45° "C2", 30° "2 × 30°", ASME "2 X 45°"); `holeForms` (THRU "Ø6 THRU"; blind "Ø6 ↧10"
    as `.text("Ø6 ")`, `.symbol(.depth)`, `.text("10")`; counterbore second line; countersink "⌵Ø12 × 90°", ASME "X"); `lostAppendsAQuestionMark`
    ("25?" keeps its stack).
  - `CalloutSymbolTests`: `depthStrokes`, `counterboreStrokes`, `countersinkStrokes` (each symbol's segments at h = 2.5 and origin (10, 20) equal the
    Interfaces' coordinates exactly); `advanceIsOnePointSixH`.
- [ ] **Step 2: Run** `swift test --filter 'DimensionNumberTests|DimensionLabelTests|CalloutSymbolTests'`; compile failure.
- [ ] **Step 3: Implement** numbers from integers as `PDFNumber` does (scale, round, split), never `formatted`.
- [ ] **Step 4: Run** the filter; pass.
- [ ] **Step 5: Commit** "Drawings: dimension numbers, labels and callout symbols".

### Task 4: Anchor resolution and measurement

**Files:**
- Create: `Sources/CreatorDrawing/Anchors/AnchorGeometry.swift`, `LostReason.swift`, `DrawingAnchorResolver.swift`,
  `Sources/CreatorDrawing/Dimensions/DrawingMeasure.swift`, `Sources/CreatorDrawing/Layout/ViewMapping.swift`
- Test: `Tests/CreatorDrawingTests/AnchorResolverTests.swift`, `DrawingMeasureTests.swift`, `Support/TopologyFixtures.swift` (hand-built
  topologies: a plate with named faces, an edge split into two collinear pieces, a circle, a cylinder)

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `public enum AnchorGeometry: Hashable, Sendable { case segment(Vector3, Vector3); case circle(center: Vector3, axis: Vector3, radius: Double,
    sweep: Double); case point(Vector3); case cylinder(axisPoint: Vector3, axis: Vector3, radius: Double, side: Double /* +1, −1, or 0 for the axis */);
    case other(midpoint: Vector3) }` (other: a held edge with no exact curve).
  - `public enum LostReason: Hashable, Sendable` with R4's cases and `var sentence: String`.
  - `public enum AnchorResolution: Hashable, Sendable { case held(AnchorGeometry, edges: [EdgeID], isRun: Bool); case lost(LostReason) }`.
  - `DrawingAnchorResolver.resolve(_ target: AnchorTarget, in topology: Topology, frame: ProjectionFrame) -> AnchorResolution` (R4; callers
    never pass `.point`, which the composer places itself (R14); given one it answers `.lost(.missing)`).
  - `public struct DrawingMeasurement: Hashable, Sendable { values: [Double]; figure: AnnotationFigure }`;
    `DrawingMeasure.measure(_ dimension: DrawingDimension, anchors: [AnchorResolution], frame: ProjectionFrame, mapping: ViewMapping?) ->
    Result<DrawingMeasurement, LostReason>` (R6's table, R5's checks as `.foreshortened`; the mapping only orients the sector choice and the
    feet's side: `nil` uses model-plane directions, which are the sheet's since views never rotate). `ViewMapping` is Task 7's; this task
    declares `public struct ViewMapping: Hashable, Sendable { public var scale: Double; public var offset: Vector2 }` with `sheet(_:)` and
    `model(_:)` and Task 7 adds `of(projection:center:scale:)`.

- [ ] **Step 1: Tests** (topologies from `TopologyFixtures`, frames from `StandardOrientation`).
  - `AnchorResolverTests`: `anExactMatchIsHeld`; `aSplitEdgeIsMeasuredAsItsRun` (two collinear pieces sharing an end: `.held(.segment(extreme ends),
    isRun: true)`); `aChangedRunCountIsLost` (the two pieces now meet at an angle: `.several(2)`); `severalSeparateMatchesAreLost`
    (`.several(2)`, the sentence says "2 edges"); `aNarrowedKeyFindingOneIsHeld`; `aNarrowedKeyFindingTwoIsLost`; `operandKeysAreNeverTried` (a key
    that only `operandKeys` would find is `.missing`); `aCornerIsTheSharedEnd`; `aCornerWhoseEdgesPartIsLost`; `aCentreOfALineIsLost`
    (`.notLineOrCircle`); `aGuessedFaceIsLost` (narrowed, ambiguous: `.guessed`); `anOutlinePicksItsSide` (side (0, 1) on a cylinder along x seen from
    the front: +1); `aTurnedOutlineIsLost`; `aPlaneIsNotACylinder`; `everyReasonHasItsSentence` (R4's table verbatim).
  - `DrawingMeasureTests`: `aHorizontalEdge` (Front view, edge (0,0,0)–(40,0,0): 40, figure points (0,0),(40,0)); `aTiltedEdgeIsForeshortened` (edge
    (0,0,0)–(40,10,0) in the Front view: `.foreshortened`); `aVerticalBetweenCorners`; `alignedBetweenPoints` (3-4-5: 5); `pointToLine`;
    `parallelLines`; `aDiameterOfAFaceOnCircle` (Top view, circle axis z, r 3: 6); `aCircleSeenEdgeOnIsForeshortened`; `aSideOnCylinderDiameter`
    (`axis` anchor: 2r, figure across the axis); `angleBySector` (lines along x and at 30°: placement angle 15° → 30°, 105° → 150°);
    `baselineValues` (points x 0, 10, 25: [10, 25]); `chainValues` ([10, 15]); `ordinateValues` (origin 5: [5, 20]); `chamferLeg` (a 45° chamfer of
    length 2√2 against a horizontal reference: leg 2, angle π/4); `anyLostAnchorLosesTheWhole` (baseline with one `.lost(.missing)`: `.missing`).
- [ ] **Step 2: Run** `swift test --filter 'AnchorResolverTests|DrawingMeasureTests'`; compile failure.
- [ ] **Step 3: Implement** R4 to R6. Line runs: order pieces by projection on the run's direction and take the extreme ends; circle runs: the
  first piece's centre, axis and radius, sweeps summed.
- [ ] **Step 4: Run** the filter, then `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: anchor resolution and measurement".

### Task 5: Reading holes (counterbores and countersinks)

**Files:**
- Create: `Sources/CreatorDrawing/Anchors/HoleReader.swift`, `Sources/CreatorDrawing/Anchors/Topology+Adjacency.swift` (`edges(of face:)`)
- Test: `Tests/CreatorDrawingTests/HoleReaderTests.swift` (hand-built topologies), `Tests/CreatorAppTests/HoleReaderOCCTTests.swift`
  (`#if canImport(CreatorOCCT)`: real holes on `OCCTKernel`)

**Interfaces:**
- Consumes: Task 3's `HoleShape`, Task 4's resolver (the picked edge resolves first; a lost edge is that reason).
- Produces: `public enum HoleReading: Hashable, Sendable { case hole(HoleShape, center: Vector3, axis: Vector3, radius: Double /* the picked circle's */);
  case notAHole; case lost(LostReason) }`; `HoleReader.read(_ target: AnchorTarget, in topology: Topology, frame: ProjectionFrame) -> HoleReading`
  (R12; `.notAHole` becomes the pick refusal sentence or `.notAHole` lost reason at the caller).

- [ ] **Step 1: Tests.** `HoleReaderTests`: `aThroughHole` (Ø6 THRU); `aBlindFlatHole` (Ø6 depth 10); `aDrillPoint` (cone bottom: depth to the
  cylinder's end, 10); `aCounterbore` (Ø11 depth 6 over Ø6 THRU); `pickingTheInnerCircleWalksOutToTheMouth` (the Ø6 circle on the counterbore floor
  reads the same as the Ø11 one); `aCountersink` (Ø12 × 90° over Ø6 THRU, angle from radii 6 and 3 over height 3: 90°); `aCircleOnABossIsNotAHole`
  (the circle's wall faces outward: an outer cylinder whose far end is a plane larger than it: `.notAHole`); `aCircleSeenEdgeOnIsForeshortened`
  (`.lost(.foreshortened)` at resolve, R5); `anUnknownStackIsNotAHole` (a cone in the middle). `HoleReaderOCCTTests` (a 40 × 40 × 20 box minus a
  revolved stepped profile, `Kernel.revolve` and `Kernel.boolean(.subtract…)`): `occtCounterbore`, `occtCountersink`, `occtBlindDrillPoint`, each
  read from the Top view's picked mouth circle.
- [ ] **Step 2: Run** `swift test --filter 'HoleReaderTests|HoleReaderOCCTTests'`; compile failure.
- [ ] **Step 3: Implement** R12 (faces' edges by `EdgeInfo.faces`, coaxial by centre-to-axis distance ≤ 1e-6 and axis parallel within 1e-9, seams
  skipped).
- [ ] **Step 4: Run** the filter, `--filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: hole callouts read counterbores and countersinks".

### Task 6: Picture primitives and the writers (fills, rotated text, centre lines)

**Files:**
- Create: `Sources/CreatorDrawing/Picture/SheetFill.swift`
- Modify: `Sources/CreatorDrawing/Picture/SheetPicture.swift` (R16's fields), `Sources/CreatorDrawing/Style/DrawingStyle.swift` (`centreDash:
  [Double]`, R13's values), `Sources/CreatorDrawing/Views/ViewLinework.swift` (strokes carry `source`), `Sources/CreatorDrawing/Picture/SheetComposer.swift`
  (sets `picture.standard`), `Sources/CreatorDrawing/Export/PDFWriter.swift`, `DXFWriter.swift`, `DXFTables.swift` (CENTER per standard)
- Test: `Tests/CreatorDrawingTests/PDFWriterTests.swift`, `DXFWriterTests.swift` (additions; `Support/PDFStructureReader.swift` and
  `Support/DXFReader.swift` learn `f`, `Tm`, `SOLID` and code 50), `ViewLineworkTests.swift` (`strokesCarryTheirSource`)

**Interfaces:**
- Produces: `public struct SheetFill: Hashable, Sendable { points: [Vector2]; layer: DrawingLayer; view: ViewID?; annotation: AnnotationID?;
  isLost: Bool }`; the R16 fields with defaults (`angle` 0, `annotation` nil, `isLost` false, `source` nil, `standard` `.iso`), so DR-1's
  call sites compile unchanged; `StrokePattern.centre`; `DrawingStyle.centreDash`.

- [ ] **Step 1: Tests.** PDF: `fillsAreClosedAndFilled` (`… h f`); `rotatedTextUsesTm` (90°: `0 1 -1 0 x y Tm`, exact); `unrotatedTextKeepsTd` (DR-1's
  bytes); `dashesFollowThePageStandard` (an ASME page's centre stroke dashes `[19 1.5 3 1.5]`, ISO `[6 0.75 0.25 0.75]`); `theDR1DigestIsUnchanged`
  (the existing pin); `annotatedPageDigest` (a new fixture with fills, a 30° text "25 ±0.1", a centre stroke and "-0.2": its SHA-256 pinned, and
  the bytes contain "-0.2" and never `\342\210\222`). DXF: `fillsAreSolids` (vertex 4 = vertex 3); `textAngleIsCode50`; `centreStrokesOffTheCenterLayer
  CarryTheLinetype`; `asmeCenterLinetype` ([19, −1.5, 3, −1.5]); `annotatedSheetIsDeterministic` (two writes equal; handles sequential).
- [ ] **Step 2: Run** `swift test --filter 'PDFWriterTests|DXFWriterTests|ViewLineworkTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`; pass (the DR-1 digest unchanged).
- [ ] **Step 5: Commit** "Drawings: fills, rotated text and centre lines on paper".

### Task 7: The sheet-millimetre dimension layout

**Files:**
- Create: `Sources/CreatorDrawing/Style/AnnotationStyle.swift`, `Sources/CreatorDrawing/Layout/ViewMapping+Projection.swift`,
  `LabelLayout.swift`, `AnnotationDrawing.swift`, `SheetDimensionLayout.swift`, `SheetDimensionLayout+Linear.swift`, `+Radial.swift`,
  `+Angle.swift`, `+Leaders.swift`
- Modify: `Sources/CreatorDrawing/Views/ViewLinework.swift` (uses `ViewMapping`)
- Test: `Tests/CreatorDrawingTests/LabelLayoutTests.swift`, `LinearLayoutTests.swift`, `RadialAndAngleLayoutTests.swift`, `LeaderLayoutTests.swift`

**Interfaces:**
- Consumes: Tasks 1, 3, 4 (`ViewMapping`), 6.
- Produces:
  - `public struct AnnotationStyle: Hashable, Sendable` with R8's constants and `static func of(_:) -> AnnotationStyle`.
  - `ViewMapping.of(projection: Projection2D, center: Vector2, scale: Double) -> ViewMapping?` (nil without bounds).
  - `public struct AnnotationDrawing: Hashable, Sendable { segments: [SheetSegment] (thin, solid); boxes: [[Vector2]] (basic frames); fills:
    [[Vector2]]; texts: [PlacedText]; textCenter: Vector2?; frame: Rect2D }`, `public struct PlacedText: Hashable, Sendable { run: TextRun;
    original: String; origin: Vector2; height: Double; angle: Double }`.
  - `LabelLayout.place(_ label: DimensionLabel, height: Double, center: Vector2, angle: Double, style: AnnotationStyle) -> (texts: [PlacedText],
    segments: [SheetSegment], width: Double, box: [Vector2]?)` (pieces left to right through `DrawingText.layout`, symbols through
    `DrawingSymbols.labelSymbol`, the stack after the main text, the trailing text after a space; centred on `center`, rotated by `angle`).
  - `SheetDimensionLayout.draw(_ figure: AnnotationFigure, kind: DrawingDimensionKind, labels: [DimensionLabel], placement: DimensionPlacement,
    mapping: ViewMapping, standard: DrawingStandard, height: Double) -> AnnotationDrawing` (one label per value; ordinate also the origin's);
    `SheetDimensionLayout.callout(center:radius:lines:placement:mapping:standard:height:)`, `.leader(from: Vector2, to: Vector2, side: …)`.

- [ ] **Step 1: Tests** (A3, h = 2.5, 1:1 unless said):
  - `LabelLayoutTests`: `widthIsHelveticas` ("25" at 2.5 = the run's width); `symbolsAdvance1_6h`; `aStackFollowsTheValue`; `rotationKeepsTheCentre`;
    `basicBoxPadsOneMillimetre`.
  - `LinearLayoutTests`: `isoTextSitsAboveParallel` (a 40 mm horizontal dimension, offset 10: the text's baseline 1 mm above the line, centred, angle 0);
    `isoVerticalTextReadsFromTheRight` (angle +90°); `asmeTextIsHorizontalInABreak` (the dimension line has a gap of width w + 3 at the text);
    `extensionLinesGapAndOvershoot` (ISO 0 and 2, ASME 1.5 and 3); `aShortDimensionFlipsItsArrows` (2 mm: heads outside, tails 2.5 mm);
    `textOutsideClearsTheExtensionLines` (8 mm: the text frame starts ≥ textGap + arrowLength past the second extension line, both standards);
    `aTextShiftMovesTheTextAndExtendsTheLine`; `baselineStacks` (three values at offsets 10, 18, 26 ISO); `chainSharesOneLine`;
    `ordinateLeadersEndOnTheLine` (origin text "0"); `arrowheadsAreTriangles` (length 2.5, base 0.8333…).
  - `RadialAndAngleLayoutTests`: `aRadiusArrowPointsAtTheArc`; `aDiameterInside` (Ø40, ISO: line through the centre, two heads inside);
    `aSmallCircleTakesALeader` (Ø3 ISO; any diameter ASME); `anAngleArcSpansTheSector`; `aShortArcFlipsItsArrows`; `asmeAngleTextHorizontal`.
  - `LeaderLayoutTests`: `aCalloutLeaderEndsInAShoulder` (3 mm, the text on the side the leader points to, lines downward 1.6h apart);
    `aNoteLeaderLeavesTheNearerSide`.
- [ ] **Step 2: Run** `swift test --filter 'LabelLayoutTests|LinearLayoutTests|RadialAndAngleLayoutTests|LeaderLayoutTests'`; compile failure.
- [ ] **Step 3: Implement** R7 and R8.
- [ ] **Step 4: Run** the filter, `--filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: the dimension layout in sheet millimetres".

### Task 8: Annotations in the sheet picture (reports, lost display, centre marks, notes)

**Files:**
- Create: `Sources/CreatorDrawing/Picture/AnnotationReport.swift`, `AnnotationComposer.swift`, `AnnotationComposer+Kinds.swift`,
  `CentreMarkComposer.swift`
- Modify: `Sources/CreatorDrawing/Picture/SheetComposer.swift` (`compose(_:in:contents:facts:notices:units:remembered:)`, annotations after the
  views, `viewExtents`), `Sources/CreatorDrawing/Views/ViewContent.swift` (`topology: Topology?`)
- Test: `Tests/CreatorDrawingTests/AnnotationComposerTests.swift`, `CentreMarkTests.swift`, `SheetComposerTests.swift` (additions)

**Interfaces:**
- Consumes: Tasks 1 to 7.
- Produces:
  - `ViewContent.topology: Topology?` (the projected solid's; filled in Task 9).
  - `public enum AnnotationStatus: Hashable, Sendable { case held; case lost(LostReason) }`; `public struct AnnotationReport: Hashable, Sendable
    { status; current: LastGood? (held only); label: String (plain text, "25?" when lost); frame: Rect2D; textCenter: Vector2? }`.
  - `SheetComposer.compose(_ sheet:, in:, contents:, facts:, notices: Bool = true, units: DocumentUnits = .millimetres, remembered:
    [AnnotationID: LastGood] = [:]) -> SheetPicture`; the picture's `annotationReports`, `lostAnnotations` (sheet order), `viewExtents`.
  - Behaviour: per annotation of a view with a projection and a topology: resolve (Task 4), measure (Task 4 / Task 5), label (Task 3, the
    sheet's `NumberFormat`), lay out (Task 7), tag strokes, texts and fills with the view, the annotation and `isLost`; R15 for lost ones (a fit
    refused when labelled, such as a size that has left ISO 286's range, makes the annotation lost `.refused(sentence)`; a view with no topology
    gives `.noPart`, a removed source `.sourceRemoved`, a failed one `.viewFailed(problem)`); a note's leaders resolved alone (a lost leader end draws to its `last` point, the note itself held);
    R13's automatic centre marks for views with `showsCentreMarks`, on `.center`, never selectable.

- [ ] **Step 1: Tests** (FakeKernel-free: projections and topologies from `TopologyFixtures`):
  - `AnnotationComposerTests`: `aHeldDimensionDrawsItsValue` ("40" on `.dimension`, tagged); `itMovesWithItsView` (moving the view by (10, 0) moves
    every annotation point by (10, 0)); `aLostDimensionShowsItsLastValueWithAQuestionMark` (remembered 40: text "40?", `isLost`, listed in
    `lostAnnotations`, report reason `.missing`); `withoutAnyLastValueItIsALoneQuestionMark`; `aRemovedSourceListsButDrawsNothing`;
    `theReportCarriesTheCurrentFigure`; `aNoteDrawsItsLines` (two lines 1.6h apart on `.text`); `aNoteLeaderEndsOnItsEdge` (nearest point to the hint);
    `aFreeNoteIsAbsolute`; `aHoleCallout` ("Ø6 THRU" with its symbol strokes); `aCentreLineRunsPastTheCylinder`; `generalToleranceWritesNothing`;
    `inchesFlowThrough` (units inches: "1.575" for 40 mm at 3); `viewExtentsCoverAnnotations`.
  - `CentreMarkTests`: `aFaceOnCircleGetsAMark` (two `.centre` strokes reaching r × s + 2); `concentricCirclesShareOne`; `aSmallCircleGetsASolidCross`;
    `arcsAndHiddenCirclesGetNone`; `theViewFlagTurnsThemOff`.
- [ ] **Step 2: Run** `swift test --filter 'AnnotationComposerTests|CentreMarkTests|SheetComposerTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`; pass (DR-1 composer tests unchanged).
- [ ] **Step 5: Commit** "Drawings: annotations on the sheet, held or lost".

### Task 9: Picking anchors, and the projected part's topology

**Files:**
- Create: `Sources/CreatorDrawing/Picks/PickCandidate.swift`, `DrawingPick.swift`, `DimensionInference.swift`
- Modify: `Sources/CreatorDrawing/Projection/ProjectionCache.swift` (`projection(...)` returns `CachedProjection`), `DrawingProjector.swift` (fills
  `ViewContent.topology`), `Sources/CreatorDrawing/Picture/SheetHitTest.swift` (`line(near:…)` skips annotation and centre-mark strokes;
  `annotation(at:in:order:)`)
- Test: `Tests/CreatorDrawingTests/DrawingPickTests.swift`, `DimensionInferenceTests.swift`, `ProjectionCacheTests.swift` and
  `DrawingProjectorTests.swift` (additions), `SheetHitTestTests.swift` (additions)

**Interfaces:**
- Consumes: Tasks 1, 4, 5, 8.
- Produces:
  - `public struct CachedProjection: Sendable { projection: Projection2D; topology: Topology? }` (one solid: its topology; several: the compound's;
    none: nil). Callers of `ProjectionCache.projection` read `.projection`.
  - `public enum PickCandidate: Hashable, Sendable { case edge(EdgeID, stroke: Int); case corner(EdgeID, at: Vector2); case centre(EdgeID, at:
    Vector2); case outline(FaceID, stroke: Int) }` (sheet points); `DrawingPick.candidate(at: Vector2, in: SheetPicture, view: ViewID, tolerance:
    Double) -> PickCandidate?` (R17's order; `.curve` sources give nil candidates and a separate `refusal(at:…)` reports R5's free-curve sentence).
  - `public enum PickPurpose: Sendable { case dimension, holeCallout, centreMark, centreLine, leader }`; `public enum PickShape: Hashable, Sendable
    { case line(Vector2, Vector2); case circle(center: Vector2, radius: Double, isFull: Bool); case point(Vector2); case cylinder(axisPoint: Vector2,
    direction: Vector2, radius: Double) }` (model plane); `public struct PickedAnchor: Hashable, Sendable { target: AnchorTarget; shape: PickShape }`;
    `DrawingPick.anchor(for: PickCandidate, click: Vector2, purpose: PickPurpose, topology: Topology, frame: ProjectionFrame, mapping: ViewMapping,
    isIsometric: Bool) -> Result<PickedAnchor, DrawingRefusal>` (R3, R5; a corner's neighbour is the lowest-`EdgeID` edge with a one-run key that
    ends at the same 3D point within 1e-4 mm; an outline's `side` is the unit sheet vector from the axis toward the clicked line).
  - `public enum DimensionTool: Sendable { case smart, baseline, chain, ordinate, chamfer }`; `DimensionInference.isComplete(_ picks: [PickedAnchor],
    tool: DimensionTool) -> Bool`, `DimensionInference.make(tool:, picks:, placing: Vector2 (model plane), aligned: Bool) -> Result<(kind:
    DrawingDimensionKind, anchors: [AnchorTarget]), DrawingRefusal>` (R6), `DimensionInference.placement(for kind: DrawingDimensionKind, picks:
    [PickedAnchor], placing: Vector2 (sheet), mapping: ViewMapping) -> DimensionPlacement` (R7 from the picks' shapes: the placing click sets
    `offset` (along n from the first feature point) or `angle` and `offset` (about the centre or the vertex), `textShift` nil).
  - `SheetHitTest.annotation(at: Vector2, in: SheetPicture, order: [AnnotationID]) -> AnnotationID?` (topmost whose report frame grown by 1 mm holds it).

- [ ] **Step 1: Tests.**
  - `DrawingPickTests`: `aLineIsAnEdge`; `nearAnEndIsACorner` (its neighbour the lowest-ID edge at that end); `nearACircleCentreIsACentre`;
    `aSilhouetteIsAnOutline` (side toward the click); `anUnnamedEdgeIsRefused`; `aSharedKeyIsRefused`; `aSplitEdgeIsAccepted` (key forms one run:
    `runCount` 1); `aFreeCurveIsRefused`; `anIsometricViewRefusesDimensionsButNotLeaders`; `aTiltedLineIsRefused` (decision 4's sentence);
    `aCircleSeenEdgeOnIsRefused`; `anEllipseEdgeIsRefusedForDimensionsOnly`; `aBossIsNotAHole` (hole purpose); `annotationStrokesAreNotPicked`.
  - `DimensionInferenceTests`: R6's table row by row (`aHorizontalLine`, `aSlantedLineIsAligned`, `aCircleIsADiameter`, `anArcIsARadius`,
    `twoPointsByWhereTheyArePlaced` (above → horizontal, right → vertical, ⇧ → aligned), `pointAndLine`, `parallelLines`, `twoLinesAreAnAngle`,
    `aCircleWithAPointGivesItsCentre`, `baselineDirectionByPlacement`, `aLineThatDoesntCrossIsRefused`, `chamferNeedsTwoLines`); `placementFromTheClick`
    (offset = the click's distance along n; radial angle = atan2 of the click about the centre).
  - `ProjectionCacheTests`: `aSingleSolidGivesItsTopology`; `aCompoundGivesItsOwn` (the hook's solid's topology); `curvesOnlyGiveNone`.
  - `DrawingProjectorTests`: `contentCarriesTheTopology`.
- [ ] **Step 2: Run** the filters; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingTests`; pass.
- [ ] **Step 5: Commit** "Drawings: picking anchors on view lines".

### Task 10: The editor's annotation tools

**Files:**
- Create: `Sources/CreatorDrawingEditor/DrawingEditorModel+Annotations.swift`, `DrawingEditorModel+Picking.swift`, `AnnotationDraft.swift`
- Modify: `Sources/CreatorDrawingEditor/DrawingTool.swift` (R17's cases and titles), `DrawingStepName.swift` (the Add steps of R19),
  `DrawingKey.swift` (`.tool(DrawingTool)`), `Views/SheetCanvasInput.swift` (D, H, M, L, N), `DrawingEditorModel.swift` (`units: DocumentUnits`
  replaces `standardUnitsAreInches` in `init` and as a public var; `remembered`, `hoverCandidate`, `draftPicture`), `DrawingEditorModel+Pointer.swift`
- Test: `Tests/CreatorDrawingEditorTests/AnnotationToolTests.swift`, `ReattachTests.swift`, `Support/DrawingEditorFixtures.swift` (contents with
  topologies: a FakeKernel-extruded plate's Front and Top views, and a hand-built view holding a face-on hole circle)

**Interfaces:**
- Consumes: Tasks 1, 8, 9.
- Produces:
  - `DrawingTool` cases `dimension, baselineDimension, chainDimension, ordinateDimension, chamferDimension, holeCallout, centreMark, centreLine, note`
    (titles "Dimension", "Baseline", "Chain", "Ordinate", "Chamfer", "Hole Callout", "Centre Mark", "Centre Line", "Note") after DR-1's.
  - `DrawingEditorModel`: `public internal(set) var hoverCandidate: PickCandidate?`, `picks: [PickedAnchor]` (read only), `draftPicture:
    SheetPicture?` (the current picture with the draft annotation composed in, nil without one), `@ObservationIgnored var remembered:
    [AnnotationID: LastGood]` (merged from every rebuilt picture's held reports), `public var units: DocumentUnits` (rebuilds), `addingLeader:
    AnnotationID?`, `beginLeader(for:)`.
  - Behaviour: R17 and R15's re-attach; R19's Add steps; a refusal sets `refusal` and commits nothing; Esc drops picks, then the tool.

- [ ] **Step 1: Tests.**
  - `AnnotationToolTests`: `oneLineThenEmptySpacePlacesItsLength` (Front view of a 40 mm plate: one "Add Dimension" commit, kind `linear(.horizontal)`,
    one `.edge` anchor, offset from the click); `twoCornersByPlacement`; `shiftMakesItAligned`; `aCircleIsADiameterAtOnce`; `aBaselineCollectsUntilPlaced`;
    `anOrdinateTakesAnOrigin`; `aChamferNeedsTwoLines`; `aHoleCalloutReadsTheHole` ("Add Hole Callout"); `aCentreMarkCommitsOnOnePick`; `aCentreLineOnAnOutline`;
    `aNoteInAViewBelongsToIt` (position relative to the view's centre; "Add Note"; selected); `aNoteOutsideIsFree`; `aLeaderEndsOnTheNextClick` ("Add Leader");
    `aLeaderIntoAnotherViewIsRefused`; `isometricRefusesTheDimensionTool` (the sentence; no commit); `foreshortenedRefuses`; `escapeDropsPicksThenTheTool`;
    `theDraftFollowsThePointer` (`draftPicture` non-nil after the first pick, nothing committed); `toolKeys` (D, H, M, L, N select their tools; F still fits);
    `hoverFindsCornersAndCentres`; `unitsChangeRebuildsThePicture`; `rememberedKeepsTheNewestHeld`.
  - `ReattachTests`: `aClickReplacesTheFirstLostAnchor` (one "Reattach Dimension" commit; the dimension is held again); `theSameCaseIsRequired` (a
    corner for an edge: the sentence); `onlyWithOneLostSelected` (a held selection: the click selects the view as before).
- [ ] **Step 2: Run** `swift test --filter 'AnnotationToolTests|ReattachTests'`; fail.
- [ ] **Step 3: Implement.** Update DR-1 call sites of the editor `init` (fixtures, `DrawingSession`) to pass `units`.
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingEditorTests`; pass.
- [ ] **Step 5: Commit** "Drawings: the editor's dimension, callout, centre and note tools".

### Task 11: Selecting, moving and editing annotations in the editor

**Files:**
- Create: `Sources/CreatorDrawingEditor/DrawingEditorModel+AnnotationSelection.swift`, `DrawingEditorModel+AnnotationInspector.swift`
- Modify: `DrawingEditorModel+Pointer.swift`, `DrawingEditorModel+Keys.swift`, `DrawingEditorModel+Views.swift` (`deleteSelection`),
  `DrawingEditorModel+Sheets.swift` (`duplicateSheet` copies annotations), `DrawingEditorModel+Inspector.swift` (`setGeneralTolerance`,
  `setDecimalSign`), `DrawingEditorEvents.swift` (`discarded: @MainActor (String) -> Void`, default no-op), `DrawingStepName.swift` (the rest of R19)
- Test: `Tests/CreatorDrawingEditorTests/AnnotationSelectionTests.swift`, `AnnotationInspectorTests.swift`, `DrawingStepNameTests.swift` (R19's table
  added to `everyMethodCommitsItsStep` and `noChangeNoCommit`)

**Interfaces:**
- Consumes: Task 10.
- Produces:
  - `public var selectedAnnotations: Set<AnnotationID>`; `lostAnnotations: [(id: AnnotationID, label: String, reason: String)]` (the current sheet's,
    in sheet order); `documentForSaving() -> DrawingDocument` (every annotation's `last` set from `remembered` where present).
  - Setters (each R19's step; each refusing in words where R10/R20 say): `setDimensionKind(_ kind: DrawingDimensionKind, of: AnnotationID)` (a linear's
    direction, radius ↔ diameter; baseline and chain refuse `.aligned`: "Baseline and chain dimensions run horizontally or vertically."),
    `setPrecision(_: Int?, of:)`, `setPrefix(_: String, of:)`, `setSuffix(_: String, of:)`, `setTolerance(_: DimensionTolerance, of:)`,
    `setTolerance(text: …)` parsing helpers for the inspector (`symmetricText:`, `upperText:lowerText:`), `setNoteText(_: String, of:)`,
    `removeLeader(at index: Int, of:)`, `setShowsCentreMarks(_: Bool, of: ViewID)`, `setGeneralTolerance(_: GeneralTolerance)`, `setDecimalSign(_:)`.
  - `pointerCancelled()` restores the gesture's base document and calls `events.discarded(key)` when it committed (R18).

- [ ] **Step 1: Tests.**
  - `AnnotationSelectionTests`: `annotationsAreHitBeforeViews`; `shiftAddsAnnotations`; `aDragMovesTheDimensionLine` (offset grows by the motion along n;
    one coalesced "Move Dimension"); `draggingTheTextShiftsIt`; `aRadialDragTurnsTheLeader`; `aNoteDragMovesItsPosition` ("Move Note"); `mixedIsMoveAnnotations`;
    `nudgeMovesSelectedAnnotations`; `deleteNames` (R19's four cases); `deletingAViewDeletesItsAnnotations` (one "Delete View"); `duplicateSheetCopiesAnnotations`
    (new IDs, views remapped); `aCancelledDragRestoresAndDiscards` (document equal to the base, `discarded` called once with the drag's key);
    `documentForSavingWritesRemembered`.
  - `AnnotationInspectorTests`: `kindAndDirection`; `precision`; `toleranceKinds` (each case commits "Change Tolerance"); `aFitOnARadiusIsRefused`;
    `aBadToleranceNumberIsRefused` ("A tolerance is a number, such as 0.1."); `tolerancesAreTypedInTheDocumentUnit` (inches "0.005" stores 0.127 mm);
    `anEmptyNoteIsRefused`; `removeLeader`; `centreMarksToggleIsChangeView`; `generalToleranceIsEditTitleBlock`; `decimalSignIsChangeNumberFormat`;
    `lostAnnotationsListed` (label "40?" and the reason).
- [ ] **Step 2: Run** `swift test --filter 'AnnotationSelectionTests|AnnotationInspectorTests|DrawingStepNameTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingEditorTests`; pass.
- [ ] **Step 5: Commit** "Drawings: selecting, moving and editing annotations".

### Task 12: The editor's views: drawing annotations, the toolbar and the inspector pages

**Files:**
- Create: `Sources/CreatorDrawingEditor/Views/SheetFillShape.swift`, `SheetSelectionLayer.swift` (selected annotations and the hover ring),
  `DimensionInspector.swift`, `ToleranceControls.swift`, `NoteInspector.swift`, `AnnotationInspector.swift` (callouts, centre marks and lines, several)
- Modify: `Views/SheetStrokeGroups.swift` (`.centre` dashes; lost strokes in the warning colour; fills), `Views/SheetTextView.swift` (R16 rotation),
  `Views/SheetViewLayer.swift` (fills, lost colours), `Views/SheetFrameLayer.swift` (free annotations), `Views/SheetCanvas.swift` (cull by
  `viewExtents`, the selection layer, `draftPicture` drawn while set), `Views/DrawingToolbar.swift` (R17's tools), `Views/DrawingInspector.swift`,
  `Views/SheetInspector.swift` (general tolerance, decimal sign, Lost references), `Views/ViewInspector.swift` (Centre marks)
- Test: `Tests/CreatorDrawingEditorTests/AnnotationRenderTests.swift`, `SheetTextViewTests.swift` (`aRotatedRunKeepsItsBaseline`),
  `SheetViewEqualityTests.swift` (new properties' variants), `DrawingInspectorTests.swift` (additions), `DrawingToolbarTests.swift` (additions)

**Interfaces:**
- Consumes: Tasks 6, 10, 11.
- Produces: views only; every new `.equatable()` view's `==` covers its stored properties (`expectEqualityCovers`).

- [ ] **Step 1: Tests.** `AnnotationRenderTests` (pixels through `PixelReader`): `anArrowheadIsFilledInk`; `aLostDimensionIsWarningColoured`; `centreDashesShowGaps`;
  `aSelectedAnnotationIsHighlighted`; `theDraftIsDrawnWhilePicking`; `freeNotesDrawOnTheFrameLayer`. `SheetTextViewTests.aRotatedRunKeepsItsBaseline` (a 90° run's
  glyphs stack upward from the origin within 0.5 pt; else log gap `DR-2-a` per R16). `DrawingInspectorTests`: `aDimensionPageShowsItsRows` (Kind, Value,
  Precision, Tolerance, General "±0.3 (ISO 2768-m)", Prefix, Suffix); `aLostDimensionSaysWhyAndHowToReattach`; `fitControlsAppearForFits`; `aNotePageEditsText`;
  `theSheetPageListsLostReferences`; `decimalSignIsISOOnly`; `asmeShowsTheDecimalsTable`. `DrawingToolbarTests`: `everyToolHasAButtonOrMore` (all eleven, in R17's
  order, overflow into More).
- [ ] **Step 2: Run** `swift test --filter 'AnnotationRenderTests|SheetTextViewTests|SheetViewEqualityTests|DrawingInspectorTests|DrawingToolbarTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter CreatorDrawingEditorTests`; pass. `swift run GraphPanelPreview` is not affected; no window check here (human
  checks DR2-x).
- [ ] **Step 5: Commit** "Drawings: annotations on the canvas and their inspector".

### Task 13: Group, Ungroup and Make Unique rename drawing anchors

**Files:**
- Create: `Sources/CreatorGraph/Groups/DrawingDocument+TagRenaming.swift`, `Sources/CreatorGraph/Groups/TagRenaming.swift` (the tag helpers lifted
  from `ConstantValue+TagRenaming.swift`, which then calls them)
- Modify: `Sources/CreatorGraph/Groups/GroupScopes+PickRenaming.swift`, `Sources/CreatorGraph/Groups/ConstantValue+TagRenaming.swift`
- Test: `Tests/CreatorGraphTests/DrawingAnchorRenamingTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces: `DrawingDocument.renamingTags(_ names: [NodeID: NodeID]) -> DrawingDocument` (every `EdgePick` key, `FacePick` tags, nested blend tags,
  in every anchor and leader target); `renamingPicks` appends one `.setDrawings(renamed)` for the host `.root` when it differs (R21).

- [ ] **Step 1: Tests.** `groupingKeepsADimensionHeld` (FakeKernel: Box → Output; a dimension on a box edge; Group the Box: the anchor's tags name
  `NodeID.scoped` of the group node and the box, and resolve held against the re-evaluated Output's topology); `ungroupRenamesBack`; `makeUniqueRenames`;
  `undoRestoresTheOldNames` (one step); `unrelatedDrawingsAreUntouched` (no `.setDrawings` when nothing changes); `constantValuePicksStillRename` (the
  lifted helpers keep DR-1's behaviour).
- [ ] **Step 2: Run** `swift test --filter DrawingAnchorRenamingTests`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter CreatorGraphTests`; pass.
- [ ] **Step 5: Commit** "Drawings: group edits keep dimensions attached".

### Task 14: Dimensions in the app (units, saving last values, export warnings, DXF of a view with annotations)

**Files:**
- Modify: `Sources/CreatorGraph/DocumentModel.swift` (`fileData(savingTo:drawings:)`, `didSave(to:drawings:)`; the old signatures forward nil),
  `Sources/CreatorApp/AppModel+Files.swift` (`save(to:)` passes `drawing.editor.documentForSaving()` to both), `Sources/CreatorApp/Drawing/DrawingSession.swift`
  (`editor.units` kept level with `document.units`; the editor's `discarded` → `discardHandler`), `Sources/CreatorApp/Drawing/AppModel+Drawing.swift`
  (`discardDrawingStep(_ key:)`: `document.discardCoalescedStep(key:)` then `drawing.resync()`), `Sources/CreatorApp/AppModel+DrawingExport.swift`
  (composes with `units` and `remembered`; R15's per-sheet lost warning; `dxfViewWithAnnotations`), `Sources/CreatorApp/Export/DrawingExportKind.swift`,
  `Sources/CreatorApp/AppCommands.swift` and `Sources/CreatorApp/TopBar.swift` (the new menu item), `Sources/CreatorDrawing/Export/DXFWriter.swift`
  (`view(_ projection:, view:, style:, annotations: (picture: SheetPicture, mapping: ViewMapping)? = nil)`: the view's annotation strokes, fills
  and texts mapped back by the mapping, text heights ÷ scale)
- Test: `Tests/CreatorAppTests/DrawingDimensionTests.swift` (FakeKernel), `Tests/CreatorAppTests/DrawingDimensionOCCTTests.swift`
  (`#if canImport(CreatorOCCT)`), `Tests/CreatorAppTests/DrawingExportTests.swift` (additions), `Tests/CreatorGraphTests/DocumentSavingTests.swift`
  (`fileData` with drawings)

**Interfaces:**
- Consumes: Tasks 1 to 13.
- Produces: `DrawingExportKind.dxfViewWithAnnotations` (title "DXF", extension "dxf", menu "DXF of View at 1:1 with Annotations…");
  `DocumentModel.fileData(savingTo: URL?, drawings: DrawingDocument?) throws -> Data`; `didSave(to: URL, drawings: DrawingDocument?)` (sets the
  drawings in `content` without an undo step when given and different).

- [ ] **Step 1: Tests.**
  - `DrawingDimensionTests`: `addingADimensionIsOneUndoStep` (undo removes it, redo brings it back, the editor follows); `aCancelledDragLeavesNoStep`
    (`undoName` unchanged after a cancelled drag of a dimension); `anInchDocumentRestylesItsNumbers` (`setUnits` to inches at 3: the picture's text
    "1.575", ASME ".984" for 25 mm); `savingWritesLastGoodValuesWithoutAnEdit` (save to a temporary file: the file's annotation has `last.values` [40],
    `document.content == savedContent`, the undo stack's count unchanged, the window not edited); `aReopenedLostDimensionShowsItsLastValue` (reopen
    the saved file after removing the edge's feature in it: "40?", listed, in the PDF as "40?"); `exportWarnsAboutLostAnnotations` (R15's sentence
    for one sheet); `lostAnnotationsDontBlockAnExport`; `dxfViewWithAnnotationsMeasuresTrue` (a 1:2 view: the dimension's extension lines 40 apart in
    the DXF, its text height 5).
  - `DrawingDimensionOCCTTests`: `aDimensionFollowsAWidthChange` (Box → Output, Front view, the top edge's length dimension; width 40 → 60: "60",
    held); `aChamferOnTheEdgeLosesTheDimension` (a Chamfer node on that edge: lost, "40?", not attached to a neighbour); `aRibThatSplitsTheEdgeKeepsIt`
    (a union that splits the top edge collinearly: held, measuring the run, value unchanged); `aHoleCalloutOnARealCounterbore`.
  - `DocumentSavingTests`: `fileDataWithDrawingsWritesThem`; `didSaveWithDrawingsIsNotAnUndoStep`.
- [ ] **Step 2: Run** `swift test --filter 'DrawingDimensionTests|DrawingDimensionOCCTTests|DrawingExportTests|DocumentSavingTests'`; fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter CreatorAppTests` and `--filter CreatorGraphTests`; pass.
- [ ] **Step 5: Commit** "Drawings: dimensions in the app, saved with their last values".

### Task 15: Benchmark drawing-3

**Files:**
- Modify: `Tests/CreatorAppTests/Bench/DrawingBench.swift`, `DrawingBenchFixtures.swift` (the bracket sheet with 30 dimensions: lengths, diameters and
  angles over its four views), `DrawingBenchFixturesTests.swift` (the fixture's 30 dimensions are all held; checked in the default run),
  `docs/verification/performance.md` (rows `drawing-3`, `drawing-3-warm`)

- [ ] **Step 1:** fixture test first (`theAnnotatedBracketHoldsThirtyDimensions`), run, see it fail, then the fixture.
- [ ] **Step 2:** rows: `drawing-3` composing the annotated sheet (median, p95, max over 50 composes; report only) and `drawing-3-warm` (60 drag steps of
  one dimension, warm window CPU per frame, budget 16.67 ms), run with `scripts/bench.sh DrawingBench` (release; a loaded Mac's numbers are recorded as
  saturated, never as a verdict). If `drawing-3`'s median is over 4 ms, say so in the report (R24 then pulls in resolution caching as a follow-up).
- [ ] **Step 3: Commit** "Drawings: benchmark drawing-3".

### Task 16: Docs and the suites

**Files:**
- Modify: `CLAUDE.md` (a "Drawings, DR-2" paragraph after DR-1's: the annotation model and format 18, the resolver's rule and the lost display, the
  measurer and decision 4, the hole reader, tolerances and ISO 286's scope, the layout beside the viewport's (R1), centre marks and lines, notes and
  leaders, the tools and keys, saving last values, group renaming, the new export kind, R1 to R24 in short, the parked items; the file-format sentence
  becomes "File format is version 18 (… 18 added drawing annotations, a view's centre-mark flag and the structured general tolerance and decimal sign
  …); files of format 1 to 17 open unchanged and are written as 18"; the `CreatorDrawing` and `CreatorDrawingEditor` module entries mention
  annotations), `docs/verification/human-checks.md` (group DR-2, below), `docs/superpowers/specs/2026-11-24-drawings-design.md` (Status line: "… DR-1
  done (…). DR-2 done (<date>; human checks group DR-2 pending; R1: a sheet-millimetre layout beside the viewport's)."), `docs/metalui-gaps.md` (only if
  Task 12 logged `DR-2-a`)
- Group DR-2 checks: DR2-1 dimension a plate in Front and Top with the Dimension tool (a length, two corners horizontal and vertical by where you place,
  ⇧ aligned, a hole's diameter, a fillet's radius, an angle) and see ISO text above and parallel, then switch to ASME: unidirectional text in breaks;
  DR2-2 drag a dimension line and its text, nudge it, a short dimension's arrows outside, a small hole's diameter on a leader; DR2-3 baseline, chain and
  ordinate on a row of holes; DR2-4 a hole callout on a through, a blind, a counterbored and a countersunk hole; DR2-5 tolerances: ±, deviations, limits,
  reference, basic, and "Ø20 H7 (+0.021/0)", "Ø20 g6"; the general ISO 2768 class and the ASME table in the title block; DR2-6 an inch document in ASME
  (".250") and a comma decimal sign in ISO; DR2-7 change a width: dimensions follow; add a chamfer on a dimensioned edge: it turns warning-coloured with
  "?" and is listed with its reason; select it and click another edge to re-attach; DR2-8 save with a lost dimension, reopen: its last value with "?";
  the document isn't marked edited by the save; DR2-9 an isometric view refuses dimensions with the sentence and takes a note with a leader; a slanted
  edge refuses with decision 4's sentence; DR2-10 centre marks on face-on holes (and the view's toggle), a Centre Line on a side-on pin; DR2-11 export PDF
  and DXF of the sheet, open in Preview, Acrobat, LibreCAD and AutoCAD/TrueView: filled arrows, rotated ISO text, centre dashes, the DIMENSION and TEXT
  layers, no audit prompt; DXF of a view at 1:1 with annotations in laser or CAM software; DR2-12 group the feature under a dimension: it stays held;
  DR2-13 Linux and Windows: the PDF's SHA-256 equals the Mac's for the same annotated document; DR2-14 the tool keys D, H, M, L, N over the sheet.
- [ ] **Step 1:** docs.
- [ ] **Step 2:** `swift test` on macOS (16 "Test run with" lines, no "recorded an issue" or "failed after"); `XP_TRACK=dr-2 IMAGE=metalcreator-linux:dr-2
  scripts/linux-test.sh test` (16 lines; afterwards remove only this run's Docker volume and image); `swiftlint lint --strict` 0.
- [ ] **Step 3: Commit** "Docs: DR-2".
