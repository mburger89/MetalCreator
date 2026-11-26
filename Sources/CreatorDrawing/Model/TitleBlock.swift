/// The typed fields of a sheet's title block (plan R15). Empty fields are not written.
public struct TitleBlock: Hashable, Sendable, Codable {
    public var owner: String
    public var title: String
    public var drawingNumber: String
    public var revision: String
    public var material: String
    public var drawnBy: String
    public var date: String
    public var density: Double?
    /// The 64 lowercase hex digits of the logo image's hash; its bytes live in the document's `images` table (DR-5 R11).
    public var logo: String?

    public init(
        owner: String = "", title: String = "", drawingNumber: String = "", revision: String = "", material: String = "",
        drawnBy: String = "", date: String = "", density: Double? = nil, logo: String? = nil
    ) {
        self.owner = owner
        self.title = title
        self.drawingNumber = drawingNumber
        self.revision = revision
        self.material = material
        self.drawnBy = drawnBy
        self.date = date
        self.density = density
        self.logo = logo
    }

    private enum CodingKeys: String, CodingKey {
        case owner, title, drawingNumber, revision, material, drawnBy, date, density, logo
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        owner = try c.decodeIfPresent(String.self, forKey: .owner) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        drawingNumber = try c.decodeIfPresent(String.self, forKey: .drawingNumber) ?? ""
        revision = try c.decodeIfPresent(String.self, forKey: .revision) ?? ""
        material = try c.decodeIfPresent(String.self, forKey: .material) ?? ""
        drawnBy = try c.decodeIfPresent(String.self, forKey: .drawnBy) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        density = try c.decodeIfPresent(Double.self, forKey: .density)
        // A damaged value reads nil: exactly 64 lowercase hexadecimal digits, as `ImageHash` has them.
        let text = (try? c.decodeIfPresent(String.self, forKey: .logo)) ?? nil
        logo = text.flatMap { Self.isHash($0) ? $0 : nil }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !owner.isEmpty { try c.encode(owner, forKey: .owner) }
        if !title.isEmpty { try c.encode(title, forKey: .title) }
        if !drawingNumber.isEmpty { try c.encode(drawingNumber, forKey: .drawingNumber) }
        if !revision.isEmpty { try c.encode(revision, forKey: .revision) }
        if !material.isEmpty { try c.encode(material, forKey: .material) }
        if !drawnBy.isEmpty { try c.encode(drawnBy, forKey: .drawnBy) }
        if !date.isEmpty { try c.encode(date, forKey: .date) }
        try c.encodeIfPresent(density, forKey: .density)
        try c.encodeIfPresent(logo, forKey: .logo)
    }

    static func isHash(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
    }
}
