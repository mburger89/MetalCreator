import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// Fills a region with a triply periodic minimal surface (implicit spec §3.4): a gyroid, Schwarz P, diamond, Neovius or Lidinoid
/// sheet (a wall of `thickness` between two volumes) or network (one of the volumes). The cell size and the thickness are fields, so
/// a 7b field can grade them. With a `skin` the region keeps a wall of that thickness and the lattice fills the inside.
public enum TPMSNode: NodeDefinition {
    public static let typeID = "creator.tpms"
    /// 2: `blend` (7c-3f, Errata D18). A node saved as version 1 reads it as 0, the sharp join it was made with.
    public static let typeVersion = 2
    public static let displayName = "TPMS"
    public static let category = NodeCategory.implicit
    public static let inputs = [
        SocketSpec("region", .implicit, optional: true),
        SocketSpec("skin", .number, defaultValue: .number(0), unit: .millimetres, range: 0...20),
        LatticeSetup.blendSocket,
        SocketSpec("type", .integer, defaultValue: .integer(TPMSType.gyroid.rawValue)),
        SocketSpec("form", .integer, defaultValue: .integer(TPMSForm.sheet.rawValue)),
        SocketSpec("cell size", .field, defaultValue: .number(8), unit: .millimetres, range: 1...50),
        SocketSpec("cell stretch", .vector, defaultValue: .vector(Vector3(1, 1, 1))),
        SocketSpec("thickness", .field, defaultValue: .number(1), unit: .millimetres, range: 0...10),
    ]
    public static let outputs = [SocketSpec("implicit", .implicit)]
    /// The resolution warnings differ between a preview and an export, so the cache keys the node by the mesh quality.
    public static let readsMeshQuality = true
    public static let help = "Where the cell size field changes fast the pattern stretches, and the preview gets slower: the "
        + "lipschitz bound grows with the field's slope. A network's thickness moves the level, so 0 fills half the region. "
        + "“blend” rounds the join between the skin and the lattice; it does nothing without a skin."
    public static let inspector = [
        InspectorSection(title: "Surface", controls: [
            .segmented("type", options: TPMSType.options), .segmented("form", options: TPMSForm.options),
        ]),
        InspectorSection(title: "Cells", controls: [.number("cell size"), .vector("cell stretch")]),
        InspectorSection(title: "Wall", controls: [.number("thickness"), .number("skin"), .number("blend"), .note(help)]),
    ]

    public static func migrate(_ node: Node, from version: Int) -> Node { LatticeSetup.sharpJoin(node) }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let region = try LatticeSetup.region(inputs)
        let skin = try LatticeSetup.skin(inputs)
        let join = try LatticeSetup.blend(inputs)
        let type = TPMSType(rawValue: try inputs.choice("type", options: TPMSType.options)) ?? .gyroid
        let form = TPMSForm(rawValue: try inputs.choice("form", options: TPMSForm.options)) ?? .sheet
        let box = region.bounds
        let (cells, cellWarnings) = try await LatticeSetup.cells(inputs, over: box, kernel: kernel, context: context)
        let wall = try await LatticeSetup.grading(inputs, "thickness", over: box, kernel: kernel, context: context)

        let lattice = ImplicitSolid.tpms(TPMSLattice(type: type, form: form, cells: cells, thickness: wall.grading, region: box))
        let voxel = LatticeSetup.voxel(over: box, context: context)
        var warnings = cellWarnings + wall.warnings + LatticeSetup.cellWarnings(cells, voxel: voxel)
        if form == .sheet { warnings += LatticeSetup.thinWarnings("Walls", thickest: wall.grading.range.upperBound, voxel: voxel) }
        warnings += ImplicitReach.warnings(for: region, reachedBy: skin)
        let result = LatticeFill.fill(region: region, lattice: lattice, skin: skin, blend: join)
        return NodeOutputs(["implicit": .implicit(result.reference)], warnings: warnings)
    }
}
