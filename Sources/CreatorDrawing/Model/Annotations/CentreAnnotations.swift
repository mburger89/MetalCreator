public struct CentreMark: Hashable, Codable, Sendable {
    public var anchor: AnchorTarget

    public init(anchor: AnchorTarget) {
        self.anchor = anchor
    }
}

public struct CentreLine: Hashable, Codable, Sendable {
    public var anchor: AnchorTarget

    public init(anchor: AnchorTarget) {
        self.anchor = anchor
    }
}
