import CreatorGeometry

/// The marks on a section's parent (R6), in sheet millimetres, by standard.
public struct SectionMarkStyle: Hashable, Sendable {
    /// The cutting-plane line's width.
    public let chainWidth: Double
    /// The thick length from each end inward (0: the whole line is thick).
    public let thickEndLength: Double
    /// The thick length each side of a step's corner.
    public let thickCornerLength: Double
    /// An arrow's shaft, from the line's end along the viewing direction.
    public let arrowShaft: Double
    /// From an arrow's tip or a detail circle to its letter.
    public let letterGap: Double
    /// An auxiliary view's arrow tip to its edge.
    public let viewArrowGap: Double

    /// A detail's letter sits along this diagonal from its centre.
    public var letterDiagonal: Vector2 { Vector2((0.5).squareRoot(), (0.5).squareRoot()) }

    private static let iso = SectionMarkStyle(
        chainWidth: 0.25, thickEndLength: 5, thickCornerLength: 3, arrowShaft: 7, letterGap: 1, viewArrowGap: 2)
    private static let asme = SectionMarkStyle(
        chainWidth: 0.6, thickEndLength: 0, thickCornerLength: 0, arrowShaft: 8, letterGap: 1.5, viewArrowGap: 2)

    public static func of(_ standard: DrawingStandard) -> SectionMarkStyle { standard == .iso ? iso : asme }
}
