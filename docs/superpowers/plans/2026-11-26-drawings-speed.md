# Drawings Speed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A drag step on a drawing sheet (a dimension, balloon, note, symbol or view) and a pan step cost work in proportion to what changed, not to the whole sheet.

**Architecture:** Three cuts, each with a work-count test.
1. The composer keeps each view's projected linework between composes, in a memo the editor owns.
2. The canvas draws from per-layer buckets built once per compose, each with a revision number. A view's linework and its annotations are separate layers, so a pan filters nothing, and a layer compares by revision instead of by array.
3. The app's last-good refresh ignores annotation placement, so a drag no longer restarts it on every step.

A new bench times a real editor drag.

**Tech Stack:** Swift 6.4 (strict concurrency), Swift Testing, MetalUI; `CreatorDrawing`, `CreatorDrawingEditor`, `CreatorApp`.

**Spec:** `docs/superpowers/specs/2026-11-24-drawings-design.md`. The pan and zoom target is 60 fps warm (line 222). A drag moves a view or an annotation (line 173). The backlog item comes from memory `drawings-backlog.md`: "Every drag step recomposes the whole sheet; drawing-5 / drawing-5-warm not re-run on an idle Mac". Numbers so far are in `docs/verification/performance.md:1546-1618`.

## Rulings (made by the controller, no question round)

- **R1. What the memo keeps.** It keeps each view's projected linework: `ViewLinework.strokes`, the view's `hatch` strokes and `ViewLinework.frame`.
  - The key is the `DrawingView`, its `ViewContent`, its centre, its scale, the standard and `sheet.size`. Task 1 adds whatever else `hatch` reads from the sheet, after checking.
  - Values are compared with `==`. Array and Dictionary `==` returns early on shared storage, so an unchanged `ViewContent` compares in O(1).
  - Annotations, labels, notices, marks, the frame, the title block, notes and the parts list are still composed every time. They are cheap (`drawing-3` composes 30 dimensions in 0.84 ms). Annotations also read sheet-wide context: item numbers and GD&T rules.
  - A moved view re-maps only itself.
  - Cost if wrong: a stale view. The equivalence tests guard against it.
- **R2. The memo changes nothing on paper.** `compose(…, linework: &memo)` returns a picture that is `==` to `compose(…)` without a memo, for every edit. Export, PDF, DXF and MCP keep calling `compose` without a memo.
- **R3. Layer buckets.**
  - `SheetLayers` is built in `rebuildPicture` from the flat `SheetPicture`. It holds:
    - a frame bucket (`view == nil`);
    - per view, a linework bucket (`annotation == nil`) and an annotations bucket (`annotation != nil`);
    - an index by `AnnotationID` and by `mark`, which the selection layer assembles from.
  - Each bucket carries a `revision: Int`. A bucket keeps its previous revision when its arrays are `==` to the previous bucket's, and takes the next revision otherwise.
  - `picture.strokes` stays flat and in its current order, because `hoveredStroke` and `hoverCandidate` index into it.
- **R4. Layer equality compares revisions, not arrays.** Each layer still compares its zoom, colours, style and flags as today. A layer whose content is unchanged still evaluates on a zoom step.
- **R5. The refresh key strips placement.**
  - `RefreshKey.annotations` holds each annotation with its placement fields set to a fixed value. A placement field is one that `lastGood` never reads: a dimension's offset or text position, a balloon's or note's position, a symbol's position. Task 3 lists the fields after reading `lastGood`.
  - Any field `lastGood` reads stays in the key. That includes a balloon's leader tip if it picks the part.
  - Cost if wrong: a figure that doesn't refresh after a drag. A test per annotation kind pins the choice.
- **R6. Parked, not done here.**
  - **Zoom.** Every layer rebuilds on a zoom step because widths and dashes are in screen units. This is a design question of its own. It is reopened only if the idle-Mac bench shows the zoom half of `drawing-5-warm` over 16.67 ms.
  - **The hover scan** (`SheetHitTest.line` over every view on each hover move).
  - **The rest of the host's per-step work:** whole-document `==` in `commit` and in `resync`, building `RequestKey`, and `followFacts`.
  - These go to the drawings backlog memory with their numbers.
- **R7. Benches assert no time** (project rule). Tests count work and never read a clock. Bench numbers are recorded only from an idle Mac, by the controller after merge, not by the tasks.

## Global Constraints

- Swift 6 strict concurrency. No `@unchecked Sendable` and no `nonisolated(unsafe)`. The memo is a value type passed `inout`, owned by the `@MainActor` editor model.
- `CreatorDrawing` depends on Geometry and Kernel only. `CreatorDrawingEditor` never imports CreatorGraph.
- MetalUI gaps are logged in `docs/metalui-gaps.md` and fixed in MetalUI, never worked around here.
- Tests use Swift Testing. Test hooks never block a pool thread (use `HookGate` where waiting is needed). No wall-clock asserts.
- `swiftlint lint --strict` reports zero violations. The full `swift test` prints 16 "Test run with" lines, with no "recorded an issue" and no "failed after".
- Notes go in `Sources/CreatorDrawing/CLAUDE.md` and `Sources/CreatorDrawingEditor/CLAUDE.md`, never the root `CLAUDE.md`.

## Review Focus

1. A projection landing, or a view's flag changing (hidden lines, tangent edges, scale, standard), must redraw that view at once. A stale memo or bucket revision would show old lines. Tasks 1 and 2 test each input.
2. A deleted or re-added view with the same `ViewID` must not reuse a stale entry. Task 1 drops entries for views no longer on the sheet.
3. Switching sheets must not show the other sheet's linework. The memo is keyed by `ViewID`, which is unique across sheets, but Task 1 tests a sheet switch anyway.
4. Hover and pick after a drag must still hit the right stroke, because the flat stroke indices are unchanged. Task 2 runs the existing pick tests and adds one after a drag.
5. A dimension dragged and then undone must restore the figure, and the refresh must not have been skipped for an anchor change. Task 3 tests both.

---

### Task 1: Keep each view's linework between composes

**Files:**
- Create: `Sources/CreatorDrawing/Picture/LineworkMemo.swift`
- Modify: `Sources/CreatorDrawing/Picture/SheetComposer.swift` (the per-view loop, about lines 39-52), `Sources/CreatorDrawing/Picture/SheetComposer+Marks.swift` (`hatch`, to see what of `sheet` it reads), `Sources/CreatorDrawingEditor/DrawingEditorModel.swift` (`rebuildPicture`, about line 166)
- Test: `Tests/CreatorDrawingTests/LineworkMemoTests.swift`, `Tests/CreatorDrawingEditorTests/DragWorkTests.swift`

**Interfaces:**
- Produces:
  - `public struct LineworkMemo: Sendable` with `public init()`, `public private(set) var mapped: Int` (views mapped by the last compose) and `public private(set) var reused: Int`.
  - `SheetComposer.compose(_:in:contents:facts:notices:units:remembered:linework: inout LineworkMemo) -> SheetPicture`. The existing signature stays and calls through with a throwaway memo.
  - `DrawingEditorModel.lineworkMapped: Int`, a running total for tests.

- [ ] **Step 1: Write the failing tests** in `LineworkMemoTests`. Use the composer test fixtures already in `Tests/CreatorDrawingTests`, with a sheet of three projected views and two dimensions.
  - `aSecondComposeMapsNothing`: compose twice with one memo. Expect `mapped == 0` and `reused == 3` the second time, and the pictures `==`.
  - `movingADimensionMapsNothing`: change one dimension's offset. Expect `mapped == 0`, and the picture `==` a memo-less compose of the same document.
  - `movingAViewMapsThatView`: change one view's `center`. Expect `mapped == 1`, and the picture `==` the memo-less one.
  - `eachViewInputMisses`, parameterised over: a new `ViewContent` (another projection), `showsHidden`, `showsTangent`, `scale`, the sheet's scale, the standard, `sheet.size`, and each extra input Task 1 finds `hatch` reading. Expect `mapped == 1`, or the view count for sheet-wide inputs, and equality with the memo-less picture each time.
  - `aRemovedViewLeavesTheMemo`: remove a view, then add a new view under the same `ViewID` with other content. Expect it to be mapped and the picture to be correct.
  - `anotherSheetDoesNotReuse`: compose sheet 1, then sheet 2 with the same memo. Expect sheet 2's pictures `==` the memo-less ones.
  - In `DragWorkTests` (editor): drive `primaryChanged` over ten steps dragging a dimension, following `SelectionAndMoveTests`' helpers. Expect `lineworkMapped` not to grow after the press.
- [ ] **Step 2: Run them and see them fail** (`swift test --filter CreatorDrawingTests.LineworkMemoTests`, then `--filter CreatorDrawingEditorTests.DragWorkTests`).
- [ ] **Step 3: Implement R1 and R2.**
  - The memo holds, per `ViewID`, the key inputs it was built from and the strokes and frame.
  - `compose` with a memo looks up each view, re-maps on a miss, and finally drops entries for views not on this sheet.
  - `rebuildPicture` passes the model's memo.
- [ ] **Step 4: Run both suites, the whole `CreatorDrawingTests` and `CreatorDrawingEditorTests` targets, and lint.**
- [ ] **Step 5: Notes.** In `Sources/CreatorDrawing/CLAUDE.md`, describe the memo: what it keys on, and that only the editor uses one.
- [ ] **Step 6: Commit.**

### Task 2: Layer buckets with revisions, and linework apart from annotations

**Files:**
- Create: `Sources/CreatorDrawingEditor/Views/SheetLayers.swift`
- Modify: `Sources/CreatorDrawingEditor/Views/SheetCanvas.swift` (`viewLayer`, `highlighted(in:)`, `paperStack`), the layer types `SheetFrameLayer`, `SheetViewLayer` and `SheetSelectionLayer` (find their files), and `DrawingEditorModel.swift` (`rebuildPicture` builds the layers; `layers` is stored beside `picture`)
- Test: `Tests/CreatorDrawingEditorTests/SheetCanvasSkipTests.swift`, `Tests/CreatorDrawingEditorTests/SheetLayersTests.swift`

**Interfaces:**
- Consumes: Task 1's `rebuildPicture`.
- Produces:
  - `struct SheetLayers: Sendable` with `frame: Bucket`, `linework: [ViewID: Bucket]`, `annotations: [ViewID: Bucket]`, and `func selection(annotations: Set<AnnotationID>, marks: Set<ViewID>) -> (strokes: [SheetStroke], fills: [SheetFill], texts: [SheetText])`.
  - `struct Bucket: Sendable { strokes; fills; texts; revision: Int }`.
  - `static func built(from: SheetPicture, previous: SheetLayers?) -> SheetLayers`.
  - `DrawingEditorModel.layers: SheetLayers?`.

- [ ] **Step 1: Write the failing tests.**
  - In `SheetLayersTests`:
    - `unchangedBucketsKeepTheirRevision`: rebuild after a dimension move. Every bucket but that view's annotations keeps its revision.
    - `changedBucketsTakeANewRevision`: a dimension's text change, a projection landing and a view flag change each bump exactly the buckets whose contents changed.
    - `bucketsHoldEverything`: the union of all buckets is the picture's strokes, fills and texts, as a multiset.
    - `selectionMatchesTheOldFilter`: for a few selections, `selection(…)` equals what today's `highlighted(in:)` filter returns. Copy the old filter into the test as the reference.
  - In `SheetCanvasSkipTests`:
    - `aDimensionDragEvaluatesTwoLayers`: per drag step, `contentEvaluations` counts only that view's annotation layer and the selection layer.
    - Keep `aPanSkipsEveryView`.
    - `aZoomEvaluatesEveryLayer` pins today's zoom behaviour (R6).
  - `aPickAfterADragHitsTheRightStroke`: after a drag, hover a projected edge. `hoveredStroke` names the same stroke as before the drag.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement R3 and R4.**
  - `SheetCanvas` reads buckets and stops filtering `picture`.
  - Each view becomes two equatable layers, linework under annotations, in the same z order as today: all linework, then annotations, per view.
  - `SheetViewLayer`'s `==` compares `revision` in place of its arrays.
  - `isSelected`, `hovered` and `isPending` stay where they are. Check whether `isSelected` belongs to the linework layer or the annotations layer by what it draws.
  - Keep `SheetCanvasRenderTests` and `SheetViewEqualityTests` green. If a render test's pixels change, the layering changed: fix the order, don't update the fixture.
- [ ] **Step 4: Run `CreatorDrawingEditorTests`, then the full suite and lint.**
- [ ] **Step 5: Notes.** In `Sources/CreatorDrawingEditor/CLAUDE.md`: the buckets, the revisions, the two layers per view, and that `picture.strokes` keeps its flat order for hover indices.
- [ ] **Step 6: Commit.**

### Task 3: The refresh ignores where an annotation sits

**Files:**
- Modify: `Sources/CreatorApp/Drawing/AppModel+DrawingRefresh.swift` (`RefreshKey`, `pendingRefreshes`, about lines 20-40 and 88-144). Also `Sources/CreatorDrawing/Model/` (the annotation types), for a `DrawingAnnotation.placementStripped` (name it as you like).
- Test: `Tests/CreatorAppTests/Drawing/DrawingRefreshKeyTests.swift`, following the folder's existing drawing-refresh tests

**Interfaces:**
- Consumes: none from Tasks 1 and 2.
- Produces: `AppModel.drawingRefreshStarts: Int`, a count of last-good refresh tasks started, for tests.

- [ ] **Step 1: Read `lastGood`** (what `pendingRefreshes` starts) and list, for each annotation kind, which fields it reads. Every field it never reads is placement. Write the list in the commit message and the notes.
- [ ] **Step 2: Write the failing tests.**
  - `aPlacementDragStartsNoRefresh`, parameterised over a dimension's offset, a balloon's position, a note's position and a symbol's position. Ten steps through the editor's drag start zero refreshes after the press.
  - `anAnchorChangeStartsOne`: re-attaching a dimension to another edge starts exactly one refresh.
  - `strippedFieldsDoNotChangeTheFigure`, per annotation kind: `lastGood` gives the same figure for two annotations that differ only in stripped fields. This is the R5 proof.
  - `undoAfterADragRestoresTheFigure`.
- [ ] **Step 3: Run them and see them fail.**
- [ ] **Step 4: Implement R5.** Each `RefreshKey` stores annotations stripped of placement. Nothing else in the key changes.
- [ ] **Step 5: Run `CreatorAppTests`' drawing tests, then the full suite and lint.**
- [ ] **Step 6: Notes.** In `Sources/CreatorApp/CLAUDE.md`'s drawing section: what the refresh key ignores, and why.
- [ ] **Step 7: Commit.**

### Task 4: A bench for a real drag, and pan and zoom apart

**Files:**
- Modify: `Tests/CreatorAppTests/Bench/DrawingBench.swift`, `docs/verification/performance.md` (method rows only, no numbers), `docs/verification/human-checks.md` (group DR-5)

- [ ] **Step 1: Add the bench `drawing-drag-warm`.**
  - Fixture: `drawing-5-warm`'s (ten parts, ten balloons, the parts list).
  - The bench presses on a dimension, then makes 60 `primaryChanged` steps of 0.5 mm each.
  - Each step's figure is the time of the `primaryChanged` call (which includes the host's `storeDrawing` and refresh), plus `timedFrame()`. Settling happens outside the timer.
  - Print `BENCH drawing-drag-warm step-cpu …` with the 16.67 ms budget, in the format of the other lines.
  - Assert, without time, that the dimension moved 30 mm and every balloon stayed held.
- [ ] **Step 2: Split `drawing-2-warm` and `drawing-5-warm`.** Each also prints a `pan` line and a `zoom` line, each over its own 60 steps, beside the combined line that's there today.
- [ ] **Step 3: Check that the fixtures run.**
  - The default run must stay green: fixtures are checked there.
  - Run `scripts/bench.sh DrawingBench` once to see that the lines print. Don't record the numbers: the Mac isn't idle (R7).
- [ ] **Step 4: Update the docs.**
  - `performance.md`: describe the new method and the split lines under DR-5, marked "numbers owed: idle Mac".
  - `human-checks.md` DR-5: add a check that dragging a dimension, a balloon and a view on a ten-part sheet follows the pointer without lag, and that the dragged item's figure is unchanged on release.
- [ ] **Step 5: Run the full suite and lint, then commit.**
