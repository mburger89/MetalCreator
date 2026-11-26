import CreatorKernel

/// A document's drawings: its settings and its sheets in tab order (plan R3).
public struct DrawingDocument: Hashable, Sendable, Codable {
    public var settings: DrawingSettings
    public var sheets: [DrawingSheet]
    /// The person's item order, materials and part numbers (DR-5 R5); written only when not empty.
    public var items: [PartItem]
    /// Remembered part names, sorted by part (DR-5 R5); written only when not empty.
    public var partNames: [PartName]

    public init(
        settings: DrawingSettings = DrawingSettings(), sheets: [DrawingSheet] = [], items: [PartItem] = [],
        partNames: [PartName] = []
    ) {
        self.settings = settings
        self.sheets = sheets
        self.items = Self.firstOfEach(items) { $0.part }
        self.partNames = Self.firstOfEach(partNames) { $0.part }.sorted { $0.part < $1.part }
    }

    public var isEmpty: Bool { sheets.isEmpty }

    public func sheet(_ id: SheetID) -> DrawingSheet? { sheets.first { $0.id == id } }

    private enum CodingKeys: String, CodingKey { case settings, sheets, items, partNames }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let settings = try c.decode(DrawingSettings.self, forKey: .settings)
        let sheets = try c.decode([DrawingSheet].self, forKey: .sheets)
        let items = try c.decodeIfPresent([PartItem].self, forKey: .items) ?? []
        let names = try c.decodeIfPresent([PartName].self, forKey: .partNames) ?? []
        self.init(settings: settings, sheets: sheets, items: items, partNames: names)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(settings, forKey: .settings)
        try c.encode(sheets, forKey: .sheets)
        if !items.isEmpty { try c.encode(items, forKey: .items) }
        if !partNames.isEmpty { try c.encode(partNames, forKey: .partNames) }
    }

    private static func firstOfEach<T>(_ values: [T], by part: (T) -> NodeID) -> [T] {
        var seen: Set<NodeID> = []
        return values.filter { seen.insert(part($0)).inserted }
    }
}
