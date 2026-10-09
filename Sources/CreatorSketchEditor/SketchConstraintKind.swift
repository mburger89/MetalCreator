import CreatorSketch

/// The constraint buttons (sketcher spec §8: "buttons for each constraint", §3's table). Each makes its constraint
/// from the selection when the selection has the right shape.
public enum SketchConstraintKind: Hashable, Sendable, CaseIterable {
    case coincident, pointOn, horizontal, vertical, parallel, perpendicular, tangent, equal, midpoint, concentric,
         symmetric, fix

    public var title: String {
        switch self {
        case .coincident: "Coincident"
        case .pointOn: "Point on"
        case .horizontal: "Horizontal"
        case .vertical: "Vertical"
        case .parallel: "Parallel"
        case .perpendicular: "Perpendicular"
        case .tangent: "Tangent"
        case .equal: "Equal"
        case .midpoint: "Midpoint"
        case .concentric: "Concentric"
        case .symmetric: "Symmetric"
        case .fix: "Fix"
        }
    }

    /// What to select for it, for the button's help text.
    public var hint: String {
        switch self {
        case .coincident: "Select two points."
        case .pointOn: "Select a point and a curve."
        case .horizontal, .vertical: "Select a line, or two points."
        case .parallel, .perpendicular: "Select two lines."
        case .tangent: "Select a line and an arc or circle, or two arcs or circles."
        case .equal: "Select two lines, or two arcs or circles."
        case .midpoint: "Select a point and a line."
        case .concentric: "Select two arcs or circles."
        case .symmetric: "Select two points and a line."
        case .fix: "Select a point."
        }
    }
}
