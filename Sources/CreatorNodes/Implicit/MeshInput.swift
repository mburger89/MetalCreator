import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// The meshes a mesh socket holds. An implicit solid wired into a mesh socket is meshed at the Mesh node's default settings
/// (implicit spec §2.3), by the node that takes it: `Scalar.converted(to: .mesh)` leaves it as it is, because meshing is work that
/// needs the run's quality and can be cancelled. While an export streams (`MeshQuality.streamedExport`) nothing is meshed here: the
/// implicit becomes a `MeshStream` that the writer meshes window by window.
enum MeshInput {
    /// Each scalar as a mesh payload, in order (a `TriangleMesh`, or a `MeshStream` while an export streams); the warnings are those of
    /// meshing the implicit ones.
    static func payloads(_ scalars: [Scalar], socket: SocketName,
                         context: EvalContext) async throws -> (payloads: [any MeshPayload], warnings: [String]) {
        var payloads: [any MeshPayload] = []
        var warnings: [String] = []
        for scalar in scalars {
            switch scalar {
            case .mesh(let payload):
                guard payload is TriangleMesh || payload is MeshStream else { throw NodeError.typeMismatch(socket, expected: .mesh) }
                payloads.append(payload)
            case .implicit(let reference):
                guard let solid = reference.solid else { throw NodeError.typeMismatch(socket, expected: .mesh) }
                let made = try await MeshNode.mesh(solid, exportResolution: MeshNode.defaultExportResolution, previewResolution: 0,
                                                   context: context)
                payloads.append(made.mesh)
                warnings += made.warnings
            default:
                throw NodeError.typeMismatch(socket, expected: .mesh)
            }
        }
        return (payloads, warnings)
    }

    /// The one mesh a scalar is, as a `MeshValue`, and the warnings of making it.
    static func value(_ scalar: Scalar, socket: SocketName, context: EvalContext) async throws -> (value: MeshValue, warnings: [String]) {
        let made = try await payloads([scalar], socket: socket, context: context)
        switch made.payloads.first {
        case let mesh as TriangleMesh: return (.mesh(mesh), made.warnings)
        case let stream as MeshStream: return (.stream(stream), made.warnings)
        default: throw NodeError.typeMismatch(socket, expected: .mesh)
        }
    }

    /// What a check works on.
    struct Checkable {
        /// The surface to check, in memory.
        var mesh: TriangleMesh
        /// What the warning says about how exact the check is; `nil` when it is exact.
        var label: String?
        /// The stream the mesh is a copy of, when an export is streaming: the check goes on to pass this to the file.
        var stream: MeshStream?
        var warnings: [String]
    }

    /// A scalar as a mesh in memory for a node that needs the whole surface. A stream is meshed again as a copy
    /// (`MeshStream.checkCopy`).
    static func checkable(_ scalar: Scalar, socket: SocketName, context: EvalContext) async throws -> Checkable {
        let (value, warnings) = try await Self.value(scalar, socket: socket, context: context)
        switch value {
        case .mesh(let mesh):
            return Checkable(mesh: mesh, label: CheckWording.label(for: mesh), stream: nil, warnings: warnings)
        case .stream(let stream):
            let selection = await ImplicitEvaluators.make(for: stream.solid, choice: context.implicitEngine)
            do {
                let copy = try await stream.checkCopy(using: selection.evaluator)
                return Checkable(mesh: copy.mesh, label: copy.isExact ? nil : CheckWording.coarseLabel, stream: stream,
                                 warnings: warnings)
            } catch let error as ImplicitMeshingError {
                throw NodeError.invalidValue(error.userMessage)
            }
        }
    }

    /// A scalar as a mesh in memory, at most `limit` triangles, for Mesh to Solid. A stream is meshed into memory with its stages
    /// applied; past the limit it says how many triangles it has.
    static func collected(_ scalar: Scalar, socket: SocketName, limit: Int,
                          context: EvalContext) async throws -> (mesh: TriangleMesh, warnings: [String]) {
        let (value, warnings) = try await Self.value(scalar, socket: socket, context: context)
        switch value {
        case .mesh(let mesh):
            return (mesh, warnings)
        case .stream(let stream):
            let selection = await ImplicitEvaluators.make(for: stream.solid, choice: context.implicitEngine)
            do {
                return (try await stream.materialized(limit: limit, using: selection.evaluator), warnings)
            } catch let MeshStream.Failure.tooManyTriangles(count) {
                try MeshToSolidNode.requireWithinLimit(count)
                throw NodeError.invalidValue("Mesh has too many triangles.")
            } catch let error as ImplicitMeshingError {
                throw NodeError.invalidValue(error.userMessage)
            }
        }
    }
}
