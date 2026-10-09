import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorOCCT

extension BracketAcceptanceTests {
    /// Roadmap "Naming: picks on merged faces", the case that comes out whole: the chamfer is picked on the
    /// plate's top outline while the flange is as wide as the plate (so the union merged each plate side with a
    /// flange side, and the flange's fillet split each side's top edge in two). Then the flange alone changes
    /// width, narrower (40) or wider (70) than the plate, so no side is merged any more. Every pick resolves to
    /// the same plate edges by its narrowed key, with no warning anywhere, and the part is still there; it
    /// survives a save and reopen, and a pick made now still holds once the flange is flush again.
    @Test(arguments: [40.0, 70.0])
    func aChamferPickedOnMergedSidesSurvivesTheFlangeChangingWidth(flangeWidth: Double) async throws {
        let kernel = OCCTKernel()
        let bracket = Self.makeBracket()
        let document = DocumentModel(file: GraphFile(graph: bracket.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        let filleted = try #require(document.results[bracket.fillet.id]?.outputs?["solid"]?.solids?.first)
        try document.perform(.setInput(bracket.chamferEdges.id, NodeSetting.picks,
                                       .edgePicks(filleted.topology.picks(for: topCapOutline(filleted, plate: bracket.plate)))))
        await document.waitForEvaluation()
        expectAllOK(document, "flush flange")
        let flushKeys = keys(try edgeSet(document, bracket.chamferEdges))
        #expect(try edgeSet(document, bracket.chamferEdges).edges.count == 7)

        let widthWire = try #require(document.graph.incomingLink(to: Endpoint(node: bracket.flangeProfile.id, socket: "width")))
        try document.perform(.batch([.disconnect(widthWire), .setInput(bracket.flangeProfile.id, "width", .number(flangeWidth))]))
        await document.waitForEvaluation()
        expectAllOK(document, "flange \(flangeWidth) wide")
        let chamfer = try edgeSet(document, bracket.chamferEdges)
        #expect(chamfer.edges.count == 5, "the front edge, its two corners and the two plate sides")
        #expect(keys(chamfer) == Set(flushKeys.map { $0.narrowed ?? $0 }))
        #expect(document.results[bracket.output.id]?.outputs?["solid"]?.solids?.count == 1)

        let reopened = try DocumentModel(data: try document.fileData(), registry: BuiltInNodes.registry, kernel: kernel)
        await reopened.waitForEvaluation()
        expectAllOK(reopened, "reopened at \(flangeWidth)")
        #expect(keys(try edgeSet(reopened, bracket.chamferEdges)) == keys(chamfer))

        // Picked again now, the five edges name the plate alone, and they stay picked once the flange is flush.
        try document.perform(.setInput(bracket.chamferEdges.id, NodeSetting.picks,
                                       .edgePicks(chamfer.solid.topology.picks(for: chamfer.edges))))
        try document.perform(.batch([.setInput(bracket.flangeProfile.id, "width", nil), .connect(widthWire)]))
        await document.waitForEvaluation()
        expectAllOK(document, "re-picked, flush again")
        #expect(keys(try edgeSet(document, bracket.chamferEdges)) == flushKeys)
        #expect(try edgeSet(document, bracket.chamferEdges).edges.count == 7)
    }
}
