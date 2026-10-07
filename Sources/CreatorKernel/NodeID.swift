import Foundation

/// Stable identity of a graph node. It lives in the kernel module because topology tags
/// name the node that created each face.
public struct NodeID: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: UUID())
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: NodeID, rhs: NodeID) -> Bool { lhs.rawValue.uuidString < rhs.rawValue.uuidString }

    public var description: String { String(rawValue.uuidString.prefix(8)) }
}
