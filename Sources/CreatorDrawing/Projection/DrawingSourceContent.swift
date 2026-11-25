import CreatorKernel

/// What a view's Output holds now, built by the app from its results.
public struct DrawingSourceContent: Sendable {
    public enum State: Sendable {
        case removed
        case failed(String)
        case evaluating
        case ready(solids: [Solid], curves: [Curve], meshCount: Int)
    }

    public var output: NodeID
    public var name: String
    public var state: State

    public init(output: NodeID, name: String, state: State) {
        self.output = output
        self.name = name
        self.state = state
    }
}
