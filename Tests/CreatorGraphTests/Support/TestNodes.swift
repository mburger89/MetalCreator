// Test fixture file: it deliberately holds several small node definitions.
import CreatorGeometry
import Foundation
import CreatorKernel
@testable import CreatorGraph

enum ConstantNode: NodeDefinition {
    static let typeID = "test.constant"
    static let displayName = "Constant"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

enum IntegerNode: NodeDefinition {
    static let typeID = "test.integer"
    static let displayName = "Integer"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .integer, defaultValue: .integer(0))]
    static let outputs = [SocketSpec("value", .integer)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .integer(try inputs.integer("value"))])
    }
}

enum AddNode: NodeDefinition {
    static let typeID = "test.add"
    static let displayName = "Add"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("a", .number, defaultValue: .number(0)), SocketSpec("b", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("sum", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["sum": .number(try inputs.number("a") + inputs.number("b"))])
    }
}

/// Requires a wired or typed `value`; it has no default.
enum RequiredNode: NodeDefinition {
    static let typeID = "test.required"
    static let displayName = "Required"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number)]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

enum SumListNode: NodeDefinition {
    static let typeID = "test.sumList"
    static let displayName = "Sum List"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("values", .number, access: .list)]
    static let outputs = [SocketSpec("sum", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let total = try inputs.list("values").reduce(0.0) { sum, scalar in
            guard case .number(let value) = scalar else { throw NodeError.typeMismatch("values", expected: .number) }
            return sum + value
        }
        return NodeOutputs(["sum": .number(total)])
    }
}

/// Emits the list 0, 1, …, count − 1 as one list-valued output.
enum ListSourceNode: NodeDefinition {
    static let typeID = "test.listSource"
    static let displayName = "List Source"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("count", .integer, defaultValue: .integer(3))]
    static let outputs = [SocketSpec("values", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let count = try inputs.integer("count")
        guard count >= 0 else { throw NodeError.invalidValue("Count can't be negative.") }
        return NodeOutputs(lists: ["values": (0..<count).map { .number(Double($0)) }])
    }
}

enum FailNode: NodeDefinition {
    static let typeID = "test.fail"
    static let displayName = "Fail"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        throw NodeError.invalidValue("Boom")
    }
}

enum WarnNode: NodeDefinition {
    static let typeID = "test.warn"
    static let displayName = "Warn"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .number(try inputs.number("value"))], warnings: ["Careful"])
    }
}

/// Sleeps 300 ms before passing its value through, so tests can cancel mid-evaluation.
enum SlowNode: NodeDefinition {
    static let typeID = "test.slow"
    static let displayName = "Slow"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        try await Task.sleep(for: .milliseconds(300))
        return NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

/// Sleeps 60 s, so a test can only finish it by cancelling.
enum HangingNode: NodeDefinition {
    static let typeID = "test.hanging"
    static let displayName = "Hanging"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        try await Task.sleep(for: .seconds(60))
        return NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

/// Cancels the evaluating task, then returns normally, so cancellation is observed only between nodes.
enum CancelsTaskNode: NodeDefinition {
    static let typeID = "test.cancelsTask"
    static let displayName = "Cancels Task"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        withUnsafeCurrentTask { $0?.cancel() }
        return NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

/// Reads the graph parameter named by its `parameter` text setting.
enum ParameterNode: NodeDefinition {
    static let typeID = "test.parameter"
    static let displayName = "Parameter"
    static let category = NodeCategory.value
    static let readsParameters = true
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        guard case .text(let raw)? = context.node.inputValues["parameter"],
              let uuid = UUID(uuidString: raw),
              case .number(let value)? = context.parameters[ParameterID(rawValue: uuid)] else {
            throw NodeError.invalidValue("Choose a parameter.")
        }
        return NodeOutputs(["value": .number(value)])
    }
}

/// Extrudes a centred rectangle through the kernel.
enum BoxNode: NodeDefinition {
    static let typeID = "test.box"
    static let displayName = "Box"
    static let category = NodeCategory.solid
    static let inputs = [
        SocketSpec("width", .number, defaultValue: .number(10), unit: .millimetres),
        SocketSpec("height", .number, defaultValue: .number(10), unit: .millimetres),
        SocketSpec("distance", .number, defaultValue: .number(10), unit: .millimetres),
    ]
    static let outputs = [SocketSpec("solid", .solid)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let profile = Profile2D.rectangle(width: try inputs.number("width"), height: try inputs.number("height"), plane: .xy)
        let solid = try await kernel.extrude(profile, distance: try inputs.number("distance"), mode: .oneSided, tag: context.tag)
        return NodeOutputs(["solid": .solid(solid)])
    }
}

/// Version 2 renamed its input from "old" to "value".
enum VersionedNode: NodeDefinition {
    static let typeID = "test.versioned"
    static let typeVersion = 2
    static let displayName = "Versioned"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static func migrate(_ node: Node, from version: Int) -> Node {
        var migrated = node
        if version < 2, let old = migrated.inputValues.removeValue(forKey: "old") {
            migrated.inputValues["value"] = old
        }
        return migrated
    }
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

let testRegistry = NodeRegistry([
    ConstantNode.self, IntegerNode.self, AddNode.self, RequiredNode.self, SumListNode.self, ListSourceNode.self,
    FailNode.self, WarnNode.self, SlowNode.self, HangingNode.self, CancelsTaskNode.self, ParameterNode.self, BoxNode.self, VersionedNode.self,
])
