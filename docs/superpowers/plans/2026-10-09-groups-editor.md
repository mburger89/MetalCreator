# Groups editor (C2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The groups editor of the groups spec §6: a group node drawn with its definition's name and a doubled accent border; entering it (double click, ⌘↓, "Edit Group"), breadcrumbs and ⌘↑ back out, each level with its own pan and zoom; editing inside through the existing graph commands addressed to the level's graph path; Group Input and Group Output with a "+" socket that exposes a socket when a wire meets it; the group inspector; the library's "Groups" section; the viewport, handles and picking on the level shown; the clipboard carrying definitions, merged by content; and inner node states from `DocumentModel.innerResults`.

**Architecture:** A *level* is the list of group nodes entered from the top level (`EditorModel.levelPath`, each by its ID in the graph before it), never a definition, so a definition used twice shows the entered instance's states. `EditorModel.graph` becomes the level's graph, which keeps every reader (hit testing, drawing, selection, the inspector, framing) unchanged, and every edit goes through `EditorModel.edit(_:)`, i.e. `DocumentModel.perform(_:at:)`, so one command is one undo step. `DocumentModel.inspectedLevel` makes the evaluator run every node of the level shown (their states are `innerResults`), without letting a node nothing reads change its group node's result. Group Input/Output's "+" is an ordinary untyped socket named `"+"` in `NodeShape`, so hit testing and wire drags need no new case; a wire meeting it is turned into one `GroupCommands.exposeOutput/exposeInput` command. A pick made in the viewport inside a group is renamed by `GraphContent.relativeToLevel` before it is stored, the inverse of `EvaluationScope.naming`. The graph panel carries out a group node's Edit Group, Make Unique and Ungroup itself (they are `InspectorAction`s declared by `GroupNode.inspector`), and S5b's double-click recogniser presses Edit Group; there is no second recogniser.

**Tech Stack:** Swift 6.4 (strict concurrency), SwiftPM, Swift Testing, MetalUI (existing `Button`, `Picker`, `TextField`, `List`; no new use), `FakeKernel` in the tests (no OCCT needed).

**Spec:** `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` §6 (with §5's commands, §8, §9, §10 and Errata (C1), which hands C2 the items this plan builds), under `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` with all its Errata. Reference for behaviour (read-only): `/Users/maxburger/Developer/MetalNodes`, `MetalNodesKit/Sources/MetalNodesUI/Editor/EditorModel+Groups.swift`, `MetalNodesCore/Groups/*` and its spec §20.

**Base:** branch `groups-editor` off master `4e4be6e` (1643 tests), beside `../MetalUI`. Run every command from the worktree root.

**Files shared with other tracks.** Checked on 2026-10-10 against the committed state of every other worktree (`git diff 4e4be6e HEAD`): adopt-c10 and viewport-final-edges already touch plan-edited files, the rest (groups-comments, sketcher-s5c, naming-face-picks, kernel-blend-max) have no commit on them yet, so their rows are what the spec and their plans say they will touch. The side that merges second keeps both sides unless a row says otherwise:

| File | Shared with | What the second merger keeps |
|---|---|---|
| `Sources/CreatorEditor/EditorModel+Editing.swift`, `NodeClipboard.swift` | groups-comments (B) | B adds comments to `clipboard(of:)`, `insert(_:offset:)`, `deleteSelection()` and `NodeClipboard` (spec Errata (A) lists them): keep this plan's boundary filter (`GroupNodes.isBoundary`), `GroupMerge` plan (additions first, then the nodes at `graphPath`), `definitions`, and B's comment lines beside them; `edit(_:)` replaces `document.perform(_:)` in each. |
| `Sources/CreatorEditor/EditorModel+Pointer.swift` | B | B's resize case in `update`, `pointerReleased` and `cancelInteraction()` stays. This plan moves `pairClick` after `click(...)` in the `case nil` branch, adds the `isPlus` branch to `finishWire`, and routes `document.perform` through `edit`. |
| `Sources/CreatorEditor/CanvasLayers.swift` | B, adopt-c10 (committed) | One line: `state: model.result(of: node.id)?.state` replaces `model.document.results[node.id]?.state`. That line sits directly above C10's `shakes: model.shakeCount(of: node.id)` (replacing `shake: model.isShaking && …`), so the two hunks touch neighbouring lines: keep both lines. B's comment layers and C10's looks stay. |
| `Sources/CreatorEditor/EditorModel.swift` | B, adopt-c10 (committed) | `graph`, `transform` and the stored properties `enteredGroups`/`levelTransforms`/`isLevelLocked` change; B's `canvasSelection` additions stay. C10 replaces `isShaking` with `shakeCounts` and adds `shakeCount(of:)` and edits `refuse`/`clearRefusal` (all of it a few lines below this plan's property hunk): keep C10's. |
| `Sources/CreatorEditor/NodeView.swift`, `NodeShape.swift` | adopt-c10 (committed: `NodeView.shake: Double` becomes `shakes: Int`, with a `keyframeAnimator`) | C10's look changes stay; keep `shape.accent`/`shape.isGroup` (the header colour and the second, inner ring). **`GroupLookTests.aGroupNodeDrawsADoubledBorderInItsAccent` calls `NodeView(… state: nil, shake: 0)`: whichever side merges second changes that call to C10's `shakes: 0`** (a compile error otherwise, in the test target only). |
| `Sources/CreatorEditor/EditorModel+Inspector.swift` | B (comment inspector), adopt-c10 (committed: `sliderEditingChanged`, and the doc comment of `setInput`) | `inspectorPage` fills `page.group`; `press(_:on:)` switches over every `InspectorAction`. This plan's `setInput` hunk (it routes through `edit`) neighbours C10's rewritten doc comment and its new `sliderEditingChanged(_:)`: keep both. B's comment page stays. |
| `Sources/CreatorEditor/InspectorPage.swift`, `InspectorPanel.swift` | B (comment inspector), adopt-c10 | The panel draws `GroupPanelView` under the header; B's comment page and C10's looks stay. |
| `Sources/CreatorEditor/GraphKeyCommand.swift`, `GraphKeyBindings.swift`, `EditorModel+Commands.swift` | B (⌘⇧N, ⌘⇧C) | Both add cases to the same enum and switches; keep all. |
| `Sources/CreatorEditor/GraphPanelHeader.swift`, `NodeLibraryView.swift`, `LibraryRow.swift`, `LibrarySectionHeader.swift`, `PaletteEntryLabel.swift` | adopt-c10 (looks; none of these in its commits yet) | C10's look changes stay; keep `BreadcrumbBar` in the header and the Groups rows. |
| `Sources/CreatorEditor/Palette+Accent.swift` (new) | B | One `Palette.accent(_ role: AccentRole)`. If B added its own mapping first, keep B's and delete this file (the group tests only need seven distinct colours per theme: `eachAccentRoleIsItsOwnColourInEveryTheme`). |
| `Sources/CreatorEditor/EditorModel+DoubleClick.swift`, `EditorModel+Nudge.swift`, `EditorModel+Library.swift`, `LibraryItem.swift`, `PaletteEntry.swift`, `PendingEntry.swift`, `Sources/CreatorApp/AppModel+Undo.swift`, `Sources/CreatorGraph/Groups/GroupNode.swift` | only this track | No other track's branch touches them. B extends `EditorModel+Selection` (not `+Nudge`) for comments that move with the selection. **S5c's owner: Key decision 9 changes S5b's double-click order for Sketch nodes too (`pairClick` runs after the click it ends on, so the node is selected first and the sketch opens second); S5c's tests that pin the old order change with it.** |
| `Sources/CreatorGraph/InspectorAction.swift` | naming-face-picks | New cases only (`editGroup`, `makeUnique`, `ungroup`); keep theirs. |
| `Sources/CreatorApp/AppModel+Picking.swift`, `AppModel+Scene.swift`, `AppModel+Viewport.swift`, `PickSession.swift`, `AppModel.swift` | naming-face-picks (face picks), viewport-final-edges (committed: `AppModel+Scene.refreshScene`), sketcher-s5c | This plan reads `editor.graph`/`levelResults` where these read `document.graph`/`results`, writes picks through `relativeToLevel` and `document.perform(_:at:)`, adds `PickSession.level`, and gives `AppModel.sketch` a `didSet` that locks the level shown. Keep their new code and read the level the same way. **viewport-final-edges** has changed the Final branch of `refreshScene` to `SceneBuilder.scene(… selection: editor.selection, showsGuides: previewMode == .final && sketch == nil)`; this plan moves that call into `shownScene()`'s `.final` branch, so the second merger carries `showsGuides: previewMode == .final && sketch == nil` into that branch (and adds `SceneBuilder`'s parameter from final-edges). Guides come from the selected rules' results; inside a group that branch passes `selection: []`, so no guides are drawn there, which is the intended behaviour (the guided rules are not top-level nodes). S5c rewrites `AppModel+Sketch.swift`, which this plan does not touch: its `handle(.editSketch)` guard here refuses a sketch inside a group until S5c makes sketch mode level-aware, and an open sketch locks the level (`isLevelLocked`). |
| `Sources/CreatorGraph/Evaluator.swift`, `DocumentModel.swift`, `Groups/EvaluationSetup.swift`, `Groups/Evaluator+Groups.swift` | naming-face-picks (possible) | The `inspecting:` parameter and `inspectedLevel` are additions; keep them with any naming change. |
| `CLAUDE.md`, `docs/superpowers/roadmap.md`, `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md`, `docs/verification/human-checks.md` | every track (adopt-c10, kernel-blend-max, naming-face-picks and viewport-final-edges already edit the first three and the checks) | Each appends its own lines/sections (Errata (C2), group GR); keep all. |

## Global Constraints

- Platforms `.macOS(.v26)`; `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`: data races are compile errors. No `@unchecked Sendable`, no `nonisolated(unsafe)`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), never XCTest.
- `swiftlint lint --strict` reports zero violations after every task; a `swiftlint:disable` carries its reason.
- No force unwraps and no force `try`; no Grand Central Dispatch; numbers shown to people use FormatStyle.
- One type per file; behaviour in `@MainActor @Observable` models (`EditorModel`, `DocumentModel`, `AppModel`), views thin MetalUI `Component`s; editor geometry stays computed (`NodeLayout`, `GraphPanelLayout`).
- Create nodes only through `NodeRegistry.makeNode` (group nodes through `makeGroupNode`).
- Every command is one `DocumentModel.perform` step, so one undo step (spec §5); a command addressed by graph path stays one step.
- Spec wording, verbatim: "Graph › Rib › Hole pattern" (breadcrumbs); "Used N times"; "Edit Group", "Make Unique", "Ungroup"; "An Output node can't go in a group."; Make Unique copies as "Name 2"; the library section is "Groups".
- The canvas double-click is S5b's recogniser (0.4 s, 4 pt, no modifiers; gap S5-b/GI-a, MetalUI C16): reuse `doubleClickActions`/`nodeDoubleClicked`, never a second recogniser.
- MetalUI gaps are logged in `docs/metalui-gaps.md` (entry and summary-table row) and never worked around. Never edit `Package.swift`'s MetalUI path; never modify `../MetalUI`.
- Selection stays view state: never undone, not saved. The level shown is view state too.
- A full `swift test` passes only if its exit code is 0, no line says "recorded an issue" or "failed after" (Swift Testing prints glyphs, not ✘), and 11 "Test run with" lines appear.
- No new compiler warning (master's one, `ContextMenuTests.swift:96`, stays; so do the linker's "built for newer macOS" lines).
- End each commit message with the attribution trailer your session gives, if any.

## Review Focus

Inputs the spec implies but no rule above names, most likely to bite first; each has its test:

1. **Two instances of one definition**: inside, the panel shows the states of the instance entered, not the other's: `EditorLevelReviewTests.insideASharedDefinitionTheStatesAreTheEnteredInstances` (Task 12).
2. **A pick made inside one instance** must hold for the others (it is stored the way the definition names faces): `GroupPickInstancesTests.aPickMadeInsideOneInstanceChamfersTheOtherToo` (Task 12), `GroupViewportTests.aPickMadeInsideAGroupIsWrittenRelativeToTheLevel` (Task 11), `GroupLevelTests.aPickIsWrittenRelativeToTheLevelShown` (Task 1).
3. **Undo while inside** that removes the group node entered: the panel falls back to the level around it with nothing selected, also through `AppModel.undo()` and the ⌘Z key: `EditorLevelTests.undoingTheGroupWhileInsideFallsBackToTheLevelAround` (Task 4), `EditorGroupEntryTests.undoingTheGroupFromInsideLeavesTheGroup` (Task 5), `GroupViewportTests.undoFromInsideAGroupAfterTheGroupWasUndoneLeavesIt` (Task 11).
4. **A number typed in the inspector, not yet committed, when the level changes** is committed to the node it was typed for, not looked up in the new level: `EditorLevelReviewTests.aValueTypedBeforeEnteringIsCommittedToTheNodeItWasTypedOn` (Task 12).
5. **Delete, copy and duplicate with Group Input or Group Output selected** (⌘A, Delete inside a group) leave them alone and say why when nothing else was selected; they are not copied: `EditorGroupClipboardTests.groupInputAndOutputAreNeverCopiedDuplicatedOrDeleted`, `deletingOnlyTheBoundaryExplainsWhyNothingHappened` (Task 6).
6. **Pasting or placing a group into its own definition** is refused with "A group can't contain itself." and changes nothing, imported definitions included: `EditorGroupClipboardTests.aGroupCantBePastedIntoItself`, `LibraryGroupsTests.aGroupCantBePlacedInsideItself` (Tasks 6, 10).
7. **An Output node added inside a group** (palette, library) is refused with the spec's sentence: `EditorLevelReviewTests.anOutputNodeAddedInsideAGroupIsRefusedWithTheSpecsSentence` (Task 12).
8. **Entering or leaving during a drag** does nothing (and the key is claimed), so a move stays one undo step: `EditorLevelReviewTests.theLevelDoesntChangeUnderADragInProgress` (Task 12).
9. **Entering or leaving while a sketch is open** does nothing, so `refreshSketch` and `finishSketch` keep reading the top level they were opened on: `EditorLevelTests.aLockedLevelCantBeEnteredOrLeft` (Task 4), `GroupViewportTests.anOpenSketchHoldsTheLevelShown` (Task 11).
10. **A pick inside a group in Final preview** starts from a node of the level shown, never a top-level endpoint or Group Output: `GroupViewportTests.inFinalPreviewAPickStartsFromANodeOfTheLevelShown` (Task 11).
11. **Pasting the same clipboard twice, or after the definition was renamed**, adds no second copy of the definition: `GroupMergeTests.theSameStaleClipboardPastedTwiceAddsOneCopy`, `EditorGroupClipboardTests.pastingTheSameStaleCopyTwiceAddsItsDefinitionOnce` (Tasks 3, 6).

## Key decisions

1. **A level is an instance path.** `levelPath` is the group nodes entered; `DocumentModel.innerResults` is keyed the same way, so a shared definition shows the entered instance's states. Not saved in the file (see User decisions).
2. **`EditorModel.graph` is the level's graph**, and all edits go through `edit(_:)`. The document's parameters live on the top level and show at every level (`graphWithDocumentParameters`), because the evaluator hands every level the top level's parameters.
3. **Evaluate the whole level shown** (`DocumentModel.inspectedLevel`), so every inner node has a state and a preview even when nothing reads it. The group node's own result, errors and warnings come only from what feeds Group Output (`inspectedNodes`, `feeding` in `evaluateGroup`). Cost: dead-end nodes in the level shown are evaluated; they are cached like any node.
4. **Edit Group, Make Unique and Ungroup are inspector buttons** (`InspectorAction`), declared by `GroupNode.inspector`, so "Edit Group in its inspector" and the double click share one path (`doubleClickActions = [.editSketch, .editGroup]`). The panel carries the three out itself; the app never sees them.
5. **The "+" is a socket named "+"** (reserved) in `NodeShape`; no new `CanvasHit` case, so B's `items(for:)` is untouched. Dropping works either way round and is one `GroupCommands.expose…` command, one undo step.
6. **A group row in the library is a key** (`group:<uuid>`) through the library's one gesture, so click and drag need no second gesture.
7. **The clipboard merges by content** (`GroupMerge`): a definition equal to a carried one ignoring ID and name (accent, sockets and inside) is reused, whatever its ID or name, so pasting a stale clipboard twice, or after a rename, makes no second copy; absent adds as it is; a taken ID or name with other content comes in as "Name (imported)" (a fresh ID when the ID was taken); a definition that places a copied one is copied too. Additions and nodes are one undo step.
8. **Sketch mode stays top-level only.** "Edit sketch" inside a group says so, and an open sketch holds the level shown (`EditorModel.isLevelLocked`, set by `AppModel.sketch`'s `didSet`): ⌘↓, ⌘↑, a breadcrumb and Edit Group do nothing meanwhile. S5c rewrites `AppModel+Sketch.swift`; making it level-aware belongs after S5c.
9. **The double-click recogniser is unchanged** apart from running its action after the click it ends on (`pairClick` after `click(...)`), so entering a group doesn't leave the group node "selected" in a level it isn't in.
10. **Per-level pan and zoom live in the model** (`levelTransforms`), not in `ViewState`: no format change. A level entered for the first time frames its nodes (F's framing).

## User decisions

**Decided: all 15 as the recommended defaults (approved 2026-10-09/10; recorded in the spec's Errata (C2)).** Product behaviour the spec left open. Each had a recommended default, which the plan builds:

1. **Sketches inside a group.** Default: "Edit sketch" there refuses with "Sketches inside a group can't be edited yet. Edit it before grouping, or from the top level." Options: (a) refuse until S5c lands (recommended: sketch mode reads the top level's graph in about ten places and S5c is rewriting that file); (b) make sketch mode level-aware in this plan (a merge fight with S5c).
2. **Saving the level and per-level pan and zoom.** Default: not saved; the file opens on the top level, and levels remember their view while the document is open. Options: (a) not saved (recommended: no format change, and `ViewState` is shared with B); (b) save them in `ViewState` as optional keys (no version bump needed).
3. **A mouse way to Group.** The spec says "Group in the context menu", but the graph canvas has no context menu. Default: keys only (⌘G, ⇧⌘G) plus the group node's Ungroup button. Options: (a) keys only now (recommended); (b) a "Group" button in the inspector when several nodes are selected; (c) build a canvas context menu (MetalUI offers right-click menus in the viewport; the canvas needs C9's key and focus scoping for a tidy one).
4. **How a dropped "+" names and defaults the new socket.** Default: named after the source or target socket (made unique: "sum", "sum2"); an input keeps its target's unit, range and default. Option: a zero default for every type (MetalNodes' choice). Recommended: keep the target's default, so the part doesn't change when a literal is promoted to an input.
5. **Evaluate the whole level shown** (Key decision 3). Option: only the selected node and what it needs (cheaper in a big group, but unselected dead-end nodes then show no badge). Recommended: the whole level.
6. **Esc and levels.** Default: Esc never leaves a group (it keeps its jobs: palette, drag, selection); leave with ⌘↑ or the breadcrumbs, as the spec says. Option: Esc with nothing to cancel leaves the level.
7. **Copies of a changed definition on paste** are named "Name (imported)" (MetalNodes' word). Options: keep (recommended); name them "Name 2" as Make Unique does.
8. **"Used N times"** reads "Used 1 time" for one and "Used 0 times" for none. Option: the spec's literal "times" for one too (recommended against).
9. **Accent picker** is a menu of the seven role names (Purple, Green, …). Option: swatches in the theme's colours (needs a small custom control).
10. **A rename after copying.** Default: pasting never makes a copy for a rename alone; the node uses the renamed definition (the match ignores ID and name, so a second paste of a stale clipboard reuses the first paste's copy too). Options: (a) ignore name (recommended: a rename is not an edit of the part, and no paste litters the document); (b) a rename counts as other content, so the paste comes in as "Name (imported)" (the spec's wording read literally: "equal content"). An accent change or any edit inside is other content under both.
11. **Group Input and Group Output can't be copied, duplicated or deleted** (only moved), and Delete with only them selected says "A group's Group Input and Group Output can't be deleted." Options: (a) as built (recommended: a group always has exactly one of each, and the spec says nothing of copying them); (b) allow copying them (a second Group Input would be a hand-edited file's shape, which C1 refuses); (c) Delete with only them selected stays silent.
12. **A pick under way is cancelled when the level changes.** Options: (a) cancel (recommended: the pick's rule, source and consumer are nodes of the level it began on); (b) keep it, and write to the level it began on while another is shown (the banner would then name nodes the panel doesn't show).
13. **Undo and Redo may change something inside a level that isn't shown.** ⌘Z at the top level undoes an inner edit made earlier; the panel falls back to the level around only when the group node entered disappears. Options: (a) leave it (recommended: it matches how undo works for a selection or a pan the user has moved away from, and the part in the viewport shows the effect); (b) navigate the panel to where the undone edit was (needs each undo step to record its level, and moves the user's view without being asked).
14. **The double-click recogniser runs after the click it ends on** (Key decision 9). That changes S5b's order for Sketch nodes too: the node is selected first and the sketch opens second. Options: (a) as built (recommended: entering a group must not leave its node "selected" in a level it isn't in, and a sketch is unaffected apart from the selection landing first); (b) keep S5b's order for sketches and use the new order for groups only (two code paths in one recogniser). The sketcher-s5c owner should know; see the shared-files table.
15. **Groups in the palette (Space).** Default: not listed there, only the library lists them. Options: (a) library only (recommended: the palette is for new node types, `NodeRegistry.all` leaves group types out on purpose, and a definition's name is not a type to search); (b) list definitions in the palette too (the same `group:<uuid>` keys as the library).

## MetalUI gaps

None new. The canvas double-click is the known GI-a/S5-b (spec §8, MetalUI C16); the window-wide key stopgap (M5-b, C9) carries ⌘↓/⌘↑ like every graph key; clicking away from a text field is handled by `PendingEntry` as for numbers (M5-g). `docs/metalui-gaps.md` is unchanged.

## File structure

New files (one type per file), by task:

| File | Responsibility | Task |
|---|---|---|
| `Sources/CreatorGraph/Groups/GraphContent+Levels.swift` | `path(entering:)`, `existingLevels`, `relativeToLevel` | 1 |
| `Sources/CreatorGraph/Groups/GroupCommands+Expose.swift` | the "+" drop as one command | 3 |
| `Sources/CreatorGraph/Groups/GroupMerge.swift` | the clipboard's definitions and their merge | 3 |
| `Sources/CreatorEditor/Breadcrumb.swift`, `EditorModel+Levels.swift` | levels in the editor | 4 |
| `Sources/CreatorEditor/EditorModel+Expose.swift`, `Palette+Accent.swift` | wires on "+", accent colours | 7 |
| `Sources/CreatorEditor/BreadcrumbBar.swift` | the header's breadcrumbs | 8 |
| `Sources/CreatorEditor/GroupPanel.swift`, `GroupPanelView.swift`, `GroupSocketRowView.swift`, `TextEntry.swift`, `EditorModel+GroupInspector.swift` | the group inspector | 9 |
| `Sources/CreatorEditor/GroupLibraryEntry.swift` | a definition in the library | 10 |
| `Tests/CreatorGraphTests/Groups/GroupLevelTests.swift`, `InspectedLevelTests.swift`, `GroupExposeTests.swift`, `GroupMergeTests.swift` | graph tests | 1–3 |
| `Tests/CreatorEditorTests/Support/GroupedEditor.swift`, `EditorLevelTests.swift`, `EditorGroupEntryTests.swift`, `EditorGroupClipboardTests.swift`, `GroupLookTests.swift`, `ExposeSocketTests.swift`, `BreadcrumbRenderTests.swift`, `EditorGroupInspectorTests.swift`, `LibraryGroupsTests.swift`, `EditorLevelReviewTests.swift` | editor tests | 4–10, 12 |
| `Tests/CreatorAppTests/GroupViewportTests.swift`, `GroupPickInstancesTests.swift` | app tests | 11, 12 |

Modified files are listed in each task's **Files**. Code blocks are complete: a **Create** block is the whole file; a **Modify** block is a unified diff against the file as the previous task left it (apply it with `git apply`, or make the same edits by hand).

## Tasks

| # | Task | Tests after |
|---|---|---|
| 1 | Levels, the + name and the group inspector buttons (CreatorGraph) | master + 6 = 1649 |
| 2 | Evaluating the level the panel shows | master + 13 = 1656 |
| 3 | Exposing sockets and merging definitions (CreatorGraph) | master + 25 = 1668 |
| 4 | Levels in the editor: enter, leave, breadcrumbs, edits at the level | master + 38 = 1681 |
| 5 | Entering by ⌘↓, double click and Edit Group; leaving by ⌘↑; group commands at the level | master + 46 = 1689 |
| 6 | The clipboard carries definitions; Group Input and Output stay put | master + 57 = 1700 |
| 7 | The look: accent header, doubled border, + sockets and dropping wires on them | master + 68 = 1711 |
| 8 | Breadcrumbs in the panel header | master + 70 = 1713 |
| 9 | The inspector for a group node and for Group Input and Output | master + 82 = 1725 |
| 10 | The library's Groups section | master + 93 = 1736 |
| 11 | The viewport inside a group (CreatorApp) | master + 104 = 1747 |
| 12 | Review pins and docs | master + 110 = 1753 |

---

### Task 1: Levels, the + name and the group inspector buttons (CreatorGraph)

The small pieces of `CreatorGraph` the editor stands on: which graph a list of entered group nodes reaches (`path(entering:)`), which of them still exist after an Undo (`existingLevels`), a pick written relative to the level shown (`relativeToLevel`, the inverse of `EvaluationScope.naming`, which the Errata (C1) hand to C2), the reserved name of the "+" socket, and the three inspector buttons of a group node (`InspectorAction.editGroup`, `.makeUnique`, `.ungroup`). `AppModel.handle(_:)` gets a case for them (the panel carries them out, so it is never reached). One existing test learns that a group node's first inspector section is now "Group".

**Files:**
- Modify: `Sources/CreatorApp/AppModel+Picking.swift`
- Create: `Sources/CreatorGraph/Groups/GraphContent+Levels.swift`
- Modify: `Sources/CreatorGraph/Groups/GroupNaming.swift`
- Modify: `Sources/CreatorGraph/Groups/GroupNode.swift`
- Modify: `Sources/CreatorGraph/InspectorAction.swift`
- Modify: `Tests/CreatorEditorTests/GroupSocketDisplayTests.swift`
- Create: `Tests/CreatorGraphTests/Groups/GroupLevelTests.swift`

**Interfaces:**
- Consumes: `GraphContent.graph(at:)`, `GroupScopes.paths(in:definitions:entered:)`, `GroupScopes.identity(_:)`, `ConstantValue.renamingTags(_:)`, `NodeID.scoped(_:)` (all C1).
- Produces:
  - `GraphContent.path(entering levels: [NodeID]) -> GraphPath?`: `.root` for `[]`; `nil` when a step is not a group node of an existing definition.
  - `GraphContent.existingLevels(_ levels: [NodeID]) -> [NodeID]`: the longest start that still exists.
  - `GraphContent.relativeToLevel(_ value: ConstantValue, levels: [NodeID]) -> ConstantValue`.
  - `GroupNaming.plusSocket: SocketName` (`"+"`), reserved by `GroupNaming.isReserved`.
  - `InspectorAction.editGroup`, `.makeUnique`, `.ungroup`; `GroupNode.inspector` (one "Group" section with the three buttons).

- [ ] **Step 1: Write the tests**

**Modify** `Tests/CreatorEditorTests/GroupSocketDisplayTests.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Tests/CreatorEditorTests/GroupSocketDisplayTests.swift b/Tests/CreatorEditorTests/GroupSocketDisplayTests.swift
index 7da24dc..1a55157 100644
--- a/Tests/CreatorEditorTests/GroupSocketDisplayTests.swift
+++ b/Tests/CreatorEditorTests/GroupSocketDisplayTests.swift
@@ -32,7 +32,7 @@ struct GroupSocketDisplayTests {
     @Test func theInspectorEditsAGroupNodesInputs() throws {
         let (node, graph) = rib()
         let page = InspectorBuilder.page(graph: graph, selection: [node.id], registry: registry, results: [:])
-        let row = try #require(page.sections.first?.rows.first)
+        let row = try #require(page.sections.first { $0.title == "Inputs" }?.rows.first)
         guard case .number(let field) = row else {
             Issue.record("expected a number row, got \(row)")
             return
````

**Create** `Tests/CreatorGraphTests/Groups/GroupLevelTests.swift`:

````swift
import CreatorKernel
import Testing
@testable import CreatorGraph

/// The levels the graph panel shows (groups spec §6): entering group nodes, falling back when one is gone, and
/// picks written relative to the level shown.
struct GroupLevelTests {
    let doubler = Doubler()

    /// "Outer" holds one instance (`inner`) of the doubler; `top` is an instance of "Outer" on the top level.
    func nested() -> (content: GraphContent, outer: GroupDefinition, top: Node, inner: Node) {
        let inner = instance(of: doubler.definition)
        let outer = define("Outer", outputs: [SocketSpec("result", .number)], nodes: [inner]) { _, output in
            [link(inner, "result", output, "result")]
        }
        let top = instance(of: outer)
        return (GraphContent(graph: graph([top]), definitions: table([doubler.definition, outer])), outer, top, inner)
    }

    func pick(naming node: NodeID) -> ConstantValue {
        let key = EdgeKey([TopoTag(node: node, item: 0, role: .endCap)], [TopoTag(node: node, item: 0, role: .startCap)])
        return .edgePicks([EdgePick(key: key, matchCount: 1, ordinals: [0])])
    }

    @Test func enteringGroupNodesWalksDownThroughTheirDefinitions() {
        let (content, outer, top, inner) = nested()
        #expect(content.path(entering: []) == .root)
        #expect(content.path(entering: [top.id]) == .definition(outer.id))
        #expect(content.path(entering: [top.id, inner.id]) == .definition(doubler.id))
        #expect(content.path(entering: [inner.id]) == nil, "inner is not on the top level")
        #expect(content.path(entering: [top.id, NodeID()]) == nil, "no such node")
        let plain = GraphContent(graph: graph([makeNode(AddNode.self)]))
        #expect(plain.path(entering: plain.graph.nodes.keys.sorted()) == nil, "an Add node isn't a group node")
    }

    @Test func aLevelThatNoLongerExistsFallsBackToTheDeepestOneThatDoes() {
        var (content, _, top, inner) = nested()
        #expect(content.existingLevels([top.id, inner.id]) == [top.id, inner.id])
        content.definitions[doubler.id] = nil
        #expect(content.existingLevels([top.id, inner.id]) == [top.id], "the doubler is gone, Outer remains")
        content.graph.nodes[top.id] = nil
        #expect(content.existingLevels([top.id, inner.id]) == [])
    }

    @Test func aPickIsWrittenRelativeToTheLevelShown() {
        let (content, _, top, inner) = nested()
        let add = doubler.add.id
        // Shown inside the doubler (via top, inner): its Add makes faces under the doubler instance's identity.
        let made = pick(naming: NodeID.scoped([top.id, inner.id, add]))
        #expect(content.relativeToLevel(made, levels: [top.id, inner.id]) == pick(naming: add))
        // Shown inside Outer, the same faces are the doubler instance's: named by the path from Outer.
        #expect(content.relativeToLevel(made, levels: [top.id]) == pick(naming: NodeID.scoped([inner.id, add])))
        // A face made by a node of the level itself.
        #expect(content.relativeToLevel(pick(naming: NodeID.scoped([top.id, inner.id])), levels: [top.id])
                == pick(naming: inner.id))
    }

    @Test func tagsOutsideTheLevelAndOtherValuesAreLeftAlone() {
        let (content, _, top, inner) = nested()
        let outside = NodeID()
        #expect(content.relativeToLevel(pick(naming: outside), levels: [top.id, inner.id]) == pick(naming: outside),
                "a face made outside the level keeps its name")
        #expect(content.relativeToLevel(.number(3), levels: [top.id]) == .number(3))
        let made = pick(naming: NodeID.scoped([top.id, inner.id, doubler.add.id]))
        #expect(content.relativeToLevel(made, levels: []) == made, "the top level names faces as they are made")
        #expect(content.relativeToLevel(made, levels: [inner.id]) == made, "a level that doesn't exist changes nothing")
    }

    @Test func thePlusSocketsNameIsReserved() throws {
        #expect(GroupNaming.isReserved(GroupNaming.plusSocket))
        var content = GraphContent(graph: Graph(), definitions: table([doubler.definition]))
        let rename = try GroupCommands.renameSocket(doubler.id, side: .input, from: "value", to: GroupNaming.plusSocket,
                                                    in: content)
        #expect(throws: GraphError.invalidValue("“+” is reserved. Choose another name.")) {
            try content.apply(rename, registry: testRegistry)
        }
    }

    @Test func aGroupNodesInspectorOffersEditMakeUniqueAndUngroup() {
        let buttons = GroupNode.inspector.flatMap(\.controls)
        #expect(buttons == [.button(title: "Edit Group", action: .editGroup),
                            .button(title: "Make Unique", action: .makeUnique),
                            .button(title: "Ungroup", action: .ungroup),
        ])
    }
}
````

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep 'error:'`

Expected: the build fails: `GraphContent` has no `path(entering:)`, `GroupNaming` no `plusSocket`, `InspectorAction` no `.editGroup`.

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorApp/AppModel+Picking.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorApp/AppModel+Picking.swift b/Sources/CreatorApp/AppModel+Picking.swift
index 4cd1ab3..d114403 100644
--- a/Sources/CreatorApp/AppModel+Picking.swift
+++ b/Sources/CreatorApp/AppModel+Picking.swift
@@ -18,6 +18,8 @@ extension AppModel {
             // sketch's lists then): it changes nothing, so the stroke, selection and camera stay (Errata (S5b)).
             guard sketch == nil else { return }
             beginSketch(for: request.node)
+        case .editGroup, .makeUnique, .ungroup:
+            break  // The graph panel carries these out itself (`EditorModel.press`); they are never recorded.
         }
     }
 
````

**Create** `Sources/CreatorGraph/Groups/GraphContent+Levels.swift`:

````swift
import CreatorKernel

/// The levels the graph panel shows (groups spec §6): the top level, or the inside of a group node entered from it,
/// and so on down. A level is named by the group nodes entered, each by its ID in the graph before it.
extension GraphContent {
    /// The graph reached by entering the group nodes `levels` from the top level (`.root` for none), or `nil` when a
    /// step isn't a group node of a definition that exists.
    public func path(entering levels: [NodeID]) -> GraphPath? {
        var path = GraphPath.root
        for id in levels {
            guard let node = graph(at: path)?.nodes[id], node.typeID == GroupNodes.groupTypeID,
                  let definition = node.inputValues[NodeSetting.group]?.groupID, definitions[definition] != nil else {
                return nil
            }
            path = .definition(definition)
        }
        return path
    }

    /// The longest start of `levels` that still exists: after Undo removes a group node, or an edit deletes the one
    /// entered, the panel falls back to the level around it.
    public func existingLevels(_ levels: [NodeID]) -> [NodeID] {
        var count = levels.count
        while count > 0, path(entering: Array(levels.prefix(count))) == nil { count -= 1 }
        return Array(levels.prefix(count))
    }

    /// `value`, if it is a remembered pick, as the graph at `levels` names faces: the tags it holds name nodes by the
    /// identities they're made under (`NodeID.scoped` of the instance path), and a pick stored in a definition names
    /// them as if the definition were the top level (`GroupScopes.identity`), so every instance reads it as its own
    /// (`EvaluationScope.naming`). A pick made in the viewport while a definition's inside is shown goes through
    /// here before it is stored. Tags naming nodes outside the level, and every other value, are unchanged.
    public func relativeToLevel(_ value: ConstantValue, levels: [NodeID]) -> ConstantValue {
        guard case .definition(let id)? = path(entering: levels), let inside = definitions[id]?.graph else { return value }
        var names: [NodeID: NodeID] = [:]
        for relative in GroupScopes.paths(in: inside, definitions: definitions, entered: [id]) {
            names[NodeID.scoped(levels + relative)] = GroupScopes.identity(relative)
        }
        return value.renamingTags(names)
    }
}
````

**Modify** `Sources/CreatorGraph/Groups/GroupNaming.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorGraph/Groups/GroupNaming.swift b/Sources/CreatorGraph/Groups/GroupNaming.swift
index 9daafe1..e4a3cb8 100644
--- a/Sources/CreatorGraph/Groups/GroupNaming.swift
+++ b/Sources/CreatorGraph/Groups/GroupNaming.swift
@@ -20,9 +20,14 @@ public enum GroupNaming {
         return SocketName("\(base.rawValue)\(number)")
     }
 
-    /// Socket names that can't be used: a group node keeps its settings (`NodeSetting`) beside its inputs' values.
+    /// The name of the "+" socket Group Input and Group Output draw to expose a new socket (groups spec §6): no
+    /// socket of a definition may have it.
+    public static let plusSocket: SocketName = "+"
+
+    /// Socket names that can't be used: a group node keeps its settings (`NodeSetting`) beside its inputs' values,
+    /// and the "+" socket is the canvas's.
     public static func isReserved(_ name: SocketName) -> Bool {
-        NodeSetting.all.contains(name) || name.rawValue.hasPrefix(NodeSetting.projectionPrefix)
+        name == plusSocket || NodeSetting.all.contains(name) || name.rawValue.hasPrefix(NodeSetting.projectionPrefix)
     }
 
     /// Why `sockets` can't be one side of a group, or `nil` if they can.
````

**Modify** `Sources/CreatorGraph/Groups/GroupNode.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorGraph/Groups/GroupNode.swift b/Sources/CreatorGraph/Groups/GroupNode.swift
index e1f28f8..a2a6634 100644
--- a/Sources/CreatorGraph/Groups/GroupNode.swift
+++ b/Sources/CreatorGraph/Groups/GroupNode.swift
@@ -8,6 +8,13 @@ public enum GroupNode: NodeDefinition {
     public static let category = NodeCategory.feature
     public static let inputs: [SocketSpec] = []
     public static let outputs: [SocketSpec] = []
+    public static let inspector = [
+        InspectorSection(title: "Group", controls: [
+            .button(title: "Edit Group", action: .editGroup),
+            .button(title: "Make Unique", action: .makeUnique),
+            .button(title: "Ungroup", action: .ungroup),
+        ]),
+    ]
 
     public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
         throw NodeError.invalidValue("A group is evaluated through its definition's graph.")
````

**Modify** `Sources/CreatorGraph/InspectorAction.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorGraph/InspectorAction.swift b/Sources/CreatorGraph/InspectorAction.swift
index 8246466..a1692f6 100644
--- a/Sources/CreatorGraph/InspectorAction.swift
+++ b/Sources/CreatorGraph/InspectorAction.swift
@@ -3,4 +3,7 @@ public enum InspectorAction: String, Sendable, Codable {
     case pickEdgesInView, pickFacesInView
     /// "Edit sketch" (sketcher spec §8): the app shell opens the node's sketch in the viewport.
     case editSketch
+    /// "Edit Group", "Make Unique" and "Ungroup" on a group node (groups spec §6): the graph panel carries them out
+    /// itself, so they never reach the app shell.
+    case editGroup, makeUnique, ungroup
 }
````

- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter 'GroupLevelTests|GroupSocketDisplayTests'`

Expected: every test passes (no "recorded an issue").

- [ ] **Step 5: Lint and run the whole suite**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-editor-test.log`.

Expected: exit code 0; `grep -cE 'recorded an issue|failed after' /tmp/groups-editor-test.log` prints 0; `grep -c 'Test run with' /tmp/groups-editor-test.log` prints 11; the counts on those lines add up to **1649** (master + 6). No new compiler warning.

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorApp/AppModel+Picking.swift' 'Sources/CreatorGraph/Groups/GraphContent+Levels.swift' 'Sources/CreatorGraph/Groups/GroupNaming.swift' 'Sources/CreatorGraph/Groups/GroupNode.swift' 'Sources/CreatorGraph/InspectorAction.swift' 'Tests/CreatorEditorTests/GroupSocketDisplayTests.swift' 'Tests/CreatorGraphTests/Groups/GroupLevelTests.swift'
git commit -m "feat(groups): levels, relative picks, the + socket's name, group inspector buttons"
```

---

### Task 2: Evaluating the level the panel shows

While the graph panel shows the inside of a group, every node there needs a state (badges, Selected node preview, handles), including one nothing downstream reads, which the evaluator never reaches. `Evaluator.evaluate(_:definitions:demand:inspecting:)` takes the level (the group nodes entered) and evaluates all of its nodes besides the demand; `DocumentModel.inspectedLevel` is the property the editor sets. The group node's own result, errors and warnings still come only from what feeds Group Output, so a failing dead-end node never fails the group.

**Files:**
- Modify: `Sources/CreatorGraph/DocumentModel.swift`
- Modify: `Sources/CreatorGraph/Evaluator.swift`
- Modify: `Sources/CreatorGraph/Groups/EvaluationSetup.swift`
- Modify: `Sources/CreatorGraph/Groups/Evaluator+Groups.swift`
- Create: `Tests/CreatorGraphTests/Groups/InspectedLevelTests.swift`

**Interfaces:**
- Consumes: `Evaluator.evaluate`, `evaluateGroup`, `EvaluationSetup`, `GroupTrail`, `Graph.evaluationOrder(for:)` (C1).
- Produces:
  - `Evaluator.evaluate(_:definitions:demand:inspecting:)` (the new parameter defaults to `[]`).
  - `DocumentModel.inspectedLevel: [NodeID]`: setting it re-evaluates; `innerResults` then holds every node of that level under `level + [node]`.
  - `EvaluationSetup.inspected`, `EvaluationSetup.inspectedNodes(inside:of:)` (internal).

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorGraphTests/Groups/InspectedLevelTests.swift`:

````swift
import CreatorKernel
import Testing
@testable import CreatorGraph

/// The level the graph panel shows is evaluated whole (groups spec §6): every node inside has a state, even one that
/// nothing downstream reads, and such a node never changes the group node's own result.
struct InspectedLevelTests {
    let doubler = Doubler()

    /// "Rib": Group Input's `value` through an Add (both inputs) to Group Output's `result`, and `extra`, which
    /// nothing reads.
    func rib(extra: Node) -> (definition: GroupDefinition, add: Node) {
        let add = makeNode(AddNode.self)
        let definition = define("Rib", inputs: [SocketSpec("value", .number)], outputs: [SocketSpec("result", .number)],
                                nodes: [add, extra]) { input, output in
            [link(input, "value", add, "a"), link(input, "value", add, "b"), link(add, "sum", output, "result")]
        }
        return (definition, add)
    }

    func evaluate(_ g: Graph, _ definitions: [GroupDefinition], demand: [Node], inspecting level: [Node] = []) async throws
        -> EvaluationReport {
        try await Evaluator(registry: testRegistry, kernel: FakeKernel())
            .evaluate(g, definitions: table(definitions), demand: Set(demand.map(\.id)), inspecting: level.map(\.id))
    }

    @Test func aNodeNothingReadsIsEvaluatedOnlyWhileItsLevelIsInspected() async throws {
        let extra = makeNode(ConstantNode.self, ["value": .number(7)])
        let (definition, _) = rib(extra: extra)
        let group = instance(of: definition, ["value": .number(3)], output: true)
        let plain = try await evaluate(graph([group]), [definition], demand: [group])
        #expect(plain.innerResults[[group.id, extra.id]] == nil, "nothing asked for it")
        let shown = try await evaluate(graph([group]), [definition], demand: [group], inspecting: [group])
        #expect(shown.innerResults[[group.id, extra.id]]?.outputs?["value"]?.numbers == [7])
        #expect(shown.results[group.id]?.outputs?["result"]?.numbers == [6], "the group's own result is as before")
    }

    @Test func aGroupNodeNothingDemandsIsEvaluatedToShowItsInside() async throws {
        let (definition, add) = rib(extra: makeNode(ConstantNode.self))
        let group = instance(of: definition, ["value": .number(3)])
        let plain = try await evaluate(graph([group]), [definition], demand: [])
        #expect(plain.results[group.id] == nil && plain.innerResults.isEmpty)
        let shown = try await evaluate(graph([group]), [definition], demand: [], inspecting: [group])
        #expect(shown.innerResults[[group.id, add.id]]?.outputs?["sum"]?.numbers == [6])
    }

    @Test func aFailingNodeNothingFeedsLeavesTheGroupNodeAlone() async throws {
        let failing = makeNode(FailNode.self)
        let (definition, _) = rib(extra: failing)
        let group = instance(of: definition, ["value": .number(3)], output: true)
        let report = try await evaluate(graph([group]), [definition], demand: [group], inspecting: [group])
        #expect(report.innerResults[[group.id, failing.id]]?.state == .error("Boom"))
        #expect(report.results[group.id]?.state.isSuccess == true)
        #expect(report.results[group.id]?.outputs?["result"]?.numbers == [6])
    }

    @Test func aFailingNodeThatFeedsGroupOutputStillFailsTheGroupNode() async throws {
        let failing = makeNode(FailNode.self)
        let definition = define("Broken", outputs: [SocketSpec("result", .number)], nodes: [failing]) { _, output in
            [link(failing, "value", output, "result")]
        }
        let group = instance(of: definition, output: true)
        let report = try await evaluate(graph([group]), [definition], demand: [group], inspecting: [group])
        #expect(report.results[group.id]?.state == .error("Broken › Fail: Boom"))
    }

    @Test func aNestedLevelIsReachedThroughItsGroupNodes() async throws {
        let inner = instance(of: doubler.definition)
        let constant = makeNode(ConstantNode.self, ["value": .number(5)])
        let outer = define("Outer", outputs: [SocketSpec("result", .number)], nodes: [inner, constant]) { _, output in
            [link(constant, "value", output, "result")]
        }
        let top = instance(of: outer, output: true)
        let report = try await evaluate(graph([top]), [doubler.definition, outer], demand: [top], inspecting: [top, inner])
        #expect(report.innerResults[[top.id, inner.id, doubler.add.id]]?.outputs?["sum"]?.numbers == [2],
                "inner is wired to nothing in Outer, and is evaluated because its inside is shown")
        #expect(report.results[top.id]?.outputs?["result"]?.numbers == [5])
        let outerOnly = try await evaluate(graph([top]), [doubler.definition, outer], demand: [top], inspecting: [top])
        #expect(outerOnly.innerResults[[top.id, inner.id]]?.state.isSuccess == true, "the nested group node itself")
    }

    @Test func aLevelThatDoesntExistChangesNothing() async throws {
        let (definition, _) = rib(extra: makeNode(ConstantNode.self))
        let group = instance(of: definition, ["value": .number(3)], output: true)
        let plain = try await evaluate(graph([group]), [definition], demand: [group])
        let odd = try await evaluate(graph([group]), [definition], demand: [group], inspecting: [makeNode(AddNode.self)])
        #expect(odd.results[group.id]?.outputs?["result"]?.numbers == plain.results[group.id]?.outputs?["result"]?.numbers)
        #expect(Set(odd.innerResults.keys) == Set(plain.innerResults.keys))
    }

    @MainActor
    @Test func theDocumentEvaluatesTheLevelItsPanelShows() async {
        let extra = makeNode(ConstantNode.self, ["value": .number(7)])
        let (definition, _) = rib(extra: extra)
        let group = instance(of: definition, ["value": .number(3)], output: true)
        let document = DocumentModel(file: GraphFile(graph: graph([group]), definitions: table([definition])),
                                     registry: testRegistry, kernel: FakeKernel())
        await document.waitForEvaluation()
        #expect(document.innerResults[[group.id, extra.id]] == nil)
        document.inspectedLevel = [group.id]
        await document.waitForEvaluation()
        #expect(document.innerResults[[group.id, extra.id]]?.outputs?["value"]?.numbers == [7])
        document.inspectedLevel = []
        await document.waitForEvaluation()
        #expect(document.innerResults[[group.id, extra.id]] == nil)
    }
}
````

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep 'error:'`

Expected: the build fails: `evaluate` has no `inspecting:` label and `DocumentModel` no `inspectedLevel`.

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorGraph/DocumentModel.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorGraph/DocumentModel.swift b/Sources/CreatorGraph/DocumentModel.swift
index a1e4260..871280a 100644
--- a/Sources/CreatorGraph/DocumentModel.swift
+++ b/Sources/CreatorGraph/DocumentModel.swift
@@ -34,6 +34,15 @@ public final class DocumentModel {
         }
     }
 
+    /// The level the graph panel shows (groups spec §6): the group nodes entered from the top level, each by its ID in
+    /// the graph before it; empty on the top level. Everything on that level is evaluated, so `innerResults` has
+    /// a state for each of its nodes.
+    public var inspectedLevel: [NodeID] = [] {
+        didSet {
+            if oldValue != inspectedLevel { scheduleEvaluation() }
+        }
+    }
+
     /// The registry the document was opened with, without its definitions.
     @ObservationIgnored private let baseRegistry: NodeRegistry
     private var undoStack = UndoStack()
@@ -158,12 +167,14 @@ public final class DocumentModel {
         let current = generation
         let snapshot = content
         let demand = demand
+        let level = inspectedLevel
         let evaluator = evaluator
         isEvaluating = true
         evaluationTask = Task {
             let report: EvaluationReport
             do {
-                report = try await evaluator.evaluate(snapshot.graph, definitions: snapshot.definitions, demand: demand)
+                report = try await evaluator.evaluate(snapshot.graph, definitions: snapshot.definitions, demand: demand,
+                                                inspecting: level)
             } catch {
                 return  // Cancelled: a newer generation is already scheduled.
             }
````

**Modify** `Sources/CreatorGraph/Evaluator.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorGraph/Evaluator.swift b/Sources/CreatorGraph/Evaluator.swift
index 06069b5..63cb09b 100644
--- a/Sources/CreatorGraph/Evaluator.swift
+++ b/Sources/CreatorGraph/Evaluator.swift
@@ -16,14 +16,19 @@ public actor Evaluator {
 
     public var cachedEntryCount: Int { cache.count }
 
-    /// Evaluates `demand` on the top level of `graph`; group nodes run the graphs of `definitions`.
-    public func evaluate(_ graph: Graph, definitions: [GroupID: GroupDefinition] = [:],
-                         demand: Set<NodeID>) async throws -> EvaluationReport {
+    /// Evaluates `demand` on the top level of `graph`; group nodes run the graphs of `definitions`. With `inspecting`,
+    /// the group nodes entered from the top level down to the level the graph panel shows (groups spec §6), every
+    /// node of that level is evaluated too, so each has a state in `innerResults` even when nothing downstream
+    /// wants it; a node there that fails doesn't fail the group node unless it feeds Group Output.
+    public func evaluate(_ graph: Graph, definitions: [GroupID: GroupDefinition] = [:], demand: Set<NodeID>,
+                         inspecting level: [NodeID] = []) async throws -> EvaluationReport {
         // Entries of nodes no longer anywhere (deleted, or inside a group node that's gone) leave the cache.
         cache.removeEntries(notIn: graph.scopedNodeIDs(definitions: definitions))
         let parameters = Dictionary(graph.parameters.map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first })
-        let setup = EvaluationSetup(registry: registry.withGroups(definitions), parameters: parameters)
+        let setup = EvaluationSetup(registry: registry.withGroups(definitions), parameters: parameters, inspected: level)
         var trace = EvaluationTrace()
+        var demand = demand
+        if let first = level.first, graph.nodes[first] != nil { demand.insert(first) }
         let level = try await evaluateLevel(graph, demand: demand, scope: EvaluationScope(setup: setup), trace: &trace)
         return EvaluationReport(results: level.results, evaluatedNodes: level.evaluated, innerResults: trace.results,
                                 evaluatedInnerNodes: trace.evaluated)
````

**Modify** `Sources/CreatorGraph/Groups/EvaluationSetup.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorGraph/Groups/EvaluationSetup.swift b/Sources/CreatorGraph/Groups/EvaluationSetup.swift
index 5c2b642..a581cc9 100644
--- a/Sources/CreatorGraph/Groups/EvaluationSetup.swift
+++ b/Sources/CreatorGraph/Groups/EvaluationSetup.swift
@@ -1,6 +1,19 @@
+import CreatorKernel
+
 /// What every level of one evaluation shares (groups spec §5): the registry carrying the document's definitions, so
 /// group nodes have their sockets, and the document's parameters.
 struct EvaluationSetup: Sendable {
     var registry: NodeRegistry
     var parameters: [ParameterID: ConstantValue]
+    /// The level the graph panel shows (`DocumentModel.inspectedLevel`): the group nodes entered from the top level.
+    /// Every node of that level is evaluated, whether or not it feeds Group Output, so each shows its state and can
+    /// be previewed.
+    var inspected: [NodeID] = []
+
+    /// The nodes of `graph`, the inside of the group node at instance path `path`, that the inspected level asks for:
+    /// all of them when `path` is the level, else the one group node on the way down to it.
+    func inspectedNodes(inside path: [NodeID], of graph: Graph) -> Set<NodeID> {
+        guard inspected.starts(with: path) else { return [] }
+        return inspected.count == path.count ? Set(graph.nodes.keys) : [inspected[path.count]]
+    }
 }
````

**Modify** `Sources/CreatorGraph/Groups/Evaluator+Groups.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorGraph/Groups/Evaluator+Groups.swift b/Sources/CreatorGraph/Groups/Evaluator+Groups.swift
index e46e5ca..a0df568 100644
--- a/Sources/CreatorGraph/Groups/Evaluator+Groups.swift
+++ b/Sources/CreatorGraph/Groups/Evaluator+Groups.swift
@@ -30,9 +30,16 @@ extension Evaluator {
         let before = trace.evaluated.count
         let inner = scope.entering(node.id, group: definition.id, graph: definition.graph,
                                   bound: EvaluationScope.Bound(values: inputs, key: key))
-        let level = try await evaluateLevel(definition.graph, demand: [output.id], scope: inner, trace: &trace)
+        let wanted = scope.setup.inspectedNodes(inside: inner.path, of: definition.graph)
+        let everything = try await evaluateLevel(definition.graph, demand: wanted.union([output.id]), scope: inner,
+                                                 trace: &trace)
         let ran = trace.evaluated.count > before
         let graph = definition.graph
+        // Only what feeds Group Output speaks for the group node: messages and states of the nodes asked for to be
+        // shown (`inspectedNodes`) stay in `trace`.
+        let feeding = Set(graph.evaluationOrder(for: [output.id]).order)
+        var level = everything
+        level.order = everything.order.filter(feeding.contains)
         if let message = GroupTrail.firstError(in: level, graph: graph, definition: definition) {
             return GroupOutcome(result: NodeResult(state: .error(message)), key: key, ran: ran)
         }
````

- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter 'InspectedLevelTests'`

Expected: every test passes (no "recorded an issue").

- [ ] **Step 5: Lint and run the whole suite**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-editor-test.log`.

Expected: exit code 0; `grep -cE 'recorded an issue|failed after' /tmp/groups-editor-test.log` prints 0; `grep -c 'Test run with' /tmp/groups-editor-test.log` prints 11; the counts on those lines add up to **1656** (master + 13). No new compiler warning.

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorGraph/DocumentModel.swift' 'Sources/CreatorGraph/Evaluator.swift' 'Sources/CreatorGraph/Groups/EvaluationSetup.swift' 'Sources/CreatorGraph/Groups/Evaluator+Groups.swift' 'Tests/CreatorGraphTests/Groups/InspectedLevelTests.swift'
git commit -m "feat(groups): evaluate the level the panel shows"
```

---

### Task 3: Exposing sockets and merging definitions (CreatorGraph)

Two command builders for C2. `GroupCommands.exposeOutput`/`exposeInput` build the "+" drop as one command: the interface change and the wire together, addressed to the definition, so the editor performs it as one undo step. `GroupMerge` is the clipboard's logic (spec §9): which definitions copied group nodes need, and how a paste merges them into a document by content (reuse a definition equal to it ignoring ID and name, add as is, or add as "Name (imported)" with the group nodes retargeted), so pasting the same clipboard twice, or after the definition was renamed, makes no second copy.

**Files:**
- Create: `Sources/CreatorGraph/Groups/GroupCommands+Expose.swift`
- Create: `Sources/CreatorGraph/Groups/GroupMerge.swift`
- Modify: `Sources/CreatorGraph/Groups/GroupNaming.swift`
- Create: `Tests/CreatorGraphTests/Groups/GroupExposeTests.swift`
- Create: `Tests/CreatorGraphTests/Groups/GroupMergeTests.swift`

**Interfaces:**
- Consumes: `GroupCommands.missingSocket`, `GroupRefusal`, `GroupNaming.uniqueSocketName`, `GroupDependencies.direct`, `GroupDefinition` (Equatable), `NodeRegistry.withGroups(_:)` (C1).
- Produces:
  - `GroupCommands.exposeOutput(from:on:in:of:registry:) throws(GraphError) -> GraphCommand` and `exposeInput(to:from:in:of:registry:)`.
  - `GroupMerge.definitions(used nodes: [Node], in content: GraphContent) -> [GroupID: GroupDefinition]`.
  - `GroupMerge.plan(importing:into:) -> GroupMerge.Plan` with `additions: [GroupDefinition]` (innermost first), `targets: [GroupID: GroupID]` and `retargeting(_ node: Node) -> Node`.
  - `GroupNaming.uniqueName(_:taken:)` (internal).

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorGraphTests/Groups/GroupExposeTests.swift`:

````swift
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Exposing a socket by wiring it to the "+" of Group Input or Group Output (groups spec §6): one command, one undo
/// step.
@MainActor
struct GroupExposeTests {
    /// "Rib": an Add whose `a` Group Input feeds; `b` is unwired (default 0, millimetres is not set on the test node).
    let add = makeNode(AddNode.self)
    let definition: GroupDefinition

    init() {
        let add = self.add
        definition = define("Rib", inputs: [SocketSpec("a", .number)], outputs: [], nodes: [add]) { input, _ in
            [link(input, "a", add, "a")]
        }
    }

    func document(_ group: Node) -> DocumentModel {
        DocumentModel(file: GraphFile(graph: graph([group]), definitions: table([definition])), registry: testRegistry,
                      kernel: FakeKernel())
    }

    @Test func droppingAWireOnGroupOutputsPlusExposesAnOutputInOneStep() throws {
        let group = instance(of: definition)
        let document = document(group)
        let output = try #require(definition.outputNode)
        let command = try GroupCommands.exposeOutput(from: Endpoint(node: add.id, socket: "sum"), on: output.id,
                                                     in: definition.id, of: document.content, registry: testRegistry)
        try document.perform(command)
        let exposed = try #require(document.definitions[definition.id])
        #expect(exposed.outputs == [SocketSpec("sum", .number)])
        #expect(exposed.graph.links.contains(link(add, "sum", output, "sum")))
        #expect(document.registry.outputs(for: group).map(\.name) == ["sum"], "the group node has it too")
        document.undo()
        #expect(document.definitions == table([definition]), "one undo step takes the socket and its wire")
        #expect(!document.canUndo)
    }

    @Test func aSecondDropFromTheSameSocketGetsAnotherName() throws {
        let document = document(instance(of: definition))
        let output = try #require(definition.outputNode)
        for _ in 0..<2 {
            let command = try GroupCommands.exposeOutput(from: Endpoint(node: add.id, socket: "sum"), on: output.id,
                                                         in: definition.id, of: document.content, registry: testRegistry)
            try document.perform(command)
        }
        #expect(document.definitions[definition.id]?.outputs.map(\.name) == ["sum", "sum2"])
    }

    @Test func draggingFromGroupInputsPlusOntoAnInputExposesAnInputWithItsDefault() throws {
        let group = instance(of: definition)
        let document = document(group)
        let input = try #require(definition.inputNode)
        let command = try GroupCommands.exposeInput(to: Endpoint(node: add.id, socket: "b"), from: input.id,
                                                    in: definition.id, of: document.content, registry: testRegistry)
        try document.perform(command)
        let exposed = try #require(document.definitions[definition.id])
        let spec = try #require(exposed.inputs.last)
        let target = try #require(AddNode.inputs.first { $0.name == "b" })
        #expect(spec.name == "b" && spec.type == .number && spec.defaultValue == target.defaultValue)
        #expect(exposed.graph.links.contains(link(input, "b", add, "b")))
        #expect(document.registry.inputs(for: group).map(\.name) == ["a", "b"])
        document.undo()
        #expect(document.definitions == table([definition]))
    }

    @Test func aDropIsRefusedForABoundaryOfAnotherDefinitionOrASocketThatIsntThere() throws {
        let document = document(instance(of: definition))
        let input = try #require(definition.inputNode), output = try #require(definition.outputNode)
        let content = document.content
        #expect(throws: GroupRefusal.boundaryCount) {
            try GroupCommands.exposeOutput(from: Endpoint(node: add.id, socket: "sum"), on: input.id, in: definition.id,
                                           of: content, registry: testRegistry)
        }
        #expect(throws: GroupRefusal.missing) {
            try GroupCommands.exposeOutput(from: Endpoint(node: add.id, socket: "sum"), on: output.id, in: GroupID(),
                                           of: content, registry: testRegistry)
        }
        #expect(throws: GroupCommands.missingSocket) {
            try GroupCommands.exposeOutput(from: Endpoint(node: add.id, socket: "nothing"), on: output.id,
                                           in: definition.id, of: content, registry: testRegistry)
        }
        #expect(throws: GroupCommands.missingSocket) {
            try GroupCommands.exposeInput(to: Endpoint(node: add.id, socket: "nothing"), from: input.id,
                                          in: definition.id, of: content, registry: testRegistry)
        }
    }
}
````

**Create** `Tests/CreatorGraphTests/Groups/GroupMergeTests.swift`:

````swift
import CreatorKernel
import Testing
@testable import CreatorGraph

/// The definitions copied group nodes carry, and how a paste merges them into a document by content (groups spec
/// §9).
struct GroupMergeTests {
    let doubler = Doubler()

    func outer(placing inner: Node) -> GroupDefinition {
        define("Outer", outputs: [SocketSpec("result", .number)], nodes: [inner]) { _, output in
            [link(inner, "result", output, "result")]
        }
    }

    func content(_ definitions: [GroupDefinition]) -> GraphContent {
        GraphContent(graph: Graph(), definitions: table(definitions))
    }

    @Test func copiedGroupNodesCarryTheDefinitionsTheyUseAtEveryDepth() {
        let inner = instance(of: doubler.definition)
        let outer = outer(placing: inner)
        let unrelated = define("Other", outputs: [], nodes: []) { _, _ in [] }
        let source = content([doubler.definition, outer, unrelated])
        let carried = GroupMerge.definitions(used: [instance(of: outer), makeNode(AddNode.self)], in: source)
        #expect(Set(carried.keys) == [doubler.id, outer.id])
        #expect(GroupMerge.definitions(used: [makeNode(AddNode.self)], in: source).isEmpty)
    }

    @Test func aDefinitionTheDocumentHasWithTheSameContentIsReused() {
        let plan = GroupMerge.plan(importing: table([doubler.definition]), into: content([doubler.definition]))
        #expect(plan.additions.isEmpty)
        #expect(plan.targets == [doubler.id: doubler.id])
    }

    @Test func aDefinitionTheDocumentLacksIsAddedAsItIsInnermostFirst() throws {
        let outer = outer(placing: instance(of: doubler.definition))
        let plan = GroupMerge.plan(importing: table([doubler.definition, outer]), into: content([]))
        #expect(plan.additions.map(\.id) == [doubler.id, outer.id])
        #expect(plan.additions == [doubler.definition, outer])
        var document = content([])
        for addition in plan.additions { try document.apply(.addDefinition(addition), registry: testRegistry) }
        #expect(document.definitions == table([doubler.definition, outer]))
    }

    @Test func aDefinitionWithTheSameIDAndOtherContentComesInAsACopy() throws {
        var changed = doubler.definition
        changed.graph.nodes[doubler.add.id]?.inputValues["b"] = .number(10)
        let plan = GroupMerge.plan(importing: table([changed]), into: content([doubler.definition]))
        let copy = try #require(plan.additions.first)
        #expect(plan.additions.count == 1 && copy.id != doubler.id)
        #expect(copy.name == "Doubler (imported)")
        #expect(copy.graph.nodes.values.filter(GroupNodes.isBoundary).allSatisfy {
            $0.inputValues[NodeSetting.group]?.groupID == copy.id
        }, "its Group Input and Group Output belong to the copy")
        #expect(plan.targets[doubler.id] == copy.id)
        let pasted = instance(of: changed)
        #expect(plan.retargeting(pasted).inputValues[NodeSetting.group]?.groupID == copy.id)
        var document = content([doubler.definition])
        try document.apply(.addDefinition(copy), registry: testRegistry)
        #expect(document.definitions.count == 2)
    }

    @Test func aDefinitionThatPlacesACopiedOneIsCopiedToo() throws {
        let inner = instance(of: doubler.definition)
        let outer = outer(placing: inner)
        var changed = doubler.definition
        changed.graph.nodes[doubler.add.id]?.inputValues["b"] = .number(10)
        let plan = GroupMerge.plan(importing: table([changed, outer]), into: content([doubler.definition, outer]))
        #expect(plan.additions.count == 2)
        let innerCopy = try #require(plan.additions.first), outerCopy = try #require(plan.additions.last)
        #expect(innerCopy.name == "Doubler (imported)" && outerCopy.name == "Outer (imported)")
        #expect(plan.targets[changed.id] == innerCopy.id && plan.targets[outer.id] == outerCopy.id)
        #expect(outerCopy.graph.nodes[inner.id]?.inputValues[NodeSetting.group]?.groupID == innerCopy.id,
                "the copy of Outer places the copy of the doubler")
        var document = content([doubler.definition, outer])
        for addition in plan.additions { try document.apply(.addDefinition(addition), registry: testRegistry) }
        #expect(document.definitions.count == 4)
    }

    @Test func aNameTheDocumentAlreadyUsesGetsImportedBesideIt() throws {
        let other = Doubler()  // Another definition, also named "Doubler", with an ID the document lacks.
        let plan = GroupMerge.plan(importing: table([other.definition]), into: content([doubler.definition]))
        let added = try #require(plan.additions.first)
        #expect(added.id == other.id, "its ID was free, so it keeps it")
        #expect(added.name == "Doubler (imported)")
        #expect(plan.targets == [other.id: other.id])
    }

    @Test func theSameStaleClipboardPastedTwiceAddsOneCopy() throws {
        var edited = doubler.definition
        edited.graph.nodes[doubler.add.id]?.inputValues["b"] = .number(10)
        var document = content([edited])
        // The clipboard holds the doubler as it was copied; the document has it edited since.
        let first = GroupMerge.plan(importing: table([doubler.definition]), into: document)
        let copy = try #require(first.additions.first)
        #expect(first.additions.count == 1 && copy.id != doubler.id)
        for addition in first.additions { try document.apply(.addDefinition(addition), registry: testRegistry) }
        let second = GroupMerge.plan(importing: table([doubler.definition]), into: document)
        #expect(second.additions.isEmpty, "the first paste's copy is reused, whatever its ID and name")
        #expect(second.targets == [doubler.id: copy.id])
        #expect(second.targets == first.targets)
    }

    @Test func aDefinitionRenamedOrRecolouredSinceTheCopyIsJudgedByItsContent() {
        var renamed = doubler.definition
        renamed.name = "Renamed"
        let plan = GroupMerge.plan(importing: table([doubler.definition]), into: content([renamed]))
        #expect(plan.additions.isEmpty && plan.targets == [doubler.id: doubler.id], "a rename makes no copy")
        var recoloured = doubler.definition
        recoloured.accent = .green
        let other = GroupMerge.plan(importing: table([doubler.definition]), into: content([recoloured]))
        #expect(other.additions.count == 1, "another accent is other content")
    }
}
````

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep 'error:'`

Expected: the build fails: no `exposeOutput`, `exposeInput` or `GroupMerge`.

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorGraph/Groups/GroupCommands+Expose.swift`:

````swift
import CreatorKernel

/// Exposing a socket by wiring it to the "+" of Group Input or Group Output (groups spec §6). Each builds one command
/// that adds the socket and its wire together, to be performed while the definition's inside is shown, so the drop is
/// one undo step.
extension GroupCommands {
    /// Dropping a wire from `source`, an output of a node inside definition `id`, on Group Output's "+" (`boundary`):
    /// a new output named after the source socket (made unique), of its type, wired from it.
    public static func exposeOutput(from source: Endpoint, on boundary: NodeID, in id: GroupID, of content: GraphContent,
                                    registry: NodeRegistry) throws(GraphError) -> GraphCommand {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        guard let output = definition.outputNode, output.id == boundary else { throw GroupRefusal.boundaryCount }
        let sockets = registry.withGroups(content.definitions)
        guard let node = definition.graph.nodes[source.node],
              let spec = sockets.outputs(for: node).first(where: { $0.name == source.socket }) else { throw missingSocket }
        var interface = definition.interface
        let name = GroupNaming.uniqueSocketName(source.socket, among: interface.outputs.map(\.name))
        interface.outputs.append(SocketSpec(name, spec.type))
        let wire = Link(from: source, to: Endpoint(node: output.id, socket: name))
        return .batch([.setInterface(id, interface), GraphCommand.connect(wire).at(.definition(id))])
    }

    /// Dragging from Group Input's "+" (`boundary`) onto `target`, an input of a node inside definition `id`: a new
    /// input named after the target socket (made unique) with its type, unit, range and default, wired to it.
    public static func exposeInput(to target: Endpoint, from boundary: NodeID, in id: GroupID, of content: GraphContent,
                                   registry: NodeRegistry) throws(GraphError) -> GraphCommand {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        guard let input = definition.inputNode, input.id == boundary else { throw GroupRefusal.boundaryCount }
        let sockets = registry.withGroups(content.definitions)
        guard let node = definition.graph.nodes[target.node],
              let spec = sockets.inputs(for: node).first(where: { $0.name == target.socket }) else { throw missingSocket }
        var interface = definition.interface
        let name = GroupNaming.uniqueSocketName(target.socket, among: interface.inputs.map(\.name))
        interface.inputs.append(SocketSpec(name, spec.type, defaultValue: spec.defaultValue, unit: spec.unit, range: spec.range))
        let wire = Link(from: Endpoint(node: input.id, socket: name), to: target)
        return .batch([.setInterface(id, interface), GraphCommand.connect(wire).at(.definition(id))])
    }
}
````

**Create** `Sources/CreatorGraph/Groups/GroupMerge.swift`:

````swift
import CreatorKernel

/// Group definitions travelling with copied group nodes (groups spec §9): the clipboard carries every definition the
/// copied nodes use, and a paste merges them into the document by content.
public enum GroupMerge {
    /// What a paste does with the definitions it was carrying.
    public struct Plan: Sendable, Equatable {
        /// The definitions to add, innermost first, so each can be added once the ones it places exist.
        public var additions: [GroupDefinition] = []
        /// Each carried definition's ID in the document: the ID of the definition that has its content already (itself
        /// when the document has it as it is), itself when the document gains it as it is, else the ID of the copy
        /// added in its place.
        public var targets: [GroupID: GroupID] = [:]

        /// `node`, a pasted group node, pointing at the definition `targets` names.
        public func retargeting(_ node: Node) -> Node {
            guard node.typeID == GroupNodes.groupTypeID, let old = node.inputValues[NodeSetting.group]?.groupID,
                  let new = targets[old], new != old else { return node }
            var moved = node
            moved.inputValues[NodeSetting.group] = .group(new)
            return moved
        }
    }

    /// The definitions `nodes` need from `content`: those their group nodes name, and every one those place, however
    /// deep.
    public static func definitions(used nodes: [Node], in content: GraphContent) -> [GroupID: GroupDefinition] {
        var found: [GroupID: GroupDefinition] = [:]
        var pending = nodes.compactMap { node in
            node.typeID == GroupNodes.groupTypeID ? node.inputValues[NodeSetting.group]?.groupID : nil
        }
        while let id = pending.popLast() {
            guard found[id] == nil, let definition = content.definitions[id] else { continue }
            found[id] = definition
            pending += GroupDependencies.direct(definition.graph).sorted()
        }
        return found
    }

    /// How to merge `incoming` into `content`: a definition some definition of the document equals, ignoring ID and
    /// name (the same accent, sockets and inside, with nested group nodes retargeted), is reused, however the document
    /// came by it: the original, a rename of it, or a copy an earlier paste added. One the document has no match for
    /// is added as it is; one whose ID is taken by different content, or whose name is taken, is added as a copy
    /// named "Name (imported)" (made unique), with a new ID if the ID was taken. A definition that places a copied one
    /// is itself copied when that changed its content.
    public static func plan(importing incoming: [GroupID: GroupDefinition], into content: GraphContent) -> Plan {
        var plan = Plan()
        var names = Set(content.definitions.values.map(\.name))
        var visited: Set<GroupID> = []

        func resolve(_ id: GroupID) {
            guard let definition = incoming[id], visited.insert(id).inserted else { return }
            for placed in GroupDependencies.direct(definition.graph).sorted() { resolve(placed) }
            var merged = definition
            for (nodeID, node) in definition.graph.nodes { merged.graph.nodes[nodeID] = plan.retargeting(node) }
            // Looked for among the document's definitions and the copies this paste has added so far; the one with
            // the same ID wins, else the lowest ID.
            let same = (Array(content.definitions.values) + plan.additions).filter { hasSameContent($0, as: merged) }
            if let found = same.min(by: { ($0.id == id ? 0 : 1, $0.id) < ($1.id == id ? 0 : 1, $1.id) }) {
                plan.targets[id] = found.id
                return
            }
            let idTaken = content.definitions[id] != nil
            if idTaken || names.contains(merged.name) {
                merged.name = GroupNaming.uniqueName("\(merged.name) (imported)", taken: names)
            }
            let target = idTaken ? GroupID() : id
            if idTaken {
                merged = GroupDefinition(id: target, name: merged.name, accent: merged.accent, inputs: merged.inputs,
                                         outputs: merged.outputs, graph: merged.graph)
                for (nodeID, node) in merged.graph.nodes where GroupNodes.isBoundary(node) {
                    merged.graph.nodes[nodeID]?.inputValues[NodeSetting.group] = .group(target)
                }
            }
            names.insert(merged.name)
            plan.targets[id] = target
            plan.additions.append(merged)
        }
        for id in incoming.keys.sorted() { resolve(id) }
        return plan
    }

    /// Whether `a` and `b` differ at most in ID and name: the same accent, sockets and inside. Group Input and Group
    /// Output carry the ID of their own definition, so that is set aside.
    static func hasSameContent(_ a: GroupDefinition, as b: GroupDefinition) -> Bool {
        a.accent == b.accent && a.inputs == b.inputs && a.outputs == b.outputs
            && inside(a, ownedBy: a.id) == inside(b, ownedBy: a.id)
    }

    /// `definition`'s inside with its Group Input and Group Output naming `owner`.
    private static func inside(_ definition: GroupDefinition, ownedBy owner: GroupID) -> Graph {
        var graph = definition.graph
        for (nodeID, node) in graph.nodes where GroupNodes.isBoundary(node) {
            graph.nodes[nodeID]?.inputValues[NodeSetting.group] = .group(owner)
        }
        return graph
    }
}
````

**Modify** `Sources/CreatorGraph/Groups/GroupNaming.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorGraph/Groups/GroupNaming.swift b/Sources/CreatorGraph/Groups/GroupNaming.swift
index e4a3cb8..9ce1c42 100644
--- a/Sources/CreatorGraph/Groups/GroupNaming.swift
+++ b/Sources/CreatorGraph/Groups/GroupNaming.swift
@@ -4,10 +4,14 @@ import Foundation
 public enum GroupNaming {
     /// `base` if no definition has that name, else "base 2", "base 3", …
     public static func uniqueDefinitionName(_ base: String, among definitions: [GroupID: GroupDefinition]) -> String {
-        let names = Set(definitions.values.map(\.name))
-        guard names.contains(base) else { return base }
+        uniqueName(base, taken: Set(definitions.values.map(\.name)))
+    }
+
+    /// `base` if it isn't in `taken`, else "base 2", "base 3", …
+    static func uniqueName(_ base: String, taken: Set<String>) -> String {
+        guard taken.contains(base) else { return base }
         var number = 2
-        while names.contains("\(base) \(number)") { number += 1 }
+        while taken.contains("\(base) \(number)") { number += 1 }
         return "\(base) \(number)"
     }
 
````

- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter 'GroupExposeTests|GroupMergeTests|GroupLevelTests'`

Expected: every test passes (no "recorded an issue").

- [ ] **Step 5: Lint and run the whole suite**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-editor-test.log`.

Expected: exit code 0; `grep -cE 'recorded an issue|failed after' /tmp/groups-editor-test.log` prints 0; `grep -c 'Test run with' /tmp/groups-editor-test.log` prints 11; the counts on those lines add up to **1668** (master + 25). No new compiler warning.

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorGraph/Groups/GroupCommands+Expose.swift' 'Sources/CreatorGraph/Groups/GroupMerge.swift' 'Sources/CreatorGraph/Groups/GroupNaming.swift' 'Tests/CreatorGraphTests/Groups/GroupExposeTests.swift' 'Tests/CreatorGraphTests/Groups/GroupMergeTests.swift'
git commit -m "feat(groups): expose-socket commands and clipboard merge"
```

---

### Task 4: Levels in the editor: enter, leave, breadcrumbs, edits at the level

`EditorModel` learns levels. `enteredGroups` (the group nodes entered) is view state; `graph` becomes the level's graph, so hit testing, drawing, selection, the inspector and framing all read it unchanged, and every edit goes through `edit(_:coalescingKey:)`, which addresses `graphPath` (one undo step each, via `DocumentModel.perform(_:at:)`). Each level keeps its own pan and zoom (the top level's stay in `ViewState`), the selection clears on changing level, a level entered for the first time frames its nodes, and `refreshLevel()` drops the panel to the level around when Undo removed the group node entered. Document parameters stay on `rootGraph`. States come from `DocumentModel.innerResults` through `result(of:)`/`levelResults`, and `document.inspectedLevel` follows the level. The shared test fixture `GroupedEditor` is added here.

**Files:**
- Create: `Sources/CreatorEditor/Breadcrumb.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Editing.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Groups.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Inspector.swift`
- Create: `Sources/CreatorEditor/EditorModel+Levels.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Nudge.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Pointer.swift`
- Modify: `Sources/CreatorEditor/EditorModel.swift`
- Create: `Tests/CreatorEditorTests/EditorLevelTests.swift`
- Create: `Tests/CreatorEditorTests/Support/GroupedEditor.swift`

**Interfaces:**
- Consumes: T1: `GraphContent.path(entering:)`, `existingLevels(_:)`; T2: `DocumentModel.inspectedLevel`; C1: `GroupCommands.group`, `DocumentModel.perform(_:at:coalescingKey:)`, `innerResults`.
- Produces:
  - `EditorModel`: `enteredGroups`, `levelPath: [NodeID]`, `isInsideGroup`, `graphPath: GraphPath`, `rootGraph`, `graph` (the level's), `edit(_:coalescingKey:) throws(GraphError)`, `result(of:) -> NodeResult?`, `levelResults`, `breadcrumbs: [Breadcrumb]`, `enterGroup(_:) -> Bool`, `exitGroup() -> Bool`, `goToLevel(_:)`, `refreshLevel()`, `transform` per level.
  - `Breadcrumb(title:depth:)`.
  - Test fixture `GroupedEditor` (Number → Rectangle → Extrude → Output with Rectangle and Extrude grouped): `editor`, `number`, `rectangle`, `extrude`, `output`, `group`, `definition`, `current`.

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorEditorTests/EditorLevelTests.swift`:

````swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Entering a group, the breadcrumbs, and editing inside it (groups spec §6).
@MainActor
struct EditorLevelTests {
    @Test func enteringAGroupShowsItsInsideAndClearsTheSelection() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        #expect(editor.enterGroup(grouped.group))
        #expect(editor.levelPath == [grouped.group] && editor.isInsideGroup)
        #expect(editor.graphPath == .definition(grouped.definition.id))
        #expect(editor.selection.isEmpty, "the selection clears on changing level")
        #expect(Set(editor.graph.nodes.keys) == Set(grouped.definition.graph.nodes.keys))
        #expect(editor.rootGraph.nodes.count == 3, "the top level is as it was")
        #expect(editor.document.inspectedLevel == [grouped.group], "the document evaluates what the panel shows")
        #expect(editor.breadcrumbs == [Breadcrumb(title: "Graph", depth: 0), Breadcrumb(title: "Group", depth: 1)])
    }

    @Test func leavingAGroupGoesBackOutAndClearsTheSelectionAgain() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        #expect(!editor.exitGroup(), "nothing to leave on the top level, so the key goes on")
        #expect(editor.enterGroup(grouped.group))
        editor.selectAll()
        #expect(editor.exitGroup())
        #expect(editor.levelPath.isEmpty && editor.graphPath == .root && editor.selection.isEmpty)
        #expect(editor.graph.nodes.count == 3 && editor.document.inspectedLevel.isEmpty)
        #expect(editor.breadcrumbs == [Breadcrumb(title: "Graph", depth: 0)])
    }

    @Test func onlyAGroupNodeCanBeEntered() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        #expect(!editor.enterGroup(grouped.number.id))
        #expect(!editor.enterGroup(NodeID()))
        #expect(!editor.enterGroup(grouped.rectangle.id), "it is inside the group, not on the top level")
        #expect(editor.levelPath.isEmpty)
    }

    @Test func aLockedLevelCantBeEnteredOrLeft() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.isLevelLocked = true
        #expect(!editor.enterGroup(grouped.group) && editor.levelPath.isEmpty, "sketch mode holds the top level")
        editor.isLevelLocked = false
        #expect(editor.enterGroup(grouped.group))
        editor.isLevelLocked = true
        #expect(!editor.exitGroup() && editor.levelPath == [grouped.group])
        editor.goToLevel(0)
        #expect(editor.levelPath == [grouped.group], "a breadcrumb does nothing either")
        editor.isLevelLocked = false
        editor.goToLevel(0)
        #expect(editor.levelPath.isEmpty)
    }

    @Test func breadcrumbsGoBackToAnyLevel() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selection = [grouped.rectangle.id]
        editor.groupSelection()
        let inner = try #require(editor.selection.first)
        #expect(editor.enterGroup(inner))
        #expect(editor.levelPath == [grouped.group, inner])
        #expect(editor.breadcrumbs.map(\.title) == ["Graph", "Group", "Group 2"])
        editor.goToLevel(1)
        #expect(editor.levelPath == [grouped.group] && editor.selection.isEmpty)
        editor.enterGroup(inner)
        editor.goToLevel(0)
        #expect(editor.levelPath.isEmpty)
        editor.goToLevel(0)
        editor.goToLevel(3)
        #expect(editor.levelPath.isEmpty, "the level shown, or a deeper one, does nothing")
    }

    @Test func eachLevelRemembersItsPanAndZoom() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let top = CanvasTransform(offset: Vector2(50, 60), zoom: 2)
        editor.transform = top
        editor.enterGroup(grouped.group)
        #expect(editor.transform != top)
        #expect(editor.document.viewState.canvasZoom == 2, "the top level's is still the saved one")
        let inside = CanvasTransform(offset: Vector2(7, 8), zoom: 1.5)
        editor.transform = inside
        editor.exitGroup()
        #expect(editor.transform == top)
        editor.enterGroup(grouped.group)
        #expect(editor.transform == inside)
        #expect(editor.document.viewState.canvasOffset == Vector2(50, 60), "the inside's pan never reached the file")
    }

    @Test func aLevelEnteredForTheFirstTimeFramesItsNodes() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let visible = CanvasRect(corner: editor.transform.toCanvas(.zero), editor.transform.toCanvas(editor.visibleCanvasSize))
        for node in editor.graph.nodes.values {
            let frame = editor.frame(of: node)
            #expect(visible.contains(frame.origin) && visible.contains(frame.origin + frame.size), "\(node.name)")
        }
    }

    @Test func editsInsideLandInTheDefinitionAsOneUndoStep() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let start = editor.screenPoint(in: grouped.rectangle.id, inset: Vector2(84, 100))
        let before = try #require(grouped.current?.graph.nodes[grouped.rectangle.id]?.position)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(30, 0))
        editor.pointerDragged(from: start, to: start + Vector2(60, 0))
        editor.pointerReleased(from: start, at: start + Vector2(60, 0))
        let moved = try #require(grouped.current?.graph.nodes[grouped.rectangle.id]?.position)
        #expect(moved != before)
        #expect(editor.rootGraph.nodes[grouped.rectangle.id] == nil, "nothing was added to the top level")
        editor.perform(.undo)
        #expect(grouped.current?.graph.nodes[grouped.rectangle.id]?.position == before, "the whole drag is one step")
        #expect(editor.document.canUndo, "the Group step is still there")
    }

    @Test func wiringInsideAGroupGoesToItsDefinition() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let input = try #require(grouped.definition.inputNode)
        let link = Link(from: Endpoint(node: input.id, socket: "width"), to: Endpoint(node: grouped.extrude.id, socket: "distance"))
        editor.connect(link)
        #expect(grouped.current?.graph.links.contains(link) == true)
        #expect(editor.rootGraph.links.contains(link) == false)
        editor.perform(.undo)
        #expect(grouped.current?.graph.links.contains(link) == false)
    }

    @Test func hitTestingAndDrawingSeeTheLevelShown() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        #expect(editor.hitTest(editor.screenPoint(in: grouped.group)) == .node(grouped.group))
        editor.enterGroup(grouped.group)
        // Framed to fit, the level is small on screen: a point in the middle of the node, away from its sockets.
        let middle = editor.screenPoint(in: grouped.rectangle.id, inset: Vector2(84, 100))
        #expect(editor.hitTest(middle) == .node(grouped.rectangle.id))
        #expect(Set(editor.drawnNodes.map(\.id)) == Set(grouped.definition.graph.nodes.keys))
    }

    @Test func undoingTheGroupWhileInsideFallsBackToTheLevelAround() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selectAll()
        editor.document.undo()
        #expect(editor.levelPath.isEmpty, "the group node is gone, so the level shown is the top level")
        #expect(editor.graph.nodes.count == 4 && editor.graphPath == .root)
        editor.refreshLevel()
        #expect(editor.enteredGroups.isEmpty && editor.selection.isEmpty)
        #expect(editor.document.inspectedLevel.isEmpty)
    }

    @Test func documentParametersStayOnTheTopLevelAndShowInsideToo() throws {
        let parameter = GraphParameter(name: "Width", type: .number, value: .number(10))
        let grouped = try GroupedEditor(parameters: [parameter])
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        #expect(editor.inspectorPage.parameters.map(\.parameter.name) == ["Width"])
        editor.setParameter(parameter.id, to: .number(25))
        #expect(editor.rootGraph.parameters.first?.value == .number(25))
        editor.setParameterNumber(parameter.id, to: 30)
        #expect(editor.rootGraph.parameters.first?.value == .number(30))
        #expect(grouped.current?.graph.parameters.isEmpty == true)
    }

    @Test func nodesInsideShowTheirStatesFromTheDocumentsInnerResults() async throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        await editor.document.waitForEvaluation()
        #expect(editor.result(of: grouped.group)?.state.isSuccess == true)
        editor.enterGroup(grouped.group)
        await editor.document.waitForEvaluation()
        #expect(editor.result(of: grouped.rectangle.id)?.state.isSuccess == true)
        #expect(editor.result(of: grouped.group) == nil, "the group node is not on this level")
        #expect(Set(editor.levelResults.keys) == Set(grouped.definition.graph.nodes.keys))
    }
}
````

**Create** `Tests/CreatorEditorTests/Support/GroupedEditor.swift`:

````swift
// Test fixture file: an editor over a document whose Rectangle and Extrude are already grouped.
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Number → Rectangle (`width`) → Extrude → Output, with Rectangle and Extrude grouped (⌘G): the top level then holds
/// Number, the group node (`group`, input `width`, output `solid`) and Output.
@MainActor
struct GroupedEditor {
    let editor: EditorModel
    let number = testNode(NumberTestNode.self, id: 1, at: Vector2(0, 0), registry: editorTestRegistry)
    let rectangle = testNode(RectangleTestNode.self, id: 2, at: Vector2(200, 0), registry: editorTestRegistry)
    let extrude = testNode(ExtrudeTestNode.self, id: 3, at: Vector2(400, 0), registry: editorTestRegistry)
    let output = testNode(OutputTestNode.self, id: 4, at: Vector2(600, 0), registry: editorTestRegistry)
    let group: NodeID
    let definition: GroupDefinition

    init(parameters: [GraphParameter] = []) throws {
        let all = [number, rectangle, extrude, output]
        editor = makeEditor(all, [
            wire(number, "value", rectangle, "width"), wire(rectangle, "profile", extrude, "profile"),
            wire(extrude, "solid", output, "solid"),
        ], parameters: parameters)
        editor.selection = [rectangle.id, extrude.id]
        editor.groupSelection()
        group = try #require(editor.selection.first)
        definition = try #require(editor.document.definitions.values.first)
    }

    /// The definition as it is now.
    var current: GroupDefinition? { editor.document.definitions[definition.id] }
}
````

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep 'error:'`

Expected: the build fails: no `Breadcrumb`, `enterGroup`, `levelPath`, `edit`.

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorEditor/Breadcrumb.swift`:

````swift
/// One level of the graph panel's header, "Graph › Rib › Hole pattern" (groups spec §6): the top level, then each
/// group entered. `depth` is what `EditorModel.goToLevel(_:)` takes.
public struct Breadcrumb: Equatable, Sendable, Identifiable {
    public var title: String
    public var depth: Int

    public var id: Int { depth }

    public init(title: String, depth: Int) {
        self.title = title
        self.depth = depth
    }
}
````

**Modify** `Sources/CreatorEditor/EditorModel+Editing.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/EditorModel+Editing.swift b/Sources/CreatorEditor/EditorModel+Editing.swift
index 954a21b..5724af5 100644
--- a/Sources/CreatorEditor/EditorModel+Editing.swift
+++ b/Sources/CreatorEditor/EditorModel+Editing.swift
@@ -12,7 +12,7 @@ extension EditorModel {
             return
         }
         do {
-            try document.perform(.connect(link))
+            try edit(.connect(link))
         } catch {
             refuse(error.message, node: link.to.node)
         }
@@ -23,7 +23,7 @@ extension EditorModel {
         let ids = selection.filter { graph.nodes[$0] != nil }.sorted()
         guard !ids.isEmpty else { return }
         do {
-            try document.perform(.batch(ids.map { .removeNode($0) }))
+            try edit(.batch(ids.map { .removeNode($0) }))
             selection = []
         } catch {
             refuse(error.message, node: nil)
@@ -61,7 +61,7 @@ extension EditorModel {
     @discardableResult
     func add(_ node: Node) -> Bool {
         do {
-            try document.perform(.addNode(node))
+            try edit(.addNode(node))
             selection = [node.id]
             return true
         } catch {
@@ -98,7 +98,7 @@ extension EditorModel {
         // Copied wires were valid when copied and join only new nodes, so they are restored as they were.
         if !links.isEmpty { commands.append(.restoreLinks(links)) }
         do {
-            try document.perform(.batch(commands))
+            try edit(.batch(commands))
             return CanvasSelection(nodes: Set(mapping.values))
         } catch {
             refuse(error.message, node: nil)
````

**Modify** `Sources/CreatorEditor/EditorModel+Groups.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/EditorModel+Groups.swift b/Sources/CreatorEditor/EditorModel+Groups.swift
index 907a427..907d821 100644
--- a/Sources/CreatorEditor/EditorModel+Groups.swift
+++ b/Sources/CreatorEditor/EditorModel+Groups.swift
@@ -1,12 +1,11 @@
 import CreatorGraph
 
 extension EditorModel {
-    /// ⌘G: groups the selected nodes into a new definition and selects its group node, as one undo step (groups
-    /// spec §5). The panel shows only the top level until C2 adds entering groups, so it groups there. A refused
-    /// group changes nothing and shows its message.
+    /// ⌘G: groups the selected nodes of the level shown into a new definition and selects its group node, as one undo
+    /// step (groups spec §5). A refused group changes nothing and shows its message.
     public func groupSelection() {
         do {
-            let edit = try GroupCommands.group(selection, in: .root, of: document.content, registry: registry)
+            let edit = try GroupCommands.group(selection, in: graphPath, of: document.content, registry: registry)
             try document.perform(edit.command)
             selection = edit.selection
         } catch {
@@ -28,7 +27,7 @@ extension EditorModel {
             return
         }
         do {
-            let edit = try GroupCommands.ungroup(id, in: .root, of: document.content, registry: registry)
+            let edit = try GroupCommands.ungroup(id, in: graphPath, of: document.content, registry: registry)
             try document.perform(edit.command)
             selection = edit.selection
         } catch {
````

**Modify** `Sources/CreatorEditor/EditorModel+Inspector.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/EditorModel+Inspector.swift b/Sources/CreatorEditor/EditorModel+Inspector.swift
index ac93a83..070725a 100644
--- a/Sources/CreatorEditor/EditorModel+Inspector.swift
+++ b/Sources/CreatorEditor/EditorModel+Inspector.swift
@@ -4,7 +4,16 @@ import CreatorKernel
 extension EditorModel {
     /// What the context inspector shows now.
     public var inspectorPage: InspectorPage {
-        InspectorBuilder.page(graph: graph, selection: selection, registry: registry, results: document.results)
+        InspectorBuilder.page(graph: graphWithDocumentParameters, selection: selection, registry: registry,
+                              results: levelResults)
+    }
+
+    /// The graph shown, with the document's parameters: they belong to the top level, and nodes inside a group read
+    /// them too (`Evaluator` hands every level the top level's), so the inspector lists and offers them there.
+    var graphWithDocumentParameters: Graph {
+        var shown = graph
+        shown.parameters = rootGraph.parameters
+        return shown
     }
 
     /// Sets an unwired input. `continuous` edits (slider steps) share one coalescing key per
@@ -14,7 +23,7 @@ extension EditorModel {
         guard value != field.value else { return }
         let key = continuous ? "input-\(field.node.rawValue.uuidString)-\(field.socket.rawValue)" : nil
         do {
-            try document.perform(.setInput(field.node, field.socket, value), coalescingKey: key)
+            try edit(.setInput(field.node, field.socket, value), coalescingKey: key)
         } catch {
             refuse(error.message, node: field.node)
         }
@@ -25,7 +34,7 @@ extension EditorModel {
     public func clearInput(_ field: InputField) {
         guard field.isOptional, graph.nodes[field.node]?.inputValues[field.socket] != nil else { return }
         do {
-            try document.perform(.setInput(field.node, field.socket, nil))
+            try edit(.setInput(field.node, field.socket, nil))
         } catch {
             refuse(error.message, node: field.node)
         }
@@ -68,7 +77,7 @@ extension EditorModel {
 
     /// A number for a parameter, as a whole number for an integer parameter (refused if no `Int` holds it).
     public func setParameterNumber(_ id: ParameterID, to number: Double, continuous: Bool = false) {
-        guard let parameter = graph.parameters.first(where: { $0.id == id }) else { return }
+        guard let parameter = rootGraph.parameters.first(where: { $0.id == id }) else { return }
         guard parameter.type == .integer else {
             setParameter(id, to: .number(number), continuous: continuous)
             return
````

**Create** `Sources/CreatorEditor/EditorModel+Levels.swift`:

````swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// The level the graph panel shows (groups spec §6): the top level, or the inside of a group node entered from it,
/// and so on down. The level is view state, never undone and not saved: `enteredGroups` names the group nodes
/// entered, each by its ID in the graph before it. Everything else in the editor reads `graph`, which is the level's,
/// and edits through `edit(_:coalescingKey:)`, which addresses the level's graph path.
extension EditorModel {
    /// The group nodes entered from the top level, outermost first, that still exist. After Undo removes one, the
    /// panel shows the level around it (`refreshLevel()` makes that official).
    public var levelPath: [NodeID] {
        enteredGroups.isEmpty ? [] : document.content.existingLevels(enteredGroups)
    }

    /// Whether the panel shows the inside of a group.
    public var isInsideGroup: Bool { !levelPath.isEmpty }

    /// The graph the level shows, addressed by commands as `graphPath`.
    public var graphPath: GraphPath {
        enteredGroups.isEmpty ? .root : document.content.path(entering: levelPath) ?? .root
    }

    /// The top-level graph, whichever level is shown: the document's parameters live here.
    public var rootGraph: Graph { document.graph }

    /// Applies `command` to the graph the panel shows, as one undo step (`DocumentModel.perform(_:at:)`).
    public func edit(_ command: GraphCommand, coalescingKey: String? = nil) throws(GraphError) {
        try document.perform(command, at: graphPath, coalescingKey: coalescingKey)
    }

    /// The result of node `id` of the graph shown: from the top-level results, or from the results inside the group
    /// node entered (`DocumentModel.innerResults`), where the document evaluates the whole level
    /// (`DocumentModel.inspectedLevel`).
    public func result(of id: NodeID) -> NodeResult? {
        isInsideGroup ? document.innerResults[levelPath + [id]] : document.results[id]
    }

    /// The results of the graph shown, by node.
    public var levelResults: [NodeID: NodeResult] {
        let path = levelPath
        guard !path.isEmpty else { return document.results }
        var results: [NodeID: NodeResult] = [:]
        for (key, result) in document.innerResults where key.count == path.count + 1 && key.starts(with: path) {
            if let id = key.last { results[id] = result }
        }
        return results
    }

    /// "Graph", then each group entered by its definition's name.
    public var breadcrumbs: [Breadcrumb] {
        var crumbs = [Breadcrumb(title: "Graph", depth: 0)]
        let content = document.content
        var path = GraphPath.root
        for (index, id) in levelPath.enumerated() {
            guard let node = content.graph(at: path)?.nodes[id], let definition = registry.group(of: node) else { break }
            crumbs.append(Breadcrumb(title: definition.name, depth: index + 1))
            path = .definition(definition.id)
        }
        return crumbs
    }

    /// Enters group node `id` of the graph shown (a double click, ⌘↓, "Edit Group"). The selection clears, and the
    /// level shows with the pan and zoom it had last time, or framing everything the first time. Returns false for
    /// anything that isn't a group node whose definition exists, while a drag is under way, or while the level is
    /// locked (`isLevelLocked`).
    @discardableResult
    public func enterGroup(_ id: NodeID) -> Bool {
        let entered = levelPath + [id]
        guard interaction == nil, !isLevelLocked, document.content.path(entering: entered) != nil else { return false }
        changeLevel(to: entered)
        return true
    }

    /// ⌘↑: out of the group shown, one level. Returns false on the top level, so the key goes on.
    @discardableResult
    public func exitGroup() -> Bool {
        guard isInsideGroup, interaction == nil, !isLevelLocked else { return false }
        changeLevel(to: Array(levelPath.dropLast()))
        return true
    }

    /// A click on a breadcrumb: back out to `depth` (0 is the top level). Does nothing for the level shown, or a
    /// deeper one, or while the level is locked.
    public func goToLevel(_ depth: Int) {
        guard depth >= 0, depth < levelPath.count, interaction == nil, !isLevelLocked else { return }
        changeLevel(to: Array(levelPath.prefix(depth)))
    }

    /// Makes a level that no longer exists official: after Undo removes the group node entered, the panel falls back to
    /// the level around it, with nothing selected. Call it after anything that undoes or redoes.
    public func refreshLevel() {
        let existing = levelPath
        guard existing != enteredGroups else { return }
        changeLevel(to: existing)
    }

    /// Shows `levels`: commits a typed value for the node it was typed on, clears the selection, closes the palette,
    /// and gives the new level its own pan and zoom.
    private func changeLevel(to levels: [NodeID]) {
        commitPendingEntry()
        clearSelection()
        palette = nil
        lastNodeClick = nil
        enteredGroups = levels
        document.inspectedLevel = levels
        if !levels.isEmpty, levelTransforms[levels] == nil, let all = bounds(of: allItems) {
            transform = .framing(all, in: visibleCanvasSize, padding: Self.framingPadding)
        }
    }
}
````

**Modify** `Sources/CreatorEditor/EditorModel+Nudge.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/EditorModel+Nudge.swift b/Sources/CreatorEditor/EditorModel+Nudge.swift
index f64f8db..7ddd2ca 100644
--- a/Sources/CreatorEditor/EditorModel+Nudge.swift
+++ b/Sources/CreatorEditor/EditorModel+Nudge.swift
@@ -16,7 +16,7 @@ extension EditorModel {
             document.endCoalescing()
             nudgeKey = "nudge-\(UUID().uuidString)"
         }
-        try? document.perform(.batch(moveCommands(from: start, by: flow.stored(delta))), coalescingKey: nudgeKey)
+        try? edit(.batch(moveCommands(from: start, by: flow.stored(delta))), coalescingKey: nudgeKey)
         return true
     }
 }
````

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/EditorModel+Pointer.swift b/Sources/CreatorEditor/EditorModel+Pointer.swift
index c83108f..0ae9fc0 100644
--- a/Sources/CreatorEditor/EditorModel+Pointer.swift
+++ b/Sources/CreatorEditor/EditorModel+Pointer.swift
@@ -125,7 +125,7 @@ extension EditorModel {
         case .panning(let startOffset):
             transform = CanvasTransform(offset: startOffset + (location - pressPoint), zoom: transform.zoom)
         case .moving(let start, let key):
-            try? document.perform(.batch(moveCommands(from: start, by: storedDelta)), coalescingKey: key)
+            try? edit(.batch(moveCommands(from: start, by: storedDelta)), coalescingKey: key)
         case .duplicating(let start, _):
             setInteraction(.duplicating(start: start, delta: storedDelta))
         case .boxSelecting(let start, _, let base, let mode):
@@ -154,7 +154,7 @@ extension EditorModel {
             // Dragging a wired input off onto empty canvas removes its wire.
             if wire.from.isInput, let link = graph.incomingLink(to: wire.from.endpoint) {
                 do {
-                    try document.perform(.disconnect(link))
+                    try edit(.disconnect(link))
                 } catch {
                     refuse(error.message, node: link.to.node)
                 }
````

**Modify** `Sources/CreatorEditor/EditorModel.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/EditorModel.swift b/Sources/CreatorEditor/EditorModel.swift
index 16705be..3f5dc2c 100644
--- a/Sources/CreatorEditor/EditorModel.swift
+++ b/Sources/CreatorEditor/EditorModel.swift
@@ -30,6 +30,16 @@ public final class EditorModel {
         set { canvasSelection = CanvasSelection(nodes: newValue) }
     }
 
+    /// The group nodes entered from the top level (`EditorModel+Levels`). Read `levelPath`, which leaves out any that
+    /// no longer exist.
+    public internal(set) var enteredGroups: [NodeID] = []
+    /// True while the host needs the level shown to stay as it is (the app: sketch mode, which works on the top level's
+    /// graph). `enterGroup`, `exitGroup` and `goToLevel` do nothing meanwhile, so no key or click changes the level
+    /// under an open sketch.
+    public var isLevelLocked = false
+    /// The pan and zoom each group level had when it was last shown, by `levelPath`.
+    var levelTransforms: [[NodeID]: CanvasTransform] = [:]
+
     /// The pointer over the canvas, in canvas-local screen points; `nil` when it is elsewhere.
     public var pointerLocation: Vector2?
     public private(set) var interaction: CanvasInteraction?
@@ -84,7 +94,10 @@ public final class EditorModel {
         if document.viewState.dock != .hidden { lastVisibleDock = document.viewState.dock }
     }
 
-    public var graph: Graph { document.graph }
+    /// The graph the panel shows: the top level's, or the inside of the group entered (`EditorModel+Levels`).
+    public var graph: Graph {
+        enteredGroups.isEmpty ? document.graph : document.content.graph(at: graphPath) ?? document.graph
+    }
     public var registry: NodeRegistry { document.registry }
 
     // MARK: - Dock and transform
@@ -105,11 +118,21 @@ public final class EditorModel {
         setDock(isPanelVisible ? .hidden : lastVisibleDock)
     }
 
+    /// Pan and zoom of the level shown. The top level's are saved with the file; each group's inside remembers its
+    /// own while the document is open (view state, not undone).
     public var transform: CanvasTransform {
-        get { CanvasTransform(document.viewState) }
+        get {
+            let levels = levelPath
+            return levels.isEmpty ? CanvasTransform(document.viewState) : levelTransforms[levels] ?? CanvasTransform()
+        }
         set {
-            document.viewState.canvasOffset = newValue.offset
-            document.viewState.canvasZoom = newValue.zoom
+            let levels = levelPath
+            if levels.isEmpty {
+                document.viewState.canvasOffset = newValue.offset
+                document.viewState.canvasZoom = newValue.zoom
+            } else if newValue.offset.isFinite {
+                levelTransforms[levels] = newValue
+            }
         }
     }
 
````

- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter 'EditorLevelTests'`

Expected: every test passes (no "recorded an issue").

- [ ] **Step 5: Lint and run the whole suite**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-editor-test.log`.

Expected: exit code 0; `grep -cE 'recorded an issue|failed after' /tmp/groups-editor-test.log` prints 0; `grep -c 'Test run with' /tmp/groups-editor-test.log` prints 11; the counts on those lines add up to **1681** (master + 38). No new compiler warning.

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorEditor/Breadcrumb.swift' 'Sources/CreatorEditor/EditorModel+Editing.swift' 'Sources/CreatorEditor/EditorModel+Groups.swift' 'Sources/CreatorEditor/EditorModel+Inspector.swift' 'Sources/CreatorEditor/EditorModel+Levels.swift' 'Sources/CreatorEditor/EditorModel+Nudge.swift' 'Sources/CreatorEditor/EditorModel+Pointer.swift' 'Sources/CreatorEditor/EditorModel.swift' 'Tests/CreatorEditorTests/EditorLevelTests.swift' 'Tests/CreatorEditorTests/Support/GroupedEditor.swift'
git commit -m "feat(groups): the graph panel shows a level; edits address it"
```

---

### Task 5: Entering by ⌘↓, double click and Edit Group; leaving by ⌘↑; group commands at the level

⌘↓ and ⌘↑ are `GraphKeyCommand`s. A double click on a group node reuses S5b's recogniser (`doubleClickActions` gains `.editGroup`, no second recogniser), which now runs after the click it ends on so the click that entered doesn't select the group node inside. `press(_:on:)` carries out the group node's Edit Group, Make Unique and Ungroup itself and still records the others for the app shell. Group, Ungroup and Make Unique act on the level shown. Undo and Redo keys call `refreshLevel()`.

**Files:**
- Modify: `Sources/CreatorEditor/EditorModel+Commands.swift`
- Modify: `Sources/CreatorEditor/EditorModel+DoubleClick.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Groups.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Inspector.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Pointer.swift`
- Modify: `Sources/CreatorEditor/GraphKeyBindings.swift`
- Modify: `Sources/CreatorEditor/GraphKeyCommand.swift`
- Create: `Tests/CreatorEditorTests/EditorGroupEntryTests.swift`

**Interfaces:**
- Consumes: T4: `enterGroup`, `exitGroup`, `refreshLevel`, `graphPath`; T1: `InspectorAction.editGroup` etc.; S5b: `pairClick`, `doubleClickActions`, `nodeDoubleClicked`.
- Produces:
  - `GraphKeyCommand.enterGroup`, `.exitGroup`; ⌘↓/⌘↑ in `GraphKeyBindings.commandChord` (⇧ declines).
  - `EditorModel.makeUnique(_:)`, `ungroup(_:)`; `groupSelection()`/`ungroupSelection()` at `graphPath`.
  - `EditorModel.press(_:on:)` runs `.editGroup`, `.makeUnique`, `.ungroup` locally.

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorEditorTests/EditorGroupEntryTests.swift`:

````swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// Entering a group by ⌘↓, a double click and "Edit Group", leaving by ⌘↑, and the group commands inside a level
/// (groups spec §6).
@MainActor
struct EditorGroupEntryTests {
    func key(_ characters: String, _ modifiers: Modifiers) -> KeyEvent {
        KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers, timestamp: 0)
    }

    @Test func commandDownAndUpAreTheEnterAndExitKeys() {
        #expect(GraphKeyBindings.command(for: key("\u{f701}", .command), paletteOpen: false) == .enterGroup)
        #expect(GraphKeyBindings.command(for: key("\u{f700}", .command), paletteOpen: false) == .exitGroup)
        #expect(GraphKeyBindings.command(for: key("\u{f701}", [.command, .shift]), paletteOpen: false) == nil)
        #expect(GraphKeyBindings.command(for: key("\u{f701}", .command), paletteOpen: true) == nil)
        #expect(GraphKeyBindings.command(for: key("\u{f701}", []), paletteOpen: false) == .nudge(Vector2(0, 1), isRepeat: false),
                "a plain arrow still nudges")
    }

    @Test func commandDownEntersTheSelectedGroupNodeAndCommandUpLeaves() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.clearSelection()
        #expect(!editor.perform(.enterGroup), "nothing selected: the key goes on")
        editor.selection = [grouped.number.id]
        #expect(!editor.perform(.enterGroup), "not a group node")
        editor.selection = [grouped.group]
        #expect(editor.perform(.enterGroup))
        #expect(editor.levelPath == [grouped.group])
        #expect(editor.perform(.exitGroup))
        #expect(editor.levelPath.isEmpty)
        #expect(!editor.perform(.exitGroup), "nothing to leave on the top level")
    }

    @Test func theEnterAndExitKeysWaitForAVisiblePanel() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.setDock(.hidden)
        #expect(!editor.perform(.enterGroup))
        editor.setDock(.bottom)
        editor.enterGroup(grouped.group)
        editor.setDock(.hidden)
        #expect(!editor.perform(.exitGroup))
        #expect(editor.levelPath == [grouped.group])
    }

    @Test func aDoubleClickOnAGroupNodeEntersItAndSelectsNothingInside() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let clock = TestClock()
        editor.now = { clock.now }
        let point = editor.screenPoint(in: grouped.group)
        editor.click(point)
        #expect(editor.levelPath.isEmpty && editor.selection == [grouped.group], "one click only selects")
        clock.advance(by: .milliseconds(200))
        editor.click(point + Vector2(2, 1))
        #expect(editor.levelPath == [grouped.group])
        #expect(editor.selection.isEmpty, "the click that entered didn't select the group node in its own inside")
    }

    @Test func aSlowOrWanderingDoubleClickDoesNotEnter() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let clock = TestClock()
        editor.now = { clock.now }
        let point = editor.screenPoint(in: grouped.group)
        editor.click(point)
        clock.advance(by: .milliseconds(450))
        editor.click(point)
        clock.advance(by: .milliseconds(100))
        editor.click(point + Vector2(8, 0))
        #expect(editor.levelPath.isEmpty)
    }

    @Test func theInspectorButtonsEnterMakeUniqueAndUngroup() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        let rows = try #require(editor.inspectorPage.sections.first { $0.title == "Group" }?.rows)
        #expect(rows == [
            .button(title: "Edit Group", action: .editGroup), .button(title: "Make Unique", action: .makeUnique),
            .button(title: "Ungroup", action: .ungroup),
        ])
        editor.press(.makeUnique, on: grouped.group)
        #expect(editor.document.definitions.count == 2)
        #expect(editor.graph.nodes[grouped.group]?.name == "Group 2")
        editor.press(.editGroup, on: grouped.group)
        #expect(editor.levelPath == [grouped.group])
        #expect(editor.document.definitions[grouped.definition.id] != nil)
        editor.exitGroup()
        editor.press(.ungroup, on: grouped.group)
        #expect(editor.graph.nodes.count == 4 && editor.graph.nodes[grouped.group] == nil)
        #expect(editor.inspectorRequest == nil, "the panel carried these out itself")
    }

    @Test func groupAndUngroupWorkOnTheLevelShown() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selection = [grouped.extrude.id]
        editor.groupSelection()
        let inner = try #require(editor.selection.first)
        #expect(editor.graph.nodes[inner]?.typeID == GroupNodes.groupTypeID)
        #expect(editor.graph.nodes[grouped.extrude.id] == nil)
        #expect(editor.rootGraph.nodes.count == 3, "the top level was not touched")
        editor.ungroupSelection()
        #expect(editor.graph.nodes.count == 4 && editor.document.definitions.count == 1)
        editor.perform(.undo)
        #expect(editor.graph.nodes[inner]?.typeID == GroupNodes.groupTypeID, "undo is one step per command")
    }

    @Test func undoingTheGroupFromInsideLeavesTheGroup() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.perform(.undo)
        #expect(editor.enteredGroups.isEmpty && editor.graph.nodes.count == 4)
        editor.perform(.redo)
        #expect(editor.levelPath.isEmpty && editor.graph.nodes[grouped.group] != nil, "redo doesn't pull the panel back in")
    }
}
````

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep 'error:'`

Expected: the build fails: no `.enterGroup`/`.exitGroup` key commands.

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorEditor/EditorModel+Commands.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/EditorModel+Commands.swift b/Sources/CreatorEditor/EditorModel+Commands.swift
index 13c1aa3..e8a8558 100644
--- a/Sources/CreatorEditor/EditorModel+Commands.swift
+++ b/Sources/CreatorEditor/EditorModel+Commands.swift
@@ -13,7 +13,7 @@ extension EditorModel {
             deleteSelection()
         case .selectAll, .nudge, .frameSelection:
             return performSelectionCommand(command)
-        case .group, .ungroup:
+        case .group, .ungroup, .enterGroup, .exitGroup:
             return performGroupKey(command)
         case .copy, .paste, .duplicate, .zoomIn, .zoomOut, .undo, .redo:
             performEdit(command)
@@ -47,8 +47,12 @@ extension EditorModel {
         case .duplicate: duplicateSelection()
         case .zoomIn: zoom(in: true)
         case .zoomOut: zoom(in: false)
-        case .undo: document.undo()
-        case .redo: document.redo()
+        case .undo:
+            document.undo()
+            refreshLevel()
+        case .redo:
+            document.redo()
+            refreshLevel()
         default: break // `perform(_:)` routes every other command elsewhere.
         }
     }
````

**Modify** `Sources/CreatorEditor/EditorModel+DoubleClick.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/EditorModel+DoubleClick.swift b/Sources/CreatorEditor/EditorModel+DoubleClick.swift
index afa3b86..887eafd 100644
--- a/Sources/CreatorEditor/EditorModel+DoubleClick.swift
+++ b/Sources/CreatorEditor/EditorModel+DoubleClick.swift
@@ -11,9 +11,9 @@ extension EditorModel {
     public static let doubleClickInterval = Duration.milliseconds(400)
     /// How far apart a double click's two clicks may land, in screen points.
     public static let doubleClickSlop = 4.0
-    /// The inspector buttons a double click presses; the first of them a node's inspector has wins. The groups
-    /// editor adds its "Edit Group" action here.
-    static let doubleClickActions: [InspectorAction] = [.editSketch]
+    /// The inspector buttons a double click presses; the first of them a node's inspector has wins: a Sketch node's
+    /// "Edit sketch", a group node's "Edit Group" (groups spec §6).
+    static let doubleClickActions: [InspectorAction] = [.editSketch, .editGroup]
 
     /// A press released without a drag, on `hit` at `point` with `modifiers` held: the second click with no modifiers
     /// on one node's body is a double click (`nodeDoubleClicked`); any other click on a body starts a new pair, and a
````

**Modify** `Sources/CreatorEditor/EditorModel+Groups.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/EditorModel+Groups.swift b/Sources/CreatorEditor/EditorModel+Groups.swift
index 907d821..aa4f6c1 100644
--- a/Sources/CreatorEditor/EditorModel+Groups.swift
+++ b/Sources/CreatorEditor/EditorModel+Groups.swift
@@ -1,37 +1,67 @@
 import CreatorGraph
+import CreatorKernel
 
 extension EditorModel {
     /// ⌘G: groups the selected nodes of the level shown into a new definition and selects its group node, as one undo
     /// step (groups spec §5). A refused group changes nothing and shows its message.
     public func groupSelection() {
-        do {
-            let edit = try GroupCommands.group(selection, in: graphPath, of: document.content, registry: registry)
-            try document.perform(edit.command)
-            selection = edit.selection
-        } catch {
-            refuse(error.message, node: nil)
+        run(refusing: nil) { () throws(GraphError) in
+            try GroupCommands.group(selection, in: graphPath, of: document.content, registry: registry)
         }
     }
 
-    /// ⌘G and ⇧⌘G. Returns false with nothing selected, so the key can go on.
-    func performGroupKey(_ command: GraphKeyCommand) -> Bool {
-        guard !selection.isEmpty else { return false }
-        if command == .ungroup { ungroupSelection() } else { groupSelection() }
-        return true
-    }
-
     /// ⇧⌘G: ungroups the one selected group node and selects the nodes it spliced back, as one undo step.
     public func ungroupSelection() {
         guard selection.count == 1, let id = selection.first else {
             refuse("Select one group node to ungroup.", node: nil)
             return
         }
+        ungroup(id)
+    }
+
+    /// Ungroups group node `id` of the level shown (its inspector's Ungroup, or ⇧⌘G).
+    public func ungroup(_ id: NodeID) {
+        run(refusing: id) { () throws(GraphError) in
+            try GroupCommands.ungroup(id, in: graphPath, of: document.content, registry: registry)
+        }
+    }
+
+    /// Make Unique on group node `id` of the level shown: it gets its own copy of the definition, as one undo step.
+    public func makeUnique(_ id: NodeID) {
+        run(refusing: id) { () throws(GraphError) in
+            try GroupCommands.makeUnique(id, in: graphPath, of: document.content, registry: registry)
+        }
+    }
+
+    /// Performs the group command `build` makes as one undo step and selects what it says, or shows why it was
+    /// refused (shaking `node`).
+    private func run(refusing node: NodeID?, _ build: () throws(GraphError) -> GroupEdit) {
         do {
-            let edit = try GroupCommands.ungroup(id, in: graphPath, of: document.content, registry: registry)
+            let edit = try build()
             try document.perform(edit.command)
             selection = edit.selection
         } catch {
-            refuse(error.message, node: id)
+            refuse(error.message, node: node)
+        }
+    }
+
+    /// ⌘G, ⇧⌘G, ⌘↓ and ⌘↑. Returns false when the key does nothing here, so it can go on: ⌘G and ⇧⌘G with nothing
+    /// selected, ⌘↓ without one group node selected, ⌘↑ on the top level, and all four while the panel is hidden.
+    /// During a drag they are claimed and do nothing, so a move stays one undo step.
+    func performGroupKey(_ command: GraphKeyCommand) -> Bool {
+        switch command {
+        case .group, .ungroup:
+            guard !selection.isEmpty else { return false }
+            if command == .ungroup { ungroupSelection() } else { groupSelection() }
+            return true
+        case .enterGroup, .exitGroup:
+            guard isPanelVisible else { return false }
+            guard interaction == nil else { return true }
+            if command == .exitGroup { return exitGroup() }
+            guard selection.count == 1, let id = selection.first else { return false }
+            return enterGroup(id)
+        default:
+            return false
         }
     }
 }
````

**Modify** `Sources/CreatorEditor/EditorModel+Inspector.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/EditorModel+Inspector.swift b/Sources/CreatorEditor/EditorModel+Inspector.swift
index 070725a..583f400 100644
--- a/Sources/CreatorEditor/EditorModel+Inspector.swift
+++ b/Sources/CreatorEditor/EditorModel+Inspector.swift
@@ -89,9 +89,19 @@ extension EditorModel {
         setParameter(id, to: .integer(whole), continuous: continuous)
     }
 
-    /// An inspector button: recorded for the viewport, which owns pick mode (M4/M6).
+    /// An inspector button. A group node's (Edit Group, Make Unique, Ungroup) the panel carries out itself; the rest are
+    /// recorded for the app shell, which owns pick mode and the sketch (M4/M6).
     public func press(_ action: InspectorAction, on node: NodeID) {
-        requestSerial += 1
-        setInspectorRequest(InspectorRequest(node: node, action: action, serial: requestSerial))
+        switch action {
+        case .editGroup:
+            enterGroup(node)
+        case .makeUnique:
+            makeUnique(node)
+        case .ungroup:
+            ungroup(node)
+        case .pickEdgesInView, .pickFacesInView, .editSketch:
+            requestSerial += 1
+            setInspectorRequest(InspectorRequest(node: node, action: action, serial: requestSerial))
+        }
     }
 }
````

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/EditorModel+Pointer.swift b/Sources/CreatorEditor/EditorModel+Pointer.swift
index 0ae9fc0..f82966c 100644
--- a/Sources/CreatorEditor/EditorModel+Pointer.swift
+++ b/Sources/CreatorEditor/EditorModel+Pointer.swift
@@ -32,9 +32,12 @@ extension EditorModel {
             endPress()
             return
         }
-        if interaction == nil { pairClick(on: press.hit, at: press.point, modifiers: press.modifiers) } else { lastNodeClick = nil }
+        if interaction != nil { lastNodeClick = nil }
         switch interaction {
-        case nil: click(press.hit, mode: SelectionMode(press.modifiers))
+        case nil:
+            click(press.hit, mode: SelectionMode(press.modifiers))
+            // After the click: a double click on a group node enters it, and the click must not select it afterwards.
+            pairClick(on: press.hit, at: press.point, modifiers: press.modifiers)
         case .moving: document.endCoalescing()
         case .duplicating(let start, let delta): finishDuplicate(start: start, delta: delta)
         case .connecting(let wire): finishWire(wire, at: location)
````

**Modify** `Sources/CreatorEditor/GraphKeyBindings.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/GraphKeyBindings.swift b/Sources/CreatorEditor/GraphKeyBindings.swift
index 864c7dd..0860ef7 100644
--- a/Sources/CreatorEditor/GraphKeyBindings.swift
+++ b/Sources/CreatorEditor/GraphKeyBindings.swift
@@ -49,7 +49,8 @@ public enum GraphKeyBindings {
         }
     }
 
-    /// ⌘ chords; `character` is already lowercased, and ⇧ turns ⌘Z into redo and ⌘G into ungroup.
+    /// ⌘ chords; `character` is already lowercased, and ⇧ turns ⌘Z into redo and ⌘G into ungroup. ⌘↓ and ⌘↑ (the
+    /// arrows' private-use characters) go into and out of a group.
     static func commandChord(for character: String, shifted: Bool) -> GraphKeyCommand? {
         switch character {
         case "c": .copy
@@ -58,6 +59,8 @@ public enum GraphKeyBindings {
         case "a": shifted ? nil : .selectAll
         case "g": shifted ? .ungroup : .group
         case "z": shifted ? .redo : .undo
+        case "\u{f701}": shifted ? nil : .enterGroup
+        case "\u{f700}": shifted ? nil : .exitGroup
         default: nil
         }
     }
````

**Modify** `Sources/CreatorEditor/GraphKeyCommand.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/GraphKeyCommand.swift b/Sources/CreatorEditor/GraphKeyCommand.swift
index 71d9f3b..a19a308 100644
--- a/Sources/CreatorEditor/GraphKeyCommand.swift
+++ b/Sources/CreatorEditor/GraphKeyCommand.swift
@@ -22,6 +22,10 @@ public enum GraphKeyCommand: Equatable, Sendable {
     case group
     /// ⇧⌘G: ungroups the selected group node.
     case ungroup
+    /// ⌘↓: enters the selected group node.
+    case enterGroup
+    /// ⌘↑: goes back out of the group shown.
+    case exitGroup
     case zoomIn
     case zoomOut
     case undo
````

- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter 'EditorGroupEntryTests|KeyCommandTests|DoubleClickTests|GroupKeyTests'`

Expected: every test passes (no "recorded an issue").

- [ ] **Step 5: Lint and run the whole suite**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-editor-test.log`.

Expected: exit code 0; `grep -cE 'recorded an issue|failed after' /tmp/groups-editor-test.log` prints 0; `grep -c 'Test run with' /tmp/groups-editor-test.log` prints 11; the counts on those lines add up to **1689** (master + 46). No new compiler warning.

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorEditor/EditorModel+Commands.swift' 'Sources/CreatorEditor/EditorModel+DoubleClick.swift' 'Sources/CreatorEditor/EditorModel+Groups.swift' 'Sources/CreatorEditor/EditorModel+Inspector.swift' 'Sources/CreatorEditor/EditorModel+Pointer.swift' 'Sources/CreatorEditor/GraphKeyBindings.swift' 'Sources/CreatorEditor/GraphKeyCommand.swift' 'Tests/CreatorEditorTests/EditorGroupEntryTests.swift'
git commit -m "feat(groups): enter by key, double click and Edit Group; group commands at the level"
```

---

### Task 6: The clipboard carries definitions; Group Input and Output stay put

`NodeClipboard` gains `definitions` (every definition the copied group nodes use, however deep). A paste asks `GroupMerge.plan` what to add and retargets the pasted group nodes, all in one undo step with the nodes; the additions are top-level commands while the nodes go to the level shown. A definition counts as already there when some definition of the document equals it ignoring ID and name, so pasting the same clipboard again, or after the definition was renamed, adds nothing new. Group Input and Group Output are never copied or duplicated, and Delete leaves them (it says why when they are all that was selected).

**Files:**
- Modify: `Sources/CreatorEditor/EditorModel+Editing.swift`
- Modify: `Sources/CreatorEditor/NodeClipboard.swift`
- Create: `Tests/CreatorEditorTests/EditorGroupClipboardTests.swift`

**Interfaces:**
- Consumes: T3: `GroupMerge`; T4: `edit`, `graphPath`.
- Produces:
  - `NodeClipboard.definitions: [GroupID: GroupDefinition]`.
  - `EditorModel.isBoundary(_:)` (internal); `clipboard(of:)` leaves boundary nodes out; `insert(_:offset:)` merges definitions.

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorEditorTests/EditorGroupClipboardTests.swift`:

````swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// The clipboard carries the definitions copied group nodes use, merged by content on paste (groups spec §9), and
/// never Group Input or Group Output.
@MainActor
struct EditorGroupClipboardTests {
    @Test func copyingAGroupNodeCarriesItsDefinition() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.copySelection()
        #expect(editor.clipboard?.definitions == [grouped.definition.id: grouped.definition])
        editor.selection = [grouped.number.id]
        editor.copySelection()
        #expect(editor.clipboard?.definitions.isEmpty == true, "a number needs no definition")
    }

    @Test func pastingNextToItsDefinitionPlacesAnotherInstanceAndAddsNothing() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.copySelection()
        editor.paste()
        let copy = try #require(editor.selection.first)
        #expect(copy != grouped.group)
        #expect(editor.document.definitions.count == 1, "same content: merged")
        #expect(editor.graph.nodes[copy]?.inputValues[NodeSetting.group] == .group(grouped.definition.id))
    }

    @Test func aDefinitionTheDocumentLostComesBackWithThePaste() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.copySelection()
        editor.ungroupSelection()
        #expect(editor.document.definitions.isEmpty)
        editor.paste()
        let copy = try #require(editor.selection.first)
        #expect(editor.document.definitions[grouped.definition.id] == grouped.definition, "added as it was")
        #expect(editor.graph.nodes[copy]?.typeID == GroupNodes.groupTypeID)
        editor.perform(.undo)
        #expect(editor.document.definitions.isEmpty && editor.graph.nodes[copy] == nil, "the paste is one undo step")
    }

    @Test func aDefinitionEditedSinceTheCopyComesInBesideTheEditedOne() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.copySelection()
        editor.enterGroup(grouped.group)
        let start = editor.screenPoint(in: grouped.rectangle.id, inset: Vector2(84, 100))
        editor.drag(start, start + Vector2(40, 0))
        editor.exitGroup()
        editor.paste()
        let copy = try #require(editor.selection.first)
        #expect(editor.document.definitions.count == 2)
        let copied = try #require(editor.graph.nodes[copy])
        let imported = try #require(editor.registry.group(of: copied))
        #expect(imported.id != grouped.definition.id && imported.name == "Group (imported)")
        #expect(imported.graph.nodes[grouped.rectangle.id]?.position
                == grouped.definition.graph.nodes[grouped.rectangle.id]?.position, "the copy is the definition as it was copied")
        #expect(grouped.current?.graph.nodes[grouped.rectangle.id]?.position
                != grouped.definition.graph.nodes[grouped.rectangle.id]?.position, "and the edit stayed in the original")
        #expect(editor.graph.nodes[grouped.group]?.inputValues[NodeSetting.group] == .group(grouped.definition.id),
                "the node already there still uses the edited one")
    }

    @Test func pastingTheSameStaleCopyTwiceAddsItsDefinitionOnce() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.copySelection()
        editor.enterGroup(grouped.group)
        let start = editor.screenPoint(in: grouped.rectangle.id, inset: Vector2(84, 100))
        editor.drag(start, start + Vector2(40, 0))
        editor.exitGroup()
        editor.paste()
        let first = try #require(editor.selection.first)
        editor.paste()
        let second = try #require(editor.selection.first)
        #expect(first != second && editor.document.definitions.count == 2, "the second paste reuses the first one's copy")
        let imported = editor.graph.nodes[first]?.inputValues[NodeSetting.group]
        #expect(imported != .group(grouped.definition.id) && editor.graph.nodes[second]?.inputValues[NodeSetting.group] == imported)
        editor.perform(.undo)
        #expect(editor.document.definitions.count == 2 && editor.graph.nodes[second] == nil, "undo takes back the second node only")
    }

    @Test func renamingTheDefinitionAfterCopyingDoesNotMakeThePasteACopy() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.copySelection()
        try editor.document.perform(GroupCommands.rename(grouped.definition.id, to: "Rib", in: editor.document.content))
        editor.paste()
        let copy = try #require(editor.selection.first)
        #expect(editor.document.definitions.count == 1, "only the name changed")
        #expect(editor.graph.nodes[copy]?.inputValues[NodeSetting.group] == .group(grouped.definition.id))
    }

    @Test func nestedDefinitionsTravelAndMerge() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selection = [grouped.rectangle.id]
        editor.groupSelection()
        editor.exitGroup()
        editor.selection = [grouped.group]
        editor.copySelection()
        #expect(editor.clipboard?.definitions.count == 2, "the group and the group inside it")
        editor.paste()
        #expect(editor.document.definitions.count == 2)
    }

    @Test func groupInputAndOutputAreNeverCopiedDuplicatedOrDeleted() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selectAll()
        editor.copySelection()
        #expect(editor.clipboard?.nodes.map(\.id).sorted() == [grouped.rectangle.id, grouped.extrude.id].sorted())
        editor.paste()
        #expect(editor.graph.nodes.count == 6, "two nodes pasted, not the boundary")
        #expect(editor.graph.nodes.values.filter(GroupNodes.isBoundary).count == 2)
        editor.selectAll()
        editor.deleteSelection()
        #expect(editor.graph.nodes.values.allSatisfy(GroupNodes.isBoundary) && editor.graph.nodes.count == 2)
        editor.perform(.undo)
        #expect(editor.graph.nodes.count == 6, "the delete was one step")
    }

    @Test func deletingOnlyTheBoundaryExplainsWhyNothingHappened() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let boundary = Set(editor.graph.nodes.values.filter(GroupNodes.isBoundary).map(\.id))
        editor.selection = boundary
        editor.perform(.deleteSelection)
        #expect(editor.refusal?.message == "A group's Group Input and Group Output can't be deleted.")
        #expect(editor.graph.nodes.count == 4)
    }

    @Test func aGroupCantBePastedIntoItself() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.copySelection()
        editor.enterGroup(grouped.group)
        let before = editor.document.content
        editor.paste()
        #expect(editor.refusal?.message == "A group can't contain itself.")
        #expect(editor.document.content == before)
    }

    @Test func duplicatingAGroupNodeInsideAGroupPlacesAnotherInstance() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selection = [grouped.rectangle.id]
        editor.groupSelection()
        let inner = try #require(editor.selection.first)
        editor.perform(.duplicate)
        let copy = try #require(editor.selection.first)
        #expect(copy != inner && editor.document.definitions.count == 2)
        #expect(editor.graph.nodes[copy]?.inputValues[NodeSetting.group] == editor.graph.nodes[inner]?.inputValues[NodeSetting.group])
    }
}
````

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep 'error:'`

Expected: the build fails: `NodeClipboard` has no `definitions`.

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorEditor/EditorModel+Editing.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/EditorModel+Editing.swift b/Sources/CreatorEditor/EditorModel+Editing.swift
index 5724af5..6922417 100644
--- a/Sources/CreatorEditor/EditorModel+Editing.swift
+++ b/Sources/CreatorEditor/EditorModel+Editing.swift
@@ -18,10 +18,15 @@ extension EditorModel {
         }
     }
 
-    /// Delete / ⌫: removes the selected nodes and their wires, as one undo step.
+    /// Delete / ⌫: removes the selected nodes and their wires, as one undo step. Group Input and Group Output stay
+    /// (a group always has both); with only those selected, it says why nothing happened.
     public func deleteSelection() {
-        let ids = selection.filter { graph.nodes[$0] != nil }.sorted()
-        guard !ids.isEmpty else { return }
+        let present = selection.filter { graph.nodes[$0] != nil }
+        let ids = present.filter { !isBoundary($0) }.sorted()
+        guard !ids.isEmpty else {
+            if !present.isEmpty { refuse("A group's Group Input and Group Output can't be deleted.", node: nil) }
+            return
+        }
         do {
             try edit(.batch(ids.map { .removeNode($0) }))
             selection = []
@@ -70,22 +75,31 @@ extension EditorModel {
         }
     }
 
-    /// What copying `items` puts on the clipboard: their nodes and the wires between them. B adds: comments.
+    /// What copying `items` puts on the clipboard: their nodes and the wires between them, and the definitions their
+    /// group nodes use. Group Input and Group Output are never copied. B adds: comments.
     func clipboard(of items: CanvasSelection) -> NodeClipboard {
-        let ids = items.nodes
-        let nodes = ids.sorted().compactMap { graph.nodes[$0] }
+        let nodes = items.nodes.sorted().compactMap { graph.nodes[$0] }.filter { !GroupNodes.isBoundary($0) }
+        let ids = Set(nodes.map(\.id))
         let links = graph.links.filter { ids.contains($0.from.node) && ids.contains($0.to.node) }
-        return NodeClipboard(nodes: nodes, links: links)
+        return NodeClipboard(nodes: nodes, links: links,
+                             definitions: GroupMerge.definitions(used: nodes, in: document.content))
+    }
+
+    /// Whether `id` is Group Input or Group Output of the level shown.
+    func isBoundary(_ id: NodeID) -> Bool {
+        graph.nodes[id].map(GroupNodes.isBoundary) ?? false
     }
 
-    /// Adds fresh copies of `clipboard` moved by `offset` (stored coordinates) as one undo
-    /// step. Returns the copies, to select, or `nil` if the graph refused. B adds: comments.
+    /// Adds fresh copies of `clipboard` moved by `offset` (stored coordinates) as one undo step, with the group
+    /// definitions it carries that the document lacks or has with other content (`GroupMerge`; the copied group
+    /// nodes follow them). Returns the copies, to select, or `nil` if the graph refused. B adds: comments.
     func insert(_ clipboard: NodeClipboard, offset: Vector2) -> CanvasSelection? {
         guard !clipboard.nodes.isEmpty else { return nil }
+        let merge = GroupMerge.plan(importing: clipboard.definitions, into: document.content)
         var mapping: [NodeID: NodeID] = [:]
         var commands: [GraphCommand] = []
         for original in clipboard.nodes {
-            var copy = original
+            var copy = merge.retargeting(original)
             copy.id = NodeID()
             copy.position = original.position + offset
             mapping[original.id] = copy.id
@@ -98,7 +112,8 @@ extension EditorModel {
         // Copied wires were valid when copied and join only new nodes, so they are restored as they were.
         if !links.isEmpty { commands.append(.restoreLinks(links)) }
         do {
-            try edit(.batch(commands))
+            // The definitions are added to the document, the nodes to the level shown.
+            try document.perform(.batch(merge.additions.map { .addDefinition($0) } + [GraphCommand.batch(commands).at(graphPath)]))
             return CanvasSelection(nodes: Set(mapping.values))
         } catch {
             refuse(error.message, node: nil)
````

**Modify** `Sources/CreatorEditor/NodeClipboard.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/NodeClipboard.swift b/Sources/CreatorEditor/NodeClipboard.swift
index d94a0c2..e38a610 100644
--- a/Sources/CreatorEditor/NodeClipboard.swift
+++ b/Sources/CreatorEditor/NodeClipboard.swift
@@ -1,8 +1,10 @@
 import CreatorGraph
 
-/// Copied nodes and the wires between them. Kept in the editor: the slice has one document
-/// and MetalUI's pasteboard carries text only.
+/// Copied nodes and the wires between them, with the group definitions the copied group nodes use (every one, however
+/// deep), so a paste finds them even after the document lost them, and merges them by content (groups spec §9,
+/// `GroupMerge`). Kept in the editor: the slice has one document and MetalUI's pasteboard carries text only.
 public struct NodeClipboard: Equatable, Sendable {
     public var nodes: [Node]
     public var links: [Link]
+    public var definitions: [GroupID: GroupDefinition] = [:]
 }
````

- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter 'EditorGroupClipboardTests|EditingTests'`

Expected: every test passes (no "recorded an issue").

- [ ] **Step 5: Lint and run the whole suite**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-editor-test.log`.

Expected: exit code 0; `grep -cE 'recorded an issue|failed after' /tmp/groups-editor-test.log` prints 0; `grep -c 'Test run with' /tmp/groups-editor-test.log` prints 11; the counts on those lines add up to **1700** (master + 57). No new compiler warning.

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorEditor/EditorModel+Editing.swift' 'Sources/CreatorEditor/NodeClipboard.swift' 'Tests/CreatorEditorTests/EditorGroupClipboardTests.swift'
git commit -m "feat(groups): the clipboard carries definitions; boundary nodes aren't copied or deleted"
```

---

### Task 7: The look: accent header, doubled border, + sockets and dropping wires on them

`NodeShape` gains `accent` and `isGroup`; a group node is titled with its definition's name and `NodeView` draws it with a doubled border (outer 2 pt, thicker when selected, and a thin inner ring) and a header in `Palette.accent(_:)`; Group Input and Group Output take the definition's accent. They also end with a "+" socket (named `GroupNaming.plusSocket`, untyped), which is an ordinary socket for hit testing. A wire between it and another socket, either way round, exposes a socket (`EditorModel.exposeSocket`); anything else with a "+" is refused with a hint. Node badges read `result(of:)`, i.e. `innerResults` inside a group.

**Files:**
- Modify: `Sources/CreatorEditor/CanvasLayers.swift`
- Create: `Sources/CreatorEditor/EditorModel+Expose.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Pointer.swift`
- Modify: `Sources/CreatorEditor/NodeShape.swift`
- Modify: `Sources/CreatorEditor/NodeView.swift`
- Create: `Sources/CreatorEditor/Palette+Accent.swift`
- Create: `Tests/CreatorEditorTests/ExposeSocketTests.swift`
- Create: `Tests/CreatorEditorTests/GroupLookTests.swift`

**Interfaces:**
- Consumes: T3: `GroupCommands.exposeOutput/exposeInput`; T4: `result(of:)`; T1: `GroupNaming.plusSocket`.
- Produces:
  - `NodeShape.accent: AccentRole?`, `NodeShape.isGroup`; `NodeShape.init(title:category:inputs:outputs:isMissing:accent:isGroup:)`.
  - `Palette.accent(_ role: AccentRole) -> HexColor` (shared with comments, sub-project B).
  - `EditorModel.exposeHint`, `isPlus(_:)`, `exposeSocket(_:_:)` (internal).

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorEditorTests/ExposeSocketTests.swift`:

````swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Dropping a wire on Group Output's "+" and dragging from Group Input's "+" expose sockets, one undo step each
/// (groups spec §6).
@MainActor
struct ExposeSocketTests {
    /// The level inside the group at zoom 1, so sockets are a full row apart and a drop lands on the socket aimed at.
    func inside() throws -> (GroupedEditor, EditorModel, input: Node, output: Node) {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.transform = CanvasTransform()
        return (grouped, editor, try #require(grouped.definition.inputNode), try #require(grouped.definition.outputNode))
    }

    @Test func droppingAnOutputOnGroupOutputsPlusExposesANewOutput() throws {
        let (grouped, editor, _, output) = try inside()
        let from = editor.screenPoint(of: grouped.rectangle.id, "profile", input: false)
        editor.drag(from, editor.screenPoint(of: output.id, "+", input: true))
        let definition = try #require(grouped.current)
        #expect(definition.outputs.map(\.name) == ["solid", "profile"])
        #expect(definition.outputs.last?.type == .profile)
        #expect(definition.graph.links.contains(wire(grouped.rectangle, "profile", output, "profile")))
        let node = try #require(editor.rootGraph.nodes[grouped.group])
        #expect(editor.registry.outputs(for: node).map(\.name) == ["solid", "profile"], "the group node has it too")
        editor.perform(.undo)
        #expect(grouped.current == grouped.definition, "one undo step")
    }

    @Test func draggingFromGroupInputsPlusOntoAnInputExposesANewInput() throws {
        let (grouped, editor, input, _) = try inside()
        let from = editor.screenPoint(of: input.id, "+", input: false)
        editor.drag(from, editor.screenPoint(of: grouped.extrude.id, "distance", input: true))
        let definition = try #require(grouped.current)
        #expect(definition.inputs.map(\.name) == ["width", "distance"])
        #expect(definition.graph.links.contains(wire(input, "distance", grouped.extrude, "distance")))
        #expect(definition.inputs.last?.defaultValue == .number(10), "it keeps the target's default")
        editor.perform(.undo)
        #expect(grouped.current == grouped.definition)
    }

    @Test func theWireCanBeDraggedEitherWayRound() throws {
        let (grouped, editor, input, output) = try inside()
        editor.drag(editor.screenPoint(of: output.id, "+", input: true),
                    editor.screenPoint(of: grouped.rectangle.id, "profile", input: false))
        editor.drag(editor.screenPoint(of: grouped.extrude.id, "distance", input: true),
                    editor.screenPoint(of: input.id, "+", input: false))
        #expect(grouped.current?.outputs.map(\.name) == ["solid", "profile"])
        #expect(grouped.current?.inputs.map(\.name) == ["width", "distance"])
    }

    @Test func aDropThatMakesNoSenseIsRefusedAndChangesNothing() throws {
        let (grouped, editor, input, output) = try inside()
        // An output onto Group Input's + (both are outputs), and an input onto Group Output's + (both are inputs).
        editor.drag(editor.screenPoint(of: grouped.rectangle.id, "profile", input: false),
                    editor.screenPoint(of: input.id, "+", input: false))
        #expect(editor.refusal?.message == EditorModel.exposeHint)
        editor.clearRefusal()
        editor.drag(editor.screenPoint(of: grouped.extrude.id, "distance", input: true),
                    editor.screenPoint(of: output.id, "+", input: true))
        #expect(editor.refusal?.message == EditorModel.exposeHint)
        editor.clearRefusal()
        editor.drag(editor.screenPoint(of: input.id, "+", input: false), editor.screenPoint(of: output.id, "+", input: true))
        #expect(editor.refusal?.message == EditorModel.exposeHint, "plus to plus")
        #expect(grouped.current == grouped.definition)
    }

    @Test func aNewSocketGetsAUniqueNameAndTheDropIsRepeatable() throws {
        let (grouped, editor, _, output) = try inside()
        let from = editor.screenPoint(of: grouped.rectangle.id, "profile", input: false)
        editor.drag(from, editor.screenPoint(of: output.id, "+", input: true))
        editor.drag(from, editor.screenPoint(of: output.id, "+", input: true))
        #expect(grouped.current?.outputs.map(\.name) == ["solid", "profile", "profile2"])
    }
}
````

**Create** `Tests/CreatorEditorTests/GroupLookTests.swift`:

````swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorStyle
import MetalUI
import Testing
@testable import CreatorEditor

/// How group nodes and the boundary nodes look (groups spec §6): the definition's name and accent, a doubled border,
/// and the "+" socket.
@MainActor
struct GroupLookTests {
    @Test func aGroupNodeIsTitledAfterItsDefinitionAndCarriesItsAccent() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let node = try #require(editor.graph.nodes[grouped.group])
        let shape = editor.shape(of: node)
        #expect(shape.title == "Group" && shape.isGroup && shape.accent == .purple)
        try editor.document.perform(GroupCommands.rename(grouped.definition.id, to: "Rib", in: editor.document.content))
        try editor.document.perform(GroupCommands.setAccent(grouped.definition.id, .green, in: editor.document.content))
        let renamed = editor.shape(of: try #require(editor.graph.nodes[grouped.group]))
        #expect(renamed.title == "Rib" && renamed.accent == .green)
        var node2 = try #require(editor.graph.nodes[grouped.group])
        node2.name = "Something else"
        #expect(editor.shape(of: node2).title == "Rib", "the header is the definition's name")
    }

    @Test func otherNodesAreNotGroupsAndHaveNoAccent() throws {
        let grouped = try GroupedEditor()
        let shape = grouped.editor.shape(of: try #require(grouped.editor.graph.nodes[grouped.number.id]))
        #expect(!shape.isGroup && shape.accent == nil)
    }

    @Test func groupInputAndOutputEndWithAPlusSocket() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let input = editor.shape(of: try #require(grouped.definition.inputNode))
        let output = editor.shape(of: try #require(grouped.definition.outputNode))
        #expect(input.outputs.map(\.name) == ["width", "+"] && input.inputs.isEmpty)
        #expect(output.inputs.map(\.name) == ["solid", "+"] && output.outputs.isEmpty)
        #expect(input.outputs.last?.type == nil && output.inputs.last?.type == nil)
        #expect(input.accent == .purple && !input.isGroup && input.title == "Group Input")
        #expect(NodeLayout.size(output).y > NodeLayout.size(NodeShape(title: "x", category: .value, inputs: [output.inputs[0]],
                                                                     outputs: [])).y, "the + takes a row")
        let rows = NodeRowModel.rows(for: try #require(grouped.definition.outputNode), shape: output, graph: editor.graph,
                                     registry: editor.registry)
        #expect(rows.map(\.label) == ["Solid", "+"])
    }

    @Test func eachAccentRoleIsItsOwnColourInEveryTheme() {
        for theme in [ColorTheme.dracula, .alucard, .nord] {
            let palette = Palette(theme)
            #expect(Set(AccentRole.allCases.map { palette.accent($0) }).count == AccentRole.allCases.count, "\(theme.name)")
        }
        #expect(Palette.dracula.accent(.purple) != Palette(.alucard).accent(.purple), "it follows the theme")
    }

    func ringCount(_ scene: Scene) -> Int {
        scene.rects.filter { $0.borderColor.a > 0 && $0.borderWidths.top > 0 }.count
    }

    @Test func aGroupNodeDrawsADoubledBorderInItsAccent() {
        func draw(isGroup: Bool, accent: AccentRole?) -> Scene {
            let shape = NodeShape(title: "Rib", category: .feature, inputs: [], outputs: [], accent: accent, isGroup: isGroup)
            return renderHeadless {
                NodeView(shape: shape, rows: [], origin: Vector2(100, 100), flow: .horizontal, isSelected: false, state: nil,
                         shake: 0)
            }
        }
        let plain = draw(isGroup: false, accent: nil), group = draw(isGroup: true, accent: .purple)
        #expect(ringCount(group) == ringCount(plain) + 1, "the inner ring")
        // The header is the 24-point strip (48 pixels at the frame's scale of 2) filled in the accent.
        func hue(_ accent: AccentRole) -> Float? {
            draw(isGroup: true, accent: accent).rects
                .first { $0.bounds.size.height == Float(NodeLayout.headerHeight * 2) }?.background.h
        }
        #expect(hue(.purple) != nil && hue(.purple) != hue(.green), "the header takes the accent")
    }

    @Test func theCanvasTitlesAGroupNodeAfterItsDefinitionAndFollowsTheLevel() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let input = GraphPanelInput(model: editor)
        func glyphs() -> Int { renderHeadless { GraphPanel(model: editor, input: input) }.glyphs.count }
        let top = glyphs()
        try editor.document.perform(GroupCommands.rename(grouped.definition.id, to: "Hole pattern for ribs",
                                                         in: editor.document.content))
        let renamed = glyphs()
        #expect(renamed > top, "the group node's header reads the definition's name")
        editor.enterGroup(grouped.group)
        #expect(glyphs() != renamed, "the canvas draws the inside, not the top level")
    }
}
````

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep 'error:'`

Expected: the build fails: `NodeShape` has no `isGroup`/`accent`, no `Palette.accent`, no `EditorModel.exposeHint`.

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorEditor/CanvasLayers.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/CanvasLayers.swift b/Sources/CreatorEditor/CanvasLayers.swift
index 2c777ee..df01514 100644
--- a/Sources/CreatorEditor/CanvasLayers.swift
+++ b/Sources/CreatorEditor/CanvasLayers.swift
@@ -27,7 +27,7 @@ struct CanvasLayers: Component {
                              ? NodeRowModel.rows(for: node, shape: shape, graph: model.graph, registry: model.registry) : [],
                          origin: model.displayOrigin(of: node), flow: flow,
                          isSelected: model.selection.contains(node.id),
-                         state: model.document.results[node.id]?.state,
+                         state: model.result(of: node.id)?.state,
                          shake: model.isShaking && model.refusal?.node == node.id ? 6 : 0)
             }
             ForEach(Self.ghosts(model), id: \.id.rawValue) { node in
````

**Create** `Sources/CreatorEditor/EditorModel+Expose.swift`:

````swift
import CreatorGraph
import CreatorKernel

/// The "+" socket of Group Input and Group Output (groups spec §6): dropping a wire on it exposes a new socket.
extension EditorModel {
    static let exposeHint = "Drop a wire from an output on Group Output's +, or drag from Group Input's + onto an input."

    /// Whether `socket` is the "+" of Group Input or Group Output.
    func isPlus(_ socket: SocketRef) -> Bool {
        socket.endpoint.socket == GroupNaming.plusSocket
    }

    /// A wire dragged between two sockets, one of them a "+" (either end can be the one dragged from). An output
    /// dropped on Group Output's "+" exposes a new output, wired from it; Group Input's "+" dragged onto an input
    /// exposes a new input, wired to it. Each is one undo step (`GroupCommands.exposeOutput`, `exposeInput`); anything
    /// else is refused with a hint.
    func exposeSocket(_ first: SocketRef, _ second: SocketRef) {
        let (plus, other) = isPlus(first) ? (first, second) : (second, first)
        guard !isPlus(other), let boundary = graph.nodes[plus.endpoint.node],
              let definition = boundary.inputValues[NodeSetting.group]?.groupID else {
            refuse(Self.exposeHint, node: plus.endpoint.node)
            return
        }
        do {
            switch (boundary.typeID, plus.isInput, other.isInput) {
            case (GroupNodes.outputTypeID, true, false):
                try document.perform(GroupCommands.exposeOutput(from: other.endpoint, on: boundary.id, in: definition,
                                                                of: document.content, registry: registry))
            case (GroupNodes.inputTypeID, false, true):
                try document.perform(GroupCommands.exposeInput(to: other.endpoint, from: boundary.id, in: definition,
                                                               of: document.content, registry: registry))
            default:
                refuse(Self.exposeHint, node: plus.endpoint.node)
            }
        } catch {
            refuse(error.message, node: plus.endpoint.node)
        }
    }
}
````

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/EditorModel+Pointer.swift b/Sources/CreatorEditor/EditorModel+Pointer.swift
index f82966c..bcc526a 100644
--- a/Sources/CreatorEditor/EditorModel+Pointer.swift
+++ b/Sources/CreatorEditor/EditorModel+Pointer.swift
@@ -164,6 +164,10 @@ extension EditorModel {
             }
             return
         }
+        if isPlus(wire.from) || isPlus(target) {
+            exposeSocket(wire.from, target)
+            return
+        }
         guard target.isInput != wire.from.isInput else {
             refuse("Connect an output to an input.", node: target.endpoint.node)
             return
````

**Modify** `Sources/CreatorEditor/NodeShape.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/NodeShape.swift b/Sources/CreatorEditor/NodeShape.swift
index 6c57488..d24dd43 100644
--- a/Sources/CreatorEditor/NodeShape.swift
+++ b/Sources/CreatorEditor/NodeShape.swift
@@ -18,20 +18,35 @@ public struct NodeShape: Equatable, Sendable {
     public var inputs: [Socket]
     public var outputs: [Socket]
     public var isMissing: Bool
+    /// A group node, Group Input or Group Output: the accent of its definition, which colours its header.
+    public var accent: AccentRole?
+    /// A group node: drawn with a doubled border (groups spec §6).
+    public var isGroup: Bool
 
-    public init(title: String, category: NodeCategory, inputs: [Socket], outputs: [Socket], isMissing: Bool = false) {
+    public init(title: String, category: NodeCategory, inputs: [Socket], outputs: [Socket], isMissing: Bool = false,
+                accent: AccentRole? = nil, isGroup: Bool = false) {
         self.title = title
         self.category = category
         self.inputs = inputs
         self.outputs = outputs
         self.isMissing = isMissing
+        self.accent = accent
+        self.isGroup = isGroup
     }
 
     public init(_ node: Node, in graph: Graph, registry: NodeRegistry) {
         if let definition = registry[node.typeID] {
-            self.init(title: node.name, category: definition.category,
-                      inputs: registry.inputs(for: node).map { Socket(name: $0.name, type: $0.type) },
-                      outputs: registry.outputs(for: node).map { Socket(name: $0.name, type: $0.type) })
+            var inputs = registry.inputs(for: node).map { Socket(name: $0.name, type: $0.type) }
+            var outputs = registry.outputs(for: node).map { Socket(name: $0.name, type: $0.type) }
+            // Group Output ends with a "+" input to drop a wire on, Group Input with a "+" output to drag from
+            // (groups spec §6): exposing a new socket.
+            let plus = Socket(name: GroupNaming.plusSocket, type: nil)
+            if node.typeID == GroupNodes.outputTypeID { inputs.append(plus) }
+            if node.typeID == GroupNodes.inputTypeID { outputs.append(plus) }
+            let group = GroupNodes.typeIDs.contains(node.typeID) ? registry.group(of: node) : nil
+            let isGroup = node.typeID == GroupNodes.groupTypeID
+            self.init(title: isGroup ? group?.name ?? node.name : node.name, category: definition.category,
+                      inputs: inputs, outputs: outputs, accent: group?.accent, isGroup: isGroup)
         } else {
             let inputs = Set(graph.links.filter { $0.to.node == node.id }.map(\.to.socket)).sorted()
             let outputs = Set(graph.links.filter { $0.from.node == node.id }.map(\.from.socket)).sorted()
````

**Modify** `Sources/CreatorEditor/NodeView.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/NodeView.swift b/Sources/CreatorEditor/NodeView.swift
index c1b5108..dddb45b 100644
--- a/Sources/CreatorEditor/NodeView.swift
+++ b/Sources/CreatorEditor/NodeView.swift
@@ -22,7 +22,7 @@ struct NodeView: Component {
     var content: some ElementGroup {
         let size = NodeLayout.size(shape)
         let palette = Palette(themes)
-        let accent = palette.header(for: shape.category)
+        let accent = shape.accent.map(palette.accent) ?? palette.header(for: shape.category)
         let corner = RoundedRectangle(cornerRadius: Pixels(6))
         return VStack(alignment: .leading, spacing: Pixels(0)) {
             NodeHeaderView(title: shape.isMissing ? "Missing: \(shape.title)" : shape.title, accent: accent, state: state)
@@ -38,8 +38,15 @@ struct NodeView: Component {
         .background(palette.nodeBody.color, in: corner)
         .clipShape(corner)
         .overlay {
-            corner.strokeBorder(isSelected ? accent.color : palette.hairline.color,
-                                lineWidth: Pixels(isSelected ? 2 : 1))
+            // A group node's border is doubled, both rings in its accent: an outer one and a thin inner one.
+            corner.strokeBorder(shape.isGroup || isSelected ? accent.color : palette.hairline.color,
+                                lineWidth: Pixels(shape.isGroup ? (isSelected ? 3 : 2) : (isSelected ? 2 : 1)))
+        }
+        .overlay {
+            if shape.isGroup {
+                RoundedRectangle(cornerRadius: Pixels(3)).strokeBorder(accent.color, lineWidth: Pixels(1))
+                    .padding(Edges(all: Pixels(4)))
+            }
         }
         .overlay(alignment: .topLeading) {
             // A Component is legacy content; inside a ZStack it is adopted, so the result stays
````

**Create** `Sources/CreatorEditor/Palette+Accent.swift`:

````swift
import CreatorGraph
import CreatorStyle

extension Palette {
    /// The colour of an accent role (groups spec §7): the theme's role it stands for, so it follows theme changes.
    /// Group definitions use it for their header and doubled border (comments, sub-project B, for their fill).
    public func accent(_ role: AccentRole) -> HexColor {
        switch role {
        case .cyan: theme.colors.outputHeader
        case .green: theme.colors.profileHeader
        case .orange: theme.colors.featureHeader
        case .pink: theme.colors.selectionHeader
        case .purple: theme.colors.solidHeader
        case .yellow: theme.colors.warning
        case .muted: theme.colors.valueHeader
        }
    }
}
````

- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter 'GroupLookTests|ExposeSocketTests'`

Expected: every test passes (no "recorded an issue").

- [ ] **Step 5: Lint and run the whole suite**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-editor-test.log`.

Expected: exit code 0; `grep -cE 'recorded an issue|failed after' /tmp/groups-editor-test.log` prints 0; `grep -c 'Test run with' /tmp/groups-editor-test.log` prints 11; the counts on those lines add up to **1711** (master + 68). No new compiler warning.

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorEditor/CanvasLayers.swift' 'Sources/CreatorEditor/EditorModel+Expose.swift' 'Sources/CreatorEditor/EditorModel+Pointer.swift' 'Sources/CreatorEditor/NodeShape.swift' 'Sources/CreatorEditor/NodeView.swift' 'Sources/CreatorEditor/Palette+Accent.swift' 'Tests/CreatorEditorTests/ExposeSocketTests.swift' 'Tests/CreatorEditorTests/GroupLookTests.swift'
git commit -m "feat(groups): group look, + sockets and exposing by wiring"
```

---

### Task 8: Breadcrumbs in the panel header

`BreadcrumbBar` replaces the header's "Graph" text: every level but the one shown is a plain button that goes back out to it, the level shown is text, with "›" between. On the top level it is just "Graph".

**Files:**
- Create: `Sources/CreatorEditor/BreadcrumbBar.swift`
- Modify: `Sources/CreatorEditor/GraphPanelHeader.swift`
- Create: `Tests/CreatorEditorTests/BreadcrumbRenderTests.swift`

**Interfaces:**
- Consumes: T4: `EditorModel.breadcrumbs`, `goToLevel(_:)`.
- Produces:
  - `BreadcrumbBar` (internal MetalUI `Component`), used by `GraphPanelHeader`.

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorEditorTests/BreadcrumbRenderTests.swift`:

````swift
import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorEditor

/// The header's breadcrumbs draw one label per level (groups spec §6).
@MainActor
struct BreadcrumbRenderTests {
    @Test func theHeaderGrowsALabelAndASeparatorPerLevelEntered() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let top = renderHeadless { GraphPanelHeader(model: editor) }.glyphs.count
        editor.enterGroup(grouped.group)
        let inside = renderHeadless { GraphPanelHeader(model: editor) }.glyphs.count
        #expect(inside > top, "Group and › join Graph")
        editor.exitGroup()
        #expect(renderHeadless { GraphPanelHeader(model: editor) }.glyphs.count == top)
    }

    @Test func nestedLevelsAllShow() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let oneDeep = renderHeadless { GraphPanelHeader(model: editor) }.glyphs.count
        editor.selection = [grouped.rectangle.id]
        editor.groupSelection()
        editor.enterGroup(try #require(editor.selection.first))
        #expect(renderHeadless { GraphPanelHeader(model: editor) }.glyphs.count > oneDeep)
        #expect(editor.breadcrumbs.map(\.title) == ["Graph", "Group", "Group 2"])
    }
}
````

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep 'error:'`

Expected: the test target builds, and `swift test --filter BreadcrumbRenderTests` records 2 issues (the header is the same inside and out). Run that instead of the build.

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorEditor/BreadcrumbBar.swift`:

````swift
import CreatorStyle
import MetalUI

/// The graph panel's title as breadcrumbs, "Graph › Rib › Hole pattern" (groups spec §6): each level but the one shown
/// is a button that goes back out to it (`EditorModel.goToLevel(_:)`), and the level shown is plain text. On the top
/// level it is just "Graph", as the title always was.
struct BreadcrumbBar: Component {
    let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        let crumbs = model.breadcrumbs
        return HStack(spacing: Pixels(4)) {
            ForEach(crumbs, id: \.depth) { crumb in
                if crumb.depth == crumbs.count - 1 {
                    Text(crumb.title).font(.headline).foregroundStyle(palette.primaryText.color)
                } else {
                    Button(crumb.title) { model.goToLevel(crumb.depth) }
                        .buttonStyle(.plain)
                        .help("Back to \(crumb.title) (⌘↑)")
                        .foregroundStyle(palette.secondaryText.color)
                    Text("›").font(.headline).foregroundStyle(palette.secondaryText.color)
                }
            }
        }
    }
}
````

**Modify** `Sources/CreatorEditor/GraphPanelHeader.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/GraphPanelHeader.swift b/Sources/CreatorEditor/GraphPanelHeader.swift
index 0e1ad25..d3819bc 100644
--- a/Sources/CreatorEditor/GraphPanelHeader.swift
+++ b/Sources/CreatorEditor/GraphPanelHeader.swift
@@ -2,8 +2,8 @@ import CreatorGraph
 import CreatorStyle
 import MetalUI
 
-/// The graph panel's header: the title, Add (opens the palette), Library (shows or hides the node
-/// library), zoom buttons (beside pinch and ⌘-scroll on the canvas, and the +/− keys) and the dock
+/// The graph panel's header: the title as breadcrumbs (`BreadcrumbBar`), Add (opens the palette), Library (shows or
+/// hides the node library), zoom buttons (beside pinch and ⌘-scroll on the canvas, and the +/− keys) and the dock
 /// buttons (Left, Bottom, Hide).
 struct GraphPanelHeader: Component {
     let model: EditorModel
@@ -11,7 +11,7 @@ struct GraphPanelHeader: Component {
 
     var content: some ElementGroup {
         HStack(spacing: Pixels(6)) {
-            Text("Graph").font(.headline).foregroundStyle(Palette(themes).primaryText.color)
+            BreadcrumbBar(model: model)
             Spacer()
             Button("Add") { model.openPalette() }
                 .help("Add a node (Space)")
````

- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter 'BreadcrumbRenderTests|GraphPanelRenderTests'`

Expected: every test passes (no "recorded an issue").

- [ ] **Step 5: Lint and run the whole suite**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-editor-test.log`.

Expected: exit code 0; `grep -cE 'recorded an issue|failed after' /tmp/groups-editor-test.log` prints 0; `grep -c 'Test run with' /tmp/groups-editor-test.log` prints 11; the counts on those lines add up to **1713** (master + 70). No new compiler warning.

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorEditor/BreadcrumbBar.swift' 'Sources/CreatorEditor/GraphPanelHeader.swift' 'Tests/CreatorEditorTests/BreadcrumbRenderTests.swift'
git commit -m "feat(groups): breadcrumbs in the graph panel header"
```

---

### Task 9: The inspector for a group node and for Group Input and Output

`GroupPanel` (name, accent, uses, and for Group Input/Output the socket list) is `EditorModel.groupPanel`, drawn by `GroupPanelView` above the node's own sections. Edit Group, Make Unique and Ungroup are the group node's inspector buttons (T1, T5). The editing methods wrap C1's `GroupCommands` as one undo step each and show a refusal's message. `TextEntry` is `NumberEntry`'s twin for names, built on a text variant of `PendingEntry`, so a typed name commits when the user clicks away or the selection changes.

**Files:**
- Create: `Sources/CreatorEditor/EditorModel+GroupInspector.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Inspector.swift`
- Create: `Sources/CreatorEditor/GroupPanel.swift`
- Create: `Sources/CreatorEditor/GroupPanelView.swift`
- Create: `Sources/CreatorEditor/GroupSocketRowView.swift`
- Modify: `Sources/CreatorEditor/InspectorPage.swift`
- Modify: `Sources/CreatorEditor/InspectorPanel.swift`
- Modify: `Sources/CreatorEditor/PendingEntry.swift`
- Create: `Sources/CreatorEditor/TextEntry.swift`
- Create: `Tests/CreatorEditorTests/EditorGroupInspectorTests.swift`

**Interfaces:**
- Consumes: C1: `GroupCommands.rename/setAccent/renameSocket/moveSocket/removeSocket/deleteDefinition`, `GroupDependencies.instances`; T4: `graph`; T5: `press`.
- Produces:
  - `GroupPanel` (`definition`, `name`, `accent`, `uses`, `usesText`, `side`, `sockets: [SocketRow]`), `EditorModel.groupPanel`, `InspectorPage.group`.
  - `EditorModel.renameGroup(_:to:)`, `setGroupAccent(_:to:)`, `renameGroupSocket(_:side:from:to:)`, `moveGroupSocket(_:side:named:by:)`, `removeGroupSocket(_:side:named:)`, `deleteGroup(_:)`.
  - `PendingEntry.init(owner:text:commitText:)`; `TextEntry`, `GroupPanelView`, `GroupSocketRowView` (internal).

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorEditorTests/EditorGroupInspectorTests.swift`:

````swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// The inspector for a group node and for Group Input and Group Output (groups spec §6).
@MainActor
struct EditorGroupInspectorTests {
    @Test func aGroupNodeShowsItsDefinitionAndHowManyTimesItIsUsed() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        let panel = try #require(editor.inspectorPage.group)
        #expect(panel.name == "Group" && panel.accent == .purple && panel.definition == grouped.definition.id)
        #expect(panel.side == nil && panel.sockets.isEmpty)
        #expect(panel.usesText == "Used 1 time")
        editor.perform(.duplicate)
        #expect(try #require(editor.groupPanel).usesText == "Used 2 times")
        editor.selection = [grouped.number.id]
        #expect(editor.inspectorPage.group == nil, "a plain node has no group part")
        editor.selection = [grouped.group, grouped.number.id]
        #expect(editor.groupPanel == nil, "nor does a selection of several")
    }

    @Test func groupInputAndOutputListTheSocketsOfTheirSide() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let input = try #require(grouped.definition.inputNode), output = try #require(grouped.definition.outputNode)
        editor.selection = [input.id]
        let inputs = try #require(editor.groupPanel)
        #expect(inputs.side == .input && inputs.sockets.map(\.name) == ["width"] && inputs.sockets.first?.type == .number)
        #expect(inputs.sockets.first?.canMoveUp == false && inputs.sockets.first?.canMoveDown == false)
        editor.selection = [output.id]
        let outputs = try #require(editor.groupPanel)
        #expect(outputs.side == .output && outputs.sockets.map(\.name) == ["solid"])
    }

    @Test func usesCountGroupNodesOnEveryLevel() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.selection = [grouped.rectangle.id]
        editor.groupSelection()
        #expect(try #require(editor.groupPanel).uses == 1)
        editor.perform(.duplicate)
        #expect(try #require(editor.groupPanel).uses == 2, "two instances of the inner group, both inside the outer one")
        editor.exitGroup()
        editor.selection = [grouped.group]
        #expect(try #require(editor.groupPanel).uses == 1, "the outer group is placed once, on the top level")
    }

    @Test func renamingTheDefinitionRenamesItsGroupNodesAndRefusesAnEmptyOrTakenName() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let id = grouped.definition.id
        editor.renameGroup(id, to: "  Rib ")
        #expect(editor.document.definitions[id]?.name == "Rib")
        #expect(editor.shape(of: try #require(editor.graph.nodes[grouped.group])).title == "Rib")
        editor.renameGroup(id, to: "   ")
        #expect(editor.refusal?.message == "A group needs a name.")
        editor.selection = [grouped.group]
        editor.perform(.duplicate)
        editor.press(.makeUnique, on: try #require(editor.selection.first))
        let other = try #require(editor.document.definitions.values.first { $0.id != id })
        editor.renameGroup(other.id, to: "Rib")
        #expect(editor.refusal?.message == "A group named “Rib” already exists.")
        editor.renameGroup(id, to: "Rib")
        #expect(editor.document.definitions[id]?.name == "Rib", "the same name again does nothing")
    }

    @Test func theAccentChangesAsOneUndoStep() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.setGroupAccent(grouped.definition.id, to: .orange)
        #expect(grouped.current?.accent == .orange)
        editor.setGroupAccent(grouped.definition.id, to: .orange)
        editor.perform(.undo)
        #expect(grouped.current?.accent == .purple, "the repeat recorded nothing")
    }

    @Test func renamingASocketMovesItsWiresInsideAndOnTheGroupNode() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.renameGroupSocket(grouped.definition.id, side: .input, from: "width", to: "w")
        #expect(grouped.current?.inputs.map(\.name) == ["w"])
        #expect(editor.graph.links.contains(Link(from: Endpoint(node: grouped.number.id, socket: "value"),
                                                 to: Endpoint(node: grouped.group, socket: "w"))))
        let input = try #require(grouped.definition.inputNode)
        #expect(grouped.current?.graph.links.contains(wire(input, "w", grouped.rectangle, "width")) == true)
        editor.perform(.undo)
        #expect(grouped.current?.inputs.map(\.name) == ["width"], "one undo step")
        editor.renameGroupSocket(grouped.definition.id, side: .input, from: "width", to: "+")
        #expect(editor.refusal?.message == "“+” is reserved. Choose another name.")
    }

    @Test func socketsMoveUpAndDownTheList() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.transform = CanvasTransform()
        let output = try #require(grouped.definition.outputNode)
        editor.drag(editor.screenPoint(of: grouped.rectangle.id, "profile", input: false),
                    editor.screenPoint(of: output.id, "+", input: true))
        editor.selection = [output.id]
        #expect(editor.groupPanel?.sockets.map(\.name) == ["solid", "profile"])
        #expect(editor.groupPanel?.sockets.map(\.canMoveUp) == [false, true])
        editor.moveGroupSocket(grouped.definition.id, side: .output, named: "profile", by: -1)
        #expect(editor.groupPanel?.sockets.map(\.name) == ["profile", "solid"])
        editor.moveGroupSocket(grouped.definition.id, side: .output, named: "profile", by: -1)
        #expect(editor.groupPanel?.sockets.map(\.name) == ["profile", "solid"], "already first: nothing moves")
        editor.perform(.undo)
        #expect(editor.groupPanel?.sockets.map(\.name) == ["solid", "profile"])
    }

    @Test func aWiredSocketCantBeRemovedAndTheRefusalNamesTheInstance() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let before = editor.document.content
        editor.selection = [grouped.group]
        editor.removeGroupSocket(grouped.definition.id, side: .output, named: "solid")
        #expect(editor.refusal?.message == "“solid” is wired on “Group”. Unwire it first.")
        editor.removeGroupSocket(grouped.definition.id, side: .input, named: "width")
        #expect(editor.refusal?.message == "“width” is wired on “Group”. Unwire it first.")
        #expect(editor.document.content == before)
    }

    @Test func anUnwiredSocketIsRemovedWithItsWiresInsideInOneStep() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.transform = CanvasTransform()
        let output = try #require(grouped.definition.outputNode)
        editor.drag(editor.screenPoint(of: grouped.rectangle.id, "profile", input: false),
                    editor.screenPoint(of: output.id, "+", input: true))
        let withProfile = editor.document.content
        editor.removeGroupSocket(grouped.definition.id, side: .output, named: "profile")
        #expect(grouped.current == grouped.definition)
        editor.perform(.undo)
        #expect(editor.document.content == withProfile)
    }

    @Test func anUnusedDefinitionCanBeDeletedAndAUsedOneCant() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.deleteGroup(grouped.definition.id)
        #expect(editor.refusal?.message == "“Group” is still in use. Delete its group nodes first.")
        editor.selection = [grouped.group]
        editor.deleteSelection()
        editor.deleteGroup(grouped.definition.id)
        #expect(editor.document.definitions.isEmpty)
        editor.perform(.undo)
        #expect(editor.document.definitions.count == 1, "the delete is one undo step")
    }

    @Test func aTypedNameIsCommittedWhenTheSelectionChanges() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let id = grouped.definition.id
        editor.selection = [grouped.group]
        editor.notePendingEntry(PendingEntry(text: "Rib") { editor.renameGroup(id, to: $0) })
        editor.selection = [grouped.number.id]
        #expect(grouped.current?.name == "Rib", "clicking away didn't drop it")
    }

    @Test func theInspectorDrawsTheGroupPartAndTheSocketList() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.number.id]
        let plain = renderHeadless { InspectorPanel(model: editor) }.glyphs.count
        editor.selection = [grouped.group]
        #expect(renderHeadless { InspectorPanel(model: editor) }.glyphs.count > plain)
        editor.enterGroup(grouped.group)
        editor.selection = [try #require(grouped.definition.outputNode).id]
        #expect(renderHeadless { InspectorPanel(model: editor) }.glyphs.count > plain, "the group part and the socket list")
    }
}
````

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep 'error:'`

Expected: the build fails: no `groupPanel`, `renameGroup`, `PendingEntry(text:commitText:)`.

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorEditor/EditorModel+GroupInspector.swift`:

````swift
import CreatorGraph
import CreatorKernel

/// The inspector's group editing (groups spec §6): the definition's name and accent, its sockets (rename, reorder,
/// remove) and deleting an unused definition. Each is one `DocumentModel.perform`, so one undo step; a refusal shows
/// its message.
extension EditorModel {
    /// The panel for the one selected group node, Group Input or Group Output; `nil` for anything else.
    public var groupPanel: GroupPanel? {
        guard selection.count == 1, let id = selection.first, let node = graph.nodes[id],
              GroupNodes.typeIDs.contains(node.typeID), let definition = registry.group(of: node) else { return nil }
        let side: GroupSocketSide? = switch node.typeID {
        case GroupNodes.inputTypeID: .input
        case GroupNodes.outputTypeID: .output
        default: nil
        }
        let specs = side == .input ? definition.inputs : side == .output ? definition.outputs : []
        let sockets = specs.enumerated().map { index, spec in
            GroupPanel.SocketRow(name: spec.name, type: spec.type, canMoveUp: index > 0, canMoveDown: index < specs.count - 1)
        }
        return GroupPanel(definition: definition.id, name: definition.name, accent: definition.accent,
                          uses: GroupDependencies.instances(of: definition.id, in: document.content).count,
                          side: side, sockets: sockets)
    }

    /// Renames definition `id`, and the group nodes still named after it.
    public func renameGroup(_ id: GroupID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed != document.definitions[id]?.name else { return }
        perform { () throws(GraphError) in try GroupCommands.rename(id, to: trimmed, in: document.content) }
    }

    public func setGroupAccent(_ id: GroupID, to accent: AccentRole) {
        guard accent != document.definitions[id]?.accent else { return }
        perform { () throws(GraphError) in try GroupCommands.setAccent(id, accent, in: document.content) }
    }

    /// Renames socket `old` of `side` to `new`, on the definition, its wires inside and every group node of it.
    public func renameGroupSocket(_ id: GroupID, side: GroupSocketSide, from old: SocketName, to new: String) {
        let name = SocketName(new.trimmingCharacters(in: .whitespaces))
        guard name != old else { return }
        perform { () throws(GraphError) in
            try GroupCommands.renameSocket(id, side: side, from: old, to: name, in: document.content)
        }
    }

    /// Moves socket `name` of `side` one place up (`by` -1) or down (+1) the list; wires follow it by name.
    public func moveGroupSocket(_ id: GroupID, side: GroupSocketSide, named name: SocketName, by step: Int) {
        let sockets = side == .input ? document.definitions[id]?.inputs : document.definitions[id]?.outputs
        guard let index = sockets?.firstIndex(where: { $0.name == name }) else { return }
        perform { () throws(GraphError) in
            try GroupCommands.moveSocket(id, side: side, from: index, to: index + step, in: document.content)
        }
    }

    /// Removes socket `name` of `side` and its wires inside. Refused while a group node has it wired, naming that node.
    public func removeGroupSocket(_ id: GroupID, side: GroupSocketSide, named name: SocketName) {
        perform { () throws(GraphError) in
            try GroupCommands.removeSocket(id, side: side, name: name, in: document.content)
        }
    }

    /// Deletes definition `id` from the document. Refused while a group node uses it.
    public func deleteGroup(_ id: GroupID) {
        perform { () throws(GraphError) in try GroupCommands.deleteDefinition(id, in: document.content) }
    }

    private func perform(_ build: () throws(GraphError) -> GraphCommand) {
        do {
            try document.perform(try build())
        } catch {
            refuse(error.message, node: selection.first)
        }
    }
}
````

**Modify** `Sources/CreatorEditor/EditorModel+Inspector.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/EditorModel+Inspector.swift b/Sources/CreatorEditor/EditorModel+Inspector.swift
index 583f400..ec57b71 100644
--- a/Sources/CreatorEditor/EditorModel+Inspector.swift
+++ b/Sources/CreatorEditor/EditorModel+Inspector.swift
@@ -4,8 +4,10 @@ import CreatorKernel
 extension EditorModel {
     /// What the context inspector shows now.
     public var inspectorPage: InspectorPage {
-        InspectorBuilder.page(graph: graphWithDocumentParameters, selection: selection, registry: registry,
-                              results: levelResults)
+        var page = InspectorBuilder.page(graph: graphWithDocumentParameters, selection: selection, registry: registry,
+                                         results: levelResults)
+        page.group = groupPanel
+        return page
     }
 
     /// The graph shown, with the document's parameters: they belong to the top level, and nodes inside a group read
````

**Create** `Sources/CreatorEditor/GroupPanel.swift`:

````swift
import CreatorGraph
import CreatorKernel

/// What the inspector shows about the group definition behind the selected node (groups spec §6): its name, accent
/// and how many group nodes use it; and, when the selection is Group Input or Group Output, the sockets of that side.
public struct GroupPanel: Equatable, Sendable {
    /// One socket of the side shown, with whether it can move up or down the list.
    public struct SocketRow: Equatable, Sendable, Identifiable {
        public var name: SocketName
        public var type: SocketType
        public var canMoveUp: Bool
        public var canMoveDown: Bool

        public var id: String { name.rawValue }
    }

    public var definition: GroupID
    public var name: String
    public var accent: AccentRole
    /// Group nodes of the definition, on every level.
    public var uses: Int
    /// Group Input's side (`.input`) or Group Output's (`.output`) when one of them is selected, else `nil`.
    public var side: GroupSocketSide?
    public var sockets: [SocketRow]

    /// "Used 1 time", "Used 3 times".
    public var usesText: String { "Used \(uses) \(uses == 1 ? "time" : "times")" }
}
````

**Create** `Sources/CreatorEditor/GroupPanelView.swift`:

````swift
import CreatorGraph
import CreatorStyle
import MetalUI

/// The inspector's part for a group node, Group Input or Group Output (groups spec §6): the definition's name and
/// accent and how many times it is used; and, for Group Input or Group Output, the sockets of that side with rename,
/// reorder and remove. Edit Group, Make Unique and Ungroup are the group node's own inspector buttons.
struct GroupPanelView: Component {
    let panel: GroupPanel
    let model: EditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    var content: some ElementGroup {
        let palette = Palette(themes)
        return VStack(alignment: .leading, spacing: Pixels(10)) {
            InspectorSectionView(title: "Definition") {
                LabeledRow(label: "Name") {
                    Spacer()
                    TextEntry(model: model, text: panel.name) { model.renameGroup(panel.definition, to: $0) }
                }
                Picker("Accent", selection: Binding(get: { panel.accent }, set: { model.setGroupAccent(panel.definition, to: $0) })) {
                    ForEach(AccentRole.allCases, id: \.self) { role in
                        Text(role.rawValue.capitalized).tag(role)
                    }
                }
                .pickerStyle(.menu)
                Text(panel.usesText).font(.callout).foregroundStyle(palette.secondaryText.color)
            }
            if let side = panel.side {
                InspectorSectionView(title: side == .input ? "Inputs" : "Outputs") {
                    if panel.sockets.isEmpty {
                        Text("Drop a wire on + to add one").font(.caption).foregroundStyle(palette.secondaryText.color)
                    }
                    ForEach(panel.sockets, id: \.id) { socket in
                        GroupSocketRowView(panel: panel, side: side, socket: socket, model: model)
                    }
                }
            }
        }
    }
}
````

**Create** `Sources/CreatorEditor/GroupSocketRowView.swift`:

````swift
import CreatorGraph
import MetalUI

/// One socket in the inspector's list for Group Input or Group Output: its name (edit to rename), and buttons to move
/// it up or down and to remove it.
struct GroupSocketRowView: Component {
    let panel: GroupPanel
    let side: GroupSocketSide
    let socket: GroupPanel.SocketRow
    let model: EditorModel

    var content: some ElementGroup {
        HStack(spacing: Pixels(4)) {
            TextEntry(model: model, text: socket.name.rawValue, width: 110) {
                model.renameGroupSocket(panel.definition, side: side, from: socket.name, to: $0)
            }
            Spacer()
            Button("↑") { model.moveGroupSocket(panel.definition, side: side, named: socket.name, by: -1) }
                .help("Move up")
                .disabled(!socket.canMoveUp)
            Button("↓") { model.moveGroupSocket(panel.definition, side: side, named: socket.name, by: 1) }
                .help("Move down")
                .disabled(!socket.canMoveDown)
            Button("Remove") { model.removeGroupSocket(panel.definition, side: side, named: socket.name) }
                .help("Remove this socket and its wires inside")
        }
    }
}
````

**Modify** `Sources/CreatorEditor/InspectorPage.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/InspectorPage.swift b/Sources/CreatorEditor/InspectorPage.swift
index 8711597..e2de408 100644
--- a/Sources/CreatorEditor/InspectorPage.swift
+++ b/Sources/CreatorEditor/InspectorPage.swift
@@ -4,4 +4,6 @@ public struct InspectorPage: Equatable, Sendable {
     public var header: InspectorHeader?
     public var sections: [InspectorSectionRows]
     public var parameters: [ParameterRow]
+    /// The definition behind the selected group node, Group Input or Group Output (`EditorModel.groupPanel`).
+    public var group: GroupPanel?
 }
````

**Modify** `Sources/CreatorEditor/InspectorPanel.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/InspectorPanel.swift b/Sources/CreatorEditor/InspectorPanel.swift
index 05c02c9..95ef8ab 100644
--- a/Sources/CreatorEditor/InspectorPanel.swift
+++ b/Sources/CreatorEditor/InspectorPanel.swift
@@ -19,6 +19,9 @@ public struct InspectorPanel: Component {
                 if let header = page.header {
                     InspectorHeaderView(header: header)
                 }
+                if let group = page.group {
+                    GroupPanelView(panel: group, model: model)
+                }
                 ForEach(page.sections, id: \.title) { section in
                     InspectorSectionView(title: section.title) {
                         ForEach(section.rows.indices, id: \.self) { index in
````

**Modify** `Sources/CreatorEditor/PendingEntry.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/PendingEntry.swift b/Sources/CreatorEditor/PendingEntry.swift
index d2b1f6e..16c6f16 100644
--- a/Sources/CreatorEditor/PendingEntry.swift
+++ b/Sources/CreatorEditor/PendingEntry.swift
@@ -11,6 +11,8 @@ public struct PendingEntry {
     public var commit: @MainActor (Double) -> Void
     /// Set for an optional input: emptying the field clears it.
     public var clear: (@MainActor () -> Void)?
+    /// Set for a text field (a group's or a socket's name): it takes the text as it is, and `commit` is unused.
+    public var commitText: (@MainActor (String) -> Void)?
 
     public init(owner: UUID? = nil, text: String, commit: @escaping @MainActor (Double) -> Void, clear: (@MainActor () -> Void)? = nil) {
         self.owner = owner
@@ -19,10 +21,21 @@ public struct PendingEntry {
         self.clear = clear
     }
 
-    /// Commits a readable number, or clears an emptied optional field. An unreadable entry is discarded.
+    /// A text field's entry: `commitText` gets the text, however it reads.
+    public init(owner: UUID? = nil, text: String, commitText: @escaping @MainActor (String) -> Void) {
+        self.owner = owner
+        self.text = text
+        self.commit = { _ in }
+        self.commitText = commitText
+    }
+
+    /// Commits a readable number, or clears an emptied optional field. An unreadable entry is discarded. A text
+    /// field's entry is committed as typed.
     @MainActor
     func apply() {
-        if let clear, text.trimmingCharacters(in: .whitespaces).isEmpty {
+        if let commitText {
+            commitText(text)
+        } else if let clear, text.trimmingCharacters(in: .whitespaces).isEmpty {
             clear()
         } else if let value = ValueText.parse(text) {
             commit(value)
````

**Create** `Sources/CreatorEditor/TextEntry.swift`:

````swift
import Foundation
import MetalUI

/// A text field for a name. As `NumberEntry` does for numbers, it keeps the draft locally and records each keystroke
/// with the model as a `PendingEntry`, committed on Return, when the field loses focus, and when the model commits
/// it (a canvas press, a selection change), so clicking away never drops it. An empty entry is committed too: the
/// command refuses it with a plain message.
struct TextEntry: Component {
    let model: EditorModel
    let text: String
    var placeholder = "Name"
    var width = 120.0
    let commit: @MainActor (String) -> Void
    @State var draft: String?
    @FocusState var isFocused: Bool
    @State var owner = UUID()

    var content: some ElementGroup {
        HStack(spacing: Pixels(0)) {
            TextField(placeholder, text: draft ?? text, onChange: { typed in
                draft = typed
                model.notePendingEntry(PendingEntry(owner: owner, text: typed, commitText: commit))
            })
            .focused($isFocused)
            .onSubmit {
                model.commitPendingEntry()
                draft = nil
            }
        }
        .frame(width: width.px)
        .onChange(of: text) {
            draft = nil
            model.discardPendingEntry(ownedBy: owner)
        }
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused, !focused {
                model.commitPendingEntry()
                draft = nil
            }
        }
    }
}
````

- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter 'EditorGroupInspectorTests'`

Expected: every test passes (no "recorded an issue").

- [ ] **Step 5: Lint and run the whole suite**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-editor-test.log`.

Expected: exit code 0; `grep -cE 'recorded an issue|failed after' /tmp/groups-editor-test.log` prints 0; `grep -c 'Test run with' /tmp/groups-editor-test.log` prints 11; the counts on those lines add up to **1725** (master + 82). No new compiler warning.

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorEditor/EditorModel+GroupInspector.swift' 'Sources/CreatorEditor/EditorModel+Inspector.swift' 'Sources/CreatorEditor/GroupPanel.swift' 'Sources/CreatorEditor/GroupPanelView.swift' 'Sources/CreatorEditor/GroupSocketRowView.swift' 'Sources/CreatorEditor/InspectorPage.swift' 'Sources/CreatorEditor/InspectorPanel.swift' 'Sources/CreatorEditor/PendingEntry.swift' 'Sources/CreatorEditor/TextEntry.swift' 'Tests/CreatorEditorTests/EditorGroupInspectorTests.swift'
git commit -m "feat(groups): the group inspector"
```

---

### Task 10: The library's Groups section

The library lists the document's definitions after the node types, filtered by the same search. A group row is a `PaletteEntry` carrying a key `group:<uuid>` through the library's one gesture in place of a node type's ID, so a click and a drag need no second gesture; `libraryNode(for:at:)` makes the node for either kind. A definition with no instances offers Delete.

**Files:**
- Modify: `Sources/CreatorEditor/EditorModel+Editing.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Library.swift`
- Create: `Sources/CreatorEditor/GroupLibraryEntry.swift`
- Modify: `Sources/CreatorEditor/LibraryItem.swift`
- Modify: `Sources/CreatorEditor/LibraryRow.swift`
- Modify: `Sources/CreatorEditor/LibrarySectionHeader.swift`
- Modify: `Sources/CreatorEditor/NodeLibraryView.swift`
- Modify: `Sources/CreatorEditor/PaletteEntry.swift`
- Modify: `Sources/CreatorEditor/PaletteEntryLabel.swift`
- Create: `Tests/CreatorEditorTests/LibraryGroupsTests.swift`

**Interfaces:**
- Consumes: T9: `deleteGroup`; T4: `add`, `edit`.
- Produces:
  - `GroupLibraryEntry` (`group`, `name`, `accent`, `uses`, `key`, `canDelete`, `paletteEntry`).
  - `EditorModel.libraryGroups`, `libraryItems`, `libraryNode(for:at:)` (internal); `librarySummary(of:)` and `libraryDragEntry` accept a group key.
  - `LibraryItem.group`, `.isGroupsHeader`, `LibraryItem.rows(_:groups:)`; `PaletteEntry.accent`.

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorEditorTests/LibraryGroupsTests.swift`:

````swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Testing
@testable import CreatorEditor

/// The node library's "Groups" section (groups spec §6): the document's definitions, placed by a click or a drag, and
/// deleted when nothing uses them.
@MainActor
struct LibraryGroupsTests {
    func placed(_ editor: EditorModel) -> EditorModel {
        let panel = CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300))
        editor.placement = { PanelPlacement(window: Vector2(1000, 700), panel: panel) }
        return editor
    }

    @Test func theSectionListsTheDocumentsDefinitionsByNameWithHowOftenEachIsUsed() throws {
        let plain = makeEditor([])
        #expect(plain.libraryGroups.isEmpty)
        #expect(!plain.libraryItems.contains { $0.isGroupsHeader }, "no definitions, no section")
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let entry = try #require(editor.libraryGroups.first)
        #expect(editor.libraryGroups.count == 1 && entry.name == "Group" && entry.uses == 1 && !entry.canDelete)
        #expect(entry.accent == .purple && entry.key == "group:" + grouped.definition.id.rawValue.uuidString)
        editor.renameGroup(grouped.definition.id, to: "Rib")
        editor.selection = [grouped.group]
        editor.perform(.duplicate)
        editor.press(.makeUnique, on: try #require(editor.selection.first))
        #expect(editor.libraryGroups.map(\.name) == ["Rib", "Rib 2"])
        #expect(editor.libraryGroups.map(\.uses) == [1, 1], "the copy made unique took one instance with it")
    }

    @Test func theRowsEndWithTheGroupsHeaderThenOneRowPerDefinition() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let items = editor.libraryItems
        let tail = items.suffix(2)
        #expect(tail.first?.isGroupsHeader == true && tail.first?.id == "header.groups")
        #expect(tail.last?.group?.group == grouped.definition.id && tail.last?.id == editor.libraryGroups.first?.key)
        #expect(items.dropLast(2).allSatisfy { $0.group == nil && !$0.isGroupsHeader }, "the node types come first")
    }

    @Test func theLibrarySearchFiltersGroupsToo() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.setLibraryQuery("grou")
        #expect(editor.libraryGroups.count == 1)
        #expect(editor.libraryItems.last?.group != nil)
        editor.setLibraryQuery("zzz")
        #expect(editor.libraryGroups.isEmpty && editor.libraryItems.isEmpty)
    }

    @Test func aClickPlacesAnotherInstanceAsOneStep() throws {
        let grouped = try GroupedEditor()
        let editor = placed(grouped.editor)
        let key = try #require(editor.libraryGroups.first).key
        let start = Vector2(100, 400)
        #expect(editor.endLibraryDrag(key, from: start, at: start))
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        #expect(added.typeID == GroupNodes.groupTypeID && added.id != grouped.group)
        #expect(added.inputValues[NodeSetting.group] == .group(grouped.definition.id))
        #expect(added.name == "Group")
        #expect(editor.document.definitions.count == 1 && editor.libraryGroups.first?.uses == 2)
        editor.document.undo()
        #expect(editor.graph.nodes[added.id] == nil)
    }

    @Test func aDragPlacesItWhereItIsDropped() throws {
        let grouped = try GroupedEditor()
        let editor = placed(grouped.editor)
        let key = try #require(editor.libraryGroups.first).key
        let canvas = try #require(editor.canvasFrameInWindow)
        let start = canvas.origin + Vector2(-100, 40), end = canvas.origin + Vector2(300, 80)
        editor.moveLibraryDrag(key, from: start, to: end)
        let ghost = try #require(editor.libraryDragEntry)
        #expect(ghost.displayName == "Group" && ghost.accent == .purple)
        #expect(editor.endLibraryDrag(key, from: start, at: end))
        let added = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        #expect(editor.transform.toScreen(editor.frame(of: added).origin) == Vector2(300, 80))
    }

    @Test func aDefinitionThatIsGoneOrNotYoursPlacesNothing() throws {
        let grouped = try GroupedEditor()
        let editor = placed(grouped.editor)
        let key = "group:" + UUID().uuidString
        #expect(!editor.addFromLibrary(key) && !editor.dropFromLibrary(key, atScreen: Vector2(50, 50)))
        #expect(editor.libraryDragEntry == nil && editor.librarySummary(of: key) == nil)
        #expect(!editor.addFromLibrary("group:not-a-uuid"))
        #expect(editor.graph.nodes.count == 3)
    }

    @Test func aGroupCantBePlacedInsideItself() throws {
        let grouped = try GroupedEditor()
        let editor = placed(grouped.editor)
        let key = try #require(editor.libraryGroups.first).key
        editor.enterGroup(grouped.group)
        let before = editor.document.content
        #expect(!editor.addFromLibrary(key))
        #expect(editor.refusal?.message == "A group can't contain itself.")
        #expect(editor.document.content == before)
    }

    @Test func aGroupCanBePlacedInsideAnotherOne() throws {
        let grouped = try GroupedEditor()
        let editor = placed(grouped.editor)
        editor.selection = [grouped.group]
        editor.perform(.duplicate)
        editor.press(.makeUnique, on: try #require(editor.selection.first))
        let other = try #require(editor.document.definitions.values.first { $0.id != grouped.definition.id })
        editor.enterGroup(try #require(editor.selection.first))
        #expect(editor.addFromLibrary(GroupLibraryEntry.key(for: grouped.definition.id)))
        #expect(editor.graph.nodes.values.contains { $0.inputValues[NodeSetting.group] == .group(grouped.definition.id) })
        #expect(editor.document.definitions[other.id] != nil)
    }

    @Test func onlyADefinitionNothingUsesOffersDelete() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        #expect(editor.libraryGroups.first?.canDelete == false)
        editor.selection = [grouped.group]
        editor.deleteSelection()
        let entry = try #require(editor.libraryGroups.first)
        #expect(entry.uses == 0 && entry.canDelete)
        editor.deleteGroup(entry.group)
        #expect(editor.libraryGroups.isEmpty)
        editor.perform(.undo)
        #expect(editor.libraryGroups.count == 1)
    }

    @Test func hoverHelpNamesAGroupsInputsThenOutputs() throws {
        let grouped = try GroupedEditor()
        let key = try #require(grouped.editor.libraryGroups.first).key
        #expect(grouped.editor.librarySummary(of: key) == "Group: width → solid")
    }

    @Test func theLibraryDrawsTheGroupsSection() throws {
        let plain = makeEditor([])
        let withoutGroups = renderHeadless { NodeLibraryView(model: plain, input: GraphPanelInput(model: plain)) }.glyphs.count
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let withGroups = renderHeadless { NodeLibraryView(model: editor, input: GraphPanelInput(model: editor)) }.glyphs.count
        #expect(withGroups > withoutGroups, "the Groups header and the row")
        editor.setLibraryQuery("zzzz")
        let noMatch = renderHeadless { NodeLibraryView(model: editor, input: GraphPanelInput(model: editor)) }.glyphs.count
        editor.setLibraryQuery("grou")
        let onlyGroups = renderHeadless { NodeLibraryView(model: editor, input: GraphPanelInput(model: editor)) }.glyphs.count
        #expect(onlyGroups < withGroups && onlyGroups != noMatch, "the search drops the node types and keeps the Groups section")
    }
}
````

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep 'error:'`

Expected: the build fails: no `GroupLibraryEntry`, `libraryGroups`, `libraryItems`.

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorEditor/EditorModel+Editing.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/EditorModel+Editing.swift b/Sources/CreatorEditor/EditorModel+Editing.swift
index 6922417..6a1bc89 100644
--- a/Sources/CreatorEditor/EditorModel+Editing.swift
+++ b/Sources/CreatorEditor/EditorModel+Editing.swift
@@ -58,7 +58,8 @@ extension EditorModel {
     /// or where a library node was dropped) and selects it, as one undo step. Returns whether the graph took it.
     @discardableResult
     public func addNode(_ typeID: String, atScreen screen: Vector2) -> Bool {
-        add(registry.makeNode(typeID, at: flow.stored(transform.toCanvas(screen))))
+        let position = flow.stored(transform.toCanvas(screen))
+        return add(libraryNode(for: typeID, at: position) ?? registry.makeNode(typeID, at: position))
     }
 
     /// Adds `node` (made by `NodeRegistry.makeNode`) and selects it, as one undo step. Returns false, having shown
````

**Modify** `Sources/CreatorEditor/EditorModel+Library.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/EditorModel+Library.swift b/Sources/CreatorEditor/EditorModel+Library.swift
index 633f036..ba9ca2a 100644
--- a/Sources/CreatorEditor/EditorModel+Library.swift
+++ b/Sources/CreatorEditor/EditorModel+Library.swift
@@ -24,9 +24,44 @@ extension EditorModel {
         LibrarySection.grouping(PaletteSearch.entries(in: registry, matching: libraryQuery))
     }
 
-    /// A type's inputs → outputs, for the library's hover help; `nil` for an unregistered type.
+    /// The document's group definitions the library's search matches (the same search as the node types), by name,
+    /// with how often each is used.
+    public var libraryGroups: [GroupLibraryEntry] {
+        let needle = libraryQuery.trimmingCharacters(in: .whitespaces)
+        let content = document.content
+        return content.definitions.values
+            .filter { needle.isEmpty || $0.name.localizedStandardContains(needle) }
+            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
+            .map { GroupLibraryEntry(group: $0.id, name: $0.name, accent: $0.accent,
+                                     uses: GroupDependencies.instances(of: $0.id, in: content).count) }
+    }
+
+    /// The library's rows: the node types by category, then the "Groups" section.
+    public var libraryItems: [LibraryItem] {
+        LibraryItem.rows(librarySections, groups: libraryGroups)
+    }
+
+    /// A type's inputs → outputs, for the library's hover help (a group's too, by its key); `nil` for an
+    /// unregistered type or a definition that is gone.
     public func librarySummary(of typeID: String) -> String? {
-        registry[typeID].map(NodeTypeSummary.text)
+        if let id = GroupLibraryEntry.group(forKey: typeID) {
+            guard let definition = document.definitions[id] else { return nil }
+            let names = { (sockets: [SocketSpec], none: String) in
+                sockets.isEmpty ? none : sockets.map { InspectorLabel.text(for: $0.name).lowercased() }.joined(separator: ", ")
+            }
+            return "\(definition.name): \(names(definition.inputs, "no inputs")) → \(names(definition.outputs, "no outputs"))"
+        }
+        return registry[typeID].map(NodeTypeSummary.text)
+    }
+
+    /// A fresh node for a library key: a node of that type, or an instance of the group definition the key names
+    /// (`GroupLibraryEntry.key`); `nil` for a type that isn't registered or a definition that is gone.
+    func libraryNode(for key: String, at position: Vector2 = .zero) -> Node? {
+        if let id = GroupLibraryEntry.group(forKey: key) {
+            guard document.definitions[id] != nil else { return nil }
+            return registry.makeGroupNode(GroupNodes.groupTypeID, for: id, at: position)
+        }
+        return registry[key] == nil ? nil : registry.makeNode(key, at: position)
     }
 
     /// The visible canvas's size in points, from the host's placement (without one,
@@ -43,8 +78,7 @@ extension EditorModel {
     /// that isn't registered, or when the graph refuses the add).
     @discardableResult
     public func addFromLibrary(_ typeID: String) -> Bool {
-        guard registry[typeID] != nil else { return false }
-        var node = registry.makeNode(typeID)
+        guard var node = libraryNode(for: typeID) else { return false }
         let size = NodeLayout.size(shape(of: node))
         let centred = transform.toCanvas(visibleCanvasCentre) - size * 0.5
         let visible = CanvasRect(corner: transform.toCanvas(.zero), transform.toCanvas(visibleCanvasSize))
@@ -57,7 +91,7 @@ extension EditorModel {
     /// refuses the add.
     @discardableResult
     public func dropFromLibrary(_ typeID: String, atScreen screen: Vector2) -> Bool {
-        guard registry[typeID] != nil, screen.isFinite else { return false }
+        guard libraryNode(for: typeID) != nil, screen.isFinite else { return false }
         return addNode(typeID, atScreen: screen)
     }
 
@@ -82,7 +116,7 @@ extension EditorModel {
         let wasDragging = isLibraryDragging(typeID, from: start)
             || LibraryDrag(typeID: typeID, start: start, location: location).isDragging
         if libraryDrag != nil { libraryDrag = nil }
-        guard registry[typeID] != nil else { return false }
+        guard libraryNode(for: typeID) != nil else { return false }
         guard wasDragging else { return addFromLibrary(typeID) }
         guard let canvas = canvasFrameInWindow, canvas.contains(location) else { return false }
         return dropFromLibrary(typeID, atScreen: location - canvas.origin)
@@ -95,7 +129,13 @@ extension EditorModel {
 
     /// The type the drag ghost shows, while a library type is being dragged.
     public var libraryDragEntry: PaletteEntry? {
-        guard let drag = libraryDrag, let definition = registry[drag.typeID] else { return nil }
+        guard let drag = libraryDrag else { return nil }
+        if let id = GroupLibraryEntry.group(forKey: drag.typeID) {
+            return document.definitions[id].map {
+                GroupLibraryEntry(group: id, name: $0.name, accent: $0.accent, uses: 0).paletteEntry
+            }
+        }
+        guard let definition = registry[drag.typeID] else { return nil }
         return PaletteEntry(typeID: definition.typeID, displayName: definition.displayName, category: definition.category)
     }
 
````

**Create** `Sources/CreatorEditor/GroupLibraryEntry.swift`:

````swift
import CreatorGraph
import Foundation

/// One group definition in the node library's "Groups" section (groups spec §6): a click or drag places another
/// instance of it, and one with no instances offers Delete.
public struct GroupLibraryEntry: Equatable, Sendable, Identifiable {
    public var group: GroupID
    public var name: String
    public var accent: AccentRole
    /// Group nodes of the definition, on every level.
    public var uses: Int

    public var id: String { key }

    /// The key the library's gestures carry for this entry in place of a node type's ID (`LibraryDrag.typeID`).
    public var key: String { Self.key(for: group) }

    /// A definition with no instance can be deleted from the library.
    public var canDelete: Bool { uses == 0 }

    /// The prefix of a group's library key: no node type's ID starts with it.
    static let keyPrefix = "group:"

    static func key(for group: GroupID) -> String { keyPrefix + group.rawValue.uuidString }

    /// The definition a library key names, or `nil` for a node type's ID.
    static func group(forKey key: String) -> GroupID? {
        guard key.hasPrefix(keyPrefix) else { return nil }
        return UUID(uuidString: String(key.dropFirst(keyPrefix.count))).map { GroupID(rawValue: $0) }
    }

    /// The row the library, the palette's label and the drag ghost draw for it.
    public var paletteEntry: PaletteEntry {
        PaletteEntry(typeID: key, displayName: name, category: .feature, accent: accent)
    }
}
````

**Modify** `Sources/CreatorEditor/LibraryItem.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/LibraryItem.swift b/Sources/CreatorEditor/LibraryItem.swift
index 26a76b0..d40228c 100644
--- a/Sources/CreatorEditor/LibraryItem.swift
+++ b/Sources/CreatorEditor/LibraryItem.swift
@@ -4,17 +4,36 @@ import CreatorGraph
 /// uniformly tall list so MetalUI's `List` builds only the rows in view (docs/metalui-gaps.md PERF-b).
 public struct LibraryItem: Equatable, Sendable, Identifiable {
     public var category: NodeCategory
-    /// The type, or `nil` for the category's header.
+    /// The type, or `nil` for a header.
     public var entry: PaletteEntry?
+    /// A group definition in the "Groups" section (groups spec §6), or `nil`.
+    public var group: GroupLibraryEntry?
+    /// The "Groups" section's header.
+    public var isGroupsHeader = false
 
-    /// The header's "header.<category>", or the type's ID.
-    public var id: String { entry?.typeID ?? "header.\(category.rawValue)" }
+    /// The header's "header.<category>" ("header.groups"), the type's ID, or the group's key.
+    public var id: String {
+        if let group { return group.key }
+        if isGroupsHeader { return "header.groups" }
+        return entry?.typeID ?? "header.\(category.rawValue)"
+    }
+
+    public init(category: NodeCategory, entry: PaletteEntry?, group: GroupLibraryEntry? = nil, isGroupsHeader: Bool = false) {
+        self.category = category
+        self.entry = entry
+        self.group = group
+        self.isGroupsHeader = isGroupsHeader
+    }
 
-    /// The rows of `sections`: each category's header, then its types.
-    public static func rows(_ sections: [LibrarySection]) -> [LibraryItem] {
-        sections.flatMap { section in
+    /// The rows of `sections`: each category's header, then its types; then, when there are `groups`, the "Groups"
+    /// header and one row each.
+    public static func rows(_ sections: [LibrarySection], groups: [GroupLibraryEntry] = []) -> [LibraryItem] {
+        let nodes = sections.flatMap { section in
             [LibraryItem(category: section.category, entry: nil)]
                 + section.entries.map { LibraryItem(category: section.category, entry: $0) }
         }
+        guard !groups.isEmpty else { return nodes }
+        return nodes + [LibraryItem(category: .feature, entry: nil, isGroupsHeader: true)]
+            + groups.map { LibraryItem(category: .feature, entry: nil, group: $0) }
     }
 }
````

**Modify** `Sources/CreatorEditor/LibraryRow.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/LibraryRow.swift b/Sources/CreatorEditor/LibraryRow.swift
index c13c40c..4bd57ab 100644
--- a/Sources/CreatorEditor/LibraryRow.swift
+++ b/Sources/CreatorEditor/LibraryRow.swift
@@ -1,6 +1,7 @@
 import MetalUI
 
-/// One row of the node library: a category's coloured header, or a type. A type's row shows the palette's row
+/// One row of the node library: a category's coloured header, or a type (or, in the "Groups" section, a group
+/// definition, with Delete when no node uses it). A type's row shows the palette's row
 /// content (`PaletteEntryLabel`) under one gesture, `GraphPanelInput.libraryGesture(for:)`: a click adds the type at
 /// the visible canvas's centre, a drag carries it to the canvas. Not a `Button`, because a child's click holds off an
 /// enclosing drag for the whole press in MetalUI (as in SwiftUI). Its help is the type's inputs → outputs.
@@ -10,7 +11,24 @@ struct LibraryRow: Component {
     let item: LibraryItem
 
     var content: some ElementGroup {
-        if let entry = item.entry {
+        if let group = item.group {
+            // A group definition: a click or drag places an instance; one nothing uses can be deleted (a button beside
+            // the gesture's area, so its click isn't a library click).
+            HStack(spacing: Pixels(4)) {
+                ZStack(alignment: .topLeading) {
+                    PaletteEntryLabel(entry: group.paletteEntry, isHighlighted: false)
+                }
+                .gesture(input.libraryGesture(for: group.key))
+                .contentShape(Rectangle())
+                .help(model.librarySummary(of: group.key) ?? group.name)
+                if group.canDelete {
+                    Button("Delete") { model.deleteGroup(group.group) }
+                        .help("Delete this group: no node uses it")
+                }
+            }
+        } else if item.isGroupsHeader {
+            LibrarySectionHeader(category: .feature, title: "Groups", accent: .purple)
+        } else if let entry = item.entry {
             ZStack(alignment: .topLeading) {
                 PaletteEntryLabel(entry: entry, isHighlighted: false)
             }
````

**Modify** `Sources/CreatorEditor/LibrarySectionHeader.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/LibrarySectionHeader.swift b/Sources/CreatorEditor/LibrarySectionHeader.swift
index 3b0b4bf..f3e134d 100644
--- a/Sources/CreatorEditor/LibrarySectionHeader.swift
+++ b/Sources/CreatorEditor/LibrarySectionHeader.swift
@@ -7,6 +7,8 @@ import MetalUI
 struct LibrarySectionHeader: Component {
     let category: NodeCategory
     let title: String
+    /// A group definition's accent colours the header in place of the category's (the "Groups" section).
+    var accent: AccentRole?
     @Environment(ThemeStore.self) var themes: ThemeStore?
 
     var content: some ElementGroup {
@@ -19,6 +21,6 @@ struct LibrarySectionHeader: Component {
         }
         .padding(Edges(top: Pixels(0), right: Pixels(6), bottom: Pixels(0), left: Pixels(6)))
         .frame(height: Pixels(18))
-        .background(palette.header(for: category).color, in: RoundedRectangle(cornerRadius: Pixels(4)))
+        .background((accent.map(palette.accent) ?? palette.header(for: category)).color, in: RoundedRectangle(cornerRadius: Pixels(4)))
     }
 }
````

**Modify** `Sources/CreatorEditor/NodeLibraryView.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/NodeLibraryView.swift b/Sources/CreatorEditor/NodeLibraryView.swift
index 0186367..31a8394 100644
--- a/Sources/CreatorEditor/NodeLibraryView.swift
+++ b/Sources/CreatorEditor/NodeLibraryView.swift
@@ -13,7 +13,7 @@ struct NodeLibraryView: Component {
 
     var content: some ElementGroup {
         let palette = Palette(themes)
-        let rows = LibraryItem.rows(model.librarySections)
+        let rows = model.libraryItems
         return VStack(alignment: .leading, spacing: PaletteLayout.spacing.px) {
             Text("Nodes")
                 .font(.system(.caption, weight: .semibold))
````

**Modify** `Sources/CreatorEditor/PaletteEntry.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/PaletteEntry.swift b/Sources/CreatorEditor/PaletteEntry.swift
index 230215c..eef42c8 100644
--- a/Sources/CreatorEditor/PaletteEntry.swift
+++ b/Sources/CreatorEditor/PaletteEntry.swift
@@ -5,6 +5,15 @@ public struct PaletteEntry: Equatable, Sendable, Identifiable {
     public var typeID: String
     public var displayName: String
     public var category: NodeCategory
+    /// A group definition's accent, which colours its dot in place of the category's.
+    public var accent: AccentRole?
 
     public var id: String { typeID }
+
+    public init(typeID: String, displayName: String, category: NodeCategory, accent: AccentRole? = nil) {
+        self.typeID = typeID
+        self.displayName = displayName
+        self.category = category
+        self.accent = accent
+    }
 }
````

**Modify** `Sources/CreatorEditor/PaletteEntryLabel.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorEditor/PaletteEntryLabel.swift b/Sources/CreatorEditor/PaletteEntryLabel.swift
index 6eb1a37..9415a3f 100644
--- a/Sources/CreatorEditor/PaletteEntryLabel.swift
+++ b/Sources/CreatorEditor/PaletteEntryLabel.swift
@@ -10,8 +10,9 @@ struct PaletteEntryLabel: Component {
 
     var content: some ElementGroup {
         let palette = Palette(themes)
+        let dot = entry.accent.map(palette.accent) ?? palette.header(for: entry.category)
         return HStack(spacing: Pixels(6)) {
-            Circle().fill(palette.header(for: entry.category).color).frame(width: Pixels(8), height: Pixels(8))
+            Circle().fill(dot.color).frame(width: Pixels(8), height: Pixels(8))
             Text(entry.displayName).font(.callout).foregroundStyle(palette.primaryText.color)
             Spacer()
         }
````

- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter 'LibraryGroupsTests|LibraryTests|LibraryViewTests|LibraryDragTests'`

Expected: every test passes (no "recorded an issue").

- [ ] **Step 5: Lint and run the whole suite**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-editor-test.log`.

Expected: exit code 0; `grep -cE 'recorded an issue|failed after' /tmp/groups-editor-test.log` prints 0; `grep -c 'Test run with' /tmp/groups-editor-test.log` prints 11; the counts on those lines add up to **1736** (master + 93). No new compiler warning.

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorEditor/EditorModel+Editing.swift' 'Sources/CreatorEditor/EditorModel+Library.swift' 'Sources/CreatorEditor/GroupLibraryEntry.swift' 'Sources/CreatorEditor/LibraryItem.swift' 'Sources/CreatorEditor/LibraryRow.swift' 'Sources/CreatorEditor/LibrarySectionHeader.swift' 'Sources/CreatorEditor/NodeLibraryView.swift' 'Sources/CreatorEditor/PaletteEntry.swift' 'Sources/CreatorEditor/PaletteEntryLabel.swift' 'Tests/CreatorEditorTests/LibraryGroupsTests.swift'
git commit -m "feat(groups): the library's Groups section"
```

---

### Task 11: The viewport inside a group (CreatorApp)

The app reads the level through the editor. Final preview and export stay on the top level; Selected node previews the level's selected node from `levelResults` (any node there, since the document evaluates the whole level); handles and picking use the level's graph and results; a pick is written through `GraphContent.relativeToLevel` so every instance reads it as its own; a pick under way is cancelled when the level changes; the solid a pick starts from is looked for among the nodes of the level shown only (Final preview's sources are top-level endpoints, and Group Output has no output to wire from); "Edit sketch" inside a group says it isn't supported yet, and an open sketch holds the level shown (`EditorModel.isLevelLocked`); Show Producing Node goes back out to the top level for the group node; AppModel's Undo/Redo call `refreshLevel()`.

**Files:**
- Modify: `Sources/CreatorApp/AppModel.swift`
- Modify: `Sources/CreatorApp/AppModel+Picking.swift`
- Modify: `Sources/CreatorApp/AppModel+Scene.swift`
- Modify: `Sources/CreatorApp/AppModel+Undo.swift`
- Modify: `Sources/CreatorApp/AppModel+Viewport.swift`
- Modify: `Sources/CreatorApp/PickSession.swift`
- Create: `Tests/CreatorAppTests/GroupViewportTests.swift`

**Interfaces:**
- Consumes: T1: `relativeToLevel`; T2: `inspectedLevel`; T4: `graph`, `levelResults`, `result(of:)`, `graphPath`, `levelPath`, `goToLevel`, `refreshLevel`.
- Produces:
  - `PickSession.level: [NodeID]` (default `[]`).
  - `AppModel.relativeToLevel(_:)` (internal); `shownScene()` (private); `AppModel.sketch`'s `didSet` sets `editor.isLevelLocked`; the app's scene, handles, picking, sketch guard, Show Producing Node and Undo/Redo follow the level.

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorAppTests/GroupViewportTests.swift`:

````swift
import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// The viewport while the graph panel shows the inside of a group (groups spec §6): Selected-node preview, handles and
/// picking work on the level shown, Final preview shows the whole part, and a pick is written relative to the level.
@MainActor
struct GroupViewportTests {
    /// Rectangle → Extrude → Output, with Rectangle and Extrude grouped; the app is inside the group.
    struct Scene {
        let app: AppModel
        let rectangle: Node, extrude: Node, output: Node
        let group: NodeID
    }

    func groupedBox(enter: Bool = true) async throws -> Scene {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.rectangle.id, box.extrude.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        if enter { app.editor.enterGroup(group) }
        await app.settle()
        return Scene(app: app, rectangle: box.rectangle, extrude: box.extrude, output: box.output, group: group)
    }

    @Test func finalPreviewStillShowsTheWholePartInsideAGroup() async throws {
        let scene = try await groupedBox()
        let app = scene.app
        #expect(app.editor.isInsideGroup && app.previewMode == .final)
        #expect(app.viewport.items.count == 1)
        #expect(app.viewport.items.first?.solid.bounds.size.z == 10)
        app.editor.selection = [scene.extrude.id]
        await app.settle()
        #expect(app.viewport.items.count == 1 && app.viewport.items.first?.isGhost == false, "selecting inside changes nothing")
    }

    @Test func selectedNodePreviewShowsTheSelectedNodeOfTheLevel() async throws {
        let scene = try await groupedBox()
        let app = scene.app
        app.previewMode = .selectedNode
        await app.settle()
        #expect(app.viewport.items.isEmpty, "nothing selected")
        app.editor.selection = [scene.extrude.id]
        await app.settle()
        let shown = try #require(app.viewport.items.first)
        #expect(app.viewport.items.count == 1 && shown.solid.bounds.size.z == 10)
        #expect(app.document.previewNode == nil, "the document evaluates the whole level instead")
        app.editor.exitGroup()
        await app.settle()
        #expect(app.viewport.items.isEmpty, "the extrude isn't on the top level")
    }

    @Test func aNodeNothingReadsPreviewsToo() async throws {
        let scene = try await groupedBox()
        let app = scene.app
        app.previewMode = .selectedNode
        app.editor.transform = CanvasTransform()
        let lonely = try #require(app.editor.registry.makeNode(ExtrudeNode.typeID, at: Vector2(200, 300)) as Node?)
        try app.editor.edit(.addNode(lonely))
        app.editor.connect(Link(from: Endpoint(node: scene.rectangle.id, socket: "profile"),
                                to: Endpoint(node: lonely.id, socket: "profile")))
        app.editor.selection = [lonely.id]
        await app.settle()
        #expect(app.viewport.items.count == 1 && app.viewport.items.first?.solid.bounds.size.z == 10,
                "evaluated for the panel's sake, not for any Output")
    }

    @Test func aHandleInsideAGroupEditsTheDefinitionAsOneStep() async throws {
        let scene = try await groupedBox()
        let app = scene.app
        app.editor.selection = [scene.extrude.id]
        await app.settle()
        let handle = try #require(app.viewport.handles.first)
        app.handleChanged(handle.id, 25, .changed)
        app.handleChanged(handle.id, 30, .ended)
        let distance = app.document.definitions.values.first?.graph.nodes[scene.extrude.id]?.inputValues["distance"]
        #expect(distance == .number(30))
        #expect(app.document.graph.nodes[scene.extrude.id] == nil)
        await app.settle()
        #expect(app.viewport.items.first?.solid.bounds.size.z == 30, "the part follows")
        app.undo()
        #expect(app.document.definitions.values.first?.graph.nodes[scene.extrude.id]?.inputValues["distance"] == .number(10))
    }

    /// Rectangle → Extrude → Edges by Tag → Chamfer → Output, with everything but the Output grouped.
    struct ChamferGroup {
        let app: AppModel
        let extrude: Node, rule: Node, chamfer: Node
        let group: NodeID
    }

    func chamferGroup() async throws -> ChamferGroup {
        var builder = GraphBuilder()
        let box = builder.solid()
        let rule = builder.add(EdgesByTagNode.self, at: Vector2(480, 0))
        let chamfer = builder.add(ChamferNode.self, at: Vector2(720, 0))
        let output = builder.add(OutputNode.self, at: Vector2(960, 0))
        builder.wire(box.extrude, "solid", to: rule, "solid")
        builder.wire(rule, "edges", to: chamfer, "edges")
        builder.wire(chamfer, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.rectangle.id, box.extrude.id, rule.id, chamfer.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        app.editor.enterGroup(group)
        await app.settle()
        return ChamferGroup(app: app, extrude: box.extrude, rule: rule, chamfer: chamfer, group: group)
    }

    @Test func aPickMadeInsideAGroupIsWrittenRelativeToTheLevel() async throws {
        let made = try await chamferGroup()
        let (app, extrude, rule, chamfer, group) = (made.app, made.extrude, made.rule, made.chamfer, made.group)
        app.beginPick(for: rule.id)
        let session = try #require(app.pick)
        #expect(session.level == [group] && session.rule == rule.id)
        await app.settle()
        app.viewportClicked(.edge(solid: 0, EdgeID(1)))
        app.viewportClicked(.edge(solid: 0, EdgeID(3)))
        app.finishPick()
        await app.settle()
        let stored = try #require(app.document.definitions.values.first?.graph.nodes[rule.id]?.inputValues[NodeSetting.picks])
        guard case .edgePicks(let picks) = stored else {
            Issue.record("expected edge picks, got \(stored)")
            return
        }
        let named = Set(picks.flatMap { [$0.key.first, $0.key.second] }.flatMap { $0 }.map(\.node))
        #expect(named.contains(extrude.id), "the extrude is named as the definition names it")
        #expect(!named.contains(NodeID.scoped([group, extrude.id])), "not under this instance's identity")
        #expect(app.editor.result(of: chamfer.id)?.state.isSuccess == true, "the chamfer finds its edges")
        #expect(app.editor.selection == [rule.id])
        app.undo()
        #expect(app.document.definitions.values.first?.graph.nodes[rule.id]?.inputValues[NodeSetting.picks] == nil)
    }

    @Test func aPickBelongsToTheLevelItBeganOn() async throws {
        let made = try await chamferGroup()
        let (app, rule) = (made.app, made.rule)
        app.beginPick(for: rule.id)
        #expect(app.pick != nil)
        app.editor.exitGroup()
        await app.settle()
        #expect(app.pick == nil, "showing another level cancels it")
    }

    @Test func inFinalPreviewAPickStartsFromANodeOfTheLevelShown() async throws {
        let scene = try await groupedBox()
        let app = scene.app
        #expect(app.previewMode == .final)
        let shown = try #require(app.viewport.items.first).solid
        let source = try #require(app.producer(of: shown))
        #expect(app.editor.graph.nodes[source.node] != nil, "not the group node's endpoint, which this level doesn't have")
        #expect(source.node == scene.extrude.id, "and not Group Output, which has no output to wire from")
    }

    @Test func anOpenSketchHoldsTheLevelShown() async throws {
        var builder = GraphBuilder()
        let sketched = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.editor.selection = [sketched.extrude.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        app.beginSketch(for: sketched.sketch.id)
        await app.settle()
        #expect(app.sketch != nil && app.editor.isLevelLocked)
        #expect(!app.editor.enterGroup(group) && app.editor.levelPath.isEmpty, "the sketch lives on the top level")
        app.finishSketch()
        await app.settle()
        #expect(!app.editor.isLevelLocked && app.editor.enterGroup(group))
    }

    @Test func aSketchInsideAGroupIsRefusedWithAReason() async throws {
        var builder = GraphBuilder()
        let sketched = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.editor.selection = [sketched.sketch.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        app.editor.enterGroup(group)
        app.editor.press(.editSketch, on: sketched.sketch.id)
        app.handle(try #require(app.editor.inspectorRequest))
        #expect(app.sketch == nil)
        #expect(app.alert != nil, "it says why")
    }

    @Test func showProducingNodeGoesBackOutToTheGroupNode() async throws {
        let scene = try await groupedBox()
        let app = scene.app
        app.showProducingNode(NodeID.scoped([scene.group, scene.extrude.id]))
        #expect(app.editor.levelPath.isEmpty)
        #expect(app.editor.selection == [scene.group])
    }

    @Test func undoFromInsideAGroupAfterTheGroupWasUndoneLeavesIt() async throws {
        let scene = try await groupedBox()
        let app = scene.app
        app.undo()
        #expect(app.editor.enteredGroups.isEmpty && app.document.definitions.isEmpty)
        #expect(app.editor.graph.nodes[scene.extrude.id] != nil, "the top level has its nodes back")
    }
}
````

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep 'error:'`

Expected: the build fails: `PickSession` has no `level`. (The viewport tests also need the new behaviour.)

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorApp/AppModel.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorApp/AppModel.swift b/Sources/CreatorApp/AppModel.swift
index 1af7b1d..7998642 100644
--- a/Sources/CreatorApp/AppModel.swift
+++ b/Sources/CreatorApp/AppModel.swift
@@ -31,8 +31,11 @@ public final class AppModel {
     public var previewMode: PreviewMode = .final
     /// "Pick edges in view…" in progress.
     public internal(set) var pick: PickSession?
-    /// A Sketch node being edited in the viewport (sketcher spec §8), or `nil`.
-    public internal(set) var sketch: SketchSession?
+    /// A Sketch node being edited in the viewport (sketcher spec §8), or `nil`. Sketch mode works on the top level's
+    /// graph, so the graph panel keeps the level it shows while one is open (`EditorModel.isLevelLocked`).
+    public internal(set) var sketch: SketchSession? {
+        didSet { editor.isLevelLocked = sketch != nil }
+    }
     public var alert: AppAlert?
     /// The docked graph panel's width (docked left) and height (docked at the bottom), in points.
     public internal(set) var panelWidth = AppLayout.defaultPanelWidth
````

**Modify** `Sources/CreatorApp/AppModel+Picking.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorApp/AppModel+Picking.swift b/Sources/CreatorApp/AppModel+Picking.swift
index d114403..260cf72 100644
--- a/Sources/CreatorApp/AppModel+Picking.swift
+++ b/Sources/CreatorApp/AppModel+Picking.swift
@@ -17,6 +17,12 @@ extension AppModel {
             // Only a double click on the graph canvas can ask while a sketch is open (the inspector shows the
             // sketch's lists then): it changes nothing, so the stroke, selection and camera stay (Errata (S5b)).
             guard sketch == nil else { return }
+            // The sketch editor works on the top level's graph, as the rest of sketch mode does.
+            guard !editor.isInsideGroup else {
+                alert = .problem(AppProblem("The sketch can't be edited here",
+                                            "Sketches inside a group can't be edited yet. Edit it before grouping, or from the top level."))
+                return
+            }
             beginSketch(for: request.node)
         case .editGroup, .makeUnique, .ungroup:
             break  // The graph panel carries these out itself (`EditorModel.press`); they are never recorded.
@@ -32,15 +38,15 @@ extension AppModel {
         editor.commitPendingEntry()
         // The banner's Escape and Return are button shortcuts, which run before the palette's keys in `onInput`.
         editor.closePalette()
-        let graph = document.graph
+        let graph = editor.graph
         guard let node = graph.nodes[id] else { return }
         if node.typeID == EdgesByTagNode.typeID {
             guard let source = graph.incomingLink(to: Endpoint(node: id, socket: "solid"))?.from,
                   let solid = solid(at: source) else {
                 return refusePick("Wire a solid with a result into “\(node.name)” first, then pick its edges.")
             }
-            let current = SceneBuilder.edgeSets(document.results[id]).first { $0.solid === solid }?.edges ?? []
-            pick = PickSession(solid: solid, source: source, rule: id, consumer: nil, picked: current)
+            let current = SceneBuilder.edgeSets(editor.result(of: id)).first { $0.solid === solid }?.edges ?? []
+            pick = PickSession(solid: solid, source: source, rule: id, consumer: nil, picked: current, level: editor.levelPath)
             return
         }
         let consumer = Endpoint(node: id, socket: "edges")
@@ -48,10 +54,11 @@ extension AppModel {
             return refusePick("Wire an edge rule into “\(node.name)” first, so there are edges to pick on.")
         }
         if upstream.typeID == EdgesByTagNode.typeID { return beginPick(for: upstream.id) }
-        guard let set = SceneBuilder.edgeSets(document.results[upstream.id]).first, let source = producer(of: set.solid) else {
+        guard let set = SceneBuilder.edgeSets(editor.result(of: upstream.id)).first, let source = producer(of: set.solid) else {
             return refusePick("“\(upstream.name)” has no edges to start from yet.")
         }
-        pick = PickSession(solid: set.solid, source: source, rule: nil, consumer: consumer, picked: set.edges)
+        pick = PickSession(solid: set.solid, source: source, rule: nil, consumer: consumer, picked: set.edges,
+                           level: editor.levelPath)
     }
 
     /// Done: the picks go into the rule (or a new one), as one undo step, and the rule is selected.
@@ -61,7 +68,7 @@ extension AppModel {
         let picks = ConstantValue.edgePicks(session.solid.topology.picks(for: session.picked))
         do {
             if let rule = session.rule {
-                try document.perform(.setInput(rule, NodeSetting.picks, picks))
+                try document.perform(.setInput(rule, NodeSetting.picks, relativeToLevel(picks)), at: editor.graphPath)
                 editor.selection = [rule]
             } else {
                 editor.selection = [try addRule(picks, from: session.source, into: session.consumer)]
@@ -109,27 +116,39 @@ extension AppModel {
     /// Adds an Edges by Tag rule holding `picks`, wired from `source` and, when given, into `consumer` (replacing
     /// its wire), as one undo step. It's placed between the two nodes, or beside `source`.
     func addRule(_ picks: ConstantValue, from source: Endpoint, into consumer: Endpoint?) throws(GraphError) -> NodeID {
-        let graph = document.graph
+        let graph = editor.graph
         let from = graph.nodes[source.node]?.position ?? .zero
         let position = consumer.flatMap { graph.nodes[$0.node]?.position }.map { (from + $0) * 0.5 + Vector2(0, 140) }
             ?? from + Vector2(240, 140)
         var rule = registry.makeNode(EdgesByTagNode.typeID, at: position)
-        rule.inputValues[NodeSetting.picks] = picks
+        rule.inputValues[NodeSetting.picks] = relativeToLevel(picks)
         var commands: [GraphCommand] = [.addNode(rule), .connect(Link(from: source, to: Endpoint(node: rule.id, socket: "solid")))]
         if let consumer {
             commands.append(.connect(Link(from: Endpoint(node: rule.id, socket: "edges"), to: consumer)))
         }
-        try document.perform(.batch(commands))
+        try document.perform(.batch(commands), at: editor.graphPath)
         return rule.id
     }
 
+    /// A pick made in the viewport, as the graph panel's level names faces: the faces shown were made under the
+    /// instance's identities, and a pick stored inside a group names them as its definition does
+    /// (`GraphContent.relativeToLevel`), so every instance reads it as its own. On the top level it is unchanged.
+    func relativeToLevel(_ picks: ConstantValue) -> ConstantValue {
+        document.content.relativeToLevel(picks, levels: editor.levelPath)
+    }
+
     /// The output socket that produced `solid`, by identity: a shown solid's recorded source, else any node
     /// whose current result carries it, preferring a node that isn't an Output (which only passes it through).
     func producer(of solid: Solid) -> Endpoint? {
-        if let source = sources[ObjectIdentifier(solid)] { return source }
+        // `sources` come from the scene shown, which in Final preview carries the top level's endpoints (an Output
+        // passes on what is wired into it): inside a group only a source that is a node of the level shown counts.
+        if let source = sources[ObjectIdentifier(solid)], editor.graph.nodes[source.node] != nil { return source }
-        let candidates = document.results.keys.sorted().flatMap { id -> [(Endpoint, Bool)] in
-            guard let result = document.results[id], result.state.isSuccess, let outputs = result.outputs else { return [] }
-            let isOutput = document.graph.nodes[id]?.isOutput ?? false
+        let results = editor.levelResults
+        let candidates = results.keys.sorted().flatMap { id -> [(Endpoint, Bool)] in
+            // Group Output only passes its inputs on to the group node: it has no output to wire from.
+            guard let result = results[id], result.state.isSuccess, let outputs = result.outputs,
+                  editor.graph.nodes[id]?.typeID != GroupNodes.outputTypeID else { return [] }
+            let isOutput = editor.graph.nodes[id]?.isOutput ?? false
             return outputs.keys.sorted().compactMap { socket in
                 outputs[socket]?.items.contains { scalar in
                     if case .solid(let candidate) = scalar { candidate === solid } else { false }
@@ -141,7 +160,7 @@ extension AppModel {
 
     /// The first solid the output `endpoint` carries now.
     func solid(at endpoint: Endpoint) -> Solid? {
-        guard let result = document.results[endpoint.node], result.state.isSuccess else { return nil }
+        guard let result = editor.result(of: endpoint.node), result.state.isSuccess else { return nil }
         for case .solid(let solid) in result.outputs?[endpoint.socket]?.items ?? [] { return solid }
         return nil
     }
````

**Modify** `Sources/CreatorApp/AppModel+Scene.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorApp/AppModel+Scene.swift b/Sources/CreatorApp/AppModel+Scene.swift
index 04f230a..7d69c34 100644
--- a/Sources/CreatorApp/AppModel+Scene.swift
+++ b/Sources/CreatorApp/AppModel+Scene.swift
@@ -20,9 +20,12 @@ extension AppModel {
         observeScene()
     }
 
-    /// "Selected node" previews the one selected node; Final, or anything but one selected node, previews none.
+    /// "Selected node" previews the one selected node of the level shown; Final, or anything but one selected node, previews none.
     func applyPreview() {
-        let wanted = previewMode == .selectedNode && editor.selection.count == 1 ? editor.selection.first : nil
+        // Inside a group the document evaluates the whole level (`DocumentModel.inspectedLevel`), so the selected node
+        // needs no demand of its own there.
+        let wanted = previewMode == .selectedNode && editor.selection.count == 1 && !editor.isInsideGroup
+            ? editor.selection.first : nil
         if document.previewNode != wanted { document.previewNode = wanted }
     }
 
@@ -32,14 +35,14 @@ extension AppModel {
     /// sent again: the observation also fires for canvas pans, camera settles and panel resizes, which change neither.
     func refreshScene() {
         refreshSketch()
+        // A pick belongs to the level it began on: showing another cancels it.
+        if let session = pick, session.level != editor.levelPath { pick = nil }
         var scene: [SceneItem]
         if viewport.isPicking != (pick != nil) { viewport.isPicking = pick != nil }
         if let pick {
             scene = [SceneItem(item: ViewportItem(solid: pick.solid, selectedEdges: Set(pick.picked)), source: pick.source)]
         } else {
-            let shown = previewMode == .final ? outputNodes : (document.previewNode.map { [$0] } ?? [])
-            scene = SceneBuilder.scene(shown: shown, graph: document.graph, results: document.results,
-                                       lastGood: document.lastGoodOutputs, selection: editor.selection)
+            scene = shownScene()
         }
         if sketch != nil {
             scene = scene.map { entry in
@@ -56,13 +59,28 @@ extension AppModel {
             viewport.show(items)
         }
         let handles = pick == nil && sketch == nil
-            ? HandleBuilder.handles(for: editor.selection, graph: document.graph, results: document.results, registry: registry)
+            ? HandleBuilder.handles(for: editor.selection, graph: editor.graph, results: editor.levelResults, registry: registry)
             : []
         handleTargets = Dictionary(handles.map { ($0.handle.id, $0.target) }, uniquingKeysWith: { first, _ in first })
         let shownHandles = handles.map(\.handle)
         if viewport.handles != shownHandles { viewport.showHandles(shownHandles) }
     }
 
+    /// The scene for the preview mode: Final shows every Output node of the whole part, whichever level the graph
+    /// panel shows; Selected node shows the one selected node of that level, from the top-level results or, inside
+    /// a group, from the results inside it (`EditorModel.levelResults`; there is no last good result to ghost).
+    private func shownScene() -> [SceneItem] {
+        if previewMode == .final {
+            return SceneBuilder.scene(shown: outputNodes, graph: document.graph, results: document.results,
+                                      lastGood: document.lastGoodOutputs, selection: editor.isInsideGroup ? [] : editor.selection)
+        }
+        let shown = editor.isInsideGroup
+            ? (editor.selection.count == 1 ? Array(editor.selection) : [])
+            : (document.previewNode.map { [$0] } ?? [])
+        return SceneBuilder.scene(shown: shown, graph: editor.graph, results: editor.levelResults,
+                                  lastGood: editor.isInsideGroup ? [:] : document.lastGoodOutputs, selection: editor.selection)
+    }
+
     /// Follows what the scene is made from, once; the first change schedules one refresh, which follows again. A
     /// registration made for parts that have since been replaced is ignored by its generation.
     func observeScene() {
@@ -70,8 +88,11 @@ extension AppModel {
         let generation = observationGeneration
         withObservationTracking {
             _ = document.results
+            _ = document.innerResults
             _ = document.lastGoodOutputs
             _ = document.graph
+            _ = document.definitions
+            _ = editor.enteredGroups
             _ = document.previewNode
             _ = editor.selection
             _ = editor.dock
````

**Modify** `Sources/CreatorApp/AppModel+Undo.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorApp/AppModel+Undo.swift b/Sources/CreatorApp/AppModel+Undo.swift
index 02f0f62..b765542 100644
--- a/Sources/CreatorApp/AppModel+Undo.swift
+++ b/Sources/CreatorApp/AppModel+Undo.swift
@@ -5,11 +5,13 @@ extension AppModel {
     public func undo() {
         editor.commitPendingEntry()
         document.undo()
+        editor.refreshLevel()
     }
 
     /// Redo. A typed value is committed first, as for Undo; it is a new edit, so nothing is left to redo.
     public func redo() {
         editor.commitPendingEntry()
         document.redo()
+        editor.refreshLevel()
     }
 }
````

**Modify** `Sources/CreatorApp/AppModel+Viewport.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorApp/AppModel+Viewport.swift b/Sources/CreatorApp/AppModel+Viewport.swift
index 6ad19e7..74ae14c 100644
--- a/Sources/CreatorApp/AppModel+Viewport.swift
+++ b/Sources/CreatorApp/AppModel+Viewport.swift
@@ -40,7 +40,8 @@ extension AppModel {
         guard let target = handleTargets[id] else { return }
         if value != currentNumber(target) {
             do {
-                try document.perform(.setInput(target.node, target.socket, .number(value)), coalescingKey: "handle-\(id)")
+                try document.perform(.setInput(target.node, target.socket, .number(value)), at: editor.graphPath,
+                                     coalescingKey: "handle-\(id)")
             } catch {
                 alert = .problem(AppProblem("The value couldn't be changed", error.message))
             }
@@ -51,17 +52,19 @@ extension AppModel {
     /// The number `target` currently reads: its stored input, or its socket's default (from `inputs(for:)`, so a
     /// per-node socket's default counts).
     private func currentNumber(_ target: HandleTarget) -> Double? {
-        guard let node = document.graph.nodes[target.node] else { return nil }
+        guard let node = editor.graph.nodes[target.node] else { return nil }
         let stored = node.inputValues[target.socket]
             ?? registry[node.typeID]?.inputs(for: node).first { $0.name == target.socket }?.defaultValue
         return HandleBuilder.number(stored)
     }
 
     /// "Show Producing Node": selects the node and scrolls the graph to it, showing a hidden panel first. A face made
-    /// inside a group names a scoped ID, so its group node on the top level is shown.
+    /// inside a group names a scoped ID, so its group node on the top level is shown: the panel goes back out to the
+    /// top level for it.
     func showProducingNode(_ id: NodeID) {
         guard let node = producingNode(id) else { return }
         if !editor.isPanelVisible { editor.toggleHidden() }
+        editor.goToLevel(0)
         editor.selection = [node.id]
         let zoom = editor.transform.zoom
         editor.transform = CanvasTransform(offset: AppLayout.revealPoint - editor.displayOrigin(of: node) * zoom, zoom: zoom)
````

**Modify** `Sources/CreatorApp/PickSession.swift` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/Sources/CreatorApp/PickSession.swift b/Sources/CreatorApp/PickSession.swift
index df1f58b..578c27e 100644
--- a/Sources/CreatorApp/PickSession.swift
+++ b/Sources/CreatorApp/PickSession.swift
@@ -15,13 +15,17 @@ public struct PickSession {
     public var consumer: Endpoint?
     /// The picked edges, in the order they were picked.
     public var picked: [EdgeID]
+    /// The level of the graph panel the pick began on (`EditorModel.levelPath`): `source`, `rule` and `consumer` are
+    /// nodes of that level's graph, and Done writes there.
+    public var level: [NodeID]
 
-    public init(solid: Solid, source: Endpoint, rule: NodeID?, consumer: Endpoint?, picked: [EdgeID]) {
+    public init(solid: Solid, source: Endpoint, rule: NodeID?, consumer: Endpoint?, picked: [EdgeID], level: [NodeID] = []) {
         self.solid = solid
         self.source = source
         self.rule = rule
         self.consumer = consumer
         self.picked = picked
+        self.level = level
     }
 
     /// Adds `edge`, or removes it if it's already picked.
````

- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter 'GroupViewportTests'`

Expected: every test passes (no "recorded an issue").

- [ ] **Step 5: Lint and run the whole suite**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-editor-test.log`.

Expected: exit code 0; `grep -cE 'recorded an issue|failed after' /tmp/groups-editor-test.log` prints 0; `grep -c 'Test run with' /tmp/groups-editor-test.log` prints 11; the counts on those lines add up to **1747** (master + 104). No new compiler warning.

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorApp/AppModel.swift' 'Sources/CreatorApp/AppModel+Picking.swift' 'Sources/CreatorApp/AppModel+Scene.swift' 'Sources/CreatorApp/AppModel+Undo.swift' 'Sources/CreatorApp/AppModel+Viewport.swift' 'Sources/CreatorApp/PickSession.swift' 'Tests/CreatorAppTests/GroupViewportTests.swift'
git commit -m "feat(groups): the viewport, handles and picking inside a group"
```

---

### Task 12: Review pins and docs

Tests for inputs the spec implies and no earlier task pins (the Review Focus below), then the docs: CLAUDE.md, the roadmap's C2 row, Errata (C2) at the end of the groups spec, and the human-check group GR. No MetalUI gap was found, so `docs/metalui-gaps.md` is unchanged.

**Files:**
- Modify: `CLAUDE.md`
- Create: `Tests/CreatorAppTests/GroupPickInstancesTests.swift`
- Create: `Tests/CreatorEditorTests/EditorLevelReviewTests.swift`
- Modify: `docs/superpowers/roadmap.md`
- Modify: `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md`
- Modify: `docs/verification/human-checks.md`

**Interfaces:**
- Consumes: Everything above (descriptions only).
- Produces:
  Tests and docs only.

- [ ] **Step 1: Write the tests**

**Create** `Tests/CreatorAppTests/GroupPickInstancesTests.swift`:

````swift
import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// A pick made inside a group holds for every instance of the definition (groups spec §5 Naming, §6 Viewport): it is
/// stored the way the definition names faces, and each instance reads it as its own.
@MainActor
struct GroupPickInstancesTests {
    @Test func aPickMadeInsideOneInstanceChamfersTheOtherToo() async throws {
        var builder = GraphBuilder()
        let box = builder.solid()
        let rule = builder.add(EdgesByTagNode.self, at: Vector2(480, 0))
        let chamfer = builder.add(ChamferNode.self, at: Vector2(720, 0))
        let output = builder.add(OutputNode.self, at: Vector2(960, 0))
        builder.wire(box.extrude, "solid", to: rule, "solid")
        builder.wire(rule, "edges", to: chamfer, "edges")
        builder.wire(chamfer, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.rectangle.id, box.extrude.id, rule.id, chamfer.id]
        app.editor.groupSelection()
        let first = try #require(app.editor.selection.first)
        app.editor.perform(.duplicate)
        let second = try #require(app.editor.selection.first)
        try app.document.perform(.setOutput(second, true))
        app.editor.enterGroup(first)
        await app.settle()

        app.beginPick(for: rule.id)
        await app.settle()
        app.viewportClicked(.edge(solid: 0, EdgeID(1)))
        app.viewportClicked(.edge(solid: 0, EdgeID(3)))
        app.finishPick()
        await app.settle()
        #expect(app.document.innerResults[[first, chamfer.id]]?.state.isSuccess == true, "the instance it was made in")
        #expect(app.document.innerResults[[second, chamfer.id]]?.state.isSuccess == true, "and the other one")
    }
}
````

**Create** `Tests/CreatorEditorTests/EditorLevelReviewTests.swift`:

````swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Inputs the groups spec implies for the levels of the graph panel (§6), pinned: two instances of one definition, a
/// value typed before entering, an Output node added inside, a drag under way, and a saved file.
@MainActor
struct EditorLevelReviewTests {
    /// The rectangle's profile in a result.
    func profile(_ result: NodeResult?) -> Profile2D? {
        for case .profile(let profile)? in [result?.outputs?["profile"]?.items.first] { return profile }
        return nil
    }

    @Test func insideASharedDefinitionTheStatesAreTheEnteredInstances() async throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.perform(.duplicate)
        let second = try #require(editor.selection.first)
        try editor.edit(.setInput(second, "width", .number(50)))
        try editor.edit(.setInput(grouped.number.id, "value", .number(7)))
        await editor.document.waitForEvaluation()

        editor.enterGroup(grouped.group)
        await editor.document.waitForEvaluation()
        let first = try #require(editor.result(of: grouped.rectangle.id))
        editor.exitGroup()
        editor.enterGroup(second)
        await editor.document.waitForEvaluation()
        let other = try #require(editor.result(of: grouped.rectangle.id))
        #expect(first.state.isSuccess && other.state.isSuccess)
        #expect(profile(first) != nil && profile(first) != profile(other), "the first is wired to 7 mm, the second typed 50")
        #expect(profile(editor.document.innerResults[[second, grouped.rectangle.id]]) == profile(other))
    }

    @Test func aValueTypedBeforeEnteringIsCommittedToTheNodeItWasTypedOn() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.number.id]
        guard case .slider(let field, _)? = editor.inspectorPage.sections.first?.rows.first else {
            Issue.record("no value slider on the Number node")
            return
        }
        editor.notePendingEntry(PendingEntry(text: "33", commit: { editor.setNumber(field, to: $0) }))
        editor.selection = [grouped.group]
        editor.enterGroup(grouped.group)
        #expect(editor.rootGraph.nodes[grouped.number.id]?.inputValues["value"] == .number(33))
        #expect(grouped.current?.graph.nodes[grouped.number.id] == nil, "and not looked for inside")
    }

    @Test func anOutputNodeAddedInsideAGroupIsRefusedWithTheSpecsSentence() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        #expect(!editor.addNode(OutputTestNode.typeID, atScreen: Vector2(100, 100)))
        #expect(editor.refusal?.message == "An Output node can't go in a group.")
        #expect(editor.graph.nodes.count == 4)
        #expect(editor.addNode(NumberTestNode.typeID, atScreen: Vector2(100, 100)), "any other node goes in")
        #expect(grouped.current?.graph.nodes.count == 5)
    }

    @Test func theLevelDoesntChangeUnderADragInProgress() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        let start = editor.screenPoint(in: grouped.group)
        editor.pointerDragged(from: start, to: start)
        editor.pointerDragged(from: start, to: start + Vector2(40, 0))
        #expect(editor.interaction != nil)
        #expect(!editor.enterGroup(grouped.group))
        #expect(editor.perform(.enterGroup), "claimed, so the key can't go elsewhere mid-drag")
        #expect(editor.levelPath.isEmpty)
        editor.pointerReleased(from: start, at: start + Vector2(40, 0))
        #expect(editor.enterGroup(grouped.group))
    }

    @Test func theLevelShownIsNotSavedWithTheFile() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        let reopened = EditorModel(document: try DocumentModel(data: try editor.document.fileData(),
                                                               registry: editorTestRegistry, kernel: FakeKernel()))
        #expect(reopened.levelPath.isEmpty && reopened.graph.nodes.count == 3)
        #expect(reopened.document.definitions == editor.document.definitions)
        #expect(reopened.document.inspectedLevel.isEmpty)
    }
}
````

- [ ] **Step 2: Edit the docs**

**Modify** `CLAUDE.md` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/CLAUDE.md b/CLAUDE.md
index d534853..a11e712 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -16,8 +16,9 @@ Themes (custom themes, `.mctheme` files, the theme editor) code is done; its hum
 M7 (measure and record) code is done: spec §7.3's numbers are in `docs/verification/performance.md`, taken by the
 release benchmarks in `Tests/CreatorAppTests/Bench` (`scripts/bench.sh`); `docs/metalui-gaps.md` opens with a summary
 table of every gap, its MetalUI item and its status; its human checks (group M7) are pending.
-Groups C1 (model and evaluation, `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` §4–§5) is done:
-⌘G/⇧⌘G work on the top level; entering a group, breadcrumbs and the group inspector are C2.
+Groups C1 (model and evaluation, `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` §4–§5) is done.
+Groups C2 (the editor, §6: entering a group, breadcrumbs, the + sockets, the group inspector, the library's Groups
+section, the viewport and the clipboard inside groups) code is done; its human checks (group GR) are pending.
 
 Module boundaries (dependency order):
 - `CreatorGeometry`: value types (vectors, planes, profiles, bounds). Millimetres.
@@ -49,6 +50,12 @@ Module boundaries (dependency order):
     if the definition were the top level (`GroupScopes.identity`), and `EvaluationScope.naming` reads it as each
     instance's; Group, Ungroup and Make Unique rename every pick whose faces they move (`GroupScopes.renamingPicks`),
     so no pick drifts. Dirty state compares `DocumentModel.content` (definitions too).
+    The editor's levels (`GraphContent.path(entering:)`, `existingLevels(_:)`, `relativeToLevel(_:levels:)`: a level is
+    the group nodes entered from the top level, each by its ID in the graph before it) and
+    `DocumentModel.inspectedLevel` (the level the panel shows, which `Evaluator.evaluate(…inspecting:)` evaluates
+    whole, so `innerResults` has a state for every node there; a node asked for that way never changes its group
+    node's result). `GroupCommands.exposeOutput/exposeInput` (the + sockets) and `GroupMerge` (the clipboard's
+    definitions, merged by content) build one command each. `GroupNaming.plusSocket` ("+") is a reserved name.
 - `CreatorNodes`: the 28 built-in node definitions (`BuiltInNodes.registry`: the slice's 26 plus Plane from Face and
   Sketch), UI-free: inspector sections and handles are data. Non-socket settings (`NodeSetting` in CreatorGraph:
   parameter, picks, showHandle, sketch, face, groupID, and `projection(reference)` per projected edge) live in
@@ -96,6 +103,17 @@ Module boundaries (dependency order):
   repeat (gap M7-a), and a `NodeID` prints only 8 hex digits. The window's size reaches the panel's placement through
   `ViewportModel.observedViewSize` (bumped one task after the draw records a new size, gap M4-a), never `viewSize`
   itself, so a resize rebuilds the canvas.
+  The graph panel shows a level (`EditorModel+Levels`: `enteredGroups`/`levelPath`, `enterGroup(_:)`, `exitGroup()`,
+  `goToLevel(_:)`, `breadcrumbs`, `refreshLevel()` after anything that undoes): `EditorModel.graph` is the level's
+  graph, so every reader (hit testing, drawing, the inspector, selection) sees it, and every edit goes through
+  `edit(_:coalescingKey:)`, which addresses `graphPath`; the document's parameters stay on `rootGraph`. Each level keeps
+  its own pan and zoom in the model (not saved), and changing level clears the selection. A group node's Edit Group,
+  Make Unique and Ungroup are its inspector buttons (`InspectorAction`), carried out by `EditorModel.press`; a double
+  click on a group node presses Edit Group through S5b's recogniser; ⌘↓/⌘↑ enter and leave. Group Input/Output draw a "+"
+  socket (a `NodeShape` socket named `GroupNaming.plusSocket`); a wire between it and another socket exposes a socket
+  (`EditorModel+Expose`). `GroupPanel` (`EditorModel.groupPanel`, `GroupPanelView`) is the inspector's definition part;
+  the library's "Groups" section carries a group by the key `GroupLibraryEntry.key` through the library's one gesture.
+  `NodeClipboard.definitions` carries the definitions copied group nodes use.
   The selection is `canvasSelection` (`CanvasSelection`: nodes, and comments once sub-project B lands); `selection`
   is its nodes, and assigning it replaces the whole selection. Every gesture and key goes through
   `EditorModel+Selection` (`select(_:mode:)` with `SelectionMode`: none replaces, ⇧ adds, ⌘ toggles; `allItems`,
@@ -127,7 +145,10 @@ Module boundaries (dependency order):
   `@MainActor @Observable AppModel` owns the open document's parts (document, editor, graph input, viewport; replaced
   together on New and Open), turns results into `ViewportItem`s (`SceneBuilder`) and `HandleSpec`s into
   `ViewportHandle`s (`HandleBuilder`), turns viewport events into graph commands (picking writes Edges by Tag rules),
-  and opens, saves and exports. `AppInput` installs the window's input once and forwards to the current document.
+  and opens, saves and exports. Inside a group `AppModel` reads the level through `editor.graph`/`levelResults`: Selected
+  node previews the level's selected node, handles and picking work there, and a pick is written through
+  `GraphContent.relativeToLevel`; Final preview and export stay on the top level. Sketch mode is top-level only
+  ("Edit sketch" inside a group says so). `AppInput` installs the window's input once and forwards to the current document.
   `MetalCreatorApp` is the executable (`OCCTKernel`). It makes the app's `ThemeStore` (`AppThemes.store()`: user
   defaults, `~/Library/Application Support/MetalCreator/Themes`) and its `ThemeEditorModel`, and opens the window on
   `AppWindowRoot`: `AppRoot` with the theme editor (`ThemeEditorDock`, a floating glass panel at the top right) over
````

**Modify** `docs/superpowers/roadmap.md` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/docs/superpowers/roadmap.md b/docs/superpowers/roadmap.md
index aa07e87..3b589e0 100644
--- a/docs/superpowers/roadmap.md
+++ b/docs/superpowers/roadmap.md
@@ -30,7 +30,7 @@ Status key: ✅ done · 🔄 in progress · ⏳ ready to start · 🔒 blocked (
 | 7 | Patterns, fields, nested data trees, surface textures, lattices | 💬 | After the slice |
 | 8 | Variants and versions UI | 💬 | Graph parameters already model variants |
 | — | Groups: model and evaluation (C1) — group definitions saved in the file (format 5), group nodes through `NodeRegistry.makeNode`, a definition's graph evaluated per instance under scoped node IDs (tags stay put per instance and across definition edits), Group / Ungroup / Make Unique and definition edits as single undo steps, ⌘G / ⇧⌘G on the top level (spec `2026-10-09-selection-groups-comments-design.md` §4–§5, plan `2026-10-09-groups-core.md`, Errata (C1)) | ✅ code done | Multi-select (A); comments (B) add their keys under format 5 |
-| — | Groups: editor (C2) — the group node's look, entering a group (double-click, ⌘↓, Edit Group), breadcrumbs and ⌘↑, per-level pan and zoom, Group Input/Output + sockets, the group inspector, the library's Groups section, the viewport inside a group (spec §6; a pick made there is written relative to the level shown, as `GroupScopes.identity` names it), the clipboard carrying the definitions pasted group nodes use, merged by content (spec §9), and inner node states from `DocumentModel.innerResults` | ⏳ after C1 | MetalUI gap GI-a (canvas double-click, synthesised until MetalUI C16) |
+| — | Groups: editor (C2) — the group node's look, entering a group (double-click, ⌘↓, Edit Group), breadcrumbs and ⌘↑, per-level pan and zoom, Group Input/Output + sockets, the group inspector, the library's Groups section, the viewport inside a group (spec §6; a pick made there is written relative to the level shown, as `GroupScopes.identity` names it), the clipboard carrying the definitions pasted group nodes use, merged by content (spec §9), and inner node states from `DocumentModel.innerResults` | ✅ code done (plan `2026-10-09-groups-editor.md`, Errata (C2)); human checks GR pending | MetalUI gap GI-a (canvas double-click, synthesised until MetalUI C16). Follow-ups: sketches inside a group can't be edited yet, and the graph canvas has no context menu for Group |
 | — | Packaging: bundle OCCT dylibs into a signed `.app` | ✅ code done; human checks P pending | Spec §11, Errata (Packaging); `scripts/package-app.sh`, `docs/packaging.md`. Ad hoc by default, Developer ID via `METALCREATOR_SIGN_IDENTITY`; notarization is manual; no icon yet; needs macOS 27 while Homebrew's bottles do; MetalUI gap P-a fixed (MetalUI 67a579e; its notices are bundled) |
 | — | C7 adoption: swap the viewport's, the graph panel's and the app's input stopgaps for MetalUI C7's APIs once `feat/input-apis` merges (lists in the carry-over note, From M4, From M5, From M6) | ✅ viewport (human checks VC pass); graph panel and app ✅ merged 2026-10-09 (human checks GI pending) | MetalUI decisions file `docs/superpowers/2026-10-08-input-apis-decisions.md` |
 | — | Naming: picks on merged faces — an Edges by Tag pick on a face a union merged must survive one operand changing (spec §8's polygon swap, Errata (M6)); needs the split-edge count handled too, not only a minimal tag subset | ✅ code done (plan `2026-10-09-naming-merged-faces.md`, Errata (naming: merged faces)): a key matching nothing is retried narrowed (`EdgeKey.narrowed`), drift counts runs as well as edges (`EdgePick.runCount`, no format bump) | `BracketAcceptanceTests+PolygonSwap` (flipped: Edges by Tag resolves with no warning; the Chamfer's failure was the invalid-blends row, now done), `BracketAcceptanceTests+MergedFaces` |
````

**Modify** `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md b/docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md
index c8a3dcd..e5af466 100644
--- a/docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md
+++ b/docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md
@@ -246,3 +246,51 @@ Plan `2026-10-09-groups-core.md`.
   be grouped: a node outside the selection both takes from them and feeds them."): the group node would be wired in a
   cycle, which wiring refuses. Applies at a definition's path too.
 - §2 The file format went 4 → 5 here; comments (B) add their keys under 5.
+
+## Errata (C2)
+
+Plan `2026-10-09-groups-editor.md`.
+
+- §6 "Entering" and "Breadcrumbs": a level is the group nodes entered from the top level (`EditorModel.levelPath`, each
+  by its ID in the graph before it), not a definition, so a definition used twice shows the entered instance's states
+  (`DocumentModel.innerResults` is keyed by instance path). `EditorModel.graph` is the level's graph and
+  `EditorModel.edit(_:)` addresses its path; the document's parameters stay on the top level and show at every level.
+  Each level remembers its pan and zoom while the document is open (not saved, not undone); a level entered for the
+  first time frames its nodes. Undo or Redo that removes the group node entered drops the panel to the level around it
+  (`refreshLevel()`).
+- §6 "Entering": Edit Group, Make Unique and Ungroup are the group node's inspector buttons (`InspectorAction.editGroup`,
+  `.makeUnique`, `.ungroup`, declared by `GroupNode.inspector`), carried out by the graph panel itself and never
+  recorded for the app shell. S5b's double-click recogniser presses the first of `doubleClickActions` ([.editSketch,
+  .editGroup]) a node's inspector has, and now runs after the click it ends on, so a click that enters a group
+  doesn't select its group node inside. ⌘↓ and ⌘↑ are `GraphKeyCommand.enterGroup`/`.exitGroup`.
+- §6 "Inside": the "+" is a socket named `GroupNaming.plusSocket` ("+", reserved: no socket of a definition may have
+  it) at the end of Group Input's outputs and Group Output's inputs. A wire dragged between it and another socket,
+  either way round, exposes the socket (`GroupCommands.exposeOutput`, `exposeInput`): the new output or input is named
+  after the socket and typed from it, an input keeps its target's unit, range and default, and the socket and its wire
+  are one command, so one undo step. Any other pairing with a "+" is refused with a hint.
+- §6 "Inside": Group Input and Group Output cannot be copied, duplicated or deleted (Delete with only them selected
+  says why); they can be moved.
+- §6 "Inspector": the definition part shows name, accent and "Used N times" ("Used 1 time") for a group node, Group
+  Input or Group Output; the socket list (rename, move up or down, remove) for Group Input and Group Output. Removing
+  a socket a group node has wired is refused naming that node (`GroupCommands.removeSocket`).
+- §6 "Library": the "Groups" section lists the definitions that match the library's search; a group row carries the
+  key "group:<uuid>" through the library's one gesture in place of a node type's ID. A definition no group node uses
+  shows Delete. Placing a group inside itself is refused ("A group can't contain itself.").
+- §6 "Viewport": while a level is shown the document evaluates all of it (`DocumentModel.inspectedLevel`,
+  `Evaluator.evaluate(_:definitions:demand:inspecting:)`), so every inner node has a state in `innerResults` and
+  Selected node previews any of them, also one nothing reads; a node asked for this way never changes its group
+  node's result. Handles and picking read the level's graph and results (a pick starts from a node of the level, never
+  a top-level endpoint or Group Output). A pick is written through
+  `GraphContent.relativeToLevel`, which renames the tags naming this instance's identities to the names the
+  definition uses; tags naming nodes outside the level stay as they are. A pick under way is cancelled by showing
+  another level. Final preview shows the Output nodes of the top level whichever level is shown. An open sketch
+  holds the level shown: entering or leaving does nothing until it closes (`EditorModel.isLevelLocked`).
+- §6 "Viewport": editing a sketch inside a group is not supported yet: "Edit sketch" there says so. Sketch mode reads
+  the top level's graph throughout, and sub-project S5c rewrites it.
+- §9 "Clipboard": `NodeClipboard.definitions` holds every definition the copied group nodes use, however deep
+  (`GroupMerge.definitions(used:in:)`). On paste (`GroupMerge.plan(importing:into:)`) a definition that some
+  definition of the document equals, ignoring ID and name (accent, sockets and inside), is reused, whatever its ID or
+  name (the original, a rename of it, or the copy an earlier paste added, so pasting the same clipboard twice adds
+  one copy at most), one the document has no match for is added as it is, and one whose ID is taken by other content,
+  or whose name is taken, comes in as a copy "Name (imported)" (a fresh ID when the ID was taken), with the pasted
+  group nodes, and any definition placing it, retargeted. The additions and the nodes are one undo step.
````

**Modify** `docs/verification/human-checks.md` (apply this diff with `git apply`, or make the same edits by hand):

````diff
diff --git a/docs/verification/human-checks.md b/docs/verification/human-checks.md
index b96f8d4..4b08912 100644
--- a/docs/verification/human-checks.md
+++ b/docs/verification/human-checks.md
@@ -674,3 +674,60 @@ at the bottom too.
 - [ ] **MS-8 Draw order.** Overlap three nodes, select the two at the back: they draw above the third, and a click
   where all three overlap selects the topmost drawn one. Docked at the bottom too. Pinned:
   `selectedNodesDrawLastAndAreHitFirst`. **Observed:**
+
+## Group GR — groups: the editor (C2)
+
+**Status: PENDING.** Plan `2026-10-09-groups-editor.md`, spec `2026-10-09-selection-groups-comments-design.md` §6 and
+its Errata (C2). The tests pin the model and the frames; these check the gestures through a real window. Run
+`swift run MetalCreatorApp` on a saved bracket, docked at the bottom, then GR-2 and GR-4 docked left too. Group the
+plate and its extrude (select both, ⌘G) first.
+
+- [ ] **GR-1 Look.** The group node has a header in its accent (purple) titled with the definition's name, and two
+  rings around it, a thick one and a thin one inside. Change the accent in the inspector: header and rings follow.
+  Switch the theme (View ▸ Theme): they follow. Select it: the outer ring thickens. Pinned: `GroupLookTests`.
+  **Observed:**
+- [ ] **GR-2 Entering and leaving.** Double-click the group node (two quick clicks): the panel shows its inside,
+  framed, nothing selected, the header reads "Graph › Group" and Group Input and Group Output flank the nodes. Click
+  "Graph" in the header: back out. Select the group node and press ⌘↓: in again, with the pan and zoom you left; ⌘↑:
+  out. Pan and zoom inside, go out and in: they are as you left them; the top level's are too. Select the group node
+  and press "Edit Group" in its inspector: in. Group something inside and go in twice: "Graph › Group › Group 2", and a
+  click on "Group" goes up one level. ⌘↓ with a plain node selected does nothing. Pinned: `EditorLevelTests`,
+  `EditorGroupEntryTests`. **Observed:**
+- [ ] **GR-3 Editing inside.** Inside, move a node, wire two nodes, add one from the library and one with Space, delete
+  one: each is one ⌘Z. Add an Output node: "An Output node can't go in a group." Select everything and press Delete:
+  Group Input and Group Output stay. ⌘C and ⌘V inside: the nodes copy, the boundary nodes don't. The part in the
+  viewport follows every edit. ⌘Z until the group itself is undone while inside: the panel falls back to the top
+  level. Pinned: `EditorLevelTests`, `EditorGroupClipboardTests`, `EditorLevelReviewTests`. **Observed:**
+- [ ] **GR-4 The + sockets.** Inside, drag from a node's output onto Group Output's "+": a new output appears on
+  Group Output named after the socket, wired, and the group node outside has it too; one ⌘Z removes both. Drag from
+  Group Input's "+" onto an unwired input: a new input, wired, with the target's default; one ⌘Z removes it. Drag the
+  wire from the node's socket to the "+" instead of the other way: the same. Drag an output onto Group Input's "+":
+  the hint appears and nothing changes. Pinned: `ExposeSocketTests`. **Observed:**
+- [ ] **GR-5 The inspector.** Select the group node: name, accent, "Used 1 time", Edit Group, Make Unique, Ungroup, and
+  its inputs. Rename it (Return, or click away): its nodes and the library follow. Duplicate it (⌘D): "Used 2 times".
+  Make Unique on the copy: it is named "<name> 2" and the original is "Used 1 time". Ungroup: its nodes come back
+  selected. Inside, select Group Output: its sockets are listed; rename one (the wire outside follows), move one up
+  and down, remove an unwired one. Remove a wired one: the message names the group node and nothing changes. Pinned:
+  `EditorGroupInspectorTests`. **Observed:**
+- [ ] **GR-6 The library.** The library ends with a "Groups" section listing each definition. Click one: another
+  instance appears in view. Drag one onto the canvas: it lands where dropped. Search for part of a name: the list
+  filters. Inside a group, click that group's own row: "A group can't contain itself." Delete both group nodes of a
+  definition: its row offers Delete, which removes it (⌘Z brings it back). Pinned: `LibraryGroupsTests`.
+  **Observed:**
+- [ ] **GR-7 The viewport inside.** With Final preview, enter the group: the whole part stays. Switch to Selected node
+  and click an inner node: its solid shows alone; click a node nothing reads (add one and wire only its input): it
+  shows too. Select a Fillet or Extrude inside: its handle appears, and dragging it edits the definition as one ⌘Z;
+  with two instances, both parts change. Pick edges in view on a rule inside: Done writes the rule, the Fillet works,
+  and the second instance's Fillet works too. Showing another level during a pick cancels it. "Edit sketch" on a
+  Sketch node inside says it can't yet. Open a sketch on the top level, then press ⌘↓ on a group node, or click a
+  breadcrumb: nothing happens. Pinned: `GroupViewportTests`. **Observed:**
+- [ ] **GR-8 Clipboard.** Select the group node, ⌘C, Ungroup (the definition goes), ⌘V: the group node returns with its
+  definition. Copy it, enter the group, edit something inside, go out and ⌘V: a second definition "<name> (imported)"
+  appears, as it was copied; the node already there still uses the edited one. ⌘V again: another node using the same
+  "(imported)" definition, no third one. Rename the definition and paste a copy made before: no new definition.
+  Pinned: `EditorGroupClipboardTests`, `GroupMergeTests`.
+  **Observed:**
+- [ ] **GR-9 Inner states.** Inside, set an Extrude's distance to -1: its header shows the error badge, and out on the
+  top level the group node fails with "<name> › Extrude: …". Fix it: both clear. A node inside that nothing reads and
+  that fails shows its badge and leaves the group node alone. Pinned: `InspectedLevelTests`, `EditorLevelTests`.
+  **Observed:**
````

- [ ] **Step 3: Run the task's tests**

Run: `swift test --filter 'EditorLevelReviewTests|GroupPickInstancesTests'`

Expected: every test passes (no "recorded an issue").

- [ ] **Step 4: Lint and run the whole suite**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-editor-test.log`.

Expected: exit code 0; `grep -cE 'recorded an issue|failed after' /tmp/groups-editor-test.log` prints 0; `grep -c 'Test run with' /tmp/groups-editor-test.log` prints 11; the counts on those lines add up to **1753** (master + 110). No new compiler warning.

- [ ] **Step 5: Commit**

```bash
git add 'CLAUDE.md' 'Tests/CreatorAppTests/GroupPickInstancesTests.swift' 'Tests/CreatorEditorTests/EditorLevelReviewTests.swift' 'docs/superpowers/roadmap.md' 'docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md' 'docs/verification/human-checks.md'
git commit -m "docs(groups): C2 in CLAUDE.md, roadmap, spec errata, human checks GR; review pins"
```

---

## Self-review

**Spec coverage** (groups spec §6, with §5, §8, §9 and Errata (C1)):

- §6 *Look*: header = definition name, doubled accent border — Task 7 (`GroupLookTests`); the accent follows the theme (`Palette.accent`) — Task 7.
- §6 *Entering*: double click reusing S5b's recogniser (`doubleClickActions`, no second one) — Task 5 (`aDoubleClickOnAGroupNodeEntersItAndSelectsNothingInside`, `aSlowOrWanderingDoubleClickDoesNotEnter`); ⌘↓ — Task 5; "Edit Group" in the inspector — Tasks 1, 5 (`theInspectorButtonsEnterMakeUniqueAndUngroup`).
- §6 *Breadcrumbs*: "Graph › Rib › Hole pattern", a click on a level, ⌘↑ — Tasks 4, 5, 8; each level remembers pan and zoom, not undone — Task 4 (`eachLevelRemembersItsPanAndZoom`); the selection clears on changing level — Task 4.
- §6 *Inside* (editing): the graph commands addressed to the level's path, one undo step each — Task 4 (`editsInsideLandInTheDefinitionAsOneUndoStep`, `wiringInsideAGroupGoesToItsDefinition`), Task 5 (group commands at the level); the + sockets on Group Input and Output, one undo step each — Tasks 3, 7 (`ExposeSocketTests`).
- §6 *Inspector*: name, accent, "Used N times", Edit Group, Make Unique, Ungroup — Tasks 1, 5, 9; the socket list with rename, reorder, remove, and removing a wired socket refused naming the instance — Task 9 (`aWiredSocketCantBeRemovedAndTheRefusalNamesTheInstance`).
- §6 *Library*: the "Groups" section, a click or drag places another instance, Delete for a definition with no instances — Task 10.
- §6 *Viewport*: Selected node, handles and picking work on the level shown, Final preview shows the whole part — Task 11 (`finalPreviewStillShowsTheWholePartInsideAGroup`, `selectedNodePreviewShowsTheSelectedNodeOfTheLevel`, `aHandleInsideAGroupEditsTheDefinitionAsOneStep`); a pick made inside is written relative to the level, as `GroupScopes.identity` names it — Tasks 1, 11, 12.
- §9 *Clipboard*: definitions travel with the pasted group nodes, merged by content — Tasks 3, 6; boundary nodes are never copied — Task 6.
- Roadmap C2 row, *inner node states from `DocumentModel.innerResults`* (badges and messages) — Tasks 2, 4, 7 (`result(of:)`, `NodeView` state); a failing inner node's message reaches the group node as C1 builds it, and the inspector header shows an inner node's own state (`levelResults`).
- §9 *Testing*: model tests for every command and refusal, undo of each, render tests for group borders and breadcrumbs (Tasks 7, 8), human checks GR (Task 12). Not done, by decision: sketch editing inside a group (User decision 1), a mouse way to Group (User decision 3).

**Placeholders:** none; every step has its code, command and expected output.

**Type consistency:** the code blocks are the verified files. Names used across tasks: `GraphContent.path(entering:)`, `existingLevels(_:)`, `relativeToLevel(_:levels:)`, `GroupNaming.plusSocket`, `DocumentModel.inspectedLevel`, `Evaluator.evaluate(_:definitions:demand:inspecting:)`, `GroupCommands.exposeOutput(from:on:in:of:registry:)`/`exposeInput(to:from:in:of:registry:)`, `GroupMerge.definitions(used:in:)`/`plan(importing:into:)`/`Plan.additions`/`targets`/`retargeting(_:)`, `EditorModel.enteredGroups`/`levelPath`/`graphPath`/`isInsideGroup`/`rootGraph`/`edit(_:coalescingKey:)`/`result(of:)`/`levelResults`/`breadcrumbs`/`enterGroup(_:)`/`exitGroup()`/`goToLevel(_:)`/`refreshLevel()`, `GraphKeyCommand.enterGroup`/`.exitGroup`, `InspectorAction.editGroup`/`.makeUnique`/`.ungroup`, `NodeClipboard.definitions`, `NodeShape.accent`/`isGroup`, `Palette.accent(_:)`, `GroupPanel`, `GroupLibraryEntry.key`, `PickSession.level`.

**Review Focus:** each of the eight lines has its test in the owning task (named in the list).

**Verified** (2026-10-10, after the review round): all 82 code blocks of this plan applied in order, by a script that parses this file, to a fresh clone of master `4e4be6e` beside a `MetalUI` symlink to `/Users/maxburger/Developer/MetalUI` (at `70e9389`). In that final tree `swift build --build-tests` succeeded with no compiler warning, `swiftlint lint --strict` reported 0 violations in 948 files, and `swift test` exited 0 with no "recorded an issue" or "failed after" line and 11 "Test run with" lines totalling 1753 (190, 65, 184, 139, 122, 151, 83, 247, 31, 377 and 164 tests; master 1643 + 110). The per-task totals in the table above are master plus the tests each task adds; the first revision of this plan ran every task in turn (1649, 1656, 1666, 1678, 1686, 1695, 1706, 1708, 1720, 1731, 1740, 1746), and this round ran only the final tree, so the totals for Tasks 3 to 11 are derived, not run. Mutation checks, each failing exactly the tests named: removing the match by content from `GroupMerge` (the two `GroupMergeTests` and the two paste-twice and rename `EditorGroupClipboardTests` tests); dropping the `isLevelLocked` guard from `enterGroup` (`aLockedLevelCantBeEnteredOrLeft`, `anOpenSketchHoldsTheLevelShown`); dropping the level check on `sources` in `producer(of:)` (`inFinalPreviewAPickStartsFromANodeOfTheLevelShown`); and, from the first revision, making `AppModel.relativeToLevel` return the pick unchanged (`aPickMadeInsideAGroupIsWrittenRelativeToTheLevel`, `aPickMadeInsideOneInstanceChamfersTheOtherToo`). Not verified by a machine: how anything looks or feels in a real window (no screenshots were taken; group GR lists those checks).
