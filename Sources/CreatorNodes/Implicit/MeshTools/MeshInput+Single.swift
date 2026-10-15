import CreatorGraph
import CreatorImplicit

extension MeshInput {
    /// The one mesh a value is, and the warnings of making it: a mesh as it is, an implicit solid meshed at the Mesh node's defaults.
    /// The mesh tools (Decimate, the checks, Mesh to Solid) take their input this way.
    static func mesh(_ scalar: Scalar, socket: SocketName, context: EvalContext) async throws -> (mesh: TriangleMesh, warnings: [String]) {
        let made = try await meshes([scalar], socket: socket, context: context)
        guard let mesh = made.meshes.first else { throw NodeError.typeMismatch(socket, expected: .mesh) }
        return (mesh, made.warnings)
    }
}
