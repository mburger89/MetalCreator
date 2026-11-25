import CreatorGeometry
import CreatorKernel

/// An Output a view may show: its node, its name and the bounds of what it holds now (`nil` before it has a result).
public struct DrawingSourceOption: Hashable, Sendable {
    public var id: NodeID
    public var name: String
    public var bounds: BoundingBox?

    public init(id: NodeID, name: String, bounds: BoundingBox?) {
        self.id = id
        self.name = name
        self.bounds = bounds
    }
}
