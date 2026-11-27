#if canImport(CreatorOCCT)
// Test fixture file: `draggableAssemblySheet` and the dimension drag for `drawing-drag-warm`.
import CreatorDrawing
import CreatorDrawingEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorApp

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
        // A dimension the editor can really drag: the press on its label must pick it, not a balloon or a neighbour, and a nudge
        // must move it. Each held candidate is tried alone on the ballooned sheet.
        var chosen: AnnotationID?
        var document = ballooned
        for id in ids where reports[id]?.status == .held {
            var trial = ballooned
            trial.sheets[0].setAnnotation(try #require(candidates.sheets[0].annotation(id)))
            try app.document.perform(.setDrawings(trial), name: "Test")
            app.refreshDrawing()
            await app.settle()
            if await DimensionDragFixture.canDrag(app, id) {
                chosen = id
                document = trial
                break
            }
        }
        let dimension = try #require(chosen, "a held length on a horizontal edge that the editor can drag")
        try app.document.perform(.setDrawings(empty), name: "Test")
        app.refreshDrawing()
        await app.settle()
        return (document, dimension)
    }
}

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

    /// Whether pressing on the label and nudging it moves the dimension; the gesture is cancelled, leaving the sheet as it was.
    static func canDrag(_ app: AppModel, _ id: AnnotationID) async -> Bool {
        let editor = app.drawing.editor
        guard let drag = try? press(app, id) else { return false }
        drag.step(to: 1)
        var moved = false
        if case .dimension(let dimension)? = editor.document.sheets[0].annotation(id)?.kind {
            moved = abs(dimension.placement.offset - drag.offsetBefore) > 0.5
        }
        editor.primaryCancelled()
        await app.settle()
        return moved
    }

    /// The part a balloon's leader is attached to, nil for anything else.
    private static func target(of annotation: DrawingAnnotation?) -> AnchorTarget? {
        if case .balloon(let balloon)? = annotation?.kind { balloon.leader.target } else { nil }
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
        let unchanged = balloonsBefore.allSatisfy { Self.target(of: sheet.annotation($0.id)) == Self.target(of: $0) }
        return DimensionDragOutcome(moved: offset - offsetBefore, balloonsHeld: held, balloonsUnchanged: unchanged)
    }
}

struct DimensionDragOutcome {
    /// How far the dimension's offset changed, in millimetres.
    let moved: Double
    let balloonsHeld: Int
    /// Every balloon is still attached to the same part (the target its leader had before the press).
    let balloonsUnchanged: Bool
}

enum DimensionDragError: Error { case notADimension }
#endif
