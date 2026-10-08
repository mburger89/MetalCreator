/// A constraint or a dimension: anything that adds residuals to the solve. Conflict lists hold
/// these because the spec's own example names a dimension ("Angle d4") as a conflict.
/// Constraints sort before dimensions, then by ID.
public enum SketchConstraintRef: Hashable, Sendable, Comparable, Codable {
    case constraint(SketchConstraintID)
    case dimension(DimensionID)

    public static func < (lhs: SketchConstraintRef, rhs: SketchConstraintRef) -> Bool {
        switch (lhs, rhs) {
        case (.constraint(let a), .constraint(let b)): a < b
        case (.dimension(let a), .dimension(let b)): a < b
        case (.constraint, .dimension): true
        case (.dimension, .constraint): false
        }
    }
}
