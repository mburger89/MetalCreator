# Named Undo Steps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every undo step carries a short user-facing name, and the Edit menu and the top bar read "Undo <name>" / "Redo <name>" (plain "Undo"/"Redo" with nothing to take back), as macOS apps do.

**Architecture:** `UndoStack.Entry` gains a `name`; `DocumentModel.perform(_:at:coalescingKey:name:)` takes it from the caller, who knows the intent (constants in a new `UndoName`), and falls back to the generic "Edit" when the caller gives none or a blank one (so a forgotten name is visible, never a guess from the command); a coalesced run keeps its first record's name. The sketch editor's commits carry a fixed `SketchCommit.name` (`SketchStepName`: "Add Line", "Change Dimension"), never the finer `description`, which holds typed text and numbers. `DocumentModel.undoName`/`redoName` feed `AppModel.undoTitle`/`redoTitle`, the only things `AppCommands` and `TopBar` show. Names live in memory only: no file-format change.

**Tech Stack:** Swift 6.4 strict concurrency, Swift Testing, `@MainActor @Observable` models, MetalUI (unchanged), SwiftLint.

**Spec:** `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` §7 ("every change is one undo step ('Add Note', 'Edit Note', 'Add Frame', 'Move', 'Resize', 'Delete')") and its Errata (B: comments) "Undo names" note; roadmap row "Named undo steps" in `docs/superpowers/roadmap.md`; parent spec `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` §4.5 (undo and coalescing) and §6.1 (the menu bar and top bar), with all its Errata. Executors read all of them.

**Branch and baseline:** worktree `/Users/maxburger/Developer/MetalCreator-undo`, branch `named-undo`, off master `af4d99f` (2096 tests). Run every command from that worktree; never `cd` into another worktree or `/Users/maxburger/Developer/MetalCreator`; never edit `Package.swift`'s `../MetalUI` path; never modify `../MetalUI`; no screenshots.

**Shared files:** no other track runs in parallel (this is the only one; MetalUI is a separate repository). Files that later tracks are likely to touch too, and what the side that merges second must keep: `Sources/CreatorGraph/DocumentModel.swift` and `UndoStack.swift` (keep the `name:` parameter and `undoName`/`redoName`; a later `perform` caller must pass a name or its step reads "Undo Edit"), `Sources/CreatorSketchEditor/SketchCommit.swift`, `SketchEditorModel.swift` and every `SketchEditorModel+*.swift` that calls `commit(_:_:named:)` (keep `name` on `SketchCommit`, the required `named:` argument and `apply(_:_:)`'s name; a new sketch tool passes a `SketchStepName`), `Tests/CreatorSketchEditorTests/SketchEditorModelTests.swift` (two `commit` calls gain `named:`), `Sources/CreatorEditor/EditorModel+Editing.swift`, `+Pointer.swift`, `+Inspector.swift`, `+Groups.swift`, `+GroupInspector.swift`, `+CommentCreation.swift`, `+CommentInspector.swift`, `Sources/CreatorApp/AppModel+Picking.swift`, `+Sketch.swift`, `+NewSketch.swift`, `+Viewport.swift` (keep each call's `name:`/`named:` argument and the `insert(_:offset:named:)`, `addRule(...named:)` signatures), `Sources/CreatorApp/AppCommands.swift` and `TopBar.swift` (keep `Button(model.undoTitle)` / `Button(model.redoTitle)`), and `CLAUDE.md`, `docs/superpowers/roadmap.md`, `docs/verification/human-checks.md` and the comments spec's Errata (B) (keep the Named undo steps paragraph, the NU group and the "Undo names" bullet; add rather than replace).

## Global Constraints

- Swift 6 strict concurrency; Swift Testing (`@Test`, `#expect`, `#require`); `@MainActor @Observable` models; behaviour in models and thin views (the titles come from `AppModel.undoTitle`/`redoTitle`, the views only show them); one type per file.
- No force unwraps, no force `try`, no GCD; `FormatStyle` for numbers and dates. Names carry no numbers (so no `Locale.messages` formatting is needed); where a number must appear, use the app's `Locale.messages` style (none does in this plan).
- Strings are English and use the app's existing message style: short title-case verb phrases ("Add Note", "Change Width"). Names are never saved: `.mcgraph` stays at its current format version and no file key is added.
- A name never contains text the person typed (a note's text, a frame's title, a group's, parameter's or dimension's name) and never a number. Fixed library text (a node type's title, an input's label, a constraint's fixed kind) is allowed. The sketch editor's `SketchCommit.description` ("Rename d1 to Plate width", "Fillet Point 2 (5 mm)") is never a step name: its commits carry a fixed `SketchCommit.name` instead (User decision 1).
- `swiftlint lint --strict` reports zero violations before every commit (140-column lines, vertically aligned parameters, trailing commas in multi-line literals).
- MetalUI gaps go in `docs/metalui-gaps.md` (the entry and the summary table row) and are never worked around. This plan finds none (see Task 5: the menu bar re-evaluates `commands` content whenever it is needed, MetalUI ruling `MN-I`, so a dynamic title needs nothing from MetalUI).
- A full `swift test` run passes only if the exit code is 0, no line says "recorded an issue" or "failed after" (Swift Testing prints glyphs, not ✘), and 11 "Test run with" lines appear. Use plain `swift test` (not `--build-system native`, which prints one aggregate run line). Count tests by adding the 11 "Test run with N tests" lines.
- New or changed lines add no compiler warnings (master has exactly one, `ContextMenuTests.swift:140` "'underPointer' mutated after capture by sendable closure").
- Test counts: master has 2096. After Task 1: master + 10 = 2106; Task 2: master + 26 = 2122; Task 3: master + 35 = 2131; Task 4: master + 41 = 2137; Task 5: master + 46 = 2142; Task 6 (docs only): 2142.

## Review Focus

The inputs and failure modes the spec implies but a straight reading of the tasks would not test, most likely first. Each has a test in the task that owns the code.

1. **A slider drag or arrow run is one step and keeps its first name.** The second and later records of a coalesced run carry other names or none (a later record's `name` is ignored); Undo then shows the first. Pinned in Task 1 (`aCoalescedRunKeepsItsFirstRecordsName`, `theStackKeepsOneNamePerEntryAndFirstWinsInARun`) and Task 2 (`anInputIsChangedByItsLabelAndASliderDragKeepsTheFirstName`, `aHeldArrowIsOneStepCalledMove`, `aMoveDragIsOneStepCalledMove`).
2. **A blank or whitespace name.** A caller can pass `""` and a `SketchCommit` can carry a blank `name`. Expect "Edit" (or "Edit Sketch" for a sketch commit), never an empty "Undo " title. Pinned: `aBlankNameFallsBackToEdit` (Task 1), `aSketchCommitIsNamedByItsFixedStepName` (Task 4).
3. **Typed text and numbers never leak into a name.** A parameter called "Plate width", a group renamed "Rib", a node or group called "My own name", a sketch dimension renamed "Plate width", a fillet of 2.5 mm, a pattern of 4: the menu says "Change Parameter", "Rename Group", "Add Group", "Rename Dimension", "Fillet", "Circular Pattern". Pinned: `aParameterIsChangedWithoutItsTypedName`, `groupDefinitionEditsEachHaveTheirOwnName` (Task 2), `inputNamesUseTheLabelWhenThereIsOne` (Task 1), `dimensionStepsHaveFixedNamesWhateverTheDimensionIsCalled`, `filletsHaveNoRadiusInTheirName`, `trimExtendMirrorAndPatternsAreNamed` (Task 3), `aRenamedDimensionNeverReachesTheMenu` (Task 4).
4. **Titles after New and Open.** A fresh document has no history, so both titles are plain. Pinned: `aNewDocumentStartsWithPlainTitles` (Task 5). Open goes through the same `load(_:from:)`.
5. **A call site that forgets its name.** There is no per-command fallback, so an unnamed `perform` shows as "Undo Edit" and every test of a call site fails if the call loses its `name:` (checked by removing it from nudge, connect, delete, edit note, move, disconnect, handle drag, New Sketch on Face, edge picks and a sketch step in the scratch copy: each failed a test). Step 4 of Task 6 greps the call sites.
6. **A refused edit records nothing, so it names nothing.** Pinned: `aRefusedEditRecordsNoName` (Task 1). Also checked by hand: a long title in the top bar (`NU-2`) and a typed, uncommitted inspector value (`NU-7`; the title names the step before it until the value commits; see Risks in the return notes).

## File Structure

New files (one type or one suite each):

- `Sources/CreatorGraph/UndoName.swift`: `UndoName`, the catalog of step names and the two label-taking builders.
- `Sources/CreatorSketchEditor/SketchStepName.swift`: `SketchStepName`, the fixed names of the sketch editor's steps (CreatorSketchEditor does not depend on CreatorGraph, so it has its own catalog).
- `Tests/CreatorGraphTests/UndoNameTests.swift`, `Tests/CreatorEditorTests/EditorUndoNameTests.swift`, `Tests/CreatorSketchEditorTests/SketchStepNameTests.swift`, `Tests/CreatorAppTests/AppUndoNameTests.swift`, `Tests/CreatorAppTests/UndoTitleTests.swift`.

Modified files:

- `Sources/CreatorGraph/UndoStack.swift`, `DocumentModel.swift`: the name on the entry; `name:` on `perform`; `undoName`/`redoName`.
- `Sources/CreatorEditor/EditorModel+Levels.swift`, `+Editing.swift`, `+Pointer.swift`, `+Nudge.swift`, `+Inspector.swift`, `+CommentCreation.swift`, `+CommentInspector.swift`, `+Groups.swift`, `+GroupInspector.swift`, `+Expose.swift`: every edit passes its name.
- `Sources/CreatorSketchEditor/SketchCommit.swift`, `SketchEditorModel.swift` and its `+Commands`, `+Copies`, `+Dimensions`, `+Drag`, `+Drawing`, `+Fillet`, `+Project`, `+Selection` extensions: a commit carries a fixed `name`.
- `Sources/CreatorApp/AppModel+Viewport.swift`, `+Picking.swift`, `+NewSketch.swift`, `+Sketch.swift`: the viewport and sketch edits pass theirs; `AppModel+Undo.swift`, `AppCommands.swift`, `TopBar.swift`: the titles.
- `Tests/CreatorEditorTests/CommentEditingTests.swift`: one call gains `named:`. `Tests/CreatorSketchEditorTests/SketchEditorModelTests.swift`: two `commit` calls gain `named:`.
- `CLAUDE.md`, `docs/superpowers/roadmap.md`, `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md`, `docs/verification/human-checks.md`: docs.

Every `DocumentModel.perform` call site (24 in `Sources`) and every `SketchEditorModel.commit` (21) is covered: Editor (`Editing` x4: connect, delete/cut, insert for paste/duplicate/copy-drag, add node; `Pointer` x3; `Nudge`; `Inspector` x3; `CommentCreation`; `CommentInspector`; `Groups`; `GroupInspector`; `Expose` x2; `Levels.edit`), App (`Viewport`, `Picking` x3 incl. `addRule`, `NewSketch`, `Sketch`). `ThemeEditorModel.perform` is unrelated (themes). Any future caller that passes no name still works: its step is called "Edit" (`UndoName.edit`). That is deliberately coarse: it is not one of the names the callers use, so a missing name fails the test of its call site.

## Naming rules (the design)

| Edit | Name | Where given |
|---|---|---|
| Add node (palette, library, drop) | "Add <node type's title>", "Add Group" for a group node, "Add Node" if untitled | `EditorModel.add(_:)` |
| Connect / Disconnect (incl. drag off an input) | "Connect" / "Disconnect" | `connect`, `finishWire` |
| Delete / Cut / Paste / Duplicate (also ⌥-drag) | "Delete" / "Cut" / "Paste" / "Duplicate" | `delete(named:)`, `insert(_:offset:named:)` |
| Node or comment drag, arrow nudge | "Move" | `+Pointer`, `+Nudge` |
| Comment handle drag | "Resize" | `+Pointer` |
| Inspector input | "Change <label>", "Clear <label>" (e.g. "Change Width") | `setInput`, `clearInput` |
| Document parameter | "Change Parameter" | `setParameter` |
| Add Note / Add Frame / Frame Selection | "Add Note" / "Add Frame" | `+CommentCreation` |
| Note text or accent / frame title or accent | "Edit Note" / "Edit Frame" | `+CommentInspector` |
| Group / Ungroup / Make Unique | "Group" / "Ungroup" / "Make Unique" | `+Groups` |
| Group inspector | "Rename Group", "Change Group Accent", "Rename Socket", "Move Socket", "Remove Socket", "Delete Group" | `+GroupInspector` |
| Group Input / Output "+" | "Add Input Socket" / "Add Output Socket" | `+Expose` |
| Viewport handle drag | "Drag Handle" | `AppModel.handleChanged` |
| Pick edges (Done) / Select Edges of Face | "Pick Edges" / "Select Edges of Face" | `+Picking` |
| New Sketch on Face | "New Sketch on Face" | `+NewSketch` |
| Sketch editor steps | fixed by kind, `SketchCommit.name`: "Add Point", "Add Line", "Add Circle", "Add Arc", "Add Constraint", "Add Dimension", "Change Dimension", "Rename Dimension", "Expose Dimension", "Stop Exposing Dimension", "Make Dimension Driving", "Make Dimension Reference", "Make Construction", "Make Normal Geometry", "Move Point", "Delete", "Trim", "Extend", "Fillet", "Mirror", "Linear Pattern", "Circular Pattern", "Project"; a blank name is "Edit Sketch" | `SketchEditorModel` (`SketchStepName`), shown by `+Sketch` |
| Anything else (no name) | "Edit" | `UndoName.edit`, in `DocumentModel.perform` |

---

### Task 1: Names on the undo stack and the document

**Files:**
- Create: `Sources/CreatorGraph/UndoName.swift`
- Modify: `Sources/CreatorGraph/UndoStack.swift`, `Sources/CreatorGraph/DocumentModel.swift`
- Test: `Tests/CreatorGraphTests/UndoNameTests.swift` (new, 10 tests)

**Interfaces:**
- Consumes: `GraphCommand`, `Node`, `GroupNodes.groupTypeID` (all in `CreatorGraph`). No per-command fallback exists: a step with no name is "Edit".
- Produces:
  - `UndoName` (enum): `static let` constants listed below; `static func addNode(_ node: Node) -> String`; `static func changeInput(_ label: String) -> String`; `static func clearInput(_ label: String) -> String`; internal `static func cleaned(_ name: String?) -> String?` (trimmed, `nil` when blank).
  - `UndoStack.Entry.name: String`; `UndoStack.record(forward:inverse:coalescingKey:name:)` with `name` defaulting to `UndoName.edit` (for the direct callers in `CommandTests`; `DocumentModel` always passes one); `UndoStack.undoName`, `redoName: String?`.
  - `DocumentModel.perform(_:coalescingKey:name:)`, `DocumentModel.perform(_:at:coalescingKey:name:)` (`name: String? = nil`), `DocumentModel.undoName`, `redoName: String?`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorGraphTests/UndoNameTests.swift`:

```swift
import CreatorGeometry
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// Every undo step carries a short name (named undo steps; groups-and-comments spec §7): the caller's, else one from
/// the command; a coalesced run keeps its first record's.
@MainActor
struct UndoNameTests {
    let a = makeNode(ConstantNode.self, ["value": .number(1)])
    let b = makeNode(AddNode.self)

    func model() -> DocumentModel {
        DocumentModel(file: GraphFile(graph: graph([a, b])), registry: testRegistry, kernel: FakeKernel())
    }

    @Test func aFreshDocumentHasNoNames() {
        let document = model()
        #expect(document.undoName == nil && document.redoName == nil)
    }

    @Test func aCallersNameIsTheStepsName() throws {
        let document = model()
        try document.perform(.move(a.id, to: Vector2(5, 5)), name: UndoName.resize)
        #expect(document.undoName == "Resize")
        try document.perform(.move(a.id, to: Vector2(9, 9)), at: .root, name: "Nudge it")
        #expect(document.undoName == "Nudge it", "the at: overload takes a name too")
    }

    @Test func withoutANameTheStepIsCalledEdit() throws {
        let document = model()
        try document.perform(.setInput(a.id, "value", .number(2)))
        #expect(document.undoName == "Edit", "no name, no guess from the command: a caller that forgets shows up as Edit")
        try document.perform(.connect(link(a, "value", b, "a")), at: .root)
        #expect(document.undoName == "Edit")
        document.undo()
        #expect(document.redoName == "Edit" && document.undoName == "Edit")
    }

    @Test func aBlankNameFallsBackToEdit() throws {
        let document = model()
        try document.perform(.move(a.id, to: Vector2(1, 1)), name: "  \n")
        #expect(document.undoName == "Edit")
        try document.perform(.move(a.id, to: Vector2(2, 2)), name: "")
        #expect(document.undoName == "Edit")
        try document.perform(.move(a.id, to: Vector2(3, 3)), name: "  Slide  ")
        #expect(document.undoName == "Slide", "a name is trimmed")
    }

    @Test func undoAndRedoWalkTheNames() throws {
        let document = model()
        try document.perform(.move(a.id, to: Vector2(1, 1)), name: "First")
        try document.perform(.move(a.id, to: Vector2(2, 2)), name: "Second")
        #expect(document.undoName == "Second" && document.redoName == nil)
        document.undo()
        #expect(document.undoName == "First" && document.redoName == "Second", "Redo names the step Undo took back")
        document.undo()
        #expect(document.undoName == nil && document.redoName == "First")
        document.redo()
        #expect(document.undoName == "First" && document.redoName == "Second")
        try document.perform(.move(a.id, to: Vector2(3, 3)), name: "Third")
        #expect(document.redoName == nil, "a new edit clears Redo")
    }

    @Test func aCoalescedRunKeepsItsFirstRecordsName() throws {
        let document = model()
        try document.perform(.setInput(a.id, "value", .number(2)), coalescingKey: "drag", name: "Change Value")
        try document.perform(.setInput(a.id, "value", .number(3)), coalescingKey: "drag", name: "Something Else")
        try document.perform(.setInput(a.id, "value", .number(4)), coalescingKey: "drag")
        #expect(document.undoName == "Change Value")
        document.undo()
        #expect(document.undoName == nil, "one step")
        #expect(document.redoName == "Change Value")
    }

    @Test func endingTheRunStartsAStepWithItsOwnName() throws {
        let document = model()
        try document.perform(.move(a.id, to: Vector2(1, 1)), coalescingKey: "drag", name: "Move")
        document.endCoalescing()
        try document.perform(.move(a.id, to: Vector2(2, 2)), coalescingKey: "drag", name: "Resize")
        #expect(document.undoName == "Resize")
        document.undo()
        #expect(document.undoName == "Move")
    }

    @Test func aRefusedEditRecordsNoName() {
        let document = model()
        #expect(throws: GraphError.self) { try document.perform(.removeNode(NodeID()), name: "Delete") }
        #expect(document.undoName == nil)
    }

    @Test func theStackKeepsOneNamePerEntryAndFirstWinsInARun() {
        var stack = UndoStack()
        let id = NodeID()
        stack.record(forward: .setInput(id, "v", .number(1)), inverse: .setInput(id, "v", nil), coalescingKey: "k", name: "One")
        stack.record(forward: .setInput(id, "v", .number(2)), inverse: .setInput(id, "v", .number(1)), coalescingKey: "k", name: "Two")
        #expect(stack.undoEntries.map(\.name) == ["One"] && stack.undoName == "One")
        stack.record(forward: .move(id, to: .zero), inverse: .move(id, to: .zero), coalescingKey: nil)
        #expect(stack.undoEntries.map(\.name) == ["One", "Edit"], "a record with no name is the generic \"Edit\"")
        _ = stack.takeUndo()
        #expect(stack.redoName == "Edit" && stack.undoName == "One")
    }

    @Test func inputNamesUseTheLabelWhenThereIsOne() {
        #expect(UndoName.changeInput("Width") == "Change Width" && UndoName.changeInput("") == "Change Input")
        #expect(UndoName.clearInput("Width") == "Clear Width" && UndoName.clearInput("") == "Clear Input")
        var node = makeNode(ConstantNode.self)
        node.name = "Box"
        #expect(UndoName.addNode(node) == "Add Box")
        node.name = "  "
        #expect(UndoName.addNode(node) == "Add Node", "a node with no title")
        let doubler = Doubler()
        var instance = instance(of: doubler.definition)
        instance.name = "My own name"
        #expect(UndoName.addNode(instance) == "Add Group", "a group node's name is the person's, so it is not used")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter UndoNameTests`
Expected: build FAIL with "type 'DocumentModel' has no member 'undoName'", "cannot find 'UndoName' in scope", "extra argument 'name' in call".

- [ ] **Step 3: Implement**

Create `Sources/CreatorGraph/UndoName.swift`:

```swift
import Foundation

/// The short, user-facing names of undo steps (the Edit menu reads "Undo Add Note"). A name says what the person did, in
/// the app's plain English, and carries no numbers; text the person typed (a note, a group's name) is never put in one.
/// Callers that know the intent pass one of these to `DocumentModel.perform(_:at:coalescingKey:name:)`; a caller that
/// gives none gets the generic `edit` ("Undo Edit"). Undo names are in memory only: they are never saved.
public enum UndoName {
    // MARK: Nodes and wires
    public static let connect = "Connect"
    public static let disconnect = "Disconnect"
    public static let delete = "Delete"
    public static let cut = "Cut"
    public static let paste = "Paste"
    public static let duplicate = "Duplicate"
    public static let move = "Move"
    public static let resize = "Resize"
    /// A node added from the palette or the library: "Add Box" (its type's title). A group node is "Add Group",
    /// whatever its definition is called, and a node with no title is "Add Node".
    public static func addNode(_ node: Node) -> String {
        if node.typeID == GroupNodes.groupTypeID { return "Add Group" }
        let title = node.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Add Node" : "Add \(title)"
    }
    /// An inspector input changed: "Change Width"; cleared: "Clear Width". `label` is the input's fixed label.
    public static func changeInput(_ label: String) -> String { label.isEmpty ? "Change Input" : "Change \(label)" }
    public static func clearInput(_ label: String) -> String { label.isEmpty ? "Clear Input" : "Clear \(label)" }
    public static let changeParameter = "Change Parameter"

    // MARK: Comments (canvas comments spec §7)
    public static let addNote = "Add Note"
    public static let editNote = "Edit Note"
    public static let addFrame = "Add Frame"
    public static let editFrame = "Edit Frame"

    // MARK: Groups (groups spec §5, §6)
    public static let group = "Group"
    public static let ungroup = "Ungroup"
    public static let makeUnique = "Make Unique"
    public static let renameGroup = "Rename Group"
    public static let changeGroupAccent = "Change Group Accent"
    public static let addInputSocket = "Add Input Socket"
    public static let addOutputSocket = "Add Output Socket"
    public static let renameSocket = "Rename Socket"
    public static let moveSocket = "Move Socket"
    public static let removeSocket = "Remove Socket"
    public static let deleteGroup = "Delete Group"

    // MARK: The viewport and the sketch editor
    public static let dragHandle = "Drag Handle"
    public static let pickEdges = "Pick Edges"
    public static let selectEdgesOfFace = "Select Edges of Face"
    public static let newSketchOnFace = "New Sketch on Face"
    public static let editSketch = "Edit Sketch"

    /// The generic name, for a step whose caller gave none (or a blank one). No callers use it: a step called "Edit"
    /// is a forgotten name, which the tests of each call site catch.
    public static let edit = "Edit"

    /// `name` trimmed, or `nil` when nothing is left (a blank name is no name).
    static func cleaned(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
```

Apply to `Sources/CreatorGraph/UndoStack.swift` and `Sources/CreatorGraph/DocumentModel.swift` (the default `name` keeps the existing direct `UndoStack.record` calls in `CommandTests` compiling; `DocumentModel` always passes one):

```diff
diff --git a/Sources/CreatorGraph/UndoStack.swift b/Sources/CreatorGraph/UndoStack.swift
--- a/Sources/CreatorGraph/UndoStack.swift
+++ b/Sources/CreatorGraph/UndoStack.swift
@@ -6,6 +6,8 @@
         /// What undo applies: the inverse of the first command of a coalesced run.
         public var inverse: GraphCommand
         public var coalescingKey: String?
+        /// What the Edit menu calls the step ("Add Note"): the first record's, for a coalesced run.
+        public var name: String
     }
 
     public private(set) var undoEntries: [Entry] = []
@@ -16,15 +18,21 @@
 
     public var canUndo: Bool { !undoEntries.isEmpty }
     public var canRedo: Bool { !redoEntries.isEmpty }
+    /// The name of the step Undo would take back, or `nil` with nothing to undo.
+    public var undoName: String? { undoEntries.last?.name }
+    /// The name of the step Redo would re-apply, or `nil` with nothing to redo.
+    public var redoName: String? { redoEntries.last?.name }
 
     /// Records an applied command. Consecutive records with the same non-nil key, with no
-    /// `endCoalescing()` between them, merge into one entry that keeps the first inverse.
-    public mutating func record(forward: GraphCommand, inverse: GraphCommand, coalescingKey: String?) {
+    /// `endCoalescing()` between them, merge into one entry that keeps the first inverse and the first `name`.
+    /// `name` defaults to "Edit" for the direct callers in tests; `DocumentModel` always passes one.
+    public mutating func record(forward: GraphCommand, inverse: GraphCommand, coalescingKey: String?,
+                                name: String = UndoName.edit) {
         redoEntries.removeAll()
         if let key = coalescingKey, isCoalescingOpen, let last = undoEntries.last, last.coalescingKey == key {
             undoEntries[undoEntries.count - 1].forward = forward
         } else {
-            undoEntries.append(Entry(forward: forward, inverse: inverse, coalescingKey: coalescingKey))
+            undoEntries.append(Entry(forward: forward, inverse: inverse, coalescingKey: coalescingKey, name: name))
         }
         isCoalescingOpen = coalescingKey != nil
     }

diff --git a/Sources/CreatorGraph/DocumentModel.swift b/Sources/CreatorGraph/DocumentModel.swift
--- a/Sources/CreatorGraph/DocumentModel.swift
+++ b/Sources/CreatorGraph/DocumentModel.swift
@@ -72,21 +72,29 @@
 
     public var canUndo: Bool { undoStack.canUndo }
     public var canRedo: Bool { undoStack.canRedo }
+    /// The name of the step Undo would take back ("Add Note"), or `nil` with nothing to undo.
+    public var undoName: String? { undoStack.undoName }
+    /// The name of the step Redo would re-apply, or `nil` with nothing to redo.
+    public var redoName: String? { undoStack.redoName }
 
     /// Applies an edit. Pass the same `coalescingKey` for every step of a slider or handle
-    /// drag, then call `endCoalescing()` when the drag ends, so the drag is one undo step.
-    public func perform(_ command: GraphCommand, coalescingKey: String? = nil) throws(GraphError) {
+    /// drag, then call `endCoalescing()` when the drag ends, so the drag is one undo step. `name` is the step's name in
+    /// the Edit menu (`UndoName`); without one (or with a blank one) the step is called "Edit", so
+    /// every caller passes one. A coalesced run keeps the name of its first record.
+    public func perform(_ command: GraphCommand, coalescingKey: String? = nil, name: String? = nil) throws(GraphError) {
         // The stale set must be taken before the edit, so dependents of removed nodes and links count.
         let stale = graph.downstreamClosure(of: content.touchedTopLevelNodes(command))
         let effect = effect(of: command)
         let inverse = try content.apply(command, registry: baseRegistry)
-        undoStack.record(forward: command, inverse: inverse, coalescingKey: coalescingKey)
+        undoStack.record(forward: command, inverse: inverse, coalescingKey: coalescingKey,
+                         name: UndoName.cleaned(name) ?? UndoName.edit)
         didChange(effect, markingStale: stale)
     }
 
     /// Applies a graph command to the graph at `path`: the top level, or inside a group definition (groups spec §5).
-    public func perform(_ command: GraphCommand, at path: GraphPath, coalescingKey: String? = nil) throws(GraphError) {
-        try perform(command.at(path), coalescingKey: coalescingKey)
+    public func perform(_ command: GraphCommand, at path: GraphPath, coalescingKey: String? = nil,
+                        name: String? = nil) throws(GraphError) {
+        try perform(command.at(path), coalescingKey: coalescingKey, name: name)
     }
 
     public func endCoalescing() {
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter UndoNameTests`
Expected: PASS, "Test run with 10 tests in 1 suite passed".

- [ ] **Step 5: Full run and lint**

Run: `swift test`, then `swiftlint lint --strict`.
Expected: exit 0, 11 "Test run with" lines, totalling 2106 tests (master + 10), no "recorded an issue" / "failed after", no new warning; lint reports 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorGraph Tests/CreatorGraphTests/UndoNameTests.swift
git commit -m "feat(graph): undo steps carry a name"
```

---

### Task 2: The graph editor names every edit

**Files:**
- Modify: `Sources/CreatorEditor/EditorModel+Levels.swift`, `+Editing.swift`, `+Pointer.swift`, `+Nudge.swift`, `+Inspector.swift`, `+CommentCreation.swift`, `+CommentInspector.swift`, `+Groups.swift`, `+GroupInspector.swift`, `+Expose.swift`
- Modify: `Tests/CreatorEditorTests/CommentEditingTests.swift` (one call gains `named:`)
- Test: `Tests/CreatorEditorTests/EditorUndoNameTests.swift` (new, 16 tests)

**Interfaces:**
- Consumes: Task 1's `UndoName` constants and `DocumentModel.perform(... name:)`.
- Produces: `EditorModel.edit(_:coalescingKey:name:)` (`name: String? = nil`); internal `EditorModel.insert(_:offset:named:)` (the `named` argument is required, so no paste path can forget it); private `delete(named:)`, `commit(_:selecting:named:)`, `commitComment(_:named:)`, `run(_:refusing:_:)`, `perform(_:_:)` (group inspector) each take the name first.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorEditorTests/EditorUndoNameTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// Every edit the graph editor makes names its undo step (named undo steps; groups-and-comments spec §7): the name
/// Undo and Redo show in the Edit menu and the top bar.
@MainActor
struct EditorUndoNameTests {
    let rect = testNode(RectangleTestNode.self, id: 1, at: .zero)
    let extrude = testNode(ExtrudeTestNode.self, id: 2, at: Vector2(300, 0))
    let output = testNode(OutputTestNode.self, id: 3, at: Vector2(600, 0))
    let sticky = note(1, at: Vector2(300, 300))
    let frame = box(2, at: Vector2(50, 400), size: Vector2(200, 150))

    func chain() -> EditorModel {
        makeEditor([rect, extrude, output], [wire(rect, "profile", extrude, "profile"), wire(extrude, "solid", output, "solid")],
                   stickies: [sticky], frames: [frame])
    }

    func widthField(_ editor: EditorModel) throws -> InputField {
        editor.selection = [rect.id]
        guard case .slider(let field, _)? = editor.inspectorPage.sections.first?.rows.first else {
            throw UndoNameFixtureError.noSlider
        }
        return field
    }

    // MARK: Nodes and wires

    @Test func addingANodeNamesItAfterItsType() {
        let editor = makeEditor([])
        editor.addFromLibrary(NumberTestNode.typeID)
        #expect(editor.document.undoName == "Add \(NumberTestNode.displayName)")
        _ = editor.addNode(RectangleTestNode.typeID, atScreen: Vector2(50, 50))
        #expect(editor.document.undoName == "Add \(RectangleTestNode.displayName)")
    }

    @Test func connectingAndDisconnecting() {
        let editor = makeEditor([rect, extrude])
        editor.connect(wire(rect, "profile", extrude, "profile"))
        #expect(editor.document.undoName == "Connect")
        editor.drag(editor.screenPoint(of: extrude.id, "profile", input: true), Vector2(900, 900))
        #expect(editor.document.undoName == "Disconnect")
        editor.document.undo()
        #expect(editor.document.undoName == "Connect" && editor.document.redoName == "Disconnect")
    }

    @Test func deleteCutPasteAndDuplicate() {
        let editor = chain()
        editor.selection = [extrude.id]
        editor.deleteSelection()
        #expect(editor.document.undoName == "Delete")
        editor.selection = [rect.id]
        editor.cutSelection()
        #expect(editor.document.undoName == "Cut")
        editor.paste()
        #expect(editor.document.undoName == "Paste")
        editor.duplicateSelection()
        #expect(editor.document.undoName == "Duplicate")
    }

    @Test func anOptionDragIsADuplicate() {
        let editor = chain()
        editor.selection = [rect.id]
        let start = editor.screenPoint(in: rect.id)
        editor.pointerDragged(from: start, to: start, modifiers: .option)
        editor.pointerDragged(from: start, to: start + Vector2(0, 60), modifiers: .option)
        editor.pointerReleased(from: start, at: start + Vector2(0, 60), modifiers: .option)
        #expect(editor.document.undoName == "Duplicate")
    }

    @Test func aMoveDragIsOneStepCalledMove() {
        let editor = chain()
        let start = editor.screenPoint(in: rect.id)
        editor.drag(start, start + Vector2(40, 30))
        #expect(editor.document.undoName == "Move")
        editor.document.undo()
        #expect(editor.document.undoName == nil, "every step of the drag was one step")
    }

    @Test func aHeldArrowIsOneStepCalledMove() {
        let editor = chain()
        editor.selection = [rect.id]
        editor.nudgeSelection(by: Vector2(1, 0), isRepeat: false)
        editor.nudgeSelection(by: Vector2(1, 0), isRepeat: true)
        #expect(editor.document.undoName == "Move")
        editor.document.undo()
        #expect(editor.document.undoName == nil)
    }

    // MARK: Inputs and parameters

    @Test func anInputIsChangedByItsLabelAndASliderDragKeepsTheFirstName() throws {
        let editor = chain()
        let field = try widthField(editor)
        editor.setInput(field, to: .number(11))
        #expect(editor.document.undoName == "Change \(field.label)")
        editor.document.endCoalescing()
        for value in [12.0, 13, 14] { editor.setInput(field, to: .number(value), continuous: true) }
        #expect(editor.document.undoName == "Change \(field.label)")
        editor.document.undo()
        #expect(editor.document.undoName == "Change \(field.label)", "the drag was one step; the typed value is the one before")
        editor.document.undo()
        #expect(editor.document.undoName == nil)
    }

    @Test func clearingAnOptionalInputSaysSo() throws {
        let grid = testNode(GridPointsTestNode.self, id: 8, at: .zero)
        let editor = makeEditor([grid], registry: inspectorTestRegistry)
        editor.selection = [grid.id]
        guard case .integer(let field)? = editor.inspectorPage.sections.first?.rows.last else { throw UndoNameFixtureError.noSlider }
        editor.setNumber(field, to: 6)
        guard case .integer(let set)? = editor.inspectorPage.sections.first?.rows.last else { throw UndoNameFixtureError.noSlider }
        editor.clearInput(set)
        #expect(editor.document.undoName == "Clear \(field.label)")
        #expect(editor.document.redoName == nil)
        editor.document.undo()
        #expect(editor.document.undoName == "Change \(field.label)")
    }

    @Test func aParameterIsChangedWithoutItsTypedName() {
        let width = GraphParameter(name: "Plate width", type: .number, value: .number(60))
        let editor = makeEditor([], parameters: [width])
        for value in [61.0, 70, 90] { editor.setParameter(width.id, to: .number(value), continuous: true) }
        #expect(editor.document.undoName == "Change Parameter", "text the person typed is never part of a name")
    }

    // MARK: Comments

    @Test func addingNotesAndFrames() {
        let editor = chain()
        editor.addNote(atScreen: Vector2(30, 40))
        #expect(editor.document.undoName == "Add Note")
        editor.canvasSelection = CanvasSelection(nodes: [rect.id])
        editor.addFrameAroundSelection()
        #expect(editor.document.undoName == "Add Frame")
    }

    @Test func editingNotesAndFrames() {
        let editor = chain()
        editor.setNoteText(sticky.id, to: "Changed")
        #expect(editor.document.undoName == "Edit Note")
        editor.setFrameTitle(frame.id, to: "Front plate")
        #expect(editor.document.undoName == "Edit Frame")
        editor.setCommentAccent(sticky.id, to: .purple)
        #expect(editor.document.undoName == "Edit Note")
        editor.setCommentAccent(frame.id, to: .orange)
        #expect(editor.document.undoName == "Edit Frame")
    }

    @Test func movingResizingAndDeletingComments() {
        let editor = chain()
        editor.canvasSelection = CanvasSelection(comments: [sticky.id])
        let rectangle = editor.frame(ofComment: sticky.id) ?? CanvasRect(origin: .zero, size: .zero)
        let handle = editor.transform.toScreen(CommentLayout.handle(of: rectangle).centre)
        editor.drag(handle, handle + Vector2(40, 25))
        #expect(editor.document.undoName == "Resize")
        let inside = editor.screenPoint(inComment: sticky.id, inset: Vector2(20, 20))
        editor.drag(inside, inside + Vector2(30, 30))
        #expect(editor.document.undoName == "Move")
        editor.deleteSelection()
        #expect(editor.document.undoName == "Delete")
    }

    // MARK: Groups

    @Test func groupUngroupAndMakeUnique() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        #expect(editor.document.undoName == "Group")
        editor.makeUnique(grouped.group)
        #expect(editor.document.undoName == "Make Unique")
        editor.selection = [try #require(editor.selection.first)]
        editor.ungroupSelection()
        #expect(editor.document.undoName == "Ungroup")
    }

    @Test func groupDefinitionEditsEachHaveTheirOwnName() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        let id = grouped.definition.id
        editor.renameGroup(id, to: "Rib")
        #expect(editor.document.undoName == "Rename Group", "the typed name is not in the step's")
        editor.setGroupAccent(id, to: .orange)
        #expect(editor.document.undoName == "Change Group Accent")
        editor.renameGroupSocket(id, side: .input, from: "width", to: "w")
        #expect(editor.document.undoName == "Rename Socket")
    }

    @Test func groupSocketsAreExposedMovedAndRemoved() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.enterGroup(grouped.group)
        editor.transform = CanvasTransform()
        let output = try #require(grouped.definition.outputNode)
        let input = try #require(grouped.definition.inputNode)
        editor.drag(editor.screenPoint(of: grouped.rectangle.id, "profile", input: false),
                    editor.screenPoint(of: output.id, "+", input: true))
        #expect(editor.document.undoName == "Add Output Socket")
        editor.moveGroupSocket(grouped.definition.id, side: .output, named: "profile", by: -1)
        #expect(editor.document.undoName == "Move Socket")
        editor.removeGroupSocket(grouped.definition.id, side: .output, named: "profile")
        #expect(editor.document.undoName == "Remove Socket")
        editor.drag(editor.screenPoint(of: input.id, "+", input: false),
                    editor.screenPoint(of: grouped.extrude.id, "distance", input: true))
        #expect(editor.document.undoName == "Add Input Socket")
    }

    @Test func deletingAnUnusedGroup() throws {
        let grouped = try GroupedEditor()
        let editor = grouped.editor
        editor.selection = [grouped.group]
        editor.deleteSelection()
        editor.deleteGroup(grouped.definition.id)
        #expect(editor.document.undoName == "Delete Group")
        editor.document.undo()
        #expect(editor.document.undoName == "Delete" && editor.document.redoName == "Delete Group")
    }
}

/// A fixture that did not have the row the test needs.
enum UndoNameFixtureError: Error {
    case noSlider
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter EditorUndoNameTests`
Expected: the suite builds (only existing API is used) and FAILS: every `undoName` is the generic "Edit", e.g. "Expectation failed: (editor.document.undoName → "Edit") == "Add Number"".

- [ ] **Step 3: Implement**

Apply (in this order; each hunk is independent):

`Sources/CreatorEditor/EditorModel+CommentCreation.swift`

```diff
diff --git a/Sources/CreatorEditor/EditorModel+CommentCreation.swift b/Sources/CreatorEditor/EditorModel+CommentCreation.swift
--- a/Sources/CreatorEditor/EditorModel+CommentCreation.swift
+++ b/Sources/CreatorEditor/EditorModel+CommentCreation.swift
@@ -50,14 +50,14 @@ extension EditorModel {
 
     private func add(_ note: StickyNote) -> Bool {
-        commit(.setSticky(note), selecting: note.id)
+        commit(.setSticky(note), selecting: note.id, named: UndoName.addNote)
     }
 
     private func add(_ box: CommentFrame) -> Bool {
-        commit(.setFrame(box), selecting: box.id)
+        commit(.setFrame(box), selecting: box.id, named: UndoName.addFrame)
     }
 
-    private func commit(_ command: GraphCommand, selecting id: CommentID) -> Bool {
+    private func commit(_ command: GraphCommand, selecting id: CommentID, named name: String) -> Bool {
         do {
-            try edit(command)
+            try edit(command, name: name)
             canvasSelection = CanvasSelection(comments: [id])
             return true
```

`Sources/CreatorEditor/EditorModel+CommentInspector.swift`

```diff
diff --git a/Sources/CreatorEditor/EditorModel+CommentInspector.swift b/Sources/CreatorEditor/EditorModel+CommentInspector.swift
--- a/Sources/CreatorEditor/EditorModel+CommentInspector.swift
+++ b/Sources/CreatorEditor/EditorModel+CommentInspector.swift
@@ -24,5 +24,5 @@ extension EditorModel {
         guard var note = graph.stickies[id], note.text != text else { return }
         note.text = text
-        commitComment(.setSticky(note))
+        commitComment(.setSticky(note), named: UndoName.editNote)
     }
 
@@ -39,5 +39,5 @@ extension EditorModel {
         guard box.title != trimmed else { return true }
         box.title = trimmed
-        return commitComment(.setFrame(box))
+        return commitComment(.setFrame(box), named: UndoName.editFrame)
     }
 
@@ -46,15 +46,15 @@ extension EditorModel {
         if var note = graph.stickies[id], note.accent != accent {
             note.accent = accent
-            commitComment(.setSticky(note))
+            commitComment(.setSticky(note), named: UndoName.editNote)
         } else if var box = graph.frames[id], box.accent != accent {
             box.accent = accent
-            commitComment(.setFrame(box))
+            commitComment(.setFrame(box), named: UndoName.editFrame)
         }
     }
 
     @discardableResult
-    private func commitComment(_ command: GraphCommand) -> Bool {
+    private func commitComment(_ command: GraphCommand, named name: String) -> Bool {
         do {
-            try edit(command)
+            try edit(command, name: name)
             return true
         } catch {
```

`Sources/CreatorEditor/EditorModel+Editing.swift`

```diff
diff --git a/Sources/CreatorEditor/EditorModel+Editing.swift b/Sources/CreatorEditor/EditorModel+Editing.swift
--- a/Sources/CreatorEditor/EditorModel+Editing.swift
+++ b/Sources/CreatorEditor/EditorModel+Editing.swift
@@ -13,5 +13,5 @@ extension EditorModel {
         }
         do {
-            try edit(.connect(link))
+            try edit(.connect(link), name: UndoName.connect)
         } catch {
             refuse(error.message, node: link.to.node)
@@ -23,4 +23,9 @@ extension EditorModel {
     /// only those selected, it says why nothing happened.
     public func deleteSelection() {
+        delete(named: UndoName.delete)
+    }
+
+    /// Deletes the selection as one undo step called `name` ("Delete", or "Cut" for ⌘X).
+    private func delete(named name: String) {
         let present = canvasSelection.nodes.filter { graph.nodes[$0] != nil }
         let commands = present.filter { !isBoundary($0) }.sorted().map { GraphCommand.removeNode($0) }
@@ -34,5 +39,5 @@ extension EditorModel {
         }
         do {
-            try edit(.batch(commands))
+            try edit(.batch(commands), name: name)
             canvasSelection = CanvasSelection()
         } catch {
@@ -46,5 +51,5 @@ extension EditorModel {
         let copied = clipboard(of: canvasSelection)
         if !copied.isEmpty { setClipboard(copied) }
-        deleteSelection()
+        delete(named: UndoName.cut)
     }
 
@@ -62,5 +67,5 @@ extension EditorModel {
     public func paste() {
         guard let clipboard else { return }
-        if let copies = insert(clipboard, offset: nextPasteOffset()) { canvasSelection = copies }
+        if let copies = insert(clipboard, offset: nextPasteOffset(), named: UndoName.paste) { canvasSelection = copies }
     }
 
@@ -68,5 +73,7 @@ extension EditorModel {
     public func duplicateSelection() {
         guard !canvasSelection.isEmpty else { return }
-        if let copies = insert(clipboard(of: canvasSelection), offset: Vector2(24, 24)) { canvasSelection = copies }
+        if let copies = insert(clipboard(of: canvasSelection), offset: Vector2(24, 24), named: UndoName.duplicate) {
+            canvasSelection = copies
+        }
     }
 
@@ -84,5 +91,5 @@ extension EditorModel {
     func add(_ node: Node) -> Bool {
         do {
-            try edit(.addNode(node))
+            try edit(.addNode(node), name: UndoName.addNode(node))
             selection = [node.id]
             return true
@@ -114,5 +121,5 @@ extension EditorModel {
     /// definitions it carries that the document lacks or has with other content (`GroupMerge`; the copied group
     /// nodes follow them). Returns the copies, to select, or `nil` if the graph refused or there was nothing to add.
-    func insert(_ clipboard: NodeClipboard, offset: Vector2) -> CanvasSelection? {
+    func insert(_ clipboard: NodeClipboard, offset: Vector2, named name: String) -> CanvasSelection? {
         guard !clipboard.isEmpty else { return nil }
         let merge = GroupMerge.plan(importing: clipboard.definitions, into: document.content)
@@ -145,5 +152,6 @@ extension EditorModel {
         do {
             // The definitions are added to the document, the nodes and comments to the level shown.
-            try document.perform(.batch(merge.additions.map { .addDefinition($0) } + [GraphCommand.batch(commands).at(graphPath)]))
+            try document.perform(.batch(merge.additions.map { .addDefinition($0) } + [GraphCommand.batch(commands).at(graphPath)]),
+                                 name: name)
             return CanvasSelection(nodes: Set(mapping.values), comments: comments)
         } catch {
```

`Sources/CreatorEditor/EditorModel+Expose.swift`

```diff
diff --git a/Sources/CreatorEditor/EditorModel+Expose.swift b/Sources/CreatorEditor/EditorModel+Expose.swift
--- a/Sources/CreatorEditor/EditorModel+Expose.swift
+++ b/Sources/CreatorEditor/EditorModel+Expose.swift
@@ -26,8 +26,10 @@ extension EditorModel {
             case (GroupNodes.outputTypeID, true, false):
                 try document.perform(GroupCommands.exposeOutput(from: other.endpoint, on: boundary.id, in: definition,
-                                                                of: document.content, registry: registry))
+                                                                of: document.content, registry: registry),
+                                     name: UndoName.addOutputSocket)
             case (GroupNodes.inputTypeID, false, true):
                 try document.perform(GroupCommands.exposeInput(to: other.endpoint, from: boundary.id, in: definition,
-                                                               of: document.content, registry: registry))
+                                                               of: document.content, registry: registry),
+                                     name: UndoName.addInputSocket)
             default:
                 refuse(Self.exposeHint, node: plus.endpoint.node)
```

`Sources/CreatorEditor/EditorModel+GroupInspector.swift`

```diff
diff --git a/Sources/CreatorEditor/EditorModel+GroupInspector.swift b/Sources/CreatorEditor/EditorModel+GroupInspector.swift
--- a/Sources/CreatorEditor/EditorModel+GroupInspector.swift
+++ b/Sources/CreatorEditor/EditorModel+GroupInspector.swift
@@ -28,10 +28,10 @@ extension EditorModel {
         let trimmed = name.trimmingCharacters(in: .whitespaces)
         guard trimmed != document.definitions[id]?.name else { return }
-        perform { () throws(GraphError) in try GroupCommands.rename(id, to: trimmed, in: document.content) }
+        perform(UndoName.renameGroup) { () throws(GraphError) in try GroupCommands.rename(id, to: trimmed, in: document.content) }
     }
 
     public func setGroupAccent(_ id: GroupID, to accent: AccentRole) {
         guard accent != document.definitions[id]?.accent else { return }
-        perform { () throws(GraphError) in try GroupCommands.setAccent(id, accent, in: document.content) }
+        perform(UndoName.changeGroupAccent) { () throws(GraphError) in try GroupCommands.setAccent(id, accent, in: document.content) }
     }
 
@@ -40,5 +40,5 @@ extension EditorModel {
         let name = SocketName(new.trimmingCharacters(in: .whitespaces))
         guard name != old else { return }
-        perform { () throws(GraphError) in
+        perform(UndoName.renameSocket) { () throws(GraphError) in
             try GroupCommands.renameSocket(id, side: side, from: old, to: name, in: document.content)
         }
@@ -49,5 +49,5 @@ extension EditorModel {
         let sockets = side == .input ? document.definitions[id]?.inputs : document.definitions[id]?.outputs
         guard let index = sockets?.firstIndex(where: { $0.name == name }) else { return }
-        perform { () throws(GraphError) in
+        perform(UndoName.moveSocket) { () throws(GraphError) in
             try GroupCommands.moveSocket(id, side: side, from: index, to: index + step, in: document.content)
         }
@@ -56,5 +56,5 @@ extension EditorModel {
     /// Removes socket `name` of `side` and its wires inside. Refused while a group node has it wired, naming that node.
     public func removeGroupSocket(_ id: GroupID, side: GroupSocketSide, named name: SocketName) {
-        perform { () throws(GraphError) in
+        perform(UndoName.removeSocket) { () throws(GraphError) in
             try GroupCommands.removeSocket(id, side: side, name: name, in: document.content)
         }
@@ -63,10 +63,10 @@ extension EditorModel {
     /// Deletes definition `id` from the document. Refused while a group node uses it.
     public func deleteGroup(_ id: GroupID) {
-        perform { () throws(GraphError) in try GroupCommands.deleteDefinition(id, in: document.content) }
+        perform(UndoName.deleteGroup) { () throws(GraphError) in try GroupCommands.deleteDefinition(id, in: document.content) }
     }
 
-    private func perform(_ build: () throws(GraphError) -> GraphCommand) {
+    private func perform(_ name: String, _ build: () throws(GraphError) -> GraphCommand) {
         do {
-            try document.perform(try build())
+            try document.perform(try build(), name: name)
         } catch {
             refuse(error.message, node: selection.first)
```

`Sources/CreatorEditor/EditorModel+Groups.swift`

```diff
diff --git a/Sources/CreatorEditor/EditorModel+Groups.swift b/Sources/CreatorEditor/EditorModel+Groups.swift
--- a/Sources/CreatorEditor/EditorModel+Groups.swift
+++ b/Sources/CreatorEditor/EditorModel+Groups.swift
@@ -6,5 +6,5 @@ extension EditorModel {
     /// step (groups spec §5). A refused group changes nothing and shows its message.
     public func groupSelection() {
-        run(refusing: nil) { () throws(GraphError) in
+        run(UndoName.group, refusing: nil) { () throws(GraphError) in
             try GroupCommands.group(selection, in: graphPath, of: document.content, registry: registry)
         }
@@ -22,5 +22,5 @@ extension EditorModel {
     /// Ungroups group node `id` of the level shown (its inspector's Ungroup, or ⇧⌘G).
     public func ungroup(_ id: NodeID) {
-        run(refusing: id) { () throws(GraphError) in
+        run(UndoName.ungroup, refusing: id) { () throws(GraphError) in
             try GroupCommands.ungroup(id, in: graphPath, of: document.content, registry: registry)
         }
@@ -29,15 +29,15 @@ extension EditorModel {
     /// Make Unique on group node `id` of the level shown: it gets its own copy of the definition, as one undo step.
     public func makeUnique(_ id: NodeID) {
-        run(refusing: id) { () throws(GraphError) in
+        run(UndoName.makeUnique, refusing: id) { () throws(GraphError) in
             try GroupCommands.makeUnique(id, in: graphPath, of: document.content, registry: registry)
         }
     }
 
-    /// Performs the group command `build` makes as one undo step and selects what it says, or shows why it was
+    /// Performs the group command `build` makes as one undo step named `name` and selects what it says, or shows why it was
     /// refused (shaking `node`).
-    private func run(refusing node: NodeID?, _ build: () throws(GraphError) -> GroupEdit) {
+    private func run(_ name: String, refusing node: NodeID?, _ build: () throws(GraphError) -> GroupEdit) {
         do {
             let edit = try build()
-            try document.perform(edit.command)
+            try document.perform(edit.command, name: name)
             selection = edit.selection
         } catch {
```

`Sources/CreatorEditor/EditorModel+Inspector.swift`

```diff
diff --git a/Sources/CreatorEditor/EditorModel+Inspector.swift b/Sources/CreatorEditor/EditorModel+Inspector.swift
--- a/Sources/CreatorEditor/EditorModel+Inspector.swift
+++ b/Sources/CreatorEditor/EditorModel+Inspector.swift
@@ -35,5 +35,5 @@ extension EditorModel {
         let key = continuous ? "input-\(field.node.rawValue.uuidString)-\(field.socket.rawValue)" : nil
         do {
-            try edit(.setInput(field.node, field.socket, value), coalescingKey: key)
+            try edit(.setInput(field.node, field.socket, value), coalescingKey: key, name: UndoName.changeInput(field.label))
         } catch {
             refuse(error.message, node: field.node)
@@ -46,5 +46,5 @@ extension EditorModel {
         guard field.isOptional, graph.nodes[field.node]?.inputValues[field.socket] != nil else { return }
         do {
-            try edit(.setInput(field.node, field.socket, nil))
+            try edit(.setInput(field.node, field.socket, nil), name: UndoName.clearInput(field.label))
         } catch {
             refuse(error.message, node: field.node)
@@ -81,5 +81,5 @@ extension EditorModel {
         let key = continuous ? "parameter-\(id.rawValue.uuidString)" : nil
         do {
-            try document.perform(.setParameter(id, value), coalescingKey: key)
+            try document.perform(.setParameter(id, value), coalescingKey: key, name: UndoName.changeParameter)
         } catch {
             refuse(error.message, node: nil)
```

`Sources/CreatorEditor/EditorModel+Levels.swift`

```diff
diff --git a/Sources/CreatorEditor/EditorModel+Levels.swift b/Sources/CreatorEditor/EditorModel+Levels.swift
--- a/Sources/CreatorEditor/EditorModel+Levels.swift
+++ b/Sources/CreatorEditor/EditorModel+Levels.swift
@@ -25,7 +25,8 @@ extension EditorModel {
     public var rootGraph: Graph { document.graph }
 
-    /// Applies `command` to the graph the panel shows, as one undo step (`DocumentModel.perform(_:at:)`).
-    public func edit(_ command: GraphCommand, coalescingKey: String? = nil) throws(GraphError) {
-        try document.perform(command, at: graphPath, coalescingKey: coalescingKey)
+    /// Applies `command` to the graph the panel shows, as one undo step named `name` (`DocumentModel.perform(_:at:)`;
+    /// without one the step is named from the command).
+    public func edit(_ command: GraphCommand, coalescingKey: String? = nil, name: String? = nil) throws(GraphError) {
+        try document.perform(command, at: graphPath, coalescingKey: coalescingKey, name: name)
     }
 
```

`Sources/CreatorEditor/EditorModel+Nudge.swift`

```diff
diff --git a/Sources/CreatorEditor/EditorModel+Nudge.swift b/Sources/CreatorEditor/EditorModel+Nudge.swift
--- a/Sources/CreatorEditor/EditorModel+Nudge.swift
+++ b/Sources/CreatorEditor/EditorModel+Nudge.swift
@@ -17,5 +17,5 @@ extension EditorModel {
             nudgeKey = "nudge-\(UUID().uuidString)"
         }
-        try? edit(.batch(moveCommands(from: start, by: flow.stored(delta))), coalescingKey: nudgeKey)
+        try? edit(.batch(moveCommands(from: start, by: flow.stored(delta))), coalescingKey: nudgeKey, name: UndoName.move)
         return true
     }
```

`Sources/CreatorEditor/EditorModel+Pointer.swift`

```diff
diff --git a/Sources/CreatorEditor/EditorModel+Pointer.swift b/Sources/CreatorEditor/EditorModel+Pointer.swift
--- a/Sources/CreatorEditor/EditorModel+Pointer.swift
+++ b/Sources/CreatorEditor/EditorModel+Pointer.swift
@@ -133,8 +133,8 @@ extension EditorModel {
             transform = CanvasTransform(offset: startOffset + (location - pressPoint), zoom: transform.zoom)
         case .moving(let start, let key):
-            try? edit(.batch(moveCommands(from: start, by: storedDelta)), coalescingKey: key)
+            try? edit(.batch(moveCommands(from: start, by: storedDelta)), coalescingKey: key, name: UndoName.move)
         case .resizing(let id, let start, let key):
             if let command = resizeCommand(id, from: start, by: (location - pressPoint) * (1 / transform.zoom)) {
-                try? edit(command, coalescingKey: key)
+                try? edit(command, coalescingKey: key, name: UndoName.resize)
             }
         case .duplicating(let start, _):
@@ -158,5 +158,5 @@ extension EditorModel {
     /// The copies land where the ghosts were, as one undo step; the originals never moved.
     private func finishDuplicate(start: SelectionPositions, delta: Vector2) {
-        if let copies = insert(clipboard(of: start.items), offset: delta) { canvasSelection = copies }
+        if let copies = insert(clipboard(of: start.items), offset: delta, named: UndoName.duplicate) { canvasSelection = copies }
     }
 
@@ -166,5 +166,5 @@ extension EditorModel {
             if wire.from.isInput, let link = graph.incomingLink(to: wire.from.endpoint) {
                 do {
-                    try edit(.disconnect(link))
+                    try edit(.disconnect(link), name: UndoName.disconnect)
                 } catch {
                     refuse(error.message, node: link.to.node)
```

And in `Tests/CreatorEditorTests/CommentEditingTests.swift`:

```diff
diff --git a/Tests/CreatorEditorTests/CommentEditingTests.swift b/Tests/CreatorEditorTests/CommentEditingTests.swift
--- a/Tests/CreatorEditorTests/CommentEditingTests.swift
+++ b/Tests/CreatorEditorTests/CommentEditingTests.swift
@@ -82,5 +82,6 @@ struct CommentEditingTests {
         let editor = editor()
         editor.canvasSelection = CanvasSelection(nodes: [a.id], comments: [frame.id])
-        let copies = try #require(editor.insert(editor.clipboard(of: editor.canvasSelection), offset: Vector2(0, 500)))
+        let copies = try #require(editor.insert(editor.clipboard(of: editor.canvasSelection), offset: Vector2(0, 500),
+                                                named: UndoName.paste))
         let copiedFrame = try #require(copies.comments.compactMap { editor.graph.frames[$0] }.first)
         #expect(copies.nodes.count == 1 && editor.members(of: copiedFrame) == copies.nodes)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter EditorUndoNameTests`
Expected: PASS, "Test run with 16 tests in 1 suite passed".

- [ ] **Step 5: Full run and lint**

Run: `swift test`, then `swiftlint lint --strict`.
Expected: exit 0, 11 run lines, 2122 tests (master + 26), no issues, no new warning, 0 lint violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorEditor Tests/CreatorEditorTests
git commit -m "feat(editor): every graph edit names its undo step"
```

---

### Task 3: The sketch editor names its steps

The sketch editor's `SketchCommit.description` is for tests and logs, not for menus: it embeds a dimension's typed name (`Rename d1 to Plate width`, `Change d1`, `Expose d1`, `Make d1 Driving`) and numbers (`Fillet Point 2 (5 mm)`, `Mirror 1 entity`, `Linear pattern of 1 entity (×3)`). Every commit therefore carries a second, fixed `name`, by kind of edit (User decision 1). `CreatorSketchEditor` does not depend on `CreatorGraph`, so the catalog is its own enum, `SketchStepName`; the host (Task 4) shows `SketchCommit.name`.

**Files:**
- Create: `Sources/CreatorSketchEditor/SketchStepName.swift`
- Modify: `Sources/CreatorSketchEditor/SketchCommit.swift`, `SketchEditorModel.swift`, `SketchEditorModel+Commands.swift`, `+Copies.swift`, `+Dimensions.swift`, `+Drag.swift`, `+Drawing.swift`, `+Fillet.swift`, `+Project.swift`, `+Selection.swift`
- Modify: `Tests/CreatorSketchEditorTests/SketchEditorModelTests.swift` (two `commit` calls gain `named:`)
- Test: `Tests/CreatorSketchEditorTests/SketchStepNameTests.swift` (new, 9 tests)

**Interfaces:**
- Consumes: nothing new (`SketchCommands`, `SketchEditorModel`).
- Produces: `SketchStepName` (enum of `static let` names); `SketchCommit.name: String` (`init(sketch:description:name:projections:)`, `name` defaulting to `SketchStepName.editSketch`); internal `SketchEditorModel.commit(_:_:named:projections:)` (`named` required, so no new tool can forget it) and `apply(_:_:)` (name first).

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorSketchEditorTests/SketchStepNameTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import CreatorSketch
import Testing
@testable import CreatorSketchEditor

/// Every commit the sketch editor makes carries a fixed step name (named undo steps): the kind of edit, never text
/// the person typed (a dimension's name) and never a number, which `SketchCommit.description` still has.
@MainActor
struct SketchStepNameTests {
    func makeModel(_ sketch: Sketch = Sketch(), tool: SketchTool = .select) -> (SketchEditorModel, RecordingHost) {
        let model = SketchEditorModel(sketch: sketch, plane: .xy)
        model.choose(tool)
        return (model, RecordingHost(model))
    }

    @Test func drawingNamesEachKindOfGeometry() {
        let (model, host) = makeModel(tool: .point)
        model.click(at: Vector2(1, 1), tolerance: 1, modifiers: [])
        model.choose(.line)
        model.click(at: Vector2(10, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(30, 0), tolerance: 1, modifiers: [])
        model.choose(.circle)
        model.click(at: Vector2(10, 40), tolerance: 1, modifiers: [])
        model.click(at: Vector2(13, 44), tolerance: 1, modifiers: [])
        model.choose(.arc)
        model.click(at: Vector2(50, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(60, 0), tolerance: 1, modifiers: [])
        model.click(at: Vector2(50, 3), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.name) == ["Add Point", "Add Line", "Add Circle", "Add Arc"])
    }

    @Test func constraintsAndConstructionAreNamedByKind() {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, host) = makeModel(rectangle.sketch)
        model.selection = [rectangle.lines[0], rectangle.lines[1]]
        model.addConstraint(.equal)
        model.selection = [rectangle.lines[0]]
        model.toggleConstruction()
        model.toggleConstruction()
        #expect(host.commits.map(\.name) == ["Add Constraint", "Make Construction", "Make Normal Geometry"])
        #expect(host.commits.first?.description == "Equal", "the finer description is kept for tests and logs")
    }

    @Test func dimensionStepsHaveFixedNamesWhateverTheDimensionIsCalled() {
        let rectangle = RectangleSketch()
        let (model, host) = makeModel(rectangle.sketch)
        model.setValue("80", of: rectangle.width)
        model.rename(rectangle.width, to: "Plate width")
        model.setExposed(true, of: rectangle.width)
        model.setExposed(false, of: rectangle.width)
        model.setDriving(false, of: rectangle.height)
        model.setDriving(true, of: rectangle.height)
        model.remove(.dimension(rectangle.height))
        #expect(host.commits.map(\.name) == [
            "Change Dimension", "Rename Dimension", "Expose Dimension", "Stop Exposing Dimension",
            "Make Dimension Reference", "Make Dimension Driving", "Delete",
        ])
        #expect(host.commits.map(\.description).contains("Rename d1 to Plate width"), "the typed name is in the description only")
        #expect(host.commits.allSatisfy { !$0.name.contains("Plate") && !$0.name.contains("d1") })
    }

    @Test func aDimensionToolPickIsAddDimension() {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, host) = makeModel(rectangle.sketch, tool: .dimension)
        model.click(at: Vector2(30, 0.3), tolerance: 1, modifiers: [])
        model.click(at: Vector2(30, 20), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.name) == ["Add Dimension"])
    }

    @Test func deletingAndDraggingAPointAreNamed() {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, host) = makeModel(rectangle.sketch)
        #expect(model.beginDrag(at: Vector2(60.3, 40.2), tolerance: 1))
        model.endDrag(at: Vector2(70, 50))
        model.selection = [rectangle.lines[2]]
        model.deleteSelection()
        #expect(host.commits.map(\.name) == ["Move Point", "Delete"])
    }

    @Test func filletsHaveNoRadiusInTheirName() {
        let rectangle = RectangleSketch(dimensioned: false)
        let (model, host) = makeModel(rectangle.sketch, tool: .fillet)
        model.setFilletRadius("2.5")
        model.click(at: Vector2(60.3, 0.2), tolerance: 1, modifiers: [])
        #expect(host.commits.map(\.name) == ["Fillet"])
        #expect(host.commits.first?.description.contains("2.5") == true, "the radius is in the description")
    }

    @Test func trimExtendMirrorAndPatternsAreNamed() {
        var crossing = Sketch()
        crossing.addLine(Vector2(0, 0), Vector2(40, 0))
        crossing.addLine(Vector2(20, -10), Vector2(20, 10))
        let (trim, trimmed) = makeModel(crossing, tool: .trim)
        trim.click(at: Vector2(35, 0), tolerance: 1, modifiers: [])
        #expect(trimmed.commits.map(\.name) == ["Trim"])

        var short = Sketch()
        short.addLine(Vector2(0, 0), Vector2(20, 0))
        short.addLine(Vector2(30, -10), Vector2(30, 10))
        let (extend, extended) = makeModel(short, tool: .extend)
        extend.click(at: Vector2(19, 0), tolerance: 1, modifiers: [])
        #expect(extended.commits.map(\.name) == ["Extend"])

        var mirrorSketch = Sketch()
        mirrorSketch.addLine(Vector2(0, -10), Vector2(0, 30), isConstruction: true)
        let line = mirrorSketch.addLine(Vector2(5, 0), Vector2(15, 10))
        let (mirror, mirrored) = makeModel(mirrorSketch, tool: .mirror)
        mirror.selection = [line]
        mirror.click(at: Vector2(0.2, 15), tolerance: 1, modifiers: [])
        #expect(mirrored.commits.map(\.name) == ["Mirror"])

        var linear = Sketch()
        let circle = linear.addCircle(center: Vector2(0, 0), radius: 2)
        linear.addLine(Vector2(0, -10), Vector2(10, -10), isConstruction: true)
        let (along, alongHost) = makeModel(linear, tool: .pattern)
        along.selection = [circle]
        along.click(at: Vector2(5, -9.8), tolerance: 1, modifiers: [])
        #expect(alongHost.commits.map(\.name) == ["Linear Pattern"])

        var round = Sketch()
        round.addPoint(Vector2(0, 0))
        let ring = round.addCircle(center: Vector2(10, 0), radius: 2)
        let (around, aroundHost) = makeModel(round, tool: .pattern)
        around.setPatternCount("4")
        around.selection = [ring]
        around.click(at: Vector2(0.2, 0.2), tolerance: 1, modifiers: [])
        #expect(aroundHost.commits.map(\.name) == ["Circular Pattern"])
        #expect(aroundHost.commits.first?.description.contains("4") == true, "the count is in the description")
    }

    @Test func projectIsNamedProject() {
        let model = SketchEditorModel(sketch: Sketch(), plane: .xz)
        let host = RecordingHost(model)
        model.choose(.project)
        let pick = EdgePick(key: EdgeKey([], []), matchCount: 1)
        let candidate = ProjectionCandidate(curve: .line(Vector2(0, 0), Vector2(30, 0)), pick: pick, solid: 0)
        model.events.projection = { _, _ in ProjectionResolution(candidates: [candidate], skipped: []) }
        model.project(.edge(solid: 0, EdgeID(1)))
        #expect(host.commits.map(\.name) == ["Project"])
    }

    @Test func aCommitMadeWithoutANameIsCalledEditSketch() {
        #expect(SketchCommit(sketch: Sketch(), description: "Vertical").name == "Edit Sketch")
    }
}
```

and update the two existing direct calls in `Tests/CreatorSketchEditorTests/SketchEditorModelTests.swift` (`model.commit(edited, "Change d1")` becomes `model.commit(edited, "Change d1", named: SketchStepName.changeDimension)`, and `model.commit(edited, "Vertical")` becomes `model.commit(edited, "Vertical", named: SketchStepName.addConstraint)`).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SketchStepNameTests`
Expected: build FAIL with "value of type 'SketchCommit' has no member 'name'", "cannot find 'SketchStepName' in scope".

- [ ] **Step 3: Implement**

Create `Sources/CreatorSketchEditor/SketchStepName.swift`:

```swift
/// The fixed names of the sketch editor's undo steps ("Add Line", "Change Dimension"). Each says what kind of edit it
/// was and never contains text the person typed (a dimension's name) or a number: the host shows it as "Undo Add Line"
/// in the Edit menu. `SketchCommit.description` is the finer, per-edit text ("Rename d1 to Plate width") and is for tests
/// and logs, not for menus.
public enum SketchStepName {
    public static let addPoint = "Add Point"
    public static let addLine = "Add Line"
    public static let addCircle = "Add Circle"
    public static let addArc = "Add Arc"
    public static let addConstraint = "Add Constraint"
    public static let addDimension = "Add Dimension"
    public static let changeDimension = "Change Dimension"
    public static let renameDimension = "Rename Dimension"
    public static let exposeDimension = "Expose Dimension"
    public static let stopExposingDimension = "Stop Exposing Dimension"
    public static let makeDimensionDriving = "Make Dimension Driving"
    public static let makeDimensionReference = "Make Dimension Reference"
    public static let makeConstruction = "Make Construction"
    public static let makeNormalGeometry = "Make Normal Geometry"
    public static let movePoint = "Move Point"
    public static let delete = "Delete"
    public static let trim = "Trim"
    public static let extend = "Extend"
    public static let fillet = "Fillet"
    public static let mirror = "Mirror"
    public static let linearPattern = "Linear Pattern"
    public static let circularPattern = "Circular Pattern"
    public static let project = "Project"
    /// What a commit made without a name is called.
    public static let editSketch = "Edit Sketch"
}
```

Apply (every `commit` site, 21 of them, gains its `named:`; `DimensionField`'s `commit()` is the view's own and is unrelated):

`Sources/CreatorSketchEditor/SketchCommit.swift`

```diff
diff --git a/Sources/CreatorSketchEditor/SketchCommit.swift b/Sources/CreatorSketchEditor/SketchCommit.swift
--- a/Sources/CreatorSketchEditor/SketchCommit.swift
+++ b/Sources/CreatorSketchEditor/SketchCommit.swift
@@ -1,16 +1,21 @@
 import CreatorSketch
 
 /// One edit the sketch editor made, for the host to store as one undo step (sketcher spec §8): the whole new
-/// sketch, already solved and remembered (S4 → S5 handoff), the undo menu's description, and, for Project, the
+/// sketch, already solved and remembered (S4 → S5 handoff), a `description` of the edit (finer text for tests and
+/// logs: it holds typed names and numbers, so it is never shown in a menu), the undo step's fixed `name`, and, for Project, the
 /// projections the edit added (their picks and solids live in the Sketch node's settings and wires, not the sketch).
 public struct SketchCommit: Hashable, Sendable {
     public var sketch: Sketch
     public var description: String
+    /// The fixed name of the undo step (`SketchStepName`, "Add Line"): what the Edit menu shows, never typed text.
+    public var name: String
     public var projections: [ProjectionWrite]
 
-    public init(sketch: Sketch, description: String, projections: [ProjectionWrite] = []) {
+    public init(sketch: Sketch, description: String, name: String = SketchStepName.editSketch,
+                projections: [ProjectionWrite] = []) {
         self.sketch = sketch
         self.description = description
+        self.name = name
         self.projections = projections
     }
 }
```

`Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift`

```diff
diff --git a/Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift b/Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift
--- a/Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel+Commands.swift
@@ -21,19 +21,19 @@ extension SketchEditorModel {
         guard let curve = SketchPicker(sketch: sketch, solution: solution).curve(near: p, tolerance: tolerance) else { return }
         let current = sketch
         if tool == .trim {
-            apply { () throws(SketchCommandError) in try SketchCommands.trim(current, curve: curve, near: p) }
+            apply(SketchStepName.trim) { () throws(SketchCommandError) in try SketchCommands.trim(current, curve: curve, near: p) }
         } else {
-            apply { () throws(SketchCommandError) in try SketchCommands.extend(current, curve: curve, near: p) }
+            apply(SketchStepName.extend) { () throws(SketchCommandError) in try SketchCommands.extend(current, curve: curve, near: p) }
         }
     }
 
     /// Commits a command's edit as one step (the selection keeps what's left of it), or shows why it was refused.
-    func apply(_ command: () throws(SketchCommandError) -> SketchEdit) {
+    func apply(_ name: String, _ command: () throws(SketchCommandError) -> SketchEdit) {
         do {
             let edit = try command()
             selection = selection.filter { edit.sketch.entities[$0] != nil }
             hovered = nil
-            commit(edit.sketch, edit.description)
+            commit(edit.sketch, edit.description, named: name)
         } catch {
             refusal = error.message
         }
```

`Sources/CreatorSketchEditor/SketchEditorModel+Copies.swift`

```diff
diff --git a/Sources/CreatorSketchEditor/SketchEditorModel+Copies.swift b/Sources/CreatorSketchEditor/SketchEditorModel+Copies.swift
--- a/Sources/CreatorSketchEditor/SketchEditorModel+Copies.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel+Copies.swift
@@ -11,7 +11,9 @@ extension SketchEditorModel {
         guard let axis = SketchPicker(sketch: sketch, solution: solution).curve(near: p, tolerance: tolerance) else { return }
         let current = sketch
         let selected = selection.sorted()
-        apply { () throws(SketchCommandError) in try SketchCommands.mirror(current, entities: selected, about: axis) }
+        apply(SketchStepName.mirror) { () throws(SketchCommandError) in
+            try SketchCommands.mirror(current, entities: selected, about: axis)
+        }
     }
 
     /// A Pattern click: on a point, `options.patternCount` instances of the selection around it (a circular pattern);
@@ -22,12 +24,12 @@ extension SketchEditorModel {
         let (current, selected, count, spacing) = (sketch, selection.sorted(), options.patternCount, options.patternSpacing)
         switch sketch.entities[target]?.kind {
         case .point?:
-            apply { () throws(SketchCommandError) in
+            apply(SketchStepName.circularPattern) { () throws(SketchCommandError) in
                 try SketchCommands.circularPattern(current, entities: selected, center: target, count: count)
             }
         case .line(let start, let end)?:
             guard let a = sketch.position(of: start), let b = sketch.position(of: end) else { return }
-            apply { () throws(SketchCommandError) in
+            apply(SketchStepName.linearPattern) { () throws(SketchCommandError) in
                 try SketchCommands.linearPattern(current, entities: selected, direction: b - a, spacing: spacing, count: count)
             }
         default:
```

`Sources/CreatorSketchEditor/SketchEditorModel+Dimensions.swift`

```diff
diff --git a/Sources/CreatorSketchEditor/SketchEditorModel+Dimensions.swift b/Sources/CreatorSketchEditor/SketchEditorModel+Dimensions.swift
--- a/Sources/CreatorSketchEditor/SketchEditorModel+Dimensions.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel+Dimensions.swift
@@ -51,7 +51,7 @@ extension SketchEditorModel {
         }
         edited.dimensions[id]?.value = measured
         edited.dimensions[id]?.isDriving = true
-        commit(edited, "Dimension \(edited.dimensions[id]?.name ?? "")")
+        commit(edited, "Dimension \(edited.dimensions[id]?.name ?? "")", named: SketchStepName.addDimension)
     }
 
     /// The inspector's dimensions, in ID order. A reference dimension shows what it measures now (its stored value is
@@ -114,7 +114,7 @@ extension SketchEditorModel {
         guard value != dimension.value else { return }
         var edited = sketch
         edited.dimensions[id]?.value = value
-        commit(edited, "Change \(dimension.name)")
+        commit(edited, "Change \(dimension.name)", named: SketchStepName.changeDimension)
     }
 
     /// Why `value` can't drive a dimension of `kind` (sizes are more than 0 mm, angles 0 to 180°), or nil if it can.
@@ -141,7 +141,7 @@ extension SketchEditorModel {
             refusal = trimmed.isEmpty ? "A dimension needs a name." : "Another dimension is already called “\(trimmed)”."
             return
         }
-        commit(edited, "Rename \(dimension.name) to \(trimmed)")
+        commit(edited, "Rename \(dimension.name) to \(trimmed)", named: SketchStepName.renameDimension)
     }
 
     /// "Expose as input" (sketcher spec §7): the dimension becomes an input socket named after it.
@@ -149,7 +149,8 @@ extension SketchEditorModel {
         guard let dimension = sketch.dimensions[id], dimension.isExposed != exposed else { return }
         var edited = sketch
         edited.dimensions[id]?.isExposed = exposed
-        commit(edited, exposed ? "Expose \(dimension.name)" : "Stop Exposing \(dimension.name)")
+        commit(edited, exposed ? "Expose \(dimension.name)" : "Stop Exposing \(dimension.name)",
+               named: exposed ? SketchStepName.exposeDimension : SketchStepName.stopExposingDimension)
     }
 
     /// Driving or reference (a reference dimension only measures, into the node's `measurements`). Either way it takes
@@ -160,7 +161,8 @@ extension SketchEditorModel {
         edited.dimensions[id]?.isDriving = driving
         let measured = driving ? solution.measurements[id] : SketchSolver.solve(edited).measurements[id]
         if let measured, measured.isFinite { edited.dimensions[id]?.value = measured }
-        commit(edited, driving ? "Make \(dimension.name) Driving" : "Make \(dimension.name) Reference")
+        commit(edited, driving ? "Make \(dimension.name) Driving" : "Make \(dimension.name) Reference",
+               named: driving ? SketchStepName.makeDimensionDriving : SketchStepName.makeDimensionReference)
     }
 
     /// Removes one constraint or dimension from the inspector's list. An exposed dimension is refused (its input and
@@ -178,6 +180,6 @@ extension SketchEditorModel {
             }
             edited.dimensions[id] = nil
         }
-        commit(edited, "Delete \(sketch.label(of: ref))")
+        commit(edited, "Delete \(sketch.label(of: ref))", named: SketchStepName.delete)
     }
 }
```

`Sources/CreatorSketchEditor/SketchEditorModel+Drag.swift`

```diff
diff --git a/Sources/CreatorSketchEditor/SketchEditorModel+Drag.swift b/Sources/CreatorSketchEditor/SketchEditorModel+Drag.swift
--- a/Sources/CreatorSketchEditor/SketchEditorModel+Drag.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel+Drag.swift
@@ -34,7 +34,7 @@ extension SketchEditorModel {
         if sketch == origin {
             solution = SketchSolver.solve(sketch)
         } else {
-            commit(sketch, "Move Point")
+            commit(sketch, "Move Point", named: SketchStepName.movePoint)
         }
     }
 }
```

`Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift`

```diff
diff --git a/Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift b/Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift
--- a/Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel+Drawing.swift
@@ -32,7 +32,8 @@ extension SketchEditorModel {
         let makeConstruction = selection.contains { sketch.entities[$0]?.isConstruction == false }
         var edited = sketch
         for id in selection.sorted() { edited.entities[id]?.isConstruction = makeConstruction }
-        commit(edited, makeConstruction ? "Make Construction" : "Make Normal Geometry")
+        commit(edited, makeConstruction ? "Make Construction" : "Make Normal Geometry",
+               named: makeConstruction ? SketchStepName.makeConstruction : SketchStepName.makeNormalGeometry)
     }
 
     /// Esc: closes the host's popup if one is open (`SketchEditorEvents.dismissHostPopup`); else ends the stroke in
@@ -129,7 +130,7 @@ extension SketchEditorModel {
         guard target.point == nil else { return }
         var edited = sketch
         _ = target.point(in: &edited, isConstruction: isConstruction)
-        commit(edited, "Point")
+        commit(edited, "Point", named: SketchStepName.addPoint)
     }
 
     /// The first click starts a chain; each later one ends a line there and starts the next from its end.
@@ -152,7 +153,7 @@ extension SketchEditorModel {
         let b = end.point(in: &edited)
         let line = edited.addLine(from: a, to: b, isConstruction: isConstruction)
         if let inference { edited.add(inference.constraint(on: line)) }
-        commit(edited, "Line")
+        commit(edited, "Line", named: SketchStepName.addLine)
         drawState = .lineFrom(.existing(b, at: end.position))
     }
 
@@ -167,7 +168,7 @@ extension SketchEditorModel {
         guard radius > 1e-9 else { return }
         var edited = sketch
         edited.addCircle(center: center.point(in: &edited), radius: radius, isConstruction: isConstruction)
-        commit(edited, "Circle")
+        commit(edited, "Circle", named: SketchStepName.addCircle)
         drawState = .idle
     }
 
@@ -186,7 +187,7 @@ extension SketchEditorModel {
             let s = start.point(in: &edited)
             let e = end.point(in: &edited)
             edited.addArc(center: c, start: s, end: e, isConstruction: isConstruction)
-            commit(edited, "Arc")
+            commit(edited, "Arc", named: SketchStepName.addArc)
             drawState = .idle
         default:
             drawState = .arcAround(target)
@@ -210,7 +211,7 @@ extension SketchEditorModel {
             let c = edited.addPoint(arc.center)
             edited.addArc(center: c, start: arc.isCounterClockwise ? s : e, end: arc.isCounterClockwise ? e : s,
                           isConstruction: isConstruction)
-            commit(edited, "Arc")
+            commit(edited, "Arc", named: SketchStepName.addArc)
             drawState = .idle
         default:
             drawState = .arcThroughFrom(anchor(at: p, tolerance: tolerance, suppressed: suppressed))
```

`Sources/CreatorSketchEditor/SketchEditorModel+Fillet.swift`

```diff
diff --git a/Sources/CreatorSketchEditor/SketchEditorModel+Fillet.swift b/Sources/CreatorSketchEditor/SketchEditorModel+Fillet.swift
--- a/Sources/CreatorSketchEditor/SketchEditorModel+Fillet.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel+Fillet.swift
@@ -12,7 +12,7 @@ extension SketchEditorModel {
         }
         let current = sketch
         let radius = options.filletRadius
-        apply { () throws(SketchCommandError) in try SketchCommands.fillet(current, corner: corner, radius: radius) }
+        apply(SketchStepName.fillet) { () throws(SketchCommandError) in try SketchCommands.fillet(current, corner: corner, radius: radius) }
     }
 
     /// The typed fillet radius ("2.5", "2.5 mm"). Not an edit, so not an undo step; text that isn't a size more than
```

`Sources/CreatorSketchEditor/SketchEditorModel+Project.swift`

```diff
diff --git a/Sources/CreatorSketchEditor/SketchEditorModel+Project.swift b/Sources/CreatorSketchEditor/SketchEditorModel+Project.swift
--- a/Sources/CreatorSketchEditor/SketchEditorModel+Project.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel+Project.swift
@@ -28,7 +28,7 @@ extension SketchEditorModel {
             refusal = left.first ?? "There is nothing there to project."
             return
         }
-        commit(edited, "Project", projections: writes)
+        commit(edited, "Project", named: SketchStepName.project, projections: writes)
         if !left.isEmpty { refusal = left.joined(separator: " ") }
     }
 
```

`Sources/CreatorSketchEditor/SketchEditorModel+Selection.swift`

```diff
diff --git a/Sources/CreatorSketchEditor/SketchEditorModel+Selection.swift b/Sources/CreatorSketchEditor/SketchEditorModel+Selection.swift
--- a/Sources/CreatorSketchEditor/SketchEditorModel+Selection.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel+Selection.swift
@@ -28,7 +28,7 @@ extension SketchEditorModel {
         var edited = sketch
         edited.add(constraint)
         selection = []
-        commit(edited, kind.title)
+        commit(edited, kind.title, named: SketchStepName.addConstraint)
     }
 
     /// Delete: removes the selected entities with everything built on them and every constraint and dimension on
@@ -51,6 +51,6 @@ extension SketchEditorModel {
         }
         selection = []
         hovered = nil
-        commit(edited, "Delete")
+        commit(edited, "Delete", named: SketchStepName.delete)
     }
 }
```

`Sources/CreatorSketchEditor/SketchEditorModel.swift`

```diff
diff --git a/Sources/CreatorSketchEditor/SketchEditorModel.swift b/Sources/CreatorSketchEditor/SketchEditorModel.swift
--- a/Sources/CreatorSketchEditor/SketchEditorModel.swift
+++ b/Sources/CreatorSketchEditor/SketchEditorModel.swift
@@ -92,14 +92,14 @@ public final class SketchEditorModel {
     }
 
     /// Takes `edited` as the sketch, solved and remembered, and hands it to the host as one undo step.
-    func commit(_ edited: Sketch, _ description: String, projections: [ProjectionWrite] = []) {
+    func commit(_ edited: Sketch, _ description: String, named name: String, projections: [ProjectionWrite] = []) {
         let solved = SketchSolver.solve(edited)
         let remembered = Self.remembering(edited, solved)
         solution = solved
         sketch = remembered
         stored = remembered
         refusal = nil
-        events.committed(SketchCommit(sketch: remembered, description: description, projections: projections))
+        events.committed(SketchCommit(sketch: remembered, description: description, name: name, projections: projections))
     }
 
     /// `sketch` with `solution` as its warm start when the solve is usable (S4 → S5 handoff: the node then
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CreatorSketchEditorTests`
Expected: PASS, including "Test run with 9 tests in 1 suite passed" for `SketchStepNameTests`; every existing sketch editor test still passes (`description` is unchanged).

- [ ] **Step 5: Full run and lint**

Run: `swift test`, then `swiftlint lint --strict`.
Expected: exit 0, 11 run lines, 2131 tests (master + 35), no issues, no new warning, 0 lint violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorSketchEditor Tests/CreatorSketchEditorTests
git commit -m "feat(sketch-editor): every sketch commit carries a fixed step name"
```

---

### Task 4: The viewport, the picks, New Sketch on Face and the sketch editor's steps are named

**Files:**
- Modify: `Sources/CreatorGraph/UndoName.swift` (adds `UndoName.sketch(_:)`), `Sources/CreatorApp/AppModel+Viewport.swift`, `AppModel+Picking.swift`, `AppModel+NewSketch.swift`, `AppModel+Sketch.swift`
- Test: `Tests/CreatorAppTests/AppUndoNameTests.swift` (new, 6 tests)

**Interfaces:**
- Consumes: Tasks 1 to 3 (`SketchCommit.name`).
- Produces: `UndoName.sketch(_ name: String) -> String` (a `SketchCommit.name`, or "Edit Sketch" when blank); internal `AppModel.addRule(_:from:into:named:)`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorAppTests/AppUndoNameTests.swift`:

```swift
import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import Testing
@testable import CreatorApp
@testable import CreatorSketchEditor
@testable import CreatorViewport

/// The edits the app shell makes (viewport handle drags, edge picks, New Sketch on Face, the sketch editor's commits)
/// name their undo steps (named undo steps).
@MainActor
struct AppUndoNameTests {
    @Test func aHandleDragIsOneStepCalledDragHandle() async throws {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.extrude.id]
        await app.settle()
        let id = try #require(app.viewport.handles.first?.id)
        app.handleChanged(id, 12, .changed)
        app.handleChanged(id, 14, .changed)
        app.handleChanged(id, 16, .ended)
        #expect(app.document.undoName == "Drag Handle")
        app.document.undo()
        #expect(app.document.undoName == nil, "the drag was one step")
    }

    @Test func pickingEdgesIntoARuleAndSelectingEdgesOfAFaceAreNamed() async throws {
        var builder = GraphBuilder()
        let box = builder.solid()
        let rule = builder.add(EdgesByTagNode.self, at: Vector2(480, 0))
        let chamfer = builder.add(ChamferNode.self, at: Vector2(720, 0))
        let output = builder.add(OutputNode.self, at: Vector2(960, 0))
        builder.wire(box.extrude, "solid", to: rule, "solid")
        builder.wire(rule, "edges", to: chamfer, "edges")
        builder.wire(chamfer, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        app.editor.press(.pickEdgesInView, on: rule.id)
        app.handle(try #require(app.editor.inspectorRequest))
        await app.settle()
        app.viewportClicked(.edge(solid: 0, EdgeID(3)))
        app.finishPick()
        #expect(app.document.undoName == "Pick Edges", "into an existing rule")

        let solid = try #require(app.viewport.items.first?.solid)
        let edges = [EdgeID(1), EdgeID(3)]
        app.selectEdgesOfFace(ViewportFaceRef(solidIndex: 0, face: FaceID(1)), solid.topology.picks(for: edges), edges)
        #expect(app.document.undoName == "Select Edges of Face", "a new rule from the face menu")
    }

    @Test func pickingOnAFeatureFedByAnotherRuleAddsARuleCalledPickEdges() async throws {
        var builder = GraphBuilder()
        let box = builder.solid()
        let all = builder.add(AllEdgesNode.self, at: Vector2(480, 200))
        let fillet = builder.add(FilletNode.self, ["radius": .number(1)], at: Vector2(720, 0))
        let output = builder.add(OutputNode.self, at: Vector2(960, 0))
        builder.wire(box.extrude, "solid", to: all, "solid")
        builder.wire(all, "edges", to: fillet, "edges")
        builder.wire(fillet, "solid", to: output, "solid")
        let app = await makeApp(builder.graph)
        app.beginPick(for: fillet.id)
        let session = try #require(app.pick)
        #expect(session.rule == nil)
        app.finishPick()
        #expect(app.document.undoName == "Pick Edges")
    }

    @Test func newSketchOnFaceIsOneNamedStep() async throws {
        var builder = GraphBuilder()
        _ = builder.box()
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        await app.viewport.waitForMeshes()
        app.viewport.pick = { _ in .face(solid: 0, FaceID(1)) }
        let items = app.viewport.contextMenuItems(at: ScreenPoint(700, 450))
        let item = try #require(items.first { if case .newSketchOnFace = $0 { true } else { false } })
        app.viewport.choose(item)
        #expect(app.document.undoName == "New Sketch on Face")
    }

    @Test func aSketchCommitIsNamedByItsFixedStepName() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.sketch.id]
        app.editor.press(.editSketch, on: box.sketch.id)
        app.handle(try #require(app.editor.inspectorRequest))
        await app.settle()
        await app.viewport.waitForAnimation()
        let editor = try #require(app.sketch?.editor)
        app.storeSketch(SketchCommit(sketch: editor.sketch, description: "Vertical", name: "Add Constraint"))
        #expect(app.document.undoName == "Add Constraint")
        app.storeSketch(SketchCommit(sketch: editor.sketch, description: "Vertical", name: "  "))
        #expect(app.document.undoName == "Edit Sketch", "a commit with a blank name")
        app.storeSketch(SketchCommit(sketch: editor.sketch, description: "Vertical"))
        #expect(app.document.undoName == "Edit Sketch", "a commit made without a name")

        editor.choose(.line)
        editor.click(at: Vector2(0, 60), tolerance: 1, modifiers: [])
        editor.click(at: Vector2(30, 80), tolerance: 1, modifiers: [])
        await app.settle()
        #expect(app.document.undoName == "Add Line")
    }

    @Test func aRenamedDimensionNeverReachesTheMenu() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox()
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.sketch.id]
        app.editor.press(.editSketch, on: box.sketch.id)
        app.handle(try #require(app.editor.inspectorRequest))
        await app.settle()
        await app.viewport.waitForAnimation()
        let editor = try #require(app.sketch?.editor)
        let dimension = try #require(editor.sketch.dimensionIDs.first)
        editor.rename(dimension, to: "Plate width")
        await app.settle()
        #expect(app.document.undoName == "Rename Dimension")
        #expect(app.undoTitle == "Undo Rename Dimension", "not \"Undo Rename d1 to Plate width\"")
        editor.setValue("55", of: dimension)
        await app.settle()
        #expect(app.undoTitle == "Undo Change Dimension")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AppUndoNameTests`
Expected: the suite builds (Tasks 1 to 3 are in place) and FAILS: every name is the generic "Edit" (`Expectation failed: (app.document.undoName → "Edit") == "Drag Handle"`).

- [ ] **Step 3: Implement**

`Sources/CreatorApp/AppModel+NewSketch.swift`

```diff
diff --git a/Sources/CreatorApp/AppModel+NewSketch.swift b/Sources/CreatorApp/AppModel+NewSketch.swift
--- a/Sources/CreatorApp/AppModel+NewSketch.swift
+++ b/Sources/CreatorApp/AppModel+NewSketch.swift
@@ -39,5 +39,5 @@ extension AppModel {
         ]
         do {
-            try document.perform(.batch(commands))
+            try document.perform(.batch(commands), name: UndoName.newSketchOnFace)
         } catch {
             alert = .problem(AppProblem("No sketch was made", error.message))
```

`Sources/CreatorApp/AppModel+Picking.swift`

```diff
diff --git a/Sources/CreatorApp/AppModel+Picking.swift b/Sources/CreatorApp/AppModel+Picking.swift
--- a/Sources/CreatorApp/AppModel+Picking.swift
+++ b/Sources/CreatorApp/AppModel+Picking.swift
@@ -69,8 +69,9 @@ extension AppModel {
         do {
             if let rule = session.rule {
-                try document.perform(.setInput(rule, NodeSetting.picks, relativeToLevel(picks)), at: editor.graphPath)
+                try document.perform(.setInput(rule, NodeSetting.picks, relativeToLevel(picks)), at: editor.graphPath,
+                                     name: UndoName.pickEdges)
                 editor.selection = [rule]
             } else {
-                editor.selection = [try addRule(picks, from: session.source, into: session.consumer)]
+                editor.selection = [try addRule(picks, from: session.source, into: session.consumer, named: UndoName.pickEdges)]
             }
         } catch {
@@ -108,5 +109,5 @@ extension AppModel {
         }
         do {
-            editor.selection = [try addRule(.edgePicks(picks), from: source, into: nil)]
+            editor.selection = [try addRule(.edgePicks(picks), from: source, into: nil, named: UndoName.selectEdgesOfFace)]
         } catch {
             alert = .problem(AppProblem("No rule was made", error.message))
@@ -115,6 +116,7 @@ extension AppModel {
 
     /// Adds an Edges by Tag rule holding `picks`, wired from `source` and, when given, into `consumer` (replacing
-    /// its wire), as one undo step. It's placed between the two nodes, or beside `source`.
-    func addRule(_ picks: ConstantValue, from source: Endpoint, into consumer: Endpoint?) throws(GraphError) -> NodeID {
+    /// its wire), as one undo step called `name`. It's placed between the two nodes, or beside `source`.
+    func addRule(_ picks: ConstantValue, from source: Endpoint, into consumer: Endpoint?,
+                 named name: String) throws(GraphError) -> NodeID {
         let graph = editor.graph
         let from = graph.nodes[source.node]?.position ?? .zero
@@ -127,5 +129,5 @@ extension AppModel {
             commands.append(.connect(Link(from: Endpoint(node: rule.id, socket: "edges"), to: consumer)))
         }
-        try document.perform(.batch(commands), at: editor.graphPath)
+        try document.perform(.batch(commands), at: editor.graphPath, name: name)
         return rule.id
     }
```

`Sources/CreatorApp/AppModel+Sketch.swift`

```diff
diff --git a/Sources/CreatorApp/AppModel+Sketch.swift b/Sources/CreatorApp/AppModel+Sketch.swift
--- a/Sources/CreatorApp/AppModel+Sketch.swift
+++ b/Sources/CreatorApp/AppModel+Sketch.swift
@@ -71,5 +71,5 @@ extension AppModel {
         do {
             let commands = SketchStore.commands(storing: commit.sketch, in: node, graph: document.graph, projections: projections)
-            try document.perform(.batch(commands))
+            try document.perform(.batch(commands), name: UndoName.sketch(commit.name))
         } catch {
             alert = .problem(AppProblem("The sketch couldn't be changed", error.message))
```

`Sources/CreatorApp/AppModel+Viewport.swift`

```diff
diff --git a/Sources/CreatorApp/AppModel+Viewport.swift b/Sources/CreatorApp/AppModel+Viewport.swift
--- a/Sources/CreatorApp/AppModel+Viewport.swift
+++ b/Sources/CreatorApp/AppModel+Viewport.swift
@@ -43,5 +43,5 @@ extension AppModel {
             do {
                 try document.perform(.setInput(target.node, target.socket, .number(value)), at: editor.graphPath,
-                                     coalescingKey: "handle-\(id)")
+                                     coalescingKey: "handle-\(id)", name: UndoName.dragHandle)
             } catch {
                 alert = .problem(AppProblem("The value couldn't be changed", error.message))
```

`Sources/CreatorGraph/UndoName.swift`

```diff
diff --git a/Sources/CreatorGraph/UndoName.swift b/Sources/CreatorGraph/UndoName.swift
--- a/Sources/CreatorGraph/UndoName.swift
+++ b/Sources/CreatorGraph/UndoName.swift
@@ -52,4 +52,6 @@ public enum UndoName {
     public static let newSketchOnFace = "New Sketch on Face"
     public static let editSketch = "Edit Sketch"
+    /// A sketch editor commit: its fixed step name (`SketchCommit.name`, "Add Line"), or "Edit Sketch" when it has none.
+    public static func sketch(_ name: String) -> String { cleaned(name) ?? editSketch }
 
     /// The generic name, for a step whose caller gave none (or a blank one). No callers use it: a step called "Edit"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AppUndoNameTests`
Expected: PASS, "Test run with 6 tests in 1 suite passed".

- [ ] **Step 5: Full run and lint**

Run: `swift test`, then `swiftlint lint --strict`.
Expected: exit 0, 11 run lines, 2137 tests (master + 41), no issues, no new warning, 0 lint violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorGraph/UndoName.swift Sources/CreatorApp Tests/CreatorAppTests/AppUndoNameTests.swift
git commit -m "feat(app): handle drags, picks, New Sketch on Face and sketch commits name their undo steps"
```

---

### Task 5: The Edit menu and the top bar read "Undo <name>" / "Redo <name>"

**Files:**
- Modify: `Sources/CreatorApp/AppModel+Undo.swift`, `Sources/CreatorApp/AppCommands.swift`, `Sources/CreatorApp/TopBar.swift`
- Test: `Tests/CreatorAppTests/UndoTitleTests.swift` (new, 5 tests)

**Interfaces:**
- Consumes: `DocumentModel.undoName`, `redoName` (Task 1) and the names Tasks 2 to 4 give.
- Produces: `AppModel.undoTitle: String` ("Undo Add Note", plain "Undo" with nothing to undo) and `AppModel.redoTitle: String`. The views show these strings and nothing else. MetalUI re-evaluates the `commands` closure whenever the menu bar is needed (ruling `MN-I`), so the menu title follows the model without a MetalUI change.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorAppTests/UndoTitleTests.swift`:

```swift
import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import MetalUIText
import Testing
@testable import CreatorApp

/// The Edit menu and the top bar read "Undo <name>" and "Redo <name>" (named undo steps; parent spec §6.1). The views
/// show `AppModel.undoTitle` and `redoTitle`, so the titles are pinned on the model.
@MainActor
struct UndoTitleTests {
    @Test func withNothingToUndoOrRedoTheTitlesArePlain() async {
        let app = await makeApp()
        #expect(app.undoTitle == "Undo" && app.redoTitle == "Redo")
    }

    @Test func theTitlesNameTheStepsAndFollowUndoAndRedo() async throws {
        let app = await makeApp()
        app.editor.addNote(atScreen: Vector2(30, 40))
        #expect(app.undoTitle == "Undo Add Note" && app.redoTitle == "Redo")
        let note = try #require(app.editor.graph.stickies.keys.first)
        app.editor.canvasSelection = CanvasSelection(comments: [note])
        app.editor.deleteSelection()
        #expect(app.undoTitle == "Undo Delete")
        app.undo()
        #expect(app.undoTitle == "Undo Add Note" && app.redoTitle == "Redo Delete")
        app.undo()
        #expect(app.undoTitle == "Undo" && app.redoTitle == "Redo Add Note")
        app.redo()
        #expect(app.undoTitle == "Undo Add Note" && app.redoTitle == "Redo Delete")
    }

    @Test func anInputEditIsTitledByTheInputsLabel() async throws {
        var builder = GraphBuilder()
        let box = builder.box(distance: 10)
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.extrude.id]
        guard case .slider(let field, _)? = app.editor.inspectorPage.sections.first?.rows.dropFirst().first else {
            Issue.record("no Distance slider"); return
        }
        app.editor.setNumber(field, to: 33)
        #expect(app.undoTitle == "Undo Change \(field.label)")
    }

    @Test func aNewDocumentStartsWithPlainTitles() async {
        let app = await makeApp()
        app.editor.addNote(atScreen: Vector2(30, 40))
        app.undo()
        #expect(app.redoTitle == "Redo Add Note")
        app.newDocument()
        #expect(app.undoTitle == "Undo" && app.redoTitle == "Redo")
    }

    /// The top bar draws the title: two apps with one edit each, named differently, differ by the glyphs of the names.
    /// This counts glyphs (spaces draw none), so it is a smoke test that the name reaches the bar, not a text check; a
    /// font or shaping change may need its arithmetic revisited. Human check NU-2 is the real one.
    @Test func theTopBarDrawsTheTitle() async throws {
        func glyphs(_ app: AppModel) -> Int {
            let scene = renderFrame({ ZStack { TopBar(model: app) } }, size: Size(width: Pixels(1400), height: Pixels(100)),
                                    scaleFactor: 2, textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
            return scene.glyphs.count
        }
        func edited(named name: String) async throws -> AppModel {
            let app = await makeApp()
            try app.document.perform(.setSticky(StickyNote(frame: CanvasRect(origin: .zero, size: Vector2(160, 100)))), name: name)
            return app
        }
        let long = try await edited(named: "Add Note"), short = try await edited(named: "Move")
        #expect(glyphs(long) - glyphs(short) == "AddNote".count - "Move".count, "the step's name joins the Undo button")
        let undone = try await edited(named: "Add Note"), other = try await edited(named: "Move")
        undone.undo()
        other.undo()
        #expect(glyphs(undone) - glyphs(other) == "AddNote".count - "Move".count, "and then the Redo button")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter UndoTitleTests`
Expected: build FAIL: "value of type 'AppModel' has no member 'undoTitle'".

- [ ] **Step 3: Implement**

`Sources/CreatorApp/AppCommands.swift`

```diff
diff --git a/Sources/CreatorApp/AppCommands.swift b/Sources/CreatorApp/AppCommands.swift
--- a/Sources/CreatorApp/AppCommands.swift
+++ b/Sources/CreatorApp/AppCommands.swift
@@ -3,5 +3,6 @@ import MetalUI
 
 /// The menu bar (spec §6.1): File's New, Open…, Save, Save As… and the exports, Edit's Undo and Redo bound to
-/// the document (`AppModel.undo()`, which commits a typed value first), and View ▸ Theme (`ThemeMenu`: every theme
+/// the document (`AppModel.undo()`, which commits a typed value first), titled "Undo Add Note" by the step
+/// (`AppModel.undoTitle`, `redoTitle`), and View ▸ Theme (`ThemeMenu`: every theme
 /// with a checkmark on the current one, and Edit Themes…, spec §6.6). Commands run when nothing in the window claims
 /// their key first (a focused field keeps its own editing keys).
@@ -25,8 +26,8 @@ public enum AppCommands {
             }
             CommandGroup(replacing: .undoRedo) {
-                Button("Undo") { model.undo() }
+                Button(model.undoTitle) { model.undo() }
                     .keyboardShortcut("z")
                     .disabled(!model.document.canUndo)
-                Button("Redo") { model.redo() }
+                Button(model.redoTitle) { model.redo() }
                     .keyboardShortcut("z", modifiers: [.command, .shift])
                     .disabled(!model.document.canRedo)
```

`Sources/CreatorApp/AppModel+Undo.swift`

```diff
diff --git a/Sources/CreatorApp/AppModel+Undo.swift b/Sources/CreatorApp/AppModel+Undo.swift
--- a/Sources/CreatorApp/AppModel+Undo.swift
+++ b/Sources/CreatorApp/AppModel+Undo.swift
@@ -1,3 +1,14 @@
 extension AppModel {
+    /// The Edit menu's and the top bar's Undo title: "Undo Add Note" for the step Undo would take back, plain "Undo"
+    /// with nothing to undo (as macOS apps read). The names are `UndoName`s, in English and never saved.
+    public var undoTitle: String { Self.title("Undo", step: document.undoName) }
+
+    /// The Redo title: "Redo Add Note", or plain "Redo" with nothing to redo.
+    public var redoTitle: String { Self.title("Redo", step: document.redoName) }
+
+    private static func title(_ verb: String, step: String?) -> String {
+        step.map { "\(verb) \($0)" } ?? verb
+    }
+
     /// Undo, from the menu bar and the top bar. A typed but uncommitted inspector value is committed first, so
     /// ⌘Z undoes that value rather than the step before it, and the value can't be committed later, after the
```

`Sources/CreatorApp/TopBar.swift`

```diff
diff --git a/Sources/CreatorApp/TopBar.swift b/Sources/CreatorApp/TopBar.swift
--- a/Sources/CreatorApp/TopBar.swift
+++ b/Sources/CreatorApp/TopBar.swift
@@ -5,5 +5,5 @@ import CreatorStyle
 import MetalUI
 
-/// The glass top bar (spec §6.1): the document's name, the Preview menu, Undo, Redo and Export. While a sketch is
+/// The glass top bar (spec §6.1): the document's name, the Preview menu, Undo, Redo (each titled by its step, `AppModel.undoTitle`) and Export. While a sketch is
 /// open it holds the sketch toolbar instead (sketcher spec §8: "Toolbar (glass, top)"), in chrome opaque to the pointer.
 struct TopBar: Component {
@@ -31,7 +31,7 @@ struct TopBar: Component {
                     }
                     .pickerStyle(.menu)
-                    Button("Undo") { model.undo() }
+                    Button(model.undoTitle) { model.undo() }
                         .disabled(!model.document.canUndo)
-                    Button("Redo") { model.redo() }
+                    Button(model.redoTitle) { model.redo() }
                         .disabled(!model.document.canRedo)
                     Menu("Export") {
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter UndoTitleTests`
Expected: PASS, "Test run with 5 tests in 1 suite passed".

- [ ] **Step 5: Full run and lint**

Run: `swift test`, then `swiftlint lint --strict`.
Expected: exit 0, 11 run lines, 2142 tests (master + 46), no issues, no new warning, 0 lint violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorApp Tests/CreatorAppTests/UndoTitleTests.swift
git commit -m "feat(app): the Edit menu and the top bar read Undo <name> and Redo <name>"
```

---

### Task 6: Docs and the human-check group

**Files:**
- Modify: `CLAUDE.md`, `docs/superpowers/roadmap.md`, `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md`, `docs/verification/human-checks.md`

**Interfaces:**
- Consumes: the names and tests of Tasks 1 to 5 (the human checks cite them).
- Produces: nothing for code. No `docs/metalui-gaps.md` change: this track opens no MetalUI gap.

- [ ] **Step 1: CLAUDE.md, the roadmap row and the Errata note**

Apply:

```diff
diff --git a/CLAUDE.md b/CLAUDE.md
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -30,2 +30,3 @@ Groups C2 (the editor, §6: entering a group, breadcrumbs, the + sockets, the gr
 section, the viewport and the clipboard inside groups) code is done; its human checks (group GR) are pending.
+Named undo steps (plan `docs/superpowers/plans/2026-10-10-named-undo.md`) code is done; its human checks (group NU) are pending.
 
@@ -47,2 +48,14 @@ Module boundaries (dependency order):
   ones.
+  - Undo names: every undo step carries a short English name (`UndoStack.Entry.name`), given where the edit is made:
+    `DocumentModel.perform(_:at:coalescingKey:name:)` takes one of `UndoName`'s constants ("Add Note", "Move", "Delete");
+    without one (or a blank one) the step is "Edit", so a forgotten name shows as "Undo Edit" and fails the test of its
+    call site. A coalesced run keeps its first record's name. Names have no numbers and never include text the person
+    typed (a note, a group's or dimension's name); an input is named by its fixed label ("Change Width"), a node by its
+    type ("Add Box"). The sketch editor (graph-free) gives each `SketchCommit` a fixed `name` from `SketchStepName`
+    ("Add Line", "Change Dimension", "Fillet"; `SketchEditorModel.commit` requires `named:`), which `AppModel.storeSketch`
+    passes through `UndoName.sketch(_:)`; `SketchCommit.description` ("Rename d1 to Plate width") holds typed text and
+    numbers and is never a name. `DocumentModel.undoName` and `redoName` feed `AppModel.undoTitle` and `redoTitle`, which
+    the Edit menu (`AppCommands`) and the top bar (`TopBar`) show as "Undo <name>" and "Redo <name>" (plain "Undo"/"Redo"
+    with nothing to take back). Names are in memory only and not part of `.mcgraph`. Tests: `UndoNameTests`,
+    `EditorUndoNameTests`, `SketchStepNameTests`, `AppUndoNameTests`, `UndoTitleTests`.
   - Groups (`Sources/CreatorGraph/Groups`): `GroupDefinition`s live in `GraphContent.definitions` beside the top-level
diff --git a/docs/superpowers/roadmap.md b/docs/superpowers/roadmap.md
--- a/docs/superpowers/roadmap.md
+++ b/docs/superpowers/roadmap.md
@@ -45,3 +45,3 @@ Status key: ✅ done · 🔄 in progress · ⏳ ready to start · 🔒 blocked (
 | — | Comments (B): sticky notes and titled comment frames per graph (`Graph.stickies`, `Graph.frames`; saved under format 5, keys optional), Add Note (⌘⇧N, context menu), Frame Selection (⌘⇧C, context menu), frames that carry the nodes inside them, resize handle, box select / ⌘A / copy / cut / paste / delete / mixed drags, inspector editing (spec `2026-10-09-selection-groups-comments-design.md` §7, Errata (B: comments); plan `2026-10-09-comments.md`) | ✅ code done; human checks CM pending | Multi-select (A), Groups core (C1); C2 shows a definition's comments |
-| — | Named undo steps: label `UndoStack.Entry`/`DocumentModel.perform` so the Edit menu reads "Undo Add Note" for every edit, not only comments (Comments (B) User decision 1 keeps its undo steps unnamed) | ⏳ | Comments (B); touches `DocumentModel`, `UndoStack`, `AppCommands`, `TopBar` |
+| — | Named undo steps: label `UndoStack.Entry`/`DocumentModel.perform` so the Edit menu and the top bar read "Undo Add Note" for every edit, not only comments (Comments (B) User decision 1 kept its undo steps unnamed; plan `2026-10-10-named-undo.md`) | ✅ code done; human checks NU pending | Comments (B); touches `DocumentModel`, `UndoStack`, `AppCommands`, `TopBar` |
 | — | Comments: typing on the canvas — edit a note's text or a frame's title in place on the canvas (spec §8) | ⏳ after MetalUI C9 + the canvas double-click (C16) | Comments (B); gaps CM-a, S5-b |
diff --git a/docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md b/docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md
--- a/docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md
+++ b/docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md
@@ -265,4 +265,7 @@ Plan `2026-10-09-comments.md`.
   inverse the old; all four have `affectsResults == false` and touch no node.
-- §7 "Undo names" ('Add Note', 'Edit Note', …): MetalCreator's undo history has no step names (the menu says "Undo"),
-  so each change is pinned as exactly one undo step; showing names is a separate change to `UndoStack` and the menus.
+- §7 "Undo names" ('Add Note', 'Edit Note', …): when comments landed MetalCreator's undo history had no step names (the
+  menu said "Undo"), so each change was pinned as exactly one undo step. Named undo steps (plan
+  `2026-10-10-named-undo.md`) now give every step a name: Add Note, Edit Note (text and accent), Add Frame, Edit Frame
+  (title and accent), Move (a drag or an arrow run), Resize and Delete, plus Cut, Paste and Duplicate, and the Edit menu
+  and the top bar read "Undo Add Note", "Redo Delete" and so on.
 - §7 Frame membership is read from drawn centres when a move begins, and a nudge carries it too; ⌥-drag and copy/paste
```

- [ ] **Step 2: Add the human-check group**

Append to the end of `docs/verification/human-checks.md` (after the last line of group S5c; keep one blank line before it):

````markdown
## Group NU — named undo steps

**Status: PENDING.** Plan `2026-10-10-named-undo.md`, spec `2026-10-09-selection-groups-comments-design.md` §7 and its
Errata (B: comments), parent spec §6.1. The tests pin the names on the model (`UndoTitleTests` pins the titles and that the
top bar draws them); these check what a person reads in the real menu bar and window. Run `swift run MetalCreatorApp` on a
saved bracket.

- [ ] **NU-1 Edit menu.** Open the Edit menu with nothing edited: the items read "Undo" and "Redo", both greyed. Press
  Cmd+Shift+N (Add Note) and open Edit again: "Undo Add Note" is enabled and "Redo" is greyed. Press Cmd+Z and open Edit:
  "Undo" greyed, "Redo Add Note" enabled. Pinned: `theTitlesNameTheStepsAndFollowUndoAndRedo`. **Observed:**
- [ ] **NU-2 Top bar.** The top bar's buttons read the same as the menu at every step of NU-1 ("Undo Add Note", then
  "Redo Add Note"), and the row stays on one line at the default window width, with the name not clipped. Make the
  window narrower: **record what the bar does when "Undo Resize" and "Redo Delete" no longer fit.** Pinned:
  `theTopBarDrawsTheTitle`. **Observed:**
- [ ] **NU-3 Each kind of edit.** After each edit below, the Edit menu reads as given. Add a node from the palette: "Undo Add
  <the node's type>". Drag a node: "Undo Move". Press an arrow key a few times: "Undo Move" (one step). Wire two sockets:
  "Undo Connect"; drag the wire off its input: "Undo Disconnect". Change an inspector slider by dragging it: "Undo Change
  <the input's label>" (one step for the whole drag). Select nodes and press Delete: "Undo Delete"; Cmd+X: "Undo Cut";
  Cmd+V: "Undo Paste"; Cmd+D: "Undo Duplicate". Pinned: `EditorUndoNameTests`. **Observed:**
- [ ] **NU-4 Comments.** Add Note: "Undo Add Note". Type in its inspector and click away: "Undo Edit Note". Frame Selection:
  "Undo Add Frame". Retitle the frame: "Undo Edit Frame". Drag a note: "Undo Move". Drag its handle: "Undo Resize".
  Delete it: "Undo Delete". Pinned: `editingNotesAndFrames`, `movingResizingAndDeletingComments`. **Observed:**
- [ ] **NU-5 Groups.** Cmd+G on two nodes: "Undo Group". Rename the group in the inspector: "Undo Rename Group" (the name you
  typed is not in the menu). Inside, drop a wire on Group Output's +: "Undo Add Output Socket". Make Unique: "Undo Make
  Unique". Cmd+Shift+G: "Undo Ungroup". Pinned: `groupUngroupAndMakeUnique`, `groupDefinitionEditsEachHaveTheirOwnName`,
  `groupSocketsAreExposedMovedAndRemoved`. **Observed:**
- [ ] **NU-6 Viewport.** Drag a handle in the viewport: "Undo Drag Handle" (one step). Pick edges in view and press Done:
  "Undo Pick Edges". Right-click a face, Select Edges of Face: "Undo Select Edges of Face"; New Sketch on Face: "Undo New
  Sketch on Face". Pinned: `AppUndoNameTests`. **Observed:**
- [ ] **NU-6b Sketch editor.** In a sketch, draw a line, a circle and an arc, add a constraint, type a dimension value,
  rename a dimension to something long ("Plate width"), Expose it, trim, fillet with a radius you typed, mirror and pattern:
  the menu reads "Undo Add Line", "Add Circle", "Add Arc", "Add Constraint", "Change Dimension", "Rename Dimension"
  (never the name you typed), "Expose Dimension", "Trim", "Fillet" (no radius), "Mirror" and "Linear Pattern"/"Circular
  Pattern" (no count). Drag a point: "Undo Move Point". Pinned: `SketchStepNameTests`, `aRenamedDimensionNeverReachesTheMenu`.
  **Record whether any name reads badly or is too coarse (for example "Delete" for an entity and for a constraint).** **Observed:**
- [ ] **NU-7 Typed value.** Type a new number into an inspector field without pressing Return and open the Edit menu: it
  names the step before the typed value (the value commits when Cmd+Z runs). **Record what it reads and whether that
  surprises you.** Pinned: `anInputEditIsTitledByTheInputsLabel`. **Observed:**
- [ ] **NU-8 Files.** Save, close and reopen: the Edit menu reads plain "Undo" and "Redo" (names are not saved). New does the
  same. Pinned: `aNewDocumentStartsWithPlainTitles`. **Observed:**
````

- [ ] **Step 3: Verify nothing else moved**

Run: `git status --short` (only the four doc files are modified), then `swift test` and `swiftlint lint --strict` once more.
Expected: exit 0, 11 run lines, 2142 tests (master + 46), 0 lint violations.

- [ ] **Step 4: Check that every call site passes a name**

Run: `grep -rn "document.perform(\|\.edit(\|\bcommit(" Sources/CreatorEditor Sources/CreatorApp Sources/CreatorSketchEditor | grep -v "func "` and read each hit with the lines after it.
Expected: every `document.perform(`, `edit(` and `commit(` call (24 `perform` sites, 21 sketch `commit`s) passes `name:`/`named:` or a `SketchStepName`, (several calls span two lines, so the `name:` is on the next one), except `EditorModel.edit(_:coalescingKey:name:)`'s own forwarding and the unrelated `PendingEntry.commit(_:)` and `DimensionField` `commit()`. A call without one would show as "Undo Edit".

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs
git commit -m "docs: named undo steps are code-done; human checks NU"
```

---

## Self-Review

**Spec coverage.** Comments spec §7 names: Add Note (`addNote`), Edit Note (`setNoteText`, accent), Add Frame (`addFrameAroundSelection`), Edit Frame (title, accent), Move (drag, nudge), Resize (handle), Delete (`deleteSelection`): `EditorUndoNameTests` (`addingNotesAndFrames`, `editingNotesAndFrames`, `movingResizingAndDeletingComments`). Graph edits: add/delete/move/duplicate/paste/cut, connect/disconnect, inputs (discrete, slider-coalesced, clear), parameters, arrow nudges: Task 2 tests one-for-one. Group, Ungroup, Make Unique, definition edits (rename, accent, sockets, delete) and the "+" sockets: `groupUngroupAndMakeUnique`, `groupDefinitionEditsEachHaveTheirOwnName`, `groupSocketsAreExposedMovedAndRemoved`, `deletingAnUnusedGroup`. Sketch editor steps (21 commit sites, fixed names by kind, none with typed text or a number): `SketchStepNameTests`. Viewport handle drags, edge picks (both paths), New Sketch on Face, sketch commits through the host: `AppUndoNameTests`. "Anything else that calls DocumentModel.perform": every call site is listed in File Structure, Task 6 Step 4 greps them, and a future caller that forgets gets "Edit" (`withoutANameTheStepIsCalledEdit`), which the tests of every existing call site would have caught (mutation-checked in the scratch copy). Parent spec §4.5 (a coalesced run is one step): first name kept (`aCoalescedRunKeepsItsFirstRecordsName`). §6.1 (menu bar, top bar): Task 5. No file-format change: names are never encoded (`UndoStack` is not `Codable`; `GraphFile` is untouched). Roadmap row, Errata note and CLAUDE.md: Task 6. Human-check group: NU-1 to NU-8 (with NU-6b).

**Placeholder scan.** No TBD/TODO; every code step shows its code or its exact diff against master `af4d99f`.

**Type consistency.** `UndoName.addNode(_ node: Node)` (Task 1) is what `EditorModel.add(_:)` calls (Task 2); `SketchStepName` and `SketchCommit.name` (Task 3) are what `UndoName.sketch(_:)` (Task 4) receives in `AppModel+Sketch`; `insert(_:offset:named:)` and `addRule(...named:)` are updated at every caller (`paste`, `duplicateSelection`, `finishDuplicate`, `CommentEditingTests`; `finishPick`, `selectEdgesOfFace`). `AppModel.undoTitle`/`redoTitle` are used by `AppCommands`, `TopBar` and `UndoTitleTests`.

**Review Focus.** Each of the six lines names its test above.

**Verification record.** The final tree (Tasks 1 to 6 applied to master `af4d99f`) was built and run in a scratch copy: a full `swift test` (exit 0, 11 "Test run with" lines totalling 2142, no "recorded an issue" / "failed after"), `swiftlint lint --strict` with 0 violations, no new warning. Mutation checks (remove one `name:` and expect a failing test): nudge, connect, delete/cut, edit note, node drag, disconnect, handle drag, New Sketch on Face, edge picks, a sketch step and the stack's own name each failed at least one test. The executor still runs the full suite after every task, as each task says.

## User decisions

Product behaviour the specs leave open. The plan is written for the recommended option of each.

1. **Typed text in a step name.** Options: (a) never: every name is fixed by kind, so a renamed dimension shows "Undo Rename Dimension"; (b) only for sketch dimensions: "Undo Rename d1 to Plate width", the sketch editor's own descriptions; (c) always: "Undo Rename Group Rib", "Undo Edit Note Hello". Recommended: (a). The cost of (b) is names with numbers ("Fillet Point 2 (5 mm)", "Linear pattern of 1 entity (×3)") and typed names that can be long; `SketchCommit.description` still carries those strings, so (b) is a one-line change in `AppModel.storeSketch` (`UndoName.sketch(commit.description)`) but then needs `Locale.messages` for the numbers and a length cap.
2. **A step whose caller gave no name.** Options: (a) "Edit" (the plan; a forgotten name is visible and tests catch it); (b) a name derived from the command ("Move", "Connect", ...), which reads better for a future caller but hides a forgotten name from every test. Recommended: (a).
3. **Sketch constraint steps.** Options: (a) "Add Constraint" (the plan); (b) "Add <kind>" ("Add Vertical", "Add Tangent"), which is more specific and still fixed text. Recommended: (a) until human check NU-6b says it is too coarse.
4. **Typed, uncommitted inspector value (NU-7).** Options: (a) the title names the step before the typed value until it commits (the plan: no state to track); (b) the title is "Undo Change <label>" while a value is pending. Recommended: (a).

