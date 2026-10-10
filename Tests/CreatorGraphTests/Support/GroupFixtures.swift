// Test fixture file: a small group definition and helpers shared by the group tests.
import CreatorKernel
@testable import CreatorGraph

/// "Doubler": one number input `value` (default 1) and one number output `result`. Inside, Group Input's `value`
/// feeds both of an Add's inputs and the Add's `sum` feeds Group Output's `result`, so the group doubles its input.
struct Doubler {
    var definition: GroupDefinition
    let input: Node
    let output: Node
    let add: Node

    init(name: String = "Doubler") {
        let id = GroupID()
        input = testRegistry.makeGroupNode(GroupNodes.inputTypeID, for: id, at: GroupDefinition.defaultInputPosition)
        output = testRegistry.makeGroupNode(GroupNodes.outputTypeID, for: id, at: GroupDefinition.defaultOutputPosition)
        add = testRegistry.makeNode(AddNode.typeID)
        var inside = graph([input, add, output], [
            link(input, "value", add, "a"), link(input, "value", add, "b"), link(add, "sum", output, "result"),
        ])
        inside.sortLinks()  // As commands and decoding keep them, so a round trip compares equal.
        definition = GroupDefinition(id: id, name: name, inputs: [SocketSpec("value", .number, defaultValue: .number(1))],
                                     outputs: [SocketSpec("result", .number)], graph: inside)
    }

    var id: GroupID { definition.id }
}

/// A group node of `definition`, made as the editor makes one.
func instance(of definition: GroupDefinition, _ values: [SocketName: ConstantValue] = [:], output: Bool = false) -> Node {
    var node = testRegistry.withGroups([definition.id: definition]).makeGroupNode(GroupNodes.groupTypeID, for: definition.id)
    node.inputValues.merge(values) { _, given in given }
    node.isOutput = output
    return node
}

/// `definitions` keyed by ID.
func table(_ definitions: [GroupDefinition]) -> [GroupID: GroupDefinition] {
    Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
}
