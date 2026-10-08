/// One equation plus where it came from.
struct SolverTerm: Hashable, Sendable {
    enum Role: Hashable, Sendable {
        /// A user constraint or driving dimension. Only these can be named in conflicts.
        case user(SketchConstraintRef)
        /// A condition implied by the model (an arc's equal radii). Never reported, never removed.
        case implicit
        /// A drag target (drag mode, first phase only).
        case drag
    }

    var role: Role
    var equation: Equation

    var userRef: SketchConstraintRef? {
        if case .user(let ref) = role { return ref }
        return nil
    }
}
