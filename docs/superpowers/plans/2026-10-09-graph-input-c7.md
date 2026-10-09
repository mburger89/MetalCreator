# Graph Panel and App Input on MetalUI C7 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the graph panel's and the app shell's input stopgaps with MetalUI C7's input APIs: Shift-click and ⇧/⌥-drag read the press's own modifiers, two-finger scroll pans the canvas (momentum honoured), ⌘-scroll and pinch zoom about the pointer, a pan shows the closed hand, and the dock's resize edge shows a resize cursor.

**Architecture:** All behaviour stays in `@MainActor @Observable EditorModel`, testable without a window: new entry points take plain values (`Vector2`, `CanvasModifiers`, `CanvasScrollPhase`) and `GraphPanelInput` turns MetalUI gesture values into them; `GraphCanvas` and `GraphPanel` only attach the modifiers. The canvas keeps one zero-distance `DragGesture` for clicks and drags (its values now carry the modifiers), gains `.onScrollWheel`, a `MagnifyGesture` and `.pointerStyle`, and `GraphPanelInput` stops tracking the window's modifier events. The keys are untouched (key scoping is MetalUI C9).

**Tech Stack:** Swift 6.4 (language mode 6, strict concurrency), SwiftPM, Swift Testing, MetalUI at `../MetalUI` master `67a579e` (C7 `c62d6ba`: `DragGesture.Value.modifiers`, `SpatialTapGesture`, `MagnifyGesture`, `.onScrollWheel` with `ScrollEvent.phase`/`momentumPhase`/`location`, `.pointerStyle(_:)` with `.grabActive`, `.columnResize`, `.rowResize`).

**Spec:** `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (§6.2 graph panel interactions, §9 MetalUI gaps, and every Errata section; Errata (M5)'s "inline value fields … Revisit when MetalUI C7 lands" is answered by Key decision 8). MetalUI's final API names: `../MetalUI/docs/superpowers/2026-10-08-input-apis-decisions.md` (`CI-A` … `CI-AL`). The stopgaps being replaced: `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md` ("From M5": the C7 swap points; "From M6": the resize edge's cursor) and `docs/metalui-gaps.md` (M5-e, M5-f, gap 4's zero-distance drag as a click-location stand-in, "Cursor for the dock's resize edge"). The pattern followed: `docs/superpowers/plans/2026-10-09-viewport-input-c7.md` (merged on master `d9fedec`).

**Files shared with other tracks** (graph-input runs beside sketcher-s5, naming-merged-faces and themes; everything else here is inside `Sources/CreatorEditor`, `Tests/CreatorEditorTests` and the two new `CreatorApp` lines below):
- `CLAUDE.md` and `AGENTS.md` — two paragraphs each (the `CreatorEditor` bullet's last line; the "Graph panel input stopgaps" paragraph). Every track edits these.
- `docs/metalui-gaps.md` — the C7 status paragraph, the M5-e, M5-f, EP-b and resize-cursor entries, and a new section "Hit by the graph panel's C7 adoption" inserted just before "## Node-drag performance". Every track may log gaps.
- `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md` — four bullets in "From M4", "From M5" and "From M6".
- `docs/verification/human-checks.md` — a new group GI inserted just before "## Group M5". Every track adds a group.
- `Sources/CreatorEditor/EditorModel.swift` — three stored properties and the press bookkeeping. sketcher-s5 (writing `Sketch.remember` back is the editor's job) may edit this file too.
- `Sources/CreatorEditor/GraphPanel.swift`, `Sources/CreatorEditor/GraphPanelHeader.swift` (one doc line), `Sources/CreatorApp/PanelResizeHandle.swift`, `Tests/CreatorEditorTests/GraphPanelRenderTests.swift` — the themes track may touch their colours.
- `Sources/CreatorApp/AppInput.swift` — one doc-comment line. sketcher-s5 may add viewport sketch keys here.
- **Not touched:** `Sources/CreatorViewport` (and its tests), `Sources/CreatorApp/AppRoot.swift` (nothing there needs to change), `Sources/GraphPanelPreview` (it gets every change through `GraphCanvas` and `GraphPanel`; its `install(on:)` call stays right), `Package.swift`, the spec and `docs/superpowers/roadmap.md` (when merging, mark the roadmap row "C7 adoption" (graph part) done and add to the spec's Errata (M5) the one-line answer of Key decision 8).

## Global Constraints

- Platforms are `.macOS(.v26)` (spec Errata (M0–M1)); `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`: data races are compile errors.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), never XCTest.
- Models are `@MainActor @Observable`; behaviour lives in models, views are thin MetalUI glue (CLAUDE.md, `CreatorEditor` bullet).
- One type per file; no force unwraps; no GCD; FormatStyle for user-facing numbers.
- `CreatorEditor` depends on Graph/Kernel/Geometry, CreatorStyle and MetalUI, **not** on `CreatorNodes` (CLAUDE.md).
- MetalUI gaps are logged in `docs/metalui-gaps.md` and fixed in MetalUI, never worked around here (spec §9: "The app never patches around a gap in a way that would have to be undone"). Never modify `../MetalUI`.
- Editor geometry is computed by `NodeLayout`, never measured; hit testing is the model's (`EditorModel.hitTest`).
- `swift build --build-tests` adds no warning (master's only compiler warning is `ContextMenuTests.swift`'s pre-existing "'underPointer' mutated after capture by sendable closure"; OCCT `ld: warning`s are expected); `swift test` passes (exit 0, and no line says "recorded an issue" or "failed after"); `swiftlint lint --strict` reports zero violations.
- Never edit `Package.swift`'s MetalUI path. Run every command from the worktree root.
- Keep the key bindings as they are: `GraphKeyBindings`, `GraphPanelInput.keymap` (↑, ↓, Tab), the viewport's `!Panel` keys and `AppInput.handleAction`'s hover veto for + and − (key scoping is MetalUI C9, not merged).

## Key decisions

1. **Clicks stay on the canvas's one zero-distance `DragGesture`; it is no longer a stand-in.** Shift-click extends the selection, so a click must know whether ⇧ was held, and `SpatialTapGesture.Value` has only `location` (`CI-B`; SwiftUI's has no more). A `DragGesture(minimumDistance: 0)`'s first change is the press itself, with the press's modifiers (`CI-G`: "the press for a `minimumDistance: 0` first change"), and its end is the release with its location, so every value the canvas needs is C7's. The viewport's shape (a `SpatialTapGesture` inside a 5-point drag) would lose Shift-click; tracking modifiers from the window again would be the stopgap this plan deletes. `GraphPanelInput.spatialTapGesture()` and `dragValueModifiers(_:)` are deleted, `canvasGesture()` builds the drag itself, and the missing tap modifiers are new gap **GI-a**. The model keeps telling a click from a drag (`EditorModel.dragThreshold`, 3 points).
2. **Modifiers are arguments, never state.** `EditorModel.modifiers` is deleted. `pointerDragged(from:to:modifiers:)`, `pointerReleased(from:at:modifiers:)` and `pointerPressed(at:modifiers:)` take the value's modifiers (default `[]`, so callers that don't care are unchanged). A click reads the modifiers held **at the press** (recorded with the press; spec wording "Shift-click"); a drag reads those held **when it starts** (the change that crosses the threshold), so ⌥ pressed just after the button still duplicates (spec §6.2 "⌥-drag duplicates"); later changes don't alter a drag under way. `GraphPanelInput.handle(_:)` no longer reads `.modifiersChanged` or a key's modifiers. A press that lost its release is dropped with its modifiers (`ensurePress`, as before).
3. **Scroll.** `.onScrollWheel` on the canvas claims every scroll over it. A plain scroll pans by the delta (`offset + delta`, the direction MetalUI's canvas demo and a scroll view's content move), the glide after a flick included (C7 item 1: "momentum is honoured for canvas panning"). ⌘-scroll zooms about `ScrollEvent.location` by `exp(Δy × 0.01)` per event (`EditorModel.scrollZoomPerPoint`, the viewport's rate and sign, so a wheel step is about 10%), within `CanvasTransform.zoomRange`; its glide is ignored. A trackpad scroll (phases) zooms or pans as it **began** (`EditorModel.scrollZooms`, latched at `.began` and cleared at `.ended`), so pressing ⌘ part-way through a pan can't turn it into a zoom; a zoom's glide is ignored from its `.ended` until its momentum ends (`scrollGlideIgnored`, cleared by `.momentumEnded`, the next scroll's `.began`/`.changed` or a wheel step), so letting go of ⌘ during the glide can't turn it into a pan. MetalUI sends each scroll event to what is under the pointer at that event (gap GI-b), so a scroll that began elsewhere can reach the canvas with a `.changed` and no `.began`: it is taken up as it is at that event (⌘ held or not) and latched from there, never inheriting the last canvas scroll's mode. A wheel step (no phase, and every SDL scroll) decides by itself. ⌃-scroll is not bound (the demo's ⌃ is for a Windows touchpad's pinch; this app is macOS only). Nothing settles: the transform is view state, written per event exactly as a drag pan writes it.
4. **The panel's chrome is opaque to the pointer.** The glass is only painted, and MetalUI gives a painted view no hitbox (divergence 141: "wrap it in `.contentShape` with a handler"), so over the header's gaps, the glass padding or the refusal line the topmost opaque hitbox was the viewport's `MetalView`: a scroll zoomed the part, a pinch (whose target is `topmostOpaqueHitbox` at the event, as a press's is, `CI-D` item 1) zoomed it too, and a press or hover picked or highlighted a face. A wheel-only region would stop the scroll alone (it is not opaque). So `GraphPanel` draws an opaque backdrop behind its glass, exactly as the palette does (gap EP-b): a `Color.clear` with `.contentShape(Rectangle())`, an empty `DragGesture(minimumDistance: 0)` and a claiming `.onScrollWheel { _ in true }` (kept, though `applyScroll` already claims an unclaimed wheel over an opaque cover, so the claim doesn't rest on that fallback). It stops scroll, pinch, press and hover over the chrome. The canvas, the header's buttons and the library's `ScrollView` are drawn above it and are opaque themselves, so they still get their own input, and the backdrop is their sibling, not their ancestor, so its empty drag joins none of their arenas. Every primary press still reaches `Window.onInput` (MetalUI claims none), so a press on the chrome still closes the palette.
5. **Pinch** is a `MagnifyGesture` on the canvas: the cumulative magnification zooms the transform the pinch began with, about `startLocation` (`CI-C` item 3), clamped below at 0.05 (`EditorModel.minimumMagnification`; MetalUI's `1 + Σ` can reach 0 or below) and to `zoomRange`. A pinch under way that changes at another centre, or finds the canvas moved since its last change (a drag pan, a scroll, +/−, a dock change: `CanvasPinch.applied` is no longer the transform), lost its end (VI-a), so it starts afresh from the canvas as it is. No `RotateGesture` (spec §6.2 gives the canvas none).
6. **Scroll and pinch close the add-node palette** when they move the canvas, as a canvas press does: the palette adds at the canvas point it opened over (spec Errata (editor polish)) and stores it as a canvas-local screen point.
7. **Cursors.** A closed hand (`.grabActive`) while a drag pans the canvas (`EditorModel.canvasCursor`, from `interaction`, so it is read where the canvas already observes); MetalUI keeps a pressed element's style while the pointer leaves it (`CI-H` item 6). The arrow otherwise: moving nodes, wiring and box selection keep it, and so does a canvas at rest, because an open hand over empty canvas only would need a hit test on every hover move and would re-render the canvas each time. The dock's resize edge shows `.columnResize` (left dock) or `.rowResize` (bottom dock).
8. **Inline node values stay read-only text** (spec Errata (M5) "Revisit when MetalUI C7 lands"; carry-over From M5). C7 is pointer input; it changes none of the reasons a canvas field is unsound: Tab is a window-wide keymap binding that opens the palette while the pointer is over the canvas (gap M5-b, key scoping is MetalUI C9), so in a node's field it would open the palette instead of moving focus; the canvas's layers are `allowsHitTesting(false)` and every hit is the model's, so a field would add a second hit test under the canvas's scale that must agree with `EditorModel.hitTest` at every zoom, and MetalUI gives a field's press to the field before any gesture, so a node could no longer be dragged by its rows; and a field per unwired input on every node adds to the whole-window rebuild each drag step pays (PERF-b). Recorded in the carry-over note (Task 5), to revisit with C9 and PERF-b.
9. **Kept:** the +/− keys and the header's zoom buttons (`EditorModel.zoom(in:)`), every key binding, `AppInput`'s hover veto (its doc now cites M4-a and M5-b instead of M5-f), `GraphPanelInput.install(on:)` for the preview, and the focus and palette stopgaps.

## Review Focus

The five inputs the spec implies but doesn't spell out that are most likely to bite, each pinned by a test in the task that owns the code:

1. **A modifier that isn't the press's** — ⇧ held for an earlier click, held on a press whose release was lost, or reported by the window while the pointer was elsewhere (or let go while the app was inactive) — must not make the next click extend the selection or the next drag box-select — `aModifierHeldForOnePressDoesntCarryIntoTheNext`, `aLostPressTakesItsModifiersWithIt`, `aShiftPressedOnlyForTheReleaseDoesntExtend`, `modifierChangesAreNeitherClaimedNorTracked` (Task 1).
2. **The glide after a ⌘-scroll** must not pan the canvas the user just zoomed, even once ⌘ is let go — `aZoomScrollsGlideIsIgnored`, `aZoomsGlideIsIgnoredOnlyUntilItsMomentumEnds`; ⌘ pressed part-way through a pan must not jump into a zoom — `aTrackpadScrollZoomsOrPansAsItBegan`; and a scroll that began elsewhere must not inherit the last canvas scroll's zoom — `aScrollThatBeganElsewhereIsTakenUpAsItIsNow` (Task 2).
3. **A scroll or pinch while the add-node palette is open** would move the canvas point it adds at, so the node would land somewhere the user never pointed — `aScrollThatMovesTheCanvasClosesThePalette` (Task 2), `aPinchClosesThePalette` (Task 3).
4. **Extreme input** — a hard pinch-in (magnification ≤ 0), a run of large ⌘-scrolls, a non-finite delta or location — must leave a finite transform inside `zoomRange`, not spring back or poison the saved view state — `aHardPinchInHoldsInsteadOfSpringingBack`, `aNonFinitePinchChangesNothing` (Task 3), `theScrollZoomStaysInRange`, `aNonFiniteScrollChangesNothing` (Task 2).
5. **A gesture MetalUI drops without an end** (VI-a): a pan whose release was lost must not keep the closed hand past the next press, and a pinch whose end was lost must not pull the next pinch back to where it began, nor undo a pan or zoom made since — `aPanThatLostItsReleaseLosesTheHandAtTheNextPress` (Task 4), `aPinchThatLostItsEndDoesntPullTheNextOneBack`, `aPinchThatLostItsEndDoesntUndoWhatMovedTheCanvasSince` (Task 3).

## Risks left open

- **The view glue isn't exercised by a test** (no headless MetalUI window, gap M6-e): `GraphCanvas`'s gesture, wheel and cursor lines, `GraphPanel`'s opaque backdrop and `PanelResizeHandle`'s cursor compile and render headless but only group GI drives them.
- **The pan's direction and the zoom's sign** follow MetalUI's canvas demo and the viewport; GI-1 and GI-2 confirm the feel.
- **A glide that drifts off the canvas** stops there and can scroll the library or the inspector (gap GI-b, MetalUI `CI-AD`).
- **Each scroll or pinch event writes the canvas transform into the document's view state**, as each drag-pan step already does, and so wakes `AppModel`'s scene observation (carry-over From M6: it reads `editor.dock`); a trackpad sends 60–120 events a second. Measure with M7's 50-node pan.
- **A pinch that lost its end, then one at the same centre with nothing moving the canvas in between**, zooms from the lost pinch's start (VI-a): the model can't tell it from the lost one going on. Anything that moved the canvas in between starts it afresh.
- **A zoom's glide whose momentum end went elsewhere** (the pointer left the canvas mid-glide) keeps `scrollGlideIgnored` until the next scroll's `.began`/`.changed` or a wheel step, so a glide drifting in from a pan elsewhere in that gap is ignored rather than panning. Safe (nothing moves); gap GI-b's latch would end it.
- **A scroll over the inspector's chrome** (outside its own scroll view) still reaches the viewport beneath; the inspector isn't this plan's.

---

## File structure

| File | Task | Responsibility |
|---|---|---|
| `Sources/CreatorEditor/EditorModel.swift` (modify) | 1, 2, 3 | Drop `modifiers`; the press's modifiers; `scrollZooms`, `scrollGlideIgnored`, `pinchStart` |
| `Sources/CreatorEditor/EditorModel+Pointer.swift` (modify) | 1 | Modifiers as arguments: a click reads the press's, a drag those when it starts |
| `Sources/CreatorEditor/CanvasModifiers.swift` (modify) | 1 | Doc: from the gesture's value |
| `Sources/CreatorEditor/GraphPanelInput.swift` (modify) | 1–4 | No modifier tracking; `canvasGesture()` from values; `scrolled(_:)`, `scrollPhase(of:)`, `pinchGesture()` |
| `Sources/CreatorEditor/CanvasScrollPhase.swift` (create) | 2 | Step, began, changed, ended, momentum, momentum ended |
| `Sources/CreatorEditor/EditorModel+Scroll.swift` (create) | 2 | `scrolled(by:at:modifiers:phase:)`, `scrollZoomPerPoint` |
| `Sources/CreatorEditor/GraphCanvas.swift` (modify) | 2, 3, 4 | `.onScrollWheel`, the pinch, `.pointerStyle` |
| `Sources/CreatorEditor/GraphPanel.swift` (modify) | 2 | The chrome is opaque to the pointer (an opaque backdrop) |
| `Sources/CreatorEditor/CanvasPinch.swift` (create) | 3 | The transform and centre a pinch began with, and the transform it last left |
| `Sources/CreatorEditor/EditorModel+Pinch.swift` (create) | 3 | `pinchChanged(magnification:centre:)`, `pinchEnded()`, `minimumMagnification` |
| `Sources/CreatorEditor/CanvasCursor.swift`, `CanvasCursor+MetalUI.swift`, `EditorModel+Cursor.swift` (create) | 4 | `canvasCursor`; → MetalUI `PointerStyle` |
| `Sources/CreatorApp/PanelResizeHandle.swift` (modify) | 4 | Resize cursors |
| Tests: `PressModifierTests` (1, create), `PointerTests`, `GraphPanelRenderTests`, `Support/PointerTestSupport` (1), `GraphPanelInputTests` (1, 2), `CanvasScrollTests` (2, create), `CanvasPinchTests` (3, create), `CanvasCursorTests` (4, create) in `Tests/CreatorEditorTests`; `PanelResizeCursorTests` (4, create) in `Tests/CreatorAppTests` | | |
| `docs/metalui-gaps.md`, carry-over note, `docs/verification/human-checks.md`, `CLAUDE.md`, `AGENTS.md`, `AppInput.swift` and `GraphPanelHeader.swift` doc lines (modify) | 5 | What C7 closed; GI-a, GI-b; the inline-values decision; group GI |

Test counts (master: **1085**; `CreatorEditorTests` 174, `CreatorAppTests` 74): after Task 1 **1093**, 2 **1105**, 3 **1111**, 4 **1116**, 5 **1116** (master + 31). To total `swift test`'s per-bundle lines: `swift test 2>&1 | grep "Test run with" | awk '{s+=$5} END {print s}'`. A run passes only if it exits 0 and no line says "recorded an issue" or "failed after": `swift test 2>&1 | grep -E "recorded an issue|failed after"` prints nothing.

---

### Task 1: Modifiers come from the press

C7 item 5 / gap M5-e (`CI-G`): `DragGesture.Value.modifiers`. Replaces `GraphPanelInput.dragValueModifiers(_:)`, `GraphPanelInput.spatialTapGesture()` and the `.modifiersChanged` tracking (Key decisions 1, 2).

**Files:**
- Modify: `Sources/CreatorEditor/EditorModel.swift`, `Sources/CreatorEditor/EditorModel+Pointer.swift`, `Sources/CreatorEditor/CanvasModifiers.swift`, `Sources/CreatorEditor/GraphPanelInput.swift`
- Test: `Tests/CreatorEditorTests/PressModifierTests.swift` (create), `Tests/CreatorEditorTests/GraphPanelInputTests.swift`, `Tests/CreatorEditorTests/PointerTests.swift`, `Tests/CreatorEditorTests/GraphPanelRenderTests.swift`, `Tests/CreatorEditorTests/Support/PointerTestSupport.swift`

**Interfaces:**
- Consumes: MetalUI `DragGesture(minimumDistance:)`, `DragGesture.Value.modifiers: Modifiers` (the press's at a zero-distance drag's first change, `CI-G`), `DragGesture.Value.init(startLocation:location:modifiers:)` (tests).
- Produces:
  - On `EditorModel`: `public func pointerDragged(from start: Vector2, to location: Vector2, modifiers: CanvasModifiers = [])`, `public func pointerReleased(from start: Vector2, at location: Vector2, modifiers: CanvasModifiers = [])`, `public func pointerPressed(at screen: Vector2, modifiers: CanvasModifiers = [])`; internal `beginPress(at:modifiers:)` and `currentPress: (point: Vector2, hit: CanvasHit, modifiers: CanvasModifiers)?`. **Removed:** `public var modifiers: CanvasModifiers`.
  - On `GraphPanelInput`: `public func canvasGesture() -> DragGesture` (zero minimum distance), internal `canvasChanged(_ value: DragGesture.Value)` and `canvasEnded(_ value: DragGesture.Value)`, `public static func canvasModifiers(_:) -> CanvasModifiers` (unchanged). **Removed:** `spatialTapGesture()`, `dragValueModifiers(_:)`, `canvasChanged(from:to:)`, `canvasEnded(from:at:)`; `handle(_:)` no longer reads `.modifiersChanged`.
  - Test support: `EditorModel.click(_:modifiers:)`, `EditorModel.drag(_:_:modifiers:)` (modifiers default `[]`).

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorEditorTests/PressModifierTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// The canvas reads the modifiers from the press itself (MetalUI C7's `DragGesture.Value.modifiers`, spec §6.2):
/// a click reads those held at the press, a drag those held when it starts, and nothing carries over from one
/// press to the next.
@MainActor
struct PressModifierTests {
    let a = testNode(NumberTestNode.self, id: 1, at: .zero)
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))

    @Test func aShiftClickReadsTheModifiersHeldAtThePress() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let point = editor.screenPoint(in: b.id)
        editor.pointerDragged(from: point, to: point, modifiers: .shift)
        editor.pointerReleased(from: point, at: point, modifiers: [])
        #expect(editor.selection == [a.id, b.id], "⇧ let go before the release still extends")
    }

    @Test func aShiftPressedOnlyForTheReleaseDoesntExtend() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let point = editor.screenPoint(in: b.id)
        editor.pointerDragged(from: point, to: point, modifiers: [])
        editor.pointerReleased(from: point, at: point, modifiers: .shift)
        #expect(editor.selection == [b.id])
    }

    /// A press that reports only its end (no change first) reads the release's modifiers.
    @Test func aClickWithNoChangeReadsItsReleasesModifiers() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let point = editor.screenPoint(in: b.id)
        editor.pointerReleased(from: point, at: point, modifiers: .shift)
        #expect(editor.selection == [a.id, b.id])
    }

    @Test func aModifierHeldForOnePressDoesntCarryIntoTheNext() {
        let editor = makeEditor([a, b])
        editor.click(editor.screenPoint(in: a.id), modifiers: .shift)
        editor.click(editor.screenPoint(in: b.id))
        #expect(editor.selection == [b.id])
        editor.drag(Vector2(600, 600), Vector2(640, 620))
        #expect(editor.transform.offset == Vector2(40, 20), "a plain drag on empty canvas pans, not box-selects")
    }

    /// ⌥ pressed after the button went down, but before the press moved far enough to drag, still duplicates.
    @Test func optionPressedBeforeTheDragStartsDuplicates() {
        let editor = makeEditor([a])
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start, modifiers: [])
        editor.pointerDragged(from: start, to: start + Vector2(1, 0), modifiers: .option)
        #expect(editor.interaction == nil)
        editor.pointerDragged(from: start, to: start + Vector2(0, 60), modifiers: .option)
        guard case .duplicating? = editor.interaction else { Issue.record("expected ghosts"); return }
    }

    /// What a drag does is decided when it starts; a modifier pressed later doesn't change it.
    @Test func aModifierPressedMidDragDoesntChangeTheDrag() {
        let editor = makeEditor([a])
        editor.pointerDragged(from: Vector2(600, 600), to: Vector2(600, 600))
        editor.pointerDragged(from: Vector2(600, 600), to: Vector2(620, 600))
        editor.pointerDragged(from: Vector2(600, 600), to: Vector2(650, 600), modifiers: .shift)
        guard case .panning? = editor.interaction else { Issue.record("expected a pan"); return }
        #expect(editor.transform.offset == Vector2(50, 0))
    }

    /// A press whose release was lost (the window resigned mid-drag) takes its ⇧ with it.
    @Test func aLostPressTakesItsModifiersWithIt() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start, modifiers: .shift)
        editor.click(editor.screenPoint(in: b.id))
        #expect(editor.selection == [b.id])
    }
}
```

Replace the contents of `Tests/CreatorEditorTests/Support/PointerTestSupport.swift` with:

```swift
// Test fixture file: pointer gestures for the editor tests.
import CreatorGeometry
@testable import CreatorEditor

@MainActor
extension EditorModel {
    /// A click (press and release without moving) at a canvas-local screen point, with `modifiers` held
    /// throughout, as the canvas's zero-distance drag reports one.
    func click(_ point: Vector2, modifiers: CanvasModifiers = []) {
        pointerDragged(from: point, to: point, modifiers: modifiers)
        pointerReleased(from: point, at: point, modifiers: modifiers)
    }

    /// A press at `start`, a move to `end` and a release there, with `modifiers` held throughout.
    func drag(_ start: Vector2, _ end: Vector2, modifiers: CanvasModifiers = []) {
        pointerDragged(from: start, to: start, modifiers: modifiers)
        pointerDragged(from: start, to: end, modifiers: modifiers)
        pointerReleased(from: start, at: end, modifiers: modifiers)
    }
}
```

Replace the contents of `Tests/CreatorEditorTests/GraphPanelInputTests.swift` with:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

@MainActor
struct GraphPanelInputTests {
    /// A canvas drag value as MetalUI reports it, in canvas-local points.
    func value(_ start: Vector2, _ location: Vector2, _ modifiers: Modifiers = []) -> DragGesture.Value {
        DragGesture.Value(startLocation: Point(x: Pixels(Float(start.x)), y: Pixels(Float(start.y))),
                          location: Point(x: Pixels(Float(location.x)), y: Pixels(Float(location.y))),
                          modifiers: modifiers)
    }

    /// The window's modifier events are neither claimed nor kept: a press reads its own (MetalUI C7), so a ⇧
    /// reported while the pointer was elsewhere can't make the next click extend the selection.
    @Test func modifierChangesAreNeitherClaimedNorTracked() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let input = GraphPanelInput(model: editor)
        #expect(!input.handle(.modifiersChanged([.shift, .option])))
        let point = editor.screenPoint(in: b.id)
        input.canvasChanged(value(point, point))
        input.canvasEnded(value(point, point))
        #expect(editor.selection == [b.id])
    }

    /// The canvas gesture starts at the press (zero minimum distance), and each value's modifiers reach the model:
    /// the press's ⇧ extends the click, and control is dropped (the canvas binds nothing to it).
    @Test func theCanvasGestureReadsThePressModifiersFromItsValues() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let input = GraphPanelInput(model: editor)
        #expect(input.canvasGesture().minimumDistance == Pixels(0))
        let point = editor.screenPoint(in: b.id)
        input.canvasChanged(value(point, point, [.shift, .control]))
        input.canvasEnded(value(point, point))
        #expect(editor.selection == [a.id, b.id])
        #expect(GraphPanelInput.canvasModifiers([.shift, .option, .command, .control]) == [.shift, .option, .command])
    }

    @Test func anOptionDragThroughTheGestureDuplicates() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let editor = makeEditor([a])
        let input = GraphPanelInput(model: editor)
        let start = editor.screenPoint(in: a.id)
        input.canvasChanged(value(start, start, .option))
        input.canvasChanged(value(start, start + Vector2(0, 80), .option))
        input.canvasEnded(value(start, start + Vector2(0, 80), .option))
        #expect(editor.graph.nodes.count == 2)
        #expect(editor.graph.nodes[a.id]?.position == .zero)
    }

    @Test func mappedKeysAreRunAndClaimed() {
        let node = testNode(NumberTestNode.self, id: 1, at: .zero)
        let editor = makeEditor([node])
        editor.selection = [node.id]
        let input = GraphPanelInput(model: editor)
        let delete = KeyEvent(charactersIgnoringModifiers: "\u{7f}", characters: "\u{7f}", timestamp: 1)
        #expect(input.handle(.keyDown(delete)))
        #expect(editor.graph.nodes.isEmpty)
        let letter = KeyEvent(charactersIgnoringModifiers: "q", characters: "q", timestamp: 2)
        #expect(!input.handle(.keyDown(letter)))
    }

    @Test func hoverTracksThePointer() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        input.hover(.active(Point(x: Pixels(12), y: Pixels(34))))
        #expect(editor.pointerLocation == Vector2(12, 34))
        input.hover(.ended)
        #expect(editor.pointerLocation == nil)
    }

    /// The window keymap runs before a focused field's editing keys, so the palette's arrows
    /// are bound there. Only the mapping is pinned here: tests can't build a real `Window`.
    @Test func paletteArrowsAreKeymapActionsOnlyWhileThePaletteIsOpen() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        #expect(GraphPanelInput.keymap.bindings.map(\.spelling) == ["up", "down", "tab"])
        #expect(GraphPanelInput.keymap.bindings.prefix(2).allSatisfy { $0.action is PaletteMove })
        // Closed: unhandled, so MetalUI passes the arrow on to a focused field.
        #expect(!input.handleAction(PaletteMove(step: 1)))
        editor.openPalette()
        #expect(input.handleAction(PaletteMove(step: 1)))
        #expect(editor.palette?.highlighted == 1)
        #expect(input.handleAction(PaletteMove(step: -1)))
        #expect(editor.palette?.highlighted == 0)
    }

    /// Tab is a keymap action because Tab focus traversal runs before `onInput` whenever anything
    /// focusable is on screen (the inspector always is). Unclaimed, it falls through to traversal
    /// or, while hidden, to `GraphShowButton`'s shortcut. Only the mapping is pinned here.
    @Test func tabIsAKeymapActionThatOpensThePaletteOnlyOverTheVisibleCanvas() throws {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        let binding = try #require(GraphPanelInput.keymap.bindings.last)
        #expect(binding.spelling == "tab")
        #expect(binding.action is GraphTab)
        // Pointer off the canvas: unclaimed, so focus traversal gets Tab.
        #expect(!input.handleAction(GraphTab()))
        #expect(editor.palette == nil)
        input.hover(.active(Point(x: Pixels(40), y: Pixels(30))))
        #expect(input.handleAction(GraphTab()))
        #expect(editor.palette?.screenPosition == Vector2(40, 30))
        // Palette already open: unclaimed (no second palette).
        #expect(!input.handleAction(GraphTab()))
        editor.closePalette()
        // Hidden: unclaimed, so `GraphShowButton`'s Tab shortcut shows the panel.
        editor.toggleHidden()
        #expect(!editor.isPanelVisible)
        #expect(!input.handleAction(GraphTab()))
        #expect(editor.palette == nil)
    }

    @Test func aCanvasPressReleasesTextFocusOncePerPress() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        var releases = 0
        input.releaseTextFocus = { releases += 1 }
        input.canvasChanged(value(Vector2(10, 10), Vector2(10, 10)))
        input.canvasChanged(value(Vector2(10, 10), Vector2(40, 10)))
        input.canvasEnded(value(Vector2(10, 10), Vector2(40, 10)))
        #expect(releases == 1)
        input.canvasEnded(value(Vector2(5, 5), Vector2(5, 5)))
        #expect(releases == 2)
        #expect(editor.transform.offset == Vector2(30, 0))
    }
}
```

In `Tests/CreatorEditorTests/PointerTests.swift`, replace:

```swift
        editor.click(editor.screenPoint(in: b.id))
        #expect(editor.selection == [b.id])
        editor.modifiers = .shift
        editor.click(editor.screenPoint(in: a.id))
        #expect(editor.selection == [a.id, b.id])
        editor.click(editor.screenPoint(in: a.id))
        #expect(editor.selection == [b.id])
    }
```

with:

```swift
        editor.click(editor.screenPoint(in: b.id))
        #expect(editor.selection == [b.id])
        editor.click(editor.screenPoint(in: a.id), modifiers: .shift)
        #expect(editor.selection == [a.id, b.id])
        editor.click(editor.screenPoint(in: a.id), modifiers: .shift)
        #expect(editor.selection == [b.id])
    }
```

In `Tests/CreatorEditorTests/PointerTests.swift`, replace:

```swift
        editor.selection = [a.id]
        editor.modifiers = .shift
        editor.click(Vector2(600, 600))
        #expect(editor.selection == [a.id])
        editor.modifiers = []
        editor.click(Vector2(600, 600))
```

with:

```swift
        editor.selection = [a.id]
        editor.click(Vector2(600, 600), modifiers: .shift)
        #expect(editor.selection == [a.id])
        editor.click(Vector2(600, 600))
```

In `Tests/CreatorEditorTests/PointerTests.swift`, replace:

```swift
        let editor = makeEditor([a])
        editor.modifiers = .option
        let start = editor.screenPoint(in: a.id)
        editor.drag(start, start + Vector2(2, 1))
```

with:

```swift
        let editor = makeEditor([a])
        let start = editor.screenPoint(in: a.id)
        editor.drag(start, start + Vector2(2, 1), modifiers: .option)
```

In `Tests/CreatorEditorTests/PointerTests.swift`, replace:

```swift
        editor.selection = [c.id]
        editor.modifiers = .shift
        let start = Vector2(380, -20)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: Vector2(420, 20))
```

with:

```swift
        editor.selection = [c.id]
        let start = Vector2(380, -20)
        editor.pointerDragged(from: start, to: start, modifiers: .shift)
        editor.pointerDragged(from: start, to: Vector2(420, 20), modifiers: .shift)
```

In `Tests/CreatorEditorTests/PointerTests.swift`, replace:

```swift
        editor.pointerReleased(from: start, at: Vector2(420, 20))
        #expect(editor.selection == [b.id, c.id])
```

with:

```swift
        editor.pointerReleased(from: start, at: Vector2(420, 20), modifiers: .shift)
        #expect(editor.selection == [b.id, c.id])
```

In `Tests/CreatorEditorTests/PointerTests.swift`, replace:

```swift
        editor.selection = [rect.id, extrude.id]
        editor.modifiers = .option
        let start = editor.screenPoint(in: rect.id)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(0, 200))
```

with:

```swift
        editor.selection = [rect.id, extrude.id]
        let start = editor.screenPoint(in: rect.id)
        editor.pointerDragged(from: start, to: start, modifiers: .option)
        editor.pointerDragged(from: start, to: start + Vector2(0, 200), modifiers: .option)
```

In `Tests/CreatorEditorTests/PointerTests.swift`, replace:

```swift
        editor.pointerReleased(from: start, at: start + Vector2(0, 200))
        #expect(editor.graph.nodes.count == 4)
```

with:

```swift
        editor.pointerReleased(from: start, at: start + Vector2(0, 200), modifiers: .option)
        #expect(editor.graph.nodes.count == 4)
```

In `Tests/CreatorEditorTests/GraphPanelRenderTests.swift`, replace:

```swift
        editor.modifiers = .shift
        editor.pointerDragged(from: Vector2(880, 580), to: Vector2(880, 580))
        editor.pointerDragged(from: Vector2(880, 580), to: Vector2(600, 400))
```

with:

```swift
        editor.pointerDragged(from: Vector2(880, 580), to: Vector2(880, 580), modifiers: .shift)
        editor.pointerDragged(from: Vector2(880, 580), to: Vector2(600, 400), modifiers: .shift)
```

In `Tests/CreatorEditorTests/GraphPanelRenderTests.swift`, replace:

```swift
        editor.modifiers = .option
        let start = editor.screenPoint(in: nodeID(1))
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(0, 120))
```

with:

```swift
        let start = editor.screenPoint(in: nodeID(1))
        editor.pointerDragged(from: start, to: start, modifiers: .option)
        editor.pointerDragged(from: start, to: start + Vector2(0, 120), modifiers: .option)
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: `error: extra argument 'modifiers' in call` (`Support/PointerTestSupport.swift`).

- [ ] **Step 3: Take the modifiers from the press**

In `Sources/CreatorEditor/EditorModel.swift`, replace:

```swift
    /// Modifier keys currently held, fed by `GraphPanelInput`.
    public var modifiers: CanvasModifiers = []
    /// The pointer over the canvas, in canvas-local screen points; `nil` when it is elsewhere.
```

with:

```swift
    /// The pointer over the canvas, in canvas-local screen points; `nil` when it is elsewhere.
```

In `Sources/CreatorEditor/EditorModel.swift`, replace:

```swift
    @ObservationIgnored private var pressHit: CanvasHit = .empty
```

with:

```swift
    @ObservationIgnored private var pressHit: CanvasHit = .empty
    /// The modifiers held at the press (MetalUI's `DragGesture.Value.modifiers` at its first change).
    @ObservationIgnored private var pressModifiers: CanvasModifiers = []
```

In `Sources/CreatorEditor/EditorModel.swift`, replace:

```swift
    func beginPress(at screen: Vector2) {
        pressStart = screen
        pressHit = hitTest(screen)
    }

    var currentPress: (point: Vector2, hit: CanvasHit)? { pressStart.map { ($0, pressHit) } }

    func endPress() {
        pressStart = nil
        pressHit = .empty
        interaction = nil
    }
```

with:

```swift
    func beginPress(at screen: Vector2, modifiers: CanvasModifiers) {
        pressStart = screen
        pressHit = hitTest(screen)
        pressModifiers = modifiers
    }

    var currentPress: (point: Vector2, hit: CanvasHit, modifiers: CanvasModifiers)? {
        pressStart.map { ($0, pressHit, pressModifiers) }
    }

    func endPress() {
        pressStart = nil
        pressHit = .empty
        pressModifiers = []
        interaction = nil
    }
```

Replace the contents of `Sources/CreatorEditor/EditorModel+Pointer.swift` with:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

extension EditorModel {
    /// How far a press must move before it counts as a drag, in screen points.
    public static let dragThreshold = 3.0

    /// A canvas drag moved. `start` and `location` are canvas-local screen points, and `modifiers` are the ones
    /// held at this change (MetalUI's `DragGesture.Value.modifiers`). The first call of a press records what it
    /// landed on and the modifiers held at the press; a drag starts once it moves `dragThreshold`, and the
    /// modifiers held then decide what it does (⇧ box-selects on empty canvas, ⌥ duplicates nodes).
    public func pointerDragged(from start: Vector2, to location: Vector2, modifiers: CanvasModifiers = []) {
        ensurePress(at: start, modifiers: modifiers)
        guard let press = currentPress else { return }
        if interaction == nil {
            guard (location - press.point).length >= Self.dragThreshold else { return }
            setInteraction(beginInteraction(for: press.hit, at: press.point, modifiers: modifiers))
        }
        update(to: location, from: press.point)
    }

    /// The press ended at `location`. Without a drag this is a click, and ⇧ held at the press extends the
    /// selection. `modifiers` (held at the release) count only for a press that reported no change before.
    public func pointerReleased(from start: Vector2, at location: Vector2, modifiers: CanvasModifiers = []) {
        ensurePress(at: start, modifiers: modifiers)
        guard let press = currentPress else { return }
        switch interaction {
        case nil: click(press.hit, extending: press.modifiers.contains(.shift))
        case .moving: document.endCoalescing()
        case .duplicating(let start, let delta): finishDuplicate(start: start, delta: delta)
        case .connecting(let wire): finishWire(wire, at: location)
        case .panning, .boxSelecting: break
        }
        endPress()
    }

    /// A press began, with `modifiers` held. Commits a typed inspector value, ends any slider drag's undo step and
    /// closes the palette.
    public func pointerPressed(at screen: Vector2, modifiers: CanvasModifiers = []) {
        commitPendingEntry()
        document.endCoalescing()
        palette = nil
        beginPress(at: screen, modifiers: modifiers)
    }

    /// Starts a press at `start` unless one with that start is in progress. A recorded press
    /// with another start is a gesture that never ended (say the window lost key status
    /// mid-drag); it is dropped, so its hit, modifiers and interaction don't leak into this one.
    private func ensurePress(at start: Vector2, modifiers: CanvasModifiers) {
        guard currentPress?.point != start else { return }
        if currentPress != nil { endPress() }
        pointerPressed(at: start, modifiers: modifiers)
    }

    private func click(_ hit: CanvasHit, extending: Bool) {
        let clicked: NodeID?
        switch hit {
        case .node(let id): clicked = id
        case .socket(let socket): clicked = socket.endpoint.node
        case .empty: clicked = nil
        }
        guard let clicked else {
            if !extending { selection = [] }
            return
        }
        if !extending {
            selection = [clicked]
        } else if selection.contains(clicked) {
            selection.remove(clicked)
        } else {
            selection.insert(clicked)
        }
    }

    private func beginInteraction(for hit: CanvasHit, at screen: Vector2, modifiers: CanvasModifiers) -> CanvasInteraction {
        switch hit {
        case .socket(let socket):
            return .connecting(WireDrag(from: socket, current: transform.toCanvas(screen)))
        case .node(let id):
            if !selection.contains(id) {
                selection = modifiers.contains(.shift) ? selection.union([id]) : [id]
            }
            let start = Dictionary(uniqueKeysWithValues: selection.compactMap { id in
                graph.nodes[id].map { (id, $0.position) }
            })
            if modifiers.contains(.option) { return .duplicating(start: start, delta: .zero) }
            return .moving(start: start, key: "move-\(UUID().uuidString)")
        case .empty:
            if modifiers.contains(.shift) {
                let point = transform.toCanvas(screen)
                return .boxSelecting(start: point, current: point, base: selection)
            }
            return .panning(startOffset: transform.offset)
        }
    }

    private func update(to location: Vector2, from pressPoint: Vector2) {
        guard let interaction else { return }
        // Screen delta → stored (left-to-right) canvas delta: undo the zoom, then the dock transpose.
        let storedDelta = flow.stored((location - pressPoint) * (1 / transform.zoom))
        switch interaction {
        case .panning(let startOffset):
            transform = CanvasTransform(offset: startOffset + (location - pressPoint), zoom: transform.zoom)
        case .moving(let start, let key):
            let moves = start.keys.sorted().compactMap { id in
                start[id].map { GraphCommand.move(id, to: $0 + storedDelta) }
            }
            try? document.perform(.batch(moves), coalescingKey: key)
        case .duplicating(let start, _):
            setInteraction(.duplicating(start: start, delta: storedDelta))
        case .boxSelecting(let start, _, let base):
            let current = transform.toCanvas(location)
            setInteraction(.boxSelecting(start: start, current: current, base: base))
            selection = base.union(nodes(intersecting: CanvasRect(corner: start, current)))
        case .connecting(var wire):
            wire.current = transform.toCanvas(location)
            setInteraction(.connecting(wire))
        }
    }

    /// The copies land where the ghosts were, as one undo step; the originals never moved.
    private func finishDuplicate(start: [NodeID: Vector2], delta: Vector2) {
        if let ids = insert(clipboard(of: Set(start.keys)), offset: delta) { selection = ids }
    }

    private func finishWire(_ wire: WireDrag, at location: Vector2) {
        guard case .socket(let target) = hitTest(location) else {
            // Dragging a wired input off onto empty canvas removes its wire.
            if wire.from.isInput, let link = graph.incomingLink(to: wire.from.endpoint) {
                do {
                    try document.perform(.disconnect(link))
                } catch {
                    refuse(error.message, node: link.to.node)
                }
            }
            return
        }
        guard target.isInput != wire.from.isInput else {
            refuse("Connect an output to an input.", node: target.endpoint.node)
            return
        }
        let output = wire.from.isInput ? target.endpoint : wire.from.endpoint
        let input = wire.from.isInput ? wire.from.endpoint : target.endpoint
        connect(Link(from: output, to: input))
    }
}
```

Replace the contents of `Sources/CreatorEditor/CanvasModifiers.swift` with:

```swift
/// Modifier keys held during a canvas press or drag. They come from the gesture's own value
/// (MetalUI C7's `DragGesture.Value.modifiers`, read by `GraphPanelInput`), so they can't go stale.
public struct CanvasModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let shift = CanvasModifiers(rawValue: 1 << 0)
    public static let option = CanvasModifiers(rawValue: 1 << 1)
    public static let command = CanvasModifiers(rawValue: 1 << 2)
}
```

Replace the contents of `Sources/CreatorEditor/GraphPanelInput.swift` with:

```swift
import CreatorGeometry
import MetalUI

/// The graph panel's input (spec §9): the canvas's gestures, and the window hooks for the MetalUI gaps C7 didn't
/// close, in one place (docs/metalui-gaps.md). The canvas's pointer input is MetalUI C7's; the behaviour is the
/// model's (`EditorModel+Pointer`), and this type only turns MetalUI values into the model's:
/// - `canvasGesture()`: one `DragGesture(minimumDistance: 0)` carries clicks, pans, moves, box selection and
///   wiring. Its values give the press point (`startLocation`) and the modifiers held at each change
///   (`DragGesture.Value.modifiers`, the press's at the first), so Shift-click and ⇧/⌥-drag read the press's own
///   modifiers, and the model tells a click from a drag (`EditorModel.dragThreshold`). It isn't a
///   `SpatialTapGesture` plus a drag, as the viewport's is: a tap's value has no modifiers, and a click must know
///   whether ⇧ was held (gap GI-a).
///
/// Three stopgaps remain, for MetalUI gaps outside C7:
/// - keys: read from the window's `onInput` fallback, so a focused text field keeps its keys;
///   the palette's ↑/↓ and Tab over the canvas alone go through the window keymap (`keymap`,
///   `handleAction`), because a focused field claims arrows and focus traversal claims Tab before
///   `onInput` (gaps M5-h, M5-b), and keys aren't scoped to an element until MetalUI C9;
/// - focus: a canvas press clears text focus through `releaseTextFocus`, because MetalUI never
///   unfocuses a field on an outside press (gap M5-g);
/// - the floating palette's "click outside": a press of any button reaching `onInput` outside the
///   palette closes it (`handle(_:)`), because MetalUI's only overlay that dismisses itself is
///   `.popover`, with its own chrome (gap EP-b).
@MainActor
public final class GraphPanelInput {
    public let model: EditorModel
    /// Clears the window's text focus. The shell sets it to `{ [weak window] in window?.focus(nil) }`.
    /// Without it, an inspector field edited a moment ago keeps claiming Delete, ⌘C/⌘V/⌘Z and
    /// Space while the user works on the canvas.
    public var releaseTextFocus: (@MainActor () -> Void)?

    public init(model: EditorModel) {
        self.model = model
    }

    /// Installs every hook on `window`, composing with the handlers already there (`GraphPanelPreview` uses it;
    /// the app installs `AppInput` instead, which forwards to the current document's `GraphPanelInput`). A keymap
    /// or `onAction` *assigned* after this call replaces the graph's, so the host sets those first, or appends and
    /// chains them like this:
    /// - `onInput`: this panel's `handle(_:)` first, then the previous handler.
    /// - `keymap`: `keymap`'s bindings are appended to the window's.
    /// - `onAction`: `handleAction(_:)` first, then the previous handler.
    /// - `releaseTextFocus`: `window.focus(nil)`, unless the shell set its own.
    public func install(on window: Window) {
        let previousInput = window.onInput
        window.onInput = { [weak self] event in
            if self?.handle(event) == true { return true }
            return previousInput?(event) ?? false
        }
        window.keymap = Keymap(window.keymap.bindings + Self.keymap.bindings)
        let previousAction = window.onAction
        window.onAction = { [weak self] action in
            if self?.handleAction(action) == true { return true }
            return previousAction?(action) ?? false
        }
        if releaseTextFocus == nil {
            releaseTextFocus = { [weak window] in window?.focus(nil) }
        }
    }

    /// Install as (or merge into) `Window.keymap`, with `handleAction(_:)` in `Window.onAction`.
    public static var keymap: Keymap {
        Keymap {
            KeyBinding("up", PaletteMove(step: -1))
            KeyBinding("down", PaletteMove(step: 1))
            KeyBinding("tab", GraphTab())
        }
    }

    /// Install from `Window.onAction`. Runs a palette move while the palette is open, and opens the
    /// palette on Tab while the pointer is over the visible canvas and no palette is open. Otherwise
    /// it returns false, and MetalUI passes the key on (to a focused field, Tab focus traversal, a
    /// `GraphShowButton` shortcut or `onInput`) as if it were unbound.
    public func handleAction(_ action: any Action) -> Bool {
        switch action {
        case let move as PaletteMove:
            guard model.palette != nil else { return false }
            model.movePaletteHighlight(by: move.step)
            return true
        case is GraphTab:
            guard model.isPanelVisible, model.pointerLocation != nil, model.palette == nil else { return false }
            model.openPalette()
            return true
        default:
            return false
        }
    }

    /// Install from `Window.onInput` (`install(on:)` does). Returns true when the event was used: the graph's
    /// keys. Every primary press reaches `onInput` (MetalUI claims none, except one in a text field or on a
    /// slider), and so does every other button's press but a right-click that opens a context menu, so the
    /// floating palette's "click outside" is read here too. Modifier changes aren't tracked: a press reads its
    /// own (`canvasGesture()`).
    public func handle(_ event: InputEvent) -> Bool {
        switch event {
        case .keyDown(let key):
            guard let command = GraphKeyBindings.command(for: key, paletteOpen: model.palette != nil) else { return false }
            return model.perform(command)
        case .mouseDown(let mouse), .rightMouseDown(let mouse), .otherMouseDown(let mouse):
            // Any button's press outside the floating palette closes it. Never claimed, so the press goes on.
            model.windowPressed(at: Self.vector(mouse.position))
            return false
        default:
            return false
        }
    }

    /// The canvas's one press-and-drag gesture: clicks, pans, moves, box selection and wiring. A zero minimum
    /// distance, so its first change is the press itself, with the press's modifiers.
    public func canvasGesture() -> DragGesture {
        DragGesture(minimumDistance: Pixels(0))
            .onChanged { [self] value in canvasChanged(value) }
            .onEnded { [self] value in canvasEnded(value) }
    }

    /// The gesture moved (its first change is the press). The first call of a press releases text focus.
    func canvasChanged(_ value: DragGesture.Value) {
        let start = Self.vector(value.startLocation)
        if model.currentPress?.point != start { releaseTextFocus?() }
        model.pointerDragged(from: start, to: Self.vector(value.location), modifiers: Self.canvasModifiers(value.modifiers))
    }

    /// The gesture ended: a release, or a click's only report when no change came first, so it releases focus too.
    func canvasEnded(_ value: DragGesture.Value) {
        let start = Self.vector(value.startLocation)
        if model.currentPress?.point != start { releaseTextFocus?() }
        model.pointerReleased(from: start, at: Self.vector(value.location), modifiers: Self.canvasModifiers(value.modifiers))
    }

    /// A node-library row's one gesture: a zero-distance drag reported in window points (`.global`), so a click
    /// and a drag are told apart by the model (`EditorModel.moveLibraryDrag`, `endLibraryDrag`, `LibraryDrag.threshold`)
    /// and the release is turned into a canvas point with the host's placement (`canvasFrameInWindow`), with no
    /// row frame needed. MetalUI's own gesture: the drag never leaves the window as a system drag.
    public func libraryGesture(for typeID: String) -> DragGesture {
        DragGesture(minimumDistance: Pixels(0), coordinateSpace: .global)
            .onChanged { [model] value in
                model.moveLibraryDrag(typeID, from: Self.vector(value.startLocation), to: Self.vector(value.location))
            }
            .onEnded { [model] value in
                model.endLibraryDrag(typeID, from: Self.vector(value.startLocation), at: Self.vector(value.location))
            }
    }

    /// The pointer over the canvas, from `.onContinuousHover`.
    public func hover(_ phase: HoverPhase) {
        switch phase {
        case .active(let point): model.pointerLocation = Self.vector(point)
        case .ended: model.pointerLocation = nil
        }
    }

    /// The canvas's modifiers from MetalUI's. Control isn't one: the canvas binds nothing to it.
    public static func canvasModifiers(_ modifiers: Modifiers) -> CanvasModifiers {
        var result: CanvasModifiers = []
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.command) { result.insert(.command) }
        return result
    }

    static func vector(_ point: Point<Pixels>) -> Vector2 {
        Vector2(Double(point.x.value), Double(point.y.value))
    }
}
```

- [ ] **Step 4: Run the editor tests**

Run: `swift test --filter CreatorEditorTests 2>&1 | grep -E "Test run with|recorded an issue|failed after"`
Expected: `Test run with 182 tests in 27 suites passed`, and no issue line.

- [ ] **Step 5: Check the whole package**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning"`, `swift test 2>&1 | grep "Test run with" | awk '{s+=$5} END {print s}'` and `swiftlint lint --strict`
Expected: only the pre-existing `ContextMenuTests.swift` warning (if that file is rebuilt); **1093**; 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor Tests/CreatorEditorTests
git commit -m "feat(editor): the canvas reads each press's modifiers from MetalUI C7's drag value"
```

### Task 2: Two-finger scroll pans and ⌘-scroll zooms

C7 item 1 / gap M5-f (`CI-I`): `.onScrollWheel` with `ScrollEvent.location`, `phase`, `momentumPhase` and `modifiers` (Key decisions 3, 4, 6). `GraphPanel`'s opaque backdrop (Key decision 4) lands here too: it stops a pinch, a press and a hover over the chrome as well as a scroll.

**Files:**
- Create: `Sources/CreatorEditor/CanvasScrollPhase.swift`, `Sources/CreatorEditor/EditorModel+Scroll.swift`
- Modify: `Sources/CreatorEditor/EditorModel.swift`, `Sources/CreatorEditor/GraphPanelInput.swift`, `Sources/CreatorEditor/GraphCanvas.swift`, `Sources/CreatorEditor/GraphPanel.swift`
- Test: `Tests/CreatorEditorTests/CanvasScrollTests.swift` (create), `Tests/CreatorEditorTests/GraphPanelInputTests.swift`

**Interfaces:**
- Consumes: Task 1's `GraphPanelInput.canvasModifiers(_:)` and `vector(_:)`; MetalUI `.onScrollWheel(perform: @escaping @MainActor (ScrollEvent) -> Bool)` (`true` claims; on a proposal group, so it goes after `.contentShape`); `ScrollEvent.delta`, `.location` (local), `.modifiers`, `.phase: InputPhase`, `.momentumPhase: InputPhase`, `.isMomentum` (`momentumPhase != .none`); `InputPhase` `.none`, `.mayBegin`, `.began`, `.changed`, `.ended`, `.cancelled`; `ScrollEvent.init(position:delta:modifiers:phase:momentumPhase:isPrecise:timestamp:)` (tests); `.contentShape(Rectangle())` and an empty `DragGesture(minimumDistance:)` for the opaque backdrop (the palette's, `SearchPaletteView`).
- Produces:
  - `public enum CanvasScrollPhase: Hashable, Sendable { case step, began, changed, ended, momentum, momentumEnded }`
  - On `EditorModel`: `public static let scrollZoomPerPoint = 0.01`; `@discardableResult public func scrolled(by delta: Vector2, at point: Vector2, modifiers: CanvasModifiers, phase: CanvasScrollPhase) -> Bool` (always `true`); internal untracked `scrollZooms: Bool?` (the fingers-down latch) and `scrollGlideIgnored: Bool` (a zoom's glide).
  - On `GraphPanelInput`: `public func scrolled(_ event: ScrollEvent) -> Bool`, `public static func scrollPhase(of event: ScrollEvent) -> CanvasScrollPhase`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorEditorTests/CanvasScrollTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import Foundation
import Testing
@testable import CreatorEditor

/// Scrolling over the graph canvas (spec §6.2, docs/metalui-gaps.md M5-f): two-finger scroll and the wheel pan
/// it, with the glide after a flick; ⌘-scroll zooms about the pointer, without a glide.
@MainActor
struct CanvasScrollTests {
    @Test func aWheelStepPansTheCanvasByItsDelta() {
        let editor = makeEditor([])
        editor.transform = CanvasTransform(offset: Vector2(5, 5), zoom: 2)
        #expect(editor.scrolled(by: Vector2(10, -20), at: Vector2(100, 100), modifiers: [], phase: .step))
        #expect(editor.transform == CanvasTransform(offset: Vector2(15, -15), zoom: 2))
        #expect(editor.document.viewState.canvasOffset == Vector2(15, -15))
        #expect(!editor.document.canUndo, "panning is not an edit")
    }

    @Test func aTrackpadScrollPansAndItsGlideKeepsPanning() {
        let editor = makeEditor([])
        editor.scrolled(by: .zero, at: Vector2(100, 100), modifiers: [], phase: .began)
        editor.scrolled(by: Vector2(4, 6), at: Vector2(100, 100), modifiers: [], phase: .changed)
        editor.scrolled(by: .zero, at: Vector2(100, 100), modifiers: [], phase: .ended)
        editor.scrolled(by: Vector2(2, 3), at: Vector2(100, 100), modifiers: [], phase: .momentum)
        #expect(editor.transform == CanvasTransform(offset: Vector2(6, 9), zoom: 1))
    }

    @Test func commandScrollZoomsAboutThePointer() {
        let editor = makeEditor([])
        editor.transform = CanvasTransform(offset: Vector2(10, 10), zoom: 1)
        let pointer = Vector2(200, 100)
        let under = editor.transform.toCanvas(pointer)
        editor.scrolled(by: Vector2(3, 10), at: pointer, modifiers: .command, phase: .step)
        #expect(abs(editor.transform.zoom - exp(0.1)) < 1e-12)
        #expect((editor.transform.toCanvas(pointer) - under).length < 1e-9, "the point under the pointer stays put")
        editor.scrolled(by: Vector2(0, -10), at: pointer, modifiers: .command, phase: .step)
        #expect(abs(editor.transform.zoom - 1) < 1e-12, "scrolling back zooms back out")
    }

    /// The glide after a ⌘-scroll is ignored, also once ⌘ is let go: it would pan the canvas the user just zoomed.
    @Test func aZoomScrollsGlideIsIgnored() {
        let editor = makeEditor([])
        let pointer = Vector2(200, 100)
        editor.scrolled(by: .zero, at: pointer, modifiers: .command, phase: .began)
        editor.scrolled(by: Vector2(0, 20), at: pointer, modifiers: .command, phase: .changed)
        editor.scrolled(by: .zero, at: pointer, modifiers: .command, phase: .ended)
        let zoomed = editor.transform
        #expect(zoomed.zoom > 1)
        editor.scrolled(by: Vector2(0, 8), at: pointer, modifiers: [], phase: .momentum)
        editor.scrolled(by: Vector2(0, 8), at: pointer, modifiers: .command, phase: .momentum)
        #expect(editor.transform == zoomed)
    }

    /// A zoom's glide is ignored until its momentum ends; a glide after that (one drifting in from a pan elsewhere)
    /// pans.
    @Test func aZoomsGlideIsIgnoredOnlyUntilItsMomentumEnds() {
        let editor = makeEditor([])
        let pointer = Vector2(200, 100)
        editor.scrolled(by: .zero, at: pointer, modifiers: .command, phase: .began)
        editor.scrolled(by: Vector2(0, 20), at: pointer, modifiers: .command, phase: .changed)
        editor.scrolled(by: .zero, at: pointer, modifiers: .command, phase: .ended)
        let zoomed = editor.transform
        editor.scrolled(by: Vector2(0, 8), at: pointer, modifiers: [], phase: .momentum)
        editor.scrolled(by: Vector2(0, 1), at: pointer, modifiers: [], phase: .momentumEnded)
        #expect(editor.transform == zoomed)
        editor.scrolled(by: Vector2(0, 8), at: pointer, modifiers: [], phase: .momentum)
        #expect(editor.transform == zoomed.panned(by: Vector2(0, 8)))
    }

    /// MetalUI sends each scroll event to what is under the pointer at that event (gap GI-b), so a scroll that began
    /// over something else reaches the canvas with a `.changed` and no `.began`. It is taken up as it is then (no ⌘:
    /// a pan), never as the last canvas scroll was (a zoom), and keeps that until it ends.
    @Test func aScrollThatBeganElsewhereIsTakenUpAsItIsNow() {
        let editor = makeEditor([])
        let pointer = Vector2(200, 100)
        editor.scrolled(by: .zero, at: pointer, modifiers: .command, phase: .began)
        editor.scrolled(by: Vector2(0, 20), at: pointer, modifiers: .command, phase: .changed)
        editor.scrolled(by: .zero, at: pointer, modifiers: .command, phase: .ended)
        let zoomed = editor.transform
        editor.scrolled(by: Vector2(0, 10), at: pointer, modifiers: [], phase: .changed)
        #expect(editor.transform == zoomed.panned(by: Vector2(0, 10)))
        editor.scrolled(by: Vector2(0, 10), at: pointer, modifiers: .command, phase: .changed)
        #expect(editor.transform == zoomed.panned(by: Vector2(0, 20)), "⌘ pressed after it was taken up changes nothing")
    }

    /// A trackpad scroll keeps doing what it began doing: ⌘ pressed or let go part-way changes nothing.
    @Test func aTrackpadScrollZoomsOrPansAsItBegan() {
        let editor = makeEditor([])
        let pointer = Vector2(200, 100)
        editor.scrolled(by: .zero, at: pointer, modifiers: [], phase: .began)
        editor.scrolled(by: Vector2(0, 10), at: pointer, modifiers: .command, phase: .changed)
        #expect(editor.transform == CanvasTransform(offset: Vector2(0, 10), zoom: 1))
        editor.scrolled(by: .zero, at: pointer, modifiers: .command, phase: .began)
        editor.scrolled(by: Vector2(0, 10), at: pointer, modifiers: [], phase: .changed)
        #expect(editor.transform.zoom > 1)
        // A wheel step decides for itself, whatever the last trackpad scroll did.
        let zoomed = editor.transform
        editor.scrolled(by: Vector2(0, 10), at: pointer, modifiers: [], phase: .step)
        #expect(editor.transform == zoomed.panned(by: Vector2(0, 10)))
    }

    @Test func theScrollZoomStaysInRange() {
        let editor = makeEditor([])
        let pointer = Vector2(200, 100)
        for _ in 0..<40 { editor.scrolled(by: Vector2(0, 100), at: pointer, modifiers: .command, phase: .step) }
        #expect(editor.transform.zoom == CanvasTransform.zoomRange.upperBound)
        for _ in 0..<80 { editor.scrolled(by: Vector2(0, -100), at: pointer, modifiers: .command, phase: .step) }
        #expect(editor.transform.zoom == CanvasTransform.zoomRange.lowerBound)
        #expect(editor.transform.offset.isFinite)
    }

    @Test func aNonFiniteScrollChangesNothing() {
        let editor = makeEditor([])
        editor.transform = CanvasTransform(offset: Vector2(5, 5), zoom: 2)
        let before = editor.transform
        #expect(editor.scrolled(by: Vector2(.nan, 4), at: Vector2(10, 10), modifiers: [], phase: .step))
        editor.scrolled(by: Vector2(0, .infinity), at: Vector2(10, 10), modifiers: .command, phase: .step)
        editor.scrolled(by: Vector2(0, 10), at: Vector2(.infinity, 10), modifiers: .command, phase: .step)
        #expect(editor.transform == before)
    }

    /// The palette adds at the canvas point it opened over, so a scroll that moves the canvas closes it.
    @Test func aScrollThatMovesTheCanvasClosesThePalette() {
        let editor = makeEditor([])
        editor.pointerLocation = Vector2(100, 100)
        editor.openPalette()
        editor.scrolled(by: .zero, at: Vector2(100, 100), modifiers: [], phase: .began)
        #expect(editor.palette != nil, "a scroll that doesn't move the canvas leaves it open")
        editor.scrolled(by: Vector2(0, 12), at: Vector2(100, 100), modifiers: [], phase: .changed)
        #expect(editor.palette == nil)
    }
}
```

In `Tests/CreatorEditorTests/GraphPanelInputTests.swift`, replace:

```swift
    @Test func aCanvasPressReleasesTextFocusOncePerPress() {
```

with:

```swift
    @Test func scrollEventsMapToCanvasPhases() {
        func event(_ phase: InputPhase, momentum: InputPhase = .none) -> ScrollEvent {
            ScrollEvent(position: Point(x: Pixels(0), y: Pixels(0)), delta: Point(x: Pixels(0), y: Pixels(1)),
                        phase: phase, momentumPhase: momentum, isPrecise: true, timestamp: 0)
        }
        #expect(GraphPanelInput.scrollPhase(of: event(.none)) == .step)
        #expect(GraphPanelInput.scrollPhase(of: event(.mayBegin)) == .began)
        #expect(GraphPanelInput.scrollPhase(of: event(.began)) == .began)
        #expect(GraphPanelInput.scrollPhase(of: event(.changed)) == .changed)
        #expect(GraphPanelInput.scrollPhase(of: event(.ended)) == .ended)
        #expect(GraphPanelInput.scrollPhase(of: event(.cancelled)) == .ended)
        #expect(GraphPanelInput.scrollPhase(of: event(.none, momentum: .began)) == .momentum)
        #expect(GraphPanelInput.scrollPhase(of: event(.none, momentum: .changed)) == .momentum)
        #expect(GraphPanelInput.scrollPhase(of: event(.none, momentum: .ended)) == .momentumEnded)
        #expect(GraphPanelInput.scrollPhase(of: event(.none, momentum: .cancelled)) == .momentumEnded)
    }

    /// A scroll is claimed and reaches the model at the canvas-local `location`, not the window's `position`.
    @Test func aScrollEventZoomsAboutItsLocalPoint() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        var event = ScrollEvent(position: Point(x: Pixels(700), y: Pixels(500)), delta: Point(x: Pixels(0), y: Pixels(10)),
                                modifiers: .command, phase: .none, momentumPhase: .none, isPrecise: false, timestamp: 0)
        event.location = Point(x: Pixels(200), y: Pixels(100))
        let under = editor.transform.toCanvas(Vector2(200, 100))
        #expect(input.scrolled(event))
        #expect(editor.transform.zoom > 1)
        #expect((editor.transform.toCanvas(Vector2(200, 100)) - under).length < 1e-6)
    }

    @Test func aCanvasPressReleasesTextFocusOncePerPress() {
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: `error: value of type 'EditorModel' has no member 'scrolled'`.

- [ ] **Step 3: Add the scroll phase, the model's scroll and the canvas's wheel**

Create `Sources/CreatorEditor/CanvasScrollPhase.swift`:

```swift
/// Where a scroll over the graph canvas sits in its gesture (from MetalUI's `ScrollEvent` phases,
/// `GraphPanelInput.scrollPhase(of:)`), as `EditorModel.scrolled(by:at:modifiers:phase:)` needs it.
public enum CanvasScrollPhase: Hashable, Sendable {
    /// A wheel mouse's step, with no gesture around it: ⌘ held zooms, anything else pans.
    case step
    /// A trackpad scroll's fingers touched or began to move: ⌘ held now makes the whole scroll a zoom.
    case began
    /// A trackpad scroll goes on, zooming or panning as it began (or, when it began elsewhere, as it was when it
    /// first reached the canvas).
    case changed
    /// The fingers lifted, or the system cancelled the scroll.
    case ended
    /// The glide after the fingers lift: it keeps panning a scroll that panned, and is ignored after a zoom.
    case momentum
    /// The glide's last event (its momentum ended or was cancelled): a zoom's glide is ignored no longer.
    case momentumEnded
}
```

Create `Sources/CreatorEditor/EditorModel+Scroll.swift`:

```swift
import CreatorGeometry
import Foundation

extension EditorModel {
    /// ⌘-scroll zoom: 100 points of scroll multiply or divide the zoom by e, as the viewport's scroll zoom does. A
    /// wheel mouse's step is 10 points (MetalUI reports its lines × 10), so about 10%.
    public static let scrollZoomPerPoint = 0.01

    /// A scroll over the canvas (spec §6.2, docs/metalui-gaps.md M5-f): `delta` points of scroll at `point`
    /// (canvas-local screen points), with `modifiers` held. Two-finger scroll and the wheel pan the canvas by the
    /// delta, and the glide after a flick keeps panning. ⌘-scroll zooms about `point`, a positive `delta.y`
    /// zooming in (as the viewport does), within `CanvasTransform.zoomRange`, and its glide is ignored until its
    /// momentum ends. A trackpad scroll zooms or pans as it began, so pressing or letting go of ⌘ part-way changes
    /// nothing until the next one. A scroll that moves the canvas closes the add-node palette, which adds at the
    /// point it opened over. Returns `true`: the canvas claims every scroll over it, so none reaches the viewport or
    /// the window.
    @discardableResult
    public func scrolled(by delta: Vector2, at point: Vector2, modifiers: CanvasModifiers, phase: CanvasScrollPhase) -> Bool {
        guard let zooms = scrollMode(for: phase, command: modifiers.contains(.command)) else { return true }
        guard delta.isFinite, point.isFinite else { return true }
        let moved = zooms
            ? transform.zoomed(by: exp(delta.y * Self.scrollZoomPerPoint), around: point)
            : transform.panned(by: delta)
        guard moved != transform else { return true }
        palette = nil
        transform = moved
        return true
    }

    /// Whether this scroll event zooms (`true`), pans (`false`) or is ignored (`nil`: a zoom's glide), keeping the
    /// trackpad latch. `scrollZooms` holds what a scroll does from its `.began` (or, for a scroll that began over
    /// something else, from its first `.changed` here: MetalUI sends each event to what is under the pointer at
    /// that event, gap GI-b) to its `.ended`; `scrollGlideIgnored` holds a zoom's glide off from its `.ended` until
    /// its momentum ends, or the next scroll starts.
    private func scrollMode(for phase: CanvasScrollPhase, command: Bool) -> Bool? {
        switch phase {
        case .step, .began:
            scrollZooms = phase == .began ? command : nil
            scrollGlideIgnored = false
            return command
        case .changed:
            let zooms = scrollZooms ?? command
            scrollZooms = zooms
            scrollGlideIgnored = false
            return zooms
        case .ended:
            let zooms = scrollZooms ?? command
            scrollZooms = nil
            scrollGlideIgnored = zooms
            return zooms
        case .momentum, .momentumEnded:
            let ignored = scrollGlideIgnored
            if phase == .momentumEnded { scrollGlideIgnored = false }
            return ignored ? nil : false
        }
    }
}
```

In `Sources/CreatorEditor/EditorModel.swift`, replace:

```swift
    /// What an inspector field holds but hasn't committed (`EditorModel+PendingEntry`).
    @ObservationIgnored var pendingEntry: PendingEntry?
```

with:

```swift
    /// What an inspector field holds but hasn't committed (`EditorModel+PendingEntry`).
    @ObservationIgnored var pendingEntry: PendingEntry?
    /// Whether the trackpad scroll under way zooms (it began with ⌘ held) or pans; `nil` between scrolls
    /// (`EditorModel+Scroll`).
    @ObservationIgnored var scrollZooms: Bool?
    /// A ⌘-scroll ended and its glide, until its momentum ends, is ignored (`EditorModel+Scroll`).
    @ObservationIgnored var scrollGlideIgnored = false
```

In `Sources/CreatorEditor/GraphPanelInput.swift`, replace:

```swift
///   whether ⇧ was held (gap GI-a).
///
```

with:

```swift
///   whether ⇧ was held (gap GI-a).
/// - `scrolled(_:)`, from the canvas's `.onScrollWheel`: two-finger scroll and the wheel pan, ⌘-scroll zooms
///   about the pointer (`EditorModel.scrolled(by:at:modifiers:phase:)`, phases from `scrollPhase(of:)`).
///
```

In `Sources/CreatorEditor/GraphPanelInput.swift`, replace:

```swift
    /// A node-library row's one gesture:
```

with:

```swift
    /// A scroll over the canvas, from its `.onScrollWheel`: the delta, the pointer in canvas-local points, the
    /// modifiers and the phase go to the model. Returns `true` (claimed), so the viewport beneath never sees it.
    public func scrolled(_ event: ScrollEvent) -> Bool {
        model.scrolled(by: Self.vector(event.delta), at: Self.vector(event.location),
                       modifiers: Self.canvasModifiers(event.modifiers), phase: Self.scrollPhase(of: event))
    }

    /// A MetalUI scroll event's place in its gesture. Momentum wins over the gesture phase, and its end (or
    /// cancellation) is its own phase; no phase at all is a wheel step (and every scroll on SDL, which reports none,
    /// MetalUI `CI-I` item 6).
    public static func scrollPhase(of event: ScrollEvent) -> CanvasScrollPhase {
        if event.isMomentum {
            return event.momentumPhase == .ended || event.momentumPhase == .cancelled ? .momentumEnded : .momentum
        }
        switch event.phase {
        case .none: return .step
        case .mayBegin, .began: return .began
        case .changed: return .changed
        case .ended, .cancelled: return .ended
        }
    }

    /// A node-library row's one gesture:
```

Replace the contents of `Sources/CreatorEditor/GraphCanvas.swift` with:

```swift
import MetalUI

/// The graph canvas: the layers under the zoom and pan transform, one press-and-drag gesture
/// for everything (hit testing is the model's), the scroll wheel, and pointer tracking for the palette. The palette
/// itself floats over the whole window (`SearchPaletteOverlay`), so the canvas never clips it.
/// All input goes through `GraphPanelInput` to the model.
struct GraphCanvas: Component {
    let model: EditorModel
    let input: GraphPanelInput

    var content: some ElementGroup {
        let transform = model.transform
        return ZStack(alignment: .topLeading) {
            Color.clear
            ZStack(alignment: .topLeading) { CanvasLayers(model: model) }
                .scaleEffect(transform.zoom, anchor: .topLeading)
                .offset(x: transform.offset.x.px, y: transform.offset.y.px)
                .allowsHitTesting(false)
        }
        .clipped()
        .gesture(input.canvasGesture())
        .contentShape(Rectangle())
        .onContinuousHover { phase in input.hover(phase) }
        .onScrollWheel { event in input.scrolled(event) }
    }
}
```

`GraphPanel`'s chrome becomes opaque to the pointer (Key decision 4):

Replace the contents of `Sources/CreatorEditor/GraphPanel.swift` with:

```swift
import CreatorGraph
import CreatorStyle
import MetalUI

/// The graph panel (spec §6.2): glass chrome, the header, and the body (the node library and the
/// canvas), with a refusal message along the bottom while one is showing. It is laid out to
/// `GraphPanelLayout`, so the host's
/// `EditorModel.placement` tells the editor where the canvas is in the window. The app shell (M6)
/// sizes and places it per dock and installs the input with `input.install(on:)`.
public struct GraphPanel: Component {
    public let model: EditorModel
    public let input: GraphPanelInput
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init(model: EditorModel, input: GraphPanelInput) {
        self.model = model
        self.input = input
    }

    public var content: some ElementGroup {
        ZStack {
            // The glass only paints, and MetalUI gives a painted view no hitbox (its divergence 141), so without this
            // backdrop a scroll, pinch, press or hover over the header's gaps, the padding or the refusal line would
            // reach the viewport beneath. Opaque (a content shape with an empty drag) and claiming every scroll, as
            // the palette's backdrop is (docs/metalui-gaps.md EP-b). The canvas, the header's buttons and the
            // library's list are drawn above it and take their own input.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: Pixels(0)))
                .onScrollWheel { _ in true }
            GlassPanel {
                VStack(alignment: .leading, spacing: GraphPanelLayout.spacing.px) {
                    GraphPanelHeader(model: model)
                        .frame(height: GraphPanelLayout.headerHeight.px)
                    GraphPanelBody(model: model, input: input)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let refusal = model.refusal {
                        Text(refusal.message).font(.caption).foregroundStyle(Palette(themes).statusError.color)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run the editor tests**

Run: `swift test --filter CreatorEditorTests 2>&1 | grep -E "Test run with|recorded an issue|failed after"`
Expected: `Test run with 194 tests in 28 suites passed`, and no issue line.

- [ ] **Step 5: Check the whole package**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning"`, `swift test 2>&1 | grep "Test run with" | awk '{s+=$5} END {print s}'` and `swiftlint lint --strict`
Expected: no new warning; **1105**; 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor Tests/CreatorEditorTests
git commit -m "feat(editor): two-finger scroll pans the graph canvas, ⌘-scroll zooms about the pointer (MetalUI C7), and the panel's chrome is opaque to the pointer"
```

### Task 3: Pinch zooms about the pinch centre

C7 item 2 / gap M5-f (`CI-C`, `CI-D`): `MagnifyGesture` with `magnification` and `startLocation` (Key decisions 5, 6).

**Files:**
- Create: `Sources/CreatorEditor/CanvasPinch.swift`, `Sources/CreatorEditor/EditorModel+Pinch.swift`
- Modify: `Sources/CreatorEditor/EditorModel.swift`, `Sources/CreatorEditor/GraphPanelInput.swift`, `Sources/CreatorEditor/GraphCanvas.swift`
- Test: `Tests/CreatorEditorTests/CanvasPinchTests.swift` (create)

**Interfaces:**
- Consumes: MetalUI `MagnifyGesture()`, `.onChanged((MagnifyGesture.Value) -> Void)`, `.onEnded`, `Value.magnification` (cumulative from 1), `Value.startLocation` (local); `CanvasTransform.zoomed(by:around:)` (unchanged: it ignores a factor that isn't finite and positive, and clamps to `zoomRange`).
- Produces:
  - `struct CanvasPinch: Equatable { var transform: CanvasTransform; var centre: Vector2; var applied: CanvasTransform }` (internal)
  - On `EditorModel`: `public static let minimumMagnification = 0.05`; `public func pinchChanged(magnification: Double, centre: Vector2)`; `public func pinchEnded()`; internal untracked `pinchStart: CanvasPinch?`.
  - On `GraphPanelInput`: `public func pinchGesture() -> MagnifyGesture`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorEditorTests/CanvasPinchTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorEditor

/// A trackpad pinch over the graph canvas (spec §6.2, docs/metalui-gaps.md M5-f) zooms about where it began.
@MainActor
struct CanvasPinchTests {
    let centre = Vector2(240, 120)

    @Test func aPinchZoomsByItsCumulativeMagnificationAboutItsCentre() {
        let editor = makeEditor([])
        editor.transform = CanvasTransform(offset: Vector2(10, 20), zoom: 1)
        let under = editor.transform.toCanvas(centre)
        editor.pinchChanged(magnification: 1.2, centre: centre)
        editor.pinchChanged(magnification: 1.5, centre: centre)
        #expect(abs(editor.transform.zoom - 1.5) < 1e-12, "cumulative from the pinch's start, not compounded")
        #expect((editor.transform.toCanvas(centre) - under).length < 1e-9)
        editor.pinchEnded()
        editor.pinchChanged(magnification: 2, centre: centre)
        #expect(abs(editor.transform.zoom - 3) < 1e-12, "the next pinch zooms from where this one left it")
        #expect(!editor.document.canUndo, "zooming is not an edit")
    }

    @Test func aHardPinchInHoldsInsteadOfSpringingBack() {
        let editor = makeEditor([])
        editor.transform = CanvasTransform(zoom: 2)
        editor.pinchChanged(magnification: 0.5, centre: centre)
        editor.pinchChanged(magnification: -0.3, centre: centre)
        #expect(editor.transform.zoom == CanvasTransform.zoomRange.lowerBound)
        editor.pinchChanged(magnification: 0, centre: centre)
        #expect(editor.transform.zoom == CanvasTransform.zoomRange.lowerBound)
        #expect(editor.transform.offset.isFinite)
    }

    @Test func aNonFinitePinchChangesNothing() {
        let editor = makeEditor([])
        editor.transform = CanvasTransform(offset: Vector2(5, 5), zoom: 1.5)
        let before = editor.transform
        editor.pinchChanged(magnification: .nan, centre: centre)
        editor.pinchChanged(magnification: .infinity, centre: centre)
        editor.pinchChanged(magnification: 1.2, centre: Vector2(.infinity, 0))
        #expect(editor.transform == before)
    }

    /// MetalUI drops a pinch that lost its end without a word (VI-a); the next one, elsewhere, must zoom from the
    /// canvas as it is, not snap back to where the lost one began.
    @Test func aPinchThatLostItsEndDoesntPullTheNextOneBack() {
        let editor = makeEditor([])
        editor.pinchChanged(magnification: 2, centre: centre)
        let zoomed = editor.transform
        editor.pinchChanged(magnification: 1.25, centre: Vector2(400, 300))
        #expect(abs(editor.transform.zoom - 2.5) < 1e-12)
        #expect(editor.transform == zoomed.zoomed(by: 1.25, around: Vector2(400, 300)))
    }

    /// Nor may a lost pinch, at the same centre, snap the canvas back over a pan or a zoom made since.
    @Test func aPinchThatLostItsEndDoesntUndoWhatMovedTheCanvasSince() {
        let editor = makeEditor([])
        editor.pinchChanged(magnification: 1.2, centre: centre)
        editor.drag(Vector2(600, 600), Vector2(640, 620))
        let panned = editor.transform
        editor.pinchChanged(magnification: 1.25, centre: centre)
        #expect(editor.transform == panned.zoomed(by: 1.25, around: centre))
        editor.zoom(in: true)
        let stepped = editor.transform
        editor.pinchChanged(magnification: 1.2, centre: centre)
        #expect(editor.transform == stepped.zoomed(by: 1.2, around: centre))
        #expect(abs(editor.transform.zoom - 2.25) < 1e-12)
    }

    @Test func aPinchClosesThePalette() {
        let editor = makeEditor([])
        editor.pointerLocation = centre
        editor.openPalette()
        editor.pinchChanged(magnification: 1.1, centre: centre)
        #expect(editor.palette == nil)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: `error: value of type 'EditorModel' has no member 'pinchChanged'`.

- [ ] **Step 3: Add the pinch**

Create `Sources/CreatorEditor/CanvasPinch.swift`:

```swift
import CreatorGeometry

/// A pinch over the canvas under way: the transform it zooms from, its centre in canvas-local screen points, and the
/// transform its last change left, so a pinch that lost its end can tell that something else moved the canvas since.
struct CanvasPinch: Equatable {
    var transform: CanvasTransform
    var centre: Vector2
    var applied: CanvasTransform
}
```

Create `Sources/CreatorEditor/EditorModel+Pinch.swift`:

```swift
import CreatorGeometry

extension EditorModel {
    /// The smallest pinch magnification the zoom follows. MetalUI's magnification is 1 plus the pinch's deltas, so
    /// a hard pinch-in can reach zero or below.
    public static let minimumMagnification = 0.05

    /// A trackpad pinch over the canvas (spec §6.2, docs/metalui-gaps.md M5-f), from MetalUI's `MagnifyGesture`:
    /// `magnification` is cumulative from 1 since the pinch began, and `centre` is where it began, in canvas-local
    /// screen points (the pointer doesn't move during a pinch). The canvas zooms by `magnification` from the
    /// transform it had when the pinch began, about `centre`, within `CanvasTransform.zoomRange`; a pinch-in to zero
    /// or below holds at `minimumMagnification` rather than springing back, and a non-finite value changes nothing.
    /// The pinch's first change closes the add-node palette, which adds at the point it opened over. A pinch under
    /// way that changes at another centre, or finds the canvas moved since its last change (a drag pan, a scroll,
    /// a zoom key, a dock change), lost its end (MetalUI drops it without a word, docs/metalui-gaps.md VI-a), so
    /// it starts afresh from the canvas as it is.
    public func pinchChanged(magnification: Double, centre: Vector2) {
        guard magnification.isFinite, centre.isFinite else { return }
        if let start = pinchStart, start.centre != centre || start.applied != transform { pinchEnded() }
        if pinchStart == nil {
            palette = nil
            pinchStart = CanvasPinch(transform: transform, centre: centre, applied: transform)
        }
        guard let start = pinchStart else { return }
        let zoomed = start.transform.zoomed(by: max(magnification, Self.minimumMagnification), around: centre)
        if zoomed != transform { transform = zoomed }
        pinchStart?.applied = transform
    }

    /// The pinch ended: the next one zooms from wherever this one left the canvas.
    public func pinchEnded() {
        pinchStart = nil
    }
}
```

In `Sources/CreatorEditor/EditorModel.swift`, replace:

```swift
    @ObservationIgnored var scrollZooms: Bool?
```

with:

```swift
    @ObservationIgnored var scrollZooms: Bool?
    /// The pinch under way (`EditorModel+Pinch`).
    @ObservationIgnored var pinchStart: CanvasPinch?
```

In `Sources/CreatorEditor/GraphPanelInput.swift`, replace:

```swift
///   about the pointer (`EditorModel.scrolled(by:at:modifiers:phase:)`, phases from `scrollPhase(of:)`).
```

with:

```swift
///   about the pointer (`EditorModel.scrolled(by:at:modifiers:phase:)`, phases from `scrollPhase(of:)`).
/// - `pinchGesture()`: a `MagnifyGesture` zooms about where the pinch began (`EditorModel.pinchChanged`).
```

In `Sources/CreatorEditor/GraphPanelInput.swift`, replace:

```swift
    /// A MetalUI scroll event's place in its gesture.
```

with:

```swift
    /// The canvas's pinch: zooms by the cumulative magnification about where it began (`startLocation`).
    public func pinchGesture() -> MagnifyGesture {
        MagnifyGesture()
            .onChanged { [model] value in
                model.pinchChanged(magnification: value.magnification, centre: Self.vector(value.startLocation))
            }
            .onEnded { [model] _ in model.pinchEnded() }
    }

    /// A MetalUI scroll event's place in its gesture.
```

Replace the contents of `Sources/CreatorEditor/GraphCanvas.swift` with:

```swift
import MetalUI

/// The graph canvas: the layers under the zoom and pan transform, one press-and-drag gesture
/// for everything (hit testing is the model's), a pinch, the scroll wheel, and pointer tracking for
/// the palette. All input goes through `GraphPanelInput` to the model. The palette itself floats over
/// the whole window (`SearchPaletteOverlay`), so the canvas never clips it.
struct GraphCanvas: Component {
    let model: EditorModel
    let input: GraphPanelInput

    var content: some ElementGroup {
        let transform = model.transform
        return ZStack(alignment: .topLeading) {
            Color.clear
            ZStack(alignment: .topLeading) { CanvasLayers(model: model) }
                .scaleEffect(transform.zoom, anchor: .topLeading)
                .offset(x: transform.offset.x.px, y: transform.offset.y.px)
                .allowsHitTesting(false)
        }
        .clipped()
        .gesture(input.canvasGesture())
        .gesture(input.pinchGesture())
        .contentShape(Rectangle())
        .onContinuousHover { phase in input.hover(phase) }
        .onScrollWheel { event in input.scrolled(event) }
    }
}
```

- [ ] **Step 4: Run the editor tests**

Run: `swift test --filter CreatorEditorTests 2>&1 | grep -E "Test run with|recorded an issue|failed after"`
Expected: `Test run with 200 tests in 29 suites passed`, and no issue line.

- [ ] **Step 5: Check the whole package**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning"`, `swift test 2>&1 | grep "Test run with" | awk '{s+=$5} END {print s}'` and `swiftlint lint --strict`
Expected: no new warning; **1111**; 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor Tests/CreatorEditorTests
git commit -m "feat(editor): a pinch zooms the graph canvas about where it began (MetalUI C7)"
```

### Task 4: Cursors — a closed hand while panning, resize cursors on the dock edge

C7 item 5 (`CI-H`): `.pointerStyle(_:)` with `.grabActive`, `.columnResize`, `.rowResize` (Key decision 7).

**Files:**
- Create: `Sources/CreatorEditor/CanvasCursor.swift`, `Sources/CreatorEditor/CanvasCursor+MetalUI.swift`, `Sources/CreatorEditor/EditorModel+Cursor.swift`
- Modify: `Sources/CreatorEditor/GraphCanvas.swift`, `Sources/CreatorEditor/GraphPanelInput.swift` (doc line), `Sources/CreatorApp/PanelResizeHandle.swift`
- Test: `Tests/CreatorEditorTests/CanvasCursorTests.swift` (create), `Tests/CreatorAppTests/PanelResizeCursorTests.swift` (create)

**Interfaces:**
- Consumes: `EditorModel.interaction` (`CanvasInteraction.panning`), Task 2's `scrolled(by:at:modifiers:phase:)` and Task 3's `pinchChanged(magnification:centre:)` (tests); MetalUI `.pointerStyle(_ style: PointerStyle?)` (`nil` attaches nothing), `PointerStyle` (`Hashable`).
- Produces:
  - `public enum CanvasCursor: Hashable, Sendable { case grabbing }` and `public var pointerStyle: PointerStyle` (`.grabActive`)
  - `EditorModel.canvasCursor: CanvasCursor?`
  - `PanelResizeHandle.pointerStyle(alongWidth: Bool) -> PointerStyle` (internal static)

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorEditorTests/CanvasCursorTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import MetalUI
import Testing
@testable import CreatorEditor

/// The canvas's cursor (docs/metalui-gaps.md C7 item 5): a closed hand while a drag pans, the arrow otherwise.
@MainActor
struct CanvasCursorTests {
    @Test func aDragOnEmptyCanvasShowsTheClosedHandUntilItsRelease() {
        let editor = makeEditor([])
        editor.pointerDragged(from: Vector2(500, 500), to: Vector2(500, 500))
        #expect(editor.canvasCursor == nil, "a press that hasn't moved may still be a click")
        editor.pointerDragged(from: Vector2(500, 500), to: Vector2(530, 500))
        #expect(editor.canvasCursor == .grabbing)
        #expect(editor.canvasCursor?.pointerStyle == .grabActive)
        editor.pointerReleased(from: Vector2(500, 500), at: Vector2(530, 500))
        #expect(editor.canvasCursor == nil)
    }

    @Test func movingWiringAndBoxSelectionKeepTheArrow() {
        let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
        let extrude = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([rect, extrude])
        let body = editor.screenPoint(in: rect.id)
        editor.pointerDragged(from: body, to: body)
        editor.pointerDragged(from: body, to: body + Vector2(0, 40))
        #expect(editor.interaction != nil && editor.canvasCursor == nil)
        editor.pointerReleased(from: body, at: body + Vector2(0, 40))
        let socket = editor.screenPoint(of: rect.id, "profile", input: false)
        editor.pointerDragged(from: socket, to: socket)
        editor.pointerDragged(from: socket, to: socket + Vector2(60, 0))
        #expect(editor.interaction != nil && editor.canvasCursor == nil)
        editor.pointerReleased(from: socket, at: Vector2(900, 900))
        editor.pointerDragged(from: Vector2(900, 900), to: Vector2(900, 900), modifiers: .shift)
        editor.pointerDragged(from: Vector2(900, 900), to: Vector2(950, 950), modifiers: .shift)
        #expect(editor.interaction != nil && editor.canvasCursor == nil)
    }

    /// A pan whose release was lost keeps its hand only until the next press.
    @Test func aPanThatLostItsReleaseLosesTheHandAtTheNextPress() {
        let editor = makeEditor([])
        editor.pointerDragged(from: Vector2(500, 500), to: Vector2(500, 500))
        editor.pointerDragged(from: Vector2(500, 500), to: Vector2(560, 500))
        #expect(editor.canvasCursor == .grabbing)
        editor.click(Vector2(100, 100))
        #expect(editor.canvasCursor == nil)
    }

    @Test func scrollingAndPinchingKeepTheArrow() {
        let editor = makeEditor([])
        editor.scrolled(by: Vector2(0, 30), at: Vector2(100, 100), modifiers: [], phase: .step)
        editor.pinchChanged(magnification: 1.3, centre: Vector2(100, 100))
        #expect(editor.canvasCursor == nil)
    }
}
```

Create `Tests/CreatorAppTests/PanelResizeCursorTests.swift`:

```swift
import MetalUI
import Testing
@testable import CreatorApp

/// The dock's resize edge shows a resize cursor (docs/metalui-gaps.md, "Cursor for the dock's resize edge").
@MainActor
struct PanelResizeCursorTests {
    @Test func theLeftDocksEdgeIsAColumnResizeAndTheBottomDocksARowResize() {
        #expect(PanelResizeHandle.pointerStyle(alongWidth: true) == .columnResize)
        #expect(PanelResizeHandle.pointerStyle(alongWidth: false) == .rowResize)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: `error: type 'PanelResizeHandle' has no member 'pointerStyle'` (and `no member 'canvasCursor'`).

- [ ] **Step 3: Add the cursors**

Create `Sources/CreatorEditor/CanvasCursor.swift`:

```swift
/// The pointer's shape over the graph canvas (docs/metalui-gaps.md C7 item 5), or none for the arrow.
public enum CanvasCursor: Hashable, Sendable {
    /// A drag pans the canvas: a closed hand.
    case grabbing
}
```

Create `Sources/CreatorEditor/CanvasCursor+MetalUI.swift`:

```swift
import MetalUI

extension CanvasCursor {
    /// The MetalUI pointer style.
    public var pointerStyle: PointerStyle {
        switch self {
        case .grabbing: .grabActive
        }
    }
}
```

Create `Sources/CreatorEditor/EditorModel+Cursor.swift`:

```swift
extension EditorModel {
    /// The pointer's shape over the canvas, or `nil` for the arrow: a closed hand while a drag pans it. MetalUI keeps
    /// a pressed element's style while the pointer leaves it (`CI-H` item 6), so a fast pan keeps the hand. Moving
    /// nodes, wiring and box selection keep the arrow, and so does a canvas at rest: an open hand over empty canvas
    /// alone would need a hit test on every hover move.
    public var canvasCursor: CanvasCursor? {
        if case .panning? = interaction { return .grabbing }
        return nil
    }
}
```

Replace the contents of `Sources/CreatorEditor/GraphCanvas.swift` with:

```swift
import MetalUI

/// The graph canvas: the layers under the zoom and pan transform, one press-and-drag gesture
/// for everything (hit testing is the model's), a pinch, the scroll wheel, the cursor, and pointer
/// tracking for the palette. All input goes through `GraphPanelInput` to the model. The palette itself floats over
/// the whole window (`SearchPaletteOverlay`), so the canvas never clips it.
struct GraphCanvas: Component {
    let model: EditorModel
    let input: GraphPanelInput

    var content: some ElementGroup {
        let transform = model.transform
        return ZStack(alignment: .topLeading) {
            Color.clear
            ZStack(alignment: .topLeading) { CanvasLayers(model: model) }
                .scaleEffect(transform.zoom, anchor: .topLeading)
                .offset(x: transform.offset.x.px, y: transform.offset.y.px)
                .allowsHitTesting(false)
        }
        .clipped()
        .gesture(input.canvasGesture())
        .gesture(input.pinchGesture())
        .contentShape(Rectangle())
        .onContinuousHover { phase in input.hover(phase) }
        .onScrollWheel { event in input.scrolled(event) }
        .pointerStyle(model.canvasCursor?.pointerStyle)
    }
}
```

In `Sources/CreatorEditor/GraphPanelInput.swift`, replace:

```swift
/// - `pinchGesture()`: a `MagnifyGesture` zooms about where the pinch began (`EditorModel.pinchChanged`).
```

with:

```swift
/// - `pinchGesture()`: a `MagnifyGesture` zooms about where the pinch began (`EditorModel.pinchChanged`).
/// - The cursor is the model's (`EditorModel.canvasCursor`, a closed hand while a drag pans); `GraphCanvas` sets it.
```

Replace the contents of `Sources/CreatorApp/PanelResizeHandle.swift` with:

```swift
import CreatorEditor
import CreatorStyle
import MetalUI

/// The graph panel's inner edge (spec §6.1), a visible hairline strip: dragging it resizes the panel, and over it the
/// pointer is a column or row resize cursor (MetalUI C7, `CI-H`), kept while the drag leaves the strip.
struct PanelResizeHandle: Component {
    let model: AppModel
    /// True for the left dock's vertical edge, dragged sideways; false for the bottom dock's top edge.
    let alongWidth: Bool
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        Palette(themes).hairline.color
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(
                DragGesture(minimumDistance: Pixels(0))
                    .onChanged { value in
                        if !model.isResizingPanel { model.beginPanelResize() }
                        let translation = alongWidth ? value.translation.width : value.translation.height
                        model.resizePanel(by: Double(translation.value))
                    }
                    .onEnded { _ in model.endPanelResize() }
            )
            .pointerStyle(Self.pointerStyle(alongWidth: alongWidth))
            .help("Drag to resize the graph panel")
    }

    /// The left dock's vertical edge is dragged sideways (a column resize), the bottom dock's top edge up and down
    /// (a row resize).
    static func pointerStyle(alongWidth: Bool) -> PointerStyle {
        alongWidth ? .columnResize : .rowResize
    }
}
```

- [ ] **Step 4: Run the editor and app tests**

Run: `swift test --filter 'CreatorEditorTests|CreatorAppTests' 2>&1 | grep -E "Test run with|recorded an issue|failed after"`
Expected: `Test run with 204 tests in 30 suites passed` and `Test run with 75 tests in 19 suites passed`, and no issue line.

- [ ] **Step 5: Check the whole package**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "ld: warning"`, `swift test 2>&1 | grep "Test run with" | awk '{s+=$5} END {print s}'` and `swiftlint lint --strict`
Expected: no new warning; **1116**; 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor Sources/CreatorApp/PanelResizeHandle.swift Tests/CreatorEditorTests Tests/CreatorAppTests/PanelResizeCursorTests.swift
git commit -m "feat(editor, app): a closed hand while the canvas pans, resize cursors on the dock edge (MetalUI C7)"
```

### Task 5: Record what C7 closed, the inline-values decision and the human checks

**Files:**
- Modify: `docs/metalui-gaps.md`, `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`, `docs/verification/human-checks.md` (new group GI before group M5), `CLAUDE.md`, `AGENTS.md` (all shared), `Sources/CreatorApp/AppInput.swift` and `Sources/CreatorEditor/GraphPanelHeader.swift` (doc lines)

**Interfaces:**
- Consumes: the names Tasks 1–4 produced and the test names the gaps doc and the human checks cite.
- Produces: documentation only (two doc comments).

- [ ] **Step 1: The gaps doc closes M5-e, M5-f and the resize cursor, and logs GI-a and GI-b**

In `docs/metalui-gaps.md`, replace:

````markdown
are closed for the viewport, and gaps 4 and 5 below with them. The graph panel's adoption (M5-e, M5-f and the
canvas's share of items 1 and 2) is a later plan; the viewport's keys still wait for key scoping (M4-a, MetalUI C9).

The provisional names, as the MetalUI session reported them on 2026-10-08 (all kept: C7's design phase probed
SwiftUI, and where SwiftUI has a spelling MetalUI took it). MetalCreator wraps each stopgap that is left (the graph
panel's, in `GraphPanelInput`) behind one function/modifier of its own, named after these, so the swap is local.
````

with:

````markdown
are closed for the viewport, and gaps 4 and 5 below with them. **The graph panel has adopted it too** (plan
`docs/superpowers/plans/2026-10-09-graph-input-c7.md`): M5-e, M5-f, the canvas's share of items 1, 2 and 5 and the
dock edge's resize cursor are closed, and GI-a and GI-b below are what it found. The viewport's and the graph's keys
still wait for key scoping (M4-a, M5-b, MetalUI C9).

The provisional names, as the MetalUI session reported them on 2026-10-08 (all kept: C7's design phase probed
SwiftUI, and where SwiftUI has a spelling MetalUI took it). No C7 stopgap is left in MetalCreator; the input stopgaps
that remain are for gaps outside C7 (keys, focus, the palette's outside press), in `GraphPanelInput` and `AppInput`.
````

In `docs/metalui-gaps.md`, replace:

````markdown
- **M5-e. Modifiers on a press** (adds to gap 5, which M4's entry made concrete).
````

with:

````markdown
- ✅ **Closed by C7 (graph panel, 2026-10-09):** the canvas's one `DragGesture(minimumDistance: 0)` reads
  `DragGesture.Value.modifiers` (a click those at the press, a drag those when it starts), `GraphPanelInput` no
  longer tracks `.modifiersChanged`, and `dragValueModifiers(_:)` and `spatialTapGesture()` are gone. A click's
  location is still that drag's, not a `SpatialTapGesture`'s, because a tap's value has no modifiers (GI-a).
  **M5-e. Modifiers on a press** (adds to gap 5, which M4's entry made concrete).
````

In `docs/metalui-gaps.md`, replace:

````markdown
- **M5-f. Canvas scroll and pinch** (adds to items 1 and 2).
````

with:

````markdown
- ✅ **Closed by C7 (graph panel, 2026-10-09):** `.onScrollWheel` pans the canvas by the scroll's delta (momentum
  honoured) and ⌘-scroll zooms about `ScrollEvent.location` (`EditorModel.scrolled(by:at:modifiers:phase:)`; a
  trackpad scroll zooms or pans as it began, and a zoom's glide is ignored); `MagnifyGesture` zooms about
  `startLocation` (`EditorModel.pinchChanged`). The +/− keys and the header's zoom buttons stay; the keys' hover veto
  in `AppInput` stays until keys are scoped (M4-a, M5-b).
  **M5-f. Canvas scroll and pinch** (adds to items 1 and 2).
````

In `docs/metalui-gaps.md`, replace:

````markdown
- **Cursor for the dock's resize edge** (adds to C7 item 5).
````

with:

````markdown
- ✅ **Closed by C7 (2026-10-09):** `PanelResizeHandle` shows `.columnResize` on the left dock's edge and
  `.rowResize` on the bottom dock's (`PanelResizeHandle.pointerStyle(alongWidth:)`).
  **Cursor for the dock's resize edge** (adds to C7 item 5).
````

In `docs/metalui-gaps.md`, replace:

````markdown
  pinch over the palette reaches what is under it, where nothing takes a pinch yet (gap 2).
````

with:

````markdown
  pinch over the palette does nothing: the palette is the pinch's target (`CI-D`) and nothing on its chain takes a
  pinch (`PaletteDock` is drawn beside the graph panel and the viewport, not inside them), so it stays open.
````

In `docs/metalui-gaps.md`, replace:

````markdown

## Node-drag performance, 2026-10-08
````

with:

````markdown

## Hit by the graph panel's C7 adoption, 2026-10-09

Labelled GI-a… so they don't clash with the C7 items 1–5 or the M4-a…, M5-a…, M6-a…, VI-a… and PERF-a… entries.

- **GI-a. A tap's value has no modifiers.** Shift-click extends the graph's selection (spec §6.2), so a canvas click
  must know whether ⇧ was held at the press. `SpatialTapGesture.Value` carries only `location` (SwiftUI's carries no
  more; a SwiftUI app reads `NSEvent.modifierFlags` or `onModifierKeysChanged(mask:initial:_:)`, which C7 deferred,
  `CI-A`). So the canvas can't be written the viewport's way (a `SpatialTapGesture` inside a nonzero-distance drag):
  it keeps one `DragGesture(minimumDistance: 0)` for clicks and drags, whose values carry the location and the
  modifiers (`CI-G`), and `EditorModel` tells a click from a drag by its own 3-point threshold, beside MetalUI's
  5-point tap slop. Every value is C7's, so nothing here is undone later, but the canvas can't recognise a double
  click. Wanted: `modifiers` on `SpatialTapGesture.Value` (MetalUI-only, as `DragGesture.Value.modifiers` is,
  divergence 140), or `onModifierKeysChanged`.
- **GI-b. No wheel latching, met by a canvas pan's glide** (MetalUI `CI-AD`, stated, not built). A flick that pans
  the graph canvas glides on through momentum events, and MetalUI sends each to whatever is under the pointer at that
  event. If the pointer drifts off the canvas mid-glide, the canvas stops and the rest of the glide scrolls the node
  library's list or the inspector, if the pointer is over one (the viewport ignores momentum, and the graph panel's
  chrome claims every scroll). Stopgap: none. Wanted: `CI-AD`'s latch (a scroll gesture's events, momentum included,
  go to the element under its `.began`). Human check GI-1 records what happens.
- **VI-a, met again.** The canvas's pinch keeps its start in `EditorModel` too, so a pinch that changes at another
  centre while one is under way, or finds the canvas moved since that one's last change, ends it first
  (`aPinchThatLostItsEndDoesntPullTheNextOneBack`, `aPinchThatLostItsEndDoesntUndoWhatMovedTheCanvasSince`); a lost
  pinch end followed by a pinch at the same centre, with nothing moving the canvas between, zooms from the lost
  pinch's start. A canvas press already drops a press that lost its release (`EditorModel.ensurePress`), its
  modifiers with it (`aLostPressTakesItsModifiersWithIt`).

## Node-drag performance, 2026-10-08
````

- [ ] **Step 2: The carry-over note marks the swap done and records the inline-values decision**

In `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`, replace:

````markdown
  crosshair and closed-hand cursors. The graph panel's own C7 swap (From M5) is still to do.
````

with:

````markdown
  crosshair and closed-hand cursors. The graph panel's own C7 swap (From M5) is done too (plan
  `2026-10-09-graph-input-c7.md`).
````

In `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`, replace:

````markdown
  a canvas `TextField` would fight the canvas-wide gesture and split keyboard focus. Revisit when MetalUI C7 lands.
````

with:

````markdown
  a canvas `TextField` would fight the canvas-wide gesture and split keyboard focus. Revisit when MetalUI C7 lands.
  Revisited after C7 (plan `2026-10-09-graph-input-c7.md`): still read-only. C7 is pointer input; what makes a
  canvas field unsound is untouched by it. (1) Keys: Tab is a window-wide keymap binding that opens the palette
  whenever the pointer is over the canvas (gap M5-b), so in a node's field it would open the palette instead of
  moving focus; keys are scoped to an element only by MetalUI C9. (2) Hit testing: the canvas draws its layers with
  `allowsHitTesting(false)` and every hit is the model's (`EditorModel.hitTest`, computed from `NodeLayout`); a field
  needs its own MetalUI hit region under the canvas's scale, a second hit test that must agree with the model's at
  every zoom, and MetalUI gives a text field's press to the field before any gesture, so a node could no longer be
  dragged by its rows. (3) Cost: a field per unwired input on every node adds to the whole-window rebuild every drag
  step pays (PERF-b). Revisit with MetalUI C9 and PERF-b.
````

In `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`, replace:

````markdown
  handlers (`.onScrollWheel`, `MagnifyGesture`); the +/− keys and header buttons stay.
````

with:

````markdown
  handlers (`.onScrollWheel`, `MagnifyGesture`); the +/− keys and header buttons stay.
  ✅ (graph input C7) Done, with one change: `dragValueModifiers(_:)` is gone (the canvas drag reads
  `DragGesture.Value.modifiers` and `handle(_:)` stops tracking), and so is `spatialTapGesture()`, but the canvas
  keeps its zero-distance drag for clicks, since a `SpatialTapGesture`'s value has no modifiers (gap GI-a). Scroll
  pans and ⌘-scroll zooms (`EditorModel.scrolled(by:at:modifiers:phase:)`), a pinch zooms
  (`EditorModel.pinchChanged`), a pan shows the closed hand (`EditorModel.canvasCursor`), and a scroll, pinch,
  press or hover over the panel's chrome no longer reaches the viewport (`GraphPanel`'s opaque backdrop).
````

In `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`, replace:

````markdown
  `.pointerStyle(.columnResize)` / `.rowResize`, C7 `CI-H`). Key-routing dispatch tests wait for gap M6-e.
````

with:

````markdown
  `.pointerStyle(.columnResize)` / `.rowResize`, C7 `CI-H`). Key-routing dispatch tests wait for gap M6-e.
  ✅ (graph input C7) The resize edge's cursor is done (`PanelResizeHandle.pointerStyle(alongWidth:)`); the hover
  veto stays until MetalUI C9.
````

- [ ] **Step 3: Human checks group GI**

In `docs/verification/human-checks.md`, replace:

````markdown

## Group M5 — the graph panel and inspector (M5)
````

with:

````markdown

## Group GI — graph panel and app input on MetalUI C7

**Status: NOT RUN.** Following MetalUI's convention (`../MetalUI/docs/verification/human-checks.md`); MetalUI's own
group Y covers the platform side (trackpad phases, momentum, every cursor).

The tests pin the model and the conversions from MetalUI values only. The view glue has no headless coverage (no
headless MetalUI window, gap M6-e): `GraphCanvas`'s `.gesture`, `.onScrollWheel` and `.pointerStyle` lines,
`GraphPanel`'s opaque backdrop and `PanelResizeHandle`'s `.pointerStyle`. Run GI-4, GI-1 and GI-6 first: a
failure there is a bug in that glue (or in MetalUI C7), not in the model.

Run `swift run MetalCreatorApp` on a saved bracket, with a trackpad and a wheel mouse; GI-8 also runs
`swift run GraphPanelPreview`.

- [ ] **GI-1 Scroll pans.** Two-finger scroll over the graph canvas pans it in every direction, the nodes following
  the fingers; a flick glides to a stop. A wheel mouse pans up and down a step at a time. Nothing else moves: the
  viewport doesn't zoom and the inspector doesn't scroll. Flick, then move the pointer off the canvas mid-glide, onto
  the viewport and then onto the node library: record whether the glide stops and whether the library scrolls
  (gap GI-b). Pinned: `aWheelStepPansTheCanvasByItsDelta`, `aTrackpadScrollPansAndItsGlideKeepsPanning`,
  `scrollEventsMapToCanvasPhases`. **Observed:**
- [ ] **GI-2 ⌘-scroll zooms about the pointer.** Hold ⌘ and scroll over a node: the node stays under the pointer as
  the canvas zooms. One way zooms in, the other out; note which way feels wrong, if one does (the sign is
  `EditorModel.scrolled(by:at:modifiers:phase:)`'s, the viewport's too). Flick with ⌘ held: the zoom stops when the
  fingers lift, with no glide, and the canvas doesn't pan either, even if ⌘ is let go during the glide. Start a plain
  scroll, then press ⌘ part-way: it keeps panning until the fingers lift. The zoom stops at 25% and 300%. Pinned:
  `commandScrollZoomsAboutThePointer`, `aZoomScrollsGlideIsIgnored`, `aZoomsGlideIsIgnoredOnlyUntilItsMomentumEnds`,
  `aTrackpadScrollZoomsOrPansAsItBegan`, `aScrollThatBeganElsewhereIsTakenUpAsItIsNow`, `theScrollZoomStaysInRange`,
  `aScrollEventZoomsAboutItsLocalPoint`. **Observed:**
- [ ] **GI-3 Pinch.** Pinch out over a node: the canvas zooms in about the point where the pinch began; pinching in
  zooms out, and a hard pinch-in holds at 25% instead of springing back. A pinch over the viewport still zooms the
  viewport, not the canvas. Pinned: `CanvasPinchTests`. **Observed:**
- [ ] **GI-4 The panel's chrome takes the pointer.** Over the graph panel's header (between its buttons), its padding
  and, while one shows, the refusal line under the canvas: scroll, ⌘-scroll and pinch, and nothing moves (before this
  plan the viewport beneath zoomed); click there, and no face is picked or highlighted in the viewport and the
  selection doesn't change; hover there after hovering a face, and the viewport's hover highlight goes. The header's
  buttons still work. Scroll over the node library: its list scrolls and the canvas doesn't. Pinned: none (view
  glue). **Observed:**
- [ ] **GI-5 Modifiers come from the press.** Shift-click two nodes: both are selected. Press on a third with ⇧ held,
  let go of ⇧, then release: it is added too. Click a node without ⇧ right after: only it is selected. ⇧-drag on
  empty canvas box-selects; ⌥-drag a node duplicates it; press on a node, then hold ⌥ before moving: it duplicates.
  Hold ⇧, ⌘-Tab to another app, let go of ⇧ there, come back and click a node: a plain click. Pinned:
  `PressModifierTests`, `modifierChangesAreNeitherClaimedNorTracked`,
  `theCanvasGestureReadsThePressModifiersFromItsValues`, `anOptionDragThroughTheGestureDuplicates`. **Observed:**
- [ ] **GI-6 Cursors.** Drag empty canvas: a closed hand from the moment it pans until the release, also when the
  pointer leaves the panel mid-drag; a click shows none. Moving nodes, dragging a wire and box selection keep the
  arrow. Hover the dock's inner edge: a left-right resize cursor docked left, an up-down one docked at the bottom,
  kept while dragging it. Pinned: `CanvasCursorTests`, `theLeftDocksEdgeIsAColumnResizeAndTheBottomDocksARowResize`.
  **Observed:**
- [ ] **GI-7 The palette.** Open the palette (Space) over the canvas, then scroll or pinch over the canvas outside
  it: it closes. Open it again and scroll over the palette itself: the canvas doesn't move and the palette stays.
  Pinch over the palette: nothing moves (neither the canvas nor the viewport) and it stays open.
  Pinned: `aScrollThatMovesTheCanvasClosesThePalette`, `aPinchClosesThePalette`. **Observed:**
- [ ] **GI-8 Keys unchanged, and the preview.** Over the canvas, + and − still zoom it (not the viewport), F frames
  the viewport, Tab and Space open the palette, and Delete, ⌘C, ⌘V and ⌘D work after a canvas click. Then in
  `swift run GraphPanelPreview`: GI-1, GI-2, GI-3, GI-5 and GI-6's canvas half behave the same. Pinned:
  `AppInputTests`, `KeyCommandTests`. **Observed:**

## Group M5 — the graph panel and inspector (M5)
````

- [ ] **Step 4: CLAUDE.md, AGENTS.md and two doc comments describe the new input**

In `CLAUDE.md`, replace:

````markdown
  Stopgap input (pending MetalUI C7) lives only in `GraphPanelInput`.
````

with:

````markdown
  Its input (MetalUI C7 gestures, and the key and focus stopgaps) lives only in `GraphPanelInput`.
````

In `CLAUDE.md`, replace:

````markdown
Graph panel input stopgaps live only in `GraphPanelInput`. Each C7 stand-in is one function named after its
provisional C7 API (`spatialTapGesture()`, `dragValueModifiers(_:)`), and `install(on:)` chains onto the window's
existing handlers.
````

with:

````markdown
The graph canvas's pointer input is MetalUI C7's, turned into `EditorModel` calls by `GraphPanelInput`: one
`DragGesture(minimumDistance: 0)` for clicks and drags, whose `value.modifiers` the model reads (a `SpatialTapGesture`
has none, gap GI-a), `.onScrollWheel` (`scrolled(by:at:modifiers:phase:)`: pan, ⌘ zooms) and `MagnifyGesture`
(`pinchChanged`); the cursor is `EditorModel.canvasCursor`. Its key, focus and palette stopgaps live only in
`GraphPanelInput` too, and `install(on:)` chains onto the window's existing handlers.
````

In `AGENTS.md`, replace:

````markdown
  Stopgap input (pending MetalUI C7) lives only in `GraphPanelInput`.
````

with:

````markdown
  Its input (MetalUI C7 gestures, and the key and focus stopgaps) lives only in `GraphPanelInput`.
````

In `AGENTS.md`, replace:

````markdown
Graph panel input stopgaps live only in `GraphPanelInput`. Each C7 stand-in is one function named after its
provisional C7 API (`spatialTapGesture()`, `dragValueModifiers(_:)`), and `install(on:)` chains onto the window's
existing handlers.
````

with:

````markdown
The graph canvas's pointer input is MetalUI C7's, turned into `EditorModel` calls by `GraphPanelInput`: one
`DragGesture(minimumDistance: 0)` for clicks and drags, whose `value.modifiers` the model reads (a `SpatialTapGesture`
has none, gap GI-a), `.onScrollWheel` (`scrolled(by:at:modifiers:phase:)`: pan, ⌘ zooms) and `MagnifyGesture`
(`pinchChanged`); the cursor is `EditorModel.canvasCursor`. Its key, focus and palette stopgaps live only in
`GraphPanelInput` too, and `install(on:)` chains onto the window's existing handlers.
````

In `Sources/CreatorApp/AppInput.swift`, replace:

```swift
///   the graph canvas, which fall through to the graph's own zoom keys (gap M5-f). F has no graph binding, so it
```

with:

```swift
///   the graph canvas, which fall through to the graph's own zoom keys (gaps M4-a, M5-b: keys aren't scoped to a
///   hovered element until MetalUI C9). F has no graph binding, so it
```

In `Sources/CreatorEditor/GraphPanelHeader.swift`, replace:

```swift
/// library), zoom buttons (the stopgap for pinch and ⌘-scroll, docs/metalui-gaps.md) and the dock
```

with:

```swift
/// library), zoom buttons (beside pinch and ⌘-scroll on the canvas, and the +/− keys) and the dock
```

- [ ] **Step 5: Check the names the docs cite, and the stopgaps' names are gone**

Run: `for t in aModifierHeldForOnePressDoesntCarryIntoTheNext aLostPressTakesItsModifiersWithIt aShiftPressedOnlyForTheReleaseDoesntExtend modifierChangesAreNeitherClaimedNorTracked theCanvasGestureReadsThePressModifiersFromItsValues anOptionDragThroughTheGestureDuplicates aWheelStepPansTheCanvasByItsDelta aTrackpadScrollPansAndItsGlideKeepsPanning scrollEventsMapToCanvasPhases commandScrollZoomsAboutThePointer aZoomScrollsGlideIsIgnored aZoomsGlideIsIgnoredOnlyUntilItsMomentumEnds aScrollThatBeganElsewhereIsTakenUpAsItIsNow aTrackpadScrollZoomsOrPansAsItBegan theScrollZoomStaysInRange aScrollEventZoomsAboutItsLocalPoint aScrollThatMovesTheCanvasClosesThePalette aPinchClosesThePalette aPinchThatLostItsEndDoesntPullTheNextOneBack aPinchThatLostItsEndDoesntUndoWhatMovedTheCanvasSince theLeftDocksEdgeIsAColumnResizeAndTheBottomDocksARowResize PressModifierTests CanvasPinchTests CanvasCursorTests AppInputTests KeyCommandTests; do grep -rq "$t" Tests || echo "missing $t"; done; grep -rn "spatialTapGesture\|dragValueModifiers\|ViewportModifierTracker" Sources CLAUDE.md AGENTS.md`
Expected: no output from either.

Run: `swift test 2>&1 | grep "Test run with" | awk '{s+=$5} END {print s}'`, `swift test 2>&1 | grep -E "recorded an issue|failed after"` and `swiftlint lint --strict`
Expected: **1116**; nothing; 0 violations.

- [ ] **Step 6: Commit**

```bash
git add docs/metalui-gaps.md docs/superpowers/notes/2026-10-07-m0-m1-carryover.md docs/verification/human-checks.md CLAUDE.md AGENTS.md Sources/CreatorApp/AppInput.swift Sources/CreatorEditor/GraphPanelHeader.swift
git commit -m "docs: the graph panel's C7 adoption closes M5-e and M5-f; gaps GI-a, GI-b; human checks GI"
```

## Self-review

- **Spec coverage.** §6.2 "Click to select, Shift-click to extend, ⇧-drag on empty canvas to box-select. A plain drag on empty canvas pans" — Task 1 (from the press's modifiers; `PointerTests`, `PressModifierTests`). "⌥-drag duplicates" — Task 1 (`optionPressedBeforeTheDragStartsDuplicates`, `anOptionDragThroughTheGestureDuplicates`). "The panel pans and zooms with the stopgap bindings (§9) until MetalUI's C7 item lands" — Tasks 2 and 3 (scroll pans, ⌘-scroll and pinch zoom), with the stopgap keys and buttons kept. §9 items 1, 2 and 5 for the canvas — Tasks 2, 3, 1 and 4; item 4 (tap location) — Key decision 1 and gap GI-a. Errata (M5) "inline value fields … Revisit when MetalUI C7 lands" — Key decision 8, recorded in Task 5. Carry-over From M5's swap points and From M6's resize cursor — Tasks 1–4, marked in Task 5. The brief's stale `ViewportModifierTracker` mention in `GraphPanelInput` — gone with Task 1's rewrite of its doc (Task 5 Step 5 greps for it).
- **Not covered, on purpose:** key scoping (MetalUI C9; every binding is kept), a canvas rotate gesture (spec §6.2 gives none), an open hand at rest and a box-selection crosshair (Key decision 7), inline value fields (Key decision 8), the inspector's chrome (Risks).
- **Placeholders:** none; every code step has its code.
- **Type consistency:** `CanvasModifiers` arguments (Task 1) are what `GraphPanelInput.canvasChanged(_:)`/`canvasEnded(_:)` (1) and `scrolled(_:)` (2) pass; `CanvasScrollPhase` cases `.step/.began/.changed/.ended/.momentum` (2) match `scrollPhase(of:)` and the tests; `pinchChanged(magnification:centre:)`/`pinchEnded()` (3) match `pinchGesture()` and `CanvasCursorTests` (4); `canvasCursor` and `CanvasCursor.pointerStyle` (4) match `GraphCanvas`; `PanelResizeHandle.pointerStyle(alongWidth:)` (4) matches `PanelResizeCursorTests`.
- **Review Focus:** each of the five lines has its test in its task (Tasks 1, 2, 2/3, 2/3, 3/4).
- **New MetalUI gaps:** GI-a (a tap's value has no modifiers) and GI-b (no wheel latching, met by a canvas glide: MetalUI's `CI-AD`, stated, not built), logged in Task 5; VI-a is met again and noted there.

## Verification of this plan

Done on 2026-10-09, before saving this plan. A scratch copy of the worktree at master `d9fedec` (`git archive`),
with a sibling `MetalUI` symlink to `/Users/maxburger/Developer/MetalUI` (master `67a579e`), had every code block
applied mechanically from this file by a script, task by task: Step 1's blocks, then a build (the red check), then
Step 3's blocks (Task 5: every step). Each `In … replace` block matched exactly once; each `Create` path was new.

| After | Red (Step 1 alone) | `CreatorEditorTests` | `CreatorAppTests` | Whole `swift test` | New warnings | `swiftlint lint --strict` |
|---|---|---|---|---|---|---|
| master | — | 174 | 74 | **1085** | — (one pre-existing) | 0 |
| Task 1 | no: `extra argument 'modifiers' in call` | 182 | 74 | **1093** | none | 0 |
| Task 2 | no: `no member 'scrolled'` | 194 | 74 | **1105** | none | 0 |
| Task 3 | no: `no member 'pinchChanged'` | 200 | 74 | **1111** | none | 0 |
| Task 4 | no: `'PanelResizeHandle' has no member 'pointerStyle'` | 204 | 75 | **1116** | none | 0 |
| Task 5 | — (docs) | 204 | 75 | **1116** (master + 31) | none | 0 |

Every `swift test` run exited 0 with no "recorded an issue" or "failed after" line. "New warnings" is
`swift build --build-tests` after each task (incremental, so the changed files recompile): none; master's only compiler
warning is `ContextMenuTests.swift`'s pre-existing one (OCCT's `ld: warning`s are expected). Task 5's Step 5 name and
grep checks printed nothing. The resulting `Sources` and `Tests` trees are byte-identical to the development copy the
code was written in.

Re-verified on 2026-10-09 after review (the chrome's opaque backdrop, the scroll latch's end, a lost pinch that
finds the canvas moved, the palette's pinch): a fresh `git archive` copy at `d9fedec` with the same `MetalUI`
symlink, every block applied by script (each replace matched once), each task's red build as in the table, Tasks 2
and 3's `CreatorEditorTests` runs (194, 200), then after Task 5 a full `swift test` that exited 0 with 1116 tests and
no "recorded an issue" or "failed after" line, `swift build --build-tests` with only the `ContextMenuTests.swift`
warning, `swiftlint lint --strict` clean and Step 5's checks printing nothing.

Not verified here (an agent can't): any real pointer, trackpad or cursor behaviour, and the view glue
(`GraphCanvas`'s modifiers, `GraphPanel`'s opaque backdrop, `PanelResizeHandle`'s cursor), which compiles and renders
headless but is exercised only by human-check group GI (no public headless MetalUI window, gap M6-e).
