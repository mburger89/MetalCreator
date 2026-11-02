/// The regions found in a sketch, plus what didn't form one.
public struct SketchRegionResult: Hashable, Sendable {
    /// Sorted by area (largest first), then centroid x, then centroid y.
    public var regions: [SketchRegion]
    /// Non-construction curves that bound no region (open or dangling).
    public var openCurves: [SketchEntityID]
    /// Splines that cross themselves: drawn, but left out of the regions.
    public var selfCrossingSplines: [SketchEntityID] = []
    /// One sentence per self-crossing spline, "Spline 4 crosses itself, so it isn't part of a region."
    public var selfCrossingWarnings: [String] = []

    /// "2 curves don't form a closed region." when any curve is open, for the node's warning.
    public var warning: String? {
        switch openCurves.count {
        case 0: nil
        case 1: "1 curve doesn't form a closed region."
        default: "\(openCurves.count) curves don't form a closed region."
        }
    }
}
