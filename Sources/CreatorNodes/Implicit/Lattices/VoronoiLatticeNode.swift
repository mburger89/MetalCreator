import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// Fills a region with the cell edges (Struts) or the cell walls (Foam) of a Voronoi diagram (implicit spec §3.4). The seeds are a
/// point list from any source (a vector or a plane's origin), or, when `seeds` is unconnected, `count` built-in seeds placed by
/// `density` and `seed` (`VoronoiSeedSource`). `thickness` is the strut diameter or the wall thickness, a field.
public enum VoronoiLatticeNode: NodeDefinition {
    public static let typeID = "creator.voronoiLattice"
    public static let displayName = "Voronoi Lattice"
    public static let category = NodeCategory.implicit
    public static let inputs = [
        SocketSpec("region", .implicit, optional: true),
        SocketSpec("skin", .number, defaultValue: .number(0), unit: .millimetres, range: 0...20),
        SocketSpec("seeds", .plane, access: .list, optional: true),
        SocketSpec("form", .integer, defaultValue: .integer(VoronoiForm.struts.rawValue)),
        SocketSpec("thickness", .field, defaultValue: .number(0.8), unit: .millimetres, range: 0...10),
        SocketSpec("count", .integer, defaultValue: .integer(100), unit: .count),
        SocketSpec("density", .field, defaultValue: .number(1), range: 0...1),
        SocketSpec("seed", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("implicit", .implicit)]
    public static let help = "Wire points into “seeds”, or leave it unconnected for “count” seeds placed at random where “density” "
        + "(a field, 0 to 1) says. Changing the seed or the density moves every seed."
    public static let inspector = [
        InspectorSection(title: "Form", controls: [.segmented("form", options: VoronoiForm.options), .number("thickness")]),
        InspectorSection(title: "Seeds", controls: [.integer("count"), .number("density"), .integer("seed"), .note(help)]),
        InspectorSection(title: "Skin", controls: [.number("skin")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let region = try LatticeSetup.region(inputs)
        let skin = try LatticeSetup.skin(inputs)
        let form = VoronoiForm(rawValue: try inputs.choice("form", options: VoronoiForm.options)) ?? .struts
        let box = region.bounds
        let wall = try await LatticeSetup.grading(inputs, "thickness", over: box, kernel: kernel, context: context)
        let (points, seedWarnings) = try await seeds(inputs, box: box, kernel: kernel, context: context)

        let seedGrid = VoronoiSeeds(points: points, radius: VoronoiSeeds.searchRadius(count: points.count, in: box))
        let lattice = ImplicitSolid.voronoi(VoronoiLattice(seeds: seedGrid, form: form, thickness: wall.grading, region: box))
        var warnings = seedWarnings + wall.warnings
        if seedGrid.uncoveredFraction(in: box) > 0 {
            warnings.append("The seeds leave gaps in the region; the lattice is solid there.")
        }
        let voxel = LatticeSetup.voxel(over: box, context: context)
        warnings += LatticeSetup.cellWarnings(spacing: seedGrid.radius / 2, voxel: voxel)
        let noun = form == .struts ? "Struts" : "Walls"
        warnings += LatticeSetup.thinWarnings(noun, thickest: wall.grading.range.upperBound, voxel: voxel)
        warnings += ImplicitReach.warnings(for: region, reachedBy: skin)
        let result = LatticeFill.fill(region: region, lattice: lattice, skin: skin)
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
