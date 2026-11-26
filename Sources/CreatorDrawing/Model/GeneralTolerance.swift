import CreatorGeometry

/// ISO 2768-1's tolerance class for lengths, angles and chamfers: fine, medium, coarse, very coarse.
public enum ISO2768Class: String, Codable, Sendable, CaseIterable {
    case f, m, c, v
}

// ISO 2768-2 names its classes with capital letters.
// swiftlint:disable identifier_name
/// ISO 2768-2's geometric tolerance class.
public enum ISO2768GeometricClass: String, Codable, Sendable, CaseIterable {
    case H, K, L
}
// swiftlint:enable identifier_name

/// One row of an ASME general-tolerance table: the tolerance for sizes typed with `places` decimals. `text` is the
/// magnitude as typed, with no sign ("0.5", ".010").
public struct ASMEToleranceRow: Hashable, Codable, Sendable {
    public var places: Int
    public var text: String

    public init(places: Int, text: String) {
        self.places = places
        self.text = text
    }
}

public struct ASMEToleranceTable: Hashable, Codable, Sendable {
    public var unit: LengthUnit
    public var rows: [ASMEToleranceRow]

    public init(unit: LengthUnit, rows: [ASMEToleranceRow]) {
        self.unit = unit
        self.rows = rows
    }

    static let millimetres = ASMEToleranceTable(
        unit: .millimetres,
        rows: [
            ASMEToleranceRow(places: 0, text: "0.5"), ASMEToleranceRow(places: 1, text: "0.1"),
            ASMEToleranceRow(places: 2, text: "0.05"),
        ])
    static let inches = ASMEToleranceTable(
        unit: .inches,
        rows: [
            ASMEToleranceRow(places: 1, text: ".03"), ASMEToleranceRow(places: 2, text: ".010"),
            ASMEToleranceRow(places: 3, text: ".005"),
        ])
}

/// The tolerance a drawing applies to every size that has none of its own (plan R10).
public enum GeneralTolerance: Hashable, Sendable {
    case iso2768(ISO2768Class, ISO2768GeometricClass?)
    case asme(ASMEToleranceTable)
    case text(String)

    /// The title block's wording: "ISO 2768-mK", "±0.5, ±0.1, ±0.05 mm", or a legacy text as typed.
    public var text: String {
        switch self {
        case .iso2768(let size, let geometric):
            "ISO 2768-\(size.rawValue)\(geometric?.rawValue ?? "")"
        case .asme(let table):
            table.rows.map { "±" + $0.text }.joined(separator: ", ") + " " + table.unit.symbol
        case .text(let text):
            text
        }
    }

    /// True only for a blank `.text`.
    public var isEmpty: Bool {
        if case .text(let text) = self { return text.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\n" } }
        return false
    }

    public static func standardDefault(for standard: DrawingStandard, inches: Bool) -> GeneralTolerance {
        switch standard {
        case .iso: .iso2768(.m, .K)
        case .asme: .asme(inches ? .inches : .millimetres)
        }
    }

    /// Reads a format-17 string (plan R10): ISO 2768's class letters, either ASME default, else the text as typed.
    public init(legacy string: String, standard: DrawingStandard) {
        let prefix = "ISO 2768-"
        if string.hasPrefix(prefix) {
            let letters = Array(string.dropFirst(prefix.count))
            if let first = letters.first, let size = ISO2768Class(rawValue: String(first)) {
                if letters.count == 1 {
                    self = .iso2768(size, nil)
                    return
                }
                if letters.count == 2, let geometric = ISO2768GeometricClass(rawValue: String(letters[1])) {
                    self = .iso2768(size, geometric)
                    return
                }
            }
        }
        if string == GeneralTolerance.asme(.millimetres).text {
            self = .asme(.millimetres)
        } else if string == GeneralTolerance.asme(.inches).text {
            self = .asme(.inches)
        } else {
            self = .text(string)
        }
    }
}

extension GeneralTolerance: Codable {
    private enum CodingKeys: String, CodingKey { case type, size, geometric, table, text }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "iso2768":
            self = .iso2768(
                try c.decode(ISO2768Class.self, forKey: .size), try c.decodeIfPresent(ISO2768GeometricClass.self, forKey: .geometric))
        case "asme":
            self = .asme(try c.decode(ASMEToleranceTable.self, forKey: .table))
        default:
            self = .text(try c.decodeIfPresent(String.self, forKey: .text) ?? "")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .iso2768(let size, let geometric):
            try c.encode("iso2768", forKey: .type)
            try c.encode(size, forKey: .size)
            try c.encodeIfPresent(geometric, forKey: .geometric)
        case .asme(let table):
            try c.encode("asme", forKey: .type)
            try c.encode(table, forKey: .table)
        case .text(let text):
            try c.encode("text", forKey: .type)
            try c.encode(text, forKey: .text)
        }
    }
}
