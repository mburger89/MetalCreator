#if canImport(CreatorOCCT)
// Test fixture file: `draggableAssemblySheet` and the dimension drag for `drawing-drag-warm`.
import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorApp
@testable import CreatorDrawing

extension DrawingBenchFixtures {
    /// `balloonedAssemblySheet` with one more annotation: an aligned length on a horizontal line edge of the Front view, held on
    /// the composed sheet, for `drawing-drag-warm` to drag. Returns the document and the dimension's ID. Nothing is applied when
    /// this returns. The app must be in Drawing mode with one empty sheet.
    @MainActor
    static func draggableAssemblySheet(_ app: AppModel, outputs: [NodeID]) async throws -> (DrawingDocument, AnnotationID) {
        let empty = app.drawing.editor.document
        let ballooned = try await balloonedAssemblySheet(app, outputs: outputs)
        try app.document.perform(.setDrawings(ballooned), name: "Test")
        app.refreshDrawing()
        await app.settle()
        let front = try #require(ballooned.sheets[0].views.first { $0.kind == .base })
        let topology = try #require(app.drawing.editor.contents[front.id]?.topology)
        var candidates = ballooned
        var ids: [AnnotationID] = []
        for (edge, pick) in namedEdges(in: topology) {
            guard case .line? = edge.curve, let direction = edge.direction, abs(abs(direction.x) - 1) < 1e-9 else { continue }
            let annotation = DrawingAnnotation(
                view: front.id,
                kind: .dimension(
                    DrawingDimension(kind: .linear(.aligned), anchors: [.edge(pick)], placement: DimensionPlacement(offset: 8, angle: 0))))
            candidates.sheets[0].setAnnotation(annotation)
            ids.append(annotation.id)
        }
        try app.document.perform(.setDrawings(candidates), name: "Test")
        app.refreshDrawing()
        await app.settle()
        let reports = try #require(app.drawing.editor.picture?.annotationReports)
        // The choice is by geometry, not by run: the first held candidate, in edge order, whose label centre (where the press
        // lands) lies in no other annotation's frame, grown by the hit test's slack. A sheet keeps its annotations sorted by their random IDs (plan R2), and a
        // press takes the topmost annotation whose frame holds it, so a label under a balloon is picked or missed by chance.
        let others = ballooned.sheets[0].annotations.compactMap { reports[$0.id]?.frame.insetBy(-hitSlack) }
        let free = ids.first { id in
            guard let report = reports[id], report.status == .held, let label = report.textCenter else { return false }
            return !others.contains { $0.contains(label) }
        }
        let dimension = try #require(free, "a held length on a horizontal edge whose label no balloon or the parts list covers")
        var document = ballooned
        document.sheets[0].setAnnotation(try #require(candidates.sheets[0].annotation(dimension)))
        try app.document.perform(.setDrawings(empty), name: "Test")
        app.refreshDrawing()
        await app.settle()
        return (document, dimension)
    }
}

/// `SheetHitTest`'s growth of an annotation's frame, in millimetres.
private let hitSlack = SheetHitTest.annotationGrowth

/// A drag of one dimension's label through the editor's own input path: the press, `primaryChanged` steps, the release.
@MainActor
struct DimensionDragFixture {
    let app: AppModel
    let id: AnnotationID
    /// The label's centre on the sheet, in millimetres, when the press came.
    let origin: Vector2
    let offsetBefore: Double
    let balloonsBefore: [DrawingAnnotation]

    /// Presses on the dimension's label with the Select tool.
    static func press(_ app: AppModel, _ id: AnnotationID) throws -> DimensionDragFixture {
        let editor = app.drawing.editor
        let sheet = try #require(editor.document.sheets.first)
        let label = try #require(editor.picture?.annotationReports[id]?.textCenter)
        guard case .dimension(let dimension)? = sheet.annotation(id)?.kind else { throw DimensionDragError.notADimension }
        editor.press(.select)
        editor.primaryChanged(to: editor.transform.screenPoint(label), modifiers: [])
        let balloons = sheet.annotations.filter { if case .balloon = $0.kind { true } else { false } }
        return DimensionDragFixture(
            app: app, id: id, origin: label, offsetBefore: dimension.placement.offset, balloonsBefore: balloons)
    }

    /// One `primaryChanged`: the pointer `distance` millimetres of sheet from the press, straight up the sheet.
    func step(to distance: Double) {
        let editor = app.drawing.editor
        editor.primaryChanged(to: editor.transform.screenPoint(origin + Vector2(0, distance)), modifiers: [])
    }

    /// The release at `distance`, then the settled result.
    func release(at distance: Double) async -> DimensionDragOutcome {
        let editor = app.drawing.editor
        editor.primaryEnded(at: editor.transform.screenPoint(origin + Vector2(0, distance)), modifiers: [])
        await app.settle()
        let sheet = editor.document.sheets[0]
        var offset = offsetBefore
        if case .dimension(let dimension)? = sheet.annotation(id)?.kind { offset = dimension.placement.offset }
        let held = balloonsBefore.filter { editor.picture?.annotationReports[$0.id]?.status == .held }.count
        let unchanged = balloonsBefore.allSatisfy { sheet.annotation($0.id) == $0 }
        return DimensionDragOutcome(moved: offset - offsetBefore, balloonsHeld: held, balloonsUnchanged: unchanged)
    }
}

struct DimensionDragOutcome {
    /// How far the dimension's offset changed, in millimetres.
    let moved: Double
    let balloonsHeld: Int
    /// Every balloon's whole record (part, hint, offset) is as it was before the press.
    let balloonsUnchanged: Bool
}

enum DimensionDragError: Error { case notADimension }
#endif
