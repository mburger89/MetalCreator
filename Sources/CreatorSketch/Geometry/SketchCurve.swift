/// A curve of the solved sketch plus the entity it came from.
struct SketchCurve: Hashable, Sendable {
    var source: SketchEntityID
    var shape: CurveShape
}
