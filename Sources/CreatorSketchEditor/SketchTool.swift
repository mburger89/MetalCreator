/// The sketch editor's tools (sketcher spec §8's toolbar): the drawing tools, Dimension, the tools that change what's
/// drawn through `SketchCommands` (Trim, Extend, Fillet, Mirror, Pattern), and Project, which takes the model's edges.
public enum SketchTool: Hashable, Sendable, CaseIterable {
    /// Click to select (⇧ adds), drag a point to move it.
    case select
    /// Lines chain from click to click (L).
    case line
    /// Centre, start, end (A).
    case arc
    /// Start, end, then a point the arc passes through (A again, from Arc).
    case arcThreePoint
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
    /// With geometry selected, click a point to copy the selection around it, or a line to copy it along the line
    /// (`SketchToolOptions.patternCount`, `patternSpacing`).
    case pattern
    /// Click an edge of the model (a face gives all its edges) to project it onto the sketch (P). It declines the plane
    /// click, so the viewport's ID-buffer pick reaches `clickedModel`.
    case project

    /// The toolbar's title.
    public var title: String {
        switch self {
        case .select: "Select"
        case .line: "Line"
        case .arc: "Arc"
        case .arcThreePoint: "3-Point Arc"
        case .circle: "Circle"
        case .point: "Point"
        case .dimension: "Dimension"
        case .trim: "Trim"
        case .extend: "Extend"
        case .fillet: "Fillet"
        case .mirror: "Mirror"
        case .pattern: "Pattern"
        case .project: "Project"
        }
    }

    /// What to do with the tool, for the inspector; `nil` for the drawing tools, whose rubber band says it.
    public var hint: String? {
        switch self {
        case .trim: "Click the part of a curve to remove, between the curves crossing it."
        case .extend: "Click a line or an arc near the end to extend to the next curve."
        case .fillet: "Click a corner where two lines meet."
        case .mirror: "Select the geometry, then click the line to mirror it about."
        case .pattern: "Select the geometry, then click a point to copy it around, or a line to copy it along."
        case .arcThreePoint: "Click the start, the end, then a point the arc passes through."
        case .project: "Click an edge of the model, or a face for all its edges, to project it onto the sketch."
        case .select, .line, .arc, .circle, .point, .dimension: nil
        }
    }

    /// Whether a click places a point (the rubber band then marks where it would land).
    var placesPoints: Bool {
        switch self {
        case .line, .arc, .arcThreePoint, .circle, .point: true
        case .select, .dimension, .trim, .extend, .fillet, .mirror, .pattern, .project: false
        }
    }

    /// Whether the tool acts on a curve, so the pointer picks the curve under it even over one of its points.
    var picksCurves: Bool {
        switch self {
        case .trim, .extend, .mirror: true
        case .select, .line, .arc, .arcThreePoint, .circle, .point, .dimension, .fillet, .pattern, .project: false
        }
    }
}
