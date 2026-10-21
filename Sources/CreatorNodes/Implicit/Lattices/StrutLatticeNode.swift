import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// Fills a region with straight struts of one of six unit cells (implicit spec §3.4): cubic, BCC, FCC, octet, Kelvin or diamond. The
/// cell size and the strut radius are fields; `node blend` rounds the joints. With a `skin` the region keeps a wall of that thickness.
public enum StrutLatticeNode: NodeDefinition {
    public static let typeID = "creator.strutLattice"
    /// 2: `blend` (7c-3f, Errata D18). A node saved as version 1 reads it as 0, the sharp join it was made with.
    public static let typeVersion = 2
    public static let displayName = "Strut Lattice"
    public static let category = NodeCategory.implicit
    public static let inputs = [
        SocketSpec("region", .implicit, optional: true),
        SocketSpec("skin", .number, defaultValue: .number(0), unit: .millimetres, range: 0...20),
        LatticeSetup.blendSocket,
        SocketSpec("cell", .integer, defaultValue: .integer(StrutCell.cubic.rawValue)),
        SocketSpec("cell size", .field, defaultValue: .number(8), unit: .millimetres, range: 1...50),
        SocketSpec("cell stretch", .vector, defaultValue: .vector(Vector3(1, 1, 1))),
        SocketSpec("strut radius", .field, defaultValue: .number(0.6), unit: .millimetres, range: 0...5),
        SocketSpec("node blend", .number, defaultValue: .number(0), unit: .millimetres, range: 0...5),
    ] + LatticeMappingSetup.sockets
    public static let outputs = [SocketSpec("implicit", .implicit)]
    /// The warnings about cells and walls depend on the voxel size, which differs between preview and export.
    public static let readsMeshQuality = true
    public static let help = "Where the cell size field changes fast the pattern stretches, and the preview gets slower: the "
        + "lipschitz bound grows with the field's slope. A node blend of up to a quarter of the smallest cell is allowed. "
        + "“blend” rounds the join between the skin and the lattice; it does nothing without a skin."
    private static let sections = [
        InspectorSection(title: "Cell", controls: [.segmented("cell", options: StrutCell.options)]),
        InspectorSection(title: "Size", controls: [.number("cell size"), .vector("cell stretch")]),
        InspectorSection(title: "Struts", controls: [
            .number("strut radius"), .number("node blend"), .number("skin"), .number("blend"), .note(help),
        ]),
    ]
    public static let inspector = LatticeMappingSetup.inspector(base: sections, kind: .straight)

    /// The Mapping section shows the inputs of the mapping this node is set to and no others.
    public static func inspector(for node: Node) -> [InspectorSection] {
        LatticeMappingSetup.inspector(base: sections, kind: LatticeMappingSetup.kind(of: node))
    }

    public static func migrate(_ node: Node, from version: Int) -> Node { LatticeSetup.sharpJoin(node) }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let region = try LatticeSetup.region(inputs)
        let skin = try LatticeSetup.skin(inputs)
        let join = try LatticeSetup.blend(inputs)
        let cell = StrutCell(rawValue: try inputs.choice("cell", options: StrutCell.options)) ?? .cubic
        let box = region.bounds
        let (cells, cellWarnings) = try await LatticeSetup.cells(inputs, over: box, kernel: kernel, context: context)
        let radius = try await LatticeSetup.grading(inputs, "strut radius", over: box, kernel: kernel, context: context)
        let blend = try inputs.number("node blend")
        let limit = cells.smallest * cells.smallestStretch / 4
        guard blend.isFinite, blend >= 0, blend <= limit else {
            throw NodeError.invalidValue("“node blend” must be between 0 and a quarter of the smallest cell "
                + "(\(limit.millimetreText(locale: .messages)) mm).")
        }

        let mapped = try LatticeMappingSetup.make(inputs, region: region, cells: cells)

        let lattice = ImplicitSolid.struts(StrutLattice(cell: cell, cells: cells, radius: radius.grading, blend: blend, region: box,
                                                        mapping: mapped.mapping))
        let voxel = LatticeSetup.voxel(over: box, context: context)
        var warnings = cellWarnings + radius.warnings + mapped.warnings + LatticeSetup.cellWarnings(cells, voxel: voxel)
        warnings += LatticeSetup.thinWarnings("Struts", thickest: 2 * radius.grading.range.upperBound, voxel: voxel)
        // A radius past `reachInCells` of the smallest cell edge makes `min(nearest, reach) - radius` negative everywhere: solid.
        if radius.grading.range.upperBound >= StrutLattice.reachInCells * cells.smallest * cells.smallestStretch {
            warnings.append("Struts are thicker than the cells; the lattice is solid.")
        }
        warnings += ImplicitReach.warnings(for: region, reachedBy: skin)
        let result = LatticeFill.fill(region: region, lattice: lattice, skin: skin, blend: join)
        return NodeOutputs(["implicit": .implicit(result.reference)], warnings: warnings)
    }
}
