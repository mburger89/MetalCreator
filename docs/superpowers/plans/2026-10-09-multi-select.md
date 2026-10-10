# Multi-select Polish (A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Select many nodes and act on them as one: ⌘-click toggles, ⇧ adds, a ⇧-box adds and a ⌘-box toggles (whether a plain drag on empty canvas box-selects or still pans is **the user's decision, taken at Gate G before Task 3**), ⌘A selects all, Esc clears, arrow keys nudge (one undo step per key-down run), F frames the selection in the graph canvas, every drag moves (or ⌥-copies) the whole selection, all on one selection model that canvas comments (sub-project B) join without reworking any of it.

**Architecture:** The selection becomes a value, `CanvasSelection` (nodes now; B adds comment ids), stored as `EditorModel.canvasSelection`; the existing `selection: Set<NodeID>` stays as its node part, so every current reader (inspector, app, scene, handles) is untouched. Every gesture and key goes through one small set of `EditorModel+Selection` members (`select(_:mode:)`, `allItems`, `items(for:)`, `items(intersecting:)`, `positions(of:)`, `moveCommands(from:by:)`, `bounds(of:)`), which are the members B extends (B's few other edits, a frame's resize drag and comment ghosts, are listed under "Interface for B"). A drag starts generically: on a socket it wires, on anything `items(for:)` maps to items it selects them then moves or ⌥-copies the selection, and on nothing it box-selects or pans, so a new kind of hit needs no pointer change. Behaviour stays in the model and is tested headless; the only view change is the box and ghost layers reading the new interaction values, and the only app change is `AppInput` letting F through to the graph while the pointer is over its canvas.

**Tech Stack:** Swift 6.4 (language mode 6, strict concurrency), SwiftPM, Swift Testing, MetalUI at `../MetalUI` `9ad2254` or later (verified on `2155f1e`, which contains it; C7's `DragGesture.Value.modifiers`; `KeyEvent.isRepeat`; the window keymap, `onAction` and `onInput` fallback).

**Gate G (before Task 3 and Task 7):** the user decides how box select is reached (Key decision 4, "Gate G" below). Tasks 1, 2 and 4–6 don't depend on it; Task 3 and Task 7's box wording do. Don't run Task 3 or Task 7 until the answer is recorded in this plan.

**Spec:** `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` §3 (sub-project A; §2 for the order A → C1 ∥ B → C2, §7 and §9 for what B needs from A), under the parent spec `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` with all its Errata (§6.2: "Click to select, Shift-click to extend, ⇧-drag on empty canvas to box-select. A plain drag on empty canvas pans."; Errata (M5) on Tab). Reference for behaviour (read-only): `../MetalNodes` `MetalNodesKit/Sources/MetalNodesUI/Editor/EditorModel+Selection.swift` (`SelectionMode`, `select(nodes:comments:mode:)`, `nudgeSelection`), `Canvas/InputModifiers.swift` (⌘ toggles before ⇧ adds), `Canvas/NodeView.swift` (a press without movement on a selected node collapses, ⌘ toggles), and its spec §18.6 (arrows 1 pt / ⇧ 10 pt, F frames the selection with 40 pt padding).

**Files shared with other tracks** (multi-select runs beside groups-core, sketcher-s5b, kernel-invalid-blends and m7-measure; everything else here is inside `Sources/CreatorEditor`, `Tests/CreatorEditorTests` and the two `CreatorApp` files below):
- `Sources/CreatorEditor/EditorModel.swift` — **sketcher-s5b** Task 8 adds two stored properties after `scrollGlideIgnored` (`now`, `lastNodeClick`). This plan replaces the `selection` property (Task 1), and adds `pressCancelled` after `pressModifiers`, `nudgeKey` after `pendingEntry`, and `cancelPress()`/`isPressCancelled` after `endPress()` (Tasks 4, 5). Different lines: merges cleanly.
- `Sources/CreatorEditor/EditorModel+Pointer.swift` — **sketcher-s5b** Task 8 inserts one line (`if interaction == nil { pairClick(on: press.hit, at: press.point, modifiers: press.modifiers) } else { lastNodeClick = nil }`) between `pointerReleased`'s `guard let press = currentPress else { return }` and its `switch`, and its replace block quotes the `case nil: click(press.hit, extending: …)` line after it. This plan changes that guard (Task 4: `guard let press = currentPress, !isPressCancelled else { endPress(); return }`) and that `case nil:` line (Task 2: `case nil: click(press.hit, mode: SelectionMode(press.modifiers))`). Whichever merges second keeps this plan's guard, then s5b's line, then this plan's `case nil:`, **and makes the cancelled-press branch clear the pending click too** — `guard let press = currentPress, !isPressCancelled else { lastNodeClick = nil; endPress(); return }` — so a node click just before an Esc-cancelled drag can't pair with the next click as a double click (s5b's own `else { lastNodeClick = nil }` never runs on that early return). s5b's `pairClick` already lets any modifier start no pair, so ⌘- and ⇧-clicks never make a double click. `click(_:extending:)` itself is not in s5b's diff.
- `Sources/CreatorEditor/CanvasLayers.swift` — **m7-measure** may add culling here (CLAUDE.md's M7 carry-over names `CanvasLayers` the hot path). This plan changes two lines (the box's pattern, the ghosts' `start.nodes`); sub-project B later adds comment ghosts to `ghosts`.
- `Sources/CreatorEditor/EditorModel+Editing.swift`, `NodeClipboard.swift` — **groups-core** (C1) may route copy and paste through groups (spec §9: "groups referenced by pasted nodes travel with them"); this plan changes `clipboard(of:)` to take a `CanvasSelection` and `insert(_:offset:)` to return one. `NodeClipboard` itself is untouched.
- `Sources/CreatorApp/AppInput.swift` and `Tests/CreatorAppTests/AppInputTests.swift` — one line of `handleAction` and its doc comment; one assertion, one test name and one new test.
- `CLAUDE.md` (project state, the `CreatorEditor` bullet, the app-shell input stopgap sentence), `docs/superpowers/roadmap.md` (one new row after "Viewport: frame in the model area"), `docs/verification/human-checks.md` (GI-8's F clause, and a new group MS at the end), and `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` (a new "Errata (A: multi-select)" at the end; groups-core adds its own errata to the same file). Every track edits CLAUDE.md, the roadmap and the human checks; whichever merges second re-applies its lines.
- **Not touched:** `Package.swift`, `../MetalUI`, `docs/metalui-gaps.md` (no new gap: see "MetalUI gaps"), `Sources/CreatorGraph` (selection is view state, never a `GraphCommand`), `Sources/CreatorViewport`, `GraphPanelInput.swift` (keys already reach the model through `handle(_:)`).

## Global Constraints

- Platforms `.macOS(.v26)`; `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`: data races are compile errors. No `@unchecked Sendable` or `nonisolated(unsafe)`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), never XCTest.
- Models are `@MainActor @Observable`; behaviour lives in models, views are thin MetalUI `Component`s (CLAUDE.md, `CreatorEditor` bullet). `CreatorEditor` depends on Graph/Kernel/Geometry, CreatorStyle and MetalUI, **not** on `CreatorNodes`.
- One type per file; no force unwraps or `try!`; no GCD; `FormatStyle` for user-facing numbers.
- Editor geometry is computed by `NodeLayout`, never measured; hit testing and draw order are the model's (`EditorModel.hitTest`, `drawOrder`) and agree: "Selected items draw last and are hit-tested in the same order (existing rule)" (spec §3).
- "Selection stays view state: never undone, not saved (as today)" (spec §3): no `GraphCommand`, no `ViewState` key, no format bump.
- "the existing shortcut rules stay" (task brief): a plain drag on empty canvas pans (parent §6.2); Tab, Space, +, − and the viewport's `!Panel` key context are unchanged; graph keys arrive through the window's `onInput` fallback, so a focused text field keeps its keys.
- MetalUI gaps are logged in `docs/metalui-gaps.md` and fixed in MetalUI, never worked around here. Never modify `../MetalUI`; never edit `Package.swift`'s MetalUI path. Run every command from the worktree root.
- **The full check** (every task ends with it):

  ```bash
  swift build --build-tests 2>&1 | grep 'warning:' | grep -v 'linking with dylib' | grep -v 'ContextMenuTests.swift' | sort -u
  swiftlint lint --strict --quiet
  swift test > .build/full-test.log 2>&1; echo "exit $?"
  grep -cE 'recorded an issue|failed after' .build/full-test.log
  grep -c 'Test run with' .build/full-test.log
  grep 'Test run with' .build/full-test.log | awk '{s += $5} END {print s}'
  ```

  Expected: the first two print nothing (master's only compiler warning is `ContextMenuTests.swift`'s "'underPointer' mutated after capture by sendable closure"; OCCT's `ld: warning`s are expected), then `exit 0`, `0`, `11`, and the task's test count. Swift Testing marks failures with glyphs, not ✘, so the `grep -cE` line is the failure check.

## Key decisions

1. **One selection value, nodes now, comments later.** `CanvasSelection { var nodes: Set<NodeID> }` with `isEmpty`, `isSuperset(of:)` and `applying(_:mode:)`; `EditorModel.canvasSelection` stores it (its `didSet` keeps today's "commit a typed value, end coalescing"). `selection: Set<NodeID>` becomes a computed view of its nodes whose **setter replaces the whole selection**, so the dozen places that assign `selection = [id]` (paste, add node, the app's Show Producing Node and picking) keep their meaning ("select exactly this") once comments exist. Moves carry `SelectionPositions { var nodes: [NodeID: Vector2] }` (stored positions at drag start). B adds `comments: Set<CommentID>` / `comments: [CommentID: Vector2]` with empty defaults and extends the "B adds" members (see "Interface for B" for its few other edits).
2. **Modes.** `SelectionMode(modifiers)`: ⌘ → `.toggle` (wins over ⇧), ⇧ → `.add`, else `.replace` (⌥ is duplication, not a mode), as MetalNodes. A click (no drag) applies its hit's items with the press's mode: plain on a selected node collapses the selection to it, ⌘ toggles it out, **⇧ keeps it** (before this plan ⇧-click on a selected node removed it; spec §3 "⇧ keeps adding"). On empty canvas only a plain click clears.
3. **A drag starting on a node** (generically: on any hit `items(for:)` maps to items, after `.socket` has taken wiring) selects it first if it isn't selected (plain: alone; ⇧ or ⌘: added — a ⌘-drag must not toggle the dragged node out) and then moves every selected item, or with ⌥ ghosts them all and copies on release; the copy happens only once the press has moved `dragThreshold` (today's rule), so an ⌥-click copies nothing.
4. **Box select: the user decides at Gate G.** The spec's §3 says "Existing: … a drag on empty canvas box-selects" and asks for "no modifier replaces, ⇧ adds, ⌘ toggles", but the parent §6.2 and today's code pan on a plain drag (only a ⇧-drag box-selects), and the brief keeps the existing shortcut rules. The two can't both hold, so this is the user's call, asked before Task 3 (see "Gate G"); nothing here or in the spec's errata treats either answer as settled before then. Either way the box's **mode is decided when the drag starts, from the modifiers held as it crosses `dragThreshold`** (`beginInteraction`'s `modifiers`, as ⌥-duplicate reads them; a click instead reads `press.modifiers`): ⇧ adds, ⌘ toggles each node the box covers (⌘ wins when both are held). Letting go of the key before the release changes nothing — a box that turned into "replace" when ⇧ came up a moment before the button would silently drop the selection it was adding to. It is recomputed from the selection the drag began with (`base`) at every step, so a node the box leaves again is as it was. Task 3 as written implements **answer (a)**: a box starts on empty canvas with ⇧ or ⌘ held (⌘-drag is new), a plain drag still pans, and `SelectionMode.replace` exists in the model only (to replace, click empty canvas first). **Answer (b)** — a plain drag box-selects, replacing — changes only `emptyCanvasDrag(at:modifiers:)` (every drag on empty canvas box-selects in `SelectionMode(modifiers)`) and moves the pan to the **middle button** (a second canvas gesture in `GraphPanelInput` beside `canvasGesture()`, `DragGesture(minimumDistance: 0, button: .middle)`, as the viewport's middle drag pans, VC3; two-finger scroll already pans, GI-1). Space-drag (MetalNodes) isn't offered: Space opens the palette. Gate G lists what (b) changes.
5. **Keys** stay in `GraphKeyBindings` → `GraphKeyCommand` → `EditorModel.perform(_:)` through the window's `onInput` fallback, which runs only when no focused field claimed the key — so a focused inspector or palette field keeps ⌘A (MetalUI's `TextEditing` selects its text), arrows (caret) and F (types). New commands: `.selectAll` (⌘A; ⇧⌘A unbound), `.nudge(Vector2, isRepeat:)` (←↑→↓ with no modifier but ⇧), `.frameSelection` (F, no modifier). The palette's navigation keys win while it is open (↑/↓ move its highlight; ←/→ and ⌘A go to its field). All three act only while the panel is visible (with it hidden, ⌘A then Delete would erase nodes no one can see) and pass the key on otherwise.
6. **Nudge** moves by 1 display canvas point, 10 with ⇧, the way the arrow points on screen (`flow.stored`, so the left dock's transpose is honoured), through `moveCommands`. **One undo step per key-down run**: a key-down that isn't an auto-repeat (`KeyEvent.isRepeat == false`) ends coalescing and starts a new key (`nudge-<UUID>`); its auto-repeats reuse it, so holding → is one step and three taps are three. Anything that ends coalescing meanwhile (a press, a selection change, Undo) makes the next repeat a new step, so a step never mixes two selections' moves. No key-up is needed.
7. **Esc**, in order: closes the palette (today); **during a drag** cancels it if it hasn't changed the document — a wire being dragged is dropped, ⌥-drag ghosts vanish, a box puts back the selection it began with — and ignores the rest of that press (no click, no connect on release); a pan or a move goes on (its steps are already in the document) and Esc is claimed so it can't clear the selection mid-move; else **clears the selection**; else passes on. Cancelling a pick (`PickBanner`'s Esc button), a sketch's Esc and the theme editor's Esc are buttons with shortcuts, which MetalUI runs before `onInput`, so they still come first ("after closing the palette, ending a wire drag, or cancelling a pick, as today").
8. **F frames the selection in the graph canvas when the pointer is over it.** `AppInput.handleAction` now declines every viewport key action — F as well as + and − — while `editor.pointerLocation != nil`, so F falls through to `onInput` and the graph's binding; elsewhere F still frames the viewport (spec: "the viewport's F is unchanged"). The graph's F needs the pointer over the visible canvas (`perform` returns false otherwise, as Tab's palette does). It fits the selected items' bounds — **everything when nothing (still on the canvas) is selected**, like the viewport's "F frames the selection, or everything" — in `visibleCanvasSize` with 40 screen points of padding, centred, the zoom clamped to `CanvasTransform.zoomRange` (MetalNodes §18.6). Immediate, no animation (the canvas transform is view state, written as a pan writes it).
9. **Draw and hit order**: unchanged code (`drawOrder`: unselected by id, then selected by id; `hitTest` walks it backwards). Task 1 pins it for a multi-selection; B draws comments in its own layers by the same rule.

## Interface for B (comments)

B (spec §7) adds `CommentID`, the `stickies`/`frames` on `Graph` and their `GraphCommand`s. To join the selection it changes only these, and every gesture and key above takes comments in unchanged:

```swift
// CanvasSelection.swift — add a stored set with an empty default and fold it into every member:
public var comments: Set<CommentID>                       // init(nodes: = [], comments: = [])
public var isEmpty: Bool                                  // nodes.isEmpty && comments.isEmpty
public func isSuperset(of other: CanvasSelection) -> Bool // both sets
public func applying(_ items: CanvasSelection, mode: SelectionMode) -> CanvasSelection  // both sets, same rule
// SelectionPositions.swift — add comment origins:
public var comments: [CommentID: Vector2]                 // stored canvas points of each frame's origin
public var isEmpty: Bool; public var items: CanvasSelection   // both
// EditorModel+Selection.swift — each member marked "B adds":
public var allItems: CanvasSelection                      // + every comment id on the current level
public func items(for hit: CanvasHit) -> CanvasSelection? // + the new comment hit cases (B adds them to CanvasHit)
public func items(intersecting rect: CanvasRect) -> CanvasSelection   // + comments whose rectangle meets rect
public func positions(of items: CanvasSelection) -> SelectionPositions  // + comment origins
public func moveCommands(from start: SelectionPositions, by delta: Vector2) -> [GraphCommand]  // + comment moves
public func bounds(of items: CanvasSelection) -> CanvasRect?           // + comment rectangles
// EditorModel+Editing.swift:
func clipboard(of items: CanvasSelection) -> NodeClipboard            // + the selected comments
func insert(_ clipboard: NodeClipboard, offset: Vector2) -> CanvasSelection?   // + the pasted comments' new ids
public func deleteSelection()                                         // + remove the selected comments, same batch
```

Unchanged for B: `select(_:mode:)`, `selectAll()`, `clearSelection()`, `canvasSelection`, `selection` (assigning it selects exactly those nodes and no comments), `SelectionMode`, `nudgeSelection(by:isRepeat:)`, `frameSelection()`, the selection keys' guards (`.deleteSelection`, ⌘C and ⌘D already test `canvasSelection.isEmpty`), the Esc order and every key binding; and in `EditorModel+Pointer` the click, select-then-move, ⌥-drag and box paths: `click(_:mode:)` and `beginInteraction` reach items only through `items(for:)` (a drag on `.socket` wires; on any hit `items(for:)` maps to items it selects them, then moves or ⌥-copies the selection; on `nil` it box-selects or pans), so B's comment hit cases need no Pointer edit for selecting or moving.

What B does add outside those members (spec §7):
- **Resizing a frame** (its bottom-right handle): a new `CanvasHit` case for the handle, taken in `beginInteraction` before `items(for:)` (beside `.socket`), a new `CanvasInteraction` case, and that case in the exhaustive switches of `update(to:from:)`, `pointerReleased` and `cancelInteraction()` (Task 4; a resize already performed into the document goes on, like a move), and a cursor for it in `canvasCursor` if it isn't the arrow.
- **Comment ghosts** in `CanvasLayers.ghosts` (it draws nodes only), and the comments' own layers.

## MetalUI gaps

None new. The plan relies on existing behaviour and logged gaps only: keys aren't scoped to the hovered canvas (M4-a, M5-b, MetalUI C9), so F over the canvas is `AppInput`'s existing hover veto widened from + and − to F; graph keys come from the `onInput` fallback, which a focused field pre-empts (as ⌘C/⌘V today). Whether MetalUI delivers Esc's key-down to `onInput` while the primary button is held is a human check (MS-4), not a known gap; if it doesn't, log it then.

## Review Focus

1. **A ⌘-drag on an already-selected node** must move the whole selection, not toggle the node out (and a ⌘-drag on an unselected node must add it, not toggle the rest) — `commandDragMovesTheSelectionAndKeepsIt`, `aModifiedDragOnAnUnselectedNodeAddsItAndMovesEverything` (Task 2).
2. **⌘A, an arrow or F with the panel hidden** must not select or move nodes no one can see (⌘A then Delete would erase the graph) — `selectAllDoesNothingWhileThePanelIsHidden` (Task 4), `withNothingSelectedOrThePanelHiddenTheKeyGoesOn` (Task 5), `fNeedsThePointerOverTheVisibleCanvas` (Task 6).
3. **Esc in the middle of a drag** must not clear the selection under a move (it would end the move's coalescing and split it in two undo steps) and must not connect a cancelled wire or count the release as a click — `escapeDuringAMoveKeepsItOneUndoStep`, `escapeEndsAWireDragWithoutConnectingAndKeepsTheSelection` (Task 4).
4. **A held arrow key** must be exactly one undo step, and a selection change during the hold must start a new step rather than fold another node's moves into the first — `aHeldArrowIsOneUndoStep`, `aRepeatAfterTheSelectionChangedStartsANewStep` (Task 5).
5. **An arrow or ⌘A in the middle of a move** must not split the move into two undo steps (a nudge ends coalescing and performs its own step; ⌘A changes the selection, whose `didSet` ends coalescing): while a drag is under way the selection keys are claimed and do nothing — `selectAllDuringAMoveKeepsItOneUndoStep` (Task 4), `aNudgeDuringAMoveKeepsItOneUndoStep` (Task 5), `fDuringADragIsClaimedAndChangesNothing` (Task 6).
6. **A stale selection** (a selected node removed by Undo, which never prunes the selection) must not crash or act on ghosts in drags, nudges, box select or F — `positionsAndMovesSkipItemsNoLongerOnTheCanvas`, `boundsCoverTheItemsDrawnFrames` (Task 1), `fWithOnlyAStaleSelectionFramesEverything` (Task 6).

## Risks left open

- **Box select waits on the user** (Gate G): the spec's "a drag on empty canvas box-selects … no modifier replaces" and the parent §6.2's "a plain drag on empty canvas pans" conflict. Task 3 implements answer (a); answer (b) changes `emptyCanvasDrag` and adds a middle-button pan (Gate G lists the rest). **⇧-click on a selected node now keeps it** instead of removing it (Key decision 2) — a behaviour change to an existing human-checked gesture (GI-5 only adds), recorded in the errata.
- **Graph keys still act in sketch mode**, as Delete, ⌘C and Tab do today: arrows nudge the Sketch node on the canvas and ⌘A selects every node. Harmless (undoable, view state), but a sketch-mode ⌘A or arrow binding (S5b+) must be a toolbar shortcut so it runs first.
- **Other keys during a drag are as today**: ⌘V, ⌘D, Delete and ⌘Z mid-move still act (and can split a move's undo step, or remove a node being dragged), as before this plan; only the new selection keys and Esc are claimed during a drag.
- **Esc during a drag** depends on MetalUI delivering the key-down while the button is held (MS-4).
- **The view glue isn't exercised headless** (gap M6-e): the box and ghost layers render in `GraphPanelRenderTests`, but MS-1…MS-8 drive them.

## Gate G: how box select is reached (the user's decision, before Task 3)

Ask the user, quoting both: spec 2026-10-09 §3 ("Existing: … a drag on empty canvas box-selects"; "Box-select modes: no modifier replaces, ⇧ adds, ⌘ toggles") and the parent spec §6.2 ("⇧-drag on empty canvas to box-select. A plain drag on empty canvas pans."). Record the answer here (date, words) before running Task 3 or Task 7.

- **(a) Keep "a plain drag pans"** (Task 3 as written): ⇧-drag adds, ⌘-drag (new) toggles; replacing is "click empty canvas, then ⇧-drag". Task 7's errata and MS-3 use their "(a)" text.
- **(b) A plain drag box-selects, replacing**; the pan moves to the middle button (and two-finger scroll, as today). Before running Task 3, revise it to: `emptyCanvasDrag(at:modifiers:)` returns `.boxSelecting(start:current:base:mode: SelectionMode(modifiers))` for every drag; a middle-button `DragGesture(minimumDistance: 0, button: .middle)` in `GraphPanelInput` beside `canvasGesture()`, calling a new `EditorModel.middleDragged(from:to:)`/`middleReleased()` that pans (and shows the closed hand, `canvasCursor`); `BoxSelectModeTests` gains `aPlainDragReplacesTheSelection` and a middle-drag pan test; the tests that pin a plain-drag pan change (`PointerTests.plainDragOnEmptyCanvasPans`, `PressModifierTests`, `CanvasCursorTests`' pan cases, `ScrollDuringDragTests`, `GraphPanelInputTests`' pan through the gesture); Task 7 rewrites GI-5's and GI-6's and M5-6's "drag empty canvas: it pans", the CLAUDE.md sentence on the canvas gesture, and uses the "(b)" errata text. Re-run the full check and recount before executing.
- **Answer:** _(pending — ask before Task 3)_

---

## File structure

| File | Task | Responsibility |
|---|---|---|
| `Sources/CreatorEditor/SelectionMode.swift` (create) | 1 | replace / add / toggle, from the modifiers held (a click's at its press, a drag's as it starts) |
| `Sources/CreatorEditor/CanvasSelection.swift` (create) | 1 | What is selected (nodes; B adds comments), combined by mode |
| `Sources/CreatorEditor/SelectionPositions.swift` (create) | 1 | Selected items' stored positions when a drag began |
| `Sources/CreatorEditor/EditorModel+Selection.swift` (create) | 1 | `select(_:mode:)`, `selectAll()`, `clearSelection()` and the "B adds" members |
| `Sources/CreatorEditor/EditorModel.swift` (modify) | 1, 4, 5 | `canvasSelection` + `selection` view; `pressCancelled`, `cancelPress()`; `nudgeKey` |
| `Sources/CreatorEditor/CanvasRect.swift` (modify) | 1, 6 | `union(_:)`, `centre` |
| `Sources/CreatorEditor/EditorModel+Pointer.swift` (modify) | 2, 3, 4 | Click modes, drags of the whole selection, box modes, Esc mid-drag |
| `Sources/CreatorEditor/CanvasInteraction.swift` (modify) | 2, 3 | `moving`/`duplicating` carry `SelectionPositions`; `boxSelecting` carries `base: CanvasSelection` and `mode` |
| `Sources/CreatorEditor/EditorModel+Editing.swift` (modify) | 2 | Clipboard of a `CanvasSelection`; inserts return one |
| `Sources/CreatorEditor/CanvasLayers.swift` (modify) | 2, 3 | Ghosts from `start.nodes`; the box's new pattern |
| `Sources/CreatorEditor/GraphKeyCommand.swift`, `GraphKeyBindings.swift` (modify) | 4, 5, 6 | ⌘A, arrows, F |
| `Sources/CreatorEditor/EditorModel+Commands.swift` (replace, then modify) | 4, 5, 6 | Routing, the selection keys, Esc's order |
| `Sources/CreatorEditor/EditorModel+Nudge.swift` (create) | 5 | Arrow nudges, one undo step per key-down run |
| `Sources/CreatorEditor/CanvasTransform.swift` (modify) | 6 | `framing(_:in:padding:)` |
| `Sources/CreatorEditor/EditorModel+Framing.swift` (create) | 6 | F: frame the selection |
| `Sources/CreatorApp/AppInput.swift` (modify) | 6 | F, + and − go to the graph over its canvas |
| `Tests/CreatorEditorTests/CanvasSelectionTests.swift` (create) | 1 | Modes, the model members, draw/hit order |
| `Tests/CreatorEditorTests/MultiSelectPointerTests.swift` (create) | 2 | Clicks and drags by mode |
| `Tests/CreatorEditorTests/BoxSelectModeTests.swift` (create) | 3 | Box modes |
| `Tests/CreatorEditorTests/SelectionKeyTests.swift` (create) | 4 | ⌘A and Esc |
| `Tests/CreatorEditorTests/NudgeTests.swift` (create) | 5 | Arrows |
| `Tests/CreatorEditorTests/FramingTests.swift` (create) | 6 | F |
| `Tests/CreatorEditorTests/PointerTests.swift` (modify) | 2, 3 | ⇧-click adds; the box's new pattern |
| `Tests/CreatorAppTests/AppInputTests.swift` (modify) | 6 | F over the canvas is the graph's |
| `docs/…` (modify) | 7 | Human checks MS, GI-8, CLAUDE.md, roadmap, spec errata |

## Tasks

| # | Task | Tests after |
|---|---|---|
| 1 | The selection model: `SelectionMode`, `CanvasSelection`, `SelectionPositions`, `canvasSelection`, `EditorModel+Selection` | master + 9 = 1399 |
| 2 | Clicks and drags by mode: ⌘-click toggles, press-without-move collapses, ⇧ adds, drags move and ⌥-copy the whole selection | master + 17 = 1407 |
| G | **Gate G: the user's box-select decision** (see above); Task 3 and Task 7 wait for it | — |
| 3 | Box select modes: ⇧ adds, ⌘ toggles, the mode fixed as the drag starts (answer (a)) | master + 22 = 1412 |
| 4 | ⌘A and Esc; the selection keys are claimed during a drag | master + 32 = 1422 |
| 5 | Arrow-key nudge, one undo step per key-down run | master + 41 = 1431 |
| 6 | F frames the selection in the graph canvas | master + 51 = 1441 |
| 7 | Docs: human checks MS, CLAUDE.md, roadmap, spec errata (box wording per Gate G) | master + 51 = 1441 |

---

### Task 1: The selection model

**Files:**
- Create: `Sources/CreatorEditor/SelectionMode.swift`, `Sources/CreatorEditor/CanvasSelection.swift`, `Sources/CreatorEditor/SelectionPositions.swift`, `Sources/CreatorEditor/EditorModel+Selection.swift`
- Modify: `Sources/CreatorEditor/EditorModel.swift` (the `selection` property), `Sources/CreatorEditor/CanvasRect.swift` (`union`)
- Test: `Tests/CreatorEditorTests/CanvasSelectionTests.swift`

**Interfaces:**
- Consumes: `EditorModel.frame(of:)`, `nodes(intersecting:)`, `graph`, `CanvasHit`, `GraphCommand.move(_:to:)`.
- Produces:
  - `public enum SelectionMode: Equatable, Sendable { case replace, add, toggle; public init(_ modifiers: CanvasModifiers) }`
  - `public struct CanvasSelection: Equatable, Sendable { public var nodes: Set<NodeID>; public init(nodes: Set<NodeID> = []); public var isEmpty: Bool; public func isSuperset(of: CanvasSelection) -> Bool; public func applying(_ items: CanvasSelection, mode: SelectionMode) -> CanvasSelection }`
  - `public struct SelectionPositions: Equatable, Sendable { public var nodes: [NodeID: Vector2]; public init(nodes: [NodeID: Vector2] = [:]); public var isEmpty: Bool; public var items: CanvasSelection }`
  - `EditorModel`: `public var canvasSelection: CanvasSelection`; `public var selection: Set<NodeID>` (get: its nodes; set: replaces the whole selection); `public func select(_ items: CanvasSelection, mode: SelectionMode)`; `public func selectAll()`; `public func clearSelection()`; `public var allItems: CanvasSelection`; `public func items(for hit: CanvasHit) -> CanvasSelection?`; `public func items(intersecting rect: CanvasRect) -> CanvasSelection`; `public func positions(of items: CanvasSelection) -> SelectionPositions`; `public func moveCommands(from start: SelectionPositions, by delta: Vector2) -> [GraphCommand]`; `public func bounds(of items: CanvasSelection) -> CanvasRect?`
  - `CanvasRect.union(_ other: CanvasRect) -> CanvasRect`

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorEditorTests/CanvasSelectionTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// The selection model every gesture and key goes through (spec 2026-10-09 §3), and the one sub-project B extends.
@MainActor
struct CanvasSelectionTests {
    let a = testNode(NumberTestNode.self, id: 1, at: .zero)
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))
    let c = testNode(NumberTestNode.self, id: 3, at: Vector2(600, 0))

    @Test func theModesReplaceAddAndToggle() {
        let ab = CanvasSelection(nodes: [a.id, b.id]), bc = CanvasSelection(nodes: [b.id, c.id])
        #expect(ab.applying(bc, mode: .replace) == bc)
        #expect(ab.applying(bc, mode: .add) == CanvasSelection(nodes: [a.id, b.id, c.id]))
        #expect(ab.applying(bc, mode: .toggle) == CanvasSelection(nodes: [a.id, c.id]))
        #expect(ab.isSuperset(of: CanvasSelection(nodes: [b.id])) && !ab.isSuperset(of: bc))
        #expect(CanvasSelection().isEmpty && !ab.isEmpty)
    }

    @Test func theModifiersPickTheMode() {
        #expect(SelectionMode([]) == .replace)
        #expect(SelectionMode(.option) == .replace, "⌥ duplicates; it isn't a selection mode")
        #expect(SelectionMode(.shift) == .add)
        #expect(SelectionMode(.command) == .toggle)
        #expect(SelectionMode([.command, .shift]) == .toggle, "⌘ wins over ⇧")
    }

    @Test func settingTheNodeSelectionReplacesTheWholeSelection() {
        let editor = makeEditor([a, b])
        editor.select(CanvasSelection(nodes: [a.id]), mode: .add)
        #expect(editor.selection == [a.id])
        editor.selection = [b.id]
        #expect(editor.canvasSelection == CanvasSelection(nodes: [b.id]))
        editor.select(CanvasSelection(nodes: [a.id]), mode: .toggle)
        #expect(editor.selection == [a.id, b.id])
    }

    @Test func selectAllAndClear() {
        let editor = makeEditor([a, b, c])
        editor.selectAll()
        #expect(editor.selection == [a.id, b.id, c.id])
        #expect(editor.allItems == editor.canvasSelection)
        editor.clearSelection()
        #expect(editor.canvasSelection.isEmpty)
    }

    @Test func aHitSelectsItsNode() {
        let editor = makeEditor([a, b])
        let socket = SocketRef(Endpoint(node: b.id, socket: "value"), isInput: true)
        #expect(editor.items(for: .node(a.id)) == CanvasSelection(nodes: [a.id]))
        #expect(editor.items(for: .socket(socket)) == CanvasSelection(nodes: [b.id]))
        #expect(editor.items(for: .empty) == nil)
        #expect(editor.items(intersecting: CanvasRect(corner: Vector2(150, 10), Vector2(320, 20))) == CanvasSelection(nodes: [a.id, b.id]))
    }

    /// Undo never prunes the selection, so it can name nodes no longer on the canvas; they are skipped.
    @Test func positionsAndMovesSkipItemsNoLongerOnTheCanvas() {
        let editor = makeEditor([a, b])
        let start = editor.positions(of: CanvasSelection(nodes: [a.id, b.id, nodeID(9)]))
        #expect(start == SelectionPositions(nodes: [a.id: .zero, b.id: Vector2(300, 0)]))
        #expect(start.items == CanvasSelection(nodes: [a.id, b.id]))
        #expect(editor.moveCommands(from: start, by: Vector2(5, 7))
            == [.move(a.id, to: Vector2(5, 7)), .move(b.id, to: Vector2(305, 7))])
        #expect(editor.positions(of: CanvasSelection(nodes: [nodeID(9)])).isEmpty)
    }

    @Test func boundsCoverTheItemsDrawnFrames() {
        let editor = makeEditor([a, c])
        let size = NodeLayout.size(editor.shape(of: a))
        #expect(editor.bounds(of: CanvasSelection(nodes: [a.id, c.id])) == CanvasRect(origin: .zero, size: Vector2(600 + size.x, size.y)))
        #expect(editor.bounds(of: CanvasSelection(nodes: [c.id])) == editor.frame(of: c))
        #expect(editor.bounds(of: CanvasSelection()) == nil)
        #expect(editor.bounds(of: CanvasSelection(nodes: [nodeID(9)])) == nil)
    }

    @Test func boundsAreInDisplayPointsInTheLeftDock() {
        let editor = makeEditor([a, c], dock: .left)
        let size = NodeLayout.size(editor.shape(of: a))
        // The left dock draws the transpose: c's stored (600, 0) is drawn at (0, 600).
        #expect(editor.bounds(of: CanvasSelection(nodes: [a.id, c.id])) == CanvasRect(origin: .zero, size: Vector2(size.x, 600 + size.y)))
    }

    /// Spec §3: "Selected items draw last and are hit-tested in the same order (existing rule)", pinned for several.
    @Test func selectedNodesDrawLastAndAreHitFirst() {
        let back = testNode(NumberTestNode.self, id: 1, at: .zero)
        let middle = testNode(NumberTestNode.self, id: 2, at: Vector2(10, 10))
        let front = testNode(NumberTestNode.self, id: 3, at: Vector2(20, 20))
        let editor = makeEditor([back, middle, front])
        let overlap = Vector2(100, 60)
        #expect(editor.hitTest(overlap) == .node(front.id))
        editor.selection = [back.id, middle.id]
        #expect(editor.drawOrder.map(\.id) == [front.id, back.id, middle.id])
        #expect(editor.hitTest(overlap) == .node(middle.id))
        editor.selection = [back.id]
        #expect(editor.hitTest(overlap) == .node(back.id))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -5`
Expected: compile errors — `cannot find 'CanvasSelection' in scope`, `cannot find 'SelectionMode' in scope`.

- [ ] **Step 3: Write the model**

**Create** `Sources/CreatorEditor/SelectionMode.swift`:

```swift
/// How a click or a box combines what it hits with the selection (spec 2026-10-09 §3): no modifier replaces the
/// selection, ⇧ adds to it, and ⌘ toggles each item in or out. ⌘ wins when both are held.
public enum SelectionMode: Equatable, Sendable {
    case replace
    case add
    case toggle

    /// The mode `modifiers` ask for: a click's are those held at its press, a box's those held as its drag starts.
    /// ⌥ isn't a mode (it duplicates).
    public init(_ modifiers: CanvasModifiers) {
        if modifiers.contains(.command) {
            self = .toggle
        } else if modifiers.contains(.shift) {
            self = .add
        } else {
            self = .replace
        }
    }
}
```

**Create** `Sources/CreatorEditor/CanvasSelection.swift`:

```swift
import CreatorKernel

/// What is selected on the canvas (spec 2026-10-09 §3). View state: never undone, never saved. Only nodes today;
/// canvas comments (sub-project B) add a `comments` set with an empty default and fold it into every member here,
/// so every gesture and key built on this type takes them in unchanged.
public struct CanvasSelection: Equatable, Sendable {
    public var nodes: Set<NodeID>

    public init(nodes: Set<NodeID> = []) {
        self.nodes = nodes
    }

    public var isEmpty: Bool { nodes.isEmpty }

    /// Whether every item of `other` is selected here.
    public func isSuperset(of other: CanvasSelection) -> Bool {
        nodes.isSuperset(of: other.nodes)
    }

    /// This selection combined with `items` as `mode` says: replaced by them, with them added, or with each of
    /// them toggled in or out.
    public func applying(_ items: CanvasSelection, mode: SelectionMode) -> CanvasSelection {
        switch mode {
        case .replace: items
        case .add: CanvasSelection(nodes: nodes.union(items.nodes))
        case .toggle: CanvasSelection(nodes: nodes.symmetricDifference(items.nodes))
        }
    }
}
```

**Create** `Sources/CreatorEditor/SelectionPositions.swift`:

```swift
import CreatorGeometry
import CreatorKernel

/// Where the selected items were when a drag began, in stored (left-to-right) canvas points: what a move offsets
/// and an ⌥-drag copies. Canvas comments (sub-project B) add their frames' origins beside the nodes.
public struct SelectionPositions: Equatable, Sendable {
    public var nodes: [NodeID: Vector2]

    public init(nodes: [NodeID: Vector2] = [:]) {
        self.nodes = nodes
    }

    public var isEmpty: Bool { nodes.isEmpty }

    /// The items these positions are of.
    public var items: CanvasSelection { CanvasSelection(nodes: Set(nodes.keys)) }
}
```

**Create** `Sources/CreatorEditor/EditorModel+Selection.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Selecting what is on the canvas (spec 2026-10-09 §3). Every gesture and key acts through these members: a click
/// and a box combine `items(for:)` and `items(intersecting:)` with the selection by a `SelectionMode`, ⌘A is
/// `allItems`, a drag and an arrow key move `positions(of:)` by `moveCommands(from:by:)`, an ⌥-drag copies
/// `SelectionPositions.items`, and F frames `bounds(of:)`. Canvas comments (sub-project B) join by adding their items
/// to `CanvasSelection`, `SelectionPositions`, `CanvasHit` and the members marked "B adds"; no caller changes.
extension EditorModel {
    /// Combines `items` with the selection as `mode` says.
    public func select(_ items: CanvasSelection, mode: SelectionMode) {
        canvasSelection = canvasSelection.applying(items, mode: mode)
    }

    /// ⌘A: everything on the canvas.
    public func selectAll() {
        canvasSelection = allItems
    }

    /// Esc, or a plain click on empty canvas: nothing selected.
    public func clearSelection() {
        canvasSelection = CanvasSelection()
    }

    /// Everything on the canvas. B adds: every comment.
    public var allItems: CanvasSelection {
        CanvasSelection(nodes: Set(graph.nodes.keys))
    }

    /// What a press on `hit` selects: the node, or a socket's node; `nil` for empty canvas. B adds: a comment.
    public func items(for hit: CanvasHit) -> CanvasSelection? {
        switch hit {
        case .node(let id): CanvasSelection(nodes: [id])
        case .socket(let socket): CanvasSelection(nodes: [socket.endpoint.node])
        case .empty: nil
        }
    }

    /// What a box covers: the items whose drawn rectangle meets `rect` (display canvas points). B adds: comments.
    public func items(intersecting rect: CanvasRect) -> CanvasSelection {
        CanvasSelection(nodes: nodes(intersecting: rect))
    }

    /// Where `items` are now (stored coordinates), skipping any no longer on the canvas. B adds: comments.
    public func positions(of items: CanvasSelection) -> SelectionPositions {
        SelectionPositions(nodes: Dictionary(uniqueKeysWithValues: items.nodes.compactMap { id in
            graph.nodes[id].map { (id, $0.position) }
        }))
    }

    /// The commands that put every item of `start` at its position there plus `delta` (stored coordinates), in a
    /// stable order. B adds: comment moves.
    public func moveCommands(from start: SelectionPositions, by delta: Vector2) -> [GraphCommand] {
        start.nodes.keys.sorted().compactMap { id in
            start.nodes[id].map { GraphCommand.move(id, to: $0 + delta) }
        }
    }

    /// The smallest rectangle (display canvas points) around the drawn rectangles of those `items` still on the
    /// canvas; `nil` when there are none. B adds: comment rectangles.
    public func bounds(of items: CanvasSelection) -> CanvasRect? {
        let frames = items.nodes.compactMap { graph.nodes[$0] }.map { frame(of: $0) }
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }
}
```

**Modify** `Sources/CreatorEditor/EditorModel.swift`, replace:

```swift
    /// Selected nodes. Changing it commits a typed but uncommitted inspector value (to the node it was typed
    /// for) and ends any slider drag's undo coalescing.
    public var selection: Set<NodeID> = [] {
        didSet {
            guard selection != oldValue else { return }
            commitPendingEntry()
            document.endCoalescing()
        }
    }
```

with:

```swift
    /// Everything selected on the canvas (`EditorModel+Selection`, spec 2026-10-09 §3). Changing it commits a typed
    /// but uncommitted inspector value (to the node it was typed for) and ends any slider drag's undo coalescing.
    /// View state: never undone, never saved.
    public var canvasSelection = CanvasSelection() {
        didSet {
            guard canvasSelection != oldValue else { return }
            commitPendingEntry()
            document.endCoalescing()
        }
    }

    /// The selected nodes. Setting it replaces the whole canvas selection (comments too, once sub-project B adds
    /// them), so code that selects nodes (a click, a paste, the app's Show Producing Node) leaves nothing else
    /// selected; to keep other items, go through `select(_:mode:)` or `canvasSelection`.
    public var selection: Set<NodeID> {
        get { canvasSelection.nodes }
        set { canvasSelection = CanvasSelection(nodes: newValue) }
    }
```

**Modify** `Sources/CreatorEditor/CanvasRect.swift`, replace:

```swift
    public func intersects(_ other: CanvasRect) -> Bool {
        origin.x <= other.maxX && other.origin.x <= maxX && origin.y <= other.maxY && other.origin.y <= maxY
    }
```

with:

```swift
    public func intersects(_ other: CanvasRect) -> Bool {
        origin.x <= other.maxX && other.origin.x <= maxX && origin.y <= other.maxY && other.origin.y <= maxY
    }

    /// The smallest rectangle holding both.
    public func union(_ other: CanvasRect) -> CanvasRect {
        CanvasRect(corner: Vector2(min(origin.x, other.origin.x), min(origin.y, other.origin.y)),
                   Vector2(max(maxX, other.maxX), max(maxY, other.maxY)))
    }
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --filter CreatorEditorTests.CanvasSelectionTests`
Expected: 9 tests pass. Then `swift test --filter CreatorEditorTests` — every editor test passes (the `selection` setter still ends coalescing: `CoalescingTests`).

- [ ] **Step 5: Run the full check**

Expected: no new warning, no lint violation, `exit 0`, `0`, `11`, **1399** tests (master + 9).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor/SelectionMode.swift Sources/CreatorEditor/CanvasSelection.swift \
  Sources/CreatorEditor/SelectionPositions.swift Sources/CreatorEditor/EditorModel+Selection.swift \
  Sources/CreatorEditor/EditorModel.swift Sources/CreatorEditor/CanvasRect.swift \
  Tests/CreatorEditorTests/CanvasSelectionTests.swift
git commit -m "feat(editor): a canvas selection value with replace/add/toggle modes, ready for comments"
```

### Task 2: Clicks and drags by mode

**Files:**
- Create: `Tests/CreatorEditorTests/MultiSelectPointerTests.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Pointer.swift` (`pointerReleased`'s click, `click`, `beginInteraction` made generic with a new `emptyCanvasDrag`, `update`'s move, `finishDuplicate`), `Sources/CreatorEditor/CanvasInteraction.swift` (`moving`, `duplicating`), `Sources/CreatorEditor/EditorModel+Editing.swift` (copy, paste, duplicate, `clipboard(of:)`, `insert`), `Sources/CreatorEditor/CanvasLayers.swift` (`ghosts`), `Tests/CreatorEditorTests/PointerTests.swift` (⇧-click adds)

**Interfaces:**
- Consumes (Task 1): `SelectionMode(_:)`, `CanvasSelection`, `SelectionPositions`, `select(_:mode:)`, `clearSelection()`, `items(for:)`, `positions(of:)`, `moveCommands(from:by:)`, `canvasSelection`.
- Produces: `CanvasInteraction.moving(start: SelectionPositions, key: String)`, `.duplicating(start: SelectionPositions, delta: Vector2)`; `EditorModel.clipboard(of items: CanvasSelection) -> NodeClipboard` and `insert(_:offset:) -> CanvasSelection?` (internal).

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorEditorTests/MultiSelectPointerTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Clicks and drags on nodes with ⌘, ⇧ and ⌥ (spec 2026-10-09 §3): ⌘-click toggles, ⇧ keeps adding, no modifier
/// replaces; a press on a selected node without movement collapses the selection to it (⌘: toggles it), so a ⌘-drag
/// still moves the selection; ⌥-drag copies the whole selection once the pointer moves.
@MainActor
struct MultiSelectPointerTests {
    let a = testNode(NumberTestNode.self, id: 1, at: .zero)
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))
    let c = testNode(NumberTestNode.self, id: 3, at: Vector2(600, 0))

    @Test func commandClickTogglesANodeInAndOut() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id]
        editor.click(editor.screenPoint(in: b.id), modifiers: .command)
        #expect(editor.selection == [a.id, b.id])
        editor.click(editor.screenPoint(in: a.id), modifiers: .command)
        #expect(editor.selection == [b.id])
        editor.click(editor.screenPoint(in: b.id), modifiers: [.command, .shift])
        #expect(editor.selection.isEmpty, "⌘ wins over ⇧")
    }

    @Test func shiftClickKeepsAdding() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        editor.click(editor.screenPoint(in: b.id), modifiers: .shift)
        #expect(editor.selection == [a.id, b.id])
        editor.click(editor.screenPoint(in: a.id), modifiers: .shift)
        #expect(editor.selection == [a.id, b.id], "⇧ never removes")
    }

    @Test func aPlainClickOnASelectedNodeCollapsesTheSelectionToIt() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id, b.id, c.id]
        editor.click(editor.screenPoint(in: b.id))
        #expect(editor.selection == [b.id])
    }

    @Test func aModifiedClickOnEmptyCanvasKeepsTheSelection() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id, b.id]
        editor.click(Vector2(900, 600), modifiers: .command)
        editor.click(Vector2(900, 600), modifiers: .shift)
        #expect(editor.selection == [a.id, b.id])
        editor.click(Vector2(900, 600))
        #expect(editor.selection.isEmpty)
    }

    @Test func aSocketClickSelectsItsNodeByTheSameModes() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        editor.click(editor.screenPoint(of: b.id, "value", input: true), modifiers: .command)
        #expect(editor.selection == [a.id, b.id])
    }

    @Test func commandDragMovesTheSelectionAndKeepsIt() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id, b.id]
        let start = editor.screenPoint(in: a.id)
        editor.drag(start, start + Vector2(0, 40), modifiers: .command)
        #expect(editor.selection == [a.id, b.id], "a ⌘-drag doesn't toggle the node it began on")
        #expect(editor.graph.nodes[a.id]?.position == Vector2(0, 40))
        #expect(editor.graph.nodes[b.id]?.position == Vector2(300, 40))
        #expect(editor.graph.nodes[c.id]?.position == Vector2(600, 0))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == .zero && editor.graph.nodes[b.id]?.position == Vector2(300, 0))
        #expect(!editor.document.canUndo, "one undo step")
    }

    @Test func aModifiedDragOnAnUnselectedNodeAddsItAndMovesEverything() {
        for modifiers: CanvasModifiers in [.shift, .command] {
            let editor = makeEditor([a, b, c])
            editor.selection = [a.id]
            let start = editor.screenPoint(in: b.id)
            editor.drag(start, start + Vector2(0, 40), modifiers: modifiers)
            #expect(editor.selection == [a.id, b.id])
            #expect(editor.graph.nodes[a.id]?.position == Vector2(0, 40))
            #expect(editor.graph.nodes[b.id]?.position == Vector2(300, 40))
            #expect(editor.graph.nodes[c.id]?.position == Vector2(600, 0))
        }
    }

    @Test func optionDragCopiesTheWholeSelectionOnlyOnceItMoves() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id, b.id]
        let start = editor.screenPoint(in: b.id)
        editor.pointerDragged(from: start, to: start, modifiers: .option)
        editor.pointerDragged(from: start, to: start + Vector2(2, 0), modifiers: .option)
        #expect(editor.interaction == nil && CanvasLayers.ghosts(editor).isEmpty, "not yet a drag: nothing is copied")
        editor.pointerDragged(from: start, to: start + Vector2(0, 60), modifiers: .option)
        #expect(CanvasLayers.ghosts(editor).map(\.position) == [Vector2(0, 60), Vector2(300, 60)])
        editor.pointerReleased(from: start, at: start + Vector2(0, 60), modifiers: .option)
        #expect(editor.graph.nodes.count == 5)
        #expect(editor.selection.count == 2 && editor.selection.isDisjoint(with: [a.id, b.id, c.id]))
        #expect(Set(editor.selection.compactMap { editor.graph.nodes[$0]?.position }) == [Vector2(0, 60), Vector2(300, 60)])
        editor.document.undo()
        #expect(editor.graph.nodes.count == 3 && !editor.document.canUndo)
    }
}
```

**Modify** `Tests/CreatorEditorTests/PointerTests.swift`, replace:

```swift
    @Test func clickSelectsAndShiftClickToggles() {
```

with:

```swift
    @Test func clickSelectsAndShiftClickAdds() {
```

**Modify** `Tests/CreatorEditorTests/PointerTests.swift`, replace:

```swift
        editor.click(editor.screenPoint(in: a.id), modifiers: .shift)
        #expect(editor.selection == [b.id])
```

with:

```swift
        editor.click(editor.screenPoint(in: a.id), modifiers: .shift)
        #expect(editor.selection == [a.id, b.id], "⇧ adds and never removes; ⌘ toggles (spec 2026-10-09 §3)")
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter 'CreatorEditorTests.MultiSelectPointerTests|CreatorEditorTests.PointerTests'`
Expected: 6 of the 19 fail — `commandClickTogglesANodeInAndOut` and `aSocketClickSelectsItsNodeByTheSameModes` (a ⌘-click replaces today), `shiftClickKeepsAdding` and `PointerTests.clickSelectsAndShiftClickAdds` (a ⇧-click on a selected node removes it today), `aModifiedDragOnAnUnselectedNodeAddsItAndMovesEverything` (a ⌘-drag on an unselected node replaces the selection today), `aModifiedClickOnEmptyCanvasKeepsTheSelection` (a ⌘-click on empty canvas clears today). `commandDragMovesTheSelectionAndKeepsIt`, `aPlainClickOnASelectedNodeCollapsesTheSelectionToIt` and `optionDragCopiesTheWholeSelectionOnlyOnceItMoves` already pass: they pin today's behaviour, which this task must keep.

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorEditor/CanvasInteraction.swift`, replace:

```swift
    /// Dragging selected nodes. `start` holds their stored positions when the drag began;
    /// `key` coalesces every step of the drag into one undo step.
    case moving(start: [NodeID: Vector2], key: String)
    /// An ⌥-drag: ghosts of the selection follow the pointer and are added on release.
    case duplicating(start: [NodeID: Vector2], delta: Vector2)
```

with:

```swift
    /// Dragging the selection: every selected item moves together. `start` holds their stored positions when the
    /// drag began; `key` coalesces every step of the drag into one undo step.
    case moving(start: SelectionPositions, key: String)
    /// An ⌥-drag: ghosts of the whole selection follow the pointer and are added on release.
    case duplicating(start: SelectionPositions, delta: Vector2)
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`, replace:

```swift
        case nil: click(press.hit, extending: press.modifiers.contains(.shift))
```

with:

```swift
        case nil: click(press.hit, mode: SelectionMode(press.modifiers))
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`, replace:

```swift
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
```

with:

```swift
    /// A press that didn't move selects what it landed on as `mode` says (spec 2026-10-09 §3). On an item already
    /// selected, a plain click collapses the selection to it, ⌘ toggles it out and ⇧ keeps it. On empty canvas a
    /// plain click clears the selection and a modified one keeps it.
    private func click(_ hit: CanvasHit, mode: SelectionMode) {
        guard let items = items(for: hit) else {
            if mode == .replace { clearSelection() }
            return
        }
        select(items, mode: mode)
    }
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`, replace:

```swift
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
```

with:

```swift
        if case .socket(let socket) = hit {
            return .connecting(WireDrag(from: socket, current: transform.toCanvas(screen)))
        }
        // Any other hit reaches the selection only through `items(for:)`, so a new kind of hit (sub-project B's
        // comments) needs no change here. An unselected item is selected first: alone, or added with ⇧ or ⌘.
        guard let items = items(for: hit) else { return emptyCanvasDrag(at: screen, modifiers: modifiers) }
        if !canvasSelection.isSuperset(of: items) {
            select(items, mode: SelectionMode(modifiers) == .replace ? .replace : .add)
        }
        // Every selected item moves (with ⌥, is copied once the pointer has moved), so a ⌘-drag on a selected
        // node moves the selection instead of toggling the node.
        let start = positions(of: canvasSelection)
        if modifiers.contains(.option) { return .duplicating(start: start, delta: .zero) }
        return .moving(start: start, key: "move-\(UUID().uuidString)")
    }

    /// A drag that began on empty canvas: ⇧ held as it starts box-selects; otherwise it pans.
    private func emptyCanvasDrag(at screen: Vector2, modifiers: CanvasModifiers) -> CanvasInteraction {
        if modifiers.contains(.shift) {
            let point = transform.toCanvas(screen)
            return .boxSelecting(start: point, current: point, base: selection)
        }
        return .panning(startOffset: transform.offset)
    }
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`, replace:

```swift
        case .moving(let start, let key):
            let moves = start.keys.sorted().compactMap { id in
                start[id].map { GraphCommand.move(id, to: $0 + storedDelta) }
            }
            try? document.perform(.batch(moves), coalescingKey: key)
```

with:

```swift
        case .moving(let start, let key):
            try? document.perform(.batch(moveCommands(from: start, by: storedDelta)), coalescingKey: key)
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`, replace:

```swift
    private func finishDuplicate(start: [NodeID: Vector2], delta: Vector2) {
        if let ids = insert(clipboard(of: Set(start.keys)), offset: delta) { selection = ids }
    }
```

with:

```swift
    private func finishDuplicate(start: SelectionPositions, delta: Vector2) {
        if let copies = insert(clipboard(of: start.items), offset: delta) { canvasSelection = copies }
    }
```

**Modify** `Sources/CreatorEditor/EditorModel+Editing.swift`, replace:

```swift
    /// ⌘C: copies the selected nodes and the wires between them.
    public func copySelection() {
        guard !selection.isEmpty else { return }
        setClipboard(clipboard(of: selection))
    }

    /// ⌘V: pastes the clipboard offset down and right, one step further on each paste,
    /// and selects the copies.
    public func paste() {
        guard let clipboard else { return }
        if let ids = insert(clipboard, offset: nextPasteOffset()) { selection = ids }
    }

    /// ⌘D: duplicates the selection offset down and right, leaving the clipboard alone.
    public func duplicateSelection() {
        guard !selection.isEmpty else { return }
        if let ids = insert(clipboard(of: selection), offset: Vector2(24, 24)) { selection = ids }
    }
```

with:

```swift
    /// ⌘C: copies the selected items (the nodes and the wires between them).
    public func copySelection() {
        guard !canvasSelection.isEmpty else { return }
        setClipboard(clipboard(of: canvasSelection))
    }

    /// ⌘V: pastes the clipboard offset down and right, one step further on each paste,
    /// and selects the copies.
    public func paste() {
        guard let clipboard else { return }
        if let copies = insert(clipboard, offset: nextPasteOffset()) { canvasSelection = copies }
    }

    /// ⌘D: duplicates the selection offset down and right, leaving the clipboard alone.
    public func duplicateSelection() {
        guard !canvasSelection.isEmpty else { return }
        if let copies = insert(clipboard(of: canvasSelection), offset: Vector2(24, 24)) { canvasSelection = copies }
    }
```

**Modify** `Sources/CreatorEditor/EditorModel+Editing.swift`, replace:

```swift
    func clipboard(of ids: Set<NodeID>) -> NodeClipboard {
        let nodes = ids.sorted().compactMap { graph.nodes[$0] }
```

with:

```swift
    /// What copying `items` puts on the clipboard: their nodes and the wires between them. B adds: comments.
    func clipboard(of items: CanvasSelection) -> NodeClipboard {
        let ids = items.nodes
        let nodes = ids.sorted().compactMap { graph.nodes[$0] }
```

**Modify** `Sources/CreatorEditor/EditorModel+Editing.swift`, replace:

```swift
    /// Adds fresh copies of `clipboard` moved by `offset` (stored coordinates) as one undo
    /// step. Returns the new IDs, or `nil` if the graph refused.
    func insert(_ clipboard: NodeClipboard, offset: Vector2) -> Set<NodeID>? {
```

with:

```swift
    /// Adds fresh copies of `clipboard` moved by `offset` (stored coordinates) as one undo
    /// step. Returns the copies, to select, or `nil` if the graph refused. B adds: comments.
    func insert(_ clipboard: NodeClipboard, offset: Vector2) -> CanvasSelection? {
```

**Modify** `Sources/CreatorEditor/EditorModel+Editing.swift`, replace:

```swift
            try document.perform(.batch(commands))
            return Set(mapping.values)
```

with:

```swift
            try document.perform(.batch(commands))
            return CanvasSelection(nodes: Set(mapping.values))
```

**Modify** `Sources/CreatorEditor/CanvasLayers.swift`, replace:

```swift
        return start.keys.sorted().compactMap { id in
            guard var node = model.graph.nodes[id], let position = start[id] else { return nil }
```

with:

```swift
        return start.nodes.keys.sorted().compactMap { id in
            guard var node = model.graph.nodes[id], let position = start.nodes[id] else { return nil }
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --filter CreatorEditorTests`
Expected: every editor test passes, among them the 8 new `MultiSelectPointerTests` and `PointerTests.clickSelectsAndShiftClickAdds`.

- [ ] **Step 5: Run the full check**

Expected: no new warning, no lint violation, `exit 0`, `0`, `11`, **1407** tests (master + 17).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor/EditorModel+Pointer.swift Sources/CreatorEditor/CanvasInteraction.swift \
  Sources/CreatorEditor/EditorModel+Editing.swift Sources/CreatorEditor/CanvasLayers.swift \
  Tests/CreatorEditorTests/MultiSelectPointerTests.swift Tests/CreatorEditorTests/PointerTests.swift
git commit -m "feat(editor): ⌘-click toggles, ⇧ adds, and drags move or ⌥-copy the whole selection"
```

### Task 3: Box select modes

**Files:**
- **Gate:** run only after Gate G is answered. As written this is answer (a); for (b), revise it first as Gate G says.
- Create: `Tests/CreatorEditorTests/BoxSelectModeTests.swift`
- Modify: `Sources/CreatorEditor/CanvasInteraction.swift` (`boxSelecting`), `Sources/CreatorEditor/EditorModel+Pointer.swift` (`pointerDragged`'s doc, `pointerReleased`, `emptyCanvasDrag`, `update`'s box case, a new `applyBox`), `Sources/CreatorEditor/CanvasLayers.swift` (the box's pattern), `Tests/CreatorEditorTests/PointerTests.swift` (the box's pattern)

**Interfaces:**
- Consumes (Task 1): `SelectionMode(_:)`, `CanvasSelection.applying(_:mode:)`, `items(intersecting:)`, `canvasSelection`.
- Produces: `CanvasInteraction.boxSelecting(start: Vector2, current: Vector2, base: CanvasSelection, mode: SelectionMode)` — Task 4's Esc puts `base` back.

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorEditorTests/BoxSelectModeTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Box select modes (spec 2026-10-09 §3, Errata (A)): a plain drag on empty canvas still pans; a drag that starts with
/// ⇧ or ⌘ held box-selects, and those modifiers, held as it starts, decide how the box combines with the selection it
/// began with: ⇧ adds, ⌘ toggles each node it covers.
@MainActor
struct BoxSelectModeTests {
    let a = testNode(NumberTestNode.self, id: 1, at: .zero)
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(400, 0))
    let c = testNode(NumberTestNode.self, id: 3, at: Vector2(800, 0))
    /// A box over b alone, and one over b and c.
    let start = Vector2(380, -20)
    let overB = Vector2(420, 20)
    let overBC = Vector2(820, 20)

    @Test func commandBoxTogglesEachNodeItCovers() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id, b.id]
        editor.drag(start, overBC, modifiers: .command)
        #expect(editor.selection == [a.id, c.id])
        #expect(editor.transform.offset == .zero, "a ⌘-drag on empty canvas doesn't pan")
    }

    @Test func shiftBoxAddsAndKeepsWhatItCoversSelected() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id, b.id]
        editor.drag(start, overBC, modifiers: .shift)
        #expect(editor.selection == [a.id, b.id, c.id])
    }

    @Test func commandWinsOverShift() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id, b.id]
        editor.drag(start, overBC, modifiers: [.command, .shift])
        #expect(editor.selection == [a.id, c.id])
    }

    /// Letting go of ⇧ a moment before the button (or pressing ⌘ mid-drag) changes nothing: a box that turned into
    /// "replace" at the end would drop the selection it was adding to.
    @Test func theModeIsTheOneTheDragStartedWith() {
        let editor = makeEditor([a, b, c])
        editor.selection = [a.id]
        editor.pointerDragged(from: start, to: start, modifiers: .shift)
        editor.pointerDragged(from: start, to: overB, modifiers: .shift)
        editor.pointerDragged(from: start, to: overB + Vector2(1, 0), modifiers: [])
        guard case .boxSelecting(_, _, let base, let mode)? = editor.interaction else {
            Issue.record("expected a box selection"); return
        }
        #expect(base == CanvasSelection(nodes: [a.id]) && mode == .add)
        #expect(editor.selection == [a.id, b.id])
        editor.pointerReleased(from: start, at: overB + Vector2(1, 0), modifiers: .command)
        #expect(editor.selection == [a.id, b.id])
    }

    /// The box is re-applied to the selection it began with at every step, so a node it covers and then leaves
    /// again is as it was.
    @Test func aNodeTheBoxLeavesAgainIsAsItWas() {
        let editor = makeEditor([a, b, c])
        editor.selection = [b.id]
        editor.pointerDragged(from: start, to: start, modifiers: .command)
        editor.pointerDragged(from: start, to: overBC, modifiers: .command)
        #expect(editor.selection == [c.id])
        editor.pointerDragged(from: start, to: Vector2(370, 20), modifiers: .command)
        #expect(editor.selection == [b.id])
        editor.pointerReleased(from: start, at: Vector2(370, 20), modifiers: .command)
        #expect(editor.selection == [b.id])
    }
}
```

**Modify** `Tests/CreatorEditorTests/PointerTests.swift`, replace:

```swift
        guard case .boxSelecting(let corner, let current, let base)? = editor.interaction else {
            Issue.record("expected a box selection"); return
        }
        #expect(corner == start && current == Vector2(420, 20) && base == [c.id])
```

with:

```swift
        guard case .boxSelecting(let corner, let current, let base, let mode)? = editor.interaction else {
            Issue.record("expected a box selection"); return
        }
        #expect(corner == start && current == Vector2(420, 20) && base == CanvasSelection(nodes: [c.id]) && mode == .add)
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: compile errors — the `.boxSelecting` patterns with four values don't match the three-value case.

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorEditor/CanvasInteraction.swift`, replace:

```swift
    /// A ⇧-drag on empty canvas. Corners are display canvas points; `base` is the selection
    /// before the drag, which the box adds to.
    case boxSelecting(start: Vector2, current: Vector2, base: Set<NodeID>)
```

with:

```swift
    /// A ⇧- or ⌘-drag on empty canvas (a plain one pans). Corners are display canvas points; `base` is the
    /// selection before the drag, which the box is combined with as `mode` says: the modifiers held as the drag
    /// started ask for it (⇧ adds, ⌘ toggles).
    case boxSelecting(start: Vector2, current: Vector2, base: CanvasSelection, mode: SelectionMode)
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`, replace:

```swift
    /// modifiers held then decide what it does (⇧ box-selects on empty canvas, ⌥ duplicates nodes).
```

with:

```swift
    /// modifiers held then decide what it does (⇧ or ⌘ box-selects on empty canvas and picks the box's mode,
    /// ⌥ duplicates the selection).
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`, replace:

```swift
    /// The press ended at `location`. Without a drag this is a click, and ⇧ held at the press extends the
    /// selection. `modifiers` (held at the release) count only for a press that reported no change before.
```

with:

```swift
    /// The press ended at `location`. Without a drag this is a click, which selects by the modifiers held at the
    /// press (`SelectionMode`). `modifiers` (held at the release) count only for a press that reported no change before.
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`, replace:

```swift
        case .connecting(let wire): finishWire(wire, at: location)
        case .panning, .boxSelecting: break
```

with:

```swift
        case .connecting(let wire): finishWire(wire, at: location)
        case .boxSelecting(let start, _, let base, let mode):
            applyBox(from: start, to: transform.toCanvas(location), base: base, mode: mode)
        case .panning: break
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`, replace:

```swift
    /// A drag that began on empty canvas: ⇧ held as it starts box-selects; otherwise it pans.
    private func emptyCanvasDrag(at screen: Vector2, modifiers: CanvasModifiers) -> CanvasInteraction {
        if modifiers.contains(.shift) {
            let point = transform.toCanvas(screen)
            return .boxSelecting(start: point, current: point, base: selection)
        }
        return .panning(startOffset: transform.offset)
    }
```

with (Gate G answer (a); answer (b) revises this first):

```swift
    /// A drag that began on empty canvas. A plain one pans (spec §6.2); with ⇧ or ⌘ held as it crosses
    /// `dragThreshold` it box-selects, in the mode those modifiers ask for (⇧ adds, ⌘ toggles).
    private func emptyCanvasDrag(at screen: Vector2, modifiers: CanvasModifiers) -> CanvasInteraction {
        if modifiers.contains(.shift) || modifiers.contains(.command) {
            let point = transform.toCanvas(screen)
            return .boxSelecting(start: point, current: point, base: canvasSelection, mode: SelectionMode(modifiers))
        }
        return .panning(startOffset: transform.offset)
    }
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`, replace:

```swift
        case .boxSelecting(let start, _, let base):
            let current = transform.toCanvas(location)
            setInteraction(.boxSelecting(start: start, current: current, base: base))
            selection = base.union(nodes(intersecting: CanvasRect(corner: start, current)))
```

with:

```swift
        case .boxSelecting(let start, _, let base, let mode):
            applyBox(from: start, to: transform.toCanvas(location), base: base, mode: mode)
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`, replace:

```swift
    private func finishDuplicate(start: SelectionPositions, delta: Vector2) {
```

with:

```swift
    /// The box from `start` to `current` (display canvas points) combined with the selection the drag began with, as
    /// `mode` says (⇧ adds, ⌘ toggles). It starts from `base` at every step, so a node the box covers and then leaves
    /// again is as it was.
    private func applyBox(from start: Vector2, to current: Vector2, base: CanvasSelection, mode: SelectionMode) {
        setInteraction(.boxSelecting(start: start, current: current, base: base, mode: mode))
        canvasSelection = base.applying(items(intersecting: CanvasRect(corner: start, current)), mode: mode)
    }

    private func finishDuplicate(start: SelectionPositions, delta: Vector2) {
```

**Modify** `Sources/CreatorEditor/CanvasLayers.swift`, replace:

```swift
            if case .boxSelecting(let start, let current, _)? = model.interaction {
```

with:

```swift
            if case .boxSelecting(let start, let current, _, _)? = model.interaction {
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --filter CreatorEditorTests`
Expected: every editor test passes, among them the 5 new `BoxSelectModeTests`, `PointerTests.shiftDragOnEmptyCanvasBoxSelectsAddingToTheSelection`, `PressModifierTests` (a plain drag still pans; a modifier pressed mid-pan doesn't box-select) and `CanvasCursorTests` (box selection keeps the arrow).

- [ ] **Step 5: Run the full check**

Expected: no new warning, no lint violation, `exit 0`, `0`, `11`, **1412** tests (master + 22).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor/CanvasInteraction.swift Sources/CreatorEditor/EditorModel+Pointer.swift \
  Sources/CreatorEditor/CanvasLayers.swift Tests/CreatorEditorTests/BoxSelectModeTests.swift \
  Tests/CreatorEditorTests/PointerTests.swift
git commit -m "feat(editor): box select adds with ⇧ and toggles with ⌘, its mode fixed as the drag starts"
```

### Task 4: ⌘A and Esc

**Files:**
- Create: `Tests/CreatorEditorTests/SelectionKeyTests.swift`
- Modify: `Sources/CreatorEditor/GraphKeyCommand.swift` (`selectAll`), `Sources/CreatorEditor/GraphKeyBindings.swift` (⌘A), `Sources/CreatorEditor/EditorModel.swift` (`pressCancelled`, `endPress`, `cancelPress()`, `isPressCancelled`), `Sources/CreatorEditor/EditorModel+Pointer.swift` (the cancelled-press guards, `cancelInteraction()`)
- Replace: `Sources/CreatorEditor/EditorModel+Commands.swift` (also: `.deleteSelection` tests `canvasSelection`, so Delete with only comments selected acts once B lands; the selection keys are claimed during a drag)

**Interfaces:**
- Consumes (Tasks 1, 3): `selectAll()`, `clearSelection()`, `canvasSelection`, `CanvasInteraction.boxSelecting(_, _, base:, _)`.
- Produces: `GraphKeyCommand.selectAll`; `EditorModel.cancelInteraction() -> Bool` (internal); `EditorModel.performSelectionCommand(_:)` (private; Tasks 5 and 6 add cases); `cancelPress()`, `isPressCancelled` (internal).

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorEditorTests/SelectionKeyTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// ⌘A and Esc (spec 2026-10-09 §3). Both reach the model through the window's `onInput` fallback, which a focused text
/// field pre-empts, so the field keeps its own ⌘A and Esc (human check MS-4).
@MainActor
struct SelectionKeyTests {
    let a = testNode(NumberTestNode.self, id: 1, at: .zero)
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(400, 0))

    func key(_ characters: String, _ modifiers: Modifiers = []) -> KeyEvent {
        KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers, timestamp: 0)
    }

    @Test func commandAIsSelectAll() {
        #expect(GraphKeyBindings.command(for: key("a", .command), paletteOpen: false) == .selectAll)
        #expect(GraphKeyBindings.command(for: key("A", [.command, .shift]), paletteOpen: false) == nil)
        #expect(GraphKeyBindings.command(for: key("a"), paletteOpen: false) == nil)
        #expect(GraphKeyBindings.command(for: key("a", .command), paletteOpen: true) == nil, "the palette's field keeps ⌘A")
    }

    @Test func selectAllSelectsEveryNodeThroughTheInputFallback() {
        let editor = makeEditor([a, b])
        let input = GraphPanelInput(model: editor)
        #expect(input.handle(.keyDown(key("a", .command))))
        #expect(editor.selection == [a.id, b.id])
    }

    /// With the panel hidden, ⌘A would select nodes no one can see, for the next Delete to remove.
    @Test func selectAllDoesNothingWhileThePanelIsHidden() {
        let editor = makeEditor([a, b], dock: .hidden)
        #expect(!editor.perform(.selectAll))
        #expect(editor.selection.isEmpty)
    }

    @Test func escapeClosesThePaletteBeforeClearingTheSelection() {
        let editor = makeEditor([a])
        editor.selection = [a.id]
        editor.openPalette()
        #expect(editor.perform(.cancel))
        #expect(editor.palette == nil && editor.selection == [a.id])
        #expect(editor.perform(.cancel))
        #expect(editor.selection.isEmpty)
        #expect(!editor.perform(.cancel), "nothing left to do: the key goes on")
    }

    @Test func escapeEndsAWireDragWithoutConnectingAndKeepsTheSelection() {
        let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
        let extrude = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([rect, extrude])
        editor.selection = [extrude.id]
        let from = editor.screenPoint(of: rect.id, "profile", input: false)
        let to = editor.screenPoint(of: extrude.id, "profile", input: true)
        editor.pointerDragged(from: from, to: from)
        editor.pointerDragged(from: from, to: to)
        guard case .connecting? = editor.interaction else { Issue.record("expected a wire drag"); return }
        #expect(editor.perform(.cancel))
        #expect(editor.interaction == nil && editor.selection == [extrude.id])
        editor.pointerDragged(from: from, to: to + Vector2(1, 0))
        #expect(editor.interaction == nil, "the rest of the press is ignored")
        editor.pointerReleased(from: from, at: to)
        #expect(editor.graph.links.isEmpty && editor.selection == [extrude.id], "no wire, and the release isn't a click")
        #expect(editor.perform(.cancel))
        #expect(editor.selection.isEmpty)
    }

    @Test func escapeDropsOptionDragGhosts() {
        let editor = makeEditor([a])
        editor.selection = [a.id]
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start, modifiers: .option)
        editor.pointerDragged(from: start, to: start + Vector2(0, 60), modifiers: .option)
        #expect(editor.perform(.cancel))
        #expect(CanvasLayers.ghosts(editor).isEmpty)
        editor.pointerReleased(from: start, at: start + Vector2(0, 60), modifiers: .option)
        #expect(editor.graph.nodes.count == 1 && !editor.document.canUndo)
        #expect(editor.selection == [a.id])
    }

    @Test func escapePutsBackTheSelectionABoxBeganWith() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let start = Vector2(380, -20)
        editor.pointerDragged(from: start, to: start, modifiers: .shift)
        editor.pointerDragged(from: start, to: Vector2(420, 20), modifiers: .shift)
        #expect(editor.selection == [a.id, b.id])
        #expect(editor.perform(.cancel))
        #expect(editor.selection == [a.id] && editor.interaction == nil)
        editor.pointerDragged(from: start, to: Vector2(430, 30), modifiers: .shift)
        editor.pointerReleased(from: start, at: Vector2(430, 30), modifiers: .shift)
        #expect(editor.selection == [a.id])
    }

    /// A move's steps are already in the document, so Esc doesn't cancel it; it is claimed, so it can't clear the
    /// selection mid-move (which would end the move's coalescing and split it into two undo steps).
    @Test func escapeDuringAMoveKeepsItOneUndoStep() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id, b.id]
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(0, 20))
        #expect(editor.perform(.cancel))
        #expect(editor.selection == [a.id, b.id])
        editor.pointerDragged(from: start, to: start + Vector2(0, 50))
        editor.pointerReleased(from: start, at: start + Vector2(0, 50))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(0, 50))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == .zero && !editor.document.canUndo)
    }

    /// ⌘A changes the selection, whose `didSet` ends coalescing; mid-move it is claimed and does nothing, so the move
    /// stays one undo step.
    @Test func selectAllDuringAMoveKeepsItOneUndoStep() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(0, 20))
        #expect(editor.perform(.selectAll))
        #expect(editor.selection == [a.id])
        editor.pointerDragged(from: start, to: start + Vector2(0, 50))
        editor.pointerReleased(from: start, at: start + Vector2(0, 50))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(0, 50))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == .zero && !editor.document.canUndo)
    }

    @Test func escapeDuringAPanIsClaimedAndThePanGoesOn() {
        let editor = makeEditor([a])
        editor.selection = [a.id]
        editor.pointerDragged(from: Vector2(900, 600), to: Vector2(900, 600))
        editor.pointerDragged(from: Vector2(900, 600), to: Vector2(920, 600))
        #expect(editor.perform(.cancel))
        editor.pointerDragged(from: Vector2(900, 600), to: Vector2(950, 600))
        editor.pointerReleased(from: Vector2(900, 600), at: Vector2(950, 600))
        #expect(editor.transform.offset == Vector2(50, 0) && editor.selection == [a.id])
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: compile error — `type 'GraphKeyCommand' has no member 'selectAll'`.

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorEditor/GraphKeyCommand.swift`, replace:

```swift
    case deleteSelection
```

with:

```swift
    case deleteSelection
    /// ⌘A: selects everything on the canvas.
    case selectAll
```

**Modify** `Sources/CreatorEditor/GraphKeyBindings.swift`, replace:

```swift
        case "d": .duplicate
```

with:

```swift
        case "d": .duplicate
        case "a": shifted ? nil : .selectAll
```

**Modify** `Sources/CreatorEditor/EditorModel.swift`, replace:

```swift
    @ObservationIgnored private var pressModifiers: CanvasModifiers = []
```

with:

```swift
    @ObservationIgnored private var pressModifiers: CanvasModifiers = []
    /// Esc cancelled the press's drag (`cancelPress()`): the rest of the press, to its release, is ignored.
    @ObservationIgnored private var pressCancelled = false
```

**Modify** `Sources/CreatorEditor/EditorModel.swift`, replace:

```swift
    func endPress() {
        pressStart = nil
        pressHit = .empty
        pressModifiers = []
        interaction = nil
    }
```

with:

```swift
    func endPress() {
        pressStart = nil
        pressHit = .empty
        pressModifiers = []
        pressCancelled = false
        interaction = nil
    }

    /// Ends the drag under way without finishing it; the press's later changes and its release do nothing.
    func cancelPress() {
        interaction = nil
        pressCancelled = true
    }

    /// Whether Esc cancelled the press under way (`cancelPress()`).
    var isPressCancelled: Bool { pressCancelled }
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`, replace:

```swift
        ensurePress(at: start, modifiers: modifiers)
        guard let press = currentPress else { return }
        if interaction == nil {
```

with:

```swift
        ensurePress(at: start, modifiers: modifiers)
        guard let press = currentPress, !isPressCancelled else { return }
        if interaction == nil {
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`, replace:

```swift
        ensurePress(at: start, modifiers: modifiers)
        guard let press = currentPress else { return }
        switch interaction {
```

with:

```swift
        ensurePress(at: start, modifiers: modifiers)
        guard let press = currentPress, !isPressCancelled else {
            // A press whose drag Esc cancelled ends here: no click, no wire.
            endPress()
            return
        }
        switch interaction {
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`, replace:

```swift
    /// Starts a press at `start` unless one with that start is in progress. A recorded press
```

with:

```swift
    /// Esc during a drag (spec 2026-10-09 §3). A drag that hasn't changed the document is cancelled and the rest of
    /// its press ignored: a wire being dragged is dropped, ⌥-drag ghosts vanish, and a box puts back the selection it
    /// began with. A pan or a move goes on (a move's steps are already in the document, for Undo), and the key is
    /// still claimed so it can't clear the selection mid-drag. Returns false with no drag under way.
    func cancelInteraction() -> Bool {
        switch interaction {
        case nil: return false
        case .panning?, .moving?: return true
        case .connecting?, .duplicating?: break
        case .boxSelecting(_, _, let base, _)?: canvasSelection = base
        }
        cancelPress()
        return true
    }

    /// Starts a press at `start` unless one with that start is in progress. A recorded press
```

**Replace the whole of** `Sources/CreatorEditor/EditorModel+Commands.swift` with:

```swift
extension EditorModel {
    /// Runs a keyboard command. Returns false when it does nothing here, so the key can go on.
    @discardableResult
    public func perform(_ command: GraphKeyCommand) -> Bool {
        switch command {
        case .tab:
            if isPanelVisible, pointerLocation != nil { openPalette() } else { toggleHidden() }
        case .openPalette:
            guard isPanelVisible else { return false }
            openPalette()
        case .deleteSelection:
            guard !canvasSelection.isEmpty else { return false }
            deleteSelection()
        case .selectAll:
            return performSelectionCommand(command)
        case .copy, .paste, .duplicate, .zoomIn, .zoomOut, .undo, .redo:
            performEdit(command)
        case .cancel, .paletteUp, .paletteDown, .paletteConfirm:
            return performPaletteCommand(command)
        }
        return true
    }

    /// The selection's keys (spec 2026-10-09 §3). They act only while the panel shows the canvas: with it hidden they
    /// would select or move nodes no one can see. During a drag they are claimed and do nothing, as Esc is during a
    /// move: a nudge or a selection change would end the move's coalescing and split it into two undo steps, and F
    /// would shift the canvas under the pointer.
    private func performSelectionCommand(_ command: GraphKeyCommand) -> Bool {
        guard isPanelVisible else { return false }
        guard interaction == nil else { return true }
        switch command {
        case .selectAll: selectAll()
        default: return false // `perform(_:)` routes every other command elsewhere.
        }
        return true
    }

    /// The commands that always apply: clipboard, zoom and undo.
    private func performEdit(_ command: GraphKeyCommand) {
        switch command {
        case .copy: copySelection()
        case .paste: paste()
        case .duplicate: duplicateSelection()
        case .zoomIn: zoom(in: true)
        case .zoomOut: zoom(in: false)
        case .undo: document.undo()
        case .redo: document.redo()
        default: break // `perform(_:)` routes every other command elsewhere.
        }
    }

    /// The palette's keys, and Escape.
    private func performPaletteCommand(_ command: GraphKeyCommand) -> Bool {
        switch command {
        case .cancel: return cancel()
        case .paletteUp: movePaletteHighlight(by: -1)
        case .paletteDown: movePaletteHighlight(by: 1)
        case .paletteConfirm: confirmPalette()
        default: return false // `perform(_:)` routes every other command elsewhere.
        }
        return true
    }

    /// Escape, in order (spec 2026-10-09 §3): closes the palette; else ends the drag under way
    /// (`cancelInteraction()`); else clears the selection. With none of these to do it returns false, and the key
    /// goes on. A pick's, a sketch's and the theme editor's Esc are button shortcuts, which MetalUI runs first.
    private func cancel() -> Bool {
        if palette != nil {
            closePalette()
            return true
        }
        if cancelInteraction() { return true }
        guard !canvasSelection.isEmpty else { return false }
        clearSelection()
        return true
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --filter CreatorEditorTests`
Expected: every editor test passes, among them the 10 new `SelectionKeyTests` and `KeyCommandTests.deleteWithNothingSelectedLetsTheKeyThrough` (Esc with nothing to do still goes on).

- [ ] **Step 5: Run the full check**

Expected: no new warning, no lint violation, `exit 0`, `0`, `11`, **1422** tests (master + 32).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor/GraphKeyCommand.swift Sources/CreatorEditor/GraphKeyBindings.swift \
  Sources/CreatorEditor/EditorModel.swift Sources/CreatorEditor/EditorModel+Pointer.swift \
  Sources/CreatorEditor/EditorModel+Commands.swift Tests/CreatorEditorTests/SelectionKeyTests.swift
git commit -m "feat(editor): ⌘A selects every node; Esc ends a drag, then clears the selection"
```

### Task 5: Arrow-key nudge

**Files:**
- Create: `Sources/CreatorEditor/EditorModel+Nudge.swift`, `Tests/CreatorEditorTests/NudgeTests.swift`
- Modify: `Sources/CreatorEditor/GraphKeyCommand.swift` (`nudge`), `Sources/CreatorEditor/GraphKeyBindings.swift` (arrows, `nudgeStep`, `largeNudgeStep`), `Sources/CreatorEditor/EditorModel.swift` (`nudgeKey`), `Sources/CreatorEditor/EditorModel+Commands.swift` (routing)

**Interfaces:**
- Consumes (Tasks 1, 4): `positions(of:)`, `moveCommands(from:by:)`, `canvasSelection`, `performSelectionCommand(_:)`; `DocumentModel.perform(_:coalescingKey:)`, `endCoalescing()`; `flow.stored(_:)`.
- Produces: `GraphKeyCommand.nudge(Vector2, isRepeat: Bool)`; `GraphKeyBindings.nudgeStep` (1), `largeNudgeStep` (10), `static func nudge(for character: String, shifted: Bool) -> Vector2?`; `EditorModel.nudgeSelection(by delta: Vector2, isRepeat: Bool) -> Bool` (public, `@discardableResult`).

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorEditorTests/NudgeTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// Arrow keys nudge the selection 1 pt, ⇧ 10 pt, as one undo step per key-down run (spec 2026-10-09 §3).
@MainActor
struct NudgeTests {
    let a = testNode(NumberTestNode.self, id: 1, at: Vector2(100, 100))
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(400, 100))

    func key(_ characters: String, _ modifiers: Modifiers = [], isRepeat: Bool = false) -> KeyEvent {
        KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers,
                 isRepeat: isRepeat, timestamp: 0)
    }

    @Test func arrowsAreNudgesOfOneOrTenPoints() {
        func command(_ key: KeyEvent) -> GraphKeyCommand? { GraphKeyBindings.command(for: key, paletteOpen: false) }
        #expect(command(key("\u{f700}")) == .nudge(Vector2(0, -1), isRepeat: false))
        #expect(command(key("\u{f701}", .shift)) == .nudge(Vector2(0, 10), isRepeat: false))
        #expect(command(key("\u{f702}", isRepeat: true)) == .nudge(Vector2(-1, 0), isRepeat: true))
        #expect(command(key("\u{f703}")) == .nudge(Vector2(1, 0), isRepeat: false))
        #expect(command(key("\u{f703}", .command)) == nil)
        #expect(command(key("\u{f703}", .option)) == nil)
        #expect(GraphKeyBindings.command(for: key("\u{f700}"), paletteOpen: true) == .paletteUp, "the palette's arrows win")
        #expect(GraphKeyBindings.command(for: key("\u{f702}"), paletteOpen: true) == nil, "← and → go to its field")
    }

    @Test func aNudgeMovesEverySelectedNode() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id, b.id]
        #expect(editor.perform(.nudge(Vector2(10, 0), isRepeat: false)))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(110, 100))
        #expect(editor.graph.nodes[b.id]?.position == Vector2(410, 100))
    }

    @Test func aHeldArrowIsOneUndoStep() {
        let editor = makeEditor([a])
        editor.selection = [a.id]
        editor.perform(.nudge(Vector2(1, 0), isRepeat: false))
        for _ in 0..<3 { editor.perform(.nudge(Vector2(1, 0), isRepeat: true)) }
        #expect(editor.graph.nodes[a.id]?.position == Vector2(104, 100))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == Vector2(100, 100))
        #expect(!editor.document.canUndo)
    }

    @Test func separatePressesAreSeparateUndoSteps() {
        let editor = makeEditor([a])
        editor.selection = [a.id]
        for _ in 0..<3 { editor.perform(.nudge(Vector2(0, 1), isRepeat: false)) }
        #expect(editor.graph.nodes[a.id]?.position == Vector2(100, 103))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == Vector2(100, 102))
    }

    /// A repeat after something ended coalescing (here a selection change) starts a new step, so one step never
    /// holds two selections' moves.
    @Test func aRepeatAfterTheSelectionChangedStartsANewStep() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        editor.perform(.nudge(Vector2(1, 0), isRepeat: false))
        editor.perform(.nudge(Vector2(1, 0), isRepeat: true))
        editor.selection = [b.id]
        editor.perform(.nudge(Vector2(1, 0), isRepeat: true))
        editor.document.undo()
        #expect(editor.graph.nodes[b.id]?.position == Vector2(400, 100))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(102, 100))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == Vector2(100, 100))
    }

    /// The left dock draws positions transposed; an arrow moves the node the way it points on screen.
    @Test func theLeftDockNudgesTheWayTheArrowPoints() {
        let editor = makeEditor([a], dock: .left)
        editor.selection = [a.id]
        editor.perform(.nudge(Vector2(0, 10), isRepeat: false))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(110, 100))
        #expect(editor.displayOrigin(of: editor.graph.nodes[a.id] ?? a) == Vector2(100, 110))
    }

    /// A nudge ends coalescing and performs its own step; mid-move it is claimed and does nothing, so the move stays
    /// one undo step.
    @Test func aNudgeDuringAMoveKeepsItOneUndoStep() {
        let editor = makeEditor([a, b])
        editor.selection = [a.id]
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(0, 20))
        #expect(editor.perform(.nudge(Vector2(1, 0), isRepeat: false)), "claimed, so it doesn't reach the viewport")
        editor.pointerDragged(from: start, to: start + Vector2(0, 50))
        editor.pointerReleased(from: start, at: start + Vector2(0, 50))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(100, 150))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == Vector2(100, 100) && !editor.document.canUndo)
    }

    @Test func withNothingSelectedOrThePanelHiddenTheKeyGoesOn() {
        let editor = makeEditor([a])
        #expect(!editor.perform(.nudge(Vector2(1, 0), isRepeat: false)))
        editor.selection = [nodeID(9)]
        #expect(!editor.perform(.nudge(Vector2(1, 0), isRepeat: false)), "a stale selection moves nothing")
        let hidden = makeEditor([a], dock: .hidden)
        hidden.selection = [a.id]
        #expect(!hidden.perform(.nudge(Vector2(1, 0), isRepeat: false)))
        #expect(hidden.graph.nodes[a.id]?.position == Vector2(100, 100) && !hidden.document.canUndo)
    }

    @Test func arrowsReachTheModelThroughTheInputFallback() {
        let editor = makeEditor([a])
        editor.selection = [a.id]
        let input = GraphPanelInput(model: editor)
        #expect(input.handle(.keyDown(key("\u{f703}", .shift))))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(110, 100))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: compile error — `type 'GraphKeyCommand' has no member 'nudge'`.

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorEditor/GraphKeyCommand.swift`, replace:

```swift
/// A keyboard command the graph panel understands (spec §6.2), independent of how the key
```

with:

```swift
import CreatorGeometry

/// A keyboard command the graph panel understands (spec §6.2), independent of how the key
```

**Modify** `Sources/CreatorEditor/GraphKeyCommand.swift`, replace:

```swift
    /// ⌘A: selects everything on the canvas.
    case selectAll
```

with:

```swift
    /// ⌘A: selects everything on the canvas.
    case selectAll
    /// An arrow key: nudges the selection by `delta` display canvas points (the way the arrow points on screen).
    /// `isRepeat` marks a held key's auto-repeat, which joins the undo step its first press began.
    case nudge(Vector2, isRepeat: Bool)
```

**Modify** `Sources/CreatorEditor/GraphKeyBindings.swift`, replace:

```swift
import MetalUI

/// The graph panel's keys (spec §6.2). Pure, so the mapping is tested without a window.
public enum GraphKeyBindings {
```

with:

```swift
import CreatorGeometry
import MetalUI

/// The graph panel's keys (spec §6.2). Pure, so the mapping is tested without a window.
public enum GraphKeyBindings {
    /// How far one arrow press nudges the selection, in canvas points (spec 2026-10-09 §3).
    public static let nudgeStep = 1.0
    /// How far one ⇧-arrow press nudges it.
    public static let largeNudgeStep = 10.0

```

**Modify** `Sources/CreatorEditor/GraphKeyBindings.swift`, replace:

```swift
        if modifiers == .command {
            return commandChord(for: character.lowercased(), shifted: shifted)
        }
```

with:

```swift
        if modifiers.isEmpty, let delta = nudge(for: character, shifted: shifted) {
            return .nudge(delta, isRepeat: key.isRepeat)
        }
        if modifiers == .command {
            return commandChord(for: character.lowercased(), shifted: shifted)
        }
```

**Modify** `Sources/CreatorEditor/GraphKeyBindings.swift`, replace:

```swift
    /// ⌘ chords; `character` is already lowercased, and ⇧ turns ⌘Z into redo.
```

with:

```swift
    /// An arrow key's nudge in display canvas points, the way it points on screen; `nil` for any other key.
    static func nudge(for character: String, shifted: Bool) -> Vector2? {
        let step = shifted ? largeNudgeStep : nudgeStep
        switch character {
        case "\u{f700}": return Vector2(0, -step)
        case "\u{f701}": return Vector2(0, step)
        case "\u{f702}": return Vector2(-step, 0)
        case "\u{f703}": return Vector2(step, 0)
        default: return nil
        }
    }

    /// ⌘ chords; `character` is already lowercased, and ⇧ turns ⌘Z into redo.
```

**Modify** `Sources/CreatorEditor/EditorModel.swift`, replace:

```swift
    @ObservationIgnored var pendingEntry: PendingEntry?
```

with:

```swift
    @ObservationIgnored var pendingEntry: PendingEntry?
    /// The undo coalescing key of the arrow-key run under way (`EditorModel+Nudge`).
    @ObservationIgnored var nudgeKey: String?
```

**Create** `Sources/CreatorEditor/EditorModel+Nudge.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import Foundation

extension EditorModel {
    /// An arrow key (spec 2026-10-09 §3): moves every selected item by `delta` display canvas points, the way the
    /// arrow points on screen (the left dock's transpose is undone). One undo step per key-down run: a press that
    /// isn't an auto-repeat starts a new step, and its repeats join it. A repeat after something ended coalescing
    /// (a press, a selection change, Undo) starts a new step too. Returns false when nothing selected is on the
    /// canvas, so the key goes on.
    @discardableResult
    public func nudgeSelection(by delta: Vector2, isRepeat: Bool) -> Bool {
        let start = positions(of: canvasSelection)
        guard !start.isEmpty else { return false }
        if !isRepeat || nudgeKey == nil {
            document.endCoalescing()
            nudgeKey = "nudge-\(UUID().uuidString)"
        }
        try? document.perform(.batch(moveCommands(from: start, by: flow.stored(delta))), coalescingKey: nudgeKey)
        return true
    }
}
```

**Modify** `Sources/CreatorEditor/EditorModel+Commands.swift`, replace:

```swift
        case .selectAll:
            return performSelectionCommand(command)
```

with:

```swift
        case .selectAll, .nudge:
            return performSelectionCommand(command)
```

**Modify** `Sources/CreatorEditor/EditorModel+Commands.swift`, replace:

```swift
        case .selectAll: selectAll()
        default: return false // `perform(_:)` routes every other command elsewhere.
```

with:

```swift
        case .selectAll: selectAll()
        case .nudge(let delta, let isRepeat): return nudgeSelection(by: delta, isRepeat: isRepeat)
        default: return false // `perform(_:)` routes every other command elsewhere.
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --filter CreatorEditorTests`
Expected: every editor test passes, among them the 9 new `NudgeTests` and `KeyCommandTests.whileThePaletteIsOpenOnlyItsNavigationKeysAreTaken`.

- [ ] **Step 5: Run the full check**

Expected: no new warning, no lint violation, `exit 0`, `0`, `11`, **1431** tests (master + 41).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor/GraphKeyCommand.swift Sources/CreatorEditor/GraphKeyBindings.swift \
  Sources/CreatorEditor/EditorModel.swift Sources/CreatorEditor/EditorModel+Nudge.swift \
  Sources/CreatorEditor/EditorModel+Commands.swift Tests/CreatorEditorTests/NudgeTests.swift
git commit -m "feat(editor): arrow keys nudge the selection 1 pt (⇧ 10 pt), one undo step per key-down run"
```

### Task 6: F frames the selection in the graph canvas

**Files:**
- Create: `Sources/CreatorEditor/EditorModel+Framing.swift`, `Tests/CreatorEditorTests/FramingTests.swift`
- Modify: `Sources/CreatorEditor/CanvasRect.swift` (`centre`), `Sources/CreatorEditor/CanvasTransform.swift` (`framing`), `Sources/CreatorEditor/GraphKeyCommand.swift`, `Sources/CreatorEditor/GraphKeyBindings.swift` (F), `Sources/CreatorEditor/EditorModel+Commands.swift` (routing), `Sources/CreatorApp/AppInput.swift` (F goes to the graph over its canvas), `Tests/CreatorAppTests/AppInputTests.swift`

**Interfaces:**
- Consumes (Tasks 1, 4): `bounds(of:)`, `allItems`, `canvasSelection`, `performSelectionCommand(_:)`; `visibleCanvasSize`, `pointerLocation`, `transform`.
- Produces: `GraphKeyCommand.frameSelection`; `CanvasRect.centre`; `CanvasTransform.framing(_ rect: CanvasRect, in size: Vector2, padding: Double) -> CanvasTransform`; `EditorModel.framingPadding` (40); `EditorModel.frameSelection() -> Bool` (public, `@discardableResult`).

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorEditorTests/FramingTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// F frames the selection in the graph canvas when the pointer is over it (spec 2026-10-09 §3): its bounds fill the
/// visible canvas inside 40 points of padding, centred, the zoom within range; with nothing selected, everything.
@MainActor
struct FramingTests {
    let a = testNode(NumberTestNode.self, id: 1, at: .zero)
    let b = testNode(NumberTestNode.self, id: 2, at: Vector2(1000, 0))

    func close(_ p: Vector2, _ q: Vector2) -> Bool { (p - q).length < 1e-9 }

    @Test func framingCentresARectAndFitsItInsideThePadding() {
        let rect = CanvasRect(origin: Vector2(0, 0), size: Vector2(1440, 100))
        let framed = CanvasTransform.framing(rect, in: Vector2(800, 400), padding: 40)
        #expect(framed.zoom == 0.5)
        #expect(framed.toScreen(rect.centre) == Vector2(400, 200))
        #expect(framed.toScreen(rect.origin).x == 40)
    }

    @Test func framingKeepsTheZoomInRange() {
        let small = CanvasRect(origin: Vector2(100, 50), size: Vector2(200, 100))
        let zoomedIn = CanvasTransform.framing(small, in: Vector2(800, 400), padding: 40)
        #expect(zoomedIn.zoom == CanvasTransform.zoomRange.upperBound)
        #expect(zoomedIn.toScreen(small.centre) == Vector2(400, 200))
        let wide = CanvasRect(origin: .zero, size: Vector2(4000, 100))
        #expect(CanvasTransform.framing(wide, in: Vector2(800, 400), padding: 40).zoom == CanvasTransform.zoomRange.lowerBound)
    }

    @Test func fIsTheFrameKey() {
        func key(_ characters: String, _ modifiers: Modifiers = []) -> KeyEvent {
            KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers, timestamp: 0)
        }
        #expect(GraphKeyBindings.command(for: key("f"), paletteOpen: false) == .frameSelection)
        #expect(GraphKeyBindings.command(for: key("F", .shift), paletteOpen: false) == nil)
        #expect(GraphKeyBindings.command(for: key("f", .command), paletteOpen: false) == nil)
        #expect(GraphKeyBindings.command(for: key("f"), paletteOpen: true) == nil, "the palette's field types it")
    }

    @Test func fFramesTheSelectionInTheVisibleCanvas() {
        let editor = makeEditor([a, b])
        editor.selection = [b.id]
        editor.pointerLocation = Vector2(10, 10)
        #expect(editor.perform(.frameSelection))
        let canvas = editor.visibleCanvasSize
        let frame = editor.frame(of: b)
        #expect(close(editor.transform.toScreen(frame.centre), canvas * 0.5))
        let topLeft = editor.transform.toScreen(frame.origin)
        #expect(min(topLeft.x, topLeft.y) >= EditorModel.framingPadding - 1e-9)
        #expect(editor.transform.toScreen(Vector2(editor.frame(of: a).maxX, 0)).x < 0, "a isn't selected, so it is off screen")
    }

    @Test func withNothingSelectedFFramesEverything() {
        let editor = makeEditor([a, b])
        editor.pointerLocation = Vector2(10, 10)
        #expect(editor.perform(.frameSelection))
        let canvas = editor.visibleCanvasSize
        #expect(editor.transform.toScreen(editor.frame(of: a).origin).x >= EditorModel.framingPadding - 1e-9)
        #expect(editor.transform.toScreen(Vector2(editor.frame(of: b).maxX, 0)).x <= canvas.x - EditorModel.framingPadding + 1e-9)
    }

    /// Undo never prunes the selection: a selection whose nodes are all gone frames everything instead.
    @Test func fWithOnlyAStaleSelectionFramesEverything() {
        let editor = makeEditor([a, b])
        editor.pointerLocation = Vector2(10, 10)
        editor.perform(.frameSelection)
        let everything = editor.transform
        editor.transform = CanvasTransform()
        editor.selection = [nodeID(9)]
        #expect(editor.perform(.frameSelection))
        #expect(editor.transform == everything)
    }

    @Test func fNeedsThePointerOverTheVisibleCanvas() {
        let editor = makeEditor([a, b])
        editor.selection = [b.id]
        #expect(!editor.perform(.frameSelection), "the pointer is elsewhere: F is the viewport's")
        #expect(editor.transform == CanvasTransform())
        let hidden = makeEditor([a, b], dock: .hidden)
        hidden.pointerLocation = Vector2(10, 10)
        #expect(!hidden.perform(.frameSelection))
        let empty = makeEditor([])
        empty.pointerLocation = Vector2(10, 10)
        #expect(!empty.perform(.frameSelection), "nothing to frame: the key goes on")
    }

    /// Mid-drag F is claimed and does nothing: a new transform under a pan or a move would jump the canvas or the nodes.
    @Test func fDuringADragIsClaimedAndChangesNothing() {
        let editor = makeEditor([a, b])
        editor.pointerLocation = Vector2(10, 10)
        editor.pointerDragged(from: Vector2(900, 600), to: Vector2(900, 600))
        editor.pointerDragged(from: Vector2(900, 600), to: Vector2(920, 600))
        #expect(editor.perform(.frameSelection))
        #expect(editor.transform == CanvasTransform(offset: Vector2(20, 0), zoom: 1))
        editor.pointerReleased(from: Vector2(900, 600), at: Vector2(920, 600))
    }

    @Test func fFramesTheLeftDocksTransposedLayout() {
        let editor = makeEditor([a, b], dock: .left)
        editor.selection = [b.id]
        editor.pointerLocation = Vector2(10, 10)
        editor.perform(.frameSelection)
        #expect(close(editor.transform.toScreen(editor.frame(of: b).centre), editor.visibleCanvasSize * 0.5))
        #expect(editor.frame(of: b).origin == Vector2(0, 1000))
    }
}
```

**Modify** `Tests/CreatorAppTests/AppInputTests.swift`, replace:

```swift
    @Test func theViewportsZoomKeysYieldToTheGraphOverItsCanvas() async {
```

with:

```swift
    @Test func theViewportsKeysYieldToTheGraphOverItsCanvas() async {
```

**Modify** `Tests/CreatorAppTests/AppInputTests.swift`, replace:

```swift
        #expect(input.handleAction(ViewportKeyAction(command: .frame)), "the graph has no F, so F frames the viewport")
    }
```

with:

```swift
        #expect(!input.handleAction(ViewportKeyAction(command: .frame)), "F goes on to the graph's own F")
    }

    /// Spec 2026-10-09 §3: "F frames the selection in the graph canvas when the pointer is over it (the viewport's F
    /// is unchanged)".
    @Test func fFramesTheGraphOverItsCanvasAndTheViewportElsewhere() async throws {
        let app = await makeApp()
        let input = AppInput(model: app)
        let node = BuiltInNodes.registry.makeNode(NumberNode.typeID, at: Vector2(2000, 2000))
        try app.document.perform(.addNode(node))
        app.editor.selection = [node.id]
        let canvas = app.editor.transform
        #expect(input.handleAction(ViewportKeyAction(command: .frame)), "the pointer elsewhere: the viewport frames")
        #expect(app.editor.transform == canvas)
        app.editor.pointerLocation = Vector2(40, 40)
        #expect(!input.handleAction(ViewportKeyAction(command: .frame)))
        let f = KeyEvent(charactersIgnoringModifiers: "f", characters: "f", timestamp: 1)
        #expect(input.handleInput(.keyDown(f)))
        #expect(app.editor.transform != canvas)
    }
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep error: | head -3`
Expected: compile errors — `type 'CanvasTransform' has no member 'framing'`, `value of type 'CanvasRect' has no member 'centre'`.

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorEditor/CanvasRect.swift`, replace:

```swift
    public var maxX: Double { origin.x + size.x }
    public var maxY: Double { origin.y + size.y }
```

with:

```swift
    public var maxX: Double { origin.x + size.x }
    public var maxY: Double { origin.y + size.y }
    public var centre: Vector2 { origin + size * 0.5 }
```

**Modify** `Sources/CreatorEditor/CanvasTransform.swift`, replace:

```swift
    public func panned(by delta: Vector2) -> CanvasTransform {
```

with:

```swift
    /// The transform that shows `rect` (display canvas points) as large as fits in a canvas of `size` (screen
    /// points) with `padding` screen points around it, centred; the zoom stays in `zoomRange`, so a small rect may
    /// fill less and a huge one overflow.
    public static func framing(_ rect: CanvasRect, in size: Vector2, padding: Double) -> CanvasTransform {
        let fit = min((size.x - 2 * padding) / rect.size.x, (size.y - 2 * padding) / rect.size.y)
        let zoom = CanvasTransform(zoom: fit).zoom
        return CanvasTransform(offset: size * 0.5 - rect.centre * zoom, zoom: zoom)
    }

    public func panned(by delta: Vector2) -> CanvasTransform {
```

**Create** `Sources/CreatorEditor/EditorModel+Framing.swift`:

```swift
import CreatorGeometry

extension EditorModel {
    /// Screen points kept clear around what F frames (MetalNodes §18.6).
    public static let framingPadding = 40.0

    /// F with the pointer over the canvas (spec 2026-10-09 §3): pans and zooms so the selection fills the visible
    /// canvas (`visibleCanvasSize`) inside `framingPadding`, centred, the zoom within `CanvasTransform.zoomRange`.
    /// With nothing selected (or only nodes no longer on the canvas) it frames everything, as the viewport's F does.
    /// Returns false for an empty canvas, so the key goes on.
    @discardableResult
    public func frameSelection() -> Bool {
        guard let bounds = bounds(of: canvasSelection) ?? bounds(of: allItems) else { return false }
        transform = .framing(bounds, in: visibleCanvasSize, padding: Self.framingPadding)
        return true
    }
}
```

**Modify** `Sources/CreatorEditor/GraphKeyCommand.swift`, replace:

```swift
    /// ⌘A: selects everything on the canvas.
    case selectAll
```

with:

```swift
    /// ⌘A: selects everything on the canvas.
    case selectAll
    /// F with the pointer over the canvas: frames the selection (everything when nothing is selected).
    case frameSelection
```

**Modify** `Sources/CreatorEditor/GraphKeyBindings.swift`, replace:

```swift
        case "-": .zoomOut
```

with:

```swift
        case "-": .zoomOut
        case "f": shifted ? nil : .frameSelection
```

**Modify** `Sources/CreatorEditor/EditorModel+Commands.swift`, replace:

```swift
        case .selectAll, .nudge:
            return performSelectionCommand(command)
```

with:

```swift
        case .selectAll, .nudge, .frameSelection:
            return performSelectionCommand(command)
```

**Modify** `Sources/CreatorEditor/EditorModel+Commands.swift`, replace:

```swift
        case .nudge(let delta, let isRepeat): return nudgeSelection(by: delta, isRepeat: isRepeat)
```

with:

```swift
        case .nudge(let delta, let isRepeat): return nudgeSelection(by: delta, isRepeat: isRepeat)
        case .frameSelection: return pointerLocation != nil && frameSelection()
```

**Modify** `Sources/CreatorApp/AppInput.swift`, replace:

```swift
/// - `onAction`: the graph's actions first, then the viewport's keys, except + and − while the pointer is over
///   the graph canvas, which fall through to the graph's own zoom keys (gaps M4-a, M5-b: keys aren't scoped to a
///   hovered element until MetalUI C9). F has no graph binding, so it
///   frames the viewport from anywhere;
```

with:

```swift
/// - `onAction`: the graph's actions first, then the viewport's keys, except while the pointer is over the graph
///   canvas: there F, + and − fall through to the graph's own keys (F frames the graph's selection, + and − zoom
///   the canvas; spec 2026-10-09 §3), because keys aren't scoped to a hovered element until MetalUI C9 (gaps M4-a,
///   M5-b);
```

**Modify** `Sources/CreatorApp/AppInput.swift`, replace:

```swift
        if key.command != .frame, model.editor.pointerLocation != nil { return false }
```

with:

```swift
        if model.editor.pointerLocation != nil { return false }
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --filter 'CreatorEditorTests|CreatorAppTests.AppInputTests'`
Expected: every test passes, among them the 9 new `FramingTests` and `AppInputTests.fFramesTheGraphOverItsCanvasAndTheViewportElsewhere`.

- [ ] **Step 5: Run the full check**

Expected: no new warning, no lint violation, `exit 0`, `0`, `11`, **1441** tests (master + 51).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor/CanvasRect.swift Sources/CreatorEditor/CanvasTransform.swift \
  Sources/CreatorEditor/EditorModel+Framing.swift Sources/CreatorEditor/GraphKeyCommand.swift \
  Sources/CreatorEditor/GraphKeyBindings.swift Sources/CreatorEditor/EditorModel+Commands.swift \
  Sources/CreatorApp/AppInput.swift Tests/CreatorEditorTests/FramingTests.swift \
  Tests/CreatorAppTests/AppInputTests.swift
git commit -m "feat(editor): F frames the selection in the graph canvas when the pointer is over it"
```

### Task 7: Docs: human checks MS, CLAUDE.md, roadmap, spec errata

**Files:**
- Modify: `docs/verification/human-checks.md` (GI-8's F clause; append group MS), `CLAUDE.md` (project state, the `CreatorEditor` bullet, the app-shell input sentence), `docs/superpowers/roadmap.md` (a row), `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` (append Errata (A: multi-select))

**Interfaces:** none (docs only).

**Gate:** run only after Gate G is answered. The MS-3 check and the errata's first bullet below are answer (a)'s text; for (b), use the "(b)" text given after each, and amend GI-5, GI-6 and M5-6 as Gate G says. The errata record the user's answer as theirs (with its date), never as this plan's interpretation.

- [ ] **Step 1: Human checks**

**Modify** `docs/verification/human-checks.md`, replace:

```markdown
- [ ] **GI-8 Keys unchanged, and the preview.** Over the canvas, + and − still zoom it (not the viewport), F frames
  the viewport, Tab and Space open the palette, and Delete, ⌘C, ⌘V and ⌘D work after a canvas click. Then in
```

with:

```markdown
- [ ] **GI-8 Keys unchanged, and the preview.** Over the canvas, + and − still zoom it (not the viewport), F frames
  the graph's selection (MS-6; before multi-select it framed the viewport), Tab and Space open the palette, and
  Delete, ⌘C, ⌘V and ⌘D work after a canvas click. Then in
```

**Append to** `docs/verification/human-checks.md`:

```markdown

## Group MS — multi-select (sub-project A)

**Status: PENDING.** Plan `2026-10-09-multi-select.md`, spec `2026-10-09-selection-groups-comments-design.md` §3 and
its Errata (A: multi-select). The tests pin the model; these check the gestures and keys through a real window (no
headless MetalUI window, gap M6-e). Run `swift run MetalCreatorApp` on a saved bracket, docked left, then MS-8 docked
at the bottom too.

- [ ] **MS-1 Clicks.** Click a node, then ⌘-click two more: all three are selected; ⌘-click one of them again: it
  alone is deselected. ⇧-click a selected node: it stays selected. Click one of several selected nodes: only it stays
  selected. ⌘-click and ⇧-click empty canvas: nothing changes; a plain click there clears. Pinned:
  `MultiSelectPointerTests`. **Observed:**
- [ ] **MS-2 Drags.** Select three nodes, then drag one of them: all three move, and one ⌘Z puts them back. ⌘-drag a
  selected node: all move and all stay selected. ⇧- or ⌘-drag an unselected node: it joins and everything moves. ⌥-drag
  one of the three: three ghosts follow and three copies land, selected, as one undo step; ⌥-click without moving:
  nothing is copied. Pinned: `commandDragMovesTheSelectionAndKeepsIt`, `aModifiedDragOnAnUnselectedNodeAddsItAndMovesEverything`,
  `optionDragCopiesTheWholeSelectionOnlyOnceItMoves`. **Observed:**
- [ ] **MS-3 Box select.** A plain drag on empty canvas still pans. ⇧-drag a box over two unselected nodes: they join
  the selection. ⌘-drag a box over one selected and one unselected node: they swap. Start a ⇧-box and let go of ⇧
  just before the button: the box still adds (nothing selected before is lost). Grow a ⌘-box over a node, then shrink
  it away: the node is as it was. Pinned: `BoxSelectModeTests`. **Observed:**
- [ ] **MS-4 ⌘A and Esc.** Click the canvas, ⌘A: every node is selected. Click into an inspector number field, ⌘A:
  the field's text is selected and the canvas selection doesn't change; the same in the open palette's search field.
  Esc with the palette open closes it and keeps the selection; Esc again clears the selection. Start dragging a wire
  and press Esc with the button still held: the wire vanishes, and releasing over a socket connects nothing (record
  whether the Esc arrives during the drag at all). ⌥-drag ghosts then Esc: they vanish. ⇧-box then Esc: the selection
  is as before the box. With Pick edges in view under way, Esc cancels the pick and keeps the selection. Drag a node
  and, with the button still held, press ⌘A and → : nothing changes, and after the release one ⌘Z puts the node back.
  Pinned: `SelectionKeyTests`, `aNudgeDuringAMoveKeepsItOneUndoStep`. **Observed:**
- [ ] **MS-5 Arrows.** Select two nodes, click empty canvas with ⇧ (so no field has focus), press → three times:
  they move 3 points right, and ⌘Z three times puts them back step by step. Hold ⇧→ for a second: they glide right
  10 points per repeat, and one ⌘Z undoes the whole hold. Docked left, ↓ moves them down the screen. In a focused
  inspector field the arrows move the caret instead. Pinned: `NudgeTests`. **Observed:**
- [ ] **MS-6 F.** Select a node far off screen, put the pointer over the graph canvas and press F: the canvas pans and
  zooms so it is centred with a margin. With nothing selected, F frames every node. With the pointer over the
  viewport, F frames the part as before; in a focused inspector field F types. Pinned: `FramingTests`,
  `AppInputTests.fFramesTheGraphOverItsCanvasAndTheViewportElsewhere`. **Observed:**
- [ ] **MS-7 Panel hidden.** Hide the panel (Tab with the pointer off the canvas), then ⌘A and Delete: no node is
  deleted (show the panel to check); arrows move nothing. Pinned: `selectAllDoesNothingWhileThePanelIsHidden`,
  `withNothingSelectedOrThePanelHiddenTheKeyGoesOn`. **Observed:**
- [ ] **MS-8 Draw order.** Overlap three nodes, select the two at the back: they draw above the third, and a click
  where all three overlap selects the topmost drawn one. Docked at the bottom too. Pinned:
  `selectedNodesDrawLastAndAreHitFirst`. **Observed:**
```

(Answer (b): MS-3 opens "A plain drag on empty canvas draws a box that replaces the selection; a middle-button drag
and two-finger scroll pan." and goes on as above.)

- [ ] **Step 2: CLAUDE.md**

**Modify** `CLAUDE.md`, replace:

```markdown
Packaging (`scripts/package-app.sh`, `docs/packaging.md`) is done; its human checks (group P) are pending.
```

with:

```markdown
Packaging (`scripts/package-app.sh`, `docs/packaging.md`) is done; its human checks (group P) are pending.
Multi-select polish (sub-project A of `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md`) code is
done; its human checks (group MS) are pending.
```

**Modify** `CLAUDE.md`, replace:

```markdown
  Its input (MetalUI C7 gestures, and the key and focus stopgaps) lives only in `GraphPanelInput`.
```

with:

```markdown
  Its input (MetalUI C7 gestures, and the key and focus stopgaps) lives only in `GraphPanelInput`.
  The selection is `canvasSelection` (`CanvasSelection`: nodes, and comments once sub-project B lands); `selection`
  is its nodes, and assigning it replaces the whole selection. Every gesture and key goes through
  `EditorModel+Selection` (`select(_:mode:)` with `SelectionMode`: none replaces, ⇧ adds, ⌘ toggles; `allItems`,
  `items(for:)`, `items(intersecting:)`, `positions(of:)`, `moveCommands(from:by:)`, `bounds(of:)`), the only members
  comments extend (spec 2026-10-09 Errata (A)). ⌘A, arrows (one undo step per key-down run) and F act only while the
  panel shows; Esc closes the palette, then cancels a drag, then clears the selection.
```

**Modify** `CLAUDE.md`, replace:

```markdown
and the inspector contribute `Panel`), and over the graph canvas + and − are declined so the graph's zoom keys work. The
```

with:

```markdown
and the inspector contribute `Panel`), and over the graph canvas F, + and − are declined so the graph's own keys work
(F frames the graph's selection there). The
```

- [ ] **Step 3: Roadmap**

**Modify** `docs/superpowers/roadmap.md`, replace:

```markdown
| — | Viewport: frame in the model area — first framing, F and Look At centre the part in `ViewportModel.modelArea`, not the whole view (spec §6.3) | ✅ merged 2026-10-09 (human checks VC pending; the arrows, cube and pointer-less key zoom keep it there) | carry-over From M6 |
```

with:

```markdown
| — | Viewport: frame in the model area — first framing, F and Look At centre the part in `ViewportModel.modelArea`, not the whole view (spec §6.3) | ✅ merged 2026-10-09 (human checks VC pending; the arrows, cube and pointer-less key zoom keep it there) | carry-over From M6 |
| — | Multi-select polish (A): ⌘-click toggles, box select modes, ⌘A, Esc, arrow nudge, F frames the graph's selection, drags and ⌥-drags of the whole selection, on a `CanvasSelection` comments join (spec `2026-10-09-selection-groups-comments-design.md` §3, Errata (A: multi-select); plan `2026-10-09-multi-select.md`) | ✅ code done; human checks MS pending | Unblocks Comments (B) and Groups (C1, C2) |
```

- [ ] **Step 4: Spec errata**

**Append to** `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md`:

```markdown

## Errata (A: multi-select)

Plan `2026-10-09-multi-select.md`.

- Box select, as the user decided on <date> (Gate G, answer (a)): §3's "Existing: … a drag on empty canvas
  box-selects" is a drag *with ⇧*, and a plain drag pans (parent §6.2), as before. A box starts on a drag on empty
  canvas with ⇧ or ⌘ held; the modifiers held when the drag starts (crosses the drag threshold, as ⌥-duplicate's are)
  fix its mode for the whole drag: ⇧ adds, ⌘ toggles each node it covers (⌘ wins over ⇧). It is recomputed from the
  selection it began with at every step. "No modifier replaces" has no box gesture; to replace, click empty canvas
  first. Pinned: `BoxSelectModeTests`.
  (Answer (b) instead: "Box select, as the user decided on <date> (Gate G, answer (b)): a drag on empty canvas
  box-selects, replacing the selection; ⇧ adds and ⌘ toggles, the modifiers held when the drag starts fixing the mode
  for the whole drag. The parent §6.2's plain-drag pan moves to the middle button; two-finger scroll still pans.")
- §3's "⇧ keeps adding": a ⇧-click on a selected node now keeps it (before, it removed it); ⌘-click toggles; ⌘ wins
  when both are held. A drag on an unselected node with ⇧ or ⌘ adds it, then moves the whole selection.
- ⌘A, the arrows and F act only while the panel is visible (with it hidden, ⌘A then Delete would erase nodes no one
  can see), and pass the key on otherwise. A focused field keeps all three (they come from the window's `onInput`
  fallback). During a drag all three are claimed and do nothing, so a move stays one undo step.
- Esc also drops ⌥-drag ghosts and cancels a box (putting back the selection it began with); during a pan or a move
  it is claimed and does nothing, so it can't split the move's undo step. The rest of a cancelled press is ignored.
- F over the graph canvas frames the selection, or every node when nothing (still on the canvas) is selected, with
  40 screen points of padding, the zoom within 25–300%. `AppInput` declines the viewport's F (as it did + and −) while
  the pointer is over the canvas.
- Arrows nudge 1 canvas point (⇧ 10) the way they point on screen (the left dock's transpose is undone). A key-down
  that isn't an auto-repeat starts a new undo step; anything that ends coalescing (a press, a selection change, Undo)
  also does.
- The selection model B extends: `CanvasSelection` (B adds `comments: Set<CommentID>`), `SelectionPositions` (B adds
  `comments: [CommentID: Vector2]`), and `EditorModel`'s `allItems`, `items(for:)`, `items(intersecting:)`,
  `positions(of:)`, `moveCommands(from:by:)`, `bounds(of:)`, `clipboard(of:)`, `insert(_:offset:)` and
  `deleteSelection()`. Assigning `EditorModel.selection` selects exactly those nodes and no comments. Drags reach
  items only through `items(for:)`, so comment hits select and move without a pointer change; B's other edits are a
  frame's resize drag (its hit case before `items(for:)`, its `CanvasInteraction` case in `update`, `pointerReleased`
  and `cancelInteraction()`) and comment ghosts in `CanvasLayers.ghosts`.
- Graph keys still act in sketch mode, as Delete and ⌘C do: arrows nudge the Sketch node and ⌘A selects every node.
```

- [ ] **Step 5: Run the full check**

Expected: no new warning, no lint violation, `exit 0`, `0`, `11`, **1441** tests (master + 51; docs only).

- [ ] **Step 6: Commit**

```bash
git add docs/verification/human-checks.md CLAUDE.md docs/superpowers/roadmap.md \
  docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md
git commit -m "docs: multi-select errata, human checks MS, CLAUDE.md and roadmap"
```

---

## Self-review

- **Spec §3 coverage:** ⌘-click toggle, ⇧ adds, no modifier replaces, press-without-move collapse (⌘: toggle), ⌘-drag moves — Task 2. Modifiers from the press's drag value — Task 2 (a click: `SelectionMode(press.modifiers)`; a drag: the modifiers held as it crosses `dragThreshold`; `GraphPanelInput` unchanged). Box modes — Gate G, then Task 3 (Key decision 4: ⇧ adds, ⌘ toggles, the mode fixed as the drag starts; whether a plain drag box-selects, replacing, is the user's answer at Gate G, asked before Task 3 and the errata). "and comments" in box select and ⌘A — the `items(intersecting:)`/`allItems` hooks B extends. ⌘A on the current level, focused field keeps it — Task 4 (`onInput` fallback; MS-4). Esc after palette/wire/pick — Task 4 (pick's Esc is a button run first). Arrows 1/10 pt, one undo step per key-down run — Task 5. F frames the selection over the canvas, viewport's F unchanged — Task 6. Mixed drags, ⌥-drag duplicates the whole selection deferred until movement — Task 2 (`positions(of: canvasSelection)`; `dragThreshold`). Selection is view state — no `GraphCommand`/`ViewState` change anywhere. Selected items draw last and hit-tested in the same order — Task 1 pin. Human checks for A — Task 7 (group MS; GI-8 amended). Roadmap row "Multi-select polish (A)" — Task 7.
- **Placeholders:** none; every step has its code or command.
- **Type consistency:** `CanvasSelection(nodes:)`, `SelectionPositions(nodes:)`, `.items`, `SelectionMode(_:)`, `select(_:mode:)`, `positions(of:)`, `moveCommands(from:by:)`, `bounds(of:)`, `.boxSelecting(start:current:base:mode:)`, `.nudge(_:isRepeat:)`, `nudgeSelection(by:isRepeat:)`, `frameSelection()`, `framingPadding`, `CanvasTransform.framing(_:in:padding:)` are used with the same names and labels in every task.
- **Review Focus:** each of the six lines has its test in the owning task (named above).
- **Verified** (2026-10-09, after review): every code block applied task by task, by script, to a scratch copy of master `2e64c96` beside a `MetalUI` symlink (`2155f1e`), Task 3 as answer (a). After each task `swift build --build-tests` printed no new warning, `swiftlint lint --strict` no violation, and `swift test` exited 0 with no "recorded an issue"/"failed after" line and 11 "Test run with" lines: 1399, 1407, 1412, 1422, 1431, 1441, 1441 tests (master 1390 + 9, 17, 22, 32, 41, 51, 51). The three during-a-drag tests fail without `performSelectionCommand`'s `interaction == nil` guard (checked by removing it).
