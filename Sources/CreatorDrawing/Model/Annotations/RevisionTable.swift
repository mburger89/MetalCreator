import CreatorGeometry

/// One row of the revision table; the date is typed by the person, never read from the clock (DR-5 R9).
public struct RevisionRow: Hashable, Codable, Sendable {
    public var letter: String
    public var description: String
    public var date: String
    public var approved: String

    public init(letter: String, description: String = "", date: String = "", approved: String = "") {
        self.letter = letter
        self.description = description
        self.date = date
        self.approved = approved
    }

    private enum CodingKeys: String, CodingKey { case letter, description, date, approved }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        letter = try c.decodeIfPresent(String.self, forKey: .letter) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        approved = try c.decodeIfPresent(String.self, forKey: .approved) ?? ""
    }
}

/// The sheet's revision table (DR-5 R9); `topRight` is nil while it stands in the frame's inside top-right corner.
public struct RevisionTable: Hashable, Codable, Sendable {
    public var rows: [RevisionRow]
    public var topRight: Vector2?

    public init(rows: [RevisionRow] = [], topRight: Vector2? = nil) {
        self.rows = rows
        self.topRight = topRight
    }

    private enum CodingKeys: String, CodingKey { case rows, topRight }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = try c.decodeIfPresent([RevisionRow].self, forKey: .rows) ?? []
        topRight = try c.decodeIfPresent(Vector2.self, forKey: .topRight)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !rows.isEmpty { try c.encode(rows, forKey: .rows) }
        try c.encodeIfPresent(topRight, forKey: .topRight)
    }
}
