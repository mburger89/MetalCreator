// Test fixture file: readers of field outputs and a sampling shortcut, shared by the field nodes' tests.
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

extension EvaluationReport {
    /// The one field on an output, or `nil` when it holds none or several.
    func field(_ node: Node, _ socket: SocketName = "field") -> Field? {
        if case .one(.field(let field))? = value(node, socket) { field } else { nil }
    }

    /// Every field on an output, in order (a list of fields from a broadcast).
    func fields(_ node: Node, _ socket: SocketName = "field") -> [Field] {
        (value(node, socket)?.items ?? []).compactMap { if case .field(let field) = $0 { field } else { nil } }
    }
}

/// `field` sampled at `points` (the field must exist).
func sampled(_ field: Field?, at points: [Vector3], kernel: any Kernel = FakeKernel()) async throws -> [Double] {
    let field = try #require(field, "the node made no field")
    return try await FieldSampler.sample(field, at: points, kernel: kernel)
}
