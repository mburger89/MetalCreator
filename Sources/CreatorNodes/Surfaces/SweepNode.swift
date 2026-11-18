import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Profiles swept along one path into a surface, or a solid when closed (NURBS spec).
public enum SweepNode: NodeDefinition {
    public static let typeID = "creator.sweep"
    public static let displayName = "Sweep"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Make"
    public static let maximumProfiles = 100
    public static let orientations = ["Frenet", "Fixed", "Rail", "Guide"]
    public static let railRefusal = "Wire a rail curve."
    public static let guideRefusal = "Wire a guide surface."
    public static let manyRailsRefusal = "Sweep takes one rail curve."
    public static let twistRefusal = "Twist can't be combined with a rail or a guide surface."
    public static let unusedGuideWarning = "The rail and guide are used only when the orientation is Rail or Guide."
    public static let pathRefusal = "Sweep needs exactly one path."
    public static var singleValuesRefusal: String? {
        "Sweep takes one path, guide, orientation, binormal, twist, end scale and solid choice at a time."
    }
    public static let inputs = [
        SocketSpec("profiles", .curve, access: .list),
        SocketSpec("path", .curve),
        SocketSpec("orientation", .integer, defaultValue: .integer(0)),
        SocketSpec("binormal", .vector, defaultValue: .vector(.unitZ)),
        SocketSpec("rail", .curve, access: .list, optional: true),
        SocketSpec("guide", .solid, optional: true),
        SocketSpec("twist", .number, defaultValue: .number(0), unit: .degrees, range: -3600...3600),
        SocketSpec("end scale", .number, defaultValue: .number(1), range: 0.01...100),
        SocketSpec("solid", .bool, defaultValue: .bool(true)),
    ]
    public static let outputs = [SocketSpec("surface", .solid)]
    private static func sections(orientation: Int, showsTwist: Bool) -> [InspectorSection] {
        var controls: [InspectorControl] = [.segmented("orientation", options: orientations)]
        if orientation == 1 { controls.append(.vector("binormal")) }
        if showsTwist { controls.append(.slider("twist")) }
        controls += [.slider("end scale"), .toggle("solid", label: "Make a solid")]
        return [InspectorSection(title: "Sweep", controls: controls)]
    }

    public static let inspector = sections(orientation: 1, showsTwist: true)

    /// The binormal is shown for Fixed, the twist for Frenet and Fixed (and while a Rail or Guide node still holds one); the rail and guide are wired, never typed.
    public static func inspector(for node: Node) -> [InspectorSection] {
        var orientation = 0
        if case .integer(let value)? = node.inputValues["orientation"] { orientation = value }
        // A twist left over from Frenet or Fixed stays visible under Rail or Guide, which refuse it, so it can be cleared.
        var staleTwist = false
        if case .number(let twist)? = node.inputValues["twist"] { staleTwist = twist != 0 }
        return sections(orientation: orientation, showsTwist: orientation <= 1 || staleTwist)
    }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let sources = try inputs.curves("profiles")
        guard sources.count <= maximumProfiles else {
            throw NodeError.invalidValue("A sweep takes at most \(maximumProfiles.display) profiles.")
        }
        let paths = try await CurveInput.loops(try inputs.curves("path"), holes: .all, kernel: kernel, tag: context.tag)
        guard let path = paths.first, paths.count == 1 else { throw NodeError.invalidValue(pathRefusal) }
        let profiles = try await CurveInput.loops(sources, holes: .all, kernel: kernel, tag: context.tag)
        let choice = try inputs.choice("orientation", options: orientations)
        let orientation = SweepOrientation(rawValue: choice) ?? .frenet
        let twist = try inputs.number("twist")
        if orientation.rawValue >= 2, twist != 0 { throw NodeError.invalidValue(twistRefusal) }
        var guide: SweepGuide?
        if orientation == .secondRail {
            guard inputs.has("rail") else { throw NodeError.invalidValue(railRefusal) }
            let rails = try await CurveInput.loops(try inputs.curves("rail"), holes: .all, kernel: kernel, tag: context.tag)
            guard let rail = rails.first else { throw NodeError.invalidValue(railRefusal) }
            guard rails.count == 1 else { throw NodeError.invalidValue(manyRailsRefusal) }
            guide = .rail(rail)
        } else if orientation == .guideSurface {
            guard inputs.has("guide") else { throw NodeError.invalidValue(guideRefusal) }
            guide = .surface(try inputs.solid("guide"))
        }
        let options = SweepOptions(orientation: orientation, binormal: try inputs.vector("binormal"),
                                   endScale: try inputs.number("end scale"), makesSolid: try inputs.bool("solid"),
                                   twist: twist)
        let surface = try await kernel.sweep(profiles, along: path, options: options, guide: guide, tag: context.tag)
        // A rail or guide wired under Frenet or Fixed is ignored; say so rather than build a different sweep silently.
        let ignored = orientation.rawValue <= 1 && (inputs.has("rail") || inputs.has("guide"))
        return NodeOutputs(["surface": .solid(surface)], warnings: ignored ? [unusedGuideWarning] : [])
    }
}
