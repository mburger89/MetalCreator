import Foundation
import Synchronization
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// `EvalContext.meshQuality`, `implicitEngine` and `meshProgress` (implicit spec §4.3, §5.3), and what they do to the cache.
struct MeshContextTests {
    func evaluator(_ engine: ImplicitEngineChoice = .cpu) -> Evaluator {
        Evaluator(registry: meshProbeRegistry, kernel: FakeKernel(), implicitEngine: engine)
    }

    /// The integer output `socket` of `node` in `report`.
    func integer(_ report: EvaluationReport, _ node: Node, _ socket: SocketName) -> Int? {
        if case .one(.integer(let value))? = report.results[node.id]?.outputs?[socket] { value } else { nil }
    }

    @Test func aContextMadeByHandPreviewsOnTheCPUAndIgnoresProgress() {
        let context = EvalContext(node: makeNode(PlainProbeNode.self), item: 0, parameters: [:])
        #expect(context.meshQuality == .preview && context.implicitEngine == .cpu)
        context.meshProgress(0.5)
    }

    @Test func theEvaluatorHandsTheQualityAndTheEngineToEveryNode() async throws {
        let probe = makeNode(QualityProbeNode.self, output: true)
        let graph = graph([probe])
        let preview = try await evaluator().evaluate(graph, demand: [probe.id])
        #expect(integer(preview, probe, "quality") == 0)
        let export = try await evaluator(.automatic).evaluate(graph, demand: [probe.id], meshQuality: .export)
        #expect(integer(export, probe, "quality") == 1)
        #expect(integer(export, probe, "engine") == 1)
        #expect(integer(preview, probe, "engine") == 0)
    }

    @Test func aNodeThatReadsTheQualityDoesNotShareAResultAcrossQualities() async throws {
        let probe = makeNode(QualityProbeNode.self, output: true)
        let graph = graph([probe])
        let one = evaluator()
        let first = try await one.evaluate(graph, demand: [probe.id])
        #expect(first.evaluatedNodes == [probe.id])
        let again = try await one.evaluate(graph, demand: [probe.id])
        #expect(again.evaluatedNodes.isEmpty, "the same quality is cached")
        let export = try await one.evaluate(graph, demand: [probe.id], meshQuality: .export)
        #expect(export.evaluatedNodes == [probe.id], "another quality runs it again")
        #expect(integer(export, probe, "quality") == 1)
        let back = try await one.evaluate(graph, demand: [probe.id])
        #expect(integer(back, probe, "quality") == 0)
    }

    @Test func aNodeThatDoesNotReadTheQualityKeepsItsCachedResult() async throws {
        let probe = makeNode(PlainProbeNode.self, output: true)
        let graph = graph([probe])
        let one = evaluator()
        _ = try await one.evaluate(graph, demand: [probe.id])
        let export = try await one.evaluate(graph, demand: [probe.id], meshQuality: .export)
        #expect(export.evaluatedNodes.isEmpty)
    }

    @Test func progressReachesTheCaller() async throws {
        let probe = makeNode(QualityProbeNode.self, output: true)
        let seen = Mutex<[Double]>([])
        _ = try await evaluator().evaluate(graph([probe]), demand: [probe.id], progress: MeshProgress { fraction in
            seen.withLock { $0.append(fraction) }
        })
        #expect(seen.withLock { $0 } == [0.25, 0.75])
    }

    @Test func progressIsHeldBetweenZeroAndOne() {
        let seen = Mutex<[Double]>([])
        let progress = MeshProgress { fraction in seen.withLock { $0.append(fraction) } }
        progress(-1)
        progress(2)
        #expect(seen.withLock { $0 } == [0, 1])
    }

    @MainActor
    @Test func aDocumentTakesTheEngine() async {
        let document = DocumentModel(registry: meshProbeRegistry, kernel: FakeKernel(), implicitEngine: .automatic)
        await document.waitForEvaluation()
        #expect(document.graph.nodes.isEmpty)
    }
}
