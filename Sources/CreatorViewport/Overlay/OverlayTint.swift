/// What an overlay line or point is drawn in: a role the viewport's theme colours (sketcher spec §8's table).
public enum OverlayTint: Hashable, Sendable {
    /// Geometry that can still move (cyan in Dracula).
    case underConstrained
    /// Geometry the constraints fix (the foreground colour).
    case fullyConstrained
    /// Geometry a conflict names (red).
    case conflicting
    /// Construction geometry (the comment colour); its lines are usually dashed.
    case construction
    /// Geometry projected from the model (purple).
    case projected
    /// Selected geometry: the Sketch node's header colour (green).
    case selected
    /// Geometry under the pointer: the theme's focus colour.
    case hovered
    /// A tool's rubber band, before it's committed: the under-constrained colour, faded.
    case preview
    /// A placement's x, y and z axes (the layout previews' triads, patterns spec §8): the theme's axis colours, as the view
    /// cube's triad draws them.
    case axisX, axisY, axisZ
    /// The fill of a closed region (sketcher spec §8's "faint green fill"): the Sketch node's header colour, faint.
    case region
    /// A driving dimension's lines and text: the theme's dimension colour (dimensions spec §5).
    case dimensionDriving
    /// A reference dimension's lines and text, in parentheses.
    case dimensionReference
}
