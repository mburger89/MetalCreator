/// An edge's name: the tag sets of its two adjacent faces, as an unordered pair.
public struct EdgeKey: Hashable, Sendable {
    public let first: Set<TopoTag>
    public let second: Set<TopoTag>

    public init(_ a: Set<TopoTag>, _ b: Set<TopoTag>) {
        if Self.canonical(a) <= Self.canonical(b) {
            (first, second) = (a, b)
        } else {
            (first, second) = (b, a)
        }
    }

    public var sortKey: String { "\(Self.canonical(first))|\(Self.canonical(second))" }

    private static func canonical(_ tags: Set<TopoTag>) -> String {
        tags.map(\.sortKey).sorted().joined(separator: "+")
    }
}
