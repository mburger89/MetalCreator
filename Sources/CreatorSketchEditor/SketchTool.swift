/// The sketch editor's tools (sketcher spec §8's toolbar). S5a has the drawing tools and Dimension; Trim, Fillet,
/// Mirror, Pattern and Project follow in S5b.
public enum SketchTool: Hashable, Sendable, CaseIterable {
    /// Click to select (⇧ adds), drag a point to move it.
    case select
    /// Lines chain from click to click (L).
    case line
    /// Centre, start, end (A).
    case arc
    /// Centre, then a point on the circle (C).
    case circle
    /// A lone point.
    case point
    /// Pick one or two entities; the kind of dimension follows from them (D).
    case dimension

    /// The toolbar's title.
    public var title: String {
        switch self {
        case .select: "Select"
        case .line: "Line"
        case .arc: "Arc"
        case .circle: "Circle"
        case .point: "Point"
        case .dimension: "Dimension"
        }
    }
}
