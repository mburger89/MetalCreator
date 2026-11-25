import CreatorDrawing
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorApp

/// What the session keeps alive and what it lets go of (final review): a request key holds its solids so an identity can't be reused,
/// and the refresh record of a view that is gone is dropped.
@MainActor
struct DrawingSessionRetentionTests {
    @Test func aRequestKeyKeepsItsSolidsAliveWithoutComparingThem() async throws {
        let box = DrawingBox(width: 10)
        let app = await AppModel.inDrawing(box.graph, kernel: FakeKernel())
        _ = try #require(await app.placeBaseView())
        let output = try #require(app.document.graph.nodes.values.first(where: \.isOutput)?.id)
        let source = DrawingSession.content(of: output, in: app.document)
        guard case .ready(let solids, _, _) = source.state, !solids.isEmpty else {
            Issue.record("the Output should be ready")
            return
        }
        let frame = ProjectionFrame(direction: Vector3(0, 1, 0), up: Vector3(0, 0, 1))
        let key = DrawingSession.key(of: source, frame: frame, scale: 1)
        #expect(key.retained.count == solids.count)
        #expect(zip(key.retained, solids).allSatisfy { $0 === $1 })
        var bare = key
        bare.retained = []
        #expect(bare == key)
        #expect(bare.hashValue == key.hashValue)
    }

    @Test func theRefreshRecordOfAGoneViewIsDropped() async throws {
        let box = DrawingBox(width: 10)
        let app = await AppModel.inDrawing(box.graph, kernel: FakeKernel())
        _ = try #require(await app.placeBaseView())
        let gone = ViewID()
        let frame = ProjectionFrame(direction: Vector3(0, 1, 0), up: Vector3(0, 0, 1))
        let format = NumberFormat(units: app.document.units, settings: app.drawing.editor.document.settings)
        app.drawing.refreshed[gone] = DrawingSession.RefreshKey(solids: [], frame: frame, format: format, annotations: [])
        app.drawing.refreshLastGood()
        #expect(app.drawing.refreshed[gone] == nil)
    }
}
