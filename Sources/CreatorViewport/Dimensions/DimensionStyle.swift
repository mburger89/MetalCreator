/// How dimensions are drawn: the sizes (in points, constant on screen) and the notation of their text.
public struct DimensionStyle: Sendable, Hashable {
    /// The drawing standard the text rules follow. ISO is a later seam (spec §9).
    public enum Notation: Sendable, Hashable {
        case ansi
    }

    public var notation: Notation
    public var arrowLength: Double
    public var arrowWidth: Double
    public var extensionGap: Double
    public var extensionOvershoot: Double
    public var textGap: Double
    public var standoff: Double
    public var leaderLength: Double
    public var shoulderLength: Double
    public var lineWidth: Double

    /// A plane seen more edge-on than this (radians from the view direction) leaves its dimensions out.
    public var edgeOnLimit: Double
    public var pinMarkRadius: Double

    /// ANSI/ASME Y14.5: filled 3:1 arrowheads, text centred in a break of the dimension line.
    public static let ansi = DimensionStyle(
        notation: .ansi,
        arrowLength: 9,
        arrowWidth: 3,
        extensionGap: 3,
        extensionOvershoot: 6,
        textGap: 4,
        standoff: 28,
        leaderLength: 24,
        shoulderLength: 10,
        lineWidth: 1,
        edgeOnLimit: 10 * Double.pi / 180,
        pinMarkRadius: 3)
}
