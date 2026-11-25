import CreatorGraph
import CreatorKernel
import Synchronization

/// The gates `GatedNode` waits at, by the number a test gives each node as its `key`. A test makes a gate, gives its node the key,
/// and an evaluation of that node stays running until the test calls `open()`: the run's length is the test's, never the clock's.
enum GatedNodeGates {
    private static let gates = Mutex<[Double: HookGate]>([:])

    /// The gate for `key`, made on first use. Tests running at once use different keys.
    static func gate(_ key: Double) -> HookGate {
        gates.withLock { gates in
            if let gate = gates[key] { return gate }
            let gate = HookGate()
            gates[key] = gate
            return gate
        }
    }
}

/// An Output node whose evaluation suspends (never blocks a thread) at `GatedNodeGates.gate(key)` until the test opens it, so an
/// evaluation can be held running while a test looks at what follows it.
enum GatedNode: NodeDefinition {
    static let typeID = "test.gated"
    static let displayName = "Gated"
    static let category = NodeCategory.output
    static let inputs = [SocketSpec("key", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let key = try inputs.number("key")
        await GatedNodeGates.gate(key).hold()
        return NodeOutputs(["value": .number(key)])
    }
}
