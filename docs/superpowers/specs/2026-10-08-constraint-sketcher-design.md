# MetalCreator — Constraint Sketcher Design (sub-project 6)

- **Date:** 2026-10-08
- **Status:** Draft, awaiting review
- **Parent spec:** `2026-10-07-metalcreator-vertical-slice-design.md` (sub-project 6 in §2). Everything there is still binding: Swift 6, Swift Testing, Dracula visual language, rule-based naming, MetalUI gaps fixed in MetalUI.

## 1. Intent

The sketcher adds Fusion-style constraint sketching to MetalCreator **as a node**. A **Sketch node** holds 2D geometry drawn on a plane, held in place by geometric constraints and named dimensions. It outputs the closed regions as a **list of profiles**, which broadcast into Extrude, Revolve and Loft like any other profile node. Selected dimensions can be **exposed as input sockets**, so graph parameters drive the sketch, keeping the node-graph promise of cheap variants without rework.

**Decisions taken in the brainstorm (user-confirmed):**
- **Where:** sketching happens **in the 3D viewport** (built on M4), not on a separate canvas.
- **Output:** **many regions, as a list.** Closed loops inside other loops become holes; construction geometry is never output.
- **v1 scope:**
  - The core geometry: lines, arcs, circles, points, construction.
  - The core constraints and dimensions.
  - **Projecting model edges.**
  - **Sketch fillet, trim and extend.**
  - **Mirror and pattern.**
  - Splines are deferred.
- **Dimensions:** promoted to sockets **on demand** ("Expose as input").
- **Solver:** **approach A**, a numeric Levenberg–Marquardt solver with decomposition into connected components and warm start from the last solution. It is pure Swift.

## 2. Architecture

| Target | Depends on | Purpose |
|---|---|---|
| `CreatorSketch` (new) | `CreatorGeometry` only | Sketch model, solver, DOF/conflict analysis, region finding, editing commands. Pure Swift, no graph, kernel or UI types. |
| `CreatorKernel` / `COCCT` / `CreatorOCCT` (changed) | — | `Profile2D` gains holes; the shim builds faces with inner wires; `TopoRole.side` gains a loop index. |
| `CreatorGraph` (changed) | — | `ConstantValue.sketch(Sketch)`; `GraphFile.currentFormatVersion` bumped. |
| `CreatorNodes` (changed) | + `CreatorSketch` | **Sketch** node and **Plane from Face** node. |
| `CreatorSketchEditor` (new) | `CreatorSketch`, `CreatorViewport`, `CreatorKernel`, MetalUI | The in-viewport editor: `SketchEditorModel`, tools, rendering overlay, inspector sections. |

**Boundary rules:**
- `CreatorSketch` never imports anything but `CreatorGeometry` and Foundation.
- The editor's logic lives in `@MainActor @Observable SketchEditorModel`, unit-tested without a GPU.

## 3. Sketch model (`CreatorSketch`)

All model types are `Sendable`, `Hashable` and `Codable`, and they are saved inside the `.mcgraph` file.

```swift
public struct Sketch {
    public var plane: SketchPlaneSource            // .fixed(Plane) | .wired (from the node's `plane` socket)
    public var entities: [SketchEntityID: SketchEntity]
    public var constraints: [SketchConstraintID: SketchConstraint]
    public var dimensions: [DimensionID: SketchDimension]
    public var solved: [SketchEntityID: SolvedState]   // warm-start positions from the last good solve
}
```

**Entities.** Each has an `isConstruction` flag.

| Entity | Unknowns |
|---|---|
| `.point(Vector2)` | x, y |
| `.line(start: PointID, end: PointID)` | none (its points carry them) |
| `.arc(center: PointID, start: PointID, end: PointID)`, counter-clockwise | none; radius consistency is an implicit constraint |
| `.circle(center: PointID, radius: Double)` | radius |
| `.projected(ProjectionSource)` | none (fixed) |

`ProjectionSource` holds an `EdgePick` (the same tag-subset pick type M3 uses for Edges by Tag) plus the cached 2D geometry from the last resolve.

Lines and arcs **share endpoint points**, so coincidence at a shared endpoint is structural, as in SolveSpace. Coincident constraints are only needed between points that are not shared.

**Constraints:**

| Constraint | Applies to |
|---|---|
| coincident | point–point |
| point on entity | point on line, arc, circle or projected edge |
| horizontal, vertical | line, or point–point |
| parallel, perpendicular | line–line |
| tangent | line–arc/circle, arc/circle–arc/circle |
| equal | lengths or radii |
| midpoint | point–line |
| concentric | arc/circle–arc/circle |
| symmetric | two points about a line |
| fix | point |

**Dimensions:**

| Field | Values |
|---|---|
| kind | distance (point–point, point–line), length (line), radius, diameter, angle (line–line) |
| `name` | auto `d1`, `d2`, …; user-editable; unique per sketch |
| `value` | mm or degrees |
| `isExposed` | when true, the dimension becomes an **input socket named after it** on the Sketch node, and a wired value overrides the stored one |
| `isDriving` | when false, the dimension is a **reference**: it measures, doesn't constrain, and appears in the node's `measurements` output |

**Commands** (`SketchCommands`) are pure functions `(Sketch, arguments) -> SketchEdit`. A `SketchEdit` holds the new sketch plus a description for undo.

- **Trim / extend:** split at intersections and remove or extend the picked span; keep coincident and point-on constraints on the new endpoints.
- **Fillet:** two lines meeting at a point become two trimmed lines plus a tangent arc, with a radius dimension.
- **Mirror:** copy the entities about a line, adding symmetric constraints.
- **Linear and circular pattern:** copy the entities, adding equal and distance (linear) or concentric and angle (circular) constraints. The count is a command argument, not a live socket, in v1.

## 4. Solver (`SketchSolver`)

**Formulation.**
- Unknowns are free point coordinates and circle radii; fixed and projected geometry are constants.
- Each constraint and each *driving* dimension contributes residuals, scaled so millimetre and angle residuals carry comparable weight.
- Each constraint provides its residuals and an **analytic Jacobian**; there are no finite differences.

**Algorithm.**
1. **Decompose** the constraint graph into connected components and solve each independently, in a fixed order sorted by smallest entity ID.
2. **Warm-start** from `solved`, falling back to the drawn positions.
3. Run **Levenberg–Marquardt** with dense QR.
   - Converged: residual below 1e-9 mm, or step below 1e-12.
   - Limit: 200 iterations.
4. **Drag mode:** dragged coordinates become heavily weighted soft targets, not hard constraints, so constrained geometry slides along whatever freedom it has.

**Result** (`SketchSolution`):
- `status`: one of
  - `.solved`
  - `.underConstrained(dof: Int)`, still a usable output
  - `.overConstrained(conflicts: [SketchConstraintID])`
  - `.failed(reason: String)`
- Per-entity `freedom` (`.free`, `.fixed`, `.conflicting`) from **rank-revealing QR** of the Jacobian: entities that touch the null space are free.
- `conflicts` is the **minimal set** of constraints whose removal restores consistency, found greedily by removing each candidate in turn and re-checking rank. It is reported in plain language, for example: "Horizontal on Line 3 conflicts with Angle d4 (30°)."

**Guarantees, each pinned by tests:**
- **Deterministic:** the same sketch and warm start give bit-identical output. There is no randomness, and iteration order is fixed.
- **Branch-stable:** sweeping an exposed dimension in small steps never flips to a mirrored or alternative solution. Arcs don't invert and triangles don't reflect.
- **Plain errors:** an unsatisfiable driving value, such as a negative length or an impossible triangle, gives a node `.error` in plain language. The last good geometry stays ghosted (parent spec §4.4).

## 5. Regions (`SketchRegions`)

1. Take the **non-construction** curves, including projected edges, from the solved sketch.
2. **Split** them at every intersection, using exact line/line, line/arc and arc/arc intersections with tolerance 1e-9 mm. Overlapping collinear or co-circular spans merge.
3. Build a planar graph and walk its faces using the "next edge counter-clockwise" rule, which yields every bounded face.
4. **Nest:** a face contained in another becomes a hole of it. Islands inside holes are separate regions (even–odd nesting).
5. Each region becomes `Profile2D(plane:, outer:, holes:)`. Regions are **sorted deterministically** by area descending, then centroid x, then y, so broadcast order is stable.
   - Each region's **holes are sorted the same way** (area descending, then centroid x, then y). A hole's loop index is its position after sorting plus one (`TopoRole.side(loop:segment:)`, loop 0 = outer), so an unordered hole list would rename hole walls and drift picks on every edit.
   - **Every loop is emitted counter-clockwise**, holes included. The face walk traverses some boundaries clockwise; for those, reverse the walked edge order and emit each arc as its counter-clockwise `Segment2D` (endpoints swapped). `Segment2D.arc` is counter-clockwise only, so a clockwise loop through an arc can't be written as a closed `Profile2D` loop. The kernel re-orients wires (a hole is reversed against the outer), so counter-clockwise everywhere is always valid.
   - **Every loop starts at a deterministic segment**, after the counter-clockwise normalisation: rotate it to begin at the segment whose start point is lexicographically smallest (x, then y, compared with the 1e-9 mm tolerance). The segment index is part of `side(loop:segment:)`, so a moving start would rename walls and drift picks just like an unordered hole list.
6. Open or dangling curves are ignored, with a node `.warning` such as "2 curves don't form a closed region."

## 6. Kernel and graph changes

**`Profile2D` holes:**
- `Profile2D` becomes `(plane, outer: [Segment2D], holes: [[Segment2D]])`.
- The current `init(plane:segments:)` and the `segments` accessor keep working as the hole-less form, so existing code and tests compile unchanged.
- `isClosed` checks every loop.

**Shim:**
- `occt_profile` gains `loops` and `loop_count`. `build_profile` builds the outer wire plus inner wires: `BRepBuilderAPI_MakeFace(outer)`, then `.Add(innerWire)` for each hole. Hole wires are oriented against the outer wire (S3 probe: OCCT needs opposite windings, and the outer loop may wind either way, so "clockwise relative to the plane normal" holds only for a counter-clockwise outline). The loop index travels in the history record's `operand`. "Either way" is fully usable only for line-only loops: `Segment2D.arc` is counter-clockwise, so a loop containing an arc must be written counter-clockwise (§5 step 5). A clockwise-arc segment case is deferred unless S4 needs it.
- History records for hole walls use `OCCT_FROM_SEGMENT` with an added loop index.

**Tags:** `TopoRole.side(segment:)` becomes `side(loop: Int = 0, segment: Int)`, where `loop == 0` is the outer loop, so `.side(segment:)` still compiles and means the outer loop. `sortKey` and `Codable` stay compatible: `loop` is written only when non-zero, and a missing `loop` decodes as 0.

**Graph:** S3 bumps `GraphFile.currentFormatVersion` to 3, because files with hole-wall picks carry a `loop` that older readers can't decode. S4 adds `ConstantValue.sketch(Sketch)` and bumps it again, to 4 (parent spec rule: a new `ConstantValue` kind means a version bump).

## 7. Nodes

**Sketch** (category `profile`, green):

| Socket | Direction | Type | Notes |
|---|---|---|---|
| `plane` | input, optional | plane | Used when the sketch's plane source is `.wired`; otherwise the stored fixed plane. |
| `references` | input, optional, list access | solid | Solids whose edges may be projected. |
| *each exposed dimension* | input | number | Named after the dimension; a wired value overrides the stored one. |
| `profiles` | output | profile, **list** | The regions from §5. |
| `measurements` | output | number, **list** | Reference (non-driving) dimensions, in name order. |

- **Settings:** the `Sketch` value, plus pick data for projected edges.
- **Evaluate:** apply wired dimension values, resolve projected edges against `references`, solve, find regions, output.
- **States:**
  - `.warning` for under-constrained sketches (not an error), for open curves, and for a projected edge whose pick now matches nothing or several edges. That edge turns red, and constraints on it are suspended, not deleted.
  - `.error` for over-constrained or failed solves.
- **Projection, v1:** a projected line becomes a 2D line; a circle or arc whose axis is parallel to the sketch normal becomes a 2D circle or arc. Any other projected curve type is refused with a plain warning.

**Plane from Face** (category `value`):
- **Inputs:** `solid` and a face pick setting (a tag subset, like Edges by Tag but for faces).
- **Output:** `plane`, with origin at the face centroid and normal along the face normal.
- **xAxis** is deterministic: the projection of world X onto the face, or of world Y when X is nearly parallel to the normal.
- **Errors:** a non-planar face, or a pick that matches no face, is a plain `.error`. A pick matching several faces gives a `.warning` and uses the first by ID.
- **Use:** "New sketch on face" creates a Plane from Face node wired into a new Sketch node.

## 8. Editor (`CreatorSketchEditor`)

**Entering and leaving:**
- Enter by double-clicking a Sketch node, choosing "Edit sketch" in the inspector, or using the face context menu's "New sketch on face".
- The camera animates a **Look At** onto the sketch plane and switches to orthographic. The model dims to about 30% but stays pickable for Project, and a plane grid appears.
- Finish with ⏎, Esc or the Finish button.
- **Each command is one undo step**, applied as a `setInput` of the whole sketch value. Point drags are coalesced into one step with `coalescingKey`.

**Toolbar** (glass, top):

| Tool | Key |
|---|---|
| Line | L |
| Arc (centre / 3-point) | A |
| Circle | C |
| Point | — |
| Construction toggle | X |
| Trim | T |
| Fillet | F |
| Mirror | — |
| Pattern | — |
| Project | P |
| Dimension | D |

There are also buttons for each constraint.

**Inspector:**
- In sketch mode it lists the constraints, and the dimensions with name and value fields and an **"Expose as input"** toggle.
- It shows the DOF readout: "3 degrees of freedom" or "Fully constrained".

**Drawing:**
- Lines chain from click to click.
- Snapping **infers constraints**: horizontal, vertical, coincident, tangent to the previous arc, and point-on for projected geometry. A glyph previews each inferred constraint, and holding ⌘ suppresses inference.
- The Dimension tool infers the dimension kind from the picked entities.

**Colours (Dracula, parent spec §6.6):**

| Element | Colour |
|---|---|
| Under-constrained geometry | cyan `#8be9fd` |
| Fully constrained | foreground `#f8f8f2` |
| Conflicting | red `#ff5555` |
| Construction | comment `#6272a4`, dashed |
| Projected | purple `#bd93f9` |
| Selection | green (the Sketch node's header colour) |
| Output regions | faint green fill |

**Picking:**
- Sketch entities are picked on the CPU in plane coordinates: intersect the cursor ray with the plane, then take the nearest entity within a few pixels.
- Model edges for Project use M4's ID-buffer picking.
- Click location uses M4's stopgap until MetalUI C7's `SpatialTapGesture` lands.

**Live feedback:**
- The sketch re-solves every frame while dragging or typing.
- **Downstream evaluation** runs on pointer-up, and is debounced to 150 ms while typing.

## 9. Milestones

| # | Delivers | Starts |
|---|---|---|
| **S1** | `CreatorSketch` model, constraints, dimensions, solver (decomposition, warm start, drag mode), DOF and conflicts | Now, in parallel with M3–M5 |
| **S2** | Regions; trim, extend and fillet commands; mirror and pattern commands | After S1 |
| **S3** | `Profile2D` holes, shim inner wires, `TopoRole.side(loop:segment:)`, format bump | After M3 merges |
| **S4** | `ConstantValue.sketch`, Sketch node, Plane from Face node, projection | After S2, S3, M3 |
| **S5** | `CreatorSketchEditor` in the viewport | After S4, M4 |

## 10. Testing

All tests use Swift Testing.

- **Solver:**
  - One analytic fixture per constraint.
  - Classic sketches: a fully constrained rectangle (0 DOF), a slot, a 3-4-5 triangle by dimensions.
  - DOF counts and freedom per entity.
  - Conflicts named minimally.
  - Determinism: two solves give bit-identical results.
  - **Branch stability:** sweep a dimension from 10 to 100 in steps of 1 with no mirror flips.
  - Drag mode keeps constraints satisfied.
- **Regions:**
  - A square with a circular hole gives 1 region with 1 hole.
  - An island inside a hole gives 2 regions.
  - Touching and overlapping shapes split correctly.
  - Construction geometry is ignored.
  - Open curves produce a warning.
  - Region order is deterministic.
- **Commands:** trim, extend, fillet, mirror and pattern each produce the expected entities and constraints, and the result solves.
- **Kernel:** extruding a profile with a hole gives the analytic volume, hole walls are tagged `side(loop: 1, …)`, and old files decode with `loop` 0.
- **Integration** (OCCTKernel):
  - Sketch → Extrude.
  - Changing an exposed dimension changes the part, and downstream edge picks keep their keys.
  - A projected edge survives an upstream width change.
  - Plane from Face follows a moved face.
- **Editor:**
  - `SketchEditorModel` tests: tool state machine, inference rules, plane hit testing, DOF colouring, undo granularity.
  - Human visual checks in `docs/verification/human-checks.md`.

## 11. Deferred

- Splines, ellipses, offset curves, slots, text.
- A live pattern count as a socket.
- Projecting non-planar or oblique curves.
- Editing a sketch outside the viewport.
- A constructive (D-Cubed-style) solver: it could later replace components behind the same `SketchSolver` interface.

## Errata (S4)

- §6's deferred clockwise-arc case is taken in S4: a `Segment2D.arc` with `end < start` runs clockwise, `build_edge`
  builds it as the counter-clockwise arc from `end` to `start`, reversed, and `Segment2D.length` is positive. A
  region with a notch (a counter-clockwise outline running along an arc the other way) extrudes and revolves.
- §6's format bump: S4 takes `GraphFile.currentFormatVersion` 3 → 4 for `ConstantValue.sketch` and `.facePick`. If
  another branch bumps the version first, whichever merges second takes the next number (the constant, the test
  `savedFilesCarryTheCurrentFormatVersion`, the doc comment on the constant and the CLAUDE.md line).
- §7's exposed-dimension sockets come from `NodeDefinition.inputs(for: node)` (CreatorGraph), in dimension-name order,
  defaulting to the stored value. A dimension named like a fixed input (`plane`, `references`), a setting, a
  `projection.` setting, empty or repeated is not exposed, and the node warns. The graph panel draws a node's
  static `inputs` until S5 switches `NodeShape` and the inspector to `inputs(for:)`, so exposed sockets can be wired
  (by `Graph.apply(.connect)`) but aren't drawn yet.
- §7's "pick data for projected edges" is one setting per projection, `NodeSetting.projection(reference)` =
  `"projection.<reference>"`, holding `.edgePicks([pick])`. The pick resolves by tag subsets across every
  `references` solid and must name exactly one edge; a changed match count is a warning (parent spec §5.3 rule 6).
  A reference dimension on a suspended projection would measure the curve stored in the sketch (S4 never refreshes
  it), so it isn't output: `measurements` is empty and the node warns naming it. The same holds for a reference
  dimension that doesn't fit its geometry (a length on a projected circle), so list positions never shift.
- §7's Plane from Face stores its face as `NodeSetting.face` = `.facePick(FacePick)`, the picked face's whole tag set
  (`Topology.facePick(for:)`), matched as a subset like an edge pick. Its "nearly parallel" threshold: world X is
  used unless its in-plane part is shorter than 1e-3.
- §7's Sketch node has no inspector controls in S4 ("Edit sketch" is S5) and Plane from Face has no "Pick face in
  view…" button: the app's `pickFacesInView` still refuses, so the button waits for the app to write `.facePick`.
- §7's under-constrained warning reads "The sketch has N degrees of freedom left, so it isn't fully constrained."; an
  empty sketch warns "Draw a closed shape in the sketch to make a profile."; a fixed-plane sketch with a wired
  `plane` warns that the wire has no effect.
- §7's evaluate does not store the solve's warm start: it solves from the stored sketch every time, so results don't
  depend on evaluation history. S5's editor writes `Sketch.remember(_:)` into the setting after each edit.

## Errata (S5a)

- §8 is split: S5a (plan `2026-10-09-sketcher-s5-editor.md`) has sketch mode, Line, Arc (centre, start, end), Circle,
  Point, construction, the constraint buttons, Dimension, the inspector's lists, point drags and the live solve. S5b
  has Project, "New sketch on face", double-click to enter, Trim, Fillet, Mirror, Pattern, 3-point arcs, tangent and
  point-on inference with glyphs, dimension labels in the view and the region fill.
- §2's `CreatorSketchEditor` depends on CreatorSketch, CreatorViewport, CreatorGeometry, CreatorStyle (the theme's
  colours, which postdate the table) and MetalUI; CreatorKernel joins with Project (S5b). The inspector sections are
  its views (`SketchInspector`, `SketchToolbar`); the app shell gives them their glass and places them.
- §8's entering: "Edit sketch" is the Sketch node's inspector button (`InspectorAction.editSketch`). The model is
  ghosted (the viewport's 40%, not 30%) and stays pickable; the plane's grid replaces the ground grid. Leaving keeps
  the camera where it is.
- §8's toolbar is one row in the top bar (it replaces the document's name, Preview, Undo, Redo and Export while
  sketching); the constraint buttons are in the inspector, three to a row. Keys are button shortcuts: L, A, C, D, X,
  ⌫ and ⌦ (Delete), ⏎ (Finish) and Esc (end the stroke, else clear the selection, else finish). ⌫ and ⌦ never fall
  through to the graph's delete, which would delete the Sketch node being edited. The toolbar and the inspector are
  opaque to the pointer, so a click on their chrome never draws in the viewport beneath; the viewport's face menu
  is empty while sketching (see the camera-lock erratum below: Look At would turn the camera).
- §8's undo: each command is one `setInput` of the whole sketch; a point drag commits once, on release, so it is one
  step without a coalescing key, and downstream evaluation runs on pointer-up. Typed values commit on Return or when
  the field loses focus (no 150 ms debounce: nothing evaluates while typing).
- §8's selection: Select-tool clicks toggle an entity in the selection (MetalUI's taps carry no modifiers,
  docs/metalui-gaps.md S5-a), a click on nothing clears it; points win over the curves through them. ⌘ can't suppress
  inference until S5-a is fixed.
- §8's inference in S5a: a click within the pick radius (8 points) of a point shares it (coincident by construction);
  a line's end within the radius of its start's height or x snaps horizontal or vertical and adds the constraint.
- §8's Dimension tool: a circle gives a diameter and an arc a radius at once; a line waits for a second pick (a line:
  angle; a point: distance; nothing: length); a point waits for a point or a line (distance). Each measures the
  geometry as it is, so nothing moves.
- §7's single source for exposed values (S4 → S5 handoff): opening a sketch folds a constant left under an exposed
  dimension's socket name into the sketch, and every commit clears it; renaming an exposed dimension moves its wire,
  and un-exposing it drops the wire. Delete and the inspector's Remove refuse to remove an exposed dimension.
- §7's "a wired value overrides the stored one" holds in the editor too: opening (and every refresh) loads a wired
  exposed dimension's value from the wire's current number result (a wire without one yet leaves the stored value),
  so the editor solves and lists what the node evaluates. Its value is read-only ("Its value comes from the wire into
  “width”."), and storing an edit keeps the stored value under a wire that stays; un-exposing drops the wire and
  keeps the value shown.
- §8's inspector: a reference dimension's row shows its live measurement (the node's `measurements`), its value is
  read-only ("d1 is a reference: make it driving to set it."), and making it driving again takes the value it
  measures now, so nothing moves.
- §8's entering, amended (user, 2026-10-09): sketch mode locks the camera to the sketch plane. The editor asks the
  viewport for planar navigation (`ViewportTool.navigation == .planar`): a primary drag that doesn't start on a sketch
  point pans (a drag on a point still moves it), right- and middle-drags pan, scroll, pinch and ⌥-drag zoom; the view
  cube, its arrows and its View menu are hidden, the commands that turn the camera (cube regions, arrows, Home,
  projection) do nothing and the face menu is empty (Look At would turn it). F frames the sketch
  (`ViewportTool.framingBounds`: its points, circles and arcs whole, with a 10% margin) without turning. Leaving
  restores free orbit and keeps the camera where it is. The first scene's isometric framing never runs while sketching
  (a new document's first solid, drawn mid-sketch, keeps the camera face-on), and input during the turn onto the
  plane finishes the turn instead of freezing it part-way.
- §8's live feedback gains a pointer readout (user, 2026-10-09), S5a's and distinct from S5b's dimension labels in the
  view: a glass chip, drawn over the panels, centred above the pointer (flipped below near the model area's top,
  clamped inside its sides; none in a model area too small to hold it) reading what the next click would commit, after
  snapping, to one decimal: a line's length and angle (counter-clockwise from the plane's +x, 0 ≤ angle < 360°), a
  circle's diameter, an arc's radius then radius and counter-clockwise sweep (0…360°, a near-full arc reads 360.0°),
  and the Point tool's plane position. The Point tool's readout is a position readout: over an existing point it
  shows that point's position, though a click there commits nothing. It follows the pointer through pans, zooms and
  scrolls, and goes with the stroke, on Esc, when the pointer leaves the view (onto the toolbar or inspector too) and
  outside sketch mode.
- The pointer readout also shows while a point is dragged (user, 2026-10-09), whatever the tool: the solved values,
  what the release keeps, in the same format, updated every drag step and following the pointer, gone on the release
  or when the drag is cancelled (undo mid-drag; Finish mid-drag also drops the drag's uncommitted steps, as it drops a
  stroke). The end of exactly one line reads that line's length and angle (start to end); the start or end of exactly
  one arc, its radius and sweep; anything else (a circle's or arc's centre, a free point, a corner) its position. A
  point is a corner when more than one curve is built on it (construction curves count) or a coincident constraint
  joins it to another point, so a point that ends both an arc and a line reads its position (precedence: shared beats
  either curve); other constraints on it (on a curve, midpoint, fix) don't make it shared.

## Errata (S5b)

- §8's S5b/S5c split (plan `2026-10-09-sketcher-s5b.md`): S5b has Trim, Extend, Fillet, Mirror, Pattern, 3-point
  arcs, point-on and tangent inference with their glyphs, and double-click to edit. S5c has Project, "New sketch on
  face", dimension labels in the view and the region fill: each needs the viewport (an ID-buffer pick routed through
  the tool, an overlay label API, filled overlay triangles), CreatorKernel in the editor, or graph insertion batches.
- §8's toolbar gains Trim (T), Extend (no key: §3 has the command, §8's table no row), Fillet, Mirror and Pattern,
  after the drawing tools and Dimension. Fillet has **no key**: F frames the sketch (Errata (S5a), the camera lock),
  and the user's later decision wins over §8's table. Each runs its `SketchCommands` command on a click as one undo
  step; a refused command shows `SketchCommandError.message` as the inspector's refusal and stores nothing.
- §8's tool flows: Trim and Extend click a curve (Extend the end nearer the click); Fillet clicks a corner point with
  the inspector's radius (default 5 mm); Mirror and Pattern act on the selection (made with Select first), Mirror on
  a click on the axis line, Pattern on a click on a point (circular, around it) or a line (linear, along it from its
  start toward its end), with the inspector's instance count (default 3, 2 or more; more than 100 is refused when it
  runs) and spacing (default 20 mm). The selection stays after Mirror and Pattern. The options aren't saved. Pattern
  construction is drawn as construction (dashed), not yet told apart from the user's own.
- §8's "Arc (centre / 3-point) | A": A picks the centre arc, and A again switches to the 3-point arc and back; the
  toolbar also has a 3-Point Arc button. A 3-point arc is start, end, then a point it passes through; its centre is a
  new point; a third click in line with the ends draws nothing and waits. Its readout reads the chord, then the radius
  and sweep.
- §8's inference: point-on applies to every curve (lines, arcs, circles, projected edges), not only projected
  geometry: a click within the pick radius of a curve, and not of a point, makes a new point held on it by point-on
  (points win over curves). ⌘ suppresses it, as §8 says of inference (the click lands where it is, free); only
  sharing a point (coincident) isn't suppressed, because it is structural. A line whose start is an arc's start or end
  snaps tangent to it (the newest such arc) when its end is within the pick radius of the tangent, either way along
  it, and gets a tangent constraint; tangent wins over horizontal and vertical, and ⌘ suppresses all three. A line's
  end on a point or a curve takes no direction inference. Until clicks and hovers carry modifiers (gaps S5-a, GI-a),
  ⌘ reaches none of this in the app; the editor's tests pin it.
- §8's glyphs: one chip below and right of the pointer names what the next click would infer ("Horizontal",
  "Point on", "Tangent", "Coincident"), in the selection's green on the theme's glass, beside the pointer readout and
  placed like it (moved left and up at the model area's edges; none when it doesn't fit). Clicks that keep no point (a
  circle's radius, a 3-point arc's third point) infer nothing.
- §8's "Enter by double-clicking a Sketch node": the graph canvas pairs two plain clicks on the same node's body,
  at most 0.4 s and 4 points apart (the groups spec's values, §6, not macOS's 500 ms default, so groups share the
  recogniser), because the canvas's one zero-distance drag carries no click count (docs/metalui-gaps.md S5-b, MetalUI
  C16). A double click on a node with an "Edit sketch" inspector button presses it. While a sketch is open, a double
  click (or any .editSketch request) changes nothing: the stroke, the selection and the camera stay.
