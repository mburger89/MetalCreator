import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// A drag of a G2 fillet's radius previews it circular and ends at G2 (`DocumentModel.isScrubbing`).
@MainActor
struct ScrubbingTests {
    func makeFillet() async throws -> (app: AppModel, kernel: FakeKernel, fillet: Node) {
        var builder = GraphBuilder()
        let box = builder.solid()
        let edges = builder.add(AllEdgesNode.self)
        let fillet = builder.add(FilletNode.self, ["radius": .number(2), "continuity": .integer(1)])
        let output = builder.add(OutputNode.self)
        builder.wire(box.extrude, "solid", to: edges, "solid")
        builder.wire(edges, "edges", to: fillet, "edges")
        builder.wire(fillet, "solid", to: output, "solid")
        let kernel = FakeKernel()
        let app = await makeApp(builder.graph, kernel: kernel)
        app.editor.selection = [fillet.id]
        await app.settle()
        return (app, kernel, fillet)
    }

    @Test func aHandleDragPreviewsG1AndEndsG2() async throws {
        let (app, kernel, fillet) = try await makeFillet()
        let id = try #require(app.viewport.handles.first?.id)
        let before = await kernel.filletProfiles.count
        app.handleChanged(id, 3, .changed)
        await app.settle()
        app.handleChanged(id, 4, .changed)
        await app.settle()
        #expect(app.document.isScrubbing)
        let during = await kernel.filletProfiles.dropFirst(before)
        #expect(Array(during) == [.circular, .circular])
        app.handleChanged(id, 5, .ended)
        await app.settle()
        #expect(!app.document.isScrubbing)
        #expect(await kernel.filletProfiles.last == .curvatureContinuous(weight: 1))
        #expect(app.document.graph.nodes[fillet.id]?.inputValues["radius"] == .number(5))
    }

    @Test func aSliderDragPreviewsG1AndEndsG2() async throws {
        let (app, kernel, fillet) = try await makeFillet()
        let before = await kernel.filletProfiles.count
        app.editor.sliderEditingChanged(true)
        try app.document.perform(.setInput(fillet.id, "radius", .number(3)))
        await app.settle()
        #expect(Array(await kernel.filletProfiles.dropFirst(before)) == [.circular])
        app.editor.sliderEditingChanged(false)
        await app.settle()
        #expect(await kernel.filletProfiles.last == .curvatureContinuous(weight: 1))
    }

    @Test func aKeyStepEndsAtG2() async throws {
        let (app, kernel, fillet) = try await makeFillet()
        app.editor.sliderEditingChanged(true)
        try app.document.perform(.setInput(fillet.id, "radius", .number(3)))
        app.editor.sliderEditingChanged(false)
        await app.settle()
        #expect(await kernel.filletProfiles.last == .curvatureContinuous(weight: 1))
    }

    @Test func undoAfterADragIsG2() async throws {
        let (app, kernel, fillet) = try await makeFillet()
        let id = try #require(app.viewport.handles.first?.id)
        app.handleChanged(id, 3, .changed)
        app.handleChanged(id, 4, .ended)
        await app.settle()
        app.document.undo()
        await app.settle()
        #expect(app.document.graph.nodes[fillet.id]?.inputValues["radius"] == .number(2))
        #expect(await kernel.filletProfiles.last == .curvatureContinuous(weight: 1))
        #expect(app.document.results[fillet.id]?.state.isSuccess == true)
    }

    @Test func theSectionHandleDoesNotScrub() async throws {
        let (app, _, _) = try await makeFillet()
        app.handleChanged(SectionModel.handleID, 1, .changed)
        #expect(!app.document.isScrubbing)
        app.handleChanged(FieldPreviewModel.sliceHandleID, 1, .changed)
        #expect(!app.document.isScrubbing)
    }
}
