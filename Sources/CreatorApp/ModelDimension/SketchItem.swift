import CreatorKernel
import CreatorSketch

/// One entity of one Sketch node: what a picked model face or edge comes from (dimensions spec §3.5).
public struct SketchItem: Hashable, Sendable {
    public var node: NodeID
    public var entity: SketchEntityID

    public init(node: NodeID, entity: SketchEntityID) {
        self.node = node
        self.entity = entity
    }
}
