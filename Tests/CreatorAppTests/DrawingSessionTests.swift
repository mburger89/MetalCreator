import CreatorDrawing
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorApp

/// What the session keeps and asks for with section and detail views (DR-3 R14).
@MainActor
struct DrawingSessionTests {
    func make() async -> (app: AppModel, base: ViewID, box: DrawingBox) {
        let kernel = FakeKernel()
        await kernel.setSectionCutHook { part, _, _ in part }
        let box = DrawingBox(width: 20)
        let app = await AppModel.inDrawing(box.graph, kernel: kernel)
        let base = await app.placeBaseView()
        return (app, base ?? ViewID(), box)
    }

    @Test func aDeletedViewsRequestIsPruned() async throws {
        let (app, base, box) = await make()
        let session = app.drawing
        var old: [ObjectIdentifier] = []
        if case .ready(let solids, _, _) = DrawingSession.content(of: box.output.id, in: app.document).state {
            old = solids.map(ObjectIdentifier.init)
        }
        #expect(!old.isEmpty)
        #expect(session.wanted[base] != nil && session.applied[base] != nil)
        session.editor.selection = [base]
        session.editor.deleteSelection()
        await app.settle()
        session.update()
        #expect(session.wanted[base] == nil && session.applied[base] == nil && session.flights[base] == nil)
        #expect(session.editor.contents[base] == nil)
        // The next evaluation replaces the solid. The session's requests (which hold their solids) must not hold the old one: the
        // document's own caches do, so this reads what the session keeps rather than a weak reference.
        try app.document.perform(.setInput(box.rectangle.id, "width", .number(30)), name: "Change Width")
        await app.settle()
        let held = (Array(session.wanted.values) + Array(session.applied.values) + session.flights.values.map(\.key))
            .flatMap(\.retained).map(ObjectIdentifier.init)
        #expect(held.allSatisfy { !old.contains($0) }, "no request of the session holds the old solid")
        #expect(session.wanted.isEmpty && session.applied.isEmpty && session.flights.isEmpty && session.generations.isEmpty)
    }

    @Test func requestKeysRetainTheirCurves() async throws {
        let kernel = FakeKernel()
        let curve = try await kernel.makeCurve([.line(.zero, Vector3(10, 0, 0))], tag: NodeTag(node: NodeID(), item: 0))
        let source = DrawingSourceContent(output: NodeID(), name: "O", state: .ready(solids: [], curves: [curve], meshCount: 0))
        let frame = ProjectionFrame(direction: Vector3(0, 1, 0), up: Vector3(0, 0, 1))
        let key = DrawingSession.key(of: source, frame: frame, scale: 1)
        #expect(key.retainedCurves.count == 1 && key.retainedCurves[0] === curve)
        var bare = key
        bare.retainedCurves = []
        #expect(bare == key)
    }

    @Test func aMovedCuttingLineReprojects() async throws {
        let (app, base, _) = await make()
        let section = try #require(await app.addSection(on: base))
        #expect(await app.drawing.cache.cutCalls == 1)
        try await app.editView(section) { view in
            guard case .section(var line)? = view.derivation else { return }
            line.cutter.points = line.cutter.points.map { $0 + Vector2(0, 1) }
            view.derivation = .section(line)
        }
        #expect(await app.drawing.cache.cutCalls == 2)
        #expect(app.drawing.editor.contents[section]?.projection != nil)
    }

    @Test func aDetailFollowsItsParent() async throws {
        let (app, base, box) = await make()
        let detail = try #require(await app.addDetail(on: base))
        let calls = await app.drawing.cache.kernelCalls
        let clipped = try #require(app.drawing.editor.contents[detail]?.projection)
        let parent = try #require(app.drawing.editor.contents[base]?.projection)
        #expect(clipped.lines.count <= parent.lines.count)
        try app.document.perform(.setInput(box.rectangle.id, "width", .number(40)), name: "Change Width")
        await app.settle()
        let after = try #require(app.drawing.editor.contents[detail])
        #expect(after.isPending == false)
        #expect(await app.drawing.cache.kernelCalls == calls + 1, "only the parent's projection asked the kernel")
        #expect(after.hatchClips.count == 1)
    }

    @Test func detailsOfDetailsResolveInOrder() async throws {
        let (app, base, box) = await make()
        let first = try #require(await app.addDetail(on: base, radius: 8))
        let second = try #require(await app.addDetail(on: first, radius: 3, dropAt: Vector2(260, 60)))
        #expect(app.drawing.editor.contents[second]?.hatchClips.count == 2, "the second detail keeps both circles")
        try app.document.perform(.setInput(box.rectangle.id, "width", .number(30)), name: "Change Width")
        await app.settle()
        #expect(app.drawing.editor.contents[second]?.hatchClips.count == 2)
        #expect(app.drawing.editor.contents[second]?.isPending == false)
    }
}
