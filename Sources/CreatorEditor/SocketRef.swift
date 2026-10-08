import CreatorGraph

/// One socket on the canvas: an endpoint and which side of its node it is on.
public struct SocketRef: Hashable, Sendable {
    public var endpoint: Endpoint
    public var isInput: Bool

    public init(_ endpoint: Endpoint, isInput: Bool) {
        self.endpoint = endpoint
        self.isInput = isInput
    }
}
