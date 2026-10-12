# Adopt MetalUI's Test Harness (MetalUITesting) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Test MetalCreator through its real window with MetalUI's `MetalUITesting` (MetalUI master `280d706`, PR #65): the canvas typing's key, focus and press routing (gap CT-c, CT-1..CT-11 including Undo), the routes gap M6-e named (F, + and − over the viewport versus the canvas, the Edit menu and its chords, the palette's key context), View ▸ Theme's content (TH-a), a warm idle frame by work counts (M7-b), the C10 motion and slider pairing (the M6-e leftovers), and `CommentKeys` on MetalUI's `.primary` modifier (C12, `f2fe54a`).

**Architecture:** One test-support type, `AppWindow` (`Tests/CreatorAppTests/Support`), opens `AppWindowRoot` over `FakeKernel` in a `TestWindow` on `TestApp`'s `HeadlessPlatform`, with the app's own `AppCommands` and `AppInput` installed as `main.swift` installs them, and maps canvas coordinates to window points from `AppLayout`/`GraphPanelLayout`. Every test drives that window with `click`, `doubleClick`, `typeText`, `typeKey` and `advance(by:)` and reads the model, the accessibility tree and `FrameWork`. Nothing under `Sources/` changes except one constant in `CommentKeys` (Task 2) and one stale doc comment in `ThemeMenu` (Task 6); `MetalUITesting` joins `CreatorAppTests` only, never a product target.

**Tech Stack:** Swift 6.4 strict, Swift Testing, MetalUI `MetalUITesting` (product of the `../MetalUI` path package).

**Spec:** `docs/metalui-gaps.md` (entries M6-e, TH-a, M7-b, CT-c, the "M6-e and M7-b, used again" paragraph, CM-a), `../MetalUI/docs/testing.md` at master `280d706` (read-only; `## Replacing an app's own platform fake` and `### Recipe: typing into a canvas app's field` are the model for the typing tests), the human checks CT-1..CT-11 in `docs/verification/human-checks.md`, under the parent spec `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` with all its Errata.

**Branch:** `harness` in `/Users/maxburger/Developer/MetalCreator-harness`, off master `9e5d2d5` (2,639 tests). Run every command from that worktree; never from `/Users/maxburger/Developer/MetalCreator` or another worktree. Never edit `../MetalUI`. Never run the release benchmark. Never take screenshots. Do not commit unless executing this plan task by task (the author of this plan committed nothing).

## What the code reading found (read before Task 1)

- **MetalCreator has no platform fake to replace.** `grep -rn "FakePlatform\|PlatformWindow\|HeadlessPlatform\|: Platform" Sources Tests` finds nothing. The M6-e stopgap was *no test at all* (the key routing was pinned only as mapping, `AppInputTests`, plus human checks). Scope item (1) is therefore "adopt `TestApp`/`TestWindow` where the old checks were manual", and there is no fake to delete; the gap entry says so. `renderFrame` (RenderSupport, the render tests, the benchmarks) is not a platform fake: it draws one cold frame and stays.
- **The type is `Modifiers.primary`.** The task text says `EventModifiers.primary`; MetalUI declares `Modifiers.primary` (`InputEvent.swift`) and `public typealias EventModifiers = Modifiers`, so `CommentKeys.commitModifier: Modifiers = .primary` is the same thing. It is ⌘ on macOS (so `CommentKeysTests` stays green with no edit), ⌃ elsewhere.
- **The window's size never reaches the app headless, and that is a limit of the harness, not a MetalUI gap.** The app's size is the viewport's `observedViewSize`, recorded from the `MetalView` draw (gap M4-a's stopgap); `MetalUITesting` records a `MetalView` draw and does not run it. `../MetalUI/docs/testing.md` lists that under "What it cannot do" (ruled deferral `HT-Q`: no GPU context to hand the closure), so the guide never promised it and the brief makes no gap of it. In a `TestWindow`, `model.panelPlacement` is `nil` and `observedViewSize` is 0 × 0. Clicks still work (a gesture's location is local to the canvas), so `AppWindow` computes where the canvas is from `AppLayout` and `GraphPanelLayout`. Nothing is set on the model to fake a size. The fix is app-side: `onGeometryChange(for:of:action:)` is public on MetalUI master (`Sources/MetalUI/GeometryChange.swift`, KF-J, C9; `GeometryProxy.size`), so the size half of M4-a can be adopted, the draw-time record dropped, and then `panelPlacement` and `canvasFrameInWindow` work headless. That is an app follow-up recorded in the M6-e entry (Task 1) and listed as decision D1; no new gap is logged and nothing is forwarded to the MetalUI session.
- **Facts the tests rely on (measured, not assumed):** a `TestWindow` action draws one frame afterwards, so a field's focus-loss `onChange(of:)` runs one frame after the click (call `runUntilIdle()`); a tick with nothing dirty draws no frame (`framesDrawn` does not move); `setNeedsRedraw()` then `tick()` draws a warm frame whose atlas, raster and texture counters are 0 but whose layout cache misses are not (hundreds at 1440 × 900: that is PERF-b, C14); the default dock is `.left`; `window.doubleClick(at:)` followed by a plain click on the same note is *three* clicks to the editor's recogniser, so a test that wants a fresh double click presses nothing on the note first; a refused connection shakes the target node by +6 pt at 0.05 s, −6 pt at 0.15 s and rests at 0.2 s. **Routes measured through the real window (probed, then pinned):** a press on the 3D viewport commits a canvas edit and clears focus (it goes through `AppModel+Viewport`, not the viewport's draw); dragging a frame's title bar moves the frame and the nodes inside it as one "Move" step; ⌘Z and ⇧⌘Z undo and redo the document's last step over the canvas and over the viewport (over the canvas the graph's own ⌘Z answers, over the viewport the Edit menu's), and the Edit menu's titles read "Undo Edit Note" and "Redo"; while an editor is focused ⌘Z undoes the field's typing and leaves the document alone; Space over the canvas opens the palette with its search field focused; the inspector's accent swatch changes the accent but does not end a canvas edit (decision D4). Two of the app's stopgaps are redundant under C9 and the tests do not pin them: with `AppInput`'s canvas hover veto removed, or the viewport keys' `Panel` key context removed, every window test here still passes (the canvas's key region and the focused field claim the keys first); `AppInputTests` keeps pinning the mapping.

## Global Constraints

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`: full Swift 6 strict concurrency; data-race violations are compile errors. Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), never XCTest.
- Platform `.macOS(.v26)`; `AGENTS.md`/`CLAUDE.md`: `@MainActor @Observable` models, behaviour in models and thin views, one type per file, no force unwraps or force `try`, no GCD, `FormatStyle` (no `String(format:)`, no `DateFormatter`), `foregroundStyle`, no `Task.sleep(nanoseconds:)`.
- `swiftlint lint --strict` reports zero violations (`.swiftlint.yml`: line length 140, comments exempt, trailing commas required in multi-line literals).
- Package.swift: the `MetalUI` path dependency (`.package(path: "../MetalUI")`) is not edited. `MetalUITesting` is added to **test targets' dependencies only**, never to a library or executable target.
- MetalUI gaps are logged in `docs/metalui-gaps.md` (the entry *and* the summary table row) and are never worked around. No timing assertions anywhere in this plan: counts, never time.
- A full `swift test` passes only if the exit code is 0, no line says `recorded an issue` or `failed after` (Swift Testing prints glyphs, not ✘), and 11 `Test run with` lines appear. No new warning (the warnings in the project's `Sources`/`Tests` are exactly master's one, `ContextMenuTests.swift:140`).
- The tests never touch `~/Library` or the person's themes: `AppModel` is built with the default in-memory `ThemeStore()`.

## Review Focus

Failure modes the spec implies that a person using the editor would hit, most likely first; each has its test (named) in the owning task.

1. **A double click on a note must open the editor over that note in either dock and at any zoom, with focus already in it.** `CanvasNoteTypingWindowTests.aDoubleClickOpensAFocusedEditorExactlyOverTheNote` (both docks), `theEditorFollowsTheCanvasZoom` (Task 3).
2. **Leaving the field by any route must keep what was typed: a click on empty canvas, a double click on another comment, a click into the inspector's box.** `aClickOnTheCanvasAwayFromTheNoteCommitsAndClearsFocus` (Task 3), `aDoubleClickOnAnotherCommentCommitsTheFirstAndFocusesTheNext`, `clickingIntoTheInspectorsBoxCommitsTheCanvasEditFirst` (Task 4).
3. **While a field has focus the graph's keys must not delete a node or open the palette; once it has not, they must work again over the canvas.** `CanvasTypingKeysWindowTests` (Task 4).
4. **A blank frame title must be refused with the old title kept, not applied.** `CanvasTitleTypingWindowTests.aBlankTitleIsRefusedAndTheOldOneStays` (Task 3).
5. **An idle editor must draw nothing, and a refused edit must shake the node, once per refusal, and come home.** `WarmFrameTests.anIdleWindowDrawsNoFrameAtAll` (Task 7), `RefusalShakeWindowTests` (Task 8).
6. **F, + and − must act on the surface under the pointer, a focused field must keep them, and the Edit menu's Undo and Redo and the copy, paste and duplicate chords must still run ahead of the graph's keys.** `ViewportKeyRoutingWindowTests`, `EditMenuRoutingWindowTests`, `PaletteKeyRoutingWindowTests` (Task 5).
7. **⌘Z around a canvas edit must undo the document between edits and only the typing while a field is focused, and a press on the viewport must not lose what was typed.** `CanvasTypingUndoWindowTests`, `CanvasTypingFocusWindowTests.aPressOnTheViewportCommitsTheEditAndClearsFocus` (Task 4).

## User decisions

Product questions the spec leaves open. Each has a default the plan is written for, so an unanswered question changes nothing.

| # | Question | Options | Default in this plan (recommended) |
|---|---|---|---|
| D1 | The harness runs no `MetalView` draw, so the app never learns its window size headless (`panelPlacement` is `nil`). Gap, or app follow-up? | (a) app follow-up: adopt `onGeometryChange` (KF-J) for the window size, drop the draw-time record, then `panelPlacement` and `canvasFrameInWindow` work headless; (b) forward it to the MetalUI session as a gap | (a). The guide lists it under "What it cannot do" (ruled deferral HT-Q), so it is not a gap, and `onGeometryChange` is already public. `AppWindow.canvasFrame` stays the stopgap either way. Recorded in the M6-e entry and the M4-a row; no gap logged |
| D2 | CT-8: while an editor is focused, ⌘Z undoes the field's typing and leaves the document alone (measured). Pin it, or leave it a human record? | (a) pin it in `CanvasTypingUndoWindowTests`; (b) leave it to a person | (a). It fails if MetalUI starts passing ⌘Z on to the Edit menu while a field is focused; the CT-8 human check keeps only the physical keyboard |
| D3 | Ship the tests for the routes M6-e named (M6-4, M6-5, EP-2) in this track, or in a follow-up? | (a) this track (Task 5); (b) a follow-up | (a). They need no new helper and are the entry's own named blocker; M6-e would otherwise be marked adopted on the strength of a menu bar and a hover test |
| D4 | The inspector's accent swatch changes the accent but does not end a canvas edit (the edit stays open with its draft; the next canvas press commits; two undo steps). Human check CT-2 expects the swatch to commit the text. Leave it, or make a swatch press commit the edit first? | (a) leave it, pin the measured behaviour, reword CT-2 to "record what happens"; (b) commit the canvas edit first (a source change in `EditorModel+CommentInspector`, out of this plan) | (a). Nothing is lost either way (`anAccentSwatchPressChangesTheAccentAndLeavesTheEditOpenWithNothingLost`), and a source change belongs to a plan of its own; choosing (b) flips that one test |
| D5 | A human check the harness now drives completely (CT-5, CT-9): tick it `[x]` with no "Observed", or leave it for a person's glance? | (a) tick `[x]`, "Automated, no manual step"; (b) leave unticked | (a). The look-and-feel parts of the same checks (CT-1, CT-6, CT-10) stay unticked |
| D6 | Move the release benchmarks (`Tests/CreatorAppTests/Bench`) onto the warm window (M7-b)? | (a) now; (b) later, in a plan that also runs the release benchmark | (b). This plan never runs the benchmark, and `performance.md` stays "cold frames, an upper bound" until it does |
| D7 | Pin zero layout work in a warm frame? | (a) pin; (b) leave it to PERF-b | (b). A forced warm redraw re-measures (hundreds of layout cache misses at 1440 × 900: PERF-b, C14), so a zero would fail; the plan pins atlas, raster, blur and texture counts instead |
| D8 | Edit the doc comments and human-check wordings that still say "no headless window" (one line in `Sources/CreatorApp/ThemeMenu.swift`, three test files, groups V, GI, AS, MS, CM)? | (a) reword them (Tasks 6 and 9); (b) leave them and say so | (a). They are false after this plan; no behaviour changes |
| D9 | The evaluating spinner's turning (C10-3) cannot be held in a test (no kernel waits). Leave it a human check? | (a) leave; (b) add a waiting test kernel | (a). A kernel that waits is a test-support type of its own and the still frame is already pinned |

## Files shared with other tracks

`7a-layouts` (`../MetalCreator-7a-layouts`) and `7a-variation` (`../MetalCreator-7a-variation`) merge first; **this track merges after both** and keeps their changes. Where both add to a file, keep both.

| File | What this track changes | What the side that merges second (this one) keeps |
|---|---|---|
| `docs/metalui-gaps.md` | edits the M6-e, TH-a, M7-b, CT-c and M4-a table rows and the M6-e, TH-a, M7-b, CT-c entries, the "M6-e and M7-b, used again" and CM-a paragraphs; adds **no row and no section** (HT-a was dropped: it is a harness limit, recorded inside the M6-e entry) | any gap row or section the 7a tracks add (keep every row of both) and their entry text untouched; if one of them edited the M4-a row, keep their wording and add the `onGeometryChange` sentence to it |
| `docs/verification/human-checks.md` | edits the `## Group CT` section (header paragraph, CT-1, 2, 3, 4, 5, 6, 8, 9, 10, 11) and, outside it, only the clause that cites gap M6-e or "no headless window" in M6-4, M6-5, EP-2, group C10's header, C10-2 and C10-4, and the headers or lines of groups V, GI, AS, MS and CM (Tasks 4, 5, 8, 9) | the 7a tracks' new groups and edits elsewhere in the file; do not reflow any group; if a 7a edit touched one of these lines, keep both edits |
| `Package.swift` | adds the `metalUITesting` constant and its use in `CreatorAppTests` | any dependency the 7a tracks add to test targets (CreatorNodesTests etc.); both edits are on different lines |
| `Tests/CreatorAppTests/` | adds new files and `Support/AppWindow.swift`, `Support/TypingFixture.swift`; edits the doc comments of `AppInputTests.swift` and `AppModelCloseTests.swift` (Task 9) and nothing else in existing files | their new files; they edit no file here, so no textual conflict is expected |
| `Tests/CreatorSketchEditorTests/SketchViewTests.swift` | one stale doc comment (Task 9) | nothing of theirs: no 7a track touches it |
| `Sources/CreatorApp/ThemeMenu.swift` | one doc-comment line (Task 6) | any change they make to `ThemeMenu` (none expected) |
| `CLAUDE.md`, `docs/superpowers/roadmap.md` | **not touched** (the 7a tracks own them) | the roadmap row "MetalUI public test harness (item 8)" is stale after this merge; correct it in the merge commit, not here |

After the merge the full-run total is master + the 7a-layouts tests + the 7a-variation tests + 50; re-run the whole suite there.

## File Structure

| File | Responsibility |
|---|---|
| `Package.swift` (modify) | `metalUITesting` dependency constant, added to `CreatorAppTests` only |
| `Tests/CreatorAppTests/Support/AppWindow.swift` (create) | the app's real root in a `TestWindow`; canvas-to-window geometry; small input helpers |
| `Tests/CreatorAppTests/Support/TypingFixture.swift` (create) | two notes, a frame and a Rectangle node at fixed places |
| `Tests/CreatorAppTests/AppWindowTests.swift` (create) | the window opens the real root and its geometry helpers agree with MetalUI's routing |
| `Sources/CreatorEditor/CommentKeys.swift`, `Tests/CreatorEditorTests/CommentKeysTests.swift` (modify) | commit modifier is `.primary` |
| `Tests/CreatorAppTests/CanvasNoteTypingWindowTests.swift`, `CanvasTitleTypingWindowTests.swift`, `CanvasTypingKeysWindowTests.swift`, `CanvasTypingFocusWindowTests.swift`, `CanvasTypingUndoWindowTests.swift` (create) | CT-1..CT-11, headless |
| `Tests/CreatorAppTests/ViewportKeyRoutingWindowTests.swift`, `EditMenuRoutingWindowTests.swift`, `PaletteKeyRoutingWindowTests.swift` (create) | the routes gap M6-e named (M6-4, M6-5, EP-2) |
| `Tests/CreatorAppTests/ThemeMenuEvaluationTests.swift` (create) | TH-a |
| `Tests/CreatorAppTests/WarmFrameTests.swift` (create) | M7-b |
| `Tests/CreatorAppTests/InspectorSliderWindowTests.swift`, `RefusalShakeWindowTests.swift` (create) | the C10 leftovers of M6-e |
| `docs/metalui-gaps.md`, `docs/verification/human-checks.md` (modify) | mark adopted; record the harness limit and the `onGeometryChange` follow-up in M6-e's entry; mark the human checks automated or reword their M6-e citations |
| `Sources/CreatorApp/ThemeMenu.swift`, `Tests/CreatorAppTests/AppInputTests.swift`, `AppModelCloseTests.swift`, `Tests/CreatorSketchEditorTests/SketchViewTests.swift` (modify) | doc comments that still say "no headless window" |

## Interfaces (what later tasks use)

```swift
// Tests/CreatorAppTests/Support/AppWindow.swift  (Task 1; helpers added in Tasks 3, 4, 7)
@MainActor struct AppWindow {
    static let defaultSize: Vector2                      // 1440 x 900
    let model: AppModel, themeEditor: ThemeEditorModel, testApp: TestApp, window: TestWindow, size: Vector2
    static func open(_ graph: Graph = Graph(), dock: DockSide = .bottom, zoom: Double = 1,
                     recordsLayout: Bool = true) async throws -> AppWindow
    var editor: EditorModel { get }
    var canvasFrame: CanvasRect { get }                  // the canvas in window points
    func point(inCanvas: Vector2) -> Point<Pixels>       // a canvas coordinate through pan and zoom
    func point(inCanvasView: Vector2) -> Point<Pixels>   // a canvas-local screen point
    func windowPoint(_ vector: Vector2) -> Point<Pixels>
    func centre(ofComment: CommentID) -> Point<Pixels>   // Task 3
    func titleBarCentre(ofFrame: CommentID) -> Point<Pixels>   // Task 3
    var inspectorColumnStart: Double { get }             // Task 4
    func redraw()                                        // Task 7
}
// Tests/CreatorAppTests/Support/TypingFixture.swift  (Task 3)
struct TypingFixture { let note, otherNote: StickyNote; let box: CommentFrame; let rectangle: Node; let graph: Graph }
```

### Task 1: Adopt `MetalUITesting` in `CreatorAppTests` and open the app's real window

**Files:**
- Modify: `Package.swift` (the `metalUI` constant block; `CreatorAppTests` dependencies)
- Create: `Tests/CreatorAppTests/Support/AppWindow.swift`, `Tests/CreatorAppTests/AppWindowTests.swift`
- Modify: `docs/metalui-gaps.md` (M6-e row and entry, M4-a row and entry)

**Interfaces:**
- Consumes: `AppModel(kernel:file:)`, `AppModel.settle()`, `AppModel.panelPlacement(inWindowOf:)`, `ThemeEditorModel(themes:)`, `AppInput(model:)`, `AppInput.install(on:)`, `AppCommands.install(on:model:themeEditor:)`, `AppWindowRoot`, `EditorModel.now`, `EditorModel.transform`, `GraphPanelLayout.canvasFrame(inPanelOf:flow:showsLibrary:)`; MetalUITesting's `TestApp()`, `TestApp.openWindow(title:size:recordsLayout:content:)`, `TestApp.menuBar`, `TestWindow.hover(at:)`, `.title`, `.framesDrawn`.
- Produces: `AppWindow` as in the Interfaces block (Task 1 members only).

- [ ] **Step 1: Add the product to the test target.** In `Package.swift`, after the `metalUI` constant add the second constant, and append it to `CreatorAppTests`.

```swift
let metalUI: Target.Dependency = .product(name: "MetalUI", package: "MetalUI")

/// MetalUI's headless test harness (`docs/testing.md` in MetalUI): a dependency of test targets only, never of a product.
let metalUITesting: Target.Dependency = .product(name: "MetalUITesting", package: "MetalUI")
```

```swift
                "CreatorGeometry", "CreatorOCCT", "CreatorStyle", "CreatorSketch", "CreatorSketchEditor", metalUI, metalUITesting,
```

(The second block replaces the last line of `CreatorAppTests`'s dependency list, which ends `metalUI,` today. The `.package(path: "../MetalUI")` line is untouched.)

- [ ] **Step 2: Write the failing test.** `Tests/CreatorAppTests/AppWindowTests.swift`:

```swift
import CreatorGeometry
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The app's real window over MetalUITesting's headless platform (`AppWindow`): it opens the app's own root with the
/// app's own menu bar, and its geometry helpers agree with where MetalUI routes the pointer.
@MainActor
struct AppWindowTests {
    @Test func theRealRootOpensWithTheAppsMenuBar() async throws {
        let app = try await AppWindow.open()
        #expect(app.window.title == "MetalCreator")
        let titles = app.testApp.menuBar.map(\.title)
        #expect(["File", "Edit", "View"].allSatisfy(titles.contains))
        #expect(app.window.framesDrawn >= 1)
    }

    @Test func aPointInTheCanvasReachesTheCanvasAtTheSamePlace() async throws {
        let app = try await AppWindow.open()
        let local = Vector2(120, 80)
        app.window.hover(at: app.point(inCanvasView: local))
        #expect(app.editor.pointerLocation == local, "the canvas sees the pointer where the helper put it")
        app.window.hover(at: Point(x: Pixels(700), y: Pixels(300)))
        #expect(app.editor.pointerLocation == nil, "and sees it leave over the viewport")
    }
}
```

- [ ] **Step 3: Run it to see it fail.**

Run: `swift test --filter AppWindowTests 2>&1 | grep -E "error:" | head -3`
Expected: build error `cannot find 'AppWindow' in scope`.

- [ ] **Step 4: Write `AppWindow`.** `Tests/CreatorAppTests/Support/AppWindow.swift`:

```swift
// Test fixture file: the app's real root in a real MetalUI window over MetalUITesting's headless platform.
import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import MetalUITesting
@testable import CreatorApp

/// `MetalCreatorApp`'s window without a screen: `AppWindowRoot` over `FakeKernel` in a `TestWindow`, with the app's
/// menu bar and input hooks installed as `main.swift` installs them (`AppCommands`, `AppInput`). Clicks and keys reach it
/// through MetalUI's own routing, so key regions, focus and gestures run as in the app.
///
/// MetalUI does not run a `MetalView`'s draw headless (its ruling HT-Q), and the app learns its window's size from the
/// viewport's draw (gap M4-a), so `model.panelPlacement` stays `nil` here. The panel is where `AppLayout` puts it for
/// `size`, and `point(inCanvas:)` and `canvasFrame` compute from that, the way the app's layout numbers do.
@MainActor
struct AppWindow {
    static let defaultSize = Vector2(1440, 900)

    let model: AppModel
    let themeEditor: ThemeEditorModel
    let testApp: TestApp
    let window: TestWindow
    let size: Vector2

    /// The app showing `graph` (docked as `dock`, the node library hidden, the canvas zoomed as given), evaluated, with
    /// the first frame drawn. The editor's double-click recogniser reads a clock that never moves, so two clicks in a row
    /// are always a double click, however loaded the machine is.
    static func open(_ graph: Graph = Graph(), dock: DockSide = .bottom, zoom: Double = 1,
                     recordsLayout: Bool = true) async throws -> AppWindow {
        let size = defaultSize
        let viewState = ViewState(dock: dock, canvasZoom: zoom, showsLibrary: false)
        let model = AppModel(kernel: FakeKernel(), file: GraphFile(graph: graph, viewState: viewState))
        await model.settle()
        let instant = ContinuousClock.now
        model.editor.now = { instant }
        let themeEditor = ThemeEditorModel(themes: model.themes)
        let input = AppInput(model: model)
        let testApp = try TestApp()
        AppCommands.install(on: testApp.app, model: model, themeEditor: themeEditor)
        let window = try testApp.openWindow(
            title: "MetalCreator", size: Size(width: Pixels(Float(size.x)), height: Pixels(Float(size.y))),
            recordsLayout: recordsLayout
        ) {
            ZStack { AppWindowRoot(model: model, input: input, themeEditor: themeEditor) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        input.install(on: window.window)
        return AppWindow(model: model, themeEditor: themeEditor, testApp: testApp, window: window, size: size)
    }

    var editor: EditorModel { model.editor }

    /// The graph canvas in window points, from `AppLayout` and `GraphPanelLayout`.
    var canvasFrame: CanvasRect {
        guard let placement = model.panelPlacement(inWindowOf: size) else { return CanvasRect(origin: .zero, size: .zero) }
        let local = GraphPanelLayout.canvasFrame(inPanelOf: placement.panel.size, flow: editor.flow,
                                                 showsLibrary: editor.showsLibrary)
        return CanvasRect(origin: placement.panel.origin + local.origin, size: local.size)
    }

    /// The window point of a point in canvas coordinates (a note's corner, say), through the canvas's pan and zoom.
    func point(inCanvas point: Vector2) -> Point<Pixels> {
        windowPoint(canvasFrame.origin + editor.transform.toScreen(point))
    }

    /// The window point of a canvas-local screen point.
    func point(inCanvasView local: Vector2) -> Point<Pixels> {
        windowPoint(canvasFrame.origin + local)
    }

    /// A window point from a vector.
    func windowPoint(_ vector: Vector2) -> Point<Pixels> {
        Point(x: Pixels(Float(vector.x)), y: Pixels(Float(vector.y)))
    }
}
```

- [ ] **Step 5: Run the tests.**

Run: `swift test --filter AppWindowTests 2>&1 | grep -E "Test run with|recorded an issue"`
Expected: `Test run with 2 tests in 1 suite passed`.

- [ ] **Step 6: Mark M6-e adopted and record what the harness cannot do (a limit, not a gap).** From the worktree root:

```bash
python3 - <<'PY'
def rep(path, old, new):
    text = open(path, encoding="utf-8").read()
    assert text.count(old) == 1, f"{path}: anchor found {text.count(old)} times: {old[:60]!r}"
    open(path, "w", encoding="utf-8").write(text.replace(old, new))

GAPS = "docs/metalui-gaps.md"

rep(GAPS,
    "| M6-e | Public headless test window | item 8 (test harness) | 🟡 landed in MetalUI master 280d706 (item 8, `MetalUITesting`); adoption here pending |",
    "| M6-e | Public headless test window | item 8 (test harness) | ✅ fixed (MetalUI 280d706, PR #65: `MetalUITesting`), adopted in the test targets (plan `2026-10-12-adopt-test-harness`): `AppWindow` opens the app's real root in a `TestWindow` (`AppWindowTests`); MetalCreator had no platform fake of its own to replace; the harness's one limit for this app (no `MetalView` draw, so no window size) and its app-side fix are in the entry |")

rep(GAPS,
    "  `Window` (or `FakePlatformWindow` in a test-support product) with `simulateInput` and a rendered frame.\n",
    "  `Window` (or `FakePlatformWindow` in a test-support product) with `simulateInput` and a rendered frame.\n"
    "  **Fixed by MetalUI item 8** (master 280d706, PR #65: the `MetalUITesting` product) **and adopted** (plan\n"
    "  `2026-10-12-adopt-test-harness`): `CreatorAppTests` depends on `MetalUITesting`, and `AppWindow` (test support) opens\n"
    "  `AppWindowRoot` over `FakeKernel` in a `TestWindow` with the app's own `AppCommands` and `AppInput`, so clicks and\n"
    "  keys go through MetalUI's real routing (`AppWindowTests`). MetalCreator never wrote a `Platform` or `PlatformWindow`\n"
    "  fake (its stopgap was no test at all, the mapping tests and the human checks), so there was nothing to replace or\n"
    "  delete; `renderFrame` stays for the render tests that read one cold frame.\n"
    "  **A limit of the harness, not a MetalUI gap:** `MetalUITesting` records a `GPUSurface`/`MetalView` draw and does not run\n"
    "  it (`../MetalUI/docs/testing.md`, \"What it cannot do\", ruled deferral `HT-Q`: there is no GPU context to hand the\n"
    "  closure), so the guide promises nothing here and nothing is forwarded. The app learns its window's size from that draw\n"
    "  (`ViewportModel.observedViewSize`, gap M4-a's stopgap), so in a `TestWindow` it stays 0 × 0 and `AppModel.panelPlacement`\n"
    "  is `nil`. Clicks and keys are unaffected (a canvas gesture's location is local to the canvas), so the window tests run;\n"
    "  they compute where the canvas is from `AppLayout` and `GraphPanelLayout` (`AppWindow.canvasFrame`) and set nothing on\n"
    "  the model. Not testable headless until the app changes: dropping a library node on the canvas (`canvasFrameInWindow`),\n"
    "  the culling of nodes beyond the panel in a real window, and anything that waits for the first viewport draw.\n"
    "  **App follow-up (decision D1):** `onGeometryChange(for:of:action:)` is public on MetalUI master\n"
    "  (`Sources/MetalUI/GeometryChange.swift`, KF-J, C9; `GeometryProxy.size`), so the size half of M4-a is adoptable now:\n"
    "  take the window's size from it, drop the draw-time `observedViewSize` record, and `panelPlacement` and\n"
    "  `canvasFrameInWindow` work headless and `AppWindow.canvasFrame` can go. Until then `AppWindow.canvasFrame` is the\n"
    "  stopgap.\n")

rep(GAPS,
    "| M4-a | An element's size (`onGeometryChange`), focus on click | C9 | 🔄 open; C9 in progress (`feat/key-focus`) |",
    "| M4-a | An element's size (`onGeometryChange`), focus on click | C9 | 🟡 C9 is on MetalUI master: `onGeometryChange` (KF-J) is public and the canvas adopted the key regions (M5-b, M5-g); the viewport still records its size from its draw and releases focus itself (app follow-up, see M6-e) |")

rep(GAPS,
    "observed `ViewportModel.viewSizeChanges` one task after the draw (`observedViewSize`, which\n     `AppModel.panelPlacement` reads), so a resize rebuilds the canvas at the new size, one frame late. It goes with\n     the stopgap.\n",
    "observed `ViewportModel.viewSizeChanges` one task after the draw (`observedViewSize`, which\n     `AppModel.panelPlacement` reads), so a resize rebuilds the canvas at the new size, one frame late. It goes with\n     the stopgap.\n"
    "     **Update 2026-10-12:** `onGeometryChange(for:of:action:)` is public on MetalUI master (`GeometryChange.swift`, KF-J,\n"
    "     C9), so the size half is no longer a MetalUI request: adopting it here replaces the draw-time record (it also makes\n"
    "     `panelPlacement` available to the headless window tests, see M6-e).\n")
PY
```

(The sentence "MetalCreator never wrote a `Platform` or `PlatformWindow` fake" is true of this repository today; re-check with `grep -rn "PlatformWindow" Sources Tests` before running the script, and if a 7a track added one, replace it here and say so in the entry.)

- [ ] **Step: Full run and lint.**

```bash
swift test 2>&1 | tee /tmp/harness-test.log; echo "exit: ${PIPESTATUS[0]}"
```

```bash
grep -c "Test run with" /tmp/harness-test.log                                   # must print 11
grep -c "recorded an issue\|failed after" /tmp/harness-test.log                # must print 0
grep "Test run with" /tmp/harness-test.log | sed -E 's/.*with ([0-9]+) tests?.*/\1/' | paste -sd+ - | bc   # the total
grep "warning:" /tmp/harness-test.log | grep -E "/(Sources|Tests)/" | sort -u   # only ContextMenuTests.swift:140 (already on master)
swiftlint lint --strict --quiet                                                 # no output
```

Expected: exit 0, 11 `Test run with` lines, 0 issue lines, total **2641** (master + 2), no project-source warning but the one already on master, no lint output.

- [ ] **Step: Commit** (end the message with the attribution lines the session specifies).

```bash
git add -A
git commit -m "test(app): AppWindow, the app's real window over MetalUITesting; M6-e adopted, the headless size limit recorded"
```

### Task 2: `CommentKeys.commitModifier` is MetalUI's `.primary`

**Files:**
- Modify: `Sources/CreatorEditor/CommentKeys.swift`, `Tests/CreatorEditorTests/CommentKeysTests.swift`

**Interfaces:**
- Consumes: `Modifiers.primary` (MetalUI `f2fe54a`, ⌘ on macOS, ⌃ elsewhere).
- Produces: `CommentKeys.commitModifier: Modifiers` (internal, unchanged name and type) now `.primary`; `CommentKeys.commitsNote(_:)` unchanged. The Tasks 3 and 4 tests send `.primary`.

- [ ] **Step 1: Write the test.** Replace the body of `CommentKeysTests` with (the doc comment above the struct stays):

```swift
import MetalUI
import Testing
@testable import CreatorEditor

/// ⌘↩ commits a note's text, in the inspector's box and on the canvas (canvas comments spec 2026-10-09 §7); plain
/// Return, ⇧↩ and ⌥↩ keep breaking the line (MetalUI C9's KF-Z leaves them to the editor).
struct CommentKeysTests {
    @Test func theCommitModifierIsMetalUIsPrimaryModifier() {
        #expect(CommentKeys.commitModifier == .primary)
    }

    @Test func commandReturnCommitsANote() {
        #expect(CommentKeys.commitsNote(.primary))
        #expect(CommentKeys.commitsNote([.primary, .shift]))
    }

    @Test func otherReturnsBreakTheLine() {
        let others: [Modifiers] = [[], .shift, .option, .control, .command]
        for modifiers in others where modifiers != .primary {
            #expect(!CommentKeys.commitsNote(modifiers))
        }
    }
}
```

- [ ] **Step 2: Run it.** `swift test --filter CommentKeysTests 2>&1 | grep -E "Test run with|recorded an issue"`
Expected on macOS: `3 tests ... passed` (this is a characterization: `.primary` equals `.command` here, so the new test cannot fail before the change; it fails off macOS or if the constant is changed, which Step 4 proves).

- [ ] **Step 3: Change the constant.** Replace the whole `#if os(macOS)` block in `Sources/CreatorEditor/CommentKeys.swift` (the doc comment and both constants) with:

```swift
    /// The platform's shortcut modifier: MetalUI's `Modifiers.primary` (⌘ on macOS, ⌃ elsewhere; MetalUI C12, `SG-B`).
    static let commitModifier: Modifiers = .primary
```

and change the doc comment of `commitsNote` to start `/// ⌘↩ (⌃↩ off macOS: the primary modifier) commits a note's text`.

- [ ] **Step 4: Prove the test bites.** Temporarily change `.primary` to `.option`, run `swift test --filter CommentKeysTests` (Expected: 4 issues, in all three tests), then restore `.primary`.

- [ ] **Step: Full run and lint.**

```bash
swift test 2>&1 | tee /tmp/harness-test.log; echo "exit: ${PIPESTATUS[0]}"
```

```bash
grep -c "Test run with" /tmp/harness-test.log                                   # must print 11
grep -c "recorded an issue\|failed after" /tmp/harness-test.log                # must print 0
grep "Test run with" /tmp/harness-test.log | sed -E 's/.*with ([0-9]+) tests?.*/\1/' | paste -sd+ - | bc   # the total
grep "warning:" /tmp/harness-test.log | grep -E "/(Sources|Tests)/" | sort -u   # only ContextMenuTests.swift:140 (already on master)
swiftlint lint --strict --quiet                                                 # no output
```

Expected: exit 0, 11 `Test run with` lines, 0 issue lines, total **2642** (master + 3), no project-source warning but the one already on master, no lint output.

- [ ] **Step: Commit** (end the message with the attribution lines the session specifies).

```bash
git add -A
git commit -m "refactor(editor): CommentKeys.commitModifier is MetalUI's primary modifier"
```

### Task 3: CT-c, a note and a frame's title typed through the real window

**Files:**
- Create: `Tests/CreatorAppTests/Support/TypingFixture.swift`, `Tests/CreatorAppTests/CanvasNoteTypingWindowTests.swift`, `Tests/CreatorAppTests/CanvasTitleTypingWindowTests.swift`
- Modify: `Tests/CreatorAppTests/Support/AppWindow.swift` (two helpers)

**Interfaces:**
- Consumes: Task 1's `AppWindow`; `EditorModel.frame(ofComment:)`, `.commentEdit`, `.graph`, `.document.undoName/.canUndo/.undo()`, `.refusal`, `CommentLayout.titleBar(of:)`; `GraphBuilder` (AppTestSupport); MetalUITesting's `doubleClick(at:)`, `click(at:)`, `drag(from:to:steps:)`, `typeText`, `typeKey(_:modifierFlags:)`, `focusedElement`.
- Produces: `AppWindow.centre(ofComment:)`, `AppWindow.titleBarCentre(ofFrame:)`, `TypingFixture` (as in Interfaces).

- [ ] **Step 1: Write the fixture and the failing tests.**

`Tests/CreatorAppTests/Support/TypingFixture.swift`:

```swift
// Test fixture file: a graph with two notes, a frame and a node, for typing on the canvas through the app's window.
import CreatorGeometry
import CreatorGraph
import CreatorNodes
import Foundation

/// A note, a second note, a frame and a Rectangle node, at fixed places well apart on the canvas.
struct TypingFixture {
    let note = StickyNote(id: Self.id(1), text: "Line one", frame: CanvasRect(origin: Vector2(40, 40), size: Vector2(160, 100)))
    let otherNote = StickyNote(id: Self.id(2), text: "Second", frame: CanvasRect(origin: Vector2(40, 150), size: Vector2(160, 60)))
    let box = CommentFrame(id: Self.id(3), title: "Bracket", frame: CanvasRect(origin: Vector2(260, 40), size: Vector2(300, 160)))
    let rectangle: Node
    let graph: Graph

    init() {
        var builder = GraphBuilder()
        rectangle = builder.add(RectangleNode.self, at: Vector2(620, 60))
        var graph = builder.graph
        graph.stickies = [note.id: note, otherNote.id: otherNote]
        graph.frames = [box.id: box]
        self.graph = graph
    }

    static func id(_ n: Int) -> CommentID {
        CommentID(rawValue: UUID(uuidString: "00000000-0000-0000-0001-" + String(repeating: "0", count: 11) + String(n)) ?? UUID())
    }
}
```

`Tests/CreatorAppTests/CanvasNoteTypingWindowTests.swift` (human checks CT-1, CT-2, CT-5, CT-6's geometry):

```swift
import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// Typing into a note on the canvas through the app's real window (human checks CT-1, CT-2, CT-5): the double click,
/// the focus, the text input and the keys travel MetalUI's own routing, so a regression in MetalUI's key regions or in
/// the editor's `onKeyPress` handlers fails here, not only in front of a person.
@MainActor
struct CanvasNoteTypingWindowTests {
    let fixture = TypingFixture()

    func open(dock: DockSide = .bottom) async throws -> AppWindow {
        try await AppWindow.open(fixture.graph, dock: dock)
    }

    @Test(arguments: [DockSide.bottom, .left])
    func aDoubleClickOpensAFocusedEditorExactlyOverTheNote(dock: DockSide) async throws {
        let app = try await open(dock: dock)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        #expect(app.editor.commentEdit?.id == fixture.note.id)
        let field = try #require(try app.window.focusedElement, "focus is in the field the moment it appears")
        #expect(field.role == .textArea)
        #expect(field.value == "Line one")
        let rect = try #require(app.editor.frame(ofComment: fixture.note.id))
        #expect(field.frame.origin == app.point(inCanvas: rect.origin))
        #expect(Double(field.frame.size.width.value) == rect.size.x && Double(field.frame.size.height.value) == rect.size.y)
    }

    /// Human check CT-6's geometry: under the canvas's zoom the editor is scaled as the note is and still lies over it.
    @Test(arguments: [0.5, 2.0])
    func theEditorFollowsTheCanvasZoom(zoom: Double) async throws {
        let app = try await AppWindow.open(fixture.graph, zoom: zoom)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        let field = try #require(try app.window.focusedElement)
        let rect = try #require(app.editor.frame(ofComment: fixture.note.id))
        #expect(abs(Double(field.frame.size.width.value) - rect.size.x * zoom) <= 1)
        #expect(abs(Double(field.frame.size.height.value) - rect.size.y * zoom) <= 1)
        let corner = app.point(inCanvas: rect.origin)
        #expect(abs(field.frame.origin.x.value - corner.x.value) <= 1 && abs(field.frame.origin.y.value - corner.y.value) <= 1)
    }

    @Test(arguments: [DockSide.bottom, .left])
    func returnBreaksTheLineAndCommandReturnCommitsOneUndoStep(dock: DockSide) async throws {
        let app = try await open(dock: dock)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("A")
        app.window.typeKey(.return)
        app.window.typeText("B")
        #expect(app.editor.commentEdit != nil, "Return commits nothing")
        #expect(app.editor.commentEdit?.draft.contains("\n") == true)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one", "typing alone changes nothing in the graph")
        app.window.typeKey(.return, modifierFlags: .primary)
        #expect(app.editor.commentEdit == nil)
        let text = try #require(app.editor.graph.stickies[fixture.note.id]?.text)
        #expect(text.contains("A\nB"), "Return broke the line; the caret opens at the start (gap CT-b)")
        #expect(app.editor.document.undoName == "Edit Note")
        app.editor.document.undo()
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one")
    }

    @Test(arguments: [DockSide.bottom, .left])
    func escapeCancelsAndLeavesNothingToUndo(dock: DockSide) async throws {
        let app = try await open(dock: dock)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Thrown away")
        app.window.typeKey(.escape)
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one")
        #expect(!app.editor.document.canUndo)
        #expect(try app.window.focusedElement == nil)
    }

    @Test func aClickOnTheCanvasAwayFromTheNoteCommitsAndClearsFocus() async throws {
        let app = try await open()
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Typed ")
        app.window.click(at: app.point(inCanvasView: Vector2(900, 120)))
        #expect(app.editor.commentEdit == nil)
        let text = try #require(app.editor.graph.stickies[fixture.note.id]?.text)
        #expect(text.contains("Typed") && text.contains("Line one"), "the typed text joined the old (the caret opens at the start)")
        #expect(try app.window.focusedElement == nil)
        app.editor.document.undo()
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one")
    }
}
```

`Tests/CreatorAppTests/CanvasTitleTypingWindowTests.swift` (CT-3, CT-5; the drag is CT-3's "still moves the frame and its nodes"):

```swift
import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// Typing a frame's title on the canvas through the app's real window (human checks CT-3 and CT-5): a one-line field
/// over the title bar, Return commits (`onSubmit`), Esc cancels, a press elsewhere commits.
@MainActor
struct CanvasTitleTypingWindowTests {
    let fixture = TypingFixture()

    @Test(arguments: [DockSide.bottom, .left])
    func aDoubleClickOnTheTitleBarOpensAFocusedOneLineField(dock: DockSide) async throws {
        let app = try await AppWindow.open(fixture.graph, dock: dock)
        app.window.doubleClick(at: app.titleBarCentre(ofFrame: fixture.box.id))
        #expect(app.editor.commentEdit?.kind == .frameTitle)
        let field = try #require(try app.window.focusedElement)
        #expect(field.role == .textField)
        #expect(field.value == "Bracket")
        let rect = try #require(app.editor.frame(ofComment: fixture.box.id))
        let corner = app.point(inCanvas: rect.origin)
        #expect(abs(field.frame.origin.x.value - corner.x.value) <= 1 && abs(field.frame.origin.y.value - corner.y.value) <= 1,
                "the field starts at the title bar's corner, give or take the field's own inset of a point")
    }

    @Test(arguments: [DockSide.bottom, .left])
    func returnCommitsTheTitleAsOneUndoStep(dock: DockSide) async throws {
        let app = try await AppWindow.open(fixture.graph, dock: dock)
        app.window.doubleClick(at: app.titleBarCentre(ofFrame: fixture.box.id))
        app.window.typeKey(.delete)
        app.window.typeText("Front plate")
        app.window.typeKey(.return)
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.frames[fixture.box.id]?.title.contains("Front plate") == true)
        #expect(app.editor.document.undoName == "Edit Frame")
        app.editor.document.undo()
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Bracket")
    }

    @Test(arguments: [DockSide.bottom, .left])
    func escapeCancelsTheTitle(dock: DockSide) async throws {
        let app = try await AppWindow.open(fixture.graph, dock: dock)
        app.window.doubleClick(at: app.titleBarCentre(ofFrame: fixture.box.id))
        app.window.typeText("Gone")
        app.window.typeKey(.escape)
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Bracket" && !app.editor.document.canUndo)
    }

    @Test func aClickAwayCommitsTheTitle() async throws {
        let app = try await AppWindow.open(fixture.graph)
        app.window.doubleClick(at: app.titleBarCentre(ofFrame: fixture.box.id))
        app.window.typeText("Front ")
        app.window.click(at: app.point(inCanvasView: Vector2(900, 120)))
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.frames[fixture.box.id]?.title.contains("Front") == true)
    }

    /// Human check CT-3: the title bar still drags the frame, with the nodes inside it, as one undo step.
    @Test func draggingTheTitleBarMovesTheFrameAndItsNodesAsOneUndoStep() async throws {
        var builder = GraphBuilder()
        let inside = builder.add(RectangleNode.self, at: Vector2(300, 90))
        var graph = builder.graph
        graph.frames = [fixture.box.id: fixture.box]
        let app = try await AppWindow.open(graph)
        let start = app.titleBarCentre(ofFrame: fixture.box.id)
        app.window.drag(from: start, to: Point(x: start.x + Pixels(50), y: start.y + Pixels(30)), steps: 6)
        #expect(app.editor.commentEdit == nil, "a drag edits nothing")
        #expect(app.editor.graph.frames[fixture.box.id]?.frame.origin == Vector2(310, 70))
        #expect(app.editor.graph.nodes[inside.id]?.position == Vector2(350, 120), "the node inside moved with it")
        #expect(app.editor.document.undoName == "Move")
        app.editor.document.undo()
        #expect(app.editor.graph.frames[fixture.box.id]?.frame.origin == Vector2(260, 40))
        #expect(app.editor.graph.nodes[inside.id]?.position == Vector2(300, 90))
        #expect(!app.editor.document.canUndo, "one step")
    }

    @Test func aBlankTitleIsRefusedAndTheOldOneStays() async throws {
        let app = try await AppWindow.open(fixture.graph)
        app.window.doubleClick(at: app.titleBarCentre(ofFrame: fixture.box.id))
        app.window.typeKey("a", modifierFlags: .primary)
        app.window.typeKey(.delete)
        #expect(app.editor.commentEdit?.draft == "")
        app.window.typeKey(.return)
        #expect(app.editor.refusal?.message == "A frame needs a title.")
        #expect(app.editor.graph.frames[fixture.box.id]?.title == "Bracket" && !app.editor.document.canUndo)
        #expect(app.editor.commentEdit == nil)
    }
}
```

- [ ] **Step 2: Run to see the build fail.** `swift test --filter "CanvasNoteTypingWindowTests|CanvasTitleTypingWindowTests" 2>&1 | grep "error:" | head -3`
Expected: `value of type 'AppWindow' has no member 'centre'` (and `titleBarCentre`).

- [ ] **Step 3: Add the two helpers to `AppWindow`**, inserted immediately before the line `    /// A window point from a vector.`:

```swift
    /// The window point at the middle of the comment `id` as the canvas draws it (docks and zoom included).
    func centre(ofComment id: CommentID) -> Point<Pixels> {
        guard let rect = editor.frame(ofComment: id) else { return windowPoint(.zero) }
        return point(inCanvas: rect.origin + rect.size * 0.5)
    }

    /// The window point at the middle of the frame `id`'s title bar.
    func titleBarCentre(ofFrame id: CommentID) -> Point<Pixels> {
        guard let rect = editor.frame(ofComment: id) else { return windowPoint(.zero) }
        let bar = CommentLayout.titleBar(of: rect)
        return point(inCanvas: bar.origin + bar.size * 0.5)
    }

```

- [ ] **Step 4: Run them.** `swift test --filter "CanvasNoteTypingWindowTests|CanvasTitleTypingWindowTests" 2>&1 | grep -E "Test run with|recorded an issue"`
Expected: `Test run with 11 tests in 2 suites passed` (these pin shipped behaviour, so they pass once they build).

- [ ] **Step 5: Prove they bite.** Each mutation is made, the named suite run (Expected: it fails as stated), and the file restored.

| Mutation | Run | Expected failure |
|---|---|---|
| `Sources/CreatorEditor/CommentEditorField.swift`: first `model.cancelCommentEdit()` → `model.commitCommentEdit()` | `--filter CanvasNoteTypingWindowTests` | `escapeCancelsAndLeavesNothingToUndo` fails for both docks |
| `Sources/CreatorEditor/CommentKeys.swift`: `.primary` → `.option` | `--filter CanvasNoteTypingWindowTests` | `returnBreaksTheLineAndCommandReturnCommitsOneUndoStep` fails |
| `Sources/CreatorEditor/CommentEditorField.swift`: the title branch's `.onSubmit { model.commitCommentEdit() }` → `.onSubmit { }` | `--filter CanvasTitleTypingWindowTests` | `returnCommitsTheTitleAsOneUndoStep` fails |
| `Sources/CreatorEditor/EditorModel+CommentMembers.swift`: `carried.nodes.formUnion(members(of: box))` → `_ = box` | `--filter CanvasTitleTypingWindowTests` | `draggingTheTitleBarMovesTheFrameAndItsNodesAsOneUndoStep` fails (the node stays) |

- [ ] **Step: Full run and lint.**

```bash
swift test 2>&1 | tee /tmp/harness-test.log; echo "exit: ${PIPESTATUS[0]}"
```

```bash
grep -c "Test run with" /tmp/harness-test.log                                   # must print 11
grep -c "recorded an issue\|failed after" /tmp/harness-test.log                # must print 0
grep "Test run with" /tmp/harness-test.log | sed -E 's/.*with ([0-9]+) tests?.*/\1/' | paste -sd+ - | bc   # the total
grep "warning:" /tmp/harness-test.log | grep -E "/(Sources|Tests)/" | sort -u   # only ContextMenuTests.swift:140 (already on master)
swiftlint lint --strict --quiet                                                 # no output
```

Expected: exit 0, 11 `Test run with` lines, 0 issue lines, total **2653** (master + 14), no project-source warning but the one already on master, no lint output.

- [ ] **Step: Commit** (end the message with the attribution lines the session specifies).

```bash
git add -A
git commit -m "test(app): the canvas typing of a note and a frame's title through the real window (CT-c)"
```

### Task 4: CT-c, the graph's keys, focus, the inspector's box and Undo through the real window; the human checks

**Files:**
- Create: `Tests/CreatorAppTests/CanvasTypingKeysWindowTests.swift`, `Tests/CreatorAppTests/CanvasTypingFocusWindowTests.swift`, `Tests/CreatorAppTests/CanvasTypingUndoWindowTests.swift`
- Modify: `Tests/CreatorAppTests/Support/AppWindow.swift` (one helper), `docs/metalui-gaps.md` (CT-c, CM-a), `docs/verification/human-checks.md` (`## Group CT`)

**Interfaces:**
- Consumes: Task 3's `AppWindow` helpers and `TypingFixture`; `EditorModel.canvasSelection`, `.selection`, `.palette`, `.pointerLocation`, `.document.undoName/.canUndo/.canRedo/.undo()`; `AppLayout.margin`, `AppLayout.inspectorWidth`; `TestWindow.element(label:)`, `.elements(where:)`, `.runUntilIdle()`, `.hover(at:)`.
- Produces: `AppWindow.inspectorColumnStart`.

- [ ] **Step 1: Write the tests.**

`Tests/CreatorAppTests/CanvasTypingKeysWindowTests.swift` (CT-4):

```swift
import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// While a comment is being typed the graph's keys stand aside, and afterwards they act again where they should (human
/// check CT-4; MetalUI C9's key regions, gap M5-b). Every key goes through the app's real window.
@MainActor
struct CanvasTypingKeysWindowTests {
    let fixture = TypingFixture()

    /// The app with the note being edited, the pointer over the canvas.
    func editing() async throws -> AppWindow {
        let app = try await AppWindow.open(fixture.graph)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        #expect(app.editor.commentEdit?.id == fixture.note.id)
        return app
    }

    @Test func deleteAndTheArrowsEditTheTextAndMoveNoNode() async throws {
        let app = try await editing()
        let before = app.editor.graph.nodes[fixture.rectangle.id]?.position
        app.window.typeText("XY")
        app.window.typeKey(.delete)
        app.window.typeKey(.leftArrow)
        app.window.typeText("Q")
        #expect(app.editor.commentEdit?.draft.hasPrefix("QX") == true, "Delete removed the Y and the arrow moved the caret")
        #expect(app.editor.graph.nodes[fixture.rectangle.id]?.position == before)
        #expect(app.editor.graph.nodes[fixture.rectangle.id] != nil, "Delete deleted no node")
    }

    @Test func spaceAndFAreTypedAndOpenNothing() async throws {
        let app = try await editing()
        app.window.typeText(" f")
        #expect(app.editor.commentEdit?.draft.hasPrefix(" f") == true)
        #expect(app.editor.palette == nil, "Space does not open the add-node palette")
    }

    @Test func commandChordsActOnTheTextNotTheCanvas() async throws {
        let app = try await editing()
        let notes = app.editor.graph.stickies.count
        let nodes = app.editor.graph.nodes.count
        app.window.typeKey("n", modifierFlags: [.primary, .shift])
        app.window.typeKey("c", modifierFlags: [.primary, .shift])
        app.window.typeKey("g", modifierFlags: .primary)
        app.window.typeKey("d", modifierFlags: .primary)
        #expect(app.editor.graph.stickies.count == notes && app.editor.graph.frames.count == 1, "no note, no frame")
        #expect(app.editor.graph.nodes.count == nodes, "no group, no duplicate")
        #expect(app.editor.commentEdit?.id == fixture.note.id, "and the edit is still open")
        app.window.typeKey("a", modifierFlags: .primary)
        app.window.typeText("All new")
        #expect(app.editor.commentEdit?.draft == "All new", "⌘A selected the text, which typing replaced")
    }

    @Test func tabOpensNoPalette() async throws {
        let app = try await editing()
        app.window.typeKey(.tab)
        #expect(app.editor.palette == nil)
    }

    @Test func afterwardsTheGraphsKeysActOverTheCanvasButNotOverTheViewport() async throws {
        let app = try await editing()
        app.window.typeKey(.escape)
        let canvasSpot = app.point(inCanvasView: Vector2(900, 120))
        app.window.click(at: app.point(inCanvas: Vector2(620, 60) + Vector2(20, 40)))
        #expect(app.editor.selection == [fixture.rectangle.id])
        // The pointer over the viewport, above the panel: Delete does nothing to the selected node (User decision 1).
        app.window.hover(at: Point(x: Pixels(700), y: Pixels(300)))
        app.window.typeKey(.delete)
        #expect(app.editor.graph.nodes[fixture.rectangle.id] != nil)
        // The pointer back over the canvas, nothing focused: Delete deletes the node.
        app.window.hover(at: canvasSpot)
        app.window.typeKey(.delete)
        #expect(app.editor.graph.nodes[fixture.rectangle.id] == nil)
    }
}
```

`Tests/CreatorAppTests/CanvasTypingFocusWindowTests.swift` (CT-2's viewport press and swatch, CT-9, CT-10, CT-11):

```swift
import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// Where a canvas edit's focus goes and what ends it, with the inspector's note box beside it (human checks CT-9,
/// CT-10 and CT-11; gaps CM-a and CT-a). Every press and key goes through the app's real window.
@MainActor
struct CanvasTypingFocusWindowTests {
    let fixture = TypingFixture()

    func open() async throws -> AppWindow {
        try await AppWindow.open(fixture.graph)
    }

    /// The inspector's multi-line note box (the canvas editor is a "Note" field too, but it is not in the inspector's column).
    func inspectorBox(_ app: AppWindow) throws -> TestElement {
        try #require(app.window.elements { $0.role == .textArea && $0.frame.origin.x.value >= Float(app.inspectorColumnStart) }.first)
    }

    @Test func aDoubleClickOnAnotherCommentCommitsTheFirstAndFocusesTheNext() async throws {
        let app = try await open()
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("One ")
        app.window.doubleClick(at: app.centre(ofComment: fixture.otherNote.id))
        #expect(app.editor.graph.stickies[fixture.note.id]?.text.contains("One") == true, "the first edit committed")
        #expect(app.editor.commentEdit?.id == fixture.otherNote.id)
        #expect(try app.window.focusedElement?.value == "Second", "and the next field has the focus")
        app.window.doubleClick(at: app.titleBarCentre(ofFrame: fixture.box.id))
        #expect(app.editor.commentEdit?.id == fixture.box.id)
        #expect(try app.window.focusedElement?.value == "Bracket")
    }

    @Test func theInspectorsBoxBreaksLinesOnReturnAndCommitsOnCommandReturn() async throws {
        let app = try await open()
        app.window.click(at: app.centre(ofComment: fixture.note.id))
        try app.window.click(try inspectorBox(app))
        app.window.typeText(" A")
        app.window.typeKey(.return)
        app.window.typeText("B")
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one", "Return breaks the line and commits nothing")
        app.window.typeKey(.return, modifierFlags: .primary)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one A\nB")
        #expect(app.editor.document.undoName == "Edit Note")
    }

    @Test func clickingIntoTheInspectorsBoxCommitsTheCanvasEditFirst() async throws {
        let app = try await open()
        app.editor.canvasSelection = CanvasSelection(comments: [fixture.note.id])
        try await app.window.runUntilIdle()
        let box = try inspectorBox(app)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Canvas ")
        #expect(try inspectorBox(app).value == "Line one", "the inspector shows the old text until the edit commits")
        try app.window.click(box)
        try await app.window.runUntilIdle()   // the field's focus-loss `onChange` runs in the frame after the click
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text.contains("Canvas") == true, "and nothing is lost")
        app.window.typeText("!")
        app.window.typeKey(.return, modifierFlags: .primary)
        let text = try #require(app.editor.graph.stickies[fixture.note.id]?.text)
        #expect(text.contains("Canvas") && text.contains("!"), "the inspector box took the next keystroke")
    }

    @Test func aPressOnThePanelsGlassLeavesTheEditorOpenAndTheNextCanvasPressCommits() async throws {
        let app = try await open()
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Kept ")
        let panel = try #require(app.model.panelPlacement(inWindowOf: app.size)).panel
        app.window.click(at: app.windowPoint(panel.origin + Vector2(4, 4)))
        #expect(app.editor.commentEdit != nil, "a press on the panel's glass resigns nothing (gap CT-a)")
        #expect(try app.window.focusedElement?.role == .textArea)
        app.window.typeText("more ")
        #expect(app.editor.commentEdit?.draft.hasPrefix("Kept more ") == true)
        app.window.click(at: app.point(inCanvasView: Vector2(900, 120)))
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text.hasPrefix("Kept more ") == true)
    }

    /// Human check CT-2's swatch (decision D4 in the plan): the inspector's accent swatch is a model edit that does not end a canvas
    /// edit. The accent changes at once, the edit stays open with its draft, and the next canvas press commits the text, so
    /// nothing is lost; the two changes are two undo steps. Pinned as measured; D4 may change it.
    @Test func anAccentSwatchPressChangesTheAccentAndLeavesTheEditOpenWithNothingLost() async throws {
        let app = try await open()
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Sw ")
        let swatches = try app.window.elements {
            $0.role == .button && $0.frame.size.width.value == 14 && $0.frame.origin.x.value >= Float(app.inspectorColumnStart)
        }
        try app.window.click(try #require(swatches.dropFirst().first))
        try await app.window.runUntilIdle()
        #expect(app.editor.graph.stickies[fixture.note.id]?.accent != fixture.note.accent, "the accent changed")
        #expect(app.editor.commentEdit?.draft.hasPrefix("Sw ") == true, "and the edit is still open with its draft")
        app.window.click(at: app.point(inCanvasView: Vector2(900, 120)))
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text.hasPrefix("Sw ") == true)
        app.editor.document.undo()
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one" && app.editor.document.canUndo)
        app.editor.document.undo()
        #expect(app.editor.graph.stickies[fixture.note.id]?.accent == fixture.note.accent && !app.editor.document.canUndo)
    }

    /// Human check CT-2's viewport press: it goes through `AppModel+Viewport`, which commits the edit and releases focus
    /// (gap M4-a's stopgap), not through the viewport's draw, so it runs headless.
    @Test func aPressOnTheViewportCommitsTheEditAndClearsFocus() async throws {
        let app = try await open()
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Vp ")
        app.window.click(at: Point(x: Pixels(700), y: Pixels(300)))
        #expect(app.editor.commentEdit == nil)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text.hasPrefix("Vp ") == true)
        #expect(try app.window.focusedElement == nil)
        #expect(app.editor.document.undoName == "Edit Note")
    }
}
```

`Tests/CreatorAppTests/CanvasTypingUndoWindowTests.swift` (CT-8; decision D2):

```swift
import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// ⌘Z and ⇧⌘Z around a canvas edit, through the app's real window (human check CT-8). Between edits the Edit menu's ⌘Z
/// undoes the document's last step; while an editor is focused MetalUI's field keeps ⌘Z before the app's command (KF-C),
/// so it undoes the typing in the field and leaves the document alone. The second test pins that measured answer.
@MainActor
struct CanvasTypingUndoWindowTests {
    let fixture = TypingFixture()

    /// The app with the note's text committed as "New Line one", one undo step, the pointer over the canvas.
    func afterOneEdit() async throws -> AppWindow {
        let app = try await AppWindow.open(fixture.graph)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("New ")
        app.window.typeKey(.return, modifierFlags: .primary)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "New Line one")
        app.window.hover(at: app.point(inCanvasView: Vector2(900, 120)))
        return app
    }

    @Test func commandZRestoresTheOldTextAndShiftCommandZTheNewOneInOneStepEach() async throws {
        let app = try await afterOneEdit()
        app.window.typeKey("z", modifierFlags: .primary)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one")
        #expect(!app.editor.document.canUndo, "the edit was a single step")
        app.window.typeKey("z", modifierFlags: [.primary, .shift])
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "New Line one")
        #expect(!app.editor.document.canRedo)
    }

    @Test func commandZWhileAnEditorIsFocusedUndoesTheTypingAndLeavesTheDocumentAlone() async throws {
        let app = try await afterOneEdit()
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("Draft ")
        #expect(app.editor.commentEdit?.draft.hasPrefix("Draft ") == true)
        app.window.typeKey("z", modifierFlags: .primary)
        #expect(app.editor.commentEdit?.draft == "New Line one", "the field took ⌘Z: the typing is gone")
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "New Line one", "and the document did not move")
        #expect(app.editor.document.undoName == "Edit Note" && !app.editor.document.canRedo)
        #expect(app.editor.commentEdit != nil, "the edit stays open")
    }
}
```

- [ ] **Step 2: Run to see the build fail.** `swift test --filter "CanvasTypingKeysWindowTests|CanvasTypingFocusWindowTests|CanvasTypingUndoWindowTests" 2>&1 | grep "error:" | head -3`
Expected: `value of type 'AppWindow' has no member 'inspectorColumnStart'`.

- [ ] **Step 3: Add the helper to `AppWindow`**, immediately before `    /// A window point from a vector.`:

```swift
    /// The window x where the inspector's column starts (it floats at the window's right edge).
    var inspectorColumnStart: Double { size.x - AppLayout.margin - AppLayout.inspectorWidth }

```

- [ ] **Step 4: Run them.** `swift test --filter "CanvasTypingKeysWindowTests|CanvasTypingFocusWindowTests|CanvasTypingUndoWindowTests" 2>&1 | grep -E "Test run with|recorded an issue"`
Expected: `Test run with 13 tests in 3 suites passed`.

- [ ] **Step 5: Prove they bite.**

| Mutation | Run | Expected failure |
|---|---|---|
| `Sources/CreatorEditor/CanvasSurface.swift`: delete `.hoverKeyRegion()` | `--filter CanvasTypingKeysWindowTests` | `afterwardsTheGraphsKeysActOverTheCanvasButNotOverTheViewport` fails |
| `Sources/CreatorEditor/CommentTextEntry.swift`: the guard line `guard CommentKeys.commitsNote(press.modifiers) else { return .ignored }` → `return .ignored` | `--filter CanvasTypingFocusWindowTests` | `theInspectorsBoxBreaksLinesOnReturnAndCommitsOnCommandReturn` fails |
| `Sources/CreatorEditor/CommentEditorField.swift`: `if wasFocused, !focused { model.commitCommentEdit() }` → `if wasFocused, !focused { }` (both branches carry the line; the first is the note's) | `--filter CanvasTypingFocusWindowTests` | `clickingIntoTheInspectorsBoxCommitsTheCanvasEditFirst` fails |
| `Sources/CreatorApp/AppModel+Viewport.swift`: delete `model.editor.commitPendingEntry()` in `viewport.events.pressed` | `--filter CanvasTypingFocusWindowTests` | `aPressOnTheViewportCommitsTheEditAndClearsFocus` fails |

`commandZWhileAnEditorIsFocusedUndoesTheTypingAndLeavesTheDocumentAlone` pins MetalUI's behaviour (the field keeps ⌘Z, KF-C), so no mutation of the app bites it; it fails if MetalUI starts passing ⌘Z on to the Edit menu while a field is focused, and `commandZAndShiftCommandZUndoAndRedoOneStepEach` (Task 5) is its contrast: the same key with nothing focused undoes the document.

- [ ] **Step 6: Mark CT-c adopted and the human checks automated.** From the worktree root (the anchors are the exact current text; the script stops at the first mismatch, which means a 7a track edited that text: merge by hand, keeping both):

```bash
python3 - <<'PY'
def rep(path, old, new):
    text = open(path, encoding="utf-8").read()
    assert text.count(old) == 1, f"{path}: anchor found {text.count(old)} times: {old[:60]!r}"
    open(path, "w", encoding="utf-8").write(text.replace(old, new))

GAPS = "docs/metalui-gaps.md"
CHECKS = "docs/verification/human-checks.md"

rep(GAPS,
    "| CT-c | The canvas typing's key, focus and press routing can't be driven from a test (the C9-dependent behaviour is pinned only by human checks CT-1..CT-9) | M6-e (public headless `Window` with `simulateInput`) | 🟡 landed in MetalUI master 280d706 (item 8, `MetalUITesting`); adoption here pending |",
    "| CT-c | The canvas typing's key, focus and press routing can't be driven from a test (the C9-dependent behaviour is pinned only by human checks CT-1..CT-9) | M6-e (public headless `Window` with `simulateInput`) | ✅ fixed (MetalUI 280d706), adopted (plan `2026-10-12-adopt-test-harness`): `CanvasNoteTypingWindowTests`, `CanvasTitleTypingWindowTests`, `CanvasTypingKeysWindowTests`, `CanvasTypingFocusWindowTests`, `CanvasTypingUndoWindowTests`; CT-1..CT-11 keep only their visual and machine-specific parts |")

rep(GAPS,
    "asserts `commentEdit` and the graph. Status: rides with M6-e (queued); forward to the MetalUI session per the standing\n  rule; the repository is never edited from here.\n",
    "asserts `commentEdit` and the graph. Status: rides with M6-e (queued); forward to the MetalUI session per the standing\n  rule; the repository is never edited from here.\n"
    "  **Adopted (2026-10-12, plan `2026-10-12-adopt-test-harness`):** the tests type through the app's real window\n"
    "  (`AppWindow`, MetalUI 280d706). `CanvasNoteTypingWindowTests`: a double click opens a focused editor exactly over the\n"
    "  note (both docks, and at 0.5× and 2× zoom), Return breaks the line, `CommentKeys.commitModifier` (primary-modifier)\n"
    "  Return commits as one \"Edit Note\" step, Esc cancels with nothing to undo, a press on empty canvas commits and clears\n"
    "  focus (M5-g). `CanvasTitleTypingWindowTests`: the same for a frame's title (Return commits through `onSubmit`, a blank\n"
    "  title is refused; dragging the title bar moves the frame and its nodes as one \"Move\" step). `CanvasTypingKeysWindowTests`: while a field is focused the graph's keys edit its text (Delete,\n"
    "  arrows, Space, F, the ⌘ chords, ⌘A, Tab) and afterwards act again over the canvas but not over the viewport (M5-b).\n"
    "  `CanvasTypingFocusWindowTests`: a double click on another comment commits the first and focuses the next; the\n"
    "  inspector's note box breaks lines on Return and commits on the primary-modifier Return (CM-a); clicking into it commits\n"
    "  a canvas edit first; a press on the panel's glass resigns nothing (CT-a, by design) and the next canvas press commits;\n"
    "  a press on the 3D viewport commits at once; the inspector's accent swatch changes the accent without ending the edit\n"
    "  (pinned as measured, decision D4). `CanvasTypingUndoWindowTests`: ⌘Z and ⇧⌘Z undo and redo a committed note edit in one\n"
    "  step each, and ⌘Z while an editor is focused undoes the typing in the field and leaves the document alone (KF-C).\n"
    "  A field's focus-loss commit (`onChange(of:)`) runs in the frame after the click, so that test runs `runUntilIdle()`.\n"
    "  Human checks CT-1..CT-11 keep what a person must judge (CT-1's look, CT-6's softness, CT-7, CT-12), a physical\n"
    "  keyboard, the paste and the swatch.\n")

# CM-a: its open question is answered through a real window now.
rep(GAPS,
    "Logged with C9 (key and focus scoping), which owns the key\n  handling.\n",
    "Logged with C9 (key and focus scoping), which owns the key\n  handling.\n"
    "  **Pinned through a real window (2026-10-12):** `CanvasTypingFocusWindowTests` types into the inspector's `TextEditor`\n"
    "  and sends the primary-modifier Return (commits, one \"Edit Note\" step) and a plain Return (breaks the line).\n")

# --- human checks ---
rep(CHECKS,
    "**Status: PENDING.** Plan `2026-10-10-comments-canvas-typing.md`, spec `2026-10-09-selection-groups-comments-design.md` §8\nand its Errata (B: typing on the canvas). The tests pin the model and the headless frames; these check the double click,\nthe focus and the keys through a real window (MetalUI C9's own tests pin the key routing; the app has no headless\nwindow, gap M6-e). Run `swift run MetalCreatorApp` on a saved bracket with a note and a frame; CT-5 docks left.",
    "**Status: PENDING (what only a person can judge).** Plan `2026-10-10-comments-canvas-typing.md`, spec\n`2026-10-09-selection-groups-comments-design.md` §8 and its Errata (B: typing on the canvas). The tests pin the model and\nthe headless frames, and since the test-harness adoption (plan `2026-10-12-adopt-test-harness.md`, gap CT-c) they also\ndrive the double click, the focus and the keys through the app's real window: `CanvasNoteTypingWindowTests`,\n`CanvasTitleTypingWindowTests`, `CanvasTypingKeysWindowTests`, `CanvasTypingFocusWindowTests`, `CanvasTypingUndoWindowTests`. A clause marked\n**Automated** below has no manual step; what stays is how it looks and what the real machine does. Run\n`swift run MetalCreatorApp` on a saved bracket with a note and a frame; CT-5 docks left.")

rep(CHECKS,
    "- [ ] **CT-1 A note.** Double click a note: a white-backed editor appears exactly over it, with the caret in it, and the\n  note's text is in it, the caret at its start and nothing selected (gap CT-b: **record it**; ⌘A selects it all). Type two lines (Return breaks the line), press ⌘↩: the editor closes, the note shows both lines,\n  and one ⌘Z puts the old text back. **Observe each of these separately and write each down:** focus is in the field the\n  moment it appears (no extra click); Return breaks the line and commits nothing; ⌘↩ commits; Esc cancels (CT-2);\n  clicking away commits (CT-2). Pinned: `CommentTypingTests`, `CommentDoubleClickTests`, `CommentEditorRenderTests`.\n  **Observed:**",
    "- [ ] **CT-1 A note (the look).** Double click a note: a white-backed editor appears exactly over it, with the caret\n  visible in it, and the note's text is in it, the caret at its start and nothing selected (gap CT-b: **record it**; ⌘A\n  selects it all). Type two lines, press ⌘↩: the note shows both lines. **Automated, no manual step:** the editor lies over\n  the note with focus in it the moment it appears, Return breaks the line and commits nothing, ⌘↩ commits as one undo\n  step, Esc cancels, clicking away commits (`CanvasNoteTypingWindowTests`). Pinned: `CommentTypingTests`,\n  `CommentDoubleClickTests`, `CommentEditorRenderTests`. **Observed:**")

rep(CHECKS,
    "- [ ] **CT-2 Ending an edit.** Four separate observations, each written down, for a note: **Esc** closes the editor and\n  the note keeps its old text, with nothing to undo; **⌘↩** commits and closes; **Return** breaks the line and the editor\n  stays open; **a click away** (the next lines) commits. For a frame's title: **Return** commits, **Esc** cancels, **a\n  click away** commits. Start a note edit and type, then Esc as above. Type again and click empty canvas, then another node, then the 3D viewport, then the inspector's\n  accent swatch: each commits the text (one ⌘Z each). Type, then ⌘S: the saved file has the text. Pinned: `CommentTypingTests`.\n  **Observed:**",
    "- [ ] **CT-2 Ending an edit (what is left).** **Automated, no manual step:** for a note, Esc closes the editor and the\n  note keeps its old text with nothing to undo, ⌘↩ commits, Return breaks the line and the editor stays open, a click on\n  empty canvas commits (one ⌘Z), and so does a press on the 3D viewport (`CanvasNoteTypingWindowTests`,\n  `CanvasTypingFocusWindowTests`); for a frame's title, Return commits, Esc cancels, a click away commits\n  (`CanvasTitleTypingWindowTests`). **By hand:** type and click another node: it commits (one ⌘Z). Type and click the\n  inspector's accent swatch and **record what happens** (through the headless window the accent changes and the edit stays\n  open with its draft until the next canvas press: decision D4, `anAccentSwatchPressChangesTheAccentAndLeavesTheEditOpenWithNothingLost`).\n  Type, then ⌘S: the saved file has the text. Pinned: `CommentTypingTests`. **Observed:**")

rep(CHECKS,
    "- [ ] **CT-3 A frame's title.** Double click a frame's title bar: a one-line field over the bar with the title in it. Type\n  \"Front plate\", Return: it commits (one ⌘Z undoes it). Esc cancels. Clear it and press Return: \"A frame needs a title.\"\n  appears and the old title returns. Paste text containing a line break: it becomes a space. A double click on the\n  frame's edge band or its inside starts no edit, and dragging the title bar still moves the frame and its nodes.\n  Pinned: `CommentTypingTests`, `CommentDoubleClickTests`. **Observed:**",
    "- [ ] **CT-3 A frame's title (what is left).** **Automated, no manual step:** a double click on the title bar opens a\n  focused one-line field over the bar with the title in it; Return commits (one ⌘Z undoes it); Esc cancels; clearing it\n  and pressing Return shows \"A frame needs a title.\" and keeps the old title; dragging the title bar moves the frame and\n  the nodes inside it as one undo step (`CanvasTitleTypingWindowTests`). **By hand:** paste text containing a line break:\n  it becomes a space. A double click on the frame's edge band or its inside starts no edit. Pinned: `CommentTypingTests`,\n  `CommentDoubleClickTests`. **Observed:**")

rep(CHECKS,
    "- [ ] **CT-4 The graph's keys stand aside.** With an editor focused and nodes selected on the canvas: Delete deletes\n  characters and no node; arrows move the caret and no node; Space and F type; ⌘A selects the text; ⌘C, ⌘X and ⌘V use the\n  text; ⌘⇧N adds no note, ⌘G, ⌘D and ⌘⇧C do nothing to the canvas; Tab does not open the add-node palette. Afterwards,\n  with the pointer over the canvas and nothing focused, Delete, arrows, ⌘A, F and Space act again (Tab opens the palette);\n  with the pointer over the viewport or the inspector's empty space they do not (User decision 1: **record it**). Pinned:\n  `GraphPanelInputTests`, `SelectionKeyTests`, `NudgeTests`. **Observed:**",
    "- [ ] **CT-4 The graph's keys stand aside (what is left).** **Automated, no manual step** (`CanvasTypingKeysWindowTests`):\n  with an editor focused, Delete deletes characters and no node; arrows move the caret and no node; Space and F type; ⌘A\n  selects the text; ⌘⇧N adds no note, ⌘G, ⌘D and ⌘⇧C do nothing to the canvas; Tab does not open the add-node palette;\n  afterwards, with the pointer over the canvas and nothing focused, Delete acts again, and with the pointer over the\n  viewport it does not (User decision 1). (Starting an edit makes the comment the whole selection, so \"nodes selected\n  while an editor is focused\" cannot arise.) **By hand:** ⌘C, ⌘X and ⌘V use the text, not the canvas's clipboard; over\n  the canvas also the arrows, ⌘A, F and Space act again and Tab opens the palette; over the inspector's empty space they\n  do not (**record it**). Pinned: `GraphPanelInputTests`, `SelectionKeyTests`, `NudgeTests`. **Observed:**")

rep(CHECKS,
    "- [ ] **CT-5 Both docks.** Repeat CT-1 and CT-3 docked bottom and docked left: the editor lies exactly over the note and\n  over the title bar (the left dock draws both transposed), and typing, ⌘↩, Return and Esc behave the same. Pinned:\n  `CommentEditorRenderTests`, `CommentTypingTests`. **Observed:**",
    "- [x] **CT-5 Both docks.** **Automated, no manual step:** docked bottom and docked left (which draws both transposed)\n  the editor lies exactly over the note and over the title bar, and ⌘↩, Return and Esc behave the same\n  (`CanvasNoteTypingWindowTests`, `CanvasTitleTypingWindowTests`, each run for both docks). Pinned:\n  `CommentEditorRenderTests`, `CommentTypingTests`.")

rep(CHECKS,
    "- [ ] **CT-6 Zoom.** At 25 %, 100 % and 300 % (⌘-scroll, or the header buttons) repeat CT-1 and CT-3: the editor's text\n  is scaled as the note's is and lies over it, typing works, and a click inside the editor places the caret under the\n  pointer (the editor is drawn under a scale effect). **Record** whether the title field is usable at 25 % and whether the\n  text is soft at 300 % (MetalUI divergence 106: text under a scale effect is resampled). Pinned: `CommentEditorRenderTests`.\n  **Observed:**",
    "- [ ] **CT-6 Zoom (the look).** At 25 %, 100 % and 300 % (⌘-scroll, or the header buttons) repeat CT-1 and CT-3: typing\n  works, and a click inside the editor places the caret under the pointer (the editor is drawn under a scale effect).\n  **Record** whether the title field is usable at 25 % and whether the text is soft at 300 % (MetalUI divergence 106: text\n  under a scale effect is resampled). **Automated:** at 0.5× and 2× the editor is scaled as the note is and lies over it\n  (`theEditorFollowsTheCanvasZoom`). Pinned: `CommentEditorRenderTests`. **Observed:**")

rep(CHECKS,
    "- [ ] **CT-8 Undo.** Edit a note, ⌘Z: the old text, ⇧⌘Z: the new. While an editor is open and focused, ⌘Z: **record\n  whether it undoes the typing in the field or the document's last step** (MetalUI's field keeps ⌘Z before the app's\n  command, KF-C). **Observed:**",
    "- [ ] **CT-8 Undo (what is left).** **Automated, no manual step:** edit a note, ⌘Z gives the old text and ⇧⌘Z the new,\n  one step each, over the canvas and over the viewport (`EditMenuRoutingWindowTests`, `CanvasTypingUndoWindowTests`); while an\n  editor is open and focused, ⌘Z undoes the typing in the field and leaves the document alone (the measured answer,\n  pinned: MetalUI's field keeps ⌘Z before the app's command, KF-C; decision D2). **By hand:** the same keys on a physical\n  keyboard. **Observed:**")

rep(CHECKS,
    "- [ ] **CT-9 Inspector and canvas together.** Select a note (the inspector shows its text), double click it and type: the\n  inspector shows the old text until the edit commits. Click into the inspector's box and type: the canvas edit commits\n  first and nothing is lost. In the inspector's box, ⌘↩ commits and Return breaks the line (gap CM-a). Pinned:\n  `CommentTypingTests`, `CommentKeysTests`. **Observed:**",
    "- [x] **CT-9 Inspector and canvas together.** **Automated, no manual step** (`CanvasTypingFocusWindowTests`): with a note\n  selected the inspector shows its text; double click the note and type, and the inspector shows the old text until the\n  edit commits; clicking into the inspector's box commits the canvas edit first and loses nothing; in the box, ⌘↩ commits\n  and Return breaks the line (gap CM-a). Pinned: `CommentTypingTests`, `CommentKeysTests`.")

rep(CHECKS,
    "- [ ] **CT-10 Focus.** Double click a note, double click another note, then a frame's title bar, without clicking\n  elsewhere between: each edit commits and the next starts with the caret in its field. Press Tab in an editor: focus\n  moves (it opens no palette). Pinned: `CommentDoubleClickTests`. **Observed:**",
    "- [ ] **CT-10 Focus (what is left).** **Automated, no manual step** (`CanvasTypingFocusWindowTests`): double click a note,\n  double click another note, then a frame's title bar, without clicking elsewhere between: each edit commits and the next\n  has the focus in its field (and Tab opens no palette, `tabOpensNoPalette`). **By hand:** the caret is visible\n  in each new field, and Tab in an editor moves focus to the next control. Pinned: `CommentDoubleClickTests`.\n  **Observed:**")

rep(CHECKS,
    "- [ ] **CT-11 Inert chrome (gap CT-a).** While a note is being edited, press the graph panel's header gap, the glass\n  padding and an empty area of the inspector. **Record** whether the editor stays open (the expected, documented\n  behaviour: User decision 2) and what the next canvas press does. **Observed:**",
    "- [ ] **CT-11 Inert chrome (gap CT-a).** While a note is being edited, press the graph panel's header gap, the glass\n  padding and an empty area of the inspector. **Record** whether the editor stays open (the expected, documented\n  behaviour: User decision 2) and what the next canvas press does. **Automated:** a press on the panel's glass padding\n  leaves the editor open and focused, typing continues, and the next canvas press commits\n  (`CanvasTypingFocusWindowTests`); **by hand:** the header gap and the inspector's empty area. **Observed:**")
PY
```

- [ ] **Step 7: Read the CT section once.** `sed -n '/^## Group CT/,/^## Group GR/p' docs/verification/human-checks.md` and confirm: CT-5 and CT-9 are `[x]` with "Automated, no manual step"; CT-1, 2, 3, 4, 6, 8, 10, 11 keep a "By hand" or "look" part; CT-7 and CT-12 are unchanged. Grep it: no `gap HT-a` anywhere (`grep -n "HT-a" docs/verification/human-checks.md docs/metalui-gaps.md` prints nothing).

- [ ] **Step: Full run and lint.**

```bash
swift test 2>&1 | tee /tmp/harness-test.log; echo "exit: ${PIPESTATUS[0]}"
```

```bash
grep -c "Test run with" /tmp/harness-test.log                                   # must print 11
grep -c "recorded an issue\|failed after" /tmp/harness-test.log                # must print 0
grep "Test run with" /tmp/harness-test.log | sed -E 's/.*with ([0-9]+) tests?.*/\1/' | paste -sd+ - | bc   # the total
grep "warning:" /tmp/harness-test.log | grep -E "/(Sources|Tests)/" | sort -u   # only ContextMenuTests.swift:140 (already on master)
swiftlint lint --strict --quiet                                                 # no output
```

Expected: exit 0, 11 `Test run with` lines, 0 issue lines, total **2666** (master + 27), no project-source warning but the one already on master, no lint output.

- [ ] **Step: Commit** (end the message with the attribution lines the session specifies).

```bash
git add -A
git commit -m "test(app): the graph's keys, focus and the inspector's box through the real window; CT-c adopted"
```

### Task 5: M6-e's own routes, F + and − over the viewport and the canvas, the Edit menu and its chords, the palette's key context

Gap M6-e's entry names the routing it blocked: "the `Panel` / `!Panel` key contexts on the focus chain, the canvas hover veto, menu commands running before `onInput`, button shortcuts ahead of the palette ... pinned only as mapping (`AppInputTests`) plus human checks M6-4, M6-5 and M6-11". `AppWindow` can drive all but the last, so this task pins them (decision D3) and marks M6-4, M6-5 and EP-2 automated. M6-11's button shortcuts are the sketch editor's, in sketch mode; they stay a human check.

**Files:**
- Create: `Tests/CreatorAppTests/ViewportKeyRoutingWindowTests.swift`, `Tests/CreatorAppTests/EditMenuRoutingWindowTests.swift`, `Tests/CreatorAppTests/PaletteKeyRoutingWindowTests.swift`
- Modify: `docs/metalui-gaps.md` (M6-e row and entry), `docs/verification/human-checks.md` (M6-4, M6-5, EP-2)

**Interfaces:**
- Consumes: Task 3's and Task 4's `AppWindow` helpers (`centre(ofComment:)`, `inspectorColumnStart`), `TypingFixture`; `AppModel.viewport.pose` (`distance`), `EditorModel.transform.zoom`, `.selection`, `.palette` (`query`), `.document.undoName/.canUndo/.canRedo`; MetalUITesting's `typeKey`, `typeText`, `hover(at:)`, `advance(by:)`, `elements(where:)`, `TestApp.menuBar`, `performMenuBarItem(_:)`, `PlatformMenuItem.isEnabled`.
- Produces: nothing later tasks use.

- [ ] **Step 1: Write the tests.** The viewport spot `(700, 300)` lies above the bottom-docked panel; `canvasSpot` is a point of the canvas with no node under it.

`Tests/CreatorAppTests/ViewportKeyRoutingWindowTests.swift` (M6-4):

```swift
import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// F, + and − go to the viewport over the viewport and to the graph over its canvas, and a focused field keeps them (human
/// check M6-4; the "canvas hover veto" and the `Panel` / `!Panel` key contexts that gap M6-e named). Every key goes through
/// the app's real window: the keymap, `AppInput`, the canvas's key region and the focus chain.
@MainActor
struct ViewportKeyRoutingWindowTests {
    /// Above the graph panel with the default (bottom) dock: the viewport, not the canvas.
    let viewportSpot = Point(x: Pixels(700), y: Pixels(300))

    func open() async throws -> (app: AppWindow, rectangle: Node, canvasSpot: Point<Pixels>) {
        var builder = GraphBuilder()
        let part = builder.box(at: Vector2(40, 40))
        let app = try await AppWindow.open(builder.graph)
        return (app, part.rectangle, app.point(inCanvasView: Vector2(900, 120)))
    }

    @Test func plusAndMinusZoomTheViewportOverTheViewportAndNotTheGraph() async throws {
        let (app, _, _) = try await open()
        let pose = app.model.viewport.pose
        let zoom = app.editor.transform.zoom
        app.window.hover(at: viewportSpot)
        app.window.typeKey("+")
        #expect(app.model.viewport.pose.distance < pose.distance, "the viewport zooms in")
        app.window.typeKey("-")
        #expect(app.model.viewport.pose.distance == pose.distance, "and out again")
        #expect(app.editor.transform.zoom == zoom, "the graph never moved")
    }

    @Test func plusAndMinusZoomTheGraphOverItsCanvasAndNotTheViewport() async throws {
        let (app, _, canvasSpot) = try await open()
        let pose = app.model.viewport.pose
        let zoom = app.editor.transform.zoom
        app.window.hover(at: canvasSpot)
        app.window.typeKey("+")
        #expect(app.editor.transform.zoom > zoom, "the graph zooms in")
        app.window.typeKey("-")
        #expect(app.editor.transform.zoom == zoom, "and out again")
        #expect(app.model.viewport.pose == pose, "the viewport never moved")
    }

    @Test func fFramesTheViewportOverTheViewportAndTheGraphOverItsCanvas() async throws {
        let (app, rectangle, canvasSpot) = try await open()
        app.editor.selection = [rectangle.id]
        let pose = app.model.viewport.pose
        let transform = app.editor.transform
        app.window.hover(at: viewportSpot)
        app.window.typeKey("f")
        app.window.advance(by: 1)
        #expect(app.model.viewport.pose != pose, "the viewport frames its part")
        #expect(app.editor.transform == transform, "and the graph stays")
        let framed = app.model.viewport.pose
        app.window.hover(at: canvasSpot)
        app.window.typeKey("f")
        app.window.advance(by: 1)
        #expect(app.editor.transform != transform, "over the canvas F frames the graph's selection")
        #expect(app.model.viewport.pose == framed, "and the viewport stays")
    }

    @Test func aFocusedInspectorFieldTakesTheKeysUntilTheViewportIsPressed() async throws {
        let (app, rectangle, _) = try await open()
        app.window.click(at: app.point(inCanvas: Vector2(60, 80)))
        #expect(app.editor.selection == [rectangle.id])
        let field = try #require(app.window.elements {
            $0.role == .textField && $0.frame.origin.x.value >= Float(app.inspectorColumnStart)
        }.first)
        try app.window.click(field)
        let pose = app.model.viewport.pose
        let transform = app.editor.transform
        app.window.hover(at: viewportSpot)
        for key: KeyEquivalent in ["f", "+", "-"] { app.window.typeKey(key) }
        #expect(app.model.viewport.pose == pose && app.editor.transform == transform, "the field has them, wherever the pointer is")
        app.window.click(at: viewportSpot)
        app.window.typeKey("+")
        #expect(app.model.viewport.pose.distance < pose.distance, "after a press on the viewport the field lets go and + zooms")
    }
}
```

`Tests/CreatorAppTests/EditMenuRoutingWindowTests.swift` (M6-5; ⌘Z is run over the viewport too, where the Edit menu's shortcut is the only thing that can answer):

```swift
import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// The Edit menu and the chords that run before the graph's keys (human check M6-5; "menu commands running before
/// `onInput`" in gap M6-e): the menu bar the app installs is read and run through MetalUITesting, and the chords go through
/// the real window's key routing.
@MainActor
struct EditMenuRoutingWindowTests {
    let fixture = TypingFixture()

    func editMenu(_ app: AppWindow) throws -> [PlatformMenuItem] {
        try #require(app.testApp.menuBar.first { $0.title == "Edit" }).items
    }

    /// The app after one committed note edit ("Edit Note"), the pointer over the canvas.
    func afterAnEdit() async throws -> AppWindow {
        let app = try await AppWindow.open(fixture.graph)
        app.window.doubleClick(at: app.centre(ofComment: fixture.note.id))
        app.window.typeText("New ")
        app.window.typeKey(.return, modifierFlags: .primary)
        app.window.hover(at: app.point(inCanvasView: Vector2(900, 120)))
        return app
    }

    @Test func theEditMenuNamesTheStepAndRunsUndoAndRedo() async throws {
        let app = try await afterAnEdit()
        let titles = try editMenu(app).prefix(2).map(\.title)
        #expect(titles == ["Undo Edit Note", "Redo"])
        try app.testApp.performMenuBarItem("Edit", "Undo Edit Note")
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one")
        #expect(try editMenu(app).prefix(2).map(\.title) == ["Undo", "Redo Edit Note"])
        #expect(try editMenu(app).first?.isEnabled == false, "nothing left to undo")
        try app.testApp.performMenuBarItem("Edit", "Redo Edit Note")
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "New Line one")
    }

    /// Over the canvas the graph's own ⌘Z answers, over the viewport the Edit menu's: the same step either way.
    @Test(arguments: [false, true])
    func commandZAndShiftCommandZUndoAndRedoOneStepEach(overTheViewport: Bool) async throws {
        let app = try await afterAnEdit()
        if overTheViewport { app.window.hover(at: Point(x: Pixels(700), y: Pixels(300))) }
        app.window.typeKey("z", modifierFlags: .primary)
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "Line one")
        #expect(!app.editor.document.canUndo && app.editor.document.canRedo)
        app.window.typeKey("z", modifierFlags: [.primary, .shift])
        #expect(app.editor.graph.stickies[fixture.note.id]?.text == "New Line one")
        #expect(app.editor.document.canUndo && !app.editor.document.canRedo)
    }

    @Test func copyPasteAndDuplicateChordsActOverTheCanvasAndNotOverTheViewport() async throws {
        var builder = GraphBuilder()
        let node = builder.add(RectangleNode.self, at: Vector2(40, 40))
        let app = try await AppWindow.open(builder.graph)
        app.window.click(at: app.point(inCanvas: Vector2(60, 80)))
        #expect(app.editor.selection == [node.id])
        app.window.hover(at: app.point(inCanvasView: Vector2(900, 120)))
        app.window.typeKey("c", modifierFlags: .primary)
        app.window.typeKey("v", modifierFlags: .primary)
        #expect(app.editor.graph.nodes.count == 2, "⌘C then ⌘V pasted a copy; the standard items did not swallow the keys")
        #expect(app.editor.document.undoName == "Paste")
        app.window.typeKey("d", modifierFlags: .primary)
        #expect(app.editor.graph.nodes.count == 3)
        #expect(app.editor.document.undoName == "Duplicate")
        app.window.hover(at: Point(x: Pixels(700), y: Pixels(300)))
        app.window.typeKey("d", modifierFlags: .primary)
        #expect(app.editor.graph.nodes.count == 3, "over the viewport the graph's chords do nothing")
    }
}
```

`Tests/CreatorAppTests/PaletteKeyRoutingWindowTests.swift` (EP-2's key context):

```swift
import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// The add-node palette's keys through the real window (human check EP-2; the `Panel` key context that gap M6-e named):
/// Space over the canvas opens it with its search field focused, F, + and − are typed into the field and not taken by the
/// viewport, and Return adds the node as one undo step.
@MainActor
struct PaletteKeyRoutingWindowTests {
    @Test func theSearchFieldTakesFPlusAndMinusAndReturnAddsTheNode() async throws {
        var builder = GraphBuilder()
        _ = builder.add(NumberNode.self, at: Vector2(40, 40))
        let app = try await AppWindow.open(builder.graph)
        let pose = app.model.viewport.pose
        let zoom = app.editor.transform.zoom
        app.window.hover(at: app.point(inCanvasView: Vector2(900, 120)))
        app.window.typeKey(.space)
        #expect(app.editor.palette != nil)
        #expect(try app.window.focusedElement?.role == .textField, "the search field has the focus the moment the palette opens")
        app.window.typeText("f+")
        #expect(app.editor.palette?.query == "f+")
        #expect(app.model.viewport.pose == pose && app.editor.transform.zoom == zoom, "the viewport neither frames nor zooms")
        app.window.typeKey("a", modifierFlags: .primary)
        app.window.typeText("Rectangle")
        app.window.typeKey(.return)
        #expect(app.editor.palette == nil)
        #expect(app.editor.graph.nodes.count == 2)
        #expect(app.editor.selection.count == 1, "the new node is selected")
        app.window.typeKey("z", modifierFlags: .primary)
        #expect(app.editor.graph.nodes.count == 1, "one ⌘Z removes it")
    }

    @Test func escapeClosesThePaletteAndAddsNothing() async throws {
        let app = try await AppWindow.open()
        app.window.hover(at: app.point(inCanvasView: Vector2(900, 120)))
        app.window.typeKey(.space)
        app.window.typeText("Box")
        app.window.typeKey(.escape)
        #expect(app.editor.palette == nil && app.editor.graph.nodes.isEmpty)
    }
}
```

- [ ] **Step 2: Run them.** They pin shipped behaviour, so they pass once they build (every helper they use exists after Task 4).

Run: `swift test --filter "ViewportKeyRoutingWindowTests|EditMenuRoutingWindowTests|PaletteKeyRoutingWindowTests" 2>&1 | grep -E "Test run with|recorded an issue"`
Expected: `Test run with 9 tests in 3 suites passed`.

- [ ] **Step 3: Prove they bite.** Each mutation is made, the suites run (Expected: the stated failure), and the file restored.

| Mutation | Run | Expected failure |
|---|---|---|
| `Sources/CreatorEditor/CanvasSurface.swift`: delete the `.hoverKeyRegion()` line | all three suites | `plusAndMinusZoomTheGraphOverItsCanvasAndNotTheViewport`, `fFramesTheViewportOverTheViewportAndTheGraphOverItsCanvas`, `copyPasteAndDuplicateChordsActOverTheCanvasAndNotOverTheViewport` and `theSearchFieldTakesFPlusAndMinusAndReturnAddsTheNode` fail |
| `Sources/CreatorApp/AppCommands.swift`: delete the Undo item's `.keyboardShortcut("z")` | `--filter EditMenuRoutingWindowTests` | `commandZAndShiftCommandZUndoAndRedoOneStepEach` fails for the viewport case only (over the canvas the graph's own ⌘Z answers) |
| `Sources/CreatorApp/AppInput.swift`: delete the `model.releaseTextFocus = ...` line | `--filter ViewportKeyRoutingWindowTests` | `aFocusedInspectorFieldTakesTheKeysUntilTheViewportIsPressed` fails at its last expectation |

Two mutations do **not** bite, and that is a finding, not a gap in the tests: deleting `if model.editor.pointerLocation != nil { return false }` in `AppInput.handleAction` (the canvas hover veto), or changing the viewport keys' `context: AppKeyContext.viewport` to `context: nil`, leaves these nine tests and `CanvasTypingKeysWindowTests` green, because under MetalUI C9 the canvas's key region and a focused field claim the keys before the window keymap sees them. `AppInputTests` keeps pinning the mapping; whether the two stopgaps can be deleted is a question for the viewport's C9 adoption (gap M4-a), not for this plan.

- [ ] **Step 4: Mark the routes pinned and M6-4, M6-5, EP-2 automated.** From the worktree root:

```bash
python3 - <<'PY'
def rep(path, old, new):
    text = open(path, encoding="utf-8").read()
    assert text.count(old) == 1, f"{path}: anchor found {text.count(old)} times: {old[:60]!r}"
    open(path, "w", encoding="utf-8").write(text.replace(old, new))

GAPS = "docs/metalui-gaps.md"
CHECKS = "docs/verification/human-checks.md"

rep(GAPS,
    "(`AppWindowTests`); MetalCreator had no platform fake of its own to replace; the harness's one limit",
    "(`AppWindowTests`), and the routes the entry named are pinned there (`ViewportKeyRoutingWindowTests`, `EditMenuRoutingWindowTests`, `PaletteKeyRoutingWindowTests`); MetalCreator had no platform fake of its own to replace; the harness's one limit")

rep(GAPS,
    "`AppWindow.canvasFrame` can go. Until then `AppWindow.canvasFrame` is the\n  stopgap.\n",
    "`AppWindow.canvasFrame` can go. Until then `AppWindow.canvasFrame` is the\n  stopgap.\n"
    "  **The routes this entry named are pinned through the window** (Task 5 of the plan): F, + and − go to the viewport over the\n"
    "  viewport and to the graph over its canvas, and a focused inspector field keeps them until a viewport press gives them\n"
    "  back (`ViewportKeyRoutingWindowTests`, M6-4); the Edit menu is titled by the step and runs Undo and Redo, ⌘Z and ⇧⌘Z\n"
    "  act over the canvas and over the viewport, and ⌘C, ⌘V and ⌘D copy, paste and duplicate over the canvas only\n"
    "  (`EditMenuRoutingWindowTests`, M6-5); Space over the canvas opens the palette with its search field focused, \"f+\" is\n"
    "  typed into it and Return adds the node (`PaletteKeyRoutingWindowTests`, EP-2). The canvas hover veto and the\n"
    "  `Panel` key context in `AppInput` are not what these tests depend on: with either removed they still pass, because C9's\n"
    "  key region and a focused field claim the keys first. **Not driven yet** (adopted, untested): the sketch toolbar's button\n"
    "  shortcuts ahead of the palette (M6-11), the window shell (close veto, title, edited dot: group AS), the viewport's\n"
    "  gesture glue (group V) and the inspector box's own focus-loss commit (CM-7).\n")

rep(CHECKS,
    "- [ ] **M6-4 Keys and focus.** Click into an inspector number field and type \"f\", \"+\" and \"-\": they go into the field;\n  the viewport doesn't frame or zoom. Open the palette and type \"f+\": they go into the search field. Click empty\n  viewport space (the field loses focus), then press F, + and −: the viewport frames and zooms. Move the pointer over\n  the graph canvas and press + and −: the graph zooms, not the viewport; press F there: the viewport frames. Pinned:\n  `AppInputTests`; the dispatch through a window is this check only (gap M6-e). **Observed:**",
    "- [ ] **M6-4 Keys and focus.** **Automated, no manual step** (`ViewportKeyRoutingWindowTests`, `PaletteKeyRoutingWindowTests`,\n  through the app's real window): \"f\", \"+\" and \"-\" pressed with an inspector field focused leave the viewport alone, and a\n  press on the viewport gives the keys back; with the pointer over the viewport + and − zoom it and F frames it; over the\n  graph canvas + and − zoom the graph and F frames the graph's selection, not the viewport (spec 2026-10-09 §3: this\n  line used to say the viewport frames); the open palette's search field takes \"f+\". **By hand:** the same on a\n  physical keyboard (+ is ⇧= on a US layout). Pinned: `AppInputTests` (the mapping). **Observed:**")

rep(CHECKS,
    "- [ ] **M6-5 Menu bar and chords.** ⌘Z and ⇧⌘Z undo and redo graph edits (Edit menu). With a node selected and the\n  pointer over the canvas, ⌘C, ⌘V and ⌘D copy, paste and duplicate it (the standard Copy and Paste items don't swallow\n  the keys). ⌘N, ⌘O, ⌘S, ⇧⌘S, ⌘E and ⇧⌘E run New, Open…, Save, Save As…, Export STEP… and Export STL…. **Observed:**",
    "- [ ] **M6-5 Menu bar and chords (what is left).** **Automated, no manual step** (`EditMenuRoutingWindowTests`): the Edit menu\n  is titled by the step (\"Undo Edit Note\") and its Undo and Redo run; ⌘Z and ⇧⌘Z undo and redo one step each over the\n  canvas and over the viewport; with a node selected and the pointer over the canvas, ⌘C, ⌘V and ⌘D copy, paste and\n  duplicate it (the standard Copy and Paste items don't swallow the keys) and do nothing over the viewport. **By hand:**\n  ⌘N, ⌘O, ⌘S, ⇧⌘S, ⌘E and ⇧⌘E run New, Open…, Save, Save As…, Export STEP… and Export STL…. **Observed:**")

rep(CHECKS,
    "`atTheBottomDockItFlipsUpAndAddsAtThePressPoint`; the key context is this check only (gap M6-e). **Observed:**",
    "`atTheBottomDockItFlipsUpAndAddsAtThePressPoint`. **Automated** (`PaletteKeyRoutingWindowTests`): Space over the canvas opens\n  the palette with the search field focused, \"f+\" go into the field (the viewport neither frames nor zooms), Return adds a\n  node and selects it, ⌘Z removes it in one step, Esc closes the palette and adds nothing. **By hand:** the rows' scrolling\n  and where the node lands. **Observed:**")
PY
```

- [ ] **Step: Full run and lint.**

```bash
swift test 2>&1 | tee /tmp/harness-test.log; echo "exit: ${PIPESTATUS[0]}"
```

```bash
grep -c "Test run with" /tmp/harness-test.log                                   # must print 11
grep -c "recorded an issue\|failed after" /tmp/harness-test.log                # must print 0
grep "Test run with" /tmp/harness-test.log | sed -E 's/.*with ([0-9]+) tests?.*/\1/' | paste -sd+ - | bc   # the total
grep "warning:" /tmp/harness-test.log | grep -E "/(Sources|Tests)/" | sort -u   # only ContextMenuTests.swift:140 (already on master)
swiftlint lint --strict --quiet                                                 # no output
```

Expected: exit 0, 11 `Test run with` lines, 0 issue lines, total **2675** (master + 36), no project-source warning but the one already on master, no lint output.

- [ ] **Step: Commit** (end the message with the attribution lines the session specifies).

```bash
git add -A
git commit -m "test(app): F, + and -, the Edit menu's chords and the palette's keys through the real window (M6-e's routes)"
```

### Task 6: TH-a, View ▸ Theme evaluated

**Files:**
- Create: `Tests/CreatorAppTests/ThemeMenuEvaluationTests.swift`
- Modify: `docs/metalui-gaps.md` (TH-a row and entry), `Sources/CreatorApp/ThemeMenu.swift` (one doc-comment line)

**Interfaces:**
- Consumes: `ThemeMenu.items(_:)` (an `@MenuContentBuilder`), `ThemeEditorModel` (`select(_:)`, `open()`, `isOpen`, `theme`), `ThemeStore` (`duplicate`, `rename`, `current`), `AppCommands`; MetalUITesting's `MenuEvaluation`, `TestApp.menuBar`, `performMenuBarItem(_:)`; Task 1's `AppWindow.open()`.
- Produces: nothing later tasks use.

- [ ] **Step 1: Write the tests.** `Tests/CreatorAppTests/ThemeMenuEvaluationTests.swift`:

```swift
import CreatorStyle
import MetalUI
import MetalUIScene
import MetalUITesting
import Testing
@testable import CreatorApp

/// What View ▸ Theme lists, which item is checked and what choosing one does, read from the evaluated menu itself
/// (gap TH-a): `MenuEvaluation` evaluates `ThemeMenu.items` as a window would at the menu's open, and the app's menu
/// bar (`AppCommands`) is read and run through `TestApp.menuBar`.
@MainActor
struct ThemeMenuEvaluationTests {
    /// Titles of the evaluated items, with a separator as "-".
    func titles(_ items: [PlatformMenuItem]) -> [String] {
        items.map { item in
            if case .separator = item.kind { "-" } else { item.title }
        }
    }

    func customThemes() throws -> ThemeStore {
        let store = ThemeStore()
        let zebra = try store.duplicate("nord")
        try store.rename(zebra.id, to: "Zebra")
        try store.duplicate("alucard")
        return store
    }

    @Test func withoutCustomThemesTheMenuListsTheBuiltInsThenEditThemes() {
        let menu = MenuEvaluation { ThemeMenu.items(ThemeEditorModel(themes: ThemeStore())) }
        #expect(titles(menu.items) == ["Dracula", "Alucard", "Nord", "-", "Edit Themes…"])
    }

    @Test func customThemesFollowTheBuiltInsDividedFromThemAndFromEditThemes() throws {
        let editor = ThemeEditorModel(themes: try customThemes())
        let menu = MenuEvaluation { ThemeMenu.items(editor) }
        #expect(titles(menu.items) == ["Dracula", "Alucard", "Nord", "-", "Alucard Copy", "Zebra", "-", "Edit Themes…"])
    }

    @Test func theShownThemeAloneIsChecked() throws {
        let store = ThemeStore()
        let editor = ThemeEditorModel(themes: store)
        let checked = MenuEvaluation { ThemeMenu.items(editor) }.items.filter(\.isOn).map(\.title)
        #expect(checked == [store.current.name])
        editor.select("nord")
        let afterwards = MenuEvaluation { ThemeMenu.items(editor) }.items.filter(\.isOn).map(\.title)
        #expect(afterwards == ["Nord"])
    }

    @Test func choosingAThemeShowsItAtOnceAndEditThemesOpensTheEditor() throws {
        let editor = ThemeEditorModel(themes: ThemeStore())
        let menu = MenuEvaluation { ThemeMenu.items(editor) }
        try menu.perform("Alucard")
        #expect(editor.theme.name == "Alucard")
        #expect(!editor.isOpen)
        try menu.perform("Edit Themes…")
        #expect(editor.isOpen)
    }

    // MARK: - The app's menu bar

    /// Every rect's fill, in draw order: what a theme change repaints.
    func fills(_ scene: Scene) -> [[Float]] {
        scene.rects.map { [$0.background.h, $0.background.s, $0.background.l, $0.background.a] }
    }

    func themeSubmenu(_ app: AppWindow) throws -> [PlatformMenuItem] {
        let view = try #require(app.testApp.menuBar.first { $0.title == "View" })
        guard case .submenu(let items)? = view.items.first(where: { $0.title == "Theme" })?.kind else {
            Issue.record("View has no Theme submenu")
            return []
        }
        return items
    }

    @Test func theMenuBarHasViewThemeWithTheShownThemeChecked() async throws {
        let app = try await AppWindow.open()
        let items = try themeSubmenu(app)
        #expect(titles(items) == ["Dracula", "Alucard", "Nord", "-", "Edit Themes…"])
        #expect(items.filter(\.isOn).map(\.title) == [app.model.themes.current.name])
    }

    @Test func choosingAThemeInTheMenuBarRestylesTheWindow() async throws {
        let app = try await AppWindow.open()
        let before = fills(app.window.scene)
        try app.testApp.performMenuBarItem("View", "Theme", "Alucard")
        #expect(app.model.themes.current.name == "Alucard")
        #expect(try themeSubmenu(app).filter(\.isOn).map(\.title) == ["Alucard"])
        #expect(fills(app.window.scene) != before, "the frame drawn after the choice is in the new theme")
        try app.testApp.performMenuBarItem("View", "Theme", "Edit Themes…")
        #expect(app.themeEditor.isOpen)
    }
}
```

- [ ] **Step 2: Run them.** `swift test --filter ThemeMenuEvaluationTests 2>&1 | grep -E "Test run with|recorded an issue"`
Expected: `Test run with 6 tests in 1 suite passed` (characterization of shipped behaviour; `ThemeMenuTests` stays and still passes).

- [ ] **Step 3: Prove they bite.**

| Mutation | Run | Expected failure |
|---|---|---|
| `Sources/CreatorApp/ThemeMenu.swift`: delete the `Divider()` line inside the `for section` loop | `--filter ThemeMenuEvaluationTests` | the three tests that list titles fail |
| same file: `set: { _ in editor.select(theme.id) }` → `set: { _ in }` | same | `choosingAThemeShowsItAtOnceAndEditThemesOpensTheEditor` and `choosingAThemeInTheMenuBarRestylesTheWindow` fail |

- [ ] **Step 4: Mark TH-a adopted.**

```bash
python3 - <<'PY'
def rep(path, old, new):
    text = open(path, encoding="utf-8").read()
    assert text.count(old) == 1, f"{path}: anchor found {text.count(old)} times: {old[:60]!r}"
    open(path, "w", encoding="utf-8").write(text.replace(old, new))

GAPS = "docs/metalui-gaps.md"
CHECKS = "docs/verification/human-checks.md"

rep(GAPS,
    "| TH-a | Menu content can't be evaluated outside MetalUI | none yet (with M6-e) | 🟡 landed in MetalUI master 280d706 (item 8, `MetalUITesting`); adoption here pending |",
    "| TH-a | Menu content can't be evaluated outside MetalUI | none yet (with M6-e) | ✅ fixed (MetalUI 280d706, `MenuEvaluation`, `TestApp.menuBar`), adopted (plan `2026-10-12-adopt-test-harness`): `ThemeMenuEvaluationTests` |")

rep(GAPS,
    "  item), or one in a test-support product (with M6-e's headless window).\n",
    "  item), or one in a test-support product (with M6-e's headless window).\n"
    "  **Fixed by MetalUI item 8** (master 280d706: `MenuEvaluation`, `TestApp.menuBar`, `performMenuBarItem`) **and adopted**\n"
    "  (plan `2026-10-12-adopt-test-harness`): `ThemeMenuEvaluationTests` evaluates `ThemeMenu.items` as a window does at the\n"
    "  menu's open and checks what it lists (built-ins, divider, custom themes, divider, Edit Themes…), which item is checked,\n"
    "  and that choosing one shows the theme and Edit Themes… opens the editor; it also reads View ▸ Theme from the app's\n"
    "  menu bar (`AppCommands`) and runs an item through `performMenuBarItem`, which restyles the window. `ThemeMenu.sections(_:)`\n"
    "  stays: it is the list the menu is built from, and `ThemeMenuTests` keeps pinning it.\n")

rep("Sources/CreatorApp/ThemeMenu.swift",
    "    /// (What the menu lists is tested here: MetalUI can't evaluate menu content outside itself, gap TH-a.)\n",
    "    /// (This list is tested here; what the evaluated menu shows and does is tested in `ThemeMenuEvaluationTests`, gap TH-a.)\n")
PY
```

- [ ] **Step: Full run and lint.**

```bash
swift test 2>&1 | tee /tmp/harness-test.log; echo "exit: ${PIPESTATUS[0]}"
```

```bash
grep -c "Test run with" /tmp/harness-test.log                                   # must print 11
grep -c "recorded an issue\|failed after" /tmp/harness-test.log                # must print 0
grep "Test run with" /tmp/harness-test.log | sed -E 's/.*with ([0-9]+) tests?.*/\1/' | paste -sd+ - | bc   # the total
grep "warning:" /tmp/harness-test.log | grep -E "/(Sources|Tests)/" | sort -u   # only ContextMenuTests.swift:140 (already on master)
swiftlint lint --strict --quiet                                                 # no output
```

Expected: exit 0, 11 `Test run with` lines, 0 issue lines, total **2681** (master + 42), no project-source warning but the one already on master, no lint output.

- [ ] **Step: Commit** (end the message with the attribution lines the session specifies).

```bash
git add -A
git commit -m "test(app): View > Theme read through MenuEvaluation and the menu bar; TH-a adopted"
```

### Task 7: M7-b, the warm idle frame by work counts

**Files:**
- Create: `Tests/CreatorAppTests/WarmFrameTests.swift`
- Modify: `Tests/CreatorAppTests/Support/AppWindow.swift` (one helper), `docs/metalui-gaps.md` (M7-b row and entry)

**Interfaces:**
- Consumes: `AppWindow.open(_:recordsLayout:)`, `TypingFixture().otherNote`, `GraphBuilder.box(at:)`; MetalUITesting's `TestWindow.frameWork`, `.lastFrameWork`, `.resetFrameWork()`, `.framesDrawn`, `.advanceFrames(_:)`, `.runUntilIdle()`, and `FrameWork` (`builds`, `atlasUploadPixels`, `rasterizedPixels`, `blurredPixels`, `newTextures`, `newTexturePixels`, `glyphs`, `rects`; `Equatable`).
- Produces: `AppWindow.redraw()`.

- [ ] **Step 1: Write the failing tests.** `Tests/CreatorAppTests/WarmFrameTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The idle editor's frames, counted by work and never by time (gap M7-b; MetalUI's `FrameWork`): a window is one
/// `Window` for its life, so every frame after the first is warm, with its shaping, rasters and textures kept. These pin
/// what must stay true of a warm frame whatever the machine: an idle window draws nothing, and a warm frame uploads no
/// glyph pixels, rasterizes and blurs no pixels and makes no texture. They are not timing assertions, and the release
/// benchmark (`Bench`, docs/verification/performance.md) stays the place for milliseconds.
@MainActor
struct WarmFrameTests {
    /// The editor with a small graph and a note on screen, laid out as production lays out (`recordsLayout: false`).
    func idleEditor() async throws -> AppWindow {
        var builder = GraphBuilder()
        _ = builder.box(at: Vector2(40, 40))
        var graph = builder.graph
        let note = TypingFixture().otherNote
        graph.stickies[note.id] = note
        let app = try await AppWindow.open(graph, recordsLayout: false)
        try await app.window.runUntilIdle()
        return app
    }

    @Test func theFirstFrameDoesTheColdWork() async throws {
        let app = try await idleEditor()
        let first = try #require(app.window.frameWork.first)
        #expect(first.atlasUploadPixels > 0, "the glyph atlas was filled")
        #expect(first.glyphs > 0 && first.rects > 0)
    }

    @Test func anIdleWindowDrawsNoFrameAtAll() async throws {
        let app = try await idleEditor()
        let drawn = app.window.framesDrawn
        let recorded = app.window.frameWork.count
        app.window.advanceFrames(10)
        try await app.window.runUntilIdle()
        #expect(app.window.framesDrawn == drawn, "ten display-link ticks with nothing dirty draw nothing")
        #expect(app.window.frameWork.count == recorded)
    }

    @Test func aWarmFrameUploadsRasterizesAndBlursNothing() async throws {
        let app = try await idleEditor()
        app.window.resetFrameWork()
        app.redraw()
        app.redraw()
        let warm = app.window.frameWork
        #expect(warm.count == 2)
        for work in warm {
            #expect(work.builds == 1)
            #expect(work.atlasUploadPixels == 0, "no glyph is shaped into the atlas again")
            #expect(work.rasterizedPixels == 0 && work.blurredPixels == 0, "no shadow or image is rasterized again")
            #expect(work.newTextures == 0 && work.newTexturePixels == 0)
        }
    }

    @Test func aSecondUnchangedFrameDoesExactlyTheWorkOfTheFirst() async throws {
        let app = try await idleEditor()
        app.window.resetFrameWork()
        app.redraw()
        app.redraw()
        let warm = app.window.frameWork
        #expect(warm.count == 2)
        #expect(warm[0] == warm[1], "a warm frame is steady: the same builds, measures, rects and glyphs every time")
    }
}
```

- [ ] **Step 2: Run to see the build fail.** `swift test --filter WarmFrameTests 2>&1 | grep "error:" | head -2`
Expected: `value of type 'AppWindow' has no member 'redraw'`.

- [ ] **Step 3: Add the helper to `AppWindow`**, immediately before `    /// A window point from a vector.`:

```swift
    /// Draws one more frame with nothing changed, as a display link would after something marked the window dirty.
    func redraw() {
        window.window.setNeedsRedraw()
        window.tick()
    }

```

- [ ] **Step 4: Run them.** `swift test --filter WarmFrameTests 2>&1 | grep -E "Test run with|recorded an issue"`
Expected: `Test run with 4 tests in 1 suite passed`.

- [ ] **Step 5: Prove the idle test bites.** In `Sources/CreatorApp/AppRoot.swift` add a line `            ProgressView()` before `            PaletteDock(model: model)` (a spinner that never stops asks for frames forever), run `swift test --filter WarmFrameTests` (Expected: `anIdleWindowDrawsNoFrameAtAll` fails on both expectations), and revert. The atlas, raster and texture counters are asserted to be 0 on a warm frame and `theFirstFrameDoesTheColdWork` shows the same counters are positive on the first frame, so they are not vacuous; no mutation of the shipped views makes a warm frame upload, so that half is verified by that contrast only.

- [ ] **Step 6: Mark M7-b adopted** (and say plainly what was left).

```bash
python3 - <<'PY'
def rep(path, old, new):
    text = open(path, encoding="utf-8").read()
    assert text.count(old) == 1, f"{path}: anchor found {text.count(old)} times: {old[:60]!r}"
    open(path, "w", encoding="utf-8").write(text.replace(old, new))

GAPS = "docs/metalui-gaps.md"
CHECKS = "docs/verification/human-checks.md"

rep(GAPS,
    "| M7-b | No warm headless frame for measuring | none yet (with M6-e) | 🟡 landed in MetalUI master 280d706 (item 8, `MetalUITesting`); adoption here pending |",
    "| M7-b | No warm headless frame for measuring | none yet (with M6-e) | ✅ fixed (MetalUI 280d706, `TestWindow` warm frames and `FrameWork`), adopted for work counts (plan `2026-10-12-adopt-test-harness`): `WarmFrameTests`; the release benchmarks (`Bench`) still report cold-frame milliseconds until they are moved onto it |")

rep(GAPS,
    "  window (or a frame renderer that keeps its caches across frames) that a client can drive with input and time,\n  including the display link's pacing.\n",
    "  window (or a frame renderer that keeps its caches across frames) that a client can drive with input and time,\n  including the display link's pacing.\n"
    "  **Fixed by MetalUI item 8** (master 280d706: a `TestWindow` is one `Window` for its life, `lastFrameWork`/`frameWork`\n"
    "  count the work of each frame) **and adopted for counts** (plan `2026-10-12-adopt-test-harness`): `WarmFrameTests` opens\n"
    "  the editor with `recordsLayout: false` and pins what is stable on any machine, never a time: an idle window draws no\n"
    "  frame at all, a warm redraw uploads no atlas pixels, rasterizes and blurs no pixels and makes no texture, and a second\n"
    "  unchanged frame does exactly the work of the first. It does **not** pin zero layout work: a forced redraw of the\n"
    "  whole window re-measures it (hundreds of layout cache misses at 1440 × 900), which is PERF-b (C14, queued), so the\n"
    "  test leaves that number to PERF-b's own adoption. Not done: moving `Tests/CreatorAppTests/Bench` onto the warm\n"
    "  window (the release benchmark is never run in this plan); `docs/verification/performance.md` still says cold frames.\n")
PY
```

- [ ] **Step: Full run and lint.**

```bash
swift test 2>&1 | tee /tmp/harness-test.log; echo "exit: ${PIPESTATUS[0]}"
```

```bash
grep -c "Test run with" /tmp/harness-test.log                                   # must print 11
grep -c "recorded an issue\|failed after" /tmp/harness-test.log                # must print 0
grep "Test run with" /tmp/harness-test.log | sed -E 's/.*with ([0-9]+) tests?.*/\1/' | paste -sd+ - | bc   # the total
grep "warning:" /tmp/harness-test.log | grep -E "/(Sources|Tests)/" | sort -u   # only ContextMenuTests.swift:140 (already on master)
swiftlint lint --strict --quiet                                                 # no output
```

Expected: exit 0, 11 `Test run with` lines, 0 issue lines, total **2685** (master + 46), no project-source warning but the one already on master, no lint output.

- [ ] **Step: Commit** (end the message with the attribution lines the session specifies).

```bash
git add -A
git commit -m "test(app): warm idle frame counted by work, no timing; M7-b adopted"
```

### Task 8: the C10 leftovers of M6-e, the refusal shake and the inspector slider through the window

**Files:**
- Create: `Tests/CreatorAppTests/InspectorSliderWindowTests.swift`, `Tests/CreatorAppTests/RefusalShakeWindowTests.swift`
- Modify: `docs/metalui-gaps.md` (the "M6-e and M7-b, used again" paragraph), `docs/verification/human-checks.md` (group C10: header, C10-2, C10-4)

**Interfaces:**
- Consumes: `AppWindow.open`, `AppWindow.redraw()` (Task 7), `AppWindow.point(inCanvas:)`; `RefusalShake`, `EditorModel.connect(_:)`, `.shakeCount(of:)`; MetalUITesting's `TestWindow.advance(by:)`, `.scene`, `.elements(role:)`, `.drag(from:to:steps:)`.
- Produces: nothing later tasks use.

- [ ] **Step 1: Write the tests.**

`Tests/CreatorAppTests/InspectorSliderWindowTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// A drag on the inspector's slider, through the app's real window (gap M5-a, used again by the C10 adoption): MetalUI's
/// `Slider(onEditingChanged:)` pairs the press and the release, so each drag is exactly one undo step.
@MainActor
struct InspectorSliderWindowTests {
    /// The window showing a Rectangle node, selected, and its inspector's first slider (Width).
    func selectedRectangle() async throws -> (app: AppWindow, node: Node, slider: TestElement) {
        var builder = GraphBuilder()
        let node = builder.add(RectangleNode.self, at: Vector2(40, 40))
        let app = try await AppWindow.open(builder.graph)
        app.window.click(at: app.point(inCanvas: Vector2(60, 80)))
        #expect(app.editor.selection == [node.id])
        let slider = try #require(app.window.elements(role: .slider).first)
        return (app, node, slider)
    }

    /// A drag along the slider's track from `from` to `to`, each a fraction of its width.
    func drag(_ app: AppWindow, _ slider: TestElement, from: Float, to: Float) {
        let y = slider.frame.origin.y + slider.frame.size.height / 2
        let width = slider.frame.size.width.value
        app.window.drag(from: Point(x: slider.frame.origin.x + Pixels(width * from), y: y),
                        to: Point(x: slider.frame.origin.x + Pixels(width * to), y: y), steps: 6)
    }

    @Test func aDragIsOneUndoStep() async throws {
        let (app, node, slider) = try await selectedRectangle()
        drag(app, slider, from: 0.1, to: 0.9)
        guard case .number(let width)? = app.editor.graph.nodes[node.id]?.inputValues["width"] else {
            Issue.record("the drag wrote no width")
            return
        }
        #expect(width > 0)
        #expect(app.editor.document.undoName == "Change Width")
        app.editor.document.undo()
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == nil, "one undo undoes the whole drag")
        #expect(!app.editor.document.canUndo)
    }

    @Test func twoDragsAreTwoUndoSteps() async throws {
        let (app, node, slider) = try await selectedRectangle()
        drag(app, slider, from: 0.1, to: 0.9)
        let first = app.editor.graph.nodes[node.id]?.inputValues["width"]
        drag(app, slider, from: 0.9, to: 0.4)
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] != first)
        app.editor.document.undo()
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == first, "the second drag was a step of its own")
        app.editor.document.undo()
        #expect(app.editor.graph.nodes[node.id]?.inputValues["width"] == nil && !app.editor.document.canUndo)
    }
}
```

`Tests/CreatorAppTests/RefusalShakeWindowTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// The refusal shake running in the app's window (gap M5-i, used again by the C10 adoption): the window's clock moves by
/// hand, and the frames drawn at those times show the node out, across and home (`RefusalShake`'s keyframes).
@MainActor
struct RefusalShakeWindowTests {
    /// A Rectangle and an Extrude, apart, and the link the editor refuses (a profile into a number input).
    func refusedLink() async throws -> (app: AppWindow, extrude: Node, link: Link) {
        var builder = GraphBuilder()
        let rectangle = builder.add(RectangleNode.self, at: Vector2(40, 40))
        let extrude = builder.add(ExtrudeNode.self, at: Vector2(300, 40))
        let app = try await AppWindow.open(builder.graph)
        let link = Link(from: Endpoint(node: rectangle.id, socket: "profile"), to: Endpoint(node: extrude.id, socket: "distance"))
        return (app, extrude, link)
    }

    /// The x of every rect in the last frame, in draw order.
    func xs(_ app: AppWindow) -> [Float] {
        app.window.scene.rects.map(\.bounds.origin.x)
    }

    /// How far each rect of the last frame is from where it was `rest`.
    func shifts(_ app: AppWindow, from rest: [Float]) -> [Float] {
        zip(rest, xs(app)).map { $1 - $0 }
    }

    @Test func aRefusedConnectionShakesTheTargetNodeOutAcrossAndHome() async throws {
        let (app, extrude, link) = try await refusedLink()
        let rest = xs(app)
        app.editor.connect(link)
        #expect(app.editor.shakeCount(of: extrude.id) == 1)
        app.redraw()
        app.window.advance(by: 0.05)
        let distance: Float = 6   // the keyframes' reach, in points (`RefusalShake.distance`), written out so a change shows here
        let out = shifts(app, from: rest)
        #expect(out.contains(distance) && !out.contains { $0 != 0 && $0 != distance },
                "after 0.05 s the node is 6 points out, and only the node moved")
        #expect(out.filter { $0 == 0 }.count > 0, "the rest of the window stayed put")
        app.window.advance(by: 0.1)
        #expect(shifts(app, from: rest).filter { $0 != 0 }.allSatisfy { $0 == -distance }, "then 6 across")
        app.window.advance(by: 0.1)
        #expect(shifts(app, from: rest).allSatisfy { $0 == 0 }, "and home: the shake lasts a fifth of a second")
    }

    @Test func eachNewRefusalShakesAgain() async throws {
        let (app, extrude, link) = try await refusedLink()
        let rest = xs(app)
        app.editor.connect(link)
        app.redraw()
        app.window.advance(by: 0.3)
        #expect(shifts(app, from: rest).allSatisfy { $0 == 0 })
        app.editor.connect(link)
        #expect(app.editor.shakeCount(of: extrude.id) == 2)
        app.redraw()
        app.window.advance(by: 0.05)
        #expect(shifts(app, from: rest).contains { $0 != 0 }, "the second refusal moved the node again")
    }
}
```

- [ ] **Step 2: Run them.** `swift test --filter "InspectorSliderWindowTests|RefusalShakeWindowTests" 2>&1 | grep -E "Test run with|recorded an issue"`
Expected: `Test run with 4 tests in 2 suites passed`.

- [ ] **Step 3: Prove they bite.**

| Mutation | Run | Expected failure |
|---|---|---|
| `Sources/CreatorEditor/RefusalShake.swift`: `static let distance = 6.0` → `0.0` | `--filter RefusalShakeWindowTests` | both tests fail (the literal 6 in the test is deliberate: comparing against `RefusalShake.distance` would pass with 0) |
| `Sources/CreatorEditor/EditorModel+Inspector.swift`: delete `document.endCoalescing()` in `sliderEditingChanged` | `--filter InspectorSliderWindowTests` | `twoDragsAreTwoUndoSteps` fails |

- [ ] **Step 4: Record it.**

```bash
python3 - <<'PY'
def rep(path, old, new):
    text = open(path, encoding="utf-8").read()
    assert text.count(old) == 1, f"{path}: anchor found {text.count(old)} times: {old[:60]!r}"
    open(path, "w", encoding="utf-8").write(text.replace(old, new))

GAPS = "docs/metalui-gaps.md"
CHECKS = "docs/verification/human-checks.md"

rep(GAPS,
    "  test can tick a `keyframeAnimator` and a `ProgressView` and press a `Slider`.\n",
    "  test can tick a `keyframeAnimator` and a `ProgressView` and press a `Slider`.\n"
    "  **Fixed by MetalUI item 8, partly adopted** (plan `2026-10-12-adopt-test-harness`): `RefusalShakeWindowTests` moves the\n"
    "  window's clock by hand and reads the frames (a refused node is 6 points out at 0.05 s, 6 across at 0.15 s and home at\n"
    "  0.25 s, only that node moves, and a second refusal shakes again) and `InspectorSliderWindowTests` drags the inspector's\n"
    "  real slider (one drag is one \"Change Width\" step, two drags are two). Not adopted: the spinner turning, because a\n"
    "  node can be held mid-evaluation only by a kernel that waits, which no test kernel does; human check C10-3 stays.\n")

rep(CHECKS,
    "spinner's still frame and the gradient's pixels; a real window is needed for the motion (no public headless window or\nframe time, gaps M6-e and M7-b) and for how things look. Run",
    "spinner's still frame and the gradient's pixels. Since the test-harness adoption (plan `2026-10-12-adopt-test-harness.md`,\ngaps M6-e and M7-b) the shake's motion and the slider's undo pairing are also driven through the app's real window and\nits clock (`RefusalShakeWindowTests`, `InspectorSliderWindowTests`); a real window is still needed for the spinner's\nturning and for how things look. Run")

rep(CHECKS,
    "Pinned: `RefusalShakeTests` (the keyframes at injected times, the\n  per-node count, a refused node drawn at rest). **Observed:**",
    "Pinned: `RefusalShakeTests` (the keyframes at injected times, the\n  per-node count, a refused node drawn at rest). **Automated** (`RefusalShakeWindowTests`, fed through\n  `EditorModel.connect`, not a pointer drag): in the app's window a refused node is 6 points out at 0.05 s, 6 across at\n  0.15 s and home at 0.25 s, only that node moves, and a second refusal shakes again. **By hand:** the look (crisp, not\n  bouncy), the message for two seconds, panning during a shake, a refused node scrolled out of sight and back, a normal\n  drag. **Observed:**")

rep(CHECKS,
    "Pinned: `SliderEditingTests` (the\n  model); the pairing through a real window is this check only. **Observed:**",
    "Pinned: `SliderEditingTests` (the\n  model). **Automated** (`InspectorSliderWindowTests`): a drag on the inspector's real slider is one \"Change Width\" undo\n  step and two drags are two. **By hand:** a document parameter's slider, a click on the track without moving, and ←\n  three times. **Observed:**")
PY
```

- [ ] **Step: Full run and lint.**

```bash
swift test 2>&1 | tee /tmp/harness-test.log; echo "exit: ${PIPESTATUS[0]}"
```

```bash
grep -c "Test run with" /tmp/harness-test.log                                   # must print 11
grep -c "recorded an issue\|failed after" /tmp/harness-test.log                # must print 0
grep "Test run with" /tmp/harness-test.log | sed -E 's/.*with ([0-9]+) tests?.*/\1/' | paste -sd+ - | bc   # the total
grep "warning:" /tmp/harness-test.log | grep -E "/(Sources|Tests)/" | sort -u   # only ContextMenuTests.swift:140 (already on master)
swiftlint lint --strict --quiet                                                 # no output
```

Expected: exit 0, 11 `Test run with` lines, 0 issue lines, total **2689** (master + 50), no project-source warning but the one already on master, no lint output.

- [ ] **Step: Commit** (end the message with the attribution lines the session specifies).

```bash
git add -A
git commit -m "test(app): refusal shake and inspector slider through the real window"
```

### Task 9: final sweep (docs and comments only)

Triage of every remaining citation of gap M6-e or "no headless window": the ones whose behaviour a task above now drives are marked automated there; the rest are reworded to say the window exists and no test covers them yet (so the next reader does not take "no headless window" for a fact), and the doc comments in code that say the same are reworded. Left untouched on purpose, being history: `docs/metalui-gaps.md` PERF-a ("they need `@testable import MetalUI`, gap M6-e": the benchmark harnesses, not checked in), S5-b ("can't be checked from a client without a headless window": a stopgap's origin) and CM-a's "Originally (before C9)".

**Files:**
- Modify: `docs/verification/human-checks.md` (groups V, GI, AS, MS, CM: the clause citing M6-e), `Tests/CreatorAppTests/AppInputTests.swift`, `Tests/CreatorAppTests/AppModelCloseTests.swift`, `Tests/CreatorSketchEditorTests/SketchViewTests.swift` (one doc comment each)

- [ ] **Step 1: Reword the remaining M6-e citations.** From the worktree root:

```bash
python3 - <<'PY'
def rep(path, old, new):
    text = open(path, encoding="utf-8").read()
    assert text.count(old) == 1, f"{path}: anchor found {text.count(old)} times: {old[:60]!r}"
    open(path, "w", encoding="utf-8").write(text.replace(old, new))

CHECKS = "docs/verification/human-checks.md"

rep(CHECKS,
    "`ViewportView+Parts.swift` `surface(model:)` has no headless coverage (no headless MetalUI window, gap M6-e). That\nglue is",
    "`ViewportView+Parts.swift` `surface(model:)` has no test through a window yet (gap M6-e is adopted: a `MetalUITesting`\nwindow can drive it, and a press on the viewport already runs through it in `CanvasTypingFocusWindowTests`). That\nglue is")

rep(CHECKS,
    "The view glue has no headless coverage (no\nheadless MetalUI window, gap M6-e): `GraphCanvas`'s",
    "The view glue has no test through a window yet\n(gap M6-e is adopted: a `MetalUITesting` window can drive it; the canvas typing and the graph's keys already do, group CT):\n`GraphCanvas`'s")

rep(CHECKS,
    "Finder do with it is these checks only (gap M6-e).",
    "Finder do with it is these checks only (gap M6-e is adopted: `TestWindow.requestClose()` and `presentedAlert` could drive\nthe window half; no test does yet).")

rep(CHECKS,
    "these check the gestures and keys through a real window (no\nheadless MetalUI window, gap M6-e). Run",
    "these check the gestures and keys through a real window (gap\nM6-e is adopted: the graph's keys and the Edit chords are driven in groups CT and M6, the gestures not yet). Run")

rep(CHECKS,
    "inspector's text field through a real window (no headless MetalUI window, gap M6-e). Run",
    "inspector's text field through a real window (gap M6-e is adopted: the typing, the note box and the Undo are driven in group\nCT, the rest not yet). Run")

rep(CHECKS,
    "The field losing focus commits the text, and no headless test reaches that (a focus loss\n  needs a real window, gap M6-e): only the model-level commit is pinned, so **record",
    "The field losing focus commits the text; through the window only the canvas editor's focus loss is driven\n  (`clickingIntoTheInspectorsBoxCommitsTheCanvasEditFirst`, group CT), not this box's own (gap M6-e is adopted), so only the\n  model-level commit is pinned here, and **record")

rep("Tests/CreatorAppTests/AppInputTests.swift",
    "/// The window's key routing, as far as it can be pinned without a real `Window` (its initializer is internal):\n/// the keymap and its contexts, and what `onAction` and `onInput` do. The routing through a window is human\n/// checks M6-4 and M6-5.",
    "/// The window's key routing at the level of the mapping: the keymap and its contexts, and what `onAction` and `onInput`\n/// do. The routing through a real window is `ViewportKeyRoutingWindowTests`, `EditMenuRoutingWindowTests` and\n/// `PaletteKeyRoutingWindowTests` (`MetalUITesting`, gap M6-e).")

rep("Tests/CreatorAppTests/AppModelCloseTests.swift",
    "MetalUI's window and app are not built here (no public headless window, gap M6-e), so the\n/// model's handler and reply are driven directly.",
    "MetalUI's window and app are not built here (a `MetalUITesting` window could drive the close,\n/// gap M6-e adopted; no test does yet), so the model's handler and reply are driven directly.")

rep("Tests/CreatorSketchEditorTests/SketchViewTests.swift",
    "human checks (group S5; a client can't send keys through a window, docs/metalui-gaps.md M6-e).",
    "human checks (group S5; a window test could send them keys with `MetalUITesting`, docs/metalui-gaps.md M6-e, adopted).")
PY
```

(If a `rep` fails, the line was edited by another track: reword by hand in the same spirit, keeping their edit.)

- [ ] **Step 2: Everything is consistent.**

```bash
grep -n "adoption here pending\|adoption pending" docs/metalui-gaps.md   # no output: M6-e, TH-a, M7-b, CT-c are all adopted
grep -n "^| \(M6-e\|TH-a\|M7-b\|CT-c\|M4-a\) " docs/metalui-gaps.md | cut -c1-110   # five rows; M6-e, TH-a, M7-b, CT-c say "✅", M4-a "🟡"
grep -n "HT-a" docs/metalui-gaps.md docs/verification/human-checks.md    # no output: no such gap exists
grep -n "no headless\|headless MetalUI window\|gap M6-e" docs/verification/human-checks.md | cut -c1-120   # only "adopted" wordings
grep -rn "MetalUITesting" Package.swift                                     # the constant and CreatorAppTests only
git diff 9e5d2d5 --stat -- Sources Package.swift                             # Sources: CommentKeys.swift and ThemeMenu.swift; Package.swift: the test target
git diff 9e5d2d5 -- Package.swift | grep '^[-+].*package(path'               # no output: the MetalUI path is untouched
```

- [ ] **Step 3: A clean full run** (from a clean build, to see warnings): `rm -rf .build && swift test 2>&1 | tee /tmp/harness-test.log`, then the checks in Task 1's "Full run" step. Expected total **2689** (master + 50), 11 run lines, exit 0, `swiftlint lint --strict --quiet` silent.

- [ ] **Step 4: Do not push and do not run the release benchmark.** The merge order (7a-layouts, 7a-variation, then this) and the push (`git push origin master:main`, once green) belong to the controller.

- [ ] **Step: Commit** (end the message with the attribution lines the session specifies).

```bash
git add -A
git commit -m "docs: M6-e citations reworded now that the headless window is adopted"
```

## Self-Review

1. **Spec coverage.** Scope (1): no fake exists, so `AppWindow` on `TestApp`/`TestWindow` is the adoption and there is nothing to delete (Task 1 says so in the gap entry); the one thing the harness cannot do for this app (a `MetalView` draw, so no window size) is recorded as a limit with an app-side fix, not as a gap (D1). M6-e's own named routes: Task 5 (F, + and − by surface, the Edit menu and chords, the palette's key context), with M6-11 left to a person and said so. (2) CT-c: Tasks 3 and 4, with the human checks edited in Task 4, including Undo (CT-8, D2), the viewport press and the title-bar drag. (3) TH-a: Task 6, through `MenuEvaluation` and `TestApp.menuBar`. (4) M7-b: Task 7, counts only; the guide's stable facts (idle draws nothing, warm frame uploads/rasterizes nothing) are pinned, and zero layout work is *not* because the harness shows a forced redraw re-measures (PERF-b). (5) Other M6-e-only entries: the C10 paragraph and its human checks C10-2 and C10-4 (Task 8) and CM-a's open question (Task 4); S5-b is not M6-e-only (it wants `clickCount`, C16) and the spinner is not feasible (stated). Every other citation of M6-e or "no headless window" in the human checks and the code comments is triaged in Tasks 4, 5, 8 and 9. (6) Task 2, with the type name corrected to `Modifiers.primary`. The gaps file: every adopted entry and its summary row are edited (Tasks 1, 4, 5, 6, 7), M4-a's stale row is corrected (Task 1); no gap is added.
2. **Placeholder scan.** No TBD, no "similar to", every step has its code or its exact command; the edit scripts quote the exact anchors and stop on a mismatch.
3. **Type consistency.** `AppWindow` members used in Tasks 3 to 8 (`open(_:dock:zoom:recordsLayout:)`, `centre(ofComment:)`, `titleBarCentre(ofFrame:)`, `point(inCanvas:)`, `point(inCanvasView:)`, `windowPoint(_:)`, `inspectorColumnStart`, `redraw()`, `editor`, `model`, `window`, `testApp`, `themeEditor`, `size`) are defined in Task 1 or the task that first needs them (Task 5 uses only helpers from Tasks 1, 3 and 4); `TypingFixture` members (`note`, `otherNote`, `box`, `rectangle`, `graph`) match their uses. The final total, 2689, is from a real full run of the whole plan applied in a scratch copy (11 run lines, no issue, `swiftlint --strict` clean); the totals after each task (2641, 2642, 2653, 2666, 2675, 2681, 2685) are master plus the running sum of the tasks' test counts, and each task's own suite counts were run.
4. **Review Focus.** Each line has a named test in Tasks 3, 4, 5, 7 and 8.

## Execution

Nine small tasks that share one support type; Tasks 3, 4, 5 and 8 depend on Task 1's helpers (and Task 5 on Task 4's `inspectorColumnStart`), and the order matters for the helper insertions. Recommended: **native** (one session does all of them in order, then one fresh reviewer checks the branch), because the tasks are tests and docs around one fixture and no shipped behaviour changes except one constant and a doc comment.
