/// The regions found in a sketch, plus what didn't form one.
public struct SketchRegionResult: Hashable, Sendable {
    /// Sorted by area (largest first), then centroid x, then centroid y.
    public var regions: [SketchRegion]
    /// Non-construction curves that bound no region (open or dangling).
    public var openCurves: [SketchEntityID]

    /// "2 curves don't form a closed region." when any curve is open, for the node's warning.
    public var warning: String? {
        switch openCurves.count {
        case 0: nil
        case 1: "1 curve doesn't form a closed region."
        default: "\(openCurves.count) curves don't form a closed region."
        }
    }
}
