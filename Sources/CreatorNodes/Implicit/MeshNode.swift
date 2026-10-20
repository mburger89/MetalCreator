import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation

/// Makes triangles from an implicit solid (implicit spec §3.6, §4.3): marching cubes over the sparse bricks the surface passes through,
/// watertight and manifold, vertices snapped to the surface. The result depends on the run (`EvalContext.meshQuality`):
/// - **Preview** (the viewport): the first pass, at 128 cells across the largest dimension, or at `preview resolution` if that is
///   coarser. The mesh remembers the solid and the target (`TriangleMesh.source`), and the app refines it in the background, pass by
///   pass, until the preview resolution (Auto: the finest that meshes in about a second).
/// - **Export**: `export resolution`, once, with a memory estimate first.
public enum MeshNode: NodeDefinition {
    public static let typeID = "creator.mesh"
    public static let displayName = "Mesh"
    public static let category = NodeCategory.mesh
    public static let readsMeshQuality = true
    /// The default settings an implicit wired into a mesh socket is meshed with (implicit spec §2.3).
    public static let defaultExportResolution = 0.1
    public static let minimumExportResolution = 0.01
    /// How far from the origin a part may reach before the warning about single-precision coordinates (implicit spec §4.2), in mm.
    static let precisionLimit = 10_000.0
    public static let inputs = [
        SocketSpec("implicit", .implicit),
        SocketSpec("export resolution", .number, defaultValue: .number(defaultExportResolution), unit: .millimetres,
                   range: minimumExportResolution...2),
        SocketSpec("preview resolution", .number, defaultValue: .number(0), unit: .millimetres, range: 0...5),
    ]
    public static let outputs = [SocketSpec("mesh", .mesh)]
    public static let inspector = [
        InspectorSection(title: "Mesh", controls: [
            .number("export resolution"), .number("preview resolution"),
            .note("A preview resolution of 0 is Auto: the finest that meshes in about a second."),
        ]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solid = try inputs.implicitSolid("implicit")
        let (export, preview) = (try inputs.number("export resolution"), try inputs.number("preview resolution"))
        guard export.isFinite, export >= minimumExportResolution else {
            let smallest = minimumExportResolution.millimetreText(locale: .messages)
            throw NodeError.invalidValue("“export resolution” must be at least \(smallest) mm.")
        }
        guard preview.isFinite, preview >= 0 else { throw NodeError.invalidValue("“preview resolution” must be 0 (Auto) or more.") }
        let made = try await mesh(solid, exportResolution: export, previewResolution: preview, context: context)
        return NodeOutputs(["mesh": .mesh(made.mesh)], warnings: made.warnings)
    }

    /// The mesh of `solid` for this run (a `MeshStream` while an export streams), and what is worth saying about how it was made.
    /// `previewResolution` 0 is Auto.
    static func mesh(_ solid: ImplicitSolid, exportResolution: Double, previewResolution: Double,
                     context: EvalContext) async throws -> (mesh: any MeshPayload, warnings: [String]) {
        let selection = await ImplicitEvaluators.make(for: solid, choice: context.implicitEngine)
        let mesher = ImplicitMesher(evaluator: selection.evaluator)
        var warnings = selection.warning.map { [$0] } ?? []
        // The GPU works in single precision (implicit spec §4.2): a part this far out is blurred.
        let box = solid.bounds
        let farthest = [box.min, box.max].flatMap { [abs($0.x), abs($0.y), abs($0.z)] }.max() ?? 0
        if farthest > precisionLimit {
            let reach = farthest.formatted(.number.precision(.fractionLength(0)).locale(.messages))
            warnings.append("This part reaches \(reach) mm from the origin; beyond 10,000 mm the GPU's single-precision "
                + "coordinates blur its surface.")
        }
        let progress = context.meshProgress
        do {
            switch context.meshQuality {
            case .export:
                let mesh = try await mesher.mesh(solid, resolution: exportResolution, quality: .export) { progress($0) }
                return (mesh, warnings)
            case .streamedExport:
                // Nothing is meshed here: the writer meshes the stream window by window, so the mesh is not the limit, but the
                // octree of bricks it walks still has to fit.
                try await MeshingBudget().check(solid, resolution: exportResolution, using: selection.evaluator,
                                                bytesPerBrick: MeshingBudget.streamedBytesPerBrick)
                return (MeshStream(solid: solid, resolution: exportResolution), warnings)
            case .preview:
                let target: PreviewSchedule.Target = previewResolution > 0 ? .fixed(previewResolution) : .automatic
                let first = PreviewSchedule(target).firstResolution(for: solid.bounds)
                let mesh = try await mesher.mesh(solid, resolution: first, quality: .preview,
                                                 source: MeshSource(solid: solid, target: target)) { progress($0) }
                return (mesh, warnings)
            }
        } catch let error as ImplicitMeshingError {
            throw NodeError.invalidValue(error.userMessage)
        }
    }
}
