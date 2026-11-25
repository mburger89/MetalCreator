# Engineering drawings — design

Status: approved for planning (2026-11-24). Sub-projects DR-1 to DR-5, built in that order. None done yet.

## Intent

MetalCreator makes parts that people want built: machined brackets, laser-cut plates, printed housings, boards
in enclosures. Today the only things a factory gets from it are STEP, STL and 3MF. That's enough for a 3D printer
and for a shop that programs from STEP, but most shops, and every inspector, work from a **drawing**: orthographic
views of the part, its dimensions with tolerances, the surface and geometric requirements, and a title block saying
what it is, what it's made of and which revision it is. A laser or waterjet shop also wants a **DXF** of the flat
outline at true size.

The user asked for "a 2D drawing mode so that we can create all the CAD drawings necessary for factories or others to
make our CAD models in real life" (2026-11-24). They asked for question rounds to be skipped on this project, so every
call below is mine unless marked as theirs.

What makes it MetalCreator's: the drawing follows the graph. A view shows an Output's part, so changing a width in
the graph redraws every view and re-measures every dimension. A dimension is tied to the part's edges by the same
stable names picks already use, so it keeps holding the right edge through edits. When it can't, it says so and is
never silently re-attached to a different edge.

## Goals

1. **Sheets.** A document holds any number of drawing sheets (ISO A4 to A0, ANSI A to E, portrait or landscape),
   each with a border, a zone grid and a title block whose fields are partly automatic (scale, sheet n of m, date,
   mass) and partly typed (title, drawing number, material, revision, drawn by).
2. **Views from the model.** Base views in standard orientations, projected views placed by dragging from a parent
   (first or third angle), section views from a cutting line, detail views from a circle, and auxiliary views. All
   are computed with exact hidden-line removal, so circles stay circles. Visible, hidden, tangent and silhouette lines
   are drawn in ISO 128 line types and weights.
3. **Associative annotation.** Linear, aligned, baseline, chain, ordinate, radius, diameter, angle, chamfer and hole
   dimensions, measured from the model. Tolerances: general (ISO 2768), ±, deviations, limits and ISO 286 fits.
   Centre marks and centre lines, notes with leaders, datum features, feature control frames (ISO 1101 / ASME Y14.5),
   surface texture symbols, balloons and a parts list.
4. **Faithful output.** A vector PDF where a 1:1 view printed at 100 % measures true, and a DXF of the sheet or of
   one view at 1:1. The screen, the PDF and the DXF show the same thing.
5. **Everywhere.** Drawing mode works on macOS, Linux and Windows, like the rest of the app.

## Non-goals (for DR-1 to DR-5)

- Shaded or rendered views, exploded assembly views, and weld symbols.
- Sheet-metal flat patterns. They are the most valuable next step for laser shops. It's a feature-modelling job
  (bends, k-factor) that the graph doesn't have yet. A flat part's DXF at 1:1 (goal 4) covers plates now.
- Auto-dimensioning (a "dimension everything" button).
- Free 2D drafting on the sheet beyond notes, leaders and sketch lines for annotation.
- DWG, and printing from the app (the PDF prints).
- Drawings of meshes (Mesh items, lattices, imported STL). A view of one is refused in words ("Drawings show solids,
  sheets and curves; this Output holds a mesh. Mesh to Solid makes a solid of a small mesh."). Hidden-line removal of
  millions of triangles isn't useful on paper.
- Editing the model from the drawing (a drawing dimension is never driving).

## Anti-goals (failures even if it works)

- **A dimension that silently shows the wrong thing after an edit.** Re-attaching to a nearby edge, keeping an old
  value, or quietly dropping a dimension. A dimension whose reference is lost is drawn in the warning colour, listed,
  and its value shown as it was with "?" appended. Exports warn about it.
- **A scale that lies.** A view marked 1:2 must measure half size in the PDF at 100 % and in the DXF in millimetres.
- **Screen and paper disagreeing** on where text and lines fall.
- **A drawing that can't be opened by a shop.** The PDF must open in any viewer, the DXF in LibreCAD, QCAD, AutoCAD
  and the common laser software (they read ASCII DXF R2000).

## Approaches

**A. Sheets are document data; views reference Output nodes (chosen).** The file gains a `drawings` table beside the
graph. A view names an Output node, and the app projects that Output's last result. Annotation is placed by hand in a
drawing editor, the way every production CAD does it. The graph stays a model of the part, and the drawing is a
document about it. Cost: a new editor and a new saved table (format 17).

**B. Views and dimensions as graph nodes.** A View node takes a solid and gives a 2D drawing value, and a Sheet node
lays views out. That's attractive in a node app, but placing dozens of dimensions and notes by hand doesn't fit a
graph: each would be a node, wired and positioned twice, once on the canvas and once on the sheet. Rejected.
Generated content that is truly parametric (a parts list from Outputs) is computed in A anyway.

**C. Export only: a "make a drawing" command that writes a PDF of standard views.** Cheap, but a shop can't build
from undimensioned views. It would be thrown away the day dimensions arrive. Rejected.

**Hidden lines: exact (chosen) vs. projected tessellation.** OpenCascade's exact `HLRBRep_Algo` keeps lines,
circles and ellipses as curves. The DXF needs them as true ARC and CIRCLE entities, and dimensions need true centres.
Projecting the display mesh is faster on huge parts, but it gives polylines and only approximate silhouettes. It's
parked as a fallback for very large parts (`HLRBRep_PolyAlgo`), not built.

## Standards

The drawing standard is a per-drawing setting with two values. **ISO** is the default (call: the app's users so far
use mm, and ISO is the wider default; a US shop picks ASME):
- **ISO:** first-angle projection, ISO 128 lines, ISO 129 dimensions (text aligned with the dimension line, above it),
  ISO 2768-mK general tolerances, ISO 1101 GD&T, ISO 21920-1 surface texture, ISO 7200 title block, ISO 5457 sheet
  borders, ISO 5455 scales, ISO 3098 lettering heights.
- **ASME:** third-angle projection, ASME Y14.2 lines, Y14.5-2018 dimensioning and GD&T (unidirectional text, no
  concentricity or symmetry symbols), title block per Y14.1.

Switching the standard restyles everything. It doesn't change what's attached to what.

Line weights (ISO 128-20, line group 0.5): thick 0.5 mm (visible outlines, cutting-plane ends), thin 0.25 mm (hidden,
tangent, centre, dimension, extension, hatch, leaders). Hidden lines are dashed 3 mm with 1.5 mm gaps (12d and 6d at
0.25 mm) and centre lines are long dash and dot, both scaled by the sheet, never by zoom. Lettering is 3.5 mm on A0 to
A2 and 2.5 mm on A3 and A4 for dimensions and notes, 5 mm and 7 mm for titles and view labels. All of these are named
constants in one `DrawingStyle` per standard, so the plan can pin them.

## Model

Everything a drawing saves is plain value types in a new portable module, **`CreatorDrawing`**. It depends on
`CreatorGeometry` and `CreatorKernel` (for the projected-geometry types and picks) and never imports OCCT, MetalUI or
CreatorGraph. `CreatorGraph` depends on it to save, as it does on `CreatorSketch`.

- `DrawingDocument`: the drawing settings (standard, default scale, general tolerance, title-block defaults) and the
  sheets in order.
- `DrawingSheet`: id, name, size and orientation, the title block's typed fields, its views and annotations.
  Coordinates are sheet millimetres, origin bottom left, y up.
- `DrawingView`: id, kind (base, projected, section, detail, auxiliary), `source` (an Output node's `NodeID`;
  inside groups is not allowed: Outputs are top level), orientation (a standard name or an exact frame), scale (one of
  ISO 5455's preferred scales or a custom ratio), position (its centre on the sheet), parent and alignment (a projected
  view stays aligned with its parent along its axis when either moves), display flags (hidden lines, tangent edges,
  label shown), and its kind's own data (section line, detail circle).
- `DrawingAnnotation`: id, kind and payload, its anchors and its placement on the sheet.
- `DrawingAnchor`: what an annotation is attached to. A view id plus one of:
  - an edge, by `EdgePick` tags;
  - a vertex, as an edge end;
  - a circle's centre;
  - a face's projected outline (a silhouette), by `FacePick`;
  - a point on the sheet, for free annotations.
  Names are the model's own stable tags, resolved by a stricter rule than a graph pick's (decision 2 below: a
  dimension never takes a guess).

**Saving.** The top-level graph file gains an optional `drawings` key, written only when there is a sheet, with sheets,
views and annotations sorted by id. That's **file format 17**: an older build can't read it, and files of format 1 to
16 open unchanged. Drawings are top-level document content, so `DocumentModel.content` (and dirty state) includes them.
Every drawing edit is one named undo step through the document's undo stack ("Add View", "Move View", "Delete View",
"Change Scale", "Add Sheet", "Rename Sheet", "Edit Title Block", "Add Dimension", "Move Dimension", "Add Note"…; names
never include typed text). Copy and paste of views and annotations stays within a drawing.

Group, Ungroup and Make Unique already rename picks whose faces they move. They rename drawing anchors in the same pass,
so a view of an Output whose part is regrouped keeps its dimensions.

## Projection (the kernel)

`Kernel.projection(of: Solid, curves: [Curve], frame: ProjectionFrame, options: ProjectionOptions) -> Projection2D`
(refused by default and in `FakeKernel`, except that `FakeKernel` projects its boxes along the axes so editor tests
run without OCCT). The projection frame is the view direction and the up direction, orthographic only. The result is
in model millimetres in the view's plane, before scale. A `Projection2D` is a list of `ProjectedLine`s:
- **visibility:** visible or hidden;
- **class:**
  - sharp: an edge between faces that meet at an angle;
  - smooth: a tangent edge;
  - outline: a silhouette of a curved face, which has no model edge;
  - sheet boundary;
  - curve;
- **geometry:** an exact 2D line, circular arc or elliptic arc where the projection is one, else a polyline within the
  sheet tolerance (0.01 mm at 1:1, scaled with the view);
- **source:** the model edge index (OCCT map order, so `Topology` names it) or, for an outline, the face index.

The OCCT side is `HLRBRep_Algo` over the shape, read edge by edge through `HLRBRep_Data`, so each visible or hidden
piece keeps its source edge. This is what anchors need, and `HLRBRep_HLRToShape` throws it away. The shim file is
`cocct_projection.cpp`, and TKHLR joins the linked libraries on all three platforms. It polls `occt_cancel`. The app
computes projections off the main actor through a `ProjectionCache` (keyed by solid identity, frame and options;
512 MB, least recently used first), so an orbit of the 3D view or a redraw of the sheet costs nothing. An edit
re-projects only the views whose Output changed. While a projection is pending the old one stays drawn, faded.

**The planner should spike `HLRBRep_Data` first:** the source mapping, how silhouettes report their face, and the time
on the bracket. The fallback, if per-edge reading fails, is to run `HLRBRep_HLRToShape` and match its edges back by
geometry. That's worse but workable.

## Drawing mode (the app)

- **Entering.** The top bar gets a segmented **Model | Drawing** switch (View ▸ Drawing, ⌘⇧D). In Drawing, the 3D
  viewport's area shows the sheet instead. The graph panel stays (it can be hidden), so editing the model with the
  drawing in view works, and the drawing updates after each evaluation. Sketch mode, picks, Measure and the control-net
  mode belong to Model and end when Drawing is entered.
- **Sheet canvas** (new module `CreatorDrawingEditor`, like `CreatorSketchEditor`: MetalUI views over a
  `@MainActor @Observable DrawingEditorModel` that holds all the behaviour, graph-free, edits leaving as commits the app
  stores). Pan and zoom follow the graph canvas (scroll pans, ⌘-scroll or a pinch zooms, a middle drag pans). F fits
  the sheet. A click selects a view or an annotation, a drag moves it (projected views slide along their alignment),
  Delete removes it, and arrows nudge it. Hover highlights the view line under the pointer, which is how dimensions
  pick.
- **Sheet tabs** along the canvas's foot: add, rename, duplicate, delete, reorder.
- **Toolbar** in the top bar (as the sketch toolbar is, with the same "More" overflow): Base View, Projected View,
  Section, Detail, Auxiliary, Dimension, Hole Callout, Centre Mark, Centre Line, Note, Datum, Feature Control Frame,
  Surface Finish, Balloon, Parts List. Each sub-project adds its own tools.
- **Inspector.** In drawing mode the inspector shows the selection's properties: a view's source, orientation, scale,
  display flags and label; a dimension's tolerance and text; the sheet's size and title block when nothing is selected.
- **Colours.** The sheet is drawn as paper: three new theme roles, `drawingPaper` (white), `drawingInk` (black) and
  `drawingHighlight` (the theme's selection colour), the same in every built-in theme. The screen then matches print,
  as other CAD apps do on a dark UI.
- **Text.** Lettering uses the PDF's font metrics (below) for layout everywhere. The screen draws the same strings at
  the same positions with the app's sans-serif, so a line of text has the same width on screen and paper, and layout
  never measures with the screen font.
- **MCP.** Out of scope until DR-5, which adds read tools (sheets, views, dimensions with their state) and export.

## Export

- **PDF** (DR-1): our own `PDFWriter` in `CreatorDrawing`, PDF 1.7, one page per sheet at true size (mm × 72 / 25.4
  points). It writes vector paths with ISO line widths and dash patterns, filled arrowheads and hatching, and text in the
  standard Helvetica font with WinAnsi encoding and no embedding. Helvetica's metrics are a table in the module, from
  Adobe's public AFM. Ø, ±, °, × and µ are in WinAnsi. GD&T and surface symbols are drawn as vector geometry from our own
  `DrawingSymbols`, never as font glyphs. A typed character outside WinAnsi is replaced with "?" and the export warns
  once, naming the text. Embedding a font subset is parked. Content streams are uncompressed and the object order is
  fixed, so the bytes are identical on every platform, and a digest test pins them.
- **DXF** (DR-1 for geometry, DR-2 adds annotation): our own `DXFWriter`, ASCII DXF R2000 (AC1015), `$INSUNITS` 4 (mm).
  Layers: VISIBLE, HIDDEN (linetype DASHED), TANGENT, CENTER (linetype CENTER), DIMENSION, TEXT, HATCH and FRAME. It
  writes true LINE, ARC, CIRCLE and ELLIPSE entities, LWPOLYLINE for the rest, TEXT for notes, and dimensions as plain
  geometry plus text (exploded, the most portable form). Two modes:
  - **Sheet:** the whole sheet, in sheet millimetres.
  - **View at 1:1:** one view, in model millimetres, with no border or title block. Its annotations are included only
    when asked. This is the laser-cutting file.
- **The export sheet** (the existing one) gains PDF and DXF while drawing mode is up. Export evaluates the graph first,
  as the streamed export does, and refuses when an Output a view shows has failed, naming it. Lost anchors don't block
  an export. The export warns about them, listing them.

## Sub-projects

### DR-1: Sheets, views and PDF

The drawing model and format 17, drawing mode with the sheet canvas, tabs, inspector and theme roles, and sheets with
border, zones and title block (ISO 7200 or Y14.1 fields; mass from volume × a typed density). Base views in the six
standard orientations plus the two isometrics, and projected views by drag, first or third angle by the standard.
Scale per sheet with a per-view override, the first view's scale picked as the largest preferred scale at which it
and two projected views fit. The `Kernel.projection` call, the shim and TKHLR on all three platforms, and the cache.
ISO 128 line drawing, hidden lines off by default and tangent lines on, both switchable per view. PDF export, and DXF
export of geometry in both modes. Human checks group DR-1 include printing a 1:1 view at 100 % and measuring it, and
opening the DXF in LibreCAD or QCAD. Benchmark rows `drawing-1`, the bracket's four views projected from cold (target
under 1 s), and `drawing-2`, a pan and zoom of that sheet (target 60 fps warm).

### DR-2: Dimensions and notes

Associative dimensions:
- the types: linear horizontal, vertical and aligned, baseline and chain, ordinate, radius, diameter, angle, chamfer
  (C2 or 2 × 45°), and the hole callout (Ø and depth, or THRU, read from a cylindrical face; a counterbore or
  countersink when the faces stack that way);
- how they're placed: by picking view lines;
- what they measure: the projected distance in the view's plane, from the model's exact geometry, never from the
  polylines;
- how they're drawn: in ISO 129 or Y14.5 style, with text moved clear of the extension lines and arrows flipped
  outside when the space is short.

Tolerances:
- the general one (from the title block's ISO 2768 class, applied silently);
- symmetric, deviation, limits, reference (in parentheses) and basic (boxed);
- ISO 286 fits for holes F, G, H, JS, K, N and P and shafts f, g, h, js, k, n, p and s at IT5 to IT11. Deviations come
  from the standard's formulas and its table, and are shown as "Ø20 H7" with "(+0.021/0)" optional.

Also centre marks (automatic for circles seen face on, a per-view option) and centre lines (cylinders seen side on),
notes and leaders, lost-anchor handling (the anti-goal), and DXF annotation. The existing viewport dimension layout
(`DimensionLayout`, `DimensionStyle`) is screen-space and ANSI. The plan decides whether to generalise it to sheet
millimetres or write a drawing layout beside it. Either way there must be one placement rule per standard, shared by
screen, PDF and DXF.

### DR-3: Sections, details and auxiliary views

- **Section views** from a cutting line drawn on a parent view: straight, or stepped through several points (an offset
  section).
  - The cut is made on a copy of the part by the half-spaces the line defines, and the remainder is projected.
  - Cut faces are hatched per ISO 128-50: thin lines at 45°, the spacing by the sheet, each part of an assembly at its
    own angle. Hatch boundaries come from `Kernel.section` and the existing triangulator's regions.
  - A sheet (open surface) cut shows its cut edge and no hatch.
  - The cutting-plane line has thick ends and arrows on the parent, and the label is "SECTION A-A" with its scale.
- **Half sections and broken-out sections:** parked.
- **Detail views:** a circle on the parent, shown magnified and clipped to the circle from the parent's exact
  projection, so they need no new hidden-line run. Labelled "DETAIL B (5 : 1)".
- **Auxiliary views:** projected perpendicular to a picked edge of the parent.
- **Break lines** for long parts (a view shortened, its dimensions still reading true): included if the plan finds
  them cheap, else parked.

### DR-4: GD&T and manufacturing symbols

- **Datum feature symbols** (A, B, C…) attached to a line, an extension line or a dimension.
- **Feature control frames** with:
  - the ISO 1101 characteristics: straightness, flatness, circularity, cylindricity, line and surface profile,
    parallelism, perpendicularity, angularity, position, concentricity and coaxiality, symmetry, circular and total
    run-out. ASME omits concentricity and symmetry.
  - a diameter zone and the material modifiers Ⓜ, Ⓛ and Ⓟ;
  - free state Ⓕ and tangent plane Ⓣ;
  - up to three datum references with modifiers;
  - composite frames.
- **Rules checked as warnings:**
  - form tolerances take no datum;
  - orientation and location need one;
  - a position tolerance's feature should be located by basic dimensions;
  - an unknown datum letter.
- **Surface texture symbols** (ISO 21920-1: basic, material removal required or prohibited, Ra or Rz value, lay
  direction) and a general surface note in the title block.
- **Edge-break and general notes.**

Every symbol is vector geometry in `DrawingSymbols`, pinned by tests that check its strokes.

### DR-5: Assemblies, revisions and the rest

- **A view of several Outputs at once:** the Final preview's parts, each its own body for hidden lines, so parts hide
  each other.
- **Balloons and the parts list:** balloons attached to parts, and a parts-list table (item, name from the Output,
  quantity, material, an optional part number) kept in step with the balloons.
- **Revisions:** a revision table, with revision letters bumping on demand.
- **Templates:** drawing templates (sheet size, title-block defaults, company name and logo from the images table)
  saved as an app preference.
- **Other exports:** SVG export, multi-sheet PDF in one file (DR-1 already writes several pages), and MCP read and
  export tools.

## Constraints

- **Code rules** (CLAUDE.md applies throughout):
  - OCCT stays behind `Kernel`, under `OCCTKernel.serialized`;
  - no CoreGraphics, CoreText or Metal outside `#if canImport` blocks;
  - nothing iterates a dictionary where order reaches output;
  - every message is a full sentence in the app's voice.
- **Tests:**
  - **Test target count:** `CreatorDrawing` and `CreatorDrawingEditor` get test targets. That makes 16 "Test run with"
    lines, so the pass rule, `EXPECTED_TEST_RUNS` in CI, `scripts/linux-test.sh` and CLAUDE.md change together. The
    plan may fold the editor's tests into one target and make it 15.
  - **Export tests:** PDF and DXF bytes are pinned per platform by digest tests. A small reader in the tests re-parses
    the PDF's cross-reference table and the DXF's entity list, so a test checks structure, not just bytes.
- **Untrusted input:** none new. A drawing reads only the document and the model.
- **Performance:** a projection runs off the main actor and is cancellable. The sheet draws only what is visible at the
  current zoom (cull by view bounds), and a steady frame skips unchanged views (`.equatable()`), as the graph canvas
  does.

## Decisions after the builder check (2026-11-24, all mine)

1. **Projected views store their direction.** When a projected view is made, its direction is derived from where it
   was dropped relative to its parent under the drawing's standard, and then stored explicitly. Switching the
   standard keeps every view's content (direction, anchors) and mirrors its position across its parent, so a
   first-angle right view becomes a third-angle right view on the other side. Annotation placements are stored
   relative to their view, so they move with it. Nothing attached changes.
2. **A dimension holds only an exact reference.** Drawings get their own resolver, `DrawingAnchorResolver`, over
   `Topology`. It is stricter than a graph rule:
   - **Held:** an exact tag match, or a narrowed match (`EdgeKey.narrowed`) that finds exactly one edge.
   - **Held, measuring the run:** an edge that has been split into pieces continuing one another as one run. The
     run's `runCount` is unchanged, and the dimension measures the whole run.
   - **Lost, shown with "?":** everything else, in the warning colour and listed. That covers a guessed `FacePick`, two
     operands that both fit, a key that matches several edges or none, and a run count that changed.
   It never chooses. Picking again (select the dimension, then click a line) re-attaches by hand.
3. **Units follow the document.** Dimensions use the document's units and precision (format 10's setting), and each
   dimension can override the precision.
   - **Zeros:** ASME drops the leading zero in inches (.250) and keeps it in mm (0.25).
   - **Decimal sign:** a point by default, with a comma as a drawing setting (ISO allows both).
   - **General tolerance:** ISO's is the ISO 2768 class (f, m, c, v, plus H, K or L for geometric tolerances). ASME's
     is a title-block table by number of decimals, typed by the user. The defaults are ±0.5, ±0.1 and ±0.05 mm, or
     ±.03, ±.010 and ±.005 in.
   - **Fits:** ISO 286 fits work in an inch drawing, with the deviations computed in mm and shown converted.
   - Dual dimensioning is parked.
4. **No foreshortened numbers.** A dimension is placed only when the geometry it measures is parallel to the view
   plane (projected and true length agree within 1e-9 relative). Otherwise it's refused at the pick: "This edge isn't
   square to the view, so its length here would be foreshortened. Dimension it in a view that sees it face on, or in
   an auxiliary view." Radii and diameters need their circle face on, and angles need both lines parallel to the
   plane. Isometric views take notes, balloons and leaders but no dimensions (isometric dimensioning is parked). A model
   edit that tilts a held dimension's geometry out of the plane makes it lost, with that reason.
5. **Meshes are left out, not refused.** A view draws an Output's solids, sheets and curves, and warns about the rest:
   "This view leaves out the Output's 3 meshes; drawings show solids, sheets and curves." That covers a KiCad board's
   VRML components. Only an Output with nothing drawable is refused, with the sentence under Non-goals.

Smaller calls:
- **PDF bytes:** identical on every platform, so one digest.
- **Title-block date:** a typed field, filled in with the creation date when a sheet is made.
- **`drawingHighlight`:** a fixed blue (#1F6FEB), the same in every theme.
- **A view whose Output is deleted:** it stays as an empty frame saying "The Output this view showed was removed.",
  its anchors are lost, and undo brings it back.
- **A lost dimension's last good value:** written into the annotation when the file is saved, never as an edit of its
  own, so evaluations don't mark the document changed.
- **Screen text:** each glyph is placed at Helvetica's advance.

## Left to the builder

- How to split the editor's files, and the internal geometry types for 2D curves on the sheet.
- How much of `DimensionLayout` to reuse.
- The exact ISO 286 table layout in code.
- The tab and toolbar visuals, within the existing chrome's rules.
- The order of tasks inside each sub-project.
