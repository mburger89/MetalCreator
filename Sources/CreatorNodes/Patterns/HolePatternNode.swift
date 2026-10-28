import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A hole at every placement (patterns spec §5): cut from the placement's origin into the part, against its normal,
/// to a depth or through everything, plain, with a counterbore or with a countersink. It is Place + Boolean
/// underneath: each distinct hole size is built once as a revolved tool and shared by every hole of that size, one
/// kernel call places all the copies, and one subtracts them. A hole whose tool misses the part doesn't fail the
/// node; it warns with the count ("3 of 24 holes miss the part.").
///
/// Every size is a list or a tree, so a hole can differ from the next (`InstanceGrid` matches them to the placements:
/// the longest flat list sets the number of holes and a shorter one repeats its last item; a tree of placements keeps
/// its rows, and a size per row is a Graft of a list). Faces of the hole at path `{i}` or `{row;i}` are tagged with that
/// path, so a fillet on its rim follows it through edits to the count, the spacing or the sizes.
public enum HolePatternNode: NodeDefinition {
    public static let typeID = "creator.holePattern"
    public static let displayName = "Hole Pattern"
    public static let category = NodeCategory.patterns
    public static let placesInstances = true
    public static let inputs = [
        SocketSpec("part", .solid),
        SocketSpec("placements", .plane, access: .tree),
        SocketSpec("diameter", .number, access: .tree, defaultValue: .number(5), unit: .millimetres, range: 0.1...100),
        SocketSpec("depth", .number, access: .tree, defaultValue: .number(10), unit: .millimetres, range: 0.1...200),
        SocketSpec("throughAll", .bool, access: .tree, defaultValue: .bool(false)),
        SocketSpec("style", .integer, access: .tree, defaultValue: .integer(0)),
        SocketSpec("counterboreDiameter", .number, access: .tree, defaultValue: .number(9), unit: .millimetres, range: 0.1...200),
        SocketSpec("counterboreDepth", .number, access: .tree, defaultValue: .number(3), unit: .millimetres, range: 0.1...200),
        SocketSpec("countersinkDiameter", .number, access: .tree, defaultValue: .number(10), unit: .millimetres, range: 0.1...200),
        SocketSpec("countersinkAngle", .number, access: .tree, defaultValue: .number(90), unit: .degrees, range: 1...179),
    ]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let inspector = [
        InspectorSection(title: "Hole", controls: [.slider("diameter"), .slider("depth"), .toggle("throughAll", label: "Through all")]),
        InspectorSection(title: "Mouth", controls: [.segmented("style", options: HoleStyle.names)]),
        InspectorSection(title: "Counterbore", controls: [.slider("counterboreDiameter"), .slider("counterboreDepth")]),
        InspectorSection(title: "Countersink", controls: [.slider("countersinkDiameter"), .slider("countersinkAngle")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        try PlacementMoves.requireSingleValues(context)
        let part = try inputs.solid("part")
        let grid = try InstanceGrid(inputs, ["placements", "diameter", "depth", "throughAll", "style", "counterboreDiameter",
                                             "counterboreDepth", "countersinkDiameter", "countersinkAngle",
        ])
        guard grid.count > 0 else { return NodeOutputs(["solid": .solid(part)]) }
        let planes = try grid.planes("placements")
        let (diameters, depths) = (try grid.numbers("diameter"), try grid.numbers("depth"))
        let (through, styles) = (try grid.bools("throughAll"), try grid.integers("style"))
        let (cbDiameters, cbDepths) = (try grid.numbers("counterboreDiameter"), try grid.numbers("counterboreDepth"))
        let (csDiameters, csAngles) = (try grid.numbers("countersinkDiameter"), try grid.numbers("countersinkAngle"))
        let reach = through.contains(true) ? ThroughReach.length(of: part, placements: planes) : 0
        var sizes: [HoleSize] = []
        for index in 0..<grid.count {
            guard let style = HoleStyle(rawValue: styles[index]) else {
                throw NodeError.invalidValue("Choose \(HoleStyle.names.formatted(.list(type: .or).locale(.messages))) for “style”.")
            }
            let size = HoleSize(diameter: diameters[index], depth: through[index] ? reach : depths[index],
                                style: style, counterbore: (cbDiameters[index], cbDepths[index]),
                                countersink: (csDiameters[index], .degrees(csAngles[index])))
            if let problem = size.problem(at: InstancePath.text(grid.items[index])) { throw NodeError.invalidValue(problem) }
            sizes.append(size)
        }
        let plan = ToolPlan(sizes: sizes)
        var built: [Solid] = []
        for size in plan.distinct {
            let profile = Profile2D.polyline(size.outline, closed: true, plane: .xz)
            built.append(try await kernel.revolve(profile, axis: .z, angle: .degrees(360), tag: context.tag))
        }
        let request = PatternApply.Request(operation: .subtract, part: part, tools: plan.toolIndex.map { built[$0] }, planes: planes,
                                           grid: grid, nouns: PatternApply.Nouns(singular: "hole", plural: "holes"))
        var outputs = try await PatternApply.run(request, kernel: kernel, context: context)
        outputs.dimensions = PatternDimensions.diameters(diameters, planes: planes)
            + PatternDimensions.depths(depths, through: through, planes: planes)
        return outputs
    }
}
