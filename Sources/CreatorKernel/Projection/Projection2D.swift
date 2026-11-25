import CreatorGeometry

/// One curve of a projection, in model millimetres in the view plane. Angles are radians, a positive sweep counter-clockwise, a
/// full circle 2 pi; an ellipse's angles are parametric and `majorAxis` is a unit vector.
public enum ProjectedCurve: Hashable, Sendable {
    case line(Vector2, Vector2)
    case arc(center: Vector2, radius: Double, start: Double, sweep: Double)
    case ellipse(center: Vector2, majorAxis: Vector2, majorRadius: Double, minorRadius: Double, start: Double, sweep: Double)
    case polyline([Vector2])
}

public enum LineVisibility: String, Sendable { case visible, hidden }

public enum LineClass: String, Sendable { case sharp, smooth, outline, sheetBoundary, curve }

/// What a projected line came from; `curve(index:piece:)` is a free curve's piece.
public enum ProjectionSource: Hashable, Sendable {
    case edge(EdgeID)
    case face(FaceID)
    case curve(index: Int, piece: Int)
}

public struct ProjectedLine: Hashable, Sendable {
    public var visibility: LineVisibility
    public var lineClass: LineClass
    public var curve: ProjectedCurve
    /// `nil` only under the plan's fallback (R10).
    public var source: ProjectionSource?

    public init(visibility: LineVisibility, lineClass: LineClass, curve: ProjectedCurve, source: ProjectionSource?) {
        self.visibility = visibility
        self.lineClass = lineClass
        self.curve = curve
        self.source = source
    }
}

public struct Projection2D: Hashable, Sendable {
    public var lines: [ProjectedLine]

    public init(lines: [ProjectedLine] = []) {
        self.lines = lines
    }
}

public struct ProjectionOptions: Hashable, Sendable {
    /// The polyline chord tolerance in model millimetres.
    public var tolerance: Double

    public init(tolerance: Double = 0.01) {
        self.tolerance = tolerance
    }
}
