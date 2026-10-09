# MetalCreator Editor Polish: Floating Palette and Node Library — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the add-node palette (Tab/Space) a window-level overlay that opens at the pointer and is always fully visible, and add a persistent, searchable node library ("Nodes") to the graph panel from which a type is added by a click or by dragging it onto the canvas.

**Architecture:**
- **Geometry is computed, and the host says where the panel is.** MetalUI measures nothing (gap M4-a), so the graph panel's insides are laid out to computed numbers (`GraphPanelLayout`: glass padding, a fixed-height header, then the body: library and canvas), the palette has a fixed computed size (`PaletteLayout`), and the host tells the editor where the panel is in its window through one closure, `EditorModel.placement: (@MainActor () -> PanelPlacement?)?`. The app answers from `AppLayout.graphPanelFrame` and the viewport's recorded draw size (the viewport fills the window); `GraphPanelPreview` answers from `PreviewLayout`, its window kept at one size. From that the editor knows the canvas's frame in window points (`canvasFrameInWindow`), turns the canvas-local pointer into window points, and finds the visible canvas's centre.
- **The palette floats.** `SearchPaletteView` leaves `GraphCanvas`. A new public `SearchPaletteOverlay` is drawn last in the window's root `ZStack` (the app wraps it in `PaletteDock` for the `Panel` key context; the preview adds it to `PreviewRoot`). `EditorModel.openPalette()` places it once, with `PalettePlacement` (top-left at the pointer, flipped left/up at the window's right/bottom edge, clamped as a last resort), in `SearchPaletteState.windowOrigin`; the node still lands at the canvas point in `screenPosition`. The palette shows ten rows (`firstVisible` scrolls them for ↑/↓) and a caption, so its size never changes. A press outside it closes it (`Window.onInput`'s `.mouseDown` → `EditorModel.windowPressed(at:)`); a transparent backdrop keeps presses on its glass from reaching what lies beneath.
- **The library is model first.** `ViewState.showsLibrary` (default true, an optional key: no format bump) holds its visibility; `EditorModel+Library` holds the search (`PaletteSearch`, the palette's), the grouping (`LibrarySection`), the hover summary (`NodeTypeSummary`), click-to-add at the visible centre (or the nearest free spot in view), drop-to-add at a canvas point, and the row's drag (`LibraryDrag`: a click under 10 pt, else a drag released on the canvas or not), each add one undo step. The views are thin: `GraphPanelBody` places `NodeLibraryView` (captioned "Nodes") as a column (docked at the bottom) or a strip (docked left); its rows are one windowed MetalUI `List` of `LibraryItem`s, each type a `PaletteEntryLabel` with `.help(_:)` (MetalUI's tooltip) under one `DragGesture(minimumDistance: 0, coordinateSpace: .global)` (`GraphPanelInput.libraryGesture(for:)`), and `LibraryDragOverlay`, drawn over the window beside the palette, draws the dragged row at the pointer. No system drag and drop.

**Tech Stack:** Swift 6.4 toolchain, Swift 6 language mode, SwiftPM, Swift Testing, MetalUI (`../MetalUI`, by path, master `c62d6ba`: C7, `feat/input-apis`), OpenCascade 7.9 (Homebrew) through `CreatorOCCT` (untouched here).

**Spec:** `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` — §3.2 (model/view split), §4.5 (files and format versions), §6.1 (window layout), §6.2 (graph panel, the palette "at the cursor"), §6.6 (themes; category header colours), §9 (MetalUI gaps), and every Errata section (M5: the palette's keys and Tab; M6: themes, key contexts). The user-approved design for this milestone (2026-10-08) is quoted in "Decisions" below; Task 5 records it as Errata (editor polish).

**Verified against master `d48d757` (901 tests) and MetalUI master `c62d6ba`** (C7 merged: `CoordinateSpace.global`, `DragGesture(coordinateSpace:)`, `.onScrollWheel`, `SpatialTapGesture`, the rewritten `Window` dispatch; the first draft was checked at `dc6528c`, which lacks the first three). Every code block below was applied in order, task by task, to a copy of master (with `../MetalUI` a link to the real checkout). Before each task's implementation the tests were built and failed as the plan says; after each task the package built with no new warnings (only the expected OCCT "built for newer macOS" linker notes and M4's `'underPointer' mutated after capture by sendable closure` warning in `ContextMenuTests`), the whole `swift test` passed, and `swiftlint lint --strict` reported zero violations. Cumulative test counts (Swift Testing counts a parameterized test once): Task 1 **907** (master + 6), Task 2 **920** (+19), Task 3 **937** (+36), Task 4 **947** (+46), Task 5 **947** (+46). `swift build --product MetalCreatorApp` and `--product GraphPanelPreview` succeed from the replayed copy after Task 4. (This revision did not launch them; the first draft's replay launched both for 10 s without an error.)

**Prerequisites:**
- Branch `editor-polish` off master `d48d757` (this worktree, `/Users/maxburger/Developer/MetalCreator-polish`); run every command from it. Never edit `Package.swift`'s `../MetalUI` path.
- `../MetalUI` at master `c62d6ba` or later (C7, `feat/input-apis`: Tasks 2 and 4 use `DragGesture(minimumDistance:coordinateSpace:)` with `.global`, `.onScrollWheel(perform:)` and `InputEvent.otherMouseDown`). It also has `.help(_:)` tooltips (`MN-P`), `List(_:rowHeight:row:)` windowing, `Window.onInput` seeing every unclaimed press (`dispatchGestures` never claims a `.mouseDown`), `keyContext`, `Stack`.
- SwiftLint installed. `git status --short` prints nothing.

## Decisions made in this plan

1. **Drag from the library is a `DragGesture` inside the window, as approved; no drag and drop.** Each type's row carries one gesture, `GraphPanelInput.libraryGesture(for:)`: `DragGesture(minimumDistance: 0, coordinateSpace: .global)` (C7), whose values are window content points. The model tells a click from a drag: `EditorModel.moveLibraryDrag(_:from:to:)` records a `LibraryDrag` only once the pointer is `LibraryDrag.threshold` (10 pt, the default `DragGesture` minimum) from the press, and `LibraryDragOverlay`, drawn over the window beside `SearchPaletteOverlay`, then draws a flat copy of the row with its top-left corner at the pointer; `endLibraryDrag(_:from:at:)` takes a shorter press as a click (added at the visible centre) and otherwise adds the type at `release − canvasFrameInWindow.origin` when the release is on the canvas (Task 1's placement; the library, the viewport, the inspector and outside the window add nothing, and so does a release before the host has placed the panel). No row frame is needed, so gap EP-a doesn't stand in the way. Considered and rejected: MetalUI's `draggable(_:)` / `dropDestination(for:action:isTargeted:)` (rulings `DN-*`). A draggable that leaves the window becomes an AppKit `NSDraggingSession` (divergence 101), the system drag the design ruled out; and it starts on the first move of more than 0 pt with no slop and outranks a click (`DN-D`, `Gesture.swift`'s `.draggable` arm), so a trackpad click's sub-point jitter would become a drag that drops nowhere. The row isn't a `Button` with a drag around it either: in MetalUI, as in SwiftUI, a child's click holds off an enclosing drag for the whole press (`IX-D` item 3, MetalUI's `aChildsOnClickHoldsOffAParentsDragWhichReportsNothing`). So it is a `PaletteEntryLabel` (the palette row's content, split out of `PaletteEntryRow`) under the one gesture. Cost: library rows aren't keyboard-focusable; the search field, the palette (Tab/Space) and the header's Add stay the keyboard ways to add. No gap is logged: MetalUI's gestures cover it.
2. **Hover help is MetalUI's tooltip.** MetalUI has `.help(_:)` (`MN-P`: shown after the pointer rests 1.0 s, flipped and clamped in the window). Each library row's help is `NodeTypeSummary.text`: "Extrude: profile, distance, mode, reversed → solid" (every input socket, then every output, labelled as the inspector labels them, lowercased; "no inputs" for Graph Parameter). No footer line and no gap.
3. **Where the library goes.** Docked at the bottom (the graph flows right; the panel is wide and short): a 176-pt column at the canvas's left edge. Docked left (the graph flows down; the panel is narrow and tall): a 176-pt strip across the canvas's top. It always sits on the side the graph flows *from*, across the panel's short axis, so it takes the room the panel has most of and leaves the canvas its long axis. The same view fills either frame; its list scrolls. `GraphPanelLayout.libraryFrame` and `canvasFrame(inPanelOf:flow:showsLibrary:)` compute both.
4. **No format bump for `showsLibrary`.** CLAUDE.md: bump `GraphFile.currentFormatVersion` only for "any change older readers can't decode". `ViewState` decodes every key with `decodeIfPresent` from a keyed container, and Swift's keyed decoding ignores keys a type doesn't name, so a format-3 build opens a file with `showsLibrary` (and drops the key if it re-saves, which only re-shows the library). New builds read files without the key as shown. Task 3 pins both directions (`anOlderReaderStillDecodesTheViewState` decodes with a copy of master's decoder) and that the version stays 3. Toggling it is a view change like the dock: saved with the file, not an edit, not undoable.
5. **Window coordinates come from the host, through one closure.** Considered and rejected: tracking the window pointer from `Window.onInput`'s `.mouseMoved` (exact for the pointer, but it still gives neither the window's size, needed to flip, nor the canvas's size, needed for "visible centre"). One mechanism covers all three: computed panel insides plus `EditorModel.placement`. The closure is asked when needed (opening the palette, a library click), never stored or observed, so a dock change, a panel resize or a window resize is always current and nothing rebuilds when the pointer moves. The app reads the window's size from `ViewportModel.viewSize` (made `public internal(set)`; the viewport fills the window and records its size in each draw, gap M4-a). Before the first draw there is no placement and the palette opens at the canvas-local point. `GraphPanelPreview`'s window keeps one size (`minSize == maxSize`), and `PreviewRoot` now pins the bottom dock to the window's bottom with a `Spacer`, so `PreviewLayout` is exact.
6. **The palette has one size, chosen at open.** It shows `PaletteLayout.visibleRows` (10) rows and a caption ("No matching nodes", or "16 more: keep typing, or ↑ ↓"); ↑/↓ scroll the rows to keep the highlight in view (`SearchPaletteState.firstVisible`). Its placement is computed once, at open, from that fixed size, so typing never makes it jump or flip. Today's palette lists every match (26 for the built-ins, about 600 pt), which could never be fully visible in a small window. The wheel doesn't scroll it; a `ScrollView` with `ScrollViewReader` could, but the model-side window is testable and enough for a keyboard-first palette.
7. **"A click outside closes it".** `GraphPanelInput.handle(_:)` reads every press of any button that reaches `Window.onInput` (`.mouseDown`, `.rightMouseDown`, `.otherMouseDown`; MetalUI claims a primary press only in a text field or on a slider) and calls `EditorModel.windowPressed(at:)`, which closes the palette when the press is outside `paletteFrame`. The press goes on, so the click outside also does what it would have done (as MetalUI's own popovers do, `MN-N` P4a). A transparent backdrop with an empty `DragGesture` and a claiming `.onScrollWheel` sits under the palette's glass, so a press or a scroll on its padding or caption doesn't reach (and pan, scroll, or close via) the canvas, the inspector or the viewport beneath. Known limits (gap EP-b): a press into an inspector field or onto a slider, and a right-click that opens the viewport's context menu, are claimed before `onInput` and don't close it; Escape or any other press does. A pinch over the palette reaches what is under it, where nothing takes a pinch yet (the canvas zooms with keys and buttons, gap 2). MetalUI's `.popover` dismisses itself but draws its own chrome and shadow and anchors to an element's edge, not a point.
8. **The palette keeps its key context.** It moved out of `GraphDock`, which contributes `AppKeyContext.panel` so the viewport's F, + and − type into a focused panel field. `PaletteDock` (a `Stack { … }.keyContext(AppKeyContext.panel)`, like `GraphDock` and `InspectorDock`) restores it. Only a real window can show the focus chain (gap M6-e): human check EP-2.
9. **Reuse.** The library searches with `PaletteSearch` (prefix matches first, then category and name) and groups the result by category without re-sorting (`LibrarySection.grouping`); its type rows show the palette row's content (`PaletteEntryLabel`, split out of `PaletteEntryRow` in Task 4), and the drag ghost reuses it; its headers use `Palette.header(for:)` and `textOnAccent`, the node headers' colours, in the current theme.
10. **Adding from the library.** A click adds the type centred in the visible canvas (`visibleCanvasCentre`: half `visibleCanvasSize`, the placed canvas's size, else `GraphPanelLayout.fallbackCanvasSize`). If that overlaps a node it goes to the nearest origin on a (24, 24) display-point grid (the paste offset), scanned ring by ring outward (at most 40 rings), whose frame lies wholly inside the visible canvas and meets no node's frame; when none does it is centred anyway, so a clicked type always lands in view. A drop adds it with its top-left corner at the drop point, as the palette does at the pointer. Each is one `DocumentModel.perform(.addNode(_:))`, so one undo step, and selects the new node; nodes are made only with `NodeRegistry.makeNode`. The library's search text is not saved.
11. **Cheap for MetalUI's whole-window rebuild** (PERF-b). The library's rows are one flat `List(_:rowHeight:row:)` of `LibraryItem`s (headers and types, all 22 pt), so after the first frame MetalUI builds only the rows in view; fills are flat (no shadow, no path: `theLibraryRasterizesNothing`), and rows are keyed by type ID or `header.<category>`. Measured headless on the first draft's rows (a `Button` with `.draggable`; not re-measured for the label under one gesture, which carries fewer modifiers) (a cold frame, every row built, 26 built-in types, 1376 × 300 panel): the library adds about 3.5 ms in release and 14 ms in debug to a frame; a warm frame builds only the 6–10 rows in view. While a type is dragged the ghost moves with each pointer event, which rebuilds the window as a node drag does (PERF-b); a click's jitter under the threshold writes nothing. The library reads only the registry and its own query, never the graph.
12. **The header is fixed at 28 pt and the canvas origin is pinned.** `GraphPanelHeader` is framed to `GraphPanelLayout.headerHeight`; a render test draws a node at the canvas origin and finds its body exactly at `canvasFrame`'s origin, with and without the library, in both docks (it fails if the frame is removed).
13. **The library is captioned "Nodes".** The design names it "Nodes", so a 16-pt "Nodes" caption (the palette's caption height) heads the column or strip, above the "Search nodes" field; the list gives up the height (docked left, the 176-pt strip still shows five 22-pt rows). The header button stays "Library", as approved.

## Global Constraints

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`, `platforms: [.macOS(.v26)]`; strict concurrency, data races are errors. No `@unchecked Sendable`, no `nonisolated(unsafe)`.
- Tests use **Swift Testing** only (`import Testing`, `@Test`, `#expect`, `#require`).
- `@MainActor @Observable` models hold all behaviour (`EditorModel`, `AppModel`); views are thin MetalUI `Component`s.
- One type per Swift file, named after the type; extensions in `Type+Purpose.swift`. Test fixture files may hold several helpers and say so in a header comment.
- No force unwraps or force `try`. No GCD. No third-party packages.
- Module boundaries (CLAUDE.md): `CreatorEditor` never imports `CreatorNodes` (its tests may); only `CreatorApp` joins Graph, Nodes, Viewport and Editor; `CreatorViewport` never imports `CreatorGraph`.
- Create nodes only with `NodeRegistry.makeNode`; every graph edit goes through `DocumentModel.perform`.
- Colours only from the current theme's roles through `Palette(themes)`; no hex outside `CreatorStyle`; fonts are MetalUI's semantic styles. No glow, no shadows.
- Editor geometry is computed, never measured: `NodeLayout`, and now `GraphPanelLayout` and `PaletteLayout`; views are framed to them.
- MetalUI gaps are logged in `docs/metalui-gaps.md` and never worked around in a way that would have to be undone; graph-panel input stopgaps live only in `GraphPanelInput`.
- `GraphFile.currentFormatVersion` changes only when older readers can't decode (it stays 3 here).
- **SwiftLint gates every commit**: `swiftlint lint --strict` must report zero violations.
- Every commit message ends with a blank line, then the implementing model's harness-provided `Co-Authored-By:` and `Claude-Session:` lines.
- Expected build noise: OCCT dylib "built for newer macOS version" linker warnings, and M4's `'underPointer' mutated after capture by sendable closure` in `ContextMenuTests`.

## Review Focus

Inputs and conditions the design implies, that a person meets in the first minutes, and that fail quietly unless pinned.

1. **Opening the palette where it can't fit.** Docked at the bottom (the canvas is near the window's bottom), near the right edge under the inspector, or in a small window, the palette must still be fully visible, flipped up or left, never cut off, and the node must still land under the pointer where Tab was pressed, not at the flipped corner. *Task 2: `itFlipsUpAtTheBottomEdge`, `itFlipsLeftAtTheRightEdge`, `itFlipsBothWaysInTheBottomRightCorner`, `itIsClampedWhenNeitherSideFits`, `atTheBottomDockItFlipsUpAndAddsAtThePressPoint`.*
2. **Typing into the floating palette.** Its field must keep F, + and − (the palette left the graph panel's `Panel` key context), and typing must not resize or move it. *Task 2: `thePaletteIsAFixedSize`, `theRowsScrollToKeepTheHighlightInView`; the focus chain needs a real window (gap M6-e): human check EP-2.*
3. **Pressing near the palette.** A press or a scroll on its glass padding must neither close it nor pan or scroll what lies beneath; a press of any button anywhere outside must close it and still reach what it landed on. *Task 2: `aPressOutsideClosesItAndOneInsideDoesNot`, `theWindowsPressesReachThePaletteUnclaimed` (primary, right and middle buttons), `thePaletteIsPaintedOverEverythingWhereItWasPlaced`; the backdrop's catch of presses and the wheel, and the right-click on the viewport's menu (EP-b), are human check EP-3.*
4. **Clicking versus dragging a library row.** A trackpad click that jitters a few points must still add at the visible centre, never start a drag; a drag released off the canvas (over the library itself, the viewport, the inspector, outside the window) must add nothing; one released on the canvas must land at the release point in either dock; an unregistered type adds nothing. *Task 3: `aClickThatMovesUnderTheThresholdStillAddsAtTheCentre`, `aReleaseOffTheCanvasAddsNothing`, `aReleaseOnTheCanvasAddsTheTypeThereAsOneStep`, `withoutAPlacementOrARegisteredTypeNothingIsAdded`; Task 4: `aRowsGestureIsAZeroDistanceDragInWindowPoints`; the drag itself in a real window is human check EP-6.*
5. **Adding from the library into a busy or moved canvas.** Panned, zoomed, docked left (transposed), or onto existing nodes, a clicked type must appear in view and overlap nothing, as one undo step. *Task 3: `aClickAddsTheTypeCentredInTheVisibleCanvasAsOneStep`, `aClickedTypeIsNudgedOffTheNodesAlreadyThere`, `aClickedTypeStaysInViewWhenTheCentreIsCrowded`, `dockedLeftItIsCentredOnScreenToo`; Task 4: `theHostPlacesTheCanvasInTheWindow` (the centre beside the library).*

---

## File Structure

| File | Task | Responsibility |
|---|---|---|
| `Sources/CreatorEditor/GraphPanelLayout.swift` | 1, 4 | The panel's computed insides: glass padding, header, body; library and canvas frames per flow |
| `Sources/CreatorEditor/PanelPlacement.swift` | 1 | The panel's frame and the window's size, as the host reports them |
| `Sources/CreatorEditor/EditorModel+Placement.swift` | 1, 4 | `panelPlacement`, `canvasFrameInWindow`, `windowPoint(fromCanvas:)` |
| `Sources/CreatorEditor/EditorModel.swift` | 1, 3 | Gains `placement` (closure) and `libraryQuery` |
| `Sources/CreatorEditor/GlassPanel.swift`, `GraphPanel.swift` | 1, 4 | Framed to `GraphPanelLayout`; the panel shows `GraphPanelBody` |
| `Sources/CreatorViewport/Model/ViewportModel.swift` | 1 | `viewSize` readable by the app |
| `Sources/CreatorApp/AppLayout.swift`, `AppModel+Placement.swift`, `AppModel.swift` | 1 | `graphPanelFrame`; the app's placement; wired on every New/Open |
| `Sources/GraphPanelPreview/PreviewLayout.swift`, `PreviewRoot.swift`, `main.swift`, `Double+Pixels.swift` | 1, 2, 4 | The preview's fixed window and placement; its palette overlay |
| `Sources/CreatorEditor/PaletteLayout.swift`, `PalettePlacement.swift` | 2 | The palette's fixed size; where it goes in the window |
| `Sources/CreatorEditor/SearchPaletteState.swift`, `EditorModel+Palette.swift` | 2 | `windowOrigin`, `firstVisible`; open, visible rows, outside press |
| `Sources/CreatorEditor/SearchPaletteView.swift`, `SearchPaletteOverlay.swift`, `PaletteEntryRow.swift` | 2, 4 | The fixed-size palette; the window-level overlay; rows framed to `rowHeight` (Task 4 splits out `PaletteEntryLabel`) |
| `Sources/CreatorEditor/GraphCanvas.swift`, `GraphPanelInput.swift` | 2, 4 | No palette in the canvas; outside press of any button; the library row's gesture |
| `Sources/CreatorApp/PaletteDock.swift`, `AppRoot.swift` | 2, 4 | The palette drawn last, in the `Panel` key context; then the library's drag ghost |
| `Sources/CreatorGraph/ViewState.swift` | 3 | `showsLibrary` |
| `Sources/CreatorEditor/LibrarySection.swift`, `NodeTypeSummary.swift`, `LibraryDrag.swift`, `EditorModel+Library.swift`, `EditorModel+Editing.swift` | 3 | Library model: sections, summary, add at centre (nudged, in view), drop at a point, a row's click or drag |
| `Sources/CreatorEditor/GraphPanelBody.swift`, `NodeLibraryView.swift`, `LibraryItem.swift`, `LibraryRow.swift`, `LibrarySectionHeader.swift`, `PaletteEntryLabel.swift`, `LibraryDragOverlay.swift`, `GraphPanelHeader.swift` | 4 | Library views, its flat row list, the shared row label, the drag ghost, Library button |
| Tests (`CreatorEditorTests`, `CreatorAppTests`, `CreatorGraphTests`) | 1–4 | See each task |
| `docs/metalui-gaps.md`, `docs/verification/human-checks.md`, spec Errata, `CLAUDE.md`, `docs/superpowers/roadmap.md` | 5 | Gaps EP-a, EP-b; group EP; Errata (editor polish); project notes |

How to read the code steps: **Create** / **Replace the whole of** give a file's complete contents; **In `file`, replace: … with: …** is an exact text replacement (the first block occurs once in the file); **Append to** adds the block at the end of the file.

---

### Task 1: The panel's geometry is computed, and the host says where the panel is

Decisions 5 and 12. Nothing visible changes yet: the header gets a fixed height, the preview's window keeps one size, and the editor can now tell where its canvas is in the window, which Tasks 2–4 use.

**Files:**
- Create: `Sources/CreatorEditor/GraphPanelLayout.swift`, `Sources/CreatorEditor/PanelPlacement.swift`, `Sources/CreatorEditor/EditorModel+Placement.swift`, `Sources/CreatorApp/AppModel+Placement.swift`, `Sources/GraphPanelPreview/PreviewLayout.swift`, `Sources/GraphPanelPreview/Double+Pixels.swift`
- Modify: `Sources/CreatorEditor/EditorModel.swift`, `Sources/CreatorEditor/GlassPanel.swift`, `Sources/CreatorEditor/GraphPanel.swift`, `Sources/CreatorViewport/Model/ViewportModel.swift`, `Sources/CreatorApp/AppLayout.swift`, `Sources/CreatorApp/AppModel.swift`, `Sources/GraphPanelPreview/PreviewRoot.swift`, `Sources/GraphPanelPreview/main.swift`
- Test: `Tests/CreatorEditorTests/PanelPlacementTests.swift`, `Tests/CreatorAppTests/PanelPlacementTests.swift`

**Interfaces:**
- Consumes: `CanvasRect` (`origin`, `size`, `maxX`, `maxY`, `contains`, `intersects`, `init(corner:_:)`), `Vector2`, `EditorModel.isPanelVisible`, `AppLayout.margin`/`topBarHeight`, `AppModel.panelWidth`/`panelHeight`, `ViewportModel.recordViewSize(_:)` (internal; tests use `@testable import CreatorViewport`).
- Produces: `GraphPanelLayout.glassPadding` (10), `.headerHeight` (28), `.spacing` (8), `.fallbackCanvasSize` (400 × 300), `.canvasFrame(inPanelOf: Vector2) -> CanvasRect` (Task 4 replaces it); `PanelPlacement(window: Vector2, panel: CanvasRect)`; `EditorModel.placement: (@MainActor () -> PanelPlacement?)?`, `.panelPlacement: PanelPlacement?`, `.canvasFrameInWindow: CanvasRect?`, `.windowPoint(fromCanvas: Vector2) -> Vector2?`; `ViewportModel.viewSize` (`public internal(set)`); `AppLayout.graphPanelFrame(dock:panelWidth:panelHeight:window:) -> CanvasRect?`; `AppModel.panelPlacement: PanelPlacement?`, `.panelPlacement(inWindowOf: Vector2) -> PanelPlacement?`; `PreviewLayout.window`, `.placement(_ dock: DockSide) -> PanelPlacement?`.

- [ ] **Step 1: Write the failing tests**

**Create `Tests/CreatorEditorTests/PanelPlacementTests.swift`:**
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// The panel's geometry is computed (`GraphPanelLayout`), and the host says where the panel is in its window
/// (`EditorModel.placement`), so the editor knows where its canvas is without measuring anything (gap M4-a).
@MainActor
struct PanelPlacementTests {
    @Test func theCanvasSitsUnderTheHeaderInsideTheGlass() {
        let frame = GraphPanelLayout.canvasFrame(inPanelOf: Vector2(400, 300))
        #expect(frame.origin == Vector2(10, 46))
        #expect(frame.size == Vector2(380, 244))
        #expect(GraphPanelLayout.canvasFrame(inPanelOf: Vector2(10, 10)).size == .zero, "never negative")
    }

    @Test func theHostPlacesTheCanvasInTheWindow() {
        let editor = makeEditor([], dock: .bottom)
        #expect(editor.canvasFrameInWindow == nil, "no host, no window coordinates")
        let panel = CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300))
        editor.placement = { PanelPlacement(window: Vector2(1000, 700), panel: panel) }
        #expect(editor.canvasFrameInWindow == CanvasRect(origin: Vector2(22, 434), size: Vector2(956, 244)))
        #expect(editor.windowPoint(fromCanvas: Vector2(5, 6)) == Vector2(27, 440))
        editor.setDock(.hidden)
        #expect(editor.canvasFrameInWindow == nil, "a hidden panel has no canvas")
    }

    /// The header is framed to `GraphPanelLayout.headerHeight`, so the canvas starts where the layout says: a node
    /// at the canvas origin, unpanned and unzoomed, is drawn at `canvasFrame`'s origin.
    @Test(arguments: [DockSide.left, .bottom])
    func aNodeAtTheCanvasOriginIsDrawnWhereTheLayoutPutsTheCanvas(_ dock: DockSide) {
        let editor = makeEditor([testNode(NumberTestNode.self, id: 1, at: .zero)], dock: dock)
        let input = GraphPanelInput(model: editor)
        let scene = renderHeadless { GraphPanel(model: editor, input: input) }
        let scale = 2.0
        let origin = GraphPanelLayout.canvasFrame(inPanelOf: Vector2(900, 600)).origin
        let body = scene.rects.contains { rect in
            abs(Double(rect.bounds.origin.x) / scale - origin.x) < 0.5
                && abs(Double(rect.bounds.origin.y) / scale - origin.y) < 0.5
                && abs(Double(rect.bounds.size.width) / scale - NodeLayout.width) < 0.5
        }
        #expect(body, "no node drawn at \(origin)")
    }
}
```
**Create `Tests/CreatorAppTests/PanelPlacementTests.swift`:**
```swift
import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import MetalUIText
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// The app tells the editor where the graph panel is in the window (`AppLayout.graphPanelFrame`, the window's
/// size from the viewport, which fills it), and draws the panel exactly there.
@MainActor
struct PanelPlacementTests {
    let window = Vector2(1400, 900)

    @Test(arguments: [DockSide.left, .bottom])
    func thePanelIsDrawnWhereTheLayoutSays(_ dock: DockSide) async throws {
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: Graph(), viewState: ViewState(dock: dock)))
        await app.settle()
        let frame = try #require(AppLayout.graphPanelFrame(dock: dock, panelWidth: app.panelWidth,
                                                           panelHeight: app.panelHeight, window: window))
        let input = AppInput(model: app)
        let scene = renderFrame({ ZStack { AppRoot(model: app, input: input) } },
                                size: Size(width: Pixels(1400), height: Pixels(900)), scaleFactor: 2,
                                textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        let scale = 2.0
        let drawn = scene.rects.contains { rect in
            abs(Double(rect.bounds.origin.x) / scale - frame.origin.x) < 1
                && abs(Double(rect.bounds.origin.y) / scale - frame.origin.y) < 1
                && abs(Double(rect.bounds.size.width) / scale - frame.size.x) < 1
                && abs(Double(rect.bounds.size.height) / scale - frame.size.y) < 1
        }
        #expect(drawn, "no glass rect at \(frame)")
    }

    @Test func theEditorIsToldWhereItsCanvasIs() async throws {
        let app = await makeApp()
        #expect(app.editor.panelPlacement == nil, "the window has no size before the viewport's first draw")
        app.viewport.recordViewSize(ViewportSize(width: window.x, height: window.y))
        let panel = try #require(AppLayout.graphPanelFrame(dock: .left, panelWidth: app.panelWidth,
                                                           panelHeight: app.panelHeight, window: window))
        #expect(app.editor.panelPlacement == PanelPlacement(window: window, panel: panel))
        #expect(app.editor.canvasFrameInWindow?.origin == panel.origin + Vector2(10, 46))
        app.editor.setDock(.bottom)
        #expect(app.editor.panelPlacement?.panel.origin == Vector2(12, 900 - 12 - app.panelHeight))
    }

    @Test func aNewDocumentIsPlacedToo() async {
        let app = await makeApp()
        app.load(GraphFile(), from: nil)
        app.viewport.recordViewSize(ViewportSize(width: window.x, height: window.y))
        #expect(app.editor.panelPlacement != nil)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | sort -u | head`
Expected: FAIL — among the errors: `cannot find 'GraphPanelLayout' in scope`, `cannot find 'PanelPlacement' in scope`, `value of type 'EditorModel' has no member 'placement'`, `… has no member 'canvasFrameInWindow'`, `… has no member 'windowPoint'`.

- [ ] **Step 3: Compute the panel's geometry in the editor**

**Create `Sources/CreatorEditor/GraphPanelLayout.swift`:**
```swift
import CreatorGeometry

/// The graph panel's own geometry, computed rather than measured (MetalUI has no geometry reader:
/// docs/metalui-gaps.md M4-a, EP-a), so the editor can tell where its canvas is in the window. `GlassPanel`,
/// `GraphPanel` and `GraphPanelHeader` are framed to these numbers, as nodes are framed to `NodeLayout`.
public enum GraphPanelLayout {
    /// The glass chrome's inset around its content (`GlassPanel`).
    public static let glassPadding = 10.0
    /// The header row (title and buttons).
    public static let headerHeight = 28.0
    /// Between the header and the canvas.
    public static let spacing = 8.0
    /// The canvas size assumed while the host hasn't placed the panel (headless tests): the centre of a small panel.
    public static let fallbackCanvasSize = Vector2(400, 300)

    /// The canvas's frame inside a panel of `size`, in panel-local points. It runs to the panel's padding; a
    /// refusal message showing under the canvas takes one line from its bottom.
    public static func canvasFrame(inPanelOf size: Vector2) -> CanvasRect {
        let origin = Vector2(glassPadding, glassPadding + headerHeight + spacing)
        return CanvasRect(origin: origin, size: Vector2(max(0, size.x - 2 * glassPadding),
                                                        max(0, size.y - origin.y - glassPadding)))
    }
}
```
**Create `Sources/CreatorEditor/PanelPlacement.swift`:**
```swift
import CreatorGeometry

/// Where the host lays the graph panel out in its window (MetalUI can't measure it: docs/metalui-gaps.md M4-a,
/// EP-a). `EditorModel.placement` asks for it when it needs window coordinates: to float the add-node palette over
/// the window, and to find the visible canvas's centre.
public struct PanelPlacement: Equatable, Sendable {
    /// The window's content size, in points.
    public var window: Vector2
    /// The panel's frame, in window points.
    public var panel: CanvasRect

    public init(window: Vector2, panel: CanvasRect) {
        self.window = window
        self.panel = panel
    }
}
```
**Create `Sources/CreatorEditor/EditorModel+Placement.swift`:**
```swift
import CreatorGeometry

extension EditorModel {
    /// The panel's placement in its window, from the host; `nil` without a host (headless tests) or before the
    /// window has a size.
    public var panelPlacement: PanelPlacement? { placement?() }

    /// The canvas's frame in window points; `nil` while the panel is hidden or not placed.
    public var canvasFrameInWindow: CanvasRect? {
        guard isPanelVisible, let placement = panelPlacement else { return nil }
        let local = GraphPanelLayout.canvasFrame(inPanelOf: placement.panel.size)
        return CanvasRect(origin: placement.panel.origin + local.origin, size: local.size)
    }

    /// A canvas-local screen point (`pointerLocation`, a press) in window points, or `nil` while unplaced.
    public func windowPoint(fromCanvas point: Vector2) -> Vector2? {
        canvasFrameInWindow.map { $0.origin + point }
    }
}
```
**In `Sources/CreatorEditor/EditorModel.swift`, replace:**
```swift
    /// The last inspector button pressed, for the viewport to act on (M4/M6).
    public private(set) var inspectorRequest: InspectorRequest?
```
**with:**
```swift
    /// The last inspector button pressed, for the viewport to act on (M4/M6).
    public private(set) var inspectorRequest: InspectorRequest?
    /// Where the host lays the panel out in its window (`EditorModel+Placement`). The app shell and
    /// `GraphPanelPreview` set it; it is asked, not stored, so it always reads the current dock and sizes.
    @ObservationIgnored public var placement: (@MainActor () -> PanelPlacement?)?
```
**Replace the whole of `Sources/CreatorEditor/GlassPanel.swift`:**
```swift
import CreatorStyle
import MetalUI

/// Glass chrome for floating panels (spec §6.1, §6.6): the theme's glass fill (`#21222c` at 86% in
/// Dracula), its 1-pt hairline (`#ffffff1f`) and rounded corners. The background blur is a MetalUI
/// gap (materials and `.blur` are not offered; docs/metalui-gaps.md), so the panel is translucent
/// without blur. Public so the app shell's top bar and pick banner (M6) share the chrome.
public struct GlassPanel<Body: ElementGroup>: Component {
    let body: Body
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init(@ElementBuilder _ body: () -> Body) {
        self.body = body()
    }

    public var content: some ElementGroup {
        let palette = Palette(themes)
        let shape = RoundedRectangle(cornerRadius: Pixels(10))
        return ZStack(alignment: .topLeading) { body }
            .padding(Edges(all: GraphPanelLayout.glassPadding.px))
            .background(palette.glass.color, in: shape)
            .overlay { shape.strokeBorder(palette.hairline.color, lineWidth: Pixels(1)) }
    }
}
```
**Replace the whole of `Sources/CreatorEditor/GraphPanel.swift`:**
```swift
import CreatorGraph
import CreatorStyle
import MetalUI

/// The graph panel (spec §6.2): glass chrome, the header and the canvas, with a refusal message
/// along the bottom while one is showing. It is laid out to `GraphPanelLayout`, so the host's
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
        GlassPanel {
            VStack(alignment: .leading, spacing: GraphPanelLayout.spacing.px) {
                GraphPanelHeader(model: model)
                    .frame(height: GraphPanelLayout.headerHeight.px)
                GraphCanvas(model: model, input: input)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let refusal = model.refusal {
                    Text(refusal.message).font(.caption).foregroundStyle(Palette(themes).statusError.color)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Tell the editor where the panel is, in the app and the preview**

**In `Sources/CreatorViewport/Model/ViewportModel.swift`, replace:**
```swift
    /// The view's size in points, recorded by the draw (MetalUI has no size callback: docs/metalui-gaps.md).
    @ObservationIgnored var viewSize = ViewportSize(width: 0, height: 0)
```
**with:**
```swift
    /// The view's size in points, recorded by the draw (MetalUI has no size callback: docs/metalui-gaps.md). The app
    /// shell reads it as the window's size, since the viewport fills the window.
    @ObservationIgnored public internal(set) var viewSize = ViewportSize(width: 0, height: 0)
```
**Replace the whole of `Sources/CreatorApp/AppLayout.swift`:**
```swift
import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorViewport

/// The window's layout numbers (spec §6.1). The views are framed to them, so the model can tell the viewport
/// which part of it the floating panels cover without measuring anything (MetalUI has no geometry reader yet,
/// docs/metalui-gaps.md M4-a).
public enum AppLayout {
    /// Around the window's edge and between panels.
    public static let margin = 12.0
    public static let topBarHeight = 44.0
    /// The inspector's 280-point column plus its glass padding.
    public static let inspectorWidth = 300.0
    /// The "Show graph" button while the panel is hidden.
    public static let showButtonHeight = 44.0
    /// The graph panel's inner-edge resize handle.
    public static let resizeHandle = 8.0
    public static let defaultPanelWidth = 460.0
    public static let defaultPanelHeight = 300.0
    public static let panelWidths: ClosedRange<Double> = 240...900
    public static let panelHeights: ClosedRange<Double> = 160...700
    /// Where "Show Producing Node" puts the node's top-left corner on the canvas, in canvas-local points.
    public static let revealPoint = Vector2(24, 24)

    /// The docked graph panel's frame in a `window`-sized window, in window points (the frame `PanelArea` gives
    /// `GraphDock`); `nil` while it's hidden.
    public static func graphPanelFrame(dock: DockSide, panelWidth: Double, panelHeight: Double, window: Vector2) -> CanvasRect? {
        let top = margin + topBarHeight + margin
        switch dock {
        case .left: return CanvasRect(origin: Vector2(margin, top), size: Vector2(panelWidth, max(0, window.y - top - margin)))
        case .bottom:
            return CanvasRect(origin: Vector2(margin, window.y - margin - panelHeight),
                              size: Vector2(max(0, window.x - 2 * margin), panelHeight))
        case .hidden: return nil
        }
    }

    /// The part of the viewport the panels leave uncovered, for `ViewportModel.setModelArea(_:)`.
    public static func modelArea(dock: DockSide, panelWidth: Double, panelHeight: Double) -> ViewportInsets {
        let top = margin + topBarHeight
        let trailing = margin + inspectorWidth
        switch dock {
        case .left: return ViewportInsets(top: top, leading: margin + panelWidth + resizeHandle, bottom: 0, trailing: trailing)
        case .bottom: return ViewportInsets(top: top, leading: 0, bottom: margin + panelHeight + resizeHandle, trailing: trailing)
        case .hidden: return ViewportInsets(top: top, leading: 0, bottom: margin + showButtonHeight, trailing: trailing)
        }
    }
}
```
**Create `Sources/CreatorApp/AppModel+Placement.swift`:**
```swift
import CreatorEditor
import CreatorGeometry

extension AppModel {
    /// Where the graph panel is in the window, from `AppLayout`'s numbers and the window's size; `nil` before the
    /// viewport's first draw (the window's size is the viewport's, gap M4-a) or while the panel is hidden.
    public var panelPlacement: PanelPlacement? {
        panelPlacement(inWindowOf: Vector2(viewport.viewSize.width, viewport.viewSize.height))
    }

    /// Where the graph panel is in a `window`-sized window.
    public func panelPlacement(inWindowOf window: Vector2) -> PanelPlacement? {
        guard window.isFinite, window.x >= 1, window.y >= 1,
              let panel = AppLayout.graphPanelFrame(dock: editor.dock, panelWidth: panelWidth, panelHeight: panelHeight,
                                                    window: window) else { return nil }
        return PanelPlacement(window: window, panel: panel)
    }
}
```
**In `Sources/CreatorApp/AppModel.swift`, replace:**
```swift
        graphInput.releaseTextFocus = { [weak self] in self?.releaseTextFocus?() }
```
**with:**
```swift
        graphInput.releaseTextFocus = { [weak self] in self?.releaseTextFocus?() }
        editor.placement = { [weak self] in self?.panelPlacement }
```
**Create `Sources/GraphPanelPreview/Double+Pixels.swift`:**
```swift
import MetalUI

extension Double {
    /// This layout length as MetalUI points. Layout numbers are `Double`; MetalUI lengths are `Float`.
    var px: Pixels { Pixels(Float(self)) }
}
```
**Create `Sources/GraphPanelPreview/PreviewLayout.swift`:**
```swift
import CreatorEditor
import CreatorGeometry
import CreatorGraph

/// The preview window's layout numbers. The window keeps one size, so the editor can be told where its panel is
/// (MetalUI has no geometry reader, docs/metalui-gaps.md M4-a, EP-a); `PreviewRoot` is framed to these.
enum PreviewLayout {
    static let window = Vector2(1280, 800)
    static let margin = 12.0
    static let leftPanelWidth = 380.0
    static let bottomPanelHeight = 300.0

    /// The graph panel's frame in the window for `dock`; `nil` while hidden.
    static func placement(_ dock: DockSide) -> PanelPlacement? {
        let panel: CanvasRect
        switch dock {
        case .left:
            panel = CanvasRect(origin: Vector2(margin, margin), size: Vector2(leftPanelWidth, window.y - 2 * margin))
        case .bottom:
            panel = CanvasRect(origin: Vector2(margin, window.y - margin - bottomPanelHeight),
                               size: Vector2(window.x - 2 * margin, bottomPanelHeight))
        case .hidden:
            return nil
        }
        return PanelPlacement(window: window, panel: panel)
    }
}
```
**Replace the whole of `Sources/GraphPanelPreview/PreviewRoot.swift`:**
```swift
import CreatorEditor
import MetalUI

/// The preview window's content: the window background, the graph panel in its dock and the
/// inspector on the right — the layout the app shell (M6) floats over the viewport. It is laid out
/// to `PreviewLayout`, which tells the editor where the panel is.
struct PreviewRoot: Component {
    let model: EditorModel
    let input: GraphPanelInput

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            Palette.dracula.backgroundBottom.color
            switch model.dock {
            case .left:
                HStack(alignment: .top, spacing: PreviewLayout.margin.px) {
                    ZStack { GraphPanel(model: model, input: input) }
                        .frame(width: PreviewLayout.leftPanelWidth.px)
                        .frame(maxHeight: .infinity)
                    Spacer()
                    InspectorPanel(model: model)
                }
                .padding(Edges(all: PreviewLayout.margin.px))
            case .bottom:
                VStack(spacing: PreviewLayout.margin.px) {
                    HStack(alignment: .top) {
                        Spacer()
                        InspectorPanel(model: model)
                    }
                    Spacer()
                    ZStack { GraphPanel(model: model, input: input) }
                        .frame(height: PreviewLayout.bottomPanelHeight.px)
                        .frame(maxWidth: .infinity)
                }
                .padding(Edges(all: PreviewLayout.margin.px))
            case .hidden:
                // Hidden keeps a visible way back: "Show graph" (Tab is its shortcut).
                HStack(alignment: .bottom) {
                    GraphShowButton(model: model)
                    Spacer()
                    InspectorPanel(model: model)
                }
                .padding(Edges(all: PreviewLayout.margin.px))
            }
        }
        .frame(width: PreviewLayout.window.x.px, height: PreviewLayout.window.y.px)
    }
}
```
**Replace the whole of `Sources/GraphPanelPreview/main.swift`:**
```swift
import CreatorEditor
import MetalUI

// `swift run GraphPanelPreview`: the graph panel and inspector over a stand-in document, for the
// human checks in docs/verification/human-checks.md (group M5). `app.run()` is called from
// synchronous top-level code, as MetalUI requires.
@MainActor
func runPreview() throws {
    let app = try App()
    let model = EditorModel(document: PreviewDocument.make())
    let input = GraphPanelInput(model: model)
    let size = Size(width: PreviewLayout.window.x.px, height: PreviewLayout.window.y.px)
    let window = try app.openWindow(title: "MetalCreator — Graph Panel Preview", size: size) {
        ZStack { PreviewRoot(model: model, input: input) }
    }
    // One size, so `PreviewLayout` knows where the panel is (gap M4-a).
    window.minSize = size
    window.maxSize = size
    model.placement = { [weak model] in model.flatMap { PreviewLayout.placement($0.dock) } }
    // Keys through `onInput`, the palette's ↑/↓ as keymap actions (they run before a focused search
    // field claims them), and a canvas press clearing text focus (gap M5-g). `install(on:)` chains
    // onto any handlers already there, as the app shell (M6) needs with the viewport's.
    input.install(on: window)
    app.run()
}

try runPreview()
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter PanelPlacementTests`
Expected: 6 tests pass (3 in `CreatorEditorTests`, 3 in `CreatorAppTests`). Then `swift test`: **907** (master + 6). Check the header test bites: delete the `.frame(height: GraphPanelLayout.headerHeight.px)` line in `GraphPanel.swift`, rerun `swift test --filter CreatorEditorTests.PanelPlacementTests` (it fails, 2 issues), and restore the line. Also `swift build --product GraphPanelPreview` succeeds.

- [ ] **Step 6: Commit**

```bash
swiftlint lint --strict   # must report 0 violations
git add Sources/CreatorEditor/GraphPanelLayout.swift Sources/CreatorEditor/PanelPlacement.swift \
        Sources/CreatorEditor/EditorModel+Placement.swift Sources/CreatorEditor/EditorModel.swift \
        Sources/CreatorEditor/GlassPanel.swift Sources/CreatorEditor/GraphPanel.swift \
        Sources/CreatorViewport/Model/ViewportModel.swift Sources/CreatorApp/AppLayout.swift \
        Sources/CreatorApp/AppModel+Placement.swift Sources/CreatorApp/AppModel.swift \
        Sources/GraphPanelPreview/Double+Pixels.swift Sources/GraphPanelPreview/PreviewLayout.swift \
        Sources/GraphPanelPreview/PreviewRoot.swift Sources/GraphPanelPreview/main.swift \
        Tests/CreatorEditorTests/PanelPlacementTests.swift Tests/CreatorAppTests/PanelPlacementTests.swift
git commit -m "feat(editor): computed panel geometry; the host says where the panel is in its window"
```

---

### Task 2: The add-node palette floats over the window at the pointer

Decisions 6, 7 and 8. The palette leaves the canvas and is drawn last over the whole window, top-left at the pointer, flipped at the window's right and bottom edges, at one fixed size; a press outside closes it.

**Files:**
- Create: `Sources/CreatorEditor/PaletteLayout.swift`, `Sources/CreatorEditor/PalettePlacement.swift`, `Sources/CreatorEditor/SearchPaletteOverlay.swift`, `Sources/CreatorApp/PaletteDock.swift`
- Modify: `Sources/CreatorEditor/SearchPaletteState.swift`, `Sources/CreatorEditor/EditorModel+Palette.swift`, `Sources/CreatorEditor/SearchPaletteView.swift`, `Sources/CreatorEditor/PaletteEntryRow.swift`, `Sources/CreatorEditor/GraphCanvas.swift`, `Sources/CreatorEditor/GraphPanelInput.swift`, `Sources/CreatorApp/AppRoot.swift`, `Sources/GraphPanelPreview/PreviewRoot.swift`
- Test: `Tests/CreatorEditorTests/FloatingPaletteTests.swift`, `Tests/CreatorEditorTests/Support/SceneGeometry.swift`, `Tests/CreatorAppTests/PaletteOverlayTests.swift`, `Tests/CreatorAppTests/Support/SceneOrder.swift`

**Interfaces:**
- Consumes: Task 1's `EditorModel.panelPlacement`, `canvasFrameInWindow`, `windowPoint(fromCanvas:)`, `GraphPanelLayout.glassPadding`, `AppModel.panelPlacement`; `ViewportModel.recordViewSize(_:)`; `PaletteSearch.entries(in:matching:)`; `AppKeyContext.panel`; MetalUI `Scene.drawList` (`DrawRun.kind/start/count`), `MUIRect.contentMask`, `MouseEvent(position:buttonNumber:)`, `InputEvent.mouseDown`/`.rightMouseDown`/`.otherMouseDown`, `.onScrollWheel(perform:)` (C7).
- Produces: `PaletteLayout.contentWidth` (220), `.fieldHeight` (28), `.rowHeight` (22), `.visibleRows` (10), `.captionHeight` (16), `.spacing` (4), `.windowMargin` (8), `.rowsHeight`, `.contentSize`, `.size` (240 × 292); `PalettePlacement.origin(pointer:size:window:margin:) -> Vector2`; `SearchPaletteState.windowOrigin`, `.firstVisible`, `init(screenPosition:windowOrigin:query:highlighted:firstVisible:)`; `EditorModel.paletteFrame: CanvasRect?`, `.windowPressed(at: Vector2)`, `.paletteVisibleEntries: [PaletteEntry]`, `.paletteHiddenCount: Int`; `SearchPaletteOverlay(model:)` (public); `PaletteDock` (app, internal); test helpers `screenFrame(of:in:scale:)` (editor) and `paintPosition(of:at:in:)`, `frame(of:scale:)` (app).

- [ ] **Step 1: Write the failing tests**

**Create `Tests/CreatorEditorTests/Support/SceneGeometry.swift`:**
```swift
// Test fixture file: where a headless frame's primitives land on screen.
import CreatorEditor
import CreatorGeometry
import MetalUI

/// A rect's frame on screen, in points: its bounds through its transform when it has one (ruling GX-F: a
/// transformed primitive's bounds are local; `x' = a x + c y + tx`). Exact for translations, which is all the
/// palette and the canvas's unzoomed layers use.
func screenFrame(of rect: MUIRect, in scene: Scene, scale: Double = 2) -> CanvasRect {
    var x = Double(rect.bounds.origin.x), y = Double(rect.bounds.origin.y)
    let index = Int(rect.shape >> 8)
    if index > 0, scene.transforms.indices.contains(index - 1) {
        let t = scene.transforms[index - 1]
        (x, y) = (Double(t.a) * x + Double(t.c) * y + Double(t.tx), Double(t.b) * x + Double(t.d) * y + Double(t.ty))
    }
    return CanvasRect(origin: Vector2(x / scale, y / scale),
                      size: Vector2(Double(rect.bounds.size.width) / scale, Double(rect.bounds.size.height) / scale))
}
```
**Create `Tests/CreatorEditorTests/FloatingPaletteTests.swift`:**
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import MetalUI
import Testing
@testable import CreatorEditor

/// The add-node palette floats over the window (spec §6.2): placed under the pointer in window points, flipped
/// at the window's right and bottom edges, fixed in size, closed by a press outside it, and the node it adds still
/// lands at the canvas point where it opened.
@MainActor
struct FloatingPaletteTests {
    let size = PaletteLayout.size
    let window = Vector2(1000, 700)

    @Test func thePaletteIsAFixedSize() {
        #expect(size == Vector2(240, 292))
    }

    @Test func itsTopLeftCornerSitsAtThePointer() {
        #expect(PalettePlacement.origin(pointer: Vector2(100, 120), size: size, window: window) == Vector2(100, 120))
        #expect(PalettePlacement.origin(pointer: Vector2(100, 120), size: size, window: nil) == Vector2(100, 120))
    }

    @Test func itFlipsLeftAtTheRightEdge() {
        #expect(PalettePlacement.origin(pointer: Vector2(900, 120), size: size, window: window) == Vector2(660, 120))
    }

    @Test func itFlipsUpAtTheBottomEdge() {
        #expect(PalettePlacement.origin(pointer: Vector2(100, 600), size: size, window: window) == Vector2(100, 308))
    }

    @Test func itFlipsBothWaysInTheBottomRightCorner() {
        #expect(PalettePlacement.origin(pointer: Vector2(900, 600), size: size, window: window) == Vector2(660, 308))
    }

    /// Neither side fits: it is clamped inside the window's margins, and a window smaller than the palette keeps
    /// its top-left margin, so the search field stays reachable.
    @Test func itIsClampedWhenNeitherSideFits() {
        let small = Vector2(300, 320)
        #expect(PalettePlacement.origin(pointer: Vector2(150, 150), size: size, window: small) == Vector2(8, 8))
        #expect(PalettePlacement.origin(pointer: Vector2(250, 30), size: size, window: small) == Vector2(10, 8))
        #expect(PalettePlacement.origin(pointer: Vector2(150, 150), size: size, window: Vector2(100, 100)) == Vector2(8, 8))
    }

    /// Docked at the bottom, the panel is near the window's bottom, so the palette flips up over the viewport,
    /// fully visible, its bottom-left corner at the pointer, and the node still lands where Tab was pressed.
    @Test func atTheBottomDockItFlipsUpAndAddsAtThePressPoint() throws {
        let editor = makeEditor([], dock: .bottom)
        let panel = CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300))
        editor.placement = { PanelPlacement(window: Vector2(1000, 700), panel: panel) }
        editor.pointerLocation = Vector2(100, 50)
        editor.openPalette()
        let palette = try #require(editor.palette)
        let pointer = try #require(editor.canvasFrameInWindow).origin + Vector2(100, 50)
        #expect(palette.windowOrigin == Vector2(pointer.x, pointer.y - PaletteLayout.size.y))
        let frame = try #require(editor.paletteFrame)
        #expect(frame.origin.y >= 0 && frame.maxY <= 700 && frame.maxX <= 1000)
        editor.confirmPalette()
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        #expect(added.position == Vector2(100, 50), "at the canvas point under the pointer, not the palette's corner")
    }

    @Test func atTheLeftDockItOpensWithItsTopLeftCornerAtThePointer() throws {
        let editor = makeEditor([], dock: .left)
        let panel = CanvasRect(origin: Vector2(12, 68), size: Vector2(460, 820))
        editor.placement = { PanelPlacement(window: Vector2(1400, 900), panel: panel) }
        editor.pointerLocation = Vector2(50, 40)
        editor.openPalette()
        let canvas = try #require(editor.canvasFrameInWindow)
        #expect(canvas.origin.x > panel.origin.x && canvas.origin.y > panel.origin.y)
        #expect(editor.palette?.windowOrigin == canvas.origin + Vector2(50, 40))
    }

    @Test func aPressOutsideClosesItAndOneInsideDoesNot() {
        let editor = makeEditor([])
        editor.pointerLocation = Vector2(100, 100)
        editor.openPalette()
        editor.windowPressed(at: Vector2(110, 110))
        #expect(editor.palette != nil)
        editor.windowPressed(at: Vector2(100 + 240 + 1, 110))
        #expect(editor.palette == nil)
        editor.windowPressed(at: Vector2(5, 5))
        #expect(editor.palette == nil, "nothing to close")
    }

    /// Any button's press reaching the window's `onInput` closes the palette when it is outside it (the primary, a
    /// right-click, the middle button), and is never claimed, so it goes on.
    @Test(arguments: ["primary", "secondary", "middle"])
    func theWindowsPressesReachThePaletteUnclaimed(_ button: String) {
        func press(_ x: Float, _ y: Float) -> InputEvent {
            let point = Point(x: Pixels(x), y: Pixels(y))
            switch button {
            case "secondary": return .rightMouseDown(MouseEvent(position: point, buttonNumber: 1))
            case "middle": return .otherMouseDown(MouseEvent(position: point, buttonNumber: 2))
            default: return .mouseDown(MouseEvent(position: point))
            }
        }
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        editor.pointerLocation = Vector2(100, 100)
        editor.openPalette()
        #expect(!input.handle(press(150, 150)))
        #expect(editor.palette != nil)
        #expect(!input.handle(press(900, 150)))
        #expect(editor.palette == nil)
    }

    /// With more matches than rows, ↑/↓ scroll the rows to keep the highlight in view, and typing starts over.
    @Test func theRowsScrollToKeepTheHighlightInView() {
        let editor = makeEditor([], registry: BuiltInNodes.registry)
        editor.openPalette()
        let all = editor.paletteEntries
        #expect(all.count > PaletteLayout.visibleRows)
        #expect(editor.paletteVisibleEntries == Array(all.prefix(PaletteLayout.visibleRows)))
        #expect(editor.paletteHiddenCount == all.count - PaletteLayout.visibleRows)
        editor.movePaletteHighlight(by: 12)
        #expect(editor.palette?.highlighted == 12)
        #expect(editor.palette?.firstVisible == 3)
        #expect(editor.paletteVisibleEntries.last == all[12])
        editor.movePaletteHighlight(by: -11)
        #expect(editor.palette?.firstVisible == 1)
        #expect(editor.paletteVisibleEntries.first == all[1])
        editor.setPaletteQuery("ex")
        #expect(editor.palette?.firstVisible == 0)
        #expect(editor.paletteHiddenCount == 0)
    }

    /// The panel no longer draws the palette (it can't clip or shift the canvas); the overlay draws it, at its
    /// window origin and at its fixed size.
    @Test func theOverlayDrawsThePaletteAndThePanelDoesNot() throws {
        let editor = sampleEditor(dock: .bottom)
        let input = GraphPanelInput(model: editor)
        let closed = renderHeadless { GraphPanel(model: editor, input: input) }.glyphs.count
        #expect(renderHeadless { SearchPaletteOverlay(model: editor) }.isEmpty, "nothing while closed")
        editor.pointerLocation = Vector2(300, 100)
        editor.openPalette()
        #expect(renderHeadless { GraphPanel(model: editor, input: input) }.glyphs.count == closed)
        let scene = renderHeadless { SearchPaletteOverlay(model: editor) }
        let origin = try #require(editor.palette?.windowOrigin)
        let glass = scene.rects.contains { rect in
            let placed = screenFrame(of: rect, in: scene)
            return (placed.origin - origin).length < 0.5 && (placed.size - PaletteLayout.size).length < 0.5
        }
        #expect(glass, "no \(PaletteLayout.size) glass at \(origin)")
    }
}
```
**Create `Tests/CreatorAppTests/Support/SceneOrder.swift`:**
```swift
// Test fixture file: reading a headless frame's paint order and rect frames.
import CreatorEditor
import CreatorGeometry
import MetalUI

/// Where a primitive is in the frame's paint order: its index in the finalized `drawList`'s runs, all kinds
/// together, so a rect can be compared with the viewport's surface. `nil` if no run holds it.
func paintPosition(of kind: PrimitiveKind, at index: Int, in scene: Scene) -> Int? {
    var position = 0
    for run in scene.drawList {
        if run.kind == kind, (run.start..<run.start + run.count).contains(index) { return position + index - run.start }
        position += run.count
    }
    return nil
}

/// A rect's frame in window points (the frame's rects here carry no transform).
func frame(of rect: MUIRect, scale: Double = 2) -> CanvasRect { frame(of: rect.bounds, scale: scale) }

/// Device-pixel bounds in window points.
func frame(of bounds: MUIBounds, scale: Double = 2) -> CanvasRect {
    CanvasRect(origin: Vector2(Double(bounds.origin.x) / scale, Double(bounds.origin.y) / scale),
               size: Vector2(Double(bounds.size.width) / scale, Double(bounds.size.height) / scale))
}
```
**Create `Tests/CreatorAppTests/PaletteOverlayTests.swift`:**
```swift
import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import MetalUIText
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// The add-node palette floats over the whole window (spec §6.2): with the panel docked at the bottom it opens
/// at the pointer, flips up over the viewport and the inspector, and is painted after all of them, unclipped.
@MainActor
struct PaletteOverlayTests {
    @Test func thePaletteIsPaintedOverEverythingWhereItWasPlaced() async throws {
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: Graph(), viewState: ViewState(dock: .bottom)))
        await app.settle()
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.editor.pointerLocation = Vector2(200, 40)
        app.editor.openPalette()
        let palette = try #require(app.editor.palette)
        let panel = try #require(app.panelPlacement?.panel)
        #expect(palette.windowOrigin.y + PaletteLayout.size.y <= panel.origin.y + 10 + 46 + 40,
                "flipped up: its bottom edge is at the pointer")
        #expect(palette.windowOrigin.y < panel.origin.y, "so it reaches above the graph panel, over the viewport")

        let input = AppInput(model: app)
        let scene = renderFrame({ ZStack { AppRoot(model: app, input: input) } },
                                size: Size(width: Pixels(1400), height: Pixels(900)), scaleFactor: 2,
                                textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        let index = try #require(scene.rects.firstIndex { rect in
            let drawn = frame(of: rect)
            return (drawn.origin - palette.windowOrigin).length < 0.5 && (drawn.size - PaletteLayout.size).length < 0.5
        }, "the palette's glass is drawn at its window origin")
        let mask = scene.rects[index].contentMask
        #expect(mask.size.width >= scene.rects[index].bounds.size.width
                && mask.size.height >= scene.rects[index].bounds.size.height, "not clipped by the graph panel")
        let position = try #require(paintPosition(of: .rect, at: index, in: scene))
        let surface = try #require(paintPosition(of: .surface, at: 0, in: scene))
        #expect(position > surface, "over the viewport")
        let panelGlass = try #require(scene.rects.firstIndex { (frame(of: $0).origin - panel.origin).length < 0.5 })
        #expect(try #require(paintPosition(of: .rect, at: panelGlass, in: scene)) < position, "over the graph panel")
        // Everything else in the window (the panels, the inspector, the top bar) is painted before it.
        let palettes = CanvasRect(origin: palette.windowOrigin - Vector2(0.5, 0.5), size: PaletteLayout.size + Vector2(1, 1))
        func inside(_ drawn: CanvasRect) -> Bool { palettes.contains(drawn.origin) && palettes.contains(drawn.origin + drawn.size) }
        let others = scene.rects.indices.filter { !inside(frame(of: scene.rects[$0])) }
            .compactMap { paintPosition(of: .rect, at: $0, in: scene) }
            + scene.glyphs.indices.filter { !inside(frame(of: scene.glyphs[$0].bounds)) }
            .compactMap { paintPosition(of: .glyph, at: $0, in: scene) }
        #expect(!others.isEmpty)
        #expect(others.allSatisfy { $0 < position }, "something outside the palette is painted over it")
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | sort -u | head`
Expected: FAIL — among the errors: `cannot find 'PaletteLayout' in scope`, `value of type 'SearchPaletteState' has no member 'windowOrigin'`.

- [ ] **Step 3: Size and place the palette, in the model**

**Create `Sources/CreatorEditor/PaletteLayout.swift`:**
```swift
import CreatorGeometry

/// The add-node palette's fixed size, computed so it can be placed inside the window before it is drawn
/// (`PalettePlacement`). It shows at most `visibleRows` matches; ↑/↓ scroll the rest into view, so the panel never
/// grows or jumps while the user types.
public enum PaletteLayout {
    /// The column inside the glass.
    public static let contentWidth = 220.0
    public static let fieldHeight = 28.0
    public static let rowHeight = 22.0
    public static let visibleRows = 10
    /// The line under the rows: "No matching nodes", or how many more matches are out of view.
    public static let captionHeight = 16.0
    /// Between the field, the rows and the caption.
    public static let spacing = 4.0
    /// The gap the palette keeps from the window's edges when it flips or is clamped.
    public static let windowMargin = 8.0

    /// The rows' height: `visibleRows` of them, filled or not.
    public static var rowsHeight: Double { Double(visibleRows) * rowHeight }

    /// The column's size inside the glass.
    public static var contentSize: Vector2 {
        Vector2(contentWidth, fieldHeight + spacing + rowsHeight + spacing + captionHeight)
    }

    /// The whole palette, glass included.
    public static var size: Vector2 {
        contentSize + Vector2(2 * GraphPanelLayout.glassPadding, 2 * GraphPanelLayout.glassPadding)
    }
}
```
**Create `Sources/CreatorEditor/PalettePlacement.swift`:**
```swift
import CreatorGeometry

/// Where the floating add-node palette goes in its window (spec §6.2: "at the cursor"): its top-left corner at the
/// pointer; flipped to the pointer's left when it would pass the window's right edge, and above it when it would pass
/// the bottom; clamped inside the window as a last resort, so it is always fully visible.
public enum PalettePlacement {
    /// The top-left corner, in window points, of a `size` palette opened at `pointer` in a `window`-sized window.
    /// Without a window size (the host hasn't placed the panel) it opens at the pointer.
    public static func origin(pointer: Vector2, size: Vector2, window: Vector2?,
                              margin: Double = PaletteLayout.windowMargin) -> Vector2 {
        guard let window else { return pointer }
        return Vector2(axis(pointer.x, size.x, window.x, margin), axis(pointer.y, size.y, window.y, margin))
    }

    /// One axis: after the pointer if it fits, else before it, then kept within the margins (the leading margin
    /// wins in a window smaller than the palette).
    private static func axis(_ pointer: Double, _ length: Double, _ window: Double, _ margin: Double) -> Double {
        let start = pointer + length > window - margin ? pointer - length : pointer
        return max(margin, min(start, window - margin - length))
    }
}
```
**Replace the whole of `Sources/CreatorEditor/SearchPaletteState.swift`:**
```swift
import CreatorGeometry

/// The open add-node palette (spec §6.2: Tab or Space opens it at the cursor).
public struct SearchPaletteState: Equatable, Sendable {
    /// Where it opened, in canvas-local screen points. New nodes land under this point.
    public var screenPosition: Vector2
    /// The palette's top-left corner in window points (`PalettePlacement`), fixed while it is open. Without a host
    /// placement it is `screenPosition`.
    public var windowOrigin: Vector2
    public var query: String
    /// Index into the current matches of the entry Return adds.
    public var highlighted: Int
    /// Index of the first match shown: the palette shows `PaletteLayout.visibleRows` from here, keeping
    /// `highlighted` in view.
    public var firstVisible: Int

    public init(screenPosition: Vector2, windowOrigin: Vector2? = nil, query: String = "", highlighted: Int = 0,
                firstVisible: Int = 0) {
        self.screenPosition = screenPosition
        self.windowOrigin = windowOrigin ?? screenPosition
        self.query = query
        self.highlighted = highlighted
        self.firstVisible = firstVisible
    }
}
```
**Replace the whole of `Sources/CreatorEditor/EditorModel+Palette.swift`:**
```swift
import CreatorGeometry

extension EditorModel {
    /// Tab or Space: opens the add-node palette under the pointer (or the canvas corner). It floats over the
    /// window (`SearchPaletteOverlay`), placed once by `PalettePlacement` so it is fully visible; the node it adds
    /// still lands at the canvas point where it opened.
    public func openPalette() {
        let screen = pointerLocation ?? Vector2(24, 24)
        let pointer = windowPoint(fromCanvas: screen) ?? screen
        let origin = PalettePlacement.origin(pointer: pointer, size: PaletteLayout.size, window: panelPlacement?.window)
        palette = SearchPaletteState(screenPosition: screen, windowOrigin: origin)
    }

    public func closePalette() { palette = nil }

    /// The open palette's frame in window points.
    public var paletteFrame: CanvasRect? {
        palette.map { CanvasRect(origin: $0.windowOrigin, size: PaletteLayout.size) }
    }

    /// A press anywhere in the window, in window points (`GraphPanelInput.handle(_:)`): one outside the open
    /// palette closes it ("a click outside").
    public func windowPressed(at point: Vector2) {
        guard let frame = paletteFrame, !frame.contains(point) else { return }
        closePalette()
    }

    /// The palette's matches for its current query.
    public var paletteEntries: [PaletteEntry] {
        guard let palette else { return [] }
        return PaletteSearch.entries(in: registry, matching: palette.query)
    }

    /// The matches in view: `PaletteLayout.visibleRows` from `firstVisible`.
    public var paletteVisibleEntries: [PaletteEntry] {
        guard let palette else { return [] }
        return Array(paletteEntries.dropFirst(palette.firstVisible).prefix(PaletteLayout.visibleRows))
    }

    /// How many matches are out of view.
    public var paletteHiddenCount: Int { paletteEntries.count - paletteVisibleEntries.count }

    public func setPaletteQuery(_ query: String) {
        palette?.query = query
        palette?.highlighted = 0
        palette?.firstVisible = 0
    }

    /// Moves the highlight by `step`, clamped to the matches, scrolling the rows to keep it in view.
    public func movePaletteHighlight(by step: Int) {
        guard let palette else { return }
        let count = paletteEntries.count
        guard count > 0 else { return }
        let highlighted = min(max(palette.highlighted + step, 0), count - 1)
        var first = palette.firstVisible
        if highlighted < first { first = highlighted }
        if highlighted >= first + PaletteLayout.visibleRows { first = highlighted - PaletteLayout.visibleRows + 1 }
        self.palette?.highlighted = highlighted
        self.palette?.firstVisible = first
    }

    /// Return: adds the highlighted match (or `entry`) under the palette and closes it.
    public func confirmPalette(_ entry: PaletteEntry? = nil) {
        guard let palette else { return }
        let entries = paletteEntries
        guard let chosen = entry ?? (entries.indices.contains(palette.highlighted) ? entries[palette.highlighted] : nil) else { return }
        closePalette()
        addNode(chosen.typeID, atScreen: palette.screenPosition)
    }
}
```

- [ ] **Step 4: Draw it over the window, and close it on a press outside**

**Replace the whole of `Sources/CreatorEditor/SearchPaletteView.swift`:**
```swift
import CreatorStyle
import MetalUI

/// The add-node palette: a search field (focused when it opens), the matches in view, the
/// highlighted one marked, and a caption line. It is `PaletteLayout.size`, whatever it shows, so it
/// never grows or jumps. Return adds, Escape closes (keys come through `GraphPanelInput`). A press or
/// a scroll on its glass is caught here, so it never reaches the canvas, inspector or viewport beneath.
struct SearchPaletteView: Component {
    let model: EditorModel
    @FocusState var searchFocused: Bool
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let entries = model.paletteVisibleEntries
        let highlighted = model.palette?.highlighted ?? 0
        let all = model.paletteEntries
        let highlightedID = all.indices.contains(highlighted) ? all[highlighted].id : nil
        let size = PaletteLayout.size
        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: size.x.px, height: size.y.px)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: Pixels(0)))
                .onScrollWheel { _ in true }
            GlassPanel {
                VStack(alignment: .leading, spacing: PaletteLayout.spacing.px) {
                    TextField("Add node", text: model.palette?.query ?? "", onChange: { model.setPaletteQuery($0) })
                        .onSubmit { model.confirmPalette() }
                        .focused($searchFocused)
                        .onAppear { searchFocused = true }
                        .frame(height: PaletteLayout.fieldHeight.px)
                    VStack(alignment: .leading, spacing: Pixels(0)) {
                        ForEach(entries, id: \.id) { entry in
                            PaletteEntryRow(entry: entry, isHighlighted: entry.id == highlightedID) {
                                model.confirmPalette(entry)
                            }
                        }
                    }
                    .frame(width: PaletteLayout.contentWidth.px, height: PaletteLayout.rowsHeight.px, alignment: .topLeading)
                    Text(caption(hidden: model.paletteHiddenCount, empty: all.isEmpty))
                        .font(.caption)
                        .foregroundStyle(Palette(themes).secondaryText.color)
                        .frame(height: PaletteLayout.captionHeight.px)
                }
                .frame(width: PaletteLayout.contentSize.x.px, height: PaletteLayout.contentSize.y.px, alignment: .topLeading)
            }
        }
    }

    private func caption(hidden: Int, empty: Bool) -> String {
        if empty { return "No matching nodes" }
        return hidden > 0 ? "\(hidden) more: keep typing, or ↑ ↓" : ""
    }
}
```
**Replace the whole of `Sources/CreatorEditor/PaletteEntryRow.swift`:**
```swift
import CreatorStyle
import MetalUI

/// One palette match: a category-coloured dot and the type's name; clicking adds it.
struct PaletteEntryRow: Component {
    let entry: PaletteEntry
    let isHighlighted: Bool
    let action: @MainActor () -> Void
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        return Button(action: action) {
            HStack(spacing: Pixels(6)) {
                Circle().fill(palette.header(for: entry.category).color).frame(width: Pixels(8), height: Pixels(8))
                Text(entry.displayName).font(.callout).foregroundStyle(palette.primaryText.color)
                Spacer()
            }
            .padding(Edges(top: Pixels(0), right: Pixels(6), bottom: Pixels(0), left: Pixels(6)))
            .frame(height: PaletteLayout.rowHeight.px)
            .background(isHighlighted ? palette.field.color : Color.clear, in: RoundedRectangle(cornerRadius: Pixels(4)))
        }
        .buttonStyle(.plain)
    }
}
```
**Create `Sources/CreatorEditor/SearchPaletteOverlay.swift`:**
```swift
import MetalUI

/// The floating add-node palette (spec §6.2), for the host to draw last, over everything in the window (the
/// canvas, the viewport, the inspector), so no panel clips it and it never takes part in their layout. Inside it
/// the palette is offset to `SearchPaletteState.windowOrigin`. It draws nothing while the palette is closed.
public struct SearchPaletteOverlay: Component {
    public let model: EditorModel

    public init(model: EditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            if let palette = model.palette {
                ZStack(alignment: .topLeading) { SearchPaletteView(model: model) }
                    .offset(x: palette.windowOrigin.x.px, y: palette.windowOrigin.y.px)
            }
        }
        // Window-sized and top-left aligned in any host, so `windowOrigin` is measured from the window's corner.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```
**Replace the whole of `Sources/CreatorEditor/GraphCanvas.swift`:**
```swift
import MetalUI

/// The graph canvas: the layers under the zoom and pan transform, one press-and-drag gesture
/// for everything (hit testing is the model's) and pointer tracking for the palette. The palette
/// itself floats over the whole window (`SearchPaletteOverlay`), so the canvas never clips it.
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
    }
}
```
**In `Sources/CreatorEditor/GraphPanelInput.swift`, replace:**
```swift
/// Two more stopgaps are for MetalUI gaps outside C7:
/// - keys: read from the window's `onInput` fallback, so a focused text field keeps its keys;
///   the palette's ↑/↓ and Tab over the canvas alone go through the window keymap (`keymap`,
///   `handleAction`), because a focused field claims arrows and focus traversal claims Tab before
///   `onInput` (gaps M5-h, M5-b);
/// - focus: a canvas press clears text focus through `releaseTextFocus`, because MetalUI never
///   unfocuses a field on an outside press (gap M5-g).
```
**with:**
```swift
/// Three more stopgaps are for MetalUI gaps outside C7:
/// - keys: read from the window's `onInput` fallback, so a focused text field keeps its keys;
///   the palette's ↑/↓ and Tab over the canvas alone go through the window keymap (`keymap`,
///   `handleAction`), because a focused field claims arrows and focus traversal claims Tab before
///   `onInput` (gaps M5-h, M5-b);
/// - focus: a canvas press clears text focus through `releaseTextFocus`, because MetalUI never
///   unfocuses a field on an outside press (gap M5-g);
/// - the floating palette's "click outside": a press of any button reaching `onInput` outside the
///   palette closes it (`handle(_:)`), because MetalUI's only overlay that dismisses itself is
///   `.popover`, with its own chrome (gap EP-b).
```
**In `Sources/CreatorEditor/GraphPanelInput.swift`, replace:**
```swift
    /// Install from `Window.onInput` (`install(on:)` does). Returns true when the event was used.
    /// Tracking modifiers here is part of the `dragValueModifiers(_:)` stopgap.
```
**with:**
```swift
    /// Install from `Window.onInput` (`install(on:)` does). Returns true when the event was used.
    /// Tracking modifiers here is part of the `dragValueModifiers(_:)` stopgap. Every primary press
    /// reaches `onInput` (MetalUI claims none, except one in a text field or on a slider), and so does
    /// every other button's press but a right-click that opens a context menu, so the floating
    /// palette's "click outside" is read here too.
```
**In `Sources/CreatorEditor/GraphPanelInput.swift`, replace:**
```swift
            guard let command = GraphKeyBindings.command(for: key, paletteOpen: model.palette != nil) else { return false }
            return model.perform(command)
```
**with:**
```swift
            guard let command = GraphKeyBindings.command(for: key, paletteOpen: model.palette != nil) else { return false }
            return model.perform(command)
        case .mouseDown(let mouse), .rightMouseDown(let mouse), .otherMouseDown(let mouse):
            // Any button's press outside the floating palette closes it. Never claimed, so the press goes on.
            model.windowPressed(at: Self.vector(mouse.position))
            return false
```
**Create `Sources/CreatorApp/PaletteDock.swift`:**
```swift
import CreatorEditor
import MetalUI

/// The floating add-node palette, contributing the `AppKeyContext.panel` key context so the viewport's F, + and −
/// type into its search field (gap M4-a), as they do in the graph panel and the inspector.
struct PaletteDock: Component {
    let model: AppModel

    var content: some ElementGroup {
        Stack(alignment: .topLeading) {
            SearchPaletteOverlay(model: model.editor)
        }
        .keyContext(AppKeyContext.panel)
    }
}
```
**Replace the whole of `Sources/CreatorApp/AppRoot.swift`:**
```swift
import CreatorEditor
import CreatorViewport
import MetalUI

/// The window's content (spec §6.1): the viewport fills the window, and the glass top bar, the graph panel in its
/// dock and the inspector float over it. A pick in progress shows its banner over the top, and the add-node palette
/// floats over everything (spec §6.2), drawn last so nothing clips or covers it. Every view below reads
/// the app's theme from the environment, and the window's MetalUI controls follow its light or dark (spec §6.6).
/// All behaviour is in `AppModel`; this is glue.
public struct AppRoot: Component {
    public let model: AppModel
    public let input: AppInput

    public init(model: AppModel, input: AppInput) {
        self.model = model
        self.input = input
    }

    public var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            ViewportView(model: model.viewport, modifiers: input.modifiers)
            VStack(alignment: .leading, spacing: AppLayout.margin.px) {
                ZStack { TopBar(model: model) }
                    .frame(height: AppLayout.topBarHeight.px)
                PanelArea(model: model)
            }
            .padding(Edges(all: AppLayout.margin.px))
            if let pick = model.pick {
                HStack {
                    Spacer()
                    PickBanner(model: model, picked: pick.picked.count)
                    Spacer()
                }
                .padding(Edges(top: (AppLayout.margin * 2 + AppLayout.topBarHeight).px, right: Pixels(0),
                               bottom: Pixels(0), left: Pixels(0)))
            }
            PaletteDock(model: model)
        }
        .onChange(of: model.editor.inspectorRequest) { _, request in
            if let request { model.handle(request) }
        }
        .alert(model.alert?.title ?? "", isPresented: Binding(get: { model.alert != nil }, set: { shown in
            if !shown { model.alert = nil }
        }), presenting: model.alert) { alert in
            if case .discardChanges = alert {
                Button("Discard Changes", role: .destructive) { Task { await model.discardChanges() } }
                Button("Cancel", role: .cancel) { model.keepChanges() }
            }
        } message: { alert in
            Text(alert.message)
        }
        .environment(model.themes)
        .preferredColorScheme(model.themes.current.isDark ? .dark : .light)
    }
}
```
**Replace the whole of `Sources/GraphPanelPreview/PreviewRoot.swift`:**
```swift
import CreatorEditor
import MetalUI

/// The preview window's content: the window background, the graph panel in its dock and the
/// inspector on the right — the layout the app shell (M6) floats over the viewport — and the
/// add-node palette floating over all of it. It is laid out to `PreviewLayout`, which tells the
/// editor where the panel is.
struct PreviewRoot: Component {
    let model: EditorModel
    let input: GraphPanelInput

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            Palette.dracula.backgroundBottom.color
            switch model.dock {
            case .left:
                HStack(alignment: .top, spacing: PreviewLayout.margin.px) {
                    ZStack { GraphPanel(model: model, input: input) }
                        .frame(width: PreviewLayout.leftPanelWidth.px)
                        .frame(maxHeight: .infinity)
                    Spacer()
                    InspectorPanel(model: model)
                }
                .padding(Edges(all: PreviewLayout.margin.px))
            case .bottom:
                VStack(spacing: PreviewLayout.margin.px) {
                    HStack(alignment: .top) {
                        Spacer()
                        InspectorPanel(model: model)
                    }
                    Spacer()
                    ZStack { GraphPanel(model: model, input: input) }
                        .frame(height: PreviewLayout.bottomPanelHeight.px)
                        .frame(maxWidth: .infinity)
                }
                .padding(Edges(all: PreviewLayout.margin.px))
            case .hidden:
                // Hidden keeps a visible way back: "Show graph" (Tab is its shortcut).
                HStack(alignment: .bottom) {
                    GraphShowButton(model: model)
                    Spacer()
                    InspectorPanel(model: model)
                }
                .padding(Edges(all: PreviewLayout.margin.px))
            }
            SearchPaletteOverlay(model: model)
        }
        .frame(width: PreviewLayout.window.x.px, height: PreviewLayout.window.y.px)
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter 'FloatingPaletteTests|PaletteOverlayTests|SearchPaletteTests|GraphPanelRenderTests|AppInputTests'`
Expected: all pass (12 new in `FloatingPaletteTests`, 1 in `PaletteOverlayTests`; `SearchPaletteTests`' `thePaletteOpensUnderThePointer` still holds, since without a placement `windowOrigin` is `screenPosition`). Then `swift test`: **920** (master + 19).

- [ ] **Step 6: Commit**

```bash
swiftlint lint --strict   # must report 0 violations
git add Sources/CreatorEditor/PaletteLayout.swift Sources/CreatorEditor/PalettePlacement.swift \
        Sources/CreatorEditor/SearchPaletteState.swift Sources/CreatorEditor/EditorModel+Palette.swift \
        Sources/CreatorEditor/SearchPaletteView.swift Sources/CreatorEditor/PaletteEntryRow.swift \
        Sources/CreatorEditor/SearchPaletteOverlay.swift Sources/CreatorEditor/GraphCanvas.swift \
        Sources/CreatorEditor/GraphPanelInput.swift Sources/CreatorApp/PaletteDock.swift \
        Sources/CreatorApp/AppRoot.swift Sources/GraphPanelPreview/PreviewRoot.swift \
        Tests/CreatorEditorTests/FloatingPaletteTests.swift Tests/CreatorEditorTests/Support/SceneGeometry.swift \
        Tests/CreatorAppTests/PaletteOverlayTests.swift Tests/CreatorAppTests/Support/SceneOrder.swift
git commit -m "feat(editor): the add-node palette floats over the window at the pointer"
```

---

### Task 3: The node library's model

Decisions 4, 9 and 10. Everything the library does, testable without a view: its saved visibility, its search and grouping, a type's one-line summary, click-to-add at the visible centre clear of other nodes and in view, drop-to-add at a point, and a row's press told apart as a click or a drag released on the canvas or elsewhere (Decision 1).

**Files:**
- Create: `Sources/CreatorEditor/LibrarySection.swift`, `Sources/CreatorEditor/NodeTypeSummary.swift`, `Sources/CreatorEditor/LibraryDrag.swift`, `Sources/CreatorEditor/EditorModel+Library.swift`
- Modify: `Sources/CreatorGraph/ViewState.swift`, `Sources/CreatorEditor/EditorModel.swift`, `Sources/CreatorEditor/EditorModel+Editing.swift`
- Test: `Tests/CreatorGraphTests/ViewStateLibraryTests.swift`, `Tests/CreatorGraphTests/Support/FormatThreeViewState.swift`, `Tests/CreatorEditorTests/LibraryTests.swift`, `Tests/CreatorEditorTests/LibraryDragTests.swift`

**Interfaces:**
- Consumes: Task 1's `canvasFrameInWindow`, `panelPlacement`, `PanelPlacement`, `GraphPanelLayout.fallbackCanvasSize`; `CanvasRect(corner:_:)`, `CanvasTransform`; `PaletteSearch.entries(in:matching:)`, `PaletteEntry`, `InspectorLabel.text(for:)`, `NodeLayout.size(_:)`, `EditorModel.shape(of:)`, `frame(of:)`, `flow`, `transform`, `addNode(_:atScreen:)`, `NodeRegistry.makeNode(_:at:)`.
- Produces: `ViewState.showsLibrary: Bool` (default `true`; `init(…, showsLibrary: Bool = true)`); `EditorModel.libraryQuery: String` (`public internal(set)`), `.showsLibrary`, `.toggleLibrary()`, `.setLibraryQuery(_:)`, `.librarySections: [LibrarySection]`, `.librarySummary(of: String) -> String?`, `.visibleCanvasSize: Vector2`, `.visibleCanvasCentre: Vector2`, `.addFromLibrary(_ typeID: String)`, `@discardableResult .dropFromLibrary(_ typeID: String, atScreen: Vector2) -> Bool`, `.libraryDrag: LibraryDrag?` (`public internal(set)`), `.moveLibraryDrag(_ typeID: String, from: Vector2, to: Vector2)`, `@discardableResult .endLibraryDrag(_ typeID: String, from: Vector2, at: Vector2) -> Bool`, `.libraryDragEntry: PaletteEntry?`, `static libraryNudge` (24, 24), internal `static maxLibraryRings` (40), `add(_ node: Node)`, `freeOrigin(near:size:in:)`; `LibraryDrag(typeID:start:location:)` with `isDragging`, `static threshold` (10); `LibrarySection(category:entries:)` with `id`, `title`, `static title(for:)`, `static grouping(_:)`; `NodeTypeSummary.text(_ definition: any NodeDefinition.Type) -> String`.

- [ ] **Step 1: Write the failing tests**

**Create `Tests/CreatorGraphTests/Support/FormatThreeViewState.swift`:**
```swift
import CreatorGraph

/// The view state as a format-3 reader from before the node library decodes it: the same optional keys, without
/// `showsLibrary`. Swift's keyed decoding ignores keys a type doesn't name, so this is what an older build does
/// with a file that has the new key.
struct FormatThreeViewState: Decodable {
    var dock: DockSide
    var canvasZoom: Double

    private enum CodingKeys: String, CodingKey { case dock, canvasOffset, canvasZoom, camera, homeCamera }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dock = try container.decodeIfPresent(DockSide.self, forKey: .dock) ?? .left
        canvasZoom = try container.decodeIfPresent(Double.self, forKey: .canvasZoom) ?? 1
    }
}
```
**Create `Tests/CreatorGraphTests/ViewStateLibraryTests.swift`:**
```swift
import Foundation
import Testing
@testable import CreatorGraph

/// The node library's visibility is saved in the view state. It is an added optional key, which older readers
/// ignore, so `GraphFile.currentFormatVersion` stays 3 (CLAUDE.md: bump only for changes older readers can't decode).
struct ViewStateLibraryTests {
    @Test func theLibraryIsShownUnlessHidden() throws {
        #expect(ViewState().showsLibrary)
        let decoded = try JSONDecoder().decode(ViewState.self, from: Data(#"{"dock":"bottom"}"#.utf8))
        #expect(decoded.showsLibrary, "files from before the library show it")
    }

    @Test func aHiddenLibraryRoundTrips() throws {
        let state = ViewState(dock: .bottom, showsLibrary: false)
        #expect(try JSONDecoder().decode(ViewState.self, from: JSONEncoder().encode(state)) == state)
    }

    @Test func anOlderReaderStillDecodesTheViewState() throws {
        let data = try JSONEncoder().encode(ViewState(dock: .bottom, canvasZoom: 2, showsLibrary: false))
        let older = try JSONDecoder().decode(FormatThreeViewState.self, from: data)
        #expect(older.dock == .bottom)
        #expect(older.canvasZoom == 2)
        #expect(GraphFile.currentFormatVersion == 3, "no format bump")
    }
}
```
**Create `Tests/CreatorEditorTests/LibraryTests.swift`:**
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorEditor

/// The node library ("Nodes", spec §6.2 editor polish): shown by default and saved with the view state, grouped by
/// category over the palette's search, a click adding at the visible canvas's centre clear of other nodes and in view,
/// a drop adding at the drop point, each one undo step.
@MainActor
struct LibraryTests {
    /// The bottom dock's canvas in a 1000 × 700 window: 956 × 244 points.
    func placed(_ editor: EditorModel) -> EditorModel {
        let panel = CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300))
        editor.placement = { PanelPlacement(window: Vector2(1000, 700), panel: panel) }
        return editor
    }

    @Test func itIsShownByDefaultAndItsVisibilityIsSavedButNotAnEdit() throws {
        let editor = makeEditor([])
        #expect(editor.showsLibrary)
        editor.toggleLibrary()
        #expect(!editor.showsLibrary)
        #expect(!editor.document.canUndo, "a view change, not an edit")
        let file = try JSONDecoder().decode(GraphFile.self, from: try editor.document.fileData())
        #expect(!file.viewState.showsLibrary)
        let reopened = EditorModel(document: try DocumentModel(data: try editor.document.fileData(),
                                                               registry: editorTestRegistry, kernel: FakeKernel()))
        #expect(!reopened.showsLibrary)
    }

    @Test func typesAreGroupedByCategoryInOrder() {
        let editor = makeEditor([])
        #expect(editor.librarySections.map(\.title) == ["Value", "Profile", "Solid", "Selection", "Feature", "Output"])
        #expect(editor.librarySections.map { $0.entries.map(\.displayName) }
                == [["Number"], ["Rectangle"], ["Extrude"], ["All Edges"], ["Fillet"], ["Output"]])
    }

    /// The library filters with the palette's search, and empty categories go.
    @Test func theSearchIsThePalettes() {
        let editor = makeEditor([])
        editor.setLibraryQuery("e")
        let flattened = editor.librarySections.flatMap(\.entries).map(\.typeID)
        #expect(Set(flattened) == Set(PaletteSearch.entries(in: editorTestRegistry, matching: "e").map(\.typeID)))
        editor.setLibraryQuery("FIL")
        let fillets = PaletteSearch.entries(in: editorTestRegistry, matching: "fil")
        #expect(editor.librarySections == [LibrarySection(category: .feature, entries: fillets)])
        editor.setLibraryQuery("zzz")
        #expect(editor.librarySections.isEmpty)
    }

    @Test func hoverHelpNamesInputsThenOutputs() {
        let editor = makeEditor([], registry: inspectorTestRegistry)
        #expect(editor.librarySummary(of: ExtrudeTestNode.typeID) == "Extrude: profile, distance, mode, reversed → solid")
        #expect(editor.librarySummary(of: GridPointsTestNode.typeID) == "Grid Points: count x, total → points")
        #expect(editor.librarySummary(of: GraphParameterTestNode.typeID)
                == "Graph Parameter: no inputs → number, integer, bool, vector")
        #expect(editor.librarySummary(of: "plugin.gone") == nil)
    }

    /// The visible canvas's centre comes from the host's placement (without one, a fallback size's).
    @Test func theVisibleCentreIsTheMiddleOfThePlacedCanvas() throws {
        let editor = makeEditor([], dock: .bottom)
        #expect(editor.visibleCanvasCentre == GraphPanelLayout.fallbackCanvasSize * 0.5)
        let canvas = try #require(placed(editor).canvasFrameInWindow)
        #expect(editor.visibleCanvasCentre == canvas.size * 0.5)
    }

    /// Panned and zoomed, the click still lands in the middle of what is on screen.
    @Test func aClickAddsTheTypeCentredInTheVisibleCanvasAsOneStep() throws {
        let editor = placed(makeEditor([], dock: .bottom))
        editor.transform = CanvasTransform(offset: Vector2(10, 20), zoom: 2)
        editor.addFromLibrary(NumberTestNode.typeID)
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        #expect(added.typeID == NumberTestNode.typeID)
        let frame = editor.frame(of: added)
        #expect(editor.transform.toScreen(frame.origin + frame.size * 0.5) == editor.visibleCanvasCentre)
        editor.document.undo()
        #expect(editor.graph.nodes.isEmpty)
        #expect(!editor.document.canUndo, "one step")
    }

    /// Three Extrudes fit side by side in the bottom dock's canvas, each clear of the others.
    @Test func aClickedTypeIsNudgedOffTheNodesAlreadyThere() throws {
        let editor = placed(makeEditor([], dock: .bottom))
        for _ in 0..<3 { editor.addFromLibrary(ExtrudeTestNode.typeID) }
        let frames = editor.graph.nodes.values.map(editor.frame(of:))
        #expect(frames.count == 3)
        for (i, a) in frames.enumerated() {
            for b in frames.dropFirst(i + 1) { #expect(!a.intersects(b), "\(a) overlaps \(b)") }
        }
    }

    /// A crowded view: each clicked type lands wholly inside the visible canvas, wherever it is panned and zoomed,
    /// and once nothing free fits in view it is centred anyway, never pushed off-screen.
    @Test(arguments: [CanvasTransform(), CanvasTransform(offset: Vector2(-300, 40), zoom: 2)])
    func aClickedTypeStaysInViewWhenTheCentreIsCrowded(_ transform: CanvasTransform) throws {
        let editor = placed(makeEditor([], dock: .bottom))
        editor.transform = transform
        let canvas = CanvasRect(origin: .zero, size: editor.visibleCanvasSize)
        for _ in 0..<12 { editor.addFromLibrary(NumberTestNode.typeID) }
        #expect(editor.graph.nodes.count == 12)
        for node in editor.graph.nodes.values {
            let frame = editor.frame(of: node)
            let corners = [frame.origin, frame.origin + frame.size].map(editor.transform.toScreen)
            #expect(corners.allSatisfy(canvas.contains), "\(corners) is outside the visible \(canvas)")
        }
    }

    /// Docked left the canvas shows the transpose, so the centre is found in display points and stored transposed.
    @Test func dockedLeftItIsCentredOnScreenToo() throws {
        let editor = makeEditor([], dock: .left)
        editor.addFromLibrary(NumberTestNode.typeID)
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        let frame = editor.frame(of: added)
        let centre = GraphPanelLayout.fallbackCanvasSize * 0.5
        #expect(frame.origin + frame.size * 0.5 == centre)
        #expect(added.position == Vector2(frame.origin.y, frame.origin.x))
    }

    @Test(arguments: [DockSide.left, .bottom])
    func aDropAddsTheTypeAtTheDropPointAsOneStep(_ dock: DockSide) throws {
        let editor = makeEditor([], dock: dock)
        #expect(editor.dropFromLibrary(FilletTestNode.typeID, atScreen: Vector2(300, 120)))
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        #expect(editor.frame(of: added).origin == Vector2(300, 120))
        editor.document.undo()
        #expect(editor.graph.nodes.isEmpty)
        #expect(!editor.dropFromLibrary("plugin.gone", atScreen: Vector2(300, 120)), "not a type this registry has")
        #expect(editor.graph.nodes.isEmpty)
    }
}
```
**Create `Tests/CreatorEditorTests/LibraryDragTests.swift`:**
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Dragging a type from the node library (a `DragGesture` in window points on its row, no system drag and drop): a
/// release on the canvas adds it at the release point, anywhere else adds nothing, and a press that moves less than
/// `LibraryDrag.threshold` is still a click, adding at the visible centre. Each add is one undo step.
@MainActor
struct LibraryDragTests {
    /// The graph panel docked at the bottom of a 1000 × 700 window, or docked left in a 1400 × 900 one.
    func placed(_ dock: DockSide) -> EditorModel {
        let editor = makeEditor([], dock: dock)
        let placement = dock == .left
            ? PanelPlacement(window: Vector2(1400, 900), panel: CanvasRect(origin: Vector2(12, 68), size: Vector2(460, 820)))
            : PanelPlacement(window: Vector2(1000, 700), panel: CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300)))
        editor.placement = { placement }
        return editor
    }

    /// A row's press in window points: inside the library, left of (or above) the canvas.
    func rowPoint(_ editor: EditorModel) throws -> Vector2 {
        let canvas = try #require(editor.canvasFrameInWindow)
        return editor.flow == .horizontal ? Vector2(canvas.origin.x - 100, canvas.origin.y + 40)
                                          : Vector2(canvas.origin.x + 40, canvas.origin.y - 100)
    }

    @Test(arguments: [DockSide.left, .bottom])
    func aReleaseOnTheCanvasAddsTheTypeThereAsOneStep(_ dock: DockSide) throws {
        let editor = placed(dock)
        let canvas = try #require(editor.canvasFrameInWindow)
        let start = try rowPoint(editor), end = canvas.origin + Vector2(120, 60)
        editor.moveLibraryDrag(FilletTestNode.typeID, from: start, to: end)
        #expect(editor.libraryDrag == LibraryDrag(typeID: FilletTestNode.typeID, start: start, location: end))
        #expect(editor.libraryDragEntry?.displayName == "Fillet")
        #expect(editor.endLibraryDrag(FilletTestNode.typeID, from: start, at: end))
        #expect(editor.libraryDrag == nil)
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        #expect(added.typeID == FilletTestNode.typeID)
        #expect(editor.transform.toScreen(editor.frame(of: added).origin) == Vector2(120, 60), "top-left at the release")
        editor.document.undo()
        #expect(editor.graph.nodes.isEmpty)
        #expect(!editor.document.canUndo, "one step")
    }

    /// Released over the library itself, the viewport, the inspector or outside the window: nothing is added.
    @Test(arguments: [DockSide.left, .bottom])
    func aReleaseOffTheCanvasAddsNothing(_ dock: DockSide) throws {
        let editor = placed(dock)
        let start = try rowPoint(editor)
        let window = try #require(editor.panelPlacement).window
        for end in [start + Vector2(12, 12), Vector2(window.x - 20, 30), Vector2(-40, -40), window + Vector2(50, 50)] {
            editor.moveLibraryDrag(ExtrudeTestNode.typeID, from: start, to: end)
            #expect(!editor.endLibraryDrag(ExtrudeTestNode.typeID, from: start, at: end), "released at \(end)")
        }
        #expect(editor.graph.nodes.isEmpty)
        #expect(editor.libraryDrag == nil)
    }

    /// A press that jitters less than the threshold (a trackpad click) is a click: no ghost, and the type is added
    /// at the visible canvas's centre.
    @Test func aClickThatMovesUnderTheThresholdStillAddsAtTheCentre() throws {
        let editor = placed(.bottom)
        let start = try rowPoint(editor), jitter = start + Vector2(6, 7)
        #expect((jitter - start).length < LibraryDrag.threshold)
        editor.moveLibraryDrag(NumberTestNode.typeID, from: start, to: jitter)
        #expect(editor.libraryDrag == nil, "no ghost for a click")
        #expect(editor.endLibraryDrag(NumberTestNode.typeID, from: start, at: jitter))
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        let frame = editor.frame(of: added)
        #expect(editor.transform.toScreen(frame.origin + frame.size * 0.5) == editor.visibleCanvasCentre)
        editor.document.undo()
        #expect(!editor.document.canUndo, "one step")
    }

    /// Before the host has placed the panel there is no canvas in window points, so a drag adds nothing; an
    /// unregistered type adds nothing either way.
    @Test func withoutAPlacementOrARegisteredTypeNothingIsAdded() {
        let editor = makeEditor([], dock: .bottom)
        #expect(!editor.endLibraryDrag(NumberTestNode.typeID, from: .zero, at: Vector2(300, 300)))
        let placed = placed(.bottom)
        #expect(!placed.endLibraryDrag("plugin.gone", from: .zero, at: .zero))
        #expect(!placed.endLibraryDrag("plugin.gone", from: .zero, at: Vector2(400, 500)))
        #expect(editor.graph.nodes.isEmpty && placed.graph.nodes.isEmpty)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | sort -u | head`
Expected: FAIL — among the errors: `cannot find 'LibrarySection' in scope`, `cannot find 'LibraryDrag' in scope`, `value of type 'EditorModel' has no member 'toggleLibrary'` (and `showsLibrary`, `librarySections`, `addFromLibrary`, `dropFromLibrary`, `visibleCanvasCentre`), `value of type 'ViewState' has no member 'showsLibrary'`.

- [ ] **Step 3: Save the library's visibility**

**Replace the whole of `Sources/CreatorGraph/ViewState.swift`:**
```swift
import CreatorGeometry

/// Editor state saved with a document. Every key is optional when decoding, so files stay
/// readable as later milestones add fields. Older readers ignore keys they don't know.
public struct ViewState: Sendable, Codable, Equatable {
    public var dock: DockSide
    public var canvasOffset: Vector2
    public var canvasZoom: Double
    /// The viewport camera when the document was saved (M4). `nil` in older files, in which case the viewport
    /// frames the part when it first appears.
    public var camera: CameraPose?
    /// The document's home view, set from the viewport's View menu (spec §6.3). `nil` means isometric and framed.
    public var homeCamera: CameraPose?
    /// Whether the graph panel shows its node library ("Nodes"). Shown unless the user hid it; files from before
    /// the editor-polish milestone have no key and show it. Not a format change: older readers ignore the key.
    public var showsLibrary: Bool

    public init(dock: DockSide = .left, canvasOffset: Vector2 = .zero, canvasZoom: Double = 1,
                camera: CameraPose? = nil, homeCamera: CameraPose? = nil, showsLibrary: Bool = true) {
        self.dock = dock
        self.canvasOffset = canvasOffset
        self.canvasZoom = canvasZoom
        self.camera = camera
        self.homeCamera = homeCamera
        self.showsLibrary = showsLibrary
    }

    private enum CodingKeys: String, CodingKey { case dock, canvasOffset, canvasZoom, camera, homeCamera, showsLibrary }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dock = try container.decodeIfPresent(DockSide.self, forKey: .dock) ?? .left
        canvasOffset = try container.decodeIfPresent(Vector2.self, forKey: .canvasOffset) ?? .zero
        canvasZoom = try container.decodeIfPresent(Double.self, forKey: .canvasZoom) ?? 1
        camera = try container.decodeIfPresent(CameraPose.self, forKey: .camera)
        homeCamera = try container.decodeIfPresent(CameraPose.self, forKey: .homeCamera)
        showsLibrary = try container.decodeIfPresent(Bool.self, forKey: .showsLibrary) ?? true
    }
}
```

- [ ] **Step 4: The library's behaviour in the editor model**

**In `Sources/CreatorEditor/EditorModel.swift`, replace:**
```swift
/// The graph panel's state and behaviour: selection, the canvas transform, the dock, drags,
/// wiring, clipboard and the add-node palette. Every edit goes through `DocumentModel.perform`,
```
**with:**
```swift
/// The graph panel's state and behaviour: selection, the canvas transform, the dock, drags,
/// wiring, clipboard, the add-node palette and the node library. Every edit goes through `DocumentModel.perform`,
```
**In `Sources/CreatorEditor/EditorModel.swift`, replace:**
```swift
    public var palette: SearchPaletteState?
```
**with:**
```swift
    public var palette: SearchPaletteState?
    /// What the node library's search field holds (`EditorModel+Library`). Not saved.
    public internal(set) var libraryQuery = ""
    /// A library type being dragged toward the canvas, once it has moved far enough to be a drag
    /// (`EditorModel+Library`); `LibraryDragOverlay` draws it at the pointer.
    public internal(set) var libraryDrag: LibraryDrag?
```
**In `Sources/CreatorEditor/EditorModel+Editing.swift`, replace:**
```swift
    /// Adds a node of `typeID` under the palette (or at the canvas origin) and selects it.
    public func addNode(_ typeID: String, atScreen screen: Vector2) {
        let node = registry.makeNode(typeID, at: flow.stored(transform.toCanvas(screen)))
        do {
            try document.perform(.addNode(node))
            selection = [node.id]
        } catch {
            refuse(error.message, node: nil)
        }
    }
```
**with:**
```swift
    /// Adds a node of `typeID` with its top-left corner at `screen` (canvas-local screen points: under the palette,
    /// or where a library node was dropped) and selects it, as one undo step.
    public func addNode(_ typeID: String, atScreen screen: Vector2) {
        add(registry.makeNode(typeID, at: flow.stored(transform.toCanvas(screen))))
    }

    /// Adds `node` (made by `NodeRegistry.makeNode`) and selects it, as one undo step.
    func add(_ node: Node) {
        do {
            try document.perform(.addNode(node))
            selection = [node.id]
        } catch {
            refuse(error.message, node: nil)
        }
    }
```
**Create `Sources/CreatorEditor/LibrarySection.swift`:**
```swift
import CreatorGraph

/// One category of the node library: its title and its types (spec §6.6 colours its header).
public struct LibrarySection: Equatable, Sendable, Identifiable {
    public var category: NodeCategory
    public var entries: [PaletteEntry]

    public var id: NodeCategory { category }

    public var title: String { Self.title(for: category) }

    /// "Value", "Profile", "Solid", "Selection", "Feature", "Output".
    public static func title(for category: NodeCategory) -> String {
        category.rawValue.prefix(1).uppercased() + category.rawValue.dropFirst()
    }

    /// `entries` grouped by category, in `NodeCategory.allCases` order, keeping their order within each group;
    /// a category with no entries is left out.
    public static func grouping(_ entries: [PaletteEntry]) -> [LibrarySection] {
        NodeCategory.allCases.compactMap { category in
            let members = entries.filter { $0.category == category }
            return members.isEmpty ? nil : LibrarySection(category: category, entries: members)
        }
    }
}
```
**Create `Sources/CreatorEditor/NodeTypeSummary.swift`:**
```swift
import CreatorGraph

/// A node type in one line, its inputs → its outputs: "Extrude: profile, distance, mode, reversed → solid". The
/// node library shows it when a type is hovered.
public enum NodeTypeSummary {
    public static func text(_ definition: any NodeDefinition.Type) -> String {
        "\(definition.displayName): \(names(definition.inputs, none: "no inputs")) → \(names(definition.outputs, none: "no outputs"))"
    }

    private static func names(_ sockets: [SocketSpec], none: String) -> String {
        sockets.isEmpty ? none : sockets.map { InspectorLabel.text(for: $0.name).lowercased() }.joined(separator: ", ")
    }
}
```
**Create `Sources/CreatorEditor/LibraryDrag.swift`:**
```swift
import CreatorGeometry

/// A press on a node-library type, followed in window points by a `DragGesture` on its row
/// (`GraphPanelInput.libraryGesture(for:)`): MetalUI's own gesture inside the window, no system drag and drop.
/// Until the pointer has moved `threshold` from the press it is still a click.
public struct LibraryDrag: Equatable, Sendable {
    /// How far, in points, the pointer must move from the press before it is a drag rather than a click (MetalUI's
    /// and SwiftUI's default `DragGesture` minimum distance).
    public static let threshold = 10.0

    public var typeID: String
    /// The press, in window points.
    public var start: Vector2
    /// The pointer now, in window points.
    public var location: Vector2

    public init(typeID: String, start: Vector2, location: Vector2) {
        self.typeID = typeID
        self.start = start
        self.location = location
    }

    /// Whether the pointer has moved far enough from the press for this to be a drag rather than a click.
    public var isDragging: Bool { (location - start).length >= Self.threshold }
}
```
**Create `Sources/CreatorEditor/EditorModel+Library.swift`:**
```swift
import CreatorGeometry
import CreatorGraph

extension EditorModel {
    /// The grid a node added from the library is nudged along, off the nodes under it, in display canvas points.
    public static let libraryNudge = Vector2(24, 24)
    /// Rings of the nudge grid scanned outward from the centre before the node is added there anyway.
    static let maxLibraryRings = 40

    /// Whether the graph panel shows its node library. Saved with the document's view state; not an edit.
    public var showsLibrary: Bool { document.viewState.showsLibrary }

    /// The panel header's "Library" button.
    public func toggleLibrary() {
        document.viewState.showsLibrary.toggle()
    }

    public func setLibraryQuery(_ query: String) {
        libraryQuery = query
    }

    /// The library's types matching its search (the palette's search, `PaletteSearch`), by category.
    public var librarySections: [LibrarySection] {
        LibrarySection.grouping(PaletteSearch.entries(in: registry, matching: libraryQuery))
    }

    /// A type's inputs → outputs, for the library's hover help; `nil` for an unregistered type.
    public func librarySummary(of typeID: String) -> String? {
        registry[typeID].map(NodeTypeSummary.text)
    }

    /// The visible canvas's size in points, from the host's placement (without one,
    /// `GraphPanelLayout.fallbackCanvasSize`).
    public var visibleCanvasSize: Vector2 {
        canvasFrameInWindow?.size ?? GraphPanelLayout.fallbackCanvasSize
    }

    /// The middle of the visible canvas, in canvas-local screen points.
    public var visibleCanvasCentre: Vector2 { visibleCanvasSize * 0.5 }

    /// A click on a library type: adds it centred in the visible canvas, or at the nearest spot in view where it
    /// overlaps no other node, and selects it, as one undo step.
    public func addFromLibrary(_ typeID: String) {
        guard registry[typeID] != nil else { return }
        var node = registry.makeNode(typeID)
        let size = NodeLayout.size(shape(of: node))
        let centred = transform.toCanvas(visibleCanvasCentre) - size * 0.5
        let visible = CanvasRect(corner: transform.toCanvas(.zero), transform.toCanvas(visibleCanvasSize))
        node.position = flow.stored(freeOrigin(near: centred, size: size, in: visible))
        add(node)
    }

    /// A library type dropped on the canvas at `screen` (canvas-local screen points): its top-left corner lands
    /// there, as one undo step. Returns false, adding nothing, for a type that isn't registered.
    @discardableResult
    public func dropFromLibrary(_ typeID: String, atScreen screen: Vector2) -> Bool {
        guard registry[typeID] != nil, screen.isFinite else { return false }
        addNode(typeID, atScreen: screen)
        return true
    }

    /// The pointer moved while pressing a library type's row (`start` and `location` in window points). Once it is
    /// `LibraryDrag.threshold` from the press the type is being dragged, and `LibraryDragOverlay` draws it at the
    /// pointer; short of that nothing changes, so a click's jitter rebuilds nothing.
    public func moveLibraryDrag(_ typeID: String, from start: Vector2, to location: Vector2) {
        let drag = LibraryDrag(typeID: typeID, start: start, location: location)
        let shown = drag.isDragging ? drag : nil
        if libraryDrag != shown { libraryDrag = shown }
    }

    /// The press on a library type's row ended at `location` (window points). Short of `LibraryDrag.threshold` it was
    /// a click: the type is added at the visible canvas's centre (`addFromLibrary(_:)`). Otherwise it was dragged: it
    /// is added with its top-left corner at the release point when that is on the canvas (`canvasFrameInWindow`, which
    /// leaves out the library), and nothing is added anywhere else or before the host has placed the panel. Each add
    /// is one undo step. Returns whether a node was added.
    @discardableResult
    public func endLibraryDrag(_ typeID: String, from start: Vector2, at location: Vector2) -> Bool {
        if libraryDrag != nil { libraryDrag = nil }
        guard registry[typeID] != nil else { return false }
        guard LibraryDrag(typeID: typeID, start: start, location: location).isDragging else {
            addFromLibrary(typeID)
            return true
        }
        guard let canvas = canvasFrameInWindow, canvas.contains(location) else { return false }
        return dropFromLibrary(typeID, atScreen: location - canvas.origin)
    }

    /// The type the drag ghost shows, while a library type is being dragged.
    public var libraryDragEntry: PaletteEntry? {
        guard let drag = libraryDrag, let definition = registry[drag.typeID] else { return nil }
        return PaletteEntry(typeID: definition.typeID, displayName: definition.displayName, category: definition.category)
    }

    /// The nearest display origin to `start` on the `libraryNudge` grid, scanned ring by ring outward, where a `size`
    /// node lies inside `visible` (the visible canvas, in display canvas points) and meets no node's frame; `start`
    /// itself when none does within `maxLibraryRings`, so the node still lands in the middle of the view.
    func freeOrigin(near start: Vector2, size: Vector2, in visible: CanvasRect) -> Vector2 {
        let frames = graph.nodes.values.map(frame(of:))
        func fits(_ origin: Vector2) -> Bool {
            let candidate = CanvasRect(origin: origin, size: size)
            return visible.contains(origin) && visible.contains(origin + size)
                && !frames.contains { $0.intersects(candidate) }
        }
        for ring in 0...Self.maxLibraryRings {
            for row in -ring...ring {
                for column in -ring...ring where max(abs(row), abs(column)) == ring {
                    let origin = start + Vector2(Self.libraryNudge.x * Double(column), Self.libraryNudge.y * Double(row))
                    if fits(origin) { return origin }
                }
            }
        }
        return start
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter 'LibraryTests|LibraryDragTests|ViewStateLibraryTests|DockTests|SearchPaletteTests'`
Expected: all pass (10 new in `LibraryTests`, 4 in `LibraryDragTests`, 3 in `ViewStateLibraryTests`; `DockTests.theDockIsSavedWithTheDocument` still compares equal, since `showsLibrary` defaults to `true` on both sides). Then `swift test`: **937** (master + 36). Check the in-view bound bites: in `freeOrigin`, replace `return visible.contains(origin) && visible.contains(origin + size)` with `return true` (keeping the `&& !frames…` line), rerun `swift test --filter CreatorEditorTests.LibraryTests` (`aClickedTypeStaysInViewWhenTheCentreIsCrowded` fails), and restore it.

- [ ] **Step 6: Commit**

```bash
swiftlint lint --strict   # must report 0 violations
git add Sources/CreatorGraph/ViewState.swift Sources/CreatorEditor/EditorModel.swift \
        Sources/CreatorEditor/EditorModel+Editing.swift Sources/CreatorEditor/LibrarySection.swift \
        Sources/CreatorEditor/NodeTypeSummary.swift Sources/CreatorEditor/EditorModel+Library.swift \
        Sources/CreatorEditor/LibraryDrag.swift \
        Tests/CreatorGraphTests/ViewStateLibraryTests.swift Tests/CreatorGraphTests/Support/FormatThreeViewState.swift \
        Tests/CreatorEditorTests/LibraryTests.swift Tests/CreatorEditorTests/LibraryDragTests.swift
git commit -m "feat(editor): node library model: saved visibility, search by category, add at the visible centre, click or drag a row"
```

---

### Task 4: The node library in the graph panel

Decisions 1, 2, 3, 11 and 13. The library is drawn as a column (docked at the bottom) or a strip (docked left), captioned "Nodes" and toggled by the header's Library button; a click adds, a drag onto the canvas adds at the release point (each row's one `DragGesture`, Task 3's model, a ghost row over the window), hover shows the summary. The canvas's computed frame now steps aside for the library, so Task 1's geometry tests are rewritten for it.

**Files:**
- Create: `Sources/CreatorEditor/GraphPanelBody.swift`, `Sources/CreatorEditor/NodeLibraryView.swift`, `Sources/CreatorEditor/LibraryItem.swift`, `Sources/CreatorEditor/LibraryRow.swift`, `Sources/CreatorEditor/LibrarySectionHeader.swift`, `Sources/CreatorEditor/PaletteEntryLabel.swift`, `Sources/CreatorEditor/LibraryDragOverlay.swift`
- Modify: `Sources/CreatorEditor/GraphPanelLayout.swift`, `Sources/CreatorEditor/EditorModel+Placement.swift`, `Sources/CreatorEditor/GraphPanel.swift`, `Sources/CreatorEditor/GraphPanelHeader.swift`, `Sources/CreatorEditor/PaletteEntryRow.swift`, `Sources/CreatorEditor/GraphPanelInput.swift`, `Sources/CreatorApp/AppRoot.swift`, `Sources/GraphPanelPreview/PreviewRoot.swift`
- Test: `Tests/CreatorEditorTests/LibraryViewTests.swift`; modify `Tests/CreatorEditorTests/PanelPlacementTests.swift`, `Tests/CreatorAppTests/PanelPlacementTests.swift`, `Tests/CreatorAppTests/PaletteOverlayTests.swift`

**Interfaces:**
- Consumes: Task 3's `showsLibrary`, `toggleLibrary()`, `libraryQuery`, `setLibraryQuery(_:)`, `librarySections`, `librarySummary(of:)`, `addFromLibrary(_:)`, `libraryDrag`, `libraryDragEntry`, `moveLibraryDrag(_:from:to:)`, `endLibraryDrag(_:from:at:)`, `LibrarySection.title(for:)`; Task 2's `PaletteLayout.spacing`/`fieldHeight`/`rowHeight`/`captionHeight`, `PaletteEntryRow`, `SearchPaletteOverlay`, `PaletteDock`, test helpers `screenFrame(of:in:scale:)`, `paintPosition(of:at:in:)`, `frame(of:scale:)`; `EditorModel.flow`; `NodeHeaderView`; MetalUI `List(_:rowHeight:row:)`, `ScrollView`, `.help(_:)`, `DragGesture(minimumDistance:coordinateSpace:)` (`.global`, C7) and its `minimumDistance`/`coordinateSpace`/`button`, `.gesture(_:)`, `.contentShape(_:)`, `.allowsHitTesting(_:)`, `ThemeStore`, `InMemoryThemePreferences`.
- Produces: `GraphPanelLayout.libraryExtent` (176), `.bodyFrame(inPanelOf:)`, `.libraryFrame(inPanelOf:flow:)`, `.canvasFrame(inPanelOf:flow:showsLibrary:)` (replacing Task 1's one-argument `canvasFrame`); `GraphPanelInput.libraryGesture(for typeID: String) -> DragGesture`; `LibraryDragOverlay(model:)` (public) with `static width`; `LibraryItem(category:entry:)` with `id`, `static rows(_ sections:)`; views `GraphPanelBody`, `NodeLibraryView(model:input:)`, `LibraryRow(model:input:item:)`, `LibrarySectionHeader(category:title:)`, `PaletteEntryLabel(entry:isHighlighted:)` (internal).

- [ ] **Step 1: Write the failing tests, and move Task 1's geometry tests to the library-aware layout**

**Replace the whole of `Tests/CreatorEditorTests/PanelPlacementTests.swift`:**
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// The panel's geometry is computed (`GraphPanelLayout`), and the host says where the panel is in its window
/// (`EditorModel.placement`), so the editor knows where its canvas is without measuring anything (gap M4-a).
@MainActor
struct PanelPlacementTests {
    @Test func theBodySitsUnderTheHeaderInsideTheGlass() {
        let body = GraphPanelLayout.bodyFrame(inPanelOf: Vector2(400, 300))
        #expect(body.origin == Vector2(10, 46))
        #expect(body.size == Vector2(380, 244))
        #expect(GraphPanelLayout.bodyFrame(inPanelOf: Vector2(10, 10)).size == .zero, "never negative")
        #expect(GraphPanelLayout.canvasFrame(inPanelOf: Vector2(400, 300), flow: .horizontal, showsLibrary: false) == body)
    }

    /// Docked at the bottom (horizontal flow) the library is a column at the canvas's left edge; docked left
    /// (vertical flow) a strip across its top.
    @Test func theLibrarySitsOnTheSideTheGraphFlowsFrom() {
        let size = Vector2(800, 300)
        #expect(GraphPanelLayout.libraryFrame(inPanelOf: size, flow: .horizontal)
                == CanvasRect(origin: Vector2(10, 46), size: Vector2(176, 244)))
        #expect(GraphPanelLayout.canvasFrame(inPanelOf: size, flow: .horizontal, showsLibrary: true)
                == CanvasRect(origin: Vector2(194, 46), size: Vector2(596, 244)))
        let tall = Vector2(400, 700)
        #expect(GraphPanelLayout.libraryFrame(inPanelOf: tall, flow: .vertical)
                == CanvasRect(origin: Vector2(10, 46), size: Vector2(380, 176)))
        #expect(GraphPanelLayout.canvasFrame(inPanelOf: tall, flow: .vertical, showsLibrary: true)
                == CanvasRect(origin: Vector2(10, 230), size: Vector2(380, 460)))
    }

    @Test func theHostPlacesTheCanvasInTheWindow() {
        let editor = makeEditor([], dock: .bottom)
        #expect(editor.canvasFrameInWindow == nil, "no host, no window coordinates")
        let panel = CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300))
        editor.placement = { PanelPlacement(window: Vector2(1000, 700), panel: panel) }
        #expect(editor.canvasFrameInWindow == CanvasRect(origin: Vector2(206, 434), size: Vector2(772, 244)))
        #expect(editor.windowPoint(fromCanvas: Vector2(5, 6)) == Vector2(211, 440))
        #expect(editor.visibleCanvasCentre == Vector2(386, 122))
        editor.toggleLibrary()
        #expect(editor.canvasFrameInWindow == CanvasRect(origin: Vector2(22, 434), size: Vector2(956, 244)))
        editor.setDock(.hidden)
        #expect(editor.canvasFrameInWindow == nil, "a hidden panel has no canvas")
    }

    /// The header and the library are framed to `GraphPanelLayout`, so the canvas starts where the layout says: a
    /// node at the canvas origin, unpanned and unzoomed, is drawn at `canvasFrame`'s origin.
    @Test(arguments: [(DockSide.left, true), (.left, false), (.bottom, true), (.bottom, false)])
    func aNodeAtTheCanvasOriginIsDrawnWhereTheLayoutPutsTheCanvas(_ dock: DockSide, _ library: Bool) {
        let editor = makeEditor([testNode(NumberTestNode.self, id: 1, at: .zero)], dock: dock)
        if !library { editor.toggleLibrary() }
        let input = GraphPanelInput(model: editor)
        let scene = renderHeadless { GraphPanel(model: editor, input: input) }
        let scale = 2.0
        let origin = GraphPanelLayout.canvasFrame(inPanelOf: Vector2(900, 600), flow: editor.flow, showsLibrary: library).origin
        let body = scene.rects.contains { rect in
            abs(Double(rect.bounds.origin.x) / scale - origin.x) < 0.5
                && abs(Double(rect.bounds.origin.y) / scale - origin.y) < 0.5
                && abs(Double(rect.bounds.size.width) / scale - NodeLayout.width) < 0.5
        }
        #expect(body, "no node drawn at \(origin)")
    }
}
```
**In `Tests/CreatorAppTests/PanelPlacementTests.swift`, replace:**
```swift
        #expect(app.editor.canvasFrameInWindow?.origin == panel.origin + Vector2(10, 46))
```
**with:**
```swift
        #expect(app.editor.canvasFrameInWindow?.origin == panel.origin + Vector2(10, 46 + 176 + 8), "under the library's strip")
```
**In `Tests/CreatorAppTests/PaletteOverlayTests.swift`, replace:**
```swift
import CreatorKernel
import MetalUI
```
**with:**
```swift
import CreatorKernel
import CreatorNodes
import MetalUI
```
**In `Tests/CreatorAppTests/PaletteOverlayTests.swift`, replace:**
```swift
        #expect(others.allSatisfy { $0 < position }, "something outside the palette is painted over it")
    }
}
```
**with:**
```swift
        #expect(others.allSatisfy { $0 < position }, "something outside the palette is painted over it")
    }

    /// A node-library type dragged out over the viewport is drawn at the pointer, over the viewport and the panel.
    @Test func aDraggedLibraryTypeIsPaintedOverTheWindow() async throws {
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: Graph(), viewState: ViewState(dock: .bottom)))
        await app.settle()
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        let panel = try #require(app.panelPlacement?.panel)
        let row = panel.origin + Vector2(60, 100), pointer = Vector2(700, 300)
        app.editor.moveLibraryDrag(FilletNode.typeID, from: row, to: pointer)
        #expect(app.editor.libraryDrag != nil)
        let input = AppInput(model: app)
        let scene = renderFrame({ ZStack { AppRoot(model: app, input: input) } },
                                size: Size(width: Pixels(1400), height: Pixels(900)), scaleFactor: 2,
                                textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        let index = try #require(scene.rects.firstIndex { (frame(of: $0).origin - pointer).length < 0.5 },
                                 "the ghost is drawn at the pointer")
        let position = try #require(paintPosition(of: .rect, at: index, in: scene))
        #expect(position > (try #require(paintPosition(of: .surface, at: 0, in: scene))), "over the viewport")
        let panelGlass = try #require(scene.rects.firstIndex { (frame(of: $0).origin - panel.origin).length < 0.5 })
        #expect(try #require(paintPosition(of: .rect, at: panelGlass, in: scene)) < position, "over the graph panel")
    }
}
```
**Create `Tests/CreatorEditorTests/LibraryViewTests.swift`:**
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorStyle
import MetalUI
import Testing
@testable import CreatorEditor

/// The node library's views and its drag: drawn inside its `GraphPanelLayout` frame in both docks, gone when
/// hidden, category headers in the theme's header colours, no shadows, and the drag's one gesture and ghost.
@MainActor
struct LibraryViewTests {
    /// In an empty panel every glyph below the header is the library's: what shows of it (inside its clip; the
    /// list scrolls) lies in the library's frame.
    @Test(arguments: [DockSide.left, .bottom])
    func theLibraryIsDrawnInItsFrame(_ dock: DockSide) {
        let editor = makeEditor([], dock: dock)
        let input = GraphPanelInput(model: editor)
        let scene = renderHeadless { GraphPanel(model: editor, input: input) }
        let library = GraphPanelLayout.libraryFrame(inPanelOf: Vector2(900, 600), flow: editor.flow)
        let shown = scene.glyphs.compactMap { glyph -> CanvasRect? in
            let bounds = points(glyph.bounds), mask = points(glyph.contentMask)
            let origin = Vector2(max(bounds.origin.x, mask.origin.x), max(bounds.origin.y, mask.origin.y))
            let corner = Vector2(min(bounds.maxX, mask.maxX), min(bounds.maxY, mask.maxY))
            guard corner.x > origin.x, corner.y > origin.y, origin.y >= library.origin.y else { return nil }
            return CanvasRect(corner: origin, corner)
        }
        #expect(shown.count > 20, "the search field's placeholder, the headers and their types")
        let slack = CanvasRect(origin: library.origin - Vector2(0.5, 0.5), size: library.size + Vector2(1, 1))
        for part in shown {
            #expect(slack.contains(part.origin) && slack.contains(part.origin + part.size), "\(part) is outside \(library)")
        }
    }

    /// Device-pixel bounds in points.
    func points(_ bounds: MUIBounds, scale: Double = 2) -> CanvasRect {
        CanvasRect(origin: Vector2(Double(bounds.origin.x) / scale, Double(bounds.origin.y) / scale),
                   size: Vector2(Double(bounds.size.width) / scale, Double(bounds.size.height) / scale))
    }

    /// One flat list of uniform rows, so MetalUI's `List` builds only those in view: each header, then its types.
    @Test func theListIsEachHeaderThenItsTypes() {
        let editor = makeEditor([])
        editor.setLibraryQuery("e")
        let rows = LibraryItem.rows(editor.librarySections)
        let expected = [
            "header.value", NumberTestNode.typeID, "header.profile", RectangleTestNode.typeID, "header.solid",
            ExtrudeTestNode.typeID, "header.selection", AllEdgesTestNode.typeID, "header.feature", FilletTestNode.typeID,
        ]
        #expect(rows.map(\.id) == expected)
        #expect(rows.filter { $0.entry == nil }.map(\.category) == [.value, .profile, .solid, .selection, .feature])
    }

    @Test func hidingTheLibraryTakesItOutOfThePanel() {
        let editor = makeEditor([], dock: .bottom)
        let input = GraphPanelInput(model: editor)
        let shown = renderHeadless { GraphPanel(model: editor, input: input) }.glyphs.count
        editor.toggleLibrary()
        let hidden = renderHeadless { GraphPanel(model: editor, input: input) }.glyphs.count
        #expect(hidden < shown - 20)
    }

    /// A category's header paints the colour its nodes' headers have, in the current theme.
    @Test(arguments: [nil, "alucard"])
    func aSectionHeaderIsItsCategorysHeaderColour(_ theme: String?) {
        let store = ThemeStore()
        if let theme { store.select(theme) }
        func fills(_ scene: Scene) -> Set<[Float]> {
            Set(scene.rects.map { [$0.background.h, $0.background.s, $0.background.l, $0.background.a] })
        }
        let accent = Palette(store).header(for: .profile)
        let header = fills(renderHeadless { LibrarySectionHeader(category: .profile, title: "Profile").environment(store) })
        let node = fills(renderHeadless { NodeHeaderView(title: "Rectangle", accent: accent, state: nil).environment(store) })
        #expect(!header.isDisjoint(with: node))
    }

    @Test func theLibraryRedrawsInTheChosenTheme() {
        let editor = makeEditor([])
        func render(_ store: ThemeStore) -> [[Float]] {
            let scene = renderHeadless { NodeLibraryView(model: editor, input: GraphPanelInput(model: editor)).environment(store) }
            return scene.rects.map { [$0.background.h, $0.background.s, $0.background.l, $0.background.a] }
                + scene.glyphs.map { [$0.color.h, $0.color.s, $0.color.l, $0.color.a] }
        }
        let store = ThemeStore()
        let dracula = render(store)
        store.select("alucard")
        #expect(render(store) != dracula)
        #expect(render(store) == render(ThemeStore(preferences: InMemoryThemePreferences(selectedThemeID: "alucard"))))
    }

    /// Flat fills and text only: no shadow or path is rasterized, whatever the view rebuilds (PERF-a, PERF-b).
    @Test func theLibraryRasterizesNothing() {
        let editor = makeEditor([])
        #expect(renderHeadless { NodeLibraryView(model: editor, input: GraphPanelInput(model: editor)) }.images.isEmpty)
    }

    /// A row is one zero-distance drag in window points, so the model tells a click from a drag
    /// (`LibraryDrag.threshold`) and maps the release with the host's placement.
    @Test func aRowsGestureIsAZeroDistanceDragInWindowPoints() {
        let editor = makeEditor([])
        let gesture = GraphPanelInput(model: editor).libraryGesture(for: FilletTestNode.typeID)
        #expect(gesture.minimumDistance == Pixels(0))
        #expect(gesture.coordinateSpace == .global)
        #expect(gesture.button == .primary)
    }

    /// The ghost is drawn with its top-left corner at the pointer, in window points, only once the press has moved
    /// far enough to be a drag; a flat row, nothing rasterized.
    @Test func theDragGhostIsDrawnAtThePointerOnlyWhileDragging() throws {
        let editor = makeEditor([])
        #expect(renderHeadless { LibraryDragOverlay(model: editor) }.isEmpty, "nothing without a drag")
        editor.moveLibraryDrag(FilletTestNode.typeID, from: Vector2(40, 300), to: Vector2(44, 303))
        #expect(renderHeadless { LibraryDragOverlay(model: editor) }.isEmpty, "nothing for a click's jitter")
        editor.moveLibraryDrag(FilletTestNode.typeID, from: Vector2(40, 300), to: Vector2(420, 250))
        let scene = renderHeadless { LibraryDragOverlay(model: editor) }
        let ghost = scene.rects.contains { rect in
            let placed = screenFrame(of: rect, in: scene)
            return (placed.origin - Vector2(420, 250)).length < 0.5 && abs(placed.size.x - LibraryDragOverlay.width) < 0.5
        }
        #expect(ghost, "no \(LibraryDragOverlay.width)-wide row at (420, 250)")
        #expect(scene.glyphs.count >= "Fillet".count)
        #expect(scene.images.isEmpty)
        editor.endLibraryDrag(FilletTestNode.typeID, from: Vector2(40, 300), at: Vector2(420, 250))
        #expect(renderHeadless { LibraryDragOverlay(model: editor) }.isEmpty, "gone at the release")
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | sort -u | head`
Expected: FAIL — among the errors: `type 'GraphPanelLayout' has no member 'bodyFrame'`, `type 'GraphPanelLayout' has no member 'libraryFrame'`, `extra arguments at positions #2, #3 in call` (the three-argument `canvasFrame`). Once those compile, `LibraryItem`, `NodeLibraryView`, `LibraryDragOverlay` and `libraryGesture(for:)` are missing too.

- [ ] **Step 3: Make room for the library in the panel's geometry**

**Replace the whole of `Sources/CreatorEditor/GraphPanelLayout.swift`:**
```swift
import CreatorGeometry

/// The graph panel's own geometry, computed rather than measured (MetalUI has no geometry reader:
/// docs/metalui-gaps.md M4-a, EP-a), so the editor can tell where its canvas is in the window. `GlassPanel`,
/// `GraphPanel`, `GraphPanelHeader` and `GraphPanelBody` are framed to these numbers, as nodes are framed to
/// `NodeLayout`.
///
/// Under the header is the body: the node library and the canvas. The library sits on the side the graph flows
/// from, across the panel's short axis: a column at the canvas's left edge when docked at the bottom (the graph
/// flows right; the panel is wide and short), a strip across its top when docked left (the graph flows down; the
/// panel is narrow and tall), so it takes the room the panel has most of.
public enum GraphPanelLayout {
    /// The glass chrome's inset around its content (`GlassPanel`).
    public static let glassPadding = 10.0
    /// The header row (title and buttons).
    public static let headerHeight = 28.0
    /// Between the header and the body, and between the library and the canvas.
    public static let spacing = 8.0
    /// The library's column width (docked at the bottom) or strip height (docked left).
    public static let libraryExtent = 176.0
    /// The canvas size assumed while the host hasn't placed the panel (headless tests): the centre of a small panel.
    public static let fallbackCanvasSize = Vector2(400, 300)

    /// The body under the header inside a panel of `size`, in panel-local points. It runs to the panel's padding; a
    /// refusal message showing under it takes one line from its bottom.
    public static func bodyFrame(inPanelOf size: Vector2) -> CanvasRect {
        let origin = Vector2(glassPadding, glassPadding + headerHeight + spacing)
        return CanvasRect(origin: origin, size: Vector2(max(0, size.x - 2 * glassPadding),
                                                        max(0, size.y - origin.y - glassPadding)))
    }

    /// The node library's frame in the body, for a panel of `size` showing the graph in `flow`.
    public static func libraryFrame(inPanelOf size: Vector2, flow: CanvasFlow) -> CanvasRect {
        let body = bodyFrame(inPanelOf: size)
        switch flow {
        case .horizontal: return CanvasRect(origin: body.origin, size: Vector2(min(libraryExtent, body.size.x), body.size.y))
        case .vertical: return CanvasRect(origin: body.origin, size: Vector2(body.size.x, min(libraryExtent, body.size.y)))
        }
    }

    /// The canvas's frame: the whole body, or the body beside or below the library.
    public static func canvasFrame(inPanelOf size: Vector2, flow: CanvasFlow, showsLibrary: Bool) -> CanvasRect {
        let body = bodyFrame(inPanelOf: size)
        guard showsLibrary else { return body }
        let inset = libraryExtent + spacing
        switch flow {
        case .horizontal:
            return CanvasRect(origin: body.origin + Vector2(inset, 0), size: Vector2(max(0, body.size.x - inset), body.size.y))
        case .vertical:
            return CanvasRect(origin: body.origin + Vector2(0, inset), size: Vector2(body.size.x, max(0, body.size.y - inset)))
        }
    }
}
```
**In `Sources/CreatorEditor/EditorModel+Placement.swift`, replace:**
```swift
        let local = GraphPanelLayout.canvasFrame(inPanelOf: placement.panel.size)
```
**with:**
```swift
        let local = GraphPanelLayout.canvasFrame(inPanelOf: placement.panel.size, flow: flow, showsLibrary: showsLibrary)
```

- [ ] **Step 4: Draw the library, its rows' gesture and the drag ghost**

**Create `Sources/CreatorEditor/PaletteEntryLabel.swift`:**
```swift
import CreatorStyle
import MetalUI

/// A node type's row content, shared by the palette, the node library and the library's drag ghost: a
/// category-coloured dot and the type's name, on the field colour while highlighted.
struct PaletteEntryLabel: Component {
    let entry: PaletteEntry
    let isHighlighted: Bool
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        return HStack(spacing: Pixels(6)) {
            Circle().fill(palette.header(for: entry.category).color).frame(width: Pixels(8), height: Pixels(8))
            Text(entry.displayName).font(.callout).foregroundStyle(palette.primaryText.color)
            Spacer()
        }
        .padding(Edges(top: Pixels(0), right: Pixels(6), bottom: Pixels(0), left: Pixels(6)))
        .frame(height: PaletteLayout.rowHeight.px)
        .background(isHighlighted ? palette.field.color : Color.clear, in: RoundedRectangle(cornerRadius: Pixels(4)))
    }
}
```
**Replace the whole of `Sources/CreatorEditor/PaletteEntryRow.swift`:**
```swift
import MetalUI

/// One palette match (`PaletteEntryLabel`); clicking adds it.
struct PaletteEntryRow: Component {
    let entry: PaletteEntry
    let isHighlighted: Bool
    let action: @MainActor () -> Void

    var content: some ElementGroup {
        Button(action: action) {
            PaletteEntryLabel(entry: entry, isHighlighted: isHighlighted)
        }
        .buttonStyle(.plain)
    }
}
```
**Create `Sources/CreatorEditor/LibraryItem.swift`:**
```swift
import CreatorGraph

/// One row of the node library's list: a category's header, or one of its types. The library is one flat,
/// uniformly tall list so MetalUI's `List` builds only the rows in view (docs/metalui-gaps.md PERF-b).
public struct LibraryItem: Equatable, Sendable, Identifiable {
    public var category: NodeCategory
    /// The type, or `nil` for the category's header.
    public var entry: PaletteEntry?

    /// The header's "header.<category>", or the type's ID.
    public var id: String { entry?.typeID ?? "header.\(category.rawValue)" }

    /// The rows of `sections`: each category's header, then its types.
    public static func rows(_ sections: [LibrarySection]) -> [LibraryItem] {
        sections.flatMap { section in
            [LibraryItem(category: section.category, entry: nil)]
                + section.entries.map { LibraryItem(category: section.category, entry: $0) }
        }
    }
}
```
**Create `Sources/CreatorEditor/LibrarySectionHeader.swift`:**
```swift
import CreatorGraph
import CreatorStyle
import MetalUI

/// A node-library category's header: its title in the theme's text-on-accent colour on the category's header
/// colour, the colour its nodes' headers have (spec §6.6).
struct LibrarySectionHeader: Component {
    let category: NodeCategory
    let title: String
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        return HStack(spacing: Pixels(0)) {
            Text(title)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(palette.textOnAccent.color)
            Spacer()
        }
        .padding(Edges(top: Pixels(0), right: Pixels(6), bottom: Pixels(0), left: Pixels(6)))
        .frame(height: Pixels(18))
        .background(palette.header(for: category).color, in: RoundedRectangle(cornerRadius: Pixels(4)))
    }
}
```
**Create `Sources/CreatorEditor/LibraryRow.swift`:**
```swift
import MetalUI

/// One row of the node library: a category's coloured header, or a type. A type's row shows the palette's row
/// content (`PaletteEntryLabel`) under one gesture, `GraphPanelInput.libraryGesture(for:)`: a click adds the type at
/// the visible canvas's centre, a drag carries it to the canvas. Not a `Button`, because a child's click holds off an
/// enclosing drag for the whole press in MetalUI (as in SwiftUI). Its help is the type's inputs → outputs.
struct LibraryRow: Component {
    let model: EditorModel
    let input: GraphPanelInput
    let item: LibraryItem

    var content: some ElementGroup {
        if let entry = item.entry {
            ZStack(alignment: .topLeading) {
                PaletteEntryLabel(entry: entry, isHighlighted: false)
            }
            .gesture(input.libraryGesture(for: entry.typeID))
            .contentShape(Rectangle())
            .help(model.librarySummary(of: entry.typeID) ?? entry.displayName)
        } else {
            LibrarySectionHeader(category: item.category, title: LibrarySection.title(for: item.category))
        }
    }
}
```
**Create `Sources/CreatorEditor/NodeLibraryView.swift`:**
```swift
import CreatorStyle
import MetalUI

/// The node library: a "Nodes" caption and a search field over the registry's types grouped by category, each group
/// under a header in its category's colour. Click a type to add it at the visible canvas's centre; drag it onto the
/// canvas to add it there; hover it for its inputs → outputs. Kept cheap for MetalUI's whole-window rebuilds
/// (docs/metalui-gaps.md PERF-b): one windowed `List` of uniform rows (only those in view are built), flat fills,
/// no shadows, rows keyed by type.
struct NodeLibraryView: Component {
    let model: EditorModel
    let input: GraphPanelInput
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        let rows = LibraryItem.rows(model.librarySections)
        return VStack(alignment: .leading, spacing: PaletteLayout.spacing.px) {
            Text("Nodes")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(palette.secondaryText.color)
                .frame(height: PaletteLayout.captionHeight.px)
            TextField("Search nodes", text: model.libraryQuery, onChange: { model.setLibraryQuery($0) })
                .frame(height: PaletteLayout.fieldHeight.px)
            if rows.isEmpty {
                Text("No matching nodes").font(.caption).foregroundStyle(palette.secondaryText.color)
            }
            ScrollView {
                List(rows, rowHeight: PaletteLayout.rowHeight.px) { row in
                    ZStack(alignment: .topLeading) { LibraryRow(model: model, input: input, item: row) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(Edges(all: Pixels(6)))
        .background(palette.panelBase.color, in: RoundedRectangle(cornerRadius: Pixels(6)))
    }
}
```
**Create `Sources/CreatorEditor/GraphPanelBody.swift`:**
```swift
import MetalUI

/// The graph panel under its header (`GraphPanelLayout`): the canvas, with the node library as a column at its
/// left edge (docked at the bottom) or a strip across its top (docked left) while it is shown.
struct GraphPanelBody: Component {
    let model: EditorModel
    let input: GraphPanelInput

    var content: some ElementGroup {
        let extent = GraphPanelLayout.libraryExtent.px
        let spacing = GraphPanelLayout.spacing.px
        if !model.showsLibrary {
            GraphCanvas(model: model, input: input)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.flow == .horizontal {
            HStack(alignment: .top, spacing: spacing) {
                NodeLibraryView(model: model, input: input)
                    .frame(width: extent)
                    .frame(maxHeight: .infinity)
                GraphCanvas(model: model, input: input)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: spacing) {
                NodeLibraryView(model: model, input: input)
                    .frame(height: extent)
                    .frame(maxWidth: .infinity)
                GraphCanvas(model: model, input: input)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
```
**Create `Sources/CreatorEditor/LibraryDragOverlay.swift`:**
```swift
import CreatorStyle
import MetalUI

/// The node-library type being dragged, drawn as a flat row with its top-left corner at the pointer (where the
/// node's top-left corner lands on release), for the host to draw over everything in its window, beside
/// `SearchPaletteOverlay`, so neither panel clips it. It draws nothing while no type is being dragged, and never
/// takes a press or hover.
public struct LibraryDragOverlay: Component {
    public let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    /// The ghost row's width: the library's column, less its padding.
    static let width = GraphPanelLayout.libraryExtent - 12

    public init(model: EditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        let palette = Palette(themes)
        return ZStack(alignment: .topLeading) {
            if let drag = model.libraryDrag, let entry = model.libraryDragEntry {
                ZStack(alignment: .topLeading) { PaletteEntryLabel(entry: entry, isHighlighted: true) }
                    .frame(width: Self.width.px)
                    .background(palette.panelBase.color, in: RoundedRectangle(cornerRadius: Pixels(4)))
                    .overlay { RoundedRectangle(cornerRadius: Pixels(4)).strokeBorder(palette.hairline.color, lineWidth: Pixels(1)) }
                    .offset(x: drag.location.x.px, y: drag.location.y.px)
            }
        }
        // Window-sized and top-left aligned in any host, so the pointer's window point is measured from its corner.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
```
**Replace the whole of `Sources/CreatorEditor/GraphPanel.swift`:**
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
```
**Replace the whole of `Sources/CreatorEditor/GraphPanelHeader.swift`:**
```swift
import CreatorGraph
import CreatorStyle
import MetalUI

/// The graph panel's header: the title, Add (opens the palette), Library (shows or hides the node
/// library), zoom buttons (the stopgap for pinch and ⌘-scroll, docs/metalui-gaps.md) and the dock
/// buttons (Left, Bottom, Hide).
struct GraphPanelHeader: Component {
    let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        HStack(spacing: Pixels(6)) {
            Text("Graph").font(.headline).foregroundStyle(Palette(themes).primaryText.color)
            Spacer()
            Button("Add") { model.openPalette() }
                .help("Add a node (Space)")
            Button("Library") { model.toggleLibrary() }
                .help(model.showsLibrary ? "Hide the node library" : "Show the node library")
            Button("−") { model.zoom(in: false) }
                .help("Zoom out (−)")
            Button("+") { model.zoom(in: true) }
                .help("Zoom in (+)")
            Button("Left") { model.setDock(.left) }
                .help("Dock left: the graph flows down")
                .disabled(model.dock == .left)
            Button("Bottom") { model.setDock(.bottom) }
                .help("Dock at the bottom: the graph flows right")
                .disabled(model.dock == .bottom)
            Button("Hide") { model.setDock(.hidden) }
                .help("Hide the graph (Tab)")
        }
    }
}
```
**In `Sources/CreatorEditor/GraphPanelInput.swift`, replace:**
```swift
    /// The pointer over the canvas, from `.onContinuousHover`.
```
**with:**
```swift
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
```

**In `Sources/CreatorApp/AppRoot.swift`, replace:**
```swift
/// dock and the inspector float over it. A pick in progress shows its banner over the top, and the add-node palette
/// floats over everything (spec §6.2), drawn last so nothing clips or covers it. Every view below reads
```
**with:**
```swift
/// dock and the inspector float over it. A pick in progress shows its banner over the top, and the add-node palette
/// and a node-library type being dragged float over everything (spec §6.2), drawn last so nothing clips or covers
/// them. Every view below reads
```
**In `Sources/CreatorApp/AppRoot.swift`, replace:**
```swift
            PaletteDock(model: model)
```
**with:**
```swift
            PaletteDock(model: model)
            LibraryDragOverlay(model: model.editor)
```
**In `Sources/GraphPanelPreview/PreviewRoot.swift`, replace:**
```swift
/// inspector on the right — the layout the app shell (M6) floats over the viewport — and the
/// add-node palette floating over all of it. It is laid out to `PreviewLayout`, which tells the
/// editor where the panel is.
```
**with:**
```swift
/// inspector on the right — the layout the app shell (M6) floats over the viewport — and the
/// add-node palette and a dragged node-library type floating over all of it. It is laid out to
/// `PreviewLayout`, which tells the editor where the panel is.
```
**In `Sources/GraphPanelPreview/PreviewRoot.swift`, replace:**
```swift
            SearchPaletteOverlay(model: model)
```
**with:**
```swift
            SearchPaletteOverlay(model: model)
            LibraryDragOverlay(model: model)
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter 'CreatorEditorTests|PanelPlacementTests|PaletteOverlayTests'`
Expected: all pass (8 new in `LibraryViewTests`, 1 new in `PanelPlacementTests`, 1 new in `PaletteOverlayTests`; `FloatingPaletteTests`, `LibraryTests` and `LibraryDragTests` still pass, since they read the canvas's frame from the model rather than hard-coding it). Then `swift test`: **947** (master + 46). Also `swift build --product GraphPanelPreview` and `swift build --product MetalCreatorApp` succeed.

- [ ] **Step 6: Commit**

```bash
swiftlint lint --strict   # must report 0 violations
git add Sources/CreatorEditor/GraphPanelLayout.swift Sources/CreatorEditor/EditorModel+Placement.swift \
        Sources/CreatorEditor/PaletteEntryLabel.swift Sources/CreatorEditor/PaletteEntryRow.swift \
        Sources/CreatorEditor/LibraryItem.swift Sources/CreatorEditor/LibrarySectionHeader.swift \
        Sources/CreatorEditor/LibraryRow.swift Sources/CreatorEditor/NodeLibraryView.swift \
        Sources/CreatorEditor/GraphPanelBody.swift Sources/CreatorEditor/LibraryDragOverlay.swift \
        Sources/CreatorEditor/GraphPanel.swift Sources/CreatorEditor/GraphPanelHeader.swift \
        Sources/CreatorEditor/GraphPanelInput.swift Sources/CreatorApp/AppRoot.swift \
        Sources/GraphPanelPreview/PreviewRoot.swift \
        Tests/CreatorEditorTests/LibraryViewTests.swift Tests/CreatorEditorTests/PanelPlacementTests.swift \
        Tests/CreatorAppTests/PanelPlacementTests.swift Tests/CreatorAppTests/PaletteOverlayTests.swift
git commit -m "feat(editor): the node library in the graph panel: a column or a strip, click or drag to add"
```

---

### Task 5: MetalUI gaps, human checks, errata and project notes

Records the milestone: gaps EP-a and EP-b (and that the library's drag and its tooltips are not gaps), human-check group EP, Errata (editor polish), the CLAUDE.md rules, and the roadmap row.

**Files:**
- Modify: `docs/metalui-gaps.md`, `docs/verification/human-checks.md`, `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`, `CLAUDE.md`, `docs/superpowers/roadmap.md`

**Interfaces:** none (documentation). It names, as written in Tasks 1–4: `GraphPanelLayout`, `PaletteLayout`, `EditorModel.placement`, `AppModel.panelPlacement`, `PreviewLayout`, `SearchPaletteOverlay`, `PaletteDock`, `ViewState.showsLibrary`, `EditorModel.windowPressed(at:)`, and the test names each check pins.

- [ ] **Step 1: Log the MetalUI gaps**

**Append to `docs/metalui-gaps.md`:**
```markdown

## Hit by editor polish (floating palette, node library), 2026-10-08

Labelled EP-a… so they don't clash with the labels above. Checked against MetalUI `c62d6ba` (C7 merged). Two
things the design expected to be gaps are not. Tooltips: `.help(_:)` (ruling `MN-P`, after the pointer rests 1 s)
shows a library type's inputs → outputs. The library's drag: each row's one `DragGesture(minimumDistance: 0,
coordinateSpace: .global)` reports window points (C7), so the release is mapped onto the canvas with the host's
placement, no row frame needed, and the model tells a click (under 10 pt) from a drag. MetalUI's drag and drop
(`draggable(_:)`, `dropDestination(for:action:isTargeted:)`, rulings `DN-*`) is deliberately not used: a draggable
that leaves the window becomes a system drag (`NSDraggingSession`, divergence 101), which the design ruled out, and
it starts on any move with no slop, ahead of a click (`DN-D`).

- **EP-a. No element frame in window coordinates, no hover coordinate space, and no window size** (adds to M4-a).
  The add-node palette floats over the window with its top-left corner at the pointer and flips at the window's right
  and bottom edges, so it needs the pointer in window points and the window's size; a click on a library type adds it
  at the visible canvas's centre, so it needs the canvas's size. Gesture values can be in window points
  (`DragGesture(coordinateSpace: .global)`, `SpatialTapGesture`, C7), which the library's drag uses, but the palette
  opens from the hover pointer: `HoverPhase.active` is element-local only, nothing reports an element's frame
  (no `onGeometryChange`), and nothing reports the window's size. Stopgap: the panel's insides
  are computed (`GraphPanelLayout`; the header and the library are framed to it), and the host reports the panel's
  frame and the window's size through `EditorModel.placement`: the app from `AppLayout.graphPanelFrame` and the
  viewport's recorded draw size (the viewport fills the window, M4-a), `GraphPanelPreview` from a window kept at one
  size (`PreviewLayout`). Known limits: before the viewport's first draw the palette opens at the canvas-local point
  unflipped; resizing the window while the palette is open leaves it where it opened; a refusal line under the
  canvas makes the "visible centre" half a line low. Wanted: `onGeometryChange(for:of:action:)` with a global or
  named coordinate space (SwiftUI's `.global`, `coordinateSpace(_:)`), a coordinate space for `onContinuousHover`'s
  location, and the window's size in the environment.
- **EP-b. No plain anchored overlay that dismisses on an outside press.** `.popover` is placed against its anchor
  and dismissed by an outside press or Escape (`MN-N`), but it draws its own chrome (the `.surface` panel, border and
  default shadow, a per-frame cost over moving content, PERF-a) and anchors to an element's edge, not to a point.
  The palette wants glass chrome, its top-left corner at the pointer, no shadow. Stopgap: the host draws
  `SearchPaletteOverlay` last in its root `ZStack` (in the app inside `PaletteDock`, which contributes the `Panel`
  key context so F, + and − type into the search field); a transparent backdrop with an empty `DragGesture` and a
  claiming `.onScrollWheel` keeps a press or a scroll on the palette's padding from reaching the canvas, the
  inspector or the viewport beneath; a press of any button outside is read from `Window.onInput`'s `.mouseDown`,
  `.rightMouseDown` and `.otherMouseDown` (`GraphPanelInput.handle(_:)` → `EditorModel.windowPressed(at:)`). Known
  limits: a press into a text field or onto a slider, and a right-click that opens the viewport's context menu, are
  claimed before `onInput`, so they don't close the palette (Escape, a canvas press, or any other press does); a
  pinch over the palette reaches what is under it, where nothing takes a pinch yet (gap 2). Wanted: a chrome-less popover style (SwiftUI's
  `.presentationBackground(.clear)` / a plain `popoverStyle`) with a point anchor (`attachmentAnchor: .point(_:)`),
  or an outside-press callback for an overlay.
```

- [ ] **Step 2: Add the human checks**

**Append to `docs/verification/human-checks.md`:**
```markdown

## Group EP — editor polish: the floating palette and the node library

**Status: NOT RUN.** Following MetalUI's convention (`../MetalUI/docs/verification/human-checks.md`).

Run `swift run MetalCreatorApp` (EP-1–EP-9) and `swift run GraphPanelPreview` (EP-10).

- [ ] **EP-1 The palette floats at the pointer.** Dock the graph at the bottom. With the pointer over the canvas,
  near its bottom-left, press Tab: the palette opens with its bottom-left corner at the pointer, reaching up over the
  viewport, every row and the search field visible, nothing clipped by the panel's edge. Escape. Move the pointer
  near the canvas's right end (under the inspector) and press Space: it opens to the pointer's left, fully visible,
  over the inspector. Dock left and press Tab near the canvas's top-left: its top-left corner is at the pointer. The
  graph panel never moves or resizes while it is open. Pinned: `FloatingPaletteTests`,
  `thePaletteIsPaintedOverEverythingWhereItWasPlaced`. **Observed:**
- [ ] **EP-2 The palette's keys and rows.** Open it with Space: ten rows show and the caption says how many more.
  Press ↓ twelve times: the rows scroll to keep the highlight in view; ↑ scrolls back. Type "ex": the rows narrow
  and the palette keeps its size and place. Type "f+": they go into the field (the viewport neither frames nor
  zooms). Press Return: the node is added where the pointer was when the palette opened (not at the palette's
  corner) and selected; ⌘Z removes it in one step. Pinned: `theRowsScrollToKeepTheHighlightInView`,
  `atTheBottomDockItFlipsUpAndAddsAtThePressPoint`; the key context is this check only (gap M6-e). **Observed:**
- [ ] **EP-3 Closing the palette.** Open it, then click empty viewport: it closes (and the viewport takes the
  click). Open it, click a top-bar button: it closes. Open it, click the canvas: it closes. Open it, right-click or
  middle-click the canvas or the inspector: it closes. Open it and click its glass padding or caption: it stays open
  and nothing under it reacts. Open it over the inspector (near the window's right edge) and scroll over it: the
  inspector doesn't scroll. Open it and click into an inspector field, or right-click the viewport (its context menu
  opens): known, it stays open (gap EP-b); Escape closes it. Pinned: `aPressOutsideClosesItAndOneInsideDoesNot`,
  `theWindowsPressesReachThePaletteUnclaimed`. **Observed:**
- [ ] **EP-4 The library's place.** A new window shows the library, captioned "Nodes" above its "Search nodes" field:
  docked at the bottom, a column at the canvas's left edge; docked left, a strip across the canvas's top. It lists Value, Profile, Solid, Selection,
  Feature and Output, each under a header in that category's node-header colour, and scrolls when it doesn't fit.
  Press Library in the header: it goes and the canvas takes its room; press it again: it's back. Hide it, save, and
  reopen the file: it's still hidden, and the top bar never showed "— Edited" for it. Pinned: `LibraryViewTests`,
  `itIsShownByDefaultAndItsVisibilityIsSavedButNotAnEdit`. **Observed:**
- [ ] **EP-5 Click to add.** Pan and zoom the canvas, then click Extrude in the library: an Extrude appears in the
  middle of the visible canvas, selected. Click it a few more times: each lands near the middle, wholly in view, none
  overlapping, and once there's no free room in view the next lands in the middle anyway. ⌘Z removes them one by one.
  Click a row with a slight trackpad wobble: it still adds (no ghost appears). Pinned:
  `aClickAddsTheTypeCentredInTheVisibleCanvasAsOneStep`, `aClickedTypeIsNudgedOffTheNodesAlreadyThere`,
  `aClickedTypeStaysInViewWhenTheCentreIsCrowded`, `aClickThatMovesUnderTheThresholdStillAddsAtTheCentre`.
  **Observed:**
- [ ] **EP-6 Drag to add.** In both docks, drag Fillet from the library onto the canvas and let go: a Fillet lands
  with its top-left corner where you let go, selected; ⌘Z removes it. While dragging, a flat copy of the row follows
  the pointer (its top-left corner at the pointer), over the canvas, the viewport and the inspector, with no shadow.
  Drag a type and let go over the library itself, the viewport, the inspector, or outside the window: nothing is
  added and the ghost goes. Dragged out of the window it stays MetalUI's own drag (no system drag image, nothing in
  another app reacts). Pinned: `LibraryDragTests`, `aRowsGestureIsAZeroDistanceDragInWindowPoints`,
  `theDragGhostIsDrawnAtThePointerOnlyWhileDragging`, `aDraggedLibraryTypeIsPaintedOverTheWindow`; the gesture in a
  scrolling list is this check only. **Observed:**
- [ ] **EP-7 Hover help.** Rest the pointer on Extrude in the library: after about a second a tooltip reads
  "Extrude: profile, distance, mode, reversed → solid". Search "fil": only Selection ▸ Edge Filter and Feature ▸ Fillet
  stay (the palette's matches for "fil"); clear the field: everything is back. Pinned: `hoverHelpNamesInputsThenOutputs`,
  `theSearchIsThePalettes`. **Observed:**
- [ ] **EP-8 Themes.** View ▸ Theme ▸ Alucard: the library's background, headers and text, and the palette's glass,
  rows and caption, all take Alucard's colours at once; no glow or shadow anywhere. Pinned:
  `theLibraryRedrawsInTheChosenTheme`, `aSectionHeaderIsItsCategorysHeaderColour`, `theLibraryRasterizesNothing`.
  **Observed:**
- [ ] **EP-9 Still quick.** With the library shown, drag a node around the §7.2 bracket's graph, drag a library
  type across the window, and scroll the library: it feels as it did before the library (PERF-b still rebuilds the whole window; the library's `List`
  builds only the rows in view). **Observed:**
- [ ] **EP-10 The preview.** In `GraphPanelPreview` (its window keeps one size), EP-1's placement holds in both
  docks, and the library works as in EP-4–EP-7 with the preview's nine node types. **Observed:**
```

- [ ] **Step 3: Record the errata in the spec**

**Append to `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`:**
```markdown

## Errata (editor polish)

User-approved design, 2026-10-08 (plan `2026-10-08-editor-polish.md`).

- §6.2's add-node palette (Tab or Space "at the cursor") floats over the whole window, above the canvas, the
  viewport and the inspector, and takes no part in the panel's layout. Its top-left corner is at the pointer; it
  flips to the pointer's left at the window's right edge and above it at the bottom edge, and is clamped inside the
  window as a last resort. It has a fixed size: ten rows, which ↑/↓ scroll, and a caption line ("No matching
  nodes", or how many more match). The node it adds lands at the canvas point where it opened. Escape and a press
  outside it close it; a press into a text field or onto a slider doesn't (docs/metalui-gaps.md EP-b).
- §6.2 gains the node library ("Nodes"): the registry's types under a search field (the palette's search), grouped
  by category under headers in the category colours (§6.6). Docked at the bottom it is a column at the canvas's left
  edge; docked left, a strip across the canvas's top (the side the graph flows from, across the panel's short axis).
  It is shown by default; the header's Library button hides and shows it, and the choice is saved in the document's
  view state (`ViewState.showsLibrary`, an optional key older readers ignore, so §4.5's format version stays 3;
  toggling it is not an edit). A "Nodes" caption heads it. A click adds the type centred in the visible canvas, or
  at the nearest spot in view where it overlaps no node; dragging it onto the canvas (a MetalUI `DragGesture` inside
  the window, no system drag and drop; a press moving under 10 pt is a click) adds it with its top-left corner at
  the release point, and a release anywhere else adds nothing; each add is one undo step. Hovering a type shows its inputs → outputs ("Extrude: profile, distance, mode,
  reversed → solid") as a MetalUI tooltip.
- The graph panel's insides are laid out to computed numbers (`GraphPanelLayout`), and the host reports where the
  panel is in its window (`EditorModel.placement`), because MetalUI measures nothing (docs/metalui-gaps.md M4-a,
  EP-a). `GraphPanelPreview`'s window keeps one size for the same reason.
```

- [ ] **Step 4: Update CLAUDE.md and the roadmap**

**In `CLAUDE.md`, replace:**
```markdown
M6 (app shell) code is done; its human checks (group M6) are pending.
```
**with:**
```markdown
M6 (app shell) code is done; its human checks (group M6) are pending.
Editor polish (the floating add-node palette and the node library) code is done; its human checks (group EP) are pending.
```
**In `CLAUDE.md`, replace:**
```markdown
Editor geometry is computed by `NodeLayout`, never measured; views are framed to it so
drawing and hit testing agree. Node positions are stored left-to-right; the left dock draws their transpose.
```
**with:**
```markdown
Editor geometry is computed by `NodeLayout`, never measured; views are framed to it so
drawing and hit testing agree. Node positions are stored left-to-right; the left dock draws their transpose.
The graph panel's insides (header, node library, canvas) are computed by `GraphPanelLayout` and the palette's size
by `PaletteLayout`; the host says where the panel is in its window through `EditorModel.placement` (the app:
`AppModel.panelPlacement`, from `AppLayout` and the viewport's size; the preview: `PreviewLayout`, a fixed-size
window). The add-node palette floats over the window: the host draws `SearchPaletteOverlay` last (the app inside
`PaletteDock`, for the `Panel` key context), then `LibraryDragOverlay`, never inside the canvas. A library row is a
`PaletteEntryLabel` under one `DragGesture(minimumDistance: 0, coordinateSpace: .global)`
(`GraphPanelInput.libraryGesture(for:)`; not a `Button`, whose click would hold the drag off), and the model tells a
click from a drag (`LibraryDrag.threshold`); never MetalUI drag and drop (it becomes a system drag outside the
window). The library's visibility is `ViewState.showsLibrary` (an optional key: no format bump).
```
**In `docs/superpowers/roadmap.md`, replace:**
```markdown
| M6 | App shell + acceptance demo (§7.2 bracket, STEP/STL export) | ✅ code merged; human checks M6 pending | M3, M4, M5 |
```
**with:**
```markdown
| M6 | App shell + acceptance demo (§7.2 bracket, STEP/STL export) | ✅ code merged; human checks M6 pending | M3, M4, M5 |
| Polish | Editor polish: the add-node palette floats over the window at the pointer (flipping at the edges); a node library ("Nodes") in the graph panel, shown by default, click or drag to add (plan `2026-10-08-editor-polish.md`, Errata (editor polish)) | ✅ code done; human checks EP pending | M5, M6 |
```

- [ ] **Step 5: Check and commit**

Run: `swift test` (still **947**) and `swiftlint lint --strict` (0 violations). Spot-check that the tests the new human checks cite exist: `grep -rE "func (theRowsScrollToKeepTheHighlightInView|thePaletteIsPaintedOverEverythingWhereItWasPlaced|aReleaseOnTheCanvasAddsTheTypeThereAsOneStep)\(" Tests | wc -l` prints 3.

```bash
git add docs/metalui-gaps.md docs/verification/human-checks.md \
        docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md CLAUDE.md docs/superpowers/roadmap.md
git commit -m "docs: editor polish: MetalUI gaps EP-a and EP-b, human checks EP, errata, CLAUDE.md, roadmap"
```

---

## Self-review

1. **Design coverage.** Floating palette: window-level overlay above canvas, viewport and inspector (Task 2, `PaletteDock` last in `AppRoot`; `PreviewRoot` too), never in the canvas's layout (`GraphCanvas` no longer holds it; fixed size), top-left at the pointer converted from canvas-local through the placement (Tasks 1, 2), flips at the right and bottom edges and clamps (Task 2), the node lands at the press point (Task 2), Tab/Space, typing, ↑/↓/Return, Escape kept (unchanged `GraphKeyBindings`, `GraphPanelInput.keymap`; Escape and Return tests in `KeyCommandTests` and `SearchPaletteTests` still pass), click outside closes (Task 2). Tests asked for: placement under the cursor, flipping at each edge, overlay order above the viewport (render), add-at-press-point — all in Task 2. Node library: left-edge column / top strip with the reasoning (Decision 3, Task 4), shown by default, Library header button (Task 4), visibility in the view state with the format decision documented (Decision 4, Task 3), grouped by the six categories with theme-coloured headers and a search field (Tasks 3, 4), click at the visible centre nudged off other nodes and kept in view (Task 3), drag to the drop point with a `DragGesture` inside the window, no system drag and drop (Decision 1, Tasks 3, 4), hover inputs → outputs (Decision 2, Tasks 3, 4), theme-aware, no glow (Task 4 render tests), one undo step each (Task 3), model tests in `EditorModel` and render tests (Tasks 3, 4), human checks (Task 5), the shared `PaletteSearch` (Task 3), MetalUI performance (Decision 11). The library carries the name "Nodes" as its caption (Decision 13). Gaps logged (Task 5): EP-a, EP-b; the gesture drag and tooltips recorded as present, and why MetalUI drag and drop isn't used.
2. **Placeholders.** None: every code step is complete file contents or an exact replacement, and the replay applied each one verbatim.
3. **Type consistency.** `canvasFrame(inPanelOf:)` (Task 1) is replaced in Task 4 by `canvasFrame(inPanelOf:flow:showsLibrary:)`, and Task 4 rewrites its two callers (`EditorModel+Placement`, `PanelPlacementTests`); `PaletteEntryRow` (Task 2) is replaced in Task 4 by a `Button` around the new `PaletteEntryLabel`, with the same initializer, so `SearchPaletteView` is untouched; `windowOrigin`, `firstVisible`, `paletteFrame`, `windowPressed(at:)`, `libraryGesture(for:)`, `moveLibraryDrag(_:from:to:)`, `endLibraryDrag(_:from:at:)`, `dropFromLibrary(_:atScreen:)`, `LibrarySection.title(for:)` are spelled the same in every task and test.
4. **Review Focus.** Each line names its tests; lines 2 and 3 also need a real window, which human checks EP-2 and EP-3 cover (gap M6-e).

## Risks

- **A library row is a gesture, not a `Button`** (Decision 1). It isn't keyboard-focusable, and its click is the model's: a press that moves 10 pt or more and is released off the canvas adds nothing, like a cancelled drag. The drop point relies on the host's placement (`canvasFrameInWindow`), as the palette does: before the viewport's first draw a drag adds nothing (EP-a). The gesture's hit testing inside a scrolling `List` is MetalUI's (human checks EP-5, EP-6).
- **The computed layout must match what MetalUI lays out.** The node-at-origin render test pins the canvas origin with and without the library in both docks, and `thePanelIsDrawnWhereTheLayoutSays` pins the app's panel frame; anything that changes `PanelArea`, `GraphDock`, `GlassPanel` or the header's height must keep `AppLayout`/`GraphPanelLayout` in step. A header too wide for a narrow panel (240 pt minimum) is clipped at 28 pt rather than growing (it already crowds at that width; the new Library button adds one more).
- **The window's size is the viewport's last draw.** Before the first draw, or while a resize hasn't redrawn the viewport, the palette may open unflipped or slightly off; it is placed once and doesn't follow a resize while open (EP-a).
- **Outside presses on text fields and sliders, and a right-click opening the viewport's menu, don't close the palette** (EP-b). Escape and every other press do. A pinch over it reaches what is under it, where nothing takes a pinch yet.
- **Performance.** A cold frame with the 26 built-ins' library costs about +3.5 ms release / +14 ms debug (measured headless on the first draft's rows; not re-measured); a warm frame builds only the rows in view, which couldn't be measured headless (no public `Window`, M6-e). Human check EP-9; if it drags, shrink the rows (drop the dot) or hide the library while dragging.
- **The library's `List` and the drag from inside it** are MetalUI behaviours covered only by its own tests and the demo here; human checks EP-4 and EP-6. Each move of a library drag past the threshold rebuilds the window (PERF-b), as a node drag does; human check EP-9.

## What comes next

Run human-check group EP (and the pending M5/M6 groups) on `MetalCreatorApp` and `GraphPanelPreview`. When MetalUI ships geometry (EP-a) or a plain popover (EP-b), replace `EditorModel.placement`, `PreviewLayout`'s fixed window and the `.mouseDown` close with them.

