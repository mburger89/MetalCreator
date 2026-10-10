/// The sketch editor's tools (sketcher spec §8's toolbar): the drawing tools, Dimension, and the tools that change
/// what's drawn through `SketchCommands` (Trim, Extend, Fillet, Mirror). Project follows in S5c.
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
    /// Click a curve to remove its span between the curves crossing it (T).
    case trim
    /// Click near a line's or an arc's end to extend it to the next curve it meets.
    case extend
    /// Click a corner where two lines meet to round it (`SketchToolOptions.filletRadius`). No key: F frames the sketch.
    case fillet
    /// With geometry selected, click a line to copy the selection mirrored about it.
    case mirror

    /// The toolbar's title.
    public var title: String {
        switch self {
        case .select: "Select"
        case .line: "Line"
        case .arc: "Arc"
        case .circle: "Circle"
        case .point: "Point"
        case .dimension: "Dimension"
        case .trim: "Trim"
        case .extend: "Extend"
        case .fillet: "Fillet"
        case .mirror: "Mirror"
        }
    }

    /// Whether a click places a point (the rubber band then marks where it would land).
    var placesPoints: Bool {
        switch self {
        case .line, .arc, .circle, .point: true
        case .select, .dimension, .trim, .extend, .fillet, .mirror: false
        }
    }

    /// Whether the tool acts on a curve, so the pointer picks the curve under it even over one of its points.
    var picksCurves: Bool {
        switch self {
        case .trim, .extend, .mirror: true
        case .select, .line, .arc, .circle, .point, .dimension, .fillet: false
        }
    }
}
