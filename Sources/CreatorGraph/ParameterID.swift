import Foundation

/// Identity of a document-level graph parameter.
public struct ParameterID: Hashable, Sendable, Codable, Comparable {
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

    public static func < (lhs: ParameterID, rhs: ParameterID) -> Bool { lhs.rawValue.uuidString < rhs.rawValue.uuidString }
}
