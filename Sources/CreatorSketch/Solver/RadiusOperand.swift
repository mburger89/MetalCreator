/// A radius inside an equation.
enum RadiusOperand: Hashable, Sendable {
    /// A circle's radius unknown.
    case unknown(column: Int)
    case constant(Double)
    /// An arc's radius: the distance from its centre to this point (its start point).
    case through(PointOperand)
}
