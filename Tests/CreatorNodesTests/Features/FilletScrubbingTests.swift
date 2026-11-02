import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// A drag previews a Curvature (G2) fillet as its circular one; the evaluation after it builds the G2 surface.
struct FilletScrubbingTests {
    func filletOnABox(continuity: Int) -> (h: Harness, fillet: Node) {
        var h = Harness()
        let box = h.box(10, 20, 30)
        let vertical = h.add(EdgesByDirectionNode.self)
        h.wire(box, "solid", to: vertical, "solid")
        let fillet = h.add(FilletNode.self, ["continuity": .integer(continuity), "tangency weight": .number(1.4)])
        h.wire(vertical, "edges", to: fillet, "edges")
        return (h, fillet)
    }

    @Test func aG2FilletPreviewsCircularWhileScrubbing() async throws {
        let (h, fillet) = filletOnABox(continuity: 1)
        let kernel = FakeKernel()
        let report = try await Evaluator(registry: BuiltInNodes.registry, kernel: kernel)
            .evaluate(h.graph, demand: [fillet.id], isScrubbing: true)
        #expect(report.isOK(fillet))
        #expect(await kernel.filletProfiles == [.circular])
    }

    @Test func aG2FilletIsG2WhenNotScrubbing() async throws {
        let (h, fillet) = filletOnABox(continuity: 1)
        let kernel = FakeKernel()
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: kernel)
        _ = try await evaluator.evaluate(h.graph, demand: [fillet.id], isScrubbing: true)
        _ = try await evaluator.evaluate(h.graph, demand: [fillet.id], isScrubbing: false)
        #expect(await kernel.filletProfiles == [.circular, .curvatureContinuous(weight: 1.4)])
    }

    @Test func aG1FilletIsTheSameWhileScrubbing() async throws {
        let (h, fillet) = filletOnABox(continuity: 0)
        let kernel = FakeKernel()
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: kernel)
        _ = try await evaluator.evaluate(h.graph, demand: [fillet.id], isScrubbing: false)
        let second = try await evaluator.evaluate(h.graph, demand: [fillet.id], isScrubbing: true)
        #expect(!second.evaluatedNodes.contains(fillet.id))
        #expect(await kernel.filletProfiles == [.circular])
    }
}
