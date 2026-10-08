import CreatorGeometry

extension Sketch {
    /// A line's direction (start → end) with its points read through `position`; projected lines
    /// are constant. `nil` for anything else.
    func lineDirection(_ id: SketchEntityID, position: (SketchEntityID) -> Vector2?) -> Vector2? {
        switch entities[id]?.kind {
        case .line(let start, let end):
            guard let a = position(start), let b = position(end) else { return nil }
            return b - a
        case .projected(let source):
            if case .line(let a, let b) = source.curve { return b - a }
            return nil
        default:
            return nil
        }
    }

    /// The sense nearest the current geometry for an angle dimension of `degrees`, or `nil` for
    /// other kinds and missing lines.
    func nearestAngleSense(for kind: DimensionKind, degrees: Double,
                           position: (SketchEntityID) -> Vector2?) -> AngleSense? {
        guard case .angle(let a, let b) = kind,
              let first = lineDirection(a, position: position), let second = lineDirection(b, position: position),
              first.length > 0, second.length > 0 else { return nil }
        return AngleSense.nearest(from: first, to: second, degrees: degrees)
    }
}
