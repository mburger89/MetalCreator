import Foundation

/// Identity of a drawing sheet; shaped like `CommentID`: a bare UUID in the file, ordered by its text.
public struct SheetID: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: SheetID, rhs: SheetID) -> Bool { lhs.rawValue.uuidString < rhs.rawValue.uuidString }

    public var description: String { String(rawValue.uuidString.prefix(8)) }
}
