import CreatorViewport

/// A sampled slice: the viewport's quad with its values (its ramp is a placeholder, set when it is shown) and the smallest and
/// largest finite value in it.
struct SliceGrid {
    var slice: ViewportSlice
    var extent: ClosedRange<Double>?
}
