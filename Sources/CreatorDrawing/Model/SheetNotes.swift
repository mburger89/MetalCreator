/// The break of sharp edges a sheet states: both in millimetres, 0 < minimum <= maximum (plan R12).
public struct EdgeBreak: Hashable, Codable, Sendable {
    public var minimum: Double
    public var maximum: Double

    public init(minimum: Double, maximum: Double) {
        self.minimum = minimum
        self.maximum = maximum
    }

    var isValid: Bool { minimum > 0 && minimum <= maximum && maximum.isFinite }
}

/// A sheet's general notes, its edge-break note and its general surface requirement (plan R12).
public struct SheetNotes: Hashable, Codable, Sendable {
    public var lines: [String]
    public var edgeBreak: EdgeBreak?
    public var surface: SurfaceRequirement?

    public init(lines: [String] = [], edgeBreak: EdgeBreak? = nil, surface: SurfaceRequirement? = nil) {
        self.lines = lines
        self.edgeBreak = edgeBreak
        self.surface = surface
    }

    public var isEmpty: Bool { lines.isEmpty && edgeBreak == nil && surface == nil }

    private enum CodingKeys: String, CodingKey { case lines, edgeBreak, surface }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lines = try c.decodeIfPresent([String].self, forKey: .lines) ?? []
        let decodedBreak = try c.decodeIfPresent(EdgeBreak.self, forKey: .edgeBreak)
        edgeBreak = decodedBreak?.isValid == true ? decodedBreak : nil
        surface = try c.decodeIfPresent(SurfaceRequirement.self, forKey: .surface)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !lines.isEmpty { try c.encode(lines, forKey: .lines) }
        try c.encodeIfPresent(edgeBreak, forKey: .edgeBreak)
        try c.encodeIfPresent(surface, forKey: .surface)
    }
}
