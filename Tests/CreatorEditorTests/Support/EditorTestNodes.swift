// Test fixture file: it deliberately holds several small node definitions, one per category,
// so the editor is tested without depending on CreatorNodes.
import CreatorGeometry
import CreatorGraph
import CreatorKernel

enum NumberTestNode: NodeDefinition {
    static let typeID = "editortest.number"
    static let displayName = "Number"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(5), unit: .millimetres, range: 0...50)]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

enum RectangleTestNode: NodeDefinition {
    static let typeID = "editortest.rectangle"
    static let displayName = "Rectangle"
    static let category = NodeCategory.profile
    static let inputs = [
        SocketSpec("width", .number, defaultValue: .number(10), unit: .millimetres),
        SocketSpec("height", .number, defaultValue: .number(10), unit: .millimetres),
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

/// Mirrors M3's Extrude: a segmented mode (integer index), the distance slider and the
/// "Reverse direction" toggle on a bool socket (spec Errata (M3): the Direction menu is a toggle).
enum ExtrudeTestNode: NodeDefinition {
    static let typeID = "editortest.extrude"
    static let displayName = "Extrude"
    static let category = NodeCategory.solid
    static let inputs = [
        SocketSpec("profile", .profile),
        SocketSpec("distance", .number, defaultValue: .number(10), unit: .millimetres, range: 0...100),
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

/// Mirrors M3's selection-rule nodes: `ruleSummary` names the node's own *output*.
enum AllEdgesTestNode: NodeDefinition {
    static let typeID = "editortest.allEdges"
    static let displayName = "All Edges"
    static let category = NodeCategory.selection
    static let inputs = [SocketSpec("solid", .solid)]
    static let outputs = [SocketSpec("edges", .edgeSet)]
    static let inspector = [InspectorSection(title: "Edges", controls: [.ruleSummary("edges")])]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solid = try inputs.solid("solid")
        return NodeOutputs(["edges": .edgeSet(EdgeSet(solid: solid, edges: solid.topology.edges.map(\.id)))])
    }
}

/// Mirrors M3's Fillet: `ruleSummary` names an *input*, and the toggle binds the `showHandle`
/// setting (not a socket), seeded `.bool(true)` by `defaultSettings` as M3 does. M3 has no
/// "Tangent chain" toggle (spec Errata (M3)), so neither does this.
enum FilletTestNode: NodeDefinition {
    static let typeID = "editortest.fillet"
    static let displayName = "Fillet"
    static let category = NodeCategory.feature
    static let inputs = [
        SocketSpec("solid", .solid),
        SocketSpec("edges", .edgeSet),
        SocketSpec("radius", .number, defaultValue: .number(1), unit: .millimetres, range: 0...20),
    ]
    static let outputs = [SocketSpec("solid", .solid)]
    static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.showHandle: .bool(true)]
    static let inspector = [
        InspectorSection(title: "Fillet", controls: [.slider("radius"), .toggle(NodeSetting.showHandle, label: "Show handle in view")]),
        InspectorSection(title: "Edges",
                         controls: [.ruleSummary("edges"), .button(title: "Pick edges in view…", action: .pickEdgesInView)]),
    ]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["solid": .solid(try inputs.solid("solid"))])
    }
}

/// Mirrors M3's Output: one `.list` input (one wire carrying every solid) passed through as one list.
enum OutputTestNode: NodeDefinition {
    static let typeID = "editortest.output"
    static let displayName = "Output"
    static let category = NodeCategory.output
    static let inputs = [SocketSpec("solid", .solid, access: .list)]
    static let outputs = [SocketSpec("solid", .solid)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(lists: ["solid": try inputs.list("solid")])
    }
}

/// Mirrors M3's Transform: a `.vector` control on a vector socket.
enum TransformTestNode: NodeDefinition {
    static let typeID = "editortest.transform"
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

/// Mirrors M3's Graph Parameter: a `.parameterPicker` bound to the `parameter` setting, and one
/// optional output per parameter type.
enum GraphParameterTestNode: NodeDefinition {
    static let typeID = "editortest.graphParameter"
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

/// Mirrors M3's Grid Points: `total` is an optional integer input with no default. Unset, the
/// grid is `countX` × `countY`; set, it overrides `countX` (M3 carry-over).
enum GridPointsTestNode: NodeDefinition {
    static let typeID = "editortest.gridPoints"
    static let displayName = "Grid Points"
    static let category = NodeCategory.value
    static let inputs = [
        SocketSpec("countX", .integer, defaultValue: .integer(2), unit: .count),
        SocketSpec("total", .integer, unit: .count, optional: true),
    ]
    static let outputs = [SocketSpec("points", .vector)]
    static let inspector = [InspectorSection(title: "Grid", controls: [.integer("countX"), .integer("total")])]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(lists: ["points": []])
    }
}

let editorTestRegistry = NodeRegistry([
    NumberTestNode.self, RectangleTestNode.self, ExtrudeTestNode.self, AllEdgesTestNode.self,
    FilletTestNode.self, OutputTestNode.self,
])

/// The editor registry plus the definitions that carry M3's newer controls and an optional input,
/// for the inspector tests. Kept separate so the palette tests' type lists stay as they are.
let inspectorTestRegistry = NodeRegistry([
    NumberTestNode.self, RectangleTestNode.self, ExtrudeTestNode.self, AllEdgesTestNode.self,
    FilletTestNode.self, OutputTestNode.self, TransformTestNode.self, GraphParameterTestNode.self,
    GridPointsTestNode.self,
])

/// Mirrors the Sketch node's exposed dimensions: one extra number input per node, named by the `extra` setting
/// (`.text(name)`), in millimetres with a default of 7, beside a static `profile` input. No inspector, so the
/// fallback rows list it.
enum PerNodeSocketTestNode: NodeDefinition {
    static let typeID = "editortest.perNodeSocket"
    static let displayName = "Per-node Socket"
    static let category = NodeCategory.profile
    static let inputs = [SocketSpec("profile", .profile, optional: true)]
    static let outputs = [SocketSpec("profile", .profile)]
    static func inputs(for node: Node) -> [SocketSpec] {
        guard case .text(let name)? = node.inputValues["extra"] else { return inputs }
        return inputs + [SocketSpec(SocketName(name), .number, defaultValue: .number(7), unit: .millimetres)]
    }
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["profile": .profile(.rectangle(width: 1, height: 1, plane: .xy))])
    }
}

/// The editor registry plus `PerNodeSocketTestNode`, for the per-node socket tests.
let perNodeSocketTestRegistry = NodeRegistry([NumberTestNode.self, PerNodeSocketTestNode.self])

/// Mirrors the Sketch node's inspector: an "Edit sketch" button, which a double click also presses.
enum SketchTestNode: NodeDefinition {
    static let typeID = "editortest.sketch"
    static let displayName = "Sketch"
    static let category = NodeCategory.profile
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("profiles", .profile)]
    static let inspector = [InspectorSection(title: "Sketch", controls: [.button(title: "Edit sketch", action: .editSketch)])]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["profiles": .profile(.rectangle(width: 1, height: 1, plane: .xy))])
    }
}

/// The editor registry plus `SketchTestNode`, for the double-click tests.
let sketchTestRegistry = NodeRegistry([NumberTestNode.self, FilletTestNode.self, SketchTestNode.self])
