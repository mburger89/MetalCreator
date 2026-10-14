import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// What the three lattice nodes read and say in the same way (implicit spec §3.4): the region and the skin, the cell size and its
/// stretch, and the warnings about cells and walls too small for the resolution.
enum LatticeSetup {
    static let noRegion = "Connect a region to fill."

    /// The `region` input, an implicit solid with a box to fill.
    static func region(_ inputs: NodeInputs) throws -> ImplicitSolid {
        guard inputs.has("region") else { throw NodeError.invalidValue(noRegion) }
        let region = try inputs.implicitSolid("region")
        let size = region.bounds.size
        guard size.x > 0, size.y > 0, size.z > 0 else { throw NodeError.invalidValue("The region has no volume to fill.") }
        return region
    }

    /// The `skin`, in millimetres.
    static func skin(_ inputs: NodeInputs) throws -> Double {
        let skin = try inputs.number("skin")
        guard skin.isFinite, skin >= 0 else { throw NodeError.invalidValue("“skin” must be 0 or more.") }
        return skin
    }

    /// The `cell size` field and the `cell stretch` of a lattice over `box`.
    static func cells(_ inputs: NodeInputs, over box: BoundingBox, kernel: any Kernel,
                      context: EvalContext) async throws -> (cells: LatticeCells, warnings: [String]) {
        let stretch = try inputs.vector("cell stretch")
        guard stretch.isFinite, stretch.x > 0, stretch.y > 0, stretch.z > 0 else {
            throw NodeError.invalidValue("“cell stretch” must be greater than 0 on every axis.")
        }
        let setting = try await ImplicitGrading.make(try inputs.field("cell size"), named: "cell size",
                                                     over: ImplicitGrading.region(around: box), holdsAtZero: false, kernel: kernel,
                                                     context: context)
        let smallest = setting.grading.range.lowerBound
        guard smallest.isFinite, smallest > 0 else {
            throw NodeError.invalidValue("“cell size” must stay above 0 mm; it reaches \(smallest.millimetreText(locale: .messages)) mm.")
        }
        return (LatticeCells(size: setting.grading, stretch: stretch), setting.warnings)
    }

    /// A graded setting (a thickness, a strut radius) over `box`: held at 0 where it is below it, with the warning.
    static func grading(_ inputs: NodeInputs, _ name: SocketName, over box: BoundingBox, kernel: any Kernel,
                        context: EvalContext) async throws -> ImplicitGrading.Result {
        try await ImplicitGrading.make(try inputs.field(name), named: name, over: ImplicitGrading.region(around: box), holdsAtZero: true,
                                       kernel: kernel, context: context)
    }

    // MARK: Resolution

    /// The voxel size the lattice is first drawn at, and what to call it: the first preview pass in the viewport, the Mesh node's
    /// default export resolution in an export (the lattice does not know the Mesh node's setting).
    static func voxel(over box: BoundingBox, context: EvalContext) -> (size: Double, name: String) {
        switch context.meshQuality {
        case .preview: (PreviewSchedule(.automatic).firstResolution(for: box), "preview")
        case .export: (MeshNode.defaultExportResolution, "export")
        }
    }

    /// "Cells are smaller than the preview resolution; the preview may look solid." when a cell is under two voxels.
    static func cellWarnings(_ cells: LatticeCells, voxel: (size: Double, name: String)) -> [String] {
        cellWarnings(spacing: cells.smallest * cells.smallestStretch, voxel: voxel)
    }

    /// The same, for cells about `spacing` millimetres across.
    static func cellWarnings(spacing smallestEdge: Double, voxel: (size: Double, name: String)) -> [String] {
        guard smallestEdge < 2 * voxel.size else { return [] }
        let result = voxel.name == "preview" ? "the preview may look solid" : "the mesh may look solid"
        return ["Cells are smaller than the \(voxel.name) resolution; \(result)."]
    }

    /// "Walls are thinner than the preview resolution; the preview may show gaps." when even the thickest part is under a voxel.
    /// - Parameter thickness: the thickest the walls or struts get, in millimetres (a strut's diameter, not its radius).
    static func thinWarnings(_ noun: String, thickest thickness: Double, voxel: (size: Double, name: String)) -> [String] {
        guard thickness < voxel.size else { return [] }
        let result = voxel.name == "preview" ? "the preview may show gaps" : "the mesh may show gaps"
        return ["\(noun) are thinner than the \(voxel.name) resolution; \(result)."]
    }
}
