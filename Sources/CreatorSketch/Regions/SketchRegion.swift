import CreatorGeometry

/// One closed region of a sketch: an outer loop and its holes (spec §5 step 5). Every loop runs
/// counter-clockwise and starts at the segment whose start point is lexicographically smallest;
/// holes are sorted by area descending, then centroid x, then y, so a hole's loop index (its
/// position plus one) is stable. Segments follow the loop: an arc the loop runs along clockwise
/// (a notch in an outline) is stored with `end < start`, so every loop stays continuous
/// (`Profile2D.isClosed` holds) even though `Segment2D` documents its arcs as counter-clockwise.
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

    /// The region as a profile with holes: loop 0 is `outer`, loop n is `holes[n - 1]`.
    public func profile(on plane: Plane) -> Profile2D {
        Profile2D(plane: plane, outer: outer, holes: holes)
    }
}
