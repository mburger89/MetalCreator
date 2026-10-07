/// Index of a face within one solid's topology table.
public struct FaceID: Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(_ rawValue: Int) { self.rawValue = rawValue }
}
