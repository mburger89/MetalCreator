# MetalCreator M5: Graph Panel and Context Inspector — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Updated against merged M3 (4efa07d), 2026-10-07; re-checked against merged M4 (`e31ba17`) and master `fbb23d7`, 2026-10-07.** Every M1–M3 symbol the plan uses was checked against the merged `Sources/` and `Tests/`, and every M4 symbol against M4's merged code. The changes: the test and preview node mirrors now match M3's merged nodes (Extrude's "Reverse direction" toggle, Output's `.list` input and pass-through output, Graph Parameter's four optional outputs). M3's optional inputs with no default (Grid Points `total`, Edge Filter `maxLength`, Transform `axisDirection`) start unset and can be cleared (`InputField.isOptional`, `EditorModel.clearInput`). The C7 stand-ins are functions named after C7's provisional APIs (`GraphPanelInput.spatialTapGesture()`, `dragValueModifiers(_:)`). `GraphPanelInput.install(on:)` composes with M4's handlers. Task 1 starts with pre-flight checks that stop the run if M3 or M4 isn't in place. Task 11 adds a spec "Errata (M5)" entry. Test counts now end at 123. The re-check against `fbb23d7` added the SwiftLint gate (master's `.swiftlint.yml`, CLAUDE.md "Linting"): every commit step runs `swiftlint lint --strict`, and the plan's code was reworked to report zero violations (`GraphKeyBindings.command` and `EditorModel.perform` split by key group, `InspectorBuilder.row` split into `ruleSummary` and `valueRow`). It also narrowed the `install(on:)` decision (only `onInput` composes in either order; see Decisions) and said which C7 swap is body-only.

**Goal:** Build `CreatorEditor`, the graph panel and context inspector on MetalUI: a `@MainActor @Observable EditorModel` that owns selection, box-select, the canvas transform, the dock (with the left-dock transpose), hit testing, wire dragging with connect/refuse/replace, delete/copy/paste/duplicate/⌥-drag, the add-node palette and inspector editing with drag coalescing — all unit-tested — plus the MetalUI views that draw it in the Dracula palette, and a preview executable for the human visual check.

**Architecture:**
- **Model first, views thin** (spec §3.2). Everything a test needs lives in `EditorModel` and pure value types (`CanvasTransform`, `CanvasFlow`, `NodeLayout`, `WireGeometry`, `InspectorBuilder`, `PaletteSearch`, `GraphKeyBindings`). Every edit goes through `DocumentModel.perform`, so undo, evaluation and saving come for free.
- **Geometry is computed, not measured** (the concept ported from MetalNodes' `NodeGeometry`). `NodeLayout` gives node sizes and socket anchors; views are framed to those numbers, and hit testing uses the same numbers under the canvas transform. So drawing, wiring and hit testing cannot disagree.
- **One gesture for the whole canvas.** The canvas carries a single `DragGesture(minimumDistance: 0)`. Node and wire layers draw with hit testing off, and `EditorModel.hitTest` decides what a press landed on. This is the spec §9 stopgap for tap location (C7 gap 4), and it keeps every interaction rule in the testable model.
- **Stopgap input lives in one type**, `GraphPanelInput`. Each C7 stand-in is one function named after the provisional C7 API it waits for (docs/metalui-gaps.md): `spatialTapGesture()` (C7 `SpatialTapGesture`, gap 4) and `dragValueModifiers(_:)` (C7 `DragGesture.Value.modifiers`, gap 5, fed meanwhile by the window's `.modifiersChanged` events). It also maps keys from `Window.onInput` (the fallback that only sees keys no focused field claimed), and `install(on:)` chains onto the window's existing handlers, as M4's `ViewportModifierTracker.install(on:)` does for `onInput`. When C7 lands, only this file and its test change.
- **Views** are MetalUI `Component`s in the SwiftUI vocabulary (`ZStack`/`VStack`/`HStack`, `.offset`, `.scaleEffect`, `Path`). The canvas content sits under `.scaleEffect(zoom, anchor: .topLeading).offset(pan)`, so zoom and pan are render effects, not relayouts. That structure is what M7 will measure for "50 nodes pan at 60 fps".

**Tech Stack:** Swift 6.4 toolchain, Swift 6 language mode, SwiftPM, Swift Testing, MetalUI (`../MetalUI`, by path).

**Execution order: M3 → M4 → M5; M3 and M4 are merged.** M5 runs last, on M4's merged tree. M3 merged at `4efa07d` and M4 at `e31ba17`. Master is now `fbb23d7`: on top of M4 it adds the SwiftLint configuration (`bfa027e`, `.swiftlint.yml` and CLAUDE.md/AGENTS.md "Linting") and the lint fixes for the existing modules (`fbb23d7`). **M5 must start from master `fbb23d7` or later.** This plan's branch (`plans/m5-update`) was cut from `4efa07d`, so the controller either rebases it onto master before M5 starts or runs M5 on a fresh branch from master. Task 1 Step 1's pre-flight checks stop the run if any of these is missing (all of them pass on `fbb23d7`):
- **In M4's merged code:**
  - `Package.swift` has the `../MetalUI` dependency, `let metalUI: Target.Dependency`, `CreatorViewport`, `CreatorViewportTests` (which also depends on `CreatorOCCT`) and `ViewportHarness`.
  - `ViewState` has `camera` and `homeCamera: CameraPose?`, with `CameraPose` in `CreatorGeometry`. `DocumentModel` refuses a non-finite camera. Both fields are optional keys, so `GraphFile.currentFormatVersion` stays `2`.
  - `ViewportPalette` (`Sources/CreatorViewport/Render/`, internal tokens) holds the spec §6.6 hex values.
  - `ViewportModifierTracker.install(on:)` chains onto `Window.onInput`.
  - `ViewportKeyBindings.bindings()` are window-wide keymap bindings for `f`, `=`, `shift-+`, `+` and `-`. M4 has no installer for them: `ViewportHarness` assigns `window.keymap` and `window.onAction` directly.
  - `docs/verification/human-checks.md` with its header and "Group V".
  - `docs/metalui-gaps.md`'s "Hit by M4 (viewport), 2026-10-08" section, with gaps M4-a and M4-b.
  - The `CreatorViewport` bullet and the "M4 (viewport) code is done; …" sentence in `CLAUDE.md`/`AGENTS.md`.
- **In master after M4:** a tracked `.swiftlint.yml`, the "Linting" section in `CLAUDE.md`/`AGENTS.md`, and a clean `swiftlint lint --strict`.

`CreatorGraph` has M3's settings contract: `NodeSetting`, `ConstantValue.parameter(_:)` / `.parameterID`, `.edgePicks`, `NodeDefinition.defaultSettings`, `SocketSpec.isOptional`, and `NodeRegistry.makeNode`, which seeds the defaults and flags `.output` nodes. M5 adds no `ConstantValue` kind, so it doesn't bump the file format.

**Spec:** `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` — §3.1–3.2, §4.5 (coalescing), §6.1, §6.2, §6.4, §6.6, §8 (editor model tests), §9 (MetalUI gaps and stopgaps), the Errata. Also read `docs/metalui-gaps.md` (C7 provisional names) and `../MetalUI/docs/api-overview.md`.

**Verified against merged M3 (2026-10-07).** All 99 code files in this plan were extracted into a scratch copy of master `4efa07d` (merged M3). The scratch copy had M4's manifest lines (the `../MetalUI` dependency and `metalUI`) and M5's targets added, and was built against `../MetalUI` master `70ed000`, which has `.task` but not C7. The plan as first written built with no warnings, and all 120 of its tests passed against the real M3 sources. After this update's edits, `CreatorEditorTests` reports `Test run with 123 tests in 18 suites passed`, and every other target still passes. The preview builds, and it ran for five seconds without trapping. The per-task counts below are the cumulative `@Test` counts of each task's files, not separate per-task runs. M4's `CreatorViewport` wasn't in that first scratch copy (M5 doesn't import it).

**Re-verified against merged M4 (2026-10-07).** The verification was repeated on a clone of master `fbb23d7` (M4's `e31ba17` plus the SwiftLint commits), with `CreatorViewport`, `CreatorViewportTests` and `ViewportHarness` present and M5's three targets added in place, against `../MetalUI` master `70ed000`. An independent review had already applied all 99 files task by task on `e31ba17`: every task built with no warnings, and the cumulative counts were 8/20/29/40/60/80/87/114/121/123. After this revision's lint rework, the build has no Swift warnings (only the expected OCCT dylib linker warnings), the full `swift test` passes (`CreatorEditorTests`: `Test run with 123 tests in 18 suites passed`), `swiftlint lint --strict` over the whole tree reports no violations, and `GraphPanelPreview` stays up past five seconds. All the Task 1 pre-flight greps print their expected values on `fbb23d7`. Treat a compile error or a lint violation as a plan bug to fix in place.

**Prerequisites:**
- **M3 and M4 are merged, and M5 starts from master `fbb23d7` or later** (M4 plus the SwiftLint configuration). Task 1 Step 1 checks this with greps and stops the run if any check fails.
- **SwiftLint is installed** (`swiftlint version` prints a version; Homebrew's is `/opt/homebrew/bin/swiftlint`).
- **The working tree is clean.** `git status --short` lists nothing. The planning edits to `docs/metalui-gaps.md` and `docs/superpowers/roadmap.md` (the C7 provisional-names section, the C7 roadmap status) were committed by the controller before M3 started, so Task 11's `git add` sweeps in only M5's edits.

**Decisions made in this plan:**
- **`CreatorEditor` depends on `CreatorGraph`, `CreatorKernel`, `CreatorGeometry` and MetalUI, not `CreatorNodes`.** Spec §3.1 lists Nodes as a dependency, but the editor only needs `NodeRegistry` and `NodeDefinition` data. Tests and the preview use their own small node definitions. The app (M6) passes in the real registry.
- **Inline node values are read-only text.** Unwired inputs show their value on the node's row (spec §6.2). Editing happens in the inspector. A `TextField` inside the canvas would compete with the canvas-wide gesture and split keyboard focus (spec §9 lists that as a risk). This is a deliberate narrowing of "inline value fields". Task 11 records it in the spec's "Errata (M5)" and in the carry-over note. Revisit when C7 lands. Rows show only input sockets, never settings. An unset optional input shows "—".
- **⌥-drag shows ghosts and adds the copies on release.** `UndoStack` coalescing keeps only the *latest* forward command, so "add copies, then coalesce moves" would redo wrongly. Instead the originals never move, ghosts follow the pointer, and one `batch` of `addNode` plus `restoreLinks` lands on release. That is one undo step.
- **Paste uses `restoreLinks` for copied wires.** They join only freshly added nodes, so they are valid by construction. That also lets wires between missing (unregistered) nodes survive copying.
- **The clipboard is in-memory.** The slice has one document, and MetalUI's pasteboard carries text only.
- **Slider drags end on the next other interaction.** MetalUI's `Slider` has no `onEditingChanged` (logged as a gap). A drag's steps share one coalescing key per socket. The step ends when the selection changes, the canvas is pressed, another edit is made, or on undo or redo. Two separate drags of the same slider with nothing between them merge into one undo step. That is the accepted stopgap cost.
- **Tab is contextual.** The spec gives ⇥ two jobs, "Hidden (⇥ toggles it)" and "Tab or Space opens the palette". Tab opens the palette when the pointer is over a visible canvas, and otherwise toggles the panel. Space always opens the palette. MetalUI's Tab focus traversal claims Tab before `onInput` whenever a focusable control exists (the inspector always has number fields), so in practice Space is the reliable key (logged as a gap). **Hide is never a one-way trip:** while the panel is hidden, `GraphShowButton` ("Show graph") is on screen, and its `.keyboardShortcut(.tab, modifiers: [])` claims Tab in MetalUI's shortcut stage, which runs before focus traversal.
- **Keys arrive through `Window.onInput`.** It sees only keys that no focused field claimed, so Delete or Space typed into the inspector or the palette's search field never edits the graph. **Two exceptions, both because of MetalUI's dispatch order** (`Window` input pipeline: keymap → focused field's editing keys → raw `onKey` → `Button` shortcuts → Tab traversal → `onInput`):
  - **The palette's ↑/↓ go through the window keymap.** A focused single-line field on mac claims ↑ and ↓ (caret to start/end), so they never reach `onInput`. `GraphPanelInput.keymap` binds `up`/`down` to `PaletteMove`, and `GraphPanelInput.handleAction` runs it only while the palette is open. Otherwise the action is unhandled, and MetalUI passes the key on to the field as if it were unbound. Return reaches the palette through the field's `onSubmit`; Escape isn't a field key and reaches `onInput`.
  - **A canvas press releases text focus.** MetalUI never clears focus on an outside press (focus-by-click is deliberately not its policy), so a number field edited in the inspector would keep Delete, ⌘C/⌘V/⌘Z and Space while the user clicks nodes. `GraphPanelInput.releaseTextFocus` (the shell sets it to `window.focus(nil)`) runs at the start of every canvas press. This is logged as gap M5-g.
- **Only the key *mapping* is unit-tested.** MetalUI's `Window` initializer is internal, so tests can't drive a real window's dispatch. `GraphKeyBindings`, `GraphPanelInput.handle`, `handleAction` and `keymap` are pinned headless. The routing through a real window (fields keeping their keys, palette arrows, Tab on "Show graph", focus release) is pinned by human checks M5-5, M5-9, M5-11 and M5-12.
- **The hidden dock keeps the vertical flow**, and showing the panel again returns it to the side it was last docked on. If a file was saved while the panel was hidden, it shows on the left.
- **The inspector renders M3's whole control set** (M3 plan, "Decisions" and "Open risks"). `InspectorControl.socket` is an exhaustive `switch`, so a control kind added later fails to compile here instead of drawing nothing. `ValueText.format` uses `if case`: it formats every `ConstantValue` kind M3 ships, including `.edgePicks` ("2 picks"), and shows "—" only for a missing value or a kind added after M3. Likewise the inspector's `.readOnly` row is only for a missing node type, never for a known control.
  - **`.vector(socket)`** is three number fields (x, y, z). Each writes the whole `.vector`, with one component replaced (`InspectorBuilder.vectorValue`).
  - **`.parameterPicker(setting)`** is a menu over `graph.parameters`. It writes `ConstantValue.parameter(id)` into the node's setting (`NodeSetting.parameter`) and reads the choice back with `ConstantValue.parameterID`. Both live in `CreatorGraph` (M3 Task 3), so the editor and `GraphParameterNode` share one encoding and no agreement test is needed.
  - **Settings are names a control binds that aren't input sockets** (M3's `NodeSetting` in `CreatorGraph`: `parameter`, `picks`, `showHandle`). They are read from and written to `Node.inputValues` like constants. New nodes come from `NodeRegistry.makeNode`, which writes each definition's `defaultSettings`, so a fresh Fillet's `showHandle` toggle reads its stored `.bool(true)`. **A setting toggle with no stored value still reads On** (a node from a hand-edited file; M3 Open risks, "Seeded settings only reach new nodes").
  - **Nodes are created only with `registry.makeNode(typeID, at:)`.** It sets `isOutput` for `.output`-category nodes (M3), so the palette, paste and the preview need no special case for Output.
  - **`.ruleSummary(name)`** counts edges from an incoming wire when `name` is an input (Fillet's `edges`: "All Edges · 12 edges"). When `name` is one of the node's own outputs, as on every M3 selection-rule node, it counts the node's own result ("12 edges", or "No result yet").
  - **Optional inputs with no default start unset and can be cleared.** M3 has three: Grid Points `total` (when set, it overrides `countX`), Edge Filter `maxLength` and Transform `axisDirection`. Their row's `InputField` has `isOptional` and `value == nil`. The field shows "Not set" (a vector's three fields show "–"). Typing sets the input, and emptying the field and pressing Return calls `EditorModel.clearInput`, which is one `.setInput(node, socket, nil)` undo step. A required input is never cleared: it would fall back to its default with no sign.
  - The editor's test definitions mirror M3's merged nodes:
    - `FilletTestNode` has M3's `showHandle` setting toggle, seeded through `defaultSettings`, and no "Tangent chain" toggle (spec Errata (M3)).
    - `ExtrudeTestNode` has the "Reverse direction" toggle on its `reversed` bool socket (spec Errata (M3): the Direction menu became a toggle).
    - `AllEdgesTestNode` has an own-output `ruleSummary`.
    - `OutputTestNode` has M3's `.list` input and pass-through output.
    - In `inspectorTestRegistry`: `TransformTestNode` carries `.vector`, `GraphParameterTestNode` carries `.parameterPicker` and M3's four optional outputs, and `GridPointsTestNode` has the optional `total`.
- **The anchor grid binds an integer socket, 0…8 row-major from the top-left, with 4 as the centre.** Segmented controls bind an integer index, a two-option bool, or the option's text, following the socket's declared type. M3's node definitions match these encodings (M3 "Segmented controls bind integer sockets").
- **Typed whole numbers never trap.** An integer field or parameter rounds the typed number and converts it with `Int(exactly:)`. A number outside `Int`'s range (for example "1e300") is refused with "Enter a whole number." (`EditorModel.setNumber`, `setParameterNumber`).
- **Numbers are shown and parsed in one fixed locale (`en_US_POSIX`)**, so "0.25" never shows as "0,25", which `ValueText.parse` would then refuse. Localised number entry is deferred along with string localisation. This is separate from M3's `Locale.messages` (`en_US`) and `Double.display`, which format numbers inside node messages: they are internal to `CreatorNodes`, which the editor doesn't import. The editor shows those messages as they come.
- **Wires are removed by dragging them off their input.** A drag that starts on a wired input and is dropped on empty canvas disconnects that wire, as one undo step. Dropped on another output, it reconnects (replacing), as before.
- **The refusal shake is a spring.** A refused node's offset jumps 6 pt and springs back with `.animation(.spring(duration: 0.35, bounce: 0.7), value:)`, so it wobbles briefly (spec §6.2's "brief shake"). MetalUI has no keyframe animation for a true back-and-forth shake.
- **C7 stand-ins are named after C7's provisional APIs** (docs/metalui-gaps.md, "C7 status and provisional API names"). Each is one function in `GraphPanelInput`, so the swap stays inside `GraphPanelInput` and `GraphPanelInputTests`:
  - `dragValueModifiers(_:)` stands in for `DragGesture.Value.modifiers`: it returns the modifiers `handle(_:)` tracked from `.modifiersChanged`. **This swap is body-only.** C7's `DragGesture.Value.modifiers` is `EventModifiers`, a typealias of MetalUI's `Modifiers` (`feat/input-apis`, `KeyboardShortcut.swift`), so the body becomes `Self.canvasModifiers(value.modifiers)` and the signature stays.
  - `spatialTapGesture()` stands in for `SpatialTapGesture`: a zero-distance `DragGesture` reports a click's location. **This swap is not body-only.** Its return type changes from `DragGesture` to `SpatialTapGesture`, so `canvasGesture()`, which is built on it today, splits into a tap gesture for clicks plus a `DragGesture` with a nonzero minimum distance for drags. The `spatialTapGesture().minimumDistance == Pixels(0)` check in `theC7StandInsAreTheirOwnFunctions` stops compiling and is rewritten in the same change.
  - Scroll and pinch (`.onScrollWheel`, `MagnifyGesture`) have no stand-in: the +/− keys and header zoom buttons are the stopgap, and they stay after C7.

  MetalUI's C7 design is drafted on its unmerged branch `feat/input-apis` (`docs/superpowers/specs/2026-10-08-input-apis-design.md`, decisions prefixed CI-). It spells these `SpatialTapGesture(count:coordinateSpace:)`, `DragGesture.Value.modifiers` and `.onScrollWheel(perform:)`. Re-check the names in its decisions file when it merges.
- **`GraphPanelInput.install(on:)` composes with M4, with one ordering rule.** It chains `onInput` and `onAction` to the handlers already there, appends its keymap bindings, and sets `releaseTextFocus` to `window.focus(nil)`. Only the `onInput` side composes in either order: M4's `ViewportModifierTracker.install(on:)` chains `onInput` the same way (M4 carry-over, "Both input stopgaps take over `Window.onInput`"). M4 has no installer for its keymap or `onAction`. `ViewportHarness` assigns them directly (`window.keymap = Keymap(ViewportKeyBindings.bindings())`, `window.onAction = { … }`). **The viewport's keymap and `onAction` must therefore be set before `GraphPanelInput.install(on:)`, or appended and chained the same way.** If M6 assigns them afterwards, as the harness does, the assignment drops the graph's `PaletteMove` bindings and `handleAction`, and the palette's ↑/↓ stop working while its search field is focused. `install(on:)` is not unit-tested, because MetalUI's `Window` can't be built in tests. One conflict stays for M6: M4's window-wide keymap binds `=`, `+`, `shift-+` and `-`, and the keymap stage runs before `onInput`, so with both installed those keys zoom the viewport, not the graph. M6 gives the viewport's bindings a key context (gap M4-a).
- **Glass without blur.** MetalUI offers no materials and no `.blur`. Panels are `#21222c` at 86% with the hairline border, and the blur is logged as a gap. MetalUI has no gradients either, so the preview's background is the solid `#191a21`.

## Global Constraints

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`, `platforms: [.macOS(.v26)]`. Strict concurrency. No `@unchecked Sendable`, no `nonisolated(unsafe)`.
- Tests use **Swift Testing** only (`import Testing`, `@Test`, `#expect`, `#require`).
- `@Observable` classes are `@MainActor`.
- One type per Swift file, named after the type. Extensions go in `Type+Purpose.swift`. Test and preview fixture files may hold several helpers and must say so in a header comment.
- Avoid force unwraps and force `try`. No GCD. No third-party packages. MetalUI is a local path dependency.
- MetalUI gaps are logged in `docs/metalui-gaps.md` and are never worked around in a way that would have to be undone. Stopgaps live only in `GraphPanelInput`, and each C7 stand-in is one function named after its provisional C7 API (`spatialTapGesture()`, `dragValueModifiers(_:)`). The non-C7 exceptions are `GraphShowButton`'s Tab shortcut (M5-b) and `PaletteMove` (M5-h).
- Colours come only from `Palette` tokens (spec §6.6). Text uses MetalUI's semantic text styles (`.caption`, `.callout`, `.headline`, …); no font sizes are hard-coded.
- Every graph edit goes through `DocumentModel.perform(_:coalescingKey:)`. Views hold no logic that a test needs.
- `CreatorEditor` must not import `CreatorNodes` or `CreatorOCCT`.
- **SwiftLint gates every commit** (CLAUDE.md "Linting", `.swiftlint.yml`). Each commit step runs `swiftlint lint --strict` over the whole tree first, and it must report zero violations. The plan's code is lint-clean as written. If a deviation trips a rule, fix the code (split a long `switch` by key group, as `GraphKeyBindings` and `EditorModel.perform` do). Use a `// swiftlint:disable:next <rule>` only with a reason on the same line.
- Every commit message ends with a blank line, then the implementing model's harness-provided `Co-Authored-By:` and `Claude-Session:` lines.
- Expected noise: linker warnings that OCCT dylibs were "built for newer macOS version" (from other targets).

## Review Focus

These are inputs and conditions that the spec implies, that a person will meet in the first minutes of use, and that fail quietly if nobody pins them. Each has a test in the named task, except where it says the real-window routing is a human check. The first two are the riskiest, because they depend on another plan and on MetalUI's input dispatch, which the model tests can't see.

1. **The inspector contract with M3.** Every control M3's node definitions declare must draw and write in M3's encoding. That means `.vector` (Transform, Revolve, Edges by Direction), `.parameterPicker` writing `ConstantValue.parameter(id)` (Graph Parameter, which the bracket demo needs), a `showHandle` setting toggle that reads its seeded `.bool(true)` (and On when absent), and an own-output `.ruleSummary("edges")` on the selection-rule nodes that shows the node's match count, Extrude's "Reverse direction" toggle on a bool socket, and M3's optional inputs (Grid Points `total`), which start unset and can be cleared. *Task 8: `aVectorControlEditsOneComponent`, `aParameterPickerListsTheDocumentParametersAndWritesTheID`, `aSettingToggleReadsOnWhenAbsent`, `aSocketToggleReadsItsDefaultAndWritesABool`, `anOptionalInputStartsUnsetAndCanBeCleared`, `aRuleNodeSummarisesItsOwnOutput`, `ruleSummaryCountsTheEdgesItsRuleMatched`; Task 10: `vectorParameterAndOptionalRowsDraw`.*
2. **Key and focus routing through a real `Window`.** MetalUI hands a keystroke to the window keymap, then a focused field's editing keys, then `Button` shortcuts, then Tab traversal, and only then `onInput`. A focused field keeps its keys even after a press elsewhere. So: palette ↑/↓ must go through `GraphPanelInput.keymap`/`handleAction` (a focused field takes them otherwise). A canvas press must release text focus, or Delete and ⌘Z keep editing the last inspector field. Hidden must be undone by "Show graph" or its Tab shortcut. *Task 6: `paletteArrowsAreKeymapActionsOnlyWhileThePaletteIsOpen`, `aCanvasPressReleasesTextFocusOncePerPress`, `theC7StandInsAreTheirOwnFunctions`; Task 9: `theHiddenPanelLeavesAShowButton`. These pin only the mapping. The real-window routing is human checks M5-5, M5-9, M5-11 and M5-12.*
3. **Clicking under zoom, pan and the left-dock transpose.** A click must land on the node or socket drawn under the pointer at any zoom, after panning, and in the transposed vertical flow. The socket grab radius must stay a constant size on screen. *Task 3: `hitsANodeUnderAZoomedAndPannedCanvas`, `socketHitRadiusIsInScreenPoints`, `leftDockHitsTheTransposedPosition`; Task 5: `leftDockMovesInStoredCoordinates`.*
4. **A click that jitters by a pixel or two.** It must select, not move the node, and must add no undo step. An ⌥-click must not duplicate. A gesture that never ended must not leak into the next press. *Task 5: `aTinyMoveIsStillAClick`, `anOptionClickDoesNotDuplicate`, `aPressThatNeverEndedDoesNotLeakIntoTheNext`.*
5. **A refused, replacing or removed wire.** A wrong-type, output-to-output or cyclic drop leaves the graph untouched and says why in plain words. Dropping on an occupied input replaces the old wire, and one undo brings it back. Dragging a wired input onto empty canvas removes its wire. *Task 4: `aRefusedConnectionChangesNothingAndSaysWhy`, `connectReplacesTheOccupiedInputInOneUndoStep`; Task 5: `aTypeMismatchIsRefusedWithAPlainMessage`, `outputToOutputIsRefused`, `aCycleIsRefused`, `droppingOnAnOccupiedInputReplacesItsWireInOneUndoStep`, `draggingAWiredInputOntoEmptyCanvasDisconnectsIt`.*
6. **Slider drags, typed values and undo.** One drag of a slider must be one undo step, and a drag on another node (or after clicking elsewhere) must be its own step. Typed values are one step each. A non-finite typed value is refused, not saved. A huge number typed into a whole-number field is refused, never a trap. Shown numbers don't depend on the machine's locale. *Task 8: `aSliderDragIsOneUndoStep`, `changingTheSelectionEndsTheDrag`, `pressingTheCanvasEndsTheDrag`, `typedValuesAreEachTheirOwnStep`, `aNonFiniteValueIsRefusedWithAMessage`, `aHugeWholeNumberIsRefusedNotTrapped`; Task 7: `typedNumbersMayCarryTheirUnit`, `formattingIgnoresTheCurrentLocale`.*
7. **Typing into the palette while the graph listens for keys.** Space, Delete and letters typed into the search field must reach the field, not delete or add nodes. Only Escape, the arrows and Return drive the palette. A query with no matches must not add anything. *Task 6: `whileThePaletteIsOpenOnlyItsNavigationKeysAreTaken`, `confirmingWithNoMatchesKeepsThePaletteOpen`, `mappedKeysAreRunAndClaimed`.*

---

## File Structure

```
Package.swift                                  CreatorEditor + tests (Task 1), preview (Task 11); reuses M4's MetalUI dependency and `metalUI`
Sources/CreatorEditor/
  HexColor.swift, Palette.swift                (Task 1) Dracula tokens, spec §6.6
  Double+Pixels.swift                          (Task 1) Double → MetalUI Pixels
  GlassPanel.swift                             (Task 1) glass chrome
  CanvasTransform.swift, CanvasRect.swift      (Task 2) pan/zoom math, rectangles
  CanvasFlow.swift                             (Task 2) dock → flow, the transpose
  NodeShape.swift, NodeLayout.swift            (Task 2) computed node geometry and socket anchors
  WireGeometry.swift                           (Task 2) bezier control points and bounds
  SocketRef.swift, CanvasHit.swift, CanvasModifiers.swift, WireDrag.swift,
  CanvasInteraction.swift, RefusalFeedback.swift, NodeClipboard.swift,
  InspectorRequest.swift, SearchPaletteState.swift   (Task 3) model value types
  EditorModel.swift                            (Task 3) state, dock, transform, geometry, hit testing
  SocketType+DisplayName.swift, ConnectionProblem+Message.swift,
  GraphError+Message.swift                     (Task 4) plain-language refusals
  EditorModel+Editing.swift                    (Task 4) connect, delete, copy, paste, duplicate, add
  EditorModel+Pointer.swift                    (Task 5) click, pan, move, box-select, ⌥-drag, wire drag
  PaletteEntry.swift, PaletteSearch.swift, EditorModel+Palette.swift   (Task 6) add-node palette
  GraphKeyCommand.swift, GraphKeyBindings.swift, EditorModel+Commands.swift   (Task 6) keys
  PaletteMove.swift, GraphPanelInput.swift     (Task 6) the palette keymap action, the stopgap input mapping
  PlaneChoice.swift, ValueText.swift, StatusBadge.swift, InspectorLabel.swift   (Task 7) formatting
  InputField.swift, InspectorRow.swift, InspectorHeader.swift, InspectorSectionRows.swift,
  ParameterRow.swift, InspectorPage.swift, InspectorControl+Socket.swift,
  InspectorBuilder.swift, EditorModel+Inspector.swift   (Task 8) inspector data and editing
  WireShape.swift, WireView.swift, NodeRowModel.swift, NodeView.swift, NodeHeaderView.swift,
  StatusBadgeView.swift, NodeRowView.swift, SocketLayer.swift, CanvasLayers.swift,
  BoxSelectionView.swift, GraphCanvas.swift, SearchPaletteView.swift, PaletteEntryRow.swift,
  GraphPanelHeader.swift, GraphPanel.swift, GraphShowButton.swift   (Task 9) the graph panel views
  NumberEntry.swift, LabeledRow.swift, AnchorGridView.swift, AnchorCell.swift,
  InspectorRowView.swift, InspectorHeaderView.swift, InspectorSectionView.swift,
  ParameterRowView.swift, InspectorPanel.swift (Task 10) the inspector views
Sources/GraphPanelPreview/                     (Task 11) main.swift, PreviewRoot.swift, PreviewDocument.swift, PreviewNodes.swift
Tests/CreatorEditorTests/
  Support/RenderSupport.swift                  (Task 1) headless frame helper
  Support/EditorTestNodes.swift, Support/EditorTestSupport.swift   (Task 2) test node definitions, IDs
  Support/EditorModelTestSupport.swift         (Task 3) makeEditor, screen points
  Support/PointerTestSupport.swift             (Task 5) click and drag helpers
  Support/SampleGraph.swift                    (Task 9) sample document for render tests
  PaletteTests, GlassPanelRenderTests          (Task 1)
  CanvasGeometryTests, WireGeometryTests       (Task 2)
  HitTestTests, DockTests                      (Task 3)
  EditingTests                                 (Task 4)
  PointerTests, WiringTests                    (Task 5)
  SearchPaletteTests, KeyCommandTests, GraphPanelInputTests   (Task 6)
  FormattingTests                              (Task 7)
  InspectorTests, CoalescingTests              (Task 8)
  CanvasLayersTests, GraphPanelRenderTests     (Task 9)
  InspectorRenderTests                         (Task 10)
docs/metalui-gaps.md, docs/verification/human-checks.md, CLAUDE.md, AGENTS.md, docs/superpowers/roadmap.md,
docs/superpowers/notes/2026-10-07-m0-m1-carryover.md, the spec's Errata (M5)   (Task 11)
```

---

### Task 1: The `CreatorEditor` target, the Dracula palette and glass chrome

This is the riskiest join, so it goes first. It proves the package links MetalUI and that a headless MetalUI frame builds from our code.

**Files:**
- Modify: `Package.swift`
- Create: `Sources/CreatorEditor/HexColor.swift`, `Sources/CreatorEditor/Palette.swift`, `Sources/CreatorEditor/Double+Pixels.swift`, `Sources/CreatorEditor/GlassPanel.swift`
- Test: `Tests/CreatorEditorTests/PaletteTests.swift`, `Tests/CreatorEditorTests/GlassPanelRenderTests.swift`, `Tests/CreatorEditorTests/Support/RenderSupport.swift`

**Interfaces:**
- Consumes: `CreatorGraph.NodeCategory`, `SocketType`, `NodeState`. From MetalUI: `Color(red:green:blue:opacity:)`, `RoundedRectangle`, `.background(_:in:)`, `.overlay`, `strokeBorder`, `renderFrame(_:size:scaleFactor:textSystem:atlas:)`, and `CoreTextTextSystem`/`GlyphAtlas` (module `MetalUIText`, importable through the `MetalUI` product).
- Produces:
  - `public struct HexColor: Hashable, Sendable { rgb: UInt32; opacity: Double; init(_:opacity:); func opacity(_:) -> HexColor; var color: Color }`
  - `public enum Palette` with tokens `backgroundTop, backgroundBottom, glass, hairline, panelBase, nodeBody, field, primaryText, secondaryText, green, purple, pink, orange, comment, cyan, yellow, red, textOnAccent, primaryButton, focus, statusOK, statusWarning, statusError` and functions `header(for: NodeCategory)`, `selection(for:)`, `socket(_: SocketType)`, `status(_: NodeState)`, all returning `HexColor`.
  - `extension Double { var px: Pixels }` (internal).
  - `struct GlassPanel<Body: ElementGroup>: Component` with `init(@ElementBuilder _ body: () -> Body)` (internal).
  - Test helper `renderHeadless(_ panel: () -> some ElementGroup) -> Scene`.

- [ ] **Step 1: Pre-flight checks. Stop if any fails.**

Run each check from the repository root and compare its output with the expected value. **If any check differs, stop and report it to the controller. Don't add the missing piece yourself:** it belongs to M3 or M4, and M5's later steps edit those files in place.

M3 (merged at `4efa07d`; these pass on master):
- `grep -c "case vector\|case parameterPicker" Sources/CreatorGraph/InspectorControl.swift` → `2`. The inspector switches over every control kind, so it doesn't compile without them.
- `grep -c "static let showHandle\|static let parameter" Sources/CreatorGraph/NodeSetting.swift` → `2`
- `grep -c "func parameter(" Sources/CreatorGraph/ConstantValue+Settings.swift` → `1`
- `grep -c "case edgePicks" Sources/CreatorGraph/ConstantValue.swift` → `1`
- `grep -c "currentFormatVersion = 2" Sources/CreatorGraph/GraphFile.swift` → `1`
- `grep -c "isOutput: definition?.category == .output" Sources/CreatorGraph/NodeRegistry.swift` → `1`
- `grep -c "public var isOptional" Sources/CreatorGraph/SocketSpec.swift` → `1`
- `grep -c "public func list(" Sources/CreatorGraph/NodeInputs.swift` → `1`

M4 (merged at `e31ba17`; these pass on master):
- `grep -c 'let metalUI: Target.Dependency' Package.swift` → `1`
- `grep -c '.package(path: "../MetalUI")' Package.swift` → `1`
- `grep -c 'name: "ViewportHarness"' Package.swift` → `1`
- `grep -c "public var camera: CameraPose?" Sources/CreatorGraph/ViewState.swift` → `1`
- `grep -c "public func install(on window: Window)" Sources/CreatorViewport/View/ViewportModifierTracker.swift` → `1`

M4's docs (merged with M4, from M4 plan Task 11). Task 11 here appends after these, so they must exist:
- `grep -c "^## Group V" docs/verification/human-checks.md` → `1`
- `grep -c "^## Hit by M4 (viewport)" docs/metalui-gaps.md` → `1`
- `grep -c '^- \*\*M4-[ab] (new)' docs/metalui-gaps.md` → `2`
- `grep -c "M4 (viewport) code is done" CLAUDE.md AGENTS.md` → `CLAUDE.md:1` and `AGENTS.md:1`
- ``grep -c '^- `CreatorViewport`' CLAUDE.md`` → `1`

SwiftLint (master `bfa027e`/`fbb23d7`, after M4). Every commit step below runs the linter, so it must be in place and clean before M5 adds code:
- `git ls-files .swiftlint.yml` → `.swiftlint.yml`
- `grep -c '^## Linting' CLAUDE.md AGENTS.md` → `CLAUDE.md:1` and `AGENTS.md:1`
- `swiftlint lint --strict --quiet` → prints nothing and exits 0

- [ ] **Step 2: Add the target to `Package.swift`**

Edit `Package.swift` in place; don't replace it. M3's targets (`CreatorNodes`, `CreatorNodesTests`) and M4's (`CreatorViewport`, `CreatorViewportTests`, `ViewportHarness`) all stay. M4 already added the MetalUI dependency and the `metalUI` constant, so don't add either again (`grep -c '.package(path: "../MetalUI")' Package.swift` stays `1`).

Add these two targets to the `targets:` array, just before `.testTarget(name: "CreatorOCCTTests", …)`:
```swift
        .target(name: "CreatorEditor", dependencies: ["CreatorGraph", "CreatorKernel", "CreatorGeometry", metalUI]),
        .testTarget(
            name: "CreatorEditorTests",
            dependencies: ["CreatorEditor", "CreatorGraph", "CreatorKernel", "CreatorGeometry", metalUI]
        ),
```
Check: `grep -c 'name: "CreatorEditor"' Package.swift` prints `1`, and `git diff Package.swift` shows only additions.

- [ ] **Step 3: Write the failing tests**

`Tests/CreatorEditorTests/Support/RenderSupport.swift`:
```swift
// Test fixture file: the headless frame helper shared by the render tests.
import MetalUI
import MetalUIText

/// A headless frame of `panel` (MetalUI's `renderFrame`, its `ImageRenderer` analogue), wrapped
/// in a `ZStack` because a frame's root must be an `Element` and a `Component` is a group.
@MainActor
func renderHeadless<Panel: ElementGroup>(_ panel: () -> Panel) -> Scene {
    let content = panel()
    return renderFrame({ ZStack { content } }, size: Size(width: Pixels(900), height: Pixels(600)), scaleFactor: 2,
                       textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
}
```

`Tests/CreatorEditorTests/PaletteTests.swift`:
```swift
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

struct PaletteTests {
    @Test(arguments: [
        (NodeCategory.value, UInt32(0x6272a4)), (.profile, 0x50fa7b), (.solid, 0xbd93f9),
        (.selection, 0xff79c6), (.feature, 0xffb86c), (.output, 0x8be9fd),
    ])
    func headerColoursFollowTheSpecTable(_ category: NodeCategory, _ rgb: UInt32) {
        #expect(Palette.header(for: category) == HexColor(rgb))
    }

    @Test func selectionGlowIsTheNodesOwnHeaderColour() {
        for category in NodeCategory.allCases {
            #expect(Palette.selection(for: category) == Palette.header(for: category))
        }
    }

    @Test func textOnAccentsIsThePanelBase() {
        #expect(Palette.textOnAccent == HexColor(0x282a36))
    }

    @Test func socketsShareTheirCategoryColours() {
        #expect(Palette.socket(.profile) == Palette.header(for: .profile))
        #expect(Palette.socket(.solid) == Palette.header(for: .solid))
        #expect(Palette.socket(.edgeSet) == Palette.header(for: .selection))
        #expect(Palette.socket(.faceSet) == Palette.header(for: .selection))
        #expect(Palette.socket(.number) == Palette.header(for: .value))
    }

    @Test func glassAndHairlineHaveTheirOpacities() {
        #expect(Palette.glass == HexColor(0x21222c, opacity: 0.86))
        #expect(Palette.hairline == HexColor(0xffffff, opacity: 31.0 / 255))
    }

    @Test func statusColours() {
        #expect(Palette.status(.ok(duration: .milliseconds(3))) == HexColor(0x50fa7b))
        #expect(Palette.status(.warning("w")) == HexColor(0xf1fa8c))
        #expect(Palette.status(.error("e")) == HexColor(0xff5555))
    }

    @Test func hexColourBecomesAnSRGBColour() {
        #expect(HexColor(0xff8000, opacity: 0.5).color == Color(red: 1, green: 128.0 / 255, blue: 0, opacity: 0.5))
    }
}
```

`Tests/CreatorEditorTests/GlassPanelRenderTests.swift`:
```swift
import MetalUI
import Testing
@testable import CreatorEditor

/// Proves the editor links MetalUI and that a headless frame of the glass chrome builds,
/// lays out and paints text. Colours are a human check (docs/verification/human-checks.md).
@MainActor
struct GlassPanelRenderTests {
    @Test func aGlassPanelDrawsItsContent() {
        let scene = renderHeadless { GlassPanel { Text("Graph") } }
        #expect(!scene.glyphs.isEmpty)
        #expect(!scene.isEmpty)
    }
}
```

- [ ] **Step 4: Run them and confirm they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: the build fails because `Sources/CreatorEditor` is empty or missing, or with errors such as "cannot find 'Palette' in scope" and "cannot find 'GlassPanel' in scope". (The first build also fetches and compiles MetalUI, which takes a few minutes.)

- [ ] **Step 5: Implement**

`Sources/CreatorEditor/HexColor.swift`:
```swift
import MetalUI

/// An sRGB colour written as `0xRRGGBB` plus an opacity, so palette tokens read like the spec's
/// table (spec §6.6) and tests can compare them exactly.
public struct HexColor: Hashable, Sendable {
    public var rgb: UInt32
    public var opacity: Double

    public init(_ rgb: UInt32, opacity: Double = 1) {
        self.rgb = rgb
        self.opacity = opacity
    }

    /// The same colour at another opacity.
    public func opacity(_ opacity: Double) -> HexColor { HexColor(rgb, opacity: opacity) }

    /// The MetalUI colour for drawing.
    public var color: Color {
        Color(red: Double((rgb >> 16) & 0xff) / 255,
              green: Double((rgb >> 8) & 0xff) / 255,
              blue: Double(rgb & 0xff) / 255,
              opacity: opacity)
    }
}
```

`Sources/CreatorEditor/Palette.swift`:
```swift
import CreatorGraph

/// The Dracula palette of spec §6.6, defined once and used everywhere by token.
public enum Palette {
    // Surfaces
    public static let backgroundTop = HexColor(0x3a3d4e)
    public static let backgroundBottom = HexColor(0x191a21)
    /// Glass panels: `#21222c` at about 86%. Blur is a MetalUI gap (docs/metalui-gaps.md).
    public static let glass = HexColor(0x21222c, opacity: 0.86)
    /// The 1-pt hairline around glass panels, `#ffffff1f`.
    public static let hairline = HexColor(0xffffff, opacity: Double(0x1f) / 255)
    /// Panel base, and the text colour on every accent fill.
    public static let panelBase = HexColor(0x282a36)
    public static let nodeBody = HexColor(0x343746)
    /// Fields, tracks and dividers.
    public static let field = HexColor(0x44475a)
    public static let primaryText = HexColor(0xf8f8f2)
    public static let secondaryText = HexColor(0x6272a4)

    // Accents
    public static let green = HexColor(0x50fa7b)
    public static let purple = HexColor(0xbd93f9)
    public static let pink = HexColor(0xff79c6)
    public static let orange = HexColor(0xffb86c)
    public static let comment = HexColor(0x6272a4)
    public static let cyan = HexColor(0x8be9fd)
    public static let yellow = HexColor(0xf1fa8c)
    public static let red = HexColor(0xff5555)

    /// Text drawn on any accent fill (headers, primary buttons, badges) is `#282a36`.
    public static let textOnAccent = panelBase
    /// Primary buttons and slider fill.
    public static let primaryButton = purple
    /// Focus outside the graph (keyboard focus, viewport hover).
    public static let focus = cyan

    public static let statusOK = green
    public static let statusWarning = yellow
    public static let statusError = red

    /// A node's header colour, by category.
    public static func header(for category: NodeCategory) -> HexColor {
        switch category {
        case .value: comment
        case .profile: green
        case .solid: purple
        case .selection: pink
        case .feature: orange
        case .output: cyan
        }
    }

    /// A selected node's outline and glow: always its own header colour (spec §6.6).
    public static func selection(for category: NodeCategory) -> HexColor { header(for: category) }

    /// A socket's colour, and the colour of wires leaving it, by type.
    public static func socket(_ type: SocketType) -> HexColor {
        switch type {
        case .profile: green
        case .solid: purple
        case .edgeSet, .faceSet: pink
        case .number, .integer, .bool, .vector, .plane: comment
        }
    }

    /// The colour for a node's status badge.
    public static func status(_ state: NodeState) -> HexColor {
        switch state {
        case .ok: statusOK
        case .warning: statusWarning
        case .error: statusError
        case .idle, .evaluating: secondaryText
        }
    }
}
```

`Sources/CreatorEditor/Double+Pixels.swift`:
```swift
import MetalUI

extension Double {
    /// This canvas length as MetalUI points. Canvas geometry is `Double`; MetalUI lengths are `Float`.
    var px: Pixels { Pixels(Float(self)) }
}
```

`Sources/CreatorEditor/GlassPanel.swift`:
```swift
import MetalUI

/// Glass chrome for floating panels (spec §6.1, §6.6): `#21222c` at 86%, a 1-pt `#ffffff1f`
/// hairline and rounded corners. The background blur is a MetalUI gap (materials and `.blur`
/// are not offered; docs/metalui-gaps.md), so the panel is translucent without blur.
struct GlassPanel<Body: ElementGroup>: Component {
    let body: Body

    init(@ElementBuilder _ body: () -> Body) {
        self.body = body()
    }

    var content: some ElementGroup {
        let shape = RoundedRectangle(cornerRadius: Pixels(10))
        return ZStack(alignment: .topLeading) { body }
            .padding(Edges(all: Pixels(10)))
            .background(Palette.glass.color, in: shape)
            .overlay { shape.strokeBorder(Palette.hairline.color, lineWidth: Pixels(1)) }
    }
}
```

- [ ] **Step 6: Run the tests**

Run: `swift test --filter CreatorEditorTests`
Expected: PASS — `Test run with 8 tests in 2 suites passed`. The parameterised header test counts as one test with 6 cases.

- [ ] **Step 7: Commit**

```bash
swiftlint lint --strict   # must report 0 violations before committing (CLAUDE.md "Linting")
git add Package.swift Sources/CreatorEditor Tests/CreatorEditorTests
git commit -m "feat(editor): add CreatorEditor on MetalUI with the Dracula palette and glass chrome"
```

---

### Task 2: Canvas geometry — transform, flow transpose, node layout, wire curves

**Files:**
- Create: `Sources/CreatorEditor/CanvasTransform.swift`, `CanvasRect.swift`, `CanvasFlow.swift`, `NodeShape.swift`, `NodeLayout.swift`, `WireGeometry.swift`
- Test: `Tests/CreatorEditorTests/CanvasGeometryTests.swift`, `Tests/CreatorEditorTests/WireGeometryTests.swift`, `Tests/CreatorEditorTests/Support/EditorTestNodes.swift`, `Tests/CreatorEditorTests/Support/EditorTestSupport.swift`

**Interfaces:**
- Consumes: `Vector2` (`CreatorGeometry`: `+`, `-`, `* Double`, `length`, `isFinite`), `ViewState`, `DockSide`, `Node`, `Graph`, `NodeRegistry`, `SocketName`, `SocketType`, `NodeCategory`.
- Produces:
  - `public struct CanvasTransform: Equatable, Sendable { offset: Vector2; zoom: Double; static zoomRange = 0.25...3; static zoomStep = 1.25; init(offset:zoom:); init(_ viewState: ViewState); toScreen(_:); toCanvas(_:); zoomed(by:around:) -> CanvasTransform; panned(by:) -> CanvasTransform }`. Here `screen = canvas × zoom + offset`.
  - `public struct CanvasRect: Equatable, Sendable { origin, size: Vector2; init(origin:size:); init(corner:_:); maxX; maxY; contains(_:); intersects(_:) }`
  - `public enum CanvasFlow { case horizontal, vertical; init(_ dock: DockSide); display(_ stored:) -> Vector2; stored(_ display:) -> Vector2 }`. `.left` and `.hidden` map to `.vertical`.
  - `public struct NodeShape { struct Socket { name: SocketName; type: SocketType? }; title; category; inputs; outputs; isMissing; init(title:category:inputs:outputs:isMissing:); init(_ node: Node, in: Graph, registry: NodeRegistry) }`
  - `public enum NodeLayout { width = 168, headerHeight = 24, rowHeight = 20, bodyPadding = 6, socketRadius = 5, socketHitRadius = 9; rowCount(_:); size(_:) -> Vector2; rowCentre(_:); socketOffset(_:isInput:in:flow:) -> Vector2? }`
  - `public struct WireGeometry { start, control1, control2, end: Vector2; init(from:to:flow:); bounds(padding:) -> CanvasRect }`
  - Test fixtures: `editorTestRegistry` (`NumberTestNode`, `RectangleTestNode`, `ExtrudeTestNode`, `AllEdgesTestNode`, `FilletTestNode`, `OutputTestNode`), `inspectorTestRegistry` (those plus `TransformTestNode`, `GraphParameterTestNode` and `GridPointsTestNode`, which mirror M3's `.vector`, `.parameterPicker` and optional-input nodes). The mirrors follow M3's merged definitions: `ExtrudeTestNode` has the `reversed` toggle, and `OutputTestNode` has a `.list` input and a pass-through output, `nodeID(_:)`, `testNode(_:id:at:values:registry:)`, `wire(_:_:_:_:)`.

- [ ] **Step 1: Write the test fixtures and failing tests**

`Tests/CreatorEditorTests/Support/EditorTestNodes.swift`:
```swift
// Test fixture file: it deliberately holds several small node definitions, one per category,
// so the editor is tested without depending on CreatorNodes.
import CreatorGeometry
import CreatorGraph
import CreatorKernel

enum NumberTestNode: NodeDefinition {
    static let typeID = "editortest.number"
    static let displayName = "Number"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(5), unit: .millimetres, range: 0...50)]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

enum RectangleTestNode: NodeDefinition {
    static let typeID = "editortest.rectangle"
    static let displayName = "Rectangle"
    static let category = NodeCategory.profile
    static let inputs = [
        SocketSpec("width", .number, defaultValue: .number(10), unit: .millimetres),
        SocketSpec("height", .number, defaultValue: .number(10), unit: .millimetres),
        SocketSpec("plane", .plane, defaultValue: .plane(.xy)),
        SocketSpec("anchor", .integer, defaultValue: .integer(4)),
    ]
    static let outputs = [SocketSpec("profile", .profile)]
    static let inspector = [
        InspectorSection(title: "Size", controls: [.slider("width"), .slider("height")]),
        InspectorSection(title: "Placement", controls: [.planePicker("plane"), .anchorGrid("anchor")]),
    ]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let profile = Profile2D.rectangle(width: try inputs.number("width"), height: try inputs.number("height"),
                                            plane: try inputs.plane("plane"))
        return NodeOutputs(["profile": .profile(profile)])
    }
}

/// Mirrors M3's Extrude: a segmented mode (integer index), the distance slider and the
/// "Reverse direction" toggle on a bool socket (spec Errata (M3): the Direction menu is a toggle).
enum ExtrudeTestNode: NodeDefinition {
    static let typeID = "editortest.extrude"
    static let displayName = "Extrude"
    static let category = NodeCategory.solid
    static let inputs = [
        SocketSpec("profile", .profile),
        SocketSpec("distance", .number, defaultValue: .number(10), unit: .millimetres, range: 0...100),
        SocketSpec("mode", .integer, defaultValue: .integer(0)),
        SocketSpec("reversed", .bool, defaultValue: .bool(false)),
    ]
    static let outputs = [SocketSpec("solid", .solid)]
    static let inspector = [
        InspectorSection(title: "Extrude", controls: [
            .segmented("mode", options: ["Distance", "Symmetric"]), .slider("distance"),
            .toggle("reversed", label: "Reverse direction"),
        ]),
    ]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let mode: ExtrudeMode = try inputs.integer("mode") == 1 ? .symmetric : .oneSided
        let solid = try await kernel.extrude(try inputs.profile("profile"), distance: try inputs.number("distance"),
                                             mode: mode, tag: context.tag)
        return NodeOutputs(["solid": .solid(solid)])
    }
}

/// Mirrors M3's selection-rule nodes: `ruleSummary` names the node's own *output*.
enum AllEdgesTestNode: NodeDefinition {
    static let typeID = "editortest.allEdges"
    static let displayName = "All Edges"
    static let category = NodeCategory.selection
    static let inputs = [SocketSpec("solid", .solid)]
    static let outputs = [SocketSpec("edges", .edgeSet)]
    static let inspector = [InspectorSection(title: "Edges", controls: [.ruleSummary("edges")])]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solid = try inputs.solid("solid")
        return NodeOutputs(["edges": .edgeSet(EdgeSet(solid: solid, edges: solid.topology.edges.map(\.id)))])
    }
}

/// Mirrors M3's Fillet: `ruleSummary` names an *input*, and the toggle binds the `showHandle`
/// setting (not a socket), seeded `.bool(true)` by `defaultSettings` as M3 does. M3 has no
/// "Tangent chain" toggle (spec Errata (M3)), so neither does this.
enum FilletTestNode: NodeDefinition {
    static let typeID = "editortest.fillet"
    static let displayName = "Fillet"
    static let category = NodeCategory.feature
    static let inputs = [
        SocketSpec("solid", .solid),
        SocketSpec("edges", .edgeSet),
        SocketSpec("radius", .number, defaultValue: .number(1), unit: .millimetres, range: 0...20),
    ]
    static let outputs = [SocketSpec("solid", .solid)]
    static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.showHandle: .bool(true)]
    static let inspector = [
        InspectorSection(title: "Fillet", controls: [.slider("radius"), .toggle(NodeSetting.showHandle, label: "Show handle in view")]),
        InspectorSection(title: "Edges",
                         controls: [.ruleSummary("edges"), .button(title: "Pick edges in view…", action: .pickEdgesInView)]),
    ]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["solid": .solid(try inputs.solid("solid"))])
    }
}

/// Mirrors M3's Output: one `.list` input (one wire carrying every solid) passed through as one list.
enum OutputTestNode: NodeDefinition {
    static let typeID = "editortest.output"
    static let displayName = "Output"
    static let category = NodeCategory.output
    static let inputs = [SocketSpec("solid", .solid, access: .list)]
    static let outputs = [SocketSpec("solid", .solid)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(lists: ["solid": try inputs.list("solid")])
    }
}

/// Mirrors M3's Transform: a `.vector` control on a vector socket.
enum TransformTestNode: NodeDefinition {
    static let typeID = "editortest.transform"
    static let displayName = "Transform"
    static let category = NodeCategory.solid
    static let inputs = [
        SocketSpec("solid", .solid),
        SocketSpec("move", .vector, defaultValue: .vector(.zero), unit: .millimetres),
    ]
    static let outputs = [SocketSpec("solid", .solid)]
    static let inspector = [InspectorSection(title: "Move", controls: [.vector("move")])]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["solid": .solid(try inputs.solid("solid"))])
    }
}

/// Mirrors M3's Graph Parameter: a `.parameterPicker` bound to the `parameter` setting, and one
/// optional output per parameter type.
enum GraphParameterTestNode: NodeDefinition {
    static let typeID = "editortest.graphParameter"
    static let displayName = "Graph Parameter"
    static let category = NodeCategory.value
    static let inputs: [SocketSpec] = []
    static let outputs = [
        SocketSpec("number", .number, optional: true), SocketSpec("integer", .integer, optional: true),
        SocketSpec("bool", .bool, optional: true), SocketSpec("vector", .vector, optional: true),
    ]
    static let inspector = [InspectorSection(title: "Parameter", controls: [.parameterPicker(NodeSetting.parameter)])]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["number": .number(0)])
    }
}

/// Mirrors M3's Grid Points: `total` is an optional integer input with no default. Unset, the
/// grid is `countX` × `countY`; set, it overrides `countX` (M3 carry-over).
enum GridPointsTestNode: NodeDefinition {
    static let typeID = "editortest.gridPoints"
    static let displayName = "Grid Points"
    static let category = NodeCategory.value
    static let inputs = [
        SocketSpec("countX", .integer, defaultValue: .integer(2), unit: .count),
        SocketSpec("total", .integer, unit: .count, optional: true),
    ]
    static let outputs = [SocketSpec("points", .vector)]
    static let inspector = [InspectorSection(title: "Grid", controls: [.integer("countX"), .integer("total")])]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(lists: ["points": []])
    }
}

let editorTestRegistry = NodeRegistry([
    NumberTestNode.self, RectangleTestNode.self, ExtrudeTestNode.self, AllEdgesTestNode.self,
    FilletTestNode.self, OutputTestNode.self,
])

/// The editor registry plus the definitions that carry M3's newer controls and an optional input,
/// for the inspector tests. Kept separate so the palette tests' type lists stay as they are.
let inspectorTestRegistry = NodeRegistry([
    NumberTestNode.self, RectangleTestNode.self, ExtrudeTestNode.self, AllEdgesTestNode.self,
    FilletTestNode.self, OutputTestNode.self, TransformTestNode.self, GraphParameterTestNode.self,
    GridPointsTestNode.self,
])
```

`Tests/CreatorEditorTests/Support/EditorTestSupport.swift`:
```swift
// Test fixture file: helpers shared by the editor tests.
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
@testable import CreatorEditor

/// A node ID whose sort order is `n`, so tests control the draw order.
func nodeID(_ n: Int) -> NodeID {
    let digits = String(n)
    let suffix = String(repeating: "0", count: max(0, 12 - digits.count)) + digits
    return NodeID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-" + suffix) ?? UUID())
}

func testNode(_ definition: any NodeDefinition.Type, id: Int, at position: Vector2,
              values: [SocketName: ConstantValue] = [:], registry: NodeRegistry = inspectorTestRegistry) -> Node {
    // Created as the app creates nodes: seeded `defaultSettings`, and `isOutput` for `.output` nodes (M3).
    var node = registry.makeNode(definition.typeID, at: position)
    node.id = nodeID(id)
    node.inputValues.merge(values) { _, given in given }
    return node
}

func wire(_ from: Node, _ fromSocket: SocketName, _ to: Node, _ toSocket: SocketName) -> Link {
    Link(from: Endpoint(node: from.id, socket: fromSocket), to: Endpoint(node: to.id, socket: toSocket))
}
```

`Tests/CreatorEditorTests/CanvasGeometryTests.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

struct CanvasGeometryTests {
    @Test func screenAndCanvasRoundTrip() {
        let transform = CanvasTransform(offset: Vector2(30, -12), zoom: 2)
        let point = Vector2(7, 9)
        #expect(transform.toScreen(point) == Vector2(44, 6))
        #expect(transform.toCanvas(transform.toScreen(point)) == point)
    }

    @Test func zoomKeepsThePointUnderTheAnchorStill() {
        let transform = CanvasTransform(offset: Vector2(10, 20), zoom: 1)
        let anchor = Vector2(100, 50)
        let before = transform.toCanvas(anchor)
        let zoomed = transform.zoomed(by: 1.25, around: anchor)
        #expect(zoomed.zoom == 1.25)
        let after = zoomed.toCanvas(anchor)
        #expect(abs(after.x - before.x) < 1e-9 && abs(after.y - before.y) < 1e-9)
    }

    @Test func zoomIsClampedAndNonFiniteFactorsAreIgnored() {
        #expect(CanvasTransform(zoom: 100).zoom == CanvasTransform.zoomRange.upperBound)
        #expect(CanvasTransform(zoom: 0.001).zoom == CanvasTransform.zoomRange.lowerBound)
        #expect(CanvasTransform(zoom: .nan).zoom == 1)
        let transform = CanvasTransform(offset: Vector2(1, 2), zoom: 1.5)
        #expect(transform.zoomed(by: .infinity, around: .zero) == transform)
        #expect(transform.zoomed(by: 0, around: .zero) == transform)
    }

    @Test func leftDockTransposesAndSwitchingIsLossless() {
        let stored = Vector2(120, -35.5)
        #expect(CanvasFlow(.left).display(stored) == Vector2(-35.5, 120))
        #expect(CanvasFlow(.bottom).display(stored) == stored)
        #expect(CanvasFlow(.hidden) == .vertical)
        for flow in [CanvasFlow.horizontal, .vertical] {
            #expect(flow.stored(flow.display(stored)) == stored)
        }
    }

    @Test func horizontalSocketsSitOnTheSideEdgesBesideTheirRows() {
        let shape = NodeShape(title: "Add", category: .value,
                              inputs: [.init(name: "a", type: .number), .init(name: "b", type: .number)],
                              outputs: [.init(name: "sum", type: .number)])
        #expect(NodeLayout.size(shape) == Vector2(168, 24 + 12 + 60))
        #expect(NodeLayout.socketOffset("a", isInput: true, in: shape, flow: .horizontal) == Vector2(0, 40))
        #expect(NodeLayout.socketOffset("b", isInput: true, in: shape, flow: .horizontal) == Vector2(0, 60))
        #expect(NodeLayout.socketOffset("sum", isInput: false, in: shape, flow: .horizontal) == Vector2(168, 80))
        #expect(NodeLayout.socketOffset("sum", isInput: true, in: shape, flow: .horizontal) == nil)
    }

    @Test func verticalSocketsSpreadAlongTheTopAndBottomEdges() {
        let shape = NodeShape(title: "Add", category: .value,
                              inputs: [.init(name: "a", type: .number), .init(name: "b", type: .number)],
                              outputs: [.init(name: "sum", type: .number)])
        #expect(NodeLayout.socketOffset("a", isInput: true, in: shape, flow: .vertical) == Vector2(56, 0))
        #expect(NodeLayout.socketOffset("b", isInput: true, in: shape, flow: .vertical) == Vector2(112, 0))
        #expect(NodeLayout.socketOffset("sum", isInput: false, in: shape, flow: .vertical) == Vector2(84, 96))
    }

    @Test func rectsFromCornersInAnyOrder() {
        let rect = CanvasRect(corner: Vector2(10, 40), Vector2(-5, 0))
        #expect(rect == CanvasRect(origin: Vector2(-5, 0), size: Vector2(15, 40)))
        #expect(rect.contains(Vector2(0, 20)))
        #expect(!rect.contains(Vector2(11, 20)))
        #expect(rect.intersects(CanvasRect(origin: Vector2(10, 40), size: Vector2(5, 5))))
        #expect(!rect.intersects(CanvasRect(origin: Vector2(11, 0), size: Vector2(5, 5))))
    }

    @Test func missingNodesKeepTheSocketsTheirWiresName() {
        let known = testNode(NumberTestNode.self, id: 1, at: .zero)
        var missing = Node(id: nodeID(2), typeID: "plugin.gone", name: "Gone")
        missing.position = Vector2(200, 0)
        let graph = Graph(nodes: [known.id: known, missing.id: missing],
                          links: [wire(known, "value", missing, "input")])
        let shape = NodeShape(missing, in: graph, registry: editorTestRegistry)
        #expect(shape.isMissing)
        #expect(shape.inputs == [.init(name: "input", type: nil)])
        #expect(shape.outputs.isEmpty)
    }
}
```

`Tests/CreatorEditorTests/WireGeometryTests.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

struct WireGeometryTests {
    @Test func horizontalWiresLeaveRightAndEnterFromTheLeft() {
        let wire = WireGeometry(from: Vector2(0, 0), to: Vector2(200, 50), flow: .horizontal)
        #expect(wire.control1 == Vector2(100, 0))
        #expect(wire.control2 == Vector2(100, 50))
    }

    @Test func verticalWiresLeaveDownAndEnterFromAbove() {
        let wire = WireGeometry(from: Vector2(0, 0), to: Vector2(30, 300), flow: .vertical)
        #expect(wire.control1 == Vector2(0, 150))
        #expect(wire.control2 == Vector2(30, 150))
    }

    @Test func backwardsWiresStillLoopOutOfTheirSockets() {
        let wire = WireGeometry(from: Vector2(200, 0), to: Vector2(0, 0), flow: .horizontal)
        #expect(wire.control1 == Vector2(300, 0))
        #expect(wire.control2 == Vector2(-100, 0))
        #expect(wire.bounds(padding: 4) == CanvasRect(origin: Vector2(-104, -4), size: Vector2(408, 8)))
    }

    @Test func shortWiresKeepAMinimumReach() {
        let wire = WireGeometry(from: Vector2(0, 0), to: Vector2(10, 0), flow: .horizontal)
        #expect(wire.control1 == Vector2(40, 0))
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: errors such as "cannot find 'CanvasTransform' in scope", "cannot find 'NodeShape' in scope" and "cannot find 'WireGeometry' in scope".

- [ ] **Step 3: Implement**

`Sources/CreatorEditor/CanvasTransform.swift`:
```swift
import CreatorGeometry
import CreatorGraph

/// Pan and zoom of the graph canvas: `screen = canvas × zoom + offset`, in points, y down.
/// "Canvas" here means display coordinates, after the dock transpose (see `CanvasFlow`).
public struct CanvasTransform: Equatable, Sendable {
    public static let zoomRange: ClosedRange<Double> = 0.25...3
    /// One press of +/− or a header zoom button.
    public static let zoomStep = 1.25

    public var offset: Vector2
    public var zoom: Double

    public init(offset: Vector2 = .zero, zoom: Double = 1) {
        self.offset = offset
        self.zoom = Self.clamped(zoom)
    }

    public init(_ viewState: ViewState) {
        self.init(offset: viewState.canvasOffset, zoom: viewState.canvasZoom)
    }

    public func toScreen(_ canvas: Vector2) -> Vector2 { canvas * zoom + offset }

    public func toCanvas(_ screen: Vector2) -> Vector2 {
        Vector2((screen.x - offset.x) / zoom, (screen.y - offset.y) / zoom)
    }

    /// Multiplies the zoom by `factor`, keeping the canvas point under `anchor` (screen) still.
    public func zoomed(by factor: Double, around anchor: Vector2) -> CanvasTransform {
        guard factor.isFinite, factor > 0 else { return self }
        let pinned = toCanvas(anchor)
        let zoom = Self.clamped(zoom * factor)
        return CanvasTransform(offset: anchor - pinned * zoom, zoom: zoom)
    }

    public func panned(by delta: Vector2) -> CanvasTransform {
        CanvasTransform(offset: offset + delta, zoom: zoom)
    }

    private static func clamped(_ zoom: Double) -> Double {
        guard zoom.isFinite else { return 1 }
        return min(max(zoom, zoomRange.lowerBound), zoomRange.upperBound)
    }
}
```

`Sources/CreatorEditor/CanvasRect.swift`:
```swift
import CreatorGeometry

/// An axis-aligned rectangle in canvas or screen points, y down.
public struct CanvasRect: Equatable, Sendable {
    public var origin: Vector2
    public var size: Vector2

    public init(origin: Vector2, size: Vector2) {
        self.origin = origin
        self.size = size
    }

    /// The rectangle spanned by two corners in any order (a box-select drag).
    public init(corner a: Vector2, _ b: Vector2) {
        origin = Vector2(min(a.x, b.x), min(a.y, b.y))
        size = Vector2(abs(a.x - b.x), abs(a.y - b.y))
    }

    public var maxX: Double { origin.x + size.x }
    public var maxY: Double { origin.y + size.y }

    public func contains(_ point: Vector2) -> Bool {
        point.x >= origin.x && point.x <= maxX && point.y >= origin.y && point.y <= maxY
    }

    public func intersects(_ other: CanvasRect) -> Bool {
        origin.x <= other.maxX && other.origin.x <= maxX && origin.y <= other.maxY && other.origin.y <= maxY
    }
}
```

`Sources/CreatorEditor/CanvasFlow.swift`:
```swift
import CreatorGeometry
import CreatorGraph

/// Which way the graph flows, from the dock (spec §6.2). Node positions are stored
/// left-to-right; the vertical flow shows their transpose (x↔y), so switching docks is lossless.
public enum CanvasFlow: Sendable, Equatable {
    /// Docked at the bottom: inputs on the left edge, outputs on the right.
    case horizontal
    /// Docked left: inputs on the top edge, outputs on the bottom.
    case vertical

    /// The flow for a dock. A hidden panel keeps the left dock's flow.
    public init(_ dock: DockSide) {
        self = dock == .bottom ? .horizontal : .vertical
    }

    /// A stored (left-to-right) position as drawn in this flow.
    public func display(_ stored: Vector2) -> Vector2 {
        self == .horizontal ? stored : Vector2(stored.y, stored.x)
    }

    /// A drawn position back in stored (left-to-right) coordinates. The transpose is its own inverse.
    public func stored(_ display: Vector2) -> Vector2 { self.display(display) }
}
```

`Sources/CreatorEditor/NodeShape.swift`:
```swift
import CreatorGraph
import CreatorKernel

/// What the canvas needs to draw and hit-test one node: its title, category and sockets.
/// A node whose type isn't registered is a "missing node" (spec §4.5): it keeps the sockets its
/// wires name, untyped.
public struct NodeShape: Equatable, Sendable {
    public struct Socket: Equatable, Sendable {
        public var name: SocketName
        /// `nil` for a missing node's sockets.
        public var type: SocketType?
    }

    public var title: String
    public var category: NodeCategory
    public var inputs: [Socket]
    public var outputs: [Socket]
    public var isMissing: Bool

    public init(title: String, category: NodeCategory, inputs: [Socket], outputs: [Socket], isMissing: Bool = false) {
        self.title = title
        self.category = category
        self.inputs = inputs
        self.outputs = outputs
        self.isMissing = isMissing
    }

    public init(_ node: Node, in graph: Graph, registry: NodeRegistry) {
        if let definition = registry[node.typeID] {
            self.init(title: node.name, category: definition.category,
                      inputs: definition.inputs.map { Socket(name: $0.name, type: $0.type) },
                      outputs: definition.outputs.map { Socket(name: $0.name, type: $0.type) })
        } else {
            let inputs = Set(graph.links.filter { $0.to.node == node.id }.map(\.to.socket)).sorted()
            let outputs = Set(graph.links.filter { $0.from.node == node.id }.map(\.from.socket)).sorted()
            self.init(title: node.name, category: .value,
                      inputs: inputs.map { Socket(name: $0, type: nil) },
                      outputs: outputs.map { Socket(name: $0, type: nil) }, isMissing: true)
        }
    }
}
```

`Sources/CreatorEditor/NodeLayout.swift`:
```swift
import CreatorGeometry
import CreatorGraph

/// Node geometry computed, not measured, so drawing, socket anchors and hit testing agree
/// (ported from MetalNodes' `NodeGeometry`). All values are canvas points at zoom 1.
public enum NodeLayout {
    public static let width = 168.0
    public static let headerHeight = 24.0
    public static let rowHeight = 20.0
    public static let bodyPadding = 6.0
    public static let socketRadius = 5.0
    /// How far from a socket's centre a press still grabs it, in screen points.
    public static let socketHitRadius = 9.0

    /// Rows in the body: one per input, then one per output.
    public static func rowCount(_ shape: NodeShape) -> Int { max(1, shape.inputs.count + shape.outputs.count) }

    public static func size(_ shape: NodeShape) -> Vector2 {
        Vector2(width, headerHeight + 2 * bodyPadding + Double(rowCount(shape)) * rowHeight)
    }

    /// The vertical centre of body row `row`, from the node's top.
    public static func rowCentre(_ row: Int) -> Double {
        headerHeight + bodyPadding + (Double(row) + 0.5) * rowHeight
    }

    /// A socket's centre relative to the node's drawn origin. Horizontal flow: inputs on the
    /// left edge beside their rows, outputs on the right edge. Vertical flow: inputs spread
    /// along the top edge, outputs along the bottom (spec §6.2).
    public static func socketOffset(_ socket: SocketName, isInput: Bool, in shape: NodeShape, flow: CanvasFlow) -> Vector2? {
        let sockets = isInput ? shape.inputs : shape.outputs
        guard let index = sockets.firstIndex(where: { $0.name == socket }) else { return nil }
        switch flow {
        case .horizontal:
            let row = isInput ? index : shape.inputs.count + index
            return Vector2(isInput ? 0 : width, rowCentre(row))
        case .vertical:
            let x = width * Double(index + 1) / Double(sockets.count + 1)
            return Vector2(x, isInput ? 0 : size(shape).y)
        }
    }
}
```

`Sources/CreatorEditor/WireGeometry.swift`:
```swift
import CreatorGeometry

/// A wire's cubic bezier between two sockets (spec §6.2). The control points leave each socket
/// along the flow — right/left in the horizontal flow, down/up in the vertical — so a wire
/// always leaves an output forwards and enters an input forwards.
public struct WireGeometry: Equatable, Sendable {
    public var start: Vector2
    public var control1: Vector2
    public var control2: Vector2
    public var end: Vector2

    /// `start` is the output end, `end` the input end, both in display canvas points.
    public init(from start: Vector2, to end: Vector2, flow: CanvasFlow) {
        let along = flow == .horizontal ? end.x - start.x : end.y - start.y
        let reach = max(40, abs(along) * 0.5)
        let step = flow == .horizontal ? Vector2(reach, 0) : Vector2(0, reach)
        self.start = start
        self.control1 = start + step
        self.control2 = end - step
        self.end = end
    }

    /// A rectangle holding the whole curve (it lies inside its control points' hull), grown
    /// by `padding` for the stroke.
    public func bounds(padding: Double) -> CanvasRect {
        let points = [start, control1, control2, end]
        let low = Vector2(points.map(\.x).min() ?? 0, points.map(\.y).min() ?? 0)
        let high = Vector2(points.map(\.x).max() ?? 0, points.map(\.y).max() ?? 0)
        return CanvasRect(origin: low - Vector2(padding, padding), size: high - low + Vector2(2 * padding, 2 * padding))
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter CreatorEditorTests`
Expected: PASS — `Test run with 20 tests in 4 suites passed`.

- [ ] **Step 5: Commit**

```bash
swiftlint lint --strict   # must report 0 violations before committing (CLAUDE.md "Linting")
git add Sources/CreatorEditor Tests/CreatorEditorTests
git commit -m "feat(editor): canvas transform, dock transpose, computed node layout and wire curves"
```

---

### Task 3: `EditorModel` — state, dock, transform and hit testing under the transform

**Files:**
- Create: `Sources/CreatorEditor/SocketRef.swift`, `CanvasHit.swift`, `CanvasModifiers.swift`, `WireDrag.swift`, `CanvasInteraction.swift`, `RefusalFeedback.swift`, `NodeClipboard.swift`, `InspectorRequest.swift`, `SearchPaletteState.swift`, `EditorModel.swift`
- Test: `Tests/CreatorEditorTests/HitTestTests.swift`, `Tests/CreatorEditorTests/DockTests.swift`, `Tests/CreatorEditorTests/Support/EditorModelTestSupport.swift`

**Interfaces:**
- Consumes: Task 2's geometry. `DocumentModel` (`graph`, `registry`, `results`, `viewState` (settable), `perform(_:coalescingKey:)`, `endCoalescing()`, `undo()`, `redo()`, `canUndo`, `fileData()`). `Endpoint`, `Link`, `Node`, `NodeID`, `InspectorAction`.
- Produces:
  - `public struct SocketRef: Hashable { endpoint: Endpoint; isInput: Bool; init(_:isInput:) }`
  - `public enum CanvasHit: Equatable { case socket(SocketRef), node(NodeID), empty }`
  - `public struct CanvasModifiers: OptionSet { shift, option, command }`
  - `public struct WireDrag: Equatable { from: SocketRef; current: Vector2 }`
  - `public enum CanvasInteraction: Equatable { case panning(startOffset:), moving(start: [NodeID: Vector2], key: String), duplicating(start: [NodeID: Vector2], delta: Vector2), boxSelecting(start:current:base:), connecting(WireDrag) }`
  - `public struct RefusalFeedback: Equatable { message: String; node: NodeID?; serial: Int }`
  - `public struct NodeClipboard: Equatable { nodes: [Node]; links: [Link] }`
  - `public struct InspectorRequest: Equatable { node: NodeID; action: InspectorAction; serial: Int }`
  - `public struct SearchPaletteState: Equatable { screenPosition: Vector2; query: String; highlighted: Int; init(screenPosition:query:highlighted:) }`
  - `@MainActor @Observable public final class EditorModel`:
    - Properties: `document`, `selection: Set<NodeID>` (a change ends coalescing), `modifiers`, `pointerLocation: Vector2?`, `interaction` (read-only), `refusal` (read-only), `isShaking` (read-only), `palette: SearchPaletteState?`, `clipboard` (read-only), `inspectorRequest` (read-only), `graph`, `registry`, `dock`, `flow`, `isPanelVisible`, `transform` (get/set through `document.viewState`).
    - Public methods: `setDock(_:)`, `toggleHidden()`, `zoom(in:)`, `shape(of:)`, `displayOrigin(of:)`, `frame(of:)`, `anchor(of:)`, `drawOrder`, `hitTest(_ screen:) -> CanvasHit`, `nodes(intersecting:)`, `clearRefusal()`.
    - Internal methods for later tasks: `refuse(_:node:)`, `setClipboard(_:)`, `nextPasteOffset()`, `setInspectorRequest(_:)`, `requestSerial`, `beginPress(at:)`, `currentPress`, `endPress()`, `setInteraction(_:)`.
  - Test fixtures: `makeEditor(_:_:parameters:dock:registry:)`, `EditorModel.screenPoint(in:inset:)`, `EditorModel.screenPoint(of:_:input:)`.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorEditorTests/Support/EditorModelTestSupport.swift`:
```swift
// Test fixture file: building an editor over a test document, and finding points on its canvas.
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorEditor

@MainActor
func makeEditor(_ nodes: [Node], _ links: [Link] = [], parameters: [GraphParameter] = [],
                dock: DockSide = .bottom, registry: NodeRegistry = editorTestRegistry) -> EditorModel {
    let graph = Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }), links: links, parameters: parameters)
    let document = DocumentModel(file: GraphFile(graph: graph, viewState: ViewState(dock: dock)),
                                 registry: registry, kernel: FakeKernel())
    return EditorModel(document: document)
}

@MainActor
extension EditorModel {
    /// The screen point `inset` canvas points inside a node's drawn top-left corner (in its body).
    func screenPoint(in node: NodeID, inset: Vector2 = Vector2(20, 40)) -> Vector2 {
        guard let node = graph.nodes[node] else { return .zero }
        return transform.toScreen(frame(of: node).origin + inset)
    }

    /// The screen point of a socket's centre.
    func screenPoint(of node: NodeID, _ socket: SocketName, input: Bool) -> Vector2 {
        let ref = SocketRef(Endpoint(node: node, socket: socket), isInput: input)
        return transform.toScreen(anchor(of: ref) ?? .zero)
    }
}
```

`Tests/CreatorEditorTests/HitTestTests.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

@MainActor
struct HitTestTests {
    @Test func hitsANodeUnderAZoomedAndPannedCanvas() {
        let number = testNode(NumberTestNode.self, id: 1, at: Vector2(100, 50))
        let editor = makeEditor([number])
        editor.transform = CanvasTransform(offset: Vector2(-40, 30), zoom: 2)
        // Canvas (110, 60) is inside the node (origin 100, 50) → screen (180, 150).
        #expect(editor.hitTest(Vector2(180, 150)) == .node(number.id))
        // Canvas (95, 60) is left of it → screen (150, 150).
        #expect(editor.hitTest(Vector2(150, 150)) == .empty)
    }

    @Test func socketHitRadiusIsInScreenPoints() {
        let number = testNode(NumberTestNode.self, id: 1, at: .zero)
        let editor = makeEditor([number])
        editor.transform = CanvasTransform(zoom: 3)
        let socket = editor.screenPoint(of: number.id, "value", input: false)
        let expected = CanvasHit.socket(SocketRef(Endpoint(node: number.id, socket: "value"), isInput: false))
        #expect(editor.hitTest(socket + Vector2(8, 0)) == expected)
        #expect(editor.hitTest(socket + Vector2(0, 10)) != expected)
    }

    @Test func theFrontmostNodeWinsAndSelectionIsRaised() {
        let back = testNode(NumberTestNode.self, id: 1, at: .zero)
        let front = testNode(NumberTestNode.self, id: 2, at: Vector2(10, 10))
        let editor = makeEditor([back, front])
        let overlap = Vector2(40, 30)
        #expect(editor.hitTest(overlap) == .node(front.id))
        editor.selection = [back.id]
        #expect(editor.hitTest(overlap) == .node(back.id))
        #expect(editor.drawOrder.map(\.id) == [front.id, back.id])
    }

    @Test func leftDockHitsTheTransposedPosition() {
        let number = testNode(NumberTestNode.self, id: 1, at: Vector2(300, 0))
        let editor = makeEditor([number], dock: .left)
        #expect(editor.hitTest(Vector2(10, 310)) == .node(number.id))
        #expect(editor.hitTest(Vector2(310, 10)) == .empty)
        // In the vertical flow the output sits on the bottom edge.
        let output = editor.screenPoint(of: number.id, "value", input: false)
        #expect(output == Vector2(84, 300 + NodeLayout.size(editor.shape(of: number)).y))
    }

    @Test func boxSelectionFindsIntersectingFrames() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let b = testNode(NumberTestNode.self, id: 2, at: Vector2(400, 0))
        let editor = makeEditor([a, b])
        #expect(editor.nodes(intersecting: CanvasRect(corner: Vector2(150, 10), Vector2(200, 20))) == [a.id])
        #expect(editor.nodes(intersecting: CanvasRect(corner: Vector2(-10, -10), Vector2(500, 20))) == [a.id, b.id])
    }
}
```

`Tests/CreatorEditorTests/DockTests.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorEditor

@MainActor
struct DockTests {
    @Test func theDockIsSavedWithTheDocument() throws {
        let editor = makeEditor([])
        editor.setDock(.left)
        editor.transform = CanvasTransform(offset: Vector2(3, 4), zoom: 1.5)
        let file = try JSONDecoder().decode(GraphFile.self, from: try editor.document.fileData())
        #expect(file.viewState == ViewState(dock: .left, canvasOffset: Vector2(3, 4), canvasZoom: 1.5))
    }

    @Test func showingAHiddenPanelReturnsItToItsLastSide() {
        let editor = makeEditor([], dock: .bottom)
        editor.toggleHidden()
        #expect(editor.dock == .hidden)
        #expect(!editor.isPanelVisible)
        editor.toggleHidden()
        #expect(editor.dock == .bottom)
    }

    @Test func aDocumentSavedHiddenShowsOnTheLeft() {
        let editor = makeEditor([], dock: .hidden)
        editor.toggleHidden()
        #expect(editor.dock == .left)
    }

    @Test func switchingDocksKeepsStoredPositionsAndTransposesTheDrawing() {
        let node = testNode(NumberTestNode.self, id: 1, at: Vector2(250, 40))
        let editor = makeEditor([node], dock: .bottom)
        #expect(editor.frame(of: node).origin == Vector2(250, 40))
        editor.setDock(.left)
        #expect(editor.graph.nodes[node.id]?.position == Vector2(250, 40))
        #expect(editor.frame(of: node).origin == Vector2(40, 250))
        #expect(!editor.document.canUndo)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: "cannot find type 'EditorModel' in scope" (and `SocketRef`, `CanvasHit`).

- [ ] **Step 3: Implement the value types**

`Sources/CreatorEditor/SocketRef.swift`:
```swift
import CreatorGraph

/// One socket on the canvas: an endpoint and which side of its node it is on.
public struct SocketRef: Hashable, Sendable {
    public var endpoint: Endpoint
    public var isInput: Bool

    public init(_ endpoint: Endpoint, isInput: Bool) {
        self.endpoint = endpoint
        self.isInput = isInput
    }
}
```

`Sources/CreatorEditor/CanvasHit.swift`:
```swift
import CreatorKernel

/// What lies under a point on the canvas, topmost first: a socket beats its node.
public enum CanvasHit: Equatable, Sendable {
    case socket(SocketRef)
    case node(NodeID)
    case empty
}
```

`Sources/CreatorEditor/CanvasModifiers.swift`:
```swift
/// Modifier keys held during a canvas press or drag. MetalUI gives no modifiers on a gesture yet
/// (docs/metalui-gaps.md item 5), so `GraphPanelInput` tracks them from the window's key events.
public struct CanvasModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let shift = CanvasModifiers(rawValue: 1 << 0)
    public static let option = CanvasModifiers(rawValue: 1 << 1)
    public static let command = CanvasModifiers(rawValue: 1 << 2)
}
```

`Sources/CreatorEditor/WireDrag.swift`:
```swift
import CreatorGeometry

/// A wire being dragged out of a socket. `current` is the pointer in display canvas points.
public struct WireDrag: Equatable, Sendable {
    public var from: SocketRef
    public var current: Vector2

    public init(from: SocketRef, current: Vector2) {
        self.from = from
        self.current = current
    }
}
```

`Sources/CreatorEditor/CanvasInteraction.swift`:
```swift
import CreatorGeometry
import CreatorKernel

/// The drag in progress on the canvas, decided by what the press landed on (spec §6.2).
public enum CanvasInteraction: Equatable, Sendable {
    /// A plain drag on empty canvas: moves the view.
    case panning(startOffset: Vector2)
    /// Dragging selected nodes. `start` holds their stored positions when the drag began;
    /// `key` coalesces every step of the drag into one undo step.
    case moving(start: [NodeID: Vector2], key: String)
    /// An ⌥-drag: ghosts of the selection follow the pointer and are added on release.
    case duplicating(start: [NodeID: Vector2], delta: Vector2)
    /// A ⇧-drag on empty canvas. Corners are display canvas points; `base` is the selection
    /// before the drag, which the box adds to.
    case boxSelecting(start: Vector2, current: Vector2, base: Set<NodeID>)
    case connecting(WireDrag)
}
```

`Sources/CreatorEditor/RefusalFeedback.swift`:
```swift
import CreatorKernel

/// A refused edit: the message shown in the panel and the node that shakes (spec §6.2).
/// `serial` increases with every refusal, so the message timer of an older refusal never
/// clears a newer one.
public struct RefusalFeedback: Equatable, Sendable {
    public var message: String
    public var node: NodeID?
    public var serial: Int
}
```

`Sources/CreatorEditor/NodeClipboard.swift`:
```swift
import CreatorGraph

/// Copied nodes and the wires between them. Kept in the editor: the slice has one document
/// and MetalUI's pasteboard carries text only.
public struct NodeClipboard: Equatable, Sendable {
    public var nodes: [Node]
    public var links: [Link]
}
```

`Sources/CreatorEditor/InspectorRequest.swift`:
```swift
import CreatorGraph
import CreatorKernel

/// An inspector button the viewport must act on, such as "Pick edges in view…".
/// `serial` distinguishes two presses of the same button.
public struct InspectorRequest: Equatable, Sendable {
    public var node: NodeID
    public var action: InspectorAction
    public var serial: Int
}
```

`Sources/CreatorEditor/SearchPaletteState.swift`:
```swift
import CreatorGeometry

/// The open add-node palette (spec §6.2: Tab or Space opens it at the cursor).
public struct SearchPaletteState: Equatable, Sendable {
    /// Where it opened, in canvas-local screen points. New nodes land under this point.
    public var screenPosition: Vector2
    public var query: String
    /// Index into the current matches of the entry Return adds.
    public var highlighted: Int

    public init(screenPosition: Vector2, query: String = "", highlighted: Int = 0) {
        self.screenPosition = screenPosition
        self.query = query
        self.highlighted = highlighted
    }
}
```

- [ ] **Step 4: Implement `EditorModel`**

The refusal timer is a plain main-actor `Task` that the model owns. MetalUI master now has `.task` and `.task(id:)`, but a view-bound task would put the timing in a view, and the model tests couldn't see it. Tests never wait on the timer.

`Sources/CreatorEditor/EditorModel.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Observation

/// The graph panel's state and behaviour: selection, the canvas transform, the dock, drags,
/// wiring, clipboard and the add-node palette. Every edit goes through `DocumentModel.perform`,
/// so it is undoable. Views hold no logic; tests drive this class directly (spec §3.2, §8).
@MainActor
@Observable
public final class EditorModel {
    public let document: DocumentModel

    /// Selected nodes. Changing it ends any slider drag's undo coalescing.
    public var selection: Set<NodeID> = [] {
        didSet {
            if selection != oldValue { document.endCoalescing() }
        }
    }

    /// Modifier keys currently held, fed by `GraphPanelInput`.
    public var modifiers: CanvasModifiers = []
    /// The pointer over the canvas, in canvas-local screen points; `nil` when it is elsewhere.
    public var pointerLocation: Vector2?
    public private(set) var interaction: CanvasInteraction?
    public private(set) var refusal: RefusalFeedback?
    /// True for a moment after a refusal, while the refused node shakes.
    public private(set) var isShaking = false
    public var palette: SearchPaletteState?
    public private(set) var clipboard: NodeClipboard?
    /// The last inspector button pressed, for the viewport to act on (M4/M6).
    public private(set) var inspectorRequest: InspectorRequest?

    /// The dock to return to when the hidden panel is shown again.
    @ObservationIgnored private var lastVisibleDock: DockSide = .left
    @ObservationIgnored private var pressStart: Vector2?
    @ObservationIgnored private var pressHit: CanvasHit = .empty
    @ObservationIgnored private var pasteCount = 0
    @ObservationIgnored private var refusalSerial = 0
    @ObservationIgnored var requestSerial = 0

    public init(document: DocumentModel) {
        self.document = document
        if document.viewState.dock != .hidden { lastVisibleDock = document.viewState.dock }
    }

    public var graph: Graph { document.graph }
    public var registry: NodeRegistry { document.registry }

    // MARK: - Dock and transform

    public var dock: DockSide { document.viewState.dock }
    public var flow: CanvasFlow { CanvasFlow(dock) }
    public var isPanelVisible: Bool { dock != .hidden }

    public func setDock(_ dock: DockSide) {
        if dock != .hidden { lastVisibleDock = dock }
        document.viewState.dock = dock
    }

    /// ⇥: hides a visible panel, or shows a hidden one on the side it was last docked.
    public func toggleHidden() {
        setDock(isPanelVisible ? .hidden : lastVisibleDock)
    }

    public var transform: CanvasTransform {
        get { CanvasTransform(document.viewState) }
        set {
            document.viewState.canvasOffset = newValue.offset
            document.viewState.canvasZoom = newValue.zoom
        }
    }

    /// Zooms by one step about the pointer, or about the canvas origin when the pointer is elsewhere.
    public func zoom(in zoomIn: Bool) {
        let factor = zoomIn ? CanvasTransform.zoomStep : 1 / CanvasTransform.zoomStep
        transform = transform.zoomed(by: factor, around: pointerLocation ?? .zero)
    }

    // MARK: - Geometry

    public func shape(of node: Node) -> NodeShape { NodeShape(node, in: graph, registry: registry) }

    /// Where `node` is drawn, in display canvas points.
    public func displayOrigin(of node: Node) -> Vector2 { flow.display(node.position) }

    public func frame(of node: Node) -> CanvasRect {
        CanvasRect(origin: displayOrigin(of: node), size: NodeLayout.size(shape(of: node)))
    }

    /// A socket's centre in display canvas points.
    public func anchor(of socket: SocketRef) -> Vector2? {
        guard let node = graph.nodes[socket.endpoint.node],
              let offset = NodeLayout.socketOffset(socket.endpoint.socket, isInput: socket.isInput,
                                                   in: shape(of: node), flow: flow) else { return nil }
        return displayOrigin(of: node) + offset
    }

    /// Nodes back to front: by ID, with the selection raised above the rest.
    public var drawOrder: [Node] {
        graph.nodes.values.sorted { a, b in
            let aSelected = selection.contains(a.id), bSelected = selection.contains(b.id)
            return aSelected != bSelected ? bSelected : a.id < b.id
        }
    }

    /// What is under `screen` (canvas-local screen points): the frontmost node's socket within
    /// `NodeLayout.socketHitRadius` screen points, else the frontmost node, else empty canvas.
    public func hitTest(_ screen: Vector2) -> CanvasHit {
        let point = transform.toCanvas(screen)
        let radius = NodeLayout.socketHitRadius / transform.zoom
        for node in drawOrder.reversed() {
            let shape = shape(of: node)
            let origin = displayOrigin(of: node)
            for (sockets, isInput) in [(shape.inputs, true), (shape.outputs, false)] {
                for socket in sockets {
                    guard let offset = NodeLayout.socketOffset(socket.name, isInput: isInput, in: shape, flow: flow) else { continue }
                    if (origin + offset - point).length <= radius {
                        return .socket(SocketRef(Endpoint(node: node.id, socket: socket.name), isInput: isInput))
                    }
                }
            }
            if CanvasRect(origin: origin, size: NodeLayout.size(shape)).contains(point) { return .node(node.id) }
        }
        return .empty
    }

    /// Nodes whose drawn frame meets `rect` (display canvas points).
    public func nodes(intersecting rect: CanvasRect) -> Set<NodeID> {
        Set(graph.nodes.values.filter { frame(of: $0).intersects(rect) }.map(\.id))
    }

    // MARK: - Feedback

    func refuse(_ message: String, node: NodeID?) {
        refusalSerial += 1
        let serial = refusalSerial
        refusal = RefusalFeedback(message: message, node: node, serial: serial)
        isShaking = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            if self?.refusal?.serial == serial { self?.isShaking = false }
            try? await Task.sleep(for: .seconds(2))
            if self?.refusal?.serial == serial { self?.refusal = nil }
        }
    }

    /// Clears the refusal message (for example when the user starts another edit).
    public func clearRefusal() {
        refusal = nil
        isShaking = false
    }

    func setClipboard(_ clipboard: NodeClipboard) {
        self.clipboard = clipboard
        pasteCount = 0
    }

    func nextPasteOffset() -> Vector2 {
        pasteCount += 1
        return Vector2(24, 24) * Double(pasteCount)
    }

    func setInspectorRequest(_ request: InspectorRequest) { inspectorRequest = request }

    // MARK: - Press bookkeeping (used by EditorModel+Pointer)

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

    func setInteraction(_ interaction: CanvasInteraction?) { self.interaction = interaction }
}
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter CreatorEditorTests`
Expected: PASS — `Test run with 29 tests in 6 suites passed`.

- [ ] **Step 6: Commit**

```bash
swiftlint lint --strict   # must report 0 violations before committing (CLAUDE.md "Linting")
git add Sources/CreatorEditor Tests/CreatorEditorTests
git commit -m "feat(editor): EditorModel with dock, canvas transform and hit testing"
```

---

### Task 4: Editing — connect, refuse, replace, delete, copy, paste, duplicate, add

**Files:**
- Create: `Sources/CreatorEditor/SocketType+DisplayName.swift`, `ConnectionProblem+Message.swift`, `GraphError+Message.swift`, `EditorModel+Editing.swift`
- Test: `Tests/CreatorEditorTests/EditingTests.swift`

**Interfaces:**
- Consumes: Task 3's `EditorModel` internals (`refuse`, `setClipboard`, `nextPasteOffset`). `Graph.connectionProblem(from:to:registry:)`, `GraphCommand` (`.connect`, `.removeNode`, `.addNode`, `.restoreLinks`, `.batch`), `NodeRegistry.makeNode(_:at:)`.
- Produces:
  - `SocketType.indefiniteName` ("a number", "an edge set", …)
  - `ConnectionProblem.message` and `GraphError.message` (plain language)
  - `EditorModel.connect(_ link: Link)`, `deleteSelection()`, `copySelection()`, `paste()`, `duplicateSelection()`, `addNode(_ typeID: String, atScreen: Vector2)`
  - Internal: `clipboard(of: Set<NodeID>) -> NodeClipboard`, `insert(_:offset:) -> Set<NodeID>?` (one undo step; `offset` is in stored coordinates)

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorEditorTests/EditingTests.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

@MainActor
struct EditingTests {
    let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
    let extrude = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
    let output = testNode(OutputTestNode.self, id: 3, at: Vector2(600, 0))

    func chain() -> EditorModel {
        makeEditor([rect, extrude, output], [wire(rect, "profile", extrude, "profile"), wire(extrude, "solid", output, "solid")])
    }

    @Test func deleteRemovesNodesAndTheirWiresAndUndoRestoresThem() {
        let editor = chain()
        let before = editor.graph
        editor.selection = [extrude.id]
        editor.deleteSelection()
        #expect(editor.graph.nodes.count == 2)
        #expect(editor.graph.links.isEmpty)
        #expect(editor.selection.isEmpty)
        editor.document.undo()
        #expect(editor.graph == before)
    }

    @Test func deleteWithNothingSelectedDoesNothing() {
        let editor = chain()
        editor.deleteSelection()
        #expect(!editor.document.canUndo)
    }

    @Test func copyPasteKeepsInternalWiresOnlyAndOffsetsFurtherEachTime() {
        let editor = chain()
        editor.selection = [rect.id, extrude.id]
        editor.copySelection()
        editor.paste()
        let first = editor.selection
        #expect(first.count == 2)
        #expect(first.isDisjoint(with: [rect.id, extrude.id]))
        let firstCopies = first.compactMap { editor.graph.nodes[$0] }
        #expect(Set(firstCopies.map(\.position)) == [Vector2(24, 24), Vector2(324, 24)])
        // The rectangle → extrude wire is copied; extrude → output is not, as output wasn't copied.
        let copiedLinks = editor.graph.links.filter { first.contains($0.to.node) }
        #expect(copiedLinks.count == 1)
        #expect(copiedLinks.allSatisfy { first.contains($0.from.node) })
        editor.paste()
        let secondCopies = editor.selection.compactMap { editor.graph.nodes[$0] }
        #expect(Set(secondCopies.map(\.position)) == [Vector2(48, 48), Vector2(348, 48)])
        editor.document.undo()
        editor.document.undo()
        #expect(editor.graph.nodes.count == 3)
    }

    @Test func pasteWithAnEmptyClipboardDoesNothing() {
        let editor = chain()
        editor.paste()
        #expect(!editor.document.canUndo)
    }

    @Test func duplicateLeavesTheClipboardAlone() {
        let editor = chain()
        editor.selection = [output.id]
        editor.copySelection()
        editor.selection = [rect.id]
        editor.duplicateSelection()
        #expect(editor.clipboard?.nodes.map(\.id) == [output.id])
        let copy = editor.selection.first.flatMap { editor.graph.nodes[$0] }
        #expect(copy?.typeID == RectangleTestNode.typeID)
        #expect(copy?.position == Vector2(24, 24))
    }

    @Test func copiesKeepTheirInputValues() {
        let number = testNode(NumberTestNode.self, id: 9, at: .zero, values: ["value": .number(42)])
        let editor = makeEditor([number])
        editor.selection = [number.id]
        editor.duplicateSelection()
        let copy = editor.selection.first.flatMap { editor.graph.nodes[$0] }
        #expect(copy?.inputValues["value"] == .number(42))
    }

    @Test func addNodeLandsUnderTheScreenPointInStoredCoordinates() {
        let editor = makeEditor([], dock: .left)
        editor.transform = CanvasTransform(offset: Vector2(10, 20), zoom: 2)
        editor.addNode(NumberTestNode.typeID, atScreen: Vector2(110, 60))
        let added = editor.selection.first.flatMap { editor.graph.nodes[$0] }
        // Screen (110, 60) is display canvas (50, 20); the vertical flow stores its transpose.
        #expect(added?.position == Vector2(20, 50))
        #expect(added?.name == "Number")
        #expect(added?.isOutput == false)
        // `NodeRegistry.makeNode` flags `.output`-category nodes (M3), so the palette needs no special case.
        editor.addNode(OutputTestNode.typeID, atScreen: Vector2(110, 60))
        #expect(editor.selection.first.flatMap { editor.graph.nodes[$0] }?.isOutput == true)
    }

    @Test func connectReplacesTheOccupiedInputInOneUndoStep() {
        let other = testNode(RectangleTestNode.self, id: 4, at: Vector2(0, 300))
        let editor = makeEditor([rect, other, extrude], [wire(rect, "profile", extrude, "profile")])
        editor.connect(wire(other, "profile", extrude, "profile"))
        #expect(editor.graph.links == [wire(other, "profile", extrude, "profile")])
        editor.document.undo()
        #expect(editor.graph.links == [wire(rect, "profile", extrude, "profile")])
    }

    @Test func aRefusedConnectionChangesNothingAndSaysWhy() {
        let number = testNode(NumberTestNode.self, id: 4, at: Vector2(0, 300))
        let editor = makeEditor([number, extrude])
        editor.connect(wire(number, "value", extrude, "profile"))
        #expect(editor.graph.links.isEmpty)
        #expect(editor.refusal == RefusalFeedback(message: "A number can't connect to a profile input.", node: extrude.id, serial: 1))
        #expect(editor.isShaking)
        #expect(!editor.document.canUndo)
    }

    @Test func reconnectingAnExistingWireAddsNoUndoStep() {
        let editor = makeEditor([rect, extrude], [wire(rect, "profile", extrude, "profile")])
        editor.connect(wire(rect, "profile", extrude, "profile"))
        #expect(!editor.document.canUndo)
    }

    @Test func connectionProblemMessagesArePlain() {
        #expect(ConnectionProblem.sameNode.message == "A node can't be wired to itself.")
        #expect(ConnectionProblem.typeMismatch(from: .solid, to: .edgeSet).message == "A solid can't connect to an edge set input.")
        #expect(ConnectionProblem.unknownNode.message == "That node's type isn't available, so it can't be wired.")
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: "value of type 'EditorModel' has no member 'deleteSelection'" (and `connect`, `copySelection`, `paste`, `addNode`), and "type 'ConnectionProblem' has no member 'message'".

- [ ] **Step 3: Implement**

`Sources/CreatorEditor/SocketType+DisplayName.swift`:
```swift
import CreatorGraph

extension SocketType {
    /// The type's name with its article, for messages: "a number", "an edge set".
    public var indefiniteName: String {
        switch self {
        case .number: "a number"
        case .integer: "a whole number"
        case .bool: "an on/off value"
        case .vector: "a vector"
        case .plane: "a plane"
        case .profile: "a profile"
        case .solid: "a solid"
        case .edgeSet: "an edge set"
        case .faceSet: "a face set"
        }
    }
}
```

`Sources/CreatorEditor/ConnectionProblem+Message.swift`:
```swift
import CreatorGraph

extension ConnectionProblem {
    /// Plain-language text for a refused wire, shown under the canvas.
    public var message: String {
        switch self {
        case .unknownNode: "That node's type isn't available, so it can't be wired."
        case .unknownSocket(let socket): "This node has no socket “\(socket)”."
        case .sameNode: "A node can't be wired to itself."
        case .typeMismatch(let from, let to):
            "\(from.indefiniteName.prefix(1).uppercased())\(from.indefiniteName.dropFirst()) can't connect to \(to.indefiniteName) input."
        case .wouldCreateCycle: "That wire would make a loop."
        }
    }
}
```

`Sources/CreatorEditor/GraphError+Message.swift`:
```swift
import CreatorGraph

extension GraphError {
    /// Plain-language text for a refused edit.
    public var message: String {
        switch self {
        case .invalidConnection(let problem): problem.message
        case .nodeNotFound: "That node no longer exists."
        case .duplicateNode: "That node already exists."
        case .linkNotFound: "That wire no longer exists."
        case .parameterNotFound: "That parameter no longer exists."
        case .invalidValue(let message): message
        }
    }
}
```

`Sources/CreatorEditor/EditorModel+Editing.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

extension EditorModel {
    /// Wires `link`, replacing whatever already feeds its input, as one undo step. A wire the
    /// graph refuses changes nothing and shakes the input's node with a plain message.
    public func connect(_ link: Link) {
        guard !graph.links.contains(link) else { return }
        if let problem = graph.connectionProblem(from: link.from, to: link.to, registry: registry) {
            refuse(problem.message, node: link.to.node)
            return
        }
        do {
            try document.perform(.connect(link))
        } catch {
            refuse(error.message, node: link.to.node)
        }
    }

    /// Delete / ⌫: removes the selected nodes and their wires, as one undo step.
    public func deleteSelection() {
        let ids = selection.filter { graph.nodes[$0] != nil }.sorted()
        guard !ids.isEmpty else { return }
        do {
            try document.perform(.batch(ids.map { .removeNode($0) }))
            selection = []
        } catch {
            refuse(error.message, node: nil)
        }
    }

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

    func clipboard(of ids: Set<NodeID>) -> NodeClipboard {
        let nodes = ids.sorted().compactMap { graph.nodes[$0] }
        let links = graph.links.filter { ids.contains($0.from.node) && ids.contains($0.to.node) }
        return NodeClipboard(nodes: nodes, links: links)
    }

    /// Adds fresh copies of `clipboard` moved by `offset` (stored coordinates) as one undo
    /// step. Returns the new IDs, or `nil` if the graph refused.
    func insert(_ clipboard: NodeClipboard, offset: Vector2) -> Set<NodeID>? {
        guard !clipboard.nodes.isEmpty else { return nil }
        var mapping: [NodeID: NodeID] = [:]
        var commands: [GraphCommand] = []
        for original in clipboard.nodes {
            var copy = original
            copy.id = NodeID()
            copy.position = original.position + offset
            mapping[original.id] = copy.id
            commands.append(.addNode(copy))
        }
        let links = clipboard.links.compactMap { link -> Link? in
            guard let from = mapping[link.from.node], let to = mapping[link.to.node] else { return nil }
            return Link(from: Endpoint(node: from, socket: link.from.socket), to: Endpoint(node: to, socket: link.to.socket))
        }
        // Copied wires were valid when copied and join only new nodes, so they are restored as they were.
        if !links.isEmpty { commands.append(.restoreLinks(links)) }
        do {
            try document.perform(.batch(commands))
            return Set(mapping.values)
        } catch {
            refuse(error.message, node: nil)
            return nil
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter CreatorEditorTests`
Expected: PASS — `Test run with 40 tests in 7 suites passed`.

- [ ] **Step 5: Commit**

```bash
swiftlint lint --strict   # must report 0 violations before committing (CLAUDE.md "Linting")
git add Sources/CreatorEditor Tests/CreatorEditorTests
git commit -m "feat(editor): connect with refusal and replace, delete, copy, paste, duplicate, add"
```

---

### Task 5: Pointer interactions — click, pan, move, box-select, ⌥-drag, wire drag

All the canvas's pointer behaviour is here (spec §6.2): a click selects (⇧ toggles), a plain drag on empty canvas pans, ⇧-drag box-selects, dragging a node moves the selection as one undo step, ⌥-drag duplicates, and dragging from a socket connects. A press must move `dragThreshold` (3 pt) before it becomes a drag.

**Files:**
- Create: `Sources/CreatorEditor/EditorModel+Pointer.swift`
- Test: `Tests/CreatorEditorTests/PointerTests.swift`, `Tests/CreatorEditorTests/WiringTests.swift`, `Tests/CreatorEditorTests/Support/PointerTestSupport.swift`

**Interfaces:**
- Consumes: Task 3 (`beginPress`, `currentPress`, `endPress`, `setInteraction`, `hitTest`, `nodes(intersecting:)`, `flow`, `transform`) and Task 4 (`connect`, `clipboard(of:)`, `insert(_:offset:)`, `refuse`).
- Produces:
  - `EditorModel.dragThreshold = 3.0`
  - `pointerDragged(from start: Vector2, to location: Vector2)` (the gesture's `onChanged`)
  - `pointerReleased(from start: Vector2, at location: Vector2)` (its `onEnded`)
  - `pointerPressed(at:)`, which ends coalescing and closes the palette
  - A press whose `start` differs from the recorded one (a gesture that never got `onEnded`) restarts the press.
  - A wire dragged from a wired input and dropped on empty canvas disconnects (`.disconnect`).
  - All points are canvas-local screen points.
  - Test fixtures: `EditorModel.click(_:)`, `EditorModel.drag(_:_:)`.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorEditorTests/Support/PointerTestSupport.swift`:
```swift
// Test fixture file: pointer gestures for the editor tests.
import CreatorGeometry
@testable import CreatorEditor

@MainActor
extension EditorModel {
    /// A click (press and release without moving) at a canvas-local screen point.
    func click(_ point: Vector2) {
        pointerDragged(from: point, to: point)
        pointerReleased(from: point, at: point)
    }

    /// A press at `start`, a move to `end` and a release there.
    func drag(_ start: Vector2, _ end: Vector2) {
        pointerDragged(from: start, to: start)
        pointerDragged(from: start, to: end)
        pointerReleased(from: start, at: end)
    }
}
```

`Tests/CreatorEditorTests/PointerTests.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

@MainActor
struct PointerTests {
    @Test func clickSelectsAndShiftClickToggles() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([a, b])
        editor.click(editor.screenPoint(in: a.id))
        #expect(editor.selection == [a.id])
        editor.click(editor.screenPoint(in: b.id))
        #expect(editor.selection == [b.id])
        editor.modifiers = .shift
        editor.click(editor.screenPoint(in: a.id))
        #expect(editor.selection == [a.id, b.id])
        editor.click(editor.screenPoint(in: a.id))
        #expect(editor.selection == [b.id])
    }

    @Test func clickOnEmptyCanvasClearsUnlessShiftIsHeld() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let editor = makeEditor([a])
        editor.selection = [a.id]
        editor.modifiers = .shift
        editor.click(Vector2(600, 600))
        #expect(editor.selection == [a.id])
        editor.modifiers = []
        editor.click(Vector2(600, 600))
        #expect(editor.selection.isEmpty)
    }

    @Test func aTinyMoveIsStillAClick() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let editor = makeEditor([a])
        let start = editor.screenPoint(in: a.id)
        editor.drag(start, start + Vector2(2, 1))
        #expect(editor.selection == [a.id])
        #expect(editor.graph.nodes[a.id]?.position == .zero)
        #expect(!editor.document.canUndo)
    }

    @Test func anOptionClickDoesNotDuplicate() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let editor = makeEditor([a])
        editor.modifiers = .option
        let start = editor.screenPoint(in: a.id)
        editor.drag(start, start + Vector2(2, 1))
        #expect(editor.graph.nodes.count == 1)
        #expect(editor.selection == [a.id])
        #expect(!editor.document.canUndo)
    }

    @Test func aPressThatNeverEndedDoesNotLeakIntoTheNext() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([a, b])
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(50, 0))
        // No release: the window lost the gesture. The next press starts afresh.
        editor.click(editor.screenPoint(in: b.id))
        #expect(editor.selection == [b.id])
        #expect(editor.graph.nodes[a.id]?.position == Vector2(50, 0))
        #expect(editor.graph.nodes[b.id]?.position == Vector2(300, 0))
        #expect(editor.interaction == nil)
    }

    @Test func plainDragOnEmptyCanvasPans() {
        let editor = makeEditor([])
        editor.transform = CanvasTransform(offset: Vector2(5, 5), zoom: 2)
        editor.drag(Vector2(100, 100), Vector2(130, 80))
        #expect(editor.transform == CanvasTransform(offset: Vector2(35, -15), zoom: 2))
        #expect(editor.document.viewState.canvasOffset == Vector2(35, -15))
        #expect(editor.interaction == nil)
    }

    @Test func shiftDragOnEmptyCanvasBoxSelectsAddingToTheSelection() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let b = testNode(NumberTestNode.self, id: 2, at: Vector2(400, 0))
        let c = testNode(NumberTestNode.self, id: 3, at: Vector2(800, 0))
        let editor = makeEditor([a, b, c])
        editor.selection = [c.id]
        editor.modifiers = .shift
        let start = Vector2(380, -20)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: Vector2(420, 20))
        guard case .boxSelecting(let corner, let current, let base)? = editor.interaction else {
            Issue.record("expected a box selection"); return
        }
        #expect(corner == start && current == Vector2(420, 20) && base == [c.id])
        editor.pointerReleased(from: start, at: Vector2(420, 20))
        #expect(editor.selection == [b.id, c.id])
        #expect(editor.transform.offset == .zero)
    }

    @Test func draggingANodeMovesTheSelectionInOneUndoStep() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([a, b])
        editor.transform = CanvasTransform(zoom: 2)
        editor.selection = [a.id, b.id]
        let start = editor.screenPoint(in: a.id)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(10, 10))
        editor.pointerDragged(from: start, to: start + Vector2(40, 20))
        editor.pointerReleased(from: start, at: start + Vector2(40, 20))
        // 40×20 screen points at zoom 2 is 20×10 canvas points.
        #expect(editor.graph.nodes[a.id]?.position == Vector2(20, 10))
        #expect(editor.graph.nodes[b.id]?.position == Vector2(320, 10))
        editor.document.undo()
        #expect(editor.graph.nodes[a.id]?.position == .zero)
        #expect(editor.graph.nodes[b.id]?.position == Vector2(300, 0))
        #expect(!editor.document.canUndo)
    }

    @Test func draggingAnUnselectedNodeSelectsItFirst() {
        let a = testNode(NumberTestNode.self, id: 1, at: .zero)
        let b = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([a, b])
        editor.selection = [b.id]
        let start = editor.screenPoint(in: a.id)
        editor.drag(start, start + Vector2(0, 50))
        #expect(editor.selection == [a.id])
        #expect(editor.graph.nodes[a.id]?.position == Vector2(0, 50))
        #expect(editor.graph.nodes[b.id]?.position == Vector2(300, 0))
    }

    @Test func leftDockMovesInStoredCoordinates() {
        let a = testNode(NumberTestNode.self, id: 1, at: Vector2(100, 0))
        let editor = makeEditor([a], dock: .left)
        let start = editor.screenPoint(in: a.id)
        // Down the screen in the vertical flow is along the stored x axis.
        editor.drag(start, start + Vector2(0, 30))
        #expect(editor.graph.nodes[a.id]?.position == Vector2(130, 0))
    }

    @Test func optionDragDuplicatesAsOneUndoStepAndLeavesTheOriginals() {
        let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
        let extrude = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([rect, extrude], [wire(rect, "profile", extrude, "profile")])
        editor.selection = [rect.id, extrude.id]
        editor.modifiers = .option
        let start = editor.screenPoint(in: rect.id)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(0, 200))
        guard case .duplicating(_, let delta)? = editor.interaction else { Issue.record("expected ghosts"); return }
        #expect(delta == Vector2(0, 200))
        #expect(editor.graph.nodes.count == 2)
        editor.pointerReleased(from: start, at: start + Vector2(0, 200))
        #expect(editor.graph.nodes.count == 4)
        #expect(editor.graph.links.count == 2)
        #expect(editor.graph.nodes[rect.id]?.position == .zero)
        let copies = editor.selection.compactMap { editor.graph.nodes[$0] }
        #expect(Set(copies.map(\.position)) == [Vector2(0, 200), Vector2(300, 200)])
        editor.document.undo()
        #expect(editor.graph.nodes.count == 2)
        #expect(!editor.document.canUndo)
    }
}
```

`Tests/CreatorEditorTests/WiringTests.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

@MainActor
struct WiringTests {
    let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
    let other = testNode(RectangleTestNode.self, id: 2, at: Vector2(0, 300))
    let extrude = testNode(ExtrudeTestNode.self, id: 3, at: Vector2(300, 0))
    let number = testNode(NumberTestNode.self, id: 4, at: Vector2(300, 300))

    @Test func draggingFromAnOutputToAnInputConnects() {
        let editor = makeEditor([rect, extrude])
        editor.drag(editor.screenPoint(of: rect.id, "profile", input: false),
                    editor.screenPoint(of: extrude.id, "profile", input: true))
        #expect(editor.graph.links == [wire(rect, "profile", extrude, "profile")])
        #expect(editor.refusal == nil)
    }

    @Test func draggingFromAnInputBackToAnOutputConnects() {
        let editor = makeEditor([rect, extrude])
        editor.drag(editor.screenPoint(of: extrude.id, "profile", input: true),
                    editor.screenPoint(of: rect.id, "profile", input: false))
        #expect(editor.graph.links == [wire(rect, "profile", extrude, "profile")])
    }

    @Test func theWireFollowsThePointerWhileDragging() {
        let editor = makeEditor([rect, extrude])
        let start = editor.screenPoint(of: rect.id, "profile", input: false)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: Vector2(250, 200))
        #expect(editor.interaction == .connecting(WireDrag(
            from: SocketRef(Endpoint(node: rect.id, socket: "profile"), isInput: false), current: Vector2(250, 200))))
    }

    @Test func droppingOnAnOccupiedInputReplacesItsWireInOneUndoStep() {
        let editor = makeEditor([rect, other, extrude], [wire(rect, "profile", extrude, "profile")])
        editor.drag(editor.screenPoint(of: other.id, "profile", input: false),
                    editor.screenPoint(of: extrude.id, "profile", input: true))
        #expect(editor.graph.links == [wire(other, "profile", extrude, "profile")])
        editor.document.undo()
        #expect(editor.graph.links == [wire(rect, "profile", extrude, "profile")])
    }

    @Test func aTypeMismatchIsRefusedWithAPlainMessage() {
        let editor = makeEditor([number, extrude])
        editor.drag(editor.screenPoint(of: number.id, "value", input: false),
                    editor.screenPoint(of: extrude.id, "profile", input: true))
        #expect(editor.graph.links.isEmpty)
        #expect(editor.refusal?.message == "A number can't connect to a profile input.")
        #expect(editor.refusal?.node == extrude.id)
        #expect(editor.isShaking)
        #expect(!editor.document.canUndo)
    }

    @Test func outputToOutputIsRefused() {
        let editor = makeEditor([rect, other])
        editor.drag(editor.screenPoint(of: rect.id, "profile", input: false),
                    editor.screenPoint(of: other.id, "profile", input: false))
        #expect(editor.graph.links.isEmpty)
        #expect(editor.refusal?.message == "Connect an output to an input.")
    }

    @Test func aCycleIsRefused() {
        let a = testNode(NumberTestNode.self, id: 5, at: .zero)
        let b = testNode(NumberTestNode.self, id: 6, at: Vector2(300, 0))
        let editor = makeEditor([a, b], [wire(a, "value", b, "value")])
        editor.drag(editor.screenPoint(of: b.id, "value", input: false),
                    editor.screenPoint(of: a.id, "value", input: true))
        #expect(editor.graph.links == [wire(a, "value", b, "value")])
        #expect(editor.refusal?.message == "That wire would make a loop.")
    }

    @Test func droppingOnEmptyCanvasDoesNothing() {
        let editor = makeEditor([rect, extrude])
        editor.drag(editor.screenPoint(of: rect.id, "profile", input: false), Vector2(900, 900))
        #expect(editor.graph.links.isEmpty)
        #expect(editor.refusal == nil)
        #expect(editor.interaction == nil)
    }

    @Test func draggingAWiredInputOntoEmptyCanvasDisconnectsIt() {
        let editor = makeEditor([rect, extrude], [wire(rect, "profile", extrude, "profile")])
        editor.drag(editor.screenPoint(of: extrude.id, "profile", input: true), Vector2(900, 900))
        #expect(editor.graph.links.isEmpty)
        editor.document.undo()
        #expect(editor.graph.links == [wire(rect, "profile", extrude, "profile")])
        #expect(!editor.document.canUndo)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: "value of type 'EditorModel' has no member 'pointerDragged'" (and `pointerReleased`).

- [ ] **Step 3: Implement**

`Sources/CreatorEditor/EditorModel+Pointer.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

extension EditorModel {
    /// How far a press must move before it counts as a drag, in screen points.
    public static let dragThreshold = 3.0

    /// A canvas drag moved. `start` and `location` are canvas-local screen points. The first
    /// call of a press records what it landed on; a drag starts once it moves `dragThreshold`.
    public func pointerDragged(from start: Vector2, to location: Vector2) {
        ensurePress(at: start)
        guard let press = currentPress else { return }
        if interaction == nil {
            guard (location - press.point).length >= Self.dragThreshold else { return }
            setInteraction(beginInteraction(for: press.hit, at: press.point))
        }
        update(to: location, from: press.point)
    }

    /// The press ended at `location`. Without a drag this is a click.
    public func pointerReleased(from start: Vector2, at location: Vector2) {
        ensurePress(at: start)
        guard let press = currentPress else { return }
        switch interaction {
        case nil: click(press.hit)
        case .moving: document.endCoalescing()
        case .duplicating(let start, let delta): finishDuplicate(start: start, delta: delta)
        case .connecting(let wire): finishWire(wire, at: location)
        case .panning, .boxSelecting: break
        }
        endPress()
    }

    /// A press began. Ends any slider drag's undo step and closes the palette.
    public func pointerPressed(at screen: Vector2) {
        document.endCoalescing()
        palette = nil
        beginPress(at: screen)
    }

    /// Starts a press at `start` unless one with that start is in progress. A recorded press
    /// with another start is a gesture that never ended (say the window lost key status
    /// mid-drag); it is dropped, so its hit and interaction don't leak into this one.
    private func ensurePress(at start: Vector2) {
        guard currentPress?.point != start else { return }
        if currentPress != nil { endPress() }
        pointerPressed(at: start)
    }

    private func click(_ hit: CanvasHit) {
        let extending = modifiers.contains(.shift)
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

    private func beginInteraction(for hit: CanvasHit, at screen: Vector2) -> CanvasInteraction {
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

- [ ] **Step 4: Run the tests**

Run: `swift test --filter CreatorEditorTests`
Expected: PASS — `Test run with 60 tests in 9 suites passed`.

- [ ] **Step 5: Commit**

```bash
swiftlint lint --strict   # must report 0 violations before committing (CLAUDE.md "Linting")
git add Sources/CreatorEditor Tests/CreatorEditorTests
git commit -m "feat(editor): canvas pointer interactions with drag threshold, box select, ⌥-drag and wiring"
```

---

### Task 6: Add-node palette, keyboard commands and the stopgap input mapping

**Files:**
- Create: `Sources/CreatorEditor/PaletteEntry.swift`, `PaletteSearch.swift`, `EditorModel+Palette.swift`, `GraphKeyCommand.swift`, `EditorModel+Commands.swift`, `GraphKeyBindings.swift`, `PaletteMove.swift`, `GraphPanelInput.swift`
- Test: `Tests/CreatorEditorTests/SearchPaletteTests.swift`, `Tests/CreatorEditorTests/KeyCommandTests.swift`, `Tests/CreatorEditorTests/GraphPanelInputTests.swift`

**Interfaces:**
- Consumes: Tasks 3–5. From MetalUI: `KeyEvent(charactersIgnoringModifiers:characters:modifiers:isRepeat:timestamp:)`, `Modifiers` (`.shift`, `.option`, `.command`), `InputEvent` (`.modifiersChanged`, `.keyDown`), `DragGesture(minimumDistance:)` with `.onChanged`/`.onEnded` (`Value.startLocation`, `.location`, and the public `Value(startLocation:location:)` for the test), `Window` (`onInput`, `keymap`, `onAction`, `focus(_:)`), `HoverPhase` (`.active(Point<Pixels>)`, `.ended`), and `Action`, `Keymap`, `KeyBinding(_:_:)` (the window keymap, which runs before a focused field's editing keys).
- Produces:
  - `public struct PaletteEntry: Identifiable { typeID; displayName; category }`
  - `public enum PaletteSearch { static func entries(in: NodeRegistry, matching: String) -> [PaletteEntry] }`. It uses `localizedStandardContains`, puts prefix matches first, then sorts by category and name.
  - `EditorModel.openPalette()`, `closePalette()`, `paletteEntries`, `setPaletteQuery(_:)`, `movePaletteHighlight(by:)`, `confirmPalette(_ entry: PaletteEntry? = nil)`
  - `public enum GraphKeyCommand { tab, openPalette, deleteSelection, copy, paste, duplicate, zoomIn, zoomOut, undo, redo, cancel, paletteUp, paletteDown, paletteConfirm }`
  - `EditorModel.perform(_: GraphKeyCommand) -> Bool` (`@discardableResult`)
  - `public enum GraphKeyBindings { static func command(for: KeyEvent, paletteOpen: Bool) -> GraphKeyCommand? }`
  - `public struct PaletteMove: Action { step: Int }`
  - `@MainActor public final class GraphPanelInput { init(model:); var releaseTextFocus: (@MainActor () -> Void)?; install(on: Window); static var keymap: Keymap; handle(_ event: InputEvent) -> Bool; handleAction(_ action: any Action) -> Bool; canvasGesture() -> DragGesture; hover(_ phase: HoverPhase); static canvasModifiers(_:) }`.
  - Internal:
    - the C7 stand-ins `static spatialTapGesture() -> DragGesture` (C7 `SpatialTapGesture`) and `dragValueModifiers(_: DragGesture.Value) -> CanvasModifiers` (C7 `DragGesture.Value.modifiers`), each named after its provisional C7 API (docs/metalui-gaps.md);
    - `canvasChanged(from:to:)` and `canvasEnded(from:at:)`, the gesture's two callbacks, which release text focus at the start of each press.
  - `install(on:)` chains `onInput`/`onAction` onto the window's existing handlers and appends `keymap`. Its `onInput` side composes with M4's `ViewportModifierTracker.install(on:)` in either order. M4 assigns its keymap and `onAction` directly, so those must be set before `install(on:)` (see Decisions).

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorEditorTests/SearchPaletteTests.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

@MainActor
struct SearchPaletteTests {
    @Test func anEmptyQueryListsEveryTypeByCategoryThenName() {
        let names = PaletteSearch.entries(in: editorTestRegistry, matching: "").map(\.displayName)
        #expect(names == ["Number", "Rectangle", "Extrude", "All Edges", "Fillet", "Output"])
    }

    @Test func queriesMatchAnywhereIgnoringCaseAndPrefixesComeFirst() {
        #expect(PaletteSearch.entries(in: editorTestRegistry, matching: "EDGE").map(\.displayName) == ["All Edges"])
        // "e" prefixes Extrude and appears inside the others.
        let names = PaletteSearch.entries(in: editorTestRegistry, matching: "e").map(\.displayName)
        #expect(names.first == "Extrude")
        #expect(Set(names) == ["Extrude", "Number", "Rectangle", "All Edges", "Fillet"])
        #expect(PaletteSearch.entries(in: editorTestRegistry, matching: "zzz").isEmpty)
        #expect(PaletteSearch.entries(in: editorTestRegistry, matching: "  fil ").map(\.displayName) == ["Fillet"])
    }

    @Test func thePaletteOpensUnderThePointer() {
        let editor = makeEditor([])
        editor.pointerLocation = Vector2(120, 80)
        editor.openPalette()
        #expect(editor.palette == SearchPaletteState(screenPosition: Vector2(120, 80)))
    }

    @Test func confirmingAddsTheHighlightedTypeUnderThePaletteAndSelectsIt() {
        let editor = makeEditor([])
        editor.pointerLocation = Vector2(200, 100)
        editor.openPalette()
        editor.setPaletteQuery("t")
        #expect(editor.paletteEntries.map(\.displayName) == ["Rectangle", "Extrude", "Fillet", "Output"])
        editor.movePaletteHighlight(by: 1)
        editor.confirmPalette()
        #expect(editor.palette == nil)
        let added = editor.selection.first.flatMap { editor.graph.nodes[$0] }
        #expect(added?.typeID == ExtrudeTestNode.typeID)
        #expect(added?.position == Vector2(200, 100))
    }

    @Test func theHighlightStaysWithinTheMatches() {
        let editor = makeEditor([])
        editor.openPalette()
        editor.movePaletteHighlight(by: -3)
        #expect(editor.palette?.highlighted == 0)
        editor.movePaletteHighlight(by: 50)
        #expect(editor.palette?.highlighted == 5)
        editor.setPaletteQuery("out")
        #expect(editor.palette?.highlighted == 0)
    }

    @Test func confirmingWithNoMatchesKeepsThePaletteOpen() {
        let editor = makeEditor([])
        editor.openPalette()
        editor.setPaletteQuery("zzz")
        editor.confirmPalette()
        #expect(editor.palette != nil)
        #expect(editor.graph.nodes.isEmpty)
    }

    @Test func pressingTheCanvasClosesThePalette() {
        let editor = makeEditor([])
        editor.openPalette()
        editor.click(Vector2(50, 50))
        #expect(editor.palette == nil)
    }
}
```

`Tests/CreatorEditorTests/KeyCommandTests.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

@MainActor
struct KeyCommandTests {
    func key(_ characters: String, _ modifiers: Modifiers = []) -> KeyEvent {
        KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers, timestamp: 0)
    }

    @Test func theCanvasKeys() {
        #expect(GraphKeyBindings.command(for: key(" "), paletteOpen: false) == .openPalette)
        #expect(GraphKeyBindings.command(for: key("\t"), paletteOpen: false) == .tab)
        #expect(GraphKeyBindings.command(for: key("\t", .shift), paletteOpen: false) == nil)
        #expect(GraphKeyBindings.command(for: key("\u{7f}"), paletteOpen: false) == .deleteSelection)
        #expect(GraphKeyBindings.command(for: key("\u{f728}"), paletteOpen: false) == .deleteSelection)
        #expect(GraphKeyBindings.command(for: key("c", .command), paletteOpen: false) == .copy)
        #expect(GraphKeyBindings.command(for: key("v", .command), paletteOpen: false) == .paste)
        #expect(GraphKeyBindings.command(for: key("d", .command), paletteOpen: false) == .duplicate)
        #expect(GraphKeyBindings.command(for: key("z", .command), paletteOpen: false) == .undo)
        #expect(GraphKeyBindings.command(for: key("Z", [.command, .shift]), paletteOpen: false) == .redo)
        #expect(GraphKeyBindings.command(for: key("="), paletteOpen: false) == .zoomIn)
        #expect(GraphKeyBindings.command(for: key("+", .shift), paletteOpen: false) == .zoomIn)
        #expect(GraphKeyBindings.command(for: key("-"), paletteOpen: false) == .zoomOut)
        #expect(GraphKeyBindings.command(for: key("c"), paletteOpen: false) == nil)
        #expect(GraphKeyBindings.command(for: key("c", [.command, .option]), paletteOpen: false) == nil)
    }

    @Test func whileThePaletteIsOpenOnlyItsNavigationKeysAreTaken() {
        #expect(GraphKeyBindings.command(for: key("\u{1b}"), paletteOpen: true) == .cancel)
        #expect(GraphKeyBindings.command(for: key("\u{f700}"), paletteOpen: true) == .paletteUp)
        #expect(GraphKeyBindings.command(for: key("\u{f701}"), paletteOpen: true) == .paletteDown)
        #expect(GraphKeyBindings.command(for: key("\r"), paletteOpen: true) == .paletteConfirm)
        #expect(GraphKeyBindings.command(for: key(" "), paletteOpen: true) == nil)
        #expect(GraphKeyBindings.command(for: key("\u{7f}"), paletteOpen: true) == nil)
    }

    @Test func tabOpensThePaletteOverTheCanvasAndOtherwiseTogglesThePanel() {
        let editor = makeEditor([], dock: .left)
        editor.perform(.tab)
        #expect(editor.dock == .hidden)
        editor.perform(.tab)
        #expect(editor.dock == .left)
        editor.pointerLocation = Vector2(10, 10)
        editor.perform(.tab)
        #expect(editor.palette != nil)
        #expect(editor.dock == .left)
    }

    @Test func spaceDoesNothingWhileThePanelIsHidden() {
        let editor = makeEditor([], dock: .hidden)
        #expect(!editor.perform(.openPalette))
        #expect(editor.palette == nil)
    }

    @Test func zoomKeysZoomAboutThePointer() {
        let editor = makeEditor([])
        editor.pointerLocation = Vector2(100, 100)
        editor.perform(.zoomIn)
        #expect(editor.transform.zoom == 1.25)
        #expect(editor.transform.toCanvas(Vector2(100, 100)) == Vector2(100, 100))
        editor.perform(.zoomOut)
        #expect(abs(editor.transform.zoom - 1) < 1e-12)
    }

    @Test func undoAndRedoGoThroughTheDocument() {
        let editor = makeEditor([testNode(NumberTestNode.self, id: 1, at: .zero)])
        editor.selection = [nodeID(1)]
        editor.perform(.deleteSelection)
        #expect(editor.graph.nodes.isEmpty)
        editor.perform(.undo)
        #expect(editor.graph.nodes.count == 1)
        editor.perform(.redo)
        #expect(editor.graph.nodes.isEmpty)
    }

    @Test func deleteWithNothingSelectedLetsTheKeyThrough() {
        let editor = makeEditor([])
        #expect(!editor.perform(.deleteSelection))
        #expect(!editor.perform(.cancel))
    }
}
```

`Tests/CreatorEditorTests/GraphPanelInputTests.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

@MainActor
struct GraphPanelInputTests {
    @Test func modifierChangesReachTheModelWithoutBeingClaimed() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        #expect(!input.handle(.modifiersChanged([.shift, .option])))
        #expect(editor.modifiers == [.shift, .option])
        #expect(!input.handle(.modifiersChanged([])))
        #expect(editor.modifiers.isEmpty)
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
        #expect(GraphPanelInput.keymap.bindings.map(\.spelling) == ["up", "down"])
        #expect(GraphPanelInput.keymap.bindings.allSatisfy { $0.action is PaletteMove })
        // Closed: unhandled, so MetalUI passes the arrow on to a focused field.
        #expect(!input.handleAction(PaletteMove(step: 1)))
        editor.openPalette()
        #expect(input.handleAction(PaletteMove(step: 1)))
        #expect(editor.palette?.highlighted == 1)
        #expect(input.handleAction(PaletteMove(step: -1)))
        #expect(editor.palette?.highlighted == 0)
    }

    @Test func aCanvasPressReleasesTextFocusOncePerPress() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        var releases = 0
        input.releaseTextFocus = { releases += 1 }
        input.canvasChanged(from: Vector2(10, 10), to: Vector2(10, 10))
        input.canvasChanged(from: Vector2(10, 10), to: Vector2(40, 10))
        input.canvasEnded(from: Vector2(10, 10), at: Vector2(40, 10))
        #expect(releases == 1)
        input.canvasEnded(from: Vector2(5, 5), at: Vector2(5, 5))
        #expect(releases == 2)
        #expect(editor.transform.offset == Vector2(30, 0))
    }

    /// The C7 stand-ins are single functions named after C7's provisional APIs, so the swap is local.
    @Test func theC7StandInsAreTheirOwnFunctions() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        #expect(GraphPanelInput.spatialTapGesture().minimumDistance == Pixels(0))
        _ = input.handle(.modifiersChanged([.option]))
        let value = DragGesture.Value(startLocation: Point(x: Pixels(1), y: Pixels(2)), location: Point(x: Pixels(3), y: Pixels(4)))
        #expect(input.dragValueModifiers(value) == .option)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: "cannot find 'PaletteSearch' in scope", "cannot find 'GraphKeyBindings' in scope", "cannot find 'GraphPanelInput' in scope".

- [ ] **Step 3: Implement**

`Sources/CreatorEditor/PaletteEntry.swift`:
```swift
import CreatorGraph

/// One node type offered by the add-node palette.
public struct PaletteEntry: Equatable, Sendable, Identifiable {
    public var typeID: String
    public var displayName: String
    public var category: NodeCategory

    public var id: String { typeID }
}
```

`Sources/CreatorEditor/PaletteSearch.swift`:
```swift
import CreatorGraph
import Foundation

/// The add-node palette's search: every registered type whose name contains the query
/// (case- and diacritic-insensitive), name-prefix matches first, then by category and name.
public enum PaletteSearch {
    public static func entries(in registry: NodeRegistry, matching query: String) -> [PaletteEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let all = registry.all.map { PaletteEntry(typeID: $0.typeID, displayName: $0.displayName, category: $0.category) }
        let matches = needle.isEmpty ? all : all.filter { $0.displayName.localizedStandardContains(needle) }
        return matches.sorted { a, b in
            let aPrefix = isPrefix(needle, of: a.displayName), bPrefix = isPrefix(needle, of: b.displayName)
            if aPrefix != bPrefix { return aPrefix }
            let aRank = NodeCategory.allCases.firstIndex(of: a.category) ?? 0
            let bRank = NodeCategory.allCases.firstIndex(of: b.category) ?? 0
            if aRank != bRank { return aRank < bRank }
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
    }

    private static func isPrefix(_ needle: String, of name: String) -> Bool {
        !needle.isEmpty && name.range(of: needle, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
    }
}
```

`Sources/CreatorEditor/EditorModel+Palette.swift`:
```swift
import CreatorGeometry

extension EditorModel {
    /// Tab or Space: opens the add-node palette under the pointer (or the canvas corner).
    public func openPalette() {
        palette = SearchPaletteState(screenPosition: pointerLocation ?? Vector2(24, 24))
    }

    public func closePalette() { palette = nil }

    /// The palette's matches for its current query.
    public var paletteEntries: [PaletteEntry] {
        guard let palette else { return [] }
        return PaletteSearch.entries(in: registry, matching: palette.query)
    }

    public func setPaletteQuery(_ query: String) {
        palette?.query = query
        palette?.highlighted = 0
    }

    /// Moves the highlight by `step`, clamped to the matches.
    public func movePaletteHighlight(by step: Int) {
        guard let palette else { return }
        let count = paletteEntries.count
        guard count > 0 else { return }
        self.palette?.highlighted = min(max(palette.highlighted + step, 0), count - 1)
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

`Sources/CreatorEditor/GraphKeyCommand.swift`:
```swift
/// A keyboard command the graph panel understands (spec §6.2), independent of how the key
/// arrived. `GraphKeyBindings` maps keys to these; `EditorModel.perform(_:)` runs them.
public enum GraphKeyCommand: Equatable, Sendable {
    /// Tab: the palette when the pointer is over a visible canvas, otherwise toggles the panel.
    case tab
    /// Space: the add-node palette.
    case openPalette
    case deleteSelection
    case copy
    case paste
    case duplicate
    case zoomIn
    case zoomOut
    case undo
    case redo
    /// Escape: closes the palette, cancels a drag-free state.
    case cancel
    case paletteUp
    case paletteDown
    case paletteConfirm
}
```

`Sources/CreatorEditor/EditorModel+Commands.swift`:
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
            guard !selection.isEmpty else { return false }
            deleteSelection()
        case .copy, .paste, .duplicate, .zoomIn, .zoomOut, .undo, .redo:
            performEdit(command)
        case .cancel, .paletteUp, .paletteDown, .paletteConfirm:
            return performPaletteCommand(command)
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

    /// The palette's keys. Escape does nothing (and goes on) while no palette is open.
    private func performPaletteCommand(_ command: GraphKeyCommand) -> Bool {
        switch command {
        case .cancel:
            guard palette != nil else { return false }
            closePalette()
        case .paletteUp: movePaletteHighlight(by: -1)
        case .paletteDown: movePaletteHighlight(by: 1)
        case .paletteConfirm: confirmPalette()
        default: return false // `perform(_:)` routes every other command elsewhere.
        }
        return true
    }
}
```

`Sources/CreatorEditor/GraphKeyBindings.swift`:
```swift
import MetalUI

/// The graph panel's keys (spec §6.2). Pure, so the mapping is tested without a window.
public enum GraphKeyBindings {
    /// The command for `key`, or `nil` to let it through. While the palette is open only its
    /// navigation keys are taken, so typing reaches its search field.
    public static func command(for key: KeyEvent, paletteOpen: Bool) -> GraphKeyCommand? {
        let modifiers = key.modifiers.subtracting(.shift)
        let character = key.charactersIgnoringModifiers
        let shifted = key.modifiers.contains(.shift)
        if paletteOpen {
            return modifiers.isEmpty ? paletteCommand(for: character) : nil
        }
        if modifiers == .command {
            return commandChord(for: character.lowercased(), shifted: shifted)
        }
        return modifiers.isEmpty ? plainCommand(for: character, shifted: shifted) : nil
    }

    /// The palette's navigation keys (no modifiers but Shift).
    static func paletteCommand(for character: String) -> GraphKeyCommand? {
        switch character {
        case "\u{1b}": .cancel
        case "\u{f700}": .paletteUp
        case "\u{f701}": .paletteDown
        case "\r": .paletteConfirm
        default: nil
        }
    }

    /// ⌘ chords; `character` is already lowercased, and ⇧ turns ⌘Z into redo.
    static func commandChord(for character: String, shifted: Bool) -> GraphKeyCommand? {
        switch character {
        case "c": .copy
        case "v": .paste
        case "d": .duplicate
        case "z": shifted ? .redo : .undo
        default: nil
        }
    }

    /// Keys with no modifier but Shift. ⇧⇥ isn't Tab's job (it's reverse focus traversal).
    static func plainCommand(for character: String, shifted: Bool) -> GraphKeyCommand? {
        switch character {
        case "\t": shifted ? nil : .tab
        case " ": .openPalette
        case "\u{7f}", "\u{f728}": .deleteSelection
        case "=", "+": .zoomIn
        case "-": .zoomOut
        case "\u{1b}": .cancel
        default: nil
        }
    }
}
```

`Sources/CreatorEditor/PaletteMove.swift`:
```swift
import MetalUI

/// Moves the add-node palette's highlight. Bound to ↑/↓ in `GraphPanelInput.keymap`, because
/// the window keymap runs before the focused search field claims the arrows (docs/metalui-gaps.md M5-h).
public struct PaletteMove: Action, Equatable, Sendable {
    public var step: Int

    public init(step: Int) {
        self.step = step
    }
}
```

`Sources/CreatorEditor/GraphPanelInput.swift`:
```swift
import CreatorGeometry
import MetalUI

/// The graph panel's stopgap input bindings (spec §9), in one place so MetalUI's C7 APIs can
/// replace them locally (docs/metalui-gaps.md). Each C7 stand-in is one function named after the
/// provisional C7 API it waits for, so the swap stays in this file (and its test):
/// - `spatialTapGesture()` (C7 `SpatialTapGesture`, gap 4): a click's location comes from a
///   `DragGesture(minimumDistance: 0)` that ends where it began. Its swap changes the return type,
///   so `canvasGesture()` then splits into a tap plus a drag with a nonzero minimum distance.
/// - `dragValueModifiers(_:)` (C7 `DragGesture.Value.modifiers`, gap 5): the modifiers held during
///   a press, tracked meanwhile from the window's `.modifiersChanged` and key events in `handle(_:)`.
///   Its swap is body-only.
/// - Scroll and pinch (C7 `.onScrollWheel`, `MagnifyGesture`, gaps 1, 2) have no stand-in: the
///   +/− keys and header zoom buttons (`EditorModel.zoom(in:)`) are the stopgap, and they stay.
///   The canvas sets no cursor yet (C7 `.pointerStyle(_:)`).
///
/// Two more stopgaps are for MetalUI gaps outside C7:
/// - keys: read from the window's `onInput` fallback, so a focused text field keeps its keys;
///   the palette's ↑/↓ alone go through the window keymap (`keymap`, `handleAction`), because a
///   focused field claims arrows before `onInput` (gap M5-h);
/// - focus: a canvas press clears text focus through `releaseTextFocus`, because MetalUI never
///   unfocuses a field on an outside press (gap M5-g).
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

    /// Installs every hook on `window`, composing with the handlers already there. Its `onInput`
    /// side can go on before or after M4's `ViewportModifierTracker.install(on:)`, which chains the
    /// same way. A keymap or `onAction` *assigned* after this call replaces the graph's (M4's
    /// harness assigns both), so the host sets those first, or appends and chains them like this:
    /// - `onInput`: this panel's `handle(_:)` first, then the previous handler. `.modifiersChanged`
    ///   is never claimed, so both trackers see it.
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
        }
    }

    /// Install from `Window.onAction`. Runs a palette move while the palette is open. Otherwise it
    /// returns false, and MetalUI passes the key on (to a focused field) as if it were unbound.
    public func handleAction(_ action: any Action) -> Bool {
        guard let move = action as? PaletteMove, model.palette != nil else { return false }
        model.movePaletteHighlight(by: move.step)
        return true
    }

    /// Install from `Window.onInput` (`install(on:)` does). Returns true when the event was used.
    /// Tracking modifiers here is part of the `dragValueModifiers(_:)` stopgap.
    public func handle(_ event: InputEvent) -> Bool {
        switch event {
        case .modifiersChanged(let modifiers):
            model.modifiers = Self.canvasModifiers(modifiers)
            return false
        case .keyDown(let key):
            model.modifiers = Self.canvasModifiers(key.modifiers)
            guard let command = GraphKeyBindings.command(for: key, paletteOpen: model.palette != nil) else { return false }
            return model.perform(command)
        default:
            return false
        }
    }

    /// The canvas's one press-and-drag gesture: clicks, pans, moves, box selection and wiring.
    public func canvasGesture() -> DragGesture {
        Self.spatialTapGesture()
            .onChanged { [self] value in
                adoptModifiers(of: value)
                canvasChanged(from: Self.vector(value.startLocation), to: Self.vector(value.location))
            }
            .onEnded { [self] value in
                adoptModifiers(of: value)
                canvasEnded(from: Self.vector(value.startLocation), at: Self.vector(value.location))
            }
    }

    /// Stand-in for C7's `SpatialTapGesture` (gap 4). MetalUI reports no tap location, so a click
    /// is a zero-distance drag: it reports a change and an end at the press point. When C7 lands,
    /// a `SpatialTapGesture` carries the clicks and this drag keeps its minimum distance.
    static func spatialTapGesture() -> DragGesture {
        DragGesture(minimumDistance: Pixels(0))
    }

    /// Stand-in for C7's `DragGesture.Value.modifiers` (gap 5): the modifiers held at this change
    /// of the press. Today they are the ones `handle(_:)` tracked from `.modifiersChanged` and key
    /// events. When C7 lands this returns `Self.canvasModifiers(value.modifiers)`, and `handle(_:)`
    /// stops tracking.
    func dragValueModifiers(_ value: DragGesture.Value) -> CanvasModifiers {
        model.modifiers
    }

    /// Writes the press's modifiers into the model only when they changed, so an unchanged set
    /// doesn't invalidate the model's observers on every drag step.
    private func adoptModifiers(of value: DragGesture.Value) {
        let held = dragValueModifiers(value)
        if held != model.modifiers { model.modifiers = held }
    }

    /// The gesture moved. The first call of a press releases text focus.
    func canvasChanged(from start: Vector2, to location: Vector2) {
        if model.currentPress?.point != start { releaseTextFocus?() }
        model.pointerDragged(from: start, to: location)
    }

    /// The gesture ended (a click calls only this, so it releases focus too).
    func canvasEnded(from start: Vector2, at location: Vector2) {
        if model.currentPress?.point != start { releaseTextFocus?() }
        model.pointerReleased(from: start, at: location)
    }

    /// The pointer over the canvas, from `.onContinuousHover`.
    public func hover(_ phase: HoverPhase) {
        switch phase {
        case .active(let point): model.pointerLocation = Self.vector(point)
        case .ended: model.pointerLocation = nil
        }
    }

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

- [ ] **Step 4: Run the tests**

Run: `swift test --filter CreatorEditorTests`
Expected: PASS — `Test run with 80 tests in 12 suites passed`.

- [ ] **Step 5: Commit**

```bash
swiftlint lint --strict   # must report 0 violations before committing (CLAUDE.md "Linting")
git add Sources/CreatorEditor Tests/CreatorEditorTests
git commit -m "feat(editor): add-node palette, keyboard commands and the stopgap input mapping"
```

---

### Task 7: Value formatting, status badges, labels and plane choices

**Files:**
- Create: `Sources/CreatorEditor/PlaneChoice.swift`, `ValueText.swift`, `StatusBadge.swift`, `InspectorLabel.swift`
- Test: `Tests/CreatorEditorTests/FormattingTests.swift`

**Interfaces:**
- Consumes: `Plane` (`.xy`, `.xz`, `.yz`, `offset(by:)`), `ConstantValue`, `ValueUnit`, `NodeState`, `SocketName`.
- Produces:
  - `public enum PlaneChoice: String, CaseIterable { xy = "XY", xz = "XZ", yz = "YZ"; var plane; init?(_ plane: Plane) }`. It matches orientation and ignores the origin.
  - `public enum ValueText { static let locale; format(_: Double, unit:); format(_: ConstantValue?, unit:); parse(_: String) -> Double?; wholeNumber(_: Double) -> Int? }`. Formatting uses `FormatStyle` with up to 3 decimals, in the fixed `en_US_POSIX` locale so what it shows `parse` reads back. Parsing accepts a trailing "mm", "°" or "deg", and rejects garbage and non-finite values. `wholeNumber` rounds and returns `nil` for a value no `Int` holds (never traps).
  - `public enum StatusBadge { text(for: NodeState?) -> String; message(for:) -> String? }`
  - `public enum InspectorLabel { text(for: SocketName) -> String }`, e.g. "cornerRadius" → "Corner radius".

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorEditorTests/FormattingTests.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

struct FormattingTests {
    @Test func numbersShowUpToThreeDecimalsWithTheirUnit() {
        #expect(ValueText.format(60, unit: .millimetres) == "60 mm")
        #expect(ValueText.format(0.25, unit: .none) == "0.25")
        #expect(ValueText.format(1.23456, unit: .degrees) == "1.235°")
        #expect(ValueText.format(12000, unit: .count) == "12000")
        #expect(ValueText.format(.bool(true), unit: .none) == "On")
        #expect(ValueText.format(.plane(.yz), unit: .none) == "YZ")
        #expect(ValueText.format(nil, unit: .millimetres) == "—")
        #expect(ValueText.format(.edgePicks([]), unit: .none) == "0 picks")
    }

    @Test func typedNumbersMayCarryTheirUnit() {
        #expect(ValueText.parse("12.5") == 12.5)
        #expect(ValueText.parse(" 12.5 mm ") == 12.5)
        #expect(ValueText.parse("45°") == 45)
        #expect(ValueText.parse("-3") == -3)
        #expect(ValueText.parse("abc") == nil)
        #expect(ValueText.parse("12 apples") == nil)
        #expect(ValueText.parse("") == nil)
        #expect(ValueText.parse("1e999") == nil)
    }

    @Test func formattingIgnoresTheCurrentLocale() {
        #expect(ValueText.locale.identifier == "en_US_POSIX")
        #expect(ValueText.format(1234.5, unit: .none) == "1234.5")
        // What the inspector shows, it can read back.
        #expect(ValueText.parse(ValueText.format(0.25, unit: .millimetres)) == 0.25)
        #expect(StatusBadge.text(for: .ok(duration: .milliseconds(1500))) == "1500 ms")
    }

    @Test func wholeNumbersRoundAndRefuseWhatNoIntHolds() {
        #expect(ValueText.wholeNumber(4.4) == 4)
        #expect(ValueText.wholeNumber(-2.5) == -3)
        #expect(ValueText.wholeNumber(1e300) == nil)
        #expect(ValueText.wholeNumber(-1e300) == nil)
        #expect(ValueText.wholeNumber(.nan) == nil)
    }

    @Test func statusBadges() {
        #expect(StatusBadge.text(for: .ok(duration: .milliseconds(12))) == "12 ms")
        #expect(StatusBadge.text(for: .ok(duration: .microseconds(300))) == "<1 ms")
        #expect(StatusBadge.text(for: .evaluating) == "◌")
        #expect(StatusBadge.text(for: .warning("matched 6 edges, expected 4")) == "⚠")
        #expect(StatusBadge.text(for: .error("Boom")) == "✕")
        #expect(StatusBadge.text(for: .idle(nil)) == "")
        #expect(StatusBadge.text(for: nil) == "")
        #expect(StatusBadge.message(for: .warning("matched 6 edges, expected 4")) == "matched 6 edges, expected 4")
        #expect(StatusBadge.message(for: .idle("Connect or set “profile”.")) == "Connect or set “profile”.")
        #expect(StatusBadge.message(for: .ok(duration: .zero)) == nil)
    }

    @Test func labelsComeFromSocketNames() {
        #expect(InspectorLabel.text(for: "cornerRadius") == "Corner radius")
        #expect(InspectorLabel.text(for: "width") == "Width")
        #expect(InspectorLabel.text(for: "holeCountX") == "Hole count x")
    }

    @Test func planeChoicesMatchOrientationNotOrigin() {
        #expect(PlaneChoice(Plane.xz.offset(by: 5)) == .xz)
        #expect(PlaneChoice(Plane(origin: .zero, normal: .unitZ, xAxis: .unitY)) == nil)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: "cannot find 'ValueText' in scope", "cannot find 'StatusBadge' in scope", "cannot find 'InspectorLabel' in scope", "cannot find 'PlaneChoice' in scope".

- [ ] **Step 3: Implement**

`Sources/CreatorEditor/PlaneChoice.swift`:
```swift
import CreatorGeometry

/// The inspector's plane picker choices (spec §7.1: XY, XZ or YZ).
public enum PlaneChoice: String, CaseIterable, Sendable {
    case xy = "XY", xz = "XZ", yz = "YZ"

    public var plane: Plane {
        switch self {
        case .xy: .xy
        case .xz: .xz
        case .yz: .yz
        }
    }

    /// The choice whose orientation matches `plane` (its origin may be offset), if any.
    public init?(_ plane: Plane) {
        guard let match = Self.allCases.first(where: { $0.plane.normal == plane.normal && $0.plane.xAxis == plane.xAxis }) else {
            return nil
        }
        self = match
    }
}
```

`Sources/CreatorEditor/ValueText.swift`:
```swift
import CreatorGraph
import Foundation

/// How numbers are shown and typed in node rows and the inspector.
public enum ValueText {
    /// One fixed locale for showing numbers, so a machine set to "0,25" still shows "0.25",
    /// which `parse` reads back. Localised entry is deferred with string localisation.
    public static let locale = Locale(identifier: "en_US_POSIX")

    /// "60 mm", "45°", "3", "0.25": up to three decimals, with the unit.
    public static func format(_ value: Double, unit: ValueUnit) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(locale))
        switch unit {
        case .millimetres: return "\(number) mm"
        case .degrees: return "\(number)°"
        case .count, .none: return number
        }
    }

    /// The constant shown on an unwired input's row. Covers every kind M3 ships, including the
    /// `.edgePicks` setting ("2 picks"). Written with `if case`, so a kind added after M3 still
    /// compiles and shows "—".
    public static func format(_ value: ConstantValue?, unit: ValueUnit) -> String {
        if case .number(let number)? = value { return format(number, unit: unit) }
        if case .integer(let integer)? = value { return format(Double(integer), unit: unit) }
        if case .bool(let flag)? = value { return flag ? "On" : "Off" }
        if case .vector(let v)? = value { return "\(format(v.x, unit: unit)), \(format(v.y, unit: unit)), \(format(v.z, unit: unit))" }
        if case .plane(let plane)? = value { return PlaneChoice(plane)?.rawValue ?? "Custom plane" }
        if case .text(let text)? = value { return text }
        if case .edgePicks(let picks)? = value { return picks.count == 1 ? "1 pick" : "\(picks.count) picks" }
        return "—"
    }

    /// A typed number, ignoring spaces and a trailing unit ("12.5 mm", "45°"); `nil` if it isn't one.
    public static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let number = trimmed.prefix { "0123456789.-+eE".contains($0) }
        guard !number.isEmpty, let value = Double(String(number)), value.isFinite else { return nil }
        let rest = trimmed.dropFirst(number.count).trimmingCharacters(in: .whitespaces)
        return ["", "mm", "°", "deg"].contains(rest) ? value : nil
    }

    /// A typed number as a whole number, rounded; `nil` when no `Int` holds it ("1e300").
    /// `Int(_:)` would trap there, so this uses `Int(exactly:)`.
    public static func wholeNumber(_ value: Double) -> Int? {
        Int(exactly: value.rounded())
    }
}
```

`Sources/CreatorEditor/StatusBadge.swift`:
```swift
import CreatorGraph
import Foundation

/// The text of a node's status badge (spec §6.2): a spinner, the time in ms, ⚠ or ✕.
public enum StatusBadge {
    public static func text(for state: NodeState?) -> String {
        switch state {
        case .evaluating?: "◌"
        case .ok(let duration)?: milliseconds(duration)
        case .warning?: "⚠"
        case .error?: "✕"
        case .idle?, nil: ""
        }
    }

    /// The message a badge's tooltip shows, if any.
    public static func message(for state: NodeState?) -> String? {
        switch state {
        case .warning(let message)?, .error(let message)?: message
        case .idle(let reason?)?: reason
        default: nil
        }
    }

    static func milliseconds(_ duration: Duration) -> String {
        let ms = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        if ms < 1 { return "<1 ms" }
        return "\(ms.formatted(.number.precision(.fractionLength(0)).grouping(.never).locale(ValueText.locale))) ms"
    }
}
```

`Sources/CreatorEditor/InspectorLabel.swift`:
```swift
import CreatorGraph

/// Readable labels from socket names: "cornerRadius" → "Corner radius".
public enum InspectorLabel {
    public static func text(for socket: SocketName) -> String {
        var words: [String] = []
        var current = ""
        for character in socket.rawValue {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        let sentence = words.map { $0.lowercased() }.joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --filter CreatorEditorTests`
Expected: PASS — `Test run with 87 tests in 13 suites passed`.

- [ ] **Step 5: Commit**

```bash
swiftlint lint --strict   # must report 0 violations before committing (CLAUDE.md "Linting")
git add Sources/CreatorEditor Tests/CreatorEditorTests
git commit -m "feat(editor): value text, status badges, socket labels and plane choices"
```

---

### Task 8: Inspector data — rows bound to unwired inputs, parameters, drag coalescing

**Files:**
- Create: `Sources/CreatorEditor/InputField.swift`, `InspectorRow.swift`, `InspectorHeader.swift`, `InspectorSectionRows.swift`, `ParameterRow.swift`, `InspectorPage.swift`, `InspectorControl+Socket.swift`, `InspectorBuilder.swift`, `EditorModel+Inspector.swift`
- Test: `Tests/CreatorEditorTests/InspectorTests.swift`, `Tests/CreatorEditorTests/CoalescingTests.swift`

**Interfaces:**
- Consumes: `InspectorControl` with M3's `.vector` and `.parameterPicker` (merged; Task 1's pre-flight checks them), `SocketSpec.isOptional`, M3's `NodeSetting` and `ConstantValue.parameter(_:)` / `.parameterID` (all `CreatorGraph`), `InspectorSection`, `SocketSpec` (`range`, `unit`, `defaultValue`), `NodeResult.outputs`, `Value.items`, `Scalar.edgeSet`, `EdgeSet.edges`, `Graph.incomingLink(to:)`, `GraphParameter`, and Task 7 (`ValueText.wholeNumber`).
- Produces:
  - `public struct InputField: Equatable { node; socket; label; type: SocketType?; unit; value: ConstantValue?; isOptional: Bool (init default false); var number: Double? }`. `isOptional` comes from `SocketSpec.isOptional` (M3's Grid Points `total`, Edge Filter `maxLength`, Transform `axisDirection`).
  - `public enum InspectorRow: Equatable { slider(InputField, range:), number, integer, toggle(InputField, label:), segmented(InputField, options:, selected:), planePicker(InputField, selected:), vector(InputField), anchorGrid(InputField, selected:), ruleSummary(label:summary:), parameterPicker(InputField, options: [GraphParameter], selected: ParameterID?), button(title:action:), wired(label:source:), readOnly(label:text:) }`. An `InputField` may name a setting rather than a socket; its `type` is then `nil` (or `.bool` for a toggle).
  - `InspectorHeader { node; title; category; state }`, `InspectorSectionRows { title; rows }`, `ParameterRow { parameter; range }`, `InspectorPage { header?; sections; parameters }`
  - `InspectorControl.socket: SocketName?` (an exhaustive `switch`; `nil` only for `.button`)
  - `public enum InspectorBuilder { page(graph:selection:registry:results:); segmentValue(_:options:type:); vectorValue(_:axis:to:) }`. The parameter setting is encoded only by M3's `ConstantValue.parameter(_:)` and decoded by `.parameterID`; the builder has no encoder of its own. Internal helpers: `segmentIndex`, `sliderRange`, `parameterRange`, `edgeCount`, `edgesText`, `fallbackSections`, `row(for:…)`.
  - `EditorModel.inspectorPage`, `setInput(_ field: InputField, to: ConstantValue, continuous: Bool = false)`, `setNumber(_ field: InputField, to: Double, continuous:)` (integer sockets get a whole number, or a refusal), `setVectorComponent(_:axis:to:)`, `clearInput(_:)` (unsets an optional input as one undo step; no-op for a required one or one already unset), `chooseParameter(_: ParameterID, for: InputField)`, `setParameter(_: ParameterID, to:continuous:)`, `setParameterNumber(_:to:continuous:)`, `press(_ action: InspectorAction, on: NodeID)`.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorEditorTests/InspectorTests.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

@MainActor
struct InspectorTests {
    let rect = testNode(RectangleTestNode.self, id: 1, at: .zero, values: ["width": .number(60)])
    let extrude = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
    let number = testNode(NumberTestNode.self, id: 3, at: Vector2(0, 300))
    let parameter = GraphParameter(name: "Width", type: .number, value: .number(60), min: 10, max: 200)

    @Test func nothingSelectedShowsOnlyTheDocumentParameters() {
        let editor = makeEditor([rect], parameters: [parameter])
        let page = editor.inspectorPage
        #expect(page.header == nil)
        #expect(page.sections.isEmpty)
        #expect(page.parameters == [ParameterRow(parameter: parameter, range: 10...200)])
    }

    @Test func severalSelectedShowsOnlyTheDocumentParameters() {
        let editor = makeEditor([rect, extrude], parameters: [parameter])
        editor.selection = [rect.id, extrude.id]
        #expect(editor.inspectorPage.header == nil)
        #expect(editor.inspectorPage.parameters.count == 1)
    }

    @Test func unwiredControlsBindToTheStoredValueOrTheDefault() {
        let editor = makeEditor([rect], parameters: [parameter])
        editor.selection = [rect.id]
        let page = editor.inspectorPage
        #expect(page.header == InspectorHeader(node: rect.id, title: "Rectangle", category: .profile, state: nil))
        #expect(page.sections.map(\.title) == ["Size", "Placement"])
        let width = InputField(node: rect.id, socket: "width", label: "Width", type: .number, unit: .millimetres, value: .number(60))
        let height = InputField(node: rect.id, socket: "height", label: "Height", type: .number, unit: .millimetres, value: .number(10))
        #expect(page.sections[0].rows == [.slider(width, range: 0...100), .slider(height, range: 0...100)])
        let plane = InputField(node: rect.id, socket: "plane", label: "Plane", type: .plane, unit: .none, value: .plane(.xy))
        let anchor = InputField(node: rect.id, socket: "anchor", label: "Anchor", type: .integer, unit: .none, value: .integer(4))
        #expect(page.sections[1].rows == [.planePicker(plane, selected: .xy), .anchorGrid(anchor, selected: 4)])
        #expect(page.parameters.count == 1)
    }

    @Test func aWiredInputShowsWhereItIsWiredFrom() {
        var source = number
        source.name = "Edges ∥ Z"
        let editor = makeEditor([source, rect], [wire(source, "value", rect, "width")])
        editor.selection = [rect.id]
        #expect(editor.inspectorPage.sections[0].rows.first == .wired(label: "Width", source: "wired from Edges ∥ Z"))
    }

    @Test func sliderRangesComeFromTheSocketAndWidenToTheValue() {
        let editor = makeEditor([testNode(ExtrudeTestNode.self, id: 4, at: .zero, values: ["distance": .number(250)])])
        editor.selection = [nodeID(4)]
        guard case .slider(_, let range)? = editor.inspectorPage.sections[0].rows.dropFirst().first else {
            Issue.record("no slider"); return
        }
        #expect(range == 0...250)
    }

    /// M3's Extrude "Reverse direction" is a toggle on a bool *socket* (spec Errata (M3)), unlike
    /// Fillet's `showHandle` setting: it reads the socket default and writes a stored `.bool`.
    @Test func aSocketToggleReadsItsDefaultAndWritesABool() {
        let editor = makeEditor([extrude])
        editor.selection = [extrude.id]
        guard case .toggle(let field, let label)? = editor.inspectorPage.sections[0].rows.last else {
            Issue.record("no toggle"); return
        }
        #expect(label == "Reverse direction")
        #expect(field.socket == "reversed" && field.type == .bool && field.value == .bool(false) && !field.isOptional)
        editor.setInput(field, to: .bool(true))
        #expect(editor.graph.nodes[extrude.id]?.inputValues["reversed"] == .bool(true))
    }

    /// M3's Grid Points `total` (also Edge Filter `maxLength`, Transform `axisDirection`) is an
    /// optional input with no default: it starts unset, can be set, and can be cleared again.
    @Test func anOptionalInputStartsUnsetAndCanBeCleared() throws {
        let grid = testNode(GridPointsTestNode.self, id: 8, at: .zero)
        let editor = makeEditor([grid], registry: inspectorTestRegistry)
        editor.selection = [grid.id]
        func totalField() -> InputField? {
            guard case .integer(let field)? = editor.inspectorPage.sections.first?.rows.last else { return nil }
            return field
        }
        let unset = try #require(totalField())
        #expect(unset.socket == "total" && unset.isOptional && unset.value == nil)
        editor.clearInput(unset)
        #expect(!editor.document.canUndo)
        editor.setNumber(unset, to: 6)
        #expect(editor.graph.nodes[grid.id]?.inputValues["total"] == .integer(6))
        editor.clearInput(try #require(totalField()))
        #expect(editor.graph.nodes[grid.id]?.inputValues["total"] == nil)
        editor.document.undo()
        #expect(editor.graph.nodes[grid.id]?.inputValues["total"] == .integer(6))
        // A required input is never cleared: it would only fall back to its default silently.
        guard case .integer(let countX)? = editor.inspectorPage.sections.first?.rows.first else {
            Issue.record("no countX row"); return
        }
        #expect(!countX.isOptional)
        editor.setNumber(countX, to: 3)
        editor.clearInput(countX)
        #expect(editor.graph.nodes[grid.id]?.inputValues["countX"] == .integer(3))
    }

    @Test func segmentedControlsReadAndWriteTheSocketsOwnType() {
        let editor = makeEditor([testNode(ExtrudeTestNode.self, id: 4, at: .zero, values: ["mode": .integer(1)])])
        editor.selection = [nodeID(4)]
        guard case .segmented(_, let options, let selected)? = editor.inspectorPage.sections[0].rows.first else {
            Issue.record("no segmented control"); return
        }
        #expect(options == ["Distance", "Symmetric"])
        #expect(selected == 1)
        #expect(InspectorBuilder.segmentValue(0, options: options, type: .integer) == .integer(0))
        #expect(InspectorBuilder.segmentValue(1, options: ["Off", "On"], type: .bool) == .bool(true))
        #expect(InspectorBuilder.segmentValue(1, options: ["A", "B"], type: nil) == .text("B"))
        #expect(InspectorBuilder.segmentValue(2, options: options, type: .integer) == nil)
        #expect(InspectorBuilder.segmentIndex(.text("B"), options: ["A", "B"]) == 1)
        #expect(InspectorBuilder.segmentIndex(.bool(false), options: ["Off", "On"]) == 0)
    }

    @Test func ruleSummaryCountsTheEdgesItsRuleMatched() async {
        let profile = testNode(RectangleTestNode.self, id: 1, at: .zero)
        let solid = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
        let edges = testNode(AllEdgesTestNode.self, id: 3, at: Vector2(600, 0))
        var fillet = testNode(FilletTestNode.self, id: 4, at: Vector2(900, 0))
        fillet.isOutput = true
        let editor = makeEditor([profile, solid, edges, fillet], [
            wire(profile, "profile", solid, "profile"), wire(solid, "solid", edges, "solid"),
            wire(solid, "solid", fillet, "solid"), wire(edges, "edges", fillet, "edges"),
        ])
        await editor.document.waitForEvaluation()
        editor.selection = [fillet.id]
        let page = editor.inspectorPage
        #expect(page.sections.map(\.title) == ["Fillet", "Edges"])
        #expect(page.sections[1].rows == [
            .ruleSummary(label: "Edges", summary: "All Edges · 12 edges"),
            .button(title: "Pick edges in view…", action: .pickEdgesInView),
        ])
        guard case .toggle(_, let label)? = page.sections[0].rows.last else { Issue.record("no toggle"); return }
        #expect(label == "Show handle in view")
    }

    @Test func anUnconnectedRuleSaysSo() {
        let editor = makeEditor([testNode(FilletTestNode.self, id: 4, at: .zero)])
        editor.selection = [nodeID(4)]
        #expect(editor.inspectorPage.sections[1].rows.first == .ruleSummary(label: "Edges", summary: "No rule connected"))
    }

    /// M3's selection-rule nodes put `ruleSummary("edges")` on their own *output*.
    @Test func aRuleNodeSummarisesItsOwnOutput() async {
        let profile = testNode(RectangleTestNode.self, id: 1, at: .zero)
        let solid = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
        var edges = testNode(AllEdgesTestNode.self, id: 3, at: Vector2(600, 0))
        edges.isOutput = true
        let editor = makeEditor([profile, solid, edges],
                                [wire(profile, "profile", solid, "profile"), wire(solid, "solid", edges, "solid")])
        editor.selection = [edges.id]
        let unevaluated = InspectorSectionRows(title: "Edges", rows: [.ruleSummary(label: "Edges", summary: "No result yet")])
        #expect(editor.inspectorPage.sections == [unevaluated])
        await editor.document.waitForEvaluation()
        #expect(editor.inspectorPage.sections[0].rows == [.ruleSummary(label: "Edges", summary: "12 edges")])
    }

    /// M3's `showHandle` is a setting, not a socket. `makeNode` seeds it `.bool(true)` through
    /// `defaultSettings`; a node without it (a hand-edited file) still reads On.
    @Test func aSettingToggleReadsOnWhenAbsent() {
        let fillet = testNode(FilletTestNode.self, id: 4, at: .zero)
        #expect(fillet.inputValues[NodeSetting.showHandle] == .bool(true))
        var bare = testNode(FilletTestNode.self, id: 5, at: Vector2(0, 300))
        bare.inputValues[NodeSetting.showHandle] = nil
        let editor = makeEditor([fillet, bare])
        editor.selection = [fillet.id]
        guard case .toggle(let field, let label)? = editor.inspectorPage.sections[0].rows.last else {
            Issue.record("no toggle"); return
        }
        #expect(label == "Show handle in view")
        #expect(field.socket == NodeSetting.showHandle && field.type == .bool && field.value == .bool(true))
        editor.setInput(field, to: .bool(false))
        #expect(editor.graph.nodes[fillet.id]?.inputValues[NodeSetting.showHandle] == .bool(false))
        editor.document.undo()
        #expect(editor.graph.nodes[fillet.id]?.inputValues[NodeSetting.showHandle] == .bool(true))
        editor.selection = [bare.id]
        guard case .toggle(let bareField, _)? = editor.inspectorPage.sections[0].rows.last else {
            Issue.record("no toggle"); return
        }
        #expect(bareField.value == .bool(true))
    }

    @Test func aVectorControlEditsOneComponent() {
        let transform = testNode(TransformTestNode.self, id: 5, at: .zero)
        let editor = makeEditor([transform], registry: inspectorTestRegistry)
        editor.selection = [transform.id]
        let field = InputField(node: transform.id, socket: "move", label: "Move", type: .vector, unit: .millimetres,
                               value: .vector(.zero))
        #expect(editor.inspectorPage.sections == [InspectorSectionRows(title: "Move", rows: [.vector(field)])])
        editor.setVectorComponent(field, axis: 1, to: 5)
        #expect(editor.graph.nodes[transform.id]?.inputValues["move"] == .vector(Vector3(0, 5, 0)))
        #expect(InspectorBuilder.vectorValue(.vector(Vector3(1, 2, 3)), axis: 2, to: 9) == .vector(Vector3(1, 2, 9)))
        #expect(InspectorBuilder.vectorValue(nil, axis: 3, to: 9) == nil)
    }

    /// M3's Graph Parameter stores `ConstantValue.parameter(id)` under `NodeSetting.parameter`.
    @Test func aParameterPickerListsTheDocumentParametersAndWritesTheID() {
        let count = GraphParameter(name: "Hole count", type: .integer, value: .integer(4))
        let node = testNode(GraphParameterTestNode.self, id: 6, at: .zero)
        let editor = makeEditor([node], parameters: [parameter, count], registry: inspectorTestRegistry)
        editor.selection = [node.id]
        guard case .parameterPicker(let field, let options, let selected)? = editor.inspectorPage.sections.first?.rows.first else {
            Issue.record("no parameter picker"); return
        }
        #expect(field.socket == NodeSetting.parameter && field.type == nil && field.value == nil)
        #expect(options.map(\.name) == ["Width", "Hole count"])
        #expect(selected == nil)
        editor.chooseParameter(count.id, for: field)
        #expect(editor.graph.nodes[node.id]?.inputValues[NodeSetting.parameter] == .parameter(count.id))
        guard case .parameterPicker(_, _, let chosen)? = editor.inspectorPage.sections.first?.rows.first else {
            Issue.record("no parameter picker"); return
        }
        #expect(chosen == count.id)
        #expect(editor.graph.nodes[node.id]?.inputValues[NodeSetting.parameter]?.parameterID == count.id)
    }

    @Test func aDefinitionWithoutAnInspectorGetsOneRowPerSimpleInput() {
        let editor = makeEditor([number])
        editor.selection = [number.id]
        let field = InputField(node: number.id, socket: "value", label: "Value", type: .number, unit: .millimetres, value: .number(5))
        #expect(editor.inspectorPage.sections == [InspectorSectionRows(title: "Inputs", rows: [.slider(field, range: 0...50)])])
    }

    @Test func aMissingNodeSaysItsTypeIsUnavailable() {
        let missing = Node(id: nodeID(7), typeID: "plugin.gone", name: "Gone")
        let editor = makeEditor([missing])
        editor.selection = [missing.id]
        let note = InspectorSectionRows(title: "Missing node",
                                        rows: [.readOnly(label: "Type", text: "“plugin.gone” isn't available")])
        #expect(editor.inspectorPage.sections == [note])
    }

    @Test func pressingAnInspectorButtonRecordsARequestForTheViewport() {
        let editor = makeEditor([testNode(FilletTestNode.self, id: 4, at: .zero)])
        editor.press(.pickEdgesInView, on: nodeID(4))
        editor.press(.pickEdgesInView, on: nodeID(4))
        #expect(editor.inspectorRequest == InspectorRequest(node: nodeID(4), action: .pickEdgesInView, serial: 2))
    }
}
```

`Tests/CreatorEditorTests/CoalescingTests.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

@MainActor
struct CoalescingTests {
    let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
    let other = testNode(RectangleTestNode.self, id: 2, at: Vector2(0, 300))

    func widthField(_ editor: EditorModel, _ node: NodeID) -> InputField? {
        editor.selection = [node]
        guard case .slider(let field, _)? = editor.inspectorPage.sections.first?.rows.first else { return nil }
        return field
    }

    @Test func aSliderDragIsOneUndoStep() throws {
        let editor = makeEditor([rect])
        let field = try #require(widthField(editor, rect.id))
        for value in [11.0, 12, 13, 14] { editor.setInput(field, to: .number(value), continuous: true) }
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == .number(14))
        editor.document.undo()
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == nil)
        #expect(!editor.document.canUndo)
    }

    @Test func changingTheSelectionEndsTheDrag() throws {
        let editor = makeEditor([rect, other])
        let field = try #require(widthField(editor, rect.id))
        editor.setInput(field, to: .number(11), continuous: true)
        editor.selection = [other.id]
        editor.selection = [rect.id]
        editor.setInput(field, to: .number(12), continuous: true)
        editor.document.undo()
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == .number(11))
    }

    @Test func pressingTheCanvasEndsTheDrag() throws {
        let editor = makeEditor([rect])
        let field = try #require(widthField(editor, rect.id))
        editor.setInput(field, to: .number(11), continuous: true)
        editor.click(Vector2(900, 900))
        editor.selection = [rect.id]
        editor.setInput(field, to: .number(12), continuous: true)
        editor.document.undo()
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == .number(11))
    }

    @Test func typedValuesAreEachTheirOwnStep() throws {
        let editor = makeEditor([rect])
        let field = try #require(widthField(editor, rect.id))
        editor.setInput(field, to: .number(11))
        editor.setInput(field, to: .number(12))
        editor.document.undo()
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == .number(11))
    }

    @Test func settingTheSameValueRecordsNothing() throws {
        let editor = makeEditor([rect])
        let field = try #require(widthField(editor, rect.id))
        editor.setInput(field, to: .number(10))
        #expect(!editor.document.canUndo)
    }

    @Test func aNonFiniteValueIsRefusedWithAMessage() throws {
        let editor = makeEditor([rect])
        let field = try #require(widthField(editor, rect.id))
        editor.setInput(field, to: .number(.infinity))
        #expect(editor.refusal?.message == "Enter a finite number.")
        #expect(editor.graph.nodes[rect.id]?.inputValues["width"] == nil)
    }

    @Test func aParameterDragIsOneUndoStep() {
        let width = GraphParameter(name: "Width", type: .number, value: .number(60))
        let editor = makeEditor([], parameters: [width])
        for value in [61.0, 70, 90] { editor.setParameter(width.id, to: .number(value), continuous: true) }
        #expect(editor.graph.parameters.first?.value == .number(90))
        editor.document.undo()
        #expect(editor.graph.parameters.first?.value == .number(60))
        #expect(!editor.document.canUndo)
    }

    @Test func aParameterOfTheWrongTypeIsRefused() {
        let count = GraphParameter(name: "Hole count", type: .integer, value: .integer(4))
        let editor = makeEditor([], parameters: [count])
        editor.setParameter(count.id, to: .number(4.5))
        #expect(editor.refusal != nil)
        #expect(editor.graph.parameters.first?.value == .integer(4))
    }

    @Test func aHugeWholeNumberIsRefusedNotTrapped() {
        let editor = makeEditor([rect])
        editor.selection = [rect.id]
        guard case .anchorGrid(let anchor, _)? = editor.inspectorPage.sections.last?.rows.last else {
            Issue.record("no anchor grid"); return
        }
        editor.setNumber(anchor, to: 1e300)
        #expect(editor.refusal?.message == "Enter a whole number.")
        #expect(editor.graph.nodes[rect.id]?.inputValues["anchor"] == nil)
        editor.setNumber(anchor, to: 2.4)
        #expect(editor.graph.nodes[rect.id]?.inputValues["anchor"] == .integer(2))
    }

    @Test func aWholeNumberParameterRoundsAndRefusesHugeValues() {
        let count = GraphParameter(name: "Hole count", type: .integer, value: .integer(4))
        let editor = makeEditor([], parameters: [count])
        editor.setParameterNumber(count.id, to: 6.4)
        #expect(editor.graph.parameters.first?.value == .integer(6))
        editor.setParameterNumber(count.id, to: -1e300)
        #expect(editor.refusal?.message == "Enter a whole number.")
        #expect(editor.graph.parameters.first?.value == .integer(6))
    }
}
```

`aParameterOfTheWrongTypeIsRefused` checks only that a refusal happened. M1's text reads "needs a integer" (`Graph+Commands.swift`, and the same `needs a \(type.rawValue)` shape in `NodeError` and `Evaluator`, which gives "a edgeSet"). Task 11 logs it in the carry-over note for a pass over CreatorGraph's messages.

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: "value of type 'EditorModel' has no member 'inspectorPage'", "cannot find 'InputField' in scope", "cannot find 'InspectorBuilder' in scope".

- [ ] **Step 3: Implement the data types**

`Sources/CreatorEditor/InputField.swift`:
```swift
import CreatorGraph
import CreatorKernel

/// An unwired input (or a node setting) the inspector edits: which node and socket, how to label
/// and show it, and its current constant (the stored value, else the socket's default). A setting
/// is a name that isn't an input socket (M3's `NodeSetting`); its `type` is `nil`, or `.bool` for
/// a toggle.
public struct InputField: Equatable, Sendable {
    public var node: NodeID
    public var socket: SocketName
    public var label: String
    public var type: SocketType?
    public var unit: ValueUnit
    public var value: ConstantValue?
    /// An optional input socket (`SocketSpec.isOptional`, such as M3's Grid Points `total`). With no
    /// default it starts unset (`value == nil`), and the inspector can clear it again.
    public var isOptional: Bool

    public init(node: NodeID, socket: SocketName, label: String, type: SocketType?, unit: ValueUnit,
                value: ConstantValue?, isOptional: Bool = false) {
        self.node = node
        self.socket = socket
        self.label = label
        self.type = type
        self.unit = unit
        self.value = value
        self.isOptional = isOptional
    }

    /// The value as a number, for sliders and number fields.
    public var number: Double? {
        switch value {
        case .number(let number)?: number
        case .integer(let integer)?: Double(integer)
        default: nil
        }
    }

    /// The value's x, y and z, for the three fields of a vector row; zeros when it isn't a vector.
    public var vectorComponents: [Double] {
        if case .vector(let vector)? = value { [vector.x, vector.y, vector.z] } else { [0, 0, 0] }
    }
}
```

`Sources/CreatorEditor/InspectorRow.swift`:
```swift
import CreatorGraph

/// One rendered inspector row, built from a node's `InspectorControl` data (spec §6.4).
public enum InspectorRow: Equatable, Sendable {
    case slider(InputField, range: ClosedRange<Double>)
    case number(InputField)
    case integer(InputField)
    case toggle(InputField, label: String)
    /// `selected` is the index of the current option, if it matches one.
    case segmented(InputField, options: [String], selected: Int?)
    case planePicker(InputField, selected: PlaneChoice?)
    /// Three number fields (x, y, z) for a vector socket.
    case vector(InputField)
    /// A 3×3 anchor grid; `selected` is 0…8, row-major from the top-left (4 is the centre).
    case anchorGrid(InputField, selected: Int?)
    case ruleSummary(label: String, summary: String)
    /// A menu of the document's parameters for a setting (M3's Graph Parameter). `selected` is
    /// the parameter the setting names, if it still exists.
    case parameterPicker(InputField, options: [GraphParameter], selected: ParameterID?)
    case button(title: String, action: InspectorAction)
    /// A wired input: read-only text such as "wired from Edges ∥ Z".
    case wired(label: String, source: String)
    /// A value shown without an editor, such as a missing node's type.
    case readOnly(label: String, text: String)
}
```

`Sources/CreatorEditor/InspectorHeader.swift`:
```swift
import CreatorGraph
import CreatorKernel

/// The inspector's header bar for the selected node: its name, category colour and status.
public struct InspectorHeader: Equatable, Sendable {
    public var node: NodeID
    public var title: String
    public var category: NodeCategory
    public var state: NodeState?
}
```

`Sources/CreatorEditor/InspectorSectionRows.swift`:
```swift
/// A titled group of rendered rows.
public struct InspectorSectionRows: Equatable, Sendable {
    public var title: String
    public var rows: [InspectorRow]
}
```

`Sources/CreatorEditor/ParameterRow.swift`:
```swift
import CreatorGraph

/// One document parameter in the inspector, with its slider range.
public struct ParameterRow: Equatable, Sendable, Identifiable {
    public var parameter: GraphParameter
    public var range: ClosedRange<Double>

    public var id: ParameterID { parameter.id }
}
```

`Sources/CreatorEditor/InspectorPage.swift`:
```swift
/// Everything the context inspector shows: the selected node's header and sections (when
/// exactly one node is selected), then the document parameters, which are always listed.
public struct InspectorPage: Equatable, Sendable {
    public var header: InspectorHeader?
    public var sections: [InspectorSectionRows]
    public var parameters: [ParameterRow]
}
```

`Sources/CreatorEditor/InspectorControl+Socket.swift`:
```swift
import CreatorGraph

extension InspectorControl {
    /// The input socket (or setting) this control edits, or `nil` for a button. Exhaustive, so a
    /// control kind added later fails to compile here instead of drawing nothing.
    public var socket: SocketName? {
        switch self {
        case .slider(let socket), .number(let socket), .integer(let socket), .planePicker(let socket),
             .vector(let socket), .anchorGrid(let socket), .ruleSummary(let socket), .parameterPicker(let socket):
            socket
        case .toggle(let socket, _), .segmented(let socket, _):
            socket
        case .button:
            nil
        }
    }
}
```

- [ ] **Step 4: Implement the builder and the model's editing**

`Sources/CreatorEditor/InspectorBuilder.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

/// Turns a node definition's inspector data into rows bound to the node's unwired inputs
/// (spec §6.4). Pure: tests check wired versus unwired binding without any UI.
public enum InspectorBuilder {
    public static func page(graph: Graph, selection: Set<NodeID>, registry: NodeRegistry,
                            results: [NodeID: NodeResult]) -> InspectorPage {
        let parameters = graph.parameters.map { ParameterRow(parameter: $0, range: parameterRange($0)) }
        guard selection.count == 1, let id = selection.first, let node = graph.nodes[id] else {
            return InspectorPage(header: nil, sections: [], parameters: parameters)
        }
        guard let definition = registry[node.typeID] else {
            let header = InspectorHeader(node: id, title: node.name, category: .value, state: results[id]?.state)
            let note = InspectorSectionRows(title: "Missing node",
                                            rows: [.readOnly(label: "Type", text: "“\(node.typeID)” isn't available")])
            return InspectorPage(header: header, sections: [note], parameters: parameters)
        }
        let header = InspectorHeader(node: id, title: node.name, category: definition.category, state: results[id]?.state)
        let declared = definition.inspector.isEmpty ? fallbackSections(definition.inputs) : definition.inspector
        let sections = declared.map { section in
            InspectorSectionRows(title: section.title, rows: section.controls.map {
                row(for: $0, node: node, inputs: definition.inputs, outputs: definition.outputs, graph: graph,
                    results: results)
            })
        }
        return InspectorPage(header: header, sections: sections, parameters: parameters)
    }

    /// A definition that declares no inspector gets one row per number, integer, bool or vector input.
    static func fallbackSections(_ inputs: [SocketSpec]) -> [InspectorSection] {
        let controls: [InspectorControl] = inputs.compactMap { spec in
            switch spec.type {
            case .number where spec.range == nil: .number(spec.name)
            case .number: .slider(spec.name)
            case .integer: .integer(spec.name)
            case .bool: .toggle(spec.name, label: InspectorLabel.text(for: spec.name))
            case .vector: .vector(spec.name)
            default: nil
            }
        }
        return controls.isEmpty ? [] : [InspectorSection(title: "Inputs", controls: controls)]
    }

    static func row(for control: InspectorControl, node: Node, inputs: [SocketSpec], outputs: [SocketSpec], graph: Graph,
                    results: [NodeID: NodeResult]) -> InspectorRow {
        guard let socket = control.socket else {
            if case .button(let title, let action) = control { return .button(title: title, action: action) }
            return .readOnly(label: "", text: "")
        }
        let label = InspectorLabel.text(for: socket)
        let spec = inputs.first { $0.name == socket }

        if case .ruleSummary = control {
            let ownOutput = spec == nil && outputs.contains { $0.name == socket }
            return .ruleSummary(label: label, summary: ruleSummary(socket, ownOutput: ownOutput, node: node, graph: graph,
                                                                   results: results))
        }
        if let link = graph.incomingLink(to: Endpoint(node: node.id, socket: socket)), let source = graph.nodes[link.from.node] {
            return .wired(label: label, source: "wired from \(source.name)")
        }

        // A name that isn't an input socket is a setting (M3's `NodeSetting`). `makeNode` seeds
        // settings from `defaultSettings`; a toggle with none stored (a hand-edited file) reads On.
        var value = node.inputValues[socket] ?? spec?.defaultValue
        var type = spec?.type
        if spec == nil, case .toggle = control {
            type = .bool
            if value == nil { value = .bool(true) }
        }
        let field = InputField(node: node.id, socket: socket, label: label, type: type, unit: spec?.unit ?? .none,
                               value: value, isOptional: spec?.isOptional ?? false)
        return valueRow(for: control, field: field, spec: spec, graph: graph)
    }

    /// The summary text of a `.ruleSummary` row. With `ownOutput` (M3's selection rules), it counts
    /// the node's own result; otherwise the rule wired into the input.
    static func ruleSummary(_ socket: SocketName, ownOutput: Bool, node: Node, graph: Graph,
                            results: [NodeID: NodeResult]) -> String {
        if ownOutput {
            guard let count = edgeCount(results[node.id]?.outputs?[socket]) else { return "No result yet" }
            return edgesText(count)
        }
        guard let link = graph.incomingLink(to: Endpoint(node: node.id, socket: socket)),
              let source = graph.nodes[link.from.node] else {
            return "No rule connected"
        }
        guard let count = edgeCount(results[source.id]?.outputs?[link.from.socket]) else { return source.name }
        return "\(source.name) · \(edgesText(count))"
    }

    /// The row for a control bound to an unwired input or a setting.
    static func valueRow(for control: InspectorControl, field: InputField, spec: SocketSpec?, graph: Graph) -> InspectorRow {
        if case .slider = control { return .slider(field, range: sliderRange(spec: spec, value: field.number)) }
        if case .number = control { return .number(field) }
        if case .integer = control { return .integer(field) }
        if case .toggle(_, let title) = control { return .toggle(field, label: title) }
        if case .segmented(_, let options) = control {
            return .segmented(field, options: options, selected: segmentIndex(field.value, options: options))
        }
        if case .planePicker = control { return .planePicker(field, selected: planeChoice(field.value)) }
        if case .anchorGrid = control { return .anchorGrid(field, selected: anchorIndex(field.value)) }
        if case .vector = control { return .vector(field) }
        if case .parameterPicker = control {
            let id = field.value?.parameterID
            let selected = graph.parameters.contains { $0.id == id } ? id : nil
            return .parameterPicker(field, options: graph.parameters, selected: selected)
        }
        return .readOnly(label: field.label, text: ValueText.format(field.value, unit: field.unit))
    }

    /// The plane picker's choice for a stored plane, or `nil` when none is stored.
    static func planeChoice(_ value: ConstantValue?) -> PlaneChoice? {
        if case .plane(let plane)? = value { return PlaneChoice(plane) }
        return nil
    }

    /// The anchor grid's cell (0…8, row-major from the top-left), or `nil` for anything else.
    static func anchorIndex(_ value: ConstantValue?) -> Int? {
        if case .integer(let index)? = value, (0...8).contains(index) { return index }
        return nil
    }

    static func edgesText(_ count: Int) -> String { "\(count) \(count == 1 ? "edge" : "edges")" }

    /// `value` with one component (0 x, 1 y, 2 z) replaced; a missing vector counts as zero.
    public static func vectorValue(_ value: ConstantValue?, axis: Int, to number: Double) -> ConstantValue? {
        var vector = Vector3.zero
        if case .vector(let current)? = value { vector = current }
        switch axis {
        case 0: vector.x = number
        case 1: vector.y = number
        case 2: vector.z = number
        default: return nil
        }
        return .vector(vector)
    }

    /// Which option a stored value selects: an integer index, a bool (false, true), or the option's text.
    static func segmentIndex(_ value: ConstantValue?, options: [String]) -> Int? {
        if case .integer(let index)? = value { return options.indices.contains(index) ? index : nil }
        if case .bool(let flag)? = value { return options.count == 2 ? (flag ? 1 : 0) : nil }
        if case .text(let text)? = value { return options.firstIndex(of: text) }
        return nil
    }

    /// The value a segmented control writes for option `index`, in the socket's own type.
    public static func segmentValue(_ index: Int, options: [String], type: SocketType?) -> ConstantValue? {
        guard options.indices.contains(index) else { return nil }
        switch type {
        case .integer?: return .integer(index)
        case .bool?: return .bool(index == 1)
        default: return .text(options[index])
        }
    }

    /// The socket's declared range, else a default for its unit, widened to include the value.
    static func sliderRange(spec: SocketSpec?, value: Double?) -> ClosedRange<Double> {
        let base: ClosedRange<Double>
        if let range = spec?.range {
            base = range
        } else {
            switch spec?.unit ?? .none {
            case .millimetres: base = 0...100
            case .degrees: base = 0...360
            case .count: base = 0...20
            case .none: base = 0...10
            }
        }
        guard let value, value.isFinite else { return base }
        return min(base.lowerBound, value)...max(base.upperBound, value)
    }

    static func parameterRange(_ parameter: GraphParameter) -> ClosedRange<Double> {
        var value = 0.0
        if case .number(let number) = parameter.value { value = number }
        if case .integer(let integer) = parameter.value { value = Double(integer) }
        let lower = min(parameter.min ?? 0, value)
        let upper = max(parameter.max ?? max(100, value * 2), value)
        return lower...max(upper, lower + 1)
    }

    /// The number of edges an edge-set output carries across its items, or `nil` if it isn't one.
    static func edgeCount(_ value: Value?) -> Int? {
        guard let value else { return nil }
        var total = 0
        for item in value.items {
            guard case .edgeSet(let set) = item else { return nil }
            total += set.edges.count
        }
        return total
    }
}
```

`Sources/CreatorEditor/EditorModel+Inspector.swift`:
```swift
import CreatorGraph
import CreatorKernel

extension EditorModel {
    /// What the context inspector shows now.
    public var inspectorPage: InspectorPage {
        InspectorBuilder.page(graph: graph, selection: selection, registry: registry, results: document.results)
    }

    /// Sets an unwired input. `continuous` edits (slider steps) share one coalescing key per
    /// socket, so a whole drag is one undo step; it ends when the selection changes, the canvas
    /// is pressed, another edit is made, or on undo (MetalUI's `Slider` reports no drag end yet).
    public func setInput(_ field: InputField, to value: ConstantValue, continuous: Bool = false) {
        guard value != field.value else { return }
        let key = continuous ? "input-\(field.node.rawValue.uuidString)-\(field.socket.rawValue)" : nil
        do {
            try document.perform(.setInput(field.node, field.socket, value), coalescingKey: key)
        } catch {
            refuse(error.message, node: field.node)
        }
    }

    /// Unsets an optional input (an empty field), so the node treats it as not given, as one undo
    /// step. A required input is left alone: clearing it would silently fall back to its default.
    public func clearInput(_ field: InputField) {
        guard field.isOptional, graph.nodes[field.node]?.inputValues[field.socket] != nil else { return }
        do {
            try document.perform(.setInput(field.node, field.socket, nil))
        } catch {
            refuse(error.message, node: field.node)
        }
    }

    /// A number from a slider or a typed field. Integer sockets get it rounded to a whole number;
    /// one no `Int` holds ("1e300") is refused rather than trapping.
    public func setNumber(_ field: InputField, to number: Double, continuous: Bool = false) {
        guard field.type == .integer else {
            setInput(field, to: .number(number), continuous: continuous)
            return
        }
        guard let whole = ValueText.wholeNumber(number) else {
            refuse("Enter a whole number.", node: field.node)
            return
        }
        setInput(field, to: .integer(whole), continuous: continuous)
    }

    /// One typed component (0 x, 1 y, 2 z) of a vector field.
    public func setVectorComponent(_ field: InputField, axis: Int, to number: Double) {
        guard let value = InspectorBuilder.vectorValue(field.value, axis: axis, to: number) else { return }
        setInput(field, to: value)
    }

    /// A parameter picker's choice, stored in the node's setting in M3's encoding (`CreatorGraph`).
    public func chooseParameter(_ id: ParameterID, for field: InputField) {
        setInput(field, to: .parameter(id))
    }

    /// Sets a document parameter; `continuous` coalesces like `setInput`.
    public func setParameter(_ id: ParameterID, to value: ConstantValue, continuous: Bool = false) {
        let key = continuous ? "parameter-\(id.rawValue.uuidString)" : nil
        do {
            try document.perform(.setParameter(id, value), coalescingKey: key)
        } catch {
            refuse(error.message, node: nil)
        }
    }

    /// A number for a parameter, as a whole number for an integer parameter (refused if no `Int` holds it).
    public func setParameterNumber(_ id: ParameterID, to number: Double, continuous: Bool = false) {
        guard let parameter = graph.parameters.first(where: { $0.id == id }) else { return }
        guard parameter.type == .integer else {
            setParameter(id, to: .number(number), continuous: continuous)
            return
        }
        guard let whole = ValueText.wholeNumber(number) else {
            refuse("Enter a whole number.", node: nil)
            return
        }
        setParameter(id, to: .integer(whole), continuous: continuous)
    }

    /// An inspector button: recorded for the viewport, which owns pick mode (M4/M6).
    public func press(_ action: InspectorAction, on node: NodeID) {
        requestSerial += 1
        setInspectorRequest(InspectorRequest(node: node, action: action, serial: requestSerial))
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter CreatorEditorTests`
Expected: PASS — `Test run with 114 tests in 15 suites passed`.

- [ ] **Step 6: Commit**

```bash
swiftlint lint --strict   # must report 0 violations before committing (CLAUDE.md "Linting")
git add Sources/CreatorEditor Tests/CreatorEditorTests
git commit -m "feat(editor): inspector rows bound to unwired inputs, parameters and slider coalescing"
```

---

### Task 9: Graph panel views — nodes, sockets, wires, canvas, palette, header

These views follow the MetalUI rules found while verifying this plan:
- A `Component` is legacy content. Inside a `ZStack`/`VStack`/`HStack` it is adopted, but a modifier that needs proposal content (`.offset`, `.opacity`, `.frame`) must go on a proposal container, never directly on a `Component`. That is why `NodeView` wraps `SocketLayer` in a `ZStack`.
- `.help` must come before `.disabled` on a `Button`.
- A frame's root must be an `Element`, so the render helper wraps panels in a `ZStack`.
- Shapes draw their path in their own frame's coordinates. So each wire gets a frame just large enough for its curve (`WireGeometry.bounds`) and is offset into place, rather than relying on a path drawing outside its frame.

**Files:**
- Create: `Sources/CreatorEditor/WireShape.swift`, `WireView.swift`, `NodeRowModel.swift`, `NodeView.swift`, `NodeHeaderView.swift`, `StatusBadgeView.swift`, `NodeRowView.swift`, `SocketLayer.swift`, `CanvasLayers.swift`, `BoxSelectionView.swift`, `GraphCanvas.swift`, `SearchPaletteView.swift`, `PaletteEntryRow.swift`, `GraphPanelHeader.swift`, `GraphPanel.swift`, `GraphShowButton.swift`
- Test: `Tests/CreatorEditorTests/CanvasLayersTests.swift`, `Tests/CreatorEditorTests/GraphPanelRenderTests.swift`, `Tests/CreatorEditorTests/Support/SampleGraph.swift`

**Interfaces:**
- Consumes: everything above. From MetalUI: `Component`, `ZStack(alignment:)`, `VStack`, `HStack`, `Spacer`, `ForEach(_:id:)`, `Text`, `.font`, `.foregroundStyle`, `Shape.path(in:)`, `Path(_:)` with `move`/`addCurve`, `.stroke(_:lineWidth:)`, `.fill`, `.strokeBorder`, `RoundedRectangle`, `Circle`, `Capsule`, `Rectangle`, `Color.clear`, `.frame(width:height:alignment:)`, `.frame(maxWidth:maxHeight:)`, `.padding(Edges)`, `.background(_:in:)`, `.background(_:)`, `.overlay`, `.clipShape`, `.shadow(color:radius:)`, `.opacity`, `.offset(x:y:)`, `.scaleEffect(_:anchor:)`, `.allowsHitTesting`, `.clipped()`, `.gesture`, `.contentShape`, `.onContinuousHover`, `TextField(_:text:onChange:)`, `.onSubmit`, `@FocusState`, `.focused`, `.onAppear`, `Button`, `.buttonStyle(.plain)`, `.keyboardShortcut(_:modifiers:)`, `.help`, `.disabled`, `.animation(_:value:)` with `Animation.spring(duration:bounce:)`.
- Produces:
  - `public struct NodeRowModel: Identifiable { socket; isInput; label; value: String?; static rows(for:shape:graph:registry:) }`
  - `public struct GraphPanel: Component { init(model: EditorModel, input: GraphPanelInput) }`. This is what M6 places per dock.
  - `public struct GraphShowButton: Component { init(model: EditorModel) }`. The shell shows it while the panel is hidden: "Show graph", with Tab as its keyboard shortcut.
  - Internal views: `NodeView`, `CanvasLayers` (with `static wires(_:)` and `static ghosts(_:)`), `GraphCanvas`, `SearchPaletteView`, …
  - Test fixture: `sampleEditor(dock:)`.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorEditorTests/Support/SampleGraph.swift`:
```swift
// Test fixture file: a bracket-like sample document shared by the render tests.
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorEditor

/// Rectangle → Extrude → All Edges → Fillet, a missing node and a Width parameter.
@MainActor
func sampleEditor(dock: DockSide) -> EditorModel {
    let rect = testNode(RectangleTestNode.self, id: 1, at: Vector2(20, 20))
    let extrude = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(260, 20))
    let edges = testNode(AllEdgesTestNode.self, id: 3, at: Vector2(500, 160))
    let fillet = testNode(FilletTestNode.self, id: 4, at: Vector2(740, 20))
    let missing = Node(id: nodeID(5), typeID: "plugin.gone", name: "Gone", position: Vector2(20, 300))
    let width = GraphParameter(name: "Width", type: .number, value: .number(60), min: 10, max: 200)
    return makeEditor([rect, extrude, edges, fillet, missing], [
        wire(rect, "profile", extrude, "profile"), wire(extrude, "solid", edges, "solid"),
        wire(extrude, "solid", fillet, "solid"), wire(edges, "edges", fillet, "edges"),
    ], parameters: [width], dock: dock)
}
```

`Tests/CreatorEditorTests/CanvasLayersTests.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

@MainActor
struct CanvasLayersTests {
    @Test func wiresRunBetweenTheirSocketAnchors() {
        let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
        let extrude = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
        let editor = makeEditor([rect, extrude], [wire(rect, "profile", extrude, "profile")])
        let wires = CanvasLayers.wires(editor)
        #expect(wires.count == 1)
        #expect(wires.first?.geometry.start == Vector2(168, 120))
        #expect(wires.first?.geometry.end == Vector2(300, 40))
        #expect(wires.first?.color == Palette.socket(.profile))
    }

    @Test func nodeRowsShowUnwiredValuesOnly() {
        let rect = testNode(RectangleTestNode.self, id: 1, at: .zero, values: ["width": .number(60)])
        let number = testNode(NumberTestNode.self, id: 2, at: Vector2(0, 300))
        let editor = makeEditor([rect, number], [wire(number, "value", rect, "height")])
        let rows = NodeRowModel.rows(for: rect, shape: editor.shape(of: rect), graph: editor.graph, registry: editor.registry)
        #expect(rows.map(\.label) == ["Width", "Height", "Plane", "Anchor", "Profile"])
        #expect(rows.map(\.value) == ["60 mm", nil, "XY", "4", nil])
        #expect(rows.map(\.isInput) == [true, true, true, true, false])
    }
}
```

`Tests/CreatorEditorTests/GraphPanelRenderTests.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// Headless frames of the graph panel in each state. They don't compare pixels; they prove the
/// views build, lay out and paint text and paths without trapping.
@MainActor
struct GraphPanelRenderTests {
    @Test(arguments: [DockSide.left, .bottom])
    func theGraphPanelDraws(_ dock: DockSide) {
        let editor = sampleEditor(dock: dock)
        editor.selection = [nodeID(2)]
        let input = GraphPanelInput(model: editor)
        let scene = renderHeadless { GraphPanel(model: editor, input: input) }
        #expect(!scene.glyphs.isEmpty)
        #expect(!scene.images.isEmpty)   // wires are rasterized paths
    }

    @Test func thePanelDrawsWhileDraggingAWireAndBoxSelecting() {
        let editor = sampleEditor(dock: .bottom)
        let input = GraphPanelInput(model: editor)
        let socket = editor.screenPoint(of: nodeID(1), "profile", input: false)
        editor.pointerDragged(from: socket, to: socket)
        editor.pointerDragged(from: socket, to: socket + Vector2(80, 60))
        #expect(!renderHeadless { GraphPanel(model: editor, input: input) }.isEmpty)
        editor.pointerReleased(from: socket, at: Vector2(880, 580))
        editor.modifiers = .shift
        editor.pointerDragged(from: Vector2(880, 580), to: Vector2(880, 580))
        editor.pointerDragged(from: Vector2(880, 580), to: Vector2(600, 400))
        #expect(!renderHeadless { GraphPanel(model: editor, input: input) }.isEmpty)
    }

    @Test func thePanelDrawsWithThePaletteOpenAndARefusalShowing() {
        let editor = sampleEditor(dock: .left)
        editor.pointerLocation = Vector2(200, 200)
        editor.openPalette()
        editor.connect(Link(from: Endpoint(node: nodeID(1), socket: "profile"), to: Endpoint(node: nodeID(4), socket: "radius")))
        #expect(editor.refusal != nil)
        let input = GraphPanelInput(model: editor)
        #expect(!renderHeadless { GraphPanel(model: editor, input: input) }.glyphs.isEmpty)
    }

    /// Hide must never be a one-way trip: the hidden state has a visible way back.
    @Test func theHiddenPanelLeavesAShowButton() {
        let editor = sampleEditor(dock: .hidden)
        #expect(!renderHeadless { GraphShowButton(model: editor) }.glyphs.isEmpty)
    }

    @Test func theDuplicateGhostsDraw() {
        let editor = sampleEditor(dock: .bottom)
        editor.selection = [nodeID(1)]
        editor.modifiers = .option
        let start = editor.screenPoint(in: nodeID(1))
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(0, 120))
        let input = GraphPanelInput(model: editor)
        #expect(!renderHeadless { GraphPanel(model: editor, input: input) }.isEmpty)
    }
}
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: "cannot find 'CanvasLayers' in scope", "cannot find 'NodeRowModel' in scope", "cannot find 'GraphPanel' in scope".

- [ ] **Step 3: Implement the wire and node views**

`Sources/CreatorEditor/WireShape.swift`:
```swift
import CreatorGeometry
import MetalUI

/// A wire drawn as a bezier `Path`, in coordinates relative to its own frame's origin.
struct WireShape: Shape, Hashable {
    var start: Vector2
    var control1: Vector2
    var control2: Vector2
    var end: Vector2

    init(_ geometry: WireGeometry, origin: Vector2) {
        start = geometry.start - origin
        control1 = geometry.control1 - origin
        control2 = geometry.control2 - origin
        end = geometry.end - origin
    }

    func path(in rect: Bounds<Pixels>) -> Path {
        Path { path in
            path.move(to: Self.point(start))
            path.addCurve(to: Self.point(end), control1: Self.point(control1), control2: Self.point(control2))
        }
    }

    static func point(_ v: Vector2) -> Point<Pixels> { Point(x: v.x.px, y: v.y.px) }
}
```

`Sources/CreatorEditor/WireView.swift`:
```swift
import CreatorGeometry
import MetalUI

/// One wire: a stroked `WireShape` in a frame just big enough for the curve, offset to its
/// place on the canvas.
struct WireView: Component {
    let geometry: WireGeometry
    let color: HexColor
    var lineWidth = 2.0

    var content: some ElementGroup {
        let bounds = geometry.bounds(padding: lineWidth * 2)
        return WireShape(geometry, origin: bounds.origin)
            .stroke(color.color, lineWidth: lineWidth.px)
            .frame(width: bounds.size.x.px, height: bounds.size.y.px)
            .offset(x: bounds.origin.x.px, y: bounds.origin.y.px)
    }
}
```

`Sources/CreatorEditor/NodeRowModel.swift`:
```swift
import CreatorGraph

/// One body row of a node on the canvas: an input (with its constant when unwired) or an output.
public struct NodeRowModel: Equatable, Sendable, Identifiable {
    public var socket: SocketName
    public var isInput: Bool
    public var label: String
    /// The unwired input's value, shown beside its label; `nil` for wired inputs and outputs.
    public var value: String?

    public var id: String { (isInput ? "in." : "out.") + socket.rawValue }

    /// Rows for `node`: inputs first, then outputs, matching `NodeLayout`'s row order.
    public static func rows(for node: Node, shape: NodeShape, graph: Graph, registry: NodeRegistry) -> [NodeRowModel] {
        let specs = registry[node.typeID]?.inputs ?? []
        let inputs = shape.inputs.map { socket -> NodeRowModel in
            let wired = graph.incomingLink(to: Endpoint(node: node.id, socket: socket.name)) != nil
            let spec = specs.first { $0.name == socket.name }
            let value = wired || spec == nil ? nil
                : ValueText.format(node.inputValues[socket.name] ?? spec?.defaultValue, unit: spec?.unit ?? .none)
            return NodeRowModel(socket: socket.name, isInput: true, label: InspectorLabel.text(for: socket.name), value: value)
        }
        let outputs = shape.outputs.map {
            NodeRowModel(socket: $0.name, isInput: false, label: InspectorLabel.text(for: $0.name), value: nil)
        }
        return inputs + outputs
    }
}
```

`Sources/CreatorEditor/NodeView.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import MetalUI

/// One node on the canvas (spec §6.2): a header in its category colour with the name and status
/// badge, then a row per input (with its value when unwired) and per output. Sized by
/// `NodeLayout` so drawing and hit testing agree; input is handled by the canvas, not here.
struct NodeView: Component {
    let shape: NodeShape
    let rows: [NodeRowModel]
    let origin: Vector2
    let flow: CanvasFlow
    let isSelected: Bool
    let state: NodeState?
    /// Horizontal offset while the node shakes after a refused wire; it springs back to 0.
    let shake: Double
    /// Drawn at reduced opacity: an ⌥-drag ghost.
    var isGhost = false

    var content: some ElementGroup {
        let size = NodeLayout.size(shape)
        let accent = Palette.header(for: shape.category)
        let corner = RoundedRectangle(cornerRadius: Pixels(6))
        return VStack(alignment: .leading, spacing: Pixels(0)) {
            NodeHeaderView(title: shape.isMissing ? "Missing: \(shape.title)" : shape.title, accent: accent, state: state)
            VStack(alignment: .leading, spacing: Pixels(0)) {
                ForEach(rows, id: \.id) { row in
                    NodeRowView(row: row)
                }
            }
            .padding(Edges(top: NodeLayout.bodyPadding.px, right: Pixels(10),
                           bottom: NodeLayout.bodyPadding.px, left: Pixels(10)))
        }
        .frame(width: size.x.px, height: size.y.px, alignment: .topLeading)
        .background(Palette.nodeBody.color, in: corner)
        .clipShape(corner)
        .overlay {
            corner.strokeBorder(isSelected ? accent.color : Palette.hairline.color,
                                lineWidth: Pixels(isSelected ? 2 : 1))
        }
        .shadow(color: accent.opacity(isSelected ? 0.7 : 0).color, radius: Pixels(isSelected ? 10 : 0))
        .overlay(alignment: .topLeading) {
            // A Component is legacy content; inside a ZStack it is adopted, so the result stays
            // proposal content and takes the modifiers below.
            ZStack(alignment: .topLeading) { SocketLayer(shape: shape, flow: flow) }
        }
        .opacity(isGhost ? 0.4 : 1)
        .offset(x: (origin.x + shake).px, y: origin.y.px)
        // Only a change of `shake` animates, so dragging and panning stay immediate. The bouncy
        // spring back to 0 is the "brief shake" (spec §6.2); MetalUI has no keyframes.
        .animation(.spring(duration: 0.35, bounce: 0.7), value: shake)
    }
}
```

`Sources/CreatorEditor/NodeHeaderView.swift`:
```swift
import CreatorGraph
import MetalUI

/// A node's header strip: dark text on the category colour, the status badge at the right.
struct NodeHeaderView: Component {
    let title: String
    let accent: HexColor
    let state: NodeState?

    var content: some ElementGroup {
        HStack(spacing: Pixels(6)) {
            Text(title)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Palette.textOnAccent.color)
            Spacer()
            StatusBadgeView(state: state)
        }
        .padding(Edges(top: Pixels(0), right: Pixels(8), bottom: Pixels(0), left: Pixels(8)))
        .frame(width: NodeLayout.width.px, height: NodeLayout.headerHeight.px)
        .background(accent.color)
    }
}
```

`Sources/CreatorEditor/StatusBadgeView.swift`:
```swift
import CreatorGraph
import MetalUI

/// The status badge: a spinner glyph, the time in ms, ⚠ or ✕, on a dark capsule so it reads on
/// any header colour. The warning or error message is its tooltip.
struct StatusBadgeView: Component {
    let state: NodeState?

    var content: some ElementGroup {
        let text = StatusBadge.text(for: state)
        let colour = state.map(Palette.status) ?? Palette.secondaryText
        return HStack(spacing: Pixels(0)) {
            Text(text)
                .font(.caption2)
                .foregroundStyle(colour.color)
        }
        .padding(Edges(top: Pixels(1), right: Pixels(5), bottom: Pixels(1), left: Pixels(5)))
        .background(Palette.panelBase.color, in: Capsule())
        .opacity(text.isEmpty ? 0 : 1)
        .help(StatusBadge.message(for: state) ?? "")
    }
}
```

`Sources/CreatorEditor/NodeRowView.swift`:
```swift
import MetalUI

/// One body row: the socket label, and an unwired input's value at the trailing edge.
struct NodeRowView: Component {
    let row: NodeRowModel

    var content: some ElementGroup {
        HStack(spacing: Pixels(6)) {
            if row.isInput {
                Text(row.label).font(.caption).foregroundStyle(Palette.primaryText.color)
                Spacer()
                Text(row.value ?? "").font(.caption).foregroundStyle(Palette.secondaryText.color)
            } else {
                Spacer()
                Text(row.label).font(.caption).foregroundStyle(Palette.primaryText.color)
            }
        }
        .frame(height: NodeLayout.rowHeight.px)
    }
}
```

`Sources/CreatorEditor/SocketLayer.swift`:
```swift
import CreatorGeometry
import MetalUI

/// A node's socket dots, coloured by type, placed by `NodeLayout` for the current flow.
struct SocketLayer: Component {
    let shape: NodeShape
    let flow: CanvasFlow

    var content: some ElementGroup {
        let size = NodeLayout.size(shape)
        let dots = Self.dots(shape: shape, flow: flow)
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(width: size.x.px, height: size.y.px)
            ForEach(dots, id: \.id) { dot in
                Circle()
                    .fill(dot.color.color)
                    .frame(width: (2 * NodeLayout.socketRadius).px, height: (2 * NodeLayout.socketRadius).px)
                    .overlay { Circle().strokeBorder(Palette.panelBase.color, lineWidth: Pixels(1.5)) }
                    .offset(x: (dot.centre.x - NodeLayout.socketRadius).px, y: (dot.centre.y - NodeLayout.socketRadius).px)
            }
        }
    }

    struct Dot: Identifiable {
        var id: String
        var centre: Vector2
        var color: HexColor
    }

    static func dots(shape: NodeShape, flow: CanvasFlow) -> [Dot] {
        var dots: [Dot] = []
        for (sockets, isInput) in [(shape.inputs, true), (shape.outputs, false)] {
            for socket in sockets {
                guard let centre = NodeLayout.socketOffset(socket.name, isInput: isInput, in: shape, flow: flow) else { continue }
                let color = socket.type.map(Palette.socket) ?? Palette.secondaryText
                dots.append(Dot(id: (isInput ? "in." : "out.") + socket.name.rawValue, centre: centre, color: color))
            }
        }
        return dots
    }
}
```

- [ ] **Step 4: Implement the canvas, palette and panel**

`Sources/CreatorEditor/CanvasLayers.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import MetalUI

/// Everything drawn under the canvas transform, back to front: wires, nodes, ⌥-drag ghosts, the
/// wire being dragged and the box selection. Positions are display canvas points; the parent
/// applies zoom and pan as render effects.
struct CanvasLayers: Component {
    let model: EditorModel

    var content: some ElementGroup {
        let flow = model.flow
        return ZStack(alignment: .topLeading) {
            ForEach(Self.wires(model), id: \.id) { wire in
                WireView(geometry: wire.geometry, color: wire.color)
            }
            ForEach(model.drawOrder, id: \.id) { node in
                let shape = model.shape(of: node)
                NodeView(shape: shape,
                         rows: NodeRowModel.rows(for: node, shape: shape, graph: model.graph, registry: model.registry),
                         origin: model.displayOrigin(of: node), flow: flow,
                         isSelected: model.selection.contains(node.id),
                         state: model.document.results[node.id]?.state,
                         shake: model.isShaking && model.refusal?.node == node.id ? 6 : 0)
            }
            ForEach(Self.ghosts(model), id: \.id) { node in
                let shape = model.shape(of: node)
                NodeView(shape: shape, rows: [], origin: flow.display(node.position), flow: flow,
                         isSelected: true, state: nil, shake: 0, isGhost: true)
            }
            if case .connecting(let drag)? = model.interaction, let anchor = model.anchor(of: drag.from) {
                let geometry = drag.from.isInput
                    ? WireGeometry(from: drag.current, to: anchor, flow: flow)
                    : WireGeometry(from: anchor, to: drag.current, flow: flow)
                WireView(geometry: geometry, color: Palette.focus)
            }
            if case .boxSelecting(let start, let current, _)? = model.interaction {
                BoxSelectionView(rect: CanvasRect(corner: start, current))
            }
        }
    }

    struct Wire: Identifiable {
        var id: String
        var geometry: WireGeometry
        var color: HexColor
    }

    /// Every wire whose two sockets are on the canvas, coloured by its source socket's type.
    static func wires(_ model: EditorModel) -> [Wire] {
        model.graph.links.compactMap { link in
            let from = SocketRef(link.from, isInput: false), to = SocketRef(link.to, isInput: true)
            guard let start = model.anchor(of: from), let end = model.anchor(of: to),
                  let source = model.graph.nodes[link.from.node] else { return nil }
            let type = model.shape(of: source).outputs.first { $0.name == link.from.socket }?.type
            return Wire(id: "\(link.to.node.rawValue.uuidString).\(link.to.socket.rawValue)",
                        geometry: WireGeometry(from: start, to: end, flow: model.flow),
                        color: type.map(Palette.socket) ?? Palette.secondaryText)
        }
    }

    /// The ⌥-drag ghosts: copies of the dragged nodes at their would-be positions.
    static func ghosts(_ model: EditorModel) -> [Node] {
        guard case .duplicating(let start, let delta)? = model.interaction else { return [] }
        return start.keys.sorted().compactMap { id in
            guard var node = model.graph.nodes[id], let position = start[id] else { return nil }
            node.position = position + delta
            return node
        }
    }
}
```

`Sources/CreatorEditor/BoxSelectionView.swift`:
```swift
import MetalUI

/// The ⇧-drag box: a faint cyan fill with a cyan outline.
struct BoxSelectionView: Component {
    let rect: CanvasRect

    var content: some ElementGroup {
        Rectangle()
            .fill(Palette.focus.opacity(0.08).color)
            .overlay { Rectangle().strokeBorder(Palette.focus.color, lineWidth: Pixels(1)) }
            .frame(width: rect.size.x.px, height: rect.size.y.px)
            .offset(x: rect.origin.x.px, y: rect.origin.y.px)
    }
}
```

`Sources/CreatorEditor/GraphCanvas.swift`:
```swift
import MetalUI

/// The graph canvas: the layers under the zoom and pan transform, one press-and-drag gesture
/// for everything (hit testing is the model's), pointer tracking for the palette, and the
/// palette itself, which is not zoomed.
struct GraphCanvas: Component {
    let model: EditorModel
    let input: GraphPanelInput

    var content: some ElementGroup {
        let transform = model.transform
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
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
            if let palette = model.palette {
                ZStack(alignment: .topLeading) { SearchPaletteView(model: model) }
                    .offset(x: palette.screenPosition.x.px, y: palette.screenPosition.y.px)
            }
        }
    }
}
```

`Sources/CreatorEditor/SearchPaletteView.swift`:
```swift
import MetalUI

/// The add-node palette: a search field (focused when it opens) and the matching types, the
/// highlighted one marked. Return adds it, Escape closes (keys come through `GraphPanelInput`).
struct SearchPaletteView: Component {
    let model: EditorModel
    @FocusState var searchFocused: Bool

    var content: some ElementGroup {
        let entries = model.paletteEntries
        let highlightedID = entries.indices.contains(model.palette?.highlighted ?? 0)
            ? entries[model.palette?.highlighted ?? 0].id : nil
        return GlassPanel {
            VStack(alignment: .leading, spacing: Pixels(4)) {
                TextField("Add node", text: model.palette?.query ?? "", onChange: { model.setPaletteQuery($0) })
                    .onSubmit { model.confirmPalette() }
                    .focused($searchFocused)
                    .onAppear { searchFocused = true }
                ForEach(entries, id: \.id) { entry in
                    PaletteEntryRow(entry: entry, isHighlighted: entry.id == highlightedID) {
                        model.confirmPalette(entry)
                    }
                }
                if entries.isEmpty {
                    Text("No matching nodes").font(.caption).foregroundStyle(Palette.secondaryText.color)
                }
            }
            .frame(width: Pixels(220), alignment: .topLeading)
        }
    }
}
```

`Sources/CreatorEditor/PaletteEntryRow.swift`:
```swift
import MetalUI

/// One palette match: a category-coloured dot and the type's name; clicking adds it.
struct PaletteEntryRow: Component {
    let entry: PaletteEntry
    let isHighlighted: Bool
    let action: @MainActor () -> Void

    var content: some ElementGroup {
        Button(action: action) {
            HStack(spacing: Pixels(6)) {
                Circle().fill(Palette.header(for: entry.category).color).frame(width: Pixels(8), height: Pixels(8))
                Text(entry.displayName).font(.callout).foregroundStyle(Palette.primaryText.color)
                Spacer()
            }
            .padding(Edges(top: Pixels(3), right: Pixels(6), bottom: Pixels(3), left: Pixels(6)))
            .background(isHighlighted ? Palette.field.color : Color.clear, in: RoundedRectangle(cornerRadius: Pixels(4)))
        }
        .buttonStyle(.plain)
    }
}
```

`Sources/CreatorEditor/GraphPanelHeader.swift`:
```swift
import CreatorGraph
import MetalUI

/// The graph panel's header: the title, dock buttons (Left, Bottom, Hide), zoom buttons (the
/// stopgap for pinch and ⌘-scroll, docs/metalui-gaps.md) and Add, which opens the palette.
struct GraphPanelHeader: Component {
    let model: EditorModel

    var content: some ElementGroup {
        HStack(spacing: Pixels(6)) {
            Text("Graph").font(.headline).foregroundStyle(Palette.primaryText.color)
            Spacer()
            Button("Add") { model.openPalette() }
                .help("Add a node (Space)")
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

`Sources/CreatorEditor/GraphShowButton.swift`:
```swift
import MetalUI

/// The hidden graph panel's way back (spec §6.1, "Hidden (⇥ toggles it)"). The shell shows it
/// while `EditorModel.isPanelVisible` is false. Its Tab shortcut is claimed in MetalUI's button
/// shortcut stage, which runs before focus traversal would take Tab (gap M5-b).
public struct GraphShowButton: Component {
    public let model: EditorModel

    public init(model: EditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        GlassPanel {
            Button("Show graph") { model.toggleHidden() }
                .keyboardShortcut(.tab, modifiers: [])
                .help("Show the graph (Tab)")
        }
    }
}
```

`Sources/CreatorEditor/GraphPanel.swift`:
```swift
import CreatorGraph
import MetalUI

/// The graph panel (spec §6.2): glass chrome, the header and the canvas, with a refusal message
/// along the bottom while one is showing. The app shell (M6) sizes and places it per dock and
/// installs the input with `input.install(on:)`.
public struct GraphPanel: Component {
    public let model: EditorModel
    public let input: GraphPanelInput

    public init(model: EditorModel, input: GraphPanelInput) {
        self.model = model
        self.input = input
    }

    public var content: some ElementGroup {
        GlassPanel {
            VStack(alignment: .leading, spacing: Pixels(8)) {
                GraphPanelHeader(model: model)
                GraphCanvas(model: model, input: input)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let refusal = model.refusal {
                    Text(refusal.message).font(.caption).foregroundStyle(Palette.statusError.color)
                }
            }
        }
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter CreatorEditorTests`
Expected: PASS — `Test run with 121 tests in 17 suites passed`. The render tests take about a second, because the first CoreText shaping is slow.

- [ ] **Step 6: Commit**

```bash
swiftlint lint --strict   # must report 0 violations before committing (CLAUDE.md "Linting")
git add Sources/CreatorEditor Tests/CreatorEditorTests
git commit -m "feat(editor): graph panel views — nodes, sockets, bezier wires, canvas, palette"
```

---

### Task 10: Context inspector views

**Files:**
- Create: `Sources/CreatorEditor/NumberEntry.swift`, `LabeledRow.swift`, `AnchorGridView.swift`, `AnchorCell.swift`, `InspectorRowView.swift`, `InspectorHeaderView.swift`, `InspectorSectionView.swift`, `ParameterRowView.swift`, `InspectorPanel.swift`
- Test: `Tests/CreatorEditorTests/InspectorRenderTests.swift`

**Interfaces:**
- Consumes: Task 8's `InspectorPage`/`InspectorRow` and the `EditorModel` editing methods (`setNumber`, `setVectorComponent`, `clearInput`, `chooseParameter`, `setParameterNumber`). From MetalUI: `Slider(value:in:)`, `Toggle(_:isOn:)`, `Picker(_:selection:content:)` with `.tag` and `.pickerStyle(.segmented)` / `.pickerStyle(.menu)`, `Grid(horizontalSpacing:verticalSpacing:)`/`GridRow`, `Binding(get:set:)`, `@State`, `.onChange(of:)` (zero-parameter closure form), `TextField(_:text:onChange:)`, `.onSubmit`.
- Produces: `public struct InspectorPanel: Component { init(model: EditorModel) }`, which M6 docks on the right.

- [ ] **Step 1: Write the failing test**

`Tests/CreatorEditorTests/InspectorRenderTests.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// Headless frames of the inspector for nothing selected and for each kind of node, including a
/// missing one: every row kind builds with MetalUI's controls without trapping.
@MainActor
struct InspectorRenderTests {
    @Test(arguments: [nil, 1, 2, 3, 4, 5])
    func theInspectorDraws(_ selected: Int?) {
        let editor = sampleEditor(dock: .left)
        editor.selection = selected.map { [nodeID($0)] } ?? []
        #expect(!renderHeadless { InspectorPanel(model: editor) }.glyphs.isEmpty)
    }

    /// M3's `.vector` and `.parameterPicker` rows, the picker with and without parameters, and an
    /// unset optional input.
    @Test func vectorParameterAndOptionalRowsDraw() {
        let transform = testNode(TransformTestNode.self, id: 5, at: .zero)
        let picker = testNode(GraphParameterTestNode.self, id: 6, at: Vector2(0, 200))
        let grid = testNode(GridPointsTestNode.self, id: 7, at: Vector2(0, 400))
        let width = GraphParameter(name: "Width", type: .number, value: .number(60))
        let editor = makeEditor([transform, picker, grid], parameters: [width], registry: inspectorTestRegistry)
        for id in [transform.id, picker.id, grid.id] {
            editor.selection = [id]
            #expect(!renderHeadless { InspectorPanel(model: editor) }.glyphs.isEmpty)
        }
        let empty = makeEditor([picker], registry: inspectorTestRegistry)
        empty.selection = [picker.id]
        #expect(!renderHeadless { InspectorPanel(model: empty) }.glyphs.isEmpty)
    }
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: "cannot find 'InspectorPanel' in scope".

- [ ] **Step 3: Implement the controls**

`NumberEntry` keeps a local draft while typing, so "6" on the way to "60" never reaches the graph. Sliders write with `continuous: true` (one undo step per drag, Task 8). Typed values and toggles write with `continuous: false`. For an optional input, the field is empty with the placeholder "Not set" while unset, and submitting it empty calls `clearInput`.

`Sources/CreatorEditor/NumberEntry.swift`:
```swift
import MetalUI

/// A number field that commits on Return. While typing, the draft is kept locally so a partial
/// value ("6" on the way to "60") never reaches the graph; an unreadable entry is discarded.
/// With `clear`, an emptied field submits a clear instead (an optional input).
struct NumberEntry: Component {
    let text: String
    var placeholder = "Value"
    var width = 72.0
    var clear: (@MainActor () -> Void)?
    let commit: @MainActor (Double) -> Void
    @State var draft: String?

    var content: some ElementGroup {
        HStack(spacing: Pixels(0)) {
            TextField(placeholder, text: draft ?? text, onChange: { draft = $0 })
                .onSubmit {
                    if let draft {
                        if let clear, draft.trimmingCharacters(in: .whitespaces).isEmpty {
                            clear()
                        } else if let value = ValueText.parse(draft) {
                            commit(value)
                        }
                    }
                    draft = nil
                }
        }
        .frame(width: width.px)
        .onChange(of: text) { draft = nil }
    }
}
```

`Sources/CreatorEditor/LabeledRow.swift`:
```swift
import MetalUI

/// An inspector row: a label in primary text, then the row's controls.
struct LabeledRow<Controls: ElementGroup>: Component {
    let label: String
    let controls: Controls

    init(label: String, @ElementBuilder controls: () -> Controls) {
        self.label = label
        self.controls = controls()
    }

    var content: some ElementGroup {
        HStack(spacing: Pixels(8)) {
            Text(label).font(.callout).foregroundStyle(Palette.primaryText.color)
            controls
        }
    }
}
```

`Sources/CreatorEditor/AnchorGridView.swift`:
```swift
import MetalUI

/// A 3×3 anchor picker; cells are numbered 0…8 row-major from the top-left.
struct AnchorGridView: Component {
    let selected: Int?
    let choose: @MainActor (Int) -> Void

    var content: some ElementGroup {
        Grid(horizontalSpacing: Pixels(2), verticalSpacing: Pixels(2)) {
            ForEach(0..<3) { row in
                GridRow {
                    ForEach(0..<3) { column in
                        AnchorCell(isSelected: selected == row * 3 + column) { choose(row * 3 + column) }
                    }
                }
            }
        }
    }
}
```

`Sources/CreatorEditor/AnchorCell.swift`:
```swift
import MetalUI

/// One anchor grid cell: filled purple when selected.
struct AnchorCell: Component {
    let isSelected: Bool
    let action: @MainActor () -> Void

    var content: some ElementGroup {
        Button(action: action) {
            Circle()
                .fill(isSelected ? Palette.primaryButton.color : Palette.field.color)
                .frame(width: Pixels(10), height: Pixels(10))
        }
        .buttonStyle(.plain)
    }
}
```

`Sources/CreatorEditor/InspectorRowView.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI

/// Draws one `InspectorRow` with MetalUI controls bound to the model (spec §6.4).
struct InspectorRowView: Component {
    let row: InspectorRow
    let model: EditorModel
    let node: NodeID?

    var content: some ElementGroup {
        switch row {
        case .slider(let field, let range):
            LabeledRow(label: field.label) {
                Slider(value: Binding(get: { field.number ?? range.lowerBound },
                                      set: { model.setNumber(field, to: $0, continuous: true) }),
                       in: range)
                NumberEntry(text: ValueText.format(field.value, unit: field.unit)) {
                    model.setNumber(field, to: $0)
                }
            }
        case .number(let field), .integer(let field):
            // `setNumber` writes a whole number for an integer socket, or refuses one no `Int` holds.
            // An optional input shows "Not set" while unset, and emptying the field clears it.
            LabeledRow(label: field.label) {
                Spacer()
                NumberEntry(text: Self.text(field), placeholder: field.isOptional ? "Not set" : "Value",
                            clear: Self.clear(field, model)) {
                    model.setNumber(field, to: $0)
                }
            }
        case .toggle(let field, let label):
            Toggle(label, isOn: Binding(get: { if case .bool(true)? = field.value { true } else { false } },
                                        set: { model.setInput(field, to: .bool($0)) }))
        case .segmented(let field, let options, let selected):
            Picker(field.label, selection: Binding(get: { selected ?? -1 }, set: { index in
                if let value = InspectorBuilder.segmentValue(index, options: options, type: field.type) {
                    model.setInput(field, to: value)
                }
            })) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index]).tag(index)
                }
            }
            .pickerStyle(.segmented)
        case .planePicker(let field, let selected):
            Picker(field.label, selection: Binding(get: { selected }, set: { choice in
                guard let choice else { return }
                var plane = choice.plane
                if case .plane(let current)? = field.value { plane.origin = current.origin }
                model.setInput(field, to: .plane(plane))
            })) {
                ForEach(PlaneChoice.allCases, id: \.self) { choice in
                    Text(choice.rawValue).tag(Optional(choice))
                }
            }
            .pickerStyle(.segmented)
        case .vector(let field):
            // Three compact fields, x y z; each writes the whole vector with one component replaced.
            // An unset optional vector (M3's Transform `axisDirection`) shows empty fields, and
            // emptying any field clears it.
            LabeledRow(label: field.label) {
                Spacer()
                ForEach(0..<3) { axis in
                    NumberEntry(text: Self.text(field, axis: axis), placeholder: field.isOptional ? "–" : "Value", width: 52,
                                clear: Self.clear(field, model)) {
                        model.setVectorComponent(field, axis: axis, to: $0)
                    }
                }
            }
        case .anchorGrid(let field, let selected):
            LabeledRow(label: field.label) {
                Spacer()
                AnchorGridView(selected: selected) { model.setInput(field, to: .integer($0)) }
            }
        case .parameterPicker(let field, let options, let selected):
            if options.isEmpty {
                LabeledRow(label: field.label) {
                    Spacer()
                    Text("No parameters").font(.callout).foregroundStyle(Palette.secondaryText.color)
                }
            } else {
                Picker(field.label, selection: Binding(get: { selected }, set: { id in
                    if let id { model.chooseParameter(id, for: field) }
                })) {
                    ForEach(options, id: \.id) { parameter in
                        Text(parameter.name).tag(Optional(parameter.id))
                    }
                }
                .pickerStyle(.menu)
            }
        case .ruleSummary(let label, let summary):
            LabeledRow(label: label) {
                Spacer()
                Text(summary).font(.callout).foregroundStyle(Palette.pink.color)
            }
        case .button(let title, let action):
            Button(title) { if let node { model.press(action, on: node) } }
        case .wired(let label, let source):
            LabeledRow(label: label) {
                Spacer()
                Text(source).font(.callout).foregroundStyle(Palette.secondaryText.color)
            }
        case .readOnly(let label, let text):
            LabeledRow(label: label) {
                Spacer()
                Text(text).font(.callout).foregroundStyle(Palette.secondaryText.color)
            }
        }
    }

    /// A field's text: empty while an optional input is unset, else its value (one component of a vector).
    static func text(_ field: InputField, axis: Int? = nil) -> String {
        guard field.value != nil else { return "" }
        guard let axis else { return ValueText.format(field.value, unit: field.unit) }
        return ValueText.format(field.vectorComponents[axis], unit: .none)
    }

    /// What emptying the field does: clears an optional input, nothing for a required one.
    static func clear(_ field: InputField, _ model: EditorModel) -> (@MainActor () -> Void)? {
        guard field.isOptional else { return nil }
        return { model.clearInput(field) }
    }
}
```

- [ ] **Step 4: Implement the panel**

`Sources/CreatorEditor/InspectorHeaderView.swift`:
```swift
import CreatorGraph
import MetalUI

/// The inspector's header bar in the node's category colour, with its name and status (spec §6.4).
struct InspectorHeaderView: Component {
    let header: InspectorHeader

    var content: some ElementGroup {
        HStack(spacing: Pixels(8)) {
            Text(header.title).font(.headline).foregroundStyle(Palette.textOnAccent.color)
            Spacer()
            StatusBadgeView(state: header.state)
        }
        .padding(Edges(top: Pixels(6), right: Pixels(10), bottom: Pixels(6), left: Pixels(10)))
        .background(Palette.header(for: header.category).color, in: RoundedRectangle(cornerRadius: Pixels(6)))
    }
}
```

`Sources/CreatorEditor/InspectorSectionView.swift`:
```swift
import MetalUI

/// A titled inspector section: a small uppercase title in hint text, then its rows.
struct InspectorSectionView<Rows: ElementGroup>: Component {
    let title: String
    let rows: Rows

    init(title: String, @ElementBuilder rows: () -> Rows) {
        self.title = title
        self.rows = rows()
    }

    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(6)) {
            Text(title.uppercased()).font(.caption2).foregroundStyle(Palette.secondaryText.color)
            rows
        }
    }
}
```

`Sources/CreatorEditor/ParameterRowView.swift`:
```swift
import CreatorGraph
import MetalUI

/// One document parameter: its name, a slider over its range and a number field.
struct ParameterRowView: Component {
    let row: ParameterRow
    let model: EditorModel

    var content: some ElementGroup {
        let parameter = row.parameter
        let number: Double = if case .integer(let value) = parameter.value {
            Double(value)
        } else if case .number(let value) = parameter.value {
            value
        } else {
            row.range.lowerBound
        }
        // `setParameterNumber` rounds for an integer parameter and refuses what no `Int` holds.
        let write: @MainActor (Double, Bool) -> Void = { value, continuous in
            model.setParameterNumber(parameter.id, to: value, continuous: continuous)
        }
        return LabeledRow(label: parameter.name) {
            Slider(value: Binding(get: { number }, set: { write($0, true) }), in: row.range)
            NumberEntry(text: ValueText.format(number, unit: .none)) { write($0, false) }
        }
    }
}
```

`Sources/CreatorEditor/InspectorPanel.swift`:
```swift
import CreatorGraph
import MetalUI

/// The context inspector (spec §6.4): the selected node's header and sections, then the document
/// parameters, which are always listed. The app shell (M6) docks it on the right.
public struct InspectorPanel: Component {
    public let model: EditorModel

    public init(model: EditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        let page = model.inspectorPage
        return GlassPanel {
            VStack(alignment: .leading, spacing: Pixels(10)) {
                if let header = page.header {
                    InspectorHeaderView(header: header)
                }
                ForEach(page.sections, id: \.title) { section in
                    InspectorSectionView(title: section.title) {
                        ForEach(section.rows.indices, id: \.self) { index in
                            InspectorRowView(row: section.rows[index], model: model, node: page.header?.node)
                        }
                    }
                }
                InspectorSectionView(title: "Document Parameters") {
                    if page.parameters.isEmpty {
                        Text("No parameters").font(.caption).foregroundStyle(Palette.secondaryText.color)
                    }
                    ForEach(page.parameters, id: \.id) { row in
                        ParameterRowView(row: row, model: model)
                    }
                }
            }
            .frame(width: Pixels(280), alignment: .topLeading)
        }
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter CreatorEditorTests`
Expected: PASS — `Test run with 123 tests in 18 suites passed`.

- [ ] **Step 6: Commit**

```bash
swiftlint lint --strict   # must report 0 violations before committing (CLAUDE.md "Linting")
git add Sources/CreatorEditor Tests/CreatorEditorTests
git commit -m "feat(editor): context inspector with node sections and document parameters"
```

---

### Task 11: Preview executable, MetalUI gaps, human checks and docs

**Files:**
- Modify: `Package.swift`, `docs/metalui-gaps.md`, `CLAUDE.md`, `AGENTS.md`, `docs/superpowers/roadmap.md`, `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`, `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (Errata (M5))
- Create: `Sources/GraphPanelPreview/main.swift`, `PreviewRoot.swift`, `PreviewDocument.swift`, `PreviewNodes.swift`
- Append to: `docs/verification/human-checks.md` (M4 created it, with group V; Task 1's pre-flight checked it)

**Interfaces:**
- Consumes: `GraphPanel`, `GraphShowButton`, `InspectorPanel`, `GraphPanelInput.install(on:)` (which sets `onInput`, `keymap`, `onAction` and `releaseTextFocus`), `EditorModel`, `Palette`. From MetalUI: `App()`, `App.openWindow(title:size:content:)`, `app.run()`.
- Produces: `swift run GraphPanelPreview`, the human-check target. M6 replaces it with the real app shell and can then delete it.

- [ ] **Step 1: Add the preview target**

In `Package.swift`, add this to `targets:` after the `CreatorEditor` target (in place, as in Task 1; `metalUI` is M4's constant):
```swift
        .executableTarget(
            name: "GraphPanelPreview",
            dependencies: ["CreatorEditor", "CreatorGraph", "CreatorKernel", "CreatorGeometry", metalUI]
        ),
```

- [ ] **Step 2: Write the preview**

`Sources/GraphPanelPreview/PreviewNodes.swift`:
```swift
// Preview fixture file: a few small node definitions, one per category, so the graph panel can be
// checked by eye without CreatorNodes. Not shipped: the app (M6) registers the real nodes.
import CreatorGeometry
import CreatorGraph
import CreatorKernel

enum PreviewNumber: NodeDefinition {
    static let typeID = "preview.number"
    static let displayName = "Number"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(60), unit: .millimetres, range: 0...200)]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

enum PreviewRectangle: NodeDefinition {
    static let typeID = "preview.rectangle"
    static let displayName = "Rectangle"
    static let category = NodeCategory.profile
    static let inputs = [
        SocketSpec("width", .number, defaultValue: .number(60), unit: .millimetres, range: 1...200),
        SocketSpec("height", .number, defaultValue: .number(40), unit: .millimetres, range: 1...200),
        SocketSpec("plane", .plane, defaultValue: .plane(.xy)),
        SocketSpec("anchor", .integer, defaultValue: .integer(4)),
    ]
    static let outputs = [SocketSpec("profile", .profile)]
    static let inspector = [
        InspectorSection(title: "Size", controls: [.slider("width"), .slider("height")]),
        InspectorSection(title: "Placement", controls: [.planePicker("plane"), .anchorGrid("anchor")]),
    ]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let profile = Profile2D.rectangle(width: try inputs.number("width"), height: try inputs.number("height"),
                                          plane: try inputs.plane("plane"))
        return NodeOutputs(["profile": .profile(profile)])
    }
}

enum PreviewExtrude: NodeDefinition {
    static let typeID = "preview.extrude"
    static let displayName = "Extrude"
    static let category = NodeCategory.solid
    static let inputs = [
        SocketSpec("profile", .profile),
        SocketSpec("distance", .number, defaultValue: .number(6), unit: .millimetres, range: 0...100),
        SocketSpec("mode", .integer, defaultValue: .integer(0)),
        SocketSpec("reversed", .bool, defaultValue: .bool(false)),
    ]
    static let outputs = [SocketSpec("solid", .solid)]
    static let inspector = [
        InspectorSection(title: "Extrude", controls: [
            .segmented("mode", options: ["Distance", "Symmetric"]), .slider("distance"),
            .toggle("reversed", label: "Reverse direction"),
        ]),
    ]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let mode: ExtrudeMode = try inputs.integer("mode") == 1 ? .symmetric : .oneSided
        let solid = try await kernel.extrude(try inputs.profile("profile"), distance: try inputs.number("distance"),
                                             mode: mode, tag: context.tag)
        return NodeOutputs(["solid": .solid(solid)])
    }
}

enum PreviewAllEdges: NodeDefinition {
    static let typeID = "preview.allEdges"
    static let displayName = "All Edges"
    static let category = NodeCategory.selection
    static let inputs = [SocketSpec("solid", .solid)]
    static let outputs = [SocketSpec("edges", .edgeSet)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solid = try inputs.solid("solid")
        return NodeOutputs(["edges": .edgeSet(EdgeSet(solid: solid, edges: solid.topology.edges.map(\.id)))])
    }
}

enum PreviewFillet: NodeDefinition {
    static let typeID = "preview.fillet"
    static let displayName = "Fillet"
    static let category = NodeCategory.feature
    static let inputs = [
        SocketSpec("solid", .solid),
        SocketSpec("edges", .edgeSet),
        SocketSpec("radius", .number, defaultValue: .number(3), unit: .millimetres, range: 0...20),
    ]
    static let outputs = [SocketSpec("solid", .solid)]
    static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.showHandle: .bool(true)]
    static let inspector = [
        InspectorSection(title: "Fillet", controls: [.slider("radius"), .toggle(NodeSetting.showHandle, label: "Show handle in view")]),
        InspectorSection(title: "Edges",
                         controls: [.ruleSummary("edges"), .button(title: "Pick edges in view…", action: .pickEdgesInView)]),
    ]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let radius = try inputs.number("radius")
        guard radius <= 10 else { throw NodeError.invalidValue("Radius \(radius) mm is too large for the selected edges.") }
        return NodeOutputs(["solid": .solid(try inputs.solid("solid"))])
    }
}

enum PreviewTransform: NodeDefinition {
    static let typeID = "preview.transform"
    static let displayName = "Transform"
    static let category = NodeCategory.solid
    static let inputs = [
        SocketSpec("solid", .solid),
        SocketSpec("move", .vector, defaultValue: .vector(.zero), unit: .millimetres),
    ]
    static let outputs = [SocketSpec("solid", .solid)]
    static let inspector = [InspectorSection(title: "Move", controls: [.vector("move")])]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["solid": .solid(try inputs.solid("solid"))])
    }
}

enum PreviewGraphParameter: NodeDefinition {
    static let typeID = "preview.graphParameter"
    static let displayName = "Graph Parameter"
    static let category = NodeCategory.value
    static let inputs: [SocketSpec] = []
    static let outputs = [
        SocketSpec("number", .number, optional: true), SocketSpec("integer", .integer, optional: true),
        SocketSpec("bool", .bool, optional: true), SocketSpec("vector", .vector, optional: true),
    ]
    static let inspector = [InspectorSection(title: "Parameter", controls: [.parameterPicker(NodeSetting.parameter)])]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["number": .number(0)])
    }
}

/// Like M3's Grid Points: `total` is optional with no default, so its field starts empty ("Not set").
enum PreviewGridPoints: NodeDefinition {
    static let typeID = "preview.gridPoints"
    static let displayName = "Grid Points"
    static let category = NodeCategory.value
    static let inputs = [
        SocketSpec("countX", .integer, defaultValue: .integer(2), unit: .count),
        SocketSpec("countY", .integer, defaultValue: .integer(2), unit: .count),
        SocketSpec("total", .integer, unit: .count, optional: true),
    ]
    static let outputs = [SocketSpec("points", .vector)]
    static let inspector = [InspectorSection(title: "Grid", controls: [.integer("countX"), .integer("countY"), .integer("total")])]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(lists: ["points": []])
    }
}

/// Like M3's Output: one `.list` input, passed through.
enum PreviewOutput: NodeDefinition {
    static let typeID = "preview.output"
    static let displayName = "Output"
    static let category = NodeCategory.output
    static let inputs = [SocketSpec("solid", .solid, access: .list)]
    static let outputs = [SocketSpec("solid", .solid)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(lists: ["solid": try inputs.list("solid")])
    }
}
```

`Sources/GraphPanelPreview/PreviewDocument.swift`:
```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// The preview's starting document: a bracket-shaped chain with a parameter, one node of each
/// category and an output, laid out left to right.
enum PreviewDocument {
    static let registry = NodeRegistry([
        PreviewNumber.self, PreviewRectangle.self, PreviewExtrude.self, PreviewAllEdges.self,
        PreviewFillet.self, PreviewTransform.self, PreviewGraphParameter.self, PreviewGridPoints.self,
        PreviewOutput.self,
    ])

    @MainActor
    static func make() -> DocumentModel {
        func node(_ definition: any NodeDefinition.Type, _ x: Double, _ y: Double) -> Node {
            registry.makeNode(definition.typeID, at: Vector2(x, y))
        }
        let rect = node(PreviewRectangle.self, 20, 20)
        let extrude = node(PreviewExtrude.self, 240, 20)
        let edges = node(PreviewAllEdges.self, 460, 140)
        let fillet = node(PreviewFillet.self, 680, 20)
        let output = node(PreviewOutput.self, 900, 20)  // `makeNode` flags `.output` nodes as outputs (M3).
        let number = node(PreviewNumber.self, 20, 220)
        func link(_ a: Node, _ s: SocketName, _ b: Node, _ t: SocketName) -> Link {
            Link(from: Endpoint(node: a.id, socket: s), to: Endpoint(node: b.id, socket: t))
        }
        let graph = Graph(
            nodes: Dictionary(uniqueKeysWithValues: [rect, extrude, edges, fillet, output, number].map { ($0.id, $0) }),
            links: [
                link(rect, "profile", extrude, "profile"), link(extrude, "solid", edges, "solid"),
                link(extrude, "solid", fillet, "solid"), link(edges, "edges", fillet, "edges"),
                link(fillet, "solid", output, "solid"),
            ],
            parameters: [GraphParameter(name: "Width", type: .number, value: .number(60), min: 10, max: 200)])
        return DocumentModel(file: GraphFile(graph: graph, viewState: ViewState(dock: .bottom)),
                             registry: registry, kernel: FakeKernel())
    }
}
```

`Sources/GraphPanelPreview/PreviewRoot.swift`:
```swift
import CreatorEditor
import MetalUI

/// The preview window's content: the window background, the graph panel in its dock and the
/// inspector on the right — the layout the app shell (M6) will float over the viewport.
struct PreviewRoot: Component {
    let model: EditorModel
    let input: GraphPanelInput

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            Palette.backgroundBottom.color
            switch model.dock {
            case .left:
                HStack(alignment: .top, spacing: Pixels(12)) {
                    ZStack { GraphPanel(model: model, input: input) }.frame(width: Pixels(380))
                    Spacer()
                    InspectorPanel(model: model)
                }
                .padding(Edges(all: Pixels(12)))
            case .bottom:
                VStack(spacing: Pixels(12)) {
                    HStack(alignment: .top) {
                        Spacer()
                        InspectorPanel(model: model)
                    }
                    ZStack { GraphPanel(model: model, input: input) }.frame(height: Pixels(300))
                }
                .padding(Edges(all: Pixels(12)))
            case .hidden:
                // Hidden keeps a visible way back: "Show graph" (Tab is its shortcut).
                HStack(alignment: .bottom) {
                    GraphShowButton(model: model)
                    Spacer()
                    InspectorPanel(model: model)
                }
                .padding(Edges(all: Pixels(12)))
            }
        }
    }
}
```

`Sources/GraphPanelPreview/main.swift`:
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
    let window = try app.openWindow(title: "MetalCreator — Graph Panel Preview",
                                    size: Size(width: Pixels(1280), height: Pixels(800))) {
        ZStack { PreviewRoot(model: model, input: input) }
    }
    // Keys through `onInput`, the palette's ↑/↓ as keymap actions (they run before a focused search
    // field claims them), and a canvas press clearing text focus (gap M5-g). `install(on:)` chains
    // onto any handlers already there, as the app shell (M6) needs with the viewport's.
    input.install(on: window)
    app.run()
}

try runPreview()
```

- [ ] **Step 3: Build it and smoke-run it**

Run: `swift build --product GraphPanelPreview 2>&1 | grep -E "error|warning: .*(CreatorEditor|GraphPanelPreview)"`
Expected: no output.

Run: `( "$(swift build --product GraphPanelPreview --show-bin-path)/GraphPanelPreview" & PID=$!; sleep 5; kill $PID && echo still-running )`
Expected: `still-running`, meaning the window opened and the first frames drew without trapping. The window is visible only on an unlocked Mac.

- [ ] **Step 4: Log the MetalUI gaps this milestone hit**

Append to the end of `docs/metalui-gaps.md`, after M4's "Hit by M4 (viewport), 2026-10-08" section (Task 1's pre-flight checked it is there; leave it as it is):
```markdown

## Reported 2026-10-08 (M5 graph panel)

These are labelled M5-a… so they don't clash with the C7 items 1–5 or M4's M4-a… entries in the section above.

- **M5-a. `Slider` has no editing-ended callback** (SwiftUI's `Slider(value:in:onEditingChanged:)`). The inspector
  coalesces a slider drag into one undo step and needs to know when the drag ends. Stopgap: steps share a coalescing
  key; it ends on the next selection change, canvas press, other edit, undo or redo
  (`EditorModel.setInput(_:to:continuous:)`). Two drags of the same slider with nothing between them merge.
- **M5-b. Tab is taken by focus traversal** whenever any focusable control exists, before `Window.onInput` sees it,
  and a `Button` shortcut is the only earlier stage. The graph panel wants Tab to open the add-node palette over the
  canvas and to toggle the hidden panel (spec §6.1, §6.2). Stopgap: Space opens the palette; while hidden,
  `GraphShowButton` carries `.keyboardShortcut(.tab, modifiers: [])`; Tab reaches `GraphKeyBindings` only when nothing
  focusable is on screen. A focus-scoped key binding, or `onKeyPress` on a focus region, would fix it.
- **M5-c. No materials or blur** (`.background(.ultraThinMaterial)`, `.blur(radius:)`). Glass panels over the viewport
  need a backdrop blur (spec §6.1). Stopgap: `#21222c` at 86% opacity with the hairline (`GlassPanel`).
- **M5-d. No gradients.** The window background is a `#3a3d4e` → `#191a21` vertical gradient (spec §6.6). Stopgap:
  solid `#191a21`.
- **M5-e. Modifiers on a press** (adds to gap 5, which M4's entry made concrete). Shift-click and ⇧/⌥-drag on the
  canvas need the modifiers at the press, in the gesture's value. Stopgap: `GraphPanelInput.dragValueModifiers(_:)`
  returns the set `GraphPanelInput.handle(_:)` tracks from `.modifiersChanged`; C7's `DragGesture.Value.modifiers`
  replaces its body. A click's location is `GraphPanelInput.spatialTapGesture()`, a zero-distance drag (gap 4).
- **M5-f. Canvas scroll and pinch** (adds to items 1 and 2). Two-finger scroll should pan the graph canvas and
  ⌘-scroll or pinch should zoom about the pointer (the `location` in the canvas's local points). Stopgap: drag on empty
  canvas pans; +/− keys and the header buttons zoom about the pointer (`EditorModel.zoom(in:)`). With M4's viewport
  in the same window, M4's window-wide keymap takes `=`/`+`/`-` before `onInput` (gap M4-a), so M6 needs a key context.
- **M5-g. A press elsewhere never clears text focus** (focus-by-click is deliberately not MetalUI policy,
  `Window.focus(_:)` docs). After editing an inspector field, the field keeps Delete, ⌘C/⌘V/⌘Z and Space while the
  user clicks nodes, so the graph's keys stop working with no visible cause. Stopgap: the canvas gesture calls
  `GraphPanelInput.releaseTextFocus` (`window.focus(nil)`) at the start of each press. A SwiftUI-like rule (a press on
  non-focusable content resigns the field), or a `.focusable(false)`-style "clears focus" modifier, would fix it.
- **M5-h. A focused single-line field claims ↑/↓** (mac: caret to start/end, `TextEditing.key`) before the raw key
  bubble and `onInput`. The add-node palette needs ↑/↓ to move its highlight while its search field is focused.
  Stopgap: `GraphPanelInput.keymap` binds `up`/`down` to `PaletteMove`, and `handleAction` runs it only while the
  palette is open (the keymap stage precedes field keys). SwiftUI's `onKeyPress` on the field would fix it.
- **M5-i. No keyframe animation.** The refused-wire "brief shake" (spec §6.2) wants a back-and-forth keyframe
  animation. Stopgap: the node's offset jumps 6 pt and springs back (`.animation(.spring(duration:bounce:), value:)`).
```

- [ ] **Step 5: Write the human checks**

M4 created `docs/verification/human-checks.md` with its header and group V (Task 1's pre-flight checked them). Keep
both and only append, after group V and without touching it. The heading and status line follow group V's style:
```markdown

## Group M5 — the graph panel and inspector (M5)

**Status: NOT RUN.** Following MetalUI's convention (`../MetalUI/docs/verification/human-checks.md`).

Run `swift run GraphPanelPreview`.

- [ ] **M5-1 Dracula colours.** Headers are comment-blue (Number), green (Rectangle), purple (Extrude), pink
  (All Edges), orange (Fillet), cyan (Output). Header text is dark (`#282a36`). Body text is near-white, hint text
  blue-grey. Pinned: `PaletteTests`. **Observed:**
- [ ] **M5-2 Selection glow.** Click Extrude: it gets a 2-pt outline and a soft glow in *purple*, its own header
  colour. Click Fillet: the glow is orange. Pinned: `selectionGlowIsTheNodesOwnHeaderColour`. **Observed:**
- [ ] **M5-3 Glass panels.** The panel and inspector are translucent dark with a faint 1-pt light hairline and rounded
  corners (no blur yet, gap M5-c). **Observed:**
- [ ] **M5-4 Wires.** Wires are smooth curves leaving outputs forwards and entering inputs forwards, coloured by the
  source socket (green from Rectangle, purple from Extrude, pink from All Edges). Socket dots use the same colours.
  Pinned: `WireGeometryTests`, `wiresRunBetweenTheirSocketAnchors`. **Observed:**
- [ ] **M5-5 Docks.** Press Left: the graph becomes a column flowing top to bottom, inputs on top edges and outputs
  on bottom edges, the layout a mirror (x↔y) of the bottom dock. Press Bottom: it flows left to right again with
  every node back where it was. Press Hide: the panel goes and a "Show graph" button appears at the bottom left.
  Press Tab (even with an inspector field focused): the panel returns to the last side. Hide again and click "Show
  graph": same. Pinned: `DockTests`, `theHiddenPanelLeavesAShowButton`; the Tab shortcut is this check only.
  **Observed:**
- [ ] **M5-6 Pan, zoom, hit testing.** Drag empty canvas: it pans. Press + three times with the pointer over a node:
  the node stays under the pointer. Click a socket's edge at that zoom and drag: a cyan wire follows the pointer.
  Pinned: `HitTestTests`. **Observed:**
- [ ] **M5-7 Wiring.** Drag Rectangle's output onto Extrude's profile input: a wire is made (it replaces the old one).
  Drag Number's output onto Extrude's profile: nothing connects, Extrude jumps sideways and springs back (a brief
  wobble, gap M5-i), and "A number can't connect to a profile input." shows under the canvas for about two seconds.
  Drag from Extrude's wired profile input onto empty canvas: the wire is removed; ⌘Z brings it back.
  Pinned: `WiringTests`. **Observed:**
- [ ] **M5-8 Box select and ⌥-drag.** Hold ⇧ and drag on empty canvas: a cyan box selects what it touches. Hold ⌥
  and drag a selected node: translucent ghosts follow, and on release copies appear there with their wires; ⌘Z
  removes them in one step. Pinned: `PointerTests`. **Observed:**
- [ ] **M5-9 Palette.** With the pointer over the canvas press Space: a glass palette opens at the pointer with the
  field focused. Type "t", press ↓ twice and ↑ once: the highlight moves down two rows and back one, while the field
  keeps focus (the arrows are window keymap actions, gap M5-h). Press Return: the highlighted node is added there
  and selected. Open it again and type a space: it goes into the field (no second palette). Escape closes it.
  Pinned: `SearchPaletteTests`, `KeyCommandTests`, `paletteArrowsAreKeymapActionsOnlyWhileThePaletteIsOpen`; the
  routing through a focused field is this check only. **Observed:**
- [ ] **M5-10 Inspector.** Select Rectangle: header in green with "Rectangle", Size sliders, a segmented XY/XZ/YZ
  plane picker and a 3×3 anchor grid; Document Parameters below. Drag the Width slider, release, then press ⌘Z
  once: width returns to where the drag started. Select Fillet: an EDGES section reads "All Edges · 12 edges" in
  pink, a "Show handle in view" toggle that starts On, and a "Pick edges in view…" button. Select All Edges: its
  EDGES row reads "12 edges". Drag Radius above 10: Fillet's badge turns to a red ✕ and hovering it shows the message.
  Select Extrude: a Distance/Symmetric segmented control, the Distance slider and a "Reverse direction" toggle that
  starts Off (no Direction menu, spec Errata (M3)).
  Add a Transform (palette): its Move row has three fields; type 5 into the middle one and the node row reads
  "0 mm, 5 mm, 0 mm". Add a Graph Parameter: its menu lists Width; choose it and the menu shows Width.
  Add a Grid Points: its Total field is empty, showing "Not set", and the node row reads "—". Type 6 and press
  Return: the row reads "6". Empty the field and press Return: it's "Not set" again. Click empty canvas and press ⌘Z: 6 comes back.
  Pinned: `InspectorTests` (`anOptionalInputStartsUnsetAndCanBeCleared`), `CoalescingTests`. **Observed:**
- [ ] **M5-11 Keys stay with fields.** Click into the Width number field, type "75" and press Delete: the digit is
  deleted, not the node. Press Return: Width becomes 75 mm. Pinned: design (`Window.onInput` fallback),
  `mappedKeysAreRunAndClaimed`. **Observed:**
- [ ] **M5-12 A canvas press gives the keys back.** Edit the Width number field (type "70", Return), then click the
  Extrude node on the canvas and press Delete: Extrude is deleted (not a character in the field). Press ⌘Z: Extrude
  comes back (the graph's undo, not the field's). Press Space over the canvas: the palette opens. Pinned:
  `aCanvasPressReleasesTextFocusOncePerPress`; the focus release itself is this check only (gap M5-g). **Observed:**
```

- [ ] **Step 6: Record the spec errata**

Append to the end of `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`, after "Errata (M3)" (leave it as it is):
```markdown

## Errata (M5)

- §6.2's "inline value fields" are read-only text on the node's row. Values are edited in the inspector, because a
  `TextField` on the canvas would compete with the canvas-wide gesture and split keyboard focus (§9's risk list).
  Revisit when MetalUI C7 lands.
- §6.1/§6.2's ⇥ is contextual: Tab opens the add-node palette while the pointer is over a visible canvas, and
  otherwise toggles the hidden panel. Space always opens the palette. While the panel is hidden, a "Show graph"
  button carries Tab as its shortcut, so hiding is never a one-way trip.
- §6.4's inspector also clears an optional input: emptying its field unsets it (for example Grid Points `total`).
- §6.1/§6.6's glass blur and the window gradient wait for MetalUI. Panels are `#21222c` at 86% with the hairline,
  and the preview's background is solid `#191a21` (docs/metalui-gaps.md M5-c, M5-d).
- §6.2's refusal shake is a spring back from a 6-pt offset (no keyframe animation yet, M5-i).
```

- [ ] **Step 7: Update `CLAUDE.md` and `AGENTS.md` (both, same edits)**

In the "Module boundaries (dependency order)" list, add this after M4's `CreatorViewport` bullet (which follows M3's `CreatorNodes`). Edit in place; don't rewrite the section:
```markdown
- `CreatorEditor`: the graph panel and context inspector on MetalUI. `@MainActor @Observable EditorModel` holds all
  behaviour (selection, canvas transform, dock transpose, hit testing, wiring, clipboard, palette, inspector edits);
  views are thin MetalUI `Component`s. Depends on Graph/Kernel/Geometry and MetalUI — **not** on `CreatorNodes`.
  Stopgap input (pending MetalUI C7) lives only in `GraphPanelInput`.
```
Add to the rules paragraph: "Editor geometry is computed by `NodeLayout`, never measured; views are framed to it so
drawing and hit testing agree. Node positions are stored left-to-right; the left dock draws their transpose.
Graph panel input stopgaps live only in `GraphPanelInput`. Each C7 stand-in is one function named after its
provisional C7 API (`spatialTapGesture()`, `dragValueModifiers(_:)`), and `install(on:)` chains onto the window's
existing handlers."

In "Project state", after M4's sentence ("M4 (viewport) code is done; its human checks … are pending."), add "M5 (graph panel and inspector) code is done; its human checks (group M5 in `docs/verification/human-checks.md`) are pending." Don't add M5 to the done list: spec §7.4's M5 exit includes the human visual check, as M4's does. The controller moves it once group M5 is ticked.

Under "Commands", add:
```sh
swift test --filter CreatorEditorTests       # editor model + headless render tests
swift run GraphPanelPreview                   # graph panel + inspector, for docs/verification/human-checks.md (M5)
```

- [ ] **Step 8: Update the roadmap and the carry-over note**

In `docs/superpowers/roadmap.md`, edit the M5 row's status cell in place to `🔄 code done; human checks M5 pending` (the controller sets ✅ once group M5 is ticked, as for M4). Add this line under "Carry-over items with a milestone", after the `Before M4:` line and before the existing `- M7:` line:
```markdown
- M6: install the graph's input with `GraphPanelInput.install(on:)` (it chains `onInput`/`onAction` and appends its
  keymap). Only its `onInput` side composes with M4's `ViewportModifierTracker.install(on:)` in either order: set the
  viewport's keymap and `onAction` (which M4's harness assigns directly) before `install(on:)`, or append and chain
  them the same way, or the palette's ↑/↓ bindings and `handleAction` are dropped. Call `releaseTextFocus` on viewport
  presses too; give M4's viewport keymap bindings a key context (gap M4-a), because window-wide `=`/`+`/`-` bindings run
  before `onInput` and take the graph's zoom keys; place `GraphPanel` per `EditorModel.dock`,
  `GraphShowButton` while hidden, and `InspectorPanel` on the right over the viewport; consume
  `EditorModel.inspectorRequest` for "Pick edges in view…" (write the picks as `.edgePicks(…)` under `NodeSetting.picks`);
  pass the real `BuiltInNodes.registry`. Deferred to M6 from spec §6.1/§6.2:
  resizing the docked panel along its inner edge, and the Preview menu (Final / Selected node →
  `document.previewNode`). M7: measure 50-node pan/zoom (CanvasLayers is the hot path; add viewport culling there if
  it misses 60 fps).
```

Then append to `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`:
```markdown

## From M5
- Inline node values are read-only text (spec §6.2 says "inline value fields"); editing is in the inspector, because
  a canvas `TextField` would fight the canvas-wide gesture and split keyboard focus. Revisit when MetalUI C7 lands.
- Inspector settings rule: a control naming a non-socket is a setting (`NodeSetting`); new nodes carry their seeded
  `defaultSettings`, and a setting toggle with nothing stored reads On; `.parameterPicker` writes M3's
  `ConstantValue.parameter(id)` and reads `.parameterID` (one encoding, in CreatorGraph).
- `Palette` (CreatorEditor) and M4's `ViewportPalette` (CreatorViewport) hold the same spec §6.6 hex values; neither
  target may import the other, so M6 picks a shared home.
- CreatorGraph messages read `needs a \(type.rawValue)` ("needs a integer", "needs a edgeSet") in `Graph+Commands`,
  `NodeError` and `Evaluator`; give them the editor's `SocketType.indefiniteName` wording in one pass.
- Numbers are shown and parsed in `en_US_POSIX`; localised number entry is deferred with string localisation.
- Only the key mapping is unit-tested (MetalUI's `Window` init is internal); real-window routing is human checks
  M5-5, M5-9, M5-11, M5-12, and `GraphPanelInput.install(on:)` is untested glue. If MetalUI exposes a test window, add
  dispatch tests.
- Optional inputs with no default (Grid Points `total`, Edge Filter `maxLength`, Transform `axisDirection`) start
  unset ("Not set" in the inspector, "—" on the node row); emptying the field clears them (`EditorModel.clearInput`).
  Required inputs are never cleared.
- C7 swap points in `GraphPanelInput`: `spatialTapGesture()` → `SpatialTapGesture` (a return-type change, so
  `canvasGesture()` becomes a tap plus a nonzero-distance drag and its stand-in test is rewritten), `dragValueModifiers(_:)` →
  `DragGesture.Value.modifiers` (body-only; then `handle(_:)` stops tracking `.modifiersChanged`), and scroll/pinch get new
  handlers (`.onScrollWheel`, `MagnifyGesture`); the +/− keys and header buttons stay.
- With M4's viewport in the same window, M4's window-wide `=`/`+`/`-` keymap bindings win over the graph's zoom keys
  (keymap runs before `onInput`); M6 scopes the viewport's with a key context (gap M4-a).
```

- [ ] **Step 9: Run everything and commit**

Run: `swift test`
Expected: every target PASSES (including M3's `CreatorNodesTests` and M4's `CreatorViewportTests`). `CreatorEditorTests` reports `Test run with 123 tests in 18 suites passed`.

```bash
swiftlint lint --strict   # must report 0 violations before committing (CLAUDE.md "Linting")
git add Package.swift Sources/GraphPanelPreview docs/metalui-gaps.md docs/verification/human-checks.md CLAUDE.md AGENTS.md \
        docs/superpowers/roadmap.md docs/superpowers/notes/2026-10-07-m0-m1-carryover.md \
        docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md
git commit -m "feat(editor): graph panel preview, M5 MetalUI gaps, errata and human checks"
```

---

## What comes next

- **M6, the app shell:** float `GraphPanel` (left column or bottom strip, per `EditorModel.dock`), `GraphShowButton` (while hidden) and `InspectorPanel` (right) over the viewport. Install the graph's input with `GraphPanelInput.install(on:)` after setting the viewport's keymap and `onAction` (only the `onInput` chaining is order-free; assigning a keymap or `onAction` afterwards drops the graph's palette arrows), and give the viewport's keymap bindings a key context so `=`/`+`/`-` reach the graph when it has the pointer (gap M4-a). Wire undo, redo and export to the top bar. Route `EditorModel.inspectorRequest` into the viewport's pick mode. Two spec §6.1/§6.2 items belong to the shell and are deliberately not in M5: resizing the docked panel along its inner edge (a drag handle that sets the panel's width or height), and the Preview menu (Final / Selected node), which in Selected-node mode sets `document.previewNode` from `EditorModel.selection`.
- **When MetalUI C7 lands:** replace the stopgaps inside `GraphPanelInput` only (plus `GraphShowButton`'s Tab shortcut and `PaletteMove` if MetalUI gains focus-scoped key handling, gaps M5-b and M5-h). First check the final spellings in MetalUI's C7 decisions file (`docs/superpowers/2026-10-08-input-apis-decisions.md`, prefix CI-). Each swap is local:
  - Make `spatialTapGesture()` return a `SpatialTapGesture` for clicks. This changes its return type, so `canvasGesture()` splits into that tap plus a `DragGesture` with a nonzero minimum distance, and `theC7StandInsAreTheirOwnFunctions` drops its `minimumDistance == Pixels(0)` check.
  - Make `dragValueModifiers(_:)` return `Self.canvasModifiers(value.modifiers)` (a body-only change: C7's `EventModifiers` is a typealias of `Modifiers`), and drop the `.modifiersChanged` tracking in `handle(_:)`.
  - Add `.onScrollWheel` for canvas pan and ⌘-zoom, and `MagnifyGesture` for pinch, about the event's local location.
  - Optionally set `.pointerStyle(_:)` (grab while panning).
- **M7:** measure 50-node pan and zoom at 60 fps (spec §7.3).
