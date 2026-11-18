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
    public static let pathRefusal = "Sweep needs exactly one path."
    public static var singleValuesRefusal: String? { "Sweep takes one path, end scale and binormal at a time." }
    public static let inputs = [
        SocketSpec("profiles", .curve, access: .list),
        SocketSpec("path", .curve),
        SocketSpec("orientation", .integer, defaultValue: .integer(0)),
        SocketSpec("binormal", .vector, defaultValue: .vector(.unitZ)),
        SocketSpec("rail", .curve, optional: true),
        SocketSpec("guide", .solid, optional: true),
        SocketSpec("twist", .number, defaultValue: .number(0), range: -3600...3600),
        SocketSpec("end scale", .number, defaultValue: .number(1), range: 0.01...100),
        SocketSpec("solid", .bool, defaultValue: .bool(true)),
    ]
    public static let outputs = [SocketSpec("surface", .solid)]
    private static func sections(orientation: Int) -> [InspectorSection] {
        var controls: [InspectorControl] = [.segmented("orientation", options: orientations)]
        if orientation == 1 { controls.append(.vector("binormal")) }
        if orientation <= 1 { controls.append(.slider("twist")) }
        controls += [.slider("end scale"), .toggle("solid", label: "Make a solid")]
        return [InspectorSection(title: "Sweep", controls: controls)]
    }

    public static let inspector = sections(orientation: 1)

    /// The binormal is shown for Fixed, the twist for Frenet and Fixed; the rail and guide are wired, never typed.
    public static func inspector(for node: Node) -> [InspectorSection] {
        if case .integer(let value)? = node.inputValues["orientation"] { return sections(orientation: value) }
        return sections(orientation: 0)
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
        var guide: SweepGuide?
        if orientation == .secondRail {
            guard inputs.has("rail") else { throw NodeError.invalidValue(railRefusal) }
            let rails = try await CurveInput.loops(try inputs.curves("rail"), holes: .all, kernel: kernel, tag: context.tag)
            guard let rail = rails.first, rails.count == 1 else { throw NodeError.invalidValue(railRefusal) }
            guide = .rail(rail)
        } else if orientation == .guideSurface {
            guard inputs.has("guide") else { throw NodeError.invalidValue(guideRefusal) }
            guide = .surface(try inputs.solid("guide"))
        }
        let options = SweepOptions(orientation: orientation, binormal: try inputs.vector("binormal"),
                                   endScale: try inputs.number("end scale"), makesSolid: try inputs.bool("solid"),
                                   twist: orientation.rawValue <= 1 ? try inputs.number("twist") : 0)
        let surface = try await kernel.sweep(profiles, along: path, options: options, guide: guide, tag: context.tag)
        return NodeOutputs(["surface": .solid(surface)])
    }
}
