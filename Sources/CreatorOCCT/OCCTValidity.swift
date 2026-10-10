/// What OCCT's checker (`BRepCheck_Analyzer`, via `occt_is_valid`) says about a shape.
enum OCCTValidity: Equatable, Sendable {
    /// The checker accepts the shape.
    case valid
    /// The checker ran and rejects the shape.
    case invalid
    /// The checker itself threw (`occt_is_valid` returned -1): the shape is neither known good nor known bad.
    case unchecked

    /// Reads `occt_is_valid`'s result: 1 valid, 0 invalid, anything else (-1) unchecked.
    init(status: Int32) {
        switch status {
        case 1: self = .valid
        case 0: self = .invalid
        default: self = .unchecked
        }
    }
}
