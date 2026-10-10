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
