import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// Copy and paste of views and annotations (DR-5 R18).
@MainActor
@Suite("Clipboard")
struct ClipboardTests {
    private struct Scene {
        let h: EditorHarness
        let first: DrawingSheet
        let second: DrawingSheet
        let base: DrawingView
        let child: DrawingView
        let section: DrawingView
        let dimension: DrawingAnnotation
        let datum: DrawingAnnotation
        let balloon: DrawingAnnotation
        let note: DrawingAnnotation
    }

    private static func dimension(on view: ViewID) -> DrawingAnnotation {
        let value = DrawingDimension(
            kind: .linear(.horizontal), anchors: [.point(Vector2(0, 0)), .point(Vector2(10, 0))],
            placement: DimensionPlacement(offset: 8, angle: 0))
        return DrawingAnnotation(view: view, kind: .dimension(value))
    }

    private func scene(secondScale: DrawingScale = DrawingScale(numerator: 1, denominator: 2)) -> Scene {
        let base = EditorDocuments.view(at: Vector2(100, 150))
        let child = EditorDocuments.child(of: base, axis: .horizontal, at: Vector2(200, 150))
        let cutter = SectionCutter(
            frame: base.orientation.frame, points: [Vector2(0, 0), Vector2(20, 0)], viewing: Vector2(0, 1))
        let section = DrawingView(
            kind: .section, source: base.source, orientation: .custom(SectionFrame.frame(for: cutter)),
            center: Vector2(100, 250), derivation: .section(SectionLine(parent: base.id, cutter: cutter)), letter: "A")
        let dimension = Self.dimension(on: base.id)
        let datum = DrawingAnnotation(
            view: base.id,
            kind: .datumFeature(DatumFeature(letter: "A", attachment: .dimension(dimension.id), distance: 4)))
        let leader = LeaderEnd(target: .point(Vector2(1, 1)), hint: Vector2(1, 1))
        let balloon = DrawingAnnotation(view: base.id, kind: .balloon(Balloon(leader: leader, offset: Vector2(5, 5))))
        let note = DrawingAnnotation(view: nil, kind: .note(DrawingNote(text: "Free", position: Vector2(20, 30))))
        let first = DrawingSheet(
            name: "Sheet 1", scale: DrawingScale(numerator: 1, denominator: 2), views: [base, child, section],
            annotations: [dimension, datum, balloon, note])
        let anchor = EditorDocuments.view(at: Vector2(120, 120))
        let second = DrawingSheet(name: "Sheet 2", scale: secondScale, views: [anchor])
        let h = EditorHarness(document: EditorDocuments.document([first, second]), sheet: first.id)
        return Scene(
            h: h, first: first, second: second, base: base, child: child, section: section, dimension: dimension,
            datum: datum, balloon: balloon, note: note)
    }

    private func copyAll(_ s: Scene) {
        s.h.model.selection = [s.base.id, s.child.id, s.section.id]
        #expect(s.h.model.copySelection())
    }

    @Test func pastingRemapsEverything() throws {
        let s = scene()
        copyAll(s)
        s.h.model.selectSheet(s.second.id)
        #expect(s.h.model.paste())
        #expect(s.h.log.commits.map(\.name) == ["Paste"])
        let sheet = try #require(s.h.model.document.sheet(s.second.id))
        let old: Set<ViewID> = [s.base.id, s.child.id, s.section.id]
        let pasted = sheet.views.filter { $0.id != s.second.views[0].id }
        #expect(pasted.count == 3)
        #expect(pasted.allSatisfy { !old.contains($0.id) })
        let base = try #require(pasted.first { $0.kind == .base })
        let child = try #require(pasted.first { $0.kind == .projected })
        let section = try #require(pasted.first { $0.kind == .section })
        #expect(child.alignment?.parent == base.id)
        #expect(section.derivation?.parent == base.id)
        #expect(section.letter == "A")  // the target has no lettered view yet
        let annotations = sheet.annotations
        #expect(annotations.count == 3)
        let dimension = try #require(annotations.first { if case .dimension = $0.kind { true } else { false } })
        #expect(dimension.id != s.dimension.id)
        #expect(dimension.view == base.id)
        let datum = try #require(annotations.first { $0.symbolKind == .datum })
        #expect(datum.symbolAttachment == .dimension(dimension.id))
        let balloon = try #require(annotations.first { if case .balloon = $0.kind { true } else { false } })
        #expect(balloon.view == base.id)
        #expect(Set(s.h.model.selection) == Set(pasted.map(\.id)))
        #expect(s.h.model.selectedAnnotations.count == 3)
        // One undo takes the whole paste back.
        #expect(s.h.log.commits.count == 1)
        s.h.model.selectSheet(s.first.id)
        #expect(s.h.model.paste())
        let again = try #require(s.h.model.document.sheet(s.first.id))
        #expect(again.views.filter { $0.kind == .section }.compactMap(\.letter).sorted() == ["A", "B"])
    }

    @Test func pastingTwiceOffsetsTwice() throws {
        let s = scene()
        s.h.model.selection = [s.base.id]
        s.h.model.copySelection()
        s.h.model.paste()
        s.h.model.paste()
        let sheet = try #require(s.h.model.document.sheet(s.first.id))
        let centres = sheet.views.map(\.center).sorted { $0.x < $1.x }
        let basesAt = centres.filter { $0.y < 150 && $0.x > 100 }
        #expect(basesAt.contains(Vector2(110, 140)))
        #expect(basesAt.contains(Vector2(120, 130)))
    }

    @Test func pastingOntoAnotherScaleKeepsTheSize() throws {
        let s = scene(secondScale: DrawingScale(numerator: 1, denominator: 5))
        s.h.model.selection = [s.base.id, s.child.id]
        s.h.model.selectedAnnotations = [s.dimension.id]
        s.h.model.copySelection()
        let own = DrawingScale(numerator: 2, denominator: 1)
        s.h.model.selectSheet(s.second.id)
        s.h.model.paste()
        let sheet = try #require(s.h.model.document.sheet(s.second.id))
        let pasted = sheet.views.filter { $0.id != s.second.views[0].id }
        #expect(pasted.count == 2)
        #expect(pasted.allSatisfy { $0.scale == DrawingScale(numerator: 1, denominator: 2) })
        let dimension = try #require(sheet.annotations.first { if case .dimension = $0.kind { true } else { false } })
        guard case .dimension(let value) = dimension.kind else {
            Issue.record("not a dimension")
            return
        }
        #expect(value.placement.offset == 8)

        // An empty sheet of another scale: the views carry the size, the sheet keeps its scale.
        let e = scene()
        let empty = DrawingSheet(name: "Sheet 3", scale: DrawingScale(numerator: 1, denominator: 1))
        var doc = e.h.model.document
        doc.sheets.append(empty)
        e.h.model.replaceDocument(doc)
        e.h.model.selection = [e.base.id, e.child.id]
        e.h.model.copySelection()
        e.h.model.selectSheet(empty.id)
        #expect(e.h.model.paste())
        let filled = try #require(e.h.model.document.sheet(empty.id))
        #expect(filled.views.count == 2)
        #expect(filled.views.allSatisfy { $0.scale == DrawingScale(numerator: 1, denominator: 2) })
        #expect(filled.scale == DrawingScale(numerator: 1, denominator: 1))

        // The same scale sets nothing.
        let t = scene(secondScale: DrawingScale(numerator: 1, denominator: 2))
        t.h.model.selection = [t.base.id, t.child.id]
        t.h.model.copySelection()
        t.h.model.selectSheet(t.second.id)
        t.h.model.paste()
        let same = try #require(t.h.model.document.sheet(t.second.id))
        #expect(same.views.allSatisfy { $0.scale == nil })

        // A view with its own scale keeps it.
        var detail = EditorDocuments.view(at: Vector2(50, 50))
        detail.scale = own
        let sheetWith = DrawingSheet(name: "Sheet 1", scale: DrawingScale(numerator: 1, denominator: 2), views: [detail])
        let other = DrawingSheet(
            name: "Sheet 2", scale: DrawingScale(numerator: 1, denominator: 5), views: [EditorDocuments.view(at: .zero)])
        let h = EditorHarness(document: EditorDocuments.document([sheetWith, other]), sheet: sheetWith.id)
        h.model.selection = [detail.id]
        h.model.copySelection()
        h.model.selectSheet(other.id)
        h.model.paste()
        let target = try #require(h.model.document.sheet(other.id))
        #expect(target.views.contains { $0.scale == own })
    }

    @Test func aDerivedViewAloneIsRefused() {
        let s = scene()
        s.h.model.selection = [s.section.id]
        #expect(!s.h.model.copySelection())
        #expect(s.h.model.refusal == "Copy a section, detail or auxiliary view together with the view it was made from.")
        #expect(s.h.model.clipboard == nil)
        s.h.model.selection = [s.base.id]
        s.h.model.copySelection()
        let before = s.h.model.clipboard
        s.h.model.selection = [s.section.id]
        #expect(!s.h.model.copySelection())
        #expect(s.h.model.clipboard == before)
    }

    @Test func annotationsAlonePasteOnTheirSheet() throws {
        let s = scene()
        s.h.model.selectedAnnotations = [s.note.id]
        let free = s.h.model.copySelection()
        #expect(free)
        s.h.model.selectedAnnotations = []
        // A note of the base view.
        let onView = DrawingAnnotation(view: s.base.id, kind: .note(DrawingNote(text: "On", position: Vector2(1, 2))))
        var sheet = s.first
        sheet.setAnnotation(onView)
        let h = EditorHarness(document: EditorDocuments.document([sheet, s.second]), sheet: sheet.id)
        h.model.selectedAnnotations = [onView.id]
        h.model.copySelection()
        h.model.paste()
        let pasted = try #require(h.model.document.sheet(sheet.id)).annotations.filter {
            $0.id != onView.id && $0.view == s.base.id && { if case .note = $0.kind { true } else { false } }($0)
        }
        #expect(pasted.count == 1)
        guard case .note(let note)? = pasted.first?.kind else {
            Issue.record("no note")
            return
        }
        #expect(note.position == Vector2(11, -8))
        h.model.selectSheet(s.second.id)
        #expect(h.model.paste() == false)
        #expect(h.model.refusal == "Some annotations belong to a view on another sheet, so they weren't pasted.")
        #expect(try #require(h.model.document.sheet(s.second.id)).annotations.isEmpty)
    }

    @Test func aSymbolWithoutItsDimensionIsNotPasted() throws {
        let s = scene()
        s.h.model.selectedAnnotations = [s.datum.id]
        s.h.model.copySelection()
        #expect(!s.h.model.paste())
        #expect(try #require(s.h.model.document.sheet(s.first.id)).annotations.count == 4)
        #expect(s.h.log.commits.isEmpty)
        s.h.model.selectSheet(s.second.id)
        #expect(!s.h.model.paste())
        #expect(
            s.h.model.refusal == "Some symbols hang on a dimension that wasn't copied, so they weren't pasted.")
        #expect(try #require(s.h.model.document.sheet(s.second.id)).annotations.isEmpty)
        #expect(s.h.log.commits.isEmpty)
    }

    @Test func aSecondPartsListIsSkipped() throws {
        let list = DrawingAnnotation(view: nil, kind: .partsList(PartsList()))
        let table = DrawingAnnotation(view: nil, kind: .revisionTable(RevisionTable()))
        let first = DrawingSheet(name: "Sheet 1", annotations: [list, table])
        let h = EditorHarness(document: EditorDocuments.document([first]), sheet: first.id)
        h.model.selectedAnnotations = [list.id, table.id]
        h.model.copySelection()
        #expect(!h.model.paste())
        #expect(
            h.model.refusal == "This sheet has a parts list already. This sheet has a revision table already.")
        #expect(try #require(h.model.document.sheet(first.id)).annotations.count == 2)
    }

    @Test func cutIsCopyThenDelete() throws {
        let s = scene()
        s.h.model.selection = [s.base.id, s.child.id, s.section.id]
        #expect(s.h.model.cutSelection())
        #expect(s.h.log.commits.map(\.name) == ["Cut"])
        #expect(s.h.model.clipboard?.views.count == 3)
        #expect(try #require(s.h.model.document.sheet(s.first.id)).views.isEmpty)
        #expect(s.h.model.paste())
        #expect(s.h.log.commits.map(\.name) == ["Cut", "Paste"])
    }

    @Test func theClipboardIsTheEditors() {
        let s = scene()
        copyAll(s)
        #expect(s.h.model.clipboard != nil)
        #expect(scene().h.model.clipboard == nil)
    }
}
