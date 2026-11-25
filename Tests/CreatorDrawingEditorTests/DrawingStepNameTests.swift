import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

@MainActor
@Suite("Drawing step names")
struct DrawingStepNameTests {
    @Test func everyNameIsR26sAndHasNoDigits() throws {
        #expect(
            Set(DrawingStepName.all) == [
                "Add Sheet", "Rename Sheet", "Duplicate Sheet", "Delete Sheet", "Move Sheet", "Change Sheet Size",
                "Edit Title Block", "Change Standard", "Add View", "Move View", "Delete View", "Change Scale", "Change View",
            ])
        #expect(DrawingStepName.all.count == 13)
        for name in DrawingStepName.all { #expect(!name.contains { $0.isNumber }, "\(name)") }
    }

    private struct Case {
        var name: String
        var expected: String
        var act: @MainActor (EditorHarness, DrawingSheet, DrawingView, [NodeID]) -> Void
    }

    private static let cases: [Case] = [
        Case(name: "addSheet", expected: "Add Sheet") { h, _, _, _ in h.model.addSheet() },
        Case(name: "renameSheet", expected: "Rename Sheet") { h, s, _, _ in h.model.renameSheet(s.id, to: "Plate") },
        Case(name: "duplicateSheet", expected: "Duplicate Sheet") { h, s, _, _ in h.model.duplicateSheet(s.id) },
        Case(name: "deleteSheet", expected: "Delete Sheet") { h, s, _, _ in h.model.deleteSheet(s.id) },
        Case(name: "moveSheet", expected: "Move Sheet") { h, s, _, _ in h.model.moveSheet(s.id, by: 1) },
        Case(name: "setSheetSize", expected: "Change Sheet Size") { h, _, _, _ in h.model.setSheetSize(.a4) },
        Case(name: "setSheetOrientation", expected: "Change Sheet Size") { h, _, _, _ in
            h.model.setSheetOrientation(.portrait)
        },
        Case(name: "setSheetScale", expected: "Change Scale") { h, _, _, _ in
            h.model.setSheetScale(DrawingScale(numerator: 1, denominator: 2))
        },
        Case(name: "setTitleField title", expected: "Edit Title Block") { h, _, _, _ in h.model.setTitleField(.title, to: "X") },
        Case(name: "setDensity", expected: "Edit Title Block") { h, _, _, _ in h.model.setDensity(7.8) },
        Case(name: "setStandard", expected: "Change Standard") { h, _, _, _ in h.model.setStandard(.asme) },
        Case(name: "setScale", expected: "Change Scale") { h, _, v, _ in
            h.model.setScale(DrawingScale(numerator: 1, denominator: 2), of: v.id)
        },
        Case(name: "setSource", expected: "Change View") { h, _, v, nodes in h.model.setSource(nodes[1], of: v.id) },
        Case(name: "setOrientation", expected: "Change View") { h, _, v, _ in h.model.setOrientation(.top, of: v.id) },
        Case(name: "setShowsHidden", expected: "Change View") { h, _, v, _ in h.model.setShowsHidden(true, of: v.id) },
        Case(name: "setShowsTangent", expected: "Change View") { h, _, v, _ in h.model.setShowsTangent(false, of: v.id) },
        Case(name: "setShowsLabel", expected: "Change View") { h, _, v, _ in h.model.setShowsLabel(true, of: v.id) },
        Case(name: "deleteSelection", expected: "Delete View") { h, _, v, _ in
            h.model.selection = [v.id]
            h.model.deleteSelection()
        },
    ]

    private func fixture() -> (EditorHarness, DrawingSheet, DrawingView, [NodeID]) {
        let sources = EditorHarness.sources()
        let view = EditorDocuments.view(at: Vector2(100, 150), source: sources[0].id)
        let sheet = DrawingSheet(name: "Sheet 1", views: [view])
        let other = DrawingSheet(name: "Sheet 2")
        let h = EditorHarness(
            document: EditorDocuments.document([sheet, other]), sheet: sheet.id, sources: sources)
        return (h, sheet, view, sources.map(\.id))
    }

    @Test func everyMethodCommitsItsStep() throws {
        for entry in Self.cases {
            let (h, sheet, view, nodes) = fixture()
            entry.act(h, sheet, view, nodes)
            #expect(h.log.commits.count == 1, "\(entry.name)")
            #expect(h.log.commits.first?.name == entry.expected, "\(entry.name)")
        }
    }

    @Test func noChangeNoCommit() throws {
        let (h, sheet, view, nodes) = fixture()
        let m = h.model
        m.renameSheet(sheet.id, to: sheet.name)
        m.moveSheet(sheet.id, by: 0)
        m.setSheetSize(sheet.size)
        m.setSheetOrientation(sheet.orientation)
        m.setSheetScale(sheet.scale)
        m.setTitleField(.title, to: sheet.titleBlock.title)
        m.setTitleField(.tolerance, to: "Y")
        m.setTitleField(.mass, to: "9 g")
        m.setTitleField(.scale, to: "1 : 7")
        m.setDensity(sheet.titleBlock.density)
        m.setStandard(m.document.settings.standard)
        m.setScale(nil, of: view.id)
        m.setSource(nodes[0], of: view.id)
        m.setOrientation(.front, of: view.id)
        m.setShowsHidden(view.showsHidden, of: view.id)
        m.setShowsTangent(view.showsTangent, of: view.id)
        m.setShowsLabel(view.showsLabel, of: view.id)
        #expect(h.log.commits.isEmpty)
    }
}
