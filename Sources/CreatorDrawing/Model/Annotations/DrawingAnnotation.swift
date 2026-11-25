public enum AnnotationKind: Hashable, Sendable {
    case dimension(DrawingDimension)
    case holeCallout(HoleCallout)
    case centreMark(CentreMark)
    case centreLine(CentreLine)
    case note(DrawingNote)
}

/// One annotation of a sheet (plan R2): on a view (`view`), or free on the sheet when nil.
public struct DrawingAnnotation: Hashable, Codable, Sendable, Identifiable {
    public var id: AnnotationID
    public var view: ViewID?
    public var kind: AnnotationKind
    public var last: LastGood?

    public init(id: AnnotationID = AnnotationID(), view: ViewID?, kind: AnnotationKind, last: LastGood? = nil) {
        self.id = id
        self.view = view
        self.kind = kind
        self.last = last
    }
}
