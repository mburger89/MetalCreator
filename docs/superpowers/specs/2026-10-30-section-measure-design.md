# Section analysis and Measure: looking inside a part and measuring it

Status: shaped in conversation 2026-10-30; this document is for the user's review.

## 1. Purpose

The user wants the section analysis that Fusion 360 and SolidWorks have, to **check wall thickness and internal features
through the part**: cut the part open on a plane, look at the cut face, and measure between its edges. Measuring grew into a
general Measure tool, as in Fusion, that works on the rest of the model too.

What the user decided (2026-10-30):

- **Both kinds of part.** B-rep solids (OpenCascade) and implicit parts and meshes (lattices, TPMS) can be sectioned and
  measured. Solids are exact; meshes are as accurate as their mesh.
- **Placing the plane:** start from a flat face of the model or one of the three origin planes (XY, YZ, XZ), then set an
  offset distance from it (typed), and the section cuts there.
- **View-only, like Fusion's Inspect ▸ Section Analysis.** It is never part of the graph, makes no undo step and changes no
  geometry.
- **Measuring a wall gives the shortest gap between the two picked edges**, not the distance between the clicked spots.
- **Measure works on the whole model**, like Fusion's Measure: distances, **angles, radii and hole diameters**.
- **Kept with the file, like Fusion.** The section and the measurements are there again when the file is reopened.

Success: on the bracket (or a lattice part), the user puts a section on a face or an origin plane, drags or types it to
depth, sees solid hatched material wherever the plane passes through the part, clicks two edges of a wall and reads its exact
thickness; then saves, reopens, and finds the same section and measurements.

### Non-goals

- More than one section at a time (Fusion allows several; one is the first version).
- Sections or measurements in the graph, as nodes, or driving anything.
- Exporting a section (DXF, drawings), section views on paper.
- A thickness heat map, curvature or draft analysis, interference checks. (`Check Thin Walls` stays the mesh's automatic
  check.)
- Exact measurement on meshes.

### Anti-goals (a failure even if it technically works)

- A "cut face" that is really the far inside wall seen through the hole (today's Cut view). On a part with several walls that
  shows the wrong wall at the wrong depth. The cap must lie on the plane.
- Measurements on solids that are approximations of the tessellation. On a solid the number must be OpenCascade's.
- Dragging the plane that stutters or freezes the window while a section is computed.
- A section or measurement that marks the document edited, adds an undo step, or survives into an export.

## 2. Context (what exists, 2026-10-30)

From reading the code:

- **The Cut view** (7c-3, implicit spec §5.1): `CutViewModel` (`Sources/CreatorApp/CutView/`) holds an axis plane (`SliceAxis`
  XY/YZ/XZ through the scene's centre), an offset, a flip and the side facing the eye, and builds a `ViewportClip` and a
  linear `ViewportHandle` (`CutViewModel.handleID`, intercepted in `AppModel.handleChanged` before the graph path, so no
  command and no undo step). The toggle is in `TopBar` and View ▸ Show/Hide Cut View, Flip Cut View (`AppCommands`).
  Clipping is a per-fragment discard in the mesh and line shaders (MSL in `ViewportShaders.swift`, HLSL `mesh.frag.hlsl`,
  `ClipUniforms` mirrored in `common.hlsli`), and in the ID pass, so clipped geometry is not pickable. **There is no cap:**
  back faces are painted the part's colour × 0.55. `CutViewModel.isAvailable` is `#if canImport(Metal)`, but the SDL
  renderer already clips (`SDLViewportRenderer+Record`, `+IDPass`), so the gate is stale.
- **Picking:** `PickTarget` is `.face(solid:, FaceID)` or `.edge(solid:, EdgeID)` (ID pass: 2 bits kind, 8 solid, 22 id).
  No vertices. `ViewportTool.clickedModel(_:at:modifiers:projector:)` hands a tool the pick under a click. A set tool trims
  the face menu to Look At. `MeshRaycast.nearest` gives a world point on a mesh.
- **Geometry the app has:** `Topology.faces: [FaceInfo]` (`SurfaceKind`, normal or axis direction, area, centroid, tags; **no
  radius, no axis point**), `Topology.edges: [EdgeInfo]` with `curve: EdgeCurve?` (`.line(start,end)`,
  `.circle(center, axis, radius, start, sweep)`, nil otherwise). No vertex table. `DisplayMesh` has triangles per face and
  `edgePolylines`.
- **Kernel:** `Kernel.distances(from points:to:signed:)` is point-to-target only (`DistanceTarget` `.solid/.faces/.edges`).
  Nothing sections a solid by a plane and nothing measures shape to shape. The shim already uses
  `BRepExtrema_DistShapeShape`, `BRepAdaptor_Surface` and `GProp`; `describe_face` reads a cylinder's axis but not its
  radius. Adding a shim call is mechanical (`guarded`, a result struct with its `*_free`, a Swift wrapper under
  `OCCTKernel.serialized`, a `Kernel` requirement with a default that throws `unsupported`, a `FakeKernel` answer).
- **Meshes:** `TriangleMesh` (CreatorImplicit) is shown through `MeshScene`/`MeshRefinementModel` (progressive passes, a mesh
  swapped by `mesh.id`). Nothing slices a mesh by a plane.
- **Dimensions:** `OverlayDimension` with `DimensionGeometry` `.linear`, `.radial`, `.angular` (all `Vector3`, each in its own
  plane) is laid out on screen by the viewport every frame (`showDimensions`). The app already draws feature dimensions on
  the model (`AppModel+Dimensions`, `FeatureDimensionBuilder`) and has a face-menu Dimension entry. Measurement results fit
  these as they are.
- **Overlays:** `ViewportOverlay` lines, points and fills are world-space, drawn ignoring depth; `OverlayFill` has no
  pattern.
- **View state** is `ViewState` (`Sources/CreatorGraph/ViewState.swift`): every key optional on decode, older readers ignore
  unknown keys, no format bump (as `showsLibrary`). View state is not part of the dirty comparison.

## 3. Section analysis

### 3.1 It replaces the Cut view

Section Analysis takes the Cut view's place: the top bar toggle becomes **Section**, View ▸ Show/Hide Cut View becomes
**Show/Hide Section**, Flip stays. The Cut view's code is grown into it (its clip, handle and flip), not kept beside it. It
works on macOS, Linux and Windows (the `isAvailable` gate goes; the SDL renderer gets every new pass the Metal one does).

### 3.2 Placing the section

A section is a **reference** plus an **offset** plus a **flip**:

- Reference: one of the origin planes XY, YZ, XZ, or a **flat face of the model** (a `plane`-kind face that has a normal).
- Offset: millimetres (shown in the document's units) along the reference's normal. Typed, or dragged with the plane's
  linear handle; the typed number follows the drag.
- Flip: which side is cut away.

Ways in:

- The top bar's **Section** button switches it on. The first time in a document it starts on the origin plane nearest the
  view direction through the parts' centre, as the Cut view does today (`SlicePose.startingAxis`); afterwards it comes back
  as it was left (§5).
- The face right-click menu gains **Section from Face** on a flat face: the reference becomes that face (stored as a
  `FacePick`, so it follows the face through edits), offset 0, and the section switches on.
- A small glass **Section panel** shows while the section is on: the reference (XY / YZ / XZ as a segmented control, or the
  face's name, "Face of Fillet 2", with a button to go back to an origin plane), the **offset field**, **Flip**, and Close.
  (Panel placement: builder's call, following `AppLayout` and the legend/theme-editor docks.)

A face reference that no longer resolves (the face is gone after an edit) keeps the last plane it had and the panel says
"The section's face no longer exists." once, as the open sketch does for a lost plane.

### 3.3 What the section shows

Everything on the cut side of the plane is clipped away (as now). Where the plane passes through material:

- **A cap lies on the plane**: a filled face in the theme's section colour with a **hatch**. Where several bodies are cut,
  their hatches run at different angles (45°, 135°, then other angles), the drawing convention, so touching bodies read
  apart. (Angles instead of colours: my call; easier to read and theme.)
- **Section outlines**: the cap's boundary edges drawn crisp in the theme's section edge colour, above the cap. These are
  pickable by Measure (§4).
- Ghosted items are clipped but not capped. Guide items, overlays, handles, the field slice and dimensions are not clipped.

The cap and outlines come from geometry, never from back faces:

- **Solids:** a new kernel call sections the solid by the plane and returns, per region of material, the exact section
  edges (lines and circle arcs as `EdgeCurve`s where OCCT has them, a polyline otherwise) and a triangulation of the region,
  holes included. In OCCT: `BRepAlgoAPI_Section` against a `gp_Pln`, wires built into faces (or `BRepAlgoAPI_Common` with a
  half-space; builder's call), tessellated as the solid's faces are. `FakeKernel` sections its boxes (a rectangle).
- **Meshes and implicit parts:** a new `CreatorImplicit` routine slices the shown `TriangleMesh` by the plane, chains the
  segments into closed loops by welded vertices, and triangulates the loops even-odd (holes and islands). It follows the
  progressive preview: a refined mesh re-slices. An open mesh's loops that do not close are drawn as outlines without a cap.

New theme roles: **`sectionFill`**, **`sectionHatch`** and **`sectionEdge`** (a `ThemeRoleGroup` of their own, last in
`ThemeRole.all`; a `.mctheme` without them reads Dracula's, as the field roles did). `OverlayTint`, `ShadeUniforms` or a new
uniform carry them to the shaders. The cap is a new pipeline in both renderers (MSL and HLSL, its structs pinned by
`GPUDataTests` and `ShaderSourceTests`), drawn with depth so the part in front of the plane hides it, and in the ID pass as
part of its solid only if the builder finds that simpler than picking outlines on the CPU (§4.2).

### 3.4 Staying smooth

Sectioning runs off the main actor. A plane move starts a new section and cancels the older one; the last cap stays drawn,
clipped to the new plane, until the new one is ready (the field preview's pattern). Mesh slices are fast enough to follow a
drag; solid sections may lag a drag by a frame or a few, never stall it. A benchmark row records sectioning the bracket and a
lattice part at a drag step (`scripts/bench.sh`, `docs/verification/performance.md`), measured release on an idle Mac.

### 3.5 What it never does

No command, no undo step, no edited dot, no effect on export, the graph or evaluation. Sketch mode hides the section and
Measure (the scene is ghosted there); leaving sketch mode brings the section back. Inside a group it sections what the
viewport shows. Final preview and Selected node preview are both sectioned.

## 4. Measure

### 4.1 The tool

**Measure** is a top bar button and View ▸ Measure (shortcut: builder's call, one that is free in the viewport key context
and not taken by the sketch editor; `M` if free). It is a `ViewportTool` with free 3D navigation, so orbit, pan and zoom work
while measuring. Esc or the button again leaves it. It can be on with or without a section.

A small glass **Measure panel** lists the current measurement and the kept ones, each with its value, a remove button, and
Clear All. Values use the document's units and precision; a mesh-derived value is prefixed "≈".

### 4.2 What can be picked

- **Faces** and **edges** of solids (the existing pick).
- **Vertices**: an edge end within the pick radius on screen snaps to the vertex (from `EdgeCurve` ends or the edge
  polyline's ends; no new kernel table needed unless the builder finds one simpler).
- **Section edges** of the current section: lines and arcs of a solid's section (exact), segments of a mesh's.
- **Mesh surfaces**: a point on a mesh (`MeshRaycast`), for meshes only.

Hovering highlights what a click would pick (faces already highlight; edges, vertices and section edges need a hover look).

### 4.3 What it measures

What it shows depends on what is picked, as in Fusion:

| Picks | Shown |
|---|---|
| one circular edge or arc | radius and diameter |
| one cylindrical face (a hole's wall) | radius and diameter |
| one straight edge | length |
| one face | area |
| two of anything | **shortest distance**, drawn between the two closest points |
| two straight edges, or two flat faces, or one of each | the angle between them as well |
| two circles or cylinders | centre-to-centre distance as well (my call; common for hole spacing) |

The shortest distance on solids is OpenCascade's (`BRepExtrema_DistShapeShape` between the two sub-shapes, a new kernel
call returning the distance and both witness points). A section edge is measured as its exact curve (a solid's) or its
segments (a mesh's). Cylinder radius needs `FaceInfo` to carry the radius and axis point (added to `describe_face` and
`occt_face_info`; `FakeKernel` answers for its own faces).

Results are drawn as viewport dimensions: distance `.linear`, radius and diameter `.radial`, angle `.angular`, in a
measurement tint (a theme role `measure` or the existing dimension colour; builder's call). A third click starts a new
measurement; the finished one is **kept** on screen and in the panel until removed.

### 4.4 Measurements follow the model

A kept measurement stores its picks the way the graph stores picks (`FacePick` / `EdgePick` by tag subsets; a section edge
by the section and the source face it came from; a mesh point by its world position), not by IDs. After each evaluation
they re-resolve and re-measure, so changing a wall's thickness updates its measurement. One that no longer resolves stays
in the panel greyed, "No longer found", until removed; it never silently jumps to another edge.

## 5. Kept with the file

`ViewState` gains two optional keys (no format bump; older readers ignore them):

- `section`: on/off, the reference (an origin plane, or a `FacePick`), the offset and the flip.
- `measurements`: the kept measurements' picks.

They are written on save like the camera, never mark the document edited, and New starts without them. An unreadable entry
is dropped on reading.

## 6. Order of work

1. **Section, part A:** replace the Cut view: reference + offset + flip, the panel, Section from Face, every platform, view
   state. (Still the old back-face look.)
2. **Section, part B:** the cap and outlines: the kernel section, the mesh slice, the cap pipeline in both renderers, the
   hatch, theme roles, the benchmark row.
3. **Measure, part A:** the tool, faces/edges/vertices, radius/diameter/length/area/distance/angle, the panel, dimensions,
   the new kernel calls, `FaceInfo` radius.
4. **Measure, part B:** section edges and mesh points, keeping and re-resolving measurements, view state.

Each is its own plan in `docs/superpowers/plans/`, its own human-check group in `docs/verification/human-checks.md`
(SA-A, SA-B, ME-A, ME-B), and its own CLAUDE.md status line. The Cut view's checks (MT-4, XP-24's cut part) are rewritten for
the section.

## 7. Constraints

- Project rules apply: OCCT only behind `Kernel` and under `OCCTKernel.serialized`; no Metal/CoreGraphics outside
  `#if canImport`; MSL, HLSL and Swift GPU structs changed together; Swift Testing; SwiftLint clean; twelve "Test run with"
  lines on every platform.
- A MetalUI bug or missing feature is logged in `docs/metalui-gaps.md` and requested from the MetalUI session, never worked
  around here.
- Text in the panels follows the project's wording (plain English, numbers through `Locale.messages`).

## 8. Left to the builder

The panels' exact layout and placement, the hatch's spacing and width on screen, the shortcut, whether the cap goes in the
ID pass or section edges are picked on the CPU, how a face is built from section wires in OCCT, the mesh slicer's welding
tolerance, and the hover look of edges and vertices.

## 9. Settled after the builder check

- **Face reference frame.** The plane passes through the face (its plane, not its centroid) with its normal the face's
  **outward** normal; a positive offset goes **into the material** (against the outward normal), so typed depths are
  positive. The cut-away side is the outward side unless flipped. A re-resolved face that only matches by guess (the
  `FacePick` warns) is still used, and the panel shows the pick's warning in its own words.
- **Which mesh is sliced.** The mesh the viewport shows, at whatever pass the progressive preview has reached; a finer pass
  re-slices. No pass is forced. The Measure panel shows "≈" and the mesh's resolution next to a mesh-derived value.
- **Several items.** Each shown, non-ghosted item is sectioned on its own and capped on its own, with its own hatch angle
  (by its order in the scene). Overlapping items' caps overlap; nothing is unioned.
- **Section edges.** One section edge is one piece of a section wire: a line, an arc (exact, `EdgeCurve`) or, where OCCT
  gives another curve, a polyline. Distances to a line or arc are exact (the section's curve built as an OCCT edge on the
  plane and measured with `BRepExtrema_DistShapeShape`); to a polyline piece they are measured on the polyline and shown
  with "≈", never passed off as exact. A section-edge pick is stored as the source face's `FacePick` plus the piece's
  position along that face's section (index and midpoint, the midpoint breaking ties after an edit).
- **Vertices.** A vertex pick is an `EdgePick` plus which end (start or end). A closed circle has no vertex; snapping
  offers its centre instead (stored as the edge pick and "centre").
- **Mixed picks** (a mesh and a solid, or two different parts) are allowed. With a mesh on either side the distance is
  measured on the shown meshes (the solid's display mesh included) and shown with "≈".
- **Measure among other tools.** Measure, the sketch editor and the model dimension tool (D) are exclusive: starting one
  ends the others. While measuring, clicks measure (they do not select nodes); handles still drag; the right-click menu
  offers Look At and Section from Face.
- **Groups and reopening.** The section and the measurements belong to the document, not to a level. Picks are stored in
  top-level terms (`GraphContent.relativeToLevel` when made inside a group); one whose level is not shown is listed in the
  panel and not drawn. After Open nothing is drawn until the first evaluation resolves the picks.
- **Platforms.** Each part lands on macOS, Linux and Windows together (the pass rules), render tests under lavapipe and
  WARP as the other SDL passes.
- **Benchmarks** record, they do not gate the merge.

## 10. Calls I made (not discussed with the user)

- One section at a time; hatch angles per body rather than colours.
- Section replaces the Cut view rather than sitting beside it.
- Single picks show length (straight edge) and area (face) as well as radius/diameter; two circles show centre-to-centre.
- Measurements re-measure live as the model changes, and lost ones stay greyed rather than vanishing.
- Sketch mode hides both tools.
- Everything in §9: a face section's positive offset goes into the material; meshes are sliced at the shown preview pass,
  never forcing a finer one; non-exact values are marked "≈"; Measure, sketching and D are exclusive.
