import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A boss or pin at every placement (patterns spec §5): standing on the placement's origin and growing along its
/// normal, with an optional draft (the sides lean in towards the tip) and a rounded tip, unioned onto the part. It is
/// Place + Boolean underneath: each distinct size is built once as a revolved tool (its tip rounded by one Fillet) and
/// shared by every boss of that size, one kernel call places all the copies, and one unions them. A boss that
/// doesn't touch the part doesn't fail the node; it warns with the count ("3 of 24 bosses miss the part.").
///
/// Every size is a list, so a boss can differ from the next: the longest list sets the number of bosses and a
/// shorter one repeats its last item. Faces of boss `i` are tagged with its instance path `{i}`.
public enum BossPatternNode: NodeDefinition {
    public static let typeID = "creator.bossPattern"
    public static let displayName = "Boss / Pin Pattern"
    public static let category = NodeCategory.patterns
    public static let placesInstances = true
    public static let inputs = [
        SocketSpec("part", .solid),
        SocketSpec("placements", .plane, access: .list),
        SocketSpec("diameter", .number, access: .list, defaultValue: .number(8), unit: .millimetres, range: 0.1...100),
        SocketSpec("height", .number, access: .list, defaultValue: .number(5), unit: .millimetres, range: 0.1...200),
        SocketSpec("draft", .number, access: .list, defaultValue: .number(0), unit: .degrees, range: 0...45),
        SocketSpec("tipFillet", .number, access: .list, defaultValue: .number(0), unit: .millimetres, range: 0...20),
    ]
    public static let outputs = [SocketSpec("solid", .solid)]
    public static let inspector = [
        InspectorSection(title: "Boss", controls: [.slider("diameter"), .slider("height")]),
        InspectorSection(title: "Finish", controls: [.slider("draft"), .slider("tipFillet")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let part = try inputs.solid("part")
        let planes = try inputs.planes("placements")
        let (diameters, heights) = (PerInstance(try inputs.numbers("diameter")), PerInstance(try inputs.numbers("height")))
        let (drafts, fillets) = (PerInstance(try inputs.numbers("draft")), PerInstance(try inputs.numbers("tipFillet")))
        let count = PerInstance<Plane>.instances([planes.count, diameters.count, heights.count, drafts.count, fillets.count])
        try PatternLimit.check(count)
        guard count > 0 else { return NodeOutputs(["solid": .solid(part)]) }
        var sizes: [BossSize] = []
        for index in 0..<count {
            let size = BossSize(diameter: diameters[index], height: heights[index], draft: .degrees(drafts[index]),
                                tipFillet: fillets[index])
            if let problem = size.problem(at: InstancePath.text(index)) { throw NodeError.invalidValue(problem) }
            sizes.append(size)
        }
        let plan = ToolPlan(sizes: sizes)
        var built: [Solid] = []
        for size in plan.distinct {
            built.append(try await tool(size, kernel: kernel, tag: context.tag))
        }
        let request = PatternApply.Request(operation: .union, part: part, tools: plan.toolIndex.map { built[$0] }, planes: planes,
                                           nouns: PatternApply.Nouns(singular: "boss", plural: "bosses"))
        return try await PatternApply.run(request, kernel: kernel, context: context)
    }

    /// The boss standing on the origin along +Z: revolved, then its tip rim rounded when `tipFillet` asks.
    private static func tool(_ size: BossSize, kernel: any Kernel, tag: NodeTag) async throws -> Solid {
        let profile = Profile2D.polyline(size.outline, closed: true, plane: .xz)
        let boss = try await kernel.revolve(profile, axis: .z, angle: .degrees(360), tag: tag)
        guard size.tipFillet > 0 else { return boss }
        // The tip's rim is the only circle at the boss's height; the revolve's seams are lines.
        let rim = boss.topology.edges.filter { $0.kind == .circle && abs($0.midpoint.z - size.height) < 1e-6 }
        return try await kernel.fillet(boss, edges: rim.map(\.id), radius: size.tipFillet, tag: tag)
    }
}
