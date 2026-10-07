// Test fixture file: helpers shared by the graph tests.
import CreatorKernel
@testable import CreatorGraph

func makeNode(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:], output: Bool = false) -> Node {
    var node = testRegistry.makeNode(definition.typeID)
    node.inputValues = values
    node.isOutput = output
    return node
}

extension Value {
    /// The numbers carried, or `nil` if any item isn't a number.
    var numbers: [Double]? {
        let values = items.compactMap { scalar -> Double? in
            if case .number(let value) = scalar { value } else { nil }
        }
        return values.count == items.count ? values : nil
    }

    var isList: Bool { if case .list = self { true } else { false } }
}
