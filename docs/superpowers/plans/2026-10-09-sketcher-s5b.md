# Sketcher S5b — the Sketch Editor's Tools and Inference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the sketch editor the tools that change what's drawn (Trim, Extend, Fillet, Mirror, Pattern), 3-point arcs, point-on and tangent inference with a glyph chip by the pointer, and double-click-a-Sketch-node-to-edit, each edit one undo step.

**Architecture:** Everything but double-click lives in `CreatorSketchEditor`'s `@MainActor @Observable SketchEditorModel`: new `SketchTool` cases route a click through `modify(at:tolerance:)` to the pure `SketchCommands` (S2) and `apply(_:)` commits the `SketchEdit` or shows its `SketchCommandError.message` as `refusal`; the tools' settings are a value (`SketchToolOptions`) typed in a new inspector section (`ToolOptionsView`). Inference grows a new anchor (`SketchAnchor.onCurve`) and a tangent case (`LineInference.tangent`), and the rubber band carries what it would infer (`SketchPreview.inferred`), which a second chip (`InferenceChip`, placed like S5a's `ReadoutChip`) names. Double-click is `EditorModel`'s (`CreatorEditor`): it pairs two plain clicks on one node with an injectable clock (MetalUI gap S5-b) and presses the node's "Edit sketch" button, which the app already turns into sketch mode; the app model changes by one guard (`AppModel.handle(_:)` ignores `.editSketch` while a sketch is open, so a double click can't restart the sketch). No viewport, kernel or graph change.

**Tech Stack:** Swift 6.4 (language mode 6, strict concurrency), Swift Testing, SwiftPM, MetalUI (`../MetalUI`, C7's input APIs; checked at 2155f1e, which has LF-b's fix 9ad2254 and C10).

**Base: rebase first.** This plan was written on `sketcher-s5b` at fdef111, but its anchors, counts and docs are for master **2e64c96** (sketch-drag-readout merged at b2b6726, LF-b's known issues removed at ae54fd1, the groups spec added at 2e64c96; Task 8 follows that spec's §6). Before Task 1, from the worktree: `git rebase master` (the branch holds only this plan's commit), then check `git log --oneline -1 master` is 2e64c96 or later. If master has moved past 2e64c96, re-check each **Modify** anchor before its task and add master's new tests to every count.

**Spec:** `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md` (§3 Commands, §8 Editor, §10 Editor tests, Errata (S4) and (S5a), especially the S5a/S5b split and the camera lock), the S5a plan's "S5b — the rest of S5" section (`docs/superpowers/plans/2026-10-09-sketcher-s5-editor.md`), and the handoff `docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md` ("S5 (editor)", "S5a → S5b"), under the binding parent spec `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` with all its Errata. Task 10 writes this plan's choices into the sketcher spec as "Errata (S5b)".

## Why S5b is split again, and what S5b is

The S5a plan's S5b list is two plans' worth (about 17 tasks). It falls into two halves that share almost no code:

- **S5b (this plan, 10 tasks): the editor's own tools.** Trim, Extend, Fillet, Mirror, Pattern, 3-point arcs, point-on and tangent inference with glyphs, and double-click to edit. All of it is `SketchEditorModel` over S2's already-tested `SketchCommands`, plus one small `EditorModel` change and one guard in `AppModel.handle(_:)` (`AppModel+Picking.swift`: a double click while sketching changes nothing); nothing in the viewport, the kernel or the graph changes, so it can't collide with the viewport-side tracks running now (m7-measure) and is reviewable task by task. The `EditorModel` change shares files with the multi-select and groups-core tracks (below).
- **S5c (next plan): the links to the model and the viewport.** Project (an ID-buffer pick routed through the tool, `EdgePick`, CreatorKernel in `CreatorSketchEditor`, a `SketchStore` batch that writes the projection setting and wires `references`), "New sketch on face" (a face-menu item, a two-node insertion batch, entering a sketch whose plane is wired before its result exists), dimension labels in the view (a viewport overlay label API projected every frame) and the region fill (filled overlay triangles: a renderer pipeline, shader and `GPUDataTests` change). Each needs the viewport or the graph, and together they are another 8–9 tasks. Scope is listed at the end.

Project and "New sketch on face" both fit the camera lock (Errata (S5a): nothing turns the camera while sketching, and the face menu is empty then): Project is a sketch-mode *tool* that declines a click so the viewport's pick reaches the host (no menu, no camera move), and "New sketch on face" is a face-menu item offered only *outside* sketch mode, which then enters the new sketch (its own look-at, as "Edit sketch" does). S5c records this.

## Global Constraints

- Swift 6 strict concurrency (`swiftLanguageModes: [.v6]`); no `@unchecked Sendable`, no `nonisolated(unsafe)`, no GCD.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`); never XCTest.
- Shared state is `@MainActor @Observable` models; behaviour lives in models, views are thin MetalUI `Component`s.
- One type per file (test fixture files under `Support/` may hold several, as the repo's do).
- No force unwraps or force `try`; number text uses `FormatStyle` (`.formatted(...)`), never `String(format:)`.
- `swiftlint lint --strict` reports zero violations (`.swiftlint.yml`: line length 140, type body 250, cyclomatic complexity 10).
- A full `swift test` run passes only if its exit code is 0, no line says "recorded an issue" or "failed after" (Swift Testing prints glyphs, not ✘), and 11 "Test run with" lines appear. On master 2e64c96 with `../MetalUI` at 9ad2254 or later there are no known issues (LF-b's were removed at ae54fd1); the "8 LF-b known issues are expected" rule applied only to fdef111 with MetalUI 0b400b4.
- `CreatorSketch` is unchanged (its commands are S2's, used as they are). `CreatorSketchEditor` must not import CreatorGraph, CreatorNodes or CreatorKernel (sketcher spec §2; CreatorKernel joins with Project in S5c). `CreatorEditor` must not import CreatorNodes.
- Colour hex values are written only in `CreatorStyle`; the glyph chip's colour is the existing `profileHeader` role (the selection's green, sketcher spec §8).
- MetalUI gaps are logged in `docs/metalui-gaps.md` and never worked around silently; this plan adds **S5-b** (no click count on a drag's value) with a documented stopgap, as the task brief allows ("two clicks within an interval in EditorModel, and log/forward a gap").
- Never edit `Package.swift`'s MetalUI path (`../MetalUI`), and never modify the `../MetalUI` repository. This plan doesn't touch `Package.swift` at all.
- Each command is one undo step, applied as a `setInput` of the whole sketch (sketcher spec §8; S5a's `SketchStore` does it from each `SketchCommit`); a refused command stores nothing.
- The camera stays locked to the sketch plane (Errata (S5a)): **F frames the sketch**, so Fillet gets no key (Task 2).
- File format stays version 4: nothing new is saved (`SketchToolOptions` is session state).

## Files shared with other tracks

Tracks running in parallel: **kernel-invalid-blends**, **m7-measure**, **multi-select** and **groups-core** (both worktrees at 2e64c96, building the groups spec `2026-10-09-selection-groups-comments-design.md`), and **themes-colorpicker**. **sketch-drag-readout is merged** (b2b6726: `SketchEditorModel+DragReadout.swift`, `DragReadoutTests`, and lines in `SketchEditorModel+Readout.swift`, `+Drawing.swift`'s `finish()`, `SketchEditorModel.swift`, CLAUDE.md, the S5a errata and human check S5-10), so it is no longer a conflict risk: this plan's anchors are on its merged text. Every file this plan edits outside its own new files, who else may touch it, and what the side that merges second keeps:

- **`Sources/CreatorEditor/EditorModel+Pointer.swift`** — shared with **multi-select** and **groups-core** (groups spec §3: ⌘-click toggles, a press on an already-selected node collapses the selection; both change `pointerReleased` and `click(_:extending:)`). Task 8 adds one line before `pointerReleased`'s `switch` (the `pairClick` call, or `lastNodeClick = nil` after a drag) and leaves `click(_:extending:)` alone. Whichever merges second keeps that one line before the switch and the other track's `click` changes.
- **`Sources/CreatorEditor/EditorModel.swift`** — shared with **multi-select** and **groups-core** (new state for the selection and the open group). Task 8 adds two stored properties after `scrollGlideIgnored` (`now`, `lastNodeClick`); the second to merge keeps both sets.
- **`Sources/CreatorEditor/EditorModel+DoubleClick.swift`** (new here) — **groups-core** (groups C2: "Edit Group" on double-click, groups spec §6) extends it: it appends its action to `doubleClickActions` or adds a group-node branch to `doubleClickAction(for:)`, and keeps `doubleClickInterval` (0.4 s) and `doubleClickSlop` (4 pt), which are already the groups spec's. If groups-core merges first with its own recogniser, the second side keeps one recogniser (this one's `pairClick` before the switch, and `doubleClickActions` holding both actions) and drops the other.
- **`Tests/CreatorEditorTests/Support/EditorTestNodes.swift`** — likely shared with **multi-select** and **groups-core** (test nodes for groups). Task 8 appends `SketchTestNode` and `sketchTestRegistry` after `perNodeSocketTestRegistry`; the second to merge keeps both appends.
- **`Sources/CreatorApp/AppModel+Picking.swift`** — Task 8 adds one guard to `handle(_:)`'s `.editSketch` case. **groups-core** may add an `InspectorAction` case for "Edit Group" to the same `switch`, and **m7-measure** may route its measure picks through this file; the second to merge keeps both. **`Tests/CreatorAppTests/SketchDoubleClickTests.swift`** is new and nobody else's, but it uses `GraphBuilder.sketchedBox()` and `makeApp` from `Tests/CreatorAppTests/Support`, which any CreatorApp track may change.
- `Sources/CreatorSketchEditor/SketchEditorModel+Readout.swift` — Task 5 adds two `case`s at the end of `pointerReadout`'s `switch drawState` (after drag-readout's merged `if let dragged` line, which it doesn't touch). No open track is in it.
- `Sources/CreatorSketchEditor/Views/PointerReadoutView.swift` — Task 7 adds one line (`InferenceChipView`) inside its `ZStack`. No open track is in it.
- `Sources/CreatorSketchEditor/SketchEditorModel.swift` — one stored property (`options`, Task 2). `SketchEditorModel+Drawing.swift` (Tasks 1–7: `click`, `hover`, `anchor`, the drawing tools' `anchor` calls, `rubberBand`; drag-readout's `finish()` is left as merged), `SketchTool.swift`, `DrawState.swift`, `SketchAnchor.swift`, `LineInference.swift`, `SketchPicker.swift`, `SketchPreview.swift`, `EditorGeometry.swift`, `DimensionText.swift`, `Views/SketchToolButton.swift`, `Views/SketchInspector.swift`, `Views/SketchColors.swift` — S5a's files; no open track is in them.
- Docs (Task 10): `CLAUDE.md` (every track), `docs/superpowers/roadmap.md` (every track), `docs/metalui-gaps.md` (a new section at the end; groups-core and multi-select will log their gaps there too), `docs/verification/human-checks.md` (group S5b at the end; every track appends a group), `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md` (Errata (S5b) at the end), `docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md` (a section at the end). Whichever merges second re-applies its lines on the other's.

## Review Focus

The five inputs the spec implies but its feature list doesn't exercise, most likely to bite first. Each has a test in the task that owns the code:

1. **A command that would take an exposed dimension with it** (trimming a line whose length is exposed as an input): a person expects the trim refused in plain words and nothing changed, not the node silently losing an input and its wire. Test: `ModifyToolTests.aTrimThatWouldRemoveAnExposedDimensionIsRefused` (Task 1).
2. **A fillet radius the corner can't hold** (50 mm on a 60 × 40 rectangle, whose corners hold at most 40 mm): a person expects to be told the largest radius that fits, and the sketch untouched. Test: `FilletToolTests.aRadiusTooLargeForTheCornerIsRefused` (Task 2).
3. **A 3-point arc's third click in line with its ends**: a person expects nothing degenerate drawn, and the tool still waiting for a usable third point. Test: `ThreePointArcTests.aThirdClickInLineDrawsNothing` (Task 5).
4. **A click near both a point and the curve through it** (a line's end): a person expects the click to share the point (coincident), not to add a second point held on the curve beside it. Test: `InferenceTests.aPointWinsOverTheCurveThroughIt` (Task 6).
5. **Two clicks that aren't a double click** (slow, far apart, on two nodes, ⇧ held, a drag between): a person expects only selection, never sketch mode opening unasked. Test: `DoubleClickTests.clicksThatArentADoubleClickDoNothing` (Task 8).

## File structure

New in `Sources/CreatorSketchEditor/` (one type per file):

| File | Responsibility |
|---|---|
| `SketchEditorModel+Commands.swift` | `modify(at:tolerance:)` (a command tool's click), Trim/Extend, `apply(_:)` (commit an edit or show its refusal) |
| `SketchEditorModel+Fillet.swift` | The Fillet click and the typed radius |
| `SketchEditorModel+Copies.swift` | Mirror and Pattern clicks, the typed count and spacing |
| `SketchToolOptions.swift` | The command tools' settings (fillet radius, pattern count and spacing) |
| `SketchEditorModel+Inference.swift` | Tangent inference for a line's end, and what a click would infer (for the glyphs) |
| `InferenceChip.swift`, `SketchEditorModel+InferenceChip.swift` | Where the glyph chip sits by the pointer |
| `Views/InferenceChipView.swift` | The glyph chip |
| `Views/ToolOptionsView.swift` | The active tool's hint and options in the inspector |

New in `Sources/CreatorEditor/`: `EditorModel+DoubleClick.swift` (pairing clicks, `nodeDoubleClicked(_:)`, `doubleClickAction(for:)`), `NodeClick.swift` (the last click).

Changed: `SketchTool` (+ `.arcThreePoint`, `.trim`, `.extend`, `.fillet`, `.mirror`, `.pattern`, `hint`, `placesPoints`, `picksCurves`), `DrawState` (+ the 3-point arc's states), `SketchAnchor` (+ `.onCurve`), `LineInference` (+ `.tangent`, `kind`), `SketchPreview` (+ `inferred`), `SketchPicker` (+ `nearestPoint(on:to:)`), `EditorGeometry` (+ `nearest`, `threePointArc`), `DimensionText` (+ `millimetres`).

New tests in `Tests/CreatorSketchEditorTests/`: `ModifyToolTests`, `FilletToolTests`, `MirrorToolTests`, `PatternToolTests`, `ThreePointArcTests`, `InferenceTests`, `InferenceGlyphTests`, `ToolOptionsViewTests`; in `Tests/CreatorEditorTests/`: `DoubleClickTests`, `Support/TestClock.swift`; in `Tests/CreatorAppTests/`: `SketchDoubleClickTests`.

## Task overview

| # | Task | Tests after (master 2e64c96: 1390) |
|---|---|---|
| 1 | Trim and Extend: the command-tool plumbing (`modify`, `apply`) | 1396 (+6) |
| 2 | Fillet, with its radius option (no key: F frames the sketch) | 1401 (+11) |
| 3 | Mirror | 1405 (+15) |
| 4 | Pattern (circular about a point, linear along a line), with count and spacing | 1412 (+22) |
| 5 | 3-point arcs (A toggles), their rubber band and readout | 1417 (+27) |
| 6 | Point-on inference on every curve (⌘ suppresses it), tangent inference off an arc's end | 1424 (+34) |
| 7 | Inference glyphs: `SketchPreview.inferred` and the chip by the pointer | 1433 (+43) |
| 8 | Double-click a Sketch node to edit it (`EditorModel`, one `AppModel` guard, gap S5-b) | 1442 (+52) |
| 9 | The inspector: each tool's hint, the fillet and pattern fields | 1446 (+56) |
| 10 | Docs: spec Errata (S5b), CLAUDE.md, roadmap, gap S5-b (sent to MetalUI), human checks S5b, handoff | 1446 (+56) |

A parameterised test counts once. The counts assume master at 2e64c96 (1390 tests, sketch-drag-readout's included) after the rebase above; if master has moved on, add its new tests to every row.

All commands run from the worktree root (`/Users/maxburger/Developer/MetalCreator-s5b`). "The full check" in every task is:

```bash
swift build --build-tests 2>&1 | grep -E "(warning|error):" | grep -v "ld: warning" | sort -u
swiftlint lint --strict --quiet
swift test > /tmp/s5b-test.log 2>&1; echo "exit $?"
grep -c "Test run with" /tmp/s5b-test.log
grep "Test run with" /tmp/s5b-test.log | sed -E 's/.*Test run with ([0-9]+) test.*/\1/' | paste -sd+ - | bc
grep -E "recorded an issue|failed after" /tmp/s5b-test.log
```

Expected: the build prints only master's one test warning (`Tests/CreatorViewportTests/ContextMenuTests.swift:96`, "'underPointer' mutated after capture by sendable closure", when that file recompiles); swiftlint prints nothing; `exit 0`; `11`; the task's total from the table; and no "recorded an issue" / "failed after" line.

---

### Task 1: Trim and Extend: the command-tool plumbing

**Files:**
- Create: `Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift`
- Modify: `Sources/CreatorSketchEditor/SketchTool.swift` (whole file), `Sources/CreatorSketchEditor/Views/SketchToolButton.swift` (whole file), `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift` (`click`, `hover`, `rubberBand`)
- Test: `Tests/CreatorSketchEditorTests/ModifyToolTests.swift`

**Interfaces:**
- Consumes (S2, `CreatorSketch`, unchanged): `SketchCommands.trim(_ sketch: Sketch, curve: SketchEntityID, near: Vector2) throws(SketchCommandError) -> SketchEdit`, `SketchCommands.extend(_:curve:near:)` (same shape), `SketchEdit.sketch`/`.description`, `SketchCommandError.message`. From S5a: `SketchEditorModel.commit(_ edited: Sketch, _ description: String)`, `SketchPicker(sketch:solution:).curve(near:tolerance:) -> SketchEntityID?`, `.entity(near:tolerance:)`, the internal `click(at:tolerance:modifiers:)` and `hover(at:tolerance:modifiers:)`.
- Produces: `SketchTool.trim`, `.extend` (titles "Trim", "Extend"; Trim's key `"t"`, Extend none); `SketchTool.placesPoints: Bool` and `picksCurves: Bool` (internal); `SketchEditorModel.modify(at p: Vector2, tolerance: Double)` (internal; a command tool's click, a `switch tool` that later tasks extend), `trimOrExtend(at:tolerance:)`, and `apply(_ command: () throws(SketchCommandError) -> SketchEdit)` (internal: commits `edit.sketch` with `edit.description`, keeps the selection's surviving entities and clears `hovered`; on a throw sets `refusal = error.message` and commits nothing). `click`'s switch routes `.trim, .extend` to `modify`; later tasks add their tool to that one `case` (keeping `click` under the complexity limit).

- [ ] **Step 1: Write the failing tests**

Trim and Extend click a curve; a refused command speaks the command's words. The command tools point at curves (a click by a line's end still means the line) and mark no rubber-band point.

**Create** `Tests/CreatorSketchEditorTests/ModifyToolTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// Trim and Extend (sketcher spec §3, §8): a click on a curve runs its command as one step; a refused command says
/// why and changes nothing.
@MainActor
struct ModifyToolTests {
    /// A horizontal line from (0, 0) to (40, 0) crossed by a vertical one from (20, −10) to (20, 10).
    func crossingLines() -> (sketch: Sketch, horizontal: SketchEntityID, vertical: SketchEntityID) {
        var sketch = Sketch()
        let horizontal = sketch.addLine(Vector2(0, 0), Vector2(40, 0))
        let vertical = sketch.addLine(Vector2(20, -10), Vector2(20, 10))
        return (sketch, horizontal, vertical)
    }

    func makeModel(_ sketch: Sketch, tool: SketchTool) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(tool)
        return (model, RecordingHost(model))
    }

    func ends(of line: SketchEntityID, in sketch: Sketch) -> [Vector2] {
        guard case .line(let start, let end)? = sketch.entities[line]?.kind else { return [] }
        return [start, end].compactMap { sketch.position(of: $0) }
    }

    @Test func trimRemovesTheSpanUnderTheClick() throws {
        let fixture = crossingLines()
        let (model, host) = makeModel(fixture.sketch, tool: .trim)
        model.click(at: Vector2(30, 0.3), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Trim Line 1"])
        let ends = ends(of: fixture.horizontal, in: model.sketch)
        #expect(ends.count == 2 && (ends[1] - Vector2(20, 0)).length < 1e-9, "the line now ends where the other crosses it")
    }

    @Test func extendReachesTheNextCurve() {
        var sketch = Sketch()
        let short = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        sketch.addLine(Vector2(20, -10), Vector2(20, 10))
        let (model, host) = makeModel(sketch, tool: .extend)
        model.click(at: Vector2(9, 0.2), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Extend Line 1"])
        let ends = ends(of: short, in: model.sketch)
        #expect(ends.count == 2 && (ends[1] - Vector2(20, 0)).length < 1e-9)
    }

    /// Review Focus 1: a trim that would take an exposed dimension with it (a trimmed line's length) is refused in the
    /// command's words, and nothing is stored.
    @Test func aTrimThatWouldRemoveAnExposedDimensionIsRefused() {
        var fixture = crossingLines()
        let length = fixture.sketch.addDimension(.length(fixture.horizontal), value: 40)
        fixture.sketch.dimensions[length]?.isExposed = true
        let (model, host) = makeModel(fixture.sketch, tool: .trim)
        model.click(at: Vector2(30, 0.3), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "That would remove d1, which is exposed as an input. Stop exposing it first.")
        #expect(model.sketch.dimensions[length] != nil)
    }

    @Test func aRefusedExtendSaysWhy() {
        var sketch = Sketch()
        sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        let (model, host) = makeModel(sketch, tool: .extend)
        model.click(at: Vector2(9, 0.2), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "There is nothing to extend Line 1 to.")
    }

    @Test func theCommandToolsPointAtCurvesAndMarkNoPoint() {
        let fixture = crossingLines()
        let (model, host) = makeModel(fixture.sketch, tool: .trim)
        model.hover(at: Vector2(0.2, 0.1), tolerance: 1, modifiers: [])
        #expect(model.hovered == fixture.horizontal, "the line, not its end point")
        #expect(model.preview == .none, "nothing would be placed")
        model.click(at: Vector2(30, 30), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty && model.refusal == nil, "a click on nothing does nothing")
    }

    @Test func trimHasItsKey() {
        #expect(SketchTool.trim.key == "t" && SketchTool.extend.key == nil)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
swift test --filter CreatorSketchEditorTests.ModifyToolTests
```

Expected: FAIL to compile: `type 'SketchTool' has no member 'trim'`.

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift`:

```swift
import CreatorGeometry
import CreatorSketch

/// The tools that change what's drawn through `SketchCommands` (sketcher spec §3, §8). Each command is one step; a
/// command that can't be applied says why in `refusal` (its `SketchCommandError.message`) and changes nothing.
extension SketchEditorModel {
    /// A click with a command tool, at `p` with `tolerance` mm of slack.
    func modify(at p: Vector2, tolerance: Double) {
        switch tool {
        case .trim, .extend: trimOrExtend(at: p, tolerance: tolerance)
        default: break
        }
    }

    /// A Trim or Extend click: the curve under `p` is trimmed around `p`, or extended at the end nearer `p`. A click
    /// on no curve does nothing.
    func trimOrExtend(at p: Vector2, tolerance: Double) {
        guard let curve = SketchPicker(sketch: sketch, solution: solution).curve(near: p, tolerance: tolerance) else { return }
        let current = sketch
        if tool == .trim {
            apply { () throws(SketchCommandError) in try SketchCommands.trim(current, curve: curve, near: p) }
        } else {
            apply { () throws(SketchCommandError) in try SketchCommands.extend(current, curve: curve, near: p) }
        }
    }

    /// Commits a command's edit as one step (the selection keeps what's left of it), or shows why it was refused.
    func apply(_ command: () throws(SketchCommandError) -> SketchEdit) {
        do {
            let edit = try command()
            selection = selection.filter { edit.sketch.entities[$0] != nil }
            hovered = nil
            commit(edit.sketch, edit.description)
        } catch {
            refusal = error.message
        }
    }
}
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
        case .arc: placeArcPoint(at: p, tolerance: tolerance)
        }
```

with:

```swift
        case .arc: placeArcPoint(at: p, tolerance: tolerance)
        case .trim, .extend: modify(at: p, tolerance: tolerance)
        }
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
        let picker = SketchPicker(sketch: sketch, solution: solution)
        let under = picker.entity(near: p, tolerance: tolerance)
        if hovered != under { hovered = under }
```

with:

```swift
        let picker = SketchPicker(sketch: sketch, solution: solution)
        let under = tool.picksCurves ? picker.curve(near: p, tolerance: tolerance) : picker.entity(near: p, tolerance: tolerance)
        if hovered != under { hovered = under }
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
        case .idle:
            return tool == .select || tool == .dimension ? .none : SketchPreview(points: [target.position])
        case .lineFrom(let start):
```

with:

```swift
        case .idle:
            return tool.placesPoints ? SketchPreview(points: [target.position]) : .none
        case .lineFrom(let start):
```

**Replace the whole of** `Sources/CreatorSketchEditor/SketchTool.swift` with:

```swift
/// The sketch editor's tools (sketcher spec §8's toolbar): the drawing tools, Dimension, and the tools that change
/// what's drawn through `SketchCommands` (Trim, Extend). Project follows in S5c.
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
    /// Click a curve to remove its span between the curves crossing it (T).
    case trim
    /// Click near a line's or an arc's end to extend it to the next curve it meets.
    case extend

    /// The toolbar's title.
    public var title: String {
        switch self {
        case .select: "Select"
        case .line: "Line"
        case .arc: "Arc"
        case .circle: "Circle"
        case .point: "Point"
        case .dimension: "Dimension"
        case .trim: "Trim"
        case .extend: "Extend"
        }
    }

    /// Whether a click places a point (the rubber band then marks where it would land).
    var placesPoints: Bool {
        switch self {
        case .line, .arc, .circle, .point: true
        case .select, .dimension, .trim, .extend: false
        }
    }

    /// Whether the tool acts on a curve, so the pointer picks the curve under it even over one of its points.
    var picksCurves: Bool {
        switch self {
        case .trim, .extend: true
        case .select, .line, .arc, .circle, .point, .dimension: false
        }
    }
}
```

**Replace the whole of** `Sources/CreatorSketchEditor/Views/SketchToolButton.swift` with:

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
        case .trim: "t"
        case .select, .point, .extend: nil
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

```bash
swift test --filter CreatorSketchEditorTests.ModifyToolTests
```

Expected: every test passes.

- [ ] **Step 5: Run the full check**

Run the full check (above). Expected: no new warning, no lint violation, `exit 0`, 11 test runs, **1396** tests, no "recorded an issue" or "failed after" line.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift \
  Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift \
  Sources/CreatorSketchEditor/SketchTool.swift \
  Sources/CreatorSketchEditor/Views/SketchToolButton.swift \
  Tests/CreatorSketchEditorTests/ModifyToolTests.swift
git commit -m "feat(sketch): Trim and Extend tools over SketchCommands"
```

### Task 2: Fillet, with its radius

**Files:**
- Create: `Sources/CreatorSketchEditor/SketchEditorModel+Fillet.swift`, `Sources/CreatorSketchEditor/SketchToolOptions.swift`
- Modify: `Sources/CreatorSketchEditor/SketchTool.swift`, `Views/SketchToolButton.swift`, `SketchEditorModel+Commands.swift` (whole files), `SketchEditorModel+Drawing.swift` (`click`), `SketchEditorModel.swift` (one stored property)
- Test: `Tests/CreatorSketchEditorTests/FilletToolTests.swift`

**Interfaces:**
- Consumes: `SketchCommands.fillet(_ sketch: Sketch, corner: SketchEntityID, radius: Double) throws(SketchCommandError) -> SketchEdit`; Task 1's `modify` and `apply`; `SketchPicker.point(near:tolerance:) -> (id: SketchEntityID, at: Vector2)?`; S5a's `DimensionText.parse(_:) -> Double?`.
- Produces: `SketchTool.fillet` (title "Fillet", **no key**: F frames the sketch, Errata (S5a)); `public struct SketchToolOptions: Hashable, Sendable` with `public var filletRadius = 5.0`; `SketchEditorModel.options: SketchToolOptions` (`public internal(set)`); `public func setFilletRadius(_ text: String)` (refuses anything not > 0 mm with "A fillet radius must be a number more than 0 mm."; not an undo step); internal `fillet(at:tolerance:)`.

- [ ] **Step 1: Write the failing tests**

A click on a corner rounds it with the typed radius; a radius the corner can't hold is refused in the command's words (Review Focus 2).

**Create** `Tests/CreatorSketchEditorTests/FilletToolTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// The Fillet tool (sketcher spec §3, §8): a click on a corner rounds it with the typed radius, as one step.
@MainActor
struct FilletToolTests {
    func makeModel() -> (SketchEditorModel, RecordingHost, RectangleSketch) {
        let rectangle = RectangleSketch(dimensioned: false)
        let model = SketchEditorModel(sketch: rectangle.sketch, plane: .xy)
        model.choose(.fillet)
        return (model, RecordingHost(model), rectangle)
    }

    @Test func aClickOnACornerRoundsIt() throws {
        let (model, host, rectangle) = makeModel()
        model.click(at: Vector2(60.3, 0.2), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Fillet Point 2 (5 mm)"])
        #expect(model.sketch.entities[rectangle.corners[1]] == nil, "the corner point is gone")
        let arcs = model.sketch.entityIDs.filter { if case .arc? = model.sketch.entities[$0]?.kind { true } else { false } }
        #expect(arcs.count == 1)
        let radius = try #require(model.sketch.dimensions.values.first { $0.kind == .radius(arcs[0]) })
        #expect(radius.value == 5)
        #expect(model.solution.status.isUsable)
    }

    @Test func theTypedRadiusIsUsed() {
        let (model, host, _) = makeModel()
        model.setFilletRadius("2.5 mm")
        #expect(model.options.filletRadius == 2.5 && model.refusal == nil)
        model.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Fillet Point 1 (2.5 mm)"])
    }

    @Test(arguments: ["0", "-1", "abc", ""])
    func aRadiusThatIsntASizeIsRefused(_ text: String) {
        let (model, host, _) = makeModel()
        model.setFilletRadius(text)
        #expect(model.refusal == "A fillet radius must be a number more than 0 mm.")
        #expect(model.options.filletRadius == 5 && host.commits.isEmpty)
    }

    /// Review Focus 2: a radius the corner can't hold is refused in the command's words, with the largest that fits,
    /// and nothing is stored.
    @Test func aRadiusTooLargeForTheCornerIsRefused() {
        let (model, host, rectangle) = makeModel()
        model.setFilletRadius("50")
        model.click(at: Vector2(60.3, 0.2), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "Radius 50 mm is too large for this corner (max ≈ 40 mm).")
        #expect(model.sketch.entities[rectangle.corners[1]] != nil)
    }

    @Test func aClickOnALineAwayFromItsCornersSaysWhatToClick() {
        let (model, host, _) = makeModel()
        model.click(at: Vector2(30, 0.3), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "Click the corner where two lines meet.")
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
swift test --filter CreatorSketchEditorTests.FilletToolTests
```

Expected: FAIL to compile: `type 'SketchTool' has no member 'fillet'`.

- [ ] **Step 3: Implement**

**Replace the whole of** `Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift` with:

```swift
import CreatorGeometry
import CreatorSketch

/// The tools that change what's drawn through `SketchCommands` (sketcher spec §3, §8). Each command is one step; a
/// command that can't be applied says why in `refusal` (its `SketchCommandError.message`) and changes nothing.
extension SketchEditorModel {
    /// A click with a command tool, at `p` with `tolerance` mm of slack.
    func modify(at p: Vector2, tolerance: Double) {
        switch tool {
        case .trim, .extend: trimOrExtend(at: p, tolerance: tolerance)
        case .fillet: fillet(at: p, tolerance: tolerance)
        default: break
        }
    }

    /// A Trim or Extend click: the curve under `p` is trimmed around `p`, or extended at the end nearer `p`. A click
    /// on no curve does nothing.
    func trimOrExtend(at p: Vector2, tolerance: Double) {
        guard let curve = SketchPicker(sketch: sketch, solution: solution).curve(near: p, tolerance: tolerance) else { return }
        let current = sketch
        if tool == .trim {
            apply { () throws(SketchCommandError) in try SketchCommands.trim(current, curve: curve, near: p) }
        } else {
            apply { () throws(SketchCommandError) in try SketchCommands.extend(current, curve: curve, near: p) }
        }
    }

    /// Commits a command's edit as one step (the selection keeps what's left of it), or shows why it was refused.
    func apply(_ command: () throws(SketchCommandError) -> SketchEdit) {
        do {
            let edit = try command()
            selection = selection.filter { edit.sketch.entities[$0] != nil }
            hovered = nil
            commit(edit.sketch, edit.description)
        } catch {
            refusal = error.message
        }
    }
}
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
        case .arc: placeArcPoint(at: p, tolerance: tolerance)
        case .trim, .extend: modify(at: p, tolerance: tolerance)
        }
```

with:

```swift
        case .arc: placeArcPoint(at: p, tolerance: tolerance)
        case .trim, .extend, .fillet: modify(at: p, tolerance: tolerance)
        }
```

**Create** `Sources/CreatorSketchEditor/SketchEditorModel+Fillet.swift`:

```swift
import CreatorGeometry
import CreatorSketch

extension SketchEditorModel {
    /// A Fillet click: the corner point under `p` is rounded with `options.filletRadius` (`SketchCommands.fillet`).
    /// A click on a curve away from its corners says what to click; a click on nothing does nothing.
    func fillet(at p: Vector2, tolerance: Double) {
        let picker = SketchPicker(sketch: sketch, solution: solution)
        guard let corner = picker.point(near: p, tolerance: tolerance)?.id else {
            if picker.curve(near: p, tolerance: tolerance) != nil { refusal = "Click the corner where two lines meet." }
            return
        }
        let current = sketch
        let radius = options.filletRadius
        apply { () throws(SketchCommandError) in try SketchCommands.fillet(current, corner: corner, radius: radius) }
    }

    /// The typed fillet radius ("2.5", "2.5 mm"). Not an edit, so not an undo step; text that isn't a size more than
    /// 0 mm is refused and the field shows the old radius.
    public func setFilletRadius(_ text: String) {
        guard let value = DimensionText.parse(text), value > 0 else {
            refusal = "A fillet radius must be a number more than 0 mm."
            return
        }
        refusal = nil
        options.filletRadius = value
    }
}
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel.swift`, replace:

```swift
    public internal(set) var isConstruction = false
    /// Where the pointer is over the viewport (`nil`: off it), and the viewport's size, for the readout's chip.
```

with:

```swift
    public internal(set) var isConstruction = false
    /// The command tools' settings (the fillet radius), typed in the inspector while their tool is active.
    public internal(set) var options = SketchToolOptions()
    /// Where the pointer is over the viewport (`nil`: off it), and the viewport's size, for the readout's chip.
```

**Replace the whole of** `Sources/CreatorSketchEditor/SketchTool.swift` with:

```swift
/// The sketch editor's tools (sketcher spec §8's toolbar): the drawing tools, Dimension, and the tools that change
/// what's drawn through `SketchCommands` (Trim, Extend, Fillet). Project follows in S5c.
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
    /// Click a curve to remove its span between the curves crossing it (T).
    case trim
    /// Click near a line's or an arc's end to extend it to the next curve it meets.
    case extend
    /// Click a corner where two lines meet to round it (`SketchToolOptions.filletRadius`). No key: F frames the sketch.
    case fillet

    /// The toolbar's title.
    public var title: String {
        switch self {
        case .select: "Select"
        case .line: "Line"
        case .arc: "Arc"
        case .circle: "Circle"
        case .point: "Point"
        case .dimension: "Dimension"
        case .trim: "Trim"
        case .extend: "Extend"
        case .fillet: "Fillet"
        }
    }

    /// Whether a click places a point (the rubber band then marks where it would land).
    var placesPoints: Bool {
        switch self {
        case .line, .arc, .circle, .point: true
        case .select, .dimension, .trim, .extend, .fillet: false
        }
    }

    /// Whether the tool acts on a curve, so the pointer picks the curve under it even over one of its points.
    var picksCurves: Bool {
        switch self {
        case .trim, .extend: true
        case .select, .line, .arc, .circle, .point, .dimension, .fillet: false
        }
    }
}
```

**Create** `Sources/CreatorSketchEditor/SketchToolOptions.swift`:

```swift
/// What the command tools use besides the clicks (sketcher spec §3: "the count is a command argument"), typed in the
/// inspector while the tool is active. Not saved: each new sketch session starts from these defaults.
public struct SketchToolOptions: Hashable, Sendable {
    /// The Fillet tool's radius, in millimetres; the arc's radius dimension starts at it.
    public var filletRadius = 5.0

    public init() {}
}
```

**Replace the whole of** `Sources/CreatorSketchEditor/Views/SketchToolButton.swift` with:

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
        case .trim: "t"
        case .select, .point, .extend, .fillet: nil
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

```bash
swift test --filter CreatorSketchEditorTests.FilletToolTests
```

Expected: every test passes.

- [ ] **Step 5: Run the full check**

Run the full check (above). Expected: no new warning, no lint violation, `exit 0`, 11 test runs, **1401** tests, no "recorded an issue" or "failed after" line.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift \
  Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift \
  Sources/CreatorSketchEditor/SketchEditorModel+Fillet.swift \
  Sources/CreatorSketchEditor/SketchEditorModel.swift \
  Sources/CreatorSketchEditor/SketchTool.swift \
  Sources/CreatorSketchEditor/SketchToolOptions.swift \
  Sources/CreatorSketchEditor/Views/SketchToolButton.swift \
  Tests/CreatorSketchEditorTests/FilletToolTests.swift
git commit -m "feat(sketch): Fillet tool with a typed radius"
```

### Task 3: Mirror

**Files:**
- Create: `Sources/CreatorSketchEditor/SketchEditorModel+Copies.swift`
- Modify: `Sources/CreatorSketchEditor/SketchTool.swift`, `Views/SketchToolButton.swift`, `SketchEditorModel+Commands.swift` (whole files), `SketchEditorModel+Drawing.swift` (`click`)
- Test: `Tests/CreatorSketchEditorTests/MirrorToolTests.swift`

**Interfaces:**
- Consumes: `SketchCommands.mirror(_ sketch: Sketch, entities: [SketchEntityID], about axis: SketchEntityID) throws(SketchCommandError) -> SketchEdit` (it drops the axis from the entities and throws "Select the geometry to mirror first." / "Mirror needs a line to mirror about."); Task 1's `modify`, `apply`, `picksCurves`.
- Produces: `SketchTool.mirror` (title "Mirror", no key, `picksCurves == true`); internal `mirror(at:tolerance:)`. The selection stays after a mirror.

- [ ] **Step 1: Write the failing tests**

Select, then click the axis: one step, symmetric constraints, and the selection kept to mirror again.

**Create** `Tests/CreatorSketchEditorTests/MirrorToolTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// The Mirror tool (sketcher spec §3, §8): select, then click the line to mirror about; one step.
@MainActor
struct MirrorToolTests {
    /// A vertical axis along x = 0 and a slanted line to its right.
    func fixture() -> (sketch: Sketch, axis: SketchEntityID, line: SketchEntityID) {
        var sketch = Sketch()
        let axis = sketch.addLine(Vector2(0, -10), Vector2(0, 30), isConstruction: true)
        let line = sketch.addLine(Vector2(5, 0), Vector2(15, 10))
        return (sketch, axis, line)
    }

    func makeModel(_ sketch: Sketch) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(.mirror)
        return (model, RecordingHost(model))
    }

    func positions(_ sketch: Sketch) -> Set<[Double]> {
        Set(sketch.entityIDs.compactMap { id in sketch.position(of: id).map { [($0.x * 1e6).rounded(), ($0.y * 1e6).rounded()] } })
    }

    @Test func aClickOnALineMirrorsTheSelectionAboutIt() {
        let fixture = fixture()
        let (model, host) = makeModel(fixture.sketch)
        model.selection = [fixture.line]
        model.hover(at: Vector2(0.2, 29.8), tolerance: 1, modifiers: [])
        #expect(model.hovered == fixture.axis, "the axis, not its end point")
        model.click(at: Vector2(0.2, 15), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Mirror 1 entity"])
        let mirrored = positions(model.sketch)
        #expect(mirrored.contains([-5e6, 0]) && mirrored.contains([-15e6, 10e6]))
        let symmetric = model.sketch.constraints.values.filter { if case .symmetric = $0 { true } else { false } }
        #expect(symmetric.count == 2)
        #expect(model.selection == [fixture.line], "the selection stays, to mirror again")
    }

    @Test func theAxisInTheSelectionIsLeftOut() {
        let fixture = fixture()
        let (model, host) = makeModel(fixture.sketch)
        model.selection = [fixture.line, fixture.axis]
        model.click(at: Vector2(0.2, 15), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Mirror 1 entity"])
    }

    @Test func withNothingSelectedItSaysWhatToSelect() {
        let (model, host) = makeModel(fixture().sketch)
        model.click(at: Vector2(0.2, 15), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "Select the geometry to mirror first.")
    }

    @Test func aCircleIsNoAxis() {
        var sketch = fixture().sketch
        let circle = sketch.addCircle(center: Vector2(40, 0), radius: 5)
        let (model, host) = makeModel(sketch)
        model.selection = [circle]
        model.click(at: Vector2(45.2, 0), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "Mirror needs a line to mirror about.")
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
swift test --filter CreatorSketchEditorTests.MirrorToolTests
```

Expected: FAIL to compile: `type 'SketchTool' has no member 'mirror'`.

- [ ] **Step 3: Implement**

**Replace the whole of** `Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift` with:

```swift
import CreatorGeometry
import CreatorSketch

/// The tools that change what's drawn through `SketchCommands` (sketcher spec §3, §8). Each command is one step; a
/// command that can't be applied says why in `refusal` (its `SketchCommandError.message`) and changes nothing.
extension SketchEditorModel {
    /// A click with a command tool, at `p` with `tolerance` mm of slack.
    func modify(at p: Vector2, tolerance: Double) {
        switch tool {
        case .trim, .extend: trimOrExtend(at: p, tolerance: tolerance)
        case .fillet: fillet(at: p, tolerance: tolerance)
        case .mirror: mirror(at: p, tolerance: tolerance)
        default: break
        }
    }

    /// A Trim or Extend click: the curve under `p` is trimmed around `p`, or extended at the end nearer `p`. A click
    /// on no curve does nothing.
    func trimOrExtend(at p: Vector2, tolerance: Double) {
        guard let curve = SketchPicker(sketch: sketch, solution: solution).curve(near: p, tolerance: tolerance) else { return }
        let current = sketch
        if tool == .trim {
            apply { () throws(SketchCommandError) in try SketchCommands.trim(current, curve: curve, near: p) }
        } else {
            apply { () throws(SketchCommandError) in try SketchCommands.extend(current, curve: curve, near: p) }
        }
    }

    /// Commits a command's edit as one step (the selection keeps what's left of it), or shows why it was refused.
    func apply(_ command: () throws(SketchCommandError) -> SketchEdit) {
        do {
            let edit = try command()
            selection = selection.filter { edit.sketch.entities[$0] != nil }
            hovered = nil
            commit(edit.sketch, edit.description)
        } catch {
            refusal = error.message
        }
    }
}
```

**Create** `Sources/CreatorSketchEditor/SketchEditorModel+Copies.swift`:

```swift
import CreatorGeometry
import CreatorSketch

/// Mirror: copies of the selection, made by a click on what they're made about.
extension SketchEditorModel {
    /// A Mirror click: the selection is copied mirrored about the line under `p` (`SketchCommands.mirror`, which leaves
    /// the line itself out of what it copies and says what's missing: a selection, or a line). The selection stays, so
    /// it can be mirrored again about another line. A click on nothing does nothing.
    func mirror(at p: Vector2, tolerance: Double) {
        guard let axis = SketchPicker(sketch: sketch, solution: solution).curve(near: p, tolerance: tolerance) else { return }
        let current = sketch
        let selected = selection.sorted()
        apply { () throws(SketchCommandError) in try SketchCommands.mirror(current, entities: selected, about: axis) }
    }
}
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
        case .arc: placeArcPoint(at: p, tolerance: tolerance)
        case .trim, .extend, .fillet: modify(at: p, tolerance: tolerance)
        }
```

with:

```swift
        case .arc: placeArcPoint(at: p, tolerance: tolerance)
        case .trim, .extend, .fillet, .mirror: modify(at: p, tolerance: tolerance)
        }
```

**Replace the whole of** `Sources/CreatorSketchEditor/SketchTool.swift` with:

```swift
/// The sketch editor's tools (sketcher spec §8's toolbar): the drawing tools, Dimension, and the tools that change
/// what's drawn through `SketchCommands` (Trim, Extend, Fillet, Mirror). Project follows in S5c.
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
    /// Click a curve to remove its span between the curves crossing it (T).
    case trim
    /// Click near a line's or an arc's end to extend it to the next curve it meets.
    case extend
    /// Click a corner where two lines meet to round it (`SketchToolOptions.filletRadius`). No key: F frames the sketch.
    case fillet
    /// With geometry selected, click a line to copy the selection mirrored about it.
    case mirror

    /// The toolbar's title.
    public var title: String {
        switch self {
        case .select: "Select"
        case .line: "Line"
        case .arc: "Arc"
        case .circle: "Circle"
        case .point: "Point"
        case .dimension: "Dimension"
        case .trim: "Trim"
        case .extend: "Extend"
        case .fillet: "Fillet"
        case .mirror: "Mirror"
        }
    }

    /// Whether a click places a point (the rubber band then marks where it would land).
    var placesPoints: Bool {
        switch self {
        case .line, .arc, .circle, .point: true
        case .select, .dimension, .trim, .extend, .fillet, .mirror: false
        }
    }

    /// Whether the tool acts on a curve, so the pointer picks the curve under it even over one of its points.
    var picksCurves: Bool {
        switch self {
        case .trim, .extend, .mirror: true
        case .select, .line, .arc, .circle, .point, .dimension, .fillet: false
        }
    }
}
```

**Replace the whole of** `Sources/CreatorSketchEditor/Views/SketchToolButton.swift` with:

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
        case .trim: "t"
        case .select, .point, .extend, .fillet, .mirror: nil
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

```bash
swift test --filter CreatorSketchEditorTests.MirrorToolTests
```

Expected: every test passes.

- [ ] **Step 5: Run the full check**

Run the full check (above). Expected: no new warning, no lint violation, `exit 0`, 11 test runs, **1405** tests, no "recorded an issue" or "failed after" line.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift \
  Sources/CreatorSketchEditor/SketchEditorModel+Copies.swift \
  Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift \
  Sources/CreatorSketchEditor/SketchTool.swift \
  Sources/CreatorSketchEditor/Views/SketchToolButton.swift \
  Tests/CreatorSketchEditorTests/MirrorToolTests.swift
git commit -m "feat(sketch): Mirror tool"
```

### Task 4: Pattern: around a point or along a line

**Files:**
- Modify: `Sources/CreatorSketchEditor/SketchTool.swift`, `Views/SketchToolButton.swift`, `SketchEditorModel+Commands.swift`, `SketchEditorModel+Copies.swift`, `SketchToolOptions.swift` (whole files), `SketchEditorModel+Drawing.swift` (`click`)
- Test: `Tests/CreatorSketchEditorTests/PatternToolTests.swift`

**Interfaces:**
- Consumes: `SketchCommands.circularPattern(_:entities:center:count:)` and `linearPattern(_:entities:direction:spacing:count:)` (both `throws(SketchCommandError) -> SketchEdit`; they refuse an empty selection, a count under 2 or over 100); Tasks 1–3.
- Produces: `SketchTool.pattern` (title "Pattern", no key); `SketchToolOptions.patternCount = 3`, `patternSpacing = 20.0`; `public func setPatternCount(_ text: String)` (a whole number ≥ 2, else "A pattern needs a whole number of instances, 2 or more."), `public func setPatternSpacing(_ text: String)` (> 0 mm, else "A pattern spacing must be a number more than 0 mm."); internal `pattern(at:tolerance:)`: a point → circular about it, a line → linear from its start toward its end, another curve → "Click a point to pattern around, or a line to pattern along.".

- [ ] **Step 1: Write the failing tests**

A click on a point patterns around it, on a line along it; typed count and spacing are checked; the command's own limit (100) refuses when it runs.

**Create** `Tests/CreatorSketchEditorTests/PatternToolTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// The Pattern tool (sketcher spec §3, §8): select, then click a point (circular) or a line (linear); one step.
@MainActor
struct PatternToolTests {
    func makeModel(_ sketch: Sketch) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(.pattern)
        return (model, RecordingHost(model))
    }

    /// The centres of every circle, rounded to a micrometre.
    func circleCentres(_ sketch: Sketch) -> Set<[Double]> {
        Set(sketch.entityIDs.compactMap { id -> [Double]? in
            guard case .circle(let center, _)? = sketch.entities[id]?.kind, let at = sketch.position(of: center) else { return nil }
            return [(at.x * 1000).rounded() / 1000, (at.y * 1000).rounded() / 1000]
        })
    }

    @Test func aClickOnALinePatternsAlongIt() {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: Vector2(0, 0), radius: 2)
        sketch.addLine(Vector2(0, -10), Vector2(10, -10), isConstruction: true)
        let (model, host) = makeModel(sketch)
        model.selection = [circle]
        model.click(at: Vector2(5, -9.8), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Linear pattern of 1 entity (×3)"])
        #expect(circleCentres(model.sketch) == [[0, 0], [20, 0], [40, 0]])
        #expect(model.selection == [circle])
    }

    @Test func aClickOnAPointPatternsAroundIt() {
        var sketch = Sketch()
        sketch.addPoint(Vector2(0, 0))
        let circle = sketch.addCircle(center: Vector2(10, 0), radius: 2)
        let (model, host) = makeModel(sketch)
        model.setPatternCount("4")
        model.selection = [circle]
        model.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Circular pattern of 1 entity (×4)"])
        #expect(circleCentres(model.sketch) == [[10, 0], [0, 10], [-10, 0], [0, -10]])
    }

    @Test func theTypedSpacingIsUsed() {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: Vector2(0, 0), radius: 2)
        sketch.addLine(Vector2(0, -10), Vector2(0, -20))
        let (model, _) = makeModel(sketch)
        model.setPatternSpacing("15 mm")
        model.setPatternCount("2")
        model.selection = [circle]
        model.click(at: Vector2(0.2, -15), tolerance: 1, modifiers: [])
        #expect(circleCentres(model.sketch) == [[0, 0], [0, -15]], "along the line, from its start toward its end")
    }

    @Test(arguments: ["1", "2.5", "abc", ""])
    func aCountThatIsntTwoOrMoreIsRefused(_ text: String) {
        let (model, _) = makeModel(Sketch())
        model.setPatternCount(text)
        #expect(model.refusal == "A pattern needs a whole number of instances, 2 or more.")
        #expect(model.options.patternCount == 3)
    }

    @Test func aSpacingThatIsntASizeIsRefused() {
        let (model, _) = makeModel(Sketch())
        model.setPatternSpacing("0")
        #expect(model.refusal == "A pattern spacing must be a number more than 0 mm.")
        #expect(model.options.patternSpacing == 20)
    }

    @Test func aCountOverTheLimitIsRefusedWhenItRuns() {
        var sketch = Sketch()
        sketch.addPoint(Vector2(0, 0))
        let circle = sketch.addCircle(center: Vector2(10, 0), radius: 2)
        let (model, host) = makeModel(sketch)
        model.setPatternCount("101")
        model.selection = [circle]
        model.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty)
        #expect(model.refusal == "A pattern can have at most 100 instances.")
    }

    @Test func anArcOrNothingSelectedSaysWhatsMissing() {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: Vector2(10, 0), radius: 2)
        sketch.addPoint(Vector2(0, 0))
        let (model, host) = makeModel(sketch)
        model.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        #expect(model.refusal == "Select the geometry to pattern first.")
        model.selection = [circle]
        model.click(at: Vector2(12.1, 0), tolerance: 1, modifiers: [])
        #expect(model.refusal == "Click a point to pattern around, or a line to pattern along.")
        #expect(host.commits.isEmpty)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
swift test --filter CreatorSketchEditorTests.PatternToolTests
```

Expected: FAIL to compile: `type 'SketchTool' has no member 'pattern'`.

- [ ] **Step 3: Implement**

**Replace the whole of** `Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift` with:

```swift
import CreatorGeometry
import CreatorSketch

/// The tools that change what's drawn through `SketchCommands` (sketcher spec §3, §8). Each command is one step; a
/// command that can't be applied says why in `refusal` (its `SketchCommandError.message`) and changes nothing.
extension SketchEditorModel {
    /// A click with a command tool, at `p` with `tolerance` mm of slack.
    func modify(at p: Vector2, tolerance: Double) {
        switch tool {
        case .trim, .extend: trimOrExtend(at: p, tolerance: tolerance)
        case .fillet: fillet(at: p, tolerance: tolerance)
        case .mirror: mirror(at: p, tolerance: tolerance)
        case .pattern: pattern(at: p, tolerance: tolerance)
        default: break
        }
    }

    /// A Trim or Extend click: the curve under `p` is trimmed around `p`, or extended at the end nearer `p`. A click
    /// on no curve does nothing.
    func trimOrExtend(at p: Vector2, tolerance: Double) {
        guard let curve = SketchPicker(sketch: sketch, solution: solution).curve(near: p, tolerance: tolerance) else { return }
        let current = sketch
        if tool == .trim {
            apply { () throws(SketchCommandError) in try SketchCommands.trim(current, curve: curve, near: p) }
        } else {
            apply { () throws(SketchCommandError) in try SketchCommands.extend(current, curve: curve, near: p) }
        }
    }

    /// Commits a command's edit as one step (the selection keeps what's left of it), or shows why it was refused.
    func apply(_ command: () throws(SketchCommandError) -> SketchEdit) {
        do {
            let edit = try command()
            selection = selection.filter { edit.sketch.entities[$0] != nil }
            hovered = nil
            commit(edit.sketch, edit.description)
        } catch {
            refusal = error.message
        }
    }
}
```

**Replace the whole of** `Sources/CreatorSketchEditor/SketchEditorModel+Copies.swift` with:

```swift
import CreatorGeometry
import CreatorSketch
import Foundation

/// Mirror and Pattern: copies of the selection, made by a click on what they're made about.
extension SketchEditorModel {
    /// A Mirror click: the selection is copied mirrored about the line under `p` (`SketchCommands.mirror`, which leaves
    /// the line itself out of what it copies and says what's missing: a selection, or a line). The selection stays, so
    /// it can be mirrored again about another line. A click on nothing does nothing.
    func mirror(at p: Vector2, tolerance: Double) {
        guard let axis = SketchPicker(sketch: sketch, solution: solution).curve(near: p, tolerance: tolerance) else { return }
        let current = sketch
        let selected = selection.sorted()
        apply { () throws(SketchCommandError) in try SketchCommands.mirror(current, entities: selected, about: axis) }
    }

    /// A Pattern click: on a point, `options.patternCount` instances of the selection around it (a circular pattern);
    /// on a line, that many along it, from its start toward its end, `options.patternSpacing` apart (a linear one).
    /// Any other curve says what to click; a click on nothing does nothing. The selection stays.
    func pattern(at p: Vector2, tolerance: Double) {
        guard let target = SketchPicker(sketch: sketch, solution: solution).entity(near: p, tolerance: tolerance) else { return }
        let (current, selected, count, spacing) = (sketch, selection.sorted(), options.patternCount, options.patternSpacing)
        switch sketch.entities[target]?.kind {
        case .point?:
            apply { () throws(SketchCommandError) in
                try SketchCommands.circularPattern(current, entities: selected, center: target, count: count)
            }
        case .line(let start, let end)?:
            guard let a = sketch.position(of: start), let b = sketch.position(of: end) else { return }
            apply { () throws(SketchCommandError) in
                try SketchCommands.linearPattern(current, entities: selected, direction: b - a, spacing: spacing, count: count)
            }
        default:
            refusal = "Click a point to pattern around, or a line to pattern along."
        }
    }

    /// The typed instance count: a whole number, 2 or more (the command refuses more than its limit when it runs).
    public func setPatternCount(_ text: String) {
        guard let count = Int(text.trimmingCharacters(in: .whitespaces)), count >= 2 else {
            refusal = "A pattern needs a whole number of instances, 2 or more."
            return
        }
        refusal = nil
        options.patternCount = count
    }

    /// The typed spacing of a linear pattern ("15", "15 mm"): a size more than 0 mm.
    public func setPatternSpacing(_ text: String) {
        guard let value = DimensionText.parse(text), value > 0 else {
            refusal = "A pattern spacing must be a number more than 0 mm."
            return
        }
        refusal = nil
        options.patternSpacing = value
    }
}
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
        case .arc: placeArcPoint(at: p, tolerance: tolerance)
        case .trim, .extend, .fillet, .mirror: modify(at: p, tolerance: tolerance)
        }
```

with:

```swift
        case .arc: placeArcPoint(at: p, tolerance: tolerance)
        case .trim, .extend, .fillet, .mirror, .pattern: modify(at: p, tolerance: tolerance)
        }
```

**Replace the whole of** `Sources/CreatorSketchEditor/SketchTool.swift` with:

```swift
/// The sketch editor's tools (sketcher spec §8's toolbar): the drawing tools, Dimension, and the tools that change
/// what's drawn through `SketchCommands` (Trim, Extend, Fillet, Mirror, Pattern). Project follows in S5c.
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
    /// Click a curve to remove its span between the curves crossing it (T).
    case trim
    /// Click near a line's or an arc's end to extend it to the next curve it meets.
    case extend
    /// Click a corner where two lines meet to round it (`SketchToolOptions.filletRadius`). No key: F frames the sketch.
    case fillet
    /// With geometry selected, click a line to copy the selection mirrored about it.
    case mirror
    /// With geometry selected, click a point to copy the selection around it, or a line to copy it along the line
    /// (`SketchToolOptions.patternCount`, `patternSpacing`).
    case pattern

    /// The toolbar's title.
    public var title: String {
        switch self {
        case .select: "Select"
        case .line: "Line"
        case .arc: "Arc"
        case .circle: "Circle"
        case .point: "Point"
        case .dimension: "Dimension"
        case .trim: "Trim"
        case .extend: "Extend"
        case .fillet: "Fillet"
        case .mirror: "Mirror"
        case .pattern: "Pattern"
        }
    }

    /// Whether a click places a point (the rubber band then marks where it would land).
    var placesPoints: Bool {
        switch self {
        case .line, .arc, .circle, .point: true
        case .select, .dimension, .trim, .extend, .fillet, .mirror, .pattern: false
        }
    }

    /// Whether the tool acts on a curve, so the pointer picks the curve under it even over one of its points.
    var picksCurves: Bool {
        switch self {
        case .trim, .extend, .mirror: true
        case .select, .line, .arc, .circle, .point, .dimension, .fillet, .pattern: false
        }
    }
}
```

**Replace the whole of** `Sources/CreatorSketchEditor/SketchToolOptions.swift` with:

```swift
/// What the command tools use besides the clicks (sketcher spec §3: "the count is a command argument"), typed in the
/// inspector while the tool is active. Not saved: each new sketch session starts from these defaults.
public struct SketchToolOptions: Hashable, Sendable {
    /// The Fillet tool's radius, in millimetres; the arc's radius dimension starts at it.
    public var filletRadius = 5.0
    /// How many instances the Pattern tool makes, the selection included.
    public var patternCount = 3
    /// A linear pattern's step between instances, in millimetres.
    public var patternSpacing = 20.0

    public init() {}
}
```

**Replace the whole of** `Sources/CreatorSketchEditor/Views/SketchToolButton.swift` with:

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
        case .trim: "t"
        case .select, .point, .extend, .fillet, .mirror, .pattern: nil
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

```bash
swift test --filter CreatorSketchEditorTests.PatternToolTests
```

Expected: every test passes.

- [ ] **Step 5: Run the full check**

Run the full check (above). Expected: no new warning, no lint violation, `exit 0`, 11 test runs, **1412** tests, no "recorded an issue" or "failed after" line.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift \
  Sources/CreatorSketchEditor/SketchEditorModel+Copies.swift \
  Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift \
  Sources/CreatorSketchEditor/SketchTool.swift \
  Sources/CreatorSketchEditor/SketchToolOptions.swift \
  Sources/CreatorSketchEditor/Views/SketchToolButton.swift \
  Tests/CreatorSketchEditorTests/PatternToolTests.swift
git commit -m "feat(sketch): Pattern tool, circular and linear"
```

### Task 5: 3-point arcs

**Files:**
- Modify: `Sources/CreatorSketchEditor/SketchTool.swift`, `Views/SketchToolButton.swift`, `DrawState.swift`, `EditorGeometry.swift` (whole files), `SketchEditorModel+Drawing.swift` (`press`, `click`, the 3-point placement, `rubberBand`), `SketchEditorModel+Readout.swift` (two `case`s; sketch-drag-readout's lines there are merged)
- Test: `Tests/CreatorSketchEditorTests/ThreePointArcTests.swift`

**Interfaces:**
- Consumes: S5a's `SketchAnchor`, `anchor(at:tolerance:)`, `commit`, `ReadoutText.line(from:to:)`, `ReadoutText.arc(center:start:end:)`, `Sketch.addArc(center:start:end:isConstruction:)` (counter-clockwise).
- Produces: `SketchTool.arcThreePoint` (title "3-Point Arc", right after `.arc` in `allCases`, no key of its own); `public func press(_ tool: SketchTool)` (the toolbar's action: Arc's A on the centre arc switches to the 3-point arc and back; every other tool is `choose`); `DrawState.arcThroughFrom(SketchAnchor)`, `.arcThrough(start:end:)`; `EditorGeometry.threePointArc(from:to:through:) -> (center: Vector2, isCounterClockwise: Bool)?` (`nil` when collinear). The readout reads the chord after the start, then "R … mm · …°".

- [ ] **Step 1: Write the failing tests**

Start, end, then a point it passes through; a far-side third point runs the long way round; a collinear third click draws nothing (Review Focus 3); A toggles the two arcs.

**Create** `Tests/CreatorSketchEditorTests/ThreePointArcTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// The 3-point arc (sketcher spec §8: "Arc (centre / 3-point) | A"): start, end, then a point it passes through.
@MainActor
struct ThreePointArcTests {
    func makeModel() -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: Sketch(), plane: .xy)
        model.choose(.arcThreePoint)
        return (model, RecordingHost(model))
    }

    /// The one arc drawn: its centre, start and end positions.
    func arc(_ sketch: Sketch) throws -> (center: Vector2, start: Vector2, end: Vector2) {
        let id = try #require(sketch.entityIDs.first { if case .arc? = sketch.entities[$0]?.kind { true } else { false } })
        guard case .arc(let c, let s, let e)? = sketch.entities[id]?.kind,
              let center = sketch.position(of: c), let start = sketch.position(of: s), let end = sketch.position(of: e) else {
            throw ArcMissing()
        }
        return (center, start, end)
    }

    struct ArcMissing: Error {}

    func near(_ a: Vector2, _ b: Vector2) -> Bool { (a - b).length < 1e-6 }

    @Test func threeClicksDrawTheArcThroughTheThird() throws {
        let (model, host) = makeModel()
        model.click(at: Vector2(10, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(0, 10), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty, "two clicks place the ends")
        model.click(at: Vector2(7.0710678, 7.0710678), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Arc"])
        let drawn = try arc(model.sketch)
        #expect(near(drawn.center, .zero) && near(drawn.start, Vector2(10, 0)) && near(drawn.end, Vector2(0, 10)))
        #expect(model.solution.status.isUsable)
    }

    @Test func aThirdPointOnTheFarSideRunsTheArcTheLongWayRound() throws {
        let (model, _) = makeModel()
        model.click(at: Vector2(10, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(0, 10), tolerance: 1, modifiers: [])
        model.click(at: Vector2(-7.0710678, -7.0710678), tolerance: 1, modifiers: [])
        let drawn = try arc(model.sketch)
        #expect(near(drawn.center, .zero))
        #expect(near(drawn.start, Vector2(0, 10)) && near(drawn.end, Vector2(10, 0)), "counter-clockwise from the end, through the third")
    }

    /// Review Focus 3: a third click in line with the ends draws nothing and keeps waiting.
    @Test func aThirdClickInLineDrawsNothing() {
        let (model, host) = makeModel()
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(10, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(5, 0), tolerance: 1, modifiers: [])
        #expect(host.commits.isEmpty)
        model.click(at: Vector2(5, 5), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Arc"])
    }

    @Test func theRubberBandAndTheReadoutFollowEachStep() {
        let (model, _) = makeModel()
        model.click(at: Vector2(10, 0), tolerance: 1, modifiers: [])
        model.hover(at: Vector2(0, 10), tolerance: 1, modifiers: [])
        #expect(model.preview.curves == [.line(Vector2(10, 0), Vector2(0, 10))])
        #expect(model.pointerReadout == "14.1 mm · 135.0°", "the chord")
        model.click(at: Vector2(0, 10), tolerance: 1, modifiers: [])
        model.hover(at: Vector2(7.0710678, 7.0710678), tolerance: 1, modifiers: [])
        guard case .arc(let center, _, _)? = model.preview.curves.first else {
            Issue.record("no arc in the rubber band")
            return
        }
        #expect(near(center, .zero))
        #expect(model.pointerReadout == "R 10.0 mm · 90.0°")
    }

    @Test func arcsKeyTogglesBetweenTheTwoArcs() {
        let model = SketchEditorModel(sketch: Sketch(), plane: .xy)
        model.press(.arc)
        #expect(model.tool == .arc)
        model.press(.arc)
        #expect(model.tool == .arcThreePoint)
        model.press(.arc)
        #expect(model.tool == .arc)
        model.press(.line)
        #expect(model.tool == .line)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
swift test --filter CreatorSketchEditorTests.ThreePointArcTests
```

Expected: FAIL to compile: `type 'SketchTool' has no member 'arcThreePoint'`.

- [ ] **Step 3: Implement**

**Replace the whole of** `Sources/CreatorSketchEditor/DrawState.swift` with:

```swift
/// What a drawing tool has placed so far (`SketchEditorModel`'s in-progress stroke).
enum DrawState: Hashable, Sendable {
    case idle
    /// A line's start; after each line the chain goes on from its end.
    case lineFrom(SketchAnchor)
    case circleAround(SketchAnchor)
    case arcAround(SketchAnchor)
    case arcFrom(center: SketchAnchor, start: SketchAnchor)
    /// A 3-point arc's start, then its start and end.
    case arcThroughFrom(SketchAnchor)
    case arcThrough(start: SketchAnchor, end: SketchAnchor)
}
```

**Replace the whole of** `Sources/CreatorSketchEditor/EditorGeometry.swift` with:

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

    /// The arc from `a` to `b` through `p`: the centre of the circle through the three, and whether the arc runs
    /// counter-clockwise from `a` (else from `b`). `nil` when the three are in line (or two coincide).
    static func threePointArc(from a: Vector2, to b: Vector2, through p: Vector2) -> (center: Vector2, isCounterClockwise: Bool)? {
        let (u, v) = (b - a, p - a)
        let cross = u.x * v.y - u.y * v.x
        guard abs(cross) > 1e-9 * max(1, u.x * u.x + u.y * u.y, v.x * v.x + v.y * v.y) else { return nil }
        let (uu, vv) = (u.x * u.x + u.y * u.y, v.x * v.x + v.y * v.y)
        let center = a + Vector2(v.y * uu - u.y * vv, u.x * vv - v.x * uu) * (1 / (2 * cross))
        // Counter-clockwise from a to b passes the points to the right of the chord a→b.
        return (center, cross < 0)
    }
}
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
        refusal = nil
    }
```

with:

```swift
        refusal = nil
    }

    /// A toolbar button or its key: picks `tool`, except that Arc's (A) on the centre arc switches to the 3-point arc,
    /// and back (sketcher spec §8: "Arc (centre / 3-point) | A").
    public func press(_ tool: SketchTool) {
        guard tool == .arc else { return choose(tool) }
        choose(self.tool == .arc ? .arcThreePoint : .arc)
    }
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
        case .arc: placeArcPoint(at: p, tolerance: tolerance)
        case .trim, .extend, .fillet, .mirror, .pattern: modify(at: p, tolerance: tolerance)
```

with:

```swift
        case .arc: placeArcPoint(at: p, tolerance: tolerance)
        case .arcThreePoint: placeThreePointArcPoint(at: p, tolerance: tolerance)
        case .trim, .extend, .fillet, .mirror, .pattern: modify(at: p, tolerance: tolerance)
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift

    /// An arc's end: an existing point as it is, else the click moved onto the start's radius; `nil` on the centre.
```

with:

```swift

    /// Start, end, then a point the arc passes through: the arc runs on the circle through the three, from the start to
    /// the end the way that passes the third (counter-clockwise from whichever end makes it so), around a new centre
    /// point. A third click in line with the other two draws nothing and waits for another.
    private func placeThreePointArcPoint(at p: Vector2, tolerance: Double) {
        switch drawState {
        case .arcThroughFrom(let start):
            let end = anchor(at: p, tolerance: tolerance)
            guard (end.position - start.position).length > 1e-9, end.point == nil || end.point != start.point else { return }
            drawState = .arcThrough(start: start, end: end)
        case .arcThrough(let start, let end):
            guard let arc = EditorGeometry.threePointArc(from: start.position, to: end.position, through: p) else { return }
            var edited = sketch
            let s = start.point(in: &edited)
            let e = end.point(in: &edited)
            let c = edited.addPoint(arc.center)
            edited.addArc(center: c, start: arc.isCounterClockwise ? s : e, end: arc.isCounterClockwise ? e : s,
                          isConstruction: isConstruction)
            commit(edited, "Arc")
            drawState = .idle
        default:
            drawState = .arcThroughFrom(anchor(at: p, tolerance: tolerance))
        }
    }

    /// An arc's end: an existing point as it is, else the click moved onto the start's radius; `nil` on the centre.
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
                                 points: [center.position, start.position, end.position])
        }
```

with:

```swift
                                 points: [center.position, start.position, end.position])
        case .arcThroughFrom(let start):
            return SketchPreview(curves: [.line(start.position, target.position)], points: [start.position])
        case .arcThrough(let start, let end):
            guard let arc = EditorGeometry.threePointArc(from: start.position, to: end.position, through: p) else {
                return SketchPreview(curves: [.line(start.position, end.position)], points: [start.position, end.position])
            }
            let (from, to) = arc.isCounterClockwise ? (start.position, end.position) : (end.position, start.position)
            return SketchPreview(curves: [.arc(center: arc.center, start: from, end: to)], points: [start.position, end.position])
        }
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Readout.swift`, replace:

```swift
            return ReadoutText.arc(center: center.position, start: start.position, end: end)
        }
```

with:

```swift
            return ReadoutText.arc(center: center.position, start: start.position, end: end)
        case .arcThroughFrom:
            // A 3-point arc reads its chord after the start, then its radius and sweep after the end.
            guard case .line(let start, let end)? = preview.curves.first else { return nil }
            return ReadoutText.line(from: start, to: end)
        case .arcThrough:
            guard case .arc(let center, let start, let end)? = preview.curves.first else { return nil }
            return ReadoutText.arc(center: center, start: start, end: end)
        }
```

**Replace the whole of** `Sources/CreatorSketchEditor/SketchTool.swift` with:

```swift
/// The sketch editor's tools (sketcher spec §8's toolbar): the drawing tools, Dimension, and the tools that change
/// what's drawn through `SketchCommands` (Trim, Extend, Fillet, Mirror, Pattern). Project follows in S5c.
public enum SketchTool: Hashable, Sendable, CaseIterable {
    /// Click to select (⇧ adds), drag a point to move it.
    case select
    /// Lines chain from click to click (L).
    case line
    /// Centre, start, end (A).
    case arc
    /// Start, end, then a point the arc passes through (A again, from Arc).
    case arcThreePoint
    /// Centre, then a point on the circle (C).
    case circle
    /// A lone point.
    case point
    /// Pick one or two entities; the kind of dimension follows from them (D).
    case dimension
    /// Click a curve to remove its span between the curves crossing it (T).
    case trim
    /// Click near a line's or an arc's end to extend it to the next curve it meets.
    case extend
    /// Click a corner where two lines meet to round it (`SketchToolOptions.filletRadius`). No key: F frames the sketch.
    case fillet
    /// With geometry selected, click a line to copy the selection mirrored about it.
    case mirror
    /// With geometry selected, click a point to copy the selection around it, or a line to copy it along the line
    /// (`SketchToolOptions.patternCount`, `patternSpacing`).
    case pattern

    /// The toolbar's title.
    public var title: String {
        switch self {
        case .select: "Select"
        case .line: "Line"
        case .arc: "Arc"
        case .arcThreePoint: "3-Point Arc"
        case .circle: "Circle"
        case .point: "Point"
        case .dimension: "Dimension"
        case .trim: "Trim"
        case .extend: "Extend"
        case .fillet: "Fillet"
        case .mirror: "Mirror"
        case .pattern: "Pattern"
        }
    }

    /// Whether a click places a point (the rubber band then marks where it would land).
    var placesPoints: Bool {
        switch self {
        case .line, .arc, .arcThreePoint, .circle, .point: true
        case .select, .dimension, .trim, .extend, .fillet, .mirror, .pattern: false
        }
    }

    /// Whether the tool acts on a curve, so the pointer picks the curve under it even over one of its points.
    var picksCurves: Bool {
        switch self {
        case .trim, .extend, .mirror: true
        case .select, .line, .arc, .arcThreePoint, .circle, .point, .dimension, .fillet, .pattern: false
        }
    }
}
```

**Replace the whole of** `Sources/CreatorSketchEditor/Views/SketchToolButton.swift` with:

```swift
import MetalUI

/// One tool in the toolbar, marked while it's the active one, with its key (sketcher spec §8).
struct SketchToolButton: Component {
    let model: SketchEditorModel
    let tool: SketchTool

    var content: some ElementGroup {
        let title = model.tool == tool ? "\(tool.title) ✓" : tool.title
        if let key = tool.key {
            Button(title) { model.press(tool) }
                .keyboardShortcut(key, modifiers: [])
                .help("\(tool.title) (\(String(key.character).uppercased()))")
        } else {
            Button(title) { model.press(tool) }
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
        case .trim: "t"
        case .select, .point, .arcThreePoint, .extend, .fillet, .mirror, .pattern: nil
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

```bash
swift test --filter CreatorSketchEditorTests.ThreePointArcTests
```

Expected: every test passes.

- [ ] **Step 5: Run the full check**

Run the full check (above). Expected: no new warning, no lint violation, `exit 0`, 11 test runs, **1417** tests, no "recorded an issue" or "failed after" line.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorSketchEditor/DrawState.swift \
  Sources/CreatorSketchEditor/EditorGeometry.swift \
  Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift \
  Sources/CreatorSketchEditor/SketchEditorModel+Readout.swift \
  Sources/CreatorSketchEditor/SketchTool.swift \
  Sources/CreatorSketchEditor/Views/SketchToolButton.swift \
  Tests/CreatorSketchEditorTests/ThreePointArcTests.swift
git commit -m "feat(sketch): 3-point arcs; A toggles the arc tools"
```

### Task 6: Point-on and tangent inference

**Files:**
- Create: `Sources/CreatorSketchEditor/SketchEditorModel+Inference.swift`
- Modify: `Sources/CreatorSketchEditor/SketchAnchor.swift`, `LineInference.swift`, `SketchPicker.swift`, `EditorGeometry.swift` (whole files), `SketchEditorModel+Drawing.swift` (`click` passes ⌘ to every drawing tool, `hover` computes the anchor once, `anchor`, `placePoint`, each drawing tool's `anchor` calls, the line's inference, the rubber band's)
- Test: `Tests/CreatorSketchEditorTests/InferenceTests.swift`

**Interfaces:**
- Consumes: `SketchConstraint.pointOn(point:curve:)`, `.tangent(_:_:)` (a shared endpoint makes it tangent there), S5a's `SketchOverlayBuilder.position(_:_:_:)`.
- Produces: `SketchAnchor.onCurve(SketchEntityID, at: Vector2)` (its `point(in:isConstruction:)` adds the point and a point-on; `curve` names the curve); `SketchEditorModel.anchor(at:tolerance:suppressed:)` now returns a point first, else (unless ⌘ `suppressed` it) `.onCurve` within the tolerance of a curve, else `.free`; every drawing tool's `place…Point(at:tolerance:suppressed:)` passes ⌘ on; `rubberBand(to:landing:tolerance:suppressed:)` takes the anchor `hover` computed (one anchor, so one curve scan for it, per pointer move); `LineInference.tangent(SketchEntityID)`; `SketchEditorModel.lineInference(from start: SketchAnchor, to end: Vector2, tolerance: Double, suppressed: Bool) -> (LineInference?, Vector2)` (tangent to the newest arc ending at the start when the end is within the tolerance of its tangent, else `LineInference.infer`); `SketchPicker.nearestPoint(on:to:) -> Vector2?`; `EditorGeometry.nearest(to:onSegment:_:)`, `nearest(to:onCircle:radius:)`.

- [ ] **Step 1: Write the failing tests**

Clicks on curves hold new points on them; points win over the curves through them (Review Focus 4); a line leaving an arc's end along its tangent snaps and is held tangent; ⌘ suppresses point-on and tangent as it does horizontal and vertical (sketcher spec §8), but never sharing a point (coincident is structural).

**Create** `Tests/CreatorSketchEditorTests/InferenceTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// Point-on and tangent inference (sketcher spec §8): a click on a curve puts a new point on it (held there by
/// point-on), and a line leaving an arc's end along its tangent snaps onto it and is held tangent.
@MainActor
struct InferenceTests {
    func makeModel(_ sketch: Sketch, tool: SketchTool) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(tool)
        return (model, RecordingHost(model))
    }

    func constraints(_ sketch: Sketch) -> [SketchConstraint] {
        sketch.constraintIDs.compactMap { sketch.constraints[$0] }
    }

    /// The newest line's start and end points.
    func newestLine(_ sketch: Sketch) -> (id: SketchEntityID, start: SketchEntityID, end: SketchEntityID)? {
        for id in sketch.entityIDs.reversed() {
            if case .line(let start, let end)? = sketch.entities[id]?.kind { return (id, start, end) }
        }
        return nil
    }

    /// An arc around the origin, radius 10, from (10, 0) counter-clockwise to 45°.
    func arcSketch() -> (sketch: Sketch, arc: SketchEntityID, end: SketchEntityID) {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let start = sketch.addPoint(Vector2(10, 0))
        let end = sketch.addPoint(Vector2(10, 10) * (1 / 2.0.squareRoot()))
        let arc = sketch.addArc(center: center, start: start, end: end)
        return (sketch, arc, end)
    }

    @Test func aLineEndingOnACurveIsHeldOnIt() throws {
        var sketch = Sketch()
        let base = sketch.addLine(Vector2(0, 0), Vector2(40, 0))
        let (model, host) = makeModel(sketch, tool: .line)
        model.click(at: Vector2(10, 15), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20, 0.4), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Line"])
        let line = try #require(newestLine(model.sketch))
        #expect(model.sketch.position(of: line.end) == Vector2(20, 0), "snapped onto the curve")
        #expect(constraints(model.sketch) == [.pointOn(point: line.end, curve: base)])
    }

    /// Review Focus 4: a click near both a point and the curve through it shares the point (coincident by
    /// construction) and adds no point-on.
    @Test func aPointWinsOverTheCurveThroughIt() throws {
        var sketch = Sketch()
        sketch.addLine(Vector2(0, 0), Vector2(40, 0))
        let (model, _) = makeModel(sketch, tool: .line)
        model.click(at: Vector2(10, 15), tolerance: 1, modifiers: [])
        model.click(at: Vector2(39.6, 0.3), tolerance: 1, modifiers: [])
        let line = try #require(newestLine(model.sketch))
        #expect(model.sketch.position(of: line.end) == Vector2(40, 0))
        #expect(constraints(model.sketch).isEmpty)
    }

    @Test func thePointToolPutsAPointOnACircle() throws {
        var sketch = Sketch()
        let circle = sketch.addCircle(center: .zero, radius: 10)
        let (model, host) = makeModel(sketch, tool: .point)
        model.hover(at: Vector2(0.3, 10.4), tolerance: 1, modifiers: [])
        let marked = try #require(model.preview.points.first)
        #expect(abs(marked.length - 10) < 1e-9, "the rubber band marks the snapped place")
        model.click(at: Vector2(0.3, 10.4), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.description) == ["Point"])
        let point = try #require(model.sketch.entityIDs.last)
        #expect(constraints(model.sketch) == [.pointOn(point: point, curve: circle)])
        #expect(abs((model.sketch.position(of: point) ?? .zero).length - 10) < 1e-9)
    }

    @Test func aLineLeavingAnArcAlongItsTangentIsHeldTangent() throws {
        let fixture = arcSketch()
        let (model, _) = makeModel(fixture.sketch, tool: .line)
        let corner = Vector2(10, 10) * (1 / 2.0.squareRoot())
        let tangent = Vector2(-1, 1) * (1 / 2.0.squareRoot())
        model.click(at: corner + Vector2(0.2, 0), tolerance: 1, modifiers: [])
        let aimed = corner + tangent * 20 + Vector2(0.4, 0.3)
        model.hover(at: aimed, tolerance: 1, modifiers: [])
        guard case .line(_, let shown)? = model.preview.curves.first else {
            Issue.record("no rubber band")
            return
        }
        #expect((shown - (corner + tangent * 20)).length < 0.5, "the rubber band snaps onto the tangent")
        model.click(at: aimed, tolerance: 1, modifiers: [])
        let line = try #require(newestLine(model.sketch))
        #expect(line.start == fixture.end, "the line starts on the arc's end")
        #expect(constraints(model.sketch) == [.tangent(line.id, fixture.arc)])
        let end = try #require(model.sketch.position(of: line.end))
        let offset = end - corner
        #expect(abs(offset.x * tangent.y - offset.y * tangent.x) < 1e-9, "the end is on the tangent")
        #expect(model.solution.status.isUsable)
    }

    @Test func commandSuppressesTangentInference() throws {
        let fixture = arcSketch()
        let (model, _) = makeModel(fixture.sketch, tool: .line)
        let corner = Vector2(10, 10) * (1 / 2.0.squareRoot())
        let tangent = Vector2(-1, 1) * (1 / 2.0.squareRoot())
        model.click(at: corner, tolerance: 1, modifiers: [])
        model.click(at: corner + tangent * 20 + Vector2(0.4, 0.3), tolerance: 1, modifiers: .command)
        #expect(constraints(model.sketch).isEmpty)
    }

    /// ⌘ suppresses point-on too (sketcher spec §8: "holding ⌘ suppresses inference"): the end stays where it was
    /// clicked, free, and so does a lone point.
    @Test func commandSuppressesPointOn() throws {
        var sketch = Sketch()
        sketch.addLine(Vector2(0, 0), Vector2(40, 0))
        let (model, host) = makeModel(sketch, tool: .line)
        model.click(at: Vector2(10, 15), tolerance: 1, modifiers: [])
        model.click(at: Vector2(20, 0.4), tolerance: 1, modifiers: .command)
        let line = try #require(newestLine(model.sketch))
        let end = try #require(model.sketch.position(of: line.end))
        #expect((end - Vector2(20, 0.4)).length < 1e-9, "not snapped onto the curve")
        model.choose(.point)
        model.click(at: Vector2(30, 0.4), tolerance: 1, modifiers: .command)
        #expect(host.commits.map(\.description) == ["Line", "Point"])
        #expect(constraints(model.sketch).isEmpty)
    }

    @Test func aLineAwayFromTheTangentStillInfersHorizontal() throws {
        let fixture = arcSketch()
        let (model, _) = makeModel(fixture.sketch, tool: .line)
        let corner = Vector2(10, 10) * (1 / 2.0.squareRoot())
        model.click(at: corner, tolerance: 1, modifiers: [])
        model.click(at: corner + Vector2(20, 0.3), tolerance: 1, modifiers: [])
        let line = try #require(newestLine(model.sketch))
        #expect(constraints(model.sketch) == [.horizontal(line.id)])
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
swift test --filter CreatorSketchEditorTests.InferenceTests
```

Expected: FAIL: `aLineEndingOnACurveIsHeldOnIt`, `thePointToolPutsAPointOnACircle` and `aLineLeavingAnArcAlongItsTangentIsHeldTangent` record issues (no point-on, no tangent yet); the other four pass.

- [ ] **Step 3: Implement**

**Replace the whole of** `Sources/CreatorSketchEditor/EditorGeometry.swift` with:

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
        (p - nearest(to: p, onSegment: a, b)).length
    }

    /// The point of the segment `a`–`b` nearest `p`.
    static func nearest(to p: Vector2, onSegment a: Vector2, _ b: Vector2) -> Vector2 {
        let d = b - a
        let squared = d.x * d.x + d.y * d.y
        guard squared > 0 else { return a }
        let t = min(max(((p.x - a.x) * d.x + (p.y - a.y) * d.y) / squared, 0), 1)
        return a + d * t
    }

    /// The point of the circle around `center` nearest `p` (its rightmost point when `p` is the centre).
    static func nearest(to p: Vector2, onCircle center: Vector2, radius: Double) -> Vector2 {
        let offset = p - center
        let length = offset.length
        guard length > 1e-12 else { return center + Vector2(radius, 0) }
        return center + offset * (radius / length)
    }

    /// The distance from `p` to a polyline.
    static func distance(from p: Vector2, toPolyline points: [Vector2]) -> Double {
        zip(points, points.dropFirst()).map { distance(from: p, toSegment: $0, $1) }.min() ?? .infinity
    }

    /// The arc from `a` to `b` through `p`: the centre of the circle through the three, and whether the arc runs
    /// counter-clockwise from `a` (else from `b`). `nil` when the three are in line (or two coincide).
    static func threePointArc(from a: Vector2, to b: Vector2, through p: Vector2) -> (center: Vector2, isCounterClockwise: Bool)? {
        let (u, v) = (b - a, p - a)
        let cross = u.x * v.y - u.y * v.x
        guard abs(cross) > 1e-9 * max(1, u.x * u.x + u.y * u.y, v.x * v.x + v.y * v.y) else { return nil }
        let (uu, vv) = (u.x * u.x + u.y * u.y, v.x * v.x + v.y * v.y)
        let center = a + Vector2(v.y * uu - u.y * vv, u.x * vv - v.x * uu) * (1 / (2 * cross))
        // Counter-clockwise from a to b passes the points to the right of the chord a→b.
        return (center, cross < 0)
    }
}
```

**Replace the whole of** `Sources/CreatorSketchEditor/LineInference.swift` with:

```swift
import CreatorGeometry
import CreatorSketch

/// The constraint a line's end infers from its start (sketcher spec §8): tangent to an arc ending at the start
/// (`SketchEditorModel.lineInference`), else horizontal when the end is within the tolerance of the start's height,
/// else vertical when it's within it of the start's x. The end is snapped onto it.
enum LineInference: Hashable, Sendable {
    case horizontal
    case vertical
    case tangent(SketchEntityID)

    /// The horizontal or vertical inference for a line from `start` to `end`, and the end it snaps to; none when ⌘
    /// suppresses it.
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
        case .tangent(let arc): .tangent(line, arc)
        }
    }
}
```

**Replace the whole of** `Sources/CreatorSketchEditor/SketchAnchor.swift` with:

```swift
import CreatorGeometry
import CreatorSketch

/// Where a tool's click lands: on an existing point (shared, so the new curve is coincident with it structurally,
/// spec §3), on a curve (a new point held on it by point-on, sketcher spec §8's inference), or at a new position.
enum SketchAnchor: Hashable, Sendable {
    case existing(SketchEntityID, at: Vector2)
    case onCurve(SketchEntityID, at: Vector2)
    case free(Vector2)

    var position: Vector2 {
        switch self {
        case .existing(_, let at), .onCurve(_, let at), .free(let at): at
        }
    }

    var point: SketchEntityID? {
        if case .existing(let id, _) = self { return id }
        return nil
    }

    /// The curve a new point is held on, for `.onCurve`.
    var curve: SketchEntityID? {
        if case .onCurve(let id, _) = self { return id }
        return nil
    }

    /// The anchor's point in `sketch`: the existing one, or a new one at its position (held on its curve by point-on
    /// for `.onCurve`).
    func point(in sketch: inout Sketch, isConstruction: Bool = false) -> SketchEntityID {
        switch self {
        case .existing(let id, _):
            return id
        case .onCurve(let curve, let at):
            let point = sketch.addPoint(at, isConstruction: isConstruction)
            sketch.add(.pointOn(point: point, curve: curve))
            return point
        case .free(let at):
            return sketch.addPoint(at, isConstruction: isConstruction)
        }
    }
}
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
        refusal = nil
        switch tool {
        case .select: select(at: p, tolerance: tolerance)
        case .dimension: dimension(at: p, tolerance: tolerance)
        case .point: placePoint(at: p, tolerance: tolerance)
        case .line: placeLinePoint(at: p, tolerance: tolerance, suppressed: modifiers.contains(.command))
        case .circle: placeCirclePoint(at: p, tolerance: tolerance)
        case .arc: placeArcPoint(at: p, tolerance: tolerance)
        case .arcThreePoint: placeThreePointArcPoint(at: p, tolerance: tolerance)
```

with:

```swift
        refusal = nil
        let suppressed = modifiers.contains(.command)
        switch tool {
        case .select: select(at: p, tolerance: tolerance)
        case .dimension: dimension(at: p, tolerance: tolerance)
        case .point: placePoint(at: p, tolerance: tolerance, suppressed: suppressed)
        case .line: placeLinePoint(at: p, tolerance: tolerance, suppressed: suppressed)
        case .circle: placeCirclePoint(at: p, tolerance: tolerance, suppressed: suppressed)
        case .arc: placeArcPoint(at: p, tolerance: tolerance, suppressed: suppressed)
        case .arcThreePoint: placeThreePointArcPoint(at: p, tolerance: tolerance, suppressed: suppressed)
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
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
```

with:

```swift
        let suppressed = modifiers.contains(.command)
        // One anchor per move, shared by everything the move shows, so its curve scan runs once.
        let target = anchor(at: p, tolerance: tolerance, suppressed: suppressed)
        let next = rubberBand(to: p, landing: target, tolerance: tolerance, suppressed: suppressed)
        if preview != next { preview = next }
    }

    /// Where a click at `p` lands: the nearest existing point within `tolerance`, else the nearest place on the nearest
    /// curve within it (point-on inference, sketcher spec §8; not while ⌘ `suppressed` it), else `p` itself.
    func anchor(at p: Vector2, tolerance: Double, suppressed: Bool) -> SketchAnchor {
        let picker = SketchPicker(sketch: sketch, solution: solution)
        if let hit = picker.point(near: p, tolerance: tolerance) { return .existing(hit.id, at: hit.at) }
        if !suppressed, let curve = picker.curve(near: p, tolerance: tolerance), let on = picker.nearestPoint(on: curve, to: p) {
            return .onCurve(curve, at: on)
        }
        return .free(p)
    }

    /// A lone point, held on the curve it's clicked on; a click on an existing point adds nothing.
    private func placePoint(at p: Vector2, tolerance: Double, suppressed: Bool) {
        let target = anchor(at: p, tolerance: tolerance, suppressed: suppressed)
        guard target.point == nil else { return }
        var edited = sketch
        _ = target.point(in: &edited, isConstruction: isConstruction)
        commit(edited, "Point")
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
            drawState = .lineFrom(anchor(at: p, tolerance: tolerance))
            return
        }
        var end = anchor(at: p, tolerance: tolerance)
        if end.point != nil, end.point == start.point { return }
        var inference: LineInference?
        if case .free(let at) = end {
            let inferred = LineInference.infer(from: start.position, to: at, tolerance: tolerance, suppressed: suppressed)
            inference = inferred.0
```

with:

```swift
            drawState = .lineFrom(anchor(at: p, tolerance: tolerance, suppressed: suppressed))
            return
        }
        var end = anchor(at: p, tolerance: tolerance, suppressed: suppressed)
        if end.point != nil, end.point == start.point { return }
        var inference: LineInference?
        if case .free(let at) = end {
            let inferred = lineInference(from: start, to: at, tolerance: tolerance, suppressed: suppressed)
            inference = inferred.0
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
    private func placeCirclePoint(at p: Vector2, tolerance: Double) {
        guard case .circleAround(let center) = drawState else {
            drawState = .circleAround(anchor(at: p, tolerance: tolerance))
            return
        }
        let radius = (anchor(at: p, tolerance: tolerance).position - center.position).length
```

with:

```swift
    private func placeCirclePoint(at p: Vector2, tolerance: Double, suppressed: Bool) {
        guard case .circleAround(let center) = drawState else {
            drawState = .circleAround(anchor(at: p, tolerance: tolerance, suppressed: suppressed))
            return
        }
        let radius = (anchor(at: p, tolerance: tolerance, suppressed: suppressed).position - center.position).length
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
    private func placeArcPoint(at p: Vector2, tolerance: Double) {
        switch drawState {
        case .arcAround(let center):
            let start = anchor(at: p, tolerance: tolerance)
            guard (start.position - center.position).length > 1e-9 else { return }
            drawState = .arcFrom(center: center, start: start)
        case .arcFrom(let center, let start):
            let end = arcEnd(center: center.position, start: start.position, toward: anchor(at: p, tolerance: tolerance))
```

with:

```swift
    private func placeArcPoint(at p: Vector2, tolerance: Double, suppressed: Bool) {
        let target = anchor(at: p, tolerance: tolerance, suppressed: suppressed)
        switch drawState {
        case .arcAround(let center):
            guard (target.position - center.position).length > 1e-9 else { return }
            drawState = .arcFrom(center: center, start: target)
        case .arcFrom(let center, let start):
            let end = arcEnd(center: center.position, start: start.position, toward: target)
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
        default:
            drawState = .arcAround(anchor(at: p, tolerance: tolerance))
        }
```

with:

```swift
        default:
            drawState = .arcAround(target)
        }
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
    private func placeThreePointArcPoint(at p: Vector2, tolerance: Double) {
        switch drawState {
        case .arcThroughFrom(let start):
            let end = anchor(at: p, tolerance: tolerance)
```

with:

```swift
    private func placeThreePointArcPoint(at p: Vector2, tolerance: Double, suppressed: Bool) {
        switch drawState {
        case .arcThroughFrom(let start):
            let end = anchor(at: p, tolerance: tolerance, suppressed: suppressed)
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
            drawState = .arcThroughFrom(anchor(at: p, tolerance: tolerance))
```

with:

```swift
            drawState = .arcThroughFrom(anchor(at: p, tolerance: tolerance, suppressed: suppressed))
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
    /// The rubber band from what's placed to `p`.
    private func rubberBand(to p: Vector2, tolerance: Double, suppressed: Bool) -> SketchPreview {
        let target = anchor(at: p, tolerance: tolerance)
        switch drawState {
        case .idle:
            return tool.placesPoints ? SketchPreview(points: [target.position]) : .none
        case .lineFrom(let start):
            var end = target.position
            if target.point == nil {
                end = LineInference.infer(from: start.position, to: end, tolerance: tolerance, suppressed: suppressed).1
            }
```

with:

```swift
    /// The rubber band from what's placed to `p`, where a click would land on `target` (`anchor`).
    private func rubberBand(to p: Vector2, landing target: SketchAnchor, tolerance: Double, suppressed: Bool) -> SketchPreview {
        switch drawState {
        case .idle:
            return tool.placesPoints ? SketchPreview(points: [target.position]) : .none
        case .lineFrom(let start):
            var end = target.position
            if case .free = target {
                end = lineInference(from: start, to: end, tolerance: tolerance, suppressed: suppressed).1
            }
```

**Create** `Sources/CreatorSketchEditor/SketchEditorModel+Inference.swift`:

```swift
import CreatorGeometry
import CreatorSketch

extension SketchEditorModel {
    /// What a line from `start` to the free point `end` infers, and where its end snaps: tangent to an arc that starts
    /// or ends at the line's start, when the end is within the tolerance of that tangent (sketcher spec §8: "tangent to
    /// the previous arc"; the newest such arc), else horizontal or vertical (`LineInference.infer`). Nothing when ⌘
    /// suppresses it.
    func lineInference(from start: SketchAnchor, to end: Vector2, tolerance: Double, suppressed: Bool) -> (LineInference?, Vector2) {
        if !suppressed, let tangent = tangent(at: start) {
            let offset = end - start.position
            let along = offset.x * tangent.direction.x + offset.y * tangent.direction.y
            let across = abs(offset.x * tangent.direction.y - offset.y * tangent.direction.x)
            if abs(along) > tolerance, across <= tolerance {
                return (.tangent(tangent.arc), start.position + tangent.direction * along)
            }
        }
        return LineInference.infer(from: start.position, to: end, tolerance: tolerance, suppressed: suppressed)
    }

    /// The newest arc that starts or ends at `start`'s point, and its unit tangent there.
    private func tangent(at start: SketchAnchor) -> (arc: SketchEntityID, direction: Vector2)? {
        guard let point = start.point else { return nil }
        for id in sketch.entityIDs.reversed() {
            guard case .arc(let center, let from, let to)? = sketch.entities[id]?.kind, from == point || to == point,
                  let c = SketchOverlayBuilder.position(center, sketch, solution) else { continue }
            let radius = start.position - c
            let length = radius.length
            guard length > 1e-9 else { continue }
            return (id, Vector2(-radius.y / length, radius.x / length))
        }
        return nil
    }
}
```

**Replace the whole of** `Sources/CreatorSketchEditor/SketchPicker.swift` with:

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

    /// The place on `curve` nearest `p`, at its solved position: on a line's segment, or on an arc's or a circle's
    /// circle (the curve is picked near its drawn span first, so that place is on what's drawn); `nil` for a point.
    func nearestPoint(on curve: SketchEntityID, to p: Vector2) -> Vector2? {
        let at = { (point: SketchEntityID) in SketchOverlayBuilder.position(point, sketch, solution) }
        switch sketch.entities[curve]?.kind {
        case .line(let start, let end)?:
            guard let a = at(start), let b = at(end) else { return nil }
            return EditorGeometry.nearest(to: p, onSegment: a, b)
        case .arc(let center, let start, _)?:
            guard let c = at(center), let s = at(start) else { return nil }
            return EditorGeometry.nearest(to: p, onCircle: c, radius: (s - c).length)
        case .circle(let center, _)?:
            guard let c = at(center), let radius = solution.radii[curve] ?? sketch.radius(of: curve) else { return nil }
            return EditorGeometry.nearest(to: p, onCircle: c, radius: radius)
        case .projected(let source)?:
            switch source.curve {
            case .line(let a, let b): return EditorGeometry.nearest(to: p, onSegment: a, b)
            case .arc(let c, let radius, _, _), .circle(let c, let radius):
                return EditorGeometry.nearest(to: p, onCircle: c, radius: radius)
            }
        case .point?, nil:
            return nil
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

```bash
swift test --filter CreatorSketchEditorTests.InferenceTests
```

Expected: every test passes.

- [ ] **Step 5: Run the full check**

Run the full check (above). Expected: no new warning, no lint violation, `exit 0`, 11 test runs, **1424** tests, no "recorded an issue" or "failed after" line.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorSketchEditor/EditorGeometry.swift \
  Sources/CreatorSketchEditor/LineInference.swift \
  Sources/CreatorSketchEditor/SketchAnchor.swift \
  Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift \
  Sources/CreatorSketchEditor/SketchEditorModel+Inference.swift \
  Sources/CreatorSketchEditor/SketchPicker.swift \
  Tests/CreatorSketchEditorTests/InferenceTests.swift
git commit -m "feat(sketch): point-on and tangent inference"
```

### Task 7: Inference glyphs

**Files:**
- Create: `Sources/CreatorSketchEditor/InferenceChip.swift`, `SketchEditorModel+InferenceChip.swift`, `Views/InferenceChipView.swift`
- Modify: `Sources/CreatorSketchEditor/SketchPreview.swift`, `LineInference.swift`, `SketchEditorModel+Inference.swift`, `Views/SketchColors.swift` (whole files), `SketchEditorModel+Drawing.swift` (`hover`), `Views/PointerReadoutView.swift` (one line)
- Test: `Tests/CreatorSketchEditorTests/InferenceGlyphTests.swift`

**Interfaces:**
- Consumes: Task 6's `anchor`, `lineInference`; S5a's `ReadoutChip.gap`, `.margin`, `.height`, `.characterWidth`, `.padding`; `SketchEditorModel.pointerOnScreen`, `viewSize`, `modelArea` (internal, set by `pointerMoved(to:projector:)`); `SketchConstraintKind.title`.
- Produces: `SketchPreview.inferred: [SketchConstraintKind]` (init gains `inferred: = []`); `LineInference.kind: SketchConstraintKind`; `SketchEditorModel.inferredConstraints(landing:tolerance:suppressed:) -> [SketchConstraintKind]` (given the anchor `hover` already computed for the rubber band, so a move still finds one anchor) and `static func inferred(by: SketchAnchor)`; `public struct InferenceChip` (`init?(kinds:pointer:in:modelArea:avoiding:)`, `text`, `origin`, `size`; `avoiding` is the readout's `ReadoutChip`, which it never overlaps); `public var inferenceChip: InferenceChip?` (placed clear of `readoutChip`); `SketchColors.inferred` (the theme's `profileHeader`). `PointerReadoutView` draws the chip beside the readout.

- [ ] **Step 1: Write the failing tests**

What a click would infer rides on the rubber band, and a chip below right of the pointer names it, clear of the model area's edges and never over the readout's chip (which near the top of the view flips below the pointer, and near the bottom stays above it).

**Create** `Tests/CreatorSketchEditorTests/InferenceGlyphTests.swift`:

```swift
import CreatorGeometry
import CreatorSketch
import CreatorViewport
import MetalUI
import Testing
@testable import CreatorSketchEditor

/// The glyphs of what a click would infer (sketcher spec §8: "a glyph previews each inferred constraint"), in a chip
/// below and right of the pointer.
@MainActor
struct InferenceGlyphTests {
    func makeModel(_ tool: SketchTool, _ sketch: Sketch = Sketch()) -> SketchEditorModel {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(tool)
        return model
    }

    func inferred(_ model: SketchEditorModel, at p: Vector2, modifiers: ViewportModifiers = []) -> [SketchConstraintKind] {
        model.hover(at: p, tolerance: 1, modifiers: modifiers)
        return model.preview.inferred
    }

    @Test func aLinesEndShowsWhatItWouldInfer() {
        var sketch = Sketch()
        sketch.addLine(Vector2(0, 40), Vector2(40, 40))
        let model = makeModel(.line, sketch)
        #expect(inferred(model, at: Vector2(20, 40.3)) == [.pointOn], "the first click would land on the line")
        #expect(inferred(model, at: Vector2(20, 40.3), modifiers: .command).isEmpty, "⌘ suppresses point on")
        #expect(inferred(model, at: Vector2(0.2, 39.8)) == [.coincident], "or share its end")
        #expect(inferred(model, at: Vector2(0.2, 39.8), modifiers: .command) == [.coincident], "⌘ never unshares a point")
        #expect(inferred(model, at: Vector2(10, 10)).isEmpty)
        model.click(at: Vector2(0, 0), tolerance: 1, modifiers: [])
        #expect(inferred(model, at: Vector2(20, 0.4)) == [.horizontal])
        #expect(inferred(model, at: Vector2(0.3, 20)) == [.vertical])
        #expect(inferred(model, at: Vector2(0.3, 20), modifiers: .command).isEmpty, "⌘ suppresses it")
        #expect(inferred(model, at: Vector2(20, 39.7)) == [.pointOn])
    }

    @Test func aLineLeavingAnArcShowsTangent() {
        var sketch = Sketch()
        let center = sketch.addPoint(.zero)
        let start = sketch.addPoint(Vector2(10, 0))
        let end = sketch.addPoint(Vector2(0, 10))
        sketch.addArc(center: center, start: start, end: end)
        let model = makeModel(.line, sketch)
        model.click(at: Vector2(0, 10), tolerance: 1, modifiers: [])
        #expect(inferred(model, at: Vector2(-20, 10.4)) == [.tangent], "tangent wins over horizontal")
    }

    @Test func clicksThatPlaceNoPointInferNothing() {
        var sketch = Sketch()
        sketch.addPoint(Vector2(10, 0))
        let model = makeModel(.circle, sketch)
        model.click(at: .zero, tolerance: 1, modifiers: [])
        #expect(inferred(model, at: Vector2(10.2, 0)).isEmpty, "a circle's radius point isn't kept")
        model.choose(.select)
        #expect(inferred(model, at: Vector2(10.2, 0)).isEmpty)
    }

    @Test func theChipSitsBelowRightOfThePointer() throws {
        let size = ViewportSize(width: 400, height: 300)
        let chip = try #require(InferenceChip(kinds: [.horizontal], pointer: ScreenPoint(200, 150), in: size))
        #expect(chip.text == "Horizontal")
        #expect(chip.origin == ScreenPoint(200 + ReadoutChip.gap, 150 + ReadoutChip.gap))
        let two = try #require(InferenceChip(kinds: [.pointOn, .tangent], pointer: ScreenPoint(200, 150), in: size))
        #expect(two.text == "Point on · Tangent" && two.size.width > chip.size.width)
        #expect(InferenceChip(kinds: [], pointer: ScreenPoint(200, 150), in: size) == nil)
    }

    @Test func theChipMovesLeftAndUpAtTheModelAreasEdges() throws {
        let size = ViewportSize(width: 400, height: 300)
        let chip = try #require(InferenceChip(kinds: [.vertical], pointer: ScreenPoint(390, 290), in: size))
        #expect(abs(chip.origin.x + chip.size.width - (390 - ReadoutChip.gap)) < 1e-9, "left of the pointer")
        #expect(abs(chip.origin.y + chip.size.height - (290 - ReadoutChip.gap)) < 1e-9, "above it")
        let inset = try #require(InferenceChip(kinds: [.vertical], pointer: ScreenPoint(250, 150), in: size,
                                               modelArea: ViewportInsets(trailing: 100)))
        #expect(inset.origin.x + inset.size.width <= 300, "clear of a panel on the trailing side")
        #expect(InferenceChip(kinds: [.vertical], pointer: ScreenPoint(20, 10), in: ViewportSize(width: 60, height: 30)) == nil)
    }

    @Test func theModelPlacesTheChipAtThePointer() throws {
        let model = makeModel(.line)
        let size = ViewportSize(width: 400, height: 300)
        let projector = ViewportProjector(pose: CameraPose(target: .zero, distance: 100, pitch: .pi / 2,
                                                           projection: .orthographic), size: size)
        model.click(at: .zero, tolerance: 1, modifiers: [])
        model.pointerMoved(to: ScreenPoint(300, 151), projector: projector)
        let chip = try #require(model.inferenceChip, "a pointer just below the start's height infers horizontal")
        #expect(chip == InferenceChip(kinds: [.horizontal], pointer: ScreenPoint(300, 151), in: size))
        #expect(chip == InferenceChip(kinds: [.horizontal], pointer: ScreenPoint(300, 151), in: size,
                                      avoiding: model.readoutChip), "the readout above the pointer is already clear")
        model.pointerMoved(to: nil, projector: projector)
        #expect(model.inferenceChip == nil)
    }

    func overlap(_ a: (origin: ScreenPoint, size: ViewportSize), _ b: (origin: ScreenPoint, size: ViewportSize)) -> Bool {
        a.origin.x < b.origin.x + b.size.width && b.origin.x < a.origin.x + a.size.width
            && a.origin.y < b.origin.y + b.size.height && b.origin.y < a.origin.y + a.size.height
    }

    /// Near the model area's bottom the readout stays above the pointer, where the glyphs would go up to; near its top
    /// the readout flips below, where the glyphs would sit. Either way they stack beyond it, never over it.
    @Test(arguments: [ScreenPoint(200, 290), ScreenPoint(200, 10), ScreenPoint(390, 290), ScreenPoint(390, 10)])
    func theChipKeepsClearOfTheReadout(_ pointer: ScreenPoint) throws {
        let size = ViewportSize(width: 400, height: 300)
        let readout = try #require(ReadoutChip(text: "20.0 mm · 0.0°", pointer: pointer, in: size))
        let chip = try #require(InferenceChip(kinds: [.horizontal], pointer: pointer, in: size, avoiding: readout))
        #expect(!overlap((chip.origin, chip.size), (readout.origin, readout.size)))
        #expect(chip.origin.y >= ReadoutChip.margin && chip.origin.y + chip.size.height <= 300 - ReadoutChip.margin)
    }

    /// The model places both chips while a line is drawn near the view's bottom and top edges.
    @Test func theModelKeepsBothChipsApart() throws {
        let model = makeModel(.line)
        let size = ViewportSize(width: 400, height: 300)
        let projector = ViewportProjector(pose: CameraPose(target: .zero, distance: 100, pitch: .pi / 2,
                                                           projection: .orthographic), size: size)
        model.click(at: .zero, tolerance: 1, modifiers: [])
        for pointer in [ScreenPoint(200.4, 292), ScreenPoint(200.4, 8)] {
            model.pointerMoved(to: pointer, projector: projector)
            let readout = try #require(model.readoutChip, "a line's length and angle")
            let chip = try #require(model.inferenceChip, "straight above or below the start infers vertical")
            #expect(chip.text == "Vertical")
            #expect(!overlap((chip.origin, chip.size), (readout.origin, readout.size)))
        }
    }

    @Test func theChipViewHoldsItsText() throws {
        let text: [SketchConstraintKind] = [.coincident, .pointOn, .tangent]
        let chip = try #require(InferenceChip(kinds: text, pointer: ScreenPoint(300, 300), in: ViewportSize(width: 1200, height: 700)))
        let scene = renderHeadless {
            ZStack(alignment: .topLeading) { InferenceChipView(chip: chip) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        #expect(scene.glyphs.count >= chip.text.filter { !$0.isWhitespace }.count - 1)
        for glyph in scene.glyphs {
            let minX = Double(glyph.bounds.origin.x) / 2
            let maxX = Double(glyph.bounds.origin.x + glyph.bounds.size.width) / 2
            #expect(minX >= chip.origin.x && maxX <= chip.origin.x + chip.size.width, "a glyph spills out")
        }
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
swift test --filter CreatorSketchEditorTests.InferenceGlyphTests
```

Expected: FAIL to compile: `value of type 'SketchPreview' has no member 'inferred'`.

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorSketchEditor/InferenceChip.swift`:

```swift
import CreatorViewport

/// Where the inferred constraints' glyphs sit, in viewport points (y down): one chip naming them ("Horizontal",
/// "Point on · Tangent"), `ReadoutChip.gap` below and right of the pointer; else below left, above right, above left
/// (near the model area's trailing side and bottom); else stacked `ReadoutChip.margin` beyond the readout's chip, on
/// its far side from the pointer. Never over the readout's chip (`readout`, placed first): a spot that would touch it
/// is skipped. Sized like the readout's chip (`ReadoutChip`'s height, character width and padding), never measured;
/// none when no spot fits in the model area.
public struct InferenceChip: Hashable, Sendable {
    public var text: String
    /// The chip's top-left corner.
    public var origin: ScreenPoint
    public var size: ViewportSize

    public init?(kinds: [SketchConstraintKind], pointer: ScreenPoint, in view: ViewportSize,
                 modelArea: ViewportInsets = ViewportInsets(), avoiding readout: ReadoutChip? = nil) {
        guard !kinds.isEmpty else { return nil }
        let text = kinds.map(\.title).joined(separator: " · ")
        let size = ViewportSize(width: Double(text.count) * ReadoutChip.characterWidth + 2 * ReadoutChip.padding,
                                height: ReadoutChip.height)
        let area = (left: modelArea.leading + ReadoutChip.margin, right: view.width - modelArea.trailing - ReadoutChip.margin,
                    top: modelArea.top + ReadoutChip.margin, bottom: view.height - modelArea.bottom - ReadoutChip.margin)
        let fits = { (p: ScreenPoint) in
            p.x >= area.left && p.x + size.width <= area.right && p.y >= area.top && p.y + size.height <= area.bottom
                && !(readout.map { Self.touches(p, size, $0) } ?? false)
        }
        guard let origin = Self.candidates(size, pointer: pointer, readout: readout).first(where: fits) else { return nil }
        self.text = text
        self.origin = origin
        self.size = size
    }

    /// The spots tried, in order: the four corners round the pointer, then beyond the readout's chip.
    private static func candidates(_ size: ViewportSize, pointer: ScreenPoint, readout: ReadoutChip?) -> [ScreenPoint] {
        let gap = ReadoutChip.gap
        let right = pointer.x + gap
        let left = pointer.x - gap - size.width
        let below = pointer.y + gap
        let above = pointer.y - gap - size.height
        var spots = [ScreenPoint(right, below), ScreenPoint(left, below), ScreenPoint(right, above), ScreenPoint(left, above)]
        if let readout {
            let beyond = readout.origin.y < pointer.y
                ? readout.origin.y - ReadoutChip.margin - size.height
                : readout.origin.y + readout.size.height + ReadoutChip.margin
            spots += [ScreenPoint(right, beyond), ScreenPoint(left, beyond)]
        }
        return spots
    }

    /// Whether a chip at `origin` of `size` would touch `readout` (closer than `ReadoutChip.margin`).
    private static func touches(_ origin: ScreenPoint, _ size: ViewportSize, _ readout: ReadoutChip) -> Bool {
        let m = ReadoutChip.margin
        return origin.x < readout.origin.x + readout.size.width + m && readout.origin.x < origin.x + size.width + m
            && origin.y < readout.origin.y + readout.size.height + m && readout.origin.y < origin.y + size.height + m
    }
}
```

**Replace the whole of** `Sources/CreatorSketchEditor/LineInference.swift` with:

```swift
import CreatorGeometry
import CreatorSketch

/// The constraint a line's end infers from its start (sketcher spec §8): tangent to an arc ending at the start
/// (`SketchEditorModel.lineInference`), else horizontal when the end is within the tolerance of the start's height,
/// else vertical when it's within it of the start's x. The end is snapped onto it.
enum LineInference: Hashable, Sendable {
    case horizontal
    case vertical
    case tangent(SketchEntityID)

    /// The horizontal or vertical inference for a line from `start` to `end`, and the end it snaps to; none when ⌘
    /// suppresses it.
    static func infer(from start: Vector2, to end: Vector2, tolerance: Double, suppressed: Bool) -> (LineInference?, Vector2) {
        guard !suppressed, (end - start).length > tolerance else { return (nil, end) }
        if abs(end.y - start.y) <= tolerance { return (.horizontal, Vector2(end.x, start.y)) }
        if abs(end.x - start.x) <= tolerance { return (.vertical, Vector2(start.x, end.y)) }
        return (nil, end)
    }

    /// The constraint button it matches, for its glyph.
    var kind: SketchConstraintKind {
        switch self {
        case .horizontal: .horizontal
        case .vertical: .vertical
        case .tangent: .tangent
        }
    }

    func constraint(on line: SketchEntityID) -> SketchConstraint {
        switch self {
        case .horizontal: .horizontal(line)
        case .vertical: .vertical(line)
        case .tangent(let arc): .tangent(line, arc)
        }
    }
}
```

**Modify** `Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`, replace:

```swift
        let next = rubberBand(to: p, landing: target, tolerance: tolerance, suppressed: suppressed)
        if preview != next { preview = next }
```

with:

```swift
        var next = rubberBand(to: p, landing: target, tolerance: tolerance, suppressed: suppressed)
        next.inferred = inferredConstraints(landing: target, tolerance: tolerance, suppressed: suppressed)
        if preview != next { preview = next }
```

**Replace the whole of** `Sources/CreatorSketchEditor/SketchEditorModel+Inference.swift` with:

```swift
import CreatorGeometry
import CreatorSketch

extension SketchEditorModel {
    /// What a line from `start` to the free point `end` infers, and where its end snaps: tangent to an arc that starts
    /// or ends at the line's start, when the end is within the tolerance of that tangent (sketcher spec §8: "tangent to
    /// the previous arc"; the newest such arc), else horizontal or vertical (`LineInference.infer`). Nothing when ⌘
    /// suppresses it.
    func lineInference(from start: SketchAnchor, to end: Vector2, tolerance: Double, suppressed: Bool) -> (LineInference?, Vector2) {
        if !suppressed, let tangent = tangent(at: start) {
            let offset = end - start.position
            let along = offset.x * tangent.direction.x + offset.y * tangent.direction.y
            let across = abs(offset.x * tangent.direction.y - offset.y * tangent.direction.x)
            if abs(along) > tolerance, across <= tolerance {
                return (.tangent(tangent.arc), start.position + tangent.direction * along)
            }
        }
        return LineInference.infer(from: start.position, to: end, tolerance: tolerance, suppressed: suppressed)
    }

    /// The constraints a click landing on `target` (`anchor`) would infer (sketcher spec §8: "a glyph previews each
    /// inferred constraint"): a new point shares an existing one (coincident) or is held on a curve (point on); a
    /// line's free end snaps tangent, horizontal or vertical. Clicks that place no point (a circle's radius, a 3-point
    /// arc's third point) infer nothing, and an arc's end only shares a point (its end is moved onto the radius
    /// otherwise). ⌘ (`suppressed`) leaves only coincident.
    func inferredConstraints(landing target: SketchAnchor, tolerance: Double, suppressed: Bool) -> [SketchConstraintKind] {
        switch drawState {
        case .idle:
            return tool.placesPoints ? Self.inferred(by: target) : []
        case .lineFrom(let start):
            guard case .free(let at) = target else { return Self.inferred(by: target) }
            return lineInference(from: start, to: at, tolerance: tolerance, suppressed: suppressed).0.map { [$0.kind] } ?? []
        case .arcAround, .arcThroughFrom:
            return Self.inferred(by: target)
        case .arcFrom:
            return target.point == nil ? [] : [.coincident]
        case .circleAround, .arcThrough:
            return []
        }
    }

    /// Coincident on a point, point on for a curve, nothing in free space.
    static func inferred(by anchor: SketchAnchor) -> [SketchConstraintKind] {
        switch anchor {
        case .existing: [.coincident]
        case .onCurve: [.pointOn]
        case .free: []
        }
    }

    /// The newest arc that starts or ends at `start`'s point, and its unit tangent there.
    private func tangent(at start: SketchAnchor) -> (arc: SketchEntityID, direction: Vector2)? {
        guard let point = start.point else { return nil }
        for id in sketch.entityIDs.reversed() {
            guard case .arc(let center, let from, let to)? = sketch.entities[id]?.kind, from == point || to == point,
                  let c = SketchOverlayBuilder.position(center, sketch, solution) else { continue }
            let radius = start.position - c
            let length = radius.length
            guard length > 1e-9 else { continue }
            return (id, Vector2(-radius.y / length, radius.x / length))
        }
        return nil
    }
}
```

**Create** `Sources/CreatorSketchEditor/SketchEditorModel+InferenceChip.swift`:

```swift
import CreatorViewport

extension SketchEditorModel {
    /// The glyphs of what the next click would infer, placed by the pointer on screen clear of the readout's chip
    /// (`InferenceChip`), or `nil` with nothing inferred or no pointer over the view.
    public var inferenceChip: InferenceChip? {
        guard let pointer = pointerOnScreen, !viewSize.isEmpty else { return nil }
        return InferenceChip(kinds: preview.inferred, pointer: pointer, in: viewSize, modelArea: modelArea,
                             avoiding: readoutChip)
    }
}
```

**Replace the whole of** `Sources/CreatorSketchEditor/SketchPreview.swift` with:

```swift
import CreatorGeometry

/// What the active tool shows before it commits: its rubber-band curves and the points it has placed, in plane
/// coordinates, and the constraints the next click would infer (their glyphs go by the pointer). Empty when nothing
/// is in progress.
public struct SketchPreview: Hashable, Sendable {
    public var curves: [PreviewCurve]
    public var points: [Vector2]
    /// What the next click would infer: coincident (on a point), point on (on a curve), horizontal, vertical or
    /// tangent (a line's end).
    public var inferred: [SketchConstraintKind]

    public init(curves: [PreviewCurve] = [], points: [Vector2] = [], inferred: [SketchConstraintKind] = []) {
        self.curves = curves
        self.points = points
        self.inferred = inferred
    }

    public static let none = SketchPreview()
}
```

**Create** `Sources/CreatorSketchEditor/Views/InferenceChipView.swift`:

```swift
import CreatorStyle
import MetalUI

/// The inferred constraints' chip framed where `InferenceChip` places it: their names in the selection's green on the
/// theme's glass, so it reads as a hint about the geometry rather than a measurement.
struct InferenceChipView: Component {
    let chip: InferenceChip
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let colors = SketchColors(themes)
        let shape = RoundedRectangle(cornerRadius: Pixels(6))
        return ProposalText(chip.text)
            .font(.caption)
            .foregroundStyle(colors.inferred)
            .frame(width: Pixels(Float(chip.size.width)), height: Pixels(Float(chip.size.height)))
            .background(colors.glass, in: shape)
            .overlay { shape.strokeBorder(colors.hairline, lineWidth: Pixels(1)) }
            .offset(x: Pixels(Float(chip.origin.x)), y: Pixels(Float(chip.origin.y)))
    }
}
```

**Modify** `Sources/CreatorSketchEditor/Views/PointerReadoutView.swift`, replace:

```swift
            if let chip = model.readoutChip { ReadoutChipView(chip: chip) }
        }
```

with:

```swift
            if let chip = model.readoutChip { ReadoutChipView(chip: chip) }
            if let chip = model.inferenceChip { InferenceChipView(chip: chip) }
        }
```

**Replace the whole of** `Sources/CreatorSketchEditor/Views/SketchColors.swift` with:

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
    /// Inferred constraints' glyphs: the selection's colour (the Sketch node's header green).
    var inferred: Color { colors.profileHeader.color }
    /// Floating chrome: the theme's glass and its hairline.
    var glass: Color { colors.glassFill.color }
    var hairline: Color { colors.glassStroke.color }
}
```

- [ ] **Step 4: Run the tests to see them pass**

```bash
swift test --filter CreatorSketchEditorTests.InferenceGlyphTests
```

Expected: every test passes.

- [ ] **Step 5: Run the full check**

Run the full check (above). Expected: no new warning, no lint violation, `exit 0`, 11 test runs, **1433** tests, no "recorded an issue" or "failed after" line.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorSketchEditor/InferenceChip.swift \
  Sources/CreatorSketchEditor/LineInference.swift \
  Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift \
  Sources/CreatorSketchEditor/SketchEditorModel+Inference.swift \
  Sources/CreatorSketchEditor/SketchEditorModel+InferenceChip.swift \
  Sources/CreatorSketchEditor/SketchPreview.swift \
  Sources/CreatorSketchEditor/Views/InferenceChipView.swift \
  Sources/CreatorSketchEditor/Views/PointerReadoutView.swift \
  Sources/CreatorSketchEditor/Views/SketchColors.swift \
  Tests/CreatorSketchEditorTests/InferenceGlyphTests.swift
git commit -m "feat(sketch): inference glyphs by the pointer"
```

### Task 8: Double-click a Sketch node to edit it

**Files:**
- Create: `Sources/CreatorEditor/EditorModel+DoubleClick.swift`, `Sources/CreatorEditor/NodeClick.swift`
- Modify: `Sources/CreatorEditor/EditorModel.swift` (two stored properties), `Sources/CreatorEditor/EditorModel+Pointer.swift` (`pointerReleased`: one line before its `switch`; `click(_:extending:)` is **not** touched, so multi-select's ⌘-click toggle merges beside it), **`Sources/CreatorApp/AppModel+Picking.swift` (`handle(_:)`'s `.editSketch` case: one guard)**
- Test: `Tests/CreatorEditorTests/DoubleClickTests.swift`, `Tests/CreatorEditorTests/Support/TestClock.swift`, `Tests/CreatorEditorTests/Support/EditorTestNodes.swift` (append), `Tests/CreatorAppTests/SketchDoubleClickTests.swift`

**Interfaces:**
- Consumes: `EditorModel.press(_ action: InspectorAction, on node: NodeID)` (S5a: records `inspectorRequest`, which `AppRoot` already hands to `AppModel.handle(_:)` → `beginSketch`); `NodeRegistry[typeID]`, `NodeDefinition.inspector`, `InspectorControl.button(title:action:)`; `EditorModel.currentPress` (`point`, `hit`, `modifiers`).
- Produces: `EditorModel.now: @MainActor () -> ContinuousClock.Instant` (public, injectable); `EditorModel.doubleClickInterval = Duration.milliseconds(400)` and `doubleClickSlop = 4.0` (the groups spec's "two primary clicks within 0.4 s and 4 pt with no modifiers", §6, so both tracks share one recogniser); `static let doubleClickActions: [InspectorAction] = [.editSketch]` (internal; the groups editor (C2) appends its "Edit Group" action, or adds a group-node branch to `doubleClickAction(for:)`); `public func nodeDoubleClicked(_ node: NodeID)` (presses the node's first inspector button in `doubleClickActions`) and internal `doubleClickAction(for:) -> InspectorAction?`; internal `pairClick(on:at:modifiers:)` and `lastNodeClick: NodeClick?`. A click with no modifiers on a node's body pairs with the one before; any modifier (⇧ extends, ⌘ toggles), a socket, empty canvas or any drag starts afresh. `AppModel.handle(_:)` ignores `.editSketch` while a sketch is open (Errata (S5b)). Test fixtures: `SketchTestNode`, `sketchTestRegistry`, `TestClock`.

- [ ] **Step 1: Write the failing tests**

Two plain clicks on one node, close in time and place, press its "Edit sketch" button; anything else only selects (Review Focus 5). The app tests pin the real Sketch node, and that a double click while a sketch is open changes nothing: the canvas still takes clicks in sketch mode, but the inspector's "Edit sketch" isn't reachable then, so a double click must not become a second way to restart or switch the sketch (dropping the stroke and the selection and re-framing the camera).

**Create** `Tests/CreatorAppTests/SketchDoubleClickTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor
@testable import CreatorViewport

/// Double-clicking the Sketch node opens its sketch (sketcher spec §8): the graph panel's double click presses the
/// real node's "Edit sketch" button, which the app turns into sketch mode as it does the button.
@MainActor
struct SketchDoubleClickTests {
    @Test func doubleClickingTheSketchNodeEntersSketchMode() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.editor.nodeDoubleClicked(box.sketch.id)
        let request = try #require(app.editor.inspectorRequest)
        #expect(request.action == .editSketch && request.node == box.sketch.id)
        app.handle(request)
        #expect(app.sketch?.node == box.sketch.id)
    }

    @Test func doubleClickingAnotherNodeAsksNothing() async {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.editor.nodeDoubleClicked(box.extrude.id)
        #expect(app.editor.inspectorRequest == nil)
        #expect(app.sketch == nil)
    }

    /// Errata (S5b): while a sketch is open, a double click on its own Sketch node or on another one changes nothing:
    /// the same session and editor, its stroke in progress, and the camera where the user panned it (a restart would
    /// look at the plane again).
    @Test func aDoubleClickWhileSketchingChangesNothing() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let other = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        await app.viewport.waitForAnimation()
        let session = try #require(app.sketch)
        let start = ScreenPoint(100, 100)
        app.viewport.dragChanged(from: start, to: ScreenPoint(180, 140), modifiers: [], button: .primary)
        app.viewport.dragEnded(from: start, at: ScreenPoint(180, 140), modifiers: [], button: .primary)
        session.editor.choose(.line)
        session.editor.click(at: Vector2(10, 10), tolerance: 1, modifiers: [])
        let stroke = session.editor.drawState
        let camera = app.viewport.pose
        for node in [box.sketch.id, other.sketch.id] {
            app.editor.nodeDoubleClicked(node)
            app.handle(try #require(app.editor.inspectorRequest))
            await app.viewport.waitForAnimation()
            #expect(app.sketch === session && app.sketch?.editor === session.editor)
            #expect(session.editor.drawState == stroke && stroke != .idle, "the line in progress is kept")
            #expect(app.viewport.pose == camera, "nothing looks at the plane again")
        }
    }
}
```

**Create** `Tests/CreatorEditorTests/DoubleClickTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Double-clicking a Sketch node opens its sketch (sketcher spec §8), as its "Edit sketch" button does: two clicks
/// with no modifiers on the same node, close together in time and place.
@MainActor
struct DoubleClickTests {
    func makeSketchEditor() -> (EditorModel, Node, Node, TestClock) {
        let sketch = testNode(SketchTestNode.self, id: 1, at: .zero, registry: sketchTestRegistry)
        let number = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0), registry: sketchTestRegistry)
        let editor = makeEditor([sketch, number], registry: sketchTestRegistry)
        let clock = TestClock()
        editor.now = { clock.now }
        return (editor, sketch, number, clock)
    }

    @Test func aDoubleClickOnASketchNodeAsksToEditIt() throws {
        let (editor, sketch, _, clock) = makeSketchEditor()
        let point = editor.screenPoint(in: sketch.id)
        editor.click(point)
        #expect(editor.inspectorRequest == nil, "one click only selects")
        clock.advance(by: .milliseconds(200))
        editor.click(point + Vector2(2, 1))
        let request = try #require(editor.inspectorRequest)
        #expect(request.node == sketch.id && request.action == .editSketch)
        #expect(editor.selection == [sketch.id])
    }

    @Test func aThirdClickStartsANewPair() {
        let (editor, sketch, _, clock) = makeSketchEditor()
        let point = editor.screenPoint(in: sketch.id)
        editor.click(point)
        editor.click(point)
        let first = editor.inspectorRequest?.serial
        clock.advance(by: .milliseconds(100))
        editor.click(point)
        #expect(editor.inspectorRequest?.serial == first, "the third click is the first of the next pair")
    }

    /// Review Focus 5: two clicks that aren't a double click (too slow, too far apart, on two nodes, a modifier held,
    /// or with a drag between) never open the sketch.
    @Test func clicksThatArentADoubleClickDoNothing() {
        let (editor, sketch, number, clock) = makeSketchEditor()
        let point = editor.screenPoint(in: sketch.id)
        editor.click(point)
        clock.advance(by: .milliseconds(450))
        editor.click(point)
        #expect(editor.inspectorRequest == nil, "too slow")
        clock.advance(by: .seconds(1))
        editor.click(point)
        editor.click(point + Vector2(6, 0))
        #expect(editor.inspectorRequest == nil, "too far apart")
        clock.advance(by: .seconds(1))
        editor.click(editor.screenPoint(in: number.id))
        editor.click(point)
        #expect(editor.inspectorRequest == nil, "two nodes")
        for modifiers: CanvasModifiers in [.shift, .command] {
            clock.advance(by: .seconds(1))
            editor.click(point, modifiers: modifiers)
            editor.click(point, modifiers: modifiers)
            #expect(editor.inspectorRequest == nil, "⇧ extends and ⌘ toggles the selection instead")
        }
        clock.advance(by: .seconds(1))
        editor.click(point)
        editor.drag(point, point + Vector2(40, 0))
        editor.click(point + Vector2(40, 0))
        #expect(editor.inspectorRequest == nil, "a drag between")
    }

    @Test func aDoubleClickOnAnotherNodeOnlySelectsIt() {
        let (editor, _, number, _) = makeSketchEditor()
        let point = editor.screenPoint(in: number.id)
        editor.click(point)
        editor.click(point)
        #expect(editor.inspectorRequest == nil)
        #expect(editor.selection == [number.id])
    }

    @Test func aDoubleClickOnEmptyCanvasDoesNothing() {
        let (editor, _, _, _) = makeSketchEditor()
        editor.click(Vector2(700, 600))
        editor.click(Vector2(700, 600))
        #expect(editor.inspectorRequest == nil)
    }

    /// The recogniser is generic: what a double click presses is looked up per node (the groups editor adds "Edit
    /// Group" to `doubleClickActions`).
    @Test func whatADoubleClickPressesIsPerNode() {
        let (editor, sketch, number, _) = makeSketchEditor()
        #expect(editor.doubleClickAction(for: sketch.id) == .editSketch)
        #expect(editor.doubleClickAction(for: number.id) == nil)
    }
}
```

**Modify** `Tests/CreatorEditorTests/Support/EditorTestNodes.swift`, replace:

```swift
let perNodeSocketTestRegistry = NodeRegistry([NumberTestNode.self, PerNodeSocketTestNode.self])
```

with:

```swift
let perNodeSocketTestRegistry = NodeRegistry([NumberTestNode.self, PerNodeSocketTestNode.self])

/// Mirrors the Sketch node's inspector: an "Edit sketch" button, which a double click also presses.
enum SketchTestNode: NodeDefinition {
    static let typeID = "editortest.sketch"
    static let displayName = "Sketch"
    static let category = NodeCategory.profile
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("profiles", .profile)]
    static let inspector = [InspectorSection(title: "Sketch", controls: [.button(title: "Edit sketch", action: .editSketch)])]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["profiles": .profile(.rectangle(width: 1, height: 1, plane: .xy))])
    }
}

/// The editor registry plus `SketchTestNode`, for the double-click tests.
let sketchTestRegistry = NodeRegistry([NumberTestNode.self, FilletTestNode.self, SketchTestNode.self])
```

**Create** `Tests/CreatorEditorTests/Support/TestClock.swift`:

```swift
// Test fixture file: a clock the double-click tests move by hand.

/// A settable time for `EditorModel.now`.
@MainActor
final class TestClock {
    var now = ContinuousClock.now

    func advance(by duration: Duration) {
        now = now.advanced(by: duration)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
swift test --filter CreatorEditorTests.DoubleClickTests
swift test --filter CreatorAppTests.SketchDoubleClickTests
```

Expected: FAIL to compile: `value of type 'EditorModel' has no member 'now'`.

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorEditor/EditorModel+DoubleClick.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Double-clicking a node (sketcher spec §8: "Enter by double-clicking a Sketch node"; the groups spec's §6 enters a
/// group the same way). The canvas's one zero-distance drag reports each click alone, without the click count
/// (docs/metalui-gaps.md S5-b, the double-click half of GI-a), so the model pairs them: a click with no modifiers on
/// the same node's body within `doubleClickInterval` and `doubleClickSlop` of the one before.
extension EditorModel {
    /// The longest gap between a double click's two clicks (the groups spec's 0.4 s, §6).
    public static let doubleClickInterval = Duration.milliseconds(400)
    /// How far apart a double click's two clicks may land, in screen points.
    public static let doubleClickSlop = 4.0
    /// The inspector buttons a double click presses; the first of them a node's inspector has wins. The groups
    /// editor adds its "Edit Group" action here.
    static let doubleClickActions: [InspectorAction] = [.editSketch]

    /// A press released without a drag, on `hit` at `point` with `modifiers` held: the second click with no modifiers
    /// on one node's body is a double click (`nodeDoubleClicked`); any other click on a body starts a new pair, and a
    /// socket, empty canvas or a modifier starts none.
    func pairClick(on hit: CanvasHit, at point: Vector2, modifiers: CanvasModifiers) {
        guard case .node(let node) = hit, modifiers.isEmpty else {
            lastNodeClick = nil
            return
        }
        let time = now()
        if let last = lastNodeClick, last.node == node, (point - last.point).length <= Self.doubleClickSlop,
           last.time.duration(to: time) <= Self.doubleClickInterval {
            lastNodeClick = nil
            nodeDoubleClicked(node)
        } else {
            lastNodeClick = NodeClick(node: node, point: point, time: time)
        }
    }

    /// A double click on `node`: presses what `doubleClickAction(for:)` finds (the Sketch node's "Edit sketch"),
    /// exactly as the button does; a node without one only stays selected.
    public func nodeDoubleClicked(_ node: NodeID) {
        if let action = doubleClickAction(for: node) { press(action, on: node) }
    }

    /// The first of `doubleClickActions` among `node`'s inspector buttons, if any.
    func doubleClickAction(for node: NodeID) -> InspectorAction? {
        guard let typeID = graph.nodes[node]?.typeID, let definition = registry[typeID] else { return nil }
        let buttons = definition.inspector.flatMap(\.controls).compactMap { control -> InspectorAction? in
            if case .button(_, let action) = control { action } else { nil }
        }
        return Self.doubleClickActions.first { buttons.contains($0) }
    }
}
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`, replace:

```swift
        guard let press = currentPress else { return }
        switch interaction {
        case nil: click(press.hit, extending: press.modifiers.contains(.shift))
```

with:

```swift
        guard let press = currentPress else { return }
        if interaction == nil { pairClick(on: press.hit, at: press.point, modifiers: press.modifiers) } else { lastNodeClick = nil }
        switch interaction {
        case nil: click(press.hit, extending: press.modifiers.contains(.shift))
```

**Modify** `Sources/CreatorEditor/EditorModel.swift`, replace:

```swift
    @ObservationIgnored var scrollGlideIgnored = false
```

with:

```swift
    @ObservationIgnored var scrollGlideIgnored = false
    /// The time now, for telling a double click from two clicks (`EditorModel+DoubleClick`); tests set their own.
    @ObservationIgnored public var now: @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now }
    /// The last plain click on a node: which, where on the canvas (screen points) and when.
    @ObservationIgnored var lastNodeClick: NodeClick?
```

**Create** `Sources/CreatorEditor/NodeClick.swift`:

```swift
import CreatorGeometry
import CreatorKernel

/// One plain click on a node's body, remembered so the next can be told a double click (`EditorModel+DoubleClick`).
struct NodeClick: Hashable, Sendable {
    var node: NodeID
    /// Where it was, in canvas-local screen points.
    var point: Vector2
    var time: ContinuousClock.Instant
}
```

**Modify** `Sources/CreatorApp/AppModel+Picking.swift`, replace:

```swift
        case .editSketch:
            beginSketch(for: request.node)
```

with:

```swift
        case .editSketch:
            // Only a double click on the graph canvas can ask while a sketch is open (the inspector shows the
            // sketch's lists then): it changes nothing, so the stroke, selection and camera stay (Errata (S5b)).
            guard sketch == nil else { return }
            beginSketch(for: request.node)
```

- [ ] **Step 4: Run the tests to see them pass**

```bash
swift test --filter CreatorEditorTests.DoubleClickTests
swift test --filter CreatorAppTests.SketchDoubleClickTests
```

Expected: every test passes.

- [ ] **Step 5: Run the full check**

Run the full check (above). Expected: no new warning, no lint violation, `exit 0`, 11 test runs, **1442** tests, no "recorded an issue" or "failed after" line.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorApp/AppModel+Picking.swift \
  Sources/CreatorEditor/EditorModel+DoubleClick.swift \
  Sources/CreatorEditor/EditorModel+Pointer.swift \
  Sources/CreatorEditor/EditorModel.swift \
  Sources/CreatorEditor/NodeClick.swift \
  Tests/CreatorAppTests/SketchDoubleClickTests.swift \
  Tests/CreatorEditorTests/DoubleClickTests.swift \
  Tests/CreatorEditorTests/Support/EditorTestNodes.swift \
  Tests/CreatorEditorTests/Support/TestClock.swift
git commit -m "feat(editor): double-click a Sketch node to edit it (gap S5-b)"
```

### Task 9: The inspector: hints and tool options

**Files:**
- Create: `Sources/CreatorSketchEditor/Views/ToolOptionsView.swift`
- Modify: `Sources/CreatorSketchEditor/SketchTool.swift` (`hint`), `DimensionText.swift` (`millimetres`), `Views/SketchInspector.swift` (whole files)
- Test: `Tests/CreatorSketchEditorTests/ToolOptionsViewTests.swift`

**Interfaces:**
- Consumes: Tasks 2 and 4's setters and `options`; S5a's `DimensionField(text:width:submit:)`, `SketchColors`.
- Produces: `public var SketchTool.hint: String?` (for the 3-point arc and the command tools); `DimensionText.millimetres(_:) -> String` ("5 mm"); `ToolOptionsView` under the refusal in `SketchInspector`: the hint, then Radius (Fillet) or Instances and Spacing (Pattern).

- [ ] **Step 1: Write the failing tests**

The toolbar holds every tool in order, the command tools and the 3-point arc say what to do, and the fillet and pattern options add their rows.

**Create** `Tests/CreatorSketchEditorTests/ToolOptionsViewTests.swift`:

```swift
import CreatorSketch
import MetalUI
import Testing
@testable import CreatorSketchEditor

/// The command tools in the toolbar and their hints and options in the inspector, drawn headless. Looks and keys are
/// human checks (group S5b).
@MainActor
struct ToolOptionsViewTests {
    @Test func theToolbarHoldsEveryTool() {
        let drawing: [SketchTool] = [.select, .line, .arc, .arcThreePoint, .circle, .point, .dimension]
        #expect(SketchTool.allCases == drawing + [.trim, .extend, .fillet, .mirror, .pattern])
        let model = SketchEditorModel(sketch: RectangleSketch().sketch, plane: .xy)
        model.choose(.pattern)
        #expect(!renderHeadless { SketchToolbar(model: model) }.glyphs.isEmpty)
    }

    @Test func theCommandToolsSayWhatToDo() {
        let hinted = SketchTool.allCases.filter { $0.hint != nil }
        #expect(hinted == [.arcThreePoint, .trim, .extend, .fillet, .mirror, .pattern])
    }

    /// The glyphs `text` draws (one per character that isn't a space).
    func glyphs(_ text: String) -> Int {
        text.filter { !$0.isWhitespace }.count
    }

    /// The fillet and pattern options add their rows under the hint: the inspector draws at least the hint's glyphs
    /// and the fields' labels' more than with no tool hint (the fields' values come on top); Mirror shows only its hint.
    @Test(arguments: [(SketchTool.fillet, ["Radius"]), (.pattern, ["Instances", "Spacing"])])
    func theOptionsAddRows(_ tool: SketchTool, labels: [String]) throws {
        let model = SketchEditorModel(sketch: RectangleSketch().sketch, plane: .xy)
        model.choose(.select)
        let plain = renderHeadless { SketchInspector(model: model) }.glyphs.count
        model.choose(tool)
        let withOptions = renderHeadless { SketchInspector(model: model) }.glyphs.count
        let hint = try #require(tool.hint)
        #expect(withOptions >= plain + glyphs(hint) + glyphs(labels.joined()), "the hint and the fields")
        model.choose(.mirror)
        let hintOnly = renderHeadless { SketchInspector(model: model) }.glyphs.count
        #expect(hintOnly == plain + glyphs(try #require(SketchTool.mirror.hint)), "only the hint")
    }

    @Test func aToolsOptionReadsInMillimetres() {
        #expect(DimensionText.millimetres(5) == "5 mm")
        #expect(DimensionText.millimetres(2.5) == "2.5 mm")
        #expect(DimensionText.millimetres(1234.5) == "1234.5 mm")
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
swift test --filter CreatorSketchEditorTests.ToolOptionsViewTests
```

Expected: FAIL to compile: `value of type 'SketchTool' has no member 'hint'`.

- [ ] **Step 3: Implement**

**Replace the whole of** `Sources/CreatorSketchEditor/DimensionText.swift` with:

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

    /// "12.5 mm": a size that belongs to no dimension (a tool's option).
    static func millimetres(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(locale))) mm"
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

**Replace the whole of** `Sources/CreatorSketchEditor/SketchTool.swift` with:

```swift
/// The sketch editor's tools (sketcher spec §8's toolbar): the drawing tools, Dimension, and the tools that change
/// what's drawn through `SketchCommands` (Trim, Extend, Fillet, Mirror, Pattern). Project follows in S5c.
public enum SketchTool: Hashable, Sendable, CaseIterable {
    /// Click to select (⇧ adds), drag a point to move it.
    case select
    /// Lines chain from click to click (L).
    case line
    /// Centre, start, end (A).
    case arc
    /// Start, end, then a point the arc passes through (A again, from Arc).
    case arcThreePoint
    /// Centre, then a point on the circle (C).
    case circle
    /// A lone point.
    case point
    /// Pick one or two entities; the kind of dimension follows from them (D).
    case dimension
    /// Click a curve to remove its span between the curves crossing it (T).
    case trim
    /// Click near a line's or an arc's end to extend it to the next curve it meets.
    case extend
    /// Click a corner where two lines meet to round it (`SketchToolOptions.filletRadius`). No key: F frames the sketch.
    case fillet
    /// With geometry selected, click a line to copy the selection mirrored about it.
    case mirror
    /// With geometry selected, click a point to copy the selection around it, or a line to copy it along the line
    /// (`SketchToolOptions.patternCount`, `patternSpacing`).
    case pattern

    /// The toolbar's title.
    public var title: String {
        switch self {
        case .select: "Select"
        case .line: "Line"
        case .arc: "Arc"
        case .arcThreePoint: "3-Point Arc"
        case .circle: "Circle"
        case .point: "Point"
        case .dimension: "Dimension"
        case .trim: "Trim"
        case .extend: "Extend"
        case .fillet: "Fillet"
        case .mirror: "Mirror"
        case .pattern: "Pattern"
        }
    }

    /// What to do with the tool, for the inspector; `nil` for the drawing tools, whose rubber band says it.
    public var hint: String? {
        switch self {
        case .trim: "Click the part of a curve to remove, between the curves crossing it."
        case .extend: "Click a line or an arc near the end to extend to the next curve."
        case .fillet: "Click a corner where two lines meet."
        case .mirror: "Select the geometry, then click the line to mirror it about."
        case .pattern: "Select the geometry, then click a point to copy it around, or a line to copy it along."
        case .arcThreePoint: "Click the start, the end, then a point the arc passes through."
        case .select, .line, .arc, .circle, .point, .dimension: nil
        }
    }

    /// Whether a click places a point (the rubber band then marks where it would land).
    var placesPoints: Bool {
        switch self {
        case .line, .arc, .arcThreePoint, .circle, .point: true
        case .select, .dimension, .trim, .extend, .fillet, .mirror, .pattern: false
        }
    }

    /// Whether the tool acts on a curve, so the pointer picks the curve under it even over one of its points.
    var picksCurves: Bool {
        switch self {
        case .trim, .extend, .mirror: true
        case .select, .line, .arc, .arcThreePoint, .circle, .point, .dimension, .fillet, .pattern: false
        }
    }
}
```

**Replace the whole of** `Sources/CreatorSketchEditor/Views/SketchInspector.swift` with:

```swift
import CreatorStyle
import MetalUI

/// The inspector while sketching (sketcher spec §8): the degrees-of-freedom readout or the problem, a refused
/// command's reason, the active tool's hint and options, the constraint buttons, the dimensions with their name and value fields, "Expose as input" and
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
            ToolOptionsView(model: model)
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

**Create** `Sources/CreatorSketchEditor/Views/ToolOptionsView.swift`:

```swift
import CreatorStyle
import MetalUI

/// The active tool's hint and settings in the inspector: the Fillet tool's radius, the Pattern tool's instance count
/// and spacing. Typed values go through the model, which refuses what isn't a size or a count; a refused entry snaps
/// back (`DimensionField`).
struct ToolOptionsView: Component {
    let model: SketchEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let colors = SketchColors(themes)
        let options = model.options
        return VStack(alignment: .leading, spacing: Pixels(4)) {
            if let hint = model.tool.hint {
                Text(hint).font(.caption).foregroundStyle(colors.secondary)
            }
            if model.tool == .fillet {
                HStack(spacing: Pixels(6)) {
                    Text("Radius").font(.callout).foregroundStyle(colors.primary)
                    DimensionField(text: DimensionText.millimetres(options.filletRadius), width: 80) { model.setFilletRadius($0) }
                }
            }
            if model.tool == .pattern {
                HStack(spacing: Pixels(6)) {
                    Text("Instances").font(.callout).foregroundStyle(colors.primary)
                    DimensionField(text: "\(options.patternCount)", width: 48) { model.setPatternCount($0) }
                    Text("Spacing").font(.callout).foregroundStyle(colors.primary)
                    DimensionField(text: DimensionText.millimetres(options.patternSpacing), width: 80) { model.setPatternSpacing($0) }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

```bash
swift test --filter CreatorSketchEditorTests.ToolOptionsViewTests
```

Expected: every test passes.

- [ ] **Step 5: Run the full check**

Run the full check (above). Expected: no new warning, no lint violation, `exit 0`, 11 test runs, **1446** tests, no "recorded an issue" or "failed after" line.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorSketchEditor/DimensionText.swift \
  Sources/CreatorSketchEditor/SketchTool.swift \
  Sources/CreatorSketchEditor/Views/SketchInspector.swift \
  Sources/CreatorSketchEditor/Views/ToolOptionsView.swift \
  Tests/CreatorSketchEditorTests/ToolOptionsViewTests.swift
git commit -m "feat(sketch): tool hints and options in the inspector"
```

### Task 10: Docs: errata, CLAUDE.md, roadmap, gap S5-b, human checks, handoff

**Files:**
- Modify: `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md` (append Errata (S5b)), `CLAUDE.md` (project state, `CreatorEditor` and `CreatorSketchEditor` bullets), `docs/superpowers/roadmap.md` (row 6), `docs/metalui-gaps.md` (append S5-b), `docs/verification/human-checks.md` (append group S5b), `docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md` (append S5b → S5c)

**Interfaces:**
- Consumes: every name above. Produces: nothing new in code; the spec erratum is the binding record of this plan's choices.

- [ ] **Step 1: Write the docs**

**Modify** `CLAUDE.md`, replace:

````markdown
The binding spec is `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`; milestone
plans live in `docs/superpowers/plans/`. M0 (OCCT probe), M1 (graph engine), M2 (OCCT kernel), M3 (the 26 nodes), S3 (profile holes) and S4 (the Sketch and Plane from Face nodes) are done. S5a (the sketch editor in the viewport: sketch mode, drawing, constraints, dimensions, live solve) code is done; its human checks (group S5) are pending; S5b (Project, New sketch on face, trim/fillet/mirror/pattern tools) is next. M4 (viewport) code is done; its human checks (group V in `docs/verification/human-checks.md`) are pending. M5 (graph panel and inspector) code is done; its human checks (group M5 in `docs/verification/human-checks.md`) are pending.
M6 (app shell) code is done; its human checks (group M6) are pending.
````

with:

````markdown
The binding spec is `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`; milestone
plans live in `docs/superpowers/plans/`. M0 (OCCT probe), M1 (graph engine), M2 (OCCT kernel), M3 (the 26 nodes), S3 (profile holes) and S4 (the Sketch and Plane from Face nodes) are done. S5a (the sketch editor in the viewport: sketch mode, drawing, constraints, dimensions, live solve) code is done; its human checks (group S5) are pending. S5b (trim, extend, fillet, mirror and pattern tools, 3-point arcs, point-on and tangent inference with glyphs, double-click to edit) code is done; its human checks (group S5b) are pending; S5c (Project, New sketch on face, dimension labels in the view, region fill) is next. M4 (viewport) code is done; its human checks (group V in `docs/verification/human-checks.md`) are pending. M5 (graph panel and inspector) code is done; its human checks (group M5 in `docs/verification/human-checks.md`) are pending.
M6 (app shell) code is done; its human checks (group M6) are pending.
````

**Modify** `CLAUDE.md`, replace:

````markdown
  views are thin MetalUI `Component`s. Depends on Graph/Kernel/Geometry, CreatorStyle and MetalUI — **not** on `CreatorNodes`.
  Its input (MetalUI C7 gestures, and the key and focus stopgaps) lives only in `GraphPanelInput`.
- `CreatorSketchEditor`: the sketch editor (sketcher spec §8). `@MainActor @Observable SketchEditorModel` holds the
````

with:

````markdown
  views are thin MetalUI `Component`s. Depends on Graph/Kernel/Geometry, CreatorStyle and MetalUI — **not** on `CreatorNodes`.
  Its input (MetalUI C7 gestures, and the key and focus stopgaps) lives only in `GraphPanelInput`. A double click on
  a node (two plain clicks on its body at most `EditorModel.doubleClickInterval`, 0.4 s as the groups spec's §6 says,
  not macOS's 500 ms default, and `doubleClickSlop`, 4 points, apart, timed by the injectable `now`; gap S5-b) presses
  its first inspector button in `doubleClickActions` ("Edit sketch"; `nodeDoubleClicked(_:)`). While a sketch is open
  the app ignores it (`AppModel.handle(_:)`'s guard).
- `CreatorSketchEditor`: the sketch editor (sketcher spec §8). `@MainActor @Observable SketchEditorModel` holds the
````

**Modify** `CLAUDE.md`, replace:

````markdown
  `ViewportOverlay` and the pointer readout (`pointerReadout`, while drawing or dragging a point; placed by
  `ReadoutChip`, drawn by its `PointerReadoutView`, which the app puts over the viewport). Graph-free: every edit is
  a `SketchCommit` (the whole sketch, solved and remembered) through `events.committed`, which the host stores.
  Depends on CreatorSketch, CreatorViewport, CreatorGeometry, CreatorStyle and MetalUI only. Its keys are toolbar
  button shortcuts (L, A, C, D, X, ⌫, ⌦, ⏎, Esc; ⌦ and Esc are hidden buttons), which run before the graph panel's
  `onInput` keys; the Delete button and the hidden ⌦ one are never disabled, so ⌫ and ⌦ never fall through to deleting
````

with:

````markdown
  `ViewportOverlay` and the pointer readout (`pointerReadout`, while drawing or dragging a point; placed by
  `ReadoutChip`, drawn by its `PointerReadoutView`, which the app puts over the viewport, with the inference glyphs'
  `InferenceChip`). The command tools (Trim, Extend, Fillet, Mirror, Pattern) run `SketchCommands` on a click and show
  a refused command's message as `refusal`; their settings are `SketchToolOptions`. A click within the pick radius of
  a curve (not a point) holds a new point on it (point-on); a line leaving an arc's end snaps tangent; ⌘ suppresses
  both, never a shared point. Graph-free: every edit is
  a `SketchCommit` (the whole sketch, solved and remembered) through `events.committed`, which the host stores.
  Depends on CreatorSketch, CreatorViewport, CreatorGeometry, CreatorStyle and MetalUI only. Its keys are toolbar
  button shortcuts (L, A (again: 3-point arc), C, D, T, X, ⌫, ⌦, ⏎, Esc; ⌦ and Esc are hidden buttons; Fillet has no
  key because F frames the sketch), which run before the graph panel's
  `onInput` keys; the Delete button and the hidden ⌦ one are never disabled, so ⌫ and ⌦ never fall through to deleting
````

**Modify** `docs/metalui-gaps.md`, replace:

````markdown
  tap modifiers (GI-a), and modifiers on hover or SwiftUI's `onModifierKeysChanged(mask:initial:_:)`.
````

with:

````markdown
  tap modifiers (GI-a), and modifiers on hover or SwiftUI's `onModifierKeysChanged(mask:initial:_:)`.

## Hit by the sketch editor (S5b), 2026-10-09

- **S5-b. A drag's value has no click count, so the graph canvas can't see a double click.** Sketcher spec §8: a
  double click on a Sketch node opens its sketch. The canvas's clicks come from its one
  `DragGesture(minimumDistance: 0)` (GI-a: a tap's value has no modifiers), whose `Value` has no click count, though
  MetalUI's platform event has one (`MouseEvent.clickCount`, AppKit's, which honours the user's double-click speed).
  `SpatialTapGesture(count: 2)` recognises a double tap, but beside the zero-distance drag the two compete in the
  gesture arena (whether `.simultaneousGesture` lets both recognise can't be checked from a client without a headless
  window, M6-e), and its sequence waits MetalUI's fixed 0.33 s (`tapSequenceDeferral`), not the user's setting.
  Stopgap: `EditorModel+DoubleClick` pairs two plain clicks on one node itself, at most 0.4 s
  (`doubleClickInterval`) and 4 points (`doubleClickSlop`) apart, with an injectable clock. The values are the groups
  spec's (`2026-10-09-selection-groups-comments-design.md` §6: "two primary clicks within 0.4 s and 4 pt with no
  modifiers"), not macOS's 500 ms default, so the groups editor shares this one recogniser. **The same request as the
  groups spec's "Canvas double-click (GI-a, MetalUI C16)" (§8)**: one MetalUI request, C16, covers both; S5-b is this
  file's record of it. Wanted: `clickCount` on `DragGesture.Value` (the press's `MouseEvent.clickCount`), as
  SwiftUI-on-AppKit apps read `NSEvent.clickCount`; then the model reads the count, the user's double-click speed is
  honoured, and the stopgap goes. Human check S5b-7 records it. Sent to the MetalUI session with this entry.
````

**Modify** `docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md`, replace:

````markdown
  modifiers), one MetalUI request.
````

with:

````markdown
  modifiers), one MetalUI request.

## S5b → S5c (plan `docs/superpowers/plans/2026-10-09-sketcher-s5b.md`)
- Done in S5b (sketcher spec Errata (S5b)): Trim, Extend, Fillet, Mirror and Pattern tools; 3-point arcs; point-on
  and tangent inference with their glyph chip; double-click to edit (gap S5-b's stopgap in `EditorModel`).
- Project (S5c): as in "S5a → S5b" above. Point-on inference already snaps onto projected edges
  (`SketchPicker.nearestPoint(on:to:)`), so a projection only has to land in the sketch.
- "New sketch on face" (S5c): offered only outside sketch mode (the face menu is empty while sketching, Errata (S5a)).
- Dimension labels in the view and the region fill (S5c) need a viewport overlay label API (projected with the
  camera every frame, like `handleLabels()`) and filled overlay triangles (a renderer pipeline; `GPUDataTests`).
- Pattern construction (connectors, spokes) is still drawn as any construction; telling it apart needs a marker in
  the sketch model (CreatorSketch) or the editor remembering what a pattern added.
````

**Modify** `docs/superpowers/roadmap.md`, replace:

````markdown
|---|---|---|---|
| 6 | Constraint sketcher: Sketch node, 2D editor, pure-Swift constraint solver | 🔄 spec `2026-10-08-constraint-sketcher-design.md`; S3 ✅ merged; S1+S2 ✅ merged (CreatorSketch: solver, regions, commands); S4 ✅ merged 2026-10-09 (Sketch node, Plane from Face, projection, format 4; human check S4-1 pending); S5a (editor in the viewport: sketch mode, drawing, constraints, dimensions, live solve; plan `2026-10-09-sketcher-s5-editor.md`) ✅ code done, human checks S5 pending; S5b (Project, New sketch on face, double-click to edit, trim/fillet/mirror/pattern tools, inference glyphs and tangent/point-on inference, dimension labels in the view, region fill) ⏳ | Rules for S4 regions: holes sorted, loops counter-clockwise, deterministic start segment (spec §5) |
| 7 | Patterns, fields, nested data trees, surface textures, lattices | 💬 | After the slice |
````

with:

````markdown
|---|---|---|---|
| 6 | Constraint sketcher: Sketch node, 2D editor, pure-Swift constraint solver | 🔄 spec `2026-10-08-constraint-sketcher-design.md`; S3 ✅ merged; S1+S2 ✅ merged (CreatorSketch: solver, regions, commands); S4 ✅ merged 2026-10-09 (Sketch node, Plane from Face, projection, format 4; human check S4-1 pending); S5a (editor in the viewport: sketch mode, drawing, constraints, dimensions, live solve; plan `2026-10-09-sketcher-s5-editor.md`) ✅ code done, human checks S5 pending; S5b (trim/extend/fillet/mirror/pattern tools, 3-point arcs, tangent and point-on inference with glyphs, double-click to edit; plan `2026-10-09-sketcher-s5b.md`) ✅ code done, human checks S5b pending; S5c (Project, New sketch on face, dimension labels in the view, region fill) ⏳ | Rules for S4 regions: holes sorted, loops counter-clockwise, deterministic start segment (spec §5) |
| 7 | Patterns, fields, nested data trees, surface textures, lattices | 💬 | After the slice |
````

**Modify** `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md`, replace:

````markdown
  either curve); other constraints on it (on a curve, midpoint, fix) don't make it shared.
````

with:

````markdown
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
````

**Modify** `docs/verification/human-checks.md`, replace:

````markdown
  a rectangle's corner, a circle's centre or a free point: its position. Release: the chip goes. **Observed:**
````

with:

````markdown
  a rectangle's corner, a circle's centre or a free point: its position. Release: the chip goes. **Observed:**

## Group S5b — the sketch editor's tools and inference (S5b)

**Status: NOT RUN.** Run `swift run MetalCreatorApp`. Add a Sketch, wire its `profiles` into an Extrude (10 mm) and
that into an Output, select the Sketch and press "Edit sketch".

- [ ] **S5b-1 Trim and Extend.** Draw two crossing lines. Press T and click one line's end beyond the crossing: that
  span goes, one ⌘Z brings it back. Choose Extend and click near the free end of a short line that points at another
  line: it grows to meet it. Extend a line that meets nothing: the inspector says "There is nothing to extend Line 1
  to." and nothing changes. Pinned headless by `ModifyToolTests`. **Observed:**
- [ ] **S5b-2 Fillet.** Draw a rectangle, choose Fillet: the inspector shows "Click a corner where two lines meet."
  and Radius "5 mm". Click a corner: it rounds, with a radius dimension. Type 500 in Radius and click another corner:
  "Radius 500 mm is too large for this corner (max ≈ …)." and nothing changes. F still frames the sketch. Pinned by
  `FilletToolTests`. **Observed:**
- [ ] **S5b-3 Mirror.** Draw a construction line (X) and a shape beside it. With Select, click the shape's lines,
  choose Mirror and click the construction line: a mirrored copy appears; drag an original corner: its copy follows,
  mirrored. With nothing selected, Mirror says "Select the geometry to mirror first." Pinned by `MirrorToolTests`.
  **Observed:**
- [ ] **S5b-4 Pattern.** Draw a small circle and a point beside it; select the circle, choose Pattern, set Instances
  to 6 and click the point: six circles around it. Select one, click a line: copies along it, Spacing apart (type 15).
  Instances "1" is refused in words. Pinned by `PatternToolTests`. **Observed:**
- [ ] **S5b-5 3-point arcs.** Press A twice: "3-Point Arc ✓". Click a start, an end, then move the pointer: the arc
  bends through it, the readout shows the chord, then "R … mm · …°"; click: the arc is drawn. A third click in line
  with the ends draws nothing. Press A again: back to the centre arc. Pinned by `ThreePointArcTests`. **Observed:**
- [ ] **S5b-6 Inference and glyphs.** With Line, move over an existing line: the rubber band's point jumps onto it and
  a green "Point on" chip sits below right of the pointer; click there and drag the line away with Select: the point
  stays on it. Over a point: "Coincident". From an arc's end, draw along its tangent: "Tangent", and the line stays
  tangent when the arc is dragged. Near the right or bottom of the view, the chip moves left or up. Pinned by
  `InferenceTests`, `InferenceGlyphTests`. **Observed:**
- [ ] **S5b-7 Double-click to edit.** Finish the sketch. Double-click the Sketch node on the graph canvas: sketch mode
  opens as with "Edit sketch". Two slow clicks (0.4 s apart or more), or a double click on another node, only
  select. While sketching, draw a line's first point and double-click the Sketch node: nothing changes (the line in
  progress, the selection and the view stay). Known (gap S5-b): the system's double-click speed isn't honoured; the
  interval is a fixed 0.4 s (the groups spec's). Pinned by `DoubleClickTests`, `SketchDoubleClickTests`.
  **Observed:**
- [ ] **S5b-8 The toolbar fits.** At the default window size, every tool (Select … Pattern), Construction, Delete and
  Finish are visible in the top bar, none clipped. Not pinned (a toolbar's width against the window's is measured only
  by eye). **Observed:**
````

- [ ] **Step 2: Send gap S5-b to the MetalUI session**

The project sends every new MetalUI gap to the MetalUI session (the groups spec's §8 says so too). Find it with `ListAgents` and send it the S5-b entry verbatim with `SendMessage`, saying that it is the groups spec's "Canvas double-click (GI-a, MetalUI C16)", so one request covers both. If no MetalUI session is listed, say so in the task's report instead; the entry stays as written. Never edit `../MetalUI`.

- [ ] **Step 3: Run the full check**

Run the full check (above). Expected: as after Task 9 (**1446** tests); `swiftlint` doesn't read Markdown, so this only confirms nothing else moved.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md \
  docs/metalui-gaps.md \
  docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md \
  docs/superpowers/roadmap.md \
  docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md \
  docs/verification/human-checks.md
git commit -m "docs(sketch): S5b errata, gap S5-b, human checks S5b, CLAUDE.md and roadmap"
```

## S5c — the rest of S5 (next plan)

Scope, so nothing from the sketcher spec's §8 is lost (each is also in the handoff's "S5b → S5c" section, Task 10):

1. **Project (P)**: `CreatorSketchEditor` gains CreatorKernel; a Project tool that declines its clicks (`ViewportTool.clicked` returns false) so the viewport's ID-buffer pick reaches the host as `ViewportEvents.clicked(.edge)` (the ghosted model stays in the ID pass); the host turns the edge into a curve on the sketch plane (`EdgeProjection` made public from CreatorNodes, or a `SketchNode` entry point), the editor adds a `.projected` entity with a unique `reference`, and `SketchStore` writes `NodeSetting.projection(reference)` = `.edgePicks(topology.picks(for: [edge]))` and wires the edge's solid (its `producer(of:)`) into `references` in the same batch. A click on a face, or an edge that can't be projected, is refused in the inspector's words. A suspended projection drawn red. It is a tool, so it fits the camera lock: no menu, nothing turns. Point-on inference already snaps onto projected edges (Task 6).
2. **"New sketch on face"**: a face context-menu item, offered only outside sketch mode (the face menu is empty while sketching, Errata (S5a)) and only on planar faces; one batch adds Plane from Face (`face` = `.facePick(topology.facePick(for:))`, wired from the face's solid) and a Sketch whose plane is `.wired`, wired from it; then sketch mode opens on the face's plane computed from the face itself (its result isn't evaluated yet; `refreshSketch` takes the wired plane once it is).
3. **Dimension labels in the view**: a viewport overlay label API (world-anchored text, projected with the camera every frame like `handleLabels()`, hidden during animations as those are) and the editor's labels at each dimension.
4. **The faint green region fill**: filled overlay triangles (a renderer pipeline with blending, its MSL and `GPUDataTests`), and the regions (`SketchRegions.find`) triangulated with their holes.
5. **Gap S5-a / GI-a follow-ups** once MetalUI reports tap and hover modifiers: ⌘ suppresses inference on clicks and hovers; ⇧-click extends the selection (plain clicks replace it). Gap S5-b's follow-up: read the click count and drop `EditorModel+DoubleClick`'s pairing.
6. Pattern construction told apart from the user's own construction (handoff "S5 (editor)"), if wanted.
7. Debounced (150 ms) downstream evaluation while typing, if live typing is added.

## Self-review

- **Spec coverage (S5b).** §8 toolbar Trim T (Task 1), Fillet (Task 2; F stays Frame: the camera-lock erratum is the later user decision), Mirror (Task 3), Pattern (Task 4), Arc centre / 3-point on A (Task 5); §3's Extend, which §8's table lacks, as a keyless tool (Task 1); §3's commands each one undo step through S5a's commit, refusals in plain words (Tasks 1–4, `apply`); §8 inference "tangent to the previous arc, and point-on for projected geometry" (Task 6, point-on widened to every curve, Errata (S5b)) with "a glyph previews each inferred constraint" (Task 7); §8 "enter by double-clicking a Sketch node" (Task 8); §10 editor tests: tool state machine (Tasks 1–5), inference rules (Tasks 6–7), undo granularity (every command test counts commits). The S5a plan's S5b list items 1, 2, 6 and the modifier follow-ups are S5c (scope above, with the reason in "Why S5b is split again"); its item 8 (debounce) stays deferred.
- **Placeholder scan.** Every step carries its code or exact command, and every count is a number checked by the run below; no template token or TBD remains. The code blocks were applied as written (below), so no step refers to code that isn't shown.
- **Type consistency.** Checked by applying every block in order in a scratch copy: `modify(at:tolerance:)` is extended by one `case` per tool (Tasks 2–4) and `click`'s single command `case` grows with it; `SketchToolOptions` gains fields in Task 4 only; `SketchAnchor.onCurve` (Task 6) is used by `inferred(by:)` (Task 7); `SketchPreview(curves:points:inferred:)` keeps S5a's call sites compiling through its default; `EditorModel.now`/`nodeDoubleClicked(_:)` (Task 8) match the app test; `anchor(at:tolerance:suppressed:)` (Task 6) has no default, so every drawing tool's call passes ⌘ on.
- **Review Focus.** Each of the five lines has its test in its owning task (Tasks 1, 2, 5, 6, 8).
- **Camera lock.** Nothing here turns the camera or adds a menu: the command tools are clicks on the sketch plane, F stays Frame, and double-click goes through the same `beginSketch` as "Edit sketch" (its look-at onto the plane is the one S5a already makes).

## Verification record (how this plan was checked)

This revision's final text was applied task by task, in order, by a script that runs each **Create**, **Replace the whole of** and **Modify** block (each Modify anchor had to match exactly once), to a scratch copy of master **2e64c96** (exported with `git archive`) beside a read-only clone of `../MetalUI` at **2155f1e** (LF-b's fix 9ad2254 and C10 included). After each task: `swift build --build-tests` printed no warning or error (master's `ContextMenuTests.swift:96` one appears only when that file recompiles; it didn't); `swiftlint lint --strict --quiet` printed nothing; `swift test` exited 0 with 11 "Test run with" lines and no "recorded an issue", "failed after" or known-issue line. Task 6's Step 2 was checked too: with `InferenceTests.swift` alone, exactly the three named tests record issues and the other four pass. The tree after Task 10 matched, file for file, a second application of the committed text. Test totals (the sum of the "Test run with N tests" lines; master 2e64c96 is 1390):

| After task | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| Tests | 1396 | 1401 | 1405 | 1412 | 1417 | 1424 | 1433 | 1442 | 1446 | 1446 |
| Over master | +6 | +11 | +15 | +22 | +27 | +34 | +43 | +52 | +56 | +56 |

An earlier revision was checked the same way at fdef111 with MetalUI 0b400b4 (1368 tests then); its table no longer applies.

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-09-sketcher-s5b.md`. Recommended: **subagent-driven** (a fresh implementer and reviewer per task), because Tasks 1–7 extend one model in layers whose interfaces each later task relies on (the `modify` dispatch, `SketchAnchor`, `SketchPreview`), and Task 8 touches `EditorModel` files the multi-select and groups-core tracks share (see "Files shared with other tracks").
