# Final-Review Follow-Ups: App, Viewport and Docs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the leftover final-review findings that belong to the app, viewport, packaging, themes and docs: ED-1, ED-15, ED-16, AV-1…AV-12 and DOC-1…DOC-7, and record the whole follow-ups round (three plans) in the roadmap, CLAUDE.md and the human checks.

**Architecture:** Ten small tasks, each one commit, each leaving the suite green. Behaviour fixes are test-first (the tests are written to fail on master `4dff87b` and do); performance items pin the new behaviour (a buffer is the same object next frame, a drag writes once) and are checked not to change what is drawn; script items are verified by running the scripts in a scratch copy. Nothing needs a new MetalUI API.

**Tech Stack:** Swift 6.4 (strict concurrency), Swift Testing, MetalUI (`../MetalUI`), Metal, OpenCascade shim, bash.

**Branch / base:** worktree `MetalCreator-fu-app`, branch `followups-app`, off master `4dff87b` (**2142 tests**, 11 “Test run with” lines).

**Spec:** the binding spec is `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` with all its Errata. The items come from the triage (`followups-triage.md`, which cites file:line on master `4dff87b`) and from these specs, as each item cites: `docs/superpowers/specs/2026-10-09-packaging-design.md` (AV-10), the themes Errata in the vertical-slice spec (AV-11: “Each change is saved at once”, and `ThemeStore`'s doc comments: “saved before it is shown”), and `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` (ED-1, GR-4).

## Global Constraints

Copied from `CLAUDE.md` and `.swiftlint.yml`; every task includes them.

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`: full Swift 6 strict concurrency; no `@unchecked Sendable` or `nonisolated(unsafe)` to silence a diagnostic.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest.
- `@MainActor @Observable` models; behaviour in models, thin views; one type per file; no force unwraps; no `DispatchQueue`; use `FormatStyle`, not `String(format:)` or `Formatter`; `Task.sleep(for:)`, never `Task.sleep(nanoseconds:)`.
- `swiftlint lint --strict` must report zero violations (comments are exempt from the 140-column line limit; a type body is capped at 250 lines).
- OCCT work only inside `OCCTKernel.serialized`; keep OCCT behind `Kernel`.
- MetalUI gaps go in `docs/metalui-gaps.md` (the entry and the summary table row) and are fixed in MetalUI, never worked around. **This plan finds none** (see “New MetalUI gaps”).
- A full `swift test` passes only if the exit code is 0, no line says “recorded an issue” or “failed after” (Swift Testing prints glyphs, not ✘), and 11 “Test run with” lines appear.
- Do not touch `Package.swift`'s MetalUI path; never modify `../MetalUI`.
- Performance figures not from a controlled run are marked as such; no number is invented (an idle benchmark re-run is pending and will replace them).

## Review Focus

Inputs and conditions the spec implies but the item list does not name, most likely first. Each has a test in the task that owns the code.

1. **Quit right after a colour drag.** A theme colour dragged and ⌘Q pressed within the 300 ms debounce must still be on disk after relaunch. → Task 7: `closingTheEditorSavesAtOnce`, `flushSavesAtOnceAndTheLaterWakeDoesNothing`; the window's close handler calls `flush()`. And a save that fails (folder replaced by a file) must put the last saved colour back and say why: `aFailedSaveShowsTheSavedColourAgainAndSaysWhy`.
2. **A file arrives while a question is on screen.** Finder opening a document while the Save / Don't Save or Discard question, or a failure alert, is up must not replace it, and Discard must open the file the question was about. → Task 1: `aFileThatArrivesWhileAProblemAlertIsUpLeavesTheAlertAlone`, `aFileThatArrivesWhileTheDiscardQuestionIsUpKeepsTheFirstQuestion`.
3. **A wired sketch plane that disappears or is mid-evaluation.** Editing the Plane node re-evaluates it (the sketch must wait, not alert); deleting the wire or a failing node says so once (a different sentence for each cause) and keeps the sketch open on its last plane. → Task 1: `theCameraLooksAtTheWiredPlaneAgainWhenItMoves` (`app.alert == nil` while it re-evaluates), `aPlaneThatLosesItsResultKeepsTheSketchOpenOnTheLastPlaneAndSaysSo`, `aPlaneWhoseWireIsRemovedKeepsTheSketchOpenOnTheLastPlaneAndSaysSoOnce`.
4. **Done or a click that outruns the level refresh.** Leaving a group and pressing Done in the same turn must not write at the wrong level or raise “node not found”. → Task 1: `PickLevelGuardTests`.
5. **Odd values from outside.** Arabic-Indic or fullwidth digits in `--info-plist`; NaN, minus infinity, zero and negative blend sizes (`Int(.nan)` traps); a theme file named `Dracula.mctheme` on a case-insensitive volume; a theme id with “/” or “..”; a checker that answers `.unchecked` every other call. → Tasks 5, 8, 7, 7, 8.

## File structure

New files (one type each, as `CLAUDE.md` asks): `Sources/CreatorViewport/Render/ViewportRenderer+Triad.swift` (the triad's cached buffer, split out of `ViewportRenderer.swift`, which is at the 250-line type-body limit); tests `PickLevelGuardTests`, `SketchPlaneFollowTests`, `HandleBisectorTests`, `ThemeColorDragTests` (CreatorAppTests), `RendererCacheTests`, `Support/GatedClock` (CreatorViewportTests), `DimensionLabelBranchTests` (CreatorSketchEditorTests), `ThemeColorPreviewTests` (CreatorStyleTests), `BlendSearchTests` (CreatorOCCTTests). Everything else is a change inside an existing file.

Responsibilities that move: the camera's reaction to a moved wired plane lives in `AppModel+Sketch.refreshSketch` (app glue, because it needs the document's results and the viewport); the colour-drag save policy lives in `ThemeEditorModel` (when to save) over `ThemeStore` (what is pending and how to restore).

## Files shared with the other two tracks

Merge order is editor, then kernel, then this track, so this track is the second side everywhere. Checked against the two plans on disk (`docs/superpowers/plans/2026-10-10-followups-editor.md` and `docs/superpowers/plans/2026-10-10-followups-kernel.md`) when this plan was revised. The side that merges second keeps both sides' changes in each file below.

| File | This track's change | Other track | Keep |
|---|---|---|---|
| `CLAUDE.md` | Task 10: DOC-1 split of one paragraph (the “Loft refuses profiles with holes.” line), a Project-state line, and sentences on picks, open-URL, the sketch plane, renderer buffers, theme colour drag, `--help` | editor (Task 18): one clause in the named-undo paragraph, near line 54. Kernel: edits nothing, but lists four sentences for this track (Task 10 Step 2 names them) | The editor's clause. The kernel's four sentences, applied by this track at merge time; the loft-line sentence merges with DOC-1's split (Step 2, item 1.2) |
| `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` | Task 10: three wording edits: the R 2.5 sentence (~line 523), the re-wrapped rule-3 bullet of Errata (naming: face picks) (~line 557), and a parenthesis on “Each change is saved at once” in Errata (Themes) (~line 583) | kernel (Task 12): one Errata bullet after the rule-6 bullet of Errata (naming: merged faces), a few lines above this track's R 2.5 hunk | Their bullet. If the two hunks collide, take both |
| `docs/superpowers/specs/2026-10-08-constraint-sketcher-design.md`, `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` | none | kernel adds a bullet at the end of Errata (S4); editor appends `Errata (F: editor follow-ups)` | their additions; this track does not edit these specs |
| `Tests/CreatorAppTests/AppModelOpenURLTests.swift` | Task 1: two tests appended to the struct | editor (Task 17): one comment line inside `nothingOpensWhileTheCloseQuestionIsUp` | the comment and the two new tests; the hunks are far apart |
| `Sources/CreatorEditor/GlassPanel.swift` | Task 10: one doc-comment sentence | none (the editor plan does not mention this file) | nothing to merge; the sentence is optional if the lines ever collide |

Files that look shared and are not: the blend files (`Sources/CreatorOCCT/OCCTKernel+Blend.swift`, `BlendGrid.swift` and their tests, Task 8) are in the kernel's module, but the kernel plan edits only `KernelError+Blend.swift` there (Task 6, the `Locale.messages` move), so there is no overlap; the earlier version of this table wrongly listed the kernel as editing them. `Sources/CreatorSketchEditor` and `Tests/CreatorSketchEditorTests`: Task 4 adds only a new test file (`DimensionLabelBranchTests`), while the kernel edits `SketchEditorModel+Project.swift` and the editor edits `SketchCommit.swift` and `SketchStepNameTests.swift`; new names only, no conflict. `docs/superpowers/roadmap.md`, `docs/verification/human-checks.md`, `docs/verification/performance.md`, `docs/metalui-gaps.md`: only this track edits them (neither other plan does). The kernel's `Locale.messages` rule applies to this track too: no new message here formats a number.

Editor-track files this plan deliberately does **not** touch although the triage lists a cosmetic wrap there: `EditorModel.swift`, `EditorModel+Nudge.swift`, `EditorModel+Pinch.swift`, `GraphCanvas.swift`, `Cursor.swift`, `Sources/CreatorGraph/Groups/GroupCommands+Ungroup.swift`. The editor plan does not take those wraps either (it touches `EditorModel.swift` only at `clearRefusal()`), so they stay open: see Risks.

---

## Items checked and dropped

Each re-verified against the code on master.

| Item | Why dropped |
|---|---|
| DOC-3 | Already fixed: `docs/superpowers/notes/2026-10-08-sketcher-s1-s2-handoff.md` first S4 bullet starts “(Done in S4: …)”. |
| DOC-4 (comments plan, “1752”) | Already says 1751 at both lines. |
| DOC-6 `FiftyNodeGraph.swift` “unused import Testing” | Used by `#_sourceLocation`; removing it fails the build. |
| DOC-6 `AppModel+Closing.swift:32-38` | No long or orphan line there. |
| DOC-6 editor/groups files | The editor track's files (see above). |
| AV-6 | Same finding and fix as AV-1. |
| AV-8 (a) | The `lessEqual` and `greater` depth draws partition the depth range, so no pixel is covered twice. (b) A guide uses two of the mesh's four edge-cache entries; clearing needs five distinct keys on one mesh in one frame. (c) Guides stay out of `sceneBounds` on purpose (Errata (M6)); `ViewportGuideTests` pins it. |
| AV-9 (d) second half, (e) second half | Needs a measurement (the idle re-run); a real `.invalid` is covered by the flange R3 tests. |
| AV-10 `describe` fallback | `String(describing:)` is the readable form for the errors the self-test meets. |
| AV-11 (b) duplicate names, (c), (d) | Harmless or deliberate (see Task 7). |
| AV-12 (a) | `BracketAcceptanceTests` pins the picks headless. |

---


## Tasks

All commands run from the repository root. The code in each task is the exact content that passed in the scratch copy: create files in full, apply `diff` blocks as patches (`git apply`, or edit by hand to the same result).

### Task 1: App guards: pick level, open-URL during an alert, sketch camera follows a wired plane (ED-1, ED-16, ED-15)

ED-1 (`finishPick` has no level guard), ED-16 (open-URL replaces a showing alert) and ED-15 (the camera does not follow a wired plane that moves). All three re-verified against master `4dff87b`: the code is as the triage describes.

Design notes. ED-1: `finishPick` now returns without writing when `session.level != editor.levelPath` (it still clears `pick`), and `viewportClicked` clears a stale pick instead of toggling an edge on it. ED-16: `openRequested` ignores the file while `alert != nil` (the close question is already covered by `closeRequest`). ED-15: `refreshSketch` re-looks at the plane when a *found* plane differs from the editor's; “lost” means the wired node is in `.error` or the wire is gone, not merely re-evaluating (an evaluating node would otherwise raise a false alert on every plane edit, which the first run of the test showed); the alert is said once, on the transition from having a plane to losing it, and it says which cause it was (`planeFailed`: the wired node has no result; `planeUnwired`: nothing is wired into “plane”, since saying that a node “has no result” when the wire is gone would be wrong). Surfacing the message in the sketch inspector instead needs a change in `CreatorSketchEditor` (the kernel track's module): see User decisions.

**Files:**
- Modify: `Sources/CreatorApp/AppModel+Picking.swift` (`finishPick`, `viewportClicked`)
- Modify: `Sources/CreatorApp/AppModel+OpenURL.swift` (`openRequested`)
- Modify: `Sources/CreatorApp/AppModel+Sketch.swift` (`refreshSketch`, new `planeLossMessage`, `planeFailed`, `planeUnwired`)
- Modify: `Sources/CreatorApp/SketchSession.swift` (`hasPlane`)
- Create: `Tests/CreatorAppTests/PickLevelGuardTests.swift`, `Tests/CreatorAppTests/SketchPlaneFollowTests.swift`
- Modify: `Tests/CreatorAppTests/AppModelOpenURLTests.swift`

**Interfaces:**
- Consumes: `PickSession.level`, `EditorModel.levelPath`, `EditorModel.goToLevel(_:)`, `ViewportModel.lookAt(_:framing:)`, `SketchEditorModel.framingBounds`.
- Produces: `SketchSession.hasPlane: Bool` (internal), `AppModel.planeFailed` and `AppModel.planeUnwired` (internal static strings). No signature changes.

- [ ] **Step 1: Write the tests**

**Modify `Tests/CreatorAppTests/AppModelOpenURLTests.swift`:**

```diff
--- a/Tests/CreatorAppTests/AppModelOpenURLTests.swift
+++ b/Tests/CreatorAppTests/AppModelOpenURLTests.swift
@@ -147,3 +147,31 @@ struct AppModelOpenURLTests {
         #expect(app.fileURL?.standardizedFileURL.path == url.standardizedFileURL.path)
     }
+
+    /// A problem alert is up: a file that arrives then must not replace it, or the question it may be hiding.
+    @Test func aFileThatArrivesWhileAProblemAlertIsUpLeavesTheAlertAlone() async throws {
+        let url = try boxFile("during-problem.mcgraph")
+        defer { try? FileManager.default.removeItem(at: url) }
+        let app = await makeApp()
+        let problem = AppAlert.problem(AppProblem("Something failed", "It did."))
+        app.alert = problem
+        app.openRequested(url)
+        #expect(app.alert == problem)
+        #expect(app.fileURL == nil, "nothing was opened behind the alert")
+    }
+
+    @Test func aFileThatArrivesWhileTheDiscardQuestionIsUpKeepsTheFirstQuestion() async throws {
+        let first = try boxFile("asked-first.mcgraph")
+        let second = try boxFile("asked-second.mcgraph")
+        defer {
+            try? FileManager.default.removeItem(at: first)
+            try? FileManager.default.removeItem(at: second)
+        }
+        let app = await makeApp()
+        try edit(app)
+        app.openRequested(first)
+        app.openRequested(second)
+        #expect(app.alert == .discardChanges)
+        await app.discardChanges()
+        #expect(app.fileURL == first, "Discard Changes opens the file the question was asked about")
+    }
 }
```

**Create `Tests/CreatorAppTests/PickLevelGuardTests.swift`:**

```swift
import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// A pick belongs to the level of the graph panel it began on (`PickSession.level`). `refreshScene` cancels it one
/// scheduled task after the level changes; Done and a viewport click that come first must not act on the wrong level.
@MainActor
struct PickLevelGuardTests {
    /// A group holding a box, its Edges by Tag rule and a Chamfer, entered, with a pick begun on the rule.
    func pickingInsideAGroup() async throws -> (app: AppModel, rule: Node) {
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
        app.beginPick(for: rule.id)
        await app.settle()
        try #require(app.pick != nil)
        return (app, rule)
    }

    @Test func doneAfterLeavingTheGroupWritesNothingAndRaisesNoAlert() async throws {
        let (app, _) = try await pickingInsideAGroup()
        app.viewportClicked(.edge(solid: 0, EdgeID(1)))
        let before = app.document.graph
        let canUndo = app.document.canUndo
        app.editor.goToLevel(0)
        app.finishPick()   // before the scheduled refresh has cancelled the pick
        #expect(app.pick == nil)
        #expect(app.alert == nil, "no “node not found” alert")
        #expect(app.document.graph == before && app.document.canUndo == canUndo)
    }

    @Test func aViewportClickAfterLeavingTheGroupEndsThePickWithoutChangingIt() async throws {
        let (app, _) = try await pickingInsideAGroup()
        app.editor.goToLevel(0)
        app.viewportClicked(.edge(solid: 0, EdgeID(1)))
        #expect(app.pick == nil)
    }

    @Test func doneOnTheLevelItBeganOnStillSavesThePicks() async throws {
        let (app, rule) = try await pickingInsideAGroup()
        app.viewportClicked(.edge(solid: 0, EdgeID(1)))
        app.finishPick()
        #expect(app.pick == nil && app.alert == nil)
        #expect(app.editor.selection == [rule.id])
        #expect(app.document.canUndo)
    }
}
```

**Create `Tests/CreatorAppTests/SketchPlaneFollowTests.swift`:**

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// A sketch drawn on a plane wired into its node follows that plane (sketcher spec §8): when the plane moves the
/// camera looks at it again, and when the plane loses its result the sketch stays open on the last plane and says so.
@MainActor
struct SketchPlaneFollowTests {
    /// A rectangle sketch on the wired XY Plane node, open in a 1400 × 900 viewport.
    func openOnWiredPlane() async throws -> (app: AppModel, plane: Node) {
        var sketch = rectangleSketch()
        sketch.plane = .wired
        var builder = GraphBuilder()
        let plane = builder.add(PlaneNode.self)
        let box = builder.sketchedBox(sketch)
        builder.wire(plane, "plane", to: box.sketch, "plane")
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.beginSketch(for: box.sketch.id)
        await app.settle()
        await app.viewport.waitForAnimation()
        try #require(app.sketch != nil)
        return (app, plane)
    }

    @Test func theCameraLooksAtTheWiredPlaneAgainWhenItMoves() async throws {
        let (app, plane) = try await openOnWiredPlane()
        let before = app.viewport.pose
        #expect(app.sketch?.editor.plane == .xy)
        try app.document.perform(.setInput(plane.id, "orientation", .integer(1)))   // XZ
        await app.settle()
        await app.viewport.waitForAnimation()
        #expect(app.sketch?.editor.plane == .xz)
        #expect(abs(app.viewport.pose.pitch - before.pitch) > 0.5, "the camera turned to face the new plane")
        #expect(app.viewport.pose.projection == .orthographic)
        #expect(app.alert == nil)
    }

    @Test func aPlaneThatDoesNotMoveLeavesTheCameraAlone() async throws {
        let (app, plane) = try await openOnWiredPlane()
        let before = app.viewport.pose
        try app.document.perform(.setInput(plane.id, "offset", .number(0)))
        await app.settle()
        #expect(app.viewport.pose == before && !app.viewport.isAnimating)
    }

    @Test func aPlaneThatLosesItsResultKeepsTheSketchOpenOnTheLastPlaneAndSaysSo() async throws {
        let (app, plane) = try await openOnWiredPlane()
        try app.document.perform(.setInput(plane.id, "orientation", .integer(7)))   // not one of XY, XZ, YZ
        await app.settle()
        #expect(app.sketch?.editor.plane == .xy, "the last plane stays")
        #expect(app.alert == .problem(AppProblem("The plane lost its result", AppModel.planeFailed)))
        app.alert = nil
        try app.document.perform(.setInput(plane.id, "offset", .number(5)))
        await app.settle()
        #expect(app.alert == nil, "said once, not on every refresh")
        try app.document.perform(.setInput(plane.id, "orientation", .integer(0)))
        await app.settle()
        #expect(app.sketch?.editor.plane == Plane.xy.offset(by: 5), "it follows the plane again once it evaluates")
    }

    /// The wire itself is deleted: no node is wired in, so the alert must not say a node has no result.
    @Test func aPlaneWhoseWireIsRemovedKeepsTheSketchOpenOnTheLastPlaneAndSaysSoOnce() async throws {
        let (app, plane) = try await openOnWiredPlane()
        let link = try #require(app.document.graph.links.first { $0.to.node == app.sketch?.node && $0.to.socket == "plane" })
        try app.document.perform(.disconnect(link))
        await app.settle()
        #expect(app.sketch?.editor.plane == .xy, "the last plane stays")
        #expect(app.alert == .problem(AppProblem("The plane lost its result", AppModel.planeUnwired)))
        app.alert = nil
        try app.document.perform(.setInput(plane.id, "offset", .number(5)))
        await app.settle()
        #expect(app.alert == nil, "said once")
    }
}
```


- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter "PickLevelGuardTests|SketchPlaneFollowTests|AppModelOpenURLTests"`

Expected failures before the change: `PickLevelGuardTests.doneAfterLeavingTheGroupWritesNothingAndRaisesNoAlert` (a “node not found” alert), `aViewportClickAfterLeavingTheGroupEndsThePickWithoutChangingIt` (pick still set), `AppModelOpenURLTests.aFileThatArrivesWhileAProblemAlertIsUpLeavesTheAlertAlone` and `aFileThatArrivesWhileTheDiscardQuestionIsUpKeepsTheFirstQuestion`, `SketchPlaneFollowTests.theCameraLooksAtTheWiredPlaneAgainWhenItMoves` (pitch unchanged), `aPlaneThatLosesItsResultKeepsTheSketchOpenOnTheLastPlaneAndSaysSo` (no alert) and `aPlaneWhoseWireIsRemovedKeepsTheSketchOpenOnTheLastPlaneAndSaysSoOnce` (no alert; the wire is removed with `.disconnect`, so it also pins that the message is the “nothing is wired” one). `aPlaneThatDoesNotMoveLeavesTheCameraAlone` and `doneOnTheLevelItBeganOnStillSavesThePicks` pass before and after (they guard against over-reaching).

- [ ] **Step 3: Make the change**

**Modify `Sources/CreatorApp/AppModel+OpenURL.swift`:**

```diff
--- a/Sources/CreatorApp/AppModel+OpenURL.swift
+++ b/Sources/CreatorApp/AppModel+OpenURL.swift
@@ -5,11 +5,12 @@ extension AppModel {
     /// and the path on `swift run MetalCreatorApp file.mcgraph`. MetalUI delivers it through `App.onOpenURL`.
     ///
-    /// A URL that isn't a file, the file that is already open, and any URL while the close question is up are
-    /// ignored. A typed but uncommitted inspector value counts as a change (it is committed first, as when closing).
-    /// With unsaved changes it asks the New and Open… question first (`alert`, then `discardChanges()`);
-    /// otherwise the file replaces the document, or an alert says why it couldn't be opened. Several files in one
-    /// drop arrive one at a time, so the last one stays open.
+    /// A URL that isn't a file, the file that is already open, and any URL while the close question or another alert
+    /// is up are ignored: the question on screen is not replaced. A typed but uncommitted inspector value counts as a
+    /// change (it is committed first, as when closing). With unsaved changes it asks the New and Open… question first
+    /// (`alert`, then `discardChanges()`); otherwise the file replaces the document, or an alert says why it couldn't be
+    /// opened. Several files in one drop arrive one at a time, so the last one stays open, unless an earlier one raised
+    /// an alert: the later ones are then ignored.
     public func openRequested(_ url: URL) {
-        guard url.isFileURL, closeRequest == .idle else { return }
+        guard url.isFileURL, closeRequest == .idle, alert == nil else { return }
         if let current = fileURL, current.standardizedFileURL == url.standardizedFileURL { return }
         editor.commitPendingEntry()
```

**Modify `Sources/CreatorApp/AppModel+Picking.swift`:**

```diff
--- a/Sources/CreatorApp/AppModel+Picking.swift
+++ b/Sources/CreatorApp/AppModel+Picking.swift
@@ -62,8 +62,11 @@ extension AppModel {
     }
 
-    /// Done: the picks go into the rule (or a new one), as one undo step, and the rule is selected.
+    /// Done: the picks go into the rule (or a new one), as one undo step, and the rule is selected. A pick whose level
+    /// is no longer the one shown is dropped without writing.
     public func finishPick() {
         guard let session = pick else { return }
         pick = nil
+        // The level changed and `refreshScene` hasn't cancelled the pick yet: its nodes belong to another graph.
+        guard session.level == editor.levelPath else { return }
         let picks = ConstantValue.edgePicks(session.solid.topology.picks(for: session.picked))
         do {
@@ -87,5 +90,10 @@ extension AppModel {
     /// A click in the viewport. While picking, a click on an edge of the picked solid adds or removes it.
     func viewportClicked(_ target: PickTarget?) {
-        guard var session = pick, case .edge(let index, let edge)? = target, viewport.items.indices.contains(index),
+        guard var session = pick else { return }
+        guard session.level == editor.levelPath else {
+            pick = nil
+            return
+        }
+        guard case .edge(let index, let edge)? = target, viewport.items.indices.contains(index),
               viewport.items[index].solid === session.solid else { return }
         session.toggle(edge)
```

**Modify `Sources/CreatorApp/AppModel+Sketch.swift`:**

```diff
--- a/Sources/CreatorApp/AppModel+Sketch.swift
+++ b/Sources/CreatorApp/AppModel+Sketch.swift
@@ -8,6 +8,8 @@ import CreatorSketchEditor
 import CreatorViewport
 
 extension AppModel {
+    static let planeFailed = "The node wired into “plane” has no result now, so the sketch stays on the plane it had."
+    static let planeUnwired = "Nothing is wired into “plane” now, so the sketch stays on the plane it had."
     static let noWiredPlane = "Its plane comes from the wire into “plane”, which has no result yet. Wire a plane that evaluates."
 
     /// "Edit sketch" (sketcher spec §8): opens the node's sketch in the viewport. The camera looks straight at its
@@ -84,9 +86,20 @@ extension AppModel {
         guard let node = document.graph.nodes[session.node], case .sketch(let stored)? = node.inputValues[NodeSetting.sketch] else {
             return finishSketch()
         }
-        let plane = sketchPlane(of: node, stored) ?? session.editor.plane
+        let found = sketchPlane(of: node, stored)
+        let plane = found ?? session.editor.plane
+        // A wired plane that moved: the camera looks at it again. One that lost its result (the wire's node failed)
+        // leaves the sketch on the last plane and says so once, when it is lost.
+        let moved = found != nil && plane != session.editor.plane
+        if found != nil {
+            session.hasPlane = true
+        } else if session.hasPlane, let message = planeLossMessage(of: node, stored) {
+            session.hasPlane = false
+            alert = .problem(AppProblem("The plane lost its result", message))
+        }
         let shown = shownSketch(of: node, stored)
         session.editor.reload(shown.sketch, plane: plane, wired: shown.wired)
+        if moved, let bounds = session.editor.framingBounds { viewport.lookAt(plane, framing: bounds) }
     }
 
     /// The sketch as the node evaluates it (sketcher spec §7): each exposed dimension takes the constant left under its
@@ -123,6 +136,17 @@ extension AppModel {
         }
     }
 
+    /// Why the plane wired into `node` is gone for good, or `nil` while it is not: its wire was removed, or its node
+    /// failed. A node that is only evaluating again (or not yet) isn't gone: the sketch waits for its result.
+    private func planeLossMessage(of node: Node, _ sketch: Sketch) -> String? {
+        guard case .wired = sketch.plane else { return nil }
+        guard let link = document.graph.incomingLink(to: Endpoint(node: node.id, socket: "plane")) else {
+            return Self.planeUnwired
+        }
+        if case .error? = document.results[link.from.node]?.state { return Self.planeFailed }
+        return nil
+    }
+
     /// The plane a Plane from Face makes, worked out from its picked face when the node itself hasn't evaluated: nothing
     /// downstream of a new sketch draws it yet. It needs the node's solid to have a result; `nil` otherwise.
     private func unevaluatedFacePlane(of id: NodeID) -> Plane? {
```

**Modify `Sources/CreatorApp/SketchSession.swift`:**

```diff
--- a/Sources/CreatorApp/SketchSession.swift
+++ b/Sources/CreatorApp/SketchSession.swift
@@ -15,4 +15,7 @@ public final class SketchSession {
     private var isFollowing = false
     private var refreshPending = false
+    /// Whether the node's plane had a result at the last refresh (a wired plane can lose it); the app says so once
+    /// when it is lost.
+    var hasPlane = false
 
     init(node: NodeID, editor: SketchEditorModel, viewport: ViewportModel) {
```


- [ ] **Step 4: Run the new tests**

Run: `swift test --filter "PickLevelGuardTests|SketchPlaneFollowTests|AppModelOpenURLTests"`
Expected: all pass.

- [ ] **Step 5: The whole suite, warnings and lint**

```bash
swift build --build-tests 2>&1 | grep 'warning:' | grep -v 'which was built for newer version' | sort -u
swift test 2>&1 | tee /tmp/test.log | grep -E 'recorded an issue|failed after|Test run with'
swiftlint lint --strict | tail -1
```

Expected: no new warning (master has two, both from `ContextMenuTests.swift:140`, `'underPointer' mutated after capture`); exit code 0, no line saying "recorded an issue" or "failed after", 11 "Test run with" lines, **master + 9 = **2151****; `Found 0 violations`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix: drop a pick after its level changed, ignore files during an alert, follow a moved wired sketch plane"
```


---

### Task 2: Viewport input and labels: handle labels track the size, scroll/pinch stop a mid-gesture animation, pinned debounce and cursor tests (AV-1, AV-6, AV-7)

AV-1 (handle labels read the untracked `viewSize`; AV-6 is the same finding, merged) and AV-7. `triadLabels()` does not read the size (its layout is fixed to the widget), so only `handleLabels()` changes. For AV-7(a), `stopAnimation()` is a no-op without an animation, so it is simply called on every scroll and pinch event; `scrollStartPose` is still captured only on the gesture's first event.

**Files:**
- Modify: `Sources/CreatorViewport/Model/ViewportModel+Labels.swift` (`handleLabels`)
- Modify: `Sources/CreatorViewport/Model/ViewportModel+Scroll.swift` (`zoomScrolling`), `ViewportModel+Pinch.swift` (`pinchChanged`)
- Create: `Tests/CreatorViewportTests/Support/GatedClock.swift`
- Modify: `Tests/CreatorViewportTests/ViewSizeObservationTests.swift`, `ScrollZoomTests.swift`, `PinchZoomTests.swift`, `CursorTests.swift`, `ViewportInputTests.swift`

**Interfaces:**
- Consumes: `ViewportModel.observedViewSize`, `stopAnimation()`, `ViewportClock`.
- Produces: `GatedClock` (test support): `time`, `now()`, `sleep(for:)` (lasts until `time` passes its deadline or the task is cancelled), `advance(by:) async`.

- [ ] **Step 1: Write the tests**

**Modify `Tests/CreatorViewportTests/CursorTests.swift`:**

```diff
--- a/Tests/CreatorViewportTests/CursorTests.swift
+++ b/Tests/CreatorViewportTests/CursorTests.swift
@@ -1,3 +1,4 @@
 import CreatorGeometry
+import Foundation
 import MetalUI
 import Testing
@@ -60,3 +61,31 @@ struct CursorTests {
         #expect(ViewportCursor.grabbing.pointerStyle == .grabActive)
     }
+
+    /// The view cube's drag is its own mode: it orbits like a drag in the view, but a click on it picks a region.
+    @Test func aDragFromTheCubeIsTheCubeModeAndAHandCursor() {
+        let model = makeModel()
+        let from = model.cubeLayout.center
+        model.dragChanged(from: from, to: from + ScreenPoint(10, 0), modifiers: [], button: .primary)
+        #expect(model.activeDragMode == .cube)
+        #expect(model.cursor == .grabbing)
+        model.dragEnded(from: from, at: from + ScreenPoint(10, 0), modifiers: [], button: .primary)
+        #expect(model.activeDragMode == nil && model.cursor == nil)
+    }
+
+    /// A handle's knob drag edits the handle: it keeps the arrow (or the crosshair while picking).
+    @Test func aHandleDragKeepsTheArrow() {
+        let pose = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0,
+                              projection: .orthographic)
+        let model = ViewportModel(kernel: StubMeshKernel(), pose: pose, clock: ManualClock())
+        model.viewSize = ViewportSize(width: 400, height: 300)
+        model.showHandles([ViewportHandle(id: "extrude", anchor: .zero, direction: .unitZ, value: 10, range: 0...100,
+                                          style: .linear, tint: .solid),
+        ])
+        // 40 mm tall in 300 points: the knob at z = 10 is 75 points above the centre.
+        model.dragChanged(from: ScreenPoint(200, 75), to: ScreenPoint(200, 60), modifiers: [], button: .primary)
+        #expect(model.activeDragMode == .handle("extrude"))
+        #expect(model.cursor == nil)
+        model.isPicking = true
+        #expect(model.cursor == .crosshair)
+    }
 }
```

**Modify `Tests/CreatorViewportTests/PinchZoomTests.swift`:**

```diff
--- a/Tests/CreatorViewportTests/PinchZoomTests.swift
+++ b/Tests/CreatorViewportTests/PinchZoomTests.swift
@@ -73,3 +73,14 @@ struct PinchZoomTests {
         #expect(!model.isAnimating)
     }
+
+    /// F, an arrow or a cube click during a pinch starts an animation; the next pinch event takes over from what is
+    /// shown instead of letting the animation finish over it.
+    @Test func aPinchEventStopsAnAnimationStartedMidPinch() {
+        let (model, _) = makeModel()
+        model.pinchChanged(magnification: 1.5, centre: centre)
+        model.perform(.view(.top))
+        #expect(model.isAnimating)
+        model.pinchChanged(magnification: 1.6, centre: centre)
+        #expect(!model.isAnimating, "the pinch's pose is shown, not the old interpolation")
+    }
 }
```

**Modify `Tests/CreatorViewportTests/ScrollZoomTests.swift`:**

```diff
--- a/Tests/CreatorViewportTests/ScrollZoomTests.swift
+++ b/Tests/CreatorViewportTests/ScrollZoomTests.swift
@@ -103,3 +103,32 @@ struct ScrollZoomTests {
         #expect(!model.isAnimating)
     }
+
+    /// The wheel's debounce (spec §7.3): each step restarts the wait, so a settle comes `wheelSettleDelay` after the
+    /// last step and not before. Needs a clock whose sleeps last (`ManualClock`'s return at once).
+    @Test func theWheelSettlesOnlyOnceItHasBeenStillForTheWholeDelay() async {
+        let clock = GatedClock()
+        let model = ViewportModel(kernel: StubMeshKernel(), pose: start, clock: clock)
+        model.viewSize = size
+        var settled: [CameraPose] = []
+        model.events.cameraSettled = { settled.append($0) }
+        let delay = ViewportInputMap.wheelSettleDelay
+        model.scrolled(by: 10, at: cursor, phase: .step)
+        await clock.advance(by: delay * 0.6)
+        model.scrolled(by: 10, at: cursor, phase: .step)
+        await clock.advance(by: delay * 0.6)
+        #expect(settled.isEmpty, "the first step's wait ran out, but the second step restarted it")
+        await clock.advance(by: delay * 0.6)
+        #expect(settled == [model.pose], "settled once, after the wheel was still for the whole delay")
+    }
+
+    /// F, an arrow or a cube click during a scroll starts an animation; the next scroll event takes over from what
+    /// is shown, as a drag does, instead of letting the animation finish over it.
+    @Test func aScrollEventStopsAnAnimationStartedMidScroll() {
+        let (model, _) = makeModel()
+        model.scrolled(by: 10, at: cursor, phase: .moving)
+        model.perform(.view(.top))
+        #expect(model.isAnimating)
+        model.scrolled(by: 10, at: cursor, phase: .moving)
+        #expect(!model.isAnimating, "the scroll's pose is shown, not the old interpolation")
+    }
 }
```

**Create `Tests/CreatorViewportTests/Support/GatedClock.swift`:**

```swift
// Test fixture file: a clock whose sleeps last until the test moves time past their deadline.
@testable import CreatorViewport

/// Starts at 100 s. `sleep(for:)` suspends until `time` reaches the moment it was asked at plus the delay, or the
/// task is cancelled, so a test can pin a debounce: advance short of the delay and nothing fires; advance past it and
/// it does. (`ManualClock`'s sleeps return at once, so a debounce can't be told from none.)
@MainActor
final class GatedClock: ViewportClock {
    var time = 100.0

    func now() -> Double { time }

    func sleep(for seconds: Double) async {
        let deadline = time + seconds
        while time < deadline, !Task.isCancelled { await Task.yield() }
    }

    /// Lets the sleeps already asked for begin (they read the time when they start), moves time on, and lets the tasks
    /// it wakes run.
    func advance(by seconds: Double) async {
        await settle()
        time += seconds
        await settle()
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}
```

**Modify `Tests/CreatorViewportTests/ViewSizeObservationTests.swift`:**

```diff
--- a/Tests/CreatorViewportTests/ViewSizeObservationTests.swift
+++ b/Tests/CreatorViewportTests/ViewSizeObservationTests.swift
@@ -1,3 +1,5 @@
+import CreatorGeometry
 import CreatorKernel
+import Foundation
 import Observation
 import Testing
@@ -42,3 +44,21 @@ struct ViewSizeObservationTests {
         #expect(model.viewSizeChanges == changes)
     }
+
+    /// The handle labels read the size through `observedViewSize` as the overlay labels do. A saved camera shows the
+    /// handles on the first build, before any draw has recorded the size: that build must be rebuilt once it is.
+    @Test func handleLabelsAreRebuiltWhenTheDrawRecordsTheFirstSize() async {
+        let front = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0,
+                               projection: .orthographic)
+        let model = ViewportModel(kernel: FakeKernel(), pose: front)
+        model.showHandles([ViewportHandle(id: "r", anchor: .zero, direction: .unitZ, value: 3, range: 0...10,
+                                          style: .radial, tint: .feature),
+        ])
+        let observer = Observer()
+        withObservationTracking { _ = model.handleLabels() } onChange: { MainActor.assumeIsolated { observer.changes += 1 } }
+        #expect(model.handleLabels().isEmpty, "no size yet")
+        model.recordViewSize(ViewportSize(width: 400, height: 300))
+        await model.sizeChangeTask?.value
+        #expect(observer.changes == 1, "the first build is invalidated by the size")
+        #expect(model.handleLabels().map(\.text) == ["R 3 mm"])
+    }
 }
```

**Modify `Tests/CreatorViewportTests/ViewportInputTests.swift`:**

```diff
--- a/Tests/CreatorViewportTests/ViewportInputTests.swift
+++ b/Tests/CreatorViewportTests/ViewportInputTests.swift
@@ -113,4 +113,9 @@ struct ViewportInputTests {
         #expect(clicks == 0)
         #expect(handleReports == 0, "a click on a knob changes nothing")
+        // The counter is wired: dragging the same knob does report.
+        model.pointerDown(at: ScreenPoint(200, 75), modifiers: [])
+        model.pointerDragged(to: ScreenPoint(200, 45))
+        model.pointerUp(at: ScreenPoint(200, 45))
+        #expect(handleReports > 0)
     }
 
```


- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter "ScrollZoomTests|PinchZoomTests|ViewSizeObservationTests|CursorTests|ViewportInputTests"`

Expected failures before the change: `handleLabelsAreRebuiltWhenTheDrawRecordsTheFirstSize` (`observer.changes == 0`: `handleLabels` read the untracked `viewSize`), `aScrollEventStopsAnAnimationStartedMidScroll` and `aPinchEventStopsAnAnimationStartedMidPinch` (`isAnimating` stays true). The rest are pinning tests that pass before and after, as AV-7(b) and (c) ask: `theWheelSettlesOnlyOnceItHasBeenStillForTheWholeDelay` was mutation-checked in the scratch copy (removing `wheelSettleTask?.cancel()`, removing the `!Task.isCancelled` guard, or a zero delay each fail it at `settled.isEmpty`); the two cursor tests and the extra drag in `aClickOnAHandleKnobOrTheCubeReportsNoPick` make the old assertions able to fail.

- [ ] **Step 3: Make the change**

**Modify `Sources/CreatorViewport/Model/ViewportModel+Labels.swift`:**

```diff
--- a/Sources/CreatorViewport/Model/ViewportModel+Labels.swift
+++ b/Sources/CreatorViewport/Model/ViewportModel+Labels.swift
@@ -12,9 +12,11 @@ extension ViewportModel {
     }
 
-    /// Each handle's value beside its knob (spec §6.5), in viewport points. "R 3 mm" for a radial handle.
+    /// Each handle's value beside its knob (spec §6.5), in viewport points. "R 3 mm" for a radial handle. The size is
+    /// read through `observedViewSize`, so labels built before the first draw recorded it are rebuilt after it.
     public func handleLabels() -> [ViewportLabel] {
-        guard !viewSize.isEmpty, !isAnimating else { return [] }
+        let size = observedViewSize
+        guard !size.isEmpty, !isAnimating else { return [] }
         return handles.compactMap { handle in
-            guard let knob = CameraMath.project(handle.knob, pose, size: viewSize)?.point else { return nil }
+            guard let knob = CameraMath.project(handle.knob, pose, size: size)?.point else { return nil }
             let amount = handle.value.formatted(.number.precision(.fractionLength(0...2)))
             let text = handle.style == .radial ? "R \(amount) mm" : "\(amount) mm"
```

**Modify `Sources/CreatorViewport/Model/ViewportModel+Pinch.swift`:**

```diff
--- a/Sources/CreatorViewport/Model/ViewportModel+Pinch.swift
+++ b/Sources/CreatorViewport/Model/ViewportModel+Pinch.swift
@@ -11,8 +11,6 @@ extension ViewportModel {
         guard magnification.isFinite else { return }
         if let start = pinchStart, start.centre != centre { pinchEnded() }
-        if pinchStart == nil {
-            stopAnimation()
-            pinchStart = PinchStart(pose: pose, centre: centre)
-        }
+        stopAnimation()   // also one started mid-pinch by F, an arrow or the cube
+        if pinchStart == nil { pinchStart = PinchStart(pose: pose, centre: centre) }
         guard let start = pinchStart else { return }
         let factor = max(magnification, ViewportInputMap.minimumMagnification)
```

**Modify `Sources/CreatorViewport/Model/ViewportModel+Scroll.swift`:**

```diff
--- a/Sources/CreatorViewport/Model/ViewportModel+Scroll.swift
+++ b/Sources/CreatorViewport/Model/ViewportModel+Scroll.swift
@@ -33,11 +33,9 @@ extension ViewportModel {
     }
 
-    /// One scroll event's zoom, without settling. The scroll's first event stops an animation and keeps the camera
-    /// it began with.
+    /// One scroll event's zoom, without settling. Every event stops an animation (one started mid-scroll by F, an arrow
+    /// or the cube, which would otherwise finish over the zoom); the scroll's first event keeps the camera it began with.
     private func zoomScrolling(by factor: Double, toward point: ScreenPoint) {
-        if scrollStartPose == nil {
-            stopAnimation()
-            scrollStartPose = pose
-        }
+        stopAnimation()
+        if scrollStartPose == nil { scrollStartPose = pose }
         apply(CameraNavigation.zoom(pose, factor: factor, toward: point, size: viewSize))
         refreshToolPointer(at: point)
```


- [ ] **Step 4: Run the new tests**

Run: `swift test --filter "ScrollZoomTests|PinchZoomTests|ViewSizeObservationTests|CursorTests|ViewportInputTests"`
Expected: all pass.

- [ ] **Step 5: The whole suite, warnings and lint**

```bash
swift build --build-tests 2>&1 | grep 'warning:' | grep -v 'which was built for newer version' | sort -u
swift test 2>&1 | tee /tmp/test.log | grep -E 'recorded an issue|failed after|Test run with'
swiftlint lint --strict | tail -1
```

Expected: no new warning (master has two, both from `ContextMenuTests.swift:140`, `'underPointer' mutated after capture`); exit code 0, no line saying "recorded an issue" or "failed after", 11 "Test run with" lines, **master + 15 = **2157****; `Found 0 violations`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix: handle labels follow the observed view size; scroll and pinch stop a mid-gesture animation; pin wheel debounce and cursors"
```


---

### Task 3: Renderer buffer reuse: triad, overlay and region fills (AV-2, AV-3, AV-4)

AV-2 (a triad buffer per frame), AV-3 (the overlay key held the pose) and AV-4 (a stale fill buffer). What is drawn must not change: the overlay instances are a pure function of `(overlay, grid extent, dash zoom if any line is dashed, scale, palette)`, so the key holds exactly those. The grid extent is the camera's whole effect on the grid lines (its centre snapped to a major line, and its reach), so an orbit, or a pan inside one major cell, reuses the buffer; a zoom changes the reach and the dash zoom and rebuilds it. `ViewportRenderer`'s body is at SwiftLint's 250-line limit, hence the triad cache lives in `ViewportRenderer+Triad.swift`.

**Files:**
- Create: `Sources/CreatorViewport/Render/ViewportRenderer+Triad.swift`
- Modify: `Sources/CreatorViewport/Render/ViewportRenderer.swift` (`triadBuffer`, `drawTriad`, doc), `ViewportRenderer+Overlay.swift`, `OverlayBufferKey.swift`, `OverlayGeometry.swift`
- Create: `Tests/CreatorViewportTests/RendererCacheTests.swift`

**Interfaces:**
- Produces: `ViewportRenderer.triadBuffer: (scale: Float, palette: ViewportPalette, buffer: any MTLBuffer, count: Int)?`; `ViewportRenderer.triadInstances(scale:palette:)`; `OverlayGeometry.GridExtent` (`plane`, `spacing`, `centreX`, `centreY`, `reach`); `OverlayGeometry.gridExtent(on:pose:size:spacing:) -> GridExtent?`; `OverlayGeometry.gridLines(_ grid: GridExtent)`; `OverlayGeometry.instances(_:grid:millimetresPerPoint:scale:palette:)`. The existing `instances(_:pose:size:gridSpacing:scale:palette:)` and `gridLines(on:pose:size:spacing:)` keep their signatures (they call the new ones), so `OverlayTests` is untouched.
- `OverlayBufferKey` is now `(overlay, grid: GridExtent?, dashZoom: Double?, scale, palette)`.

- [ ] **Step 1: Write the tests**

**Create `Tests/CreatorViewportTests/RendererCacheTests.swift`:**

```swift
import CreatorGeometry
import Foundation
import Metal
import Testing
@testable import CreatorViewport

/// The renderer keeps the GPU buffers a frame of a continuous orbit, pan or zoom would otherwise allocate again
/// (spec §7.3's 60 fps; `ViewCubeResources` makes the same promise for the cube): the triad's, the overlay's and the
/// region fills'. A cached buffer is the very same object on the next frame; what is drawn doesn't change.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct RendererCacheTests {
    static let front = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0,
                                  projection: .orthographic)
    static let size = ViewportSize(width: 200, height: 200)

    /// A renderer and a 400 × 400 (2 pixels per point) target to draw into.
    @MainActor
    struct Rig {
        let renderer: ViewportRenderer
        let target: any MTLTexture
        let queue: any MTLCommandQueue

        init() throws {
            let device = try #require(MTLCreateSystemDefaultDevice())
            renderer = try ViewportRenderer(device: device)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 400, height: 400,
                                                                      mipmapped: false)
            descriptor.usage = .renderTarget
            descriptor.storageMode = .shared
            target = try #require(device.makeTexture(descriptor: descriptor))
            queue = try #require(device.makeCommandQueue())
        }

        /// Draws `frame` and returns the target's BGRA bytes.
        @discardableResult
        func draw(_ frame: ViewportFrame) throws -> [UInt8] {
            let commandBuffer = try #require(queue.makeCommandBuffer())
            renderer.encode(frame, into: target, scale: 2, commandBuffer: commandBuffer)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            var bytes = [UInt8](repeating: 0, count: 400 * 400 * 4)
            target.getBytes(&bytes, bytesPerRow: 400 * 4, from: MTLRegionMake2D(0, 0, 400, 400), mipmapLevel: 0)
            return bytes
        }
    }

    func frame(pose: CameraPose = front, overlay: ViewportOverlay = ViewportOverlay()) -> ViewportFrame {
        ViewportFrame(pose: pose, size: Self.size, sceneBounds: nil, items: [], shading: .shadedEdges, gridSpacing: 10,
                      handles: [], cube: ViewCubeLayout(), hoveredCubeRegion: nil, triad: TriadLayout(), overlay: overlay)
    }

    /// A sketch's overlay: the plane grid, a dashed line and a point.
    var sketch: ViewportOverlay {
        ViewportOverlay(lines: [OverlayLine(.zero, Vector3(10, 0, 10), tint: .construction, isDashed: true)],
                        points: [OverlayPoint(Vector3(10, 0, 10), tint: .fullyConstrained)], gridPlane: .xz)
    }

    func turned(_ pose: CameraPose, by yaw: Double) -> CameraPose {
        var turned = pose
        turned.yaw += yaw
        return turned
    }

    // MARK: - The triad (AV-2)

    @Test func theTriadBufferIsMadeOnceAndSurvivesAnOrbit() throws {
        let rig = try Rig()
        try rig.draw(frame())
        let first = try #require(rig.renderer.triadBuffer)
        try rig.draw(frame(pose: turned(Self.front, by: 0.3)))
        try rig.draw(frame(pose: turned(Self.front, by: 0.6)))
        let later = try #require(rig.renderer.triadBuffer)
        #expect(later.buffer === first.buffer, "an orbit turns the widget's camera, not its instances")
    }

    @Test func theTriadBufferIsRebuiltForANewPalette() throws {
        let rig = try Rig()
        try rig.draw(frame())
        let first = try #require(rig.renderer.triadBuffer)
        var other = frame()
        other.palette = ViewportPalette(.alucard)
        try rig.draw(other)
        #expect(try #require(rig.renderer.triadBuffer).buffer !== first.buffer)
    }

    // MARK: - The overlay (AV-3)

    @Test func theOverlayBufferSurvivesAnOrbitOfTheCamera() throws {
        let rig = try Rig()
        try rig.draw(frame(overlay: sketch))
        let first = try #require(rig.renderer.overlayBuffer)
        try rig.draw(frame(pose: turned(Self.front, by: 0.2), overlay: sketch))
        #expect(try #require(rig.renderer.overlayBuffer).buffer === first.buffer,
                "the grid reach and the dashes depend on the zoom and on where the grid is centred, not on the angle")
    }

    @Test func aPanWithinAGridCellKeepsTheOverlayBufferAndAZoomRebuildsIt() throws {
        let rig = try Rig()
        try rig.draw(frame(overlay: sketch))
        let first = try #require(rig.renderer.overlayBuffer)
        var panned = Self.front
        panned.target = Vector3(1, 0, 16)   // the grid is centred on the nearest major line (100 mm apart here)
        try rig.draw(frame(pose: panned, overlay: sketch))
        #expect(try #require(rig.renderer.overlayBuffer).buffer === first.buffer)
        var zoomed = Self.front
        zoomed.distance *= 2
        try rig.draw(frame(pose: zoomed, overlay: sketch))
        #expect(try #require(rig.renderer.overlayBuffer).buffer !== first.buffer, "dashes and reach follow the zoom")
    }

    /// The cache changes what is allocated, not what is drawn: a renderer that reused its buffers draws the same pixels
    /// as a new one.
    @Test func aReusedOverlayDrawsThePixelsAFreshRendererDoes() throws {
        let reused = try Rig()
        try reused.draw(frame(overlay: sketch))
        let moved = frame(pose: turned(Self.front, by: 0.2), overlay: sketch)
        let fromReused = try reused.draw(moved)
        let fromFresh = try Rig().draw(moved)
        #expect(fromReused == fromFresh)
    }

    // MARK: - The fills (AV-4)

    @Test func theFillBufferIsReusedThenReleasedWhenTheFillsGoAway() throws {
        let rig = try Rig()
        let fill = OverlayFill(vertices: [Vector3(-6, 0, 9), Vector3(6, 0, 9), Vector3(0, 0, 21)])
        let overlay = ViewportOverlay(fills: [fill])
        try rig.draw(frame(overlay: overlay))
        let first = try #require(rig.renderer.fillBuffer)
        try rig.draw(frame(overlay: overlay))
        #expect(try #require(rig.renderer.fillBuffer).buffer === first.buffer, "the same fills reuse the buffer")
        try rig.draw(frame())
        #expect(rig.renderer.fillBuffer == nil, "leaving sketch mode frees it")
    }
}
```


- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter "RendererCacheTests|OverlayTests|OffscreenRenderTests"`

`RendererCacheTests` does not compile before the change (`triadBuffer` is new). With that one property stubbed as `nil`, `theOverlayBufferSurvivesAnOrbitOfTheCamera`, `aPanWithinAGridCellKeepsTheOverlayBufferAndAZoomRebuildsIt` (the key held the pose) and `theFillBufferIsReusedThenReleasedWhenTheFillsGoAway` (`fillBuffer` kept) fail; `aReusedOverlayDrawsThePixelsAFreshRendererDoes` passes before and after and is what proves the change draws the same pixels. The suite is skipped without a Metal device.

- [ ] **Step 3: Make the change**

**Modify `Sources/CreatorViewport/Render/OverlayBufferKey.swift`:**

```diff
--- a/Sources/CreatorViewport/Render/OverlayBufferKey.swift
+++ b/Sources/CreatorViewport/Render/OverlayBufferKey.swift
@@ -1,11 +1,12 @@
 import CreatorGeometry
 
-/// What the renderer's overlay buffer is built from: the overlay, and the camera and scale its dashes and plane
-/// grid depend on.
+/// What the renderer's overlay buffer is built from: the overlay, the scale and palette, and from the camera only what
+/// the instances depend on, so an orbit or a pan inside a grid cell doesn't rebuild them.
 struct OverlayBufferKey: Equatable {
     var overlay: ViewportOverlay
-    var pose: CameraPose
-    var size: ViewportSize
-    var gridSpacing: Double
+    /// Where the plane grid is centred and how far it reaches; `nil` without a grid plane.
+    var grid: OverlayGeometry.GridExtent?
+    /// The millimetres a point covers, which dashes are cut at; `nil` when no line is dashed.
+    var dashZoom: Double?
     var scale: Float
     var palette: ViewportPalette
```

**Modify `Sources/CreatorViewport/Render/OverlayGeometry.swift`:**

```diff
--- a/Sources/CreatorViewport/Render/OverlayGeometry.swift
+++ b/Sources/CreatorViewport/Render/OverlayGeometry.swift
@@ -14,10 +14,26 @@ enum OverlayGeometry {
     static let majorGridWidth = 1.25
 
+    /// Where the plane grid is centred and how far it reaches: everything of the camera the grid lines depend on.
+    struct GridExtent: Equatable {
+        var plane: Plane
+        var spacing: Double
+        var centreX: Double
+        var centreY: Double
+        var reach: Double
+    }
+
     static func instances(_ overlay: ViewportOverlay, pose: CameraPose, size: ViewportSize, gridSpacing: Double,
                           scale: Float, palette: ViewportPalette) -> [LineInstance] {
+        let grid = overlay.gridPlane.flatMap { gridExtent(on: $0, pose: pose, size: size, spacing: gridSpacing) }
+        return instances(overlay, grid: grid, millimetresPerPoint: CameraMath.millimetresPerPoint(pose, size: size),
+                         scale: scale, palette: palette)
+    }
+
+    /// The instances for a camera already reduced to what they depend on (`gridExtent`, and the zoom the dashes use).
+    static func instances(_ overlay: ViewportOverlay, grid: GridExtent?, millimetresPerPoint: Double, scale: Float,
+                          palette: ViewportPalette) -> [LineInstance] {
         var instances: [LineInstance] = []
-        let millimetresPerPoint = CameraMath.millimetresPerPoint(pose, size: size)
-        if let plane = overlay.gridPlane {
-            for line in gridLines(on: plane, pose: pose, size: size, spacing: gridSpacing) {
+        if let grid {
+            for line in gridLines(grid) {
                 let color = line.major ? palette.gridMajor : palette.gridMinor
                 let width = Float(line.major ? majorGridWidth : gridWidth) * scale
@@ -70,10 +86,21 @@ enum OverlayGeometry {
     static func gridLines(on plane: Plane, pose: CameraPose, size: ViewportSize,
                           spacing: Double) -> [(a: Vector3, b: Vector3, major: Bool)] {
-        guard spacing.isFinite, spacing > 0, !size.isEmpty else { return [] }
+        gridExtent(on: plane, pose: pose, size: size, spacing: spacing).map(gridLines) ?? []
+    }
+
+    /// The grid's centre (snapped to a major line) and reach for this camera; `nil` for a degenerate spacing or size.
+    static func gridExtent(on plane: Plane, pose: CameraPose, size: ViewportSize, spacing: Double) -> GridExtent? {
+        guard spacing.isFinite, spacing > 0, !size.isEmpty else { return nil }
         let offset = pose.target - plane.origin
         let major = spacing * 10
-        let centreX = (offset.dot(plane.xAxis) / major).rounded() * major
-        let centreY = (offset.dot(plane.yAxis) / major).rounded() * major
-        let reach = (pose.visibleHeight * max(size.aspect, 1) / spacing).rounded(.up) * spacing + major
+        return GridExtent(plane: plane, spacing: spacing,
+                          centreX: (offset.dot(plane.xAxis) / major).rounded() * major,
+                          centreY: (offset.dot(plane.yAxis) / major).rounded() * major,
+                          reach: (pose.visibleHeight * max(size.aspect, 1) / spacing).rounded(.up) * spacing + major)
+    }
+
+    static func gridLines(_ grid: GridExtent) -> [(a: Vector3, b: Vector3, major: Bool)] {
+        let (plane, spacing, centreX, centreY, reach) = (grid.plane, grid.spacing, grid.centreX, grid.centreY, grid.reach)
+        let major = spacing * 10
         let count = Int(reach / spacing)
         var lines: [(a: Vector3, b: Vector3, major: Bool)] = []
```

**Modify `Sources/CreatorViewport/Render/ViewportRenderer+Overlay.swift`:**

```diff
--- a/Sources/CreatorViewport/Render/ViewportRenderer+Overlay.swift
+++ b/Sources/CreatorViewport/Render/ViewportRenderer+Overlay.swift
@@ -22,5 +22,8 @@ extension ViewportRenderer {
     /// The frame's fill triangles in its palette, kept until the fills or the palette change.
     func fillVertices(for frame: ViewportFrame) -> (buffer: any MTLBuffer, count: Int)? {
-        guard !frame.overlay.fills.isEmpty else { return nil }
+        guard !frame.overlay.fills.isEmpty else {
+            fillBuffer = nil
+            return nil
+        }
         let key = FillBufferKey(fills: frame.overlay.fills, palette: frame.palette)
         if let cached = fillBuffer, cached.key == key { return (cached.buffer, cached.count) }
@@ -34,12 +37,18 @@ extension ViewportRenderer {
     }
 
-    /// The frame's overlay in its palette, kept until the overlay, the camera, the scale or the palette change.
+    /// The frame's overlay in its palette, kept until what the instances are built from changes: the overlay, the scale,
+    /// the palette, and the camera only as far as it reaches them (where the plane grid is centred and how far it
+    /// reaches, and the zoom the dashes are cut at). An orbit, or a pan inside one grid cell, reuses the buffer.
     func overlayInstances(for frame: ViewportFrame, scale: Float) -> (buffer: any MTLBuffer, count: Int)? {
         guard !frame.overlay.isEmpty else { return nil }
-        let key = OverlayBufferKey(overlay: frame.overlay, pose: frame.pose, size: frame.size, gridSpacing: frame.gridSpacing,
-                                   scale: scale, palette: frame.palette)
+        let grid = frame.overlay.gridPlane.flatMap {
+            OverlayGeometry.gridExtent(on: $0, pose: frame.pose, size: frame.size, spacing: frame.gridSpacing)
+        }
+        let dashZoom = frame.overlay.lines.contains(where: \.isDashed)
+            ? CameraMath.millimetresPerPoint(frame.pose, size: frame.size) : nil
+        let key = OverlayBufferKey(overlay: frame.overlay, grid: grid, dashZoom: dashZoom, scale: scale, palette: frame.palette)
         if let cached = overlayBuffer, cached.key == key { return (cached.buffer, cached.count) }
-        let instances = OverlayGeometry.instances(frame.overlay, pose: frame.pose, size: frame.size,
-                                                  gridSpacing: frame.gridSpacing, scale: scale, palette: frame.palette)
+        let instances = OverlayGeometry.instances(frame.overlay, grid: grid, millimetresPerPoint: dashZoom ?? 1, scale: scale,
+                                                  palette: frame.palette)
         guard let buffer = GPUBuffers.make(device, instances) else {
             overlayBuffer = nil
```

**Create `Sources/CreatorViewport/Render/ViewportRenderer+Triad.swift`:**

```swift
import Metal

extension ViewportRenderer {
    /// The triad's instances in GPU memory, kept until the scale or the palette change.
    func triadInstances(scale: Float, palette: ViewportPalette) -> (buffer: any MTLBuffer, count: Int)? {
        if let cached = triadBuffer, cached.scale == scale, cached.palette == palette { return (cached.buffer, cached.count) }
        let instances = GPUGeometry.triadInstances(scale: scale, palette: palette)
        guard let buffer = GPUBuffers.make(device, instances) else {
            triadBuffer = nil
            return nil
        }
        triadBuffer = (scale, palette, buffer, instances.count)
        return (buffer, instances.count)
    }
}
```

**Modify `Sources/CreatorViewport/Render/ViewportRenderer.swift`:**

```diff
--- a/Sources/CreatorViewport/Render/ViewportRenderer.swift
+++ b/Sources/CreatorViewport/Render/ViewportRenderer.swift
@@ -23,6 +23,8 @@ final class ViewportRenderer {
     /// The overlay's instances, kept until what they're built from changes (dashes and the plane grid follow the zoom).
     var overlayBuffer: (key: OverlayBufferKey, buffer: any MTLBuffer, count: Int)?
-    /// The overlay's fill triangles, kept until the fills or the palette change.
+    /// The overlay's fill triangles, kept until the fills or the palette change, and dropped once a frame has none.
     var fillBuffer: (key: FillBufferKey, buffer: any MTLBuffer, count: Int)?
+    /// The triad's instances, which depend only on the pixel scale and the palette: an orbit turns the widget's camera.
+    var triadBuffer: (scale: Float, palette: ViewportPalette, buffer: any MTLBuffer, count: Int)?
     private let cube: ViewCubeResources
     /// The palette `handleBuffer` was built in.
@@ -258,12 +260,11 @@ final class ViewportRenderer {
         let y = origin.y * scale
         let side = triad.side * scale
-        let instances = GPUGeometry.triadInstances(scale: Float(scale), palette: frame.palette)
         guard x >= 0, y >= 0, x + side <= Double(width), y + side <= Double(height),
-              let buffer = GPUBuffers.make(device, instances) else { return }
+              let lines = triadInstances(scale: Float(scale), palette: frame.palette) else { return }
         encoder.setViewport(MTLViewport(originX: x, originY: y, width: side, height: side, znear: 0, zfar: 1))
         let uniforms = GPUGeometry.frameUniforms(triad.widgetPose(frame.pose),
                                                  size: ViewportSize(width: triad.side, height: triad.side), sceneRadius: 2,
                                                  pixelWidth: Int(side), pixelHeight: Int(side))
-        drawLines(buffer, count: instances.count, uniforms, depth: pipelines.depthAlways, style: Self.plainLines, encoder)
+        drawLines(lines.buffer, count: lines.count, uniforms, depth: pipelines.depthAlways, style: Self.plainLines, encoder)
     }
 
```


- [ ] **Step 4: Run the new tests**

Run: `swift test --filter "RendererCacheTests|OverlayTests|OffscreenRenderTests"`
Expected: all pass.

- [ ] **Step 5: The whole suite, warnings and lint**

```bash
swift build --build-tests 2>&1 | grep 'warning:' | grep -v 'which was built for newer version' | sort -u
swift test 2>&1 | tee /tmp/test.log | grep -E 'recorded an issue|failed after|Test run with'
swiftlint lint --strict | tail -1
```

Expected: no new warning (master has two, both from `ContextMenuTests.swift:140`, `'underPointer' mutated after capture`); exit code 0, no line saying "recorded an issue" or "failed after", 11 "Test run with" lines, **master + 21 = **2163****; `Found 0 violations`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "perf: reuse the triad and overlay GPU buffers across camera moves; free the fill buffer when the fills go"
```


---

### Task 4: Sketch dimension label branches and the handle bisector (AV-5, AV-12)

AV-5 and the useful part of AV-12. The suspended-projection, parallel-lines, coincident-points and mismatched-kind branches of `SketchDimensionLabels` are tested through the editor's overlay (the public path), plus a 40-dimension test for “not capped”. AV-12(a) (`AppAcceptanceTests` and “picks still land on the intended edges”) is dropped: `BracketAcceptanceTests` pins the counts headless, as the triage itself says. The bisector arithmetic is extracted unchanged so two normals can be tested; a normal sum of zero still hides the handle without a message, and the doc comment now says so.

**Files:**
- Modify: `Sources/CreatorApp/HandleBuilder.swift` (extract `bisector(of:)`)
- Create: `Tests/CreatorSketchEditorTests/DimensionLabelBranchTests.swift`, `Tests/CreatorAppTests/HandleBisectorTests.swift`

**Interfaces:**
- Produces: `HandleBuilder.bisector(of normals: [Vector3]) -> Vector3?` (internal static): the normalised sum, `nil` when it is zero.

- [ ] **Step 1: Write the tests**

**Create `Tests/CreatorAppTests/HandleBisectorTests.swift`:**

```swift
import CreatorGeometry
import Testing
@testable import CreatorApp

/// A radial handle points along the bisector of the (up to two) faces at its edge, away from the part (spec §6.5).
/// `HandleTests` only reaches the one-face case (FakeKernel's side faces have no normal), so the sum of two normals is
/// pinned here.
struct HandleBisectorTests {
    @Test func aSingleNormalIsTheDirection() {
        #expect(HandleBuilder.bisector(of: [.unitZ]) == .unitZ)
        #expect(HandleBuilder.bisector(of: [Vector3(0, 0, 3)]) == .unitZ, "normalised")
    }

    @Test func twoFacesAtARightAngleGiveTheDiagonalBetweenThem() throws {
        let direction = try #require(HandleBuilder.bisector(of: [.unitX, .unitZ]))
        let root = 0.5.squareRoot()
        #expect((direction - Vector3(root, 0, root)).length < 1e-12)
    }

    @Test func aFlatEdgeBetweenTwoCoplanarFacesPointsAlongTheirNormal() {
        #expect(HandleBuilder.bisector(of: [.unitY, .unitY]) == .unitY)
    }

    /// A thin wall folded flat: the normals cancel, so no direction exists and the handle is not shown (it says nothing
    /// about why, which is the right amount for a case that only a degenerate part reaches).
    @Test func opposingNormalsGiveNoDirection() {
        #expect(HandleBuilder.bisector(of: [.unitX, -.unitX]) == nil)
        #expect(HandleBuilder.bisector(of: []) == nil, "a face without a normal contributes nothing")
    }
}
```

**Create `Tests/CreatorSketchEditorTests/DimensionLabelBranchTests.swift`:**

```swift
import CreatorGeometry
import CreatorSketch
import CreatorViewport
import Testing
@testable import CreatorSketchEditor

/// The branches of the dimension labels (sketcher spec §8) that `DimensionLabelTests` leaves out: a suspended
/// projection, parallel angle lines, coincident points (the `up` fallback) and a dimension whose entities don't fit
/// its kind. A label that can't be placed is left out; it never reaches the screen at a made-up spot.
@MainActor
struct DimensionLabelBranchTests {
    func labels(_ sketch: Sketch) -> [OverlayLabel] {
        SketchEditorModel(sketch: sketch, plane: .xy).overlay.labels
    }

    func near(_ a: Vector3?, _ b: Vector3) -> Bool {
        guard let a else { return false }
        return (a - b).length < 1e-9
    }

    /// A projected line from (0, 0) to (30, 0), suspended or not, with a point at (10, 10).
    func projected(suspended: Bool) -> (sketch: Sketch, line: SketchEntityID, point: SketchEntityID) {
        var sketch = Sketch()
        let source = ProjectionSource(reference: "edge1", curve: .line(Vector2(0, 0), Vector2(30, 0)), isSuspended: suspended)
        let line = sketch.add(SketchEntity(.projected(source)))
        let point = sketch.addPoint(Vector2(10, 10))
        return (sketch, line, point)
    }

    @Test func aDistanceToAProjectedLineIsLabelledUnlessTheProjectionIsSuspended() throws {
        var live = projected(suspended: false)
        live.sketch.addDimension(.distance(live.point, live.line), value: 10)
        #expect(labels(live.sketch).map(\.text) == ["10 mm"])
        var suspended = projected(suspended: true)
        suspended.sketch.addDimension(.distance(suspended.point, suspended.line), value: 10)
        #expect(labels(suspended.sketch).isEmpty, "a suspended projection has no geometry to anchor the label on")
    }

    @Test func twoParallelLinesAnchorTheAngleAtTheirCentreAndStandOffUp() throws {
        var sketch = Sketch()
        let first = sketch.addLine(Vector2(0, 0), Vector2(10, 0))
        let second = sketch.addLine(Vector2(0, 10), Vector2(10, 10))
        sketch.addDimension(.angle(first, second), value: 0)
        let found = try #require(labels(sketch).first)
        #expect(near(found.position, Vector3(5, 5, 0)), "no corner: the middle of the four ends")
        #expect(found.nudge == Vector3(0, 1, 0), "the two middles are opposite each other, so the bisector is nothing: up")
    }

    @Test func coincidentPointsStandTheirDistanceLabelOffUp() throws {
        var sketch = Sketch()
        let a = sketch.addPoint(Vector2(4, 4))
        let b = sketch.addPoint(Vector2(4, 4))
        sketch.addDimension(.distance(a, b), value: 0)
        let found = try #require(labels(sketch).first)
        #expect(near(found.position, Vector3(4, 4, 0)))
        #expect(found.nudge == Vector3(0, 1, 0), "no direction between them: up")
    }

    @Test func aDegenerateLineStandsItsLengthLabelOffUp() throws {
        var sketch = Sketch()
        let line = sketch.addLine(Vector2(2, 2), Vector2(2, 2))
        sketch.addDimension(.length(line), value: 0)
        #expect(try #require(labels(sketch).first).nudge == Vector3(0, 1, 0))
    }

    @Test func aDimensionWhoseEntitiesDontFitItsKindHasNoLabel() {
        var sketch = Sketch()
        let point = sketch.addPoint(.zero)
        let other = sketch.addPoint(Vector2(5, 0))
        let line = sketch.addLine(Vector2(0, 10), Vector2(10, 10))
        let circle = sketch.addCircle(center: Vector2(30, 5), radius: 3)
        let kinds: [DimensionKind] = [
            .length(point),         // a length needs a line
            .radius(line),          // a radius needs an arc or a circle
            .diameter(point),
            .distance(line, circle),   // a distance takes points, or a point and a line
            .distance(circle, point),
            .angle(point, other),   // an angle takes two lines
            .angle(line, point),
        ]
        for kind in kinds { sketch.addDimension(kind, value: 1) }
        #expect(labels(sketch).isEmpty)
    }

    /// Labels are neither capped nor culled by count here (the viewport drops those off screen): every dimension that
    /// can be placed has one.
    @Test func everyPlaceableDimensionHasALabel() {
        var sketch = Sketch()
        for index in 0..<40 {
            let line = sketch.addLine(Vector2(Double(index), 0), Vector2(Double(index), 5))
            sketch.addDimension(.length(line), value: 5)
        }
        #expect(labels(sketch).count == 40)
    }
}
```


- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter "HandleBisectorTests|HandleTests|DimensionLabelBranchTests"`

`HandleBisectorTests` does not compile before (the function is new). `DimensionLabelBranchTests` pins branches that already behave correctly, so it passes before and after; it exists for coverage (AV-5), and the file is new so it cannot conflict with the kernel/sketch track's edits to `DimensionLabelTests`.

- [ ] **Step 3: Make the change**

**Modify `Sources/CreatorApp/HandleBuilder.swift`:**

```diff
--- a/Sources/CreatorApp/HandleBuilder.swift
+++ b/Sources/CreatorApp/HandleBuilder.swift
@@ -70,8 +70,15 @@ public enum HandleBuilder {
               let edge = set.edges.first.flatMap(set.solid.topology.edge) else { return nil }
         let normals = edge.faces.compactMap { set.solid.topology.face($0)?.normal }
-        guard let bisector = normals.reduce(Vector3.zero, +).normalized else { return nil }
+        guard let bisector = bisector(of: normals) else { return nil }
         return (edge.midpoint, bisector, 1)
     }
 
+    /// The unit direction a radial handle points along: the normalised sum of the normals of the faces at its edge.
+    /// A face that isn't planar contributes its axis (`Face.normal`). Normals that cancel (or none) give `nil`, and the
+    /// handle is then left out without a message: only a degenerate part reaches it.
+    static func bisector(of normals: [Vector3]) -> Vector3? {
+        normals.reduce(Vector3.zero, +).normalized
+    }
+
     /// The first item the link into `node.socket` carries, from its upstream node's current result.
     static func upstream(_ node: Node, _ socket: SocketName, graph: Graph, results: [NodeID: NodeResult]) -> Scalar? {
```


- [ ] **Step 4: Run the new tests**

Run: `swift test --filter "HandleBisectorTests|HandleTests|DimensionLabelBranchTests"`
Expected: all pass.

- [ ] **Step 5: The whole suite, warnings and lint**

```bash
swift build --build-tests 2>&1 | grep 'warning:' | grep -v 'which was built for newer version' | sort -u
swift test 2>&1 | tee /tmp/test.log | grep -E 'recorded an issue|failed after|Test run with'
swiftlint lint --strict | tail -1
```

Expected: no new warning (master has two, both from `ContextMenuTests.swift:140`, `'underPointer' mutated after capture`); exit code 0, no line saying "recorded an issue" or "failed after", 11 "Test run with" lines, **master + 31 = **2173****; `Found 0 violations`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "test: cover the dimension label branches and the radial handle bisector"
```


---

### Task 5: Launch command and self-test edges, uncaught top-level errors (AV-10, Swift part)

AV-10's Swift part. `main.swift` is untestable glue (an executable target with top-level code): its two uncaught `try`s (the one the triage names, `--info-plist`, and `runApp`, which throws when `App()` cannot start) now print a sentence on stderr and exit 1; they are checked by running `.build/debug/MetalCreatorApp --help`, `--info-plist ٢٦` (exit 64) and `--info-plist 26.0` by hand (done in the scratch copy). Dropped from AV-10: `SelfTest.describe`'s `String(describing:)` fallback is the readable form for the errors the self-test meets (`Failure`, `AppError`), and `localizedDescription` would hide a `Failure`'s own text. Extra arguments after a file: pinned as ignored (see User decisions).

**Files:**
- Modify: `Sources/CreatorApp/LaunchCommand.swift`, `Sources/MetalCreatorApp/main.swift`
- Modify: `Tests/CreatorAppTests/LaunchCommandTests.swift`, `Tests/CreatorAppTests/SelfTestTests.swift`

**Interfaces:**
- Produces: `LaunchCommand.help` (a new case: print `usage`, exit 0). `usage` now also lists `--help`. `main.swift` gets `fail(_:_:) -> Never`.

- [ ] **Step 1: Write the tests**

**Modify `Tests/CreatorAppTests/LaunchCommandTests.swift`:**

```diff
--- a/Tests/CreatorAppTests/LaunchCommandTests.swift
+++ b/Tests/CreatorAppTests/LaunchCommandTests.swift
@@ -37,3 +37,21 @@ struct LaunchCommandTests {
         #expect(LaunchCommand(arguments: arguments) == .run(path: nil))
     }
+
+    /// `\d` matches any script's digits; a macOS version is ASCII ("٢٦" is Arabic-Indic 26, "２６" fullwidth).
+    @Test(arguments: ["٢٦", "２６", "26.٠"])
+    func infoPlistTakesOnlyASCIIDigits(_ version: String) {
+        #expect(LaunchCommand(arguments: ["--info-plist", version]) == .usageError("--info-plist takes one macOS version, like 26.0."))
+    }
+
+    @Test func helpPrintsTheUsageInsteadOfBeingAnUnknownOption() {
+        #expect(LaunchCommand(arguments: ["--help"]) == .help)
+        #expect(LaunchCommand(arguments: ["--help", "x"]) == .usageError("--help takes no value."))
+        #expect(LaunchCommand.usage.contains("--help") && LaunchCommand.usage.contains("--self-test"))
+    }
+
+    /// Only the first file is opened; later arguments (Xcode appends its own after the file) are not files.
+    @Test func argumentsAfterTheFileAreIgnored() {
+        #expect(LaunchCommand(arguments: ["a.mcgraph", "b.mcgraph"]) == .run(path: "a.mcgraph"))
+        #expect(LaunchCommand(arguments: ["a.mcgraph", "-NSDocumentRevisionsDebugMode", "YES"]) == .run(path: "a.mcgraph"))
+    }
 }
```

**Modify `Tests/CreatorAppTests/SelfTestTests.swift`:**

```diff
--- a/Tests/CreatorAppTests/SelfTestTests.swift
+++ b/Tests/CreatorAppTests/SelfTestTests.swift
@@ -18,10 +18,12 @@ struct SelfTestTests {
     }
 
-    @Test func aFailingCheckIsReportedInWordsAndFailsTheRun() async {
+    @Test func aFailingCheckIsReportedInWordsFailsTheRunAndStillRemovesTheScratchFolder() async {
         struct NoBundle: Error, CustomStringConvertible {
             var description: String { "no shader bundle" }
         }
-        let report = await SelfTest.run(kernel: FakeKernel(), scratch: Self.scratch()) { throw NoBundle() }
+        let scratch = Self.scratch()
+        let report = await SelfTest.run(kernel: FakeKernel(), scratch: scratch) { throw NoBundle() }
         #expect(!report.passed)
+        #expect(!FileManager.default.fileExists(atPath: scratch.path))
         #expect(report.results == [
             SelfTestResult(name: "kernel", passed: true, detail: "a 10 mm cube, 1000 mm³, meshed into 12 triangles"),
@@ -39,4 +41,18 @@ struct SelfTestTests {
     }
 
+    /// The scratch folder can't be made when something that is not a folder is in the way: that is a failed check of its
+    /// own, and the exports (which have nowhere to write) fail beside it instead of the run stopping.
+    @Test func ifTheScratchFolderCantBeMadeThatIsReportedAndTheRestStillRuns() async throws {
+        let blocker = Self.scratch()
+        try Data("in the way".utf8).write(to: blocker)
+        defer { try? FileManager.default.removeItem(at: blocker) }
+        let report = await SelfTest.run(kernel: FakeKernel(), scratch: blocker.appending(path: "inside")) { }
+        #expect(report.results.map(\.name) == ["kernel", "scratch folder", "STEP export", "STL export", "shaders"])
+        #expect(!report.passed)
+        let scratch = try #require(report.results.first { $0.name == "scratch folder" })
+        #expect(!scratch.passed && !scratch.detail.isEmpty)
+        #expect(report.results.first?.passed == true && report.results.last?.passed == true)
+    }
+
     @Test func aReportWithNoChecksHasNotPassed() {
         #expect(!SelfTestReport(results: []).passed)
```


- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter "LaunchCommandTests|SelfTestTests"`

Expected failures before the change: `infoPlistTakesOnlyASCIIDigits` (all 3 arguments: `\d` matches Arabic-Indic and fullwidth digits; verified in the scratch copy by putting `\d` back), `helpPrintsTheUsageInsteadOfBeingAnUnknownOption` (does not compile: no `.help`). `argumentsAfterTheFileAreIgnored` and the two `SelfTestTests` additions are pins that pass before and after.

- [ ] **Step 3: Make the change**

**Modify `Sources/CreatorApp/LaunchCommand.swift`:**

```diff
--- a/Sources/CreatorApp/LaunchCommand.swift
+++ b/Sources/CreatorApp/LaunchCommand.swift
@@ -3,9 +3,12 @@
 /// can use the packaged binary headlessly.
 public enum LaunchCommand: Equatable, Sendable {
-    /// Open the window, and the `.mcgraph` file at `path` if one is named. The file is handed to the app as Finder
-    /// would (`App.open`, then `AppModel.openRequested(_:)`), so it gets the same unsaved-changes check.
+    /// Open the window, and the `.mcgraph` file at `path` if one is named (the first argument; any after it are
+    /// ignored). The file is handed to the app as Finder would (`App.open`, then `AppModel.openRequested(_:)`), so it
+    /// gets the same unsaved-changes check.
     case run(path: String?)
     /// `--version`: print ``AppBundleInfo/versionLine``.
     case version
+    /// `--help`: print ``usage`` and exit 0.
+    case help
     /// `--self-test`: run ``SelfTest`` and exit 0 when every check passes, 1 otherwise.
     case selfTest
@@ -15,7 +18,8 @@ public enum LaunchCommand: Equatable, Sendable {
     case usageError(String)
 
-    /// The flags, as `--help` would list them.
+    /// The flags, as `--help` lists them.
     public static let usage = """
         usage: MetalCreator [file.mcgraph]
+               MetalCreator --help
                MetalCreator --version
                MetalCreator --self-test
@@ -31,8 +35,10 @@ public enum LaunchCommand: Equatable, Sendable {
         case "--version":
             self = arguments.count == 1 ? .version : .usageError("--version takes no value.")
+        case "--help":
+            self = arguments.count == 1 ? .help : .usageError("--help takes no value.")
         case "--self-test":
             self = arguments.count == 1 ? .selfTest : .usageError("--self-test takes no value.")
         case "--info-plist":
-            guard arguments.count == 2, let minimum = arguments.last, minimum.wholeMatch(of: /\d+(\.\d+){0,2}/) != nil else {
+            guard arguments.count == 2, let minimum = arguments.last, minimum.wholeMatch(of: /[0-9]+(\.[0-9]+){0,2}/) != nil else {
                 self = .usageError("--info-plist takes one macOS version, like 26.0.")
                 return
```

**Modify `Sources/MetalCreatorApp/main.swift`:**

```diff
--- a/Sources/MetalCreatorApp/main.swift
+++ b/Sources/MetalCreatorApp/main.swift
@@ -61,13 +61,29 @@ func printError(_ text: String) {
 }
 
+/// Prints why a launch step failed and exits 1, in place of the crash report an uncaught top-level error makes.
+func fail(_ action: String, _ error: any Error) -> Never {
+    printError("\(action): \(error.localizedDescription)")
+    exit(1)
+}
+
 switch LaunchCommand(arguments: Array(CommandLine.arguments.dropFirst())) {
 case .run(let path):
-    try runApp(opening: path)
+    do {
+        try runApp(opening: path)
+    } catch {
+        fail("MetalCreator couldn't start", error)
+    }
 case .version:
     print(AppBundleInfo.versionLine)
+case .help:
+    print(LaunchCommand.usage)
 case .selfTest:
     runSelfTest()
 case .infoPlist(let minimum):
-    FileHandle.standardOutput.write(try AppBundleInfo.infoPlistData(minimumSystemVersion: minimum))
+    do {
+        FileHandle.standardOutput.write(try AppBundleInfo.infoPlistData(minimumSystemVersion: minimum))
+    } catch {
+        fail("The Info.plist couldn't be written", error)
+    }
 case .usageError(let message):
     printError(message + "\n" + LaunchCommand.usage)
```


- [ ] **Step 4: Run the new tests**

Run: `swift test --filter "LaunchCommandTests|SelfTestTests"`
Expected: all pass.

- [ ] **Step 5: The whole suite, warnings and lint**

```bash
swift build --build-tests 2>&1 | grep 'warning:' | grep -v 'which was built for newer version' | sort -u
swift test 2>&1 | tee /tmp/test.log | grep -E 'recorded an issue|failed after|Test run with'
swiftlint lint --strict | tail -1
```

Expected: no new warning (master has two, both from `ContextMenuTests.swift:140`, `'underPointer' mutated after capture`); exit code 0, no line saying "recorded an issue" or "failed after", 11 "Test run with" lines, **master + 35 = **2177****; `Found 0 violations`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix: launch command takes ASCII digits and --help; report top-level launch errors"
```


---

### Task 6: Packaging scripts: failures visible, no word-splitting, a same-volume swap that never leaves the destination empty, all relative install names checked (AV-10, scripts)

Four fixes from AV-10. (1) `linked_libraries`/`rpaths` output goes to a file before the `while read` loops (`$WORK/links`, `$WORK/rpaths`, `$WORK/kegs`), because a failure inside `< <(…)` is invisible to `set -e`; the one remaining process substitution, in `resolve()`, ends in `fail "can't find …"` when `otool` yields nothing, so it is already visible. (2) The licence loop reads kegs with `while IFS= read -r`, so a path with a space no longer splits. (3) The finished app is copied (`ditto`) to `$DIST/.MetalCreator.app.staging`, verified *there*, then swapped in with two same-volume renames: the old app is moved aside to `$DIST/.MetalCreator.app.old`, the staged one is moved into place, and the old one is deleted; if the second rename fails the old app is put back. (This is not one atomic operation: a crash between the two renames leaves `.MetalCreator.app.old` and no `MetalCreator.app`, and the next run deletes the leftover. The earlier `rm -rf` followed by `mv` left no app at all in that window.) The trap removes the staging folder on failure. (4) `verify-app.sh` resolves `@loader_path/` and `@executable_path/` as well as `@rpath/`.

**Files:**
- Modify: `scripts/package-app.sh`, `scripts/verify-app.sh`

**Interfaces:**
- None. `scripts/package-app.sh` and `scripts/verify-app.sh` keep their usage and exit codes. `PackagingScriptTests` (parse + executable) is unchanged.

- [ ] **Step 1: Make the change**

**Modify `scripts/package-app.sh`:**

```diff
--- a/scripts/package-app.sh
+++ b/scripts/package-app.sh
@@ -2,8 +2,8 @@
 # Builds dist/MetalCreator.app: a release build of MetalCreatorApp with the OpenCascade libraries it links (and theirs,
 # from Homebrew) copied into Contents/Frameworks and re-pointed there, MetalUI's resource bundles in Contents/Resources,
 # an Info.plist written by the app itself (`--info-plist`), signed inside-out, then checked by scripts/verify-app.sh.
-# The app is assembled in a temporary folder and replaces dist/MetalCreator.app only once it has passed, so a failed
-# run leaves the previous app alone.
+# The app is assembled in a temporary folder, copied next to dist/MetalCreator.app and checked there, and replaces it only
+# once it has passed, so a failed run leaves the previous app alone.
 # Design: docs/superpowers/specs/2026-10-09-packaging-design.md.
 #
 # usage: scripts/package-app.sh
@@ -17,7 +17,9 @@ ROOT="$(cd "$(dirname "$0")/.." && pwd)"
 DIST="${METALCREATOR_DIST_DIR:-$ROOT/dist}"
 IDENTITY="${METALCREATOR_SIGN_IDENTITY:--}"
 WORK="$(mktemp -d)"
-trap 'rm -rf "$WORK"' EXIT
+# The finished app is staged beside its destination, so the last step is a rename on one volume.
+STAGE="$DIST/.MetalCreator.app.staging"
+trap 'rm -rf "$WORK" "$STAGE"' EXIT   # (.old is removed once the new app is in place)
 APP="$WORK/MetalCreator.app"
 CONTENTS="$APP/Contents"
 FRAMEWORKS="$CONTENTS/Frameworks"
@@ -82,6 +84,8 @@ printf '%s\n' "$BINARY" > "$WORK/queue"
 while [ -s "$WORK/queue" ]; do
     file="$(head -n 1 "$WORK/queue")"
     sed -i '' '1d' "$WORK/queue"
+    # Into a file first: a failure of otool inside a process substitution would go unseen by `set -e`.
+    linked_libraries "$file" > "$WORK/links"
     while IFS= read -r name; do
         is_system "$name" && continue
         library="$(basename "$name")"
@@ -96,14 +100,15 @@ while [ -s "$WORK/queue" ]; do
         cp "$real" "$FRAMEWORKS/$library"
         chmod u+w "$FRAMEWORKS/$library"
         printf '%s\n' "$source" >> "$WORK/queue"
-    done < <(linked_libraries "$file")
+    done < "$WORK/links"
 done
 printf '    %s libraries\n' "$(wc -l < "$WORK/seen" | tr -d ' ')"
 
 step "Copying their licences into Contents/Resources/Licenses"
 # Each library comes from a Homebrew keg, <prefix>/Cellar/<formula>/<version>; its licence files sit at the keg's top
 # level or in share/doc/<formula>.
-for keg in $(awk '{ print $2 }' "$WORK/seen" | sed -nE 's#^(.*/Cellar/[^/]+/[^/]+)/.*#\1#p' | sort -u); do
+awk '{ print $2 }' "$WORK/seen" | sed -nE 's#^(.*/Cellar/[^/]+/[^/]+)/.*#\1#p' | sort -u > "$WORK/kegs"
+while IFS= read -r keg; do
     formula="$(basename "$(dirname "$keg")")"
     mkdir -p "$CONTENTS/Resources/Licenses/$formula"
     find "$keg" "$keg/share/doc/$formula" -maxdepth 1 -type f \
@@ -111,7 +116,7 @@ for keg in $(awk '{ print $2 }' "$WORK/seen" | sed -nE 's#^(.*/Cellar/[^/]+/[^/]
         -exec cp {} "$CONTENTS/Resources/Licenses/$formula/" \; 2> /dev/null || true
     [ -n "$(ls -A "$CONTENTS/Resources/Licenses/$formula")" ] || fail "found no licence file for $formula in $keg"
     printf '    %s: %s\n' "$formula" "$(ls "$CONTENTS/Resources/Licenses/$formula" | tr '\n' ' ')"
-done
+done < "$WORK/kegs"
 [ "$(awk '{ print $2 }' "$WORK/seen" | grep -vc '/Cellar/' || true)" -eq 0 ] \
     || fail "a bundled library isn't from a Homebrew keg, so its licence is unknown: $(awk '{ print $2 }' "$WORK/seen" | grep -v '/Cellar/' | head -n 1)"
 # The code MetalUI compiles into the binary: on macOS with its default (CoreText) text system that is stb_image only
@@ -130,10 +135,12 @@ repoint() {
     local file="$1" name
     local args=()
     codesign --remove-signature "$file"
+    linked_libraries "$file" > "$WORK/links"
+    rpaths "$file" > "$WORK/rpaths"
     while IFS= read -r name; do
         is_system "$name" || args+=(-change "$name" "@rpath/$(basename "$name")")
-    done < <(linked_libraries "$file")
-    while IFS= read -r name; do args+=(-delete_rpath "$name"); done < <(rpaths "$file")
+    done < "$WORK/links"
+    while IFS= read -r name; do args+=(-delete_rpath "$name"); done < "$WORK/rpaths"
     install_name_tool ${args[@]+"${args[@]}"} "${@:2}" "$file"
 }
 for library in "$FRAMEWORKS"/*.dylib; do
@@ -157,9 +164,16 @@ for library in "$FRAMEWORKS"/*.dylib; do
 done
 codesign "${sign_options[@]}" "$APP"
 
-"$ROOT/scripts/verify-app.sh" "$APP"
-
 mkdir -p "$DIST"
-rm -rf "$DIST/MetalCreator.app"
-mv "$APP" "$DIST/MetalCreator.app"
+rm -rf "$STAGE"
+ditto "$APP" "$STAGE"
+"$ROOT/scripts/verify-app.sh" "$STAGE"
+
+# The old app is moved aside, not deleted first, so no moment leaves the destination empty: if the second rename fails
+# the old one is put back.
+OLD="$DIST/.MetalCreator.app.old"
+rm -rf "$OLD"
+if [ -e "$DIST/MetalCreator.app" ]; then mv "$DIST/MetalCreator.app" "$OLD"; fi
+mv "$STAGE" "$DIST/MetalCreator.app" || { [ ! -e "$OLD" ] || mv "$OLD" "$DIST/MetalCreator.app"; fail "couldn't move the new app into place"; }
+rm -rf "$OLD"
 step "Wrote $(cd "$DIST" && pwd -P)/MetalCreator.app"
```

**Modify `scripts/verify-app.sh`:**

```diff
--- a/scripts/verify-app.sh
+++ b/scripts/verify-app.sh
@@ -4,5 +4,5 @@
 #   2. the signature verifies, deep and strict;
 #   3. no Mach-O file in the bundle links or searches Homebrew (/opt/homebrew, /usr/local), and every @rpath library
-#      it links is in Contents/Frameworks;
+#      it links (and every @loader_path and @executable_path one) is in the bundle;
 #   4. LSMinimumSystemVersion is no older than any bundled binary's minimum macOS;
 #   5. `MetalCreator --self-test` passes with the environment emptied (no DYLD_* variables) and Homebrew's directories
@@ -55,6 +55,13 @@ while IFS= read -r -d '' file; do
         fail "$file searches a Homebrew directory (LC_RPATH)"
     fi
-    for name in $(otool -L "$file" | sed -n '2,$p' | awk '{ print $1 }' | grep '^@rpath/' || true); do
-        [ -f "$CONTENTS/Frameworks/${name#@rpath/}" ] || fail "$file links $name, which is not in Contents/Frameworks"
+    # Each relative install name must name a file in the bundle: @rpath/ ones in Contents/Frameworks (the app's only
+    # rpath), @loader_path/ ones beside the file that links them, @executable_path/ ones beside the executable.
+    for name in $(otool -L "$file" | sed -n '2,$p' | awk '{ print $1 }' | grep -E '^@(rpath|loader_path|executable_path)/' || true); do
+        case "$name" in
+            @rpath/*) wanted="$CONTENTS/Frameworks/${name#@rpath/}" ;;
+            @loader_path/*) wanted="$(dirname "$file")/${name#@loader_path/}" ;;
+            *) wanted="$CONTENTS/MacOS/${name#@executable_path/}" ;;
+        esac
+        [ -f "$wanted" ] || fail "$file links $name, which is not in the bundle ($wanted)"
     done
     needs="$(minimum_os "$file")"
```


- [ ] **Step 2: Verify by running**

Run: `bash -n scripts/package-app.sh && bash -n scripts/verify-app.sh`, then:

There is no unit test for a shell script's behaviour; the proof is by running them, **in the scratch copy only**:

```bash
scripts/package-app.sh            # about 2 minutes; ends with "verify: passed" and "Wrote …/dist/MetalCreator.app", no .staging or .old left in dist; run it a second time as well, so the swap goes over an existing app
# Negative check for verify-app.sh: a copy of the app whose libTKVCAF links a @loader_path name that is not there.
ditto dist/MetalCreator.app /tmp/tamper/MetalCreator.app
L=/tmp/tamper/MetalCreator.app/Contents/Frameworks/libTKVCAF.7.9.dylib
codesign --remove-signature $L && install_name_tool -change @rpath/libTKV3d.7.9.dylib @loader_path/gone.dylib $L
codesign --force --sign - $L && codesign --force --sign - /tmp/tamper/MetalCreator.app
git show HEAD:scripts/verify-app.sh > /tmp/verify-old.sh && chmod +x /tmp/verify-old.sh
/tmp/verify-old.sh /tmp/tamper/MetalCreator.app     # before: passes the links step, then dies in the self-test with a dyld abort
scripts/verify-app.sh /tmp/tamper/MetalCreator.app  # after: "FAILED: …libTKVCAF.7.9.dylib links @loader_path/gone.dylib, which is not in the bundle"
```

Run once on the scratch copy of this plan: the old script reached `==> verify: self-test without Homebrew` and aborted in dyld; the new one failed at `==> verify: links` with the sentence above.

- [ ] **Step 3: The whole suite, warnings and lint**

```bash
swift build --build-tests 2>&1 | grep 'warning:' | grep -v 'which was built for newer version' | sort -u
swift test 2>&1 | tee /tmp/test.log | grep -E 'recorded an issue|failed after|Test run with'
swiftlint lint --strict | tail -1
```

Expected: no new warning (master has two, both from `ContextMenuTests.swift:140`, `'underPointer' mutated after capture`); exit code 0, no line saying "recorded an issue" or "failed after", 11 "Test run with" lines, **master + 35 = **2177** (no test changes)**; `Found 0 violations`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "fix: packaging scripts surface otool failures, read paths safely, swap the app in by renames and check every relative install name"
```


---

### Task 7: Themes: write a colour drag once; case-insensitive reserved ids; unusable ids (AV-11 a, b)

AV-11(a) and (b). The contract is the themes Errata's “Each change is saved at once” and `ThemeStore`'s doc comments' “every change is saved before it is shown”; a colour drag is now the one exception, kept narrow, and the code says so: the doc comments of `ThemeStore` and of `ThemeStore+Library` (the latter said “Every change is saved before it is shown…” and would now be false for a drag) name `previewColor`/`saveColors` as the exception. No spec states “saved before shown” in those words (that text is only in the code and in `CLAUDE.md`); the spec's nearest sentence, “Each change is saved at once”, gets a short parenthesis in Task 10 so the Errata does not contradict the behaviour, and `CLAUDE.md` gets the same exception. the store shows each sample (`previewColor`, memory only, remembering the saved theme in `unsavedBase`), and `saveColors()` writes once. The editor schedules that write `saveDelay` after the last sample (one cancelled-and-restarted `Task` using an injectable `sleep`), and `flush()` writes at once on Done, and when the window is asked to close (`main.swift`), so a colour dragged just before ⌘Q is kept. Any other change to the same theme (`rename`, `setDark`, `setColor`) saves the previewed colours with it because `editable` returns the in-memory theme; previewing another theme saves the first one's pending colours first; `delete` drops them. A failed save puts the saved colours back (`show(base)`) and the editor shows the problem. Dropped from AV-11: (c) the stricter `ThemeFileBody` is the documented safe refusal; (d) the `.dracula` fallback cannot happen at today's call sites; the hand-placed-duplicate-name finding is harmless (ids differ, `sorted` orders ties by id).

**Files:**
- Modify: `Sources/CreatorStyle/ThemeStore.swift` (`unsavedBase`), `ThemeStore+Library.swift` (the type's doc comment, `previewColor`, `hasUnsavedColors`, `saveColors`, `show`, `replace`, `delete`), `ThemeFolder.swift`
- Modify: `Sources/CreatorApp/ThemeEditorModel.swift`, `Sources/MetalCreatorApp/main.swift` (`onCloseRequest` flushes)
- Create: `Tests/CreatorStyleTests/ThemeColorPreviewTests.swift`, `Tests/CreatorAppTests/ThemeColorDragTests.swift`
- Modify: `Tests/CreatorStyleTests/ThemeFolderTests.swift`

**Interfaces:**
- Produces (CreatorStyle): `ThemeStore.previewColor(_:for:in:) throws(ThemeProblem)`, `ThemeStore.hasUnsavedColors: Bool`, `ThemeStore.saveColors() throws(ThemeProblem)`, `ThemeStore.show(_:)` (internal; the memory half of `replace`), `ThemeFolder.isUsable(_:)` (internal static).
- Produces (CreatorApp): `ThemeEditorModel.init(themes:sleep:)` (`sleep` defaults to `Task.sleep(for:)`), `ThemeEditorModel.saveDelay` (300 ms), `dragColor(_:for:)`, `flush()`. `colorBinding(for:)` now calls `dragColor`; `setColor(_:for:)` is unchanged (immediate, used by tests).

- [ ] **Step 1: Write the tests**

**Create `Tests/CreatorAppTests/ThemeColorDragTests.swift`:**

```swift
import CreatorStyle
import Foundation
import MetalUI
import Testing
@testable import CreatorApp

/// A colour picker's drag in the theme editor: every sample is shown at once, and the theme's file is written once,
/// when the drag pauses, the editor closes or the window is asked to close.
@MainActor
struct ThemeColorDragTests {
    /// Stands in for `ThemeEditorModel.saveDelay`: a sleep that lasts until the test opens the gate.
    @MainActor
    final class Gate {
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            await withCheckedContinuation { waiting.append($0) }
        }

        /// Lets the sleeps asked for begin, ends them all, and lets the tasks they wake run.
        func open() async {
            for _ in 0..<20 { await Task.yield() }
            let released = waiting
            waiting = []
            for continuation in released { continuation.resume() }
            for _ in 0..<20 { await Task.yield() }
        }
    }

    let accent = ThemeRole.named("accent")

    /// An editor on a custom copy of Dracula saved in a temporary folder, and the gate its save delay waits on.
    func makeEditor() throws -> (editor: ThemeEditorModel, folder: ThemeFolder, gate: Gate) {
        let folder = ThemeFolder(URL.temporaryDirectory.appending(path: "ThemeColorDragTests-\(UUID().uuidString)",
                                                  directoryHint: .isDirectory))
        let gate = Gate()
        let editor = ThemeEditorModel(themes: ThemeStore(folder: folder), sleep: { _ in await gate.wait() })
        editor.duplicate()
        try #require(editor.isEditable)
        return (editor, folder, gate)
    }

    func savedAccent(_ folder: ThemeFolder) -> HexColor? {
        folder.load(reserved: []).themes.first?.colors.accent
    }

    @Test func aDragShowsEverySampleAndWritesOnceWhenItPauses() async throws {
        let (editor, folder, gate) = try makeEditor()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let role = try #require(accent)
        let before = try #require(savedAccent(folder))
        let binding = editor.colorBinding(for: role)
        for step in 1...50 {
            binding.wrappedValue = Color(.sRGB, red: Double(step) / 255, green: 0, blue: 0)
            #expect(editor.theme.colors.accent == HexColor(UInt32(step) << 16), "shown at once")
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(savedAccent(folder) == before, "no write while the drag goes on")
        await gate.open()
        #expect(savedAccent(folder) == HexColor(50 << 16), "the last sample, written when the drag paused")
        #expect(!editor.themes.hasUnsavedColors && editor.message == nil)
    }

    @Test func closingTheEditorSavesAtOnce() async throws {
        let (editor, folder, _) = try makeEditor()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        editor.dragColor(HexColor(0x123456), for: try #require(accent))
        #expect(savedAccent(folder) != HexColor(0x123456))
        editor.close()
        #expect(savedAccent(folder) == HexColor(0x123456))
    }

    @Test func flushSavesAtOnceAndTheLaterWakeDoesNothing() async throws {
        let (editor, folder, gate) = try makeEditor()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        editor.dragColor(HexColor(0x654321), for: try #require(accent))
        editor.flush()
        #expect(savedAccent(folder) == HexColor(0x654321))
        await gate.open()
        #expect(savedAccent(folder) == HexColor(0x654321) && editor.message == nil)
    }

    @Test func aFailedSaveShowsTheSavedColourAgainAndSaysWhy() async throws {
        let (editor, folder, gate) = try makeEditor()
        let role = try #require(accent)
        let saved = try #require(savedAccent(folder))
        editor.dragColor(HexColor(0x123456), for: role)
        try FileManager.default.removeItem(at: folder.url)
        try Data("in the way".utf8).write(to: folder.url)
        defer { try? FileManager.default.removeItem(at: folder.url) }
        await gate.open()
        #expect(editor.theme.colors.accent == saved)
        #expect(editor.message?.contains("couldn’t be saved") == true)
    }

    @Test func aBuiltInThemeStaysUntouchedAndSaysSo() throws {
        let editor = ThemeEditorModel(themes: ThemeStore())
        editor.dragColor(HexColor(0), for: try #require(accent))
        #expect(editor.theme == .dracula)
        #expect(editor.message == "Built-in themes can’t be changed. Duplicate one to make your own.")
    }
}
```

**Create `Tests/CreatorStyleTests/ThemeColorPreviewTests.swift`:**

```swift
import Foundation
import Testing
@testable import CreatorStyle

/// A colour picker's drag shows each sample at once but writes the theme's file once (`ThemeStore.previewColor` and
/// `saveColors`), where `setColor` writes every call. A failed save puts the saved colours back and says why.
@MainActor
struct ThemeColorPreviewTests {
    let accent = ThemeRole.named("accent")

    /// The accent colour of the custom theme in `folder`'s file, as the next launch would read it.
    func savedAccent(_ folder: ThemeFolder) -> HexColor? {
        folder.load(reserved: []).themes.first?.colors.accent
    }

    @Test func aDragShowsEverySampleButSavesOnlyWhenTold() throws {
        let folder = ThemeFolderTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let store = ThemeStore(folder: folder)
        let copy = try store.duplicate("dracula")
        let role = try #require(accent)
        let before = try #require(savedAccent(folder))
        for step in 1...50 {
            try store.previewColor(HexColor(UInt32(step) << 16), for: role, in: copy.id)
            #expect(store.current.colors.accent == HexColor(UInt32(step) << 16), "shown at once")
        }
        #expect(store.hasUnsavedColors)
        #expect(savedAccent(folder) == before, "50 samples, no write")
        try store.saveColors()
        #expect(!store.hasUnsavedColors)
        #expect(savedAccent(folder) == HexColor(50 << 16), "the last sample, in one write")
        try store.saveColors()   // nothing pending: nothing happens
    }

    @Test func anotherChangeSavesThePreviewedColoursWithIt() throws {
        let folder = ThemeFolderTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let store = ThemeStore(folder: folder)
        let copy = try store.duplicate("dracula")
        let role = try #require(accent)
        try store.previewColor(HexColor(0x123456), for: role, in: copy.id)
        try store.rename(copy.id, to: "Midnight")
        #expect(!store.hasUnsavedColors)
        let saved = try #require(folder.load(reserved: []).themes.first)
        #expect(saved.name == "Midnight" && saved.colors.accent == HexColor(0x123456))
    }

    @Test func previewingAnotherThemeSavesTheFirstOnesColoursFirst() throws {
        let folder = ThemeFolderTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let store = ThemeStore(folder: folder)
        let first = try store.duplicate("dracula")
        let second = try store.duplicate("nord")
        let role = try #require(accent)
        try store.previewColor(HexColor(0x111111), for: role, in: first.id)
        try store.previewColor(HexColor(0x222222), for: role, in: second.id)
        let reloaded = ThemeStore(folder: folder)
        #expect(reloaded.theme(first.id)?.colors.accent == HexColor(0x111111))
        #expect(reloaded.theme(second.id)?.colors.accent != HexColor(0x222222), "the second is still pending")
        try store.saveColors()
        #expect(ThemeStore(folder: folder).theme(second.id)?.colors.accent == HexColor(0x222222))
    }

    @Test func aBuiltInIsRefusedAndNothingIsPending() throws {
        let store = ThemeStore()
        #expect(throws: ThemeProblem.self) { try store.previewColor(HexColor(0), for: try #require(accent), in: "nord") }
        #expect(!store.hasUnsavedColors)
    }

    @Test func aFailedSaveGoesBackToTheSavedColoursAndSaysWhy() throws {
        let folder = ThemeFolderTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let store = ThemeStore(folder: folder)
        let copy = try store.duplicate("dracula")
        let role = try #require(accent)
        let saved = try #require(savedAccent(folder))
        try store.previewColor(HexColor(0x123456), for: role, in: copy.id)
        // Something that is not a folder in the way of the theme's file makes the write fail.
        try FileManager.default.removeItem(at: folder.url)
        try Data("in the way".utf8).write(to: folder.url)
        #expect(throws: ThemeProblem.self) { try store.saveColors() }
        #expect(store.current.colors.accent == saved && !store.hasUnsavedColors)
        try FileManager.default.removeItem(at: folder.url)
    }

    @Test func deletingAThemeDropsItsPendingColours() throws {
        let store = ThemeStore(folder: ThemeFolderTests.temporaryFolder())
        let copy = try store.duplicate("dracula")
        try store.previewColor(HexColor(0x123456), for: try #require(accent), in: copy.id)
        try store.delete(copy.id)
        #expect(!store.hasUnsavedColors)
        try store.saveColors()
    }
}
```

**Modify `Tests/CreatorStyleTests/ThemeFolderTests.swift`:**

```diff
--- a/Tests/CreatorStyleTests/ThemeFolderTests.swift
+++ b/Tests/CreatorStyleTests/ThemeFolderTests.swift
@@ -77,3 +77,22 @@ struct ThemeFolderTests {
         #expect(error?.message.hasPrefix("“Alpha” couldn’t be saved: ") == true)
     }
+
+    /// The usual volume is case-insensitive: "Dracula.mctheme" is the built-in's file name there, so it is skipped too.
+    @Test func aFileNamedLikeABuiltInInAnotherCaseIsSkipped() throws {
+        let folder = Self.temporaryFolder()
+        defer { try? FileManager.default.removeItem(at: folder.url) }
+        try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
+        try ThemeFile.encode(Self.custom("Dracula", "Shouty")).write(to: folder.fileURL(for: "Dracula"))
+        let loaded = folder.load(reserved: ["dracula"])
+        #expect(loaded.themes.isEmpty)
+        #expect(loaded.problems == ["“Dracula.mctheme” was skipped: its name is a built-in theme’s."])
+    }
+
+    @Test(arguments: ["a/b", "..", ".", ""])
+    func anIdThatIsNotAFileNameIsNeverWrittenOrRemoved(_ id: String) {
+        let folder = Self.temporaryFolder()
+        #expect(throws: ThemeProblem.self) { try folder.save(Self.custom(id, "Odd")) }
+        #expect(throws: ThemeProblem.self) { try folder.remove(id) }
+        #expect(!FileManager.default.fileExists(atPath: folder.url.path(percentEncoded: false)), "not even the folder")
+    }
 }
```


- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter "ThemeColorPreviewTests|ThemeColorDragTests|ThemeFolderTests|ThemeLibraryTests|ThemeEditorModelTests"`

Expected failures before the change: none of these compile (`previewColor`, `dragColor`, `flush`, `isUsable` are new). Behaviourally, against `setColor`, `ThemeColorDragTests.aDragShowsEverySampleAndWritesOnceWhenItPauses` fails at “no write while the drag goes on” (the file changes after the first sample), and `aFileNamedLikeABuiltInInAnotherCaseIsSkipped` fails (the file loads as custom id “Dracula”).

- [ ] **Step 3: Make the change**

**Modify `Sources/CreatorApp/ThemeEditorModel.swift`:**

```diff
--- a/Sources/CreatorApp/ThemeEditorModel.swift
+++ b/Sources/CreatorApp/ThemeEditorModel.swift
@@ -22,7 +22,13 @@ public final class ThemeEditorModel {
     /// The window's open and save panels. The app sets it once the window is open.
     @ObservationIgnored public var filePicker: (any FilePicker)?
+    /// How long a colour drag must pause before the theme is saved.
+    public static let saveDelay = Duration.milliseconds(300)
+    /// Waits `saveDelay` (tests stand in for it).
+    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void
+    @ObservationIgnored private var saveTask: Task<Void, Never>?
 
-    public init(themes: ThemeStore) {
+    public init(themes: ThemeStore, sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
         self.themes = themes
+        self.sleep = sleep
     }
 
@@ -59,4 +65,5 @@ public final class ThemeEditorModel {
     public func close() {
         commitName()
+        flush()
         isOpen = false
         pendingDeleteID = nil
@@ -118,7 +125,29 @@ public final class ThemeEditorModel {
     }
 
-    /// The colour picker's binding for `role`: the shown theme's colour, and `setColor` for each write.
+    /// The colour picker's binding for `role`: the shown theme's colour, and `dragColor` for each write.
     public func colorBinding(for role: ThemeRole) -> Binding<Color> {
-        Binding(get: { [self] in theme.colors[role].color }, set: { [self] in setColor(HexColor($0), for: role) })
+        Binding(get: { [self] in theme.colors[role].color }, set: { [self] in dragColor(HexColor($0), for: role) })
+    }
+
+    /// One sample of a colour drag: shown at once, saved once the drag has paused for `saveDelay` (or sooner, by `flush()`),
+    /// so a drag writes the theme's file once and not for every sample.
+    public func dragColor(_ color: HexColor, for role: ThemeRole) {
+        guard perform({ () throws(ThemeProblem) in try themes.previewColor(color, for: role, in: theme.id) }) else { return }
+        saveTask?.cancel()
+        let sleep = sleep
+        saveTask = Task { [weak self] in
+            await sleep(Self.saveDelay)
+            guard !Task.isCancelled else { return }
+            self?.flush()
+        }
+    }
+
+    /// Saves colours not yet saved, now: a problem is shown as the message. Called when the editor closes and the window
+    /// is asked to close, so no colour is lost.
+    public func flush() {
+        saveTask?.cancel()
+        saveTask = nil
+        guard themes.hasUnsavedColors else { return }
+        perform { () throws(ThemeProblem) in try themes.saveColors() }
     }
 
```

**Modify `Sources/CreatorStyle/ThemeFolder.swift`:**

```diff
--- a/Sources/CreatorStyle/ThemeFolder.swift
+++ b/Sources/CreatorStyle/ThemeFolder.swift
@@ -16,4 +16,9 @@ public struct ThemeFolder: Hashable, Sendable {
     }
 
+    /// Whether `id` can be a file's name in this folder: it holds no "/" and isn't "." or "..".
+    static func isUsable(_ id: ColorTheme.ID) -> Bool {
+        !id.isEmpty && !id.contains("/") && id != "." && id != ".."
+    }
+
     /// The `.mctheme` file of the theme with `id`.
     public func fileURL(for id: ColorTheme.ID) -> URL {
@@ -32,4 +37,5 @@ public struct ThemeFolder: Hashable, Sendable {
             return ([], ["The themes folder couldn’t be read: \(error.localizedDescription)"])
         }
+        let reservedLowercased = Set(reserved.map { $0.lowercased() })
         var themes: [ColorTheme] = []
         var problems: [String] = []
@@ -38,8 +44,13 @@ public struct ThemeFolder: Hashable, Sendable {
             let id = file.deletingPathExtension().lastPathComponent
             let skipped = "“\(file.lastPathComponent)” was skipped:"
-            guard !reserved.contains(id) else {
+            // Case-insensitively: on the usual case-insensitive volume "Dracula.mctheme" is the built-in's name too.
+            guard !reservedLowercased.contains(id.lowercased()) else {
                 problems.append("\(skipped) its name is a built-in theme’s.")
                 continue
             }
+            guard Self.isUsable(id) else {
+                problems.append("\(skipped) its name can’t be used for a theme.")
+                continue
+            }
             do {
                 let data = try Data(contentsOf: file)
@@ -58,4 +69,5 @@ public struct ThemeFolder: Hashable, Sendable {
     /// Writes `theme` to its file, creating the folder if needed.
     public func save(_ theme: ColorTheme) throws(ThemeProblem) {
+        guard Self.isUsable(theme.id) else { throw ThemeProblem("“\(theme.name)” couldn’t be saved: its id can’t be a file name.") }
         do {
             try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
@@ -68,4 +80,5 @@ public struct ThemeFolder: Hashable, Sendable {
     /// Deletes the file of the theme with `id`. A file that is already gone is fine.
     public func remove(_ id: ColorTheme.ID) throws(ThemeProblem) {
+        guard Self.isUsable(id) else { throw ThemeProblem("The theme couldn’t be deleted: its id can’t be a file name.") }
         do {
             try FileManager.default.removeItem(at: fileURL(for: id))
```

**Modify `Sources/CreatorStyle/ThemeStore+Library.swift`:**

```diff
--- a/Sources/CreatorStyle/ThemeStore+Library.swift
+++ b/Sources/CreatorStyle/ThemeStore+Library.swift
@@ -2,7 +2,8 @@ import Foundation
 
 /// Custom themes (Themes milestone): duplicate any theme, then rename, recolour, darken or delete the copy. The
 /// built-ins stay read-only (spec §6.6). Every change is saved before it is shown, so a save that fails changes
-/// nothing and says why.
+/// nothing and says why. The one exception is a colour picker's drag (`previewColor`): each sample is shown at once
+/// and `saveColors()` writes them once, so there a failed save puts the saved colours back and says why afterwards.
 extension ThemeStore {
     /// Duplicate: a custom copy of the theme with `id` named "<name> Copy" (then "… Copy 2" and on), saved and shown.
     @discardableResult
@@ -35,4 +36,37 @@ extension ThemeStore {
     }
 
+    /// Shows one role's new colour in a custom theme at once and leaves saving it to `saveColors()`: a colour picker sends
+    /// a value for every sample of a drag, and each would otherwise rewrite the theme's file on the main actor. Until it is
+    /// saved a failure can't be reported, so `saveColors()` puts the saved colours back and says why then. Another
+    /// theme's pending colours are saved first; any other change to this theme saves them with it.
+    public func previewColor(_ color: HexColor, for role: ThemeRole, in id: ColorTheme.ID) throws(ThemeProblem) {
+        var theme = try editable(id)
+        let color = color.quantized
+        guard theme.colors[role] != color else { return }
+        if unsavedBase?.id != id {
+            try saveColors()
+            unsavedBase = theme
+        }
+        theme.colors[role] = color
+        show(theme)
+    }
+
+    /// Whether colours shown by `previewColor` are not saved yet.
+    public var hasUnsavedColors: Bool { unsavedBase != nil }
+
+    /// Saves the colours `previewColor` showed, in one write. If that fails the theme goes back to its last saved colours
+    /// and the problem is thrown.
+    public func saveColors() throws(ThemeProblem) {
+        guard let base = unsavedBase else { return }
+        unsavedBase = nil
+        guard let theme = customs.first(where: { $0.id == base.id }) else { return }
+        do {
+            try folder?.save(theme)
+        } catch {
+            show(base)
+            throw error
+        }
+    }
+
     /// Whether a custom theme asks for MetalUI's dark controls (and the window's dark appearance) or its light ones.
     public func setDark(_ isDark: Bool, in id: ColorTheme.ID) throws(ThemeProblem) {
@@ -47,4 +81,5 @@ extension ThemeStore {
         _ = try editable(id)
         try folder?.remove(id)
+        if unsavedBase?.id == id { unsavedBase = nil }
         customs.removeAll { $0.id == id }
         if current.id == id {
@@ -71,4 +106,10 @@ extension ThemeStore {
     func replace(_ theme: ColorTheme) throws(ThemeProblem) {
         try folder?.save(theme)
+        if unsavedBase?.id == theme.id { unsavedBase = nil }
+        show(theme)
+    }
+
+    /// Lists a changed custom theme and, if it is current, shows the change; nothing is saved.
+    func show(_ theme: ColorTheme) {
         customs = Self.sorted(customs.map { $0.id == theme.id ? theme : $0 })
         if current.id == theme.id { current = theme }
```

**Modify `Sources/CreatorStyle/ThemeStore.swift`:**

```diff
--- a/Sources/CreatorStyle/ThemeStore.swift
+++ b/Sources/CreatorStyle/ThemeStore.swift
@@ -5,7 +5,8 @@ import Observation
 /// the environment and the app shell hands it to the viewport, so selecting a theme, or editing the current one,
 /// re-renders the editor by observation and reaches the GPU colours on the viewport's next frame. The built-ins are
 /// read-only; the person's own themes (`customs`) are duplicated, renamed, recoloured, deleted, imported and
-/// exported here (`ThemeStore+Library`, `ThemeStore+Files`), and each change is saved to `folder` at once.
+/// exported here (`ThemeStore+Library`, `ThemeStore+Files`), and each change is saved to `folder` at once (except a
+/// colour drag, which is shown first and saved once: `previewColor`, `saveColors()`).
 @MainActor
 @Observable
 public final class ThemeStore {
@@ -21,4 +22,6 @@ public final class ThemeStore {
     /// Where custom themes are saved; `nil` keeps them in memory only (tests, previews).
     @ObservationIgnored let folder: ThemeFolder?
+    /// A custom theme as it was last saved, while colours changed with `previewColor` wait to be saved (`saveColors()`).
+    @ObservationIgnored var unsavedBase: ColorTheme?
 
     /// Loads the custom themes from `folder`, then starts with the theme `preferences` remembers, or Dracula when it
```

**Modify `Sources/MetalCreatorApp/main.swift`:**

```diff
--- a/Sources/MetalCreatorApp/main.swift
+++ b/Sources/MetalCreatorApp/main.swift
@@ -25,5 +25,8 @@ func runApp(opening path: String?) throws {
     // Close and quit (gap M6-b): ⌘Q asks each window's `onCloseRequest` in turn when the app sets no
     // `onTerminateRequest`, and this app has one window, so one handler and one reply route serve both.
-    window.onCloseRequest = { model.closeRequested() }
+    window.onCloseRequest = {
+        themeEditor.flush()   // a colour dragged just now is saved before the window can go
+        return model.closeRequested()
+    }
     model.replyToCloseRequest = { window.replyToCloseRequest($0) }
     // Title, edited dot and proxy icon (gap M6-a) follow the document. The task lives as long as the app.
```


- [ ] **Step 4: Run the new tests**

Run: `swift test --filter "ThemeColorPreviewTests|ThemeColorDragTests|ThemeFolderTests|ThemeLibraryTests|ThemeEditorModelTests"`
Expected: all pass.

- [ ] **Step 5: The whole suite, warnings and lint**

```bash
swift build --build-tests 2>&1 | grep 'warning:' | grep -v 'which was built for newer version' | sort -u
swift test 2>&1 | tee /tmp/test.log | grep -E 'recorded an issue|failed after|Test run with'
swiftlint lint --strict | tail -1
```

Expected: no new warning (master has two, both from `ContextMenuTests.swift:140`, `'underPointer' mutated after capture`); exit code 0, no line saying "recorded an issue" or "failed after", 11 "Test run with" lines, **master + 48 = **2190****; `Found 0 violations`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "perf: write a theme colour drag once; reject case-variant built-in ids and ids that are not file names"
```


---

### Task 8: Blend search: a checker that cannot judge gets a second look; a non-positive size has nothing to try (AV-9)

AV-9(a), (b), (c), (d) and the `CheckCount` visibility from (e). **Shared with the kernel track** (`Sources/CreatorOCCT/OCCTKernel+Blend.swift`, `BlendGrid.swift`, and the blend tests): the second to merge keeps both sides' lines. The bench change is the one assertion the triage asks for, the “works” bracket samples must succeed; the bench is gated (`METALCREATOR_BENCH=1`), so it is compiled by `swift build --build-tests` but not run. Dropped from AV-9: (d)'s second half (recording the R8.x refusal path in `performance.md`) needs a measurement, which the idle re-run will provide; (e)'s “no test asserts a real shape reports `.invalid`” is covered by the flange R3 tests (`aFilletOCCTBreaksIsRefusedWithTheLargestRadiusThatWorks`).

**Files:**
- Modify: `Sources/CreatorOCCT/OCCTKernel+Blend.swift` (`largestValidBlend`), `Sources/CreatorOCCT/BlendGrid.swift` (`firstFailingTenths`)
- Create: `Tests/CreatorOCCTTests/BlendSearchTests.swift`
- Modify: `Tests/CreatorOCCTTests/BlendGridTests.swift`, `UnbuildableBlendTests.swift` (comment), `InvalidBlendTests.swift` (`CheckCount` private), `Tests/CreatorAppTests/Bench/BlendRefusalBench.swift`

**Interfaces:**
- Changes behaviour only for a checker that returns `.unchecked` mid-search (asked once more) and for sizes that are not positive (`BlendGrid.firstFailingTenths(for:)` returns 0). No signature changes.

- [ ] **Step 1: Write the tests**

**Modify `Tests/CreatorAppTests/Bench/BlendRefusalBench.swift`:**

```diff
--- a/Tests/CreatorAppTests/Bench/BlendRefusalBench.swift
+++ b/Tests/CreatorAppTests/Bench/BlendRefusalBench.swift
@@ -77,4 +77,5 @@ struct BlendRefusalBench {
             await app.settle()
             let b = clock.now
+            #expect(app.document.results[bracket.fillet.id]?.state.isSuccess == true, "the “works” sample must work (R3.x)")
             try app.document.perform(.setInput(bracket.fillet.id, "radius", .number(8 + Double(step) * 0.05)))
             await app.settle()
```

**Modify `Tests/CreatorOCCTTests/BlendGridTests.swift`:**

```diff
--- a/Tests/CreatorOCCTTests/BlendGridTests.swift
+++ b/Tests/CreatorOCCTTests/BlendGridTests.swift
@@ -21,4 +21,11 @@ struct BlendGridTests {
     }
 
+    /// `Int(.nan)` traps. Nothing but `blendSource` (which refuses such a size first) calls the search today.
+    @Test(arguments: [Double.nan, -Double.infinity, -1.0, 0.0])
+    func aSizeThatIsNotPositiveHasNothingToTry(_ size: Double) {
+        #expect(BlendGrid.firstFailingTenths(for: size) == 0)
+        #expect(!BlendGrid.triesSmallest(below: size))
+    }
+
     @Test func theSmallestSizeIsTriedOnlyBelowASizeAboveIt() {
         #expect(!BlendGrid.triesSmallest(below: 0.1))
```

**Create `Tests/CreatorOCCTTests/BlendSearchTests.swift`:**

```swift
import Synchronization
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// The search for the largest size that works (`OCCTKernel.largestValidBlend`) when its checker doesn't answer every time.
struct BlendSearchTests {
    /// A checker that, called again, gives a different answer: every odd call is `.unchecked` and every even one `.valid`.
    final class Flaky: Sendable {
        let calls = Mutex(0)

        func check(_: OCCTShape) -> OCCTValidity {
            calls.withLock { calls in
                calls += 1
                return calls.isMultiple(of: 2) ? .valid : .unchecked
            }
        }
    }

    func standingBox() async throws -> (kernel: OCCTKernel, source: OCCTShape, edge: EdgeID) {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try #require(solid.topology.edges.first { $0.kind == .line && isClose($0.length, 30) })
        return (kernel, try #require((solid.storage as? OCCTSolidStorage)?.shape), edge.id)
    }

    /// A try the checker could not judge says nothing about that size: it is asked once more before the size counts as
    /// failed, so a checker that fails now and then does not name a smaller maximum than the part allows.
    @Test func aTryTheCheckerCouldNotJudgeIsCheckedOnceMoreBeforeItCountsAsFailed() async throws {
        let (kernel, source, edge) = try await standingBox()
        let sure = try await kernel.largestValidBlend(of: source, edges: [edge], below: 40, chamfer: false)
        #expect(sure == 9.9)
        let flaky = Flaky()
        let found = try await kernel.largestValidBlend(of: source, edges: [edge], below: 40, chamfer: false) { flaky.check($0) }
        #expect(found == sure, "the same maximum as with a checker that always answers")
        #expect(flaky.calls.withLock { $0 } > 0)
    }

    /// A checker that never answers names nothing: no size was ever shown to work.
    @Test func aCheckerThatNeverAnswersNamesNoSize() async throws {
        let (kernel, source, edge) = try await standingBox()
        let found = try await kernel.largestValidBlend(of: source, edges: [edge], below: 40, chamfer: false) { _ in .unchecked }
        #expect(found == nil)
    }
}
```

**Modify `Tests/CreatorOCCTTests/InvalidBlendTests.swift`:**

```diff
--- a/Tests/CreatorOCCTTests/InvalidBlendTests.swift
+++ b/Tests/CreatorOCCTTests/InvalidBlendTests.swift
@@ -90,5 +90,5 @@ struct InvalidBlendTests {
 
     /// Counts the checker's calls from a closure the kernel runs on its own actor.
-    final class CheckCount: Sendable {
+    private final class CheckCount: Sendable {
         let calls = Mutex(0)
         func record() { calls.withLock { $0 += 1 } }
```

**Modify `Tests/CreatorOCCTTests/UnbuildableBlendTests.swift`:**

```diff
--- a/Tests/CreatorOCCTTests/UnbuildableBlendTests.swift
+++ b/Tests/CreatorOCCTTests/UnbuildableBlendTests.swift
@@ -47,6 +47,6 @@ struct UnbuildableBlendTests {
     }
 
-    /// The search starts from the size asked for, capped, so a size far beyond the part (here a metre-scale 1e9 mm) ends in
-    /// the same maximum after the same few tries.
+    /// The search starts from the size asked for, capped, so a size far beyond the part (here 1e9 mm, a thousand
+    /// kilometres) ends in the same maximum as one just beyond it.
     @Test func aRadiusFarBeyondThePartNamesTheSameMaximum() async throws {
         let kernel = OCCTKernel()
```


- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter "BlendSearchTests|BlendGridTests|InvalidBlendTests|UnbuildableBlendTests"`

Expected failures before the change: `BlendSearchTests.aTryTheCheckerCouldNotJudgeIsCheckedOnceMoreBeforeItCountsAsFailed` (`found == sure`: the flaky checker names a smaller maximum; mutation-checked), and `BlendGridTests.aSizeThatIsNotPositiveHasNothingToTry` with `.nan` (`Int(.nan)` traps the test process). `aCheckerThatNeverAnswersNamesNoSize` passes before and after.

- [ ] **Step 3: Make the change**

**Modify `Sources/CreatorOCCT/BlendGrid.swift`:**

```diff
--- a/Sources/CreatorOCCT/BlendGrid.swift
+++ b/Sources/CreatorOCCT/BlendGrid.swift
@@ -9,13 +9,15 @@ enum BlendGrid {
     /// Slack for products like `0.3 * 10` that land a hair above a whole number.
     private static let slack = 1e-9
 
-    /// The first count of tenths of a millimetre at or above `size`: the search tries only counts below it, so it
-    /// names a size below the one asked for. A size on the grid is exact even when float arithmetic put it a hair
-    /// over (`0.1 + 0.2`, which `ceil` alone would round up to 4 tenths). The slack also means a size within 1e-9
-    /// above a grid value counts as that value, so for an off-grid size the maximum named is conservative: it can be
-    /// a step below a size that would still build.
+    /// The first count of tenths of a millimetre at or above `size` (0 for a size that is not positive): the search
+    /// tries only counts below it, so it names a size below the one asked for. A size on the grid is exact even when
+    /// float arithmetic put it a hair over (`0.1 + 0.2`, which `ceil` alone would round up to 4 tenths). The slack also
+    /// means a size within 1e-9 above a grid value counts as that value, so for an off-grid size the maximum named is
+    /// conservative: it can be a step below a size that would still build.
     static func firstFailingTenths(for size: Double) -> Int {
-        Int(min((size * 10 - slack).rounded(.up), Double(mostTenths)))
+        // Not a positive number (NaN, minus infinity, zero, negative): no size to try, and `Int(.nan)` would trap.
+        guard size > 0 else { return 0 }
+        return Int(min((size * 10 - slack).rounded(.up), Double(mostTenths)))
     }
 
     /// Whether a search for `size` tries the smallest grid size, 0.1 mm. When it didn't, finding none says nothing
```

**Modify `Sources/CreatorOCCT/OCCTKernel+Blend.swift`:**

```diff
--- a/Sources/CreatorOCCT/OCCTKernel+Blend.swift
+++ b/Sources/CreatorOCCT/OCCTKernel+Blend.swift
@@ -65,9 +65,10 @@ extension OCCTKernel {
         return try shape(of: solid)
     }
 
-    /// The largest size below `size`, on a 0.1 mm grid, whose blend OCCT builds and `check` accepts; nil when not
-    /// even 0.1 mm does. It bisects, assuming every size above one that fails fails too; the size it returns was built
-    /// and checked. Each try takes the OCCT lock on its own, and a cancelled evaluation stops between tries.
+    /// The largest size below `size`, on a 0.1 mm grid, whose blend OCCT builds and `check` accepts (asked a second
+    /// time when it can't judge); nil when not even 0.1 mm does. It bisects, assuming every size above one that fails
+    /// fails too; the size it returns was built and checked. Each try takes the OCCT lock on its own, and a cancelled
+    /// evaluation stops between tries.
     func largestValidBlend(of source: OCCTShape, edges: [EdgeID], below size: Double, chamfer: Bool,
                            check: (OCCTShape) -> OCCTValidity = { $0.validity }) throws -> Double? {
         var works = 0
@@ -78,7 +79,9 @@ extension OCCTKernel {
             let tenths = (works + fails) / 2
             let valid = Self.serialized { () -> Bool in
                 guard let built = try? source.blended(edges: edges, size: Double(tenths) / 10, chamfer: chamfer) else { return false }
-                return check(built.0) == .valid
+                // A checker that can't judge says nothing about the size: it gets one more look before it fails.
+                let verdict = check(built.0)
+                return (verdict == .unchecked ? check(built.0) : verdict) == .valid
             }
             if valid { works = tenths } else { fails = tenths }
         }
```


- [ ] **Step 4: Run the new tests**

Run: `swift test --filter "BlendSearchTests|BlendGridTests|InvalidBlendTests|UnbuildableBlendTests"`
Expected: all pass.

- [ ] **Step 5: The whole suite, warnings and lint**

```bash
swift build --build-tests 2>&1 | grep 'warning:' | grep -v 'which was built for newer version' | sort -u
swift test 2>&1 | tee /tmp/test.log | grep -E 'recorded an issue|failed after|Test run with'
swiftlint lint --strict | tail -1
```

Expected: no new warning (master has two, both from `ContextMenuTests.swift:140`, `'underPointer' mutated after capture`); exit code 0, no line saying "recorded an issue" or "failed after", 11 "Test run with" lines, **master + 51 = **2193****; `Found 0 violations`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix: re-check a blend the checker could not judge; no grid for a non-positive size"
```


---

### Task 9: Comment and wrap cleanup in the app and viewport (DOC-6, code part)

DOC-6, the part in this track's modules. No test applies (comments and line breaks only); the proof is that Task 8's counts hold, the build has no new warning and SwiftLint is clean. Checked and dropped: `FiftyNodeGraph.swift`'s `import Testing` is used (`#_sourceLocation`; removing it fails the build), `AppModel+Closing.swift:32-38` has no over-long line, and the editor/groups-module items (`EditorModel.swift:25`, `EditorModel+Nudge.swift:6`, `GroupCommands+Ungroup.swift`, `GraphCanvas.swift:3-5`, `Cursor.swift:3-5`, `EditorModel+Pinch.swift:14`) belong to the editor track's files and are left to it (see Risks). The `GraphPanZoomBench` comment is corrected from the code (16 points and 2 points a frame over 130 frames: 2,080 and 260 points), not from the triage's “about 8 of 10 rows”.

**Files:**
- Modify (comments and line wraps only): `Sources/CreatorApp/AppRoot.swift`, `ThemeEditorDock.swift`, `ThemeMenu.swift`, `AppModel+Closing.swift`, `SceneBuilder.swift`, `AppModel+Scene.swift`, `AppBundleInfo.swift`, `SketchStore.swift`, `Sources/CreatorViewport/Render/ViewportRenderer.swift`, `Tests/CreatorAppTests/Bench/FilletDragBench.swift`, `GraphPanZoomBench.swift`

**Interfaces:**
- None. No behaviour change.

- [ ] **Step 1: Make the change**

**Modify `Sources/CreatorApp/AppBundleInfo.swift`:**

```diff
--- a/Sources/CreatorApp/AppBundleInfo.swift
+++ b/Sources/CreatorApp/AppBundleInfo.swift
@@ -53,5 +53,7 @@ public enum AppBundleInfo {
                     "UTTypeDescription": documentTypeName,
                     "UTTypeConformsTo": [ContentType.json.identifier],
-                    "UTTypeTagSpecification": ["public.filename-extension": [document.preferredFilenameExtension ?? "mcgraph"]],
+                    "UTTypeTagSpecification": [
+                        "public.filename-extension": [document.preferredFilenameExtension ?? "mcgraph"],
+                    ],
                 ] as [String: Any],
             ],
```

**Modify `Sources/CreatorApp/AppModel+Closing.swift`:**

```diff
--- a/Sources/CreatorApp/AppModel+Closing.swift
+++ b/Sources/CreatorApp/AppModel+Closing.swift
@@ -4,6 +4,7 @@ extension AppModel {
     /// The window's `onCloseRequest` (close button, ⌘W, and ⌘Q, which asks each window in turn). With unsaved changes
     /// it shows the Save / Don't Save / Cancel alert and answers `.later`; the answer reaches the window through
-    /// `replyToCloseRequest`. A typed but uncommitted inspector value counts as a change, so it is committed first. A request that arrives while
-    /// the question is open answers `.later` again and puts the alert back if another alert replaced it.
+    /// `replyToCloseRequest`. A typed but uncommitted inspector value counts as a change, so it is committed first. A
+    /// request that arrives while the question is open answers `.later` again and puts the alert back if another alert
+    /// replaced it.
     public func closeRequested() -> CloseRequestReply {
         guard closeRequest == .idle else {
```

**Modify `Sources/CreatorApp/AppModel+Scene.swift`:**

```diff
--- a/Sources/CreatorApp/AppModel+Scene.swift
+++ b/Sources/CreatorApp/AppModel+Scene.swift
@@ -31,8 +31,9 @@ extension AppModel {
 
     /// Shows the scene and the selected nodes' handles. In Final preview the scene also carries the selected rules'
-    /// edges on solids it doesn't show, as guides (not while sketching). While picking, only the solid being picked on, with the
-    /// picked edges selected, no handles and a crosshair pointer. While sketching, the scene dimmed (ghosted, still
-    /// pickable) and no handles, and the open sketch follows its node. A scene or handles equal to what's shown aren't
-    /// sent again: the observation also fires for canvas pans, camera settles and panel resizes, which change neither.
+    /// edges on solids it doesn't show, as guides (not while sketching). While picking, only the solid being picked on,
+    /// with the picked edges selected, no handles and a crosshair pointer. While sketching, the scene dimmed (ghosted,
+    /// still pickable) and no handles, and the open sketch follows its node. A scene or handles equal to what's shown
+    /// aren't sent again: the observation also fires for canvas pans, camera settles and panel resizes, which change
+    /// neither.
     func refreshScene() {
         refreshSketch()
```

**Modify `Sources/CreatorApp/AppRoot.swift`:**

```diff
--- a/Sources/CreatorApp/AppRoot.swift
+++ b/Sources/CreatorApp/AppRoot.swift
@@ -8,6 +8,6 @@ import MetalUI
 /// readout is drawn over all of those (it never takes the pointer). The add-node palette and a node-library type
 /// being dragged float over everything (spec §6.2), drawn last so nothing clips or covers them. Every view below
-/// reads the app's theme from the environment, and the window's MetalUI controls follow its light or dark (spec
-/// §6.6). All behaviour is in `AppModel`; this is glue.
+/// reads the app's theme from the environment, and the window's MetalUI controls follow its light or dark (spec §6.6).
+/// All behaviour is in `AppModel`; this is glue.
 public struct AppRoot: Component {
     public let model: AppModel
@@ -25,6 +25,8 @@ public struct AppRoot: Component {
             ViewportView(model: model.viewport)
             VStack(alignment: .leading, spacing: AppLayout.margin.px) {
-                ZStack { TopBar(model: model, clearance: Pixels(Float(AppLayout.topBarClearance(titleBarInsets: titleBarInsets)))) }
-                    .frame(height: AppLayout.topBarHeight.px)
+                ZStack {
+                    TopBar(model: model, clearance: Pixels(Float(AppLayout.topBarClearance(titleBarInsets: titleBarInsets))))
+                }
+                .frame(height: AppLayout.topBarHeight.px)
                 PanelArea(model: model)
             }
```

**Modify `Sources/CreatorApp/SceneBuilder.swift`:**

```diff
--- a/Sources/CreatorApp/SceneBuilder.swift
+++ b/Sources/CreatorApp/SceneBuilder.swift
@@ -75,5 +75,6 @@ public enum SceneBuilder {
         var order: [Solid] = []
         var edges: [ObjectIdentifier: Set<EdgeID>] = [:]
-        for set in sets where !set.edges.isEmpty && !scene.contains(where: { !$0.item.isGhost && $0.item.solid === set.solid }) {
+        for set in sets where !set.edges.isEmpty
+            && !scene.contains(where: { !$0.item.isGhost && $0.item.solid === set.solid }) {
             let key = ObjectIdentifier(set.solid)
             if edges[key] == nil { order.append(set.solid) }
```

**Modify `Sources/CreatorApp/SketchStore.swift`:**

```diff
--- a/Sources/CreatorApp/SketchStore.swift
+++ b/Sources/CreatorApp/SketchStore.swift
@@ -12,7 +12,7 @@ import Foundation
 /// - a dimension still wired keeps its stored value: the editor showed (and solved) the wired value, which overrides
 ///   the stored one only while the wire is there (sketcher spec §7).
-/// Reserved names are never touched: they are never sockets (`SketchNode.isReservedDimensionName`).
 /// - a projection the edit added stores its pick under `NodeSetting.projection(reference)` and wires its solid into
 ///   `references` when nothing is wired there; one the edit removed clears its pick.
+/// Reserved names are never touched: they are never sockets (`SketchNode.isReservedDimensionName`).
 enum SketchStore {
     /// A projection to store beside the sketch: the pick, and the output that made the solid it was picked on.
```

**Modify `Sources/CreatorApp/ThemeEditorDock.swift`:**

```diff
--- a/Sources/CreatorApp/ThemeEditorDock.swift
+++ b/Sources/CreatorApp/ThemeEditorDock.swift
@@ -3,7 +3,8 @@ import MetalUI
 /// The theme editor (Themes milestone), floating at the window's top-right corner below the top bar, over the
 /// inspector and down to `bottom` points from the window's bottom edge (above a graph panel docked at the bottom,
-/// `ThemeEditorLayout.bottom(dock:panelHeight:)`), so the graph panel and the viewport show each change as it is made. Drawn over everything else in
-/// the window (`AppWindowRoot`); nothing while it is closed. It contributes the `AppKeyContext.panel` key context,
-/// so the viewport's F, + and − type into its name field (gap M4-a), as they do in the other panels.
+/// `ThemeEditorLayout.bottom(dock:panelHeight:)`), so the graph panel and the viewport show each change as it is made.
+/// Drawn over everything else in the window (`AppWindowRoot`); nothing while it is closed. It contributes the
+/// `AppKeyContext.panel` key context, so the viewport's F, + and − type into its name field (gap M4-a), as they do in
+/// the other panels.
 struct ThemeEditorDock: Component {
     let model: ThemeEditorModel
```

**Modify `Sources/CreatorApp/ThemeMenu.swift`:**

```diff
--- a/Sources/CreatorApp/ThemeMenu.swift
+++ b/Sources/CreatorApp/ThemeMenu.swift
@@ -19,5 +19,6 @@ enum ThemeMenu {
             for theme in section {
                 // Choosing the checked theme writes `false`; selecting it again changes nothing.
-                Toggle(theme.name, isOn: Binding(get: { editor.theme.id == theme.id }, set: { _ in editor.select(theme.id) }))
+                Toggle(theme.name, isOn: Binding(get: { editor.theme.id == theme.id },
+                                                 set: { _ in editor.select(theme.id) }))
             }
             Divider()
```

**Modify `Sources/CreatorViewport/Render/ViewportRenderer.swift`:**

```diff
--- a/Sources/CreatorViewport/Render/ViewportRenderer.swift
+++ b/Sources/CreatorViewport/Render/ViewportRenderer.swift
@@ -4,7 +4,7 @@ import Metal
 
 /// Draws a `ViewportFrame` with Metal (spec §6.3).
-/// - The main pass draws, in order: the background gradient, opaque solids, the ground grid, B-rep edges,
-///   ghosts, guides' selected edges, handles, the view cube (its face names painted on from a label atlas) and the triad. It renders
-///   into its own 4× MSAA colour and depth targets, resolved into the MetalView's target.
+/// - The main pass draws, in order: the background gradient, opaque solids, the ground grid, B-rep edges, ghosts,
+///   guides' selected edges, handles, the view cube (its face names painted on from a label atlas) and the triad. It
+///   renders into its own 4× MSAA colour and depth targets, resolved into the MetalView's target.
 /// - The ID pass writes `PickID`s into an `r32Uint` target (edges 6 points wide).
 /// GPU meshes are cached by mesh serial and dropped once a frame no longer shows them. Every colour comes from the
```

**Modify `Tests/CreatorAppTests/Bench/FilletDragBench.swift`:**

```diff
--- a/Tests/CreatorAppTests/Bench/FilletDragBench.swift
+++ b/Tests/CreatorAppTests/Bench/FilletDragBench.swift
@@ -5,6 +5,6 @@ import Testing
 /// value change. Measured from command to presented frame, as the median over a scripted drag." The §7.2 bracket on
 /// OCCT with its Fillet selected; each step drags the radius handle to a new value (2.00 → 3.48 mm in 0.02 mm steps,
-/// never a value the evaluator has cached; the bracket's edges take up to about 4 mm), then waits for the evaluation, the scene and its meshes, then draws the
-/// window's frame (CPU) and both GPU passes. Prints `BENCH fillet-drag …`.
+/// never a value the evaluator has cached; the bracket's edges take up to about 4 mm), then waits for the evaluation,
+/// the scene and its meshes, then draws the window's frame (CPU) and both GPU passes. Prints `BENCH fillet-drag …`.
 @MainActor
 @Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
```

**Modify `Tests/CreatorAppTests/Bench/GraphPanZoomBench.swift`:**

```diff
--- a/Tests/CreatorAppTests/Bench/GraphPanZoomBench.swift
+++ b/Tests/CreatorAppTests/Bench/GraphPanZoomBench.swift
@@ -50,6 +50,6 @@ struct GraphPanZoomBench {
     }
 
-    /// 130 frames at zoom 1, panning along the rows (docked left, they run across the canvas) from the first row to
-    /// the last, drifting down a little.
+    /// 130 frames at zoom 1, panning along the rows (docked left, they run across the canvas) 16 points a frame and
+    /// drifting down 2 points a frame: 2,080 and 260 points in all, which is not the whole graph.
     @Test func panningFiftyNodes() async throws {
         let transforms = (0..<130).map { step in
```


- [ ] **Step 2: The whole suite, warnings and lint**

```bash
swift build --build-tests 2>&1 | grep 'warning:' | grep -v 'which was built for newer version' | sort -u
swift test 2>&1 | tee /tmp/test.log | grep -E 'recorded an issue|failed after|Test run with'
swiftlint lint --strict | tail -1
```

Expected: no new warning (master has two, both from `ContextMenuTests.swift:140`, `'underPointer' mutated after capture`); exit code 0, no line saying "recorded an issue" or "failed after", 11 "Test run with" lines, **master + 51 = **2193** (no test changes)**; `Found 0 violations`.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "docs: wrap and correct comments in the app and viewport"
```


---

### Task 10: Docs: CLAUDE.md, roadmap, human checks, spec and plan wording, performance labels, MetalUI gaps (DOC-1…DOC-7)

Item by item. **DOC-1**: `CLAUDE.md` paragraph split so “Create nodes only with `NodeRegistry.makeNode`…” is its own line. **DOC-2**: roadmap row reads “Adopted by MetalCreator except M6-c (held for AS-5; plan …)”. **DOC-3 is dropped: already fixed** (the handoff note's first S4 bullet already starts “(Done in S4: …)”). **DOC-4**: spec wording (the R 2.5 sentence now says only what was recorded: “the chamfer also succeeds at R 2.5 (`BRepCheck` validity was recorded at 0.5, 1 and 2 only)”, with no new claim about R 2.5); the kernel-blend-max plan says M6-15 where it means the drag check; the adopt-c10 plan no longer says “the user may overrule it”; the comments plan's test count is already 1751 on master (dropped); `docs/metalui-gaps.md`'s intro no longer defines a status no row uses, and the closed M5-e, M5-f and resize-cursor entries now say “former stopgap”; `GlassPanel.swift`'s two IDs for one gap are explained (MetalUI's item C10-c, logged here as gap C10-a); human checks: C10-3 no longer states MetalUI's spinner period, GR-4 names unit, range, access and optional, S5c-1/EP-4/EP-7/EP-9/GI-6/AS intro are re-wrapped, and the missing check for the Library button at the minimum dock width is **EP-12**. **AV-11 (spec)**: the themes Errata's “Each change is saved at once” gets a parenthesis naming the colour drag as Task 7's one exception. **DOC-5**: the “without culling” and “without culling and level of detail” cells now say they come from a separate run at a different load; a paragraph above the Results table says every unlabelled-as-controlled figure is indicative and that the idle re-run will replace them; the refused-bracket median (100.91 ms at load ≈150) is stated as **not judged** against the 100 ms budget; the repeated figures in `docs/metalui-gaps.md` PERF-b and the carry-over note are replaced by pointers to `performance.md`. No number is invented or re-measured. **DOC-6**: the spec's Errata bullet (face picks) re-wrapped; the other human-check wraps as above. **DOC-7**: CM-7 now says the focus-loss commit has no headless test and asks the tester to record it; NF-1 says what to write if the second warning is unreachable. **Roadmap and CLAUDE.md for the three tracks**: the row “Final-review follow-ups” (✅ code done) names the three plans; a Project-state line in `CLAUDE.md` does the same; and the app track's own facts (pick level guard, open-URL during an alert, the sketch following its plane, renderer buffers, theme colour drag, `--help`) are added to the paragraphs they belong to.

**Files:**
- Modify: `CLAUDE.md`, `docs/superpowers/roadmap.md`, `docs/verification/human-checks.md`, `docs/verification/performance.md`, `docs/metalui-gaps.md`
- Modify: `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`, `docs/superpowers/plans/2026-10-09-kernel-blend-max.md`, `docs/superpowers/plans/2026-10-09-adopt-c10.md`, `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`
- Modify: `Sources/CreatorEditor/GlassPanel.swift` (one doc-comment sentence)

**Interfaces:**
- Adds human-check group **FA** (FA-1…FA-7) and EP-12; adds the roadmap row “Final-review follow-ups”.

- [ ] **Step 1: Make the change**

**Modify `CLAUDE.md`:**

```diff
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -30,4 +30,6 @@ Groups C2 (the editor, §6: entering a group, breadcrumbs, the + sockets, the gr
 section, the viewport and the clipboard inside groups) code is done; its human checks (group GR) are pending.
 Named undo steps (plan `docs/superpowers/plans/2026-10-10-named-undo.md`) code is done; its human checks (group NU) are pending.
+Final-review follow-ups (plans `docs/superpowers/plans/2026-10-10-followups-app.md`, `2026-10-10-followups-editor.md` and
+`2026-10-10-followups-kernel.md`) code is done; the app track's human checks (group FA) are pending.
 
 Module boundaries (dependency order):
@@ -88,5 +90,8 @@ Module boundaries (dependency order):
   `.mctheme` keys; `ThemeRoleTests` pins them to the stored properties). `@MainActor @Observable ThemeStore` holds
   `current`, `select(_:)` and the custom themes (`customs`: duplicate, rename, `setColor`, `setDark`, delete, import,
-  export), saving each change to an injected `ThemeFolder` before showing it (`nil`: memory only, every test's), with
+  export), saving each change to an injected `ThemeFolder` before showing it (`nil`: memory only, every test's; a colour
+  picker's drag is the one exception: `previewColor` shows each sample and `saveColors()` writes once, driven by
+  `ThemeEditorModel.dragColor` after `saveDelay` and by `flush()` on close, and a failed save puts the saved colours
+  back; the folder skips a file named like a built-in in any case, and never writes an id that is not a file name), with
   injected `ThemePreferences` (`UserDefaultsThemePreferences` in the app). `ThemeFile` is the `.mctheme` format
   (version 1; missing roles are Dracula's, unknown ones ignored, a bad colour refused naming its role); custom themes'
@@ -115,5 +120,8 @@ Module boundaries (dependency order):
     MetalUI glue. A `ViewportItem` with `isGuide` is no part of the scene: only its selected edges are drawn, after the
     solids and ghosts (faded where the part hides them), and it never frames, orbits, picks or opens the face menu
-    (`ViewportRenderer+Guides`).
+    (`ViewportRenderer+Guides`). The renderer keeps the triad's, the overlay's and the region fills' GPU buffers between
+    frames: the overlay's key holds the grid's extent and the dashes' zoom, not the pose, so an orbit allocates none, and
+    the fills' buffer is dropped once a frame has no fills (`RendererCacheTests`). `handleLabels()` reads the size through
+    `observedViewSize`, as `overlayLabels()` does. Every scroll or pinch event stops a camera animation started mid-gesture.
   - It depends on Kernel, Geometry, CreatorStyle and MetalUI only, never CreatorGraph. The app shell turns graph outputs into
     `ViewportItem`s and `HandleSpec`s into `ViewportHandle`s.
@@ -202,6 +210,9 @@ Module boundaries (dependency order):
   and opens, saves and exports. Inside a group `AppModel` reads the level through `editor.graph`/`levelResults`: Selected
   node previews the level's selected node, handles and picking work there, and a pick is written through
-  `GraphContent.relativeToLevel`; Final preview and export stay on the top level. Sketch mode is top-level only
-  ("Edit sketch" and New Sketch on Face inside a group say so). `AppInput` installs the window's input once and forwards to the current document.
+  `GraphContent.relativeToLevel` (Done and a viewport click drop a pick whose level is no longer the one shown); Final
+  preview and export stay on the top level. Sketch mode is top-level only
+  ("Edit sketch" and New Sketch on Face inside a group say so). The open sketch follows a wired plane: when it moves the
+  camera looks at it again (`viewport.lookAt`), and when its node fails or its wire goes the sketch stays on the last plane
+  and says so once (`SketchSession.hasPlane`; a plane that is only evaluating again is waited for). `AppInput` installs the window's input once and forwards to the current document.
   The window shell is MetalUI C8's, wired in `MetalCreatorApp`: `Window.onCloseRequest` is `AppModel.closeRequested()`
   (`CloseDecision`; `.later` with unsaved changes, the Save / Don't Save / Cancel alert, `answerSaveChanges(_:)` replying
@@ -210,5 +221,6 @@ Module boundaries (dependency order):
   (`AppModel.windowChrome`), the window keeps its standard title bar (`.hiddenTitleBar` waits for check AS-5, gap C8-a; `TopBar` already pads by
   `AppLayout.topBarClearance`, zero in a standard window), and
-  `App.onOpenURL` is `AppModel.openRequested(_:)` (the path argument goes through `App.open(_:)`).
+  `App.onOpenURL` is `AppModel.openRequested(_:)` (the path argument goes through `App.open(_:)`; a file that arrives while
+  any alert is up is ignored).
   `MetalCreatorApp` is the executable (`OCCTKernel`). It makes the app's `ThemeStore` (`AppThemes.store()`: user
   defaults, `~/Library/Application Support/MetalCreator/Themes`) and its `ThemeEditorModel`, and opens the window on
@@ -216,5 +228,5 @@ Module boundaries (dependency order):
   it, the store in the environment and `.theme(current.controlTheme)` for MetalUI's controls. View ▸ Theme is
   `ThemeMenu` (every theme, then Edit Themes…). `LaunchCommand` parses its command line: a file to open, or the
-  headless `--version`, `--self-test` (`SelfTest`: OCCT, STEP/STL export, MetalUI's shaders) and `--info-plist`.
+  headless `--help`, `--version`, `--self-test` (`SelfTest`: OCCT, STEP/STL export, MetalUI's shaders) and `--info-plist`.
   `AppBundleInfo` is the version's one source; the packaged `Info.plist` is generated from it, never edited.
 
@@ -234,5 +246,6 @@ rebuilds a profile must keep `holes` (copy it and change `plane`, don't re-init
 `.side(loop:segment:)` and `.side(segment:)` means loop 0; never match `.side` with one binding (`case .side(let s)`
 binds the tuple and only warns). The shim orients hole wires against the outer wire; history `operand` on segment
-records is the loop. Loft refuses profiles with holes. Create nodes only with `NodeRegistry.makeNode`. Numbers in node messages use `Locale.messages` (`Double.display`, `Int.display`).
+records is the loop. Loft refuses profiles with holes.
+Create nodes only with `NodeRegistry.makeNode`. Numbers in node messages use `Locale.messages` (`Double.display`, `Int.display`).
 Shim errors: `cocct::user_error` / `set_error` messages are user-facing and unprefixed; any other OCCT exception is prefixed "occt: " by `guarded` and mapped to a generic sentence by `KernelError.plainReason`.
 Every fillet and chamfer result is checked with OCCT's `BRepCheck_Analyzer` (`OCCTShape.isValid`) and never returned when
```

**Modify `Sources/CreatorEditor/GlassPanel.swift`:**

```diff
--- a/Sources/CreatorEditor/GlassPanel.swift
+++ b/Sources/CreatorEditor/GlassPanel.swift
@@ -6,8 +6,9 @@ import MetalUI
 /// with MetalUI C10 in hand): MetalUI's materials (`.ultraThinMaterial` and the rest) are a flat grey fitted to
 /// SwiftUI's, with no backdrop blur and no theme, so they would drop the theme's `glass` role (which the theme editor
 /// lets people set) for a grey no theme chose; and `.blur(radius:)` blurs a view's own pixels, not what is behind it.
-/// A true backdrop blur is MetalUI's C10-c (docs/metalui-gaps.md C10-a), and the viewport behind the panels is a GPU
-/// surface a CPU blur could not read anyway. Public so the app shell's top bar and pick banner (M6) share the chrome.
+/// A true backdrop blur is MetalUI's item C10-c, which docs/metalui-gaps.md logs as gap C10-a, and the viewport behind
+/// the panels is a GPU surface a CPU blur could not read anyway. Public so the app shell's top bar and pick banner (M6)
+/// share the chrome.
 public struct GlassPanel<Body: ElementGroup>: Component {
     let body: Body
     @Environment(ThemeStore.self) var themes: ThemeStore?
```

**Modify `docs/metalui-gaps.md`:**

```diff
--- a/docs/metalui-gaps.md
+++ b/docs/metalui-gaps.md
@@ -8,6 +8,6 @@ which button or gesture, which coordinates, what we do in the meantime.
 Every gap in this file, the MetalUI item that owns it and where it stands, checked against MetalUI master `2155f1e`
 and its branches.
-"Fixed, not adopted" means MetalUI has the API and MetalCreator still runs its stopgap; adopting it is MetalCreator's
-work (the owner named). The sections below keep each gap's full use case.
+A gap marked fixed and adopted no longer has a stopgap in MetalCreator; its entry below keeps the use case and the
+stopgap as they were. The sections below keep each gap's full use case.
 
 | Gap | What | MetalUI item | Status |
@@ -186,7 +186,8 @@ These are labelled M5-a… so they don't clash with the C7 items 1–5 or M4's M
   location is still that drag's, not a `SpatialTapGesture`'s, because a tap's value has no modifiers (GI-a).
   **M5-e. Modifiers on a press** (adds to gap 5, which M4's entry made concrete). Shift-click and ⇧/⌥-drag on the
-  canvas need the modifiers at the press, in the gesture's value. Stopgap: `GraphPanelInput.dragValueModifiers(_:)`
-  returns the set `GraphPanelInput.handle(_:)` tracks from `.modifiersChanged`; C7's `DragGesture.Value.modifiers`
-  replaces its body. A click's location is `GraphPanelInput.spatialTapGesture()`, a zero-distance drag (gap 4).
+  canvas need the modifiers at the press, in the gesture's value. Former stopgap (removed by C7):
+  `GraphPanelInput.dragValueModifiers(_:)` returned the set `GraphPanelInput.handle(_:)` tracked from `.modifiersChanged`
+  until C7's `DragGesture.Value.modifiers` replaced its body. A click's location was
+  `GraphPanelInput.spatialTapGesture()`, a zero-distance drag (gap 4).
 - ✅ **Closed by C7 (graph panel, 2026-10-09):** `.onScrollWheel` pans the canvas by the scroll's delta (momentum
   honoured) and ⌘-scroll zooms about `ScrollEvent.location` (`EditorModel.scrolled(by:at:modifiers:phase:)`; a
@@ -195,7 +196,8 @@ These are labelled M5-a… so they don't clash with the C7 items 1–5 or M4's M
   in `AppInput` stays until keys are scoped (M4-a, M5-b).
   **M5-f. Canvas scroll and pinch** (adds to items 1 and 2). Two-finger scroll should pan the graph canvas and
-  ⌘-scroll or pinch should zoom about the pointer (the `location` in the canvas's local points). Stopgap: drag on empty
-  canvas pans; +/− keys and the header buttons zoom about the pointer (`EditorModel.zoom(in:)`). With M4's viewport
-  in the same window, M4's window-wide keymap takes `=`/`+`/`-` before `onInput` (gap M4-a), so M6 needs a key context.
+  ⌘-scroll or pinch should zoom about the pointer (the `location` in the canvas's local points). Former stopgap (C7
+  replaced the pan; the +/− keys and the header buttons stay): a drag on empty canvas panned, and the keys and buttons
+  zoomed about the pointer (`EditorModel.zoom(in:)`). With M4's viewport in the same window, M4's window-wide keymap
+  takes `=`/`+`/`-` before `onInput` (gap M4-a), so M6 needed a key context.
 - **M5-g. A press elsewhere never clears text focus** (focus-by-click is deliberately not MetalUI policy,
   `Window.focus(_:)` docs). After editing an inspector field, the field keeps Delete, ⌘C/⌘V/⌘Z and Space while the
@@ -280,6 +282,6 @@ Labelled M6-a… so they don't clash with the C7 items 1–5, M4-a… or M5-a…
   `.rowResize` on the bottom dock's (`PanelResizeHandle.pointerStyle(alongWidth:)`).
   **Cursor for the dock's resize edge** (adds to C7 item 5). The graph panel's inner edge is a drag handle and should
-  show a column or row resize cursor. C7's `PointerStyle` has `.columnResize` and `.rowResize` (decision `CI-H`).
-  Adopt them when C7 merges.
+  show a column or row resize cursor. C7's `PointerStyle` has `.columnResize` and `.rowResize` (decision `CI-H`);
+  MetalCreator adopted them when C7 merged.
 
 ## Hit by the viewport's C7 adoption, 2026-10-09
@@ -393,7 +395,7 @@ and after a drag, and draws exactly one frame per drag event.
   camera, yet the window's CPU frame with the graph panel shown is several times the frame with it hidden, close to
   the 60 fps budget: every orbit step rebuilds the panel's nodes. Zooming the 50-node graph out until every node is in
-  view costs about the budget, about 0.5 ms a node rebuilt, so canvas culling (which brought panning well inside the
-  budget) can't help there; MetalCreator's level of detail (no rows below half zoom) takes about a third off such a
-  frame, and what is left is MetalUI's rebuild of nodes that didn't change. Both verdicts are not judged yet (the
+  view costs about the budget, so canvas culling (which brought panning well inside the budget) can't help there;
+  MetalCreator's level of detail (no rows below half zoom) takes a share off such a frame (its figure is in
+  performance.md, from a probe at another load), and what is left is MetalUI's rebuild of nodes that didn't change. Both verdicts are not judged yet (the
   recorded run was not idle); a miss on an idle run waits for C14.
 
```

**Modify `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`:**

```diff
--- a/docs/superpowers/notes/2026-10-07-m0-m1-carryover.md
+++ b/docs/superpowers/notes/2026-10-07-m0-m1-carryover.md
@@ -45,5 +45,5 @@ Read this before writing the M2 and M3 plans.
 - `CancelsTaskNode` test assumes nodes run in the caller's task — revisit with parallel evaluation.
 - ✅ Hard-coded `/opt/homebrew` OCCT prefix: the build still links Homebrew's OCCT through `Package.swift`'s prefix, but `scripts/package-app.sh` bundles the libraries and removes that rpath, so the packaged app doesn't depend on it (Errata (Packaging)).
-- M2 final review residuals (✅ M7 measured `oriented()`: a whole extrude, `oriented()` included, costs well under a millisecond; left as it is; `docs/verification/performance.md`): `oriented()` runs `BRepLib::OrientClosedSolid` on every extrude/revolve/loft even when the volume is already positive (only call it when negative — measure in M7); its boolean return is ignored; note that it works by reversing the solid, like the old code. The non-destructive-boolean test is a regression guard only — a stronger test would read max vertex/edge tolerance of a near-touching tool input (rises from 1e-7 in destructive mode).
+- M2 final review residuals (✅ M7 measured `oriented()`: small beside the extrude it belongs to, left as it is; the figure, from a run that was not idle, is in `docs/verification/performance.md`): `oriented()` runs `BRepLib::OrientClosedSolid` on every extrude/revolve/loft even when the volume is already positive (only call it when negative — measure in M7); its boolean return is ignored; note that it works by reversing the solid, like the old code. The non-destructive-boolean test is a regression guard only — a stronger test would read max vertex/edge tolerance of a near-touching tool input (rises from 1e-7 in destructive mode).
 - ✅ (M4) Before M4: build edge polylines from `BRep_Tool::PolygonOnTriangulation` so lines sit on the face mesh; meshes depend on earlier tessellations (BRepMesh reuses finer triangulation in shared TShapes).
 - ✅ (M3) M3 notes from the M2 review: Edges by Tag should match "picked tags ⊆ face tags" per side (unions merge tag sets); Edges by Direction uses `abs(dot)` and `kind == .line`; Edge Set Op dedupes; Loft rejects sections with different segment counts (Rectangle → Circle) — show a clear message or plan resampling; warn when a picked key contains `.unnamed`.
@@ -160,6 +160,6 @@ Read this before writing the M2 and M3 plans.
 - `AppModel.refreshScene()` re-shows only a changed scene or changed handles; the observation itself still wakes for
   every `viewState` change (it reads `editor.dock`). Narrow it if M7's 50-node pan measurement shows the wake-ups.
-  ✅ (M7) It doesn't: a pan step's model work, the scene refresh's wake-up included, is about a tenth of a
-  millisecond (`docs/verification/performance.md`, the `model` lines).
+  ✅ (M7) It doesn't: a pan step's model work, the scene refresh's wake-up included, is small beside the frame's cost
+  (`docs/verification/performance.md`, the `model` lines; figures from a run that was not idle).
 - The panel's size isn't saved with the file (add `ViewState` fields if wanted; optional keys, no format bump).
 - Handles show only for the selected nodes; nodes not upstream of an Output (and not previewed) have no result, so they
```

**Modify `docs/superpowers/plans/2026-10-09-adopt-c10.md`:**

```diff
--- a/docs/superpowers/plans/2026-10-09-adopt-c10.md
+++ b/docs/superpowers/plans/2026-10-09-adopt-c10.md
@@ -891,5 +891,5 @@ Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS"
 - Produces: nothing new. The behaviour is unchanged on purpose; the test pins it.
 
-The decision (the user may overrule it, see "User decisions" in the handoff): what spec §6.1 asks for is a blur of what is behind a panel. MetalUI C10 has neither half of that. `Material` (`.ultraThinMaterial`, ...) is a flat grey at an alpha fitted to SwiftUI over uniform white and black (`LK-L`: for example thin, dark: grey 0.2105 at 0.5961), with no backdrop blur (divergence 166, "deferred" to C10-c), and `.blur(radius:)` blurs a view's own pixels per leaf, leaving a `MetalView` unblurred (divergence 167), so it cannot soften the viewport behind a panel. Swapping `palette.glass.color` for `.thinMaterial` would make every panel the same grey in every theme, orphaning the theme editor's Glass role (opacity-editable) and Alucard's light glass, for no blur. So `GlassPanel` stays, the doc comments say why, `GlassFillTests` fails if someone swaps the fill, and the missing backdrop blur is the new gap **C10-a** (Task 6). Mutation done in the scratch copy: `.background(.thinMaterial, in: shape)` reddens `aPanelIsFilledWithTheThemesGlassColourAtItsOwnOpacity` and `theGlassColourFollowsTheTheme`.
+The decision (made 2026-10-09; see "User decisions" in the handoff): what spec §6.1 asks for is a blur of what is behind a panel. MetalUI C10 has neither half of that. `Material` (`.ultraThinMaterial`, ...) is a flat grey at an alpha fitted to SwiftUI over uniform white and black (`LK-L`: for example thin, dark: grey 0.2105 at 0.5961), with no backdrop blur (divergence 166, "deferred" to C10-c), and `.blur(radius:)` blurs a view's own pixels per leaf, leaving a `MetalView` unblurred (divergence 167), so it cannot soften the viewport behind a panel. Swapping `palette.glass.color` for `.thinMaterial` would make every panel the same grey in every theme, orphaning the theme editor's Glass role (opacity-editable) and Alucard's light glass, for no blur. So `GlassPanel` stays, the doc comments say why, `GlassFillTests` fails if someone swaps the fill, and the missing backdrop blur is the new gap **C10-a** (Task 6). Mutation done in the scratch copy: `.background(.thinMaterial, in: shape)` reddens `aPanelIsFilledWithTheThemesGlassColourAtItsOwnOpacity` and `theGlassColourFollowsTheTheme`.
 
 - [ ] **Step 1: Write the tests (they pass on the current code: this task pins behaviour)**
```

**Modify `docs/superpowers/plans/2026-10-09-kernel-blend-max.md`:**

```diff
--- a/docs/superpowers/plans/2026-10-09-kernel-blend-max.md
+++ b/docs/superpowers/plans/2026-10-09-kernel-blend-max.md
@@ -24,5 +24,5 @@ Parallel tracks: groups-comments, groups-editor, sketcher-s5c, adopt-c10, naming
 | `docs/verification/performance.md` | the "How to run" suite list gains `BlendRefusalBench`; a new section "Refused blends" before "Raw output" | other tracks' rows and sections; the union of the suite names in "How to run" |
 | `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md` | appends a section at the end | other tracks' appended sections (both stay; order doesn't matter) |
-| `docs/verification/human-checks.md` | extends one pending check, M5-10 (the Fillet radius sentence and its "Pinned" line, about line 232) | other tracks' new and changed checks; if both sides edited M5-10, keep both sides' sentences in it |
+| `docs/verification/human-checks.md` | adds one check, M6-15 (planned as an extension of M5-10's Fillet radius sentence) | other tracks' new and changed checks; if both sides edited M6-15, keep both sides' sentences in it |
 | `Tests/CreatorOCCTTests/FeatureConformanceTests.swift` | one test's assertions (`impossibleFilletFailsCleanlyAndKernelRecovers`) | any other test in the file |
 | `Tests/CreatorAppTests/Bench/` | adds `BlendRefusalBench.swift` and `BlendRefusalFixtureTests.swift` only | other benchmark files |
@@ -1068,5 +1068,5 @@ index e98fd63..3ae5b38 100644
 +  blend costs tens of milliseconds more than one that works, on §8's hexagon flange and on the §7.2 bracket's Fillet
 +  node alike. While the Fillet's radius handle is dragged past the maximum, each step pays that search; the evaluation
-+  is off the main actor and cancellable. Human check M5-10 covers the drag.
++  is off the main actor and cancellable. Human check M6-15 covers the drag.
 +- `BRepCheck_Analyzer` runs on every blend result: a few milliseconds on the flange union. Watch it on large parts
 +  (`docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`).
@@ -1137,5 +1137,5 @@ index 458d189..5d274ea 100644
 ```
 
-`docs/verification/human-checks.md` (M5-10, the one pending check that drags a Fillet radius past its maximum):
+`docs/verification/human-checks.md` (M6-15, the one pending check that drags a Fillet radius past its maximum):
 
 ```diff
@@ -1180,5 +1180,5 @@ Expected: each name appears and exists in `Sources/CreatorOCCT`.
 ```bash
 git add docs CLAUDE.md
-git commit -m "docs: blend maximum errata, roadmap, performance record, carry-over note and the M5-10 drag check"
+git commit -m "docs: blend maximum errata, roadmap, performance record, carry-over note and the M6-15 drag check"
 ```
 
@@ -1187,5 +1187,5 @@ git commit -m "docs: blend maximum errata, roadmap, performance record, carry-ov
 ## Self-review
 
-- **Spec coverage:** §3/§10 "max ≈ where possible" for a not-built blend: Task 3. The four minors: size ≤ 0.1 mm (Task 2), `fails` without overshoot (Task 2), -1 to the generic message (Task 1), analyzer cost noted in the carry-over note (Task 5). Measurement on bracket and flange in release: Task 4, recorded in Task 5 (figures in `performance.md` only). Roadmap row and spec errata: Task 5. `maxRadius` 9.9: Task 3. The visible change (a refused Fillet drag): the M5-10 human check, Task 5.
+- **Spec coverage:** §3/§10 "max ≈ where possible" for a not-built blend: Task 3. The four minors: size ≤ 0.1 mm (Task 2), `fails` without overshoot (Task 2), -1 to the generic message (Task 1), analyzer cost noted in the carry-over note (Task 5). Measurement on bracket and flange in release: Task 4, recorded in Task 5 (figures in `performance.md` only). Roadmap row and spec errata: Task 5. `maxRadius` 9.9: Task 3. The visible change (a refused Fillet drag): the M6-15 human check, Task 5.
 - **Placeholder scan:** none; every code step is a complete file or a diff from verified code. The only values that depend on the executor's machine are the measurements, stated as such.
 - **Type consistency:** `OCCTValidity` (Task 1) → `check:` closures and `attempt(blending:…)`; `BlendGrid.firstFailingTenths(for:)` and `triesSmallest(below:)` (Task 2) used by `largestValidBlend` and `invalidBlend`; `blendFailed(size:chamfer:largest:)` (Task 3) replaces the Task 1 form, and Task 1's `InvalidBlendTests` case reaches it only through `blend`, so Task 3 breaks no earlier test. The Task 1 `blend` calls `KernelError.blendFailed(size:chamfer:)`; Task 3 replaces that whole file.
```

**Modify `docs/superpowers/roadmap.md`:**

```diff
--- a/docs/superpowers/roadmap.md
+++ b/docs/superpowers/roadmap.md
@@ -46,4 +46,5 @@ Status key: ✅ done · 🔄 in progress · ⏳ ready to start · 🔒 blocked (
 | — | Named undo steps: label `UndoStack.Entry`/`DocumentModel.perform` so the Edit menu and the top bar read "Undo Add Note" for every edit, not only comments (Comments (B) User decision 1 kept its undo steps unnamed; plan `2026-10-10-named-undo.md`) | ✅ code done; human checks NU pending | Comments (B); touches `DocumentModel`, `UndoStack`, `AppCommands`, `TopBar` |
 | — | Comments: typing on the canvas — edit a note's text or a frame's title in place on the canvas (spec §8) | ⏳ after MetalUI C9 + the canvas double-click (C16) | Comments (B); gaps CM-a, S5-b |
+| — | Final-review follow-ups: the findings the final reviews left open, in three plans by module — `2026-10-10-followups-app.md` (app, viewport, packaging, themes, docs), `2026-10-10-followups-editor.md` (editor, groups) and `2026-10-10-followups-kernel.md` (kernel, nodes, sketch) | ✅ code done; human checks FA (app) pending, the other plans' checks as they name them | Named undo steps |
 
 ## Cross-project dependencies
@@ -52,5 +53,5 @@ Status key: ✅ done · 🔄 in progress · ⏳ ready to start · 🔒 blocked (
 |---|---|---|
 | MetalUI C7 "Input API gaps for MetalCreator" (scroll, pinch/rotate, middle/right drag, tap location, cursor + drag modifiers) | MetalUI session | ✅ merged as MetalUI c62d6ba (PR #56), 2026-10-09; final names in MetalUI `docs/superpowers/2026-10-08-input-apis-decisions.md` (CI-A…CI-AL). Adopted by the viewport; graph panel and app still to adopt |
-| MetalUI C8 app shell: M6-b close/quit veto (first), M6-a title + edited marker, M6-c hidden title bar, M6-d open-document events | MetalUI session | ✅ merged as MetalUI 70e9389 (PR #61), 2026-10-09; final names in `docs/superpowers/2026-10-08-app-shell-decisions.md` (AS-A…AS-Q), record §87. Adopted by MetalCreator (plan `2026-10-09-adopt-c8`) |
+| MetalUI C8 app shell: M6-b close/quit veto (first), M6-a title + edited marker, M6-c hidden title bar, M6-d open-document events | MetalUI session | ✅ merged as MetalUI 70e9389 (PR #61), 2026-10-09; final names in `docs/superpowers/2026-10-08-app-shell-decisions.md` (AS-A…AS-Q), record §87. Adopted by MetalCreator except M6-c (held for AS-5; plan `2026-10-09-adopt-c8`) |
 | MetalUI C9 key and focus scoping: M4-a/M5-b hover- or region-scoped keys + element size, M5-g press ends editing, M5-h ↑/↓ in fields, M4-b redraw during animation | MetalUI session | 🔄 in progress since 2026-10-09; also onGeometryChange, the for-loop builder fix (M4-b; until then `ForEach` works), TimelineView, focus-on-click |
 | MetalUI C10 controls and looks: M6-f ColorPicker (needed by Themes), M5-a Slider onEditingChanged, M5-c blur, M5-d gradients, M5-i keyframes, M5-j ProgressView | MetalUI session | ✅ merged 2155f1e (PR #59); ColorPicker adopted by Themes Task 11, the rest by the row "Adopt MetalUI C10" |
```

**Modify `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`:**

```diff
--- a/docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md
+++ b/docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md
@@ -520,10 +520,11 @@ Plan `2026-10-09-naming-merged-faces.md`, roadmap row "Naming: picks on merged f
   reports success but returns a solid that `BRepCheck_Analyzer` rejects, and on it every fillet or chamfer along the
   plate top's tangent chain fails (at 0.5, 0.2 and 0.05 mm alike), while the same resolved edges chamfer on the union
   before the fillet. It depends on the fillet radius: `BRepCheck`-valid at R 0.5, 1 and 2, where the chamfer
-  succeeds; through the graph the chamfer also succeeds at R 2.5; invalid at the bracket's R3. So the Chamfer stays
-  in error and the Output has no result, until the kernel rejects or repairs invalid blend results (roadmap row
-  "Kernel: blends that return an invalid solid"). (Superseded: see Errata (Kernel: invalid blends); the test below is
-  now `swappingTheFlangeForAPolygonKeepsEveryPickOnceTheFilletFits`.)
+  succeeds; through the graph the chamfer also succeeds at R 2.5 (`BRepCheck` validity was recorded at 0.5, 1 and 2
+  only); invalid at the bracket's R3. So the Chamfer stays in error and the Output has no result, until the kernel
+  rejects or repairs invalid blend results (roadmap row "Kernel: blends that return an invalid solid"). (Superseded:
+  see Errata (Kernel: invalid blends); the test below is now
+  `swappingTheFlangeForAPolygonKeepsEveryPickOnceTheFilletFits`.)
   `BracketAcceptanceTests.swappingTheFlangeForAPolygonKeepsEveryPickButTheFilletedHexagonCantBeChamfered` pins it, and
   `BracketAcceptanceTests.aChamferPickedOnMergedSidesSurvivesTheFlangeChangingWidth` pins the case end to end with no
   warning or error (the flange alone made 40 or 70 mm wide, so no plate side stays merged).
@@ -555,10 +556,10 @@ picks with no position).
   side (`EdgeKey.operandKeys`): the rim of a hole through a face a union merged is `{plate.side, flange.side} |
   {hole.wall}` and the wall shares no node call with either. When several operands' keys name edges, the one with the
   recorded edge count wins if exactly one has it; otherwise the nearest count wins and Edges by Tag warns
-  (`EdgeTagMatch.ambiguousPick`), as does a Sketch projection (`SketchProjections.locate`). A count summed over several reference solids is never
-  compared with one operand's, and a pick with edge ordinals that resolved through one operand's share of its key is a
-  guess too (the ordinals were recorded against the whole key's edges). An edge where two operands meet keeps its full
-  name, and a key that matches anything or narrows is never split.
+  (`EdgeTagMatch.ambiguousPick`), as does a Sketch projection (`SketchProjections.locate`). A count summed over several
+  reference solids is never compared with one operand's, and a pick with edge ordinals that resolved through one
+  operand's share of its key is a guess too (the ordinals were recorded against the whole key's edges). An edge where
+  two operands meet keeps its full name, and a key that matches anything or narrows is never split.
 - The case with the flange wider than the plate: the hole's rim at the bracket's left side is then the flange's own
   face (x = -35), so the pick follows the hole to that face rather than staying on the plate.
   `BracketAcceptanceTests.aPlanePickedOnAMergedSideSurvivesTheFlangeChangingWidth`, `...BecomingAPolygon` and
@@ -581,9 +582,10 @@ Plan `2026-10-09-themes-editor.md` (roadmap row "Themes").
   theme, is refused with a sentence. An import never replaces a theme: a taken name becomes "<name> 2".
 - Custom themes live in `~/Library/Application Support/MetalCreator/Themes`, one `<id>.mctheme` per theme (the id
   survives renames); a file that can't be read is skipped and the editor says which and why. Each change is saved at
-  once. The chosen theme is remembered in the user's defaults (`selectedThemeID`), which replaces Errata (M6)'s "isn't
-  remembered between launches either"; a remembered theme that is gone falls back to Dracula. Themes are still
-  app-level and never in a `.mcgraph`.
+  once (a colour picker's drag is shown at once and saved once it pauses for 300 ms, and when the editor or the window
+  closes: plan `2026-10-10-followups-app.md`, Task 7). The chosen theme is remembered in the user's defaults
+  (`selectedThemeID`), which replaces Errata (M6)'s "isn't remembered between launches either"; a remembered theme
+  that is gone falls back to Dracula. Themes are still app-level and never in a `.mcgraph`.
 - The theme editor is a floating glass panel at the window's top right, below the top bar and over the inspector,
   down to the window's bottom margin or, with the graph panel docked at the bottom, to a margin above it, so the graph
   panel and the viewport show each edit as it is made (a second window would end the app when closed until
```

**Modify `docs/verification/human-checks.md`:**

```diff
--- a/docs/verification/human-checks.md
+++ b/docs/verification/human-checks.md
@@ -173,7 +173,7 @@ Run `swift run MetalCreatorApp` on a saved bracket, with a trackpad and a wheel
 - [ ] **GI-6 Cursors.** Middle-drag the canvas: a closed hand from the press until the release, also when the pointer
   leaves the panel mid-drag (since multi-select a plain drag on empty canvas box-selects, MS-3); a click shows none.
-  Moving nodes, dragging a wire and box selection keep the arrow. Hover the dock's inner edge: a left-right resize cursor docked left, an up-down one docked at the bottom,
-  kept while dragging it. Pinned: `CanvasCursorTests`, `theLeftDocksEdgeIsAColumnResizeAndTheBottomDocksARowResize`.
-  **Observed:**
+  Moving nodes, dragging a wire and box selection keep the arrow. Hover the dock's inner edge: a left-right resize
+  cursor docked left, an up-down one docked at the bottom, kept while dragging it. Pinned: `CanvasCursorTests`,
+  `theLeftDocksEdgeIsAColumnResizeAndTheBottomDocksARowResize`. **Observed:**
 - [ ] **GI-7 The palette.** Open the palette (Space) over the canvas, then scroll or pinch over the canvas outside
   it: it closes. Open it again and scroll over the palette itself: the canvas doesn't move and the palette stays.
@@ -379,11 +379,11 @@ for C10-5.
   back: it does not shake. Drag a node normally: no shake. Pinned: `RefusalShakeTests` (the keyframes at injected times, the
   per-node count, a refused node drawn at rest). **Observed:**
-- [ ] **C10-3 Evaluating spinner.** Make a node slow (a Boolean or a large-radius fillet on a dense part) and edit
-  it: its badge shows a small spinner of twelve spokes turning once every 0.8 seconds, then the time in ms. The spinner fits
-  the header and reads on every header colour (value, profile, solid, selection rule, feature, output) in Dracula and in
-  Alucard. Select the busy node: the inspector header's badge shows the same spinner, readable on its background (its
-  colour is MetalUI's control accent, not the old status grey: accepted, user decision 4).
-  While it turns, panning the canvas stays smooth; note the frame rate (a spinner redraws the whole window each
-  frame, PERF-b). Pinned: `StatusBadgeRenderTests` (the still frame), `statusBadges`. **Observed:**
+- [ ] **C10-3 Evaluating spinner.** Make a node slow (a Boolean or a large-radius fillet on a dense part) and edit it:
+  its badge shows a small spinner of twelve spokes turning steadily (MetalUI sets its period), then the time in ms. The
+  spinner fits the header and reads on every header colour (value, profile, solid, selection rule, feature, output) in
+  Dracula and in Alucard. Select the busy node: the inspector header's badge shows the same spinner, readable on its
+  background (its colour is MetalUI's control accent, not the old status grey: accepted, user decision 4). While it
+  turns, panning the canvas stays smooth; note the frame rate (a spinner redraws the whole window each frame, PERF-b).
+  Pinned: `StatusBadgeRenderTests` (the still frame), `statusBadges`. **Observed:**
 - [ ] **C10-4 Slider undo.** Select a node with a slider (Extrude's Distance): drag the slider, then ⌘Z once: the whole drag
   is undone and the value returns to what it was before the press. Drag it again twice with nothing in between: two ⌘Z. Use a
@@ -422,9 +422,9 @@ Run `swift run MetalCreatorApp` (EP-1–EP-9, EP-11) and `swift run GraphPanelPr
   `theWindowsPressesReachThePaletteUnclaimed`. **Observed:**
 - [ ] **EP-4 The library's place.** A new window shows the library, captioned "Nodes" above its "Search nodes" field:
-  docked at the bottom, a column at the canvas's left edge; docked left, a strip across the canvas's top. It lists Value, Profile, Solid, Selection,
-  Feature and Output, each under a header in that category's node-header colour, and scrolls when it doesn't fit.
-  Press Library in the header: it goes and the canvas takes its room; press it again: it's back. Hide it, save, and
-  reopen the file: it's still hidden, and the top bar never showed "— Edited" for it. Pinned: `LibraryViewTests`,
-  `itIsShownByDefaultAndItsVisibilityIsSavedButNotAnEdit`. **Observed:**
+  docked at the bottom, a column at the canvas's left edge; docked left, a strip across the canvas's top. It lists
+  Value, Profile, Solid, Selection, Feature and Output, each under a header in that category's node-header colour, and
+  scrolls when it doesn't fit. Press Library in the header: it goes and the canvas takes its room; press it again: it's
+  back. Hide it, save, and reopen the file: it's still hidden, and the top bar never showed "— Edited" for it. Pinned:
+  `LibraryViewTests`, `itIsShownByDefaultAndItsVisibilityIsSavedButNotAnEdit`. **Observed:**
 - [ ] **EP-5 Click to add.** Pan and zoom the canvas, then click Extrude in the library: an Extrude appears in the
   middle of the visible canvas, selected. Click it a few more times: each lands near the middle, wholly in view, none
@@ -442,7 +442,7 @@ Run `swift run MetalCreatorApp` (EP-1–EP-9, EP-11) and `swift run GraphPanelPr
   `theDragGhostIsDrawnAtThePointerOnlyWhileDragging`, `aDraggedLibraryTypeIsPaintedOverTheWindow`; the gesture in a
   scrolling list is this check only. **Observed:**
-- [ ] **EP-7 Hover help.** Rest the pointer on Extrude in the library: after about a second a tooltip reads
-  "Extrude: profile, distance, mode, reversed → solid". Search "fil": only Selection ▸ Edge Filter and Feature ▸ Fillet
-  stay (the palette's matches for "fil"); clear the field: everything is back. Pinned: `hoverHelpNamesInputsThenOutputs`,
+- [ ] **EP-7 Hover help.** Rest the pointer on Extrude in the library: after about a second a tooltip reads "Extrude:
+  profile, distance, mode, reversed → solid". Search "fil": only Selection ▸ Edge Filter and Feature ▸ Fillet stay (the
+  palette's matches for "fil"); clear the field: everything is back. Pinned: `hoverHelpNamesInputsThenOutputs`,
   `theSearchIsThePalettes`. **Observed:**
 - [ ] **EP-8 Themes.** View ▸ Theme ▸ Alucard: the library's background, headers and text, and the palette's glass,
@@ -450,7 +450,7 @@ Run `swift run MetalCreatorApp` (EP-1–EP-9, EP-11) and `swift run GraphPanelPr
   `theLibraryRedrawsInTheChosenTheme`, `aSectionHeaderIsItsCategorysHeaderColour`, `theLibraryRasterizesNothing`.
   **Observed:**
-- [ ] **EP-9 Still quick.** With the library shown, drag a node around the §7.2 bracket's graph, drag a library
-  type across the window, and scroll the library: it feels as it did before the library (PERF-b still rebuilds the whole window; the library's `List`
-  builds only the rows in view). **Observed:**
+- [ ] **EP-9 Still quick.** With the library shown, drag a node around the §7.2 bracket's graph, drag a library type
+  across the window, and scroll the library: it feels as it did before the library (PERF-b still rebuilds the whole
+  window; the library's `List` builds only the rows in view). **Observed:**
 - [ ] **EP-10 The preview.** In `GraphPanelPreview` (its window keeps one size), EP-1's placement holds in both
   docks, and the library works as in EP-4–EP-7 with the preview's nine node types. **Observed:**
@@ -465,4 +465,8 @@ Run `swift run MetalCreatorApp` (EP-1–EP-9, EP-11) and `swift run GraphPanelPr
   `aNodeUnderTheLibraryColumnIsHiddenByIt`, `aNodeAboveTheCanvasNeverCoversTheHeader`,
   `aNodeAtANegativeCanvasPositionDrawsWhole`. **Observed:**
+- [ ] **EP-12 The header at the minimum width.** Drag the dock's edge to its narrowest (240 points) with the library
+  shown: the 28 pt header's title, Library button and the dock and hide buttons do not overlap or get cut off, and each
+  can still be pressed. **Record what gives way first** (the title, or a button). Pinned: `GraphPanelLayout`'s header
+  height only; the crowding itself is this check only. **Observed:**
 
 ## Group P — the packaged app (packaging)
@@ -498,11 +502,12 @@ Run `scripts/package-app.sh` first; it ends with `==> Wrote …/dist/MetalCreato
 Run `swift run MetalCreatorApp` for AS-1 to AS-5, and `scripts/package-app.sh` first for AS-6 and AS-7. The model's side
 of each check is pinned headless (`AppModelCloseTests`, `WindowChromeTests`, `AppModelOpenURLTests`,
-`TitleBarClearanceTests`, `TopBarClearanceRenderTests`, `SaveChangesAnswerTests`); what MetalUI's window, menu and Finder do with it is these checks only (gap M6-e).
+`TitleBarClearanceTests`, `TopBarClearanceRenderTests`, `SaveChangesAnswerTests`); what MetalUI's window, menu and
+Finder do with it is these checks only (gap M6-e).
 
-Product decisions behind these checks (the user approved the recommended default of each on 2026-10-09/10): (1) the hidden
-title bar (not merged; the window is standard) ships only if AS-5 shows the window drags, as its own commit; (2) a Finder open of the file already open does
-nothing; (3) a typed but uncommitted inspector value counts as a change when a Finder open arrives; (4) the top bar keeps
-the name and "— Edited"; (5) close and quit share one alert; (6) an open onto edited work asks "Discard unsaved changes?".
-Gap C8-a was reported to the MetalUI session on 2026-10-10.
+Product decisions behind these checks (the user approved the recommended default of each on 2026-10-09/10): (1) the
+hidden title bar (not merged; the window is standard) ships only if AS-5 shows the window drags, as its own commit; (2)
+a Finder open of the file already open does nothing; (3) a typed but uncommitted inspector value counts as a change when
+a Finder open arrives; (4) the top bar keeps the name and "— Edited"; (5) close and quit share one alert; (6) an open
+onto edited work asks "Discard unsaved changes?". Gap C8-a was reported to the MetalUI session on 2026-10-10.
 
 - [ ] **AS-1 Close with unsaved changes.** In an empty window add a node, then press the close button. A sheet asks "Do
@@ -789,5 +794,6 @@ warnings read well where they appear.
   by a test, since the app can't pick a face yet), then unmerge it so the choice is a guess (a pick made before
   positions were recorded). (2) Edges by Tag's ambiguous-pick warning: a hole rim picked on a merged side, then a
-  change after which two parts each have a rim. Record which of the two you could reach. Pinned:
+  change after which two parts each have a rim. Record which of the two you could reach (the second needs both operands to have a rim after an edit; if you can't
+  get there, write that, the tests pin both). Pinned:
   `aPlanePickWithoutAPositionWarnsOnceTheFaceHasComeApart`, `aGuessBetweenOperandsIsReportedNotSilent`.
   **Observed:**
@@ -837,5 +843,7 @@ on a saved bracket, docked at the bottom; CM-9 docks left.
   frame: a title field and the swatches; Return commits "Front plate"; clearing it and pressing Return refuses with
   "A frame needs a title." and the old title returns. Select two comments: "2 comments selected". Pinned:
-  `CommentInspectorTests`. **Observed:**
+  `CommentInspectorTests`. The field losing focus commits the text, and no headless test reaches that (a focus loss
+  needs a real window, gap M6-e): only the model-level commit is pinned, so **record whether clicking away from the text
+  box, not only onto the canvas, commits it.** **Observed:**
 - [ ] **CM-8 Saving.** Save with notes and frames, close, reopen: they are where they were, with their text, titles and
   accents; ⌘Z has nothing to undo. Open a file saved before comments: it opens unchanged. Editing a note marks the
@@ -872,9 +880,10 @@ plate and its extrude (select both, ⌘G) first.
   viewport follows every edit. ⌘Z until the group itself is undone while inside: the panel falls back to the top
   level. Pinned: `EditorLevelTests`, `EditorGroupClipboardTests`, `EditorLevelReviewTests`. **Observed:**
-- [ ] **GR-4 The + sockets.** Inside, drag from a node's output onto Group Output's "+": a new output appears on
-  Group Output named after the socket, wired, and the group node outside has it too; one ⌘Z removes both. Drag from
-  Group Input's "+" onto an unwired input: a new input, wired, with the target's default; one ⌘Z removes it. Drag the
-  wire from the node's socket to the "+" instead of the other way: the same. Drag an output onto Group Input's "+":
-  the hint appears and nothing changes. Pinned: `ExposeSocketTests`. **Observed:**
+- [ ] **GR-4 The + sockets.** Inside, drag from a node's output onto Group Output's "+": a new output appears on Group
+  Output named after the socket, wired, and the group node outside has it too; one ⌘Z removes both. Drag from Group
+  Input's "+" onto an unwired input: a new input, wired, with the target's default, unit, range, access and optional
+  (Errata (C2)); one ⌘Z removes it. Drag the wire from the node's socket to the "+" instead of the other way: the same.
+  Drag an output onto Group Input's "+": the hint appears and nothing changes. Pinned: `ExposeSocketTests`.
+  **Observed:**
 - [ ] **GR-5 The inspector.** Select the group node: name, accent, "Used 1 time", Edit Group, Make Unique, Ungroup, and
   its inputs. Rename it (Return, or click away): its nodes and the library follow. Duplicate it (⌘D): "Used 2 times".
@@ -911,10 +920,12 @@ plate and its extrude (select both, ⌘G) first.
 there is a box, then a Sketch (select it, "Edit sketch").
 
-- [ ] **S5c-1 Project an edge.** In a sketch on the XY plane, press P ("Project ✓") and click one of the box's top edges: a
-  purple line appears on the plane (nothing highlights the edge under the pointer while you aim: only faces highlight, a
-  known gap, see Errata (S5c); a click takes the edge whose pixels it lands on). In the graph, the Sketch node now
-  has a wire into `references` from the box's Extrude. The tool stays on Project after the click (click a second edge without pressing P again). One ⌘Z removes the line, the wire and the stored pick together. The purple line is real geometry: draw a closed shape that uses it and the fill appears. Draw a line ending on the purple line: "Point on" appears and the point stays on it
-  when you drag. Change the Rectangle's width in the graph and the purple line follows. Pinned: `ProjectToolTests`,
-  `SketchProjectTests`. **Observed:**
+- [ ] **S5c-1 Project an edge.** In a sketch on the XY plane, press P ("Project ✓") and click one of the box's top
+  edges: a purple line appears on the plane (nothing highlights the edge under the pointer while you aim: only faces
+  highlight, a known gap, see Errata (S5c); a click takes the edge whose pixels it lands on). In the graph, the Sketch
+  node now has a wire into `references` from the box's Extrude. The tool stays on Project after the click (click a
+  second edge without pressing P again). One ⌘Z removes the line, the wire and the stored pick together. The purple line
+  is real geometry: draw a closed shape that uses it and the fill appears. Draw a line ending on the purple line: "Point
+  on" appears and the point stays on it when you drag. Change the Rectangle's width in the graph and the purple line
+  follows. Pinned: `ProjectToolTests`, `SketchProjectTests`. **Observed:**
 - [ ] **S5c-2 Project a face, and what can't be projected.** Press P and click the box's top face: all four of its edges
   project. Click a vertical edge: the inspector says "That edge can't be projected: it is perpendicular to the sketch
@@ -993,2 +1004,33 @@ saved bracket.
 - [ ] **NU-8 Files.** Save, close and reopen: the Edit menu reads plain "Undo" and "Redo" (names are not saved). New does the
   same. Pinned: `aNewDocumentStartsWithPlainTitles`. **Observed:**
+
+## Group FA — final-review follow-ups (app, viewport, docs)
+
+**Status: NOT RUN.** Plan `2026-10-10-followups-app.md`. Run `swift run MetalCreatorApp`. The tests pin the models and the
+renderer's buffers; these check what a real window shows.
+
+- [ ] **FA-1 A moved plane.** On a box (Rectangle, Extrude, Output), right-click its top face and choose New Sketch on
+  Face; the sketch opens on the face's plane. While it is open, change the Extrude's distance in the graph: the plane
+  moves with the face, the camera looks at it again (animated) and the sketch stays open, drawn on it. Then delete the
+  wire into the Sketch node's `plane`: one alert, "The plane lost its result", saying that nothing is wired into
+  "plane" now, and the sketch stays open on the last plane; further edits raise no second alert. Pinned:
+  `SketchPlaneFollowTests`. **Observed:**
+- [ ] **FA-2 Handle labels after Open.** Save a document with the camera moved, quit, reopen it, and select an Extrude
+  at once, before touching the viewport: its "10 mm" label stands beside the knob. Resize the window while it is
+  selected: the label follows the knob. Pinned: `handleLabelsAreRebuiltWhenTheDrawRecordsTheFirstSize`. **Observed:**
+- [ ] **FA-3 Scroll or pinch during a camera move.** Zoom with the wheel or a pinch and press F (or click a view cube
+  face) in the middle of it: the next scroll or pinch step continues from what is on screen, with no jump when the
+  animation would have finished. Pinned: `aScrollEventStopsAnAnimationStartedMidScroll`,
+  `aPinchEventStopsAnAnimationStartedMidPinch`. **Observed:**
+- [ ] **FA-4 A sketch orbit stays smooth.** In a sketch, orbit is locked to the plane, so pan and zoom the sketch with a
+  dashed construction line and the grid on: the grid, the dashes and the points draw exactly as before, and a pan or zoom
+  is no slower. Leave the sketch: the faint region fill goes. Pinned: `RendererCacheTests`. **Observed:**
+- [ ] **FA-5 A colour drag.** Duplicate a theme, open Edit Themes… and drag a colour picker's selection around
+  continuously: the window recolours smoothly with no stutter. Stop dragging, wait a second, quit and reopen: the last
+  colour is kept. Drag again and quit at once (⌘Q): the colour is still kept. Pinned: `ThemeColorDragTests`,
+  `ThemeColorPreviewTests`. **Observed:**
+- [ ] **FA-6 A file arrives while an alert is up.** With the Save / Don't Save question up (edit, then ⌘W), or after a
+  failed Open, double-click a `.mcgraph` in Finder: the alert on screen stays as it is and nothing opens behind it. Press
+  OK, double-click again: it opens. Pinned: `AppModelOpenURLTests`. **Observed:**
+- [ ] **FA-7 The command line.** In the packaged app (`scripts/package-app.sh`), running
+  `MetalCreator.app/Contents/MacOS/MetalCreator --help` prints the usage and exits 0; `--info-plist ٢٦` is a usage error
+  (exit 64). Pinned: `LaunchCommandTests`. **Observed:**
```

**Modify `docs/verification/performance.md`:**

```diff
--- a/docs/verification/performance.md
+++ b/docs/verification/performance.md
@@ -48,4 +48,8 @@ What headless can't show, so the numbers are an upper bound for the CPU and a lo
 ## Results
 
+Figures in this file that did not come from one controlled run (the same machine, load and commit for both sides of a
+comparison) are labelled as such where they appear. They are indicative only. An idle-machine re-run is pending and will
+replace them.
+
 2026-10-09, MacBook Pro (MacBookPro18,2, Apple M1 Max, 10 cores), macOS 27.0.1, MetalUI `2155f1e`, MetalCreator
 `71ec6fc` (branch `m7-measure`). Load averages (1, 5, 15 minutes) 22.54 / 33.70 / 58.73 before the run and 11.92 / 26.99 / 53.35
@@ -57,6 +61,6 @@ at any load.
 | §7.3 target | Benchmark | Measured (median, p95) | Budget | Verdict | A miss belongs to |
 |---|---|---|---|---|---|
-| Panning a 50-node graph at 60 fps | `pan-50` | CPU 13.09 ms (p95 14.79), GPU 3.25 ms; the canvas builds 16 of 50 nodes (max 20) | 16.67 ms | **Met** (with canvas culling; 26.63 ms without it, indicative: a separate run at a different load) | — |
-| Zooming a 50-node graph at 60 fps | `zoom-50` | CPU 15.03 ms (p95 17.56, max 36.06), GPU 3.38 ms; 25 of 50 nodes built (all 50 zoomed out), with level of detail | 16.67 ms | **Not judged: within noise at load 22.54 / 33.70 / 58.73** (median under the budget, p95 over; 26.53 ms without culling and level of detail, indicative: a separate run at a different load) | MetalUI C14 (PERF-b), if it misses on an idle run |
+| Panning a 50-node graph at 60 fps | `pan-50` | CPU 13.09 ms (p95 14.79), GPU 3.25 ms; the canvas builds 16 of 50 nodes (max 20) | 16.67 ms | **Met** (with canvas culling; 26.63 ms without it is from a separate run at a different load, so not a controlled comparison) | — |
+| Zooming a 50-node graph at 60 fps | `zoom-50` | CPU 15.03 ms (p95 17.56, max 36.06), GPU 3.38 ms; 25 of 50 nodes built (all 50 zoomed out), with level of detail | 16.67 ms | **Not judged: within noise at load 22.54 / 33.70 / 58.73** (median under the budget, p95 over; 26.53 ms without culling and level of detail is from a separate run at a different load, so not a controlled comparison) | MetalUI C14 (PERF-b), if it misses on an idle run |
 | Fillet radius drag: viewport updated within 100 ms of each value change | `fillet-drag` | command-to-frame 43.14 ms (p95 45.59): evaluate + mesh 20.44 ms, window CPU 16.91 ms, GPU 5.44 ms; 75 of 75 steps showed a new part | 100 ms | **Met** | — |
 | Orbiting the bracket at 60 fps | `orbit-panel-left` | CPU 16.01 ms (p95 17.70), GPU 5.11 ms | 16.67 ms | **Not judged: within noise at load 22.54 / 33.70 / 58.73** (median at the budget's edge, p95 over): each orbit step rebuilds the graph panel too | MetalUI C14 (PERF-b), if it misses on an idle run |
@@ -135,4 +139,8 @@ the search on every step, so its error appears about 100 ms after the drag, not
 radius 8.25 to 9.20 met (OCCT not done, or the checker rejecting) is not recorded; both run the same search.
 
+Against the 100 ms budget for the fillet drag (spec §7.3), the bracket's refused evaluation (median 100.91 ms, p95
+255.27 ms) sits at the budget's edge, but the run was at a load of about 150, far from idle, so it is **not judged**:
+neither inside nor outside the budget until the idle re-run replaces these figures. (The “works” cases are well inside it.)
+
 ## Raw output
 
```


- [ ] **Step 2: At merge time, apply the other tracks' sentences**

This track merges last (order: editor, kernel, app). Both other plans exist; their names and sections were checked when this plan was revised.

1. **Kernel**, `docs/superpowers/plans/2026-10-10-followups-kernel.md`, section “**CLAUDE.md sentences for the app track**” (it edits no `CLAUDE.md` itself). Apply its four sentences:
   1. “drift counts edges and runs (`EdgePick.runCount` …)” (CLAUDE.md line about edge picks, near line 225): add “a run is edges that continue each other end to end (ends within 1e-4 mm, leaving that point in opposite directions to within 0.01 rad), so two edges meeting at a corner are two runs”.
   2. The loft line (near line 236): “Loft refuses profiles with holes, before it compares segment counts (`KernelError.loftWithHoles`).”, and the general rule “Numbers in node and kernel messages use `Locale.messages` (defined in CreatorKernel; `Double.display`, `Int.display` in CreatorNodes; `KernelError.userMessage` uses it too).” **This merges with DOC-1's split in Task 10**: DOC-1 turns that one line into “Loft refuses profiles with holes.” on its own line and a second line “Create nodes only with `NodeRegistry.makeNode`. Numbers in node messages use `Locale.messages` …”. Put the kernel's loft wording on the first of those lines and its `Locale.messages` wording on the second (the two general rules stay their own line, as DOC-1 and the kernel plan both ask).
   3. “`FakeKernel` for tests” (near line 38): add “(it refuses extruded holes that lie outside the outline's bounds, as OCCT refuses strays)”.
   4. The sketch paragraph (S4, near lines 170-178): add “a constraint or dimension on a projected edge of the wrong kind is skipped and named in a warning, like one on a suspended edge”.
2. **Editor**, `docs/superpowers/plans/2026-10-10-followups-editor.md`, Task 18 (it edits `CLAUDE.md` itself, so there is no list to apply): keep its one clause in the named-undo paragraph (`SketchCommit.init` and `EditorModel.edit` require `name:`), and its new section `Errata (F: editor follow-ups)` at the end of `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md`. It adds no sentence for this track to apply.
3. Tick the roadmap row only when their code is merged too. Keep every Errata bullet and spec edit they made (the kernel adds one after the rule-6 bullet of “Errata (naming: merged faces)”, right beside this track's R 2.5 hunk, and one at the end of “Errata (S4)” in the constraint-sketcher spec; neither plan edits `roadmap.md` or `human-checks.md`). In `docs/verification/human-checks.md` nobody else adds anything, but append rather than reorder if one of them does by then. Re-run the full suite and SwiftLint after the merge.

- [ ] **Step 3: The whole suite, warnings and lint**

```bash
swift build --build-tests 2>&1 | grep 'warning:' | grep -v 'which was built for newer version' | sort -u
swift test 2>&1 | tee /tmp/test.log | grep -E 'recorded an issue|failed after|Test run with'
swiftlint lint --strict | tail -1
```

Expected: no new warning (master has two, both from `ContextMenuTests.swift:140`, `'underPointer' mutated after capture`); exit code 0, no line saying "recorded an issue" or "failed after", 11 "Test run with" lines, **master + 51 = **2193** (no test changes)**; `Found 0 violations`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs: follow-ups round: CLAUDE.md, roadmap, human checks FA and EP-12, performance labels, wording fixes"
```


---



## User decisions

Each is written into the plan at its recommended default.

1. **How to say “the plane lost its result” (ED-15).** The triage wants it in the sketch inspector. *Options:* (a) an alert, once, when the plane is lost (**recommended**; in `CreatorApp`, no module change); (b) a line in the sketch inspector (needs `CreatorSketchEditor`, the kernel track's module, plus an inspector slot); (c) say nothing. If you want (b), it is a small follow-up on top of this plan: `SketchEditorModel.refusal` is `internal(set)`, so the editor would need a public `notice`.
2. **A file opened while an alert is up (ED-16).** *Options:* ignore it (**recommended**: the visible question stays and Discard opens the file it was about); queue it until the alert is answered. Ignoring costs one more double-click after OK.
3. **`--help` (AV-10).** *Options:* add it (**recommended**: prints the usage, exit 0, listed in `usage`); or only fix the doc comment that mentions it.
4. **Extra arguments after a file (AV-10).** *Options:* keep ignoring them (**recommended**; Xcode appends its own flags after the file, and the test pins it); or make them a usage error.
5. **Coalescing theme colour writes (AV-11a).** The themes contract (the Errata's “Each change is saved at once”, the code's “saved before it is shown”) is relaxed: a drag now shows each sample and writes once, 300 ms after it pauses, on Done and when the window is asked to close. *Options:* coalesce (**recommended**); keep write-through (no change; a slow disk can stutter the picker); write only on picker end (MetalUI's `ColorPicker` has no such callback, and neither does SwiftUI's, so this is not a gap). The residual risk of coalescing is a crash within 300 ms of a drag losing that colour.

## New MetalUI gaps

None. (Considered and rejected: a “picker drag ended” callback for `ColorPicker`: SwiftUI's has none either, so the debounce is not a workaround for a gap.)

## Risks

- Task 7 deliberately relaxes “saved before shown” for colour drags only; a crash inside the debounce loses the last drag. Mitigated by `flush()` on Done and on close.
- Task 3's key change is exact by construction (the instances are a pure function of the key), and `aReusedOverlayDrawsThePixelsAFreshRendererDoes` compares pixels, but the headless render is skipped without a Metal device; human check FA-4 covers the real window.
- Task 6 changes shell that only a release build exercises (about 2 minutes). Run it in a scratch copy; the plan's check is by running, not by unit test.
- Merge conflicts are listed under “Files shared”; the likeliest is `CLAUDE.md`'s loft-holes line and the end of `human-checks.md`.
- The editor-track cosmetic wraps are left undone here, and the editor plan does not take them either (checked), so they remain open: `EditorModel.swift:25`, `EditorModel+Nudge.swift:6`, `EditorModel+Pinch.swift:14`, `GraphCanvas.swift:3-5`, `Cursor.swift:3-5`, `GroupCommands+Ungroup.swift`. Comments only.
- Task 6's swap is two renames, not one atomic step: a crash between them leaves `dist/.MetalCreator.app.old` and no `dist/MetalCreator.app` (the next run cleans it). Only a real power cut or kill -9 in that instant does it; the scripts were re-run after this change, but crash-in-the-window was not exercised.
- The wired-plane alert (Task 1) is an alert, not an inspector line (User decision 1), and now has two sentences; whether FA-1's wire-removal case reads well is for the human check.
- `swift test` can print only 10 “Test run with” lines when the first run after a checkout drops one target's summary (seen once in about 14 runs; the rerun printed 11). Rerun before judging.
- The roadmap row and `CLAUDE.md` name `2026-10-10-followups-editor.md` and `2026-10-10-followups-kernel.md`; both files now exist under those names. The editor plan's count line still read “None tests (master + ?)” when checked, so the roadmap row quotes no combined test count.

## Self-review

- **Spec coverage.** ED-1, ED-15, ED-16: Task 1. AV-1 (with AV-6) and AV-7: Task 2. AV-2, AV-3, AV-4: Task 3. AV-5, AV-12: Task 4. AV-10: Tasks 5 (Swift) and 6 (scripts). AV-11: Task 7. AV-9: Task 8. AV-8: dropped with reasons. DOC-1…DOC-7: Tasks 9 (code part of DOC-6) and 10. The roadmap row, CLAUDE.md and human checks for all three tracks: Task 10 (this track's own parts; the other tracks' sentences at merge time, step “At merge time”).
- **Placeholders.** None: every code block is the exact content verified in the scratch copy; there are no “TODO”s.
- **Type consistency.** `triadBuffer`, `triadInstances`, `GridExtent`, `gridExtent`, `gridLines(_:)`, `instances(_:grid:millimetresPerPoint:scale:palette:)`, `OverlayBufferKey(overlay:grid:dashZoom:scale:palette:)`, `previewColor`/`saveColors`/`hasUnsavedColors`/`show`, `dragColor`/`flush`/`saveDelay`, `SketchSession.hasPlane`, `LaunchCommand.help` and `HandleBuilder.bisector(of:)` are defined in exactly one task and used with the same names in the tests.
- **Review Focus.** Each of the five lines has a named test above.

## Verification (scratch copy)

The plan was applied task by task in a scratch copy of the worktree (sibling `MetalUI` symlinked to `/Users/maxburger/Developer/MetalUI`), one commit per task. After each task: `swift build --build-tests` (no warning beyond the two from `ContextMenuTests.swift:140` that master already has, and the expected OpenCascade “built for newer version” linker lines), `swift test` (exit 0, no “recorded an issue” or “failed after”, 11 “Test run with” lines) and `swiftlint lint --strict` (0 violations). Counts: Task 1 **2151** (master + 9); Task 2 **2157** (+15); Task 3 **2163** (+21); Task 4 **2173** (+31); Task 5 **2177** (+35); Task 6 **2177** (+35, scripts only; also run at that commit: 2177, 11 lines, after a first run at that commit printed 10 lines, see Risks); Task 7 **2190** (+48); Task 8 **2193** (+51); Tasks 9 and 10 **2193** (+51). Tests per task that fail on master are listed in each task's Step 2; mutation checks were run for the wheel debounce (three mutations) and the checker retry. `scripts/package-app.sh` and `scripts/verify-app.sh` were run in the scratch copy only (Task 6): packaging passed; the tampered-copy check failed as described. The final tip was run once more in full after the review round: exit 0, 2193, 11 lines, no “recorded an issue” or “failed after”, 0 violations, no new warning; `scripts/package-app.sh` was re-run at that tip (131 s of CPU): `verify: passed` on the staged copy, `Wrote …/dist/MetalCreator.app`, over an existing `dist/MetalCreator.app`, and no `.staging` or `.old` folder left in `dist`. A plain master run was 2142 in 11 lines, as the brief says.
