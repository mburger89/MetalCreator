import CreatorGraph
import CreatorKernel

/// Holds an evaluation of `StallNode` until `open()`, so a test can wait on a document that never finishes.
actor StallGate {
    private var isOpen = false
    func open() { isOpen = true }
    func close() { isOpen = false }
    func waitUntilOpen() async throws {
        while !isOpen { try await Task.sleep(for: .milliseconds(5)) }
    }
}

enum StallNode: NodeDefinition {
    static let typeID = "test.stall"
    static let displayName = "Stall"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static let gate = StallGate()
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        try await gate.waitUntilOpen()
        return NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}
