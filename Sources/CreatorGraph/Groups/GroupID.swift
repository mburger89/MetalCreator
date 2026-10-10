import Foundation

/// Identity of a group definition (groups spec §4). Saved in the file and in each group node's `NodeSetting.group`.
public struct GroupID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
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

    public static func < (lhs: GroupID, rhs: GroupID) -> Bool { lhs.rawValue.uuidString < rhs.rawValue.uuidString }

    public var description: String { String(rawValue.uuidString.prefix(8)) }
}
