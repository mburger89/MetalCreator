import Foundation
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
        let app = await makeApp(builder.graph)
        app.editor.selection = [convert.id]
        await app.settle()
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

    /// In Final preview a selected Convert Units with no Output is evaluated for its Result row; an unselected one is not, and
    /// the viewport's scene is untouched either way.
    @Test func finalPreviewDemandsOnlyTheSelectedConvertUnits() async {
        var builder = GraphBuilder()
        let box = builder.box()
        let selected = builder.add(ConvertUnitsNode.self)
        let other = builder.add(ConvertUnitsNode.self)
        let app = await makeApp(builder.graph)
        #expect(app.previewMode == .final && box.output.isOutput)
        #expect(app.document.results[selected.id]?.outputs == nil && app.document.results[other.id]?.outputs == nil)
        let items = app.viewport.items.count
        app.editor.selection = [selected.id]
        await app.settle()
        let convert = app.editor.inspectorPage.sections.first { $0.title == "Convert" }
        let row = convert?.rows.first { if case .recipe("Result", _) = $0 { true } else { false } }
        #expect(text(row) == "25.4")
        #expect(app.document.results[other.id]?.outputs == nil, "an unselected node is not forced")
        #expect(app.viewport.items.count == items, "the scene gains nothing")
        app.editor.selection = [other.id]
        await app.settle()
        #expect(app.document.results[other.id]?.outputs != nil)
        #expect(app.viewport.items.count == items)
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

    @Test(arguments: ["en_US", "sv_SE", "fa_IR", "ar_EG"], [-0.0, 0.0])
    func aZeroResultHasNoSign(_ identifier: String, _ value: Double) {
        let locale = Locale(identifier: identifier)
        #expect(InspectorBuilder.resultNumber(value, locale: locale) == InspectorBuilder.resultNumber(0, locale: locale))
    }

    @Test func aTinyResultIsNeverShownAsZero() {
        #expect(InspectorBuilder.resultNumber(0.000001) == "1E-6")
        #expect(InspectorBuilder.resultNumber(-0.000001) == "-1E-6")
        #expect(InspectorBuilder.resultNumber(0.00001) == "0.00001")
        #expect(InspectorBuilder.resultNumber(3.14159265) == "3.14159")
        #expect(InspectorBuilder.resultNumber(25.4) == "25.4")
    }

    @Test func beforeTheFirstRunItSaysSo() {
        var builder = GraphBuilder()
        let convert = builder.add(ConvertUnitsNode.self)
        #expect(text(InspectorBuilder.resultRow("value", node: convert, results: [:])) == "No result yet")
    }
}
