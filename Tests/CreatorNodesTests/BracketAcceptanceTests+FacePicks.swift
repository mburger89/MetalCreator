import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import Testing
@testable import CreatorOCCT

extension BracketAcceptanceTests {
    /// Roadmap "Naming: face picks on merged faces", the Plane from Face half. A plane is picked on the plate's
    /// left side, which the union merged with the flange's coplanar side (it names both operands' tags), while
    /// the flange is as wide as the plate. Then the flange alone changes width, narrower (40) or wider (70)
    /// than the plate, so the faces no longer merge and the pick matches nothing. The plane stays on the plate's
    /// side, with no warning, it survives a save and reopen, and it is back on the merged face once the flange
    /// is flush again.
    @Test(arguments: [40.0, 70.0])
    func aPlanePickedOnAMergedSideSurvivesTheFlangeChangingWidth(flangeWidth: Double) async throws {
        let kernel = OCCTKernel()
        let (document, bracket, plane) = try await openBracketWithPlane(kernel)
        let flush = try planeOutput(document, plane)
        #expect(isClose(flush.origin.x, -30) && flush.normal.dot(-.unitX) > 0.999)

        let widthWire = try #require(document.graph.incomingLink(to: Endpoint(node: bracket.flangeProfile.id, socket: "width")))
        try document.perform(.batch([.disconnect(widthWire), .setInput(bracket.flangeProfile.id, "width", .number(flangeWidth))]))
        await document.waitForEvaluation()
        try expectPlaneOnThePlateSide(document, plane, bracket, "flange \(flangeWidth) wide")

        let reopened = try DocumentModel(data: try document.fileData(), registry: BuiltInNodes.registry, kernel: kernel)
        reopened.previewNode = plane.id
        await reopened.waitForEvaluation()
        try expectPlaneOnThePlateSide(reopened, plane, bracket, "reopened at \(flangeWidth)")

        try document.perform(.batch([.setInput(bracket.flangeProfile.id, "width", nil), .connect(widthWire)]))
        await document.waitForEvaluation()
        #expect(isOK(document, plane), "flush again")
        let again = try planeOutput(document, plane)
        #expect(isClose(again.origin.x, -30) && isClose(again.origin.y, flush.origin.y) && isClose(again.origin.z, flush.origin.z))
    }

    /// The same pick with the flange's Rectangle swapped for the hexagon of Errata (M6): the hexagon's vertical
    /// sides carry the flange's side tags and face the same way, 17 mm inboard of the plate's side, and the
    /// plane stays on the plate's side. The Fillet after the union refuses the hexagon bracket at R3 (spec
    /// Errata (Kernel: invalid blends)), which is not the plane's business: it sits on the union.
    @Test func aPlanePickedOnAMergedSideSurvivesTheFlangeBecomingAPolygon() async throws {
        let kernel = OCCTKernel()
        let (document, bracket, plane) = try await openBracketWithPlane(kernel)
        try swapTheFlangeForAHexagon(in: document, bracket)
        await document.waitForEvaluation()
        try expectPlaneOnThePlateSide(document, plane, bracket, "hexagon flange")

        document.undo()
        await document.waitForEvaluation()
        #expect(isOK(document, plane), "undone")
    }

    /// The other way round: the plate alone is widened to 80 (its sides move to x = -40) while the flange stays 60
    /// wide, so the only part left in the plane the pick was in (x = -30) is the flange's own side, up the flange.
    /// The plane stays where it was in space, on that part, and the node says nothing: it doesn't follow the plate's
    /// side that moved (user decision 1, option (e)).
    @Test func aPlanePickedOnAMergedSideStaysInPlaceWhenOnlyThePlateMoves() async throws {
        let kernel = OCCTKernel()
        let (document, bracket, plane) = try await openBracketWithPlane(kernel)
        let widthWire = try #require(document.graph.incomingLink(to: Endpoint(node: bracket.flangeProfile.id, socket: "width")))
        try document.perform(.batch([.disconnect(widthWire), .setInput(bracket.flangeProfile.id, "width", .number(60))]))
        try document.perform(.setParameter(bracket.width.id, .number(80)))
        await document.waitForEvaluation()
        #expect(isOK(document, plane), "silent: \(String(describing: document.results[plane.id]?.state))")
        let result = try planeOutput(document, plane)
        #expect(isClose(result.origin.x, -30), "still in the plane x = -30, not the plate's new side at -40")
        #expect(result.normal.dot(-.unitX) > 0.999)
        #expect(result.origin.z > 6, "on the flange's side, up the flange")
    }

    /// A pick made before faces recorded their position can't tell the parts apart: the plane is still found, on
    /// the first part, and it says so.
    @Test func aPlanePickWithoutAPositionWarnsOnceTheFaceHasComeApart() async throws {
        let kernel = OCCTKernel()
        let (document, bracket, plane) = try await openBracketWithPlane(kernel)
        let union = try #require(document.results[bracket.union.id]?.outputs?["solid"]?.solids?.first)
        let tags = try #require(union.topology.facePick(for: mergedLeftSide(union, bracket))?.tags)
        try document.perform(.setInput(plane.id, NodeSetting.face, .facePick(FacePick(tags: tags))))
        let widthWire = try #require(document.graph.incomingLink(to: Endpoint(node: bracket.flangeProfile.id, socket: "width")))
        try document.perform(.batch([.disconnect(widthWire), .setInput(bracket.flangeProfile.id, "width", .number(40))]))
        await document.waitForEvaluation()
        #expect(document.results[plane.id]?.state == .warning(PlaneFromFaceNode.mergedPick))
        #expect(document.results[plane.id]?.outputs?["plane"]?.planes?.count == 1)
    }

    /// The bracket with a Plane from Face on the union's merged left side, shown in the preview and evaluated.
    func openBracketWithPlane(_ kernel: OCCTKernel) async throws -> (DocumentModel, Bracket, Node) {
        let bracket = Self.makeBracket()
        let document = DocumentModel(file: GraphFile(graph: bracket.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        let union = try #require(document.results[bracket.union.id]?.outputs?["solid"]?.solids?.first)
        let plane = BuiltInNodes.registry.makeNode(PlaneFromFaceNode.typeID)
        let solidWire = Link(from: Endpoint(node: bracket.union.id, socket: "solid"), to: Endpoint(node: plane.id, socket: "solid"))
        let pick = try #require(union.topology.facePick(for: mergedLeftSide(union, bracket)))
        try document.perform(.batch([.addNode(plane), .connect(solidWire), .setInput(plane.id, NodeSetting.face, .facePick(pick))]))
        document.previewNode = plane.id
        await document.waitForEvaluation()
        #expect(isOK(document, plane), "flush flange")
        return (document, bracket, plane)
    }

    /// The union's face on the plate's left side that carries both the plate's and the flange's tags.
    func mergedLeftSide(_ union: Solid, _ bracket: Bracket) throws -> FaceID {
        try #require(union.topology.faces.first { face in
            face.kind == .plane && (face.normal?.dot(-.unitX) ?? 0) > 0.999
                && face.tags.contains { $0.node == bracket.plate.id } && face.tags.contains { $0.node == bracket.flange.id }
        }).id
    }

    /// True for `.ok`: the node succeeded with no warning.
    func isOK(_ document: DocumentModel, _ node: Node) -> Bool {
        if case .ok? = document.results[node.id]?.state { true } else { false }
    }

    func planeOutput(_ document: DocumentModel, _ plane: Node) throws -> Plane {
        try #require(document.results[plane.id]?.outputs?["plane"]?.planes?.first)
    }

    /// The plane is on the plate's left side (x = -30, facing -X), and the node says nothing about it.
    func expectPlaneOnThePlateSide(_ document: DocumentModel, _ plane: Node, _ bracket: Bracket, _ when: String,
                                   sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(isOK(document, plane), "\(when)", sourceLocation: sourceLocation)
        let result = try planeOutput(document, plane)
        #expect(isClose(result.origin.x, -30), "\(when): at the plate's side", sourceLocation: sourceLocation)
        #expect(result.normal.dot(-.unitX) > 0.999, "\(when): facing out", sourceLocation: sourceLocation)
        #expect(result.origin.z <= 6, "\(when): on the plate, not up the flange", sourceLocation: sourceLocation)
    }
}
