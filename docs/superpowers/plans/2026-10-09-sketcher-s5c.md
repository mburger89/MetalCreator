# Sketcher S5c — Project, New Sketch on Face, Dimension Labels and the Region Fill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the sketch editor's links to the model and the viewport (sketcher spec §8, as Errata (S5b) scopes it): Project an edge or a face from the ID buffer and keep it projected, "New sketch on face", dimension labels in the view, and the region fill; and fold in the S5b review's deferred items.

**Architecture:** The viewport grows what the editor needs and stays free of `CreatorGraph`: a tool can take the pick under a click it declined (`ViewportTool.clickedModel`), a face-menu item with an event, and `ViewportOverlay` gains world-anchored `labels` (MetalUI text over the surface, gap S5-c) and `fills` (blended triangles, a new pipeline). The editor gains `CreatorKernel` and stays graph-free: the Project tool asks its host to resolve a pick (`events.projection`), adds fixed `.projected` entities and hands the picks to store in its `SketchCommit`; a pure triangulator and a pure label builder feed the overlay. The app resolves picks with the Sketch node's own `EdgeProjection`, and `SketchStore` writes the picks and wires the solid in the same batch as the sketch (one undo step); "New sketch on face" is one more batch (Plane from Face → Sketch) followed by opening the sketch.

**Tech Stack:** Swift 6.4 (language mode 6, strict concurrency), Swift Testing, SwiftPM, MetalUI (`../MetalUI`, checked at 2155f1e), Metal (one more blended pipeline, runtime-compiled MSL).

**Base:** worktree `/Users/maxburger/Developer/MetalCreator-s5c`, branch `sketcher-s5c` off master **4e4be6e** (1643 tests). Check `git log --oneline -1 master` before Task 1: if master has moved, re-check each **Modify** anchor before its task, and add master's new tests to every count below.

**Spec:** `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md` (§3, §8, §10 and Errata (S4), (S5a), (S5b): the S5b/S5c split), under the binding parent spec `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` with all its Errata; the S5a plan (`2026-10-09-sketcher-s5-editor.md`, "S5b — the rest of S5") and the S5b plan (`2026-10-09-sketcher-s5b.md`, "S5c — the rest of S5") for the scope this plan finishes. Task 11 writes this plan's choices into the sketcher spec as "Errata (S5c)".

## What S5c is, and the task order

| # | Task | Needs | Touches |
|---|---|---|---|
| 1 | The S5b review's follow-ups | — | editor |
| 2 | A tool takes the pick under a declined click | — | viewport |
| 3 | "New Sketch on Face" in the face menu | — | viewport |
| 4 | Overlay labels (world-anchored text) | — | viewport |
| 5 | Filled overlay triangles | 4 | viewport |
| 6 | The region fill in the sketch overlay | 5 (and so 4) | editor |
| 7 | Dimension labels in the sketch overlay | 4, 6 | editor |
| 8 | The Project tool in the editor (CreatorKernel joins) | 1, 2 | editor, Package.swift |
| 9 | Project in the app | 8 | app, nodes |
| 10 | "New Sketch on Face" in the app | 3 | app, nodes |
| 11 | The record: gap S5-c, errata, human checks, CLAUDE.md, roadmap, handoff | all | docs |

The tasks are in the order they were checked, and the test totals below assume it. Only Tasks 1, 2, 3 and 4 are independent of each other (each was applied to master alone and built), so only they can be run in parallel by separate workers on separate branches. The rest are chains, and the "Needs" column is what each task's code needs to apply and compile: Task 5's whole-file `ViewportOverlay.swift` already holds Task 4's `labels` and its `ViewportModel+TextColors.swift` hunk edits the file Task 4 creates, so 5 needs 4 (and 6 needs 5, 7 needs 4 and 6); Task 8 edits the `case .select, .line, … .dimension: break` line Task 1 writes and consumes Task 2's `clickedModel`, so it needs 1 and 2; 9 needs 8; 10 needs 3. Task 7 edits `SketchEditorModel+Overlay.swift` and `SketchOverlayBuilder.swift` after Task 6, and Tasks 9 and 10 both edit `AppModel+Sketch.swift` (different functions); if the tasks run in parallel, the one that merges second keeps the other's hunks (every shared hunk is listed in "Files shared with other tracks"). Only the final total (master + 85, 1728 tests) is order-independent.

## Global Constraints

- Swift 6 strict concurrency (`swiftLanguageModes: [.v6]`); no `@unchecked Sendable`, no `nonisolated(unsafe)`, no GCD.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`); never XCTest.
- Shared state is `@MainActor @Observable` models; behaviour lives in models (and pure helpers), views are thin MetalUI `Component`s.
- One type per file (test fixture files under `Support/` may hold several, as the repo's do).
- No force unwraps or force `try`; number text uses `FormatStyle` (`.formatted(...)`), never `String(format:)`.
- `swiftlint lint --strict` reports zero violations (`.swiftlint.yml`: line length 140, type body 250, cyclomatic complexity 10, trailing commas in multi-line literals).
- A full `swift test` run passes only if its exit code is 0, no line says "recorded an issue" or "failed after" (Swift Testing prints glyphs, not ✘), and 11 "Test run with" lines appear. The **full-suite check** each task runs, from the worktree:

```bash
swift test > .build/s5c-test.log 2>&1; echo "exit $?"
grep -cE 'recorded an issue|failed after' .build/s5c-test.log   # 0
grep -c 'Test run with' .build/s5c-test.log                      # 11
grep -E 'Test run with' .build/s5c-test.log | awk '{s+=$5} END{print s}'   # the task's total
```

- `swift build --build-tests 2>&1 | grep -E 'warning:|error:'` shows nothing new. Master has one known test warning, `Tests/CreatorViewportTests/ContextMenuTests.swift:140` "'underPointer' mutated after capture by sendable closure", which prints whenever that file recompiles; it is not this plan's.
- Module boundaries (sketcher spec §2; CLAUDE.md): `CreatorViewport` depends on Kernel, Geometry, CreatorStyle and MetalUI only, **never CreatorGraph**. `CreatorSketchEditor` imports CreatorSketch, CreatorViewport, **CreatorKernel (new, for `EdgePick`)**, CreatorGeometry, CreatorStyle and MetalUI, and never CreatorGraph or CreatorNodes. `CreatorEditor` never imports CreatorNodes. `CreatorSketch` is unchanged. Only `CreatorApp` joins the graph with the editors.
- Colour hex values are written only in `CreatorStyle`: the region fill is the `profileHeader` role at 18% opacity (`ViewportPalette`), labels use the theme's roles.
- MetalUI gaps are logged in `docs/metalui-gaps.md` (the entry and the summary-table row) and never worked around silently; this plan adds **S5-c** (no text drawn inside a `MetalView`'s pass) with the stopgap the existing handle labels use (Tasks 4 and 11).
- Never edit `Package.swift`'s MetalUI path (`../MetalUI`), and never modify the `../MetalUI` repository. Task 8 edits `Package.swift` only to add `CreatorKernel` to two dependency lists.
- Each command is one undo step, applied as a `setInput` of the whole sketch (sketcher spec §8); a Project edit also stores its picks and the wire in that same batch; a refused command stores nothing.
- The camera stays locked to the sketch plane while sketching (Errata (S5a)): Project is a tool, so nothing turns the camera; "New Sketch on Face" is a face-menu item only outside sketch mode.
- File format stays version 5 (`GraphFile.currentFormatVersion`; groups made it 5) with no new keys: the projection settings (`projection.<reference>` = `.edgePicks`), `.facePick` and the wired plane are S4's. A stored sketch may now carry refreshed projection curves and `isSuspended`, both existing `ProjectionSource` fields.

## Files shared with other tracks

Tracks running now: **groups-comments**, **groups-editor** (EditorModel, canvas, inspector), **adopt-c10**, **kernel-blend-max**, **naming-face-picks** and **viewport-final-edges** (CreatorViewport and SceneBuilder: overlay and scene). Read from their worktrees' diffs against master (read-only) on the day this plan was written; each line says what the side that merges second must keep.

- **`Sources/CreatorViewport/Render/ViewportPipelines.swift`** — **viewport-final-edges** adds the `depthBehind` depth state (a property after `depthTest`, an init line after it); Task 5 adds the `fill` pipeline (a property after `grid`, an init line after `grid = …`). Different lines. The second keeps both.
- **`Sources/CreatorViewport/Render/ViewportRenderer.swift`** — final-edges makes `meshes` `private(set)`, filters guides out of the ID pass, the solids and the edges, and calls `drawGuides` just before `drawOverlay`; Task 5 adds one stored property (`fillBuffer`) after `overlayBuffer`. The second keeps both, and the draw order guides → overlay (fills, then lines).
- **`Sources/CreatorViewport/Render/ViewportRenderer+Overlay.swift`** — Task 5 replaces it whole (`drawFills` before the lines). Nobody else edits it today; if final-edges does, the second keeps `drawFills` first and the `drawOverlay` signature.
- **`Sources/CreatorViewport/Model/ViewportModel+Input.swift`** — final-edges edits `pivotPoint` (`item.isGuide`); Task 2 edits `click` and its doc comment. Different functions. The second keeps both. (A guide is never in the ID pass, so a pick's `solidIndex` always names a real solid in `items`; `resolveProjection` and `newSketchOnFace` rely on it.)
- **`Tests/CreatorViewportTests/GPUDataTests.swift`** — final-edges adds a test; Task 5 adds two `#expect` lines to the strides test. The second keeps both. **`Tests/CreatorViewportTests/OffscreenRenderTests.swift`** — Task 5 adds one test.
- **`Sources/CreatorViewport/Model/ViewportMenuItem.swift`, `ViewportEvents.swift`, `ViewportModel+ContextMenu.swift`** — Task 3 adds the "New Sketch on Face" item (order: Look At, Select Edges of Face, New Sketch on Face, Show Producing Node), its event and its `choose` case. No open track edits them today; a track that adds a face-menu item keeps this order and `ContextMenuTests`' expectations (including `showProducingNodeNamesEveryNodeOnAMergedFace`'s `dropFirst(3)`).
- **`Sources/CreatorNodes/Values/PlaneFromFaceNode.swift`** — **naming-face-picks** rewrites `evaluate`'s face matching (`topology.resolution(of:)`) and adds a warning; Task 10 only **appends** `plane(of:)` at the end of the enum and leaves `evaluate` alone, so the edits don't overlap. The second keeps both, and then makes `AppModel.unevaluatedFacePlane` (Task 10) call `topology.resolution(of: pick).faces.first` instead of `faces(matching: pick).first`, so the editor picks the face the node does. `Topology.facePick(for:)` (CreatorKernel) changes there to carry the normal and centroid: Task 3 and 10 pass it on unchanged and their tests compare with `facePick(for:)` itself, so they need no edit. That track also changes the shape of `SketchProjections.locate` and `EdgeTagMatch.choose`; `SketchNode.refreshingProjections` (Task 9, `SketchNode+Refresh.swift`) calls `SketchProjections.resolve`, whose signature is unchanged there, and must keep calling `resolve` (not `locate` or `choose`). After that merge re-run `SketchProjectTests`, `SketchRefreshTests` and `EdgeProjectionTests` (they rely on `topology.picks(for: [id])` returning one pick per edge and on `resolve` finding it).
- **`Sources/CreatorApp/AppModel+Sketch.swift`** — Tasks 9 and 10 change `beginSketch` (a `plane:` parameter), add `events.projection`, change `storeSketch`, `shownSketch` and `sketchPlane`. **groups-editor**'s plan expects to make sketch mode level-aware only after S5c: it rebases onto this. **`Sources/CreatorApp/AppModel+Viewport.swift`** — Task 10 adds one line to `connectViewportEvents`; groups-editor (with naming-face-picks and final-edges) edits other functions in it. Keep all lines. **`AppModel+Picking.swift`, `AppModel+Scene.swift`, `SceneBuilder.swift`, `PickSession.swift`** are not touched; this plan calls `producer(of:)` and `solid(at:)` from `AppModel+Picking.swift` as they are, so if groups-editor or naming-face-picks changes their signatures, the second updates the callers in `AppModel+Project.swift`, `AppModel+NewSketch.swift` and `AppModel+Sketch.swift`.
- **`Sources/CreatorApp/SketchStore.swift`**, `Sources/CreatorNodes/Sketch/EdgeProjection.swift` (now `public`), `Sources/CreatorNodes/Sketch/SketchNode+Refresh.swift` (new): nobody else's.
- **`Package.swift`** — Task 8 adds `CreatorKernel` to the `CreatorSketchEditor` target and its test target. No open track edits those two lines; a track that adds a target keeps both.
- Docs (Task 11): `CLAUDE.md` (every track), `docs/superpowers/roadmap.md` (every track), `docs/metalui-gaps.md` (a section at the end and one table row; **adopt-c10** edits the table's statuses), `docs/verification/human-checks.md` (group S5c at the end; every track appends a group), the sketcher spec (Errata (S5c) at the end), the handoff note (a section at the end). Whichever merges second re-applies its lines on the other's.
- The editor's and the viewport's own files (`SketchEditorModel*.swift`, `SketchTool.swift`, `SketchOverlayBuilder.swift`, `ViewportOverlay.swift`, `ViewportModel+Labels.swift`, `ViewportView+Parts.swift`, …) are not touched by any open track.

## Review Focus

The inputs the spec implies but its feature list doesn't exercise, most likely to bite first. Each has a test in the task that owns the code:

1. **Projecting an edge of a part made from the sketch itself** (the Sketch feeds the Extrude whose edge is clicked): wiring it into `references` would make a cycle. A person expects it refused in words, nothing stored. Test: `SketchProjectTests.aPartMadeFromThisSketchCantBeProjectedIntoIt` (Task 9).
2. **Projecting from a second part** when `references` already holds the first (it takes one wire): refused in words, the sketch and the wire untouched. Test: `SketchProjectTests.aSecondPartIsRefusedBecauseReferencesTakesOneWire` (Task 9).
3. **A face pick whose edges don't all project** (vertical edges, a side face whose top and bottom edges project to one line): the ones that can are stored once, in one undo step, and the rest are said in words. Tests: `aSideFaceKeepsWhatProjectsAndSaysWhatDoesNot` (Task 9), `someEdgesProjectingAndSomeNotStoresTheOnesThatDo…` and `anEdgeAlreadyProjectedIsLeftOutWithAReason` (Task 8).
4. **Regions that aren't a plain outline**: a hole, an island in the hole, open curves, construction geometry, several holes, a grid of aligned holes (a Pattern of rectangles: bridges run along other holes' edges), a notched outline. A person expects the fill exactly inside the region, and none rather than a wrong one when the clipper can't finish. Tests: `RegionFillTests`, `RegionTriangulatorTests` (`aGridOfAlignedSquareHolesLeavesEveryHoleEmpty`, `holesSharingAnEdgeLineWithEachOtherAndTheOutlineStillFill`, `aHoleThatCantBeBridgedGivesNoFillRatherThanAWrongOne`) (Task 6).
5. **"Edit sketch" on a sketch made by New Sketch on Face before anything draws it**: its Plane from Face feeds no Output, so it never evaluates, and without a plane the sketch couldn't open ("Wire a plane that evaluates"). Test: `NewSketchOnFaceTests.theSketchOpensAgainBeforeAnythingDrawsIt` (Task 10).

Smaller ones are tested where they live: a projection whose model moved is redrawn where the edge is now, and red when its pick finds nothing (Tasks 8, 9); a dimension whose geometry is gone has no label, a label off the view or during an animation isn't built (Tasks 4, 7); a circle's radius click and a centre arc's end click snap to no curve (Task 1); a projection whose part is gone by the time the commit is stored is refused in words and the editor goes back to the stored sketch (Task 9).

## File structure

**`Sources/CreatorViewport`** — create `Overlay/OverlayLabel.swift`, `Overlay/PlacedLabel.swift`, `Overlay/OverlayFill.swift`, `Render/FillVertex.swift`, `Render/FillBufferKey.swift`; replace `Overlay/ViewportOverlay.swift`, `Render/ViewportRenderer+Overlay.swift`, `View/ViewportModel+TextColors.swift`; modify `Tool/ViewportTool.swift`, `Model/ViewportModel+Input.swift`, `Model/ViewportMenuItem.swift`, `Model/ViewportEvents.swift`, `Model/ViewportModel+ContextMenu.swift`, `Model/ViewportModel+Labels.swift`, `View/ViewportView+Parts.swift`, `Overlay/OverlayTint.swift`, `Render/ViewportPalette.swift`, `Render/ViewportPalette+Overlay.swift`, `Render/OverlayGeometry.swift`, `Render/ViewportShaders.swift`, `Render/ViewportPipelines.swift`, `Render/ViewportRenderer.swift`.

**`Sources/CreatorSketchEditor`** — create `RegionTriangulator.swift`, `SketchRegionFills.swift`, `SketchDimensionLabels.swift`, `ProjectionCandidate.swift`, `ProjectionResolution.swift`, `ProjectionWrite.swift`, `SketchEditorModel+Project.swift`; replace `SketchCommit.swift`, `SketchEditorEvents.swift`, `SketchEditorModel+Overlay.swift`; modify `DrawState.swift`, `SketchTool.swift`, `SketchEditorModel.swift`, `SketchEditorModel+Drawing.swift`, `SketchEditorModel+Commands.swift`, `SketchEditorModel+ViewportTool.swift`, `SketchEditorModel+Dimensions.swift`, `SketchOverlayBuilder.swift`, `EditorGeometry.swift`, `Views/SketchToolButton.swift`.

**`Sources/CreatorNodes`** — create `Sketch/SketchNode+Refresh.swift`; modify `Sketch/EdgeProjection.swift` (public), `Values/PlaneFromFaceNode.swift` (append `plane(of:)`).

**`Sources/CreatorApp`** — create `AppModel+Project.swift`, `AppModel+NewSketch.swift`; modify `SketchStore.swift`, `AppModel+Sketch.swift`, `AppModel+Viewport.swift`.

**Tests** — create `CreatorSketchEditorTests/{SnapAndTangentCoverage,RegionTriangulator,RegionFill,DimensionLabel,ProjectTool}Tests.swift`, `CreatorViewportTests/{OverlayLabel,OverlayFill}Tests.swift`, `CreatorNodesTests/{SketchRefresh,FacePlane}Tests.swift`, `CreatorAppTests/{SketchProject,NewSketchOnFace}Tests.swift`; extend `RecordingTool`, `ViewportToolTests`, `ContextMenuTests`, `GPUDataTests`, `OffscreenRenderTests`, `ToolOptionsViewTests`, `SketchStoreTests`.

**Docs** — `docs/metalui-gaps.md`, the sketcher spec, `docs/verification/human-checks.md`, `CLAUDE.md`, `docs/superpowers/roadmap.md`, the handoff note.

---

### Task 1: The S5b review's follow-ups (editor only)

The four items the S5b review deferred, none of which needs the viewport: a circle's radius click and a centre arc's
end click are only sizes, so no curve under them may snap them (they snapped with no glyph); the hover scans the
curves once, and only for tools that place points; the command dispatch names the tools that aren't commands; and the
snaps and the tangent inference that had no test get one.

**Files:**
- Create: `Tests/CreatorSketchEditorTests/SnapAndTangentCoverageTests.swift`
- Modify: `Sources/CreatorSketchEditor/DrawState.swift`, `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, `Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift`

**Interfaces:**
- Consumes: S5b's `SketchEditorModel.anchor(at:tolerance:suppressed:)`, `hover(at:tolerance:modifiers:)`, `click(at:tolerance:modifiers:)`, `DrawState`, `RecordingHost` (`Tests/CreatorSketchEditorTests/Support/SketchFixtures.swift`).
- Produces: `DrawState.snapsToCurves: Bool` (false in `.circleAround` and `.arcFrom`), `SketchEditorModel.curvesSuppressed(_:) -> Bool`. No public API changes.

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorSketchEditorTests/SnapAndTangentCoverageTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// The S5b review's follow-ups: what a click that is only a size (a circle's radius, a centre arc's end) may snap
/// to, where a circle's centre and a 3-point arc's ends land when they are clicked on a curve, the tangent inference
/// from an arc's start, and the 3-point arc's end on its start's point.
@MainActor
struct SnapAndTangentCoverageTests {
    func makeModel(_ sketch: Sketch, tool: SketchTool) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(tool)
        return (model, RecordingHost(model))
    }

    /// A horizontal line along y = 0 from x = −50 to 50.
    func lineSketch() -> (sketch: Sketch, line: SketchEntityID) {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(-50, 0), Vector2(50, 0))
        return (sketch, line)
    }

    func constraints(_ sketch: Sketch) -> [SketchConstraint] {
        sketch.constraintIDs.compactMap { sketch.constraints[$0] }
    }

    /// The newest entity whose kind `matches`.
    func newest(in sketch: Sketch, where matches: (SketchEntityKind) -> Bool) -> SketchEntityID? {
        sketch.entityIDs.last { sketch.entities[$0].map { matches($0.kind) } ?? false }
    }

    func near(_ a: Vector2?, _ b: Vector2) -> Bool {
        guard let a else { return false }
        return (a - b).length < 1e-9
    }

    @Test func aCircleRadiusClickIsOnlyASizeSoNoCurveSnapsIt() throws {
        let (model, host) = makeModel(lineSketch().sketch, tool: .circle)
        model.click(at: Vector2(0, 20), tolerance: 1, modifiers: [])
        model.hover(at: Vector2(0, 0.4), tolerance: 1, modifiers: [])
        guard case .circle(_, let shown)? = model.preview.curves.first else {
            Issue.record("no rubber band")
            return
        }
        #expect(abs(shown - 19.6) < 1e-9, "the rubber band isn't snapped onto the line under the pointer")
        #expect(model.preview.inferred.isEmpty, "and shows no glyph, since nothing is inferred")
        model.click(at: Vector2(0, 0.4), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Circle"])
        let circle = try #require(newest(in: model.sketch) { if case .circle = $0 { true } else { false } })
        #expect(abs((model.sketch.radius(of: circle) ?? 0) - 19.6) < 1e-9)
        #expect(constraints(model.sketch).isEmpty)
    }

    @Test func aCentreArcsEndIsOnlyADirectionSoNoCurveHoldsIt() throws {
        var sketch = Sketch()
        sketch.addLine(Vector2(-50, 5), Vector2(50, 5))
        let (model, host) = makeModel(sketch, tool: .arc)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(10, 0), tolerance: 1, modifiers: [])
        // Off the arc's axis, so that snapping onto the line (to (3, 5)) would turn the ray: (3, 5.4) is the direction asked for.
        let asked = Vector2(3, 5.4)
        model.hover(at: asked, tolerance: 1, modifiers: [])
        #expect(model.preview.inferred.isEmpty)
        model.click(at: asked, tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Arc"])
        let arc = try #require(newest(in: model.sketch) { if case .arc = $0 { true } else { false } })
        guard case .arc(_, _, let end)? = model.sketch.entities[arc]?.kind else {
            Issue.record("no arc")
            return
        }
        #expect(near(model.sketch.position(of: end), asked * (10 / asked.length)),
                "the end lies on the start's radius, along the click and not along the snapped (3, 5)")
        #expect(constraints(model.sketch).isEmpty, "no point-on: the end was moved onto the radius, not held on the line")
    }

    @Test func aCircleCentreOnACurveIsHeldOnIt() throws {
        let (sketch, line) = lineSketch()
        let (model, host) = makeModel(sketch, tool: .circle)
        model.click(at: Vector2(20, 0.4), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20, 12), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Circle"])
        let circle = try #require(newest(in: model.sketch) { if case .circle = $0 { true } else { false } })
        guard case .circle(let centre, _)? = model.sketch.entities[circle]?.kind else {
            Issue.record("no circle")
            return
        }
        #expect(near(model.sketch.position(of: centre), Vector2(20, 0)), "snapped onto the line")
        #expect(constraints(model.sketch) == [.pointOn(point: centre, curve: line)])
        #expect(abs((model.sketch.radius(of: circle) ?? 0) - 12) < 1e-9)
    }

    @Test func aThreePointArcsEndsOnACurveAreHeldOnIt() {
        let (sketch, line) = lineSketch()
        let (model, host) = makeModel(sketch, tool: .arcThreePoint)
        model.click(at: Vector2(10, 0.3), tolerance: 1, modifiers: [])
        model.click(at: Vector2(30, -0.3), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20, 9), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Arc"])
        let held = constraints(model.sketch).filter { constraint in
            if case .pointOn(_, let curve) = constraint { curve == line } else { false }
        }
        #expect(held.count == 2, "the start and the end are each held on the line")
    }

    @Test func aLineLeavingAnArcsStartAlongItsTangentIsHeldTangent() throws {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let start = sketch.addPoint(Vector2(10, 0))
        let end = sketch.addPoint(Vector2(0, 10))
        let arc = sketch.addArc(center: center, start: start, end: end)
        let (model, _) = makeModel(sketch, tool: .line)
        model.click(at: Vector2(10.2, 0), tolerance: 1, modifiers: [])
        let aimed = Vector2(10.4, -20)
        model.hover(at: aimed, tolerance: 1, modifiers: [])
        #expect(model.preview.inferred == [.tangent], "down the tangent at the start, away from the arc")
        model.click(at: aimed, tolerance: 1, modifiers: [])
        let line = try #require(newest(in: model.sketch) { if case .line = $0 { true } else { false } })
        guard case .line(let from, let to)? = model.sketch.entities[line]?.kind else {
            Issue.record("no line")
            return
        }
        #expect(from == start)
        #expect(near(model.sketch.position(of: to), Vector2(10, -20)), "the end snapped onto the tangent")
        #expect(constraints(model.sketch) == [.tangent(line, arc)])
    }

    @Test func aThreePointArcsEndOnItsStartsPointWaits() {
        var sketch = Sketch()
        sketch.addPoint(Vector2(10, 0))
        let (model, host) = makeModel(sketch, tool: .arcThreePoint)
        model.click(at: Vector2(10.2, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(10.1, 0.1), tolerance: 1, modifiers: [])
        guard case .arcThroughFrom = model.drawState else {
            Issue.record("the end on the start's own point must not be taken: \(model.drawState)")
            return
        }
        model.click(at: Vector2(30, 0), tolerance: 1, modifiers: [])
        guard case .arcThrough = model.drawState else {
            Issue.record("a different end is taken: \(model.drawState)")
            return
        }
        #expect(host.commits.isEmpty)
    }

    @Test(arguments: [SketchTool.select, .dimension, .trim, .extend, .fillet, .mirror, .pattern])
    func hoveringWithAToolThatPlacesNoPointsShowsNoRubberBand(_ tool: SketchTool) {
        let (sketch, line) = lineSketch()
        let (model, _) = makeModel(sketch, tool: tool)
        model.hover(at: Vector2(20, 0.4), tolerance: 1, modifiers: [])
        #expect(model.hovered == line, "the entity under the pointer is still found")
        #expect(model.preview == .none)
    }
}
```

- [ ] **Step 2: Run the tests; the circle radius one and the centre arc end one fail**

Run: `swift test --filter SnapAndTangentCoverageTests`
Expected: FAIL in `aCircleRadiusClickIsOnlyASizeSoNoCurveSnapsIt` (the rubber band's radius is 20 and the circle's too: the line under the pointer snapped it) and in `aCentreArcsEndIsOnlyADirectionSoNoCurveHoldsIt` (the end lies along the snapped (3, 5), not along the click); the other five tests pass, because they pin behaviour S5b already has. (With the arc half of `placeArcPoint` left unfixed that test fails alone, so it can fail; `.project` joins the last test's arguments in Task 8, where the tool exists.)

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorSketchEditor/DrawState.swift`:

```swift
    case arcThrough(start: SketchAnchor, end: SketchAnchor)
}
```

with:

```swift
    case arcThrough(start: SketchAnchor, end: SketchAnchor)
}

extension DrawState {
    /// Whether the next click may be held on a curve under it (point-on, sketcher spec §8). A circle's radius point and
    /// a centre arc's end are only sizes and keep no point, so a curve under them must not move them: they would snap
    /// with no constraint and no glyph (`SketchEditorModel.inferredConstraints` infers nothing there).
    var snapsToCurves: Bool {
        switch self {
        case .circleAround, .arcFrom: false
        case .idle, .lineFrom, .arcAround, .arcThroughFrom, .arcThrough: true
        }
    }
}
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`:

```swift
        let suppressed = modifiers.contains(.command)
        // One anchor per move, shared by everything the move shows, so its curve scan runs once.
        let target = anchor(at: p, tolerance: tolerance, suppressed: suppressed)
        var next = rubberBand(to: p, landing: target, tolerance: tolerance, suppressed: suppressed)
        next.inferred = inferredConstraints(landing: target, tolerance: tolerance, suppressed: suppressed)
        if preview != next { preview = next }
```

with:

```swift
        // Only a tool that places points has a rubber band, so only it needs an anchor (and its second scan of the curves).
        var next = SketchPreview.none
        if tool.placesPoints {
            let suppressed = modifiers.contains(.command)
            // One anchor per move, shared by everything the move shows, so its curve scan runs once.
            let target = anchor(at: p, tolerance: tolerance, suppressed: curvesSuppressed(suppressed))
            next = rubberBand(to: p, landing: target, tolerance: tolerance, suppressed: suppressed)
            next.inferred = inferredConstraints(landing: target, tolerance: tolerance, suppressed: suppressed)
        }
        if preview != next { preview = next }
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`:

```swift
    /// A lone point, held on the curve it's clicked on; a click on an existing point adds nothing.
```

with:

```swift
    /// Whether a click now ignores the curves under it: ⌘ is held (`suppressed`), or the click is only a size
    /// (`DrawState.snapsToCurves`).
    func curvesSuppressed(_ suppressed: Bool) -> Bool { suppressed || !drawState.snapsToCurves }

    /// A lone point, held on the curve it's clicked on; a click on an existing point adds nothing.
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`:

```swift
    private func placeCirclePoint(at p: Vector2, tolerance: Double, suppressed: Bool) {
        guard case .circleAround(let center) = drawState else {
            drawState = .circleAround(anchor(at: p, tolerance: tolerance, suppressed: suppressed))
            return
        }
        let radius = (anchor(at: p, tolerance: tolerance, suppressed: suppressed).position - center.position).length
```

with:

```swift
    /// The centre (held on a curve or shared with a point, like any placed point), then a point on the circle: that
    /// click is only a size, so it snaps to an existing point's distance but never onto a curve.
    private func placeCirclePoint(at p: Vector2, tolerance: Double, suppressed: Bool) {
        guard case .circleAround(let center) = drawState else {
            drawState = .circleAround(anchor(at: p, tolerance: tolerance, suppressed: suppressed))
            return
        }
        let radius = (anchor(at: p, tolerance: tolerance, suppressed: curvesSuppressed(suppressed)).position - center.position).length
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`:

```swift
    private func placeArcPoint(at p: Vector2, tolerance: Double, suppressed: Bool) {
        let target = anchor(at: p, tolerance: tolerance, suppressed: suppressed)
```

with:

```swift
    private func placeArcPoint(at p: Vector2, tolerance: Double, suppressed: Bool) {
        let target = anchor(at: p, tolerance: tolerance, suppressed: curvesSuppressed(suppressed))
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift`:

```swift
        case .pattern: pattern(at: p, tolerance: tolerance)
        default: break
        }
```

with:

```swift
        case .pattern: pattern(at: p, tolerance: tolerance)
        case .select, .line, .arc, .arcThreePoint, .circle, .point, .dimension: break   // not commands: `click` routes them
        }
```

- [ ] **Step 4: Run the new tests, then the whole suite**

Run: `swift test --filter SnapAndTangentCoverageTests` — Expected: all pass.
Run the **full-suite check** (Global Constraints) — Expected: exit code 0, `0` failure lines, `11` runs, and a total of **master + 7** (1650).
Run: `swift build --build-tests 2>&1 | grep -E 'warning:|error:'` — Expected: nothing new. `swiftlint lint --strict --quiet` — Expected: nothing.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorSketchEditor Tests/CreatorSketchEditorTests
git commit -m "fix(sketch): a circle radius and a centre arc end snap to no curve; hover scans once; cover the snaps"
```

### Task 2: The viewport offers a declined click's pick to its tool

Project (§8) takes its edge from the ID buffer, and it must work while the camera is locked and the face menu is empty.
The viewport already picks under a click the tool declines (`ViewportEvents.clicked`). This task lets the tool take that
pick too, instead of the host, so Project is a sketch-mode tool: it declines `clicked(at:…)` (no plane click), and takes
the pick in `clickedModel(_:at:modifiers:projector:)`. Nothing turns the camera and no menu opens. `CreatorViewport`
stays free of `CreatorGraph`.

**Files:**
- Modify: `Sources/CreatorViewport/Tool/ViewportTool.swift`, `Sources/CreatorViewport/Model/ViewportModel+Input.swift`
- Modify (tests): `Tests/CreatorViewportTests/Support/RecordingTool.swift`, `Tests/CreatorViewportTests/ViewportToolTests.swift`

**Interfaces:**
- Consumes: `ViewportModel.pick` (the ID-buffer pick), `PickTarget`, `ViewportTool.clicked(at:modifiers:projector:)`.
- Produces: `ViewportTool.clickedModel(_ target: PickTarget?, at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool` (default `false`), called only for a click `clicked` declined and that no handle or the view cube took; a `true` keeps the click from `ViewportEvents.clicked`. `RecordingTool.claimsModel`, `RecordingTool.modelPicks`.

- [ ] **Step 1: Write the tests**

**Modify** `Tests/CreatorViewportTests/Support/RecordingTool.swift`:

```swift
    var claims = true
```

with:

```swift
    var claims = true
    /// Whether the tool takes the pick under a click it declined (`clickedModel`).
    var claimsModel = false
    /// The picks offered to `clickedModel`, in order (`nil`: empty space).
    private(set) var modelPicks: [PickTarget?] = []
```

**Modify** `Tests/CreatorViewportTests/Support/RecordingTool.swift`:

```swift
    func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {
        record("ended", point, projector)
    }
}
```

with:

```swift
    func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {
        record("ended", point, projector)
    }

    func clickedModel(_ target: PickTarget?, at point: ScreenPoint, modifiers: ViewportModifiers,
                      projector: ViewportProjector) -> Bool {
        modelPicks.append(target)
        return claimsModel
    }
}
```

**Modify** `Tests/CreatorViewportTests/ViewportToolTests.swift`:

```swift
    @Test func aClaimedDragMovesNoCamera() {
```

with:

```swift
    @Test func aDeclinedClickOffersThePickToTheTool() {
        let tool = RecordingTool()
        tool.claims = false
        let model = makeModel(tool: tool)
        model.pick = { _ in .edge(solid: 0, EdgeID(3)) }
        var reported: [PickTarget?] = []
        model.events.clicked = { reported.append($0) }
        model.click(at: ScreenPoint(200, 150))
        #expect(tool.modelPicks == [.edge(solid: 0, EdgeID(3))])
        #expect(reported == [.edge(solid: 0, EdgeID(3))], "the tool left it, so the host hears it as before")
    }

    @Test func aToolThatTakesThePickKeepsItFromTheHost() {
        let tool = RecordingTool()
        tool.claims = false
        tool.claimsModel = true
        let model = makeModel(tool: tool)
        model.pick = { point in point.x < 100 ? .face(solid: 0, FaceID(1)) : nil }
        var reported: [PickTarget?] = []
        model.events.clicked = { reported.append($0) }
        model.click(at: ScreenPoint(50, 150))
        model.click(at: ScreenPoint(300, 150))
        #expect(tool.modelPicks == [.face(solid: 0, FaceID(1)), nil], "empty space is offered too")
        #expect(reported.isEmpty)
    }

    @Test func aClaimedClickIsNotOfferedAPick() {
        let tool = RecordingTool()
        tool.claimsModel = true
        let model = makeModel(tool: tool)
        model.pick = { _ in .face(solid: 0, FaceID(1)) }
        model.click(at: ScreenPoint(200, 150))
        #expect(tool.modelPicks.isEmpty, "the tool claimed the click on the plane, so there is nothing to offer")
    }

    @Test func theCubeAndTheHandlesKeepTheirClicksFromTheToolsPick() {
        let tool = RecordingTool()
        tool.claims = false
        tool.claimsModel = true
        let model = makeModel(tool: tool)
        model.pick = { _ in .face(solid: 0, FaceID(1)) }
        model.click(at: model.cubeLayout.center)
        #expect(tool.modelPicks.isEmpty)
    }

    @Test func aClaimedDragMovesNoCamera() {
```

- [ ] **Step 2: Run the tests; the first two fail**

Run: `swift test --filter ViewportToolTests`
Expected: FAIL in `aDeclinedClickOffersThePickToTheTool` and `aToolThatTakesThePickKeepsItFromTheHost` (`modelPicks` is empty: nothing offers the pick); the other two pass.

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorViewport/Tool/ViewportTool.swift`:

```swift
    func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool
```

with:

```swift
    func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool
    /// A click `clicked(at:…)` declined, with the face or edge the ID pass found under it (`nil`: empty space), for a
    /// tool that works on the model (the sketch editor's Project). Return true to claim it; unclaimed, the viewport
    /// reports the pick as usual (`ViewportEvents.clicked`). It is not called for a click the view cube or a handle took.
    func clickedModel(_ target: PickTarget?, at point: ScreenPoint, modifiers: ViewportModifiers,
                      projector: ViewportProjector) -> Bool
```

**Modify** `Sources/CreatorViewport/Tool/ViewportTool.swift`:

```swift
extension ViewportTool {
    public var navigation: ViewportNavigation { .free }
    public var framingBounds: BoundingBox? { nil }
}
```

with:

```swift
extension ViewportTool {
    public var navigation: ViewportNavigation { .free }
    public var framingBounds: BoundingBox? { nil }
    public func clickedModel(_ target: PickTarget?, at point: ScreenPoint, modifiers: ViewportModifiers,
                             projector: ViewportProjector) -> Bool {
        false
    }
}
```

**Modify** `Sources/CreatorViewport/Model/ViewportModel+Input.swift`:

```swift
    /// elsewhere the `tool` may claim it, and otherwise it reports the face or edge under the pointer, or `nil` for
    /// empty space. `modifiers` are the click's (MetalUI's tap reports none yet: docs/metalui-gaps.md S5-a).
```

with:

```swift
    /// elsewhere the `tool` may claim it, and otherwise the face or edge under the pointer (or `nil` for empty space)
    /// is offered to the tool (`clickedModel`) and, unclaimed, reported. `modifiers` are the click's (MetalUI's tap
    /// reports none yet: docs/metalui-gaps.md S5-a).
```

**Modify** `Sources/CreatorViewport/Model/ViewportModel+Input.swift`:

```swift
                  tool?.clicked(at: point, modifiers: modifiers, projector: projector) != true {
            events.clicked(pick?(point))
        }
```

with:

```swift
                  tool?.clicked(at: point, modifiers: modifiers, projector: projector) != true {
            let target = pick?(point)
            if tool?.clickedModel(target, at: point, modifiers: modifiers, projector: projector) != true {
                events.clicked(target)
            }
        }
```

- [ ] **Step 4: Run the tests and the full-suite check**

Run: `swift test --filter ViewportToolTests` — Expected: all pass.
Run the **full-suite check** — Expected: exit 0, `0`, `11`, total **master + 11** (1654). Build with no new warnings; `swiftlint lint --strict --quiet` prints nothing.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorViewport Tests/CreatorViewportTests
git commit -m "feat(viewport): a tool can take the pick under a click it declined"
```

### Task 3: "New Sketch on Face" in the face menu

Sketcher spec §8: "Enter by … using the face context menu's New sketch on face." The viewport adds the menu item and an
event carrying the face and its remembered pick; the host (Task 10) builds the graph. The item is offered only on a flat
face that has a normal (what Plane from Face accepts), and only outside sketch mode: while a tool is set the menu is
Look At alone, and with planar navigation it is empty (Errata (S5a)).

**Files:**
- Modify: `Sources/CreatorViewport/Model/ViewportMenuItem.swift`, `Sources/CreatorViewport/Model/ViewportEvents.swift`, `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift`
- Modify (tests): `Tests/CreatorViewportTests/ContextMenuTests.swift`

**Interfaces:**
- Consumes: `Topology.facePick(for:) -> FacePick?`, `FaceInfo.kind`, `FaceInfo.normal`.
- Produces: `ViewportMenuItem.newSketchOnFace(ViewportFaceRef)` (title "New Sketch on Face"), `ViewportEvents.newSketchOnFace: @MainActor (ViewportFaceRef, FacePick) -> Void`.

- [ ] **Step 1: Write the tests**

**Modify** `Tests/CreatorViewportTests/ContextMenuTests.swift`:

```swift
    @Test func nothingUnderThePressMeansNoMenu() async throws {
```

with:

```swift
    /// `fakeBox`'s end cap (face 1) is flat and has a normal; its side faces are flat too but carry none.
    @Test func aFlatFaceWithANormalOffersNewSketchOnFace() async throws {
        let model = await model(showing: [try await fakeBox()])
        let cap = ViewportFaceRef(solidIndex: 0, face: FaceID(1))
        model.pick = { _ in .face(solid: 0, FaceID(1)) }
        let items = model.contextMenuItems(at: ScreenPoint(300, 200))
        #expect(items.prefix(3).map(\.title) == ["Look At", "Select Edges of Face", "New Sketch on Face"])
        #expect(items.contains(.newSketchOnFace(cap)))
        model.pick = { _ in .face(solid: 0, FaceID(2)) }
        #expect(!model.contextMenuItems(at: ScreenPoint(301, 200)).contains { item in
            if case .newSketchOnFace = item { true } else { false }
        }, "a face with no normal can't have a Plane from Face")
    }

    @Test func aCurvedFaceOffersNoSketch() async throws {
        let face = FaceInfo(id: FaceID(0), kind: .cylinder, normal: .unitZ, area: 1, centroid: .zero, tags: [])
        let cylinder = Solid(topology: Topology(faces: [face], edges: []),
                             bounds: BoundingBox(min: .zero, max: Vector3(1, 1, 1)), storage: TestStorage())
        let model = await model(showing: [cylinder])
        model.pick = { _ in .face(solid: 0, FaceID(0)) }
        let ref = ViewportFaceRef(solidIndex: 0, face: FaceID(0))
        #expect(model.contextMenuItems(at: ScreenPoint(300, 200)) == [.lookAt(ref), .selectEdgesOfFace(ref)])
    }

    @Test func whileAToolHoldsThePointerTheMenuIsLookAtAlone() async throws {
        let model = await model(showing: [try await fakeBox()])
        model.tool = RecordingTool()
        model.pick = { _ in .face(solid: 0, FaceID(1)) }
        #expect(model.contextMenuItems(at: ScreenPoint(300, 200)) == [.lookAt(ViewportFaceRef(solidIndex: 0, face: FaceID(1)))])
    }

    @Test func choosingNewSketchOnFaceReportsTheFaceAndItsRememberedPick() async throws {
        let solid = try await fakeBox()
        let model = await model(showing: [solid])
        var reported: [(face: ViewportFaceRef, pick: FacePick)] = []
        model.events.newSketchOnFace = { reported.append(($0, $1)) }
        let ref = ViewportFaceRef(solidIndex: 0, face: FaceID(1))
        model.choose(.newSketchOnFace(ref))
        #expect(reported.map(\.face) == [ref])
        #expect(reported.first?.pick == solid.topology.facePick(for: FaceID(1)))
        model.choose(.newSketchOnFace(ViewportFaceRef(solidIndex: 5, face: FaceID(1))))
        #expect(reported.count == 1, "a face of a solid that is gone reports nothing")
    }

    @Test func nothingUnderThePressMeansNoMenu() async throws {
```

The merged face in `showProducingNodeNamesEveryNodeOnAMergedFace` is flat with a normal, so its menu now has three
fixed items before the producing nodes:

**Modify** `Tests/CreatorViewportTests/ContextMenuTests.swift`:

```swift
        #expect(Array(titles.dropFirst(2)) == expected)
```

with:

```swift
        #expect(Array(titles.dropFirst(3)) == expected)
```

**Modify** `Tests/CreatorViewportTests/ContextMenuTests.swift`:

```swift
        for item in model.contextMenuItems(at: ScreenPoint(300, 200)).dropFirst(2) { model.choose(item) }
```

with:

```swift
        for item in model.contextMenuItems(at: ScreenPoint(300, 200)).dropFirst(3) { model.choose(item) }
```

- [ ] **Step 2: Run the tests; they don't compile**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: errors "has no member 'newSketchOnFace'" (the case and the event don't exist yet), so nothing runs.

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorViewport/Model/ViewportMenuItem.swift`:

```swift
    case selectEdgesOfFace(ViewportFaceRef)
```

with:

```swift
    case selectEdgesOfFace(ViewportFaceRef)
    /// A Plane from Face and a Sketch on it, opened for drawing (sketcher spec §8). Only on a flat face, only outside
    /// sketch mode.
    case newSketchOnFace(ViewportFaceRef)
```

**Modify** `Sources/CreatorViewport/Model/ViewportMenuItem.swift`:

```swift
        case .selectEdgesOfFace: "Select Edges of Face"
```

with:

```swift
        case .selectEdgesOfFace: "Select Edges of Face"
        case .newSketchOnFace: "New Sketch on Face"
```

**Modify** `Sources/CreatorViewport/Model/ViewportEvents.swift`:

```swift
    /// "Show Producing Node": the node that made the face, from its tags.
```

with:

```swift
    /// "New Sketch on Face" (sketcher spec §8): the flat face, and its remembered pick (`topology.facePick(for:)`, the
    /// encoding Plane from Face stores). The host wraps the pick as `.facePick(…)`; the viewport never builds a graph value.
    public var newSketchOnFace: @MainActor (ViewportFaceRef, FacePick) -> Void = { _, _ in }
    /// "Show Producing Node": the node that made the face, from its tags.
```

**Modify** `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift`:

```swift
        var menu: [ViewportMenuItem] = [.lookAt(ref), .selectEdgesOfFace(ref)]
```

with:

```swift
        var menu: [ViewportMenuItem] = [.lookAt(ref), .selectEdgesOfFace(ref)]
        // Plane from Face takes a flat face with a normal (`PlaneFromFaceNode`); another face would only make an error.
        if face.kind == .plane, face.normal != nil { menu.append(.newSketchOnFace(ref)) }
```

**Modify** `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift`:

```swift
        case .showProducingNode(let node, _):
            events.showProducingNode(node)
```

with:

```swift
        case .showProducingNode(let node, _):
            events.showProducingNode(node)
        case .newSketchOnFace(let ref):
            guard items.indices.contains(ref.solidIndex),
                  let pick = items[ref.solidIndex].solid.topology.facePick(for: ref.face) else { return }
            events.newSketchOnFace(ref, pick)
```

- [ ] **Step 4: Run the tests and the full-suite check**

Run: `swift test --filter ContextMenuTests` — Expected: all pass.
Run the **full-suite check** — Expected: exit 0, `0`, `11`, total **master + 15** (1658) . No new warnings; lint clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorViewport Tests/CreatorViewportTests
git commit -m "feat(viewport): New Sketch on Face in the face menu"
```

### Task 4: Overlay labels in the viewport

Sketcher spec §8 puts dimension values in the view. The viewport gets a label API on `ViewportOverlay`: text anchored at
a world point, projected with the camera and drawn as MetalUI text over the surface, as the handle values are
(`handleLabels()`). **MetalUI gap S5-c** (Task 11 logs it): MetalUI can't draw text inside a `MetalView`'s pass, so these
labels are element-tree text rebuilt when the pose, the overlay or the size changes; a camera animation doesn't rebuild
the tree (gap M4-b), so the labels are hidden while one runs (the Look At onto the plane when a sketch opens). That is the
stopgap the existing labels use. The labels are read-only: spec §8 puts the editable name and value fields in the
inspector, and says nothing of editing in the view.

**Files:**
- Create: `Sources/CreatorViewport/Overlay/OverlayLabel.swift`, `Sources/CreatorViewport/Overlay/PlacedLabel.swift`, `Tests/CreatorViewportTests/OverlayLabelTests.swift`
- Replace: `Sources/CreatorViewport/Overlay/ViewportOverlay.swift`, `Sources/CreatorViewport/View/ViewportModel+TextColors.swift`
- Modify: `Sources/CreatorViewport/Model/ViewportModel+Labels.swift`, `Sources/CreatorViewport/View/ViewportView+Parts.swift`

**Interfaces:**
- Consumes: `CameraMath.project(_:_:size:)`, `ViewportModel.observedViewSize`, `isAnimating`, `OverlayTint`.
- Produces: `OverlayLabel(_ text: String, at position: Vector3, tint: OverlayTint = .fullyConstrained, nudge: Vector3? = nil)` and `OverlayLabel.nudgeDistance` (16 points); `ViewportOverlay.labels: [OverlayLabel]` (init parameter `labels:` between `points:` and `gridPlane:`); `PlacedLabel(text:tint:origin:size:)` and `PlacedLabel.size(of:) -> ViewportSize`; `ViewportModel.overlayLabels() -> [PlacedLabel]`; `ViewportModel.textColor(for: OverlayTint) -> Color`.

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorViewportTests/OverlayLabelTests.swift`:

```swift
import CreatorGeometry
import Foundation
import MetalUI
import MetalUIText
import Testing
@testable import CreatorViewport

/// Overlay labels (sketcher spec §8's dimension values): anchored in world space, projected every frame, nudged along a
/// world direction as it looks on screen, hidden while the camera animates, and drawn as text over the surface.
@MainActor
struct OverlayLabelTests {
    let top = CameraPose(target: .zero, distance: 100, pitch: .pi / 2, projection: .orthographic)
    let size = ViewportSize(width: 400, height: 300)

    func makeModel(_ labels: [OverlayLabel]) -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: top, clock: ManualClock())
        model.viewSize = size
        model.showOverlay(ViewportOverlay(labels: labels))
        return model
    }

    func centre(_ label: PlacedLabel) -> ScreenPoint {
        ScreenPoint(label.origin.x + label.size.width / 2, label.origin.y + label.size.height / 2)
    }

    @Test func aLabelIsCentredOnItsProjectedAnchor() throws {
        let model = makeModel([OverlayLabel("12.5 mm", at: .zero)])
        let placed = try #require(model.overlayLabels().first)
        #expect(placed.text == "12.5 mm")
        #expect(placed.size == PlacedLabel.size(of: "12.5 mm"))
        #expect(abs(centre(placed).x - 200) < 1e-6 && abs(centre(placed).y - 150) < 1e-6, "the target is the view's centre")
    }

    @Test func theBoxHoldsTheTextAtSevenPointsACharacter() {
        let box = PlacedLabel.size(of: "12.5 mm")
        #expect(box.width == 7 * 7 + 2 * PlacedLabel.padding)
        #expect(box.height == PlacedLabel.height)
        #expect(PlacedLabel.size(of: "").width == 2 * PlacedLabel.padding)
    }

    @Test func aNudgeMovesTheLabelSixteenPointsAlongTheDirectionAsItLooksOnScreen() throws {
        let anchor = try #require(makeModel([OverlayLabel("a", at: .zero)]).overlayLabels().first)
        let right = try #require(makeModel([OverlayLabel("a", at: .zero, nudge: .unitX)]).overlayLabels().first)
        let left = try #require(makeModel([OverlayLabel("a", at: .zero, nudge: -Vector3.unitX)]).overlayLabels().first)
        let (home, a, b) = (centre(anchor), centre(right), centre(left))
        #expect(abs(hypot(a.x - home.x, a.y - home.y) - OverlayLabel.nudgeDistance) < 1e-6)
        #expect(abs(a.x + b.x - 2 * home.x) < 1e-6 && abs(a.y + b.y - 2 * home.y) < 1e-6, "opposite nudges are opposite")
        let edgeOn = try #require(makeModel([OverlayLabel("a", at: .zero, nudge: .unitZ)]).overlayLabels().first)
        #expect(centre(edgeOn) == home, "a nudge along the line of sight has no direction on screen: no nudge")
    }

    @Test func labelsOutsideTheViewOrOfAnEmptyViewOrDuringAnAnimationAreLeftOut() {
        let model = makeModel([OverlayLabel("in", at: .zero), OverlayLabel("far", at: Vector3(1e6, 0, 0))])
        #expect(model.overlayLabels().map(\.text) == ["in"], "a box wholly outside the view is dropped")
        model.perform(.view(.front))
        #expect(model.isAnimating)
        #expect(model.overlayLabels().isEmpty, "labels can't follow a running animation (gap M4-b)")
        let blank = makeModel([OverlayLabel("in", at: .zero)])
        blank.viewSize = ViewportSize(width: 0, height: 0)
        #expect(blank.overlayLabels().isEmpty)
    }

    @Test func aLabelsTextTakesItsTintsRoleInTheTheme() {
        let model = makeModel([])
        let colors = model.theme.colors
        #expect(model.textColor(for: .conflicting) == colors.sketchConflicting.color)
        #expect(model.textColor(for: .fullyConstrained) == colors.sketchFullyConstrained.color)
        #expect(model.textColor(for: .construction) == colors.sketchConstruction.color)
        #expect(model.textColor(for: .selected) == colors.profileHeader.color)
    }

    @Test func labelsAreTheOverlaysToo() {
        let overlay = ViewportOverlay(labels: [OverlayLabel("a", at: .zero)])
        #expect(!overlay.isEmpty)
        let model = makeModel([])
        let before = model.renderKey
        model.showOverlay(overlay)
        #expect(model.renderKey != before)
    }

    @Test func theViewDrawsEachLabelsTextInsideItsBox() throws {
        let model = makeModel([OverlayLabel("12.5 mm", at: .zero)])
        let big = ViewportSize(width: 1400, height: 900)
        model.viewSize = big
        let placed = try #require(model.overlayLabels().first)
        let scene = renderFrame({ ZStack { ViewportView(model: model) } }, size: Size(width: Pixels(1400), height: Pixels(900)),
                                scaleFactor: 2, textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        let inside = scene.glyphs.filter { glyph in
            let x = Double(glyph.bounds.origin.x + glyph.bounds.size.width / 2) / 2
            let y = Double(glyph.bounds.origin.y + glyph.bounds.size.height / 2) / 2
            return x >= placed.origin.x && x <= placed.origin.x + placed.size.width
                && y >= placed.origin.y && y <= placed.origin.y + placed.size.height
        }
        #expect(inside.count == 6, "1 2 . 5 m m: the glyphs of the text, without its space")
    }
}
```

- [ ] **Step 2: Run the tests; they don't compile**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: errors for `OverlayLabel`, `PlacedLabel` and `ViewportOverlay(labels:)`.

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorViewport/Overlay/OverlayLabel.swift`:

```swift
import CreatorGeometry

/// A piece of text the host anchors in world space (a sketch dimension's value, sketcher spec §8). The viewport projects
/// the anchor with the camera every frame and draws the text over the surface in a small glass box
/// (`ViewportModel.overlayLabels()`). It never takes the pointer.
public struct OverlayLabel: Hashable, Sendable {
    /// How far (points) a label with a `nudge` sits from its anchor.
    public static let nudgeDistance = 16.0

    public var text: String
    /// The world point the label sits at.
    public var position: Vector3
    /// The role the text is coloured in (the theme's colour for that tint).
    public var tint: OverlayTint
    /// A world direction to move the label away along, `nudgeDistance` points, in whichever way that points on screen, so
    /// the box clears the geometry it names (a dimension's label stands off the line it measures). `nil`: centred on
    /// the anchor.
    public var nudge: Vector3?

    public init(_ text: String, at position: Vector3, tint: OverlayTint = .fullyConstrained, nudge: Vector3? = nil) {
        self.text = text
        self.position = position
        self.tint = tint
        self.nudge = nudge
    }
}
```

**Create** `Sources/CreatorViewport/Overlay/PlacedLabel.swift`:

```swift
/// An overlay label on screen: the box the view draws it in, in viewport points (y down). The box is computed from the
/// text, never measured, so drawing and placement agree (as the sketch editor's readout chip is): `.caption` is 10 pt and
/// its widest characters (digits, "⌀", "°", "-") advance under 7 pt.
public struct PlacedLabel: Hashable, Sendable {
    public static let height = 20.0
    public static let characterWidth = 7.0
    public static let padding = 6.0

    public var text: String
    public var tint: OverlayTint
    /// The box's top-left corner.
    public var origin: ScreenPoint
    public var size: ViewportSize

    public init(text: String, tint: OverlayTint, origin: ScreenPoint, size: ViewportSize) {
        self.text = text
        self.tint = tint
        self.origin = origin
        self.size = size
    }

    /// The box that holds `text`.
    public static func size(of text: String) -> ViewportSize {
        ViewportSize(width: Double(text.count) * characterWidth + 2 * padding, height: height)
    }
}
```

**Replace the whole of** `Sources/CreatorViewport/Overlay/ViewportOverlay.swift`:

```swift
import CreatorGeometry

/// Lines, points and labels the host draws over the scene, on top of everything but the widgets (the sketch editor's
/// geometry and dimension values, sketcher spec §8). With a `gridPlane`, a grid on that plane replaces the ground
/// grid. The viewport never interprets it: the host builds it, the viewport draws it.
public struct ViewportOverlay: Hashable, Sendable {
    public var lines: [OverlayLine]
    public var points: [OverlayPoint]
    /// Text anchored in world space, drawn over the surface (`ViewportModel.overlayLabels()`).
    public var labels: [OverlayLabel]
    /// The plane whose grid is drawn instead of the ground grid, or `nil` for the ground grid.
    public var gridPlane: Plane?

    public init(lines: [OverlayLine] = [], points: [OverlayPoint] = [], labels: [OverlayLabel] = [], gridPlane: Plane? = nil) {
        self.lines = lines
        self.points = points
        self.labels = labels
        self.gridPlane = gridPlane
    }

    public var isEmpty: Bool { lines.isEmpty && points.isEmpty && labels.isEmpty && gridPlane == nil }
}
```

**Modify** `Sources/CreatorViewport/Model/ViewportModel+Labels.swift`:

```swift
    /// The unit and grid label (spec §6.3), such as "mm · grid 10 mm".
```

with:

```swift
    /// The overlay's labels on screen (`ViewportOverlay.labels`): each box centred on its anchor projected with the camera,
    /// moved `OverlayLabel.nudgeDistance` points along its nudge as that looks on screen. Left out: all of them while
    /// the camera animates (as the handle labels are), an anchor at or behind a perspective eye, and a box wholly
    /// outside the view. Gap S5-c: this is element-tree text, not text in the Metal pass.
    public func overlayLabels() -> [PlacedLabel] {
        let size = observedViewSize
        guard !size.isEmpty, !isAnimating, !overlay.labels.isEmpty else { return [] }
        return overlay.labels.compactMap { label in
            guard let anchor = CameraMath.project(label.position, pose, size: size)?.point else { return nil }
            var centre = anchor
            if let nudge = label.nudge, let tip = CameraMath.project(label.position + nudge, pose, size: size)?.point {
                let (dx, dy) = (tip.x - anchor.x, tip.y - anchor.y)
                let length = (dx * dx + dy * dy).squareRoot()
                if length > 1e-6 {
                    centre = ScreenPoint(anchor.x + dx / length * OverlayLabel.nudgeDistance,
                                         anchor.y + dy / length * OverlayLabel.nudgeDistance)
                }
            }
            let box = PlacedLabel.size(of: label.text)
            let origin = ScreenPoint(centre.x - box.width / 2, centre.y - box.height / 2)
            guard origin.x + box.width > 0, origin.y + box.height > 0, origin.x < size.width, origin.y < size.height else {
                return nil
            }
            return PlacedLabel(text: label.text, tint: label.tint, origin: origin, size: box)
        }
    }

    /// The unit and grid label (spec §6.3), such as "mm · grid 10 mm".
```

**Replace the whole of** `Sources/CreatorViewport/View/ViewportModel+TextColors.swift`:

```swift
import MetalUI

extension ViewportModel {
    /// Primary text over the viewport: the theme's foreground (#f8f8f2 in Dracula, spec §6.6).
    var labelColor: Color { theme.colors.foreground.color }
    /// Secondary and hint text: the theme's comment colour (#6272a4 in Dracula).
    var hintColor: Color { theme.colors.comment.color }
    /// An overlay label's box: the theme's glass.
    var labelFill: Color { theme.colors.glassFill.color }

    /// An overlay label's text colour: its tint's role in the theme, the same role the GPU draws that tint in.
    func textColor(for tint: OverlayTint) -> Color {
        let colors = theme.colors
        return switch tint {
        case .underConstrained, .preview: colors.sketchUnderConstrained.color
        case .fullyConstrained: colors.sketchFullyConstrained.color
        case .conflicting: colors.sketchConflicting.color
        case .construction: colors.sketchConstruction.color
        case .projected: colors.sketchProjected.color
        case .selected: colors.profileHeader.color
        case .hovered: colors.focus.color
        }
    }
}
```

**Modify** `Sources/CreatorViewport/View/ViewportView+Parts.swift`:

```swift
            if model.showsViewCube { cubeControls(model: model) }
```

with:

```swift
            for label in model.overlayLabels() {
                ProposalText(label.text)
                    .font(.caption)
                    .foregroundStyle(model.textColor(for: label.tint))
                    .frame(width: Pixels(Float(label.size.width)), height: Pixels(Float(label.size.height)))
                    .background(model.labelFill, in: RoundedRectangle(cornerRadius: Pixels(4)))
                    .offset(x: Pixels(Float(label.origin.x)), y: Pixels(Float(label.origin.y)))
                    .allowsHitTesting(false)
            }
            if model.showsViewCube { cubeControls(model: model) }
```

- [ ] **Step 4: Run the tests and the full-suite check**

Run: `swift test --filter OverlayLabelTests` — Expected: all pass.
Run the **full-suite check** — Expected: exit 0, `0`, `11`, total **master + 22** (1665). No new warnings; lint clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorViewport Tests/CreatorViewportTests
git commit -m "feat(viewport): overlay labels, anchored in world space and drawn as text over the surface"
```

### Task 5: Filled triangles in the overlay

Sketcher spec §8's "Output regions: faint green fill" needs filled geometry under the overlay's lines. The viewport gets
`OverlayFill` (world-space triangles in an `OverlayTint`), a `.region` tint (the Sketch node's header green at 18%
opacity), a blended `fill` pipeline with its shader, a cached vertex buffer, and draws the fills just before the
overlay's lines (so the grid, the curves and the points sit on top). Fills are never in the ID pass, so a click goes
through them. The editor builds them in Task 6.

**Files:**
- Create: `Sources/CreatorViewport/Overlay/OverlayFill.swift`, `Sources/CreatorViewport/Render/FillVertex.swift`, `Sources/CreatorViewport/Render/FillBufferKey.swift`, `Tests/CreatorViewportTests/OverlayFillTests.swift`
- Replace: `Sources/CreatorViewport/Overlay/ViewportOverlay.swift`, `Sources/CreatorViewport/Render/ViewportRenderer+Overlay.swift`
- Modify: `Sources/CreatorViewport/Overlay/OverlayTint.swift`, `Sources/CreatorViewport/Render/ViewportPalette.swift`, `Sources/CreatorViewport/Render/ViewportPalette+Overlay.swift`, `Sources/CreatorViewport/Render/OverlayGeometry.swift`, `Sources/CreatorViewport/Render/ViewportShaders.swift`, `Sources/CreatorViewport/Render/ViewportPipelines.swift`, `Sources/CreatorViewport/Render/ViewportRenderer.swift`, `Sources/CreatorViewport/View/ViewportModel+TextColors.swift`
- Modify (tests): `Tests/CreatorViewportTests/GPUDataTests.swift`, `Tests/CreatorViewportTests/OffscreenRenderTests.swift`

**Interfaces:**
- Consumes: `ViewportOverlay(lines:points:labels:gridPlane:)` (Task 4), `ViewportPalette.color(_:)`, `GPUBuffers.make`.
- Produces: `OverlayFill(vertices: [Vector3], tint: OverlayTint = .region)` with `triangleCount`; `OverlayTint.region`; `ViewportOverlay.fills: [OverlayFill]` (init parameter `fills:` between `points:` and `labels:`); `ViewportPalette.sketchRegion`; `FillVertex` (32 bytes); `OverlayGeometry.fillVertices(_:palette:) -> [FillVertex]`.

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorViewportTests/OverlayFillTests.swift`:

```swift
import CreatorGeometry
import CreatorStyle
import Testing
@testable import CreatorViewport

/// Filled overlay triangles (sketcher spec §8's faint green region fill): the `.region` tint, three vertices a
/// triangle in the tint's colour, and fills counting as overlay content. The GPU side is pinned by `GPUDataTests`
/// (the vertex stride) and `OffscreenRenderTests` (a fill tints the pixels it covers).
struct OverlayFillTests {
    let triangle = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0)]

    @Test func theRegionTintIsTheSketchNodesGreenFaded() {
        let theme = ColorTheme.dracula
        let colour = ViewportPalette(theme).color(.region)
        let header = theme.colors.profileHeader.rgba
        #expect(colour.x == header.x && colour.y == header.y && colour.z == header.z)
        #expect(colour.w > 0 && colour.w < 0.5, "faint: the model and the grid show through")
    }

    @Test func eachTriangleBecomesThreeVerticesInTheTintsColour() {
        let shifted = triangle.map { $0 + Vector3(20, 0, 0) }
        let fills = [OverlayFill(vertices: triangle + shifted), OverlayFill(vertices: triangle, tint: .selected)]
        let vertices = OverlayGeometry.fillVertices(fills, palette: .dracula)
        #expect(vertices.count == 9)
        #expect(vertices[0].color == ViewportPalette.dracula.sketchRegion)
        #expect(vertices[3].position == SIMD3<Float>(20, 0, 0))
        #expect(vertices[6].color == ViewportPalette.dracula.sketchSelected)
    }

    @Test func aTrailingVertexOrTwoAreIgnored() {
        let fill = OverlayFill(vertices: triangle + [Vector3(1, 1, 1), Vector3(2, 2, 2)])
        #expect(fill.triangleCount == 1)
        #expect(OverlayGeometry.fillVertices([fill], palette: .dracula).count == 3)
        #expect(OverlayGeometry.fillVertices([OverlayFill(vertices: [])], palette: .dracula).isEmpty)
    }

    @Test func fillsAreOverlayContent() {
        #expect(ViewportOverlay().isEmpty)
        #expect(!ViewportOverlay(fills: [OverlayFill(vertices: triangle)]).isEmpty)
    }
}
```

**Modify** `Tests/CreatorViewportTests/GPUDataTests.swift`:

```swift
        #expect(MemoryLayout<CubeVertex>.stride == 64)
```

with:

```swift
        #expect(MemoryLayout<FillVertex>.stride == 32)
        #expect(MemoryLayout<FillVertex>.offset(of: \FillVertex.color) == 16)
        #expect(MemoryLayout<CubeVertex>.stride == 64)
```

**Modify** `Tests/CreatorViewportTests/OffscreenRenderTests.swift`:

```swift
    @Test func aTargetOfTheWrongFormatIsLeftAlone() throws {
```

with:

```swift
    /// A fill tints the pixels it covers and leaves the rest: the same frame with and without a triangle round the view's
    /// centre. (It compares the two renders, not colours.)
    @Test func anOverlayFillTintsThePixelsItCoversAndNoOthers() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try ViewportRenderer(device: device)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 400, height: 400,
                                                                  mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        let target = try #require(device.makeTexture(descriptor: descriptor))
        let queue = try #require(device.makeCommandQueue())
        func pixels(_ overlay: ViewportOverlay) throws -> [UInt8] {
            let frame = ViewportFrame(pose: Self.front, size: Self.size, sceneBounds: nil, items: [], shading: .shadedEdges,
                                      gridSpacing: 10, handles: [], cube: ViewCubeLayout(), hoveredCubeRegion: nil,
                                      triad: TriadLayout(), overlay: overlay)
            let commandBuffer = try #require(queue.makeCommandBuffer())
            renderer.encode(frame, into: target, scale: 2, commandBuffer: commandBuffer)
            commitAndWait(commandBuffer)
            var bytes = [UInt8](repeating: 0, count: 400 * 400 * 4)
            target.getBytes(&bytes, bytesPerRow: 400 * 4, from: MTLRegionMake2D(0, 0, 400, 400), mipmapLevel: 0)
            return bytes
        }
        func channels(_ bytes: [UInt8], x: Int, y: Int) -> [Int] {
            (0..<3).map { Int(bytes[(y * 400 + x) * 4 + $0]) }
        }
        let fill = OverlayFill(vertices: [Vector3(-6, 0, 9), Vector3(6, 0, 9), Vector3(0, 0, 21)])
        let plain = try pixels(ViewportOverlay())
        let filled = try pixels(ViewportOverlay(fills: [fill]))
        let inside = zip(channels(plain, x: 200, y: 200), channels(filled, x: 200, y: 200)).map { abs($0 - $1) }
        #expect(inside.contains { $0 >= 3 }, "the view's centre is inside the triangle: \(inside)")
        #expect(channels(plain, x: 20, y: 380) == channels(filled, x: 20, y: 380), "a corner far from it is untouched")
    }

    @Test func aTargetOfTheWrongFormatIsLeftAlone() throws {
```

- [ ] **Step 2: Run the tests; they don't compile**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: errors for `OverlayFill`, `FillVertex`, `ViewportOverlay(fills:)`, `.region`.

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorViewport/Overlay/OverlayFill.swift`:

```swift
import CreatorGeometry

/// Filled triangles in world space, drawn under the overlay's lines (a sketch region's faint fill, sketcher spec §8).
/// Fills never take the pointer: they are not in the ID pass.
public struct OverlayFill: Hashable, Sendable {
    /// Three points per triangle, in either winding; a trailing one or two are ignored.
    public var vertices: [Vector3]
    public var tint: OverlayTint

    public init(vertices: [Vector3], tint: OverlayTint = .region) {
        self.vertices = vertices
        self.tint = tint
    }

    public var triangleCount: Int { vertices.count / 3 }
}
```

**Replace the whole of** `Sources/CreatorViewport/Overlay/ViewportOverlay.swift`:

```swift
import CreatorGeometry

/// Lines, points, fills and labels the host draws over the scene, on top of everything but the widgets (the sketch
/// editor's geometry, region fill and dimension values, sketcher spec §8). With a `gridPlane`, a grid on that plane
/// replaces the ground grid. The viewport never interprets it: the host builds it, the viewport draws it.
public struct ViewportOverlay: Hashable, Sendable {
    public var lines: [OverlayLine]
    public var points: [OverlayPoint]
    /// Filled triangles, drawn under the lines and points.
    public var fills: [OverlayFill]
    /// Text anchored in world space, drawn over the surface (`ViewportModel.overlayLabels()`).
    public var labels: [OverlayLabel]
    /// The plane whose grid is drawn instead of the ground grid, or `nil` for the ground grid.
    public var gridPlane: Plane?

    public init(lines: [OverlayLine] = [], points: [OverlayPoint] = [], fills: [OverlayFill] = [],
                labels: [OverlayLabel] = [], gridPlane: Plane? = nil) {
        self.lines = lines
        self.points = points
        self.fills = fills
        self.labels = labels
        self.gridPlane = gridPlane
    }

    public var isEmpty: Bool { lines.isEmpty && points.isEmpty && fills.isEmpty && labels.isEmpty && gridPlane == nil }
}
```

**Modify** `Sources/CreatorViewport/Overlay/OverlayTint.swift`:

```swift
    /// A tool's rubber band, before it's committed: the under-constrained colour, faded.
    case preview
```

with:

```swift
    /// A tool's rubber band, before it's committed: the under-constrained colour, faded.
    case preview
    /// The fill of a closed region (sketcher spec §8's "faint green fill"): the Sketch node's header colour, faint.
    case region
```

**Modify** `Sources/CreatorViewport/Render/ViewportPalette.swift`:

```swift
    var sketchPreview: SIMD4<Float>

    init(_ theme: ColorTheme) {
```

with:

```swift
    var sketchPreview: SIMD4<Float>
    /// A closed region's fill: the Sketch node's header colour at 18% opacity.
    var sketchRegion: SIMD4<Float>

    init(_ theme: ColorTheme) {
```

**Modify** `Sources/CreatorViewport/Render/ViewportPalette.swift`:

```swift
        sketchPreview = colors.sketchUnderConstrained.opacity(0.6).rgba
```

with:

```swift
        sketchPreview = colors.sketchUnderConstrained.opacity(0.6).rgba
        sketchRegion = colors.profileHeader.opacity(0.18).rgba
```

**Modify** `Sources/CreatorViewport/Render/ViewportPalette+Overlay.swift`:

```swift
        case .preview: sketchPreview
```

with:

```swift
        case .preview: sketchPreview
        case .region: sketchRegion
```

**Modify** `Sources/CreatorViewport/View/ViewportModel+TextColors.swift`:

```swift
        case .selected: colors.profileHeader.color
```

with:

```swift
        case .selected, .region: colors.profileHeader.color
```

**Create** `Sources/CreatorViewport/Render/FillVertex.swift`:

```swift
/// One corner of a filled overlay triangle (`ViewportShaders`' `FillVertex`, pinned by `GPUDataTests`).
struct FillVertex: Equatable {
    var position: SIMD3<Float>
    var color: SIMD4<Float>
}
```

**Create** `Sources/CreatorViewport/Render/FillBufferKey.swift`:

```swift
/// What the renderer's fill buffer is built from. Fills don't depend on the camera, so a pan or a zoom keeps the buffer.
struct FillBufferKey: Equatable {
    var fills: [OverlayFill]
    var palette: ViewportPalette
}
```

**Modify** `Sources/CreatorViewport/Render/OverlayGeometry.swift`:

```swift
    /// `a`–`b` cut into dashes `dash` points long
```

with:

```swift
    /// Three vertices per triangle of every fill, in the tint's colour; a fill's trailing one or two vertices are ignored.
    static func fillVertices(_ fills: [OverlayFill], palette: ViewportPalette) -> [FillVertex] {
        fills.flatMap { fill -> [FillVertex] in
            let color = palette.color(fill.tint)
            return fill.vertices.prefix(fill.triangleCount * 3).map { FillVertex(position: GPUGeometry.float3($0), color: color) }
        }
    }

    /// `a`–`b` cut into dashes `dash` points long
```

**Modify** `Sources/CreatorViewport/Render/ViewportShaders.swift`:

```swift
struct CubeVertex { float3 position; float4 color; float2 uv; float4 labelRect; };
```

with:

```swift
struct CubeVertex { float3 position; float4 color; float2 uv; float4 labelRect; };
struct FillVertex { float3 position; float4 color; };
```

**Modify** `Sources/CreatorViewport/Render/ViewportShaders.swift`:

```swift
// MARK: View cube
```

with:

```swift
// MARK: Overlay fills (a sketch region's faint colour, under the overlay's lines)

struct FillOut {
    float4 position [[position]];
    float4 color [[flat]];
};

vertex FillOut fill_vertex(uint vid [[vertex_id]],
                           device const FillVertex *vertices [[buffer(0)]],
                           constant FrameUniforms &uniforms [[buffer(1)]]) {
    FillVertex v = vertices[vid];
    FillOut out;
    out.position = uniforms.viewProjection * float4(v.position, 1.0);
    out.color = v.color;
    return out;
}

fragment float4 fill_fragment(FillOut in [[stage_in]]) {
    return float4(in.color.rgb * in.color.a, in.color.a);
}

// MARK: View cube
```

**Modify** `Sources/CreatorViewport/Render/ViewportPipelines.swift`:

```swift
    let grid: any MTLRenderPipelineState
```

with:

```swift
    let grid: any MTLRenderPipelineState
    /// The overlay's filled triangles: blended, drawn under its lines.
    let fill: any MTLRenderPipelineState
```

**Modify** `Sources/CreatorViewport/Render/ViewportPipelines.swift`:

```swift
        grid = try pipeline("grid_vertex", "grid_fragment", blended: true)
```

with:

```swift
        grid = try pipeline("grid_vertex", "grid_fragment", blended: true)
        fill = try pipeline("fill_vertex", "fill_fragment", blended: true)
```

**Modify** `Sources/CreatorViewport/Render/ViewportRenderer.swift`:

```swift
    var overlayBuffer: (key: OverlayBufferKey, buffer: any MTLBuffer, count: Int)?
```

with:

```swift
    var overlayBuffer: (key: OverlayBufferKey, buffer: any MTLBuffer, count: Int)?
    /// The overlay's fill triangles, kept until the fills or the palette change.
    var fillBuffer: (key: FillBufferKey, buffer: any MTLBuffer, count: Int)?
```

**Replace the whole of** `Sources/CreatorViewport/Render/ViewportRenderer+Overlay.swift`:

```swift
import Metal

extension ViewportRenderer {
    /// The host's overlay over the scene and the ghosts, whatever their depth (sketcher spec §8: the sketch is drawn
    /// over the dimmed model): its fills first, then its grid, lines and points on top of them.
    func drawOverlay(_ frame: ViewportFrame, _ uniforms: FrameUniforms, scale: Float, _ encoder: any MTLRenderCommandEncoder) {
        drawFills(frame, uniforms, encoder)
        guard let overlay = overlayInstances(for: frame, scale: scale) else { return }
        drawLines(overlay.buffer, count: overlay.count, uniforms, depth: pipelines.depthAlways, style: Self.plainLines, encoder)
    }

    private func drawFills(_ frame: ViewportFrame, _ uniforms: FrameUniforms, _ encoder: any MTLRenderCommandEncoder) {
        guard let fills = fillVertices(for: frame) else { return }
        var copy = uniforms
        encoder.setRenderPipelineState(pipelines.fill)
        encoder.setDepthStencilState(pipelines.depthAlways)
        encoder.setVertexBuffer(fills.buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&copy, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: fills.count)
    }

    /// The frame's fill triangles in its palette, kept until the fills or the palette change.
    func fillVertices(for frame: ViewportFrame) -> (buffer: any MTLBuffer, count: Int)? {
        guard !frame.overlay.fills.isEmpty else { return nil }
        let key = FillBufferKey(fills: frame.overlay.fills, palette: frame.palette)
        if let cached = fillBuffer, cached.key == key { return (cached.buffer, cached.count) }
        let vertices = OverlayGeometry.fillVertices(frame.overlay.fills, palette: frame.palette)
        guard let buffer = GPUBuffers.make(device, vertices) else {
            fillBuffer = nil
            return nil
        }
        fillBuffer = (key, buffer, vertices.count)
        return (buffer, vertices.count)
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

- [ ] **Step 4: Run the tests and the full-suite check**

Run: `swift test --filter OverlayFillTests`, `swift test --filter GPUDataTests`, `swift test --filter OffscreenRenderTests` — Expected: all pass (the offscreen suite needs a Metal device, as before).
Run the **full-suite check** — Expected: exit 0, `0`, `11`, total **master + 27** (1670). No new warnings; lint clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorViewport Tests/CreatorViewportTests
git commit -m "feat(viewport): filled overlay triangles under the overlay's lines"
```

### Task 6: The region fill in the sketch overlay

`SketchRegions.find` gives each closed region as an outer loop and its holes; the overlay needs triangles. A pure
`RegionTriangulator` tessellates the loops (arcs at the editor's 72 segments a turn, as the curves are drawn), bridges each
hole into the outline and ear-clips the result, so a region with holes fills exactly and an island inside a hole is its
own region (the regions already nest even-odd). A grid of aligned holes (a Pattern of rectangles) is the hard case: the
bridges run along other holes' edges and their twins are collinear, so a bridge must touch no other vertex, flat and
repeated vertices are dropped before clipping, and a region the clipper can't finish exactly gets **no** fill (never a
wrong one: the triangles' areas must add up to the polygon's). `SketchEditorModel.overlay` then carries one `OverlayFill` per region,
found again only when the sketch or its plane changes (the overlay is rebuilt on every hover).

**Files:**
- Create: `Sources/CreatorSketchEditor/RegionTriangulator.swift`, `Sources/CreatorSketchEditor/SketchRegionFills.swift`, `Tests/CreatorSketchEditorTests/RegionTriangulatorTests.swift`, `Tests/CreatorSketchEditorTests/RegionFillTests.swift`
- Replace: `Sources/CreatorSketchEditor/SketchEditorModel+Overlay.swift`
- Modify: `Sources/CreatorSketchEditor/SketchEditorModel.swift`, `Sources/CreatorSketchEditor/SketchOverlayBuilder.swift`

**Interfaces:**
- Consumes: `SketchRegions.find(in:)`, `SketchRegion.outer`/`holes` (`[Segment2D]` loops, counter-clockwise), `EditorGeometry.segmentsPerTurn`, `OverlayFill` (Task 5), `Plane.point(_:)`.
- Produces: `RegionTriangulator.triangles(of: SketchRegion) -> [Vector2]` and `triangles(outer:holes:) -> [Vector2]` (three points per triangle, counter-clockwise), `RegionTriangulator.polyline(_ loop: [Segment2D]) -> [Vector2]`; `SketchRegionFills.fills(of: Sketch, on: Plane) -> [OverlayFill]`; `SketchOverlayBuilder.overlay(…, fills: [OverlayFill] = [])`; `SketchEditorModel.regionFills`.

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorSketchEditorTests/RegionTriangulatorTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import Foundation
import Testing
@testable import CreatorSketchEditor

/// The triangulation of a region's loops (sketcher spec §8's region fill): every triangle counter-clockwise, the
/// triangles' areas adding up to the outline's less the holes', none of them inside a hole.
struct RegionTriangulatorTests {
    func square(_ x: Double, _ y: Double, _ side: Double) -> [Vector2] {
        [Vector2(x, y), Vector2(x + side, y), Vector2(x + side, y + side), Vector2(x, y + side)]
    }

    func circle(_ centre: Vector2, _ radius: Double, steps: Int = 72) -> [Vector2] {
        (0..<steps).map { step in
            let angle = 2 * Double.pi * Double(step) / Double(steps)
            return centre + Vector2(cos(angle), sin(angle)) * radius
        }
    }

    /// The polygon's area (positive for counter-clockwise).
    func area(_ loop: [Vector2]) -> Double {
        zip(loop, loop.dropFirst() + loop.prefix(1)).reduce(0) { $0 + ($1.0.x * $1.1.y - $1.1.x * $1.0.y) } / 2
    }

    func triangleAreas(_ points: [Vector2]) -> [Double] {
        stride(from: 0, to: points.count - 2, by: 3).map { area([points[$0], points[$0 + 1], points[$0 + 2]]) }
    }

    func contains(_ loop: [Vector2], _ p: Vector2) -> Bool {
        var inside = false
        for (a, b) in zip(loop, loop.dropFirst() + loop.prefix(1)) where (a.y > p.y) != (b.y > p.y) {
            if p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        }
        return inside
    }

    /// Checks what every triangulation must satisfy and returns the triangles.
    @discardableResult
    func check(outer: [Vector2], holes: [[Vector2]], sourceLocation: SourceLocation = #_sourceLocation) -> [Vector2] {
        let points = RegionTriangulator.triangles(outer: outer, holes: holes)
        #expect(points.count % 3 == 0, sourceLocation: sourceLocation)
        let areas = triangleAreas(points)
        #expect(areas.allSatisfy { $0 > 0 }, "every triangle runs counter-clockwise", sourceLocation: sourceLocation)
        let expected = abs(area(outer)) - holes.reduce(0) { $0 + abs(area($1)) }
        #expect(abs(areas.reduce(0, +) - expected) < 1e-6 * max(1, expected), "the areas add up", sourceLocation: sourceLocation)
        for (index, area) in areas.enumerated() {
            let corners = Array(points[3 * index..<3 * index + 3])
            let centroid = (corners[0] + corners[1] + corners[2]) * (1.0 / 3)
            #expect(contains(outer, centroid) && !holes.contains { contains($0, centroid) },
                    "triangle \(index) (area \(area)) lies in the region", sourceLocation: sourceLocation)
        }
        return points
    }

    @Test func aSquareIsTwoTriangles() {
        #expect(check(outer: square(0, 0, 10), holes: []).count == 6)
    }

    @Test func aConcaveOutlineFills() {
        let l = [Vector2(0, 0), Vector2(20, 0), Vector2(20, 10), Vector2(10, 10), Vector2(10, 20), Vector2(0, 20)]
        #expect(check(outer: l, holes: []).count == 12, "n − 2 triangles")
    }

    @Test func loopsInEitherWindingGiveTheSameFill() {
        let hole = square(5, 5, 5)
        let forward = check(outer: square(0, 0, 20), holes: [hole])
        let backward = check(outer: Array(square(0, 0, 20).reversed()), holes: [Array(hole.reversed())])
        #expect(triangleAreas(forward).reduce(0, +) == triangleAreas(backward).reduce(0, +))
    }

    @Test func aSquareHoleLeavesTheHoleEmpty() {
        #expect(check(outer: square(0, 0, 20), holes: [square(5, 5, 10)]).count == 24, "4 + 4 + 2 − 2 triangles")
    }

    @Test func aCircularHoleLeavesTheHoleEmpty() {
        check(outer: square(0, 0, 40), holes: [circle(Vector2(20, 20), 8)])
    }

    @Test func severalHolesAreAllCutOut() {
        check(outer: square(0, 0, 60), holes: [circle(Vector2(15, 30), 8), square(30, 10, 10), circle(Vector2(45, 40), 6, steps: 24)])
    }

    @Test func aHoleNearACornerAndOneTouchingTheOutlinesLineOfSightStillFill() {
        check(outer: square(0, 0, 20), holes: [square(1, 1, 4), square(14, 14, 4)])
        let notch = [Vector2(0, 0), Vector2(30, 0), Vector2(30, 30), Vector2(20, 30), Vector2(20, 10), Vector2(10, 10),
                     Vector2(10, 30), Vector2(0, 30),
        ]
        check(outer: notch, holes: [square(2, 2, 4), square(22, 14, 4)])
    }

    /// An n × n grid of 10 mm square holes, 10 mm apart, in a plate with a 10 mm margin.
    func gridHoles(_ count: Int) -> (outer: [Vector2], holes: [[Vector2]]) {
        let side = Double(count) * 20 + 10
        let holes = (0..<count).flatMap { column in
            (0..<count).map { row in square(10 + Double(column) * 20, 10 + Double(row) * 20, 10) }
        }
        return (square(0, 0, side), holes)
    }

    @Test(arguments: 2...5) func aGridOfAlignedSquareHolesLeavesEveryHoleEmpty(count: Int) {
        let (outer, holes) = gridHoles(count)
        let points = check(outer: outer, holes: holes)
        let side = Double(count) * 20 + 10
        #expect(abs(triangleAreas(points).reduce(0, +) - (side * side - Double(count * count) * 100)) < 1e-6)
    }

    @Test func holesSharingAnEdgeLineWithEachOtherAndTheOutlineStillFill() {
        check(outer: square(0, 0, 50), holes: [square(10, 10, 10), square(30, 10, 10), square(10, 30, 10)])
        check(outer: square(0, 0, 50), holes: [square(10, 10, 10), square(10, 30, 10), square(30, 20, 10)])
        check(outer: square(0, 0, 60), holes: [square(10, 10, 10), square(10, 30, 20), square(40, 10, 10), square(40, 30, 10)])
    }

    @Test func aHoleThatCantBeBridgedGivesNoFillRatherThanAWrongOne() {
        #expect(RegionTriangulator.triangles(outer: square(0, 0, 10), holes: [square(8, 8, 5)]).isEmpty, "a hole crossing the outline")
    }

    @Test func degenerateInputGivesNoTrianglesAndNeverHangs() {
        #expect(RegionTriangulator.triangles(outer: [], holes: []).isEmpty)
        #expect(RegionTriangulator.triangles(outer: [Vector2(0, 0), Vector2(1, 0)], holes: []).isEmpty)
        #expect(RegionTriangulator.triangles(outer: [Vector2(0, 0), Vector2(5, 0), Vector2(10, 0)], holes: []).isEmpty, "collinear")
        #expect(RegionTriangulator.triangles(outer: square(0, 0, 10), holes: [[Vector2(2, 2), Vector2(3, 3)]]).count == 6,
                "a hole of two points is no hole")
    }

    @Test func polylinesFollowLinesAndArcsAndDropRepeatedPoints() {
        let lines: [Segment2D] = [.line(Vector2(0, 0), Vector2(10, 0)), .line(Vector2(10, 0), Vector2(10, 10)),
                                  .line(Vector2(10, 10), Vector2(0, 10)), .line(Vector2(0, 10), Vector2(0, 0)),
        ]
        #expect(RegionTriangulator.polyline(lines) == square(0, 0, 10))
        let full: [Segment2D] = [.arc(center: Vector2(5, 5), radius: 3, start: Angle(radians: 0), end: Angle(radians: 2 * .pi))]
        let ring = RegionTriangulator.polyline(full)
        #expect(ring.count == EditorGeometry.segmentsPerTurn)
        #expect(ring.allSatisfy { abs((Vector2(5, 5) - $0).length - 3) < 1e-9 })
        let half: [Segment2D] = [.arc(center: .zero, radius: 10, start: Angle(radians: 0), end: Angle(radians: .pi)),
                                 .line(Vector2(-10, 0), Vector2(10, 0)),
        ]
        let d = RegionTriangulator.polyline(half)
        #expect(d.count == EditorGeometry.segmentsPerTurn / 2 + 1, "half a turn's steps, then the line's start")
        #expect(area(d) > 0 && abs(area(d) - Double.pi * 50) < 1)
    }
}
```

**Create** `Tests/CreatorSketchEditorTests/RegionFillTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// The overlay carries one fill per closed region (sketcher spec §8: "Output regions: faint green fill").
@MainActor
struct RegionFillTests {
    /// The area the fill's triangles cover (in the plane's xy).
    func area(_ fill: OverlayFill) -> Double {
        stride(from: 0, to: fill.vertices.count - 2, by: 3).reduce(0) { sum, index in
            let (a, b, c) = (fill.vertices[index], fill.vertices[index + 1], fill.vertices[index + 2])
            return sum + abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
        }
    }

    @Test func aClosedShapeIsOneRegionFill() throws {
        let model = SketchEditorModel(sketch: RectangleSketch().sketch, plane: .xy)
        let fill = try #require(model.overlay.fills.first)
        #expect(model.overlay.fills.count == 1 && fill.tint == .region)
        #expect(fill.vertices.count == 6 && abs(area(fill) - 2400) < 1e-9)
    }

    @Test func aHoleIsLeftEmptyAndAnIslandInItIsItsOwnRegion() {
        var sketch = RectangleSketch().sketch
        sketch.addCircle(center: Vector2(30, 20), radius: 12)
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        #expect(model.overlay.fills.count == 1)
        let ring = Double.pi * 144
        #expect(abs(area(model.overlay.fills[0]) - (2400 - ring)) < 0.01 * ring, "the circle's polygon, not the disc")
        sketch.addCircle(center: Vector2(30, 20), radius: 4)
        let island = SketchEditorModel(sketch: sketch, plane: .xy)
        #expect(island.overlay.fills.count == 2, "the rectangle with the big circle cut out, and the small disc")
    }

    @Test func openCurvesAndConstructionMakeNoFill() {
        var open = Sketch()
        open.addLine(Vector2(0, 0), Vector2(10, 0))
        open.addLine(Vector2(10, 0), Vector2(10, 10))
        #expect(SketchEditorModel(sketch: open, plane: .xy).overlay.fills.isEmpty)
        var construction = RectangleSketch().sketch
        for id in construction.entityIDs { construction.entities[id]?.isConstruction = true }
        #expect(SketchEditorModel(sketch: construction, plane: .xy).overlay.fills.isEmpty)
    }

    @Test func theFillLiesOnThePlane() throws {
        let model = SketchEditorModel(sketch: RectangleSketch().sketch, plane: .xz)
        let fill = try #require(model.overlay.fills.first)
        #expect(fill.vertices.allSatisfy { $0.y == 0 }, "the xz plane: y is the normal")
        #expect(fill.vertices.contains(Vector3(60, 0, 40)))
    }

    @Test func theFillFollowsEditsAndIsFoundOncePerSketch() throws {
        let model = SketchEditorModel(sketch: Sketch(), plane: .xy)
        #expect(model.overlay.fills.isEmpty)
        let host = RecordingHost(model)
        model.choose(.line)
        for corner in [Vector2(0, 0), Vector2(30, 0), Vector2(30, 20), Vector2(0, 20), Vector2(0, 0)] {
            model.click(at: corner, tolerance: 0.5, modifiers: [])
        }
        #expect(host.commits.count == 4)
        let first = model.overlay.fills
        #expect(first.count == 1 && abs(area(first[0]) - 600) < 1e-9, "the fourth line closes the rectangle")
        #expect(model.fillCache?.sketch == model.sketch, "kept for this sketch")
        model.hover(at: Vector2(50, 50), tolerance: 0.5, modifiers: [])
        #expect(model.overlay.fills == first, "a hover doesn't change it")
    }
}
```

- [ ] **Step 2: Run the tests; they don't compile**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: errors for `RegionTriangulator` and `fillCache`/`fills`.

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorSketchEditor/RegionTriangulator.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import Foundation

/// Triangles for a region's fill (sketcher spec §8): the loops as polylines (arcs at `EditorGeometry.segmentsPerTurn` a
/// turn), each hole bridged into the outline by a segment to the nearest vertex it can see (a bridge touches no other
/// vertex and runs along no edge, so a grid of aligned holes bridges cleanly), and the resulting weakly simple polygon
/// ear-clipped after its flat and repeated vertices are dropped. Pure. Every triangle is counter-clockwise. Degenerate
/// input (fewer than three points, or no area) gives none, and so does a region the clipper can't finish exactly: a
/// hole that no bridge reaches, a polygon with no ear left, or triangles whose areas don't add up to the polygon's. A
/// missing fill is the safe outcome; a fill drawn over a hole is not. The loops always end: each pass clips an ear or
/// gives up.
enum RegionTriangulator {
    /// Areas and cross products below this (mm²) count as zero.
    static let epsilon = 1e-9

    /// The region's triangles in plane coordinates, three points each.
    static func triangles(of region: SketchRegion) -> [Vector2] {
        triangles(outer: polyline(region.outer), holes: region.holes.map(polyline))
    }

    /// `outer` and `holes` in either winding.
    static func triangles(outer: [Vector2], holes: [[Vector2]]) -> [Vector2] {
        guard outer.count >= 3 else { return [] }
        var polygon = oriented(outer, counterClockwise: true)
        var pending = holes.filter { $0.count >= 3 }.map { oriented($0, counterClockwise: false) }
        pending.sort { rightmost($0).point.x > rightmost($1).point.x }
        while !pending.isEmpty {
            let hole = pending.removeFirst()
            guard let merged = bridged(polygon, hole, others: pending) else { return [] }
            polygon = merged
        }
        return earClip(polygon)
    }

    /// A loop's points in order: a line's start, an arc's start and the points along it up to (not including) its end,
    /// so the next segment's start is the previous one's end. Consecutive repeats are dropped.
    static func polyline(_ loop: [Segment2D]) -> [Vector2] {
        var points: [Vector2] = []
        for segment in loop {
            switch segment {
            case .line(let start, _):
                points.append(start)
            case .arc(let center, let radius, let start, let end):
                let sweep = end.radians - start.radians
                let steps = max(2, Int((abs(sweep) / (2 * .pi) * Double(EditorGeometry.segmentsPerTurn)).rounded(.up)))
                for step in 0..<steps {
                    let angle = start.radians + sweep * Double(step) / Double(steps)
                    points.append(center + Vector2(cos(angle), sin(angle)) * radius)
                }
            }
        }
        var distinct: [Vector2] = []
        for point in points where distinct.last.map({ ($0 - point).length > epsilon }) ?? true { distinct.append(point) }
        if distinct.count > 1, let first = distinct.first, let last = distinct.last, (first - last).length <= epsilon {
            distinct.removeLast()
        }
        return distinct
    }

    // MARK: - Geometry

    static func cross(_ a: Vector2, _ b: Vector2) -> Double { a.x * b.y - a.y * b.x }

    /// Twice the polygon's signed area: positive for counter-clockwise.
    static func doubleArea(_ loop: [Vector2]) -> Double {
        zip(loop, loop.dropFirst() + loop.prefix(1)).reduce(0) { $0 + cross($1.0, $1.1) }
    }

    static func oriented(_ loop: [Vector2], counterClockwise: Bool) -> [Vector2] {
        (doubleArea(loop) > 0) == counterClockwise ? loop : Array(loop.reversed())
    }

    static func rightmost(_ loop: [Vector2]) -> (index: Int, point: Vector2) {
        var best = 0
        for index in loop.indices where loop[index].x > loop[best].x { best = index }
        return (best, loop[best])
    }

    /// Whether `p` is inside the polygon (even-odd).
    static func contains(_ loop: [Vector2], _ p: Vector2) -> Bool {
        var inside = false
        for (a, b) in zip(loop, loop.dropFirst() + loop.prefix(1)) where (a.y > p.y) != (b.y > p.y) {
            if p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        }
        return inside
    }

    /// Whether the segments `a`–`b` and `c`–`d` cross at a point inside both (touching at an end doesn't count).
    static func cross(_ a: Vector2, _ b: Vector2, _ c: Vector2, _ d: Vector2) -> Bool {
        let d1 = cross(b - a, c - a)
        let d2 = cross(b - a, d - a)
        let d3 = cross(d - c, a - c)
        let d4 = cross(d - c, b - c)
        return ((d1 > epsilon && d2 < -epsilon) || (d1 < -epsilon && d2 > epsilon))
            && ((d3 > epsilon && d4 < -epsilon) || (d3 < -epsilon && d4 > epsilon))
    }

    // MARK: - Bridging

    /// Whether `p` lies in the open wedge at `polygon[index]` that is the polygon's inside (counter-clockwise polygon).
    static func inCone(_ polygon: [Vector2], at index: Int, towards p: Vector2) -> Bool {
        let count = polygon.count
        let (before, v, after) = (polygon[(index + count - 1) % count], polygon[index], polygon[(index + 1) % count])
        if cross(v - before, after - v) >= 0 {
            return cross(after - v, p - v) > epsilon && cross(p - v, before - v) > epsilon
        }
        return !(cross(before - v, p - v) >= -epsilon && cross(p - v, after - v) >= -epsilon)
    }

    /// Whether the segment `from`–`to` touches no loop except at its ends: it crosses no edge, passes through no vertex
    /// and so runs along no edge.
    static func isClear(_ from: Vector2, _ to: Vector2, loops: [[Vector2]]) -> Bool {
        let direction = to - from
        let length = direction.length
        for loop in loops {
            for (c, d) in zip(loop, loop.dropFirst() + loop.prefix(1)) where cross(from, to, c, d) { return false }
            for v in loop where (v - from).length > epsilon && (v - to).length > epsilon {
                let offset = v - from
                let along = (offset.x * direction.x + offset.y * direction.y) / (length * length)
                if abs(cross(direction, offset)) <= epsilon * max(1, length), along > 0, along < 1 { return false }
            }
        }
        return true
    }

    /// `polygon` with `hole` joined in by a bridge: from the hole's rightmost vertex (then its others, if none works) to
    /// the nearest polygon vertex it sees (the segment is clear, leaves that vertex into the polygon's inside and runs
    /// outside the holes), or `nil` when no vertex of the hole sees one. The bridge appears twice in the result.
    static func bridged(_ polygon: [Vector2], _ hole: [Vector2], others: [[Vector2]]) -> [Vector2]? {
        let loops = [polygon, hole] + others
        for start in hole.indices.sorted(by: { hole[$0].x > hole[$1].x }) {
            let from = hole[start]
            let nearest = polygon.indices.sorted { (polygon[$0] - from).length < (polygon[$1] - from).length }
            for index in nearest {
                let to = polygon[index]
                let middle = (from + to) * 0.5
                guard (to - from).length > epsilon, inCone(polygon, at: index, towards: from), isClear(from, to, loops: loops),
                      contains(polygon, middle), !contains(hole, middle), !others.contains(where: { contains($0, middle) })
                else { continue }
                let turned = Array(hole[start...] + hole[..<start])
                return Array(polygon[...index]) + turned + [from, to] + Array(polygon[(index + 1)...])
            }
        }
        return nil
    }

    // MARK: - Ear clipping

    /// `points` without a vertex that repeats the next one or lies on the line through its neighbours, until none is left
    /// (fewer than three left: none).
    static func withoutFlatVertices(_ points: [Vector2]) -> [Vector2] {
        var ring = points
        var changed = true
        while changed, ring.count >= 3 {
            changed = false
            var index = 0
            while index < ring.count, ring.count >= 3 {
                let count = ring.count
                let (a, b, c) = (ring[(index + count - 1) % count], ring[index], ring[(index + 1) % count])
                if (b - c).length <= epsilon || abs(cross(b - a, c - b)) <= epsilon {
                    ring.remove(at: index)
                    changed = true
                } else {
                    index += 1
                }
            }
        }
        return ring.count >= 3 ? ring : []
    }

    /// The polygon's triangles, counter-clockwise, or none when they don't cover exactly its area. A vertex coinciding
    /// with a corner of the ear is a bridge's twin and doesn't block it; so doesn't a convex one touching the ear's edge
    /// (where the two sides of a bridge lie along each other); a reflex or flat one in or on the ear does.
    static func earClip(_ polygon: [Vector2]) -> [Vector2] {
        var ring = withoutFlatVertices(polygon)
        var triangles: [Vector2] = []
        while ring.count > 3 {
            guard let position = ring.indices.first(where: { isEar(ring, at: $0) }) else { return [] }
            let count = ring.count
            triangles += [ring[(position + count - 1) % count], ring[position], ring[(position + 1) % count]]
            ring.remove(at: position)
        }
        if ring.count == 3, cross(ring[1] - ring[0], ring[2] - ring[1]) > epsilon { triangles += ring }
        let covered = stride(from: 0, to: triangles.count, by: 3).reduce(0.0) {
            $0 + cross(triangles[$1 + 1] - triangles[$1], triangles[$1 + 2] - triangles[$1 + 1])
        }
        let whole = doubleArea(polygon)
        return abs(covered - whole) <= 1e-6 * max(1, abs(whole)) ? triangles : []
    }

    private static func isEar(_ ring: [Vector2], at position: Int) -> Bool {
        let count = ring.count
        let corners = [(position + count - 1) % count, position, (position + 1) % count]
        let (a, b, c) = (ring[corners[0]], ring[corners[1]], ring[corners[2]])
        guard cross(b - a, c - b) > epsilon else { return false }
        for other in ring.indices where !corners.contains(other) {
            let p = ring[other]
            if p == a || p == b || p == c { continue }
            let inside = cross(b - a, p - a) >= -epsilon && cross(c - b, p - b) >= -epsilon && cross(a - c, p - c) >= -epsilon
            if inside, cross(p - ring[(other + count - 1) % count], ring[(other + 1) % count] - p) <= epsilon { return false }
        }
        return true
    }
}
```

**Create** `Sources/CreatorSketchEditor/SketchRegionFills.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import CreatorViewport

/// The overlay's region fills: one `OverlayFill` per closed region of the sketch (`SketchRegions.find`, so construction
/// geometry and suspended projections are left out and holes stay empty), in the plane's world space.
enum SketchRegionFills {
    static func fills(of sketch: Sketch, on plane: Plane) -> [OverlayFill] {
        SketchRegions.find(in: sketch).regions.compactMap { region in
            let triangles = RegionTriangulator.triangles(of: region)
            return triangles.isEmpty ? nil : OverlayFill(vertices: triangles.map(plane.point), tint: .region)
        }
    }
}
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel.swift`:

```swift
    @ObservationIgnored var stored: Sketch
```

with:

```swift
    @ObservationIgnored var stored: Sketch
    /// The region fills of `sketch` on `plane`, kept until either changes: the overlay is rebuilt on every hover, and
    /// finding regions is more work than a hover (`regionFills`).
    @ObservationIgnored var fillCache: (sketch: Sketch, plane: Plane, fills: [OverlayFill])?
```

**Modify** `Sources/CreatorSketchEditor/SketchOverlayBuilder.swift`:

```swift
    static func overlay(sketch: Sketch, solution: SketchSolution, plane: Plane, selection: Set<SketchEntityID>,
                        hovered: SketchEntityID?, preview: SketchPreview) -> ViewportOverlay {
```

with:

```swift
    static func overlay(sketch: Sketch, solution: SketchSolution, plane: Plane, selection: Set<SketchEntityID>,
                        hovered: SketchEntityID?, preview: SketchPreview, fills: [OverlayFill] = []) -> ViewportOverlay {
```

**Modify** `Sources/CreatorSketchEditor/SketchOverlayBuilder.swift`:

```swift
        return ViewportOverlay(lines: lines, points: points, gridPlane: plane)
```

with:

```swift
        return ViewportOverlay(lines: lines, points: points, fills: fills, gridPlane: plane)
```

**Replace the whole of** `Sources/CreatorSketchEditor/SketchEditorModel+Overlay.swift`:

```swift
import CreatorViewport

extension SketchEditorModel {
    /// What the viewport draws while this sketch is edited (`ViewportModel.showOverlay(_:)`): the curves, the region fills
    /// under them and the rubber band. The Dimension tool's first pick is drawn selected.
    public var overlay: ViewportOverlay {
        let picked = dimensionPick.map { selection.union([$0]) } ?? selection
        return SketchOverlayBuilder.overlay(sketch: sketch, solution: solution, plane: plane, selection: picked, hovered: hovered,
                                            preview: preview, fills: regionFills)
    }

    /// One fill per closed region of the sketch as it is now (spec §8), found again only when the sketch or its plane
    /// changed (a drag changes it every step; a hover never does).
    var regionFills: [OverlayFill] {
        if let cache = fillCache, cache.sketch == sketch, cache.plane == plane { return cache.fills }
        let fills = SketchRegionFills.fills(of: sketch, on: plane)
        fillCache = (sketch, plane, fills)
        return fills
    }
}
```

- [ ] **Step 4: Run the tests and the full-suite check**

Run: `swift test --filter RegionTriangulatorTests` and `swift test --filter RegionFillTests` — Expected: all pass.
Run the **full-suite check** — Expected: exit 0, `0`, `11`, total **master + 44** (1687). No new warnings; lint clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorSketchEditor Tests/CreatorSketchEditorTests
git commit -m "feat(sketch): the region fill, triangulated from SketchRegions"
```

### Task 7: Dimension labels in the sketch overlay

Each dimension gets a label in the view (sketcher spec §8; the inspector keeps the editable name and value). The label
sits at the dimension's natural place (a line's middle, an arc's middle, a circle's upper right, two points' midpoint, the
corner between two lines) and stands off it along the normal, so the box clears the geometry. It reads the value
("60 mm", "45°"); an exposed dimension reads "width = 60 mm" (its name is its socket); a reference dimension reads its
measurement in brackets, in the construction colour; a dimension in a conflict is red. It is read-only: editing is the
inspector's. **Gap S5-c** (Task 4): these are element-tree labels.

**Files:**
- Create: `Sources/CreatorSketchEditor/SketchDimensionLabels.swift`, `Tests/CreatorSketchEditorTests/DimensionLabelTests.swift`
- Replace: `Sources/CreatorSketchEditor/SketchEditorModel+Overlay.swift`
- Modify: `Sources/CreatorSketchEditor/SketchOverlayBuilder.swift`, `Sources/CreatorSketchEditor/SketchEditorModel+Dimensions.swift`

**Interfaces:**
- Consumes: `OverlayLabel` (Task 4), `DimensionText.format(_:kind:)`, `SketchSolution.measurements`/`radii`, `SketchOverlayBuilder.position(_:_:_:)`, `EditorGeometry.sweep(center:start:end:)`, `SketchEditorModel.regionFills` (Task 6).
- Produces: `SketchDimensionLabels.labels(sketch:solution:plane:conflicting:) -> [OverlayLabel]`; `SketchOverlayBuilder.overlay(…, labels: [OverlayLabel] = [])`; `SketchEditorModel.dimensionLabels`; `SketchEditorModel.conflictRefs` (was private).

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorSketchEditorTests/DimensionLabelTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// The dimensions' labels in the view (sketcher spec §8): where each kind sits, what it reads, and its colour.
@MainActor
struct DimensionLabelTests {
    func labels(_ sketch: Sketch, plane: Plane = .xy) -> [OverlayLabel] {
        SketchEditorModel(sketch: sketch, plane: plane).overlay.labels
    }

    func near(_ a: Vector3?, _ b: Vector3) -> Bool {
        guard let a else { return false }
        return (a - b).length < 1e-9
    }

    @Test func aLengthSitsOnTheLinesMiddleAndStandsOffItsNormal() throws {
        let found = labels(RectangleSketch().sketch)
        try #require(found.count == 2)
        #expect(found.map(\.text) == ["60 mm", "40 mm"])
        #expect(near(found[0].position, Vector3(30, 0, 0)) && found[0].nudge == Vector3(0, 1, 0), "above")
        #expect(near(found[1].position, Vector3(60, 20, 0)) && found[1].nudge == Vector3(1, 0, 0), "right of the right edge")
        #expect(found.allSatisfy { $0.tint == .fullyConstrained })
    }

    @Test func aRadiusSitsOnTheArcsMiddleAndADiameterOnTheCirclesUpperRight() throws {
        var sketch = Sketch()
        let centre = sketch.addPoint(.zero)
        let arc = sketch.addArc(center: centre, start: sketch.addPoint(Vector2(10, 0)), end: sketch.addPoint(Vector2(0, 10)))
        sketch.addDimension(.radius(arc), value: 10)
        let circle = sketch.addCircle(center: Vector2(30, 5), radius: 3)
        sketch.addDimension(.diameter(circle), value: 6)
        let found = labels(sketch)
        try #require(found.count == 2)
        let root = 0.5.squareRoot()
        #expect(found.map(\.text) == ["10 mm", "6 mm"])
        #expect(near(found[0].position, Vector3(10 * root, 10 * root, 0)) && near(found[0].nudge, Vector3(root, root, 0)))
        #expect(near(found[1].position, Vector3(30 + 3 * root, 5 + 3 * root, 0)) && near(found[1].nudge, Vector3(root, root, 0)))
    }

    @Test func aDistanceSitsBetweenItsPointsOrBetweenAPointAndItsFootOnALine() throws {
        var sketch = Sketch()
        let a = sketch.addPoint(.zero)
        let b = sketch.addPoint(Vector2(30, 40))
        sketch.addDimension(.distance(a, b), value: 50)
        let p = sketch.addPoint(Vector2(105, 10))
        let line = sketch.addLine(Vector2(100, 0), Vector2(110, 0))
        sketch.addDimension(.distance(p, line), value: 10)
        let found = labels(sketch)
        try #require(found.count == 2)
        #expect(found.map(\.text) == ["50 mm", "10 mm"])
        #expect(near(found[0].position, Vector3(15, 20, 0)) && near(found[0].nudge, Vector3(-0.8, 0.6, 0)))
        #expect(near(found[1].position, Vector3(105, 5, 0)), "halfway from the point to its foot on the line")
    }

    @Test func anAngleSitsAtTheCornerAndStandsOffAlongTheBisector() {
        var sketch = Sketch()
        let corner = sketch.addPoint(.zero)
        let along = sketch.addLine(from: corner, to: sketch.addPoint(Vector2(10, 0)))
        let up = sketch.addLine(from: corner, to: sketch.addPoint(Vector2(0, 10)))
        sketch.addDimension(.angle(along, up), value: 90)
        let root = 0.5.squareRoot()
        let found = labels(sketch)
        #expect(found.map(\.text) == ["90°"])
        #expect(near(found.first?.position, .zero) && near(found.first?.nudge, Vector3(root, root, 0)))
    }

    @Test func aLabelLiesOnThePlane() {
        let found = labels(RectangleSketch().sketch, plane: .xz)
        #expect(found.allSatisfy { $0.position.y == 0 && $0.nudge?.y == 0 }, "xz: y is the normal")
        #expect(near(found.first?.position, Vector3(30, 0, 0)) && found.first?.nudge == Vector3(0, 0, 1))
    }

    @Test func anExposedDimensionReadsItsNameAndAReferenceItsMeasurementInBrackets() throws {
        var sketch = RectangleSketch().sketch
        let width = try #require(sketch.dimensionIDs.first)
        sketch.renameDimension(width, to: "width")
        sketch.dimensions[width]?.isExposed = true
        let height = try #require(sketch.dimensionIDs.last)
        sketch.dimensions[height]?.isDriving = false
        sketch.dimensions[height]?.value = 1
        let found = labels(sketch)
        #expect(found.map(\.text) == ["width = 60 mm", "(40 mm)"], "the reference reads what it measures, not its stored 1")
        #expect(found.map(\.tint) == [.fullyConstrained, .construction])
    }

    @Test func aDimensionInAConflictIsRed() {
        let rectangle = RectangleSketch()
        var sketch = rectangle.sketch
        sketch.addDimension(.length(rectangle.lines[0]), value: 50)
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        guard case .overConstrained = model.solution.status else {
            Issue.record("a 60 and a 50 length on one line must conflict: \(model.solution.status)")
            return
        }
        #expect(model.overlay.labels.contains { $0.tint == .conflicting })
        #expect(model.overlay.labels.count == 3)
    }

    @Test func aDimensionWhoseGeometryIsGoneHasNoLabel() {
        var sketch = RectangleSketch().sketch
        sketch.dimensions[sketch.dimensionIDs[0]]?.kind = .length(SketchEntityID(999))
        #expect(labels(sketch).map(\.text) == ["40 mm"])
    }

    @Test func theDimensionToolAddsALabel() {
        let model = SketchEditorModel(sketch: RectangleSketch(dimensioned: false).sketch, plane: .xy)
        #expect(model.overlay.labels.isEmpty)
        model.choose(.dimension)
        model.click(at: Vector2(30, 0.2), tolerance: 1, modifiers: [])
        model.click(at: Vector2(30, 80), tolerance: 1, modifiers: [])
        #expect(model.overlay.labels.map(\.text) == ["60 mm"])
    }
}
```

- [ ] **Step 2: Run the tests; they fail**

Run: `swift test --filter DimensionLabelTests`
Expected: it builds (Task 4 gave the overlay its `labels`), and all nine tests record issues: the editor's overlay has no labels yet.

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorSketchEditor/SketchDimensionLabels.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Foundation

/// The labels the overlay shows for a sketch's dimensions (sketcher spec §8): where each kind sits, what it reads and the
/// role it is coloured in. Pure. The viewport projects the anchors with the camera and stands each label off its anchor
/// along `nudge`, so the editor needs no camera.
enum SketchDimensionLabels {
    /// A dimensioned entity's shape at its solved position.
    enum Shape {
        case point(Vector2)
        case line(Vector2, Vector2)
        case circle(center: Vector2, radius: Double)
        /// `middle` is the polar angle halfway along the arc.
        case arc(center: Vector2, radius: Double, middle: Double)
    }

    static func labels(sketch: Sketch, solution: SketchSolution, plane: Plane, conflicting: Set<DimensionID>) -> [OverlayLabel] {
        sketch.dimensionIDs.compactMap { id in
            guard let dimension = sketch.dimensions[id],
                  let place = placement(of: dimension.kind, sketch: sketch, solution: solution) else { return nil }
            let value = dimension.isDriving ? dimension.value : solution.measurements[id] ?? dimension.value
            let text = DimensionText.format(value, kind: dimension.kind)
            let reads = dimension.isDriving ? (dimension.isExposed ? "\(dimension.name) = \(text)" : text) : "(\(text))"
            let tint: OverlayTint = conflicting.contains(id) ? .conflicting : dimension.isDriving ? .fullyConstrained : .construction
            let away = place.away
            return OverlayLabel(reads, at: plane.point(place.anchor), tint: tint,
                                nudge: plane.xAxis * away.x + plane.yAxis * away.y)
        }
    }

    /// Where a dimension's label is anchored and which way (a unit vector in the plane) it stands off; `nil` when its
    /// geometry is gone or doesn't fit its kind.
    static func placement(of kind: DimensionKind, sketch: Sketch, solution: SketchSolution) -> (anchor: Vector2, away: Vector2)? {
        let shape = { (id: SketchEntityID) in self.shape(of: id, sketch: sketch, solution: solution) }
        switch kind {
        case .length(let id):
            guard case .line(let a, let b)? = shape(id) else { return nil }
            return ((a + b) * 0.5, normal(of: b - a) ?? up)
        case .radius(let id), .diameter(let id):
            return circlePlacement(shape(id))
        case .distance(let first, let second):
            return distancePlacement(shape(first), shape(second))
        case .angle(let first, let second):
            return anglePlacement(shape(first), shape(second))
        }
    }

    static let up = Vector2(0, 1)

    /// A radius or diameter: on the arc's middle, or a circle's upper right, standing off outwards.
    static func circlePlacement(_ shape: Shape?) -> (anchor: Vector2, away: Vector2)? {
        switch shape {
        case .arc(let center, let radius, let middle)?: onCircle(center, radius, middle)
        case .circle(let center, let radius)?: onCircle(center, radius, .pi / 4)
        default: nil
        }
    }

    /// Between two points, or between a point and its foot on a line.
    static func distancePlacement(_ first: Shape?, _ second: Shape?) -> (anchor: Vector2, away: Vector2)? {
        switch (first, second) {
        case (.point(let a)?, .point(let b)?):
            return ((a + b) * 0.5, normal(of: b - a) ?? up)
        case (.point(let p)?, .line(let a, let b)?), (.line(let a, let b)?, .point(let p)?):
            let foot = EditorGeometry.nearest(to: p, onLine: a, b)
            return ((p + foot) * 0.5, normal(of: foot - p) ?? up)
        default:
            return nil
        }
    }

    /// At the corner where the lines meet, standing off along the bisector of the two lines' middles.
    static func anglePlacement(_ first: Shape?, _ second: Shape?) -> (anchor: Vector2, away: Vector2)? {
        guard case .line(let a, let b)? = first, case .line(let c, let d)? = second else { return nil }
        let corner = intersection(a, b, c, d) ?? ((a + b + c + d) * 0.25)
        let away = unit(unit((a + b) * 0.5 - corner) + unit((c + d) * 0.5 - corner))
        return (corner, away == .zero ? up : away)
    }

    static func shape(of id: SketchEntityID, sketch: Sketch, solution: SketchSolution) -> Shape? {
        let at = { (point: SketchEntityID) in SketchOverlayBuilder.position(point, sketch, solution) }
        switch sketch.entities[id]?.kind {
        case .point?:
            return at(id).map(Shape.point)
        case .line(let start, let end)?:
            guard let a = at(start), let b = at(end) else { return nil }
            return .line(a, b)
        case .circle(let center, _)?:
            guard let c = at(center), let radius = solution.radii[id] ?? sketch.radius(of: id) else { return nil }
            return .circle(center: c, radius: radius)
        case .arc(let center, let start, let end)?:
            guard let c = at(center), let s = at(start), let e = at(end) else { return nil }
            let first = EditorGeometry.angle(s - c)
            return .arc(center: c, radius: (s - c).length, middle: first + EditorGeometry.sweep(center: c, start: s, end: e) / 2)
        case .projected(let source)?:
            return source.isSuspended ? nil : shape(of: source.curve)
        case nil:
            return nil
        }
    }

    static func shape(of curve: ProjectedCurve) -> Shape {
        switch curve {
        case .line(let a, let b): .line(a, b)
        case .circle(let center, let radius): .circle(center: center, radius: radius)
        case .arc(let center, let radius, let start, let end):
            .arc(center: center, radius: radius, middle: (start.radians + end.radians) / 2)
        }
    }

    static func onCircle(_ center: Vector2, _ radius: Double, _ angle: Double) -> (anchor: Vector2, away: Vector2) {
        let direction = Vector2(cos(angle), sin(angle))
        return (center + direction * radius, direction)
    }

    /// `v` turned a quarter, as a unit vector pointing up (or, for a horizontal `v`, right); `nil` for no length.
    static func normal(of v: Vector2) -> Vector2? {
        let length = v.length
        guard length > 1e-9 else { return nil }
        let left = Vector2(-v.y / length, v.x / length)
        let flip = left.y < -1e-9 || (abs(left.y) <= 1e-9 && left.x < 0)
        return flip ? left * -1 : left
    }

    static func unit(_ v: Vector2) -> Vector2 {
        let length = v.length
        return length > 1e-9 ? v * (1 / length) : .zero
    }

    /// Where the infinite lines `a`–`b` and `c`–`d` meet; `nil` when they are parallel.
    static func intersection(_ a: Vector2, _ b: Vector2, _ c: Vector2, _ d: Vector2) -> Vector2? {
        let (r, s) = (b - a, d - c)
        let denominator = r.x * s.y - r.y * s.x
        guard abs(denominator) > 1e-9 else { return nil }
        let t = ((c.x - a.x) * s.y - (c.y - a.y) * s.x) / denominator
        return a + r * t
    }
}
```

**Modify** `Sources/CreatorSketchEditor/EditorGeometry.swift`:

```swift
    /// The point of the circle around `center` nearest `p` (its rightmost point when `p` is the centre).
```

with:

```swift
    /// The point of the infinite line through `a` and `b` nearest `p` (`a` when they coincide).
    static func nearest(to p: Vector2, onLine a: Vector2, _ b: Vector2) -> Vector2 {
        let d = b - a
        let squared = d.x * d.x + d.y * d.y
        guard squared > 0 else { return a }
        return a + d * (((p.x - a.x) * d.x + (p.y - a.y) * d.y) / squared)
    }

    /// The point of the circle around `center` nearest `p` (its rightmost point when `p` is the centre).
```

**Modify** `Sources/CreatorSketchEditor/SketchOverlayBuilder.swift`:

```swift
                        hovered: SketchEntityID?, preview: SketchPreview, fills: [OverlayFill] = []) -> ViewportOverlay {
```

with:

```swift
                        hovered: SketchEntityID?, preview: SketchPreview, fills: [OverlayFill] = [],
                        labels: [OverlayLabel] = []) -> ViewportOverlay {
```

**Modify** `Sources/CreatorSketchEditor/SketchOverlayBuilder.swift`:

```swift
        return ViewportOverlay(lines: lines, points: points, fills: fills, gridPlane: plane)
```

with:

```swift
        return ViewportOverlay(lines: lines, points: points, fills: fills, labels: labels, gridPlane: plane)
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Dimensions.swift`:

```swift
    private var conflictRefs: Set<SketchConstraintRef> {
```

with:

```swift
    var conflictRefs: Set<SketchConstraintRef> {
```

**Replace the whole of** `Sources/CreatorSketchEditor/SketchEditorModel+Overlay.swift`:

```swift
import CreatorSketch
import CreatorViewport

extension SketchEditorModel {
    /// What the viewport draws while this sketch is edited (`ViewportModel.showOverlay(_:)`): the curves, the region fills
    /// under them, the rubber band and the dimensions' labels. The Dimension tool's first pick is drawn selected.
    public var overlay: ViewportOverlay {
        let picked = dimensionPick.map { selection.union([$0]) } ?? selection
        return SketchOverlayBuilder.overlay(sketch: sketch, solution: solution, plane: plane, selection: picked, hovered: hovered,
                                            preview: preview, fills: regionFills, labels: dimensionLabels)
    }

    /// One fill per closed region of the sketch as it is now (spec §8), found again only when the sketch or its plane
    /// changed (a drag changes it every step; a hover never does).
    var regionFills: [OverlayFill] {
        if let cache = fillCache, cache.sketch == sketch, cache.plane == plane { return cache.fills }
        let fills = SketchRegionFills.fills(of: sketch, on: plane)
        fillCache = (sketch, plane, fills)
        return fills
    }

    /// A label for each dimension whose geometry is there (`SketchDimensionLabels`); a dimension in a conflict is red.
    var dimensionLabels: [OverlayLabel] {
        let conflicting = Set(conflictRefs.compactMap { ref -> DimensionID? in
            if case .dimension(let id) = ref { id } else { nil }
        })
        return SketchDimensionLabels.labels(sketch: sketch, solution: solution, plane: plane, conflicting: conflicting)
    }
}
```

- [ ] **Step 4: Run the tests and the full-suite check**

Run: `swift test --filter DimensionLabelTests` — Expected: all pass.
Run the **full-suite check** — Expected: exit 0, `0`, `11`, total **master + 53** (1696). No new warnings; lint clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorSketchEditor Tests/CreatorSketchEditorTests
git commit -m "feat(sketch): dimension labels in the view"
```

### Task 8: The Project tool in the editor (CreatorKernel joins)

Sketcher spec §8: "Model edges for Project use M4's ID-buffer picking", key P. Project is a sketch-mode **tool** that
declines the plane click (`clicked(at:…)` returns false) and takes the viewport's pick in `clickedModel` (Task 2), so
nothing turns the camera and no menu opens. The editor stays graph-free: it asks its host to resolve the pick
(`SketchEditorEvents.projection`: the picked edge, or every edge of a picked face, as a projected curve plus the
`EdgePick` the Sketch node stores) and adds one fixed `.projected` entity per edge with a fresh `reference`; the
commit carries a `ProjectionWrite` per entity so the host stores each pick and wires the solid (Task 9). `CreatorSketchEditor`
now depends on `CreatorKernel` (sketcher spec §2), for `EdgePick`.

**Files:**
- Create: `Sources/CreatorSketchEditor/ProjectionCandidate.swift`, `ProjectionResolution.swift`, `ProjectionWrite.swift`, `SketchEditorModel+Project.swift`, `Tests/CreatorSketchEditorTests/ProjectToolTests.swift`
- Modify: `Package.swift` (the `CreatorSketchEditor` target and its test target gain `CreatorKernel`), `Sources/CreatorSketchEditor/SketchTool.swift`, `SketchCommit.swift`, `SketchEditorEvents.swift`, `SketchEditorModel.swift`, `SketchEditorModel+Commands.swift`, `SketchEditorModel+Drawing.swift`, `SketchEditorModel+ViewportTool.swift`, `SketchOverlayBuilder.swift`, `Views/SketchToolButton.swift`
- Modify (tests): `Tests/CreatorSketchEditorTests/ToolOptionsViewTests.swift`, `Tests/CreatorSketchEditorTests/SnapAndTangentCoverageTests.swift` (Task 1's)

**Interfaces:**
- Consumes: `ViewportTool.clickedModel` (Task 2), `PickTarget`, `ProjectionSource(reference:curve:isSuspended:)`, `EdgePick`.
- Produces: `SketchTool.project` (title "Project", key P, after `.pattern`); `ProjectionCandidate(curve: ProjectedCurve, pick: EdgePick, solid: Int)`; `ProjectionResolution(candidates: [ProjectionCandidate], skipped: [String])`; `ProjectionWrite(reference: String, pick: EdgePick, solid: Int)`; `SketchCommit.projections: [ProjectionWrite]` (default empty); `SketchEditorEvents.projection: @MainActor (PickTarget, Plane) -> ProjectionResolution`; `SketchEditorModel.project(_ target: PickTarget?)`.

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorSketchEditorTests/ProjectToolTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// The Project tool (sketcher spec §8): a click on the model's edge or face becomes fixed projected curves in the sketch,
/// each with a fresh reference, handed to the host with the picks to store. One undo step.
@MainActor
struct ProjectToolTests {
    let pick = EdgePick(key: EdgeKey([], []), matchCount: 1)
    let projector = ViewportProjector(pose: CameraPose(target: .zero, distance: 100, pitch: .pi / 2, projection: .orthographic),
                                      size: ViewportSize(width: 400, height: 300))

    func candidate(_ x: Double, solid: Int = 0) -> ProjectionCandidate {
        ProjectionCandidate(curve: .line(Vector2(x, 0), Vector2(x + 30, 0)), pick: pick, solid: solid)
    }

    func makeModel(_ sketch: Sketch = Sketch(), answering candidates: [ProjectionCandidate] = [],
                   skipped: [String] = []) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xz)
        model.choose(.project)
        model.events.projection = { _, _ in ProjectionResolution(candidates: candidates, skipped: skipped) }
        return (model, RecordingHost(model))
    }

    func projected(_ sketch: Sketch) -> [ProjectionSource] {
        sketch.entityIDs.compactMap { id in
            if case .projected(let source)? = sketch.entities[id]?.kind { source } else { nil }
        }
    }

    @Test func projectDeclinesThePlaneClickAndTakesTheModelsPick() {
        let (model, _) = makeModel(answering: [candidate(0)])
        #expect(!model.clicked(at: ScreenPoint(200, 150), modifiers: [], projector: projector), "so the viewport picks the model")
        #expect(model.clickedModel(.edge(solid: 0, EdgeID(1)), at: ScreenPoint(200, 150), modifiers: [], projector: projector))
        model.choose(.line)
        #expect(model.clicked(at: ScreenPoint(200, 150), modifiers: [], projector: projector))
        #expect(!model.clickedModel(.edge(solid: 0, EdgeID(1)), at: ScreenPoint(200, 150), modifiers: [], projector: projector),
                "any other tool leaves the pick to the host")
    }

    @Test func aPickedEdgeIsAFixedProjectedEntityCommittedWithItsPick() throws {
        var asked: [(PickTarget, Plane)] = []
        let (model, host) = makeModel(answering: [candidate(5, solid: 2)])
        model.events.projection = { target, plane in
            asked.append((target, plane))
            return ProjectionResolution(candidates: [self.candidate(5, solid: 2)], skipped: [])
        }
        model.project(.edge(solid: 2, EdgeID(7)))
        #expect(asked.count == 1 && asked[0].0 == .edge(solid: 2, EdgeID(7)) && asked[0].1 == .xz, "the host gets the pick and the plane")
        #expect(host.commits.map(\.description) == ["Project"])
        let commit = try #require(host.commits.first)
        #expect(commit.projections == [ProjectionWrite(reference: "edge1", pick: pick, solid: 2)])
        #expect(projected(model.sketch) == [ProjectionSource(reference: "edge1", curve: .line(Vector2(5, 0), Vector2(35, 0)))])
        #expect(model.sketch.constraintIDs.isEmpty && model.solution.status.isUsable)
    }

    @Test func aFacePicksOneProjectionPerEdgeAndLaterOnesTakeTheNextReferences() {
        let (model, host) = makeModel(answering: [candidate(0), candidate(100), candidate(200)])
        model.project(.face(solid: 0, FaceID(1)))
        #expect(projected(model.sketch).map(\.reference) == ["edge1", "edge2", "edge3"])
        #expect(host.commits.count == 1, "one undo step for the face")
        model.events.projection = { _, _ in ProjectionResolution(candidates: [self.candidate(300)], skipped: []) }
        model.project(.edge(solid: 0, EdgeID(2)))
        #expect(projected(model.sketch).map(\.reference) == ["edge1", "edge2", "edge3", "edge4"])
        #expect(host.commits.last?.projections.map(\.reference) == ["edge4"], "only the new one is written")
    }

    @Test func aReferenceInUseIsNeverReusedAndAFreedOneIsTaken() {
        var sketch = Sketch()
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "edge1", curve: .line(Vector2(0, 50), Vector2(1, 50))))))
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "edge3", curve: .line(Vector2(0, 60), Vector2(1, 60))))))
        let (model, _) = makeModel(sketch, answering: [candidate(0), candidate(100)])
        model.project(.face(solid: 0, FaceID(1)))
        #expect(projected(model.sketch).map(\.reference) == ["edge1", "edge3", "edge2", "edge4"])
    }

    @Test func anEdgeAlreadyProjectedIsLeftOutWithAReason() {
        let (model, host) = makeModel(answering: [candidate(0)])
        model.project(.edge(solid: 0, EdgeID(1)))
        model.project(.edge(solid: 0, EdgeID(1)))
        #expect(host.commits.count == 1 && projected(model.sketch).count == 1, "nothing is stored twice")
        #expect(model.refusal == "That edge is already projected.")
    }

    @Test func whatCantBeProjectedIsSaidInWordsAndNothingIsStored() {
        let (model, host) = makeModel(skipped: ["Edge 3 can't be projected: it is perpendicular to the sketch plane."])
        model.project(.edge(solid: 0, EdgeID(3)))
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "Edge 3 can't be projected: it is perpendicular to the sketch plane.")
        let (silent, _) = makeModel()
        silent.project(.face(solid: 0, FaceID(1)))
        #expect(silent.refusal == "There is nothing there to project.")
        silent.project(nil)
        #expect(silent.refusal == "Click an edge or a face of the model to project it.")
    }

    @Test func someEdgesProjectingAndSomeNotStoresTheOnesThatDoAndSaysWhatWasLeftOut() {
        let reason = "Edge 2 can't be projected: it is a circle that doesn't face the sketch plane."
        let (model, host) = makeModel(answering: [candidate(0)], skipped: [reason])
        model.project(.face(solid: 0, FaceID(1)))
        #expect(host.commits.count == 1 && projected(model.sketch).count == 1)
        #expect(model.refusal == reason)
    }

    @Test func aProjectedEdgeHoldsAPointDrawnOnIt() {
        let (model, _) = makeModel(answering: [candidate(0)])
        model.project(.edge(solid: 0, EdgeID(1)))
        model.choose(.line)
        model.hover(at: Vector2(10, 0.3), tolerance: 1, modifiers: [])
        #expect(model.preview.inferred == [.pointOn], "S5b's point-on inference snaps onto projected geometry")
    }

    @Test func aSuspendedProjectionIsDrawnRed() {
        var sketch = Sketch()
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "edge1", curve: .line(.zero, Vector2(10, 0))))))
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "edge2", curve: .line(Vector2(0, 5), Vector2(10, 5)),
                                                            isSuspended: true))))
        let tints = SketchEditorModel(sketch: sketch, plane: .xy).overlay.lines.filter { $0.tint != .preview }.map(\.tint)
        #expect(tints == [.projected, .conflicting], "a projection whose pick finds no edge now is red, with its last curve")
    }

    @Test func projectHasItsKeyAndHint() {
        #expect(SketchTool.project.title == "Project" && SketchTool.project.key == "p")
        #expect(SketchTool.project.hint?.contains("edge") == true)
    }
}
```

**Modify** `Tests/CreatorSketchEditorTests/SnapAndTangentCoverageTests.swift` (Task 1's test: Project places no points either):

```swift
    @Test(arguments: [SketchTool.select, .dimension, .trim, .extend, .fillet, .mirror, .pattern])
```

with:

```swift
    @Test(arguments: [SketchTool.select, .dimension, .trim, .extend, .fillet, .mirror, .pattern, .project])
```

**Modify** `Tests/CreatorSketchEditorTests/ToolOptionsViewTests.swift`:

```swift
        #expect(SketchTool.allCases == drawing + [.trim, .extend, .fillet, .mirror, .pattern])
```

with:

```swift
        #expect(SketchTool.allCases == drawing + [.trim, .extend, .fillet, .mirror, .pattern, .project])
```

**Modify** `Tests/CreatorSketchEditorTests/ToolOptionsViewTests.swift`:

```swift
        #expect(hinted == [.arcThreePoint, .trim, .extend, .fillet, .mirror, .pattern])
```

with:

```swift
        #expect(hinted == [.arcThreePoint, .trim, .extend, .fillet, .mirror, .pattern, .project])
```

- [ ] **Step 2: Run the tests; they don't compile**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: errors for `SketchTool.project`, `ProjectionCandidate`, `ProjectionResolution`, `ProjectionWrite`.

- [ ] **Step 3: Implement**

**Modify** `Package.swift`:

```swift
        .target(name: "CreatorSketchEditor",
                dependencies: ["CreatorSketch", "CreatorViewport", "CreatorGeometry", "CreatorStyle", metalUI]),
```

with:

```swift
        .target(name: "CreatorSketchEditor",
                dependencies: ["CreatorSketch", "CreatorViewport", "CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI]),
```

**Modify** `Package.swift`:

```swift
        .testTarget(name: "CreatorSketchEditorTests",
                    dependencies: ["CreatorSketchEditor", "CreatorSketch", "CreatorViewport", "CreatorGeometry", "CreatorStyle", metalUI]),
```

with:

```swift
        .testTarget(
            name: "CreatorSketchEditorTests",
            dependencies: [
                "CreatorSketchEditor", "CreatorSketch", "CreatorViewport", "CreatorKernel", "CreatorGeometry", "CreatorStyle", metalUI,
            ]
        ),
```

**Create** `Sources/CreatorSketchEditor/ProjectionCandidate.swift`:

```swift
import CreatorKernel
import CreatorSketch

/// A model edge the host resolved for the Project tool (sketcher spec §8): its curve on the sketch plane, the remembered
/// pick the Sketch node stores for it, and the solid it is on.
public struct ProjectionCandidate: Hashable, Sendable {
    public var curve: ProjectedCurve
    /// `topology.picks(for: [edge])`: exactly one pick, which names the edge by its faces' tags.
    public var pick: EdgePick
    /// The viewport item the edge is on (`PickTarget.solidIndex`); the host turns it into the node that made the solid.
    public var solid: Int

    public init(curve: ProjectedCurve, pick: EdgePick, solid: Int) {
        self.curve = curve
        self.pick = pick
        self.solid = solid
    }
}
```

**Create** `Sources/CreatorSketchEditor/ProjectionResolution.swift`:

```swift
/// What the host made of a Project pick: the edges that can be projected (one for an edge pick, each edge of the
/// face for a face pick) and, in plain words, why others were left out.
public struct ProjectionResolution: Hashable, Sendable {
    public var candidates: [ProjectionCandidate]
    public var skipped: [String]

    public init(candidates: [ProjectionCandidate], skipped: [String]) {
        self.candidates = candidates
        self.skipped = skipped
    }
}
```

**Create** `Sources/CreatorSketchEditor/ProjectionWrite.swift`:

```swift
import CreatorKernel

/// One projection an edit added, for the host to store beside the sketch: the Sketch node's `projection.<reference>`
/// setting takes the pick, and the solid it is on is wired into the node's `references`.
public struct ProjectionWrite: Hashable, Sendable {
    public var reference: String
    public var pick: EdgePick
    public var solid: Int

    public init(reference: String, pick: EdgePick, solid: Int) {
        self.reference = reference
        self.pick = pick
        self.solid = solid
    }
}
```

**Replace the whole of** `Sources/CreatorSketchEditor/SketchCommit.swift`:

```swift
import CreatorSketch

/// One edit the sketch editor made, for the host to store as one undo step (sketcher spec §8): the whole new
/// sketch, already solved and remembered (S4 → S5 handoff), the undo menu's description, and, for Project, the
/// projections the edit added (their picks and solids live in the Sketch node's settings and wires, not the sketch).
public struct SketchCommit: Hashable, Sendable {
    public var sketch: Sketch
    public var description: String
    public var projections: [ProjectionWrite]

    public init(sketch: Sketch, description: String, projections: [ProjectionWrite] = []) {
        self.sketch = sketch
        self.description = description
        self.projections = projections
    }
}
```

**Replace the whole of** `Sources/CreatorSketchEditor/SketchEditorEvents.swift`:

```swift
import CreatorGeometry
import CreatorViewport

/// What the sketch editor tells its host. Every callback runs on the main actor, from input.
public struct SketchEditorEvents {
    /// An edit: the host stores `commit.sketch` in the Sketch node's `sketch` setting as one undo step.
    public var committed: @MainActor (SketchCommit) -> Void = { _ in }
    /// Finish (⏎, Esc with nothing in progress, or the Finish button): the host leaves sketch mode.
    public var finished: @MainActor () -> Void = {}
    /// Asked first by Esc and Finish: the host closes a popup of its own that is open over the sketch (the add-node
    /// palette) and returns true, and the key does nothing else. The sketch's keys are button shortcuts, which run
    /// before the host's own keys, so without this Esc would end sketch mode under an open palette.
    public var dismissHostPopup: @MainActor () -> Bool = { false }
    /// The Project tool's pick (an edge, or a face for all its edges) and the sketch plane: the host resolves it into the
    /// edges that can be projected onto that plane, with the picks the Sketch node stores.
    public var projection: @MainActor (PickTarget, Plane) -> ProjectionResolution = { _, _ in
        ProjectionResolution(candidates: [], skipped: ["Projecting isn't available here."])
    }

    public init() {}
}
```

**Modify** `Sources/CreatorSketchEditor/SketchTool.swift`:

```swift
/// The sketch editor's tools (sketcher spec §8's toolbar): the drawing tools, Dimension, and the tools that change
/// what's drawn through `SketchCommands` (Trim, Extend, Fillet, Mirror, Pattern). Project follows in S5c.
```

with:

```swift
/// The sketch editor's tools (sketcher spec §8's toolbar): the drawing tools, Dimension, the tools that change what's
/// drawn through `SketchCommands` (Trim, Extend, Fillet, Mirror, Pattern), and Project, which takes the model's edges.
```

**Modify** `Sources/CreatorSketchEditor/SketchTool.swift`:

```swift
    case pattern

    /// The toolbar's title.
```

with:

```swift
    case pattern
    /// Click an edge of the model (a face gives all its edges) to project it onto the sketch (P). It declines the plane
    /// click, so the viewport's ID-buffer pick reaches `clickedModel`.
    case project

    /// The toolbar's title.
```

**Modify** `Sources/CreatorSketchEditor/SketchTool.swift`:

```swift
        case .pattern: "Pattern"
        }
```

with:

```swift
        case .pattern: "Pattern"
        case .project: "Project"
        }
```

**Modify** `Sources/CreatorSketchEditor/SketchTool.swift`:

```swift
        case .arcThreePoint: "Click the start, the end, then a point the arc passes through."
```

with:

```swift
        case .arcThreePoint: "Click the start, the end, then a point the arc passes through."
        case .project: "Click an edge of the model, or a face for all its edges, to project it onto the sketch."
```

**Modify** `Sources/CreatorSketchEditor/SketchTool.swift`:

```swift
        case .select, .dimension, .trim, .extend, .fillet, .mirror, .pattern: false
```

with:

```swift
        case .select, .dimension, .trim, .extend, .fillet, .mirror, .pattern, .project: false
```

**Modify** `Sources/CreatorSketchEditor/SketchTool.swift`:

```swift
        case .select, .line, .arc, .arcThreePoint, .circle, .point, .dimension, .fillet, .pattern: false
```

with:

```swift
        case .select, .line, .arc, .arcThreePoint, .circle, .point, .dimension, .fillet, .pattern, .project: false
```

**Modify** `Sources/CreatorSketchEditor/Views/SketchToolButton.swift`:

```swift
        case .trim: "t"
        case .select, .point, .arcThreePoint, .extend, .fillet, .mirror, .pattern: nil
```

with:

```swift
        case .trim: "t"
        case .project: "p"
        case .select, .point, .arcThreePoint, .extend, .fillet, .mirror, .pattern: nil
```

**Modify** `Sources/CreatorSketchEditor/SketchOverlayBuilder.swift`:

```swift
        if entity.isConstruction { return .construction }
        if case .projected = entity.kind { return .projected }
```

with:

```swift
        if case .projected(let source) = entity.kind, source.isSuspended { return .conflicting }
        if entity.isConstruction { return .construction }
        if case .projected = entity.kind { return .projected }
```

**Modify** `Sources/CreatorSketchEditor/SketchOverlayBuilder.swift`:

```swift
    /// The colour role of one entity: selected, then hovered, then conflicting, construction, projected, then free or
    /// fixed.
```

with:

```swift
    /// The colour role of one entity: selected, then hovered, then conflicting, a suspended projection (conflicting too:
    /// its pick finds no edge now), construction, projected, then free or fixed.
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel.swift`:

```swift
    func commit(_ edited: Sketch, _ description: String) {
```

with:

```swift
    func commit(_ edited: Sketch, _ description: String, projections: [ProjectionWrite] = []) {
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel.swift`:

```swift
        events.committed(SketchCommit(sketch: remembered, description: description))
```

with:

```swift
        events.committed(SketchCommit(sketch: remembered, description: description, projections: projections))
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift`:

```swift
        case .select, .line, .arc, .arcThreePoint, .circle, .point, .dimension: break   // not commands: `click` routes them
```

with:

```swift
        case .select, .line, .arc, .arcThreePoint, .circle, .point, .dimension, .project: break   // not commands: `click` routes them
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`:

```swift
        case .trim, .extend, .fillet, .mirror, .pattern: modify(at: p, tolerance: tolerance)
        }
```

with:

```swift
        case .trim, .extend, .fillet, .mirror, .pattern: modify(at: p, tolerance: tolerance)
        case .project: break   // takes no plane click: the viewport's pick reaches `clickedModel`
        }
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+ViewportTool.swift`:

```swift
    public func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool {
        follow(point, projector)
        if let p = projector.planePoint(under: point, on: plane) {
```

with:

```swift
    public func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool {
        follow(point, projector)
        guard tool != .project else { return false }
        if let p = projector.planePoint(under: point, on: plane) {
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+ViewportTool.swift`:

```swift
    /// A drag that starts on a point moves it; any other drag pans (planar navigation).
```

with:

```swift
    /// The Project tool takes the model's pick under a click it declined (Task 2): an edge, a face, or empty space.
    public func clickedModel(_ target: PickTarget?, at point: ScreenPoint, modifiers: ViewportModifiers,
                             projector: ViewportProjector) -> Bool {
        guard tool == .project else { return false }
        follow(point, projector)
        project(target)
        return true
    }

    /// A drag that starts on a point moves it; any other drag pans (planar navigation).
```

**Create** `Sources/CreatorSketchEditor/SketchEditorModel+Project.swift`:

```swift
import CreatorSketch
import CreatorViewport

extension SketchEditorModel {
    /// A Project click: the host resolves the pick into the edges that can be projected onto the plane (`events.projection`),
    /// and each becomes a fixed `.projected` entity with a fresh reference, all in one undo step with the picks to store. An
    /// edge that is already projected, and any the host left out, are said in words; nothing projectable stores nothing.
    func project(_ target: PickTarget?) {
        refusal = nil
        guard let target else {
            refusal = "Click an edge or a face of the model to project it."
            return
        }
        let resolution = events.projection(target, plane)
        var edited = sketch
        var writes: [ProjectionWrite] = []
        var left = resolution.skipped
        for candidate in resolution.candidates {
            guard !Self.isProjected(candidate.curve, in: edited) else {
                if !left.contains(Self.alreadyProjected) { left.append(Self.alreadyProjected) }
                continue
            }
            let reference = Self.nextReference(in: edited)
            edited.add(SketchEntity(.projected(ProjectionSource(reference: reference, curve: candidate.curve))))
            writes.append(ProjectionWrite(reference: reference, pick: candidate.pick, solid: candidate.solid))
        }
        guard !writes.isEmpty else {
            refusal = left.first ?? "There is nothing there to project."
            return
        }
        commit(edited, "Project", projections: writes)
        if !left.isEmpty { refusal = left.joined(separator: " ") }
    }

    static let alreadyProjected = "That edge is already projected."

    /// Whether the sketch already projects exactly this curve (a re-projected edge gives the very same numbers).
    static func isProjected(_ curve: ProjectedCurve, in sketch: Sketch) -> Bool {
        sketch.entityIDs.contains { id in
            if case .projected(let source)? = sketch.entities[id]?.kind { source.curve == curve && !source.isSuspended } else { false }
        }
    }

    /// "edge1", "edge2", …: the first not used by a projection in the sketch.
    static func nextReference(in sketch: Sketch) -> String {
        let used = Set(sketch.entityIDs.compactMap { id -> String? in
            if case .projected(let source)? = sketch.entities[id]?.kind { source.reference } else { nil }
        })
        var number = 1
        while used.contains("edge\(number)") { number += 1 }
        return "edge\(number)"
    }
}
```

- [ ] **Step 4: Run the tests and the full-suite check**

Run: `swift test --filter ProjectToolTests`, `swift test --filter ToolOptionsViewTests` — Expected: all pass.
Run the **full-suite check** — Expected: exit 0, `0`, `11`, total **master + 63** (1706). No new warnings; lint clean.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/CreatorSketchEditor Tests/CreatorSketchEditorTests
git commit -m "feat(sketch): the Project tool, over the viewport's pick"
```

### Task 9: Project in the app: resolving the pick, storing it, wiring the solid

The editor (Task 8) asks its host to resolve a pick and hands back the projections it added. The app resolves an edge
(or each edge of a face) with the Sketch node's own `EdgeProjection` (made public here, so the editor's projected curve is
exactly what the node recomputes on every evaluation), and `SketchStore` writes, in the same batch as the sketch (one undo
step), each pick under `NodeSetting.projection(reference)` and the solid's producer into the node's `references` input
when nothing is wired there yet. `references` takes one wire, so a sketch projects from one part: a pick on another part,
or on a part made from this very sketch (a cycle), is refused in words before anything is drawn. Deleting a projected
curve clears its stored pick. The stored sketch keeps the curve a projection was made with (the node re-resolves it on
every evaluation and never writes it back), so whenever the editor shows the sketch it re-resolves the projected edges
against the wired solid the same way (`SketchNode.refreshingProjections`): what is drawn is what the node outputs, and a
pick that finds no edge any more is drawn red (Task 8). If a commit can't be stored (the part it was picked on is gone, or the batch is refused), the alert says so and the editor is reloaded from the stored sketch (`refreshSketch`), so it never keeps projections the graph doesn't have.

**Files:**
- Create: `Sources/CreatorApp/AppModel+Project.swift`, `Sources/CreatorNodes/Sketch/SketchNode+Refresh.swift`, `Tests/CreatorAppTests/SketchProjectTests.swift`, `Tests/CreatorNodesTests/SketchRefreshTests.swift`
- Modify: `Sources/CreatorNodes/Sketch/EdgeProjection.swift`, `Sources/CreatorApp/SketchStore.swift`, `Sources/CreatorApp/AppModel+Sketch.swift`
- Modify (tests): `Tests/CreatorAppTests/SketchStoreTests.swift`

**Interfaces:**
- Consumes: `SketchEditorEvents.projection`, `SketchCommit.projections`, `ProjectionCandidate`/`ProjectionResolution` (Task 8), `AppModel.producer(of:)`, `Topology.picks(for:)`, `Graph.connectionProblem(from:to:registry:)`.
- Produces: `EdgeProjection.project(_:onto:)` and `EdgeProjection.Outcome` public; `SketchNode.refreshingProjections(of:settings:references:on:) -> Sketch`; `AppModel.refreshedProjections(_:of:) -> Sketch`; `SketchStore.Projection(reference:pick:source:)`; `SketchStore.commands(storing:in:graph:projections:)`; `AppModel.resolveProjection(_:onto:for:) -> ProjectionResolution`.

- [ ] **Step 1: Write the tests**

**Modify** `Tests/CreatorAppTests/SketchStoreTests.swift`:

```swift
        #expect(values.sorted() == [40, 75], "only the socket's dimension takes the constant")
    }
}
```

with:

```swift
        #expect(values.sorted() == [40, 75], "only the socket's dimension takes the constant")
    }

    @Test func aProjectionWritesItsPickAndWiresTheSolidOnlyWhenNothingIsWired() {
        let pick = EdgePick(key: EdgeKey([], []), matchCount: 1)
        var node = BuiltInNodes.registry.makeNode(SketchNode.typeID, at: .zero)
        node.inputValues[NodeSetting.sketch] = .sketch(Sketch(plane: .fixed(.xy)))
        var graph = Graph()
        graph.nodes[node.id] = node
        let source = Endpoint(node: NodeID(), socket: "solid")
        let references = Endpoint(node: node.id, socket: "references")
        var edited = Sketch(plane: .fixed(.xy))
        edited.add(SketchEntity(.projected(ProjectionSource(reference: "edge1", curve: .line(.zero, Vector2(10, 0))))))
        let projection = SketchStore.Projection(reference: "edge1", pick: pick, source: source)
        let commands = SketchStore.commands(storing: edited, in: node, graph: graph, projections: [projection])
        #expect(commands.contains(.setInput(node.id, NodeSetting.projection("edge1"), .edgePicks([pick]))))
        #expect(commands.contains(.connect(Link(from: source, to: references))))
        graph.links.append(Link(from: source, to: references))
        let again = SketchStore.commands(storing: edited, in: node, graph: graph, projections: [projection])
        #expect(!again.contains { if case .connect = $0 { true } else { false } }, "the wire is already there")
    }

    @Test func aRemovedProjectionTakesItsStoredPickWithIt() {
        var old = Sketch(plane: .fixed(.xy))
        let id = old.add(SketchEntity(.projected(ProjectionSource(reference: "edge1", curve: .line(.zero, Vector2(10, 0))))))
        var node = BuiltInNodes.registry.makeNode(SketchNode.typeID, at: .zero)
        node.inputValues[NodeSetting.sketch] = .sketch(old)
        node.inputValues[NodeSetting.projection("edge1")] = .edgePicks([EdgePick(key: EdgeKey([], []), matchCount: 1)])
        var edited = old
        edited.entities[id] = nil
        let commands = SketchStore.commands(storing: edited, in: node, graph: Graph())
        #expect(commands.contains(.setInput(node.id, NodeSetting.projection("edge1"), nil)))
        let kept = SketchStore.commands(storing: old, in: node, graph: Graph())
        #expect(!kept.contains(.setInput(node.id, NodeSetting.projection("edge1"), nil)), "a projection that stays keeps its pick")
    }
}
```

**Modify** `Tests/CreatorAppTests/SketchStoreTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
```

with:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
```

**Create** `Tests/CreatorNodesTests/SketchRefreshTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorSketch
import Testing
@testable import CreatorNodes

/// A sketch's projected edges re-resolved the way the node does on every evaluation, for the editor to draw.
struct SketchRefreshTests {
    func box() async throws -> Solid {
        try await FakeKernel().extrude(.rectangle(width: 40, height: 20, plane: .xy), distance: 10, mode: .oneSided,
                                       tag: NodeTag(node: NodeID(), item: 0))
    }

    func sketch() -> Sketch {
        var sketch = Sketch(plane: .fixed(.xy))
        sketch.add(SketchEntity(.projected(ProjectionSource(reference: "edge1", curve: .line(.zero, Vector2(1, 0))))))
        return sketch
    }

    func source(_ sketch: Sketch) -> ProjectionSource? {
        for id in sketch.entityIDs {
            if case .projected(let source)? = sketch.entities[id]?.kind { return source }
        }
        return nil
    }

    @Test func aProjectionTakesTheEdgesCurrentCurve() async throws {
        let solid = try await box()
        let settings: [SocketName: ConstantValue] = [NodeSetting.projection("edge1"): .edgePicks(solid.topology.picks(for: [EdgeID(1)]))]
        let refreshed = SketchNode.refreshingProjections(of: sketch(), settings: settings, references: [solid], on: .xy)
        let edge = try #require(solid.topology.edge(EdgeID(1)))
        guard case .curve(let expected) = EdgeProjection.project(edge, onto: .xy) else {
            Issue.record("the top edge projects onto xy")
            return
        }
        #expect(source(refreshed) == ProjectionSource(reference: "edge1", curve: expected), "the stale unit line is replaced")
    }

    @Test func aPickThatFindsNoEdgeSuspendsTheProjectionAndKeepsItsLastCurve() async throws {
        let solid = try await box()
        let refreshed = SketchNode.refreshingProjections(of: sketch(), settings: [:], references: [solid], on: .xy)
        #expect(source(refreshed)?.isSuspended == true)
        #expect(source(refreshed)?.curve == .line(.zero, Vector2(1, 0)))
        let nothing = SketchNode.refreshingProjections(of: sketch(), settings: [:], references: [], on: .xy)
        #expect(source(nothing)?.isSuspended == true, "no reference solid: suspended too")
    }
}
```

**Create** `Tests/CreatorAppTests/SketchProjectTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor
@testable import CreatorViewport

/// Project in the app (sketcher spec §8): a click on the model's edge or face, taken by the Project tool, lands in the
/// Sketch node as projected curves with their picks and a wire from the solid's producer, as one undo step; what can't be
/// projected, or wired, is said in words and stores nothing.
@MainActor
struct SketchProjectTests {
    struct Setup {
        var app: AppModel
        var sketch: Node
        var box: (rectangle: Node, extrude: Node, output: Node)
        var editor: SketchEditorModel
    }

    /// A box on the xy plane (bottom cap face 0, top cap face 1; edge 2k is a bottom edge, 2k + 1 a top edge, 8…11 rise) and
    /// an empty Sketch on xy, open for editing with the Project tool.
    func open() async throws -> Setup {
        var builder = GraphBuilder()
        let box = builder.box()
        let sketch = builder.add(SketchNode.self, [NodeSetting.sketch: .sketch(Sketch(plane: .fixed(.xy)))], at: Vector2(0, 300))
        // The sketch feeds an Extrude and an Output of its own, so it is evaluated (nothing is drawn in it yet, so no solid).
        let extrude = builder.add(ExtrudeNode.self, ["distance": .number(5)], at: Vector2(240, 300))
        let output = builder.add(OutputNode.self, at: Vector2(480, 300))
        builder.wire(sketch, "profiles", to: extrude, "profile")
        builder.wire(extrude, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: sketch.id)
        await app.settle()
        await app.viewport.waitForMeshes()
        await app.viewport.waitForAnimation()
        let editor = try #require(app.sketch?.editor)
        editor.choose(.project)
        return Setup(app: app, sketch: sketch, box: box, editor: editor)
    }

    func click(_ setup: Setup, _ target: PickTarget?) async {
        setup.app.viewport.pick = { _ in target }
        setup.app.viewport.click(at: ScreenPoint(700, 450))
        await setup.app.settle()
    }

    func stored(_ setup: Setup) -> Sketch? {
        let value = setup.app.document.graph.nodes[setup.sketch.id]?.inputValues[NodeSetting.sketch]
        if case .sketch(let sketch)? = value { return sketch }
        return nil
    }

    func references(_ stored: Sketch?) -> [String] {
        (stored?.entityIDs ?? []).compactMap { id in
            if case .projected(let source)? = stored?.entities[id]?.kind { source.reference } else { nil }
        }
    }

    func link(_ setup: Setup) -> Link? {
        setup.app.document.graph.incomingLink(to: Endpoint(node: setup.sketch.id, socket: "references"))
    }

    @Test func aPickedEdgeIsStoredWithItsPickAndTheSolidIsWiredAsOneUndoStep() async throws {
        let setup = try await open()
        let topology = setup.app.viewport.items[0].solid.topology
        await click(setup, .edge(solid: 0, EdgeID(1)))
        #expect(references(stored(setup)) == ["edge1"])
        let node = try #require(setup.app.document.graph.nodes[setup.sketch.id])
        #expect(node.inputValues[NodeSetting.projection("edge1")] == .edgePicks(topology.picks(for: [EdgeID(1)])))
        #expect(link(setup)?.from == Endpoint(node: setup.box.extrude.id, socket: "solid"), "the part's producer, not its Output")
        let state = try #require(setup.app.document.results[setup.sketch.id]?.state)
        if case .warning(let text) = state { #expect(!text.contains("Projected edge"), "the node resolves the pick: \(text)") }
        #expect(setup.app.document.canUndo)
        setup.app.document.undo()
        await setup.app.settle()
        #expect(references(stored(setup)).isEmpty && link(setup) == nil)
        #expect(setup.app.document.graph.nodes[setup.sketch.id]?.inputValues[NodeSetting.projection("edge1")] == nil)
        #expect(setup.app.document.canUndo == false, "the sketch, the pick and the wire were one step")
    }

    @Test func aPickedFaceProjectsEachOfItsEdges() async throws {
        let setup = try await open()
        await click(setup, .face(solid: 0, FaceID(1)))
        #expect(references(stored(setup)) == ["edge1", "edge2", "edge3", "edge4"], "the top cap's four edges")
        let node = try #require(setup.app.document.graph.nodes[setup.sketch.id])
        #expect((1...4).allSatisfy { node.inputValues[NodeSetting.projection("edge\($0)")] != nil })
        #expect(setup.editor.refusal == nil)
        setup.app.document.undo()
        await setup.app.settle()
        #expect(setup.app.document.canUndo == false)
    }

    @Test func aSideFaceKeepsWhatProjectsAndSaysWhatDoesNot() async throws {
        let setup = try await open()
        await click(setup, .face(solid: 0, FaceID(2)))
        #expect(references(stored(setup)) == ["edge1"], "its bottom and top edges project to the same line")
        let message = try #require(setup.editor.refusal)
        #expect(message.contains("already projected") && message.contains("2 edges of that face can't be projected"))
        #expect(message.contains("perpendicular"), "\(message)")
    }

    @Test func anEdgeThatCantBeProjectedStoresNothing() async throws {
        let setup = try await open()
        await click(setup, .edge(solid: 0, EdgeID(8)))
        #expect(setup.editor.refusal == "That edge can't be projected: it is perpendicular to the sketch plane, so it projects to a point.")
        #expect(setup.app.document.canUndo == false && link(setup) == nil)
    }

    @Test func aSecondPartIsRefusedBecauseReferencesTakesOneWire() async throws {
        var builder = GraphBuilder()
        let first = builder.box()
        let second = builder.box(at: Vector2(0, 200))
        let sketch = builder.add(SketchNode.self, [NodeSetting.sketch: .sketch(Sketch(plane: .fixed(.xy)))], at: Vector2(0, 500))
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: sketch.id)
        await app.settle()
        await app.viewport.waitForMeshes()
        let editor = try #require(app.sketch?.editor)
        editor.choose(.project)
        let order = app.viewport.items.compactMap { item in app.producer(of: item.solid)?.node }
        let firstIndex = try #require(order.firstIndex(of: first.extrude.id))
        let secondIndex = try #require(order.firstIndex(of: second.extrude.id))
        app.viewport.pick = { _ in .edge(solid: firstIndex, EdgeID(1)) }
        app.viewport.click(at: ScreenPoint(700, 450))
        await app.settle()
        #expect(editor.refusal == nil && app.document.graph.incomingLink(to: Endpoint(node: sketch.id, socket: "references")) != nil)
        app.viewport.pick = { _ in .edge(solid: secondIndex, EdgeID(1)) }
        app.viewport.click(at: ScreenPoint(700, 451))
        await app.settle()
        #expect(editor.refusal == "This sketch already projects from another part. Project from one part per sketch.")
        #expect(editor.sketch.entityIDs.count == 1, "nothing was added")
    }

    @Test func aPartMadeFromThisSketchCantBeProjectedIntoIt() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        await app.viewport.waitForMeshes()
        let editor = try #require(app.sketch?.editor)
        editor.choose(.project)
        app.viewport.pick = { _ in .edge(solid: 0, EdgeID(1)) }
        app.viewport.click(at: ScreenPoint(700, 450))
        #expect(editor.refusal == "That part is made from this sketch, so its edges can't be projected into it.")
        #expect(app.document.canUndo == false)
    }

    @Test func aProjectionWhoseSolidIsGoneIsRefusedAndTheEditorFallsBackToTheStoredSketch() async throws {
        let setup = try await open()
        let resolution = setup.app.resolveProjection(.edge(solid: 0, EdgeID(1)), onto: .xy, for: setup.sketch.id)
        var candidate = try #require(resolution.candidates.first)
        candidate.solid = 99   // the solid the editor was told about has gone by the time the commit is stored
        setup.editor.events.projection = { _, _ in ProjectionResolution(candidates: [candidate], skipped: []) }
        await click(setup, .edge(solid: 0, EdgeID(1)))
        #expect(setup.app.alert != nil, "said in words")
        #expect(references(stored(setup)).isEmpty && link(setup) == nil && setup.app.document.canUndo == false, "nothing stored")
        #expect(references(setup.editor.sketch).isEmpty, "and the editor doesn't keep the projection the graph refused")
    }

    @Test func emptySpaceAsksForAnEdge() async throws {
        let setup = try await open()
        await click(setup, nil)
        #expect(setup.editor.refusal == "Click an edge or a face of the model to project it.")
    }

    @Test func theEditorShowsTheProjectionWhereTheModelIsNow() async throws {
        let setup = try await open()
        await click(setup, .edge(solid: 0, EdgeID(1)))
        func curve() -> ProjectedCurve? {
            for id in setup.editor.sketch.entityIDs {
                if case .projected(let source)? = setup.editor.sketch.entities[id]?.kind { return source.curve }
            }
            return nil
        }
        func length(_ curve: ProjectedCurve?) -> Double? {
            if case .line(let a, let b)? = curve { (b - a).length } else { nil }
        }
        let before = length(curve())
        try setup.app.document.perform(.setInput(setup.box.rectangle.id, "width", .number(80)))
        await setup.app.settle()
        #expect(length(curve()) == 80 && before != 80, "the purple line is the edge's new length, not the one it was projected at")
        #expect(setup.app.sketch?.editor === setup.editor, "and the sketch stayed open")
    }

    @Test func theProjectionSurvivesTheSketchBeingEvaluatedAndFollowsTheModel() async throws {
        let setup = try await open()
        await click(setup, .edge(solid: 0, EdgeID(1)))
        try setup.app.document.perform(.setInput(setup.box.rectangle.id, "width", .number(80)))
        await setup.app.settle()
        let node = try #require(setup.app.document.graph.nodes[setup.sketch.id])
        let state = try #require(setup.app.document.results[node.id]?.state)
        if case .warning(let text) = state { #expect(!text.contains("matches no edge"), "the pick still finds its edge: \(text)") }
        #expect(state.isSuccess)
    }
}
```

- [ ] **Step 2: Run the tests; they don't compile**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: errors "type 'SketchStore' has no member 'Projection'" and "extra argument 'projections' in call".

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorNodes/Sketch/EdgeProjection.swift`:

```swift
enum EdgeProjection {
    enum Outcome: Equatable {
```

with:

```swift
public enum EdgeProjection {
    public enum Outcome: Equatable {
```

**Modify** `Sources/CreatorNodes/Sketch/EdgeProjection.swift`:

```swift
    static func project(_ edge: EdgeInfo, onto plane: Plane) -> Outcome {
```

with:

```swift
    public static func project(_ edge: EdgeInfo, onto plane: Plane) -> Outcome {
```

**Modify** `Sources/CreatorApp/SketchStore.swift`:

```swift
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
```

with:

```swift
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import Foundation
```

**Modify** `Sources/CreatorApp/SketchStore.swift`:

```swift
/// Reserved names are never touched: they are never sockets (`SketchNode.isReservedDimensionName`).
enum SketchStore {
    static func commands(storing new: Sketch, in node: Node, graph: Graph) -> [GraphCommand] {
```

with:

```swift
/// Reserved names are never touched: they are never sockets (`SketchNode.isReservedDimensionName`).
/// - a projection the edit added stores its pick under `NodeSetting.projection(reference)` and wires its solid into
///   `references` when nothing is wired there; one the edit removed clears its pick.
enum SketchStore {
    /// A projection to store beside the sketch: the pick, and the output that made the solid it was picked on.
    struct Projection {
        let reference: String
        let pick: EdgePick
        let source: Endpoint
    }

    /// The Sketch node's input the projected solids are wired into (sketcher spec §7).
    static let referencesSocket: SocketName = "references"

    static func commands(storing new: Sketch, in node: Node, graph: Graph, projections: [Projection] = []) -> [GraphCommand] {
```

**Modify** `Sources/CreatorApp/SketchStore.swift`:

```swift
        return before + [.setInput(node.id, NodeSetting.sketch, .sketch(storing))] + after
    }
```

with:

```swift
        return before + [.setInput(node.id, NodeSetting.sketch, .sketch(storing))] + after
            + projectionCommands(old: old, new: new, in: node, graph: graph, projections: projections)
    }

    /// The picks of the projections the edit added, the pick settings of the ones it removed (cleared), and the wire from the
    /// first added projection's solid into `references` when that input has none.
    static func projectionCommands(old: Sketch?, new: Sketch, in node: Node, graph: Graph,
                                   projections: [Projection]) -> [GraphCommand] {
        var commands: [GraphCommand] = []
        let removed = old.map(projectedReferences).map { $0.subtracting(projectedReferences(new)) } ?? []
        for reference in removed.sorted() where node.inputValues[NodeSetting.projection(reference)] != nil {
            commands.append(.setInput(node.id, NodeSetting.projection(reference), nil))
        }
        for projection in projections {
            commands.append(.setInput(node.id, NodeSetting.projection(projection.reference), .edgePicks([projection.pick])))
        }
        let references = Endpoint(node: node.id, socket: referencesSocket)
        if let first = projections.first, graph.incomingLink(to: references) == nil {
            commands.append(.connect(Link(from: first.source, to: references)))
        }
        return commands
    }

    /// The references of the sketch's projected edges.
    static func projectedReferences(_ sketch: Sketch) -> Set<String> {
        Set(sketch.entityIDs.compactMap { id -> String? in
            if case .projected(let source)? = sketch.entities[id]?.kind { source.reference } else { nil }
        })
    }
```

**Create** `Sources/CreatorNodes/Sketch/SketchNode+Refresh.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorSketch

extension SketchNode {
    /// `sketch` with each projected edge re-resolved against `references` exactly as the node does on every evaluation
    /// (`SketchProjections`): its curve is the picked edge's current projection onto `plane`, and it is suspended when its pick
    /// (in `settings`, under `NodeSetting.projection(reference)`) no longer finds exactly one edge. The sketch editor shows this,
    /// because the stored sketch keeps the curve a projection was made with and the node never writes the refresh back.
    public static func refreshingProjections(of sketch: Sketch, settings: [SocketName: ConstantValue], references: [Solid],
                                             on plane: Plane) -> Sketch {
        var refreshed = sketch
        _ = SketchProjections.resolve(&refreshed, settings: settings, references: references, on: plane)
        return refreshed
    }
}
```

**Modify** `Sources/CreatorApp/AppModel+Sketch.swift`:

```swift
        var sketch = SketchStore.folded(stored, constants: node.inputValues)
```

with:

```swift
        var sketch = refreshedProjections(SketchStore.folded(stored, constants: node.inputValues), of: node)
```

**Modify** `Sources/CreatorApp/AppModel+Sketch.swift`:

```swift
        sketchEditor.events.finished = { [weak self] in self?.finishSketch() }
```

with:

```swift
        sketchEditor.events.finished = { [weak self] in self?.finishSketch() }
        sketchEditor.events.projection = { [weak self] target, plane in
            self?.resolveProjection(target, onto: plane, for: id) ?? ProjectionResolution(candidates: [], skipped: [Self.noProjection])
        }
```

**Modify** `Sources/CreatorApp/AppModel+Sketch.swift`:

```swift
    func storeSketch(_ commit: SketchCommit) {
        guard let session = sketch, let node = document.graph.nodes[session.node] else { return }
        do {
            try document.perform(.batch(SketchStore.commands(storing: commit.sketch, in: node, graph: document.graph)))
        } catch {
            alert = .problem(AppProblem("The sketch couldn't be changed", error.message))
        }
    }
```

with:

```swift
    func storeSketch(_ commit: SketchCommit) {
        guard let session = sketch, let node = document.graph.nodes[session.node] else { return }
        var projections: [SketchStore.Projection] = []
        for write in commit.projections {
            guard viewport.items.indices.contains(write.solid), let source = producer(of: viewport.items[write.solid].solid) else {
                alert = .problem(AppProblem("The projection couldn't be stored", "The part it was picked on can't be found."))
                refreshSketch()   // the editor already shows the projections it was refused: back to what is stored
                return
            }
            projections.append(SketchStore.Projection(reference: write.reference, pick: write.pick, source: source))
        }
        do {
            let commands = SketchStore.commands(storing: commit.sketch, in: node, graph: document.graph, projections: projections)
            try document.perform(.batch(commands))
        } catch {
            alert = .problem(AppProblem("The sketch couldn't be changed", error.message))
            refreshSketch()
        }
    }
```

**Create** `Sources/CreatorApp/AppModel+Project.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorSketchEditor
import CreatorViewport

extension AppModel {
    static let noProjection = "Projecting isn't available right now."

    /// The sketch with its projected edges re-resolved against the solids wired into `references` (current curves; suspended
    /// where a pick no longer finds exactly one edge), as the node resolves them on every evaluation, so the editor draws what
    /// the node outputs. Unchanged when nothing is projected, or when the wired solid has no result yet.
    func refreshedProjections(_ sketch: Sketch, of node: Node) -> Sketch {
        guard !SketchStore.projectedReferences(sketch).isEmpty, let plane = sketchPlane(of: node, sketch),
              let link = document.graph.incomingLink(to: Endpoint(node: node.id, socket: SketchStore.referencesSocket)),
              let result = document.results[link.from.node], result.state.isSuccess else { return sketch }
        let solids = (result.outputs?[link.from.socket]?.items ?? []).compactMap { scalar -> Solid? in
            if case .solid(let solid) = scalar { solid } else { nil }
        }
        return SketchNode.refreshingProjections(of: sketch, settings: node.inputValues, references: solids, on: plane)
    }

    /// The Project tool's pick (sketcher spec §8) as projectable edges: the picked edge, or every edge of the picked face, on
    /// `plane`, each with the pick the Sketch node stores (`topology.picks(for:)`) and the solid it is on. The Sketch node's
    /// `references` takes one wire, so the part must be the one already wired there, or the first (and then it must not be made
    /// from this sketch). Edges that can't be projected are left out with the reason, said once per reason.
    func resolveProjection(_ target: PickTarget, onto plane: Plane, for sketchNode: NodeID) -> ProjectionResolution {
        func refused(_ text: String) -> ProjectionResolution { ProjectionResolution(candidates: [], skipped: [text]) }
        guard viewport.items.indices.contains(target.solidIndex) else { return refused("That part isn't shown any more.") }
        let solid = viewport.items[target.solidIndex].solid
        guard let source = producer(of: solid) else { return refused("The node that made this part can't be found.") }
        if let problem = referencesProblem(source, sketchNode) { return refused(problem) }
        let topology = solid.topology
        let isFace: Bool
        let edges: [EdgeInfo]
        switch target {
        case .edge(_, let id):
            (isFace, edges) = (false, topology.edge(id).map { [$0] } ?? [])
        case .face(_, let id):
            (isFace, edges) = (true, topology.edges.filter { !$0.isSeam && $0.faces.contains(id) })
        }
        var candidates: [ProjectionCandidate] = []
        var left: [(reason: String, count: Int)] = []
        for edge in edges {
            switch EdgeProjection.project(edge, onto: plane) {
            case .curve(let curve):
                let picks = topology.picks(for: [edge.id])
                if picks.count == 1, let pick = picks.first {
                    candidates.append(ProjectionCandidate(curve: curve, pick: pick, solid: target.solidIndex))
                } else {
                    Self.note("it has no stable name: it isn't between two faces", in: &left)
                }
            case .refused(let reason):
                Self.note(reason, in: &left)
            }
        }
        let skipped = left.map { entry -> String in
            if !isFace { return "That edge can't be projected: \(entry.reason)." }
            let which = entry.count == 1 ? "An edge" : "\(entry.count.formatted()) edges"
            return "\(which) of that face can't be projected: \(entry.reason)."
        }
        return ProjectionResolution(candidates: candidates, skipped: skipped)
    }

    private static func note(_ reason: String, in left: inout [(reason: String, count: Int)]) {
        if let index = left.firstIndex(where: { $0.reason == reason }) {
            left[index].count += 1
        } else {
            left.append((reason, 1))
        }
    }

    /// Why `source` can't be the part a sketch projects from, in words, or `nil`: the sketch's `references` already holds
    /// another part, or wiring this one would make a cycle (the part is made from the sketch).
    func referencesProblem(_ source: Endpoint, _ sketchNode: NodeID) -> String? {
        let references = Endpoint(node: sketchNode, socket: SketchStore.referencesSocket)
        if let link = document.graph.incomingLink(to: references) {
            return link.from == source ? nil : "This sketch already projects from another part. Project from one part per sketch."
        }
        switch document.graph.connectionProblem(from: source, to: references, registry: registry) {
        case nil: return nil
        case .wouldCreateCycle?: return "That part is made from this sketch, so its edges can't be projected into it."
        case _?: return "That part can't be wired into this sketch."
        }
    }
}
```

- [ ] **Step 4: Run the tests and the full-suite check**

Run: `swift test --filter SketchProjectTests` and `swift test --filter SketchStoreTests` — Expected: all pass.
Run the **full-suite check** — Expected: exit 0, `0`, `11`, total **master + 77** (1720). No new warnings; lint clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorApp Sources/CreatorNodes Tests/CreatorAppTests
git commit -m "feat(app): Project stores its picks and wires the solid, as one undo step"
```

### Task 10: "New Sketch on Face" in the app

Choosing the face menu's item (Task 3) inserts Plane from Face and a Sketch into the graph as one batch (spec §8: "New
sketch on face"; sketcher spec §7: Plane from Face "wires into a Sketch"), and opens the sketch. The solid's producer is wired
into the plane node's `solid`, the plane into the Sketch's `plane`, the Sketch's own plane is `.wired`, and the nodes
sit beside the producer. The new Plane from Face hasn't evaluated when the sketch opens, so the sketch opens on the plane
computed from the face right now (`PlaneFromFaceNode.plane(of:)`, a new public function over the same `FacePlane` that
`evaluate` uses; `evaluate` is left alone so the naming-face-picks track's edits to it merge, and a test pins the two equal); the editor takes the node's own
plane once it evaluates (`refreshSketch` already does). Nothing downstream draws the new chain, so
the node may never evaluate (Final preview runs only what feeds an Output); `sketchPlane(of:_:)` then works the plane out from
the picked face of the solid wired in, so "Edit sketch" opens the sketch again before it is wired on. The Sketch's `references`
stays unwired, as the spec has it; the first Project wires it.

**Files:**
- Create: `Sources/CreatorApp/AppModel+NewSketch.swift`, `Tests/CreatorAppTests/NewSketchOnFaceTests.swift`, `Tests/CreatorNodesTests/FacePlaneTests.swift`
- Modify: `Sources/CreatorNodes/Values/PlaneFromFaceNode.swift`, `Sources/CreatorApp/AppModel+Sketch.swift`, `Sources/CreatorApp/AppModel+Viewport.swift`

**Interfaces:**
- Consumes: `ViewportEvents.newSketchOnFace` (Task 3), `AppModel.producer(of:)`, `NodeRegistry.makeNode(_:at:)`, `NodeSetting.face`, `ConstantValue.facePick`.
- Produces: `PlaneFromFaceNode.plane(of: FaceInfo) -> Plane?`; `AppModel.beginSketch(for:plane:)` (the plane of a wired sketch whose source hasn't evaluated); `AppModel.newSketchOnFace(_:_:)`.

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorNodesTests/FacePlaneTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorNodes

/// The plane a flat face gets, shared by the Plane from Face node and the editor that opens before the node has run.
struct FacePlaneTests {
    func face(_ kind: SurfaceKind, normal: Vector3?, centroid: Vector3 = Vector3(1, 2, 3)) -> FaceInfo {
        FaceInfo(id: FaceID(0), kind: kind, normal: normal, area: 1, centroid: centroid, tags: [])
    }

    @Test func aFlatFaceWithANormalGetsThePlaneOnItsCentroid() {
        let plane = PlaneFromFaceNode.plane(of: face(.plane, normal: Vector3(0, 0, 2)))
        #expect(plane == FacePlane.plane(origin: Vector3(1, 2, 3), normal: .unitZ))
        #expect(plane?.normal == .unitZ && plane?.origin == Vector3(1, 2, 3))
    }

    @Test func aCurvedFaceOrOneWithNoNormalGetsNone() {
        #expect(PlaneFromFaceNode.plane(of: face(.cylinder, normal: .unitZ)) == nil)
        #expect(PlaneFromFaceNode.plane(of: face(.plane, normal: nil)) == nil)
        #expect(PlaneFromFaceNode.plane(of: face(.plane, normal: .zero)) == nil)
    }
}
```

**Create** `Tests/CreatorAppTests/NewSketchOnFaceTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor
@testable import CreatorViewport

/// "New Sketch on Face" (sketcher spec §8): the face menu inserts Plane from Face and a Sketch as one undo step and opens
/// the sketch on the face's plane before the new plane node has evaluated.
@MainActor
struct NewSketchOnFaceTests {
    /// A box on xy: face 0 is its bottom, face 1 its top (flat, with normals); faces 2…5 are flat with none (FakeKernel).
    func open() async -> (app: AppModel, box: (rectangle: Node, extrude: Node, output: Node)) {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        await app.viewport.waitForMeshes()
        return (app, box)
    }

    func node(_ app: AppModel, _ type: String) -> Node? {
        app.document.graph.nodes.values.first { $0.typeID == type }
    }

    func chooseNewSketch(_ app: AppModel, on face: FaceID) throws {
        app.viewport.pick = { _ in .face(solid: 0, face) }
        let items = app.viewport.contextMenuItems(at: ScreenPoint(700, 450))
        let item = try #require(items.first { if case .newSketchOnFace = $0 { true } else { false } })
        app.viewport.choose(item)
    }

    @Test func theFaceMenuInsertsThePlaneAndTheSketchAsOneStepAndOpensTheSketch() async throws {
        let (app, box) = await open()
        try chooseNewSketch(app, on: FaceID(1))
        #expect(app.sketch != nil && app.viewport.tool === app.sketch?.editor, "the sketch is open at once, before any evaluation")
        let planeNode = try #require(node(app, PlaneFromFaceNode.typeID))
        let sketchNode = try #require(node(app, SketchNode.typeID))
        let topology = app.viewport.items[0].solid.topology
        #expect(planeNode.inputValues[NodeSetting.face] == .facePick(try #require(topology.facePick(for: FaceID(1)))))
        guard case .sketch(let sketch)? = sketchNode.inputValues[NodeSetting.sketch] else {
            Issue.record("the Sketch holds no sketch")
            return
        }
        #expect(sketch.plane == .wired)
        let links = app.document.graph.links
        #expect(links.contains(Link(from: Endpoint(node: box.extrude.id, socket: "solid"),
                                    to: Endpoint(node: planeNode.id, socket: "solid"))), "from the part's producer")
        #expect(links.contains(Link(from: Endpoint(node: planeNode.id, socket: "plane"),
                                    to: Endpoint(node: sketchNode.id, socket: "plane"))))
        #expect(app.document.graph.incomingLink(to: Endpoint(node: sketchNode.id, socket: "references")) == nil)
        #expect(app.sketch?.node == sketchNode.id && app.editor.selection == [sketchNode.id])
        #expect(app.sketch?.editor.plane == .xy, "FakeKernel's centroids are the origin, so the top cap's plane is xy")
        app.document.undo()
        await app.settle()
        #expect(node(app, PlaneFromFaceNode.typeID) == nil && node(app, SketchNode.typeID) == nil, "both nodes in one step")
        #expect(app.document.canUndo == false)
        #expect(app.sketch == nil, "undoing the sketch's node leaves sketch mode")
    }

    @Test func theEditorTakesTheNodesOwnPlaneOnceItEvaluates() async throws {
        let (app, _) = await open()
        try chooseNewSketch(app, on: FaceID(1))
        // Nothing draws the new chain yet, so it isn't evaluated; previewing the selected Sketch evaluates it and the plane.
        app.previewMode = .selectedNode
        await app.settle()
        let planeNode = try #require(node(app, PlaneFromFaceNode.typeID))
        let result = try #require(app.document.results[planeNode.id])
        #expect(result.state.isSuccess)
        guard case .plane(let evaluated)? = result.outputs?["plane"]?.items.first else {
            Issue.record("no plane output")
            return
        }
        #expect(app.sketch?.editor.plane == evaluated, "the plane computed up front is the one the node makes")
        let sketchNode = try #require(node(app, SketchNode.typeID))
        #expect(app.document.results[sketchNode.id]?.state.isSuccess == true, "the new sketch evaluates on the wired plane")
    }

    /// Nothing downstream draws the new sketch, so its Plane from Face never evaluates; "Edit sketch" later still opens it,
    /// on the plane worked out from the face of the solid that did evaluate.
    @Test func theSketchOpensAgainBeforeAnythingDrawsIt() async throws {
        let (app, _) = await open()
        try chooseNewSketch(app, on: FaceID(1))
        let sketchNode = try #require(node(app, SketchNode.typeID))
        app.finishSketch()
        await app.settle()
        #expect(app.document.results[sketchNode.id] == nil, "never evaluated: it feeds nothing")
        app.beginSketch(for: sketchNode.id)
        #expect(app.alert == nil && app.sketch?.node == sketchNode.id)
        #expect(app.sketch?.editor.plane == .xy)
    }

    @Test func aFaceWithNoPlaneIsRefusedInWordsAndChangesNothing() async throws {
        let (app, _) = await open()
        let pick = try #require(app.viewport.items[0].solid.topology.facePick(for: FaceID(2)))
        app.newSketchOnFace(ViewportFaceRef(solidIndex: 0, face: FaceID(2)), pick)
        guard case .problem(let problem)? = app.alert else {
            Issue.record("no alert")
            return
        }
        #expect(problem.title == "No sketch was made" && problem.message.contains("flat"))
        #expect(app.sketch == nil && app.document.canUndo == false)
    }

    @Test func aFaceOfASolidThatIsGoneChangesNothing() async throws {
        let (app, _) = await open()
        let pick = try #require(app.viewport.items[0].solid.topology.facePick(for: FaceID(1)))
        app.newSketchOnFace(ViewportFaceRef(solidIndex: 9, face: FaceID(1)), pick)
        #expect(app.alert == nil && app.sketch == nil && app.document.canUndo == false)
    }

    @Test func whileASketchIsOpenNothingStarts() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        await app.viewport.waitForMeshes()
        let pick = try #require(app.viewport.items[0].solid.topology.facePick(for: FaceID(1)))
        let session = app.sketch
        app.newSketchOnFace(ViewportFaceRef(solidIndex: 0, face: FaceID(1)), pick)
        #expect(app.sketch === session && app.document.canUndo == false)
    }
}
```

- [ ] **Step 2: Run the tests; they don't compile**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: errors for `PlaneFromFaceNode.plane(of:)` and `AppModel.newSketchOnFace`.

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorNodes/Values/PlaneFromFaceNode.swift`:

```swift
        return NodeOutputs(["plane": .plane(FacePlane.plane(origin: face.centroid, normal: normal))], warnings: warnings)
    }
}
```

with:

```swift
        return NodeOutputs(["plane": .plane(FacePlane.plane(origin: face.centroid, normal: normal))], warnings: warnings)
    }

    /// The plane `evaluate` puts on a flat face that has a normal (its centroid and `FacePlane`'s axes); `nil` for any
    /// other face. The sketch editor opens a new sketch on it before this node has run. (`evaluate` is left as it is, so
    /// the naming-face-picks track's edits to it merge; `NewSketchOnFaceTests` pins that the two agree.)
    public static func plane(of face: FaceInfo) -> Plane? {
        guard face.kind == .plane, let normal = face.normal?.normalized else { return nil }
        return FacePlane.plane(origin: face.centroid, normal: normal)
    }
}
```

**Modify** `Sources/CreatorApp/AppModel+Sketch.swift`:

```swift
    public func beginSketch(for id: NodeID) {
```

with:

```swift
    public func beginSketch(for id: NodeID, plane known: Plane? = nil) {
```

**Modify** `Sources/CreatorApp/AppModel+Sketch.swift`:

```swift
        guard let plane = sketchPlane(of: node, stored) else {
```

with:

```swift
        // `known`: the plane of a sketch whose wired source hasn't evaluated yet (New Sketch on Face).
        guard let plane = known ?? sketchPlane(of: node, stored) else {
```

**Modify** `Sources/CreatorApp/AppModel+Sketch.swift`:

```swift
            guard let link = document.graph.incomingLink(to: Endpoint(node: node.id, socket: "plane")),
                  let result = document.results[link.from.node], result.state.isSuccess,
                  case .plane(let plane)? = result.outputs?[link.from.socket]?.items.first else {
                return nil
            }
            return plane
        }
    }
```

with:

```swift
            guard let link = document.graph.incomingLink(to: Endpoint(node: node.id, socket: "plane")) else { return nil }
            if let result = document.results[link.from.node], result.state.isSuccess,
               case .plane(let plane)? = result.outputs?[link.from.socket]?.items.first {
                return plane
            }
            return unevaluatedFacePlane(of: link.from.node)
        }
    }

    /// The plane a Plane from Face makes, worked out from its picked face when the node itself hasn't evaluated: nothing
    /// downstream of a new sketch draws it yet. It needs the node's solid to have a result; `nil` otherwise.
    private func unevaluatedFacePlane(of id: NodeID) -> Plane? {
        guard let node = document.graph.nodes[id], node.typeID == PlaneFromFaceNode.typeID,
              case .facePick(let pick)? = node.inputValues[NodeSetting.face],
              let source = document.graph.incomingLink(to: Endpoint(node: id, socket: "solid"))?.from,
              let solid = solid(at: source), let face = solid.topology.faces(matching: pick).first else { return nil }
        return PlaneFromFaceNode.plane(of: face)
    }
```

**Modify** `Sources/CreatorApp/AppModel+Viewport.swift`:

```swift
        viewport.events.showProducingNode = { events()?.showProducingNode($0) }
```

with:

```swift
        viewport.events.showProducingNode = { events()?.showProducingNode($0) }
        viewport.events.newSketchOnFace = { face, pick in events()?.newSketchOnFace(face, pick) }
```

**Create** `Sources/CreatorApp/AppModel+NewSketch.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorViewport

extension AppModel {
    /// "New Sketch on Face" (sketcher spec §8): a Plane from Face on the face's solid and a Sketch drawn on its plane, as one
    /// undo step, placed beside the node that made the solid; then the sketch opens on the plane computed from the face now (the
    /// new Plane from Face hasn't evaluated; `refreshSketch` takes the node's own plane once it has). A face that isn't flat is
    /// said in words, a face of a solid that is gone does nothing, and nothing starts while a sketch is open.
    func newSketchOnFace(_ ref: ViewportFaceRef, _ pick: FacePick) {
        guard sketch == nil, viewport.items.indices.contains(ref.solidIndex) else { return }
        let solid = viewport.items[ref.solidIndex].solid
        guard let face = solid.topology.face(ref.face), let plane = PlaneFromFaceNode.plane(of: face) else {
            alert = .problem(AppProblem("No sketch was made", "Only a flat face can hold a sketch."))
            return
        }
        guard let source = producer(of: solid) else {
            alert = .problem(AppProblem("No sketch was made", "The node that made this solid can't be found."))
            return
        }
        let from = document.graph.nodes[source.node]?.position ?? .zero
        var planeNode = registry.makeNode(PlaneFromFaceNode.typeID, at: from + Vector2(240, 140))
        planeNode.inputValues[NodeSetting.face] = .facePick(pick)
        var sketchNode = registry.makeNode(SketchNode.typeID, at: from + Vector2(480, 140))
        sketchNode.inputValues[NodeSetting.sketch] = .sketch(Sketch(plane: .wired))
        let commands: [GraphCommand] = [
            .addNode(planeNode), .addNode(sketchNode),
            .connect(Link(from: source, to: Endpoint(node: planeNode.id, socket: "solid"))),
            .connect(Link(from: Endpoint(node: planeNode.id, socket: "plane"), to: Endpoint(node: sketchNode.id, socket: "plane"))),
        ]
        do {
            try document.perform(.batch(commands))
        } catch {
            alert = .problem(AppProblem("No sketch was made", error.message))
            return
        }
        editor.selection = [sketchNode.id]
        beginSketch(for: sketchNode.id, plane: plane)
    }
}
```

- [ ] **Step 4: Run the tests and the full-suite check**

Run: `swift test --filter NewSketchOnFaceTests` and `swift test --filter FacePlaneTests` — Expected: all pass.
Run the **full-suite check** — Expected: exit 0, `0`, `11`, total **master + 85** (1728). No new warnings; lint clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/CreatorApp Sources/CreatorNodes Tests/CreatorAppTests Tests/CreatorNodesTests
git commit -m "feat(app): New Sketch on Face inserts Plane from Face and a Sketch and opens it"
```

### Task 11: The record: gap S5-c, the spec's Errata (S5c), human checks, CLAUDE.md, the roadmap and the handoff

Documentation only; nothing to run first. Whichever track merges second re-applies its lines on the other's (every doc here is shared; see "Files shared with other tracks").

**Files:**
- Modify: `docs/metalui-gaps.md`, `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md`, `docs/verification/human-checks.md`, `CLAUDE.md`, `docs/superpowers/roadmap.md`, `docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md`

- [ ] **Step 1: Log gap S5-c**

**Modify** `docs/metalui-gaps.md`:

```markdown
| S5-b | No click count on a drag's value (canvas double click) | C16 (with GI-a) | ⏳ reported 2026-10-09 |
```

with:

```markdown
| S5-b | No click count on a drag's value (canvas double click) | C16 (with GI-a) | ⏳ reported 2026-10-09 |
| S5-c | A `MetalView` draw can't draw text (world-anchored labels) | MetalUI session (with M4-b) | ⏳ reported 2026-10-09, sent to the MetalUI session |
```

**Modify** `docs/metalui-gaps.md`:

```markdown
  checked in. Stopgap: cold frames, labelled as an upper bound. Wanted, as one request with M6-e: a public headless
  window (or a frame renderer that keeps its caches across frames) that a client can drive with input and time,
  including the display link's pacing.
```

with:

```markdown
  checked in. Stopgap: cold frames, labelled as an upper bound. Wanted, as one request with M6-e: a public headless
  window (or a frame renderer that keeps its caches across frames) that a client can drive with input and time,
  including the display link's pacing.

## Hit by the sketch editor (S5c), 2026-10-09

- **S5-c. A `MetalView` draw can't draw text, so labels anchored in the 3D scene are element-tree text, rebuilt on every
  camera change.** Sketcher spec §8: a sketch's dimension values are shown in the view, at the dimension
  (`ViewportOverlay.labels`, drawn from `ViewportModel.overlayLabels()`). They follow the camera (a pan, a zoom, the Look
  At onto the plane) and a sketch has dozens. MetalUI draws text only as elements in the tree, never inside a `MetalView`'s
  draw (`MetalDrawContext` offers the target, the command buffer, `clear(…)` and the scale factor, and no text), so
  `ViewportView` places one `ProposalText` per label from a function that reads the pose: the tree is rebuilt on every
  camera change (PERF-b's cost), and a camera animation doesn't rebuild it (M4-b), so the labels are hidden for the 250 ms
  Look At that opens a sketch. A text box's size can't be asked either, so the box is computed from the text (7 points a
  character, `PlacedLabel.size(of:)`, as the S5a readout chip is). Stopgap: exactly that, which is how the handle values
  (`handleLabels()`) and the triad's axis names are drawn. Wanted: text drawn into a `MetalView` pass, such as a
  `MetalDrawContext.drawText(_:at:style:)` positioned in the view's points and batched with the frame's glyph atlas, so
  scene-anchored text moves with the frame it is drawn in, needs no tree rebuild and shows during animations; and a way
  to measure a string from a component. M4-b (a redraw during an animation) would remove the hiding but not the
  rebuilds. Human check S5c-6 records it. Not measured: a sketch with 20 or more labels pays the rebuild for each on every
  camera change; S5c-6 is where that is looked at, and the labels are not capped or culled by count (a silent cap would hide
  dimensions). Sent to the MetalUI session (the standing rule: every MetalUI gap goes to that session to implement); the
  repository is never edited from here.
```

- [ ] **Step 2: Errata (S5c) in the sketcher spec**

**Modify** `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md`:

```markdown
  C16). A double click on a node with an "Edit sketch" inspector button presses it. While a sketch is open, a double
  click (or any .editSketch request) changes nothing: the stroke, the selection and the camera stay.
```

with:

```markdown
  C16). A double click on a node with an "Edit sketch" inspector button presses it. While a sketch is open, a double
  click (or any .editSketch request) changes nothing: the stroke, the selection and the camera stay.

## Errata (S5c)

- §8's S5c (plan `2026-10-09-sketcher-s5c.md`) has Project, "New sketch on face", dimension labels in the view and the region
  fill; `CreatorSketchEditor` now depends on `CreatorKernel` (§2), for `EdgePick`.
- §8's Project (P) is a sketch-mode tool that declines the plane click, so the viewport's ID-buffer pick reaches the tool
  (`ViewportTool.clickedModel`): nothing turns the camera and no menu opens. An edge pick projects that edge; a face pick
  projects each of its edges. Each edge becomes a fixed `.projected` entity whose `reference` is the first unused
  `edgeN`; the commit stores `projection.<reference>` = `.edgePicks([pick])` and wires the solid's producer into
  `references` (when nothing is wired there) in the same batch as the sketch: one undo step. `references` takes one wire, so a
  sketch projects from one part: a pick on another part, or on a part made from this sketch (a cycle), is refused in words,
  as are edges S4 can't project (perpendicular, oblique, unsupported) and edges already projected. Deleting a projected curve
  clears its stored pick (its wire stays).
- §8's "New sketch on face" is the face menu's item, offered on a flat face that has a normal and only outside sketch mode
  (Errata (S5a)). One batch adds Plane from Face (`face` = the picked face's `facePick`, `solid` wired from the producer
  of the face's solid) and a Sketch (plane `.wired`, wired from the Plane from Face), beside the producer, and the sketch
  opens at once on the plane worked out from the face by the node's own function (`PlaneFromFaceNode.plane(of:)`); the
  editor takes the evaluated plane once there is one, and "Edit sketch" works the plane out the same way while the chain
  feeds no Output and so never evaluates. The Sketch's `references` stays unwired until the first Project.
- §8's dimension labels are read-only text at the dimension: a length at the line's middle, a radius at the arc's middle,
  a diameter at the circle's upper right, a distance between its two points (or a point and its foot on the line), an
  angle at the lines' corner; each stands off its geometry along its normal (or the bisector, or outwards) by 16 points on
  screen. A driving dimension reads its value ("60 mm", "45°"; an exposed one "width = 60 mm"), a reference dimension its
  measurement in brackets in the construction colour, a dimension in a conflict is red. §8 puts the editable name and value
  fields in the inspector and says nothing of editing in the view, so the labels don't take the pointer. They are
  element-tree text (docs/metalui-gaps.md S5-c) and are hidden while the camera animates.
- §8's "Output regions: faint green fill" is one filled triangle set per region `SketchRegions.find` returns (holes left
  empty, an island in a hole its own region), in the Sketch node's header green at 18% opacity, drawn under the curves and
  over the model, and never in the ID pass, so a click goes through it.
- Project stays the active tool after a click (a repeated Project; Select is one key away). Nothing highlights the edge under
  the pointer while the Project tool aims: the viewport highlights only a hovered face (`FrameItem.hoveredFace`), so an edge
  click gives no feedback until the line appears (a face click shows the face lit, though it projects all its edges). A
  hovered-edge highlight is a viewport change (a picked edge in the frame, a highlight in the edge pipeline) that the
  viewport-final-edges track is rewriting; it is not in S5c.
- A projected edge is real, not construction, geometry: it closes regions and gets the faint fill like a drawn line.
- The new Plane from Face and Sketch are placed 240 and 480 points right of, and 140 below, the producer of the picked
  face's solid. They may overlap nodes already there; moving them is the user's, and placing clear of nodes is a later nicety.
  The new Sketch feeds nothing, so nothing previews until it is wired on (Errata (S4): a Sketch's profiles go into an
  Extrude).
- The S5b review's follow-ups: a circle's radius click and a centre arc's end click are only sizes, so no curve snaps them
  (they snap to an existing point's distance only); the hover scans the curves once and only for tools that place points.
```

- [ ] **Step 3: Human checks**

**Modify** `docs/verification/human-checks.md`:

```markdown
- [ ] **MS-8 Draw order.** Overlap three nodes, select the two at the back: they draw above the third, and a click
  where all three overlap selects the topmost drawn one. Docked at the bottom too. Pinned:
  `selectedNodesDrawLastAndAreHitFirst`. **Observed:**
```

with:

```markdown
- [ ] **MS-8 Draw order.** Overlap three nodes, select the two at the back: they draw above the third, and a click
  where all three overlap selects the topmost drawn one. Docked at the bottom too. Pinned:
  `selectedNodesDrawLastAndAreHitFirst`. **Observed:**

## Group S5c — the sketch editor's links to the model and the viewport (S5c)

**Status: NOT RUN.** Run `swift run MetalCreatorApp`. Add a Rectangle wired into an Extrude (20 mm) into an Output, so
there is a box, then a Sketch (select it, "Edit sketch").

- [ ] **S5c-1 Project an edge.** In a sketch on the XY plane, press P ("Project ✓") and click one of the box's top edges: a
  purple line appears on the plane (nothing highlights the edge under the pointer while you aim: only faces highlight, a
  known gap, see Errata (S5c); a click takes the edge whose pixels it lands on). In the graph, the Sketch node now
  has a wire into `references` from the box's Extrude. The tool stays on Project after the click (click a second edge without pressing P again). One ⌘Z removes the line, the wire and the stored pick together. The purple line is real geometry: draw a closed shape that uses it and the fill appears. Draw a line ending on the purple line: "Point on" appears and the point stays on it
  when you drag. Change the Rectangle's width in the graph and the purple line follows. Pinned: `ProjectToolTests`,
  `SketchProjectTests`. **Observed:**
- [ ] **S5c-2 Project a face, and what can't be projected.** Press P and click the box's top face: all four of its edges
  project. Click a vertical edge: the inspector says "That edge can't be projected: it is perpendicular to the sketch
  plane, so it projects to a point." and nothing changes. Click a side face: only what projects appears, and the inspector
  says what was left out. Click the same edge twice: "That edge is already projected." Pinned: `SketchProjectTests`.
  **Observed:**
- [ ] **S5c-3 One part per sketch.** Add a second box, project an edge of the first in the sketch, then an edge of the second:
  "This sketch already projects from another part. Project from one part per sketch." Wire the Sketch's profiles into
  the first box's Extrude and try to project one of that box's edges: "That part is made from this sketch, so its edges
  can't be projected into it." Nothing is stored either time. Pinned: `SketchProjectTests`. **Observed:**
- [ ] **S5c-4 New sketch on face.** Finish the sketch. Right-click the box's top face: the menu reads Look At, Select Edges
  of Face, New Sketch on Face, Show Producing Node. Choose New Sketch on Face: a Plane from Face and a Sketch appear in the
  graph beside the box's Extrude, wired; the sketch is open, the view looks straight at the top face, and drawing works.
  One ⌘Z removes both nodes and leaves sketch mode. A side face of the box offers the same item; a cylinder's curved face
  does not. While a sketch is open, the right-click menu is empty. Nothing previews yet: the new Sketch feeds nothing, so
  wire its `profiles` into an Extrude to see a solid (the nodes are placed 240 and 480 points to the right of the producer
  and a little below, and may overlap nodes already there). Finish the new sketch without wiring it on, then press
  "Edit sketch" on it: it opens again. Pinned: `NewSketchOnFaceTests`. **Observed:**
- [ ] **S5c-5 Dimension labels.** Draw a rectangle and dimension it (D, then each side): each dimension shows a small glass
  label with its value ("60 mm") standing off its line. A circle's diameter and an arc's radius label sit on the curve's
  upper right and middle; an angle between two lines sits at their corner. Expose a dimension ("Expose as input"): its label
  reads "width = 60 mm". Make one a reference: "(40 mm)" in grey. Add a conflicting dimension: the label is red. The
  labels follow pans and zooms, and typing a new value in the inspector changes the label. Clicking a label picks what is
  under it. Pinned: `DimensionLabelTests`, `OverlayLabelTests`. **Observed:**
- [ ] **S5c-6 Labels and the camera** (gap S5-c). Open a sketch with dimensions: the labels appear after the camera has
  turned onto the plane, not during the turn. Pan and zoom: they stay on their dimensions with no lag you can see, and
  stay legible in the other themes. Note whether panning a sketch with many labels (20 or more) stays smooth. **Observed:**
- [ ] **S5c-7 Region fill.** Draw a closed shape: a faint green fill appears inside it, under the lines and points. A shape
  with a hole (a circle inside a rectangle) is filled around the hole; a small circle inside the hole is filled again.
  Open the shape (delete a line): the fill goes. Construction geometry is never filled. Drag a corner: the fill follows live.
  The fill never blocks a click: clicking inside it selects what is under the pointer, or clears the selection. Pinned:
  `RegionFillTests`, `RegionTriangulatorTests`, `OffscreenRenderTests.anOverlayFillTintsThePixelsItCoversAndNoOthers`.
  **Observed:**
- [ ] **S5c-8 Review follow-ups.** With Circle, click a centre, then move the pointer over an existing line while sizing the
  circle: the rubber band doesn't jump onto the line and no chip appears. Click a centre on a line: "Point on" appears and
  the centre stays on the line. Pinned: `SnapAndTangentCoverageTests`. **Observed:**
```

- [ ] **Step 4: CLAUDE.md, the roadmap and the handoff**

**Modify** `CLAUDE.md`:

```markdown
its human checks (group S5b) are pending; S5c (Project, New sketch on face, dimension labels in the view, region fill) is next.
```

with:

```markdown
its human checks (group S5b) are pending; S5c (Project, New sketch on face, dimension labels in the view, region fill) code is done; its human checks (group S5c) are pending.
```

**Modify** `CLAUDE.md`:

```markdown
    `lookAt(_ plane:framing:)` faces a plane, orthographic.
```

with:

```markdown
    `lookAt(_ plane:framing:)` faces a plane, orthographic. A tool also takes the face or edge under a click it declined
    (`clickedModel`: the sketch editor's Project). `ViewportOverlay` also carries `fills` (`OverlayFill`: world triangles
    in the `.region` tint, one blended pipeline drawn under the lines, never in the ID pass) and `labels` (`OverlayLabel`:
    text anchored in world space, placed by `overlayLabels()` and drawn as MetalUI text over the surface, hidden while
    the camera animates: gap S5-c). The face menu adds New Sketch on Face (`ViewportEvents.newSketchOnFace`) on a flat
    face that has a normal, outside sketch mode.
```

**Modify** `CLAUDE.md`:

```markdown
  both, never a shared point. Graph-free: every edit is
  a `SketchCommit` (the whole sketch, solved and remembered) through `events.committed`, which the host stores.
  Depends on CreatorSketch, CreatorViewport, CreatorGeometry, CreatorStyle and MetalUI only. Its keys are toolbar
  button shortcuts (L, A (again: 3-point arc), C, D, T, X, ⌫, ⌦, ⏎, Esc; ⌦ and Esc are hidden buttons; Fillet has no
```

with:

```markdown
  both, never a shared point. Project (P) declines the plane click and takes the viewport's pick: the host resolves it
  (`events.projection`) into `ProjectionCandidate`s, each becomes a fixed `.projected` entity with a reference `edgeN`, and
  the commit's `projections` carry the picks to store. The overlay also carries a fill per closed region
  (`RegionTriangulator`, found again only when the sketch changes) and a read-only label per dimension
  (`SketchDimensionLabels`). Graph-free: every edit is
  a `SketchCommit` (the whole sketch, solved and remembered) through `events.committed`, which the host stores.
  Depends on CreatorSketch, CreatorViewport, CreatorKernel (Project's `EdgePick`), CreatorGeometry, CreatorStyle and
  MetalUI only. Its keys are toolbar
  button shortcuts (L, A (again: 3-point arc), C, D, T, P, X, ⌫, ⌦, ⏎, Esc; ⌦ and Esc are hidden buttons; Fillet has no
```

**Modify** `CLAUDE.md`:

```markdown
  and a renamed exposed dimension's wire moved (dropped when it stops being exposed).
```

with:

```markdown
  and a renamed exposed dimension's wire moved (dropped when it stops being exposed). A Project commit also stores each pick
  under `NodeSetting.projection(reference)` and wires the solid's producer into `references` (one wire: `resolveProjection`
  refuses another part, or one made from the sketch); a removed projection clears its pick. The face menu's New Sketch on
  Face (`newSketchOnFace`) inserts Plane from Face and a wired Sketch as one batch and opens the sketch on
  `PlaneFromFaceNode.plane(of:)`.
```

**Modify** `docs/superpowers/roadmap.md`:

```markdown
S5c (Project, New sketch on face, dimension labels in the view, region fill) ⏳ |
```

with:

```markdown
S5c (Project, New sketch on face, dimension labels in the view, region fill; plan `2026-10-09-sketcher-s5c.md`) ✅ code done, human checks S5c pending |
```

**Modify** `docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md`:

```markdown
- Pattern construction (connectors, spokes) is still drawn as any construction; telling it apart needs a marker in
  the sketch model (CreatorSketch) or the editor remembering what a pattern added.
```

with:

```markdown
- Pattern construction (connectors, spokes) is still drawn as any construction; telling it apart needs a marker in
  the sketch model (CreatorSketch) or the editor remembering what a pattern added.

## S5c → later (plan `docs/superpowers/plans/2026-10-09-sketcher-s5c.md`)
- Done in S5c (sketcher spec Errata (S5c)): Project (an edge or a face, over `ViewportTool.clickedModel`), New sketch on face,
  read-only dimension labels in the view (gap S5-c), the region fill, and the S5b review's follow-ups.
- Not done: ⌘ to suppress inference and ⇧-click to extend the selection (gaps S5-a and GI-a); editing a dimension in the
  view (the spec puts the fields in the inspector); labels that avoid each other (two dimensions near one spot overlap);
  a sketch that projects from more than one part (`references` takes one wire; several would need a list of wires or a
  merge node); a projection that follows a re-projected edge it already holds (a re-projection after the model moved
  makes a second entity only while the wired solid has no result yet, because then the duplicate check falls back to the
  stored curve; once the solid evaluates, the editor shows the refreshed curve (`refreshedProjections`) and compares with it);
  hover feedback for the edge under the Project tool (only faces highlight); framing a new sketch on the
  face itself (it frames 100 mm round the face's centroid; the viewport knows the face's bounds and the app doesn't);
  the 150 ms debounce while typing; pattern construction told apart from the user's own.
```

- [ ] **Step 5: Send gap S5-c to the MetalUI session**

The standing rule is that every MetalUI fix or feature request goes to the MetalUI session to implement, never worked around
silently and never made from this repository. Find the session with `ListAgents` and `SendMessage` it (the MetalUI session
is the agent whose worktree is `../MetalUI`) this request, so the gap entry's "sent to the MetalUI session" is true:

```text
MetalCreator gap S5-c (docs/metalui-gaps.md in the MetalCreator repo): a MetalView draw can't draw text. Wanted: a
MetalDrawContext.drawText(_ text: String, at: point in the view's points, style:) that draws into the view's own pass,
batched with the frame's glyph atlas, so scene-anchored text moves with the frame it is drawn in, needs no element-tree
rebuild on camera changes and shows during animations (M4-b). And a way to measure a string from a component (its size
for a style), which today is guessed at 7 points a character. Stopgap in MetalCreator: one ProposalText per label from a
function reading the camera pose, as handleLabels() does. Not urgent; it removes the label rebuild and the hiding during Look At.
```

If no MetalUI session is listed, leave the entry's status as "reported" and say so in the task's report. Nothing is committed for this step.

- [ ] **Step 6: The full-suite check and commit**

Run the **full-suite check** — Expected: exit 0, `0`, `11`, total **master + 85** (1728), unchanged by this task. `swiftlint lint --strict --quiet` prints nothing.

```bash
git add docs CLAUDE.md
git commit -m "docs(sketch): S5c errata, gap S5-c, human checks S5c, CLAUDE.md, roadmap and handoff"
```

## User decisions

Product behaviour the spec leaves open. Each is written into the plan as the recommended default; changing one means the task named.

1. **Project on a face.** (a) Project every edge of the picked face, one fixed curve each, in one undo step **(recommended: one click gives a face's outline, and the extras are one Delete away)**; (b) only an edge click projects, a face click says "Click an edge"; (c) only the face's outer outline, not its holes' edges. Tasks 8 and 9 (`resolveProjection`).
2. **One part per sketch.** The Sketch node's `references` input takes one wire, so a sketch can project from one part. (a) Refuse a pick on another part, in words, nothing changed **(recommended: no graph change, nothing lost)**; (b) replace the wire and suspend the projections made from the old part (destructive: they turn red); (c) let `references` take several wires, a graph-engine change (multi-input sockets) outside S5c. Task 9 (`referencesProblem`).
3. **Dimension labels in the view: read or edit.** (a) Read-only; the inspector edits the name and value, as §8 says **(recommended)**; (b) click a label to edit its value in place: it needs a text field at a point that moves with the camera, hits the focus gaps (M5-g, M5-h) and S5-c, and fights clicks that should pick the geometry under the label. Tasks 4 and 7.
4. **What a label reads.** (a) The value ("60 mm", "45°"); an exposed dimension "name = value"; a reference dimension "(value)" in the construction colour; a conflict red **(recommended)**; (b) always "name = value" ("d1 = 60 mm", Fusion-like for named dimensions but noisy for auto names); (c) the value alone. Task 7 (`SketchDimensionLabels.labels`).
5. **New Sketch on Face: wiring and framing.** (a) As the spec has it: Plane from Face and a Sketch, `references` left unwired until the first Project, the view framed 100 mm round the face's centre **(recommended)**; (b) also wire the face's solid into `references` at once, so Project works without a wire step (it also makes the new sketch depend on the part before it projects anything); (c) frame the face's own size (the viewport knows the face's bounds, the app doesn't; it needs a bounds query on the viewport). Task 10.
6. **How strong the region fill is.** (a) Every closed region, the Sketch node's green at 18% **(recommended)**; (b) also hide it while the sketch is over-constrained or failed; (c) a dedicated theme role for the fill (a new `ThemeRole`, so a new `.mctheme` key). Tasks 5 and 6.
7. **Deleting a projected curve.** (a) Its stored pick goes with it, the `references` wire stays **(recommended)**; (b) the wire goes too when the last projection does (a later Project wires it again, but a wire the user made is lost). Task 9 (`projectionCommands`).
8. **Feedback while aiming the Project tool.** The viewport highlights a hovered face but has no hovered-edge rendering, so nothing shows which edge a click will take. (a) None; the check says so and the gap is recorded in the Errata and the handoff **(recommended: a hovered-edge highlight touches the edge pipeline and renderer that viewport-final-edges is rewriting, and the line appears at once on click, one ⌘Z away)**; (b) add a hovered-edge highlight to the viewport as an extra task (an edge under the pointer in the frame, a highlight in the edge draw). Tasks 8 and 11 (human check S5c-1).
9. **Project stays active after a click.** (a) It stays, so several edges can be clicked in a row **(recommended: the other tools stay too)**; (b) it returns to Select after one click. Task 8 (`project`), written into the Errata.
10. **Where the new nodes of New Sketch on Face go.** (a) 240 and 480 points right of and 140 below the producer of the picked face's solid, which may overlap nodes already there **(recommended: stated in the Errata and the check; moving them is the user's)**; (b) search for clear space. Task 10 (`newSketchOnFace`).
11. **What a new sketch on a face shows.** The new Sketch feeds nothing, so nothing previews until it is wired on. (a) As the spec has it, stated in check S5c-4 **(recommended, with 5(a))**; (b) also add an Extrude and an Output after it (more nodes the user did not ask for). Task 10.
12. **Projected edges are real geometry.** (a) They close regions and get the fill, like drawn lines **(recommended: the sketch model already does this; Project is for building on the model's outline)**; (b) projected edges are construction-like and never close a region (a change in `SketchRegions`, outside S5c). Tasks 6 and 8.

## Self-review

- **Spec coverage.** §8 "Model edges for Project use M4's ID-buffer picking" and key P → Tasks 2, 8, 9 (pick routed through the tool, edge or face, reference written, solid wired, kept resolved: the node re-resolves on every evaluation and the editor shows the same refresh); §8 "the face context menu's New sketch on face" → Tasks 3 and 10 (§7: Plane from Face "wires into a Sketch", `.wired`); §8's dimensions in the view (S5b Errata's "dimension labels in the view") → Tasks 4 and 7, read-only because §8 puts the editable fields in the inspector; §8 "Output regions: faint green fill" → Tasks 5 and 6 (§5's regions, holes empty); §8 "Each command is one undo step" → Project's sketch, picks and wire are one batch (Task 9), New sketch on face's two nodes and two wires are one batch (Task 10); §2's `CreatorSketchEditor` → `CreatorKernel` (Task 8); the camera lock (Errata (S5a)) → Project is a tool and New sketch on face is outside sketch mode; the S5b review's four follow-ups → Task 1 (the circle radius and centre arc end snap, the single hover scan, the listed non-command tools, the four tests); the gap rule → S5-c logged with its stopgap (Tasks 4 and 11); human checks → group S5c (Task 11).
- **Placeholder scan.** Every step carries its code or its exact command; no "TBD", "TODO", "similar to Task N" or undefined name remains (grepped before saving). Every Modify block's old text matched exactly once when applied.
- **Type consistency.** Checked by applying every block in order (below): `ViewportTool.clickedModel` (Task 2) is `SketchEditorModel`'s in Task 8; `ViewportOverlay(lines:points:fills:labels:gridPlane:)` is built in two steps (Task 4 adds `labels`, Task 5 adds `fills`, both with defaults, so S5a's call sites compile); `OverlayTint.region` (Task 5) is handled by `ViewportPalette.color`, `ViewportModel.textColor(for:)` and, through the default, the editor; `SketchOverlayBuilder.overlay(…, fills:, labels:)` get their defaults in Tasks 6 and 7; `SketchCommit.projections: [ProjectionWrite]` (Task 8) is read by `AppModel.storeSketch` (Task 9); `SketchStore.Projection`/`referencesSocket` (Task 9) are used by `AppModel+Project` in the same task; `PlaneFromFaceNode.plane(of:)` (Task 10) is used by `newSketchOnFace` and `sketchPlane`; `beginSketch(for:plane:)` keeps its old call sites compiling through the default.
- **Review Focus.** Each of the five lines has its test in its owning task (Tasks 6, 9, 9, 9/8, 10).
- **Deferred S5b items.** (1) The circle-radius and arc-end clicks snap onto no curve: `DrawState.snapsToCurves` (Task 1), pinned by two tests that fail without it (the arc one clicks off the arc's axis, so snapping would turn the ray); (2) the missing tests: a circle centre, a 3-point arc's start and end on a curve, tangent from an arc's start, the 3-point end on the start's point (Task 1); (3) the hover computes its anchor only when the tool places points (Task 1); (4) `modify`'s `default: break` lists the seven tools that are not commands, and `.project` joins them in Task 8.

## Verification record (how this plan was checked)

Every code block above was applied task by task, in order, by a script that runs each **Create**, **Replace the whole of** and **Modify** block (each Modify's old text had to match exactly once; `--max-step 1` applies only the Step 1 tests), to a scratch copy of the worktree at master **4e4be6e** (`git archive`, in the session's scratchpad) beside a `MetalUI` symlink to `/Users/maxburger/Developer/MetalUI` (2155f1e when the plan was first checked; it also builds at 70e9389). After each task: `swift build --build-tests` printed no warning or error beyond master's `ContextMenuTests.swift:140` one (which prints when that file recompiles); `swift test` exited 0 with 11 "Test run with" lines and no "recorded an issue" or "failed after" line; `swiftlint lint --strict --quiet` printed nothing. The red step (Step 2) was run from the previous task's tree with only Step 1 applied for Tasks 1 (two tests fail), 2 (two fail), 3 to 5 and 8 to 10 (compile errors, as each step says), 6 (compile errors) and 7 (all nine fail). The baseline master run printed 1643 tests in 11 runs.

Revised after review (this revision): the region fill's clipper was replaced and re-run on a 2 × 2 to 8 × 8 grid of aligned square holes, a 3 × 3 to 6 × 6 grid of circles, 200 random lattices of rectangles and the plan's own tests (all exact; the old clipper failed the 3 × 3, 4 × 4 and 5 × 5 grids and filled over holes); the centre-arc-end test was mutated (the arc half of `placeArcPoint` left unfixed) and fails alone; the storeSketch test was mutated (without `refreshSketch()`) and fails; the dependency table was checked by applying each task to master alone and after its prerequisites (5 alone, 7 alone and 8 without 1 fail to apply; 1, 2, 3, 4, 9 and 10 apply alone; Tasks 1, 2, 3 and 4 each build alone, and 3 with 10 builds without 9). The whole plan was then re-run as 11 tasks in order, with the totals below. Test totals (the sum of the "Test run with N tests" lines):

| After task | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Tests | 1650 | 1654 | 1658 | 1665 | 1670 | 1687 | 1696 | 1706 | 1720 | 1728 | 1728 |
| Over master | +7 | +11 | +15 | +22 | +27 | +44 | +53 | +63 | +77 | +85 | +85 |

A parameterised test counts once. The two GPU tests (`OffscreenRenderTests`) need a Metal device, as the suite's other offscreen tests do; the figures above are from a machine with one.

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-09-sketcher-s5c.md`. Recommended: **subagent-driven** (a fresh implementer and reviewer per task), because the chains 5 → 6 → 7 and 2 → 8 → 9 each rely on interfaces the earlier task defines (`OverlayFill`, `OverlayLabel`, `clickedModel`, `ProjectionWrite`), Tasks 2, 5 and 9 touch files the viewport-final-edges, naming-face-picks and groups-editor tracks share (see "Files shared with other tracks"), and a mistake in the renderer or in `SketchStore` would ship a wrong picture or a wrong graph edit.
