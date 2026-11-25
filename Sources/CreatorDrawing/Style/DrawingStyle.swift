/// Line weights and lettering heights on paper, in sheet millimetres (plan R11). Never written as literals at a call site.
public struct DrawingStyle: Hashable, Sendable {
    public let standard: DrawingStandard
    public let thick: Double
    public let thin: Double
    public let frame: Double
    public let zone: Double
    public let hiddenDash: Double
    public let hiddenGap: Double
    public let titleHeight: Double
    public let viewLabelHeight: Double
    public let fieldLabelHeight: Double
    public let zoneLabelHeight: Double
    private let smallNotes: Double
    private let largeNotes: Double

    public func notesHeight(for size: SheetSize) -> Double { size.isLarge ? largeNotes : smallNotes }

    public static let iso = DrawingStyle(
        standard: .iso, thick: 0.5, thin: 0.25, frame: 0.7, zone: 0.35, hiddenDash: 3, hiddenGap: 1.5, titleHeight: 7,
        viewLabelHeight: 5, fieldLabelHeight: 1.8, zoneLabelHeight: 3.5, smallNotes: 2.5, largeNotes: 3.5)

    public static let asme = DrawingStyle(
        standard: .asme, thick: 0.6, thin: 0.3, frame: 0.7, zone: 0.35, hiddenDash: 3, hiddenGap: 1.5, titleHeight: 6,
        viewLabelHeight: 6, fieldLabelHeight: 1.8, zoneLabelHeight: 3.5, smallNotes: 3, largeNotes: 3)

    public static func of(_ standard: DrawingStandard) -> DrawingStyle { standard == .iso ? iso : asme }
}
