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
                "Add Dimension", "Add Hole Callout", "Add Centre Mark", "Add Centre Line", "Add Note", "Add Leader",
                "Reattach Dimension", "Remove Leader", "Move Dimension", "Move Note", "Move Annotations", "Delete Dimension",
                "Delete Note", "Delete Annotations", "Change Dimension", "Change Tolerance", "Edit Note", "Change Number Format",
            ])
        #expect(DrawingStepName.all.count == 31)
        for name in DrawingStepName.all { #expect(!name.contains { $0.isNumber }, "\(name)") }
    }

    private static func dimensionID(_ sheet: DrawingSheet) -> AnnotationID {
        sheet.annotations.first { if case .dimension = $0.kind { true } else { false } }!.id
    }

    private static func noteID(_ sheet: DrawingSheet) -> AnnotationID {
        sheet.annotations.first { if case .note = $0.kind { true } else { false } }!.id
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
        Case(name: "setDimensionKind", expected: "Change Dimension") { h, s, _, _ in
            h.model.setDimensionKind(.linear(.vertical), of: Self.dimensionID(s))
        },
        Case(name: "setPrecision", expected: "Change Dimension") { h, s, _, _ in h.model.setPrecision(2, of: Self.dimensionID(s)) },
        Case(name: "setPrefix", expected: "Change Dimension") { h, s, _, _ in h.model.setPrefix("~", of: Self.dimensionID(s)) },
        Case(name: "setSuffix", expected: "Change Dimension") { h, s, _, _ in h.model.setSuffix("x", of: Self.dimensionID(s)) },
        Case(name: "setTolerance", expected: "Change Tolerance") { h, s, _, _ in
            h.model.setTolerance(.symmetric(0.1), of: Self.dimensionID(s))
        },
        Case(name: "setNoteText", expected: "Edit Note") { h, s, _, _ in h.model.setNoteText("Other", of: Self.noteID(s)) },
        Case(name: "removeLeader", expected: "Remove Leader") { h, s, _, _ in h.model.removeLeader(at: 0, of: Self.noteID(s)) },
        Case(name: "setGeneralTolerance", expected: "Edit Title Block") { h, _, _, _ in
            h.model.setGeneralTolerance(.iso2768(.f, nil))
        },
        Case(name: "setDecimalSign", expected: "Change Number Format") { h, _, _, _ in h.model.setDecimalSign(.comma) },
        Case(name: "setShowsCentreMarks", expected: "Change View") { h, _, v, _ in h.model.setShowsCentreMarks(false, of: v.id) },
        Case(name: "deleteDimension", expected: "Delete Dimension") { h, s, _, _ in
            h.model.selectedAnnotations = [Self.dimensionID(s)]
            h.model.deleteSelection()
        },
        Case(name: "deleteNote", expected: "Delete Note") { h, s, _, _ in
            h.model.selectedAnnotations = [Self.noteID(s)]
            h.model.deleteSelection()
        },
        Case(name: "deleteAnnotations", expected: "Delete Annotations") { h, s, _, _ in
            h.model.selectedAnnotations = Set(s.annotations.map(\.id))
            h.model.deleteSelection()
        },
        Case(name: "nudgeNote", expected: "Move Note") { h, s, _, _ in
            h.model.selectedAnnotations = [Self.noteID(s)]
            h.model.keyPressed(.nudge(Vector2(1, 0), isRepeat: false))
        },
    ]

    private func fixture() -> (EditorHarness, DrawingSheet, DrawingView, [NodeID]) {
        let sources = EditorHarness.sources()
        let view = EditorDocuments.view(at: Vector2(100, 150), source: sources[0].id)
        let dimension = DrawingAnnotation(
            view: view.id,
            kind: .dimension(
                DrawingDimension(
                    kind: .linear(.horizontal), anchors: [.point(Vector2(0, 0)), .point(Vector2(10, 0))],
                    placement: DimensionPlacement(offset: 5, angle: 0))))
        let note = DrawingAnnotation(
            view: view.id,
            kind: .note(
                DrawingNote(text: "Note", position: Vector2(20, 0), leaders: [LeaderEnd(target: .point(Vector2(1, 1)), hint: .zero)])))
        let sheet = DrawingSheet(name: "Sheet 1", views: [view], annotations: [dimension, note])
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
        let dimension = (id: Self.dimensionID(sheet), 0), note = (id: Self.noteID(sheet), 0)
        m.setDimensionKind(.linear(.horizontal), of: dimension.id)
        m.setPrecision(nil, of: dimension.id)
        m.setPrefix("", of: dimension.id)
        m.setSuffix("", of: dimension.id)
        m.setTolerance(.general, of: dimension.id)
        m.setNoteText("Note", of: note.id)
        m.setShowsCentreMarks(view.showsCentreMarks, of: view.id)
        m.setGeneralTolerance(m.document.settings.generalTolerance)
        m.setDecimalSign(m.document.settings.decimalSign)
        m.removeLeader(at: 9, of: note.id)
        #expect(h.log.commits.isEmpty)
    }
}
