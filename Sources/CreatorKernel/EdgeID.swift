/// Index of an edge within one solid's topology table.
public struct EdgeID: Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
}
