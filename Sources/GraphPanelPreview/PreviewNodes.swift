// Preview fixture file: a few small node definitions, one per category, so the graph panel can be
// checked by eye without CreatorNodes. Not shipped: the app (M6) registers the real nodes.
import CreatorGeometry
import CreatorGraph
import CreatorKernel

enum PreviewNumber: NodeDefinition {
    static let typeID = "preview.number"
    static let displayName = "Number"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(60), unit: .millimetres, range: 0...200)]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

enum PreviewRectangle: NodeDefinition {
    static let typeID = "preview.rectangle"
    static let displayName = "Rectangle"
    static let category = NodeCategory.profile
    static let inputs = [
        SocketSpec("width", .number, defaultValue: .number(60), unit: .millimetres, range: 1...200),
        SocketSpec("height", .number, defaultValue: .number(40), unit: .millimetres, range: 1...200),
        SocketSpec("plane", .plane, defaultValue: .plane(.xy)),
        SocketSpec("anchor", .integer, defaultValue: .integer(4)),
    ]
    static let outputs = [SocketSpec("profile", .profile)]
    static let inspector = [
        InspectorSection(title: "Size", controls: [.slider("width"), .slider("height")]),
        InspectorSection(title: "Placement", controls: [.planePicker("plane"), .anchorGrid("anchor")]),
    ]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let profile = Profile2D.rectangle(width: try inputs.number("width"), height: try inputs.number("height"),
                                          plane: try inputs.plane("plane"))
        return NodeOutputs(["profile": .profile(profile)])
    }
}

enum PreviewExtrude: NodeDefinition {
    static let typeID = "preview.extrude"
    static let displayName = "Extrude"
    static let category = NodeCategory.solid
    static let inputs = [
        SocketSpec("profile", .profile),
        SocketSpec("distance", .number, defaultValue: .number(6), unit: .millimetres, range: 0...100),
        SocketSpec("mode", .integer, defaultValue: .integer(0)),
        SocketSpec("reversed", .bool, defaultValue: .bool(false)),
    ]
    static let outputs = [SocketSpec("solid", .solid)]
    static let inspector = [
        InspectorSection(title: "Extrude", controls: [
            .segmented("mode", options: ["Distance", "Symmetric"]), .slider("distance"),
            .toggle("reversed", label: "Reverse direction"),
        ]),
    ]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let mode: ExtrudeMode = try inputs.integer("mode") == 1 ? .symmetric : .oneSided
        let solid = try await kernel.extrude(try inputs.profile("profile"), distance: try inputs.number("distance"),
                                             mode: mode, tag: context.tag)
        return NodeOutputs(["solid": .solid(solid)])
    }
}

enum PreviewAllEdges: NodeDefinition {
    static let typeID = "preview.allEdges"
    static let displayName = "All Edges"
    static let category = NodeCategory.selection
    static let inputs = [SocketSpec("solid", .solid)]
    static let outputs = [SocketSpec("edges", .edgeSet)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solid = try inputs.solid("solid")
        return NodeOutputs(["edges": .edgeSet(EdgeSet(solid: solid, edges: solid.topology.edges.map(\.id)))])
    }
}

enum PreviewFillet: NodeDefinition {
    static let typeID = "preview.fillet"
    static let displayName = "Fillet"
    static let category = NodeCategory.feature
    static let inputs = [
        SocketSpec("solid", .solid),
        SocketSpec("edges", .edgeSet),
        SocketSpec("radius", .number, defaultValue: .number(3), unit: .millimetres, range: 0...20),
    ]
    static let outputs = [SocketSpec("solid", .solid)]
    static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.showHandle: .bool(true)]
    static let inspector = [
        InspectorSection(title: "Fillet", controls: [.slider("radius"), .toggle(NodeSetting.showHandle, label: "Show handle in view")]),
        InspectorSection(title: "Edges",
                         controls: [.ruleSummary("edges"), .button(title: "Pick edges in view…", action: .pickEdgesInView)]),
    ]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let radius = try inputs.number("radius")
        guard radius <= 10 else { throw NodeError.invalidValue("Radius \(radius) mm is too large for the selected edges.") }
        return NodeOutputs(["solid": .solid(try inputs.solid("solid"))])
    }
}

enum PreviewTransform: NodeDefinition {
    static let typeID = "preview.transform"
    static let displayName = "Transform"
    static let category = NodeCategory.solid
    static let inputs = [
        SocketSpec("solid", .solid),
        SocketSpec("move", .vector, defaultValue: .vector(.zero), unit: .millimetres),
    ]
    static let outputs = [SocketSpec("solid", .solid)]
    static let inspector = [InspectorSection(title: "Move", controls: [.vector("move")])]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["solid": .solid(try inputs.solid("solid"))])
    }
}

enum PreviewGraphParameter: NodeDefinition {
    static let typeID = "preview.graphParameter"
    static let displayName = "Graph Parameter"
    static let category = NodeCategory.value
    static let inputs: [SocketSpec] = []
    static let outputs = [
        SocketSpec("number", .number, optional: true), SocketSpec("integer", .integer, optional: true),
        SocketSpec("bool", .bool, optional: true), SocketSpec("vector", .vector, optional: true),
    ]
    static let inspector = [InspectorSection(title: "Parameter", controls: [.parameterPicker(NodeSetting.parameter)])]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["number": .number(0)])
    }
}

/// Like M3's Grid Points: `total` is optional with no default, so its field starts empty ("Not set").
enum PreviewGridPoints: NodeDefinition {
    static let typeID = "preview.gridPoints"
    static let displayName = "Grid Points"
    static let category = NodeCategory.value
    static let inputs = [
        SocketSpec("countX", .integer, defaultValue: .integer(2), unit: .count),
        SocketSpec("countY", .integer, defaultValue: .integer(2), unit: .count),
        SocketSpec("total", .integer, unit: .count, optional: true),
    ]
    static let outputs = [SocketSpec("points", .vector)]
    static let inspector = [InspectorSection(title: "Grid", controls: [.integer("countX"), .integer("countY"), .integer("total")])]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(lists: ["points": []])
    }
}

/// Like M3's Output: one `.list` input, passed through.
enum PreviewOutput: NodeDefinition {
    static let typeID = "preview.output"
    static let displayName = "Output"
    static let category = NodeCategory.output
    static let inputs = [SocketSpec("solid", .solid, access: .list)]
    static let outputs = [SocketSpec("solid", .solid)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(lists: ["solid": try inputs.list("solid")])
    }
}
