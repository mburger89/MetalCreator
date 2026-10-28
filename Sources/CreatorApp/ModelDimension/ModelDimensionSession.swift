import CreatorKernel
import CreatorViewport

/// The model dimension tool running (dimensions spec §3.5): the first pick made, the chip text to show, and the level it began on.
public struct ModelDimensionSession: Hashable, Sendable {
    /// The first click's pick, or `nil` before it and after a refused pair.
    public var first: ModelDimensionPick?
    /// The chip text (why the last pair added nothing), cleared by the next click.
    public var message: String?
    /// `editor.levelPath` at the start: showing another level cancels the tool.
    public var level: [NodeID]

    public var pickedCount: Int { first == nil ? 0 : 1 }

    public init(first: ModelDimensionPick? = nil, message: String? = nil, level: [NodeID]) {
        self.first = first
        self.message = message
        self.level = level
    }
}

/// One click of the tool: what was clicked, and the sketch entities the part's face or edge comes from.
public struct ModelDimensionPick: Hashable, Sendable {
    public var target: PickTarget
    public var items: [SketchItem]

    public init(target: PickTarget, items: [SketchItem]) {
        self.target = target
        self.items = items
    }
}
