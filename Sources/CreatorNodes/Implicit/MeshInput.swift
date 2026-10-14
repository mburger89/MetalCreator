import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// The meshes a mesh socket holds. An implicit solid wired into a mesh socket is meshed at the Mesh node's default settings
/// (implicit spec §2.3), by the node that takes it: `Scalar.converted(to: .mesh)` leaves it as it is, because meshing is work that
/// needs the run's quality and can be cancelled.
enum MeshInput {
    /// Each scalar as a mesh, in order; the warnings are those of meshing the implicit ones.
    static func meshes(_ scalars: [Scalar], socket: SocketName,
                       context: EvalContext) async throws -> (meshes: [TriangleMesh], warnings: [String]) {
        var meshes: [TriangleMesh] = []
        var warnings: [String] = []
        for scalar in scalars {
            switch scalar {
            case .mesh(let payload):
                guard let mesh = payload as? TriangleMesh else { throw NodeError.typeMismatch(socket, expected: .mesh) }
                meshes.append(mesh)
            case .implicit(let reference):
                guard let solid = reference.solid else { throw NodeError.typeMismatch(socket, expected: .mesh) }
                let made = try await MeshNode.mesh(solid, exportResolution: MeshNode.defaultExportResolution, previewResolution: 0,
                                                   context: context)
                meshes.append(made.mesh)
                warnings += made.warnings
            default:
                throw NodeError.typeMismatch(socket, expected: .mesh)
            }
        }
        return (meshes, warnings)
    }
}
