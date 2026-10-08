import CreatorGeometry

/// One closed region of a sketch: an outer loop and its holes (spec §5). The outer loop runs
/// counter-clockwise and each hole clockwise. Segments follow the loop: an arc traversed
/// clockwise is stored with `end < start`, so every loop stays continuous (`Profile2D.isClosed`
/// holds) even though `Segment2D` documents its arcs as counter-clockwise.
public struct SketchRegion: Hashable, Sendable {
    public var outer: [Segment2D]
    public var holes: [[Segment2D]]
    /// The outer area minus the holes' areas, mm².
    public var area: Double
    public var centroid: Vector2

    public init(outer: [Segment2D], holes: [[Segment2D]], area: Double, centroid: Vector2) {
        self.outer = outer
        self.holes = holes
        self.area = area
        self.centroid = centroid
    }

    /// Today's single-loop profile: the outer loop only. S3 gives `Profile2D` holes and switches
    /// this to `Profile2D(plane:outer:holes:)`; until then holes are not cut.
    public func profile(on plane: Plane) -> Profile2D {
        Profile2D(plane: plane, segments: outer)
    }
}
