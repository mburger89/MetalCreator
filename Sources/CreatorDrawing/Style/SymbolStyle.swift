import CreatorGeometry

/// The proportions of GD&T, datum and surface texture symbols (plan R3 to R6). Members named as factors are multiplied by the
/// lettering height h at the call site (`style.frameHeight * h`); the two millimetre constants are not.
public struct SymbolStyle: Hashable, Sendable {
    /// A frame row's height.
    public let frameHeight: Double
    /// A compartment's padding each side of its content.
    public let framePadding: Double
    /// A datum compartment's least width.
    public let datumCellMinimum: Double
    /// A circled modifier's circle radius.
    public let circleRadius: Double
    /// A circled letter's cap height.
    public let circledLetter: Double
    /// A circled modifier's advance.
    public let circledAdvance: Double
    /// The gap between a frame's pieces.
    public let modifierGap: Double
    /// A datum square's side.
    public let datumSquare: Double
    /// A datum triangle's side.
    public let datumTriangle: Double
    /// A datum symbol's least leader length.
    public let datumLeaderMinimum: Double
    /// A surface texture symbol's short leg.
    public let surfaceShort: Double
    /// A surface texture symbol's long leg.
    public let surfaceLong: Double
    /// Text to the symbol's lines.
    public let surfaceTextGap: Double
    /// Where the lay symbol's box starts, from the apex.
    public let layOrigin: Vector2
    /// The lay symbol's size.
    public let layGlyph: Double
    /// Where a surface symbol goes on a leader when it has no offset.
    public let defaultSurfaceOffset: Vector2
    /// Between stacked notes, in millimetres.
    public let notesGap: Double
    /// A symbol's snap distance to a line, in millimetres.
    public let standSnap: Double

    private static let shared = SymbolStyle(
        frameHeight: 2, framePadding: 0.5, datumCellMinimum: 2, circleRadius: 0.6, circledLetter: 0.7, circledAdvance: 1.2,
        modifierGap: 0.3, datumSquare: 2, datumTriangle: 1.2, datumLeaderMinimum: 1, surfaceShort: 1.4, surfaceLong: 3,
        surfaceTextGap: 0.3, layOrigin: Vector2(1, 0.2), layGlyph: 0.8, defaultSurfaceOffset: Vector2(2, 4), notesGap: 4,
        standSnap: 3)

    /// The same values for both standards today, so a later difference is one place.
    public static func of(_ standard: DrawingStandard) -> SymbolStyle { shared }
}
