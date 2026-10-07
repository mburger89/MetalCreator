/// A wire from an output socket to an input socket. An input takes at most one link.
public struct Link: Hashable, Sendable, Codable {
    public var from: Endpoint
    public var to: Endpoint

    public init(from: Endpoint, to: Endpoint) {
        self.from = from
        self.to = to
    }
}
