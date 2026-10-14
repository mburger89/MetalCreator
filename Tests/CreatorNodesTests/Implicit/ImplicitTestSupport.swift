import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing
@testable import CreatorNodes

extension Value {
    /// The implicit solids carried, or `nil` if any item isn't one.
    var implicitSolids: [ImplicitSolid]? {
        typed { if case .implicit(let reference) = $0 { reference.solid } else { nil } }
    }
}

extension EvaluationReport {
    /// The one implicit solid on `socket` of `node`.
    func implicitSolid(_ node: Node, _ socket: SocketName = "implicit") -> ImplicitSolid? {
        guard let solids = value(node, socket)?.implicitSolids, solids.count == 1 else { return nil }
        return solids[0]
    }
}

extension ImplicitSolid {
    func distance(_ x: Double, _ y: Double, _ z: Double) -> Double { signedDistance(at: Vector3(x, y, z)) }
}

extension Value {
    /// The triangle meshes carried, or `nil` if any item isn't one.
    var triangleMeshes: [TriangleMesh]? {
        typed { if case .mesh(let payload) = $0 { payload as? TriangleMesh } else { nil } }
    }
}

extension EvaluationReport {
    /// The one mesh on `socket` of `node`.
    func triangleMesh(_ node: Node, _ socket: SocketName = "mesh") -> TriangleMesh? {
        guard let meshes = value(node, socket)?.triangleMeshes, meshes.count == 1 else { return nil }
        return meshes[0]
    }
}

extension Harness {
    /// A run of the graph for an export: Mesh nodes work at their export resolution.
    func runForExport(_ demand: [Node], kernel: any Kernel = FakeKernel()) async throws -> EvaluationReport {
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: kernel)
        return try await evaluator.evaluate(graph, demand: Set(demand.map(\.id)), meshQuality: .export)
    }
}
