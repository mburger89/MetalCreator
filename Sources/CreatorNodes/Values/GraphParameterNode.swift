import CreatorGraph
import CreatorKernel
import Foundation

/// Reads one document parameter (spec §4.1), chosen by the `parameter` setting. Socket types are
/// fixed per node type, so there is one optional output per parameter type: a number parameter
/// fills `number`; an integer parameter fills `integer` and also `number`; a bool fills `bool`;
/// a vector fills `vector`. Wiring an output the chosen parameter doesn't fill is reported
/// on the downstream node.
public enum GraphParameterNode: NodeDefinition {
    public static let typeID = "creator.graphParameter"
    public static let displayName = "Graph Parameter"
    public static let category = NodeCategory.value
    public static let readsParameters = true
    public static let inputs: [SocketSpec] = []
    public static let outputs = [
        SocketSpec("number", .number, optional: true),
        SocketSpec("integer", .integer, optional: true),
        SocketSpec("bool", .bool, optional: true),
        SocketSpec("vector", .vector, optional: true),
    ]
    public static let inspector = [InspectorSection(title: "Parameter", controls: [.parameterPicker(NodeSetting.parameter)])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard let id = context.node.inputValues[NodeSetting.parameter]?.parameterID else {
            throw NodeError.invalidValue("Choose a document parameter for this node to read.")
        }
        guard let value = context.parameters[id] else {
            throw NodeError.invalidValue("The parameter this node read was removed. Choose another one.")
        }
        switch value {
        case .number(let number):
            return NodeOutputs(["number": .number(number)])
        case .integer(let integer):
            return NodeOutputs(["integer": .integer(integer), "number": .number(Double(integer))])
        case .bool(let bool):
            return NodeOutputs(["bool": .bool(bool)])
        case .vector(let vector):
            return NodeOutputs(["vector": .vector(vector)])
        case .plane, .text, .edgePicks, .sketch, .facePick:
            throw NodeError.invalidValue("Graph Parameter reads number, integer, true/false and vector parameters.")
        }
    }
}
