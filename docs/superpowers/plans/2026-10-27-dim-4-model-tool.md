# DIM-4 Model Dimension Tool and Acceptance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Draw a new dimension on the model (D, or "Dimension" in the face menu): two picks that come from one Sketch add
that sketch's dimension at the measured value and open its value box. Then prove the whole project with the spec §1 success
scenario, end to end and headless, in mm and in inches, and close the project's docs.

**Architecture:** The Sketch node reports how its profiles came from its entities (`SketchTrace`, carried on `NodeResult`
the way DIM-3 carries `dimensions`). The app traces a pick through the face's `TopoTag` (`.side(loop:segment:)` of a
node whose `profile` is wired from a Sketch's `profiles`), or through a projected entity's stored edge pick, to
`SketchItem`s (node and entity). It picks the kind (`ModelDimensionKind`), measures it on the sketch as evaluated with DIM-2's
`Sketch.measuredDimension` (a reference when a driving one would over-define), and adds it to the stored sketch as one "Add
Dimension" batch (`SketchStore.commands`, through `MeasuredDimension`). The tool is an app session like `PickSession`, with a
banner. The box opens on DIM-3's feature dimension for the new sketch dimension (`FeatureDimension.overlayID`) once evaluation
shows it.

**Tech Stack:** Swift 6.4, MetalUI (`../MetalUI`, read only), Swift Testing, OpenCascade through `CreatorOCCT`.

**Spec:** `docs/superpowers/specs/2026-10-27-driving-dimensions-design.md` §1 (success), §3.5, §4.4, §7, §8, §10, §11.
Read the overview `docs/superpowers/plans/2026-10-27-dim-overview.md` first: its SHARED INTERFACES and Global Constraints
are binding. DIM-1: `2026-10-27-dim-1-foundation.md`.

**Branch / worktree:** `dim-4-acceptance` in `/Users/maxburger/Developer/worktrees/dim-4` (the overview's Worktrees note).
Starts after DIM-2 and DIM-3 are merged to master.

## DIM-2 / DIM-3 interfaces this plan consumes (reconciled 2026-10-27 against their plans; all in the overview)

| From | Interface | Where used |
|---|---|---|
| DIM-2 | `DimensionKind.centreDistance(SketchEntityID, SketchEntityID)`: two circles or arcs, or a circle or arc and a point (two points are refused); projected circles give their centre | Tasks 4, 5 |
| DIM-2 | `DimensionKind.lineDistance(SketchEntityID, SketchEntityID)`: two lines, measured from the second's midpoint along the first's normal; `quantity == .length` for all four new kinds | Tasks 4, 5 |
| DIM-2 | `Sketch.measuredDimension(_ kind:) -> (value: Double, isDriving: Bool)?` (Task 3, `Sketch+MeasuredDimension.swift`): §4.4's rule (reference when the driving solve is `.overConstrained` with the new dimension among the conflicts); nil when unmeasurable or a length under 1e-9. Task 4 builds on it; it does not re-implement it | Task 4 |
| DIM-2 | Two lines within 0.5° of parallel are a line distance, else an angle (DIM-2 decision 5); Task 4 uses the same limit | Task 4 |
| DIM-2 | `SketchDimension.labelPoint` is `nil` for a new dimension (the style's standoff) | Task 5 |
| DIM-3 | `NodeOutputs.dimensions` / `NodeResult.dimensions`, collected by `IterationOutputs.record` and put on the result in `Evaluator+Running.run`; `sketchTrace` follows the same path | Task 2 |
| DIM-3 | `SketchSolve.Output` already carries the solved `sketch` and `solution` (DIM-3 Task 9); the trace is built from them | Task 2 |
| DIM-3 | Sketch declares `DimensionSpec(.sketchDimension(id), geometry, kind.quantity, value:)` per dimension (`SketchDimensionGeometry`); Extrude `distance`; Hole Pattern `diameter` with `count` (NX); Linear Pattern `spacing` and `count`; Fillet `radius` and Chamfer `distance`, each with `count` = the edge count when ≥ 2 | Tasks 5, 7, 8 |
| DIM-3 | `FeatureDimension.overlayID(node:target:component:index:)`: the instance-free ID is `FeatureDimension.overlayID(node: sketch, target: .sketchDimension(id))` | Task 5 |
| DIM-3 | `AppModel.selectFeature(at:)`, called from `viewportClicked(_:)` with no pick session and no sketch, **in Final preview only** (`previewMode == .final`, the default); a hole wall selects the Hole Pattern | Tasks 5, 7 |
| DIM-3 | `FeatureChain.nodes(of:in:)`: stops at a node with another consumer (an `isOutput` node counts as one), at Graph Parameter and Group Input nodes, and **never crosses a body wire** (`.solid`, `.implicit`, `.mesh`) | Tasks 7, 8 |
| DIM-3 | `AppDimensionEditing` routes `"feature/"`; `commitChecked(_:at:name:)` commits a feature input or a sketch dimension as `UndoName.changeDimension` ("Change Dimension") and a parameter-wired one as `UndoName.changeParameter` ("Change Parameter", top level); box `note` "Wall (parameter, used by 1 feature)"; out of range "Wall must be between 1 mm and 20 mm." | Tasks 7, 8 |
| DIM-3 | `menuActions(for:)` titles "Pin Dimension" / "Unpin Dimension" (`UndoName.pinDimension`); `DimensionPin(node:target:)`, `DimensionTarget`, `Graph.dimensionPins` on the level's graph; `OverlayDimension.isPinned` | Task 7 |

## Global Constraints

- The overview's Global Constraints apply to every task: Swift 6.4 strict concurrency, Swift Testing only, `@MainActor @Observable` models, portable code (`.primary`, no CoreText/CoreGraphics/Metal outside `#if canImport`), colours only in `CreatorStyle`, undo names only `UndoName`/`SketchStepName` constants (no numbers, no typed text), `swiftlint lint --strict` clean, never broad `pkill`, never modify `../MetalUI`, the two commit trailers.
- Per task: `swift build --build-tests`, then `swift test --filter <suites named in the task>`. Task 10 runs the full suite: exit 0, exactly 12 "Test run with" lines, no "recorded an issue" or "failed after", on macOS and Linux.
- File format stays 10 (DIM-1). This stage adds **no** file key: `SketchTrace` is evaluation output, never saved.
- Spec §3.5 copy, verbatim: the chip "These come from different features: a measurement tool is planned"; the undo step "Add Dimension" (`UndoName.sketch(SketchStepName.addDimension)`, as `AppModel.storeSketch` names sketch steps).
- Spec §3.5: the new dimension is added at its measured value (nothing moves), then its box opens at once; over-defining → added as a reference (§4.4). Spec §7: typing changes nothing; Return commits one step; the camera does not move.
- Tests that need real faces, tags and edge curves run on `OCCTKernel` inside `#if canImport(CreatorOCCT)` (as `AppAcceptanceTests`); OCCT is available on Linux (xp-2), so they run there too.

## Decisions here that touch the spec or what the user sees (flagged for the orchestrator)

1. **Vertices** are "available" only as an upright edge of an extruded wall (an edge between two walls of one sweep): it
   traces to the sketch point the two entities share. `Topology` has no vertices, so a corner can't be clicked as a point.
2. **Side faces pick too**: a flat wall is its line, a hole's cylindrical wall its circle. A cap face traces to nothing.
3. **Two non-parallel lines give an angle** (`.angle`), as the sketch D tool does; the spec lists only centre-to-centre,
   edge-to-edge and point-to-line. A circle with a line gives the distance from the circle's centre point to the line.
4. **A trace follows only a direct wire** from a Sketch's `profiles` into the sweeping node's `profile`. Anything between
   them (List Item, Place, a group's socket) makes the pick come from "different features". Item k of the sweep is region k.
5. **After the add, the Sketch node is selected** (`editor.selection = [sketch]`), so its dimensions show and the new one's
   box can open even when the sketch feeds more than one feature. In Selected-node preview this also switches the preview to the
   Sketch, as any selection does; the box still opens.
6. **Add and edit are two steps**: Esc on the opened box keeps the dimension added at its measured value ("Add Dimension");
   Return with a new value adds "Change Dimension". A reference opens no box (it isn't editable) and shows no extra message:
   it appears grey in parentheses.
7. **The tool's UI** is a banner in `PickBanner`'s place: "Click two edges or holes to dimension · N picked", Cancel (Esc);
   the chip text shows as a second line until the next click. Picked items are not highlighted (the count says it).
8. **D's binding** is a window keymap key in the `AppKeyContext.viewport` context (like F): it never fires while a panel
   field or the value box has focus, passes through over the graph canvas, and passes through in sketch mode so the sketch
   toolbar's D button still chooses the sketch Dimension tool (the keymap runs before button shortcuts; an unclaimed action
   is passed on as unbound). Checked: no viewport (`ViewportInputMap.keyBindings`: f, =, shift-+, +, -), graph
   (`GraphKeyBindings`: ⌘D only) or app menu shortcut uses plain D.
9. **File name**: this plan is `2026-10-27-dim-4-model-tool.md` (the overview's stage table says so since the 2026-10-27
   reconciliation).
10. **Merge task M comes first.** Whichever of DIM-2/DIM-3 merged second completed DIM-3 Task 9's `SketchDimensionGeometry` for
    DIM-2's four kinds and wired `SketchFlipCheck` into feature-mode sketch edits (the overview's merge task M, the
    orchestrator's). This stage starts only after it; if `SketchDimensionGeometry` lacks a DIM-2 kind, stop and report it.
11. **A circle with a line** measures from the circle's centre point (decision 3), where the sketch D tool refuses that pair
    (DIM-2 Task 7). Kept: the spec lists point-to-line for the model tool; flagged for the orchestrator.

## Review Focus

1. The first pick goes stale before the second (an undo, an edit, the part re-evaluating, the level changing): the add reads the current sketch, and a node or entity that is gone adds nothing and shows the chip. Test: Task 5 `aPickThatWentStaleAddsNothing`.
2. D pressed while a panel field or the value box has focus, over the graph canvas, or in sketch mode: it types, does nothing, or chooses the sketch tool, and never starts the model tool. Tests: Task 6 `dInAPanelFieldTypes`, `dInTheValueBoxTypes`, `dOverTheGraphCanvasDoesNothing`, `dInSketchModeChoosesTheSketchDimensionTool`.
3. A sketch whose exposed dimension is wired: the measured value is the evaluated geometry's (80), not the stored one's (60), so nothing moves. Tests: Task 4 `theValueComesFromTheEvaluatedSketch`, Task 5 `aWiredSketchIsMeasuredAsEvaluated`.
4. Two picks on the same item (a hole's top and bottom rim, one edge twice): no dimension; the second pick is ignored. Test: Task 5 `theSameItemTwiceIsIgnored`.
5. A pick on a ghost (a failing node's last good part) or a guide item: ignored, never traced from stale results. Test: Task 5 `ghostsAndGuidesArentPicked`.

---

### Task 1: Region sources in CreatorSketch

**Files:**
- Modify: `Sources/CreatorSketch/Regions/SketchRegion.swift` (stored `sources`, init parameter defaulting to `[]`), `SketchRegions.swift` / `RegionGraph+Faces.swift` (fill it from each `LoopSegment.source`'s curve entity, in the same order and orientation as the loop's segments, holes in the holes' sorted order)
- Test: `Tests/CreatorSketchTests/Regions/RegionSourceTests.swift`

**Interfaces:**
- Produces: `SketchRegion.sources: [[SketchEntityID]]`, parallel to `[outer] + holes`: `sources[loop][segment]` is the entity that segment comes from (a projected entity's ID for a projected curve). Not `Codable`, not saved.

- [ ] **Step 1: Write the failing tests** (a 60 × 40 rectangle from (0,0), lines `l0`…`l3` bottom, right, top, left; circles `c1` at (15,20) and `c2` at (45,20), r 4)

```swift
@Test func theOuterLoopNamesItsLinesFromTheSmallestCorner() // regions[0].sources[0] == [l0, l1, l2, l3]
@Test func holesNameTheirCirclesInHoleOrder()               // sources[1].allSatisfy { $0 == c1 }; sources[2] all c2; non-empty
@Test func sourcesParallelTheSegments()                     // for every loop: sources[i].count == loops[i].count
@Test func aSplitCurveNamesEachPiece()                      // a line crossed by another (two regions): both pieces name it
@Test func aProjectedEdgeNamesItsEntity()                   // a projected line closing a U of three lines: its segment names it
```

- [ ] **Step 2: Run** `swift test --filter RegionSourceTests` — Expected: FAIL (no `sources`).
- [ ] **Step 3: Implement**; reversing a loop (to run CCW) reverses its sources with it.
- [ ] **Step 4: Run** `swift test --filter CreatorSketchTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(sketch): each region segment names the entity it comes from`.

### Task 2: The Sketch node's trace

**Files:**
- Create: `Sources/CreatorSketch/Regions/SketchTrace.swift`
- Modify: `Sources/CreatorGraph/NodeOutputs.swift`, `NodeResult.swift`, `IterationOutputs.swift` (`record` keeps the first iteration's trace; a Sketch node runs once) and `Evaluator+Running.swift` (`run` puts it on the result), beside DIM-3's `dimensions`; `Sources/CreatorNodes/Sketch/SketchSolve.swift` (`Output.trace`, from DIM-3's `Output.sketch` and `solution`), `Profiles/SketchNode.swift` (sets `outputs.sketchTrace`); `Sources/CreatorNodes/Sketch/SketchProjections.swift` (public entry below)
- Test: `Tests/CreatorNodesTests/SketchTraceTests.swift`

**Interfaces:**
- Consumes: Task 1.
- Produces:

```swift
public struct SketchTrace: Hashable, Sendable {
    public var sketch: Sketch            // as evaluated: projections resolved, wired values applied, solution remembered
    public var regionSources: [[[SketchEntityID]]]   // profile item → loop → segment (Task 1's sources, region order)
    public init(sketch: Sketch, regionSources: [[[SketchEntityID]]])
    public func entity(item: Int, loop: Int, segment: Int) -> SketchEntityID?   // nil when out of range
}
extension NodeOutputs { public var sketchTrace: SketchTrace? }   // default nil
extension NodeResult { public var sketchTrace: SketchTrace? }    // nil for every node but a Sketch that solved
extension SketchNode {
    /// The projected entity of `trace.sketch` whose stored pick (`NodeSetting.projection(reference)` on `node`)
    /// locates exactly `edge` on `solid` (`SketchProjections.locate`), first in entity order; nil otherwise.
    public static func projectedEntity(for edge: EdgeID, on solid: Solid, node: Node, trace: SketchTrace) -> SketchEntityID?
}
```

- [ ] **Step 1: Write the failing tests** (FakeKernel; the Task 1 sketch in a Sketch node)

```swift
@Test func aSolvedSketchCarriesItsTrace() async throws   // result.sketchTrace?.regionSources.count == 1; entity(0, 0, 0) == l0
@Test func theTraceIsTheSketchAsEvaluated() async throws // exposed width wired from Number 80: trace.sketch.position(of: corner1) == (80, 0)
@Test func aFailingSketchHasNoTrace() async throws       // an over-constrained sketch (error state) → sketchTrace == nil
@Test func otherNodesHaveNoTrace() async throws          // the Extrude's result.sketchTrace == nil
@Test func outOfRangeIsNil()                             // entity(item: 3, …), loop 9, segment 99 → nil
@Test func aProjectedEdgeIsFoundByItsPick() async throws // Sketch projecting a box's top edge: projectedEntity(for: that edge) == its entity;
                                                         // another edge → nil
```

- [ ] **Step 2: Run** `swift test --filter SketchTraceTests` — Expected: FAIL.
- [ ] **Step 3: Implement.** `SketchSolve.run` builds the trace from the solved sketch DIM-3 put on `Output`. The trace is not part of `estimatedBytes` beyond a flat 64 per region.
- [ ] **Step 4: Run** `swift test --filter CreatorNodesTests` and `swift test --filter CreatorGraphTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(nodes): the Sketch node reports which entity made each profile segment`.

### Task 3: Tracing a pick to sketch items

**Files:**
- Create: `Sources/CreatorApp/ModelDimension/SketchItem.swift`, `ModelDimensionTrace.swift`
- Modify: `Tests/CreatorAppTests/Support/SketchGraph.swift` (`holedPlateSketch() -> HoledPlate`: the Task 1 sketch, fully constrained except the circles' centres, dims `width` 60 and `height` 40; `struct HoledPlate { sketch; lines: [SketchEntityID]; corners: [SketchEntityID]; circles: [SketchEntityID] }`)
- Test: `Tests/CreatorAppTests/ModelDimension/ModelDimensionTraceTests.swift` (OCCT; the holed plate in `sketchedBox`, extruded 10)

**Interfaces:**
- Consumes: Task 2 (`NodeResult.sketchTrace`, `SketchNode.projectedEntity`), `editor.graph`, `editor.levelResults`.
- Produces:

```swift
public struct SketchItem: Hashable, Sendable { public var node: NodeID; public var entity: SketchEntityID }
enum ModelDimensionTrace {
    /// What `target` (on `viewport.items[index]`, a part that is neither ghost nor guide) comes from, best first:
    /// sweep traces (the face's `.side` tags), then projections (Sketch nodes in node-ID order). [] when nothing.
    static func items(for target: PickTarget, solid: Solid, graph: Graph, results: [NodeID: NodeResult]) -> [SketchItem]
    /// The first item of `first` whose node `second` also has, with that item of `second`; nil when none.
    static func shared(_ first: [SketchItem], _ second: [SketchItem]) -> (SketchItem, SketchItem)?
}
```

  Rule (the signature leaves it open):

```
wall(face) = for each tag in face.tags with role .side(loop, segment), sorted by sortKey:
    link = graph.incomingLink(to: Endpoint(node: tag.node, socket: "profile")), from a SketchNode's "profiles"
    entity = results[link.from.node]?.sketchTrace?.entity(item: tag.item, loop, segment)
face target:  wall(face)
edge target:  faces a, b (a seam lists one face twice: use it once)
    both have walls of one Sketch → the point entity both walls' entities end on (none shared → nothing)
    one has walls             → its entities
    then append every Sketch at the level whose projectedEntity(for: edge, on: solid, …) is non-nil
```

- [ ] **Step 1: Write the failing tests**

```swift
@Test func aWallTracesToItsSketchLine() async throws        // face tagged side(0,0) → [SketchItem(sketch, lines[0])]
@Test func aTopEdgeTracesToTheLineUnderIt() async throws    // edge endCap|side(0,2) → [lines[2]]
@Test func anUprightEdgeTracesToTheCornerPoint() async throws   // edge side(0,0)|side(0,1) → [corners[1]]
@Test func aHoleRimTracesToItsCircle() async throws         // circular edge endCap|side(1,_) → [circles[0]]; its wall face too
@Test func aCapTracesToNothing() async throws               // endCap face → []
@Test func aPartNotFromASketchTracesToNothing() async throws    // Rectangle → Extrude: every face and edge → []
@Test func somethingBetweenTheSketchAndTheSweepBreaksTheTrace() async throws   // Sketch → List Item → Extrude → []
@Test func theItemPicksTheRegion() async throws             // two separate rectangles (80×40, 20×20): the small one's wall → its line
@Test func aProjectedEdgeTracesToTheSketchHoldingItToo() async throws
    // a second Sketch projecting the plate's right top edge: items == [plate lines[1], SketchItem(second, projected)]
@Test func sharedTakesTheFirstSketchBothHave()              // pure: ([a1, b1], [b2]) → (b1, b2); ([a1], [b2]) → nil
```

- [ ] **Step 2: Run** `swift test --filter ModelDimensionTraceTests` — Expected: FAIL.
- [ ] **Step 3: Implement** as above.
- [ ] **Step 4: Run** `swift test --filter ModelDimensionTraceTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(app): trace a picked face or edge to the sketch entity that made it`.

### Task 4: The kind and the measured add

**Files:**
- Create: `Sources/CreatorSketch/Dimensions/ModelDimensionKind.swift`, `MeasuredDimension.swift` (a thin wrapper over DIM-2's `Sketch.measuredDimension`; the sketch D tool is not changed)
- Test: `Tests/CreatorSketchTests/Dimensions/ModelDimensionKindTests.swift`, `MeasuredDimensionAddTests.swift` (not `MeasuredDimensionTests`: DIM-2 owns that suite)

**Interfaces:**

```swift
public enum ModelDimensionKind {
    /// circle|arc + circle|arc|point → .centreDistance; lines within 0.5° of parallel on the solved positions (DIM-2's
    /// limit) → .lineDistance; other lines → .angle; point + line → .distance(point, line); circle|arc + line →
    /// .distance(its centre, line); point + point → .distance; the same entity, or anything else → nil.
    /// A projected entity counts as its `ProjectedCurve`'s kind (a circle has no centre point: with a line → nil).
    public static func between(_ a: SketchEntityID, _ b: SketchEntityID, in sketch: Sketch) -> DimensionKind?
}
public enum MeasuredDimension {
    public struct Added: Hashable, Sendable { public var sketch: Sketch; public var id: DimensionID; public var value: Double; public var isDriving: Bool }
    /// `evaluated.measuredDimension(kind)` (DIM-2: the value as solved, and whether it can drive, spec §4.4), then adds the
    /// dimension (that value, `isDriving`, `labelPoint` nil, the next dimension name) to `stored` under the ID `stored` assigns
    /// next, the same ID in both. nil when `measuredDimension` is nil (unmeasurable, a suspended projection, a zero length).
    public static func add(_ kind: DimensionKind, measuredOn evaluated: Sketch, to stored: Sketch) -> Added?
}
```

- [ ] **Step 1: Write the failing tests** (the holed plate's sketch, built in the test target as in Task 3)

```swift
@Test func twoCirclesGiveCentreToCentre()        // (c1, c2) → .centreDistance(c1, c2)
@Test func aCircleAndAPointGiveCentreToCentre()  // (c1, corners[0]) → .centreDistance(c1, corners[0])
@Test func parallelLinesGiveEdgeToEdge()         // (l0, l2) → .lineDistance(l0, l2)
@Test func crossingLinesGiveAnAngle()            // (l0, l1) → .angle(l0, l1)
@Test func aPointAndALineGivePointToLine()       // (corners[1], l3) → .distance(corners[1], l3)
@Test func aCircleAndALineMeasureFromTheCentre() // (c1, l3) → .distance(centre of c1, l3)
@Test func twoPointsGiveTheirDistance()
@Test func theSameEntityTwiceGivesNothing()      // (c1, c1) → nil
@Test func projectedCurvesCountAsTheirKind()     // a projected line parallel to l0 → .lineDistance
// MeasuredDimensionAddTests:
@Test func aFreeDistanceIsAddedDrivingAtItsMeasuredValue()   // centreDistance(c1,c2): value 30, isDriving; solving the result
                                                             // leaves every point where it was (within 1e-9)
@Test func anOverDefiningDimensionIsAddedAsAReference()      // lineDistance(l0, l2) with height 40: isDriving false, value 40
@Test func theValueComesFromTheEvaluatedSketch()             // evaluated width 80, stored 60: lineDistance(l1, l3) value 80;
                                                             // added.sketch.dimensions[width].value == 60; ids equal
@Test func anUnmeasurableKindAddsNothing()                   // a distance to a suspended projected line → nil
```

- [ ] **Step 2: Run** `swift test --filter ModelDimensionKindTests` and `--filter MeasuredDimensionAddTests` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter CreatorSketchTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(sketch): choose and measure a dimension between two entities, as a reference when it over-defines`.

### Task 5: The model dimension tool

**Files:**
- Create: `Sources/CreatorApp/ModelDimension/ModelDimensionSession.swift`, `ModelDimensionText.swift`, `ModelDimensionBanner.swift` (pattern `PickBanner.swift`), `Sources/CreatorApp/AppModel+ModelDimension.swift`
- Modify: `AppModel.swift` (`public internal(set) var modelDimension: ModelDimensionSession?`; `@ObservationIgnored var pendingValueBox: OverlayDimensionID?`), `AppModel+Picking.swift` (`viewportClicked`: the tool takes the click first, before DIM-3's `selectFeature(at:)` and the pick session), `AppModel+Dimensions.swift` (`refreshDimensions()` opens `pendingValueBox` once it is shown, then clears it), `AppRoot.swift` (the banner in `PickBanner`'s place), and wherever `pick` is cancelled (beginning sketch mode, a level change in `refreshScene`, New/Open): cancel the tool too; undo/redo clear `pendingValueBox`
- Test: `Tests/CreatorAppTests/ModelDimension/ModelDimensionToolTests.swift` (OCCT; holed plate)

**Interfaces:**
- Consumes: Tasks 3, 4; `SketchStore.commands(storing:in:graph:)` (takes the Sketch `Node`); DIM-3's `FeatureDimension.overlayID(node:target:)`; DIM-1's `viewport.openValueBox(for:)`.
- Produces:

```swift
public struct ModelDimensionSession: Hashable, Sendable {
    public var first: ModelDimensionPick?
    public var message: String?        // the chip text, cleared by the next click
    public var level: [NodeID]         // editor.levelPath at the start
    public var pickedCount: Int { first == nil ? 0 : 1 }
}
public struct ModelDimensionPick: Hashable, Sendable { public var target: PickTarget; public var items: [SketchItem] }
enum ModelDimensionText {
    static let differentFeatures = "These come from different features: a measurement tool is planned"
    static func prompt(picked: Int) -> String     // "Click two edges or holes to dimension · 0 picked"
}
extension AppModel {
    /// Refused (false) while a sketch is open or a pick session runs; true otherwise (already running: nothing changes).
    @discardableResult public func beginModelDimension(from target: PickTarget? = nil) -> Bool
    public func cancelModelDimension()
    func modelDimensionClicked(_ target: PickTarget?)
}
```

  A click: on nothing, a ghost or a guide item → ignored. First pick → stored with its items. Second pick → items traced;
  same item as the first → ignored; `shared` nil, or the shared node or either entity gone from the current results, or
  `ModelDimensionKind.between` nil, or `MeasuredDimension.add` nil → `message = differentFeatures`, `first = nil`, nothing
  written. Otherwise: one `document.perform(.batch(SketchStore.commands(storing: added.sketch, in: sketchNode, graph:
  editor.graph)), at: editor.graphPath, name: UndoName.sketch(SketchStepName.addDimension))` (`sketchNode` the Sketch `Node` of
  `editor.graph`), `modelDimension = nil`, `editor.selection = [sketchNode.id]`, and when `added.isDriving`, `pendingValueBox =
  FeatureDimension.overlayID(node: sketchNode.id, target: .sketchDimension(added.id))`. The measured sketch is the trace's (`results[node].sketchTrace.sketch`); the stored one is
  the node's `NodeSetting.sketch`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func theToolWaitsForBothPicksBeforeTouchingTheDocument() async throws
    // begin; click rim of hole 1 → pickedCount 1, graph unchanged, undoName nil, banner text "… · 1 picked"
@Test func twoHoleRimsAddACentreToCentreDimensionAndOpenItsBox() async throws
    // + rim of hole 2, settle → stored sketch's new dimension .centreDistance(c1, c2), value 30, driving;
    // undoTitle "Undo Add Dimension"; modelDimension nil; selection [sketch]; viewport.valueBox?.draft == "30";
    // the extruded part's rim centroids unchanged within 1e-6; camera pose unchanged
@Test func oneUndoTakesItAway() async throws                  // undo → the Sketch node's sketch equals the one before
@Test func returnWithANewValueIsASecondStep() async throws    // draft "35", submit, settle → value 35, "Undo Change Dimension";
                                                              // undo → 30 and still added; undo → gone
@Test func escapeOnTheBoxKeepsTheMeasuredDimension() async throws   // cancelValueBox → value 30, undoTitle "Undo Add Dimension"
@Test func anOverDefiningPairIsAddedAsAReferenceWithNoBox() async throws
    // top edges over l0 and l2 → .lineDistance(l0, l2), isDriving false, value 40; valueBox nil
@Test func aWallAndAHoleGiveTheDistanceFromItsCentre() async throws   // left wall + rim 1 → .distance(centre c1, l3), 15
@Test func differentFeaturesSayWhyAndAddNothing() async throws
    // plate wall + a face of a second part (Rectangle → Extrude) → message == "These come from different features: a
    // measurement tool is planned"; graph unchanged; session still open with first nil; the next click clears message
@Test func theSameItemTwiceIsIgnored() async throws           // top rim then bottom rim of hole 1 → pickedCount 1, nothing added
@Test func aPickThatWentStaleAddsNothing() async throws       // pick rim 1; replace the sketch without c1 (perform); pick rim 2
                                                              // → the chip, nothing added
@Test func aWiredSketchIsMeasuredAsEvaluated() async throws   // exposed width wired from Number 80: left + right walls →
                                                              // lineDistance value 80 (reference)
@Test func ghostsAndGuidesArentPicked() async throws          // a click on a ghost item → pickedCount 0
@Test func theToolEndsWithEscapeSketchModeOrALevelChange() async throws
    // cancelModelDimension → nil; begin then beginSketch → nil; begin then enter a group → nil
@Test func itCantStartWhileSketchingOrPicking() async throws  // beginModelDimension() == false in both; modelDimension nil
```

- [ ] **Step 2: Run** `swift test --filter ModelDimensionToolTests` — Expected: FAIL.
- [ ] **Step 3: Implement.** The banner: `GlassPanel(.pickBanner)`, prompt in the selection colour, `message` below it in `textColor` of the conflicting role, `Button("Cancel")` with `.keyboardShortcut(.escape, modifiers: [])`.
- [ ] **Step 4: Run** `swift test --filter ModelDimensionToolTests` and `swift test --filter CreatorAppTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(app): the model dimension tool adds a sketch dimension from two picks (spec §3.5)`.

### Task 6: D and the face menu's Dimension

**Files:**
- Create: `Sources/CreatorApp/ModelDimension/ModelDimensionKeyAction.swift` (`struct ModelDimensionKeyAction: Action`)
- Modify: `Sources/CreatorApp/AppInput.swift` (keymap: `KeyBinding("d", ModelDimensionKeyAction(), context: AppKeyContext.viewport)`; `handleAction`: after the graph's actions, a `ModelDimensionKeyAction` returns `false` while `editor.pointerLocation != nil`, else `model.beginModelDimension()`); `Sources/CreatorViewport/Model/ViewportMenuItem.swift` (`case dimension(PickTarget)`, title "Dimension"), `ViewportEvents.swift` (`public var dimension: @MainActor (PickTarget) -> Void = { _ in }`), `ViewportModel+ContextMenu.swift` (after Select Edges of Face, for the pressed target itself, face or edge, only when `tool == nil`; `choose` forwards it); `Sources/CreatorApp/AppModel+Viewport.swift` (`events.dimension = { events()?.beginModelDimension(from: $0) }`); existing tests pinning the menu's items (`ContextMenuTests`, `NewSketchOnFaceTests`, `PatternOnFaceTests`, `ScatterOnFaceTests`, `GroupViewportTests`)
- Test: `Tests/CreatorViewportTests/ContextMenuTests.swift` (two tests added), `Tests/CreatorAppTests/ModelDimension/ModelDimensionKeyWindowTests.swift` (pattern `CanvasTitleTypingWindowTests.swift`, `AppWindow` support)

- [ ] **Step 1: Write the failing tests**

```swift
// ContextMenuTests:
@Test func aFaceOrEdgeOffersDimension()       // over an edge: items contain .dimension(.edge(solid: 0, e)), title "Dimension";
                                              // choose → events.dimension receives that edge
@Test func aToolHidesDimension()              // with a tool set: no .dimension item
// ModelDimensionKeyWindowTests (FakeKernel unless a trace is needed):
@Test func dOverTheViewportStartsTheTool() async throws        // press "d" → modelDimension != nil, banner shown
@Test func dInAPanelFieldTypes() async throws                  // focused inspector number field: "d" lands in its text; tool nil
@Test func dInTheValueBoxTypes() async throws                  // open value box: draft gains "d"; tool nil
@Test func dOverTheGraphCanvasDoesNothing() async throws       // pointer over the canvas → tool nil, graph unchanged
@Test func dInSketchModeChoosesTheSketchDimensionTool() async throws   // sketch open: editor.tool == .dimension; tool nil
@Test func escapeCancelsTheTool() async throws                 // "d" then Esc → nil
@Test func theMenusDimensionStartsWithThatPick() async throws  // OCCT: choose .dimension(rim 1) → pickedCount 1
```

- [ ] **Step 2: Run** `swift test --filter ContextMenuTests` and `--filter ModelDimensionKeyWindowTests` — Expected: FAIL.
- [ ] **Step 3: Implement**; update the menu pins the suites name.
- [ ] **Step 4: Run** `swift test --filter CreatorViewportTests` and `swift test --filter CreatorAppTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: D and the face menu's Dimension start the model dimension tool`.

### Task 7: The sketch-based bracket and the success scenario

**Files:**
- Create: `Tests/CreatorAppTests/Support/AppSketchBracket.swift`, `Tests/CreatorAppTests/DimensionAcceptanceTests.swift` (OCCT)

**Interfaces:**
- Consumes: DIM-3's display, pins and commit path (table); Tasks 5–6 are not needed here except `refreshDimensions`.
- The fixture (`@MainActor struct AppSketchBracket`, built through `document.perform` as `AppBracket` is): a Sketch on XY of a 100 × 50
  rectangle from (0,0) (lines bottom, right, top, left; horizontal/vertical; corner 0 fixed; `.length(bottom)` 100 named
  "length", `.length(right)` 50 named "width"; fully defined) → Extrude `distance` 6 → Hole Pattern (`part` ← the solid,
  `placements` ← a Linear Pattern: `start` (20, 25, 6), `direction` +x, `count` 2, `spacing` 60, `facing` +z; `diameter` 8,
  `throughAll` true) → Output "Bracket". Exposes `sketch`, `extrude`, `layout`, `holes`, `output`, `lengthID`.
  Helpers: `shown(_ app, _ text) -> OverlayDimension?` (first `viewport.dimensions` with that text) and
  `holeCentresX(_ app) -> [Double]` (sorted x of the Hole Pattern solid's cylindrical faces' centroids).

- [ ] **Step 1: Write the failing test** (`@Test(arguments: [LengthUnit.millimetres, .inches])`)

```swift
@Test func theHolePatternsSpacingIsEditedOnThePart(_ unit: LengthUnit) async throws {
    // expected texts:          mm      inches (precision 2)
    //   spacing before/after   "60"/"70"   "2.36"/"2.75"
    //   holes                  "2X Ø8"     "2X Ø.31"
    //   pinned plate length    "100"       "3.94"
    //   typed                  "70"        "2.75"   → spacing 70 / 69.85
    // 1. settle; expectAllOK; app.setUnits(unit) (inches only)
    // 2. pin: editor.selection = [sketch]; refreshDimensions; d = shown("100"/"3.94");
    //    perform dimensionRouter.menuActions(for: d.id) titled "Pin Dimension" →
    //    graph.dimensionPins == [DimensionPin(node: sketch.id, target: .sketchDimension(lengthID))]
    // 3. (Final preview, the default) click a hole wall: viewportClicked(.face(solid: 0, cylindrical face)) →
    //    editor.selection == [holes.id] (DIM-3's selectFeature); the chain reaches the layout but not the plate (body wire);
    //    shown(spacing), shown(holes text) non-nil; shown(pinned)?.isPinned == true
    // 4. snapshot graph, results, extrude solid, camera pose; openValueBox(for: spacing.id) == true; draft == editText
    //    ("60" / "2.3622"); valueBoxDraftChanged(typed) → graph and pose unchanged, no evaluation started
    // 5. await submitValueBox(); settle → layout.inputValues["spacing"] == .number(70 / 69.85) (|Δ| < 1e-9);
    //    every other node's inputValues unchanged; extrude's solid === before (not re-evaluated); pose unchanged;
    //    holeCentresX == [20, 90] / [20, 89.85] (±1e-6); undoTitle == "Undo Change Dimension"; expectAllOK
    // 6. pinned length still shown, isPinned, text unchanged; shown(spacing after) non-nil
    // 7. undo once → spacing back to 60 and holeCentresX [20, 80]; redo
    // 8. save to temporaryURL, open, settle → document.units == (unit == .inches ? DocumentUnits(length: .inches) : .millimetres);
    //    dimensionPins equal; isEdited false; select the hole pattern again → pinned text and isPinned as before, spacing after shown
}
```

- [ ] **Step 2: Run** `swift test --filter DimensionAcceptanceTests` — Expected: FAIL (fixture missing), then PASS once the fixture exists if DIM-1–3 are right. A failure after the fixture builds is a DIM-1/2/3 defect: report it to the orchestrator with the failing step; do not patch around it here.
- [ ] **Step 3: Write the fixture** and run again — Expected: PASS for both arguments.
- [ ] **Step 4: Add the model-tool pass on the same part** `@Test func theToolAddsThePlatesEdgeToEdgeAsAReference() async throws`: begin; click the top edges over the left and right lines → `.lineDistance(left, right)` reference 100 (the length dimension defines it), "Undo Add Dimension", no box; click a hole rim then the plate wall → the chip, nothing added (the holes are the Hole Pattern's).
- [ ] **Step 5: Run** `swift test --filter DimensionAcceptanceTests` — Expected: PASS.
- [ ] **Step 6: Commit** `test: driving dimensions acceptance on a sketched bracket, in mm and inches`.

### Task 8: The §7.2 bracket: private chain and parameters

**Files:**
- Modify: `Tests/CreatorAppTests/Support/AppBracket.swift` (keep `wall: GraphParameter` and the flange Extrude as properties)
- Create: `Tests/CreatorAppTests/BracketDimensionChainTests.swift` (OCCT); one test in `DimensionAcceptanceTests.swift`

- [ ] **Step 1: Write the tests**

```swift
@Test func theChamferShowsItsDistanceButNotTheFilletsRadius() async throws
    // selection [chamfer] → a text contains "0.5", none "R3" (the chain never crosses the fillet's solid wire, DIM-3 decision 2)
@Test func theFilletShowsItsRadiusWhenSelected() async throws   // selection [fillet] → "R3"
@Test func thePlatesDepthIsTheWallParameter() async throws
    // selection [plate]: d = shown("6"), tint .dimensionDriving; dimensionRouter.valueBoxContent(for: d.id)?.note ==
    // "Wall (parameter, used by 1 feature)"; box "8", submit, settle → parameter Wall == .number(8), undoName
    // UndoName.changeParameter ("Change Parameter"), the flange's distance still .number(8) and unwired, expectAllOK; undo → 6
@Test func aParameterOutsideItsRangeIsRefusedInTheBox() async throws
    // box "40" (Wall 1…20) → refused("Wall must be between 1 mm and 20 mm."), the box stays open with it, Wall still 6, no undo step
// DimensionAcceptanceTests:
@Test func aSharedLayoutBelongsToNeitherFeature() async throws
    // AppSketchBracket plus a second Hole Pattern (Ø4, part ← the first's solid, placements ← the same layout):
    // selecting the first Hole Pattern shows "2X Ø8" and not "60"
```

- [ ] **Step 2: Run** `swift test --filter BracketDimensionChainTests` and `--filter DimensionAcceptanceTests` — Expected: PASS (these pin DIM-3's rules; a failure is reported to the orchestrator, as in Task 7).
- [ ] **Step 3: Commit** `test: the §7.2 bracket's private-chain and parameter-wired dimensions`.

### Task 9: Docs: human checks, CLAUDE.md, the sketcher erratum, the gaps row

**Files:**
- Modify: `docs/verification/human-checks.md` (a group at the end), `CLAUDE.md`, `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md` (Errata (S5c)), `docs/metalui-gaps.md` (DIM-a's summary row and entry: its state now)

- [ ] **Step 1: Human checks.** `## Group DIM — driving dimensions (DIM-1 to DIM-4)`, **Status: PENDING.**, plans and spec named, run `swift run MetalCreatorApp` on the sketched bracket (Task 7's recipe written out for a person). Items, each with **Pinned:** (test names from DIM-1–4's merged code) and **Observed:**
  - **DIM-1 The ANSI look**: arrows filled 3:1, text horizontal and breaking the line, extension lines with a gap and overshoot, thin lines, Ø/R/2X notation, mm "60" vs inch ".50"; compare with an ASME Y14.5 drawing.
  - **DIM-2 Sketch dimensions**: D tool box on placement, placement picks horizontal/vertical/aligned, right-click Radius/Diameter and Driving/Reference, centre-to-centre and edge-to-edge, "2X Ø8" from Equal, over-define gives "(70)".
  - **DIM-3 Contextual and pinned**: click the hole pattern: "60" and "2X Ø8"; click empty space: gone; pin the plate length: stays while working on the holes, with its pin mark; no two labels overlap from the default views; edge-on dimensions hide.
  - **DIM-4 No jump**: double-click 60, type 70: nothing moves while typing; Return: holes 70 apart, one "Undo Change Dimension", nothing else moves, camera still; Esc and a click elsewhere change nothing; a flipping value and a failing value are refused in the box (needs DIM-a for the double-click; until then this check is blocked).
  - **DIM-5 Inches**: View ▸ Units ▸ Inches: texts in inches, "2.75" and "70 mm" both accepted, precision menu; a new document remembers inches.
  - **DIM-6 The model dimension tool**: D over the view (banner), two hole rims of a sketched plate add a dimension at its value and open its box; two edges from different features show the chip; an over-defining pair adds a grey reference; D in a panel field types; D in sketch mode is the sketch tool; the face menu's Dimension.
  - **DIM-7 Files**: save with inches, a pin and a placed sketch dimension; reopen: all three back; an older file opens in mm with nothing pinned.
  - **DIM-8 Linux and Windows**: DIM-1, DIM-3, DIM-4 and DIM-6 on a Linux or Windows build (SDL viewport).
- [ ] **Step 2: CLAUDE.md.** Project state, after the cable-ties line: "Driving dimensions (spec `docs/superpowers/specs/2026-10-27-driving-dimensions-design.md`, plans `2026-10-27-dim-overview.md` and `dim-1`…`dim-4`) code is done; its human checks (group DIM) are pending." Module notes: under CreatorSketch, `SketchRegion.sources`, `SketchTrace`, `ModelDimensionKind`, `MeasuredDimension`; under CreatorNodes, the Sketch node's `sketchTrace` and `SketchNode.projectedEntity`; under CreatorApp, the model dimension tool (`ModelDimensionSession`, the trace rule, D in the viewport key context, the face menu's Dimension, the box opened through `pendingValueBox`). Replace the CreatorSketchEditor note's "a read-only label per dimension (`SketchDimensionLabels`)" if DIM-1 left it. Check the file-format sentence says 10 with DIM-1's units, DIM-2's kinds and `labelPoint`, DIM-3's `dimensionPins`.
- [ ] **Step 3: Sketcher erratum.** In Errata (S5c), after the bullet ending "so the labels don't take the pointer": "- Reversed by driving dimensions (spec `2026-10-27-driving-dimensions-design.md` §4.1, §4.5): sketch dimensions are drawn as ANSI dimensions (`SketchDimensionDrawing`), and a double-click on a dimension's text opens its value box in the view; the inspector's fields stay."
- [ ] **Step 4: Gaps.** DIM-a's row and entry say whether it is adopted (DIM-1 Task 11) or still open, with the date.
- [ ] **Step 5: Commit** `docs: driving dimensions human checks, project state, sketcher erratum`.

### Task 10: Stage verification

- [ ] **Step 1:** `swiftlint lint --strict` — Expected: 0 violations.
- [ ] **Step 2:** `swift test 2>&1 | tee /private/tmp/claude-501/dim4-full.log`; `grep -c "Test run with" /private/tmp/claude-501/dim4-full.log` → 12; `grep -E "recorded an issue|failed after" /private/tmp/claude-501/dim4-full.log` → nothing; exit status 0.
- [ ] **Step 3:** `XP_TRACK=dim-4 IMAGE=metalcreator-linux:dim-4 scripts/linux-test.sh test` — Expected: exit 0, 12 "Test run with" lines, neither failure phrase; `DimensionAcceptanceTests` ran (its name appears in the log).
- [ ] **Step 4:** Report to the orchestrator: commits, any DIM-1/2/3 defect Tasks 7–8 found, any name in the table above that differed from the merged code, DIM-a's state.
