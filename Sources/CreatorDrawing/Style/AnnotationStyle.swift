/// The sizes and gaps of dimensions on paper, in sheet millimetres (plan R8). Never written as literals at a call site.
public struct AnnotationStyle: Hashable, Sendable {
    public let standard: DrawingStandard
    /// A filled arrowhead's length; its width is a third of it.
    public let arrowLength: Double
    /// Feature to extension line.
    public let extensionGap: Double
    /// An extension line's reach past the dimension line.
    public let extensionOvershoot: Double
    /// An ISO text's baseline above its dimension line (unused by ASME, whose text sits in a break).
    public let textLift: Double
    /// Text to a line it is clear of.
    public let textGap: Double
    /// Baseline dimensions' spacing.
    public let stackSpacing: Double
    /// A leader's horizontal end.
    public let shoulder: Double
    /// Centre lines past the circle or cylinder.
    public let centreOvershoot: Double
    /// A centre mark on a circle of smaller sheet radius is a solid cross.
    public let smallCentre: Double
    /// Stacked tolerance text height over the label's.
    public let toleranceScale: Double
    /// Note line spacing over the text height.
    public let linePitch: Double
    /// A basic dimension's frame.
    public let boxPadding: Double

    public var arrowWidth: Double { arrowLength / 3 }

    public static let iso = AnnotationStyle(
        standard: .iso, arrowLength: 2.5, extensionGap: 0, extensionOvershoot: 2, textLift: 1, textGap: 1, stackSpacing: 8,
        shoulder: 3, centreOvershoot: 2, smallCentre: 3, toleranceScale: 0.75, linePitch: 1.6, boxPadding: 1)

    public static let asme = AnnotationStyle(
        standard: .asme, arrowLength: 3, extensionGap: 1.5, extensionOvershoot: 3, textLift: 0, textGap: 1.5, stackSpacing: 10,
        shoulder: 3, centreOvershoot: 3, smallCentre: 3, toleranceScale: 1, linePitch: 1.6, boxPadding: 1)

    public static func of(_ standard: DrawingStandard) -> AnnotationStyle { standard == .iso ? iso : asme }
}
