import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

struct OutputNodeTests {
    /// The slice's 26 (spec §7.1) plus Plane from Face and Sketch (S4), Place and Points to Placements (7a-2).
    @Test func theBuiltInsAreTheSliceTheSketcherAndThePatternNodesInSevenCategories() {
        #expect(BuiltInNodes.all.count == 31)
        let counts = Dictionary(grouping: BuiltInNodes.all, by: { $0.category }).mapValues(\.count)
        #expect(counts == [.value: 9, .profile: 6, .solid: 5, .selection: 5, .feature: 2, .patterns: 3, .output: 1])
    }

    /// The palette path (M5) is `registry.makeNode(typeID, at:)`, so that is what is tested.
    @Test func newOutputNodesAreFlaggedAsOutputs() {
        #expect(BuiltInNodes.registry.makeNode(OutputNode.typeID).isOutput)
        #expect(!BuiltInNodes.registry.makeNode(ExtrudeNode.typeID).isOutput)
        #expect(BuiltInNodes.registry.makeNode(OutputNode.typeID, at: Vector2(3, 4)).position == Vector2(3, 4))
        #expect(BuiltInNodes.all.filter { BuiltInNodes.registry.makeNode($0.typeID).isOutput }.map { $0.typeID } == [OutputNode.typeID])
    }

    @MainActor
    @Test func anOutputNodeDrivesDocumentEvaluation() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let output = h.add(OutputNode.self)
        h.wire(box, "solid", to: output, "solid")
        let document = DocumentModel(file: GraphFile(graph: h.graph), registry: BuiltInNodes.registry, kernel: FakeKernel())
        await document.waitForEvaluation()
        let solids = try #require(document.results[output.id]?.outputs?["solid"]?.solids)
        #expect(solids.count == 1)
        #expect(document.results[box.id]?.state.isSuccess == true)
    }

    @Test func broadcastSolidsArriveAsOneList() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self)
        let circle = h.add(CircleNode.self)
        h.wire(grid, "points", to: circle, "plane")
        let extrude = h.add(ExtrudeNode.self)
        h.wire(circle, "profile", to: extrude, "profile")
        let output = h.add(OutputNode.self)
        h.wire(extrude, "solid", to: output, "solid")
        let report = try await h.run([output])
        #expect(report.value(output, "solid")?.solids?.count == 4)
        #expect(report.isOK(output))
    }

    @Test func anUnwiredOutputWaits() async throws {
        var h = Harness()
        let output = h.add(OutputNode.self)
        #expect(try await h.run([output]).state(output) == .idle("Connect or set “solid”."))
    }
}
