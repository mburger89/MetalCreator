/// The outcome of a solve (spec §4).
public enum SketchSolveStatus: Hashable, Sendable {
    /// Every constraint met and no degrees of freedom left.
    case solved
    /// Every constraint met with `dof` degrees of freedom left. Still a usable output.
    case underConstrained(dof: Int)
    /// Some constraints can't all be met, or some are redundant. `conflicts` holds every
    /// minimal conflicting set found (one per independent conflict, `ConflictSearch.setLimit`
    /// at most per component), flattened, components in order.
    case overConstrained(conflicts: [SketchConstraintRef])
    /// The sketch was refused before solving (bad value or reference), or its constraints can
    /// only be met by collapsing or inverting a curve. Unsatisfied components keep their warm start.
    case failed(reason: String)

    /// True for `.solved` and `.underConstrained`, whose geometry is good to output.
    public var isUsable: Bool {
        switch self {
        case .solved, .underConstrained: true
        case .overConstrained, .failed: false
        }
    }
}
