import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

@MainActor
@Suite("Sheet editing")
struct SheetEditingTests {
    @Test func addSheetNamesAndDatesIt() throws {
        let h = EditorHarness(document: DrawingDocument(), sheet: nil)
        h.model.addSheet()
        #expect(h.log.commits.count == 1)
        #expect(h.log.commits[0].name == "Add Sheet")
        let sheet = try #require(h.model.document.sheets.first)
        #expect(sheet.name == "Sheet 1")
        #expect(sheet.size == .a3)
        #expect(sheet.orientation == .landscape)
        #expect(sheet.titleBlock.date == "2026-11-24")
        #expect(h.model.currentSheet == sheet.id)
        #expect(h.log.sheets.last == sheet.id)
    }

    @Test func theSmallestUnusedNumber() throws {
        let h = EditorHarness(document: DrawingDocument(), sheet: nil)
        h.model.addSheet()
        h.model.addSheet()
        #expect(h.model.document.sheets.map(\.name) == ["Sheet 1", "Sheet 2"])
        h.model.deleteSheet(h.model.document.sheets[0].id)
        h.model.addSheet()
        #expect(h.model.document.sheets.map(\.name).sorted() == ["Sheet 1", "Sheet 2"])
    }

    @Test func aNewASMESheetIsANSIB() throws {
        let h = EditorHarness(
            document: DrawingDocument(settings: DrawingSettings(standard: .asme)), sheet: nil)
        h.model.addSheet()
        let sheet = try #require(h.model.document.sheets.first)
        #expect(sheet.size == .ansiB)
        #expect(sheet.orientation == .landscape)
    }

    @Test func aNewSheetStartsFromTheTitleDefaults() throws {
        var settings = DrawingSettings()
        settings.titleBlockDefaults = TitleBlock(owner: "Acme", drawnBy: "MB")
        let h = EditorHarness(document: DrawingDocument(settings: settings), sheet: nil)
        h.model.addSheet()
        let block = try #require(h.model.document.sheets.first).titleBlock
        #expect(block.owner == "Acme")
        #expect(block.drawnBy == "MB")
    }

    @Test func renameIsOneStep() throws {
        let sheet = DrawingSheet(name: "Sheet 1")
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        h.model.renameSheet(sheet.id, to: "Plate")
        #expect(h.log.commits.map(\.name) == ["Rename Sheet"])
        #expect(h.model.document.sheets[0].name == "Plate")
    }

    @Test func duplicateCopiesViewsWithNewIDs() throws {
        let parent = EditorDocuments.view(at: Vector2(100, 150))
        let child = EditorDocuments.child(of: parent, axis: .horizontal, at: Vector2(200, 150))
        let sheet = DrawingSheet(name: "Sheet 1", views: [parent, child])
        let other = DrawingSheet(name: "Sheet 2")
        let h = EditorHarness(document: EditorDocuments.document([sheet, other]), sheet: sheet.id)
        h.model.duplicateSheet(sheet.id)
        #expect(h.log.commits.map(\.name) == ["Duplicate Sheet"])
        let sheets = h.model.document.sheets
        #expect(sheets.count == 3)
        #expect(sheets[2].id == other.id)
        let copy = sheets[1]
        #expect(copy.id != sheet.id)
        #expect(copy.views.count == 2)
        #expect(Set(copy.views.map(\.id)).isDisjoint(with: [parent.id, child.id]))
        let copiedChild = try #require(copy.views.first { $0.kind == .projected })
        let copiedParent = try #require(copy.views.first { $0.kind == .base })
        #expect(copiedChild.alignment == ViewAlignment(parent: copiedParent.id, axis: .horizontal))
        #expect(h.model.currentSheet == copy.id)
    }

    @Test func duplicatingRemapsParents() throws {
        let base = EditorDocuments.view(at: Vector2(100, 150))
        let cutter = SectionCutter(
            frame: base.orientation.frame, points: [Vector2(0, 0), Vector2(20, 0)], viewing: Vector2(0, 1))
        let section = DrawingView(
            kind: .section, source: base.source, orientation: .custom(SectionFrame.frame(for: cutter)),
            center: Vector2(100, 250), derivation: .section(SectionLine(parent: base.id, cutter: cutter)), letter: "A")
        let detail = DrawingView(
            kind: .detail, source: base.source, orientation: base.orientation, center: Vector2(200, 150),
            derivation: .detail(DetailCircle(parent: base.id, center: .zero, radius: 5)), letter: "B")
        let sheet = DrawingSheet(name: "Sheet 1", views: [base, section, detail])
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        h.model.duplicateSheet(sheet.id)
        let copy = h.model.document.sheets[1]
        let copiedBase = try #require(copy.views.first { $0.kind == .base })
        let copiedSection = try #require(copy.views.first { $0.kind == .section })
        let copiedDetail = try #require(copy.views.first { $0.kind == .detail })
        #expect(copiedSection.derivation?.parent == copiedBase.id)
        #expect(copiedDetail.derivation?.parent == copiedBase.id)
        #expect(copiedSection.letter == "A")
        #expect(copiedDetail.letter == "B")
    }

    @Test func deleteSelectsTheNeighbour() throws {
        let sheets = ["a", "b", "c"].map { DrawingSheet(name: $0) }
        let h = EditorHarness(document: EditorDocuments.document(sheets), sheet: sheets[1].id)
        h.model.deleteSheet(sheets[1].id)
        #expect(h.log.commits.map(\.name) == ["Delete Sheet"])
        #expect(h.model.currentSheet == sheets[2].id)
        h.model.deleteSheet(sheets[2].id)
        #expect(h.model.currentSheet == sheets[0].id)
        h.model.deleteSheet(sheets[0].id)
        #expect(h.model.currentSheet == nil)
        #expect(h.log.sheets.last == .some(nil))
    }

    @Test func moveSheetReorders() throws {
        let sheets = ["a", "b", "c"].map { DrawingSheet(name: $0) }
        let h = EditorHarness(document: EditorDocuments.document(sheets), sheet: sheets[0].id)
        h.model.moveSheet(sheets[0].id, by: 1)
        #expect(h.model.document.sheets.map(\.name) == ["b", "a", "c"])
        h.model.moveSheet(sheets[0].id, by: 5)
        #expect(h.model.document.sheets.map(\.name) == ["b", "c", "a"])
        #expect(h.log.commits.map(\.name) == ["Move Sheet", "Move Sheet"])
    }

    @Test func editingATitleFieldUpdatesTheDefaults() throws {
        let sheet = DrawingSheet(name: "Sheet 1")
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        h.model.setTitleField(.title, to: "Bracket")
        #expect(h.log.commits.count == 1)
        #expect(h.log.commits[0].name == "Edit Title Block")
        #expect(h.model.document.sheets[0].titleBlock.title == "Bracket")
        #expect(h.model.document.settings.titleBlockDefaults.title == "Bracket")
        let commits = h.log.commits.count
        h.model.setTitleField(.tolerance, to: "ISO 2768-fH")
        #expect(h.log.commits.count == commits)
        #expect(h.model.document.settings.generalTolerance == .iso2768(.m, .K))
    }

    @Test func addSheetFillsAnEmptyTolerance() throws {
        var empty = DrawingDocument()
        empty.settings.generalTolerance = .text("")
        let h = EditorHarness(document: empty, sheet: nil)
        h.model.addSheet()
        #expect(h.model.document.settings.generalTolerance == .standardDefault(for: .iso, inches: false))
        var typed = DrawingDocument()
        typed.settings.generalTolerance = .text("Per drawing 12")
        let kept = EditorHarness(document: typed, sheet: nil)
        kept.model.addSheet()
        #expect(kept.model.document.settings.generalTolerance == .text("Per drawing 12"))
    }

    @Test func changeStandardIsOneStep() throws {
        func sheet(_ name: String) -> (DrawingSheet, ViewID) {
            let parent = EditorDocuments.view(at: Vector2(100, 150))
            let child = EditorDocuments.child(of: parent, axis: .horizontal, at: Vector2(180, 150))
            return (DrawingSheet(name: name, views: [parent, child]), child.id)
        }
        let (first, firstChild) = sheet("one")
        let (second, secondChild) = sheet("two")
        let h = EditorHarness(document: EditorDocuments.document([first, second]), sheet: first.id)
        h.model.setStandard(.asme)
        #expect(h.log.commits.map(\.name) == ["Change Standard"])
        #expect(h.model.document.settings.standard == .asme)
        for (index, id) in [firstChild, secondChild].enumerated() {
            let moved = try #require(h.model.document.sheets[index].view(id))
            #expect(abs(moved.center.x - 20) < 1e-9)
        }
    }

    @Test func sheetChangeIsNotACommit() throws {
        let sheets = ["a", "b"].map { DrawingSheet(name: $0) }
        let h = EditorHarness(document: EditorDocuments.document(sheets), sheet: sheets[0].id)
        h.model.selectSheet(sheets[1].id)
        #expect(h.log.commits.isEmpty)
        #expect(h.model.currentSheet == sheets[1].id)
        #expect(h.log.sheets.last == sheets[1].id)
    }

    @Test func duplicatingRemapsSymbolAttachments() throws {
        let node = NodeID()
        let view = DrawingView(kind: .base, source: node, orientation: .standard(.front), center: Vector2(100, 100))
        let tag = TopoTag(node: node, item: 0, role: .startCap)
        let pick = EdgePick(key: EdgeKey([tag], [TopoTag(node: node, item: 0, role: .endCap)]), matchCount: 1)
        let size = DrawingAnnotation(
            view: view.id,
            kind: .dimension(
                DrawingDimension(kind: .linear(.horizontal), anchors: [.edge(pick)], placement: DimensionPlacement(offset: 5, angle: 0))))
        let frame = DrawingAnnotation(
            view: view.id,
            kind: .featureControl(
                FeatureControlFrame(
                    characteristic: .position, rows: [ToleranceRow(value: 0.1)], attachment: .dimension(size.id))))
        let datum = DrawingAnnotation(
            view: view.id, kind: .datumFeature(DatumFeature(letter: "B", attachment: .dimension(size.id))))
        let sheet = DrawingSheet(name: "Plate", views: [view], annotations: [size, frame, datum])
        let h = EditorHarness(document: DrawingDocument(sheets: [sheet]), sheet: sheet.id)
        h.model.duplicateSheet(sheet.id)
        let copy = try #require(h.model.document.sheets.first { $0.id != sheet.id })
        let copiedSize = try #require(
            copy.annotations.first { if case .dimension = $0.kind { true } else { false } })
        #expect(copiedSize.id != size.id)
        let hanging = copy.symbols(on: copiedSize.id)
        #expect(hanging.count == 2)
        #expect(copy.annotations.count == 3)
        let letters = hanging.compactMap { annotation -> String? in
            if case .datumFeature(let d) = annotation.kind { d.letter } else { nil }
        }
        #expect(letters == ["B"])
        #expect(h.model.document.sheet(sheet.id)?.symbols(on: size.id).count == 2)
    }
}

@MainActor
@Suite("Sheet names")
struct SheetNameTests {
    @Test func duplicateNamesAreUnique() throws {
        let sheet = DrawingSheet(name: "Plate")
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        h.model.duplicateSheet(sheet.id)
        h.model.duplicateSheet(sheet.id)
        h.model.duplicateSheet(sheet.id)
        #expect(h.model.document.sheets.map(\.name).sorted() == ["Plate", "Plate copy", "Plate copy 2", "Plate copy 3"])
    }

    @Test func aCopyNameFillsTheFirstGap() throws {
        let sheets = ["Plate", "Plate copy", "Plate copy 3"].map { DrawingSheet(name: $0) }
        let h = EditorHarness(document: EditorDocuments.document(sheets), sheet: sheets[0].id)
        h.model.duplicateSheet(sheets[0].id)
        #expect(h.model.document.sheets.map(\.name).contains("Plate copy 2"))
    }

    @Test func renamingTrims() throws {
        let sheet = DrawingSheet(name: "Plate")
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        h.model.renameSheet(sheet.id, to: "  Assembly  ")
        #expect(h.model.document.sheets[0].name == "Assembly")
        #expect(h.log.commits.count == 1)
    }

    @Test func aBlankNameIsRefusedWithNoStep() throws {
        let sheet = DrawingSheet(name: "Plate")
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        h.model.renameSheet(sheet.id, to: "   ")
        #expect(h.model.refusal == "A sheet needs a name.")
        #expect(h.model.document.sheets[0].name == "Plate")
        #expect(h.log.commits.isEmpty)
    }

    @Test func aNameAnotherSheetHasIsRefusedWithNoStep() throws {
        let sheets = [DrawingSheet(name: "Plate"), DrawingSheet(name: "Cover")]
        let h = EditorHarness(document: EditorDocuments.document(sheets), sheet: sheets[0].id)
        h.model.renameSheet(sheets[1].id, to: " Plate ")
        #expect(h.model.refusal == "Another sheet already has that name.")
        #expect(h.model.document.sheets[1].name == "Cover")
        #expect(h.log.commits.isEmpty)
        h.model.renameSheet(sheets[0].id, to: "Plate")
        #expect(h.log.commits.isEmpty, "a sheet's own name is no clash, and no change")
        h.model.renameSheet(sheets[1].id, to: "PLATE")
        #expect(h.model.document.sheets[1].name == "PLATE", "names compare exactly after trimming")
        h.model.renameSheet(sheets[0].id, to: "ß")
        h.model.renameSheet(sheets[1].id, to: "SS")
        #expect(h.model.document.sheets.map(\.name) == ["ß", "SS"])
    }

    @Test func switchingSheetsDropsALeaderAndTheHover() throws {
        let sheets = [DrawingSheet(name: "A"), DrawingSheet(name: "B")]
        let h = EditorHarness(document: EditorDocuments.document(sheets), sheet: sheets[0].id)
        h.model.addingLeader = AnnotationID()
        h.model.selectSheet(sheets[1].id)
        #expect(h.model.addingLeader == nil)
        #expect(h.model.hoverCandidate == nil)
    }

    @Test func aLayoutPassWithTheSameSizeStillSettlesTheFit() throws {
        let sheet = DrawingSheet(name: "A")
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        h.model.requestFit()
        h.model.visibleRect = h.model.visibleRect
        let fitted = h.model.transform
        h.model.visibleRect = Rect2D(min: .zero, max: Vector2(500, 300))
        #expect(h.model.transform == fitted, "a later size no longer refits")
    }
}
