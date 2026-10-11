import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorOCCT

/// User decision 3, fixed in 7a-2: Group, Ungroup and Make Unique rename a pick on a pattern instance's faces exactly as
/// they rename a pick on any node's, because they change the identities the instance's tags name (the placer and the
/// tool's tag node). Every test picks the rim of hole {2} of a 3 × 2 Hole Pattern and expects that rim afterwards.
@MainActor
struct InstancePickRenamingTests {
    let registry = BuiltInNodes.registry

    /// A plate, a Hole Pattern on it, an Edges by Tag `rule` picking hole {2}'s rim, and a Fillet on it.
    struct Part {
        var plate: PatternPlate
        let holes: Node, rule: Node, fillet: Node

        init(picking index: Int = 2) async throws {
            plate = PatternPlate(columns: 3, rows: 2, spacingX: 15, spacingY: 15)
            holes = plate.h.add(HolePatternNode.self, ["diameter": .number(5), "depth": .number(6)])
            plate.h.wire(plate.plate, "solid", to: holes, "part")
            plate.h.wire(plate.placements, "placements", to: holes, "placements")
            rule = plate.h.add(EdgesByTagNode.self)
            plate.h.wire(holes, "solid", to: rule, "solid")
            fillet = plate.h.add(FilletNode.self, ["radius": .number(0.5)])
            plate.h.wire(rule, "edges", to: fillet, "edges")
            let solid = try onlySolid(try await plate.h.run([holes], kernel: OCCTKernel()), holes)
            let bore = TopoTag(node: NodeID.instanceScoped([holes.id, holes.id]), item: index, role: .side(segment: 1))
            let top = TopoTag(node: plate.plate.id, item: 0, role: .endCap)
            let rim = solid.topology.edges.first { edge in
                guard edge.kind == .circle, !edge.isSeam, edge.faces.count == 2 else { return false }
                let sides = edge.faces.compactMap { solid.topology.face($0) }
                return sides.contains { $0.tags.contains(bore) } && sides.contains { $0.tags.contains(top) }
            }
            plate.h.set(rule, NodeSetting.picks, .edgePicks(solid.topology.picks(for: [rim?.id].compactMap { $0 })))
        }

        @MainActor
        func document(_ registry: NodeRegistry) -> DocumentModel {
            DocumentModel(file: GraphFile(graph: plate.h.graph), registry: registry, kernel: OCCTKernel())
        }
    }

    /// The edges `rule` (at `path`, a node's ID or a group node's then its own) selects in `content`, with the rule's state.
    func selection(_ content: GraphContent, rule path: [NodeID]) async throws -> (state: NodeState?, rims: [Int]) {
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
        let (state, rims) = try await selection(content, rule: path)
        guard case .ok? = state else {
            Issue.record("the pick should resolve with no warning, got \(String(describing: state))", sourceLocation: sourceLocation)
            return
        }
        #expect(rims == [2], "the rim of instance {2}", sourceLocation: sourceLocation)
    }

    @Test func groupingAPatternNodeRenamesAPickOnItsInstanceAndUndoRestoresIt() async throws {
        let part = try await Part()
        let document = part.document(registry)
        let before = document.content
        try await expectRim(before, rule: [part.rule.id])
        let edit = try GroupCommands.group([part.holes.id], in: .root, of: document.content, registry: registry)
        try document.perform(edit.command)
        #expect(document.content.graph.nodes[part.rule.id]?.inputValues[NodeSetting.picks]
            != before.graph.nodes[part.rule.id]?.inputValues[NodeSetting.picks], "the pick was renamed")
        try await expectRim(document.content, rule: [part.rule.id])
        document.undo()
        // The fixture's links aren't in a loaded file's canonical order, so compare them as a set.
        #expect(document.content.graph.nodes == before.graph.nodes, "undo restores every setting, the pick exactly")
        #expect(Set(document.content.graph.links) == Set(before.graph.links) && document.content.definitions.isEmpty)
    }

    @Test func ungroupingRenamesAPickInsideTheGroupToTheSplicedPatternNode() async throws {
        let part = try await Part()
        let document = part.document(registry)
        let grouped = try GroupCommands.group([part.holes.id, part.rule.id], in: .root, of: document.content, registry: registry)
        try document.perform(grouped.command)
        let group = try #require(grouped.selection.first)
        try await expectRim(document.content, rule: [group, part.rule.id])
        let before = document.content

        let edit = try GroupCommands.ungroup(group, in: .root, of: document.content, registry: registry)
        try document.perform(edit.command)
        let content = document.content
        let holes = try #require(content.graph.nodes.values.first { $0.typeID == HolePatternNode.typeID })
        let rule = try #require(content.graph.nodes.values.first { $0.typeID == EdgesByTagNode.typeID })
        let bore = NodeID.instanceScoped([holes.id, holes.id])
        guard case .edgePicks(let picks)? = rule.inputValues[NodeSetting.picks] else { throw NodeError.invalidValue("no pick") }
        #expect(picks.flatMap { $0.key.first.union($0.key.second) }.contains { $0.node == bore })
        try await expectRim(content, rule: [rule.id])
        document.undo()
        #expect(document.content == before)
    }

    @Test func ungroupingRenamesAPickOutsideTheGroupOnItsPatternNode() async throws {
        let part = try await Part()
        let document = part.document(registry)
        let grouped = try GroupCommands.group([part.holes.id], in: .root, of: document.content, registry: registry)
        try document.perform(grouped.command)
        let group = try #require(grouped.selection.first)
        let edit = try GroupCommands.ungroup(group, in: .root, of: document.content, registry: registry)
        try document.perform(edit.command)
        try await expectRim(document.content, rule: [part.rule.id])
        document.undo()
        try await expectRim(document.content, rule: [part.rule.id])
    }

    /// The part's nodes but the grid and its placements, grouped: a definition with the plate, the pattern and the rule.
    func groupedPart(_ part: Part, in document: DocumentModel) throws -> NodeID {
        let ids = Set(part.plate.h.nodes.keys).subtracting([part.plate.grid.id, part.plate.placements.id])
            .subtracting([part.fillet.id])
        let edit = try GroupCommands.group(ids, in: .root, of: document.content, registry: registry)
        try document.perform(edit.command)
        return try #require(edit.selection.first)
    }

    @Test func makeUniqueGivesTheCopyPicksThatNameItsOwnInstanceFaces() async throws {
        let part = try await Part()
        let document = part.document(registry)
        let group = try groupedPart(part, in: document)
        try await expectRim(document.content, rule: [group, part.rule.id])
        let before = document.content

        let edit = try GroupCommands.makeUnique(group, in: .root, of: document.content, registry: registry)
        try document.perform(edit.command)
        let content = document.content
        let copy = try #require(content.graph.nodes[group]?.inputValues[NodeSetting.group]?.groupID)
        #expect(copy != before.graph.nodes[group]?.inputValues[NodeSetting.group]?.groupID)
        let rule = try #require(content.definitions[copy]?.graph.nodes.values.first { $0.typeID == EdgesByTagNode.typeID })
        #expect(rule.id != part.rule.id)
        try await expectRim(content, rule: [group, rule.id])
        document.undo()
        #expect(document.content == before)
    }

    @Test func makeUniqueRenamesAPickOutsideTheGroupOnAnInstanceInsideIt() async throws {
        let part = try await Part()
        let document = part.document(registry)
        let all = Set(part.plate.h.nodes.keys).subtracting([part.rule.id, part.fillet.id])
        let edit = try GroupCommands.group(all, in: .root, of: document.content, registry: registry)
        try document.perform(edit.command)
        let group = try #require(edit.selection.first)
        try await expectRim(document.content, rule: [part.rule.id])
        let before = document.content
        let unique = try GroupCommands.makeUnique(group, in: .root, of: document.content, registry: registry)
        try document.perform(unique.command)
        try await expectRim(document.content, rule: [part.rule.id])
        document.undo()
        #expect(document.content == before)
    }

    @Test func aPickOnAnInstanceThatIsGoneStillWarnsAfterGrouping() async throws {
        var part = try await Part(picking: 4)
        part.plate.h.set(part.plate.grid, "countY", .integer(1))  // 3 holes: {4} is gone.
        let document = part.document(registry)
        let message = "Instance {4} no longer exists, so the edge picked on it isn't selected."
        let (beforeState, beforeRims) = try await selection(document.content, rule: [part.rule.id])
        #expect(beforeState == .warning(message) && beforeRims.isEmpty)
        let edit = try GroupCommands.group([part.holes.id], in: .root, of: document.content, registry: registry)
        try document.perform(edit.command)
        let (state, rims) = try await selection(document.content, rule: [part.rule.id])
        #expect(state == .warning(message), "renaming never invents a target")
        #expect(rims.isEmpty)
    }
}
