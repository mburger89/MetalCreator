# Groups core (C1): model and evaluation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Node groups' data model and evaluation (groups spec §4–§5): group definitions saved in `.mcgraph` (format 5), group nodes with their definition's sockets, a definition evaluated per instance under scoped node IDs so picks stay put, picks that keep naming their faces inside definitions and across Group / Ungroup / Make Unique, those commands and the definition edits as single undo steps, and ⌘G / ⇧⌘G in the graph panel on the top level.

**Architecture:** Definitions live beside the top-level graph in a new value type, `GraphContent` (`DocumentModel.content`), whose `apply(_:registry:)` runs every `GraphCommand` — graph commands on the top level, `.inDefinition(id, command)` inside a definition, and `addDefinition` / `removeDefinition` / `setInterface` — and refuses what breaks a group rule (a removed or retyped socket that is still wired is checked once the whole command has applied). `NodeRegistry` registers the three group types itself and carries the document's definitions (`withGroups(_:)`), so `registry.inputs(for:)` / `outputs(for:)` give every node its sockets, a group node its definition's. The `Evaluator` works level by level: a group node runs its definition's graph with Group Input handing on its gathered inputs unchanged, and inner nodes evaluate and cache under `NodeID.scoped(instance path + id)`, a name-based UUID, so tags differ per instance and survive definition edits. A pick stored in a definition names faces relative to it and is read per instance (`EvaluationScope.naming`). `GroupCommands` builds each group command as a `GroupEdit` (the command, the selection after it); Group, Ungroup and Make Unique rename, in the same batch, every pick whose faces they move (`GroupScopes.renamingPicks`).

**Tech Stack:** Swift 6.4 (strict concurrency), SwiftPM, Swift Testing, CryptoKit (`Insecure.SHA1` for version-5 UUIDs), OpenCascade 7.9 through `OCCTKernel` (tests only here), MetalUI (no new use).

**Spec:** `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` §4 and §5 (user-approved 2026-10-09; §2 for the format, §9 for the tests), under `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` with all its Errata. Reference for behaviour (read-only): `../MetalNodes`, `MetalNodesKit/Sources/MetalNodesCore/Groups/GroupOperations.swift`, `GroupDependencies.swift`, `ShaderDocument.swift`.

**Base:** branch `groups-core` off master `2e64c96` (1390 tests), beside `../MetalUI`. Run every command from the worktree root.

**Files shared with other tracks** (merge the second one by keeping both sides):
- Multi-select (A, `MetalCreator-msel`): `Sources/CreatorEditor/GraphKeyCommand.swift`, `GraphKeyBindings.swift` and `EditorModel+Commands.swift` (both add cases to the same enum and switches), `CLAUDE.md`, `docs/superpowers/roadmap.md` (A adds a row after "Viewport: frame in the model area"; this plan adds two after row 8, so the lines don't touch), and `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` (each appends its own Errata section at the end).
- Comments (B, not started): `Sources/CreatorGraph/AccentRole.swift` (this plan adds it as spec §7 lists it; B keeps it unchanged), `Sources/CreatorGraph/GraphFile.swift` and the three format-version tests (`EdgePickFileTests.swift`, `EdgePickRunCountFileTests.swift`, `ViewStateLibraryTests.swift`): one 4 → 5 bump between C1 and B (see Task 2), `CLAUDE.md`, the spec's errata. B's `stickies`/`frames` go in `Graph.swift`, which this plan doesn't touch; a definition's `graph` carries them for free.
- Sketcher S5b, kernel-invalid-blends, M7 measure: `CLAUDE.md` (each edits its own lines); M7 also `docs/superpowers/roadmap.md` (its own rows). Blends edits `BracketAcceptanceTests+PolygonSwap.swift`; this plan adds `BracketAcceptanceTests+Groups.swift` and uses `makeBracket()` unchanged.
- Groups editor (C2, after this): builds on `EditorModel+Groups.swift`, `GroupCommands`, `GraphPath`, `DocumentModel.perform(_:at:)` and `DocumentModel.innerResults` (the inner nodes' states it draws). C2 owns two things this plan leaves out, both on the roadmap's C2 row: a pick made in the viewport while a definition's inside is shown must be written relative to that level (the inverse of `EvaluationScope.names`; `GroupScopes.identity` names a node from a level), and spec §9's clipboard round trip: `NodeClipboard` carrying the definitions that copied group nodes use, merged by content on paste (today a group node pasted after its definition is gone, e.g. after undoing Group, is refused with "That group no longer exists."). Both are editor and clipboard code C2 rewrites anyway (boundary nodes can't be copied either).
- No other track touches `Sources/CreatorApp/AppModel.swift` or `AppModel+Files.swift` (Task 6); M7 edits `AppModel+Placement.swift` and S5b `AppModel+Picking.swift`, which this plan leaves alone.

**Minimal editor and app changes (C2 does the UI):** `NodeShape.swift`, `NodeRowModel.swift`, `InspectorBuilder.swift` (sockets from the registry, Task 3); `Sources/CreatorApp/AppModel.swift`, `AppModel+Files.swift` (`isEdited` compares the definitions too, Task 6); `GraphKeyCommand.swift`, `GraphKeyBindings.swift`, `EditorModel+Commands.swift`, new `EditorModel+Groups.swift` (⌘G/⇧⌘G, Task 10); `Sources/CreatorApp/AppModel+Viewport.swift` (Show Producing Node, Task 12). `CreatorNodes` and `CreatorKernel` are unchanged; `Package.swift` is unchanged.

## Global Constraints

- Platforms `.macOS(.v26)`; `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`: data races are compile errors. No `@unchecked Sendable`, no `nonisolated(unsafe)`.
- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), never XCTest.
- `swiftlint lint --strict` reports zero violations after every task; a `swiftlint:disable` carries its reason.
- No force unwraps and no force `try`; no Grand Central Dispatch; numbers shown to people use FormatStyle.
- One type per file; behaviour in models (`@MainActor @Observable` `DocumentModel` and `EditorModel`), views thin; editor geometry stays computed.
- Create nodes only through `NodeRegistry.makeNode` (group nodes through `makeGroupNode`, which calls it).
- Every command is one `DocumentModel.perform` step, so one undo step (spec §5).
- File format: `GraphFile.currentFormatVersion` goes 4 → 5 once, in whichever of C1 and B merges first; the other adds its keys under 5. `definitions` is optional on decode, so version-4 files open unchanged (spec §2).
- Spec wording, verbatim: definitions are named "Group", "Group 2", …; "An Output node can't go in a group."; inner messages read "Rib › Fillet: …"; Make Unique copies as "Name 2".
- Never edit `Package.swift`'s MetalUI path; never modify `../MetalUI`; a MetalUI gap goes in `docs/metalui-gaps.md` (this plan found none).
- OCCT stays behind `Kernel`; tests reach it only through `OCCTKernel`.
- A full `swift test` passes only if its exit code is 0, no line says "recorded an issue" or "failed after" (Swift Testing prints glyphs, not ✘), and 11 "Test run with" lines appear.
- No new compiler warning (master's one, `ContextMenuTests.swift:96`, stays).
- End each commit message with the attribution trailer your session gives, if any.

## Review Focus

Inputs the spec implies but no rule above names, most likely to bite first; each has its test in the owning task:

1. **⌘D or paste of a group node** places another instance of the same definition (the existing clipboard copies the `groupID` setting): `GroupKeyTests.duplicatingAGroupNodePlacesAnotherInstance` (Task 10).
2. **One inner output wired to several consumers** becomes one output socket, and every consumer is rewired to it: `GroupCommandTests.oneSourceWiredOutTwiceIsOneOutput` (Task 7).
3. **A selection holding a group node** groups into a nested group, and the part is unchanged: `GroupCommandTests.groupingAGroupNodeNestsItAndKeepsTheResult` (Task 7).
4. **Save and reopen** with picks on faces made inside groups: scoped IDs are derived, never saved, so the picks resolve to the same keys: the reopen half of `GroupNamingStabilityTests.editingTheDefinitionKeepsBothPicks` (Task 11).
5. **Show Producing Node on a face made inside a group** selects its group node instead of doing nothing: `GroupProducingNodeTests.aFaceMadeInsideAGroupShowsItsGroupNode` (Task 12).
6. **A pick across ⌘G**: a fillet or chamfer picked before grouping, on nodes grouped or around them, keeps its edges, in every instance: `BracketAcceptanceTests.groupingThePickedPlateKeepsTheChamfer`, `GroupNamingStabilityTests.aFilletPickedBeforeGroupingFilletsEveryInstance` (Task 11).

## Key decisions

1. **Sockets through the registry.** A node definition's static `inputs(for:)` can't see the document's definitions, so every reader asks `NodeRegistry.inputs(for:)` / `outputs(for:)` (new), which return a group node's, Group Input's and Group Output's sockets from the definition its `NodeSetting.group` names, and `NodeDefinition.inputs(for:)` / `outputs(for:)` (the latter new) for every other node. `DocumentModel.registry` carries the document's definitions, so `EditorModel.registry` (which is `document.registry`) does too. Recorded in Errata (C1).
2. **The three group types live in `CreatorGraph`** and every `NodeRegistry.init` registers them (the evaluator and the commands need them; `CreatorEditor` can't import `CreatorNodes`). `NodeRegistry.all`, the palette's and library's list, leaves them out. `BuiltInNodes` is unchanged (still 28).
3. **`GraphContent` + `.inDefinition`.** A "graph path" is `GraphPath.root` or `.definition(GroupID)`; `GraphCommand.at(_:)` addresses any graph command to one, and `DocumentModel.perform(_:at:)` is the shorthand. Group rules are checked in `GraphContent.apply`, so undo, redo and every builder go through the same checks.
4. **Scoped IDs** are version-5 UUIDs (SHA-1 of a fixed MetalCreator namespace and the path's UUID bytes) from the instance path (the group nodes from the top level down, each by its own ID in its graph) plus the inner node's ID. `CreatorKernel` is unchanged: `NodeTag`, `TopoTag`, `EdgePick`, `FacePick` and files keep their shape.
5. **Caching per instance path:** inner nodes are cached under their scoped identity; the group node itself isn't cached (its key joins its gathered key with Group Output's, so consumers miss when the inside changes). Entries from before a definition edit stay until the LRU budget drops them (as for any node, so undo hits the cache); entries of nodes no longer anywhere leave at the next evaluation.
6. **Group Output's inputs are optional:** an unwired one is an output the group node doesn't produce, so a half-built definition evaluates.
7. **Messages:** an inner error makes the group node's error "Definition › Node: message" (a nested group adds only its definition name: "Rib › Hole pattern › Fillet: …"); every inner warning line gets the same trail; an idle inner node leaves the group idle with its reason trailed.
8. **Group's sockets:** one input per distinct source outside (typed by the source's output, named after the first input it feeds, with that input's unit and range) and one output per distinct source inside wired out; both ordered by their node's place, top to bottom; names made unique as "a2", "a3" and never a setting's name ("groupID").
9. **Ungroup removes the definition with its last group node**; Make Unique also renames its group node to the copy's name; renaming a definition renames the group nodes still named after it.
10. **Picks never drift across group commands.** A pick stored in a definition names faces as if the definition were the top level (its nodes by ID, nodes inside its group nodes by `NodeID.scoped` of the path from it), and the evaluator maps those names to each instance's identities (Task 5), so a picked fillet inside a definition works in every instance. Group, Ungroup and Make Unique change the identities faces are made under, so each adds to its batch a `setInput` for every pick in the document that names a moved node's faces, through every chain of group nodes that reaches the level (Tasks 7, 8). Spec §5 expected Ungroup and Make Unique to drift and say so; they now don't, so `GroupEdit` has no notice (Errata (C1)).
11. **⌘G / ⇧⌘G are in this plan** (Task 10): the `EditorModel` actions and their keys are a few lines on the top level. C2 switches `.root` to the level shown and adds the context menu.
12. **Format 4 → 5 here**, written so that B, merging second, adds its keys under 5.
13. **Show Producing Node** (Task 12) is a small app fix this plan causes: faces made inside groups name scoped IDs.
14. **Messages without results.** A new definition name, accent or inner node name changes no result (`GraphContent.affectsResults` compares sockets), but a name is in the group's trail, so `DocumentModel` re-evaluates from the cache without marking anything evaluating (`affectsMessages`); an accent re-evaluates nothing.
15. **Edited state counts definitions:** `AppModel.isEdited` compares `document.content` with `savedContent` (Task 6).

## MetalUI gaps

None new. The canvas double-click C2 needs is the known GI-a (spec §8).

## File structure

`Sources/CreatorGraph/Groups/` (new folder, one type per file):

| File | Responsibility | Task |
|---|---|---|
| `GroupID.swift`, `GroupInterface.swift`, `GroupDefinition.swift`, `GroupDefinition+Codable.swift`, `GroupDefinition+Make.swift` | the definition model | 1 |
| `GroupNodes.swift`, `GroupNode.swift`, `GroupInputNode.swift`, `GroupOutputNode.swift` | the three node types | 1 |
| `NodeRegistry+Groups.swift` | sockets through the registry, `makeGroupNode` | 1 |
| `GraphPath.swift`, `GraphContent.swift`, `GraphContent+Apply.swift`, `GraphContent+Staleness.swift`, `GraphCommand+Path.swift`, `GraphCommand+GroupEdits.swift` | the document's graphs and commands on them | 4 |
| `GroupInstance.swift`, `GroupDependencies.swift`, `GroupNaming.swift`, `GroupRefusal.swift`, `GroupSocketSide.swift` | rules, names, messages | 4 |
| `NodeID+Scoped.swift`, `GroupScopes.swift`, `Graph+ScopedIDs.swift`, `EvaluationSetup.swift`, `EvaluationScope.swift`, `EvaluationLevel.swift`, `EvaluationTrace.swift`, `GroupTrail.swift`, `Evaluator+Groups.swift` | evaluation inside groups | 5 |
| `ConstantValue+TagRenaming.swift`, `Node+TagRenaming.swift` | renaming the tags picks name | 5 |
| `GroupEdit.swift`, `GroupScopes+PickRenaming.swift`, `GroupBuilder.swift`, `GroupCommands.swift` | Group | 7 |
| `GroupSplice.swift`, `GroupCommands+Ungroup.swift`, `GroupCommands+MakeUnique.swift` | Ungroup, Make Unique | 8 |
| `GroupCommands+Interface.swift` | definition edits | 9 |
| `GraphContent+Producers.swift` | which top-level node made a face | 12 |

Elsewhere: `Sources/CreatorGraph/AccentRole.swift`, `SocketSpec+Codable.swift`, `Evaluator+Running.swift` (new); `SocketSpec.swift`, `NodeSetting.swift`, `ConstantValue+Settings.swift`, `NodeDefinition.swift`, `NodeRegistry.swift`, `GraphFile.swift`, `GraphFileIO.swift`, `Graph+Connections.swift`, `GraphCommand.swift`, `Graph+Commands.swift`, `EvaluationReport.swift`, `Evaluator.swift`, `DocumentModel.swift` (modified); the editor and app files listed above. Tests: `Tests/CreatorGraphTests/Groups/` (new), `Support/GroupFixtures.swift`, `Support/GroupScene.swift`, `Support/FacePickCountNode.swift`, `Tests/CreatorAppTests/GroupEditedTests.swift`, `Tests/CreatorEditorTests/GroupSocketDisplayTests.swift`, `GroupKeyTests.swift`, `Tests/CreatorNodesTests/BracketAcceptanceTests+Groups.swift`, `GroupNamingStabilityTests.swift`, `Tests/CreatorAppTests/GroupProducingNodeTests.swift`.

## Tasks

| # | Task | Tests after |
|---|---|---|
| 1 | The group model: definitions, group node types, sockets through the registry | master + 9 = 1399 |
| 2 | File format 5: definitions in `.mcgraph` | master + 14 = 1404 |
| 3 | Wiring and drawing group sockets | master + 19 = 1409 |
| 4 | `GraphContent`: commands inside definitions and the group rules | master + 33 = 1423 |
| 5 | Evaluating group nodes under scoped node IDs | master + 45 = 1435 |
| 6 | `DocumentModel` holds the definitions | master + 51 = 1441 |
| 7 | Group (⌘G's command) | master + 61 = 1451 |
| 8 | Ungroup and Make Unique | master + 68 = 1458 |
| 9 | Definition edits: rename, accent, sockets, delete | master + 76 = 1466 |
| 10 | ⌘G and ⇧⌘G in the graph panel | master + 80 = 1470 |
| 11 | On OCCT: the grouped bracket and naming stability | master + 86 = 1476 |
| 12 | Show Producing Node on a face made inside a group | master + 88 = 1478 |
| 13 | Docs: CLAUDE.md, roadmap, spec errata | master + 88 = 1478 |

Code blocks are complete. A **Modify** step gives a unified diff against the file as the previous task left it; apply it with `git apply` (paste the block into a file) or make the same edits by hand.

---

### Task 1: The group model: definitions, group node types, sockets through the registry

Adds the data of spec §4: `GroupID`, `AccentRole`, `GroupInterface`, `GroupDefinition` (Codable, `make`), the three node types (`group`, `groupInput`, `groupOutput`, registered by every `NodeRegistry`), the `groupID` setting, `SocketSpec: Codable`, `NodeDefinition.outputs(for:)`, and `NodeRegistry.inputs(for:)`/`outputs(for:)`/`withGroups(_:)`/`makeGroupNode(_:for:at:)`. Nothing reads them yet.

**Files:**
- Create: `Sources/CreatorGraph/AccentRole.swift`
- Modify: `Sources/CreatorGraph/SocketSpec.swift`
- Create: `Sources/CreatorGraph/SocketSpec+Codable.swift`
- Create: `Sources/CreatorGraph/Groups/GroupID.swift`
- Create: `Sources/CreatorGraph/Groups/GroupInterface.swift`
- Create: `Sources/CreatorGraph/Groups/GroupDefinition.swift`
- Create: `Sources/CreatorGraph/Groups/GroupDefinition+Codable.swift`
- Create: `Sources/CreatorGraph/Groups/GroupDefinition+Make.swift`
- Create: `Sources/CreatorGraph/Groups/GroupNodes.swift`
- Create: `Sources/CreatorGraph/Groups/GroupNode.swift`
- Create: `Sources/CreatorGraph/Groups/GroupInputNode.swift`
- Create: `Sources/CreatorGraph/Groups/GroupOutputNode.swift`
- Modify: `Sources/CreatorGraph/NodeRegistry.swift`
- Create: `Sources/CreatorGraph/Groups/NodeRegistry+Groups.swift`
- Modify: `Sources/CreatorGraph/NodeSetting.swift`
- Modify: `Sources/CreatorGraph/ConstantValue+Settings.swift`
- Modify: `Sources/CreatorGraph/NodeDefinition.swift`
- Test: `Tests/CreatorGraphTests/Support/GroupFixtures.swift`
- Test: `Tests/CreatorGraphTests/Groups/GroupModelTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `public struct GroupID: Hashable, Sendable, Codable, Comparable` (`rawValue: UUID`, `init(rawValue: UUID = UUID())`).
  - `public enum AccentRole: String, Sendable, Codable, CaseIterable { case cyan, green, orange, pink, purple, yellow, muted }`.
  - `public struct GroupInterface: Sendable, Equatable { name: String; accent: AccentRole; inputs: [SocketSpec]; outputs: [SocketSpec] }`.
  - `public struct GroupDefinition: Sendable, Equatable, Codable { let id; var name, accent, inputs, outputs, graph: Graph; var interface: GroupInterface; var inputNode: Node?; var outputNode: Node? }`, `init(id:name:accent: = .purple, inputs:outputs:graph:)`, `static func make(id:name:accent:inputs:outputs:registry:inputAt:outputAt:) -> GroupDefinition`, `defaultInputPosition` (−240, 0), `defaultOutputPosition` (240, 0).
  - `public enum GroupNodes { groupTypeID = "group", inputTypeID = "groupInput", outputTypeID = "groupOutput", typeIDs, static func isBoundary(_ node: Node) -> Bool }`; `GroupNode`, `GroupInputNode`, `GroupOutputNode: NodeDefinition`.
  - `NodeSetting.group: SocketName = "groupID"` (in `NodeSetting.all`); `ConstantValue.group(_ id: GroupID)`, `ConstantValue.groupID: GroupID?`.
  - `NodeDefinition.outputs(for node: Node) -> [SocketSpec]` (default: `outputs`).
  - `NodeRegistry.groups: [GroupID: GroupDefinition]` (`internal(set)`), `withGroups(_:) -> NodeRegistry`, `group(of: Node) -> GroupDefinition?`, `inputs(for: Node) -> [SocketSpec]`, `outputs(for: Node) -> [SocketSpec]`, `makeGroupNode(_ typeID: String, for: GroupID, at: Vector2 = .zero) -> Node`; `all` leaves the group types out.
  - `SocketSpec: Codable`; `SocketSpec.Access: String, Codable`.
  - Test fixtures (`Tests/CreatorGraphTests/Support/GroupFixtures.swift`): `struct Doubler` (`definition`, `input`, `output`, `add`, `id`), `instance(of:_:output:) -> Node`, `table(_:) -> [GroupID: GroupDefinition]`.

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorGraphTests/Support/GroupFixtures.swift`:

```swift
// Test fixture file: a small group definition and helpers shared by the group tests.
import CreatorKernel
@testable import CreatorGraph

/// "Doubler": one number input `value` (default 1) and one number output `result`. Inside, Group Input's `value`
/// feeds both of an Add's inputs and the Add's `sum` feeds Group Output's `result`, so the group doubles its input.
struct Doubler {
    var definition: GroupDefinition
    let input: Node
    let output: Node
    let add: Node

    init(name: String = "Doubler") {
        let id = GroupID()
        input = testRegistry.makeGroupNode(GroupNodes.inputTypeID, for: id, at: GroupDefinition.defaultInputPosition)
        output = testRegistry.makeGroupNode(GroupNodes.outputTypeID, for: id, at: GroupDefinition.defaultOutputPosition)
        add = testRegistry.makeNode(AddNode.typeID)
        var inside = graph([input, add, output], [
            link(input, "value", add, "a"), link(input, "value", add, "b"), link(add, "sum", output, "result"),
        ])
        inside.sortLinks()  // As commands and decoding keep them, so a round trip compares equal.
        definition = GroupDefinition(id: id, name: name, inputs: [SocketSpec("value", .number, defaultValue: .number(1))],
                                     outputs: [SocketSpec("result", .number)], graph: inside)
    }

    var id: GroupID { definition.id }
}

/// A group node of `definition`, made as the editor makes one.
func instance(of definition: GroupDefinition, _ values: [SocketName: ConstantValue] = [:], output: Bool = false) -> Node {
    var node = testRegistry.withGroups([definition.id: definition]).makeGroupNode(GroupNodes.groupTypeID, for: definition.id)
    node.inputValues.merge(values) { _, given in given }
    node.isOutput = output
    return node
}

/// `definitions` keyed by ID.
func table(_ definitions: [GroupDefinition]) -> [GroupID: GroupDefinition] {
    Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
}
```

**Create** `Tests/CreatorGraphTests/Groups/GroupModelTests.swift`:

```swift
import Foundation
import Testing
@testable import CreatorGraph

struct GroupModelTests {
    @Test func everyRegistryMakesGroupNodesButThePaletteDoesNotListThem() throws {
        for typeID in [GroupNodes.groupTypeID, GroupNodes.inputTypeID, GroupNodes.outputTypeID] {
            #expect(testRegistry[typeID] != nil)
            #expect(testRegistry.makeNode(typeID).typeID == typeID)
        }
        #expect(testRegistry.makeNode(GroupNodes.groupTypeID).name == "Group")
        #expect(!testRegistry.all.contains { GroupNodes.typeIDs.contains($0.typeID) })
        #expect(testRegistry.all.count == 18)
    }

    @Test func aGroupNodesSocketsAreItsDefinitions() {
        let doubler = Doubler()
        let registry = testRegistry.withGroups(table([doubler.definition]))
        let node = instance(of: doubler.definition)
        #expect(node.name == "Doubler")
        #expect(node.inputValues[NodeSetting.group] == .group(doubler.id))
        #expect(registry.inputs(for: node) == doubler.definition.inputs)
        #expect(registry.outputs(for: node) == doubler.definition.outputs)
        #expect(registry.outputs(for: doubler.input) == doubler.definition.inputs)
        #expect(registry.inputs(for: doubler.input).isEmpty)
        #expect(registry.inputs(for: doubler.output).map(\.name) == ["result"])
        #expect(registry.inputs(for: doubler.output).allSatisfy { $0.isOptional })
        #expect(registry.outputs(for: doubler.output).isEmpty)
        // A registry without the document's definitions knows the type but not the sockets.
        #expect(testRegistry.inputs(for: node).isEmpty)
    }

    @Test func otherNodesKeepTheirTypesSockets() {
        let extra = makeNode(ExtraInputsNode.self, ["extra": .text("w,h")])
        #expect(testRegistry.inputs(for: extra).map(\.name) == ["value", "w", "h"])
        #expect(testRegistry.outputs(for: makeNode(AddNode.self)) == AddNode.outputs)
        #expect(testRegistry.inputs(for: Node(typeID: "missing.type", name: "Missing")).isEmpty)
    }

    @Test func aNewDefinitionHoldsOnlyItsBoundary() throws {
        let definition = GroupDefinition.make(name: "Rib", registry: testRegistry)
        #expect(definition.graph.nodes.count == 2)
        let input = try #require(definition.inputNode), output = try #require(definition.outputNode)
        #expect(input.inputValues[NodeSetting.group] == .group(definition.id))
        #expect(output.inputValues[NodeSetting.group] == .group(definition.id))
        #expect(input.position == GroupDefinition.defaultInputPosition)
        #expect(output.position == GroupDefinition.defaultOutputPosition)
        #expect(definition.accent == .purple)
    }

    @Test func theGroupSettingNamesADefinition() {
        let id = GroupID()
        #expect(ConstantValue.group(id).groupID == id)
        #expect(ConstantValue.text("garbage").groupID == nil)
        #expect(NodeSetting.all.contains(NodeSetting.group))
    }

    @Test func socketsRoundTripThroughJSON() throws {
        let specs = [
            SocketSpec("height", .number, defaultValue: .number(10), unit: .millimetres, range: 1...50),
            SocketSpec("tools", .solid, access: .list, optional: true),
        ]
        #expect(try JSONDecoder().decode([SocketSpec].self, from: JSONEncoder().encode(specs)) == specs)
        let minimal = try JSONDecoder().decode(SocketSpec.self, from: Data(#"{"name": "a", "type": "integer"}"#.utf8))
        #expect(minimal == SocketSpec("a", .integer))
    }

    @Test func aDefinitionRoundTripsThroughJSON() throws {
        var definition = Doubler().definition
        definition.accent = .cyan
        #expect(try JSONDecoder().decode(GroupDefinition.self, from: JSONEncoder().encode(definition)) == definition)
    }

    @Test func anUnknownAccentReadsAsPurple() throws {
        let json = #"{"id": "\#(UUID().uuidString)", "name": "Rib", "accent": "chartreuse"}"#
        let definition = try JSONDecoder().decode(GroupDefinition.self, from: Data(json.utf8))
        #expect(definition.accent == .purple)
        #expect(definition.graph == Graph())
    }

    @Test func theInterfaceIsNameAccentAndSockets() {
        var definition = Doubler().definition
        let interface = GroupInterface(name: "Twice", accent: .green, inputs: [], outputs: [SocketSpec("out", .number)])
        definition.interface = interface
        #expect(definition.interface == interface)
        #expect(definition.name == "Twice")
        #expect(definition.graph.nodes.count == 3)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning' | head`

Expected: error: cannot find type 'GroupDefinition' in scope (and `GroupID`, `GroupNodes`).

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorGraph/AccentRole.swift`:

```swift
/// A theme accent role (groups spec §4, §7): the accent of a group definition and of a canvas comment. It names a
/// role of the current theme, never a colour, so it follows theme changes. Shared with comments (track B): whichever
/// of C1 and B merges first adds this file, and the other keeps it unchanged.
public enum AccentRole: String, Sendable, Codable, CaseIterable {
    case cyan, green, orange, pink, purple, yellow, muted
}
```

**Modify** `Sources/CreatorGraph/SocketSpec.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorGraph/SocketSpec.swift b/Sources/CreatorGraph/SocketSpec.swift
index 250e112..2c97e97 100644
--- a/Sources/CreatorGraph/SocketSpec.swift
+++ b/Sources/CreatorGraph/SocketSpec.swift
@@ -1,7 +1,7 @@
 /// Declares one input or output socket of a node type.
 public struct SocketSpec: Sendable, Equatable {
     /// `.item` sockets broadcast over lists. `.list` sockets receive the whole list at once.
-    public enum Access: Sendable, Equatable { case item, list }
+    public enum Access: String, Sendable, Equatable, Codable { case item, list }
 
     public var name: SocketName
     public var type: SocketType
```

**Create** `Sources/CreatorGraph/SocketSpec+Codable.swift`:

```swift
/// A group definition saves its sockets (groups spec §4). Every key but `name` and `type` is optional on decode, with
/// the same defaults as `SocketSpec.init`.
extension SocketSpec: Codable {
    private enum CodingKeys: String, CodingKey { case name, type, access, defaultValue, unit, range, optional }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decode(SocketName.self, forKey: .name), try container.decode(SocketType.self, forKey: .type),
                  access: try container.decodeIfPresent(Access.self, forKey: .access) ?? .item,
                  defaultValue: try container.decodeIfPresent(ConstantValue.self, forKey: .defaultValue),
                  unit: try container.decodeIfPresent(ValueUnit.self, forKey: .unit) ?? .none,
                  range: try container.decodeIfPresent(ClosedRange<Double>.self, forKey: .range),
                  optional: try container.decodeIfPresent(Bool.self, forKey: .optional) ?? false)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(access, forKey: .access)
        try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        try container.encode(unit, forKey: .unit)
        try container.encodeIfPresent(range, forKey: .range)
        try container.encode(isOptional, forKey: .optional)
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupID.swift`:

```swift
import Foundation

/// Identity of a group definition (groups spec §4). Saved in the file and in each group node's `NodeSetting.group`.
public struct GroupID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: GroupID, rhs: GroupID) -> Bool { lhs.rawValue.uuidString < rhs.rawValue.uuidString }

    public var description: String { String(rawValue.uuidString.prefix(8)) }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupInterface.swift`:

```swift
/// What a group definition shows on the outside: its name, accent and sockets (groups spec §4).
/// `GraphCommand.setInterface` replaces it as one step; the inside is edited with `GraphCommand.inDefinition`.
public struct GroupInterface: Sendable, Equatable {
    public var name: String
    public var accent: AccentRole
    /// The group node's inputs, which are Group Input's outputs. Ordered; names unique.
    public var inputs: [SocketSpec]
    /// The group node's outputs, which are Group Output's inputs. Ordered; names unique.
    public var outputs: [SocketSpec]

    public init(name: String, accent: AccentRole, inputs: [SocketSpec], outputs: [SocketSpec]) {
        self.name = name
        self.accent = accent
        self.inputs = inputs
        self.outputs = outputs
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupDefinition.swift`:

```swift
/// A reusable sub-graph (groups spec §4): every group node naming it stands for its `graph`, with Group Input
/// standing for the node's inputs and Group Output for its outputs. Editing it updates every instance.
public struct GroupDefinition: Sendable, Equatable {
    public let id: GroupID
    /// Unique in the document, for example "Rib".
    public var name: String
    public var accent: AccentRole
    public var inputs: [SocketSpec]
    public var outputs: [SocketSpec]
    /// The inside: its nodes (exactly one Group Input and one Group Output among them) and links.
    public var graph: Graph

    public init(id: GroupID = GroupID(), name: String, accent: AccentRole = .purple, inputs: [SocketSpec] = [],
                outputs: [SocketSpec] = [], graph: Graph = Graph()) {
        self.id = id
        self.name = name
        self.accent = accent
        self.inputs = inputs
        self.outputs = outputs
        self.graph = graph
    }

    /// Name, accent and sockets: what `GraphCommand.setInterface` replaces.
    public var interface: GroupInterface {
        get { GroupInterface(name: name, accent: accent, inputs: inputs, outputs: outputs) }
        set {
            name = newValue.name
            accent = newValue.accent
            inputs = newValue.inputs
            outputs = newValue.outputs
        }
    }

    /// The Group Input node (the lowest ID if a hand-edited file has several).
    public var inputNode: Node? { boundaryNode(GroupNodes.inputTypeID) }

    /// The Group Output node (the lowest ID if a hand-edited file has several).
    public var outputNode: Node? { boundaryNode(GroupNodes.outputTypeID) }

    private func boundaryNode(_ typeID: String) -> Node? {
        graph.nodes.values.filter { $0.typeID == typeID }.min { $0.id < $1.id }
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupDefinition+Codable.swift`:

```swift
/// Saved in `GraphFile.definitions` (format 5). An accent this build doesn't know reads as purple, so a newer theme
/// role never stops a file from opening.
extension GroupDefinition: Codable {
    private enum CodingKeys: String, CodingKey { case id, name, accent, inputs, outputs, graph }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(GroupID.self, forKey: .id),
                  name: try container.decode(String.self, forKey: .name),
                  accent: (try? container.decodeIfPresent(AccentRole.self, forKey: .accent)) ?? .purple,
                  inputs: try container.decodeIfPresent([SocketSpec].self, forKey: .inputs) ?? [],
                  outputs: try container.decodeIfPresent([SocketSpec].self, forKey: .outputs) ?? [],
                  graph: try container.decodeIfPresent(Graph.self, forKey: .graph) ?? Graph())
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(accent, forKey: .accent)
        try container.encode(inputs, forKey: .inputs)
        try container.encode(outputs, forKey: .outputs)
        try container.encode(graph, forKey: .graph)
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupDefinition+Make.swift`:

```swift
import CreatorGeometry

extension GroupDefinition {
    /// Where `make` puts Group Input and Group Output when it isn't told.
    public static let defaultInputPosition = Vector2(-240, 0)
    public static let defaultOutputPosition = Vector2(240, 0)

    /// A definition whose inside holds only its Group Input and Group Output, both made by `registry.makeGroupNode`
    /// (so they carry this definition's ID in `NodeSetting.group`).
    public static func make(id: GroupID = GroupID(), name: String, accent: AccentRole = .purple, inputs: [SocketSpec] = [],
                            outputs: [SocketSpec] = [], registry: NodeRegistry,
                            inputAt: Vector2 = defaultInputPosition, outputAt: Vector2 = defaultOutputPosition) -> GroupDefinition {
        var definition = GroupDefinition(id: id, name: name, accent: accent, inputs: inputs, outputs: outputs)
        let input = registry.makeGroupNode(GroupNodes.inputTypeID, for: id, at: inputAt)
        let output = registry.makeGroupNode(GroupNodes.outputTypeID, for: id, at: outputAt)
        definition.graph.nodes[input.id] = input
        definition.graph.nodes[output.id] = output
        return definition
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupNodes.swift`:

```swift
/// The three node types groups are made of (groups spec §4). `NodeRegistry` registers them itself, so every registry
/// makes group nodes through `makeNode` and the evaluator, which runs them itself, finds them; the add-node palette and
/// the library don't list them (`NodeRegistry.all`).
public enum GroupNodes {
    /// A group node: one instance of the definition its `NodeSetting.group` names.
    public static let groupTypeID = "group"
    /// Inside a definition: stands for the group node's inputs (its outputs are the definition's inputs).
    public static let inputTypeID = "groupInput"
    /// Inside a definition: stands for the group node's outputs (its inputs are the definition's outputs).
    public static let outputTypeID = "groupOutput"

    public static let typeIDs: Set<String> = [groupTypeID, inputTypeID, outputTypeID]

    static let definitions: [any NodeDefinition.Type] = [GroupNode.self, GroupInputNode.self, GroupOutputNode.self]

    /// True for Group Input and Group Output, which exist only inside a definition, exactly once each.
    public static func isBoundary(_ node: Node) -> Bool {
        node.typeID == inputTypeID || node.typeID == outputTypeID
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupNode.swift`:

```swift
import CreatorKernel

/// A group node (groups spec §4): its sockets are its definition's (`NodeRegistry.inputs(for:)`/`outputs(for:)`), and
/// the evaluator runs the definition's graph in its place, so `evaluate` is never called.
public enum GroupNode: NodeDefinition {
    public static let typeID = GroupNodes.groupTypeID
    public static let displayName = "Group"
    public static let category = NodeCategory.feature
    public static let inputs: [SocketSpec] = []
    public static let outputs: [SocketSpec] = []

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        throw NodeError.invalidValue("A group is evaluated through its definition's graph.")
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupInputNode.swift`:

```swift
import CreatorKernel

/// Group Input (groups spec §4): inside a definition, its outputs are the group node's inputs. The evaluator hands it
/// the group node's gathered values unchanged, so `evaluate` is never called.
public enum GroupInputNode: NodeDefinition {
    public static let typeID = GroupNodes.inputTypeID
    public static let displayName = "Group Input"
    public static let category = NodeCategory.value
    public static let inputs: [SocketSpec] = []
    public static let outputs: [SocketSpec] = []

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        throw NodeError.invalidValue("Group Input takes its values from the group node.")
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupOutputNode.swift`:

```swift
import CreatorKernel

/// Group Output (groups spec §4): inside a definition, its inputs are the group node's outputs. The evaluator passes
/// what reaches it through unchanged, so `evaluate` is never called. Its inputs are optional: an unwired one is an
/// output the group node doesn't produce.
public enum GroupOutputNode: NodeDefinition {
    public static let typeID = GroupNodes.outputTypeID
    public static let displayName = "Group Output"
    public static let category = NodeCategory.value
    public static let inputs: [SocketSpec] = []
    public static let outputs: [SocketSpec] = []

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        throw NodeError.invalidValue("Group Output hands its values to the group node.")
    }
}
```

**Replace the whole of** `Sources/CreatorGraph/NodeRegistry.swift` with:

```swift
import CreatorGeometry

/// Maps type IDs to node definitions. It always holds the three group types (`GroupNodes`), and carries the open
/// document's group definitions (`groups`), which give group nodes their sockets.
public struct NodeRegistry: Sendable {
    private let definitions: [String: any NodeDefinition.Type]
    /// The document's group definitions. Empty in a bare registry; `DocumentModel.registry` carries the document's
    /// (`withGroups(_:)`).
    public internal(set) var groups: [GroupID: GroupDefinition] = [:]

    /// Duplicate type IDs are a programming error and trap. The group types are added here, so a caller never lists them.
    public init(_ definitions: [any NodeDefinition.Type]) {
        var map: [String: any NodeDefinition.Type] = [:]
        for definition in definitions + GroupNodes.definitions {
            precondition(map[definition.typeID] == nil, "Duplicate node typeID \(definition.typeID)")
            map[definition.typeID] = definition
        }
        self.definitions = map
    }

    public subscript(typeID: String) -> (any NodeDefinition.Type)? { definitions[typeID] }

    /// Every definition the add-node palette and the library offer, sorted by display name: all but the group types,
    /// which are made by grouping (groups spec §5).
    public var all: [any NodeDefinition.Type] {
        definitions.values.filter { !GroupNodes.typeIDs.contains($0.typeID) }.sorted { $0.displayName < $1.displayName }
    }

    /// A fresh node of a registered type: named after it, seeded with its `defaultSettings`, and
    /// flagged `isOutput` when its category is `.output`, so Output nodes join the evaluation
    /// demand on every creation path (palette, app, tests). An unregistered type gives a plain
    /// node with version 1 whose name is the type ID.
    public func makeNode(_ typeID: String, at position: Vector2 = .zero) -> Node {
        let definition = definitions[typeID]
        return Node(typeID: typeID, typeVersion: definition?.typeVersion ?? 1,
                    name: definition?.displayName ?? typeID, inputValues: definition?.defaultSettings ?? [:],
                    position: position, isOutput: definition?.category == .output)
    }
}
```

**Create** `Sources/CreatorGraph/Groups/NodeRegistry+Groups.swift`:

```swift
import CreatorGeometry

extension NodeRegistry {
    /// This registry carrying `groups`, so group nodes, Group Inputs and Group Outputs have their definitions' sockets.
    public func withGroups(_ groups: [GroupID: GroupDefinition]) -> NodeRegistry {
        var copy = self
        copy.groups = groups
        return copy
    }

    /// The definition a group node, Group Input or Group Output belongs to, if `groups` has it.
    public func group(of node: Node) -> GroupDefinition? {
        node.inputValues[NodeSetting.group]?.groupID.flatMap { groups[$0] }
    }

    /// A node's input sockets. Every reader of a node's sockets (wiring, evaluation, the canvas, the inspector) asks
    /// here: a group node's are its definition's inputs, Group Output's are the definition's outputs (optional, so an
    /// unwired one is an output the group doesn't produce), and any other node's are `inputs(for:)` of its type.
    public func inputs(for node: Node) -> [SocketSpec] {
        switch node.typeID {
        case GroupNodes.groupTypeID:
            group(of: node)?.inputs ?? []
        case GroupNodes.inputTypeID:
            []
        case GroupNodes.outputTypeID:
            (group(of: node)?.outputs ?? []).map { spec in
                var optional = spec
                optional.isOptional = true
                return optional
            }
        default:
            self[node.typeID]?.inputs(for: node) ?? []
        }
    }

    /// A node's output sockets: a group node's are its definition's outputs, Group Input's are the definition's
    /// inputs, and any other node's are `outputs(for:)` of its type.
    public func outputs(for node: Node) -> [SocketSpec] {
        switch node.typeID {
        case GroupNodes.groupTypeID: group(of: node)?.outputs ?? []
        case GroupNodes.inputTypeID: group(of: node)?.inputs ?? []
        case GroupNodes.outputTypeID: []
        default: self[node.typeID]?.outputs(for: node) ?? []
        }
    }

    /// A group node, Group Input or Group Output of definition `group`, made by `makeNode` with `NodeSetting.group`
    /// set. A group node is named after its definition when `groups` has it.
    public func makeGroupNode(_ typeID: String, for group: GroupID, at position: Vector2 = .zero) -> Node {
        var node = makeNode(typeID, at: position)
        node.inputValues[NodeSetting.group] = .group(group)
        if typeID == GroupNodes.groupTypeID, let definition = groups[group] { node.name = definition.name }
        return node
    }
}
```

**Modify** `Sources/CreatorGraph/NodeSetting.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorGraph/NodeSetting.swift b/Sources/CreatorGraph/NodeSetting.swift
index 314b236..54c9ade 100644
--- a/Sources/CreatorGraph/NodeSetting.swift
+++ b/Sources/CreatorGraph/NodeSetting.swift
@@ -15,8 +15,11 @@ public enum NodeSetting {
     public static let sketch: SocketName = "sketch"
     /// Plane from Face: the picked face, as `.facePick(topology.facePick(for:))`.
     public static let face: SocketName = "face"
+    /// Group, Group Input and Group Output: the definition they belong to, as `ConstantValue.group(_:)`
+    /// (groups spec §4). `NodeRegistry.makeGroupNode` sets it.
+    public static let group: SocketName = "groupID"
 
-    public static let all: Set<SocketName> = [parameter, picks, showHandle, sketch, face]
+    public static let all: Set<SocketName> = [parameter, picks, showHandle, sketch, face, group]
 
     /// The start of every projection setting's name, which no exposed dimension may use.
     public static let projectionPrefix = "projection."
```

**Modify** `Sources/CreatorGraph/ConstantValue+Settings.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorGraph/ConstantValue+Settings.swift b/Sources/CreatorGraph/ConstantValue+Settings.swift
index 4d8b7c2..753c447 100644
--- a/Sources/CreatorGraph/ConstantValue+Settings.swift
+++ b/Sources/CreatorGraph/ConstantValue+Settings.swift
@@ -11,4 +11,15 @@ extension ConstantValue {
         guard case .text(let raw) = self, let uuid = UUID(uuidString: raw) else { return nil }
         return ParameterID(rawValue: uuid)
     }
+
+    /// The `NodeSetting.group` value that ties a group node (or a Group Input or Output) to definition `id`.
+    public static func group(_ id: GroupID) -> ConstantValue {
+        .text(id.rawValue.uuidString)
+    }
+
+    /// The definition a `NodeSetting.group` value names, or `nil` if it isn't one.
+    public var groupID: GroupID? {
+        guard case .text(let raw) = self, let uuid = UUID(uuidString: raw) else { return nil }
+        return GroupID(rawValue: uuid)
+    }
 }
```

**Modify** `Sources/CreatorGraph/NodeDefinition.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorGraph/NodeDefinition.swift b/Sources/CreatorGraph/NodeDefinition.swift
index 02790a0..9b4983a 100644
--- a/Sources/CreatorGraph/NodeDefinition.swift
+++ b/Sources/CreatorGraph/NodeDefinition.swift
@@ -13,6 +13,9 @@ public protocol NodeDefinition: Sendable {
     /// its settings (the Sketch node's exposed dimensions, sketcher spec §7) adds more. The evaluator and
     /// `Graph.connectionProblem` read this, so a socket listed here can be wired and is gathered.
     static func inputs(for node: Node) -> [SocketSpec]
+    /// The output sockets of one node; the fixed `outputs` unless a type says otherwise. Read sockets through
+    /// `NodeRegistry.inputs(for:)`/`outputs(for:)`, which also give group nodes their definition's sockets.
+    static func outputs(for node: Node) -> [SocketSpec]
     static var inspector: [InspectorSection] { get }
     static var handles: [HandleSpec] { get }
     /// True if `evaluate` reads `context.parameters`, so parameter edits invalidate its cache.
@@ -30,6 +33,7 @@ public protocol NodeDefinition: Sendable {
 extension NodeDefinition {
     public static var typeVersion: Int { 1 }
     public static func inputs(for node: Node) -> [SocketSpec] { inputs }
+    public static func outputs(for node: Node) -> [SocketSpec] { outputs }
     public static var inspector: [InspectorSection] { [] }
     public static var handles: [HandleSpec] { [] }
     public static var readsParameters: Bool { false }
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning'` (expect no output: no error, no new warning), then `swift test --skip-build --filter 'CreatorGraphTests.GroupModelTests'`

Expected: `Test run with 9 tests in 1 suite passed`.

- [ ] **Step 5: Verify the whole package**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-test.log`.

Expected: exit code 0; `grep -c 'recorded an issue' /tmp/groups-test.log` and `grep -c 'failed after' /tmp/groups-test.log` print 0; `grep -c 'Test run with' /tmp/groups-test.log` prints 11; the counts on those lines add up to **1399** (master + 9).

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorGraph/AccentRole.swift' 'Sources/CreatorGraph/SocketSpec.swift' 'Sources/CreatorGraph/SocketSpec+Codable.swift' 'Sources/CreatorGraph/Groups/GroupID.swift' 'Sources/CreatorGraph/Groups/GroupInterface.swift' 'Sources/CreatorGraph/Groups/GroupDefinition.swift' 'Sources/CreatorGraph/Groups/GroupDefinition+Codable.swift' 'Sources/CreatorGraph/Groups/GroupDefinition+Make.swift' 'Sources/CreatorGraph/Groups/GroupNodes.swift' 'Sources/CreatorGraph/Groups/GroupNode.swift' 'Sources/CreatorGraph/Groups/GroupInputNode.swift' 'Sources/CreatorGraph/Groups/GroupOutputNode.swift' 'Sources/CreatorGraph/NodeRegistry.swift' 'Sources/CreatorGraph/Groups/NodeRegistry+Groups.swift' 'Sources/CreatorGraph/NodeSetting.swift' 'Sources/CreatorGraph/ConstantValue+Settings.swift' 'Sources/CreatorGraph/NodeDefinition.swift' 'Tests/CreatorGraphTests/Support/GroupFixtures.swift' 'Tests/CreatorGraphTests/Groups/GroupModelTests.swift'
git commit -m "feat(graph): group definitions, group node types and sockets through the registry"
```

---

### Task 2: File format 5: definitions in `.mcgraph`

`GraphFile` gains `definitions` (spec §2, §4): written as an array sorted by ID, optional on decode, so version-4 files open unchanged; `GraphFileIO.decode` migrates nodes inside definitions too. `currentFormatVersion` goes 4 → 5 here. **Coordination:** comments (B) add keys under the same version 5; whichever of C1 and B merges first bumps. This plan is written for 4 → 5; if B has already merged with 5, keep B's number and skip only the `currentFormatVersion` line (the three version tests then already say 5).

**Files:**
- Modify: `Sources/CreatorGraph/GraphFile.swift`
- Modify: `Sources/CreatorGraph/GraphFileIO.swift`
- Test: `Tests/CreatorGraphTests/Groups/GroupFileTests.swift`
- Modify test: `Tests/CreatorGraphTests/EdgePickFileTests.swift`
- Modify test: `Tests/CreatorGraphTests/EdgePickRunCountFileTests.swift`
- Modify test: `Tests/CreatorGraphTests/ViewStateLibraryTests.swift`

**Interfaces:**
- Consumes: Task 1: `GroupDefinition` (Codable), `GroupID`, the fixtures.
- Produces:
  - `GraphFile.definitions: [GroupID: GroupDefinition]`; `GraphFile.init(formatVersion:graph:definitions: = [:], viewState:)`; `GraphFile.currentFormatVersion == 5`.
  - `GraphFileIO.decode` migrates every definition's nodes.

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorGraphTests/Groups/GroupFileTests.swift`:

```swift
import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

struct GroupFileTests {
    @Test func definitionsRoundTripWithTheirInstances() throws {
        let doubler = Doubler()
        let node = instance(of: doubler.definition, ["value": .number(3)], output: true)
        let file = GraphFile(graph: graph([node]), definitions: table([doubler.definition]))
        let decoded = try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
        #expect(decoded == file)
    }

    @Test func definitionsAreWrittenSortedByID() throws {
        let definitions = (0..<4).map { GroupDefinition(name: "Group \($0)") }
        let data = try GraphFileIO.encode(GraphFile(definitions: table(definitions)))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let written = try #require(json["definitions"] as? [[String: Any]]).compactMap { $0["id"] as? String }
        #expect(written == definitions.map(\.id).sorted().map(\.rawValue.uuidString))
    }

    @Test func aVersionFourFileOpensWithNoDefinitions() throws {
        let id = NodeID()
        let json = """
        {"formatVersion": 4, "graph": {"nodes": [{"id": "\(id.rawValue.uuidString)", "typeID": "test.constant",
        "typeVersion": 1, "name": "Constant", "position": {"x": 0, "y": 0}, "isOutput": false,
        "inputValues": {"value": {"type": "number", "value": 2}}}]}}
        """
        let file = try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
        #expect(file.definitions.isEmpty)
        #expect(file.graph.nodes[id]?.inputValues["value"] == .number(2))
    }

    /// 5 since groups (C1). Comments (B) add their keys under the same version; whichever merges first bumps.
    @Test func savedFilesAreFormatFive() throws {
        #expect(GraphFile.currentFormatVersion == 5)
        let text = try #require(String(bytes: try GraphFileIO.encode(GraphFile()), encoding: .utf8))
        #expect(text.contains(#""formatVersion" : 5"#))
        #expect(text.contains(#""definitions" : ["#))
    }

    @Test func nodesInsideDefinitionsAreMigratedOnLoad() throws {
        var definition = GroupDefinition.make(name: "Old", registry: testRegistry)
        var old = makeNode(VersionedNode.self, ["old": .number(3)])
        old.typeVersion = 1
        definition.graph.nodes[old.id] = old
        let file = GraphFile(definitions: table([definition]))
        let decoded = try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
        let migrated = try #require(decoded.definitions[definition.id]?.graph.nodes[old.id])
        #expect(migrated.typeVersion == 2)
        #expect(migrated.inputValues == ["value": .number(3)])
    }
}
```

**Modify** `Tests/CreatorGraphTests/EdgePickFileTests.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Tests/CreatorGraphTests/EdgePickFileTests.swift b/Tests/CreatorGraphTests/EdgePickFileTests.swift
index 419eed2..bdf3858 100644
--- a/Tests/CreatorGraphTests/EdgePickFileTests.swift
+++ b/Tests/CreatorGraphTests/EdgePickFileTests.swift
@@ -25,12 +25,12 @@ struct EdgePickFileTests {
         #expect(decoded.graph.nodes[rule.id]?.inputValues["picks"] == .edgePicks(samplePicks()))
     }
 
-    /// 4 since S4 (`sketch` and `facePick` settings). Whichever of S4 and another format-bumping branch
+    /// 5 since groups (C1; 4 since S4's `sketch` and `facePick` settings). Whichever format-bumping branch
     /// merges second takes the next number and updates both literals here.
     @Test func savedFilesCarryTheCurrentFormatVersion() throws {
-        #expect(GraphFile.currentFormatVersion == 4)
+        #expect(GraphFile.currentFormatVersion == 5)
         let text = try #require(String(bytes: try GraphFileIO.encode(GraphFile()), encoding: .utf8))
-        #expect(text.contains(#""formatVersion" : 4"#))
+        #expect(text.contains(#""formatVersion" : 5"#))
     }
 
     @Test func versionTwoEdgePicksDecodeAsOuterWalls() throws {
```

**Modify** `Tests/CreatorGraphTests/EdgePickRunCountFileTests.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Tests/CreatorGraphTests/EdgePickRunCountFileTests.swift b/Tests/CreatorGraphTests/EdgePickRunCountFileTests.swift
index 2644553..2b6347a 100644
--- a/Tests/CreatorGraphTests/EdgePickRunCountFileTests.swift
+++ b/Tests/CreatorGraphTests/EdgePickRunCountFileTests.swift
@@ -21,12 +21,12 @@ struct EdgePickRunCountFileTests {
         return EdgePick(key: EdgeKey([top], [side]), matchCount: 2, runCount: 1)
     }
 
-    @Test func aRunCountRoundTripsThroughAVersionFourFile() throws {
+    @Test func aRunCountRoundTripsThroughACurrentFile() throws {
         let rule = makeNode(ConstantNode.self, ["picks": .edgePicks([split])])
         let data = try GraphFileIO.encode(GraphFile(graph: graph([rule])))
         let text = try #require(String(bytes: data, encoding: .utf8))
         #expect(text.contains(#""runCount" : 1"#))
-        #expect(text.contains(#""formatVersion" : 4"#))
+        #expect(text.contains(#""formatVersion" : \#(GraphFile.currentFormatVersion)"#))
         let decoded = try GraphFileIO.decode(data, registry: testRegistry)
         #expect(decoded.graph.nodes[rule.id]?.inputValues["picks"] == .edgePicks([split]))
     }
```

**Modify** `Tests/CreatorGraphTests/ViewStateLibraryTests.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Tests/CreatorGraphTests/ViewStateLibraryTests.swift b/Tests/CreatorGraphTests/ViewStateLibraryTests.swift
index 537ae66..de67b0f 100644
--- a/Tests/CreatorGraphTests/ViewStateLibraryTests.swift
+++ b/Tests/CreatorGraphTests/ViewStateLibraryTests.swift
@@ -22,6 +22,6 @@ struct ViewStateLibraryTests {
         let older = try JSONDecoder().decode(FormatThreeViewState.self, from: data)
         #expect(older.dock == .bottom)
         #expect(older.canvasZoom == 2)
-        #expect(GraphFile.currentFormatVersion == 4, "S4's bump only; the library's key added none")
+        #expect(GraphFile.currentFormatVersion == 5, "S4's and groups' bumps only; the library's key added none")
     }
 }
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning' | head`

Expected: error: extra argument 'definitions' in call.

- [ ] **Step 3: Implement**

**Replace the whole of** `Sources/CreatorGraph/GraphFile.swift` with:

```swift
/// The contents of a `.mcgraph` file: the recipe and the editor's view, no geometry (spec §4.5).
public struct GraphFile: Sendable, Codable, Equatable {
    /// 2: adds the `edgePicks` constant kind (M3). 3: side-face tags may carry a `loop` (S3, hole
    /// walls), which a version-2 reader would silently drop. 4: adds the `sketch` and `facePick` setting
    /// kinds (S4), which a version-3 reader can't decode. 5: adds group definitions (groups spec §2, §4), which a
    /// version-4 reader would drop while keeping group nodes that name them. Version-1 to -4 files still load unchanged.
    public static let currentFormatVersion = 5

    public var formatVersion: Int
    public var graph: Graph
    /// The document's group definitions (groups spec §4). Written as an array sorted by ID; absent in older files.
    public var definitions: [GroupID: GroupDefinition]
    public var viewState: ViewState

    public init(formatVersion: Int = GraphFile.currentFormatVersion, graph: Graph = Graph(),
                definitions: [GroupID: GroupDefinition] = [:], viewState: ViewState = ViewState()) {
        self.formatVersion = formatVersion
        self.graph = graph
        self.definitions = definitions
        self.viewState = viewState
    }

    private enum CodingKeys: String, CodingKey { case formatVersion, graph, definitions, viewState }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        graph = try container.decode(Graph.self, forKey: .graph)
        let list = try container.decodeIfPresent([GroupDefinition].self, forKey: .definitions) ?? []
        definitions = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        viewState = try container.decodeIfPresent(ViewState.self, forKey: .viewState) ?? ViewState()
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(graph, forKey: .graph)
        try container.encode(definitions.values.sorted { $0.id < $1.id }, forKey: .definitions)
        try container.encode(viewState, forKey: .viewState)
    }
}
```

**Replace the whole of** `Sources/CreatorGraph/GraphFileIO.swift` with:

```swift
import Foundation

/// Reads and writes `.mcgraph` JSON.
public enum GraphFileIO {
    private struct FormatHeader: Decodable {
        let formatVersion: Int
    }

    public static func encode(_ file: GraphFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    /// Decodes and migrates old node versions, on the top level and inside every group definition.
    /// Unknown node types are kept as-is.
    public static func decode(_ data: Data, registry: NodeRegistry) throws -> GraphFile {
        let header = try JSONDecoder().decode(FormatHeader.self, from: data)
        guard header.formatVersion <= GraphFile.currentFormatVersion else {
            throw GraphFileError.newerFormat(header.formatVersion)
        }
        var file = try JSONDecoder().decode(GraphFile.self, from: data)
        file.graph = migrated(file.graph, registry: registry)
        for (id, definition) in file.definitions {
            file.definitions[id]?.graph = migrated(definition.graph, registry: registry)
        }
        return file
    }

    private static func migrated(_ graph: Graph, registry: NodeRegistry) -> Graph {
        var graph = graph
        for (id, node) in graph.nodes {
            guard let definition = registry[node.typeID], node.typeVersion < definition.typeVersion else { continue }
            var migrated = definition.migrate(node, from: node.typeVersion)
            migrated.typeVersion = definition.typeVersion
            graph.nodes[id] = migrated
        }
        return graph
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning'` (expect no output: no error, no new warning), then `swift test --skip-build --filter 'GroupFileTests|EdgePickFileTests|EdgePickRunCountFileTests|ViewStateLibraryTests'`

Expected: `Test run with 17 tests in 4 suites passed`.

- [ ] **Step 5: Verify the whole package**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-test.log`.

Expected: exit code 0; `grep -c 'recorded an issue' /tmp/groups-test.log` and `grep -c 'failed after' /tmp/groups-test.log` print 0; `grep -c 'Test run with' /tmp/groups-test.log` prints 11; the counts on those lines add up to **1404** (master + 14).

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorGraph/GraphFile.swift' 'Sources/CreatorGraph/GraphFileIO.swift' 'Tests/CreatorGraphTests/Groups/GroupFileTests.swift' 'Tests/CreatorGraphTests/EdgePickFileTests.swift' 'Tests/CreatorGraphTests/EdgePickRunCountFileTests.swift' 'Tests/CreatorGraphTests/ViewStateLibraryTests.swift'
git commit -m "feat(graph): file format 5 saves group definitions"
```

---

### Task 3: Wiring and drawing group sockets

`Graph.connectionProblem` and the editor's readers (`NodeShape`, `NodeRowModel`, `InspectorBuilder`) take sockets from `registry.inputs(for:)`/`outputs(for:)`, so a group node wires, draws and inspects with its definition's sockets once the registry carries the document's definitions (Task 6). The look of a group node is C2's.

**Files:**
- Modify: `Sources/CreatorGraph/Graph+Connections.swift`
- Modify: `Sources/CreatorEditor/NodeShape.swift`
- Modify: `Sources/CreatorEditor/NodeRowModel.swift`
- Modify: `Sources/CreatorEditor/InspectorBuilder.swift`
- Test: `Tests/CreatorGraphTests/Groups/GroupWiringTests.swift`
- Test: `Tests/CreatorEditorTests/GroupSocketDisplayTests.swift`

**Interfaces:**
- Consumes: Task 1: `NodeRegistry.inputs(for:)`, `outputs(for:)`, `withGroups(_:)`, `makeGroupNode`.
- Produces: no new API; `connectionProblem(from:to:registry:)` keeps its signature.

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorGraphTests/Groups/GroupWiringTests.swift`:

```swift
import Testing
@testable import CreatorGraph

/// Wires reach a group node's sockets, and Group Input's and Group Output's, through the registry carrying the
/// document's definitions (groups spec §4).
struct GroupWiringTests {
    let doubler = Doubler()
    var registry: NodeRegistry { testRegistry.withGroups(table([doubler.definition])) }

    @Test func aWireReachesAGroupNodesInput() {
        let constant = makeNode(ConstantNode.self), group = instance(of: doubler.definition)
        let g = graph([constant, group])
        let from = Endpoint(node: constant.id, socket: "value"), to = Endpoint(node: group.id, socket: "value")
        #expect(g.connectionProblem(from: from, to: to, registry: registry) == nil)
        #expect(g.connectionProblem(from: from, to: to, registry: testRegistry) == .unknownSocket("value"))
    }

    @Test func aWireLeavesAGroupNodesOutput() {
        let group = instance(of: doubler.definition), add = makeNode(AddNode.self)
        let g = graph([group, add])
        let to = Endpoint(node: add.id, socket: "a")
        #expect(g.connectionProblem(from: Endpoint(node: group.id, socket: "result"), to: to, registry: registry) == nil)
        #expect(g.connectionProblem(from: Endpoint(node: group.id, socket: "nope"), to: to, registry: registry)
            == .unknownSocket("nope"))
    }

    @Test func insideTheBoundaryNodesWireLikeTheDefinitionsSockets() {
        let inside = doubler.definition.graph, box = makeNode(BoxNode.self)
        var withBox = inside
        withBox.nodes[box.id] = box
        let fromInput = Endpoint(node: doubler.input.id, socket: "value")
        #expect(inside.connectionProblem(from: fromInput, to: Endpoint(node: doubler.add.id, socket: "b"), registry: registry) == nil)
        let toOutput = Endpoint(node: doubler.output.id, socket: "result")
        #expect(inside.connectionProblem(from: Endpoint(node: doubler.add.id, socket: "sum"), to: toOutput, registry: registry) == nil)
        #expect(withBox.connectionProblem(from: Endpoint(node: box.id, socket: "solid"), to: toOutput, registry: registry)
            == .typeMismatch(from: .solid, to: .number))
    }
}
```

**Create** `Tests/CreatorEditorTests/GroupSocketDisplayTests.swift`:

```swift
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// A group node is drawn, labelled and inspected with its definition's sockets (groups spec §4; the look is C2's).
@MainActor
struct GroupSocketDisplayTests {
    let definition = GroupDefinition.make(
        name: "Rib", inputs: [SocketSpec("height", .number, defaultValue: .number(10), unit: .millimetres)],
        outputs: [SocketSpec("solid", .solid)], registry: editorTestRegistry)
    var registry: NodeRegistry { editorTestRegistry.withGroups([definition.id: definition]) }

    func rib() -> (Node, Graph) {
        let node = registry.makeGroupNode(GroupNodes.groupTypeID, for: definition.id)
        var graph = Graph()
        graph.nodes[node.id] = node
        return (node, graph)
    }

    @Test func aGroupNodeDrawsItsDefinitionsSockets() {
        let (node, graph) = rib()
        let shape = NodeShape(node, in: graph, registry: registry)
        #expect(shape.title == "Rib")
        #expect(shape.inputs.map(\.name) == ["height"])
        #expect(shape.outputs.map(\.name) == ["solid"])
        #expect(shape.outputs.first?.type == .solid)
        let rows = NodeRowModel.rows(for: node, shape: shape, graph: graph, registry: registry)
        #expect(rows.first { $0.id == "in.height" }?.value == ValueText.format(10, unit: .millimetres))
    }

    @Test func theInspectorEditsAGroupNodesInputs() throws {
        let (node, graph) = rib()
        let page = InspectorBuilder.page(graph: graph, selection: [node.id], registry: registry, results: [:])
        let row = try #require(page.sections.first?.rows.first)
        guard case .number(let field) = row else {
            Issue.record("expected a number row, got \(row)")
            return
        }
        #expect(field.socket == "height" && field.unit == .millimetres && field.value == .number(10))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests && swift test --skip-build --filter 'CreatorGraphTests.GroupWiringTests|CreatorGraphTests.ConnectionTests|GroupSocketDisplayTests|PerNodeSocketTests'`

Expected: the new tests build and fail (5 issues in each run): `Expectation failed: g.connectionProblem(from: from, to: to, registry: registry) == nil` (`.unknownSocket("value")`) and `shape.inputs.map(\.name) == ["height"]` (`[]`).

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorGraph/Graph+Connections.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorGraph/Graph+Connections.swift b/Sources/CreatorGraph/Graph+Connections.swift
index bc8bb6f..321b237 100644
--- a/Sources/CreatorGraph/Graph+Connections.swift
+++ b/Sources/CreatorGraph/Graph+Connections.swift
@@ -1,12 +1,16 @@
 extension Graph {
-    /// `nil` if `from` (an output) may be wired to `to` (an input), otherwise why not.
+    /// `nil` if `from` (an output) may be wired to `to` (an input), otherwise why not. Sockets are
+    /// `registry.outputs(for:)`/`inputs(for:)`, so a group node wires to its definition's sockets when the registry
+    /// carries the document's groups.
     public func connectionProblem(from: Endpoint, to: Endpoint, registry: NodeRegistry) -> ConnectionProblem? {
         guard let source = nodes[from.node], let target = nodes[to.node],
-              let sourceDefinition = registry[source.typeID], let targetDefinition = registry[target.typeID] else {
+              registry[source.typeID] != nil, registry[target.typeID] != nil else {
             return .unknownNode
         }
-        guard let output = sourceDefinition.outputs.first(where: { $0.name == from.socket }) else { return .unknownSocket(from.socket) }
-        guard let input = targetDefinition.inputs(for: target).first(where: { $0.name == to.socket }) else {
+        guard let output = registry.outputs(for: source).first(where: { $0.name == from.socket }) else {
+            return .unknownSocket(from.socket)
+        }
+        guard let input = registry.inputs(for: target).first(where: { $0.name == to.socket }) else {
             return .unknownSocket(to.socket)
         }
         guard from.node != to.node else { return .sameNode }
```

**Modify** `Sources/CreatorEditor/NodeShape.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorEditor/NodeShape.swift b/Sources/CreatorEditor/NodeShape.swift
index c47bf1f..6c57488 100644
--- a/Sources/CreatorEditor/NodeShape.swift
+++ b/Sources/CreatorEditor/NodeShape.swift
@@ -1,8 +1,9 @@
 import CreatorGraph
 import CreatorKernel
 
-/// What the canvas needs to draw and hit-test one node: its title, category and sockets. A registered node's inputs
-/// are `inputs(for: node)`, so per-node sockets (the Sketch node's exposed dimensions) are drawn and wired.
+/// What the canvas needs to draw and hit-test one node: its title, category and sockets. A registered node's sockets
+/// are `registry.inputs(for:)`/`outputs(for:)`, so per-node sockets (the Sketch node's exposed dimensions, a group
+/// node's definition sockets) are drawn and wired.
 /// A node whose type isn't registered is a "missing node" (spec §4.5): it keeps the sockets its
 /// wires name, untyped.
 public struct NodeShape: Equatable, Sendable {
@@ -29,8 +30,8 @@ public struct NodeShape: Equatable, Sendable {
     public init(_ node: Node, in graph: Graph, registry: NodeRegistry) {
         if let definition = registry[node.typeID] {
             self.init(title: node.name, category: definition.category,
-                      inputs: definition.inputs(for: node).map { Socket(name: $0.name, type: $0.type) },
-                      outputs: definition.outputs.map { Socket(name: $0.name, type: $0.type) })
+                      inputs: registry.inputs(for: node).map { Socket(name: $0.name, type: $0.type) },
+                      outputs: registry.outputs(for: node).map { Socket(name: $0.name, type: $0.type) })
         } else {
             let inputs = Set(graph.links.filter { $0.to.node == node.id }.map(\.to.socket)).sorted()
             let outputs = Set(graph.links.filter { $0.from.node == node.id }.map(\.from.socket)).sorted()
```

**Modify** `Sources/CreatorEditor/NodeRowModel.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorEditor/NodeRowModel.swift b/Sources/CreatorEditor/NodeRowModel.swift
index 1793e25..254432c 100644
--- a/Sources/CreatorEditor/NodeRowModel.swift
+++ b/Sources/CreatorEditor/NodeRowModel.swift
@@ -11,9 +11,9 @@ public struct NodeRowModel: Equatable, Sendable, Identifiable {
     public var id: String { (isInput ? "in." : "out.") + socket.rawValue }
 
     /// Rows for `node`: inputs first, then outputs, matching `NodeLayout`'s row order. Each input's unit and default
-    /// come from `inputs(for: node)`, the same list `NodeShape` draws.
+    /// come from `registry.inputs(for:)`, the same list `NodeShape` draws.
     public static func rows(for node: Node, shape: NodeShape, graph: Graph, registry: NodeRegistry) -> [NodeRowModel] {
-        let specs = registry[node.typeID]?.inputs(for: node) ?? []
+        let specs = registry.inputs(for: node)
         let inputs = shape.inputs.map { socket -> NodeRowModel in
             let wired = graph.incomingLink(to: Endpoint(node: node.id, socket: socket.name)) != nil
             let spec = specs.first { $0.name == socket.name }
```

**Modify** `Sources/CreatorEditor/InspectorBuilder.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorEditor/InspectorBuilder.swift b/Sources/CreatorEditor/InspectorBuilder.swift
index ec4141a..50caf4f 100644
--- a/Sources/CreatorEditor/InspectorBuilder.swift
+++ b/Sources/CreatorEditor/InspectorBuilder.swift
@@ -19,16 +19,17 @@ public enum InspectorBuilder {
             return InspectorPage(header: header, sections: [note], parameters: parameters)
         }
         let header = InspectorHeader(node: id, title: node.name, category: definition.category, state: results[id]?.state)
-        // `inputs(for:)`, not the static list: per-node sockets (exposed sketch dimensions) get their unit and default.
-        // A declared inspector can't name them, so they follow its sections as fallback rows.
-        let inputs = definition.inputs(for: node)
+        // `registry.inputs(for:)`, not the static list: per-node sockets (exposed sketch dimensions, a group node's
+        // definition sockets) get their unit and default. A declared inspector can't name them, so they follow its
+        // sections as fallback rows.
+        let inputs = registry.inputs(for: node)
         let fixed = Set(definition.inputs.map(\.name))
         let declared = definition.inspector.isEmpty
             ? fallbackSections(inputs)
             : definition.inspector + fallbackSections(inputs.filter { !fixed.contains($0.name) })
         let sections = declared.map { section in
             InspectorSectionRows(title: section.title, rows: section.controls.map {
-                row(for: $0, node: node, inputs: inputs, outputs: definition.outputs, graph: graph,
+                row(for: $0, node: node, inputs: inputs, outputs: registry.outputs(for: node), graph: graph,
                     results: results)
             })
         }
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning'` (expect no output: no error, no new warning), then `swift test --skip-build --filter 'CreatorGraphTests.GroupWiringTests|CreatorGraphTests.ConnectionTests|GroupSocketDisplayTests|PerNodeSocketTests'`

Expected: `Test run with 13 tests in 2 suites passed`; `Test run with 7 tests in 2 suites passed`.

- [ ] **Step 5: Verify the whole package**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-test.log`.

Expected: exit code 0; `grep -c 'recorded an issue' /tmp/groups-test.log` and `grep -c 'failed after' /tmp/groups-test.log` print 0; `grep -c 'Test run with' /tmp/groups-test.log` prints 11; the counts on those lines add up to **1409** (master + 19).

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorGraph/Graph+Connections.swift' 'Sources/CreatorEditor/NodeShape.swift' 'Sources/CreatorEditor/NodeRowModel.swift' 'Sources/CreatorEditor/InspectorBuilder.swift' 'Tests/CreatorGraphTests/Groups/GroupWiringTests.swift' 'Tests/CreatorEditorTests/GroupSocketDisplayTests.swift'
git commit -m "feat(graph,editor): wires, canvas rows and inspector read group sockets from the registry"
```

---

### Task 4: `GraphContent`: commands inside definitions and the group rules

Adds `GraphPath`, `GraphContent` (the top-level graph plus the definitions) and its `apply(_:registry:)`, the four group commands (`inDefinition`, `addDefinition`, `removeDefinition`, `setInterface`), `GraphCommand.at(_:)`, `GroupDependencies` (spec §4: `wouldRecurse`), `GroupNaming` and the refusals: a group containing itself, an Output node in a group, a stray, second or deleted Group Input/Output, a definition still in use, bad names, and, checked once the whole command has applied (so a batch can rename a socket and move its wires), a socket removed or retyped while a wire is still on it, on a group node or on Group Input or Group Output inside. `GraphContent.touchedTopLevelNodes` says which top-level group nodes an edit inside a definition reaches; `affectsResults(_:)` says whether an edit changes any result (a new interface only when its sockets change) and `affectsMessages(_:)` whether it changes only a group's message (a renamed definition or inner node, which the trail "Rib › Fillet: …" names). `GroupSocketSide` lives here because the check names a side.

**Files:**
- Create: `Sources/CreatorGraph/Groups/GraphPath.swift`
- Create: `Sources/CreatorGraph/Groups/GraphContent.swift`
- Create: `Sources/CreatorGraph/Groups/GroupInstance.swift`
- Create: `Sources/CreatorGraph/Groups/GroupDependencies.swift`
- Create: `Sources/CreatorGraph/Groups/GroupRefusal.swift`
- Create: `Sources/CreatorGraph/Groups/GroupNaming.swift`
- Create: `Sources/CreatorGraph/Groups/GroupSocketSide.swift`
- Modify: `Sources/CreatorGraph/GraphCommand.swift`
- Modify: `Sources/CreatorGraph/Graph+Commands.swift`
- Create: `Sources/CreatorGraph/Groups/GraphCommand+Path.swift`
- Create: `Sources/CreatorGraph/Groups/GraphCommand+GroupEdits.swift`
- Create: `Sources/CreatorGraph/Groups/GraphContent+Apply.swift`
- Create: `Sources/CreatorGraph/Groups/GraphContent+Staleness.swift`
- Test: `Tests/CreatorGraphTests/Groups/GraphContentTests.swift`

**Interfaces:**
- Consumes: Task 1: the model and registry. Task 2: nothing.
- Produces:
  - `public enum GraphPath: Hashable, Sendable { case root, definition(GroupID) }`.
  - `public struct GraphContent: Sendable, Equatable { var graph: Graph; var definitions: [GroupID: GroupDefinition]; func graph(at: GraphPath) -> Graph? }`; `mutating func apply(_: GraphCommand, registry: NodeRegistry) throws(GraphError) -> GraphCommand` (inverse); `func touchedTopLevelNodes(_: GraphCommand) -> Set<NodeID>`.
  - `GraphCommand` cases `.inDefinition(GroupID, GraphCommand)`, `.addDefinition(GroupDefinition)`, `.removeDefinition(GroupID)`, `.setInterface(GroupID, GroupInterface)`; `func at(_ path: GraphPath) -> GraphCommand`. `Graph.apply` refuses the four.
  - `public enum GroupDependencies { direct(_: Graph) -> Set<GroupID>; transitive(_:in:) -> Set<GroupID>; wouldRecurse(placing:in:definitions:) -> Bool; instances(of:in:) -> [GroupInstance]; dependents(of:in:) -> Set<NodeID> }`; `public struct GroupInstance { path: GraphPath; node: Node }`.
  - `public enum GroupNaming { uniqueDefinitionName(_:among:) -> String; uniqueSocketName(_:among:) -> SocketName; isReserved(_:) -> Bool }` ("Group 2"; "value2").
  - `enum GroupRefusal` (internal): the messages, e.g. `outputInside` = "An Output node can't go in a group.".
  - `GraphContent.affectsResults(_ command: GraphCommand) -> Bool`, `affectsMessages(_ command: GraphCommand) -> Bool` (judged before the command applies).
  - `public enum GroupSocketSide: Sendable, Equatable { case input, output }`.
  - Internal: `GraphCommand.interfaceEdits: Set<GroupID>`, `renamesNodes: Bool`.

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorGraphTests/Groups/GraphContentTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Group commands on the whole document (groups spec §4, §5): every one undoable, and the group rules refused with a
/// plain message.
struct GraphContentTests {
    let doubler = Doubler()

    func content(_ nodes: [Node], _ definitions: [GroupDefinition]) -> GraphContent {
        GraphContent(graph: graph(nodes), definitions: table(definitions))
    }

    /// "Outer": a definition whose inside places one Doubler.
    func outer() -> GroupDefinition {
        var outer = GroupDefinition.make(name: "Outer", registry: testRegistry)
        let inner = instance(of: doubler.definition)
        outer.graph.nodes[inner.id] = inner
        return outer
    }

    /// Applies `command`, then its inverse: the content changed, then is back where it started.
    func expectRoundTrip(_ command: GraphCommand, on start: GraphContent,
                         sourceLocation: SourceLocation = #_sourceLocation) throws {
        var content = start
        let inverse = try content.apply(command, registry: testRegistry)
        #expect(content != start, sourceLocation: sourceLocation)
        try content.apply(inverse, registry: testRegistry)
        #expect(content == start, sourceLocation: sourceLocation)
    }

    func expectRefused(_ command: GraphCommand, on start: GraphContent, _ message: String,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        var content = start
        #expect(throws: GraphError.invalidValue(message), sourceLocation: sourceLocation) {
            try content.apply(command, registry: testRegistry)
        }
        #expect(content == start, sourceLocation: sourceLocation)
    }

    @Test func everyGroupCommandIsReversible() throws {
        let start = content([instance(of: doubler.definition)], [doubler.definition])
        let other = Doubler(name: "Other").definition
        var renamed = doubler.definition.interface
        renamed.name = "Twice"
        try expectRoundTrip(.inDefinition(doubler.id, .addNode(makeNode(ConstantNode.self))), on: start)
        try expectRoundTrip(.inDefinition(doubler.id, .move(doubler.add.id, to: Vector2(5, 5))), on: start)
        try expectRoundTrip(.addDefinition(other), on: start)
        try expectRoundTrip(.setInterface(doubler.id, renamed), on: start)
        try expectRoundTrip(.batch([.addDefinition(other), .addNode(instance(of: other))]), on: start)
        try expectRoundTrip(.removeDefinition(other.id), on: content([], [doubler.definition, other]))
    }

    @Test func anEditInsideADefinitionChangesOnlyItsGraph() throws {
        let top = makeNode(ConstantNode.self)
        var content = content([top], [doubler.definition])
        try content.apply(.inDefinition(doubler.id, .setInput(doubler.add.id, "b", .number(3))), registry: testRegistry)
        #expect(content.definitions[doubler.id]?.graph.nodes[doubler.add.id]?.inputValues["b"] == .number(3))
        #expect(content.graph == graph([top]))
        #expect(content.graph(at: .definition(doubler.id)) == content.definitions[doubler.id]?.graph)
        #expect(content.graph(at: .definition(GroupID())) == nil)
    }

    @Test func aGraphCommandIsAddressedToAPath() {
        let command = GraphCommand.move(doubler.add.id, to: Vector2(1, 2))
        #expect(command.at(.root) == command)
        #expect(command.at(.definition(doubler.id)) == .inDefinition(doubler.id, command))
    }

    @Test func aGroupCantContainItself() {
        let outer = outer()
        let start = content([], [doubler.definition, outer])
        let message = "A group can't contain itself."
        expectRefused(.inDefinition(doubler.id, .addNode(instance(of: doubler.definition))), on: start, message)
        expectRefused(.inDefinition(doubler.id, .addNode(instance(of: outer))), on: start, message)
        let placed = outer.graph.nodes.values.first { $0.typeID == GroupNodes.groupTypeID }
        expectRefused(.inDefinition(outer.id, .setInput(placed?.id ?? NodeID(), NodeSetting.group, .group(outer.id))),
                      on: start, message)
        var selfish = GroupDefinition.make(name: "Selfish", registry: testRegistry)
        let inside = testRegistry.withGroups(table([selfish])).makeGroupNode(GroupNodes.groupTypeID, for: selfish.id)
        selfish.graph.nodes[inside.id] = inside
        expectRefused(.addDefinition(selfish), on: start, message)
    }

    @Test func anOutputNodeCantGoInAGroup() throws {
        let start = content([], [doubler.definition])
        let message = "An Output node can't go in a group."
        expectRefused(.inDefinition(doubler.id, .addNode(makeNode(SinkNode.self))), on: start, message)
        expectRefused(.inDefinition(doubler.id, .setOutput(doubler.add.id, true)), on: start, message)
        var withSink = Doubler(name: "With sink").definition
        let sink = makeNode(SinkNode.self)
        withSink.graph.nodes[sink.id] = sink
        expectRefused(.addDefinition(withSink), on: start, message)
        try expectRoundTrip(.addNode(makeNode(SinkNode.self)), on: start)
    }

    @Test func groupInputAndOutputStayInTheirGroup() {
        let start = content([], [doubler.definition])
        expectRefused(.inDefinition(doubler.id, .removeNode(doubler.input.id)), on: start,
                      "A group's Group Input and Group Output can't be deleted.")
        expectRefused(.addNode(testRegistry.makeGroupNode(GroupNodes.inputTypeID, for: doubler.id)), on: start,
                      "Group Input and Group Output only go inside a group.")
        expectRefused(.inDefinition(doubler.id, .addNode(testRegistry.makeGroupNode(GroupNodes.outputTypeID, for: doubler.id))),
                      on: start, "A group has exactly one Group Input and one Group Output.")
        expectRefused(.inDefinition(doubler.id, .setInput(doubler.output.id, NodeSetting.group, .group(GroupID()))),
                      on: start, "Group Input and Group Output belong to their group.")
        expectRefused(.addDefinition(GroupDefinition(name: "Bare")), on: start,
                      "A group has exactly one Group Input and one Group Output.")
    }

    @Test func aDefinitionInUseCantBeRemoved() {
        let start = content([], [doubler.definition, outer()])
        expectRefused(.removeDefinition(doubler.id), on: start, "“Doubler” is still in use. Delete its group nodes first.")
        expectRefused(.addNode(instance(of: Doubler(name: "Elsewhere").definition)), on: start, "That group no longer exists.")
    }

    @Test func namesAndSocketsAreChecked() {
        let start = content([], [doubler.definition])
        expectRefused(.addDefinition(Doubler().definition), on: start, "A group named “Doubler” already exists.")
        var interface = doubler.definition.interface
        interface.name = "  "
        expectRefused(.setInterface(doubler.id, interface), on: start, "A group needs a name.")
        interface = doubler.definition.interface
        interface.inputs.append(SocketSpec("value", .integer))
        expectRefused(.setInterface(doubler.id, interface), on: start, "Two sockets can't both be named “value”.")
        interface = doubler.definition.interface
        interface.outputs.append(SocketSpec(NodeSetting.group, .number))
        expectRefused(.setInterface(doubler.id, interface), on: start, "“groupID” is reserved. Choose another name.")
        interface = doubler.definition.interface
        interface.outputs.append(SocketSpec("value", .number))  // An input's name is free on the output side.
        #expect(throws: Never.self) {
            var content = start
            try content.apply(.setInterface(doubler.id, interface), registry: testRegistry)
        }
    }

    @Test func aRefusedBatchChangesNothing() {
        let start = content([instance(of: doubler.definition)], [doubler.definition])
        expectRefused(.batch([.inDefinition(doubler.id, .addNode(makeNode(ConstantNode.self))), .removeDefinition(doubler.id)]),
                      on: start, "“Doubler” is still in use. Delete its group nodes first.")
        expectRefused(.inDefinition(doubler.id, .batch([.removeDefinition(doubler.id)])), on: start,
                      "A group edit can't go inside another edit.")
    }

    @Test func anEditInsideADefinitionTouchesEveryGroupNodeThatReachesIt() {
        let outer = outer()
        let direct = instance(of: doubler.definition), nested = instance(of: outer), plain = makeNode(ConstantNode.self)
        let content = content([direct, nested, plain], [doubler.definition, outer])
        #expect(content.touchedTopLevelNodes(.inDefinition(doubler.id, .move(doubler.add.id, to: .zero))) == [direct.id, nested.id])
        #expect(content.touchedTopLevelNodes(.setInterface(outer.id, outer.interface)) == [nested.id])
        #expect(content.touchedTopLevelNodes(.addDefinition(Doubler(name: "New").definition)).isEmpty)
        #expect(content.touchedTopLevelNodes(.batch([.setInput(plain.id, "value", .number(1))])) == [plain.id])
    }

    @Test func instancesAreListedTopLevelFirst() {
        let outer = outer()
        let direct = instance(of: doubler.definition)
        let instances = GroupDependencies.instances(of: doubler.id, in: content([direct], [doubler.definition, outer]))
        #expect(instances.map(\.path) == [.root, .definition(outer.id)])
        #expect(instances.first?.node == direct)
        #expect(GroupDependencies.transitive(outer.id, in: table([doubler.definition, outer])) == [doubler.id])
    }

    @Test func oneGraphRefusesGroupCommands() {
        var g = Graph()
        #expect(throws: GraphError.self) { try g.apply(.removeDefinition(GroupID()), registry: testRegistry) }
        #expect(GraphCommand.inDefinition(doubler.id, .move(doubler.add.id, to: .zero)).affectsResults == false)
        #expect(GraphCommand.inDefinition(doubler.id, .setInput(doubler.add.id, "b", nil)).affectsResults)
        #expect(GraphCommand.addDefinition(doubler.definition).affectsResults == false)
    }

    @Test func aWiredSocketCantBeRemovedOrRetypedByANewInterface() throws {
        let constant = makeNode(ConstantNode.self)
        let node = instance(of: doubler.definition)
        var start = GraphContent(graph: graph([constant, node], [link(constant, "value", node, "value")]),
                                 definitions: table([doubler.definition]))
        var interface = doubler.definition.interface
        interface.inputs = []
        #expect(throws: GraphError.invalidValue("“value” is wired on “Doubler”. Unwire it first.")) {
            try start.apply(.setInterface(doubler.id, interface), registry: testRegistry)
        }
        #expect(start.definitions == table([doubler.definition]), "a refused command changes nothing")

        // Inside: Group Output takes `result` from Add, so it can't become a vector.
        start.graph.links = []
        var retyped = doubler.definition.interface
        retyped.outputs = [SocketSpec("result", .vector)]
        #expect(throws: GraphError.invalidValue("“result” is wired on “Group Output”. Unwire it first.")) {
            try start.apply(.setInterface(doubler.id, retyped), registry: testRegistry)
        }
        // Renaming a socket in one batch that also moves its wires is fine; so is a new name or accent.
        var renamed = doubler.definition.interface
        renamed.name = "Twice"
        renamed.accent = .green
        try expectRoundTrip(.setInterface(doubler.id, renamed), on: start)
    }

    @Test func aNewNameOrAccentChangesNoResultButANameChangesMessages() {
        let start = content([instance(of: doubler.definition)], [doubler.definition])
        var named = doubler.definition.interface
        named.name = "Twice"
        var accented = doubler.definition.interface
        accented.accent = .green
        var socketed = doubler.definition.interface
        socketed.inputs[0].defaultValue = .number(2)
        #expect(!start.affectsResults(.setInterface(doubler.id, named)) && start.affectsMessages(.setInterface(doubler.id, named)))
        #expect(!start.affectsResults(.setInterface(doubler.id, accented)) && !start.affectsMessages(.setInterface(doubler.id, accented)))
        #expect(start.affectsResults(.batch([.setInterface(doubler.id, socketed)])))
        let rename = GraphCommand.inDefinition(doubler.id, .rename(doubler.add.id, "Plus"))
        #expect(!start.affectsResults(rename) && start.affectsMessages(rename))
        #expect(start.affectsResults(.inDefinition(doubler.id, .setInput(doubler.add.id, "b", nil))))
        #expect(!start.affectsMessages(.rename(doubler.add.id, "Plus")), "top-level names aren't in any message")
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning' | head`

Expected: error: cannot find type 'GraphContent' in scope.

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorGraph/Groups/GraphPath.swift`:

```swift
/// Which graph an edit addresses (groups spec §5): the top level, or the inside of a group definition.
public enum GraphPath: Hashable, Sendable {
    case root
    case definition(GroupID)
}
```

**Create** `Sources/CreatorGraph/Groups/GraphContent.swift`:

```swift
/// Everything graph commands edit (groups spec §4, §5): the top-level graph and the document's group definitions.
/// `apply(_:registry:)` (`GraphContent+Apply`) is how `DocumentModel` changes either.
public struct GraphContent: Sendable, Equatable {
    public var graph: Graph
    public var definitions: [GroupID: GroupDefinition]

    public init(graph: Graph = Graph(), definitions: [GroupID: GroupDefinition] = [:]) {
        self.graph = graph
        self.definitions = definitions
    }

    /// The graph at `path`, or `nil` for a definition that doesn't exist.
    public func graph(at path: GraphPath) -> Graph? {
        switch path {
        case .root: graph
        case .definition(let id): definitions[id]?.graph
        }
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupInstance.swift`:

```swift
/// One group node of a definition, and the graph it sits in.
public struct GroupInstance: Sendable, Equatable {
    public var path: GraphPath
    public var node: Node

    public init(path: GraphPath, node: Node) {
        self.path = path
        self.node = node
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupDependencies.swift`:

```swift
import CreatorKernel

/// Which definitions place which (groups spec §4): the rule that no definition contains itself, directly or through
/// other groups, and which group nodes an edit to a definition reaches.
public enum GroupDependencies {
    /// The definitions placed directly in `graph`.
    public static func direct(_ graph: Graph) -> Set<GroupID> {
        Set(graph.nodes.values.compactMap { node in
            node.typeID == GroupNodes.groupTypeID ? node.inputValues[NodeSetting.group]?.groupID : nil
        })
    }

    /// Every definition `id`'s inside places, directly or through other groups.
    public static func transitive(_ id: GroupID, in definitions: [GroupID: GroupDefinition]) -> Set<GroupID> {
        var seen: Set<GroupID> = []
        var pending = Array(definitions[id].map { direct($0.graph) } ?? [])
        while let next = pending.popLast() {
            guard seen.insert(next).inserted else { continue }
            if let definition = definitions[next] { pending += direct(definition.graph) }
        }
        return seen
    }

    /// Whether a group node of `target` in the graph at `path` would make a definition contain itself.
    public static func wouldRecurse(placing target: GroupID, in path: GraphPath,
                                    definitions: [GroupID: GroupDefinition]) -> Bool {
        guard case .definition(let host) = path else { return false }
        return target == host || transitive(target, in: definitions).contains(host)
    }

    /// Every group node of `id`: the top level's first, then each definition's in ID order; by node ID within a graph.
    public static func instances(of id: GroupID, in content: GraphContent) -> [GroupInstance] {
        let graphs = [(GraphPath.root, content.graph)]
            + content.definitions.values.sorted { $0.id < $1.id }.map { (GraphPath.definition($0.id), $0.graph) }
        return graphs.flatMap { path, graph in
            graph.nodes.values
                .filter { $0.typeID == GroupNodes.groupTypeID && $0.inputValues[NodeSetting.group]?.groupID == id }
                .sorted { $0.id < $1.id }
                .map { GroupInstance(path: path, node: $0) }
        }
    }

    /// The top-level nodes whose results depend on definition `id`: group nodes of it, or of a definition placing it.
    public static func dependents(of id: GroupID, in content: GraphContent) -> Set<NodeID> {
        Set(content.graph.nodes.values.filter { node in
            guard node.typeID == GroupNodes.groupTypeID, let target = node.inputValues[NodeSetting.group]?.groupID else {
                return false
            }
            return target == id || transitive(target, in: content.definitions).contains(id)
        }.map(\.id))
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupRefusal.swift`:

```swift
/// The plain sentences a refused group edit carries, as `GraphError.invalidValue` (groups spec §5).
enum GroupRefusal {
    static let missing = GraphError.invalidValue("That group no longer exists.")
    static let containsItself = GraphError.invalidValue("A group can't contain itself.")
    static let outputInside = GraphError.invalidValue("An Output node can't go in a group.")
    static let boundaryOutside = GraphError.invalidValue("Group Input and Group Output only go inside a group.")
    static let boundaryCount = GraphError.invalidValue("A group has exactly one Group Input and one Group Output.")
    static let boundaryDeleted = GraphError.invalidValue("A group's Group Input and Group Output can't be deleted.")
    static let boundaryMoved = GraphError.invalidValue("Group Input and Group Output belong to their group.")
    static let nested = GraphError.invalidValue("A group edit can't go inside another edit.")
    static let duplicateID = GraphError.invalidValue("That group already exists.")
    static let emptyName = GraphError.invalidValue("A group needs a name.")

    static func nameTaken(_ name: String) -> GraphError { .invalidValue("A group named “\(name)” already exists.") }
    static func inUse(_ name: String) -> GraphError { .invalidValue("“\(name)” is still in use. Delete its group nodes first.") }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupNaming.swift`:

```swift
import Foundation

/// Names for definitions and their sockets (groups spec §4, §5).
public enum GroupNaming {
    /// `base` if no definition has that name, else "base 2", "base 3", …
    public static func uniqueDefinitionName(_ base: String, among definitions: [GroupID: GroupDefinition]) -> String {
        let names = Set(definitions.values.map(\.name))
        guard names.contains(base) else { return base }
        var number = 2
        while names.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    /// `base` if no socket in `existing` has it and it isn't a setting's name, else "base2", "base3", …
    public static func uniqueSocketName(_ base: SocketName, among existing: [SocketName]) -> SocketName {
        let taken = Set(existing)
        guard taken.contains(base) || isReserved(base) else { return base }
        var number = 2
        while taken.contains(SocketName("\(base.rawValue)\(number)")) { number += 1 }
        return SocketName("\(base.rawValue)\(number)")
    }

    /// Socket names that can't be used: a group node keeps its settings (`NodeSetting`) beside its inputs' values.
    public static func isReserved(_ name: SocketName) -> Bool {
        NodeSetting.all.contains(name) || name.rawValue.hasPrefix(NodeSetting.projectionPrefix)
    }

    /// Why `sockets` can't be one side of a group, or `nil` if they can.
    static func problem(with sockets: [SocketSpec]) -> String? {
        var seen: Set<SocketName> = []
        for socket in sockets {
            if socket.name.rawValue.trimmingCharacters(in: .whitespaces).isEmpty { return "A socket needs a name." }
            if isReserved(socket.name) { return "“\(socket.name)” is reserved. Choose another name." }
            if !seen.insert(socket.name).inserted { return "Two sockets can't both be named “\(socket.name)”." }
        }
        return nil
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupSocketSide.swift`:

```swift
/// Which side of a group a socket is on: an input of the group node (an output of Group Input), or an output of the
/// group node (an input of Group Output).
public enum GroupSocketSide: Sendable, Equatable {
    case input, output
}
```

**Modify** `Sources/CreatorGraph/GraphCommand.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorGraph/GraphCommand.swift b/Sources/CreatorGraph/GraphCommand.swift
index f4e17db..172ef1f 100644
--- a/Sources/CreatorGraph/GraphCommand.swift
+++ b/Sources/CreatorGraph/GraphCommand.swift
@@ -23,9 +23,19 @@ public indirect enum GraphCommand: Sendable, Equatable {
     case removeParameter(ParameterID)
     case setParameter(ParameterID, ConstantValue)
     case batch([GraphCommand])
+    /// A graph command applied inside definition `GroupID` (groups spec §5). Group commands run only through
+    /// `GraphContent.apply`; `Graph.apply` refuses them.
+    case inDefinition(GroupID, GraphCommand)
+    /// Adds a group definition (the inverse of `removeDefinition`).
+    case addDefinition(GroupDefinition)
+    /// Removes a definition that no group node uses.
+    case removeDefinition(GroupID)
+    /// Replaces a definition's name, accent and sockets; wires and values on its group nodes are separate commands.
+    case setInterface(GroupID, GroupInterface)
 
-    /// Nodes whose own inputs or existence change. Callers that mark results stale must take
-    /// `downstreamClosure` on the graph *before* applying the command, so dependents of removed
+    /// Nodes whose own inputs or existence change, on the graph the command addresses (group commands touch none
+    /// here; `GraphContent.touchedTopLevelNodes` adds the group nodes they reach). Callers that mark results stale
+    /// must take `downstreamClosure` on the graph *before* applying the command, so dependents of removed
     /// nodes and links are included.
     public var touchedNodes: Set<NodeID> {
         switch self {
@@ -35,6 +45,7 @@ public indirect enum GraphCommand: Sendable, Equatable {
         case .connect(let link), .disconnect(let link): [link.to.node]
         case .restoreLinks(let links): Set(links.map(\.to.node))
         case .move, .rename, .addParameter, .removeParameter, .setParameter: []
+        case .inDefinition, .addDefinition, .removeDefinition, .setInterface: []
         case .batch(let commands): commands.reduce(into: []) { $0.formUnion($1.touchedNodes) }
         }
     }
@@ -43,8 +54,9 @@ public indirect enum GraphCommand: Sendable, Equatable {
     /// need not re-evaluate.
     public var affectsResults: Bool {
         switch self {
-        case .move, .rename: false
+        case .move, .rename, .addDefinition, .removeDefinition: false
         case .batch(let commands): commands.contains { $0.affectsResults }
+        case .inDefinition(_, let command): command.affectsResults
         default: true
         }
     }
```

**Modify** `Sources/CreatorGraph/Graph+Commands.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorGraph/Graph+Commands.swift b/Sources/CreatorGraph/Graph+Commands.swift
index 581e4d8..1b00b66 100644
--- a/Sources/CreatorGraph/Graph+Commands.swift
+++ b/Sources/CreatorGraph/Graph+Commands.swift
@@ -121,6 +121,9 @@ extension Graph {
                 throw error
             }
             return .batch(Array(inverses.reversed()))
+
+        case .inDefinition, .addDefinition, .removeDefinition, .setInterface:
+            throw .invalidValue("A group edit applies to the whole document, not to one graph.")
         }
     }
 
```

**Create** `Sources/CreatorGraph/Groups/GraphCommand+Path.swift`:

```swift
extension GraphCommand {
    /// This command addressed to the graph at `path` (groups spec §5): itself on the top level, `.inDefinition`
    /// inside a group.
    public func at(_ path: GraphPath) -> GraphCommand {
        switch path {
        case .root: self
        case .definition(let id): .inDefinition(id, self)
        }
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GraphCommand+GroupEdits.swift`:

```swift
extension GraphCommand {
    /// The definitions this command gives a new interface (`.setInterface`), at any depth of its batches.
    var interfaceEdits: Set<GroupID> {
        switch self {
        case .setInterface(let id, _): [id]
        case .batch(let commands): commands.reduce(into: []) { $0.formUnion($1.interfaceEdits) }
        default: []
        }
    }

    /// Whether this command renames a node, at any depth of its batches.
    var renamesNodes: Bool {
        switch self {
        case .rename: true
        case .batch(let commands): commands.contains { $0.renamesNodes }
        default: false
        }
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GraphContent+Apply.swift`:

```swift
import CreatorKernel
import Foundation

extension GraphContent {
    /// Applies `command` and returns the command that undoes it; on error nothing changes. Graph commands edit the
    /// top level, `.inDefinition` a definition's inside. Refused, with a plain message (groups spec §4, §5): a group
    /// containing itself, directly or through other groups; an Output node in a group; Group Input or Group Output
    /// outside a group, a second one, or deleting one; removing a definition in use; a bad name or socket list; and,
    /// once the whole command has applied, a socket removed from a definition or given another type while a wire is
    /// still on it, on a group node or inside on Group Input or Group Output.
    @discardableResult
    public mutating func apply(_ command: GraphCommand, registry: NodeRegistry) throws(GraphError) -> GraphCommand {
        let before = self
        let inverse = try applyCommand(command, registry: registry)
        do {
            try checkWiredSockets(changedBy: command, before: before)
        } catch {
            self = before
            throw error
        }
        return inverse
    }

    /// `apply` without the check across the whole command, so a batch can rename a socket and move its wires.
    private mutating func applyCommand(_ command: GraphCommand, registry: NodeRegistry) throws(GraphError) -> GraphCommand {
        switch command {
        case .batch(let commands):
            let snapshot = self
            var inverses: [GraphCommand] = []
            do {
                for command in commands {
                    inverses.append(try applyCommand(command, registry: registry))
                }
            } catch {
                self = snapshot
                throw error
            }
            return .batch(Array(inverses.reversed()))
        case .inDefinition, .addDefinition, .removeDefinition, .setInterface:
            return try applyGroupEdit(command, registry: registry)
        default:
            try check(command, in: .root, registry: registry)
            return try graph.apply(command, registry: registry.withGroups(definitions))
        }
    }

    /// The four group commands; `apply` routes them here.
    private mutating func applyGroupEdit(_ command: GraphCommand, registry: NodeRegistry) throws(GraphError) -> GraphCommand {
        switch command {
        case .inDefinition(let id, let inner):
            guard var definition = definitions[id] else { throw GroupRefusal.missing }
            try check(inner, in: .definition(id), registry: registry)
            let inverse = try definition.graph.apply(inner, registry: registry.withGroups(definitions))
            definitions[id] = definition
            return .inDefinition(id, inverse)
        case .addDefinition(let definition):
            try checkNew(definition, registry: registry)
            definitions[definition.id] = definition
            return .removeDefinition(definition.id)
        case .removeDefinition(let id):
            guard let definition = definitions[id] else { throw GroupRefusal.missing }
            guard GroupDependencies.instances(of: id, in: self).isEmpty else { throw GroupRefusal.inUse(definition.name) }
            definitions[id] = nil
            return .addDefinition(definition)
        case .setInterface(let id, let interface):
            guard var definition = definitions[id] else { throw GroupRefusal.missing }
            try checkInterface(interface, of: id)
            let old = definition.interface
            definition.interface = interface
            definitions[id] = definition
            return .setInterface(id, old)
        default:
            throw GroupRefusal.nested  // `apply` routes only the four group commands here.
        }
    }

    // MARK: - Rules

    /// Refuses a graph command that would break a group rule in the graph at `path`.
    private func check(_ command: GraphCommand, in path: GraphPath, registry: NodeRegistry) throws(GraphError) {
        switch command {
        case .batch(let commands):
            for command in commands { try check(command, in: path, registry: registry) }
        case .inDefinition, .addDefinition, .removeDefinition, .setInterface:
            throw GroupRefusal.nested
        case .addNode(let node), .restoreNode(let node, _):
            try checkPlacing(node, in: path, registry: registry)
        case .removeNode(let id):
            if let node = graph(at: path)?.nodes[id], GroupNodes.isBoundary(node) { throw GroupRefusal.boundaryDeleted }
        case .setOutput(_, true) where path != .root:
            throw GroupRefusal.outputInside
        case .setInput(let id, NodeSetting.group, let value):
            try checkRetargeting(id, to: value, in: path, registry: registry)
        default:
            break
        }
    }

    /// Refuses pointing a group node at a definition that's missing or would contain itself, and moving a Group
    /// Input or Output to another definition.
    private func checkRetargeting(_ id: NodeID, to value: ConstantValue?, in path: GraphPath,
                                  registry: NodeRegistry) throws(GraphError) {
        guard var node = graph(at: path)?.nodes[id] else { return }
        if GroupNodes.isBoundary(node) { throw GroupRefusal.boundaryMoved }
        node.inputValues[NodeSetting.group] = value
        if node.typeID == GroupNodes.groupTypeID { try checkPlacing(node, in: path, registry: registry) }
    }

    /// Refuses putting `node` in the graph at `path` when it breaks a group rule.
    private func checkPlacing(_ node: Node, in path: GraphPath, registry: NodeRegistry) throws(GraphError) {
        if GroupNodes.isBoundary(node) { throw path == .root ? GroupRefusal.boundaryOutside : GroupRefusal.boundaryCount }
        if path != .root, node.isOutput || registry[node.typeID]?.category == .output { throw GroupRefusal.outputInside }
        guard node.typeID == GroupNodes.groupTypeID else { return }
        guard let target = node.inputValues[NodeSetting.group]?.groupID, definitions[target] != nil else {
            throw GroupRefusal.missing
        }
        if GroupDependencies.wouldRecurse(placing: target, in: path, definitions: definitions) {
            throw GroupRefusal.containsItself
        }
    }

    /// Refuses a new definition that breaks a group rule: its ID or name taken, bad sockets, not exactly one Group
    /// Input and one Group Output (of this definition), an Output node inside, or a group inside that contains it.
    private func checkNew(_ definition: GroupDefinition, registry: NodeRegistry) throws(GraphError) {
        guard definitions[definition.id] == nil else { throw GroupRefusal.duplicateID }
        try checkInterface(definition.interface, of: definition.id)
        let boundary = definition.graph.nodes.values.filter(GroupNodes.isBoundary)
        guard boundary.count(where: { $0.typeID == GroupNodes.inputTypeID }) == 1,
              boundary.count(where: { $0.typeID == GroupNodes.outputTypeID }) == 1,
              boundary.allSatisfy({ $0.inputValues[NodeSetting.group]?.groupID == definition.id }) else {
            throw GroupRefusal.boundaryCount
        }
        var withNew = definitions
        withNew[definition.id] = definition
        for node in definition.graph.nodes.values where !GroupNodes.isBoundary(node) {
            if node.isOutput || registry[node.typeID]?.category == .output { throw GroupRefusal.outputInside }
            guard node.typeID == GroupNodes.groupTypeID else { continue }
            guard let target = node.inputValues[NodeSetting.group]?.groupID, withNew[target] != nil else {
                throw GroupRefusal.missing
            }
            if GroupDependencies.wouldRecurse(placing: target, in: .definition(definition.id), definitions: withNew) {
                throw GroupRefusal.containsItself
            }
        }
    }

    /// Refuses the sockets `command` removed from a definition, or gave another type, that still have a wire: on any
    /// group node of it, or inside on Group Input (an input) or Group Output (an output). `before` is the content the
    /// command applied to.
    private func checkWiredSockets(changedBy command: GraphCommand, before: GraphContent) throws(GraphError) {
        for id in command.interfaceEdits {
            guard let old = before.definitions[id], let definition = definitions[id] else { continue }
            for side in [GroupSocketSide.input, .output] {
                let kept = side == .input ? definition.inputs : definition.outputs
                for socket in side == .input ? old.inputs : old.outputs
                where !kept.contains(where: { $0.name == socket.name && $0.type == socket.type }) {
                    if let node = nodeWiring(socket.name, side: side, of: definition) {
                        throw .invalidValue("“\(socket.name)” is wired on “\(node.name)”. Unwire it first.")
                    }
                }
            }
        }
    }

    /// The first node with a wire on socket `name` of definition `definition`: a group node of it, or Group Input or
    /// Group Output inside it.
    private func nodeWiring(_ name: SocketName, side: GroupSocketSide, of definition: GroupDefinition) -> Node? {
        for instance in GroupDependencies.instances(of: definition.id, in: self) {
            let socket = Endpoint(node: instance.node.id, socket: name)
            if graph(at: instance.path)?.links.contains(where: { side == .input ? $0.to == socket : $0.from == socket }) == true {
                return instance.node
            }
        }
        guard let boundary = side == .input ? definition.inputNode : definition.outputNode else { return nil }
        let socket = Endpoint(node: boundary.id, socket: name)
        return definition.graph.links.contains { side == .input ? $0.from == socket : $0.to == socket } ? boundary : nil
    }

    /// Refuses an empty or taken name, and a side whose socket names are empty, reserved or repeated.
    private func checkInterface(_ interface: GroupInterface, of id: GroupID) throws(GraphError) {
        guard !interface.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw GroupRefusal.emptyName }
        if definitions.values.contains(where: { $0.id != id && $0.name == interface.name }) {
            throw GroupRefusal.nameTaken(interface.name)
        }
        for sockets in [interface.inputs, interface.outputs] {
            if let problem = GroupNaming.problem(with: sockets) { throw .invalidValue(problem) }
        }
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GraphContent+Staleness.swift`:

```swift
import CreatorKernel

extension GraphContent {
    /// The top-level nodes whose own inputs or existence `command` changes: `GraphCommand.touchedNodes`, plus every
    /// top-level group node an edit inside a definition (or to its sockets) reaches. As with `touchedNodes`, take
    /// `graph.downstreamClosure` of it *before* applying the command.
    public func touchedTopLevelNodes(_ command: GraphCommand) -> Set<NodeID> {
        switch command {
        case .batch(let commands): commands.reduce(into: []) { $0.formUnion(touchedTopLevelNodes($1)) }
        case .inDefinition(let id, _), .setInterface(let id, _): GroupDependencies.dependents(of: id, in: self)
        case .addDefinition, .removeDefinition: []
        default: command.touchedNodes
        }
    }

    /// Whether `command` can change any node's result, judged against this content before it applies: as
    /// `GraphCommand.affectsResults`, except that a definition's new interface does only when its sockets change (a
    /// new name or accent changes no value).
    public func affectsResults(_ command: GraphCommand) -> Bool {
        switch command {
        case .batch(let commands): commands.contains { affectsResults($0) }
        case .setInterface(let id, let interface):
            definitions[id].map { $0.inputs != interface.inputs || $0.outputs != interface.outputs } ?? true
        default: command.affectsResults
        }
    }

    /// Whether `command` changes the text of a group node's message without changing any result: renaming a
    /// definition, or a node inside one, changes the trail inner messages carry ("Rib › Fillet: …", `GroupTrail`).
    public func affectsMessages(_ command: GraphCommand) -> Bool {
        switch command {
        case .batch(let commands): commands.contains { affectsMessages($0) }
        case .inDefinition(_, let inner): inner.renamesNodes
        case .setInterface(let id, let interface): definitions[id]?.name != interface.name
        default: false
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning'` (expect no output: no error, no new warning), then `swift test --skip-build --filter 'CreatorGraphTests.GraphContentTests|CreatorGraphTests.CommandTests'`

Expected: `Test run with 38 tests in 2 suites passed`.

- [ ] **Step 5: Verify the whole package**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-test.log`.

Expected: exit code 0; `grep -c 'recorded an issue' /tmp/groups-test.log` and `grep -c 'failed after' /tmp/groups-test.log` print 0; `grep -c 'Test run with' /tmp/groups-test.log` prints 11; the counts on those lines add up to **1423** (master + 33).

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorGraph/Groups/GraphPath.swift' 'Sources/CreatorGraph/Groups/GraphContent.swift' 'Sources/CreatorGraph/Groups/GroupInstance.swift' 'Sources/CreatorGraph/Groups/GroupDependencies.swift' 'Sources/CreatorGraph/Groups/GroupRefusal.swift' 'Sources/CreatorGraph/Groups/GroupNaming.swift' 'Sources/CreatorGraph/Groups/GroupSocketSide.swift' 'Sources/CreatorGraph/GraphCommand.swift' 'Sources/CreatorGraph/Graph+Commands.swift' 'Sources/CreatorGraph/Groups/GraphCommand+Path.swift' 'Sources/CreatorGraph/Groups/GraphCommand+GroupEdits.swift' 'Sources/CreatorGraph/Groups/GraphContent+Apply.swift' 'Sources/CreatorGraph/Groups/GraphContent+Staleness.swift' 'Tests/CreatorGraphTests/Groups/GraphContentTests.swift'
git commit -m "feat(graph): GraphContent applies commands inside definitions and enforces the group rules"
```

---

### Task 5: Evaluating group nodes under scoped node IDs

The `Evaluator` evaluates level by level (spec §5). A group node gathers its inputs as any node does, then runs its definition's graph demanding Group Output, with Group Input handing on the gathered values unchanged (no broadcasting at the group; nodes inside broadcast as usual) and Group Output's inputs becoming its outputs. Inner nodes evaluate under `NodeID.scoped(instance path + id)` (a version-5 UUID), so their cache entries and tags are per instance and stable across definition edits; the group node isn't cached, and its key joins its gathered key with Group Output's. Cancellation is checked before every node at every level. Inner failures and warnings reach the group node with their trail ("Rib › Fail: Boom"). A pick stored inside a definition names faces as if the definition were the top level (its own nodes by ID, nodes inside its group nodes by `NodeID.scoped` of the path from it, `GroupScopes.identity`); entering a group node, `EvaluationScope` maps those names to the identities this instance makes faces under (keeping the outer levels' names for anything else), and `naming(_:)` rewrites a node's picks before it gathers, so a picked fillet inside a definition works in every instance. `gather` and `run` move to `Evaluator+Running.swift` unchanged except for the registry's sockets and the scoped identity.

**Files:**
- Create: `Sources/CreatorGraph/Groups/NodeID+Scoped.swift`
- Create: `Sources/CreatorGraph/Groups/GroupScopes.swift`
- Create: `Sources/CreatorGraph/Groups/Graph+ScopedIDs.swift`
- Create: `Sources/CreatorGraph/Groups/EvaluationSetup.swift`
- Create: `Sources/CreatorGraph/Groups/EvaluationScope.swift`
- Create: `Sources/CreatorGraph/Groups/EvaluationLevel.swift`
- Create: `Sources/CreatorGraph/Groups/EvaluationTrace.swift`
- Modify: `Sources/CreatorGraph/EvaluationReport.swift`
- Create: `Sources/CreatorGraph/Groups/GroupTrail.swift`
- Modify: `Sources/CreatorGraph/Evaluator.swift`
- Create: `Sources/CreatorGraph/Evaluator+Running.swift`
- Create: `Sources/CreatorGraph/Groups/Evaluator+Groups.swift`
- Create: `Sources/CreatorGraph/Groups/ConstantValue+TagRenaming.swift`
- Create: `Sources/CreatorGraph/Groups/Node+TagRenaming.swift`
- Modify test: `Tests/CreatorGraphTests/Support/GroupFixtures.swift`
- Test: `Tests/CreatorGraphTests/Support/FacePickCountNode.swift`
- Test: `Tests/CreatorGraphTests/Groups/GroupEvaluationTests.swift`

**Interfaces:**
- Consumes: Task 1: `NodeRegistry.inputs(for:)`/`outputs(for:)`/`group(of:)`/`withGroups`, `GroupNodes`. Task 4: nothing (the evaluator takes the definitions directly).
- Produces:
  - `Evaluator.evaluate(_ graph: Graph, definitions: [GroupID: GroupDefinition] = [:], demand: Set<NodeID>) async throws -> EvaluationReport`.
  - `EvaluationReport.innerResults: [[NodeID]: NodeResult]`, `evaluatedInnerNodes: [[NodeID]]` (instance path, then the inner node's ID).
  - `public static func NodeID.scoped(_ path: [NodeID]) -> NodeID`.
  - Internal: `EvaluationScope` (`names`, `entering(_:group:graph:bound:)`, `naming(_:)`), `EvaluationSetup`, `EvaluationLevel`, `EvaluationTrace`, `GroupTrail`, `GroupScopes.inner(of:at:definitions:entered:)`, `paths(in:definitions:entered:) -> [[NodeID]]`, `identity(_ path: [NodeID]) -> NodeID`, `Graph.scopedNodeIDs(definitions:)`, `ConstantValue.renamingTags(_ names: [NodeID: NodeID]) -> ConstantValue`, `Node.renamingTags(_:) -> Node`.
  - Fixtures: `define(_ name:inputs:outputs:nodes:links:) -> GroupDefinition`; `FacePickCountNode` (counts the faces its `face` pick names), `pickRegistry`, `endCapPick(of:) -> ConstantValue`.

- [ ] **Step 1: Write the failing tests**

**Modify** `Tests/CreatorGraphTests/Support/GroupFixtures.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Tests/CreatorGraphTests/Support/GroupFixtures.swift b/Tests/CreatorGraphTests/Support/GroupFixtures.swift
index 4e7b1a7..499e07c 100644
--- a/Tests/CreatorGraphTests/Support/GroupFixtures.swift
+++ b/Tests/CreatorGraphTests/Support/GroupFixtures.swift
@@ -38,3 +38,15 @@ func instance(of definition: GroupDefinition, _ values: [SocketName: ConstantVal
 func table(_ definitions: [GroupDefinition]) -> [GroupID: GroupDefinition] {
     Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
 }
+
+/// A definition named `name` whose inside holds `nodes` and its boundary; `links` is given Group Input and Group
+/// Output and returns the inside's wires.
+func define(_ name: String, inputs: [SocketSpec] = [], outputs: [SocketSpec], nodes: [Node],
+            links: (_ input: Node, _ output: Node) -> [Link]) -> GroupDefinition {
+    let id = GroupID()
+    let input = testRegistry.makeGroupNode(GroupNodes.inputTypeID, for: id, at: GroupDefinition.defaultInputPosition)
+    let output = testRegistry.makeGroupNode(GroupNodes.outputTypeID, for: id, at: GroupDefinition.defaultOutputPosition)
+    var inside = graph([input, output] + nodes, links(input, output))
+    inside.sortLinks()
+    return GroupDefinition(id: id, name: name, inputs: inputs, outputs: outputs, graph: inside)
+}
```

**Create** `Tests/CreatorGraphTests/Support/FacePickCountNode.swift`:

```swift
// Test fixture file: a node that reads a face pick, and the registry the pick tests use.
import CreatorKernel
@testable import CreatorGraph

/// Counts the faces of its solid that its `face` setting (a `FacePick`) names, as Plane from Face resolves one.
enum FacePickCountNode: NodeDefinition {
    static let typeID = "test.facePickCount"
    static let displayName = "Face Pick Count"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("solid", .solid)]
    static let outputs = [SocketSpec("count", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard case .facePick(let pick)? = context.node.inputValues[NodeSetting.face] else {
            return NodeOutputs(["count": .number(0)])
        }
        return NodeOutputs(["count": .number(Double(try inputs.solid("solid").topology.faces(matching: pick).count))])
    }
}

/// The test nodes with the face pick counter; `testRegistry` stays as it is.
let pickRegistry = NodeRegistry([BoxNode.self, FacePickCountNode.self, ConstantNode.self, AddNode.self, SinkNode.self])

/// A face pick on the end cap of the box `node` makes, as a pick on the level `node` sits at names it.
func endCapPick(of node: NodeID) -> ConstantValue {
    .facePick(FacePick(tags: [TopoTag(node: node, item: 0, role: .endCap)]))
}
```

**Create** `Tests/CreatorGraphTests/Groups/GroupEvaluationTests.swift`:

```swift
import CreatorKernel
import Testing
@testable import CreatorGraph

/// A group node evaluates its definition's graph (groups spec §5).
struct GroupEvaluationTests {
    let doubler = Doubler()

    func evaluate(_ g: Graph, _ definitions: [GroupDefinition], demand: [Node],
                  evaluator: Evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())) async throws -> EvaluationReport {
        try await evaluator.evaluate(g, definitions: table(definitions), demand: Set(demand.map(\.id)))
    }

    /// "Quadrupler": two Doublers in a row.
    func quadrupler() -> (definition: GroupDefinition, first: Node, second: Node) {
        let first = instance(of: doubler.definition), second = instance(of: doubler.definition)
        let definition = define("Quadrupler", inputs: [SocketSpec("value", .number)], outputs: [SocketSpec("result", .number)],
                                nodes: [first, second]) { input, output in
            [link(input, "value", first, "value"), link(first, "result", second, "value"), link(second, "result", output, "result")]
        }
        return (definition, first, second)
    }

    @Test func aGroupNodeRunsItsDefinition() async throws {
        let constant = makeNode(ConstantNode.self, ["value": .number(3)])
        let wired = instance(of: doubler.definition), typed = instance(of: doubler.definition, ["value": .number(4)])
        let defaulted = instance(of: doubler.definition)
        let report = try await evaluate(graph([constant, wired, typed, defaulted], [link(constant, "value", wired, "value")]),
                                        [doubler.definition], demand: [wired, typed, defaulted])
        #expect(report.results[wired.id]?.outputs?["result"]?.numbers == [6])
        #expect(report.results[typed.id]?.outputs?["result"]?.numbers == [8])
        #expect(report.results[defaulted.id]?.outputs?["result"]?.numbers == [2], "the socket's default, 1")
        #expect(report.innerResults[[wired.id, doubler.add.id]]?.outputs?["sum"]?.numbers == [6])
    }

    @Test func listsPassThroughAndBroadcastInside() async throws {
        let list = makeNode(ListSourceNode.self, ["count": .integer(3)])
        let sum = makeNode(SumListNode.self)
        let summer = define("Summer", inputs: [SocketSpec("values", .number)], outputs: [SocketSpec("sum", .number)],
                            nodes: [sum]) { input, output in
            [link(input, "values", sum, "values"), link(sum, "sum", output, "sum")]
        }
        let summed = instance(of: summer), doubled = instance(of: doubler.definition)
        let report = try await evaluate(graph([list, summed, doubled], [
            link(list, "values", summed, "values"), link(list, "values", doubled, "value"),
        ]), [summer, doubler.definition], demand: [summed, doubled])
        #expect(report.results[summed.id]?.outputs?["sum"]?.numbers == [3], "the list reached Sum List whole")
        #expect(report.results[doubled.id]?.outputs?["result"]?.numbers == [0, 2, 4], "Add broadcast over it inside")
        #expect(report.results[doubled.id]?.outputs?["result"]?.isList == true)
    }

    @Test func groupsNest() async throws {
        let (quadrupler, first, second) = quadrupler()
        let node = instance(of: quadrupler, ["value": .number(5)])
        let report = try await evaluate(graph([node]), [doubler.definition, quadrupler], demand: [node])
        #expect(report.results[node.id]?.outputs?["result"]?.numbers == [20])
        #expect(report.innerResults[[node.id, first.id, doubler.add.id]]?.outputs?["sum"]?.numbers == [10])
        #expect(report.innerResults[[node.id, second.id, doubler.add.id]]?.outputs?["sum"]?.numbers == [20])
    }

    @Test func scopedIDsAreNameBasedAndDistinct() {
        let a = NodeID(), b = NodeID()
        #expect(NodeID.scoped([a, b]) == NodeID.scoped([a, b]))
        #expect(NodeID.scoped([a, b]) != NodeID.scoped([b, a]))
        #expect(NodeID.scoped([a]) != a)
        #expect(NodeID.scoped([a, b]) != NodeID.scoped([a]))
        #expect(NodeID.scoped([a, b]).rawValue.uuidString.dropFirst(14).first == "5", "a version-5 UUID")
    }

    @Test func eachInstanceTagsItsFacesWithItsOwnScopedID() async throws {
        let box = makeNode(BoxNode.self)
        let boxer = define("Boxer", outputs: [SocketSpec("solid", .solid)], nodes: [box]) { _, output in
            [link(box, "solid", output, "solid")]
        }
        let first = instance(of: boxer), second = instance(of: boxer)
        let report = try await evaluate(graph([first, second]), [boxer], demand: [first, second])
        for node in [first, second] {
            guard case .solid(let solid)? = report.results[node.id]?.outputs?["solid"]?.items.first else {
                Issue.record("expected a solid")
                return
            }
            let tags = solid.topology.faces.flatMap(\.tags)
            #expect(!tags.isEmpty)
            #expect(tags.allSatisfy { $0.node == NodeID.scoped([node.id, box.id]) })
        }
    }

    @Test func aPickInsideADefinitionNamesEachInstancesFaces() async throws {
        let box = pickRegistry.makeNode(BoxNode.typeID)
        var counter = pickRegistry.makeNode(FacePickCountNode.typeID)
        counter.inputValues[NodeSetting.face] = endCapPick(of: box.id)
        let counted = define("Counted", outputs: [SocketSpec("count", .number), SocketSpec("solid", .solid)],
                             nodes: [box, counter]) { _, output in
            [link(box, "solid", counter, "solid"), link(counter, "count", output, "count"), link(box, "solid", output, "solid")]
        }
        // Nested: a pick in "Outer" names the box inside its group node `inner` as Outer's own level reaches it.
        let inner = instance(of: counted)
        var outerCounter = pickRegistry.makeNode(FacePickCountNode.typeID)
        outerCounter.inputValues[NodeSetting.face] = endCapPick(of: NodeID.scoped([inner.id, box.id]))
        let outer = define("Outer", outputs: [SocketSpec("count", .number)], nodes: [inner, outerCounter]) { _, output in
            [link(inner, "solid", outerCounter, "solid"), link(outerCounter, "count", output, "count")]
        }

        let first = instance(of: counted), second = instance(of: counted), nested = instance(of: outer)
        let report = try await evaluate(graph([first, second, nested]), [counted, outer], demand: [first, second, nested],
                                        evaluator: Evaluator(registry: pickRegistry, kernel: FakeKernel()))
        #expect(report.results[first.id]?.outputs?["count"]?.numbers == [1], "the pick names this instance's end cap")
        #expect(report.results[second.id]?.outputs?["count"]?.numbers == [1], "and this one's")
        #expect(report.innerResults[[nested.id, inner.id, counter.id]]?.outputs?["count"]?.numbers == [1], "a nested one's")
        #expect(report.results[nested.id]?.outputs?["count"]?.numbers == [1], "a pick through a nested group")
    }

    @Test func renamingTagsReachesBlendSourceEdges() {
        let a = NodeID(), b = NodeID(), c = NodeID()
        let edge = EdgeKey([TopoTag(node: a, item: 0, role: .endCap)], [TopoTag(node: c, item: 0, role: .side(segment: 1))])
        let blend = TopoTag(node: c, item: 0, role: .blend(sourceEdge: edge))
        let pick = EdgePick(key: EdgeKey([blend], [TopoTag(node: a, item: 1, role: .startCap)]), matchCount: 2, ordinals: [1])
        let renamedEdge = EdgeKey([TopoTag(node: b, item: 0, role: .endCap)], [TopoTag(node: c, item: 0, role: .side(segment: 1))])
        let renamedBlend = TopoTag(node: c, item: 0, role: .blend(sourceEdge: renamedEdge))
        let renamedPick = EdgePick(key: EdgeKey([renamedBlend], [TopoTag(node: b, item: 1, role: .startCap)]), matchCount: 2,
                                   ordinals: [1])
        let picks = ConstantValue.edgePicks([pick]), renamed = ConstantValue.edgePicks([renamedPick])
        #expect(picks.renamingTags([a: b]) == renamed)
        #expect(endCapPick(of: a).renamingTags([a: b]) == endCapPick(of: b))
        #expect(ConstantValue.number(1).renamingTags([a: b]) == .number(1))
    }

    @Test func eachInstanceIsCachedOnItsOwnAndADefinitionEditRerunsThemAll() async throws {
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        let first = instance(of: doubler.definition, ["value": .number(2)])
        let second = instance(of: doubler.definition, ["value": .number(3)])
        let g = graph([first, second])
        let opening = try await evaluate(g, [doubler.definition], demand: [first, second], evaluator: evaluator)
        #expect(Set(opening.evaluatedInnerNodes) == [[first.id, doubler.add.id], [second.id, doubler.add.id]])
        #expect(await evaluator.cachedEntryCount == 2)
        let again = try await evaluate(g, [doubler.definition], demand: [first, second], evaluator: evaluator)
        #expect(again.evaluatedNodes.isEmpty && again.evaluatedInnerNodes.isEmpty)
        #expect(again.results[second.id]?.outputs?["result"]?.numbers == [6])

        // Inside, Add's `b` is now 10 instead of a second copy of the input.
        var edited = doubler.definition
        edited.graph.links.removeAll { $0.to == Endpoint(node: doubler.add.id, socket: "b") }
        edited.graph.nodes[doubler.add.id]?.inputValues["b"] = .number(10)
        let after = try await evaluate(g, [edited], demand: [first, second], evaluator: evaluator)
        #expect(Set(after.evaluatedNodes) == [first.id, second.id])
        #expect(after.results[first.id]?.outputs?["result"]?.numbers == [12])
        #expect(after.results[second.id]?.outputs?["result"]?.numbers == [13])
        // Each instance's Add has an entry from before the edit (kept, so undo hits the cache) and one from after.
        #expect(await evaluator.cachedEntryCount == 4)

        // A group node that's gone takes its inner entries out of the cache.
        _ = try await evaluate(graph([first]), [edited], demand: [first], evaluator: evaluator)
        #expect(await evaluator.cachedEntryCount == 2)
    }

    @Test func cancellationIsHonouredBetweenNodesInsideAGroup() async throws {
        let kernel = FakeKernel()
        let canceller = makeNode(CancelsTaskNode.self), box = makeNode(BoxNode.self)
        let definition = define("Cancels", outputs: [SocketSpec("solid", .solid)], nodes: [canceller, box]) { _, output in
            [link(canceller, "value", box, "width"), link(box, "solid", output, "solid")]
        }
        let node = instance(of: definition)
        let evaluator = Evaluator(registry: testRegistry, kernel: kernel)
        let task = Task { try await evaluator.evaluate(graph([node]), definitions: table([definition]), demand: [node.id]) }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await kernel.operationLog.isEmpty)
    }

    @Test func innerFailuresAndWarningsCarryTheirPath() async throws {
        let fail = makeNode(FailNode.self), warn = makeNode(WarnNode.self)
        let failing = define("Rib", outputs: [SocketSpec("value", .number)], nodes: [fail]) { _, output in
            [link(fail, "value", output, "value")]
        }
        let warning = define("Careful rib", outputs: [SocketSpec("value", .number)], nodes: [warn]) { _, output in
            [link(warn, "value", output, "value")]
        }
        let inner = instance(of: failing)
        let outer = define("Bracket", outputs: [SocketSpec("value", .number)], nodes: [inner]) { _, output in
            [link(inner, "value", output, "value")]
        }
        let failed = instance(of: failing), warned = instance(of: warning), nested = instance(of: outer)
        let report = try await evaluate(graph([failed, warned, nested]), [failing, warning, outer],
                                        demand: [failed, warned, nested])
        #expect(report.results[failed.id]?.state == .error("Rib › Fail: Boom"))
        #expect(report.results[nested.id]?.state == .error("Bracket › Rib › Fail: Boom"))
        #expect(report.results[warned.id]?.state == .warning("Careful rib › Warn: Careful"))
        #expect(report.results[warned.id]?.outputs?["value"]?.numbers == [0])
    }

    @Test func aWaitingInnerNodeLeavesTheGroupWaiting() async throws {
        let required = makeNode(RequiredNode.self)
        let definition = define("Needy", outputs: [SocketSpec("value", .number)], nodes: [required]) { _, output in
            [link(required, "value", output, "value")]
        }
        let node = instance(of: definition)
        let report = try await evaluate(graph([node]), [definition], demand: [node])
        #expect(report.results[node.id]?.state == .idle("Needy › Required: Connect or set “value”."))
    }

    @Test func handEditedFilesFailPlainly() async throws {
        let orphan = instance(of: Doubler(name: "Gone").definition)
        var loop = GroupDefinition.make(name: "Loop", outputs: [SocketSpec("value", .number)], registry: testRegistry)
        let inside = testRegistry.withGroups(table([loop])).makeGroupNode(GroupNodes.groupTypeID, for: loop.id)
        loop.graph.nodes[inside.id] = inside
        if let output = loop.outputNode { loop.graph.links = [link(inside, "value", output, "value")] }
        let looping = instance(of: loop)
        let strayInput = testRegistry.makeGroupNode(GroupNodes.inputTypeID, for: loop.id)
        let report = try await evaluate(graph([orphan, looping, strayInput]), [loop], demand: [orphan, looping, strayInput])
        #expect(report.results[orphan.id]?.state == .error("This group's definition is missing."))
        #expect(report.results[looping.id]?.state == .error("Loop › “Loop” contains itself, so it can't be evaluated."))
        #expect(report.results[strayInput.id]?.state == .error("Group Input works only inside a group."))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning' | head`

Expected: error: extra argument 'definitions' in call (and: type 'NodeID' has no member 'scoped').

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorGraph/Groups/NodeID+Scoped.swift`:

```swift
import CreatorKernel
import CryptoKit
import Foundation

extension NodeID {
    /// The identity a node inside a group evaluates under (groups spec §5): a name-based UUID (version 5, SHA-1)
    /// of `path`, the group nodes from the top level down followed by the inner node's own ID. Deterministic, so a
    /// tag made inside a group, and a pick that names it, stay the same as long as those IDs do: across evaluations,
    /// saves and edits to the definition. Two instances of a definition have different paths, so their tags differ.
    public static func scoped(_ path: [NodeID]) -> NodeID {
        var bytes = namespace
        for id in path {
            withUnsafeBytes(of: id.rawValue.uuid) { bytes += $0 }
        }
        var digest = Array(Insecure.SHA1.hash(data: bytes).prefix(16))
        digest[6] = (digest[6] & 0x0F) | 0x50  // Version 5: name-based, SHA-1.
        digest[8] = (digest[8] & 0x3F) | 0x80  // The RFC 4122 variant.
        return NodeID(rawValue: digest.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) })
    }

    /// The namespace of scoped IDs: MetalCreator's own, so they never equal a UUID named under another namespace.
    private static let namespace: [UInt8] = [
        0x6D, 0x63, 0x2E, 0x67, 0x72, 0x6F, 0x75, 0x70, 0x2E, 0x73, 0x63, 0x6F, 0x70, 0x65, 0x2E, 0x31,
    ]
}
```

**Create** `Sources/CreatorGraph/Groups/GroupScopes.swift`:

```swift
import CreatorKernel

/// The identities nodes evaluate under across a document's groups (groups spec §5, `NodeID.scoped`): the cache keeps
/// entries of these, picks name faces by them, and group commands rename picks when they change
/// (`GroupScopes+PickRenaming`).
enum GroupScopes {
    /// Every identity of the nodes inside group node `node`, at every depth, when `node` sits at instance path `path`
    /// (the group nodes above it). A definition met inside itself isn't entered again.
    static func inner(of node: Node, at path: [NodeID], definitions: [GroupID: GroupDefinition],
                      entered: [GroupID] = []) -> Set<NodeID> {
        guard node.typeID == GroupNodes.groupTypeID, let id = node.inputValues[NodeSetting.group]?.groupID,
              !entered.contains(id), let definition = definitions[id] else { return [] }
        let inside = path + [node.id]
        var ids: Set<NodeID> = []
        for innerNode in definition.graph.nodes.values {
            ids.insert(NodeID.scoped(inside + [innerNode.id]))
            ids.formUnion(inner(of: innerNode, at: inside, definitions: definitions, entered: entered + [id]))
        }
        return ids
    }

    /// Every path from `graph` to one of its nodes (`[node]`) or to a node inside its group nodes, at every depth
    /// (`[group node, …, inner node]`). A definition met inside itself isn't entered again.
    static func paths(in graph: Graph, definitions: [GroupID: GroupDefinition], entered: [GroupID] = []) -> [[NodeID]] {
        var found: [[NodeID]] = []
        for node in graph.nodes.values {
            found.append([node.id])
            guard node.typeID == GroupNodes.groupTypeID, let id = node.inputValues[NodeSetting.group]?.groupID,
                  !entered.contains(id), let definition = definitions[id] else { continue }
            found += paths(in: definition.graph, definitions: definitions, entered: entered + [id]).map { [node.id] + $0 }
        }
        return found
    }

    /// The identity of the node `path` reaches from a graph, as that graph's picks name it: its own ID for a node of
    /// the graph, else `NodeID.scoped(path)`. From the top level, this is the identity it evaluates under.
    static func identity(_ path: [NodeID]) -> NodeID {
        if path.count == 1, let only = path.first { return only }
        return NodeID.scoped(path)
    }
}
```

**Create** `Sources/CreatorGraph/Groups/Graph+ScopedIDs.swift`:

```swift
import CreatorKernel

extension Graph {
    /// Every identity this graph's nodes evaluate under, given `definitions`: its own node IDs, and the scoped ID of
    /// every node inside every group node, at every depth (`NodeID.scoped`). The evaluator keeps cache entries of
    /// these and drops the rest.
    func scopedNodeIDs(definitions: [GroupID: GroupDefinition]) -> Set<NodeID> {
        nodes.values.reduce(into: Set(nodes.keys)) { ids, node in
            ids.formUnion(GroupScopes.inner(of: node, at: [], definitions: definitions))
        }
    }
}
```

**Create** `Sources/CreatorGraph/Groups/EvaluationSetup.swift`:

```swift
/// What every level of one evaluation shares (groups spec §5): the registry carrying the document's definitions, so
/// group nodes have their sockets, and the document's parameters.
struct EvaluationSetup: Sendable {
    var registry: NodeRegistry
    var parameters: [ParameterID: ConstantValue]
}
```

**Create** `Sources/CreatorGraph/Groups/EvaluationScope.swift`:

```swift
import CreatorKernel

/// Where one level of an evaluation sits (groups spec §5): the top level, or the inside of a group node.
struct EvaluationScope: Sendable {
    /// What a level's Group Input hands on: the group node's gathered inputs, unchanged, and their cache key.
    struct Bound: Sendable {
        var values: [SocketName: Value]
        var key: CacheKey
    }

    /// What every level of one evaluation shares: the registry carrying the definitions, and the parameters.
    let setup: EvaluationSetup
    /// The group nodes from the top level down to this level, each by its ID in its own graph. Empty on the top level.
    var path: [NodeID] = []
    /// The definitions being evaluated around this level, so a definition that contains itself stops.
    var groups: [GroupID] = []
    /// What this level's Group Input produces; `nil` on the top level.
    var bound: Bound?
    /// How a pick stored at this level names faces, mapped to the identities they're made under here: a pick in a
    /// definition names faces as if that definition were the top level (`GroupScopes.identity`), so it holds for
    /// every instance; a name this level doesn't have is looked up in the levels around it. Empty on the top level,
    /// where picks already name faces by the identities they're made under.
    var names: [NodeID: NodeID] = [:]

    /// The identity a node of this level evaluates under: its own ID on the top level, else `NodeID.scoped`.
    func identity(of id: NodeID) -> NodeID {
        path.isEmpty ? id : NodeID.scoped(path + [id])
    }

    /// The scope inside group node `node` of definition `group`, whose graph is `graph`.
    func entering(_ node: NodeID, group: GroupID, graph: Graph, bound: Bound) -> EvaluationScope {
        let inside = path + [node], groups = groups + [group]
        var names = names
        for relative in GroupScopes.paths(in: graph, definitions: setup.registry.groups, entered: groups) {
            names[GroupScopes.identity(relative)] = NodeID.scoped(inside + relative)
        }
        return EvaluationScope(setup: setup, path: inside, groups: groups, bound: bound, names: names)
    }

    /// `node` with the picks it stores naming faces by the identities they're made under at this level.
    func naming(_ node: Node) -> Node {
        node.renamingTags(names)
    }
}
```

**Create** `Sources/CreatorGraph/Groups/EvaluationLevel.swift`:

```swift
import CreatorKernel

/// What one level of an evaluation produced, by each node's ID in that level's graph.
struct EvaluationLevel: Sendable {
    var order: [NodeID]
    var results: [NodeID: NodeResult] = [:]
    var keys: [NodeID: CacheKey] = [:]
    /// Nodes that ran (cache misses), in order; a group node counts when anything inside it ran.
    var evaluated: [NodeID] = []
}
```

**Create** `Sources/CreatorGraph/Groups/EvaluationTrace.swift`:

```swift
import CreatorKernel

/// What an evaluation saw inside group nodes, by instance path (the group nodes from the top level down, then the
/// inner node's ID): every inner result, and the inner nodes that ran.
struct EvaluationTrace: Sendable {
    var results: [[NodeID]: NodeResult] = [:]
    var evaluated: [[NodeID]] = []
}
```

**Replace the whole of** `Sources/CreatorGraph/EvaluationReport.swift` with:

```swift
import CreatorKernel

public struct EvaluationReport: Sendable {
    /// Top-level results.
    public var results: [NodeID: NodeResult]
    /// Top-level nodes that actually ran this time (cache misses), in order. A group node counts when any node
    /// inside it ran.
    public var evaluatedNodes: [NodeID]
    /// Results inside group nodes (groups spec §5), by instance path: the group nodes from the top level down, then
    /// the inner node's ID.
    public var innerResults: [[NodeID]: NodeResult] = [:]
    /// Inner nodes that actually ran this time, by instance path, in order.
    public var evaluatedInnerNodes: [[NodeID]] = []
}
```

**Create** `Sources/CreatorGraph/Groups/GroupTrail.swift`:

```swift
/// How an inner node's message reads on its group node (groups spec §5): "Rib › Fillet: …". A nested group's
/// message already starts with its own definition's name, so it gains only this one: "Rib › Hole pattern › Fillet: …".
enum GroupTrail {
    static func message(_ message: String, from inner: Node, in definition: GroupDefinition) -> String {
        inner.typeID == GroupNodes.groupTypeID
            ? "\(definition.name) › \(message)"
            : "\(definition.name) › \(inner.name): \(message)"
    }

    /// The first error inside, in evaluation order, as the group node's message.
    static func firstError(in level: EvaluationLevel, graph: Graph, definition: GroupDefinition) -> String? {
        for id in level.order {
            if case .error(let message)? = level.results[id]?.state, let node = graph.nodes[id] {
                return Self.message(message, from: node, in: definition)
            }
        }
        return nil
    }

    /// The first reason an inner node gave for waiting, in evaluation order.
    static func firstIdleReason(in level: EvaluationLevel, graph: Graph, definition: GroupDefinition) -> String? {
        for id in level.order {
            if case .idle(let reason?)? = level.results[id]?.state, let node = graph.nodes[id] {
                return Self.message(reason, from: node, in: definition)
            }
        }
        return nil
    }

    /// Every warning inside, one per line, each with its trail, in evaluation order and without repeats.
    static func warnings(in level: EvaluationLevel, graph: Graph, definition: GroupDefinition) -> [String] {
        var lines: [String] = []
        for id in level.order {
            guard case .warning(let text)? = level.results[id]?.state, let node = graph.nodes[id] else { continue }
            for line in text.split(separator: "\n") {
                let trailed = Self.message(String(line), from: node, in: definition)
                if !lines.contains(trailed) { lines.append(trailed) }
            }
        }
        return lines
    }
}
```

**Replace the whole of** `Sources/CreatorGraph/Evaluator.swift` with:

```swift
import CreatorKernel

/// Evaluates the part of a graph a demand set needs, upstream first, caching each node's
/// result (spec §4.4). It throws only `CancellationError`. Every other failure becomes a
/// node state. A group node runs its definition's graph (groups spec §5, `Evaluator+Groups`).
public actor Evaluator {
    let registry: NodeRegistry
    let kernel: any Kernel
    private var cache: ResultCache

    public init(registry: NodeRegistry, kernel: any Kernel, cacheBudgetBytes: Int = 512 * 1024 * 1024) {
        self.registry = registry
        self.kernel = kernel
        self.cache = ResultCache(budgetBytes: cacheBudgetBytes)
    }

    public var cachedEntryCount: Int { cache.count }

    /// Evaluates `demand` on the top level of `graph`; group nodes run the graphs of `definitions`.
    public func evaluate(_ graph: Graph, definitions: [GroupID: GroupDefinition] = [:],
                         demand: Set<NodeID>) async throws -> EvaluationReport {
        // Entries of nodes no longer anywhere (deleted, or inside a group node that's gone) leave the cache.
        cache.removeEntries(notIn: graph.scopedNodeIDs(definitions: definitions))
        let parameters = Dictionary(graph.parameters.map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first })
        let setup = EvaluationSetup(registry: registry.withGroups(definitions), parameters: parameters)
        var trace = EvaluationTrace()
        let level = try await evaluateLevel(graph, demand: demand, scope: EvaluationScope(setup: setup), trace: &trace)
        return EvaluationReport(results: level.results, evaluatedNodes: level.evaluated, innerResults: trace.results,
                                evaluatedInnerNodes: trace.evaluated)
    }

    /// One level: the top-level graph, or a definition's graph inside a group node (`scope`). Cancellation is
    /// checked before every node, so inside groups too.
    func evaluateLevel(_ graph: Graph, demand: Set<NodeID>, scope: EvaluationScope,
                       trace: inout EvaluationTrace) async throws -> EvaluationLevel {
        let plan = graph.evaluationOrder(for: demand)
        var level = EvaluationLevel(order: plan.order)
        for id in plan.order {
            try Task.checkCancellation()
            guard let node = graph.nodes[id] else { continue }
            let result = plan.cyclic.contains(id)
                ? NodeResult(state: .error("This node is part of a cycle. Remove one of the wires in the loop."))
                : try await evaluateNode(node, in: graph, scope: scope, level: &level, trace: &trace)
            level.results[id] = result
            if !scope.path.isEmpty { trace.results[scope.path + [id]] = result }
        }
        return level
    }

    // One node of a level. One branch per kind of outcome (Group Input, unknown or newer type, the three gather
    // results, a group node, Group Output, any other node), which is over the limit.
    // swiftlint:disable:next cyclomatic_complexity
    private func evaluateNode(_ node: Node, in graph: Graph, scope: EvaluationScope,
                              level: inout EvaluationLevel, trace: inout EvaluationTrace) async throws -> NodeResult {
        if node.typeID == GroupNodes.inputTypeID {
            guard let bound = scope.bound else { return NodeResult(state: .error("Group Input works only inside a group.")) }
            level.keys[node.id] = bound.key
            return NodeResult(state: .ok(duration: .zero), outputs: bound.values)
        }
        guard let definition = scope.setup.registry[node.typeID] else {
            return NodeResult(state: .error("Unknown node type “\(node.typeID)”. It's kept so the file isn't damaged."))
        }
        if node.typeVersion > definition.typeVersion {
            return NodeResult(state: .error(
                "This node was saved by a newer MetalCreator (version \(node.typeVersion)). It's kept unchanged."))
        }
        // Picks stored inside a definition name faces as if it were the top level; read them as this instance's.
        let node = scope.naming(node)
        switch gather(node, definition, graph: graph, level: level, scope: scope) {
        case .blocked(let reason):
            return NodeResult(state: .idle(reason))
        case .failed(let message):
            return NodeResult(state: .error(message))
        case .ready(let inputs, let key):
            switch node.typeID {
            case GroupNodes.groupTypeID:
                let outcome = try await evaluateGroup(node, inputs: inputs, key: key, scope: scope, trace: &trace)
                level.keys[node.id] = outcome.key
                if outcome.ran { level.evaluated.append(node.id) }
                return outcome.result
            case GroupNodes.outputTypeID:
                // Values pass through unchanged; the group node takes them as its outputs.
                level.keys[node.id] = key
                return NodeResult(state: .ok(duration: .zero), outputs: inputs)
            default:
                level.keys[node.id] = key
                if let cached = cache.result(for: key) { return cached }
                var scoped = node
                scoped.id = scope.identity(of: node.id)  // Tags name the node this way (`EvalContext.tag`).
                let result = try await run(definition, node: scoped, inputs: inputs, setup: scope.setup)
                level.evaluated.append(node.id)
                if !scope.path.isEmpty { trace.evaluated.append(scope.path + [node.id]) }
                if result.state.isSuccess {
                    cache.insert(result, for: key, node: scoped.id)
                }
                return result
            }
        }
    }
}
```

**Create** `Sources/CreatorGraph/Evaluator+Running.swift`:

```swift
import CreatorKernel

extension Evaluator {
    enum Gathered {
        case ready([SocketName: Value], CacheKey)
        case blocked(String)
        case failed(String)
    }

    // Gathers a node's inputs (wire, else typed value, else the socket's default) and builds its cache key in the
    // same pass, naming the node by the identity it evaluates under (`EvaluationScope.identity(of:)`).
    // One pass over the inputs that also builds the cache key; one branch over the limit.
    // swiftlint:disable:next cyclomatic_complexity
    func gather(_ node: Node, _ definition: any NodeDefinition.Type, graph: Graph, level: EvaluationLevel,
                scope: EvaluationScope) -> Gathered {
        let setup = scope.setup
        var inputs: [SocketName: Value] = [:]
        var hasher = Hasher()
        // Output depends on node identity: the kernel tags created faces with it.
        hasher.combine(scope.identity(of: node.id))
        hasher.combine(node.typeID)
        hasher.combine(node.typeVersion)
        // Every stored constant, including non-socket settings, sorted for determinism.
        for (name, value) in node.inputValues.sorted(by: { $0.key < $1.key }) {
            hasher.combine(name)
            hasher.combine(value)
        }
        if definition.readsParameters {
            for (id, value) in setup.parameters.sorted(by: { $0.key < $1.key }) {
                hasher.combine(id)
                hasher.combine(value)
            }
        }

        for spec in setup.registry.inputs(for: node) {
            if let link = graph.incomingLink(to: Endpoint(node: node.id, socket: spec.name)) {
                guard let upstream = level.results[link.from.node], upstream.state.isSuccess, let outputs = upstream.outputs else {
                    return .blocked("Waiting on “\(spec.name)”: the node wired into it has no result.")
                }
                guard let value = outputs[link.from.socket] else {
                    return .failed("“\(spec.name)” is wired to “\(link.from.socket)”, "
                        + "which that node doesn't produce with its current settings.")
                }
                guard let converted = value.converted(to: spec.type) else {
                    return .failed("“\(spec.name)” needs \(spec.type.indefiniteName).")
                }
                inputs[spec.name] = converted
                hasher.combine(spec.name)
                hasher.combine(level.keys[link.from.node])
                hasher.combine(link.from.socket)
            } else if let constant = node.inputValues[spec.name] ?? spec.defaultValue {
                guard let scalar = Scalar(constant)?.converted(to: spec.type) else {
                    return .failed("“\(spec.name)” has a value of the wrong type.")
                }
                inputs[spec.name] = .one(scalar)
                hasher.combine(spec.defaultValue)
            } else if !spec.isOptional {
                return .blocked(NodeError.missingInput(spec.name).message)
            }
        }
        return .ready(inputs, CacheKey(digest: hasher.finalize()))
    }

    /// Runs a node once per broadcast item. `node` carries the identity it evaluates under.
    func run(_ definition: any NodeDefinition.Type, node: Node, inputs: [SocketName: Value],
             setup: EvaluationSetup) async throws -> NodeResult {
        let plan = BroadcastPlan.make(inputs: inputs, specs: setup.registry.inputs(for: node))
        let outputSpecs = setup.registry.outputs(for: node)
        let clock = ContinuousClock()
        let start = clock.now
        var collected: [SocketName: [Scalar]] = [:]
        var producedList: Set<SocketName> = []
        var absent: Set<SocketName> = []
        var warnings: [String] = []
        do {
            for item in 0..<plan.iterations {
                try Task.checkCancellation()
                let context = EvalContext(node: node, item: item, parameters: setup.parameters)
                let outputs = try await definition.evaluate(plan.inputs(at: item), kernel: kernel, context: context)
                for spec in outputSpecs {
                    if let list = outputs.lists[spec.name] {
                        collected[spec.name, default: []] += list
                        producedList.insert(spec.name)
                    } else if let scalar = outputs.values[spec.name] {
                        collected[spec.name, default: []].append(scalar)
                    } else if spec.isOptional {
                        absent.insert(spec.name)
                    } else {
                        throw NodeError.invalidValue("The node didn't produce its “\(spec.name)” output.")
                    }
                }
                warnings += outputs.warnings
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A node aborted by cancellation may throw something else; don't record that as an error.
            try Task.checkCancellation()
            return NodeResult(state: .error(Self.message(for: error)))
        }

        var outputs: [SocketName: Value] = [:]
        // An optional output that any iteration left out is absent from the result.
        for spec in outputSpecs where !absent.contains(spec.name) {
            let scalars = collected[spec.name] ?? []
            if plan.isSingle, !producedList.contains(spec.name), let only = scalars.first, scalars.count == 1 {
                outputs[spec.name] = .one(only)
            } else {
                outputs[spec.name] = .list(scalars)
            }
        }
        let unique = Array(Set(warnings)).sorted()
        let state: NodeState = unique.isEmpty ? .ok(duration: start.duration(to: clock.now)) : .warning(unique.joined(separator: "\n"))
        return NodeResult(state: state, outputs: outputs)
    }

    /// Plain-language text for any error a node can throw.
    public static func message(for error: any Error) -> String {
        switch error {
        case let error as KernelError: error.userMessage
        case let error as NodeError: error.message
        default: String(describing: error)
        }
    }
}
```

**Create** `Sources/CreatorGraph/Groups/Evaluator+Groups.swift`:

```swift
import CreatorKernel

extension Evaluator {
    /// A group node's result, the key its consumers' keys build on, and whether anything inside it ran.
    struct GroupOutcome {
        var result: NodeResult
        var key: CacheKey
        var ran: Bool
    }

    /// Runs group node `node` (groups spec §5): its definition's graph, demanding Group Output, with Group Input
    /// handing on `inputs` unchanged (no broadcasting here; nodes inside broadcast as usual). The group node takes
    /// Group Output's inputs as its outputs. It isn't cached itself: its inner nodes are, each under its own scoped
    /// identity, so instances never share entries and a definition edit misses exactly the nodes it changed. Its key
    /// joins its own gathered key with Group Output's, so consumers re-run when the inside changes.
    func evaluateGroup(_ node: Node, inputs: [SocketName: Value], key: CacheKey, scope: EvaluationScope,
                       trace: inout EvaluationTrace) async throws -> GroupOutcome {
        func failure(_ message: String) -> GroupOutcome {
            GroupOutcome(result: NodeResult(state: .error(message)), key: key, ran: false)
        }
        guard let definition = scope.setup.registry.group(of: node) else { return failure("This group's definition is missing.") }
        guard !scope.groups.contains(definition.id) else {
            return failure("“\(definition.name)” contains itself, so it can't be evaluated.")
        }
        guard definition.inputNode != nil, let output = definition.outputNode else {
            return failure("“\(definition.name)” has no Group Input or Group Output.")
        }
        let clock = ContinuousClock()
        let start = clock.now
        let before = trace.evaluated.count
        let inner = scope.entering(node.id, group: definition.id, graph: definition.graph,
                                  bound: EvaluationScope.Bound(values: inputs, key: key))
        let level = try await evaluateLevel(definition.graph, demand: [output.id], scope: inner, trace: &trace)
        let ran = trace.evaluated.count > before
        let graph = definition.graph
        if let message = GroupTrail.firstError(in: level, graph: graph, definition: definition) {
            return GroupOutcome(result: NodeResult(state: .error(message)), key: key, ran: ran)
        }
        guard let result = level.results[output.id], result.state.isSuccess, let outputs = result.outputs,
              let outputKey = level.keys[output.id] else {
            let reason = GroupTrail.firstIdleReason(in: level, graph: graph, definition: definition)
            return GroupOutcome(result: NodeResult(state: .idle(reason)), key: key, ran: ran)
        }
        var hasher = Hasher()
        hasher.combine(key)
        hasher.combine(outputKey)
        let warnings = GroupTrail.warnings(in: level, graph: graph, definition: definition)
        let state: NodeState = warnings.isEmpty
            ? .ok(duration: start.duration(to: clock.now)) : .warning(warnings.joined(separator: "\n"))
        return GroupOutcome(result: NodeResult(state: state, outputs: outputs), key: CacheKey(digest: hasher.finalize()), ran: ran)
    }
}
```

**Create** `Sources/CreatorGraph/Groups/ConstantValue+TagRenaming.swift`:

```swift
import CreatorKernel

extension ConstantValue {
    /// This value with every tag of a remembered pick (`.edgePicks`, `.facePick`) that names a node in `names`
    /// renamed to the node it maps to, blend faces' source edges included; any other value, and tags naming other
    /// nodes, unchanged. Picks keep naming the faces they named when the identities those faces are made under change
    /// (groups spec §5): inside a group (`EvaluationScope.naming`) and across Group, Ungroup and Make Unique.
    func renamingTags(_ names: [NodeID: NodeID]) -> ConstantValue {
        guard !names.isEmpty else { return self }
        switch self {
        case .edgePicks(let picks):
            return .edgePicks(picks.map { pick in
                var renamed = pick
                renamed.key = Self.renaming(pick.key, names)
                return renamed
            })
        case .facePick(let pick):
            return .facePick(FacePick(tags: Self.renaming(pick.tags, names)))
        default:
            return self
        }
    }

    private static func renaming(_ key: EdgeKey, _ names: [NodeID: NodeID]) -> EdgeKey {
        EdgeKey(renaming(key.first, names), renaming(key.second, names))
    }

    private static func renaming(_ tags: Set<TopoTag>, _ names: [NodeID: NodeID]) -> Set<TopoTag> {
        Set(tags.map { tag in
            var role = tag.role
            if case .blend(let edge) = tag.role { role = .blend(sourceEdge: renaming(edge, names)) }
            return TopoTag(node: names[tag.node] ?? tag.node, item: tag.item, role: role)
        })
    }
}
```

**Create** `Sources/CreatorGraph/Groups/Node+TagRenaming.swift`:

```swift
import CreatorKernel

extension Node {
    /// This node with the tags of every pick it stores renamed by `names` (`ConstantValue.renamingTags`).
    func renamingTags(_ names: [NodeID: NodeID]) -> Node {
        guard !names.isEmpty else { return self }
        var renamed = self
        for (name, value) in inputValues {
            renamed.inputValues[name] = value.renamingTags(names)
        }
        return renamed
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning'` (expect no output: no error, no new warning), then `swift test --skip-build --filter 'GroupEvaluationTests|EvaluatorTests|CacheTests'`

Expected: `Test run with 38 tests in 3 suites passed`.

- [ ] **Step 5: Verify the whole package**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-test.log`.

Expected: exit code 0; `grep -c 'recorded an issue' /tmp/groups-test.log` and `grep -c 'failed after' /tmp/groups-test.log` print 0; `grep -c 'Test run with' /tmp/groups-test.log` prints 11; the counts on those lines add up to **1435** (master + 45).

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorGraph/Groups/NodeID+Scoped.swift' 'Sources/CreatorGraph/Groups/GroupScopes.swift' 'Sources/CreatorGraph/Groups/Graph+ScopedIDs.swift' 'Sources/CreatorGraph/Groups/EvaluationSetup.swift' 'Sources/CreatorGraph/Groups/EvaluationScope.swift' 'Sources/CreatorGraph/Groups/EvaluationLevel.swift' 'Sources/CreatorGraph/Groups/EvaluationTrace.swift' 'Sources/CreatorGraph/EvaluationReport.swift' 'Sources/CreatorGraph/Groups/GroupTrail.swift' 'Sources/CreatorGraph/Evaluator.swift' 'Sources/CreatorGraph/Evaluator+Running.swift' 'Sources/CreatorGraph/Groups/Evaluator+Groups.swift' 'Sources/CreatorGraph/Groups/ConstantValue+TagRenaming.swift' 'Sources/CreatorGraph/Groups/Node+TagRenaming.swift' 'Tests/CreatorGraphTests/Support/GroupFixtures.swift' 'Tests/CreatorGraphTests/Support/FacePickCountNode.swift' 'Tests/CreatorGraphTests/Groups/GroupEvaluationTests.swift'
git commit -m "feat(graph): evaluate group nodes level by level under scoped node IDs"
```

---

### Task 6: `DocumentModel` holds the definitions

`DocumentModel` keeps a `GraphContent` (`content`; `graph` and `definitions` read it), applies every command through `GraphContent.apply`, marks the group nodes an edit inside a definition reaches as evaluating, evaluates with the definitions, saves them, and offers `perform(_:at:coalescingKey:)` for a command addressed to a graph path. `registry` becomes the opened registry carrying the document's definitions, so the editor (which reads `document.registry`) wires and draws group sockets without change. An edit that changes only a message (a renamed definition or inner node, `GraphContent.affectsMessages`) re-evaluates from the cache without marking anything evaluating; a new accent re-evaluates nothing. `innerResults` keeps the evaluation's results inside group nodes for C2. In the app, `AppModel.isEdited` compares `document.content` with the content last opened or saved (`savedContent`), so an edit only to a definition marks the document edited and New and Open ask before discarding it.

**Files:**
- Modify: `Sources/CreatorGraph/DocumentModel.swift`
- Modify: `Sources/CreatorApp/AppModel.swift`
- Modify: `Sources/CreatorApp/AppModel+Files.swift`
- Test: `Tests/CreatorGraphTests/Groups/DocumentModelGroupTests.swift`
- Test: `Tests/CreatorAppTests/GroupEditedTests.swift`

**Interfaces:**
- Consumes: Task 2: `GraphFile.definitions`. Task 4: `GraphContent`, `apply`, `touchedTopLevelNodes`, `GraphCommand.at`. Task 5: `Evaluator.evaluate(_:definitions:demand:)`.
- Produces:
  - `DocumentModel.content: GraphContent` (`public private(set)`), `graph: Graph` and `definitions: [GroupID: GroupDefinition]` (computed), `registry: NodeRegistry` (computed: `withGroups(definitions)`).
  - `DocumentModel.perform(_ command: GraphCommand, at path: GraphPath, coalescingKey: String? = nil) throws(GraphError)`.
  - `DocumentModel.innerResults: [[NodeID]: NodeResult]` (`public private(set)`).
  - `AppModel.savedContent: GraphContent` (internal; replaces `savedGraph`).

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorGraphTests/Groups/DocumentModelGroupTests.swift`:

```swift
import CreatorKernel
import Testing
@testable import CreatorGraph

/// The document holds its group definitions, edits them through `perform`, saves them and evaluates group nodes
/// (groups spec §4, §5).
@MainActor
struct DocumentModelGroupTests {
    let doubler = Doubler()

    func model(_ nodes: [Node], _ definitions: [GroupDefinition]) -> DocumentModel {
        DocumentModel(file: GraphFile(graph: graph(nodes), definitions: table(definitions)), registry: testRegistry,
                      kernel: FakeKernel())
    }

    @Test func groupNodesEvaluateAndTheRegistryCarriesTheDefinitions() async {
        let node = instance(of: doubler.definition, ["value": .number(4)], output: true)
        let document = model([node], [doubler.definition])
        await document.waitForEvaluation()
        #expect(document.definitions == table([doubler.definition]))
        #expect(document.registry.inputs(for: node) == doubler.definition.inputs)
        #expect(document.results[node.id]?.outputs?["result"]?.numbers == [8])
    }

    @Test func anEditInsideADefinitionReevaluatesItsGroupNodesAndUndoes() async throws {
        let node = instance(of: doubler.definition, ["value": .number(4)], output: true)
        let document = model([node], [doubler.definition])
        await document.waitForEvaluation()
        let wire = link(doubler.input, "value", doubler.add, "b")
        try document.perform(.batch([.disconnect(wire), .setInput(doubler.add.id, "b", .number(10))]),
                             at: .definition(doubler.id))
        #expect(document.results[node.id]?.state == .evaluating)
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.outputs?["result"]?.numbers == [14])
        #expect(document.definitions[doubler.id]?.graph.links.contains(wire) == false)
        document.undo()
        await document.waitForEvaluation()
        #expect(document.definitions == table([doubler.definition]))
        #expect(document.results[node.id]?.outputs?["result"]?.numbers == [8])
        document.redo()
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.outputs?["result"]?.numbers == [14])
    }

    @Test func definitionsAreSavedAndReopened() async throws {
        let node = instance(of: doubler.definition, output: true)
        let document = model([node], [doubler.definition])
        let reopened = try DocumentModel(data: try document.fileData(), registry: testRegistry, kernel: FakeKernel())
        #expect(reopened.content == document.content)
        await reopened.waitForEvaluation()
        #expect(reopened.results[node.id]?.outputs?["result"]?.numbers == [2])
    }

    @Test func aRefusedGroupEditLeavesNoUndoStep() {
        let document = model([], [doubler.definition])
        #expect(throws: GraphError.invalidValue("An Output node can't go in a group.")) {
            try document.perform(.addNode(makeNode(SinkNode.self)), at: .definition(doubler.id))
        }
        #expect(!document.canUndo)
    }

    @Test func renamesRefreshTheGroupsMessageWithoutMarkingItStale() async throws {
        let warn = makeNode(WarnNode.self)
        let warner = define("Warner", outputs: [SocketSpec("value", .number)], nodes: [warn]) { _, output in
            [link(warn, "value", output, "value")]
        }
        let node = instance(of: warner, output: true)
        let document = model([node], [warner])
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.state == .warning("Warner › Warn: Careful"))
        #expect(document.innerResults[[node.id, warn.id]]?.state == .warning("Careful"), "inner results are kept")

        try document.perform(.inDefinition(warner.id, .rename(warn.id, "Check")))
        #expect(document.results[node.id]?.state == .warning("Warner › Warn: Careful"), "not marked evaluating")
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.state == .warning("Warner › Check: Careful"))
        var interface = warner.interface
        interface.name = "Checker"
        try document.perform(.setInterface(warner.id, interface))
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.state == .warning("Checker › Check: Careful"))

        // A new accent changes no result and no message: nothing re-evaluates.
        interface.accent = .green
        try document.perform(.setInterface(warner.id, interface))
        #expect(!document.isEvaluating)
        document.undo()
        #expect(!document.isEvaluating)
        document.undo()
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.state == .warning("Warner › Check: Careful"))
    }
}
```

**Create** `Tests/CreatorAppTests/GroupEditedTests.swift`:

```swift
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// An edit that changes only a group definition marks the document edited (groups spec §5): New and Open ask before
/// throwing it away, and the title says "— Edited".
@MainActor
struct GroupEditedTests {
    @Test func editsToADefinitionMarkTheDocumentEditedUntilSaved() async throws {
        let registry = BuiltInNodes.registry
        var rib = GroupDefinition.make(name: "Rib", registry: registry)
        let rectangle = registry.makeNode(RectangleNode.typeID)
        rib.graph.nodes[rectangle.id] = rectangle
        let node = registry.withGroups([rib.id: rib]).makeGroupNode(GroupNodes.groupTypeID, for: rib.id)
        let app = AppModel(kernel: FakeKernel(), file: GraphFile(graph: Graph(nodes: [node.id: node]), definitions: [rib.id: rib]))
        await app.settle()
        #expect(!app.isEdited, "opening a file with definitions isn't an edit")
        let url = temporaryURL("rib.mcgraph")
        defer { try? FileManager.default.removeItem(at: url) }

        try app.document.perform(.setInput(rectangle.id, "width", .number(5)), at: .definition(rib.id))
        #expect(app.isEdited, "an edit inside a definition")
        try app.save(to: url)
        #expect(!app.isEdited)

        var interface = rib.interface
        interface.accent = .green
        try app.document.perform(.setInterface(rib.id, interface))
        #expect(app.isEdited, "a new accent")
        try app.save(to: url)
        #expect(!app.isEdited)
        app.document.undo()
        #expect(app.isEdited, "undoing past the save")
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning' | head`

Expected: error: extra argument 'at' in call (and: cannot infer contextual base in reference to member 'definition'): `perform(_:at:)` doesn't exist yet.

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorGraph/DocumentModel.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorGraph/DocumentModel.swift b/Sources/CreatorGraph/DocumentModel.swift
index 32eeba4..a1e4260 100644
--- a/Sources/CreatorGraph/DocumentModel.swift
+++ b/Sources/CreatorGraph/DocumentModel.swift
@@ -2,13 +2,17 @@ import CreatorKernel
 import Foundation
 import Observation
 
-/// One open document: the graph, its undo history and its latest evaluation. The UI observes
-/// this. Every edit goes through `perform(_:coalescingKey:)`.
+/// One open document: the graph and its group definitions, its undo history and its latest evaluation. The UI
+/// observes this. Every edit goes through `perform(_:coalescingKey:)` (or `perform(_:at:coalescingKey:)`).
 @MainActor
 @Observable
 public final class DocumentModel {
-    public private(set) var graph: Graph
+    /// The top-level graph and the group definitions (groups spec §4), edited together.
+    public private(set) var content: GraphContent
     public private(set) var results: [NodeID: NodeResult] = [:]
+    /// Results inside group nodes (groups spec §5), by instance path: the group nodes from the top level down, then
+    /// the inner node's ID (`EvaluationReport.innerResults`). C2 draws a group's inside from these.
+    public private(set) var innerResults: [[NodeID]: NodeResult] = [:]
     /// The last successful outputs of each node. The viewport ghosts these when a node errors (spec §4.4).
     public private(set) var lastGoodOutputs: [NodeID: [SocketName: Value]] = [:]
     public private(set) var isEvaluating = false
@@ -30,7 +34,8 @@ public final class DocumentModel {
         }
     }
 
-    public let registry: NodeRegistry
+    /// The registry the document was opened with, without its definitions.
+    @ObservationIgnored private let baseRegistry: NodeRegistry
     private var undoStack = UndoStack()
     @ObservationIgnored private let evaluator: Evaluator
     @ObservationIgnored private var evaluationTask: Task<Void, Never>?
@@ -38,9 +43,9 @@ public final class DocumentModel {
 
     public init(file: GraphFile = GraphFile(), registry: NodeRegistry, kernel: any Kernel,
                 cacheBudgetBytes: Int = 512 * 1024 * 1024) {
-        self.graph = file.graph
+        self.content = GraphContent(graph: file.graph, definitions: file.definitions)
         self.viewState = file.viewState
-        self.registry = registry
+        self.baseRegistry = registry
         self.evaluator = Evaluator(registry: registry, kernel: kernel, cacheBudgetBytes: cacheBudgetBytes)
         scheduleEvaluation()
     }
@@ -49,6 +54,13 @@ public final class DocumentModel {
         self.init(file: try GraphFileIO.decode(data, registry: registry), registry: registry, kernel: kernel)
     }
 
+    /// The top-level graph.
+    public var graph: Graph { content.graph }
+    /// The document's group definitions.
+    public var definitions: [GroupID: GroupDefinition] { content.definitions }
+    /// The registry carrying this document's definitions, so group nodes have their sockets.
+    public var registry: NodeRegistry { baseRegistry.withGroups(content.definitions) }
+
     public var canUndo: Bool { undoStack.canUndo }
     public var canRedo: Bool { undoStack.canRedo }
 
@@ -56,11 +68,16 @@ public final class DocumentModel {
     /// drag, then call `endCoalescing()` when the drag ends, so the drag is one undo step.
     public func perform(_ command: GraphCommand, coalescingKey: String? = nil) throws(GraphError) {
         // The stale set must be taken before the edit, so dependents of removed nodes and links count.
-        let stale = graph.downstreamClosure(of: command.touchedNodes)
-        let inverse = try graph.apply(command, registry: registry)
+        let stale = graph.downstreamClosure(of: content.touchedTopLevelNodes(command))
+        let effect = effect(of: command)
+        let inverse = try content.apply(command, registry: baseRegistry)
         undoStack.record(forward: command, inverse: inverse, coalescingKey: coalescingKey)
-        guard command.affectsResults else { return }
-        didChange(markingStale: stale)
+        didChange(effect, markingStale: stale)
+    }
+
+    /// Applies a graph command to the graph at `path`: the top level, or inside a group definition (groups spec §5).
+    public func perform(_ command: GraphCommand, at path: GraphPath, coalescingKey: String? = nil) throws(GraphError) {
+        try perform(command.at(path), coalescingKey: coalescingKey)
     }
 
     public func endCoalescing() {
@@ -78,7 +95,7 @@ public final class DocumentModel {
     }
 
     public func fileData() throws -> Data {
-        try GraphFileIO.encode(GraphFile(graph: graph, viewState: viewState))
+        try GraphFileIO.encode(GraphFile(graph: graph, definitions: definitions, viewState: viewState))
     }
 
     /// Returns once the most recently scheduled evaluation has finished and been applied.
@@ -97,20 +114,31 @@ public final class DocumentModel {
         return ids
     }
 
+    /// What applying `command` to the content as it is now changes: results (mark the stale nodes and re-evaluate),
+    /// only group messages (re-evaluate, every result cached, nothing marked), or nothing.
+    private func effect(of command: GraphCommand) -> (results: Bool, messages: Bool) {
+        (content.affectsResults(command), content.affectsMessages(command))
+    }
+
     private func replay(_ command: GraphCommand) {
-        let stale = graph.downstreamClosure(of: command.touchedNodes)
+        let stale = graph.downstreamClosure(of: content.touchedTopLevelNodes(command))
+        let effect = effect(of: command)
         do {
-            try graph.apply(command, registry: registry)
+            try content.apply(command, registry: baseRegistry)
         } catch {
             // Undo and redo replay commands that were valid when recorded, so this means
             // the history is out of step with the graph.
             assertionFailure("Undo history could not be replayed: \(error)")
         }
-        guard command.affectsResults else { return }
-        didChange(markingStale: stale)
+        didChange(effect, markingStale: stale)
     }
 
-    private func didChange(markingStale stale: Set<NodeID>) {
+    private func didChange(_ effect: (results: Bool, messages: Bool), markingStale stale: Set<NodeID>) {
+        guard effect.results else {
+            // A renamed definition or inner node: group messages carry the names, so re-evaluate (from the cache).
+            if effect.messages { scheduleEvaluation() }
+            return
+        }
         let existing = Set(graph.nodes.keys)
         results = results.filter { existing.contains($0.key) }
         lastGoodOutputs = lastGoodOutputs.filter { existing.contains($0.key) }
@@ -128,14 +156,14 @@ public final class DocumentModel {
         evaluationTask?.cancel()
         generation += 1
         let current = generation
-        let snapshot = graph
+        let snapshot = content
         let demand = demand
         let evaluator = evaluator
         isEvaluating = true
         evaluationTask = Task {
             let report: EvaluationReport
             do {
-                report = try await evaluator.evaluate(snapshot, demand: demand)
+                report = try await evaluator.evaluate(snapshot.graph, definitions: snapshot.definitions, demand: demand)
             } catch {
                 return  // Cancelled: a newer generation is already scheduled.
             }
@@ -147,6 +175,7 @@ public final class DocumentModel {
     private func apply(_ report: EvaluationReport) {
         // Replace, not merge: a node that left the demand must not keep a stale `.evaluating` state.
         results = report.results
+        innerResults = report.innerResults
         for (id, result) in report.results {
             if result.state.isSuccess, let outputs = result.outputs {
                 lastGoodOutputs[id] = outputs
```

**Modify** `Sources/CreatorApp/AppModel.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorApp/AppModel.swift b/Sources/CreatorApp/AppModel.swift
index ce3e609..1af7b1d 100644
--- a/Sources/CreatorApp/AppModel.swift
+++ b/Sources/CreatorApp/AppModel.swift
@@ -26,8 +26,8 @@ public final class AppModel {
     public private(set) var viewport: ViewportModel
     /// Where the document was last opened from or saved to; `nil` for a new one.
     public internal(set) var fileURL: URL?
-    /// The graph as it was last opened or saved. The document is edited while its graph differs.
-    var savedGraph: Graph
+    /// The graph and its group definitions as they were last opened or saved. The document is edited while they differ.
+    var savedContent: GraphContent
     public var previewMode: PreviewMode = .final
     /// "Pick edges in view…" in progress.
     public internal(set) var pick: PickSession?
@@ -66,13 +66,13 @@ public final class AppModel {
         graphInput = parts.input
         viewport = parts.viewport
         self.fileURL = fileURL
-        savedGraph = file.graph
+        savedContent = GraphContent(graph: file.graph, definitions: file.definitions)
         connectParts()
     }
 
-    /// True while the graph differs from the one last opened or saved. Camera, dock and canvas changes are saved
-    /// with the file but don't count as edits.
-    public var isEdited: Bool { document.graph != savedGraph }
+    /// True while the graph or a group definition differs from the one last opened or saved. Camera, dock and canvas
+    /// changes are saved with the file but don't count as edits.
+    public var isEdited: Bool { document.content != savedContent }
 
     /// The file's name, or "Untitled".
     public var displayName: String { fileURL?.lastPathComponent ?? "Untitled" }
@@ -89,7 +89,7 @@ public final class AppModel {
         graphInput = parts.input
         viewport = parts.viewport
         fileURL = url
-        savedGraph = file.graph
+        savedContent = GraphContent(graph: file.graph, definitions: file.definitions)
         requestedScene = []
         connectParts()
     }
```

**Modify** `Sources/CreatorApp/AppModel+Files.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorApp/AppModel+Files.swift b/Sources/CreatorApp/AppModel+Files.swift
index 5643141..0a39a1f 100644
--- a/Sources/CreatorApp/AppModel+Files.swift
+++ b/Sources/CreatorApp/AppModel+Files.swift
@@ -71,7 +71,7 @@ extension AppModel {
             throw AppProblem("“\(url.lastPathComponent)” couldn't be saved", error.localizedDescription)
         }
         fileURL = url
-        savedGraph = document.graph
+        savedContent = document.content
     }
 
     /// Save: to the document's file, or Save As… for a new document. Returns whether it was saved.
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning'` (expect no output: no error, no new warning), then `swift test --skip-build --filter 'DocumentModelGroupTests|DocumentModelTests|GroupEditedTests'`

Expected: `Test run with 22 tests in 2 suites passed`; `Test run with 1 test in 1 suite passed`.

- [ ] **Step 5: Verify the whole package**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-test.log`.

Expected: exit code 0; `grep -c 'recorded an issue' /tmp/groups-test.log` and `grep -c 'failed after' /tmp/groups-test.log` print 0; `grep -c 'Test run with' /tmp/groups-test.log` prints 11; the counts on those lines add up to **1441** (master + 51).

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorGraph/DocumentModel.swift' 'Sources/CreatorApp/AppModel.swift' 'Sources/CreatorApp/AppModel+Files.swift' 'Tests/CreatorGraphTests/Groups/DocumentModelGroupTests.swift' 'Tests/CreatorAppTests/GroupEditedTests.swift'
git commit -m "feat(graph,app): DocumentModel edits, evaluates and saves group definitions; edits to them mark the document edited"
```

---

### Task 7: Group (⌘G's command)

`GroupCommands.group` (spec §5) builds one `GroupEdit`: a new definition named "Group", "Group 2"… holding the selected nodes (positions relative to the selection's top-left, Group Input 240 pt left of them, Group Output 240 pt right) and the links among them; one input per distinct outside source (named after the first input it feeds, made unique, typed by the source, with the target's unit and range) and one output per distinct inside source wired out; the group node at the top-left with the boundary rewired to it; the new node selected. Refused for an empty selection, Group Input/Output, an Output node, or a boundary socket of unknown type. Inside the group the moved nodes make their faces under scoped IDs, so the same batch renames every pick in the document that names one (`GroupScopes.renamingPicks`): on the grouped level a tag naming X becomes `NodeID.scoped([group node, X])`, and in every graph that reaches that level through group nodes the same with that chain in front. Picks inside the selection keep naming the nodes as they did (Task 5 reads them per level), so no pick drifts.

**Files:**
- Create: `Sources/CreatorGraph/Groups/GroupEdit.swift`
- Create: `Sources/CreatorGraph/Groups/GroupScopes+PickRenaming.swift`
- Create: `Sources/CreatorGraph/Groups/GroupBuilder.swift`
- Create: `Sources/CreatorGraph/Groups/GroupCommands.swift`
- Test: `Tests/CreatorGraphTests/Support/GroupScene.swift`
- Test: `Tests/CreatorGraphTests/Groups/GroupCommandTests.swift`

**Interfaces:**
- Consumes: Task 4: `GraphContent`, `GraphPath`, `GraphCommand.at`, `GroupNaming`, `GroupRefusal`, `GraphCommand.addDefinition`. Task 5: `GroupScopes.paths`/`identity`, `ConstantValue.renamingTags`, `NodeID.scoped`, the pick fixtures. Task 6: `DocumentModel.content`, `perform`.
- Produces:
  - `public struct GroupEdit: Sendable, Equatable { var command: GraphCommand; var selection: Set<NodeID> }`.
  - `public enum GroupCommands { static let boundaryMargin = 240.0; static func group(_ ids: Set<NodeID>, in path: GraphPath, of content: GraphContent, registry: NodeRegistry) throws(GraphError) -> GroupEdit }`.
  - Internal: `GroupBuilder`; `GroupScopes.names(in:definitions:through:_:) -> [NodeID: NodeID]`, `chains(to:in:) -> [(path: GraphPath, chain: [NodeID])]`, `renamingPicks(at:in:skipping:_:) -> [GraphCommand]`.
  - Fixture: `struct GroupScene` (c1, c2, a1, a2, sink, other; `nodes`, `links`, `position(_:_:_:)`).

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorGraphTests/Support/GroupScene.swift`:

```swift
// Test fixture file: the graph the Group and Ungroup tests group.
import CreatorGeometry
import CreatorKernel
@testable import CreatorGraph

/// c1 (2) feeds both of a1's inputs, a1 and c2 (3) feed a2; a2 feeds the Sink and a1 feeds `other`.
struct GroupScene {
    let c1 = position(makeNode(ConstantNode.self, ["value": .number(2)]), 0, 0)
    let c2 = position(makeNode(ConstantNode.self, ["value": .number(3)]), 0, 100)
    let a1 = position(makeNode(AddNode.self), 200, 0)
    let a2 = position(makeNode(AddNode.self), 200, 100)
    let sink = position(makeNode(SinkNode.self, output: true), 400, 50)
    let other = position(makeNode(AddNode.self), 400, 200)

    var nodes: [Node] { [c1, c2, a1, a2, sink, other] }
    var links: [Link] {
        [link(c1, "value", a1, "a"), link(c1, "value", a1, "b"), link(a1, "sum", a2, "a"), link(c2, "value", a2, "b"),
         link(a2, "sum", sink, "value"), link(a1, "sum", other, "a"), ]
    }

    static func position(_ node: Node, _ x: Double, _ y: Double) -> Node {
        var placed = node
        placed.position = Vector2(x, y)
        return placed
    }
}
```

**Create** `Tests/CreatorGraphTests/Groups/GroupCommandTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Group (⌘G, groups spec §5).
@MainActor
struct GroupCommandTests {
    let scene = GroupScene()

    func document(_ extra: [Node] = []) -> DocumentModel {
        var start = graph(scene.nodes + extra, scene.links)
        start.sortLinks()  // As a loaded file has them, so undo compares equal.
        return DocumentModel(file: GraphFile(graph: start), registry: testRegistry, kernel: FakeKernel())
    }

    func group(_ ids: Set<NodeID>, in document: DocumentModel, at path: GraphPath = .root) throws -> GroupEdit {
        let edit = try GroupCommands.group(ids, in: path, of: document.content, registry: testRegistry)
        try document.perform(edit.command)
        return edit
    }

    @Test func groupingMovesTheNodesIntoANewDefinitionAndWiresTheBoundary() async throws {
        let document = document()
        await document.waitForEvaluation()
        #expect(document.results[scene.sink.id]?.outputs?["value"]?.numbers == [7])
        let edit = try group([scene.a1.id, scene.a2.id], in: document)

        let definition = try #require(document.definitions.values.first)
        #expect(definition.name == "Group")
        #expect(definition.inputs == [SocketSpec("a", .number), SocketSpec("b", .number)])
        #expect(definition.outputs == [SocketSpec("sum", .number), SocketSpec("sum2", .number)])
        #expect(definition.graph.nodes[scene.a1.id]?.position == Vector2(0, 0))
        #expect(definition.graph.nodes[scene.a2.id]?.position == Vector2(0, 100))
        #expect(definition.inputNode?.position == Vector2(-240, 0))
        #expect(definition.outputNode?.position == Vector2(240, 0))
        let input = try #require(definition.inputNode), output = try #require(definition.outputNode)
        #expect(Set(definition.graph.links) == [
            link(input, "a", scene.a1, "a"), link(input, "a", scene.a1, "b"), link(input, "b", scene.a2, "b"),
            link(scene.a1, "sum", scene.a2, "a"), link(scene.a1, "sum", output, "sum"), link(scene.a2, "sum", output, "sum2"),
        ])

        let node = try #require(edit.selection.first.flatMap { document.graph.nodes[$0] })
        #expect(edit.selection.count == 1)
        #expect(node.typeID == GroupNodes.groupTypeID && node.name == "Group" && node.position == Vector2(200, 0))
        #expect(document.graph.nodes[scene.a1.id] == nil && document.graph.nodes[scene.a2.id] == nil)
        #expect(Set(document.graph.links) == [
            link(scene.c1, "value", node, "a"), link(scene.c2, "value", node, "b"),
            link(node, "sum2", scene.sink, "value"), link(node, "sum", scene.other, "a"),
        ])

        await document.waitForEvaluation()
        #expect(document.results[scene.sink.id]?.outputs?["value"]?.numbers == [7])
    }

    @Test func groupingIsOneUndoStep() throws {
        let document = document()
        let before = document.content
        _ = try group([scene.a1.id, scene.a2.id], in: document)
        document.undo()
        #expect(document.content == before)
        document.redo()
        #expect(document.definitions.count == 1)
    }

    @Test func eachNewDefinitionGetsTheNextName() throws {
        let document = document()
        _ = try group([scene.a1.id], in: document)
        _ = try group([scene.a2.id], in: document)
        #expect(Set(document.definitions.values.map(\.name)) == ["Group", "Group 2"])
    }

    @Test func groupingInsideADefinitionNestsAGroup() async throws {
        let doubler = Doubler()
        let node = instance(of: doubler.definition, ["value": .number(5)], output: true)
        let document = DocumentModel(file: GraphFile(graph: graph([node]), definitions: table([doubler.definition])),
                                     registry: testRegistry, kernel: FakeKernel())
        let edit = try group([doubler.add.id], in: document, at: .definition(doubler.id))
        let inner = try #require(document.definitions.values.first { $0.id != doubler.id })
        #expect(inner.inputs.map(\.name) == ["a"], "Group Input's one source feeds both of Add's inputs")
        #expect(document.definitions[doubler.id]?.graph.nodes[edit.selection.first ?? NodeID()]?.typeID == GroupNodes.groupTypeID)
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.outputs?["result"]?.numbers == [10])
    }

    @Test func oneSourceWiredOutTwiceIsOneOutput() throws {
        let second = GroupScene.position(makeNode(AddNode.self), 400, 300)
        var start = graph(scene.nodes + [second], scene.links + [link(scene.a2, "sum", second, "a")])
        start.sortLinks()
        let document = DocumentModel(file: GraphFile(graph: start), registry: testRegistry, kernel: FakeKernel())
        let edit = try group([scene.a2.id], in: document)
        let node = try #require(edit.selection.first)
        #expect(document.definitions.values.first?.outputs.map(\.name) == ["sum"])
        let fromGroup = Endpoint(node: node, socket: "sum")
        #expect(document.graph.incomingLink(to: Endpoint(node: scene.sink.id, socket: "value"))?.from == fromGroup)
        #expect(document.graph.incomingLink(to: Endpoint(node: second.id, socket: "a"))?.from == fromGroup)
    }

    @Test func groupingAGroupNodeNestsItAndKeepsTheResult() async throws {
        let document = document()
        let first = try group([scene.a1.id, scene.a2.id], in: document)
        let inner = try #require(first.selection.first)
        let outer = try group([inner], in: document)
        let outerNode = try #require(outer.selection.first.flatMap { document.graph.nodes[$0] })
        let outerDefinition = try #require(document.registry.group(of: outerNode))
        #expect(outerDefinition.graph.nodes[inner]?.typeID == GroupNodes.groupTypeID)
        await document.waitForEvaluation()
        #expect(document.results[scene.sink.id]?.outputs?["value"]?.numbers == [7])
    }

    @Test func socketAndDefinitionNamesAreMadeUnique() {
        #expect(GroupNaming.uniqueSocketName("a", among: ["a", "a2"]) == "a3")
        #expect(GroupNaming.uniqueSocketName(NodeSetting.group, among: []) == "groupID2")
        #expect(GroupNaming.uniqueSocketName("projection.e1", among: []) == "projection.e12")
        #expect(GroupNaming.uniqueSocketName("b", among: ["a"]) == "b")
        let doubler = Doubler(name: "Group")
        #expect(GroupNaming.uniqueDefinitionName("Group", among: table([doubler.definition])) == "Group 2")
        #expect(GroupNaming.uniqueDefinitionName("Rib", among: table([doubler.definition])) == "Rib")
    }

    @Test func groupingIsRefusedPlainly() {
        let document = document()
        let doubler = Doubler()
        let content = GraphContent(graph: document.graph, definitions: table([doubler.definition]))
        #expect(throws: GraphError.invalidValue("Select the nodes to group.")) {
            try GroupCommands.group([], in: .root, of: content, registry: testRegistry)
        }
        #expect(throws: GraphError.invalidValue("An Output node can't go in a group.")) {
            try GroupCommands.group([scene.a2.id, scene.sink.id], in: .root, of: content, registry: testRegistry)
        }
        #expect(throws: GraphError.invalidValue("Group Input and Group Output can't go in a group.")) {
            try GroupCommands.group([doubler.input.id, doubler.add.id], in: .definition(doubler.id), of: content,
                                    registry: testRegistry)
        }
        var mystery = GroupScene.position(makeNode(ConstantNode.self), -200, 0)
        mystery.typeID = "missing.type"
        var withMystery = content
        withMystery.graph.nodes[mystery.id] = mystery
        withMystery.graph.links.append(link(mystery, "value", scene.a1, "a"))
        withMystery.graph.links.removeAll { $0 == link(scene.c1, "value", scene.a1, "a") }
        #expect(throws: GraphError.invalidValue(
            "A wire into the selection comes from a socket of unknown type, so it can't become an input.")) {
            try GroupCommands.group([scene.a1.id], in: .root, of: withMystery, registry: testRegistry)
        }
    }

    /// The counts of `ids`' `count` outputs after evaluating `content` with the face pick counter registered.
    func counts(_ content: GraphContent, _ ids: [NodeID]) async throws -> [Double?] {
        let report = try await Evaluator(registry: pickRegistry, kernel: FakeKernel())
            .evaluate(content.graph, definitions: content.definitions, demand: Set(ids))
        return ids.map { report.results[$0]?.outputs?["count"]?.numbers?.first }
    }

    @Test func groupingRenamesThePicksOnTheGroupedNodesFaces() async throws {
        let box = pickRegistry.makeNode(BoxNode.typeID)
        var inside = pickRegistry.makeNode(FacePickCountNode.typeID), outside = pickRegistry.makeNode(FacePickCountNode.typeID)
        inside.inputValues[NodeSetting.face] = endCapPick(of: box.id)
        outside.inputValues[NodeSetting.face] = endCapPick(of: box.id)
        var unrelated = pickRegistry.makeNode(FacePickCountNode.typeID)
        unrelated.inputValues[NodeSetting.face] = endCapPick(of: outside.id)
        let sink = pickRegistry.makeNode(SinkNode.typeID)  // So the inside counter's count is an output of the group.
        var content = GraphContent(graph: graph([box, inside, outside, unrelated, sink], [
            link(box, "solid", inside, "solid"), link(box, "solid", outside, "solid"), link(inside, "count", sink, "value"),
        ]))
        #expect(try await counts(content, [inside.id, outside.id]) == [1, 1])

        let edit = try GroupCommands.group([box.id, inside.id], in: .root, of: content, registry: pickRegistry)
        try content.apply(edit.command, registry: pickRegistry)
        let node = try #require(edit.selection.first)
        let definition = try #require(content.definitions.values.first)
        #expect(content.graph.nodes[outside.id]?.inputValues[NodeSetting.face] == endCapPick(of: NodeID.scoped([node, box.id])))
        #expect(definition.graph.nodes[inside.id]?.inputValues[NodeSetting.face] == endCapPick(of: box.id),
                "a pick inside the selection names its nodes as before")
        #expect(content.graph.nodes[unrelated.id]?.inputValues[NodeSetting.face] == endCapPick(of: outside.id))
        #expect(try await counts(content, [outside.id]) == [1])
        let report = try await Evaluator(registry: pickRegistry, kernel: FakeKernel())
            .evaluate(content.graph, definitions: content.definitions, demand: [node])
        #expect(report.innerResults[[node, inside.id]]?.outputs?["count"]?.numbers == [1])
    }

    @Test func groupingInsideADefinitionRenamesPicksThroughEachInstance() async throws {
        let box = pickRegistry.makeNode(BoxNode.typeID)
        let boxer = define("Boxer", outputs: [SocketSpec("solid", .solid)], nodes: [box]) { _, output in
            [link(box, "solid", output, "solid")]
        }
        let first = instance(of: boxer), second = instance(of: boxer)
        var counters: [Node] = []
        for placed in [first, second] {
            var counter = pickRegistry.makeNode(FacePickCountNode.typeID)
            counter.inputValues[NodeSetting.face] = endCapPick(of: NodeID.scoped([placed.id, box.id]))
            counters.append(counter)
        }
        var content = GraphContent(graph: graph([first, second] + counters, [
            link(first, "solid", counters[0], "solid"), link(second, "solid", counters[1], "solid"),
        ]), definitions: table([boxer]))
        #expect(try await counts(content, counters.map(\.id)) == [1, 1])

        let edit = try GroupCommands.group([box.id], in: .definition(boxer.id), of: content, registry: pickRegistry)
        try content.apply(edit.command, registry: pickRegistry)
        let node = try #require(edit.selection.first)
        #expect(content.graph.nodes[counters[0].id]?.inputValues[NodeSetting.face]
            == endCapPick(of: NodeID.scoped([first.id, node, box.id])))
        #expect(try await counts(content, counters.map(\.id)) == [1, 1])
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning' | head`

Expected: error: cannot find type 'GroupEdit' in scope.

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorGraph/Groups/GroupEdit.swift`:

```swift
import CreatorKernel

/// What a group command builds (groups spec §5): the command to perform, one undo step, and the nodes to select after
/// it. The command also renames the picks the edit would otherwise strand (`GroupScopes.renamingPicks`), so every pick
/// keeps naming the faces it named.
public struct GroupEdit: Sendable, Equatable {
    public var command: GraphCommand
    public var selection: Set<NodeID>

    public init(command: GraphCommand, selection: Set<NodeID>) {
        self.command = command
        self.selection = selection
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupScopes+PickRenaming.swift`:

```swift
import CreatorKernel

extension GroupScopes {
    /// How the picks of a graph name the nodes an edit moves: for every path from `graph` (`paths(in:definitions:)`)
    /// that `rename` maps to the path its node has after the edit, the identity before (`identity`) mapped to the one
    /// after, both reached through `chain` (the group nodes from the picks' graph down to `graph`).
    static func names(in graph: Graph, definitions: [GroupID: GroupDefinition], through chain: [NodeID] = [],
                      _ rename: ([NodeID]) -> [NodeID]?) -> [NodeID: NodeID] {
        var names: [NodeID: NodeID] = [:]
        for path in paths(in: graph, definitions: definitions) {
            if let renamed = rename(path) { names[identity(chain + path)] = identity(chain + renamed) }
        }
        return names
    }

    /// Every graph that reaches the graph at `level`, with each chain of group nodes it reaches it through: `level`
    /// itself through no group node, and each graph placing it, directly or through other groups, once per chain.
    static func chains(to level: GraphPath, in content: GraphContent) -> [(path: GraphPath, chain: [NodeID])] {
        var found: [(path: GraphPath, chain: [NodeID])] = [(level, [])]
        guard case .definition(let target) = level else { return found }
        func visit(_ graph: Graph, from path: GraphPath, prefix: [NodeID], entered: [GroupID]) {
            for node in graph.nodes.values.sorted(by: { $0.id < $1.id }) where node.typeID == GroupNodes.groupTypeID {
                guard let id = node.inputValues[NodeSetting.group]?.groupID, !entered.contains(id),
                      let definition = content.definitions[id] else { continue }
                if id == target {
                    found.append((path, prefix + [node.id]))
                } else {
                    visit(definition.graph, from: path, prefix: prefix + [node.id], entered: entered + [id])
                }
            }
        }
        visit(content.graph, from: .root, prefix: [], entered: [])
        for definition in content.definitions.values.sorted(by: { $0.id < $1.id }) where definition.id != target {
            visit(definition.graph, from: .definition(definition.id), prefix: [], entered: [definition.id])
        }
        return found
    }

    /// The commands that keep every pick in `content` naming its faces when an edit to the graph at `level` changes
    /// the paths its nodes are reached by: `rename` maps a path from that graph to the node's path after the edit, or
    /// gives `nil` for one that stays. Each pick it changes gets one `setInput`, addressed to its graph; the picks on
    /// `skipping`, nodes of the graph at `level` that the edit takes out of it, are left as they are.
    static func renamingPicks(at level: GraphPath, in content: GraphContent, skipping: Set<NodeID> = [],
                              _ rename: ([NodeID]) -> [NodeID]?) -> [GraphCommand] {
        guard let graph = content.graph(at: level) else { return [] }
        var commands: [GraphCommand] = []
        for (path, chain) in chains(to: level, in: content) {
            guard let host = content.graph(at: path) else { continue }
            let table = names(in: graph, definitions: content.definitions, through: chain, rename)
            guard !table.isEmpty else { continue }
            for node in host.nodes.values.sorted(by: { $0.id < $1.id }) where !(path == level && skipping.contains(node.id)) {
                for (setting, value) in node.inputValues.sorted(by: { $0.key < $1.key }) {
                    let renamed = value.renamingTags(table)
                    if renamed != value { commands.append(GraphCommand.setInput(node.id, setting, renamed).at(path)) }
                }
            }
        }
        return commands
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupBuilder.swift`:

```swift
import CreatorGeometry
import CreatorKernel

/// Builds what one Group command makes (`GroupCommands.group`): the new definition, holding the grouped nodes at
/// their places relative to the selection's top-left and the links among them, and the wires outside that join the
/// new group node to the rest of its graph.
struct GroupBuilder {
    private let graph: Graph
    private let sockets: NodeRegistry
    private let input: NodeID
    private let output: NodeID
    let groupNode: Node
    private(set) var definition: GroupDefinition
    private(set) var outside: [Link] = []
    private var inputs: [Endpoint: SocketName] = [:]
    private var outputs: [Endpoint: SocketName] = [:]

    /// `sockets` carries the document's definitions; `registry` makes the new nodes.
    init(_ picked: [Node], from graph: Graph, content: GraphContent, sockets: NodeRegistry,
         registry: NodeRegistry) throws(GraphError) {
        let topLeft = Vector2(picked.map(\.position.x).min() ?? 0, picked.map(\.position.y).min() ?? 0)
        let right = (picked.map(\.position.x).max() ?? 0) - topLeft.x
        let id = GroupID()
        var definition = GroupDefinition.make(
            id: id, name: GroupNaming.uniqueDefinitionName("Group", among: content.definitions), registry: registry,
            inputAt: Vector2(-GroupCommands.boundaryMargin, 0), outputAt: Vector2(right + GroupCommands.boundaryMargin, 0))
        guard let input = definition.inputNode, let output = definition.outputNode else { throw GroupRefusal.boundaryCount }
        let ids = Set(picked.map(\.id))
        for node in picked {
            var moved = node
            moved.position = node.position - topLeft
            definition.graph.nodes[moved.id] = moved
        }
        definition.graph.links = graph.links.filter { ids.contains($0.from.node) && ids.contains($0.to.node) }
        self.graph = graph
        self.sockets = sockets
        self.input = input.id
        self.output = output.id
        self.definition = definition
        groupNode = sockets.withGroups(content.definitions.merging([id: definition]) { first, _ in first })
            .makeGroupNode(GroupNodes.groupTypeID, for: id, at: topLeft)
    }

    /// A wire from outside into the selection: its source becomes an input (once per source), and inside, Group
    /// Input feeds the wire's target.
    mutating func wireIn(_ link: Link) throws(GraphError) {
        let name: SocketName
        if let known = inputs[link.from] {
            name = known
        } else {
            guard let type = type(of: link.from) else {
                throw .invalidValue("A wire into the selection comes from a socket of unknown type, so it can't become an input.")
            }
            let target = graph.nodes[link.to.node].flatMap { node in
                sockets.inputs(for: node).first { $0.name == link.to.socket }
            }
            name = GroupNaming.uniqueSocketName(link.to.socket, among: definition.inputs.map(\.name))
            definition.inputs.append(SocketSpec(name, type, unit: target?.unit ?? .none, range: target?.range))
            inputs[link.from] = name
            outside.append(Link(from: link.from, to: Endpoint(node: groupNode.id, socket: name)))
        }
        definition.graph.links.append(Link(from: Endpoint(node: input, socket: name), to: link.to))
    }

    /// A wire from the selection out: its source becomes an output (once per source) that Group Output takes inside,
    /// and outside, the group node feeds the wire's target.
    mutating func wireOut(_ link: Link) throws(GraphError) {
        let name: SocketName
        if let known = outputs[link.from] {
            name = known
        } else {
            guard let type = type(of: link.from) else {
                throw .invalidValue("A wire out of the selection leaves a socket of unknown type, so it can't become an output.")
            }
            name = GroupNaming.uniqueSocketName(link.from.socket, among: definition.outputs.map(\.name))
            definition.outputs.append(SocketSpec(name, type))
            outputs[link.from] = name
            definition.graph.links.append(Link(from: link.from, to: Endpoint(node: output, socket: name)))
        }
        outside.append(Link(from: Endpoint(node: groupNode.id, socket: name), to: link.to))
    }

    /// The definition with its links in canonical order.
    var finished: GroupDefinition {
        var finished = definition
        finished.graph.sortLinks()
        return finished
    }

    private func type(of source: Endpoint) -> SocketType? {
        graph.nodes[source.node].flatMap { node in sockets.outputs(for: node).first { $0.name == source.socket }?.type }
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupCommands.swift`:

```swift
import CreatorGeometry
import CreatorKernel

/// The group commands (groups spec §5), each built as one `GroupEdit` whose command `DocumentModel.perform` applies
/// as one undo step. Builders only read the document; `GraphContent.apply` checks the group rules again.
public enum GroupCommands {
    /// How far Group Input sits left of the grouped nodes, and Group Output right of them, inside a new definition.
    public static let boundaryMargin = 240.0

    /// Group (⌘G): moves `ids`, nodes of the graph at `path`, into a new definition named "Group" ("Group 2", …) and
    /// puts one group node of it at their top-left, selected. Links among them move with them; each distinct source
    /// outside that feeds them becomes one input (named after the first input it feeds, made unique) and each
    /// distinct source inside wired out becomes one output (named after it). Inputs and outputs are ordered by their
    /// nodes' places, top to bottom. The grouped nodes' faces are made under new identities (`NodeID.scoped`), so every
    /// pick outside the selection that names one is renamed to match; picks inside it name them as before. Refused for
    /// an empty selection, Group Input or Output, an Output node, or a boundary socket whose type can't be told.
    public static func group(_ ids: Set<NodeID>, in path: GraphPath, of content: GraphContent,
                             registry: NodeRegistry) throws(GraphError) -> GroupEdit {
        guard let graph = content.graph(at: path) else { throw GroupRefusal.missing }
        let sockets = registry.withGroups(content.definitions)
        let picked = try groupable(ids, in: graph, sockets: sockets)
        var builder = try GroupBuilder(picked, from: graph, content: content, sockets: sockets, registry: registry)
        for link in boundary(of: ids, in: graph, inbound: true) { try builder.wireIn(link) }
        for link in boundary(of: ids, in: graph, inbound: false) { try builder.wireOut(link) }

        let here: [GraphCommand] = ids.sorted().map { .removeNode($0) } + [.addNode(builder.groupNode)]
            + (builder.outside.isEmpty ? [] : [.restoreLinks(builder.outside)])
        let groupNode = builder.groupNode.id
        let picks = GroupScopes.renamingPicks(at: path, in: content, skipping: ids) { reached in
            guard let first = reached.first, ids.contains(first) else { return nil }
            return [groupNode] + reached
        }
        return GroupEdit(command: .batch([.addDefinition(builder.finished), GraphCommand.batch(here).at(path)] + picks),
                         selection: [groupNode])
    }

    /// The selected nodes, by ID, or why they can't be grouped.
    private static func groupable(_ ids: Set<NodeID>, in graph: Graph, sockets: NodeRegistry) throws(GraphError) -> [Node] {
        guard !ids.isEmpty else { throw .invalidValue("Select the nodes to group.") }
        var picked: [Node] = []
        for id in ids.sorted() {
            guard let node = graph.nodes[id] else { throw .nodeNotFound(id) }
            if GroupNodes.isBoundary(node) { throw .invalidValue("Group Input and Group Output can't go in a group.") }
            if node.isOutput || sockets[node.typeID]?.category == .output { throw GroupRefusal.outputInside }
            picked.append(node)
        }
        return picked
    }

    /// The links crossing into (`inbound`) or out of the selection, ordered by the place of the node inside it, top
    /// to bottom and then left to right, then by ID and socket, so the group's sockets follow the layout.
    private static func boundary(of ids: Set<NodeID>, in graph: Graph, inbound: Bool) -> [Link] {
        func order(_ link: Link) -> (Double, Double, String) {
            let end = inbound ? link.to : link.from
            let position = graph.nodes[end.node]?.position ?? .zero
            return (position.y, position.x, end.node.rawValue.uuidString + "." + end.socket.rawValue)
        }
        return graph.links.filter { link in
            let (inner, other) = inbound ? (link.to.node, link.from.node) : (link.from.node, link.to.node)
            return ids.contains(inner) && !ids.contains(other)
        }.sorted { order($0) < order($1) }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning'` (expect no output: no error, no new warning), then `swift test --skip-build --filter 'GroupCommandTests'`

Expected: `Test run with 10 tests in 1 suite passed`.

- [ ] **Step 5: Verify the whole package**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-test.log`.

Expected: exit code 0; `grep -c 'recorded an issue' /tmp/groups-test.log` and `grep -c 'failed after' /tmp/groups-test.log` print 0; `grep -c 'Test run with' /tmp/groups-test.log` prints 11; the counts on those lines add up to **1451** (master + 61).

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorGraph/Groups/GroupEdit.swift' 'Sources/CreatorGraph/Groups/GroupScopes+PickRenaming.swift' 'Sources/CreatorGraph/Groups/GroupBuilder.swift' 'Sources/CreatorGraph/Groups/GroupCommands.swift' 'Tests/CreatorGraphTests/Support/GroupScene.swift' 'Tests/CreatorGraphTests/Groups/GroupCommandTests.swift'
git commit -m "feat(graph): Group moves a selection into a new definition"
```

---

### Task 8: Ungroup and Make Unique

`GroupCommands.ungroup` splices a group node back (spec §5): the definition's nodes with fresh IDs, placed relative to the group node; outside sources rewired onto the inner targets, an unwired input's typed value (or default) written onto them; the group node's consumers fed by what fed Group Output, Group Input wired straight to Group Output resolved to what fed that input (or its value); the spliced nodes selected; the definition removed with its last group node. `GroupCommands.makeUnique` copies the definition as "Name 2" with fresh inner IDs and points this group node, renamed, at the copy. Both rename the picks they would strand, in the same batch: outside, a tag naming `scoped([group node, X, …])` becomes the spliced copy's ID (Ungroup) or `scoped([group node, X's copy, …])` (Make Unique), through every chain of group nodes that reaches the level; inside, the spliced or copied nodes' own picks name the copies. So, beyond spec §5, no pick drifts across them either (Errata (C1)).

**Files:**
- Create: `Sources/CreatorGraph/Groups/GroupSplice.swift`
- Create: `Sources/CreatorGraph/Groups/GroupCommands+Ungroup.swift`
- Create: `Sources/CreatorGraph/Groups/GroupCommands+MakeUnique.swift`
- Test: `Tests/CreatorGraphTests/Groups/UngroupTests.swift`

**Interfaces:**
- Consumes: Task 4: `GroupDependencies.instances`, `GroupNaming`, `GraphCommand.at`. Task 5: `Node.renamingTags`. Task 7: `GroupEdit`, `GroupScopes.names`/`renamingPicks`.
- Produces:
  - `GroupCommands.ungroup(_ id: NodeID, in: GraphPath, of: GraphContent, registry: NodeRegistry) throws(GraphError) -> GroupEdit`.
  - `GroupCommands.makeUnique(_ id: NodeID, in: GraphPath, of: GraphContent, registry: NodeRegistry) throws(GraphError) -> GroupEdit`.
  - Internal: `GroupCommands.groupNode(_:in:of:registry:action:)`, `struct GroupSplice` (`init(definition:at:definitions:)`, `fresh`).

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorGraphTests/Groups/UngroupTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Ungroup and Make Unique (groups spec §5).
@MainActor
struct UngroupTests {
    let scene = GroupScene()
    let doubler = Doubler()

    func document(_ nodes: [Node], _ links: [Link] = [], _ definitions: [GroupDefinition] = []) -> DocumentModel {
        var start = graph(nodes, links)
        start.sortLinks()
        return DocumentModel(file: GraphFile(graph: start, definitions: table(definitions)), registry: testRegistry,
                             kernel: FakeKernel())
    }

    func perform(_ edit: GroupEdit, on document: DocumentModel) throws -> GroupEdit {
        try document.perform(edit.command)
        return edit
    }

    @Test func ungroupingPutsTheNodesBackWithNewIDs() async throws {
        let document = document(scene.nodes, scene.links)
        let before = document.content
        let grouped = try perform(try GroupCommands.group([scene.a1.id, scene.a2.id], in: .root, of: document.content,
                                                          registry: testRegistry), on: document)
        let node = try #require(grouped.selection.first)
        let edit = try perform(try GroupCommands.ungroup(node, in: .root, of: document.content, registry: testRegistry),
                               on: document)
        #expect(document.definitions.isEmpty, "its last group node is gone")
        #expect(edit.selection.count == 2)
        #expect(edit.selection.isDisjoint(with: [scene.a1.id, scene.a2.id]))
        let spliced = edit.selection.compactMap { document.graph.nodes[$0] }
        #expect(Set(spliced.map(\.position)) == [Vector2(200, 0), Vector2(200, 100)])
        #expect(document.graph.links.count == scene.links.count)
        await document.waitForEvaluation()
        #expect(document.results[scene.sink.id]?.outputs?["value"]?.numbers == [7])
        document.undo()
        document.undo()
        #expect(document.content == before)
    }

    @Test func anUnwiredInputsValueLandsOnTheInnerInputs() async throws {
        let node = instance(of: doubler.definition, ["value": .number(4)])
        let sink = makeNode(SinkNode.self, output: true)
        let document = document([node, sink], [link(node, "result", sink, "value")], [doubler.definition])
        let edit = try perform(try GroupCommands.ungroup(node.id, in: .root, of: document.content, registry: testRegistry),
                               on: document)
        let add = try #require(edit.selection.first.flatMap { document.graph.nodes[$0] })
        #expect(add.inputValues == ["a": .number(4), "b": .number(4)])
        #expect(document.graph.links == [Link(from: Endpoint(node: add.id, socket: "sum"), to: Endpoint(node: sink.id, socket: "value"))])
        await document.waitForEvaluation()
        #expect(document.results[sink.id]?.outputs?["value"]?.numbers == [8])
    }

    @Test func aStraightThroughWireJoinsWhatFedItToWhatItFed() throws {
        let pass = define("Pass", inputs: [SocketSpec("x", .number)], outputs: [SocketSpec("y", .number)], nodes: []) { input, output in
            [link(input, "x", output, "y")]
        }
        let constant = makeNode(ConstantNode.self), wired = instance(of: pass), typed = instance(of: pass, ["x": .number(5)])
        let first = makeNode(SinkNode.self, output: true), second = makeNode(SinkNode.self, output: true)
        let document = document([constant, wired, typed, first, second],
                                [link(constant, "value", wired, "x"), link(wired, "y", first, "value"), link(typed, "y", second, "value")],
                                [pass])
        _ = try perform(try GroupCommands.ungroup(wired.id, in: .root, of: document.content, registry: testRegistry), on: document)
        let fed = document.graph.incomingLink(to: Endpoint(node: first.id, socket: "value"))?.from
        #expect(fed == Endpoint(node: constant.id, socket: "value"))
        #expect(document.definitions[pass.id] != nil, "another group node still uses it")
        _ = try perform(try GroupCommands.ungroup(typed.id, in: .root, of: document.content, registry: testRegistry), on: document)
        #expect(document.graph.nodes[second.id]?.inputValues["value"] == .number(5))
        #expect(document.definitions.isEmpty)
    }

    @Test func onlyAGroupNodeUngroups() {
        let content = GraphContent(graph: graph([scene.c1]))
        #expect(throws: GraphError.invalidValue("Select one group node to ungroup.")) {
            try GroupCommands.ungroup(scene.c1.id, in: .root, of: content, registry: testRegistry)
        }
        #expect(throws: GraphError.invalidValue("Select one group node to make unique.")) {
            try GroupCommands.makeUnique(scene.c1.id, in: .root, of: content, registry: testRegistry)
        }
    }

    @Test func makeUniqueGivesOneGroupNodeItsOwnCopy() async throws {
        let kept = instance(of: doubler.definition, ["value": .number(1)], output: true)
        let split = instance(of: doubler.definition, ["value": .number(1)], output: true)
        let document = document([kept, split], [], [doubler.definition])
        let before = document.content
        let edit = try perform(try GroupCommands.makeUnique(split.id, in: .root, of: document.content, registry: testRegistry),
                               on: document)
        #expect(edit.selection == [split.id])
        let copy = try #require(document.definitions.values.first { $0.id != doubler.id })
        #expect(copy.name == "Doubler 2" && copy.inputs == doubler.definition.inputs && copy.outputs == doubler.definition.outputs)
        #expect(Set(copy.graph.nodes.keys).isDisjoint(with: doubler.definition.graph.nodes.keys))
        #expect(copy.graph.nodes.count == 3 && copy.graph.links.count == 3)
        #expect(copy.inputNode?.inputValues[NodeSetting.group] == .group(copy.id))
        #expect(document.graph.nodes[split.id]?.inputValues[NodeSetting.group] == .group(copy.id))
        #expect(document.graph.nodes[split.id]?.name == "Doubler 2")

        let add = try #require(copy.graph.nodes.values.first { $0.typeID == AddNode.typeID })
        let wire = try #require(copy.graph.incomingLink(to: Endpoint(node: add.id, socket: "b")))
        try document.perform(.batch([.disconnect(wire), .setInput(add.id, "b", .number(10))]), at: .definition(copy.id))
        await document.waitForEvaluation()
        #expect(document.results[kept.id]?.outputs?["result"]?.numbers == [2])
        #expect(document.results[split.id]?.outputs?["result"]?.numbers == [11])
        document.undo()
        document.undo()
        #expect(document.content == before)
    }

    /// "Counted": a box whose end cap a counter inside picks; it puts out the box's solid and the count. One group
    /// node of it, and a counter outside picking that node's box's end cap.
    struct CountedScene {
        var content: GraphContent
        let box: Node
        let counter: Node
        let node: Node
        let outside: Node
    }

    func countedScene() -> CountedScene {
        let box = pickRegistry.makeNode(BoxNode.typeID)
        var counter = pickRegistry.makeNode(FacePickCountNode.typeID)
        counter.inputValues[NodeSetting.face] = endCapPick(of: box.id)
        let counted = define("Counted", outputs: [SocketSpec("count", .number), SocketSpec("solid", .solid)],
                             nodes: [box, counter]) { _, output in
            [link(box, "solid", counter, "solid"), link(counter, "count", output, "count"), link(box, "solid", output, "solid")]
        }
        let node = instance(of: counted)
        var outside = pickRegistry.makeNode(FacePickCountNode.typeID)
        outside.inputValues[NodeSetting.face] = endCapPick(of: NodeID.scoped([node.id, box.id]))
        let content = GraphContent(graph: graph([node, outside], [link(node, "solid", outside, "solid")]),
                                   definitions: table([counted]))
        return CountedScene(content: content, box: box, counter: counter, node: node, outside: outside)
    }

    func count(_ content: GraphContent, _ path: [NodeID]) async throws -> Double? {
        let report = try await Evaluator(registry: pickRegistry, kernel: FakeKernel())
            .evaluate(content.graph, definitions: content.definitions, demand: [path[0]])
        let result = path.count == 1 ? report.results[path[0]] : report.innerResults[path]
        return result?.outputs?["count"]?.numbers?.first
    }

    @Test func ungroupRenamesThePicksOnTheSplicedNodesFaces() async throws {
        let counted = countedScene()
        var content = counted.content
        let (box, counter, node, outside) = (counted.box, counted.counter, counted.node, counted.outside)
        #expect(try await count(content, [outside.id]) == 1)
        let edit = try GroupCommands.ungroup(node.id, in: .root, of: content, registry: pickRegistry)
        try content.apply(edit.command, registry: pickRegistry)
        let spliced = try #require(content.graph.nodes.values.first { $0.typeID == BoxNode.typeID })
        let splicedCounter = try #require(content.graph.nodes.values.first { $0.id != outside.id && $0.typeID == FacePickCountNode.typeID })
        #expect(spliced.id != box.id && splicedCounter.id != counter.id)
        #expect(content.graph.nodes[outside.id]?.inputValues[NodeSetting.face] == endCapPick(of: spliced.id))
        #expect(splicedCounter.inputValues[NodeSetting.face] == endCapPick(of: spliced.id))
        #expect(try await count(content, [outside.id]) == 1)
        #expect(try await count(content, [splicedCounter.id]) == 1)
    }

    @Test func makeUniqueRenamesThePicksOnTheCopysFaces() async throws {
        let counted = countedScene()
        var content = counted.content
        let (box, node, outside) = (counted.box, counted.node, counted.outside)
        let edit = try GroupCommands.makeUnique(node.id, in: .root, of: content, registry: pickRegistry)
        try content.apply(edit.command, registry: pickRegistry)
        let copy = try #require(content.definitions.values.first { $0.name == "Counted 2" })
        let copyBox = try #require(copy.graph.nodes.values.first { $0.typeID == BoxNode.typeID })
        let copyCounter = try #require(copy.graph.nodes.values.first { $0.typeID == FacePickCountNode.typeID })
        #expect(copyBox.id != box.id)
        #expect(content.graph.nodes[outside.id]?.inputValues[NodeSetting.face] == endCapPick(of: NodeID.scoped([node.id, copyBox.id])))
        #expect(copyCounter.inputValues[NodeSetting.face] == endCapPick(of: copyBox.id))
        #expect(try await count(content, [outside.id]) == 1)
        #expect(try await count(content, [node.id, copyCounter.id]) == 1)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning' | head`

Expected: error: type 'GroupCommands' has no member 'ungroup' (and 'makeUnique').

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorGraph/Groups/GroupSplice.swift`:

```swift
import CreatorGeometry
import CreatorKernel

/// A definition's nodes on their way out of it (Ungroup): copies with fresh IDs, placed relative to the group node,
/// and the links among them, to which Ungroup adds the ones across the old boundary. The copies' picks name the
/// copies, as the originals' named the originals.
struct GroupSplice {
    private(set) var nodes: [NodeID: Node] = [:]
    var links: [Link] = []
    /// Each inner node's copy, by the inner node's ID.
    private(set) var fresh: [NodeID: NodeID] = [:]

    init(definition: GroupDefinition, at origin: Vector2, definitions: [GroupID: GroupDefinition]) {
        for node in definition.graph.nodes.values where !GroupNodes.isBoundary(node) {
            fresh[node.id] = NodeID()
        }
        let names = GroupScopes.names(in: definition.graph, definitions: definitions) { [fresh] path in
            path.first.flatMap { fresh[$0] }.map { [$0] + path.dropFirst() }
        }
        for node in definition.graph.nodes.values {
            guard let id = fresh[node.id] else { continue }
            var copy = node.renamingTags(names)
            copy.id = id
            copy.position = node.position + origin
            nodes[id] = copy
        }
        links = definition.graph.links.compactMap { link in
            guard let from = endpoint(link.from), let to = endpoint(link.to) else { return nil }
            return Link(from: from, to: to)
        }
    }

    /// `endpoint` of an inner node, on its spliced copy; `nil` for Group Input and Group Output.
    func endpoint(_ endpoint: Endpoint) -> Endpoint? {
        fresh[endpoint.node].map { Endpoint(node: $0, socket: endpoint.socket) }
    }

    /// Feeds inner input `target` from `source` outside, or else writes `value` onto it.
    mutating func feed(_ target: Endpoint, from source: Endpoint?, value: ConstantValue?) {
        guard let spliced = endpoint(target) else { return }
        if let source {
            links.append(Link(from: source, to: spliced))
        } else if let value {
            nodes[spliced.node]?.inputValues[spliced.socket] = value
        }
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupCommands+Ungroup.swift`:

```swift
import CreatorKernel

extension GroupCommands {
    /// Ungroup (⇧⌘G): splices group node `id`, in the graph at `path`, back into that graph and selects what it
    /// spliced (groups spec §5). Its definition's nodes come back with fresh IDs, placed relative to the group node.
    /// Whatever fed an input of the group node now feeds what Group Input fed with it; an unwired input's typed value
    /// (or its default) is written onto those inner inputs instead. What took an output of the group node now takes
    /// what fed Group Output, and where Group Input fed Group Output straight through, what fed that input (or its
    /// value). The definition is removed with its last group node. Picks on the spliced nodes' faces, outside them or
    /// inside, are renamed to the nodes' new IDs, so they keep naming the same faces.
    public static func ungroup(_ id: NodeID, in path: GraphPath, of content: GraphContent,
                               registry: NodeRegistry) throws(GraphError) -> GroupEdit {
        let (graph, instance, definition) = try groupNode(id, in: path, of: content, registry: registry, action: "ungroup")
        guard let input = definition.inputNode, let output = definition.outputNode else { throw GroupRefusal.boundaryCount }
        var splice = GroupSplice(definition: definition, at: instance.position, definitions: content.definitions)
        for spec in definition.inputs {
            let external = graph.incomingLink(to: Endpoint(node: id, socket: spec.name))?.from
            let value = instance.inputValues[spec.name] ?? spec.defaultValue
            for link in definition.graph.links where link.from == Endpoint(node: input.id, socket: spec.name) {
                splice.feed(link.to, from: external, value: value)
            }
        }
        var settings: [GraphCommand] = []
        for spec in definition.outputs {
            guard let source = definition.graph.incomingLink(to: Endpoint(node: output.id, socket: spec.name))?.from else { continue }
            let throughFrom = source.node == input.id
                ? graph.incomingLink(to: Endpoint(node: id, socket: source.socket))?.from : splice.endpoint(source)
            let throughValue = source.node == input.id
                ? instance.inputValues[source.socket] ?? definition.inputs.first { $0.name == source.socket }?.defaultValue : nil
            for link in graph.links where link.from == Endpoint(node: id, socket: spec.name) {
                if let throughFrom {
                    splice.links.append(Link(from: throughFrom, to: link.to))
                } else if let throughValue {
                    settings.append(.setInput(link.to.node, link.to.socket, throughValue))
                }
            }
        }
        let here: [GraphCommand] = [.removeNode(id)] + splice.nodes.values.sorted { $0.id < $1.id }.map { .addNode($0) }
            + (splice.links.isEmpty ? [] : [.restoreLinks(splice.links)]) + settings
        let lastOne = GroupDependencies.instances(of: definition.id, in: content).allSatisfy { $0.path == path && $0.node.id == id }
        let fresh = splice.fresh
        let picks = GroupScopes.renamingPicks(at: path, in: content, skipping: [id]) { reached in
            guard reached.count > 1, reached.first == id, let copy = fresh[reached[1]] else { return nil }
            return [copy] + reached.dropFirst(2)
        }
        return GroupEdit(command: .batch([GraphCommand.batch(here).at(path)] + picks
                                         + (lastOne ? [.removeDefinition(definition.id)] : [])),
                         selection: Set(splice.nodes.keys))
    }

    /// The graph at `path`, group node `id` in it and its definition, or a refusal naming `action`.
    static func groupNode(_ id: NodeID, in path: GraphPath, of content: GraphContent, registry: NodeRegistry,
                          action: String) throws(GraphError) -> (Graph, Node, GroupDefinition) {
        guard let graph = content.graph(at: path) else { throw GroupRefusal.missing }
        guard let node = graph.nodes[id] else { throw .nodeNotFound(id) }
        guard node.typeID == GroupNodes.groupTypeID else { throw .invalidValue("Select one group node to \(action).") }
        guard let definition = registry.withGroups(content.definitions).group(of: node) else { throw GroupRefusal.missing }
        return (graph, node, definition)
    }
}
```

**Create** `Sources/CreatorGraph/Groups/GroupCommands+MakeUnique.swift`:

```swift
import CreatorKernel

extension GroupCommands {
    /// Make Unique: copies group node `id`'s definition as "Name 2" (the next free number), with fresh IDs for every
    /// node inside, and points this group node, renamed to match, at the copy (groups spec §5). Picks on this group
    /// node's faces, and the copy's own picks, are renamed to the new IDs, so they keep naming the same faces.
    public static func makeUnique(_ id: NodeID, in path: GraphPath, of content: GraphContent,
                                  registry: NodeRegistry) throws(GraphError) -> GroupEdit {
        let (_, _, definition) = try groupNode(id, in: path, of: content, registry: registry, action: "make unique")
        let copyID = GroupID()
        var copy = GroupDefinition(id: copyID, name: GroupNaming.uniqueDefinitionName(definition.name, among: content.definitions),
                                   accent: definition.accent, inputs: definition.inputs, outputs: definition.outputs)
        let fresh = Dictionary(uniqueKeysWithValues: definition.graph.nodes.keys.map { ($0, NodeID()) })
        let names = GroupScopes.names(in: definition.graph, definitions: content.definitions) { path in
            path.first.flatMap { fresh[$0] }.map { [$0] + path.dropFirst() }
        }
        for node in definition.graph.nodes.values {
            var inner = node.renamingTags(names)
            inner.id = fresh[node.id] ?? NodeID()
            if GroupNodes.isBoundary(inner) { inner.inputValues[NodeSetting.group] = .group(copyID) }
            copy.graph.nodes[inner.id] = inner
        }
        copy.graph.links = definition.graph.links.compactMap { link in
            guard let from = fresh[link.from.node], let to = fresh[link.to.node] else { return nil }
            return Link(from: Endpoint(node: from, socket: link.from.socket), to: Endpoint(node: to, socket: link.to.socket))
        }
        copy.graph.sortLinks()
        let here = GraphCommand.batch([.setInput(id, NodeSetting.group, .group(copyID)), .rename(id, copy.name)])
        let picks = GroupScopes.renamingPicks(at: path, in: content) { reached in
            guard reached.count > 1, reached.first == id, let copy = fresh[reached[1]] else { return nil }
            return [id, copy] + reached.dropFirst(2)
        }
        return GroupEdit(command: .batch([.addDefinition(copy), here.at(path)] + picks), selection: [id])
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning'` (expect no output: no error, no new warning), then `swift test --skip-build --filter 'UngroupTests'`

Expected: `Test run with 7 tests in 1 suite passed`.

- [ ] **Step 5: Verify the whole package**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-test.log`.

Expected: exit code 0; `grep -c 'recorded an issue' /tmp/groups-test.log` and `grep -c 'failed after' /tmp/groups-test.log` print 0; `grep -c 'Test run with' /tmp/groups-test.log` prints 11; the counts on those lines add up to **1458** (master + 68).

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorGraph/Groups/GroupSplice.swift' 'Sources/CreatorGraph/Groups/GroupCommands+Ungroup.swift' 'Sources/CreatorGraph/Groups/GroupCommands+MakeUnique.swift' 'Tests/CreatorGraphTests/Groups/UngroupTests.swift'
git commit -m "feat(graph): Ungroup and Make Unique"
```

---

### Task 9: Definition edits: rename, accent, sockets, delete

The rest of spec §5's commands, each one command for one undo step: rename (and the group nodes still named after the definition), set accent, add a socket (name made unique), rename a socket everywhere (the definition, Group Input's or Group Output's wires inside, every group node's wires and typed value), reorder sockets, remove a socket (refused while a group node has it wired, naming that node; otherwise its inside wires and typed values go too), and delete an unused definition.

**Files:**
- Create: `Sources/CreatorGraph/Groups/GroupCommands+Interface.swift`
- Test: `Tests/CreatorGraphTests/Groups/GroupInterfaceTests.swift`

**Interfaces:**
- Consumes: Task 4: `GraphCommand.setInterface`, `removeDefinition`, `GroupDependencies.instances`, `GroupNaming`, `GroupRefusal`, `GroupSocketSide`. Task 6: `DocumentModel`.
- Produces:
  - `GroupCommands.rename(_:to:in:)`, `setAccent(_:_:in:)`, `addSocket(_:side:name:type:in:) -> (command: GraphCommand, name: SocketName)`, `moveSocket(_:side:from:to:in:)`, `renameSocket(_:side:from:to:in:)`, `removeSocket(_:side:name:in:)`, `deleteDefinition(_:in:)`, each `throws(GraphError) -> GraphCommand` unless noted.

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorGraphTests/Groups/GroupInterfaceTests.swift`:

```swift
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Definition edits (groups spec §5): rename, accent, sockets and delete, each one undo step.
@MainActor
struct GroupInterfaceTests {
    let doubler = Doubler()

    /// A constant wired into one Doubler, a typed value on another, and both results taken by sinks.
    @MainActor
    struct Setup {
        let constant = makeNode(ConstantNode.self, ["value": .number(3)])
        let wired: Node
        let typed: Node
        let first = makeNode(SinkNode.self, output: true)
        let second = makeNode(SinkNode.self, output: true)
        let document: DocumentModel

        init(_ doubler: Doubler) {
            wired = instance(of: doubler.definition)
            typed = instance(of: doubler.definition, ["value": .number(4)])
            var start = graph([constant, wired, typed, first, second], [
                link(constant, "value", wired, "value"), link(wired, "result", first, "value"), link(typed, "result", second, "value"),
            ])
            start.sortLinks()
            document = DocumentModel(file: GraphFile(graph: start, definitions: table([doubler.definition])),
                                     registry: testRegistry, kernel: FakeKernel())
        }
    }

    @Test func renamingADefinitionRenamesTheGroupNodesNamedAfterIt() throws {
        let setup = Setup(doubler)
        try setup.document.perform(.rename(setup.typed.id, "Mine"))
        let before = setup.document.content
        try setup.document.perform(try GroupCommands.rename(doubler.id, to: "Twice", in: setup.document.content))
        #expect(setup.document.definitions[doubler.id]?.name == "Twice")
        #expect(setup.document.graph.nodes[setup.wired.id]?.name == "Twice")
        #expect(setup.document.graph.nodes[setup.typed.id]?.name == "Mine")
        setup.document.undo()
        #expect(setup.document.content == before)
        let taken = Doubler(name: "Taken")
        try setup.document.perform(.addDefinition(taken.definition))
        #expect(throws: GraphError.invalidValue("A group named “Taken” already exists.")) {
            try setup.document.perform(try GroupCommands.rename(doubler.id, to: "Taken", in: setup.document.content))
        }
    }

    @Test func theAccentIsADefinitionEdit() throws {
        let setup = Setup(doubler)
        try setup.document.perform(try GroupCommands.setAccent(doubler.id, .orange, in: setup.document.content))
        #expect(setup.document.definitions[doubler.id]?.accent == .orange)
        setup.document.undo()
        #expect(setup.document.definitions[doubler.id]?.accent == .purple)
    }

    @Test func anAddedSocketGetsAFreeName() throws {
        let setup = Setup(doubler)
        let (command, name) = try GroupCommands.addSocket(doubler.id, side: .input, name: "value", type: .integer,
                                                          in: setup.document.content)
        try setup.document.perform(command)
        #expect(name == "value2")
        #expect(setup.document.registry.inputs(for: setup.wired).map(\.name) == ["value", "value2"])
        let (output, outputName) = try GroupCommands.addSocket(doubler.id, side: .output, name: "result", type: .solid,
                                                               in: setup.document.content)
        try setup.document.perform(output)
        #expect(outputName == "result2")
        #expect(setup.document.definitions[doubler.id]?.outputs.last == SocketSpec("result2", .solid))
    }

    @Test func renamingASocketKeepsItsWiresAndValues() async throws {
        let setup = Setup(doubler)
        let before = setup.document.content
        try setup.document.perform(try GroupCommands.renameSocket(doubler.id, side: .input, from: "value", to: "x",
                                                                  in: setup.document.content))
        try setup.document.perform(try GroupCommands.renameSocket(doubler.id, side: .output, from: "result", to: "out",
                                                                  in: setup.document.content))
        let document = setup.document
        #expect(document.graph.incomingLink(to: Endpoint(node: setup.wired.id, socket: "x"))?.from.node == setup.constant.id)
        #expect(document.graph.nodes[setup.typed.id]?.inputValues["x"] == .number(4))
        #expect(document.graph.nodes[setup.typed.id]?.inputValues["value"] == nil)
        #expect(document.graph.incomingLink(to: Endpoint(node: setup.first.id, socket: "value"))?.from.socket == "out")
        #expect(document.definitions[doubler.id]?.graph.links.filter { $0.from.node == doubler.input.id }.map(\.from.socket) == ["x", "x"])
        await document.waitForEvaluation()
        #expect(document.results[setup.first.id]?.outputs?["value"]?.numbers == [6])
        #expect(document.results[setup.second.id]?.outputs?["value"]?.numbers == [8])
        document.undo()
        document.undo()
        #expect(document.content == before)
        #expect(throws: GraphError.invalidValue("That socket no longer exists.")) {
            try GroupCommands.renameSocket(doubler.id, side: .input, from: "nope", to: "x", in: document.content)
        }
    }

    @Test func socketsReorder() throws {
        let setup = Setup(doubler)
        let (command, _) = try GroupCommands.addSocket(doubler.id, side: .input, name: "extra", type: .number, in: setup.document.content)
        try setup.document.perform(command)
        try setup.document.perform(try GroupCommands.moveSocket(doubler.id, side: .input, from: 1, to: 0, in: setup.document.content))
        #expect(setup.document.definitions[doubler.id]?.inputs.map(\.name) == ["extra", "value"])
        #expect(throws: GraphError.invalidValue("That socket no longer exists.")) {
            try GroupCommands.moveSocket(doubler.id, side: .input, from: 0, to: 5, in: setup.document.content)
        }
    }

    @Test func aWiredSocketCantBeRemoved() throws {
        let setup = Setup(doubler)
        #expect(throws: GraphError.invalidValue("“value” is wired on “Doubler”. Unwire it first.")) {
            try GroupCommands.removeSocket(doubler.id, side: .input, name: "value", in: setup.document.content)
        }
        #expect(throws: GraphError.invalidValue("“result” is wired on “Doubler”. Unwire it first.")) {
            try GroupCommands.removeSocket(doubler.id, side: .output, name: "result", in: setup.document.content)
        }
    }

    @Test func removingASocketDropsItsWiresInsideAndItsValues() async throws {
        let setup = Setup(doubler)
        let document = setup.document
        try document.perform(.disconnect(link(setup.constant, "value", setup.wired, "value")))
        try document.perform(try GroupCommands.removeSocket(doubler.id, side: .input, name: "value", in: document.content))
        #expect(document.definitions[doubler.id]?.inputs.isEmpty == true)
        #expect(document.definitions[doubler.id]?.graph.links == [link(doubler.add, "sum", doubler.output, "result")])
        #expect(document.graph.nodes[setup.typed.id]?.inputValues["value"] == nil)
        await document.waitForEvaluation()
        #expect(document.results[setup.second.id]?.outputs?["value"]?.numbers == [0], "Add's own defaults now")
    }

    @Test func onlyAnUnusedDefinitionIsDeleted() throws {
        let setup = Setup(doubler)
        #expect(throws: GraphError.invalidValue("“Doubler” is still in use. Delete its group nodes first.")) {
            try GroupCommands.deleteDefinition(doubler.id, in: setup.document.content)
        }
        let unused = Doubler(name: "Unused")
        try setup.document.perform(.addDefinition(unused.definition))
        try setup.document.perform(try GroupCommands.deleteDefinition(unused.id, in: setup.document.content))
        #expect(setup.document.definitions[unused.id] == nil)
        setup.document.undo()
        #expect(setup.document.definitions[unused.id] == unused.definition)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning' | head`

Expected: error: type 'GroupCommands' has no member 'rename' (and the others).

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorGraph/Groups/GroupCommands+Interface.swift`:

```swift
import CreatorKernel

/// Definition edits (groups spec §5): rename, accent, sockets, delete. Each builds one command; `GraphContent.apply`
/// refuses an empty or taken name and repeated or reserved socket names.
extension GroupCommands {
    static let missingSocket = GraphError.invalidValue("That socket no longer exists.")

    /// Renames definition `id`, and each of its group nodes still named after it.
    public static func rename(_ id: GroupID, to name: String, in content: GraphContent) throws(GraphError) -> GraphCommand {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        var interface = definition.interface
        interface.name = name
        let renames = GroupDependencies.instances(of: id, in: content).filter { $0.node.name == definition.name }
            .map { GraphCommand.rename($0.node.id, name).at($0.path) }
        return .batch([.setInterface(id, interface)] + renames)
    }

    public static func setAccent(_ id: GroupID, _ accent: AccentRole, in content: GraphContent) throws(GraphError) -> GraphCommand {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        var interface = definition.interface
        interface.accent = accent
        return .setInterface(id, interface)
    }

    /// Adds a socket named `name` (made unique on its side) of `type`; returns the command and the name it got.
    public static func addSocket(_ id: GroupID, side: GroupSocketSide, name: SocketName, type: SocketType,
                                 in content: GraphContent) throws(GraphError) -> (command: GraphCommand, name: SocketName) {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        var interface = definition.interface
        let unique = GroupNaming.uniqueSocketName(name, among: (side == .input ? interface.inputs : interface.outputs).map(\.name))
        if side == .input { interface.inputs.append(SocketSpec(unique, type)) } else { interface.outputs.append(SocketSpec(unique, type)) }
        return (.setInterface(id, interface), unique)
    }

    /// Moves the socket at `from` to `to` on its side; wires follow it by name.
    public static func moveSocket(_ id: GroupID, side: GroupSocketSide, from: Int, to: Int,
                                  in content: GraphContent) throws(GraphError) -> GraphCommand {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        var interface = definition.interface
        var sockets = side == .input ? interface.inputs : interface.outputs
        guard sockets.indices.contains(from), sockets.indices.contains(to) else { throw missingSocket }
        sockets.insert(sockets.remove(at: from), at: to)
        if side == .input { interface.inputs = sockets } else { interface.outputs = sockets }
        return .setInterface(id, interface)
    }

    /// Renames socket `old` to `new` everywhere: on the definition, on Group Input's or Group Output's wires inside,
    /// and on every group node's wires and typed value.
    public static func renameSocket(_ id: GroupID, side: GroupSocketSide, from old: SocketName, to new: SocketName,
                                    in content: GraphContent) throws(GraphError) -> GraphCommand {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        var interface = definition.interface
        let sockets = side == .input ? interface.inputs : interface.outputs
        guard let index = sockets.firstIndex(where: { $0.name == old }) else { throw missingSocket }
        guard new != old else { return .batch([]) }
        if side == .input { interface.inputs[index].name = new } else { interface.outputs[index].name = new }
        var commands: [GraphCommand] = [.setInterface(id, interface)]
        let boundary = side == .input ? definition.inputNode : definition.outputNode
        if let boundary {
            commands.append(rewire(definition.graph, node: boundary.id, from: old, to: new, outgoing: side == .input)
                .at(.definition(id)))
        }
        for instance in GroupDependencies.instances(of: id, in: content) {
            guard let graph = content.graph(at: instance.path) else { continue }
            var here = [rewire(graph, node: instance.node.id, from: old, to: new, outgoing: side == .output)]
            if side == .input, let value = instance.node.inputValues[old] {
                here += [.setInput(instance.node.id, old, nil), .setInput(instance.node.id, new, value)]
            }
            commands.append(GraphCommand.batch(here).at(instance.path))
        }
        return .batch(commands)
    }

    /// Removes socket `name`, its wires inside and its typed values on group nodes. Refused while a group node has it
    /// wired, naming that node.
    public static func removeSocket(_ id: GroupID, side: GroupSocketSide, name: SocketName,
                                    in content: GraphContent) throws(GraphError) -> GraphCommand {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        var interface = definition.interface
        guard (side == .input ? interface.inputs : interface.outputs).contains(where: { $0.name == name }) else {
            throw missingSocket
        }
        let instances = GroupDependencies.instances(of: id, in: content)
        for instance in instances {
            let socket = Endpoint(node: instance.node.id, socket: name)
            let links = content.graph(at: instance.path)?.links ?? []
            if links.contains(where: { side == .input ? $0.to == socket : $0.from == socket }) {
                throw .invalidValue("“\(name)” is wired on “\(instance.node.name)”. Unwire it first.")
            }
        }
        if side == .input { interface.inputs.removeAll { $0.name == name } } else { interface.outputs.removeAll { $0.name == name } }
        var commands: [GraphCommand] = [.setInterface(id, interface)]
        if let boundary = side == .input ? definition.inputNode : definition.outputNode {
            let socket = Endpoint(node: boundary.id, socket: name)
            let wires = definition.graph.links.filter { side == .input ? $0.from == socket : $0.to == socket }
            commands += wires.map { GraphCommand.disconnect($0).at(.definition(id)) }
        }
        for instance in instances where side == .input && instance.node.inputValues[name] != nil {
            commands.append(GraphCommand.setInput(instance.node.id, name, nil).at(instance.path))
        }
        return .batch(commands)
    }

    /// Delete: removes definition `id`, refused while a group node uses it.
    public static func deleteDefinition(_ id: GroupID, in content: GraphContent) throws(GraphError) -> GraphCommand {
        guard let definition = content.definitions[id] else { throw GroupRefusal.missing }
        guard GroupDependencies.instances(of: id, in: content).isEmpty else { throw GroupRefusal.inUse(definition.name) }
        return .removeDefinition(id)
    }

    /// Moves the wires on socket `old` of `node` to socket `new`: those leaving it (`outgoing`) or the one entering.
    private static func rewire(_ graph: Graph, node: NodeID, from old: SocketName, to new: SocketName,
                               outgoing: Bool) -> GraphCommand {
        let socket = Endpoint(node: node, socket: old), renamed = Endpoint(node: node, socket: new)
        let moving = graph.links.filter { outgoing ? $0.from == socket : $0.to == socket }
        guard !moving.isEmpty else { return .batch([]) }
        let moved = moving.map { outgoing ? Link(from: renamed, to: $0.to) : Link(from: $0.from, to: renamed) }
        return .batch(moving.map { .disconnect($0) } + [.restoreLinks(moved)])
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning'` (expect no output: no error, no new warning), then `swift test --skip-build --filter 'GroupInterfaceTests'`

Expected: `Test run with 8 tests in 1 suite passed`.

- [ ] **Step 5: Verify the whole package**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-test.log`.

Expected: exit code 0; `grep -c 'recorded an issue' /tmp/groups-test.log` and `grep -c 'failed after' /tmp/groups-test.log` print 0; `grep -c 'Test run with' /tmp/groups-test.log` prints 11; the counts on those lines add up to **1466** (master + 76).

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorGraph/Groups/GroupCommands+Interface.swift' 'Tests/CreatorGraphTests/Groups/GroupInterfaceTests.swift'
git commit -m "feat(graph): definition edits — rename, accent, sockets, delete"
```

---

### Task 10: ⌘G and ⇧⌘G in the graph panel

Decision: the `EditorModel` actions and their keys belong to C1 because they are trivial on the top level: `groupSelection()` and `ungroupSelection()` perform the `GroupEdit` and select its nodes, refusing with the command's message; ⌘G maps to `.group`, ⇧⌘G to `.ungroup` (`GraphKeyBindings`), and with nothing selected the key goes on. C2 changes `.root` to the level shown.

**Files:**
- Modify: `Sources/CreatorEditor/GraphKeyCommand.swift`
- Modify: `Sources/CreatorEditor/GraphKeyBindings.swift`
- Modify: `Sources/CreatorEditor/EditorModel+Commands.swift`
- Create: `Sources/CreatorEditor/EditorModel+Groups.swift`
- Test: `Tests/CreatorEditorTests/GroupKeyTests.swift`

**Interfaces:**
- Consumes: Task 7: `GroupCommands.group`, `GroupEdit`. Task 8: `GroupCommands.ungroup`. Task 6: `document.content`, `document.registry`.
- Produces:
  - `GraphKeyCommand.group`, `.ungroup`; `GraphKeyBindings`: ⌘G → `.group`, ⇧⌘G → `.ungroup`.
  - `EditorModel.groupSelection()`, `EditorModel.ungroupSelection()` (public); `performGroupKey(_:) -> Bool` (internal).

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorEditorTests/GroupKeyTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorEditor

/// ⌘G groups the selection and ⇧⌘G ungroups a group node (groups spec §5), on the top level until C2.
@MainActor
struct GroupKeyTests {
    func key(_ characters: String, _ modifiers: Modifiers) -> KeyEvent {
        KeyEvent(charactersIgnoringModifiers: characters, characters: characters, modifiers: modifiers, timestamp: 0)
    }

    let number = testNode(NumberTestNode.self, id: 1, at: Vector2(0, 0), registry: editorTestRegistry)
    let rectangle = testNode(RectangleTestNode.self, id: 2, at: Vector2(200, 0), registry: editorTestRegistry)
    let extrude = testNode(ExtrudeTestNode.self, id: 3, at: Vector2(400, 0), registry: editorTestRegistry)
    let output = testNode(OutputTestNode.self, id: 4, at: Vector2(600, 0), registry: editorTestRegistry)

    func editor() -> EditorModel {
        makeEditor([number, rectangle, extrude, output], [
            wire(number, "value", rectangle, "width"), wire(rectangle, "profile", extrude, "profile"),
            wire(extrude, "solid", output, "solid"),
        ])
    }

    @Test func commandGGroupsAndShiftCommandGUngroups() {
        #expect(GraphKeyBindings.command(for: key("g", .command), paletteOpen: false) == .group)
        #expect(GraphKeyBindings.command(for: key("G", [.command, .shift]), paletteOpen: false) == .ungroup)
        #expect(GraphKeyBindings.command(for: key("g", .command), paletteOpen: true) == nil)
    }

    @Test func groupingSelectsTheGroupNodeAndUngroupingSelectsWhatCameBack() throws {
        let editor = editor()
        editor.selection = [rectangle.id, extrude.id]
        #expect(editor.perform(.group))
        let node = try #require(editor.selection.first.flatMap { editor.graph.nodes[$0] })
        #expect(editor.selection.count == 1 && node.typeID == GroupNodes.groupTypeID)
        #expect(editor.graph.nodes.count == 3)
        #expect(editor.shape(of: node).inputs.map(\.name) == ["width"])
        #expect(editor.shape(of: node).outputs.map(\.name) == ["solid"])

        #expect(editor.perform(.ungroup))
        #expect(editor.selection.count == 2)
        #expect(editor.graph.nodes.count == 4)
        #expect(editor.document.definitions.isEmpty)
        editor.perform(.undo)
        editor.perform(.undo)
        #expect(Set(editor.graph.nodes.keys) == [number.id, rectangle.id, extrude.id, output.id])
    }

    @Test func duplicatingAGroupNodePlacesAnotherInstance() throws {
        let editor = editor()
        editor.selection = [rectangle.id, extrude.id]
        editor.groupSelection()
        let first = try #require(editor.selection.first)
        editor.perform(.duplicate)
        let second = try #require(editor.selection.first)
        #expect(second != first)
        #expect(editor.document.definitions.count == 1)
        #expect(editor.graph.nodes[second]?.inputValues[NodeSetting.group] == editor.graph.nodes[first]?.inputValues[NodeSetting.group])
        #expect(editor.shape(of: try #require(editor.graph.nodes[second])).outputs.map(\.name) == ["solid"])
    }

    @Test func refusedGroupingShowsWhy() {
        let editor = editor()
        #expect(!editor.perform(.group), "nothing selected: the key goes on")
        editor.selection = [extrude.id, output.id]
        editor.groupSelection()
        #expect(editor.refusal?.message == "An Output node can't go in a group.")
        #expect(editor.document.definitions.isEmpty)
        editor.selection = [number.id]
        editor.ungroupSelection()
        #expect(editor.refusal?.message == "Select one group node to ungroup.")
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning' | head`

Expected: error: type 'GraphKeyCommand?' has no member 'group' (and 'ungroup').

- [ ] **Step 3: Implement**

**Modify** `Sources/CreatorEditor/GraphKeyCommand.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorEditor/GraphKeyCommand.swift b/Sources/CreatorEditor/GraphKeyCommand.swift
index bddf1c7..36e5281 100644
--- a/Sources/CreatorEditor/GraphKeyCommand.swift
+++ b/Sources/CreatorEditor/GraphKeyCommand.swift
@@ -9,6 +9,10 @@ public enum GraphKeyCommand: Equatable, Sendable {
     case copy
     case paste
     case duplicate
+    /// ⌘G: groups the selection (groups spec §5).
+    case group
+    /// ⇧⌘G: ungroups the selected group node.
+    case ungroup
     case zoomIn
     case zoomOut
     case undo
```

**Modify** `Sources/CreatorEditor/GraphKeyBindings.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorEditor/GraphKeyBindings.swift b/Sources/CreatorEditor/GraphKeyBindings.swift
index 9154ecf..140e265 100644
--- a/Sources/CreatorEditor/GraphKeyBindings.swift
+++ b/Sources/CreatorEditor/GraphKeyBindings.swift
@@ -28,12 +28,13 @@ public enum GraphKeyBindings {
         }
     }
 
-    /// ⌘ chords; `character` is already lowercased, and ⇧ turns ⌘Z into redo.
+    /// ⌘ chords; `character` is already lowercased, and ⇧ turns ⌘Z into redo and ⌘G into ungroup.
     static func commandChord(for character: String, shifted: Bool) -> GraphKeyCommand? {
         switch character {
         case "c": .copy
         case "v": .paste
         case "d": .duplicate
+        case "g": shifted ? .ungroup : .group
         case "z": shifted ? .redo : .undo
         default: nil
         }
```

**Modify** `Sources/CreatorEditor/EditorModel+Commands.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorEditor/EditorModel+Commands.swift b/Sources/CreatorEditor/EditorModel+Commands.swift
index 5e7921f..84eea5d 100644
--- a/Sources/CreatorEditor/EditorModel+Commands.swift
+++ b/Sources/CreatorEditor/EditorModel+Commands.swift
@@ -11,6 +11,8 @@ extension EditorModel {
         case .deleteSelection:
             guard !selection.isEmpty else { return false }
             deleteSelection()
+        case .group, .ungroup:
+            return performGroupKey(command)
         case .copy, .paste, .duplicate, .zoomIn, .zoomOut, .undo, .redo:
             performEdit(command)
         case .cancel, .paletteUp, .paletteDown, .paletteConfirm:
```

**Create** `Sources/CreatorEditor/EditorModel+Groups.swift`:

```swift
import CreatorGraph

extension EditorModel {
    /// ⌘G: groups the selected nodes into a new definition and selects its group node, as one undo step (groups
    /// spec §5). The panel shows only the top level until C2 adds entering groups, so it groups there. A refused
    /// group changes nothing and shows its message.
    public func groupSelection() {
        do {
            let edit = try GroupCommands.group(selection, in: .root, of: document.content, registry: registry)
            try document.perform(edit.command)
            selection = edit.selection
        } catch {
            refuse(error.message, node: nil)
        }
    }

    /// ⌘G and ⇧⌘G. Returns false with nothing selected, so the key can go on.
    func performGroupKey(_ command: GraphKeyCommand) -> Bool {
        guard !selection.isEmpty else { return false }
        if command == .ungroup { ungroupSelection() } else { groupSelection() }
        return true
    }

    /// ⇧⌘G: ungroups the one selected group node and selects the nodes it spliced back, as one undo step.
    public func ungroupSelection() {
        guard selection.count == 1, let id = selection.first else {
            refuse("Select one group node to ungroup.", node: nil)
            return
        }
        do {
            let edit = try GroupCommands.ungroup(id, in: .root, of: document.content, registry: registry)
            try document.perform(edit.command)
            selection = edit.selection
        } catch {
            refuse(error.message, node: id)
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning'` (expect no output: no error, no new warning), then `swift test --skip-build --filter 'GroupKeyTests|KeyCommandTests'`

Expected: `Test run with 11 tests in 2 suites passed`.

- [ ] **Step 5: Verify the whole package**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-test.log`.

Expected: exit code 0; `grep -c 'recorded an issue' /tmp/groups-test.log` and `grep -c 'failed after' /tmp/groups-test.log` print 0; `grep -c 'Test run with' /tmp/groups-test.log` prints 11; the counts on those lines add up to **1470** (master + 80).

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorEditor/GraphKeyCommand.swift' 'Sources/CreatorEditor/GraphKeyBindings.swift' 'Sources/CreatorEditor/EditorModel+Commands.swift' 'Sources/CreatorEditor/EditorModel+Groups.swift' 'Tests/CreatorEditorTests/GroupKeyTests.swift'
git commit -m "feat(editor): ⌘G groups the selection, ⇧⌘G ungroups"
```

---

### Task 11: On OCCT: the grouped bracket and naming stability

Spec §9's evaluation-equality test (the §7.2 bracket with its rib, the L-flange, grouped by `GroupCommands.group` has the same union and fillet: volume, faces, edges, bounds; the fillet rule still finds four edges) and §5's naming-stability tests: two instances of a "Rib" definition unioned with a plate, a fillet picked on each rib's top; editing the definition (rib height 10 → 14) keeps both picks (no warning, same keys, also after save and reopen); Make Unique on the right rib, then editing the copy (18), leaves the left pick untouched, and the right pick, renamed by Make Unique to the copy's IDs, still holds. Two more pin picks across Group on OCCT: the bracket with its chamfer picked, grouped at the flange and grouped at the picked plate itself, keeps its seven chamfer edges with nothing warning; and Rectangle, Extrude, Edges by Tag (picked) and Fillet grouped fillet the same in two instances of the group. These tests pin behaviour Tasks 1–8 built, so they pass when first run; if one fails, debug the evaluator or the commands (superpowers:systematic-debugging), not the test.

**Files:**
- Test: `Tests/CreatorNodesTests/BracketAcceptanceTests+Groups.swift`
- Test: `Tests/CreatorNodesTests/GroupNamingStabilityTests.swift`

**Interfaces:**
- Consumes: Tasks 5–8: `DocumentModel` with definitions, `perform(_:at:)`, `GroupCommands.group`/`makeUnique`, `NodeID.scoped`; `BracketAcceptanceTests.makeBracket()`, `edgeSet`, `isClose`, `volume` (existing).
- Produces: tests only.

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorNodesTests/BracketAcceptanceTests+Groups.swift`:

```swift
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorOCCT

extension BracketAcceptanceTests {
    /// The bracket with its chamfer's top-cap outline picked, as the viewport would.
    func pickedBracket(_ kernel: OCCTKernel) async throws -> (Bracket, Graph) {
        let bracket = Self.makeBracket()
        let document = DocumentModel(file: GraphFile(graph: bracket.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        let filleted = try #require(document.results[bracket.fillet.id]?.outputs?["solid"]?.solids?.first)
        try document.perform(.setInput(bracket.chamferEdges.id, NodeSetting.picks,
                                       .edgePicks(filleted.topology.picks(for: topCapOutline(filleted, plate: bracket.plate)))))
        return (bracket, document.graph)
    }

    /// Groups spec §9: the §7.2 bracket's rib, its L-flange (plane, Rectangle and Extrude), grouped with ⌘G's command
    /// evaluates to the same part: the union and the fillet have the same volume, faces and edges, the fillet's rule
    /// still finds its four edges, the picked chamfer its seven, and nothing warns.
    @Test func theBracketWithItsFlangeGroupedIsTheSamePart() async throws {
        let kernel = OCCTKernel()
        let (bracket, picked) = try await pickedBracket(kernel)
        let plain = DocumentModel(file: GraphFile(graph: picked), registry: BuiltInNodes.registry, kernel: kernel)
        let grouped = DocumentModel(file: GraphFile(graph: picked), registry: BuiltInNodes.registry, kernel: kernel)
        let edit = try GroupCommands.group([bracket.flangePlane.id, bracket.flangeProfile.id, bracket.flange.id], in: .root,
                                           of: grouped.content, registry: grouped.registry)
        try grouped.perform(edit.command)
        let definition = try #require(grouped.definitions.values.first)
        #expect(definition.inputs.map(\.name) == ["width"])
        #expect(definition.outputs == [SocketSpec("solid", .solid)])
        await plain.waitForEvaluation()
        await grouped.waitForEvaluation()

        let node = try #require(edit.selection.first)
        #expect(grouped.results[node]?.state.isSuccess == true)
        for id in [bracket.union.id, bracket.fillet.id] {
            let expected = try #require(plain.results[id]?.outputs?["solid"]?.solids?.first)
            let actual = try #require(grouped.results[id]?.outputs?["solid"]?.solids?.first)
            #expect(isClose(try await volume(actual, kernel), try await volume(expected, kernel)))
            #expect(actual.topology.faces.count == expected.topology.faces.count)
            #expect(actual.topology.edges.count == expected.topology.edges.count)
            #expect(isClose(actual.bounds.size, expected.bounds.size, tolerance: 1e-6))
        }
        #expect(try edgeSet(grouped, bracket.filletEdges).edges.count == 4)
        #expect(try edgeSet(grouped, bracket.chamferEdges).edges.count == 7)
        expectAllOK(plain, "plain")
        expectAllOK(grouped, "flange grouped")
    }

    /// Grouping the picked plate itself: its faces are made under a scoped ID inside the group, and Group renames the
    /// chamfer's picks to it, so the chamfer still finds its seven edges and nothing warns.
    @Test func groupingThePickedPlateKeepsTheChamfer() async throws {
        let kernel = OCCTKernel()
        let (bracket, picked) = try await pickedBracket(kernel)
        let document = DocumentModel(file: GraphFile(graph: picked), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        let chamferKeys = keys(try edgeSet(document, bracket.chamferEdges)).count
        let edit = try GroupCommands.group([bracket.plate.id, bracket.cut.id], in: .root, of: document.content,
                                           registry: document.registry)
        try document.perform(edit.command)
        await document.waitForEvaluation()
        let node = try #require(edit.selection.first)
        #expect(document.graph.nodes[bracket.chamferEdges.id] != picked.nodes[bracket.chamferEdges.id], "the picks were renamed")
        #expect(try edgeSet(document, bracket.chamferEdges).edges.count == 7)
        #expect(keys(try edgeSet(document, bracket.chamferEdges)).count == chamferKeys)
        #expect(keys(try edgeSet(document, bracket.chamferEdges)).allSatisfy { key in
            key.first.union(key.second).contains { $0.node == NodeID.scoped([node, bracket.plate.id]) }
        })
        expectAllOK(document, "plate grouped")
    }
}
```

**Create** `Tests/CreatorNodesTests/GroupNamingStabilityTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorOCCT

/// Groups spec §5's naming-stability tests, on OCCT: a "Rib" definition placed twice on a plate, a fillet picked on
/// each rib's top. Editing the definition keeps both picks; Make Unique on one, then editing it, leaves the other's
/// pick untouched and keeps its own. And a fillet picked before grouping fillets every instance of the group.
@MainActor
struct GroupNamingStabilityTests {
    /// The part: a 60 × 40 × 6 plate, two ribs (4 × 30, 10 tall) at x = ∓15 unioned onto it, then a fillet on the
    /// left rib's top edges (picked by Edges by Tag) and one on the right rib's.
    struct Part {
        var file: GraphFile
        let rib: GroupID
        /// The Extrude inside the definition: its distance is the rib's height.
        let ribExtrude: NodeID
        let left: Node
        let right: Node
        let union: Node
        let leftEdges: Node
        let leftFillet: Node
        let rightEdges: Node
        let rightFillet: Node
    }

    static func makePart() -> Part {
        let registry = BuiltInNodes.registry
        var rib = GroupDefinition.make(name: "Rib", inputs: [SocketSpec("base", .plane)], outputs: [SocketSpec("solid", .solid)],
                                       registry: registry)
        var profile = registry.makeNode(RectangleNode.typeID)
        profile.inputValues.merge(["width": .number(4), "height": .number(30)]) { _, given in given }
        var extrude = registry.makeNode(ExtrudeNode.typeID)
        extrude.inputValues["distance"] = .number(10)
        rib.graph.nodes[profile.id] = profile
        rib.graph.nodes[extrude.id] = extrude
        if let input = rib.inputNode, let output = rib.outputNode {
            rib.graph.links = [wire(input, "base", profile, "plane"), wire(profile, "profile", extrude, "profile"),
                               wire(extrude, "solid", output, "solid"), ]
        }

        var nodes: [Node] = []
        func add(_ typeID: String, _ values: [SocketName: ConstantValue] = [:]) -> Node {
            var node = registry.makeNode(typeID)
            node.inputValues.merge(values) { _, given in given }
            nodes.append(node)
            return node
        }
        func place(at x: Double) -> Node {
            var node = registry.withGroups([rib.id: rib]).makeGroupNode(GroupNodes.groupTypeID, for: rib.id)
            node.inputValues["base"] = .plane(.through(Vector3(x, 0, 6)))
            nodes.append(node)
            return node
        }
        let plateProfile = add(RectangleNode.typeID, ["width": .number(60), "height": .number(40)])
        let plate = add(ExtrudeNode.typeID, ["distance": .number(6)])
        let left = place(at: -15), right = place(at: 15)
        let withLeft = add(BooleanNode.typeID), union = add(BooleanNode.typeID)
        let leftEdges = add(EdgesByTagNode.typeID), leftFillet = add(FilletNode.typeID, ["radius": .number(1)])
        let rightEdges = add(EdgesByTagNode.typeID), rightFillet = add(FilletNode.typeID, ["radius": .number(1)])
        let output = add(OutputNode.typeID)
        let links = [
            wire(plateProfile, "profile", plate, "profile"),
            wire(plate, "solid", withLeft, "target"), wire(left, "solid", withLeft, "tools"),
            wire(withLeft, "solid", union, "target"), wire(right, "solid", union, "tools"),
            wire(union, "solid", leftEdges, "solid"), wire(leftEdges, "edges", leftFillet, "edges"),
            wire(leftFillet, "solid", rightEdges, "solid"), wire(rightEdges, "edges", rightFillet, "edges"),
            wire(rightFillet, "solid", output, "solid"),
        ]
        let graph = Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }), links: links)
        return Part(file: GraphFile(graph: graph, definitions: [rib.id: rib]), rib: rib.id, ribExtrude: extrude.id,
                    left: left, right: right, union: union, leftEdges: leftEdges, leftFillet: leftFillet,
                    rightEdges: rightEdges, rightFillet: rightFillet)
    }

    static func wire(_ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName) -> Link {
        Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input))
    }

    /// The edges between the top cap and the sides of the faces made under `node`: a rib's top outline.
    func topOutline(_ solid: Solid, made node: NodeID) -> [EdgeID] {
        let top = TopoTag(node: node, item: 0, role: .endCap)
        func isSide(_ face: FaceInfo) -> Bool {
            face.tags.contains { tag in
                guard tag.node == node, case .side = tag.role else { return false }
                return true
            }
        }
        return solid.topology.edges.filter { edge in
            guard !edge.isSeam, edge.faces.count == 2,
                  let a = solid.topology.face(edge.faces[0]), let b = solid.topology.face(edge.faces[1]) else { return false }
            return (a.tags.contains(top) && isSide(b)) || (b.tags.contains(top) && isSide(a))
        }.map(\.id)
    }

    func solid(_ document: DocumentModel, _ node: Node) throws -> Solid {
        try #require(document.results[node.id]?.outputs?["solid"]?.solids?.first,
                     "no solid on \(node.name): \(String(describing: document.results[node.id]?.state))")
    }

    func edgeSet(_ document: DocumentModel, _ node: Node) throws -> EdgeSet {
        try #require(document.results[node.id]?.outputs?["edges"]?.edgeSets?.first)
    }

    func keys(_ set: EdgeSet) -> Set<EdgeKey> {
        Set(set.edges.compactMap { id in set.solid.topology.edge(id).flatMap(set.solid.topology.key(of:)) })
    }

    func isOK(_ document: DocumentModel, _ node: Node) -> Bool {
        if case .ok? = document.results[node.id]?.state { true } else { false }
    }

    /// Opens the part and picks each rib's top outline, as the viewport would.
    func pickedPart() async throws -> (Part, DocumentModel) {
        let part = Self.makePart()
        let document = DocumentModel(file: part.file, registry: BuiltInNodes.registry, kernel: OCCTKernel())
        await document.waitForEvaluation()
        let union = try solid(document, part.union)
        let leftTop = topOutline(union, made: NodeID.scoped([part.left.id, part.ribExtrude]))
        #expect(leftTop.count == 4)
        try document.perform(.setInput(part.leftEdges.id, NodeSetting.picks, .edgePicks(union.topology.picks(for: leftTop))))
        await document.waitForEvaluation()
        let filleted = try solid(document, part.leftFillet)
        let rightTop = topOutline(filleted, made: NodeID.scoped([part.right.id, part.ribExtrude]))
        #expect(rightTop.count == 4)
        try document.perform(.setInput(part.rightEdges.id, NodeSetting.picks,
                                       .edgePicks(filleted.topology.picks(for: rightTop))))
        await document.waitForEvaluation()
        return (part, document)
    }

    @Test func theTwoRibsNameTheirFacesApart() async throws {
        let part = Self.makePart()
        let document = DocumentModel(file: part.file, registry: BuiltInNodes.registry, kernel: OCCTKernel())
        await document.waitForEvaluation()
        let nodes = Set(try solid(document, part.union).topology.faces.flatMap(\.tags).map(\.node))
        #expect(nodes.contains(NodeID.scoped([part.left.id, part.ribExtrude])))
        #expect(nodes.contains(NodeID.scoped([part.right.id, part.ribExtrude])))
        #expect(!nodes.contains(part.ribExtrude))
    }

    @Test func editingTheDefinitionKeepsBothPicks() async throws {
        let (part, document) = try await pickedPart()
        for node in [part.leftEdges, part.rightEdges, part.leftFillet, part.rightFillet] {
            #expect(isOK(document, node), "\(node.name): \(String(describing: document.results[node.id]?.state))")
        }
        let leftKeys = keys(try edgeSet(document, part.leftEdges)), rightKeys = keys(try edgeSet(document, part.rightEdges))

        try document.perform(.setInput(part.ribExtrude, "distance", .number(14)), at: .definition(part.rib))
        await document.waitForEvaluation()
        #expect(isClose(try solid(document, part.union).bounds.max.z, 20))
        for node in [part.leftEdges, part.rightEdges, part.leftFillet, part.rightFillet] {
            #expect(isOK(document, node), "\(node.name): \(String(describing: document.results[node.id]?.state))")
        }
        #expect(try edgeSet(document, part.leftEdges).edges.count == 4)
        #expect(try edgeSet(document, part.rightEdges).edges.count == 4)
        #expect(keys(try edgeSet(document, part.leftEdges)) == leftKeys)
        #expect(keys(try edgeSet(document, part.rightEdges)) == rightKeys)

        // Scoped IDs are derived, never saved: a reopened file names the same faces.
        let reopened = try DocumentModel(data: try document.fileData(), registry: BuiltInNodes.registry, kernel: OCCTKernel())
        await reopened.waitForEvaluation()
        #expect(isOK(reopened, part.rightFillet))
        #expect(keys(try edgeSet(reopened, part.leftEdges)) == leftKeys)
        #expect(keys(try edgeSet(reopened, part.rightEdges)) == rightKeys)
    }

    @Test func makeUniqueThenEditingItLeavesTheOtherPickAlone() async throws {
        let (part, document) = try await pickedPart()
        let leftKeys = keys(try edgeSet(document, part.leftEdges))

        let edit = try GroupCommands.makeUnique(part.right.id, in: .root, of: document.content, registry: document.registry)
        try document.perform(edit.command)
        let copy = try #require(document.definitions.values.first { $0.name == "Rib 2" })
        let copyExtrude = try #require(copy.graph.nodes.values.first { $0.typeID == ExtrudeNode.typeID })
        try document.perform(.setInput(copyExtrude.id, "distance", .number(18)), at: .definition(copy.id))
        await document.waitForEvaluation()

        #expect(isClose(try solid(document, part.union).bounds.max.z, 24))
        #expect(isOK(document, part.leftEdges) && isOK(document, part.leftFillet))
        #expect(try edgeSet(document, part.leftEdges).edges.count == 4)
        #expect(keys(try edgeSet(document, part.leftEdges)) == leftKeys)
        // The copy's nodes have new IDs, and Make Unique renamed the right rib's pick to them: it still holds.
        #expect(isOK(document, part.rightEdges) && isOK(document, part.rightFillet),
                "\(String(describing: document.results[part.rightEdges.id]?.state))")
        #expect(try edgeSet(document, part.rightEdges).edges.count == 4)
    }

    @Test func aFilletPickedBeforeGroupingFilletsEveryInstance() async throws {
        let registry = BuiltInNodes.registry, kernel = OCCTKernel()
        var nodes: [Node] = []
        func add(_ typeID: String, _ values: [SocketName: ConstantValue] = [:]) -> Node {
            var node = registry.makeNode(typeID)
            node.inputValues.merge(values) { _, given in given }
            nodes.append(node)
            return node
        }
        let profile = add(RectangleNode.typeID, ["width": .number(20), "height": .number(10)])
        let extrude = add(ExtrudeNode.typeID, ["distance": .number(5)])
        let edges = add(EdgesByTagNode.typeID), fillet = add(FilletNode.typeID, ["radius": .number(1)])
        let output = add(OutputNode.typeID)
        let graph = Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }), links: [
            Self.wire(profile, "profile", extrude, "profile"), Self.wire(extrude, "solid", edges, "solid"),
            Self.wire(edges, "edges", fillet, "edges"), Self.wire(fillet, "solid", output, "solid"),
        ])
        let document = DocumentModel(file: GraphFile(graph: graph), registry: registry, kernel: kernel)
        await document.waitForEvaluation()
        let box = try solid(document, extrude)
        let top = topOutline(box, made: extrude.id)
        #expect(top.count == 4)
        try document.perform(.setInput(edges.id, NodeSetting.picks, .edgePicks(box.topology.picks(for: top))))
        await document.waitForEvaluation()
        let plain = try solid(document, fillet)

        let edit = try GroupCommands.group([profile.id, extrude.id, edges.id, fillet.id], in: .root, of: document.content,
                                           registry: document.registry)
        try document.perform(edit.command)
        let definition = try #require(document.definitions.values.first)
        let first = try #require(edit.selection.first)
        let second = document.registry.makeGroupNode(GroupNodes.groupTypeID, for: definition.id)
        var content = document.content
        content.graph.nodes[second.id] = second
        let report = try await Evaluator(registry: registry, kernel: kernel)
            .evaluate(content.graph, definitions: content.definitions, demand: [first, second.id])
        for node in [first, second.id] {
            guard case .ok? = report.results[node]?.state else {
                Issue.record("expected the group to fillet without a warning, got \(String(describing: report.results[node]?.state))")
                continue
            }
            let filleted = try #require(report.results[node]?.outputs?["solid"]?.solids?.first)
            #expect(isClose(try await volume(filleted, kernel), try await volume(plain, kernel)))
            #expect(filleted.topology.faces.count == plain.topology.faces.count)
            #expect(report.innerResults[[node, edges.id]]?.outputs?["edges"]?.edgeSets?.first?.edges.count == 4)
        }
    }
}
```

- [ ] **Step 2: Run them**

Run: `swift test --filter 'GroupNamingStabilityTests|BracketAcceptanceTests'`

Expected: `Test run with 9 tests in 2 suites passed` straight away: these tests pin behaviour Tasks 1–8 built, so this task has no red step.

- [ ] **Step 3: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning'` (expect no output: no error, no new warning), then `swift test --skip-build --filter 'GroupNamingStabilityTests|BracketAcceptanceTests'`

Expected: `Test run with 9 tests in 2 suites passed`.

- [ ] **Step 4: Verify the whole package**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-test.log`.

Expected: exit code 0; `grep -c 'recorded an issue' /tmp/groups-test.log` and `grep -c 'failed after' /tmp/groups-test.log` print 0; `grep -c 'Test run with' /tmp/groups-test.log` prints 11; the counts on those lines add up to **1476** (master + 86).

- [ ] **Step 5: Commit**

```bash
git add 'Tests/CreatorNodesTests/BracketAcceptanceTests+Groups.swift' 'Tests/CreatorNodesTests/GroupNamingStabilityTests.swift'
git commit -m "test(nodes): grouped bracket equals the plain one; picks inside groups survive edits and Make Unique"
```

---

### Task 12: Show Producing Node on a face made inside a group

Faces made inside a group carry scoped IDs, which name no node in the graph, so the viewport's "Show Producing Node" did nothing for them and its title fell back to an ID. `GraphContent.topLevelNode(producing:)` maps an identity to its node or to the top-level group node whose inside made it; the app's `showProducingNode` and the viewport's `nodeName` use it.

**Files:**
- Create: `Sources/CreatorGraph/Groups/GraphContent+Producers.swift`
- Modify: `Sources/CreatorApp/AppModel+Viewport.swift`
- Test: `Tests/CreatorGraphTests/Groups/ProducingNodeTests.swift`
- Test: `Tests/CreatorAppTests/GroupProducingNodeTests.swift`

**Interfaces:**
- Consumes: Task 5: `GroupScopes.inner`, `NodeID.scoped`. Task 6: `DocumentModel.content`.
- Produces:
  - `GraphContent.topLevelNode(producing identity: NodeID) -> NodeID?`.
  - `AppModel.producingNode(_ id: NodeID) -> Node?` (internal).

- [ ] **Step 1: Write the failing tests**

**Create** `Tests/CreatorGraphTests/Groups/ProducingNodeTests.swift`:

```swift
import CreatorKernel
import Testing
@testable import CreatorGraph

/// Which top-level node made a face, when faces made inside groups carry scoped IDs (groups spec §5).
struct ProducingNodeTests {
    @Test func aScopedIDLeadsToItsTopLevelGroupNode() {
        let doubler = Doubler()
        let inner = instance(of: doubler.definition)
        let outer = define("Outer", outputs: [SocketSpec("result", .number)], nodes: [inner]) { _, output in
            [link(inner, "result", output, "result")]
        }
        let top = instance(of: outer), plain = makeNode(ConstantNode.self)
        let content = GraphContent(graph: graph([top, plain]), definitions: table([doubler.definition, outer]))
        #expect(content.topLevelNode(producing: plain.id) == plain.id)
        #expect(content.topLevelNode(producing: NodeID.scoped([top.id, inner.id, doubler.add.id])) == top.id)
        #expect(content.topLevelNode(producing: NodeID.scoped([top.id, inner.id])) == top.id)
        #expect(content.topLevelNode(producing: doubler.add.id) == nil)
    }
}
```

**Create** `Tests/CreatorAppTests/GroupProducingNodeTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// A face made inside a group is tagged with a scoped ID (groups spec §5); "Show Producing Node" shows its group node.
@MainActor
struct GroupProducingNodeTests {
    @Test func aFaceMadeInsideAGroupShowsItsGroupNode() async throws {
        let registry = BuiltInNodes.registry
        var rib = GroupDefinition.make(name: "Rib", outputs: [SocketSpec("solid", .solid)], registry: registry)
        let rectangle = registry.makeNode(RectangleNode.typeID), extrude = registry.makeNode(ExtrudeNode.typeID)
        rib.graph.nodes[rectangle.id] = rectangle
        rib.graph.nodes[extrude.id] = extrude
        if let output = rib.outputNode {
            rib.graph.links = [
                Link(from: Endpoint(node: rectangle.id, socket: "profile"), to: Endpoint(node: extrude.id, socket: "profile")),
                Link(from: Endpoint(node: extrude.id, socket: "solid"), to: Endpoint(node: output.id, socket: "solid")),
            ]
        }
        var node = registry.withGroups([rib.id: rib]).makeGroupNode(GroupNodes.groupTypeID, for: rib.id, at: Vector2(600, 400))
        node.isOutput = true
        let file = GraphFile(graph: Graph(nodes: [node.id: node]), definitions: [rib.id: rib], viewState: ViewState(dock: .hidden))
        let app = AppModel(kernel: FakeKernel(), file: file)
        await app.settle()

        let scoped = NodeID.scoped([node.id, extrude.id])
        guard case .solid(let solid)? = app.document.results[node.id]?.outputs?["solid"]?.items.first else {
            Issue.record("expected the group's solid")
            return
        }
        #expect(solid.topology.faces.allSatisfy { face in face.tags.allSatisfy { $0.node == scoped } })
        #expect(app.viewport.events.nodeName(scoped) == "Rib")
        app.showProducingNode(scoped)
        #expect(app.editor.selection == [node.id])
        #expect(app.editor.isPanelVisible)
        #expect(app.viewport.events.nodeName(NodeID()) == nil)
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning' | head`

Expected: error: value of type 'GraphContent' has no member 'topLevelNode'.

- [ ] **Step 3: Implement**

**Create** `Sources/CreatorGraph/Groups/GraphContent+Producers.swift`:

```swift
import CreatorKernel

extension GraphContent {
    /// The top-level node behind faces tagged with `identity`: that node, or the group node whose inside made them
    /// (they are tagged with a scoped ID, groups spec §5), or `nil` when no node is.
    public func topLevelNode(producing identity: NodeID) -> NodeID? {
        if graph.nodes[identity] != nil { return identity }
        return graph.nodes.values.sorted { $0.id < $1.id }.first { node in
            GroupScopes.inner(of: node, at: [], definitions: definitions).contains(identity)
        }?.id
    }
}
```

**Modify** `Sources/CreatorApp/AppModel+Viewport.swift` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/Sources/CreatorApp/AppModel+Viewport.swift b/Sources/CreatorApp/AppModel+Viewport.swift
index 16d65e1..6ad19e7 100644
--- a/Sources/CreatorApp/AppModel+Viewport.swift
+++ b/Sources/CreatorApp/AppModel+Viewport.swift
@@ -15,7 +15,7 @@ extension AppModel {
         viewport.events.selectEdgesOfFace = { face, picks, edges in events()?.selectEdgesOfFace(face, picks, edges) }
         viewport.events.showProducingNode = { events()?.showProducingNode($0) }
         viewport.events.handleChanged = { id, value, phase in events()?.handleChanged(id, value, phase) }
-        viewport.events.nodeName = { events()?.document.graph.nodes[$0]?.name }
+        viewport.events.nodeName = { id in events()?.producingNode(id)?.name }
         // The camera reaches the file only when it comes to rest, never per frame: writing `viewState` invalidates
         // the editor, which reads its dock and canvas transform from it (M4 carry-over, spec §7.3).
         viewport.events.cameraSettled = { events()?.document.viewState.camera = $0 }
@@ -57,12 +57,18 @@ extension AppModel {
         return HandleBuilder.number(stored)
     }
 
-    /// "Show Producing Node": selects the node and scrolls the graph to it, showing a hidden panel first.
+    /// "Show Producing Node": selects the node and scrolls the graph to it, showing a hidden panel first. A face made
+    /// inside a group names a scoped ID, so its group node on the top level is shown.
     func showProducingNode(_ id: NodeID) {
-        guard let node = document.graph.nodes[id] else { return }
+        guard let node = producingNode(id) else { return }
         if !editor.isPanelVisible { editor.toggleHidden() }
-        editor.selection = [id]
+        editor.selection = [node.id]
         let zoom = editor.transform.zoom
         editor.transform = CanvasTransform(offset: AppLayout.revealPoint - editor.displayOrigin(of: node) * zoom, zoom: zoom)
     }
+
+    /// The top-level node behind faces tagged with `id` (`GraphContent.topLevelNode(producing:)`).
+    func producingNode(_ id: NodeID) -> Node? {
+        document.content.topLevelNode(producing: id).flatMap { document.graph.nodes[$0] }
+    }
 }
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift build --build-tests 2>&1 | grep -E 'error|warning: ' | grep -v 'ld: warning'` (expect no output: no error, no new warning), then `swift test --skip-build --filter 'CreatorGraphTests.ProducingNodeTests|GroupProducingNodeTests|ViewportGlueTests'`

Expected: `Test run with 1 test in 1 suite passed`; `Test run with 9 tests in 2 suites passed`.

- [ ] **Step 5: Verify the whole package**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-test.log`.

Expected: exit code 0; `grep -c 'recorded an issue' /tmp/groups-test.log` and `grep -c 'failed after' /tmp/groups-test.log` print 0; `grep -c 'Test run with' /tmp/groups-test.log` prints 11; the counts on those lines add up to **1478** (master + 88).

- [ ] **Step 6: Commit**

```bash
git add 'Sources/CreatorGraph/Groups/GraphContent+Producers.swift' 'Sources/CreatorApp/AppModel+Viewport.swift' 'Tests/CreatorGraphTests/Groups/ProducingNodeTests.swift' 'Tests/CreatorAppTests/GroupProducingNodeTests.swift'
git commit -m "fix(app): Show Producing Node finds the group node behind a face made inside it"
```

---

### Task 13: Docs: CLAUDE.md, roadmap, spec errata

CLAUDE.md's project state, `CreatorGraph` bullet, `NodeSetting` list and file-format sentence; two roadmap rows (C1 done, C2 next) after row 8; and Errata (C1) at the end of the groups spec, recording this plan's departures (sockets through the registry, group types in `CreatorGraph`, optional Group Output inputs, picks named per definition level and renamed by Group, Ungroup and Make Unique (no notices), interfaces refused while a removed or retyped socket is wired, Ungroup removing the last definition, Make Unique and Rename naming group nodes, ⌘G on the top level until C2, the 4 → 5 bump).

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/roadmap.md`
- Modify: `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md`

**Interfaces:**
- Consumes: everything above (descriptions only).
- Produces: docs only.

- [ ] **Step 1: Edit the docs**

**Modify** `CLAUDE.md` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/CLAUDE.md b/CLAUDE.md
index 8ea329a..47ca1cc 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -11,6 +11,8 @@ M6 (app shell) code is done; its human checks (group M6) are pending.
 Editor polish (the floating add-node palette and the node library) code is done; its human checks (group EP) are pending.
 Packaging (`scripts/package-app.sh`, `docs/packaging.md`) is done; its human checks (group P) are pending.
 Themes (custom themes, `.mctheme` files, the theme editor) code is done; its human checks (group TH) are pending. Editing a colour in the app waits for MetalUI C10's `ColorPicker` (plan Task 11); until then colours change by import.
+Groups C1 (model and evaluation, `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` §4–§5) is done:
+⌘G/⇧⌘G work on the top level; entering a group, breadcrumbs and the group inspector are C2.
 
 Module boundaries (dependency order):
 - `CreatorGeometry`: value types (vectors, planes, profiles, bounds). Millimetres.
@@ -22,12 +24,29 @@ Module boundaries (dependency order):
   OCCT history, tessellation, STEP/STL export). **The only code that may touch OCCT.** Every C allocation has a
   `*_free`; no C++ exception crosses into Swift.
 - `CreatorGraph`: graph model, sockets, broadcasting, `Evaluator` (cached, cancellable), commands and undo,
-  `.mcgraph` files, `DocumentModel`. Depends on `CreatorSketch` for the `ConstantValue.sketch` setting. A node's inputs
-  are `NodeDefinition.inputs(for: node)` (default: the static `inputs`); the Evaluator and `connectionProblem` read
-  it, so per-node sockets (the Sketch node's exposed dimensions) wire and gather like declared ones.
+  `.mcgraph` files, `DocumentModel`. Depends on `CreatorSketch` for the `ConstantValue.sketch` setting. A node's sockets
+  are `NodeRegistry.inputs(for:)`/`outputs(for:)`: `NodeDefinition.inputs(for:)`/`outputs(for:)` of its type
+  (default: the static lists), or, for a group node, Group Input or Group Output, its definition's (the registry
+  carries the document's definitions: `DocumentModel.registry`, `withGroups(_:)`). Every reader (the Evaluator,
+  `connectionProblem`, the canvas, the inspector) asks the registry, so per-node sockets wire and gather like declared
+  ones.
+  - Groups (`Sources/CreatorGraph/Groups`): `GroupDefinition`s live in `GraphContent.definitions` beside the top-level
+    graph (`DocumentModel.content`); a group node is type `group` with `NodeSetting.group`, and every `NodeRegistry`
+    registers `group`, `groupInput` and `groupOutput` itself (`NodeRegistry.all`, the palette's list, leaves them out).
+    Edits go through `GraphContent.apply`: graph commands on the top level, `.inDefinition(id, …)` (or
+    `DocumentModel.perform(_:at:)`) inside a definition, plus `addDefinition`/`removeDefinition`/`setInterface`; it
+    refuses a group inside itself (`GroupDependencies`), an Output node in a group and a stray or missing Group
+    Input/Output, and (after the whole command) a socket removed or retyped while still wired. `GroupCommands`
+    builds Group, Ungroup, Make Unique and the definition edits as `GroupEdit`s (one undo step). The Evaluator runs
+    a group node's definition level by level (`Evaluator+Groups`): values pass through, inner nodes evaluate and
+    cache under `NodeID.scoped(instance path + id)`, so their tags differ per instance and stay put when the
+    definition is edited; inner messages read "Rib › Fillet: …". A pick stored inside a definition names faces as
+    if the definition were the top level (`GroupScopes.identity`), and `EvaluationScope.naming` reads it as each
+    instance's; Group, Ungroup and Make Unique rename every pick whose faces they move (`GroupScopes.renamingPicks`),
+    so no pick drifts. Dirty state compares `DocumentModel.content` (definitions too).
 - `CreatorNodes`: the 28 built-in node definitions (`BuiltInNodes.registry`: the slice's 26 plus Plane from Face and
   Sketch), UI-free: inspector sections and handles are data. Non-socket settings (`NodeSetting` in CreatorGraph:
-  parameter, picks, showHandle, sketch, face, and `projection(reference)` per projected edge) live in
+  parameter, picks, showHandle, sketch, face, groupID, and `projection(reference)` per projected edge) live in
   `Node.inputValues`; `NodeRegistry.makeNode` seeds `defaultSettings` and sets `isOutput` for `.output`-category nodes.
 - `CreatorStyle`: colour themes (spec §6.6, Dracula by default), the only place colour hex values are written.
   `ThemeColors` is a colour per role (never a hue); `ColorTheme` (not `Theme`: MetalUI exports one) has the built-ins
@@ -94,8 +113,8 @@ Rules: keep OCCT behind `Kernel`; MetalUI gaps are logged in `docs/metalui-gaps.
 never worked around here. Graph links are kept canonically sorted by destination; result caching is keyed by node identity.
 Edge/face IDs are OCCT map order. A circle edge's `direction` is its axis, so direction rules must also check `kind == .line`.
 All OCCT work runs under `OCCTKernel.serialized` (process-wide lock) because OCCT shapes share geometry across solids and meshing mutates it; never call the shim outside it (tests included).
-Edge picks (`EdgePick`) match by tag subsets per side, and a key that matches nothing is retried `EdgeKey.narrowed` (to the operand its edge runs along, so picks on faces a union merged survive the other operand changing); drift counts edges and runs (`EdgePick.runCount`, an optional key, so no format bump; a pick without one counts each recorded edge as a run) and warns only when both changed; selection rules never select seams. Segmented controls bind integer sockets (option index). File format is version 4 (2 added `.edgePicks`; 3 added `loop` on hole-wall side tags, written only when non-zero;
-4 added the `.sketch` and `.facePick` settings).
+Edge picks (`EdgePick`) match by tag subsets per side, and a key that matches nothing is retried `EdgeKey.narrowed` (to the operand its edge runs along, so picks on faces a union merged survive the other operand changing); drift counts edges and runs (`EdgePick.runCount`, an optional key, so no format bump; a pick without one counts each recorded edge as a run) and warns only when both changed; selection rules never select seams. Segmented controls bind integer sockets (option index). File format is version 5 (2 added `.edgePicks`; 3 added `loop` on hole-wall side tags, written only when non-zero;
+4 added the `.sketch` and `.facePick` settings; 5 added `definitions`, group definitions, optional on decode).
 A `Segment2D.arc` with `end < start` runs clockwise (a sketch region's notch); the shim builds it reversed and
 `length` is positive. Edges carry `EdgeInfo.curve` (`EdgeCurve`, lines and circles) for sketch projection; a
 `FacePick` names faces by tag subset like `EdgePick`. The Sketch node solves on every evaluation from the stored
```

**Modify** `docs/superpowers/roadmap.md` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/docs/superpowers/roadmap.md b/docs/superpowers/roadmap.md
index 88e9d50..a5d8236 100644
--- a/docs/superpowers/roadmap.md
+++ b/docs/superpowers/roadmap.md
@@ -29,6 +29,8 @@ Status key: ✅ done · 🔄 in progress · ⏳ ready to start · 🔒 blocked (
 | 6 | Constraint sketcher: Sketch node, 2D editor, pure-Swift constraint solver | 🔄 spec `2026-10-08-constraint-sketcher-design.md`; S3 ✅ merged; S1+S2 ✅ merged (CreatorSketch: solver, regions, commands); S4 ✅ merged 2026-10-09 (Sketch node, Plane from Face, projection, format 4; human check S4-1 pending); S5a (editor in the viewport: sketch mode, drawing, constraints, dimensions, live solve; plan `2026-10-09-sketcher-s5-editor.md`) ✅ code done, human checks S5 pending; S5b (Project, New sketch on face, double-click to edit, trim/fillet/mirror/pattern tools, inference glyphs and tangent/point-on inference, dimension labels in the view, region fill) ⏳ | Rules for S4 regions: holes sorted, loops counter-clockwise, deterministic start segment (spec §5) |
 | 7 | Patterns, fields, nested data trees, surface textures, lattices | 💬 | After the slice |
 | 8 | Variants and versions UI | 💬 | Graph parameters already model variants |
+| — | Groups: model and evaluation (C1) — group definitions saved in the file (format 5), group nodes through `NodeRegistry.makeNode`, a definition's graph evaluated per instance under scoped node IDs (tags stay put per instance and across definition edits), Group / Ungroup / Make Unique and definition edits as single undo steps, ⌘G / ⇧⌘G on the top level (spec `2026-10-09-selection-groups-comments-design.md` §4–§5, plan `2026-10-09-groups-core.md`, Errata (C1)) | ✅ code done | Multi-select (A); comments (B) add their keys under format 5 |
+| — | Groups: editor (C2) — the group node's look, entering a group (double-click, ⌘↓, Edit Group), breadcrumbs and ⌘↑, per-level pan and zoom, Group Input/Output + sockets, the group inspector, the library's Groups section, the viewport inside a group (spec §6; a pick made there is written relative to the level shown, as `GroupScopes.identity` names it), the clipboard carrying the definitions pasted group nodes use, merged by content (spec §9), and inner node states from `DocumentModel.innerResults` | ⏳ after C1 | MetalUI gap GI-a (canvas double-click, synthesised until MetalUI C16) |
 | — | Packaging: bundle OCCT dylibs into a signed `.app` | ✅ code done; human checks P pending | Spec §11, Errata (Packaging); `scripts/package-app.sh`, `docs/packaging.md`. Ad hoc by default, Developer ID via `METALCREATOR_SIGN_IDENTITY`; notarization is manual; no icon yet; needs macOS 27 while Homebrew's bottles do; MetalUI gap P-a fixed (MetalUI 67a579e; its notices are bundled) |
 | — | C7 adoption: swap the viewport's, the graph panel's and the app's input stopgaps for MetalUI C7's APIs once `feat/input-apis` merges (lists in the carry-over note, From M4, From M5, From M6) | ✅ viewport (human checks VC pass); graph panel and app ✅ merged 2026-10-09 (human checks GI pending) | MetalUI decisions file `docs/superpowers/2026-10-08-input-apis-decisions.md` |
 | — | Naming: picks on merged faces — an Edges by Tag pick on a face a union merged must survive one operand changing (spec §8's polygon swap, Errata (M6)); needs the split-edge count handled too, not only a minimal tag subset | ✅ code done (plan `2026-10-09-naming-merged-faces.md`, Errata (naming: merged faces)): a key matching nothing is retried narrowed (`EdgeKey.narrowed`), drift counts runs as well as edges (`EdgePick.runCount`, no format bump) | `BracketAcceptanceTests+PolygonSwap` (flipped: Edges by Tag resolves with no warning; the Chamfer still fails, row below), `BracketAcceptanceTests+MergedFaces` |
```

**Modify** `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` (apply this diff with `git apply`, or make the same edits by hand):

```diff
diff --git a/docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md b/docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md
index aa7be29..60a9127 100644
--- a/docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md
+++ b/docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md
@@ -181,3 +181,31 @@ public struct CommentFrame: Sendable, Codable, Equatable { id, title: String, fr
 
 Rows: "Multi-select polish (A)", "Groups: model and evaluation (C1)", "Comments (B)", "Groups: editor (C2)",
 "Comments: typing on the canvas (after MetalUI C9 + canvas double-click)".
+
+## Errata (C1)
+
+Plan `2026-10-09-groups-core.md`.
+
+- §4 "per-node sockets through `NodeDefinition.inputs(for:)`/`outputs(for:)`": a node definition's static methods
+  can't see the document's definitions, so a node's sockets are read through `NodeRegistry.inputs(for:)`/
+  `outputs(for:)`, which give group nodes, Group Input and Group Output their definition's sockets (the registry
+  carries the document's definitions, `DocumentModel.registry`) and every other node `NodeDefinition.inputs(for:)`/
+  `outputs(for:)` (the latter added here). Group Input and Group Output also carry `NodeSetting.group`.
+- §4 "registry entry `group`": the three group types live in `CreatorGraph` (the evaluator and the commands need
+  them, and `CreatorEditor` can't import `CreatorNodes`), and every `NodeRegistry` registers them itself; the palette
+  and the library don't list them.
+- §4 Group Output's inputs are optional: an unwired one is an output the group node doesn't produce.
+- §5 Naming: a pick stored inside a definition names faces as if the definition were the top level (its own nodes
+  by ID, nodes inside its group nodes by `NodeID.scoped` of the path from it), and each instance reads it as its own
+  (`EvaluationScope.naming`), so a sub-graph with a picked fillet works in every instance.
+- §5 Naming: Group, Ungroup and Make Unique change the names faces are made under, and each renames, in the same
+  undo step, every pick in the document that names a face of the nodes it moves (`GroupScopes.renamingPicks`),
+  inside the moved nodes too. So no pick drifts across them, and there is no message to state ("picks across them
+  follow the existing drift rules … stated in the commands' messages" no longer applies; `GroupEdit` has no notice).
+- §4/§5 A definition's new interface is refused, after the whole command, when it removes a socket, or gives it
+  another type, while a wire is still on it: on a group node, or inside on Group Input or Group Output.
+- §5 Ungroup removes the definition with its last group node; Make Unique also renames its group node to the
+  copy's name; renaming a definition renames the group nodes still named after it.
+- §5 ⌘G and ⇧⌘G (`EditorModel.groupSelection`/`ungroupSelection`) act on the top level until C2 shows a
+  definition's inside.
+- §2 The file format went 4 → 5 here; comments (B) add their keys under 5.
```

- [ ] **Step 2: Verify the whole package**

Run: `swiftlint lint --strict` (expect no violation), then `swift test 2>&1 | tee /tmp/groups-test.log`.

Expected: exit code 0; `grep -c 'recorded an issue' /tmp/groups-test.log` and `grep -c 'failed after' /tmp/groups-test.log` print 0; `grep -c 'Test run with' /tmp/groups-test.log` prints 11; the counts on those lines add up to **1478** (master + 88).

- [ ] **Step 3: Commit**

```bash
git add 'CLAUDE.md' 'docs/superpowers/roadmap.md' 'docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md'
git commit -m "docs: groups C1 in CLAUDE.md, roadmap and spec errata"
```

---

## Self-review

**Spec coverage** (groups spec §4, §5, §9 for C1):

- §4 `GroupID`, `GroupDefinition` (id, name, accent, inputs, outputs, graph) — Task 1; `GraphFile.definitions`, encoded sorted by ID — Task 2; format 4 → 5 with definitions optional on decode and version-4 files unchanged — Task 2 (`aVersionFourFileOpensWithNoDefinitions`).
- §4 group node of type `group` naming its definition, built by `NodeRegistry.makeNode` (entry `group`), per-node sockets, typed values in `inputValues` — Tasks 1, 3 (Key decision 1); Group Input / Group Output, exactly one each, never deleted — Tasks 1, 4 (`groupInputAndOutputStayInTheirGroup`; copying them is C2's clipboard, and Group refuses them, Task 7); nesting allowed and cycles refused (`GroupDependencies.wouldRecurse`) — Task 4 (`aGroupCantContainItself`), Task 7 (nesting by ⌘G); no Output node inside — Tasks 4, 7.
- §5 evaluation: inputs bound (wire, typed value, default), outputs from Group Output — Task 5 (`aGroupNodeRunsItsDefinition`); values pass through, no group-level broadcasting — Task 5 (`listsPassThroughAndBroadcastInside`); cached per instance path, a definition edit re-runs every instance — Task 5 (`eachInstanceIsCachedOnItsOwnAndADefinitionEditRerunsThemAll`), Task 6 (document level); cancellation at inner node boundaries — Task 5; failures and warnings with the inner path — Task 5.
- §5 naming: scoped `NodeID`s, picks keep their shape, distinct per instance and stable under definition edits — Tasks 5, 11; a pick inside a definition holds in every instance — Task 5 (`aPickInsideADefinitionNamesEachInstancesFaces`), Task 11 (`aFilletPickedBeforeGroupingFilletsEveryInstance`); Group keeps picks — Task 7 (`groupingRenamesThePicksOnTheGroupedNodesFaces`, `groupingInsideADefinitionRenamesPicksThroughEachInstance`), Task 11 (`groupingThePickedPlateKeepsTheChamfer`); Ungroup and Make Unique give new IDs and, beyond the spec, rename the picks to them instead of drifting (Errata (C1)) — Task 8, Task 11 (`makeUniqueThenEditingItLeavesTheOtherPickAlone`); the naming-stability tests on OCCT — Task 11.
- §5 commands: Group (refusals, naming, boundary sockets, placement, selection) — Task 7, keys Task 10; Ungroup (fresh IDs, rewiring, typed values, straight-through, selection, definition kept while used) — Task 8; Make Unique — Task 8; rename, accent, add / rename / reorder / remove socket (removing a wired one refused, naming the node, by the builder and, for any raw `setInterface`, by `GraphContent.apply`) — Tasks 9, 4 (`aWiredSocketCantBeRemovedOrRetypedByANewInterface`); delete definition only when unused — Tasks 4, 9; graph commands addressed to a graph path, undoable — Tasks 4, 6.
- §9 evaluation equality on the §7.2 bracket's rib, with its chamfer picked — Task 11; lists, nesting, cycles, caching — Task 5; format 5 encode/decode — Task 2; undo of each command — Tasks 4, 6–9. Render tests, human checks and the clipboard round trip (definitions travelling with pasted group nodes) are C2's (header, roadmap C2 row). Not in the spec but found in review: an edit only to a definition marks the document edited — Task 6 (`GroupEditedTests`); a rename refreshes the group's message without marking it stale — Task 6.

**Placeholders:** none; every step has its code, command and expected output.

**Type consistency:** `GroupID`, `GroupDefinition.make(id:name:accent:inputs:outputs:registry:inputAt:outputAt:)`, `NodeRegistry.withGroups(_:)` / `group(of:)` / `inputs(for:)` / `outputs(for:)` / `makeGroupNode(_:for:at:)`, `GraphContent.apply(_:registry:)` / `graph(at:)` / `touchedTopLevelNodes(_:)` / `topLevelNode(producing:)`, `GraphCommand.inDefinition` / `addDefinition` / `removeDefinition` / `setInterface` / `at(_:)`, `GraphPath.root` / `.definition`, `Evaluator.evaluate(_:definitions:demand:)`, `NodeID.scoped(_:)`, `DocumentModel.content` / `definitions` / `perform(_:at:coalescingKey:)`, `GroupEdit(command:selection:)`, `GraphContent.affectsResults(_:)` / `affectsMessages(_:)`, `DocumentModel.innerResults`, `GroupScopes.paths(in:definitions:entered:)` / `identity(_:)` / `names(in:definitions:through:_:)` / `chains(to:in:)` / `renamingPicks(at:in:skipping:_:)`, `EvaluationScope.entering(_:group:graph:bound:)` / `naming(_:)`, `ConstantValue.renamingTags(_:)`, `Node.renamingTags(_:)`, `GroupCommands.group` / `ungroup` / `makeUnique` (`(_:in:of:registry:)`), `rename(_:to:in:)`, `setAccent(_:_:in:)`, `addSocket(_:side:name:type:in:)`, `moveSocket(_:side:from:to:in:)`, `renameSocket(_:side:from:to:in:)`, `removeSocket(_:side:name:in:)`, `deleteDefinition(_:in:)`, `EditorModel.groupSelection()` / `ungroupSelection()` are spelled the same in every task that uses them (the code blocks are the verified files).

**Review Focus:** each of the six lines has its test in the owning task (named in the list).

**Verified** (2026-10-09): every code block of this plan applied task by task, by script, to a scratch copy of master `2e64c96` beside a `MetalUI` symlink to `/Users/maxburger/Developer/MetalUI` (at `2155f1e`, which contains `9ad2254`); each task's tree compared byte for byte with the verified one. After each task `swift build --build-tests` printed no compiler warning in any file it compiled, `swiftlint lint --strict` printed no violation, and `swift test` exited 0 with no "recorded an issue" or "failed after" line and 11 "Test run with" lines totalling 1399, 1404, 1409, 1423, 1435, 1441, 1451, 1458, 1466, 1470, 1476, 1478, 1478 (master 1390 + 9, 14, 19, 33, 45, 51, 61, 68, 76, 80, 86, 88, 88). Each Step 2 was checked too: with only the task's tests applied on the previous task, the build fails with the errors quoted (Task 3: builds, and its new tests fail with 5 issues per run); Task 11's tests pass at once.
