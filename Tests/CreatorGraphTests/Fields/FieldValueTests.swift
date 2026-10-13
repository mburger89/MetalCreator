import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

/// Fields spec §2.1: `Scalar.field`, `SocketType.field`, the one-way conversion from numbers, and what the evaluator does with it.
struct FieldValueTests {
    // MARK: the type and the conversion (D4)

    @Test func aFieldIsAFieldTypedValue() {
        #expect(Scalar.field(.constant(1)).type == .field)
        #expect(SocketType.field.indefiniteName == "a field")
        #expect(SocketType.field.rawValue == "field")
    }

    @Test func aNumberOrAnIntegerBecomesAConstantField() throws {
        let fromNumber = try #require(Scalar.number(2.5).converted(to: .field))
        let fromInteger = try #require(Scalar.integer(3).converted(to: .field))
        guard case .field(let a) = fromNumber, case .field(let b) = fromInteger else {
            Issue.record("expected fields")
            return
        }
        #expect(a.description == "2.5" && b.description == "3")
    }

    @Test func nothingConvertsBackToANumberOrAnythingElse() {
        let field = Scalar.field(.constant(1))
        for target in [SocketType.number, .integer, .bool, .vector, .plane, .profile, .solid, .edgeSet, .faceSet] {
            #expect(field.converted(to: target) == nil, "a field is not \(target)")
        }
        #expect(field.converted(to: .field) != nil)
        #expect(field.converted(to: .any) != nil)
    }

    @Test func otherTypesDoNotBecomeFields() {
        #expect(Scalar.bool(true).converted(to: .field) == nil)
        #expect(Scalar.vector(.zero).converted(to: .field) == nil)
        #expect(Scalar.plane(.xy).converted(to: .field) == nil)
    }

    @Test func aFieldSocketAcceptsNumbersAndIntegersButNothingAcceptsAField() {
        #expect(SocketType.field.accepts(.number) && SocketType.field.accepts(.integer) && SocketType.field.accepts(.field))
        #expect(!SocketType.field.accepts(.bool) && !SocketType.field.accepts(.vector) && !SocketType.field.accepts(.solid))
        for type in SocketType.allCases where type != .field && type != .any {
            #expect(!type.accepts(.field), "\(type) must not accept a field")
        }
        #expect(SocketType.any.accepts(.field) && SocketType.field.accepts(.any))
    }

    @Test func aListOfNumbersConvertsToAListOfFields() throws {
        let list = try #require(Value.list([.number(1), .integer(2), .number(0.5)]).converted(to: .field))
        #expect(list.items.map { if case .field(let f) = $0 { f.description } else { "?" } } == ["1", "2", "0.5"])
        #expect(Value.list([.number(1), .bool(true)]).converted(to: .field) == nil)
    }

    // MARK: size

    @Test func aFieldCostsSixtyFourPlusThirtyTwoPerNode() {
        #expect(Field.constant(1).nodeCount == 1 && Field.constant(1).estimatedBytes == 96)
        let tree = Field.add(.constant(1), .multiply(.constant(2), .constant(3)))
        #expect(tree.nodeCount == 5 && tree.estimatedBytes == 64 + 32 * 5)
        #expect(Scalar.field(tree).estimatedBytes == tree.estimatedBytes)
        #expect(Value.one(.field(tree)).estimatedBytes == 16 + tree.estimatedBytes)
    }

    @Test func childrenAreTheOperandsInOrder() {
        let a = Field.constant(1), b = Field.noise(seed: 1, scale: 1, octaves: 1)
        #expect(Field.add(a, b).children.count == 2)
        #expect(Field.remap(a, fromLow: 0, fromHigh: 1, toLow: 0, toHigh: 1, clamped: true).children.count == 1)
        #expect(Field.radialGradient(center: .zero, radius: 1).children.isEmpty)
        #expect(Field.smoothMinimum(a, b, width: 1).children.count == 2)
    }

    // MARK: through the evaluator

    static let registry = NodeRegistry([
        FieldSourceNode.self, FieldSinkNode.self, NumberSourceNode.self, WholeSourceNode.self, NumberSinkNode.self, NumberListNode.self,
    ])

    func run(_ nodes: [Node], _ links: [Link], demand: Node) async throws -> NodeResult {
        let graph = Graph(nodes: Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) }), links: links)
        let report = try await Evaluator(registry: Self.registry, kernel: FakeKernel()).evaluate(graph, demand: [demand.id])
        return try #require(report.results[demand.id])
    }

    /// A wire from `source`'s `socket` into the sink's "field".
    func wire(_ source: Node, _ socket: SocketName, to sink: Node) -> Link {
        Link(from: Endpoint(node: source.id, socket: socket), to: Endpoint(node: sink.id, socket: "field"))
    }

    func recipe(_ result: NodeResult) -> String? {
        if case .one(.field(let field))? = result.outputs?["field"] { field.description } else { nil }
    }

    @Test func anUnwiredFieldSocketTakesItsNumberAsAConstantField() async throws {
        let sink = Self.registry.makeNode(FieldSinkNode.typeID)
        #expect(recipe(try await run([sink], [], demand: sink)) == "7")
        var typed = sink
        typed.inputValues["field"] = .number(0.5)
        #expect(recipe(try await run([typed], [], demand: typed)) == "0.5", "a number typed into a field socket (Multiply by 0.5)")
    }

    @Test func aNumberOrIntegerWireArrivesAsAConstantField() async throws {
        let number = Self.registry.makeNode(NumberSourceNode.typeID)
        let whole = Self.registry.makeNode(WholeSourceNode.typeID)
        let sink = Self.registry.makeNode(FieldSinkNode.typeID)
        let fromNumber = try await run([number, sink], [wire(number, "value", to: sink)], demand: sink)
        let fromWhole = try await run([whole, sink], [wire(whole, "value", to: sink)], demand: sink)
        #expect(recipe(fromNumber) == "4.5" && recipe(fromWhole) == "6")
    }

    @Test func aFieldWireIsRefusedByANumberSocketLikeAnyTypeMismatch() {
        let source = Self.registry.makeNode(FieldSourceNode.typeID)
        let sink = Self.registry.makeNode(NumberSinkNode.typeID)
        let graph = Graph(nodes: [source.id: source, sink.id: sink], links: [])
        #expect(graph.connectionProblem(from: Endpoint(node: source.id, socket: "field"), to: Endpoint(node: sink.id, socket: "value"),
                                        registry: Self.registry) == .typeMismatch(from: .field, to: .number))
    }

    @Test func numbersAreWireableIntoAFieldSocketAndFieldsIntoOne() {
        let number = Self.registry.makeNode(NumberSourceNode.typeID)
        let whole = Self.registry.makeNode(WholeSourceNode.typeID)
        let source = Self.registry.makeNode(FieldSourceNode.typeID)
        let sink = Self.registry.makeNode(FieldSinkNode.typeID)
        let graph = Graph(nodes: [number.id: number, whole.id: whole, source.id: source, sink.id: sink], links: [])
        for from in [number, whole, source] {
            let socket: SocketName = from.id == source.id ? "field" : "value"
            #expect(graph.connectionProblem(from: Endpoint(node: from.id, socket: socket),
                                            to: Endpoint(node: sink.id, socket: "field"), registry: Self.registry) == nil)
        }
    }

    @Test func aListOfFieldsBroadcastsLikeAnyItemValue() async throws {
        let list = Self.registry.makeNode(NumberListNode.typeID)
        let sink = Self.registry.makeNode(FieldSinkNode.typeID)
        let graph = Graph(nodes: [list.id: list, sink.id: sink], links: [wire(list, "values", to: sink)])
        let report = try await Evaluator(registry: Self.registry, kernel: FakeKernel()).evaluate(graph, demand: [sink.id])
        let out = try #require(report.results[sink.id]?.outputs?["field"])
        #expect(out.items.map { if case .field(let f) = $0 { f.description } else { "?" } } == ["0", "1", "2"])
    }

    @Test func aWrongTypedConstantInAFieldSocketIsReported() async throws {
        var sink = Self.registry.makeNode(FieldSinkNode.typeID)
        sink.inputValues["field"] = .bool(true)
        let result = try await run([sink], [], demand: sink)
        #expect(result.state == .error("“field” has a value of the wrong type."))
    }
}

enum FieldSourceNode: NodeDefinition {
    static let typeID = "test.fieldSource"
    static let displayName = "Field Source"
    static let category = NodeCategory.fields
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(2))]
    static let outputs = [SocketSpec("field", .field)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["field": .field(.multiply(.constant(try inputs.number("value")), .constant(3)))])
    }
}

enum FieldSinkNode: NodeDefinition {
    static let typeID = "test.fieldSink"
    static let displayName = "Field Sink"
    static let category = NodeCategory.fields
    static let inputs = [SocketSpec("field", .field, defaultValue: .number(7))]
    static let outputs = [SocketSpec("field", .field)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["field": .field(try inputs.field("field"))])
    }
}

enum NumberSourceNode: NodeDefinition {
    static let typeID = "test.numberSource"
    static let displayName = "Number Source"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(4.5))]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

enum WholeSourceNode: NodeDefinition {
    static let typeID = "test.wholeSource"
    static let displayName = "Whole Source"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .integer, defaultValue: .integer(6))]
    static let outputs = [SocketSpec("value", .integer)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .integer(try inputs.integer("value"))])
    }
}

enum NumberSinkNode: NodeDefinition {
    static let typeID = "test.numberSink"
    static let displayName = "Number Sink"
    static let category = NodeCategory.value
    static let inputs = [SocketSpec("value", .number, defaultValue: .number(0))]
    static let outputs = [SocketSpec("value", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(["value": .number(try inputs.number("value"))])
    }
}

enum NumberListNode: NodeDefinition {
    static let typeID = "test.numberList"
    static let displayName = "Number List"
    static let category = NodeCategory.value
    static let inputs: [SocketSpec] = []
    static let outputs = [SocketSpec("values", .number)]
    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        NodeOutputs(lists: ["values": [.number(0), .number(1), .number(2)]])
    }
}
