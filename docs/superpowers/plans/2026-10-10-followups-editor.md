# Final-Review Follow-Ups: Editor and Groups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the leftover final-review findings of the editor and groups track: two real bugs (a refused group or socket edit shaking the wrong node; ⌘G dropping a target socket's default and optional flag), the editor and group items ED-2 to ED-13, ED-17, ED-18 and the group items GK-10 and GK-13.

**Architecture:** Small, local fixes in the existing style. Behaviour lives in `EditorModel` extensions and in the `CreatorGraph` group commands; views only pass what the model needs (`GroupPanel.node`). Every behaviour fix is test-first (the test fails for the stated reason before the source patch); pure cleanups keep the suite green and add no test; coverage gaps are pins that pass on today's code.

**Tech Stack:** Swift 6.2 strict concurrency, Swift Testing, SwiftPM (`swift test`), MetalUI via `../MetalUI` (not edited), SwiftLint `--strict`.

**Spec:** `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` (groups and comments, §3 to §7 and its Errata for A, C1, B and C2) for the BUG, ED and GK-10/13 items it governs; the parent `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (§6.2 refusal feedback, §3.2 editor, with its Errata) for the rest. The issue statements are the triage at `/private/tmp/claude-501/-Users-maxburger-Developer/89808cd9-ba62-46fa-aaed-bac3e12fa878/scratchpad/followups-triage.md` (written against master `4dff87b`; its `file:line` references had drifted in places, every item below was re-read against the code first).

**Repo and branch:** run everything from `/Users/maxburger/Developer/MetalCreator-fu-editor` (git worktree, branch `followups-editor`, off master `4dff87b`, which has **2142 tests**). Never `cd` into `/Users/maxburger/Developer/MetalCreator` or another worktree. Never edit `Package.swift`'s `../MetalUI` path. Never modify `../MetalUI`. No screenshots.

**Verification status of this plan:** every patch below was applied task by task, in this order, to a scratch copy of the worktree (a sibling `MetalUI` symlink beside it). At each task commit the copy built with no new warnings, passed the full `swift test` by the rule below and was clean under `swiftlint lint --strict`. The test counts quoted per task are those runs. **Final: 2183 tests (master + 41).** A later revision added two tests and one assertion (`aSketchWithOneDegreeOfFreedomLeftWarnsInTheSingular` in Task 15, `aNumberedNameTheDocumentUsesIsImportedNotCountedOn` in Task 9, and the second assertion of `aPressWithoutAChangeLeavesNoUndoStep` in Task 16, which adds no test) and was verified in the final tree only: build, a full `swift test` by the rule below (exit 0, 0 issue lines, 11 `Test run with` lines, 2183 tests) and `swiftlint lint --strict` (0 violations); the per-task counts from Task 9 on are the earlier per-task runs plus those additions.

## The pass rule for a full `swift test`

A full run passes only if: the exit code is 0; no line says `recorded an issue` or `failed after` (Swift Testing prints glyphs, not ✘); and exactly 11 `Test run with` lines appear. The per-task counts below are the sum of those lines' test counts.

```bash
swift test > /tmp/full.txt 2>&1; echo "exit=$?"
grep -cE 'recorded an issue|failed after' /tmp/full.txt      # must print 0
grep -cE 'Test run with' /tmp/full.txt                       # must print 11
grep -E 'Test run with' /tmp/full.txt | awk '{s+=$5} END {print s}'   # the count
swiftlint lint --strict                                      # 0 violations
```

## Global Constraints

- Swift 6 strict concurrency; Swift Testing (`@Test`, `#expect`, `#require`); `@Observable` models are `@MainActor`; behaviour in models, thin views; one type per file; no force unwraps or force `try`; no GCD or `Task.sleep(nanoseconds:)`; `FormatStyle`, never `String(format:)` or `Formatter` subclasses (CLAUDE.md, AGENTS.md).
- `swiftlint lint --strict` reports zero violations before every commit; prefer fixing the code over `swiftlint:disable` (CLAUDE.md "SwiftLint").
- Keep changes minimal and in the existing style; no refactors beyond what an item needs. MetalUI gaps go in `docs/metalui-gaps.md` (entry and summary-table row) and are never worked around. **This track found no new MetalUI gap.**
- No docs changes except this plan, the Errata section and the one CLAUDE.md clause named in the shared-files table.
- The numbers are cumulative: each task's count is the full-suite total after that task, applied in order on top of the previous.
- End each commit message with the attribution lines the session gives (this plan shows only the subject line).

## Review Focus

The inputs this work implies but whose tests the item list would not otherwise write, most likely first. Each line names the test that pins it and the task that owns it.

1. **A group name typed in the inspector and committed after Undo removed that group.** Expect a caption (`That group no longer exists.`), no crash, no change. Test `aNameCommittedAfterItsGroupWasUndoneOnlySaysSo`, Task 1 (a pin: it passes before the fix; of Task 1's four tests the others fail on the old code).
2. **⌘G, then unwiring an outside source, then ⇧⌘G.** Expect the spliced nodes to evaluate as the group did (Add's `b` on its default 0), now that the group input carries the default. Test `ungroupingAfterUnwiringAGroupedInputEvaluatesAsBefore`, Task 2.
3. **A definition name ending in a number that overflows `Int`, in non-ASCII digits, or with a sign** (`Rib 99999999999999999999`, `Rib ٣`, `Rib +3`). Expect a plain `... 2`, no trap, no wrong stem. Assertions in `aNumberedNameCountsOnFromItsOwnNumber`, Task 9.
4. **Cut, Undo, Paste.** Expect Undo to bring the cut node back and a paste still to add a copy (the clipboard is taken only after the delete went through). Test `cutUndoPasteGivesTheNodeAndACopy`, Task 11.
5. **Undo of an inner-node delete after `innerResults` was pruned.** Expect the node's state back once the next evaluation finishes. Assertion in `innerResultsOfNodesThatAreGoneLeaveAtOnce`, Task 12.

Not testable headless, listed under Risks instead: a refusal message long enough to wrap (Task 6), and the real height of a `.caption` line.

## Files shared with the other tracks

The editor track (this plan) merges first. The side that merges second must keep everything in the "Kept by the second merger" column and resolve any textual overlap by taking both sides.

| File | Other track | What this plan changes | Kept by the second merger |
|---|---|---|---|
| `CLAUDE.md` | app (`followups-app`, DOC items edit it) | Task 18: one clause in the named-undo paragraph (around line 54): `SketchCommit.init` and `EditorModel.edit` require `name:`. Nothing else. | The clause. Other CLAUDE.md edits anywhere else are independent. |
| `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` | app (owns specs and Errata) | Task 18: a new section `## Errata (F: editor follow-ups)` appended after `Errata (C2)`'s last line. | The section; add any further Errata sections after it. |
| `Tests/CreatorAppTests/AppModelOpenURLTests.swift` | app (ED-16 adds a test) | Task 17 (**test-only; every Task 17 edit is, and none touches a source file**): one comment line in `nothingOpensWhileTheCloseQuestionIsUp`. | The comment; ED-16's new test beside it. |
| `Tests/CreatorAppTests/GroupPickInstancesTests.swift` | app (ED-1 may add its test here) | Task 17: assert the stored pick is non-empty inside `aPickMadeInsideOneInstanceChamfersTheOtherToo`. | The assertion; ED-1's test as a separate `@Test`. |
| `Tests/CreatorAppTests/GroupViewportTests.swift`, `PaletteOverlayTests.swift`, `TitleBarClearanceTests.swift`, `WindowChromeTests.swift`, `AppUndoNameTests.swift` | app (directory owner) | Tasks 11 and 17: small edits named in those tasks, all test-only (Task 11 adds `name:` to two call sites; Task 17 is one-line changes and added assertions, no moved code, so textual conflicts are unlikely and resolve by taking both sides). | The edits. |
| `Sources/CreatorEditor/EditorModel.swift` | app (DOC-6 re-wraps comments, e.g. near line 25) | Task 5: `clearRefusal()` near line 218. | Both hunks (they do not overlap). |
| `Sources/CreatorSketchEditor/SketchCommit.swift`, `Tests/CreatorSketchEditorTests/SketchStepNameTests.swift` | kernel (CreatorSketchEditor is theirs; ED-14 edits other files there) | Task 11 (ED-18): `name` has no default; the test `aCommitMadeWithoutANameIsCalledEditSketch` is removed. | No default `name`, and do not restore the removed test; add `name:` to any new `SketchCommit(...)` call (see the `EditorModel.edit(...)` row). `SketchStepName.editSketch` is now unused; the kernel track may delete it. |
| `Sources/CreatorNodes/Sketch/SketchSockets.swift`, new `Tests/CreatorNodesTests/SketchExposedNameTests.swift` | kernel (CreatorNodes is theirs; GK-9 edits `SketchNode`/`SketchSolve`) | Task 15 (GK-10): `partition`/`refused` give a repeat its own warning; tests in a new file so `SketchNodeTests.swift` is untouched. | The new warning text and the new test file. |
| `docs/verification/human-checks.md` | app (owns it; the brief puts human checks with the app track) | **Not edited by this plan.** Two visual or hover-only items (ED-5, ED-7) need human checks; the text is under "Human checks to hand over" below. | The app track appends them to Group GR as GR-10 and GR-11 (or the next free numbers), with their own **Observed:** lines. |
| Every call to `EditorModel.edit(...)` or `SketchCommit(...)` that another track adds or already has | app (ED-1, ED-15, ED-16 tests) and kernel (ED-14 sketch-editor tests) | Task 11 makes `name:` required in both, so a call without `name:` no longer compiles. This plan edits the three call sites that exist on master (`EditingTests`, `AppUndoNameTests`, `GroupViewportTests`). It cannot edit calls the other tracks write in parallel. | The second merger adds `name:` to each such call: an `UndoName` constant (or `UndoName.sketch(...)`) for `editor.edit(...)`, a `SketchStepName` for `SketchCommit(sketch:description:name:)`. A mechanical fix, found by the compiler. **The app and kernel tracks should pass `name:` in every new call from now on.** |
| `Sources/CreatorGraph/DocumentModel.swift`, `Groups/GraphContent+Apply.swift`, `Groups/GraphContent+Levels.swift`, `Groups/GroupBuilder.swift`, `Groups/GroupCommands+Expose.swift`, `Groups/GroupNaming.swift` | none claimed (kernel's GK-5 edits `Evaluator+Running.swift`, which this plan does not touch) | Tasks 2, 3, 9, 12, 13. | n/a |

## User decisions

Each is product behaviour the spec leaves open. The plan is written for the recommended default; the alternative is a one-task change.

1. **Make Unique numbering (ED-8).** Spec §5 says the copy is called "Name 2". A name that already ends in a number then gives "Rib 2 2" today. *Recommended:* count on from the number ("Rib 2" gives "Rib 3"; "Rib" still gives "Rib 2"), as Finder does (Task 9, Errata line added). Only Make Unique changes: `GroupNaming.uniqueName` is shared, but ⌘G's base ("Group") has no number, and the clipboard merge names a colliding pasted definition "<name> (imported)", which ends in `)` and is never counted on (a pasted "Rib 2" that collides stays "Rib 2 (imported)"; pinned by `aNumberedNameTheDocumentUsesIsImportedNotCountedOn`). *Alternative:* keep "Rib 2 2" and only note it in the Errata.
2. **When the refusal caption goes (ED-4).** Today it stays 2.3 s whatever happens next. *Recommended:* a successful edit (any `EditorModel.edit`, a paste or duplicate, a group-inspector command) clears it at once (Task 5). *Alternative:* delete the never-called `clearRefusal()` and keep the 2.3 s timer only (then `RefusalShakeTests.aCountNeverGoesDownSoClearingTheMessageDoesNotShakeAgain` must drop its call).
3. **Exposed outputs keep `optional` (ED-2).** It has no effect on evaluation today (group nodes take their outputs from Group Output's inputs, which are optional already); it only makes the definition say what the inner socket says. *Recommended:* carry it (Task 3, one line). *Alternative:* drop the item and leave the Errata (C2) note that an exposed output is always required.
4. **⌘G inputs carry the target's default, optional and access (BUG-2).** This is also the C2 rule for the "+" drop (decision 4). The visible consequences: the group node's input row gets the target's slider range and default; Ungroup after the source was unwired writes the default as an explicit value on the inner input. Files saved before this change keep their old definitions. *Recommended:* yes (Task 2). *Alternative:* none sensible, but say if you want old definitions migrated.
5. **The refusal line is 16 points high in the layout (ED-5).** `GraphPanelLayout.refusalLineHeight` is set to the library caption's 16 points (`PaletteLayout.captionHeight`) and the caption gets `frame(minHeight:)`; I could not measure a real `.caption` line without a screenshot. *Recommended:* keep 16 and add a human check (the app track owns `human-checks.md`): show a refusal, confirm a library drop on the caption adds nothing and a drop just above it does. *Alternative:* fix the line to one line (`lineLimit(1)` plus an exact height), which truncates long messages. The check text is under "Human checks to hand over".
6. **ED-18 across the package boundary.** Requiring `name` in `SketchCommit.init` edits the kernel track's `CreatorSketchEditor` and removes one of its tests. *Recommended:* do it here (Task 11), since the editor merges first and nothing else uses the default. *Alternative:* leave `SketchCommit` to the kernel track and keep only `EditorModel.edit`. **Build-break risk either way:** the editor merges first, so any `editor.edit(...)` or `SketchCommit(...)` call the app or kernel track writes without `name:` stops compiling at the second merge; the fix is one argument per call (shared-files table). If the other tracks are far along and you would rather not carry that, take the alternative and make `name` required in a follow-up once both have merged.
7. **Where a refused group-inspector commit shakes (BUG-1).** A name typed in the inspector is committed when the selection moves on, and a level change commits it too, so the node the field was typed for can sit in another level, or be gone (Undo), when the refusal happens. *Recommended (written):* shake the node the field was typed for and show the caption either way; if that node is not in the shown graph nothing visibly shakes (the count is only a trigger), the caption still reads, and a "That group no longer exists." commit refuses with no node at all. *Alternative:* pass `node: nil` (caption only) whenever the node is not in the shown graph. The triage allowed either; the difference is one `graph.nodes[node] != nil` check in `perform`, and no visible behaviour changes (an invisible node cannot be seen shaking).

## Human checks to hand over

For the app track to add to `docs/verification/human-checks.md` (Group GR, after GR-9). This plan does not edit that file.

- [ ] **GR-10 Refusal caption.** Make any edit that is refused (for example drag a wire from a number into an Extrude's profile). The red message appears under the graph panel and the canvas ends above it: the bottom nodes are not covered by it. Wait for it to go (about 2 seconds) and the canvas grows back. With the message showing, drag a node type from the library and drop it on the message: nothing is added; drop it just above the message, on the canvas: the node is added (and the message goes, because an edit went through). Make a refusal with a long message (a sketch with a long error) and note whether it wraps over the bottom canvas row. Pinned: `PanelPlacementTests`, `LibraryDragTests`, `RefusalShakeTests` (the 16 pt line height is a constant; this check is the only measurement of a real caption line). **Observed:**
- [ ] **GR-11 Breadcrumb tooltips.** Inside a group two levels deep, hover each crumb in the header and wait for its tooltip. Only the crumb for the level just outside the one shown reads "Back to <name> (⌘↑)"; every other crumb reads "Back to <name>" with no shortcut (the top "Graph" crumb included when it is two levels out). At the top level no tooltip names ⌘↑. Press ⌘↑ and confirm it goes out one level, as the tooltip said. Pinned: `BreadcrumbRenderTests`. **Observed:**

## What each owned item became

Every item was re-read against the code before planning. "Pin" means a test that passes today and guards the behaviour.

| Item | Verdict | Where |
|---|---|---|
| BUG-1 | Confirmed: `perform` refused with `selection.first`, and the commit runs after the selection moved. `moveGroupSocket` range check added. | Task 1 |
| BUG-2 | Confirmed: `GroupBuilder.wireIn` dropped default, optional and access. | Task 2 |
| ED-2 | Confirmed, but invisible to evaluation (decision 3). | Task 3 |
| ED-3 | Confirmed: `addNode` fell back to `makeNode`. | Task 4 |
| ED-4 | Confirmed: `clearRefusal()` had no caller outside a test. | Task 5 |
| ED-5 | Confirmed. | Task 6 |
| ED-6 | Confirmed. | Task 7 |
| ED-7 | Two of four: breadcrumb tooltip and `isPlus`. **Dropped:** `levelTransforms` never pruned (one `CanvasTransform` per group level entered in a session, and pruning would forget a level's view when Undo restores the node); two accent roles one colour in a custom theme (theme data, the person's choice, no defect); "GroupNaming reserves + retroactively" (documented behaviour, nothing to fix). | Task 8 |
| ED-8 | Confirmed (decision 1). | Task 9 |
| ED-9 | Confirmed dead: `.panning` cannot coexist with a primary press. | Task 11 |
| ED-10 | (a) confirmed. **Dropped:** (b) nudge refused — `moveCommands` only emits moves for items found in the selection with a finite delta, so `edit` cannot refuse; (c) F over an empty canvas does nothing — harmless, and zero-size framing is already pinned by `FramingTests.framingAZeroSizeRectStaysFiniteAndCentred`; (d) stale middle-press cases — defensive by MetalUI CI-AA 4, as the triage says. | Task 10 |
| ED-11 | As written it is not reachable (the copy and the delete cover the same items, so a refused delete with a non-empty copy cannot happen today). Reordered anyway as hardening. | Tasks 11, 16 (pins) |
| ED-12 | Confirmed. | Task 11 |
| ED-13 | Confirmed. | Task 12 |
| ED-17 | Done: glyph-count render tests get model assertions; `ThemeRenderTests` role coverage; the no-op `transform =` line; the stored pick non-empty; `PaletteOverlayTests`, `TitleBarClearanceTests`, `WindowChromeTests`, `AppModelOpenURLTests`. **Already fixed or not a gap, dropped:** "no `selection =` drops comments test" (`CommentSelectionTests.assigningTheNodeSelectionClearsSelectedComments`), "no multi-node ⌘C/⌘V/⌘D test" (`EditingTests.pasteAndDuplicateOfTwoConnectedNodesCopyTheWireAndSelectTheCopies`), "`ThemeEditorModelTests` last expectation only `message != nil`" (already `editor.message == "A theme needs a name." && ...`), `AppModelOpenURLTests`'s closing `discardChanges()` (not a no-op: it proves nothing was queued; a comment says so). **Slider and shake pins, checked by reverting the code each guards:** removing `document.endCoalescing()` from `sliderEditingChanged` fails `twoDragsWithNothingBetweenThemAreTwoUndoSteps` and `aParameterSliderDragIsOneStepAndTwoDragsAreTwo`, so the behaviour that needs the code is pinned. `aDragFromPressToReleaseIsOneUndoStep` cannot fail without it (one key coalesces a drag by itself), `aTypedValueAfterTheReleaseIsItsOwnStep` cannot (a typed edit has no coalescing key, so it is its own step however the drag before it ended; it guards the keyless path) and `aPressWithoutAChangeLeavesNoUndoStep` could not (no edit, no step). The last is strengthened (Task 16): it now also drags through the value the field already has, which fails if `setInput`'s `value != field.value` guard goes. `RefusalShakeTests.aCountNeverGoesDownSoClearingTheMessageDoesNotShakeAgain` is a real guard: with `clearRefusal()` also zeroing the counts it fails (mutation-checked). **Dropped:** nothing else of that item; `CommentResizeTests`/zero-size framing "not mutation-checked" — the mutation check was done: deleting `document.endCoalescing()` where a move or resize ends fails no test in the suite, because the keys are unique per gesture, so the line is not observable through undo steps and the test cannot be strengthened. | Tasks 16, 17 |
| ED-18 | Confirmed (decision 6). | Task 11 |
| GK-10 | Both parts done. The duplicate-name message confirmed (own warning for a repeat). "The one-degree-of-freedom message branch" is the `freedom == 1 ? "1 degree" : …` wording at `SketchSolve.swift:34`, untested (only "8 degrees" was); now pinned by a test in the new `SketchExposedNameTests.swift` with no source change. The empty-name warning of `SketchSockets.refused`, also untested, is pinned there too. | Task 15 |
| GK-13 | `replay` confirmed (reproduced: a debug build traps). Every listed test gap is written; none revealed a defect. | Tasks 13, 14 |

## File structure

New files: `Tests/CreatorGraphTests/Groups/NestedGroupEditTests.swift` (Task 14: Ungroup and Make Unique inside a definition, fan-out, two-level picks; separate from `UngroupTests` for SwiftLint's 250-line struct limit) and `Tests/CreatorNodesTests/SketchExposedNameTests.swift` (Task 15). Everything else is an edit; each task lists its files.

| Area | Files | Responsibility |
|---|---|---|
| Group inspector | `EditorModel+GroupInspector.swift`, `GroupPanel.swift`, `GroupPanelView.swift`, `GroupSocketRowView.swift` | Definition and socket edits from the inspector; the node a refusal belongs to (Task 1) |
| Editing and clipboard | `EditorModel+Editing.swift`, `EditorModel+Levels.swift`, `EditorModel.swift` | Add, cut, paste, `edit(...)`, refusal feedback (Tasks 4, 5, 11) |
| Layout | `GraphPanelLayout.swift`, `EditorModel+Placement.swift`, `EditorModel+Culling.swift`, `GraphPanel.swift` | Where the canvas is, including the refusal line (Task 6) |
| Groups, CreatorGraph | `GroupBuilder.swift`, `GroupCommands+Expose.swift`, `GroupNaming.swift`, `GraphContent+Apply.swift`, `GraphContent+Levels.swift`, `DocumentModel.swift` | Group commands and the document's evaluation state (Tasks 2, 3, 9, 12, 13) |

## Task index

| # | Task | Items | Tests after |
|---|---|---|---|
| 1 | A refused group or socket edit shakes the node it was typed for (BUG-1) | BUG-1 | 2146 (master + 4) |
| 2 | Group (⌘G) keeps the target socket's default, optional and access (BUG-2) | BUG-2 | 2149 (master + 7) |
| 3 | An exposed output keeps its optional flag (ED-2) | ED-2 | 2150 (master + 8) |
| 4 | Adding a stale or unknown library key adds nothing (ED-3) | ED-3 | 2151 (master + 9) |
| 5 | A successful edit clears the refusal caption (ED-4) | ED-4 | 2153 (master + 11) |
| 6 | The canvas frame leaves room for the refusal caption line (ED-5) | ED-5 | 2156 (master + 14) |
| 7 | A comment menu item chosen mid-drag does nothing (ED-6) | ED-6 | 2157 (master + 15) |
| 8 | Breadcrumb tooltips and a Missing node's "+" socket (ED-7) | ED-7 | 2160 (master + 18) |
| 9 | Make Unique counts on from a numbered name (ED-8) | ED-8 | 2163 (master + 21) |
| 10 | Esc leaves the selection alone while the panel is hidden (ED-10a) | ED-10a | 2164 (master + 22) |
| 11 | Cleanups and required undo names (ED-9, ED-11, ED-12, ED-18) | ED-9, ED-11, ED-12, ED-18 | 2164 (master + 22) |
| 12 | Prune innerResults with results (ED-13) | ED-13 | 2165 (master + 23) |
| 13 | Undo and Redo replay without the new-definition and interface rules (GK-13) | GK-13 (replay) | 2167 (master + 25) |
| 14 | Group-edit test gaps (GK-13) | GK-13 (tests) | 2177 (master + 35) |
| 15 | A repeated exposed dimension name gets its own warning (GK-10) | GK-10 | 2180 (master + 38) |
| 16 | Editor test hardening (ED-17, editor side) | ED-17 (editor) | 2183 (master + 41) |
| 17 | App test hardening (ED-17, app side) | ED-17 (app) | 2183 (master + 41) |
| 18 | Errata and the CLAUDE.md sentence | Errata, CLAUDE.md | 2183 (master + 41) |

## Dropped items and risks

- **Risk, ED-5:** the 16-point caption line is a layout constant I could not measure (no screenshots). A refusal message that wraps takes more room than modelled, and the canvas is then taller than the editor thinks by the extra lines. Decision 5 covers the human check.
- **Risk, ED-4:** any code that calls `refuse(...)` and then a successful `edit(...)` in one gesture would lose its caption. None does today (every `refuse` call site returns or ends the function), and a slider drag over a refusal clears it, which is intended.
- **Risk, BUG-2:** only groups made after this change carry defaults; saved definitions are not migrated (decision 4).
- **Risk, GK-13:** `replaying` also skips the interface name check on Redo of `.setInterface`; those commands were valid when recorded. The wired-socket check after a command still runs on replay.
- **Note, ED-18:** `SketchStepName.editSketch` has no user left; delete it with the kernel track.

---

## Tasks

### Task 1: A refused group or socket edit shakes the node it was typed for (BUG-1)

**Why.** `EditorModel.perform(_:_:)` in `EditorModel+GroupInspector.swift` refuses with `node: selection.first`. A group name or a socket name is committed when the selection changes (`canvasSelection.didSet` calls `commitPendingEntry()` after the selection moved), so a refused commit shook and captioned the node just selected (or an arbitrary one of a multi-selection). The panel now knows its node (`GroupPanel.node`) and the views pass it. The node can be in another level, or gone, by the time the entry commits; user decision 7 records that choice. `moveGroupSocket` also gets a range check, so an arrow with nowhere to go neither refuses nor records a step.

**Files:**

- Modify: `Sources/CreatorEditor/EditorModel+GroupInspector.swift`
- Modify: `Sources/CreatorEditor/GroupPanel.swift`
- Modify: `Sources/CreatorEditor/GroupPanelView.swift`
- Modify: `Sources/CreatorEditor/GroupSocketRowView.swift`
- Test: `Tests/CreatorEditorTests/EditorGroupInspectorTests.swift`

**Interfaces:**
- Consumes: `PendingEntry(text:textCommit:)`, `EditorModel.notePendingEntry(_:)`, `GroupedEditor` (test fixture), `EditorModel.shakeCount(of:)`.
- Produces: `GroupPanel.node: NodeID`; `renameGroup(_:to:on:)`, `setGroupAccent(_:to:on:)`, `renameGroupSocket(_:side:from:to:on:)`, `moveGroupSocket(_:side:named:by:on:)`, `removeGroupSocket(_:side:named:on:)`, each with `on node: NodeID? = nil` (nil shows the message and shakes nothing); `deleteGroup(_:)` unchanged and shakes nothing.

- [ ] **Step 1: Write the failing tests**

Apply this patch (tests only):

```diff
diff --git a/Tests/CreatorEditorTests/EditorGroupInspectorTests.swift b/Tests/CreatorEditorTests/EditorGroupInspectorTests.swift
--- a/Tests/CreatorEditorTests/EditorGroupInspectorTests.swift
+++ b/Tests/CreatorEditorTests/EditorGroupInspectorTests.swift
@@ -164,6 +164,73 @@ struct EditorGroupInspectorTests {
         #expect(grouped.current?.name == "Rib", "clicking away didn't drop it")
     }
 
+    /// A name typed in the inspector is committed when the selection moves on, and a refusal then belongs to the node
+    /// the field was typed for, not to the node just selected.
+    @Test func aRefusedNameCommittedByClickingAwayShakesTheNodeItWasTypedFor() throws {
+        let grouped = try GroupedEditor()
+        let editor = grouped.editor
+        editor.selection = [grouped.group]
+        editor.perform(.duplicate)
+        editor.press(.makeUnique, on: try #require(editor.selection.first))
+        let other = try #require(editor.document.definitions.values.first { $0.id != grouped.definition.id })
+        editor.renameGroup(other.id, to: "Rib")
+        editor.selection = [grouped.group]
+        let panel = try #require(editor.groupPanel)
+        #expect(panel.node == grouped.group)
+        // What the Name field records on each keystroke (`GroupPanelView`).
+        editor.notePendingEntry(PendingEntry(text: "Rib") { editor.renameGroup(panel.definition, to: $0, on: panel.node) })
+        editor.selection = [grouped.number.id]
+        #expect(editor.refusal?.message == "A group named “Rib” already exists.")
+        #expect(editor.refusal?.node == grouped.group)
+        #expect(editor.shakeCount(of: grouped.group) == 1)
+        #expect(editor.shakeCount(of: grouped.number.id) == 0, "the node just selected didn't refuse anything")
+    }
+
+    /// The node a name was typed for can be gone when the entry is committed (Undo took the Group back): the caption says
+    /// so and nothing crashes.
+    @Test func aNameCommittedAfterItsGroupWasUndoneOnlySaysSo() throws {
+        let grouped = try GroupedEditor()
+        let editor = grouped.editor
+        editor.selection = [grouped.group]
+        let panel = try #require(editor.groupPanel)
+        editor.notePendingEntry(PendingEntry(text: "Rib") { editor.renameGroup(panel.definition, to: $0, on: panel.node) })
+        editor.document.undo()
+        #expect(editor.document.definitions.isEmpty)
+        editor.commitPendingEntry()
+        #expect(editor.refusal?.message == "That group no longer exists.")
+        #expect(editor.document.definitions.isEmpty)
+    }
+
+    @Test func aRefusedSocketNameShakesTheGroupInputItWasTypedFor() throws {
+        let grouped = try GroupedEditor()
+        let editor = grouped.editor
+        editor.enterGroup(grouped.group)
+        let input = try #require(grouped.definition.inputNode)
+        editor.selection = [input.id]
+        let panel = try #require(editor.groupPanel)
+        editor.notePendingEntry(PendingEntry(text: "  ") {
+            editor.renameGroupSocket(panel.definition, side: .input, from: "width", to: $0, on: panel.node)
+        })
+        editor.selection = [grouped.rectangle.id]
+        #expect(editor.refusal?.message == "A socket needs a name.")
+        #expect(editor.shakeCount(of: input.id) == 1)
+        #expect(editor.shakeCount(of: grouped.rectangle.id) == 0)
+        #expect(grouped.current?.inputs.map(\.name) == ["width"])
+    }
+
+    @Test func movingTheFirstSocketUpOrTheLastDownIsIgnored() throws {
+        let grouped = try GroupedEditor()
+        let editor = grouped.editor
+        editor.enterGroup(grouped.group)
+        editor.selection = [try #require(grouped.definition.inputNode).id]
+        let undoName = editor.document.undoName
+        editor.moveGroupSocket(grouped.definition.id, side: .input, named: "width", by: -1)
+        editor.moveGroupSocket(grouped.definition.id, side: .input, named: "width", by: 1)
+        #expect(editor.refusal == nil, "an arrow with nowhere to go says nothing")
+        #expect(editor.document.undoName == undoName, "and records nothing")
+        #expect(grouped.current?.inputs.map(\.name) == ["width"])
+    }
+
     @Test func theInspectorDrawsTheGroupPartAndTheSocketList() throws {
         let grouped = try GroupedEditor()
         let editor = grouped.editor
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter 'EditorGroupInspectorTests'`
Expected: FAIL to compile: `value of type 'GroupPanel' has no member 'node'` and `extra argument 'on' in call`. (After the source change, the mutation check `refuse(error.message, node: selection.first)` makes `aRefusedNameCommittedByClickingAwayShakesTheNodeItWasTypedFor` and `aRefusedSocketNameShakesTheGroupInputItWasTypedFor` fail.)

- [ ] **Step 3: Implement**

Apply this patch (sources):

```diff
diff --git a/Sources/CreatorEditor/EditorModel+GroupInspector.swift b/Sources/CreatorEditor/EditorModel+GroupInspector.swift
--- a/Sources/CreatorEditor/EditorModel+GroupInspector.swift
+++ b/Sources/CreatorEditor/EditorModel+GroupInspector.swift
@@ -18,58 +18,71 @@ extension EditorModel {
         let sockets = specs.enumerated().map { index, spec in
             GroupPanel.SocketRow(name: spec.name, type: spec.type, canMoveUp: index > 0, canMoveDown: index < specs.count - 1)
         }
-        return GroupPanel(definition: definition.id, name: definition.name, accent: definition.accent,
+        return GroupPanel(node: id, definition: definition.id, name: definition.name, accent: definition.accent,
                           uses: GroupDependencies.instances(of: definition.id, in: document.content).count,
                           side: side, sockets: sockets)
     }
 
-    /// Renames definition `id`, and the group nodes still named after it.
-    public func renameGroup(_ id: GroupID, to name: String) {
+    /// Renames definition `id`, and the group nodes still named after it. A refusal shakes `node`, the node the name was
+    /// typed for (`GroupPanel.node`), which is no longer the selected one when a click away commits the entry; with
+    /// none, it only shows the message.
+    public func renameGroup(_ id: GroupID, to name: String, on node: NodeID? = nil) {
         let trimmed = name.trimmingCharacters(in: .whitespaces)
         guard trimmed != document.definitions[id]?.name else { return }
-        perform(UndoName.renameGroup) { () throws(GraphError) in try GroupCommands.rename(id, to: trimmed, in: document.content) }
+        perform(UndoName.renameGroup, on: node) { () throws(GraphError) in
+            try GroupCommands.rename(id, to: trimmed, in: document.content)
+        }
     }
 
-    public func setGroupAccent(_ id: GroupID, to accent: AccentRole) {
+    public func setGroupAccent(_ id: GroupID, to accent: AccentRole, on node: NodeID? = nil) {
         guard accent != document.definitions[id]?.accent else { return }
-        perform(UndoName.changeGroupAccent) { () throws(GraphError) in try GroupCommands.setAccent(id, accent, in: document.content) }
+        perform(UndoName.changeGroupAccent, on: node) { () throws(GraphError) in
+            try GroupCommands.setAccent(id, accent, in: document.content)
+        }
     }
 
-    /// Renames socket `old` of `side` to `new`, on the definition, its wires inside and every group node of it.
-    public func renameGroupSocket(_ id: GroupID, side: GroupSocketSide, from old: SocketName, to new: String) {
+    /// Renames socket `old` of `side` to `new`, on the definition, its wires inside and every group node of it. A
+    /// refusal shakes `node` (see `renameGroup`).
+    public func renameGroupSocket(_ id: GroupID, side: GroupSocketSide, from old: SocketName, to new: String,
+                                  on node: NodeID? = nil) {
         let name = SocketName(new.trimmingCharacters(in: .whitespaces))
         guard name != old else { return }
-        perform(UndoName.renameSocket) { () throws(GraphError) in
+        perform(UndoName.renameSocket, on: node) { () throws(GraphError) in
             try GroupCommands.renameSocket(id, side: side, from: old, to: name, in: document.content)
         }
     }
 
-    /// Moves socket `name` of `side` one place up (`by` -1) or down (+1) the list; wires follow it by name.
-    public func moveGroupSocket(_ id: GroupID, side: GroupSocketSide, named name: SocketName, by step: Int) {
+    /// Moves socket `name` of `side` one place up (`by` -1) or down (+1) the list; wires follow it by name. A move past
+    /// either end does nothing.
+    public func moveGroupSocket(_ id: GroupID, side: GroupSocketSide, named name: SocketName, by step: Int,
+                                on node: NodeID? = nil) {
         let sockets = side == .input ? document.definitions[id]?.inputs : document.definitions[id]?.outputs
-        guard let index = sockets?.firstIndex(where: { $0.name == name }) else { return }
-        perform(UndoName.moveSocket) { () throws(GraphError) in
+        guard let sockets, let index = sockets.firstIndex(where: { $0.name == name }),
+              sockets.indices.contains(index + step) else { return }
+        perform(UndoName.moveSocket, on: node) { () throws(GraphError) in
             try GroupCommands.moveSocket(id, side: side, from: index, to: index + step, in: document.content)
         }
     }
 
     /// Removes socket `name` of `side` and its wires inside. Refused while a group node has it wired, naming that node.
-    public func removeGroupSocket(_ id: GroupID, side: GroupSocketSide, named name: SocketName) {
-        perform(UndoName.removeSocket) { () throws(GraphError) in
+    public func removeGroupSocket(_ id: GroupID, side: GroupSocketSide, named name: SocketName, on node: NodeID? = nil) {
+        perform(UndoName.removeSocket, on: node) { () throws(GraphError) in
             try GroupCommands.removeSocket(id, side: side, name: name, in: document.content)
         }
     }
 
     /// Deletes definition `id` from the document. Refused while a group node uses it.
     public func deleteGroup(_ id: GroupID) {
-        perform(UndoName.deleteGroup) { () throws(GraphError) in try GroupCommands.deleteDefinition(id, in: document.content) }
+        perform(UndoName.deleteGroup, on: nil) { () throws(GraphError) in
+            try GroupCommands.deleteDefinition(id, in: document.content)
+        }
     }
 
-    private func perform(_ name: String, _ build: () throws(GraphError) -> GraphCommand) {
+    private func perform(_ name: String, on node: NodeID?, _ build: () throws(GraphError) -> GraphCommand) {
         do {
             try document.perform(try build(), name: name)
         } catch {
-            refuse(error.message, node: selection.first)
+            refuse(error.message, node: node)
         }
     }
 }
diff --git a/Sources/CreatorEditor/GroupPanel.swift b/Sources/CreatorEditor/GroupPanel.swift
--- a/Sources/CreatorEditor/GroupPanel.swift
+++ b/Sources/CreatorEditor/GroupPanel.swift
@@ -14,6 +14,9 @@ public struct GroupPanel: Equatable, Sendable {
         public var id: String { name.rawValue }
     }
 
+    /// The node the panel is for (the group node, Group Input or Group Output): an edit the panel makes that is
+    /// refused shakes this node, whatever is selected by the time a typed name is committed.
+    public var node: NodeID
     public var definition: GroupID
     public var name: String
     public var accent: AccentRole
diff --git a/Sources/CreatorEditor/GroupPanelView.swift b/Sources/CreatorEditor/GroupPanelView.swift
--- a/Sources/CreatorEditor/GroupPanelView.swift
+++ b/Sources/CreatorEditor/GroupPanelView.swift
@@ -16,9 +16,11 @@ struct GroupPanelView: Component {
             InspectorSectionView(title: "Definition") {
                 LabeledRow(label: "Name") {
                     Spacer()
-                    TextEntry(model: model, text: panel.name) { model.renameGroup(panel.definition, to: $0) }
+                    TextEntry(model: model, text: panel.name) { model.renameGroup(panel.definition, to: $0, on: panel.node) }
                 }
-                Picker("Accent", selection: Binding(get: { panel.accent }, set: { model.setGroupAccent(panel.definition, to: $0) })) {
+                Picker("Accent", selection: Binding(
+                    get: { panel.accent }, set: { model.setGroupAccent(panel.definition, to: $0, on: panel.node) }
+                )) {
                     ForEach(AccentRole.allCases, id: \.self) { role in
                         Text(role.rawValue.capitalized).tag(role)
                     }
diff --git a/Sources/CreatorEditor/GroupSocketRowView.swift b/Sources/CreatorEditor/GroupSocketRowView.swift
--- a/Sources/CreatorEditor/GroupSocketRowView.swift
+++ b/Sources/CreatorEditor/GroupSocketRowView.swift
@@ -12,16 +12,16 @@ struct GroupSocketRowView: Component {
     var content: some ElementGroup {
         HStack(spacing: Pixels(4)) {
             TextEntry(model: model, text: socket.name.rawValue, width: 110) {
-                model.renameGroupSocket(panel.definition, side: side, from: socket.name, to: $0)
+                model.renameGroupSocket(panel.definition, side: side, from: socket.name, to: $0, on: panel.node)
             }
             Spacer()
-            Button("↑") { model.moveGroupSocket(panel.definition, side: side, named: socket.name, by: -1) }
+            Button("↑") { model.moveGroupSocket(panel.definition, side: side, named: socket.name, by: -1, on: panel.node) }
                 .help("Move up")
                 .disabled(!socket.canMoveUp)
-            Button("↓") { model.moveGroupSocket(panel.definition, side: side, named: socket.name, by: 1) }
+            Button("↓") { model.moveGroupSocket(panel.definition, side: side, named: socket.name, by: 1, on: panel.node) }
                 .help("Move down")
                 .disabled(!socket.canMoveDown)
-            Button("Remove") { model.removeGroupSocket(panel.definition, side: side, named: socket.name) }
+            Button("Remove") { model.removeGroupSocket(panel.definition, side: side, named: socket.name, on: panel.node) }
                 .help("Remove this socket and its wires inside")
         }
     }
```

- [ ] **Step 4: Run them and see them pass**

Run: `swift test --filter 'EditorGroupInspectorTests'`
Expected: all pass.

- [ ] **Step 5: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2146 tests (master + 4)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor/EditorModel+GroupInspector.swift Sources/CreatorEditor/GroupPanel.swift Sources/CreatorEditor/GroupPanelView.swift Sources/CreatorEditor/GroupSocketRowView.swift Tests/CreatorEditorTests/EditorGroupInspectorTests.swift
git commit -m "followups-editor task 1: A refused group or socket edit shakes the node it was typed for (BUG-1)"
```

### Task 2: Group (⌘G) keeps the target socket's default, optional and access (BUG-2)

**Why.** `GroupBuilder.wireIn` built the new group input as `SocketSpec(name, type, unit:, range:)`, losing default, optional and access, so unwiring the outside source left the group node idle although the inner node would have run on its default. It now copies the target spec as `GroupCommands.exposeInput` does. The existing `groupingMovesTheNodesIntoANewDefinitionAndWiresTheBoundary` expectation changes: Add's `a` and `b` inputs now carry their default 0 (`GroupCommandTests.addInputs`).

**Files:**

- Modify: `Sources/CreatorGraph/Groups/GroupBuilder.swift`
- Test: `Tests/CreatorGraphTests/Groups/GroupCommandTests.swift`

**Interfaces:**
- Consumes: `ExposeProbeNode` and `probeRegistry` (existing fixtures: a list input, an optional input, and an input with default, unit and range), `GroupCommands.group`.
- Produces: Group inputs made by ⌘G carry `access`, `defaultValue`, `unit`, `range` and `isOptional` of their target socket.

- [ ] **Step 1: Write the failing tests**

Apply this patch (tests only):

```diff
diff --git a/Tests/CreatorGraphTests/Groups/GroupCommandTests.swift b/Tests/CreatorGraphTests/Groups/GroupCommandTests.swift
--- a/Tests/CreatorGraphTests/Groups/GroupCommandTests.swift
+++ b/Tests/CreatorGraphTests/Groups/GroupCommandTests.swift
@@ -7,6 +7,8 @@ import Testing
 @MainActor
 struct GroupCommandTests {
     let scene = GroupScene()
+    /// Add's two inputs as a group keeps them: both default to 0.
+    static let addInputs = [SocketSpec("a", .number, defaultValue: .number(0)), SocketSpec("b", .number, defaultValue: .number(0))]
 
     func document(_ extra: [Node] = []) -> DocumentModel {
         var start = graph(scene.nodes + extra, scene.links)
@@ -28,7 +30,7 @@ struct GroupCommandTests {
 
         let definition = try #require(document.definitions.values.first)
         #expect(definition.name == "Group")
-        #expect(definition.inputs == [SocketSpec("a", .number), SocketSpec("b", .number)])
+        #expect(definition.inputs == Self.addInputs, "each keeps its target socket's default")
         #expect(definition.outputs == [SocketSpec("sum", .number), SocketSpec("sum2", .number)])
         #expect(definition.graph.nodes[scene.a1.id]?.position == Vector2(0, 0))
         #expect(definition.graph.nodes[scene.a2.id]?.position == Vector2(0, 100))
@@ -53,6 +55,50 @@ struct GroupCommandTests {
         #expect(document.results[scene.sink.id]?.outputs?["value"]?.numbers == [7])
     }
 
+    /// A wire from outside becomes an input that keeps what the target socket has (access, optional, default, unit and
+    /// range), as the "+" drop does (`GroupCommands.exposeInput`), so unwiring it later leaves the part as it was.
+    @Test func anInputWiredFromOutsideKeepsTheTargetSocketsSettings() throws {
+        let probe = makeNode(ExposeProbeNode.self)
+        let sources = (0..<3).map { _ in makeNode(AddNode.self) }
+        var content = GraphContent(graph: graph([probe] + sources, [
+            link(sources[0], "sum", probe, "values"), link(sources[1], "sum", probe, "maybe"),
+            link(sources[2], "sum", probe, "length"),
+        ]))
+        let edit = try GroupCommands.group([probe.id], in: .root, of: content, registry: probeRegistry)
+        try content.apply(edit.command, registry: probeRegistry)
+        let definition = try #require(content.definitions.values.first)
+        #expect(Set(definition.inputs.map(\.name)) == ["values", "maybe", "length"])
+        let byName = Dictionary(uniqueKeysWithValues: definition.inputs.map { ($0.name, $0) })
+        #expect(byName["values"] == SocketSpec("values", .number, access: .list))
+        #expect(byName["maybe"] == SocketSpec("maybe", .number, optional: true))
+        #expect(byName["length"] == SocketSpec("length", .number, defaultValue: .number(5), unit: .millimetres, range: 1...20))
+    }
+
+    @Test func unwiringAGroupedInputLeavesTheGroupRunningOnTheTargetsDefault() async throws {
+        let document = document()
+        let edit = try group([scene.a1.id, scene.a2.id], in: document)
+        let node = try #require(edit.selection.first.flatMap { document.graph.nodes[$0] })
+        let definition = try #require(document.definitions.values.first)
+        #expect(definition.inputs == Self.addInputs, "each keeps its target socket's default")
+        try document.perform(.disconnect(link(scene.c2, "value", node, "b")))
+        await document.waitForEvaluation()
+        // a1 = 2 + 2 = 4 and a2 = a1 + b, with b on its default 0 rather than the group going idle.
+        #expect(document.results[scene.sink.id]?.outputs?["value"]?.numbers == [4])
+    }
+
+    /// Group, unwire an outside source, Ungroup: the spliced nodes evaluate as the group did.
+    @Test func ungroupingAfterUnwiringAGroupedInputEvaluatesAsBefore() async throws {
+        let document = document()
+        let grouped = try group([scene.a1.id, scene.a2.id], in: document)
+        let node = try #require(grouped.selection.first)
+        try document.perform(.disconnect(link(scene.c2, "value", document.graph.nodes[node] ?? scene.c2, "b")))
+        let edit = try GroupCommands.ungroup(node, in: .root, of: document.content, registry: testRegistry)
+        try document.perform(edit.command)
+        #expect(document.definitions.isEmpty)
+        await document.waitForEvaluation()
+        #expect(document.results[scene.sink.id]?.outputs?["value"]?.numbers == [4], "b is on its default 0, as in the group")
+    }
+
     @Test func groupingIsOneUndoStep() throws {
         let document = document()
         let before = document.content
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter 'GroupCommandTests'`
Expected: FAIL (6 issues): `anInputWiredFromOutsideKeepsTheTargetSocketsSettings`, `unwiringAGroupedInputLeavesTheGroupRunningOnTheTargetsDefault` and the updated `groupingMovesTheNodesIntoANewDefinitionAndWiresTheBoundary`. `ungroupingAfterUnwiringAGroupedInputEvaluatesAsBefore` is a pin (Review Focus 2) and passes before and after.

- [ ] **Step 3: Implement**

Apply this patch (sources):

```diff
diff --git a/Sources/CreatorGraph/Groups/GroupBuilder.swift b/Sources/CreatorGraph/Groups/GroupBuilder.swift
--- a/Sources/CreatorGraph/Groups/GroupBuilder.swift
+++ b/Sources/CreatorGraph/Groups/GroupBuilder.swift
@@ -55,7 +55,10 @@ struct GroupBuilder {
                 sockets.inputs(for: node).first { $0.name == link.to.socket }
             }
             name = GroupNaming.uniqueSocketName(link.to.socket, among: definition.inputs.map(\.name))
-            definition.inputs.append(SocketSpec(name, type, unit: target?.unit ?? .none, range: target?.range))
+            // As `GroupCommands.exposeInput` does for the "+" drop, so unwiring the source later leaves the part as it was.
+            definition.inputs.append(SocketSpec(name, type, access: target?.access ?? .item, defaultValue: target?.defaultValue,
+                                                unit: target?.unit ?? .none, range: target?.range,
+                                                optional: target?.isOptional ?? false))
             inputs[link.from] = name
             outside.append(Link(from: link.from, to: Endpoint(node: groupNode.id, socket: name)))
         }
```

- [ ] **Step 4: Run them and see them pass**

Run: `swift test --filter 'GroupCommandTests'`
Expected: all pass.

- [ ] **Step 5: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2149 tests (master + 7)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorGraph/Groups/GroupBuilder.swift Tests/CreatorGraphTests/Groups/GroupCommandTests.swift
git commit -m "followups-editor task 2: Group (⌘G) keeps the target socket's default, optional and access (BUG-2)"
```

### Task 3: An exposed output keeps its optional flag (ED-2)

**Why.** `GroupCommands.exposeOutput` copied the source socket's type and unit but not `isOptional`, so an optional inner output became a required group output in the definition. (Evaluation does not read it for group nodes today, because the evaluator builds a group's outputs from Group Output's inputs, which `NodeRegistry.inputs(for:)` already forces optional; the flag is carried so the definition says what the inner socket says. Recorded as a user decision.)

**Files:**

- Modify: `Sources/CreatorGraph/Groups/GroupCommands+Expose.swift`
- Test: `Tests/CreatorGraphTests/Groups/GroupExposeTests.swift`

**Interfaces:**
- Consumes: `OptionalOutputNode` (existing test node with an optional output `sometimes`), `define(_:inputs:outputs:nodes:links:)`.
- Produces: `exposeOutput` appends `SocketSpec(name, type, unit:, optional: spec.isOptional)`.

- [ ] **Step 1: Write the failing tests**

Apply this patch (tests only):

```diff
diff --git a/Tests/CreatorGraphTests/Groups/GroupExposeTests.swift b/Tests/CreatorGraphTests/Groups/GroupExposeTests.swift
--- a/Tests/CreatorGraphTests/Groups/GroupExposeTests.swift
+++ b/Tests/CreatorGraphTests/Groups/GroupExposeTests.swift
@@ -131,6 +131,20 @@ struct GroupExposeTests {
         #expect(model.definitions[probeDefinition.id]?.outputs.last?.unit == .millimetres)
     }
 
+    @Test func anOptionalOutputStaysOptional() throws {
+        let source = makeNode(OptionalOutputNode.self)
+        let maybe = define("Maybe", outputs: [], nodes: [source]) { _, _ in [] }
+        let model = DocumentModel(file: GraphFile(graph: graph([instance(of: maybe)]), definitions: table([maybe])),
+                                  registry: testRegistry, kernel: FakeKernel())
+        let output = try #require(maybe.outputNode)
+        for socket in ["always", "sometimes"] {
+            let command = try GroupCommands.exposeOutput(from: Endpoint(node: source.id, socket: SocketName(socket)),
+                                                         on: output.id, in: maybe.id, of: model.content, registry: testRegistry)
+            try model.perform(command)
+        }
+        #expect(model.definitions[maybe.id]?.outputs == [SocketSpec("always", .number), SocketSpec("sometimes", .number, optional: true)])
+    }
+
     @Test func aSecondInputDropFromTheSameSocketGetsAnotherName() throws {
         let document = document(instance(of: definition))
         let input = try #require(definition.inputNode)
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter 'GroupExposeTests'`
Expected: FAIL (1 issue): `anOptionalOutputStaysOptional`.

- [ ] **Step 3: Implement**

Apply this patch (sources):

```diff
diff --git a/Sources/CreatorGraph/Groups/GroupCommands+Expose.swift b/Sources/CreatorGraph/Groups/GroupCommands+Expose.swift
--- a/Sources/CreatorGraph/Groups/GroupCommands+Expose.swift
+++ b/Sources/CreatorGraph/Groups/GroupCommands+Expose.swift
@@ -5,7 +5,7 @@ import CreatorKernel
 /// one undo step.
 extension GroupCommands {
     /// Dropping a wire from `source`, an output of a node inside definition `id`, on Group Output's "+" (`boundary`):
-    /// a new output named after the source socket (made unique), of its type and unit, wired from it.
+    /// a new output named after the source socket (made unique), of its type, unit and optional, wired from it.
     public static func exposeOutput(from source: Endpoint, on boundary: NodeID, in id: GroupID, of content: GraphContent,
                                     registry: NodeRegistry) throws(GraphError) -> GraphCommand {
         guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
@@ -15,7 +15,7 @@ extension GroupCommands {
               let spec = sockets.outputs(for: node).first(where: { $0.name == source.socket }) else { throw missingSocket }
         var interface = definition.interface
         let name = GroupNaming.uniqueSocketName(source.socket, among: interface.outputs.map(\.name))
-        interface.outputs.append(SocketSpec(name, spec.type, unit: spec.unit))
+        interface.outputs.append(SocketSpec(name, spec.type, unit: spec.unit, optional: spec.isOptional))
         let wire = Link(from: source, to: Endpoint(node: output.id, socket: name))
         return .batch([.setInterface(id, interface), GraphCommand.connect(wire).at(.definition(id))])
     }
```

- [ ] **Step 4: Run them and see them pass**

Run: `swift test --filter 'GroupExposeTests'`
Expected: all pass.

- [ ] **Step 5: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2150 tests (master + 8)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorGraph/Groups/GroupCommands+Expose.swift Tests/CreatorGraphTests/Groups/GroupExposeTests.swift
git commit -m "followups-editor task 3: An exposed output keeps its optional flag (ED-2)"
```

### Task 4: Adding a stale or unknown library key adds nothing (ED-3)

**Why.** `addNode(_:atScreen:)` fell back to `registry.makeNode(typeID, ...)` when `libraryNode(for:)` returned nil, so a stale `group:<uuid>` (or any unknown key reaching the palette or a drop) made a Missing node of that type. Only `dropFromLibrary` guarded it. Now it refuses with a caption and returns false.

**Files:**

- Modify: `Sources/CreatorEditor/EditorModel+Editing.swift`
- Test: `Tests/CreatorEditorTests/LibraryGroupsTests.swift`

**Interfaces:**
- Consumes: `libraryNode(for:at:)`, `refuse(_:node:)`.
- Produces: `addNode` returns false and sets `refusal.message == "That node isn't in the library any more."` for a key that is neither a registered type nor an existing definition.

- [ ] **Step 1: Write the failing tests**

Apply this patch (tests only):

```diff
diff --git a/Tests/CreatorEditorTests/LibraryGroupsTests.swift b/Tests/CreatorEditorTests/LibraryGroupsTests.swift
--- a/Tests/CreatorEditorTests/LibraryGroupsTests.swift
+++ b/Tests/CreatorEditorTests/LibraryGroupsTests.swift
@@ -91,6 +91,21 @@ struct LibraryGroupsTests {
         #expect(editor.graph.nodes.count == 3)
     }
 
+    /// The palette and the drop both end in `addNode(_:atScreen:)`; a key that names nothing registered, or a definition
+    /// that is gone, adds no node (not a "missing" node of that type) and says so.
+    @Test func addingAStaleOrUnknownKeyAddsNothingAndSaysSo() throws {
+        let grouped = try GroupedEditor()
+        let editor = grouped.editor
+        let before = editor.document.content
+        #expect(!editor.addNode("group:" + UUID().uuidString, atScreen: Vector2(50, 50)))
+        #expect(editor.refusal?.message == "That node isn't in the library any more.")
+        editor.clearRefusal()
+        #expect(!editor.addNode("no.such.type", atScreen: Vector2(50, 50)))
+        #expect(editor.refusal?.message == "That node isn't in the library any more.")
+        #expect(editor.document.content == before)
+        #expect(editor.addNode(NumberTestNode.typeID, atScreen: Vector2(50, 50)), "a registered type still goes in")
+    }
+
     @Test func aGroupCantBePlacedInsideItself() throws {
         let grouped = try GroupedEditor()
         let editor = placed(grouped.editor)
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter 'LibraryGroupsTests'`
Expected: FAIL (5 issues): `addingAStaleOrUnknownKeyAddsNothingAndSaysSo`.

- [ ] **Step 3: Implement**

Apply this patch (sources):

```diff
diff --git a/Sources/CreatorEditor/EditorModel+Editing.swift b/Sources/CreatorEditor/EditorModel+Editing.swift
--- a/Sources/CreatorEditor/EditorModel+Editing.swift
+++ b/Sources/CreatorEditor/EditorModel+Editing.swift
@@ -78,11 +78,16 @@ extension EditorModel {
     }
 
     /// Adds a node of `typeID` with its top-left corner at `screen` (canvas-local screen points: under the palette,
-    /// or where a library node was dropped) and selects it, as one undo step. Returns whether the graph took it.
+    /// or where a library node was dropped) and selects it, as one undo step. Returns whether the graph took it. A key
+    /// that names no registered type, or a group definition that is gone, adds nothing and says so.
     @discardableResult
     public func addNode(_ typeID: String, atScreen screen: Vector2) -> Bool {
         let position = flow.stored(transform.toCanvas(screen))
-        return add(libraryNode(for: typeID, at: position) ?? registry.makeNode(typeID, at: position))
+        guard let node = libraryNode(for: typeID, at: position) else {
+            refuse("That node isn't in the library any more.", node: nil)
+            return false
+        }
+        return add(node)
     }
 
     /// Adds `node` (made by `NodeRegistry.makeNode`) and selects it, as one undo step. Returns false, having shown
```

- [ ] **Step 4: Run them and see them pass**

Run: `swift test --filter 'LibraryGroupsTests'`
Expected: all pass.

- [ ] **Step 5: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2151 tests (master + 9)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor/EditorModel+Editing.swift Tests/CreatorEditorTests/LibraryGroupsTests.swift
git commit -m "followups-editor task 4: Adding a stale or unknown library key adds nothing (ED-3)"
```

### Task 5: A successful edit clears the refusal caption (ED-4)

**Why.** `clearRefusal()` was documented "when the user starts another edit" and never called, so a caption stayed its full 2.3 s after the person had fixed the problem. `edit(...)`, `insert(...)` (paste, duplicate) and the group inspector's `perform` now call it on success. It no longer assigns when there is nothing to clear, so a slider drag does not invalidate observers every sample.

**Files:**

- Modify: `Sources/CreatorEditor/EditorModel.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Levels.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Editing.swift`
- Modify: `Sources/CreatorEditor/EditorModel+GroupInspector.swift`
- Test: `Tests/CreatorEditorTests/RefusalShakeTests.swift`

**Interfaces:**
- Consumes: `EditorModel.refuse(_:node:)`, `GroupedEditor`.
- Produces: `clearRefusal()` is called by every successful `edit`, `insert` and group-inspector command.

- [ ] **Step 1: Write the failing tests**

Apply this patch (tests only):

```diff
diff --git a/Tests/CreatorEditorTests/RefusalShakeTests.swift b/Tests/CreatorEditorTests/RefusalShakeTests.swift
--- a/Tests/CreatorEditorTests/RefusalShakeTests.swift
+++ b/Tests/CreatorEditorTests/RefusalShakeTests.swift
@@ -38,6 +38,31 @@ struct RefusalShakeTests {
         #expect(editor.shakeCount(of: extrude.id) == 1)
     }
 
+    /// The caption says why the last edit was refused; once another edit goes through it is stale, so it goes at once
+    /// (the shake count stays: it only ever counts refusals).
+    @Test func aSuccessfulEditClearsTheCaptionAtOnce() {
+        let editor = makeEditor([number, extrude])
+        editor.connect(wire(number, "value", extrude, "profile"))
+        #expect(editor.refusal != nil)
+        editor.connect(wire(number, "value", extrude, "distance"))
+        #expect(editor.refusal == nil)
+        #expect(editor.shakeCount(of: extrude.id) == 1)
+    }
+
+    @Test func aPasteOrAGroupEditClearsItToo() throws {
+        let editor = makeEditor([number, extrude])
+        editor.connect(wire(number, "value", extrude, "profile"))
+        editor.selection = [number.id]
+        editor.copySelection()
+        editor.paste()
+        #expect(editor.refusal == nil, "a paste is an edit")
+        let grouped = try GroupedEditor()
+        grouped.editor.renameGroup(grouped.definition.id, to: " ")
+        #expect(grouped.editor.refusal?.message == "A group needs a name.")
+        grouped.editor.renameGroup(grouped.definition.id, to: "Rib")
+        #expect(grouped.editor.refusal == nil, "and so is a rename")
+    }
+
     @Test func aRefusalNamingNoNodeShakesNothing() {
         let editor = makeEditor([number])
         editor.refuse("Nothing to group.", node: nil)
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter 'RefusalShakeTests'`
Expected: FAIL (3 issues, with the source patch not applied): `aSuccessfulEditClearsTheCaptionAtOnce`, `aPasteOrAGroupEditClearsItToo`.

- [ ] **Step 3: Implement**

Apply this patch (sources):

```diff
diff --git a/Sources/CreatorEditor/EditorModel+Editing.swift b/Sources/CreatorEditor/EditorModel+Editing.swift
--- a/Sources/CreatorEditor/EditorModel+Editing.swift
+++ b/Sources/CreatorEditor/EditorModel+Editing.swift
@@ -158,6 +158,7 @@ extension EditorModel {
             // The definitions are added to the document, the nodes and comments to the level shown.
             try document.perform(.batch(merge.additions.map { .addDefinition($0) } + [GraphCommand.batch(commands).at(graphPath)]),
                                  name: name)
+            clearRefusal()
             return CanvasSelection(nodes: Set(mapping.values), comments: comments)
         } catch {
             refuse(error.message, node: nil)
diff --git a/Sources/CreatorEditor/EditorModel+GroupInspector.swift b/Sources/CreatorEditor/EditorModel+GroupInspector.swift
--- a/Sources/CreatorEditor/EditorModel+GroupInspector.swift
+++ b/Sources/CreatorEditor/EditorModel+GroupInspector.swift
@@ -81,6 +81,7 @@ extension EditorModel {
     private func perform(_ name: String, on node: NodeID?, _ build: () throws(GraphError) -> GraphCommand) {
         do {
             try document.perform(try build(), name: name)
+            clearRefusal()
         } catch {
             refuse(error.message, node: node)
         }
diff --git a/Sources/CreatorEditor/EditorModel+Levels.swift b/Sources/CreatorEditor/EditorModel+Levels.swift
--- a/Sources/CreatorEditor/EditorModel+Levels.swift
+++ b/Sources/CreatorEditor/EditorModel+Levels.swift
@@ -25,9 +25,10 @@ extension EditorModel {
     public var rootGraph: Graph { document.graph }
 
     /// Applies `command` to the graph the panel shows, as one undo step named `name` (`DocumentModel.perform(_:at:)`;
-    /// without one the step is named from the command).
+    /// without one the step is named from the command). An edit that goes through clears the refusal caption.
     public func edit(_ command: GraphCommand, coalescingKey: String? = nil, name: String? = nil) throws(GraphError) {
         try document.perform(command, at: graphPath, coalescingKey: coalescingKey, name: name)
+        clearRefusal()
     }
 
     /// The result of node `id` of the graph shown: from the top-level results, or from the results inside the group
diff --git a/Sources/CreatorEditor/EditorModel.swift b/Sources/CreatorEditor/EditorModel.swift
--- a/Sources/CreatorEditor/EditorModel.swift
+++ b/Sources/CreatorEditor/EditorModel.swift
@@ -214,9 +214,10 @@ public final class EditorModel {
         shakeCounts[node] ?? 0
     }
 
-    /// Clears the refusal message (for example when the user starts another edit).
+    /// Clears the refusal message: an edit that goes through calls it (`edit(_:coalescingKey:name:)`, a paste, a group
+    /// edit), as the caption would otherwise go on explaining a refusal the person has moved past.
     public func clearRefusal() {
-        refusal = nil
+        if refusal != nil { refusal = nil }
     }
 
     func setClipboard(_ clipboard: NodeClipboard) {
```

- [ ] **Step 4: Run them and see them pass**

Run: `swift test --filter 'RefusalShakeTests'`
Expected: all pass.

- [ ] **Step 5: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2153 tests (master + 11)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor/EditorModel+Editing.swift Sources/CreatorEditor/EditorModel+GroupInspector.swift Sources/CreatorEditor/EditorModel+Levels.swift Sources/CreatorEditor/EditorModel.swift Tests/CreatorEditorTests/RefusalShakeTests.swift
git commit -m "followups-editor task 5: A successful edit clears the refusal caption (ED-4)"
```

### Task 6: The canvas frame leaves room for the refusal caption line (ED-5)

**Why.** While a refusal shows, `GraphPanel` puts a caption line under the body, which shrinks the canvas by one line and the spacing above it, but `GraphPanelLayout` (the editor's idea of where the canvas is) did not know. `visibleCanvasCentre` was half a line low and `endLibraryDrag` accepted a drop on the caption text. `bodyFrame`, `libraryFrame` and `canvasFrame` take `showsRefusal` (default false), `canvasFrameInWindow` and `drawnCanvasRect` pass `refusal != nil`, and the caption gets `frame(minHeight: refusalLineHeight)` so the model is exact for a one-line message. A message that wraps takes more room than modelled (Risks).

**Files:**

- Modify: `Sources/CreatorEditor/GraphPanelLayout.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Placement.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Culling.swift`
- Modify: `Sources/CreatorEditor/GraphPanel.swift`
- Test: `Tests/CreatorEditorTests/LibraryDragTests.swift`
- Test: `Tests/CreatorEditorTests/PanelPlacementTests.swift`

**Interfaces:**
- Consumes: `PanelPlacement`, `EditorModel.placement`, `endLibraryDrag(_:from:at:)`.
- Produces: `GraphPanelLayout.refusalLineHeight = 16.0`; `bodyFrame(inPanelOf:showsRefusal:)`, `libraryFrame(inPanelOf:flow:showsRefusal:)`, `canvasFrame(inPanelOf:flow:showsLibrary:showsRefusal:)`.

- [ ] **Step 1: Write the failing tests**

Apply this patch (tests only):

```diff
diff --git a/Tests/CreatorEditorTests/LibraryDragTests.swift b/Tests/CreatorEditorTests/LibraryDragTests.swift
--- a/Tests/CreatorEditorTests/LibraryDragTests.swift
+++ b/Tests/CreatorEditorTests/LibraryDragTests.swift
@@ -44,6 +44,19 @@ struct LibraryDragTests {
         #expect(!editor.document.canUndo, "one step")
     }
 
+    /// The refusal caption sits under the canvas, so a release on it is off the canvas.
+    @Test func aReleaseOnTheRefusalCaptionAddsNothing() throws {
+        let editor = placed(.bottom)
+        let start = try rowPoint(editor)
+        let canvas = try #require(editor.canvasFrameInWindow)
+        let onCaption = canvas.origin + Vector2(120, canvas.size.y - 4)
+        editor.refuse("No.", node: nil)
+        #expect(!editor.endLibraryDrag(FilletTestNode.typeID, from: start, at: onCaption))
+        #expect(editor.graph.nodes.isEmpty)
+        editor.clearRefusal()
+        #expect(editor.endLibraryDrag(FilletTestNode.typeID, from: start, at: onCaption), "the same spot is canvas without it")
+    }
+
     /// Released over the library itself, the viewport, the inspector or outside the window: nothing is added.
     @Test(arguments: [DockSide.left, .bottom])
     func aReleaseOffTheCanvasAddsNothing(_ dock: DockSide) throws {
diff --git a/Tests/CreatorEditorTests/PanelPlacementTests.swift b/Tests/CreatorEditorTests/PanelPlacementTests.swift
--- a/Tests/CreatorEditorTests/PanelPlacementTests.swift
+++ b/Tests/CreatorEditorTests/PanelPlacementTests.swift
@@ -32,6 +32,37 @@ struct PanelPlacementTests {
                 == CanvasRect(origin: Vector2(10, 230), size: Vector2(380, 460)))
     }
 
+    /// A refusal message showing under the body takes one caption line and the spacing above it from the body's bottom,
+    /// so the editor's idea of where the canvas is matches what `GraphPanel` lays out.
+    @Test func aRefusalLineTakesOneCaptionLineFromTheBodysBottom() {
+        let line = Vector2(0, GraphPanelLayout.refusalLineHeight + GraphPanelLayout.spacing)
+        let size = Vector2(800, 300)
+        let body = GraphPanelLayout.bodyFrame(inPanelOf: size)
+        let shown = GraphPanelLayout.bodyFrame(inPanelOf: size, showsRefusal: true)
+        #expect(shown.origin == body.origin && shown.size == body.size - line)
+        #expect(GraphPanelLayout.bodyFrame(inPanelOf: Vector2(10, 10), showsRefusal: true).size == .zero, "never negative")
+        for (flow, library) in [(CanvasFlow.horizontal, false), (.horizontal, true), (.vertical, false), (.vertical, true)] {
+            let plain = GraphPanelLayout.canvasFrame(inPanelOf: size, flow: flow, showsLibrary: library)
+            let withLine = GraphPanelLayout.canvasFrame(inPanelOf: size, flow: flow, showsLibrary: library, showsRefusal: true)
+            #expect(withLine.origin == plain.origin && withLine.size == plain.size - line)
+        }
+        #expect(GraphPanelLayout.libraryFrame(inPanelOf: size, flow: .horizontal, showsRefusal: true).size
+                == GraphPanelLayout.libraryFrame(inPanelOf: size, flow: .horizontal).size - line)
+    }
+
+    @Test func theCanvasShrinksWhileARefusalShows() {
+        let editor = makeEditor([], dock: .bottom)
+        let panel = CanvasRect(origin: Vector2(12, 388), size: Vector2(976, 300))
+        editor.placement = { PanelPlacement(window: Vector2(1000, 700), panel: panel) }
+        #expect(editor.canvasFrameInWindow?.size == Vector2(772, 244))
+        #expect(editor.drawnCanvasRect != nil)
+        editor.refuse("No.", node: nil)
+        #expect(editor.canvasFrameInWindow?.size == Vector2(772, 220), "one 16-point line and the 8 points above it")
+        #expect(editor.visibleCanvasCentre == Vector2(386, 110))
+        editor.clearRefusal()
+        #expect(editor.canvasFrameInWindow?.size == Vector2(772, 244))
+    }
+
     @Test func theHostPlacesTheCanvasInTheWindow() {
         let editor = makeEditor([], dock: .bottom)
         #expect(editor.canvasFrameInWindow == nil, "no host, no window coordinates")
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter 'PanelPlacementTests'`
Expected: FAIL to compile: `type 'GraphPanelLayout' has no member 'refusalLineHeight'`, `extra argument 'showsRefusal' in call`.

- [ ] **Step 3: Implement**

Apply this patch (sources):

```diff
diff --git a/Sources/CreatorEditor/EditorModel+Culling.swift b/Sources/CreatorEditor/EditorModel+Culling.swift
--- a/Sources/CreatorEditor/EditorModel+Culling.swift
+++ b/Sources/CreatorEditor/EditorModel+Culling.swift
@@ -12,7 +12,8 @@ extension EditorModel {
     /// panel is hidden, when everything is drawn.
     public var drawnCanvasRect: CanvasRect? {
         guard isPanelVisible, let placement = panelPlacement else { return nil }
-        let size = GraphPanelLayout.canvasFrame(inPanelOf: placement.panel.size, flow: flow, showsLibrary: showsLibrary).size
+        let size = GraphPanelLayout.canvasFrame(inPanelOf: placement.panel.size, flow: flow, showsLibrary: showsLibrary,
+                                                showsRefusal: refusal != nil).size
         let margin = Vector2(Self.cullingMargin, Self.cullingMargin)
         return CanvasRect(corner: transform.toCanvas(.zero - margin), transform.toCanvas(size + margin))
     }
diff --git a/Sources/CreatorEditor/EditorModel+Placement.swift b/Sources/CreatorEditor/EditorModel+Placement.swift
--- a/Sources/CreatorEditor/EditorModel+Placement.swift
+++ b/Sources/CreatorEditor/EditorModel+Placement.swift
@@ -9,7 +9,8 @@ extension EditorModel {
     /// The canvas's frame in window points; `nil` while the panel is hidden or not placed.
     public var canvasFrameInWindow: CanvasRect? {
         guard isPanelVisible, let placement = panelPlacement else { return nil }
-        let local = GraphPanelLayout.canvasFrame(inPanelOf: placement.panel.size, flow: flow, showsLibrary: showsLibrary)
+        let local = GraphPanelLayout.canvasFrame(inPanelOf: placement.panel.size, flow: flow, showsLibrary: showsLibrary,
+                                                 showsRefusal: refusal != nil)
         return CanvasRect(origin: placement.panel.origin + local.origin, size: local.size)
     }
 
diff --git a/Sources/CreatorEditor/GraphPanel.swift b/Sources/CreatorEditor/GraphPanel.swift
--- a/Sources/CreatorEditor/GraphPanel.swift
+++ b/Sources/CreatorEditor/GraphPanel.swift
@@ -37,6 +37,7 @@ public struct GraphPanel: Component {
                         .frame(maxWidth: .infinity, maxHeight: .infinity)
                     if let refusal = model.refusal {
                         Text(refusal.message).font(.caption).foregroundStyle(Palette(themes).statusError.color)
+                            .frame(minHeight: GraphPanelLayout.refusalLineHeight.px)
                     }
                 }
             }
diff --git a/Sources/CreatorEditor/GraphPanelLayout.swift b/Sources/CreatorEditor/GraphPanelLayout.swift
--- a/Sources/CreatorEditor/GraphPanelLayout.swift
+++ b/Sources/CreatorEditor/GraphPanelLayout.swift
@@ -22,17 +22,22 @@ public enum GraphPanelLayout {
     /// The canvas size assumed while the host hasn't placed the panel (headless tests): the centre of a small panel.
     public static let fallbackCanvasSize = Vector2(400, 300)
 
+    /// The refusal message's caption line under the body (`GraphPanel`): one `.caption` line. A message long enough to wrap
+    /// takes more, which this does not model.
+    public static let refusalLineHeight = 16.0
+
     /// The body under the header inside a panel of `size`, in panel-local points. It runs to the panel's padding; a
-    /// refusal message showing under it takes one line from its bottom.
-    public static func bodyFrame(inPanelOf size: Vector2) -> CanvasRect {
+    /// refusal message showing under it (`showsRefusal`) takes one line, and the spacing above it, from its bottom.
+    public static func bodyFrame(inPanelOf size: Vector2, showsRefusal: Bool = false) -> CanvasRect {
         let origin = Vector2(glassPadding, glassPadding + headerHeight + spacing)
+        let refusal = showsRefusal ? refusalLineHeight + spacing : 0
         return CanvasRect(origin: origin, size: Vector2(max(0, size.x - 2 * glassPadding),
-                                                        max(0, size.y - origin.y - glassPadding)))
+                                                        max(0, size.y - origin.y - glassPadding - refusal)))
     }
 
     /// The node library's frame in the body, for a panel of `size` showing the graph in `flow`.
-    public static func libraryFrame(inPanelOf size: Vector2, flow: CanvasFlow) -> CanvasRect {
-        let body = bodyFrame(inPanelOf: size)
+    public static func libraryFrame(inPanelOf size: Vector2, flow: CanvasFlow, showsRefusal: Bool = false) -> CanvasRect {
+        let body = bodyFrame(inPanelOf: size, showsRefusal: showsRefusal)
         switch flow {
         case .horizontal: return CanvasRect(origin: body.origin, size: Vector2(min(libraryExtent, body.size.x), body.size.y))
         case .vertical: return CanvasRect(origin: body.origin, size: Vector2(body.size.x, min(libraryExtent, body.size.y)))
@@ -40,8 +45,9 @@ public enum GraphPanelLayout {
     }
 
     /// The canvas's frame: the whole body, or the body beside or below the library.
-    public static func canvasFrame(inPanelOf size: Vector2, flow: CanvasFlow, showsLibrary: Bool) -> CanvasRect {
-        let body = bodyFrame(inPanelOf: size)
+    public static func canvasFrame(inPanelOf size: Vector2, flow: CanvasFlow, showsLibrary: Bool,
+                                   showsRefusal: Bool = false) -> CanvasRect {
+        let body = bodyFrame(inPanelOf: size, showsRefusal: showsRefusal)
         guard showsLibrary else { return body }
         let inset = libraryExtent + spacing
         switch flow {
```

- [ ] **Step 4: Run them and see them pass**

Run: `swift test --filter 'PanelPlacementTests'`
Expected: all pass.

- [ ] **Step 5: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2156 tests (master + 14)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor/EditorModel+Culling.swift Sources/CreatorEditor/EditorModel+Placement.swift Sources/CreatorEditor/GraphPanel.swift Sources/CreatorEditor/GraphPanelLayout.swift Tests/CreatorEditorTests/LibraryDragTests.swift Tests/CreatorEditorTests/PanelPlacementTests.swift
git commit -m "followups-editor task 6: The canvas frame leaves room for the refusal caption line (ED-5)"
```

### Task 7: A comment menu item chosen mid-drag does nothing (ED-6)

**Why.** `choose(_:at:)` ran the item even while a move was under way, adding a step in the middle of the move's coalesced run (the keys already refuse mid-drag in `performSelectionCommand`). It now returns when `interaction != nil`.

**Files:**

- Modify: `Sources/CreatorEditor/EditorModel+CommentCreation.swift`
- Test: `Tests/CreatorEditorTests/CommentCreationTests.swift`

**Interfaces:**
- Consumes: `EditorModel.interaction`.
- Produces: `choose(_:at:)` is a no-op during a drag.

- [ ] **Step 1: Write the failing tests**

Apply this patch (tests only):

```diff
diff --git a/Tests/CreatorEditorTests/CommentCreationTests.swift b/Tests/CreatorEditorTests/CommentCreationTests.swift
--- a/Tests/CreatorEditorTests/CommentCreationTests.swift
+++ b/Tests/CreatorEditorTests/CommentCreationTests.swift
@@ -28,6 +28,23 @@ struct CommentCreationTests {
         #expect(editor.graph.stickies.isEmpty && !editor.document.canUndo, "one undo step")
     }
 
+    /// A menu item chosen while a drag is under way (a secondary press during a primary drag) would add a step in the
+    /// middle of the move's coalesced run, as the keys never do (`performSelectionCommand`).
+    @Test func aMenuItemChosenMidDragChangesNothingAndTheMoveStaysOneStep() {
+        let editor = makeEditor([a])
+        let press = editor.screenPoint(in: a.id)
+        editor.pointerDragged(from: press, to: press + Vector2(20, 0))
+        guard case .moving? = editor.interaction else { Issue.record("expected a move"); return }
+        editor.choose(.addNote, at: Vector2(300, 300))
+        editor.choose(.frameSelection, at: nil)
+        #expect(editor.graph.stickies.isEmpty && editor.graph.frames.isEmpty)
+        editor.pointerDragged(from: press, to: press + Vector2(40, 0))
+        editor.pointerReleased(from: press, at: press + Vector2(40, 0))
+        #expect(editor.graph.nodes[a.id]?.position == a.position + Vector2(40, 0))
+        editor.document.undo()
+        #expect(editor.graph.nodes[a.id]?.position == a.position && !editor.document.canUndo, "the whole drag, one step")
+    }
+
     @Test func addNoteReadsTheTransformAndTheLeftDocksFlow() throws {
         let editor = makeEditor([], dock: .left)
         editor.transform = CanvasTransform(offset: Vector2(10, 20), zoom: 2)
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter 'CommentCreationTests'`
Expected: FAIL (2 issues): `aMenuItemChosenMidDragChangesNothingAndTheMoveStaysOneStep`.

- [ ] **Step 3: Implement**

Apply this patch (sources):

```diff
diff --git a/Sources/CreatorEditor/EditorModel+CommentCreation.swift b/Sources/CreatorEditor/EditorModel+CommentCreation.swift
--- a/Sources/CreatorEditor/EditorModel+CommentCreation.swift
+++ b/Sources/CreatorEditor/EditorModel+CommentCreation.swift
@@ -38,8 +38,10 @@ extension EditorModel {
         }
     }
 
-    /// Runs a context-menu item; `screen` is where the menu opened (`nil` for a keyboard open: the visible centre).
+    /// Runs a context-menu item; `screen` is where the menu opened (`nil` for a keyboard open: the visible centre). It does
+    /// nothing while a drag is under way, as the keys do nothing then: the item's edit would split the drag's undo step.
     public func choose(_ item: CanvasMenuItem, at screen: Vector2?) {
+        guard interaction == nil else { return }
         switch item {
         case .addNote:
             if let screen { addNote(atScreen: screen) } else { addNoteAtPointer() }
```

- [ ] **Step 4: Run them and see them pass**

Run: `swift test --filter 'CommentCreationTests'`
Expected: all pass.

- [ ] **Step 5: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2157 tests (master + 15)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor/EditorModel+CommentCreation.swift Tests/CreatorEditorTests/CommentCreationTests.swift
git commit -m "followups-editor task 7: A comment menu item chosen mid-drag does nothing (ED-6)"
```

### Task 8: Breadcrumb tooltips and a Missing node's "+" socket (ED-7)

**Why.** Two of ED-7's four small items are real. (a) Every crumb's tooltip said "(⌘↑)", but ⌘↑ goes out one level, so only the crumb for the level just outside the one shown names it (`breadcrumbHelp`). (b) `isPlus` matched any socket named "+", so a wire dragged from a Missing node's "+" (a Missing node keeps the sockets its wires name) was diverted into the expose hint; it now requires Group Input or Group Output. The other two (levelTransforms never pruned, two accent roles one colour in a custom theme) are dropped, see Dropped items.

**Files:**

- Modify: `Sources/CreatorEditor/BreadcrumbBar.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Expose.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Levels.swift`
- Test: `Tests/CreatorEditorTests/BreadcrumbRenderTests.swift`
- Test: `Tests/CreatorEditorTests/ExposeSocketTests.swift`

**Interfaces:**
- Consumes: `EditorModel.breadcrumbs`, `isBoundary(_:)`.
- Produces: `EditorModel.breadcrumbHelp(_ crumb: Breadcrumb) -> String`; `isPlus` is true only for "+" on a Group Input or Group Output node.

- [ ] **Step 1: Write the failing tests**

Apply this patch (tests only):

```diff
diff --git a/Tests/CreatorEditorTests/BreadcrumbRenderTests.swift b/Tests/CreatorEditorTests/BreadcrumbRenderTests.swift
--- a/Tests/CreatorEditorTests/BreadcrumbRenderTests.swift
+++ b/Tests/CreatorEditorTests/BreadcrumbRenderTests.swift
@@ -28,4 +28,17 @@ struct BreadcrumbRenderTests {
         #expect(renderHeadless { GraphPanelHeader(model: editor) }.glyphs.count > oneDeep)
         #expect(editor.breadcrumbs.map(\.title) == ["Graph", "Group", "Group 2"])
     }
+
+    @Test func onlyTheCrumbJustOutsideTheLevelShownNamesTheKeyThatGoesThere() throws {
+        let grouped = try GroupedEditor()
+        let editor = grouped.editor
+        editor.enterGroup(grouped.group)
+        editor.selection = [grouped.rectangle.id]
+        editor.groupSelection()
+        editor.enterGroup(try #require(editor.selection.first))
+        let crumbs = editor.breadcrumbs
+        #expect(crumbs.map(editor.breadcrumbHelp) == ["Back to Graph", "Back to Group (⌘↑)", "Back to Group 2"])
+        editor.exitGroup()
+        #expect(editor.breadcrumbs.map(editor.breadcrumbHelp) == ["Back to Graph (⌘↑)", "Back to Group"])
+    }
 }
diff --git a/Tests/CreatorEditorTests/ExposeSocketTests.swift b/Tests/CreatorEditorTests/ExposeSocketTests.swift
--- a/Tests/CreatorEditorTests/ExposeSocketTests.swift
+++ b/Tests/CreatorEditorTests/ExposeSocketTests.swift
@@ -76,4 +76,27 @@ struct ExposeSocketTests {
         editor.drag(from, editor.screenPoint(of: output.id, "+", input: true))
         #expect(grouped.current?.outputs.map(\.name) == ["solid", "profile", "profile2"])
     }
+
+    /// Only Group Input's and Group Output's "+" is the expose socket; a node whose type is missing keeps whatever sockets
+    /// its wires name, one of them possibly called "+", and a wire dragged from that is refused as any wire from such a node.
+    @Test func aMissingNodesPlusSocketIsNotTheExposeSocket() {
+        let first = testNode(NumberTestNode.self, id: 1, at: Vector2(300, 0))
+        let second = testNode(NumberTestNode.self, id: 2, at: Vector2(300, 200))
+        var gone = Node(id: nodeID(3), typeID: "plugin.gone", name: "Gone")
+        gone.position = .zero
+        let editor = makeEditor([first, second, gone], [wire(gone, "+", first, "value")])
+        editor.transform = CanvasTransform()
+        editor.drag(editor.screenPoint(of: gone.id, "+", input: false), editor.screenPoint(of: second.id, "value", input: true))
+        #expect(editor.refusal?.message == "That node's type isn't available, so it can't be wired.")
+        #expect(editor.refusal?.node == second.id)
+        #expect(editor.graph.links == [wire(gone, "+", first, "value")])
+    }
+
+    @Test func plusIsOnlyGroupInputsOrOutputsSocket() throws {
+        let (grouped, editor, input, output) = try inside()
+        #expect(editor.isPlus(SocketRef(Endpoint(node: input.id, socket: "+"), isInput: false)))
+        #expect(editor.isPlus(SocketRef(Endpoint(node: output.id, socket: "+"), isInput: true)))
+        #expect(!editor.isPlus(SocketRef(Endpoint(node: grouped.rectangle.id, socket: "+"), isInput: true)))
+        #expect(!editor.isPlus(SocketRef(Endpoint(node: nodeID(99), socket: "+"), isInput: true)))
+    }
 }
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter 'ExposeSocketTests|BreadcrumbRenderTests'`
Expected: FAIL to compile: `value of type 'EditorModel' has no member 'breadcrumbHelp'`; with that stubbed, `aMissingNodesPlusSocketIsNotTheExposeSocket` and `plusIsOnlyGroupInputsOrOutputsSocket` fail.

- [ ] **Step 3: Implement**

Apply this patch (sources):

```diff
diff --git a/Sources/CreatorEditor/BreadcrumbBar.swift b/Sources/CreatorEditor/BreadcrumbBar.swift
--- a/Sources/CreatorEditor/BreadcrumbBar.swift
+++ b/Sources/CreatorEditor/BreadcrumbBar.swift
@@ -18,7 +18,7 @@ struct BreadcrumbBar: Component {
                 } else {
                     Button(crumb.title) { model.goToLevel(crumb.depth) }
                         .buttonStyle(.plain)
-                        .help("Back to \(crumb.title) (⌘↑)")
+                        .help(model.breadcrumbHelp(crumb))
                         .foregroundStyle(palette.secondaryText.color)
                     Text("›").font(.headline).foregroundStyle(palette.secondaryText.color)
                 }
diff --git a/Sources/CreatorEditor/EditorModel+Expose.swift b/Sources/CreatorEditor/EditorModel+Expose.swift
--- a/Sources/CreatorEditor/EditorModel+Expose.swift
+++ b/Sources/CreatorEditor/EditorModel+Expose.swift
@@ -5,9 +5,10 @@ import CreatorKernel
 extension EditorModel {
     static let exposeHint = "Drop a wire from an output on Group Output's +, or drag from Group Input's + onto an input."
 
-    /// Whether `socket` is the "+" of Group Input or Group Output.
+    /// Whether `socket` is the "+" of Group Input or Group Output. A node whose type is missing keeps the sockets its wires
+    /// name, so one may be called "+" (older files could); that is an ordinary socket.
     func isPlus(_ socket: SocketRef) -> Bool {
-        socket.endpoint.socket == GroupNaming.plusSocket
+        socket.endpoint.socket == GroupNaming.plusSocket && isBoundary(socket.endpoint.node)
     }
 
     /// A wire dragged between two sockets, one of them a "+" (either end can be the one dragged from). An output
diff --git a/Sources/CreatorEditor/EditorModel+Levels.swift b/Sources/CreatorEditor/EditorModel+Levels.swift
--- a/Sources/CreatorEditor/EditorModel+Levels.swift
+++ b/Sources/CreatorEditor/EditorModel+Levels.swift
@@ -62,6 +62,12 @@ extension EditorModel {
         return crumbs
     }
 
+    /// A breadcrumb's tooltip. ⌘↑ goes out one level, so only the crumb for the level just outside the one shown names it.
+    public func breadcrumbHelp(_ crumb: Breadcrumb) -> String {
+        let help = "Back to \(crumb.title)"
+        return crumb.depth == breadcrumbs.count - 2 ? help + " (⌘↑)" : help
+    }
+
     /// Enters group node `id` of the graph shown (a double click, ⌘↓, "Edit Group"). The selection clears, and the
     /// level shows with the pan and zoom it had last time, or framing everything the first time. Returns false for
     /// anything that isn't a group node whose definition exists, while a drag is under way, or while the level is
```

- [ ] **Step 4: Run them and see them pass**

Run: `swift test --filter 'ExposeSocketTests|BreadcrumbRenderTests'`
Expected: all pass.

- [ ] **Step 5: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2160 tests (master + 18)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor/BreadcrumbBar.swift Sources/CreatorEditor/EditorModel+Expose.swift Sources/CreatorEditor/EditorModel+Levels.swift Tests/CreatorEditorTests/BreadcrumbRenderTests.swift Tests/CreatorEditorTests/ExposeSocketTests.swift
git commit -m "followups-editor task 8: Breadcrumb tooltips and a Missing node's + socket (ED-7)"
```

### Task 9: Make Unique counts on from a numbered name (ED-8)

**Why.** `GroupNaming.uniqueName` appended " 2" to the whole base, so Make Unique of "Rib 2" gave "Rib 2 2". The groups spec says "Name 2" and means the next free number, so a base that already ends in a space and ASCII digits counts on from its own number ("Rib 2" gives "Rib 3"; "Rib" still gives "Rib 2"). Digits `Int` cannot hold, non-ASCII digits and signs are not counted on (Review Focus 3). Recorded as a user decision.

`uniqueName` has three callers; only Make Unique changes. ⌘G's base ("Group", `GroupBuilder`) has no number. The clipboard merge (`GroupMerge`) names a colliding pasted definition `"<name> (imported)"`, which ends in `)` and so is never counted on: a pasted "Rib 2" that collides stays "Rib 2 (imported)", and the new `aNumberedNameTheDocumentUsesIsImportedNotCountedOn` pins that.

**Files:**

- Modify: `Sources/CreatorGraph/Groups/GroupNaming.swift`
- Test: `Tests/CreatorGraphTests/Groups/GroupCommandTests.swift`
- Test: `Tests/CreatorGraphTests/Groups/GroupMergeTests.swift`
- Test: `Tests/CreatorGraphTests/Groups/UngroupTests.swift`

**Interfaces:**
- Consumes: `Doubler(name:)` fixture, `table(_:)`.
- Produces: `GroupNaming.uniqueName(_:taken:)` and `uniqueDefinitionName(_:among:)` as described; `"imported"` names and ⌘G's "Group" are unaffected.

- [ ] **Step 1: Write the failing tests**

Apply this patch (tests only):

```diff
diff --git a/Tests/CreatorGraphTests/Groups/GroupCommandTests.swift b/Tests/CreatorGraphTests/Groups/GroupCommandTests.swift
--- a/Tests/CreatorGraphTests/Groups/GroupCommandTests.swift
+++ b/Tests/CreatorGraphTests/Groups/GroupCommandTests.swift
@@ -164,6 +164,26 @@ struct GroupCommandTests {
         #expect(GroupNaming.uniqueDefinitionName("Rib", among: table([doubler.definition])) == "Rib")
     }
 
+    /// A copy of "Rib 2" is "Rib 3" (the groups spec's "Name 2"), not "Rib 2 2".
+    @Test func aNumberedNameCountsOnFromItsOwnNumber() {
+        func named(_ names: [String]) -> [GroupID: GroupDefinition] { table(names.map { Doubler(name: $0).definition }) }
+        #expect(GroupNaming.uniqueDefinitionName("Rib 2", among: named(["Rib", "Rib 2"])) == "Rib 3")
+        #expect(GroupNaming.uniqueDefinitionName("Rib 2", among: named(["Rib 2", "Rib 3"])) == "Rib 4")
+        #expect(GroupNaming.uniqueDefinitionName("Rib 2020", among: named(["Rib 2020"])) == "Rib 2021")
+        #expect(GroupNaming.uniqueDefinitionName("Rib", among: named(["Rib"])) == "Rib 2", "no number: from 2 as before")
+        #expect(GroupNaming.uniqueDefinitionName("Rib 0", among: named(["Rib 0"])) == "Rib 2")
+        #expect(GroupNaming.uniqueDefinitionName("Rib 2", among: named(["Other"])) == "Rib 2", "free names stay as they are")
+        #expect(GroupNaming.uniqueDefinitionName("2", among: named(["2"])) == "2 2", "a bare number has no stem to count on")
+        #expect(GroupNaming.uniqueDefinitionName("Rib 2x", among: named(["Rib 2x"])) == "Rib 2x 2")
+        // Numbers `Int` can't hold or that aren't ASCII digits are not counted on.
+        #expect(GroupNaming.uniqueDefinitionName("Rib 99999999999999999999", among: named(["Rib 99999999999999999999"]))
+                == "Rib 99999999999999999999 2")
+        #expect(GroupNaming.uniqueDefinitionName("Rib 9223372036854775807", among: named(["Rib 9223372036854775807"]))
+                == "Rib 9223372036854775807 2")
+        #expect(GroupNaming.uniqueDefinitionName("Rib ٣", among: named(["Rib ٣"])) == "Rib ٣ 2")
+        #expect(GroupNaming.uniqueDefinitionName("Rib +3", among: named(["Rib +3"])) == "Rib +3 2")
+    }
+
     @Test func groupingIsRefusedPlainly() {
         let document = document()
         let doubler = Doubler()
diff --git a/Tests/CreatorGraphTests/Groups/GroupMergeTests.swift b/Tests/CreatorGraphTests/Groups/GroupMergeTests.swift
--- a/Tests/CreatorGraphTests/Groups/GroupMergeTests.swift
+++ b/Tests/CreatorGraphTests/Groups/GroupMergeTests.swift
@@ -87,6 +87,14 @@ struct GroupMergeTests {
         #expect(plan.targets == [other.id: other.id])
     }
 
+    /// Make Unique counts on from a number ("Rib 2" gives "Rib 3"); a paste that meets a taken name does not: it adds
+    /// "(imported)", so the number-aware naming never reaches it.
+    @Test func aNumberedNameTheDocumentUsesIsImportedNotCountedOn() throws {
+        let other = Doubler(name: "Rib 2")
+        let plan = GroupMerge.plan(importing: table([other.definition]), into: content([Doubler(name: "Rib 2").definition]))
+        #expect(try #require(plan.additions.first).name == "Rib 2 (imported)")
+    }
+
     @Test func theSameStaleClipboardPastedTwiceAddsOneCopy() throws {
         var edited = doubler.definition
         edited.graph.nodes[doubler.add.id]?.inputValues["b"] = .number(10)
diff --git a/Tests/CreatorGraphTests/Groups/UngroupTests.swift b/Tests/CreatorGraphTests/Groups/UngroupTests.swift
--- a/Tests/CreatorGraphTests/Groups/UngroupTests.swift
+++ b/Tests/CreatorGraphTests/Groups/UngroupTests.swift
@@ -110,6 +110,17 @@ struct UngroupTests {
         #expect(document.content == before)
     }
 
+    @Test func makeUniqueOfANumberedGroupCountsOn() throws {
+        let numbered = Doubler(name: "Doubler 2")
+        let node = instance(of: numbered.definition, output: true)
+        let content = GraphContent(graph: graph([node]), definitions: table([numbered.definition]))
+        let edit = try GroupCommands.makeUnique(node.id, in: .root, of: content, registry: testRegistry)
+        var applied = content
+        try applied.apply(edit.command, registry: testRegistry)
+        #expect(applied.definitions.values.map(\.name).sorted() == ["Doubler 2", "Doubler 3"])
+        #expect(applied.graph.nodes[node.id]?.name == "Doubler 3")
+    }
+
     /// "Counted": a box whose end cap a counter inside picks; it puts out the box's solid and the count. One group
     /// node of it, and a counter outside picking that node's box's end cap.
     struct CountedScene {
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter 'GroupCommandTests|UngroupTests'`
Expected: FAIL: `aNumberedNameCountsOnFromItsOwnNumber`, `makeUniqueOfANumberedGroupCountsOn`. `aNumberedNameTheDocumentUsesIsImportedNotCountedOn` is a pin.

- [ ] **Step 3: Implement**

Apply this patch (sources):

```diff
diff --git a/Sources/CreatorGraph/Groups/GroupNaming.swift b/Sources/CreatorGraph/Groups/GroupNaming.swift
--- a/Sources/CreatorGraph/Groups/GroupNaming.swift
+++ b/Sources/CreatorGraph/Groups/GroupNaming.swift
@@ -2,17 +2,26 @@ import Foundation
 
 /// Names for definitions and their sockets (groups spec §4, §5).
 public enum GroupNaming {
-    /// `base` if no definition has that name, else "base 2", "base 3", …
+    /// `base` if no definition has that name, else "base 2", "base 3", …; a `base` that already ends in a number counts on
+    /// from it, so a copy of "Rib 2" is "Rib 3", not "Rib 2 2".
     public static func uniqueDefinitionName(_ base: String, among definitions: [GroupID: GroupDefinition]) -> String {
         uniqueName(base, taken: Set(definitions.values.map(\.name)))
     }
 
-    /// `base` if it isn't in `taken`, else "base 2", "base 3", …
+    /// `base` if it isn't in `taken`, else "base 2", "base 3", … (see `uniqueDefinitionName`).
     static func uniqueName(_ base: String, taken: Set<String>) -> String {
         guard taken.contains(base) else { return base }
+        var stem = base
         var number = 2
-        while taken.contains("\(base) \(number)") { number += 1 }
-        return "\(base) \(number)"
+        if let space = base.lastIndex(of: " "), space > base.startIndex {
+            let digits = base[base.index(after: space)...]
+            if !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let own = Int(digits), own < Int.max {
+                stem = String(base[..<space])
+                number = max(own + 1, 2)
+            }
+        }
+        while taken.contains("\(stem) \(number)") { number += 1 }
+        return "\(stem) \(number)"
     }
 
     /// `base` if no socket in `existing` has it and it isn't a setting's name, else "base2", "base3", …
```

- [ ] **Step 4: Run them and see them pass**

Run: `swift test --filter 'GroupCommandTests|UngroupTests'`
Expected: all pass.

- [ ] **Step 5: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2163 tests (master + 21)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorGraph/Groups/GroupNaming.swift Tests/CreatorGraphTests/Groups/GroupCommandTests.swift Tests/CreatorGraphTests/Groups/GroupMergeTests.swift Tests/CreatorGraphTests/Groups/UngroupTests.swift
git commit -m "followups-editor task 9: Make Unique counts on from a numbered name (ED-8)"
```

### Task 10: Esc leaves the selection alone while the panel is hidden (ED-10a)

**Why.** `cancel()` cleared a leftover selection and claimed Esc with the panel hidden, unlike ⌘A, the arrows and F, which are gated on `isPanelVisible`. The palette and drag branches stay as they were. ED-10 (b), (c) and (d) are dropped (Dropped items).

**Files:**

- Modify: `Sources/CreatorEditor/EditorModel+Commands.swift`
- Test: `Tests/CreatorEditorTests/SelectionKeyTests.swift`

**Interfaces:**
- Consumes: `EditorModel.isPanelVisible`, `setDock(_:)`.
- Produces: `perform(.cancel)` returns false and keeps the selection while the panel is hidden.

- [ ] **Step 1: Write the failing tests**

Apply this patch (tests only):

```diff
diff --git a/Tests/CreatorEditorTests/SelectionKeyTests.swift b/Tests/CreatorEditorTests/SelectionKeyTests.swift
--- a/Tests/CreatorEditorTests/SelectionKeyTests.swift
+++ b/Tests/CreatorEditorTests/SelectionKeyTests.swift
@@ -37,6 +37,17 @@ struct SelectionKeyTests {
         #expect(editor.selection.isEmpty)
     }
 
+    /// With the panel hidden a leftover selection is out of sight, and Esc is not the editor's to claim or to clear it with.
+    @Test func escapeDoesNothingWhileThePanelIsHidden() {
+        let editor = makeEditor([a, b])
+        editor.selection = [a.id]
+        editor.setDock(.hidden)
+        #expect(!editor.perform(.cancel), "the key goes on")
+        #expect(editor.selection == [a.id])
+        editor.setDock(.bottom)
+        #expect(editor.perform(.cancel) && editor.selection.isEmpty)
+    }
+
     @Test func escapeClosesThePaletteBeforeClearingTheSelection() {
         let editor = makeEditor([a])
         editor.selection = [a.id]
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter 'SelectionKeyTests'`
Expected: FAIL (3 issues): `escapeDoesNothingWhileThePanelIsHidden`.

- [ ] **Step 3: Implement**

Apply this patch (sources):

```diff
diff --git a/Sources/CreatorEditor/EditorModel+Commands.swift b/Sources/CreatorEditor/EditorModel+Commands.swift
--- a/Sources/CreatorEditor/EditorModel+Commands.swift
+++ b/Sources/CreatorEditor/EditorModel+Commands.swift
@@ -75,15 +75,15 @@ extension EditorModel {
     }
 
     /// Escape, in order (spec 2026-10-09 §3): closes the palette; else ends the drag under way
-    /// (`cancelInteraction()`); else clears the selection. With none of these to do it returns false, and the key
-    /// goes on. A pick's, a sketch's and the theme editor's Esc are button shortcuts, which MetalUI runs first.
+    /// (`cancelInteraction()`); else clears the selection, while the panel shows the canvas (as with the other selection
+    /// keys). With none of these to do it returns false, and the key goes on. A pick's, a sketch's and the theme editor's Esc are button shortcuts, which MetalUI runs first.
     private func cancel() -> Bool {
         if palette != nil {
             closePalette()
             return true
         }
         if cancelInteraction() { return true }
-        guard !canvasSelection.isEmpty else { return false }
+        guard isPanelVisible, !canvasSelection.isEmpty else { return false }
         clearSelection()
         return true
     }
```

- [ ] **Step 4: Run them and see them pass**

Run: `swift test --filter 'SelectionKeyTests'`
Expected: all pass.

- [ ] **Step 5: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2164 tests (master + 22)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor/EditorModel+Commands.swift Tests/CreatorEditorTests/SelectionKeyTests.swift
git commit -m "followups-editor task 10: Esc leaves the selection alone while the panel is hidden (ED-10a)"
```

### Task 11: Cleanups and required undo names (ED-9, ED-11, ED-12, ED-18)

**Why.** Four cleanups that change no behaviour a person can reach, so there is no failing test; the suite must stay green. ED-9: `update(to:from:)` no longer does arithmetic for `.panning` (only `middleDragged` creates it and a primary press ends it first), so it is a commented no-op. ED-11: `delete(named:)` returns whether it deleted, and `cutSelection` replaces the clipboard only after a delete went through (today the copy and the delete cover the same items, so this is hardening). ED-12: `CanvasLayers` evaluates `commentGhosts(model)` once. ED-18: `EditorModel.edit(_:coalescingKey:name:)` and `SketchCommit.init` take `name` with no default, so a forgotten name is a compile error; the two tests that pinned the old "Edit Sketch" default are removed and the three test call sites without a name get one. Review Focus 4 (`cutUndoPasteGivesTheNodeAndACopy`) pins the clipboard order. The dead constant `SketchStepName.editSketch` is left for the kernel track.

**Files:**

- Modify: `Sources/CreatorEditor/CanvasLayers.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Pointer.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Editing.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Levels.swift`
- Modify: `Sources/CreatorSketchEditor/SketchCommit.swift`
- Test: `Tests/CreatorAppTests/AppUndoNameTests.swift`
- Test: `Tests/CreatorAppTests/GroupViewportTests.swift`
- Test: `Tests/CreatorEditorTests/EditingTests.swift`
- Test: `Tests/CreatorEditorTests/EditorLevelReviewTests.swift`
- Test: `Tests/CreatorSketchEditorTests/SketchStepNameTests.swift`

**Interfaces:**
- Consumes: `UndoName.changeInput(_:)`, `UndoName.addNode(_:)`.
- Produces: `EditorModel.edit(_:coalescingKey:name:)` with `name: String` required; `SketchCommit.init(sketch:description:name:projections:)` with `name: String` required.

- [ ] **Step 1: Apply the cleanup patch**

No new failing test: these change nothing a person can reach. Apply both the source and the test call-site edits:

```diff
diff --git a/Sources/CreatorEditor/CanvasLayers.swift b/Sources/CreatorEditor/CanvasLayers.swift
--- a/Sources/CreatorEditor/CanvasLayers.swift
+++ b/Sources/CreatorEditor/CanvasLayers.swift
@@ -17,6 +17,7 @@ struct CanvasLayers: Component {
         let flow = model.flow
         let palette = Palette(themes)
         let selectedComments = model.canvasSelection.comments
+        let commentGhosts = Self.commentGhosts(model)
         return ZStack(alignment: .topLeading) {
             ForEach(model.drawnFrames, id: \.id.rawValue) { box in
                 CommentFrameView(box: box, rect: model.frame(of: box), isSelected: selectedComments.contains(box.id))
@@ -42,10 +43,10 @@ struct CanvasLayers: Component {
                 NodeView(shape: shape, rows: [], origin: flow.display(node.position), flow: flow,
                          isSelected: true, state: nil, shakes: 0, isGhost: true)
             }
-            ForEach(Self.commentGhosts(model).frames, id: \.id.rawValue) { box in
+            ForEach(commentGhosts.frames, id: \.id.rawValue) { box in
                 CommentFrameView(box: box, rect: model.frame(of: box), isSelected: true, isGhost: true)
             }
-            ForEach(Self.commentGhosts(model).notes, id: \.id.rawValue) { note in
+            ForEach(commentGhosts.notes, id: \.id.rawValue) { note in
                 StickyView(note: note, rect: model.frame(of: note), isSelected: true, isGhost: true)
             }
             if case .connecting(let drag)? = model.interaction, let anchor = model.anchor(of: drag.from) {
diff --git a/Sources/CreatorEditor/EditorModel+Editing.swift b/Sources/CreatorEditor/EditorModel+Editing.swift
--- a/Sources/CreatorEditor/EditorModel+Editing.swift
+++ b/Sources/CreatorEditor/EditorModel+Editing.swift
@@ -25,8 +25,10 @@ extension EditorModel {
         delete(named: UndoName.delete)
     }
 
-    /// Deletes the selection as one undo step called `name` ("Delete", or "Cut" for ⌘X).
-    private func delete(named name: String) {
+    /// Deletes the selection as one undo step called `name` ("Delete", or "Cut" for ⌘X). Returns whether anything was
+    /// deleted.
+    @discardableResult
+    private func delete(named name: String) -> Bool {
         let present = canvasSelection.nodes.filter { graph.nodes[$0] != nil }
         let commands = present.filter { !isBoundary($0) }.sorted().map { GraphCommand.removeNode($0) }
             + canvasSelection.comments.sorted().compactMap { id -> GraphCommand? in
@@ -35,22 +37,25 @@ extension EditorModel {
             }
         guard !commands.isEmpty else {
             if !present.isEmpty { refuse("A group's Group Input and Group Output can't be deleted.", node: nil) }
-            return
+            return false
         }
         do {
             try edit(.batch(commands), name: name)
             canvasSelection = CanvasSelection()
+            return true
         } catch {
             refuse(error.message, node: nil)
+            return false
         }
     }
 
-    /// ⌘X: copies the selection, then deletes it, the delete being one undo step.
+    /// ⌘X: copies the selection, then deletes it, the delete being one undo step. The clipboard is replaced only once the
+    /// delete has gone through.
     public func cutSelection() {
         guard !canvasSelection.isEmpty else { return }
         let copied = clipboard(of: canvasSelection)
-        if !copied.isEmpty { setClipboard(copied) }
-        delete(named: UndoName.cut)
+        guard delete(named: UndoName.cut), !copied.isEmpty else { return }
+        setClipboard(copied)
     }
 
     /// ⌘C: copies the selected items (the nodes, the wires between them, and the comments).
diff --git a/Sources/CreatorEditor/EditorModel+Levels.swift b/Sources/CreatorEditor/EditorModel+Levels.swift
--- a/Sources/CreatorEditor/EditorModel+Levels.swift
+++ b/Sources/CreatorEditor/EditorModel+Levels.swift
@@ -24,9 +24,9 @@ extension EditorModel {
     /// The top-level graph, whichever level is shown: the document's parameters live here.
     public var rootGraph: Graph { document.graph }
 
-    /// Applies `command` to the graph the panel shows, as one undo step named `name` (`DocumentModel.perform(_:at:)`;
-    /// without one the step is named from the command). An edit that goes through clears the refusal caption.
-    public func edit(_ command: GraphCommand, coalescingKey: String? = nil, name: String? = nil) throws(GraphError) {
+    /// Applies `command` to the graph the panel shows, as one undo step named `name` (`UndoName`; required, so no edit can
+    /// reach the Edit menu as the fallback "Edit"). An edit that goes through clears the refusal caption.
+    public func edit(_ command: GraphCommand, coalescingKey: String? = nil, name: String) throws(GraphError) {
         try document.perform(command, at: graphPath, coalescingKey: coalescingKey, name: name)
         clearRefusal()
     }
diff --git a/Sources/CreatorEditor/EditorModel+Pointer.swift b/Sources/CreatorEditor/EditorModel+Pointer.swift
--- a/Sources/CreatorEditor/EditorModel+Pointer.swift
+++ b/Sources/CreatorEditor/EditorModel+Pointer.swift
@@ -129,8 +129,8 @@ extension EditorModel {
         // Screen delta → stored (left-to-right) canvas delta: undo the zoom, then the dock transpose.
         let storedDelta = flow.stored((location - pressPoint) * (1 / transform.zoom))
         switch interaction {
-        case .panning(let startOffset):
-            transform = CanvasTransform(offset: startOffset + (location - pressPoint), zoom: transform.zoom)
+        case .panning:
+            break  // The middle button's (`middleDragged`); a primary press ends a pan first (`pointerPressed`).
         case .moving(let start, let key):
             try? edit(.batch(moveCommands(from: start, by: storedDelta)), coalescingKey: key, name: UndoName.move)
         case .resizing(let id, let start, let key):
diff --git a/Sources/CreatorSketchEditor/SketchCommit.swift b/Sources/CreatorSketchEditor/SketchCommit.swift
--- a/Sources/CreatorSketchEditor/SketchCommit.swift
+++ b/Sources/CreatorSketchEditor/SketchCommit.swift
@@ -11,8 +11,8 @@ public struct SketchCommit: Hashable, Sendable {
     public var name: String
     public var projections: [ProjectionWrite]
 
-    public init(sketch: Sketch, description: String, name: String = SketchStepName.editSketch,
-                projections: [ProjectionWrite] = []) {
+    /// `name` is required, so no edit can reach the Edit menu without one.
+    public init(sketch: Sketch, description: String, name: String, projections: [ProjectionWrite] = []) {
         self.sketch = sketch
         self.description = description
         self.name = name
diff --git a/Tests/CreatorAppTests/AppUndoNameTests.swift b/Tests/CreatorAppTests/AppUndoNameTests.swift
--- a/Tests/CreatorAppTests/AppUndoNameTests.swift
+++ b/Tests/CreatorAppTests/AppUndoNameTests.swift
@@ -95,8 +95,6 @@ struct AppUndoNameTests {
         #expect(app.document.undoName == "Add Constraint")
         app.storeSketch(SketchCommit(sketch: editor.sketch, description: "Vertical", name: "  "))
         #expect(app.document.undoName == "Edit Sketch", "a commit with a blank name")
-        app.storeSketch(SketchCommit(sketch: editor.sketch, description: "Vertical"))
-        #expect(app.document.undoName == "Edit Sketch", "a commit made without a name")
 
         editor.choose(.line)
         editor.click(at: Vector2(0, 60), tolerance: 1, modifiers: [])
diff --git a/Tests/CreatorAppTests/GroupViewportTests.swift b/Tests/CreatorAppTests/GroupViewportTests.swift
--- a/Tests/CreatorAppTests/GroupViewportTests.swift
+++ b/Tests/CreatorAppTests/GroupViewportTests.swift
@@ -63,7 +63,7 @@ struct GroupViewportTests {
         app.previewMode = .selectedNode
         app.editor.transform = CanvasTransform()
         let lonely = try #require(app.editor.registry.makeNode(ExtrudeNode.typeID, at: Vector2(200, 300)) as Node?)
-        try app.editor.edit(.addNode(lonely))
+        try app.editor.edit(.addNode(lonely), name: UndoName.addNode(lonely))
         app.editor.connect(Link(from: Endpoint(node: scene.rectangle.id, socket: "profile"),
                                 to: Endpoint(node: lonely.id, socket: "profile")))
         app.editor.selection = [lonely.id]
diff --git a/Tests/CreatorEditorTests/EditingTests.swift b/Tests/CreatorEditorTests/EditingTests.swift
--- a/Tests/CreatorEditorTests/EditingTests.swift
+++ b/Tests/CreatorEditorTests/EditingTests.swift
@@ -99,6 +99,21 @@ struct EditingTests {
         #expect(copy?.position == Vector2(24, 24))
     }
 
+    /// Cut takes the clipboard only once the delete went through, and Undo of the cut leaves it: the cut nodes come back and
+    /// a paste still puts a copy beside them.
+    @Test func cutUndoPasteGivesTheNodeAndACopy() {
+        let number = testNode(NumberTestNode.self, id: 9, at: .zero, values: ["value": .number(42)])
+        let editor = makeEditor([number])
+        editor.selection = [number.id]
+        editor.cutSelection()
+        #expect(editor.graph.nodes.isEmpty && editor.clipboard?.nodes.map(\.id) == [number.id])
+        editor.document.undo()
+        #expect(editor.graph.nodes.keys.sorted() == [number.id])
+        editor.paste()
+        #expect(editor.graph.nodes.count == 2)
+        #expect(editor.selection.first.flatMap { editor.graph.nodes[$0] }?.inputValues["value"] == .number(42))
+    }
+
     @Test func copiesKeepTheirInputValues() {
         let number = testNode(NumberTestNode.self, id: 9, at: .zero, values: ["value": .number(42)])
         let editor = makeEditor([number])
diff --git a/Tests/CreatorEditorTests/EditorLevelReviewTests.swift b/Tests/CreatorEditorTests/EditorLevelReviewTests.swift
--- a/Tests/CreatorEditorTests/EditorLevelReviewTests.swift
+++ b/Tests/CreatorEditorTests/EditorLevelReviewTests.swift
@@ -20,8 +20,8 @@ struct EditorLevelReviewTests {
         editor.selection = [grouped.group]
         editor.perform(.duplicate)
         let second = try #require(editor.selection.first)
-        try editor.edit(.setInput(second, "width", .number(50)))
-        try editor.edit(.setInput(grouped.number.id, "value", .number(7)))
+        try editor.edit(.setInput(second, "width", .number(50)), name: UndoName.changeInput("Width"))
+        try editor.edit(.setInput(grouped.number.id, "value", .number(7)), name: UndoName.changeInput("Value"))
         await editor.document.waitForEvaluation()
 
         editor.enterGroup(grouped.group)
diff --git a/Tests/CreatorSketchEditorTests/SketchStepNameTests.swift b/Tests/CreatorSketchEditorTests/SketchStepNameTests.swift
--- a/Tests/CreatorSketchEditorTests/SketchStepNameTests.swift
+++ b/Tests/CreatorSketchEditorTests/SketchStepNameTests.swift
@@ -139,8 +139,4 @@ struct SketchStepNameTests {
         model.project(.edge(solid: 0, EdgeID(1)))
         #expect(host.commits.map(\.name) == ["Project"])
     }
-
-    @Test func aCommitMadeWithoutANameIsCalledEditSketch() {
-        #expect(SketchCommit(sketch: Sketch(), description: "Vertical").name == "Edit Sketch")
-    }
 }
```

- [ ] **Step 2: Build and run the touched suites**

Run: `swift build --build-tests` then `swift test --filter 'EditingTests|EditorLevelReviewTests|AppUndoNameTests|GroupViewportTests|SketchStepNameTests'`
Expected: build with no new warnings; all pass.

- [ ] **Step 3: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2164 tests (master + 22)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 4: Commit**

```bash
git add Sources/CreatorEditor/CanvasLayers.swift Sources/CreatorEditor/EditorModel+Editing.swift Sources/CreatorEditor/EditorModel+Levels.swift Sources/CreatorEditor/EditorModel+Pointer.swift Sources/CreatorSketchEditor/SketchCommit.swift Tests/CreatorAppTests/AppUndoNameTests.swift Tests/CreatorAppTests/GroupViewportTests.swift Tests/CreatorEditorTests/EditingTests.swift Tests/CreatorEditorTests/EditorLevelReviewTests.swift Tests/CreatorSketchEditorTests/SketchStepNameTests.swift
git commit -m "followups-editor task 11: Cleanups and required undo names (ED-9, ED-11, ED-12, ED-18)"
```

### Task 12: Prune innerResults with results (ED-13)

**Why.** `DocumentModel.didChange` filtered `results` and `lastGoodOutputs` by the nodes that still exist but not `innerResults`, so entries for deleted inner nodes (and for everything inside a deleted group node) lingered until the next report replaced the dictionary. `GraphContent.hasNode(atInstance:)` says whether an instance path (the group nodes from the top level down, then the inner node) still names a node, and `didChange` filters by it. Review Focus 5 checks Undo brings the state back.

**Files:**

- Modify: `Sources/CreatorGraph/Groups/GraphContent+Levels.swift`
- Modify: `Sources/CreatorGraph/DocumentModel.swift`
- Test: `Tests/CreatorGraphTests/Groups/InspectedLevelTests.swift`

**Interfaces:**
- Consumes: `GraphContent.path(entering:)`, `graph(at:)`.
- Produces: `public func hasNode(atInstance instance: [NodeID]) -> Bool` on `GraphContent`.

- [ ] **Step 1: Write the failing tests**

Apply this patch (tests only):

```diff
diff --git a/Tests/CreatorGraphTests/Groups/InspectedLevelTests.swift b/Tests/CreatorGraphTests/Groups/InspectedLevelTests.swift
--- a/Tests/CreatorGraphTests/Groups/InspectedLevelTests.swift
+++ b/Tests/CreatorGraphTests/Groups/InspectedLevelTests.swift
@@ -104,4 +104,31 @@ struct InspectedLevelTests {
         await document.waitForEvaluation()
         #expect(document.innerResults[[group.id, extra.id]] == nil)
     }
+
+    /// `innerResults` follows the document as `results` does: an entry for a node that is gone doesn't wait for the next
+    /// evaluation to leave.
+    @MainActor
+    @Test func innerResultsOfNodesThatAreGoneLeaveAtOnce() async throws {
+        let extra = makeNode(ConstantNode.self, ["value": .number(7)])
+        let (definition, add) = rib(extra: extra)
+        let group = instance(of: definition, ["value": .number(3)], output: true)
+        let document = DocumentModel(file: GraphFile(graph: graph([group]), definitions: table([definition])),
+                                     registry: testRegistry, kernel: FakeKernel())
+        document.inspectedLevel = [group.id]
+        await document.waitForEvaluation()
+        #expect(document.innerResults[[group.id, extra.id]] != nil && document.innerResults[[group.id, add.id]] != nil)
+
+        try document.perform(GraphCommand.removeNode(extra.id).at(.definition(definition.id)))
+        #expect(document.innerResults[[group.id, extra.id]] == nil, "the deleted inner node, before the evaluation reports")
+        #expect(document.innerResults[[group.id, add.id]] != nil, "the others stay until it does")
+        await document.waitForEvaluation()
+        #expect(document.innerResults[[group.id, add.id]] != nil)
+        document.undo()
+        await document.waitForEvaluation()
+        #expect(document.innerResults[[group.id, extra.id]]?.outputs?["value"]?.numbers == [7], "Undo brings its state back")
+
+        try document.perform(.removeNode(group.id))
+        #expect(document.innerResults.isEmpty, "a deleted group node takes everything inside it")
+        await document.waitForEvaluation()
+    }
 }
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter 'InspectedLevelTests'`
Expected: FAIL (2 issues): `innerResultsOfNodesThatAreGoneLeaveAtOnce`.

- [ ] **Step 3: Implement**

Apply this patch (sources):

```diff
diff --git a/Sources/CreatorGraph/DocumentModel.swift b/Sources/CreatorGraph/DocumentModel.swift
--- a/Sources/CreatorGraph/DocumentModel.swift
+++ b/Sources/CreatorGraph/DocumentModel.swift
@@ -159,6 +159,8 @@ public final class DocumentModel {
         let existing = Set(graph.nodes.keys)
         results = results.filter { existing.contains($0.key) }
         lastGoodOutputs = lastGoodOutputs.filter { existing.contains($0.key) }
+        let content = content
+        innerResults = innerResults.filter { content.hasNode(atInstance: $0.key) }
         for id in stale where results[id] != nil {
             results[id]?.state = .evaluating
         }
diff --git a/Sources/CreatorGraph/Groups/GraphContent+Levels.swift b/Sources/CreatorGraph/Groups/GraphContent+Levels.swift
--- a/Sources/CreatorGraph/Groups/GraphContent+Levels.swift
+++ b/Sources/CreatorGraph/Groups/GraphContent+Levels.swift
@@ -25,6 +25,13 @@ extension GraphContent {
         return Array(levels.prefix(count))
     }
 
+    /// Whether `instance`, the group nodes from the top level down and then an inner node (the key of
+    /// `DocumentModel.innerResults`), names a node that exists.
+    public func hasNode(atInstance instance: [NodeID]) -> Bool {
+        guard let node = instance.last, let path = path(entering: Array(instance.dropLast())) else { return false }
+        return graph(at: path)?.nodes[node] != nil
+    }
+
     /// `value`, if it is a remembered pick, as the graph at `levels` names faces: the tags it holds name nodes by the
     /// identities they're made under (`NodeID.scoped` of the instance path), and a pick stored in a definition names
     /// them as if the definition were the top level (`GroupScopes.identity`), so every instance reads it as its own
```

- [ ] **Step 4: Run them and see them pass**

Run: `swift test --filter 'InspectedLevelTests'`
Expected: all pass.

- [ ] **Step 5: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2165 tests (master + 23)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorGraph/DocumentModel.swift Sources/CreatorGraph/Groups/GraphContent+Levels.swift Tests/CreatorGraphTests/Groups/InspectedLevelTests.swift
git commit -m "followups-editor task 12: Prune innerResults with results (ED-13)"
```

### Task 13: Undo and Redo replay without the new-definition and interface rules (GK-13)

**Why.** `DocumentModel.replay` runs `content.apply`, whose `.addDefinition` runs `checkNew` and `.setInterface` runs `checkInterface`. A file that already breaks those rules (two definitions with one name, which a hand edit or an older file can have) could Ungroup one of them but then not Undo it: the add-back is refused, `assertionFailure` fires (a debug build traps) and the history is out of step. `apply(_:registry:replaying:)` skips those two checks and only `replay` passes true. The wired-socket check after the command still runs.

**Files:**

- Modify: `Sources/CreatorGraph/Groups/GraphContent+Apply.swift`
- Modify: `Sources/CreatorGraph/DocumentModel.swift`
- Test: `Tests/CreatorGraphTests/Groups/GraphContentTests.swift`

**Interfaces:**
- Consumes: `Doubler(name:)`, `GroupCommands.ungroup`.
- Produces: `GraphContent.apply(_:registry:replaying: Bool = false)`.

- [ ] **Step 1: Write the failing tests**

Apply this patch (tests only):

```diff
diff --git a/Tests/CreatorGraphTests/Groups/GraphContentTests.swift b/Tests/CreatorGraphTests/Groups/GraphContentTests.swift
--- a/Tests/CreatorGraphTests/Groups/GraphContentTests.swift
+++ b/Tests/CreatorGraphTests/Groups/GraphContentTests.swift
@@ -145,6 +145,46 @@ struct GraphContentTests {
         }
     }
 
+    /// Undo and Redo replay commands that were valid when recorded (`DocumentModel.replay`), so the new-definition and
+    /// interface rules, which a hand-edited file may already break, don't apply to them.
+    @Test func aReplayedCommandSkipsTheRulesTheFileMayAlreadyBreak() throws {
+        let start = content([], [Doubler(name: "Same").definition])
+        let twin = Doubler(name: "Same").definition
+        expectRefused(.addDefinition(twin), on: start, "A group named “Same” already exists.")
+        var replayed = start
+        try replayed.apply(.addDefinition(twin), registry: testRegistry, replaying: true)
+        #expect(replayed.definitions.count == 2, "two definitions called “Same”, as the hand-edited file had")
+        var renamed = twin.interface
+        renamed.name = "Other"
+        try replayed.apply(.setInterface(twin.id, renamed), registry: testRegistry)
+        var back = twin.interface
+        back.name = "Same"
+        #expect(throws: GraphError.invalidValue("A group named “Same” already exists.")) {
+            try replayed.apply(.setInterface(twin.id, back), registry: testRegistry)
+        }
+        try replayed.apply(.setInterface(twin.id, back), registry: testRegistry, replaying: true)
+        #expect(replayed.definitions[twin.id]?.name == "Same")
+    }
+
+    /// Ungrouping removes the definition with its last group node, and Undo adds it back. If the file already had another
+    /// definition of that name, the add-back must still go through (it used to trip `assertionFailure` in a debug build).
+    @MainActor
+    @Test func undoingAnUngroupInAFileWithRepeatedNamesRestoresTheDefinition() throws {
+        let first = Doubler(name: "Same"), second = Doubler(name: "Same")
+        let node = instance(of: first.definition), kept = instance(of: second.definition)
+        let document = DocumentModel(file: GraphFile(graph: graph([node, kept]),
+                                                     definitions: table([first.definition, second.definition])),
+                                     registry: testRegistry, kernel: FakeKernel())
+        let before = document.content
+        let edit = try GroupCommands.ungroup(node.id, in: .root, of: document.content, registry: testRegistry)
+        try document.perform(edit.command)
+        #expect(document.definitions.count == 1)
+        document.undo()
+        #expect(document.content == before)
+        document.redo()
+        #expect(document.definitions.count == 1)
+    }
+
     @Test func aRefusedBatchChangesNothing() {
         let start = content([instance(of: doubler.definition)], [doubler.definition])
         expectRefused(.batch([.inDefinition(doubler.id, .addNode(makeNode(ConstantNode.self))), .removeDefinition(doubler.id)]),
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter 'GraphContentTests'`
Expected: FAIL to compile: `extra argument 'replaying' in call`. To see the real defect, apply only the `GraphContent+Apply.swift` hunks: `undoingAnUngroupInAFileWithRepeatedNamesRestoresTheDefinition` then traps with `Fatal error: Undo history could not be replayed: invalidValue("A group named “Same” already exists.")` (signal 5).

- [ ] **Step 3: Implement**

Apply this patch (sources):

```diff
diff --git a/Sources/CreatorGraph/DocumentModel.swift b/Sources/CreatorGraph/DocumentModel.swift
--- a/Sources/CreatorGraph/DocumentModel.swift
+++ b/Sources/CreatorGraph/DocumentModel.swift
@@ -141,7 +141,7 @@ public final class DocumentModel {
         let stale = graph.downstreamClosure(of: content.touchedTopLevelNodes(command))
         let effect = effect(of: command)
         do {
-            try content.apply(command, registry: baseRegistry)
+            try content.apply(command, registry: baseRegistry, replaying: true)
         } catch {
             // Undo and redo replay commands that were valid when recorded, so this means
             // the history is out of step with the graph.
diff --git a/Sources/CreatorGraph/Groups/GraphContent+Apply.swift b/Sources/CreatorGraph/Groups/GraphContent+Apply.swift
--- a/Sources/CreatorGraph/Groups/GraphContent+Apply.swift
+++ b/Sources/CreatorGraph/Groups/GraphContent+Apply.swift
@@ -7,11 +7,14 @@ extension GraphContent {
     /// containing itself, directly or through other groups; an Output node in a group; Group Input or Group Output
     /// outside a group, a second one, or deleting one; removing a definition in use; a bad name or socket list; and,
     /// once the whole command has applied, a socket removed from a definition or given another type while a wire is
-    /// still on it, on a group node or inside on Group Input or Group Output.
+    /// still on it, on a group node or inside on Group Input or Group Output. `replaying` is for Undo and Redo, which
+    /// replay commands that were valid when recorded: a new definition and a new interface are then not checked again,
+    /// as a hand-edited file may already break those rules (a name used twice) and its history must still replay.
     @discardableResult
-    public mutating func apply(_ command: GraphCommand, registry: NodeRegistry) throws(GraphError) -> GraphCommand {
+    public mutating func apply(_ command: GraphCommand, registry: NodeRegistry,
+                               replaying: Bool = false) throws(GraphError) -> GraphCommand {
         let before = self
-        let inverse = try applyCommand(command, registry: registry)
+        let inverse = try applyCommand(command, registry: registry, replaying: replaying)
         do {
             try checkWiredSockets(changedBy: command, before: before)
         } catch {
@@ -22,14 +25,15 @@ extension GraphContent {
     }
 
     /// `apply` without the check across the whole command, so a batch can rename a socket and move its wires.
-    private mutating func applyCommand(_ command: GraphCommand, registry: NodeRegistry) throws(GraphError) -> GraphCommand {
+    private mutating func applyCommand(_ command: GraphCommand, registry: NodeRegistry,
+                                       replaying: Bool) throws(GraphError) -> GraphCommand {
         switch command {
         case .batch(let commands):
             let snapshot = self
             var inverses: [GraphCommand] = []
             do {
                 for command in commands {
-                    inverses.append(try applyCommand(command, registry: registry))
+                    inverses.append(try applyCommand(command, registry: registry, replaying: replaying))
                 }
             } catch {
                 self = snapshot
@@ -37,7 +41,7 @@ extension GraphContent {
             }
             return .batch(Array(inverses.reversed()))
         case .inDefinition, .addDefinition, .removeDefinition, .setInterface:
-            return try applyGroupEdit(command, registry: registry)
+            return try applyGroupEdit(command, registry: registry, replaying: replaying)
         default:
             try check(command, in: .root, registry: registry)
             return try graph.apply(command, registry: registry.withGroups(definitions))
@@ -45,12 +49,13 @@ extension GraphContent {
     }
 
     /// The four group commands; `apply` routes them here.
-    private mutating func applyGroupEdit(_ command: GraphCommand, registry: NodeRegistry) throws(GraphError) -> GraphCommand {
+    private mutating func applyGroupEdit(_ command: GraphCommand, registry: NodeRegistry,
+                                         replaying: Bool) throws(GraphError) -> GraphCommand {
         switch command {
         case .inDefinition(let id, let inner):
             return .inDefinition(id, try applyInside(id, inner, registry: registry))
         case .addDefinition(let definition):
-            try checkNew(definition, registry: registry)
+            if !replaying { try checkNew(definition, registry: registry) }
             definitions[definition.id] = definition
             return .removeDefinition(definition.id)
         case .removeDefinition(let id):
@@ -60,7 +65,7 @@ extension GraphContent {
             return .addDefinition(definition)
         case .setInterface(let id, let interface):
             guard var definition = definitions[id] else { throw GroupRefusal.missing }
-            try checkInterface(interface, of: id)
+            if !replaying { try checkInterface(interface, of: id) }
             let old = definition.interface
             definition.interface = interface
             definitions[id] = definition
```

- [ ] **Step 4: Run them and see them pass**

Run: `swift test --filter 'GraphContentTests'`
Expected: all pass.

- [ ] **Step 5: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2167 tests (master + 25)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorGraph/DocumentModel.swift Sources/CreatorGraph/Groups/GraphContent+Apply.swift Tests/CreatorGraphTests/Groups/GraphContentTests.swift
git commit -m "followups-editor task 13: Undo and Redo replay without the new-definition and interface rules (GK-13)"
```

### Task 14: Group-edit test gaps (GK-13)

**Why.** The rest of GK-13 is missing coverage; each test below passes on the current code (pins, no source change), and the two-level pick test for Ungroup was mutation-checked (dropping `picks` from Ungroup's batch makes it fail). New: Ungroup and Make Unique with the group node inside a definition; an output that fans out to two takers; a pick through two levels of group nodes for Ungroup and for Make Unique; removal of an unwired output socket; a wire left on Group Input refusing a socket's removal; the unknown-type message for a wire leaving the selection; and comments when other instances remain and when ungrouping inside a definition. The new `NestedGroupEditTests` struct keeps `UngroupTests` under SwiftLint's 250-line struct limit.

**Files:**

- Create: `Tests/CreatorGraphTests/Groups/NestedGroupEditTests.swift`
- Test: `Tests/CreatorGraphTests/Comments/CommentGroupTests.swift`
- Test: `Tests/CreatorGraphTests/Groups/GraphContentTests.swift`
- Test: `Tests/CreatorGraphTests/Groups/GroupCommandTests.swift`
- Test: `Tests/CreatorGraphTests/Groups/GroupInterfaceTests.swift`

**Interfaces:**
- Consumes: `define`, `instance(of:)`, `Doubler`, `pickRegistry`, `endCapPick(of:)`, `NodeID.scoped`, `FacePickCountNode`.
- Produces: Tests only.

- [ ] **Step 1: Add the tests**

These pass on the current code (they pin behaviour or add coverage); there is no source change in this task. Apply:

```diff
diff --git a/Tests/CreatorGraphTests/Comments/CommentGroupTests.swift b/Tests/CreatorGraphTests/Comments/CommentGroupTests.swift
--- a/Tests/CreatorGraphTests/Comments/CommentGroupTests.swift
+++ b/Tests/CreatorGraphTests/Comments/CommentGroupTests.swift
@@ -70,4 +70,44 @@ struct CommentGroupTests {
         document.undo()
         #expect(document.content == before, "one undo brings back the definition and the node, and removes both comments")
     }
+
+    @Test func ungroupingOneOfSeveralInstancesSplicesCommentsAndLeavesTheDefinitionsOwnAlone() throws {
+        var doubler = Doubler()
+        doubler.definition.graph.stickies[commentID(5)] = note(5, "Inside", at: Vector2(10, 20))
+        var node = instance(of: doubler.definition, output: true)
+        node.position = Vector2(100, 200)
+        let other = instance(of: doubler.definition, output: true)
+        let document = DocumentModel(file: GraphFile(graph: graph([node, other]), definitions: table([doubler.definition])),
+                                     registry: testRegistry, kernel: FakeKernel())
+        let before = document.content
+        let edit = try GroupCommands.ungroup(node.id, in: .root, of: document.content, registry: testRegistry)
+        try document.perform(edit.command)
+        #expect(document.definitions[doubler.id]?.graph.stickies[commentID(5)]?.text == "Inside", "the other instance keeps it")
+        #expect(document.graph.stickies.values.map(\.text) == ["Inside"])
+        #expect(document.graph.stickies.values.first?.frame.origin == Vector2(110, 220))
+        #expect(document.graph.stickies[commentID(5)] == nil, "a fresh ID")
+        document.undo()
+        #expect(document.content == before)
+    }
+
+    @Test func ungroupingInsideADefinitionSplicesCommentsIntoThatDefinition() throws {
+        var doubler = Doubler()
+        doubler.definition.graph.frames[commentID(6)] = box(6, "Inner", at: Vector2(30, 40))
+        var inner = instance(of: doubler.definition)
+        inner.position = Vector2(100, 200)
+        let wrapper = define("Wrapper", outputs: [SocketSpec("result", .number)], nodes: [inner]) { _, output in
+            [link(inner, "result", output, "result")]
+        }
+        let top = instance(of: wrapper, output: true)
+        let document = DocumentModel(file: GraphFile(graph: graph([top]), definitions: table([doubler.definition, wrapper])),
+                                     registry: testRegistry, kernel: FakeKernel())
+        let before = document.content
+        let edit = try GroupCommands.ungroup(inner.id, in: .definition(wrapper.id), of: document.content, registry: testRegistry)
+        try document.perform(edit.command)
+        let frames = try #require(document.definitions[wrapper.id]).graph.frames.values
+        #expect(frames.map(\.title) == ["Inner"] && frames.first?.frame.origin == Vector2(130, 240))
+        #expect(document.graph.frames.isEmpty, "not the top level")
+        document.undo()
+        #expect(document.content == before)
+    }
 }
diff --git a/Tests/CreatorGraphTests/Groups/GraphContentTests.swift b/Tests/CreatorGraphTests/Groups/GraphContentTests.swift
--- a/Tests/CreatorGraphTests/Groups/GraphContentTests.swift
+++ b/Tests/CreatorGraphTests/Groups/GraphContentTests.swift
@@ -262,4 +262,12 @@ struct GraphContentTests {
         #expect(start.affectsResults(.inDefinition(doubler.id, .setInput(doubler.add.id, "b", nil))))
         #expect(!start.affectsMessages(.rename(doubler.add.id, "Plus")), "top-level names aren't in any message")
     }
+
+    /// With no group node using the definition the wire left on the socket is inside, on Group Input.
+    @Test func aSocketWiredInsideOnGroupInputCantBeRemovedEither() {
+        let start = content([], [doubler.definition])
+        var interface = doubler.definition.interface
+        interface.inputs = []
+        expectRefused(.setInterface(doubler.id, interface), on: start, "“value” is wired on “Group Input”. Unwire it first.")
+    }
 }
diff --git a/Tests/CreatorGraphTests/Groups/GroupCommandTests.swift b/Tests/CreatorGraphTests/Groups/GroupCommandTests.swift
--- a/Tests/CreatorGraphTests/Groups/GroupCommandTests.swift
+++ b/Tests/CreatorGraphTests/Groups/GroupCommandTests.swift
@@ -210,6 +210,18 @@ struct GroupCommandTests {
         }
     }
 
+    @Test func aWireOutOfTheSelectionFromASocketOfUnknownTypeIsRefused() {
+        var mystery = GroupScene.position(makeNode(ConstantNode.self), -200, 0)
+        mystery.typeID = "missing.type"
+        var content = GraphContent(graph: document().graph, definitions: [:])
+        content.graph.nodes[mystery.id] = mystery
+        content.graph.links.append(link(mystery, "value", scene.other, "b"))
+        #expect(throws: GraphError.invalidValue(
+            "A wire out of the selection leaves a socket of unknown type, so it can't become an output.")) {
+            try GroupCommands.group([mystery.id], in: .root, of: content, registry: testRegistry)
+        }
+    }
+
     /// A node outside the selection that both takes from it and feeds it would leave the group node wired in a cycle
     /// (G → a1 → G), which wiring refuses, so Group refuses it too.
     @Test func groupingAroundAnOutsideNodeInBetweenIsRefused() {
diff --git a/Tests/CreatorGraphTests/Groups/GroupInterfaceTests.swift b/Tests/CreatorGraphTests/Groups/GroupInterfaceTests.swift
--- a/Tests/CreatorGraphTests/Groups/GroupInterfaceTests.swift
+++ b/Tests/CreatorGraphTests/Groups/GroupInterfaceTests.swift
@@ -137,4 +137,19 @@ struct GroupInterfaceTests {
         setup.document.undo()
         #expect(setup.document.definitions[unused.id] == unused.definition)
     }
+
+    @Test func anUnwiredOutputIsRemovedWithItsWireInside() throws {
+        let setup = Setup(doubler)
+        let document = setup.document
+        try document.perform(.disconnect(link(setup.wired, "result", setup.first, "value")))
+        try document.perform(.disconnect(link(setup.typed, "result", setup.second, "value")))
+        let before = document.content
+        try document.perform(try GroupCommands.removeSocket(doubler.id, side: .output, name: "result", in: document.content))
+        let definition = try #require(document.definitions[doubler.id])
+        #expect(definition.outputs.isEmpty)
+        let remaining: Set = [link(doubler.input, "value", doubler.add, "a"), link(doubler.input, "value", doubler.add, "b")]
+        #expect(Set(definition.graph.links) == remaining)
+        document.undo()
+        #expect(document.content == before, "one undo step")
+    }
 }
diff --git a/Tests/CreatorGraphTests/Groups/NestedGroupEditTests.swift b/Tests/CreatorGraphTests/Groups/NestedGroupEditTests.swift
new file mode 100644
--- /dev/null
+++ b/Tests/CreatorGraphTests/Groups/NestedGroupEditTests.swift
@@ -0,0 +1,145 @@
+import CreatorKernel
+import Testing
+@testable import CreatorGraph
+
+/// Ungroup and Make Unique where the group node sits inside a definition, where an output fans out, and where a pick
+/// names a face through two levels of group nodes (groups spec §5). `UngroupTests` has the top-level cases.
+@MainActor
+struct NestedGroupEditTests {
+    let doubler = Doubler()
+
+    func document(_ nodes: [Node], _ links: [Link] = [], _ definitions: [GroupDefinition]) -> DocumentModel {
+        var start = graph(nodes, links)
+        start.sortLinks()
+        return DocumentModel(file: GraphFile(graph: start, definitions: table(definitions)), registry: testRegistry,
+                             kernel: FakeKernel())
+    }
+
+    func perform(_ edit: GroupEdit, on document: DocumentModel) throws -> GroupEdit {
+        try document.perform(edit.command)
+        return edit
+    }
+
+    func count(_ content: GraphContent, _ id: NodeID) async throws -> Double? {
+        let report = try await Evaluator(registry: pickRegistry, kernel: FakeKernel())
+            .evaluate(content.graph, definitions: content.definitions, demand: [id])
+        return report.results[id]?.outputs?["count"]?.numbers?.first
+    }
+
+    /// "Outer": a definition that places `inner` once and puts out its `result`.
+    func outer(placing inner: Node) -> GroupDefinition {
+        define("Outer", outputs: [SocketSpec("result", .number)], nodes: [inner]) { _, output in
+            [link(inner, "result", output, "result")]
+        }
+    }
+
+    @Test func ungroupingInsideADefinitionSplicesIntoThatDefinitionOnly() async throws {
+        let inner = instance(of: doubler.definition, ["value": .number(4)])
+        let outer = outer(placing: inner)
+        let top = instance(of: outer, output: true)
+        let document = document([top], [], [doubler.definition, outer])
+        let before = document.content
+        let edit = try GroupCommands.ungroup(inner.id, in: .definition(outer.id), of: document.content, registry: testRegistry)
+        try document.perform(edit.command)
+        let spliced = try #require(document.definitions[outer.id]).graph
+        let add = try #require(edit.selection.first.flatMap { spliced.nodes[$0] })
+        #expect(add.typeID == AddNode.typeID && add.inputValues == ["a": .number(4), "b": .number(4)])
+        #expect(spliced.nodes[inner.id] == nil, "the group node is gone from Outer")
+        let output = try #require(document.definitions[outer.id]?.outputNode)
+        #expect(spliced.links.contains(link(add, "sum", output, "result")))
+        #expect(document.definitions[doubler.id] == nil, "its last group node went with it")
+        #expect(document.graph.nodes[top.id] == top, "the top level is untouched")
+        await document.waitForEvaluation()
+        #expect(document.results[top.id]?.outputs?["result"]?.numbers == [8])
+        document.undo()
+        #expect(document.content == before)
+    }
+
+    @Test func makeUniqueInsideADefinitionRetargetsThatGroupNodeOnly() async throws {
+        let inner = instance(of: doubler.definition, ["value": .number(4)])
+        let outer = outer(placing: inner)
+        let beside = instance(of: doubler.definition, ["value": .number(1)], output: true)
+        let top = instance(of: outer, output: true)
+        let document = document([top, beside], [], [doubler.definition, outer])
+        let before = document.content
+        let edit = try GroupCommands.makeUnique(inner.id, in: .definition(outer.id), of: document.content, registry: testRegistry)
+        try document.perform(edit.command)
+        let copy = try #require(document.definitions.values.first { $0.name == "Doubler 2" })
+        #expect(edit.selection == [inner.id])
+        #expect(document.definitions[outer.id]?.graph.nodes[inner.id]?.inputValues[NodeSetting.group] == .group(copy.id))
+        #expect(document.definitions[outer.id]?.graph.nodes[inner.id]?.name == "Doubler 2")
+        #expect(document.graph.nodes[beside.id]?.inputValues[NodeSetting.group] == .group(doubler.id), "the other keeps the original")
+        await document.waitForEvaluation()
+        #expect(document.results[top.id]?.outputs?["result"]?.numbers == [8])
+        #expect(document.results[beside.id]?.outputs?["result"]?.numbers == [2])
+        document.undo()
+        #expect(document.content == before)
+    }
+
+    @Test func ungroupingAnOutputThatFansOutFeedsEveryTakerFromTheSameInnerSocket() async throws {
+        let node = instance(of: doubler.definition, ["value": .number(3)])
+        let first = makeNode(SinkNode.self, output: true), second = makeNode(SinkNode.self, output: true)
+        let document = document([node, first, second],
+                                [link(node, "result", first, "value"), link(node, "result", second, "value")], [doubler.definition])
+        let edit = try perform(try GroupCommands.ungroup(node.id, in: .root, of: document.content, registry: testRegistry),
+                               on: document)
+        let add = try #require(edit.selection.first.flatMap { document.graph.nodes[$0] })
+        #expect(Set(document.graph.links) == [link(add, "sum", first, "value"), link(add, "sum", second, "value")])
+        await document.waitForEvaluation()
+        #expect(document.results[first.id]?.outputs?["value"]?.numbers == [6])
+        #expect(document.results[second.id]?.outputs?["value"]?.numbers == [6])
+    }
+
+    /// "Wrapped": a group node of "Capped" (a box) inside "Wrapper", both taking the box's solid out; a counter at the top
+    /// level picks the end cap of that box by the name it has through the two group nodes.
+    struct ChainScene {
+        var content: GraphContent
+        let box: Node
+        let inner: Node
+        let outer: Node
+        let counter: Node
+    }
+
+    func chainScene() -> ChainScene {
+        let box = pickRegistry.makeNode(BoxNode.typeID)
+        let capped = define("Capped", outputs: [SocketSpec("solid", .solid)], nodes: [box]) { _, output in
+            [link(box, "solid", output, "solid")]
+        }
+        let inner = instance(of: capped)
+        let wrapper = define("Wrapper", outputs: [SocketSpec("solid", .solid)], nodes: [inner]) { _, output in
+            [link(inner, "solid", output, "solid")]
+        }
+        let outer = instance(of: wrapper)
+        var counter = pickRegistry.makeNode(FacePickCountNode.typeID)
+        counter.inputValues[NodeSetting.face] = endCapPick(of: NodeID.scoped([outer.id, inner.id, box.id]))
+        let content = GraphContent(graph: graph([outer, counter], [link(outer, "solid", counter, "solid")]),
+                                   definitions: table([capped, wrapper]))
+        return ChainScene(content: content, box: box, inner: inner, outer: outer, counter: counter)
+    }
+
+    @Test func ungroupRenamesAPickThroughTwoLevelsOfGroups() async throws {
+        let scene = chainScene()
+        var content = scene.content
+        #expect(try await count(content, scene.counter.id) == 1)
+        let edit = try GroupCommands.ungroup(scene.outer.id, in: .root, of: content, registry: pickRegistry)
+        try content.apply(edit.command, registry: pickRegistry)
+        let spliced = try #require(edit.selection.first)
+        #expect(spliced != scene.inner.id, "the inner group node comes out under a new ID")
+        #expect(content.graph.nodes[scene.counter.id]?.inputValues[NodeSetting.face]
+                == endCapPick(of: NodeID.scoped([spliced, scene.box.id])), "now one group node deep")
+        #expect(try await count(content, scene.counter.id) == 1)
+    }
+
+    @Test func makeUniqueRenamesAPickThroughTwoLevelsOfGroups() async throws {
+        let scene = chainScene()
+        var content = scene.content
+        let edit = try GroupCommands.makeUnique(scene.outer.id, in: .root, of: content, registry: pickRegistry)
+        try content.apply(edit.command, registry: pickRegistry)
+        let copy = try #require(content.definitions.values.first { $0.name == "Wrapper 2" })
+        let copiedInner = try #require(copy.graph.nodes.values.first { $0.typeID == GroupNodes.groupTypeID })
+        #expect(copiedInner.id != scene.inner.id)
+        #expect(content.graph.nodes[scene.counter.id]?.inputValues[NodeSetting.face]
+                == endCapPick(of: NodeID.scoped([scene.outer.id, copiedInner.id, scene.box.id])))
+        #expect(try await count(content, scene.counter.id) == 1)
+    }
+}
```

- [ ] **Step 2: Run them**

Run: `swift test --filter CreatorGraphTests`
Expected: all pass.

- [ ] **Step 3: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2177 tests (master + 35)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 4: Commit**

```bash
git add Tests/CreatorGraphTests/Comments/CommentGroupTests.swift Tests/CreatorGraphTests/Groups/GraphContentTests.swift Tests/CreatorGraphTests/Groups/GroupCommandTests.swift Tests/CreatorGraphTests/Groups/GroupInterfaceTests.swift Tests/CreatorGraphTests/Groups/NestedGroupEditTests.swift
git commit -m "followups-editor task 14: Group-edit test gaps (GK-13)"
```

### Task 15: A repeated exposed dimension name gets its own warning (GK-10)

**Why.** `SketchSockets.refused` said "the node already has an input or setting with that name" for every refused exposed dimension, including one whose name another exposed dimension already has (only a hand-edited file can: renaming refuses a taken name). `partition` now records whether a refusal is a repeat and the warning says so; the empty-name warning gets its first test, and the one-degree-of-freedom wording (`freedom == 1 ? "1 degree" : …` in `SketchSolve.run`, the branch GK-10 names; `SketchNodeTests` pins only "8 degrees") gets its own. The tests are in a new file so they cannot collide with the kernel track's edits to `SketchNodeTests.swift`.

**Files:**

- Create: `Tests/CreatorNodesTests/SketchExposedNameTests.swift`
- Modify: `Sources/CreatorNodes/Sketch/SketchSockets.swift`

**Interfaces:**
- Consumes: `Harness`, `RectangleSketch` (CreatorNodesTests fixtures).
- Produces: `SketchSockets.refused` returns "Dimension “x” can't be an input: another exposed dimension has the same name. Rename one of them." for a repeat.

- [ ] **Step 1: Write the failing tests**

Apply this patch (tests only):

```diff
diff --git a/Tests/CreatorNodesTests/SketchExposedNameTests.swift b/Tests/CreatorNodesTests/SketchExposedNameTests.swift
new file mode 100644
--- /dev/null
+++ b/Tests/CreatorNodesTests/SketchExposedNameTests.swift
@@ -0,0 +1,52 @@
+import CreatorGraph
+import CreatorKernel
+@testable import CreatorNodes
+import CreatorSketch
+import Testing
+
+/// Why an exposed dimension isn't an input (`SketchSockets.refused`): no name, a name the node already uses, or a name
+/// another exposed dimension has; and the singular wording of the degrees-of-freedom warning (`SketchSolve.run`).
+struct SketchExposedNameTests {
+    func sketchNode(_ h: inout Harness, _ sketch: Sketch) -> Node {
+        h.add(SketchNode.self, [NodeSetting.sketch: .sketch(sketch)])
+    }
+
+    /// One degree of freedom left reads "1 degree", where `SketchNodeTests` pins the plural ("8 degrees").
+    @Test func aSketchWithOneDegreeOfFreedomLeftWarnsInTheSingular() async throws {
+        var rectangle = RectangleSketch()
+        rectangle.sketch.dimensions[rectangle.height] = nil  // The height is the only thing left free.
+        var h = Harness()
+        let node = sketchNode(&h, rectangle.sketch)
+        let report = try await h.run([node])
+        #expect(SketchSolver.solve(rectangle.sketch).degreesOfFreedom == 1)
+        #expect(report.warning(node) == "The sketch has 1 degree of freedom left, so it isn't fully constrained.")
+    }
+
+    @Test func aDimensionWithNoNameIsNotExposedAndWarns() async throws {
+        var rectangle = RectangleSketch()
+        rectangle.expose(rectangle.width)
+        rectangle.sketch.dimensions[rectangle.width]?.name = ""
+        var h = Harness()
+        let node = sketchNode(&h, rectangle.sketch)
+        #expect(SketchNode.inputs(for: h.graph.nodes[node.id] ?? node).map(\.name) == ["plane", "references"])
+        let report = try await h.run([node])
+        #expect(report.warning(node) == "An exposed dimension has no name, so it isn't an input. Name it to expose it.")
+    }
+
+    /// Two exposed dimensions with one name can only come from a hand-edited file (renaming refuses a taken name). The
+    /// first, in id order, is the input; the other's warning says why, which isn't "the node already has an input or
+    /// setting with that name".
+    @Test func aSecondExposedDimensionWithTheSameNameIsNotExposedAndSaysSo() async throws {
+        var rectangle = RectangleSketch()
+        rectangle.expose(rectangle.width)
+        rectangle.expose(rectangle.height)
+        let name = rectangle.sketch.dimensions[rectangle.width]?.name ?? ""
+        rectangle.sketch.dimensions[rectangle.height]?.name = name
+        var h = Harness()
+        let node = sketchNode(&h, rectangle.sketch)
+        let report = try await h.run([node])
+        #expect(SketchNode.inputs(for: h.graph.nodes[node.id] ?? node).map(\.name) == ["plane", "references", SocketName(name)])
+        #expect(report.warning(node) == "Dimension “\(name)” can't be an input: another exposed dimension has the same name. "
+            + "Rename one of them.")
+    }
+}
```

- [ ] **Step 2: Run them and see them fail**

Run: `swift test --filter 'SketchExposedNameTests'`
Expected: FAIL (1 issue): `aSecondExposedDimensionWithTheSameNameIsNotExposedAndSaysSo`. `aDimensionWithNoNameIsNotExposedAndWarns` and `aSketchWithOneDegreeOfFreedomLeftWarnsInTheSingular` are pins (the latter needs no source change; mutation-checked: changing `"1 degree"` to `"1 degrees"` in `SketchSolve.swift` fails it). The kernel track's GK-9 edits `SketchSolve.swift`; this task does not.

- [ ] **Step 3: Implement**

Apply this patch (sources):

```diff
diff --git a/Sources/CreatorNodes/Sketch/SketchSockets.swift b/Sources/CreatorNodes/Sketch/SketchSockets.swift
--- a/Sources/CreatorNodes/Sketch/SketchSockets.swift
+++ b/Sources/CreatorNodes/Sketch/SketchSockets.swift
@@ -13,23 +13,31 @@ enum SketchSockets {
 
     /// Exposed dimensions that can't be sockets, as warnings for the node.
     static func refused(_ sketch: Sketch) -> [String] {
-        partition(sketch).refused.map { name in
-            name.isEmpty
-                ? "An exposed dimension has no name, so it isn't an input. Name it to expose it."
-                : "Dimension “\(name)” can't be an input: the node already has an input or setting with that name. Rename it."
+        partition(sketch).refused.map { refusal in
+            if refusal.name.isEmpty {
+                return "An exposed dimension has no name, so it isn't an input. Name it to expose it."
+            }
+            return refusal.isRepeat
+                ? "Dimension “\(refusal.name)” can't be an input: another exposed dimension has the same name. Rename one of them."
+                : "Dimension “\(refusal.name)” can't be an input: the node already has an input or setting with that name. Rename it."
         }
     }
 
-    private static func partition(_ sketch: Sketch) -> (sockets: [(id: DimensionID, spec: SocketSpec)], refused: [String]) {
+    private static func partition(_ sketch: Sketch)
+        -> (sockets: [(id: DimensionID, spec: SocketSpec)], refused: [(name: String, isRepeat: Bool)]) {
         var sockets: [(id: DimensionID, spec: SocketSpec)] = []
-        var refused: [String] = []
+        var refused: [(name: String, isRepeat: Bool)] = []
         var used = Set<String>()
         let exposed = sketch.dimensionIDs.compactMap { id in sketch.dimensions[id].map { (id, $0) } }
             .filter { $0.1.isExposed }
             .sorted { ($0.1.name, $0.0) < ($1.1.name, $1.0) }
         for (id, dimension) in exposed {
-            guard !isReserved(dimension.name), used.insert(dimension.name).inserted else {
-                refused.append(dimension.name)
+            guard !isReserved(dimension.name) else {
+                refused.append((dimension.name, false))
+                continue
+            }
+            guard used.insert(dimension.name).inserted else {
+                refused.append((dimension.name, true))
                 continue
             }
             let unit: ValueUnit = if case .angle = dimension.kind { .degrees } else { .millimetres }
```

- [ ] **Step 4: Run them and see them pass**

Run: `swift test --filter 'SketchExposedNameTests'`
Expected: all pass.

- [ ] **Step 5: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2180 tests (master + 38)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorNodes/Sketch/SketchSockets.swift Tests/CreatorNodesTests/SketchExposedNameTests.swift
git commit -m "followups-editor task 15: A repeated exposed dimension name gets its own warning (GK-10)"
```

### Task 16: Editor test hardening (ED-17, editor side)

**Why.** Render tests that compared glyph counts only get the model-level assertion they were standing in for (`BreadcrumbRenderTests`, `LibraryGroupsTests`, `GroupLookTests`); `ThemeRenderTests` gains a test that draws seven role-reading views under Dracula and under Alucard (a view that forgot `@Environment(ThemeStore.self)` fails it; mutation-checked on `StickyView`); two cut tests pin ED-11's order; `SliderEditingTests.aPressWithoutAChangeLeavesNoUndoStep` also drags through the value the field already has (mutation-checked: removing the `value != field.value` guard in `setInput` fails it). No source changes. Why the other two named slider and shake pins are not strengthened further is in "What each owned item became", ED-17.

**Files:**

- Test: `Tests/CreatorEditorTests/BreadcrumbRenderTests.swift`
- Test: `Tests/CreatorEditorTests/EditorGroupClipboardTests.swift`
- Test: `Tests/CreatorEditorTests/GroupLookTests.swift`
- Test: `Tests/CreatorEditorTests/LibraryGroupsTests.swift`
- Test: `Tests/CreatorEditorTests/SliderEditingTests.swift`
- Test: `Tests/CreatorEditorTests/ThemeRenderTests.swift`

**Interfaces:**
- Consumes: `GroupedEditor`, `renderHeadless`.
- Produces: Tests only.

- [ ] **Step 1: Add the tests**

These pass on the current code (they pin behaviour or add coverage); there is no source change in this task. Apply:

```diff
diff --git a/Tests/CreatorEditorTests/BreadcrumbRenderTests.swift b/Tests/CreatorEditorTests/BreadcrumbRenderTests.swift
--- a/Tests/CreatorEditorTests/BreadcrumbRenderTests.swift
+++ b/Tests/CreatorEditorTests/BreadcrumbRenderTests.swift
@@ -13,7 +13,9 @@ struct BreadcrumbRenderTests {
         editor.enterGroup(grouped.group)
         let inside = renderHeadless { GraphPanelHeader(model: editor) }.glyphs.count
         #expect(inside > top, "Group and › join Graph")
+        #expect(editor.breadcrumbs.map(\.title) == ["Graph", "Group"])
         editor.exitGroup()
+        #expect(editor.breadcrumbs.map(\.title) == ["Graph"])
         #expect(renderHeadless { GraphPanelHeader(model: editor) }.glyphs.count == top)
     }
 
diff --git a/Tests/CreatorEditorTests/EditorGroupClipboardTests.swift b/Tests/CreatorEditorTests/EditorGroupClipboardTests.swift
--- a/Tests/CreatorEditorTests/EditorGroupClipboardTests.swift
+++ b/Tests/CreatorEditorTests/EditorGroupClipboardTests.swift
@@ -146,6 +146,31 @@ struct EditorGroupClipboardTests {
         #expect(editor.clipboard == earlier)
     }
 
+    /// Cut deletes first and copies only what the delete took, so a cut that deletes nothing leaves the clipboard alone.
+    @Test func cuttingOnlyTheBoundaryKeepsTheClipboardAndExplainsWhy() throws {
+        let grouped = try GroupedEditor()
+        let editor = grouped.editor
+        editor.enterGroup(grouped.group)
+        editor.selection = [grouped.rectangle.id]
+        editor.copySelection()
+        let earlier = editor.clipboard
+        editor.selection = Set(editor.graph.nodes.values.filter(GroupNodes.isBoundary).map(\.id))
+        editor.perform(.cut)
+        #expect(editor.clipboard == earlier)
+        #expect(editor.refusal?.message == "A group's Group Input and Group Output can't be deleted.")
+        #expect(editor.graph.nodes.count == 4)
+    }
+
+    @Test func cuttingTheBoundaryWithANodeTakesOnlyTheNode() throws {
+        let grouped = try GroupedEditor()
+        let editor = grouped.editor
+        editor.enterGroup(grouped.group)
+        editor.selectAll()
+        editor.perform(.cut)
+        #expect(editor.clipboard?.nodes.map(\.id).sorted() == [grouped.rectangle.id, grouped.extrude.id].sorted())
+        #expect(editor.graph.nodes.values.allSatisfy(GroupNodes.isBoundary) && editor.graph.nodes.count == 2)
+    }
+
     @Test func deletingOnlyTheBoundaryExplainsWhyNothingHappened() throws {
         let grouped = try GroupedEditor()
         let editor = grouped.editor
diff --git a/Tests/CreatorEditorTests/GroupLookTests.swift b/Tests/CreatorEditorTests/GroupLookTests.swift
--- a/Tests/CreatorEditorTests/GroupLookTests.swift
+++ b/Tests/CreatorEditorTests/GroupLookTests.swift
@@ -88,6 +88,7 @@ struct GroupLookTests {
                                                          in: editor.document.content))
         let renamed = glyphs()
         #expect(renamed > top, "the group node's header reads the definition's name")
+        #expect(editor.shape(of: try #require(editor.graph.nodes[grouped.group])).title == "Hole pattern for ribs")
         editor.enterGroup(grouped.group)
         #expect(glyphs() != renamed, "the canvas draws the inside, not the top level")
     }
diff --git a/Tests/CreatorEditorTests/LibraryGroupsTests.swift b/Tests/CreatorEditorTests/LibraryGroupsTests.swift
--- a/Tests/CreatorEditorTests/LibraryGroupsTests.swift
+++ b/Tests/CreatorEditorTests/LibraryGroupsTests.swift
@@ -162,5 +162,8 @@ struct LibraryGroupsTests {
         editor.setLibraryQuery("grou")
         let onlyGroups = renderHeadless { NodeLibraryView(model: editor, input: GraphPanelInput(model: editor)) }.glyphs.count
         #expect(onlyGroups < withGroups && onlyGroups != noMatch, "the search drops the node types and keeps the Groups section")
+        #expect(editor.librarySections.isEmpty && editor.libraryGroups.map(\.name) == ["Group"], "what the view was handed")
+        editor.setLibraryQuery("zzzz")
+        #expect(editor.librarySections.isEmpty && editor.libraryGroups.isEmpty)
     }
 }
diff --git a/Tests/CreatorEditorTests/SliderEditingTests.swift b/Tests/CreatorEditorTests/SliderEditingTests.swift
--- a/Tests/CreatorEditorTests/SliderEditingTests.swift
+++ b/Tests/CreatorEditorTests/SliderEditingTests.swift
@@ -59,6 +59,8 @@ struct SliderEditingTests {
         let field = try #require(widthField(editor))
         drag(editor, field, through: [])
         #expect(!editor.document.canUndo)
+        drag(editor, field, through: [10, 10])
+        #expect(!editor.document.canUndo, "writing the value it already has is not an edit")
     }
 
     @Test func aParameterSliderDragIsOneStepAndTwoDragsAreTwo() {
diff --git a/Tests/CreatorEditorTests/ThemeRenderTests.swift b/Tests/CreatorEditorTests/ThemeRenderTests.swift
--- a/Tests/CreatorEditorTests/ThemeRenderTests.swift
+++ b/Tests/CreatorEditorTests/ThemeRenderTests.swift
@@ -1,3 +1,5 @@
+import CreatorGeometry
+import CreatorGraph
 import CreatorStyle
 import MetalUI
 import Testing
@@ -36,4 +38,46 @@ struct ThemeRenderTests {
         #expect(switched != dracula)
         #expect(switched == render(ThemeStore(preferences: InMemoryThemePreferences(selectedThemeID: "alucard"))))
     }
+
+    /// The colours `view` paints under `store`.
+    func paint<View: ElementGroup>(_ store: ThemeStore?, _ view: () -> View) -> [[Float]] {
+        let scene = renderHeadless { view().environment(store) }
+        let fills = scene.rects.map { [$0.background.h, $0.background.s, $0.background.l, $0.background.a] }
+        let borders = scene.rects.map { [$0.borderColor.h, $0.borderColor.s, $0.borderColor.l, $0.borderColor.a] }
+        return fills + borders + scene.glyphs.map { [$0.color.h, $0.color.s, $0.color.l, $0.color.a] }
+    }
+
+    /// A view that forgot `@Environment(ThemeStore.self)` would draw Dracula whatever theme is chosen, which the glass
+    /// panel test above can't see. Each of these is drawn under Dracula and under Alucard and must differ.
+    @Test func eachViewThatPaintsRolesReadsTheStore() throws {
+        let alucard = ThemeStore(preferences: InMemoryThemePreferences(selectedThemeID: "alucard"))
+        let dracula = ThemeStore()
+        let grouped = try GroupedEditor()
+        let editor = grouped.editor
+        let shape = NodeShape(title: "Rib", category: .feature, inputs: [], outputs: [])
+        let rect = CanvasRect(origin: .zero, size: Vector2(200, 120))
+        let views: [(String, (ThemeStore?) -> [[Float]])] = [
+            ("node", { store in
+                self.paint(store) {
+                    NodeView(shape: shape, rows: [], origin: .zero, flow: .horizontal, isSelected: true, state: nil, shakes: 0)
+                }
+            }),
+            ("note", { store in
+                self.paint(store) { StickyView(note: StickyNote(text: "Hi", frame: rect), rect: rect, isSelected: false) }
+            }),
+            ("frame", { store in
+                self.paint(store) { CommentFrameView(box: CommentFrame(title: "Frame", frame: rect), rect: rect, isSelected: false) }
+            }),
+            ("header", { store in self.paint(store) { GraphPanelHeader(model: editor) } }),
+            ("library", { store in self.paint(store) { NodeLibraryView(model: editor, input: GraphPanelInput(model: editor)) } }),
+            ("inspector", { store in self.paint(store) { InspectorPanel(model: editor) } }),
+            ("status", { store in self.paint(store) { StatusBadgeView(state: .error("No")) } }),
+        ]
+        editor.selection = [grouped.group]
+        for (name, draw) in views {
+            #expect(!draw(dracula).isEmpty, "\(name) draws something")
+            #expect(draw(alucard) != draw(dracula), "\(name) reads the store's theme")
+            #expect(draw(nil) == draw(dracula), "\(name) without a store is Dracula")
+        }
+    }
 }
```

- [ ] **Step 2: Run them**

Run: `swift test --filter CreatorEditorTests`
Expected: all pass.

- [ ] **Step 3: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2183 tests (master + 41)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 4: Commit**

```bash
git add Tests/CreatorEditorTests/BreadcrumbRenderTests.swift Tests/CreatorEditorTests/EditorGroupClipboardTests.swift Tests/CreatorEditorTests/GroupLookTests.swift Tests/CreatorEditorTests/LibraryGroupsTests.swift Tests/CreatorEditorTests/SliderEditingTests.swift Tests/CreatorEditorTests/ThemeRenderTests.swift
git commit -m "followups-editor task 16: Editor test hardening (ED-17, editor side)"
```

### Task 17: App test hardening (ED-17, app side)

**Why.** Every edit here is test-only (no source file, no `Package.swift`), and each is a one-line change or one added assertion to a test that exists on master. Small edits to app-side tests that ED-17 names: a no-op `transform = CanvasTransform()` removed (`GroupViewportTests`); the pick stored inside the definition must be non-empty (`GroupPickInstancesTests`); `PaletteOverlayTests` compares the palette's bottom edge with the pointer's window point instead of `+ 10 + 46 + 40`; `TitleBarClearanceTests` names AS-5 and uses `GraphPanelLayout.glassPadding`; `WindowChromeTests` asserts the first apply wrote the title; `AppModelOpenURLTests` says why its closing `discardChanges()` is there. Edits only, no new tests, no source changes. These files belong to the app track's directory (see the shared-files table).

**Files:**

- Test: `Tests/CreatorAppTests/AppModelOpenURLTests.swift`
- Test: `Tests/CreatorAppTests/GroupPickInstancesTests.swift`
- Test: `Tests/CreatorAppTests/GroupViewportTests.swift`
- Test: `Tests/CreatorAppTests/PaletteOverlayTests.swift`
- Test: `Tests/CreatorAppTests/TitleBarClearanceTests.swift`
- Test: `Tests/CreatorAppTests/WindowChromeTests.swift`

**Interfaces:**
- Consumes: `EditorModel.windowPoint(fromCanvas:)`, `GraphPanelLayout.glassPadding`.
- Produces: Tests only.

- [ ] **Step 1: Add the tests**

These pass on the current code (they pin behaviour or add coverage); there is no source change in this task. Apply:

```diff
diff --git a/Tests/CreatorAppTests/AppModelOpenURLTests.swift b/Tests/CreatorAppTests/AppModelOpenURLTests.swift
--- a/Tests/CreatorAppTests/AppModelOpenURLTests.swift
+++ b/Tests/CreatorAppTests/AppModelOpenURLTests.swift
@@ -117,6 +117,7 @@ struct AppModelOpenURLTests {
         _ = app.closeRequested()
         app.openRequested(url)
         #expect(app.alert == .saveChanges(name: "Untitled"), "the close question isn't replaced")
+        // Nothing was queued behind the close question, so confirming a discard has no file to open.
         await app.discardChanges()
         #expect(app.fileURL == nil)
     }
diff --git a/Tests/CreatorAppTests/GroupPickInstancesTests.swift b/Tests/CreatorAppTests/GroupPickInstancesTests.swift
--- a/Tests/CreatorAppTests/GroupPickInstancesTests.swift
+++ b/Tests/CreatorAppTests/GroupPickInstancesTests.swift
@@ -35,6 +35,12 @@ struct GroupPickInstancesTests {
         app.viewportClicked(.edge(solid: 0, EdgeID(3)))
         app.finishPick()
         await app.settle()
+        let definition = try #require(app.document.definitions.values.first)
+        guard case .edgePicks(let picks)? = definition.graph.nodes[rule.id]?.inputValues[NodeSetting.picks] else {
+            Issue.record("the rule inside the definition holds no picks")
+            return
+        }
+        #expect(!picks.isEmpty, "the two clicked edges are stored with the definition")
         #expect(app.document.innerResults[[first, chamfer.id]]?.state.isSuccess == true, "the instance it was made in")
         #expect(app.document.innerResults[[second, chamfer.id]]?.state.isSuccess == true, "and the other one")
     }
diff --git a/Tests/CreatorAppTests/GroupViewportTests.swift b/Tests/CreatorAppTests/GroupViewportTests.swift
--- a/Tests/CreatorAppTests/GroupViewportTests.swift
+++ b/Tests/CreatorAppTests/GroupViewportTests.swift
@@ -61,7 +61,6 @@ struct GroupViewportTests {
         let scene = try await groupedBox()
         let app = scene.app
         app.previewMode = .selectedNode
-        app.editor.transform = CanvasTransform()
         let lonely = try #require(app.editor.registry.makeNode(ExtrudeNode.typeID, at: Vector2(200, 300)) as Node?)
         try app.editor.edit(.addNode(lonely), name: UndoName.addNode(lonely))
         app.editor.connect(Link(from: Endpoint(node: scene.rectangle.id, socket: "profile"),
diff --git a/Tests/CreatorAppTests/PaletteOverlayTests.swift b/Tests/CreatorAppTests/PaletteOverlayTests.swift
--- a/Tests/CreatorAppTests/PaletteOverlayTests.swift
+++ b/Tests/CreatorAppTests/PaletteOverlayTests.swift
@@ -21,8 +21,8 @@ struct PaletteOverlayTests {
         app.editor.openPalette()
         let palette = try #require(app.editor.palette)
         let panel = try #require(app.panelPlacement?.panel)
-        #expect(palette.windowOrigin.y + PaletteLayout.size.y <= panel.origin.y + 10 + 46 + 40,
-                "flipped up: its bottom edge is at the pointer")
+        let pointer = try #require(app.editor.windowPoint(fromCanvas: Vector2(200, 40)))
+        #expect(palette.windowOrigin.y + PaletteLayout.size.y <= pointer.y + 0.5, "flipped up: its bottom edge is at the pointer")
         #expect(palette.windowOrigin.y < panel.origin.y, "so it reaches above the graph panel, over the viewport")
 
         let input = AppInput(model: app)
diff --git a/Tests/CreatorAppTests/TitleBarClearanceTests.swift b/Tests/CreatorAppTests/TitleBarClearanceTests.swift
--- a/Tests/CreatorAppTests/TitleBarClearanceTests.swift
+++ b/Tests/CreatorAppTests/TitleBarClearanceTests.swift
@@ -1,9 +1,10 @@
+import CreatorEditor
 import MetalUI
 import Testing
 @testable import CreatorApp
 
 /// The top bar clears the window buttons under a hidden title bar (spec §6.1, gap M6-c). MetalUI sets the insets from
-/// the real window, so the numbers are given here; where the buttons really sit is human check AS-4.
+/// the real window, so the numbers are given here; where the buttons really sit is human check AS-5.
 struct TitleBarClearanceTests {
     func insets(left: Float) -> Edges<Pixels> {
         Edges(top: Pixels(32), right: Pixels(0), bottom: Pixels(0), left: Pixels(left))
@@ -16,7 +17,7 @@ struct TitleBarClearanceTests {
     @Test func theContentStartsRightOfTheButtons() {
         // The buttons end at 69 pt; the glass starts at the margin and pads its content, so the content needs the rest.
         let clearance = AppLayout.topBarClearance(titleBarInsets: insets(left: 69))
-        let contentStart = AppLayout.margin + 10 + clearance
+        let contentStart = AppLayout.margin + GraphPanelLayout.glassPadding + clearance
         #expect(contentStart == 69 + AppLayout.titleBarGap)
         #expect(clearance > 0)
     }
diff --git a/Tests/CreatorAppTests/WindowChromeTests.swift b/Tests/CreatorAppTests/WindowChromeTests.swift
--- a/Tests/CreatorAppTests/WindowChromeTests.swift
+++ b/Tests/CreatorAppTests/WindowChromeTests.swift
@@ -50,6 +50,7 @@ struct WindowChromeTests {
         let chrome = RecordingChrome()
         let sync = WindowChromeSync(model: app, chrome: chrome)
         sync.apply()
+        #expect(chrome.titleWrites == ["Untitled"], "the first apply wrote the title")
         let writes = (chrome.titleWrites.count, chrome.editedWrites.count, chrome.urlWrites.count)
         sync.apply()
         #expect((chrome.titleWrites.count, chrome.editedWrites.count, chrome.urlWrites.count) == writes)
```

- [ ] **Step 2: Run them**

Run: `swift test --filter CreatorAppTests`
Expected: all pass.

- [ ] **Step 3: Full suite and lint**

Run: `swift test 2>&1 | tee /tmp/full.txt; echo exit=$?` then `swiftlint lint --strict`
Expected: exit 0, no line says `recorded an issue` or `failed after`, 11 `Test run with` lines, **2183 tests (master + 41)**, no new build warnings (the `building for macOS-26.0, but linking with dylib` linker warnings are old), SwiftLint 0 violations.

- [ ] **Step 4: Commit**

```bash
git add Tests/CreatorAppTests/AppModelOpenURLTests.swift Tests/CreatorAppTests/GroupPickInstancesTests.swift Tests/CreatorAppTests/GroupViewportTests.swift Tests/CreatorAppTests/PaletteOverlayTests.swift Tests/CreatorAppTests/TitleBarClearanceTests.swift Tests/CreatorAppTests/WindowChromeTests.swift
git commit -m "followups-editor task 17: App test hardening (ED-17, app side)"
```

### Task 18: Errata and the CLAUDE.md sentence

**Why.** Where a fix changes documented behaviour: one new section `Errata (F: editor follow-ups)` appended to the end of the groups/comments spec (BUG-2, ED-2, ED-3, ED-4, ED-5, ED-6, ED-7, ED-8, ED-10, BUG-1, GK-13), and one clause in CLAUDE.md's named-undo paragraph for ED-18. Nothing else in docs changes.

**Files:**

- Modify: `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: Tasks 1 to 17 merged.
- Produces: Docs only.

- [ ] **Step 1: Make the doc edits**

Apply this patch (append the new section at the end of the spec; one clause in CLAUDE.md). Nothing else in `docs/` changes.

```diff
diff --git a/CLAUDE.md b/CLAUDE.md
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -52,7 +52,8 @@ Module boundaries (dependency order):
     call site. A coalesced run keeps its first record's name. Names have no numbers and never include text the person
     typed (a note, a group's or dimension's name); an input is named by its fixed label ("Change Width"), a node by its
     type ("Add Box"). The sketch editor (graph-free) gives each `SketchCommit` a fixed `name` from `SketchStepName`
-    ("Add Line", "Change Dimension", "Fillet"; `SketchEditorModel.commit` requires `named:`), which `AppModel.storeSketch`
+    ("Add Line", "Change Dimension", "Fillet"; `SketchEditorModel.commit` requires `named:`, `SketchCommit.init` and
+    `EditorModel.edit` require `name:`), which `AppModel.storeSketch`
     passes through `UndoName.sketch(_:)`; `SketchCommit.description` ("Rename d1 to Plate width") holds typed text and
     numbers and is never a name. `DocumentModel.undoName` and `redoName` feed `AppModel.undoTitle` and `redoTitle`, which
     the Edit menu (`AppCommands`) and the top bar (`TopBar`) show as "Undo <name>" and "Redo <name>" (plain "Undo"/"Redo"
diff --git a/docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md b/docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md
--- a/docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md
+++ b/docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md
@@ -360,3 +360,26 @@ User decisions (C2), all 15 of the plan's "User decisions" decided as the recomm
     the sketch opens second (`EditorModel+Pointer.swift`: `pairClick` after `click`). The sketcher-s5c owner must
     know before merging.
 15. Groups are not in the palette (Space), only in the library.
+
+## Errata (F: editor follow-ups)
+
+Plan `2026-10-10-followups-editor.md` (the final review's leftover editor and groups items).
+
+- §5 Make Unique: a name that already ends in a number counts on from it, so a copy of "Rib 2" is "Rib 3", not "Rib 2 2";
+  "Name" still gives "Name 2". (`GroupNaming.uniqueName`; only Make Unique is affected: ⌘G's "Group" has no number and a
+  paste that meets a taken name is named "<name> (imported)", which is never counted on.)
+- §5 Group: an input made from a wire into the selection keeps its target socket's access, optional, default, unit and
+  range, as the "+" drop does (C2 decision 4), so unwiring that source later leaves the part running on the default.
+- §6 "+" drop: an exposed output keeps its source socket's optional flag as well as its unit.
+- §6 Inspector: a refused name or socket edit shakes the node the field was typed for (`GroupPanel.node`), also when a
+  click away is what commits it.
+- §6 Library and palette: adding a key that names no registered type, or a group definition that is gone, adds nothing
+  and says "That node isn't in the library any more."
+- §6 "+": only Group Input's and Group Output's "+" is the expose socket; a Missing node's "+" is an ordinary socket.
+- §6 Breadcrumbs: only the crumb for the level just outside the one shown names ⌘↑ in its tooltip.
+- §3 Esc clears the selection only while the panel shows the canvas, like the other selection keys.
+- §6.2 (parent spec) Refusal caption: a successful edit clears it at once, and while it shows the canvas is one caption
+  line (`GraphPanelLayout.refusalLineHeight`) and the panel's spacing shorter, so a library drop on the caption adds
+  nothing. A comment menu item chosen mid-drag does nothing.
+- §4/§5 Undo and Redo replay without the new-definition and interface rules (`GraphContent.apply(_:registry:replaying:)`),
+  so a hand-edited file that already repeats a group name can still undo an Ungroup.
```

- [ ] **Step 2: Check nothing else moved**

Run: `git diff --stat` and confirm only those two files changed. `swift test` is unaffected (still 2183 tests).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md
git commit -m "followups-editor task 18: Errata and the CLAUDE.md sentence"
```

---

## Self-review

**Spec coverage.** Every item this track owns is either a task or a one-line drop in "What each owned item became": BUG-1, BUG-2, ED-2 to ED-13, ED-17, ED-18, GK-10 and GK-13. The parts of ED-7, ED-10 and ED-17 that are not bugs, are already covered, or cannot be strengthened are named with the evidence (the code, an existing test, or a mutation check). Where a fix changes documented behaviour the Errata section (Task 18) says so; the one CLAUDE.md sentence is the named-undo paragraph.

**Placeholder scan.** No step says "TBD", "similar to Task N" or "add appropriate handling": every code step is an exact patch taken from the commit that was built and tested, and every command shows its expected result. The `@@ -a,b +c,d @@` line numbers in the patches are positions in the verified tree, for orientation; apply the hunks in task order and `git apply` finds them by context.

**Type consistency.** `GroupPanel.node` (Task 1) is what the three view edits pass as `on:`; `clearRefusal()` (Task 5) is what Tasks 6 and 16 call in tests; `GraphPanelLayout.refusalLineHeight` and `showsRefusal` (Task 6) are used only by `canvasFrameInWindow`, `drawnCanvasRect` and `GraphPanel`; `EditorModel.edit(_:coalescingKey:name:)` with `name` required (Task 11) is called with a name by every source file and by the three test call sites the patch edits; `GraphContent.apply(_:registry:replaying:)` (Task 13) has one caller that passes `true` (`DocumentModel.replay`); `GraphContent.hasNode(atInstance:)` (Task 12) has one caller. `GroupCommandTests.addInputs` (Task 2) is a static on the test struct that Task 9's and Task 14's additions do not redefine.

**Review Focus.** Five inputs, five tests, each in the task that owns the code (Tasks 1, 2, 9, 11, 12). The two cases that cannot be tested headless (a wrapping refusal message; the real height of a caption line) are under "Dropped items and risks" and decision 5.

**Applying the plan.** Save each fenced `diff` block to a file and run `git apply --index file.patch`, or make the same edit by hand. Run the tasks in order: later patches assume the earlier ones. After Task 18 the tree equals the verified tree.

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-10-followups-editor.md`. Please review it, in particular the seven User decisions. Both execution approaches work: subagent-driven (a fresh implementer and reviewer per task) suits this plan because the tasks are independent of each other apart from the shared files they edit in order; the native approach is cheaper and the verified patches leave little to design.
