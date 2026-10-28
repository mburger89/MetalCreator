import CreatorGeometry
import CreatorSketch

/// The Dimension tool's new dimension between its completing pick and the click that places it (spec §4.2): nothing of it is in
/// the document until that click.
public struct PendingDimension: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        /// A circle's or arc's diameter or radius, before the second click.
        case picked
        /// The value box is open.
        case entering
        /// The label follows the pointer; the next click places the dimension.
        case placing
    }

    /// The kind as picked (length, distance, centre distance, …).
    public var aligned: DimensionKind
    /// What it is now: `aligned`, or a horizontal or vertical distance chosen by where the label is.
    public var kind: DimensionKind
    /// Millimetres, or degrees.
    public var value: Double
    public var isDriving: Bool
    public var labelPoint: Vector2
    public var phase: Phase
    /// A typed value fixes the kind: moving the pointer no longer re-chooses the orientation (that would move the geometry).
    public var isOrientationLocked: Bool
}
