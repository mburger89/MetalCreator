# NURBS surface modelling — design

Status: NS-1 done (2026-11-17; human checks group NS-1 pending). NS-2 done (2026-11-18; human checks group NS-2 pending; R1: a network is G0 only, matching to a part is NS-4; R3: a G2 patch takes no interior points or curves). NS-3 done (2026-11-18; human checks group NS-3 pending; R1: Rebuild is two nodes, Rebuild Surface and Rebuild Curve). NS-4 done (2026-11-18; human checks group NS-4 pending; R1: the nodes are named … Surface; R2: pieces are named by cutter element and side). Sub-projects NS-1 to NS-5, built in that order.

## Intent

MetalCreator already *contains* NURBS: OpenCascade keeps every face as an analytic or B-spline surface, sketches
have degree-5 splines, Loft skins B-spline sections, the G2 fillet builds quintic B-spline strips, and STEP and
IGES models already come in through KiCad components. What it can't do is **model surfaces**. Every node makes or
changes a closed solid, so a shape that is hard to describe as a sketch plus an extrusion can't be made at all.
Examples are a handle, a mouse shell, a duct, a car-style fillet between two freeform panels, or a STEP part
that needs a patch.

This design adds surface modelling in the node graph's own terms:
- curves and open surfaces are values on wires;
- every surface is built by nodes and rebuilt when an input changes;
- the classic surfacing tools (sweep, network, patch, control points, trim, extend, match, blend, sew, thicken)
  are nodes;
- the existing checks (zebra, continuity, measure) work on surfaces.

The user asked for this after the review of what exists ("Yes let's add this", 2026-11-17). They had asked for
question rounds to be skipped, so every call below is mine unless it is marked as theirs.

## Goals

1. **Curves on wires.** A 3D curve (lines, arcs and B-splines joined end to end, open or closed) is a value. It
   can come from a sketch (open curves too), from points, from a part's edges, or from an imported model.
2. **Sheets.** An open surface body travels where a solid does. It is drawn, picked, measured, zebra-striped,
   moved, patterned and exported.
3. **Surfaces from curves.** Extrude, revolve, loft and sweep curves into sheets (and, for closed profiles,
   solids). Fill a closed planar curve. Build a surface through a network of curves. Patch an N-sided hole with
   G0, G1 or G2 to its neighbours.
4. **Control points.** Show a surface's or curve's control net. Drag control points in the viewport, with the
   moves stored in the graph. Rebuild a surface or curve to a chosen degree and span count.
5. **Editing surfaces.** Trim and split by curves or surfaces. Extend an edge. Match an edge to another edge at
   G0, G1 or G2. Blend two edges with a G1 or G2 surface.
6. **Back to solids.** Sew sheets into a solid when they close. Thicken a sheet into a solid. Offset a sheet.
   Split a solid with a surface.
7. **Import Model.** A general STEP or IGES import node, so a supplier's freeform part can be patched, matched
   and thickened.

## Non-goals

- T-splines and subdivision surfaces.
- Editing the weights of rational surfaces. A weight is kept as read but never changed: control-point moves
  change positions only.
- Editing a surface's knots by hand (Rebuild replaces them).
- Class-A tooling such as highlight lines or curvature combs on surfaces. Zebra and the edge continuity reading
  exist; a curvature map is a later project.
- IGES export (STEP carries sheets).
- Untrimming, or recovering an imported model's feature history.

## Anti-goals: things that would make this a failure even if it works

- **A surface that silently misses its promise.** A node that offers G1 or G2 checks the result at its seams
  against the measure's thresholds (position 1e-4 mm, angle 0.01°, curvature within 1 %, the G2 fillet's rule).
  If the result misses, the node refuses in words or warns with a count. It never shows a "G2" surface that is
  only G1. An invalid shape (`BRepCheck_Analyzer`) is never returned.
- **Picks that drift.** A picked sheet edge or face must keep naming the same thing through a parameter change,
  as picks on solids do.
- **Hidden geometry.** Every surface is rebuilt from the graph. A control-point move is a node setting, never a
  change to geometry outside the graph.

## Approaches considered

- **A. Sheets travel on the `solid` socket (chosen).** A `Solid` may be closed or open. A new `curve` socket
  carries wires. The viewport, picks, Transform, the patterns, Measure, zebra, Section and export already take a
  `Solid`, so a sheet reaches them with little new code. Nodes that need a closed solid refuse an open one in
  words, as the mesh tools refuse an open mesh (`MeshInput.requireClosed`). The cost: the type system no longer
  tells a sheet from a solid at wiring time, only at run time.
- **B. A separate `surface` socket type.** Wiring is clearer, but every consumer (viewport, picks, transform,
  patterns, export, measure, section, zebra, groups) needs a second path or a conversion. That is roughly the
  work of A again, for a check the run-time refusal already gives.
- **C. A direct modeller,** where surfaces are stored data edited in place, as in Rhino. It fights the
  parametric graph: an upstream edit could not flow through hand edits. Rejected; control-point editing is done
  the graph's way instead (goal 4).

The socket keeps its name `solid` in files. Its label in the UI becomes "Body" only if the builder finds that
cheap; otherwise it stays "solid". The builder's call.

## Design

### Values

- **`Curve` (CreatorKernel),** a new class like `Solid`. It holds kernel storage (an OCCT `TopoDS_Wire`), its
  bounds, whether it is closed, whether it is planar (with the plane), its length, and a display polyline at the
  viewport's tolerance.
  - Its pieces carry `CurveTag`s (the node, the item, and a role such as `.segment(k)`, `.spline`,
    `.edge(EdgeKey)`), so a surface built from a curve can name its faces and edges after the curve's pieces.
- **`SocketType.curve`.**
  - A `curve` socket also accepts a `profile` wire (`accepts`), but there is no conversion in `Value`.
    Conversions are one value to one value, and a profile with holes is several loops. The node reads its input
    through one helper, `CurveInput`, and each node says what a profile means to it:
    - Loft Surface and Network Surface use the outer loop and refuse a profile with holes ("Section 2 has holes;
      a loft section is one loop.").
    - Sweep and Planar Surface use every loop, so a holed profile sweeps to a tube or fills a face with holes.
    - Curve from Edges and the explicit **Profile to Curves** node (outer, then holes, as a flat list) give the
      loops when a person wants them on a wire.
  - An edge set reaches a curve through Curve from Edges, so the chaining is explicit.
- **Closed and open bodies.**
  - One `Solid` value may mix closed solids and open sheets (a pattern, an import, a partial Sew). `Solid`
    gains `isClosed` (every shell closed, i.e. no free edges) and `Topology` gains, per face, whether it lies
    on an open shell.
  - Back-face colour is per face, from that flag. The refusals test `isClosed` on the whole value.
  - Export judges each Output's value as a whole: 3MF refuses any open shell in it, and STL warns.
  - Section caps only the closed shells.
  - The facts and the socket tooltip say "solid", "sheet" or "2 solids and 1 sheet".

### Naming

- `EdgeKey` today is the tag sets of the two faces beside an edge. A sheet's boundary edge has one face.
- Such an edge is named by its face's tags plus a **boundary role**: the tag of the curve piece or construction
  step that made that boundary. Examples:
  - a sweep's start edge is `.boundary(.start)` of the sweep's tag, and its sides are the profile's piece tags;
  - a loft's edges are its sections' piece tags;
  - a trimmed edge is the trimming curve's or surface's tag.
- Every reader of edges learns one-face edges: `Topology.key(of:)`, `Topology+EdgePicks` (which skips them
  today), the selection rules (Edges by Tag, All Edges, Edges by Direction) and the drift counts (`runCount`).
- The builder chooses the encoding (an `EdgeKey` whose second side is a one-element set of boundary roles is the
  obvious one). It must:
  - round-trip in saved picks;
  - narrow and retry like the existing keys;
  - come with a file format bump.
- Sewing turns two boundary edges into one shared edge, and its key becomes the ordinary two-face key. A pick
  made before the sew on one of those boundary edges resolves through `EdgeKey.operandKeys`'s existing per-side
  retry.

### Drawing

- **Back faces.** A sheet's faces are drawn on both sides. The back side takes a new theme role `sheetBack` (a
  muted second colour) so orientation is visible, which matters for Thicken and Match. This is needed in Metal and
  HLSL alike (`GPUDataTests` and `ShaderSourceTests` rules). It replaces the darkened back face for sheets only.
- **Curves.** A curve is drawn as a line item (reference colour), hovered and framed. Curves are not picked.
  Nodes take curves by wire and edges by picks on bodies. A curve pick kind can be added later if a node
  needs one. A curve on an
  Output node is part of the scene, like a sheet.
- **Control nets** (NS-3). These are dashed overlay lines and points, drawn only while an Edit Surface or Edit
  Curve node is selected.
- **Section** caps closed solids only. A sheet is cut and drawn as its outline.

### Export

| Format | Sheets | Curves |
|---|---|---|
| STEP | Written as shells | Written as wires |
| STL | Written as open meshes, with a warning naming the Output | Left out with a warning |
| 3MF | Refused, naming the Output: "<Output> is an open surface; 3MF needs closed parts. Thicken or Sew it first." | Left out with a warning |

### Joining a part

- Patch, Network Surface, Match, Blend and Extend output **a separate sheet**. They never sew it into the part,
  so the part's picks downstream are untouched. Sew (NS-5) joins pieces when a person wants one body.
- Match changes its own input sheet and gives that sheet back.
- Continuity to another body's face is graded by a new kernel call `continuity(along:of:against:)`: the edge of
  one shape against the matching face of another, sampled as `continuity(along:of:)` is, with the same
  thresholds. Internally it may sew a temporary pair.

### Rules every surface node follows

- A **continuity** input is a segmented G0 / G1 / G2 control where the node joins something. The seams are
  checked after the build (the anti-goal above), using `Kernel.continuity`'s thresholds. Refusals name the
  largest or smallest setting that works where a search is cheap, as the fillet does.
- Every OCCT call goes through the shim under `OCCTKernel.serialized`. Algorithms OCCT lacks are ours in
  `Sources/COCCT`: the Gordon surface, matching, and blending (reusing `cocct_g2_*`'s quintic sections).
- `FakeKernel` refuses curves and sheets with `.unsupported`. It is extended only where a node's graph-level
  tests need it (a straight-line `Curve`, a planar rectangle sheet).
- Cancellation is asked between sections, curves and iterations. Every limit is a sentence: 2,000 curves in a
  network, 100,000 control points per surface, degree 1 to 11.

## Sub-projects

### NS-1: Curves, sheets and import

- **Values and infrastructure:** the `curve` socket and `Curve` value; sheets on `solid`; boundary naming; back
  faces; export rules; facts ("Sheet: N faces, open edges M, area A").
- **Closed-solid refusals:** Fillet, Chamfer, Boolean (any operand), the patterns' Boolean shortcuts, Section
  caps and the mesh-making nodes need `isClosed`. Fillet and Chamfer refuse a sheet in NS-1 ("Fillet needs a
  closed solid; Thicken or Sew the sheet first."). Fillets on sheets are a later addition, since the
  `largestValidBlend` search and the G2 strip code assume a solid. Boolean refuses a sheet operand: "<input> is an open surface; use Split or Trim, or Thicken or Sew it
  first."
- **Sketch:** a new `curves` output carrying every non-construction chain (open or closed), placed on the
  sketch's plane.
- **Curve nodes:**
  - **Curve through Points:** `points` list of vectors, `degree` 3 or 5, `closed`, optional start and end
    tangents.
  - **Curve from Edges:** an edge set chained into curves, one per chain.
- **Surface nodes:**
  - **Extrude Curve** (a direction and distance, or both ways).
  - **Revolve Curve.**
  - **Loft Surface:** sections as curves (open or closed), ruled or smooth, optional `closed` loop of sections.
    An all-closed loft gives a sheet tube; Cap Planar Holes in NS-5 closes it.
  - **Sweep.**
  - **Planar Surface** (a closed planar curve, or a profile with holes).
- **Sweep in detail:**
  - Inputs: `profiles` (curves; a profile converts) and `path` (one curve).
  - `orientation`: Frenet, fixed direction, or follow a guide surface's normal (the guide is NS-2's job; NS-1
    ships Frenet and fixed).
  - `twist` in degrees, end `scale`, and `solid` (when every profile is closed, cap the ends and give a closed
    solid).
  - Built with `BRepOffsetAPI_MakePipeShell`. A self-intersecting result is refused: "The sweep runs into
    itself; shorten the path or shrink the profile."
- **Import Model:**
  - A STEP or IGES file, linked or embedded (as Import Mesh's `meshFile`; a new `modelFile` setting).
  - It is read through a new kernel call `readShapes`, which returns the closed solids, the open sheets and the
    free wires separately. KI-2's `readModel` stays as it is: it returns one `Solid` and refuses a file with no
    faces, which a wire-only file must not be.
  - It gives solids, sheets and curves as three outputs (lists) and `units` (From file, or an explicit unit).
  - Its faces are tagged `.imported(face:)` as KI-2's are, so picks on an imported face survive only while the
    file is unchanged. The facts say so.
- **File format 14.** It adds the `curve` socket type in group interfaces, `modelFile`, sheet-boundary edge keys
  and the new nodes' settings.

### NS-2: Surfaces from curves

- **Network Surface:** `uCurves` and `vCurves`, each a list of at least 2. It is a Gordon surface (our code in
  the shim):
  - the curves are made compatible (common degree and knots, reparametrised by their intersections);
  - every u curve must meet every v curve within `tolerance` (default 0.01 mm), else it refuses, naming the pair:
    "u curve 2 and v curve 3 miss each other by 0.4 mm.";
  - the result passes through every curve to the tolerance.
  - Optional edge continuity to adjacent faces (the four border curves may come from a part's edges): G0, G1 or
    G2 per side, checked.
- **Boundary Patch:** 2 to 16 bounding curves or edges forming one closed loop, plus optional interior curves or
  points that the patch passes through.
  - Per bounding edge that lies on a part, a continuity G0, G1 or G2 to that face.
  - Built with `BRepFill_Filling` for G0 and G1, then checked. G2 uses our own corner-patch machinery where the
    loop has 3 or 4 sides; otherwise it is refused: "A G2 patch needs 3 or 4 sides; this loop has 6."
- **Sweep with a guide:** the guide-surface orientation, and a second rail (two-rail sweep).

### NS-3: Control points

- **Edit Surface:**
  - Input `surface`: a sheet with one face. If it has more, it is refused naming the count, with "Rebuild or
    Split it first". A non-B-spline face is converted exactly (`BRepBuilderAPI_NurbsConvert`).
  - Setting `poleMoves`: pole index (i, j) mapped to a displacement in mm, sorted, saved.
  - The output is the surface with those poles moved. Its tags are the input's, so picks downstream survive.
  - When an upstream change alters the net's size, moves whose index no longer exists are dropped from the
    result, kept in the setting, and warned about: "3 control point moves no longer fit the surface's 6 × 8 net."
- **Edit Curve:** the same for a curve, with pole index i.
- **Viewport editing:** a mode, as sketch mode is, not a kind of handle. Today's handles are one scalar along a
  direction, and plain drags navigate.
  - The inspector's "Edit Control Points" (and a double click on the node) installs a `ControlNetTool` as the
    viewport's `ViewportTool`, with free (not planar) navigation. Orbit moves to the right and middle drags, as
    the sketch editor's free tools already allow.
  - A primary press on a point picks it (⇧ adds, ⌘ toggles). A primary drag on empty space box-selects. A drag
    on a selected point moves the selection in the plane through it that faces the camera. While dragging,
    X, Y and Z lock to the world axes and N to the surface normal at that point.
  - Done or Esc leaves the mode.
  - The point selection is view state: not saved, and no undo step. A drag is one undo step,
    "Move Control Points".
  - Typing in the inspector edits the selected point's x, y, z offset.
  - While a point is being dragged, `isScrubbing` holds, so downstream G2 nodes build at G1 as they do today.
- **Rebuild:** a surface or curve, `degreeU`/`degreeV` (or `degree`), `spansU`/`spansV`, giving a non-rational
  B-spline approximation (`GeomAPI_PointsToBSplineSurface` over sampled points). It reports the largest
  deviation in its facts and warns above `tolerance`.
- **Surface Info** facts on every sheet face (inspector "Surface" section, for the selected face of an Edit
  Surface or Rebuild): degree, pole count, knots, rational or not.

### NS-4: Editing surfaces

- **Trim:**
  - A sheet and a cutter: curves projected along a direction or onto the surface's normals, or another
    sheet/solid.
  - `keep`: picked regions (a point near the kept side, picked in the view like a face pick; stored as a
    `FacePick` on the split result), or Inside/Outside for a closed planar cutter.
  - Built with `BRepAlgoAPI_Splitter` plus projection (`BRepProj_Projection`).
- **Split:** the same cut, keeping every piece as a list.
- **Intersect:** two bodies give their intersection curves (a `curve` list).
- **Extend:** picked boundary edges of a sheet, a `length`, `mode` Natural (curvature continuous,
  `GeomLib::ExtendSurfByLength` at G2) or Linear (G1 ruled).
- **Match Surface:**
  - A picked boundary edge of the sheet to change, a target edge (a sheet's or solid's), and continuity
    G0, G1 or G2.
  - The sheet's first 1, 2 or 3 pole rows are moved to meet the target exactly (our code, after inserting knots
    so the rows exist; refined until the check passes or the rows run out).
  - It refuses when the edges' ends don't meet within 0.01 mm: "The edges' ends are 0.8 mm apart; Match needs
    them to meet." It never refuses because the result is merely ugly.
- **Blend Surface:**
  - Two picked edges (on sheets or solids), continuity G1 or G2 at each end, and a `bulge` (0.1 to 2, as the
    fillet's tangency weight) per side.
  - Built from quintic sections, as the G2 fillet's strips are (shared code in `cocct_g2_section.hpp`), and
    checked.

### NS-5: Back to solids

- **Sew:** a list of sheets (and solids' faces), with `tolerance` defaulting to 0.01 mm
  (`BRepBuilderAPI_Sewing`).
  - A closed result becomes a solid (`BRepBuilderAPI_MakeSolid`, oriented outward).
  - An open one stays a sheet and warns with the count of free edges.
  - The facts list free edges, and the free edges are shown in the warning colour.
- **Thicken:** a sheet, a `distance`, and `side` (front, back or both) give a solid
  (`BRepOffsetAPI_MakeThickSolid`/`MakeOffsetShape` plus walls). Failure names the largest distance that works
  (a search, as `largestValidBlend` does).
- **Offset Surface:** a sheet at a distance, possibly negative.
- **Cap Planar Holes:** closes a sheet's planar boundary loops with planar faces and gives a solid when the
  result is closed.
- **Split Solid:** a solid cut by a sheet gives a list of solids. Boolean's Subtract with a sheet tool stays
  refused; Split is the tool for it.

## Testing

- **OCCT tests** (`CreatorOCCTTests`, every platform): each node's geometry against known values:
  - a swept circle's volume;
  - a network surface through grid curves, measured at the intersections;
  - a patch's seam continuity graded G2 by `Kernel.continuity`;
  - a match's rows;
  - a thickened plate's volume;
  - sew closing six faces of a box into a solid.
- **Naming tests:** a pick on a sheet's boundary edge survives a parameter change, a sew, and a group, as the
  existing suites do for solids.
- **Viewport tests:** the back-face colour in the Metal and SDL render suites, and a curve item drawn and picked.
- **Benchmarks:** `SurfaceBench` rows in `docs/verification/performance.md`, each from edit to preview:
  - a 20 × 20 network surface;
  - a 4-sided G2 patch;
  - dragging one control point on a 30 × 30 net (target: 60 fps while dragging the preview at G1).
- **Human checks:** group NS per sub-project.

## Left to the builder

- The `Curve` storage's exact Swift shape.
- The boundary-key encoding (within the rules above).
- The point handle's drawing.
- Whether the socket's label becomes "Body".
- The order of nodes within a sub-project.
- Which OCCT classes back each algorithm where the design names none.
- Every message's exact words, in the app's voice, as full sentences.

## Calls I made (the user asked for no question rounds)

1. Sheets ride the `solid` socket (approach A), not a new socket.
2. A `curve` socket and value, with the conversion profile → curves.
3. Five sub-projects in the order above, with Import Model in NS-1 because it brings real surfaces to work on early.
4. Control-point editing stores moves by pole index in the node. A changed net drops moves that no longer fit,
   with a warning, and never remaps them.
5. G2 promises are checked, never assumed (the G2 fillet's policy).
6. No weight editing, no curvature map, no IGES export, no T-splines or SubD.
7. Back faces of sheets get a new theme role, `sheetBack`.
8. 3MF refuses open sheets; STL writes them with a warning.
9. A profile on a curve socket is read by each node in its own way, not by a `Value` conversion.
10. One value may mix solids and sheets; whether a face is on an open shell is recorded per face.
11. Surfaces joined to a part are separate sheets, graded by a new two-body continuity call.
12. Curves are not picked in the viewport, for now.
13. Control-point editing is a viewport mode with its own tool (selection, box select, axis locks).
14. Fillet and Chamfer refuse sheets for now.
15. Import Model uses a new `readShapes`, not `readModel`.
16. One-face edges are taught to every selection rule (Edges by Tag, drift counting), not only to the key.
