/// Adds a dimension at the value its geometry already has, so nothing moves.
public enum MeasuredDimension {
    public struct Added: Hashable, Sendable {
        public var sketch: Sketch
        public var id: DimensionID
        public var value: Double
        public var isDriving: Bool
    }

    /// `evaluated.measuredDimension(kind)` (DIM-2: the value as solved, and whether it can drive, spec §4.4), then adds the
    /// dimension (that value, `isDriving`, `labelPoint` nil, the next dimension name) to `stored` under the ID `stored` assigns
    /// next, the same ID in both. nil when `measuredDimension` is nil (unmeasurable, a suspended projection, a zero length).
    public static func add(_ kind: DimensionKind, measuredOn evaluated: Sketch, to stored: Sketch) -> Added? {
        // `measuredDimension` still reads a suspended projection's last curve; a suspended edge measures nothing.
        guard !touchesSuspendedProjection(kind, in: evaluated), let measured = evaluated.measuredDimension(kind) else {
            return nil
        }
        var sketch = stored
        let id = sketch.addDimension(kind, value: measured.value, isDriving: measured.isDriving)
        return Added(sketch: sketch, id: id, value: measured.value, isDriving: measured.isDriving)
    }

    private static func touchesSuspendedProjection(_ kind: DimensionKind, in sketch: Sketch) -> Bool {
        kind.entities.contains { id in
            if case .projected(let source)? = sketch.entities[id]?.kind { source.isSuspended } else { false }
        }
    }
}
