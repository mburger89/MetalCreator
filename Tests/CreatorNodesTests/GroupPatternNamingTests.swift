import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorOCCT

/// Patterns spec §6 with groups spec §5: a "Drilled plate" definition holds a plate, a Hole Pattern and a Fillet on the
/// rim of hole {4}, picked as if the definition were the top level. Placed twice, each instance names its holes by its
/// own pattern node, and the pick inside holds for both.
@MainActor
struct GroupPatternNamingTests {
    struct Drilled {
        let content: GraphContent
        let definition: GroupID
        let plate: NodeID
        let holes: NodeID
        let rule: NodeID
        let first: Node
        let second: Node
    }

    static func wire(_ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName) -> Link {
        Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input))
    }

    /// The definition: a plate, a Hole Pattern on it and, with `pick`, a Fillet on the rim of hole {4}.
    static func makeDefinition(pick: Bool) -> (definition: GroupDefinition, plate: NodeID, holes: NodeID, rule: NodeID) {
        let registry = BuiltInNodes.registry
        var definition = GroupDefinition.make(name: "Drilled plate", inputs: [SocketSpec("placements", .plane, access: .list)],
                                              outputs: [SocketSpec("solid", .solid)], registry: registry)
        func inner(_ typeID: String, _ values: [SocketName: ConstantValue] = [:]) -> Node {
            var node = registry.makeNode(typeID)
            node.inputValues.merge(values) { _, given in given }
            definition.graph.nodes[node.id] = node
            return node
        }
        let profile = inner(RectangleNode.typeID, ["width": .number(60), "height": .number(40),
                                                   "plane": .plane(.through(Vector3(0, 0, -6))),
        ])
        let plate = inner(ExtrudeNode.typeID, ["distance": .number(6)])
        let holes = inner(HolePatternNode.typeID, ["diameter": .number(5), "depth": .number(6)])
        var rule = registry.makeNode(EdgesByTagNode.typeID)
        let fillet = registry.makeNode(FilletNode.typeID, at: .zero)
        guard let input = definition.inputNode, let output = definition.outputNode else { return (definition, plate.id, holes.id, rule.id) }
        var links = [wire(profile, "profile", plate, "profile"), wire(plate, "solid", holes, "part"),
                     wire(input, "placements", holes, "placements"),
        ]
        if pick {
            // As if the definition were the top level: the hole's bore named by the pattern node's own ID.
            let bore = TopoTag(node: NodeID.instanceScoped([holes.id, holes.id]), item: 4, role: .side(segment: 1))
            let key = EdgeKey([bore], [TopoTag(node: plate.id, item: 0, role: .endCap)])
            rule.inputValues[NodeSetting.picks] = .edgePicks([EdgePick(key: key, matchCount: 1)])
            for node in [rule, fillet] { definition.graph.nodes[node.id] = node }
            links += [wire(holes, "solid", rule, "solid"), wire(rule, "edges", fillet, "edges"), wire(fillet, "solid", output, "solid")]
        } else {
            links.append(wire(holes, "solid", output, "solid"))
        }
        definition.graph.links = links
        return (definition, plate.id, holes.id, rule.id)
    }

    /// The definition placed twice on one grid of placements.
    static func make(pick: Bool = true) -> Drilled {
        let registry = BuiltInNodes.registry
        let inside = makeDefinition(pick: pick)
        var nodes: [Node] = []
        func top(_ typeID: String, _ values: [SocketName: ConstantValue] = [:]) -> Node {
            var node = registry.makeNode(typeID)
            node.inputValues.merge(values) { _, given in given }
            nodes.append(node)
            return node
        }
        let grid = top(GridPointsNode.typeID, ["countX": .integer(3), "countY": .integer(2), "spacingX": .number(15),
                                               "spacingY": .number(15),
        ])
        let placements = top(PointsToPlacementsNode.typeID)
        let groups = registry.withGroups([inside.definition.id: inside.definition])
        let first = groups.makeGroupNode(GroupNodes.groupTypeID, for: inside.definition.id)
        let second = groups.makeGroupNode(GroupNodes.groupTypeID, for: inside.definition.id)
        nodes += [first, second]
        let links = [wire(grid, "points", placements, "points"), wire(placements, "placements", first, "placements"),
                     wire(placements, "placements", second, "placements"),
        ]
        let graph = Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }), links: links)
        return Drilled(content: GraphContent(graph: graph, definitions: [inside.definition.id: inside.definition]),
                       definition: inside.definition.id, plate: inside.plate, holes: inside.holes, rule: inside.rule,
                       first: first, second: second)
    }

    func evaluate(_ drilled: Drilled) async throws -> EvaluationReport {
        try await Evaluator(registry: BuiltInNodes.registry, kernel: OCCTKernel())
            .evaluate(drilled.content.graph, definitions: drilled.content.definitions, demand: [drilled.first.id, drilled.second.id])
    }

    @Test func eachInstanceNamesItsHolesByItsOwnPatternNode() async throws {
        let drilled = Self.make(pick: false)
        let report = try await evaluate(drilled)
        for group in [drilled.first, drilled.second] {
            let solid = try #require(report.results[group.id]?.outputs?["solid"]?.solids?.first)
            let pattern = NodeID.scoped([group.id, drilled.holes])
            let expected = NodeID.instanceScoped([pattern, pattern])
            let nodes = Set(solid.topology.faces.flatMap(\.tags).map(\.node).filter(\.isInstanceQualified))
            #expect(nodes == [expected])
        }
    }

    @Test func aPickStoredInsideTheDefinitionHoldsForEveryInstance() async throws {
        let drilled = Self.make()
        let report = try await evaluate(drilled)
        for group in [drilled.first, drilled.second] {
            #expect(report.results[group.id]?.state.isSuccess == true, "\(String(describing: report.results[group.id]?.state))")
            guard case .ok? = report.results[group.id]?.state else {
                Issue.record("expected a clean result, got \(String(describing: report.results[group.id]?.state))")
                continue
            }
            let selected = report.innerResults[[group.id, drilled.rule]]?.outputs?["edges"]?.edgeSets?.first
            #expect(selected?.edges.count == 1)
            let solid = try #require(report.results[group.id]?.outputs?["solid"]?.solids?.first)
            #expect(solid.topology.faces.contains { face in face.tags.contains { if case .blend = $0.role { true } else { false } } })
        }
    }

    @Test func aPickMadeInsideAnInstanceIsStoredRelativeToTheDefinition() {
        let drilled = Self.make()
        let pattern = NodeID.scoped([drilled.first.id, drilled.holes])
        func pick(bore: NodeID, plate: NodeID) -> ConstantValue {
            let key = EdgeKey([TopoTag(node: bore, item: 4, role: .side(segment: 1))],
                              [TopoTag(node: plate, item: 0, role: .endCap)])
            return .edgePicks([EdgePick(key: key, matchCount: 1)])
        }
        let made = pick(bore: NodeID.instanceScoped([pattern, pattern]), plate: NodeID.scoped([drilled.first.id, drilled.plate]))
        let stored = pick(bore: NodeID.instanceScoped([drilled.holes, drilled.holes]), plate: drilled.plate)
        let relative = drilled.content.relativeToLevel(made, levels: [drilled.first.id], registry: BuiltInNodes.registry)
        #expect(relative == stored)
        // Without the registry only the plain nodes are renamed, as before patterns.
        let plain = drilled.content.relativeToLevel(made, levels: [drilled.first.id])
        #expect(plain == pick(bore: NodeID.instanceScoped([pattern, pattern]), plate: drilled.plate))
    }
}
