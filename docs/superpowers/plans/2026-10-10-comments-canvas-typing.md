# Comments: Typing on the Canvas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **EXECUTION WAITS FOR MetalUI C9.** This plan builds on MetalUI C9 (key and focus scoping), which is on the branch
> `feat/key-focus` in `../MetalUI` and **not on its `master` yet**. Do not start Task 1 until C9 has merged to MetalUI's
> `master`: Task 3 (`onKeyPress` on a `TextEditor`) and Task 4 (`hoverKeyRegion`) do not compile without it. Before
> starting, re-check every C9 API in "C9 APIs this plan uses" below against the merged code and run the probe in Appendix A
> against it (`../MetalUI` itself is never edited from here).

> **MERGE `master` FIRST.** The named-undo track has merged to `master` (`4dff87b`, "Merge named-undo") since this plan was
> written at `af4d99f`. Before Task 1, in the worktree: `git merge master` (it merges without conflict: see "Files shared
> with other tracks"). After it the base is `master`'s test count (every count below is "master + N", and "master" means
> the merged tree), the comment edit paths already name their steps ("Edit Note", "Edit Frame"), and Task 5's `Modify`
> anchors in `CLAUDE.md`, the roadmap and the human checks are re-read against the merged files (a changed anchor is
> re-anchored, never skipped).
>
> **Tasks 3 and 4 ship together.** After Task 3 alone a focused canvas field still lets keys it declines (⌘⇧N, ⌘G, ⌘D)
> reach the graph through the window's `onInput` fallback; the rule "the canvas's keys cannot act while a canvas field has
> focus" is first true after Task 4. They are separate commits on one branch, but are never merged or released apart.

**Goal:** Edit a note's text or a frame's title in place on the graph canvas: a double click starts it, a `TextEditor` (note)
or `TextField` (title) is drawn over the comment at its canvas position and zoom in both docks, and the edit commits or
cancels without the canvas's keys ever acting while it has focus.

**Architecture:** The edit is model state (`EditorModel.commentEdit`) whose draft rides the model's single `pendingEntry`
slot, so every moment that already commits a typed inspector value commits it too, as one `setNoteText` / `setFrameTitle`
undo step. The views are thin: a `CommentEditorLayer` beside the canvas surface under the canvas's own zoom and pan. The
graph's keys and text focus move onto MetalUI C9's key region (`CanvasSurface` is a `hoverKeyRegion` with one
`onKeyPress`), which is what makes a focused canvas field keep every key.

**Tech Stack:** Swift 6.4 (strict concurrency), SwiftUI-style MetalUI components, Swift Testing, SwiftLint; MetalUI C9
(`hoverKeyRegion`, `onKeyPress`, `KeyPress`).

**Spec:** `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` §7 (comments) and §8 ("Typing comments on the
canvas waits for MetalUI C9 and the canvas double-click"), with its Errata (B: comments) including the CM-a editing note
(this plan adds Errata (B: typing on the canvas)); the roadmap row "Comments: typing on the canvas" in
`docs/superpowers/roadmap.md`; under the parent spec `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`
with all its Errata. Written against master `af4d99f` (2096 tests), replayed on master `4dff87b` (2142 tests, named-undo merged); worktree branch `comments-typing`.

## C9 APIs this plan uses

Read at MetalUI branch `feat/key-focus`, head **`c5df112`** ("feat(kf): lane C", 2026-10-09; merge-base with MetalUI master
`c62d6ba`). The executor re-checks each against the merged code (`git -C ../MetalUI show master:<path>`).

| API / behaviour | Where (at `c5df112`) | Used by |
|---|---|---|
| `StyledElement.hoverKeyRegion(_ isEnabled: Bool = true) -> Self`: with nothing focused, keys go to the key region under the pointer; a primary press in it clears a field's focus unless it lands on a text field (KF-D, KF-E item 5); a press outside every region resigns nothing (KF-G) | `Sources/MetalUI/HoverKeyRegion.swift`; `Window.focusOnPress`, `keyChain` | Task 4 (`CanvasSurface`) |
| `StyledElement.onKeyPress(phases:action:)`, `onKeyPress(keys:phases:action:)`, `onKeyPress(_:action:)` (`action` returns `KeyPress.Result`; runs before a focused field's own editing keys, outermost first, KF-B, KF-C) | `Sources/MetalUI/KeyPress.swift` | Tasks 3, 4 |
| `KeyPress` (`key: KeyEquivalent`, `characters: String`, `modifiers: EventModifiers`, `phase: KeyPress.Phases`; made by MetalUI only), `KeyPress.Phases` (`.down`, `.repeat`), `KeyPress.Result` (`.handled`, `.ignored`) | `Sources/MetalUI/KeyPress.swift` | Tasks 3, 4 |
| `KeyEquivalent.return`, `.escape` (on MetalUI master already) | `Sources/MetalUI/KeyboardShortcut.swift` | Task 3 |
| A key an enabled app command binds (`AppCommands`: ⌘N ⌘O ⌘S ⇧⌘S ⌘E ⇧⌘E ⌘Z ⇧⌘Z) is declined by `onKeyPress` and runs the command (KF-X) | `Window.dispatchKeyPress` | Task 4 (the graph's ⌘Z is the menu's) |
| ⌘↩ is not an editing key of a `TextEditor`: an `onKeyPress(keys: [.return])` handler for it runs before the editor, plain Return still breaks the line (KF-Z item 2) | `TextEditing.handleKey` | Tasks 3 (canvas editor, inspector box) |
| The key chain is the focus chain while something is focused (so a focused canvas field keeps every key, and a handler on its sibling key region never hears them); the chain's `keyContext`s feed the window keymap (KF-D, KF-U) | `Window.keyChain` | Tasks 3, 4 |
| A `FocusState` written in `onAppear` focuses a freshly built, focusable `TextEditor` / `TextField` (SwiftUI's idiom; `IX-J`, not a C9 API, but probed with C9) | `FocusState.swift` | Task 3 |

Not used: `focusable(_:interactions:)`, `onGeometryChange`, `TimelineView`, `KeyboardModifier`. Anything above that is missing or
does something else in the merged code is a **new MetalUI gap**: log it in `docs/metalui-gaps.md`, never work around it.

**New gaps this plan logs** (Task 5; verbatim in the plan's return and in `docs/metalui-gaps.md`): CT-a (a press outside
every key region resigns no focus, and nothing asks it to without taking over key routing) and CT-b (no way to set a text
field's selection or caret). The existing S5-b (canvas double click, MetalUI C16) stays: the recogniser is still S5b's.

**Out of scope** (YAGNI; each is a follow-up, not a gap): starting an edit from the keyboard (Return or F2 on a selected
comment); the viewport adopting C9 (M4-a, and `AppInput`'s pointer veto and `AppModel.releaseTextFocus` with it); the
palette's ↑/↓ moving onto `onKeyPress` (M5-h); editing a comment inside a sketch; any change to `setNoteText`,
`setFrameTitle` or the undo step names (the named-undo track's).

## Global Constraints

- Target macOS 26.0 or later, Swift 6.4 tools, strict Swift concurrency; Swift Testing (never XCTest); `@MainActor @Observable` models; behaviour in models, views thin.
- One type per file; no force unwraps, no force `try`; no `DispatchQueue`/GCD; `Task.sleep(for:)` only; modern Foundation and `FormatStyle` (no `String(format:)`, no `DateFormatter`).
- SwiftUI-style rules: `foregroundStyle`, `clipShape(.rect(cornerRadius:))`, no `onTapGesture` unless a location or count is needed, no `AnyView`, Dynamic Type text (`.font(.callout)`), `ForEach` over a sequence, never `Array(x.enumerated())`.
- `swiftlint lint --strict` reports zero violations; give any `swiftlint:disable` a reason (this plan needs none).
- MetalUI gaps go in `docs/metalui-gaps.md` (the entry and the summary-table row) and are **never worked around**; `../MetalUI` is never modified and `Package.swift`'s MetalUI path is never edited.
- Spec §7: "Editing: with one comment selected, the inspector edits its text (multi-line; commits on focus loss or ⌘↩) or title (commits on Return; empty refused)"; "every change is one undo step ("Add Note", "Edit Note", "Add Frame", "Move", "Resize", "Delete")"; "No shadows (PERF-a); views stay cheap (PERF-b)"; "a frame only on its title bar and a 6 pt inner edge band"; comments never affect evaluation, their edits don't re-evaluate.
- Spec Errata (B: comments): an empty or blank title is refused ("A frame needs a title.") and the field shows the old one.
- Double click: S5b's recogniser, `EditorModel.doubleClickInterval` 0.4 s and `doubleClickSlop` 4 pt, timed by the injectable `EditorModel.now`; it runs after the click it ends on.
- The commit path is `EditorModel.setNoteText(_:to:)` / `setFrameTitle(_:to:)` and nothing else: no view or new code performs a graph command for a comment edit itself (the named-undo track names the steps there).
- A full `swift test` passes only if the exit code is 0, no line says "recorded an issue" or "failed after" (Swift Testing prints glyphs, not ✘), and 11 "Test run with" lines appear.

### Verifying a task

Run from the worktree, after each task:

```bash
swift build --build-tests 2>&1 | grep -E '\.swift:[0-9]+:[0-9]+: warning'   # no output (the linker's OCCT "built for newer version" warnings are old)
swift test > /tmp/typing-test.log 2>&1; echo "exit $?"                      # 0
grep -cE 'recorded an issue|failed after' /tmp/typing-test.log              # 0
grep -c 'Test run with' /tmp/typing-test.log                                # 11
grep -E 'Test run with' /tmp/typing-test.log | awk '{s+=$5} END{print s}'   # the task's count: "master + N"
swiftlint lint --strict                                                     # 0 violations
```

## Review Focus

The spec says what comments do; it is silent on these, and a person editing text in place will meet each. The test that pins
each is named in its task.

1. **An empty, blank or multi-line title.** Return on a cleared title (or leaving the field) must refuse with "A frame needs a title." and bring the old title back; a line break pasted into the one-line field must become a space, not a two-line title. (Task 1: `anEmptyTitleIsRefusedAndTheOldOneStays`, `aLineBreakPastedIntoATitleBecomesASpace`.)
2. **Docked left, and every zoom.** The field must lie exactly over the note or the title bar in the left dock's transposed drawing and at 50 %, 100 % and 200 %, and a double click must work there too. (Task 1: `theLeftDockTransposesTheField`; Task 2: `itWorksInBothDocksAtEveryZoom`; Task 3: `CommentEditorRenderTests`.)
3. **The comment disappears or the canvas goes away mid-edit.** Undo of its creation, a delete, or hiding the panel must not write into nothing or leave a stale pending edit. (Task 1: `aCommentThatIsGoneHasNoFieldAndNothingToCommit`, `hidingThePanelCommitsTheEdit`.)
4. **Leaving a group mid-edit.** The text must land on the level it was typed on, not the one shown next. (Task 1: `leavingAGroupCommitsTheEditToThatLevel`.)
5. **Near-miss double clicks.** Two slow, distant, modified, interrupted or handle clicks, or two different comments, must never open an editor, and a frame's edge band is not its title bar. (Task 2: `clicksThatArentADoubleClickDoNothing`, `onlyAFramesTitleBarCounts`.)

## Files shared with other tracks

The named-undo track (`../MetalCreator-undo`, branch `named-undo`) gave every undo step a name through `DocumentModel.perform`
and `UndoStack`, and touched the comment editing code to name "Edit Note" / "Edit Frame". **It has already merged to
`master` (`4dff87b`), so this plan is the side that merges second:** it merges `master` in before Task 1, and keeps what
named-undo put there. It commits only through `setNoteText` / `setFrameTitle`, so the names come along with no change here.
The comparison below is `git diff af4d99f master` over every file this plan edits; the hunks are far apart, so the merge is
textual and clean.

| Shared file | Who touches what | What this plan (the side that merges **second**) must keep |
|---|---|---|
| `Sources/CreatorEditor/EditorModel+CommentInspector.swift`, `EditorModel+CommentCreation.swift` | named-undo: `commitComment(_:named:)`, `UndoName.editNote` / `.editFrame` / the add names. This plan **does not edit** either file. | Nothing to resolve. Keep `commitCommentEdit`'s route through `setNoteText` / `setFrameTitle` (never perform commands from `EditorModel+CommentEditing`), so canvas edits carry the names. |
| `Sources/CreatorEditor/EditorModel+Levels.swift` (`edit(_:coalescingKey:name:)`; one `lastNodeClick` line here, line 104) | named-undo: `edit` gained `name:`. This plan changes only `lastNodeClick = nil` to `lastClick = nil`. | Keep both: `lastClick = nil` and the `name:` parameter. |
| `Sources/CreatorEditor/EditorModel+Pointer.swift` | named-undo: `name: UndoName.move` / `.resize` / `.duplicate` / `.disconnect` arguments to `edit` and `insert` (3 hunks, lines 132-168). This plan (Task 2): the two `lastNodeClick` reads (lines 31, 35) become `lastClick`, and one comment. | Keep both: `lastClick` and every `name:` / `named:` argument. The hunks are 100 lines apart. |
| `Sources/CreatorEditor/EditorModel.swift` | named-undo does not touch it. This plan: the `commentEdit` property, the line in `setDock`, and (Task 2) the `lastNodeClick: NodeClick?` property becomes `lastClick: RecentClick?`. | Keep all three; the property sits next to `pendingEntry`. |
| `Sources/CreatorEditor/EditorModel+PendingEntry.swift` | named-undo does not touch it. This plan changes `notePendingEntry`. | Keep the `commentEdit` check before the assignment. |
| `Tests/CreatorEditorTests/CommentEditingTests.swift` (named-undo: one `named: UndoName.paste` argument), `EditorUndoNameTests.swift` (named-undo's new file, which already asserts "Edit Note" for the inspector's path) | This plan edits neither: it adds only new test files. | Keep named-undo's. In `typingThenCommittingIsOneUndoStep` (Task 1) assert `editor.document.undoName == "Edit Note"` and, in the frame-title test, `"Edit Frame"` (the plan's code has both assertions). |
| `CLAUDE.md`, `docs/superpowers/roadmap.md`, `docs/metalui-gaps.md`, the comments spec's Errata, `docs/verification/human-checks.md` | both append and edit rows (named-undo: group NU, its roadmap row, a spec Errata line). | Keep both sides' text. In the roadmap, the "Named undo steps" row stays and the "Comments: typing on the canvas" row (this plan) says code done. |

## User decisions (defaults this plan implements)

These are product behaviours the spec leaves open. Each is written for its recommended default; the alternative is a small change.

1. **Scope of the graph's keys.** Recommended (a, implemented): the graph's keys (Delete, arrows, Space, ⌘A, F, ⌘C ⌘X ⌘V ⌘D, ⌘G, ⌘⇧N, ⌘⇧C, Esc, Tab) act only while the pointer is over the canvas **and nothing is focused**; a focused field anywhere keeps every key. The canvas never holds focus itself (`CanvasSurface` has no `focusable`; a canvas press leaves `focusedElement == nil`, which Appendix A asserts), so after a click on the canvas, moving the pointer to the inspector or the viewport stops Delete, arrows, ⌘A and the rest. Alternatives: (b) make the whole graph panel (header, library, canvas) the key region; (c) keep the keys window-wide and gate them with a model flag while a canvas field is open, which is the stopgap the brief forbids; (d) make the canvas `focusable(true, interactions: .edit)`: a canvas press focuses it, and the keys then follow focus instead of the pointer, so Delete and the arrows keep working after a click wherever the pointer goes, which is closer to today's window-wide behaviour. Costs of (d): a canvas press takes focus from the viewport and the inspector's fields (so the viewport's F, + and − reach the viewport only once focus is cleared), Tab traversal now stops on the canvas, a focus ring or its absence must be designed, and the C9 behaviour of a focused non-field element under `hoverKeyRegion` has to be re-probed (Appendix A does not cover it).
2. **A press on inert chrome while editing** (the glass padding, header gaps, the inspector's empty areas). Recommended (implemented): it does not end the edit (gap CT-a); a press on the canvas, the viewport, any selection change, undo, save and export do. Alternative: a key region on the whole panel or the app root (the root also changes key routing).
3. **An empty title.** Recommended (implemented): the editor closes, the old title returns and "A frame needs a title." shows, as in the inspector. Alternative: keep the editor open with the message so it can be fixed.
4. **Where the caret opens.** Implemented: as MetalUI opens a field focused from code, caret at the start, nothing selected (gap CT-b). Recommended once MetalUI offers a selection API: select the whole title, caret at the end of a note.
5. **Pointer-less ⌘⇧N after typing, Tab while typing, ⌘Z while typing.** Implemented: the field keeps them (Tab moves focus, ⌘Z undoes the field's own typing: MetalUI's field keys run before the app's menu command). No alternative proposed.
6. **Hiding the panel mid-edit** (Tab with the pointer off the canvas, the header's hide button). Recommended (implemented): the edit commits (`setDock(.hidden)`; `hidingThePanelCommitsTheEdit`). Alternative: cancel it, as Esc does, so a hidden panel never lands text.
7. **A line break in a title** (pasted into the one-line field). Recommended (implemented): it becomes a space (`aLineBreakPastedIntoATitleBecomesASpace`). Alternatives: the first line only, or refuse the whole commit like an empty title.
8. **A dock change mid-edit** (the header's Left / Bottom buttons). Recommended (implemented): the edit continues, the field follows the comment into the other drawing and the draft is kept (`changingTheDockMidEditMovesTheFieldAndKeepsTheDraft`). Alternative: commit on any dock change, as hiding does.
9. **Typing while a sketch is open.** Recommended (implemented): allowed. The graph panel stays on screen in sketch mode (only the level is locked, `isLevelLocked`), comments are no part of the sketch, and Add Note already works then (`typingWorksWhileTheLevelIsLocked` pins the model; the app's `editSketch` guard covers only a node's double click). Alternative: refuse `beginEditing` while `AppModel.sketch != nil`, which needs a model flag the app sets, as `isLevelLocked` is.

## File structure

| File | Task | Responsibility |
|---|---|---|
| `Sources/CreatorEditor/CommentEdit.swift` | 1 | The edit: id, kind, original, draft, owner |
| `Sources/CreatorEditor/CommentEditor.swift` | 1 | The edit plus its field's rectangle (display canvas points) |
| `Sources/CreatorEditor/EditorModel+CommentEditing.swift` | 1 | `beginEditing`, `commentDraftChanged`, `commitCommentEdit`, `cancelCommentEdit`, `commentEditor` |
| `Sources/CreatorEditor/ClickTarget.swift`, `RecentClick.swift` | 2 | What a double click pairs on; the remembered click (replaces `NodeClick`) |
| `Sources/CreatorEditor/EditorModel+DoubleClick.swift` | 2 | The recogniser, now over nodes, notes and frame title bars |
| `Sources/CreatorEditor/CommentKeys.swift` | 3 | ⌘↩ commits a note |
| `Sources/CreatorEditor/CommentEditorField.swift`, `CommentEditorLayer.swift` | 3 | The `TextEditor` / `TextField` and the layer under the canvas's zoom and pan |
| `Sources/CreatorEditor/CanvasSurface.swift`, `GraphCanvas.swift` | 3, 4 | The canvas's input surface (a key region from Task 4) beside the editor layer |
| `Sources/CreatorEditor/CommentTextEntry.swift` | 3 | The inspector's note box commits on ⌘↩ |
| `Sources/CreatorEditor/GraphPanelInput.swift` | 4 | `keyPressed`, `handleKey`; the palette's stopgaps only; no `releaseTextFocus` |
| `Sources/CreatorEditor/GraphTab.swift` | 4 | Deleted |
| `Sources/CreatorApp/AppModel.swift`, `AppInput.swift` | 4 | One line; a comment |
| Tests | 1 to 4 | `CommentTypingTests`, `CommentDoubleClickTests`, `CommentKeysTests`, `CommentEditorRenderTests`; edits to `GraphPanelInputTests`, `SelectionKeyTests`, `NudgeTests`, `AppInputTests`, `ViewportGlueTests` |
| Docs | 5 | `CLAUDE.md`, roadmap, `docs/metalui-gaps.md`, the spec's Errata, human checks (group CT) |

---

### Task 1: The editing state in `EditorModel`

Everything testable about typing on the canvas lives here: which comment is being edited, the draft, and how the edit
ends (commit, cancel, refused). No view yet. The edit rides the model's existing `pendingEntry` slot, so every moment
that already commits a typed inspector value (a canvas press, a selection change, undo, save, export, close) commits a
canvas edit too, and there is never more than one pending entry.

**Files:**
- Create: `Sources/CreatorEditor/CommentEdit.swift`
- Create: `Sources/CreatorEditor/CommentEditor.swift`
- Create: `Sources/CreatorEditor/EditorModel+CommentEditing.swift`
- Modify: `Sources/CreatorEditor/EditorModel.swift` (one stored property; `setDock` commits an edit when the panel hides)
- Modify: `Sources/CreatorEditor/EditorModel+PendingEntry.swift` (`notePendingEntry`)
- Test: `Tests/CreatorEditorTests/CommentTypingTests.swift`

**Interfaces:**
- Consumes: `EditorModel.setNoteText(_:to:)`, `EditorModel.setFrameTitle(_:to:)` (the existing commit paths; they stay the only
  place a comment's text or title reaches the graph, so the named-undo track's step names come with them),
  `PendingEntry(owner:text:textCommit:)`, `EditorModel.commitPendingEntry()`, `CommentLayout.titleBar(of:)`.
- Produces (later tasks rely on these exact names):
  - `struct CommentEdit: Equatable, Sendable { enum Kind { case noteText, frameTitle }; var id: CommentID; var kind: Kind; var original: String; var draft: String; var owner: UUID }`
  - `struct CommentEditor: Equatable, Sendable { var edit: CommentEdit; var rect: CanvasRect }`
  - `EditorModel.commentEdit: CommentEdit?` (`public internal(set)`, observable)
  - `EditorModel.commentEditor: CommentEditor?` (the edit and its field's rectangle in display canvas points; `nil` when there is no edit, the comment is gone or the panel is hidden)
  - `@discardableResult EditorModel.beginEditing(_ id: CommentID) -> Bool`
  - `EditorModel.commentDraftChanged(_ text: String)`, `commitCommentEdit()`, `cancelCommentEdit()`

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorEditorTests/CommentTypingTests.swift`

```swift
import CreatorGeometry
import CreatorGraph
import Foundation
import Testing
@testable import CreatorEditor

/// Typing into a comment in place on the canvas (comments typing plan, spec 2026-10-09 §8): the model's side. The edit
/// is a draft until it is committed, as one undo step through `setNoteText` / `setFrameTitle`; Esc throws it away.
@MainActor
struct CommentTypingTests {
    let a = testNode(NumberTestNode.self, id: 1, at: Vector2(600, 400))
    let sticky = note(1, "Line one", at: Vector2(100, 100))
    let frame = box(2, "Bracket", at: Vector2(400, 100))
    /// Not symmetric about the diagonal, so the left dock's transpose shows.
    let tall = note(3, "Tall", at: Vector2(100, 300))

    func editor(dock: DockSide = .bottom) -> EditorModel {
        makeEditor([a], stickies: [sticky, tall], frames: [frame], dock: dock)
    }

    @Test func beginningSelectsTheCommentAloneAndChangesNothing() throws {
        let editor = editor()
        editor.selection = [a.id]
        #expect(editor.beginEditing(sticky.id))
        #expect(editor.canvasSelection == CanvasSelection(comments: [sticky.id]))
        let edit = try #require(editor.commentEdit)
        #expect(edit.id == sticky.id && edit.kind == .noteText)
        #expect(edit.original == "Line one" && edit.draft == "Line one")
        #expect(!editor.document.canUndo)
    }

    @Test func typingThenCommittingIsOneUndoStep() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commentDraftChanged("Line one\nLine two")
        #expect(editor.graph.stickies[sticky.id]?.text == "Line one", "typing alone changes nothing in the graph")
        editor.commitCommentEdit()
        #expect(editor.commentEdit == nil)
        #expect(editor.graph.stickies[sticky.id]?.text == "Line one\nLine two")
        #expect(editor.document.undoName == "Edit Note", "the inspector's path, so the step carries named-undo's name")
        #expect(editor.canvasSelection == CanvasSelection(comments: [sticky.id]), "the note stays selected")
        editor.document.undo()
        #expect(editor.graph.stickies[sticky.id]?.text == "Line one" && !editor.document.canUndo)
    }

    @Test func cancellingPutsTheOldTextBackAndLeavesNothingPending() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commentDraftChanged("Thrown away")
        editor.cancelCommentEdit()
        #expect(editor.commentEdit == nil)
        editor.commitPendingEntry()
        #expect(editor.graph.stickies[sticky.id]?.text == "Line one" && !editor.document.canUndo)
    }

    @Test func aFramesTitleIsTrimmedAndCommittedAsOneStep() {
        let editor = editor()
        editor.beginEditing(frame.id)
        #expect(editor.commentEdit?.kind == .frameTitle)
        editor.commentDraftChanged("  Front plate \n")
        editor.commitCommentEdit()
        #expect(editor.graph.frames[frame.id]?.title == "Front plate")
        #expect(editor.document.undoName == "Edit Frame")
        editor.document.undo()
        #expect(editor.graph.frames[frame.id]?.title == "Bracket" && !editor.document.canUndo)
    }

    /// Review Focus 1: an empty or blank title is refused as the inspector refuses it; the bar shows the old title.
    @Test func anEmptyTitleIsRefusedAndTheOldOneStays() {
        let editor = editor()
        for empty in ["", "   ", "\n"] {
            editor.beginEditing(frame.id)
            editor.commentDraftChanged(empty)
            editor.commitCommentEdit()
            #expect(editor.refusal?.message == "A frame needs a title.")
            #expect(editor.graph.frames[frame.id]?.title == "Bracket" && !editor.document.canUndo)
            #expect(editor.commentEdit == nil, "the edit ends and the title bar shows the old title again")
            editor.clearRefusal()
        }
    }

    @Test func anUnchangedTextRecordsNothing() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commitCommentEdit()
        editor.beginEditing(frame.id)
        editor.commentDraftChanged("Bracket")
        editor.commitCommentEdit()
        #expect(!editor.document.canUndo && editor.refusal == nil)
    }

    @Test func aLateKeystrokeAfterTheEditEndedDoesNothing() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.cancelCommentEdit()
        editor.commentDraftChanged("Too late")
        editor.commitCommentEdit()
        #expect(editor.commentEdit == nil && editor.graph.stickies[sticky.id]?.text == "Line one")
    }

    // MARK: - Every moment the model already commits a typed value

    @Test func aPressElsewhereOnTheCanvasCommits() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commentDraftChanged("Typed")
        editor.click(Vector2(1200, 800))
        #expect(editor.graph.stickies[sticky.id]?.text == "Typed" && editor.commentEdit == nil)
    }

    @Test func changingTheSelectionCommits() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commentDraftChanged("Typed")
        editor.selection = [a.id]
        #expect(editor.graph.stickies[sticky.id]?.text == "Typed" && editor.commentEdit == nil)
    }

    /// The shell commits before it saves, exports, undoes or closes (`AppModel`): a canvas edit lands then too.
    @Test func theShellsCommitBeforeSavingCommitsACanvasEdit() {
        let editor = editor()
        editor.beginEditing(frame.id)
        editor.commentDraftChanged("Saved title")
        editor.commitPendingEntry()
        #expect(editor.graph.frames[frame.id]?.title == "Saved title" && editor.commentEdit == nil)
    }

    // MARK: - One pending entry at a time

    @Test func aFieldTypedIntoWhileTheCanvasIsBeingTypedIntoCommitsTheCanvasEditFirst() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commentDraftChanged("Canvas text")
        var landed: [String] = []
        editor.notePendingEntry(PendingEntry(owner: UUID(), text: "from the inspector", textCommit: { landed.append($0) }))
        #expect(editor.graph.stickies[sticky.id]?.text == "Canvas text" && editor.commentEdit == nil)
        editor.commitPendingEntry()
        #expect(landed == ["from the inspector"], "the inspector's entry now holds the slot, and lands on its own")
    }

    @Test func beginningCommitsATypedInspectorEntryFirstAndTakesTheSlot() {
        let editor = editor()
        var landed: [String] = []
        editor.notePendingEntry(PendingEntry(owner: UUID(), text: "typed in the inspector", textCommit: { landed.append($0) }))
        editor.beginEditing(sticky.id)
        #expect(landed == ["typed in the inspector"])
        #expect(editor.pendingEntry?.owner != nil && editor.pendingEntry?.owner == editor.commentEdit?.owner)
    }

    @Test func beginningAnotherCommentCommitsTheFirst() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commentDraftChanged("First")
        editor.beginEditing(frame.id)
        #expect(editor.graph.stickies[sticky.id]?.text == "First")
        #expect(editor.commentEdit?.id == frame.id)
        #expect(editor.canvasSelection == CanvasSelection(comments: [frame.id]))
    }

    // MARK: - The field's place

    @Test func theFieldSitsOverTheNoteAndOverTheFramesTitleBar() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        #expect(editor.commentEditor?.rect == CanvasRect(origin: Vector2(100, 100), size: Vector2(160, 100)))
        editor.beginEditing(frame.id)
        #expect(editor.commentEditor?.rect == CanvasRect(origin: Vector2(400, 100), size: Vector2(400, 22)))
    }

    /// Review Focus 2: docked left the graph is drawn transposed, and the field is drawn where the comment is.
    @Test func theLeftDockTransposesTheField() {
        let editor = editor(dock: .left)
        editor.beginEditing(tall.id)
        #expect(editor.commentEditor?.rect == CanvasRect(origin: Vector2(300, 100), size: Vector2(100, 160)))
        editor.beginEditing(frame.id)
        #expect(editor.commentEditor?.rect == CanvasRect(origin: Vector2(100, 400), size: Vector2(300, 22)))
    }

    /// Review Focus 3: the comment is deleted (undo of its creation, say) while it is being edited.
    @Test func aCommentThatIsGoneHasNoFieldAndNothingToCommit() throws {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commentDraftChanged("Typed")
        try editor.edit(.removeSticky(sticky.id))
        #expect(editor.commentEditor == nil)
        editor.commitCommentEdit()
        #expect(editor.graph.stickies[sticky.id] == nil && editor.commentEdit == nil)
    }

    /// Review Focus 3: the panel is hidden mid-edit (its canvas, and so the field, goes away): the edit is committed
    /// then, not left pending to land on a later save.
    @Test func hidingThePanelCommitsTheEdit() {
        let editor = editor()
        editor.beginEditing(sticky.id)
        editor.commentDraftChanged("Typed")
        editor.setDock(.hidden)
        #expect(editor.commentEditor == nil && editor.commentEdit == nil)
        #expect(editor.graph.stickies[sticky.id]?.text == "Typed")
    }

    /// The header's Left / Bottom buttons mid-edit: the edit goes on, and the field follows the comment into the other
    /// drawing (`commentEditor` is computed from the flow each time), the draft kept.
    @Test func changingTheDockMidEditMovesTheFieldAndKeepsTheDraft() {
        let editor = editor()
        editor.beginEditing(tall.id)
        editor.commentDraftChanged("Typed")
        #expect(editor.commentEditor?.rect == CanvasRect(origin: Vector2(100, 300), size: Vector2(160, 100)))
        editor.setDock(.left)
        #expect(editor.commentEdit?.draft == "Typed" && editor.commentEdit?.id == tall.id)
        #expect(editor.commentEditor?.rect == CanvasRect(origin: Vector2(300, 100), size: Vector2(100, 160)))
        editor.setDock(.bottom)
        #expect(editor.commentEditor?.rect == CanvasRect(origin: Vector2(100, 300), size: Vector2(160, 100)))
        editor.commitCommentEdit()
        #expect(editor.graph.stickies[tall.id]?.text == "Typed")
    }

    /// User decision 9: a sketch being open locks the level (`isLevelLocked`), not the comments; add-note works then too.
    @Test func typingWorksWhileTheLevelIsLocked() {
        let editor = editor()
        editor.isLevelLocked = true
        #expect(editor.beginEditing(sticky.id))
        editor.commentDraftChanged("Typed during a sketch")
        editor.commitCommentEdit()
        #expect(editor.graph.stickies[sticky.id]?.text == "Typed during a sketch")
    }

    /// Review Focus 4: leaving the group being edited in commits to the level it was typed on.
    @Test func leavingAGroupCommitsTheEditToThatLevel() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        #expect(editor.addNote(atScreen: Vector2(40, 40)))
        let id = try #require(editor.canvasSelection.comments.first)
        editor.beginEditing(id)
        editor.commentDraftChanged("Rib")
        editor.exitGroup()
        #expect(grouped.current?.graph.stickies[id]?.text == "Rib")
        #expect(editor.rootGraph.stickies.isEmpty && editor.commentEdit == nil)
    }

    /// Review Focus 1: a title is one line; a line break pasted into it becomes a space.
    @Test func aLineBreakPastedIntoATitleBecomesASpace() {
        let editor = editor()
        editor.beginEditing(frame.id)
        editor.commentDraftChanged("Front\nplate")
        editor.commitCommentEdit()
        #expect(editor.graph.frames[frame.id]?.title == "Front plate")
    }

    @Test func beginningNeedsACommentThePanelAndNoDragUnderWay() {
        let editor = editor()
        #expect(!editor.beginEditing(commentID(99)) && editor.commentEdit == nil)
        let start = Vector2(1200, 800)
        editor.pointerDragged(from: start, to: start + Vector2(50, 50))
        #expect(editor.interaction != nil)
        #expect(!editor.beginEditing(sticky.id))
        editor.pointerReleased(from: start, at: start + Vector2(50, 50))
        let hidden = makeEditor([], stickies: [sticky], dock: .hidden)
        #expect(!hidden.beginEditing(sticky.id))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CommentTypingTests`
Expected: FAIL to compile, "value of type 'EditorModel' has no member 'beginEditing'".

- [ ] **Step 3: Write the implementation**

**Create** `Sources/CreatorEditor/CommentEdit.swift`

```swift
import CreatorGraph
import Foundation

/// A comment being typed into in place on the canvas (comments typing plan; spec 2026-10-09 §8): which comment, what it
/// held when editing began (Esc puts it back) and what has been typed since. View state: never undone, never saved.
/// The text reaches the graph only when the edit is committed (`EditorModel.commitCommentEdit()`), as one undo step.
public struct CommentEdit: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A note's multi-line text.
        case noteText
        /// A frame's single-line title.
        case frameTitle
    }

    public var id: CommentID
    public var kind: Kind
    /// What the note's text or the frame's title was when editing began.
    public var original: String
    /// What the field holds now.
    public var draft: String
    /// Names this edit's `PendingEntry`, so only the edit itself can replace or drop it, and the canvas view keys its
    /// field by it (a new edit is a new field, with focus asked for afresh).
    public var owner: UUID
}
```

**Create** `Sources/CreatorEditor/CommentEditor.swift`

```swift
import CreatorGraph

/// What the canvas draws to edit a comment in place: the edit, and the rectangle of its field in display canvas
/// points (a note's whole rectangle, a frame's title bar), under the canvas's own pan and zoom.
public struct CommentEditor: Equatable, Sendable {
    public var edit: CommentEdit
    public var rect: CanvasRect
}
```

**Create** `Sources/CreatorEditor/EditorModel+CommentEditing.swift`

```swift
import CreatorGeometry
import CreatorGraph
import Foundation

/// Typing into a note or a frame's title in place on the canvas (comments typing plan; spec 2026-10-09 §8). The draft
/// is held here and in the model's one `pendingEntry` slot, so a canvas press, a selection change, undo, saving and
/// every other moment that commits a typed inspector value commits it too, and a field typed into elsewhere commits it
/// first (`notePendingEntry`). A commit goes through `setNoteText` / `setFrameTitle`, the inspector's own paths: one
/// undo step, an empty title refused, an unchanged text recorded as nothing.
extension EditorModel {
    /// The edit and where its field is drawn, or `nil` when nothing is being edited, the comment is gone from the
    /// level shown, or the panel is hidden.
    public var commentEditor: CommentEditor? {
        guard isPanelVisible, let edit = commentEdit, let rect = fieldRect(of: edit) else { return nil }
        return CommentEditor(edit: edit, rect: rect)
    }

    /// Starts editing comment `id` in place: a note's text over the note, a frame's title over its title bar. The
    /// comment becomes the whole selection, and anything typed and not yet committed (in the inspector, or on another
    /// comment) is committed first. Returns false, doing nothing, for a comment that isn't on the level shown, with
    /// the panel hidden, or during a drag.
    @discardableResult
    public func beginEditing(_ id: CommentID) -> Bool {
        guard isPanelVisible, interaction == nil else { return false }
        let kind: CommentEdit.Kind
        let text: String
        if let note = graph.stickies[id] {
            kind = .noteText
            text = note.text
        } else if let box = graph.frames[id] {
            kind = .frameTitle
            text = box.title
        } else {
            return false
        }
        commitPendingEntry()
        canvasSelection = CanvasSelection(comments: [id])
        let edit = CommentEdit(id: id, kind: kind, original: text, draft: text, owner: UUID())
        commentEdit = edit
        pendingEntry = entry(for: edit)
        return true
    }

    /// The field's text changed (every keystroke).
    public func commentDraftChanged(_ text: String) {
        guard var edit = commentEdit, edit.draft != text else { return }
        edit.draft = text
        commentEdit = edit
        pendingEntry = entry(for: edit)
    }

    /// Ends the edit, writing the draft: focus loss, ⌘↩ on a note, Return on a title. Does nothing with no edit.
    public func commitCommentEdit() {
        guard let edit = commentEdit else { return }
        if pendingEntry?.owner == edit.owner {
            commitPendingEntry()
        } else {
            commentEdit = nil
        }
    }

    /// Ends the edit and throws the draft away (Esc): the comment keeps what it held.
    public func cancelCommentEdit() {
        guard let edit = commentEdit else { return }
        if pendingEntry?.owner == edit.owner { pendingEntry = nil }
        commentEdit = nil
    }

    /// The field's rectangle in display canvas points: the note's, or the frame's title bar.
    private func fieldRect(of edit: CommentEdit) -> CanvasRect? {
        switch edit.kind {
        case .noteText: graph.stickies[edit.id].map { frame(of: $0) }
        case .frameTitle: graph.frames[edit.id].map { CommentLayout.titleBar(of: frame(of: $0)) }
        }
    }

    /// The pending entry that stands for `edit`: committing it ends the edit and writes the draft.
    private func entry(for edit: CommentEdit) -> PendingEntry {
        PendingEntry(owner: edit.owner, text: edit.draft, textCommit: { [weak self] text in self?.finishCommentEdit(with: text) })
    }

    /// Writes the draft and ends the edit. A title is one line: line breaks in it (pasted ones) become spaces.
    private func finishCommentEdit(with text: String) {
        guard let edit = commentEdit else { return }
        commentEdit = nil
        switch edit.kind {
        case .noteText: setNoteText(edit.id, to: text)
        case .frameTitle: setFrameTitle(edit.id, to: text.split(whereSeparator: \.isNewline).joined(separator: " "))
        }
    }
}
```

**Modify** `Sources/CreatorEditor/EditorModel.swift`

```swift
    /// What an inspector field holds but hasn't committed (`EditorModel+PendingEntry`).
    @ObservationIgnored var pendingEntry: PendingEntry?
```

```swift
    /// What an inspector field holds but hasn't committed (`EditorModel+PendingEntry`).
    @ObservationIgnored var pendingEntry: PendingEntry?
    /// The comment being typed into in place on the canvas (`EditorModel+CommentEditing`). View state: never undone,
    /// never saved. While it is set, `pendingEntry` is its draft.
    public internal(set) var commentEdit: CommentEdit?
```

**Modify** `Sources/CreatorEditor/EditorModel.swift`

```swift
    public func setDock(_ dock: DockSide) {
        if dock != .hidden { lastVisibleDock = dock }
```

```swift
    public func setDock(_ dock: DockSide) {
        // The canvas, and the field typed into on it, go away: commit what was typed rather than leave it pending.
        if dock == .hidden { commitCommentEdit() }
        if dock != .hidden { lastVisibleDock = dock }
```

**Modify** `Sources/CreatorEditor/EditorModel+PendingEntry.swift`

```swift
    /// Records what an inspector field holds after a keystroke (`nil` once it's committed or abandoned).
    public func notePendingEntry(_ entry: PendingEntry?) {
        pendingEntry = entry
    }
```

```swift
    /// Records what an inspector field holds after a keystroke (`nil` once it's committed or abandoned). There is one
    /// pending entry at a time: a field typed into while a comment is being typed into on the canvas commits that
    /// edit first, so the two never fight over the same text.
    public func notePendingEntry(_ entry: PendingEntry?) {
        if let edit = commentEdit, entry?.owner != edit.owner { commitCommentEdit() }
        pendingEntry = entry
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CommentTypingTests`
Expected: PASS, 22 tests.

- [ ] **Step 5: Lint, run everything, commit**

Run: `swiftlint lint --strict` (zero violations), then the full suite (see "Verifying a task" in the header): expected master + 22 tests.

```bash
git add Sources/CreatorEditor Tests/CreatorEditorTests/CommentTypingTests.swift
git commit -m "feat(editor): the model for typing on the canvas"
```

### Task 2: A double click on a note or a frame's title bar starts editing

S5b's recogniser pairs two plain clicks on one node (0.4 s, 4 pt, the injectable `EditorModel.now`). It now pairs clicks on
one *target*: a node, a note, or a frame's title bar (not its edge band: that is for grabbing the frame). It already runs
after the click it ends on (`EditorModel+Pointer`), so the second click has selected the comment before editing starts.
The record is renamed from `NodeClick` to `RecentClick` because it no longer holds only nodes.

**Files:**
- Create: `Sources/CreatorEditor/ClickTarget.swift`
- Create: `Sources/CreatorEditor/RecentClick.swift`
- Delete: `Sources/CreatorEditor/NodeClick.swift`
- Modify: `Sources/CreatorEditor/EditorModel+DoubleClick.swift`
- Modify: `Sources/CreatorEditor/EditorModel.swift` (`lastNodeClick` becomes `lastClick`)
- Modify: `Sources/CreatorEditor/EditorModel+Pointer.swift` (two reads of it, one comment)
- Modify: `Sources/CreatorEditor/EditorModel+Levels.swift` (one)
- Test: `Tests/CreatorEditorTests/CommentDoubleClickTests.swift`

**Interfaces:**
- Consumes: `EditorModel.beginEditing(_:)` (Task 1), `CommentLayout.titleBar(of:)`, `EditorModel.frame(ofComment:)`, `CanvasHit`.
- Produces: `enum ClickTarget: Hashable, Sendable { case node(NodeID), note(CommentID), frameTitle(CommentID) }`,
  `EditorModel.clickTarget(for:at:) -> ClickTarget?` (internal), `EditorModel.lastClick: RecentClick?`.

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorEditorTests/CommentDoubleClickTests.swift`

```swift
import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorEditor

/// A double click on a note, or on a frame's title bar, starts editing it in place (comments typing plan; spec
/// 2026-10-09 §8). The recogniser is S5b's: two plain clicks on one target within 0.4 s and 4 points.
@MainActor
struct CommentDoubleClickTests {
    let sticky = note(1, "Line one", at: Vector2(100, 100))
    let other = note(3, "Other", at: Vector2(100, 400))
    let frame = box(2, "Bracket", at: Vector2(500, 100))

    func make(dock: DockSide = .bottom) -> (EditorModel, TestClock) {
        let editor = makeEditor([], stickies: [sticky, other], frames: [frame], dock: dock)
        let clock = TestClock()
        editor.now = { clock.now }
        return (editor, clock)
    }

    func body(_ editor: EditorModel, of id: CommentID) -> Vector2 {
        editor.screenPoint(inComment: id, inset: Vector2(40, 40))
    }

    func titleBar(_ editor: EditorModel) -> Vector2 {
        editor.screenPoint(inComment: frame.id, inset: Vector2(60, 10))
    }

    @Test func aDoubleClickOnANoteEditsItsText() throws {
        let (editor, clock) = make()
        let point = body(editor, of: sticky.id)
        editor.click(point)
        #expect(editor.commentEdit == nil, "one click only selects")
        #expect(editor.canvasSelection == CanvasSelection(comments: [sticky.id]))
        clock.advance(by: .milliseconds(200))
        editor.click(point + Vector2(2, 1))
        let edit = try #require(editor.commentEdit)
        #expect(edit.id == sticky.id && edit.kind == .noteText && edit.draft == "Line one")
        #expect(editor.canvasSelection == CanvasSelection(comments: [sticky.id]))
        #expect(!editor.document.canUndo, "starting to edit records nothing")
    }

    @Test func aDoubleClickOnAFramesTitleBarEditsItsTitle() throws {
        let (editor, clock) = make()
        editor.click(titleBar(editor))
        clock.advance(by: .milliseconds(200))
        editor.click(titleBar(editor))
        let edit = try #require(editor.commentEdit)
        #expect(edit.id == frame.id && edit.kind == .frameTitle && edit.draft == "Bracket")
    }

    /// Review Focus 2: both docks and any pan and zoom, the click points read through the model's own transform.
    @Test func itWorksInBothDocksAtEveryZoom() {
        let transforms = [
            CanvasTransform(),
            CanvasTransform(offset: Vector2(30, 20), zoom: 0.5),
            CanvasTransform(offset: Vector2(-40, 15), zoom: 2),
        ]
        for dock in [DockSide.bottom, .left] {
            for transform in transforms {
                let (editor, clock) = make(dock: dock)
                editor.transform = transform
                for (id, point) in [(sticky.id, body(editor, of: sticky.id)), (frame.id, titleBar(editor))] {
                    editor.click(point)
                    clock.advance(by: .milliseconds(100))
                    editor.click(point)
                    #expect(editor.commentEdit?.id == id, "\(dock) at zoom \(transform.zoom)")
                    editor.cancelCommentEdit()
                    clock.advance(by: .seconds(1))
                }
            }
        }
    }

    /// A frame's edge band is for grabbing the frame, and its inside belongs to the nodes and the box.
    @Test func onlyAFramesTitleBarCounts() {
        let (editor, clock) = make()
        let band = editor.screenPoint(inComment: frame.id, inset: Vector2(3, 150))
        let inside = editor.screenPoint(inComment: frame.id, inset: Vector2(200, 150))
        #expect(editor.hitTest(band) == .frame(frame.id) && editor.hitTest(inside) == .empty)
        for point in [band, inside] {
            editor.click(point)
            clock.advance(by: .milliseconds(100))
            editor.click(point)
            #expect(editor.commentEdit == nil)
            clock.advance(by: .seconds(1))
        }
    }

    /// Review Focus 5: two clicks that aren't a double click (too slow, too far apart, on two comments, a modifier
    /// held, a drag between, or on a selected note's resize handle) never start editing.
    @Test func clicksThatArentADoubleClickDoNothing() throws {
        let (editor, clock) = make()
        let point = body(editor, of: sticky.id)
        editor.click(point)
        clock.advance(by: .milliseconds(450))
        editor.click(point)
        #expect(editor.commentEdit == nil, "too slow")
        clock.advance(by: .seconds(1))
        editor.click(point)
        editor.click(point + Vector2(6, 0))
        #expect(editor.commentEdit == nil, "too far apart")
        clock.advance(by: .seconds(1))
        editor.click(body(editor, of: other.id))
        editor.click(point)
        #expect(editor.commentEdit == nil, "two comments")
        for modifiers: CanvasModifiers in [.shift, .command] {
            clock.advance(by: .seconds(1))
            editor.click(point, modifiers: modifiers)
            editor.click(point, modifiers: modifiers)
            #expect(editor.commentEdit == nil, "⇧ extends and ⌘ toggles the selection instead")
        }
        clock.advance(by: .seconds(1))
        editor.click(point)
        editor.drag(point, point + Vector2(40, 0))
        editor.click(point + Vector2(40, 0))
        #expect(editor.commentEdit == nil, "a drag between")
        clock.advance(by: .seconds(1))
        let moved = try #require(editor.frame(ofComment: sticky.id), "the drag between moved the note")
        let handle = editor.transform.toScreen(CommentLayout.handle(of: moved).centre)
        editor.canvasSelection = CanvasSelection(comments: [sticky.id])
        #expect(editor.hitTest(handle) == .resize(sticky.id))
        editor.click(handle)
        editor.click(handle)
        #expect(editor.commentEdit == nil, "the handle resizes")
    }

    @Test func doubleClickingAnotherCommentWhileEditingCommitsTheFirstAndEditsTheNext() {
        let (editor, clock) = make()
        let first = body(editor, of: sticky.id)
        editor.click(first)
        editor.click(first)
        editor.commentDraftChanged("First")
        clock.advance(by: .seconds(1))
        let second = body(editor, of: other.id)
        editor.click(second)
        #expect(editor.graph.stickies[sticky.id]?.text == "First", "the first press committed it")
        #expect(editor.commentEdit == nil)
        clock.advance(by: .milliseconds(100))
        editor.click(second)
        #expect(editor.commentEdit?.id == other.id)
        editor.document.undo()
        #expect(editor.graph.stickies[sticky.id]?.text == "Line one", "the first edit was one undo step")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CommentDoubleClickTests`
Expected: FAIL: the assertions that `editor.commentEdit` is set fail (a double click on a comment does nothing yet).

- [ ] **Step 3: Write the implementation**

**Create** `Sources/CreatorEditor/ClickTarget.swift`

```swift
import CreatorGraph
import CreatorKernel

/// What a click can be paired on to make a double click (`EditorModel+DoubleClick`): a node's body, a note, or a
/// frame's title bar.
enum ClickTarget: Hashable, Sendable {
    case node(NodeID)
    case note(CommentID)
    case frameTitle(CommentID)
}
```

**Delete** `Sources/CreatorEditor/NodeClick.swift`

**Create** `Sources/CreatorEditor/RecentClick.swift`

```swift
import CreatorGeometry

/// One plain click on a `ClickTarget`, remembered so the next can be told a double click (`EditorModel+DoubleClick`).
struct RecentClick: Hashable, Sendable {
    var target: ClickTarget
    /// Where it was, in canvas-local screen points.
    var point: Vector2
    var time: ContinuousClock.Instant
}
```

**Replace the whole of** `Sources/CreatorEditor/EditorModel+DoubleClick.swift`

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Double-clicking (sketcher spec §8: "Enter by double-clicking a Sketch node"; the groups spec's §6 enters a group the
/// same way; the comments typing plan, spec 2026-10-09 §8, edits a note or a frame's title). The canvas's one
/// zero-distance drag reports each click alone, without the click count (docs/metalui-gaps.md S5-b, the double-click
/// half of GI-a), so the model pairs them: a click with no modifiers on the same target within `doubleClickInterval`
/// and `doubleClickSlop` of the one before. A target is a node's body, a note, or a frame's title bar.
extension EditorModel {
    /// The longest gap between a double click's two clicks (the groups spec's 0.4 s, §6).
    public static let doubleClickInterval = Duration.milliseconds(400)
    /// How far apart a double click's two clicks may land, in screen points.
    public static let doubleClickSlop = 4.0
    /// The inspector buttons a double click on a node presses; the first of them a node's inspector has wins: a Sketch
    /// node's "Edit sketch", a group node's "Edit Group" (groups spec §6).
    static let doubleClickActions: [InspectorAction] = [.editSketch, .editGroup]

    /// A press released without a drag, on `hit` at `point` with `modifiers` held: the second click with no modifiers
    /// on one target is a double click (`doubleClicked`); any other click on a target starts a new pair, and a socket,
    /// a frame's edge band, empty canvas or a modifier starts none.
    func pairClick(on hit: CanvasHit, at point: Vector2, modifiers: CanvasModifiers) {
        guard modifiers.isEmpty, let target = clickTarget(for: hit, at: point) else {
            lastClick = nil
            return
        }
        let time = now()
        if let last = lastClick, last.target == target, (point - last.point).length <= Self.doubleClickSlop,
           last.time.duration(to: time) <= Self.doubleClickInterval {
            lastClick = nil
            doubleClicked(target)
        } else {
            lastClick = RecentClick(target: target, point: point, time: time)
        }
    }

    /// The target a press on `hit` at `point` (canvas-local screen points) can double-click: a node, a note, or a
    /// frame's title bar. A frame's edge band is `.frame` too, for grabbing it, but is no target.
    func clickTarget(for hit: CanvasHit, at point: Vector2) -> ClickTarget? {
        switch hit {
        case .node(let node):
            return .node(node)
        case .note(let id):
            return .note(id)
        case .frame(let id):
            guard let rect = frame(ofComment: id), CommentLayout.titleBar(of: rect).contains(transform.toCanvas(point)) else {
                return nil
            }
            return .frameTitle(id)
        case .socket, .resize, .empty:
            return nil
        }
    }

    private func doubleClicked(_ target: ClickTarget) {
        switch target {
        case .node(let node): nodeDoubleClicked(node)
        case .note(let id), .frameTitle(let id): beginEditing(id)
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

**Modify** `Sources/CreatorEditor/EditorModel.swift`

```swift
    /// The last plain click on a node: which, where on the canvas (screen points) and when.
    @ObservationIgnored var lastNodeClick: NodeClick?
```

```swift
    /// The last plain click on a node, a note or a frame's title bar: which, where on the canvas (screen points) and
    /// when.
    @ObservationIgnored var lastClick: RecentClick?
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`

```swift
            // A press whose drag Esc cancelled ends here: no click, no wire, and no half of a double click.
            lastNodeClick = nil
            endPress()
            return
        }
        if interaction != nil { lastNodeClick = nil }
```

```swift
            // A press whose drag Esc cancelled ends here: no click, no wire, and no half of a double click.
            lastClick = nil
            endPress()
            return
        }
        if interaction != nil { lastClick = nil }
```

**Modify** `Sources/CreatorEditor/EditorModel+Pointer.swift`

```swift
            // After the click: a double click on a group node enters it, and the click must not select it afterwards.
```

```swift
            // After the click: a double click on a group node enters it and one on a note or a frame's title bar edits
            // it, and the click must not select it afterwards.
```

**Modify** `Sources/CreatorEditor/EditorModel+Levels.swift`

```swift
        lastNodeClick = nil
```

```swift
        lastClick = nil
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "CommentDoubleClickTests|DoubleClickTests"`
Expected: PASS (the new suite and S5b's `DoubleClickTests`, unchanged).

- [ ] **Step 5: Lint, run everything, commit**

Run: `swiftlint lint --strict` (zero violations), then the full suite: expected master + 22 + 6 = master + 28 tests.

```bash
git add -A Sources/CreatorEditor Tests/CreatorEditorTests/CommentDoubleClickTests.swift
git commit -m "feat(editor): a double click on a note or a frame's title bar starts editing it"
```

### Task 3: The canvas editor, drawn over the comment, and ⌘↩ in the inspector's note box

A `TextEditor` over a note and a `TextField` over a frame's title bar, in a layer over the canvas that has the canvas's
own zoom and pan, so the field is exactly where the comment is, in both docks, with its text scaled as the comment's
is. The canvas's surface (its gestures, hover, scroll, menu and cursor) moves unchanged into `CanvasSurface` so the
editor can be its sibling, not its child: Task 4 makes the surface a key region, and a field inside a key region's
subtree would hand its keys to the canvas's handler. The field's keys are `onKeyPress` handlers on the field (MetalUI C9),
so they run only while it has focus, before the field's own editing keys: ⌘↩ commits a note (`CommentKeys`), Esc cancels
(both), Return commits a title (`onSubmit`). Focus is asked for as the field appears (`onAppear`); losing it commits.

The same `CommentKeys.commitsNote` closes gap CM-a in the inspector: its note `TextEditor` (`CommentTextEntry`) commits on
⌘↩ with an `onKeyPress`, exactly the spelling MetalUI's KF-Z ruling gives, and plain Return still breaks the line.

MetalUI facts this task rests on, measured in the scratch probe (Appendix A, at feat/key-focus `c5df112`): a
`FocusState` written in `onAppear` focuses a freshly built `TextEditor`; a press inside a field drawn under
`scaleEffect` focuses it; keys typed in the focused field never reach a handler on a sibling key region; ⌘↩ reaches the
field's `onKeyPress` and Esc too.

**Files:**
- Create: `Sources/CreatorEditor/CommentKeys.swift`
- Create: `Sources/CreatorEditor/CommentEditorField.swift`
- Create: `Sources/CreatorEditor/CommentEditorLayer.swift`
- Create: `Sources/CreatorEditor/CanvasSurface.swift`
- Replace: `Sources/CreatorEditor/GraphCanvas.swift`
- Modify: `Sources/CreatorEditor/CommentTextEntry.swift` (⌘↩)
- Test: `Tests/CreatorEditorTests/CommentKeysTests.swift`, `Tests/CreatorEditorTests/CommentEditorRenderTests.swift`

**Interfaces:**
- Consumes: `EditorModel.commentEditor`, `commentDraftChanged(_:)`, `commitCommentEdit()`, `cancelCommentEdit()` (Task 1).
- Produces: `CommentKeys.commitsNote(_ modifiers: Modifiers) -> Bool` (used by `CommentEditorField` and by `CommentTextEntry`, the inspector's box, both in this task),
  `CanvasSurface(model:input:)` (the old `GraphCanvas` body; Task 4 adds the key region to it), `CommentEditorLayer(model:)`,
  `CommentEditorField(model:editor:)`.

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorEditorTests/CommentKeysTests.swift`

```swift
import MetalUI
import Testing
@testable import CreatorEditor

/// ⌘↩ commits a note's text, in the inspector's box and on the canvas (canvas comments spec 2026-10-09 §7); plain
/// Return, ⇧↩ and ⌥↩ keep breaking the line (MetalUI C9's KF-Z leaves them to the editor).
struct CommentKeysTests {
    @Test func commandReturnCommitsANote() {
        #expect(CommentKeys.commitsNote(.command))
        #expect(CommentKeys.commitsNote([.command, .shift]))
    }

    @Test func otherReturnsBreakTheLine() {
        for modifiers: Modifiers in [[], .shift, .option, .control] {
            #expect(!CommentKeys.commitsNote(modifiers))
        }
    }
}
```

**Create** `Tests/CreatorEditorTests/CommentEditorRenderTests.swift`

```swift
import CreatorGeometry
import CreatorGraph
import MetalUI
import Testing
@testable import CreatorEditor

/// Headless frames of the canvas while a note or a frame's title is being typed into in place (comments typing plan;
/// spec 2026-10-09 §8): the field lies over the comment, in either dock and at any pan and zoom, and it is opaque, so
/// the text under it doesn't show through.
@MainActor
struct CommentEditorRenderTests {
    let sticky = note(1, "Line one", at: Vector2(100, 60))
    let frame = box(2, "Bracket", at: Vector2(50, 200), size: Vector2(300, 150))
    let transforms = [
        CanvasTransform(),
        CanvasTransform(offset: Vector2(10, 5), zoom: 0.5),
        CanvasTransform(offset: Vector2(-30, 15), zoom: 2),
    ]

    func canvasOrigin(_ editor: EditorModel) -> Vector2 {
        GraphPanelLayout.canvasFrame(inPanelOf: Vector2(900, 600), flow: editor.flow, showsLibrary: editor.showsLibrary).origin
    }

    func panel(_ editor: EditorModel) -> Scene {
        renderHeadless { GraphPanel(model: editor, input: GraphPanelInput(model: editor)) }
    }

    /// The rect painted last at `displayPoint` (display canvas points), as a frame in window points.
    func painted(at displayPoint: Vector2, in scene: Scene, _ editor: EditorModel) -> (frame: CanvasRect, opaque: Bool)? {
        let point = canvasOrigin(editor) + editor.transform.toScreen(displayPoint)
        return topRect(at: point, in: scene).map { (screenFrame(of: $0, in: scene), $0.background.a == 1) }
    }

    func editor(dock: DockSide, _ transform: CanvasTransform) -> EditorModel {
        let editor = makeEditor([], stickies: [sticky], frames: [frame], dock: dock)
        editor.transform = transform
        return editor
    }

    /// Review Focus 2: both docks, three zooms; the field is exactly the note's rectangle through the canvas's own
    /// transform, and opaque where the note's tint is not.
    @Test func theNoteEditorLiesExactlyOverTheNote() throws {
        for dock in [DockSide.bottom, .left] {
            for transform in transforms {
                let editor = editor(dock: dock, transform)
                let rect = try #require(editor.frame(ofComment: sticky.id))
                let inside = rect.origin + Vector2(10, 10)
                let before = try #require(painted(at: inside, in: panel(editor), editor))
                #expect(!before.opaque, "set up: the note is a tint")
                editor.beginEditing(sticky.id)
                let during = try #require(painted(at: inside, in: panel(editor), editor))
                let origin = canvasOrigin(editor) + transform.toScreen(rect.origin)
                let size = rect.size * transform.zoom
                #expect(during.opaque, "\(dock), zoom \(transform.zoom)")
                #expect((during.frame.origin - origin).length < 0.51 && (during.frame.size - size).length < 0.51,
                        "\(dock), zoom \(transform.zoom): \(during.frame) against \(origin) \(size)")
            }
        }
    }

    @Test func theTitleEditorLiesInsideTheTitleBar() throws {
        for dock in [DockSide.bottom, .left] {
            for transform in transforms {
                let editor = editor(dock: dock, transform)
                let bar = CommentLayout.titleBar(of: try #require(editor.frame(ofComment: frame.id)))
                let inside = bar.origin + Vector2(30, bar.size.y * 0.5)
                let before = try #require(painted(at: inside, in: panel(editor), editor))
                #expect(!before.opaque, "set up: the bar is a tint")
                editor.beginEditing(frame.id)
                let during = try #require(painted(at: inside, in: panel(editor), editor))
                let origin = canvasOrigin(editor) + transform.toScreen(bar.origin)
                let size = bar.size * transform.zoom
                #expect(during.opaque, "\(dock), zoom \(transform.zoom)")
                #expect(during.frame.origin.x >= origin.x - 0.51 && during.frame.maxX <= origin.x + size.x + 0.51)
                #expect(during.frame.origin.y >= origin.y - 0.51 && during.frame.maxY <= origin.y + size.y + 0.51,
                        "\(dock), zoom \(transform.zoom): \(during.frame) in \(origin) \(size)")
            }
        }
    }

    /// The layer builds nothing without an edit (views stay cheap, PERF-b): the frame is what it was when the comment
    /// was merely selected, once the edit has ended either way.
    @Test func noFieldIsBuiltWithoutAnEdit() {
        let editor = editor(dock: .bottom, CanvasTransform())
        for id in [sticky.id, frame.id] {
            editor.canvasSelection = CanvasSelection(comments: [id])
            let selected = panel(editor).rects.count
            editor.beginEditing(id)
            #expect(panel(editor).rects.count > selected)
            editor.cancelCommentEdit()
            #expect(panel(editor).rects.count == selected)
            editor.beginEditing(id)
            editor.commitCommentEdit()
            #expect(panel(editor).rects.count == selected)
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "CommentKeysTests|CommentEditorRenderTests"`
Expected: FAIL to compile, "cannot find 'CommentKeys' in scope".

- [ ] **Step 3: Write the implementation**

**Create** `Sources/CreatorEditor/CommentKeys.swift`

```swift
import MetalUI

/// Keys that end the editing of a comment, shared by the inspector's note box and the canvas's editor.
enum CommentKeys {
    /// ⌘↩ commits a note's text (canvas comments spec 2026-10-09 §7). MetalUI C9 (KF-Z) leaves ⌘↩ out of a
    /// `TextEditor`'s editing keys, so an `onKeyPress` for Return that answers `.handled` for it runs before the editor
    /// and plain Return still breaks the line.
    static func commitsNote(_ modifiers: Modifiers) -> Bool { modifiers.contains(.command) }
}
```

**Create** `Sources/CreatorEditor/CommentEditorField.swift`

```swift
import CreatorGraph
import MetalUI

/// The field a comment is typed into on the canvas (comments typing plan; spec 2026-10-09 §8): a multi-line
/// `TextEditor` over a note, a single-line `TextField` over a frame's title bar. It takes focus as it appears, and
/// reports every edit to the model (`commentDraftChanged`). Return in a title and ⌘↩ in a note commit, Esc cancels,
/// and losing focus commits (a press elsewhere on the canvas clears focus: it is a key region, MetalUI C9's M5-g). The
/// keys are `onKeyPress` handlers on the field itself, so they run only while it has focus and before its own editing.
/// It is drawn under the canvas's pan and zoom (`CommentEditorLayer`), so `editor.rect` is in canvas points.
struct CommentEditorField: Component {
    let model: EditorModel
    let editor: CommentEditor
    @FocusState var isFocused: Bool

    var content: some ElementGroup {
        let rect = editor.rect
        switch editor.edit.kind {
        case .noteText:
            TextEditor("Note", text: editor.edit.draft, onChange: { model.commentDraftChanged($0) })
                .font(.callout)
                .focused($isFocused)
                .onKeyPress(keys: [.return]) { press in
                    guard CommentKeys.commitsNote(press.modifiers) else { return .ignored }
                    model.commitCommentEdit()
                    return .handled
                }
                .onKeyPress(.escape) {
                    model.cancelCommentEdit()
                    return .handled
                }
                .frame(width: rect.size.x.px, height: rect.size.y.px)
                .offset(x: rect.origin.x.px, y: rect.origin.y.px)
                .onAppear { isFocused = true }
                .onChange(of: isFocused) { wasFocused, focused in
                    if wasFocused, !focused { model.commitCommentEdit() }
                }
        case .frameTitle:
            TextField("Title", text: editor.edit.draft, onChange: { model.commentDraftChanged($0) })
                .font(.system(.caption, weight: .semibold))
                .focused($isFocused)
                .onKeyPress(.escape) {
                    model.cancelCommentEdit()
                    return .handled
                }
                .onSubmit { model.commitCommentEdit() }
                .frame(width: rect.size.x.px, height: rect.size.y.px)
                .offset(x: rect.origin.x.px, y: rect.origin.y.px)
                .onAppear { isFocused = true }
                .onChange(of: isFocused) { wasFocused, focused in
                    if wasFocused, !focused { model.commitCommentEdit() }
                }
        }
    }
}
```

**Create** `Sources/CreatorEditor/CommentEditorLayer.swift`

```swift
import MetalUI

/// The canvas's editing layer (comments typing plan; spec 2026-10-09 §8): the field of the comment being typed into,
/// or nothing. It sits over the canvas's surface under the same zoom and pan as `CanvasLayers`, so a field built at a
/// comment's canvas rectangle lies exactly over the comment, in either dock, at any zoom, with its text scaled as the
/// comment's is. A sibling of the surface rather than a child: the surface is a key region (`CanvasSurface`), and a
/// field inside it would pass its keys to the canvas's own handler.
struct CommentEditorLayer: Component {
    let model: EditorModel

    var content: some ElementGroup {
        let transform = model.transform
        let editors = model.commentEditor.map { [$0] } ?? []
        return ZStack(alignment: .topLeading) {
            // Keyed by the edit, so a new edit is a new field (focus asked for again), though it sits where the last was.
            ForEach(editors, id: \.edit.owner) { editor in
                CommentEditorField(model: model, editor: editor)
            }
        }
        .scaleEffect(transform.zoom, anchor: .topLeading)
        .offset(x: transform.offset.x.px, y: transform.offset.y.px)
    }
}
```

**Create** `Sources/CreatorEditor/CanvasSurface.swift`

```swift
import MetalUI

/// The graph canvas's surface: the layers under the zoom and pan transform, one press-and-drag gesture for everything
/// (hit testing is the model's), a middle-button drag that pans, a pinch, the scroll wheel, the cursor, the context
/// menu (Add Note, Frame Selection at the point it opened) and pointer tracking for the palette. All input goes
/// through `GraphPanelInput` to the model.
struct CanvasSurface: Component {
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
        .gesture(input.middlePanGesture())
        .gesture(input.pinchGesture())
        .contentShape(Rectangle())
        .onContinuousHover { phase in input.hover(phase) }
        .onScrollWheel { event in input.scrolled(event) }
        .contextMenu { (location: Point<Pixels>?) in
            for item in CanvasMenuItem.allCases {
                Button(item.title) { model.choose(item, at: location.map { GraphPanelInput.vector($0) }) }
                    .disabled(!model.isEnabled(item))
            }
        }
        .pointerStyle(model.canvasCursor?.pointerStyle)
    }
}
```

**Replace the whole of** `Sources/CreatorEditor/GraphCanvas.swift`

```swift
import MetalUI

/// The graph canvas: its surface (`CanvasSurface`, which takes all the input) with the editing layer over it
/// (`CommentEditorLayer`, a note or a frame's title being typed into in place). The palette itself floats over the whole
/// window (`SearchPaletteOverlay`), so the canvas never clips it.
struct GraphCanvas: Component {
    let model: EditorModel
    let input: GraphPanelInput

    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            CanvasSurface(model: model, input: input)
            CommentEditorLayer(model: model)
        }
        .clipped()
    }
}
```

**Modify** `Sources/CreatorEditor/CommentTextEntry.swift`

```swift
/// kept locally and recorded with the model as a text `PendingEntry`; it is committed (one "Edit Note" undo step)
/// when the field loses focus and when the model commits it (a canvas press, a
/// selection change, the shell saving), so clicking away never drops it.
```

```swift
/// kept locally and recorded with the model as a text `PendingEntry`; it is committed (one "Edit Note" undo step)
/// on ⌘↩ (an `onKeyPress` on the field, MetalUI C9's answer to gap CM-a: the key reaches the handler before the
/// editor, and plain Return still breaks the line), when the field loses focus and when the model commits it (a
/// canvas press, a selection change, the shell saving), so clicking away never drops it.
```

**Modify** `Sources/CreatorEditor/CommentTextEntry.swift`

```swift
        .focused($isFocused)
        .frame(width: Pixels(256), height: Pixels(96))
```

```swift
        .focused($isFocused)
        .onKeyPress(keys: [.return]) { press in
            guard CommentKeys.commitsNote(press.modifiers) else { return .ignored }
            model.commitPendingEntry()
            draft = nil
            return .handled
        }
        .frame(width: Pixels(256), height: Pixels(96))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "CommentKeysTests|CommentEditorRenderTests"`
Expected: PASS, 5 tests. (With only `GraphCanvas` left as it was, `theNoteEditorLiesExactlyOverTheNote` and
`theTitleEditorLiesInsideTheTitleBar` fail on `during.opaque`: no field is drawn.)

- [ ] **Step 5: Lint, run everything, commit**

Run: `swiftlint lint --strict` (zero violations), then the full suite: expected master + 22 + 6 + 5 = master + 33 tests. The
existing render tests (`CanvasClipRenderTests`, `CommentRenderTests`, `GraphPanelRenderTests`) pin that the canvas moved
into the new wrapper without moving.

```bash
git add -A Sources/CreatorEditor Tests/CreatorEditorTests
git commit -m "feat(editor): the canvas editor over a note or a frame's title bar"
```

### Task 4: The graph's keys and text focus go through the canvas's key region (MetalUI C9)

Until now the graph's keys were read from the window's `onInput` fallback ("whatever a focused field didn't claim")
and a canvas press called `window.focus(nil)`. Neither can say "a canvas text field has focus, so the canvas's keys must
not act", and a field that declines a key (⌘⇧N, ⌘G, ⌘D, Esc, Tab) would pass it to the graph. C9 scopes keys properly:
`CanvasSurface` becomes a `hoverKeyRegion` carrying one `onKeyPress` for the graph's keys. With nothing focused, keys go
to the region under the pointer; a focused field anywhere keeps every key (focus wins); a primary press in the region
clears a field's focus (which commits what was typed). The comment editor is the surface's sibling (Task 3), so its
keys never reach the canvas's handler. This adopts M5-b (the graph's keys, and Tab, which stops opening the palette
from a focused field) and M5-g (a canvas press ends text editing) for the graph panel. Not adopted, because nothing here
uses them: M5-h (the palette's ↑/↓ stay a keymap action) and the viewport's side of M4-a/M5-b/M5-g
(`AppInput`'s pointer veto for F, + and −; `AppModel.releaseTextFocus` for viewport presses).

Behaviour that changes, deliberately (User decision 1): the graph's keys now act only while the pointer is over the
canvas and nothing is focused (the canvas itself is not focusable, so a click never leaves focus on it). With nothing
focused and the pointer over the viewport, the inspector or the header,
Delete, ⌘A, arrows, Space, ⌘C/⌘V/⌘X/⌘D, ⌘G, ⌘⇧N, ⌘⇧C and Esc no longer reach the graph. ⌘Z and ⇧⌘Z are the app's
menu commands (`AppCommands`) and are unchanged.

**Files:**
- Modify: `Sources/CreatorEditor/CanvasSurface.swift` (`hoverKeyRegion`, `onKeyPress`)
- Modify: `Sources/CreatorEditor/GraphPanelInput.swift` (`keyPressed`, `handleKey`; `handle(_:)` keeps only the open palette's keys; `releaseTextFocus`, the `tab` binding and `GraphTab` go)
- Delete: `Sources/CreatorEditor/GraphTab.swift`
- Modify: `Sources/CreatorApp/AppModel.swift` (one line), `Sources/CreatorApp/AppInput.swift` (comment)
- Create: `Tests/CreatorEditorTests/GraphKeyEventTests.swift` (the `KeyPress` to `KeyEvent` conversion)
- Test: `Tests/CreatorEditorTests/GraphPanelInputTests.swift`, `SelectionKeyTests.swift`, `NudgeTests.swift`, `Tests/CreatorAppTests/AppInputTests.swift`, `ViewportGlueTests.swift`

**Interfaces:**
- Consumes: MetalUI C9 `StyledElement.hoverKeyRegion(_:)`, `onKeyPress(phases:action:)`, `KeyPress` (`.key`, `.characters`,
  `.modifiers`, `.phase`), `KeyPress.Result`.
- Produces: `GraphPanelInput.keyPressed(_ press: KeyPress) -> KeyPress.Result`, `GraphPanelInput.handleKey(_ key: KeyEvent) -> Bool`
  (public, what `keyPressed` and the tests call), and the pure `GraphPanelInput.keyEvent(key:characters:modifiers:isRepeat:) -> KeyEvent`
  that `keyPressed` builds its event with (a `KeyPress` can be made only by MetalUI, but `KeyEquivalent`, `EventModifiers`
  (= `Modifiers`) and the phase are public, so the conversion is tested on its own). Removed: `GraphPanelInput.releaseTextFocus`, `GraphTab`, the keymap's `tab` binding.

- [ ] **Step 1: Update the tests first**

These tests moved with the keys: they call `handleKey` where they called `handle(.keyDown(…))`, the `tab` and
`releaseTextFocus` tests are rewritten for C9, and one new test pins that `onInput` no longer runs the graph's keys.

**Modify** `Tests/CreatorEditorTests/GraphPanelInputTests.swift`

```swift
        #expect(input.handle(.keyDown(delete)))
        #expect(editor.graph.nodes.isEmpty)
        let letter = KeyEvent(charactersIgnoringModifiers: "q", characters: "q", timestamp: 2)
        #expect(!input.handle(.keyDown(letter)))
    }
```

```swift
        #expect(!input.handle(.keyDown(delete)), "the window's input fallback no longer runs the graph's keys")
        #expect(editor.graph.nodes.count == 1)
        #expect(input.handleKey(delete))
        #expect(editor.graph.nodes.isEmpty)
        let letter = KeyEvent(charactersIgnoringModifiers: "q", characters: "q", timestamp: 2)
        #expect(!input.handleKey(letter))
    }

    /// While the add-node palette is open its keys are the window's (a focused search field claims arrows before
    /// anything else, gap M5-h): the graph's own keys stand aside, and Esc closes the palette.
    @Test func theOpenPalettesKeysStayOnTheInputFallback() {
        let node = testNode(NumberTestNode.self, id: 1, at: .zero)
        let editor = makeEditor([node])
        editor.selection = [node.id]
        let input = GraphPanelInput(model: editor)
        editor.openPalette()
        let delete = KeyEvent(charactersIgnoringModifiers: "\u{7f}", characters: "\u{7f}", timestamp: 1)
        #expect(!input.handleKey(delete) && !input.handle(.keyDown(delete)))
        #expect(editor.graph.nodes.count == 1)
        let escape = KeyEvent(charactersIgnoringModifiers: "\u{1b}", characters: "\u{1b}", timestamp: 2)
        #expect(input.handle(.keyDown(escape)))
        #expect(editor.palette == nil)
    }
```

**Modify** `Tests/CreatorEditorTests/GraphPanelInputTests.swift`

```swift
        #expect(GraphPanelInput.keymap.bindings.map(\.spelling) == ["up", "down", "tab"])
```

```swift
        #expect(GraphPanelInput.keymap.bindings.map(\.spelling) == ["up", "down"])
```

**Modify** `Tests/CreatorEditorTests/GraphPanelInputTests.swift`

```swift
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
```

```swift
    /// Tab is the canvas region's key now (MetalUI C9, gap M5-b), not a keymap action: it reaches the graph only while
    /// the pointer is over the canvas with nothing focused, so a focused field (the inspector's, a comment being typed
    /// into on the canvas) gets it. It opens the palette over the visible canvas; unclaimed, it is focus traversal's.
    @Test func tabOpensThePaletteOnlyOverTheVisibleCanvas() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        let tab = KeyEvent(charactersIgnoringModifiers: "\t", characters: "\t", timestamp: 1)
        // Pointer not over the canvas: unclaimed, so focus traversal gets Tab.
        #expect(!input.handleKey(tab))
        #expect(editor.palette == nil && editor.isPanelVisible)
        input.hover(.active(Point(x: Pixels(40), y: Pixels(30))))
        #expect(input.handleKey(tab))
        #expect(editor.palette?.screenPosition == Vector2(40, 30))
        // Palette already open: unclaimed (no second palette).
        #expect(!input.handleKey(tab))
        editor.closePalette()
        // Hidden: unclaimed, so `GraphShowButton`'s Tab shortcut shows the panel.
        editor.toggleHidden()
        #expect(!editor.isPanelVisible)
        #expect(!input.handleKey(tab))
        #expect(editor.palette == nil && !editor.isPanelVisible)
    }
```

**Modify** `Tests/CreatorEditorTests/GraphPanelInputTests.swift`

```swift
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
        #expect(editor.transform.offset == .zero, "a plain drag through the canvas gesture box-selects; it doesn't pan")
    }
```

```swift
    /// Clearing a field's focus on a canvas press is the surface's, as a MetalUI C9 key region (gap M5-g); the gesture
    /// only reports the press.
    @Test func aPlainDragThroughTheCanvasGestureBoxSelectsAndDoesNotPan() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        input.canvasChanged(value(Vector2(10, 10), Vector2(10, 10)))
        input.canvasChanged(value(Vector2(10, 10), Vector2(40, 10)))
        input.canvasEnded(value(Vector2(10, 10), Vector2(40, 10)))
        input.canvasEnded(value(Vector2(5, 5), Vector2(5, 5)))
        #expect(editor.transform.offset == .zero, "a plain drag through the canvas gesture box-selects; it doesn't pan")
    }
```

**Modify** `Tests/CreatorEditorTests/GraphPanelInputTests.swift`

```swift
    /// (MetalUI `CI-F`), and leaves text focus alone: it isn't a click on the canvas.
    @Test func aMiddleDragThroughItsGesturePansAndKeepsTextFocus() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        var releases = 0
        input.releaseTextFocus = { releases += 1 }
        let gesture = input.middlePanGesture()
```

```swift
    /// (MetalUI `CI-F`).
    @Test func aMiddleDragThroughItsGesturePans() {
        let editor = makeEditor([])
        let input = GraphPanelInput(model: editor)
        let gesture = input.middlePanGesture()
```

**Modify** `Tests/CreatorEditorTests/GraphPanelInputTests.swift`

```swift
        #expect(editor.transform.offset == Vector2(30, 20) && editor.interaction == nil)
        #expect(releases == 0)
    }
```

```swift
        #expect(editor.transform.offset == Vector2(30, 20) && editor.interaction == nil)
    }
```

**Modify** `Tests/CreatorEditorTests/SelectionKeyTests.swift`

```swift
        #expect(input.handle(.keyDown(key("a", .command))))
```

```swift
        #expect(input.handleKey(key("a", .command)))
```

**Modify** `Tests/CreatorEditorTests/NudgeTests.swift`

```swift
        #expect(input.handle(.keyDown(key("\u{f703}", .shift))))
```

```swift
        #expect(input.handleKey(key("\u{f703}", .shift)))
```

**Modify** `Tests/CreatorAppTests/AppInputTests.swift`

```swift
        #expect(bindings.map(\.spelling) == ["f", "=", "shift-+", "+", "-", "up", "down", "tab"])
        #expect(bindings.prefix(5).allSatisfy { $0.action is ViewportKeyAction && $0.context == AppKeyContext.viewport })
        #expect(bindings.suffix(3).allSatisfy { $0.context == nil })
```

```swift
        #expect(bindings.map(\.spelling) == ["f", "=", "shift-+", "+", "-", "up", "down"])
        #expect(bindings.prefix(5).allSatisfy { $0.action is ViewportKeyAction && $0.context == AppKeyContext.viewport })
        #expect(bindings.suffix(2).allSatisfy { $0.context == nil })
```

**Modify** `Tests/CreatorAppTests/AppInputTests.swift`

```swift
        let f = KeyEvent(charactersIgnoringModifiers: "f", characters: "f", timestamp: 1)
        #expect(input.handleInput(.keyDown(f)))
        #expect(app.editor.transform != canvas)
```

```swift
        let f = KeyEvent(charactersIgnoringModifiers: "f", characters: "f", timestamp: 1)
        #expect(app.graphInput.handleKey(f), "the canvas region's onKeyPress runs the graph's F")
        #expect(app.editor.transform != canvas)
```

**Modify** `Tests/CreatorAppTests/AppInputTests.swift`

```swift
        #expect(input.handleAction(PaletteMove(step: 1)))
        #expect(!input.handleAction(GraphTab()), "the palette is already open")
    }

    @Test func theGraphsKeysArriveThroughTheInputFallback() async throws {
```

```swift
        #expect(input.handleAction(PaletteMove(step: 1)))
    }

    @Test func theGraphsKeysArriveThroughTheCanvasRegionNotTheInputFallback() async throws {
```

**Modify** `Tests/CreatorAppTests/AppInputTests.swift`

```swift
        #expect(input.handleInput(.keyDown(delete)))
        #expect(app.document.graph.nodes.isEmpty)
```

```swift
        #expect(!input.handleInput(.keyDown(delete)), "the window's input fallback is the open palette's, not the graph's")
        #expect(app.document.graph.nodes.count == 1)
        #expect(app.graphInput.handleKey(delete))
        #expect(app.document.graph.nodes.isEmpty)
```

**Modify** `Tests/CreatorAppTests/ViewportGlueTests.swift`

```swift
    @Test func aPressOnTheViewportOrTheCanvasReleasesTextFocus() async {
        let app = await makeApp()
        var released = 0
        app.releaseTextFocus = { released += 1 }
        app.viewport.pointerDown(at: ScreenPoint(500, 400), modifiers: [])
        app.viewport.pointerUp(at: ScreenPoint(500, 400))
        #expect(released == 1)
        app.graphInput.releaseTextFocus?()
        #expect(released == 2, "the graph panel's press goes through the same hook")
    }
```

```swift
    /// A press on the canvas clears text focus by itself (a MetalUI C9 key region, gap M5-g); the viewport's press still
    /// goes through the shell's hook (gap M4-a).
    @Test func aPressOnTheViewportReleasesTextFocus() async {
        let app = await makeApp()
        var released = 0
        app.releaseTextFocus = { released += 1 }
        app.viewport.pointerDown(at: ScreenPoint(500, 400), modifiers: [])
        app.viewport.pointerUp(at: ScreenPoint(500, 400))
        #expect(released == 1)
    }
```

**Create** `Tests/CreatorEditorTests/GraphKeyEventTests.swift`

```swift
import CreatorGeometry
import MetalUI
import Testing
@testable import CreatorEditor

/// `GraphPanelInput.keyPressed(_:)` builds its `KeyEvent` with `keyEvent(key:characters:modifiers:isRepeat:)`. A
/// `KeyPress` can be made only by MetalUI, so the conversion is pinned here on its own parts: a wrong mapping would break
/// every graph key and no `handleKey` test would notice.
@MainActor
struct GraphKeyEventTests {
    func command(_ key: KeyEquivalent, _ characters: String? = nil, _ modifiers: EventModifiers = [],
                 isRepeat: Bool = false) -> GraphKeyCommand? {
        let event = GraphPanelInput.keyEvent(key: key, characters: characters ?? String(key.character),
                                             modifiers: modifiers, isRepeat: isRepeat)
        return GraphKeyBindings.command(for: event, paletteOpen: false)
    }

    @Test func theEventCarriesTheKeysPartsUnchanged() {
        let event = GraphPanelInput.keyEvent(key: KeyEquivalent("n"), characters: "N", modifiers: [.command, .shift], isRepeat: true)
        #expect(event.charactersIgnoringModifiers == "n" && event.characters == "N")
        #expect(event.modifiers == [.command, .shift] && event.isRepeat)
        let plain = GraphPanelInput.keyEvent(key: .space, characters: " ", modifiers: [], isRepeat: false)
        #expect(plain.charactersIgnoringModifiers == " " && plain.modifiers.isEmpty && !plain.isRepeat)
    }

    @Test func theArrowsAreNudgesTheWayTheyPoint() {
        #expect(command(.upArrow) == .nudge(Vector2(0, -1), isRepeat: false))
        #expect(command(.downArrow) == .nudge(Vector2(0, 1), isRepeat: false))
        #expect(command(.leftArrow) == .nudge(Vector2(-1, 0), isRepeat: false))
        #expect(command(.rightArrow, nil, .shift) == .nudge(Vector2(10, 0), isRepeat: false))
    }

    /// A held arrow's auto-repeat joins the undo step its first press began, so `isRepeat` must reach the command.
    @Test func theRepeatFlagReachesTheNudge() {
        #expect(command(.rightArrow, nil, [], isRepeat: true) == .nudge(Vector2(1, 0), isRepeat: true))
        #expect(command(.rightArrow, nil, [], isRepeat: false) == .nudge(Vector2(1, 0), isRepeat: false))
    }

    @Test func deleteTabReturnEscapeAndSpaceAreTheirCommands() {
        #expect(command(.delete) == .deleteSelection)
        #expect(command(.deleteForward) == .deleteSelection)
        #expect(command(.tab) == .tab)
        #expect(command(.space) == .openPalette)
        #expect(command(.escape) == .cancel)
        #expect(command(.return) == nil, "Return is no graph key outside the palette")
        #expect(command(KeyEquivalent("q")) == nil)
    }

    @Test func theCommandChordsKeepTheirModifiers() {
        #expect(command(KeyEquivalent("a"), nil, .command) == .selectAll)
        #expect(command(KeyEquivalent("N"), "N", [.command, .shift]) == .addNote, "AppKit reports a shifted letter upper-case")
        #expect(command(KeyEquivalent("n"), "N", [.command, .shift]) == .addNote)
        #expect(command(KeyEquivalent("c"), nil, [.command, .shift]) == .addFrame)
        #expect(command(.downArrow, nil, .command) == .enterGroup)
        #expect(command(.upArrow, nil, .command) == .exitGroup)
        #expect(command(KeyEquivalent("a"), nil, .option) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "GraphPanelInputTests|SelectionKeyTests|NudgeTests|AppInputTests|ViewportGlueTests"`
Expected: FAIL to compile, "value of type 'GraphPanelInput' has no member 'handleKey'".

- [ ] **Step 3: Write the implementation**

**Replace the whole of** `Sources/CreatorEditor/GraphPanelInput.swift`

```swift
import CreatorGeometry
import MetalUI

/// The graph panel's input (spec §9): the canvas's gestures, and the window hooks for the MetalUI gaps C7 didn't
/// close, in one place (docs/metalui-gaps.md). The canvas's pointer input is MetalUI C7's; the behaviour is the
/// model's (`EditorModel+Pointer`), and this type only turns MetalUI values into the model's:
/// - `canvasGesture()`: one `DragGesture(minimumDistance: 0)` carries clicks, moves, box selection and
///   wiring. Its values give the press point (`startLocation`) and the modifiers held at each change
///   (`DragGesture.Value.modifiers`, the press's at the first), so Shift-click and ⇧/⌥-drag read the press's own
///   modifiers, and the model tells a click from a drag (`EditorModel.dragThreshold`). It isn't a
///   `SpatialTapGesture` plus a drag, as the viewport's is: a tap's value has no modifiers, and a click must know
///   whether ⇧ was held (gap GI-a).
/// - `middlePanGesture()`: a `DragGesture(minimumDistance: 0, button: .middle)` pans (`EditorModel.middleDragged`),
///   in the middle button's own arena (MetalUI `CI-F`), as the viewport's middle drag does (VC3). A plain drag
///   box-selects (the user's Gate G answer (b), 2026-10-09), so this and two-finger scroll are the canvas's pans.
/// - `scrolled(_:)`, from the canvas's `.onScrollWheel`: two-finger scroll and the wheel pan, ⌘-scroll zooms
///   about the pointer (`EditorModel.scrolled(by:at:modifiers:phase:)`, phases from `scrollPhase(of:)`).
/// - `pinchGesture()`: a `MagnifyGesture` zooms about where the pinch began (`EditorModel.pinchChanged`).
/// - The cursor is the model's (`EditorModel.canvasCursor`, a closed hand while a middle drag pans); `GraphCanvas`
///   sets it.
///
/// The canvas's keys and its text focus are MetalUI C9's (key and focus scoping), not stopgaps:
/// - `keyPressed(_:)`, from the canvas surface's `.onKeyPress` (`CanvasSurface`): the graph's keys. The surface is a
///   `hoverKeyRegion`, so with nothing focused the keys go to the canvas under the pointer, and a focused field (the
///   inspector's, the library's search, the canvas's own comment editor) keeps every key, wherever the pointer is
///   (gap M5-b). A press on the canvas also clears a field's focus (gap M5-g).
///
/// Two stopgaps remain, for MetalUI gaps C9 did not close:
/// - the palette's keys: its ↑/↓ and the keys of the open palette's search field go through the window keymap
///   (`keymap`, `handleAction`) and `onInput` (`handle(_:)`), because a focused single-line field claims arrows before
///   `onInput` (gap M5-h, which C9 answers with `onKeyPress` on the field; not adopted here);
/// - the floating palette's "click outside": a press of any button reaching `onInput` outside the
///   palette closes it (`handle(_:)`), because MetalUI's only overlay that dismisses itself is
///   `.popover`, with its own chrome (gap EP-b).
@MainActor
public final class GraphPanelInput {
    public let model: EditorModel

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
    }

    /// Install as (or merge into) `Window.keymap`, with `handleAction(_:)` in `Window.onAction`.
    public static var keymap: Keymap {
        Keymap {
            KeyBinding("up", PaletteMove(step: -1))
            KeyBinding("down", PaletteMove(step: 1))
        }
    }

    /// Install from `Window.onAction`. Runs a palette move while the palette is open. Otherwise it returns false, and
    /// MetalUI passes the key on (to a focused field, Tab focus traversal, a `GraphShowButton` shortcut or `onInput`)
    /// as if it were unbound.
    public func handleAction(_ action: any Action) -> Bool {
        guard let move = action as? PaletteMove, model.palette != nil else { return false }
        model.movePaletteHighlight(by: move.step)
        return true
    }

    /// Install from `Window.onInput` (`install(on:)` does). Returns true when the event was used: the open palette's keys
    /// (the rest of the graph's keys are `keyPressed(_:)`'s, scoped by MetalUI C9). Every primary press reaches
    /// `onInput` (MetalUI claims none, except one in a text field or on a slider), and so does every other button's
    /// press but a right-click that opens a context menu, so the floating palette's "click outside" is read here too.
    /// Modifier changes aren't tracked: a press reads its own (`canvasGesture()`).
    public func handle(_ event: InputEvent) -> Bool {
        switch event {
        case .keyDown(let key):
            guard model.palette != nil, let command = GraphKeyBindings.command(for: key, paletteOpen: true) else { return false }
            return model.perform(command)
        case .mouseDown(let mouse), .rightMouseDown(let mouse), .otherMouseDown(let mouse):
            // Any button's press outside the floating palette closes it. Never claimed, so the press goes on.
            model.windowPressed(at: Self.vector(mouse.position))
            return false
        default:
            return false
        }
    }

    /// The graph's keys, from the canvas surface's `onKeyPress` (MetalUI C9: the surface is a key region, so these
    /// arrive only while the pointer is over the canvas and nothing is focused; a focused
    /// field anywhere keeps its keys). `.handled` claims the key, `.ignored` lets it go on (the palette's own keys are
    /// `handle(_:)`'s, and Tab only counts over the canvas: unclaimed it moves focus).
    public func keyPressed(_ press: KeyPress) -> KeyPress.Result {
        let key = Self.keyEvent(key: press.key, characters: press.characters, modifiers: press.modifiers,
                                isRepeat: press.phase.contains(.repeat))
        return handleKey(key) ? .handled : .ignored
    }

    /// The `KeyEvent` the graph's bindings read, from a `KeyPress`'s parts. `KeyPress.key` is the first character the
    /// unmodified layout reports (`KeyEquivalent` spells the arrows, Delete, Tab, Return and Esc as AppKit's
    /// characters, which `GraphKeyBindings` matches); `isRepeat` is what splits a held arrow's nudges from a new step.
    /// Pure, so the mapping is tested without a window. The timestamp is unused by the bindings.
    public static func keyEvent(key: KeyEquivalent, characters: String, modifiers: EventModifiers, isRepeat: Bool) -> KeyEvent {
        KeyEvent(charactersIgnoringModifiers: String(key.character), characters: characters, modifiers: modifiers,
                 isRepeat: isRepeat, timestamp: 0)
    }

    /// Runs the graph's command for `key`, if it has one and the palette isn't open. Returns whether it was used.
    public func handleKey(_ key: KeyEvent) -> Bool {
        guard model.palette == nil, let command = GraphKeyBindings.command(for: key, paletteOpen: false) else { return false }
        // Tab opens the palette at the pointer; with the pointer not reported over the canvas it is focus traversal's.
        if command == .tab, model.pointerLocation == nil { return false }
        return model.perform(command)
    }

    /// The canvas's one press-and-drag gesture: clicks, moves, box selection and wiring. A zero minimum
    /// distance, so its first change is the press itself, with the press's modifiers.
    public func canvasGesture() -> DragGesture {
        DragGesture(minimumDistance: Pixels(0))
            .onChanged { [self] value in canvasChanged(value) }
            .onEnded { [self] value in canvasEnded(value) }
    }

    /// The gesture moved (its first change is the press). A press also clears a focused field's focus, because the
    /// canvas surface is a key region (MetalUI C9, gap M5-g).
    func canvasChanged(_ value: DragGesture.Value) {
        let start = Self.vector(value.startLocation)
        model.pointerDragged(from: start, to: Self.vector(value.location), modifiers: Self.canvasModifiers(value.modifiers))
    }

    /// The gesture ended: a release, or a click's only report when no change came first.
    func canvasEnded(_ value: DragGesture.Value) {
        let start = Self.vector(value.startLocation)
        model.pointerReleased(from: start, at: Self.vector(value.location), modifiers: Self.canvasModifiers(value.modifiers))
    }

    /// The canvas's middle-button drag: pans. A zero minimum distance, so the closed hand shows from the press (a
    /// middle press never clicks). Text focus is left alone: a pan isn't a click on the canvas.
    public func middlePanGesture() -> DragGesture {
        DragGesture(minimumDistance: Pixels(0), button: .middle)
            .onChanged { [self] value in middleChanged(value) }
            .onEnded { [self] value in middleEnded(value) }
    }

    /// The middle drag moved (its first change is the press).
    func middleChanged(_ value: DragGesture.Value) {
        model.middleDragged(from: Self.vector(value.startLocation), to: Self.vector(value.location))
    }

    /// The middle button was released.
    func middleEnded(_ value: DragGesture.Value) {
        model.middleReleased(from: Self.vector(value.startLocation), at: Self.vector(value.location))
    }

    /// A scroll over the canvas, from its `.onScrollWheel`: the delta, the pointer in canvas-local points, the
    /// modifiers and the phase go to the model. Returns `true` (claimed), so the viewport beneath never sees it.
    public func scrolled(_ event: ScrollEvent) -> Bool {
        model.scrolled(by: Self.vector(event.delta), at: Self.vector(event.location),
                       modifiers: Self.canvasModifiers(event.modifiers), phase: Self.scrollPhase(of: event))
    }

    /// The canvas's pinch: zooms by the cumulative magnification about where it began (`startLocation`).
    public func pinchGesture() -> MagnifyGesture {
        MagnifyGesture()
            .onChanged { [model] value in
                model.pinchChanged(magnification: value.magnification, centre: Self.vector(value.startLocation))
            }
            .onEnded { [model] _ in model.pinchEnded() }
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

**Replace the whole of** `Sources/CreatorEditor/CanvasSurface.swift`

```swift
import MetalUI

/// The graph canvas's surface: the layers under the zoom and pan transform, one press-and-drag gesture for everything
/// (hit testing is the model's), a middle-button drag that pans, a pinch, the scroll wheel, the cursor, the context
/// menu (Add Note, Frame Selection at the point it opened) and pointer tracking for the palette. All input goes
/// through `GraphPanelInput` to the model.
///
/// It is a MetalUI C9 key region (`hoverKeyRegion`), which does the work of two stopgaps: with nothing focused, keys go
/// to the canvas under the pointer, where `onKeyPress` runs the graph's keys (`GraphPanelInput.keyPressed(_:)`); a
/// focused field anywhere keeps its keys; and a primary press on the canvas clears a field's focus, which commits a
/// typed value. A field inside this subtree would pass its keys up to the handler, so the comment editor is the
/// surface's sibling (`GraphCanvas`).
struct CanvasSurface: Component {
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
        .gesture(input.middlePanGesture())
        .gesture(input.pinchGesture())
        .contentShape(Rectangle())
        .hoverKeyRegion()
        .onKeyPress(phases: [.down, .repeat]) { press in input.keyPressed(press) }
        .onContinuousHover { phase in input.hover(phase) }
        .onScrollWheel { event in input.scrolled(event) }
        .contextMenu { (location: Point<Pixels>?) in
            for item in CanvasMenuItem.allCases {
                Button(item.title) { model.choose(item, at: location.map { GraphPanelInput.vector($0) }) }
                    .disabled(!model.isEnabled(item))
            }
        }
        .pointerStyle(model.canvasCursor?.pointerStyle)
    }
}
```

**Delete** `Sources/CreatorEditor/GraphTab.swift`

**Modify** `Sources/CreatorApp/AppModel.swift`

```swift
        graphInput.releaseTextFocus = { [weak self] in self?.releaseTextFocus?() }
        editor.placement
```

```swift
        editor.placement
```

**Modify** `Sources/CreatorApp/AppInput.swift`

```swift
/// - keymap: the viewport's F, + and − in the `AppKeyContext.viewport` context, so they type into a focused
///   panel field instead (gap M4-a), then the graph's palette arrows and Tab (gaps M5-h, M5-b);
/// - `onAction`: the graph's actions first, then the viewport's keys, except while the pointer is over the graph
///   canvas: there F, + and − fall through to the graph's own keys (F frames the graph's selection, + and − zoom
///   the canvas; spec 2026-10-09 §3), because keys aren't scoped to a hovered element until MetalUI C9 (gaps M4-a,
///   M5-b);
/// - `onInput`: the graph's keys;
/// - text focus: `AppModel.releaseTextFocus` clears the window's focus, for canvas and viewport presses (gap M5-g).
```

```swift
/// - keymap: the viewport's F, + and − in the `AppKeyContext.viewport` context, so they type into a focused
///   panel field instead (gap M4-a), then the graph's palette arrows (gap M5-h);
/// - `onAction`: the graph's actions first, then the viewport's keys, except while the pointer is over the graph
///   canvas: there F, + and − fall through to the graph's own keys (F frames the graph's selection, + and − zoom
///   the canvas; spec 2026-10-09 §3). The graph's keys are scoped by MetalUI C9 (the canvas is a key region whose
///   `onKeyPress` runs them), so this veto is only the viewport's side of M4-a, left until the viewport adopts C9;
/// - `onInput`: the open palette's keys and its click-outside;
/// - text focus: `AppModel.releaseTextFocus` clears the window's focus for a viewport press (gap M4-a); the canvas
///   clears it itself, as a key region (gap M5-g).
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "GraphPanelInputTests|SelectionKeyTests|NudgeTests|AppInputTests|ViewportGlueTests"`
Expected: PASS.

- [ ] **Step 5: Lint, run everything, commit**

Run: `swiftlint lint --strict` (zero violations), then the full suite: expected master + 22 + 6 + 5 + 6 = master + 39 tests.

```bash
git add -A Sources Tests
git commit -m "feat(editor): the graph's keys and text focus go through the canvas key region (MetalUI C9)"
```

### Task 5: Documentation, the gaps and the human checks

No code. CLAUDE.md, the roadmap, `docs/metalui-gaps.md`, the comments spec's Errata and the human checks say what is now
true. The statuses below are the ones that hold once C9 is on MetalUI master and Tasks 1 to 4 are merged; they name no
MetalUI commit because C9's merge commit does not exist yet (the executor may add it to the gap rows).

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/roadmap.md`
- Modify: `docs/metalui-gaps.md`
- Modify: `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` (Errata)
- Modify: `docs/verification/human-checks.md` (group CT; CM-7)

- [ ] **Step 1: CLAUDE.md**

**Modify** `CLAUDE.md`

```
Canvas comments (sub-project B of the same spec, §7: sticky notes and comment frames, plan `2026-10-09-comments.md`)
code is done; its human checks (group CM) are pending.

```

```
Canvas comments (sub-project B of the same spec, §7: sticky notes and comment frames, plan `2026-10-09-comments.md`)
code is done; its human checks (group CM) are pending.
Typing on the canvas (spec §8: a double click on a note or a frame's title bar edits it in place; plan
`2026-10-10-comments-canvas-typing.md`; the graph's keys and text focus on MetalUI C9's key regions) code is done; its human
checks (group CT) are pending.

```

**Modify** `CLAUDE.md`

```
  Its input (MetalUI C7 gestures, and the key and focus stopgaps) lives only in `GraphPanelInput`. A double click on
  a node (two plain clicks on its body at most `EditorModel.doubleClickInterval`, 0.4 s as the groups spec's §6 says,
  not macOS's 500 ms default, and `doubleClickSlop`, 4 points, apart, timed by the injectable `now`; gap S5-b) presses
  its first inspector button in `doubleClickActions` ("Edit sketch"; `nodeDoubleClicked(_:)`). While a sketch is open
  the app ignores it (`AppModel.handle(_:)`'s guard).

```

```
  Its input (MetalUI C7 gestures, C9 key scoping, and the palette's stopgaps) lives only in `GraphPanelInput`. A double
  click on a node (two plain clicks on its body at most `EditorModel.doubleClickInterval`, 0.4 s as the groups spec's §6
  says, not macOS's 500 ms default, and `doubleClickSlop`, 4 points, apart, timed by the injectable `now`; gap S5-b)
  presses its first inspector button in `doubleClickActions` ("Edit sketch"; `nodeDoubleClicked(_:)`); the same pairing on
  a note or a frame's title bar, not its edge band (a `ClickTarget`, kept in `lastClick`), starts editing it in place
  (`beginEditing(_:)`). While a sketch is open the app ignores it (`AppModel.handle(_:)`'s guard).

```

**Modify** `CLAUDE.md`

```
  (`CommentInspectorView`); text commits through `PendingEntry.textCommit`, on focus loss or any
  model commit (no ⌘↩ chord, gap CM-a). Comment views draw no shadows
```

```
  (`CommentInspectorView`); text commits through `PendingEntry.textCommit`, on ⌘↩ (`CommentKeys.commitsNote`, an
  `onKeyPress` on the box: MetalUI C9, gap CM-a), on focus loss or any model commit.
  Typing on the canvas: `EditorModel.commentEdit` (`CommentEdit`) is the comment being edited in place, `commentEditor`
  (`CommentEditor`) where its field goes (a note's rectangle, a frame's title bar, in display canvas points). Its draft
  rides the model's one `pendingEntry` (`EditorModel+CommentEditing`: `beginEditing`, `commentDraftChanged`,
  `commitCommentEdit`, `cancelCommentEdit`), so a canvas press, a selection or level change, hiding the panel, undo, save
  and export commit it, as one `setNoteText` / `setFrameTitle` step (the inspector's own paths), and a field typed into
  elsewhere (`notePendingEntry`) commits it first. `CommentEditorLayer` draws the field (`CommentEditorField`: a
  `TextEditor`, ⌘↩ commits, or a `TextField`, Return commits; Esc cancels; losing focus commits) under the canvas's own
  zoom and pan, as the sibling of `CanvasSurface`, the canvas's key region: never inside it, or the field's keys would
  reach the canvas's handler. Comment views draw no shadows
```

**Modify** `CLAUDE.md`

```
(`pinchChanged`); the cursor is `EditorModel.canvasCursor` (a closed hand while a middle drag pans). Its key, focus
and palette stopgaps live only in
`GraphPanelInput` too, and `install(on:)` chains onto the window's existing handlers.

```

```
(`pinchChanged`); the cursor is `EditorModel.canvasCursor` (a closed hand while a middle drag pans). Its keys and text
focus are MetalUI C9's: `CanvasSurface` is a `hoverKeyRegion` whose one `onKeyPress` runs the graph's keys
(`GraphPanelInput.keyPressed(_:)`), so with nothing focused they act where the pointer is, a focused field (the inspector's,
the library's, the canvas's comment editor) keeps every key wherever the pointer is, and a canvas press clears a field's focus.
The open palette's ↑/↓ (a keymap action, gap M5-h), its keys on `onInput` and its click-outside (gap EP-b) are the stopgaps
left in `GraphPanelInput`, and `install(on:)` chains onto the window's existing handlers.

```


- [ ] **Step 2: The roadmap**

**Modify** `docs/superpowers/roadmap.md`

```
| — | Comments: typing on the canvas — edit a note's text or a frame's title in place on the canvas (spec §8) | ⏳ after MetalUI C9 + the canvas double-click (C16) | Comments (B); gaps CM-a, S5-b |
```

```
| — | Comments: typing on the canvas — edit a note's text or a frame's title in place (spec §8, Errata (B: typing on the canvas), plan `2026-10-10-comments-canvas-typing.md`): a double click on a note or a frame's title bar, a `TextEditor` / `TextField` over it at the canvas's zoom in both docks, committed on focus loss, a canvas press, ⌘↩ (note) or Return (title), cancelled by Esc; the inspector's note box commits on ⌘↩ too; the graph's keys and text focus moved onto the canvas's MetalUI C9 key region | ✅ code done; human checks CT pending | Comments (B); MetalUI C9 (adopts M5-b, M5-g and CM-a; M5-h not used); the double click is still S5b's synthesised pairing (S5-b, until C16); new gap CT-a |
```

**Modify** `docs/superpowers/roadmap.md`

```
| MetalUI C9 key and focus scoping: M4-a/M5-b hover- or region-scoped keys + element size, M5-g press ends editing, M5-h ↑/↓ in fields, M4-b redraw during animation | MetalUI session | 🔄 in progress since 2026-10-09; also onGeometryChange, the for-loop builder fix (M4-b; until then `ForEach` works), TimelineView, focus-on-click |
```

```
| MetalUI C9 key and focus scoping: M4-a/M5-b hover- or region-scoped keys + element size, M5-g press ends editing, M5-h ↑/↓ in fields, M4-b redraw during animation | MetalUI session | 🔄 in progress since 2026-10-09; also onGeometryChange, the for-loop builder fix (M4-b; until then `ForEach` works), TimelineView, focus-on-click; adopted for the graph canvas's keys and text focus (M5-b, M5-g) and the note box's ⌘↩ (CM-a) by the row "Comments: typing on the canvas" (executes after C9 merges to MetalUI master); the viewport's side (M4-a, M5-g for viewport presses) and the palette's ↑/↓ (M5-h) are not adopted |
```


- [ ] **Step 3: docs/metalui-gaps.md**

The summary table first, then each entry, then the new gap.

**Modify** `docs/metalui-gaps.md`

```
| M5-b | Hover- or region-scoped key bindings | C9 | 🔄 open; C9 in progress (`feat/key-focus`) |
```

```
| M5-b | Hover- or region-scoped key bindings | C9 | ✅ fixed by C9 (`feat/key-focus`: `hoverKeyRegion`, `onKeyPress`), adopted for the graph canvas (Comments typing plan); the viewport still runs its pointer veto (M4-a) |
```

**Modify** `docs/metalui-gaps.md`

```
| M5-g | A press elsewhere ends text editing | C9 | 🔄 open; C9 in progress (`feat/key-focus`) |
```

```
| M5-g | A press elsewhere ends text editing | C9 | ✅ fixed by C9 (`feat/key-focus`: a key region clears a field's focus on a press), adopted for the graph canvas (Comments typing plan); viewport presses still call `AppModel.releaseTextFocus` (M4-a); a press outside every region resigns nothing, by design (CT-a) |
```

**Modify** `docs/metalui-gaps.md`

```
| M5-h | ↑/↓ in a focused single-line field | C9 | 🔄 open; C9 in progress (`feat/key-focus`) |
```

```
| M5-h | ↑/↓ in a focused single-line field | C9 | ✅ fixed by C9 (`onKeyPress(keys:)` on the field), not adopted: the palette's ↑/↓ stay a keymap action (`PaletteMove`) until the palette is moved onto it |
```

**Modify** `docs/metalui-gaps.md`

```
| CM-a | `TextEditor` has no commit key (⌘↩ or `onSubmit`) | lands with C9 | ✅ answered: lands with C9 |
```

```
| CM-a | `TextEditor` has no commit key (⌘↩ or `onSubmit`) | C9 | ✅ fixed by C9 (KF-Z: ⌘↩ is no editing key of a `TextEditor`, so an `onKeyPress` for it commits), adopted by the inspector's note box and the canvas editor (Comments typing plan) |
| CT-a | A press outside every key region resigns no focus, and nothing asks it to without taking over key routing | none yet | ⏳ reported 2026-10-10 (Comments typing plan), not queued |
| CT-b | No way to set a text field's selection or caret (a field focused from code opens with its caret at the start) | none yet | ⏳ reported 2026-10-10 (Comments typing plan), not queued |
```

**Modify** `docs/metalui-gaps.md`

```
  Wanted: a key context an element contributes while hovered (as M4-a asks for the viewport), or `onKeyPress` on a
  focus region.
```

```
  Wanted: a key context an element contributes while hovered (as M4-a asks for the viewport), or `onKeyPress` on a
  focus region.
  **Fixed by MetalUI C9** (`feat/key-focus`, KF-B to KF-E: `onKeyPress`, `hoverKeyRegion`; a key region's keys follow the
  pointer while nothing is focused, and a focused field keeps every key) and **adopted for the graph canvas** (Comments typing
  plan Task 4): `CanvasSurface` is a key region and its one `onKeyPress` runs the graph's keys, Tab included (it no longer opens
  the palette from a focused field; `GraphTab` and the keymap's `tab` binding are gone). The viewport's F, + and − keep
  `AppInput`'s pointer veto until the viewport adopts C9 (M4-a).
```

**Modify** `docs/metalui-gaps.md`

```
A SwiftUI-like rule (a press on
  non-focusable content resigns the field), or a `.focusable(false)`-style "clears focus" modifier, would fix it.
```

```
A SwiftUI-like rule (a press on
  non-focusable content resigns the field), or a `.focusable(false)`-style "clears focus" modifier, would fix it.
  **Fixed by MetalUI C9** as an opt-in, not a default (KF-G keeps SwiftUI's rule that a press elsewhere resigns nothing):
  a primary press inside a `hoverKeyRegion` clears a field's focus, unless it lands on a text field. **Adopted for the
  graph canvas** (Comments typing plan Task 4): the canvas surface is a key region, `GraphPanelInput.releaseTextFocus` is
  gone, and a canvas press ends a typed value and a canvas edit. Viewport presses still call `AppModel.releaseTextFocus`
  (the viewport adopts C9 with M4-a). A press outside every region still resigns nothing: gap CT-a.
```

**Modify** `docs/metalui-gaps.md`

```
SwiftUI's `onKeyPress` on the field would fix it.
```

```
SwiftUI's `onKeyPress` on the field would fix it.
  **Fixed by MetalUI C9** (`onKeyPress(keys: [.upArrow, .downArrow])` on the field runs before the field's own keys, KF-C
  item 4). **Not adopted** by the Comments typing plan, which uses no single-line field's arrows: the palette's `PaletteMove`
  keymap action stays until the palette moves onto it.
```

**Modify** `docs/metalui-gaps.md`

```
Logged with C9 (key and focus scoping), which owns the key
  handling.
```

```
Logged with C9 (key and focus scoping), which owns the key
  handling.
  **Fixed by MetalUI C9** (KF-Z, `feat/key-focus`): a Return with the platform's shortcut modifier is not an editing key of a
  `TextEditor`, and an `onKeyPress(keys: [.return])` handler runs before the editor's keys, so
  `press.modifiers.contains(.command) ? commit() : .ignored` commits on ⌘↩ while plain Return still breaks the line (no
  MetalUI-only hook was needed). **Adopted** (Comments typing plan Task 3): `CommentKeys.commitsNote` is that test, used by
  the inspector's note box (`CommentTextEntry`) and the canvas editor (`CommentEditorField`). The spec's CM Errata line
  "not on ⌘↩" is superseded (Errata (B: typing on the canvas)).
```

**Modify** `docs/metalui-gaps.md`

```
  camera change; S5c-6 is where that is looked at, and the labels are not capped or culled by count (a silent cap would hide
  dimensions). Sent to the MetalUI session (the standing rule: every MetalUI gap goes to that session to implement); the
  repository is never edited from here.
```

```
  camera change; S5c-6 is where that is looked at, and the labels are not capped or culled by count (a silent cap would hide
  dimensions). Sent to the MetalUI session (the standing rule: every MetalUI gap goes to that session to implement); the
  repository is never edited from here.

## Typing on the canvas (Comments typing plan), 2026-10-10

Labelled CT-a… so they don't clash with the C7 items 1–5 or the M4-a…, M5-a…, M6-a…, CM-a… entries.

- **CT-a. A press outside every key region resigns no focus, and nothing asks it to without taking over key routing.**
  Typing a note or a title on the canvas should end when the user presses anywhere else (spec §8: "on a press elsewhere").
  C9 gives a key region (`hoverKeyRegion`): a primary press inside it clears a field's focus, but a region also routes keys
  by hover, and a press outside every region resigns nothing (KF-G, SwiftUI's rule). MetalCreator uses what exists and works
  around nothing: the canvas is a region (a canvas press ends the edit), viewport presses still call `window.focus(nil)`
  (M4-a's hook), and every model commit ends it (a selection or level change, hiding the panel, undo, save, export, another
  field being typed into). A press on inert chrome (the glass padding, the header's gaps, the inspector's empty areas)
  leaves the editor open and focused; the next press on the canvas, the viewport or a control ends it. Wanted: an opt-in
  that makes a container resign focus on a primary press inside it without routing keys, for example
  `.resignsFocusOnPress()` (or `hoverKeyRegion(routesKeys: false)`), which MetalCreator would put on the app's root. Human
  check CT-11 records what a press on inert chrome does. Status: reported to the controller for the MetalUI session (the
  standing rule: every MetalUI gap goes to that session to implement); the repository is never edited from here.
- **CT-b. No way to set a text field's selection or caret, so an editor opened from code cannot open with its text
  selected or its caret at the end.** A double click that starts editing a note or a title in place wants the title's
  whole text selected (as a rename does) and a note's caret at the end of its text. `TextField` and `TextEditor` have no
  selection binding (SwiftUI's `TextField(text:selection:)` with `TextSelection`, macOS 15), and a field focused from code
  (`FocusState` written in `onAppear`) opens with its caret at the start of its text and nothing selected (measured in the
  C9 probe: a `.textInput("X")` into a freshly focused field gives `Xhello`). MetalCreator works around nothing: the editor
  opens as MetalUI opens it, and the user presses ⌘A or ⌘→ (or clicks) to select or move the caret. Wanted: a selection
  binding on both fields, or `FocusState`-style `selectAll()` / caret-position on focus. Human check CT-1 records what the
  user sees. Status: reported to the controller for the MetalUI session; the repository is never edited from here.
```


- [ ] **Step 4: The comments spec's Errata**

**Modify** `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md`

```
  old one. The inspector's comment page shows only when no node is selected.

```

```
  old one. The inspector's comment page shows only when no node is selected. (The ⌘↩ part is superseded by Errata (B:
  typing on the canvas): MetalUI C9 answered gap CM-a.)

```

**Modify** `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md`

```
## Errata (C2)

```

```
## Errata (B: typing on the canvas)

Plan `2026-10-10-comments-canvas-typing.md`; MetalUI C9 (`feat/key-focus`).

- §8 Typing on the canvas is built. A double click (S5b's recogniser, still synthesised: gap S5-b, until MetalUI C16) on
  a note, or on a frame's title bar (not its 6 pt edge band, which grabs the frame), starts editing in place: a
  multi-line `TextEditor` over the note, a single-line `TextField` over the title bar, drawn under the canvas's own zoom
  and pan, so it lies over the comment in both docks at any zoom. The comment becomes the whole selection.
- §7 Editing (amends Errata (B: comments)): a note's text now commits on ⌘↩ as well as on focus loss, in the canvas
  editor and in the inspector's box (an `onKeyPress`; gap CM-a closed). A title commits on Return. Esc cancels a canvas
  edit: the comment keeps what it held. A press elsewhere on the canvas, a selection or level change, hiding the panel,
  undo, saving and exporting commit it. An empty or blank title is refused as in the inspector ("A frame needs a title.")
  and the old title returns; a line break pasted into a title becomes a space. Every commit is one `setNoteText` /
  `setFrameTitle` step, the inspector's own path ("Edit Note", "Edit Frame"), so the two surfaces share one undo story.
- One pending entry at a time: a canvas draft is the model's `pendingEntry`. Beginning an edit commits whatever was
  typed before (in the inspector, or on another comment), and a field typed into while the canvas is being typed into (the
  inspector's) commits the canvas edit first, so the two never fight over one comment's text.
- Keys: the graph canvas is a MetalUI C9 key region carrying one `onKeyPress` for the graph's keys, and the comment
  editor is its sibling, not its child. While a canvas field has focus, the canvas's keys (Delete, arrows, Space, ⌘A,
  F, ⌘C/⌘V/⌘X/⌘D, ⌘G, ⌘⇧N, ⌘⇧C, Tab) cannot act on the canvas, because a focused element keeps every key. Consequence,
  deliberate: the graph's keys act only while the pointer is over the canvas and nothing is focused (the canvas is not
  focusable, so a click leaves no focus on it), not from anywhere in the window; a click and then moving the pointer to
  the inspector or the viewport ends Delete, the arrows and ⌘A. The open palette's keys and the viewport's F, + and − are unchanged (M5-h and the viewport's side of
  M4-a stay open). A canvas press clears a field's focus (M5-g, adopted for the canvas).
- A press outside every key region (inert chrome) leaves a canvas edit open: gap CT-a.

## Errata (C2)

```


- [ ] **Step 5: The human checks**

**Modify** `docs/verification/human-checks.md`

```
  again and press ⌘↩: nothing is bound to it (**record what the field does with it**, gap CM-a); click away and the
  text commits.
```

```
  again and press ⌘↩: the text commits at once (gap CM-a, closed by MetalUI C9; Return alone still breaks the line);
  click away and the text commits.
```

**Modify** `docs/verification/human-checks.md`

```
## Group GR — groups: the editor (C2)

```

```
## Group CT — typing on the canvas (Comments typing plan)

**Status: PENDING.** Plan `2026-10-10-comments-canvas-typing.md`, spec `2026-10-09-selection-groups-comments-design.md` §8
and its Errata (B: typing on the canvas). The tests pin the model and the headless frames; these check the double click,
the focus and the keys through a real window (MetalUI C9's own tests pin the key routing; the app has no headless
window, gap M6-e). Run `swift run MetalCreatorApp` on a saved bracket with a note and a frame; CT-5 docks left.

- [ ] **CT-1 A note.** Double click a note: a white-backed editor appears exactly over it, with the caret in it, and the
  note's text is in it, the caret at its start and nothing selected (gap CT-b: **record it**; ⌘A selects it all). Type two lines (Return breaks the line), press ⌘↩: the editor closes, the note shows both lines,
  and one ⌘Z puts the old text back. **Observe each of these separately and write each down:** focus is in the field the
  moment it appears (no extra click); Return breaks the line and commits nothing; ⌘↩ commits; Esc cancels (CT-2);
  clicking away commits (CT-2). Pinned: `CommentTypingTests`, `CommentDoubleClickTests`, `CommentEditorRenderTests`.
  **Observed:**
- [ ] **CT-2 Ending an edit.** Four separate observations, each written down, for a note: **Esc** closes the editor and
  the note keeps its old text, with nothing to undo; **⌘↩** commits and closes; **Return** breaks the line and the editor
  stays open; **a click away** (the next lines) commits. For a frame's title: **Return** commits, **Esc** cancels, **a
  click away** commits. Start a note edit and type, then Esc as above. Type again and click empty canvas, then another node, then the 3D viewport, then the inspector's
  accent swatch: each commits the text (one ⌘Z each). Type, then ⌘S: the saved file has the text. Pinned: `CommentTypingTests`.
  **Observed:**
- [ ] **CT-3 A frame's title.** Double click a frame's title bar: a one-line field over the bar with the title in it. Type
  "Front plate", Return: it commits (one ⌘Z undoes it). Esc cancels. Clear it and press Return: "A frame needs a title."
  appears and the old title returns. Paste text containing a line break: it becomes a space. A double click on the
  frame's edge band or its inside starts no edit, and dragging the title bar still moves the frame and its nodes.
  Pinned: `CommentTypingTests`, `CommentDoubleClickTests`. **Observed:**
- [ ] **CT-4 The graph's keys stand aside.** With an editor focused and nodes selected on the canvas: Delete deletes
  characters and no node; arrows move the caret and no node; Space and F type; ⌘A selects the text; ⌘C, ⌘X and ⌘V use the
  text; ⌘⇧N adds no note, ⌘G, ⌘D and ⌘⇧C do nothing to the canvas; Tab does not open the add-node palette. Afterwards,
  with the pointer over the canvas and nothing focused, Delete, arrows, ⌘A, F and Space act again (Tab opens the palette);
  with the pointer over the viewport or the inspector's empty space they do not (User decision 1: **record it**). Pinned:
  `GraphPanelInputTests`, `SelectionKeyTests`, `NudgeTests`. **Observed:**
- [ ] **CT-5 Both docks.** Repeat CT-1 and CT-3 docked bottom and docked left: the editor lies exactly over the note and
  over the title bar (the left dock draws both transposed), and typing, ⌘↩, Return and Esc behave the same. Pinned:
  `CommentEditorRenderTests`, `CommentTypingTests`. **Observed:**
- [ ] **CT-6 Zoom.** At 25 %, 100 % and 300 % (⌘-scroll, or the header buttons) repeat CT-1 and CT-3: the editor's text
  is scaled as the note's is and lies over it, typing works, and a click inside the editor places the caret under the
  pointer (the editor is drawn under a scale effect). **Record** whether the title field is usable at 25 % and whether the
  text is soft at 300 % (MetalUI divergence 106: text under a scale effect is resampled). Pinned: `CommentEditorRenderTests`.
  **Observed:**
- [ ] **CT-7 Themes.** In each of the three built-in themes the editor's background, text and focus ring are readable
  over the note's tint and the title bar's tint, and Esc or ⌘↩ returns to the themed note. **Observed:**
- [ ] **CT-8 Undo.** Edit a note, ⌘Z: the old text, ⇧⌘Z: the new. While an editor is open and focused, ⌘Z: **record
  whether it undoes the typing in the field or the document's last step** (MetalUI's field keeps ⌘Z before the app's
  command, KF-C). **Observed:**
- [ ] **CT-9 Inspector and canvas together.** Select a note (the inspector shows its text), double click it and type: the
  inspector shows the old text until the edit commits. Click into the inspector's box and type: the canvas edit commits
  first and nothing is lost. In the inspector's box, ⌘↩ commits and Return breaks the line (gap CM-a). Pinned:
  `CommentTypingTests`, `CommentKeysTests`. **Observed:**
- [ ] **CT-10 Focus.** Double click a note, double click another note, then a frame's title bar, without clicking
  elsewhere between: each edit commits and the next starts with the caret in its field. Press Tab in an editor: focus
  moves (it opens no palette). Pinned: `CommentDoubleClickTests`. **Observed:**
- [ ] **CT-11 Inert chrome (gap CT-a).** While a note is being edited, press the graph panel's header gap, the glass
  padding and an empty area of the inspector. **Record** whether the editor stays open (the expected, documented
  behaviour: User decision 2) and what the next canvas press does. **Observed:**
- [ ] **CT-12 Groups and saving.** Enter a group, double click a note there and type, then leave the group with ⌘↑: the
  text is in the definition's note. Save, quit, reopen: the text persists, the edit marked the document edited, and ⌘Z
  has nothing to undo. Pinned: `CommentTypingTests`. **Observed:**

## Group GR — groups: the editor (C2)

```


- [ ] **Step 6: Check the docs and commit**

Run: `swiftlint lint --strict` (zero violations; unchanged by docs) and `grep -n "CM-a" docs/metalui-gaps.md` (the summary
row and the entry both say fixed and adopted). Nothing else runs: no code changed.

```bash
git add CLAUDE.md docs
git commit -m "docs: typing on the canvas (CLAUDE.md, roadmap, MetalUI gaps, comments spec Errata, human checks CT)"
```

---

## Appendix A: the C9 probe

Throwaway; it is **not** part of either repository. It builds the element tree this plan builds (a `hoverKeyRegion` canvas
with one `onKeyPress`, and a `TextEditor` sibling under `scaleEffect` that takes focus in `onAppear`, handles ⌘↩ and Esc
with `onKeyPress` and reports focus loss) in MetalUI's own fake window and asserts the key and focus facts the plan relies
on. To re-check C9 once it is merged: make a scratch clone of `../MetalUI` (never touch the real one), check out `master`,
save this as `Tests/MetalUITests/ZZProbeTests.swift` there, run `swift test --filter ZZProbe`, and expect 2 tests passing.
Any failure is a C9 behaviour this plan does not get, and so a gap to log, not a thing to work around.
Run at `feat/key-focus` `c5df112` (merged locally with MetalUI master `70e9389`, see the Verification record below): 2 passed.

```swift
import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// A throwaway probe for MetalCreator's "typing on the canvas" plan: the element tree it builds (a hover key region with
// one onKeyPress, a TextEditor beside it under scaleEffect) against C9's key and focus rules. Not part of MetalUI.

private func kd(_ c: String, _ m: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: m, timestamp: 0))
}
private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func mv(_ p: Point<Pixels>) -> InputEvent { .mouseMoved(MouseEvent(position: p)) }
private func down(_ p: Point<Pixels>) -> InputEvent { .mouseDown(MouseEvent(position: p)) }
private func up(_ p: Point<Pixels>) -> InputEvent { .mouseUp(MouseEvent(position: p)) }

@MainActor final class ZProbeLog {
    var log: [String] = []
    var text = "hello"
    var scale = 1.0
}

/// The comment editor: focus asked for on appear, ⌘↩ and Esc as `onKeyPress` on the field, focus loss reported.
struct ZProbeEditor: Component {
    let m: ZProbeLog
    @FocusState var f: Bool
    var content: some ElementGroup {
        TextEditor("", text: m.text, onChange: { m.text = $0 })
            .focused($f)
            .onKeyPress(keys: [.return]) { press in
                if press.modifiers.contains(.command) { m.log.append("commit"); return .handled }
                return .ignored
            }
            .onKeyPress(.escape) { m.log.append("esc"); return .handled }
            .frame(width: px(80), height: px(40))
            .onAppear { f = true }
            .onChange(of: f) { was, now in m.log.append("focus \(was)->\(now)") }
    }
}

/// The canvas surface (a key region with one onKeyPress; a tap starts editing) with the editor layer as its sibling.
struct ZProbeHost: Component {
    let m: ZProbeLog
    @State var editing = false
    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) { Color.clear }
                .frame(width: px(200), height: px(200))
                .contentShape(Rectangle())
                .onTapGesture { editing = true }
                .hoverKeyRegion()
                .onKeyPress(phases: [.down, .repeat]) { press in m.log.append("canvas \(press.characters)"); return .handled }
            if editing {
                ZStack { ZProbeEditor(m: m) }
                    .scaleEffect(m.scale, anchor: .topLeading)
                    .offset(x: px(20), y: px(30))
            }
        }
    }
}

@MainActor private func settle(_ window: Window) { for _ in 0..<4 { window.drawFrameIfNeeded() } }

@MainActor
@Test func theCanvasRegionAndTheEditorSibling() throws {
    let m = ZProbeLog()
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200) { ZStack { ZProbeHost(m: m) } }
    window.drawFrameIfNeeded()
    platform.simulateInput(mv(pt(150, 150)))
    #expect(platform.simulateInput(kd("a")), "nothing focused: the hovered canvas region hears the key")
    platform.simulateInput(down(pt(150, 150))); platform.simulateInput(up(pt(150, 150)))
    settle(window)
    #expect(window.focusedElement != nil, "a field focused from onAppear")
    #expect(m.log.contains("focus false->true"))
    _ = platform.simulateInput(.textInput("X"))
    #expect(m.text == "Xhello", "gap CT-b: a field focused from code opens with its caret at the start")
    m.log = []
    for k in ["x", "\u{7f}", "\u{f700}", " ", "f", "\t"] { _ = platform.simulateInput(kd(k)) }
    _ = platform.simulateInput(kd("a", .command))
    _ = platform.simulateInput(kd("n", [.command, .shift]))
    _ = platform.simulateInput(kd("g", .command))
    #expect(!m.log.contains { $0.hasPrefix("canvas") }, "a focused field keeps every key: \(m.log)")
    _ = platform.simulateInput(kd("\r"))
    #expect(!m.log.contains("commit"), "plain Return is the editor's (a line break)")
    _ = platform.simulateInput(kd("\u{1b}"))
    _ = platform.simulateInput(kd("\r", .command))
    #expect(m.log.contains("esc") && m.log.contains("commit"), "Esc and ⌘↩ reach the field's onKeyPress: \(m.log)")
    m.log = []
    platform.simulateInput(down(pt(180, 180))); platform.simulateInput(up(pt(180, 180)))
    settle(window)
    #expect(window.focusedElement == nil, "a press in the canvas region clears the field's focus")
    #expect(m.log.contains("focus true->false"))
}

@MainActor
@Test func aFieldUnderAScaleEffectTakesAPressWhereItIsDrawn() throws {
    let m = ZProbeLog()
    m.scale = 2
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200) { ZStack { ZProbeHost(m: m) } }
    window.drawFrameIfNeeded()
    platform.simulateInput(down(pt(190, 190))); platform.simulateInput(up(pt(190, 190)))
    settle(window)
    window.focus(nil)
    settle(window)
    // The 80 x 40 field at offset (20, 30), scaled 2x from its top-left, covers x 20...180, y 30...110.
    platform.simulateInput(down(pt(170, 100))); platform.simulateInput(up(pt(170, 100)))
    settle(window)
    #expect(window.focusedElement != nil, "a press at the scaled field's far corner focuses it")
    window.focus(nil)
    settle(window)
    platform.simulateInput(down(pt(190, 190))); platform.simulateInput(up(pt(190, 190)))
    settle(window)
    #expect(window.focusedElement == nil, "a press just outside the scaled field is the canvas's")
}
```

---

## Self-review

**Spec coverage** (the brief's list, §7/§8 and the Errata, against the tasks):

| Requirement | Where |
|---|---|
| A double click on a note, through the existing recogniser (0.4 s / 4 pt, runs after the click it ends on) | Task 2 (`pairClick`, `ClickTarget.note`) |
| A double click on a frame's title bar (not its edge band) | Task 2 (`ClickTarget.frameTitle`, `onlyAFramesTitleBarCounts`) |
| A note edits in a multi-line `TextEditor` over the note at its canvas position and zoom, both docks | Tasks 1 (`commentEditor` rect), 3 (`CommentEditorLayer`, `CommentEditorRenderTests`) |
| A frame title edits in a single-line `TextField` over its title bar | Tasks 1, 3 |
| Commit on focus loss | Task 3 (`onChange(of: isFocused)`) |
| Commit on a press elsewhere (C9's M5-g) | Task 1 (`pointerPressed` commits the pending entry), Task 4 (`hoverKeyRegion`) |
| Commit on ⌘↩ for a note (CM-a), on Return for a title | Task 3 (`CommentKeys`, `onKeyPress`, `onSubmit`) |
| Esc cancels and restores the old text | Tasks 1 (`cancelCommentEdit`), 3 (`onKeyPress(.escape)`) |
| An empty frame title is refused ("A frame needs a title.") | Task 1 (`setFrameTitle` is the commit path; `anEmptyTitleIsRefusedAndTheOldOneStays`) |
| Each committed edit is one undo step through the existing commands | Task 1 (`finishCommentEdit` calls `setNoteText` / `setFrameTitle`; `typingThenCommittingIsOneUndoStep`) |
| While a canvas field has focus the graph canvas's keys cannot act, via C9's region/focus-scoped keys, no stopgap | Task 4 (the surface is a key region; the editor is its sibling, Task 3) |
| Editing state in `EditorModel`, views thin; inspector and canvas never fight (one pending entry) | Task 1 (`commentEdit`, `notePendingEntry`) |
| Bind ⌘↩ in the inspector's note box (CM-a) | Task 3 (`CommentTextEntry`) |
| Close CM-a and the M5-g / M5-h rows as adopted where this uses them; CLAUDE.md, roadmap row, gaps file, spec Errata | Task 5 (M5-h is marked fixed by C9 but **not** adopted: nothing here uses it) |
| Header: execution waits for C9; every C9 API with its `feat/key-focus` commit | Header ("C9 APIs this plan uses", `c5df112`) |
| Human-check group (both docks, zoom levels, three themes, undo) | Task 5 (group CT) |
| Files shared with the named-undo track, and what the second merger keeps | Header ("Files shared with other tracks") |

**Placeholder scan:** none (`grep -nE "TBD|TODO|implement later|Similar to Task"` over this file finds nothing outside this sentence).

**Type consistency:** every name a later task uses is defined in an earlier one and was built that way: `CommentEdit`, `CommentEditor`,
`beginEditing`, `commentDraftChanged`, `commitCommentEdit`, `cancelCommentEdit`, `commentEditor` (Task 1) are used by Tasks 2 to 4;
`CommentKeys.commitsNote` (Task 3) by `CommentEditorField` and `CommentTextEntry`; `CanvasSurface` (Task 3) is extended in Task 4;
`GraphPanelInput.handleKey` (Task 4) by the rewritten tests. The whole plan was replayed task by task from master (see the
return's Verification).

**Review Focus:** each of the five lines names its tests (Tasks 1, 2 and 3).

**What the tests cannot pin** (they go to the human checks, group CT, and to MetalUI C9's own tests and Appendix A): that a real window
routes keys and focus as the probe's fake window does; that `keyPressed(_:)` passes `press.phase`, `press.key` and the rest to `keyEvent(key:characters:modifiers:isRepeat:)` (a one-statement
call; the conversion itself is `GraphKeyEventTests`'); the field's own wiring in `CommentEditorField` (Esc, ⌘↩, Return, the focus-loss
commit, focus on appear: no headless window, gap M6-e; CT-1 and CT-2 list each as its own observation, and `CommentKeysTests`
pins only the ⌘ predicate; Appendix A probes a copy of the editor, not the component); the editor's look in the three themes, its caret under a scale effect, and the 22 pt title field.

---

## Verification record (revised 2026-10-10, after review)

Every code block was applied, task by task, to a scratch clone at **master `4dff87b`** (named-undo merged; the tree the executor
will have after `git merge master`), with a sibling `MetalUI` symlinked to a scratch clone of `../MetalUI` at `feat/key-focus`
`c5df112`, with MetalUI master `70e9389` merged in locally, because C9 branched before C8 and C10 and MetalCreator uses both
(the merge conflicted only in the demos' `main.swift`, two docs tables, `AnimationStore.swift` (both sides kept) and one
cross-platform test fake that needed six new protocol members). Each task built with no new source warnings, passed a full
`swift test` by the rule above (exit 0, no "recorded an issue" or "failed after", 11 "Test run with" lines) and reported zero
`swiftlint lint --strict` violations; Task 5's `Modify` anchors all matched the merged docs:

| After | Full-suite tests | = |
|---|---|---|
| master `4dff87b` | 2142 | |
| Task 1 | 2164 | master + 22 |
| Task 2 | 2170 | master + 22 + 6 |
| Task 3 | 2175 | master + 22 + 6 + 5 |
| Task 4 | 2181 | master + 22 + 6 + 5 + 6 |
| Task 5 | 2181 | docs only |

Appendix A's two tests passed against that scratch MetalUI when the plan was first written; they are unchanged. The merged-C9 run above is the one the executor repeats.
