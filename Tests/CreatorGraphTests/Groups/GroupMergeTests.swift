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

    /// Make Unique counts on from a number ("Rib 2" gives "Rib 3"); a paste that meets a taken name does not: it adds
    /// "(imported)", so the number-aware naming never reaches it.
    @Test func aNumberedNameTheDocumentUsesIsImportedNotCountedOn() throws {
        let other = Doubler(name: "Rib 2")
        let plan = GroupMerge.plan(importing: table([other.definition]), into: content([Doubler(name: "Rib 2").definition]))
        #expect(try #require(plan.additions.first).name == "Rib 2 (imported)")
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
