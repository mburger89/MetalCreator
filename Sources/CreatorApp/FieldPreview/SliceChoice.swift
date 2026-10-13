/// Where the legend says the slice is: on the field's own plane (the start, when it has one), on an axis plane through the
/// part, or hidden.
enum SliceChoice: Equatable, Sendable {
    case own
    case axis(SliceAxis)
    case hidden
}
