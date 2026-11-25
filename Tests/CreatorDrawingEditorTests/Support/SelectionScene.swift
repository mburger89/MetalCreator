import CreatorGeometry
import CreatorKernel

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The part seen from the top at 4 points per millimetre, with the annotations a test asks for already on its sheet.
@MainActor
struct SelectionScene {
    typealias Fixtures = AnnotationEditorFixtures

    let h: EditorHarness
    let view: DrawingView
    let mapping: ViewMapping

    static let horizontal = AnnotationID()
    static let diameter = AnnotationID()
    static let note = AnnotationID()
    static let mark = AnnotationID()

    enum Piece { case horizontal, diameter, note, mark }

    static func make(_ pieces: [Piece], units: DocumentUnits = .millimetres, removing: [Int] = []) -> SelectionScene {
        let full = Fixtures.topology()
        let content = Fixtures.top(Fixtures.topology(removing: removing))
        let view = EditorDocuments.view(at: Fixtures.centre, orientation: .top)
        let annotations = pieces.map { piece -> DrawingAnnotation in
            switch piece {
            case .horizontal:
                DrawingAnnotation(
                    id: horizontal, view: view.id,
                    kind: .dimension(
                        DrawingDimension(
                            kind: .linear(.horizontal), anchors: [Fixtures.pick(full, 100), Fixtures.pick(full, 103)],
                            placement: DimensionPlacement(offset: 10, angle: 0))))
            case .diameter:
                DrawingAnnotation(
                    id: diameter, view: view.id,
                    kind: .dimension(
                        DrawingDimension(
                            kind: .diameter, anchors: [Fixtures.pick(full, 0)],
                            placement: DimensionPlacement(offset: 2, angle: 0.8))))
            case .note:
                DrawingAnnotation(
                    id: note, view: view.id, kind: .note(DrawingNote(text: "Plate", position: Vector2(60, -10))))
            case .mark:
                DrawingAnnotation(id: mark, view: view.id, kind: .centreMark(CentreMark(anchor: centre(of: Fixtures.pick(full, 0)))))
            }
        }
        let sheet = DrawingSheet(name: "Sheet 1", views: [view], annotations: annotations)
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id, units: units, contents: [view.id: content])
        h.model.transform = SheetTransform(offset: Vector2(0, 297 * 4), zoom: 4)
        return SelectionScene(h: h, view: view, mapping: Fixtures.mapping(content))
    }

    private static func centre(of target: AnchorTarget) -> AnchorTarget {
        if case .edge(let pick) = target { .centre(pick) } else { target }
    }

    var report: [AnnotationID: AnnotationReport] { h.model.picture?.annotationReports ?? [:] }

    /// The middle of what the annotation drew.
    func centre(of id: AnnotationID) -> Vector2 { report[id]?.frame.center ?? .zero }

    /// The middle of its first text.
    func label(of id: AnnotationID) -> Vector2 { report[id]?.textCenter ?? centre(of: id) }

    func press(_ point: Vector2, _ modifiers: SheetModifiers = []) {
        h.model.pointerDown(at: h.canvas(point.x, point.y), modifiers: modifiers)
    }

    func drag(to point: Vector2) {
        h.model.pointerDragged(to: h.canvas(point.x, point.y))
    }

    func release(at point: Vector2) {
        h.model.pointerUp(at: h.canvas(point.x, point.y))
    }

    /// Presses at `from`, drags in two steps to `from + delta` and releases.
    func drag(from: Vector2, by delta: Vector2, _ modifiers: SheetModifiers = []) {
        press(from, modifiers)
        drag(to: from + delta * 0.5)
        drag(to: from + delta)
        release(at: from + delta)
    }

    func annotation(_ id: AnnotationID) -> DrawingAnnotation? { h.model.document.sheets[0].annotation(id) }

    func dimension(_ id: AnnotationID) -> DrawingDimension? {
        guard case .dimension(let value)? = annotation(id)?.kind else { return nil }
        return value
    }

    func note(_ id: AnnotationID) -> DrawingNote? {
        guard case .note(let value)? = annotation(id)?.kind else { return nil }
        return value
    }
}
