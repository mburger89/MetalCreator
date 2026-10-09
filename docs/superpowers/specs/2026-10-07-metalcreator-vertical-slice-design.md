# MetalCreator — Vertical Slice Design

- **Date:** 2026-10-07
- **Status:** Draft, awaiting review
- **Scope of this spec:** the first sub-project, a *vertical slice*. It is a thin, end-to-end version of the graph engine, kernel bridge, profile nodes, viewport and node editor, inside a MetalUI app.

## 1. Intent

MetalCreator is a node-based parametric CAD application for macOS, built on the MetalUI framework (`../MetalUI`). Modelling operations (Extrude, Revolve, Loft, Boolean, Fillet, Chamfer, …) are nodes wired together in a graph, as in Blender's geometry nodes or Rhino's Grasshopper. The graph *is* the model.

**Goals (from the user):**
1. Rapid iteration on how a part looks and performs: many variants, no costly rework.
2. Feature patterns and surface textures of the kind that until now only Grasshopper could do.
3. A real tool the user will use for their own parts.
4. A large app that proves out and stress-tests MetalUI.

**Manufacturing targets:** both. CNC and machinists need exact B-rep solids exported as **STEP**. 3D printing needs **STL**, and later 3MF. A later sub-project adds mesh-based and implicit textures on top of B-rep parts.

**Constraints:**
- Swift 6 language mode with strict concurrency, built with the Swift 6.4 toolchain. Tests use Swift Testing.
- macOS only. MetalUI's `MetalView` is macOS-only, and MetalUI excludes iOS and touch input.
- **Prefer pure Swift.** OpenCascade (OCCT) is approved as the B-rep kernel, but it must stay behind a Swift protocol in a single target, so it can eventually be ported to Swift one operation at a time.
- MetalUI shortcomings are fixed **in MetalUI**, through its own process, not worked around in the app (§9).

## 2. The program, decomposed

| # | Sub-project | In this slice? |
|---|---|---|
| 1 | Graph engine | thin version |
| 2 | Kernel bridge (Swift `Kernel` protocol + OCCT) | thin version |
| 3 | Node editor on MetalUI | thin version |
| 4 | 3D viewport | thin version |
| 5 | Profile nodes | thin version |
| 6 | Constraint sketcher (Sketch node + pure-Swift 2D solver) | **no.** Its own spec, written right after this one, and it can be built in parallel |
| 7 | Patterns, fields, surface textures, lattices | no |
| 8 | Variants and versions UI | no (but graph parameters are designed for it, §4.1) |

## 3. Architecture

### 3.1 Package layout

The project is the `MetalCreator` SwiftPM package. It depends on MetalUI via `.package(path: "../MetalUI")`. The existing placeholder target `MetalCreator` and its test target are replaced. The package targets `.macOS(.v14)` to match MetalUI.

| Target | Pure Swift | Depends on | Purpose |
|---|---|---|---|
| `CreatorGeometry` | ✅ | — | Value types: `Vector2/3`, `Transform`, `Plane`, `Axis`, `Angle`, `Profile2D` (closed loops of line and arc segments), `BoundingBox`, `DisplayMesh`. Units are millimetres, as `Double`. |
| `CreatorKernel` | ✅ | Geometry | The `Kernel` protocol, `Solid`, the topology table, `TopoTag`, `KernelError`, and `FakeKernel` for tests. |
| `COCCT` | ❌ C/C++ | OCCT (system library) | A thin `extern "C"` shim over OCCT. |
| `CreatorOCCT` | ✅ (Swift side) | Kernel, COCCT | `OCCTKernel: Kernel`. **This is the only target that may import `COCCT`.** |
| `CreatorGraph` | ✅ | Kernel | The graph model, socket types, values and broadcasting, `NodeDefinition`, registry, `Evaluator`, commands and undo, file format. |
| `CreatorNodes` | ✅ | Graph, Kernel | The built-in node definitions (§7.1). These are UI-free: they describe their inspector and handles as data. |
| `CreatorViewport` | ✅ | Kernel, MetalUI | The 3D viewport on `MetalView`. |
| `CreatorEditor` | ✅ | Graph, Nodes, MetalUI | The graph panel, the context inspector, the add-node palette. |
| `MetalCreatorApp` | ✅ (executable) | all except COCCT | Window, document, menus, export. |

Test targets mirror the library targets: `CreatorGeometryTests`, `CreatorKernelTests` (FakeKernel), `CreatorOCCTTests` (the conformance suite), `CreatorGraphTests`, `CreatorNodesTests`, `CreatorViewportTests`, `CreatorEditorTests`.

### 3.2 Boundary rules

- Graph, nodes, viewport and editor see only `any Kernel` and Swift value types. No OCCT type, header or naming crosses `CreatorOCCT`.
- `CreatorNodes` does not import MetalUI. Inspector sections and viewport handles are declared as data (§6.4) and rendered by `CreatorEditor` and `CreatorViewport`.
- Observable state lives in `@MainActor @Observable` model classes. View structs hold no logic that tests need to reach.

## 4. Graph engine (`CreatorGraph`)

### 4.1 Data model

All of these are `Sendable` value types:

- `Graph` holds `nodes: [NodeID: Node]`, `links: [Link]` and `parameters: [GraphParameter]`.
- `Node` holds `id`, `typeID` (for example `"creator.extrude"`), `typeVersion`, `name`, `inputValues: [SocketName: Value]` (constants used when an input is not wired), `position: Point` (§6.2), and `isOutput: Bool`.
- `Link` holds `from: (NodeID, SocketName)` and `to: (NodeID, SocketName)`. An input takes at most one link. An output can feed any number of links.
- `GraphParameter` holds `id`, `name`, `type` and `value`, plus optional `min`, `max` and `step`. Parameters appear in the inspector as document parameters. A *variant* (sub-project 8) will be a named set of parameter values, so nothing else in the model needs to change for variants.

### 4.2 Socket types and values

`enum SocketType { number, integer, bool, vector, plane, profile, solid, edgeSet, faceSet }`. The `mesh` type is reserved for sub-project 7.

- Implicit conversions: integer → number, and vector → plane (the XY plane through the point). Every other mismatch is refused when the user tries to connect.
- Values: `enum Value { case one(Scalar), list([Scalar]) }`.
- **Broadcasting.** A node evaluates once per item of its *longest* list input. A shorter list repeats its last item, and a `one` acts as a list that repeats forever. Outputs from a broadcast are lists. Nested data trees are deferred to sub-project 7, but the `Value` enum is meant to grow, and no code may assume it has exactly two cases.

### 4.3 Node definitions

```swift
protocol NodeDefinition: Sendable {
    static var typeID: String { get }
    static var typeVersion: Int { get }
    static var category: NodeCategory { get }        // value, profile, solid, selection, feature, output
    static var inputs: [SocketSpec] { get }          // name, type, default, unit, range
    static var outputs: [SocketSpec] { get }
    static var inspector: [InspectorSection] { get } // §6.4
    static var handles: [HandleSpec] { get }         // §6.5
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs
}
```

The `NodeRegistry` maps `typeID` to a definition. Each definition also supplies `migrate(from:)`, which upgrades nodes saved under an older `typeVersion`.

### 4.4 Evaluation

- An `actor Evaluator` owns the cache. The `DocumentModel` asks it to evaluate a **demand set**: every output-flagged node, plus whichever node is selected in "Selected node" preview mode, plus export targets.
- **Pull-based and topological.** Only nodes upstream of the demand set run.
- **Per-node cache.** The key is a hash of the node's `typeID`, `typeVersion`, its constant input values and the cache keys of its upstream nodes. A changed value invalidates only that node and everything downstream of it.
- **Cancellation.** Every edit starts a new evaluation generation and cancels the previous `Task`. Cancellation is checked between nodes. A single OCCT call cannot be interrupted in the slice. Interrupting long operations through OCCT's progress indicator is deferred.
- **Memory.** The cache is LRU-bounded (default 512 MB of estimated solid and mesh memory). Entries for nodes that have been deleted are dropped immediately.
- **Results.** Each node's result goes to the main actor as a `NodeState`: `.idle`, `.evaluating`, `.ok(duration)`, `.warning(message)`, or `.error(message)`. Outputs are delivered too.
- **Errors.** A node that throws shows `.error`, and nodes downstream of it show `.idle` with "missing input". The viewport keeps showing the **last good** result of each output, drawn as a ghost (§6.3). Kernel errors are mapped to plain language. For example, `KernelError.filletFailed` becomes "Radius 8 mm is too large for the selected edges (max ≈ 5.9 mm)" when OCCT reports enough information, and a generic message otherwise.

### 4.5 Commands, undo and files

- Every change is a `GraphCommand` with `apply` and `revert`: add or remove a node, connect, disconnect, set a value, move, rename, set a parameter, toggle output. Commands that arrive during one continuous slider or handle drag are **coalesced into one undo step**.
- The file is `.mcgraph`: UTF-8 JSON containing `formatVersion`, the graph, the parameters, and the editor's view state (dock side, canvas transform, camera). It stores **only the recipe, no geometry**. Loading an unknown `typeID` keeps that node as an inert "missing node" with its data intact, so the file round-trips without losing anything.

## 5. Kernel boundary and topological naming

### 5.1 The protocol

```swift
protocol Kernel: Actor {
    func extrude(_ profile: Profile2D, on plane: Plane, distance: Double, mode: ExtrudeMode, tag: NodeTag) throws -> Solid
    func revolve(_ profile: Profile2D, on plane: Plane, axis: Axis, angle: Angle, tag: NodeTag) throws -> Solid
    func loft(_ sections: [(Profile2D, Plane)], ruled: Bool, tag: NodeTag) throws -> Solid
    func boolean(_ op: BooleanOp, _ a: Solid, _ b: [Solid], tag: NodeTag) throws -> Solid
    func transform(_ s: Solid, by t: Transform, tag: NodeTag) throws -> Solid
    func fillet(_ s: Solid, edges: [EdgeID], radius: Double, tag: NodeTag) throws -> Solid
    func chamfer(_ s: Solid, edges: [EdgeID], distance: Double, tag: NodeTag) throws -> Solid
    func tessellate(_ s: Solid, tolerance: Double) throws -> DisplayMesh
    func export(_ solids: [Solid], format: ExportFormat, to url: URL) throws   // .step, .stl
}
```

- `ExtrudeMode` is `.oneSided` or `.symmetric`. "To face" is deferred.
- `Solid` is an immutable `Sendable` final class. It holds an opaque kernel handle, released in `deinit`, and a **topology table**. For each face the table records `FaceID`, surface kind (plane, cylinder, cone, B-spline, …), normal or axis, area, centroid and `tags`. For each edge it records `EdgeID`, curve kind (line, circle, B-spline), direction, length, midpoint, convexity, its two adjacent faces and `tags`. Selection rules run in Swift against this table, without calling back into the kernel. **Seam edges** (an edge with the same face on both sides, such as the seam OCCT puts on every cylindrical hole wall) are flagged `isSeam` and excluded from every selection rule. Otherwise "edges parallel to Z" would catch each hole's seam and the fillet would fail.
- `DisplayMesh` contains positions, normals and indices, a per-triangle `FaceID`, and per-edge polylines tagged with `EdgeID`.
- Kernel calls are serialized because `Kernel` is an actor. OCCT shapes are immutable, so cached solids can be shared freely.

### 5.2 OCCT bridge

- `COCCT` exposes plain C functions over opaque handles (`occt_shape_t*`). Every entry point catches `Standard_Failure` and `std::exception` and returns `{status, message}`. No exception ever crosses into Swift.
- History comes from OCCT's `BRepBuilderAPI_MakeShape::Generated`, `::Modified` and `::IsDeleted`, which `CreatorOCCT` uses to carry tags across operations (§5.3).
- **Build.** For development, OCCT is linked from Homebrew `opencascade` 7.9.3 through a `systemLibrary` target with a `pkg-config`/module map. Bundling OCCT's dylibs into a signed `.app` is **deferred** (see §11).

### 5.3 Topological naming

The problem is that "fillet these edges" must keep meaning the same edges after upstream parameters change. MetalCreator never stores edge indices. Instead:

1. **Creation tags.** Each operation tags the faces it creates with stable roles: `TopoTag(node: NodeID, item: Int, role: Role)`. `item` is the broadcast list index, and `Role` is one of:
   - Extrude: `.startCap`, `.endCap`, `.side(segment: k)`
   - Revolve: `.side(segment: k)`, `.startCap`, `.endCap` (only for a partial revolve)
   - Loft: `.startCap`, `.endCap`, `.side(segment: k)`
   - Fillet and Chamfer: `.blend(sourceEdge: EdgeKey)`
2. **Propagation.** A face that an operation modifies keeps its tags. A face it generates gets the new operation's tags. Boolean results keep the tags of both operands. A face split by a boolean keeps its tag on every fragment.
3. **Edge identity.** An edge's *key* is the unordered pair of tags of its two adjacent faces, for example `{Extrude#3[0].endCap, Extrude#3[0].side(2)}`. Several edges can share a key, such as the four hole rims of a broadcast. A key with an item index tells them apart.
4. **Selection is always a rule.** `edgeSet` and `faceSet` values come only from rule nodes (§7.1). There is no "list of indices" node.
5. **Picking writes a rule.** Picking edges in the viewport, from the "Pick edges in view…" inspector button or the face context menu, creates or updates an **Edges by Tag** node holding the picked edge keys. When a key matches more edges than were picked, the node also stores the picked edges' order within that key, sorted deterministically by midpoint along X, then Y, then Z.
6. **No silent drift.** When a rule's match count differs from the count recorded when it was picked, or is zero, the node shows a `.warning` ("matched 6 edges, expected 4"). It still evaluates with what it matched.

### 5.4 `FakeKernel`

`FakeKernel` is a pure-Swift kernel that represents solids as tagged axis-aligned boxes. It is used for graph, evaluator, broadcasting, caching, cancellation and editor tests. It supports extrude of rectangles, booleans (approximated by bounding boxes), transform, tags, and a deterministic fake fillet. It is **not** geometrically correct, and the conformance suite never runs against it.

## 6. User interface

The direction was chosen in the visual brainstorm: **"Model-First," refined, in Dracula.**

### 6.1 Window layout

```
┌───────────────────────── glass top bar ─────────────────────────┐
│ ● ● ●  bracket.mcgraph        Preview: Final ▾     Undo Redo Export│
├────────────┬───────────────────────────────────────┬──────────────┤
│ Graph      │ ┌────┐                                │ Context      │
│ panel      │ │cube│      full-bleed 3D viewport    │ inspector    │
│ (glass,    │ └────┘      (model in the centre)     │ (glass,      │
│ docked     │                                       │  changes with│
│ left,      │                                       │  selected    │
│ flows ↓)   │                                       │  node)       │
└────────────┴───────────────────────────────────────┴──────────────┘
```

- The **viewport fills the window**. The top bar, graph panel and inspector float above it as translucent glass panels (blur and a 1-pt hairline border).
- The **graph panel** has three dock states: **Left** (the default, a vertical column, graph flows top to bottom), **Bottom** (a horizontal strip, graph flows left to right) and **Hidden** (⇥ toggles it). The panel can be resized along its inner edge. Buttons in the panel header switch the dock.
- The **inspector** is docked on the right and shows the selected node (§6.4). With nothing selected, it shows the document parameters.
- **Preview** has two modes. *Final* shows all output-flagged nodes. *Selected node* shows only the selected node's output, for stepping through the recipe.

### 6.2 Graph panel (`CreatorEditor`)

- Nodes are MetalUI components placed under a canvas transform for pan and zoom. Wires are bezier `Path`s coloured by the type of their source socket.
- **Flow follows the dock.** When docked left, inputs sit on the **top** edge of each node and outputs on the **bottom**. When docked at the bottom, inputs are on the left and outputs on the right. Each node stores one canonical position in left-to-right coordinates. The vertical layout is its **transpose** (x↔y), so switching docks is deterministic and lossless.
- Node anatomy: a coloured header (by category, §6.6) with the node name, then rows for inputs with inline value fields when unwired. A status badge sits at the top-right of the header: a spinner, the evaluation time in ms, ⚠, or ✕.
- **Selection.** A selected node is outlined **in its own header colour**, with no glow (user decision, 2026-10-08).
- Interactions in the slice:
  - Drag from a socket to connect. Dropping onto an occupied input replaces its wire. Invalid drops are refused with a brief shake.
  - Click to select, Shift-click to extend, ⇧-drag on empty canvas to box-select. A plain drag on empty canvas pans.
  - ⌥-drag duplicates. Delete removes. ⌘C, ⌘V and ⌘D copy, paste and duplicate.
  - **Tab** or **Space** opens the add-node search palette at the cursor.
  - The panel pans and zooms with the stopgap bindings (§9) until MetalUI's C7 item lands.

### 6.3 Viewport (`CreatorViewport`)

The viewport is built on `MetalView`, using the device, command buffer and colour target it provides. It owns its own resources: a depth texture and an MSAA target (4×) sized to the surface, plus pipelines compiled once.

- **Shaded pass.** The part is lit with a studio matcap in neutral lavender greys (§6.6). Hovered faces get a faint cyan tint. Faces and edges selected by the active rule glow **pink**, the colour of selection rules. When an output's node is in error, its last good result is drawn **ghosted** (desaturated, at 40% opacity).
- **Edge pass.** B-rep edges (from `DisplayMesh` edge polylines, not triangle wireframe) are drawn as anti-aliased screen-space lines in `#f8f8f2`.
- **ID pass.** This renders to an `r32Uint` target encoding `(solid index, face or edge, id)`. A pick reads back the pixel under the cursor. Edges are drawn wider in this pass, about 6 px, so they're easy to pick.
- **Overlays.** A ground grid (spacing adapts to zoom in 1, 10 or 100 mm steps), an axis triad, and a unit and grid label.
- **View cube**, at the top-left of the model area:
  - Faces are labelled TOP, BOTTOM, FRONT, BACK, LEFT and RIGHT. The face under the cursor is highlighted cyan.
  - **Click a face** and the camera animates (about 250 ms) to look straight at it, **switching to orthographic** projection.
  - **Click an edge or corner** of the cube for a 45° or isometric view. These views keep the current projection.
  - **Drag the cube** to orbit freely.
  - **Arrow buttons** rotate 90° to the adjacent face. **⌂ Home** returns to the document's home view, which can be set from a menu.
  - A projection and shading menu sits below the cube (Perspective or Orthographic, Shaded or Shaded+Edges).
- **Right-click context menu on a model face:**
  - **Look At**: animates the camera to face that face's normal, orthographic, framed on the face.
  - **Select Edges of Face**: creates an Edges by Tag rule for that face's boundary edges.
  - **Show Producing Node**: selects and scrolls to the node that created the face (from its tags).
- **Camera.** Orbit pivots on the point under the cursor, or on the bounds centre if there's nothing under the cursor. Zoom goes towards the cursor. **F** frames the selection, or everything.
- **Tessellation** is cached per `Solid` and display tolerance, and only re-tessellated when one of those changes.

### 6.4 Context inspector

Each `NodeDefinition` declares `inspector: [InspectorSection]` as data. A section is a title plus controls from a closed set: `slider(socket, unit, range)`, `number`, `integer`, `toggle`, `segmented(options)`, `planePicker`, `anchorGrid`, `ruleSummary(socket)`, `button(action)`. `CreatorEditor` renders these with MetalUI controls. Every control is bound to the node's unwired input value. A wired input shows read-only text such as "wired from Edges ∥ Z".

For example, **Fillet** shows a Radius slider, a "Tangent chain" toggle, an EDGES section (rule summary, match count, and a "Pick edges in view…" button that enters pick mode) and a "Show handle in view" toggle. **Extrude** shows segmented Distance or Symmetric, a Distance slider, and a Direction menu (plane normal or reversed). **Rounded Rect** shows Width, Height, Corner R, Plane and Anchor.

A header bar in the node's category colour shows the node name and its status. Below the node's sections, **Document Parameters** are always listed.

### 6.5 In-view handles

Each `NodeDefinition` declares `handles: [HandleSpec]`: `linear(socket, origin, axis)` or `radial(socket, edgeRef)`. Each is resolved against the node's output and drawn in the viewport in the node's category colour, with a value label. Dragging a handle edits the socket, coalesced into one undo step. In the slice: the **Extrude distance arrow** and the **Fillet and Chamfer radius or distance handle**. Rectangle edge handles are deferred.

### 6.6 Visual language — themes, Dracula by default

Colours are a **theme**: a colour for every *role*, never a hue (user decision, 2026-10-07; M6). The table below is
the default theme, **Dracula**. The built-in themes are Dracula, **Alucard** (Dracula's official light variant) and
**Nord**, read-only and chosen from View ▸ Theme; switching applies at once, to the panels and the viewport. The roles
(`ThemeColors` in `CreatorStyle`): the background gradient's top and bottom; the glass fill and hairline; panel base;
node body; field; foreground (primary text); comment (secondary, hint and dimmed text); text on accents; accent
(primary buttons, slider fill); focus (hover and focus outside the graph); selection (what a rule selects); a header
colour for each node category (value, profile, solid, selection rule, feature, output), which also colours its
sockets, wires, selection glow and in-view handles; status success, warning and error; the part shading ramp (light
and dark); B-rep edges; the grid's minor and major lines; the view cube's face, rim and label ink; the X, Y and Z axes;
and the sketcher's under-constrained, fully constrained, conflicting, construction and projected geometry (sketcher
spec §8). Themes are app-level and never stored in a `.mcgraph` file. Custom themes and `.mctheme` files are the
Themes milestone after M6 (roadmap).

| Role | Colour |
|---|---|
| Window and viewport background (gradient) | `#3a3d4e` → `#191a21` |
| Glass panels | `#21222c` at about 86% with blur, hairline `#ffffff1f` |
| Panel base, dark text on accents | `#282a36` |
| Node body, fields, tracks, dividers | `#343746` / `#44475a` |
| Primary text / secondary and hint text | `#f8f8f2` / `#6272a4` |
| **Profile** nodes and sockets | Green `#50fa7b` |
| **Solid** nodes and sockets, primary buttons, slider fill | Purple `#bd93f9` |
| **Selection rule** nodes and sockets, and the edges and faces they select | Pink `#ff79c6` |
| **Feature** nodes (Fillet, Chamfer), and in-view handles of feature nodes | Orange `#ffb86c` |
| **Value** nodes | Comment `#6272a4` |
| **Output** node | Cyan `#8be9fd` |
| Focus outside the graph (view-cube hover and active face, keyboard focus), viewport hover | Cyan `#8be9fd` |
| Status OK / warning / error | `#50fa7b` / `#f1fa8c` / `#ff5555` |
| Model shading | Neutral lavender greys (about `#c5c8de` → `#6f739a`), edges `#f8f8f2` |

Rules:
- A node's selection outline always uses **its own header colour**.
- Text on accent fills (headers, primary buttons, badges) is the theme's text-on-accent colour, chosen for contrast:
  `#282a36` in Dracula.
- Colours are defined once, as the roles of the built-in themes in `CreatorStyle`, and used everywhere by role: views
  through `Palette` (`CreatorEditor`), the GPU through `ViewportPalette` (`CreatorViewport`).
- Fonts use MetalUI's semantic text styles. No sizes are hard-coded.

## 7. Scope of the vertical slice

### 7.1 Nodes (26)

- **Values:** Number, Integer, Vector, Plane (XY, XZ or YZ plus offset), Graph Parameter, Series (start, step, count), Range (start, end, count), Grid Points (count X×Y, spacing, centred)
- **Profiles:** Rectangle, Rounded Rectangle, Circle, Regular Polygon, Polyline (points, closed)
- **Solids:** Extrude, Revolve, Loft, Boolean (union, subtract, intersect), Transform (move and rotate)
- **Selection:** Edges by Tag, Edges by Direction (axis, angle tolerance), Edge Filter (convex, concave, length range), All Edges, Edge Set Op (union, subtract, intersect)
- **Features:** Fillet (constant radius), Chamfer (equal distance)
- **Output:** Output (marks for preview and export, with a name)

### 7.2 Acceptance demo — parametric mounting bracket

The slice is accepted when the following can be built from scratch in the app, using only the nodes above, and saved, reopened and exported:

1. A Rounded Rectangle plate (graph parameters `Width` = 60, depth 40, corner R 4), extruded by `Wall` = 6.
2. Holes from Grid Points (driven by `Hole count` = 4, as 2×2) → Circle Ø5 (broadcast) → Extrude → **subtracted in one Boolean**.
3. An L-flange from a Rectangle on the XZ plane, extruded and unioned.
4. **Fillet** R3 on `Edges by Direction(Z) ∩ Edge Filter(convex)`. **Chamfer** 0.5 on the plate's top-cap edges, using `Edges by Tag`.
5. Export **STEP**, which opens with matching geometry in FreeCAD or Fusion, and **STL**, which a slicer accepts as manifold.
6. Change `Width` from 60 to 90 and `Hole count` from 4 to 6 (2×3). The fillet and chamfer must still land on the intended edges, no node may show a warning, and both exports must succeed again.

### 7.3 Performance targets (measured, not just asserted)

- Panning and zooming a 50-node graph runs at 60 fps on the development Mac.
- While the fillet radius is being dragged on the bracket, the viewport updates within **100 ms** of each value change. Measured from command to presented frame, as the median over a scripted drag.
- Orbiting the viewport with the bracket shown runs at 60 fps.

### 7.4 Milestones (ordered by risk)

| Milestone | Delivers | Exit check |
|---|---|---|
| **M0 — OCCT probe** | Package skeleton, `COCCT` + system-library link, make box → fillet → write STEP from a Swift test | The test passes, and the STEP opens in FreeCAD |
| **M1 — Graph & evaluator** | `CreatorGraph` with `FakeKernel`: values, broadcasting, cache, cancellation, errors, commands and undo, file I/O | Unit tests green |
| **M2 — Kernel ops, tags & history** | Every protocol operation in OCCT, topology tables, tag propagation, conformance suite | Conformance plus naming-stability tests green |
| **M3 — Nodes** | The 26 node definitions with inspector and handle specs | Node tests green, and the bracket evaluates headless |
| **M4 — Viewport** | Shaded, edge and ID passes, camera, view cube, picking, context menu, handles | Model and ID-buffer tests green, human visual check |
| **M5 — Graph panel** | Canvas on MetalUI, both docks, palette, inspector | Editor model tests green, human visual check |
| **M6 — App shell & demo** | Window, glass layout, open, save, export, acceptance demo | §7.2 passes |
| **M7 — Measure & record** | §7.3 measurements, `docs/metalui-gaps.md` completed, CLAUDE.md updated | Numbers recorded |

The pure-Swift M1 can proceed while M0 is being solved.

## 8. Testing

All tests use Swift Testing.

- **Graph and evaluator** (FakeKernel): topological order, cache hits and misses after each kind of edit, broadcasting rules, cancellation of superseded generations, error propagation and last-good retention, command apply and revert symmetry, drag coalescing, JSON round-trip including unknown nodes and `typeVersion` migration.
- **Kernel conformance** (OCCT), checked analytically to a tolerance of 1e-6 relative:
  - The volume of a 10×20×30 box extrusion is 6000.
  - Filleting one 30 mm edge at r = 2 removes (4 − π)·30.
  - A revolve of a rectangle gives the expected volume for a cylinder or tube.
  - Boolean volumes add up correctly.
  - Face and edge counts and tags are correct after each operation.
  - A STEP export → re-import (through OCCT in the test only) preserves volume and face count.
  - STL output is manifold.

  The suite is written against `any Kernel`, so a future pure-Swift kernel can run it unchanged.
- **Topological-naming stability:** the bracket's fillet and chamfer edge sets keep their meaning (the same tag keys, and the expected counts) across Width 60→90, Hole count 4→6, and a rectangle profile swapped for a polygon.
- **Editor and viewport models:** the dock transpose, hit testing under the canvas transform, connect, refuse and replace rules, the inspector binding wired vs unwired, mapping a pick to a rule, view-cube face to camera orientation, the Look At camera.
- **Offscreen render test:** the ID pass on a known solid returns the expected face and edge IDs at chosen pixels. Pixel colour is not compared.
- **Human checks:** a short `docs/verification/human-checks.md` list, following MetalUI's convention, covers glass panels, Dracula colours, selection outline, handles, and view-cube animation.

## 9. MetalUI dependency and gaps

Already reported to the MetalUI session and queued there as item **C7 "Input API gaps for MetalCreator"**:

1. a public scroll-wheel and trackpad-scroll hook, with phase and momentum
2. `MagnifyGesture` and `RotateGesture`, plus the AppKit magnify and rotate events
3. middle and other mouse buttons, and dragging with the secondary and middle buttons
4. the location of a tap (`SpatialTapGesture`). **Also needed for the right-click context menu to know which face was under the cursor.**
5. setting the cursor from content, and modifier keys during a drag

**Stopgap bindings until C7 lands:**
- Viewport: primary-drag orbits, Shift-drag pans, ⌥-drag or the +/− keys zoom, F frames, plus the view cube.
- Graph panel: drag on empty canvas pans, the +/− keys or the zoom buttons in the panel header zoom, and ⇧-drag box-selects.
- The face context menu and picking use a zero-distance `DragGesture` for the location if MetalUI allows it. If it doesn't, they wait for C7, and the slice's acceptance demo doesn't depend on them because rules can be built in the graph.

**Process:** every gap the app hits is logged in `docs/metalui-gaps.md` with a concrete use case: which button or gesture, expected coordinates, the current workaround. MetalUI's design agent reads that file. The app never patches around a gap in a way that would have to be undone.

**Risks to watch, logged as they happen:** hit testing under a scaled canvas transform, the cost of `Path` with hundreds of wires, frame pacing of a `MetalView` that redraws continuously during drags, the cost of glass blur over a continuously redrawing `MetalView`, and keyboard focus split between the canvas and its fields.

## 10. Risks

| Risk | Mitigation |
|---|---|
| OCCT does not build or link cleanly with SwiftPM | M0 comes first. The fallback is a prebuilt `.xcframework` binary target wrapping the shim. |
| OCCT's history is incomplete for some operation, so tags are lost | The conformance and naming tests catch it. The fallback is geometric matching (normal, centroid) to the previous result for that operation only. |
| OCCT fillets fail for some radii | Clear errors with the maximum radius where possible, and the ghosted last good result. |
| MetalUI performance, or a missing API | Measured in M7. Gaps go to MetalUI (§9). |
| Scope creep from the "to 11" goals | Patterns, textures, sketcher and variants each have their own spec. Not in this slice. |

## 11. Deferred (explicitly out of scope)

- Constraint sketcher and Sketch node (sub-project 6, next spec)
- Sweep, shell, draft, text, "extrude to face", variable-radius fillets, Rectangle edge handles
- Patterns, fields, nested data trees, mesh and SDF textures, lattices (sub-project 7)
- Variants UI and comparison (sub-project 8)
- Node groups and subgraphs, STEP import as a node, multi-body assemblies, 3MF
- Interruptible long OCCT operations, parallel kernel evaluation
- Bundling OCCT into a signed, distributable `.app`
- Multiple documents and windows, localisation (strings are written to be catalog-ready)

## Errata (M0–M1)

- Platforms are `.macOS(.v26)`, not v14.
- `Profile2D` carries its plane, so kernel methods take no `on plane:` parameter.
- OCCT is linked via explicit Homebrew paths (no pkg-config).
- The result cache key includes node identity (the kernel tags created faces with it).
- Graph links are kept in canonical order (by destination), on commands and on load.

## Errata (M3)

- §6.4's closed set of inspector controls gains `vector(socket)` (three number fields) and `parameterPicker(setting)` (Graph Parameter's menu of document parameters).
- §6.4's Fillet "Tangent chain" toggle is dropped: OCCT always follows tangent chains, so the toggle would have no effect.
- §6.4's Extrude "Direction" menu (plane normal or reversed) is a "Reverse direction" toggle (`reversed`).
- §7.1/§7.2 Circle takes a `diameter` (§7.2 says Ø5), not a radius.
- Non-socket node settings (`parameter`, `picks`, `showHandle`) are stored in `Node.inputValues` under `NodeSetting` names, and new nodes are seeded with their `defaultSettings`.
- §4.5's `formatVersion` is 2 from M3 on: `ConstantValue` gained `.edgePicks`. Files from M3 or later are refused by older builds.
- §8's naming-stability bullet: the rectangle that is swapped for a polygon is the L-flange's Rectangle (the only plain Rectangle in §7.2), replaced by a Regular Polygon on the same plane. As written, the swap cannot keep the fillet's meaning. Regular Polygon puts its first corner on +x and has no rotation input, so on the XZ plane none of its sides is parallel to Z. A probe in M3 swapped the flange for 4-, 6- and 8-sided polygons (r 15). In every case `Edges by Direction(Z) ∩ Edge Filter(convex)` was empty, Fillet reported “No edges are selected.”, and Chamfer never ran. Today the four fillet edges are the flange's vertical corners (`side(segment: 1/3)` against the flange's `startCap`/`endCap`). The test is owned by M6, and it does not block M3. It means: the chamfer's picked plate top-cap keys still resolve (subset matching) with no node warning. The fillet set is re-derived by its rule, and its flange keys are expected to change, but its count is pinned. For that, the polygon needs sides parallel to Z, for example a hexagon rotated 30°. M6 either gives Regular Polygon a `rotation` input (a `typeVersion` bump) or uses a Polyline that has vertical sides, and records the counts it pins in the test.

## Errata (M5)

- §6.2's "inline value fields" are read-only text on the node's row. Values are edited in the inspector, because a
  `TextField` on the canvas would compete with the canvas-wide gesture and split keyboard focus (§9's risk list).
  Revisit when MetalUI C7 lands.
- §6.1/§6.2's ⇥ is contextual: Tab opens the add-node palette while the panel is visible, the pointer is over the
  canvas and no palette is open; otherwise it moves keyboard focus as usual. Space always opens the palette. Tab
  hides the panel only when nothing focusable is on screen (in practice never, since the inspector is). While the
  panel is hidden, a "Show graph" button carries Tab as its shortcut, so hiding is never a one-way trip. With the
  pointer over the canvas, Tab opens the palette even from a focused inspector field (docs/metalui-gaps.md M5-b).
- §3.1's `CreatorEditor` row: the library depends on Graph, Kernel, Geometry and MetalUI, not Nodes. It renders
  any `NodeRegistry` it is given, so its tests and the preview use hand-written fixture nodes, and the app shell (M6)
  passes `BuiltInNodes.registry`. `CreatorNodes` is a test-only dependency of `CreatorEditorTests`, where
  `BuiltInNodesInspectorTests` runs every built-in definition through `InspectorBuilder` and `NodeShape`.
- §6.4's inspector also clears an optional input: emptying its field unsets it (for example Grid Points `total`).
- §6.1/§6.6's glass blur and the window gradient wait for MetalUI. Panels are `#21222c` at 86% with the hairline,
  and the preview's background is solid `#191a21` (docs/metalui-gaps.md M5-c, M5-d).
- §6.2's refusal shake is a spring back from a 6-pt offset (no keyframe animation yet, M5-i).
- §6.2's status-badge spinner is a static `◌` glyph while a node evaluates: MetalUI has no `ProgressView` or
  activity indicator yet (docs/metalui-gaps.md M5-j).

## Errata (M6)

- §3.1's `MetalCreatorApp` target is two: the `CreatorApp` library (the `@MainActor @Observable AppModel`, the
  scene and handle builders, the views and the menu bar; the only target joining Graph, Nodes, Viewport and Editor)
  and the `MetalCreatorApp` executable, which opens the window over `OCCTKernel`. The split keeps the model testable
  (§3.2). A new `CreatorStyle` target holds the colour themes (below), which the editor's `Palette` and the viewport's
  GPU colours read.
- §6.6 is themeable, Dracula by default (user decision, 2026-10-07): colours are the roles of a `ColorTheme`
  (`CreatorStyle`: `ThemeColors`, `ThemeStore`), with Dracula, Alucard and Nord built in and chosen from View ▸ Theme.
  §6.6's table is the Dracula theme, and its rule "defined once as named tokens in `CreatorEditor`" now reads "defined
  once, as theme roles in `CreatorStyle`". The theme is the app's and is never saved in a `.mcgraph` file; until the
  Themes milestone it isn't remembered between launches either. Custom themes and `.mctheme` files: roadmap row
  "Themes".
- §6.1's window title, close prompt and full-size glass top bar wait for MetalUI (docs/metalui-gaps.md M6-a, M6-b,
  M6-c): the document's name and "— Edited" are shown in the top bar, New and Open ask before discarding changes, but
  closing or quitting doesn't ask.
- §6.1's "Selected node" preview shows exactly one selected node's outputs; with none or several selected the viewport
  is empty. An edge set previews as its solid with the set's edges selected.
- §6.5's handles are shown for the selected nodes, for unwired number inputs only.
- §7.1 Regular Polygon gains `rotation` (degrees, default 0; `typeVersion` 2). The file format version is unchanged.
- §8's polygon swap (Errata (M3)), ruled by M6 plan Decision 9, signed off by the user (2026-10-07): with the flange's
  Rectangle swapped for a hexagon turned 30° (r 15, lifted 15 mm so it stands on the plate), the fillet's rule
  re-derives 4 edges on the hexagon's vertical sides, but Errata (M3)'s promise for the chamfer does not hold. The union
  had merged the plate's left and right faces with the rectangle flange's coplanar sides, so two of the five picks
  recorded on the rectangle bracket name the flange's side tags. After the swap those two match nothing and Edges by
  Tag warns ("Matched 0 edges, expected 2; 0 edges, expected 2.", §5.3 rule 6); the three plate-only picks resolve
  unchanged, but OCCT refuses to chamfer that partial chain, so the Chamfer is in error ("Chamfer failed: …") and the
  Output has no result: the part is gone (the last good one shows as a ghost, and Export refuses) until the user
  re-picks. Recording each side's minimal identifying tag subset doesn't rescue it: the two picks then resolve, but
  match 1 edge each where they matched 2 (the rectangle flange had split the plate's top edges), so the warning and
  the error stay. `BracketAcceptanceTests.swappingTheFlangeRectangleForAPolygonRederivesTheFilletAndFlagsTheChamferDrift`
  pins all of it. Owner of the fix: roadmap row "Naming: picks on merged faces".
- §6.3's "edges selected by the active rule glow pink" holds in Selected-node preview and in pick mode, and in Final
  only when the rule's own solid is shown. A rule feeding a Fillet or Chamfer is on the solid before the feature,
  which Final doesn't show, so selecting it glows nothing (the viewport draws no edges on ghosts or on solids it
  doesn't show). Pinned: `SceneTests.aRuleSelectedInFinalPreviewGlowsOnlyOnItsOwnSolid`. Owner: roadmap row
  "Viewport: a selected rule's edges over the Final part".
- §6.3's Look At is framed on the face, but in the whole viewport, not the model area the panels leave; so are the
  first framing and F. Owner: roadmap row "Viewport: frame in the model area".
- §6.2 "inline value fields" (Errata (M5)) gained a commit rule: a typed value is committed on Return, when its field
  loses focus, and on the next canvas or viewport press, selection change, pick, Undo or Redo, save or export.
