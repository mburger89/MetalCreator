# Driving dimensions: ANSI dimensions on the model and in sketches

Status: agreed in conversation 2026-10-27; this document is for the user's review.

## 1. Purpose

The user wants to change the sizes that matter on a part ("the distance between two holes on a bracket, or the distance
between two edges") while looking at the part, without digging through a sketch or the node inspector. The reference is
SolidCraft 0.24 (x.com/CadcamManiac/status/2114900334342791513): the dimensions sit on the 3D part, a double-click opens a
box, a typed value rebuilds the part. SolidWorks calls this Instant3D; Fusion does it only inside sketches.

What the user decided (2026-10-27):

- **A dimension on the model is a window onto a number that already exists.** Editing it changes the number that made
  that geometry (a sketch dimension, a pattern's spacing, an extrude's depth, a hole's size). Nothing new "drives" the
  model from outside the graph, and nothing guesses which upstream number to change.
- **Every number that shapes a feature can show**: sketch dimensions and the features' own sizes (extrude depth, pattern
  spacing and count, hole Ø, fillet R, and so on), not only sketch dimensions.
- **Contextual, with pins.** Selecting a feature (in the view or its node in the graph) shows its dimensions on the part;
  selecting something else hides them. Any dimension can be **pinned** to stay visible while the user works on another
  feature.
- **Drawing a new dimension on the model** between two items that come from the same sketch adds that dimension to the
  sketch, as if drawn there. Between items no one sketch owns, there is nothing to edit: that is the read-only measure
  tool, **filed as future work** (§9).
- **ANSI first** (ASME Y14.5 look, §5). ISO 129 comes later as a style setting, so the look must be a swappable style,
  never hard-coded.
- **Inches and millimetres.** Both are offered (§6).
- **Nothing moves until Return.** Typing in a dimension's box changes nothing; Return commits; Esc cancels. The part
  "jumping" (moving early, flipping to a mirrored shape, the camera leaping) is the user's red flag (§7).
- Sketch dimensions are brought up to Fusion's level (§4): real dimension lines, a value box on placement, double-click to
  edit, centre-to-centre and edge-to-edge kinds.

Success: on the bracket, the user clicks the hole pattern, sees "60" between the holes and "2X Ø8" on a leader,
double-clicks 60, types 70, presses Return, and the holes are 70 apart in one undo step, with nothing else moving. A pinned
plate length stays in view while they work on the holes. The same works in inches. The file reopens with its pins and units.

Out of scope: the read-only measure tool between arbitrary model geometry (§9); a dimension that solves for an upstream
number it does not own; ISO and other styles (the style seam is in scope, the ISO style is not); GD&T, tolerances and
drawing sheets; dimensions on implicit geometry that the node does not describe (§3.4).

## 2. Context (what exists, 2026-10-27)

- **Sketch dimensions already drive** (sketcher spec `2026-10-08-constraint-sketcher-design.md` §3, §4, §7, §8; S5a-S5c,
  code done, human checks S5/S5b/S5c pending). `SketchDimension` (`kind`, `name` d1…, `value` mm or degrees, `isExposed`,
  `isDriving`, `angleSense`); `DimensionKind` `.distance(a,b)` (point-point, point-line with the line infinite), `.length`,
  `.radius`, `.diameter`, `.angle`. `SketchSolver` (Levenberg-Marquardt, warm-started from `Sketch.solved`, branch
  stability tested). The D tool (`SketchEditorModel+Dimensions`) creates a dimension at its measured value; the value is
  typed in the inspector (`DimensionField`, `DimensionRowView`, `setValue(_:of:)`, one "Change Dimension" step). Labels in
  the view are read-only `OverlayLabel` text (`SketchDimensionLabels`; sketcher Errata S5c: "the labels don't take the
  pointer").
- **Viewport overlay**: `ViewportOverlay` (lines, points, fills, labels) through `ViewportModel.showOverlay(_:)`; labels are
  MetalUI text placed by `overlayLabels(measuring:)` at measured sizes (`TextMeasure`), on macOS and SDL alike, hidden while
  the camera animates. No overlay element takes the pointer today.
- **Handles**: `HandleSpec` (`.linear`/`.radial` of a socket) declared by Extrude, Fillet, Chamfer; `HandleBuilder` makes
  `ViewportHandle`s; `AppModel.handleChanged` writes the socket with one coalesced, named undo step. This is the precedent
  for "a node declares something in the viewport bound to one of its inputs".
- **Picking and provenance**: B-rep faces and edges carry `TopoTag(node, item, role)` (`OCCTTagger`); `ViewportPicker` /
  `SDLViewportPicker` return `.face`/`.edge` per solid. A picked face's tag names the node that made it. Implicit meshes
  carry no such identity.
- **File format 9** (`GraphFile.currentFormatVersion`). Additive optional keys written only when present do not bump.
- **Units**: everything is millimetres internally (`CreatorGeometry`); there is no unit setting today.

## 3. Feature dimensions on the model

### 3.1 Who owns a dimension

A **feature dimension** is one number of one node, shown as a dimension on the part:

- a node **input** that holds a typed constant (extrude `depth`, a pattern's `spacing` and `count`, a hole's size, a fillet's
  radius, a box's size…), or
- one **dimension of a Sketch node's sketch** (driving or reference).

A node declares the feature dimensions it can show, and how to draw each, through a new declaration beside `HandleSpec`
(builder's naming; working name `DimensionSpec`), produced **at evaluation** from the node's actual inputs and outputs so that
each carries world-space geometry: its kind (linear, aligned/horizontal/vertical, radius, diameter, angle, count), its
anchor points or circle, and the input or sketch dimension it edits. It is data, like `HandleSpec`, and the viewport never
learns about the graph (the app shell turns specs into overlay items, as `HandleBuilder` does).

**A feature is a node plus its private chain** (my call, from the builder check): selecting a node shows its own
dimensions and those of every node upstream of it whose outputs feed **only** this chain (approved by the user, 2026-10-27,
with the other calls marked "my call" below) (a layout wired only into a
Hole Pattern, a Sketch wired only into one Extrude, a Place or cull between them). The walk stops at a node with another
consumer, and at graph parameters. Each number still belongs to exactly one node and is edited there; nothing guesses. So
clicking the hole pattern shows the layout's spacing and count beside the pattern's Ø, and clicking an extruded plate's face
shows its sketch's dimensions as well as the depth.

Tree-shaped inputs (my call): "NX Ø8" shows when one constant applies to N instances; a wired list that varies per instance
shows each instance's value as a reference. A pin names a node and an input or sketch dimension, never an instance.

Editability:
- an input holding a typed constant: **driving** (blue), editable;
- an input wired from a **graph parameter** (user, 2026-10-27): **driving** and editable; the edit changes the parameter
  (one undo step, "Change <parameter label>" per CLAUDE.md's undo-name rules, within the parameter's min/max), so every
  feature using it moves. The value box says so before Return: "Width (parameter, used by 3 features)". A pin on it names the
  node and input it was pinned from;
- an input wired from anything else (its value comes from another node): shown as **reference** (grey, in parentheses), not
  editable, with the source named on hover ("from Number 'width'"); *builder's call to add a jump-to-source later*;
- a sketch's reference dimension: reference, as in the sketch;
- an exposed sketch dimension that is wired: reference, as the sketch editor already treats it.

### 3.2 Coverage

Required for this project (the bracket path and the common features): Sketch (all its dimensions, drawn in 3D on its
plane), Extrude (depth), Revolve (angle), Hole Pattern / Boss-Pin Pattern / Slot Pattern (size, and the spacing and count of
their layouts), Linear / Grid / Circular Pattern (spacing, count, radius, angle), Fillet (R), Chamfer (distance), Box /
Cylinder / Sphere solids and their implicit twins (sizes), Shell (thickness). Other nodes may declare dimensions later; a
node that declares none simply shows none. *Builder's call*: the exact list of inputs per node, keeping to "numbers a
machinist would dimension"; settings like seeds, resolutions and blend radii of lattices are not dimensions.

### 3.3 Showing them

- **Contextual**: the dimensions of the **selected feature** show. A feature is selected by selecting its node in the graph,
  or by clicking a face or edge of the part in the view, which selects the node in the face's `TopoTag` (the nearest
  dimension-declaring producer up the chain when that node declares none; *builder's call* on the exact rule, documented).
  A click on empty space hides them. With several nodes selected, each shows its own.
- **Pinned**: any dimension can be pinned from its context menu ("Pin Dimension" / "Unpin Dimension"); a pinned dimension
  shows whatever is selected, with a small pin mark. Pins are saved with the document (§8). A pin whose node or sketch
  dimension is gone is dropped silently.
- **Inside a group**: the level the graph panel shows is the level whose features show, as handles do today.
- **While sketching**: the open sketch's own dimensions show as in §4; other features' pinned dimensions stay visible and
  ghosted with the scene; contextual ones hide.
- **Hidden while the camera animates**, as labels are today. Dimensions are never part of the ID pass, framing or
  `sceneBounds`.
- Placement: each dimension is placed by its spec off the part (extension lines off the geometry, the dimension line at a
  standoff), and kept readable from the current camera: text always faces the screen (unidirectional, §5), a dimension whose
  plane is seen edge-on (within ~10°) is hidden rather than drawn as a sliver. *Builder's call* on the standoff rule and on
  nudging overlapping labels apart; the bar is "no two labels overlap on the bracket from the default views".

### 3.4 Implicit geometry

Implicit parts have no face identity, so clicking them in the view selects nothing new; selecting an implicit node in the
graph still shows its declared dimensions (a sphere's Ø at its centre, a box's sizes along its edges, a cylinder's Ø and
height), placed from the node's own parameters and placement. Dimensions between implicit features are not possible.

### 3.5 Drawing a new dimension on the model

The D key outside sketch mode (or "Dimension" in the face/edge menu; *builder's call* on the entry point, D must not
collide with existing viewport keys) starts the model dimension tool:

1. Pick two items in the view: circular edges (their centres), straight edges, or vertices where available.
2. If both trace to **the same Sketch node** (a face or edge whose `TopoTag` role is `.side(loop:segment:)` of a profile
   from that sketch, or a projected edge in it), the tool adds the matching sketch dimension (centre-to-centre,
   edge-to-edge, point-to-line) to that sketch, at the measured value (nothing moves), then opens its value box at once
   (§7). It is one undo step ("Add Dimension").
3. Otherwise the tool says so in a chip ("These come from different features: a measurement tool is planned") and adds
   nothing.

If the new dimension would over-define the sketch it is added as a reference (§4.4).

## 4. Dimensions in a sketch

### 4.1 Drawing

Sketch dimensions are drawn as ANSI dimensions (§5) in the sketch's plane, replacing today's offset text labels: extension
lines, dimension line with arrows, text breaking the line; radius and diameter on a leader with a shoulder. The same drawing
code serves sketch mode and the model view.

### 4.2 The D tool

- Pick geometry as today. A value box opens at the pointer showing the measured value, selected. Typing replaces it; Return
  commits the value (§7); Esc cancels the whole new dimension (Fusion's behaviour; nothing was added).
- After Return, the dimension follows the pointer until a click places it. For a linear dimension, where it is dropped
  chooses horizontal, vertical or aligned, as in Fusion and SolidWorks.
- Right-click while placing offers Radius/Diameter and Driving/Reference.

### 4.3 New kinds

- **Centre to centre**: two circles or arcs (or a circle and a point) give the distance between centres. Picking a circle
  alone still gives its diameter.
- **Edge to edge**: two parallel lines give the distance between them (the solver keeps them parallel only if a constraint
  says so; the dimension measures along the first line's normal).
- **Horizontal and vertical** distances (point-point, centre-centre) as their own kinds, chosen by placement.
- **Equal diameters, 2X**: circles held equal by an Equal constraint with one diameter dimension show "2X Ø8" (count of the
  equal set). Display only; no new constraint.

These are new `DimensionKind` cases in `CreatorSketch` with solver residuals and analytic Jacobians, tested like the
existing kinds (branch stability included).

### 4.4 Over-defining

A dimension that would over-define the sketch is created as a **reference** (grey, in parentheses), as Fusion and Onshape
do, never as an error. Making it driving later goes through the existing conflict handling.

### 4.5 Editing in the view

A double-click on a dimension's text in the view opens its value box (§7), in sketch mode and on the model. This reverses
sketcher Errata S5c ("the labels don't take the pointer"); add an erratum there pointing here. The inspector's fields stay.

## 5. The ANSI style

A `DimensionStyle` value (builder's naming) holds every look decision; `ansi` is the only style built now, `iso` is later.
Nothing about the look is written outside it.

- **Text**: unidirectional (always horizontal on screen, reads from the bottom), centred in a break in the dimension line;
  when it doesn't fit between the extension lines, arrows go outside pointing in and the text sits outside on the dimension
  line's extension.
- **Arrowheads**: filled, length:width 3:1, constant on-screen size.
- **Extension lines**: a small visible gap from the geometry, running a little past the dimension line (ASME practice;
  commonly 1.5 mm gap and 3 mm overshoot at drawing scale; here constant screen points, *builder's call* on the values).
- **Leaders**: inclined line with a short horizontal shoulder; arrow on an edge; radial to a circle or arc.
- **Notation**: Ø before the size ("Ø8"), R for radius ("R17"), "NX" for N equal features ("2X Ø8"), angles in degrees
  ("45°"), reference dimensions in parentheses ("(70)"), an exposed dimension prefixed with its name as today
  ("width = 60") *builder's call on keeping that prefix in ANSI*.
- **Numbers** (ASME Y14.5 1.6): millimetres keep the leading zero and drop trailing zeros ("0.5", "60"); inches drop the
  leading zero and show trailing zeros to the precision (".50", "2.250"). No unit suffix on the dimension itself (the
  document's unit is stated once, §6).
- **Colour** from theme roles: driving, reference, conflict (red as today), selected, pinned mark. *Builder's call* on new
  roles vs reusing existing ones; never a hex outside `CreatorStyle`.
- **Line weight**: thin, as ASME dimension lines are thin against visible lines.
- **Size**: text and arrows a constant on-screen size; extension lines follow the model.

## 6. Units

- **Internal values stay millimetres.** Units are display and entry only; switching units changes no number in the model.
- **Per document**: Document Settings (or the View menu; *builder's call*) chooses Millimetres or Inches, saved with the
  document (§8). A new document uses the last unit chosen (an app preference). A file without one reads Millimetres.
- **Typing** follows the document's unit, and a suffix overrides it: "2 in", "2in", "2\"", "50 mm", "5 cm" (*builder's call*
  on the accepted spellings; at least in, ", mm). Arithmetic is not in scope.
- **Precision**: per document, defaulting to 2 places in inches and 1 in millimetres (*builder's call* on the defaults if
  ASME practice suggests better), applied by §5's number rules.
- **Where units show**: the dimensions and their value boxes, the sketch inspector's dimension rows and the pointer readout.
  Node inspector number fields stay in millimetres in this project (*noted as a known inconsistency*; converting the whole
  inspector is future work, §9).

## 7. Editing a value: nothing moves until Return

- The value box is a small text field over the dimension's text, showing the current value in the document's unit,
  selected.
- **While typing nothing changes**: no evaluation, no solve, no preview, no camera move.
- **Return** parses (§6), refuses a non-number, a value ≤ 0 for lengths, an angle outside the kind's range (today's
  refusals, in the box, red, box stays open), then commits **one undo step** ("Change Dimension") and evaluates.
- **Esc** or a click elsewhere closes the box with no change (unlike the inspector, focus loss does **not** commit here:
  the user's red flag is the part moving when they didn't press Return).
- **No jumping after Return**:
  - a sketch solve that converges to a mirrored or flipped configuration (the branch test the solver already has) is
    refused: the edit is not committed, the box stays open showing "This value would flip the sketch." *Builder's call* on
    detecting it (the existing branch-stability machinery);
  - a value that makes the feature fail (over-constrained, kernel refusal) is refused the same way with the node's message,
    and the model stays as it was: never a committed failing state behind a ghost. My call on the mechanism: commit,
    evaluate, and if the edited node or anything downstream of it now **errors** (warnings are not refusals), take the edit
    back invisibly (no redo entry) and reopen the box with the message. The box shows "Checking…" meanwhile and takes no
    input; the old geometry stays drawn until the new result is accepted, so a refused value never flashes on screen;
  - the solver has no runtime flip detector today (branch stability comes from the warm start); detecting a flip after
    Return is new work to size in the plan;
  - the camera does not move.
- Editing a pinned or contextual dimension is the same flow.

## 8. File format

All additive, optional, written only when present, so no version bump (the cable-ties/`showsLibrary` precedent), unless the
builder finds an older reader would silently lose user data, in which case bump to 10 and say why in the plan:

- the document's **unit** and **precision**, in `ViewState` (or a new optional document-settings key; *builder's call*);
- **pins**: a sorted list of pinned dimensions, each naming its node and its input name or sketch `DimensionID`, scoped like
  picks inside group definitions (§3.3), remapped by Group, Ungroup, Make Unique and paste as picks are;
- a sketch dimension's **label placement** and horizontal/vertical choice live in the sketch (new optional fields on
  `SketchDimension`); a feature dimension's placement is computed, never saved.

A file from before this opens unchanged, in millimetres, with nothing pinned.

## 9. Future work (filed, not built)

- **Measure tool**: a read-only dimension between any two model points, edges or faces, including ones no single number
  owns. Not driving.
- **ISO 129 style** (text above an unbroken line, aligned text) as a `DimensionStyle` choice.
- Node inspector number fields in the document's unit.
- Jump from a wired (reference) dimension to the node that drives it.
- Expressions in value boxes ("60/2", names).

## 10. Testing and checks

- Unit tests (Swift Testing): `DimensionStyle.ansi` number formatting (mm and inch rules, precision, Ø/R/NX/parentheses);
  unit parsing; new `DimensionKind`s' residuals, Jacobians and branch stability; each node's declared dimensions for known
  inputs (kinds, anchors, the input they edit); contextual/pinned visibility rules; the no-commit-before-Return rule (a typed
  draft changes no document and runs no evaluation); refusal of a flip and of a failing value leaving the document unchanged;
  pins and units round-tripping through `.mcgraph` and surviving Group/Ungroup/Make Unique/paste; a file without them.
- Headless render tests of a dimension (lines, arrows, text break) on macOS and SDL, as the overlay's tests do today.
- The bracket acceptance: the §1 success scenario, end to end, headless, in mm and inches, on a new fixture (my call): a
  plate from a Sketch, extruded, with a Hole Pattern over a Linear Pattern layout. The existing §7.2 bracket (Grid Points,
  graph parameters) gets a smaller test of the private-chain rule and of parameter-wired dimensions.
- Platforms: macOS, Linux and Windows (cross-platform rules in CLAUDE.md); any MetalUI limit met (hit-testing overlay text,
  an in-viewport text field) is filed in `docs/metalui-gaps.md` and sent to MetalUI, never worked around.
- Human checks: a new group **DIM** in `docs/verification/human-checks.md` (the look against ASME practice, contextual and
  pinned display, editing with no jump, inches, Linux and Windows), and a CLAUDE.md project-state line.

## 11. Errata to add when this lands

- Sketcher spec Errata (S5c): labels take the pointer for double-click editing and are ANSI dimensions, pointing here.

## Errata (plans, 2026-10-27)

Decisions taken in the plans (`docs/superpowers/plans/2026-10-27-dim-overview.md`, `dim-1` to `dim-4`) that change or sharpen
this spec:

- **File format 10**, bumped once in DIM-1: new `DimensionKind` cases can't decode in a format-9 reader, and an older reader
  would drop units, pins and label points on save. 10 covers units, the new kinds, `labelPoint` and `dimensionPins`.
- **Units live on the top-level `Graph`** (key `units`), not `ViewState`: changing them is an undoable step ("Change Units",
  "Change Precision") and marks the document edited.
- Entry point: **View ▸ Units** (Millimetres, Inches) and **View ▸ Precision** (1 to 0.0001). Choosing a unit resets precision to
  its default (1 place mm, 2 in). The app remembers the last unit for new documents.
- A parameter edit's undo name is **"Change Parameter"** (§3.1's "Change <parameter label>" would put typed text in it).
- **The private chain never crosses a solid, implicit or mesh wire**; an `isOutput` node counts as another consumer; the walk stops
  at Graph Parameter and Group Input nodes.
- **A face click selects a feature only in Final preview**; empty space clears the selection; a tagless face does nothing.
- **Coverage (§3.2):** no B-rep Box, Cylinder, Sphere or Shell node exists, so only their implicit twins are covered. Rectangle and
  Circle are added. A 360° Revolve or Circular sweep shows no angle. Per-instance reference dimensions stop at 24.
- **An exposed sketch dimension wired from a graph parameter is editable** (through the parameter), not a reference.
- **Pins are kept on their level's graph** (top level or a definition) and show only at that level. Removing a node removes its
  pins (undo restores them). A dangling pin stays in the file and shows nothing.
- **New theme roles** `dimensionDriving` and `dimensionReference` (group "Dimensions"). Sketch driving dimensions change colour:
  in Dracula, from the foreground (white) to cyan.
- **Ø is U+00D8**, replacing "⌀" (U+2300) everywhere, the readout included.
- **Circle-pick rule (§4.3):** a circle or arc alone gives its diameter or radius at once, placed by the next click; a second
  circle, arc or point turns it into a centre distance.
- **A typed value locks the orientation** while placing (moving the pointer no longer switches horizontal/vertical/aligned).
- **The model tool (§3.5) makes two undo steps:** "Add Dimension" (at the measured value), then "Change Dimension" on Return.
  Esc on its box keeps the measured dimension.
- **Double-click needs MetalUI gap DIM-a** (`SpatialTapGesture.Value.clickCount`); until it lands a double-click opens no box in
  the running app (model tests pass the click count).
- **A circle or arc with a line** gives the distance from its centre to the line, in the sketch D tool and the model tool alike.
- **The model tool leaves the selection alone.** The new dimension shows while its box is open; afterwards only by the usual
  rule (in a selected feature's chain, or pinned).
