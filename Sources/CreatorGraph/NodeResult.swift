import CreatorSketch

/// A node's state and, on success, its outputs.
public struct NodeResult: Sendable {
    public var state: NodeState
    public var outputs: [SocketName: Value]?
    /// What the node declared while it ran, every iteration's in order. Empty when it failed.
    public var dimensions: [DimensionSpec] = []
    /// The Sketch node's trace of profile segments to sketch entities; nil for every other node and when it failed.
    public var sketchTrace: SketchTrace?

    public init(state: NodeState, outputs: [SocketName: Value]? = nil, dimensions: [DimensionSpec] = [], sketchTrace: SketchTrace? = nil) {
        self.state = state
        self.outputs = outputs
        self.dimensions = dimensions
        self.sketchTrace = sketchTrace
    }

    public var estimatedBytes: Int {
        (outputs ?? [:]).values.reduce(64) { $0 + $1.estimatedBytes } + 64 * (sketchTrace?.regionSources.count ?? 0)
    }
}
