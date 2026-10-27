/// The slack of one piece of a wire's route (cable ties spec 2026-10-26 §5.2): a spring on each of its two control points,
/// and the most either offset may be (`cap`, 40% of the piece's length when it was last kicked). All zero at rest.
public struct PieceSpring: Equatable, Sendable {
    public var control1: SpringPoint
    public var control2: SpringPoint
    public var cap: Double

    public init(control1: SpringPoint = SpringPoint(), control2: SpringPoint = SpringPoint(), cap: Double = 0) {
        self.control1 = control1
        self.control2 = control2
        self.cap = cap
    }

    public var isAtRest: Bool { control1 == SpringPoint() && control2 == SpringPoint() }
}
