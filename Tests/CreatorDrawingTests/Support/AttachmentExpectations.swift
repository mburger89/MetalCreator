import CreatorDrawing
import CreatorGeometry
import Testing

/// A symbol's remembered figure on a straight edge: its foot and tangent, and the edge's two projected ends.
func expectAttachment(
    _ figure: AnnotationFigure?, foot: Vector2, along: Vector2, sourceLocation: SourceLocation = #_sourceLocation
) {
    guard case .attachment(let found, let tangent, let ends)? = figure else {
        Issue.record("expected an attachment figure, found \(String(describing: figure))", sourceLocation: sourceLocation)
        return
    }
    #expect((found - foot).length < 1e-9 && (tangent - along).length < 1e-9, sourceLocation: sourceLocation)
    #expect(ends.count == 2, "a straight edge keeps its two ends", sourceLocation: sourceLocation)
}
