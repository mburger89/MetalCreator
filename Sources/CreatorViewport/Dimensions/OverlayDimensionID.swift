/// A dimension's identity across frames and edits: the host's own string ("sketch/…", "feature/…").
public struct OverlayDimensionID: Hashable, Sendable, Comparable {
    public var rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (a: OverlayDimensionID, b: OverlayDimensionID) -> Bool { a.rawValue < b.rawValue }
}
