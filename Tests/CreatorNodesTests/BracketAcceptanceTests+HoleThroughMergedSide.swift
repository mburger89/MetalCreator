import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorOCCT

extension BracketAcceptanceTests {
    /// Roadmap "Naming: face picks on merged faces", the edge half: a 5 mm hole drilled along X at y = 16, z = 3
    /// through the bracket's union, so its rim on the left side is an edge between a face the union merged (the
    /// plate's side and the flange's, `{plate.side, flange.side}`) and the hole's wall, which shares no node call
    /// with either. The rim is picked with the flange flush; then the flange alone changes width (40 or 70), or is
    /// swapped for the hexagon of Errata (M6), so the faces no longer merge and the key matches nothing. Edges by
    /// Tag still finds the rim on the plate's side, with no warning, after a save and reopen too, and the pick holds
    /// once the flange is flush again (the width cases).
    @Test(arguments: [(40.0, -30.0), (70.0, -35.0)])
    func aHoleRimPickedOnAMergedSideSurvivesTheFlangeChangingWidth(flangeWidth: Double, rimX: Double) async throws {
        try await checkTheRimSurvives("flange \(flangeWidth) wide", rimX: rimX) { document, bracket in
            let widthWire = try #require(document.graph.incomingLink(to: Endpoint(node: bracket.flangeProfile.id, socket: "width")))
            try document.perform(.batch([.disconnect(widthWire), .setInput(bracket.flangeProfile.id, "width", .number(flangeWidth))]))
            return .batch([.setInput(bracket.flangeProfile.id, "width", nil), .connect(widthWire)])
        }
    }

    @Test func aHoleRimPickedOnAMergedSideSurvivesTheFlangeBecomingAPolygon() async throws {
        try await checkTheRimSurvives("hexagon flange", rimX: -30) { document, bracket in
            try swapTheFlangeForAHexagon(in: document, bracket)
            return nil
        }
    }

    /// Picks the hole's rim with the flange flush, applies `change` (which returns the command that restores the
    /// flange, if it has one), and checks the rule before, after, reopened and restored.
    func checkTheRimSurvives(_ when: String, rimX: Double, change: (DocumentModel, Bracket) throws -> GraphCommand?) async throws {
        let kernel = OCCTKernel()
        let bracket = Self.makeBracket()
        let document = DocumentModel(file: GraphFile(graph: bracket.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        let rule = try await addHole(to: document, bracket)
        let drilled = try edgeSetOutput(document, rule)
        let leftRim = try #require(drilled.solid.topology.edges.first { edge in
            !edge.isSeam && edge.kind == .circle && edge.midpoint.x < -29
        })
        let picks = drilled.solid.topology.picks(for: [leftRim.id])
        let flushKey = try #require(picks.first?.key)
        #expect(picks.count == 1 && flushKey.first.union(flushKey.second).contains { $0.node == bracket.flange.id },
                "the rim is named by the merged side's tags, the flange's among them")
        try document.perform(.setInput(rule.id, NodeSetting.picks, .edgePicks(picks)))
        await document.waitForEvaluation()
        #expect(isOK(document, rule), "flush flange")

        let restore = try change(document, bracket)
        await document.waitForEvaluation()
        try expectTheRim(document, rule, at: rimX, notNamed: flushKey, when)

        let reopened = try DocumentModel(data: try document.fileData(), registry: BuiltInNodes.registry, kernel: kernel)
        reopened.previewNode = rule.id
        await reopened.waitForEvaluation()
        try expectTheRim(reopened, rule, at: rimX, notNamed: flushKey, "reopened, \(when)")

        if let restore {
            try document.perform(restore)
            await document.waitForEvaluation()
            #expect(isOK(document, rule), "flush again")
            #expect(keys(try edgeSetOutput(document, rule)) == [flushKey])
        }
    }

    /// Drills the hole (a Circle on a YZ plane through (0, 16, 3), a symmetric Extrude, a subtracting Boolean on the
    /// union) and adds an Edges by Tag on the result, shown in the preview and evaluated.
    func addHole(to document: DocumentModel, _ bracket: Bracket) async throws -> Node {
        let registry = BuiltInNodes.registry
        var circle = registry.makeNode(CircleNode.typeID)
        let plane = Plane(origin: Vector3(0, 16, 3), normal: .unitX, xAxis: .unitY)
        circle.inputValues.merge(["diameter": .number(5), "plane": .plane(plane)]) { _, new in new }
        var bore = registry.makeNode(ExtrudeNode.typeID)
        bore.inputValues.merge(["distance": .number(100), "mode": .integer(1)]) { _, new in new }
        var drill = registry.makeNode(BooleanNode.typeID)
        drill.inputValues["operation"] = .integer(1)
        let rule = registry.makeNode(EdgesByTagNode.typeID)
        func link(_ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName) -> GraphCommand {
            .connect(Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input)))
        }
        try document.perform(.batch([
            .addNode(circle), .addNode(bore), .addNode(drill), .addNode(rule),
            link(circle, "profile", bore, "profile"), link(bracket.union, "solid", drill, "target"),
            link(bore, "solid", drill, "tools"), link(drill, "solid", rule, "solid"),
        ]))
        document.previewNode = rule.id
        await document.waitForEvaluation()
        #expect(document.results[rule.id]?.state == .warning("Pick edges in view to fill this rule."), "drilled, nothing picked yet")
        return rule
    }

    func edgeSetOutput(_ document: DocumentModel, _ rule: Node) throws -> EdgeSet {
        try #require(document.results[rule.id]?.outputs?["edges"]?.edgeSets?.first)
    }

    /// The rule picks exactly one edge, the hole's rim in the bracket's left side at x = `x`, under another name
    /// than the merged side's (the plate's side at -30, or the flange's own at -35 once it sticks out), and says
    /// nothing about it.
    func expectTheRim(_ document: DocumentModel, _ rule: Node, at x: Double, notNamed flushKey: EdgeKey, _ when: String,
                      sourceLocation: SourceLocation = #_sourceLocation) throws {
        let state = String(describing: document.results[rule.id]?.state)
        #expect(isOK(document, rule), "\(when): \(state)", sourceLocation: sourceLocation)
        let set = try edgeSetOutput(document, rule)
        #expect(set.edges.count == 1, "\(when): the rim", sourceLocation: sourceLocation)
        let rim = try #require(set.edges.first.flatMap { set.solid.topology.edge($0) }, sourceLocation: sourceLocation)
        #expect(rim.kind == .circle && isClose(rim.midpoint.x, x), "\(when): at x = \(x)", sourceLocation: sourceLocation)
        #expect(set.solid.topology.key(of: rim) != flushKey, "\(when): named by the operand that has it", sourceLocation: sourceLocation)
    }
}
