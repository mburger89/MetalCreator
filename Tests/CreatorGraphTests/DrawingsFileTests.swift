import CreatorDrawing
import CreatorGeometry
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// The drawings are saved with the top-level graph (DR-1 Task 4): format 20, the key written only when there is a sheet, one command
/// that replaces the document, and the mode and sheet kept as view state.
@MainActor
struct DrawingsFileTests {
    private func reopened(_ file: GraphFile) throws -> GraphFile {
        try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
    }

    private func json(_ file: GraphFile) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: try GraphFileIO.encode(file)) as? [String: Any])
    }

    private func drawings(_ names: String...) -> DrawingDocument {
        DrawingDocument(sheets: names.map { DrawingSheet(name: $0) })
    }

    private func emptyDocument() -> DocumentModel {
        DocumentModel(file: GraphFile(), registry: testRegistry, kernel: FakeKernel())
    }

    @Test func theFormatIs21() {
        #expect(GraphFile.currentFormatVersion == 21)
    }

    @Test func aDocumentWithoutDrawingsHasNoKey() throws {
        let written = try #require(try json(GraphFile())["graph"] as? [String: Any])
        #expect(written["drawings"] == nil)
    }

    @Test func drawingsRoundTripThroughAFile() throws {
        let sheets = drawings("Plate", "Cover")
        let file = GraphFile(graph: Graph(drawings: sheets))
        let written = try #require(try json(file)["graph"] as? [String: Any])
        #expect(written["drawings"] != nil)
        let back = try reopened(file)
        #expect(back == file)
        #expect(back.graph.drawings.sheets.map(\.name) == ["Plate", "Cover"])
        #expect(back.formatVersion == 21)
    }

    @Test func aFormat16FileOpens() throws {
        let text = #"{"formatVersion": 16, "graph": {"nodes": [], "links": [], "parameters": []}}"#
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.formatVersion == 16)
        #expect(file.graph.drawings.isEmpty)
        #expect(try reopened(GraphFile(graph: file.graph)).formatVersion == 21)
    }

    @Test func aFormat17FileOpensAndIsWrittenAs21() throws {
        let text = #"""
        {"formatVersion": 17, "graph": {"nodes": [], "links": [], "parameters": [],
         "drawings": {"settings": {"standard": "iso", "generalTolerance": "ISO 2768-mK", "titleBlockDefaults": {}}, "sheets": []}}}
        """#
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.formatVersion == 17)
        #expect(file.graph.drawings.settings.generalTolerance == .iso2768(.m, .K))
        #expect(try reopened(GraphFile(graph: file.graph)).formatVersion == 21)
    }

    @Test func aFormat18FileOpensAndIsWrittenAs21() throws {
        let text = #"""
        {"formatVersion": 18, "graph": {"nodes": [], "links": [], "parameters": [],
         "drawings": {"settings": {"standard": "iso", "generalTolerance": "ISO 2768-mK", "titleBlockDefaults": {}}, "sheets": []}}}
        """#
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.formatVersion == 18)
        #expect(try reopened(GraphFile(graph: file.graph)).formatVersion == 21)
    }

    /// A format-18 file with two views (the second aligned to the first) and a horizontal dimension on the first, as the DR-2 build
    /// wrote it: a drawing with content, not an empty one.
    @Test func aFormat18FileWithViewsAndADimensionOpensAndIsWrittenAs21() throws {
        let drawings = [
            #"{"settings":{"standard":"iso","titleBlockDefaults":{},"generalTolerance":{"size":"m","#,
            #""type":"iso2768","geometric":"K"}},"sheets":[{"annotations":[{"kind":{"type":"dimension","#,
            #""dimension":{"placement":{"angle":0,"offset":8},"kind":{"type":"linear","direction":"horizontal"},"#,
            #""anchors":[{"point":{"y":0,"x":0},"type":"point"},{"point":{"y":0,"x":40},"type":"point"}]}},"#,
            #""view":"00000000-0000-4000-8000-000000000001","id":"00000000-0000-4000-8000-0000000000D1"}],"#,
            #""name":"Plate","scale":{"numerator":1,"denominator":1},"size":"a3","orientation":"landscape","#,
            #""titleBlock":{},"views":[{"id":"00000000-0000-4000-8000-000000000001","showsCentreMarks":true,"#,
            #""source":"00000000-0000-4000-8000-0000000000A1","showsHidden":false,"center":{"y":120,"x":100},"#,
            #""orientation":{"standard":{"_0":"front"}},"showsTangent":true,"showsLabel":false,"kind":"base"},"#,
            #"{"showsCentreMarks":true,"showsLabel":false,"center":{"y":120,"x":200},"#,
            #""source":"00000000-0000-4000-8000-0000000000A1","id":"00000000-0000-4000-8000-000000000002","#,
            #""orientation":{"standard":{"_0":"right"}},"showsHidden":false,"alignment":{"axis":"horizontal","#,
            #""parent":"00000000-0000-4000-8000-000000000001"},"kind":"projected","showsTangent":true}],"#,
            #""id":"00000000-0000-4000-8000-0000000000E1"}]}"#,
        ].joined()
        let text = #"{"formatVersion": 18, "graph": {"nodes": [], "links": [], "parameters": [], "drawings": "# + drawings + "}}"
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.formatVersion == 18)
        let sheet = try #require(file.graph.drawings.sheets.first)
        #expect(sheet.views.count == 2)
        #expect(sheet.views[1].alignment?.parent == sheet.views[0].id)
        #expect(sheet.annotations.count == 1)
        guard case .dimension(let dimension)? = sheet.annotations.first?.kind else {
            Issue.record("the dimension was lost")
            return
        }
        #expect(dimension.anchors.count == 2 && dimension.placement.offset == 8)
        #expect(sheet.annotations.first?.view == sheet.views[0].id)
        let written = try reopened(GraphFile(graph: file.graph))
        #expect(written.formatVersion == 21)
        #expect(written.graph.drawings == file.graph.drawings)
    }

    @Test func derivedViewsRoundTrip() throws {
        let node = NodeID()
        let base = DrawingView(kind: .base, source: node, orientation: .standard(.top), center: Vector2(100, 100))
        let cutter = SectionCutter(
            frame: base.orientation.frame, points: [Vector2(0, 0), Vector2(20, 0)], viewing: Vector2(0, 1))
        let section = DrawingView(
            kind: .section, source: node, orientation: .custom(SectionFrame.frame(for: cutter)), center: Vector2(100, 200),
            derivation: .section(SectionLine(parent: base.id, cutter: cutter)), letter: "A")
        let detail = DrawingView(
            kind: .detail, source: node, orientation: base.orientation, center: Vector2(200, 100),
            derivation: .detail(DetailCircle(parent: base.id, center: Vector2(5, 5), radius: 4)), letter: "B")
        let file = GraphFile(graph: Graph(drawings: DrawingDocument(sheets: [
            DrawingSheet(name: "Plate", views: [base, section, detail])])))
        let back = try reopened(file)
        #expect(back == file)
        #expect(back.graph.drawings.sheets[0].views.count == 3)
    }

    @Test func aFormat20FileOpensAndIsWrittenAs21() throws {
        let text = #"""
        {"formatVersion": 20, "graph": {"nodes": [], "links": [], "parameters": [],
         "drawings": {"settings": {"standard": "iso", "generalTolerance": "ISO 2768-mK", "titleBlockDefaults": {}}, "sheets": []}}}
        """#
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.formatVersion == 20)
        #expect(try reopened(GraphFile(graph: file.graph)).formatVersion == 21)
    }

    @Test func aNewerFileIsRefused() throws {
        let text = #"{"formatVersion": 22, "graph": {"nodes": [], "links": [], "parameters": []}}"#
        #expect(throws: (any Error).self) { try GraphFileIO.decode(Data(text.utf8), registry: testRegistry) }
    }

    @Test func annotationsRoundTripThroughTheGraphFile() throws {
        let node = NodeID()
        let view = DrawingView(kind: .base, source: node, orientation: .standard(.front), center: Vector2(100, 100))
        let tag = TopoTag(node: node, item: 0, role: .startCap)
        let pick = EdgePick(key: EdgeKey([tag], [TopoTag(node: node, item: 0, role: .endCap)]), matchCount: 1)
        let annotation = DrawingAnnotation(
            id: AnnotationID(), view: view.id,
            kind: .dimension(
                DrawingDimension(
                    kind: .linear(.horizontal), anchors: [.edge(pick), .point(Vector2(1, 2))],
                    placement: DimensionPlacement(offset: 8, angle: 0, textShift: nil), tolerance: .symmetric(0.1))))
        var sheet = DrawingSheet(name: "Plate", views: [view])
        sheet.setAnnotation(annotation)
        var document = DrawingDocument(sheets: [sheet])
        document.settings.decimalSign = .comma
        let file = GraphFile(graph: Graph(drawings: document))
        let back = try reopened(file)
        #expect(back == file)
        #expect(back.graph.drawings.sheets[0].annotations == [annotation])
        #expect(back.graph.drawings.settings.decimalSign == .comma)
    }

    @Test func aFormat19FileOpensAndIsWrittenAs21() throws {
        let text = #"""
        {"formatVersion": 19, "graph": {"nodes": [], "links": [], "parameters": [],
         "drawings": {"settings": {"standard": "iso", "generalTolerance": "ISO 2768-mK", "titleBlockDefaults": {}}, "sheets": []}}}
        """#
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.formatVersion == 19)
        #expect(try reopened(GraphFile(graph: file.graph)).formatVersion == 21)
    }

    @Test func symbolsRoundTrip() throws {
        let node = NodeID()
        let view = DrawingView(kind: .base, source: node, orientation: .standard(.front), center: Vector2(100, 100))
        let tag = TopoTag(node: node, item: 0, role: .startCap)
        let pick = EdgePick(key: EdgeKey([tag], [TopoTag(node: node, item: 0, role: .endCap)]), matchCount: 1)
        let end = LeaderEnd(target: .edge(pick), hint: Vector2(1, 2))
        let size = DrawingAnnotation(
            view: view.id,
            kind: .dimension(
                DrawingDimension(kind: .diameter, anchors: [.edge(pick)], placement: DimensionPlacement(offset: 8, angle: 0))))
        let datum = DrawingAnnotation(
            view: view.id, kind: .datumFeature(DatumFeature(letter: "A", attachment: .dimension(size.id), distance: 12, dimensionEnd: 1)))
        let frame = DrawingAnnotation(
            view: view.id,
            kind: .featureControl(
                FeatureControlFrame(
                    characteristic: .position,
                    rows: [ToleranceRow(zone: .diameter, value: 0.1, material: .maximum, datums: [DatumReference(letter: "A")])],
                    attachment: .feature(end), offset: Vector2(5, -5))))
        let surface = DrawingAnnotation(
            view: view.id,
            kind: .surfaceTexture(
                SurfaceTexture(
                    requirement: SurfaceRequirement(process: .removalRequired, parameter: .ra, value: 1.6), lay: .circular,
                    feature: end)))
        var sheet = DrawingSheet(name: "Plate", views: [view])
        for annotation in [size, datum, frame, surface] { sheet.setAnnotation(annotation) }
        sheet.notes = SheetNotes(lines: ["Deburr."], edgeBreak: EdgeBreak(minimum: 0.2, maximum: 0.4))
        let file = GraphFile(graph: Graph(drawings: DrawingDocument(sheets: [sheet])))
        let back = try reopened(file)
        #expect(back == file)
        #expect(back.graph.drawings.sheets[0].annotations.count == 4)
        #expect(back.graph.drawings.sheets[0].notes == sheet.notes)
    }

    @Test func setDrawingsIsUndoable() throws {
        let document = emptyDocument()
        let one = drawings("Sheet 1")
        try document.perform(.setDrawings(one), name: UndoName.drawing("Add Sheet"))
        #expect(document.drawings == one)
        #expect(document.undoName == "Add Sheet")
        document.undo()
        #expect(document.drawings.isEmpty)
        #expect(document.redoName == "Add Sheet")
        document.redo()
        #expect(document.drawings == one)
    }

    @Test func setDrawingsDoesNotEvaluate() async throws {
        let command = GraphCommand.setDrawings(drawings("A"))
        #expect(command.affectsResults == false)
        #expect(command.touchedNodes.isEmpty)
        let document = emptyDocument()
        await document.waitForEvaluation()
        try document.perform(command, name: UndoName.drawing("Add Sheet"))
        #expect(!document.isEvaluating, "no evaluation was scheduled")
    }

    @Test func drawingsMakeTheDocumentEdited() throws {
        let document = emptyDocument()
        let saved = document.content
        try document.perform(.setDrawings(drawings("A")), name: UndoName.drawing("Add Sheet"))
        #expect(document.content != saved)
    }

    @Test func setDrawingsInsideADefinitionIsRefused() throws {
        let definition = Doubler().definition
        let document = DocumentModel(file: GraphFile(graph: graph([]), definitions: table([definition])), registry: testRegistry,
                                     kernel: FakeKernel())
        #expect(throws: GraphError.invalidValue("Drawings belong to the document, not to a group.")) {
            try document.perform(.setDrawings(drawings("A")), at: .definition(definition.id), name: UndoName.drawing("Add Sheet"))
        }
        #expect(document.drawings.isEmpty)
    }

    @Test func drawingViewStateRoundTrips() throws {
        let sheet = SheetID()
        for state in [DrawingViewState(isOn: true, sheet: sheet), DrawingViewState(isOn: false, sheet: nil)] {
            let view = ViewState(drawing: state)
            #expect(try JSONDecoder().decode(ViewState.self, from: JSONEncoder().encode(view)) == view)
        }
        let none = try #require(String(bytes: JSONEncoder().encode(ViewState()), encoding: .utf8))
        #expect(!none.contains("\"drawing\""))
        let damaged = try JSONDecoder().decode(ViewState.self, from: Data(#"{"drawing":{"isOn":"yes"}}"#.utf8))
        #expect(damaged.drawing == nil)
        let file = GraphFile(viewState: ViewState(drawing: DrawingViewState(isOn: true, sheet: sheet)))
        #expect(try reopened(file).viewState.drawing == DrawingViewState(isOn: true, sheet: sheet))
    }

    @Test func drawingViewIsNotAnEdit() {
        let document = emptyDocument()
        let before = document.content
        let undoName = document.undoName
        document.drawingView = DrawingViewState(isOn: true, sheet: SheetID())
        #expect(document.content == before)
        #expect(document.undoName == undoName)
        #expect(document.viewState.drawing == document.drawingView)
        document.viewState = ViewState()
        #expect(document.drawingView == nil)
    }

    @Test func aBlankNameIsEditDrawing() {
        #expect(UndoName.drawing("  ") == "Edit Drawing")
        #expect(UndoName.drawing("") == UndoName.editDrawing)
        #expect(UndoName.drawing("Add Sheet") == "Add Sheet")
    }
}

/// DR-5 Task 1: the assembly model survives a file (format 21).
@MainActor
struct DR5FileTests {
    private func reopened(_ file: GraphFile) throws -> GraphFile {
        try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
    }

    @Test func dr5RoundTrips() throws {
        let part = NodeID(), other = NodeID()
        let tag = TopoTag(node: part, item: 0, role: .startCap)
        let pick = EdgePick(key: EdgeKey([tag], [TopoTag(node: part, item: 0, role: .endCap)]), matchCount: 1)
        let view = DrawingView(
            kind: .base, source: part, orientation: .standard(.front), center: Vector2(100, 100), assembly: [part, other])
        let dimension = DrawingAnnotation(
            view: view.id,
            kind: .dimension(
                DrawingDimension(
                    kind: .linear(.horizontal), anchors: [.onPart(part, .edge(pick)), .onPart(other, .edge(pick))],
                    placement: DimensionPlacement(offset: 8, angle: 0, textShift: nil))))
        let balloon = DrawingAnnotation(
            view: view.id,
            kind: .balloon(Balloon(leader: LeaderEnd(target: .onPart(other, .edge(pick)), hint: Vector2(3, 4)), offset: Vector2(9, 9))))
        let list = DrawingAnnotation(view: nil, kind: .partsList(PartsList(bottomRight: Vector2(200, 40))))
        let table = DrawingAnnotation(
            view: nil,
            kind: .revisionTable(RevisionTable(rows: [RevisionRow(letter: "A", description: "First", date: "d", approved: "MB")])))
        var block = TitleBlock(owner: "Acme")
        block.logo = ImageHash(of: Data("logo".utf8)).hex
        let sheet = DrawingSheet(name: "A", titleBlock: block, views: [view], annotations: [dimension, balloon, list, table])
        let document = DrawingDocument(
            sheets: [sheet], items: [PartItem(part: other, material: "Steel", partNumber: "P-1")],
            partNames: [PartName(part: part, name: "Plate"), PartName(part: other, name: "Bolt")])
        let file = GraphFile(graph: Graph(drawings: document))
        let back = try reopened(file)
        #expect(back == file)
        #expect(back.formatVersion == 21)
        #expect(back.graph.drawings == document)
    }

    @Test func aLogoKeepsItsImage() throws {
        let used = Data("used logo".utf8), unused = Data("unused".utf8)
        let usedHash = ImageHash(of: used), unusedHash = ImageHash(of: unused)
        let sheet = DrawingSheet(name: "A", titleBlock: TitleBlock(logo: usedHash.hex))
        let file = GraphFile(graph: Graph(drawings: DrawingDocument(sheets: [sheet])), images: [usedHash: used, unusedHash: unused])
        let model = DocumentModel(file: file, registry: testRegistry, kernel: FakeKernel())
        let written = try GraphFileIO.decode(try model.fileData(), registry: testRegistry)
        #expect(written.images[usedHash] == used)
        #expect(written.images[unusedHash] == nil)
    }
}
