import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorEditor

/// Convert Units' inspector says what the node makes (human checks CU-1 to CU-3 read "25.4", "3.14159" and a list).
@MainActor
struct ConvertUnitsInspectorTests {
    func result(_ values: [SocketName: ConstantValue], series: Bool = false) async -> InspectorRow? {
        var builder = GraphBuilder()
        let convert = builder.add(ConvertUnitsNode.self, values)
        if series {
            let source = builder.add(SeriesNode.self, ["start": .number(1), "step": .number(1), "count": .integer(3)])
            builder.wire(source, "values", to: convert, "value")
        }
        var graph = builder.graph
        graph.nodes[convert.id]?.isOutput = true
        let app = await makeApp(graph)
        app.editor.selection = [convert.id]
        return app.editor.inspectorPage.sections.first { $0.title == "Convert" }?.rows.last { row in
            if case .recipe("Result", _) = row { return true }
            if case .readOnly("Result", _) = row { return true }
            return false
        }
    }

    func text(_ row: InspectorRow?) -> String? {
        switch row {
        case .recipe(_, let text)?, .readOnly(_, let text)?: text
        default: nil
        }
    }

    @Test func oneInchReadsTwentyFivePointFour() async {
        #expect(text(await result([:])) == "25.4")
    }

    @Test func oneeightyDegreesReadsPi() async {
        #expect(text(await result(["value": .number(180), "quantity": .integer(1)])) == "3.14159")
    }

    @Test func aListReadsItsValues() async {
        #expect(text(await result([:], series: true)) == "25.4, 50.8, 76.2")
    }

    @Test func aLongListIsCut() {
        var builder = GraphBuilder()
        let convert = builder.add(ConvertUnitsNode.self)
        let values = (1...20).map { Scalar.number(Double($0)) }
        let results = [convert.id: NodeResult(state: .ok(duration: .zero), outputs: ["value": .list(values)])]
        guard case .recipe(_, let text) = InspectorBuilder.resultRow("value", node: convert, results: results) else {
            Issue.record("a list is a wrapping recipe row")
            return
        }
        #expect(text == "1, 2, 3, 4, 5, 6, 7, 8 … (20 values)")
    }

    @Test func beforeTheFirstRunItSaysSo() {
        var builder = GraphBuilder()
        let convert = builder.add(ConvertUnitsNode.self)
        #expect(text(InspectorBuilder.resultRow("value", node: convert, results: [:])) == "No result yet")
    }
}
