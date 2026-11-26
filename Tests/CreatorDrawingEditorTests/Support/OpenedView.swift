import CreatorGeometry
import CreatorKernel

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// One view on a sheet at (150, 150) with its content, the mapping its lines have there and a harness over them.
@MainActor
struct OpenedView {
    typealias Fixtures = AnnotationEditorFixtures

    let h: EditorHarness
    let view: DrawingView
    let mapping: ViewMapping
    let content: ViewContent

    static func make(
        _ content: ViewContent, orientation: StandardOrientation, zoom: Double = 1,
        annotations: (ViewID) -> [DrawingAnnotation] = { _ in [] }, units: DocumentUnits = .millimetres
    ) -> OpenedView {
        let view = EditorDocuments.view(at: Fixtures.centre, orientation: orientation)
        let sheet = DrawingSheet(name: "Sheet 1", views: [view], annotations: annotations(view.id))
        let h = EditorHarness(
            document: EditorDocuments.document([sheet]), sheet: sheet.id, units: units, contents: [view.id: content])
        h.model.transform = SheetTransform(offset: Vector2(0, 297 * zoom), zoom: zoom)
        return OpenedView(h: h, view: view, mapping: Fixtures.mapping(content), content: content)
    }

    /// The sheet point of model-plane point (x, y).
    func at(_ x: Double, _ y: Double) -> Vector2 { mapping.sheet(Vector2(x, y)) }

    func click(_ point: Vector2, _ modifiers: SheetModifiers = []) {
        h.click(point.x, point.y, modifiers)
    }
}
