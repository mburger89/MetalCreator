import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

/// What each state of a part does to an assembly view (DR-5 R2).
extension AssemblyContentTests {
    @Test func aFailedPartFailsTheView() async throws {
        let kernel = await kernel()
        let box = try await base(kernel)
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let ready = [part(nodeA, "Plate", [solid(6, from: box)]), part(nodeB, "Bolt", [solid(6, from: box)])]
        let first = await projector.content(for: view([nodeA, nodeB]), scale: 1, parts: ready, previous: nil)
        let failed = await projector.content(
            for: view([nodeA, nodeB]), scale: 1,
            parts: [ready[0], DrawingSourceContent(output: nodeB, name: "Bolt", state: .failed("No fit."))], previous: first)
        #expect(failed.projection == first.projection)
        #expect(failed.parts == first.parts)
        #expect(!failed.isPending)
        #expect(failed.problem == "“Bolt” can't be drawn: No fit.")
        #expect(failed.problem == DrawingProjector.partFailedSentence(name: "Bolt", message: "No fit."))
    }

    @Test func anEvaluatingPartKeepsTheViewPending() async throws {
        let kernel = await kernel()
        let box = try await base(kernel)
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let ready = [part(nodeA, "Plate", [solid(6, from: box)]), part(nodeB, "Bolt", [solid(6, from: box)])]
        let first = await projector.content(for: view([nodeA, nodeB]), scale: 1, parts: ready, previous: nil)
        let waiting = await projector.content(
            for: view([nodeA, nodeB]), scale: 1,
            parts: [ready[0], DrawingSourceContent(output: nodeB, name: "Bolt", state: .evaluating)], previous: first)
        #expect(waiting.projection == first.projection)
        #expect(waiting.topology == first.topology)
        #expect(waiting.parts == first.parts)
        #expect(waiting.problem == nil)
    }

    @Test func aRemovedPartIsLeftOutWithAWarning() async throws {
        let kernel = await kernel()
        let box = try await base(kernel)
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let removed = DrawingSourceContent(output: nodeB, name: "", state: .removed)
        let content = await projector.content(
            for: view([nodeA, nodeB]), scale: 1, parts: [part(nodeA, "Plate", [solid(6, from: box)]), removed], previous: nil)
        #expect(content.problem == nil && content.projection != nil)
        #expect(content.warnings == [DrawingProjector.partRemovedSentence])
        #expect(
            DrawingProjector.partRemovedSentence == "One of this view's parts was removed from the model, so it isn't drawn.")
        #expect(content.parts.map(\.output) == [nodeA])
        let gone = await projector.content(for: view([nodeB]), scale: 1, parts: [removed], previous: nil)
        #expect(gone.problem == DrawingProjector.removedSentence)
    }

    @Test func anEmptyPartIsLeftOut() async throws {
        let kernel = await kernel()
        let box = try await base(kernel)
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let content = await projector.content(
            for: view([nodeA, nodeB]), scale: 1, parts: [part(nodeA, "Plate", [solid(6, from: box)]), part(nodeB, "Gasket", [])],
            previous: nil)
        #expect(content.warnings == ["“Gasket” holds nothing to draw, so this view leaves it out."])
        #expect(content.projection != nil)
        let none = await projector.content(for: view([nodeB]), scale: 1, parts: [part(nodeB, "Gasket", [])], previous: nil)
        #expect(none.problem == DrawingProjector.nothingYetSentence)
    }

    @Test func meshesWarnPerPart() async throws {
        let kernel = await kernel()
        let box = try await base(kernel)
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let content = await projector.content(
            for: view([nodeA, nodeB]), scale: 1,
            parts: [part(nodeA, "Plate", [solid(6, from: box)], meshes: 1), part(nodeB, "Board", [], meshes: 3)], previous: nil)
        #expect(content.warnings.contains("This view leaves out “Board”'s 3 meshes; drawings show solids, sheets and curves."))
        #expect(content.warnings.contains("This view leaves out “Plate”'s mesh; drawings show solids, sheets and curves."))
        #expect(!content.warnings.contains { $0.contains("holds nothing") })
    }

    @Test func allPartsMeshesIsOnlyMeshes() async throws {
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: await kernel())
        let content = await projector.content(
            for: view([nodeA]), scale: 1, parts: [part(nodeA, "Board", [], meshes: 2)], previous: nil)
        #expect(content.problem == DrawingProjector.onlyMeshesSentence)
    }

    @Test func aSharedSolidIsDrawnOnce() async throws {
        let kernel = await kernel()
        let box = try await base(kernel)
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let shared = solid(6, from: box)
        let content = await projector.content(
            for: view([nodeA, nodeB]), scale: 1, parts: [part(nodeA, "Plate", [shared]), part(nodeB, "Twin", [shared])],
            previous: nil)
        #expect(content.parts.map(\.faces) == [0..<6, 6..<6])
        #expect(content.topology?.faces.count == 6)
        #expect(content.warnings == ["“Twin” shows the same solid as “Plate”, so this view draws it once."])
    }
}
