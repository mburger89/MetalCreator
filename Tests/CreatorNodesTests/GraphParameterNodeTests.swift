import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

struct GraphParameterNodeTests {
    @Test func numberParameterFillsTheNumberOutput() async throws {
        var h = Harness()
        let width = GraphParameter(name: "Width", type: .number, value: .number(60))
        h.parameters = [width]
        let node = h.add(GraphParameterNode.self, [NodeSetting.parameter: .parameter(width.id)])
        let report = try await h.run([node])
        #expect(report.value(node, "number")?.numbers == [60])
        #expect(report.value(node, "integer") == nil)
        #expect(report.isOK(node))
    }

    @Test func integerParameterFillsIntegerAndNumber() async throws {
        var h = Harness()
        let count = GraphParameter(name: "Hole count", type: .integer, value: .integer(4))
        h.parameters = [count]
        let node = h.add(GraphParameterNode.self, [NodeSetting.parameter: .parameter(count.id)])
        let integer = h.add(IntegerNode.self)
        h.wire(node, "integer", to: integer, "value")
        let report = try await h.run([node, integer])
        #expect(report.value(node, "integer")?.integers == [4])
        #expect(report.value(node, "number")?.numbers == [4])
        #expect(report.value(integer, "value")?.integers == [4])
    }

    @Test func wiringAnOutputTheParameterDoesNotFillIsExplained() async throws {
        var h = Harness()
        let width = GraphParameter(name: "Width", type: .number, value: .number(60))
        h.parameters = [width]
        let node = h.add(GraphParameterNode.self, [NodeSetting.parameter: .parameter(width.id)])
        let integer = h.add(IntegerNode.self)
        h.wire(node, "integer", to: integer, "value")
        let report = try await h.run([integer])
        #expect(report.error(integer)
            == "“value” is wired to “integer”, which that node doesn't have, or doesn't produce with its current settings.")
    }

    @Test func boolAndVectorParametersFillTheirOutputs() async throws {
        var h = Harness()
        let flag = GraphParameter(name: "Flag", type: .bool, value: .bool(true))
        let offset = GraphParameter(name: "Offset", type: .vector, value: .vector(Vector3(1, 2, 3)))
        h.parameters = [flag, offset]
        let a = h.add(GraphParameterNode.self, [NodeSetting.parameter: .parameter(flag.id)])
        let b = h.add(GraphParameterNode.self, [NodeSetting.parameter: .parameter(offset.id)])
        let report = try await h.run([a, b])
        #expect(report.value(a, "bool")?.bools == [true])
        #expect(report.value(b, "vector")?.vectors == [Vector3(1, 2, 3)])
    }

    @Test func noChosenParameterAsksForOne() async throws {
        var h = Harness()
        let node = h.add(GraphParameterNode.self)
        let report = try await h.run([node])
        #expect(report.error(node) == "Choose a document parameter for this node to read.")
    }

    @Test func aRemovedParameterIsReported() async throws {
        var h = Harness()
        let node = h.add(GraphParameterNode.self, [NodeSetting.parameter: .parameter(ParameterID())])
        let report = try await h.run([node])
        #expect(report.error(node) == "The parameter this node read was removed. Choose another one.")
    }

    @MainActor
    @Test func changingTheParameterReevaluatesTheDocument() async throws {
        var h = Harness()
        let width = GraphParameter(name: "Width", type: .number, value: .number(60))
        h.parameters = [width]
        let node = h.add(GraphParameterNode.self, [NodeSetting.parameter: .parameter(width.id)], output: true)
        let document = DocumentModel(file: GraphFile(graph: h.graph), registry: BuiltInNodes.registry, kernel: FakeKernel())
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.outputs?["number"]?.numbers == [60])
        try document.perform(.setParameter(width.id, .number(90)))
        await document.waitForEvaluation()
        #expect(document.results[node.id]?.outputs?["number"]?.numbers == [90])
    }
}
