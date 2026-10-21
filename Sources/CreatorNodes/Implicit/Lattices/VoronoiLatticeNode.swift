import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// Fills a region with the cell edges (Struts) or the cell walls (Foam) of a Voronoi diagram (implicit spec §3.4). The seeds are a
/// point list from any source (a vector or a plane's origin), or, when `seeds` is unconnected, `count` built-in seeds placed by
/// `density` and `seed` (`VoronoiSeedSource`). `thickness` is the strut diameter or the wall thickness, a field.
public enum VoronoiLatticeNode: NodeDefinition {
    public static let typeID = "creator.voronoiLattice"
    /// 2: `blend` (7c-3f, Errata D18). A node saved as version 1 reads it as 0, the sharp join it was made with.
    public static let typeVersion = 2
    public static let displayName = "Voronoi Lattice"
    public static let category = NodeCategory.implicit
    public static let inputs = [
        SocketSpec("region", .implicit, optional: true),
        SocketSpec("skin", .number, defaultValue: .number(0), unit: .millimetres, range: 0...20),
        LatticeSetup.blendSocket,
        SocketSpec("seeds", .plane, access: .list, optional: true),
        SocketSpec("form", .integer, defaultValue: .integer(VoronoiForm.struts.rawValue)),
        SocketSpec("thickness", .field, defaultValue: .number(0.8), unit: .millimetres, range: 0...10),
        SocketSpec("count", .integer, defaultValue: .integer(100), unit: .count),
        SocketSpec("density", .field, defaultValue: .number(1), range: 0...1),
        SocketSpec("seed", .integer, defaultValue: .integer(0)),
    ] + LatticeMappingSetup.sockets
    public static let outputs = [SocketSpec("implicit", .implicit)]
    /// The warnings about cells and walls depend on the voxel size, which differs between preview and export.
    public static let readsMeshQuality = true
    public static let help = "Wire points into “seeds”, or leave it unconnected for “count” seeds placed at random where “density” "
        + "(a field, 0 to 1) says. Changing the seed or the density moves every seed. "
        + "“blend” rounds the join between the skin and the lattice; it does nothing without a skin."
    private static let sections = [
        InspectorSection(title: "Form", controls: [.segmented("form", options: VoronoiForm.options), .number("thickness")]),
        InspectorSection(title: "Seeds", controls: [.integer("count"), .number("density"), .integer("seed"), .note(help)]),
        InspectorSection(title: "Skin", controls: [.number("skin"), .number("blend")]),
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
        let form = VoronoiForm(rawValue: try inputs.choice("form", options: VoronoiForm.options)) ?? .struts
        let box = region.bounds
        let wall = try await LatticeSetup.grading(inputs, "thickness", over: box, kernel: kernel, context: context)
        let (points, seedWarnings) = try await seeds(inputs, box: box, kernel: kernel, context: context)
        let mapped = try LatticeMappingSetup.make(inputs, region: region, cells: nil)

        // The seeds are placed in the region as before and then put through the mapping, so a density field is read where the seed is.
        let seedGrid = VoronoiSeeds.mapped(points: points, mapping: mapped.mapping, region: box)
        let lattice = ImplicitSolid.voronoi(VoronoiLattice(seeds: seedGrid, form: form, thickness: wall.grading, region: box,
                                                           mapping: mapped.mapping))
        var warnings = seedWarnings + wall.warnings + mapped.warnings
        if seedGrid.uncoveredFraction(in: box, mapping: mapped.mapping) > 0 {
            warnings.append("The seeds leave gaps in the region; the lattice is solid there.")
        }
        let voxel = LatticeSetup.voxel(over: box, context: context)
        warnings += LatticeSetup.cellWarnings(spacing: seedGrid.radius / 2, voxel: voxel)
        let noun = form == .struts ? "Struts" : "Walls"
        warnings += LatticeSetup.thinWarnings(noun, thickest: wall.grading.range.upperBound, voxel: voxel)
        warnings += ImplicitReach.warnings(for: region, reachedBy: skin)
        let result = LatticeFill.fill(region: region, lattice: lattice, skin: skin, blend: join)
        return NodeOutputs(["implicit": .implicit(result.reference)], warnings: warnings)
    }

    /// The seeds: the wired points, else the built-in ones.
    private static func seeds(_ inputs: NodeInputs, box: BoundingBox, kernel: any Kernel,
                              context: EvalContext) async throws -> (points: [Vector3], warnings: [String]) {
        let limit = VoronoiSeedSource.maximumCount
        guard inputs.has("seeds") else {
            let count = try inputs.integer("count")
            guard (1...limit).contains(count) else {
                throw NodeError.invalidValue("“count” must be between 1 and \(limit.display).")
            }
            let made = try await VoronoiSeedSource.points(count: count, density: try inputs.field("density"),
                                                          seed: try inputs.integer("seed"), in: box, kernel: kernel,
                                                          cache: context.fieldDistances)
            return (made.points, made.warnings)
        }
        let items = try inputs.list("seeds")
        guard !items.isEmpty else {
            throw NodeError.invalidValue("“seeds” has no points. Wire some in, or disconnect it to use “count” seeds.")
        }
        guard items.count <= limit else {
            throw NodeError.invalidValue("A Voronoi lattice takes at most \(limit.display) seeds; “seeds” has \(items.count.display).")
        }
        let points = try items.map { item -> Vector3 in
            switch item {
            case .vector(let point): point
            case .plane(let plane): plane.origin
            default: throw NodeError.typeMismatch("seeds", expected: .plane)
            }
        }
        guard points.allSatisfy(\.isFinite) else { throw NodeError.invalidValue("“seeds” has a point that isn't a finite position.") }
        return (points, [])
    }
}
