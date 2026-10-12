import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorOCCT

/// User decision 3 (7a-2) with trees: Group, Ungroup and Make Unique rename a pick on the instance at `{1;1}` exactly as they
/// rename any node's, because they change the identities its tags name and leave the path alone.
@MainActor
struct InstancePickRenamingTreeTests {
    let registry = BuiltInNodes.registry
    let item = InstancePath.item(for: [1, 1])

    func fixture() async throws -> PatternTreePickTests.Fixture {
        var part = PatternTreePickTests.Fixture()
        try await part.pick([[1, 1]], kernel: OCCTKernel())
        return part
    }

    func document(_ part: PatternTreePickTests.Fixture) -> DocumentModel {
        DocumentModel(file: GraphFile(graph: part.plate.h.graph), registry: registry, kernel: OCCTKernel())
    }

    /// The rim items (tag items of the instance faces) the rule at `path` selects in `content`, with its state.
    func selection(_ content: GraphContent, rule path: [NodeID]) async throws -> (state: NodeState?, items: [Int]) {
        let top = try #require(path.first)
        let report = try await Evaluator(registry: registry, kernel: OCCTKernel())
            .evaluate(content.graph, definitions: content.definitions, demand: Set(content.graph.nodes.keys))
        let result = path.count == 1 ? report.results[top] : report.innerResults[path]
        guard let set = result?.outputs?["edges"]?.edgeSets?.first else { return (result?.state, []) }
        let items = set.edges.flatMap { id -> [Int] in
            guard let edge = set.solid.topology.edge(id) else { return [] }
            return edge.faces.compactMap { set.solid.topology.face($0) }.flatMap(\.tags)
                .filter { $0.node.isInstanceQualified }.map(\.item)
        }
        return (result?.state, items)
    }

    func expectRim(_ content: GraphContent, rule path: [NodeID], sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let (state, items) = try await selection(content, rule: path)
        guard case .ok? = state else {
            Issue.record("the pick should resolve with no warning, got \(String(describing: state))", sourceLocation: sourceLocation)
            return
        }
        #expect(items == [item].compactMap { $0 }, "the rim of instance {1;1}", sourceLocation: sourceLocation)
    }

    @Test func groupingAPatternNodeRenamesATreePathPickAndUndoRestoresIt() async throws {
        let part = try await fixture()
        let document = document(part)
        let before = document.content
        try await expectRim(before, rule: [part.rule.id])
        let edit = try GroupCommands.group([part.holes.id], in: .root, of: document.content, registry: registry)
        try document.perform(edit.command)
        #expect(document.content.graph.nodes[part.rule.id]?.inputValues[NodeSetting.picks]
            != before.graph.nodes[part.rule.id]?.inputValues[NodeSetting.picks], "the pick was renamed")
        try await expectRim(document.content, rule: [part.rule.id])
        document.undo()
        #expect(document.content.graph.nodes == before.graph.nodes, "undo restores every setting, the pick exactly")
    }

    @Test func ungroupingRenamesATreePathPickInsideTheGroupToTheSplicedPatternNode() async throws {
        let part = try await fixture()
        let document = document(part)
        let grouped = try GroupCommands.group([part.holes.id, part.rule.id], in: .root, of: document.content, registry: registry)
        try document.perform(grouped.command)
        let group = try #require(grouped.selection.first)
        try await expectRim(document.content, rule: [group, part.rule.id])
        let before = document.content

        let edit = try GroupCommands.ungroup(group, in: .root, of: document.content, registry: registry)
        try document.perform(edit.command)
        let rule = try #require(document.content.graph.nodes.values.first { $0.typeID == EdgesByTagNode.typeID })
        try await expectRim(document.content, rule: [rule.id])
        document.undo()
        #expect(document.content == before)
    }

    @Test func makeUniqueGivesTheCopyTreePathPicksThatNameItsOwnInstanceFaces() async throws {
        let part = try await fixture()
        let document = document(part)
        let ids = Set(part.plate.h.nodes.keys).subtracting([part.plate.grid.id, part.plate.placements.id, part.rows.id, part.fillet.id])
        let grouped = try GroupCommands.group(ids, in: .root, of: document.content, registry: registry)
        try document.perform(grouped.command)
        let group = try #require(grouped.selection.first)
        try await expectRim(document.content, rule: [group, part.rule.id])
        let before = document.content

        let edit = try GroupCommands.makeUnique(group, in: .root, of: document.content, registry: registry)
        try document.perform(edit.command)
        let copy = try #require(document.content.graph.nodes[group]?.inputValues[NodeSetting.group]?.groupID)
        let rule = try #require(document.content.definitions[copy]?.graph.nodes.values.first { $0.typeID == EdgesByTagNode.typeID })
        try await expectRim(document.content, rule: [group, rule.id])
        document.undo()
        #expect(document.content == before)
    }

    @Test func aTreePathPickOnAnInstanceThatIsGoneStillWarnsAfterGrouping() async throws {
        var part = try await fixture()
        part.plate.h.set(part.plate.grid, "countY", .integer(1))  // One row: {1;1} is gone.
        let document = document(part)
        let message = "Instance {1;1} no longer exists, so the edge picked on it isn't selected."
        let (beforeState, beforeItems) = try await selection(document.content, rule: [part.rule.id])
        #expect(beforeState == .warning(message) && beforeItems.isEmpty)
        let edit = try GroupCommands.group([part.holes.id], in: .root, of: document.content, registry: registry)
        try document.perform(edit.command)
        let (state, items) = try await selection(document.content, rule: [part.rule.id])
        #expect(state == .warning(message), "renaming never invents a target")
        #expect(items.isEmpty)
    }
}
