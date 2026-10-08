import CreatorKernel
import Testing
@testable import CreatorGraph

/// Plain-language messages name types the way the editor does ("a whole number", "an edge set"), never by
/// their raw names ("a integer"), and a file from a newer build says what to do.
struct MessageTests {
    @Test(arguments: [
        (SocketType.integer, "“count” needs a whole number."), (.edgeSet, "“count” needs an edge set."),
        (.bool, "“count” needs an on/off value."), (.number, "“count” needs a number."),
    ])
    func aTypeMismatchNamesTheTypeInPlainWords(_ type: SocketType, _ message: String) {
        #expect(NodeError.typeMismatch("count", expected: type).message == message)
    }

    @Test func aParameterSetToTheWrongTypeIsRefusedInPlainWords() {
        let holes = GraphParameter(name: "Hole count", type: .integer, value: .integer(4))
        var graph = Graph(parameters: [holes])
        #expect(throws: GraphError.invalidValue("“Hole count” needs a whole number.")) {
            try graph.apply(.setParameter(holes.id, .number(4.5)), registry: NodeRegistry([]))
        }
    }

    /// A wire whose value can't become the input's type (a number into a whole-number input; a file can hold one)
    /// fails the node with the type named the same way.
    @Test func anUnconvertibleWiredValueNamesTheTypeInPlainWords() async throws {
        let number = makeNode(ConstantNode.self, ["value": .number(2.5)])
        let integer = makeNode(IntegerNode.self)
        let evaluator = Evaluator(registry: testRegistry, kernel: FakeKernel())
        let report = try await evaluator.evaluate(graph([number, integer], [link(number, "value", integer, "value")]),
                                                  demand: [integer.id])
        #expect(report.results[integer.id]?.state == .error("“value” needs a whole number."))
    }

    @Test func aNewerFileSaysWhichFormatAndWhatToDo() {
        #expect(GraphFileError.newerFormat(9).message
            == "This file was saved by a newer version of MetalCreator (file format 9). Update MetalCreator to open it.")
    }
}
