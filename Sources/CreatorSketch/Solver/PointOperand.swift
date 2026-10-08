import CreatorGeometry

/// A point inside an equation: two unknown columns (x at `column`, y at `column + 1`) or a constant.
enum PointOperand: Hashable, Sendable {
    case unknown(column: Int)
    case constant(Vector2)

    func value(_ x: [Double]) -> Vector2 {
        switch self {
        case .unknown(let column): Vector2(x[column], x[column + 1])
        case .constant(let point): point
        }
    }
}
