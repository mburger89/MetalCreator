import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Testing

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
