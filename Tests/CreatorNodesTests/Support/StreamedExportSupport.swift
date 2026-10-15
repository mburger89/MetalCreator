import CreatorGraph
import CreatorImplicit
import CreatorKernel
@testable import CreatorNodes

extension Harness {
    /// A run of the graph for an export that streams: Mesh nodes hand over streams instead of meshes.
    func runStreamed(_ demand: [Node], kernel: any Kernel = FakeKernel()) async throws -> EvaluationReport {
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: kernel)
        return try await evaluator.evaluate(graph, demand: Set(demand.map(\.id)), meshQuality: .streamedExport)
    }
}

extension EvaluationReport {
    /// The one stream on `socket` of `node`.
    func meshStream(_ node: Node, _ socket: SocketName = "mesh") -> MeshStream? {
        guard let items = value(node, socket)?.items, items.count == 1, case .mesh(let payload) = items[0] else { return nil }
        return payload as? MeshStream
    }
}
