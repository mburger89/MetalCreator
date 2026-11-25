/// A document's drawings: its settings and its sheets in tab order (plan R3).
public struct DrawingDocument: Hashable, Sendable, Codable {
    public var settings: DrawingSettings
    public var sheets: [DrawingSheet]

    public init(settings: DrawingSettings = DrawingSettings(), sheets: [DrawingSheet] = []) {
        self.settings = settings
        self.sheets = sheets
    }

    public var isEmpty: Bool { sheets.isEmpty }

    public func sheet(_ id: SheetID) -> DrawingSheet? { sheets.first { $0.id == id } }
}
