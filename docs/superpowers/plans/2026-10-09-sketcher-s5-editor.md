# Sketcher S5a — the Sketch Editor in the Viewport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Edit a Sketch node's sketch in the 3D viewport: enter from "Edit sketch", look at its plane, draw lines, arcs, circles and points with horizontal/vertical/coincident inference, add constraints and dimensions, drag points with the live solve, and store every edit as one undo step, with exposed-dimension sockets drawn and wired everywhere.

**Architecture:** A new graph-free target `CreatorSketchEditor` holds `@MainActor @Observable SketchEditorModel` (tools, stroke, selection, live solve, inspector rows) and its thin MetalUI views (`SketchToolbar`, `SketchInspector`). The viewport gains two generic hooks, `ViewportModel.tool` (a `ViewportTool` takes the primary pointer, with a `ViewportProjector` for screen → plane) and `showOverlay(_:)` (world-space lines and points in sketch colour roles, plus a plane grid), so `CreatorViewport` never learns what a sketch is. The app shell (`CreatorApp`) owns a `SketchSession` while a node is edited, ghosts the scene, puts the toolbar in the top bar and the lists in the inspector, and turns each `SketchCommit` into one `.batch` graph command (`SketchStore`) that keeps an exposed dimension's value and wire in one place.

**Tech Stack:** Swift 6.4 (language mode 6, strict concurrency), Swift Testing, SwiftPM, MetalUI (`../MetalUI`, master 67a579e with C7's input APIs), Metal for the overlay lines (the viewport's existing line pipeline, no shader change).

**Spec:** `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md` (§2 module table, §8 Editor, §9 S5 row, §10 Editor tests, Errata (S4)) and the handoff `docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md` ("S4 → S5 (editor)", "S5 (editor)"), under the binding parent spec `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` with all its Errata. Task 11 writes this plan's choices into the sketcher spec as "Errata (S5a)".

## Why S5 is split, and what S5a is

S5 as specified is two plans' worth. Projection and "New sketch on face" need the viewport's ID-buffer picks routed through the tool, kernel topology (`EdgePick`/`FacePick`) in the editor's commits, a new face-menu item and two-node insertion batches; Trim/Fillet/Mirror/Pattern each need their own tool states over `SketchCommands`; double-click-to-edit lives in the graph canvas's gestures (`GraphPanelInput`), which the graph-input track is rewriting right now. Folding those in would take this plan to ~18 tasks and into another track's files. **S5a** (this plan, 11 tasks) delivers a complete, usable editor: entering and leaving sketch mode, drawing, constraints, dimensions, the live solve, and the five `inputs(for:)` readers. **S5b**'s scope is listed at the end.

## Global Constraints

- Swift 6 strict concurrency (`swiftLanguageModes: [.v6]`); no `@unchecked Sendable`, no `nonisolated(unsafe)`, no GCD.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`); never XCTest.
- Shared state is `@MainActor @Observable` models; behaviour lives in models, views are thin MetalUI `Component`s.
- One type per file (test fixture files under `Support/` may hold several, as the repo's do).
- No force unwraps or force `try`; number text uses `FormatStyle` (`.formatted(...)`), never `String(format:)`.
- `swiftlint lint --strict` reports zero violations (`.swiftlint.yml`: line length 140, type body 250, cyclomatic complexity 10).
- A `swift test` run passes only if its exit code is 0 **and** no line says "recorded an issue" or "failed after".
- `CreatorSketch` imports only `CreatorGeometry` and Foundation (unchanged here). `CreatorSketchEditor` must not import CreatorGraph or CreatorNodes (sketcher spec §2: graph-free; the app shell joins). §2's table also lists CreatorKernel, which isn't needed until Project (S5b, Errata (S5a)), so S5a leaves it out.
- `CreatorViewport` must not import CreatorGraph or CreatorSketch: its new hooks are generic (`ViewportTool`, `ViewportOverlay`).
- Colour hex values are written only in `CreatorStyle`; the sketch colours are its existing roles `sketchUnderConstrained`, `sketchFullyConstrained`, `sketchConflicting`, `sketchConstruction`, `sketchProjected` (Dracula `#8be9fd`, `#f8f8f2`, `#ff5555`, `#6272a4`, `#bd93f9`), and selection is `profileHeader` ("green (the Sketch node's header colour)").
- MetalUI gaps are logged in `docs/metalui-gaps.md` and never worked around; this plan adds **S5-a** (no modifiers on hover; the tap half is the graph-input track's **GI-a**, so the two go to the MetalUI session as one request with two parts).
- Never edit `Package.swift`'s MetalUI path (`../MetalUI`), and never modify the `../MetalUI` repository.
- Each command is one undo step, applied as a `setInput` of the whole sketch (sketcher spec §8); after each edit the stored sketch is `Sketch.remember(SketchSolver.solve(sketch))` (handoff).
- An exposed dimension's typed value lives in exactly one place (handoff): the sketch. Readers of a node's sockets use `definition.inputs(for: node)`, never the static `inputs`.
- File format stays version 4: nothing new is saved (the editor writes the existing `.sketch` setting).

## Files shared with other tracks

Other tracks run in parallel (graph-input, naming-merged-faces, themes). These are the files this plan edits outside its own new target; each change is small and named here so merges are easy:

- `Package.swift` — adds the `CreatorSketchEditor` target and its test target, and adds `CreatorSketch` + `CreatorSketchEditor` to `CreatorApp` and `CreatorAppTests` (Task 4). Every track may touch this file.
- `CLAUDE.md`, `docs/superpowers/roadmap.md`, `docs/metalui-gaps.md`, `docs/verification/human-checks.md` — appended sections / one-line edits (Task 11).
- `Sources/CreatorEditor/NodeShape.swift`, `NodeRowModel.swift`, `InspectorBuilder.swift` — one line each, `inputs` → `inputs(for: node)`, plus four lines in `InspectorBuilder.page` that append the per-node sockets' rows after a declared inspector (Task 1). The graph-input track edits `GraphPanelInput`, not these.
- `Sources/CreatorApp/HandleBuilder.swift`, `AppModel+Viewport.swift` — one line each (Task 1).
- `Sources/CreatorApp/AppModel.swift` — one stored property (`sketch`) and two lines in `load(_:from:)` (Task 10).
- `Sources/CreatorApp/AppModel+Scene.swift` — `refreshScene()` ghosts the scene and drops handles while sketching, `observeScene()` tracks `sketch` (Task 10).
- `Sources/CreatorApp/AppModel+Picking.swift` — one `case .editSketch` in `handle(_:)` (Task 10).
- `Sources/CreatorApp/TopBar.swift`, `InspectorDock.swift` — swap in the sketch views, in the new `SketchChrome`, while sketching (Task 11; `TopBar`'s body is re-indented under an `if`). **`AppRoot.swift`, `AppInput.swift` and `GraphPanelInput.swift` are not touched**: the sketch keys are button shortcuts, so no keymap or `onInput` change is needed.
- `Sources/CreatorGraph/InspectorAction.swift` — adds `case editSketch` (Task 10).
- `Sources/CreatorNodes/Profiles/SketchNode.swift` — its inspector button and a public `isReservedDimensionName(_:)` (Task 10).
- `Sources/CreatorViewport/...` — Tasks 2–3 add files and touch `ViewportModel.swift`, `ViewportModel+Input.swift`, `ViewportModel+Cursor.swift`, `ViewportModel+ContextMenu.swift` (one guard: only Look At while a tool is set), `ViewportModel+Frame.swift`, `ViewportRenderKey.swift`, `DragState.swift`, `ViewportDragMode.swift`, `ViewportFrame.swift`, `ViewportPalette.swift` and `ViewportRenderer.swift` (the renderer's handle buffer moves to `ViewportRenderer+Handles.swift` to stay under `type_body_length`). No other track is in the viewport now (viewport-input has merged).
- `Tests/CreatorEditorTests/Support/EditorTestNodes.swift` (appends a fixture), `Tests/CreatorViewportTests/OffscreenRenderTests.swift` (adds an overlay to one frame).

## Review Focus

The five inputs the spec implies but its feature list doesn't exercise, most likely to bite first. Each has a test in the task that owns the code:

1. **Esc or ⏎ while the add-node palette is open over a sketch** (Space opens it over the canvas mid-sketch): a person expects the palette to close and the sketch to stay open, not sketch mode to end. The sketch's Esc/⏎ are button shortcuts that run before the palette's keys, so the editor asks the host first (`SketchEditorEvents.dismissHostPopup`). Test: `SketchModeTests.escapeAndFinishCloseTheAddNodePaletteFirst` (Task 10).
2. **A drag that changes nothing** (dragging a fixed point, or any point of a conflicting sketch, whose drag solve is unusable): a person expects no new undo step. Test: `SelectionAndConstraintTests.aDragThatMovesNothingIsNoUndoStep` (Task 7).
3. **Clicking the same spot twice** (a line's end on its start, a circle's radius point on its centre): a person expects nothing degenerate drawn and nothing stored. Test: `DrawingTests.clickingTheSameSpotTwiceDrawsNothing` (Task 6).
4. **A click where the sketch plane can't be hit** (seen edge-on after orbiting, or off the plane in perspective): a person expects nothing to happen — no stray point, and no model face selected behind the sketch. Test: `DrawingTests.aClickOffThePlaneIsClaimedButDrawsNothing` (Task 6).
5. **An exposed dimension named like a setting in a hand-edited file** (`sketch`, `plane`): a person expects the sketch not to be wiped when they edit it. `SketchStore` never clears a reserved name. Test: `SketchModeTests.aReservedExposedNameNeverClearsTheSketchSetting` (Task 10).

## File structure

New target `Sources/CreatorSketchEditor/` (one type per file):

| File | Responsibility |
|---|---|
| `SketchEditorModel.swift` | The model: sketch, plane, live solution, selection, hover, preview, tool, stroke; `reload`, `commit` |
| `SketchEditorModel+Status.swift` | DOF readout ("3 degrees of freedom", "Fully constrained", conflicts) |
| `SketchEditorModel+Overlay.swift` | `overlay` for the viewport |
| `SketchEditorModel+Drawing.swift` | Tools, construction, Esc/Finish, Line/Arc/Circle/Point placement and rubber band |
| `SketchEditorModel+Selection.swift` | Select clicks, constraint buttons, Delete |
| `SketchEditorModel+Drag.swift` | Point drags with `solve(_:dragging:)` |
| `SketchEditorModel+Dimensions.swift` | Dimension tool, value/name/expose/driving edits, inspector rows, Remove |
| `SketchEditorModel+ViewportTool.swift` | `ViewportTool` conformance: screen → plane, pick radius |
| `SketchEditorEvents.swift`, `SketchCommit.swift` | What the editor tells its host |
| `SketchTool.swift`, `SketchConstraintKind.swift`, `DrawState.swift`, `SketchAnchor.swift`, `LineInference.swift` | Tool and inference values |
| `SketchPicker.swift`, `SelectionShape.swift`, `EditorGeometry.swift` | CPU picking, selection → constraint, 2D helpers |
| `SketchOverlayBuilder.swift`, `PreviewCurve.swift`, `SketchPreview.swift` | Sketch → `ViewportOverlay` |
| `DimensionText.swift`, `DimensionRow.swift`, `ConstraintRow.swift` | Inspector values |
| `Views/SketchToolbar.swift`, `Views/SketchToolButton.swift`, `Views/EscapeKey.swift`, `Views/ForwardDeleteKey.swift`, `Views/SketchInspector.swift`, `Views/ConstraintButtons.swift`, `Views/DimensionRowView.swift`, `Views/DimensionField.swift`, `Views/SketchColors.swift` | Thin views |

New in `Sources/CreatorViewport/`: `Tool/ViewportTool.swift`, `Tool/ViewportProjector.swift`, `Model/ViewportModel+Tool.swift`, `Overlay/{ViewportOverlay,OverlayLine,OverlayPoint,OverlayTint}.swift`, `Render/{OverlayGeometry,OverlayBufferKey,ViewportPalette+Overlay,ViewportRenderer+Overlay,ViewportRenderer+Handles}.swift`.

New in `Sources/CreatorApp/`: `SketchSession.swift` (editor as the viewport's tool, overlay following), `SketchStore.swift` (commit → graph batch, single-source rule), `AppModel+Sketch.swift` (enter, finish, store, refresh, plane, framing), `SketchChrome.swift` (the glass over an opaque backdrop for the sketch views).

## Task overview

| # | Task | Tests after (master 1085) |
|---|---|---|
| 1 | Exposed-dimension sockets everywhere: the five `inputs(for:)` readers | 1090 (+5) |
| 2 | Viewport: `ViewportTool`, `ViewportProjector`, tool routing, `lookAt(_ plane:)` | 1098 (+13) |
| 3 | Viewport: the overlay (`ViewportOverlay`), its colours, dashes and plane grid | 1103 (+18) |
| 4 | `CreatorSketchEditor` target and `SketchEditorModel` core (solve, remember, commit, readout) | 1109 (+24) |
| 5 | The sketch as a viewport overlay (`SketchOverlayBuilder`) | 1115 (+30) |
| 6 | Drawing tools and inference; the editor as the viewport's tool | 1126 (+41) |
| 7 | Selection, constraint buttons, Delete, point drags | 1133 (+48) |
| 8 | Dimensions: the Dimension tool and the inspector's edits | 1140 (+55) |
| 9 | The sketch views: toolbar and inspector | 1143 (+58) |
| 10 | App: sketch mode (enter, ghost, overlay, commits, undo, single-source rule, the Sketch node's inspector) | 1161 (+76) |
| 11 | App: the views in the top bar and inspector, opaque to the pointer; docs | 1163 (+78) |


---

### Task 1: Exposed-dimension sockets everywhere: the five `inputs(for:)` readers

The S4 → S5 handoff names five places that still read a definition's static `inputs`, so a Sketch node's exposed dimensions (`SketchNode.inputs(for:)`) are wired and evaluated but not drawn, and their rows have no unit or default. Switch all five together (switching only some leaves rows without their unit). The inspector's fallback rows only run for a definition that declares no inspector, and the Sketch node declares one in Task 10 ("Edit sketch"), so `InspectorBuilder` also appends fallback rows for the per-node sockets (the names in `inputs(for:)` that the static `inputs` lack) after a declared inspector's sections; Task 10's `aSketchNodesInspectorHasEditSketchAndItsExposedDimensions` pins it on the real node. The editor tests use a test-only definition with a per-node socket (`PerNodeSocketTestNode`, appended to the fixture file) plus the real Sketch node; the app test uses a test-only node whose handle drives a per-node socket.

**Files:**
- Modify: `Sources/CreatorApp/AppModel+Viewport.swift`
- Modify: `Sources/CreatorApp/HandleBuilder.swift`
- Modify: `Sources/CreatorEditor/InspectorBuilder.swift`
- Modify: `Sources/CreatorEditor/NodeRowModel.swift`
- Modify: `Sources/CreatorEditor/NodeShape.swift`
- Create: `Tests/CreatorAppTests/PerNodeHandleTests.swift`
- Create: `Tests/CreatorAppTests/Support/PerNodeHandleTestNode.swift`
- Create: `Tests/CreatorEditorTests/PerNodeSocketTests.swift`
- Modify: `Tests/CreatorEditorTests/Support/EditorTestNodes.swift`

**Interfaces:**
- Consumes: `NodeDefinition.inputs(for: Node) -> [SocketSpec]` (CreatorGraph, S4); `SketchNode` (CreatorNodes).
- Produces: No new API. `NodeShape(_:in:registry:)`, `NodeRowModel.rows(for:shape:graph:registry:)`, `InspectorBuilder.page(...)`, `HandleBuilder.handles(...)` and `AppModel.handleChanged(_:_:_:)` now read `inputs(for: node)`; a declared inspector is followed by an "Inputs" section of the per-node sockets.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorAppTests/PerNodeHandleTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// A handle on a per-node socket (`inputs(for:)`, as an exposed sketch dimension is one; S4 → S5 handoff) is shown
/// with its default, and dragging it to the value it already reads records nothing.
@MainActor
struct PerNodeHandleTests {
    func makeGraph() -> (graph: Graph, node: Node) {
        let registry = PerNodeHandleTestNode.registry
        let rectangle = registry.makeNode(RectangleNode.typeID)
        let node = registry.makeNode(PerNodeHandleTestNode.typeID, at: Vector2(240, 0))
        var graph = Graph()
        graph.nodes[rectangle.id] = rectangle
        graph.nodes[node.id] = node
        graph.links.append(Link(from: Endpoint(node: rectangle.id, socket: "profile"), to: Endpoint(node: node.id, socket: "profile")))
        return (graph, node)
    }

    @Test func aPerNodeSocketsHandleShowsItsDefaultAndEditsIt() async throws {
        let (graph, node) = makeGraph()
        let app = AppModel(kernel: FakeKernel(), registry: PerNodeHandleTestNode.registry, file: GraphFile(graph: graph))
        app.previewMode = .selectedNode
        app.editor.selection = [node.id]
        await app.settle()
        let handle = try #require(app.viewport.handles.first)
        #expect(handle.value == 8 && handle.range == 0...50, "the per-node socket's default and range")
        app.handleChanged(handle.id, 8, .ended)
        #expect(!app.document.canUndo, "dragging to the value it already reads records nothing")
        app.handleChanged(handle.id, 12, .ended)
        #expect(app.document.graph.nodes[node.id]?.inputValues["size"] == .number(12))
    }
}
```

Create `Tests/CreatorAppTests/Support/PerNodeHandleTestNode.swift`:

```swift
// Test fixture file: a node whose handle drives a per-node socket, as an exposed sketch dimension is one.
import CreatorGraph
import CreatorKernel
import CreatorNodes

/// A `profile` input plus a per-node `size` number socket (`inputs(for:)` only, default 8, 0…50) with a linear handle,
/// so the handle builder and the drag's no-op check must read `inputs(for:)` to find it.
enum PerNodeHandleTestNode: NodeDefinition {
    static let typeID = "apptest.perNodeHandle"
    static let displayName = "Per-node Handle"
    static let category = NodeCategory.solid
    static let inputs = [SocketSpec("profile", .profile)]
    static let outputs: [SocketSpec] = []
    static let handles: [HandleSpec] = [.linear("size")]
    static func inputs(for node: Node) -> [SocketSpec] {
        inputs + [SocketSpec("size", .number, defaultValue: .number(8), unit: .millimetres, range: 0...50)]
    }
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs([:])
    }

    /// The built-in nodes plus this one.
    static let registry = NodeRegistry(BuiltInNodes.all + [PerNodeHandleTestNode.self])
}
```

Create `Tests/CreatorEditorTests/PerNodeSocketTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import Testing
@testable import CreatorEditor

/// Per-node sockets (`NodeDefinition.inputs(for:)`, the Sketch node's exposed dimensions; S4 → S5 handoff) are
/// drawn, labelled with their unit and default, and listed in the inspector, like declared ones.
@MainActor
struct PerNodeSocketTests {
    func perNodeNode() -> Node {
        testNode(PerNodeSocketTestNode.self, id: 1, at: .zero, values: ["extra": .text("width")],
                 registry: perNodeSocketTestRegistry)
    }

    @Test func aPerNodeSocketIsDrawnAfterTheDeclaredOnes() {
        let node = perNodeNode()
        var graph = Graph()
        graph.nodes[node.id] = node
        let shape = NodeShape(node, in: graph, registry: perNodeSocketTestRegistry)
        #expect(shape.inputs.map(\.name) == ["profile", "width"])
        #expect(shape.inputs.last?.type == .number)
    }

    @Test func itsRowShowsItsDefaultInItsUnit() {
        let node = perNodeNode()
        var graph = Graph()
        graph.nodes[node.id] = node
        let shape = NodeShape(node, in: graph, registry: perNodeSocketTestRegistry)
        let rows = NodeRowModel.rows(for: node, shape: shape, graph: graph, registry: perNodeSocketTestRegistry)
        #expect(rows.first { $0.id == "in.width" }?.value == ValueText.format(7, unit: .millimetres))
    }

    @Test func theFallbackInspectorListsItWithItsUnitAndDefault() throws {
        let node = perNodeNode()
        var graph = Graph()
        graph.nodes[node.id] = node
        let page = InspectorBuilder.page(graph: graph, selection: [node.id], registry: perNodeSocketTestRegistry, results: [:])
        let row = try #require(page.sections.first?.rows.first)
        guard case .number(let field) = row else {
            Issue.record("expected a number row, got \(row)")
            return
        }
        #expect(field.socket == "width" && field.unit == .millimetres && field.value == .number(7))
    }

    @Test func aSketchNodesExposedDimensionIsASocketOnTheCanvas() {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(25, 0))
        let dimension = sketch.addDimension(.length(line), value: 25)
        sketch.dimensions[dimension]?.isExposed = true
        var node = BuiltInNodes.registry.makeNode(SketchNode.typeID)
        node.inputValues[NodeSetting.sketch] = .sketch(sketch)
        var graph = Graph()
        graph.nodes[node.id] = node
        let shape = NodeShape(node, in: graph, registry: BuiltInNodes.registry)
        #expect(shape.inputs.map(\.name) == ["plane", "references", "d1"])
        let rows = NodeRowModel.rows(for: node, shape: shape, graph: graph, registry: BuiltInNodes.registry)
        #expect(rows.first { $0.id == "in.d1" }?.value == ValueText.format(25, unit: .millimetres))
    }
}
```

Modify `Tests/CreatorEditorTests/Support/EditorTestNodes.swift` (apply this diff):

```diff
--- a/Tests/CreatorEditorTests/Support/EditorTestNodes.swift
+++ b/Tests/CreatorEditorTests/Support/EditorTestNodes.swift
@@ -176,3 +176,24 @@ let inspectorTestRegistry = NodeRegistry([
     FilletTestNode.self, OutputTestNode.self, TransformTestNode.self, GraphParameterTestNode.self,
     GridPointsTestNode.self,
 ])
+
+/// Mirrors the Sketch node's exposed dimensions: one extra number input per node, named by the `extra` setting
+/// (`.text(name)`), in millimetres with a default of 7, beside a static `profile` input. No inspector, so the
+/// fallback rows list it.
+enum PerNodeSocketTestNode: NodeDefinition {
+    static let typeID = "editortest.perNodeSocket"
+    static let displayName = "Per-node Socket"
+    static let category = NodeCategory.profile
+    static let inputs = [SocketSpec("profile", .profile, optional: true)]
+    static let outputs = [SocketSpec("profile", .profile)]
+    static func inputs(for node: Node) -> [SocketSpec] {
+        guard case .text(let name)? = node.inputValues["extra"] else { return inputs }
+        return inputs + [SocketSpec(SocketName(name), .number, defaultValue: .number(7), unit: .millimetres)]
+    }
+    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
+        NodeOutputs(["profile": .profile(.rectangle(width: 1, height: 1, plane: .xy))])
+    }
+}
+
+/// The editor registry plus `PerNodeSocketTestNode`, for the per-node socket tests.
+let perNodeSocketTestRegistry = NodeRegistry([NumberTestNode.self, PerNodeSocketTestNode.self])
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter 'PerNodeSocketTests|PerNodeHandleTests'`

Expected: FAIL — `aPerNodeSocketIsDrawnAfterTheDeclaredOnes` sees `["profile"]`, the row and inspector tests find no `width` row, `aSketchNodesExposedDimensionIsASocketOnTheCanvas` sees `["plane", "references"]`, and `PerNodeHandleTests` finds no handle (`#require` fails).

- [ ] **Step 3: Switch the five readers to `inputs(for:)`**

Modify `Sources/CreatorApp/AppModel+Viewport.swift` (apply this diff):

```diff
--- a/Sources/CreatorApp/AppModel+Viewport.swift
+++ b/Sources/CreatorApp/AppModel+Viewport.swift
@@ -48,11 +48,12 @@ extension AppModel {
         if phase == .ended { document.endCoalescing() }
     }
 
-    /// The number `target` currently reads: its stored input, or its socket's default.
+    /// The number `target` currently reads: its stored input, or its socket's default (from `inputs(for:)`, so a
+    /// per-node socket's default counts).
     private func currentNumber(_ target: HandleTarget) -> Double? {
         guard let node = document.graph.nodes[target.node] else { return nil }
         let stored = node.inputValues[target.socket]
-            ?? registry[node.typeID]?.inputs.first { $0.name == target.socket }?.defaultValue
+            ?? registry[node.typeID]?.inputs(for: node).first { $0.name == target.socket }?.defaultValue
         return HandleBuilder.number(stored)
     }
 
```

Modify `Sources/CreatorApp/HandleBuilder.swift` (apply this diff):

```diff
--- a/Sources/CreatorApp/HandleBuilder.swift
+++ b/Sources/CreatorApp/HandleBuilder.swift
@@ -31,7 +31,7 @@ public enum HandleBuilder {
         case .linear(let name), .radial(let name): socket = name
         }
         guard graph.incomingLink(to: Endpoint(node: node.id, socket: socket)) == nil,
-              let input = definition.inputs.first(where: { $0.name == socket }), input.type == .number,
+              let input = definition.inputs(for: node).first(where: { $0.name == socket }), input.type == .number,
               let value = number(node.inputValues[socket] ?? input.defaultValue) else { return nil }
         let placement: Placement?
         let style: HandleStyle
```

Modify `Sources/CreatorEditor/InspectorBuilder.swift` (apply this diff):

```diff
--- a/Sources/CreatorEditor/InspectorBuilder.swift
+++ b/Sources/CreatorEditor/InspectorBuilder.swift
@@ -19,10 +19,16 @@ public enum InspectorBuilder {
             return InspectorPage(header: header, sections: [note], parameters: parameters)
         }
         let header = InspectorHeader(node: id, title: node.name, category: definition.category, state: results[id]?.state)
-        let declared = definition.inspector.isEmpty ? fallbackSections(definition.inputs) : definition.inspector
+        // `inputs(for:)`, not the static list: per-node sockets (exposed sketch dimensions) get their unit and default.
+        // A declared inspector can't name them, so they follow its sections as fallback rows.
+        let inputs = definition.inputs(for: node)
+        let fixed = Set(definition.inputs.map(\.name))
+        let declared = definition.inspector.isEmpty
+            ? fallbackSections(inputs)
+            : definition.inspector + fallbackSections(inputs.filter { !fixed.contains($0.name) })
         let sections = declared.map { section in
             InspectorSectionRows(title: section.title, rows: section.controls.map {
-                row(for: $0, node: node, inputs: definition.inputs, outputs: definition.outputs, graph: graph,
+                row(for: $0, node: node, inputs: inputs, outputs: definition.outputs, graph: graph,
                     results: results)
             })
         }
```

Modify `Sources/CreatorEditor/NodeRowModel.swift` (apply this diff):

```diff
--- a/Sources/CreatorEditor/NodeRowModel.swift
+++ b/Sources/CreatorEditor/NodeRowModel.swift
@@ -10,9 +10,10 @@ public struct NodeRowModel: Equatable, Sendable, Identifiable {
 
     public var id: String { (isInput ? "in." : "out.") + socket.rawValue }
 
-    /// Rows for `node`: inputs first, then outputs, matching `NodeLayout`'s row order.
+    /// Rows for `node`: inputs first, then outputs, matching `NodeLayout`'s row order. Each input's unit and default
+    /// come from `inputs(for: node)`, the same list `NodeShape` draws.
     public static func rows(for node: Node, shape: NodeShape, graph: Graph, registry: NodeRegistry) -> [NodeRowModel] {
-        let specs = registry[node.typeID]?.inputs ?? []
+        let specs = registry[node.typeID]?.inputs(for: node) ?? []
         let inputs = shape.inputs.map { socket -> NodeRowModel in
             let wired = graph.incomingLink(to: Endpoint(node: node.id, socket: socket.name)) != nil
             let spec = specs.first { $0.name == socket.name }
```

Modify `Sources/CreatorEditor/NodeShape.swift` (apply this diff):

```diff
--- a/Sources/CreatorEditor/NodeShape.swift
+++ b/Sources/CreatorEditor/NodeShape.swift
@@ -1,7 +1,8 @@
 import CreatorGraph
 import CreatorKernel
 
-/// What the canvas needs to draw and hit-test one node: its title, category and sockets.
+/// What the canvas needs to draw and hit-test one node: its title, category and sockets. A registered node's inputs
+/// are `inputs(for: node)`, so per-node sockets (the Sketch node's exposed dimensions) are drawn and wired.
 /// A node whose type isn't registered is a "missing node" (spec §4.5): it keeps the sockets its
 /// wires name, untyped.
 public struct NodeShape: Equatable, Sendable {
@@ -28,7 +29,7 @@ public struct NodeShape: Equatable, Sendable {
     public init(_ node: Node, in graph: Graph, registry: NodeRegistry) {
         if let definition = registry[node.typeID] {
             self.init(title: node.name, category: definition.category,
-                      inputs: definition.inputs.map { Socket(name: $0.name, type: $0.type) },
+                      inputs: definition.inputs(for: node).map { Socket(name: $0.name, type: $0.type) },
                       outputs: definition.outputs.map { Socket(name: $0.name, type: $0.type) })
         } else {
             let inputs = Set(graph.links.filter { $0.to.node == node.id }.map(\.to.socket)).sorted()
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter 'PerNodeSocketTests|PerNodeHandleTests'`

Expected: PASS (exit 0, no line says "recorded an issue" or "failed after").

- [ ] **Step 5: Full verification**

Run, from the repo root: `swift build --build-tests 2>&1 | grep -E "(error|warning):" | grep -v "ld: warning"` (expected: nothing new; master's one test warning, `ContextMenuTests.swift:96` "'underPointer' mutated after capture", shows only when that file recompiles), then `swift test` (expected: exit 0, no "recorded an issue" / "failed after" lines, and the "Test run with N tests" lines sum to **1090 (master + 5)**), then `swiftlint lint --strict` (zero violations).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorApp/AppModel+Viewport.swift Sources/CreatorApp/HandleBuilder.swift Sources/CreatorEditor/InspectorBuilder.swift Sources/CreatorEditor/NodeRowModel.swift Sources/CreatorEditor/NodeShape.swift Tests/CreatorAppTests/PerNodeHandleTests.swift Tests/CreatorAppTests/Support/PerNodeHandleTestNode.swift Tests/CreatorEditorTests/PerNodeSocketTests.swift Tests/CreatorEditorTests/Support/EditorTestNodes.swift
git commit -m "feat(editor): draw and read per-node sockets through inputs(for:)"
```


---

### Task 2: Viewport: `ViewportTool`, `ViewportProjector`, tool routing and `lookAt(_ plane:)`

A generic hook so a host (the sketch editor) takes the viewport's primary pointer input without the viewport knowing what a sketch is. While `ViewportModel.tool` is set: hover goes to it; a click off the cube and handles is offered to it first (claimed, nothing is picked); a plain primary drag (no Shift/⌥) off the cube and handles is offered at its press (taken: drag mode `.tool`, the camera stays). Right/middle drags, scroll, pinch, Shift/⌥ drags, the cube and handles stay the viewport's. Each call carries a `ViewportProjector` (pose + size) for screen → plane. `click(at:modifiers:)` takes modifiers for when MetalUI reports them on taps (gap S5-a); the view keeps calling `click(at:)`. `lookAt(_:framing:)` faces a plane, orthographic, its x axis right where the turntable allows. While a tool is set the face context menu offers only Look At: "Select Edges of Face" would add an Edges by Tag node and "Show Producing Node" would change the graph's selection in the middle of a sketch.

**Files:**
- Modify: `Sources/CreatorViewport/Input/ViewportDragMode.swift`
- Modify: `Sources/CreatorViewport/Model/DragState.swift`
- Modify: `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift`
- Modify: `Sources/CreatorViewport/Model/ViewportModel+Cursor.swift`
- Modify: `Sources/CreatorViewport/Model/ViewportModel+Input.swift`
- Create: `Sources/CreatorViewport/Model/ViewportModel+Tool.swift`
- Modify: `Sources/CreatorViewport/Model/ViewportModel.swift`
- Create: `Sources/CreatorViewport/Tool/ViewportProjector.swift`
- Create: `Sources/CreatorViewport/Tool/ViewportTool.swift`
- Create: `Tests/CreatorViewportTests/Support/RecordingTool.swift`
- Create: `Tests/CreatorViewportTests/ViewportToolTests.swift`

**Interfaces:**
- Consumes: `CameraMath.ray(through:_:size:)`, `CameraMath.project`, `CameraNavigation.orientation/frame`, `ViewportModel.animate(to:)`, `DragState`.
- Produces: `@MainActor public protocol ViewportTool: AnyObject { func pointerMoved(to: ScreenPoint?, projector: ViewportProjector); func clicked(at: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool; func dragBegan(at: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool; func dragMoved(to: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector); func dragEnded(at: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) }`; `public struct ViewportProjector { pose, size; millimetresPerPoint: Double; planePoint(under: ScreenPoint, on: Plane) -> Vector2?; screenPoint(of: Vector3) -> ScreenPoint? }`; `ViewportModel.tool: (any ViewportTool)?`; `ViewportModel.click(at:modifiers: = [])`; `ViewportModel.lookAt(_ plane: Plane, framing: BoundingBox)`; `ViewportDragMode.tool`; the cursor is `.crosshair` while a tool is set; `contextMenuItems(at:)` is `[.lookAt]` while a tool is set.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorViewportTests/Support/RecordingTool.swift`:

```swift
// Test fixture file: a viewport tool that records what reaches it and claims what it is told to.
@testable import CreatorViewport

/// Records every call as a short string ("moved 10,20", "clicked 10,20", "began 10,20", "dragged 10,20",
/// "ended 10,20"), and claims clicks and drags while `claims` is true.
@MainActor
final class RecordingTool: ViewportTool {
    var claims = true
    private(set) var calls: [String] = []
    private(set) var lastProjector: ViewportProjector?

    private func record(_ verb: String, _ point: ScreenPoint?, _ projector: ViewportProjector) {
        calls.append(point.map { "\(verb) \(Int($0.x)),\(Int($0.y))" } ?? "\(verb) nowhere")
        lastProjector = projector
    }

    func pointerMoved(to point: ScreenPoint?, projector: ViewportProjector) { record("moved", point, projector) }

    func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool {
        record("clicked", point, projector)
        return claims
    }

    func dragBegan(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool {
        record("began", point, projector)
        return claims
    }

    func dragMoved(to point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {
        record("dragged", point, projector)
    }

    func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {
        record("ended", point, projector)
    }
}
```

Create `Tests/CreatorViewportTests/ViewportToolTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

/// A `ViewportTool` takes the primary pointer input while it is set (sketcher spec §8), and the viewport keeps its
/// navigation.
@MainActor
struct ViewportToolTests {
    func makeModel(tool: RecordingTool?) -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: CameraPose(target: .zero, distance: 100, pitch: .pi / 2,
                                                                             projection: .orthographic),
                                  clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.tool = tool
        return model
    }

    @Test func aClaimedClickReachesTheToolAndNotThePicker() {
        let tool = RecordingTool()
        let model = makeModel(tool: tool)
        var picked: [PickTarget?] = []
        model.events.clicked = { picked.append($0) }
        model.click(at: ScreenPoint(200, 150))
        #expect(tool.calls == ["clicked 200,150", "moved 200,150"], "then the pointer is over the release point")
        #expect(picked.isEmpty, "the tool claimed it")
        tool.claims = false
        model.click(at: ScreenPoint(210, 150))
        #expect(picked.count == 1, "an unclaimed click is reported as before")
    }

    @Test func aClaimedDragMovesNoCamera() {
        let tool = RecordingTool()
        let model = makeModel(tool: tool)
        let before = model.pose
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(230, 150), modifiers: [], button: .primary)
        #expect(model.activeDragMode == .tool)
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(240, 160), modifiers: [], button: .primary)
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(250, 170), modifiers: [], button: .primary)
        #expect(tool.calls == ["began 200,150", "dragged 230,150", "dragged 240,160", "ended 250,170", "moved 250,170"])
        #expect(model.pose == before)
        #expect(model.activeDragMode == nil)
    }

    @Test func aDeclinedDragOrbitsAndNavigationStaysTheViewports() {
        let tool = RecordingTool()
        tool.claims = false
        let model = makeModel(tool: tool)
        let before = model.pose
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(230, 150), modifiers: [], button: .primary)
        #expect(model.activeDragMode == .orbit)
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(230, 150), modifiers: [], button: .primary)
        #expect(model.pose != before)
        tool.claims = true
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(230, 150), modifiers: .shift, button: .primary)
        #expect(model.activeDragMode == .pan, "Shift-drag pans without asking the tool")
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(230, 150), modifiers: .shift, button: .primary)
        model.dragChanged(from: ScreenPoint(200, 150), to: ScreenPoint(230, 150), modifiers: [], button: .secondary)
        #expect(model.activeDragMode == .orbit, "right-drag orbits")
        model.dragEnded(from: ScreenPoint(200, 150), at: ScreenPoint(230, 150), modifiers: [], button: .secondary)
        #expect(tool.calls.filter { $0.hasPrefix("began") } == ["began 200,150"], "only the plain primary drag was offered")
    }

    @Test func theCubeStaysTheViewports() {
        let tool = RecordingTool()
        let model = makeModel(tool: tool)
        model.click(at: model.cubeLayout.center)
        #expect(!tool.calls.contains { $0.hasPrefix("clicked") })
        #expect(model.isAnimating)
    }

    @Test func hoverReachesTheToolAndTheCursorIsACrosshair() {
        let tool = RecordingTool()
        let model = makeModel(tool: nil)
        #expect(model.cursor == nil)
        model.tool = tool
        #expect(model.cursor == .crosshair)
        model.pointerHovered(at: ScreenPoint(100, 100))
        model.pointerHovered(at: nil)
        #expect(tool.calls == ["moved 100,100", "moved nowhere"])
        #expect(tool.lastProjector?.size == ViewportSize(width: 400, height: 300))
    }

    /// The face menu stays, but while a tool holds the pointer it only navigates: "Select Edges of Face" would add a
    /// node and "Show Producing Node" would change the graph's selection in the middle of a sketch.
    @Test func whileAToolIsSetTheFaceMenuOnlyLooksAt() async throws {
        let model = makeModel(tool: RecordingTool())
        model.show([ViewportItem(solid: try await fakeBox())])
        await model.waitForMeshes()
        model.pick = { _ in .face(solid: 0, FaceID(2)) }
        let ref = ViewportFaceRef(solidIndex: 0, face: FaceID(2))
        #expect(model.contextMenuItems(at: ScreenPoint(300, 200)) == [.lookAt(ref)])
        model.tool = nil
        #expect(model.contextMenuItems(at: ScreenPoint(300, 200)).count == 3, "Look At, Select Edges, Show Producing Node")
    }

    @Test func theProjectorMapsScreenPointsOntoAPlaneAndBack() throws {
        let pose = CameraPose(target: Vector3(5, 5, 0), distance: 100, pitch: .pi / 2, projection: .orthographic)
        let size = ViewportSize(width: 400, height: 300)
        let projector = ViewportProjector(pose: pose, size: size)
        let centre = try #require(projector.planePoint(under: size.center, on: .xy))
        #expect(abs(centre.x - 5) < 1e-9 && abs(centre.y - 5) < 1e-9, "the view's centre is over the target")
        let right = try #require(projector.planePoint(under: ScreenPoint(300, 150), on: .xy))
        #expect(abs(right.x - (5 + 100 * projector.millimetresPerPoint)) < 1e-9, "screen right is plane +x from the top")
        let back = try #require(projector.screenPoint(of: Plane.xy.point(right)))
        #expect(abs(back.x - 300) < 1e-6 && abs(back.y - 150) < 1e-6)
        let edgeOn = ViewportProjector(pose: CameraPose(distance: 100, pitch: 0, projection: .orthographic), size: size)
        #expect(edgeOn.planePoint(under: size.center, on: .xy) == nil, "a plane seen edge-on has no point under the pointer")
    }

    @Test func lookingAtAPlaneTurnsItsXAxisRightAndGoesOrthographic() async {
        let model = makeModel(tool: nil)
        model.pose = CameraPose(target: .zero, distance: 100, yaw: 0.7, pitch: 0.3)
        let plane = Plane(origin: Vector3(0, 0, 10), normal: .unitZ, xAxis: Vector3(0, 1, 0))
        model.lookAt(plane, framing: BoundingBox(min: Vector3(-10, -10, 10), max: Vector3(10, 10, 10)))
        await model.waitForAnimation()
        #expect(model.pose.projection == .orthographic)
        #expect(isClose(model.pose.toEye, .unitZ))
        #expect(isClose(model.pose.right, plane.xAxis), "the sketch's x axis points right")
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter ViewportToolTests`

Expected: FAIL — the build fails: "cannot find type 'ViewportTool' in scope" (and `ViewportProjector`, `model.tool`, `lookAt(_:framing:)`).

- [ ] **Step 3: Add the tool, the projector and the routing**

Modify `Sources/CreatorViewport/Input/ViewportDragMode.swift` (apply this diff):

```diff
--- a/Sources/CreatorViewport/Input/ViewportDragMode.swift
+++ b/Sources/CreatorViewport/Input/ViewportDragMode.swift
@@ -7,4 +7,6 @@ public enum ViewportDragMode: Hashable, Sendable {
     case cube
     /// The drag began on a handle's knob: it edits that handle (by `ViewportHandle.id`).
     case handle(String)
+    /// The `ViewportModel.tool` took the drag (a sketch point being dragged).
+    case tool
 }
```

Modify `Sources/CreatorViewport/Model/DragState.swift` (apply this diff):

```diff
--- a/Sources/CreatorViewport/Model/DragState.swift
+++ b/Sources/CreatorViewport/Model/DragState.swift
@@ -11,4 +11,6 @@ struct DragState {
     /// The orbit pivot: the model point under the press, else the bounds centre.
     var pivot: Vector3?
     var handleStartValue: Double
+    /// The modifiers held at the press, passed to a tool's drag.
+    var modifiers: ViewportModifiers = []
 }
```

Modify `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift` (apply this diff):

```diff
--- a/Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift
+++ b/Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift
@@ -6,10 +6,12 @@ extension ViewportModel {
     /// location, which MetalUI's located `.contextMenu` hands its builder (C7 item 4). The face is picked there and
     /// then, so it's the one under the press even if the pointer moved without a hover event or the camera moved
     /// under it. Over an edge, the menu uses the edge's first face. Over nothing, over the view cube, or opened
-    /// without a pointer (`nil`: from the keyboard or accessibility) it's empty, and MetalUI opens no menu.
+    /// without a pointer (`nil`: from the keyboard or accessibility) it's empty, and MetalUI opens no menu. While a
+    /// `tool` holds the pointer (a sketch is open) it only navigates: Look At, and nothing that edits or selects.
     public func contextMenuItems(at point: ScreenPoint?) -> [ViewportMenuItem] {
         guard let point, !cubeLayout.contains(point), let ref = faceRef(for: pick?(point)),
               let face = items[ref.solidIndex].solid.topology.face(ref.face) else { return [] }
+        guard tool == nil else { return [.lookAt(ref)] }
         var menu: [ViewportMenuItem] = [.lookAt(ref), .selectEdgesOfFace(ref)]
         let nodes = MeshQueries.producingNodes(of: face)
         for node in nodes {
```

Modify `Sources/CreatorViewport/Model/ViewportModel+Cursor.swift` (apply this diff):

```diff
--- a/Sources/CreatorViewport/Model/ViewportModel+Cursor.swift
+++ b/Sources/CreatorViewport/Model/ViewportModel+Cursor.swift
@@ -1,10 +1,11 @@
 extension ViewportModel {
     /// The pointer's shape over the viewport, or `nil` for the platform's arrow: a closed hand while a drag orbits
-    /// or pans (the cube's drag orbits too), else a crosshair while the host is picking edges (`isPicking`).
+    /// or pans (the cube's drag orbits too), else a crosshair while the host is picking edges (`isPicking`) or a tool
+    /// is set (sketching).
     public var cursor: ViewportCursor? {
         switch activeDragMode {
         case .orbit?, .pan?, .cube?: .grabbing
-        case .zoom?, .handle?, nil: isPicking ? .crosshair : nil
+        case .zoom?, .handle?, .tool?, nil: isPicking || tool != nil ? .crosshair : nil
         }
     }
 }
```

Modify `Sources/CreatorViewport/Model/ViewportModel+Input.swift` (apply this diff):

```diff
--- a/Sources/CreatorViewport/Model/ViewportModel+Input.swift
+++ b/Sources/CreatorViewport/Model/ViewportModel+Input.swift
@@ -40,7 +40,8 @@ extension ViewportModel {
 
     /// A press. What the drag will do is decided here:
     /// - with the primary button: on the view cube, it orbits (a click goes to `click(at:)`); on a handle's knob,
-    ///   it edits the handle; otherwise it depends on the modifiers (`ViewportInputMap`)
+    ///   it edits the handle; with no modifier, a `tool` may take it; otherwise it depends on the modifiers
+    ///   (`ViewportInputMap`)
     /// - with the right button it orbits (the cube's way on the cube), and with the middle button it pans
     public func pointerDown(at point: ScreenPoint, modifiers: ViewportModifiers, button: ViewportPointerButton = .primary) {
         events.pressed()
@@ -53,11 +54,13 @@ extension ViewportModel {
         } else if button == .primary, let handle = HandleMath.hit(handles, at: point, pose: pose, size: viewSize) {
             mode = .handle(handle.id)
             handleStart = handle.value
+        } else if button == .primary, mode == .orbit, toolTakesDrag(at: point, modifiers: modifiers) {
+            mode = .tool
         } else if mode == .orbit {
             pivot = pivotPoint(under: point)
         }
         drag = DragState(mode: mode, button: button, start: point, last: point, startPose: pose, pivot: pivot,
-                         handleStartValue: handleStart)
+                         handleStartValue: handleStart, modifiers: modifiers)
         if activeDragMode != mode { activeDragMode = mode }
     }
 
@@ -77,6 +80,8 @@ extension ViewportModel {
                                         size: viewSize))
         case .handle(let id):
             updateHandle(id, state, to: point, phase: .changed)
+        case .tool:
+            tool?.dragMoved(to: point, modifiers: state.modifiers, projector: projector)
         }
         state.last = point
         drag = state
@@ -89,6 +94,7 @@ extension ViewportModel {
         drag = nil
         activeDragMode = nil
         if case .handle(let id) = state.mode { updateHandle(id, state, to: point, phase: .ended) }
+        if state.mode == .tool { tool?.dragEnded(at: point, modifiers: state.modifiers, projector: projector) }
         // A drag that moved the camera settles it here.
         if !isAnimating, pose != state.startPose { events.cameraSettled(pose) }
         pointerReleased(at: point)
@@ -96,17 +102,19 @@ extension ViewportModel {
 
     /// A click: a primary press released within MetalUI's tap slop (`SpatialTapGesture`, its location the
     /// release). On the view cube it looks at the region under the pointer; on a handle's knob it does nothing;
-    /// elsewhere it reports the face or edge under the pointer, or `nil` for empty space.
+    /// elsewhere the `tool` may claim it, and otherwise it reports the face or edge under the pointer, or `nil` for
+    /// empty space. `modifiers` are the click's (MetalUI's tap reports none yet: docs/metalui-gaps.md S5-a).
     ///
     /// A drag still under way ends first, where it was: a click is a primary press and release, so a primary drag
     /// under way lost its release, and the primary button wins over another (`beginDragIfNeeded`).
-    public func click(at point: ScreenPoint) {
+    public func click(at point: ScreenPoint, modifiers: ViewportModifiers = []) {
         if let state = drag { pointerUp(at: state.last) }
         events.pressed()
         stopAnimation()
         if cubeLayout.contains(point) {
             if let region = cubeLayout.region(at: point, pose: pose) { perform(.view(region)) }
-        } else if HandleMath.hit(handles, at: point, pose: pose, size: viewSize) == nil {
+        } else if HandleMath.hit(handles, at: point, pose: pose, size: viewSize) == nil,
+                  tool?.clicked(at: point, modifiers: modifiers, projector: projector) != true {
             events.clicked(pick?(point))
         }
         pointerReleased(at: point)
@@ -124,6 +132,7 @@ extension ViewportModel {
     /// animates (the end of the animation picks once, `refreshHover()`).
     public func pointerHovered(at point: ScreenPoint?) {
         lastHoverPoint = point
+        if drag == nil { tool?.pointerMoved(to: point, projector: projector) }
         guard drag == nil, animation == nil else { return }
         var newHovered: PickTarget?
         var newCubeRegion: ViewCubeRegion?
```

Create `Sources/CreatorViewport/Model/ViewportModel+Tool.swift`:

```swift
import CreatorGeometry
import Foundation

extension ViewportModel {
    /// The camera input is made in now, for the tool.
    var projector: ViewportProjector { ViewportProjector(pose: currentPose(), size: viewSize) }

    /// Offers a primary drag's press to the tool; true when the tool took it.
    func toolTakesDrag(at point: ScreenPoint, modifiers: ViewportModifiers) -> Bool {
        tool?.dragBegan(at: point, modifiers: modifiers, projector: projector) ?? false
    }

    /// Looks straight at `plane` (sketcher spec §8, entering a sketch): orthographic, from the plane's front, turned so
    /// the plane's x axis points right wherever the turntable camera allows (a plane whose x axis isn't horizontal
    /// still shows it rotated), framed on `bounds` in the model area. It animates, as Look At does.
    public func lookAt(_ plane: Plane, framing bounds: BoundingBox) {
        var target = currentPose()
        let yaw = atan2(plane.xAxis.y, plane.xAxis.x)
        guard let orientation = CameraNavigation.orientation(lookingFrom: plane.normal, fallbackYaw: yaw) else { return }
        target.yaw = orientation.yaw
        target.pitch = orientation.pitch
        target.projection = .orthographic
        animate(to: CameraNavigation.frame(bounds, target, size: viewSize, insets: modelArea))
    }
}
```

Modify `Sources/CreatorViewport/Model/ViewportModel.swift` (apply this diff):

```diff
--- a/Sources/CreatorViewport/Model/ViewportModel.swift
+++ b/Sources/CreatorViewport/Model/ViewportModel.swift
@@ -25,6 +25,9 @@ public final class ViewportModel {
     /// True while the host is picking edges in the view ("Pick edges in view…", spec §5.3): the pointer is a
     /// crosshair (`cursor`).
     public var isPicking = false
+    /// What takes the primary pointer input first (`ViewportTool`), or `nil`: the sketch editor while sketching. While
+    /// one is set the pointer is a crosshair.
+    public var tool: (any ViewportTool)?
     /// The colour theme the viewport draws in (spec §6.6). The app shell sets it from its `ThemeStore`; a change is
     /// drawn on the next frame, because the GPU colours (`palette`) are part of `renderKey`.
     public var theme: ColorTheme = .dracula
```

Create `Sources/CreatorViewport/Tool/ViewportProjector.swift`:

```swift
import CreatorGeometry

/// The camera and view size one piece of input was made in, for a `ViewportTool`: screen points to rays, to points
/// on a plane, and back (spec §6.3's projection maths, read-only). Screen points are viewport points, y down.
public struct ViewportProjector: Hashable, Sendable {
    public var pose: CameraPose
    public var size: ViewportSize

    public init(pose: CameraPose, size: ViewportSize) {
        self.pose = pose
        self.size = size
    }

    /// Millimetres per point at the target's depth (everywhere, in orthographic).
    public var millimetresPerPoint: Double { CameraMath.millimetresPerPoint(pose, size: size) }

    /// Where the ray under `point` meets `plane`, in the plane's own (x, y) coordinates; `nil` for an empty view, a
    /// plane seen edge-on, or (in perspective) a plane behind the eye.
    public func planePoint(under point: ScreenPoint, on plane: Plane) -> Vector2? {
        guard !size.isEmpty, point.x.isFinite, point.y.isFinite, let normal = plane.normal.normalized else { return nil }
        let ray = CameraMath.ray(through: point, pose, size: size)
        let facing = normal.dot(ray.direction)
        guard abs(facing) > 1e-9 else { return nil }
        let t = normal.dot(plane.origin - ray.origin) / facing
        guard t >= ray.minimumT, t.isFinite else { return nil }
        let offset = ray.point(at: t) - plane.origin
        return Vector2(offset.dot(plane.xAxis), offset.dot(plane.yAxis))
    }

    /// Where a world point lands on screen, or `nil` at or behind a perspective eye.
    public func screenPoint(of world: Vector3) -> ScreenPoint? {
        CameraMath.project(world, pose, size: size)?.point
    }
}
```

Create `Sources/CreatorViewport/Tool/ViewportTool.swift`:

```swift
/// Something that takes the viewport's primary pointer input while it is set (`ViewportModel.tool`): the sketch
/// editor (sketcher spec §8). The viewport keeps navigation: right-drag orbits, middle-drag pans, scroll and pinch
/// zoom, Shift- and ⌥-drags pan and zoom, and the view cube and handles work as before. Everything else a primary
/// button does is offered to the tool first. Each call carries the camera it was made in.
@MainActor
public protocol ViewportTool: AnyObject {
    /// The pointer moved over the viewport with no drag under way (`nil`: it left the view).
    func pointerMoved(to point: ScreenPoint?, projector: ViewportProjector)
    /// A click off the view cube and the handles. Return true to claim it; unclaimed, the viewport reports the pick
    /// under it as usual (`ViewportEvents.clicked`).
    func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool
    /// A primary drag with no navigating modifier (Shift, ⌥) begins at `point`, off the cube and the handles.
    /// Return true to take it: its moves and release then come here, and the camera stays put. Declined, it orbits.
    func dragBegan(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool
    func dragMoved(to point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector)
    func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ViewportToolTests`

Expected: PASS (exit 0, no line says "recorded an issue" or "failed after").

- [ ] **Step 5: Full verification**

Run, from the repo root: `swift build --build-tests 2>&1 | grep -E "(error|warning):" | grep -v "ld: warning"` (expected: nothing new; master's one test warning, `ContextMenuTests.swift:96` "'underPointer' mutated after capture", shows only when that file recompiles), then `swift test` (expected: exit 0, no "recorded an issue" / "failed after" lines, and the "Test run with N tests" lines sum to **1098 (master + 13)**), then `swiftlint lint --strict` (zero violations).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorViewport/Input/ViewportDragMode.swift Sources/CreatorViewport/Model/DragState.swift Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift Sources/CreatorViewport/Model/ViewportModel+Cursor.swift Sources/CreatorViewport/Model/ViewportModel+Input.swift Sources/CreatorViewport/Model/ViewportModel+Tool.swift Sources/CreatorViewport/Model/ViewportModel.swift Sources/CreatorViewport/Tool/ViewportProjector.swift Sources/CreatorViewport/Tool/ViewportTool.swift Tests/CreatorViewportTests/Support/RecordingTool.swift Tests/CreatorViewportTests/ViewportToolTests.swift
git commit -m "feat(viewport): let a ViewportTool take the primary pointer; add ViewportProjector and lookAt(plane)"
```


---

### Task 3: Viewport: the overlay, its colours, dashes and plane grid

`showOverlay(_:)` draws host lines and points over the scene and the ghosts (depth-always, the existing line pipeline: no shader or GPU struct change, so `GPUDataTests` strides stand). Tints are colour roles mapped through the viewport's palette (the theme's existing sketch roles; selection is the profile header colour). Dashed lines are cut into 6-point dashes with 4-point gaps at the current zoom. With `gridPlane`, a grid on that plane (1/10/100 mm like the ground grid, every tenth major) replaces the ground grid. The overlay is part of `renderKey` and of the frame snapshot; the renderer caches its buffer by overlay, camera, scale and palette. To keep `ViewportRenderer` under `type_body_length`, its handle-buffer function moves unchanged into `ViewportRenderer+Handles.swift` and the overlay's into `ViewportRenderer+Overlay.swift` (a few members become internal).

**Files:**
- Modify: `Sources/CreatorViewport/Model/ViewportModel+Frame.swift`
- Modify: `Sources/CreatorViewport/Model/ViewportModel.swift`
- Modify: `Sources/CreatorViewport/Model/ViewportRenderKey.swift`
- Create: `Sources/CreatorViewport/Overlay/OverlayLine.swift`
- Create: `Sources/CreatorViewport/Overlay/OverlayPoint.swift`
- Create: `Sources/CreatorViewport/Overlay/OverlayTint.swift`
- Create: `Sources/CreatorViewport/Overlay/ViewportOverlay.swift`
- Create: `Sources/CreatorViewport/Render/OverlayBufferKey.swift`
- Create: `Sources/CreatorViewport/Render/OverlayGeometry.swift`
- Modify: `Sources/CreatorViewport/Render/ViewportFrame.swift`
- Create: `Sources/CreatorViewport/Render/ViewportPalette+Overlay.swift`
- Modify: `Sources/CreatorViewport/Render/ViewportPalette.swift`
- Create: `Sources/CreatorViewport/Render/ViewportRenderer+Handles.swift`
- Create: `Sources/CreatorViewport/Render/ViewportRenderer+Overlay.swift`
- Modify: `Sources/CreatorViewport/Render/ViewportRenderer.swift`
- Modify: `Tests/CreatorViewportTests/OffscreenRenderTests.swift`
- Create: `Tests/CreatorViewportTests/OverlayTests.swift`

**Interfaces:**
- Consumes: `LineInstance`, `GPUGeometry.float3`, `ViewportPalette`, `GridSpacing` (via `frame.gridSpacing`), `CameraMath.millimetresPerPoint`, `ThemeColors.sketch*` and `profileHeader`.
- Produces: `public struct ViewportOverlay { lines: [OverlayLine]; points: [OverlayPoint]; gridPlane: Plane?; isEmpty }`; `public struct OverlayLine { a, b: Vector3; tint: OverlayTint; width: Double = 1.5; isDashed: Bool = false }` (init `OverlayLine(_:_:tint:width:isDashed:)`); `public struct OverlayPoint { position; tint; size = 6 }`; `public enum OverlayTint { underConstrained, fullyConstrained, conflicting, construction, projected, selected, hovered, preview }`; `ViewportModel.overlay` and `showOverlay(_:)`.

- [ ] **Step 1: Write the failing tests**

Modify `Tests/CreatorViewportTests/OffscreenRenderTests.swift` (apply this diff):

```diff
--- a/Tests/CreatorViewportTests/OffscreenRenderTests.swift
+++ b/Tests/CreatorViewportTests/OffscreenRenderTests.swift
@@ -92,6 +92,9 @@ struct OffscreenRenderTests {
                                         style: .linear, tint: .solid),
         ]
         frame.hoveredCubeRegion = .top
+        // A sketch overlay: a plane grid in place of the ground grid, a dashed construction line and a point.
+        frame.overlay = ViewportOverlay(lines: [OverlayLine(.zero, Vector3(10, 0, 10), tint: .construction, isDashed: true)],
+                                        points: [OverlayPoint(Vector3(10, 0, 10), tint: .fullyConstrained)], gridPlane: .xz)
         let device = try #require(MTLCreateSystemDefaultDevice())
         let renderer = try ViewportRenderer(device: device)
         let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 400, height: 400,
```

Create `Tests/CreatorViewportTests/OverlayTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import CreatorStyle
import Testing
@testable import CreatorViewport

/// The host's overlay (the sketch editor's geometry, sketcher spec §8): drawn over the scene in the theme's sketch
/// colours, construction dashed, a plane grid in place of the ground grid, and redrawn when it changes.
@MainActor
struct OverlayTests {
    let top = CameraPose(target: .zero, distance: 100, pitch: .pi / 2, projection: .orthographic)
    let size = ViewportSize(width: 400, height: 300)

    @Test func eachTintTakesItsThemeRole() {
        let theme = ColorTheme.dracula
        let palette = ViewportPalette(theme)
        #expect(palette.color(.underConstrained) == theme.colors.sketchUnderConstrained.rgba)
        #expect(palette.color(.fullyConstrained) == theme.colors.sketchFullyConstrained.rgba)
        #expect(palette.color(.conflicting) == theme.colors.sketchConflicting.rgba)
        #expect(palette.color(.construction) == theme.colors.sketchConstruction.rgba)
        #expect(palette.color(.projected) == theme.colors.sketchProjected.rgba)
        #expect(palette.color(.selected) == theme.colors.profileHeader.rgba, "the Sketch node's header colour")
        #expect(palette.color(.hovered) == theme.colors.focus.rgba)
        #expect(palette.color(.preview).w < 1, "the rubber band is faded")
    }

    @Test func linesAndPointsBecomeInstancesInPointWidthsTimesTheScale() {
        let overlay = ViewportOverlay(lines: [OverlayLine(.zero, Vector3(10, 0, 0), tint: .conflicting, width: 2)],
                                      points: [OverlayPoint(Vector3(10, 0, 0), tint: .fullyConstrained, size: 6)])
        let instances = OverlayGeometry.instances(overlay, pose: top, size: size, gridSpacing: 10, scale: 2, palette: .dracula)
        #expect(instances.count == 2)
        #expect(instances[0].width == 4 && instances[0].color == ViewportPalette.dracula.sketchConflicting)
        #expect(instances[1].a == instances[1].b && instances[1].width == 12, "a point is a square knob")
    }

    @Test func dashedLinesAreCutIntoDashesAtTheCurrentZoom() {
        let pieces = OverlayGeometry.dashes(.zero, Vector3(25, 0, 0), millimetresPerPoint: 1)
        #expect(pieces.count == 3, "dashes start every 10 points: at 0, 10 and 20")
        #expect(pieces[0].1 == Vector3(6, 0, 0))
        #expect(pieces[2].0 == Vector3(20, 0, 0) && pieces[2].1 == Vector3(25, 0, 0), "the last dash stops at the end")
        #expect(OverlayGeometry.dashes(.zero, Vector3(1e6, 0, 0), millimetresPerPoint: 1e-3).count == 1,
                "a dash pattern far finer than the line is drawn solid")
    }

    @Test func thePlaneGridLiesOnThePlaneWithEveryTenthLineMajor() throws {
        let plane = Plane(origin: Vector3(0, 0, 5), normal: .unitZ, xAxis: .unitX)
        let lines = OverlayGeometry.gridLines(on: plane, pose: top, size: size, spacing: 1)
        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy { $0.a.z == 5 && $0.b.z == 5 }, "on the plane, not the ground")
        let throughOrigin = try #require(lines.first { $0.a.x == 0 && $0.b.x == 0 })
        #expect(throughOrigin.major)
        #expect(lines.first { $0.a.x == 1 && $0.b.x == 1 }?.major == false)
    }

    @Test func showingAnOverlayRedrawsAndReachesTheFrame() {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: top, clock: ManualClock())
        model.viewSize = size
        let before = model.renderKey
        let overlay = ViewportOverlay(lines: [OverlayLine(.zero, .unitX, tint: .underConstrained)], gridPlane: .xy)
        model.showOverlay(overlay)
        #expect(model.renderKey != before)
        #expect(model.frame(at: 0).overlay == overlay)
        let key = model.renderKey
        model.showOverlay(overlay)
        #expect(model.renderKey == key, "an equal overlay changes nothing")
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter 'OverlayTests|OffscreenRenderTests'`

Expected: FAIL — the build fails: "cannot find type 'ViewportOverlay' in scope".

- [ ] **Step 3: Add the overlay and draw it**

Modify `Sources/CreatorViewport/Model/ViewportModel+Frame.swift` (apply this diff):

```diff
--- a/Sources/CreatorViewport/Model/ViewportModel+Frame.swift
+++ b/Sources/CreatorViewport/Model/ViewportModel+Frame.swift
@@ -16,7 +16,7 @@ extension ViewportModel {
         }
         return ViewportFrame(pose: shown, size: viewSize, sceneBounds: sceneBounds, items: frameItems, shading: shading,
                              gridSpacing: gridSpacing(for: shown), handles: handles, cube: cubeLayout,
-                             hoveredCubeRegion: hoveredCubeRegion, triad: triadLayout, palette: palette)
+                             hoveredCubeRegion: hoveredCubeRegion, triad: triadLayout, palette: palette, overlay: overlay)
     }
 
     /// 1, 10 or 100 mm for this pose in this view.
```

Modify `Sources/CreatorViewport/Model/ViewportModel.swift` (apply this diff):

```diff
--- a/Sources/CreatorViewport/Model/ViewportModel.swift
+++ b/Sources/CreatorViewport/Model/ViewportModel.swift
@@ -41,6 +41,8 @@ public final class ViewportModel {
     /// requested scene's meshes are ready.
     public private(set) var items: [ViewportItem] = []
     public internal(set) var handles: [ViewportHandle] = []
+    /// Lines and points the host draws over the scene (`showOverlay(_:)`): the sketch editor's geometry.
+    public private(set) var overlay = ViewportOverlay()
     public internal(set) var hovered: PickTarget?
     public internal(set) var hoveredCubeRegion: ViewCubeRegion?
     /// What the drag under way does, or `nil` between drags. It's written once at each press and release (never per
@@ -98,7 +100,7 @@ public final class ViewportModel {
     public var renderKey: ViewportRenderKey {
         ViewportRenderKey(pose: pose, isAnimating: isAnimating, shading: shading, hovered: hovered,
                           hoveredCubeRegion: hoveredCubeRegion, sceneGeneration: sceneGeneration, handles: handles,
-                          cube: cubeLayout, triad: triadLayout, palette: palette)
+                          cube: cubeLayout, triad: triadLayout, palette: palette, overlay: overlay)
     }
 
     /// The union of every shown solid's bounds, ghosts included.
@@ -147,6 +149,11 @@ public final class ViewportModel {
         handles = newHandles
     }
 
+    /// The overlay to draw over the scene (the sketch editor's geometry and plane grid); an equal one changes nothing.
+    public func showOverlay(_ newOverlay: ViewportOverlay) {
+        if overlay != newOverlay { overlay = newOverlay }
+    }
+
     /// Returns once the most recent `show(_:)` has finished loading.
     public func waitForMeshes() async {
         while let task = meshTask {
```

Modify `Sources/CreatorViewport/Model/ViewportRenderKey.swift` (apply this diff):

```diff
--- a/Sources/CreatorViewport/Model/ViewportRenderKey.swift
+++ b/Sources/CreatorViewport/Model/ViewportRenderKey.swift
@@ -15,4 +15,6 @@ public struct ViewportRenderKey: Hashable, Sendable {
     var triad: TriadLayout
     /// The theme's GPU colours: switching themes redraws.
     var palette: ViewportPalette
+    /// The host's overlay: a sketch edit redraws.
+    var overlay: ViewportOverlay
 }
```

Create `Sources/CreatorViewport/Overlay/OverlayLine.swift`:

```swift
import CreatorGeometry

/// One straight overlay segment in world space (a sketch line, or one piece of a tessellated arc).
public struct OverlayLine: Hashable, Sendable {
    public var a: Vector3
    public var b: Vector3
    public var tint: OverlayTint
    /// Width in points.
    public var width: Double
    /// Drawn as dashes of `OverlayGeometry.dash` points with `OverlayGeometry.gap`-point gaps (construction).
    public var isDashed: Bool

    public init(_ a: Vector3, _ b: Vector3, tint: OverlayTint, width: Double = 1.5, isDashed: Bool = false) {
        self.a = a
        self.b = b
        self.tint = tint
        self.width = width
        self.isDashed = isDashed
    }
}
```

Create `Sources/CreatorViewport/Overlay/OverlayPoint.swift`:

```swift
import CreatorGeometry

/// One overlay knob in world space: a square `size` points wide (a sketch point).
public struct OverlayPoint: Hashable, Sendable {
    public var position: Vector3
    public var tint: OverlayTint
    public var size: Double

    public init(_ position: Vector3, tint: OverlayTint, size: Double = 6) {
        self.position = position
        self.tint = tint
        self.size = size
    }
}
```

Create `Sources/CreatorViewport/Overlay/OverlayTint.swift`:

```swift
/// What an overlay line or point is drawn in: a role the viewport's theme colours (sketcher spec §8's table).
public enum OverlayTint: Hashable, Sendable {
    /// Geometry that can still move (cyan in Dracula).
    case underConstrained
    /// Geometry the constraints fix (the foreground colour).
    case fullyConstrained
    /// Geometry a conflict names (red).
    case conflicting
    /// Construction geometry (the comment colour); its lines are usually dashed.
    case construction
    /// Geometry projected from the model (purple).
    case projected
    /// Selected geometry: the Sketch node's header colour (green).
    case selected
    /// Geometry under the pointer: the theme's focus colour.
    case hovered
    /// A tool's rubber band, before it's committed: the under-constrained colour, faded.
    case preview
}
```

Create `Sources/CreatorViewport/Overlay/ViewportOverlay.swift`:

```swift
import CreatorGeometry

/// Lines and points the host draws over the scene, on top of everything but the widgets (the sketch editor's
/// geometry, sketcher spec §8). With a `gridPlane`, a grid on that plane replaces the ground grid. The viewport
/// never interprets it: the host builds it, the viewport draws it.
public struct ViewportOverlay: Hashable, Sendable {
    public var lines: [OverlayLine]
    public var points: [OverlayPoint]
    /// The plane whose grid is drawn instead of the ground grid, or `nil` for the ground grid.
    public var gridPlane: Plane?

    public init(lines: [OverlayLine] = [], points: [OverlayPoint] = [], gridPlane: Plane? = nil) {
        self.lines = lines
        self.points = points
        self.gridPlane = gridPlane
    }

    public var isEmpty: Bool { lines.isEmpty && points.isEmpty && gridPlane == nil }
}
```

Create `Sources/CreatorViewport/Render/OverlayBufferKey.swift`:

```swift
import CreatorGeometry

/// What the renderer's overlay buffer is built from: the overlay, and the camera and scale its dashes and plane
/// grid depend on.
struct OverlayBufferKey: Equatable {
    var overlay: ViewportOverlay
    var pose: CameraPose
    var size: ViewportSize
    var gridSpacing: Double
    var scale: Float
    var palette: ViewportPalette
}
```

Create `Sources/CreatorViewport/Render/OverlayGeometry.swift`:

```swift
import CreatorGeometry
import Foundation

/// Turns a `ViewportOverlay` into line instances (pure, so it's tested without a GPU): the plane grid first, so the
/// sketch draws over it, then the lines (dashed ones cut into dashes at the current zoom), then the points.
enum OverlayGeometry {
    /// A dash and the gap after it, in points.
    static let dash = 6.0
    static let gap = 4.0
    /// More dashes than this on one line and it's drawn solid (a dash pattern finer than a pixel reads as solid).
    static let dashLimit = 2_000
    /// The plane grid's minor and major line widths, in points.
    static let gridWidth = 1.0
    static let majorGridWidth = 1.25

    static func instances(_ overlay: ViewportOverlay, pose: CameraPose, size: ViewportSize, gridSpacing: Double,
                          scale: Float, palette: ViewportPalette) -> [LineInstance] {
        var instances: [LineInstance] = []
        let millimetresPerPoint = CameraMath.millimetresPerPoint(pose, size: size)
        if let plane = overlay.gridPlane {
            for line in gridLines(on: plane, pose: pose, size: size, spacing: gridSpacing) {
                let color = line.major ? palette.gridMajor : palette.gridMinor
                let width = Float(line.major ? majorGridWidth : gridWidth) * scale
                instances.append(LineInstance(a: GPUGeometry.float3(line.a), b: GPUGeometry.float3(line.b), color: color,
                                              width: width, id: 0))
            }
        }
        for line in overlay.lines {
            let color = palette.color(line.tint)
            let width = Float(line.width) * scale
            let pieces = line.isDashed ? dashes(line.a, line.b, millimetresPerPoint: millimetresPerPoint) : [(line.a, line.b)]
            for (a, b) in pieces {
                instances.append(LineInstance(a: GPUGeometry.float3(a), b: GPUGeometry.float3(b), color: color, width: width, id: 0))
            }
        }
        for point in overlay.points {
            let at = GPUGeometry.float3(point.position)
            instances.append(LineInstance(a: at, b: at, color: palette.color(point.tint), width: Float(point.size) * scale, id: 0))
        }
        return instances
    }

    /// `a`–`b` cut into dashes `dash` points long with `gap`-point gaps at `millimetresPerPoint`, the last dash
    /// clipped at `b`. A degenerate zoom, or more than `dashLimit` dashes, gives the whole line.
    static func dashes(_ a: Vector3, _ b: Vector3, millimetresPerPoint: Double) -> [(Vector3, Vector3)] {
        let length = (b - a).length
        let period = (dash + gap) * millimetresPerPoint
        guard length > 0, period.isFinite, period > 0, length / period <= Double(dashLimit) else { return [(a, b)] }
        let direction = (b - a) * (1 / length)
        var pieces: [(Vector3, Vector3)] = []
        var start = 0.0
        while start < length {
            let end = min(start + dash * millimetresPerPoint, length)
            pieces.append((a + direction * start, a + direction * end))
            start += period
        }
        return pieces
    }

    /// Grid lines on `plane` every `spacing` mm, every tenth one major, around the camera's target dropped onto the
    /// plane (snapped to a major line so the grid doesn't swim while panning), reaching past the view's edges.
    static func gridLines(on plane: Plane, pose: CameraPose, size: ViewportSize,
                          spacing: Double) -> [(a: Vector3, b: Vector3, major: Bool)] {
        guard spacing.isFinite, spacing > 0, !size.isEmpty else { return [] }
        let offset = pose.target - plane.origin
        let major = spacing * 10
        let centreX = (offset.dot(plane.xAxis) / major).rounded() * major
        let centreY = (offset.dot(plane.yAxis) / major).rounded() * major
        let reach = (pose.visibleHeight * max(size.aspect, 1) / spacing).rounded(.up) * spacing + major
        let count = Int(reach / spacing)
        var lines: [(a: Vector3, b: Vector3, major: Bool)] = []
        for step in -count...count {
            let along = Double(step) * spacing
            let isMajor = ((centreX + along) / major).rounded() * major == centreX + along
            lines.append((plane.point(Vector2(centreX + along, centreY - reach)), plane.point(Vector2(centreX + along, centreY + reach)),
                          isMajor))
        }
        for step in -count...count {
            let along = Double(step) * spacing
            let isMajor = ((centreY + along) / major).rounded() * major == centreY + along
            lines.append((plane.point(Vector2(centreX - reach, centreY + along)), plane.point(Vector2(centreX + reach, centreY + along)),
                          isMajor))
        }
        return lines
    }
}
```

Modify `Sources/CreatorViewport/Render/ViewportFrame.swift` (apply this diff):

```diff
--- a/Sources/CreatorViewport/Render/ViewportFrame.swift
+++ b/Sources/CreatorViewport/Render/ViewportFrame.swift
@@ -15,6 +15,8 @@ struct ViewportFrame {
     var triad: TriadLayout
     /// The colours to draw in: the model's theme (`ViewportModel.palette`).
     var palette: ViewportPalette = .dracula
+    /// The host's overlay (`ViewportModel.overlay`): the sketch editor's geometry and plane grid.
+    var overlay = ViewportOverlay()
 
     /// Half the scene's diagonal (at least 1 mm), used for depth ranges.
     var sceneRadius: Double { sceneBounds.map { max($0.size.length / 2, 1) } ?? 1 }
```

Create `Sources/CreatorViewport/Render/ViewportPalette+Overlay.swift`:

```swift
extension ViewportPalette {
    /// An overlay tint's colour (sketcher spec §8's table).
    func color(_ tint: OverlayTint) -> SIMD4<Float> {
        switch tint {
        case .underConstrained: sketchUnderConstrained
        case .fullyConstrained: sketchFullyConstrained
        case .conflicting: sketchConflicting
        case .construction: sketchConstruction
        case .projected: sketchProjected
        case .selected: sketchSelected
        case .hovered: hover
        case .preview: sketchPreview
        }
    }
}
```

Modify `Sources/CreatorViewport/Render/ViewportPalette.swift` (apply this diff):

```diff
--- a/Sources/CreatorViewport/Render/ViewportPalette.swift
+++ b/Sources/CreatorViewport/Render/ViewportPalette.swift
@@ -24,6 +24,15 @@ struct ViewportPalette: Hashable, Sendable {
     var axisX: SIMD4<Float>
     var axisY: SIMD4<Float>
     var axisZ: SIMD4<Float>
+    /// The sketch overlay (sketcher spec §8): free, fixed, conflicting, construction and projected geometry, the
+    /// selection (the Sketch node's header colour) and a tool's rubber band (the free colour, faded).
+    var sketchUnderConstrained: SIMD4<Float>
+    var sketchFullyConstrained: SIMD4<Float>
+    var sketchConflicting: SIMD4<Float>
+    var sketchConstruction: SIMD4<Float>
+    var sketchProjected: SIMD4<Float>
+    var sketchSelected: SIMD4<Float>
+    var sketchPreview: SIMD4<Float>
 
     init(_ theme: ColorTheme) {
         let colors = theme.colors
@@ -44,6 +53,13 @@ struct ViewportPalette: Hashable, Sendable {
         axisX = colors.axisX.rgba
         axisY = colors.axisY.rgba
         axisZ = colors.axisZ.rgba
+        sketchUnderConstrained = colors.sketchUnderConstrained.rgba
+        sketchFullyConstrained = colors.sketchFullyConstrained.rgba
+        sketchConflicting = colors.sketchConflicting.rgba
+        sketchConstruction = colors.sketchConstruction.rgba
+        sketchProjected = colors.sketchProjected.rgba
+        sketchSelected = colors.profileHeader.rgba
+        sketchPreview = colors.sketchUnderConstrained.opacity(0.6).rgba
     }
 
     /// The default theme's colours.
```

Create `Sources/CreatorViewport/Render/ViewportRenderer+Handles.swift`:

```swift
import Metal

extension ViewportRenderer {
    /// The frame's handles in its palette, kept until the handles, the scale or the palette change.
    func handleInstances(for frame: ViewportFrame, scale: Float) -> (buffer: any MTLBuffer, count: Int)? {
        if let cached = handleBuffer, cached.handles == frame.handles, cached.scale == scale, handlePalette == frame.palette {
            return (cached.buffer, cached.count)
        }
        handlePalette = frame.palette
        let instances = GPUGeometry.handleInstances(frame.handles, scale: scale, palette: frame.palette)
        guard let buffer = GPUBuffers.make(device, instances) else {
            handleBuffer = nil
            return nil
        }
        handleBuffer = (frame.handles, scale, buffer, instances.count)
        return (buffer, instances.count)
    }
}
```

Create `Sources/CreatorViewport/Render/ViewportRenderer+Overlay.swift`:

```swift
import Metal

extension ViewportRenderer {
    /// The host's overlay over the scene and the ghosts, whatever their depth (sketcher spec §8: the sketch is drawn
    /// over the dimmed model).
    func drawOverlay(_ frame: ViewportFrame, _ uniforms: FrameUniforms, scale: Float, _ encoder: any MTLRenderCommandEncoder) {
        guard let overlay = overlayInstances(for: frame, scale: scale) else { return }
        drawLines(overlay.buffer, count: overlay.count, uniforms, depth: pipelines.depthAlways, style: Self.plainLines, encoder)
    }

    /// The frame's overlay in its palette, kept until the overlay, the camera, the scale or the palette change.
    func overlayInstances(for frame: ViewportFrame, scale: Float) -> (buffer: any MTLBuffer, count: Int)? {
        guard !frame.overlay.isEmpty else { return nil }
        let key = OverlayBufferKey(overlay: frame.overlay, pose: frame.pose, size: frame.size, gridSpacing: frame.gridSpacing,
                                   scale: scale, palette: frame.palette)
        if let cached = overlayBuffer, cached.key == key { return (cached.buffer, cached.count) }
        let instances = OverlayGeometry.instances(frame.overlay, pose: frame.pose, size: frame.size,
                                                  gridSpacing: frame.gridSpacing, scale: scale, palette: frame.palette)
        guard let buffer = GPUBuffers.make(device, instances) else {
            overlayBuffer = nil
            return nil
        }
        overlayBuffer = (key, buffer, instances.count)
        return (buffer, instances.count)
    }
}
```

Modify `Sources/CreatorViewport/Render/ViewportRenderer.swift` (apply this diff):

```diff
--- a/Sources/CreatorViewport/Render/ViewportRenderer.swift
+++ b/Sources/CreatorViewport/Render/ViewportRenderer.swift
@@ -13,16 +13,18 @@ import Metal
 @MainActor
 final class ViewportRenderer {
     let device: any MTLDevice
-    private let pipelines: ViewportPipelines
+    let pipelines: ViewportPipelines
     private let placeholder: any MTLBuffer
     private var meshes: [Int: GPUMesh] = [:]
     private var multisample: (width: Int, height: Int, color: any MTLTexture, depth: any MTLTexture)?
     /// The handles' instances, kept until the handles change, so a frame of a continuous orbit allocates no
     /// buffers (spec §7.3's 60 fps). The view cube keeps its own.
-    private var handleBuffer: (handles: [ViewportHandle], scale: Float, buffer: any MTLBuffer, count: Int)?
+    var handleBuffer: (handles: [ViewportHandle], scale: Float, buffer: any MTLBuffer, count: Int)?
+    /// The overlay's instances, kept until what they're built from changes (dashes and the plane grid follow the zoom).
+    var overlayBuffer: (key: OverlayBufferKey, buffer: any MTLBuffer, count: Int)?
     private let cube: ViewCubeResources
     /// The palette `handleBuffer` was built in.
-    private var handlePalette = ViewportPalette.dracula
+    var handlePalette = ViewportPalette.dracula
     /// Main passes encoded so far. Tests use it to tell "drew" from "bailed out".
     private(set) var encodedPasses = 0
 
@@ -62,9 +64,10 @@ final class ViewportRenderer {
                                                  pixelWidth: width, pixelHeight: height)
         drawBackground(frame.palette, encoder)
         drawSolids(frame, ghosts: false, uniforms, encoder)
-        drawGrid(frame, uniforms, encoder)
+        if frame.overlay.gridPlane == nil { drawGrid(frame, uniforms, encoder) }
         drawEdges(frame, uniforms, scale: pixelScale, encoder)
         drawSolids(frame, ghosts: true, uniforms, encoder)
+        drawOverlay(frame, uniforms, scale: pixelScale, encoder)
         if let handles = handleInstances(for: frame, scale: pixelScale) {
             drawLines(handles.buffer, count: handles.count, uniforms, depth: pipelines.depthAlways, style: Self.plainLines,
                       encoder)
@@ -114,7 +117,7 @@ final class ViewportRenderer {
 
     // MARK: - Layers
 
-    private static let plainLines = LineUniforms(widthOverride: 0, depthBias: 0, padding0: 0, padding1: 0)
+    static let plainLines = LineUniforms(widthOverride: 0, depthBias: 0, padding0: 0, padding1: 0)
 
     /// How far (mm) edges move towards the camera so they win against the faces they bound.
     private func edgeDepthBias(_ frame: ViewportFrame) -> Double { max(frame.pose.distance * 0.002, 1e-3) }
@@ -181,21 +184,6 @@ final class ViewportRenderer {
         }
     }
 
-    /// The frame's handles in its palette, kept until the handles, the scale or the palette change.
-    private func handleInstances(for frame: ViewportFrame, scale: Float) -> (buffer: any MTLBuffer, count: Int)? {
-        if let cached = handleBuffer, cached.handles == frame.handles, cached.scale == scale, handlePalette == frame.palette {
-            return (cached.buffer, cached.count)
-        }
-        handlePalette = frame.palette
-        let instances = GPUGeometry.handleInstances(frame.handles, scale: scale, palette: frame.palette)
-        guard let buffer = GPUBuffers.make(device, instances) else {
-            handleBuffer = nil
-            return nil
-        }
-        handleBuffer = (frame.handles, scale, buffer, instances.count)
-        return (buffer, instances.count)
-    }
-
     private func drawGrid(_ frame: ViewportFrame, _ uniforms: FrameUniforms, _ encoder: any MTLRenderCommandEncoder) {
         var grid = GPUGeometry.gridUniforms(frame)
         encoder.setRenderPipelineState(pipelines.grid)
@@ -219,9 +207,9 @@ final class ViewportRenderer {
         }
     }
 
-    private func drawLines(_ buffer: any MTLBuffer, count: Int, _ uniforms: FrameUniforms,
-                           depth: any MTLDepthStencilState, style: LineUniforms,
-                           pipeline: (any MTLRenderPipelineState)? = nil, _ encoder: any MTLRenderCommandEncoder) {
+    func drawLines(_ buffer: any MTLBuffer, count: Int, _ uniforms: FrameUniforms,
+                   depth: any MTLDepthStencilState, style: LineUniforms,
+                   pipeline: (any MTLRenderPipelineState)? = nil, _ encoder: any MTLRenderCommandEncoder) {
         guard count > 0 else { return }
         var style = style
         encoder.setRenderPipelineState(pipeline ?? pipelines.line)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter 'OverlayTests|OffscreenRenderTests'`

Expected: PASS (exit 0, no line says "recorded an issue" or "failed after").

- [ ] **Step 5: Full verification**

Run, from the repo root: `swift build --build-tests 2>&1 | grep -E "(error|warning):" | grep -v "ld: warning"` (expected: nothing new; master's one test warning, `ContextMenuTests.swift:96` "'underPointer' mutated after capture", shows only when that file recompiles), then `swift test` (expected: exit 0, no "recorded an issue" / "failed after" lines, and the "Test run with N tests" lines sum to **1103 (master + 18)**), then `swiftlint lint --strict` (zero violations).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorViewport/Model/ViewportModel+Frame.swift Sources/CreatorViewport/Model/ViewportModel.swift Sources/CreatorViewport/Model/ViewportRenderKey.swift Sources/CreatorViewport/Overlay/OverlayLine.swift Sources/CreatorViewport/Overlay/OverlayPoint.swift Sources/CreatorViewport/Overlay/OverlayTint.swift Sources/CreatorViewport/Overlay/ViewportOverlay.swift Sources/CreatorViewport/Render/OverlayBufferKey.swift Sources/CreatorViewport/Render/OverlayGeometry.swift Sources/CreatorViewport/Render/ViewportFrame.swift Sources/CreatorViewport/Render/ViewportPalette+Overlay.swift Sources/CreatorViewport/Render/ViewportPalette.swift Sources/CreatorViewport/Render/ViewportRenderer+Handles.swift Sources/CreatorViewport/Render/ViewportRenderer+Overlay.swift Sources/CreatorViewport/Render/ViewportRenderer.swift Tests/CreatorViewportTests/OffscreenRenderTests.swift Tests/CreatorViewportTests/OverlayTests.swift
git commit -m "feat(viewport): draw a host overlay of lines and points with a plane grid"
```


---

### Task 4: `CreatorSketchEditor` target and the `SketchEditorModel` core

The new graph-free target (sketcher spec §2; it also takes CreatorStyle for theme colours, which postdates the spec's table; CreatorKernel waits for Project in S5b) and its test target, and `CreatorApp`/`CreatorAppTests` get `CreatorSketch` and `CreatorSketchEditor` now, so `Package.swift` changes once. The model holds the sketch as shown (solved and remembered), the plane and the live solution; `commit(_:_:)` solves, remembers when usable (handoff: an unusable solve keeps its warm start) and hands a `SketchCommit` to the host; `reload(_:plane:)` shows what the host stored (after undo). `statusText` is the inspector's readout; an empty sketch says how to start instead of "Fully constrained".

**Files:**
- Modify: `Package.swift`
- Create: `Sources/CreatorSketchEditor/SketchCommit.swift`
- Create: `Sources/CreatorSketchEditor/SketchEditorEvents.swift`
- Create: `Sources/CreatorSketchEditor/SketchEditorModel+Status.swift`
- Create: `Sources/CreatorSketchEditor/SketchEditorModel.swift`
- Create: `Tests/CreatorSketchEditorTests/SketchEditorModelTests.swift`
- Create: `Tests/CreatorSketchEditorTests/Support/SketchFixtures.swift`

**Interfaces:**
- Consumes: `SketchSolver.solve(_:)`, `Sketch.remember(_:)`, `SketchSolveStatus.isUsable`, `SketchSolution.conflictMessages`.
- Produces: `@MainActor @Observable public final class SketchEditorModel { sketch: Sketch; plane: Plane; solution: SketchSolution; refusal: String?; events: SketchEditorEvents; init(sketch:plane:); reload(_:plane:); commit(_ edited: Sketch, _ description: String) (internal); static remembering(_:_:) (internal); statusText: String; statusIsProblem: Bool }`; `public struct SketchCommit { sketch: Sketch; description: String }`; `public struct SketchEditorEvents { committed: (SketchCommit) -> Void; finished: () -> Void }`. Test fixtures `RectangleSketch` (corners IDs 1–4, lines 5–8, width d1, height d2) and `RecordingHost`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorSketchEditorTests/SketchEditorModelTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// The editor's sketch, its live solve and its commits (sketcher spec §8; S4 → S5 handoff: every edit stores the
/// remembered solve as one step).
@MainActor
struct SketchEditorModelTests {
    @Test func loadingSolvesAndRemembersWithoutCommitting() {
        var rectangle = RectangleSketch()
        rectangle.sketch.move(rectangle.corners[2], to: Vector2(70, 45))
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        let host = RecordingHost(model)
        #expect(model.solution.status == .solved)
        #expect(model.sketch.position(of: rectangle.corners[2]) == model.solution.points[rectangle.corners[2]],
                "the shown positions are the solved ones")
        #expect(host.commits.isEmpty, "opening a sketch isn't an edit")
    }

    @Test func aCommitStoresTheRememberedSolveAsOneStep() throws {
        let rectangle = RectangleSketch()
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        let host = RecordingHost(model)
        var edited = model.sketch
        edited.dimensions[rectangle.width]?.value = 80
        model.commit(edited, "Change d1")
        let commit = try #require(host.commits.first)
        #expect(host.commits.count == 1 && commit.description == "Change d1")
        let corner = try #require(commit.sketch.position(of: rectangle.corners[1]))
        #expect(abs(corner.x - 80) < 1e-6, "the stored sketch warm-starts from the new solve")
        #expect(model.sketch == commit.sketch)
    }

    @Test func anUnusableSolveIsCommittedAsDrawn() throws {
        let rectangle = RectangleSketch()
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        let host = RecordingHost(model)
        var edited = model.sketch
        edited.add(.vertical(rectangle.lines[0]))
        model.commit(edited, "Vertical")
        #expect(model.statusIsProblem)
        #expect(host.commits.first?.sketch == edited, "a conflicting sketch keeps its warm start")
    }

    @Test func reloadingTheShownSketchChangesNothing() {
        let rectangle = RectangleSketch()
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        let shown = model.sketch
        model.reload(shown, plane: .xy)
        #expect(model.sketch == shown)
        var undone = RectangleSketch(dimensioned: false).sketch
        undone.move(undone.entityIDs[0], to: Vector2(1, 1))
        model.reload(undone, plane: .xz)
        #expect(model.plane == .xz)
        #expect(model.solution.degreesOfFreedom == 2, "an undo back to an undimensioned rectangle re-solves it")
    }

    @Test func anEmptySketchSaysHowToStartNotFullyConstrained() {
        #expect(SketchEditorModel(sketch: Sketch(), plane: .xy).statusText.hasPrefix("Nothing drawn yet"))
    }

    @Test func theReadoutNamesTheFreedomOrTheProblem() {
        #expect(SketchEditorModel(sketch: RectangleSketch().sketch, plane: .xy).statusText == "Fully constrained")
        #expect(SketchEditorModel(sketch: RectangleSketch(dimensioned: false).sketch, plane: .xy).statusText
            == "2 degrees of freedom")
        var oneShort = RectangleSketch(dimensioned: false).sketch
        oneShort.addDimension(.length(oneShort.entityIDs[4]), value: 60)
        #expect(SketchEditorModel(sketch: oneShort, plane: .xy).statusText == "1 degree of freedom")
        var conflicting = RectangleSketch().sketch
        conflicting.add(.vertical(conflicting.entityIDs[4]))
        let model = SketchEditorModel(sketch: conflicting, plane: .xy)
        #expect(model.statusIsProblem && model.statusText.contains("conflicts with"))
    }
}
```

Create `Tests/CreatorSketchEditorTests/Support/SketchFixtures.swift`:

```swift
// Test fixture file: sketches and a recording host for the sketch editor's tests.
import CreatorGeometry
import CreatorSketch
@testable import CreatorSketchEditor

/// A 60 × 40 rectangle of four shared-corner lines, held by horizontal and vertical constraints and a fixed corner,
/// with `width` and `height` dimensions: fully constrained when both are driving.
struct RectangleSketch {
    var sketch = Sketch()
    var corners: [SketchEntityID] = []
    var lines: [SketchEntityID] = []
    var width = DimensionID(0)
    var height = DimensionID(0)

    init(dimensioned: Bool = true) {
        corners = [Vector2(0, 0), Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)].map { sketch.addPoint($0) }
        lines = (0..<4).map { sketch.addLine(from: corners[$0], to: corners[($0 + 1) % 4]) }
        sketch.add(.horizontal(lines[0]))
        sketch.add(.horizontal(lines[2]))
        sketch.add(.vertical(lines[1]))
        sketch.add(.vertical(lines[3]))
        sketch.add(.fix(corners[0], at: .zero))
        if dimensioned {
            width = sketch.addDimension(.length(lines[0]), value: 60)
            height = sketch.addDimension(.length(lines[1]), value: 40)
        }
    }
}

/// Collects what an editor hands its host.
@MainActor
final class RecordingHost {
    private(set) var commits: [SketchCommit] = []
    private(set) var finishes = 0

    init(_ model: SketchEditorModel) {
        model.events.committed = { [weak self] in self?.commits.append($0) }
        model.events.finished = { [weak self] in self?.finishes += 1 }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter CreatorSketchEditorTests`

Expected: FAIL — the build fails: "no such module 'CreatorSketchEditor'" until `Package.swift` and the sources exist (write the manifest change first, then the tests fail with "cannot find 'SketchEditorModel' in scope").

- [ ] **Step 3: Add the target and the model**

Modify `Package.swift` (apply this diff):

```diff
--- a/Package.swift
+++ b/Package.swift
@@ -46,13 +46,17 @@ let package = Package(
             name: "GraphPanelPreview",
             dependencies: ["CreatorEditor", "CreatorGraph", "CreatorKernel", "CreatorGeometry", metalUI]
         ),
-        // The app shell (M6): the one target that joins the graph, the nodes, the viewport and the editor. A library,
+        // The in-viewport sketch editor (sketcher spec §8, S5): `SketchEditorModel`, its tools and its views. Graph-free:
+        // the app shell turns its commits into graph commands. CreatorStyle for the theme's colours.
+        .target(name: "CreatorSketchEditor",
+                dependencies: ["CreatorSketch", "CreatorViewport", "CreatorGeometry", "CreatorStyle", metalUI]),
+        // The app shell (M6): the one target that joins the graph, the nodes, the viewport and the editors. A library,
         // so its model is tested; the executable below only opens the window.
         .target(
             name: "CreatorApp",
             dependencies: [
                 "CreatorEditor", "CreatorViewport", "CreatorNodes", "CreatorGraph", "CreatorKernel", "CreatorGeometry",
-                "CreatorStyle", metalUI,
+                "CreatorStyle", "CreatorSketch", "CreatorSketchEditor", metalUI,
             ]
         ),
         .executableTarget(name: "MetalCreatorApp", dependencies: ["CreatorApp", "CreatorOCCT", metalUI]),
@@ -61,7 +65,7 @@ let package = Package(
             name: "CreatorAppTests",
             dependencies: [
                 "CreatorApp", "CreatorEditor", "CreatorViewport", "CreatorNodes", "CreatorGraph", "CreatorKernel",
-                "CreatorGeometry", "CreatorOCCT", "CreatorStyle", metalUI,
+                "CreatorGeometry", "CreatorOCCT", "CreatorStyle", "CreatorSketch", "CreatorSketchEditor", metalUI,
             ]
         ),
         // CreatorNodes is a test-only dependency: BuiltInNodesInspectorTests runs the real M3
@@ -73,6 +77,8 @@ let package = Package(
             ]
         ),
         .testTarget(name: "CreatorStyleTests", dependencies: ["CreatorStyle", metalUI]),
+        .testTarget(name: "CreatorSketchEditorTests",
+                    dependencies: ["CreatorSketchEditor", "CreatorSketch", "CreatorViewport", "CreatorGeometry", "CreatorStyle", metalUI]),
         .testTarget(name: "CreatorOCCTTests", dependencies: ["CreatorOCCT", "CreatorKernel", "CreatorGeometry"]),
         .testTarget(name: "CreatorGeometryTests", dependencies: ["CreatorGeometry"]),
         .testTarget(name: "CreatorSketchTests", dependencies: ["CreatorSketch", "CreatorGeometry"]),
```

Create `Sources/CreatorSketchEditor/SketchCommit.swift`:

```swift
import CreatorSketch

/// One edit the sketch editor made, for the host to store as one undo step (sketcher spec §8): the whole new
/// sketch, already solved and remembered (S4 → S5 handoff), and the undo menu's description.
public struct SketchCommit: Hashable, Sendable {
    public var sketch: Sketch
    public var description: String

    public init(sketch: Sketch, description: String) {
        self.sketch = sketch
        self.description = description
    }
}
```

Create `Sources/CreatorSketchEditor/SketchEditorEvents.swift`:

```swift
/// What the sketch editor tells its host. Every callback runs on the main actor, from input.
public struct SketchEditorEvents {
    /// An edit: the host stores `commit.sketch` in the Sketch node's `sketch` setting as one undo step.
    public var committed: @MainActor (SketchCommit) -> Void = { _ in }
    /// Finish (⏎, Esc with nothing in progress, or the Finish button): the host leaves sketch mode.
    public var finished: @MainActor () -> Void = {}

    public init() {}
}
```

Create `Sources/CreatorSketchEditor/SketchEditorModel+Status.swift`:

```swift
import CreatorSketch

extension SketchEditorModel {
    /// The inspector's readout (sketcher spec §8): "Fully constrained", "3 degrees of freedom", the conflicts, or why
    /// the solve failed. An empty sketch says how to start instead (it would read "Fully constrained").
    public var statusText: String {
        guard !sketch.entities.isEmpty else { return "Nothing drawn yet. Pick Line (L), Arc (A) or Circle (C)." }
        switch solution.status {
        case .solved:
            return "Fully constrained"
        case .underConstrained(let dof):
            return dof == 1 ? "1 degree of freedom" : "\(dof.formatted()) degrees of freedom"
        case .overConstrained:
            let messages = solution.conflictMessages.filter { !$0.isEmpty }
            return messages.isEmpty ? "The constraints conflict." : messages.joined(separator: "\n")
        case .failed(let reason):
            return reason
        }
    }

    /// True when the status is a problem to show in the error colour (a conflict or a failed solve).
    public var statusIsProblem: Bool { !solution.status.isUsable }
}
```

Create `Sources/CreatorSketchEditor/SketchEditorModel.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import Foundation
import Observation

/// The sketch editor's state and behaviour (sketcher spec §8), testable without a GPU or a graph: the sketch being
/// edited and its live solve, the tool and what it has drawn so far, the selection, and the edits it hands to its
/// host (`events`). Its views are thin. The host (the app shell) owns it while one Sketch node is being edited,
/// feeds it the node's stored sketch (`reload(_:)`, after undo or redo too), and stores every `SketchCommit` back.
@MainActor
@Observable
public final class SketchEditorModel {
    /// The sketch as the editor shows it: the last stored or committed one, solved and remembered, so its positions
    /// are the ones on screen.
    public private(set) var sketch: Sketch
    /// The plane the sketch is drawn on, in world space.
    public private(set) var plane: Plane
    /// The live solve of `sketch` (re-run on every edit and every drag step).
    public private(set) var solution: SketchSolution
    /// A plain-language reason the last command was refused, until the next edit or tool change.
    public internal(set) var refusal: String?

    @ObservationIgnored public var events = SketchEditorEvents()

    public init(sketch: Sketch, plane: Plane) {
        self.plane = plane
        let solution = SketchSolver.solve(sketch)
        self.solution = solution
        self.sketch = Self.remembering(sketch, solution)
    }

    /// Shows a sketch that came from the host (undo, redo, or a file change), unless it's the one already shown.
    public func reload(_ stored: Sketch, plane newPlane: Plane) {
        if newPlane != plane { plane = newPlane }
        guard stored != sketch else { return }
        let solved = SketchSolver.solve(stored)
        solution = solved
        sketch = Self.remembering(stored, solved)
    }

    /// Takes `edited` as the sketch, solved and remembered, and hands it to the host as one undo step.
    func commit(_ edited: Sketch, _ description: String) {
        let solved = SketchSolver.solve(edited)
        let stored = Self.remembering(edited, solved)
        solution = solved
        sketch = stored
        refusal = nil
        events.committed(SketchCommit(sketch: stored, description: description))
    }

    /// `sketch` with `solution` as its warm start when the solve is usable (S4 → S5 handoff: the node then
    /// warm-starts from what the user sees); an unusable solve keeps the sketch as it is.
    static func remembering(_ sketch: Sketch, _ solution: SketchSolution) -> Sketch {
        guard solution.status.isUsable else { return sketch }
        var remembered = sketch
        remembered.remember(solution)
        return remembered
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CreatorSketchEditorTests`

Expected: PASS (exit 0, no line says "recorded an issue" or "failed after").

- [ ] **Step 5: Full verification**

Run, from the repo root: `swift build --build-tests 2>&1 | grep -E "(error|warning):" | grep -v "ld: warning"` (expected: nothing new; master's one test warning, `ContextMenuTests.swift:96` "'underPointer' mutated after capture", shows only when that file recompiles), then `swift test` (expected: exit 0, no "recorded an issue" / "failed after" lines, and the "Test run with N tests" lines sum to **1109 (master + 24)**), then `swiftlint lint --strict` (zero violations).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/CreatorSketchEditor/SketchCommit.swift Sources/CreatorSketchEditor/SketchEditorEvents.swift Sources/CreatorSketchEditor/SketchEditorModel+Status.swift Sources/CreatorSketchEditor/SketchEditorModel.swift Tests/CreatorSketchEditorTests/SketchEditorModelTests.swift Tests/CreatorSketchEditorTests/Support/SketchFixtures.swift
git commit -m "feat(sketch-editor): add CreatorSketchEditor with SketchEditorModel's live solve and commits"
```


---

### Task 5: The sketch as a viewport overlay

`SketchOverlayBuilder` draws each entity on the sketch plane in its role: selected, then hovered, then conflicting, construction (dashed), projected, then fixed or free (sketcher spec §8's table); points as 6-point knobs; arcs and circles as 72-segments-per-turn polylines; the tool's rubber band as `.preview`; and the plane's grid. The model gains `selection`, `hovered` and `preview` (set by later tasks) and `overlay`. `reload` drops selection and hover of entities that no longer exist.

**Files:**
- Create: `Sources/CreatorSketchEditor/EditorGeometry.swift`
- Create: `Sources/CreatorSketchEditor/PreviewCurve.swift`
- Create: `Sources/CreatorSketchEditor/SketchEditorModel+Overlay.swift`
- Modify: `Sources/CreatorSketchEditor/SketchEditorModel.swift`
- Create: `Sources/CreatorSketchEditor/SketchOverlayBuilder.swift`
- Create: `Sources/CreatorSketchEditor/SketchPreview.swift`
- Create: `Tests/CreatorSketchEditorTests/SketchOverlayTests.swift`

**Interfaces:**
- Consumes: `SketchEditorModel` (Task 4), `ViewportOverlay`/`OverlayLine`/`OverlayPoint`/`OverlayTint` (Task 3), `SketchSolution.freedom`, `Sketch.position(of:)`/`radius(of:)`.
- Produces: `SketchEditorModel.selection: Set<SketchEntityID>`, `hovered: SketchEntityID?`, `preview: SketchPreview`, `overlay: ViewportOverlay`; `public struct SketchPreview { curves: [PreviewCurve]; points: [Vector2]; static none }`; `public enum PreviewCurve { line(Vector2, Vector2), circle(center:radius:), arc(center:start:end:) }`; internal `EditorGeometry` (`arcPoints`, `circlePoints`, `distance(from:toSegment:_:)`, `distance(from:toPolyline:)`, `segmentsPerTurn = 72`) and `SketchOverlayBuilder.position/polyline(of:sketch:solution:id:)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorSketchEditorTests/SketchOverlayTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// The sketch drawn over the viewport (sketcher spec §8's colour table): freedom colours, construction dashed, the
/// selection and hover over them, the rubber band, and the plane grid, all on the sketch's plane.
@MainActor
struct SketchOverlayTests {
    func tints(_ overlay: ViewportOverlay) -> Set<OverlayTint> { Set(overlay.lines.map(\.tint) + overlay.points.map(\.tint)) }

    @Test func aFullyConstrainedRectangleIsDrawnFixedOnItsPlane() {
        let model = SketchEditorModel(sketch: RectangleSketch().sketch, plane: .xz)
        let overlay = model.overlay
        #expect(overlay.lines.count == 4 && overlay.points.count == 4)
        #expect(tints(overlay) == [.fullyConstrained])
        #expect(overlay.gridPlane == .xz, "the plane grid replaces the ground grid")
        #expect(overlay.lines.allSatisfy { abs($0.a.y) < 1e-9 && abs($0.b.y) < 1e-9 }, "XZ: plane y is world z")
        #expect(overlay.lines.contains { abs($0.a.z - 40) < 1e-9 && abs($0.b.z - 40) < 1e-9 }, "the top edge is at z 40")
    }

    @Test func freeGeometryIsUnderConstrainedAndConflictsAreRed() {
        let free = SketchEditorModel(sketch: RectangleSketch(dimensioned: false).sketch, plane: .xy)
        #expect(tints(free.overlay).contains(.underConstrained))
        var conflicting = RectangleSketch()
        conflicting.sketch.add(.vertical(conflicting.lines[0]))
        let model = SketchEditorModel(sketch: conflicting.sketch, plane: .xy)
        #expect(model.overlay.lines.contains { $0.tint == .conflicting })
    }

    @Test func constructionIsDashedInItsOwnColour() throws {
        var sketch = Sketch()
        sketch.addLine(Vector2(0, 0), Vector2(10, 0), isConstruction: true)
        let line = try #require(SketchEditorModel(sketch: sketch, plane: .xy).overlay.lines.first)
        #expect(line.isDashed && line.tint == .construction)
    }

    @Test func theSelectionAndTheHoveredEntityAreDrawnOverTheirFreedom() {
        let rectangle = RectangleSketch()
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        model.selection = [rectangle.lines[0]]
        model.hovered = rectangle.corners[2]
        let overlay = model.overlay
        #expect(overlay.lines.filter { $0.tint == .selected }.count == 1)
        #expect(overlay.lines.first { $0.tint == .selected }?.width == SketchOverlayBuilder.selectedWidth)
        #expect(overlay.points.filter { $0.tint == .hovered }.count == 1)
    }

    @Test func circlesAndArcsAreSmoothPolylines() {
        var sketch = Sketch()
        sketch.addCircle(center: Vector2(0, 0), radius: 5)
        let centre = sketch.addPoint(Vector2(20, 0))
        let start = sketch.addPoint(Vector2(25, 0))
        let end = sketch.addPoint(Vector2(20, 5))
        sketch.addArc(center: centre, start: start, end: end)
        let overlay = SketchEditorModel(sketch: sketch, plane: .xy).overlay
        let circle = overlay.lines.filter { $0.a.x < 10 }
        #expect(circle.count == EditorGeometry.segmentsPerTurn)
        #expect(circle.allSatisfy { abs(Vector2($0.a.x, $0.a.y).length - 5) < 1e-9 })
        let arc = overlay.lines.filter { $0.a.x >= 10 }
        #expect(arc.count == EditorGeometry.segmentsPerTurn / 4, "a quarter turn")
    }

    @Test func theRubberBandIsDrawnFaded() {
        let model = SketchEditorModel(sketch: Sketch(), plane: .xy)
        model.preview = SketchPreview(curves: [.line(Vector2(0, 0), Vector2(5, 5))], points: [Vector2(0, 0)])
        let overlay = model.overlay
        #expect(overlay.lines.map(\.tint) == [.preview] && overlay.points.map(\.tint) == [.preview])
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter CreatorSketchEditorTests`

Expected: FAIL — the build fails: "value of type 'SketchEditorModel' has no member 'overlay'".

- [ ] **Step 3: Build the overlay**

Create `Sources/CreatorSketchEditor/EditorGeometry.swift`:

```swift
import CreatorGeometry
import Foundation

/// The editor's 2D helpers: polylines for drawing curves, and distances for picking them.
enum EditorGeometry {
    /// Segments per full turn when a circle or an arc is drawn as a polyline.
    static let segmentsPerTurn = 72

    /// The polar angle of `v`, in (−π, π].
    static func angle(_ v: Vector2) -> Double { atan2(v.y, v.x) }

    /// `angle` wrapped into [0, 2π).
    static func wrapped(_ angle: Double) -> Double {
        let turn = 2 * Double.pi
        let value = angle.truncatingRemainder(dividingBy: turn)
        return value < 0 ? value + turn : value
    }

    /// The counter-clockwise sweep from `start` to the ray through `end` around `center`, in (0, 2π]; a full turn
    /// when the two rays coincide.
    static func sweep(center: Vector2, start: Vector2, end: Vector2) -> Double {
        let raw = wrapped(angle(end - center) - angle(start - center))
        return raw > 1e-12 ? raw : 2 * .pi
    }

    /// The arc as a polyline from `start`, counter-clockwise, ending on the ray through `end` at `start`'s radius.
    static func arcPoints(center: Vector2, start: Vector2, end: Vector2) -> [Vector2] {
        let radius = (start - center).length
        let from = angle(start - center)
        let sweep = sweep(center: center, start: start, end: end)
        let count = max(2, Int((sweep / (2 * .pi) * Double(segmentsPerTurn)).rounded(.up)))
        return (0...count).map { step in
            let at = from + sweep * Double(step) / Double(count)
            return center + Vector2(cos(at), sin(at)) * radius
        }
    }

    /// The circle as a closed polyline (its first point repeated at the end).
    static func circlePoints(center: Vector2, radius: Double) -> [Vector2] {
        (0...segmentsPerTurn).map { step in
            let at = 2 * Double.pi * Double(step) / Double(segmentsPerTurn)
            return center + Vector2(cos(at), sin(at)) * radius
        }
    }

    /// The distance from `p` to the segment `a`–`b`.
    static func distance(from p: Vector2, toSegment a: Vector2, _ b: Vector2) -> Double {
        let d = b - a
        let squared = d.x * d.x + d.y * d.y
        guard squared > 0 else { return (p - a).length }
        let t = min(max(((p.x - a.x) * d.x + (p.y - a.y) * d.y) / squared, 0), 1)
        return (p - (a + d * t)).length
    }

    /// The distance from `p` to a polyline.
    static func distance(from p: Vector2, toPolyline points: [Vector2]) -> Double {
        zip(points, points.dropFirst()).map { distance(from: p, toSegment: $0, $1) }.min() ?? .infinity
    }
}
```

Create `Sources/CreatorSketchEditor/PreviewCurve.swift`:

```swift
import CreatorGeometry

/// A curve a tool is about to draw, in plane coordinates (the rubber band).
public enum PreviewCurve: Hashable, Sendable {
    case line(Vector2, Vector2)
    case circle(center: Vector2, radius: Double)
    /// Counter-clockwise from `start` around `center` to the ray through `end`, as `Sketch.addArc` draws it.
    case arc(center: Vector2, start: Vector2, end: Vector2)
}
```

Create `Sources/CreatorSketchEditor/SketchEditorModel+Overlay.swift`:

```swift
import CreatorViewport

extension SketchEditorModel {
    /// What the viewport draws while this sketch is edited (`ViewportModel.showOverlay(_:)`).
    public var overlay: ViewportOverlay {
        SketchOverlayBuilder.overlay(sketch: sketch, solution: solution, plane: plane, selection: selection, hovered: hovered,
                                     preview: preview)
    }
}
```

Modify `Sources/CreatorSketchEditor/SketchEditorModel.swift` (apply this diff):

```diff
--- a/Sources/CreatorSketchEditor/SketchEditorModel.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel.swift
@@ -19,6 +19,12 @@ public final class SketchEditorModel {
     public private(set) var solution: SketchSolution
     /// A plain-language reason the last command was refused, until the next edit or tool change.
     public internal(set) var refusal: String?
+    /// The selected entities (drawn in the selection colour; constraints and dimensions apply to them).
+    public internal(set) var selection: Set<SketchEntityID> = []
+    /// The entity under the pointer, if any.
+    public internal(set) var hovered: SketchEntityID?
+    /// The active tool's rubber band.
+    public internal(set) var preview = SketchPreview.none
 
     @ObservationIgnored public var events = SketchEditorEvents()
 
@@ -36,6 +42,8 @@ public final class SketchEditorModel {
         let solved = SketchSolver.solve(stored)
         solution = solved
         sketch = Self.remembering(stored, solved)
+        selection = selection.filter { sketch.entities[$0] != nil }
+        if let hovered, sketch.entities[hovered] == nil { self.hovered = nil }
     }
 
     /// Takes `edited` as the sketch, solved and remembered, and hands it to the host as one undo step.
```

Create `Sources/CreatorSketchEditor/SketchOverlayBuilder.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Foundation

/// Draws a sketch as a viewport overlay on its plane (sketcher spec §8's colours): each curve and point in its
/// freedom's colour, construction dashed in its own, projected edges in theirs, the selection and the hovered entity
/// over everything, then the tool's rubber band, with the plane's grid underneath. Pure.
enum SketchOverlayBuilder {
    /// Curve and point sizes, in points.
    static let curveWidth = 1.5
    static let selectedWidth = 2.5
    static let pointSize = 6.0

    static func overlay(sketch: Sketch, solution: SketchSolution, plane: Plane, selection: Set<SketchEntityID>,
                        hovered: SketchEntityID?, preview: SketchPreview) -> ViewportOverlay {
        var lines: [OverlayLine] = []
        var points: [OverlayPoint] = []
        for id in sketch.entityIDs {
            guard let entity = sketch.entities[id] else { continue }
            let tint = tint(of: id, entity, solution: solution, selection: selection, hovered: hovered)
            let width = tint == .selected || tint == .hovered ? selectedWidth : curveWidth
            if case .point = entity.kind {
                if let at = position(id, sketch, solution) { points.append(OverlayPoint(plane.point(at), tint: tint, size: pointSize)) }
                continue
            }
            let polyline = self.polyline(of: entity.kind, sketch: sketch, solution: solution, id: id)
            lines += segments(polyline, on: plane, tint: tint, width: width, dashed: entity.isConstruction)
        }
        for curve in preview.curves {
            lines += segments(polyline(of: curve), on: plane, tint: .preview, width: curveWidth, dashed: false)
        }
        points += preview.points.map { OverlayPoint(plane.point($0), tint: .preview, size: pointSize) }
        return ViewportOverlay(lines: lines, points: points, gridPlane: plane)
    }

    /// The colour role of one entity: selected, then hovered, then conflicting, construction, projected, then free or
    /// fixed.
    static func tint(of id: SketchEntityID, _ entity: SketchEntity, solution: SketchSolution, selection: Set<SketchEntityID>,
                     hovered: SketchEntityID?) -> OverlayTint {
        if selection.contains(id) { return .selected }
        if hovered == id { return .hovered }
        let freedom = solution.freedom[id] ?? .free
        if freedom == .conflicting { return .conflicting }
        if entity.isConstruction { return .construction }
        if case .projected = entity.kind { return .projected }
        return freedom == .fixed ? .fullyConstrained : .underConstrained
    }

    /// A point's solved position, else its stored one.
    static func position(_ id: SketchEntityID, _ sketch: Sketch, _ solution: SketchSolution) -> Vector2? {
        solution.points[id] ?? sketch.position(of: id)
    }

    /// A curve entity as a polyline in plane coordinates, at its solved positions; empty for a curve whose points are
    /// missing.
    static func polyline(of kind: SketchEntityKind, sketch: Sketch, solution: SketchSolution, id: SketchEntityID) -> [Vector2] {
        let at = { (point: SketchEntityID) in position(point, sketch, solution) }
        switch kind {
        case .point:
            return []
        case .line(let start, let end):
            guard let a = at(start), let b = at(end) else { return [] }
            return [a, b]
        case .arc(let center, let start, let end):
            guard let c = at(center), let s = at(start), let e = at(end) else { return [] }
            return EditorGeometry.arcPoints(center: c, start: s, end: e)
        case .circle(let center, _):
            guard let c = at(center), let radius = solution.radii[id] ?? sketch.radius(of: id) else { return [] }
            return EditorGeometry.circlePoints(center: c, radius: radius)
        case .projected(let source):
            return polyline(of: source.curve)
        }
    }

    static func polyline(of curve: ProjectedCurve) -> [Vector2] {
        switch curve {
        case .line(let a, let b):
            return [a, b]
        case .circle(let center, let radius):
            return EditorGeometry.circlePoints(center: center, radius: radius)
        case .arc(let center, let radius, let start, let end):
            let from = center + Vector2(cos(start.radians), sin(start.radians)) * radius
            let to = center + Vector2(cos(end.radians), sin(end.radians)) * radius
            return EditorGeometry.arcPoints(center: center, start: from, end: to)
        }
    }

    static func polyline(of curve: PreviewCurve) -> [Vector2] {
        switch curve {
        case .line(let a, let b): [a, b]
        case .circle(let center, let radius): EditorGeometry.circlePoints(center: center, radius: radius)
        case .arc(let center, let start, let end): EditorGeometry.arcPoints(center: center, start: start, end: end)
        }
    }

    static func segments(_ polyline: [Vector2], on plane: Plane, tint: OverlayTint, width: Double, dashed: Bool) -> [OverlayLine] {
        zip(polyline, polyline.dropFirst()).map { a, b in
            OverlayLine(plane.point(a), plane.point(b), tint: tint, width: width, isDashed: dashed)
        }
    }
}
```

Create `Sources/CreatorSketchEditor/SketchPreview.swift`:

```swift
import CreatorGeometry

/// What the active tool shows before it commits: its rubber-band curves and the points it has placed, in plane
/// coordinates. Empty when nothing is in progress.
public struct SketchPreview: Hashable, Sendable {
    public var curves: [PreviewCurve]
    public var points: [Vector2]

    public init(curves: [PreviewCurve] = [], points: [Vector2] = []) {
        self.curves = curves
        self.points = points
    }

    public static let none = SketchPreview()
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CreatorSketchEditorTests`

Expected: PASS (exit 0, no line says "recorded an issue" or "failed after").

- [ ] **Step 5: Full verification**

Run, from the repo root: `swift build --build-tests 2>&1 | grep -E "(error|warning):" | grep -v "ld: warning"` (expected: nothing new; master's one test warning, `ContextMenuTests.swift:96` "'underPointer' mutated after capture", shows only when that file recompiles), then `swift test` (expected: exit 0, no "recorded an issue" / "failed after" lines, and the "Test run with N tests" lines sum to **1115 (master + 30)**), then `swiftlint lint --strict` (zero violations).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorSketchEditor/EditorGeometry.swift Sources/CreatorSketchEditor/PreviewCurve.swift Sources/CreatorSketchEditor/SketchEditorModel+Overlay.swift Sources/CreatorSketchEditor/SketchEditorModel.swift Sources/CreatorSketchEditor/SketchOverlayBuilder.swift Sources/CreatorSketchEditor/SketchPreview.swift Tests/CreatorSketchEditorTests/SketchOverlayTests.swift
git commit -m "feat(sketch-editor): draw the sketch as a viewport overlay in its freedom colours"
```


---

### Task 6: Drawing tools and inference; the editor as the viewport's tool

Line chains from click to click; Circle takes a centre and a radius point; Arc takes centre, start, then an end placed on the start's radius; Point places a lone point. A click within the pick radius (8 points, in plane mm at the current zoom) of a point shares it (coincident by construction); a line's end within it of its start's height or x snaps horizontal or vertical and adds that constraint; ⌘ suppresses inference (on drags only until gap S5-a). X toggles construction for new geometry, or for the selection. Esc ends the stroke, else finishes; ⏎ finishes. The model conforms to `ViewportTool` (screen → plane through the projector) and claims every click, so the model behind the sketch is never selected. The default tool is Line.

**Files:**
- Create: `Sources/CreatorSketchEditor/DrawState.swift`
- Create: `Sources/CreatorSketchEditor/LineInference.swift`
- Create: `Sources/CreatorSketchEditor/SketchAnchor.swift`
- Create: `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`
- Create: `Sources/CreatorSketchEditor/SketchEditorModel+ViewportTool.swift`
- Modify: `Sources/CreatorSketchEditor/SketchEditorModel.swift`
- Create: `Sources/CreatorSketchEditor/SketchPicker.swift`
- Create: `Sources/CreatorSketchEditor/SketchTool.swift`
- Create: `Tests/CreatorSketchEditorTests/DrawingTests.swift`

**Interfaces:**
- Consumes: `ViewportTool`/`ViewportProjector`/`ViewportModifiers` (Task 2), `SketchEditorModel.commit` (Task 4), `preview`/`hovered` (Task 5), `Sketch.addPoint/addLine/addArc/addCircle/add(_:)`.
- Produces: `public enum SketchTool: CaseIterable { select, line, arc, circle, point, dimension; title }`; `SketchEditorModel.tool`, `isConstruction`, `choose(_:)`, `toggleConstruction()`, `escape()`, `finish()`, `static pickRadius = 8.0`; internal `click(at: Vector2, tolerance: Double, modifiers: ViewportModifiers)`, `hover(at: Vector2?, tolerance:modifiers:)`, `anchor(at:tolerance:)`, `drawState: DrawState`, `tolerance(_ projector:)`; `SketchPicker { point(near:tolerance:excluding:), curve(near:tolerance:), entity(near:tolerance:) }`; `SketchAnchor`, `LineInference`, `DrawState`; `extension SketchEditorModel: ViewportTool` (drags declined until Task 7). `reload` resets the stroke.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorSketchEditorTests/DrawingTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// Drawing (sketcher spec §8): lines chain from click to click and infer horizontal and vertical (⌘ suppresses it),
/// clicks snap onto existing points (shared, so coincidence is structural), circles and arcs, points, construction,
/// Esc and ⏎. Each finished curve is one commit.
@MainActor
struct DrawingTests {
    func makeModel(_ sketch: Sketch = Sketch()) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        return (model, RecordingHost(model))
    }

    func lines(_ sketch: Sketch) -> [(start: SketchEntityID, end: SketchEntityID)] {
        sketch.entityIDs.compactMap { id in
            if case .line(let start, let end)? = sketch.entities[id]?.kind { return (start, end) }
            return nil
        }
    }

    @Test func linesChainAndInferHorizontalAndVertical() throws {
        let (model, host) = makeModel()
        model.choose(.line)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty, "the first click only starts the chain")
        model.click(at: Vector2(20, 0.4), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20.5, 15), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Line", "Line"])
        let sketch = model.sketch
        let drawn = lines(sketch)
        #expect(drawn.count == 2 && drawn[0].end == drawn[1].start, "the chain shares its points")
        #expect(sketch.position(of: drawn[0].end) == Vector2(20, 0), "snapped onto the horizontal")
        let constraints = sketch.constraintIDs.compactMap { sketch.constraints[$0] }
        #expect(constraints.contains { if case .horizontal = $0 { true } else { false } })
        #expect(constraints.contains { if case .vertical = $0 { true } else { false } })
    }

    @Test func commandSuppressesInference() {
        let (model, _) = makeModel()
        model.choose(.line)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20, 0.4), tolerance: 1, modifiers: .command)
        #expect(model.sketch.constraints.isEmpty)
        #expect(model.sketch.position(of: lines(model.sketch)[0].end) == Vector2(20, 0.4))
    }

    @Test func aClickNearAPointSharesItAndClosesTheLoop() {
        let (model, _) = makeModel()
        model.choose(.line)
        for corner in [Vector2(0, 0), Vector2(30, 0), Vector2(30, 20), Vector2(0, 20), Vector2(0.3, 0.2)] {
            model.click(at: corner, tolerance: 1, modifiers: [])
        }
        let drawn = lines(model.sketch)
        #expect(drawn.count == 4)
        #expect(drawn[3].end == drawn[0].start, "the last line ends on the first point")
        #expect(model.sketch.entities.count == 8, "four points, four lines")
    }

    @Test func escapeEndsTheChainThenFinishes() {
        let (model, host) = makeModel()
        model.choose(.line)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        model.hover(at: Vector2(10, 10), tolerance: 1, modifiers: [])
        #expect(model.preview.curves == [.line(Vector2(0, 0), Vector2(10, 10))], "the rubber band follows the pointer")
        model.escape()
        #expect(model.preview == .none && host.finishes == 0)
        model.click(at: Vector2(5, 5), tolerance: 1, modifiers: [])
        model.escape()
        model.escape()
        #expect(host.finishes == 1)
        #expect(host.commits.isEmpty)
    }

    @Test func circlesTakeACentreAndARadius() throws {
        let (model, host) = makeModel()
        model.choose(.circle)
        model.click(at: Vector2(10, 10), tolerance: 1, modifiers: [])
        model.click(at: Vector2(13, 14), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Circle"])
        let circles = model.sketch.entityIDs.filter { id in
            if case .circle? = model.sketch.entities[id]?.kind { return true }
            return false
        }
        let circle = try #require(circles.first)
        #expect(abs((model.sketch.radius(of: circle) ?? 0) - 5) < 1e-9)
    }

    @Test func arcsTakeACentreAStartAndAnEndOnTheStartsRadius() throws {
        let (model, host) = makeModel()
        model.choose(.arc)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(10, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(0, 3), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Arc"])
        let sketch = model.sketch
        let ends = sketch.entityIDs.compactMap { id -> SketchEntityID? in
            if case .arc(_, _, let end)? = sketch.entities[id]?.kind { return end }
            return nil
        }
        let end = try #require(ends.first.flatMap { sketch.position(of: $0) })
        #expect(abs(end.x) < 1e-9 && abs(end.y - 10) < 1e-9)
    }

    @Test func pointsGoWhereNoPointIs() {
        let (model, host) = makeModel()
        model.choose(.point)
        model.click(at: Vector2(1, 1), tolerance: 1, modifiers: [])
        model.click(at: Vector2(1.2, 1.1), tolerance: 1, modifiers: [])
        #expect(host.commits.count == 1 && model.sketch.entities.count == 1)
    }

    @Test func constructionAppliesToNewGeometryAndToTheSelection() throws {
        let (model, host) = makeModel()
        model.toggleConstruction()
        model.choose(.line)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(10, 5), tolerance: 1, modifiers: [])
        let line = try #require(model.sketch.entityIDs.last)
        #expect(model.sketch.entities[line]?.isConstruction == true)
        model.selection = [line]
        model.toggleConstruction()
        #expect(model.sketch.entities[line]?.isConstruction == false)
        #expect(host.commits.last?.description == "Make Normal Geometry")
    }

    @Test func viewportClicksLandOnThePlane() {
        let (model, host) = makeModel()
        model.choose(.point)
        let projector = ViewportProjector(pose: CameraPose(target: Vector3(5, 5, 0), distance: 100, pitch: .pi / 2,
                                                           projection: .orthographic),
                                          size: ViewportSize(width: 400, height: 300))
        #expect(model.clicked(at: ScreenPoint(200, 150), modifiers: [], projector: projector), "every click is the editor's")
        let point = model.sketch.entityIDs.first.flatMap { model.sketch.position(of: $0) }
        #expect(point.map { abs($0.x - 5) < 1e-9 && abs($0.y - 5) < 1e-9 } == true)
        #expect(host.commits.count == 1)
    }

    /// Review Focus 3: a double click draws nothing degenerate and stores nothing.
    @Test func clickingTheSameSpotTwiceDrawsNothing() {
        let (model, host) = makeModel()
        model.choose(.line)
        model.click(at: Vector2(3, 3), tolerance: 1, modifiers: [])
        model.click(at: Vector2(3, 3), tolerance: 1, modifiers: [])
        model.choose(.circle)
        model.click(at: Vector2(9, 9), tolerance: 1, modifiers: [])
        model.click(at: Vector2(9, 9), tolerance: 1, modifiers: [])
        model.choose(.arc)
        model.click(at: Vector2(20, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20, 0), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty && model.sketch.entities.isEmpty)
    }

    /// Review Focus 4: with the plane seen edge-on there is no point under the pointer; the click is still the
    /// editor's, so nothing behind the sketch is selected, and nothing is drawn.
    @Test func aClickOffThePlaneIsClaimedButDrawsNothing() {
        let (model, host) = makeModel()
        model.choose(.point)
        let edgeOn = ViewportProjector(pose: CameraPose(distance: 100, pitch: 0, projection: .orthographic),
                                       size: ViewportSize(width: 400, height: 300))
        #expect(model.clicked(at: ScreenPoint(200, 150), modifiers: [], projector: edgeOn))
        model.pointerMoved(to: ScreenPoint(210, 150), projector: edgeOn)
        #expect(host.commits.isEmpty && model.preview == .none)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter CreatorSketchEditorTests`

Expected: FAIL — the build fails: "value of type 'SketchEditorModel' has no member 'choose'".

- [ ] **Step 3: Add the tools**

Create `Sources/CreatorSketchEditor/DrawState.swift`:

```swift
/// What a drawing tool has placed so far (`SketchEditorModel`'s in-progress stroke).
enum DrawState: Hashable, Sendable {
    case idle
    /// A line's start; after each line the chain goes on from its end.
    case lineFrom(SketchAnchor)
    case circleAround(SketchAnchor)
    case arcAround(SketchAnchor)
    case arcFrom(center: SketchAnchor, start: SketchAnchor)
}
```

Create `Sources/CreatorSketchEditor/LineInference.swift`:

```swift
import CreatorGeometry
import CreatorSketch

/// The constraint a line's end infers from its start (sketcher spec §8): horizontal when the end is within the
/// tolerance of the start's height, else vertical when it's within it of the start's x. The end is snapped onto it.
enum LineInference: Hashable, Sendable {
    case horizontal
    case vertical

    /// The inference for a line from `start` to `end`, and the end it snaps to; none when ⌘ suppresses it.
    static func infer(from start: Vector2, to end: Vector2, tolerance: Double, suppressed: Bool) -> (LineInference?, Vector2) {
        guard !suppressed, (end - start).length > tolerance else { return (nil, end) }
        if abs(end.y - start.y) <= tolerance { return (.horizontal, Vector2(end.x, start.y)) }
        if abs(end.x - start.x) <= tolerance { return (.vertical, Vector2(start.x, end.y)) }
        return (nil, end)
    }

    func constraint(on line: SketchEntityID) -> SketchConstraint {
        switch self {
        case .horizontal: .horizontal(line)
        case .vertical: .vertical(line)
        }
    }
}
```

Create `Sources/CreatorSketchEditor/SketchAnchor.swift`:

```swift
import CreatorGeometry
import CreatorSketch

/// Where a tool's click lands: on an existing point (shared, so the new curve is coincident with it structurally,
/// spec §3), or at a new position.
enum SketchAnchor: Hashable, Sendable {
    case existing(SketchEntityID, at: Vector2)
    case free(Vector2)

    var position: Vector2 {
        switch self {
        case .existing(_, let at), .free(let at): at
        }
    }

    var point: SketchEntityID? {
        if case .existing(let id, _) = self { return id }
        return nil
    }

    /// The anchor's point in `sketch`: the existing one, or a new one at its position.
    func point(in sketch: inout Sketch, isConstruction: Bool = false) -> SketchEntityID {
        switch self {
        case .existing(let id, _): id
        case .free(let at): sketch.addPoint(at, isConstruction: isConstruction)
        }
    }
}
```

Create `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import CreatorViewport

extension SketchEditorModel {
    /// Points within this many points of the pointer are picked and snapped to (sketcher spec §8: "a few pixels").
    public static let pickRadius = 8.0

    /// Picks a tool (the toolbar, or its key). What the old one had in progress is dropped.
    public func choose(_ newTool: SketchTool) {
        tool = newTool
        drawState = .idle
        preview = .none
        refusal = nil
    }

    /// X (sketcher spec §8): with a selection, turns it into construction geometry, or back when it all is already;
    /// with none, toggles whether new geometry is construction.
    public func toggleConstruction() {
        guard !selection.isEmpty else {
            isConstruction.toggle()
            return
        }
        let makeConstruction = selection.contains { sketch.entities[$0]?.isConstruction == false }
        var edited = sketch
        for id in selection.sorted() { edited.entities[id]?.isConstruction = makeConstruction }
        commit(edited, makeConstruction ? "Make Construction" : "Make Normal Geometry")
    }

    /// Esc: ends the stroke in progress, or with none, finishes the sketch.
    public func escape() {
        if drawState != .idle {
            drawState = .idle
            preview = .none
        } else {
            finish()
        }
    }

    /// ⏎ or the Finish button: leaves sketch mode (the host does), dropping any stroke in progress.
    public func finish() {
        drawState = .idle
        preview = .none
        events.finished()
    }

    /// A click at `p` (plane coordinates) with `tolerance` mm of slack, for the active tool. ⌘ suppresses inference
    /// (sketcher spec §8).
    func click(at p: Vector2, tolerance: Double, modifiers: ViewportModifiers) {
        refusal = nil
        switch tool {
        case .select, .dimension: break
        case .point: placePoint(at: p, tolerance: tolerance)
        case .line: placeLinePoint(at: p, tolerance: tolerance, suppressed: modifiers.contains(.command))
        case .circle: placeCirclePoint(at: p, tolerance: tolerance)
        case .arc: placeArcPoint(at: p, tolerance: tolerance)
        }
        hover(at: p, tolerance: tolerance, modifiers: modifiers)
    }

    /// The pointer moved to `p` (`nil`: off the view, or off the plane): the hovered entity and the rubber band follow.
    func hover(at p: Vector2?, tolerance: Double, modifiers: ViewportModifiers) {
        guard let p else {
            hovered = nil
            preview = .none
            return
        }
        let picker = SketchPicker(sketch: sketch, solution: solution)
        let under = picker.entity(near: p, tolerance: tolerance)
        if hovered != under { hovered = under }
        let next = rubberBand(to: p, tolerance: tolerance, suppressed: modifiers.contains(.command))
        if preview != next { preview = next }
    }

    /// Where a click at `p` lands: the nearest existing point within `tolerance`, else `p` itself.
    func anchor(at p: Vector2, tolerance: Double) -> SketchAnchor {
        let picker = SketchPicker(sketch: sketch, solution: solution)
        guard let hit = picker.point(near: p, tolerance: tolerance) else { return .free(p) }
        return .existing(hit.id, at: hit.at)
    }

    private func placePoint(at p: Vector2, tolerance: Double) {
        guard case .free(let at) = anchor(at: p, tolerance: tolerance) else { return }
        var edited = sketch
        edited.addPoint(at, isConstruction: isConstruction)
        commit(edited, "Point")
    }

    /// The first click starts a chain; each later one ends a line there and starts the next from its end.
    private func placeLinePoint(at p: Vector2, tolerance: Double, suppressed: Bool) {
        guard case .lineFrom(let start) = drawState else {
            drawState = .lineFrom(anchor(at: p, tolerance: tolerance))
            return
        }
        var end = anchor(at: p, tolerance: tolerance)
        if end.point != nil, end.point == start.point { return }
        var inference: LineInference?
        if case .free(let at) = end {
            let inferred = LineInference.infer(from: start.position, to: at, tolerance: tolerance, suppressed: suppressed)
            inference = inferred.0
            end = .free(inferred.1)
        }
        guard (end.position - start.position).length > 1e-9 else { return }
        var edited = sketch
        let a = start.point(in: &edited)
        let b = end.point(in: &edited)
        let line = edited.addLine(from: a, to: b, isConstruction: isConstruction)
        if let inference { edited.add(inference.constraint(on: line)) }
        commit(edited, "Line")
        drawState = .lineFrom(.existing(b, at: end.position))
    }

    private func placeCirclePoint(at p: Vector2, tolerance: Double) {
        guard case .circleAround(let center) = drawState else {
            drawState = .circleAround(anchor(at: p, tolerance: tolerance))
            return
        }
        let radius = (anchor(at: p, tolerance: tolerance).position - center.position).length
        guard radius > 1e-9 else { return }
        var edited = sketch
        edited.addCircle(center: center.point(in: &edited), radius: radius, isConstruction: isConstruction)
        commit(edited, "Circle")
        drawState = .idle
    }

    /// Centre, start, then end: the end lands on the start's radius, along the ray through the click.
    private func placeArcPoint(at p: Vector2, tolerance: Double) {
        switch drawState {
        case .arcAround(let center):
            let start = anchor(at: p, tolerance: tolerance)
            guard (start.position - center.position).length > 1e-9 else { return }
            drawState = .arcFrom(center: center, start: start)
        case .arcFrom(let center, let start):
            let end = arcEnd(center: center.position, start: start.position, toward: anchor(at: p, tolerance: tolerance))
            guard let end, end.point == nil || end.point != start.point else { return }
            var edited = sketch
            let c = center.point(in: &edited)
            let s = start.point(in: &edited)
            let e = end.point(in: &edited)
            edited.addArc(center: c, start: s, end: e, isConstruction: isConstruction)
            commit(edited, "Arc")
            drawState = .idle
        default:
            drawState = .arcAround(anchor(at: p, tolerance: tolerance))
        }
    }

    /// An arc's end: an existing point as it is, else the click moved onto the start's radius; `nil` on the centre.
    private func arcEnd(center: Vector2, start: Vector2, toward target: SketchAnchor) -> SketchAnchor? {
        if target.point != nil { return target }
        let ray = target.position - center
        let length = ray.length
        guard length > 1e-9 else { return nil }
        return .free(center + ray * ((start - center).length / length))
    }

    /// The rubber band from what's placed to `p`.
    private func rubberBand(to p: Vector2, tolerance: Double, suppressed: Bool) -> SketchPreview {
        let target = anchor(at: p, tolerance: tolerance)
        switch drawState {
        case .idle:
            return tool == .select || tool == .dimension ? .none : SketchPreview(points: [target.position])
        case .lineFrom(let start):
            var end = target.position
            if target.point == nil {
                end = LineInference.infer(from: start.position, to: end, tolerance: tolerance, suppressed: suppressed).1
            }
            return SketchPreview(curves: [.line(start.position, end)], points: [start.position, end])
        case .circleAround(let center):
            return SketchPreview(curves: [.circle(center: center.position, radius: (target.position - center.position).length)],
                                 points: [center.position])
        case .arcAround(let center):
            return SketchPreview(curves: [.line(center.position, target.position)], points: [center.position])
        case .arcFrom(let center, let start):
            guard let end = arcEnd(center: center.position, start: start.position, toward: target) else {
                return SketchPreview(points: [center.position, start.position])
            }
            return SketchPreview(curves: [.arc(center: center.position, start: start.position, end: end.position)],
                                 points: [center.position, start.position, end.position])
        }
    }
}
```

Create `Sources/CreatorSketchEditor/SketchEditorModel+ViewportTool.swift`:

```swift
import CreatorGeometry
import CreatorViewport

/// The viewport's primary input, mapped onto the sketch plane (sketcher spec §8: "intersect the cursor ray with the
/// plane, then take the nearest entity within a few pixels"). The editor claims every click while it is the tool, so
/// a click never selects the model under the sketch.
extension SketchEditorModel: ViewportTool {
    /// `pickRadius` points in plane millimetres at the projector's zoom.
    func tolerance(_ projector: ViewportProjector) -> Double {
        Self.pickRadius * projector.millimetresPerPoint
    }

    public func pointerMoved(to point: ScreenPoint?, projector: ViewportProjector) {
        hover(at: point.flatMap { projector.planePoint(under: $0, on: plane) }, tolerance: tolerance(projector), modifiers: [])
    }

    public func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool {
        if let p = projector.planePoint(under: point, on: plane) {
            click(at: p, tolerance: tolerance(projector), modifiers: modifiers)
        }
        return true
    }

    public func dragBegan(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool {
        false
    }

    public func dragMoved(to point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {}

    public func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {}
}
```

Modify `Sources/CreatorSketchEditor/SketchEditorModel.swift` (apply this diff):

```diff
--- a/Sources/CreatorSketchEditor/SketchEditorModel.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel.swift
@@ -25,6 +25,12 @@ public final class SketchEditorModel {
     public internal(set) var hovered: SketchEntityID?
     /// The active tool's rubber band.
     public internal(set) var preview = SketchPreview.none
+    /// The active tool (`choose(_:)`).
+    public internal(set) var tool = SketchTool.line
+    /// Whether new geometry is construction geometry (X toggles it).
+    public internal(set) var isConstruction = false
+    /// What the drawing tool has placed so far.
+    var drawState = DrawState.idle
 
     @ObservationIgnored public var events = SketchEditorEvents()
 
@@ -44,6 +50,9 @@ public final class SketchEditorModel {
         sketch = Self.remembering(stored, solved)
         selection = selection.filter { sketch.entities[$0] != nil }
         if let hovered, sketch.entities[hovered] == nil { self.hovered = nil }
+        // A stroke may hold points the stored sketch no longer has.
+        drawState = .idle
+        preview = .none
     }
 
     /// Takes `edited` as the sketch, solved and remembered, and hands it to the host as one undo step.
```

Create `Sources/CreatorSketchEditor/SketchPicker.swift`:

```swift
import CreatorGeometry
import CreatorSketch

/// Picking on the CPU in plane coordinates (sketcher spec §8): the nearest point within the tolerance, else the
/// nearest curve within it. Points win so a line's endpoint can be picked where the line passes too.
struct SketchPicker {
    let sketch: Sketch
    let solution: SketchSolution

    /// The nearest point entity to `p` within `tolerance` mm, leaving out `excluding`.
    func point(near p: Vector2, tolerance: Double, excluding: Set<SketchEntityID> = []) -> (id: SketchEntityID, at: Vector2)? {
        var best: (id: SketchEntityID, at: Vector2, distance: Double)?
        for id in sketch.entityIDs where !excluding.contains(id) {
            guard case .point? = sketch.entities[id]?.kind,
                  let at = SketchOverlayBuilder.position(id, sketch, solution) else { continue }
            let distance = (at - p).length
            if distance <= tolerance, distance < (best?.distance ?? .infinity) { best = (id, at, distance) }
        }
        return best.map { ($0.id, $0.at) }
    }

    /// The nearest curve (line, arc, circle or projected edge) to `p` within `tolerance` mm.
    func curve(near p: Vector2, tolerance: Double) -> SketchEntityID? {
        var best: (id: SketchEntityID, distance: Double)?
        for id in sketch.entityIDs {
            guard let kind = sketch.entities[id]?.kind else { continue }
            if case .point = kind { continue }
            let polyline = SketchOverlayBuilder.polyline(of: kind, sketch: sketch, solution: solution, id: id)
            let distance = EditorGeometry.distance(from: p, toPolyline: polyline)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) { best = (id, distance) }
        }
        return best?.id
    }

    /// The entity a click at `p` picks: a point first, else a curve.
    func entity(near p: Vector2, tolerance: Double) -> SketchEntityID? {
        point(near: p, tolerance: tolerance)?.id ?? curve(near: p, tolerance: tolerance)
    }
}
```

Create `Sources/CreatorSketchEditor/SketchTool.swift`:

```swift
/// The sketch editor's tools (sketcher spec §8's toolbar). S5a has the drawing tools and Dimension; Trim, Fillet,
/// Mirror, Pattern and Project follow in S5b.
public enum SketchTool: Hashable, Sendable, CaseIterable {
    /// Click to select (⇧ adds), drag a point to move it.
    case select
    /// Lines chain from click to click (L).
    case line
    /// Centre, start, end (A).
    case arc
    /// Centre, then a point on the circle (C).
    case circle
    /// A lone point.
    case point
    /// Pick one or two entities; the kind of dimension follows from them (D).
    case dimension

    /// The toolbar's title.
    public var title: String {
        switch self {
        case .select: "Select"
        case .line: "Line"
        case .arc: "Arc"
        case .circle: "Circle"
        case .point: "Point"
        case .dimension: "Dimension"
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CreatorSketchEditorTests`

Expected: PASS (exit 0, no line says "recorded an issue" or "failed after").

- [ ] **Step 5: Full verification**

Run, from the repo root: `swift build --build-tests 2>&1 | grep -E "(error|warning):" | grep -v "ld: warning"` (expected: nothing new; master's one test warning, `ContextMenuTests.swift:96` "'underPointer' mutated after capture", shows only when that file recompiles), then `swift test` (expected: exit 0, no "recorded an issue" / "failed after" lines, and the "Test run with N tests" lines sum to **1126 (master + 41)**), then `swiftlint lint --strict` (zero violations).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorSketchEditor/DrawState.swift Sources/CreatorSketchEditor/LineInference.swift Sources/CreatorSketchEditor/SketchAnchor.swift Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift Sources/CreatorSketchEditor/SketchEditorModel+ViewportTool.swift Sources/CreatorSketchEditor/SketchEditorModel.swift Sources/CreatorSketchEditor/SketchPicker.swift Sources/CreatorSketchEditor/SketchTool.swift Tests/CreatorSketchEditorTests/DrawingTests.swift
git commit -m "feat(sketch-editor): draw lines, arcs, circles and points with horizontal/vertical/coincident inference"
```


---

### Task 7: Selection, constraint buttons, Delete and point drags

Select-tool clicks toggle the entity under the pointer (points win over the curves through them); a click on nothing clears. Additive clicks are a deliberate choice: two-entity constraints need no modifier, which MetalUI's taps don't report (gap S5-a). `availableConstraints` lists the constraint kinds the selection's shape fits (sketcher spec §3's table); `addConstraint(_:)` is one step and clears the selection, or says what to select. Delete removes the selection, what's built on it and its lone points, refusing to remove an exposed dimension. A plain drag starting on a point moves it: each step solves in drag mode and remembers (no commit); the release commits once ("Move Point"), so a drag is one undo step and downstream evaluation runs on pointer-up; a drag that moved nothing records nothing (Review Focus 2). Esc clears a selection before it finishes. `sketch` and `solution` become `internal(set)` for the drag.

**Files:**
- Create: `Sources/CreatorSketchEditor/SelectionShape.swift`
- Create: `Sources/CreatorSketchEditor/SketchConstraintKind.swift`
- Create: `Sources/CreatorSketchEditor/SketchEditorModel+Drag.swift`
- Modify: `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`
- Create: `Sources/CreatorSketchEditor/SketchEditorModel+Selection.swift`
- Modify: `Sources/CreatorSketchEditor/SketchEditorModel+ViewportTool.swift`
- Modify: `Sources/CreatorSketchEditor/SketchEditorModel.swift`
- Create: `Tests/CreatorSketchEditorTests/SelectionAndConstraintTests.swift`

**Interfaces:**
- Consumes: `SketchPicker` (Task 6), `SketchSolver.solve(_:dragging:)`, `Sketch.removeEntity/removeOrphanPoints/position(of:)`, `SketchEditorModel.remembering`.
- Produces: `public enum SketchConstraintKind: CaseIterable { coincident, pointOn, horizontal, vertical, parallel, perpendicular, tangent, equal, midpoint, concentric, symmetric, fix; title; hint }`; `SketchEditorModel.availableConstraints: [SketchConstraintKind]`, `addConstraint(_:)`, `deleteSelection()`; internal `select(at:tolerance:)`, `beginDrag(at:tolerance:) -> Bool`, `drag(to:)`, `endDrag(at: Vector2?)`, `dragged`, `dragOrigin`; `SelectionShape`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorSketchEditorTests/SelectionAndConstraintTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// Selecting (additive clicks, points before curves), the constraint buttons on the selection, Delete, and dragging
/// a point with the live solve (sketcher spec §8).
@MainActor
struct SelectionAndConstraintTests {
    func makeModel(_ sketch: Sketch) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(.select)
        return (model, RecordingHost(model))
    }

    @Test func clicksToggleTheSelectionAndPointsWinOverTheirCurves() {
        let rectangle = RectangleSketch()
        let (model, _) = makeModel(rectangle.sketch)
        model.click(at: Vector2(30, 0.5), tolerance: 1, modifiers: [])
        #expect(model.selection == [rectangle.lines[0]])
        model.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        #expect(model.selection == [rectangle.lines[0], rectangle.corners[0]], "a corner, not the lines through it")
        model.click(at: Vector2(30, 0.5), tolerance: 1, modifiers: [])
        #expect(model.selection == [rectangle.corners[0]], "a second click deselects")
        model.click(at: Vector2(30, 20), tolerance: 1, modifiers: [])
        #expect(model.selection.isEmpty, "a click on nothing clears it")
    }

    @Test func constraintButtonsFollowTheSelectionsShape() {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, _) = makeModel(rectangle.sketch)
        model.selection = [rectangle.lines[0], rectangle.lines[1]]
        #expect(Set(model.availableConstraints) == [.parallel, .perpendicular, .equal])
        model.selection = [rectangle.corners[0]]
        #expect(model.availableConstraints == [.fix])
        model.selection = [rectangle.corners[0], rectangle.corners[2], rectangle.lines[0]]
        #expect(model.availableConstraints == [.symmetric])
    }

    @Test func aConstraintIsOneStepAndClearsTheSelection() throws {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, host) = makeModel(rectangle.sketch)
        model.selection = [rectangle.lines[0], rectangle.lines[1]]
        model.addConstraint(.equal)
        #expect(host.commits.map(\.description) == ["Equal"])
        #expect(model.selection.isEmpty)
        #expect(model.solution.degreesOfFreedom == 1, "equal sides leave one size free")
        model.addConstraint(.tangent)
        #expect(model.refusal == SketchConstraintKind.tangent.hint, "nothing selected: the button says what to select")
        #expect(host.commits.count == 1)
    }

    @Test func deleteRemovesTheCurveAndItsLonePoints() {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        sketch.add(.horizontal(line))
        let (model, host) = makeModel(sketch)
        model.selection = [line]
        model.deleteSelection()
        #expect(model.sketch.entities.isEmpty && model.sketch.constraints.isEmpty)
        #expect(host.commits.map(\.description) == ["Delete"])
    }

    @Test func deleteRefusesToRemoveAnExposedDimension() {
        var rectangle = RectangleSketch()
        rectangle.sketch.dimensions[rectangle.width]?.isExposed = true
        let (model, host) = makeModel(rectangle.sketch)
        model.selection = [rectangle.lines[0]]
        model.deleteSelection()
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "That would remove d1, which is exposed as an input. Stop exposing it first.")
    }

    @Test func draggingAPointSolvesEveryStepAndCommitsOnceOnRelease() throws {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, host) = makeModel(rectangle.sketch)
        #expect(model.beginDrag(at: Vector2(60.3, 40.2), tolerance: 1))
        model.drag(to: Vector2(70, 50))
        #expect(host.commits.isEmpty, "downstream evaluation waits for the release")
        let mid = try #require(model.sketch.position(of: rectangle.corners[2]))
        #expect(abs(mid.x - 70) < 1e-3 && abs(mid.y - 50) < 1e-3, "a free corner follows the pointer")
        let bottom = try #require(model.sketch.position(of: rectangle.corners[1]))
        #expect(abs(bottom.x - 70) < 1e-3 && abs(bottom.y) < 1e-6, "the vertical side keeps it vertical")
        model.endDrag(at: Vector2(80, 50))
        #expect(host.commits.map(\.description) == ["Move Point"])
        let fixed = try #require(model.sketch.position(of: rectangle.corners[0]))
        #expect(fixed.length < 1e-9, "the fixed corner stays")
        #expect(!model.beginDrag(at: Vector2(30, 20), tolerance: 1), "a drag on nothing is the viewport's (it orbits)")
    }

    /// Review Focus 2: dragging a point of a sketch whose constraints conflict moves nothing (no drag step is
    /// usable), so the release records no undo step.
    @Test func aDragThatMovesNothingIsNoUndoStep() {
        var rectangle = RectangleSketch()
        rectangle.sketch.add(.vertical(rectangle.lines[0]))
        let (model, host) = makeModel(rectangle.sketch)
        #expect(model.statusIsProblem)
        #expect(model.beginDrag(at: Vector2(60.2, 40.1), tolerance: 1))
        model.drag(to: Vector2(70, 50))
        model.endDrag(at: Vector2(75, 55))
        #expect(host.commits.isEmpty)
        #expect(model.statusIsProblem, "the readout still shows the conflict")
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter CreatorSketchEditorTests`

Expected: FAIL — the build fails: "value of type 'SketchEditorModel' has no member 'availableConstraints'".

- [ ] **Step 3: Add selection, constraints, Delete and drags**

Create `Sources/CreatorSketchEditor/SelectionShape.swift`:

```swift
import CreatorGeometry
import CreatorSketch

/// The selection sorted by what it is, each group in ID order, for the constraint and dimension tools.
struct SelectionShape {
    var points: [SketchEntityID] = []
    var lines: [SketchEntityID] = []
    /// Arcs and circles.
    var rounds: [SketchEntityID] = []
    /// Projected edges.
    var projected: [SketchEntityID] = []

    init(_ selection: Set<SketchEntityID>, in sketch: Sketch) {
        for id in selection.sorted() {
            switch sketch.entities[id]?.kind {
            case .point?: points.append(id)
            case .line?: lines.append(id)
            case .arc?, .circle?: rounds.append(id)
            case .projected?: projected.append(id)
            case nil: break
            }
        }
    }

    var count: Int { points.count + lines.count + rounds.count + projected.count }

    /// Exactly `points` points, `lines` lines and `rounds` arcs or circles, and nothing else.
    func `is`(points: Int = 0, lines: Int = 0, rounds: Int = 0) -> Bool {
        self.points.count == points && self.lines.count == lines && self.rounds.count == rounds && projected.isEmpty
    }

    // The constraint `kind` makes from this selection, or `nil` when the selection doesn't fit it: one case per
    // constraint kind, each checking its own shape.
    // swiftlint:disable:next cyclomatic_complexity
    func constraint(_ kind: SketchConstraintKind, at position: (SketchEntityID) -> Vector2?) -> SketchConstraint? {
        switch kind {
        case .coincident: return `is`(points: 2) ? .coincident(points[0], points[1]) : nil
        case .pointOn:
            let curves = lines + rounds + projected
            return points.count == 1 && curves.count == 1 ? .pointOn(point: points[0], curve: curves[0]) : nil
        case .horizontal: return `is`(lines: 1) ? .horizontal(lines[0]) : `is`(points: 2) ? .horizontalPoints(points[0], points[1]) : nil
        case .vertical: return `is`(lines: 1) ? .vertical(lines[0]) : `is`(points: 2) ? .verticalPoints(points[0], points[1]) : nil
        case .parallel: return `is`(lines: 2) ? .parallel(lines[0], lines[1]) : nil
        case .perpendicular: return `is`(lines: 2) ? .perpendicular(lines[0], lines[1]) : nil
        case .tangent:
            if `is`(lines: 1, rounds: 1) { return .tangent(lines[0], rounds[0]) }
            return `is`(rounds: 2) ? .tangent(rounds[0], rounds[1]) : nil
        case .equal:
            if `is`(lines: 2) { return .equal(lines[0], lines[1]) }
            return `is`(rounds: 2) ? .equal(rounds[0], rounds[1]) : nil
        case .midpoint: return `is`(points: 1, lines: 1) ? .midpoint(point: points[0], line: lines[0]) : nil
        case .concentric: return `is`(rounds: 2) ? .concentric(rounds[0], rounds[1]) : nil
        case .symmetric: return `is`(points: 2, lines: 1) ? .symmetric(points[0], points[1], about: lines[0]) : nil
        case .fix:
            guard `is`(points: 1), let at = position(points[0]) else { return nil }
            return .fix(points[0], at: at)
        }
    }
}
```

Create `Sources/CreatorSketchEditor/SketchConstraintKind.swift`:

```swift
import CreatorSketch

/// The constraint buttons (sketcher spec §8: "buttons for each constraint", §3's table). Each makes its constraint
/// from the selection when the selection has the right shape.
public enum SketchConstraintKind: Hashable, Sendable, CaseIterable {
    case coincident, pointOn, horizontal, vertical, parallel, perpendicular, tangent, equal, midpoint, concentric,
         symmetric, fix

    public var title: String {
        switch self {
        case .coincident: "Coincident"
        case .pointOn: "Point on"
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        case .parallel: "Parallel"
        case .perpendicular: "Perpendicular"
        case .tangent: "Tangent"
        case .equal: "Equal"
        case .midpoint: "Midpoint"
        case .concentric: "Concentric"
        case .symmetric: "Symmetric"
        case .fix: "Fix"
        }
    }

    /// What to select for it, for the button's help text.
    public var hint: String {
        switch self {
        case .coincident: "Select two points."
        case .pointOn: "Select a point and a curve."
        case .horizontal, .vertical: "Select a line, or two points."
        case .parallel, .perpendicular: "Select two lines."
        case .tangent: "Select a line and an arc or circle, or two arcs or circles."
        case .equal: "Select two lines, or two arcs or circles."
        case .midpoint: "Select a point and a line."
        case .concentric: "Select two arcs or circles."
        case .symmetric: "Select two points and a line."
        case .fix: "Select a point."
        }
    }
}
```

Create `Sources/CreatorSketchEditor/SketchEditorModel+Drag.swift`:

```swift
import CreatorGeometry
import CreatorSketch

extension SketchEditorModel {
    /// Begins dragging the point under `p`, if there is one and no stroke is in progress (sketcher spec §8). True when
    /// the drag is the editor's.
    func beginDrag(at p: Vector2, tolerance: Double) -> Bool {
        guard drawState == .idle,
              let hit = SketchPicker(sketch: sketch, solution: solution).point(near: p, tolerance: tolerance) else { return false }
        dragged = hit.id
        dragOrigin = sketch
        preview = .none
        return true
    }

    /// One drag step: the sketch re-solves with the point pulled toward `p` as a soft target (spec §4's drag mode),
    /// and remembers the result so the next step warm-starts from it. Nothing is committed until the release.
    func drag(to p: Vector2) {
        guard let dragged else { return }
        let pulled = SketchSolver.solve(sketch, dragging: [dragged: p])
        solution = pulled
        sketch = Self.remembering(sketch, pulled)
    }

    /// The release (at `p`, or off the plane): the dragged sketch is one undo step ("Move Point"), and downstream
    /// evaluation runs once. A drag that moved nothing (a fixed point, or a sketch whose constraints conflict, so no
    /// drag step was usable) records no step.
    func endDrag(at p: Vector2?) {
        guard dragged != nil else { return }
        if let p { drag(to: p) }
        let origin = dragOrigin
        dragged = nil
        dragOrigin = nil
        if sketch == origin {
            solution = SketchSolver.solve(sketch)
        } else {
            commit(sketch, "Move Point")
        }
    }
}
```

Modify `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift` (apply this diff):

```diff
--- a/Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift
@@ -27,11 +27,13 @@ extension SketchEditorModel {
         commit(edited, makeConstruction ? "Make Construction" : "Make Normal Geometry")
     }
 
-    /// Esc: ends the stroke in progress, or with none, finishes the sketch.
+    /// Esc: ends the stroke in progress; with none, clears the selection; with nothing selected, finishes the sketch.
     public func escape() {
         if drawState != .idle {
             drawState = .idle
             preview = .none
+        } else if !selection.isEmpty {
+            selection = []
         } else {
             finish()
         }
@@ -49,7 +51,8 @@ extension SketchEditorModel {
     func click(at p: Vector2, tolerance: Double, modifiers: ViewportModifiers) {
         refusal = nil
         switch tool {
-        case .select, .dimension: break
+        case .select: select(at: p, tolerance: tolerance)
+        case .dimension: break
         case .point: placePoint(at: p, tolerance: tolerance)
         case .line: placeLinePoint(at: p, tolerance: tolerance, suppressed: modifiers.contains(.command))
         case .circle: placeCirclePoint(at: p, tolerance: tolerance)
```

Create `Sources/CreatorSketchEditor/SketchEditorModel+Selection.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import CreatorViewport

extension SketchEditorModel {
    /// A Select-tool click: toggles the entity under it in the selection (additive, so two-entity constraints need no
    /// modifier key, which MetalUI's taps don't report yet: docs/metalui-gaps.md S5-a); a click on nothing clears it.
    func select(at p: Vector2, tolerance: Double) {
        guard let picked = SketchPicker(sketch: sketch, solution: solution).entity(near: p, tolerance: tolerance) else {
            if !selection.isEmpty { selection = [] }
            return
        }
        if selection.contains(picked) { selection.remove(picked) } else { selection.insert(picked) }
    }

    /// The constraint buttons that fit the selection.
    public var availableConstraints: [SketchConstraintKind] {
        let shape = SelectionShape(selection, in: sketch)
        return SketchConstraintKind.allCases.filter { shape.constraint($0, at: sketch.position(of:)) != nil }
    }

    /// Adds `kind` on the selection as one step, then clears the selection. A selection that doesn't fit says why.
    public func addConstraint(_ kind: SketchConstraintKind) {
        guard let constraint = SelectionShape(selection, in: sketch).constraint(kind, at: sketch.position(of:)) else {
            refusal = kind.hint
            return
        }
        var edited = sketch
        edited.add(constraint)
        selection = []
        commit(edited, kind.title)
    }

    /// Delete: removes the selected entities with everything built on them and every constraint and dimension on
    /// them, and points left on their own. Refused when it would remove an exposed dimension (its input would vanish
    /// from the node with its wire: S1–S2 handoff).
    public func deleteSelection() {
        guard !selection.isEmpty else { return }
        var edited = sketch
        var freed: [SketchEntityID] = []
        for id in selection.sorted() {
            freed += edited.entities[id]?.kind.referencedPoints ?? []
            edited.removeEntity(id)
        }
        edited.removeOrphanPoints(freed)
        let exposed = sketch.dimensionIDs.compactMap { id -> String? in
            guard let dimension = sketch.dimensions[id], dimension.isExposed, edited.dimensions[id] == nil else { return nil }
            return dimension.name
        }
        if let name = exposed.first {
            refusal = "That would remove \(name), which is exposed as an input. Stop exposing it first."
            return
        }
        selection = []
        hovered = nil
        commit(edited, "Delete")
    }
}
```

Modify `Sources/CreatorSketchEditor/SketchEditorModel+ViewportTool.swift` (apply this diff):

```diff
--- a/Sources/CreatorSketchEditor/SketchEditorModel+ViewportTool.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel+ViewportTool.swift
@@ -21,11 +21,17 @@ extension SketchEditorModel: ViewportTool {
         return true
     }
 
+    /// A drag that starts on a point moves it; any other drag orbits.
     public func dragBegan(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool {
-        false
+        guard let p = projector.planePoint(under: point, on: plane) else { return false }
+        return beginDrag(at: p, tolerance: tolerance(projector))
     }
 
-    public func dragMoved(to point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {}
+    public func dragMoved(to point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {
+        if let p = projector.planePoint(under: point, on: plane) { drag(to: p) }
+    }
 
-    public func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {}
+    public func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {
+        endDrag(at: projector.planePoint(under: point, on: plane))
+    }
 }
```

Modify `Sources/CreatorSketchEditor/SketchEditorModel.swift` (apply this diff):

```diff
--- a/Sources/CreatorSketchEditor/SketchEditorModel.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel.swift
@@ -12,11 +12,11 @@ import Observation
 public final class SketchEditorModel {
     /// The sketch as the editor shows it: the last stored or committed one, solved and remembered, so its positions
     /// are the ones on screen.
-    public private(set) var sketch: Sketch
+    public internal(set) var sketch: Sketch
     /// The plane the sketch is drawn on, in world space.
     public private(set) var plane: Plane
     /// The live solve of `sketch` (re-run on every edit and every drag step).
-    public private(set) var solution: SketchSolution
+    public internal(set) var solution: SketchSolution
     /// A plain-language reason the last command was refused, until the next edit or tool change.
     public internal(set) var refusal: String?
     /// The selected entities (drawn in the selection colour; constraints and dimensions apply to them).
@@ -31,6 +31,10 @@ public final class SketchEditorModel {
     public internal(set) var isConstruction = false
     /// What the drawing tool has placed so far.
     var drawState = DrawState.idle
+    /// The point being dragged, between a drag's press and its release.
+    @ObservationIgnored var dragged: SketchEntityID?
+    /// The sketch when the drag began, so a drag that moved nothing records no step.
+    @ObservationIgnored var dragOrigin: Sketch?
 
     @ObservationIgnored public var events = SketchEditorEvents()
 
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CreatorSketchEditorTests`

Expected: PASS (exit 0, no line says "recorded an issue" or "failed after").

- [ ] **Step 5: Full verification**

Run, from the repo root: `swift build --build-tests 2>&1 | grep -E "(error|warning):" | grep -v "ld: warning"` (expected: nothing new; master's one test warning, `ContextMenuTests.swift:96` "'underPointer' mutated after capture", shows only when that file recompiles), then `swift test` (expected: exit 0, no "recorded an issue" / "failed after" lines, and the "Test run with N tests" lines sum to **1133 (master + 48)**), then `swiftlint lint --strict` (zero violations).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorSketchEditor/SelectionShape.swift Sources/CreatorSketchEditor/SketchConstraintKind.swift Sources/CreatorSketchEditor/SketchEditorModel+Drag.swift Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift Sources/CreatorSketchEditor/SketchEditorModel+Selection.swift Sources/CreatorSketchEditor/SketchEditorModel+ViewportTool.swift Sources/CreatorSketchEditor/SketchEditorModel.swift Tests/CreatorSketchEditorTests/SelectionAndConstraintTests.swift
git commit -m "feat(sketch-editor): select, constrain, delete and drag points with the live solve"
```


---

### Task 8: Dimensions: the Dimension tool and the inspector's edits

The Dimension tool infers the kind from its picks (sketcher spec §8): a circle gives a diameter and an arc a radius at once; a line waits (another line: angle; a point: distance; a click on nothing: length); a point waits for a point or a line (distance). The value is measured as the geometry is (added as a reference, solved, then made driving), so nothing moves. The inspector's rows (`dimensionRows`, `constraintRows`, conflicts marked) and edits: typed values ("12.5 mm", "30°"; nonsense refused), rename (empty, repeated and reserved names refused; the reserved check is injected by the host as `isReservedName`, since the editor can't import CreatorNodes), "Expose as input", driving/reference, and Remove (refusing an exposed dimension). The Dimension tool's first pick is drawn selected.

**Files:**
- Create: `Sources/CreatorSketchEditor/ConstraintRow.swift`
- Create: `Sources/CreatorSketchEditor/DimensionRow.swift`
- Create: `Sources/CreatorSketchEditor/DimensionText.swift`
- Create: `Sources/CreatorSketchEditor/SketchEditorModel+Dimensions.swift`
- Modify: `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`
- Modify: `Sources/CreatorSketchEditor/SketchEditorModel+Overlay.swift`
- Modify: `Sources/CreatorSketchEditor/SketchEditorModel.swift`
- Create: `Tests/CreatorSketchEditorTests/DimensionTests.swift`

**Interfaces:**
- Consumes: `SketchSolution.measurements`, `Sketch.addDimension/renameDimension/label(of:)`, `SketchPicker`, `commit`.
- Produces: `SketchEditorModel.init(sketch:plane:isReservedName: @escaping @MainActor (String) -> Bool = { _ in false })`; `dimensionRows: [DimensionRow]`, `constraintRows: [ConstraintRow]`, `setValue(_ text: String, of: DimensionID)`, `rename(_: DimensionID, to: String)`, `setExposed(_: Bool, of:)`, `setDriving(_: Bool, of:)`, `remove(_: SketchConstraintRef)`; `public struct DimensionRow { id, kind, name, value, isExposed, isDriving, isConflicting }`; `public struct ConstraintRow { id, label, isConflicting }`; internal `dimensionPick`, `DimensionText.format/parse`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorSketchEditorTests/DimensionTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// Dimensions (sketcher spec §8): the Dimension tool infers the kind from its picks and measures what's there; the
/// inspector edits value, name, "Expose as input" and driving, and removes constraints and dimensions.
@MainActor
struct DimensionTests {
    func makeModel(_ sketch: Sketch, reserved: Set<String> = []) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy) { reserved.contains($0) }
        model.choose(.dimension)
        return (model, RecordingHost(model))
    }

    func onlyDimension(_ model: SketchEditorModel) -> SketchDimension? {
        model.sketch.dimensionIDs.last.flatMap { model.sketch.dimensions[$0] }
    }

    @Test func aLineThenNothingIsItsLength() throws {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, host) = makeModel(rectangle.sketch)
        model.click(at: Vector2(30, 0.3), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty, "a line waits for a second pick")
        #expect(model.overlay.lines.contains { $0.tint == .selected }, "the first pick is shown")
        model.click(at: Vector2(30, 20), tolerance: 1, modifiers: [])
        let dimension = try #require(onlyDimension(model))
        #expect(dimension.kind == .length(rectangle.lines[0]) && abs(dimension.value - 60) < 1e-9 && dimension.isDriving)
        #expect(host.commits.map(\.description) == ["Dimension d1"])
        #expect(model.solution.degreesOfFreedom == 1, "it holds the width, and nothing moved")
    }

    @Test func twoLinesAreAnAngleAndTwoPointsADistance() throws {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, _) = makeModel(rectangle.sketch)
        model.click(at: Vector2(30, 0.3), tolerance: 1, modifiers: [])
        model.click(at: Vector2(60.2, 20), tolerance: 1, modifiers: [])
        let angle = try #require(onlyDimension(model))
        #expect(angle.kind == .angle(rectangle.lines[0], rectangle.lines[1]) && abs(angle.value - 90) < 1e-6)
        model.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        model.click(at: Vector2(60.2, 40.2), tolerance: 1, modifiers: [])
        let distance = try #require(onlyDimension(model))
        #expect(distance.kind == .distance(rectangle.corners[0], rectangle.corners[2]))
        #expect(abs(distance.value - Vector2(60, 40).length) < 1e-6)
    }

    @Test func aCircleIsItsDiameterAtOnce() throws {
        var sketch = Sketch()
        sketch.addCircle(center: Vector2(0, 0), radius: 5)
        let (model, host) = makeModel(sketch)
        model.click(at: Vector2(5.2, 0), tolerance: 1, modifiers: [])
        #expect(host.commits.count == 1)
        let dimension = try #require(onlyDimension(model))
        #expect(abs(dimension.value - 10) < 1e-9)
    }

    @Test func typedValuesDriveTheSketchAndNonsenseIsRefused() throws {
        let rectangle = RectangleSketch()
        let (model, host) = makeModel(rectangle.sketch)
        model.setValue("80 mm", of: rectangle.width)
        #expect(host.commits.map(\.description) == ["Change d1"])
        let corner = try #require(model.sketch.position(of: rectangle.corners[1]))
        #expect(abs(corner.x - 80) < 1e-6)
        #expect(model.dimensionRows.first?.value == "80 mm")
        model.setValue("wide", of: rectangle.width)
        #expect(model.refusal == "“wide” isn't a number." && host.commits.count == 1)
    }

    @Test func renamingRefusesTakenAndReservedNames() {
        let rectangle = RectangleSketch()
        let (model, host) = makeModel(rectangle.sketch, reserved: ["plane"])
        model.rename(rectangle.width, to: "d2")
        #expect(model.refusal == "Another dimension is already called “d2”.")
        model.rename(rectangle.width, to: "plane")
        #expect(model.refusal?.contains("taken by the Sketch node") == true)
        model.rename(rectangle.width, to: " width ")
        #expect(model.sketch.dimensions[rectangle.width]?.name == "width")
        #expect(host.commits.map(\.description) == ["Rename d1 to width"])
    }

    @Test func exposingAndReferenceAreOneStepEach() {
        let rectangle = RectangleSketch()
        let (model, host) = makeModel(rectangle.sketch)
        model.setExposed(true, of: rectangle.width)
        model.setDriving(false, of: rectangle.height)
        #expect(model.sketch.dimensions[rectangle.width]?.isExposed == true)
        #expect(model.dimensionRows.map(\.isDriving) == [true, false])
        #expect(host.commits.map(\.description) == ["Expose d1", "Make d2 Reference"])
        #expect(model.solution.degreesOfFreedom == 1, "a reference dimension holds nothing")
    }

    @Test func theInspectorListsAndRemovesConstraintsAndMarksConflicts() throws {
        var rectangle = RectangleSketch()
        let extra = rectangle.sketch.add(.vertical(rectangle.lines[0]))
        rectangle.sketch.dimensions[rectangle.width]?.isExposed = true
        let (model, host) = makeModel(rectangle.sketch)
        let row = try #require(model.constraintRows.first { $0.id == extra })
        #expect(row.isConflicting && row.label == "Vertical on Line 1")
        model.remove(.dimension(rectangle.width))
        #expect(host.commits.isEmpty && model.refusal?.contains("exposed as an input") == true)
        model.remove(.constraint(extra))
        #expect(host.commits.map(\.description) == ["Delete Vertical on Line 1"])
        #expect(model.statusText == "Fully constrained")
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter CreatorSketchEditorTests`

Expected: FAIL — the build fails: "extra trailing closure passed in call" (the `isReservedName` initializer) and "no member 'dimensionRows'".

- [ ] **Step 3: Add the Dimension tool and the inspector's edits**

Create `Sources/CreatorSketchEditor/ConstraintRow.swift`:

```swift
import CreatorSketch

/// One constraint in the sketch inspector: its plain-language label ("Horizontal on Line 3").
public struct ConstraintRow: Hashable, Sendable, Identifiable {
    public var id: SketchConstraintID
    public var label: String
    /// A conflict names it.
    public var isConflicting: Bool
}
```

Create `Sources/CreatorSketchEditor/DimensionRow.swift`:

```swift
import CreatorSketch

/// One dimension in the sketch inspector (sketcher spec §8): its kind and name, its value, and its switches.
public struct DimensionRow: Hashable, Sendable, Identifiable {
    public var id: DimensionID
    /// "Length", "Distance", "Radius", "Diameter" or "Angle".
    public var kind: String
    public var name: String
    /// "12.5 mm", "30°".
    public var value: String
    public var isExposed: Bool
    public var isDriving: Bool
    /// A conflict names it.
    public var isConflicting: Bool
}
```

Create `Sources/CreatorSketchEditor/DimensionText.swift`:

```swift
import CreatorSketch
import Foundation

/// A dimension's value as the inspector shows and reads it: up to three decimals, in millimetres or degrees.
enum DimensionText {
    static let locale = Locale(identifier: "en_US_POSIX")

    /// "12.5 mm", "30°".
    static func format(_ value: Double, kind: DimensionKind) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(locale))
        if case .angle = kind { return "\(number)°" }
        return "\(number) mm"
    }

    /// A typed value, ignoring spaces and a trailing unit ("12.5 mm", "45°"); `nil` if it isn't a finite number.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let number = trimmed.prefix { "0123456789.-+eE".contains($0) }
        guard !number.isEmpty, let value = Double(String(number)), value.isFinite else { return nil }
        let rest = trimmed.dropFirst(number.count).trimmingCharacters(in: .whitespaces)
        return ["", "mm", "°", "deg"].contains(rest) ? value : nil
    }
}
```

Create `Sources/CreatorSketchEditor/SketchEditorModel+Dimensions.swift`:

```swift
import CreatorGeometry
import CreatorSketch

extension SketchEditorModel {
    /// A Dimension-tool click (sketcher spec §8: the kind follows from the picks). A circle gives a diameter and an
    /// arc a radius at once. A line waits: another line gives an angle, a point a distance, and a click on nothing its
    /// length. A point waits for a point or a line (a distance). The new dimension measures the geometry as it is, so
    /// nothing moves.
    func dimension(at p: Vector2, tolerance: Double) {
        let picked = SketchPicker(sketch: sketch, solution: solution).entity(near: p, tolerance: tolerance)
        guard let first = dimensionPick else {
            guard let picked else { return }
            switch sketch.entities[picked]?.kind {
            case .circle?: addMeasuredDimension(.diameter(picked))
            case .arc?: addMeasuredDimension(.radius(picked))
            case .line?, .point?: dimensionPick = picked
            default: refusal = "Pick a line, a point, an arc or a circle to dimension."
            }
            return
        }
        dimensionPick = nil
        guard let kind = dimensionKind(first, picked) else {
            refusal = "Those can't be dimensioned together. Pick two points, a point and a line, or two lines."
            return
        }
        addMeasuredDimension(kind)
    }

    /// The kind for a first pick and a second (nil: a click on nothing).
    private func dimensionKind(_ first: SketchEntityID, _ second: SketchEntityID?) -> DimensionKind? {
        let firstKind = sketch.entities[first]?.kind
        guard let second else {
            if case .line? = firstKind { return .length(first) }
            return nil
        }
        switch (firstKind, sketch.entities[second]?.kind) {
        case (.line?, .line?): return second == first ? .length(first) : .angle(first, second)
        case (.point?, .point?): return second == first ? nil : .distance(first, second)
        case (.point?, .line?), (.line?, .point?): return .distance(first, second)
        default: return nil
        }
    }

    /// Adds a driving dimension of `kind` at the value the geometry has now (measured as a reference first).
    private func addMeasuredDimension(_ kind: DimensionKind) {
        var edited = sketch
        let id = edited.addDimension(kind, value: 0, isDriving: false)
        guard let measured = SketchSolver.solve(edited).measurements[id], measured.isFinite else {
            refusal = "That can't be measured."
            return
        }
        edited.dimensions[id]?.value = measured
        edited.dimensions[id]?.isDriving = true
        commit(edited, "Dimension \(edited.dimensions[id]?.name ?? "")")
    }

    /// The inspector's dimensions, in ID order.
    public var dimensionRows: [DimensionRow] {
        let conflicts = conflictRefs
        return sketch.dimensionIDs.compactMap { id in
            guard let dimension = sketch.dimensions[id] else { return nil }
            return DimensionRow(id: id, kind: Self.kindName(dimension.kind), name: dimension.name,
                                value: DimensionText.format(dimension.value, kind: dimension.kind), isExposed: dimension.isExposed,
                                isDriving: dimension.isDriving, isConflicting: conflicts.contains(.dimension(id)))
        }
    }

    /// The inspector's constraints, in ID order.
    public var constraintRows: [ConstraintRow] {
        let conflicts = conflictRefs
        return sketch.constraintIDs.map { id in
            ConstraintRow(id: id, label: sketch.label(of: .constraint(id)), isConflicting: conflicts.contains(.constraint(id)))
        }
    }

    private var conflictRefs: Set<SketchConstraintRef> {
        if case .overConstrained(let conflicts) = solution.status { return Set(conflicts) }
        return []
    }

    static func kindName(_ kind: DimensionKind) -> String {
        switch kind {
        case .distance: "Distance"
        case .length: "Length"
        case .radius: "Radius"
        case .diameter: "Diameter"
        case .angle: "Angle"
        }
    }

    /// A typed value for a dimension: one step. Text that isn't a number is refused, and the field shows the old value.
    public func setValue(_ text: String, of id: DimensionID) {
        guard let dimension = sketch.dimensions[id] else { return }
        guard let value = DimensionText.parse(text) else {
            refusal = "“\(text)” isn't a number."
            return
        }
        guard value != dimension.value else { return }
        var edited = sketch
        edited.dimensions[id]?.value = value
        commit(edited, "Change \(dimension.name)")
    }

    /// Renames a dimension, refusing an empty or repeated name and one the Sketch node reserves (`isReservedName`).
    public func rename(_ id: DimensionID, to name: String) {
        guard let dimension = sketch.dimensions[id] else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed != dimension.name else { return }
        if isReservedName(trimmed) {
            refusal = "“\(trimmed)” is taken by the Sketch node's own inputs and settings. Pick another name."
            return
        }
        var edited = sketch
        guard edited.renameDimension(id, to: trimmed) else {
            refusal = trimmed.isEmpty ? "A dimension needs a name." : "Another dimension is already called “\(trimmed)”."
            return
        }
        commit(edited, "Rename \(dimension.name) to \(trimmed)")
    }

    /// "Expose as input" (sketcher spec §7): the dimension becomes an input socket named after it.
    public func setExposed(_ exposed: Bool, of id: DimensionID) {
        guard let dimension = sketch.dimensions[id], dimension.isExposed != exposed else { return }
        var edited = sketch
        edited.dimensions[id]?.isExposed = exposed
        commit(edited, exposed ? "Expose \(dimension.name)" : "Stop Exposing \(dimension.name)")
    }

    /// Driving or reference (a reference dimension only measures, into the node's `measurements`).
    public func setDriving(_ driving: Bool, of id: DimensionID) {
        guard let dimension = sketch.dimensions[id], dimension.isDriving != driving else { return }
        var edited = sketch
        edited.dimensions[id]?.isDriving = driving
        if !driving, let measured = SketchSolver.solve(edited).measurements[id] { edited.dimensions[id]?.value = measured }
        commit(edited, driving ? "Make \(dimension.name) Driving" : "Make \(dimension.name) Reference")
    }

    /// Removes one constraint or dimension from the inspector's list. An exposed dimension is refused (its input and
    /// any wire into it would vanish: S1–S2 handoff).
    public func remove(_ ref: SketchConstraintRef) {
        var edited = sketch
        switch ref {
        case .constraint(let id):
            guard edited.constraints.removeValue(forKey: id) != nil else { return }
        case .dimension(let id):
            guard let dimension = edited.dimensions[id] else { return }
            guard !dimension.isExposed else {
                refusal = "That would remove \(dimension.name), which is exposed as an input. Stop exposing it first."
                return
            }
            edited.dimensions[id] = nil
        }
        commit(edited, "Delete \(sketch.label(of: ref))")
    }
}
```

Modify `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift` (apply this diff):

```diff
--- a/Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift
@@ -10,6 +10,7 @@ extension SketchEditorModel {
     public func choose(_ newTool: SketchTool) {
         tool = newTool
         drawState = .idle
+        dimensionPick = nil
         preview = .none
         refusal = nil
     }
@@ -29,8 +30,9 @@ extension SketchEditorModel {
 
     /// Esc: ends the stroke in progress; with none, clears the selection; with nothing selected, finishes the sketch.
     public func escape() {
-        if drawState != .idle {
+        if drawState != .idle || dimensionPick != nil {
             drawState = .idle
+            dimensionPick = nil
             preview = .none
         } else if !selection.isEmpty {
             selection = []
@@ -52,7 +54,7 @@ extension SketchEditorModel {
         refusal = nil
         switch tool {
         case .select: select(at: p, tolerance: tolerance)
-        case .dimension: break
+        case .dimension: dimension(at: p, tolerance: tolerance)
         case .point: placePoint(at: p, tolerance: tolerance)
         case .line: placeLinePoint(at: p, tolerance: tolerance, suppressed: modifiers.contains(.command))
         case .circle: placeCirclePoint(at: p, tolerance: tolerance)
```

Modify `Sources/CreatorSketchEditor/SketchEditorModel+Overlay.swift` (apply this diff):

```diff
--- a/Sources/CreatorSketchEditor/SketchEditorModel+Overlay.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel+Overlay.swift
@@ -1,9 +1,11 @@
 import CreatorViewport
 
 extension SketchEditorModel {
-    /// What the viewport draws while this sketch is edited (`ViewportModel.showOverlay(_:)`).
+    /// What the viewport draws while this sketch is edited (`ViewportModel.showOverlay(_:)`). The Dimension tool's
+    /// first pick is drawn selected.
     public var overlay: ViewportOverlay {
-        SketchOverlayBuilder.overlay(sketch: sketch, solution: solution, plane: plane, selection: selection, hovered: hovered,
-                                     preview: preview)
+        let picked = dimensionPick.map { selection.union([$0]) } ?? selection
+        return SketchOverlayBuilder.overlay(sketch: sketch, solution: solution, plane: plane, selection: picked, hovered: hovered,
+                                            preview: preview)
     }
 }
```

Modify `Sources/CreatorSketchEditor/SketchEditorModel.swift` (apply this diff):

```diff
--- a/Sources/CreatorSketchEditor/SketchEditorModel.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel.swift
@@ -35,11 +35,16 @@ public final class SketchEditorModel {
     @ObservationIgnored var dragged: SketchEntityID?
     /// The sketch when the drag began, so a drag that moved nothing records no step.
     @ObservationIgnored var dragOrigin: Sketch?
+    /// The Dimension tool's first pick, while it waits for the second.
+    var dimensionPick: SketchEntityID?
+    /// Names an exposed dimension can't take (the Sketch node's own inputs and settings). The host provides it.
+    @ObservationIgnored let isReservedName: @MainActor (String) -> Bool
 
     @ObservationIgnored public var events = SketchEditorEvents()
 
-    public init(sketch: Sketch, plane: Plane) {
+    public init(sketch: Sketch, plane: Plane, isReservedName: @escaping @MainActor (String) -> Bool = { _ in false }) {
         self.plane = plane
+        self.isReservedName = isReservedName
         let solution = SketchSolver.solve(sketch)
         self.solution = solution
         self.sketch = Self.remembering(sketch, solution)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CreatorSketchEditorTests`

Expected: PASS (exit 0, no line says "recorded an issue" or "failed after").

- [ ] **Step 5: Full verification**

Run, from the repo root: `swift build --build-tests 2>&1 | grep -E "(error|warning):" | grep -v "ld: warning"` (expected: nothing new; master's one test warning, `ContextMenuTests.swift:96` "'underPointer' mutated after capture", shows only when that file recompiles), then `swift test` (expected: exit 0, no "recorded an issue" / "failed after" lines, and the "Test run with N tests" lines sum to **1140 (master + 55)**), then `swiftlint lint --strict` (zero violations).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorSketchEditor/ConstraintRow.swift Sources/CreatorSketchEditor/DimensionRow.swift Sources/CreatorSketchEditor/DimensionText.swift Sources/CreatorSketchEditor/SketchEditorModel+Dimensions.swift Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift Sources/CreatorSketchEditor/SketchEditorModel+Overlay.swift Sources/CreatorSketchEditor/SketchEditorModel.swift Tests/CreatorSketchEditorTests/DimensionTests.swift
git commit -m "feat(sketch-editor): dimension tool with inferred kinds; edit, rename, expose and remove dimensions"
```


---

### Task 9: The sketch views: toolbar and inspector

Thin MetalUI views; the host adds the glass chrome and places them (Task 11). `SketchToolbar` is one row for the 44-point top bar: the tools (L, A, C, D), Construction (X), Delete (⌫), Finish (⏎) and invisible buttons for Esc and forward delete (⌦, fn-⌫). Keys are button shortcuts: a focused field claims its keys first, and shortcuts run before the window's `onInput`, where the graph panel's keys are, so no keymap or `AppInput` change is needed. Delete and ⌦ are never disabled: a disabled button's shortcut falls through to the graph's Delete, which maps both ⌫ and ⌦ (`GraphKeyBindings.plainCommand`) and would delete the selected graph nodes, and while sketching that is the Sketch node being edited. `SketchInspector` shows the readout, a refusal, the constraint buttons three to a row (enabled for the selection, the hint as tooltip), the dimension rows (name and value fields that commit on Return or focus loss, Expose and Driving toggles, Remove) and the constraint rows (Remove).

**Files:**
- Create: `Sources/CreatorSketchEditor/Views/ConstraintButtons.swift`
- Create: `Sources/CreatorSketchEditor/Views/DimensionField.swift`
- Create: `Sources/CreatorSketchEditor/Views/DimensionRowView.swift`
- Create: `Sources/CreatorSketchEditor/Views/EscapeKey.swift`
- Create: `Sources/CreatorSketchEditor/Views/ForwardDeleteKey.swift`
- Create: `Sources/CreatorSketchEditor/Views/SketchColors.swift`
- Create: `Sources/CreatorSketchEditor/Views/SketchInspector.swift`
- Create: `Sources/CreatorSketchEditor/Views/SketchToolButton.swift`
- Create: `Sources/CreatorSketchEditor/Views/SketchToolbar.swift`
- Create: `Tests/CreatorSketchEditorTests/SketchViewTests.swift`
- Create: `Tests/CreatorSketchEditorTests/Support/RenderSupport.swift`

**Interfaces:**
- Consumes: `SketchEditorModel` (Tasks 4–8), `ThemeStore` (CreatorStyle) from the environment.
- Produces: `public struct SketchToolbar: Component { init(model:) }`, `public struct SketchInspector: Component { init(model:) }`; internal `SketchTool.key: KeyEquivalent?`, `SketchToolButton`, `EscapeKey`, `ForwardDeleteKey`, `ConstraintButtons`, `DimensionRowView`, `DimensionField`, `SketchColors`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorSketchEditorTests/SketchViewTests.swift`:

```swift
import CreatorSketch
import MetalUI
import Testing
@testable import CreatorSketchEditor

/// Headless frames of the toolbar and the inspector: they build, lay out and paint in each state. Looks and keys are
/// human checks (group S5; a client can't send keys through a window, docs/metalui-gaps.md M6-e).
@MainActor
struct SketchViewTests {
    @Test func theToolKeysAreTheSpecs() {
        #expect(SketchTool.line.key == "l" && SketchTool.arc.key == "a" && SketchTool.circle.key == "c")
        #expect(SketchTool.dimension.key == "d" && SketchTool.select.key == nil && SketchTool.point.key == nil)
    }

    @Test func theToolbarAndTheConstraintButtonsDrawWithAndWithoutASelection() {
        let rectangle = RectangleSketch()
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        #expect(!renderHeadless { SketchToolbar(model: model) }.glyphs.isEmpty)
        model.selection = [rectangle.lines[0], rectangle.lines[1]]
        model.toggleConstruction()
        #expect(!renderHeadless { SketchToolbar(model: model) }.glyphs.isEmpty)
        #expect(!renderHeadless { SketchInspector(model: model) }.glyphs.isEmpty)
    }

    @Test func theInspectorDrawsDimensionsConstraintsAndProblems() {
        var rectangle = RectangleSketch()
        rectangle.sketch.add(.vertical(rectangle.lines[0]))
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        model.refusal = "Select two lines."
        #expect(!renderHeadless { SketchInspector(model: model) }.glyphs.isEmpty)
        let empty = SketchEditorModel(sketch: Sketch(), plane: .xy)
        #expect(!renderHeadless { SketchInspector(model: empty) }.glyphs.isEmpty)
    }
}
```

Create `Tests/CreatorSketchEditorTests/Support/RenderSupport.swift`:

```swift
// Test fixture file: the headless frame helper for the sketch editor's view tests.
import MetalUI
import MetalUIText

/// A headless frame of `view` (MetalUI's `renderFrame`), wrapped in a `ZStack` because a frame's root must be an
/// `Element` and a `Component` is a group.
@MainActor
func renderHeadless<View: ElementGroup>(_ view: () -> View) -> Scene {
    let content = view()
    return renderFrame({ ZStack { content } }, size: Size(width: Pixels(1200), height: Pixels(700)), scaleFactor: 2,
                       textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter SketchViewTests`

Expected: FAIL — the build fails: "cannot find 'SketchToolbar' in scope".

- [ ] **Step 3: Add the views**

Create `Sources/CreatorSketchEditor/Views/ConstraintButtons.swift`:

```swift
import MetalUI

/// The constraint buttons (sketcher spec §8), three to a row, each enabled when the selection fits it and saying
/// what to select in its tooltip.
struct ConstraintButtons: Component {
    let model: SketchEditorModel
    static let perRow = 3

    var content: some ElementGroup {
        let available = model.availableConstraints
        let kinds = SketchConstraintKind.allCases
        return VStack(alignment: .leading, spacing: Pixels(4)) {
            ForEach(Array(stride(from: 0, to: kinds.count, by: Self.perRow)), id: \.self) { start in
                HStack(spacing: Pixels(4)) {
                    ForEach(kinds[start..<min(start + Self.perRow, kinds.count)], id: \.self) { kind in
                        Button(kind.title) { model.addConstraint(kind) }
                            .help(kind.hint)
                            .disabled(!available.contains(kind))
                    }
                }
            }
        }
    }
}
```

Create `Sources/CreatorSketchEditor/Views/DimensionField.swift`:

```swift
import MetalUI

/// A text field that keeps its draft while typing and submits it on Return or when it loses focus; the shown text
/// comes back whenever the model's changes (a refused entry snaps back).
struct DimensionField: Component {
    let text: String
    let width: Double
    let submit: @MainActor (String) -> Void
    @State var draft: String?
    @FocusState var isFocused: Bool

    var content: some ElementGroup {
        TextField("", text: draft ?? text, onChange: { draft = $0 })
            .focused($isFocused)
            .onSubmit { commit() }
            .frame(width: Pixels(Float(width)))
            .onChange(of: text) { draft = nil }
            .onChange(of: isFocused) { wasFocused, focused in
                if wasFocused, !focused { commit() }
            }
    }

    private func commit() {
        guard let typed = draft else { return }
        draft = nil
        submit(typed)
    }
}
```

Create `Sources/CreatorSketchEditor/Views/DimensionRowView.swift`:

```swift
import CreatorStyle
import MetalUI

/// One dimension: kind, name field, value field, then "Expose as input", Driving and Remove.
struct DimensionRowView: Component {
    let model: SketchEditorModel
    let row: DimensionRow
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let colors = SketchColors(themes)
        return VStack(alignment: .leading, spacing: Pixels(4)) {
            HStack(spacing: Pixels(6)) {
                Text(row.kind).font(.callout).foregroundStyle(row.isConflicting ? colors.problem : colors.primary)
                DimensionField(text: row.name, width: 64) { model.rename(row.id, to: $0) }
                DimensionField(text: row.value, width: 80) { model.setValue($0, of: row.id) }
            }
            HStack(spacing: Pixels(6)) {
                Toggle("Expose as input", isOn: Binding(get: { row.isExposed }, set: { model.setExposed($0, of: row.id) }))
                Toggle("Driving", isOn: Binding(get: { row.isDriving }, set: { model.setDriving($0, of: row.id) }))
                Spacer()
                Button("Remove") { model.remove(.dimension(row.id)) }
            }
        }
    }
}
```

Create `Sources/CreatorSketchEditor/Views/EscapeKey.swift`:

```swift
import MetalUI

/// Esc while sketching (sketcher spec §8): ends the stroke in progress, clears the selection, or finishes. A button
/// shortcut, drawn invisibly (MetalUI fires a hidden button's shortcut), so it runs before the graph panel's Escape.
struct EscapeKey: Component {
    let model: SketchEditorModel

    var content: some ElementGroup {
        Button("Escape") { model.escape() }
            .keyboardShortcut(.escape, modifiers: [])
            .frame(width: Pixels(0), height: Pixels(0))
            .opacity(0)
            .allowsHitTesting(false)
    }
}
```

Create `Sources/CreatorSketchEditor/Views/ForwardDeleteKey.swift`:

```swift
import MetalUI

/// Forward delete (⌦, fn-⌫) while sketching: deletes the selection, as ⌫ does. The graph panel maps both keys to
/// deleting nodes, and while sketching the graph's selection is the Sketch node being edited, so without this a
/// forward delete would delete it. A button shortcut drawn invisibly, as `EscapeKey` is, so it runs before the graph
/// panel's keys; never disabled, so the key never falls through.
struct ForwardDeleteKey: Component {
    let model: SketchEditorModel

    var content: some ElementGroup {
        Button("Delete Forward") { model.deleteSelection() }
            .keyboardShortcut(.deleteForward, modifiers: [])
            .frame(width: Pixels(0), height: Pixels(0))
            .opacity(0)
            .allowsHitTesting(false)
    }
}
```

Create `Sources/CreatorSketchEditor/Views/SketchColors.swift`:

```swift
import CreatorStyle
import MetalUI

/// The theme's colours for the sketch editor's views: the store's theme, or Dracula without one (headless tests).
struct SketchColors {
    let colors: ThemeColors

    @MainActor
    init(_ store: ThemeStore?) {
        colors = (store?.current ?? .dracula).colors
    }

    var primary: Color { colors.foreground.color }
    var secondary: Color { colors.comment.color }
    var problem: Color { colors.error.color }
    var warning: Color { colors.warning.color }
}
```

Create `Sources/CreatorSketchEditor/Views/SketchInspector.swift`:

```swift
import CreatorStyle
import MetalUI

/// The inspector while sketching (sketcher spec §8): the degrees-of-freedom readout or the problem, a refused
/// command's reason, the constraint buttons, the dimensions with their name and value fields, "Expose as input" and
/// driving switches, and the constraints, each removable. Conflicting rows are in the error colour. The host draws it
/// in glass chrome.
public struct SketchInspector: Component {
    let model: SketchEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init(model: SketchEditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        let colors = SketchColors(themes)
        return VStack(alignment: .leading, spacing: Pixels(8)) {
            Text(model.statusText).font(.callout).foregroundStyle(model.statusIsProblem ? colors.problem : colors.primary)
            if let refusal = model.refusal {
                Text(refusal).font(.caption).foregroundStyle(colors.warning)
            }
            Text("CONSTRAIN").font(.caption2).foregroundStyle(colors.secondary)
            ConstraintButtons(model: model)
            Text("DIMENSIONS").font(.caption2).foregroundStyle(colors.secondary)
            if model.dimensionRows.isEmpty {
                Text("Pick the Dimension tool (D), then a line, two points or a circle.").font(.caption).foregroundStyle(colors.secondary)
            }
            ForEach(model.dimensionRows, id: \.id) { row in
                DimensionRowView(model: model, row: row)
            }
            Text("CONSTRAINTS").font(.caption2).foregroundStyle(colors.secondary)
            if model.constraintRows.isEmpty {
                Text("No constraints").font(.caption).foregroundStyle(colors.secondary)
            }
            ForEach(model.constraintRows, id: \.id) { row in
                HStack(spacing: Pixels(6)) {
                    Text(row.label).font(.callout).foregroundStyle(row.isConflicting ? colors.problem : colors.primary)
                    Spacer()
                    Button("Remove") { model.remove(.constraint(row.id)) }
                }
            }
        }
        .frame(width: Pixels(280), alignment: .topLeading)
    }
}
```

Create `Sources/CreatorSketchEditor/Views/SketchToolButton.swift`:

```swift
import MetalUI

/// One tool in the toolbar, marked while it's the active one, with its key (sketcher spec §8).
struct SketchToolButton: Component {
    let model: SketchEditorModel
    let tool: SketchTool

    var content: some ElementGroup {
        let title = model.tool == tool ? "\(tool.title) ✓" : tool.title
        if let key = tool.key {
            Button(title) { model.choose(tool) }
                .keyboardShortcut(key, modifiers: [])
                .help("\(tool.title) (\(String(key.character).uppercased()))")
        } else {
            Button(title) { model.choose(tool) }
        }
    }
}

extension SketchTool {
    /// The tool's key (sketcher spec §8's table), or `nil` for none.
    var key: KeyEquivalent? {
        switch self {
        case .line: "l"
        case .arc: "a"
        case .circle: "c"
        case .dimension: "d"
        case .select, .point: nil
        }
    }
}
```

Create `Sources/CreatorSketchEditor/Views/SketchToolbar.swift`:

```swift
import CreatorStyle
import MetalUI

/// The sketch toolbar (sketcher spec §8), one row for the top bar: the tools with their keys, Construction (X),
/// Delete (⌫, and ⌦ through `ForwardDeleteKey`) and Finish (⏎), plus Esc. The constraint buttons are in the inspector
/// (`SketchInspector`). Keys are button shortcuts, so a focused field still types them, and they run before the graph
/// panel's keys (MetalUI's key order: a focused field, then button shortcuts, then the window's `onInput`).
public struct SketchToolbar: Component {
    let model: SketchEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init(model: SketchEditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        HStack(spacing: Pixels(6)) {
            Text("Sketch").font(.headline).foregroundStyle(SketchColors(themes).primary)
            ForEach(SketchTool.allCases, id: \.self) { tool in
                SketchToolButton(model: model, tool: tool)
            }
            Button(model.isConstruction ? "Construction ✓" : "Construction") { model.toggleConstruction() }
                .keyboardShortcut("x", modifiers: [])
                .help("Construction geometry (X): new geometry, or the selection")
            // Never disabled: a disabled button's shortcut falls through to the graph panel's Delete, which deletes nodes.
            Button("Delete") { model.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
            ForwardDeleteKey(model: model)
            Spacer()
            Button("Finish") { model.finish() }
                .keyboardShortcut(.return, modifiers: [])
            EscapeKey(model: model)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SketchViewTests`

Expected: PASS (exit 0, no line says "recorded an issue" or "failed after").

- [ ] **Step 5: Full verification**

Run, from the repo root: `swift build --build-tests 2>&1 | grep -E "(error|warning):" | grep -v "ld: warning"` (expected: nothing new; master's one test warning, `ContextMenuTests.swift:96` "'underPointer' mutated after capture", shows only when that file recompiles), then `swift test` (expected: exit 0, no "recorded an issue" / "failed after" lines, and the "Test run with N tests" lines sum to **1143 (master + 58)**), then `swiftlint lint --strict` (zero violations).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorSketchEditor/Views/ConstraintButtons.swift Sources/CreatorSketchEditor/Views/DimensionField.swift Sources/CreatorSketchEditor/Views/DimensionRowView.swift Sources/CreatorSketchEditor/Views/EscapeKey.swift Sources/CreatorSketchEditor/Views/ForwardDeleteKey.swift Sources/CreatorSketchEditor/Views/SketchColors.swift Sources/CreatorSketchEditor/Views/SketchInspector.swift Sources/CreatorSketchEditor/Views/SketchToolButton.swift Sources/CreatorSketchEditor/Views/SketchToolbar.swift Tests/CreatorSketchEditorTests/SketchViewTests.swift Tests/CreatorSketchEditorTests/Support/RenderSupport.swift
git commit -m "feat(sketch-editor): toolbar and inspector views with button-shortcut keys"
```


---

### Task 10: App: sketch mode

"Edit sketch" becomes the Sketch node's inspector button (`InspectorAction.editSketch`, handled in `AppModel.handle(_:)`). `beginSketch(for:)` resolves the plane (fixed, or the wired plane's current result; refused plainly without one), folds a constant left under an exposed dimension's socket name into the sketch, makes a `SketchEditorModel` (reserved names from `SketchNode.isReservedDimensionName`), starts a `SketchSession` (the editor as the viewport's tool, its overlay followed by its own observation loop so hover and the rubber band don't need scene refreshes) and looks at the plane. While sketching the scene is ghosted, handles are hidden, and every scene refresh reloads the editor from the node (undo, redo) or leaves sketch mode when the node is gone; New/Open leave it too. Each commit is one `.batch` (`SketchStore`): the `sketch` setting; cleared constants under exposed names (the value lives in the sketch alone); a renamed exposed dimension's wire moved, an un-exposed one's dropped; reserved names never touched (Review Focus 5). Esc/Finish ask the host first so an open add-node palette closes instead of sketch mode ending (Review Focus 1). The editor now compares `reload` against the sketch the host last stored (not its own solved copy), so the per-refresh reload keeps a stroke in progress; a reload that changes the sketch (undo, redo) also drops a Dimension tool's pending first pick and ends a point drag, so neither names an entity that is gone nor commits "Move Point" over the undo. The new inspector button would hide the exposed dimensions' fallback rows but for Task 1's per-node section, which a test on the real Sketch node pins (outside sketch mode the inspector still edits them; a constant typed there is folded into the sketch on open and cleared by the next commit).

**Files:**
- Modify: `Sources/CreatorApp/AppModel+Picking.swift`
- Modify: `Sources/CreatorApp/AppModel+Scene.swift`
- Create: `Sources/CreatorApp/AppModel+Sketch.swift`
- Modify: `Sources/CreatorApp/AppModel.swift`
- Create: `Sources/CreatorApp/SketchSession.swift`
- Create: `Sources/CreatorApp/SketchStore.swift`
- Modify: `Sources/CreatorGraph/InspectorAction.swift`
- Modify: `Sources/CreatorNodes/Profiles/SketchNode.swift`
- Modify: `Sources/CreatorSketchEditor/SketchEditorEvents.swift`
- Modify: `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`
- Modify: `Sources/CreatorSketchEditor/SketchEditorModel.swift`
- Create: `Tests/CreatorAppTests/SketchModeTests.swift`
- Create: `Tests/CreatorAppTests/Support/SketchGraph.swift`
- Modify: `Tests/CreatorEditorTests/PerNodeSocketTests.swift`
- Modify: `Tests/CreatorSketchEditorTests/SketchEditorModelTests.swift`

**Interfaces:**
- Consumes: Tasks 1–9; `EditorModel.press/inspectorRequest/palette/closePalette/commitPendingEntry`, `DocumentModel.perform(.batch(_))`, `Graph.incomingLink(to:)`, `ViewportModel.lookAt/showOverlay/tool`.
- Produces: `InspectorAction.editSketch`; `SketchNode.inspector` ("Edit sketch") and `public static func isReservedDimensionName(_:) -> Bool`; `AppModel.sketch: SketchSession?`, `beginSketch(for: NodeID)`, `finishSketch()`, internal `storeSketch(_:)`, `refreshSketch()`, `sketchPlane(of:_:)`, `closePaletteOverSketch()`, `static framing(_:on:)`; `@MainActor public final class SketchSession { node; editor; start(); stop(); settle() async }`; `enum SketchStore { commands(storing:in:graph:), folded(_:constants:), exposedNames(_:) }`; `SketchEditorEvents.dismissHostPopup`; `SketchEditorModel.stored`. Test fixtures `rectangleSketch(on:exposed:)` and `GraphBuilder.sketchedBox(_:values:)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorAppTests/SketchModeTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor

/// Sketch mode (sketcher spec §8): "Edit sketch" opens the node's sketch in the viewport, every editor commit is one
/// `setInput` undo step, undo reloads it, Finish leaves, and an exposed dimension's value and wire live in one place
/// (S4 → S5 handoff).
@MainActor
struct SketchModeTests {
    func openSketch(_ builder: GraphBuilder, _ node: Node) async throws -> AppModel {
        let app = await makeApp(builder.graph)
        app.editor.selection = [node.id]
        app.editor.press(.editSketch, on: node.id)
        app.handle(try #require(app.editor.inspectorRequest))
        await app.settle()
        return app
    }

    func storedSketch(_ app: AppModel, _ node: Node) -> Sketch? {
        if case .sketch(let sketch)? = app.document.graph.nodes[node.id]?.inputValues[NodeSetting.sketch] { return sketch }
        return nil
    }

    @Test func theSketchNodesInspectorHasEditSketch() {
        #expect(SketchNode.inspector.first?.controls == [.button(title: "Edit sketch", action: .editSketch)])
    }

    @Test func editSketchLooksAtThePlaneDimsTheModelAndTakesThePointer() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch(on: .xz))
        let app = try await openSketch(builder, box.sketch)
        let session = try #require(app.sketch)
        #expect(session.node == box.sketch.id)
        #expect(app.viewport.tool === session.editor)
        await app.viewport.waitForAnimation()
        #expect(app.viewport.pose.projection == .orthographic)
        #expect((app.viewport.pose.toEye - Plane.xz.normal).length < 1e-9, "looking straight at the sketch plane")
        #expect(!app.viewport.items.isEmpty && app.viewport.items.allSatisfy(\.isGhost), "the model is dimmed")
        #expect(app.viewport.handles.isEmpty)
        #expect(app.viewport.overlay == session.editor.overlay, "the sketch is drawn over it")
        #expect(app.viewport.overlay.gridPlane == .xz)
    }

    @Test func eachCommitIsOneUndoStepAndUndoReloadsTheEditor() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await openSketch(builder, box.sketch)
        let editor = try #require(app.sketch?.editor)
        let before = storedSketch(app, box.sketch)
        editor.choose(.line)
        editor.click(at: Vector2(0, 60), tolerance: 1, modifiers: [])
        editor.click(at: Vector2(30, 80), tolerance: 1, modifiers: [])
        await app.settle()
        #expect(storedSketch(app, box.sketch) == editor.sketch, "the node holds what the editor shows, remembered")
        app.document.undo()
        await app.settle()
        #expect(storedSketch(app, box.sketch) == before)
        #expect(editor.sketch.entities.count == 8, "the editor shows the sketch as it was")
        #expect(app.sketch != nil, "undo stays in sketch mode")
        #expect(app.document.canUndo == false)
    }

    @Test func aStrokeInProgressSurvivesSceneRefreshes() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await openSketch(builder, box.sketch)
        let editor = try #require(app.sketch?.editor)
        editor.choose(.line)
        editor.click(at: Vector2(0, 60), tolerance: 1, modifiers: [])
        app.editor.selection = []
        await app.settle()
        editor.click(at: Vector2(30, 80), tolerance: 1, modifiers: [])
        #expect(app.document.canUndo, "the line was drawn from the first click")
    }

    @Test func theOverlayFollowsTheEditorBetweenSceneRefreshes() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await openSketch(builder, box.sketch)
        let session = try #require(app.sketch)
        session.editor.choose(.line)
        session.editor.click(at: Vector2(0, 60), tolerance: 1, modifiers: [])
        session.editor.hover(at: Vector2(10, 70), tolerance: 1, modifiers: [])
        await session.settle()
        #expect(app.viewport.overlay.lines.contains { $0.tint == .preview }, "the rubber band reaches the viewport")
    }

    @Test func finishingGivesTheViewportBack() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await openSketch(builder, box.sketch)
        try #require(app.sketch).editor.finish()
        await app.settle()
        #expect(app.sketch == nil && app.viewport.tool == nil)
        #expect(app.viewport.overlay.isEmpty)
        #expect(app.viewport.items.allSatisfy { !$0.isGhost })
    }

    @Test func removingTheNodeLeavesSketchMode() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await openSketch(builder, box.sketch)
        try app.document.perform(.removeNode(box.sketch.id))
        await app.settle()
        #expect(app.sketch == nil && app.viewport.tool == nil)
    }

    @Test func aNewDocumentLeavesSketchMode() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await openSketch(builder, box.sketch)
        let old = app.viewport
        #expect(!app.isEdited, "opening a sketch isn't an edit, so New doesn't ask")
        app.newDocument()
        await app.settle()
        #expect(app.sketch == nil && old.tool == nil)
    }

    @Test func anExposedDimensionsConstantIsFoldedIntoTheSketchAndCleared() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch(exposed: true), values: ["width": .number(70)])
        let app = try await openSketch(builder, box.sketch)
        let editor = try #require(app.sketch?.editor)
        #expect(editor.dimensionRows.first?.value == "70 mm", "the editor shows what the node evaluates")
        let height = try #require(editor.sketch.dimensionIDs.last)
        editor.setValue("30", of: height)
        await app.settle()
        let node = try #require(app.document.graph.nodes[box.sketch.id])
        #expect(node.inputValues["width"] == nil, "the value lives in the sketch alone")
        let stored = try #require(storedSketch(app, box.sketch))
        #expect(stored.dimensions.values.first { $0.name == "width" }?.value == 70)
    }

    @Test func renamingAnExposedDimensionMovesItsWireAndUnexposingDropsIt() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch(exposed: true))
        let number = builder.add(NumberNode.self, ["value": .number(75)], at: Vector2(0, 200))
        builder.wire(number, "value", to: box.sketch, "width")
        let app = try await openSketch(builder, box.sketch)
        let editor = try #require(app.sketch?.editor)
        let width = try #require(editor.sketch.dimensionIDs.first)
        editor.rename(width, to: "w")
        await app.settle()
        let to = { (socket: SocketName) in app.document.graph.incomingLink(to: Endpoint(node: box.sketch.id, socket: socket)) }
        #expect(to("width") == nil && to("w")?.from.node == number.id, "the wire follows the rename")
        #expect(app.document.results[box.sketch.id]?.state.isSuccess == true)
        editor.setExposed(false, of: width)
        await app.settle()
        #expect(to("w") == nil, "no socket, no wire")
        app.document.undo()
        app.document.undo()
        await app.settle()
        #expect(to("width")?.from.node == number.id, "undo puts the wire back")
    }

    @Test func reservedNamesAreRefused() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await openSketch(builder, box.sketch)
        let editor = try #require(app.sketch?.editor)
        let width = try #require(editor.sketch.dimensionIDs.first)
        editor.rename(width, to: "references")
        #expect(editor.refusal?.contains("taken by the Sketch node") == true)
        #expect(!app.document.canUndo)
    }

    @Test func aWiredPlaneWithoutAResultIsRefusedPlainly() async throws {
        var builder = GraphBuilder()
        var sketch = rectangleSketch()
        sketch.plane = .wired
        let node = builder.add(SketchNode.self, [NodeSetting.sketch: .sketch(sketch)])
        let app = try await openSketch(builder, node)
        #expect(app.sketch == nil)
        #expect(app.alert != nil)
    }

    /// Review Focus 1: Esc and ⏎ are the sketch's button shortcuts, which run before the palette's keys, so with the
    /// add-node palette open they close it and the sketch stays open.
    @Test func escapeAndFinishCloseTheAddNodePaletteFirst() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = try await openSketch(builder, box.sketch)
        let editor = try #require(app.sketch?.editor)
        app.editor.openPalette()
        editor.escape()
        #expect(app.editor.palette == nil && app.sketch != nil)
        app.editor.openPalette()
        editor.finish()
        #expect(app.editor.palette == nil && app.sketch != nil)
        editor.finish()
        #expect(app.sketch == nil)
    }

    /// Review Focus 5: an exposed dimension named like a setting (a hand-edited file) is never a socket, so storing
    /// the sketch never clears that setting, even when the dimension stops being exposed.
    @Test func aReservedExposedNameNeverClearsTheSketchSetting() async throws {
        var sketch = rectangleSketch(exposed: true)
        let width = try #require(sketch.dimensions.first { $0.value.name == "width" }?.key)
        sketch.dimensions[width]?.name = "sketch"
        var builder = GraphBuilder()
        let box = builder.sketchedBox(sketch)
        let app = try await openSketch(builder, box.sketch)
        try #require(app.sketch?.editor).setExposed(false, of: width)
        await app.settle()
        let stored = try #require(storedSketch(app, box.sketch))
        #expect(stored.dimensions[width]?.isExposed == false, "the edit is stored, and the sketch setting with it")
        #expect(app.document.results[box.sketch.id]?.state.isSuccess == true)
    }
}
```

Create `Tests/CreatorAppTests/Support/SketchGraph.swift`:

```swift
// Test fixture file: a Sketch node holding a dimensioned rectangle, extruded into an Output.
import CreatorGeometry
import CreatorGraph
import CreatorNodes
import CreatorSketch
import Testing

/// A 60 × 40 rectangle on `plane` (four shared-corner lines, horizontal and vertical, a fixed corner), with
/// dimensions `width` (exposed when `exposed`) and `height`.
func rectangleSketch(on plane: Plane = .xy, exposed: Bool = false) -> Sketch {
    var sketch = Sketch(plane: .fixed(plane))
    let corners = [Vector2(0, 0), Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)].map { sketch.addPoint($0) }
    let lines = (0..<4).map { sketch.addLine(from: corners[$0], to: corners[($0 + 1) % 4]) }
    sketch.add(.horizontal(lines[0]))
    sketch.add(.horizontal(lines[2]))
    sketch.add(.vertical(lines[1]))
    sketch.add(.vertical(lines[3]))
    sketch.add(.fix(corners[0], at: .zero))
    let width = sketch.addDimension(.length(lines[0]), value: 60)
    sketch.addDimension(.length(lines[1]), value: 40)
    sketch.renameDimension(width, to: "width")
    sketch.dimensions[width]?.isExposed = exposed
    return sketch
}

extension GraphBuilder {
    /// Sketch (holding `sketch`) → Extrude (10 mm) → Output. Returns the sketch node and the extrude.
    mutating func sketchedBox(_ sketch: Sketch = rectangleSketch(),
                              values: [SocketName: ConstantValue] = [:]) -> (sketch: Node, extrude: Node) {
        var settings = values
        settings[NodeSetting.sketch] = .sketch(sketch)
        let node = add(SketchNode.self, settings)
        let extrude = add(ExtrudeNode.self, ["distance": .number(10)], at: Vector2(240, 0))
        let output = add(OutputNode.self, at: Vector2(480, 0))
        wire(node, "profiles", to: extrude, "profile")
        wire(extrude, "solid", to: output, "solid")
        return (node, extrude)
    }
}
```

Modify `Tests/CreatorEditorTests/PerNodeSocketTests.swift` (apply this diff):

```diff
--- a/Tests/CreatorEditorTests/PerNodeSocketTests.swift
+++ b/Tests/CreatorEditorTests/PerNodeSocketTests.swift
@@ -60,4 +60,24 @@ struct PerNodeSocketTests {
         let rows = NodeRowModel.rows(for: node, shape: shape, graph: graph, registry: BuiltInNodes.registry)
         #expect(rows.first { $0.id == "in.d1" }?.value == ValueText.format(25, unit: .millimetres))
     }
+
+    /// The Sketch node declares an inspector ("Edit sketch"), which can't name its exposed dimensions, so they follow
+    /// it as number rows: outside sketch mode the inspector still edits them.
+    @Test func aSketchNodesInspectorHasEditSketchAndItsExposedDimensions() throws {
+        var sketch = Sketch()
+        let line = sketch.addLine(Vector2(0, 0), Vector2(25, 0))
+        let dimension = sketch.addDimension(.length(line), value: 25)
+        sketch.dimensions[dimension]?.isExposed = true
+        var node = BuiltInNodes.registry.makeNode(SketchNode.typeID)
+        node.inputValues[NodeSetting.sketch] = .sketch(sketch)
+        var graph = Graph()
+        graph.nodes[node.id] = node
+        let page = InspectorBuilder.page(graph: graph, selection: [node.id], registry: BuiltInNodes.registry, results: [:])
+        let rows = page.sections.flatMap(\.rows)
+        #expect(rows.contains { if case .button(_, .editSketch) = $0 { true } else { false } })
+        let field = try #require(rows.lazy.compactMap { row -> InputField? in
+            if case .number(let field) = row { field } else { nil }
+        }.first)
+        #expect(field.socket == "d1" && field.unit == .millimetres && field.value == .number(25))
+    }
 }
```

Modify `Tests/CreatorSketchEditorTests/SketchEditorModelTests.swift` (apply this diff):

```diff
--- a/Tests/CreatorSketchEditorTests/SketchEditorModelTests.swift
+++ b/Tests/CreatorSketchEditorTests/SketchEditorModelTests.swift
@@ -60,6 +60,46 @@ struct SketchEditorModelTests {
         #expect(SketchEditorModel(sketch: Sketch(), plane: .xy).statusText.hasPrefix("Nothing drawn yet"))
     }
 
+    /// The host reloads the stored sketch on every scene refresh; the stored sketch has no warm start yet, so it
+    /// differs from the solved one shown, but it is the one the editor was given, so nothing is dropped.
+    @Test func reloadingTheStoredSketchAgainKeepsAStrokeInProgress() {
+        let given = RectangleSketch().sketch
+        let model = SketchEditorModel(sketch: given, plane: .xy)
+        model.choose(.line)
+        model.click(at: Vector2(0, 60), tolerance: 1, modifiers: [])
+        model.reload(given, plane: .xy)
+        #expect(model.drawState != .idle)
+    }
+
+    /// Undo while the Dimension tool waits for its second pick: the first pick may name an entity the reloaded
+    /// sketch lacks, so it is dropped, and the next click starts afresh instead of being refused.
+    @Test func reloadingDropsAPendingDimensionPick() {
+        let model = SketchEditorModel(sketch: RectangleSketch(dimensioned: false).sketch, plane: .xy)
+        let host = RecordingHost(model)
+        model.choose(.dimension)
+        model.click(at: Vector2(30, 0.3), tolerance: 1, modifiers: [])
+        #expect(model.dimensionPick != nil)
+        model.reload(Sketch(), plane: .xy)
+        model.click(at: Vector2(30, 20), tolerance: 1, modifiers: [])
+        #expect(model.refusal == nil && host.commits.isEmpty)
+    }
+
+    /// Undo (⌘Z) in the middle of a point drag ends the drag: its next step and its release don't commit "Move
+    /// Point" over the undo.
+    @Test func reloadingEndsAPointDrag() {
+        let model = SketchEditorModel(sketch: RectangleSketch(dimensioned: false).sketch, plane: .xy)
+        let host = RecordingHost(model)
+        model.choose(.select)
+        #expect(model.beginDrag(at: Vector2(60.3, 40.2), tolerance: 1))
+        model.drag(to: Vector2(70, 50))
+        model.reload(RectangleSketch().sketch, plane: .xy)
+        model.drag(to: Vector2(75, 55))
+        model.endDrag(at: Vector2(80, 50))
+        #expect(host.commits.isEmpty)
+        let corner = model.sketch.position(of: RectangleSketch().corners[2]) ?? .zero
+        #expect((corner - Vector2(60, 40)).length < 1e-6, "the reloaded sketch, unmoved")
+    }
+
     @Test func theReadoutNamesTheFreedomOrTheProblem() {
         #expect(SketchEditorModel(sketch: RectangleSketch().sketch, plane: .xy).statusText == "Fully constrained")
         #expect(SketchEditorModel(sketch: RectangleSketch(dimensioned: false).sketch, plane: .xy).statusText
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter 'SketchModeTests|CreatorSketchEditorTests|PerNodeSocketTests'`

Expected: FAIL — the build fails: "type 'InspectorAction' has no member 'editSketch'" and "value of type 'AppModel' has no member 'sketch'".

- [ ] **Step 3: Add sketch mode to the app**

Modify `Sources/CreatorApp/AppModel+Picking.swift` (apply this diff):

```diff
--- a/Sources/CreatorApp/AppModel+Picking.swift
+++ b/Sources/CreatorApp/AppModel+Picking.swift
@@ -13,6 +13,8 @@ extension AppModel {
             beginPick(for: request.node)
         case .pickFacesInView:
             alert = .problem(AppProblem("Faces can't be picked yet", "No node in this version selects faces."))
+        case .editSketch:
+            beginSketch(for: request.node)
         }
     }
 
```

Modify `Sources/CreatorApp/AppModel+Scene.swift` (apply this diff):

```diff
--- a/Sources/CreatorApp/AppModel+Scene.swift
+++ b/Sources/CreatorApp/AppModel+Scene.swift
@@ -27,10 +27,12 @@ extension AppModel {
     }
 
     /// Shows the scene and the selected nodes' handles. While picking, only the solid being picked on, with the
-    /// picked edges selected, no handles and a crosshair pointer. A scene or handles equal to what's shown aren't sent again: the
-    /// observation also fires for canvas pans, camera settles and panel resizes, which change neither.
+    /// picked edges selected, no handles and a crosshair pointer. While sketching, the scene dimmed (ghosted, still
+    /// pickable) and no handles, and the open sketch follows its node. A scene or handles equal to what's shown aren't
+    /// sent again: the observation also fires for canvas pans, camera settles and panel resizes, which change neither.
     func refreshScene() {
-        let scene: [SceneItem]
+        refreshSketch()
+        var scene: [SceneItem]
         if viewport.isPicking != (pick != nil) { viewport.isPicking = pick != nil }
         if let pick {
             scene = [SceneItem(item: ViewportItem(solid: pick.solid, selectedEdges: Set(pick.picked)), source: pick.source)]
@@ -39,6 +41,13 @@ extension AppModel {
             scene = SceneBuilder.scene(shown: shown, graph: document.graph, results: document.results,
                                        lastGood: document.lastGoodOutputs, selection: editor.selection)
         }
+        if sketch != nil {
+            scene = scene.map { entry in
+                var dimmed = entry
+                dimmed.item.isGhost = true
+                return dimmed
+            }
+        }
         sources = Dictionary(scene.compactMap { entry in entry.source.map { (ObjectIdentifier(entry.item.solid), $0) } },
                              uniquingKeysWith: { first, _ in first })
         let items = scene.map(\.item)
@@ -46,7 +55,7 @@ extension AppModel {
             requestedScene = items
             viewport.show(items)
         }
-        let handles = pick == nil
+        let handles = pick == nil && sketch == nil
             ? HandleBuilder.handles(for: editor.selection, graph: document.graph, results: document.results, registry: registry)
             : []
         handleTargets = Dictionary(handles.map { ($0.handle.id, $0.target) }, uniquingKeysWith: { first, _ in first })
@@ -68,6 +77,7 @@ extension AppModel {
             _ = editor.dock
             _ = previewMode
             _ = pick
+            _ = sketch
             _ = panelWidth
             _ = panelHeight
             _ = themes.current
```

Create `Sources/CreatorApp/AppModel+Sketch.swift`:

```swift
import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorSketchEditor
import CreatorViewport

extension AppModel {
    static let noWiredPlane = "Its plane comes from the wire into “plane”, which has no result yet. Wire a plane that evaluates."

    /// "Edit sketch" (sketcher spec §8): opens the node's sketch in the viewport. The camera looks straight at its
    /// plane, orthographic; the model dims (ghosts) but stays in view; the editor takes the primary pointer and the
    /// top bar and inspector show its toolbar and lists. A pick in progress is cancelled, as it would be by any edit.
    public func beginSketch(for id: NodeID) {
        editor.commitPendingEntry()
        editor.closePalette()
        guard let node = document.graph.nodes[id], node.typeID == SketchNode.typeID,
              case .sketch(let stored)? = node.inputValues[NodeSetting.sketch] else { return }
        guard let plane = sketchPlane(of: node, stored) else {
            alert = .problem(AppProblem("The sketch can't be opened yet", Self.noWiredPlane))
            return
        }
        pick = nil
        sketch?.stop()
        let sketchEditor = SketchEditorModel(sketch: SketchStore.folded(stored, constants: node.inputValues), plane: plane,
                                             isReservedName: SketchNode.isReservedDimensionName)
        sketchEditor.events.committed = { [weak self] in self?.storeSketch($0) }
        sketchEditor.events.finished = { [weak self] in self?.finishSketch() }
        sketchEditor.events.dismissHostPopup = { [weak self] in self?.closePaletteOverSketch() ?? false }
        let session = SketchSession(node: id, editor: sketchEditor, viewport: viewport)
        sketch = session
        session.start()
        viewport.lookAt(plane, framing: Self.framing(sketchEditor.sketch, on: plane))
    }

    /// Leaves sketch mode: the viewport gets its pointer, its ground grid and its camera controls back, and the model
    /// is drawn solid again.
    public func finishSketch() {
        sketch?.stop()
        sketch = nil
    }

    /// Closes the add-node palette if it's open over the sketch; true when it was (Review Focus 1).
    func closePaletteOverSketch() -> Bool {
        guard editor.palette != nil else { return false }
        editor.closePalette()
        return true
    }

    /// Stores one editor commit in the node as one undo step (`SketchStore`).
    func storeSketch(_ commit: SketchCommit) {
        guard let session = sketch, let node = document.graph.nodes[session.node] else { return }
        do {
            try document.perform(.batch(SketchStore.commands(storing: commit.sketch, in: node, graph: document.graph)))
        } catch {
            alert = .problem(AppProblem("The sketch couldn't be changed", error.message))
        }
    }

    /// Keeps the open sketch in step with its node after undo, redo or any other edit; leaves sketch mode when the node
    /// is gone. Called from every scene refresh.
    func refreshSketch() {
        guard let session = sketch else { return }
        guard let node = document.graph.nodes[session.node], case .sketch(let stored)? = node.inputValues[NodeSetting.sketch] else {
            return finishSketch()
        }
        let plane = sketchPlane(of: node, stored) ?? session.editor.plane
        session.editor.reload(SketchStore.folded(stored, constants: node.inputValues), plane: plane)
    }

    /// The plane a sketch is drawn on: its own, or the plane wired into the node (from the wire's current result).
    func sketchPlane(of node: Node, _ sketch: Sketch) -> Plane? {
        switch sketch.plane {
        case .fixed(let plane):
            return plane
        case .wired:
            guard let link = document.graph.incomingLink(to: Endpoint(node: node.id, socket: "plane")),
                  case .plane(let plane)? = document.results[link.from.node]?.outputs?[link.from.socket]?.items.first else {
                return nil
            }
            return plane
        }
    }

    /// What entering a sketch frames: its points with a margin, or 100 mm around the plane's origin when it has fewer
    /// than two distinct points.
    static func framing(_ sketch: Sketch, on plane: Plane) -> BoundingBox {
        let points = sketch.entityIDs.compactMap { sketch.position(of: $0) }.map(plane.point)
        if let box = BoundingBox(points: points), box.size.length > 1e-6 {
            let margin = box.size * 0.1
            return BoundingBox(min: box.min - margin, max: box.max + margin)
        }
        return BoundingBox(points: [plane.point(Vector2(-50, -50)), plane.point(Vector2(50, 50))])
            ?? BoundingBox(min: plane.origin, max: plane.origin)
    }
}
```

Modify `Sources/CreatorApp/AppModel.swift` (apply this diff):

```diff
--- a/Sources/CreatorApp/AppModel.swift
+++ b/Sources/CreatorApp/AppModel.swift
@@ -31,6 +31,8 @@ public final class AppModel {
     public var previewMode: PreviewMode = .final
     /// "Pick edges in view…" in progress.
     public internal(set) var pick: PickSession?
+    /// A Sketch node being edited in the viewport (sketcher spec §8), or `nil`.
+    public internal(set) var sketch: SketchSession?
     public var alert: AppAlert?
     /// The docked graph panel's width (docked left) and height (docked at the bottom), in points.
     public internal(set) var panelWidth = AppLayout.defaultPanelWidth
@@ -79,6 +81,8 @@ public final class AppModel {
     func load(_ file: GraphFile, from url: URL?) {
         let parts = DocumentParts(file, registry: registry, kernel: kernel)
         pick = nil
+        sketch?.stop()
+        sketch = nil
         previewMode = .final
         document = parts.document
         editor = parts.editor
```

Create `Sources/CreatorApp/SketchSession.swift`:

```swift
import CreatorGraph
import CreatorKernel
import CreatorSketchEditor
import CreatorViewport
import Observation

/// One Sketch node being edited in the viewport (sketcher spec §8). It owns the editor, makes it the viewport's tool,
/// and keeps the viewport's overlay following the editor's drawing (hover, rubber band, solve) without a scene
/// refresh. `stop()` hands the viewport back.
@MainActor
public final class SketchSession {
    public let node: NodeID
    public let editor: SketchEditorModel
    private weak var viewport: ViewportModel?
    private var isFollowing = false
    private var refreshPending = false

    init(node: NodeID, editor: SketchEditorModel, viewport: ViewportModel) {
        self.node = node
        self.editor = editor
        self.viewport = viewport
    }

    /// Makes the editor the viewport's tool and starts drawing its overlay.
    func start() {
        isFollowing = true
        viewport?.tool = editor
        follow()
    }

    /// Gives the viewport back: no tool, no overlay.
    func stop() {
        isFollowing = false
        guard let viewport else { return }
        if viewport.tool === editor { viewport.tool = nil }
        viewport.showOverlay(ViewportOverlay())
    }

    /// Shows the editor's overlay and follows it once more: the first change schedules one redraw, which follows again.
    private func follow() {
        guard isFollowing, let viewport else { return }
        let overlay = withObservationTracking { editor.overlay } onChange: { [weak self] in
            // Observation calls this as a tracked property is about to change, on the main actor that changes it.
            MainActor.assumeIsolated { self?.scheduleFollow() }
        }
        viewport.showOverlay(overlay)
    }

    private func scheduleFollow() {
        guard !refreshPending else { return }
        refreshPending = true
        Task { [weak self] in
            self?.refreshPending = false
            self?.follow()
        }
    }

    /// Waits until the overlay shows the editor's latest state (tests).
    func settle() async {
        while refreshPending { await Task.yield() }
    }
}
```

Create `Sources/CreatorApp/SketchStore.swift`:

```swift
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch

/// The graph commands that store an edited sketch in its node as one undo step (S4 → S5 handoff):
/// - the whole sketch, as a `setInput` of the `sketch` setting;
/// - an exposed dimension's value lives in one place, the sketch, so a constant left under its socket name is cleared
///   (otherwise it would silently override later edits);
/// - a renamed exposed dimension takes its wire with it, and one no longer exposed drops its wire and constant.
/// Reserved names are never touched: they are never sockets (`SketchNode.isReservedDimensionName`).
enum SketchStore {
    static func commands(storing new: Sketch, in node: Node, graph: Graph) -> [GraphCommand] {
        let old: Sketch? = if case .sketch(let stored)? = node.inputValues[NodeSetting.sketch] { stored } else { nil }
        let oldNames = old.map(exposedNames) ?? [:]
        let newNames = exposedNames(new)
        var before: [GraphCommand] = []
        var after: [GraphCommand] = []
        for id in oldNames.keys.sorted() {
            guard let oldName = oldNames[id], newNames[id] != oldName else { continue }
            if let link = graph.incomingLink(to: Endpoint(node: node.id, socket: oldName)) {
                before.append(.disconnect(link))
                if let newName = newNames[id] {
                    after.append(.connect(Link(from: link.from, to: Endpoint(node: node.id, socket: newName))))
                }
            }
            if node.inputValues[oldName] != nil { after.append(.setInput(node.id, oldName, nil)) }
        }
        for id in newNames.keys.sorted() {
            guard let name = newNames[id], case .number? = node.inputValues[name] else { continue }
            after.append(.setInput(node.id, name, nil))
        }
        return before + [.setInput(node.id, NodeSetting.sketch, .sketch(new))] + after
    }

    /// The sketch with each exposed dimension's constant (left under its socket name) folded into its value, so the
    /// editor shows what the node evaluates.
    static func folded(_ sketch: Sketch, constants: [SocketName: ConstantValue]) -> Sketch {
        var folded = sketch
        for (id, name) in exposedNames(sketch) {
            if case .number(let value)? = constants[name] { folded.dimensions[id]?.value = value }
        }
        return folded
    }

    /// Each exposed dimension's socket name, leaving out the reserved ones.
    static func exposedNames(_ sketch: Sketch) -> [DimensionID: SocketName] {
        var names: [DimensionID: SocketName] = [:]
        for (id, dimension) in sketch.dimensions where dimension.isExposed && !SketchNode.isReservedDimensionName(dimension.name) {
            names[id] = SocketName(dimension.name)
        }
        return names
    }
}
```

Modify `Sources/CreatorGraph/InspectorAction.swift` (apply this diff):

```diff
--- a/Sources/CreatorGraph/InspectorAction.swift
+++ b/Sources/CreatorGraph/InspectorAction.swift
@@ -1,4 +1,6 @@
 /// An inspector button's effect, carried out by the editor or viewport.
 public enum InspectorAction: String, Sendable, Codable {
     case pickEdgesInView, pickFacesInView
+    /// "Edit sketch" (sketcher spec §8): the app shell opens the node's sketch in the viewport.
+    case editSketch
 }
```

Modify `Sources/CreatorNodes/Profiles/SketchNode.swift` (apply this diff):

```diff
--- a/Sources/CreatorNodes/Profiles/SketchNode.swift
+++ b/Sources/CreatorNodes/Profiles/SketchNode.swift
@@ -27,12 +27,20 @@ public enum SketchNode: NodeDefinition {
         SocketSpec("measurements", .number),
     ]
     public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.sketch: .sketch(Sketch())]
+    /// "Edit sketch" opens the sketch editor in the viewport (sketcher spec §8, S5).
+    public static let inspector = [InspectorSection(title: "Sketch", controls: [.button(title: "Edit sketch", action: .editSketch)])]
 
     static let missingSketch = "This sketch's drawing is missing. Undo the last change, or add a new Sketch."
     static let unreadableSketch = "This sketch's drawing can't be read. Undo the last change, or add a new Sketch."
     static let wiredPlaneMissing = "Wire a plane into “plane”: this sketch is drawn on the wired plane."
     static let ignoredPlane = "“plane” is wired, but this sketch is drawn on its own plane, so the wire has no effect."
 
+    /// True for a name an exposed dimension can't take: a fixed input, a setting or a projection setting (the sketch
+    /// editor refuses it when renaming; S4 → S5 handoff).
+    public static func isReservedDimensionName(_ name: String) -> Bool {
+        SketchSockets.isReserved(name)
+    }
+
     public static func inputs(for node: Node) -> [SocketSpec] {
         guard case .sketch(let sketch)? = node.inputValues[NodeSetting.sketch] else { return inputs }
         return inputs + SketchSockets.exposed(sketch).map(\.spec)
```

Modify `Sources/CreatorSketchEditor/SketchEditorEvents.swift` (apply this diff):

```diff
--- a/Sources/CreatorSketchEditor/SketchEditorEvents.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorEvents.swift
@@ -4,6 +4,10 @@ public struct SketchEditorEvents {
     public var committed: @MainActor (SketchCommit) -> Void = { _ in }
     /// Finish (⏎, Esc with nothing in progress, or the Finish button): the host leaves sketch mode.
     public var finished: @MainActor () -> Void = {}
+    /// Asked first by Esc and Finish: the host closes a popup of its own that is open over the sketch (the add-node
+    /// palette) and returns true, and the key does nothing else. The sketch's keys are button shortcuts, which run
+    /// before the host's own keys, so without this Esc would end sketch mode under an open palette.
+    public var dismissHostPopup: @MainActor () -> Bool = { false }
 
     public init() {}
 }
```

Modify `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift` (apply this diff):

```diff
--- a/Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift
@@ -28,8 +28,10 @@ extension SketchEditorModel {
         commit(edited, makeConstruction ? "Make Construction" : "Make Normal Geometry")
     }
 
-    /// Esc: ends the stroke in progress; with none, clears the selection; with nothing selected, finishes the sketch.
+    /// Esc: closes the host's popup if one is open (`SketchEditorEvents.dismissHostPopup`); else ends the stroke in
+    /// progress; with none, clears the selection; with nothing selected, finishes the sketch.
     public func escape() {
+        if events.dismissHostPopup() { return }
         if drawState != .idle || dimensionPick != nil {
             drawState = .idle
             dimensionPick = nil
@@ -41,8 +43,10 @@ extension SketchEditorModel {
         }
     }
 
-    /// ⏎ or the Finish button: leaves sketch mode (the host does), dropping any stroke in progress.
+    /// ⏎ or the Finish button: leaves sketch mode (the host does), dropping any stroke in progress; with the host's
+    /// popup open, it only closes that.
     public func finish() {
+        if events.dismissHostPopup() { return }
         drawState = .idle
         preview = .none
         events.finished()
```

Modify `Sources/CreatorSketchEditor/SketchEditorModel.swift` (apply this diff):

```diff
--- a/Sources/CreatorSketchEditor/SketchEditorModel.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel.swift
@@ -39,39 +39,49 @@ public final class SketchEditorModel {
     var dimensionPick: SketchEntityID?
     /// Names an exposed dimension can't take (the Sketch node's own inputs and settings). The host provides it.
     @ObservationIgnored let isReservedName: @MainActor (String) -> Bool
+    /// The sketch as the host last stored it (given, reloaded or committed), before this editor's solve: `reload(_:)`
+    /// compares against it, so the host can reload on every refresh without dropping a stroke in progress.
+    @ObservationIgnored var stored: Sketch
 
     @ObservationIgnored public var events = SketchEditorEvents()
 
     public init(sketch: Sketch, plane: Plane, isReservedName: @escaping @MainActor (String) -> Bool = { _ in false }) {
         self.plane = plane
         self.isReservedName = isReservedName
+        stored = sketch
         let solution = SketchSolver.solve(sketch)
         self.solution = solution
         self.sketch = Self.remembering(sketch, solution)
     }
 
-    /// Shows a sketch that came from the host (undo, redo, or a file change), unless it's the one already shown.
-    public func reload(_ stored: Sketch, plane newPlane: Plane) {
+    /// Shows a sketch that came from the host (undo, redo, or a file change), unless it is the one the host last stored.
+    public func reload(_ newSketch: Sketch, plane newPlane: Plane) {
         if newPlane != plane { plane = newPlane }
-        guard stored != sketch else { return }
-        let solved = SketchSolver.solve(stored)
+        guard newSketch != stored else { return }
+        stored = newSketch
+        let solved = SketchSolver.solve(newSketch)
         solution = solved
-        sketch = Self.remembering(stored, solved)
+        sketch = Self.remembering(newSketch, solved)
         selection = selection.filter { sketch.entities[$0] != nil }
         if let hovered, sketch.entities[hovered] == nil { self.hovered = nil }
-        // A stroke may hold points the stored sketch no longer has.
+        // A stroke, a Dimension tool's first pick or a point drag may name entities the stored sketch no longer has,
+        // and a drag's release would commit over the undo: all three end here.
         drawState = .idle
         preview = .none
+        dimensionPick = nil
+        dragged = nil
+        dragOrigin = nil
     }
 
     /// Takes `edited` as the sketch, solved and remembered, and hands it to the host as one undo step.
     func commit(_ edited: Sketch, _ description: String) {
         let solved = SketchSolver.solve(edited)
-        let stored = Self.remembering(edited, solved)
+        let remembered = Self.remembering(edited, solved)
         solution = solved
-        sketch = stored
+        sketch = remembered
+        stored = remembered
         refusal = nil
-        events.committed(SketchCommit(sketch: stored, description: description))
+        events.committed(SketchCommit(sketch: remembered, description: description))
     }
 
     /// `sketch` with `solution` as its warm start when the solve is usable (S4 → S5 handoff: the node then
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter 'SketchModeTests|CreatorSketchEditorTests|PerNodeSocketTests'`

Expected: PASS (exit 0, no line says "recorded an issue" or "failed after").

- [ ] **Step 5: Full verification**

Run, from the repo root: `swift build --build-tests 2>&1 | grep -E "(error|warning):" | grep -v "ld: warning"` (expected: nothing new; master's one test warning, `ContextMenuTests.swift:96` "'underPointer' mutated after capture", shows only when that file recompiles), then `swift test` (expected: exit 0, no "recorded an issue" / "failed after" lines, and the "Test run with N tests" lines sum to **1161 (master + 76)**), then `swiftlint lint --strict` (zero violations).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorApp/AppModel+Picking.swift Sources/CreatorApp/AppModel+Scene.swift Sources/CreatorApp/AppModel+Sketch.swift Sources/CreatorApp/AppModel.swift Sources/CreatorApp/SketchSession.swift Sources/CreatorApp/SketchStore.swift Sources/CreatorGraph/InspectorAction.swift Sources/CreatorNodes/Profiles/SketchNode.swift Sources/CreatorSketchEditor/SketchEditorEvents.swift Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift Sources/CreatorSketchEditor/SketchEditorModel.swift Tests/CreatorAppTests/SketchModeTests.swift Tests/CreatorAppTests/Support/SketchGraph.swift Tests/CreatorEditorTests/PerNodeSocketTests.swift Tests/CreatorSketchEditorTests/SketchEditorModelTests.swift
git commit -m "feat(app): sketch mode — edit a Sketch node in the viewport, one undo step per edit"
```


---

### Task 11: App: the views in the top bar and inspector; docs

While sketching the top bar holds `SketchToolbar` (instead of the name, Preview, Undo, Redo and Export) and the inspector dock holds `SketchInspector` (keeping the `Panel` key context, so F, + and − type into its fields), each in `SketchChrome`: the glass over an opaque backdrop. MetalUI gives a painted view (the glass, a label, a spacer) no hitbox, so without it a click in a gap between the toolbar's buttons or on an inspector label reaches the viewport beneath, which the editor claims while sketching: it would draw hidden geometry or clear the selection, and hover would drive the rubber band under the panel. The backdrop is the add-node palette's and the graph-input track's (`Color.clear`, `.contentShape(Rectangle())`, an empty `DragGesture(minimumDistance: 0)`, `.onScrollWheel { _ in true }`), attached with `.background` so it is exactly the glass's size. `AppRoot` is untouched. Then the documents: CLAUDE.md's module notes, the sketcher spec's Errata (S5a), the gap S5-a (cross-referencing the graph-input track's GI-a), human checks group S5, the roadmap row and the handoff's S5a → S5b section.

**Files:**
- Modify: `CLAUDE.md`
- Modify: `Sources/CreatorApp/InspectorDock.swift`
- Create: `Sources/CreatorApp/SketchChrome.swift`
- Modify: `Sources/CreatorApp/TopBar.swift`
- Modify: `docs/metalui-gaps.md`
- Modify: `docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md`
- Modify: `docs/superpowers/roadmap.md`
- Modify: `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md`
- Modify: `docs/verification/human-checks.md`
- Create: `Tests/CreatorAppTests/SketchModeRenderTests.swift`

**Interfaces:**
- Consumes: `SketchToolbar`, `SketchInspector` (Task 9), `AppModel.sketch` (Task 10), `GlassPanel` (CreatorEditor); MetalUI `.background(alignment:content:)`, `.contentShape(_:)`, `DragGesture(minimumDistance:)`, `.onScrollWheel(perform:)`.
- Produces: Internal `SketchChrome<Body>: Component` (CreatorApp). No public API.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorAppTests/SketchModeRenderTests.swift`:

```swift
import CreatorGraph
import CreatorKernel
import CreatorNodes
import MetalUI
import MetalUIText
import Testing
@testable import CreatorApp

/// Headless frames of the window in sketch mode: the top bar holds the sketch toolbar and the inspector the sketch's
/// lists, in every dock. Looks, keys and the chrome's opacity to the pointer are human checks (group S5).
@MainActor
struct SketchModeRenderTests {
    @Test(arguments: [DockSide.left, .bottom, .hidden])
    func theWindowDrawsInSketchMode(_ dock: DockSide) async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch(exposed: true))
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph, viewState: ViewState(dock: dock)))
        await app.settle()
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        #expect(app.sketch != nil)
        let input = AppInput(model: app)
        let scene = renderFrame({ ZStack { AppRoot(model: app, input: input) } }, size: Size(width: Pixels(1400), height: Pixels(900)),
                                scaleFactor: 2, textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        #expect(scene.surfaces.count == 1, "the viewport's Metal surface")
        #expect(!scene.glyphs.isEmpty)
    }

    /// The top bar and the inspector swap their views in sketch mode, and back when it ends: each draws other text
    /// (the toolbar's buttons for the document's name and menus; the sketch's lists for the node's rows).
    @Test func theTopBarAndTheInspectorSwapInTheSketchViews() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch(exposed: true))
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: builder.graph))
        await app.settle()
        app.editor.selection = [box.sketch.id]
        let before = (bar: glyphCount { TopBar(model: app) }, inspector: glyphCount { InspectorDock(model: app) })
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        #expect(glyphCount { TopBar(model: app) } != before.bar)
        #expect(glyphCount { InspectorDock(model: app) } != before.inspector)
        app.finishSketch()
        #expect(glyphCount { TopBar(model: app) } == before.bar)
        #expect(glyphCount { InspectorDock(model: app) } == before.inspector)
    }

    func glyphCount<View: ElementGroup>(_ view: () -> View) -> Int {
        let content = view()
        return renderFrame({ ZStack { content } }, size: Size(width: Pixels(1400), height: Pixels(900)), scaleFactor: 2,
                           textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024)).glyphs.count
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter SketchModeRenderTests`

Expected: FAIL — `theTopBarAndTheInspectorSwapInTheSketchViews` records two issues (the top bar's and the inspector's glyph counts are the same in sketch mode as before it), while `theWindowDrawsInSketchMode` passes either way (it pins the window building in sketch mode in every dock). The chrome's opacity to the pointer has no headless check (MetalUI has no public hit test; gap M6-e): human check S5-8.

- [ ] **Step 3: Swap the views in, then write the docs**

Modify `CLAUDE.md` (apply this diff):

```diff
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -6,7 +6,7 @@ This file provides guidance to Claude Code (claude.ai/code) when working with co
 
 MetalCreator is a node-based parametric CAD app for macOS built on MetalUI (`../MetalUI`, joined in M4).
 The binding spec is `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`; milestone
-plans live in `docs/superpowers/plans/`. M0 (OCCT probe), M1 (graph engine), M2 (OCCT kernel), M3 (the 26 nodes), S3 (profile holes) and S4 (the Sketch and Plane from Face nodes) are done. M4 (viewport) code is done; its human checks (group V in `docs/verification/human-checks.md`) are pending. M5 (graph panel and inspector) code is done; its human checks (group M5 in `docs/verification/human-checks.md`) are pending.
+plans live in `docs/superpowers/plans/`. M0 (OCCT probe), M1 (graph engine), M2 (OCCT kernel), M3 (the 26 nodes), S3 (profile holes) and S4 (the Sketch and Plane from Face nodes) are done. S5a (the sketch editor in the viewport: sketch mode, drawing, constraints, dimensions, live solve) code is done; its human checks (group S5) are pending; S5b (Project, New sketch on face, trim/fillet/mirror/pattern tools) is next. M4 (viewport) code is done; its human checks (group V in `docs/verification/human-checks.md`) are pending. M5 (graph panel and inspector) code is done; its human checks (group M5 in `docs/verification/human-checks.md`) are pending.
 M6 (app shell) code is done; its human checks (group M6) are pending.
 Editor polish (the floating add-node palette and the node library) code is done; its human checks (group EP) are pending.
 Packaging (`scripts/package-app.sh`, `docs/packaging.md`) is done; its human checks (group P) are pending.
@@ -35,6 +35,12 @@ Module boundaries (dependency order):
   `Palette(themes)` (Dracula without a store); the viewport draws `ViewportModel.theme`, which the app shell sets.
   Themes are app-level, never in `.mcgraph`. Tests: `swift test --filter CreatorStyleTests`.
 - `CreatorViewport`: the 3D viewport on MetalUI's `MetalView`.
+  - A host takes the primary pointer through `ViewportModel.tool` (`ViewportTool`: hover, clicks, and plain primary
+    drags it claims, each with a `ViewportProjector` for screen → plane), and draws over the scene with
+    `showOverlay(_:)` (`ViewportOverlay`: world-space lines and points in `OverlayTint` roles, dashed construction, and
+    a `gridPlane` that replaces the ground grid). Navigation (right/middle drags, Shift/⌥ drags, scroll, pinch, the
+    cube, handles) always stays the viewport's; the face menu offers only Look At while a tool is set.
+    `lookAt(_ plane:framing:)` faces a plane, orthographic.
   - `ViewportModel` (`@MainActor @Observable`, testable without a GPU) owns the camera, picking, the view cube,
     the context menu and handles. `ViewportRenderer`/`ViewportPicker` are the Metal side. `ViewportView` is the
     MetalUI glue.
@@ -44,7 +50,21 @@ Module boundaries (dependency order):
   behaviour (selection, canvas transform, dock transpose, hit testing, wiring, clipboard, palette, inspector edits);
   views are thin MetalUI `Component`s. Depends on Graph/Kernel/Geometry, CreatorStyle and MetalUI — **not** on `CreatorNodes`.
   Stopgap input (pending MetalUI C7) lives only in `GraphPanelInput`.
-- `CreatorApp` + `MetalCreatorApp`: the app shell, the only target joining Graph, Nodes, Viewport and Editor.
+- `CreatorSketchEditor`: the sketch editor (sketcher spec §8). `@MainActor @Observable SketchEditorModel` holds the
+  sketch being edited, its live solve (`solve(_:dragging:)` per drag step), the tool and its stroke, the selection, and
+  the inspector's rows; it is the viewport's `ViewportTool` and builds its `ViewportOverlay`. Graph-free: every edit is
+  a `SketchCommit` (the whole sketch, solved and remembered) through `events.committed`, which the host stores.
+  Depends on CreatorSketch, CreatorViewport, CreatorGeometry, CreatorStyle and MetalUI only. Its keys are toolbar
+  button shortcuts (L, A, C, D, X, ⌫, ⌦, ⏎, Esc; ⌦ and Esc are hidden buttons), which run before the graph panel's
+  `onInput` keys; the Delete button and the hidden ⌦ one are never disabled, so ⌫ and ⌦ never fall through to deleting
+  nodes (the graph's selection is the Sketch node being edited). Tests: `swift test --filter CreatorSketchEditorTests`.
+- `CreatorApp` + `MetalCreatorApp`: the app shell, the only target joining Graph, Nodes, Viewport and the editors.
+  Sketch mode is `AppModel.sketch` (`SketchSession`: the editor as the viewport's tool, its overlay followed), entered
+  by the Sketch node's "Edit sketch" (`InspectorAction.editSketch`); the scene is ghosted and handle-free meanwhile,
+  the top bar holds `SketchToolbar` and the inspector `SketchInspector`, each in `SketchChrome` (glass over an opaque
+  backdrop, so a click on the chrome never reaches the editor beneath). `SketchStore` turns a commit into one batch:
+  the `sketch` setting, a cleared constant under each exposed dimension's name (the value lives in the sketch alone),
+  and a renamed exposed dimension's wire moved (dropped when it stops being exposed).
   `@MainActor @Observable AppModel` owns the open document's parts (document, editor, graph input, viewport; replaced
   together on New and Open), turns results into `ViewportItem`s (`SceneBuilder`) and `HandleSpec`s into
   `ViewportHandle`s (`HandleBuilder`), turns viewport events into graph commands (picking writes Edges by Tag rules),
@@ -63,7 +83,8 @@ Edge picks (`EdgePick`) match by tag subsets per side and warn on count drift; s
 A `Segment2D.arc` with `end < start` runs clockwise (a sketch region's notch); the shim builds it reversed and
 `length` is positive. Edges carry `EdgeInfo.curve` (`EdgeCurve`, lines and circles) for sketch projection; a
 `FacePick` names faces by tag subset like `EdgePick`. The Sketch node solves on every evaluation from the stored
-sketch's warm start; writing `Sketch.remember` back into the setting is the editor's job (S5).
+sketch's warm start; the editor writes `Sketch.remember` back into the setting with every commit (S5a). Node readers
+of sockets use `inputs(for: node)` (canvas shape and rows, inspector, handles), never the static `inputs`.
 `Profile2D` is `outer` + `holes` (loop 0 = outer, n = hole n); `segments` is the outer loop only, so code that
 rebuilds a profile must keep `holes` (copy it and change `plane`, don't re-init from `segments`). Side tags are
 `.side(loop:segment:)` and `.side(segment:)` means loop 0; never match `.side` with one binding (`case .side(let s)`
@@ -115,6 +136,7 @@ swift run GraphPanelPreview                   # graph panel + inspector, for doc
 swift run MetalCreatorApp [file.mcgraph]   # the app (docs/verification/human-checks.md, group M6)
 swift test --filter CreatorAppTests        # app model, scene, handles, picking, files, export, input; AppAcceptanceTests runs §7.2 on OCCT
 swift test --filter CreatorStyleTests      # colour themes: the built-ins, legibility, ThemeStore
+swift test --filter CreatorSketchEditorTests   # the sketch editor: tools, inference, constraints, dimensions, overlay
 scripts/package-app.sh                     # dist/MetalCreator.app: release build, OCCT bundled, signed ad hoc, verified (docs/packaging.md)
 scripts/verify-app.sh [path.app]           # re-check a packaged app: signature, no Homebrew links, self-test with Homebrew unreadable
 swift run MetalCreatorApp --self-test      # the same headless checks, unpackaged
```

Modify `Sources/CreatorApp/InspectorDock.swift` (apply this diff):

```diff
--- a/Sources/CreatorApp/InspectorDock.swift
+++ b/Sources/CreatorApp/InspectorDock.swift
@@ -1,14 +1,20 @@
 import CreatorEditor
+import CreatorSketchEditor
 import MetalUI
 
 /// The context inspector, contributing the `AppKeyContext.panel` key context so the viewport's F, + and − type
-/// into its number fields (gap M4-a).
+/// into its number fields (gap M4-a). While a sketch is open it shows the sketch's lists instead (sketcher spec §8), in
+/// chrome opaque to the pointer (`SketchChrome`).
 struct InspectorDock: Component {
     let model: AppModel
 
     var content: some ElementGroup {
         Stack(alignment: .topLeading) {
-            InspectorPanel(model: model.editor)
+            if let sketch = model.sketch {
+                SketchChrome { SketchInspector(model: sketch.editor) }
+            } else {
+                InspectorPanel(model: model.editor)
+            }
         }
         .keyContext(AppKeyContext.panel)
     }
```

Create `Sources/CreatorApp/SketchChrome.swift`:

```swift
import CreatorEditor
import MetalUI

/// The glass around the sketch toolbar and the sketch inspector, opaque to the pointer. The glass only paints, and
/// MetalUI gives a painted view no hitbox (its divergence 141), so without the backdrop a click in a gap between the
/// toolbar's buttons or on an inspector label would reach the viewport beneath, which the sketch editor claims: it
/// would draw hidden geometry, or clear the selection, and hover would drive the rubber band under the panel. The
/// backdrop is the add-node palette's (a content shape with an empty drag, claiming every scroll; gap EP-b), sized to
/// the glass by `.background`. The buttons and fields are drawn above it and take their own input.
struct SketchChrome<Body: ElementGroup>: Component {
    let body: Body

    init(@ElementBuilder _ body: () -> Body) {
        self.body = body()
    }

    var content: some ElementGroup {
        GlassPanel { body }
            .background {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: Pixels(0)))
                    .onScrollWheel { _ in true }
            }
    }
}
```

Modify `Sources/CreatorApp/TopBar.swift` (apply this diff):

```diff
--- a/Sources/CreatorApp/TopBar.swift
+++ b/Sources/CreatorApp/TopBar.swift
@@ -1,33 +1,39 @@
 import CreatorEditor
 import CreatorKernel
+import CreatorSketchEditor
 import CreatorStyle
 import MetalUI
 
-/// The glass top bar (spec §6.1): the document's name, the Preview menu, Undo, Redo and Export.
+/// The glass top bar (spec §6.1): the document's name, the Preview menu, Undo, Redo and Export. While a sketch is
+/// open it holds the sketch toolbar instead (sketcher spec §8: "Toolbar (glass, top)"), in chrome opaque to the pointer.
 struct TopBar: Component {
     let model: AppModel
     @Environment(ThemeStore.self) var themes: ThemeStore?
 
     var content: some ElementGroup {
-        GlassPanel {
-            HStack(spacing: Pixels(10)) {
-                Text(model.isEdited ? "\(model.displayName) — Edited" : model.displayName)
-                    .font(.headline)
-                    .foregroundStyle(Palette(themes).primaryText.color)
-                Spacer()
-                Picker("Preview", selection: Binding(get: { model.previewMode }, set: { model.previewMode = $0 })) {
-                    ForEach(PreviewMode.allCases, id: \.self) { mode in
-                        Text(mode.title).tag(mode)
+        if let sketch = model.sketch {
+            SketchChrome { SketchToolbar(model: sketch.editor) }
+        } else {
+            GlassPanel {
+                HStack(spacing: Pixels(10)) {
+                    Text(model.isEdited ? "\(model.displayName) — Edited" : model.displayName)
+                        .font(.headline)
+                        .foregroundStyle(Palette(themes).primaryText.color)
+                    Spacer()
+                    Picker("Preview", selection: Binding(get: { model.previewMode }, set: { model.previewMode = $0 })) {
+                        ForEach(PreviewMode.allCases, id: \.self) { mode in
+                            Text(mode.title).tag(mode)
+                        }
+                    }
+                    .pickerStyle(.menu)
+                    Button("Undo") { model.undo() }
+                        .disabled(!model.document.canUndo)
+                    Button("Redo") { model.redo() }
+                        .disabled(!model.document.canRedo)
+                    Menu("Export") {
+                        Button("STEP…") { model.withFilePicker { await model.exportDocument(.step, using: $0) } }
+                        Button("STL…") { model.withFilePicker { await model.exportDocument(.stl, using: $0) } }
                     }
-                }
-                .pickerStyle(.menu)
-                Button("Undo") { model.undo() }
-                    .disabled(!model.document.canUndo)
-                Button("Redo") { model.redo() }
-                    .disabled(!model.document.canRedo)
-                Menu("Export") {
-                    Button("STEP…") { model.withFilePicker { await model.exportDocument(.step, using: $0) } }
-                    Button("STL…") { model.withFilePicker { await model.exportDocument(.stl, using: $0) } }
                 }
             }
         }
```

Modify `docs/metalui-gaps.md` (apply this diff):

```diff
--- a/docs/metalui-gaps.md
+++ b/docs/metalui-gaps.md
@@ -313,3 +313,18 @@ Labelled P-a… so they don't clash with the C7 items, M4-a…, M5-a…, M6-a…
   `Contents/Resources/Licenses/MetalUI/` (checked by `scripts/verify-app.sh`).
 - **M6-d, now visible.** The packaged app declares `.mcgraph` (owner, exported type), so a double-click in Finder
   opens MetalCreator, but not the file: no open-document event reaches the app (human check P2).
+
+## Hit by the sketch editor (S5a), 2026-10-09
+
+Labelled S5-a… so they don't clash with the labels above.
+
+- **S5-a. No modifiers on a hover (and, as GI-a, on a tap).** Sketcher spec §8: holding ⌘ suppresses constraint
+  inference while drawing (a line's end snapping horizontal or vertical), and the rubber band previews what a click
+  would infer, so both the click and the hover need the modifiers held. The tap half is the graph-input track's
+  **GI-a** (`SpatialTapGesture.Value` has only `location`), one request with this one. What S5-a adds is the hover:
+  `onContinuousHover`'s phase carries no modifiers, and nothing reports a modifier change while the pointer is still
+  (SwiftUI apps on macOS read `NSEvent.modifierFlags` or `onModifierKeysChanged(mask:initial:_:)`).
+  `DragGesture.Value.modifiers` (C7's `CI-G`) covers drags only. Stopgap: none. `ViewportModel.click(at:modifiers:)`
+  and the editor take modifiers, and `ViewportView` passes `[]`, so ⌘ doesn't suppress inference yet (human check
+  S5-3 records it). The Select tool's clicks toggle membership instead of needing ⇧. Wanted, as one request with GI-a:
+  tap modifiers (GI-a), and modifiers on hover or SwiftUI's `onModifierKeysChanged(mask:initial:_:)`.
```

Modify `docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md` (apply this diff):

```diff
--- a/docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md
+++ b/docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md
@@ -72,3 +72,14 @@ These are the items later milestones must pick up (S3 has merged; its items are
   geometry, if the editor can tell them apart.
 - Constraints that hold whatever the geometry is (concentric on circles sharing a centre) are dropped by the solver,
   not reported; the editor may skip creating them when it infers constraints.
+
+## S5a → S5b (plan `docs/superpowers/plans/2026-10-09-sketcher-s5-editor.md`)
+- Project: give `CreatorSketchEditor` CreatorKernel, add a Project tool that asks the host for model-edge picks (the
+  viewport's ID-buffer `pick`, so `ViewportTool.clicked` returning false lets `ViewportEvents.clicked` report the edge),
+  and have `SketchStore` add `NodeSetting.projection(reference)` and wire the solid into `references` in the same batch.
+- "New sketch on face": the face context menu item (`ViewportMenuItem`) and a batch that adds Plane from Face + Sketch
+  (`.wired`); `AppModel.sketchPlane(of:_:)` already reads a wired plane from the upstream result.
+- Double-click a Sketch node to edit: the canvas's tap gesture in `GraphPanelInput` (the graph-input track's file).
+- Trim, Fillet, Mirror, Pattern call `SketchCommands` and route `SketchCommandError.message` into `refusal`.
+- ⌘ to suppress inference and ⇧-click to extend the selection wait for gap S5-a (hover modifiers) and GI-a (tap
+  modifiers), one MetalUI request.
```

Modify `docs/superpowers/roadmap.md` (apply this diff):

```diff
--- a/docs/superpowers/roadmap.md
+++ b/docs/superpowers/roadmap.md
@@ -26,7 +26,7 @@ Status key: ✅ done · 🔄 in progress · ⏳ ready to start · 🔒 blocked (
 
 | # | Item | Status | Notes |
 |---|---|---|---|
-| 6 | Constraint sketcher: Sketch node, 2D editor, pure-Swift constraint solver | 🔄 spec `2026-10-08-constraint-sketcher-design.md`; S3 ✅ merged; S1+S2 ✅ merged (CreatorSketch: solver, regions, commands); S4 ✅ merged 2026-10-09 (Sketch node, Plane from Face, projection, format 4; human check S4-1 pending); S5 (editor in the viewport) ⏳ ready to plan (handoff: notes/2026-10-08-sketcher-s1-s2-handoff.md, "S4 → S5") | Rules for S4 regions: holes sorted, loops counter-clockwise, deterministic start segment (spec §5) |
+| 6 | Constraint sketcher: Sketch node, 2D editor, pure-Swift constraint solver | 🔄 spec `2026-10-08-constraint-sketcher-design.md`; S3 ✅ merged; S1+S2 ✅ merged (CreatorSketch: solver, regions, commands); S4 ✅ merged 2026-10-09 (Sketch node, Plane from Face, projection, format 4; human check S4-1 pending); S5a (editor in the viewport: sketch mode, drawing, constraints, dimensions, live solve; plan `2026-10-09-sketcher-s5-editor.md`) ✅ code done, human checks S5 pending; S5b (Project, New sketch on face, double-click to edit, trim/fillet/mirror/pattern tools, inference glyphs and tangent/point-on inference, dimension labels in the view, region fill) ⏳ | Rules for S4 regions: holes sorted, loops counter-clockwise, deterministic start segment (spec §5) |
 | 7 | Patterns, fields, nested data trees, surface textures, lattices | 💬 | After the slice |
 | 8 | Variants and versions UI | 💬 | Graph parameters already model variants |
 | — | Packaging: bundle OCCT dylibs into a signed `.app` | ✅ code done; human checks P pending | Spec §11, Errata (Packaging); `scripts/package-app.sh`, `docs/packaging.md`. Ad hoc by default, Developer ID via `METALCREATOR_SIGN_IDENTITY`; notarization is manual; no icon yet; needs macOS 27 while Homebrew's bottles do; MetalUI gap P-a fixed (MetalUI 67a579e; its notices are bundled) |
```

Modify `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md` (apply this diff):

```diff
--- a/docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md
+++ b/docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md
@@ -310,3 +310,36 @@ All tests use Swift Testing.
   `plane` warns that the wire has no effect.
 - §7's evaluate does not store the solve's warm start: it solves from the stored sketch every time, so results don't
   depend on evaluation history. S5's editor writes `Sketch.remember(_:)` into the setting after each edit.
+
+## Errata (S5a)
+
+- §8 is split: S5a (plan `2026-10-09-sketcher-s5-editor.md`) has sketch mode, Line, Arc (centre, start, end), Circle,
+  Point, construction, the constraint buttons, Dimension, the inspector's lists, point drags and the live solve. S5b
+  has Project, "New sketch on face", double-click to enter, Trim, Fillet, Mirror, Pattern, 3-point arcs, tangent and
+  point-on inference with glyphs, dimension labels in the view and the region fill.
+- §2's `CreatorSketchEditor` depends on CreatorSketch, CreatorViewport, CreatorGeometry, CreatorStyle (the theme's
+  colours, which postdate the table) and MetalUI; CreatorKernel joins with Project (S5b). The inspector sections are
+  its views (`SketchInspector`, `SketchToolbar`); the app shell gives them their glass and places them.
+- §8's entering: "Edit sketch" is the Sketch node's inspector button (`InspectorAction.editSketch`). The model is
+  ghosted (the viewport's 40%, not 30%) and stays pickable; the plane's grid replaces the ground grid. Leaving keeps
+  the camera where it is.
+- §8's toolbar is one row in the top bar (it replaces the document's name, Preview, Undo, Redo and Export while
+  sketching); the constraint buttons are in the inspector, three to a row. Keys are button shortcuts: L, A, C, D, X,
+  ⌫ and ⌦ (Delete), ⏎ (Finish) and Esc (end the stroke, else clear the selection, else finish). ⌫ and ⌦ never fall
+  through to the graph's delete, which would delete the Sketch node being edited. The toolbar and the inspector are
+  opaque to the pointer, so a click on their chrome never draws in the viewport beneath; the viewport's face menu
+  offers only Look At while sketching.
+- §8's undo: each command is one `setInput` of the whole sketch; a point drag commits once, on release, so it is one
+  step without a coalescing key, and downstream evaluation runs on pointer-up. Typed values commit on Return or when
+  the field loses focus (no 150 ms debounce: nothing evaluates while typing).
+- §8's selection: Select-tool clicks toggle an entity in the selection (MetalUI's taps carry no modifiers,
+  docs/metalui-gaps.md S5-a), a click on nothing clears it; points win over the curves through them. ⌘ can't suppress
+  inference until S5-a is fixed.
+- §8's inference in S5a: a click within the pick radius (8 points) of a point shares it (coincident by construction);
+  a line's end within the radius of its start's height or x snaps horizontal or vertical and adds the constraint.
+- §8's Dimension tool: a circle gives a diameter and an arc a radius at once; a line waits for a second pick (a line:
+  angle; a point: distance; nothing: length); a point waits for a point or a line (distance). Each measures the
+  geometry as it is, so nothing moves.
+- §7's single source for exposed values (S4 → S5 handoff): opening a sketch folds a constant left under an exposed
+  dimension's socket name into the sketch, and every commit clears it; renaming an exposed dimension moves its wire,
+  and un-exposing it drops the wire. Delete and the inspector's Remove refuse to remove an exposed dimension.
```

Modify `docs/verification/human-checks.md` (apply this diff):

```diff
--- a/docs/verification/human-checks.md
+++ b/docs/verification/human-checks.md
@@ -387,3 +387,41 @@ Run `swift run MetalCreatorApp`, with the preview mode set to Selected node.
   Known (S5): exposed-dimension sockets aren't drawn, and neither node has inspector controls of its own. Pinned:
   `theBuiltInsAreTheSliceAndTheSketcherNodesInSixCategories`, `aNewSketchHoldsAnEmptySketchOnXYAndAsksForAShape`,
   `aMissingUnreadableOrStalePickIsAPlainError`, `aSketchSettingRoundTripsThroughAFile`. **Observed:**
+
+## Group S5 — the sketch editor in the viewport (S5a)
+
+**Status: NOT RUN.** Run `swift run MetalCreatorApp`. Add a Sketch, wire its `profiles` into an Extrude (10 mm) and
+that into an Output. Select the Sketch.
+
+- [ ] **S5-1 Entering.** The inspector shows "Edit sketch". Press it: the camera turns to look straight down at XY,
+  orthographic; the ground grid gives way to a grid on the sketch plane; the top bar shows the sketch toolbar (Sketch,
+  Select, Line, Arc, Circle, Point, Dimension, Construction, Delete, Finish) and the inspector "Nothing drawn yet. Pick
+  Line (L), Arc (A) or Circle (C).", the CONSTRAIN buttons (all dimmed), DIMENSIONS and CONSTRAINTS. The pointer is a
+  crosshair. **Observed:**
+- [ ] **S5-2 Drawing a rectangle.** Press L and click four corners, then click the first corner again: each line is
+  cyan while it can move; the rubber band follows the pointer; a near-horizontal or near-vertical line snaps and the
+  readout drops. The last click closes the loop on the first point. Press Esc: the chain ends. The Extrude shows a
+  ghosted box under the sketch. **Observed:**
+- [ ] **S5-3 Inference and ⌘.** Draw a nearly horizontal line holding ⌘. Known (gap S5-a): it still snaps.
+  **Observed:**
+- [ ] **S5-4 Constraints and dimensions.** Choose Select, click two lines (both turn green); the inspector's
+  Perpendicular, Parallel and Equal buttons are enabled, the rest dimmed with a tooltip saying what to select. Press D,
+  click the bottom line, then empty space: "Length d1" appears with its value. Type 80 in its value field and press
+  Return: the rectangle and the extrusion follow. Add dimensions until the readout says "Fully constrained": the lines
+  turn the foreground colour. Add a conflicting constraint: the readout and the conflicting rows turn red, and Remove
+  on the extra one fixes it. **Observed:**
+- [ ] **S5-5 Dragging.** With Select, drag a free corner: the sketch follows live and stays constrained; the extrusion
+  updates once, on release; one ⌘Z undoes the whole drag. A drag on empty space orbits; right-drag orbits, middle-drag
+  pans, scroll zooms. **Observed:**
+- [ ] **S5-6 Exposing.** Turn on "Expose as input" for d1, then Finish (⏎): the Sketch node on the canvas shows a `d1`
+  input with "80 mm". Wire a Number into it: the part follows the Number. Edit sketch again, rename d1 to `width`: the
+  wire moves to `width`. Renaming it `plane` is refused in words. **Observed:**
+- [ ] **S5-7 Keys stay where they belong.** While sketching, click into a dimension's name field and type "lad":
+  the letters go into the field, the tool doesn't change. Click the Sketch node on the graph canvas (it is the graph's
+  selection) and press ⌫, then fn-⌫ (or ⌦ on an extended keyboard), with nothing selected in the sketch: no graph node
+  is deleted and sketch mode stays. Select a line and press fn-⌫: the line is deleted. Press Esc twice with nothing in
+  progress: sketch mode ends and the top bar comes back. **Observed:**
+- [ ] **S5-8 The chrome is not the sketch.** With Line active, click in the gaps between the toolbar's buttons, on
+  the inspector's "DIMENSIONS" label and on its readout, and scroll over both: nothing is drawn, no rubber band
+  follows the pointer under the panels, and the view doesn't zoom. Choose Select, select a line and click a gap in the
+  toolbar: the selection stays. Right-click a ghosted face: the menu offers only Look At. **Observed:**
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SketchModeRenderTests`

Expected: PASS (exit 0, no line says "recorded an issue" or "failed after").

- [ ] **Step 5: Full verification**

Run, from the repo root: `swift build --build-tests 2>&1 | grep -E "(error|warning):" | grep -v "ld: warning"` (expected: nothing new; master's one test warning, `ContextMenuTests.swift:96` "'underPointer' mutated after capture", shows only when that file recompiles), then `swift test` (expected: exit 0, no "recorded an issue" / "failed after" lines, and the "Test run with N tests" lines sum to **1163 (master + 78)**), then `swiftlint lint --strict` (zero violations).

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md Sources/CreatorApp/InspectorDock.swift Sources/CreatorApp/SketchChrome.swift Sources/CreatorApp/TopBar.swift docs/metalui-gaps.md docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md docs/superpowers/roadmap.md docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md docs/verification/human-checks.md Tests/CreatorAppTests/SketchModeRenderTests.swift
git commit -m "feat(app): sketch toolbar in the top bar and sketch lists in the inspector; S5a docs"
```


---

## S5b — the rest of S5 (next plan)

Scope, so nothing from the sketcher spec's §8 is lost (each is also in the handoff's "S5a → S5b" section, Task 11):

1. **Project (P)**: `CreatorSketchEditor` gains CreatorKernel; the tool declines clicks so the viewport's ID-buffer pick reaches the host (`ViewportEvents.clicked` with `.edge`), and `SketchStore` writes `NodeSetting.projection(reference)` = `.edgePicks(topology.picks(for: [edge]))`, wires the edge's solid into `references`, and adds a `.projected` entity with a unique `reference`, in one batch. Point-on inference onto projected geometry. A suspended projection drawn red.
2. **"New sketch on face"**: a face context-menu item; one batch adds Plane from Face (`face` = `.facePick(topology.facePick(for:))`) wired from the face's solid and into a new Sketch whose plane is `.wired`, then enters it (`AppModel.sketchPlane(of:_:)` already reads a wired plane).
3. **Double-click a Sketch node** on the canvas to edit it (after the graph-input track lands `GraphPanelInput`'s C7 taps).
4. **Trim (T), Fillet (F, which needs the viewport's F key moved to a key context), Mirror, Pattern** tools over `SketchCommands`, routing `SketchCommandError.message` into `refusal` and showing pattern construction as such.
5. **3-point arcs**, **tangent-to-previous-arc inference**, and **inference glyphs** in the rubber band.
6. **Dimension labels in the view** (an overlay label API on the viewport) and the **faint green region fill** (triangles in the overlay).
7. **Gap S5-a / GI-a follow-ups** once MetalUI reports tap and hover modifiers: ⌘ suppresses inference on clicks; ⇧-click extends the selection (and plain clicks replace it).
8. Debounced (150 ms) downstream evaluation while typing, if live typing is added (S5a commits on Return/focus loss, so nothing evaluates mid-typing).

## Self-review

- **Spec coverage (S5a).** Enter via "Edit sketch" (Task 10); Look At + orthographic (Tasks 2, 10); model dimmed and pickable (Task 10: ghosts stay in the ID pass); plane grid (Task 3, 5); Finish with ⏎/Esc/button (Tasks 6, 9); each command one `setInput` undo step and coalesced drags (Tasks 7, 10); toolbar Line L / Arc A / Circle C / Point / Construction X / Dimension D (Tasks 6, 8, 9) — Trim, Fillet, Mirror, Pattern, Project are S5b; constraint buttons (Tasks 7, 9); inspector lists, name/value fields, "Expose as input", DOF readout (Tasks 4, 8, 9); lines chain, inference horizontal/vertical/coincident and ⌘ (Task 6, ⌘ on clicks blocked by S5-a; tangent and point-on are S5b); Dimension tool infers its kind (Task 8); colours under/fully/conflicting/construction dashed/projected/selection (Tasks 3, 5) — region fill is S5b; CPU picking in plane coordinates within a few pixels (Tasks 5–6); live re-solve on every drag step, downstream on pointer-up (Task 7); editor tests for the tool state machine, inference, plane hit testing, DOF colouring and undo granularity (Tasks 2, 4–8, 10). Handoff: five `inputs(for:)` readers (Task 1); single-source exposed values, rename moves or drops the wire and entry (Task 10); `Sketch.remember` after each edit (Task 4); reserved names refused on rename (Tasks 8, 10); exposed-dimension removal refused (Tasks 7, 8); labels from `Sketch.label(of:)` (Task 8); freedom colours from `SketchSolution.freedom` (Task 5).
- **Placeholder scan.** Every step carries its code or exact command; no TBD/TODO. Task 11's `theWindowDrawsInSketchMode` passes before its change by design; `theTopBarAndTheInspectorSwapInTheSketchViews` is the one that fails first (its step 2).
- **Type consistency.** Checked by applying every block in order in a scratch copy (below): `SketchEditorModel.click(at:tolerance:modifiers:)`, `hover(at:tolerance:modifiers:)`, `endDrag(at: Vector2?)`, `SketchStore.commands(storing:in:graph:)`, `ViewportModel.lookAt(_:framing:)` and `ViewportOverlay(lines:points:gridPlane:)` are used with the same signatures throughout. `SketchEditorModel.sketch`/`solution` start `public private(set)` in Task 4 and become `public internal(set)` in Task 7 (shown in its diff).
- **Review Focus.** Each of the five lines has its test in its owning task (Tasks 6, 7, 10).
- **Revised after review (2026-10-09).** Forward delete (⌦, fn-⌫) is a hidden shortcut too, so it can't reach the graph's Delete and delete the Sketch node being edited (Task 9; S5-7). The Sketch node's declared inspector no longer hides its exposed dimensions' rows: `InspectorBuilder` appends the per-node sockets after a declared inspector (Task 1; pinned on the real node in Task 10). The sketch toolbar and inspector sit in `SketchChrome`, opaque to the pointer, so a click on their chrome never draws hidden geometry (Task 11; S5-8). The face menu offers only Look At while a tool is set (Task 2). `reload` drops a pending dimension pick and ends a point drag (Task 10). S5-a cross-references GI-a. Task 11 has a render test that fails before its change.

## Verification record (how this plan was checked)

Every code block above was applied task by task, in order (again after the review revision, on 2026-10-09), to a scratch copy of this worktree at master `d9fedec` (`MetalCreator-s5` copied without `.build`, with a sibling `MetalUI` symlink to `/Users/maxburger/Developer/MetalUI` at `67a579e`). After each task: `swift build --build-tests` showed no new warnings (master's single test warning, `Tests/CreatorViewportTests/ContextMenuTests.swift:96` "'underPointer' mutated after capture by sendable closure", appears only when that file recompiles); `swift test` exited 0 with no "recorded an issue" or "failed after" line; `swiftlint lint --strict` reported no violations. Test totals (the sum of the "Test run with N tests" lines; master is 1085):

| After task | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Tests | 1090 | 1098 | 1103 | 1109 | 1115 | 1126 | 1133 | 1140 | 1143 | 1161 | 1163 |
| Over master | +5 | +13 | +18 | +24 | +30 | +41 | +48 | +55 | +58 | +76 | +78 |

A parameterised test (`SketchModeRenderTests.theWindowDrawsInSketchMode`, three docks) counts once.

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-09-sketcher-s5-editor.md`. Recommended: **subagent-driven** (a fresh implementer and reviewer per task), because Tasks 4–10 build one model in layers whose interfaces each later task relies on, and Task 10 touches files other tracks share.
