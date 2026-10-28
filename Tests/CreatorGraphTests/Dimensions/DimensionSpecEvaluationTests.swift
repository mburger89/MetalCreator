import CreatorKernel
import CreatorSketch
import Foundation
import Testing
@testable import CreatorGraph

struct DimensionSpecEvaluationTests {
    func evaluator() -> Evaluator { Evaluator(registry: dimensionTestRegistry, kernel: FakeKernel()) }

    func makeNode(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:]) -> Node {
        var node = dimensionTestRegistry.makeNode(definition.typeID)
        node.inputValues = values
        return node
    }

    @Test func aNodesSpecsReachItsResult() async throws {
        let node = makeNode(SpecEmittingNode.self, ["value": .number(12)])
        let report = try await evaluator().evaluate(graph([node]), demand: [node.id])
        #expect(report.results[node.id]?.dimensions == [SpecEmittingNode.spec(12)])
    }

    @Test func eachIterationAppendsItsSpecsInOrder() async throws {
        let list = makeNode(ListSourceNode.self, ["count": .integer(3)])
        let node = makeNode(SpecEmittingNode.self)
        let report = try await evaluator().evaluate(graph([list, node], [link(list, "values", node, "value")]), demand: [node.id])
        #expect(report.results[node.id]?.dimensions.map(\.value) == [0, 1, 2])
    }

    @Test func aCachedResultKeepsItsSpecs() async throws {
        let node = makeNode(SpecEmittingNode.self, ["value": .number(7)])
        let evaluator = evaluator()
        _ = try await evaluator.evaluate(graph([node]), demand: [node.id])
        let second = try await evaluator.evaluate(graph([node]), demand: [node.id])
        #expect(second.evaluatedNodes.isEmpty)
        #expect(second.results[node.id]?.dimensions == [SpecEmittingNode.spec(7)])
    }

    @Test func aFailedNodeHasNoSpecs() async throws {
        let node = makeNode(SpecEmittingNode.self, ["value": .number(-1)])
        let report = try await evaluator().evaluate(graph([node]), demand: [node.id])
        #expect(report.results[node.id]?.state.isSuccess == false)
        #expect(report.results[node.id]?.dimensions == [])
    }

    @Test func targetsAndPinsCodeAsDocumented() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        func json(_ value: some Encodable) throws -> String {
            try #require(String(bytes: encoder.encode(value), encoding: .utf8))
        }
        #expect(try json(DimensionTarget.input("distance")) == #"{"input":"distance"}"#)
        #expect(try json(DimensionTarget.sketchDimension(DimensionID(3))) == #"{"sketchDimension":3}"#)
        let id = NodeID()
        let pin = DimensionPin(node: id, target: .input("distance"))
        #expect(try json(pin) == #"{"input":"distance","node":"\#(id.rawValue.uuidString)"}"#)
        for target in [DimensionTarget.input("a"), .sketchDimension(DimensionID(9))] {
            #expect(try JSONDecoder().decode(DimensionTarget.self, from: encoder.encode(target)) == target)
        }
        #expect(try JSONDecoder().decode(DimensionPin.self, from: encoder.encode(pin)) == pin)
        #expect(DimensionTarget.input("a").key == "input/a")
        #expect(DimensionTarget.sketchDimension(DimensionID(3)).key == "sketch/3")
        let sorted = [DimensionTarget.sketchDimension(DimensionID(1)), .input("b"), .input("a")].sorted()
        #expect(sorted == [.input("a"), .input("b"), .sketchDimension(DimensionID(1))])
        let (low, high) = (NodeID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
                           NodeID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!))
        #expect(DimensionPin(node: low, target: .input("z")) < DimensionPin(node: high, target: .input("a")))
        #expect(DimensionPin(node: low, target: .input("a")) < DimensionPin(node: low, target: .input("z")))
    }
}
