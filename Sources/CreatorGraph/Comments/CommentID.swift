import Foundation

/// Identity of a canvas comment, a sticky note or a comment frame alike (canvas comments spec 2026-10-09 §7): one
/// namespace, so a selection or a hit names a comment without saying which kind it is.
public struct CommentID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
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

    public static func < (lhs: CommentID, rhs: CommentID) -> Bool { lhs.rawValue.uuidString < rhs.rawValue.uuidString }

    public var description: String { String(rawValue.uuidString.prefix(8)) }
}
